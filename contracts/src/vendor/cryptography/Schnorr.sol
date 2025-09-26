// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * BIP-340 (Schnorr over secp256k1) verification for Taproot (x-only pubkeys).
 * Проверка равенства: s*G = R + e*P, где
 *   e = int(tagged_hash("BIP0340/challenge", r_x || p_x || m)) mod n
 * Требуется, чтобы и P, и восстановленная R' имели чётный y (BIP-340).
 *
 * Замечания по реализации:
 * - Используются проектные арифметические примитивы из Secp256k1Arithmetic.
 * - Вызовы mulProjectivePoint/addProjectivePoint/convertProjectivePointToAffinePoint
 *   соответствуют сигнатурам в репозитории:
 *      mulProjectivePoint(x, y, scalar, z)
 *      addProjectivePoint(x1, y1, z1, x2, y2, z2)
 *      convertProjectivePointToAffinePoint(x, y, z, zInv)
 * - Для аффинных точек используем z = 1.
 * - В convertProjectivePointToAffinePoint передаём zInv = 0, если внутри
 *   библиотека сама считает обратный (как это сделано в репозитории).
 */

import {Secp256k1} from "./Secp256k1.sol";
import {Secp256k1Arithmetic} from "./Secp256k1Arithmetic.sol";
import {Memory} from "./Memory.sol";

library Schnorr {
    /// @dev BIP0340 tagged hashing: sha256(tag || tag || msg)
    /// tag = sha256("BIP0340/challenge")
    function _taggedChallenge(
        bytes32 rx32,
        uint256 px,
        bytes32 m32
    ) private pure returns (uint256 e) {
        bytes32 tag = sha256("BIP0340/challenge");
        bytes32 h = sha256(abi.encodePacked(tag, tag, rx32, bytes32(px), m32));
        e = uint256(h) % Secp256k1.N;
    }

    /**
     * @notice Верификация подписи BIP-340 для x-only публичного ключа.
     * @param pubkeyX x(P) — x-координата публичного ключа (P с чётным y).
     * @param rx      x(R) — x-координата коммита R (должен быть чётный y).
     * @param s       s-скаляр из подписи.
     * @param msg32   32-байтовое сообщение (хэш).
     */
    function verifyXonly(
        uint256 pubkeyX,
        uint256 rx,
        uint256 s,
        bytes32 msg32
    ) internal view returns (bool) {
        // Базовые диапазоны
        if (pubkeyX == 0 || pubkeyX >= Secp256k1.P) return false;
        if (rx == 0 || rx >= Secp256k1.P) return false;
        if (s == 0 || s >= Secp256k1.N) return false;

        // Поднимаем P из x-only, требуя чётный y (BIP-340).
        // В проекте есть calculateY(x, yIsOdd). Нам нужен yIsOdd=false.
        uint256 py = Secp256k1.calculateY(pubkeyX, /*yIsOdd=*/false);
        if (!Secp256k1.isOnCurve(pubkeyX, py)) return false;

        // e = H(rx || px || m) mod n
        uint256 e = _taggedChallenge(bytes32(rx), pubkeyX, msg32);

        // Считаем R' = s·G − e·P = sG + (−eP)
        // 1) sG (аффинная G => z = 1)
        (uint256 sGx, uint256 sGy, uint256 sGz) =
            Secp256k1Arithmetic.mulProjectivePoint(Secp256k1.GX, Secp256k1.GY, s, 1);

        // 2) eP (аффинная P => z = 1)
        (uint256 ePx, uint256 ePy, uint256 ePz) =
            Secp256k1Arithmetic.mulProjectivePoint(pubkeyX, py, e, 1);

        // 3) -eP: инвертируем Y по модулю поля для вычитания
        ePy = (ePy == 0) ? 0 : Secp256k1.P - ePy;

        // 4) R' = sG + (-eP)
        (uint256 rxp, uint256 ryp, uint256 rzp) =
            Secp256k1Arithmetic.addProjectivePoint(sGx, sGy, sGz, ePx, ePy, ePz);

        // Бесконечность? (в проекте аффинное преобразование вернёт x=0 при z=0)
        if (rzp == 0) return false;

        // В аффинные координаты. Внутри библиотека сама посчитает zInv, если 0.
        (uint256 rxa, uint256 rya) =
            Secp256k1Arithmetic.convertProjectivePointToAffinePoint(rxp, ryp, rzp, 0);

        // Проверки: допустимый x, совпадение x-координаты, чётный y.
        if (rxa == 0 || rxa >= Secp256k1.P) return false;
        if (rxa != rx) return false;
        if ((rya & 1) != 0) return false; // Требуем чётный y у R'

        return true;
    }

    /**
     * Совместимость с прежним интерфейсом (игнорируем y-компоненты).
     * Параметры pubkeyY/ry оставлены для ABI-совместимости, но не используются.
     */
    function verify(
        uint256 pubkeyX,
        uint256 /*pubkeyY*/,
        uint256 rx,
        uint256 /*ry*/,
        uint256 s,
        bytes32 msgHash
    ) internal view returns (bool) {
        return verifyXonly(pubkeyX, rx, s, msgHash);
    }
    function isValidPublicKey(uint256 pubX, uint256 pubY) internal pure returns (bool) {
    return Secp256k1.isOnCurve(pubX, pubY);
}
}
