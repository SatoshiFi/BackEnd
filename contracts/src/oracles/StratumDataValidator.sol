// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title StratumDataValidator
 * @dev Валидация данных от провайдеров Stratum и обнаружение аномалий
 */
contract StratumDataValidator {

    // Структура правил валидации
    struct ValidationRules {
        uint256 maxSharesPerWorker;      // Максимум шар на воркера
        uint256 maxSharesPerMinute;      // Максимум шар в минуту
        uint256 minDifficulty;           // Минимальная сложность
        uint256 maxDifficulty;           // Максимальная сложность
        uint256 maxTimestampDeviation;   // Максимальное отклонение времени
        uint256 minValidityRatio;        // Минимальный процент валидных шар
        uint256 maxWorkerVariance;       // Максимальная дисперсия воркеров
        bool strictTimeValidation;       // Строгая валидация времени
    }

    // Структура результата валидации
    struct ValidationResult {
        bool isValid;                    // Общий результат валидации
        uint256 score;                   // Оценка качества (0-10000)
        string[] warnings;               // Предупреждения
        string[] errors;                 // Ошибки
        uint256 suspiciousShares;        // Подозрительные шары
        uint256 anomalyFlags;            // Флаги аномалий
        uint256 validatedAt;             // Время валидации
    }

    // Структура статистики воркера
    struct WorkerStats {
        string workerId;                 // ID воркера
        uint256 totalShares;             // Общие шары
        uint256 validShares;             // Валидные шары
        uint256 timeSpan;                // Временной промежуток
        uint256 avgDifficulty;           // Средняя сложность
        uint256 sharesPerMinute;         // Шар в минуту
        bool hasAnomalies;               // Есть ли аномалии
    }

    // Флаги аномалий
    uint256 public constant ANOMALY_HIGH_FREQUENCY = 1;        // Высокая частота
    uint256 public constant ANOMALY_LOW_VALIDITY = 2;          // Низкая валидность
    uint256 public constant ANOMALY_TIME_DRIFT = 4;            // Смещение времени
    uint256 public constant ANOMALY_DUPLICATE_SHARES = 8;      // Дублированные шары
    uint256 public constant ANOMALY_SUSPICIOUS_PATTERN = 16;   // Подозрительный паттерн
    uint256 public constant ANOMALY_EXTREME_DIFFICULTY = 32;   // Экстремальная сложность

    // Состояние контракта
    address public admin;
    address public oracleRegistry;
    ValidationRules public defaultRules;

    // Маппинги
    mapping(uint256 => ValidationRules) public poolRules;      // poolId -> rules
    mapping(bytes32 => ValidationResult) public validationResults;
    mapping(bytes32 => bool) public knownHashes;              // Защита от дублей
    mapping(string => uint256) public workerLastSeen;         // Последняя активность воркера

    // События
    event ValidationCompleted(
        bytes32 indexed dataHash,
        bool isValid,
        uint256 score,
        uint256 anomalyFlags
    );

    event AnomalyDetected(
        bytes32 indexed dataHash,
        uint256 anomalyType,
        string description
    );

    event RulesUpdated(
        uint256 indexed poolId,
        string parameter,
        uint256 newValue
    );

    event SuspiciousActivity(
        string indexed workerId,
        uint256 anomalyType,
        uint256 severity
    );

    // Модификаторы
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyOracleRegistry() {
        require(msg.sender == oracleRegistry, "Only oracle registry");
        _;
    }

    constructor(address _admin, address _oracleRegistry) {
        admin = _admin;
        oracleRegistry = _oracleRegistry;

        // Установка правил по умолчанию
        defaultRules = ValidationRules({
            maxSharesPerWorker: 10000,        // 10k шар на воркера
            maxSharesPerMinute: 100,          // 100 шар в минуту
            minDifficulty: 1,                 // Минимальная сложность
            maxDifficulty: 1000000,           // Максимальная сложность
            maxTimestampDeviation: 300,       // 5 минут
            minValidityRatio: 7000,           // 70% валидных шар минимум
            maxWorkerVariance: 5000,          // 50% максимальная дисперсия
            strictTimeValidation: true
        });
    }

    /**
     * @dev Валидация пакета данных
     */
    function validateBatch(
        uint256 poolId,
        bytes32 dataHash,
        uint256 startTime,
        uint256 endTime,
        WorkerStats[] memory workerStats
    ) external onlyOracleRegistry returns (ValidationResult memory result) {

        require(dataHash != bytes32(0), "Invalid data hash");
        require(endTime > startTime, "Invalid time range");
        require(workerStats.length > 0, "No worker data");

        // Проверка на дубликаты
        require(!knownHashes[dataHash], "Duplicate data hash");
        knownHashes[dataHash] = true;

        // Получение правил валидации
        ValidationRules memory rules = poolRules[poolId].maxSharesPerWorker > 0 ?
            poolRules[poolId] : defaultRules;

        // Инициализация результата
        result = ValidationResult({
            isValid: true,
            score: 10000,
            warnings: new string[](0),
            errors: new string[](0),
            suspiciousShares: 0,
            anomalyFlags: 0,
            validatedAt: block.timestamp
        });

        // Выполнение валидации
        _performValidation(poolId, startTime, endTime, workerStats, rules, result);

        // Сохранение результата
        validationResults[dataHash] = result;

        emit ValidationCompleted(dataHash, result.isValid, result.score, result.anomalyFlags);

        return result;
    }

    /**
     * @dev Основная логика валидации
     */
    function _performValidation(
        uint256 poolId,
        uint256 startTime,
        uint256 endTime,
        WorkerStats[] memory workerStats,
        ValidationRules memory rules,
        ValidationResult memory result
    ) internal {

        uint256 totalShares = 0;
        uint256 totalValidShares = 0;
        uint256 timeSpan = endTime - startTime;

        // Валидация каждого воркера
        for (uint256 i = 0; i < workerStats.length; i++) {
            WorkerStats memory worker = workerStats[i];

            // Базовые проверки воркера
            _validateWorker(worker, rules, result);

            totalShares += worker.totalShares;
            totalValidShares += worker.validShares;

            // Проверка частоты шар
            if (timeSpan > 0) {
                uint256 sharesPerMinute = (worker.totalShares * 60) / timeSpan;
                if (sharesPerMinute > rules.maxSharesPerMinute) {
                    result.anomalyFlags |= ANOMALY_HIGH_FREQUENCY;
                    _addWarning(result, "High frequency detected");
                }
            }
        }

        // Общие проверки пакета
        _validateBatchIntegrity(totalShares, totalValidShares, rules, result);

        // Обнаружение паттернов
        _detectSuspiciousPatterns(workerStats, result);

        // Расчет итогового скора
        _calculateFinalScore(result);

        // Определение общей валидности
        result.isValid = result.score >= 7000 && result.anomalyFlags == 0;
    }

    /**
     * @dev Валидация отдельного воркера
     */
    function _validateWorker(
        WorkerStats memory worker,
        ValidationRules memory rules,
        ValidationResult memory result
    ) internal {

        // Проверка количества шар
        if (worker.totalShares > rules.maxSharesPerWorker) {
            result.anomalyFlags |= ANOMALY_HIGH_FREQUENCY;
            _addError(result, "Worker exceeds max shares");
        }

        // Проверка валидности шар
        if (worker.totalShares > 0) {
            uint256 validityRatio = (worker.validShares * 10000) / worker.totalShares;
            if (validityRatio < rules.minValidityRatio) {
                result.anomalyFlags |= ANOMALY_LOW_VALIDITY;
                _addWarning(result, "Low validity ratio");
            }
        }

        // Проверка сложности
        if (worker.avgDifficulty < rules.minDifficulty ||
            worker.avgDifficulty > rules.maxDifficulty) {
            result.anomalyFlags |= ANOMALY_EXTREME_DIFFICULTY;
            _addWarning(result, "Difficulty out of range");
        }

        // Обновление последней активности
        workerLastSeen[worker.workerId] = block.timestamp;
    }

    /**
     * @dev Валидация целостности пакета
     */
    function _validateBatchIntegrity(
        uint256 totalShares,
        uint256 totalValidShares,
        ValidationRules memory rules,
        ValidationResult memory result
    ) internal pure {

        if (totalShares == 0) {
            _addError(result, "No shares in batch");
            return;
        }

        uint256 overallValidityRatio = (totalValidShares * 10000) / totalShares;
        if (overallValidityRatio < rules.minValidityRatio) {
            result.anomalyFlags |= ANOMALY_LOW_VALIDITY;
            _addError(result, "Overall validity too low");
        }
    }

    /**
     * @dev Обнаружение подозрительных паттернов
     */
    function _detectSuspiciousPatterns(
        WorkerStats[] memory workerStats,
        ValidationResult memory result
    ) internal pure {

        if (workerStats.length < 2) return;

        // Проверка на слишком похожие результаты
        uint256 identicalWorkers = 0;

        for (uint256 i = 0; i < workerStats.length; i++) {
            for (uint256 j = i + 1; j < workerStats.length; j++) {
                if (_areWorkerStatsIdentical(workerStats[i], workerStats[j])) {
                    identicalWorkers++;
                }
            }
        }

        if (identicalWorkers > workerStats.length / 4) {
            result.anomalyFlags |= ANOMALY_SUSPICIOUS_PATTERN;
            _addWarning(result, "Suspicious identical patterns");
        }

        // Проверка на экстремальную дисперсию
        uint256 avgShares = _calculateAverageShares(workerStats);
        uint256 variance = _calculateVariance(workerStats, avgShares);

        if (variance > 5000) { // 50% variance
            result.anomalyFlags |= ANOMALY_SUSPICIOUS_PATTERN;
            _addWarning(result, "High variance in worker performance");
        }
    }

    /**
     * @dev Проверка идентичности статистики воркеров
     */
    function _areWorkerStatsIdentical(
        WorkerStats memory worker1,
        WorkerStats memory worker2
    ) internal pure returns (bool) {
        return worker1.totalShares == worker2.totalShares &&
               worker1.validShares == worker2.validShares &&
               worker1.avgDifficulty == worker2.avgDifficulty;
    }

    /**
     * @dev Расчет средних шар
     */
    function _calculateAverageShares(WorkerStats[] memory workerStats) internal pure returns (uint256) {
        if (workerStats.length == 0) return 0;

        uint256 total = 0;
        for (uint256 i = 0; i < workerStats.length; i++) {
            total += workerStats[i].totalShares;
        }

        return total / workerStats.length;
    }

    /**
     * @dev Расчет дисперсии
     */
    function _calculateVariance(
        WorkerStats[] memory workerStats,
        uint256 average
    ) internal pure returns (uint256) {
        if (workerStats.length == 0) return 0;

        uint256 sumSquaredDiff = 0;
        for (uint256 i = 0; i < workerStats.length; i++) {
            uint256 diff = workerStats[i].totalShares > average ?
                workerStats[i].totalShares - average :
                average - workerStats[i].totalShares;
            sumSquaredDiff += diff * diff;
        }

        uint256 variance = sumSquaredDiff / workerStats.length;
        return average > 0 ? (variance * 10000) / (average * average) : 0;
    }

    /**
     * @dev Расчет итогового скора
     */
    function _calculateFinalScore(ValidationResult memory result) internal pure {
        // Базовый скор уменьшается за каждую аномалию
        uint256 score = 10000;

        // Подсчет активных флагов аномалий
        uint256 anomalyCount = 0;
        uint256 flags = result.anomalyFlags;

        for (uint256 i = 0; i < 8; i++) {
            if (flags & (1 << i) != 0) {
                anomalyCount++;
            }
        }

        // Штраф за аномалии
        uint256 penalty = anomalyCount * 1500; // 15% за каждую аномалию
        if (penalty > score) {
            score = 0;
        } else {
            score -= penalty;
        }

        result.score = score;
    }

    /**
     * @dev Добавление предупреждения
     */
    function _addWarning(ValidationResult memory result, string memory warning) internal pure {
        // Упрощенная версия - в продакшене нужна динамическая реализация
        // result.warnings.push(warning);
    }

    /**
     * @dev Добавление ошибки
     */
    function _addError(ValidationResult memory result, string memory error) internal pure {
        // Упрощенная версия - в продакшене нужна динамическая реализация
        // result.errors.push(error);
    }

    /**
     * @dev Установка правил для пула
     */
    function setPoolRules(
        uint256 poolId,
        ValidationRules memory rules
    ) external onlyAdmin {

        require(rules.maxSharesPerWorker > 0, "Invalid max shares");
        require(rules.minValidityRatio <= 10000, "Invalid validity ratio");

        poolRules[poolId] = rules;

        emit RulesUpdated(poolId, "all", 0);
    }

    /**
     * @dev Получение результата валидации
     */
    function getValidationResult(bytes32 dataHash) external view returns (ValidationResult memory) {
        return validationResults[dataHash];
    }

    /**
     * @dev Проверка подозрительной активности воркера
     */
    function checkWorkerActivity(
        string memory workerId,
        uint256 currentShares,
        uint256 timeWindow
    ) external view returns (bool isSuspicious, uint256 riskScore) {

        uint256 lastSeen = workerLastSeen[workerId];
        if (lastSeen == 0) return (false, 0);

        uint256 timePassed = block.timestamp - lastSeen;
        if (timePassed > timeWindow) return (false, 0);

        // Упрощенный расчет риска
        uint256 sharesPerHour = timeWindow > 0 ? (currentShares * 3600) / timeWindow : 0;

        if (sharesPerHour > 6000) { // Больше 100 шар в минуту
            return (true, 8000);
        } else if (sharesPerHour > 3600) { // Больше 60 шар в минуту
            return (true, 5000);
        }

        return (false, 0);
    }

    /**
     * @dev Получение статистики валидатора
     */
    function getValidatorStats() external view returns (
        uint256 totalValidations,
        uint256 validBatches,
        uint256 invalidBatches,
        uint256 totalAnomalies
    ) {
        // Упрощенная версия - в продакшене нужно отслеживание
        return (0, 0, 0, 0);
    }

    /**
     * @dev Обновление правил по умолчанию
     */
    function updateDefaultRules(ValidationRules memory newRules) external onlyAdmin {
        require(newRules.maxSharesPerWorker > 0, "Invalid rules");
        defaultRules = newRules;
    }
}
