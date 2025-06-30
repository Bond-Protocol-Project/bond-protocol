// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IBondProtocol
 * @dev Interface of the protocol main contract.
 */
interface IBondBridge {
    /// @notice Sends data and transfer tokens to receiver on the destination chain.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _bridgeMsgData The bytes data to be sent.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @param _gasLimit gas limit for ccip
    function sendMessage(
        uint64 _destinationChainSelector,
        bytes calldata _bridgeMsgData,
        address _token,
        uint256 _amount,
        uint64 _gasLimit
    ) external returns (uint256 _fees, bytes32 messageId);

    function getFees(
        uint64 _destinationChainSelector,
        bytes calldata _bridgeMsgData,
        address _token,
        uint256 _amount,
        uint64 _gasLimit
    ) external view returns (uint256 _fees);
}
