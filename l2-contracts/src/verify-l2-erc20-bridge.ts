import { Command } from "commander";
import { getAddressFromEnv } from "../../l1-contracts/src.ts/utils";
import { verifyPromise } from "./verify";

const mergeTokenPortalAddress = getAddressFromEnv("CONTRACTS_MERGE_TOKEN_PORTAL_ADDR");

async function main() {
  const program = new Command();

  program.version("0.1.0").name("verify").description("verify L2 contracts");

  program
    .requiredOption("--impl-address <impl-address>")
    .requiredOption("--era-chain-id <ear-chain-id>")
    .action(async (cmd) => {
      const promises = [];

      // Contracts without constructor parameters
      const constructorArguments = [cmd.eraChainId, mergeTokenPortalAddress];
      const promise = verifyPromise(cmd.implAddress, constructorArguments);
      promises.push(promise);

      const messages = await Promise.allSettled(promises);
      for (const message of messages) {
        console.log(message.status == "fulfilled" ? message.value : message.reason);
      }
    });
  await program.parseAsync(process.argv);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });
