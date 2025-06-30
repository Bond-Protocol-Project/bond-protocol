// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IBondBridge} from "../interfaces/IBondBridge.sol";
import {IBondPool} from "../interfaces/IBondPool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract BondProtocol is Ownable, ReentrancyGuard {
    IBondBridge bridge;
    IBondPool pool;

    // mappings
    mapping(address user => uint64) public intentNonce;
    mapping(uint64 => uint64) public chainIdToChainSelector;
    mapping(uint64 => uint64) public chainSelectorToChainId;
    mapping(bytes32 intentId => DataTypes.IntentData) private intents;
    mapping(bytes32 intentId => bool) public intentSettled;
    mapping(bytes32 intentId => mapping(uint64 chainId => bool)) srcExecuted;
    mapping(bytes32 => bool) intentExecuted;
    mapping(bytes32 => uint8) srcExecutionCount;

    // hardcoded, but in the future there will be a mapping for each chain
    uint256 baseProtocolFee = 2e16;

    // protocol circut breaker switch
    bool public emergencyStop = false;

    AggregatorV3Interface internal linkUsdAggregator;

    // events
    event IntentExecutionRequested(bytes32 intentId, address account);
    event IntentSubmitted(
        bytes32 indexed intentId,
        address indexed sender,
        uint256 timestamp
    );

    // errors
    error InvalidIntent();
    error InvalidIntentNonce();
    error InvalidIntentSender();
    error InvalidExecutionChain();
    error InvalidIntentExpiryTime();
    error IntentAlreadySubmitted();
    error IntentExpired();
    error InvalidIntentSrcLength();
    error InvalidInitChain();
    error InvalidDstChain();
    error InvalidPoolId();
    error UnsupportedSrcChain();
    error InsufficientFunds();
    error InsufficientAllowance();
    error DuplicateSourceChain();
    error ZeroAddressNotAllowed();
    error ZeroAmountNotAllowed();
    error InvalidChain();
    error TokenTransferError();
    error ProtocolPaused();
    error OnlyBridge();

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    modifier onlyBridge() {
        if (msg.sender != address(bridge)) revert OnlyBridge();
        _;
    }

    modifier whenNotPaused() {
        if (emergencyStop) revert ProtocolPaused();
        _;
    }

    /**
     * @notice This function sends the intent message to every required chain
     * @dev This is the entry function to send an intent request
     * @param _intentData the intent bytes to be executed
     */
    function submitIntent(
        bytes memory _intentData
    ) external nonReentrant whenNotPaused {
        // decode the intent
        DataTypes.IntentData memory _intent = abi.decode(
            _intentData,
            (DataTypes.IntentData)
        );

        // ensure the intent nonce is valid to prevent replay attack
        if (_intent.initChainSenderNonce != intentNonce[msg.sender])
            revert InvalidIntentNonce();

        //ensure the intent sender is the contract caller
        if (_intent.sender != msg.sender) revert InvalidIntentSender();

        //intent source list must not be more than 3
        if (_intent.srcChainIds.length > 3) revert InvalidIntentSrcLength();

        uint256 _currentBlockTimestamp = block.timestamp;

        // users pass the expiry time themselves so ensure the intent expiry time is between 30 minutes and 2 hours
        if (
            _intent.expires < _currentBlockTimestamp + (60 * 30) ||
            _intent.expires > _currentBlockTimestamp + (60 * 60 * 2)
        ) revert InvalidIntentExpiryTime();

        // get the pool data
        // the token address to be interacted with can be retreived from the pool data
        // the poolId is consistent accross chain so this way we can keep track of
        // token addresses across chains
        DataTypes.PoolData memory _poolData = pool.getPool(_intent.poolId);
        if (_poolData.underlyingToken == address(0)) revert InvalidPoolId();

        // calculate the intent Id from the intent bytes
        bytes32 _intentId = getIntentId(_intentData);

        //make sure intent hasn't already been submited
        if (intents[_intentId].initChainId != 0)
            revert IntentAlreadySubmitted();

        uint64 _getChainId = getChainId();

        // init chain in intent being submited must match the chain it was called from (i.e current chain)
        if (_intent.initChainId != _getChainId) revert InvalidInitChain();

        // the intent source chain list's length must match the length of the intent source amount
        // there positions in the array defineds the token amount each source chain is required to provide
        if (_intent.srcChainIds.length != _intent.srcAmounts.length)
            revert InvalidIntentSrcLength();

        uint64 _dstChainSelector = chainIdToChainSelector[_intent.dstChainId];

        // ensure destination chain is valid and supported
        if (_dstChainSelector == 0 && _intent.dstChainId != _getChainId) revert InvalidDstChain();

        // store the intent to storage
        intents[_intentId] = _intent;

        uint256 _srcIdLength = _intent.srcChainIds.length;

        // we start with _feesInLink = baseProtocolFee  * _srcIdLength which will contain fee to cover destination chain fee and
        // compensation paid to solvers
        // other intent src fees will be added accordingly
        uint256 _feesInLink = baseProtocolFee * _srcIdLength;

        // prepare interface instance of the underlying token
        IERC20 _token = IERC20(_poolData.underlyingToken);

        // encode DataTypes.BridgeData
        bytes memory _bridgeData = abi.encode(
            DataTypes.BridgeData(_intentId, _intentData)
        );

        // encode DataTypes.BridgeMsgData set isBatch to false (not a batched message)
        bytes memory _bridgeMsgData = abi.encode(
            DataTypes.BridgeMsgData(false, _bridgeData)
        );

        // loop through intent source chains and process accordingly
        for (uint8 i = 0; i < _srcIdLength; ) {
            // ensure source chain is valid by checking if it has been registered as a valid chain
            if (chainIdToChainSelector[_intent.srcChainIds[i]] == 0 && _getChainId != _intent.srcChainIds[i])
                revert UnsupportedSrcChain();

            // Validate no zero amounts
            if (_intent.srcAmounts[i] == 0) revert ZeroAmountNotAllowed();

            // Validate no duplicate source chains
            for (uint8 j = i + 1; j < _srcIdLength; j++) {
                if (_intent.srcChainIds[i] == _intent.srcChainIds[j])
                    revert DuplicateSourceChain();
            }

            //if the current chain is among the intent source chain list in the iteration
            if (_getChainId == _intent.srcChainIds[i]) {
                // and if the current chain is not the destination chain
                // it means the current chain has to send tokens to the destination chain
                if (_getChainId != _intent.dstChainId) {
                    //  make sure the user has enough token and allowance
                    uint256 _srcAmount = _intent.srcAmounts[i];
                    if (_token.balanceOf(msg.sender) < _srcAmount)
                        revert InsufficientFunds();
                    if (
                        _token.allowance(msg.sender, address(this)) < _srcAmount
                    ) revert InsufficientAllowance();

                    _token.transferFrom(
                        msg.sender,
                        address(bridge),
                        _srcAmount
                    );

                    // call the internal function to send token to destination chain
                    (uint256 _bridgeFees, ) = _bridgeIntentMessage(
                        _dstChainSelector,
                        _bridgeMsgData,
                        _poolData.underlyingToken,
                        _srcAmount,
                        400000
                    );
                    // we multiply bridge fee by 2 for now to cover other fees
                    _feesInLink += _bridgeFees * 2;
                } else {
                    // if the current chain is the destination chain and it is also in the intent source chain list
                    // just mark the chain as executed. we are telling the protocol that the current chain has done its part
                    // since the curren chain is the destination chain, it dosent need to bridge funds to itself even if it is
                    // listed in the intent source chain
                    if (_srcIdLength == 1) revert InvalidIntentSrcLength();
                    srcExecutionCount[_intentId]++;
                    srcExecuted[_intentId][_getChainId] = true;
                }
            } else {
                // but if the current chain is not among the source chain list in the iteration, it means it is meant
                // to send a bridge message to the chain. this message will signal the receiving chain to send its token to
                // the destination chain
                (uint256 _bridgeFees, ) = _bridgeIntentMessage(
                    chainIdToChainSelector[_intent.srcChainIds[i]],
                    _bridgeMsgData,
                    address(0),
                    0,
                    400000
                );
                // we multiply bridge fee by 2 for now just to cover the second transaction that goes to destination chain
                _feesInLink += _bridgeFees * 2;
            }
            unchecked {
                ++i;
            }
        }

        // get fees in selected token using chainlink pricefeed
        (
            ,
            /* uint80 roundId */ int256 answer /*uint256 startedAt*/ /*uint256 updatedAt*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = linkUsdAggregator.latestRoundData();
        uint256 _fees = convertLinkToStable(
            _feesInLink,
            answer,
            IERC20(_poolData.underlyingToken).decimals()
        );

        // make sure there is still enough balance to pay for fees
        if (_token.balanceOf(msg.sender) < _fees) revert InsufficientFunds();
        if (_token.allowance(msg.sender, address(this)) < _fees)
            revert InsufficientAllowance();
        _token.transferFrom(msg.sender, address(this), _fees);

        intentNonce[msg.sender]++;

        emit IntentSubmitted(_intentId, msg.sender, _currentBlockTimestamp);
    }

    /**
     * @dev helper function to send bridge message
     * @param _chainSelector destination chain selector
     * @param _bridgeMsgData the encoded bridge data
     * @param token the token to send
     * @param _amount amount to be sent
     * @param _gasLimit gas limit for ccip
     * @return _fees
     * @return _messageId
     */
    function _bridgeIntentMessage(
        uint64 _chainSelector,
        bytes memory _bridgeMsgData,
        address token,
        uint256 _amount,
        uint64 _gasLimit
    ) internal returns (uint256 _fees, bytes32 _messageId) {
        // bridge intent message to that chain
        return
            bridge.sendMessage(
                _chainSelector,
                _bridgeMsgData,
                token,
                _amount,
                _gasLimit
            );
    }

    /**
     * @notice This function just simulates the submitIntent function above and get required fees to process the intent passed
     * @dev simulate submiting intent and get fees
     * @param _intentData the intent bytes data
     */
    function getFees(bytes memory _intentData) external view returns (uint256) {
        DataTypes.IntentData memory _intent = abi.decode(
            _intentData,
            (DataTypes.IntentData)
        );
        if (_intent.initChainSenderNonce != intentNonce[msg.sender])
            revert InvalidIntentNonce();
        if (_intent.sender != msg.sender) revert InvalidIntentSender();

        DataTypes.PoolData memory _poolData = pool.getPool(_intent.poolId);
        if (_poolData.underlyingToken == address(0)) revert InvalidPoolId();

        bytes32 _intentId = getIntentId(_intentData);

        if (intents[_intentId].initChainId != 0)
            revert IntentAlreadySubmitted();

        uint64 _getChainId = getChainId();

        // init chain in intent being submited must match the chain it was called (i.e current chain)
        if (_intent.initChainId != _getChainId) revert InvalidInitChain();

        if (_intent.srcChainIds.length != _intent.srcAmounts.length)
            revert InvalidIntentSrcLength();

        if (chainIdToChainSelector[_intent.dstChainId] == 0 && _intent.dstChainId != _getChainId)
            revert InvalidDstChain();

        uint256 _srcIdLength = _intent.srcChainIds.length;

        // we start with _feesInLink = baseProtocolFee which will contain fee to cover destination chain fee and other fees
        // we start with _feesInLink = baseProtocolFee  * _srcIdLength which will contain fee to cover destination chain fee and
        // compensation paid to solvers
        // other intent src fees will be added accordingly
        uint256 _feesInLink = baseProtocolFee * _srcIdLength;

        bytes memory _bridgeMsgData = abi.encode(
            DataTypes.BridgeData(_intentId, _intentData)
        );

        for (uint8 i = 0; i < _srcIdLength; ) {
            // ensure source chain is valid by checking if it has been registered as a valid chain
            if (chainIdToChainSelector[_intent.srcChainIds[i]] == 0 && _getChainId != _intent.srcChainIds[i])
                revert UnsupportedSrcChain();

            if (_getChainId == _intent.srcChainIds[i]) {
                if (_getChainId != _intent.dstChainId) {
                    uint256 _srcAmount = _intent.srcAmounts[i];

                    uint256 _bridgeFees = bridge.getFees(
                        chainIdToChainSelector[_intent.dstChainId],
                        _bridgeMsgData,
                        _poolData.underlyingToken,
                        _srcAmount,
                        400000
                    );
                    // we multiply bridge fee by 2 for now to cover other fees
                    _feesInLink += _bridgeFees * 2;
                }
            } else {
                uint256 _bridgeFees = bridge.getFees(
                    chainIdToChainSelector[_intent.srcChainIds[i]],
                    _bridgeMsgData,
                    address(0),
                    0,
                    400000
                );
                // we multiply bridge fee by 2 for now just to cover the second transaction that goes to destination chain
                _feesInLink += _bridgeFees * 2;
            }
            unchecked {
                ++i;
            }
        }

        // get fees in selected token using chainlink pricefeed
        (
            ,
            /* uint80 roundId */ int256 answer /*uint256 startedAt*/ /*uint256 updatedAt*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = linkUsdAggregator.latestRoundData();
        uint256 _fees = convertLinkToStable(
            _feesInLink,
            answer,
            IERC20(_poolData.underlyingToken).decimals()
        );

        return _fees;
    }

    /**
     * @notice This function emits event that notifies solvers to build next required userop
     * @dev This function is called by _ccipReceive from the bridge contract, data is to be consumed by the protocol
     * @param _data this is the CCIP bridged message (DataTypes.BridgeData).
     * @param srcBridgedChainSelector The source chain selector from CCIP
     */
    function confirmIncomingIntent(
        bytes memory _data,
        uint64 srcBridgedChainSelector
    ) external onlyBridge whenNotPaused nonReentrant {
        uint64 _getChainId = getChainId();

        // temporary intent data storage
        DataTypes.IntentData memory _intent = abi.decode(
            _data,
            (DataTypes.IntentData)
        );

        bytes32 _intentId = getIntentId(_data);

        // store intent in storage if it does not exist
        if (intents[_intentId].sender == address(0)) {
            intents[_intentId] = _intent;
        } else {
            // verify that incoming intent belong to intent sender
            if (_intent.sender != intents[_intentId].sender)
                revert InvalidIntent();
        }

        // convert the chainlink chainselector to real blockchain ID
        uint64 srcBridgedChainId = chainSelectorToChainId[
            srcBridgedChainSelector
        ];

        // get underlying token
        DataTypes.PoolData memory _poolData = getPool(_intent.poolId);

        // if current chain is the intent destination chain
        if (_intent.dstChainId == _getChainId) {
            bool srcBridgedChainIsInIntentSrcChains;
            bool currentDestChainIsInIntentSrc;
            // loop through to know if current chain is present in intent source chains list
            for (uint8 i = 0; i < _intent.srcChainIds.length; ) {
                // if source ccip chain is present in intent source chains list
                if (_intent.srcChainIds[i] == srcBridgedChainId) {
                    srcBridgedChainIsInIntentSrcChains = true;
                    // if current chain is the destination chain
                    // and src chain from ccip is in the list of source chains in intent
                    // then it means tokens was sent from that source chain to this chain.
                    // send the token to sender address

                    // mark the ccip src chain as executed
                    // this means the src chain has fufilled its obligation to fund destination chain
                    srcExecutionCount[_intentId]++;
                    srcExecuted[_intentId][_intent.srcChainIds[i]] = true;

                    IERC20(_poolData.underlyingToken).transfer(
                        _intent.sender,
                        _intent.srcAmounts[i]
                    );
                }
                // if the current chain which is the destination chain is also in the intent source chain list
                if (_intent.srcChainIds[i] == _getChainId) {
                    currentDestChainIsInIntentSrc = true;
                }

                unchecked {
                    ++i;
                }
            }
            // if the src chain from ccip is not in intent src chain list then it means
            // bridged message is from init chain and no funds was sent
            // also it means current chain is in the intent src list too, hence the init chain sending the message
            // even if it is the dest chain
            if (srcBridgedChainIsInIntentSrcChains == false) {
                // verify that the current chain is in the intent source chain list if
                // the ccip src chain is not in the intent src list.
                // i.e Just making sure the message was sent because the destination chain is in the intent src list
                if (!currentDestChainIsInIntentSrc) revert InvalidChain();
                // since the call was from the init chain and current chain is destination chain
                // current chain is also in the src list, then mark the current chain as executed
                // because the destination chain will only execute execute the
                // dest data when all source chain has been marked as executed
                srcExecutionCount[_intentId]++;
                srcExecuted[_intentId][_getChainId] = true;
            }

            // check if executions from src is complete
            // first check if the count is equal to the length of the src chains length
            // we use the count first to save gas, if the count is complete then we loop through the
            // srcExecuted to verify that all chains have settled the destination chain
            if (srcExecutionCount[_intentId] >= _intent.srcChainIds.length) {
                bool allSrcExecuted = true;
                for (uint8 i = 0; i < _intent.srcChainIds.length; ) {
                    if (
                        srcExecuted[_intentId][_intent.srcChainIds[i]] == false
                    ) {
                        allSrcExecuted = false;
                    }
                    unchecked {
                        ++i;
                    }
                }
                // if all src chains have indeed sent funds (i.e executed) to the destination chain then
                // emit event so solvers can build userop to settle destination chain
                if (allSrcExecuted) {
                    emit IntentExecutionRequested(_intentId, _intent.sender);
                }
            }
        } else {
            // if current chain is not the intent destination chain
            // then it is in the intent src chain list
            // emit event so solvers can build userop to settle destination chain
            emit IntentExecutionRequested(_intentId, _intent.sender);
        }
    }

    function isIntentDstChainFullySettled(
        bytes32 _intentId
    ) external view returns (bool) {
        DataTypes.IntentData memory _intent = intents[_intentId];
        if (_intent.sender == address(0)) revert InvalidIntent();

        bool isSrcExecutionComplete = true;

        if (srcExecutionCount[_intentId] >= _intent.srcChainIds.length) {
            for (uint8 i = 0; i < _intent.srcChainIds.length; ) {
                if (srcExecuted[_intentId][_intent.srcChainIds[i]] == false) {
                    isSrcExecutionComplete = false;
                }
                unchecked {
                    ++i;
                }
            }
        } else {
            isSrcExecutionComplete = false;
        }

        return isSrcExecutionComplete;
    }

    /**
     * @dev This function is called by account to settle intent destination chain (i.e send tokens to destination chain)
     * @param _intentId intent Id to interact with
     * @param _executor this is the solver that built the userOp
     */
    function settleIntentDestChain(
        bytes32 _intentId,
        address _executor
    ) external whenNotPaused nonReentrant {
        DataTypes.IntentData memory _intent = intents[_intentId];

        // validate intentId
        if (_intent.sender != msg.sender) revert InvalidIntentSender();
        // make sure the intentId is still active
        if (intentExecuted[_intentId] != false) revert IntentAlreadySubmitted();
        if (_intent.expires < block.timestamp) revert IntentExpired();

        // get amount to send
        uint256 _intentSrcAmount = 0;
        for (uint8 i = 0; i < _intent.srcChainIds.length; ) {
            if (_intent.srcChainIds[i] == block.chainid) {
                _intentSrcAmount = _intent.srcAmounts[i];
            }
            unchecked {
                ++i;
            }
        }
        if (_intentSrcAmount == 0) revert InvalidChain();

        // get pool data so we can retreive token
        DataTypes.PoolData memory _poolData = getPool(_intent.poolId);

        // make sure protocol have enough allowance
        if (
            IERC20(_poolData.underlyingToken).allowance(
                msg.sender,
                address(this)
            ) < _intentSrcAmount
        ) revert InsufficientAllowance();

        if (
            IERC20(_poolData.underlyingToken).balanceOf(msg.sender) <
            _intentSrcAmount
        ) revert InsufficientFunds();

        IERC20(_poolData.underlyingToken).transferFrom(
            msg.sender,
            address(bridge),
            _intentSrcAmount
        );

        bytes memory _intentData = abi.encode(_intent);

        // encode DataTypes.BridgeData
        bytes memory _bridgeData = abi.encode(
            DataTypes.BridgeData(_intentId, _intentData)
        );

        // encode DataTypes.BridgeMsgData set isBatch to false (not a batched message)
        bytes memory _bridgeMsgData = abi.encode(
            DataTypes.BridgeMsgData(false, _bridgeData)
        );

        // call the internal function to send token to destination chain
        _bridgeIntentMessage(
            chainIdToChainSelector[_intent.dstChainId],
            _bridgeMsgData,
            _poolData.underlyingToken,
            _intentSrcAmount,
            400000
        );

        // for now we will just set the intentExecuted to true, later executor will be incentivised
        intentExecuted[_intentId] = true;
    }

    /**
     * @dev This function is called by account to settle the solver that build the userOp to run the intent destination datas
     * @param _intentId intent Id to interact with
     * @param _executor this is the solver that built the userOp
     */
    function settleIntentDestExecutor(
        bytes32 _intentId,
        address _executor
    ) external whenNotPaused nonReentrant {
        // validate intentId
        if (intents[_intentId].sender != msg.sender)
            revert InvalidIntentSender();
        // make sure the intentId is still active
        if (intentExecuted[_intentId] != false) revert IntentAlreadySubmitted();
        if(intents[_intentId].expires < block.timestamp) revert IntentExpired();
        // for now we will just set the intentExecuted to true, later executor will be incentivised
        intentExecuted[_intentId] = true;
    }

    /**
     * @dev helper function to check if intent has been used on this chain
     * @param _intentId Intent id to check
     */
    function isIntentExecuted(bytes32 _intentId) external view returns (bool) {
        return intentExecuted[_intentId];
    }

    /**
     * @dev helper function to check if intent is valid
     * @param _intentId Intent id to check
     */
    function isIntentValid(
        bytes32 _intentId,
        address sender_
    ) external view returns (bool) {
        if (
            intentExecuted[_intentId] == false &&
            intents[_intentId].expires > block.timestamp &&
            intents[_intentId].sender == sender_
        ) {
            return true;
        }
        return false;
    }

    /**
     * @notice Allows a user to supply tokens to the pool and receive supply tokens in return.
     * @param _poolId Pool ID.
     * @param _amount Amount of tokens to supply.
     */
    function supply(uint64 _poolId, uint256 _amount) external nonReentrant {
        DataTypes.PoolData memory _pool = pool.getPool(_poolId);
        if (IERC20(_pool.underlyingToken).balanceOf(msg.sender) < _amount)
            revert InsufficientFunds();
        if (
            IERC20(_pool.underlyingToken).allowance(msg.sender, address(this)) <
            _amount
        ) revert InsufficientAllowance();
        IERC20(_pool.underlyingToken).transferFrom(
            msg.sender,
            address(pool),
            _amount
        );
        pool.supply(_poolId, _amount, msg.sender);
    }

    /**
     * @notice Allows a user to withdraw tokens from the pool.
     * @param _poolId Pool ID.
     * @param _amount Amount of tokens to withdraw.
     */
    function withdrawSupply(uint64 _poolId, uint256 _amount) external nonReentrant {
        DataTypes.PoolData memory _pool = pool.getPool(_poolId);
        if (IERC20(_pool.supplyToken).balanceOf(msg.sender) < _amount)
            revert InsufficientFunds();
        pool.withdraw(_poolId, _amount, msg.sender);
    }

    /**
     * @notice Creates a new pool with the specified parameters.
     * @param _poolId Pool ID.
     * @param _underlyingToken Address of the underlying token.
     * @param _supplyTokenName Name of the supply token.
     * @param _supplyTokenSymbol Symbol of the supply token.
     */
    function createPool(
        uint64 _poolId,
        address _underlyingToken,
        string memory _supplyTokenName,
        string memory _supplyTokenSymbol
    ) external onlyOwner nonReentrant returns (DataTypes.PoolData memory) {
        return
            pool.createPool(
                _poolId,
                _underlyingToken,
                _supplyTokenName,
                _supplyTokenSymbol
            );
    }

    /**
     * @notice Retrieves pool data for a given pool ID.
     * @param _poolId Pool ID.
     * @return Pool data structure.
     */
    function getPool(
        uint64 _poolId
    ) public view returns (DataTypes.PoolData memory) {
        return pool.getPool(_poolId);
    }

    /**
     * @notice Handles incentives to pool.
     * @param _poolId pool ID to handle.
     * @param _fee Fee associated with the transaction.
     */
    function handlePoolIncentive(uint64 _poolId, uint256 _fee) internal {
        pool.handlePoolIncentive(_poolId, _fee);
    }

    /**
     * @dev Retreive current intent nonce for sender
     * @param _sender the sender to retreive intent nonce for
     */
    function getNonce(address _sender) external view returns (uint64) {
        return intentNonce[_sender];
    }

    /**
     * @dev retreive intent data
     * @param _intentId intent Id to be retreived
     */
    function getIntent(
        bytes32 _intentId
    ) external view returns (DataTypes.IntentData memory) {
        return intents[_intentId];
    }

    /**
     * @dev Calcuate intent id from intent bytes
     * @param _intent the intent bytes
     */
    function getIntentId(bytes memory _intent) internal pure returns (bytes32) {
        return keccak256(_intent);
    }

    /**
     * @dev helper function to get the blockchain Id
     */
    function getChainId() internal view returns (uint64) {
        uint256 chainId = block.chainid;
        return uint64(chainId);
    }

    /**
     * @dev This function pauses or starts protocol
     * @param _value value of protocol switch
     */
    function emergencyPause(bool _value) external onlyOwner {
        emergencyStop = _value;
    }

    /**
     * @dev This function maps ccip chain selector to blockchain id
     * @param _chainId blockchain id
     * @param _chainSelector ccip chain selector
     */
    function peerChainIdandChainSelector(
        uint64 _chainId,
        uint64 _chainSelector
    ) external onlyOwner {
        chainIdToChainSelector[_chainId] = _chainSelector;
        chainSelectorToChainId[_chainSelector] = _chainId;
    }

    function convertLinkToStable(
        uint256 feeInLink, // 18 decimals (LINK)
        int256 linkUsdPrice, // 8 decimals (Chainlink LINK/USD feed)
        uint8 stableTokenDecimals // e.g., 6 for USDC, 18 for DAI
    ) public view returns (uint256) {
        require(linkUsdPrice > 0, "Invalid price");

        // Total decimals after multiplying feeInLink and linkUsdPrice
        uint256 totalDecimals = 18 + linkUsdAggregator.decimals();

        // Amount to divide by to normalize to target stablecoin decimals
        uint256 decimalAdjustment = totalDecimals - stableTokenDecimals;

        return (feeInLink * uint256(linkUsdPrice)) / (10 ** decimalAdjustment);
    }

    /**
     * @dev Admin only function to initailize protocol bridge address
     * @param bridge_ bridge address
     */
    function initializeBridge(address bridge_) external nonReentrant onlyOwner {
        bridge = IBondBridge(bridge_);
    }

    /**
     * @dev Admin only function to initailize protocol pool address
     * @param pool_ pool address
     */
    function initializePool(address pool_) external nonReentrant onlyOwner {
        pool = IBondPool(pool_);
    }

    function initializeLinkUsdAggregator(
        address _linkUsdAggregatorAddress
    ) external nonReentrant onlyOwner {
        linkUsdAggregator = AggregatorV3Interface(_linkUsdAggregatorAddress);
    }
}
