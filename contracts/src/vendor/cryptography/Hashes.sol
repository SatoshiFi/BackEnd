// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Hashes {
    function efficientKeccak256(uint256 a, uint256 b) internal pure returns (uint256 value) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
