import { Command } from "commander";
import { ethers, Wallet } from "ethers";
import { Deployer } from "../src.ts/deploy";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { getAddressFromEnv, web3Provider } from "./utils";

const provider = web3Provider();

async function main() {
  const program = new Command();

  program.version("0.1.0").name("set-admin");

  program
    .option("--validator <validator>", "Validator address")
    .option("--gas-price <gas-price>")
    .action(async (cmd) => {
      const deployWallet = new Wallet(process.env.GOVERNOR_PRIVATE_KEY, provider);
      console.log(`Using deployer wallet: ${deployWallet.address}`);

      const gasPrice = cmd.gasPrice ? parseUnits(cmd.gasPrice, "gwei") : await provider.getGasPrice();
      console.log(`Using gas price: ${formatUnits(gasPrice, "gwei")} gwei`);

      const ownerAddress = deployWallet.address;
      if (!cmd.validator) {
        console.log("Validator address is not provided");
        return;
      }
      const validatorAddress = cmd.validator;

      const deployer = new Deployer({
        deployWallet,
        ownerAddress,
        verbose: true,
      });

      const governance = deployer.governanceContract(deployWallet);
      const zkSync = deployer.zkSyncContract(deployWallet);

      const call = {
        target: zkSync.address,
        value: 0,
        data: zkSync.interface.encodeFunctionData("setValidator", [validatorAddress, true]),
      };

      const operation = {
        calls: [call],
        predecessor: ethers.constants.HashZero,
        salt: ethers.constants.HashZero,
      };

      await (await governance.scheduleTransparent(operation, 0)).wait();
      await (await governance.execute(operation)).wait();
    });

  await program.parseAsync(process.argv);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
