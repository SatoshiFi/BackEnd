// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../calculators/interfaces/IDistributionScheme.sol";
import "../libs/DistributionMath.sol";

/**
 * @title FPPSCalculator
 * @dev Full Pay Per Share - PPS плюс доля от комиссий транзакций
 * Поддерживает как воркеров (WorkerData[]), так и агрегированных DAO-членов (MemberData[]).
 */
contract FPPSCalculator is IDistributionScheme {

    using DistributionMath for uint256;

    // Константы
    uint256 public constant MIN_BASE_RATE = 1e12;
    uint256 public constant MAX_BASE_RATE = 1e18;
    uint256 public constant MIN_WORKERS = 1;
    uint256 public constant MAX_WORKERS = 1000;
    uint256 public constant MAX_FEE_BONUS = 5000;  // максимум 50% бонуса от комиссий
    uint256 public constant DIFFICULTY_MULTIPLIER = 1e18;

    // ------------------------------------------------------------------------
    // Основной расчет FPPS для воркеров (legacy)
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

        uint256 baseRate = params.baseRate == 0 ? 1e15 : params.baseRate;
        uint256 blockReward = params.blockReward == 0 ? totalAmount * 9500 / 10000 : params.blockReward;

        (uint256 basePPSAmount, uint256 feeBonus) = _calculateAmounts(totalAmount, blockReward);

        uint256 totalShares = _calculateTotalSharesWorkers(workers);
        require(totalShares > 0, "No valid shares found");

        uint256 activeWorkers = _countActiveWorkers(workers);
        results = new DistributionResult[](activeWorkers);

        distributedAmount = _distributeWorkers(
            workers,
            baseRate,
            basePPSAmount,
            feeBonus,
            totalShares,
            results
        );

        remainder = totalAmount - distributedAmount;
    }

    // ------------------------------------------------------------------------
    // Новый расчет FPPS для членов DAO
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

        uint256 baseRate = params.baseRate == 0 ? 1e15 : params.baseRate;
        uint256 blockReward = params.blockReward == 0 ? totalAmount * 9500 / 10000 : params.blockReward;

        (uint256 basePPSAmount, uint256 feeBonus) = _calculateAmounts(totalAmount, blockReward);

        uint256 totalShares = _calculateTotalSharesMembers(members);
        require(totalShares > 0, "No valid shares found");

        uint256 activeMembers = _countActiveMembers(members);
        results = new DistributionResult[](activeMembers);

        distributedAmount = _distributeMembers(
            members,
            baseRate,
            basePPSAmount,
            feeBonus,
            totalShares,
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
        uint256 basePPSAmount,
        uint256 feeBonus,
        uint256 totalShares,
        DistributionResult[] memory results
    ) internal pure returns (uint256 distributed) {
        uint256 idx = 0;
        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].isActive && workers[i].validShares > 0) {
                uint256 baseReward = _calculateBasePPS(
                    workers[i].validShares,
                    baseRate,
                    basePPSAmount,
                    totalShares
                );
                uint256 bonusReward = feeBonus.mulDiv(workers[i].validShares, totalShares);
                uint256 totalReward = baseReward + bonusReward;
                uint256 percentage = (workers[i].validShares * 10000) / totalShares;

                results[idx] = DistributionResult({
                    recipient: workers[i].payoutAddress,
                    amount: totalReward,
                    workerId: workers[i].workerId,
                    percentage: percentage
                });

                distributed += totalReward;
                idx++;
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
        uint256 basePPSAmount,
        uint256 feeBonus,
        uint256 totalShares,
        DistributionResult[] memory results
    ) internal pure returns (uint256 distributed) {
        uint256 idx = 0;
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].isActive && members[i].aggregatedValidShares > 0) {
                uint256 baseReward = _calculateBasePPS(
                    members[i].aggregatedValidShares,
                    baseRate,
                    basePPSAmount,
                    totalShares
                );
                uint256 bonusReward = feeBonus.mulDiv(members[i].aggregatedValidShares, totalShares);
                uint256 totalReward = baseReward + bonusReward;
                uint256 percentage = (members[i].aggregatedValidShares * 10000) / totalShares;

                results[idx] = DistributionResult({
                    recipient: members[i].payoutAddress,
                    amount: totalReward,
                    workerId: "", // нет ID воркера
                    percentage: percentage
                });

                distributed += totalReward;
                idx++;
            }
        }
    }

    // ------------------------------------------------------------------------
    // Общие хелперы
    // ------------------------------------------------------------------------
    function _calculateAmounts(
        uint256 totalAmount,
        uint256 blockReward
    ) internal pure returns (uint256 basePPSAmount, uint256 feeBonus) {
        if (blockReward >= totalAmount) {
            basePPSAmount = totalAmount;
            feeBonus = 0;
        } else {
            basePPSAmount = blockReward;
            feeBonus = totalAmount - blockReward;
        }
    }

    function _calculateBasePPS(
        uint256 shares,
        uint256 baseRate,
        uint256 basePPSAmount,
        uint256 totalShares
    ) internal pure returns (uint256 baseReward) {
        uint256 theoreticalReward = shares * baseRate;
        uint256 proportionalReward = basePPSAmount.mulDiv(shares, totalShares);
        baseReward = theoreticalReward < proportionalReward ? theoreticalReward : proportionalReward;
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
        if (params.blockReward > totalAmount) return (false, "Block reward exceeds total amount");

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
        if (params.blockReward > totalAmount) return (false, "Block reward exceeds total amount");

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
        return ("FPPS", "2.0.0", "Full Pay Per Share - PPS plus proportional share of transaction fees; supports DAO member aggregation");
    }

    function estimateGas(
        uint256 workerCount,
        SchemeParams memory
    ) external pure override returns (uint256 estimatedGas) {
        if (workerCount == 0) return 55000;
        uint256 baseGas = 55000;
        uint256 perWorkerGas = 6000;
        estimatedGas = baseGas + (workerCount * perWorkerGas);
        if (estimatedGas > 8000000) estimatedGas = 8000000;
    }
}
