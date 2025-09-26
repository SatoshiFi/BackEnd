// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title BitcoinTxSerializer
 * @notice Утилиты для сборки raw Bitcoin-транзакций (SegWit/legacy) ончейн.
 *
 * Поддержано:
 *  - varint (Bitcoin)
 *  - сериализация input/output
 *  - witness-массивы и segwit-маркер/флаг
 *  - конструкторы scriptPubKey:
 *      * Taproot (P2TR, v1):  OP_1 (0x51) PUSH32 (0x20) <32-byte x-only>
 *      * P2WPKH (v0):         0x00 PUSH20 (0x14) <20-byte hash160>
 *      * P2WSH  (v0):         0x00 PUSH32 (0x20) <32-byte sha256(script)>
 *
 * Добавлены хелперы, которые используются DAO:
 *  - getScriptPubKey (Taproot/P2WPKH/P2WSH)
 *  - isValidP2TR
 *  - getStakeInput (дефолтный input со стандартной последовательностью)
 *  - serializeTx (полная сборка raw tx, включая segwit)
 *
 * Важно: txid в prevout сериализуется в маленьком индейце (LE). Если вы храните txid в BE,
 * используйте reverseBytes32 при формировании input.
 */
library BitcoinTxSerializer {
    // -------------------------
    // Types
    // -------------------------
    struct TxInput {
        bytes32 prevTxIdBE;   // BE-представление txid, как обычно приходит из RPC/hex
        uint32  vout;         // индекс выхода
        bytes   scriptSig;    // чаще всего пусто для segwit
        uint32  sequence;     // по умолчанию 0xFFFFFFFD (RBF+nLockTime)
        bytes[] witness;      // witness stack (если segwit)
    }

    struct TxOutput {
        uint64 value;         // сатоши
        bytes  scriptPubKey;  // готовый скрипт
    }

    struct Tx {
        uint32   version;     // как правило 2
        bool     segwit;      // true -> пишем marker/flag и witness после outputs
        TxInput[] vin;
        TxOutput[] vout;
        uint32   locktime;    // 0 либо высота/время
    }

    enum SpkKind { P2TR, P2WPKH, P2WSH }

    // -------------------------
    // Constants
    // -------------------------
    uint32 internal constant SEQUENCE_FINAL      = 0xFFFFFFFF;
    uint32 internal constant SEQUENCE_DEFAULT    = 0xFFFFFFFD; // RBF + nLockTime enabled
    bytes1 internal constant OP_0  = 0x00;
    bytes1 internal constant OP_1  = 0x51;

    // -------------------------
    // Public helpers expected by DAO
    // -------------------------

    /**
     * @notice Построить scriptPubKey по типу (Taproot/P2WPKH/P2WSH).
     * @param kind   вид выхода
     * @param data   для P2TR — 32b x-only pubkey; для P2WPKH — 20b hash160; для P2WSH — 32b sha256(script)
     */
    function getScriptPubKey(SpkKind kind, bytes memory data) internal pure returns (bytes memory) {
        if (kind == SpkKind.P2TR) {
            require(data.length == 32, "P2TR: x-only must be 32b");
            // v1 witness program: OP_1 0x20 <32b>
            return abi.encodePacked(OP_1, bytes1(0x20), data);
        } else if (kind == SpkKind.P2WPKH) {
            require(data.length == 20, "P2WPKH: hash160 must be 20b");
            // v0 witness program: 0x00 0x14 <20b>
            return abi.encodePacked(OP_0, bytes1(0x14), data);
        } else {
            // P2WSH
            require(data.length == 32, "P2WSH: sha256(script) must be 32b");
            // v0 witness program: 0x00 0x20 <32b>
            return abi.encodePacked(OP_0, bytes1(0x20), data);
        }
    }

    /**
     * @notice Быстрая проверка формата Taproot-ключа (x-only, 32 байта).
     */
    function isValidP2TR(bytes memory xonly) internal pure returns (bool) {
        return xonly.length == 32;
    }

    /**
     * @notice Сконструировать типичный input для стейка/выплаты:
     *         пустой scriptSig, sequence = 0xFFFFFFFD (RBF+LockTime), без witness (заполните отдельно при необходимости).
     * @param prevTxIdBE txid в BE (как в большинстве RPC)
     * @param vout       индекс выхода
     */
    function getStakeInput(bytes32 prevTxIdBE, uint32 vout) internal pure returns (TxInput memory ti) {
        ti.prevTxIdBE = prevTxIdBE;
        ti.vout       = vout;
        ti.scriptSig  = hex"";
        ti.sequence   = SEQUENCE_DEFAULT;
        // witness оставляем пустым по умолчанию (для Taproot/SegWit заполните отдельно в оффчейне)
    }

    /**
     * @notice Полная сериализация транзакции (legacy/SegWit). Для SegWit: marker=0x00, flag=0x01.
     */
    function serializeTx(Tx memory t) internal pure returns (bytes memory) {
        bytes memory header = abi.encodePacked(
            _u32LE(t.version),
            t.segwit ? bytes1(0x00) : bytes1(0x00), // marker (для legacy тоже положим 0x00, но ниже flag не пишем)
            t.segwit ? bytes1(0x01) : bytes1(0x00)  // flag
        );

        // Для legacy нужно НЕ писать marker/flag вообще.
        // Поэтому, если legacy, перезапишем header на версию без marker/flag.
        if (!t.segwit) {
            header = abi.encodePacked(_u32LE(t.version));
        }

        bytes memory vin = _serializeInputs(t.vin);
        bytes memory vout = _serializeOutputs(t.vout);

        if (!t.segwit) {
            // legacy: version | vin | vout | locktime
            return abi.encodePacked(
                header,
                vin,
                vout,
                _u32LE(t.locktime)
            );
        } else {
            // segwit: version | 0x00 0x01 | vin | vout | witness | locktime
            bytes memory wit = _serializeWitnesses(t.vin);
            return abi.encodePacked(
                header,
                vin,
                vout,
                wit,
                _u32LE(t.locktime)
            );
        }
    }

    // -------------------------
    // Core serialization
    // -------------------------

    function _serializeInputs(TxInput[] memory ins) private pure returns (bytes memory) {
        bytes memory out;
        out = bytes.concat(out, _encodeVarInt(ins.length));

        for (uint256 i = 0; i < ins.length; i++) {
            // prevout hash little-endian:
            bytes32 prevLE = reverseBytes32(ins[i].prevTxIdBE);

            out = bytes.concat(
                out,
                bytes32ToBytes(prevLE),        // 32b hash (LE)
                _u32LE(ins[i].vout),           // 4b index
                _encodeVarInt(ins[i].scriptSig.length),
                ins[i].scriptSig,
                _u32LE(ins[i].sequence)        // 4b sequence
            );
        }
        return out;
    }

    function _serializeOutputs(TxOutput[] memory outs) private pure returns (bytes memory) {
        bytes memory out;
        out = bytes.concat(out, _encodeVarInt(outs.length));

        for (uint256 i = 0; i < outs.length; i++) {
            out = bytes.concat(
                out,
                _u64LE(outs[i].value),                 // 8b value (sat)
                _encodeVarInt(outs[i].scriptPubKey.length),
                outs[i].scriptPubKey
            );
        }
        return out;
    }

    function _serializeWitnesses(TxInput[] memory ins) private pure returns (bytes memory) {
        // Для каждого input пишется witness stack: <stack_count> <item_len+item>...
        bytes memory out;
        for (uint256 i = 0; i < ins.length; i++) {
            bytes[] memory stack = ins[i].witness;
            out = bytes.concat(out, _encodeVarInt(stack.length));
            for (uint256 j = 0; j < stack.length; j++) {
                out = bytes.concat(out, _encodeVarInt(stack[j].length), stack[j]);
            }
        }
        return out;
    }

    // -------------------------
    // VarInt (Bitcoin)
    // -------------------------
    function _encodeVarInt(uint256 v) internal pure returns (bytes memory) {
        if (v < 0xFD) {
            return abi.encodePacked(uint8(v));
        } else if (v <= 0xFFFF) {
            return abi.encodePacked(uint8(0xFD), _u16LE(uint16(v)));
        } else if (v <= 0xFFFFFFFF) {
            return abi.encodePacked(uint8(0xFE), _u32LE(uint32(v)));
        } else {
            return abi.encodePacked(uint8(0xFF), _u64LE(uint64(v)));
        }
    }

    // -------------------------
    // Little-endian helpers
    // -------------------------
    function _u16LE(uint16 v) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes2((v >> 8) | (v << 8)));
    }

    function _u32LE(uint32 v) internal pure returns (bytes memory) {
        // вручную составляя байты (gas-дружелюбно)
        return abi.encodePacked(
            bytes1(uint8(v)),
            bytes1(uint8(v >> 8)),
            bytes1(uint8(v >> 16)),
            bytes1(uint8(v >> 24))
        );
    }

    function _u64LE(uint64 v) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes1(uint8(v)),
            bytes1(uint8(v >> 8)),
            bytes1(uint8(v >> 16)),
            bytes1(uint8(v >> 24)),
            bytes1(uint8(v >> 32)),
            bytes1(uint8(v >> 40)),
            bytes1(uint8(v >> 48)),
            bytes1(uint8(v >> 56))
        );
    }

    // -------------------------
    // Bytes helpers
    // -------------------------
    function reverseBytes32(bytes32 x) internal pure returns (bytes32) {
        // реверс 32 байт (BE <-> LE)
        bytes32 v = x;
        v =
            ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
            ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);
        v =
            ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
            ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);
        v =
            ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32) |
            ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);
        v =
            ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64) |
            ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);
        v = (v >> 128) | (v << 128);
        return v;
    }

    function bytes32ToBytes(bytes32 b) internal pure returns (bytes memory) {
        return abi.encodePacked(b);
    }

    // -------------------------
    // Convenience constructors for outputs
    // -------------------------
    function buildP2TROutput(uint64 value, bytes32 xonlyPubkey) internal pure returns (TxOutput memory o) {
        o.value = value;
        o.scriptPubKey = getScriptPubKey(SpkKind.P2TR, abi.encodePacked(xonlyPubkey));
    }

    function buildP2WPKHOutput(uint64 value, bytes20 hash160) internal pure returns (TxOutput memory o) {
        o.value = value;
        o.scriptPubKey = getScriptPubKey(SpkKind.P2WPKH, abi.encodePacked(hash160));
    }

    function buildP2WSHOutput(uint64 value, bytes32 scriptHash) internal pure returns (TxOutput memory o) {
        o.value = value;
        o.scriptPubKey = getScriptPubKey(SpkKind.P2WSH, abi.encodePacked(scriptHash));
    }
}
