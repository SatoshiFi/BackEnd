// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IDistributionScheme
 * @dev Интерфейс для схем распределения наград майнинг-пулов
 * Обновлено для поддержки DAO-членов (агрегация воркеров по владельцу).
 */
interface IDistributionScheme {

    // -----------------------------
    // Структуры данных
    // -----------------------------

    /**
     * @dev Данные отдельного воркера (low-level, как сейчас)
     */
    struct WorkerData {
        string workerId;        // ID воркера (offchain/stratum)
        address payoutAddress;  // Адрес для выплат (устарело, лучше использовать owner)
        address owner;          // Владелец воркера = член DAO
        uint256 validShares;    // Количество валидных шар
        uint256 totalShares;    // Общее количество шар
        uint256 lastActivity;   // Время последней активности
        uint256 hashRate;       // Хешрейт воркера
        bool isActive;          // Активен ли воркер
    }

    /**
     * @dev Данные агрегированные по члену DAO (owner), включают всех его воркеров
     */
    struct MemberData {
        address member;               // адрес члена DAO
        address payoutAddress;        // адрес куда платить (может быть EOA или контракт)
        uint256 aggregatedValidShares;
        uint256 aggregatedTotalShares;
        uint256 aggregatedHashRate;
        uint256 lastActivity;         // время последней активности любого воркера
        bool isActive;
    }

    /**
     * @dev Результат распределения
     */
    struct DistributionResult {
        address recipient;     // получатель (воркер или член DAO)
        uint256 amount;        // сумма награды
        string workerId;       // ID воркера (для совместимости, пусто если член DAO)
        uint256 percentage;    // процент от общей суммы (в базисных пунктах)
    }

    /**
     * @dev Параметры схемы
     */
    struct SchemeParams {
        uint256 windowSize;       // Размер окна (для PPLNS)
        uint256 baseRate;         // Базовая ставка (для PPS)
        uint256 difficultyTarget; // Целевая сложность
        uint256 blockReward;      // Награда за блок
        bytes additionalParams;   // Доп. параметры
    }

    // -----------------------------
    // Основные методы
    // -----------------------------

    /**
     * @dev Распределение по воркерам (старый режим)
     */
    function calculate(
        uint256 totalAmount,
        WorkerData[] memory workers,
        SchemeParams memory params
    ) external view returns (
        DistributionResult[] memory results,
        uint256 distributedAmount,
        uint256 remainder
    );

    /**
     * @dev Распределение по членам DAO (агрегированные данные)
     */
    function calculateForMembers(
        uint256 totalAmount,
        MemberData[] memory members,
        SchemeParams memory params
    ) external view returns (
        DistributionResult[] memory results,
        uint256 distributedAmount,
        uint256 remainder
    );

    /**
     * @dev Валидация входных данных (воркеры)
     */
    function validateInput(
        uint256 totalAmount,
        WorkerData[] memory workers,
        SchemeParams memory params
    ) external pure returns (bool isValid, string memory errorMessage);

    /**
     * @dev Валидация входных данных (члены)
     */
    function validateMemberInput(
        uint256 totalAmount,
        MemberData[] memory members,
        SchemeParams memory params
    ) external pure returns (bool isValid, string memory errorMessage);

    /**
     * @dev Получение метаданных схемы
     */
    function getSchemeInfo() external pure returns (
        string memory name,
        string memory version,
        string memory description
    );

    /**
     * @dev Оценка газовых затрат для расчета
     */
    function estimateGas(
        uint256 workerCount,
        SchemeParams memory params
    ) external pure returns (uint256 estimatedGas);
}
