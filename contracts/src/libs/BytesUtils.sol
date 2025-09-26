// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Утилиты для работы с bytes и calldata (LE/BE чтение, slice, reverse)
library BytesUtils {
    /// @notice Читает 4 байта (little-endian) из calldata bytes и возвращает uint32
    function toUint32LE(bytes calldata data, uint256 start) internal pure returns (uint32 v) {
        unchecked {
            v =
                (uint32(uint8(data[start + 0]))      ) |
                (uint32(uint8(data[start + 1])) <<  8) |
                (uint32(uint8(data[start + 2])) << 16) |
                (uint32(uint8(data[start + 3])) << 24);
        }
    }

    /// @notice Читает 8 байт (little-endian) из calldata bytes и возвращает uint64
    function toUint64LE(bytes calldata data, uint256 start) internal pure returns (uint64 v) {
        unchecked {
            v =
                (uint64(uint8(data[start + 0]))      ) |
                (uint64(uint8(data[start + 1])) <<  8) |
                (uint64(uint8(data[start + 2])) << 16) |
                (uint64(uint8(data[start + 3])) << 24) |
                (uint64(uint8(data[start + 4])) << 32) |
                (uint64(uint8(data[start + 5])) << 40) |
                (uint64(uint8(data[start + 6])) << 48) |
                (uint64(uint8(data[start + 7])) << 56);
        }
    }

    /// @notice Возвращает 32-байтовое значение из memory bytes по смещению (проверка OOB)
    function slice32(bytes memory bs, uint256 start) internal pure returns (bytes32 out) {
        require(bs.length >= start + 32, "BytesUtils: slice OOB");
        assembly {
            out := mload(add(add(bs, 0x20), start))
        }
    }

    /// @notice Загружает 32 байта из calldata (на offset) и возвращает bytes32
    function readBytes32Calldata(bytes calldata data, uint256 start) internal pure returns (bytes32 out) {
        require(data.length >= start + 32, "BytesUtils: read OOB");
        assembly {
            out := calldataload(add(data.offset, start))
        }
    }

    /// @notice Переворачивает порядок байт в bytes32 (endianness flip)
    function reverse32(bytes32 input) internal pure returns (bytes32 v) {
        bytes32 x = input;
        bytes32 y;
        for (uint256 i = 0; i < 32; ++i) {
            y |= (x & bytes32(uint256(0xFF) << (i * 8))) >> (i * 8) << ((31 - i) * 8);
        }
        return y;
    }

    /// @notice Конвертирует первые N байт calldata в bytes memory
    function sliceCalldata(bytes calldata data, uint256 start, uint256 len) internal pure returns (bytes memory out) {
        require(data.length >= start + len, "BytesUtils: sliceCalldata OOB");
        out = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            out[i] = data[start + i];
        }
    }
}
