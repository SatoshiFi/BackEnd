// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {PoolMpToken} from "../tokens/PoolMpToken.sol";
import {PoolSToken} from "../tokens/PoolSToken.sol";

/**
 * @title PoolTokenFactory
 * @notice Выпускает пул-специфичные mp-токены и S-токены мультипула.
 * @dev Разделены права:
 *      - POOL_FACTORY_ROLE  — может выпускать mp-токены (используется MiningPoolFactory)
 *      - MULTIPOOL_ROLE     — может выпускать S-токены (используется MultiPoolDAO)
 */
contract PoolTokenFactory is AccessControl {
    bytes32 public constant POOL_FACTORY_ROLE = keccak256("POOL_FACTORY_ROLE");
    bytes32 public constant MULTIPOOL_ROLE    = keccak256("MULTIPOOL_ROLE");

    /// @notice Для удобства трека: (name, symbol, creator) → token
    mapping(bytes32 => address) public deployedTokens;

    event MpTokenCreated(
        address indexed token,
        string name,
        string symbol,
        address indexed poolDAO,
        address indexed creator
    );

    event STokenCreated(
        address indexed token,
        string name,
        string symbol,
        address indexed multiPoolDAO,
        address indexed creator
    );

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ------------------------
    //   mpToken factory
    // ------------------------

    /// @notice Базовый вариант: mp-токен без ограничений трансфера (совместим с MiningPoolFactory)
    function createMpToken(
        string memory name,
        string memory symbol,
        address poolDAO
    ) external onlyRole(POOL_FACTORY_ROLE) returns (address tokenAddr) {
        tokenAddr = _deployMp(name, symbol, poolDAO, false);
    }

    /// @notice Жёсткий вариант: mp-токен с ограниченными трансферами (по вайтлисту/DAO)
    function createMpTokenRestricted(
        string memory name,
        string memory symbol,
        address poolDAO
    ) external onlyRole(POOL_FACTORY_ROLE) returns (address tokenAddr) {
        tokenAddr = _deployMp(name, symbol, poolDAO, true);
    }

    function _deployMp(
        string memory name,
        string memory symbol,
        address poolDAO,
        bool restrictTransfer
    ) internal returns (address tokenAddr) {
        PoolMpToken token = new PoolMpToken(name, symbol, poolDAO, restrictTransfer);
        tokenAddr = address(token);

        bytes32 key = keccak256(abi.encodePacked(name, symbol, msg.sender));
        deployedTokens[key] = tokenAddr;

        emit MpTokenCreated(tokenAddr, name, symbol, poolDAO, msg.sender);
    }

    // ------------------------
    //   sToken factory
    // ------------------------

    /*function createSToken(
        string memory name,
        string memory symbol,
        address multiPoolDAO
    ) external onlyRole(MULTIPOOL_ROLE) returns (address tokenAddr) {
        PoolSToken token = new PoolSToken(name, symbol, multiPoolDAO);
        tokenAddr = address(token);

        bytes32 key = keccak256(abi.encodePacked(name, symbol, msg.sender));
        deployedTokens[key] = tokenAddr;

        emit STokenCreated(tokenAddr, name, symbol, multiPoolDAO, msg.sender);
    }
    */

    // ------------------------
    //   Helpers
    // ------------------------

    function getTokenAddress(
        string memory name,
        string memory symbol,
        address creator
    ) external view returns (address) {
        return deployedTokens[keccak256(abi.encodePacked(name, symbol, creator))];
    }
}
