// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../MiningPoolStorage.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../../interfaces/ISPVContract.sol";
import "../../initialFROST.sol";
import "../../oracles/StratumOracleRegistry.sol";
import "../../calculators/CalculatorRegistry.sol";

/**
 * @title MiningPoolCore
 * @notice Core implementation containing initialization and basic functions
 * @dev Size target: ~10KB
 */
contract MiningPoolCore is MiningPoolStorage, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // Events
    event PoolInitialized(string poolId, uint256 pubX, uint256 pubY);
    event PayoutScriptSet(bytes script);
    event CalculatorSet(uint256 calculatorId, address calculator);
    event ParticipantRegistered(address participant);
    event PoolDeactivated(string reason);
    event PoolReactivated();

    /**
     * @notice Initialize the mining pool
     * @dev This is called once when the pool is created
     */
    function initialize(
        address _spv,
        address _frost,
        address _calculatorRegistry,
        address _stratumAggregator,
        address _stratumValidator,
        address _oracleRegistry,
        uint256 _pubX,
        uint256 _pubY,
        string memory _poolId
    ) external initializer {
        require(_spv != address(0) && _frost != address(0), "Invalid SPV/FROST");
        require(_calculatorRegistry != address(0), "Invalid calculator registry");

        // Initialize AccessControl
        __AccessControl_init();
        __ReentrancyGuard_init();

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(POOL_MANAGER_ROLE, msg.sender);

        // Set core dependencies
        spv = _spv;
        frost = _frost;
        calculatorRegistry = _calculatorRegistry;
        stratumDataAggregator = _stratumAggregator;
        stratumDataValidator = _stratumValidator;
        oracleRegistry = _oracleRegistry;

        // Set pool identity
        groupPubkeyX = _pubX;
        groupPubkeyY = _pubY;
        poolId = _poolId;
        isActive = true;

        emit PoolInitialized(_poolId, _pubX, _pubY);
    }

    /**
     * @notice Set the payout script for Bitcoin rewards
     */
    function setPayoutScript(bytes memory _payoutScript) external onlyRole(ADMIN_ROLE) {
        require(_payoutScript.length > 0, "Empty script");
        payoutScript = _payoutScript;
        emit PayoutScriptSet(_payoutScript);
    }

    /**
     * @notice Set the calculator for reward distribution
     */
    function setCalculator(uint256 _calculatorId) external onlyRole(ADMIN_ROLE) {
        CalculatorRegistry registry = CalculatorRegistry(calculatorRegistry);
        address calc = registry.getCalculator(_calculatorId);
        require(calc != address(0), "Invalid calculator");

        calculator = calc;
        calculatorId = _calculatorId;
        emit CalculatorSet(_calculatorId, calc);
    }

    /**
     * @notice Set the pool token contract
     */
    function setPoolToken(address _poolToken) external onlyRole(ADMIN_ROLE) {
        require(_poolToken != address(0), "Invalid token");
        poolToken = _poolToken;
    }

    /**
     * @notice Set the MultiPoolDAO contract
     */
    function setMultiPoolDAO(address _multiPoolDAO) external onlyRole(ADMIN_ROLE) {
        require(_multiPoolDAO != address(0), "Invalid MultiPoolDAO");
        multiPoolDAO = _multiPoolDAO;
    }

    /**
     * @notice Set policy contract for custom rules
     */
    function setPolicy(address _policy) external onlyRole(ADMIN_ROLE) {
        policy = _policy;
    }

    /**
     * @notice Set membership contracts for NFT integration
     */
    function setMembershipContracts(address _membershipSBT, address _roleBadgeSBT) external onlyRole(ADMIN_ROLE) {
        membershipSBT = _membershipSBT;
        roleBadgeSBT = _roleBadgeSBT;
    }

    /**
     * @notice Register a participant in the pool
     */
    function registerParticipant(address participant) external onlyRole(POOL_MANAGER_ROLE) {
        require(participant != address(0), "Invalid participant");
        require(!isParticipant[participant], "Already registered");

        isParticipant[participant] = true;
        participants[participantCount] = participant;
        participantCount++;

        emit ParticipantRegistered(participant);
    }

    /**
     * @notice Deactivate the pool
     */
    function deactivatePool(string memory reason) external onlyRole(ADMIN_ROLE) {
        require(isActive, "Already inactive");
        isActive = false;
        emit PoolDeactivated(reason);
    }

    /**
     * @notice Reactivate the pool
     */
    function reactivatePool() external onlyRole(ADMIN_ROLE) {
        require(!isActive, "Already active");
        isActive = true;
        emit PoolReactivated();
    }

    /**
     * @notice Set SPV contract for a specific network
     */
    function setSPVContract(uint8 networkId, address _spvContract) external onlyRole(ADMIN_ROLE) {
        require(_spvContract != address(0), "Invalid SPV");
        spvContracts[networkId] = _spvContract;
        supportedNetworks[networkId] = true;
    }

    /**
     * @notice Get SPV contract for a network (default to main SPV if not set)
     */
    function getSPVContract(uint8 networkId) external view returns (address) {
        address networkSpv = spvContracts[networkId];
        return networkSpv != address(0) ? networkSpv : spv;
    }

    /**
     * @notice Check if address has role (for external contracts)
     */
    function hasPoolRole(bytes32 role, address account) external view returns (bool) {
        return hasRole(role, account);
    }

}