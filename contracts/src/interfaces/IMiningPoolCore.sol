// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMiningPoolCore {
    struct UTXO {
        bool registered;
        bool spent;
        bool reserved;
        uint256 amountSat;
        bytes32 txHash;
        uint32 vout;
        uint256 reservedForRedemptionId;
    }
    function initialize(
        address spvContract,
        address frostCoordinator,
        address calculatorRegistry,
        address stratumDataAggregator,
        address stratumDataValidator,
        address oracleRegistry,
        uint256 pubX,
        uint256 pubY,
        string calldata poolId
    ) external;

    function setPayoutScript(bytes calldata script) external;
    function setCalculator(uint256 calculatorId) external;
    function setPolicy(address policy) external;
    function setMembershipContracts(address membershipSBT, address roleBadgeSBT) external;
    function setPoolToken(address token) external;
    function setMultiPoolDAO(address dao) external;
    function setRewardsContract(address rewards) external;
    function setExtensionsContract(address extensions) external;
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;

    function ADMIN_ROLE() external pure returns (bytes32);
    function groupPubkeyX() external view returns (uint256);
    function groupPubkeyY() external view returns (uint256);
    function calculatorId() external view returns (uint256);
    function poolId() external view returns (string memory);
    function minerWorkerAddresses(uint256 index) external view returns (address);
    function membershipSBT() external view returns (address);
    function roleBadgeSBT() external view returns (address);
    function poolToken() external view returns (address);
    function multiPoolDAO() external view returns (address);
    function getUTXO(bytes32 utxoKey) external view returns (UTXO memory);
    function updateUTXOState(bytes32 utxoKey, bool spent, bool reserved, uint256 redemptionId) external;
    function participants(address) external view returns (bool);
    function availableFor(address beneficiary) external view returns (uint256);
    function updateBalances(address beneficiary, uint256 amount, uint256 reserved) external;
    function minConfirmations() external view returns (uint256);
    function registerRewardStrict(
        bytes calldata blockHeaderRaw,
        bytes calldata txRaw,
        uint32 vout,
        bytes32[] calldata merkleProof,
        uint8[] calldata directions
    ) external;
    function minerShares(address miner) external view returns (uint256);
    function updateShares(address miner, uint256 amount) external;
}