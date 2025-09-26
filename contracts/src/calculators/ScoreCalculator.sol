// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../calculators/interfaces/IDistributionScheme.sol";
import "../libs/DistributionMath.sol";

/**
 * @title ScoreCalculator
 * @dev Схема распределения на основе скоринга: учитывает не только количество шар,
 *      но и время активности. Используется модель экспоненциального decay.
 * Поддерживает как воркеров (WorkerData[]), так и агрегированных DAO-членов (MemberData[]).
 */
contract ScoreCalculator is IDistributionScheme {

    using DistributionMath for uint256;

    // Константы
    uint256 public constant MIN_DECAY_FACTOR = 1e15;   // 0.001
    uint256 public constant MAX_DECAY_FACTOR = 1e18;   // 1.0
    uint256 public constant DEFAULT_DECAY_FACTOR = 95e16; // 0.95
    uint256 public constant MIN_WORKERS = 1;
    uint256 public constant MAX_WORKERS = 2000;

    // ------------------------------------------------------------------------
    // Основной расчет Score для воркеров (legacy)
    // ------------------------------------------------------------------------
    function calculate(
        uint256 totalAmount,
        WorkerData[] memory workers,
        SchemeParams memory params
    ) external view override returns (
        DistributionResult[] memory results,
        uint256 distributedAmount,
        uint256 remainder
    ) {
        (bool isValid, string memory error) = validateInput(totalAmount, workers, params);
        require(isValid, error);

        uint256 decayFactor = params.baseRate > 0 ? params.baseRate : DEFAULT_DECAY_FACTOR;

        uint256 totalScore = _calculateTotalScoreWorkers(workers, decayFactor);
        require(totalScore > 0, "No valid score");

        uint256 activeWorkers = _countActiveWorkers(workers);
        results = new DistributionResult[](activeWorkers);

        distributedAmount = _distributeWorkers(
            workers,
            totalAmount,
            totalScore,
            decayFactor,
            results
        );

        remainder = totalAmount - distributedAmount;
    }

    // ------------------------------------------------------------------------
    // Новый расчет Score для членов DAO
    // ------------------------------------------------------------------------
    function calculateForMembers(
        uint256 totalAmount,
        MemberData[] memory members,
        SchemeParams memory params
    ) external view override returns (
        DistributionResult[] memory results,
        uint256 distributedAmount,
        uint256 remainder
    ) {
        (bool isValid, string memory error) = validateMemberInput(totalAmount, members, params);
        require(isValid, error);

        uint256 decayFactor = params.baseRate > 0 ? params.baseRate : DEFAULT_DECAY_FACTOR;

        uint256 totalScore = _calculateTotalScoreMembers(members, decayFactor);
        require(totalScore > 0, "No valid score");

        uint256 activeMembers = _countActiveMembers(members);
        results = new DistributionResult[](activeMembers);

        distributedAmount = _distributeMembers(
            members,
            totalAmount,
            totalScore,
            decayFactor,
            results
        );

        remainder = totalAmount - distributedAmount;
    }

    // ------------------------------------------------------------------------
    // Helpers: воркеры
    // ------------------------------------------------------------------------
    function _calculateScoreWorker(
        WorkerData memory worker,
        uint256 decayFactor
    ) internal view returns (uint256) {
        if (!worker.isActive || worker.validShares == 0) return 0;
        uint256 timeFactor = block.timestamp - worker.lastActivity;
        uint256 decay = _applyDecay(timeFactor, decayFactor);
        return worker.validShares.mulDiv(decay, 1e18);
    }

    function _calculateTotalScoreWorkers(
        WorkerData[] memory workers,
        uint256 decayFactor
    ) internal view returns (uint256 totalScore) {
        for (uint256 i = 0; i < workers.length; i++) {
            totalScore += _calculateScoreWorker(workers[i], decayFactor);
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
        uint256 totalAmount,
        uint256 totalScore,
        uint256 decayFactor,
        DistributionResult[] memory results
    ) internal view returns (uint256 distributed) {
        uint256 idx = 0;
        for (uint256 i = 0; i < workers.length; i++) {
            uint256 score = _calculateScoreWorker(workers[i], decayFactor);
            if (score > 0) {
                uint256 reward = totalAmount.mulDiv(score, totalScore);
                uint256 percentage = (score * 10000) / totalScore;

                results[idx] = DistributionResult({
                    recipient: workers[i].payoutAddress,
                    amount: reward,
                    workerId: workers[i].workerId,
                    percentage: percentage
                });

                distributed += reward;
                idx++;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Helpers: члены DAO
    // ------------------------------------------------------------------------
    function _calculateScoreMember(
        MemberData memory member,
        uint256 decayFactor
    ) internal view returns (uint256) {
        if (!member.isActive || member.aggregatedValidShares == 0) return 0;
        uint256 timeFactor = block.timestamp - member.lastActivity;
        uint256 decay = _applyDecay(timeFactor, decayFactor);
        return member.aggregatedValidShares.mulDiv(decay, 1e18);
    }

    function _calculateTotalScoreMembers(
        MemberData[] memory members,
        uint256 decayFactor
    ) internal view returns (uint256 totalScore) {
        for (uint256 i = 0; i < members.length; i++) {
            totalScore += _calculateScoreMember(members[i], decayFactor);
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
        uint256 totalAmount,
        uint256 totalScore,
        uint256 decayFactor,
        DistributionResult[] memory results
    ) internal view returns (uint256 distributed) {
        uint256 idx = 0;
        for (uint256 i = 0; i < members.length; i++) {
            uint256 score = _calculateScoreMember(members[i], decayFactor);
            if (score > 0) {
                uint256 reward = totalAmount.mulDiv(score, totalScore);
                uint256 percentage = (score * 10000) / totalScore;

                results[idx] = DistributionResult({
                    recipient: members[i].payoutAddress,
                    amount: reward,
                    workerId: "",
                    percentage: percentage
                });

                distributed += reward;
                idx++;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Общие хелперы
    // ------------------------------------------------------------------------
    function _applyDecay(uint256 timeElapsed, uint256 decayFactor) internal pure returns (uint256) {
        // Простая модель: decayFactor^(timeElapsed/60)
        // где timeElapsed в секундах, каждая минута уменьшает вклад
        uint256 minutesPassed = timeElapsed / 60;
        if (minutesPassed == 0) return 1e18;

        uint256 result = 1e18;
        for (uint256 i = 0; i < minutesPassed; i++) {
            result = result.mulDiv(decayFactor, 1e18);
            if (result == 0) break;
        }
        return result;
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
        if (params.baseRate < MIN_DECAY_FACTOR || params.baseRate > MAX_DECAY_FACTOR)
            return (false, "Invalid decay factor");

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
        if (params.baseRate < MIN_DECAY_FACTOR || params.baseRate > MAX_DECAY_FACTOR)
            return (false, "Invalid decay factor");

        uint256 active;
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].payoutAddress == address(0)) return (false, "Invalid member payout address");
            if (members[i].isActive && members[i].aggregatedValidShares > 0) active++;
        }
        if (active == 0) return (false, "No active members with shares");
        return (true, "");
    }

    // ------------------------------------------------------------------------
    // Метаданные
    // ------------------------------------------------------------------------
    function getSchemeInfo() external pure override returns (
        string memory name,
        string memory version,
        string memory description
    ) {
        return ("Score", "2.0.1", "Score-based distribution with exponential decay; supports DAO member aggregation");
    }

    function estimateGas(
        uint256 workerCount,
        SchemeParams memory
    ) external pure override returns (uint256 estimatedGas) {
        if (workerCount == 0) return 70000;
        uint256 baseGas = 70000;
        uint256 perWorkerGas = 7000;
        estimatedGas = baseGas + (workerCount * perWorkerGas);
        if (estimatedGas > 8000000) estimatedGas = 8000000;
    }
}
