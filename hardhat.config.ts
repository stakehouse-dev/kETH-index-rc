require("dotenv").config();
import { task, HardhatUserConfig } from "hardhat/config";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "@openzeppelin/hardhat-upgrades";;
import "hardhat-deploy";
import "solidity-coverage";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const config: HardhatUserConfig = {
  solidity: {
    compilers: [{
      version: "0.8.19",
      settings: {
        outputSelection: {
          "*": {
            "*": ["storageLayout"]
          }
        },
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
    }]
  },
  typechain: {
    outDir: "types/",
    target: "ethers-v5",
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.GOERLI_URL!,
      },
      chainId: 5,
    },
    goerli: {
      url: process.env.GOERLI_URL!,
      accounts: [process.env.PRIVATE_KEY!],
    },
    mainnet: {
      url: process.env.MAINNET_URL!,
      accounts: [process.env.PRIVATE_KEY!],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  mocha: {
    timeout: 60 * 30 * 1000,
  },
};

export default config;
