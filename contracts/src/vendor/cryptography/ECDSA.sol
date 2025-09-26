// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Secp256k1} from "./Secp256k1.sol";
import {Secp256k1Arithmetic} from "./Secp256k1Arithmetic.sol";
import {ModExp} from "./ModExp.sol";
import {Memory} from "./Memory.sol";
import {AffinePoint} from "./AffinePoint.sol";

/// @notice Minimal ECDSA helpers with self-contained affine math (no external mul/mulG/toJacobian needed)
library ECDSA {
    /// ====== internal helpers (finite field over P) ======

    function _modInvP(uint256 memPtr, uint256 a) private view returns (uint256) {
        // inverse in F_p: a^(P-2) mod P  (P is prime)
        return ModExp.modexp(memPtr, a % Secp256k1.P, Secp256k1.P - 2, Secp256k1.P);
    }

    function _modAddP(uint256 a, uint256 b) private pure returns (uint256) {
        return addmod(a, b, Secp256k1.P);
    }

    function _modSubP(uint256 a, uint256 b) private pure returns (uint256) {
        // a - b mod P
        return addmod(a, Secp256k1.P - (b % Secp256k1.P), Secp256k1.P);
    }

    function _modMulP(uint256 a, uint256 b) private pure returns (uint256) {
        return mulmod(a, b, Secp256k1.P);
    }

    function _squareP(uint256 a) private pure returns (uint256) {
        return mulmod(a, a, Secp256k1.P);
    }

    ///  Elliptic curve point doubling in affine coordinates.
    ///  (x3,y3,inf) where 'inf' marks point at infinity.
    function _doubleAffine(uint256 memPtr, uint256 x1, uint256 y1)
        private
        view
        returns (uint256 x3, uint256 y3, bool inf)
    {
        if (y1 == 0) {
            // tangent is vertical -> infinity
            return (0, 0, true);
        }
        // lambda = (3*x1^2) / (2*y1) mod P   (a = 0 for secp256k1)
        uint256 num = mulmod(3, _squareP(x1), Secp256k1.P);
        uint256 denInv = _modInvP(memPtr, mulmod(2, y1, Secp256k1.P));
        uint256 lambda = _modMulP(num, denInv);

        // x3 = lambda^2 - 2*x1
        x3 = _modSubP(_squareP(lambda), _modAddP(x1, x1));
        // y3 = lambda*(x1 - x3) - y1
        y3 = _modSubP(_modMulP(lambda, _modSubP(x1, x3)), y1);
    }

    /// @dev Elliptic curve point addition in affine coordinates (P != Q case mostly).
    /// Handles special cases, returns infinity when P == -Q.
    function _addAffine(uint256 memPtr, uint256 x1, uint256 y1, uint256 x2, uint256 y2)
        private
        view
        returns (uint256 x3, uint256 y3, bool inf)
    {
        if (x1 == 0 && y1 == 0) return (x2, y2, false);       // ∞ + Q = Q
        if (x2 == 0 && y2 == 0) return (x1, y1, false);       // P + ∞ = P

        if (x1 == x2) {
            // P == Q or P == -Q
            if ((y1 + y2) % Secp256k1.P == 0) {
                // P == -Q -> infinity
                return (0, 0, true);
            }
            // P == Q -> use doubling
            return _doubleAffine(memPtr, x1, y1);
        }

        // lambda = (y2 - y1) / (x2 - x1) mod P
        uint256 num = _modSubP(y2, y1);
        uint256 denInv = _modInvP(memPtr, _modSubP(x2, x1));
        uint256 lambda = _modMulP(num, denInv);

        // x3 = lambda^2 - x1 - x2
        x3 = _modSubP(_squareP(lambda), _modAddP(x1, x2));
        // y3 = lambda*(x1 - x3) - y1
        y3 = _modSubP(_modMulP(lambda, _modSubP(x1, x3)), y1);
    }

    /// @dev Scalar multiply (double-and-add) in affine coordinates.
    /// Uses simple binary ladder; not gas-optimal, but robust and standalone.
    function _scalarMul(uint256 memPtr, uint256 x, uint256 y, uint256 k)
        private
        view
        returns (uint256 rx, uint256 ry, bool inf)
    {
        // R = ∞
        rx = 0; ry = 0; inf = true;

        if (k == 0) return (0, 0, true);

        // running point = (x, y)
        uint256 px = x;
        uint256 py = y;

        uint256 scalar = k;
        while (scalar != 0) {
            if (scalar & 1 == 1) {
                if (inf) {
                    // R = P
                    rx = px; ry = py; inf = false;
                } else {
                    (rx, ry, inf) = _addAffine(memPtr, rx, ry, px, py);
                }
            }
            // P = 2P
            (px, py, /*infP*/) = _doubleAffine(memPtr, px, py);
            scalar >>= 1;
        }
    }

    /// ====== ECDSA recovery ======

    /// @notice Recover public key from ECDSA `(r, s, v)` and message hash `msgHash`.
    /// @dev Uses formula with s^{-1}:
    ///      u1 = (-e) * s^{-1} mod n,  u2 = r * s^{-1} mod n,
    ///      Q = u1 * G + u2 * R,  where R is reconstructed from (x=r, parity=v&1).
    function recoverPubKey(
        bytes32 msgHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (AffinePoint memory Q) {
        uint256 rU = uint256(r);
        uint256 sU = uint256(s);

        // sanity for scalars in [1, N-1]
        require(rU > 0 && rU < Secp256k1.N, "r overflow");
        require(sU > 0 && sU < Secp256k1.N, "s overflow");

        // reconstruct R from x=r and y-parity (v&1)
        bool isYOdd = (v & 1) == 1;
        require(rU < Secp256k1.P, "x overflow");

        uint256 memPtr = Memory.allocate(0x200);

        uint256 yCompressed = isYOdd ? 3 : 2;
        (uint256 Rx, uint256 Ry) =
            Secp256k1Arithmetic.decompressToAffinePoint(memPtr, rU, yCompressed);

        // s^{-1} mod n  (n is prime)
        uint256 sInv = ModExp.modexp(memPtr, sU, Secp256k1.N - 2, Secp256k1.N);

        // u1 = (-e) * sInv mod n   (avoid negative by (N - (e % N)))
        uint256 e = uint256(msgHash) % Secp256k1.N;
        uint256 u1 = mulmod(Secp256k1.N - e, sInv, Secp256k1.N);
        uint256 u2 = mulmod(rU, sInv, Secp256k1.N);

        // Q = u1*G + u2*R  (pure affine math)
        (uint256 q1x, uint256 q1y, bool q1inf) = _scalarMul(memPtr, Secp256k1.GX, Secp256k1.GY, u1);
        (uint256 q2x, uint256 q2y, bool q2inf) = _scalarMul(memPtr, Rx, Ry, u2);

        uint256 Qx;
        uint256 Qy;
        bool Qinf;

        if (q1inf && q2inf) {
            // both infinity -> invalid (shouldn't happen for valid sig)
            return AffinePoint(0, 0);
        } else if (q1inf) {
            Qx = q2x; Qy = q2y; Qinf = q2inf;
        } else if (q2inf) {
            Qx = q1x; Qy = q1y; Qinf = q1inf;
        } else {
            (Qx, Qy, Qinf) = _addAffine(memPtr, q1x, q1y, q2x, q2y);
        }

        require(!Qinf, "recovery to infinity");
        Q = AffinePoint(Qx, Qy);
    }
}
