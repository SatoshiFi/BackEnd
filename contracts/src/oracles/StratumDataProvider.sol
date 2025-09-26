// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title StratumDataProvider
 * @dev Контракт провайдера данных Stratum для индивидуального сервера
 */
contract StratumDataProvider {

    // Структура данных о шаре
    struct ShareData {
        string workerId;         // ID воркера
        uint256 difficulty;      // Сложность шары
        uint256 timestamp;       // Время нахождения
        bytes32 jobId;          // ID задания
        bytes32 shareHash;      // Хеш решения
        bool isValid;           // Валидна ли шара
        string rejectReason;    // Причина отклонения (если не валидна)
    }

    // Структура пакета данных
    struct DataBatch {
        uint256 batchId;        // ID пакета
        uint256 poolId;         // ID пула
        uint256 startTime;      // Время начала периода
        uint256 endTime;        // Время окончания периода
        ShareData[] shares;     // Массив шар
        bytes32 merkleRoot;     // Merkle root всех шар
        bytes signature;        // Подпись провайдера
        uint256 submittedAt;    // Время подачи
        bool isProcessed;       // Обработан ли пакет
    }

    // Состояние контракта
    address public provider;
    address public oracleRegistry;
    string public providerName;
    string public endpoint;
    bytes32 public publicKey;

    uint256 public batchCounter;
    uint256 public lastSubmissionTime;
    uint256 public totalSharesSubmitted;
    uint256 public totalBatchesSubmitted;

    // Настройки
    uint256 public constant MAX_SHARES_PER_BATCH = 10000;
    uint256 public constant MAX_BATCH_AGE = 1 hours;
    uint256 public constant MIN_BATCH_INTERVAL = 5 minutes;

    // Маппинги
    mapping(uint256 => DataBatch) public batches;
    mapping(uint256 => uint256[]) public poolBatches;    // poolId -> batchIds
    mapping(bytes32 => bool) public submittedHashes;     // Защита от дублей

    // События
    event BatchSubmitted(
        uint256 indexed batchId,
        uint256 indexed poolId,
        uint256 shareCount,
        bytes32 merkleRoot
    );

    event BatchProcessed(
        uint256 indexed batchId,
        bool success,
        string reason
    );

    event ShareAdded(
        uint256 indexed batchId,
        string indexed workerId,
        bool isValid
    );

    event ProviderConfigUpdated(
        string parameter,
        string newValue
    );

    // Модификаторы
    modifier onlyProvider() {
        require(msg.sender == provider, "Only provider");
        _;
    }

    modifier onlyOracleRegistry() {
        require(msg.sender == oracleRegistry, "Only oracle registry");
        _;
    }

    modifier validBatch(uint256 batchId) {
        require(batchId < batchCounter, "Invalid batch ID");
        _;
    }

    constructor(
        address _provider,
        address _oracleRegistry,
        string memory _providerName,
        string memory _endpoint,
        bytes32 _publicKey
    ) {
        provider = _provider;
        oracleRegistry = _oracleRegistry;
        providerName = _providerName;
        endpoint = _endpoint;
        publicKey = _publicKey;
        batchCounter = 0;
    }

    /**
     * @dev Подача пакета данных
     */
    function submitBatch(
        uint256 poolId,
        uint256 startTime,
        uint256 endTime,
        ShareData[] memory shares,
        bytes memory signature
    ) external onlyProvider returns (uint256 batchId) {

        require(shares.length > 0, "Empty batch");
        require(shares.length <= MAX_SHARES_PER_BATCH, "Batch too large");
        require(endTime > startTime, "Invalid time range");
        require(block.timestamp >= lastSubmissionTime + MIN_BATCH_INTERVAL, "Too frequent submissions");
        require(block.timestamp <= endTime + MAX_BATCH_AGE, "Batch too old");

        // Вычисление Merkle root
        bytes32 merkleRoot = _calculateMerkleRoot(shares);

        // Проверка на дубликаты
        require(!submittedHashes[merkleRoot], "Duplicate batch");
        submittedHashes[merkleRoot] = true;

        batchId = batchCounter++;

        // Создание пакета
        batches[batchId] = DataBatch({
            batchId: batchId,
            poolId: poolId,
            startTime: startTime,
            endTime: endTime,
            shares: shares,
            merkleRoot: merkleRoot,
            signature: signature,
            submittedAt: block.timestamp,
            isProcessed: false
        });

        poolBatches[poolId].push(batchId);

        // Обновление статистики
        totalSharesSubmitted += shares.length;
        totalBatchesSubmitted++;
        lastSubmissionTime = block.timestamp;

        emit BatchSubmitted(batchId, poolId, shares.length, merkleRoot);

        // Эмиссия событий для каждой шары
        for (uint256 i = 0; i < shares.length; i++) {
            emit ShareAdded(batchId, shares[i].workerId, shares[i].isValid);
        }

        return batchId;
    }

    /**
     * @dev Вычисление Merkle root для массива шар
     */
    function _calculateMerkleRoot(ShareData[] memory shares) internal pure returns (bytes32) {
        if (shares.length == 0) return bytes32(0);
        if (shares.length == 1) return _hashShare(shares[0]);

        // Упрощенная версия Merkle tree
        bytes32[] memory hashes = new bytes32[](shares.length);
        for (uint256 i = 0; i < shares.length; i++) {
            hashes[i] = _hashShare(shares[i]);
        }

        return _buildMerkleTree(hashes);
    }

    /**
     * @dev Хеширование отдельной шары
     */
    function _hashShare(ShareData memory share) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            share.workerId,
            share.difficulty,
            share.timestamp,
            share.jobId,
            share.shareHash,
            share.isValid
        ));
    }

    /**
     * @dev Построение Merkle tree
     */
    function _buildMerkleTree(bytes32[] memory hashes) internal pure returns (bytes32) {
        uint256 length = hashes.length;

        while (length > 1) {
            for (uint256 i = 0; i < length / 2; i++) {
                hashes[i] = keccak256(abi.encodePacked(hashes[2 * i], hashes[2 * i + 1]));
            }

            if (length % 2 == 1) {
                hashes[length / 2] = hashes[length - 1];
                length = length / 2 + 1;
            } else {
                length = length / 2;
            }
        }

        return hashes[0];
    }

    /**
     * @dev Отметка пакета как обработанного
     */
    function markBatchProcessed(
        uint256 batchId,
        bool success,
        string memory reason
    ) external onlyOracleRegistry validBatch(batchId) {

        batches[batchId].isProcessed = true;
        emit BatchProcessed(batchId, success, reason);
    }

    /**
     * @dev Получение данных пакета
     */
    function getBatch(uint256 batchId) external view validBatch(batchId) returns (DataBatch memory) {
        return batches[batchId];
    }

    /**
     * @dev Получение шар из пакета
     */
    function getBatchShares(uint256 batchId) external view validBatch(batchId) returns (ShareData[] memory) {
        return batches[batchId].shares;
    }

    /**
     * @dev Получение пакетов пула
     */
    function getPoolBatches(uint256 poolId) external view returns (uint256[] memory) {
        return poolBatches[poolId];
    }

    /**
     * @dev Получение последних пакетов
     */
    function getRecentBatches(uint256 count) external view returns (uint256[] memory) {
        if (count == 0 || batchCounter == 0) {
            return new uint256[](0);
        }

        if (count > batchCounter) count = batchCounter;

        uint256[] memory recentBatches = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            recentBatches[i] = batchCounter - 1 - i;
        }

        return recentBatches;
    }

    /**
     * @dev Проверка подписи пакета
     */
    function verifyBatchSignature(
        uint256 batchId,
        bytes memory signature
    ) external view validBatch(batchId) returns (bool) {

        DataBatch memory batch = batches[batchId];
        bytes32 messageHash = keccak256(abi.encodePacked(
            batch.poolId,
            batch.startTime,
            batch.endTime,
            batch.merkleRoot
        ));

        // Упрощенная проверка подписи (в продакшене нужна полная ECDSA)
        return keccak256(signature) == keccak256(batch.signature);
    }

    /**
     * @dev Получение статистики провайдера
     */
    function getProviderStats() external view returns (
        uint256 _totalBatches,
        uint256 _totalShares,
        uint256 _lastSubmission,
        uint256 _avgSharesPerBatch
    ) {
        _totalBatches = totalBatchesSubmitted;
        _totalShares = totalSharesSubmitted;
        _lastSubmission = lastSubmissionTime;
        _avgSharesPerBatch = _totalBatches > 0 ? _totalShares / _totalBatches : 0;

        return (_totalBatches, _totalShares, _lastSubmission, _avgSharesPerBatch);
    }

    /**
     * @dev Анализ качества данных
     */
    function analyzeDataQuality(uint256 poolId) external view returns (
        uint256 totalShares,
        uint256 validShares,
        uint256 invalidShares,
        uint256 qualityScore
    ) {
        uint256[] memory poolBatchList = poolBatches[poolId];

        for (uint256 i = 0; i < poolBatchList.length; i++) {
            ShareData[] memory shares = batches[poolBatchList[i]].shares;

            for (uint256 j = 0; j < shares.length; j++) {
                totalShares++;
                if (shares[j].isValid) {
                    validShares++;
                } else {
                    invalidShares++;
                }
            }
        }

        qualityScore = totalShares > 0 ? (validShares * 10000) / totalShares : 0;

        return (totalShares, validShares, invalidShares, qualityScore);
    }

    /**
     * @dev Обновление конфигурации провайдера
     */
    function updateProviderConfig(
        string memory parameter,
        string memory newValue
    ) external onlyProvider {

        if (keccak256(bytes(parameter)) == keccak256(bytes("name"))) {
            providerName = newValue;
        } else if (keccak256(bytes(parameter)) == keccak256(bytes("endpoint"))) {
            endpoint = newValue;
        } else {
            revert("Invalid parameter");
        }

        emit ProviderConfigUpdated(parameter, newValue);
    }

    /**
     * @dev Получение информации о провайдере
     */
    function getProviderInfo() external view returns (
        address _provider,
        string memory _name,
        string memory _endpoint,
        bytes32 _publicKey
    ) {
        return (provider, providerName, endpoint, publicKey);
    }

    /**
     * @dev Очистка старых данных
     */
    function cleanupOldBatches(uint256 maxAge) external onlyProvider {
        uint256 cutoffTime = block.timestamp - maxAge;

        // Упрощенная очистка - помечаем как обработанные
        for (uint256 i = 0; i < batchCounter; i++) {
            if (batches[i].submittedAt < cutoffTime && !batches[i].isProcessed) {
                batches[i].isProcessed = true;
                emit BatchProcessed(i, false, "Expired");
            }
        }
    }
}
