// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../calculators/interfaces/IDistributionScheme.sol";
import "../libs/DistributionMath.sol";

/**
 * @title PPLNSCalculator
 * @dev Pay Per Last N Shares - выплаты по последним N шарам
 * Поддерживает как воркеров (WorkerData[]), так и агрегированных DAO-членов (MemberData[]).
 */
contract PPLNSCalculator is IDistributionScheme {

    using DistributionMath for uint256;

    // Константы
    uint256 public constant MIN_WINDOW_SIZE = 100;
    uint256 public constant MAX_WINDOW_SIZE = 1000000;
    uint256 public constant MIN_WORKERS = 1;
    uint256 public constant MAX_WORKERS = 2000;

    // ------------------------------------------------------------------------
    // Основной расчет PPLNS для воркеров (legacy)
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

        uint256 windowSize = params.windowSize > 0 ? params.windowSize : MIN_WINDOW_SIZE;

        uint256 totalShares = _calculateTotalSharesWorkers(workers, windowSize);
        require(totalShares > 0, "No valid shares in window");

        uint256 activeWorkers = _countActiveWorkers(workers, windowSize);
        results = new DistributionResult[](activeWorkers);

        distributedAmount = _distributeWorkers(
            workers,
            totalAmount,
            windowSize,
            totalShares,
            results
        );

        remainder = totalAmount - distributedAmount;
    }

    // ------------------------------------------------------------------------
    // Новый расчет PPLNS для членов DAO
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

        uint256 windowSize = params.windowSize > 0 ? params.windowSize : MIN_WINDOW_SIZE;

        uint256 totalShares = _calculateTotalSharesMembers(members, windowSize);
        require(totalShares > 0, "No valid shares in window");

        uint256 activeMembers = _countActiveMembers(members, windowSize);
        results = new DistributionResult[](activeMembers);

        distributedAmount = _distributeMembers(
            members,
            totalAmount,
            windowSize,
            totalShares,
            results
        );

        remainder = totalAmount - distributedAmount;
    }

    // ------------------------------------------------------------------------
    // Helpers: воркеры
    // ------------------------------------------------------------------------
    function _calculateTotalSharesWorkers(
        WorkerData[] memory workers,
        uint256 windowSize
    ) internal pure returns (uint256 totalShares) {
        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].isActive && workers[i].validShares > 0) {
                uint256 shares = workers[i].validShares > windowSize
                    ? windowSize
                    : workers[i].validShares;
                totalShares += shares;
            }
        }
    }

    function _countActiveWorkers(
        WorkerData[] memory workers,
        uint256 windowSize
    ) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].isActive && workers[i].validShares > 0) {
                count++;
            }
        }
    }

    function _distributeWorkers(
        WorkerData[] memory workers,
        uint256 totalAmount,
        uint256 windowSize,
        uint256 totalShares,
        DistributionResult[] memory results
    ) internal pure returns (uint256 distributed) {
        uint256 idx = 0;
        for (uint256 i = 0; i < workers.length; i++) {
            if (workers[i].isActive && workers[i].validShares > 0) {
                uint256 shares = workers[i].validShares > windowSize
                    ? windowSize
                    : workers[i].validShares;
                uint256 reward = totalAmount.mulDiv(shares, totalShares);
                uint256 percentage = (shares * 10000) / totalShares;

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
    function _calculateTotalSharesMembers(
        MemberData[] memory members,
        uint256 windowSize
    ) internal pure returns (uint256 totalShares) {
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].isActive && members[i].aggregatedValidShares > 0) {
                uint256 shares = members[i].aggregatedValidShares > windowSize
                    ? windowSize
                    : members[i].aggregatedValidShares;
                totalShares += shares;
            }
        }
    }

    function _countActiveMembers(
        MemberData[] memory members,
        uint256 windowSize
    ) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].isActive && members[i].aggregatedValidShares > 0) {
                count++;
            }
        }
    }

    function _distributeMembers(
        MemberData[] memory members,
        uint256 totalAmount,
        uint256 windowSize,
        uint256 totalShares,
        DistributionResult[] memory results
    ) internal pure returns (uint256 distributed) {
        uint256 idx = 0;
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i].isActive && members[i].aggregatedValidShares > 0) {
                uint256 shares = members[i].aggregatedValidShares > windowSize
                    ? windowSize
                    : members[i].aggregatedValidShares;
                uint256 reward = totalAmount.mulDiv(shares, totalShares);
                uint256 percentage = (shares * 10000) / totalShares;

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

        uint256 windowSize = params.windowSize > 0 ? params.windowSize : MIN_WINDOW_SIZE;
        if (windowSize < MIN_WINDOW_SIZE || windowSize > MAX_WINDOW_SIZE)
            return (false, "Invalid window size");

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

        uint256 windowSize = params.windowSize > 0 ? params.windowSize : MIN_WINDOW_SIZE;
        if (windowSize < MIN_WINDOW_SIZE || windowSize > MAX_WINDOW_SIZE)
            return (false, "Invalid window size");

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
        return ("PPLNS", "2.0.0", "Pay Per Last N Shares - rewards based on last N shares; supports DAO member aggregation");
    }

    function estimateGas(
        uint256 workerCount,
        SchemeParams memory
    ) external pure override returns (uint256 estimatedGas) {
        if (workerCount == 0) return 60000;
        uint256 baseGas = 60000;
        uint256 perWorkerGas = 5500;
        estimatedGas = baseGas + (workerCount * perWorkerGas);
        if (estimatedGas > 8000000) estimatedGas = 8000000;
    }
}
