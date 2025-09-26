// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMiningPoolFactoryCore {
    function spvContract() external view returns (address);
    function frostCoordinator() external view returns (address);
    function calculatorRegistry() external view returns (address);
    function stratumDataAggregator() external view returns (address);
    function stratumDataValidator() external view returns (address);
    function oracleRegistry() external view returns (address);
    function poolTokenFactory() external view returns (address);
    function multiPoolDAO() external view returns (address);
}

interface IMiningPoolDAO {
    function initialize(
        address spvAddress,
        address frostAddress,
        address _calculatorRegistry,
        address _stratumAggregator,
        address _stratumValidator,
        address _oracleRegistry,
        uint256 pubX,
        uint256 pubY,
        string calldata _poolId
    ) external;

    function setPayoutScript(bytes calldata script) external;
    function grantRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
    function ADMIN_ROLE() external pure returns (bytes32);
    function POOL_MANAGER_ROLE() external pure returns (bytes32);
}

interface IPoolTokenFactory {
    function createMpToken(string memory name, string memory symbol, address pool) external returns (address);
    function createMpTokenRestricted(string memory name, string memory symbol, address pool) external returns (address);
}

interface ICalculatorRegistry {
    function getCalculator(uint256 id) external returns (address);
}

contract PoolDeployerLite {
    address public factory;
    address public poolImplementation;

    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    constructor(address _factory, address _poolImpl) {
        factory = _factory;
        poolImplementation = _poolImpl;
    }

    struct DeployParams {
        address spv;
        address frost;
        address calcRegistry;
        address aggregator;
        address validator;
        address oracleRegistry;
        address tokenFactory;
        address multiPoolDAO;
    }

    function deployPool(
        address, // spvContract
        address, // frostCoordinator
        address, // calculatorRegistry
        address, // stratumDataAggregator
        address, // stratumDataValidator
        address, // oracleRegistry
        address, // poolTokenFactory
        address, // multiPoolDAO
        bytes calldata params
    ) external onlyFactory returns (address poolAddress, address mpTokenAddress) {
        // Extract addresses from factory
        DeployParams memory deps = DeployParams({
            spv: IMiningPoolFactoryCore(factory).spvContract(),
            frost: IMiningPoolFactoryCore(factory).frostCoordinator(),
            calcRegistry: IMiningPoolFactoryCore(factory).calculatorRegistry(),
            aggregator: IMiningPoolFactoryCore(factory).stratumDataAggregator(),
            validator: IMiningPoolFactoryCore(factory).stratumDataValidator(),
            oracleRegistry: IMiningPoolFactoryCore(factory).oracleRegistry(),
            tokenFactory: IMiningPoolFactoryCore(factory).poolTokenFactory(),
            multiPoolDAO: IMiningPoolFactoryCore(factory).multiPoolDAO()
        });
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

        // Get calculator
        address calculatorImpl = ICalculatorRegistry(deps.calcRegistry).getCalculator(calculatorId);
        require(calculatorImpl != address(0), "Invalid calculator");

        // Deploy minimal proxy
        bytes memory bytecode = abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            poolImplementation,
            hex"5af43d82803e903d91602b57fd5bf3"
        );

        bytes32 salt = keccak256(abi.encodePacked(asset, poolId, block.timestamp));
        assembly {
            poolAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(poolAddress != address(0), "Deployment failed");

        // Deploy MP token
        if (restrictedMp) {
            mpTokenAddress = IPoolTokenFactory(deps.tokenFactory).createMpTokenRestricted(
                mpName,
                mpSymbol,
                poolAddress
            );
        } else {
            mpTokenAddress = IPoolTokenFactory(deps.tokenFactory).createMpToken(
                mpName,
                mpSymbol,
                poolAddress
            );
        }

        // Initialize pool
        IMiningPoolDAO(poolAddress).initialize(
            deps.spv,
            deps.frost,
            deps.calcRegistry,
            deps.aggregator,
            deps.validator,
            deps.oracleRegistry,
            pubX,
            pubY,
            poolId
        );

        // Transfer admin roles to creator
        IMiningPoolDAO pool = IMiningPoolDAO(poolAddress);

        // First set payout script while we still have ADMIN_ROLE
        pool.setPayoutScript(payoutScript);

        // Grant roles to creator
        pool.grantRole(pool.ADMIN_ROLE(), creator);
        pool.grantRole(pool.POOL_MANAGER_ROLE(), creator);

        // Grant confirmer role too
        bytes32 CONFIRMER_ROLE = keccak256("CONFIRMER_ROLE");
        pool.grantRole(CONFIRMER_ROLE, creator);

        // Renounce our roles - keep DEFAULT_ADMIN_ROLE for now
        pool.renounceRole(pool.ADMIN_ROLE(), address(this));
        pool.renounceRole(pool.POOL_MANAGER_ROLE(), address(this));
        pool.renounceRole(CONFIRMER_ROLE, address(this));

        return (poolAddress, mpTokenAddress);
    }
}