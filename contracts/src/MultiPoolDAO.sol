// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MultiPoolDAO
 * @notice Агрегатор наград из пулов + выпуск S-токенов (SBTC/SDOGE/SBCH/SLTC) и redeem с блокировкой.
 *         Поддерживает строгий режим mint: caller предоставляет SPV-пруф (blockHeaderRaw, txRaw, vout, merkleProof, directions)
 *         и конкретный poolId; контракт сам регистрирует UTXO (если не зарегистрирован), резервирует часть UTXO и минтит S-token.
 *
 * Важное:
 *  - mintSTokenWithProof(...) - строгий режим, требует SPV-пруфа и проверяет совпадение payoutScript пула.
 *  - mintSToken(networkId, amount, recipient) - legacy режим, может использоваться только пулом (onlyPool) и черпает из уже зарегистрированного backing.
 */
