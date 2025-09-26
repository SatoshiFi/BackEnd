// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IFROSTCoordinator
 * @notice Интерфейс для FROSTCoordinator, поддерживающий FROST-сессии и DKG:
 *  - Создание сессий для подписи и DKG
 *  - Управление nonce commitments, signature shares и DKG shares
 *  - Финализация сессий подписи и DKG
 *  - Отказ от подписи с учётом для слешинга
 *  - Получение данных о сессиях и хранителях
 */
interface IFROSTCoordinator {
    /**
     * @notice Создаёт сессию для подписи (совместимость с MiningPoolDAO)
     * @param sessionId Идентификатор сессии (0 для автоназначения)
     * @param groupPubkey Публичный ключ группы (32 байта для Schnorr, 64 байта для ECDSA)
     * @param participants Список адресов участников
     * @param threshold Порог подписи (t из t-of-n)
     * @param deadline Unix timestamp дедлайна
     */
    function createSession(
        uint256 sessionId,
        bytes calldata groupPubkey,
        address[] calldata participants,
        uint256 threshold,
        uint256 deadline
    ) external;

    /**
     * @notice Создаёт сессию с привязкой сообщения (современный API)
     * @param sessionId Идентификатор сессии (0 для автоназначения)
     * @param groupPubkey Публичный ключ группы
     * @param message Сообщение для подписи (хэшируется в messageHash)
     * @param signatureType Тип подписи ("Schnorr" или "ECDSA")
     * @param deadline Unix timestamp дедлайна
     */
    function createSession(
        uint256 sessionId,
        bytes calldata groupPubkey,
        bytes calldata message,
        string calldata signatureType,
        uint256 deadline
    ) external;

    /**
     * @notice Возвращает список хранителей (custodians)
     * @return Список адресов хранителей
     */
    function getCustodians() external view returns (address[] memory);

    /**
     * @notice Возвращает данные сессии
     * @param sessionId Идентификатор сессии
     * @return id Идентификатор сессии
     * @return creator Адрес создателя
     * @return groupPubkey Публичный ключ группы
     * @return messageHash Хэш сообщения
     * @return messageBound Зафиксирован ли messageHash
     * @return threshold Порог подписи
     * @return total Количество участников
     * @return deadline Unix timestamp дедлайна
     * @return enforceSharesCheck Требовать ли >= threshold шардов
     * @return verifierOverride Адрес верификатора (если есть)
     * @return state Состояние сессии (0=NONE, 1=OPENED, 2=FINALIZED, 3=ABORTED)
     * @return commitsCount Количество nonce commitments
     * @return sharesCount Количество signature shares
     * @return refusalCount Количество отказов
     * @return purpose Цель сессии (0=UNKNOWN, 1=WITHDRAWAL, 2=SLASH, 3=REDEMPTION, 4=BRIDGE_OUT, 5=BRIDGE_IN, 6=DKG)
     * @return originContract Контракт-инициатор
     * @return originId ID заявки в контракте-инициаторе
     * @return networkId ID сети (0=BTC, 1=DOGE, 2=BCH, 3=LTC)
     * @return poolId ID пула
     * @return dkgSharesCount Количество зашифрованных DKG shares (добавлено)
     */
    function getSession(uint256 sessionId)
        external
        view
        returns (
            uint256 id,
            address creator,
            bytes memory groupPubkey,
            bytes32 messageHash,
            bool messageBound,
            uint256 threshold,
            uint256 total,
            uint64 deadline,
            bool enforceSharesCheck,
            address verifierOverride,
            uint256 state,
            uint256 commitsCount,
            uint256 sharesCount,
            uint256 refusalCount,
            uint256 purpose,
            address originContract,
            uint256 originId,
            uint16 networkId,
            bytes32 poolId,
            uint256 dkgSharesCount
        );

    /**
     * @notice Финализирует сессию подписи
     * @param sessionId Идентификатор сессии
     * @param signature Агрегированная подпись
     * @param messageHash Хэш сообщения
     */
    function finalizeSession(
        uint256 sessionId,
        bytes calldata signature,
        bytes32 messageHash
    ) external;

    /**
     * @notice Отправляет nonce commitment
     * @param sessionId Идентификатор сессии
     * @param commitment Хэш nonce (keccak256)
     */
    function submitNonceCommit(uint256 sessionId, bytes32 commitment) external;

    /**
     * @notice Отправляет signature share
     * @param sessionId Идентификатор сессии
     * @param share Signature share
     */
    function submitSignatureShare(uint256 sessionId, bytes calldata share) external;

    /**
     * @notice Отправляет зашифрованную DKG share
     * @param sessionId Идентификатор сессии
     * @param recipient Адрес получателя share
     * @param encryptedShare Зашифрованная доля (например, через ECIES)
     */
    function submitDKGShare(uint256 sessionId, address recipient, bytes calldata encryptedShare) external;

    /**
     * @notice Финализирует DKG-сессию
     * @param sessionId Идентификатор сессии
     * @param groupPubkey Итоговый публичный ключ группы
     */
    function finalizeDKG(uint256 sessionId, bytes calldata groupPubkey) external;

    /**
     * @notice Получает зашифрованную DKG share
     * @param sessionId Идентификатор сессии
     * @param sender Адрес отправителя
     * @param recipient Адрес получателя
     * @return Зашифрованная доля
     */
    function getDKGShare(uint256 sessionId, address sender, address recipient) external view returns (bytes memory);

    /**
     * @notice Отказ от участия в сессии
     * @param sessionId Идентификатор сессии
     * @param reason Причина отказа (для слешинга)
     */
    function rejectSignatureRequest(uint256 sessionId, string calldata reason) external;

    /**
     * @notice Получает список участников сессии
     * @param sessionId Идентификатор сессии
     * @return participants Массив адресов участников
     */
    function getSessionParticipants(uint256 sessionId) external view returns (address[] memory participants);
}