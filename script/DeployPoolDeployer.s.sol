// script/DeployPoolDeployer.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";

contract DeployPoolDeployer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Адреса из config.js для Sepolia testnet
        address factoryAddress = 0xb87DB5fF6802A8B0bd48fb314234916f1BA27C1a;
        address spvContract = 0xD7f2293659A000b37Fd3973B06d4699935c511e9;

        vm.startBroadcast(deployerPrivateKey);

        PoolDeployerV2 deployer = new PoolDeployerV2(factoryAddress, spvContract);

        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("PoolDeployerV2:", address(deployer));
        console.log("Factory:", factoryAddress);
        console.log("SPV Contract:", spvContract);
        console.log("RewardHandler:", deployer.rewardHandler());
        console.log("RedemptionHandler:", deployer.redemptionHandler());
        console.log("\n=== UPDATE FACTORY ===");
        console.log("Run: factory.setPoolDeployer(%s)", address(deployer));
        console.log("\n=== UPDATE config.js ===");
        console.log("POOL_DEPLOYER: '%s',", address(deployer));

        vm.stopBroadcast();
    }
}
