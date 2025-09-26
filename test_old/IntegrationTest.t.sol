// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/src/factory/MiningPoolFactory.sol";
import "../contracts/src/initialFROST.sol";
import "../contracts/src/MiningPoolDAO.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/calculators/FPPSCalculator.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";
import "../contracts/src/SPVContract.sol";
import "../contracts/src/MultiPoolDAO.sol";
import "../contracts/src/membership/PoolMembershipNFT.sol";
import "../contracts/src/membership/PoolRoleBadgeNFT.sol";

contract IntegrationTest is Test {
    // Core contracts
    MiningPoolFactory factory;
    initialFROSTCoordinator frost;
    CalculatorRegistry calculatorRegistry;
    PoolTokenFactory poolTokenFactory;
    SPVContract spvContract;
    MultiPoolDAO multiPoolDAO;

    // Supporting contracts
    StratumDataAggregator stratumAggregator;
    StratumDataValidator stratumValidator;
    StratumOracleRegistry oracleRegistry;
    FPPSCalculator calculator;
    PoolMembershipNFT membershipNFT;
    PoolRoleBadgeNFT roleBadgeNFT;

    // Test actors
    address admin = address(0x1);
    address participant1 = address(0x11);
    address participant2 = address(0x12);
    address participant3 = address(0x13);

    // Test constants
    uint256 constant SESSION_ID = 1;
    uint256 constant THRESHOLD = 2;
    string constant POOL_ID = "INTEGRATION-TEST-POOL";

    function setUp() public {
        vm.startPrank(admin);

        // Deploy all infrastructure
        spvContract = new SPVContract();
        multiPoolDAO = new MultiPoolDAO();
        frost = new initialFROSTCoordinator();

        // Deploy oracle components
        oracleRegistry = new StratumOracleRegistry(admin);
        stratumAggregator = new StratumDataAggregator(admin, address(oracleRegistry));
        stratumValidator = new StratumDataValidator(admin, address(oracleRegistry));

        // Deploy factory and dependencies
        factory = new MiningPoolFactory();
        poolTokenFactory = new PoolTokenFactory(admin);
        calculatorRegistry = new CalculatorRegistry(admin, address(factory));

        // Deploy NFTs
        membershipNFT = new PoolMembershipNFT(admin);
        roleBadgeNFT = new PoolRoleBadgeNFT(address(membershipNFT), "", admin);

        // Setup factory
        factory.setDependencies(
            address(spvContract),
            address(frost),
            address(calculatorRegistry),
            address(stratumAggregator),
            address(stratumValidator),
            address(oracleRegistry),
            address(poolTokenFactory),
            address(multiPoolDAO)
        );

        factory.setOptionalDependencies(
            address(0),
            address(membershipNFT),
            address(roleBadgeNFT)
        );

        // Setup calculator
        calculator = new FPPSCalculator();
        calculatorRegistry.authorizeAuthor(admin, true);
        uint256 calcId = calculatorRegistry.registerCalculator(
            address(calculator),
            CalculatorRegistry.SchemeType.FPPS,
            "FPPS",
            "Full Pay Per Share",
            "1.0.0",
            100000
        );
        calculatorRegistry.whitelistCalculator(calcId, true);

        // Grant necessary roles
        factory.grantRole(factory.ADMIN_ROLE(), admin);
        poolTokenFactory.grantRole(poolTokenFactory.POOL_FACTORY_ROLE(), address(factory));

        vm.stopPrank();
    }

    function testRealDKGFlowWithoutMocks() public {
        console.log("=== INTEGRATION TEST: Real DKG to Pool Creation ===");

        // Step 1: Create DKG session in initialFROST
        vm.startPrank(admin);

        // NOTE: This would fail because initialFROST doesn't have a public createSession function
        // The contract expects sessions to be created through specific entry points

        console.log("PROBLEM 1: Cannot create DKG session - no public method");

        // Even if we could create a session, we would need:
        // 1. Each participant to call publishNonceCommits
        // 2. Each participant to call publishShares
        // 3. Admin to call finalizeDKG

        console.log("PROBLEM 2: No way for participants to submit nonce commits");
        console.log("PROBLEM 3: No way to exchange encrypted shares");
        console.log("PROBLEM 4: finalizeDKG might not be implemented");

        vm.stopPrank();
    }

    function testFactoryDoesNotGetParticipantsList() public {
        console.log("=== INTEGRATION TEST: Factory Participant Handling ===");

        vm.startPrank(admin);

        // Mock a finalized FROST session (since we can't create real one)
        uint256 pubX = 0x1234;
        uint256 pubY = 0x5678;
        bytes memory groupPubkey = abi.encodePacked(pubX, pubY);

        // Mock the getSession call
        vm.mockCall(
            address(frost),
            abi.encodeWithSelector(initialFROSTCoordinator.getSession.selector, SESSION_ID),
            abi.encode(
                SESSION_ID, admin, groupPubkey, bytes32(0), false,
                THRESHOLD, 3, uint64(block.timestamp + 1 hours),
                false, address(0), 2, 3, 3, 0, 0, address(0), 0, 1,
                bytes32(bytes(POOL_ID)), 3
            )
        );

        // Create pool from FROST
        (address poolCore, address mpToken) = factory.createPoolFromFrost(
            SESSION_ID,
            "BTC",
            POOL_ID,
            "mpBTC",
            "mpBTC",
            false,
            hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac",
            0
        );

        console.log("Pool created:", poolCore);
        console.log("MP Token:", mpToken);

        // Check if participants got NFTs automatically
        uint256 p1Balance = membershipNFT.balanceOf(participant1);
        uint256 p2Balance = membershipNFT.balanceOf(participant2);
        uint256 p3Balance = membershipNFT.balanceOf(participant3);

        console.log("Participant1 NFT balance:", p1Balance);
        console.log("Participant2 NFT balance:", p2Balance);
        console.log("Participant3 NFT balance:", p3Balance);

        // These will all be 0 because factory doesn't mint NFTs to participants!
        assertEq(p1Balance, 0, "PROBLEM: Factory doesn't mint NFTs to participants");
        assertEq(p2Balance, 0, "PROBLEM: Factory doesn't mint NFTs to participants");
        assertEq(p3Balance, 0, "PROBLEM: Factory doesn't mint NFTs to participants");

        console.log("CONFIRMED: Factory does NOT automatically mint NFTs to DKG participants!");

        vm.stopPrank();
    }

    function testMissingFunctionalityInInitialFROST() public {
        console.log("=== INTEGRATION TEST: Missing Functions Check ===");

        // Try to find methods that should exist according to requirements

        // 1. No createSession or startDKG
        console.log("MISSING: Public method to create DKG session");

        // 2. No publishNonceCommits
        console.log("MISSING: Method for participants to publish nonce commits");

        // 3. No publishShares
        console.log("MISSING: Method for encrypted share exchange");

        // 4. No getParticipants
        console.log("MISSING: Method to get list of session participants");

        // 5. Factory doesn't use participant info
        console.log("MISSING: Factory integration to mint NFTs to participants");

        console.log("\nCONCLUSION: The implementation is incomplete!");
        console.log("Tests are using mocks instead of real functionality");
    }
}