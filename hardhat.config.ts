import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import { HardhatUserConfig } from "hardhat/types";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-etherscan";
import "solidity-coverage";

const PRIVATE_KEY =
  process.env.PRIVATE_KEY! ||
  "c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"; // well known private key
const BSCSCAN_API_KEY = process.env.BSCSCAN_API_KEY;

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    compilers: [{ version: "0.8.12", settings: {} }],
  },
  networks: {
    hardhat: {},
    localhost: {},
    testnet: {
      url: "https://rpc.ankr.com/eth_goerli",
      chainId: 5,
      gas: 2100000,
      gasPrice: 20000000000,
      accounts: [PRIVATE_KEY]
    },
    mainnet: {
      url: "https://rpc.ankr.com/eth",
      chainId: 1,
      gas: 2100000,
      gasPrice: 20000000000,
      accounts: [PRIVATE_KEY]
    },
    coverage: {
      url: "http://127.0.0.1:8555", // Coverage launches its own ganache-cli client
    },
  },
  etherscan: {
    // Your API key for BscScan
    // Obtain one at https://bscscan.com/
    apiKey: BSCSCAN_API_KEY,
  },
};

export default config;
