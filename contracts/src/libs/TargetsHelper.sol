// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TargetsHelper {
    uint32 internal constant DIFFICULTY_ADJUSTMENT_INTERVAL = 2016;
    uint32 internal constant TARGET_TIME_PER_BLOCK = 600;
    uint32 internal constant TARGET_TIMESPAN = TARGET_TIME_PER_BLOCK * DIFFICULTY_ADJUSTMENT_INTERVAL;

    function bitsToTarget(uint32 bits) internal pure returns (uint256) {
        uint256 exponent = uint8(bits >> 24);
        uint256 mantissa = uint256(bits & 0xFFFFFF);
        if (exponent == 0) return 0;
        if (exponent <= 3) {
            return mantissa >> (8 * (3 - exponent));
        } else {
            return mantissa * (1 << (8 * (exponent - 3)));
        }
    }

    function targetToBits(uint256 target) internal pure returns (uint32) {
        if (target == 0) return 0;
        uint256 n = _bytesLen(target);
        uint256 exponent = n;
        uint256 mantissa;

        if (n <= 3) {
            mantissa = target << (8 * (3 - n));
            exponent = 3;
        } else {
            mantissa = target >> (8 * (n - 3));
            if ((mantissa & 0x800000) != 0) {
                mantissa >>= 8;
                exponent = n + 1;
            }
        }

        return uint32((exponent << 24) | (mantissa & 0xFFFFFF));
    }

    function workFromTarget(uint256 target) internal pure returns (uint256) {
        unchecked {
            return type(uint256).max / (target + 1);
        }
    }

    function isAdjustmentBlock(uint64 height) internal pure returns (bool) {
        return height != 0 && (height % DIFFICULTY_ADJUSTMENT_INTERVAL == 0);
    }

    function retarget(uint256 prevTarget, uint32 actualTimespan) internal pure returns (uint256) {
        uint32 span = actualTimespan;
        uint32 minSpan = TARGET_TIMESPAN / 4;
        uint32 maxSpan = TARGET_TIMESPAN * 4;

        if (span < minSpan) span = minSpan;
        if (span > maxSpan) span = maxSpan;

        uint256 newTarget = (prevTarget * span) / TARGET_TIMESPAN;
        if (newTarget == 0) newTarget = 1;
        if (newTarget > 0x00000000FFFF0000000000000000000000000000000000000000000000000000) {
            newTarget = 0x00000000FFFF0000000000000000000000000000000000000000000000000000;
        }
        return newTarget;
    }

    function _bytesLen(uint256 x) private pure returns (uint256 n) {
        if (x == 0) return 0;
        assembly {
            n := add(div(sub(0, and(sub(x, 1), add(not(sub(x, 1)), 1))), 255), 1)
        }
    }
}