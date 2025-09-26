// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hashes} from "./Hashes.sol";
import {Schnorr} from "./Schnorr.sol";
import {Secp256k1} from "./Secp256k1.sol";
import {Memory} from "./Memory.sol";
import {Secp256k1Arithmetic} from "./Secp256k1Arithmetic.sol";
import {AffinePoint} from "./AffinePoint.sol";
import {ModExp} from "./ModExp.sol";
import {Utils} from "./Utils.sol";

/**
 * @dev Library for verifying `FROST-secp256k1-KECCAK256` signatures.
 */
library FROST {
    uint256 internal constant KECCAK256_BLOCK_SIZE = 136;

    uint256 internal constant PUBLIC_KEY_Y_PARITY_SIZE = 1;
    uint256 internal constant PUBLIC_KEY_X_SIZE = 32;
    uint256 internal constant PUBLIC_KEY_SIZE = 33;

    uint256 internal constant MESSAGE_HASH_SIZE = 32;

    uint256 internal constant LEN_IN_BYTES_U16_SIZE = 2;
    uint256 internal constant ZERO_BYTE_SIZE = 1;

    uint256 internal constant DOMAIN_SIZE = 32;
    uint256 internal constant DOMAIN_PART1_SIZE = 29;
    uint256 internal constant DOMAIN_PART2_SIZE = 3;

    uint256 internal constant DOMAIN_LENGTH_SIZE = 1;

    uint256 internal constant CHALLENGE_SIZE = KECCAK256_BLOCK_SIZE
        + PUBLIC_KEY_SIZE
        + PUBLIC_KEY_SIZE
        + MESSAGE_HASH_SIZE
        + LEN_IN_BYTES_U16_SIZE
        + ZERO_BYTE_SIZE
        + DOMAIN_SIZE
        + DOMAIN_LENGTH_SIZE;

    uint256 internal constant INPUT_HASH_SIZE = 32;
    uint256 internal constant RESERVED_BYTE_SIZE = 1;

    uint256 internal constant OUTPUT_HASH_SIZE =
        INPUT_HASH_SIZE + RESERVED_BYTE_SIZE + DOMAIN_SIZE + DOMAIN_LENGTH_SIZE;

    // "\x00\x30" - len_in_bytes_u16
    // "\x00" - zero byte
    // "FROST-secp256k1-KECCAK256-v1c" - domain
    uint256 internal constant DOMAIN_SEPARATOR1 =
        0x00300046524F53542D736563703235366B312D4B454343414B3235362D763163;
    // "hal" - domain
    // "\x20" - domain length
    uint256 internal constant DOMAIN_SEPARATOR2 =
        0x68616C2000000000000000000000000000000000000000000000000000000000;

    uint256 internal constant F_2_192 = 0x0000000000000001000000000000000000000000000000000000000000000000;
    uint256 internal constant MASK_64  = 0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF;

    /**
     * @dev Checks if public key `(x, y)` is on curve.
     */
    function isValidPublicKey(uint256 publicKeyX, uint256 publicKeyY) internal pure returns (bool) {
        return Secp256k1.isOnCurve(publicKeyX, publicKeyY);
    }

    /**
     * @dev Computes challenge for `FROST-secp256k1-KECCAK256` signature.
     * @param publicKeyX Public key x.
     * @param publicKeyY Public key y.
     * @param signatureCommitmentX Signature commitment R x.
     * @param signatureCommitmentY Signature commitment R y.
     * @param messageHash Message hash.
     * @return memPtr Pointer to allocated memory, memory size is `FROST.CHALLENGE_SIZE`.
     * @return challenge Challenge.
     */
    function computeChallenge(
        uint256 publicKeyX,
        uint256 publicKeyY,
        uint256 signatureCommitmentX,
        uint256 signatureCommitmentY,
        bytes32 messageHash
    ) internal pure returns (uint256, uint256) {
        uint256 publicKeyYCompressed = Secp256k1.yCompressed(publicKeyY);
        uint256 signatureCommitmentYCompressed = Secp256k1.yCompressed(signatureCommitmentY);

        uint256 memPtr = Memory.allocate(CHALLENGE_SIZE);

        // Обнуляем первый KECCAK-блок (ровно 136 байт).
        // В твоём Memory.zeroize сигнатура: (dataStart, dataSizeInBytes).
        Memory.zeroize(memPtr, KECCAK256_BLOCK_SIZE);

        // Записываем R и P в память (байт префикса Y-паритета + X-координата)
        Memory.writeByte(memPtr, KECCAK256_BLOCK_SIZE, signatureCommitmentYCompressed);
        Memory.writeWord(memPtr, KECCAK256_BLOCK_SIZE + PUBLIC_KEY_Y_PARITY_SIZE, signatureCommitmentX);

        Memory.writeByte(memPtr, KECCAK256_BLOCK_SIZE + PUBLIC_KEY_SIZE, publicKeyYCompressed);
        Memory.writeWord(memPtr, KECCAK256_BLOCK_SIZE + PUBLIC_KEY_SIZE + PUBLIC_KEY_Y_PARITY_SIZE, publicKeyX);

        Memory.writeWord(
            memPtr,
            KECCAK256_BLOCK_SIZE + PUBLIC_KEY_SIZE + PUBLIC_KEY_SIZE,
            uint256(messageHash)
        );

        uint256 offset = KECCAK256_BLOCK_SIZE + PUBLIC_KEY_SIZE + PUBLIC_KEY_SIZE + MESSAGE_HASH_SIZE;
        Memory.writeWord(memPtr, offset, DOMAIN_SEPARATOR1);
        Memory.writeWord(
            memPtr,
            offset + LEN_IN_BYTES_U16_SIZE + ZERO_BYTE_SIZE + DOMAIN_PART1_SIZE,
            DOMAIN_SEPARATOR2
        );

        // b0 = keccak(memPtr, CHALLENGE_SIZE)
        uint256 b0 = Hashes.efficientKeccak256(memPtr, CHALLENGE_SIZE);

        uint256 offset1 = KECCAK256_BLOCK_SIZE + PUBLIC_KEY_SIZE + PUBLIC_KEY_SIZE + 2;
        uint256 offset2 = KECCAK256_BLOCK_SIZE + PUBLIC_KEY_SIZE + PUBLIC_KEY_SIZE + MESSAGE_HASH_SIZE + LEN_IN_BYTES_U16_SIZE;

        // Записываем b0 и счётчик=1
        Memory.writeWord(memPtr, offset1, b0);
        Memory.writeByte(memPtr, offset2, 1);

        // bVals = keccak(memPtr + offset1, OUTPUT_HASH_SIZE)
        uint256 bVals = Hashes.efficientKeccak256(memPtr + offset1, OUTPUT_HASH_SIZE);
        uint256 tmp = b0 ^ bVals;

        // Пишем tmp и счётчик=2
        Memory.writeWord(memPtr, offset1, tmp);
        Memory.writeByte(memPtr, offset2, 2);

        uint256 bVals2 = Hashes.efficientKeccak256(memPtr + offset1, OUTPUT_HASH_SIZE);

        uint256 d0 = bVals >> 64;
        uint256 d1 = ((bVals & MASK_64) << 128) | (bVals2 >> 128);

        // challenge = (d0 * 2^192 + d1) mod n
        return (memPtr, addmod(mulmod(d0, F_2_192, Secp256k1.N), d1, Secp256k1.N));
    }

    /**
     * @dev Верификация `FROST-secp256k1-KECCAK256`.
     * Делегирует в проектную реализацию Schnorr.verify(pubX, pubY, rx, ry, s, msgHash),
     * т.к. в твоём Schnorr.sol нет `verifySignature`, а есть `verify(...)`.
     *
     * @param publicKeyX X публичного ключа.
     * @param publicKeyY Y публичного ключа.
     * @param signatureCommitmentX R.x.
     * @param signatureCommitmentY R.y (может игнорироваться в x-only проверке).
     * @param signatureZ           s (или z).
     * @param messageHash          хэш сообщения (32 байта).
     */
    function verifySignature(
        uint256 publicKeyX,
        uint256 publicKeyY,
        uint256 signatureCommitmentX,
        uint256 signatureCommitmentY,
        uint256 signatureZ,
        bytes32 messageHash
    ) internal view returns (bool) {
        // Валидация ключа на кривой
        if (!isValidPublicKey(publicKeyX, publicKeyY)) return false;

        // Диапазоны
        if (signatureCommitmentX >= Secp256k1.P) return false;
        if (signatureZ == 0 || signatureZ >= Secp256k1.N) return false;

        // Делегируем в твою реализацию Schnorr.verify(...)
        // Обрати внимание: Schnorr.verify игнорирует pubkeyY и ry, и делает x-only проверку.
        return Schnorr.verify(
            publicKeyX,
            publicKeyY,
            signatureCommitmentX,
            signatureCommitmentY,
            signatureZ,
            messageHash
        );
    }
}
