// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";

contract DeployNewFactoryScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);

        console.log("==================================================");
        console.log("DEPLOYING NEW MINING POOL FACTORY");
        console.log("==================================================");
        console.log("Deployer:", deployerAddr);
        console.log("Network: Sepolia Testnet");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new factory
        MiningPoolFactoryCore factory = new MiningPoolFactoryCore();

        console.log("\n[SUCCESS] Factory deployed!");
        console.log("Factory address:", address(factory));

        // Verify roles
        bytes32 defaultAdminRole = factory.DEFAULT_ADMIN_ROLE();
        bytes32 adminRole = factory.ADMIN_ROLE();
        bytes32 poolManagerRole = factory.POOL_MANAGER_ROLE();

        console.log("\nRole verification:");
        console.log("DEFAULT_ADMIN_ROLE:", factory.hasRole(defaultAdminRole, deployerAddr));
        console.log("ADMIN_ROLE:", factory.hasRole(adminRole, deployerAddr));
        console.log("POOL_MANAGER_ROLE:", factory.hasRole(poolManagerRole, deployerAddr));

        vm.stopBroadcast();

        console.log("\n==================================================");
        console.log("NEXT STEPS:");
        console.log("1. Call setDependencies() with all contract addresses");
        console.log("2. Call setPoolDeployer() with deployer address");
        console.log("3. Grant POOL_MANAGER_ROLE to authorized users");
        console.log("4. Update CONFIG.CONTRACTS.FACTORY in frontend");
        console.log("==================================================");
    }
}
