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
