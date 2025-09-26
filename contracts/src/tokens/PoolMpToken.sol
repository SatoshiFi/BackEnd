// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PoolMpToken
 * @notice Пул-специфичный mp-токен (например, mpBTC-pool001).
 *         Минт/бёрн — только DAO пула. Неизменяемо знает адрес DAO пула.
 *         Опционально может ограничивать трансферы (внутрипуловые переводы по вайтлисту).
 */
contract PoolMpToken is ERC20, ERC20Permit, AccessControl {
    // Роли (назначаются DAO пула в конструкторе)
    bytes32 public constant MINTER_ROLE         = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE         = keccak256("BURNER_ROLE");
    bytes32 public constant WHITELIST_MANAGER   = keccak256("WHITELIST_MANAGER");
    bytes32 public constant WHITELISTED_ACCOUNT = keccak256("WHITELISTED_ACCOUNT");

    /// @notice DAO пула, которому принадлежат админ-права
    address public immutable poolDAO;

    /// @notice Если true — включены ограничения трансферов (только вайтлист/DAO)
    bool public immutable restrictTransfer;

    event WhitelistUpdated(address indexed account, bool allowed);

    constructor(
        string memory name_,
        string memory symbol_,
        address poolDAO_,
        bool restrictTransfer_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        require(poolDAO_ != address(0), "poolDAO=0");
        poolDAO = poolDAO_;
        restrictTransfer = restrictTransfer_;

        // Делегируем полный контроль DAO пула
        _grantRole(DEFAULT_ADMIN_ROLE, poolDAO_);
        _grantRole(MINTER_ROLE,         poolDAO_);
        _grantRole(BURNER_ROLE,         poolDAO_);
        _grantRole(WHITELIST_MANAGER,   poolDAO_);
    }

    // -------------------
    // DAO-ограниченные API
    // -------------------

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /// @notice DAO (или делегаты с ролью) управляют вайтлистом получателей/отправителей
    function addToWhitelist(address account) external onlyRole(WHITELIST_MANAGER) {
        _grantRole(WHITELISTED_ACCOUNT, account);
        emit WhitelistUpdated(account, true);
    }

    function removeFromWhitelist(address account) external onlyRole(WHITELIST_MANAGER) {
        _revokeRole(WHITELISTED_ACCOUNT, account);
        emit WhitelistUpdated(account, false);
    }

    // -------------------
    // Ограничения трансфера
    // -------------------

    /**
     * @dev Если включён режим restrictTransfer:
     *  - mint/burn всегда разрешены (from==0 / to==0)
     *  - любые переводы разрешены DAO пула
     *  - иначе обе стороны должны быть в вайтлисте (или одна из них — DAO пула)
     */
    function _update(address from, address to, uint256 value) internal override {
        if (restrictTransfer) {
            bool minting = from == address(0);
            bool burning = to   == address(0);
            if (!(minting || burning)) {
                if (from != poolDAO && to != poolDAO) {
                    // проверяем обе стороны
                    require(
                        hasRole(WHITELISTED_ACCOUNT, from) &&
                        hasRole(WHITELISTED_ACCOUNT, to),
                        "mp: restricted transfer"
                    );
                }
            }
        }
        super._update(from, to, value);
    }
}
