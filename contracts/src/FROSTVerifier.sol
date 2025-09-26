// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title FROSTVerifier (multi-format)
 * @notice Verifies aggregated FROST signatures for Schnorr (BIP340) and ECDSA (DOGE)
 * @dev Implements IFROSTVerifier for FROSTCoordinator.sol
 *      Supports groupPubkey formats:
 *        - 64 bytes: abi.encodePacked(uint256 pubX, uint256 pubY) (uncompressed)
 *        - 33 bytes: SEC compressed (0x02/0x03 || X)
 *        - 32 bytes: x-only (BIP340, assumes even Y)
 *      Supports signature formats:
 *        - Schnorr: 96 bytes (Rx,Ry,z) or 64 bytes (Rx,z, even Ry)
 *        - ECDSA: 65-71 bytes (DER-encoded)
 *      Delegates to FROST.sol for Schnorr, OpenZeppelin ECDSA for DOGE
 */
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./vendor/cryptography/frost.sol";
import "./vendor/cryptography/Secp256k1.sol";

interface IFROSTVerifier {
    /// @dev Verifies an aggregated signature under groupPubkey and messageHash
    function verify(
        bytes calldata groupPubkey,
        bytes32 messageHash,
        bytes calldata signature,
        string calldata signatureType
    ) external view returns (bool ok);
}

