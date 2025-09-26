// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Minimal interfaces
interface IPoolDeployer {
    function deployPool(
        address spv,
        address frost,
        address calculator,
        address aggregator,
        address validator,
        address oracleRegistry,
        address tokenFactory,
        address multiPoolDAO,
        bytes calldata params
    ) external returns (address pool, address mpToken);
}

contract MiningPoolFactoryCore is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant POOL_MANAGER_ROLE = keccak256("POOL_MANAGER_ROLE");

    struct PoolParams {
        string asset;
        string poolId;
        uint256 pubX;
        uint256 pubY;
        string mpName;
        string mpSymbol;
        bool restrictedMp;
        bytes payoutScript;
        uint256 calculatorId;
    }

    struct PoolInfo {
        address poolCore;
        address mpToken;
        string poolId;
        bool isActive;
        uint256 createdAt;
        address creator;
    }

    // Dependencies
    address public spvContract;
    address public frostCoordinator;
    address public calculatorRegistry;
    address public stratumDataAggregator;
    address public stratumDataValidator;
    address public oracleRegistry;
    address public poolTokenFactory;
    address public multiPoolDAO;
    address public poolDeployer;

    // Storage
    mapping(string => address) public poolsByAsset;
    mapping(address => bool) public isValidPool;
    mapping(address => PoolInfo) public poolsInfo;
    address[] public allPools;

    event PoolCreated(
        address indexed poolCore,
        address indexed mpToken,
        string asset,
        string poolId,
        address creator
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function setDependencies(
        address _spv,
        address _frost,
        address _calcRegistry,
        address _aggregator,
        address _validator,
        address _oracleRegistry,
        address _tokenFactory,
        address _multiPoolDAO
    ) external onlyRole(ADMIN_ROLE) {
        spvContract = _spv;
        frostCoordinator = _frost;
        calculatorRegistry = _calcRegistry;
        stratumDataAggregator = _aggregator;
        stratumDataValidator = _validator;
        oracleRegistry = _oracleRegistry;
        poolTokenFactory = _tokenFactory;
        multiPoolDAO = _multiPoolDAO;
    }

    function setPoolDeployer(address _deployer) external onlyRole(ADMIN_ROLE) {
        poolDeployer = _deployer;
    }

    function createPool(PoolParams calldata params)
        external
        nonReentrant
        onlyRole(POOL_MANAGER_ROLE)
        returns (address poolAddress, address mpTokenAddress)
    {
        require(poolDeployer != address(0), "Deployer not set");
        require(poolsByAsset[params.asset] == address(0), "Pool exists for asset");

        // Encode params for deployer
        bytes memory deployParams = abi.encode(
            params.asset,
            params.poolId,
            params.pubX,
            params.pubY,
            params.mpName,
            params.mpSymbol,
            params.restrictedMp,
            params.payoutScript,
            params.calculatorId,
            msg.sender
        );

        // Call external deployer
        (poolAddress, mpTokenAddress) = IPoolDeployer(poolDeployer).deployPool(
            spvContract,
            frostCoordinator,
            calculatorRegistry,
            stratumDataAggregator,
            stratumDataValidator,
            oracleRegistry,
            poolTokenFactory,
            multiPoolDAO,
            deployParams
        );

        // Store pool info
        poolsByAsset[params.asset] = poolAddress;
        isValidPool[poolAddress] = true;

        poolsInfo[poolAddress] = PoolInfo({
            poolCore: poolAddress,
            mpToken: mpTokenAddress,
            poolId: params.poolId,
            isActive: true,
            createdAt: block.timestamp,
            creator: msg.sender
        });

        allPools.push(poolAddress);

        emit PoolCreated(
            poolAddress,
            mpTokenAddress,
            params.asset,
            params.poolId,
            msg.sender
        );

        return (poolAddress, mpTokenAddress);
    }

    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }

    function getPoolAt(uint256 index) external view returns (address) {
        return allPools[index];
    }

    function deactivatePool(address pool) external onlyRole(ADMIN_ROLE) {
        require(isValidPool[pool], "Invalid pool");
        poolsInfo[pool].isActive = false;
    }
}