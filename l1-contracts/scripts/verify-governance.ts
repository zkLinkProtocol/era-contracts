import * as hardhat from "hardhat";
import { web3Provider } from "./utils";
import { ethers, Wallet } from "ethers";

const provider = web3Provider();

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function verifyPromise(address: string, constructorArguments?: Array<any>, libraries?: object): Promise<any> {
  return new Promise((resolve, reject) => {
    hardhat
      .run("verify:verify", { address, constructorArguments, libraries })
      .then(() => resolve(`Successfully verified ${address}`))
      .catch((e) => reject(`Failed to verify ${address}\nError: ${e.message}`));
  });
}

async function main() {
  if (process.env.CHAIN_ETH_NETWORK == "localhost") {
    console.log("Skip contract verification on localhost");
    return;
  }

  if (!process.env.MISC_ETHERSCAN_API_KEY) {
    console.log("Skip contract verification given etherscan api key is missing");
    return;
  }

  const deployWallet = new Wallet(process.env.GOVERNOR_PRIVATE_KEY, provider);
  const governanceAddress = process.env.CONTRACTS_GOVERNANCE_ADDR;

  console.log(`Verifying governance contract: ${governanceAddress}`);
  await verifyPromise(governanceAddress, [deployWallet.address, ethers.constants.AddressZero, 0]);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err.message || err);
    process.exit(1);
  });
