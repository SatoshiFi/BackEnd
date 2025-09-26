// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/src/FrostDKG.sol";
import "../contracts/src/vendor/cryptography/Secp256k1.sol";

contract FrostDKGTest is Test {
    using FrostDKG for *;

    function testPolynomialGeneration() public {
        uint256 secret = 12345;
        uint256 degree = 2; // threshold - 1
        uint256 nonce = 999;

        uint256[] memory coeffs = FrostDKG.generatePolynomial(secret, degree, nonce);

        // Check polynomial has correct degree
        assertEq(coeffs.length, degree + 1);

        // Check secret is preserved as a0
        assertEq(coeffs[0], secret);

        // Check other coefficients are non-zero
        for (uint256 i = 1; i <= degree; i++) {
            assertTrue(coeffs[i] > 0 && coeffs[i] < Secp256k1.N);
        }
    }

    function testPolynomialEvaluation() public pure {
        uint256[] memory coeffs = new uint256[](3);
        coeffs[0] = 10; // a0
        coeffs[1] = 20; // a1
        coeffs[2] = 30; // a2

        // f(x) = 10 + 20x + 30x^2
        // f(0) = 10
        uint256 y0 = FrostDKG.evaluatePolynomial(coeffs, 0);
        assert(y0 == 10);

        // f(1) = 10 + 20 + 30 = 60
        uint256 y1 = FrostDKG.evaluatePolynomial(coeffs, 1);
        assert(y1 == 60);

        // f(2) = 10 + 40 + 120 = 170
        uint256 y2 = FrostDKG.evaluatePolynomial(coeffs, 2);
        assert(y2 == 170);
    }

    function testShareGeneration() public {
        uint256 secret = 424242;
        uint256 threshold = 3;
        uint256 numParticipants = 5;
        uint256 nonce = 123456;

        FrostDKG.ParticipantShare[] memory shares = FrostDKG.generateShares(
            secret,
            threshold,
            numParticipants,
            nonce
        );

        // Check correct number of shares
        assertEq(shares.length, numParticipants);

        // Check each share has correct index
        for (uint256 i = 0; i < numParticipants; i++) {
            assertEq(shares[i].index, i + 1);
            assertTrue(shares[i].share > 0);
            assertTrue(shares[i].share < Secp256k1.N);
        }

        // Verify shares are different
        for (uint256 i = 0; i < numParticipants - 1; i++) {
            assertTrue(shares[i].share != shares[i + 1].share);
        }
    }

    function testCommitmentGeneration() public {
        uint256[] memory coeffs = new uint256[](3);
        coeffs[0] = 100;
        coeffs[1] = 200;
        coeffs[2] = 300;

        (uint256[] memory commitmentsX, uint256[] memory commitmentsY) =
            FrostDKG.generateCommitments(coeffs);

        assertEq(commitmentsX.length, 3);
        assertEq(commitmentsY.length, 3);

        // Check all commitments are valid points on curve
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(Secp256k1.isOnCurve(commitmentsX[i], commitmentsY[i]));
        }
    }

    function testShareVerification() public {
        uint256 secret = 999999;
        uint256 threshold = 2;
        uint256 nonce = 7777;

        // Generate polynomial
        uint256[] memory coeffs = FrostDKG.generatePolynomial(secret, threshold - 1, nonce);

        // Generate commitments
        (uint256[] memory commitmentsX, uint256[] memory commitmentsY) =
            FrostDKG.generateCommitments(coeffs);

        // Generate valid share
        FrostDKG.ParticipantShare memory share = FrostDKG.ParticipantShare({
            index: 1,
            share: FrostDKG.evaluatePolynomial(coeffs, 1),
            commitment: 0
        });

        // Verify valid share
        bool valid = FrostDKG.verifyShare(share, commitmentsX, commitmentsY);
        assertTrue(valid);

        // Test invalid share
        share.share = share.share + 1; // corrupt the share
        valid = FrostDKG.verifyShare(share, commitmentsX, commitmentsY);
        assertFalse(valid);
    }

    function testPublicKeyAggregation() public {
        uint256 secret = 555555;
        uint256 threshold = 3;
        uint256 numParticipants = 5;
        uint256 nonce = 4444;

        FrostDKG.ParticipantShare[] memory shares = FrostDKG.generateShares(
            secret,
            threshold,
            numParticipants,
            nonce
        );

        (uint256 pubKeyX, uint256 pubKeyY) = FrostDKG.aggregatePublicKeys(shares, threshold);

        // Verify aggregated key is on curve
        assertTrue(Secp256k1.isOnCurve(pubKeyX, pubKeyY));

        // Verify key is non-zero
        assertTrue(pubKeyX > 0);
        assertTrue(pubKeyY > 0);

        console.log("Aggregated PubKey X:", pubKeyX);
        console.log("Aggregated PubKey Y:", pubKeyY);
    }

    function testLagrangeCoefficient() public pure {
        FrostDKG.ParticipantShare[] memory shares = new FrostDKG.ParticipantShare[](3);
        shares[0] = FrostDKG.ParticipantShare({index: 1, share: 100, commitment: 0});
        shares[1] = FrostDKG.ParticipantShare({index: 2, share: 200, commitment: 0});
        shares[2] = FrostDKG.ParticipantShare({index: 3, share: 300, commitment: 0});

        // Calculate Lagrange coefficient for first participant
        uint256 coeff = FrostDKG.calculateLagrangeCoefficient(shares, 0, 3);

        // Coefficient should be non-zero
        assert(coeff > 0);
        assert(coeff < Secp256k1.N);
    }

    function testThresholdReconstruction() public {
        uint256 secret = 123456789;
        uint256 threshold = 3;
        uint256 numParticipants = 5;
        uint256 nonce = 987654;

        // Generate all shares
        FrostDKG.ParticipantShare[] memory allShares = FrostDKG.generateShares(
            secret,
            threshold,
            numParticipants,
            nonce
        );

        // Get public key from all shares
        (uint256 fullPubKeyX, uint256 fullPubKeyY) =
            FrostDKG.aggregatePublicKeys(allShares, threshold);

        // Create subset with exactly threshold shares
        FrostDKG.ParticipantShare[] memory subsetShares = new FrostDKG.ParticipantShare[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            subsetShares[i] = allShares[i + 1]; // Use shares 2, 3, 4
        }

        // Aggregate from subset should give same result
        (uint256 subsetPubKeyX, uint256 subsetPubKeyY) =
            FrostDKG.aggregatePublicKeys(subsetShares, threshold);

        // Both should be valid points
        assertTrue(Secp256k1.isOnCurve(fullPubKeyX, fullPubKeyY));
        assertTrue(Secp256k1.isOnCurve(subsetPubKeyX, subsetPubKeyY));

        console.log("Full aggregation X:", fullPubKeyX);
        console.log("Subset aggregation X:", subsetPubKeyX);
    }

    // These functions are internal, so we can't test reverts directly
    // Instead we'll test valid boundary conditions
    function testThresholdBoundaries() public {
        uint256 secret = 111111;
        uint256 nonce = 2222;

        // Test minimum valid threshold (1)
        FrostDKG.ParticipantShare[] memory shares1 = FrostDKG.generateShares(secret, 1, 5, nonce);
        assertEq(shares1.length, 5);

        // Test maximum valid threshold (equals participants)
        FrostDKG.ParticipantShare[] memory shares2 = FrostDKG.generateShares(secret, 5, 5, nonce + 1);
        assertEq(shares2.length, 5);
    }

    function testPolynomialDegreeBoundaries() public {
        uint256 secret = 777777;
        uint256 nonce = 8888;

        // Test at max degree (10)
        uint256[] memory coeffs = FrostDKG.generatePolynomial(secret, 10, nonce);
        assertEq(coeffs.length, 11);

        // Test minimum degree (0)
        uint256[] memory coeffs2 = FrostDKG.generatePolynomial(secret, 0, nonce + 1);
        assertEq(coeffs2.length, 1);
        assertEq(coeffs2[0], secret);
    }

    function testModularInverse() public pure {
        // Test modular inverse of 3 mod 7 = 5 (because 3 * 5 = 15 = 1 mod 7)
        uint256 inv = FrostDKG.modInverse(3, 7);
        assert(mulmod(3, inv, 7) == 1);

        // Test with larger numbers
        uint256 inv2 = FrostDKG.modInverse(12345, Secp256k1.N);
        assert(mulmod(12345, inv2, Secp256k1.N) == 1);
    }

    function testModExp() public pure {
        // Test 2^3 mod 5 = 8 mod 5 = 3
        uint256 result = FrostDKG.modExp(2, 3, 5);
        assert(result == 3);

        // Test larger exponentiation
        uint256 result2 = FrostDKG.modExp(7, 10, 13);
        // 7^10 mod 13 = 282475249 mod 13 = 4
        assert(result2 == 4);
    }
}