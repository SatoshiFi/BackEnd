// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/BitcoinHash.sol";

/**
 * @notice Merkle proof verification for Bitcoin transaction id (txid).
 *
 * Условие: leaf и siblings должны быть в том же байтовом порядке (endianness),
 * что и merkleRoot, хранящийся в block header. В этом репозитории мы используем
 * wire-format double-sha256 output (sha256d) как стандартное представление.
 *
 * verify: берёт leaf, по списку siblings (от снизу к верх) и вычисляет root,
 * сравнивая с переданным root.
 */
library TxMerkleProof {
    /// @notice Проверяет inclusion proof.
    /// @param siblings массив sibling hashes (по уровню, снизу вверх)
    /// @param index позиция листа (начиная с 0) в уровне листьев (первоначальный индекс)
    /// @param root ожидаемый merkle root (как в block header)
    /// @param leaf txid (как bytes32)
    /// @return ok true если proof корректен
    function verify(bytes32[] calldata siblings, uint256 index, bytes32 root, bytes32 leaf) internal pure returns (bool ok) {
        bytes32 h = leaf;
        uint256 idx = index;

        for (uint256 i = 0; i < siblings.length; ++i) {
            bytes32 s = siblings[i];
            if ((idx & 1) == 0) {
                // current is left
                h = BitcoinHash.doubleSha256(abi.encodePacked(h, s));
            } else {
                // current is right
                h = BitcoinHash.doubleSha256(abi.encodePacked(s, h));
            }
            idx >>= 1;
        }
        return h == root;
    }
}
