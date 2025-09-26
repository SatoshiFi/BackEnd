// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @notice Merkle proof verification for Bitcoin txids.
 * Important: this library expects that `leaf` and `siblings` are provided in the same byte-order
 * as the merkle root stored in block header. Convention in this repo:
 *  - all txid/blockhash values used in onchain functions are **wire double-sha256 output**, i.e. as produced by doubleSHA256(raw) (big-endian chunk)
 *  - if external tool provides txid as hex shown in explorers (reversed), caller must flip bytes before calling onchain functions.
 */
library MerkleProofLib {
    function verify(bytes32[] calldata siblings, uint256 index, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 h = leaf;
        for (uint256 i = 0; i < siblings.length; ++i) {
            bytes32 s = siblings[i];
            if ((index & 1) == 0) {
                h = _doubleSha256(abi.encodePacked(h, s));
            } else {
                h = _doubleSha256(abi.encodePacked(s, h));
            }
            index >>= 1;
        }
        return h == root;
    }

    function _doubleSha256(bytes memory data) private pure returns (bytes32) {
        return sha256(abi.encodePacked(sha256(data)));
    }
}
