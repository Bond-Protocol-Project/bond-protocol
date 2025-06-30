import { network } from "hardhat";
import { deployment_configs, getChainNameFromId } from "../configs.js";
import { Hex } from "viem";

type SupportedChains = "polygon_amoy" | "avalanche_fuji" | "sepolia" | "arbitrum_sepolia" ;

const newBridge = {
    polygon_amoy: "0x7E60C904CdfcF25d7e7e8c245Ffce4B7d99E1D68" as Hex,
    sepolia: "0x5e1c84B064a8232D735Bc3B3fd06fB1589ba1208" as Hex,
    arbitrum_sepolia: "0xEbae7530DEb9b106595025B1a4208354102B0867" as Hex,
    avalanche_fuji: "0x8Bb975F66f5bBE04be7991D78BB7CB92E8250950" as Hex
}

async function main() {
    try {
        const { viem } = await network.connect();

        const publicClient = await viem.getPublicClient();

        const chainName = getChainNameFromId(publicClient.chain.id);
        console.log(chainName);
        const deploymentConfigChain = deployment_configs[chainName];

        const protocolContract = await viem.getContractAt("BondProtocol", deploymentConfigChain.protocol);
        const bridgeContract = await viem.getContractAt("BondBridge", deploymentConfigChain.bridge);

        console.log(`Withdrawing from bridge ... from:${bridgeContract.address} to ${newBridge[chainName as SupportedChains]}`);

        await bridgeContract.write.withdrawToken([newBridge[chainName as SupportedChains], deployment_configs[chainName].link_token]);
        
        console.log("WITHDRAWAL COMPLETE")
    } catch (e) {
        console.log("Error:", e)
    };
}

main().catch((e) => {
    console.log("Error:", e)
})
