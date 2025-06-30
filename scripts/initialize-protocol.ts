import { network } from "hardhat";
import { deployment_configs, getChainNameFromId } from "./configs.js";

type SupportedChains = "polygon_amoy" | "avalanche_fuji" | "sepolia" | "arbitrum_sepolia" ;

async function main() {
    try {
        const { viem } = await network.connect();

        const publicClient = await viem.getPublicClient();

        const chainName = getChainNameFromId(publicClient.chain.id);
        console.log(chainName);
        const deploymentConfigChain = deployment_configs[chainName];

        const protocolContract = await viem.getContractAt("BondProtocol", deploymentConfigChain.protocol);
        const bridgeContract = await viem.getContractAt("BondBridge", deploymentConfigChain.bridge);

        console.log("initialize protocol & bridge ...");
        // initialize protocol & bridge
        for (const e of deploymentConfigChain.allowed_chainselectors) {
            console.log(`Protocol Peering chainId with chain selectors: (id:${e.chain_id} - selector:${e.chain_selector})`);
            await protocolContract.write.peerChainIdandChainSelector([BigInt(e.chain_id), BigInt(e.chain_selector)]);
            console.log("done");

            console.log(`Bridge allowing destination chain selector ${e.chain_selector}`);
            await bridgeContract.write.allowlistDestinationChain([BigInt(e.chain_selector), true]);
            console.log("done");

            console.log(`Bridge allowing source chain selector ${e.chain_selector}`);
            await bridgeContract.write.allowlistSourceChain([BigInt(e.chain_selector), true]);
            console.log("done");
        }
        console.log("initialization Completed");

        const _chains = Object.keys({...deployment_configs}).filter((e) => e != chainName && e != 'local') as SupportedChains[] ;
        console.log(_chains);

        for (const e of _chains) {
            console.log(`Configuring allow list sender & bridge address: selector:${deployment_configs[e].chain_selector}, bridge: ${deployment_configs[e].bridge}`)
            await bridgeContract.write.configureAllowListedSender([deployment_configs[e].bridge, true])
            await bridgeContract.write.configureDestinationBridgeAddress([BigInt(deployment_configs[e].chain_selector), deployment_configs[e].bridge])
            console.log("configured")
        }
        
        // create pool
        console.log("Protocol creating pool ...")
        for (const e of deploymentConfigChain.pools) {
            console.log(`Creating ${e.id}`);
            await protocolContract.write.createPool([
                BigInt(e.id),
                e.underlying_token,
                e.supply_token_name,
                e.supply_token_symbol,
            ]);
            console.log("done");
        }
        console.log("Initializing Chainlink LINKUSD aggregator")
        protocolContract.write.initializeLinkUsdAggregator([deploymentConfigChain.linkusd_aggregator]);
        console.log("INITIALIZATION COMPLETE")
    } catch (e) {
        console.log("Error:", e)
    };
}

main().catch((e) => {
    console.log("Error:", e)
})
