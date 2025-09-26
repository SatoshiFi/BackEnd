// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
interface ISPVContract {
    struct BlockData {
        bytes32 prevBlockHash;
        bytes32 merkleRoot;
        uint32 version;
        uint32 time;
        uint32 nonce;
        uint32 bits;
        uint64 blockHeight;
    }

    struct BlockInfo {
        BlockData mainBlockData;
        bool isInMainchain;
        uint256 cumulativeWork;
        bool exists;
    }

    event BlockHeaderAdded(uint64 blockHeight, bytes32 blockHash);
    event MainchainHeadUpdated(uint64 blockHeight, bytes32 blockHash);

    error PrevBlockDoesNotExist(bytes32 prevBlockHash);
    error BlockAlreadyExists(bytes32 blockHash);
    error EmptyBlockHeaderArray();
    error InvalidBlockHeadersOrder();
    error InvalidTarget(bytes32 got, bytes32 expected);
    error InvalidBlockHash(bytes32 blockHash, bytes32 target);
    error InvalidBlockTime(uint32 blockTime, uint32 medianTime);
    error InvalidInitialBlockHeight(uint64 blockHeight);

    function addBlockHeader(bytes calldata blockHeaderRaw) external;
    function addBlockHeaderBatch(bytes[] calldata blockHeaderRawArray) external;

    function checkTxInclusion(
        bytes32 blockHash,
        bytes32 txid,
        bytes32[] calldata merkleProof,
        uint8[] calldata directions
    ) external view returns (bool);

    function getMainchainHead() external view returns (bytes32);
    function getMainchainHeight() external view returns (uint64);
    function getBlockInfo(bytes32 blockHash) external view returns (BlockInfo memory);
    function getBlockHeader(bytes32 blockHash) external view returns (BlockData memory);
    function getBlockStatus(bytes32 blockHash) external view returns (bool isInMainchain, uint64 confirmations);
    function getBlockMerkleRoot(bytes32 blockHash) external view returns (bytes32);
    function getBlockHeight(bytes32 blockHash) external view returns (uint64);
    function getBlockHash(uint64 blockHeight) external view returns (bytes32);
    function getBlockTarget(bytes32 blockHash) external view returns (bytes32);
    function getLastEpochCumulativeWork() external view returns (uint256);
    function blockExists(bytes32 blockHash) external view returns (bool);
    function isInMainchain(bytes32 blockHash) external view returns (bool);
    function isMature(bytes32 blockHash) external view returns (bool); // Добавьте эту строку
}