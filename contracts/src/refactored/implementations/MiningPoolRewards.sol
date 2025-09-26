// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../MiningPoolStorage.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../../interfaces/ISPVContract.sol";
import "../../interfaces/IPoolMpToken.sol";
import "../../interfaces/IMultiPoolDAO.sol";
import "../../oracles/StratumDataAggregator.sol";
import "../../oracles/StratumDataValidator.sol";
import "../../calculators/interfaces/IDistributionScheme.sol";
import "../../core/BitcoinTxParser.sol";

/**
 * @title MiningPoolRewards
 * @notice Reward registration and distribution logic
 * @dev Size target: ~12KB
 */
contract MiningPoolRewards is MiningPoolStorage, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using BitcoinTxParser for bytes;

    // Events
    event RewardRegistered(bytes32 indexed utxoKey, uint64 amount, bytes32 blockHash);
    event RewardsDistributed(uint256 totalAmount, uint256 recipientCount);
    event SharesUpdated(address indexed miner, uint256 shares);

    modifier onlyActive() {
        require(isActive, "Pool inactive");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    /**
     * @notice Register a reward UTXO from Bitcoin
     * @param txid Transaction ID
     * @param vout Output index
     * @param amountSat Amount in satoshis
     * @param blockHash Block hash containing the transaction
     * @param blockHeight Block height
     */
    function registerReward(
        bytes32 txid,
        uint32 vout,
        uint64 amountSat,
        bytes32 blockHash,
        uint64 blockHeight
    ) external onlyAdmin onlyActive nonReentrant returns (bytes32) {
        bytes32 utxoKey = keccak256(abi.encodePacked(txid, vout));
        require(!registeredRewards[utxoKey], "Already registered");
        require(amountSat > 0, "Zero amount");

        // Verify with SPV if needed
        ISPVContract spvContract = ISPVContract(spv);
        if (address(spvContract) != address(0)) {
            (bool isInMainchain,) = spvContract.getBlockStatus(blockHash);
            require(isInMainchain, "Block not in mainchain");
        }

        // Store reward UTXO
        rewardUTXOs[utxoKey] = RewardUTXO({
            txid: txid,
            vout: vout,
            amountSat: amountSat,
            blockHash: blockHash,
            blockHeight: blockHeight,
            isRegistered: true,
            isDistributed: false
        });

        rewardUTXOKeys.push(utxoKey);
        registeredRewards[utxoKey] = true;
        totalRewards += amountSat;

        // Notify MultiPoolDAO if configured
        // Note: Simplified version - actual implementation would pass SPV data
        // if (multiPoolDAO != address(0)) {
        //     IMultiPoolDAO(multiPoolDAO).receiveReward(...);
        // }

        emit RewardRegistered(utxoKey, amountSat, blockHash);
        return utxoKey;
    }

    /**
     * @notice Distribute rewards to miners based on calculator logic
     * @param utxoKey The UTXO key to distribute
     */
    function distributeRewards(bytes32 utxoKey) external onlyAdmin onlyActive nonReentrant {
        RewardUTXO storage utxo = rewardUTXOs[utxoKey];
        require(utxo.isRegistered, "UTXO not registered");
        require(!utxo.isDistributed, "Already distributed");

        // Get worker data from oracle
        StratumDataAggregator aggregator = StratumDataAggregator(stratumDataAggregator);
        StratumDataAggregator.WorkerData[] memory workers = aggregator.getWorkerData(address(this));
        require(workers.length > 0, "No workers");

        // Convert to distribution format
        IDistributionScheme.WorkerData[] memory distWorkers = new IDistributionScheme.WorkerData[](workers.length);
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

        // Calculate distribution
        IDistributionScheme scheme = IDistributionScheme(calculator);
        IDistributionScheme.SchemeParams memory params = IDistributionScheme.SchemeParams({
            windowSize: block.timestamp - lastDistribution,
            baseRate: 0,
            difficultyTarget: 0,
            blockReward: utxo.amountSat,
            additionalParams: ""
        });

        (IDistributionScheme.DistributionResult[] memory results, uint256 distributedAmount, ) =
            scheme.calculate(utxo.amountSat, distWorkers, params);

        // Extract addresses and amounts
        address[] memory recipients = new address[](results.length);
        uint256[] memory amounts = new uint256[](results.length);
        for (uint256 i = 0; i < results.length; i++) {
            recipients[i] = results[i].recipient;
            amounts[i] = results[i].amount;
        }

        // Distribute MP tokens
        _distributeTokens(recipients, amounts, utxo.amountSat);

        // Mark as distributed
        utxo.isDistributed = true;
        lastDistribution = block.timestamp;

        emit RewardsDistributed(utxo.amountSat, recipients.length);
    }

    /**
     * @notice Distribute rewards strictly based on existing shares
     */
    function distributeRewardsStrict(uint256 totalAmount) external onlyAdmin onlyActive nonReentrant {
        require(totalAmount > 0, "Zero amount");
        require(participantCount > 0, "No participants");

        uint256 totalShares = 0;
        for (uint256 i = 0; i < participantCount; i++) {
            totalShares += minerShares[participants[i]];
        }
        require(totalShares > 0, "No shares");

        // Distribute proportionally
        for (uint256 i = 0; i < participantCount; i++) {
            address participant = participants[i];
            uint256 shares = minerShares[participant];
            if (shares > 0) {
                uint256 amount = (totalAmount * shares) / totalShares;
                if (amount > 0) {
                    IPoolMpToken(poolToken).mint(participant, amount);
                    totalDistributed += amount;
                    emit SharesUpdated(participant, minerShares[participant] + amount);
                    minerShares[participant] += amount;
                }
            }
        }

        lastDistribution = block.timestamp;
        emit RewardsDistributed(totalAmount, participantCount);
    }

    /**
     * @notice Update miner shares manually
     */
    function updateMinerShares(address miner, uint256 shares) external onlyAdmin {
        require(miner != address(0), "Invalid miner");
        minerShares[miner] = shares;
        emit SharesUpdated(miner, shares);
    }

    /**
     * @notice Claim accumulated balance
     */
    function claimBalance() external nonReentrant {
        uint256 balance = minerShares[msg.sender];
        require(balance > claimedBalance[msg.sender], "Nothing to claim");

        uint256 toClaim = balance - claimedBalance[msg.sender];
        claimedBalance[msg.sender] = balance;

        // Transfer MP tokens
        IPoolMpToken(poolToken).mint(msg.sender, toClaim);

        emit SharesUpdated(msg.sender, balance);
    }

    /**
     * @notice Internal function to distribute tokens
     */
    function _distributeTokens(
        address[] memory recipients,
        uint256[] memory amounts,
        uint256 total
    ) private {
        require(recipients.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < recipients.length; i++) {
            if (amounts[i] > 0) {
                IPoolMpToken(poolToken).mint(recipients[i], amounts[i]);
                minerShares[recipients[i]] += amounts[i];
            }
        }

        totalDistributed += total;
    }

    /**
     * @notice Get pending rewards for a miner
     */
    function getPendingRewards(address miner) external view returns (uint256) {
        return minerShares[miner] - claimedBalance[miner];
    }

    /**
     * @notice Get total undistributed rewards
     */
    function getUndistributedRewards() external view returns (uint256) {
        uint256 undistributed = 0;
        for (uint256 i = 0; i < rewardUTXOKeys.length; i++) {
            RewardUTXO memory utxo = rewardUTXOs[rewardUTXOKeys[i]];
            if (utxo.isRegistered && !utxo.isDistributed) {
                undistributed += utxo.amountSat;
            }
        }
        return undistributed;
    }
}