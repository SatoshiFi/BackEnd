// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPoolTokenFactory {
    /// @notice Создаёт пул-специфичный mp-токен. Пример: mpBTC-pool001
    /// @param name   Полное имя токена (рекомендуется = символу, см. уникализацию)
    /// @param symbol Символ токена (например "mpBTC-pool001")
    /// @param pool   Адрес пула-владельца (минтер/бёрнер)
    /// @return token Адрес созданного ERC20
    function createMpToken(
        string calldata name,
        string calldata symbol,
        address pool
    ) external returns (address token);

    /// (на будущее) Создание S-токенов мультипула:
    /// function createSToken(string calldata name, string calldata symbol, address multiPoolDAO) external returns (address token);
}
