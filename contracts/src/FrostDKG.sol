// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./vendor/cryptography/Secp256k1.sol";
import "./vendor/cryptography/Secp256k1Arithmetic.sol";
import "./vendor/cryptography/Memory.sol";
import "./vendor/cryptography/ModExp.sol";

/**
 * @title FrostDKG
 * @notice Implements FROST Distributed Key Generation with Shamir Secret Sharing
 * @dev This contract handles the cryptographic operations for FROST DKG
 */
