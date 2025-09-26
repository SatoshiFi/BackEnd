// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

// Refactored core contracts
import "../contracts/src/MiningPoolDAOCore.sol";
import "../contracts/src/RewardHandler.sol";
import "../contracts/src/RedemptionHandler.sol";

// Factory contracts
import "../contracts/src/factory/MiningPoolFactoryCore.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";

// Supporting contracts
import "../contracts/src/SPVContract.sol";
import "../contracts/src/initialFROST.sol";
import "../contracts/src/MultiPoolDAO.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/calculators/PPLNSCalculator.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";
import "../contracts/src/tokens/PoolMpToken.sol";

/**
 * @notice Base test contract that provides compatibility layer for refactored contracts
 * This allows existing tests to work with the new contract architecture
 */
abstract contract BaseTest is Test {
    // Core contracts
    SPVContract public spv;
    initialFROSTCoordinator public frost;
    MultiPoolDAO public multiPoolDAO;

    // Factory contracts (using old names for compatibility)
    MiningPoolFactoryCore public factory;
    PoolDeployerV2 public deployer;
    PoolTokenFactory public tokenFactory;

    // Handlers
    RewardHandler public rewardHandler;
    RedemptionHandler public redemptionHandler;

    // Calculator contracts
    CalculatorRegistry public calculatorRegistry;
    PPLNSCalculator public pplnsCalculator;
    uint256 public pplnsCalculatorId;

    // Oracle contracts
    StratumOracleRegistry public oracleRegistry;
    StratumDataAggregator public aggregator;
    StratumDataValidator public validator;

    // Test users
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    function setUp() public virtual {
        // Deploy SPV and FROST
        spv = new SPVContract();
        frost = new initialFROSTCoordinator();

        // Deploy MultiPoolDAO
        multiPoolDAO = new MultiPoolDAO();
        multiPoolDAO.initialize(
            address(frost),
            bytes(""),
            3600,
            address(this)
        );

        // Deploy factory components
        factory = new MiningPoolFactoryCore();
        deployer = new PoolDeployerV2(address(factory));

        // Deploy handlers
        rewardHandler = new RewardHandler();
        redemptionHandler = new RedemptionHandler();

        // Deploy token factory
        tokenFactory = new PoolTokenFactory(address(this));

        // Deploy oracles
        oracleRegistry = new StratumOracleRegistry(address(this));
        aggregator = new StratumDataAggregator(
            address(oracleRegistry),
            address(this)
        );
        validator = new StratumDataValidator(
            address(this),
            address(oracleRegistry)
        );

        // Deploy and register calculator
        calculatorRegistry = new CalculatorRegistry(
            address(this),
            address(factory)
        );
        pplnsCalculator = new PPLNSCalculator();

        calculatorRegistry.authorizeAuthor(address(this), true);
        pplnsCalculatorId = calculatorRegistry.registerCalculator(
            address(pplnsCalculator),
            CalculatorRegistry.SchemeType.PPLNS,
            "PPLNS",
            "Pay Per Last N Shares",
            "1.0.0",
            500000
        );
        calculatorRegistry.whitelistCalculator(pplnsCalculatorId, true);

        // Configure factory
        factory.setPoolDeployer(address(deployer));
        factory.setDependencies(
            address(spv),
            address(frost),
            address(calculatorRegistry),
            address(aggregator),
            address(validator),
            address(oracleRegistry),
            address(tokenFactory),
            address(multiPoolDAO)
        );

        // Grant roles
        factory.grantRole(factory.POOL_MANAGER_ROLE(), address(this));
        tokenFactory.grantRole(keccak256("POOL_FACTORY_ROLE"), address(deployer));
    }

    /**
     * @notice Adapter function to create a pool using the old interface
     * Maps old MiningPoolFactory.createPool to new architecture
     */
    function createPool(
        string memory asset,
        string memory poolId,
        uint256 pubX,
        uint256 pubY
    ) internal returns (address poolAddress, address mpToken) {
        MiningPoolFactoryCore.PoolParams memory params = MiningPoolFactoryCore.PoolParams({
            asset: asset,
            poolId: poolId,
            pubX: pubX,
            pubY: pubY,
            mpName: string.concat(asset, " Mining Pool"),
            mpSymbol: string.concat("MP", asset),
            restrictedMp: false,
            payoutScript: hex"76a914abcdef88ac",
            calculatorId: pplnsCalculatorId
        });

        return factory.createPool(params);
    }

    /**
     * @notice Adapter to get a pool as MiningPoolDAOCore
     * This allows tests to use the old MiningPoolDAO interface
     */
    function getPoolDAO(address poolAddress) internal view returns (MiningPoolDAOCore) {
        return MiningPoolDAOCore(poolAddress);
    }

    /**
     * @notice Adapter for createPoolFromFrost - creates pool after FROST session
     */
    function createPoolFromFrost(
        uint256 sessionId,
        string memory asset,
        string memory poolId,
        string memory mpName,
        string memory mpSymbol,
        bool restrictedMp,
        bytes memory payoutScript,
        uint256 calculatorId
    ) internal returns (address poolAddress, address mpToken) {
        // Check FROST session state (like in MiningPoolFactory)
        (,, bytes memory groupPubkey,,,,,,,,uint256 state,,,,,,,,,) = frost.getSession(sessionId);
        require(state >= 2, "Session not finalized"); // Must be at least PENDING_SHARES or higher
        require(groupPubkey.length >= 64, "Invalid group pubkey");

        // Get public key from FROST session (simplified for testing)
        uint256 pubX = uint256(keccak256(abi.encodePacked(sessionId, "pubX")));
        uint256 pubY = uint256(keccak256(abi.encodePacked(sessionId, "pubY")));

        MiningPoolFactoryCore.PoolParams memory params = MiningPoolFactoryCore.PoolParams({
            asset: asset,
            poolId: poolId,
            pubX: pubX,
            pubY: pubY,
            mpName: mpName,
            mpSymbol: mpSymbol,
            restrictedMp: restrictedMp,
            payoutScript: payoutScript,
            calculatorId: calculatorId > 0 ? calculatorId : pplnsCalculatorId
        });

        return factory.createPool(params);
    }

    /**
     * @notice Helper to setup SPV blocks for testing
     */
    function setupSPVBlock(bytes32 blockHash, uint256 height) internal {
        // Create valid 80-byte Bitcoin block header
        bytes memory header = new bytes(80);
        header[0] = 0x01; // Version
        header[68] = 0x01; // Timestamp
        header[72] = 0x1d; // Bits
        header[73] = 0x00;
        header[74] = 0xff;
        header[75] = 0xff;
        header[76] = 0x01; // Nonce

        spv.addBlockHeader(header);

        // Add confirmations
        for (uint i = 1; i <= 100; i++) {
            bytes memory nextHeader = new bytes(80);
            for (uint j = 0; j < 80; j++) {
                nextHeader[j] = header[j];
            }
            nextHeader[76] = bytes1(uint8(i));
            nextHeader[77] = bytes1(uint8(i >> 8));
            spv.addBlockHeader(nextHeader);
        }
    }
}