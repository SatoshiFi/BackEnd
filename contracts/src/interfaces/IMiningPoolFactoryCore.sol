// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMiningPoolFactoryCore {
    function spvContract() external view returns (address);
    function frostCoordinator() external view returns (address);
    function calculatorRegistry() external view returns (address);
    function stratumDataAggregator() external view returns (address);
    function stratumDataValidator() external view returns (address);
    function oracleRegistry() external view returns (address);
    function poolTokenFactory() external view returns (address);
    function multiPoolDAO() external view returns (address);
}
