// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../contracts/src/mocks/MockSPVContract.sol";

contract SimpleDeployTest is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Simple Deployment Test");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying MockSPVContract...");
        MockSPVContract spv = new MockSPVContract();
        console.log("MockSPV deployed at:", address(spv));

        vm.stopBroadcast();

        console.log("\n[SUCCESS] Test deployment complete!");
    }
}