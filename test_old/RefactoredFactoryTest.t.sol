// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";
import "../contracts/src/factory/PoolDeployerLite.sol";
import "../contracts/src/MiningPoolDAO.sol";
import "../contracts/src/initialFROST.sol";
import "../contracts/src/mocks/MockSPVContract.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/calculators/PPLNSCalculator.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/MultiPoolDAO.sol";

contract RefactoredFactoryTest is Test {
    // Refactored factory contracts
    MiningPoolFactoryCore public factoryCore;
    PoolDeployerLite public poolDeployer;
    MiningPoolDAO public poolImplementation;

    // Supporting contracts
    MockSPVContract public spv;
    initialFROSTCoordinator public frost;
    PoolTokenFactory public tokenFactory;
    CalculatorRegistry public calculatorRegistry;
    PPLNSCalculator public pplns;
    StratumDataAggregator public aggregator;
    StratumDataValidator public validator;
    StratumOracleRegistry public oracleRegistry;
    MultiPoolDAO public multiPoolDAO;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    uint256 public pplnsCalculatorId;

    function setUp() public {
        // Deploy supporting contracts
        spv = new MockSPVContract();
        frost = new initialFROSTCoordinator();
        tokenFactory = new PoolTokenFactory(address(this));
        oracleRegistry = new StratumOracleRegistry(address(this));

        // Deploy pool implementation for cloning
        poolImplementation = new MiningPoolDAO();

        // Deploy refactored factory
        factoryCore = new MiningPoolFactoryCore();
        poolDeployer = new PoolDeployerLite(
            address(factoryCore),
            address(poolImplementation)
        );

        // Configure factory core
        factoryCore.setPoolDeployer(address(poolDeployer));

        // Deploy calculator registry with factory core address
        calculatorRegistry = new CalculatorRegistry(
            address(this),
            address(factoryCore)
        );

        // Deploy and register PPLNS calculator
        pplns = new PPLNSCalculator();
        calculatorRegistry.authorizeAuthor(address(this), true);
        pplnsCalculatorId = calculatorRegistry.registerCalculator(
            address(pplns),
            CalculatorRegistry.SchemeType.PPLNS,
            "PPLNS",
            "Pay Per Last N Shares",
            "1.0.0",
            500000
        );

        // Whitelist the calculator
        calculatorRegistry.whitelistCalculator(pplnsCalculatorId, true);

        // Deploy aggregator and validator
        aggregator = new StratumDataAggregator(
            address(oracleRegistry),
            address(this)
        );
        validator = new StratumDataValidator(
            address(this),
            address(oracleRegistry)
        );

        // Deploy MultiPoolDAO
        multiPoolDAO = new MultiPoolDAO();
        multiPoolDAO.initialize(
            address(frost),
            bytes(""),
            3600,
            address(this)
        );

        // Set dependencies in factory
        factoryCore.setDependencies(
            address(spv),
            address(frost),
            address(calculatorRegistry),
            address(aggregator),
            address(validator),
            address(oracleRegistry),
            address(tokenFactory),
            address(multiPoolDAO)
        );

        // Grant pool manager role
        factoryCore.grantRole(factoryCore.POOL_MANAGER_ROLE(), address(this));

        // Grant factory role to pool deployer in token factory
        bytes32 POOL_FACTORY_ROLE = keccak256("POOL_FACTORY_ROLE");
        tokenFactory.grantRole(POOL_FACTORY_ROLE, address(poolDeployer));
    }

    function testRefactoredFactoryDeployment() public {
        // Verify all components are deployed
        assertEq(address(factoryCore.poolDeployer()), address(poolDeployer), "Pool deployer not set");
        assertEq(factoryCore.spvContract(), address(spv), "SPV not set");
        assertEq(factoryCore.frostCoordinator(), address(frost), "FROST not set");
        assertEq(factoryCore.calculatorRegistry(), address(calculatorRegistry), "Calculator registry not set");

        console.log("[OK] Refactored factory deployed successfully");
    }

    function testCreatePoolWithRefactoredFactory() public {
        // Prepare pool params
        MiningPoolFactoryCore.PoolParams memory params = MiningPoolFactoryCore.PoolParams({
            asset: "BTC",
            poolId: "test-pool-1",
            pubX: 12345,
            pubY: 67890,
            mpName: "Mining Pool Token",
            mpSymbol: "MPT",
            restrictedMp: false,
            payoutScript: hex"76a914abcdef88ac",
            calculatorId: pplnsCalculatorId
        });

        // Create pool through factory
        (address poolAddress, address mpTokenAddress) = factoryCore.createPool(params);

        // Verify pool was created
        assertTrue(poolAddress != address(0), "Pool not created");
        assertTrue(mpTokenAddress != address(0), "MP token not created");
        assertTrue(factoryCore.isValidPool(poolAddress), "Pool not marked as valid");
        assertEq(factoryCore.poolsByAsset("BTC"), poolAddress, "Pool not stored by asset");

        // Verify pool info
        (
            address storedPool,
            address storedToken,
            string memory storedId,
            bool isActive,
            uint256 createdAt,
            address creator
        ) = factoryCore.poolsInfo(poolAddress);

        assertEq(storedPool, poolAddress, "Wrong pool address stored");
        assertEq(storedToken, mpTokenAddress, "Wrong token address stored");
        assertEq(storedId, "test-pool-1", "Wrong pool ID stored");
        assertTrue(isActive, "Pool not active");
        assertEq(creator, address(this), "Wrong creator stored");

        console.log("[OK] Pool created with refactored factory");
        console.log("  Pool address:", poolAddress);
        console.log("  MP token:", mpTokenAddress);
    }

    function testCannotCreateDuplicatePool() public {
        MiningPoolFactoryCore.PoolParams memory params = MiningPoolFactoryCore.PoolParams({
            asset: "BTC",
            poolId: "test-pool-1",
            pubX: 12345,
            pubY: 67890,
            mpName: "Mining Pool Token",
            mpSymbol: "MPT",
            restrictedMp: false,
            payoutScript: hex"76a914abcdef88ac",
            calculatorId: pplnsCalculatorId
        });

        // Create first pool
        factoryCore.createPool(params);

        // Try to create duplicate
        vm.expectRevert("Pool exists for asset");
        factoryCore.createPool(params);

        console.log("[OK] Cannot create duplicate pool for same asset");
    }

    function testPoolDeployerOnlyFactory() public {
        // Try to call deployer directly (not from factory)
        bytes memory params = abi.encode(
            "ETH", "pool-1", 111, 222, "Token", "TKN", false, hex"", 1, address(this)
        );

        vm.expectRevert("Only factory");
        poolDeployer.deployPool(
            address(spv),
            address(frost),
            address(calculatorRegistry),
            address(aggregator),
            address(validator),
            address(oracleRegistry),
            address(tokenFactory),
            address(multiPoolDAO),
            params
        );

        console.log("[OK] Pool deployer can only be called by factory");
    }

    function testMultiplePoolsCreation() public {
        string[3] memory assets = ["BTC", "ETH", "DOGE"];

        for (uint i = 0; i < 3; i++) {
            MiningPoolFactoryCore.PoolParams memory params = MiningPoolFactoryCore.PoolParams({
                asset: assets[i],
                poolId: string.concat("pool-", assets[i]),
                pubX: 12345 + i,
                pubY: 67890 + i,
                mpName: string.concat(assets[i], " Mining Token"),
                mpSymbol: string.concat("MP", assets[i]),
                restrictedMp: false,
                payoutScript: hex"76a914abcdef88ac",
                calculatorId: pplnsCalculatorId
            });

            (address pool, address token) = factoryCore.createPool(params);

            assertTrue(pool != address(0), "Pool not created");
            assertEq(factoryCore.poolsByAsset(assets[i]), pool, "Pool not mapped to asset");
        }

        assertEq(factoryCore.getPoolCount(), 3, "Wrong pool count");
        console.log("[OK] Multiple pools created successfully");
    }

    function testPoolDeactivation() public {
        // Create a pool
        MiningPoolFactoryCore.PoolParams memory params = MiningPoolFactoryCore.PoolParams({
            asset: "BTC",
            poolId: "test-pool",
            pubX: 12345,
            pubY: 67890,
            mpName: "Test Token",
            mpSymbol: "TEST",
            restrictedMp: false,
            payoutScript: hex"76a914abcdef88ac",
            calculatorId: pplnsCalculatorId
        });

        (address pool, ) = factoryCore.createPool(params);

        // Verify pool is active
        (, , , bool isActive, , ) = factoryCore.poolsInfo(pool);
        assertTrue(isActive, "Pool should be active");

        // Grant admin role and deactivate
        factoryCore.grantRole(factoryCore.ADMIN_ROLE(), address(this));
        factoryCore.deactivatePool(pool);

        // Verify pool is deactivated
        (, , , bool isActiveAfter, , ) = factoryCore.poolsInfo(pool);
        assertFalse(isActiveAfter, "Pool should be deactivated");

        console.log("[OK] Pool deactivation works");
    }

    function testFactorySizeLimits() public view {
        // Check that refactored contracts are within size limits
        uint256 factoryCoreSize = address(factoryCore).code.length;
        uint256 deployerSize = address(poolDeployer).code.length;
        uint256 implSize = address(poolImplementation).code.length;

        console.log("Contract sizes:");
        console.log("  FactoryCore:", factoryCoreSize, "bytes");
        console.log("  PoolDeployer:", deployerSize, "bytes");
        console.log("  PoolImplementation:", implSize, "bytes");

        // Verify factory core and deployer are under 24KB limit
        assertTrue(factoryCoreSize < 24576, "FactoryCore too large");
        assertTrue(deployerSize < 24576, "PoolDeployer too large");

        console.log("[OK] Factory contracts within size limits");
    }
}