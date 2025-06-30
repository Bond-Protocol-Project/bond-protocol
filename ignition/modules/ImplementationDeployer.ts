import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ENTRYPOINT_ADDRESS } from "../../utils/constants.js";
import { protocolAddress } from "../../scripts/configs.js";

// export default buildModule("ImplementationDeployerModule", (m) => {
//     const implDeployer = m.contract("ImplementationDeployer", []);

//     const implSalt = "0x0000000000000000000000000000000000000000000000000000000000000000";
//     const factorySalt = "0x0000000000000000000000000000000000000000000000000000000000000000";

//     m.call(implDeployer, "deployAll", [ENTRYPOINT_ADDRESS, protocolAddress, implSalt, factorySalt]);

//     return { implDeployer };
// });

export default buildModule("ImplementationDeployerModuleV3", (m) => {
    const implDeployer = m.contract("ImplementationDeployer", []);

    const implSalt = "0x0000000000000000000000000000000000000000000000000000000000000000";
    const factorySalt = "0x0000000000000000000000000000000000000000000000000000000000000000";

    m.call(implDeployer, "deployAll", [ENTRYPOINT_ADDRESS, protocolAddress, implSalt, factorySalt]);

    return { implDeployer };
});