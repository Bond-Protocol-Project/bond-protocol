import { network } from "hardhat";
import { decodeIntentData, encodeIntentData } from "../../utils/helpers.js";
import { parseEther } from "viem";
import { deployment_configs, getChainNameFromId } from "../configs.js";


async function main() {
    const { viem } = await network.connect();

    const publicClient = await viem.getPublicClient();
    const [senderAccount] = await viem.getWalletClients();

    const chainName = getChainNameFromId(publicClient.chain.id);
    console.log(chainName);
    const deploymentConfigChain = deployment_configs[chainName];

    const protocolContract = await viem.getContractAt("BondProtocol", deploymentConfigChain.protocol);

    const _nonce = await protocolContract.read.getNonce([senderAccount.account.address]);
    console.log(_nonce);

    const intentData = encodeIntentData({
        sender: senderAccount.account.address,
        initChainSenderNonce: _nonce,
        initChainId: BigInt(publicClient.chain.id),
        poolId: 100001n,
        srcChainIds: [421614n, 43113n],
        srcAmounts: [parseEther('2'), parseEther('2')],
        dstChainId: 421614n,
        dstDatas: [
            {
                target: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
                value: parseEther('0.1'),
                data: '0x095ea7b3000000000000000000000000a0b86a33e6776e681c000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
            },
            {
                target: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
                value: 0n,
                data: '0xa9059cbb000000000000000000000000def1c0ded9bec7f1a1670819833240f027b25eff00000000000000000000000000000000000000000000000000000000000003e8'
            }
        ],
        expires: BigInt(Math.floor(Date.now() / 1000) + 3600) // 1 hour from now
    });

    // console.log("intentData:", decodeIntentData(intentData));

    const feeData = await protocolContract.read.getFees([intentData], {
        account: senderAccount.account.address
    });
    console.log("feeData:", feeData)

    // const poolData = await protocolContract.read.getPool([100001n], {
    //     account: senderAccount.account.address
    // });
    // console.log("poolData:", poolData)
}

main().catch((e) => {
    console.log("Error:", e)
});
