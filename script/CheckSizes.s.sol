// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../contracts/src/MiningPoolDAOCore.sol";
import "../contracts/src/RewardHandler.sol";
import "../contracts/src/RedemptionHandler.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";

contract CheckSizes is Script {
    function run() external {
        console.log("\n=== CONTRACT SIZES ===");
        MiningPoolDAOCore core = new MiningPoolDAOCore();
        console.log("MiningPoolDAOCore:", address(core).code.length, "bytes");

        RewardHandler rewards = new RewardHandler();
        console.log("RewardHandler:", address(rewards).code.length, "bytes");

        RedemptionHandler redemption = new RedemptionHandler();
        console.log("RedemptionHandler:", address(redemption).code.length, "bytes");

        // Check old MiningPoolDAO if it exists
        console.log("\n=== SIZE LIMIT: 24576 bytes ===");
    }
}