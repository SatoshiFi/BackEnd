// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library LibSortUint {
    function insertionSort(uint256[] memory a) internal pure {
        for (uint256 i = 1; i < a.length; ++i) {
            uint256 key = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > key) {
                a[j] = a[j - 1];
                unchecked { --j; }
            }
            a[j] = key;
        }
    }
}
