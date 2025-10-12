// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/calculators/FPPSCalculator.sol";

contract DeployEssentialScript is Script {
    function run() external {
        uint256 deployerPrivateKey = 0x7569ceea62ef59db9a5c688d0ff1b2544110d6a16526a8612196ddd11abfa4cb;
        address deployerAddr = vm.addr(deployerPrivateKey);

        console.log("==================================================");
        console.log("ESSENTIAL CONTRACTS DEPLOYMENT");
        console.log("==================================================");
        console.log("Deployer:", deployerAddr);

        // Use already deployed contracts
        address frost = 0x62e09a399D475051bd0DAA6BCBdE15B3A2ea2Bd7;
        address spv = 0x57Ed9E748212DB5B2Ac92fB9354F5E9C4BB88987;
        address multiPoolDAO = 0x52E040D20CaCA2090A083e857CB07De253e0306F;

        console.log("\nUsing existing contracts:");
        console.log("  FROST:", frost);
        console.log("  SPV:", spv);
        console.log("  MultiPoolDAO:", multiPoolDAO);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy calculator registry and FPPS
        console.log("\n1. Deploying CalculatorRegistry...");
        CalculatorRegistry calculatorRegistry = new CalculatorRegistry(deployerAddr, deployerAddr);
        console.log("  CalculatorRegistry:", address(calculatorRegistry));

        console.log("\n2. Deploying FPPSCalculator...");
        FPPSCalculator fppsCalc = new FPPSCalculator();
        console.log("  FPPSCalculator:", address(fppsCalc));

        // Register calculator
        calculatorRegistry.authorizeAuthor(deployerAddr, true);
        uint256 calcId = calculatorRegistry.registerCalculator(
            address(fppsCalc),
            CalculatorRegistry.SchemeType.FPPS,
            "FPPS",
            "Full Pay Per Share",
            "1.0.0",
            300000
        );
        calculatorRegistry.whitelistCalculator(calcId, true);
        console.log("  Calculator registered with ID:", calcId);

        // Deploy token factory
        console.log("\n3. Deploying PoolTokenFactory...");
        PoolTokenFactory tokenFactory = new PoolTokenFactory(deployerAddr);
        console.log("  PoolTokenFactory:", address(tokenFactory));

        // Deploy factory
        console.log("\n4. Deploying MiningPoolFactoryCore...");
        MiningPoolFactoryCore factory = new MiningPoolFactoryCore();
        console.log("  Factory:", address(factory));

        // Deploy pool deployer
        console.log("\n5. Deploying PoolDeployerV2...");
        PoolDeployerV2 deployer = new PoolDeployerV2(address(factory));
        console.log("  Deployer:", address(deployer));

        // Configure factory
        console.log("\n6. Configuring factory...");

        // Create dummy oracle contracts (just for dependencies)
        address dummyOracle = address(0x1234567890123456789012345678901234567890);

        factory.setDependencies(
            spv,
            frost,
            address(calculatorRegistry),
            dummyOracle, // aggregator
            dummyOracle, // validator
            dummyOracle, // oracle registry
            address(tokenFactory),
            multiPoolDAO
        );

        factory.setPoolDeployer(address(deployer));
        factory.grantRole(factory.POOL_MANAGER_ROLE(), deployerAddr);

        // Grant factory role to token factory
        tokenFactory.grantRole(tokenFactory.POOL_FACTORY_ROLE(), address(deployer));

        console.log("  Factory configured!");

        vm.stopBroadcast();

        console.log("\n==================================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("==================================================");

        console.log("\nDEPLOYED CONTRACTS:");
        console.log("  CalculatorRegistry:", address(calculatorRegistry));
        console.log("  FPPSCalculator:", address(fppsCalc));
        console.log("  PoolTokenFactory:", address(tokenFactory));
        console.log("  MiningPoolFactory:", address(factory));
        console.log("  PoolDeployer:", address(deployer));

        console.log("\n[SUCCESS] You can now create pools using the factory!");
    }
}