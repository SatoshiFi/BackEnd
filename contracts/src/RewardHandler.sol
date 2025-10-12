// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IPoolMpToken.sol";
import "./interfaces/ISPVContract.sol";
import "./calculators/interfaces/IDistributionScheme.sol";
import "./interfaces/IMiningPoolCore.sol";
import "./oracles/StratumDataAggregator.sol";

/**
 * @title RewardHandler
 * @notice Обработчик наград с двухэтапным распределением:
 *         1. Mint на pool + расчёт распределения → pending
 *         2. Approve от менеджера → автоматическая рассылка
 */
contract RewardHandler {
    // ========================================
    // СТРУКТУРЫ
    // ========================================

    struct RewardUTXO {
        bytes32 txid;
        uint32 vout;
        uint64 amountSat;
        bytes32 blockHash;
        bool isRegistered;
        bool isDistributed;
    }

    struct PendingDistribution {
        bytes32 utxoKey;
        address pool;
        address aggregator;
        IDistributionScheme.DistributionResult[] results;
        uint256 totalAmount;
        bool isApproved;
        bool isExecuted;
        uint256 createdAt;
    }

    // ========================================
    // СОСТОЯНИЕ
    // ========================================

    mapping(address => mapping(bytes32 => RewardUTXO)) public poolRewards;
    mapping(address => mapping(uint256 => PendingDistribution)) public pendingDistributions;
    mapping(address => uint256) public distributionCounter;
    mapping(address => uint256) public lastDistribution;

    address public immutable spvContract;

    // ========================================
    // СОБЫТИЯ
    // ========================================

    event RewardRegistered(
        address indexed pool,
        bytes32 indexed utxoKey,
        uint64 amount,
        bytes32 blockHash
    );

    event DistributionCalculated(
        address indexed pool,
        bytes32 indexed utxoKey,
        uint256 indexed distributionId,
        uint256 recipientsCount,
        uint256 totalAmount
    );

    event DistributionApproved(
        address indexed pool,
        uint256 indexed distributionId
    );

    event RewardsDistributed(
        address indexed pool,
        bytes32 indexed utxoKey,
        uint256 distributedAmount,
        uint256 recipients
    );

    event RewardToRecipient(
        address indexed pool,
        address indexed recipient,
        uint256 amount
    );

    // ========================================
    // КОНСТРУКТОР
    // ========================================

    constructor(address _spvContract) {
        require(_spvContract != address(0), "Invalid SPV contract");
        spvContract = _spvContract;
    }

    // ========================================
    // РЕГИСТРАЦИЯ НАГРАДЫ
    // ========================================

    function registerReward(
        bytes32 txid,
        uint32 vout,
        uint64 amountSat,
        bytes32 blockHash,
        address pool
    ) external returns (bytes32) {
        bytes32 utxoKey = keccak256(abi.encodePacked(txid, vout));

        require(!poolRewards[pool][utxoKey].isRegistered, "already registered");
        require(amountSat > 0, "zero amount");
        require(blockHash != bytes32(0), "invalid block hash");

        poolRewards[pool][utxoKey] = RewardUTXO({
            txid: txid,
            vout: vout,
            amountSat: amountSat,
            blockHash: blockHash,
            isRegistered: true,
            isDistributed: false
        });

        emit RewardRegistered(pool, utxoKey, amountSat, blockHash);
        return utxoKey;
    }

    // ========================================
    // РАСПРЕДЕЛЕНИЕ НАГРАД (ШАГ 1: MINT + РАСЧЁТ)
    // ========================================

    function distributeRewards(
        bytes32 utxoKey,
        address pool,
        address calculator,
        address aggregator
    ) external returns (uint256) {
        // ВАЛИДАЦИЯ
        RewardUTXO storage utxo = poolRewards[pool][utxoKey];
        require(utxo.isRegistered, "UTXO not registered");
        require(!utxo.isDistributed, "Already distributed");
        require(calculator != address(0), "Invalid calculator");
        require(aggregator != address(0), "Invalid aggregator");

        // ПРОВЕРКА МАТЮРНОСТИ (100 ПОДТВЕРЖДЕНИЙ)
        ISPVContract spv = ISPVContract(spvContract);
        require(
            spv.isMature(utxo.blockHash),
                "Block not mature (need 100 confirmations)"
        );

        // ПОЛУЧЕНИЕ ДАННЫХ ВОРКЕРОВ
        StratumDataAggregator aggregatorContract = StratumDataAggregator(aggregator);
        StratumDataAggregator.WorkerData[] memory workers =
        aggregatorContract.getWorkerData(pool);

        require(workers.length > 0, "No workers in pool");

        // КОНВЕРТАЦИЯ В ФОРМАТ CALCULATOR
        IDistributionScheme.WorkerData[] memory distWorkers =
        new IDistributionScheme.WorkerData[](workers.length);

        for (uint256 i = 0; i < workers.length; i++) {
            distWorkers[i] = IDistributionScheme.WorkerData({
                workerId: "",
                payoutAddress: workers[i].workerAddress,
                owner: address(0),
                                                            validShares: workers[i].validShares,
                                                            totalShares: workers[i].totalShares,
                                                            lastActivity: workers[i].lastSubmission,
                                                            hashRate: 0,
                                                            isActive: workers[i].isActive
            });
        }

        // РАСЧЁТ ЧЕРЕЗ CALCULATOR
        IDistributionScheme scheme = IDistributionScheme(calculator);

        IDistributionScheme.SchemeParams memory params = IDistributionScheme.SchemeParams({
            windowSize: block.timestamp - lastDistribution[pool],
            baseRate: 0,
            difficultyTarget: 0,
            blockReward: utxo.amountSat,
            additionalParams: ""
        });

        (
            IDistributionScheme.DistributionResult[] memory results,
         uint256 distributedAmount,
         /* uint256 remainder */
        ) = scheme.calculate(utxo.amountSat, distWorkers, params);

        require(results.length > 0, "No distribution results");
        require(distributedAmount > 0, "Nothing to distribute");

        // MINT НА ПУЛ (НЕ НА МАЙНЕРОВ!)
        address mpToken = getMpTokenForPool(pool);
        require(mpToken != address(0), "MP token not set");

        IPoolMpToken(mpToken).mint(pool, distributedAmount);

        // СОЗДАТЬ PENDING DISTRIBUTION
        uint256 distId = distributionCounter[pool]++;
        PendingDistribution storage pending = pendingDistributions[pool][distId];

        pending.utxoKey = utxoKey;
        pending.pool = pool;
        pending.aggregator = aggregator;
        pending.totalAmount = distributedAmount;
        pending.isApproved = false;
        pending.isExecuted = false;
        pending.createdAt = block.timestamp;

        // Копируем results в storage
        for (uint256 i = 0; i < results.length; i++) {
            pending.results.push(results[i]);
        }

        emit DistributionCalculated(pool, utxoKey, distId, results.length, distributedAmount);

        return distributedAmount;
    }

    // ========================================
    // APPROVE DISTRIBUTION (ШАГ 2: ОДОБРЕНИЕ)
    // ========================================

    function approveDistribution(
        address pool,
        uint256 distributionId
    ) external {
        // Только pool контракт может вызвать
        require(msg.sender == pool, "only pool");

        PendingDistribution storage dist = pendingDistributions[pool][distributionId];
        require(dist.totalAmount > 0, "distribution not found");
        require(!dist.isApproved, "already approved");
        require(!dist.isExecuted, "already executed");

        dist.isApproved = true;

        emit DistributionApproved(pool, distributionId);

        // Автоматически выполнить рассылку
        _executeDistribution(pool, distributionId);
    }

    // ========================================
    // EXECUTE DISTRIBUTION (ШАГ 3: РАССЫЛКА)
    // ========================================

    function _executeDistribution(
        address pool,
        uint256 distributionId
    ) internal {
        PendingDistribution storage dist = pendingDistributions[pool][distributionId];
        require(dist.isApproved, "not approved");
        require(!dist.isExecuted, "already executed");

        address mpToken = getMpTokenForPool(pool);
        uint256 totalDistributed = 0;

        // ПРИМЕНИТЬ MAPPING ВОРКЕР → МАЙНЕР + РАССЫЛКА
        for (uint256 i = 0; i < dist.results.length; i++) {
            address recipient = dist.results[i].recipient;
            uint256 amount = dist.results[i].amount;

            if (amount > 0) {
                // Проверить workerOwner
                address owner = StratumDataAggregator(dist.aggregator).workerOwner(recipient);
                if (owner != address(0)) {
                    recipient = owner; // Заменяем воркера на владельца
                }

                // transferFrom требует approve от pool
                IPoolMpToken(mpToken).transferFrom(pool, recipient, amount);

                totalDistributed += amount;
                emit RewardToRecipient(pool, recipient, amount);
            }
        }

        // Обновить статус
        dist.isExecuted = true;
        poolRewards[pool][dist.utxoKey].isDistributed = true;
        lastDistribution[pool] = block.timestamp;

        emit RewardsDistributed(pool, dist.utxoKey, totalDistributed, dist.results.length);
    }

    // ========================================
    // VIEW ФУНКЦИИ
    // ========================================

    function getMpTokenForPool(address pool) internal view returns (address) {
        try IMiningPoolCore(pool).poolToken() returns (address token) {
            return token;
        } catch {
            return address(0);
        }
    }

    function getRewardInfo(address pool, bytes32 utxoKey)
    external
    view
    returns (RewardUTXO memory)
    {
        return poolRewards[pool][utxoKey];
    }

    function getPendingDistribution(
        address pool,
        uint256 distributionId
    ) external view returns (
        bytes32 utxoKey,
        uint256 totalAmount,
        uint256 recipientsCount,
        bool isApproved,
        bool isExecuted,
        uint256 createdAt
    ) {
        PendingDistribution storage dist = pendingDistributions[pool][distributionId];
        return (
            dist.utxoKey,
            dist.totalAmount,
            dist.results.length,
            dist.isApproved,
            dist.isExecuted,
            dist.createdAt
        );
    }

    function getDistributionRecipients(
        address pool,
        uint256 distributionId
    ) external view returns (IDistributionScheme.DistributionResult[] memory) {
        return pendingDistributions[pool][distributionId].results;
    }

    function isReadyToDistribute(address pool, bytes32 utxoKey)
    external
    view
    returns (bool)
    {
        RewardUTXO memory utxo = poolRewards[pool][utxoKey];

        if (!utxo.isRegistered) return false;
        if (utxo.isDistributed) return false;

        ISPVContract spv = ISPVContract(spvContract);
        return spv.isMature(utxo.blockHash);
    }

    function getConfirmations(bytes32 blockHash)
    external
    view
    returns (uint256 confirmations)
    {
        ISPVContract spv = ISPVContract(spvContract);

        try spv.getBlockInfo(blockHash) returns (ISPVContract.BlockInfo memory blockInfo) {
            if (!blockInfo.exists) return 0;

            uint64 currentHeight = spv.getMainchainHeight();
            uint64 blockHeight = blockInfo.mainBlockData.blockHeight;

            if (currentHeight >= blockHeight) {
                return uint256(currentHeight - blockHeight);
            }
            return 0;
        } catch {
            return 0;
        }
    }

    function getPendingDistributionsCount(address pool) external view returns (uint256) {
        return distributionCounter[pool];
    }
}
