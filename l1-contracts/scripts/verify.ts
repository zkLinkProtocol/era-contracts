import * as hardhat from "hardhat";
import { deployedAddressesFromEnv, getAddressFromEnv, getNumberFromEnv, web3Provider } from "../scripts/utils";
import { Deployer } from "../src.ts/deploy";
import { Wallet } from "ethers";

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
  const addresses = deployedAddressesFromEnv();

  // Contracts without constructor parameters
  // verify Getter contract
  console.log(`Verifying GettersFacet contract: ${addresses.ZkSync.GettersFacet}`);
  await verifyPromise(addresses.ZkSync.GettersFacet);
  // verify DiamondInit contract
  console.log(`Verifying DiamondInit contract: ${addresses.ZkSync.DiamondInit}`);
  await verifyPromise(addresses.ZkSync.DiamondInit);
  // verify AdminFacet contract
  console.log(`Verifying AdminFacet contract: ${addresses.ZkSync.AdminFacet}`);
  await verifyPromise(addresses.ZkSync.AdminFacet);
  // verify MailboxFacet contract
  console.log(`Verifying MailboxFacet contract: ${addresses.ZkSync.MailboxFacet}`);
  await verifyPromise(addresses.ZkSync.MailboxFacet);
  // verify ExecutorFacet contract
  console.log(`Verifying ExecutorFacet contract: ${addresses.ZkSync.ExecutorFacet}`);
  await verifyPromise(addresses.ZkSync.ExecutorFacet);
  // verify Verifier contract
  console.log(`Verifying Verifier contract: ${addresses.ZkSync.Verifier}`);
  await verifyPromise(addresses.ZkSync.Verifier);

  // Proxy
  const provider = web3Provider();
  const wallet = new Wallet(process.env.GOVERNOR_PRIVATE_KEY, provider);
  // Create dummy deployer to get constructor parameters for diamond proxy
  const deployer = new Deployer({
    deployWallet: wallet,
  });

  const chainId = process.env.ETH_CLIENT_CHAIN_ID;
  const constructorArguments = [chainId, await deployer.initialProxyDiamondCut()];
  console.log(`Verifying DiamondProxy contract: ${addresses.ZkSync.DiamondProxy}`);
  await verifyPromise(addresses.ZkSync.DiamondProxy, constructorArguments);

  // Bridges
  // verify ERC20BridgeImplementation contract
  console.log(`Verifying ERC20BridgeImplementation contract: ${addresses.Bridges.ERC20BridgeImplementation}`);
  await verifyPromise(addresses.Bridges.ERC20BridgeImplementation, [addresses.ZkSync.DiamondProxy]);
  // verify ERC20BridgeProxy contract
  console.log(`Verifying ERC20BridgeProxy contract: ${addresses.Bridges.ERC20BridgeProxy}`);
  await verifyPromise(addresses.Bridges.ERC20BridgeProxy, [
    addresses.Bridges.ERC20BridgeImplementation,
    process.env.GOVERNOR_ADDRESS,
    "0x",
  ]);
  // verify wETHBridgeImplementation contract
  console.log(`Verifying wETHBridgeImplementation contract: ${addresses.Bridges.WethBridgeImplementation}`);
  await verifyPromise(addresses.Bridges.WethBridgeImplementation, [
    process.env.CONTRACTS_L1_WETH_TOKEN_ADDR,
    addresses.ZkSync.DiamondProxy,
  ]);
  // verify wETHBridgeProxy contract
  console.log(`Verifying wETHBridgeProxy contract: ${addresses.Bridges.WethBridgeProxy}`);
  await verifyPromise(addresses.Bridges.WethBridgeProxy, [
    addresses.Bridges.WethBridgeImplementation,
    process.env.GOVERNOR_ADDRESS,
    "0x",
  ]);
  // wETH
  // verify wETH token
  console.log(`Verifying wETH token: ${process.env.CONTRACTS_L1_WETH_TOKEN_ADDR}`);
  await verifyPromise(process.env.CONTRACTS_L1_WETH_TOKEN_ADDR);

  // validator timelock
  console.log(`Verifying ValidatorTimeLock contract: ${addresses.ValidatorTimeLock}`);
  await verifyPromise(addresses.ValidatorTimeLock, [
    getAddressFromEnv("GOVERNOR_ADDRESS"),
    addresses.ZkSync.DiamondProxy,
    getNumberFromEnv("CONTRACTS_VALIDATOR_TIMELOCK_EXECUTION_DELAY"),
    getAddressFromEnv("ETH_SENDER_SENDER_OPERATOR_COMMIT_ETH_ADDR"),
  ]);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err.message || err);
    process.exit(1);
  });
