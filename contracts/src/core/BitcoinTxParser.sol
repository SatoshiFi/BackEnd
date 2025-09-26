// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library BitcoinTxParser {
    error InvalidVarInt();
    error InvalidTxLength();

    struct VarInt { uint256 value; uint256 size; }

    function _readVarInt(bytes calldata raw, uint256 offset) internal pure returns (VarInt memory varInt) {
        if (offset >= raw.length) revert InvalidVarInt();
        uint8 fb = uint8(raw[offset]);
        if (fb < 0xFD) return VarInt(fb, 1);
        if (fb == 0xFD) {
            if (offset + 3 > raw.length) revert InvalidVarInt();
            uint16 val = uint16(uint8(raw[offset+1])) | (uint16(uint8(raw[offset+2])) << 8);
            return VarInt(val, 3);
        }
        if (fb == 0xFE) {
            if (offset + 5 > raw.length) revert InvalidVarInt();
            uint32 val = uint32(uint8(raw[offset+1])) |
                        (uint32(uint8(raw[offset+2])) << 8) |
                        (uint32(uint8(raw[offset+3])) << 16) |
                        (uint32(uint8(raw[offset+4])) << 24);
            return VarInt(val, 5);
        }
        if (offset + 9 > raw.length) revert InvalidVarInt();
        uint256 val;
        unchecked {
            for (uint i = 0; i < 8; ++i) {
                val |= uint256(uint8(raw[offset + 1 + i])) << (8 * i);
            }
        }
        return VarInt(val, 9);
    }

    function stripWitness(bytes calldata raw) internal pure returns (bytes memory out) {
        if (raw.length < 10) revert InvalidTxLength();
        uint256 offset = 0;
        out = bytes.concat(raw[0:4]);
        offset += 4;

        bool hasWitness = false;
        if (offset + 2 <= raw.length && raw[offset] == 0x00 && raw[offset+1] == 0x01) {
            hasWitness = true;
            offset += 2;
        }

        VarInt memory vin = _readVarInt(raw, offset);
        out = bytes.concat(out, raw[offset:offset+vin.size]);
        offset += vin.size;

        for (uint i = 0; i < vin.value; ++i) {
            out = bytes.concat(out, raw[offset:offset+36]);
            offset += 36;
            VarInt memory sl = _readVarInt(raw, offset);
            out = bytes.concat(out, raw[offset:offset+sl.size]);
            offset += sl.size;
            out = bytes.concat(out, raw[offset:offset+sl.value]);
            offset += sl.value;
            out = bytes.concat(out, raw[offset:offset+4]);
            offset += 4;
        }

        VarInt memory voutCount = _readVarInt(raw, offset);
        out = bytes.concat(out, raw[offset:offset+voutCount.size]);
        offset += voutCount.size;

        for (uint i = 0; i < voutCount.value; ++i) {
            out = bytes.concat(out, raw[offset:offset+8]);
            offset += 8;
            VarInt memory pk = _readVarInt(raw, offset);
            out = bytes.concat(out, raw[offset:offset+pk.size]);
            offset += pk.size;
            out = bytes.concat(out, raw[offset:offset+pk.value]);
            offset += pk.value;
        }

        if (hasWitness) {
            unchecked {
                for (uint i = 0; i < vin.value; ++i) {
                    VarInt memory wc = _readVarInt(raw, offset);
                    offset += wc.size;
                    for (uint j = 0; j < wc.value; ++j) {
                        VarInt memory item = _readVarInt(raw, offset);
                        offset += item.size + item.value;
                    }
                }
            }
        }

        out = bytes.concat(out, raw[offset:offset+4]);
        offset += 4;

        if (offset != raw.length) revert InvalidTxLength();
    }

    function parseFirstInput(bytes calldata raw) internal pure returns (bytes32 prevTxIdLE, uint32 vout) {
        require(raw.length >= 41, "InvalidTxLength");
        uint256 offset = 4;
        if (offset + 2 <= raw.length && raw[offset] == 0x00 && raw[offset+1] == 0x01) {
            offset += 2;
        }
        VarInt memory varInt = _readVarInt(raw, offset);
        require(varInt.value >= 1, "no inputs");
        offset += varInt.size;

        assembly {
            prevTxIdLE := calldataload(add(raw.offset, offset))
        }
        offset += 32;
        vout = uint32(uint8(raw[offset])) |
               (uint32(uint8(raw[offset+1])) << 8) |
               (uint32(uint8(raw[offset+2])) << 16) |
               (uint32(uint8(raw[offset+3])) << 24);
    }

    function doubleSha256(bytes memory data) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(data)));
    }

    function flipBytes32(bytes32 x) internal pure returns (bytes32) {
        bytes32 y;
        unchecked {
            for (uint i = 0; i < 32; ++i) {
                y |= bytes32(uint256(uint8(x[i])) << ((31 - i) * 8));
            }
        }
        return y;
    }
}