// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MiningPoolStorage.sol";

/**
 * @title MiningPoolProxy
 * @notice Main proxy contract that delegates calls to implementation contracts
 * @dev Uses delegatecall to preserve storage context while splitting logic across multiple contracts
 */
contract MiningPoolProxy is MiningPoolStorage {
    // Mapping from function selector to implementation address
    mapping(bytes4 => address) public implementations;

    // Admin address for managing implementations
    address public proxyAdmin;

    // Events
    event ImplementationSet(bytes4 indexed selector, address indexed implementation);
    event ProxyAdminChanged(address indexed previousAdmin, address indexed newAdmin);

    modifier onlyProxyAdmin() {
        require(msg.sender == proxyAdmin, "Only proxy admin");
        _;
    }

    constructor() {
        proxyAdmin = msg.sender;
    }

    /**
     * @notice Set implementation address for a function selector
     * @param selector Function selector
     * @param implementation Address of implementation contract
     */
    function setImplementation(bytes4 selector, address implementation) external onlyProxyAdmin {
        require(implementation != address(0), "Invalid implementation");
        implementations[selector] = implementation;
        emit ImplementationSet(selector, implementation);
    }

    /**
     * @notice Set multiple implementations at once
     * @param selectors Array of function selectors
     * @param _implementations Array of implementation addresses
     */
    function setImplementations(
        bytes4[] memory selectors,
        address[] memory _implementations
    ) external onlyProxyAdmin {
        require(selectors.length == _implementations.length, "Length mismatch");

        for (uint256 i = 0; i < selectors.length; i++) {
            require(_implementations[i] != address(0), "Invalid implementation");
            implementations[selectors[i]] = _implementations[i];
            emit ImplementationSet(selectors[i], _implementations[i]);
        }
    }

    /**
     * @notice Change proxy admin
     * @param newAdmin New admin address
     */
    function changeProxyAdmin(address newAdmin) external onlyProxyAdmin {
        require(newAdmin != address(0), "Invalid admin");
        address oldAdmin = proxyAdmin;
        proxyAdmin = newAdmin;
        emit ProxyAdminChanged(oldAdmin, newAdmin);
    }

    /**
     * @notice Main fallback function that delegates calls to implementation contracts
     */
    fallback() external payable {
        // Get function selector from msg.data
        bytes4 selector;
        assembly {
            selector := calldataload(0)
        }

        // Get implementation address for this selector
        address implementation = implementations[selector];
        require(implementation != address(0), "Function not found");

        // Delegate call to implementation
        assembly {
            // Copy calldata to memory
            let calldataSize := calldatasize()
            let freeMemoryPointer := mload(0x40)
            calldatacopy(freeMemoryPointer, 0, calldataSize)

            // Perform delegatecall
            let result := delegatecall(
                gas(),
                implementation,
                freeMemoryPointer,
                calldataSize,
                0,
                0
            )

            // Get return data size
            let returnDataSize := returndatasize()

            // Copy return data to memory
            returndatacopy(freeMemoryPointer, 0, returnDataSize)

            // Return or revert based on result
            switch result
            case 0 {
                // Delegatecall failed, revert with error data
                revert(freeMemoryPointer, returnDataSize)
            }
            default {
                // Delegatecall succeeded, return data
                return(freeMemoryPointer, returnDataSize)
            }
        }
    }

    receive() external payable {
        // Accept ETH transfers
    }
}