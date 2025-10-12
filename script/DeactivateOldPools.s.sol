// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";

contract DeactivateOldPools is Script {
    address constant FACTORY = 0xb87DB5fF6802A8B0bd48fb314234916f1BA27C1a;
    address constant POOL_1 = 0x2f624C204B9d8C8Cd941C7dA6A113552eCdd4C12;
    address constant POOL_2 = 0x27F8DFE525Ac2B86c33d1de8103441ac86b955A7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MiningPoolFactoryCore factory = MiningPoolFactoryCore(FACTORY);

        console.log("Deactivating old pools...");
        console.log("");

        // Deactivate Pool 1
        console.log("Pool 1:", POOL_1);
        factory.deactivatePool(POOL_1);
        console.log("  [OK] Deactivated");

        console.log("");

        // Deactivate Pool 2
        console.log("Pool 2:", POOL_2);
        factory.deactivatePool(POOL_2);
        console.log("  [OK] Deactivated");

        console.log("");
        console.log("==============================================");
        console.log("[SUCCESS] Both pools deactivated");
        console.log("==============================================");
        console.log("");
        console.log("Now you can create new pools with:");
        console.log("- New PoolDeployerV2");
        console.log("- New RewardHandler with correct logic");

        vm.stopBroadcast();
    }
}
