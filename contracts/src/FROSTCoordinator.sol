// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title FROSTCoordinator
 * @notice Ончейн-координатор FROST-сессий с поддержкой DKG и подписи:
 *  - Совместимость с MiningPoolDAO (createSessionWithId / finalizeSession(id,sig,msgHash))
 *  - Привязка messageHash позже (bind или в finalize)
 *  - Учёт отказов участников (refuse) для слешинга в DAO
 *  - Гибкая проверка порога (enforceSharesCheck true/false)
 *  - Поддержка внешнего верификатора (override на сессию)
 *  - Метаданные purpose/origin (тип операции и источник)
 *  - События-алиасы (SessionOpened) для старых агентов
 *  - Мультичейн поддержка (Schnorr для BTC/BCH/LTC, ECDSA для DOGE)
 *  - DKG с ончейн-хранением зашифрованных secret shares
 *
 * Валидация подписи делегирована IFROSTVerifier (BIP340 для Schnorr, ECDSA для DOGE).
 * Оффчейн агенты слушают события и исполняют MPC-протокол.
 */
