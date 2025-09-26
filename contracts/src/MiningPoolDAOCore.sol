// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ISPVContract.sol";
import "./interfaces/IFROSTCoordinator.sol";
import "./interfaces/IPoolMpToken.sol";

interface IRewardHandler {
    function registerReward(
        bytes32 txid,
        uint32 vout,
        uint64 amount,
        bytes32 blockHash,
        address pool
    ) external returns (bytes32);

    function distributeRewards(
        address pool,
        address calculator,
        address aggregator
    ) external returns (uint256);
}

interface IRedemptionHandler {
    function requestRedemption(
        address requester,
        uint64 amountSat,
        bytes calldata btcScript,
        address pool
    ) external returns (uint256);

    function confirmRedemption(
        uint256 redemptionId,
        bool ok,
        address pool
    ) external;
}

contract MiningPoolDAOCore is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant CONFIRMER_ROLE = keccak256("CONFIRMER_ROLE");

    // Core dependencies
    ISPVContract public spv;
    IFROSTCoordinator public frost;

    // Handler contracts
    address public rewardHandler;
    address public redemptionHandler;

    // Pool configuration
    uint256 public publicKeyX;
    uint256 public publicKeyY;
    bytes public payoutScript;
    string public poolId;
    address public poolToken; // MP token address

    // Registries
    address public calculatorRegistry;
    address public oracleRegistry;
    address public stratumAggregator;
    address public stratumValidator;

    // Events
    event RewardRegistered(bytes32 indexed utxoKey, bytes32 txid, uint32 vout, uint64 amount);
    event RewardsDistributed(uint256 amount);
    event RedemptionRequested(uint256 indexed id, address indexed requester, uint64 amount);

    function initialize(
        address spvAddress,
        address frostAddress,
        address _calculatorRegistry,
        address _stratumAggregator,
        address _stratumValidator,
        address _oracleRegistry,
        uint256 pubX,
        uint256 pubY,
        string calldata _poolId
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(CONFIRMER_ROLE, msg.sender);
        _grantRole(POOL_MANAGER_ROLE, msg.sender);

        require(spvAddress != address(0) && frostAddress != address(0), "zero dep");

        spv = ISPVContract(spvAddress);
        frost = IFROSTCoordinator(frostAddress);
        calculatorRegistry = _calculatorRegistry;
        stratumAggregator = _stratumAggregator;
        stratumValidator = _stratumValidator;
        oracleRegistry = _oracleRegistry;

        publicKeyX = pubX;
        publicKeyY = pubY;
        poolId = _poolId;
    }

    function setHandlers(
        address _rewardHandler,
        address _redemptionHandler
    ) external onlyRole(ADMIN_ROLE) {
        rewardHandler = _rewardHandler;
        redemptionHandler = _redemptionHandler;

        // If pool token is set, grant roles to handlers
        if (poolToken != address(0)) {
            IPoolMpToken(poolToken).grantRole(IPoolMpToken(poolToken).MINTER_ROLE(), _rewardHandler);
            IPoolMpToken(poolToken).grantRole(IPoolMpToken(poolToken).BURNER_ROLE(), _redemptionHandler);
        }
    }

    function setPayoutScript(bytes calldata script) external onlyRole(ADMIN_ROLE) {
        require(script.length > 0 && script.length <= 128, "bad script");
        payoutScript = script;
    }

    function setPoolToken(address token) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "zero token");
        poolToken = token;

        // Grant roles to handlers if they are set
        if (rewardHandler != address(0)) {
            IPoolMpToken(token).grantRole(IPoolMpToken(token).MINTER_ROLE(), rewardHandler);
        }
        if (redemptionHandler != address(0)) {
            IPoolMpToken(token).grantRole(IPoolMpToken(token).BURNER_ROLE(), redemptionHandler);
        }
    }

    // Delegated functions
    function registerRewardStrict(
        bytes32 txid,
        uint32 vout,
        uint64 amountSat,
        bytes32 blockHash,
        bytes calldata rawTx,
        bytes32 merkleRoot,
        bytes32[] calldata siblings,
        uint8[] calldata directions
    ) external onlyRole(POOL_MANAGER_ROLE) returns (bytes32) {
        // SPV verification
        require(spv.checkTxInclusion(blockHash, txid, siblings, directions), "SPV fail");
        require(spv.getBlockInfo(blockHash).exists, "block not found");
        require(spv.isMature(blockHash), "not mature");

        return IRewardHandler(rewardHandler).registerReward(
            txid,
            vout,
            amountSat,
            blockHash,
            address(this)
        );
    }

    function distributeRewardsStrict(
        address calculator
    ) external onlyRole(POOL_MANAGER_ROLE) returns (uint256) {
        return IRewardHandler(rewardHandler).distributeRewards(
            address(this),
            calculator,
            stratumAggregator
        );
    }

    function requestRedemption(
        uint64 amountSat,
        bytes calldata btcScript
    ) external returns (uint256) {
        return IRedemptionHandler(redemptionHandler).requestRedemption(
            msg.sender,
            amountSat,
            btcScript,
            address(this)
        );
    }

    function confirmRedemption(
        uint256 redemptionId,
        bool ok
    ) external onlyRole(CONFIRMER_ROLE) {
        IRedemptionHandler(redemptionHandler).confirmRedemption(
            redemptionId,
            ok,
            address(this)
        );
    }
}
