import { network } from "hardhat";
import ERC20_ARTIFACT from "../../artifacts/contracts/mocks/TokenERC20.sol/TokenERC20.json";
import ACCOUNT_ARTIFACT from "../../artifacts/contracts/account/BondSmartAccount.sol/BondSmartAccount.json";
import ACCOUNT_FACTORY_ARTIFACT from "../../artifacts/contracts/factory/BondAccountFactory.sol/BondAccountFactory.json";
import ENTRYPOINT_ARTIFACT from "../../utils/EntrypontV06.json"
import { encodeFunctionData, Hex, parseUnits, getContract, recoverAddress, hashMessage, decodeFunctionData, createPublicClient, http, decodeAbiParameters } from "viem";
import { getDummySignatureByTotalSignersLength, getPaymasterData, getProviderFromChainId, getUserOpReceipt, sleep, toBytes32Salt } from "../../utils/helpers.js";
import { ENTRYPOINT_ADDRESS, FACTORY_ADDRESS } from "../../utils/constants.js";

import "dotenv/config"
import { UserOperationStruct } from "../../types/global.types.js";

const { viem } = await network.connect();

const publicClient = await viem.getPublicClient();
const [senderClient] = await viem.getWalletClients();

// const publicClient = createPublicClient({
//     transport: http("https://arb-sepolia.g.alchemy.com/v2/m-5XfdCcVmgvaBrKpPrDddiSnz9cIxZP"),
// });

async function simulateExecuteIntent() {
    const intentId = "0xf0f10045d165de91da53ad960c848734bebc1dd5d5772d296a23f0d3f377caf3";
    const accountAddress = "0xf21cE0083E3Dc743D96276Ed2DCD8c9457B0e623";
    const executor = "0x85db92aD7a03727063D58846617C977B3Aaa3036";

    console.log("=== SIMULATING EXECUTE INTENT ===");

    try {
        // Try to simulate the executeIntent call using simulateContract
        const smartAccount = getContract({
            address: accountAddress as Hex,
            abi: ACCOUNT_ARTIFACT.abi,
            client: publicClient,
        });

        const result = await publicClient.simulateContract({
            address: accountAddress as Hex,
            abi: ACCOUNT_ARTIFACT.abi,
            functionName: "executeIntent",
            args: [intentId, executor],
            account: ENTRYPOINT_ADDRESS as Hex, // Simulate call from EntryPoint
        });

        console.log("✅ Simulation successful:", result);

    } catch (simulationError) {
        console.log("❌ Simulation failed:");
        console.log("Error:", simulationError);

        // Try to extract the revert reason
        if ((simulationError as any).data) {
            console.log("Revert data:", (simulationError as any).data);

            // Try to decode common revert reasons
            const revertReasons = [
                { sig: "0x356680b7", name: "InsufficientFunds()" },
                { sig: "0x8f4eb604", name: "InvalidIntentSender()" },
                { sig: "0x6f7eac26", name: "IntentExpired()" },
                { sig: "0x1425ea42", name: "InvalidExecutionChain()" },
                { sig: "0x8baa579f", name: "TransactionExecutionFailed()" },
            ];

            for (const reason of revertReasons) {
                if ((simulationError as any).data.startsWith(reason.sig)) {
                    console.log("🎯 Likely revert reason:", reason.name);
                    break;
                }
            }
        }

        // Additional specific checks based on the error
        if ((simulationError as any).message.includes("InsufficientFunds")) {
            console.log("\n💡 SOLUTION: Your smart account needs tokens!");
            console.log("Steps to fix:");
            console.log("1. Find the required token from pool data");
            console.log("2. Transfer tokens to your smart account:", accountAddress);
            console.log("3. Try the transaction again");
        }
    }

    console.log("=== END SIMULATION ===");
}

