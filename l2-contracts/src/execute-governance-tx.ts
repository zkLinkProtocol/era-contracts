import * as hre from "hardhat";
import { Command } from "commander";
import { Wallet, ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";
import { IGovernanceFactory } from "../../l1-contracts/typechain/IGovernanceFactory";
import { getAddressFromEnv, web3Provider } from "../../l1-contracts/scripts/utils";

const SupportedGovernanceFunctions = ["scheduleTransparent", "scheduleShadow", "execute", "executeInstant"] as const;
type SupportedGovernanceFunction = (typeof SupportedGovernanceFunctions)[number];

const provider = web3Provider();
const testConfigPath = path.join(process.env.ZKSYNC_HOME as string, "etc/test_config/constant");
const ethTestConfig = JSON.parse(fs.readFileSync(`${testConfigPath}/eth.json`, { encoding: "utf-8" }));

const governanceAddress = getAddressFromEnv("CONTRACTS_GOVERNANCE_ADDR");

async function sendTxToGovernance(wallet: Wallet, data: string, value: ethers.BigNumber = ethers.BigNumber.from(0)) {
  const tx = await wallet.sendTransaction({ to: governanceAddress, data: data, value: value });
  console.log(`Transaction sent: ${tx.hash}`);
  await tx.wait();
  console.log("Transaction executed");
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function checkSupportedGovernanceFunction(func: any): func is SupportedGovernanceFunction {
  if (!SupportedGovernanceFunctions.includes(func)) {
    throw new Error(`Unsupported function: ${func}`);
  }

  return true;
}

async function main() {
  const program = new Command();
  program.version("0.1.0").name("execute-governance-transaction").description("Execute governance transactions");

  program
    .command("schedule-transparent")
    .requiredOption("--call-data <schedule-transparent-calldata>")
    .option("--private-key <private-key>")
    .action(async (cmd) => {
      // We deploy the target contract through L1 to ensure security
      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider);

      const callData = cmd.callData;
      await sendTxToGovernance(deployWallet, callData);
    });

  program
    .command("execute")
    .requiredOption("--call-data <execute-call-data>")
    .option("--private-key <private-key>")
    .option("--value <value>")
    .action(async (cmd) => {
      // We deploy the target contract through L1 to ensure security
      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider);
      const value = cmd.value ? ethers.BigNumber.from(cmd.value) : ethers.BigNumber.from(0);

      const callData = cmd.callData;
      await sendTxToGovernance(deployWallet, callData, value);
    });

  program
    .command("decode-call-data")
    .requiredOption("--function-name <function name>")
    .requiredOption("--call-data <call-data>")
    .action(async (cmd) => {
      const functionName = cmd.functionName;
      console.log(`Decoding call data for function: ${functionName}`);
      checkSupportedGovernanceFunction(functionName);
      const callData = cmd.callData;
      const governanceInterface = IGovernanceFactory.connect(governanceAddress, provider).interface;
      const result = governanceInterface.decodeFunctionData(functionName, callData);
      console.log(`Decoded call data: ${JSON.stringify(result)}`);
    });

  await program.parseAsync(process.argv);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
