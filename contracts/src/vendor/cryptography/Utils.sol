// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Utils
 * @dev Разные вспомогательные утилиты
 */
library Utils {
    function isZero(uint256 x) internal pure returns (bool) {
        return x == 0;
    }

    function isOdd(uint256 x) internal pure returns (bool) {
        return x & 1 == 1;
    }

    function toUint(bytes32 b) internal pure returns (uint256) {
        return uint256(b);
    }

    function toBytes32(uint256 x) internal pure returns (bytes32) {
        return bytes32(x);
    }

    /// @notice Читает 32-байтное big-endian слово из bytes, начиная с offset.
    /// @dev Ожидается, что в массиве лежит ровно big-endian представление.
    function bytesToUint(bytes memory b, uint256 offset) internal pure returns (uint256 r) {
        require(b.length >= offset + 32, "bytesToUint OOB");
        assembly {
            r := mload(add(add(b, 0x20), offset))
        }
    }

    /// @notice Конвертирует uint256 в 32-байтный big-endian bytes.
    function uintToBytes(uint256 x) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32(x));
    }
}
