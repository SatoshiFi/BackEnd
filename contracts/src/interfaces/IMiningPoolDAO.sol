// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMiningPoolDAO {
    /// @notice Инициализация клонов пула (вызывается фабрикой сразу после деплоя)
    function initialize(
        address spvContract,
        address frostCoordinator,
        uint256 pubX,
        uint256 pubY
    ) external;

    /// @notice Провязка зависимостей пула (шаблоны выплат)
    function setPolicy(address policyTemplate) external;

    /// @notice Провязка зависимостей пула (двухслойные SBT)
    function setMembershipContracts(address membershipSBT, address roleBadgeSBT) external;

    /// @notice Установка адреса мультипул DAO
    function setMultiPoolDAO(address multiPoolDAO) external;

    /// @notice Установка адреса mp-токена (выпускается отдельно через фабрику токенов)
    function setPoolToken(address mpToken) external;
}
