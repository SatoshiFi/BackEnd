// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./vendor/cryptography/Secp256k1.sol";
import "./vendor/cryptography/Secp256k1Arithmetic.sol";
import "./vendor/cryptography/Memory.sol";
import "./vendor/cryptography/ModExp.sol";

/**
 * @title FrostDKG
 * @notice Implements FROST Distributed Key Generation with Shamir Secret Sharing
 * @dev This contract handles the cryptographic operations for FROST DKG
 */
library FrostDKG {
    using Secp256k1 for uint256;
    using Secp256k1Arithmetic for uint256;

    // Maximum degree of polynomial (threshold - 1)
    uint256 constant MAX_POLYNOMIAL_DEGREE = 10;

    // Participant share structure
    struct ParticipantShare {
        uint256 index;      // Participant index (x-coordinate)
        uint256 share;      // Secret share value (y-coordinate)
        uint256 commitment; // Public commitment to verify share
    }

    // Polynomial coefficients for secret sharing
    struct Polynomial {
        uint256[] coefficients; // a0, a1, a2, ..., at-1
        uint256 degree;         // t - 1
    }

    // DKG round data
    struct DKGRound {
        uint256 threshold;
        uint256 numParticipants;
        mapping(uint256 => ParticipantShare) shares;
        mapping(uint256 => uint256) commitments;
        uint256 aggregatedPubKeyX;
        uint256 aggregatedPubKeyY;
    }

    /**
     * @dev Generate random polynomial coefficients for Shamir secret sharing
     * @param secret The secret value (a0 coefficient)
     * @param degree The degree of polynomial (threshold - 1)
     * @param nonce Additional randomness
     * @return coeffs Array of polynomial coefficients
     */
    function generatePolynomial(
        uint256 secret,
        uint256 degree,
        uint256 nonce
    ) internal view returns (uint256[] memory coeffs) {
        require(degree <= MAX_POLYNOMIAL_DEGREE, "Degree too high");

        coeffs = new uint256[](degree + 1);
        coeffs[0] = secret; // a0 = secret

        // Generate random coefficients a1, a2, ..., at-1
        for (uint256 i = 1; i <= degree; i++) {
            // Use blockhash and other entropy sources for randomness
            // In production, should use VRF or commit-reveal for better randomness
            coeffs[i] = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                nonce,
                i
            ))) % Secp256k1.N;

            // Ensure non-zero coefficient
            if (coeffs[i] == 0) {
                coeffs[i] = 1;
            }
        }
    }

    /**
     * @dev Evaluate polynomial at given x using Horner's method
     * @param coeffs Polynomial coefficients
     * @param x Point to evaluate at
     * @return y The polynomial value at x
     */
    function evaluatePolynomial(
        uint256[] memory coeffs,
        uint256 x
    ) internal pure returns (uint256 y) {
        require(coeffs.length > 0, "Empty polynomial");

        // Horner's method: a0 + x*(a1 + x*(a2 + x*(...)))
        y = coeffs[coeffs.length - 1];

        for (uint256 i = coeffs.length - 1; i > 0; i--) {
            y = addmod(
                coeffs[i - 1],
                mulmod(y, x, Secp256k1.N),
                Secp256k1.N
            );
        }
    }

    /**
     * @dev Generate Shamir secret shares for participants
     * @param secret The secret to share
     * @param threshold Minimum shares needed to reconstruct
     * @param numParticipants Total number of participants
     * @param nonce Random nonce
     * @return shares Array of secret shares for each participant
     */
    function generateShares(
        uint256 secret,
        uint256 threshold,
        uint256 numParticipants,
        uint256 nonce
    ) internal view returns (ParticipantShare[] memory shares) {
        require(threshold > 0, "Invalid threshold");
        require(threshold <= numParticipants, "Threshold exceeds participants");

        // Generate polynomial with secret as constant term
        uint256[] memory coeffs = generatePolynomial(
            secret,
            threshold - 1,
            nonce
        );

        shares = new ParticipantShare[](numParticipants);

        // Evaluate polynomial at x = 1, 2, ..., n for each participant
        for (uint256 i = 0; i < numParticipants; i++) {
            uint256 x = i + 1; // Participant index (never use 0)
            uint256 y = evaluatePolynomial(coeffs, x);

            shares[i] = ParticipantShare({
                index: x,
                share: y,
                commitment: 0 // Will be filled with public commitments
            });
        }
    }

    /**
     * @dev Generate public commitments for polynomial coefficients
     * @param coeffs Polynomial coefficients
     * @return commitmentsX X-coordinates of commitment points
     * @return commitmentsY Y-coordinates of commitment points
     */
    function generateCommitments(
        uint256[] memory coeffs
    ) internal view returns (
        uint256[] memory commitmentsX,
        uint256[] memory commitmentsY
    ) {
        commitmentsX = new uint256[](coeffs.length);
        commitmentsY = new uint256[](coeffs.length);

        uint256 memPtr = Memory.allocate(192);

        for (uint256 i = 0; i < coeffs.length; i++) {
            // Commitment = coeff * G (generator point)
            (uint256 gxProj, uint256 gyProj, uint256 gzProj) =
                Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                    Secp256k1.GX,
                    Secp256k1.GY
                );

            // Multiply by coefficient
            (uint256 cxProj, uint256 cyProj, uint256 czProj) =
                Secp256k1Arithmetic.mulProjectivePoint(
                    gxProj,
                    gyProj,
                    gzProj,
                    coeffs[i]
                );

            // Convert back to affine
            (commitmentsX[i], commitmentsY[i]) =
                Secp256k1Arithmetic.convertProjectivePointToAffinePoint(
                    memPtr,
                    cxProj,
                    cyProj,
                    czProj
                );
        }
    }

    /**
     * @dev Verify a share against public commitments using polynomial commitment
     * @param share The share to verify
     * @param commitmentsX X-coordinates of commitments
     * @param commitmentsY Y-coordinates of commitments
     * @return valid True if share is valid
     */
    function verifyShare(
        ParticipantShare memory share,
        uint256[] memory commitmentsX,
        uint256[] memory commitmentsY
    ) internal view returns (bool valid) {
        require(commitmentsX.length == commitmentsY.length, "Invalid commitments");
        require(commitmentsX.length > 0, "Empty commitments");

        uint256 memPtr = Memory.allocate(192);

        // Compute expected commitment: sum(Ci * x^i) for i=0 to t-1
        uint256 expectedX = commitmentsX[0];
        uint256 expectedY = commitmentsY[0];

        uint256 xPower = share.index;

        for (uint256 i = 1; i < commitmentsX.length; i++) {
            // Convert commitment to projective
            (uint256 cxProj, uint256 cyProj, uint256 czProj) =
                Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                    commitmentsX[i],
                    commitmentsY[i]
                );

            // Multiply by x^i
            (uint256 rxProj, uint256 ryProj, uint256 rzProj) =
                Secp256k1Arithmetic.mulProjectivePoint(
                    cxProj,
                    cyProj,
                    czProj,
                    xPower
                );

            // Convert to affine
            (uint256 rx, uint256 ry) =
                Secp256k1Arithmetic.convertProjectivePointToAffinePoint(
                    memPtr,
                    rxProj,
                    ryProj,
                    rzProj
                );

            // Add to expected point
            (uint256 exProj, uint256 eyProj, uint256 ezProj) =
                Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                    expectedX,
                    expectedY
                );

            (uint256 rxProj2, uint256 ryProj2, uint256 rzProj2) =
                Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                    rx,
                    ry
                );

            (uint256 sumXProj, uint256 sumYProj, uint256 sumZProj) =
                Secp256k1Arithmetic.addProjectivePoint(
                    exProj,
                    eyProj,
                    ezProj,
                    rxProj2,
                    ryProj2,
                    rzProj2
                );

            (expectedX, expectedY) =
                Secp256k1Arithmetic.convertProjectivePointToAffinePoint(
                    memPtr,
                    sumXProj,
                    sumYProj,
                    sumZProj
                );

            xPower = mulmod(xPower, share.index, Secp256k1.N);
        }

        // Compute share * G
        (uint256 gxProj, uint256 gyProj, uint256 gzProj) =
            Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                Secp256k1.GX,
                Secp256k1.GY
            );

        (uint256 sxProj, uint256 syProj, uint256 szProj) =
            Secp256k1Arithmetic.mulProjectivePoint(
                gxProj,
                gyProj,
                gzProj,
                share.share
            );

        (uint256 sharePointX, uint256 sharePointY) =
            Secp256k1Arithmetic.convertProjectivePointToAffinePoint(
                memPtr,
                sxProj,
                syProj,
                szProj
            );

        // Check if share * G == expected commitment
        valid = (sharePointX == expectedX && sharePointY == expectedY);
    }

    /**
     * @dev Aggregate public keys from participant shares
     * @param shares Array of participant shares
     * @param threshold Minimum shares needed
     * @return pubKeyX Aggregated public key X coordinate
     * @return pubKeyY Aggregated public key Y coordinate
     */
    function aggregatePublicKeys(
        ParticipantShare[] memory shares,
        uint256 threshold
    ) internal view returns (uint256 pubKeyX, uint256 pubKeyY) {
        require(shares.length >= threshold, "Insufficient shares");

        uint256 memPtr = Memory.allocate(192);

        // Start with identity point
        (pubKeyX, pubKeyY) = Secp256k1Arithmetic.identityAffinePoint();
        bool isFirst = true;

        for (uint256 i = 0; i < shares.length && i < threshold; i++) {
            // Compute share * G
            (uint256 gxProj, uint256 gyProj, uint256 gzProj) =
                Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                    Secp256k1.GX,
                    Secp256k1.GY
                );

            // Calculate Lagrange coefficient
            uint256 lagrangeCoeff = calculateLagrangeCoefficient(
                shares,
                i,
                threshold
            );

            // Multiply by Lagrange coefficient and share value
            uint256 scaledShare = mulmod(
                shares[i].share,
                lagrangeCoeff,
                Secp256k1.N
            );

            (uint256 sxProj, uint256 syProj, uint256 szProj) =
                Secp256k1Arithmetic.mulProjectivePoint(
                    gxProj,
                    gyProj,
                    gzProj,
                    scaledShare
                );

            (uint256 sx, uint256 sy) =
                Secp256k1Arithmetic.convertProjectivePointToAffinePoint(
                    memPtr,
                    sxProj,
                    syProj,
                    szProj
                );

            if (isFirst) {
                pubKeyX = sx;
                pubKeyY = sy;
                isFirst = false;
            } else {
                // Add to accumulated public key
                (uint256 pxProj, uint256 pyProj, uint256 pzProj) =
                    Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                        pubKeyX,
                        pubKeyY
                    );

                (uint256 sxProj2, uint256 syProj2, uint256 szProj2) =
                    Secp256k1Arithmetic.convertAffinePointToProjectivePoint(
                        sx,
                        sy
                    );

                (uint256 rxProj, uint256 ryProj, uint256 rzProj) =
                    Secp256k1Arithmetic.addProjectivePoint(
                        pxProj,
                        pyProj,
                        pzProj,
                        sxProj2,
                        syProj2,
                        szProj2
                    );

                (pubKeyX, pubKeyY) =
                    Secp256k1Arithmetic.convertProjectivePointToAffinePoint(
                        memPtr,
                        rxProj,
                        ryProj,
                        rzProj
                    );
            }
        }

        require(Secp256k1.isOnCurve(pubKeyX, pubKeyY), "Invalid aggregated key");
    }

    /**
     * @dev Calculate Lagrange coefficient for polynomial interpolation
     * @param shares Array of shares
     * @param idx Index of current share
     * @param threshold Number of shares to use
     * @return coeff The Lagrange coefficient
     */
    function calculateLagrangeCoefficient(
        ParticipantShare[] memory shares,
        uint256 idx,
        uint256 threshold
    ) internal pure returns (uint256 coeff) {
        require(idx < shares.length, "Invalid index");

        uint256 xi = shares[idx].index;
        coeff = 1;

        for (uint256 j = 0; j < threshold; j++) {
            if (j != idx) {
                uint256 xj = shares[j].index;

                // Calculate (0 - xj) / (xi - xj) mod N
                uint256 numerator = Secp256k1.N - xj; // -xj mod N
                uint256 denominator = (xi >= xj)
                    ? xi - xj
                    : Secp256k1.N - (xj - xi);

                // Modular inverse of denominator
                uint256 invDenominator = modInverse(denominator, Secp256k1.N);

                // Multiply coefficient
                coeff = mulmod(
                    coeff,
                    mulmod(numerator, invDenominator, Secp256k1.N),
                    Secp256k1.N
                );
            }
        }
    }

    /**
     * @dev Calculate modular inverse using extended Euclidean algorithm
     * @param a Value to invert
     * @param m Modulus
     * @return inv Modular inverse of a mod m
     */
    function modInverse(uint256 a, uint256 m) internal pure returns (uint256 inv) {
        require(a != 0, "Cannot invert zero");
        require(m != 0, "Invalid modulus");

        // Use Fermat's little theorem: a^(m-2) mod m
        // For secp256k1, m = N (the order)
        inv = modExp(a, m - 2, m);
    }

    /**
     * @dev Modular exponentiation
     * @param base Base value
     * @param exp Exponent
     * @param mod Modulus
     * @return result base^exp mod mod
     */
    function modExp(uint256 base, uint256 exp, uint256 mod) internal pure returns (uint256 result) {
        result = 1;
        base = base % mod;

        while (exp > 0) {
            if (exp % 2 == 1) {
                result = mulmod(result, base, mod);
            }
            exp = exp >> 1;
            base = mulmod(base, base, mod);
        }
    }
}