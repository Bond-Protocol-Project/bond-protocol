import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { network } from "hardhat";
import { deployment_configs, getChainNameFromId } from "../../scripts/configs.js";

const { viem } = await network.connect();
const publicClient = await viem.getPublicClient();
const chainName = getChainNameFromId(publicClient.chain.id);
const deploymentConfigChain = deployment_configs[chainName];

// const ProtocolModule = buildModule("ProtocolModule", (m) => {
//     const protocol = m.contract("BondProtocol", [m.getAccount(0)]);

//     return { protocol };
// });

const BridgeModule = buildModule("BridgeModuleV4", (m) => {
    // const { protocol } = m.useModule(ProtocolModule);
    const bridge = m.contract("BondBridge", [
        deploymentConfigChain.link_router,
        deploymentConfigChain.link_token,
        "0x1F4899e17F9eEc08B91a48f8A5be12Bca14F18a6",
        m.getAccount(0)
    ]);

    return { bridge };
});

// const PoolTokenFactoryModule = buildModule("PoolTokenFactoryModule", (m) => {
//     const lpFactory = m.contract("LPTokenFactory", [m.getAccount(0)]);

//     return { lpFactory };
// });

// const PoolModule = buildModule("PoolModule", (m) => {
//     const { protocol } = m.useModule(ProtocolModule);
//     const { bridge } = m.useModule(BridgeModule);
//     const { lpFactory } = m.useModule(PoolTokenFactoryModule);
//     const pool = m.contract("BondPool", [protocol, lpFactory]);

//     m.call(protocol, "initializeBridge", [bridge]);
//     m.call(protocol, "initializePool", [pool]);
//     m.call(lpFactory, "initializePool", [pool]);

//     return { pool };
// });

export default BridgeModule;