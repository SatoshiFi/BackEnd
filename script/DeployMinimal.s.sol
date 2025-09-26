// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/initialFROST.sol";
import "../contracts/src/SPVContract.sol";
import "../contracts/src/MultiPoolDAO.sol";

contract DeployMinimalScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==================================================");
        console.log("Minimal Deployment to Sepolia");
        console.log("Deployer:", deployer);
        console.log("==================================================");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy only essential contracts
        console.log("\n1. Deploying FROST...");
        initialFROSTCoordinator frost = new initialFROSTCoordinator();
        console.log("   FROST deployed at:", address(frost));

        console.log("\n2. Deploying SPV...");
        SPVContract spv = new SPVContract();
        console.log("   SPV deployed at:", address(spv));

        console.log("\n3. Deploying MultiPoolDAO...");
        MultiPoolDAO dao = new MultiPoolDAO();
        console.log("   MultiPoolDAO deployed at:", address(dao));

        // Initialize MultiPoolDAO
        dao.initialize(
            address(frost),
            hex"", // Empty group pubkey for now
            7 days, // Redemption timeout
            deployer // Slash receiver
        );
        console.log("   MultiPoolDAO initialized");

        vm.stopBroadcast();

        console.log("\n==================================================");
        console.log("Deployment Complete!");
        console.log("==================================================");
        console.log("\nDeployed Addresses:");
        console.log("  FROST:", address(frost));
        console.log("  SPV:", address(spv));
        console.log("  MultiPoolDAO:", address(dao));

        // Save to JSON for reference
        string memory json = "deployment";
        vm.serializeAddress(json, "frost", address(frost));
        vm.serializeAddress(json, "spv", address(spv));
        string memory finalJson = vm.serializeAddress(json, "dao", address(dao));

        // Try to write, but don't fail if it can't
        try vm.writeJson(finalJson, "./deployments/minimal_sepolia.json") {
            console.log("\nAddresses saved to: deployments/minimal_sepolia.json");
        } catch {
            console.log("\nCould not save addresses to file");
        }
    }
}