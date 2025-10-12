// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/RewardHandler.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";
import "../contracts/src/MiningPoolDAOCore.sol";
import "../contracts/src/tokens/PoolMpToken.sol";

contract DeployAndSetup is Script {
    // Core Infrastructure
    address constant SPV_CONTRACT = 0xD7f2293659A000b37Fd3973B06d4699935c511e9;
    address constant FACTORY = 0xb87DB5fF6802A8B0bd48fb314234916f1BA27C1a;

    // Existing pools
    address constant POOL_1 = 0x2f624C204B9d8C8Cd941C7dA6A113552eCdd4C12;
    address constant POOL_2 = 0x27F8DFE525Ac2B86c33d1de8103441ac86b955A7;

    // MP tokens (checksummed)
    address constant POOL_1_TOKEN = 0x4055d483417d24715138f1384368FAc859222940;
    address constant POOL_2_TOKEN = 0x4172b6a5cCd856C9FA5F03c253BC4D1222c98488;

    // Old handlers
    address constant OLD_REWARD_HANDLER = 0x8B7bD9568DC90641D00649f5C7EA7f941644FF64;
    address constant REDEMPTION_HANDLER = 0x6fa2409EF49D87A8261F06E17fFd8031ed0FCDB7;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("==============================================");
        console.log("STEP 1: DEPLOY NEW CONTRACTS");
        console.log("==============================================");

        // Deploy new RewardHandler
        RewardHandler newRewardHandler = new RewardHandler(SPV_CONTRACT);
        console.log("New RewardHandler:", address(newRewardHandler));

        // Deploy new PoolDeployerV2
        PoolDeployerV2 newDeployer = new PoolDeployerV2(FACTORY, SPV_CONTRACT);
        console.log("New PoolDeployerV2:", address(newDeployer));
        console.log("  Internal RewardHandler:", newDeployer.rewardHandler());

        console.log("");
        console.log("==============================================");
        console.log("STEP 2: UPDATE EXISTING POOLS");
        console.log("==============================================");

        // Update Pool 1
        console.log("Updating Pool 1:", POOL_1);
        MiningPoolDAOCore(POOL_1).setHandlers(
            address(newRewardHandler),
                                              REDEMPTION_HANDLER
        );
        console.log("  [OK] Handlers updated");

        // Update Pool 2
        console.log("Updating Pool 2:", POOL_2);
        MiningPoolDAOCore(POOL_2).setHandlers(
            address(newRewardHandler),
                                              REDEMPTION_HANDLER
        );
        console.log("  [OK] Handlers updated");

        console.log("");
        console.log("==============================================");
        console.log("STEP 3: GRANT MINTER ROLES");
        console.log("==============================================");

        // Grant MINTER_ROLE for Pool 1 Token
        console.log("Pool 1 Token:", POOL_1_TOKEN);
        PoolMpToken token1 = PoolMpToken(POOL_1_TOKEN);
        bytes32 MINTER_ROLE = token1.MINTER_ROLE();

        if (!token1.hasRole(MINTER_ROLE, address(newRewardHandler))) {
            token1.grantRole(MINTER_ROLE, address(newRewardHandler));
            console.log("  [OK] Granted MINTER_ROLE to new RewardHandler");
        } else {
            console.log("  [SKIP] Already has MINTER_ROLE");
        }

        // Revoke from old handler
        if (token1.hasRole(MINTER_ROLE, OLD_REWARD_HANDLER)) {
            token1.revokeRole(MINTER_ROLE, OLD_REWARD_HANDLER);
            console.log("  [OK] Revoked MINTER_ROLE from old RewardHandler");
        }

        console.log("");

        // Grant MINTER_ROLE for Pool 2 Token
        console.log("Pool 2 Token:", POOL_2_TOKEN);
        PoolMpToken token2 = PoolMpToken(POOL_2_TOKEN);

        if (!token2.hasRole(MINTER_ROLE, address(newRewardHandler))) {
            token2.grantRole(MINTER_ROLE, address(newRewardHandler));
            console.log("  [OK] Granted MINTER_ROLE to new RewardHandler");
        } else {
            console.log("  [SKIP] Already has MINTER_ROLE");
        }

        if (token2.hasRole(MINTER_ROLE, OLD_REWARD_HANDLER)) {
            token2.revokeRole(MINTER_ROLE, OLD_REWARD_HANDLER);
            console.log("  [OK] Revoked MINTER_ROLE from old RewardHandler");
        }

        console.log("");
        console.log("==============================================");
        console.log("STEP 4: UPDATE FACTORY (optional)");
        console.log("==============================================");
        console.log("To use new PoolDeployer for future pools:");
        console.log("cast send", FACTORY, "setPoolDeployer(address)", address(newDeployer));

        console.log("");
        console.log("==============================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("==============================================");
        console.log("New RewardHandler:     ", address(newRewardHandler));
        console.log("New PoolDeployerV2:    ", address(newDeployer));
        console.log("Pool 1 updated:        ", POOL_1);
        console.log("Pool 2 updated:        ", POOL_2);
        console.log("");
        console.log("==============================================");
        console.log("[SUCCESS] ALL STEPS COMPLETED");
        console.log("==============================================");

        vm.stopBroadcast();
    }
}
