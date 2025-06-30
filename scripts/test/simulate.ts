import { network } from "hardhat";
import ERC20_ARTIFACT from "../../artifacts/contracts/mocks/TokenERC20.sol/TokenERC20.json";
import ACCOUNT_ARTIFACT from "../../artifacts/contracts/account/BondSmartAccount.sol/BondSmartAccount.json";
import ACCOUNT_FACTORY_ARTIFACT from "../../artifacts/contracts/factory/BondAccountFactory.sol/BondAccountFactory.json";
import ENTRYPOINT_ARTIFACT from "../../utils/EntrypontV06.json"
import { encodeFunctionData, Hex, parseUnits, getContract, recoverAddress, hashMessage, decodeFunctionData, createPublicClient, http, decodeAbiParameters, erc20Abi } from "viem";
import { getDummySignatureByTotalSignersLength, getPaymasterData, getProviderFromChainId, getUserOpReceipt, sleep, toBytes32Salt } from "../../utils/helpers.js";
import { ENTRYPOINT_ADDRESS, FACTORY_ADDRESS } from "../../utils/constants.js";

import "dotenv/config"
import { UserOperationStruct } from "../../types/global.types.js";

const { viem } = await network.connect();

const publicClient = await viem.getPublicClient();
const [senderClient] = await viem.getWalletClients();

const intentId = "0xcd3f4a31179c572a931d6a483eee66e051dfd63962f8d51a20a1e503e7cc7289";
const accountAddress = "0xCae1e3c19868Bd248742D01284d83e486822753f";
const executor = "0x85db92aD7a03727063D58846617C977B3Aaa3036";

const protocol = await viem.getContractAt("BondProtocol", "0x1F4899e17F9eEc08B91a48f8A5be12Bca14F18a6");
const bridge = await viem.getContractAt("BondBridge", "0xF2791A85159D7cEC9dA0cd5112baB84845EB79FC"); //sepolia
// const bridge = await viem.getContractAt("BondBridge", "0xd1Ed0D7194ACdeF973Bf1036cd866d4AC156757C"); //arbitrum
// const bridge = await viem.getContractAt("BondBridge", "0xC78e8b092434E694F2CcCe489EE0983Ed5CC88F3"); //fuji

const addressContract = await viem.getContractAt("BondSmartAccount", accountAddress) ;

const tokenAddress = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"; // sepolia
// const tokenAddress = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"; // arb
// const tokenAddress = "0x5425890298aed601595a70AB815c96711a31Bc65"; // fuji

// const allowance = await publicClient.readContract({
//     address: tokenAddress,
//     abi: erc20Abi,
//     functionName: "allowance",
//     args: [accountAddress, protocol.address]
// });
// console.log("allowance:", allowance);

async function getIntent() {
    const resp = await protocol.read.getIntent([intentId]);
    console.log(resp);
    console.log("dstChainId:", resp.dstChainId);

    const getChainSelectorResp = await protocol.read.chainIdToChainSelector([resp.dstChainId]);
    console.log(getChainSelectorResp);

    const bridgeResp = await bridge.read.allowlistedDestinationChains([getChainSelectorResp]);
    console.log("Is destination chainSelector Allowed:", bridgeResp);

    const bridgeDestResp = await bridge.read.chainSelectorToBridgeAddress([getChainSelectorResp]);
    console.log("Is destination chainSelector Allowed:", bridgeDestResp);

    const accountResp = await addressContract.read.protocol();
    console.log("accountResp:", accountResp)
}

// await getIntent().catch(console.error);

async function simulateConfirmDestIntent() {
    try {
        const result = await publicClient.simulateContract({
            address: protocol.address as Hex,
            abi: protocol.abi,
            functionName: "settleIntentDestChain",
            args: [intentId, executor],
            account: accountAddress as Hex, // Simulate call from account
        });
        console.log("simulated");
    } catch (e) {
        console.log("❌ settleIntentDestChain simulation failed:");
        console.log("Error:", (e as Error).message);
    }
}

// simulateConfirmDestIntent().catch(console.error);

async function simulateExecuteIntent() {
    try {
        const result = await publicClient.simulateContract({
            address: accountAddress,
            abi: ACCOUNT_ARTIFACT.abi,
            functionName: "executeIntent",
            args: [intentId, executor],
            account: ENTRYPOINT_ADDRESS, // Simulate call from EntryPoint
        });
        console.log("simulated");
    } catch (e) {
        console.log("❌ simulateExecuteIntent simulation failed:");
        console.log("Error:", (e as Error).message);
    }
}

// simulateExecuteIntent().catch(console.error);

async function simulateValidateUserOp() {
    try {

        const userOpCallData = encodeFunctionData({
            abi: ACCOUNT_ARTIFACT.abi,
            functionName: "executeIntent",
            args: [intentId, executor],
        });        

        const entrypoint = getContract({
            address: ENTRYPOINT_ADDRESS,
            abi: ENTRYPOINT_ARTIFACT.abi,
            client: publicClient,
        });

        const accountNonce = await entrypoint.read.getNonce([accountAddress, 0]);

        console.log("accountNonce:", accountNonce)

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

        // Calculate userOpHash
        const userOpHash = await entrypoint.read.getUserOpHash([completeUserOp]);
        console.log("UserOp hash:", userOpHash);

        const result = await publicClient.simulateContract({
            address: accountAddress,
            abi: ACCOUNT_ARTIFACT.abi,
            functionName: "validateUserOp",
            args: [completeUserOp, userOpHash, 0n],
            account: ENTRYPOINT_ADDRESS, // Simulate call from EntryPoint
        });
        console.log("simulated");
    } catch (e) {
        console.log("❌ simulateValidateUserOp simulation failed:");
        console.log("Error:", (e as Error).message);
    }
}

// simulateValidateUserOp().catch(console.error);

async function simulateConfirmIncomingIntent() {
    const _intentData = '0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000cae1e3c19868bd248742d01284d83e486822753f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001388200000000000000000000000000000000000000000000000000000000000186a1000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000aa36a700000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000068612fc60000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000a8690000000000000000000000000000000000000000000000000000000000066eee000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000001e848000000000000000000000000000000000000000000000000000000000001e8480000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000041e94eb019c0762f9bfcf9fb1e58725bfb0e7582000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000325522253a66c475c5c5302d5a2538115969c09c0000000000000000000000000000000000000000000000003782dace9d90000000000000000000000000000000000000000000000000000000000000'
    try {
        const result = await publicClient.simulateContract({
            address: protocol.address as Hex,
            abi: protocol.abi,
            functionName: "confirmIncomingIntent",
            args: [
                _intentData,
                14767482510784806043n
            ],
            account: bridge.address as Hex, // Simulate call from account
        });
        console.log("simulated");
        console.log(result);
    } catch (e) {
        console.log("❌ settleIntentDestChain simulation failed:");
        console.log("Error:", (e as Error).message);
    }
}

await simulateConfirmIncomingIntent().catch(console.error);