// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./BaseTest.sol";

import "../contracts/src/initialFROST.sol";
import "../contracts/src/vendor/cryptography/Secp256k1.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/calculators/FPPSCalculator.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/membership/PoolMembershipNFT.sol";
import "../contracts/src/SPVContract.sol";
import "../contracts/src/MultiPoolDAO.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";

contract Secp256k1ValidationTest is BaseTest {
    // Contracts
    // Using factory from BaseTest (MiningPoolFactoryCore)
    PoolMembershipNFT membershipNFT;

    // Test actors
    address admin = address(0x1);
    address participant1 = address(0x11);
    address participant2 = address(0x12);
    address participant3 = address(0x13);
    address[] participants;

    function setUp() public override {
        super.setUp(); // Initialize BaseTest infrastructure

        participants.push(participant1);
        participants.push(participant2);
        participants.push(participant3);

        // Deploy additional NFT
        membershipNFT = new PoolMembershipNFT(address(this));

        // All infrastructure is already set up in BaseTest
        // Just grant additional roles if needed
        factory.grantRole(factory.ADMIN_ROLE(), address(this));
        membershipNFT.grantRole(membershipNFT.MINTER_ROLE(), address(factory));
    }

    // TEST 1: Verify generated keys are valid points on secp256k1 curve
    function testGeneratedKeysAreValidCurvePoints() public {
        console.log("\n=== TEST: Generated Keys Must Be Valid Secp256k1 Points ===");

        vm.startPrank(admin);
        uint256 sessionId = frost.createDKGSession(2, participants);
        vm.stopPrank();

        // Complete DKG process
        _completeDKGProcess(sessionId);

        vm.startPrank(admin);

        // Get the group public key
        (,,,, bytes32 groupPubKeyX,) = frost.getSessionDetails(sessionId);

        // Get the full session data
        (,, bytes memory groupPubkey,,,,,,,,uint256 state,,,,,,,,,) =
            frost.getSession(sessionId);

        assertEq(state, 2, "Session not finalized");
        assertEq(groupPubkey.length, 64, "Should have 64 bytes (X and Y)");

        // Extract X and Y coordinates
        bytes32 pubX;
        bytes32 pubY;
        assembly {
            pubX := mload(add(groupPubkey, 32))
            pubY := mload(add(groupPubkey, 64))
        }

        console.log("  PubKey X:", uint256(pubX));
        console.log("  PubKey Y:", uint256(pubY));

        // CRITICAL TEST: Verify the key is on the secp256k1 curve
        bool isOnCurve = Secp256k1.isOnCurve(uint256(pubX), uint256(pubY));
        assertTrue(isOnCurve, "FAIL: Generated key is NOT on secp256k1 curve!");
        console.log("  OK: Key is valid point on secp256k1 curve");

        // Additional checks
        assertTrue(uint256(pubX) > 0 && uint256(pubX) < Secp256k1.P, "X not in valid range");
        assertTrue(uint256(pubY) > 0 && uint256(pubY) < Secp256k1.P, "Y not in valid range");
        console.log("  OK: X and Y coordinates are in valid range [1, P-1]");

        vm.stopPrank();
    }

    // TEST 2: Verify threshold validation
    function testThresholdValidation() public {
        console.log("\n=== TEST: Threshold Validation (t <= n) ===");

        vm.startPrank(admin);

        // Should fail: threshold > participants
        vm.expectRevert("Threshold exceeds participants");
        frost.createDKGSession(4, participants); // 4 > 3

        // Should fail: threshold = 0
        vm.expectRevert("Threshold too low");
        frost.createDKGSession(0, participants);

        // Should succeed: valid threshold
        uint256 sessionId = frost.createDKGSession(2, participants);
        assertTrue(sessionId > 0, "Valid session should be created");
        console.log("  OK: Threshold validation works correctly");

        vm.stopPrank();
    }

    // TEST 3: Verify session timeout
    function testSessionTimeout() public {
        console.log("\n=== TEST: Session Timeout After 24 Hours ===");

        vm.startPrank(admin);
        uint256 sessionId = frost.createDKGSession(2, participants);
        vm.stopPrank();

        // Submit nonce commitment before timeout
        vm.startPrank(participant1);
        frost.publishNonceCommitment(sessionId, keccak256("nonce1"));
        console.log("  OK: Can submit before timeout");
        vm.stopPrank();

        // Fast forward 25 hours
        vm.warp(block.timestamp + 25 hours);
        console.log("  TIME: Fast forwarded 25 hours");

        // Should fail after timeout
        vm.startPrank(participant2);
        vm.expectRevert("Session expired");
        frost.publishNonceCommitment(sessionId, keccak256("nonce2"));
        console.log("  OK: Cannot submit after timeout");
        vm.stopPrank();

        // Anyone can cancel expired session
        vm.startPrank(participant3); // Not creator, but can cancel expired
        frost.cancelDKGSession(sessionId);
        console.log("  OK: Non-creator can cancel expired session");
        vm.stopPrank();
    }

    // TEST 4: Verify session cancellation
    function testSessionCancellation() public {
        console.log("\n=== TEST: Session Cancellation ===");

        vm.startPrank(admin);
        uint256 sessionId = frost.createDKGSession(2, participants);

        // Creator can cancel
        frost.cancelDKGSession(sessionId);
        console.log("  OK: Creator can cancel session");

        // Cannot finalize cancelled session
        vm.expectRevert("Session not ready");
        frost.finalizeDKG(sessionId);
        console.log("  OK: Cannot finalize cancelled session");

        vm.stopPrank();

        // Non-creator cannot cancel non-expired session
        uint256 sessionId2 = frost.createDKGSession(2, participants);
        vm.startPrank(participant1);
        vm.expectRevert("Not authorized to cancel");
        frost.cancelDKGSession(sessionId2);
        console.log("  OK: Non-creator cannot cancel active session");
        vm.stopPrank();
    }

    // TEST 5: Verify different sessions generate different keys
    function testUniqueKeysPerSession() public {
        console.log("\n=== TEST: Each Session Generates Unique Keys ===");

        vm.startPrank(admin);

        // Create and finalize first session
        uint256 session1 = frost.createDKGSession(2, participants);
        vm.stopPrank();
        _completeDKGProcess(session1);

        vm.startPrank(admin);
        (,,,, bytes32 pubX1,) = frost.getSessionDetails(session1);

        // Create and finalize second session
        uint256 session2 = frost.createDKGSession(2, participants);
        vm.stopPrank();
        _completeDKGProcess(session2);

        vm.startPrank(admin);
        (,,,, bytes32 pubX2,) = frost.getSessionDetails(session2);

        console.log("  Session 1 pubX:", uint256(pubX1));
        console.log("  Session 2 pubX:", uint256(pubX2));

        assertTrue(pubX1 != pubX2, "Different sessions should generate different keys");
        console.log("  OK: Each session generates unique keys");

        vm.stopPrank();
    }

    // Helper function
    function _completeDKGProcess(uint256 sessionId) internal {
        // Submit all nonces
        for (uint i = 0; i < participants.length; i++) {
            vm.startPrank(participants[i]);
            frost.publishNonceCommitment(sessionId, keccak256(abi.encodePacked("nonce", i)));
            vm.stopPrank();
        }

        // Submit all shares
        for (uint i = 0; i < participants.length; i++) {
            vm.startPrank(participants[i]);
            for (uint j = 0; j < participants.length; j++) {
                if (i != j) {
                    frost.publishEncryptedShare(
                        sessionId,
                        participants[j],
                        abi.encodePacked("encrypted_share_", i, "_to_", j)
                    );
                }
            }
            vm.stopPrank();
        }

        // Finalize
        vm.startPrank(admin);
        frost.finalizeDKG(sessionId);
        vm.stopPrank();
    }
}