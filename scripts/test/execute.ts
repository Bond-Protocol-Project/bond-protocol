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

const { viem } = await network.connect();

const accountSalt = toBytes32Salt(1);

const publicClient = await viem.getPublicClient();
const [senderClient] = await viem.getWalletClients();

const tokenAddress = "0x587C3D85C9272484A6e40a8300290F55a4D5a589";
const erc20Token = await viem.getContractAt("TokenERC20", tokenAddress);
const getDecimals = await erc20Token.read.decimals();

const entrypoint = getContract({
    address: ENTRYPOINT_ADDRESS,
    abi: ENTRYPOINT_ARTIFACT.abi,
    client: senderClient,
});

const tnxArgs = ["0x85db92aD7a03727063D58846617C977B3Aaa3036", parseUnits('1', getDecimals)]
const tnxData = encodeFunctionData({
    abi: ERC20_ARTIFACT.abi,
    functionName: "transfer",
    args: tnxArgs,
});

const callDataArgs = [tokenAddress, 0, tnxData]
const userOpCallData = encodeFunctionData({
    abi: ACCOUNT_ARTIFACT.abi,
    functionName: "execute",
    args: callDataArgs,
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
console.log(code);

if (code !== undefined || code !== "0x") {
    initCode = "0x";
}
console.log(initCode);

const accountNonce: any = await entrypoint.read.getNonce([accountAddress, 0]);
console.log("accountNonce:", accountNonce);
console.log(accountNonce.toString());

const userOp: Partial<UserOperationStruct> = {
    sender: accountAddress as Hex, // smart account address
    nonce: "0x" + accountNonce.toString(16) as Hex,
    initCode: initCode as Hex,
    callData: userOpCallData,
    paymasterAndData: '0x',
    signature: getDummySignatureByTotalSignersLength(1),
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

const userOpHash = await entrypoint.read.getUserOpHash([userOp as UserOperationStruct]);

console.log("userOpHash:", userOpHash);

const userSignature = await senderClient.signMessage({
    account: senderClient.account,
    message: { raw: userOpHash as Hex }
});

console.log("userSignature:", userSignature);

userOp.signature = userSignature;

const messageHash = hashMessage({ raw: userOpHash as Hex });
const recoveredAddress = await recoverAddress({
    hash: messageHash,
    signature: userOp.signature
});

console.log("Signer address:", senderClient.account.address);
console.log("recoveredAddress:", recoveredAddress);

const opTxHash = await pimlicoPublicClient.send("eth_sendUserOperation", [
    userOp,
    ENTRYPOINT_ADDRESS,
]);

console.log("user op hash:", opTxHash)

await sleep(10);

const receipt = await getUserOpReceipt(publicClient.chain.id, opTxHash);

console.log("Tx:", receipt.transactionHash);