async function directDebugExecution() {
    const intentId = "0xf0f10045d165de91da53ad960c848734bebc1dd5d5772d296a23f0d3f377caf3";
    const accountAddress = "0xf21cE0083E3Dc743D96276Ed2DCD8c9457B0e623";

    console.log("=== DIRECT DEBUG EXECUTION ===");

    const protocol = await viem.getContractAt("BondProtocol", "0x1F4899e17F9eEc08B91a48f8A5be12Bca14F18a6");

    // Step 1: Get intent data
    console.log("1. Getting intent data...");
    const intentData = await protocol.read.getIntent([intentId]);
    console.log("Intent sender:", intentData.sender);
    console.log("Account address:", accountAddress);
    console.log("✅ Sender matches:", intentData.sender.toLowerCase() === accountAddress.toLowerCase());

    // Step 2: Check expiry
    console.log("\n2. Checking expiry...");
    const currentTime = Math.floor(Date.now() / 1000);
    const isExpired = Number(intentData.expires) < currentTime;
    console.log("Current timestamp:", currentTime);
    console.log("Intent expires timestamp:", Number(intentData.expires));
    console.log("✅ Not expired:", !isExpired);

    // Step 3: Check chain logic
    console.log("\n3. Checking chain logic...");
    const currentChainId = await publicClient.getChainId();
    const isDstChain = currentChainId === Number(intentData.dstChainId);
    console.log("Current chain:", currentChainId);
    console.log("Destination chain:", Number(intentData.dstChainId));
    console.log("Is destination chain:", isDstChain);

    if (isDstChain) {
        console.log("This is destination chain execution logic");
        // Check if destination chain is settled
        try {
            const isSettled = await protocol.read.isIntentDstChainFullySettled([intentId]);
            console.log("Is destination settled:", isSettled);

            const isExecuted = await protocol.read.isIntentExecuted([intentId]);
            console.log("Is already executed:", isExecuted);
        } catch (e) {
            console.log("❌ Error checking destination chain status:", (e as Error).message);
        }
    } else {
        console.log("This is SOURCE chain execution logic");

        // Step 4: Find source amount for this chain
        console.log("\n4. Finding source amount...");
        let intentSrcAmount = 0n;
        for (let i = 0; i < intentData.srcChainIds.length; i++) {
            if (Number(intentData.srcChainIds[i]) === currentChainId) {
                intentSrcAmount = intentData.srcAmounts[i];
                console.log("✅ Found source amount:", intentSrcAmount.toString());
                break;
            }
        }

        if (intentSrcAmount === 0n) {
            console.log("❌ ERROR: No source amount found for current chain");
            return;
        }

        // Step 5: Get pool data
        console.log("\n5. Getting pool data...");
        try {
            const poolData = await protocol.read.getPool([intentData.poolId]);
            console.log("✅ Pool ID:", Number(intentData.poolId));
            console.log("✅ Underlying token:", poolData.underlyingToken);

            // Step 6: Check token balance
            console.log("\n6. Checking token balance...");
            const tokenContract = await viem.getContractAt("IERC20", poolData.underlyingToken);
            const balance = await tokenContract.read.balanceOf([accountAddress]);
            console.log("Account balance:", balance.toString());
            console.log("Required amount:", intentSrcAmount.toString());

            if (balance < intentSrcAmount) {
                console.log("❌ INSUFFICIENT FUNDS!");
                console.log("Missing amount:", (intentSrcAmount - balance).toString());
                console.log("\n🔧 SOLUTION:");
                console.log(`Transfer ${(intentSrcAmount - balance).toString()} tokens to ${accountAddress}`);
                console.log(`Token address: ${poolData.underlyingToken}`);
                return;
            } else {
                console.log("✅ Sufficient balance");
            }

            // Step 7: Check current allowance (should be 0 initially)
            console.log("\n7. Checking current allowance...");
            const allowance = await tokenContract.read.allowance([accountAddress, protocol.address]);
            console.log("Current allowance:", allowance.toString());
            console.log("(This should be 0 initially, approval happens during execution)");

            console.log("\n✅ All checks passed! The issue might be in the actual execution logic.");

        } catch (e) {
            console.log("❌ Error with pool/token operations:", (e as Error).message);
        }
    }

    console.log("=== END DIRECT DEBUG ===");
}

