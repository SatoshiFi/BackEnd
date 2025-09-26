const { ethers, upgrades } = require("hardhat");

async function main() {
  // Получение аккаунтов
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Параметры конфигурации
  const frostThreshold = 2; // Порог для FROST (например, 2 из 3)
  const networkIds = [0, 1]; // 0: BTC, 1: DOGE
  const poolId = "pool1";
  const groupPubkeyX = ethers.utils.hexZeroPad("0x1234", 32); // Замените реальным значением
  const groupPubkeyY = ethers.utils.hexZeroPad("0x5678", 32); // Замените реальным значением
  const custodians = [deployer.address]; // Пример списка кастодианов

  // Развертывание библиотек
  const BitcoinUtils = await ethers.getContractFactory("BitcoinUtils");
  const bitcoinUtils = await BitcoinUtils.deploy();
  await bitcoinUtils.waitForDeployment();
  console.log("BitcoinUtils deployed to:", await bitcoinUtils.getAddress());

  const BlockHeader = await ethers.getContractFactory("BlockHeader");
  const blockHeader = await BlockHeader.deploy();
  await blockHeader.waitForDeployment();
  console.log("BlockHeader deployed to:", await blockHeader.getAddress());

  const BitcoinTxParser = await ethers.getContractFactory("BitcoinTxParser");
  const bitcoinTxParser = await BitcoinTxParser.deploy();
  await bitcoinTxParser.waitForDeployment();
  console.log("BitcoinTxParser deployed to:", await bitcoinTxParser.getAddress());

  const TxMerkleProof = await ethers.getContractFactory("TxMerkleProof");
  const txMerkleProof = await TxMerkleProof.deploy();
  await txMerkleProof.waitForDeployment();
  console.log("TxMerkleProof deployed to:", await txMerkleProof.getAddress());

  const MerkleProofLib = await ethers.getContractFactory("MerkleProofLib");
  const merkleProofLib = await MerkleProofLib.deploy();
  await merkleProofLib.waitForDeployment();
  console.log("MerkleProofLib deployed to:", await merkleProofLib.getAddress());

  const DistributionMath = await ethers.getContractFactory("DistributionMath");
  const distributionMath = await DistributionMath.deploy();
  await distributionMath.waitForDeployment();
  console.log("DistributionMath deployed to:", await distributionMath.getAddress());

  // Развертывание SPV контрактов
  const SPVContract = await ethers.getContractFactory("SPVContract", {
    libraries: {
      BlockHeader: await blockHeader.getAddress(),
      BitcoinTxParser: await bitcoinTxParser.getAddress(),
      TxMerkleProof: await txMerkleProof.getAddress(),
      BitcoinUtils: await bitcoinUtils.getAddress(),
    },
  });
  const spvContract = await SPVContract.deploy();
  await spvContract.waitForDeployment();
  console.log("SPVContract deployed to:", await spvContract.getAddress());

  const SPVContractDogecoin = await ethers.getContractFactory("SPVContractDogecoin", {
    libraries: {
      BlockHeader: await blockHeader.getAddress(),
      BitcoinTxParser: await bitcoinTxParser.getAddress(),
      TxMerkleProof: await txMerkleProof.getAddress(),
      BitcoinUtils: await bitcoinUtils.getAddress(),
    },
  });
  const spvContractDogecoin = await SPVContractDogecoin.deploy();
  await spvContractDogecoin.waitForDeployment();
  console.log("SPVContractDogecoin deployed to:", await spvContractDogecoin.getAddress());

  // Развертывание FROST
  const FROSTVerifier = await ethers.getContractFactory("FROSTVerifier");
  const frostVerifier = await FROSTVerifier.deploy();
  await frostVerifier.waitForDeployment();
  console.log("FROSTVerifier deployed to:", await frostVerifier.getAddress());

  const FROSTCoordinator = await ethers.getContractFactory("FROSTCoordinator", {
    libraries: {
      FROSTVerifier: await frostVerifier.getAddress(),
    },
  });
  const frostCoordinator = await FROSTCoordinator.deploy(frostThreshold, custodians);
  await frostCoordinator.waitForDeployment();
  console.log("FROSTCoordinator deployed to:", await frostCoordinator.getAddress());

  // Развертывание оракулов
  const StratumDataValidator = await ethers.getContractFactory("StratumDataValidator");
  const stratumDataValidator = await StratumDataValidator.deploy();
  await stratumDataValidator.waitForDeployment();
  console.log("StratumDataValidator deployed to:", await stratumDataValidator.getAddress());

  const StratumOracleRegistry = await ethers.getContractFactory("StratumOracleRegistry");
  const stratumOracleRegistry = await StratumOracleRegistry.deploy();
  await stratumOracleRegistry.waitForDeployment();
  console.log("StratumOracleRegistry deployed to:", await stratumOracleRegistry.getAddress());

  const StratumDataAggregator = await ethers.getContractFactory("StratumDataAggregator");
  const stratumDataAggregator = await StratumDataAggregator.deploy(await stratumDataValidator.getAddress());
  await stratumDataAggregator.waitForDeployment();
  console.log("StratumDataAggregator deployed to:", await stratumDataAggregator.getAddress());

  // Развертывание калькуляторов
  const FPPSCalculator = await ethers.getContractFactory("FPPSCalculator", {
    libraries: { DistributionMath: await distributionMath.getAddress() },
  });
  const fppsCalculator = await FPPSCalculator.deploy();
  await fppsCalculator.waitForDeployment();
  console.log("FPPSCalculator deployed to:", await fppsCalculator.getAddress());

  const PPLNSCalculator = await ethers.getContractFactory("PPLNSCalculator", {
    libraries: { DistributionMath: await distributionMath.getAddress() },
  });
  const pplnsCalculator = await PPLNSCalculator.deploy();
  await pplnsCalculator.waitForDeployment();
  console.log("PPLNSCalculator deployed to:", await pplnsCalculator.getAddress());

  const PPSCalculator = await ethers.getContractFactory("PPSCalculator", {
    libraries: { DistributionMath: await distributionMath.getAddress() },
  });
  const ppsCalculator = await PPSCalculator.deploy();
  await ppsCalculator.waitForDeployment();
  console.log("PPSCalculator deployed to:", await ppsCalculator.getAddress());

  const ScoreCalculator = await ethers.getContractFactory("ScoreCalculator", {
    libraries: { DistributionMath: await distributionMath.getAddress() },
  });
  const scoreCalculator = await ScoreCalculator.deploy();
  await scoreCalculator.waitForDeployment();
  console.log("ScoreCalculator deployed to:", await scoreCalculator.getAddress());

  const CalculatorRegistry = await ethers.getContractFactory("CalculatorRegistry");
  const calculatorRegistry = await CalculatorRegistry.deploy(deployer.address, await miningPoolFactory.getAddress()); // Обновлено: poolFactory не развернут еще, используйте deployer как admin
  await calculatorRegistry.waitForDeployment();
  console.log("CalculatorRegistry deployed to:", await calculatorRegistry.getAddress());

  // Регистрация калькуляторов
  await calculatorRegistry.registerCalculator(await fppsCalculator.getAddress(), 2, "FPPS", "Full Pay Per Share", "1.0", 100000); // Пример
  await calculatorRegistry.registerCalculator(await pplnsCalculator.getAddress(), 0, "PPLNS", "Pay Per Last N Shares", "1.0", 100000);
  await calculatorRegistry.registerCalculator(await ppsCalculator.getAddress(), 1, "PPS", "Pay Per Share", "1.0", 100000);
  await calculatorRegistry.registerCalculator(await scoreCalculator.getAddress(), 3, "Score", "Score-based", "1.0", 100000);
  console.log("Calculators registered in CalculatorRegistry");

  // Развертывание токенов
  const PoolMpToken = await ethers.getContractFactory("PoolMpToken");
  const poolMpToken = await PoolMpToken.deploy("MiningPoolToken", "MPT");
  await poolMpToken.waitForDeployment();
  console.log("PoolMpToken deployed to:", await poolMpToken.getAddress());

  const PoolSToken = await ethers.getContractFactory("PoolSToken");
  const poolSToken = await PoolSToken.deploy("SyntheticToken", "ST");
  await poolSToken.waitForDeployment();
  console.log("PoolSToken deployed to:", await poolSToken.getAddress());

  // Развертывание NFT
  const PoolMembershipNFT = await ethers.getContractFactory("PoolMembershipNFT");
  const poolMembershipNFT = await PoolMembershipNFT.deploy();
  await poolMembershipNFT.waitForDeployment();
  console.log("PoolMembershipNFT deployed to:", await poolMembershipNFT.getAddress());

  const PoolRoleBadgeNFT = await ethers.getContractFactory("PoolRoleBadgeNFT");
  const poolRoleBadgeNFT = await PoolRoleBadgeNFT.deploy();
  await poolRoleBadgeNFT.waitForDeployment();
  console.log("PoolRoleBadgeNFT deployed to:", await poolRoleBadgeNFT.getAddress());

  // Развертывание BitcoinTxSerializer
  const BitcoinTxSerializer = await ethers.getContractFactory("BitcoinTxSerializer", {
    libraries: { BitcoinUtils: await bitcoinUtils.getAddress() },
  });
  const bitcoinTxSerializer = await BitcoinTxSerializer.deploy();
  await bitcoinTxSerializer.waitForDeployment();
  console.log("BitcoinTxSerializer deployed to:", await bitcoinTxSerializer.getAddress());

  // Развертывание MultiPoolDAO
  const MultiPoolDAO = await ethers.getContractFactory("MultiPoolDAO", {
    libraries: {
      MerkleProofLib: await merkleProofLib.getAddress(),
      BitcoinUtils: await bitcoinUtils.getAddress(),
    },
  });
  const multiPoolDAO = await upgrades.deployProxy(MultiPoolDAO, [deployer.address, frostCoordinator.address], {
    initializer: "initialize",
    unsafeAllow: ["external-library-linking"],
  });
  await multiPoolDAO.waitForDeployment();
  console.log("MultiPoolDAO deployed to:", await multiPoolDAO.getAddress());

  // Развертывание MiningPoolDAO
  const MiningPoolDAO = await ethers.getContractFactory("MiningPoolDAO", {
    libraries: {
      BitcoinTxSerializer: await bitcoinTxSerializer.getAddress(),
      BlockHeader: await blockHeader.getAddress(),
      BitcoinTxParser: await bitcoinTxParser.getAddress(),
      BitcoinUtils: await bitcoinUtils.getAddress(),
    },
  });
  const miningPoolDAO = await upgrades.deployProxy(
    MiningPoolDAO,
    [
      await spvContract.getAddress(),
      await frostCoordinator.getAddress(),
      await calculatorRegistry.getAddress(),
      await stratumDataAggregator.getAddress(),
      await stratumOracleRegistry.getAddress(),
      groupPubkeyX,
      groupPubkeyY,
      poolId,
    ],
    {
      initializer: "initialize",
      unsafeAllow: ["external-library-linking"],
    }
  );
  await miningPoolDAO.waitForDeployment();
  console.log("MiningPoolDAO deployed to:", await miningPoolDAO.getAddress());

  // Развертывание MiningPoolFactory
  const MiningPoolFactory = await ethers.getContractFactory("MiningPoolFactory");
  const miningPoolFactory = await MiningPoolFactory.deploy(
    await miningPoolDAO.getAddress(),
    await poolMpToken.getAddress(),
    await poolMembershipNFT.getAddress(),
    await poolRoleBadgeNFT.getAddress()
  );
  await miningPoolFactory.waitForDeployment();
  console.log("MiningPoolFactory deployed to:", await miningPoolFactory.getAddress());

  // Настройка MiningPoolDAO
  await miningPoolDAO.setPoolToken(await poolMpToken.getAddress());
  await miningPoolDAO.setMultiPoolDAO(await multiPoolDAO.getAddress());
  await miningPoolDAO.setMembershipContracts(await poolMembershipNFT.getAddress(), await poolRoleBadgeNFT.getAddress());
  await miningPoolDAO.setBtcTxSerializer(await bitcoinTxSerializer.getAddress());
  await miningPoolDAO.setStratumDataValidator(await stratumDataValidator.getAddress());
  await miningPoolDAO.setCalculator(1); // Устанавливаем FPPSCalculator по умолчанию
  console.log("MiningPoolDAO configured");

  // Настройка SPV для сетей
  await miningPoolDAO.setSPVContract(0, await spvContract.getAddress()); // BTC
  await miningPoolDAO.setSPVContract(1, await spvContractDogecoin.getAddress()); // DOGE
  console.log("SPV contracts set for BTC and DOGE");

  // Вывод результатов
  console.log("\nDeployment Summary:");
  console.log("BitcoinUtils:", await bitcoinUtils.getAddress());
  console.log("BlockHeader:", await blockHeader.getAddress());
  console.log("BitcoinTxParser:", await bitcoinTxParser.getAddress());
  console.log("TxMerkleProof:", await txMerkleProof.getAddress());
  console.log("MerkleProofLib:", await merkleProofLib.getAddress());
  console.log("DistributionMath:", await distributionMath.getAddress());
  console.log("SPVContract:", await spvContract.getAddress());
  console.log("SPVContractDogecoin:", await spvContractDogecoin.getAddress());
  console.log("FROSTVerifier:", await frostVerifier.getAddress());
  console.log("FROSTCoordinator:", await frostCoordinator.getAddress());
  console.log("StratumDataValidator:", await stratumDataValidator.getAddress());
  console.log("StratumOracleRegistry:", await stratumOracleRegistry.getAddress());
  console.log("StratumDataAggregator:", await stratumDataAggregator.getAddress());
  console.log("FPPSCalculator:", await fppsCalculator.getAddress());
  console.log("PPLNSCalculator:", await pplnsCalculator.getAddress());
  console.log("PPSCalculator:", await ppsCalculator.getAddress());
  console.log("ScoreCalculator:", await scoreCalculator.getAddress());
  console.log("CalculatorRegistry:", await calculatorRegistry.getAddress());
  console.log("PoolMpToken:", await poolMpToken.getAddress());
  console.log("PoolSToken:", await poolSToken.getAddress());
  console.log("PoolMembershipNFT:", await poolMembershipNFT.getAddress());
  console.log("PoolRoleBadgeNFT:", await poolRoleBadgeNFT.getAddress());
  console.log("BitcoinTxSerializer:", await bitcoinTxSerializer.getAddress());
  console.log("MultiPoolDAO:", await multiPoolDAO.getAddress());
  console.log("MiningPoolDAO:", await miningPoolDAO.getAddress());
  console.log("MiningPoolFactory:", await miningPoolFactory.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });