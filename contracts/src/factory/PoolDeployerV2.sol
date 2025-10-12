// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../MiningPoolDAOCore.sol";
import "../RewardHandler.sol";
import "../RedemptionHandler.sol";
import "./PoolTokenFactory.sol";
import "../interfaces/IMiningPoolFactoryCore.sol";

interface IPoolTokenFactory {
    function createMpToken(string memory name, string memory symbol, address pool) external returns (address);
    function createMpTokenRestricted(string memory name, string memory symbol, address pool) external returns (address);
}

contract PoolDeployerV2 {
    address public factory;
    address public rewardHandler;
    address public redemptionHandler;

    struct PoolAddresses {
        address pool;
        address mpToken;
        address rewardHandler;
        address redemptionHandler;
    }

    mapping(address => PoolAddresses) public poolRegistry;

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor(address _factory, address _spvContract) {
        require(_factory != address(0), "Invalid factory");
        require(_spvContract != address(0), "Invalid SPV contract");

        factory = _factory;

        rewardHandler = address(new RewardHandler(_spvContract));
        redemptionHandler = address(new RedemptionHandler());
    }

    function deployPool(
        address, address, address, address, address, address, address, address,
        bytes calldata params
    )
    external
    onlyFactory
    returns (address poolAddress, address mpTokenAddress)
    {
        // Get dependencies from factory
        address spv = IMiningPoolFactoryCore(factory).spvContract();
        address frost = IMiningPoolFactoryCore(factory).frostCoordinator();
        address calcRegistry = IMiningPoolFactoryCore(factory).calculatorRegistry();
        address aggregator = IMiningPoolFactoryCore(factory).stratumDataAggregator();
        address validator = IMiningPoolFactoryCore(factory).stratumDataValidator();
        address oracleRegistry = IMiningPoolFactoryCore(factory).oracleRegistry();
        address tokenFactory = IMiningPoolFactoryCore(factory).poolTokenFactory();

        // Decode params
        (
            string memory asset,
         string memory poolId,
         uint256 pubX,
         uint256 pubY,
         string memory mpName,
         string memory mpSymbol,
         bool restrictedMp,
         bytes memory payoutScript,
         uint256 calculatorId,
         address creator
        ) = abi.decode(params, (string, string, uint256, uint256, string, string, bool, bytes, uint256, address));

        // NOTE: Calculator verification removed - Factory handles this
        // Deployer should not call CalculatorRegistry directly

        // Deploy core pool contract
        MiningPoolDAOCore pool = new MiningPoolDAOCore();

        // Initialize pool
        pool.initialize(
            spv,
            frost,
            calcRegistry,
            aggregator,
            validator,
            oracleRegistry,
            pubX,
            pubY,
            poolId
        );

        // Set handlers
        pool.setHandlers(rewardHandler, redemptionHandler);
        pool.setPayoutScript(payoutScript);

        // Deploy MP token
        if (restrictedMp) {
            mpTokenAddress = IPoolTokenFactory(tokenFactory).createMpTokenRestricted(
                mpName,
                mpSymbol,
                address(pool)
            );
        } else {
            mpTokenAddress = IPoolTokenFactory(tokenFactory).createMpToken(
                mpName,
                mpSymbol,
                address(pool)
            );
        }

        // Set pool token
        pool.setPoolToken(mpTokenAddress);

        // Grant roles to creator
        pool.grantRole(pool.ADMIN_ROLE(), creator);
        pool.grantRole(pool.POOL_MANAGER_ROLE(), creator);
        pool.grantRole(pool.CONFIRMER_ROLE(), creator);

        // Renounce our roles
        pool.renounceRole(pool.ADMIN_ROLE(), address(this));
        pool.renounceRole(pool.POOL_MANAGER_ROLE(), address(this));
        pool.renounceRole(pool.CONFIRMER_ROLE(), address(this));

        poolAddress = address(pool);

        // Store pool addresses
        poolRegistry[poolAddress] = PoolAddresses({
            pool: poolAddress,
            mpToken: mpTokenAddress,
            rewardHandler: rewardHandler,
            redemptionHandler: redemptionHandler
        });

        return (poolAddress, mpTokenAddress);
    }

    function getPoolAddresses(address pool) external view returns (PoolAddresses memory) {
        return poolRegistry[pool];
    }
}