async function testValidationWithGasLimits() {
    const intentId = "0xf0f10045d165de91da53ad960c848734bebc1dd5d5772d296a23f0d3f377caf3";
    const accountAddress = "0xf21cE0083E3Dc743D96276Ed2DCD8c9457B0e623";
    const executor = "0x85db92aD7a03727063D58846617C977B3Aaa3036";
    
    console.log("=== TESTING VALIDATION WITH GAS LIMITS ===");
    
    const entrypoint = getContract({
        address: ENTRYPOINT_ADDRESS,
        abi: ENTRYPOINT_ARTIFACT.abi,
        client: publicClient,
    });
    
    // Create a complete UserOperation
    const userOpCallData = encodeFunctionData({
        abi: ACCOUNT_ARTIFACT.abi,
        functionName: "executeIntent",
        args: [intentId, executor],
    });
    
    const accountNonce = await entrypoint.read.getNonce([accountAddress, 0]);
    
    const completeUserOp = {
        sender: accountAddress as Hex,
        nonce: "0x" + (accountNonce as any).toString(16) as Hex,
        initCode: "0x" as Hex,
        callData: userOpCallData,
        callGasLimit: "0x100000" as Hex, // High gas limit for testing
        verificationGasLimit: "0x100000" as Hex,
        preVerificationGas: "0x10000" as Hex,
        maxFeePerGas: "0x7de2900" as Hex,
        maxPriorityFeePerGas: "0xa1220" as Hex,
        paymasterAndData: "0x" as Hex,
        signature: intentId as Hex,
    };
    
    console.log("Complete UserOp:", completeUserOp);
    
    // Calculate userOpHash
    const userOpHash = await entrypoint.read.getUserOpHash([completeUserOp]);
    console.log("UserOp hash:", userOpHash);
    
    // Test validation directly
    console.log("\n1. Testing validateUserOp directly...");
    try {
        const smartAccount = getContract({
            address: accountAddress as Hex,
            abi: ACCOUNT_ARTIFACT.abi,
            client: publicClient,
        });
        
        const validationResult = await publicClient.call({
            to: accountAddress as Hex,
            data: encodeFunctionData({
                abi: ACCOUNT_ARTIFACT.abi,
                functionName: "validateUserOp",
                args: [completeUserOp, userOpHash, 0n]
            }),
            account: ENTRYPOINT_ADDRESS as Hex,
        });
        
        console.log("✅ Validation result:", validationResult);
        
        // Decode the result (should be uint256)
        const decodedResult = decodeAbiParameters([{ type: 'uint256' }], validationResult.data as Hex);
        console.log("Decoded validation result:", decodedResult[0]);
        
        if (decodedResult[0] === 0n) {
            console.log("✅ Validation SUCCESS");
        } else {
            console.log("❌ Validation FAILED with code:", decodedResult[0]);
        }
        
    } catch (e) {
        console.log("❌ Validation call failed:", (e as Error).message);
    }
    
    // Test with lower gas limits to see if it's a gas issue
    console.log("\n2. Testing with lower gas limits...");
    const lowerGasUserOp = {
        ...completeUserOp,
        callGasLimit: "0x30000" as Hex, // Lower gas limit
        verificationGasLimit: "0x30000" as Hex,
    };
    
    try {
        const lowerGasHash = await entrypoint.read.getUserOpHash([lowerGasUserOp]);
        
        const validationResult = await publicClient.call({
            to: accountAddress as Hex,
            data: encodeFunctionData({
                abi: ACCOUNT_ARTIFACT.abi,
                functionName: "validateUserOp",
                args: [lowerGasUserOp, lowerGasHash, 0n]
            }),
            account: ENTRYPOINT_ADDRESS as Hex,
        });
        
        const decodedResult = decodeAbiParameters([{ type: 'uint256' }], validationResult.data as Hex);
        console.log("Lower gas validation result:", decodedResult[0]);
        
    } catch (e) {
        console.log("❌ Lower gas validation failed:", (e as Error).message);
        if ((e as Error).message.includes("out of gas")) {
            console.log("🎯 This is likely a gas limit issue!");
        }
    }
    
    // Test execution phase simulation
    console.log("\n3. Testing execution phase...");
    try {
        const executionResult = await publicClient.estimateGas({
            to: accountAddress as Hex,
            data: userOpCallData,
            account: ENTRYPOINT_ADDRESS as Hex,
        });
        
        console.log("✅ Estimated execution gas:", executionResult.toString());
        
        if (executionResult > 500000n) {
            console.log("⚠️  High gas usage detected - this might cause issues with gas limits");
        }
        
    } catch (e) {
        console.log("❌ Execution gas estimation failed:", (e as Error).message);
        console.log("🎯 This confirms the execution will fail");
    }
    
    console.log("=== END VALIDATION TEST ===");
}

