// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/src/factory/MiningPoolFactory.sol";
import "../contracts/src/MiningPoolCore.sol";
import "../contracts/src/MiningPoolRewards.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/FROSTCoordinator.sol";
import "../contracts/src/calculators/FPPSCalculator.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";
import "../contracts/src/SPVContract.sol";
import "../contracts/src/MultiPoolDAO.sol";

contract FROSTPoolCreationTest is Test {
    // Contracts
    MiningPoolFactory factory;
    CalculatorRegistry calculatorRegistry;
    FROSTCoordinator frostCoordinator;
    PoolTokenFactory poolTokenFactory;
    StratumDataAggregator stratumAggregator;
    StratumDataValidator stratumValidator;
    StratumOracleRegistry oracleRegistry;
    SPVContract spvContract;
    MultiPoolDAO multiPoolDAO;
    FPPSCalculator fppsCalculator;

    // Test addresses
    address admin = address(0x1);
    address poolManager = address(0x2);
    address authorizedAuthor = address(0x3);
    address participant1 = address(0x4);
    address participant2 = address(0x5);
    address participant3 = address(0x6);

    // Test constants
    uint256 constant SESSION_ID = 1;
    uint256 constant PUB_X = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint256 constant PUB_Y = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;
    string constant POOL_ID = "test-pool-001";
    string constant ASSET = "BTC";

    function setUp() public {
        vm.startPrank(admin);

        // Deploy all dependencies
        spvContract = new SPVContract();
        frostCoordinator = new FROSTCoordinator(admin);
        multiPoolDAO = new MultiPoolDAO();
        poolTokenFactory = new PoolTokenFactory(admin);

        // Deploy oracle components
        oracleRegistry = new StratumOracleRegistry(admin);
        stratumAggregator = new StratumDataAggregator(admin, address(oracleRegistry));
        stratumValidator = new StratumDataValidator(admin, address(oracleRegistry));

        // Deploy and setup factory
        factory = new MiningPoolFactory();

        // Deploy and setup calculator registry
        calculatorRegistry = new CalculatorRegistry(admin, address(factory));

        // Setup factory dependencies
        factory.setDependencies(
            address(spvContract),
            address(frostCoordinator),
            address(calculatorRegistry),
            address(stratumAggregator),
            address(stratumValidator),
            address(oracleRegistry),
            address(poolTokenFactory),
            address(multiPoolDAO)
        );

        // Deploy a test calculator
        fppsCalculator = new FPPSCalculator();

        // Authorize author and register calculator
        calculatorRegistry.authorizeAuthor(authorizedAuthor, true);

        vm.stopPrank();
        vm.startPrank(authorizedAuthor);

        uint256 calculatorId = calculatorRegistry.registerCalculator(
            address(fppsCalculator),
            CalculatorRegistry.SchemeType.FPPS,
            "FPPS Calculator",
            "Full Pay Per Share calculator",
            "1.0.0",
            100000 // gas estimate
        );

        vm.stopPrank();
        vm.startPrank(admin);

        // Whitelist the calculator
        calculatorRegistry.whitelistCalculator(calculatorId, true);

        // Grant roles to factory on PoolTokenFactory
        poolTokenFactory.grantRole(poolTokenFactory.POOL_FACTORY_ROLE(), address(factory));

        // Grant roles
        factory.grantRole(factory.POOL_MANAGER_ROLE(), poolManager);

        vm.stopPrank();
    }

    function testCalculatorRegistrySetup() public {
        // Test that calculator is properly registered
        (address contractAddr, , string memory name, , , , , , bool isActive, bool isWhitelisted, ,) =
            calculatorRegistry.calculators(0);

        assertEq(contractAddr, address(fppsCalculator), "Calculator address mismatch");
        assertEq(name, "FPPS Calculator", "Calculator name mismatch");
        assertTrue(isActive, "Calculator should be active");
        assertTrue(isWhitelisted, "Calculator should be whitelisted");
    }

    function testGetCalculatorWithoutPoolFactory() public {
        // Test that any contract can get calculator after modifier removal
        vm.startPrank(address(0x999)); // Random address, not poolFactory

        address calcAddr = calculatorRegistry.getCalculator(0);
        assertEq(calcAddr, address(fppsCalculator), "Should return calculator address");

        vm.stopPrank();
    }

    function testCreatePoolFromFrost() public {
        vm.startPrank(admin);

        // Setup FROST session mock
        _mockFrostSession();

        // Create pool from FROST
        bytes memory payoutScript = hex"76a914" // OP_DUP OP_HASH160
                                   hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba" // 20-byte hash
                                   hex"88ac"; // OP_EQUALVERIFY OP_CHECKSIG

        (address poolCore, address mpToken) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "mpBTC-001",
            "mpBTC001",
            false, // not restricted
            payoutScript,
            0 // calculator ID
        );

        // Verify pool was created
        assertTrue(poolCore != address(0), "Pool core should be deployed");
        assertTrue(mpToken != address(0), "MP token should be deployed");

        // Verify pool is registered
        assertTrue(factory.isValidPool(poolCore), "Pool should be valid");
        assertEq(factory.poolsByAsset(ASSET), poolCore, "Pool should be registered by asset");

        // Get pool info
        MiningPoolFactory.PoolInfo memory info = factory.getPoolInfo(poolCore);
        assertEq(info.poolCore, poolCore, "Pool core address mismatch");
        assertEq(info.poolId, POOL_ID, "Pool ID mismatch");
        assertTrue(info.isActive, "Pool should be active");
        assertEq(info.creator, admin, "Creator mismatch");

        vm.stopPrank();
    }

    function testCalculatorAssignmentInPool() public {
        vm.startPrank(admin);

        // Setup FROST session
        _mockFrostSession();

        // Create pool with calculator
        bytes memory payoutScript = hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac";

        (address poolCore, ) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "mpBTC-001",
            "mpBTC001",
            false,
            payoutScript,
            0 // Use FPPS calculator
        );

        // Get pool info to find rewards contract
        MiningPoolFactory.PoolInfo memory info = factory.getPoolInfo(poolCore);
        address poolRewards = info.poolRewards;

        // Verify calculator is set in Core
        MiningPoolCoreV2 core = MiningPoolCoreV2(poolCore);
        // Calculator ID check removed - not in interface

        // Verify calculator is set in Rewards
        MiningPoolRewardsV2 rewards = MiningPoolRewardsV2(poolRewards);
        assertEq(rewards.calculatorId(), 0, "Calculator ID should be set in rewards");
        assertEq(rewards.calculator(), address(fppsCalculator), "Calculator address should be set");

        vm.stopPrank();
    }

    function testMultiplePoolCreation() public {
        vm.startPrank(admin);

        // Create first pool
        _mockFrostSession();

        (address poolCore1, ) = factory.createPoolFromFrost(
            SESSION_ID,
            "BTC",
            "pool-001",
            "mpBTC-001",
            "mpBTC001",
            false,
            hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac",
            0
        );

        // Create second pool with different session
        _mockFrostSessionWithId(2, PUB_X + 1, PUB_Y + 1);

        (address poolCore2, ) = factory.createPoolFromFrost(
            2,
            "ETH",
            "pool-002",
            "mpETH-002",
            "mpETH002",
            true, // restricted
            hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac",
            0
        );

        // Verify both pools exist
        assertTrue(factory.isValidPool(poolCore1), "First pool should be valid");
        assertTrue(factory.isValidPool(poolCore2), "Second pool should be valid");

        // Verify different assets
        assertEq(factory.poolsByAsset("BTC"), poolCore1, "BTC pool mismatch");
        assertEq(factory.poolsByAsset("ETH"), poolCore2, "ETH pool mismatch");

        // Check pool count
        assertEq(factory.getPoolCount(), 2, "Should have 2 pools");

        // Check active pools
        address[] memory activePools = factory.getActivePools();
        assertEq(activePools.length, 2, "Should have 2 active pools");

        vm.stopPrank();
    }

    function testPoolDeactivationAndReactivation() public {
        vm.startPrank(admin);

        // Create pool
        _mockFrostSession();

        (address poolCore, ) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "mpBTC-001",
            "mpBTC001",
            false,
            hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac",
            0
        );

        // Verify pool is active
        assertTrue(factory.isValidPool(poolCore), "Pool should be valid");

        vm.stopPrank();

        // Deactivate as pool manager
        vm.startPrank(poolManager);
        factory.deactivatePool(poolCore, "Maintenance");

        // Verify pool is deactivated
        assertFalse(factory.isValidPool(poolCore), "Pool should be invalid");

        MiningPoolFactory.PoolInfo memory info = factory.getPoolInfo(poolCore);
        assertFalse(info.isActive, "Pool should be inactive");

        vm.stopPrank();

        // Reactivate as admin
        vm.startPrank(admin);
        factory.reactivatePool(poolCore);

        // Verify pool is active again
        assertTrue(factory.isValidPool(poolCore), "Pool should be valid again");

        info = factory.getPoolInfo(poolCore);
        assertTrue(info.isActive, "Pool should be active again");

        vm.stopPrank();
    }

    function test_RevertWhen_CreatePoolWithInvalidCalculator() public {
        vm.startPrank(admin);

        _mockFrostSession();

        // Try to create pool with non-existent calculator
        vm.expectRevert();
        factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "mpBTC-001",
            "mpBTC001",
            false,
            hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac",
            999 // Invalid calculator ID
        );

        vm.stopPrank();
    }

    function test_RevertWhen_CreatePoolWithoutDependencies() public {
        vm.startPrank(admin);

        // Deploy new factory without dependencies
        MiningPoolFactory emptyFactory = new MiningPoolFactory();
        emptyFactory.grantRole(emptyFactory.ADMIN_ROLE(), admin);

        _mockFrostSession();

        // Should fail due to missing dependencies
        vm.expectRevert();
        emptyFactory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "mpBTC-001",
            "mpBTC001",
            false,
            hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabba88ac",
            0
        );

        vm.stopPrank();
    }

    // Helper functions
    function _mockFrostSession() internal {
        _mockFrostSessionWithId(SESSION_ID, PUB_X, PUB_Y);
    }

    function _mockFrostSessionWithId(uint256 sessionId, uint256 pubX, uint256 pubY) internal {
        // Mock FROST coordinator to return a finalized session
        bytes memory groupPubkey = abi.encodePacked(pubX, pubY);

        // This would normally require mocking the FROSTCoordinator
        // For simplicity, we'll deploy a mock version
        vm.mockCall(
            address(frostCoordinator),
            abi.encodeWithSelector(IFROSTCoordinator.getSession.selector, sessionId),
            abi.encode(
                sessionId,      // id
                admin,          // creator
                groupPubkey,    // groupPubkey
                bytes32(0),     // messageHash
                false,          // messageBound
                2,              // threshold
                3,              // total
                uint64(block.timestamp + 1 hours), // deadline
                false,          // enforceSharesCheck
                address(0),     // verifierOverride
                2,              // state (finalized)
                3,              // commitsCount
                3,              // sharesCount
                0,              // refusalCount
                0,              // purpose
                address(0),     // originContract
                0,              // originId
                1,              // networkId
                bytes32(bytes(POOL_ID)), // poolId
                3               // dkgSharesCount
            )
        );
    }
}