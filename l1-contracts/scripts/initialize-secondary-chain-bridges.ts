import { Command } from "commander";
import { ethers, Wallet } from "ethers";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { SYSTEM_CONFIG } from "./utils";
import {
  applyL1ToL2Alias,
  computeL2Create2Address,
  getAddressFromEnv,
  getNumberFromEnv,
  hashL2Bytecode,
  ethTestConfig,
} from "../src.ts/utils";

import * as fs from "fs";
import * as path from "path";
const contractArtifactsPath = path.join(process.env.ZKSYNC_HOME as string, "contracts/l2-contracts/artifacts-zk/");

const l2BridgeArtifactsPath = path.join(contractArtifactsPath, "cache-zk/solpp-generated-contracts/bridge/");

const openzeppelinTransparentProxyArtifactsPath = path.join(
  contractArtifactsPath,
  "@openzeppelin/contracts/proxy/transparent/"
);
const openzeppelinBeaconProxyArtifactsPath = path.join(contractArtifactsPath, "@openzeppelin/contracts/proxy/beacon");

function readBytecode(path: string, fileName: string) {
  return JSON.parse(fs.readFileSync(`${path}/${fileName}.sol/${fileName}.json`, { encoding: "utf-8" })).bytecode;
}

function readInterface(path: string, fileName: string) {
  const abi = JSON.parse(fs.readFileSync(`${path}/${fileName}.sol/${fileName}.json`, { encoding: "utf-8" })).abi;
  return new ethers.utils.Interface(abi);
}

const L2_ERC20_BRIDGE_PROXY_BYTECODE = readBytecode(
  openzeppelinTransparentProxyArtifactsPath,
  "TransparentUpgradeableProxy"
);
const L2_ERC20_BRIDGE_PROXY_BYTECODE_HASH = ethers.utils.sha256(L2_ERC20_BRIDGE_PROXY_BYTECODE);
const L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE = readBytecode(l2BridgeArtifactsPath, "L2ERC20Bridge");
const L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE_HASH = ethers.utils.sha256(L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE);
const L2_STANDARD_ERC20_IMPLEMENTATION_BYTECODE = readBytecode(l2BridgeArtifactsPath, "L2StandardERC20");
const L2_STANDARD_ERC20_PROXY_BYTECODE = readBytecode(openzeppelinBeaconProxyArtifactsPath, "BeaconProxy");
const L2_STANDARD_ERC20_PROXY_BYTECODE_HASH = ethers.utils.sha256(L2_STANDARD_ERC20_PROXY_BYTECODE);
const L2_STANDARD_ERC20_PROXY_FACTORY_BYTECODE = readBytecode(
  openzeppelinBeaconProxyArtifactsPath,
  "UpgradeableBeacon"
);
const L2_ERC20_BRIDGE_INTERFACE = readInterface(l2BridgeArtifactsPath, "L2ERC20Bridge");
const DEPLOY_L2_BRIDGE_COUNTERPART_GAS_LIMIT = getNumberFromEnv("CONTRACTS_DEPLOY_L2_BRIDGE_COUNTERPART_GAS_LIMIT");
const CONTRACTS_MERGE_TOKEN_PORTAL_ADDR = getAddressFromEnv("CONTRACTS_MERGE_TOKEN_PORTAL_ADDR");
const L2_ERC20_BRIDGE_CONSTRUCTOR_DATA = new ethers.utils.AbiCoder().encode(
  ["address"],
  [CONTRACTS_MERGE_TOKEN_PORTAL_ADDR]
);
console.log(`L2 ERC20 bridge constructor data: ${L2_ERC20_BRIDGE_CONSTRUCTOR_DATA}`);

