import * as hardhat from "hardhat";
import { Command } from "commander";
import { getAddressFromEnv } from "../../l1-contracts/scripts/utils";

const mergeTokenPortalAddress = getAddressFromEnv("CONTRACTS_MERGE_TOKEN_PORTAL_ADDR");

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function verifyPromise(address: string, constructorArguments?: Array<any>, libraries?: object): Promise<any> {
  return new Promise((resolve, reject) => {
    hardhat
      .run("verify:verify", { address, constructorArguments, libraries })
      .then(() => resolve(`Successfully verified ${address}`))
      .catch((e) => {
        if (e.message.includes("contract is already verified")) {
          resolve(`Contract source code already verified: ${address}`);
        } else {
          reject(`Failed to verify ${address}\nError: ${e.message}`);
        }
      });
  });
}

async function main() {
  const program = new Command();

  program.version("0.1.0").name("verify").description("verify L2 contracts");

  program.requiredOption("--impl-address <impl-address>").action(async (cmd) => {
    const promises = [];

    // Contracts without constructor parameters
    const constructorArguments = [mergeTokenPortalAddress];
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
