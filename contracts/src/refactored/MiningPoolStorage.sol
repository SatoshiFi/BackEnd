// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MiningPoolStorage
 * @notice Shared storage layout for all MiningPool components using diamond/proxy pattern
 * @dev All implementation contracts must inherit from this to maintain storage compatibility
 */
contract MiningPoolStorage {
    // ===== Storage slot 0-10: Core configuration
    address public spv;
    address public frost;
    address public policy;
    address public poolToken;
    address public multiPoolDAO;
    address public membershipSBT;
    address public roleBadgeSBT;

    // ===== Storage slot 11-20: Oracle & Calculator
    address public calculator;
    uint256 public calculatorId;
    address public calculatorRegistry;
    address public stratumDataAggregator;
    address public stratumDataValidator;
    address public oracleRegistry;

    // ===== Storage slot 21-30: Pool identity
    uint256 public groupPubkeyX;
    uint256 public groupPubkeyY;
    string public poolId;
    string public poolName;
    bytes public payoutScript;
    string public asset;

    // ===== Storage slot 31-50: Pool state
    mapping(address => uint256) public minerShares;
    mapping(address => uint256) public claimedBalance;
    mapping(bytes32 => bool) public registeredRewards;
    mapping(uint256 => address) public participants;
    mapping(address => bool) public isParticipant;
    uint256 public participantCount;
    uint256 public totalDistributed;
    uint256 public totalRewards;
    uint256 public lastDistribution;
    bool public isActive;

    // ===== Storage slot 51-60: Redemption state
    struct Redemption {
        address requester;
        uint64 amountSat;
        bytes btcScript;
        bytes32 txid;
        uint32 vout;
        uint64 createdAt;
        uint64 confirmedAt;
        bool isConfirmed;
        uint8 networkId;
    }

    mapping(uint256 => Redemption) public redemptions;
    uint256 public nextRedemptionId;
    uint256 public redemptionTimeout;
    mapping(bytes32 => bool) public processedRedemptions;

    // ===== Storage slot 61-70: Reward tracking
    struct RewardUTXO {
        bytes32 txid;
        uint32 vout;
        uint64 amountSat;
        bytes32 blockHash;
        uint64 blockHeight;
        bool isRegistered;
        bool isDistributed;
    }

    mapping(bytes32 => RewardUTXO) public rewardUTXOs;
    bytes32[] public rewardUTXOKeys;

    // ===== Storage slot 71-80: Extensions & Governance
    address public governanceIntegrator;
    mapping(bytes32 => bytes) public extensionData;
    mapping(address => mapping(bytes32 => bool)) public userPermissions;

    // ===== Storage slot 81-90: Access control
    mapping(bytes32 => mapping(address => bool)) internal _roles;
    mapping(bytes32 => uint256) internal _roleCount;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CONFIRMER_ROLE = keccak256("CONFIRMER_ROLE");
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    // ===== Storage slot 91-100: SPV per network
    mapping(uint8 => address) public spvContracts;
    mapping(uint8 => bool) public supportedNetworks;

    // ===== Storage slot 101+: Reserved for future upgrades
}