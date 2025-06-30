// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../account/BondSmartAccount.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BondAccountFactory {
    address public immutable implementation;
    address public immutable entryPoint;
    address public protocol;

    // Event for account creation
    event AccountCreated(
        address indexed account,
        address indexed owner,
        bytes32 salt
    );

    constructor(address _implementation, address _entryPoint, address _protocol) {
        require(
            _implementation != address(0),
            "Invalid implementation address"
        );
        require(
            _implementation.code.length > 0,
            "Implementation must be a contract"
        );
        require(_entryPoint != address(0), "Invalid entryPoint address");
        require(_protocol != address(0), "Invalid protocol address");

        implementation = _implementation;
        entryPoint = _entryPoint;
        protocol = _protocol;
    }

    function createAccount(
        address owner,
        bytes32 salt
    ) external returns (address) {
        // Calculate the expected address first
        address expectedAddress = getAccountAddress(owner, salt);

        // Check if account already exists to avoid revert
        if (expectedAddress.code.length > 0) {
            return expectedAddress;
        }        

        // Generate initialization data - only pass owner since entryPoint is already in implementation 
        bytes memory initData = abi.encodeWithSelector(
            BondSmartAccount.initialize.selector,
            owner,
            protocol
        );

        // Deploy proxy with Create2
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        address account = Create2.deploy(0, salt, proxyBytecode);

        emit AccountCreated(account, owner, salt);

        return account;
    }

    function getAccountAddress(
        address owner,
        bytes32 salt
    ) public view returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            BondSmartAccount.initialize.selector,
            owner,
            protocol
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        return
            Create2.computeAddress(
                salt,
                keccak256(proxyBytecode),
                address(this)
            );
    }

    // Helper function to generate deterministic salt
    function generateSalt(
        address owner,
        uint256 index
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, index));
    }

    // Get the entryPoint address used by this factory
    function getEntryPoint() external view returns (address) {
        return entryPoint;
    }

    // Get the protocol address used by this factory
    function getProtocol() external view returns (address) {
        return protocol;
    }
}