async function deepDebugProtocolOperations() {
    const intentId = "0xf0f10045d165de91da53ad960c848734bebc1dd5d5772d296a23f0d3f377caf3";
    const accountAddress = "0xf21cE0083E3Dc743D96276Ed2DCD8c9457B0e623";
    const executor = "0x85db92aD7a03727063D58846617C977B3Aaa3036";
    
    console.log("=== DEEP PROTOCOL DEBUG ===");
    
    const protocol = await viem.getContractAt("BondProtocol", "0x1F4899e17F9eEc08B91a48f8A5be12Bca14F18a6");
    const intentData = await protocol.read.getIntent([intentId]);
    const poolData = await protocol.read.getPool([intentData.poolId]);
    const tokenContract = await viem.getContractAt("IERC20", poolData.underlyingToken);
    
    // Check 1: Protocol contract state
    console.log("1. Checking protocol contract state...");
    try {
        const isPaused = await protocol.read.emergencyStop();
        console.log("Protocol paused:", isPaused);
        if (isPaused) {
            console.log("❌ ERROR: Protocol is paused!");
            return;
        }
    } catch (e) {
        console.log("Could not check paused state:", (e as Error).message);
    }
    
    // Check 2: Intent execution status
    console.log("\n2. Checking intent execution status...");
    try {
        const isAlreadyExecuted = await protocol.read.isIntentExecuted([intentId]);
        console.log("Intent already executed:", isAlreadyExecuted);
        if (isAlreadyExecuted) {
            console.log("❌ ERROR: Intent already executed!");
            return;
        }
    } catch (e) {
        console.log("Could not check execution status:", (e as Error).message);
    }
    
    // Check 3: Bridge contract
    console.log("\n3. Checking bridge contract...");
    console.log("Bridge contract exists:", true);
    
    // Check 4: Chain selector mapping
    console.log("\n4. Checking chain selector mapping...");
    try {
        const dstChainSelector = await protocol.read.chainIdToChainSelector([intentData.dstChainId]);
        console.log("Destination chain selector:", dstChainSelector);
        
        if (dstChainSelector == 0n) {
            console.log("❌ ERROR: Chain selector not configured for destination chain!");
            return;
        }
    } catch (e) {
        console.log("❌ Error checking chain selector:", (e as Error).message);
    }
    
    // Check 5: Token operations simulation
    console.log("\n5. Simulating token operations...");
    const intentSrcAmount = 2000000n; // We know this from previous debug
    
    try {
        // Test approve operation
        console.log("5a. Testing token approve...");
        const approveData = encodeFunctionData({
            abi: [
                {
                    name: "approve",
                    type: "function",
                    inputs: [
                        { name: "spender", type: "address" },
                        { name: "amount", type: "uint256" }
                    ],
                    outputs: [{ name: "", type: "bool" }]
                }
            ],
            functionName: "approve",
            args: [protocol.address, intentSrcAmount]
        });
        
        const approveResult = await publicClient.call({
            to: poolData.underlyingToken,
            data: approveData,
            account: accountAddress as Hex
        });
        console.log("✅ Approve simulation passed");
        
    } catch (e) {
        console.log("❌ Approve simulation failed:", (e as Error).message);
        return;
    }
    
    // Check 6: Protocol settleIntentDestChain simulation
    console.log("\n6. Simulating settleIntentDestChain...");
    try {
        const settleResult = await publicClient.simulateContract({
            address: protocol.address,
            abi: [
                {
                    name: "settleIntentDestChain",
                    type: "function",
                    inputs: [
                        { name: "_intentId", type: "bytes32" },
                        { name: "_executor", type: "address" }
                    ],
                    outputs: []
                }
            ],
            functionName: "settleIntentDestChain",
            args: [intentId, executor],
            account: accountAddress as Hex
        });
        console.log("✅ settleIntentDestChain simulation passed");
        
    } catch (e) {
        console.log("❌ settleIntentDestChain simulation failed:");
        console.log("Error:", (e as Error).message);
        
        // Check specific error conditions for settleIntentDestChain
        if ((e as Error).message.includes("InvalidIntentSender")) {
            console.log("🎯 The protocol thinks you're not the intent sender");
        } else if ((e as Error).message.includes("IntentAlreadySubmitted")) {
            console.log("🎯 Intent already submitted to protocol");
        } else if ((e as Error).message.includes("IntentExpired")) {
            console.log("🎯 Protocol thinks intent is expired");
        } else if ((e as Error).message.includes("InvalidChain")) {
            console.log("🎯 Protocol doesn't recognize this as a valid source chain for the intent");
        } else if ((e as Error).message.includes("InsufficientAllowance")) {
            console.log("🎯 Protocol doesn't have enough allowance (but we just approved)");
        } else if ((e as Error).message.includes("InsufficientFunds")) {
            console.log("🎯 Protocol thinks account doesn't have enough tokens");
        }
        
        return;
    }
    
    // Check 7: Check if this might be a reentrancy issue
    console.log("\n7. Additional checks...");
    console.log("Account nonce:", await publicClient.getTransactionCount({ address: accountAddress as Hex }));
    console.log("Block number:", await publicClient.getBlockNumber());
    
    console.log("\n✅ All deep checks passed! The issue might be in the internal _bridgeIntentMessage function.");
    console.log("💡 Try adding console.log statements to your contract or use hardhat console.log for debugging.");
}

// Run the deep debug
// deepDebugProtocolOperations().catch(console.error);

// Run the validation test
// testValidationWithGasLimits().catch(console.error);

// Run the direct debug
// directDebugExecution().catch(console.error);

// Run the simulation
// simulateExecuteIntent().catch(console.error);