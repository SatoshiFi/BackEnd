// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMembershipSBT {
    function mint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function isSoulbound(uint256 tokenId) external view returns (bool);
    function setMetadata(uint256 tokenId, string memory metadata) external;
    function getMetadata(uint256 tokenId) external view returns (string memory);
    function tokenOfOwner(address owner) external view returns (uint256);
}