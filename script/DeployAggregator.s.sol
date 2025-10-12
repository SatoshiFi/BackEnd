// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";

contract DeployAggregator is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Address from CONFIG
        address oracleRegistry = 0x1E384f7112857C9e0437779f441F65853df7Eb26;

        // Deploy StratumDataAggregator
        StratumDataAggregator aggregator = new StratumDataAggregator(
            oracleRegistry,
            deployer  // admin = deployer
        );

        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("StratumDataAggregator:", address(aggregator));
        console.log("Oracle Registry:", oracleRegistry);
        console.log("Admin (deployer):", deployer);
        console.log("============================");
        console.log("");
        console.log("Copy this to CONFIG.CONTRACTS:");
        console.log("STRATUM_AGGREGATOR: '%s'", address(aggregator));

        vm.stopBroadcast();
    }
}
