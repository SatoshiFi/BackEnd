// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library BitcoinHash {
    function doubleSha256(bytes memory data) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(data)));
    }

    function flip32(bytes32 x) internal pure returns (bytes32 y) {
        for (uint i = 0; i < 32; ++i) {
            y |= bytes32(uint256(uint8(x[i])) << ((31 - i) * 8));
        }
    }
}
