import { Command } from "commander";
import { ethers, Wallet } from "ethers";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { Deployer } from "../src.ts/deploy";
import { applyL1ToL2Alias, computeL2Create2Address, getNumberFromEnv, hashL2Bytecode, SYSTEM_CONFIG } from "./utils";

import * as fs from "fs";
import * as path from "path";

const testConfigPath = path.join(process.env.ZKSYNC_HOME as string, "etc/test_config/constant");
const ethTestConfig = JSON.parse(fs.readFileSync(`${testConfigPath}/eth.json`, { encoding: "utf-8" }));

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
const L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE = readBytecode(l2BridgeArtifactsPath, "L2ERC20Bridge");
const L2_STANDARD_ERC20_IMPLEMENTATION_BYTECODE = readBytecode(l2BridgeArtifactsPath, "L2StandardERC20");
const L2_STANDARD_ERC20_PROXY_BYTECODE = readBytecode(openzeppelinBeaconProxyArtifactsPath, "BeaconProxy");
const L2_STANDARD_ERC20_PROXY_FACTORY_BYTECODE = readBytecode(
  openzeppelinBeaconProxyArtifactsPath,
  "UpgradeableBeacon"
);
const L2_ERC20_BRIDGE_INTERFACE = readInterface(l2BridgeArtifactsPath, "L2ERC20Bridge");
const DEPLOY_L2_BRIDGE_COUNTERPART_GAS_LIMIT = getNumberFromEnv("CONTRACTS_DEPLOY_L2_BRIDGE_COUNTERPART_GAS_LIMIT");

async function main() {
  const program = new Command();

  program.version("0.1.0").name("initialize-bridges");

  program
    .requiredOption("--web3-url <web3-url>")
    .option("--private-key <private-key>")
    .option("--gas-price <gas-price>")
    .option("--nonce <nonce>")
    .requiredOption("--erc20-bridge <erc20-bridge>")
    .requiredOption("--zksync <zksync>")
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

      const deployer = new Deployer({
        deployWallet,
        verbose: true,
      });

      const zkSync = deployer.zkSyncContract(deployWallet).attach(cmd.zksync);
      const erc20Bridge = cmd.erc20Bridgedeployer.defaultERC20Bridge(deployWallet).attach(cmd.erc20Bridge);

      const l1GovernorAddress = await zkSync.getGovernor();
      // Check whether governor is a smart contract on L1 to apply alias if needed.
      const l1GovernorCodeSize = ethers.utils.hexDataLength(await deployWallet.provider.getCode(l1GovernorAddress));
      const l2GovernorAddress = l1GovernorCodeSize == 0 ? l1GovernorAddress : applyL1ToL2Alias(l1GovernorAddress);
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
      const primaryChainTxGasPrice = await zkSync.txGasPrice();
      const requiredValueToInitializeBridge = await zkSync.l2TransactionBaseCost(
        primaryChainTxGasPrice,
        DEPLOY_L2_BRIDGE_COUNTERPART_GAS_LIMIT,
        SYSTEM_CONFIG.requiredL2GasPricePerPubdata
      );

      const tx = await erc20Bridge.initialize(
        [L2_ERC20_BRIDGE_IMPLEMENTATION_BYTECODE, L2_ERC20_BRIDGE_PROXY_BYTECODE, L2_STANDARD_ERC20_PROXY_BYTECODE],
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
