// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBIP340Verifier {
    function verifySchnorr(
        uint256 pubkeyX,
        uint256 pubkeyY,
        uint256 rx,
        uint256 ry,
        uint256 s,
        bytes32 msgHash
    ) external view returns (bool);

    function verify(
        bytes calldata groupPubkey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool);
}