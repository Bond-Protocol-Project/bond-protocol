import { network } from "hardhat";
import ERC20_ARTIFACT from "../../artifacts/contracts/mocks/TokenERC20.sol/TokenERC20.json";
import ACCOUNT_ARTIFACT from "../../artifacts/contracts/account/BondSmartAccount.sol/BondSmartAccount.json";
import ACCOUNT_FACTORY_ARTIFACT from "../../artifacts/contracts/factory/BondAccountFactory.sol/BondAccountFactory.json";
import ENTRYPOINT_ARTIFACT from "../../utils/EntrypontV06.json"
import { encodeFunctionData, Hex, parseUnits, getContract, recoverAddress, hashMessage, decodeFunctionData } from "viem";
import { getDummySignatureByTotalSignersLength, getPaymasterData, getProviderFromChainId, getUserOpReceipt, sleep, toBytes32Salt } from "../../utils/helpers.js";
import { ENTRYPOINT_ADDRESS, FACTORY_ADDRESS } from "../../utils/constants.js";

import "dotenv/config"
import { UserOperationStruct } from "../../types/global.types.js";
import { protocolAddress } from "../configs.js";

const { viem } = await network.connect();

const accountSalt = toBytes32Salt(1);

const publicClient = await viem.getPublicClient();
const [senderClient] = await viem.getWalletClients();

const intentId = "0xcd3f4a31179c572a931d6a483eee66e051dfd63962f8d51a20a1e503e7cc7289";

const protocol = await viem.getContractAt("BondProtocol", protocolAddress);
const resp = await protocol.read.getIntent([intentId]);

console.log(resp);

const entrypoint = getContract({
    address: ENTRYPOINT_ADDRESS,
    abi: ENTRYPOINT_ARTIFACT.abi,
    client: senderClient,
});

const executeIntentArgs = [intentId, "0x85db92aD7a03727063D58846617C977B3Aaa3036"];
const userOpCallData = encodeFunctionData({
    abi: ACCOUNT_ARTIFACT.abi,
    functionName: "executeIntent",
    args: executeIntentArgs,
});

const createAccountArgs = [senderClient.account.address, accountSalt]
const factoryCreateAccountData = encodeFunctionData({
    abi: ACCOUNT_FACTORY_ARTIFACT.abi,
    functionName: "createAccount",
    args: createAccountArgs,
});

let initCode =
    FACTORY_ADDRESS +
    factoryCreateAccountData.slice(2);

let accountAddress = "";
try {
    await entrypoint.read.getSenderAddress([initCode]);
} catch (ex: any) {
    if (ex.cause.data && (ex.cause.data.args as any[]).length > 0) {
        accountAddress = ex.cause.data.args[0];
        console.log("Counterfactual address:", accountAddress);
    } else {
        throw new Error("Could not get Address");
    }
}
console.log(accountAddress);

const pimlicoPublicClient = getProviderFromChainId(publicClient.chain.id);
const code = await publicClient.getCode({
    address: accountAddress as Hex
});
console.log("Contract code:", code);

if (code !== undefined || code !== "0x") {
    initCode = "0x";
}
console.log("initCode:", initCode);

const accountNonce: any = await entrypoint.read.getNonce([accountAddress, 0]);
console.log("accountNonce:", accountNonce);
console.log(accountNonce.toString());

const userOp: Partial<UserOperationStruct> = {
    sender: accountAddress as Hex, // smart account address
    nonce: "0x" + accountNonce.toString(16) as Hex,
    initCode: initCode as Hex,
    callData: userOpCallData,
    paymasterAndData: '0x',
    signature: intentId,
};

const feeData = await pimlicoPublicClient.send(
    "pimlico_getUserOperationGasPrice",
    []
);

console.log(feeData);

userOp.maxFeePerGas = feeData.fast.maxFeePerGas;
userOp.maxPriorityFeePerGas = feeData.fast.maxPriorityFeePerGas;

// Add this debugging code to your script before the paymaster call

console.log("=== DEBUG VALIDATION ===");

// First, let's check the signature format
console.log("Signature length:", userOp.signature!.length);
console.log("Signature:", userOp.signature);
console.log("Intent ID:", intentId);
console.log("Intent ID length:", intentId.length);

// Simulate the validateUserOp call directly
try {
    const smartAccount = getContract({
        address: accountAddress as Hex,
        abi: ACCOUNT_ARTIFACT.abi,
        client: publicClient,
    });

    // Create a proper UserOperation structure for validation
    const userOpForValidation = {
        sender: userOp.sender,
        nonce: userOp.nonce,
        initCode: userOp.initCode,
        callData: userOp.callData,
        callGasLimit: "0x100000", // temporary high value
        verificationGasLimit: "0x100000", // temporary high value  
        preVerificationGas: "0x10000", // temporary high value
        maxFeePerGas: userOp.maxFeePerGas,
        maxPriorityFeePerGas: userOp.maxPriorityFeePerGas,
        paymasterAndData: "0x",
        signature: intentId // Use intentId directly as signature
    };

    console.log("UserOp for validation:", userOpForValidation);

    // Calculate the userOpHash for validation
    const userOpHashForValidation = await entrypoint.read.getUserOpHash([userOpForValidation]);
    console.log("UserOp hash for validation:", userOpHashForValidation);

    // Try to call validateUserOp directly
    const validationResult = await smartAccount.read.validateUserOp([
        userOpForValidation,
        userOpHashForValidation,
        0n // missingAccountFunds
    ]);

    console.log("Validation result:", validationResult);

} catch (validationError) {
    console.log("Validation error details:", validationError);

    // If the above fails, let's check individual components
    console.log("\n=== CHECKING INDIVIDUAL COMPONENTS ===");

    // Check if the intent exists and is valid
    try {
        const isIntentValid = await protocol.read.isIntentValid([intentId, accountAddress as Hex]);
        console.log("Is intent valid:", isIntentValid);
    } catch (e) {
        console.log("Error checking intent validity:", e);
    }

    // Check the callData format
    console.log("CallData:", userOp.callData);
    console.log("CallData length:", userOp.callData!.length);

    // Decode the function selector
    const functionSelector = userOp.callData!.slice(0, 10); // 0x + 4 bytes = 10 chars
    console.log("Function selector:", functionSelector);

    // Check if it matches executeIntent selector
    const executeIntentSelector = encodeFunctionData({
        abi: ACCOUNT_ARTIFACT.abi,
        functionName: "executeIntent",
        args: [intentId, "0x85db92aD7a03727063D58846617C977B3Aaa3036"],
    }).slice(0, 10);
    console.log("Expected executeIntent selector:", executeIntentSelector);
    console.log("Selectors match:", functionSelector === executeIntentSelector);

    // Try to decode the callData parameters
    try {
        const decoded = decodeFunctionData({
            abi: ACCOUNT_ARTIFACT.abi,
            data: userOp.callData as Hex
        });
        console.log("Decoded callData:", decoded);
    } catch (e) {
        console.log("Error decoding callData:", e);
    }
}

// Also check the current chain ID
const chainId = await publicClient.getChainId();
console.log("Current chain ID:", chainId);
console.log("Intent destination chain ID:", resp.dstChainId.toString());
console.log("Intent source chain IDs:", resp.srcChainIds.map(id => id.toString()));

console.log("=== END DEBUG ===\n");
