import { network } from "hardhat";
import ERC20_ARTIFACT from "../../artifacts/contracts/mocks/TokenERC20.sol/TokenERC20.json";
import ACCOUNT_ARTIFACT from "../../artifacts/contracts/account/BondSmartAccount.sol/BondSmartAccount.json";
import ACCOUNT_FACTORY_ARTIFACT from "../../artifacts/contracts/factory/BondAccountFactory.sol/BondAccountFactory.json";
import ENTRYPOINT_ARTIFACT from "../../utils/EntrypontV06.json"
import { encodeFunctionData, Hex, parseUnits, getContract, recoverAddress, hashMessage } from "viem";
import { getDummySignatureByTotalSignersLength, getPaymasterData, getProviderFromChainId, getUserOpReceipt, sleep, toBytes32Salt } from "../../utils/helpers.js";
import { ENTRYPOINT_ADDRESS, FACTORY_ADDRESS } from "../../utils/constants.js";

import "dotenv/config"
import { UserOperationStruct } from "../../types/global.types.js";
import { protocolAddress } from "../configs.js";

const { viem } = await network.connect();

const accountSalt = toBytes32Salt(1);

const publicClient = await viem.getPublicClient();
const [senderClient] = await viem.getWalletClients();

const intentId = "0xe00a586acdd9dad9c8c47b25f506c65066937b92526fabf466c7b616e04de4fe";
// const accountAddress = "0xCae1e3c19868Bd248742D01284d83e486822753f";

const protocol = await viem.getContractAt("BondProtocol", protocolAddress);
const resp = await protocol.read.getIntent([intentId]);

console.log(resp);

try {

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

    const paymasterData = await getPaymasterData(publicClient.chain.id, userOp)

    console.log("paymasterData:", paymasterData);

    userOp.paymasterAndData = paymasterData.paymasterAndData;
    userOp.preVerificationGas = paymasterData.preVerificationGas;
    userOp.verificationGasLimit = paymasterData.verificationGasLimit;
    userOp.callGasLimit = paymasterData.callGasLimit;

    console.log("Signer address:", senderClient.account.address);
    // console.log("recoveredAddress:", recoveredAddress);

    const opTxHash = await pimlicoPublicClient.send("eth_sendUserOperation", [
        userOp,
        ENTRYPOINT_ADDRESS,
    ]);

    console.log("user op hash:", opTxHash)

    await sleep(10);

    const receipt = await getUserOpReceipt(publicClient.chain.id, opTxHash);

    console.log("Tx:", receipt.transactionHash);
} catch (e) {
    console.log("Error:", e);
}