// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMultiPoolDAO {
    function registerPool(address poolAddress) external;
    function unregisterPool(address poolAddress) external;
    function isRegisteredPool(address poolAddress) external view returns (bool);
    function getPoolCount() external view returns (uint256);
    function getPoolAt(uint256 index) external view returns (address);
    function executeProposal(uint256 proposalId) external;
    function createProposal(string memory description, bytes memory data) external returns (uint256);
    function voteOnProposal(uint256 proposalId, bool support) external;
    function receiveReward(
        bytes32 poolId,
        bytes calldata header,
        bytes calldata txRaw,
        uint32 vout,
        bytes32[] calldata merkleProof,
        uint8[] calldata directions
    ) external;
    function mintSToken(uint8 networkId, uint256 amount, address recipient) external;
    function selectUTXO(bytes32 poolId, uint8 networkId, uint256 amount) external returns (bytes32 txId, uint32 vout);
    function burnAndRedeem(bytes32 poolId, uint8 networkId, uint256 amount, address sender) external;
}
