// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/RewardHandler.sol";

contract DeployRewardHandler is Script {
    // Из config.js
    address constant SPV_CONTRACT = 0xD7f2293659A000b37Fd3973B06d4699935c511e9;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        RewardHandler rewardHandler = new RewardHandler(SPV_CONTRACT);

        console.log("==============================================");
        console.log("RewardHandler deployed at:", address(rewardHandler));
        console.log("==============================================");

        vm.stopBroadcast();
    }
}
