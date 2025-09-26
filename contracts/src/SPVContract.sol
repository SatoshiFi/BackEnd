// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./libs/BlockHeader.sol";
import "./libs/TxMerkleProof.sol";
import "./libs/TargetsHelper.sol";
import "./libs/LibSortUint.sol";

contract SPVContract {
    uint8 public constant MEDIAN_PAST_BLOCKS = 11;
    uint32 public constant COINBASE_MATURITY = 100;

    struct BlockData {
        bytes32 prev;
        bytes32 merkleRoot;
        uint32 version;
        uint32 time;
        uint32 nonce;
        uint32 bits;
        uint64 height;
        uint256 cumulativeWork;
    }

    mapping(bytes32 => BlockData) internal blocks;
    mapping(uint64 => bytes32) internal height2hash;
    bytes32 internal mainchainHead;

    event BlockHeaderAdded(uint64 height, bytes32 blockHash);
    event MainchainHeadUpdated(uint64 height, bytes32 head);
    event ReorgOccurred(bytes32 oldHead, bytes32 newHead);

    error InvalidHeaderLength();
    error BlockAlreadyExists(bytes32);
    error PrevNotFound(bytes32);
    error InvalidTarget(uint256 blockTarget, uint256 expected);
    error InvalidBlockHash(bytes32, uint256);
    error InvalidBlockTime(uint32, uint32);
    error ReorgTooDeep();

    // ======== Views / Status ========

    function blockExists(bytes32 bh) public view returns (bool) {
        return blocks[bh].time != 0;
    }

    function isInMainchain(bytes32 bh) public view returns (bool) {
        uint64 h = blocks[bh].height;
        return h != 0 && height2hash[h] == bh;
    }

    /// @notice Возвращает (isInMainchain, confirmations)
    function getBlockStatus(bytes32 bh) external view returns (bool isIn, uint256 confirmations) {
        uint64 h = blocks[bh].height;
        if (h == 0) return (false, 0);
        isIn = (height2hash[h] == bh);
        if (!isIn) return (false, 0);

        uint64 headH = blocks[mainchainHead].height;
        confirmations = headH >= h ? uint256(headH - h + 1) : 0;
    }

    function isMature(bytes32 bh) external view returns (bool) {
        uint64 h = blocks[bh].height;
        if (h == 0 || !isInMainchain(bh)) return false;
        uint64 head = blocks[mainchainHead].height;
        return head >= h + COINBASE_MATURITY;
    }

    function getMainchainHead() external view returns (bytes32) { return mainchainHead; }
    function getMainchainHeight() external view returns (uint64) { return blocks[mainchainHead].height; }
    function getBlockMerkleRoot(bytes32 bh) external view returns (bytes32) { return blocks[bh].merkleRoot; }
    function getBlockHeight(bytes32 bh) external view returns (uint64) { return blocks[bh].height; }
    function getBlockHash(uint64 height) external view returns (bytes32) { return height2hash[height]; }

    function checkTxInclusion(
        bytes32 blockHash,
        bytes32 txid,
        bytes32[] calldata siblings,
        uint256 index
    ) external view returns (bool) {
        bytes32 root = blocks[blockHash].merkleRoot;
        return TxMerkleProof.verify(siblings, index, root, txid);
    }

    // ======== Mutations ========

    function addBlockHeader(bytes calldata raw) public {
        (BlockHeaderData memory h, bytes32 bh) = BlockHeader.parseHeader(raw);
        if (blocks[bh].time != 0) revert BlockAlreadyExists(bh);

        if (h.prevBlockHash != bytes32(0) && blocks[h.prevBlockHash].time == 0) {
            revert PrevNotFound(h.prevBlockHash);
        }

        uint64 height = (h.prevBlockHash == bytes32(0)) ? 0 : blocks[h.prevBlockHash].height + 1;

        (uint256 expectedTarget, uint32 medianTime) = _expectedTargetAndMTP(h.prevBlockHash, height);

        uint256 blockTarget = TargetsHelper.bitsToTarget(h.bits);
        if (blockTarget != expectedTarget) revert InvalidTarget(blockTarget, expectedTarget);
        if (uint256(bh) > blockTarget) revert InvalidBlockHash(bh, blockTarget);
        if (h.time <= medianTime) revert InvalidBlockTime(h.time, medianTime);

        _addBlock(h, bh, height);
    }

    function addBlockHeaderBatch(bytes[] calldata arr) external {
        require(arr.length > 0, "Empty batch");
        for (uint i = 0; i < arr.length; ++i) {
            addBlockHeader(arr[i]);
        }
    }

    // ======== Internals ========

    function _expectedTargetAndMTP(bytes32 prevHash, uint64 nextHeight)
        internal
        view
        returns (uint256 expectedTarget, uint32 medianTime)
    {
        if (prevHash == bytes32(0)) {
            expectedTarget = TargetsHelper.bitsToTarget(0x1d00ffff);
            medianTime = 0;
            return (expectedTarget, medianTime);
        }

        if (TargetsHelper.isAdjustmentBlock(nextHeight)) {
            bytes32 prev = prevHash;
            unchecked {
                for (uint i = 0; i < TargetsHelper.DIFFICULTY_ADJUSTMENT_INTERVAL - 1; ++i) {
                    prev = blocks[prev].prev;
                }
            }
            uint32 startTime = blocks[prev].time;
            uint32 endTime = blocks[prevHash].time;
            uint32 actual = endTime - startTime;

            uint256 prevTarget = TargetsHelper.bitsToTarget(blocks[prevHash].bits);
            expectedTarget = TargetsHelper.retarget(prevTarget, actual);
        } else {
            expectedTarget = TargetsHelper.bitsToTarget(blocks[prevHash].bits);
        }

        medianTime = _medianPastTime(prevHash);
    }

    function _medianPastTime(bytes32 toBlock) internal view returns (uint32) {
        uint256[] memory times = new uint256[](MEDIAN_PAST_BLOCKS); // исправлено: uint256[]
        bytes32 cursor = toBlock;
        uint256 count = 0;

        unchecked {
            while (cursor != bytes32(0) && count < MEDIAN_PAST_BLOCKS) {
                times[count++] = blocks[cursor].time; // uint32 → uint256
                cursor = blocks[cursor].prev;
            }
        }

        if (count == 0) return 0;
        if (count < MEDIAN_PAST_BLOCKS) return uint32(times[count - 1]);

        LibSortUint.insertionSort(times);
        return uint32(times[count / 2]); // возвращаем обратно в uint32
    }

    function _addBlock(BlockHeaderData memory h, bytes32 bh, uint64 height) internal {
        uint256 target = TargetsHelper.bitsToTarget(h.bits);
        uint256 work = TargetsHelper.workFromTarget(target);

        uint256 cumulative =
            (h.prevBlockHash == bytes32(0)) ? work : addmod(blocks[h.prevBlockHash].cumulativeWork, work, type(uint256).max);

        blocks[bh] = BlockData({
            prev: h.prevBlockHash,
            merkleRoot: h.merkleRoot,
            version: h.version,
            time: h.time,
            nonce: h.nonce,
            bits: h.bits,
            height: height,
            cumulativeWork: cumulative
        });

        if (mainchainHead == bytes32(0)) {
            mainchainHead = bh;
            height2hash[height] = bh;
            emit MainchainHeadUpdated(height, bh);
        } else {
            if (blocks[bh].cumulativeWork > blocks[mainchainHead].cumulativeWork) {
                _reorgTo(bh, height);
            } else if (h.prevBlockHash == mainchainHead) {
                mainchainHead = bh;
                height2hash[height] = bh;
                emit MainchainHeadUpdated(height, bh);
            }
        }

        emit BlockHeaderAdded(height, bh);
    }

    function _reorgTo(bytes32 newHead, uint64 height) internal {
        uint64 maxReorgDepth = 10;
        bytes32 cursor = newHead;
        uint64 h = height;
        bytes32 oldHead = mainchainHead;
        uint64 reorgCount = 0;

        unchecked {
            while (true) {
                if (height2hash[h] == cursor) break;
                height2hash[h] = cursor;

                bytes32 p = blocks[cursor].prev;
                if (p == bytes32(0)) break;

                cursor = p;
                --h;
                ++reorgCount;

                if (reorgCount > maxReorgDepth) revert ReorgTooDeep();
            }
        }

        mainchainHead = newHead;
        emit ReorgOccurred(oldHead, newHead);
        emit MainchainHeadUpdated(height, newHead);
    }
}
