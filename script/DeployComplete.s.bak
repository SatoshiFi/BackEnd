// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/FROSTCoordinator.sol";  // ИСПРАВЛЕНО: правильный контракт
import "../contracts/src/SPVContractDogecoin.sol";
import "../contracts/src/MultiPoolDAO.sol";
import "../contracts/src/MiningPoolDAOCore.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/calculators/FPPSCalculator.sol";
import "../contracts/src/calculators/PPLNSCalculator.sol";
import "../contracts/src/calculators/PPSCalculator.sol";
import "../contracts/src/calculators/ScoreCalculator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/tokens/SBTC.sol";
import "../contracts/src/tokens/SDOGE.sol";
import "../contracts/src/tokens/SLTC.sol";
import "../contracts/src/refactored/MiningPoolProxy.sol";
import "../contracts/src/refactored/implementations/MiningPoolCore.sol";
import "../contracts/src/refactored/implementations/MiningPoolRewards.sol";
import "../contracts/src/refactored/implementations/MiningPoolRedemption.sol";
import "../contracts/src/refactored/implementations/MiningPoolExtensions.sol";
import "../contracts/src/RewardHandler.sol";
import "../contracts/src/RedemptionHandler.sol";

contract DeployCompleteFixedScript is Script {
    // Core contracts
    FROSTCoordinator public frost;  // ИСПРАВЛЕНО: правильный тип
    SPVContractDogecoin public spv;
    MultiPoolDAO public multiPoolDAO;

    // Factory contracts
    MiningPoolFactoryCore public factory;
    PoolDeployerV2 public deployer;
    PoolTokenFactory public tokenFactory;

    // Calculator contracts
    CalculatorRegistry public calculatorRegistry;
    FPPSCalculator public fppsCalc;
    PPLNSCalculator public pplnsCalc;
    PPSCalculator public ppsCalc;
    ScoreCalculator public scoreCalc;

    // Oracle contracts
    StratumOracleRegistry public oracleRegistry;
    StratumDataAggregator public aggregator;
    StratumDataValidator public validator;

    // Synthetic tokens
    SBTC public sBTC;
    SDOGE public sDOGE;
    SLTC public sLTC;

    // Proxy implementations
    MiningPoolCore public coreImpl;
    MiningPoolRewards public rewardsImpl;
    MiningPoolRedemption public redemptionImpl;
    MiningPoolExtensions public extensionsImpl;

    // Handlers
    RewardHandler public rewardHandler;
    RedemptionHandler public redemptionHandler;

    function run() external {
        // ИСПРАВЛЕНО: использует PRIVATE_KEY из .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);

        console.log("==================================================");
        console.log("COMPLETE DEPLOYMENT TO SEPOLIA - FIXED VERSION");
        console.log("==================================================");
        console.log("Deployer:", deployerAddr);
        console.log("\nStarting deployment...\n");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Core Infrastructure
        console.log("[1/8] Deploying Core Infrastructure...");

        // ИСПРАВЛЕНО: деплоим правильный FROSTCoordinator с verifier
        address verifierAddress = 0x4dccA4E12d0Cb7B3d713B717f3C4fB348571a4C0;
        frost = new FROSTCoordinator(verifierAddress);
        console.log("  FROST:", address(frost));

        spv = new SPVContractDogecoin(deployerAddr);
        console.log("  SPV:", address(spv));

        multiPoolDAO = new MultiPoolDAO();
        console.log("  MultiPoolDAO:", address(multiPoolDAO));

        // Initialize MultiPoolDAO
        multiPoolDAO.initialize(
            address(frost),
                                hex"",
                                7 days,
                                deployerAddr
        );

        // 2. Deploy Oracle Infrastructure
        console.log("\n[2/8] Deploying Oracle Infrastructure...");
        oracleRegistry = new StratumOracleRegistry(deployerAddr);
        console.log("  OracleRegistry:", address(oracleRegistry));

        aggregator = new StratumDataAggregator(address(oracleRegistry), deployerAddr);
        console.log("  Aggregator:", address(aggregator));

        validator = new StratumDataValidator(address(oracleRegistry), deployerAddr);
        console.log("  Validator:", address(validator));

        // 3. Deploy Calculator System
        console.log("\n[3/8] Deploying Calculator System...");
        calculatorRegistry = new CalculatorRegistry(deployerAddr, deployerAddr);
        console.log("  CalculatorRegistry:", address(calculatorRegistry));

        fppsCalc = new FPPSCalculator();
        console.log("  FPPSCalculator:", address(fppsCalc));

        pplnsCalc = new PPLNSCalculator();
        console.log("  PPLNSCalculator:", address(pplnsCalc));

        ppsCalc = new PPSCalculator();
        console.log("  PPSCalculator:", address(ppsCalc));

        scoreCalc = new ScoreCalculator();
        console.log("  ScoreCalculator:", address(scoreCalc));

        // Register calculators
        calculatorRegistry.authorizeAuthor(deployerAddr, true);

        uint256 fppsId = calculatorRegistry.registerCalculator(
            address(fppsCalc),
                                                               CalculatorRegistry.SchemeType.FPPS,
                                                               "FPPS",
                                                               "Full Pay Per Share",
                                                               "1.0.0",
                                                               300000
        );
        calculatorRegistry.whitelistCalculator(fppsId, true);

        uint256 pplnsId = calculatorRegistry.registerCalculator(
            address(pplnsCalc),
                                                                CalculatorRegistry.SchemeType.PPLNS,
                                                                "PPLNS",
                                                                "Pay Per Last N Shares",
                                                                "1.0.0",
                                                                300000
        );
        calculatorRegistry.whitelistCalculator(pplnsId, true);

        uint256 ppsId = calculatorRegistry.registerCalculator(
            address(ppsCalc),
                                                              CalculatorRegistry.SchemeType.PPS,
                                                              "PPS",
                                                              "Pay Per Share",
                                                              "1.0.0",
                                                              300000
        );
        calculatorRegistry.whitelistCalculator(ppsId, true);

        uint256 scoreId = calculatorRegistry.registerCalculator(
            address(scoreCalc),
                                                                CalculatorRegistry.SchemeType.SCORE,
                                                                "SCORE",
                                                                "Score Based",
                                                                "1.0.0",
                                                                300000
        );
        calculatorRegistry.whitelistCalculator(scoreId, true);

        // 4. Deploy Factory System
        console.log("\n[4/8] Deploying Factory System...");
        tokenFactory = new PoolTokenFactory(deployerAddr);
        console.log("  TokenFactory:", address(tokenFactory));

        factory = new MiningPoolFactoryCore();
        console.log("  Factory:", address(factory));

        deployer = new PoolDeployerV2(address(factory));
        console.log("  Deployer:", address(deployer));

        // Configure factory
        factory.setDependencies(
            address(spv),
                                address(frost),  // ИСПРАВЛЕНО: правильный FROST
                                address(calculatorRegistry),
                                address(aggregator),
                                address(validator),
                                address(oracleRegistry),
                                address(tokenFactory),
                                address(multiPoolDAO)
        );
        factory.setPoolDeployer(address(deployer));
        factory.grantRole(factory.POOL_MANAGER_ROLE(), deployerAddr);

        // Grant factory role to token factory
        tokenFactory.grantRole(tokenFactory.POOL_FACTORY_ROLE(), address(deployer));

        // 5. Deploy Proxy Implementations
        console.log("\n[5/8] Deploying Proxy Implementations...");
        coreImpl = new MiningPoolCore();
        console.log("  CoreImpl:", address(coreImpl));

        rewardsImpl = new MiningPoolRewards();
        console.log("  RewardsImpl:", address(rewardsImpl));

        redemptionImpl = new MiningPoolRedemption();
        console.log("  RedemptionImpl:", address(redemptionImpl));

        extensionsImpl = new MiningPoolExtensions();
        console.log("  ExtensionsImpl:", address(extensionsImpl));

        // 6. Deploy Handlers
        console.log("\n[6/8] Deploying Handlers...");
        rewardHandler = new RewardHandler();
        console.log("  RewardHandler:", address(rewardHandler));

        redemptionHandler = new RedemptionHandler();
        console.log("  RedemptionHandler:", address(redemptionHandler));

        // 7. Deploy Synthetic Tokens
        console.log("\n[7/8] Deploying Synthetic Tokens...");
        sBTC = new SBTC(address(multiPoolDAO), deployerAddr);
        console.log("  sBTC:", address(sBTC));

        sDOGE = new SDOGE(address(multiPoolDAO), deployerAddr);
        console.log("  sDOGE:", address(sDOGE));

        sLTC = new SLTC(address(multiPoolDAO), deployerAddr);
        console.log("  sLTC:", address(sLTC));

        // 8. Final configuration
        console.log("\n[8/8] Final configuration...");
        console.log("  All contracts deployed and configured!");

        vm.stopBroadcast();

        // Save all addresses
        saveAllAddresses(deployerAddr);

        console.log("\n==================================================");
        console.log("DEPLOYMENT COMPLETE - FIXED VERSION!");
        console.log("==================================================");
        printSummary();
    }

    function saveAllAddresses(address deployerAddr) private {
        string memory json = "deployment";

        // Core
        vm.serializeAddress(json, "deployer", deployerAddr);
        vm.serializeAddress(json, "frost", address(frost));
        vm.serializeAddress(json, "spv", address(spv));
        vm.serializeAddress(json, "multiPoolDAO", address(multiPoolDAO));

        // Factory
        vm.serializeAddress(json, "factory", address(factory));
        vm.serializeAddress(json, "deployer", address(deployer));
        vm.serializeAddress(json, "tokenFactory", address(tokenFactory));

        // Calculators
        vm.serializeAddress(json, "calculatorRegistry", address(calculatorRegistry));
        vm.serializeAddress(json, "fppsCalc", address(fppsCalc));
        vm.serializeAddress(json, "pplnsCalc", address(pplnsCalc));
        vm.serializeAddress(json, "ppsCalc", address(ppsCalc));
        vm.serializeAddress(json, "scoreCalc", address(scoreCalc));

        // Oracles
        vm.serializeAddress(json, "oracleRegistry", address(oracleRegistry));
        vm.serializeAddress(json, "aggregator", address(aggregator));
        vm.serializeAddress(json, "validator", address(validator));

        // Synthetic tokens
        vm.serializeAddress(json, "sBTC", address(sBTC));
        vm.serializeAddress(json, "sDOGE", address(sDOGE));
        vm.serializeAddress(json, "sLTC", address(sLTC));

        // Implementations
        vm.serializeAddress(json, "coreImpl", address(coreImpl));
        vm.serializeAddress(json, "rewardsImpl", address(rewardsImpl));
        vm.serializeAddress(json, "redemptionImpl", address(redemptionImpl));
        vm.serializeAddress(json, "extensionsImpl", address(extensionsImpl));

        // Handlers
        vm.serializeAddress(json, "rewardHandler", address(rewardHandler));
        string memory finalJson = vm.serializeAddress(json, "redemptionHandler", address(redemptionHandler));

        console.log("\nAddresses collected (save manually if needed)");
    }

    function printSummary() private view {
        console.log("\nDEPLOYED CONTRACTS SUMMARY:");
        console.log("\n[CORE - 3 contracts]");
        console.log("  FROST (FIXED):", address(frost));
        console.log("  SPV:", address(spv));
        console.log("  MultiPoolDAO:", address(multiPoolDAO));

        console.log("\n[FACTORY - 3 contracts]");
        console.log("  Factory:", address(factory));
        console.log("  Deployer:", address(deployer));
        console.log("  TokenFactory:", address(tokenFactory));

        console.log("\n[CALCULATORS - 5 contracts]");
        console.log("  Registry:", address(calculatorRegistry));
        console.log("  FPPS:", address(fppsCalc));
        console.log("  PPLNS:", address(pplnsCalc));
        console.log("  PPS:", address(ppsCalc));
        console.log("  SCORE:", address(scoreCalc));

        console.log("\n[ORACLES - 3 contracts]");
        console.log("  Registry:", address(oracleRegistry));
        console.log("  Aggregator:", address(aggregator));
        console.log("  Validator:", address(validator));

        console.log("\n[SYNTHETIC TOKENS - 3 contracts]");
        console.log("  sBTC:", address(sBTC));
        console.log("  sDOGE:", address(sDOGE));
        console.log("  sLTC:", address(sLTC));

        console.log("\n[PROXY IMPLEMENTATIONS - 4 contracts]");
        console.log("  Core:", address(coreImpl));
        console.log("  Rewards:", address(rewardsImpl));
        console.log("  Redemption:", address(redemptionImpl));
        console.log("  Extensions:", address(extensionsImpl));

        console.log("\n[HANDLERS - 2 contracts]");
        console.log("  RewardHandler:", address(rewardHandler));
        console.log("  RedemptionHandler:", address(redemptionHandler));

        console.log("\n==================================================");
        console.log("TOTAL: 26 CONTRACTS DEPLOYED!");
        console.log("FROST COORDINATOR: FIXED VERSION!");
        console.log("==================================================");
    }
}
