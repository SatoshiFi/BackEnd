// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IFROSTCoordinator.sol";
import "./interfaces/IMiningPoolCore.sol";
import "./FrostSessionReader.sol";

/**
 * @title GovernanceIntegrator
 * @notice Middleware contract for setting up and managing FROST governance in mining pools
 * @dev Bridges FROST coordinator with mining pool governance systems
 */
contract GovernanceIntegrator is AccessControl {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant POOL_FACTORY_ROLE = keccak256("POOL_FACTORY_ROLE");

    struct PoolGovernanceConfig {
        uint256 frostSessionId;
        uint256 threshold;
        uint256 totalCustodians;
        address[] custodians;
        uint256 groupPubkeyX;
        uint256 groupPubkeyY;
        bool isActive;
        uint256 configuredAt;
    }

    FrostSessionReader public immutable frostReader;
    IFROSTCoordinator public immutable frostCoordinator;

    // Pool address => governance configuration
    mapping(address => PoolGovernanceConfig) public poolGovernance;

    // Custodian => pools they participate in
    mapping(address => address[]) public custodianPools;

    // Pool => custodian => is registered
    mapping(address => mapping(address => bool)) public isPoolCustodian;

    error InvalidPool();
    error InvalidSession();
    error SessionNotFinalized();
    error CustodianAlreadyRegistered();
    error NotPoolCustodian();
    error GovernanceNotConfigured();
    error InvalidThreshold();

    event GovernanceConfigured(
        address indexed poolCore,
        uint256 indexed sessionId,
        uint256 threshold,
        uint256 custodianCount
    );

    event CustodianRegistered(address indexed poolCore, address indexed custodian);
    event CustodianRemoved(address indexed poolCore, address indexed custodian);
    event GovernanceDeactivated(address indexed poolCore);

    constructor(address _frostReader, address _frostCoordinator) {
        require(_frostReader != address(0), "frostReader=0");
        require(_frostCoordinator != address(0), "frostCoordinator=0");

        frostReader = FrostSessionReader(_frostReader);
        frostCoordinator = IFROSTCoordinator(_frostCoordinator);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Setup FROST governance for a newly created mining pool
     * @param poolCore Address of the mining pool core contract
     * @param sessionId FROST DKG session ID
     */
    function setupFrostGovernance(
        address poolCore,
        uint256 sessionId
    ) external onlyRole(POOL_FACTORY_ROLE) {
        require(poolCore != address(0), "poolCore=0");
        require(poolGovernance[poolCore].configuredAt == 0, "already configured");

        // Validate and extract FROST session data
        FrostSessionReader.FrostSessionData memory sessionData = frostReader.getFrostSessionData(sessionId);
        require(sessionData.isValid && sessionData.isSuccessful, "invalid session");
        require(sessionData.participants.length >= 2, "insufficient participants");

        // Configure governance
        PoolGovernanceConfig storage config = poolGovernance[poolCore];
        config.frostSessionId = sessionId;
        config.threshold = sessionData.threshold;
        config.totalCustodians = sessionData.participants.length;
        config.custodians = sessionData.participants;
        config.groupPubkeyX = sessionData.groupPubkeyX;
        config.groupPubkeyY = sessionData.groupPubkeyY;
        config.isActive = true;
        config.configuredAt = block.timestamp;

        // Register custodians
        for (uint i = 0; i < sessionData.participants.length; i++) {
            address custodian = sessionData.participants[i];
            isPoolCustodian[poolCore][custodian] = true;
            custodianPools[custodian].push(poolCore);

            // NOTE: Removed addCustodian call as it doesn't exist in IFROSTCoordinator
            // Custodians are managed through FROST sessions directly

            emit CustodianRegistered(poolCore, custodian);
        }

        emit GovernanceConfigured(poolCore, sessionId, sessionData.threshold, sessionData.participants.length);
    }

    /**
     * @notice Validate if an action can be executed with FROST governance
     * @param poolCore Pool address
     * @param actionData Encoded action data
     * @param requiredCustodians Custodians required for this action
     * @return isValid True if action meets governance requirements
     */
    function validateFrostAction(
        address poolCore,
        bytes calldata actionData,
        address[] calldata requiredCustodians
    ) external view returns (bool isValid) {
        PoolGovernanceConfig storage config = poolGovernance[poolCore];
        if (!config.isActive) return false;

        // Check if we have enough custodians
        if (requiredCustodians.length < config.threshold) return false;

        // Verify all provided custodians are valid for this pool
        for (uint i = 0; i < requiredCustodians.length; i++) {
            if (!isPoolCustodian[poolCore][requiredCustodians[i]]) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Get governance configuration for a pool
     * @param poolCore Pool address
     * @return config Complete governance configuration
     */
    function getPoolGovernance(address poolCore) external view returns (PoolGovernanceConfig memory config) {
        return poolGovernance[poolCore];
    }

    /**
     * @notice Get list of custodians for a pool
     * @param poolCore Pool address
     * @return custodians Array of custodian addresses
     */
    function getPoolCustodians(address poolCore) external view returns (address[] memory custodians) {
        return poolGovernance[poolCore].custodians;
    }

    /**
     * @notice Get list of pools where address is a custodian
     * @param custodian Custodian address
     * @return pools Array of pool addresses
     */
    function getCustodianPools(address custodian) external view returns (address[] memory pools) {
        return custodianPools[custodian];
    }

    /**
     * @notice Check if address is custodian for specific pool
     * @param poolCore Pool address
     * @param custodian Address to check
     * @return isCustodian True if address is pool custodian
     */
    function isCustodianForPool(address poolCore, address custodian) external view returns (bool isCustodian) {
        return isPoolCustodian[poolCore][custodian];
    }

    /**
     * @notice Get governance threshold for pool
     * @param poolCore Pool address
     * @return threshold Minimum custodians required for actions
     * @return total Total number of custodians
     */
    function getPoolThreshold(address poolCore) external view returns (uint256 threshold, uint256 total) {
        PoolGovernanceConfig storage config = poolGovernance[poolCore];
        return (config.threshold, config.totalCustodians);
    }

    /**
     * @notice Emergency function to deactivate pool governance
     * @param poolCore Pool address
     * @dev Only admin can deactivate governance in emergency situations
     */
    function deactivateGovernance(address poolCore) external onlyRole(ADMIN_ROLE) {
        require(poolGovernance[poolCore].isActive, "not active");
        poolGovernance[poolCore].isActive = false;
        emit GovernanceDeactivated(poolCore);
    }

    /**
     * @notice Update threshold for existing pool governance
     * @param poolCore Pool address
     * @param newThreshold New threshold value
     * @dev Requires consensus from current custodians (simplified for now)
     */
    function updateThreshold(
        address poolCore,
        uint256 newThreshold
    ) external onlyRole(ADMIN_ROLE) {
        PoolGovernanceConfig storage config = poolGovernance[poolCore];
        require(config.isActive, "governance not active");
        require(newThreshold > 0 && newThreshold <= config.totalCustodians, "invalid threshold");

        config.threshold = newThreshold;
        emit GovernanceConfigured(poolCore, config.frostSessionId, newThreshold, config.totalCustodians);
    }
}
