import { Command } from "commander";
import { Wallet } from "ethers";
import { formatUnits } from "ethers/lib/utils";
import { web3Provider } from "./utils";

const provider = web3Provider();

async function main() {
  const program = new Command();

  program.version("0.1.0").name("replace-tx").description("replace a tx");

  program
    .requiredOption("--private-key <private-key>")
    .requiredOption("--to <to>")
    .requiredOption("--value <value>")
    .requiredOption("--data <data>")
    .requiredOption("--nonce <nonce>")
    .requiredOption("--gas-price <gas-price>")
    .requiredOption("--gas-limit <gas-limit>")
    .action(async (cmd) => {
      const deployWallet = new Wallet(cmd.privateKey, provider);
      console.log(`Using deployer wallet: ${deployWallet.address}`);

      const nonce = cmd.nonce;
      console.log(`Using nonce: ${nonce}`);

      const gasPrice = cmd.gasPrice;
      console.log(`Using gas price: ${formatUnits(gasPrice, "gwei")} gwei`);

      const gasLimit = cmd.gasLimit;
      console.log(`Using gas limit: ${gasLimit}`);

      await deployWallet.sendTransaction({
        to: cmd.to,
        value: cmd.value,
        data: cmd.data,
        nonce,
        gasPrice,
        gasLimit,
      });
    });

  await program.parseAsync(process.argv);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
