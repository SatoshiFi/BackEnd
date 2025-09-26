// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IPoolMpToken.sol";
import "./calculators/interfaces/IDistributionScheme.sol";
import "./interfaces/IMiningPoolCore.sol";
import "./oracles/StratumDataAggregator.sol";

contract RewardHandler {
    struct RewardUTXO {
        bytes32 txid;
        uint32 vout;
        uint64 amountSat;
        bytes32 blockHash;
        bool isRegistered;
        bool isDistributed;
    }

    mapping(address => mapping(bytes32 => RewardUTXO)) public poolRewards;
    mapping(address => uint256) public poolTotalRewards;

    event RewardRegistered(address indexed pool, bytes32 indexed utxoKey, uint64 amount);
    event RewardsDistributed(address indexed pool, uint256 amount);

    function registerReward(
        bytes32 txid,
        uint32 vout,
        uint64 amountSat,
        bytes32 blockHash,
        address pool
    ) external returns (bytes32) {
        bytes32 utxoKey = keccak256(abi.encodePacked(txid, vout));

        require(!poolRewards[pool][utxoKey].isRegistered, "already registered");

        poolRewards[pool][utxoKey] = RewardUTXO({
            txid: txid,
            vout: vout,
            amountSat: amountSat,
            blockHash: blockHash,
            isRegistered: true,
            isDistributed: false
        });

        poolTotalRewards[pool] += amountSat;

        emit RewardRegistered(pool, utxoKey, amountSat);
        return utxoKey;
    }

    function distributeRewards(
        address pool,
        address calculator,
        address aggregator
    ) external returns (uint256) {
        uint256 totalAmount = poolTotalRewards[pool];
        require(totalAmount > 0, "no rewards");

        // Simplified for now - just mint directly to a single address
        address mpToken = getMpTokenForPool(pool);

        // For simplicity, mint all rewards to the pool address
        if (totalAmount > 0) {
            IPoolMpToken(mpToken).mint(pool, totalAmount);
        }

        poolTotalRewards[pool] = 0;
        emit RewardsDistributed(pool, totalAmount);
        return totalAmount;
    }

    function getMpTokenForPool(address pool) internal view returns (address) {
        // Get MP token from the pool's storage
        // The pool should have poolToken set during creation
        try IMiningPoolCore(pool).poolToken() returns (address token) {
            return token;
        } catch {
            // Fallback - pool might not have the getter
            return address(0);
        }
    }
}