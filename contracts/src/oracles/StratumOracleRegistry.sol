// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title StratumOracleRegistry
 * @dev Реестр оракулов для системы Stratum данных
 */
contract StratumOracleRegistry {

    // Статусы провайдеров
    enum ProviderStatus {
        INACTIVE,        // 0 - неактивен
        PROBATIONARY,    // 1 - испытательный период
        ACTIVE,          // 2 - активен
        SUSPENDED,       // 3 - приостановлен
        SLASHED          // 4 - наказан
    }

    // Структура провайдера данных
    struct DataProvider {
        address providerAddress;     // Адрес провайдера
        string name;                 // Название провайдера
        string endpoint;             // URL endpoint
        bytes32 publicKey;           // Публичный ключ для подписей
        uint256 stake;               // Размер залога
        ProviderStatus status;       // Статус провайдера
        uint256 reputation;          // Репутация (0-1000)
        uint256 registeredAt;        // Время регистрации
        uint256 lastActiveAt;        // Последняя активность
        uint256 totalDataSubmitted;  // Всего данных подано
        uint256 validSubmissions;    // Валидных подач
        uint256 invalidSubmissions;  // Невалидных подач
        uint256[] supportedPools;    // Поддерживаемые пулы
    }

    // Структура слэшинга
    struct SlashingRecord {
        address provider;            // Адрес провайдера
        uint256 amount;              // Размер штрафа
        string reason;               // Причина
        uint256 timestamp;           // Время
        address slasher;             // Кто применил штраф
    }

    // Состояние контракта
    address public admin;
    address public poolFactory;
    uint256 public minimumStake;
    uint256 public maxProviders;
    uint256 public providerCounter;
    uint256 public slashingCounter;

    // Маппинги
    mapping(address => DataProvider) public providers;
    mapping(address => bool) public isRegisteredProvider;
    mapping(uint256 => address[]) public poolProviders;        // poolId -> providers
    mapping(address => uint256[]) public providerPools;        // provider -> poolIds
    mapping(uint256 => SlashingRecord) public slashingRecords;
    mapping(address => uint256) public providerSlashCount;

    address[] public allProviders;

    // События
    event ProviderRegistered(
        address indexed provider,
        string name,
        uint256 stake,
        uint256 reputation
    );

    event ProviderStatusChanged(
        address indexed provider,
        ProviderStatus oldStatus,
        ProviderStatus newStatus
    );

    event ProviderSlashed(
        address indexed provider,
        uint256 amount,
        string reason
    );

    event ReputationUpdated(
        address indexed provider,
        uint256 oldReputation,
        uint256 newReputation
    );

    event DataSubmitted(
        address indexed provider,
        uint256 indexed poolId,
        bytes32 indexed dataHash,
        bool isValid
    );

    event ProviderPoolAssigned(
        address indexed provider,
        uint256 indexed poolId
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

    modifier onlyRegisteredProvider() {
        require(isRegisteredProvider[msg.sender], "Not registered provider");
        _;
    }

    modifier validProvider(address provider) {
        require(isRegisteredProvider[provider], "Invalid provider");
        _;
    }

    constructor(address _poolFactory) {
        admin = msg.sender;
        poolFactory = _poolFactory;
        minimumStake = 1 ether;
        maxProviders = 50;
        providerCounter = 0;
        slashingCounter = 0;
    }

    /**
     * @dev Регистрация нового провайдера данных
     */
    function registerProvider(
        string memory name,
        string memory endpoint,
        bytes32 publicKey
    ) external payable {
        require(bytes(name).length > 0, "Name required");
        require(bytes(endpoint).length > 0, "Endpoint required");
        require(publicKey != bytes32(0), "Public key required");
        require(msg.value >= minimumStake, "Insufficient stake");
        require(!isRegisteredProvider[msg.sender], "Already registered");
        require(providerCounter < maxProviders, "Max providers reached");

        providers[msg.sender] = DataProvider({
            providerAddress: msg.sender,
            name: name,
            endpoint: endpoint,
            publicKey: publicKey,
                stake: msg.value,
                status: ProviderStatus.PROBATIONARY,
                reputation: 500, // Начальная репутация 50%
                registeredAt: block.timestamp,
                lastActiveAt: block.timestamp,
                totalDataSubmitted: 0,
                validSubmissions: 0,
                invalidSubmissions: 0,
                supportedPools: new uint256[](0)
        });

        isRegisteredProvider[msg.sender] = true;
        allProviders.push(msg.sender);
        providerCounter++;

        emit ProviderRegistered(msg.sender, name, msg.value, 500);
    }

    /**
     * @dev Назначение провайдера на пул
     */
    function assignProviderToPool(address provider, uint256 poolId)
    external
    onlyPoolFactory
    validProvider(provider)
    {
        require(providers[provider].status == ProviderStatus.ACTIVE, "Provider not active");

        // Проверяем что провайдер еще не назначен на этот пул
        uint256[] storage providerPoolList = providerPools[provider];
        for (uint256 i = 0; i < providerPoolList.length; i++) {
            require(providerPoolList[i] != poolId, "Already assigned to pool");
        }

        poolProviders[poolId].push(provider);
        providerPools[provider].push(poolId);
        providers[provider].supportedPools.push(poolId);

        emit ProviderPoolAssigned(provider, poolId);
    }

    /**
     * @dev Подача данных провайдером
     */
    function submitData(
        uint256 poolId,
        bytes32 dataHash,
        bytes memory signature
    ) external onlyRegisteredProvider {
        require(providers[msg.sender].status == ProviderStatus.ACTIVE ||
        providers[msg.sender].status == ProviderStatus.PROBATIONARY, "Provider not active");

        // Проверка что провайдер работает с этим пулом
        bool isAssigned = false;
        uint256[] memory providerPoolList = providerPools[msg.sender];
        for (uint256 i = 0; i < providerPoolList.length; i++) {
            if (providerPoolList[i] == poolId) {
                isAssigned = true;
                break;
            }
        }
        require(isAssigned, "Not assigned to this pool");

        // Проверка подписи (упрощенная версия)
        bool isValid = _verifySignature(dataHash, signature, providers[msg.sender].publicKey);

        // Обновление статистики
        providers[msg.sender].totalDataSubmitted++;
        providers[msg.sender].lastActiveAt = block.timestamp;

        if (isValid) {
            providers[msg.sender].validSubmissions++;
        } else {
            providers[msg.sender].invalidSubmissions++;
        }

        // Обновление репутации
        _updateReputation(msg.sender);

        emit DataSubmitted(msg.sender, poolId, dataHash, isValid);
    }

    /**
     * @dev Обновление репутации провайдера
     */
    function _updateReputation(address provider) internal {
        DataProvider storage p = providers[provider];

        if (p.totalDataSubmitted == 0) return;

        uint256 successRate = (p.validSubmissions * 1000) / p.totalDataSubmitted;
        uint256 oldReputation = p.reputation;

        // Плавное изменение репутации
        if (successRate > p.reputation) {
            p.reputation = p.reputation + ((successRate - p.reputation) / 10);
        } else {
            p.reputation = p.reputation - ((p.reputation - successRate) / 10);
        }

        // Ограничения репутации
        if (p.reputation > 1000) p.reputation = 1000;
        if (p.reputation < 0) p.reputation = 0;

        emit ReputationUpdated(provider, oldReputation, p.reputation);

        // Автоматическое изменение статуса
        if (p.status == ProviderStatus.PROBATIONARY && p.reputation >= 700 && p.totalDataSubmitted >= 100) {
            _changeProviderStatus(provider, ProviderStatus.ACTIVE);
        } else if (p.reputation < 200) {
            _changeProviderStatus(provider, ProviderStatus.SUSPENDED);
        }
    }

    /**
     * @dev Изменение статуса провайдера
     */
    function changeProviderStatus(address provider, ProviderStatus newStatus)
    external
    onlyAdmin
    validProvider(provider)
    {
        _changeProviderStatus(provider, newStatus);
    }

    /**
     * @dev Внутренняя функция изменения статуса
     */
    function _changeProviderStatus(address provider, ProviderStatus newStatus) internal {
        ProviderStatus oldStatus = providers[provider].status;
        providers[provider].status = newStatus;

        emit ProviderStatusChanged(provider, oldStatus, newStatus);
    }

    /**
     * @dev Слэшинг провайдера
     */
    function slashProvider(
        address provider,
        uint256 amount,
        string memory reason
    ) external onlyAdmin validProvider(provider) {
        require(amount <= providers[provider].stake, "Amount exceeds stake");

        providers[provider].stake -= amount;
        providerSlashCount[provider]++;

        // Запись о слэшинге
        slashingRecords[slashingCounter] = SlashingRecord({
            provider: provider,
            amount: amount,
            reason: reason,
            timestamp: block.timestamp,
            slasher: msg.sender
        });
        slashingCounter++;

        // Снижение репутации
        if (providers[provider].reputation > amount / 1e15) {
            providers[provider].reputation -= amount / 1e15;
        } else {
            providers[provider].reputation = 0;
        }

        // Изменение статуса при критическом слэшинге
        if (providerSlashCount[provider] >= 3 || providers[provider].stake == 0) {
            _changeProviderStatus(provider, ProviderStatus.SLASHED);
        }

        emit ProviderSlashed(provider, amount, reason);
    }

    /**
     * @dev Упрощенная проверка подписи
     */
    function _verifySignature(
        bytes32 /* dataHash */,
        bytes memory signature,
        bytes32 publicKey
    ) internal pure returns (bool) {
        // Упрощенная проверка для демо
        // В продакшене должна быть реальная проверка ECDSA
        return signature.length > 0 && publicKey != bytes32(0);
    }

    /**
     * @dev Получение провайдеров пула
     */
    function getPoolProviders(uint256 poolId) external view returns (address[] memory) {
        return poolProviders[poolId];
    }

    /**
     * @dev Получение пулов провайдера
     */
    function getProviderPools(address provider) external view returns (uint256[] memory) {
        return providerPools[provider];
    }

    /**
     * @dev Получение активных провайдеров
     */
    function getActiveProviders() external view returns (address[] memory) {
        uint256 activeCount = 0;

        // Подсчет активных провайдеров
        for (uint256 i = 0; i < allProviders.length; i++) {
            if (providers[allProviders[i]].status == ProviderStatus.ACTIVE) {
                activeCount++;
            }
        }

        address[] memory activeProviders = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allProviders.length; i++) {
            if (providers[allProviders[i]].status == ProviderStatus.ACTIVE) {
                activeProviders[index] = allProviders[i];
                index++;
            }
        }

        return activeProviders;
    }

    /**
     * @dev Получение статистики провайдера
     */
    function getProviderStats(address provider) external view returns (
        uint256 totalSubmissions,
        uint256 validSubmissions,
        uint256 reputation,
        ProviderStatus status,
        uint256 stake
    ) {
        DataProvider memory p = providers[provider];
        return (
            p.totalDataSubmitted,
            p.validSubmissions,
            p.reputation,
            p.status,
            p.stake
        );
    }

    /**
     * @dev Обновление настроек
     */
    function updateSettings(
        uint256 _minimumStake,
        uint256 _maxProviders
    ) external onlyAdmin {
        minimumStake = _minimumStake;
        maxProviders = _maxProviders;
    }

    /**
     * @dev Вывод средств слэшинга
     */
    function withdrawSlashedFunds(uint256 amount) external onlyAdmin {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(admin).transfer(amount);
    }

    /**
     * @dev Получение всех провайдеров
     */
    function getAllProviders() external view returns (address[] memory) {
        return allProviders;
    }
}
