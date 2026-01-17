// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IFROSTCoordinator.sol";
import "./initialFROST.sol";

/**
 * @title FrostSessionReader
 * @notice Utility contract for reading and validating FROST DKG session data
 * @dev Used by MiningPoolFactoryV6 to extract participant info from completed DKG sessions
 */
