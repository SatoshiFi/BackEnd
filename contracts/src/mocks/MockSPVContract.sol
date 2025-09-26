// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/ISPVContract.sol";

/**
 * @title MockSPVContract
 * @notice Simplified SPV for testing that doesn't validate proof-of-work
 */
contract MockSPVContract is ISPVContract {
    mapping(bytes32 => uint256) public blockHeight;
    mapping(bytes32 => bool) public blockExists;
    uint256 public currentHeight;

    error InvalidHeaderLength();

    function addBlockHeader(bytes calldata raw) external {
        if (raw.length != 80) revert InvalidHeaderLength();

        // Calculate block hash
        bytes32 blockHash = bytes32(sha256(abi.encodePacked(sha256(raw))));

        // Add block without PoW validation
        if (!blockExists[blockHash]) {
            currentHeight++;
            blockHeight[blockHash] = currentHeight;
            blockExists[blockHash] = true;
        }
    }

    function addBlockHeaderBatch(bytes[] calldata arr) external {
        for (uint256 i = 0; i < arr.length; i++) {
            this.addBlockHeader(arr[i]);
        }
    }

    // Additional helper for tests that need specific block hashes
    function addBlockWithHash(bytes32 blockHash, uint256 height) external {
        blockExists[blockHash] = true;
        blockHeight[blockHash] = height;
        if (height >= currentHeight) {
            currentHeight = height + 1;
        }
    }

    function checkTxInclusion(
        bytes32 blockHash,
        bytes32 txid,
        bytes32[] calldata siblings,
        uint256 index
    ) external view returns (bool) {
        // Simplified: just check block exists
        return blockExists[blockHash];
    }

    function isMature(bytes32 blockHash) external view returns (bool) {
        if (!blockExists[blockHash]) return false;

        // Check if we have 100+ blocks after this one
        return currentHeight >= blockHeight[blockHash] + 100;
    }

    function isMainChain(bytes32 blockHash) external view returns (bool) {
        return blockExists[blockHash];
    }

    function isSideChain(bytes32 blockHash) external pure returns (bool) {
        return false;
    }

    function isOrphaned(bytes32 blockHash) external pure returns (bool) {
        return false;
    }

    function chainWork(bytes32 blockHash) external view returns (uint256) {
        return blockHeight[blockHash];
    }

    function confirmations(bytes32 blockHash) external view returns (uint256) {
        if (!blockExists[blockHash]) return 0;
        return currentHeight - blockHeight[blockHash] + 1;
    }

    function mainChainHeight() external view returns (uint256) {
        return currentHeight;
    }

    // This version is used in tests (matches SPVContract implementation)
    // Note: ISPVContract interface has different signature with uint8[] directions

    // Implement ISPVContract version
    function checkTxInclusion(
        bytes32 blockHash,
        bytes32,
        bytes32[] calldata,
        uint8[] calldata
    ) external view returns (bool) {
        return blockExists[blockHash]; // Simplified for testing
    }

    function getBlockHash(uint64) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getBlockHeader(bytes32) external view returns (BlockData memory) {
        return BlockData({
            prevBlockHash: bytes32(0),
            merkleRoot: bytes32(0),
            version: 1,
            time: uint32(block.timestamp),
            nonce: uint32(0),
            bits: uint32(0x1d00ffff),
            blockHeight: 0
        });
    }

    function getBlockHeight(bytes32 blockHash) external view returns (uint64) {
        return uint64(blockHeight[blockHash]);
    }

    function getBlockInfo(bytes32 blockHash) external view returns (BlockInfo memory) {
        return BlockInfo({
            mainBlockData: BlockData({
                prevBlockHash: bytes32(0),
                merkleRoot: bytes32(0),
                version: 1,
                time: uint32(block.timestamp),
                nonce: uint32(0),
                bits: uint32(0x1d00ffff),
                blockHeight: uint64(blockExists[blockHash] ? blockHeight[blockHash] : 0)
            }),
            isInMainchain: blockExists[blockHash],
            cumulativeWork: blockExists[blockHash] ? blockHeight[blockHash] : 0,
            exists: blockExists[blockHash]
        });
    }

    function getBlockMerkleRoot(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function getBlockStatus(bytes32 blockHash) external view returns (bool isInMainchain, uint64 confirmations_) {
        isInMainchain = blockExists[blockHash];
        confirmations_ = uint64(currentHeight - blockHeight[blockHash] + 1);
    }

    function getBlockTarget(bytes32) external pure returns (bytes32) {
        return bytes32(uint256(0xffff0000000000000000000000000000000000000000000000000000));
    }

    function getLastEpochCumulativeWork() external view returns (uint256) {
        return currentHeight;
    }

    function getMainchainHead() external pure returns (bytes32) {
        return bytes32(0);
    }

    function getMainchainHeight() external view returns (uint64) {
        return uint64(currentHeight);
    }

    function isInMainchain(bytes32 blockHash) external view returns (bool) {
        return blockExists[blockHash];
    }
}