// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@account-abstraction/contracts/legacy/v06/IEntryPoint06.sol";
import "@account-abstraction/contracts/legacy/v06/IAccount06.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IBondProtocol} from "../interfaces/IBondProtocol.sol";
import {IBondPool} from "../interfaces/IBondPool.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Compatibility} from "../abstract/Compatibility.sol";
import {IERC20} from "../interfaces/IERC20.sol";

// The implementation contract for the smart account
contract BondSmartAccount is
    IAccount06,
    Compatibility,
    UUPSUpgradeable,
    Initializable
{
    address public owner;
    IEntryPoint public immutable entryPoint;
    IBondProtocol public protocol;

    uint256 private constant SIG_VALIDATION_FAILED = 1;
    uint256 private constant SIG_VALIDATION_SUCCESS = 0;

    bytes4 private constant EXECUTE_INTENT_SELECTOR =
        bytes4(keccak256("executeIntent(bytes32,address)"));

    event BondAccountInitialized(
        IEntryPoint indexed entryPoint,
        address indexed owner,
        address indexed protocol
    );
    event IntentExecuted(bytes32 indexed intentId, address indexed executor);

    error OnlyOwner();
    error OnlyEntryPoint();
    error TransactionExecutionFailed();
    error InvalidIntentSender();
    error IntentSrcNotSettled();
    error IntentExpired();
    error InvalidIntent();
    error InvalidIntentExecuted();
    error InvalidExecutionChain();
    error FailedToSettleExecutor();
    error InsufficientFunds();

    // EntryPoint is set once during implementation deployment
    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
        _disableInitializers();
    }

    function initialize(address anOwner, address _protocol) public virtual initializer {
        _initialize(anOwner, _protocol);
    }

    function _initialize(address anOwner, address _protocol) internal virtual {
        require(anOwner != address(0), "Invalid owner address");
        require(_protocol != address(0), "Invalid protocol address");
        
        owner = anOwner;
        protocol = IBondProtocol(_protocol);
        emit BondAccountInitialized(entryPoint, owner, _protocol);
    }

    modifier onlyOwner() {
        if (msg.sender != owner && msg.sender != address(this))
            revert OnlyOwner();
        _;
    }

    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert OnlyEntryPoint();
        _;
    }

    // Execute function for direct calls from owner
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyEntryPoint returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) revert TransactionExecutionFailed();

        return result;
    }

    // Batch execute function for gas efficiency
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external onlyEntryPoint returns (bytes[] memory results) {
        require(
            targets.length == values.length && targets.length == datas.length,
            "Array length mismatch"
        );

        results = new bytes[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{
                value: values[i]
            }(datas[i]);
            require(success, "Transaction execution failed");
            results[i] = result;
        }
    }

    // Execute function for direct calls from owner
    function executeIntent(
        bytes32 _intentId,
        address _executor
    ) external onlyEntryPoint returns (bytes[] memory results) {
        DataTypes.IntentData memory _intent = protocol.getIntent(_intentId);
        // make sure the acoount is the owner of intent
        if (_intent.sender != address(this)) revert InvalidIntentSender();
        // check if intent is expired
        if (_intent.expires < block.timestamp) revert IntentExpired();
        // check if current chain is the intent destination chain
        if (_intent.dstChainId == block.chainid) {
            bool dstChainSettled = protocol.isIntentDstChainFullySettled(
                _intentId
            );
            if (!dstChainSettled) revert IntentSrcNotSettled();
            // if infact the destination chain has been settled
            // check if intent has been used to execute a transaction
            if (protocol.isIntentExecuted(_intentId))
                revert InvalidIntentExecuted();
            // decode intent destination datas
            DataTypes.IntentDstData[] memory _dstDatas = abi.decode(
                _intent.dstDatas,
                (DataTypes.IntentDstData[])
            );
            // declare results length
            results = new bytes[](_dstDatas.length);
            for (uint256 i = 0; i < _dstDatas.length; i++) {
                (bool success, bytes memory result) = _dstDatas[i].target.call{
                    value: _dstDatas[i].value
                }(_dstDatas[i].data);
                if (!success) revert TransactionExecutionFailed();
                results[i] = result;
            }

            (bool executeSuccess, ) = address(protocol).call(
                abi.encodeWithSelector(
                    IBondProtocol.settleIntentDestExecutor.selector,
                    _intentId,
                    _executor
                )
            );
            if (!executeSuccess) revert FailedToSettleExecutor();
        } else {
            // if it is not the destination chain then it is the source chain.
            // loop through intent source chain to find the amount to send to destination chain
            uint256 _intentSrcAmount = 0;
            for (uint i = 0; i < _intent.srcChainIds.length; ) {
                if (_intent.srcChainIds[i] == block.chainid) {
                    _intentSrcAmount = _intent.srcAmounts[i];
                }
                unchecked {
                    ++i;
                }
            }
            if (_intentSrcAmount == 0) revert InvalidExecutionChain();
            // get pool info so we can get the underlying token we interact with,
            // this is the token to interact with and send to destination chain.
            // using a single poolId across chain helps us to manage tokens on different chains
            DataTypes.PoolData memory _poolData = protocol.getPool(
                _intent.poolId
            );
            // now we have the pool data containing the token information we need to make 2 calls
            // first approve the protocol to spend the token
            // second call interacts with the protocol to bridge tokens to destination chain

            // make sure user has enough balance before calling approve
            if (
                IERC20(_poolData.underlyingToken).balanceOf(address(this)) <
                _intentSrcAmount
            ) revert InsufficientFunds();
            // approves the protocol to spend the token
            (bool approveSuccess, bytes memory successResult) = address(
                _poolData.underlyingToken
            ).call(
                    abi.encodeWithSelector(
                        IERC20.approve.selector,
                        address(protocol),
                        _intentSrcAmount
                    )
                );
            if (!approveSuccess) revert TransactionExecutionFailed();

            // call the protocol to settle destination chain
            (bool executeSuccess, bytes memory executeResult) = address(
                protocol
            ).call(
                    abi.encodeWithSelector(
                        IBondProtocol.settleIntentDestChain.selector,
                        _intentId,
                        _executor
                    )
                );
            if (!executeSuccess) revert TransactionExecutionFailed();

            results = new bytes[](2);
            results[0] = successResult;
            results[1] = executeResult;

            return results;
        }

        emit IntentExecuted(_intentId, _executor);
    }

    // Validate user operation (called by EntryPoint)
    function validateUserOp(
        UserOperation06 calldata userOp,
        bytes32 userOpHash,
        uint256
    ) external view override onlyEntryPoint returns (uint256 validationData) {
        // Check signature length to determine type
        if (userOp.signature.length == 32) {
            // Intent-based validation
            return _validateIntentSignature(userOp);
        } else {
            // Traditional ECDSA signature validation
            return _validateECDSASignature(userOpHash, userOp.signature);
        }
    }

    function _validateECDSASignature(
        bytes32 userOpHash,
        bytes calldata signature
    ) internal view returns (uint256) {
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(
            userOpHash
        );
        address signer = ECDSA.recover(messageHash, signature);
        if (owner != signer) return SIG_VALIDATION_FAILED;
        return SIG_VALIDATION_SUCCESS;
    }

    function _validateIntentSignature(
        UserOperation06 calldata userOp
    ) internal view returns (uint256) {
        // Extract intentId from signature (32 bytes)
        bytes32 intentId = bytes32(userOp.signature);

        // Validate intentId is not zero
        if (intentId == bytes32(0)) return SIG_VALIDATION_FAILED;

        // 1. Check if callData is calling executeIntent function
        if (userOp.callData.length < 4) return SIG_VALIDATION_FAILED;

        bytes4 functionSelector = bytes4(userOp.callData[:4]);
        if (functionSelector != EXECUTE_INTENT_SELECTOR)
            return SIG_VALIDATION_FAILED;

        // 2. Decode the executeIntent parameters to check intentId match
        if (!_validateExecuteIntentCall(userOp.callData, intentId)) {
            return SIG_VALIDATION_FAILED;
        }

        // 3. Check if intent is valid using protocol contract
        if (!protocol.isIntentValid(intentId, address(this)))
            return SIG_VALIDATION_FAILED;

        return SIG_VALIDATION_SUCCESS;
    }

    function _validateExecuteIntentCall(
        bytes calldata callData,
        bytes32 expectedIntentId
    ) internal view returns (bool) {
        // Skip the function selector (first 4 bytes) and decode parameters
        if (callData.length < 4 + 64) {
            // 4 bytes selector + minimum 64 bytes for two parameters
            return false;
        }

        // Decode the executeIntent function call
        // executeIntent(bytes32 _intentId, address _executor)
        try this._decodeExecuteIntentCall(callData[4:]) returns (
            bytes32 intentId,
            address executor
        ) {
            // Validate intentId matches and executor is not zero address
            return
                intentId == expectedIntentId &&
                intentId != bytes32(0) &&
                executor != address(0);
        } catch {
            return false;
        }
    }

    // Helper function to decode executeIntent call and extract intentId
    function _decodeExecuteIntentCall(
        bytes calldata data
    ) external pure returns (bytes32, address) {
        // Decode the parameters: (bytes32 _intentId, address _executor)
        (bytes32 intentId, address executor) = abi.decode(data, (bytes32, address));
        return (intentId, executor);
    }

    function getEntryPoint() external view returns (IEntryPoint) {
        return entryPoint;
    }

    // Add ERC165 support for interface detection
    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == type(IAccount06).interfaceId;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {
        (newImplementation);
    }
}
