// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../calculators/interfaces/IDistributionScheme.sol";
import "../libs/DistributionMath.sol";

/**
 * @title PPSCalculator
 * @dev Pay Per Share - фиксированная выплата за каждую валидную шару
 * Поддерживает как воркеров (WorkerData[]), так и агрегированных DAO-членов (MemberData[]).
 */
contract PPSCalculator is IDistributionScheme {
    using DistributionMath for uint256;

    // ------------------------------------------------------------------------
    // Константы
    // ------------------------------------------------------------------------
    uint256 public constant MIN_BASE_RATE = 1e12;      // 0.000001 ETH за шару
    uint256 public constant MAX_BASE_RATE = 1e18;      // 1 ETH за шару
    uint256 public constant MIN_WORKERS = 1;
    uint256 public constant MAX_WORKERS = 1000;
    uint256 public constant DIFFICULTY_MULTIPLIER = 1e18;

    // ------------------------------------------------------------------------
    // Основная функция расчета PPS для воркеров (legacy)
    // ------------------------------------------------------------------------
    function calculate(
        uint256 totalAmount,
        WorkerData[] memory workers,
        SchemeParams memory params
    ) external pure override returns (
        DistributionResult[] memory results,
        uint256 distributedAmount,
        uint256 remainder
    ) {
        (bool isValid, string memory error) = validateInput(totalAmount, workers, params);
        require(isValid, error);

        uint256 baseRate = params.baseRate > 0 ? params.baseRate : 1e15; // 0.001 ETH по умолчанию
        uint256 totalShares = _calculateTotalSharesWorkers(workers);
        require(totalShares > 0, "No valid shares found");

        uint256 totalRewardByRate = totalShares * baseRate;
        uint256 scalingFactor = DIFFICULTY_MULTIPLIER;
        if (totalRewardByRate > totalAmount) {
            scalingFactor = totalAmount.mulDiv(DIFFICULTY_MULTIPLIER, totalRewardByRate);
        }

        uint256 activeWorkers = _countActiveWorkers(workers);
        results = new DistributionResult[](activeWorkers);

        distributedAmount = _distributeWorkers(
            workers,
            baseRate,
            scalingFactor,
            results
        );
        remainder = totalAmount - distributedAmount;
    }

    // ------------------------------------------------------------------------
    // Новая функция: расчет PPS для членов DAO
    // ------------------------------------------------------------------------
    function calculateForMembers(
        uint256 totalAmount,
        MemberData[] memory members,
        SchemeParams memory params
    ) external pure override returns (
        DistributionResult[] memory results,
        uint256 distributedAmount,
        uint256 remainder
    ) {
        (bool isValid, string memory error) = validateMemberInput(totalAmount, members, params);
        require(isValid, error);

        uint256 baseRate = params.baseRate > 0 ? params.baseRate : 1e15;
        uint256 totalShares = _calculateTotalSharesMembers(members);
        require(totalShares > 0, "No valid shares found");

        uint256 totalRewardByRate = totalShares * baseRate;
        uint256 scalingFactor = DIFFICULTY_MULTIPLIER;
        if (totalRewardByRate > totalAmount) {
            scalingFactor = totalAmount.mulDiv(DIFFICULTY_MULTIPLIER, totalRewardByRate);
        }

        uint256 activeMembers = _countActiveMembers(members);
        results = new DistributionResult[](activeMembers);

        distributedAmount = _distributeMembers(
            members,
            baseRate,
            scalingFactor,
            results
        );
        remainder = totalAmount - distributedAmount;
    }

    // ------------------------------------------------------------------------
    // Helpers: воркеры
    // ------------------------------------------------------------------------
    function _calculateTotalSharesWorkers(
        WorkerData[] memory workers
    ) internal pure returns (uint256 totalShares) {
        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].isActive && workers[i].validShares > 0) {
                totalShares += workers[i].validShares;
            }
        }
    }

    function _countActiveWorkers(
        WorkerData[] memory workers
    ) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].isActive && workers[i].validShares > 0) count++;
        }
    }

    function _distributeWorkers(
        WorkerData[] memory workers,
        uint256 baseRate,
        uint256 scalingFactor,
        DistributionResult[] memory results
    ) internal pure returns (uint256 distributed) {
        uint256 resultIndex = 0;
        uint256 totalShares = _calculateTotalSharesWorkers(workers);

        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].isActive && workers[i].validShares > 0) {
                uint256 baseReward = workers[i].validShares * baseRate;
                uint256 workerReward = baseReward.mulDiv(scalingFactor, DIFFICULTY_MULTIPLIER);
                uint256 percentage = (workers[i].validShares * 10000) / totalShares;

                results[resultIndex] = DistributionResult({
                    recipient: workers[i].payoutAddress,
                    amount: workerReward,
                    workerId: workers[i].workerId,
                    percentage: percentage
                });

                distributed += workerReward;
                resultIndex++;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Helpers: члены DAO
    // ------------------------------------------------------------------------
    function _calculateTotalSharesMembers(
        MemberData[] memory members
    ) internal pure returns (uint256 totalShares) {
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].isActive && members[i].aggregatedValidShares > 0) {
                totalShares += members[i].aggregatedValidShares;
            }
        }
    }

    function _countActiveMembers(
        MemberData[] memory members
    ) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].isActive && members[i].aggregatedValidShares > 0) count++;
        }
    }

    function _distributeMembers(
        MemberData[] memory members,
        uint256 baseRate,
        uint256 scalingFactor,
        DistributionResult[] memory results
    ) internal pure returns (uint256 distributed) {
        uint256 resultIndex = 0;
        uint256 totalShares = _calculateTotalSharesMembers(members);

        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].isActive && members[i].aggregatedValidShares > 0) {
                uint256 baseReward = members[i].aggregatedValidShares * baseRate;
                uint256 reward = baseReward.mulDiv(scalingFactor, DIFFICULTY_MULTIPLIER);
                uint256 percentage = (members[i].aggregatedValidShares * 10000) / totalShares;

                results[resultIndex] = DistributionResult({
                    recipient: members[i].payoutAddress,
                    amount: reward,
                    workerId: "", // пусто для DAO
                    percentage: percentage
                });

                distributed += reward;
                resultIndex++;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Валидация
    // ------------------------------------------------------------------------
    function validateInput(
        uint256 totalAmount,
        WorkerData[] memory workers,
        SchemeParams memory params
    ) public pure override returns (bool, string memory) {
        if (totalAmount == 0) return (false, "Total amount must be positive");
        if (workers.length == 0) return (false, "No workers provided");
        if (workers.length > MAX_WORKERS) return (false, "Too many workers");
        if (params.baseRate > 0 && params.baseRate < MIN_BASE_RATE) return (false, "Base rate too low");
        if (params.baseRate > MAX_BASE_RATE) return (false, "Base rate too high");

        uint256 active;
        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].payoutAddress == address(0)) return (false, "Invalid worker address");
            if (workers[i].isActive && workers[i].validShares > 0) active++;
        }
        if (active == 0) return (false, "No active workers with shares");
        return (true, "");
    }

    function validateMemberInput(
        uint256 totalAmount,
        MemberData[] memory members,
        SchemeParams memory params
    ) public pure override returns (bool, string memory) {
        if (totalAmount == 0) return (false, "Total amount must be positive");
        if (members.length == 0) return (false, "No members provided");
        if (members.length > MAX_WORKERS) return (false, "Too many members");
        if (params.baseRate > 0 && params.baseRate < MIN_BASE_RATE) return (false, "Base rate too low");
        if (params.baseRate > MAX_BASE_RATE) return (false, "Base rate too high");

        uint256 active;
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].payoutAddress == address(0)) return (false, "Invalid member payout address");
            if (members[i].isActive && members[i].aggregatedValidShares > 0) active++;
        }
        if (active == 0) return (false, "No active members with shares");
        return (true, "");
    }

    // ------------------------------------------------------------------------
    // Дополнительные методы
    // ------------------------------------------------------------------------

    /// @notice Оптимальная ставка для воркеров
    function calculateOptimalRate(WorkerData[] memory workers, uint256 targetReward)
        public pure returns (uint256 optimalRate)
    {
        uint256 totalShares = _calculateTotalSharesWorkers(workers);
        require(totalShares > 0, "No shares");
        optimalRate = targetReward / totalShares;
    }

    /// @notice Оптимальная ставка для членов
    function calculateOptimalRateForMembers(MemberData[] memory members, uint256 targetReward)
        public pure returns (uint256 optimalRate)
    {
        uint256 totalShares = _calculateTotalSharesMembers(members);
        require(totalShares > 0, "No shares");
        optimalRate = targetReward / totalShares;
    }

    /// @notice Симуляция распределения при разных ставках (воркеры)
    function simulateRates(WorkerData[] memory workers, uint256[] memory rates)
        public pure returns (uint256[] memory rewards)
    {
        rewards = new uint256[](rates.length);
        for (uint256 i = 0; i < rates.length; i++) {
            rewards[i] = _calculateTotalSharesWorkers(workers) * rates[i];
        }
    }

    /// @notice Симуляция распределения при разных ставках (члены)
    function simulateRatesForMembers(MemberData[] memory members, uint256[] memory rates)
        public pure returns (uint256[] memory rewards)
    {
        rewards = new uint256[](rates.length);
        for (uint256 i = 0; i < rates.length; i++) {
            rewards[i] = _calculateTotalSharesMembers(members) * rates[i];
        }
    }

    /// @notice Расчет риска пула (воркеры)
    function calculatePoolRisk(WorkerData[] memory workers, uint256 difficulty)
        public pure returns (uint256 riskScore)
    {
        uint256 totalShares = _calculateTotalSharesWorkers(workers);
        riskScore = difficulty.mulDiv(1e18, totalShares);
    }

    /// @notice Расчет риска пула (члены)
    function calculatePoolRiskForMembers(MemberData[] memory members, uint256 difficulty)
        public pure returns (uint256 riskScore)
    {
        uint256 totalShares = _calculateTotalSharesMembers(members);
        riskScore = difficulty.mulDiv(1e18, totalShares);
    }

    // ------------------------------------------------------------------------
    // Метаданные
    // ------------------------------------------------------------------------
    function getSchemeInfo() external pure override returns (
        string memory name,
        string memory version,
        string memory description
    ) {
        return ("PPS", "2.0.0", "Pay Per Share - fixed payment per share; supports DAO member aggregation");
    }

    function estimateGas(
        uint256 workerCount,
        SchemeParams memory
    ) external pure override returns (uint256 estimatedGas) {
        if (workerCount == 0) return 45000;
        uint256 baseGas = 45000;
        uint256 perWorkerGas = 4000;
        estimatedGas = baseGas + (workerCount * perWorkerGas);
        if (estimatedGas > 8000000) estimatedGas = 8000000;
    }
}
