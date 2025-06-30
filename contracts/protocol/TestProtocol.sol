// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {DataTypes} from "../libraries/DataTypes.sol";

contract TestProtocol {
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
    uint256 baseProtocolFee = 200000;

    constructor() {}

    function getTestFees(
        bytes memory _intentData
    ) external view returns (uint256) {
        DataTypes.IntentData memory _intent = abi.decode(
            _intentData,
            (DataTypes.IntentData)
        );
        require(
            _intent.initChainSenderNonce == intentNonce[msg.sender],
            "Invalid intent nonce"
        );
        require(_intent.sender == msg.sender, "Invalid intent sender");

        bytes32 _intentId = getIntentId(_intentData);

        require(
            intents[_intentId].initChainId == 0,
            "Intent Already Submitted"
        );

        uint64 _getChainId = getChainId();

        // init chain in intent being submited must match the chain it was called (i.e current chain)
        require(
            _intent.initChainId == _getChainId,
            "Invalid init chain.intent init chain must match current chain"
        );

        require(
            _intent.srcChainIds.length == _intent.srcAmounts.length,
            "Invalid intent: source data mismatch"
        );

        require(
            chainIdToChainSelector[_intent.dstChainId] != 0,
            "Unsupported destination chain"
        );

        uint256 _srcIdLength = _intent.srcChainIds.length;

        // we start with _feesInLink = baseProtocolFee which will contain fee to cover destination chain fee and other fees
        // we start with _feesInLink = baseProtocolFee  * _srcIdLength which will contain fee to cover destination chain fee and
        // compensation paid to solvers
        // other intent src fees will be added accordingly
        uint256 _feesInLink = baseProtocolFee * _srcIdLength;

        bytes memory _bridgeMsgData = abi.encode(
            DataTypes.BridgeData(_intentId, _intentData)
        );

        for (uint i = 0; i < _srcIdLength; ) {
            // ensure source chain is valid by checking if it has been registered as a valid chain
            require(
                chainIdToChainSelector[_intent.srcChainIds[i]] != 0,
                "Unsupported source chain"
            );

            if (_getChainId == _intent.srcChainIds[i]) {
                if (_getChainId != _intent.dstChainId) {
                    uint256 _srcAmount = _intent.srcAmounts[i];

                    uint256 _bridgeFees = 50000;
                    // we multiply bridge fee by 2 for now to cover other fees
                    _feesInLink += _bridgeFees * 2;
                }
            } else {
                uint256 _bridgeFees = 50000;
                // we multiply bridge fee by 2 for now just to cover the second transaction that goes to destination chain
                _feesInLink += _bridgeFees * 2;
            }
            unchecked {
                ++i;
            }
        }

        // get fees in selected token using chainlink pricefeed
        uint256 _fees = _feesInLink;

        return _fees;
    }

    function getTestIntent(
        bytes memory _intentData
    ) external pure returns (DataTypes.IntentData memory) {
        DataTypes.IntentData memory _intent = abi.decode(
            _intentData,
            (DataTypes.IntentData)
        );
        return _intent;
    }

    function peerChainIdandChainSelector(
        uint64 _chainId,
        uint64 _chainSelector
    ) external {
        chainIdToChainSelector[_chainId] = _chainSelector;
        chainSelectorToChainId[_chainSelector] = _chainId;
    }

    function getIntentId(bytes memory _intent) internal pure returns (bytes32) {
        return keccak256(_intent);
    }

    function getNonce(address _sender) external view returns (uint64) {
        return intentNonce[_sender];
    }

    /**
     * @dev helper function to get the blockchain Id
     */
    function getChainId() internal view returns (uint64) {
        uint256 chainId = block.chainid;
        require(chainId <= type(uint64).max, "chainId exceeds uint64 limit");
        return uint64(chainId);
    }
}
