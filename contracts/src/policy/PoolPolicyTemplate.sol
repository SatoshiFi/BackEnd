// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title PoolPolicyTemplate
/// @notice Реестр ончейн-шаблонов выплат/комиссий для DAO пула
/// @dev Хранит параметры по templateId; Badge SBT несёт только ссылку (templateId)
contract PoolPolicyTemplate is AccessControl {
    // ------------------------
    //          Roles
    // ------------------------
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE; // Фабрика/совет пула
    bytes32 public constant EDITOR_ROLE = keccak256("EDITOR_ROLE"); // DAO пула может редактировать/создавать

    // ------------------------
    //        Storage
    // ------------------------
    enum PayoutMode { IMMEDIATE, THRESHOLD, SCHEDULED, PARTIAL }
    enum PayoutAsset { NATIVE, MP_TOKEN, S_TOKEN }

    struct TemplateParams {
        PayoutMode mode;        // режим выплат
        PayoutAsset asset;      // какой ассет выплачивать
        uint32 period;          // период для SCHEDULED (сек), 0 если не используется
        uint64 threshold;       // лимит для THRESHOLD в минимальных единицах (сатоши и т.п.)
        uint16 percent;         // процент для PARTIAL (0..10000 bps)
        uint16 feeBps;          // комиссия пула (bps)
        bytes32 assetId;        // идентификатор сети/ассета (keccak256("BTC"))
        bool deprecated;        // флаг деактивации
    }

    // templateId => params
    mapping(uint256 => TemplateParams) private _template;

    // дефолтный шаблон (используется если у участника нет бейджа)
    uint256 public defaultTemplateId;

    // ------------------------
    //          Events
    // ------------------------
    event TemplateDefined(uint256 indexed templateId, TemplateParams params);
    event TemplateUpdated(uint256 indexed templateId, TemplateParams params);
    event TemplateDeprecated(uint256 indexed templateId, bool deprecated);
    event DefaultTemplateSet(uint256 indexed templateId);

    constructor(address admin_) {
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(EDITOR_ROLE, admin_);
    }

    // ------------------------
    //         Mutators
    // ------------------------
    function defineTemplate(uint256 templateId, TemplateParams calldata params) external onlyRole(EDITOR_ROLE) {
        require(templateId != 0, "templateId=0 reserved");
        require(_template[templateId].assetId == bytes32(0), "already defined");
        require(_validate(params), "invalid params");
        _template[templateId] = params;
        emit TemplateDefined(templateId, params);
    }

    function updateTemplate(uint256 templateId, TemplateParams calldata params) external onlyRole(EDITOR_ROLE) {
        require(_template[templateId].assetId != bytes32(0), "not defined");
        require(_validate(params), "invalid params");
        _template[templateId] = params;
        emit TemplateUpdated(templateId, params);
    }

    function deprecateTemplate(uint256 templateId, bool flag) external onlyRole(EDITOR_ROLE) {
        require(_template[templateId].assetId != bytes32(0), "not defined");
        _template[templateId].deprecated = flag;
        emit TemplateDeprecated(templateId, flag);
    }

    function setDefaultTemplate(uint256 templateId) external onlyRole(ADMIN_ROLE) {
        require(_template[templateId].assetId != bytes32(0), "not defined");
        require(!_template[templateId].deprecated, "template deprecated");
        defaultTemplateId = templateId;
        emit DefaultTemplateSet(templateId);
    }

    // ------------------------
    //           Views
    // ------------------------
    function templateOf(uint256 templateId) external view returns (TemplateParams memory) {
        return _template[templateId];
    }

    function isDefined(uint256 templateId) external view returns (bool) {
        return _template[templateId].assetId != bytes32(0);
    }

    function isDeprecated(uint256 templateId) external view returns (bool) {
        return _template[templateId].deprecated;
    }

    /// @notice Вспомогательный расчёт для PARTIAL — разбиение суммы на payout и остаток
    function computePartial(uint256 amount, uint16 percentBps) public pure returns (uint256 payout, uint256 remainder) {
        if (percentBps == 0) return (0, amount);
        if (percentBps >= 10000) return (amount, 0);
        payout = amount * percentBps / 10000;
        remainder = amount - payout;
    }

    // ------------------------
    //        Validation
    // ------------------------
    function _validate(TemplateParams calldata p) internal pure returns (bool) {
        if (p.assetId == bytes32(0)) return false;
        if (p.feeBps > 5000) return false; // 50% потолок комиссии
        if (p.mode == PayoutMode.SCHEDULED && p.period == 0) return false;
        if (p.mode == PayoutMode.THRESHOLD && p.threshold == 0) return false;
        if (p.mode == PayoutMode.PARTIAL && p.percent == 0) return false;
        return true;
    }
}
