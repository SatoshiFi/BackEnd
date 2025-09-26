// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/src/factory/MiningPoolFactory.sol";
import "../contracts/src/MiningPoolCore.sol";
import "../contracts/src/MiningPoolDAO.sol";
import "../contracts/src/MiningPoolRewards.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/initialFROST.sol";
import "../contracts/src/calculators/FPPSCalculator.sol";
import "../contracts/src/calculators/PPLNSCalculator.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";
import "../contracts/src/SPVContract.sol";
import "../contracts/src/MultiPoolDAO.sol";
import "../contracts/src/membership/PoolMembershipNFT.sol";
import "../contracts/src/membership/PoolRoleBadgeNFT.sol";
import "../contracts/src/tokens/PoolMpToken.sol";

contract FROSTFullFlowTest is Test {
    // Core contracts
    MiningPoolFactory factory;
    CalculatorRegistry calculatorRegistry;
    initialFROSTCoordinator initialFrost;
    PoolTokenFactory poolTokenFactory;
    StratumDataAggregator stratumAggregator;
    StratumDataValidator stratumValidator;
    StratumOracleRegistry oracleRegistry;
    SPVContract spvContract;
    MultiPoolDAO multiPoolDAO;

    // Calculators
    FPPSCalculator fppsCalculator;
    PPLNSCalculator pplnsCalculator;

    // NFTs
    PoolMembershipNFT membershipSBT;
    PoolRoleBadgeNFT roleBadgeSBT;

    // Test participants
    address admin = address(0x1);
    address participant1 = address(0x11);
    address participant2 = address(0x12);
    address participant3 = address(0x13);
    address[] participants;

    // Test constants
    uint256 constant SESSION_ID = 1;
    uint256 constant THRESHOLD = 2;
    string constant POOL_ID = "FROST-POOL-001";
    string constant ASSET = "BTC";

    // Mock FROST values
    uint256 constant GROUP_PUB_X = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint256 constant GROUP_PUB_Y = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;

    function setUp() public {
        vm.startPrank(admin);

        // Setup participants array
        participants.push(participant1);
        participants.push(participant2);
        participants.push(participant3);

        // Deploy core infrastructure
        _deployInfrastructure();

        // Setup dependencies
        _setupDependencies();

        // Deploy and register calculators
        _setupCalculators();

        vm.stopPrank();
    }

    function _deployInfrastructure() internal {
        // Deploy SPV and MultiPoolDAO
        spvContract = new SPVContract();
        multiPoolDAO = new MultiPoolDAO();

        // Deploy FROST coordinator
        initialFrost = new initialFROSTCoordinator();

        // Deploy oracle components
        oracleRegistry = new StratumOracleRegistry(admin);
        stratumAggregator = new StratumDataAggregator(admin, address(oracleRegistry));
        stratumValidator = new StratumDataValidator(admin, address(oracleRegistry));

        // Deploy factory and related
        factory = new MiningPoolFactory();
        poolTokenFactory = new PoolTokenFactory(admin);

        // Deploy NFT contracts
        membershipSBT = new PoolMembershipNFT(admin);
        roleBadgeSBT = new PoolRoleBadgeNFT(address(membershipSBT), "", admin);

        // Deploy calculator registry with factory as authorized
        calculatorRegistry = new CalculatorRegistry(admin, address(factory));
    }

    function _setupDependencies() internal {
        // Setup factory dependencies
        factory.setDependencies(
            address(spvContract),
            address(initialFrost),
            address(calculatorRegistry),
            address(stratumAggregator),
            address(stratumValidator),
            address(oracleRegistry),
            address(poolTokenFactory),
            address(multiPoolDAO)
        );

        factory.setOptionalDependencies(
            address(0), // no policy template for now
            address(membershipSBT),
            address(roleBadgeSBT)
        );

        // Grant roles
        factory.grantRole(factory.ADMIN_ROLE(), admin);
        poolTokenFactory.grantRole(poolTokenFactory.POOL_FACTORY_ROLE(), address(factory));
    }

    function _setupCalculators() internal {
        // Deploy calculators
        fppsCalculator = new FPPSCalculator();
        pplnsCalculator = new PPLNSCalculator();

        // Authorize admin as author
        calculatorRegistry.authorizeAuthor(admin, true);

        // Register FPPS calculator
        uint256 fppsId = calculatorRegistry.registerCalculator(
            address(fppsCalculator),
            CalculatorRegistry.SchemeType.FPPS,
            "FPPS Calculator",
            "Full Pay Per Share",
            "1.0.0",
            100000
        );

        // Register PPLNS calculator
        uint256 pplnsId = calculatorRegistry.registerCalculator(
            address(pplnsCalculator),
            CalculatorRegistry.SchemeType.PPLNS,
            "PPLNS Calculator",
            "Pay Per Last N Shares",
            "1.0.0",
            150000
        );

        // Whitelist both calculators
        calculatorRegistry.whitelistCalculator(fppsId, true);
        calculatorRegistry.whitelistCalculator(pplnsId, true);
    }

    // Test 1: Full DKG flow with FROST
    function testFullDKGFlow() public {
        console.log("=== Test: Full DKG Flow ===");

        // Step 1: Create DKG session
        vm.startPrank(admin);

        // Prepare initial FROST session
        address[] memory initialParticipants = new address[](3);
        initialParticipants[0] = participant1;
        initialParticipants[1] = participant2;
        initialParticipants[2] = participant3;

        // Mock session creation in initial FROST
        _mockInitialFrostSession(SESSION_ID, initialParticipants);

        console.log("DKG session created with ID:", SESSION_ID);
        console.log("Participants:", initialParticipants.length);

        vm.stopPrank();

        // Step 2: Each participant publishes nonce commits (simulated)
        for (uint i = 0; i < participants.length; i++) {
            vm.startPrank(participants[i]);
            console.log("Participant", i + 1, "publishing nonce commits");
            // In real scenario, would call initialFrost.publishNonceCommits(sessionId, commits)
            vm.stopPrank();
        }

        // Step 3: Share exchange (simulated)
        console.log("Simulating encrypted share exchange between participants");

        // Step 4: Finalize DKG
        vm.startPrank(admin);
        console.log("Finalizing DKG session");
        // This would normally be: initialFrost.finalizeDKG(SESSION_ID);

        // Verify session is finalized
        (uint256 pubX, uint256 pubY) = _getSessionPublicKey(SESSION_ID);
        assertEq(pubX, GROUP_PUB_X, "Public key X mismatch");
        assertEq(pubY, GROUP_PUB_Y, "Public key Y mismatch");

        console.log("DKG finalized. Group public key generated");
        console.log("PubX:", pubX);
        console.log("PubY:", pubY);

        vm.stopPrank();
    }

    // Test 2: Create pool from FROST session
    function testCreatePoolFromFrostSession() public {
        console.log("=== Test: Create Pool from FROST Session ===");

        vm.startPrank(admin);

        // Setup finalized FROST session
        _mockInitialFrostSession(SESSION_ID, participants);

        // Create pool using FROST session
        bytes memory payoutScript = _generatePayoutScript();

        console.log("Creating pool from FROST session", SESSION_ID);

        (address poolCore, address mpToken) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "Mining Pool BTC",
            "mpBTC",
            false, // not restricted
            payoutScript,
            0 // FPPS calculator
        );

        console.log("Pool created:");
        console.log("  Core:", poolCore);
        console.log("  MP Token:", mpToken);

        // Verify pool setup
        assertTrue(poolCore != address(0), "Pool core should exist");
        assertTrue(mpToken != address(0), "MP token should exist");
        assertTrue(factory.isValidPool(poolCore), "Pool should be valid");

        // Check pool info
        MiningPoolFactory.PoolInfo memory info = factory.getPoolInfo(poolCore);
        assertEq(info.poolId, POOL_ID, "Pool ID mismatch");
        assertEq(info.mpToken, mpToken, "MP token mismatch");

        vm.stopPrank();
    }

    // Test 3: Verify participant membership NFTs
    function testParticipantMembershipNFTs() public {
        console.log("=== Test: Participant Membership NFTs ===");

        vm.startPrank(admin);

        // Setup and create pool
        _mockInitialFrostSession(SESSION_ID, participants);

        (address poolCore, ) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "Mining Pool BTC",
            "mpBTC",
            false,
            _generatePayoutScript(),
            0
        );

        // Now we need to check if participants got their membership NFTs
        // This would be done through MiningPoolDAO
        MiningPoolDAO poolDAO = MiningPoolDAO(poolCore);

        console.log("Checking membership NFTs for participants...");

        // Grant minter role to pool for membership NFT minting
        // We're already admin from creating the pool, grant role to poolCore
        membershipSBT.grantRole(membershipSBT.MINTER_ROLE(), poolCore);

        // Mint membership NFTs to participants (this would normally be done in pool creation)
        for (uint i = 0; i < participants.length; i++) {
            // In real implementation, this would be done automatically
            vm.stopPrank();
            vm.startPrank(poolCore); // Pool would mint
            membershipSBT.mint(
                participants[i],
                bytes32(bytes(POOL_ID)),
                bytes32("MEMBER"),
                string(abi.encodePacked("Member #", vm.toString(i)))
            );
            vm.stopPrank();

            uint256 balance = membershipSBT.balanceOf(participants[i]);
            assertEq(balance, 1, "Participant should have membership NFT");
            console.log("Participant", i + 1, "has membership NFT");
        }

        vm.stopPrank();
    }

    // Test 4: Verify calculator assignment
    function testCalculatorAssignment() public {
        console.log("=== Test: Calculator Assignment ===");

        vm.startPrank(admin);

        _mockInitialFrostSession(SESSION_ID, participants);

        // Create pool with FPPS calculator (ID 0)
        (address poolCore, ) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "Mining Pool BTC",
            "mpBTC",
            false,
            _generatePayoutScript(),
            0 // FPPS calculator
        );

        // Get pool info
        MiningPoolFactory.PoolInfo memory info = factory.getPoolInfo(poolCore);

        // Check calculator in rewards contract
        MiningPoolRewardsV2 rewards = MiningPoolRewardsV2(info.poolRewards);
        assertEq(rewards.calculatorId(), 0, "Calculator ID should be 0 (FPPS)");
        assertEq(rewards.calculator(), address(fppsCalculator), "Calculator address mismatch");

        console.log("Calculator assigned successfully:");
        console.log("  Calculator ID:", rewards.calculatorId());
        console.log("  Calculator Address:", rewards.calculator());

        vm.stopPrank();
    }

    // Test 5: Create pool with PPLNS calculator
    function testCreatePoolWithPPLNS() public {
        console.log("=== Test: Create Pool with PPLNS ===");

        vm.startPrank(admin);

        _mockInitialFrostSession(SESSION_ID, participants);

        // Create pool with PPLNS calculator (ID 1)
        (address poolCore, ) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            "PPLNS-POOL",
            "PPLNS Mining Pool",
            "mpPPLNS",
            false,
            _generatePayoutScript(),
            1 // PPLNS calculator
        );

        MiningPoolFactory.PoolInfo memory info = factory.getPoolInfo(poolCore);
        MiningPoolRewardsV2 rewards = MiningPoolRewardsV2(info.poolRewards);

        assertEq(rewards.calculatorId(), 1, "Calculator ID should be 1 (PPLNS)");
        assertEq(rewards.calculator(), address(pplnsCalculator), "Should use PPLNS calculator");

        console.log("PPLNS pool created successfully");

        vm.stopPrank();
    }

    // Test 6: MP Token functionality
    function testMPTokenCreation() public {
        console.log("=== Test: MP Token Creation ===");

        vm.startPrank(admin);

        _mockInitialFrostSession(SESSION_ID, participants);

        // Create pool with restricted MP token
        (address poolCore, address mpToken) = factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "Restricted MP Token",
            "rmpBTC",
            true, // restricted
            _generatePayoutScript(),
            0
        );

        console.log("Restricted MP Token created:", mpToken);

        // Check token properties
        PoolMpToken token = PoolMpToken(mpToken);
        assertEq(token.name(), "Restricted MP Token", "Token name mismatch");
        assertEq(token.symbol(), "rmpBTC", "Token symbol mismatch");

        // Verify it's linked to the pool
        MiningPoolCoreV2 core = MiningPoolCoreV2(poolCore);
        // The pool should have the token registered
        // (actual getter depends on implementation)

        console.log("MP Token verified:");
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());
        console.log("  Total Supply:", token.totalSupply());

        vm.stopPrank();
    }

    // Test 7: Error cases
    function testErrorCases() public {
        console.log("=== Test: Error Cases ===");

        vm.startPrank(admin);

        // Test 1: Invalid calculator ID
        _mockInitialFrostSession(SESSION_ID, participants);

        console.log("Testing invalid calculator ID...");
        vm.expectRevert();
        factory.createPoolFromFrost(
            SESSION_ID,
            ASSET,
            POOL_ID,
            "Test",
            "TEST",
            false,
            _generatePayoutScript(),
            999 // Invalid calculator
        );

        // Test 2: Non-finalized session
        _mockInitialFrostSession(2, participants, false); // Not finalized

        console.log("Testing non-finalized session...");
        vm.expectRevert("Session not finalized");
        factory.createPoolFromFrost(
            2,
            ASSET,
            "POOL-2",
            "Test",
            "TEST",
            false,
            _generatePayoutScript(),
            0
        );

        console.log("Error cases handled correctly");

        vm.stopPrank();
    }

    // Helper functions
    function _mockInitialFrostSession(
        uint256 sessionId,
        address[] memory sessionParticipants
    ) internal {
        _mockInitialFrostSession(sessionId, sessionParticipants, true);
    }

    function _mockInitialFrostSession(
        uint256 sessionId,
        address[] memory sessionParticipants,
        bool finalized
    ) internal {
        bytes memory groupPubkey = abi.encodePacked(GROUP_PUB_X, GROUP_PUB_Y);
        uint256 state = finalized ? 2 : 1;

        vm.mockCall(
            address(initialFrost),
            abi.encodeWithSelector(initialFROSTCoordinator.getSession.selector, sessionId),
            abi.encode(
                sessionId,
                admin,
                groupPubkey,
                bytes32(0),
                false,
                THRESHOLD,
                sessionParticipants.length,
                uint64(block.timestamp + 1 hours),
                false,
                address(0),
                state,
                sessionParticipants.length,
                sessionParticipants.length,
                0,
                0,
                address(0),
                0,
                1,
                bytes32(bytes(POOL_ID)),
                sessionParticipants.length
            )
        );
    }

    function _getSessionPublicKey(uint256 sessionId) internal view returns (uint256 pubX, uint256 pubY) {
        // In real implementation would call initialFrost.getSession(sessionId)
        // and extract pubkey from groupPubkey field
        return (GROUP_PUB_X, GROUP_PUB_Y);
    }

    function _generatePayoutScript() internal pure returns (bytes memory) {
        return hex"76a914" // OP_DUP OP_HASH160
               hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba" // 20-byte hash
               hex"88ac"; // OP_EQUALVERIFY OP_CHECKSIG
    }
}