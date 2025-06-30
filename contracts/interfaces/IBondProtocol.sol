// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title IBondProtocol
 * @dev Interface of the protocol main contract.
 */
interface IBondProtocol {
    /**
     * @notice This function sends the intent message to every required chain
     * @dev This is the entry function to send an intent request
     * @param _intentData the intent bytes to be executed
     */
    function submitIntent(bytes memory _intentData) external;

    /**
     * @notice This function just simulates the submitIntent function above and get required fees to process the intent passed
     * @dev simulate submiting intent and get fees
     * @param _intentData the intent bytes data
     */
    function getFees(bytes memory _intentData) external;

    /**
     * @notice This function emits event that notifies solvers to build next required userop
     * @dev This function is called by _ccipReceive from the bridge contract, data is to be consumed by the protocol
     * @param _data this is the CCIP bridged message (DataTypes.BridgeData).
     * @param srcBridgedChainSelector The source chain selector from CCIP
     */
    function confirmIncomingIntent(
        bytes memory _data,
        uint64 srcBridgedChainSelector
    ) external;

    /**
     * @dev This function is called by account to settle intent destination chain
     * @param _intentId intent Id to interact with
     * @param _executor this is the solver that built the userOp
     */
    function settleIntentDestChain(
        bytes32 _intentId,
        address _executor
    ) external;

    /**
     * @dev This function is called by account to settle the solver that build the userOp to run the intent destination datas
     * @param _intentId intent Id to interact with
     * @param _executor this is the solver that built the userOp
     */
    function settleIntentDestExecutor(
        bytes32 _intentId,
        address _executor
    ) external;

    /**
     * @dev helper function to check if intent has been used on this chain
     * @param _intentId Intent id to check
     */
    function isIntentExecuted(bytes32 _intentId) external view returns (bool);

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
    ) external returns (DataTypes.PoolData memory);

    /**
     * @notice Retrieves pool data for a given pool ID.
     * @param _poolId Pool ID.
     * @return Pool data structure.
     */
    function getPool(
        uint64 _poolId
    ) external view returns (DataTypes.PoolData memory);

    /**
     * @dev retreive intent data
     * @param _intentId intent Id to be retreived
     */
    function getIntent(
        bytes32 _intentId
    ) external view returns (DataTypes.IntentData memory);

    /**
     * @dev checks if all source chains in intent has settled the destination chain
     * @param _intentId intent Id ro be checked
     */
    function isIntentDstChainFullySettled(
        bytes32 _intentId
    ) external view returns (bool);

    /**
     * @dev helper function to check if intent is valid
     * @param _intentId Intent id to check
     */
    function isIntentValid(
        bytes32 _intentId,
        address sender_
    ) external view returns (bool);

    /**
     * @dev Retreive current intent nonce for sender
     * @param _sender the sender to retreive intent nonce for
     */
    function getNonce(address _sender) external view returns (uint64);

    /**
     * @dev Admin only function to initailize protocol bridge address
     * @param bridge_ bridge address
     */
    function initializeBridge(address bridge_) external;

    /**
     * @dev Admin only function to initailize protocol pool address
     * @param pool_ pool address
     */
    function initializePool(address pool_) external;
}
