// script/SetupFactory.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

interface IFactory {
    function setPoolDeployer(address) external;
    function poolDeployer() external view returns (address);
    function grantRole(bytes32, address) external;
    function hasRole(bytes32, address) external view returns (bool);
    function POOL_MANAGER_ROLE() external view returns (bytes32);
    function ADMIN_ROLE() external view returns (bytes32);
}

contract SetupFactory is Script {
    function run(
        address factoryAddress,
        address poolDeployerAddress,
        address poolManagerAccount
    ) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        require(factoryAddress != address(0), "Factory address required");
        require(poolDeployerAddress != address(0), "PoolDeployer address required");
        require(poolManagerAccount != address(0), "Pool manager account required");

        IFactory factory = IFactory(factoryAddress);

        vm.startBroadcast(pk);

        // 1. Установить PoolDeployer
        console.log("Setting PoolDeployer...");
        factory.setPoolDeployer(poolDeployerAddress);

        address current = factory.poolDeployer();
        console.log("Current deployer:", current);
        require(current == poolDeployerAddress, "Deployer mismatch");

        // 2. Выдать POOL_MANAGER_ROLE
        console.log("Granting POOL_MANAGER_ROLE...");
        bytes32 role = factory.POOL_MANAGER_ROLE();

        if (!factory.hasRole(role, poolManagerAccount)) {
            factory.grantRole(role, poolManagerAccount);
            console.log("Role granted");
        } else {
            console.log("Role already granted");
        }

        vm.stopBroadcast();

        console.log("\n=== SETUP COMPLETE ===");
        console.log("Factory:", factoryAddress);
        console.log("PoolDeployer:", poolDeployerAddress);
        console.log("Pool Manager:", poolManagerAccount);
    }
}
