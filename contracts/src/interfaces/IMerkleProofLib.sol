// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IMerkleProofLib {
    function verify(
        bytes32[] calldata proof,
        uint8[] calldata positions,
        bytes32 root,
        bytes32 leaf
    ) external pure returns (bool);
}
