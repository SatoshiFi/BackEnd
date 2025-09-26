// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FieldOps
 * @dev Полевая арифметика над простым модулем P = secp256k1 prime
 */
library FieldOps {
    uint256 internal constant P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;

    function addmodP(uint256 x, uint256 y) internal pure returns (uint256) {
        return addmod(x, y, P);
    }

    function submodP(uint256 x, uint256 y) internal pure returns (uint256) {
        return addmod(x, P - y, P);
    }

    function mulmodP(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulmod(x, y, P);
    }

    function invmodP(uint256 x) internal view returns (uint256) {
        return _modExp(x, P - 2, P);
    }

    function _modExp(uint256 base, uint256 e, uint256 m) private view returns (uint256 result) {
        assembly {
            let freemem := mload(0x40)
            mstore(freemem, 0x20)         // base length
            mstore(add(freemem, 0x20), 0x20) // exponent length
            mstore(add(freemem, 0x40), 0x20) // modulus length
            mstore(add(freemem, 0x60), base)
            mstore(add(freemem, 0x80), e)
            mstore(add(freemem, 0xa0), m)
            if iszero(staticcall(not(0), 0x05, freemem, 0xc0, freemem, 0x20)) {
                revert(0, 0)
            }
            result := mload(freemem)
        }
    }
}
