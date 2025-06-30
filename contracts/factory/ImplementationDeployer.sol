// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BondSmartAccount} from "../account/BondSmartAccount.sol";
import {BondAccountFactory} from "./BondAccountFactory.sol";

// Helper contract for deterministic deployment of implementation and factory
contract ImplementationDeployer {
    event ImplementationDeployed(
        address indexed implementation,
        address indexed entryPoint,
        bytes32 salt
    );
    event FactoryDeployed(
        address indexed factory,
        address indexed implementation,
        address protocol,
        bytes32 salt
    );

    // Deploy SmartAccount implementation with deterministic address and entryPoint
    // Note: Protocol is no longer passed to implementation constructor
    function deployImplementation(
        address entryPoint,
        bytes32 salt
    ) public returns (address) {
        require(entryPoint != address(0), "Invalid entryPoint address");

        address expectedAddr = getImplementationAddress(entryPoint, salt);
        if (expectedAddr.code.length > 0) {
            return expectedAddr;
        }

        bytes memory bytecode = abi.encodePacked(
            type(BondSmartAccount).creationCode,
            abi.encode(entryPoint)
        );

        address implementation = Create2.deploy(0, salt, bytecode);

        emit ImplementationDeployed(implementation, entryPoint, salt);
        return implementation;
    }

    // Get the deterministic implementation address before deployment
    function getImplementationAddress(
        address entryPoint,
        bytes32 salt
    ) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(BondSmartAccount).creationCode,
            abi.encode(entryPoint)
        );

        return Create2.computeAddress(salt, keccak256(bytecode), address(this));
    }

    // Deploy factory with the implementation address
    function deployFactory(
        address implementation,
        address entryPoint,
        address protocol,
        bytes32 salt
    ) public returns (address) {
        require(entryPoint != address(0), "Invalid entryPoint address");
        require(protocol != address(0), "Invalid protocol address");

        address expectedAddr = getFactoryAddress(
            implementation,
            entryPoint,
            protocol,
            salt
        );
        if (expectedAddr.code.length > 0) {
            return expectedAddr;
        }

        bytes memory bytecode = abi.encodePacked(
            type(BondAccountFactory).creationCode,
            abi.encode(implementation, entryPoint, protocol)
        );

        address factory = Create2.deploy(0, salt, bytecode);

        emit FactoryDeployed(factory, implementation, protocol, salt);
        return factory;
    }

    // Get factory address before deployment
    function getFactoryAddress(
        address implementation,
        address entryPoint,
        address protocol,
        bytes32 salt
    ) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(BondAccountFactory).creationCode,
            abi.encode(implementation, entryPoint, protocol)
        );

        return Create2.computeAddress(salt, keccak256(bytecode), address(this));
    }

    // Deploy both implementation and factory in one transaction
    function deployAll(
        address entryPoint,
        address protocol,
        bytes32 implementationSalt,
        bytes32 factorySalt
    ) external returns (address implementation, address factory) {
        // Deploy implementation first (only needs entryPoint)
        implementation = deployImplementation(entryPoint, implementationSalt);

        // Deploy factory with the implementation and protocol
        factory = deployFactory(
            implementation,
            entryPoint,
            protocol,
            factorySalt
        );

        return (implementation, factory);
    }
}