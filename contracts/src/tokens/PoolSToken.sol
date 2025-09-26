// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PoolSToken
 * @notice S-токен мультипула (например, SBTC/SDOGE/SLTC/SBCH).
 *         Минт/бёрн — только MultiPoolDAO. Без ограничений трансфера (дефолт dApp UX/DeFi-friendly).
 */
contract PoolSToken is ERC20, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    address public immutable multiPoolDAO;

    constructor(
        string memory name_,
        string memory symbol_,
        address multiPoolDAO_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        require(multiPoolDAO_ != address(0), "mpDAO=0");
        multiPoolDAO = multiPoolDAO_;
        _grantRole(DEFAULT_ADMIN_ROLE, multiPoolDAO_);
        _grantRole(MINTER_ROLE,        multiPoolDAO_);
        _grantRole(BURNER_ROLE,        multiPoolDAO_);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /// @notice Опциональный burnFrom для UX (по allowance)
    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}
