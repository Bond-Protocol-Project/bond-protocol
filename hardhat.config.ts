import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
import "dotenv/config"

const config: HardhatUserConfig = {
  /*
   * In Hardhat 3, plugins are defined as part of the Hardhat config instead of
   * being based on the side-effect of imports.
   *
   * Note: A `hardhat-toolbox` like plugin for Hardhat 3 hasn't been defined yet,
   * so this list is larger than what you would normally have.
   */
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    /*
     * Hardhat 3 supports different build profiles, allowing you to configure
     * different versions of `solc` and its settings for various use cases.
     *
     * Note: Using profiles is optional, and any Hardhat 2 `solidity` config
     * is still valid in Hardhat 3.
     */
    profiles: {
      /*
       * The default profile is used when no profile is defined or specified
       * in the CLI or by the tasks you are running.
       */
      default: {
        version: "0.8.28",
      },
      /*
       * The production profile is meant to be used for deployments, providing
       * more control over settings for production builds and taking some extra
       * steps to simplify the process of verifying your contracts.
       */
      production: {
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
    /*
     * Hardhat 3 natively supports remappings and makes extensive use of them
     * internally to fully support npm resolution rules (i.e., it supports
     * transitive dependencies, multiple versions of the same package,
     * monorepos, etc.).
     */
    remappings: [
      /*
       * This remapping is added to the example because most people import
       * forge-std/Test.sol, not forge-std/src/Test.sol.
       *
       * Note: The config currently leaks internal IDs, but this will be fixed
       * in the future.
       */
      "forge-std/=npm/forge-std@1.9.4/src/",
      "@account-abstraction/=node_modules/@account-abstraction/",
      "@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/",
      "@chainlink/contracts/=node_modules/@chainlink/contracts/",
      "@chainlink/contracts-ccip/=node_modules/@chainlink/contracts-ccip/"
    ],
  },
  /*
   * The `networks` configuration is mostly compatible with Hardhat 2.
   * The key differences right now are:
   *
   * - You must set a `type` for each network, which is either `edr` or `http`,
   *   allowing you to have multiple simulated networks.
   *
   * - You can set a `chainType` for each network, which is either `generic`,
   *   `l1`, or `optimism`. This has two uses. It ensures that you always
   *   connect to the network with the right Chain Type. And, on `edr`
   *   networks, it makes sure that the simulated chain behaves exactly like the
   *   real one. More information about this can be found in the test files.
   *
   * - The `accounts` field of `http` networks can also receive Configuration
   *   Variables, which are values that only get loaded when needed. This allows
   *   Hardhat to still run despite some of its config not being available
   *   (e.g., a missing private key or API key). More info about this can be
   *   found in the "Sending a Transaction to Optimism Sepolia" of the README.
   */

  // defaultNetwork: "sepolia",

  networks: {
    hardhatMainnet: {
      type: "edr",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr",
      chainType: "optimism",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.ETHEREUM_SEPOLIA_RPC_URL!,
      accounts: [process.env.TEST_PRIVATE_KEY!, process.env.TEST_PRIVATE_KEY2!, process.env.TEST_PRIVATE_KEY3!],
    },
    polygon_amoy: {
      type: "http",
      chainType: "l1",
      url: process.env.POLYGON_AMOY_RPC_URL!,
      accounts: [process.env.TEST_PRIVATE_KEY!, process.env.TEST_PRIVATE_KEY2!, process.env.TEST_PRIVATE_KEY3!],
    },
    arbitrum_sepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL!,
      accounts: [process.env.TEST_PRIVATE_KEY!, process.env.TEST_PRIVATE_KEY2!, process.env.TEST_PRIVATE_KEY3!],
    },
    avalanche_fuji: {
      type: "http",
      chainType: "l1",
      url: process.env.AVALANCHE_FUJI_RPC_URL!,
      accounts: [process.env.TEST_PRIVATE_KEY!, process.env.TEST_PRIVATE_KEY2!, process.env.TEST_PRIVATE_KEY3!],
      gasPrice: 5000000000
    },
  },

  ignition: {
    strategyConfig: {
      create2: {
        // To learn more about salts, see the CreateX documentation
        salt: "0x0000000000000000000000000000000000000000000000000000000000000014",
      },
    },
  },
};

export default config;
