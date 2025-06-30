// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Minimal UserOperation struct for testing
struct UserOperation06 {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

contract ValidationDebugContract {
    using ECDSA for bytes32;

    // Constants
    uint256 constant SIG_VALIDATION_FAILED = 1;
    uint256 constant SIG_VALIDATION_SUCCESS = 0;
    bytes4 constant EXECUTE_INTENT_SELECTOR = bytes4(keccak256("executeIntent(bytes32,address)"));

    // State variables
    address public owner;

    // Debug events
    event DebugLog(string message, bytes data);
    event DebugUint(string message, uint256 value);
    event DebugAddress(string message, address addr);
    event DebugBytes32(string message, bytes32 value);
    event DebugBool(string message, bool value);
    event ValidationStep(string step, bool success, string reason);

    constructor(address _owner) {
        owner = _owner;
    }

    // Main validation function with full debug
    function validateUserOp(
        UserOperation06 calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        emit DebugLog("Starting validation", "");
        emit DebugUint("Signature length", userOp.signature.length);
        
        // Check signature length to determine type
        if (userOp.signature.length == 32) {
            emit DebugLog("Using intent-based validation", "");
            return _validateIntentSignature(userOp);
        } else {
            emit DebugLog("Using ECDSA validation", "");
            return _validateECDSASignature(userOpHash, userOp.signature);
        }
    }

    // Public version for testing without onlyEntryPoint restriction
    function validateUserOpPublic(
        UserOperation06 calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        emit DebugLog("Starting PUBLIC validation", "");
        emit DebugUint("Signature length", userOp.signature.length);
        
        if (userOp.signature.length == 32) {
            emit DebugLog("Using intent-based validation", "");
            return _validateIntentSignature(userOp);
        } else {
            emit DebugLog("Using ECDSA validation", "");
            return _validateECDSASignature(userOpHash, userOp.signature);
        }
    }

    function _validateECDSASignature(
        bytes32 userOpHash,
        bytes calldata signature
    ) internal returns (uint256) {
        emit DebugLog("ECDSA validation started", "");
        emit DebugBytes32("UserOp hash", userOpHash);
        
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        emit DebugBytes32("Message hash", messageHash);
        
        address signer = ECDSA.recover(messageHash, signature);
        emit DebugAddress("Recovered signer", signer);
        emit DebugAddress("Expected owner", owner);
        
        if (owner != signer) {
            emit ValidationStep("ECDSA", false, "Signer mismatch");
            return SIG_VALIDATION_FAILED;
        }
        
        emit ValidationStep("ECDSA", true, "Success");
        return SIG_VALIDATION_SUCCESS;
    }

    function _validateIntentSignature(
        UserOperation06 calldata userOp
    ) internal returns (uint256) {
        emit DebugLog("Intent validation started", "");
        
        // Extract intentId from signature (32 bytes)
        bytes32 intentId = bytes32(userOp.signature);
        emit DebugBytes32("Intent ID", intentId);

        // Step 1: Validate intentId is not zero
        if (intentId == bytes32(0)) {
            emit ValidationStep("Intent ID zero check", false, "Intent ID is zero");
            return SIG_VALIDATION_FAILED;
        }
        emit ValidationStep("Intent ID zero check", true, "Intent ID is not zero");

        // Step 2: Check if callData is calling executeIntent function
        emit DebugUint("CallData length", userOp.callData.length);
        if (userOp.callData.length < 4) {
            emit ValidationStep("CallData length", false, "CallData too short");
            return SIG_VALIDATION_FAILED;
        }
        emit ValidationStep("CallData length", true, "CallData length OK");

        bytes4 functionSelector = bytes4(userOp.callData[:4]);
        emit DebugLog("Function selector", abi.encodePacked(functionSelector));
        emit DebugLog("Expected selector", abi.encodePacked(EXECUTE_INTENT_SELECTOR));
        
        if (functionSelector != EXECUTE_INTENT_SELECTOR) {
            emit ValidationStep("Function selector", false, "Wrong function selector");
            return SIG_VALIDATION_FAILED;
        }
        emit ValidationStep("Function selector", true, "Function selector matches");

        // Step 3: Decode the executeIntent parameters to check intentId match
        bool executeIntentValid = _validateExecuteIntentCall(userOp.callData, intentId);
        if (!executeIntentValid) {
            emit ValidationStep("Execute intent call", false, "Execute intent validation failed");
            return SIG_VALIDATION_FAILED;
        }
        emit ValidationStep("Execute intent call", true, "Execute intent validation passed");

        // Step 4: Always return true for protocol validation (simplified for testing)
        emit ValidationStep("Protocol check", true, "Protocol validation skipped - always true for testing");

        emit ValidationStep("Overall validation", true, "All checks passed");
        return SIG_VALIDATION_SUCCESS;
    }

    function _validateExecuteIntentCall(
        bytes calldata callData,
        bytes32 expectedIntentId
    ) internal returns (bool) {
        emit DebugLog("Validating execute intent call", "");
        emit DebugUint("CallData length for decoding", callData.length);
        
        // Skip the function selector (first 4 bytes) and decode parameters
        if (callData.length < 4 + 64) {
            emit ValidationStep("CallData minimum length", false, "Not enough data for two 32-byte parameters");
            return false;
        }
        emit ValidationStep("CallData minimum length", true, "Enough data for parameters");

        // Extract the data part (skip 4-byte selector)
        bytes calldata dataForDecoding = callData[4:];
        emit DebugLog("Data for decoding", dataForDecoding);

        try this._decodeExecuteIntentCall(dataForDecoding) returns (
            bytes32 intentId,
            address executor
        ) {
            emit DebugBytes32("Decoded intent ID", intentId);
            emit DebugAddress("Decoded executor", executor);
            emit DebugBytes32("Expected intent ID", expectedIntentId);
            
            bool intentIdMatch = intentId == expectedIntentId;
            bool intentIdNotZero = intentId != bytes32(0);
            bool executorNotZero = executor != address(0);
            
            emit DebugBool("Intent ID match", intentIdMatch);
            emit DebugBool("Intent ID not zero", intentIdNotZero);
            emit DebugBool("Executor not zero", executorNotZero);
            
            if (!intentIdMatch) {
                emit ValidationStep("Intent ID match", false, "Intent IDs don't match");
                return false;
            }
            if (!intentIdNotZero) {
                emit ValidationStep("Intent ID not zero", false, "Intent ID is zero");
                return false;
            }
            if (!executorNotZero) {
                emit ValidationStep("Executor not zero", false, "Executor is zero address");
                return false;
            }
            
            emit ValidationStep("Execute intent parameters", true, "All parameters valid");
            return true;
            
        } catch Error(string memory reason) {
            emit ValidationStep("Decode execute intent", false, string(abi.encodePacked("Decode error: ", reason)));
            return false;
        } catch {
            emit ValidationStep("Decode execute intent", false, "Unknown decode error");
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

    // Test functions for manual verification
    function testDecodeExecuteIntent(bytes calldata data) external pure returns (bytes32, address) {
        return abi.decode(data, (bytes32, address));
    }

    function testFunctionSelector() external pure returns (bytes4) {
        return EXECUTE_INTENT_SELECTOR;
    }

    function testCalculateSelector(string calldata sig) external pure returns (bytes4) {
        return bytes4(keccak256(bytes(sig)));
    }

    // Mock executeIntent function for testing
    function executeIntent(bytes32 _intentId, address _executor) external {
        emit DebugBytes32("Execute intent called with intentId", _intentId);
        emit DebugAddress("Execute intent called with executor", _executor);
    }

    // Admin functions
    function setOwner(address _owner) external {
        require(msg.sender == owner, "Only owner");
        owner = _owner;
    }
}

// Factory contract to deploy everything together
contract ValidationTestFactory {
    event ContractDeployed(
        address debugContract,
        address owner
    );
    
    function deployTestContract(
        address owner
    ) external returns (address debugContract) {
        // Deploy debug validation contract
        debugContract = address(new ValidationDebugContract(owner));
        
        emit ContractDeployed(debugContract, owner);
        
        return debugContract;
    }
}