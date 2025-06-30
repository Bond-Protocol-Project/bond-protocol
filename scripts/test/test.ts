import { network } from "hardhat";
import { deployment_configs, getChainNameFromId } from "../configs.js";
import { decodeIntentData, encodeIntentData, encodeIntentDataOpt } from "../../utils/helpers.js";
import { encodeFunctionData, getContract, Hex, parseEther } from "viem";
import { ENTRYPOINT_ADDRESS } from "../../utils/constants.js";
import ENTRYPOINT_ARTIFACT from "../../utils/EntrypontV06.json"
import ACCOUNT_ARTIFACT from "../../artifacts/contracts/account/BondSmartAccount.sol/BondSmartAccount.json";

async function main() {
    try {
        const { viem } = await network.connect();

        const publicClient = await viem.getPublicClient();
        const [senderAccount] = await viem.getWalletClients();

        // const accountContract = await viem.deployContract("ValidationDebugContract", [senderAccount.account.address]);

        // console.log(`contract Deployed at: ${accountContract.address}`);

        const intentId = "0xcd3f4a31179c572a931d6a483eee66e051dfd63962f8d51a20a1e503e7cc7289";
        const executor = "0x85db92aD7a03727063D58846617C977B3Aaa3036";

        const protocol = await viem.getContractAt("BondProtocol", "0x1F4899e17F9eEc08B91a48f8A5be12Bca14F18a6");
        const bridge = await viem.getContractAt("BondBridge", "0xF2791A85159D7cEC9dA0cd5112baB84845EB79FC");
        const pResp = await protocol.read.getIntent([intentId]);
        await bridge.write.withdrawToken(["0x85db92aD7a03727063D58846617C977B3Aaa3036", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"])
        

        console.log("pResp:", pResp);

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

        // const completeUserOp = {
        //     sender: accountContract.address as Hex,
        //     nonce: 0n,
        //     initCode: "0x" as Hex,
        //     callData: userOpCallData,
        //     callGasLimit: 0n, // High gas limit for testing
        //     verificationGasLimit: 0n,
        //     preVerificationGas: 0n,
        //     maxFeePerGas: 0n,
        //     maxPriorityFeePerGas: 0n,
        //     paymasterAndData: "0x" as Hex,
        //     signature: intentId as Hex,
        // };

        // // Calculate userOpHash
        // const userOpHash = await entrypoint.read.getUserOpHash([completeUserOp]) as Hex;
        // console.log("UserOp hash:", userOpHash);

        // const result = await publicClient.simulateContract({
        //     address: accountContract.address,
        //     abi: accountContract.abi,
        //     functionName: "validateUserOp", // No need for "Public" version anymore
        //     args: [completeUserOp, userOpHash, 0n],
        // });

        // console.log("Validation result:", result);

        // const protocolContract = await viem.deployContract("TestProtocol");

        // console.log(`contract Deployed at: ${protocolContract.address}`);

        // for (const e of deployment_configs.local.allowed_chainselectors) {
        //     console.log(`Protocol Peering chainId with chain selectors: (id:${e.chain_id} - selector:${e.chain_selector})`);
        //     await protocolContract.write.peerChainIdandChainSelector([BigInt(e.chain_id), BigInt(e.chain_selector)]);
        //     console.log("done");
        // }

        // const _nonce = await protocolContract.read.getNonce([senderAccount.account.address]);
        // console.log(_nonce);

        // const intentData = encodeIntentData({
        //     sender: senderAccount.account.address,
        //     initChainSenderNonce: _nonce,
        //     initChainId: BigInt(publicClient.chain.id),
        //     poolId: 100001n,
        //     srcChainIds: [421614n, 43113n],
        //     srcAmounts: [parseEther('2'), parseEther('2')],
        //     dstChainId: 80002n,
        //     dstDatas: [
        //         {
        //             target: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
        //             value: parseEther('0.1'),
        //             data: '0x095ea7b3000000000000000000000000a0b86a33e6776e681c000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
        //         },
        //         {
        //             target: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
        //             value: 0n,
        //             data: '0xa9059cbb000000000000000000000000def1c0ded9bec7f1a1670819833240f027b25eff00000000000000000000000000000000000000000000000000000000000003e8'
        //         }
        //     ],
        //     expires: BigInt(Math.floor(Date.now() / 1000) + 3600) // 1 hour from now
        // });

        // const intentData = encodeIntentDataOpt({
        //     sender: '0xCae1e3c19868Bd248742D01284d83e486822753f',
        //     initChainSenderNonce: 0n,
        //     initChainId: 80002n,
        //     poolId: 100001n,
        //     srcChainIds: [43113n, 421614n],
        //     srcAmounts: [2000000n, 2000000n],
        //     dstChainId: 11155111n,
        //     dstDatas: [
        //         {
        //             target: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
        //             value: 0n,
        //             data: '0xa9059cbb000000000000000000000000def1c0ded9bec7f1a1670819833240f027b25eff00000000000000000000000000000000000000000000000000000000000003e8'
        //         }
        //     ],
        //     expires: 1751199686n
        // }, '0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000041e94eb019c0762f9bfcf9fb1e58725bfb0e7582000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000325522253a66c475c5c5302d5a2538115969c09c0000000000000000000000000000000000000000000000003782dace9d90000000000000000000000000000000000000000000000000000000000000');

        // console.log(intentData);

        // // const intentData = "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000001c7e4f6acb2787ed0b93484e42b852d0b357b8e40000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000001388200000000000000000000000000000000000000000000000000000000000186a1000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001800000000000000000000000000000000000000000000000000000000000066eee00000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000685f4a4f0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000a8690000000000000000000000000000000000000000000000000000000000066eee000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000001e848000000000000000000000000000000000000000000000000000000000001e8480000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000041e94eb019c0762f9bfcf9fb1e58725bfb0e7582000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000044a9059cbb000000000000000000000000325522253a66c475c5c5302d5a2538115969c09c0000000000000000000000000000000000000000000000003782dace9d90000000000000000000000000000000000000000000000000000000000000";
        // console.log("intentData:", decodeIntentData(intentData)); 

        // const feeData = await protocolContract.read.getTestFees([intentData], {
        //     account: senderAccount.account.address
        // });
        // console.log("feeData:", feeData)

        // const respIntentData = await protocolContract.read.getTestIntent([intentData], {
        //     account: senderAccount.account.address
        // });
        // console.log("respIntentData:", respIntentData)

    } catch (e) {
        console.log("Error:", e)
    };
}

main().catch((e) => {
    console.log("Error:", e)
})
