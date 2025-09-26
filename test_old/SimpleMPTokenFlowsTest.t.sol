// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/src/SPVContract.sol";
import "../contracts/src/tokens/PoolMpToken.sol";

/**
 * @title SimpleMPTokenFlowsTest
 * @notice Simplified test for MP token flows - tests core functionality only
 */
contract SimpleMPTokenFlowsTest is Test {

    SPVContract spv;
    PoolMpToken mpToken;

    address admin = address(1);
    address poolCore = address(0xBEEF);
    address miner1 = address(0x1001);
    address miner2 = address(0x1002);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy SPV contract
        spv = new SPVContract();

        // Deploy MP token with pool core as minter
        mpToken = new PoolMpToken(
            "Test MP Token",
            "mpBTC",
            poolCore,
            false
        );

        vm.stopPrank();
    }

    /**
     * @notice Test Flow 1: MP token minting (simplified without SPV)
     */
    function testFlow1_MPTokenMinting() public {
        console.log("\n=== FLOW 1: MP Token Minting ===\n");

        // Skip SPV verification for this simplified test
        // Focus on MP token functionality
        console.log("Step 1: Skipping SPV verification (simplified test)");
        console.log("        In production: would verify Bitcoin blocks");

        vm.startPrank(admin);

        // Step 2: Mint MP tokens from pool
        vm.stopPrank();
        vm.startPrank(poolCore);

        uint256 amount1 = 250000000; // 2.5 BTC in satoshis
        uint256 amount2 = 175000000; // 1.75 BTC in satoshis

        mpToken.mint(miner1, amount1);
        mpToken.mint(miner2, amount2);

        console.log("\nStep 2: Minted MP tokens");
        console.log("  Miner1:", mpToken.balanceOf(miner1), "satoshis");
        console.log("  Miner2:", mpToken.balanceOf(miner2), "satoshis");

        assertEq(mpToken.balanceOf(miner1), amount1, "Miner1 should have correct balance");
        assertEq(mpToken.balanceOf(miner2), amount2, "Miner2 should have correct balance");

        vm.stopPrank();

        console.log("\n[SUCCESS] FLOW 1 COMPLETE");
    }

    /**
     * @notice Test Flow 2: MP token burning for redemptions
     */
    function testFlow2_MPTokenBurning() public {
        // Setup: First mint some tokens
        vm.startPrank(poolCore);
        mpToken.mint(miner1, 500000000); // 5 BTC
        vm.stopPrank();

        console.log("\n=== FLOW 2: MP Token Burning for Redemption ===\n");

        uint256 initialBalance = mpToken.balanceOf(miner1);
        console.log("Step 1: Initial balance:", initialBalance, "satoshis");

        // Pool burns tokens for redemption (pool has BURNER_ROLE)
        vm.startPrank(poolCore);
        uint256 burnAmount = 200000000; // 2 BTC

        mpToken.burn(miner1, burnAmount);
        console.log("Step 2: Burned", burnAmount, "satoshis for redemption");

        uint256 finalBalance = mpToken.balanceOf(miner1);
        console.log("Step 3: Final balance:", finalBalance, "satoshis");

        assertEq(finalBalance, initialBalance - burnAmount, "Balance should be reduced by burn amount");

        vm.stopPrank();

        console.log("\n[SUCCESS] FLOW 2 COMPLETE");
    }

    /**
     * @notice Test Flow 3: MP token transfers between users
     */
    function testFlow3_MPTokenTransfers() public {
        // Setup: Mint tokens to miner1
        vm.startPrank(poolCore);
        mpToken.mint(miner1, 1000000000); // 10 BTC
        vm.stopPrank();

        console.log("\n=== FLOW 3: MP Token Transfers ===\n");

        uint256 miner1Initial = mpToken.balanceOf(miner1);
        uint256 miner2Initial = mpToken.balanceOf(miner2);

        console.log("Initial balances:");
        console.log("  Miner1:", miner1Initial, "satoshis");
        console.log("  Miner2:", miner2Initial, "satoshis");

        // Transfer from miner1 to miner2
        vm.startPrank(miner1);
        uint256 transferAmount = 300000000; // 3 BTC

        mpToken.transfer(miner2, transferAmount);
        console.log("\nTransferred", transferAmount, "satoshis from Miner1 to Miner2");

        vm.stopPrank();

        uint256 miner1Final = mpToken.balanceOf(miner1);
        uint256 miner2Final = mpToken.balanceOf(miner2);

        console.log("\nFinal balances:");
        console.log("  Miner1:", miner1Final, "satoshis");
        console.log("  Miner2:", miner2Final, "satoshis");

        assertEq(miner1Final, miner1Initial - transferAmount, "Miner1 balance incorrect");
        assertEq(miner2Final, miner2Initial + transferAmount, "Miner2 balance incorrect");

        console.log("\n[SUCCESS] FLOW 3 COMPLETE");
    }

    /**
     * @notice Test all flows in sequence
     */
    function testAllFlowsSequential() public {
        console.log("\n=============================================================");
        console.log("TESTING ALL MP TOKEN FLOWS SEQUENTIALLY");
        console.log("=============================================================");

        testFlow1_MPTokenMinting();
        testFlow2_MPTokenBurning();
        testFlow3_MPTokenTransfers();

        console.log("\n=============================================================");
        console.log("[COMPLETE] ALL MP TOKEN FLOWS TESTED SUCCESSFULLY!");
        console.log("=============================================================\n");
    }
}