// hardhat import should be the first import in the file
import * as hardhat from "hardhat";
import { deployedAddressesFromEnv } from "../src.ts/deploy-utils";
import { getNumberFromEnv, getHashFromEnv, getAddressFromEnv } from "../src.ts/utils";

import { Interface } from "ethers/lib/utils";
import { Deployer } from "../src.ts/deploy";
import { ethers, Wallet } from "ethers";
import { packSemver, unpackStringSemVer, web3Provider } from "./utils";
import { getTokens } from "../src.ts/deploy-token";

const provider = web3Provider();

function verifyPromise(
  address: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  constructorArguments?: Array<any>,
  libraries?: object,
  contract?: string
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<any> {
  return new Promise((resolve, reject) => {
    hardhat
      .run("verify:verify", {
        address,
        constructorArguments,
        libraries,
        contract,
      })
      .then(() => resolve(`Successfully verified ${address}`))
      .catch((e) => reject(`Failed to verify ${address}\nError: ${e.message}`));
  });
}

// Note: running all verifications in parallel might be too much for etherscan, comment out some of them if needed
async function main() {
  if (process.env.CHAIN_ETH_NETWORK == "localhost") {
    console.log("Skip contract verification on localhost");
    return;
  }
  if (!process.env.MISC_ETHERSCAN_API_KEY) {
    console.log("Skip contract verification given etherscan api key is missing");
    return;
  }
  if (!process.env.DEPLOYER_PRIVATE_KEY) {
    console.log("Skip contract verification deployer private key is missing");
    return;
  }
  const addresses = deployedAddressesFromEnv();

  const deployWallet = new Wallet(process.env.DEPLOYER_PRIVATE_KEY, provider);
  const deployWalletAddress = await deployWallet.getAddress();
  const deployer = new Deployer({
    deployWallet,
    addresses: deployedAddressesFromEnv(),
    ownerAddress: deployWalletAddress,
    verbose: true,
  });
  // TODO: Restore after switching to hardhat tasks (SMA-1711).
  // promises.push(verifyPromise(addresses.AllowList, [governor]));

  // Proxy
  // {
  //     Create dummy deployer to get constructor parameters for diamond proxy
  //     const deployer = new Deployer({
  //         deployWallet: ethers.Wallet.createRandom(),
  //         governorAddress: governor
  //     });

  //     const chainId = process.env.ETH_CLIENT_CHAIN_ID;
  //     const constructorArguments = [chainId, await deployer.initialProxyDiamondCut()];
  //     const promise = verifyPromise(addresses.ZkSync.DiamondProxy, constructorArguments);
  //     promises.push(promise);
  // }

  const executionDelay = getNumberFromEnv("CONTRACTS_VALIDATOR_TIMELOCK_EXECUTION_DELAY");
  const eraChainId = getNumberFromEnv("CONTRACTS_ERA_CHAIN_ID");
  await verifyPromise(addresses.ValidatorTimeLock, [deployWalletAddress, executionDelay, eraChainId]);

  await verifyPromise(addresses.Governance, [deployWalletAddress, ethers.constants.AddressZero, 0]);

  await verifyPromise(addresses.ChainAdmin, [deployWalletAddress]);

  if (process.env.CONTRACTS_HYPERCHAIN_UPGRADE_ADDR) {
    await verifyPromise(process.env.CONTRACTS_HYPERCHAIN_UPGRADE_ADDR);
  }

  await verifyPromise(addresses.TransparentProxyAdmin);

  // bridgehub

  await verifyPromise(addresses.Bridgehub.BridgehubImplementation);
  const bridgehub = new Interface(hardhat.artifacts.readArtifactSync("Bridgehub").abi);
  const initCalldata1 = bridgehub.encodeFunctionData("initialize", [deployWalletAddress]);
  await verifyPromise(addresses.Bridgehub.BridgehubProxy, [
    addresses.Bridgehub.BridgehubImplementation,
    addresses.TransparentProxyAdmin,
    initCalldata1,
  ]);

  // stm

  // Contracts without constructor parameters
  for (const address of [
    addresses.StateTransition.GettersFacet,
    addresses.StateTransition.DiamondInit,
    addresses.StateTransition.AdminFacet,
    addresses.StateTransition.ExecutorFacet,
    addresses.StateTransition.Verifier,
    addresses.StateTransition.GenesisUpgrade,
    addresses.StateTransition.DefaultUpgrade,
  ]) {
    await verifyPromise(address);
  }

  // Verify DiamondProxy, we get the real diamond cut from deploy log
  const chainId = process.env.ETH_CLIENT_CHAIN_ID;
  const dpI = new Interface(hardhat.artifacts.readArtifactSync("Diamond").abi);
  const dcEventTopic = dpI.getEventTopic("DiamondCut");
  const tr = await provider.getTransactionReceipt(process.env.CONTRACTS_HYPERCHAIN_DEPLOY_TX);
  const logs = tr.logs.filter((log) => {
    return log.topics[0] === dcEventTopic;
  });
  if (logs.length === 0) {
    console.log("Diamond deploy log not found");
    return;
  }
  const log = logs[0];
  const dc = dpI.decodeEventLog("DiamondCut", log.data);
  await verifyPromise(addresses.StateTransition.DiamondProxy, [chainId, dc]);

  const stateTransitionManager = new Interface(hardhat.artifacts.readArtifactSync("StateTransitionManager").abi);
  const genesisBatchHash = getHashFromEnv("CONTRACTS_GENESIS_ROOT"); // TODO: confusing name
  const genesisRollupLeafIndex = getNumberFromEnv("CONTRACTS_GENESIS_ROLLUP_LEAF_INDEX");
  const genesisBatchCommitment = getHashFromEnv("CONTRACTS_GENESIS_BATCH_COMMITMENT");
  const diamondCut = await deployer.initialZkSyncHyperchainDiamondCut([]);
  const protocolVersion = packSemver(...unpackStringSemVer(process.env.CONTRACTS_GENESIS_PROTOCOL_SEMANTIC_VERSION));

  const initCalldata2 = stateTransitionManager.encodeFunctionData("initialize", [
    {
      owner: addresses.Governance,
      validatorTimelock: addresses.ValidatorTimeLock,
      chainCreationParams: {
        genesisUpgrade: addresses.StateTransition.GenesisUpgrade,
        genesisBatchHash,
        genesisIndexRepeatedStorageChanges: genesisRollupLeafIndex,
        genesisBatchCommitment,
        diamondCut,
      },
      protocolVersion,
    },
  ]);

  await verifyPromise(addresses.StateTransition.StateTransitionProxy, [
    addresses.StateTransition.StateTransitionImplementation,
    addresses.TransparentProxyAdmin,
    initCalldata2,
  ]);

  // bridges
  await verifyPromise(
    addresses.Bridges.ERC20BridgeImplementation,
    [addresses.Bridges.SharedBridgeProxy],
    undefined,
    "contracts/bridge/L1ERC20Bridge.sol:L1ERC20Bridge"
  );
  const initCalldata3 = new Interface(hardhat.artifacts.readArtifactSync("L1ERC20Bridge").abi).encodeFunctionData(
    "initialize",
    []
  );
  await verifyPromise(addresses.Bridges.ERC20BridgeProxy, [
    addresses.Bridges.ERC20BridgeImplementation,
    addresses.TransparentProxyAdmin,
    initCalldata3,
  ]);

  const eraDiamondProxy = getAddressFromEnv("CONTRACTS_ERA_DIAMOND_PROXY_ADDR");
  const tokens = getTokens();
  const l1WethToken = tokens.find((token: { symbol: string }) => token.symbol == "WETH")!.address;

  await verifyPromise(addresses.Bridges.SharedBridgeImplementation, [
    l1WethToken,
    addresses.Bridgehub.BridgehubProxy,
    eraChainId,
    eraDiamondProxy,
  ]);
  const initCalldata4 = new Interface(hardhat.artifacts.readArtifactSync("L1SharedBridge").abi).encodeFunctionData(
    "initialize",
    [deployWalletAddress]
  );
  await verifyPromise(addresses.Bridges.SharedBridgeProxy, [
    addresses.Bridges.SharedBridgeImplementation,
    addresses.TransparentProxyAdmin,
    initCalldata4,
  ]);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err.message || err);
    process.exit(1);
  });
