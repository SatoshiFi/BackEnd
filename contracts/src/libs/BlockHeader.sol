// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./BytesUtils.sol";
import "../core/BitcoinHash.sol";

/// @notice Структура, представляющая разобранный 80-байтный Bitcoin block header
struct BlockHeaderData {
    uint32 version;
    bytes32 prevBlockHash; // wire format (32 bytes)
    bytes32 merkleRoot;    // wire format (32 bytes)
    uint32 time;
    uint32 bits;
    uint32 nonce;
}

library BlockHeader {
    using BytesUtils for bytes;

    error InvalidHeaderLength();

    /// @notice Парсит 80-байтный raw header (wire format) и возвращает структуру и blockHash (sha256d)
    /// @param raw 80-byte block header (calldata)
    /// @return header разобранный HeaderData
    /// @return blockHash double-sha256(header) — тот самый block hash (как в wire)
    function parseHeader(bytes calldata raw) internal pure returns (BlockHeaderData memory header, bytes32 blockHash) {
        if (raw.length != 80) revert InvalidHeaderLength();

        header.version = raw.toUint32LE(0);

        // prevBlockHash (32 bytes) at offset 4
        bytes32 prev;
        bytes32 merkle;
        assembly {
            // calldataload loads 32 bytes starting at position (raw.offset + 4)
            prev := calldataload(add(raw.offset, 4))
            merkle := calldataload(add(raw.offset, 36))
        }
        header.prevBlockHash = prev;
        header.merkleRoot = merkle;

        header.time = raw.toUint32LE(68);
        header.bits = raw.toUint32LE(72);
        header.nonce = raw.toUint32LE(76);

        // blockHash = doubleSha256(raw)
        blockHash = BitcoinHash.doubleSha256(raw);
    }
}
