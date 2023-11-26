import { CONTRACT_DEPLOYER_ADDRESS, hashBytecode } from "zksync-web3/build/src/utils";
import { KeccakTest, KeccakTest__factory } from "../typechain-types";
import { KECCAK256_CONTRACT_ADDRESS } from "./shared/constants";
import { getWallets, loadArtifact, publishBytecode, setCode, getCode } from "./shared/utils";
import { ethers } from "hardhat";
import { readYulBytecode } from "../scripts/utils";
import { Language } from "../scripts/constants";
import { BytesLike, Wallet, providers } from "ethers";
import { expect } from "chai";
import * as hre from "hardhat";

describe("Keccak256 tests", function () {
  let testWallet: Wallet;
  let keccakTest: KeccakTest;

  let oldKeccakCodeHash: string;
  let correctKeccakCodeHash: string;
  let alwaysRevertCodeHash: string;
  let keccakMockCodeHash: string;

  // Kernel space address, needed to enable mimicCall
  const KECCAK_TEST_ADDRESS = "0x0000000000000000000000000000000000009000";

  before(async () => {
    testWallet = getWallets()[0];

    await setCode(KECCAK_TEST_ADDRESS, (await loadArtifact("KeccakTest")).bytecode);

    const keccakCode = await getCode(KECCAK256_CONTRACT_ADDRESS);
    oldKeccakCodeHash = ethers.utils.hexlify(hashBytecode(keccakCode));

    const keccakMockCode = readYulBytecode({
      codeName: "Keccak256Mock",
      path: "precompiles/test-contracts",
      lang: Language.Yul,
      address: ethers.constants.AddressZero,
    });

    keccakMockCodeHash = ethers.utils.hexlify(hashBytecode(keccakMockCode));

    keccakTest = KeccakTest__factory.connect(KECCAK_TEST_ADDRESS, getWallets()[0]);
    const correctKeccakCode = readYulBytecode({
      codeName: "Keccak256",
      path: "precompiles",
      lang: Language.Yul,
      address: ethers.constants.AddressZero,
    });

    const correctContractDeployerCode = (await loadArtifact("ContractDeployer")).bytecode;
    await setCode(CONTRACT_DEPLOYER_ADDRESS, correctContractDeployerCode);

    const emptyContractCode = (await loadArtifact("AlwaysRevert")).bytecode;

    await publishBytecode(keccakCode);
    await publishBytecode(correctKeccakCode);
    await publishBytecode(emptyContractCode);
    await publishBytecode(keccakMockCode);

    correctKeccakCodeHash = ethers.utils.hexlify(hashBytecode(correctKeccakCode));
    alwaysRevertCodeHash = ethers.utils.hexlify(hashBytecode(emptyContractCode));
  });

  it("zero pointer test", async () => {
    await keccakTest.zeroPointerTest();
  });

  it("keccak upgrade test", async () => {
    const deployerInterfact = new ethers.utils.Interface((await loadArtifact("ContractDeployer")).abi);

    const eraseInput = deployerInterfact.encodeFunctionData("forceDeployKeccak256", [alwaysRevertCodeHash]);

    const upgradeInput = deployerInterfact.encodeFunctionData("forceDeployKeccak256", [correctKeccakCodeHash]);

    await keccakTest.keccakUpgradeTest(eraseInput, upgradeInput);
  });

  it("keccak validation test", async () => {
    const deployerInterfact = new ethers.utils.Interface((await loadArtifact("ContractDeployer")).abi);

    const upgradeInput = deployerInterfact.encodeFunctionData("forceDeployKeccak256", [correctKeccakCodeHash]);

    const resetInput = deployerInterfact.encodeFunctionData("forceDeployKeccak256", [oldKeccakCodeHash]);

    const seed = ethers.utils.randomBytes(32);
    // Displaying seed for reproducible tests
    console.log("Keccak256 fussing seed", ethers.utils.hexlify(seed));

    const BLOCK_SIZE = 136;

    const inputsToTest = [
      "0x",
      randomHexFromSeed(seed, BLOCK_SIZE),
      randomHexFromSeed(seed, BLOCK_SIZE - 1),
      randomHexFromSeed(seed, BLOCK_SIZE - 2),
      randomHexFromSeed(seed, BLOCK_SIZE + 1),
      randomHexFromSeed(seed, BLOCK_SIZE + 2),
      randomHexFromSeed(seed, 101 * BLOCK_SIZE),
      randomHexFromSeed(seed, 101 * BLOCK_SIZE - 1),
      randomHexFromSeed(seed, 101 * BLOCK_SIZE - 2),
      randomHexFromSeed(seed, 101 * BLOCK_SIZE + 1),
      randomHexFromSeed(seed, 101 * BLOCK_SIZE + 2),
      // In order to get random length, we use modulo operation
      randomHexFromSeed(seed, ethers.BigNumber.from(seed).mod(113).toNumber()),
      randomHexFromSeed(seed, ethers.BigNumber.from(seed).mod(1101).toNumber()),
      randomHexFromSeed(seed, ethers.BigNumber.from(seed).mod(17).toNumber()),
    ];

    const expectedOutput = inputsToTest.map((e) => ethers.utils.keccak256(e));

    await keccakTest.keccakValidationTest(upgradeInput, resetInput, inputsToTest, expectedOutput);
  });

  it("keccak upgrade if needed test", async () => {
    const deployerInterfact = new ethers.utils.Interface((await loadArtifact("ContractDeployer")).abi);

    const mockKeccakInput = deployerInterfact.encodeFunctionData("forceDeployKeccak256", [keccakMockCodeHash]);

    await keccakTest.keccakPerformUpgrade(mockKeccakInput);

    var keccakCode = await getCode(KECCAK256_CONTRACT_ADDRESS);
    var keccakCodeHash = ethers.utils.hexlify(hashBytecode(keccakCode));

    expect(keccakCodeHash).to.eq(keccakMockCodeHash);

    // Needed to create a new batch & thus start the bootloader once more.
    // After this, the bootloader should automatically return the code hash to the
    // previous one.
    await hre.network.provider.send("hardhat_mine", ["0x100"]);

    keccakCode = await getCode(KECCAK256_CONTRACT_ADDRESS);
    keccakCodeHash = ethers.utils.hexlify(hashBytecode(keccakCode));

    expect(keccakCodeHash).to.eq(oldKeccakCodeHash);
  });
});

async function compareCorrectHash(data: BytesLike, provider: providers.Provider) {
  const correctHash = ethers.utils.keccak256(data);
  const hashFromPrecompile = await provider.call({
    to: KECCAK256_CONTRACT_ADDRESS,
    data,
  });
  expect(hashFromPrecompile).to.equal(correctHash, "Hash is incorrect");
}

function randomHexFromSeed(seed: BytesLike, len: number) {
  const hexLen = len * 2 + 2;
  let data = "0x";
  while (data.length < hexLen) {
    const next = ethers.utils.keccak256(ethers.utils.hexConcat([seed, data]));
    data = ethers.utils.hexConcat([data, next]);
  }
  return data.substring(0, hexLen);
}
