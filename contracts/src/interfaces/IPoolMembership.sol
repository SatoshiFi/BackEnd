// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPoolMembership {
    function isMember(address account) external view returns (bool);
    function getMemberRole(address account) external view returns (bytes32);
    function addMember(address account) external;
    function removeMember(address account) external;
    function setMemberRole(address account, bytes32 role) external;
    function getMemberCount() external view returns (uint256);
    function getMemberAt(uint256 index) external view returns (address);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function btcScriptOf(uint256 tokenId) external view returns (bytes memory);
    function tokenOf(address owner) external view returns (uint256);
    function payoutOf(uint256 tokenId) external view returns (address evmPayout, string memory btcAddress, bytes32 btcXOnlyPub, bytes20 btcPubKeyHash);
}