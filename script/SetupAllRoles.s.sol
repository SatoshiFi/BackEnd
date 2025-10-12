// script/SetupAllRoles.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

interface IPoolTokenFactory {
    function POOL_FACTORY_ROLE() external view returns (bytes32);
    function grantRole(bytes32, address) external;
}

interface ICalculatorRegistry {
    function poolFactory() external view returns (address);
    function setPoolFactory(address) external;
}

contract SetupAllRoles is Script {
    function run(
        address factoryAddress,
        address poolDeployerAddress,
        address tokenFactoryAddress,
        address calcRegistryAddress
    ) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);

        console.log("=== SETTING UP ALL ROLES ===\n");

        // 1. PoolTokenFactory - выдать POOL_FACTORY_ROLE deployer'у
        console.log("1. Granting POOL_FACTORY_ROLE to PoolDeployer...");
        IPoolTokenFactory tokenFactory = IPoolTokenFactory(tokenFactoryAddress);
        bytes32 role = tokenFactory.POOL_FACTORY_ROLE();
        tokenFactory.grantRole(role, poolDeployerAddress);
        console.log("   Done");

        // 2. CalculatorRegistry - установить Factory
        console.log("2. Setting Factory in CalculatorRegistry...");
        ICalculatorRegistry calcRegistry = ICalculatorRegistry(calcRegistryAddress);
        address currentFactory = calcRegistry.poolFactory();
        console.log("   Current factory:", currentFactory);

        if (currentFactory != factoryAddress) {
            calcRegistry.setPoolFactory(factoryAddress);
            console.log("   Factory updated");
        } else {
            console.log("   Factory already correct");
        }

        vm.stopBroadcast();

        console.log("\n=== SETUP COMPLETE ===");
        console.log("Factory:", factoryAddress);
        console.log("PoolDeployer:", poolDeployerAddress);
        console.log("TokenFactory:", tokenFactoryAddress);
        console.log("CalcRegistry:", calcRegistryAddress);
    }
}