async function main() {
  const program = new Command();

  program.version("0.1.0").name("initialize-secondary-chain-bridges");

  program
    .requiredOption("--erc20-bridge-artifacts-path <l1-bridge-artifacts-path>")
    .requiredOption("--zklink-artifacts-path <zklink-artifacts-path>")
    .requiredOption("--erc20-bridge <erc20-bridge>")
    .requiredOption("--zklink <zklink>")
    .requiredOption("--web3-url <web3-url>")
    .option("--private-key <private-key>")
    .option("--gas-price <gas-price>")
    .option("--nonce <nonce>")
    .action(async (cmd) => {
      const web3Url = cmd.web3Url;
      const provider = new ethers.providers.JsonRpcProvider(web3Url);
      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/0"
          ).connect(provider);
      console.log(`Using deployer wallet: ${deployWallet.address}`);

      const gasPrice = cmd.gasPrice ? parseUnits(cmd.gasPrice, "gwei") : await provider.getGasPrice();
      console.log(`Using gas price: ${formatUnits(gasPrice, "gwei")} gwei`);

      const nonce = cmd.nonce ? parseInt(cmd.nonce) : await deployWallet.getTransactionCount();
      console.log(`Using nonce: ${nonce}`);

      const ZKLINK_INTERFACE = readInterface(cmd.zklinkArtifactsPath, "ZkLink");
      const L1_ERC20_BRIDGE_INTERFACE = readInterface(cmd.erc20BridgeArtifactsPath, "L1ERC20Bridge");

      const zkLink = ethers.ContractFactory.getContract(cmd.zklink, ZKLINK_INTERFACE, deployWallet);
      const erc20Bridge = ethers.ContractFactory.getContract(cmd.erc20Bridge, L1_ERC20_BRIDGE_INTERFACE, deployWallet);

      const l1GovernorAddress = await zkLink.getGovernor();
      console.log(`L1 governor address: ${l1GovernorAddress}`);
      // Check whether governor is a smart contract on L1 to apply alias if needed.
      const l1GovernorCodeSize = ethers.utils.hexDataLength(await deployWallet.provider.getCode(l1GovernorAddress));
      const l2GovernorAddress = l1GovernorCodeSize == 0 ? l1GovernorAddress : applyL1ToL2Alias(l1GovernorAddress);
      console.log(`L2 governor address: ${l2GovernorAddress}`);
      const abiCoder = new ethers.utils.AbiCoder();

      const l2ERC20BridgeImplAddr = computeL2Create2Address(
        applyL1ToL2Alias(erc20Bridge.address),
        L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE,
        "0x",
        ethers.constants.HashZero
      );

      const proxyInitializationParams = L2_ERC20_BRIDGE_INTERFACE.encodeFunctionData("initialize", [
        erc20Bridge.address,
        hashL2Bytecode(L2_STANDARD_ERC20_PROXY_BYTECODE),
        l2GovernorAddress,
      ]);
      const l2ERC20BridgeProxyAddr = computeL2Create2Address(
        applyL1ToL2Alias(erc20Bridge.address),
        L2_ERC20_BRIDGE_PROXY_BYTECODE,
        ethers.utils.arrayify(
          abiCoder.encode(
            ["address", "address", "bytes"],
            [l2ERC20BridgeImplAddr, l2GovernorAddress, proxyInitializationParams]
          )
        ),
        ethers.constants.HashZero
      );

      const l2StandardToken = computeL2Create2Address(
        l2ERC20BridgeProxyAddr,
        L2_STANDARD_ERC20_IMPLEMENTATION_BYTECODE,
        "0x",
        ethers.constants.HashZero
      );
      const l2TokenFactoryAddr = computeL2Create2Address(
        l2ERC20BridgeProxyAddr,
        L2_STANDARD_ERC20_PROXY_FACTORY_BYTECODE,
        ethers.utils.arrayify(abiCoder.encode(["address"], [l2StandardToken])),
        ethers.constants.HashZero
      );

      // There will be two deployments done during the initial initialization
      const primaryGasPrice = await zkLink.txGasPrice();
      console.log(`Using primary gas price: ${formatUnits(primaryGasPrice, "gwei")} gwei`);
      const requiredValueToInitializeBridge = await zkLink.l2TransactionBaseCost(
        primaryGasPrice,
        DEPLOY_L2_BRIDGE_COUNTERPART_GAS_LIMIT,
        SYSTEM_CONFIG.requiredL2GasPricePerPubdata
      );

      const tx = await erc20Bridge.initialize(
        [L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE, L2_ERC20_BRIDGE_PROXY_BYTECODE, L2_STANDARD_ERC20_PROXY_BYTECODE],
        [
          L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE_HASH,
          L2_ERC20_BRIDGE_PROXY_BYTECODE_HASH,
          L2_STANDARD_ERC20_PROXY_BYTECODE_HASH,
        ],
        L2_ERC20_BRIDGE_CONSTRUCTOR_DATA,
        l2TokenFactoryAddr,
        l2GovernorAddress,
        requiredValueToInitializeBridge,
        requiredValueToInitializeBridge,
        {
          gasPrice,
          nonce,
          value: requiredValueToInitializeBridge.mul(2),
        }
      );
      console.log(`Transaction sent with hash ${tx.hash} and nonce ${tx.nonce}. Waiting for receipt...`);
      const receipt = await tx.wait(2);
      console.log(`ERC20 bridge initialized, gasUsed: ${receipt.gasUsed.toString()}`);
      console.log(`CONTRACTS_L2_ERC20_BRIDGE_ADDR=${await erc20Bridge.l2Bridge()}`);
    });

  await program.parseAsync(process.argv);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