contract FROSTVerifier is IFROSTVerifier {
    using ECDSA for bytes32;

    // Errors
    error InvalidSignatureType();
    error InvalidGroupPubkey();
    error InvalidSignature();
    error PointNotOnCurve();

    /**
     * @notice Verify an aggregated FROST signature
     * @param groupPubkey Public key (64, 33, or 32 bytes)
     * @param messageHash Hash of message (keccak256 for Schnorr, doubleSha256 for ECDSA)
     * @param signature Signature (96 or 64 bytes for Schnorr, 65-71 for ECDSA)
     * @param signatureType "Schnorr" for BTC/BCH/LTC, "ECDSA" for DOGE
     * @return ok True if signature is valid
     */
    function verify(
        bytes calldata groupPubkey,
        bytes32 messageHash,
        bytes calldata signature,
        string calldata signatureType
    ) external view override returns (bool ok) {
        if (keccak256(abi.encodePacked(signatureType)) == keccak256(abi.encodePacked("Schnorr"))) {
            return _verifySchnorr(groupPubkey, messageHash, signature);
        } else if (keccak256(abi.encodePacked(signatureType)) == keccak256(abi.encodePacked("ECDSA"))) {
            return _verifyECDSA(groupPubkey, messageHash, signature);
        } else {
            revert InvalidSignatureType();
        }
    }

    /**
     * @notice Verify a Schnorr signature (BIP340)
     * @param groupPubkey Public key (64, 33, or 32 bytes)
     * @param messageHash keccak256(message)
     * @param signature 96 bytes (Rx,Ry,z) or 64 bytes (Rx,z)
     */
    function _verifySchnorr(
        bytes calldata groupPubkey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view returns (bool) {
        // Decode groupPubkey to (pubX, pubY)
        (bool successPub, uint256 pubX, uint256 pubY) = _decodeGroupPubkey(groupPubkey);
        if (!successPub) revert InvalidGroupPubkey();

        // Decode signature to (rx, ry, z)
        (bool successSig, uint256 rx, uint256 ry, uint256 z) = _decodeSignature(signature);
        if (!successSig) revert InvalidSignature();

        // Delegate to FROST.sol for verification
        return FROST.verifySignature(pubX, pubY, rx, ry, z, messageHash);
    }

    /**
     * @notice Verify an ECDSA signature (for DOGE)
     * @param groupPubkey Public key (64 or 33 bytes)
     * @param messageHash doubleSha256(message)
     * @param signature DER-encoded ECDSA signature (65-71 bytes)
     */
    function _verifyECDSA(
        bytes calldata groupPubkey,
        bytes32 messageHash,
        bytes calldata signature
    ) internal view returns (bool) {
        // ECDSA supports only 64-byte or 33-byte pubkeys
        if (groupPubkey.length != 64 && groupPubkey.length != 33) revert InvalidGroupPubkey();
        if (signature.length < 65 || signature.length > 71) revert InvalidSignature();

        // Decode groupPubkey to (pubX, pubY)
        (bool successPub, uint256 pubX, uint256 pubY) = _decodeGroupPubkey(groupPubkey);
        if (!successPub) revert InvalidGroupPubkey();

        // Compute address from pubkey
        bytes memory pubkey = abi.encodePacked(pubX, pubY);
        address expected = address(uint160(uint256(keccak256(pubkey)) >> 96));

        // Recover address from signature
        address recovered = messageHash.recover(signature);
        if (recovered == address(0)) revert InvalidSignature();

        return recovered == expected;
    }

    /**
     * @dev Decode group public key (64, 33, or 32 bytes) to (X, Y)
     */
    function _decodeGroupPubkey(
        bytes calldata groupPubkey
    ) internal view returns (bool success, uint256 pubX, uint256 pubY) {
        // 64 bytes: (pubX||pubY)
        if (groupPubkey.length == 64) {
            (pubX, pubY) = abi.decode(groupPubkey, (uint256, uint256));
            if (!Secp256k1.isOnCurve(pubX, pubY)) return (false, 0, 0);
            return (true, pubX, pubY);
        }

        // 33 bytes: SEC compressed (0x02/0x03 || X)
        if (groupPubkey.length == 33) {
            bytes1 prefix = groupPubkey[0];
            if (prefix != 0x02 && prefix != 0x03) return (false, 0, 0);
            pubX = _readUint256FromCalldata(groupPubkey, 1);
            bool yIsOdd = (prefix == 0x03);
            pubY = Secp256k1.calculateY(pubX, yIsOdd);
            if (!Secp256k1.isOnCurve(pubX, pubY)) return (false, 0, 0);
            return (true, pubX, pubY);
        }

        // 32 bytes: x-only (BIP340, even Y)
        if (groupPubkey.length == 32) {
            pubX = _readUint256FromCalldata(groupPubkey, 0);
            pubY = Secp256k1.deriveY(pubX); // even Y
            if (!Secp256k1.isOnCurve(pubX, pubY)) return (false, 0, 0);
            return (true, pubX, pubY);
        }

        return (false, 0, 0);
    }

    /**
     * @dev Decode signature to (rx, ry, z) for Schnorr or check ECDSA format
     */
    function _decodeSignature(
        bytes calldata signature
    ) internal view returns (bool success, uint256 rx, uint256 ry, uint256 z) {
        // Schnorr: 96 bytes (Rx||Ry||z)
        if (signature.length == 96) {
            (rx, ry, z) = abi.decode(signature, (uint256, uint256, uint256));
            if (!Secp256k1.isOnCurve(rx, ry)) return (false, 0, 0, 0);
            return (true, rx, ry, z);
        }

        // Schnorr: 64 bytes (Rx||z, even Ry)
        if (signature.length == 64) {
            (rx, z) = abi.decode(signature, (uint256, uint256));
            ry = Secp256k1.deriveY(rx); // even Y
            if (!Secp256k1.isOnCurve(rx, ry)) return (false, 0, 0, 0);
            return (true, rx, ry, z);
        }

        // ECDSA: 65-71 bytes (DER-encoded, handled in _verifyECDSA)
        if (signature.length >= 65 && signature.length <= 71) {
            return (true, 0, 0, 0); // ECDSA verification doesn't need (rx,ry,z)
        }

        return (false, 0, 0, 0);
    }

    /**
     * @dev Read uint256 from bytes calldata at offset
     */
    function _readUint256FromCalldata(bytes calldata b, uint256 offset) internal pure returns (uint256 result) {
        require(b.length >= offset + 32, "read out of bounds");
        assembly {
            result := calldataload(add(b.offset, offset))
        }
    }
}