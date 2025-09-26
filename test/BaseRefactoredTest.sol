// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

// Refactored contracts
import "../contracts/src/MiningPoolDAOCore.sol";
import "../contracts/src/RewardHandler.sol";
import "../contracts/src/RedemptionHandler.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";
import "../contracts/src/factory/PoolDeployerV2.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";

// Supporting contracts
import "../contracts/src/mocks/MockSPVContract.sol";
import "../contracts/src/initialFROST.sol";
import "../contracts/src/MultiPoolDAO.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import "../contracts/src/calculators/PPLNSCalculator.sol";
import "../contracts/src/oracles/StratumDataAggregator.sol";
import "../contracts/src/oracles/StratumDataValidator.sol";
import "../contracts/src/oracles/StratumOracleRegistry.sol";

abstract contract BaseRefactoredTest is Test {
    // Core contracts
    MockSPVContract public spv;
    initialFROSTCoordinator public frost;
    MultiPoolDAO public multiPoolDAO;

    // Factory contracts
    MiningPoolFactoryCore public factory;
    PoolDeployerV2 public deployer;
    PoolTokenFactory public tokenFactory;

    // Handlers
    address public rewardHandler;
    address public redemptionHandler;

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
        // Deploy core contracts
        spv = new MockSPVContract();
        frost = new initialFROSTCoordinator();

        multiPoolDAO = new MultiPoolDAO();
        multiPoolDAO.initialize(
            address(frost),
            bytes(""),
            3600,
            address(this)
        );

        // Deploy factory
        factory = new MiningPoolFactoryCore();
        deployer = new PoolDeployerV2(address(factory));

        // Get handler addresses from deployer
        rewardHandler = deployer.rewardHandler();
        redemptionHandler = deployer.redemptionHandler();

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

        // Deploy calculator
        calculatorRegistry = new CalculatorRegistry(
            address(this),
            address(factory)
        );
        pplnsCalculator = new PPLNSCalculator();

        // Register calculator
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

    function setupSPVBlock(bytes32 targetHash, uint256 targetHeight) internal {
        // Use the new helper to add the block with specific hash
        MockSPVContract(address(spv)).addBlockWithHash(targetHash, targetHeight);

        // Add 100+ confirmations to make it mature
        for (uint i = 1; i <= 100; i++) {
            bytes memory header = new bytes(80);
            // Set version (4 bytes)
            header[0] = 0x01;
            // Set some timestamp
            header[68] = 0x01;
            // Set bits (difficulty)
            header[72] = 0x1d;
            header[73] = 0x00;
            header[74] = 0xff;
            header[75] = 0xff;
            // Set unique nonce
            header[76] = bytes1(uint8(i));
            header[77] = bytes1(uint8(i >> 8));

            spv.addBlockHeader(header);
        }
    }
}