// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/BitcoinHash.sol";
import "./BytesUtils.sol";

library BitcoinUtils {
    using BytesUtils for bytes;

    /// @notice Double SHA256 (sha256(sha256(data))) — типично для Bitcoin.
    /// @param data байты (memory или calldata).
    /// @return hash double-sha256 as bytes32
    function doubleSha256(bytes memory data) internal pure returns (bytes32) {
        return BitcoinHash.doubleSha256(data);
    }

    /// @notice Double SHA256 для calldata (обёртка)
    function doubleSha256Calldata(bytes calldata data) internal pure returns (bytes32) {
        // в solidity нет sha256(calldata) напрямую; нужно копировать в memory — но для компактности используем abi.encodePacked
        return BitcoinHash.doubleSha256(abi.encodePacked(data));
    }

    /// @notice Переворачивает порядок байт 32-байтового слова (big-endian <-> little-endian)
    function flipBytes32(bytes32 x) internal pure returns (bytes32) {
        return BytesUtils.reverse32(x);
    }

    /// @notice Вычисляет blockHash из 80-байтного заголовка (calldata)
    /// @dev Эквивалент doubleSha256(headerRaw)
    function computeBlockHashFromRaw(bytes calldata headerRaw) internal pure returns (bytes32) {
        // sha256(sha256(headerRaw))
        return BitcoinHash.doubleSha256(abi.encodePacked(headerRaw));
    }

    /// @notice Преобразует legacy serialized tx (bytes memory) в txid = doubleSha256(legacy)
    function txidFromLegacy(bytes memory legacy) internal pure returns (bytes32) {
        return BitcoinHash.doubleSha256(legacy);
    }

    /// @notice Извлекает значение и scriptPubKey из выхода транзакции (vout) по индексу
    /// @param raw Сырые данные транзакции (calldata)
    /// @param index Индекс выхода (vout)
    /// @return value Значение выхода в сатоши (uint64)
    /// @return scriptPubKey scriptPubKey выхода
    function _extractVout(bytes calldata raw, uint32 index)
        internal
        pure
        returns (uint64 value, bytes memory scriptPubKey)
    {
        if (raw.length < 10) revert("Invalid tx");
        uint256 offset = 0;

        offset += 4; // Пропускаем version
        bool hasWitness = false;
        if (offset + 2 <= raw.length && raw[offset] == 0x00 && raw[offset+1] == 0x01) {
            hasWitness = true;
            offset += 2; // Пропускаем witness marker
        }

        // Пропускаем vin
        (uint256 vinCount, uint256 sz) = _readVarInt(raw, offset);
        offset += sz;
        for (uint i = 0; i < vinCount; ++i) {
            offset += 36; // txid (32) + vout (4)
            (uint256 sl, uint256 sls) = _readVarInt(raw, offset);
            offset += sls + sl; // scriptSig + его длина
            offset += 4; // sequence
        }

        // Читаем vout
        (uint256 voutCount, uint256 vsz) = _readVarInt(raw, offset);
        offset += vsz;
        if (index >= voutCount) revert("vout OOB");

        for (uint32 i = 0; i < voutCount; ++i) {
            // Читаем значение выхода (8 байт)
            uint64 val = uint64(uint8(raw[offset])) |
                         (uint64(uint8(raw[offset+1])) << 8) |
                         (uint64(uint8(raw[offset+2])) << 16) |
                         (uint64(uint8(raw[offset+3])) << 24) |
                         (uint64(uint8(raw[offset+4])) << 32) |
                         (uint64(uint8(raw[offset+5])) << 40) |
                         (uint64(uint8(raw[offset+6])) << 48) |
                         (uint64(uint8(raw[offset+7])) << 56);
            offset += 8;

            // Читаем длину scriptPubKey
            (uint256 pkLen, uint256 pks) = _readVarInt(raw, offset);
            offset += pks;

            if (i == index) {
                bytes memory spk = raw[offset:offset+pkLen];
                return (val, spk);
            }
            offset += pkLen;
        }

        if (hasWitness) {
            for (uint256 i = 0; i < vinCount; ++i) {
                (uint256 wc, uint256 wcs) = _readVarInt(raw, offset);
                offset += wcs;
                for (uint256 j = 0; j < wc; ++j) {
                    (uint256 wl, uint256 wls) = _readVarInt(raw, offset);
                    offset += wls + wl;
                }
            }
        }

        revert("output not found");
    }

    /// @notice Читает VarInt из байтов транзакции
    /// @param raw Сырые данные транзакции (calldata)
    /// @param offset Смещение в байтах
    /// @return value Значение VarInt
    /// @return size Размер VarInt в байтах
    function _readVarInt(bytes calldata raw, uint256 offset) internal pure returns (uint256 value, uint256 size) {
        if (offset >= raw.length) revert("Invalid VarInt");
        uint8 fb = uint8(raw[offset]);
        if (fb < 0xFD) return (fb, 1);
        if (fb == 0xFD) {
            if (offset + 3 > raw.length) revert("Invalid VarInt");
            uint16 v = uint16(uint8(raw[offset+1])) | (uint16(uint8(raw[offset+2])) << 8);
            return (v, 3);
        }
        if (fb == 0xFE) {
            if (offset + 5 > raw.length) revert("Invalid VarInt");
            uint32 v = uint32(uint8(raw[offset+1])) |
                       (uint32(uint8(raw[offset+2])) << 8) |
                       (uint32(uint8(raw[offset+3])) << 16) |
                       (uint32(uint8(raw[offset+4])) << 24);
            return (v, 5);
        }
        if (offset + 9 > raw.length) revert("Invalid VarInt");
        uint256 vv;
        unchecked {
            for (uint i = 0; i < 8; ++i) {
                vv |= uint256(uint8(raw[offset + 1 + i])) << (8 * i);
            }
        }
        return (vv, 9);
    }
}
