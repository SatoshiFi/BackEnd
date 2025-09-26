// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IDistributionScheme.sol";

/**
 * @title CalculatorRegistry
 * @dev Реестр калькуляторов распределения с управлением версиями и whitelist
 */
contract CalculatorRegistry {

    // Типы схем распределения
    enum SchemeType {
        PPLNS,      // Pay Per Last N Shares
        PPS,        // Pay Per Share
        FPPS,       // Full Pay Per Share
        SCORE,      // Score-based
        CUSTOM      // Кастомная схема
    }

    // Структура калькулятора
    struct Calculator {
        address contractAddress;     // Адрес контракта
        SchemeType schemeType;       // Тип схемы
        string name;                 // Название
        string description;          // Описание
        string version;              // Версия
        address author;              // Автор
        uint256 registeredAt;        // Время регистрации
        uint256 gasEstimate;         // Оценка газа
        bool isActive;               // Активен ли
        bool isWhitelisted;          // В белом списке
        uint256 usageCount;          // Количество использований
        uint256 totalGasUsed;        // Общий газ использованный
    }

    // Структура метаданных схемы
    struct SchemeMetadata {
        string[] supportedParams;    // Поддерживаемые параметры
        uint256 minWorkers;          // Минимум воркеров
        uint256 maxWorkers;          // Максимум воркеров
        uint256 avgGasPerWorker;     // Средний газ на воркера
        bool supportsSimulation;     // Поддержка симуляции
        string documentation;        // Ссылка на документацию
    }

    // Состояние контракта
    address public admin;
    address public poolFactory;
    uint256 public calculatorCounter;

    // Константы
    uint256 public constant MAX_GAS_ESTIMATE = 5000000;  // 5M газа максимум
    uint256 public constant MIN_GAS_ESTIMATE = 50000;    // 50k газа минимум

    // Маппинги
    mapping(uint256 => Calculator) public calculators;
    mapping(address => uint256) public calculatorByAddress;
    mapping(SchemeType => uint256[]) public calculatorsByType;
    mapping(address => bool) public authorizedAuthors;
    mapping(uint256 => SchemeMetadata) public metadata;

    // Статистика
    mapping(uint256 => uint256) public weeklyUsage;      // Недельная статистика
    mapping(address => uint256) public authorEarnings;   // Заработок авторов

    // События
    event CalculatorRegistered(
        uint256 indexed calculatorId,
        address indexed contractAddress,
        SchemeType schemeType,
        address indexed author
    );

    event PoolFactoryUpdated(
        address indexed oldFactory,
        address indexed newFactory
    );

    event CalculatorWhitelisted(
        uint256 indexed calculatorId,
        bool whitelisted
    );

    event CalculatorUsed(
        uint256 indexed calculatorId,
        uint256 gasUsed,
        address indexed user
    );

    event AuthorAuthorized(
        address indexed author,
        bool authorized
    );

    event CalculatorUpdated(
        uint256 indexed calculatorId,
        string parameter,
        string newValue
    );

    // Модификаторы
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyPoolFactory() {
        require(msg.sender == poolFactory, "Only pool factory");
        _;
    }

    modifier onlyAuthorizedAuthor() {
        require(authorizedAuthors[msg.sender], "Not authorized author");
        _;
    }

    modifier validCalculator(uint256 calculatorId) {
        require(calculatorId < calculatorCounter, "Invalid calculator ID");
        _;
    }

    modifier activeCalculator(uint256 calculatorId) {
        require(calculators[calculatorId].isActive, "Calculator not active");
        _;
    }

    constructor(address _admin, address _poolFactory) {
        admin = _admin;
        poolFactory = _poolFactory;
        calculatorCounter = 0;
    }

    /**
     * @dev Регистрация нового калькулятора
     */
    function registerCalculator(
        address contractAddress,
        SchemeType schemeType,
        string memory name,
        string memory description,
        string memory version,
        uint256 gasEstimate
    ) external onlyAuthorizedAuthor returns (uint256 calculatorId) {

        require(contractAddress != address(0), "Invalid contract address");
        require(bytes(name).length > 0, "Name required");
        require(gasEstimate >= MIN_GAS_ESTIMATE, "Gas estimate too low");
        require(gasEstimate <= MAX_GAS_ESTIMATE, "Gas estimate too high");
        require(calculatorByAddress[contractAddress] == 0, "Already registered");

        // Проверка интерфейса
        require(_checkInterface(contractAddress), "Invalid interface");

        calculatorId = calculatorCounter++;

        calculators[calculatorId] = Calculator({
            contractAddress: contractAddress,
            schemeType: schemeType,
            name: name,
            description: description,
            version: version,
            author: msg.sender,
            registeredAt: block.timestamp,
            gasEstimate: gasEstimate,
            isActive: true,
            isWhitelisted: false,
            usageCount: 0,
            totalGasUsed: 0
        });

        calculatorByAddress[contractAddress] = calculatorId;
        calculatorsByType[schemeType].push(calculatorId);

        emit CalculatorRegistered(calculatorId, contractAddress, schemeType, msg.sender);

        return calculatorId;
    }

    /**
     * @dev Обновление адреса pool factory (только admin)
     */
    function setPoolFactory(address _poolFactory) external onlyAdmin {
        require(_poolFactory != address(0), "Invalid pool factory address");

        address oldFactory = poolFactory;
        poolFactory = _poolFactory;

        emit PoolFactoryUpdated(oldFactory, _poolFactory);
    }

    /**
     * @dev Проверка интерфейса калькулятора
     */
    function _checkInterface(address contractAddress) internal view returns (bool) {
        // Упрощенная проверка - просто проверяем что контракт существует
        uint256 size;
        assembly {
            size := extcodesize(contractAddress)
        }
        return size > 0;
    }

    /**
     * @dev Добавление в whitelist
     */
    function whitelistCalculator(uint256 calculatorId, bool whitelisted)
    external onlyAdmin validCalculator(calculatorId) {

        calculators[calculatorId].isWhitelisted = whitelisted;
        emit CalculatorWhitelisted(calculatorId, whitelisted);
    }

    /**
     * @dev Получение калькулятора для использования
     */
    function getCalculator(uint256 calculatorId)
    external validCalculator(calculatorId) activeCalculator(calculatorId)
    returns (address) {

        Calculator storage calc = calculators[calculatorId];
        require(calc.isWhitelisted, "Calculator not whitelisted");

        // Обновление статистики
        calc.usageCount++;
        weeklyUsage[calculatorId]++;

        emit CalculatorUsed(calculatorId, 0, msg.sender);

        return calc.contractAddress;
    }

    /**
     * @dev Отчет об использовании газа
     */
    function reportGasUsage(uint256 calculatorId, uint256 gasUsed)
    external validCalculator(calculatorId) {

        calculators[calculatorId].totalGasUsed += gasUsed;
        emit CalculatorUsed(calculatorId, gasUsed, msg.sender);

        // Награда автору (если настроена)
        address author = calculators[calculatorId].author;
        if (author != address(0)) {
            authorEarnings[author] += gasUsed / 10000; // Символическая награда
        }
    }

    /**
     * @dev Получение лучших калькуляторов по типу
     */
    function getBestCalculators(SchemeType schemeType, uint256 limit)
    external view returns (uint256[] memory) {

        uint256[] memory typeCalculators = calculatorsByType[schemeType];
        if (typeCalculators.length == 0 || limit == 0) {
            return new uint256[](0);
        }

        uint256 resultCount = typeCalculators.length < limit ? typeCalculators.length : limit;
        uint256[] memory result = new uint256[](resultCount);
        uint256[] memory scores = new uint256[](typeCalculators.length);

        // Расчет скоров
        for (uint256 i = 0; i < typeCalculators.length; i++) {
            uint256 calcId = typeCalculators[i];
            Calculator memory calc = calculators[calcId];

            if (calc.isActive && calc.isWhitelisted) {
                uint256 score = _calculateScore(calcId);
                scores[i] = score;
            }
        }

        // Простая сортировка (для продакшена нужен более эффективный алгоритм)
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 maxScore = 0;
            uint256 maxIndex = 0;

            for (uint256 j = 0; j < typeCalculators.length; j++) {
                if (scores[j] > maxScore) {
                    maxScore = scores[j];
                    maxIndex = j;
                }
            }

            result[i] = typeCalculators[maxIndex];
            scores[maxIndex] = 0; // Убираем из следующих итераций
        }

        return result;
    }

    /**
     * @dev Расчет скора калькулятора
     */
    function _calculateScore(uint256 calculatorId) internal view returns (uint256) {
        Calculator memory calc = calculators[calculatorId];

        if (!calc.isActive || !calc.isWhitelisted) return 0;

        uint256 score = 10000; // Базовый скор

        // Бонус за использование
        score += calc.usageCount * 10;

        // Штраф за высокий расход газа
        if (calc.usageCount > 0) {
            uint256 avgGas = calc.totalGasUsed / calc.usageCount;
            if (avgGas > calc.gasEstimate) {
                score = score * calc.gasEstimate / avgGas;
            }
        }

        // Бонус за новизну
        uint256 age = block.timestamp - calc.registeredAt;
        if (age < 30 days) {
            score += 1000;
        }

        return score;
    }

    /**
     * @dev Поиск калькуляторов
     */
    function searchCalculators(
        string memory query,
        SchemeType schemeType,
        bool onlyWhitelisted
    ) external view returns (uint256[] memory) {

        uint256[] memory typeCalculators = calculatorsByType[schemeType];
        uint256[] memory results = new uint256[](typeCalculators.length);
        uint256 resultCount = 0;

        for (uint256 i = 0; i < typeCalculators.length; i++) {
            uint256 calcId = typeCalculators[i];
            Calculator memory calc = calculators[calcId];

            if (!calc.isActive) continue;
            if (onlyWhitelisted && !calc.isWhitelisted) continue;

            // Простой поиск по имени (в продакшене нужен более сложный)
            if (bytes(query).length == 0 || _contains(calc.name, query)) {
                results[resultCount] = calcId;
                resultCount++;
            }
        }

        // Обрезка массива
        uint256[] memory finalResults = new uint256[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            finalResults[i] = results[i];
        }

        return finalResults;
    }

    /**
     * @dev Проверка содержания подстроки
     */
    function _contains(string memory source, string memory query) internal pure returns (bool) {
        bytes memory sourceBytes = bytes(source);
        bytes memory queryBytes = bytes(query);

        if (queryBytes.length > sourceBytes.length) return false;
        if (queryBytes.length == 0) return true;

        // Упрощенная проверка
        return keccak256(sourceBytes) == keccak256(queryBytes);
    }

    /**
     * @dev Установка метаданных
     */
    function setMetadata(
        uint256 calculatorId,
        SchemeMetadata memory _metadata
    ) external validCalculator(calculatorId) {

        require(
            msg.sender == calculators[calculatorId].author || msg.sender == admin,
            "Not authorized"
        );

        metadata[calculatorId] = _metadata;
    }

    /**
     * @dev Авторизация автора
     */
    function authorizeAuthor(address author, bool authorized) external onlyAdmin {
        authorizedAuthors[author] = authorized;
        emit AuthorAuthorized(author, authorized);
    }

    /**
     * @dev Деактивация калькулятора
     */
    function deactivateCalculator(uint256 calculatorId)
    external validCalculator(calculatorId) {

        require(
            msg.sender == calculators[calculatorId].author || msg.sender == admin,
            "Not authorized"
        );

        calculators[calculatorId].isActive = false;
    }

    /**
     * @dev Получение статистики реестра
     */
    function getRegistryStats() external view returns (
        uint256 totalCalculators,
        uint256 activeCalculators,
        uint256 whitelistedCalculators,
        uint256 totalUsage
    ) {
        uint256 active = 0;
        uint256 whitelisted = 0;
        uint256 usage = 0;

        for (uint256 i = 0; i < calculatorCounter; i++) {
            Calculator memory calc = calculators[i];
            if (calc.isActive) active++;
            if (calc.isWhitelisted) whitelisted++;
            usage += calc.usageCount;
        }

        return (calculatorCounter, active, whitelisted, usage);
    }

    /**
     * @dev Получение калькуляторов по типу
     */
    function getCalculatorsByType(SchemeType schemeType)
    external view returns (uint256[] memory) {
        return calculatorsByType[schemeType];
    }

    /**
     * @dev Получение информации о калькуляторе
     */
    function getCalculatorInfo(uint256 calculatorId)
    external view validCalculator(calculatorId)
    returns (Calculator memory, SchemeMetadata memory) {
        return (calculators[calculatorId], metadata[calculatorId]);
    }
}