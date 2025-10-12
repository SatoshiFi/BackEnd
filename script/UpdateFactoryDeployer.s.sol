// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";

contract UpdateFactoryDeployer is Script {
    address constant FACTORY = 0xb87DB5fF6802A8B0bd48fb314234916f1BA27C1a;
    address constant SPV_CONTRACT = 0xD7f2293659A000b37Fd3973B06d4699935c511e9;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new PoolDeployerV2
        PoolDeployerV2 newDeployer = new PoolDeployerV2(FACTORY, SPV_CONTRACT);

        console.log("New PoolDeployerV2:", address(newDeployer));
        console.log("  Internal RewardHandler:", newDeployer.rewardHandler());
        console.log("  Internal RedemptionHandler:", newDeployer.redemptionHandler());

        // Update Factory
        MiningPoolFactoryCore factory = MiningPoolFactoryCore(FACTORY);
        factory.setPoolDeployer(address(newDeployer));

        console.log("");
        console.log("[OK] Factory updated with new deployer");
        console.log("");
        console.log("Now you can create new pools with corrected logic");

        vm.stopBroadcast();
    }
}
