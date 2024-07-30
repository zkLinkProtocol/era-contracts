import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-verify";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-ethers";
import "hardhat-typechain";

// If no network is specified, use the default config
if (!process.env.CHAIN_ETH_NETWORK) {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  require("dotenv").config();
}

export default {
  zksolc: {
    version: "1.3.18",
    compilerSource: "binary",
    settings: {
      isSystem: true,
    },
  },
  solidity: {
    version: "0.8.20",
  },
  defaultNetwork: "env",
  networks: {
    env: {
      url: process.env.API_WEB3_JSON_RPC_HTTP_URL,
      ethNetwork: process.env.ETH_CLIETN_WEB3_URL,
      zksync: true,
      verifyURL: process.env.CONTRACT_VERIFIER_URL,
    },
  },
};
