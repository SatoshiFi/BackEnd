// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IBIP340Verifier.sol";
import "./vendor/cryptography/Schnorr.sol";

contract BIP340VerifierImpl is IBIP340Verifier {
    // Сигнатура оставлена прежней, но внутри x-only
    function verifySchnorr(
        uint256 pubkeyX,
        uint256 pubkeyY,
        uint256 rx,
        uint256 ry,
        uint256 s,
        bytes32 msgHash
    ) external view returns (bool) {
        return Schnorr.verifyXonly(pubkeyX, rx, s, msgHash);
    }

    // groupPubkey: 64 байта (x||y), signature: 64 (r||s)
    function verify(
        bytes calldata groupPubkey,
        bytes32 messageHash,
        bytes calldata signature
    ) external view returns (bool) {
        require(groupPubkey.length == 64, "invalid pubkey length");
        require(signature.length == 64, "invalid signature length");

        uint256 pubkeyX = uint256(bytes32(groupPubkey[:32]));
        uint256 r = uint256(bytes32(signature[:32]));
        uint256 s = uint256(bytes32(signature[32:]));

        return Schnorr.verifyXonly(pubkeyX, r, s, messageHash);
    }
}
