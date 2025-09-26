// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MultiPoolDAO
 * @notice Агрегатор наград из пулов + выпуск S-токенов (SBTC/SDOGE/SBCH/SLTC) и redeem с блокировкой.
 *         Поддерживает строгий режим mint: caller предоставляет SPV-пруф (blockHeaderRaw, txRaw, vout, merkleProof, directions)
 *         и конкретный poolId; контракт сам регистрирует UTXO (если не зарегистрирован), резервирует часть UTXO и минтит S-token.
 *
 * Важное:
 *  - mintSTokenWithProof(...) - строгий режим, требует SPV-пруфа и проверяет совпадение payoutScript пула.
 *  - mintSToken(networkId, amount, recipient) - legacy режим, может использоваться только пулом (onlyPool) и черпает из уже зарегистрированного backing.
 */
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./interfaces/ISPVContract.sol"; // Импортируем ISPVContract
import "./FROSTCoordinator.sol";
import "./libs/BitcoinUtils.sol";
import "./libs/BlockHeader.sol";
import "./core/BitcoinTxParser.sol";

interface ISTokenMinimal {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract MultiPoolDAO is AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");

    // -------- Network config
    struct NetworkConfig {
        bool active;
        address spv;       // SPV contract for this network
        address sToken;    // S-token contract (SBTC/SDOGE/...)
    }
    mapping(uint8 => NetworkConfig) public networks;

    // -------- Pools
    struct PoolInfo {
        bytes32 poolId;
        uint8   networkId;        // сеть пула (BTC/DOGE/...)
        bytes   payoutScript;     // scriptPubKey, на который приходят награды из майнинга
        bool    active;
    }
    // poolId => info
    mapping(bytes32 => PoolInfo) public pools;
    // для удобства: оператор пула → poolId (необязательно единственный)
    mapping(address => bytes32[]) public poolsByOperator;

    // -------- Backing reserves per network
    struct Backing {
        uint256 totalReceived;
        uint256 reserved;
        uint256 available;
    }
    mapping(uint8 => Backing) public backing;

    // -------- UTXO storage for coin-selection (пер сеть, пер пул)
    struct UTXO {
        bytes32 txId;
        uint32  vout;
        uint64  amount;
        bool    spent;
    }
    mapping(uint8 => mapping(bytes32 => UTXO[])) public poolUTXOs; // networkId => poolId => UTXO[]

    // -------- Redemption queue / lock
    enum RedemptionStatus { None, Locked, Processing, Finalized, Reverted }
    struct LockedTokens {
        uint8    networkId;
        address  owner;
        uint256  amount;       // netAmount (после удержания комиссии)
        bytes    powScript;
        bytes32  txId;
        uint64   createdAt;
        uint64   deadline;
        RedemptionStatus status;
    }
    uint256 public nextRequestId;
    mapping(uint256 => LockedTokens) public redemptions;
    mapping(uint8 => uint256[]) public redemptionQueueByNetwork;
    uint64 public defaultRedemptionTimeout;

    // -------- Custodians
    struct Custodian {
        uint256 deposit;
        bool    exists;
    }
    mapping(address => Custodian) public custodians;
    address[] private _custodianList;

    // -------- Fees
    mapping(uint8 => uint256) public feeAccrued; // per network

    // -------- Events
    event PoolRegistered(bytes32 indexed poolId, uint8 networkId, bytes payoutScript);
    event RewardReceived(uint8 indexed networkId, bytes32 indexed poolId, bytes32 txId, uint32 vout, uint64 amount);
    event UTXOAdded(uint8 indexed networkId, bytes32 indexed poolId, bytes32 txId, uint32 vout, uint64 amount);
    event STokensMinted(uint8 indexed networkId, address indexed to, uint256 amount);
    event FeesWithdrawn(uint8 indexed networkId, address to, uint256 amount);

    // -------- Init
    function initialize(
        address frostAddress,
        bytes calldata groupPub,
        uint64 redemptionTimeout,
        address slashRecv
    ) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        // defaults
        defaultRedemptionTimeout = redemptionTimeout;
    }

    // -------- Admin helpers
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Only admin");
        _;
    }

    modifier onlyPool() {
        require(hasRole(POOL_ROLE, msg.sender), "Only pool");
        _;
    }

    // -------- Network management
    function setNetwork(uint8 networkId, address spvAddr, address sToken, bool active) external onlyAdmin {
        networks[networkId] = NetworkConfig({active: active, spv: spvAddr, sToken: sToken});
    }

    // -------- Pool registration
    function registerPool(bytes32 poolId, uint8 networkId, bytes calldata payoutScript, address operator) external onlyAdmin {
        require(poolId != bytes32(0), "bad poolId");
        require(networks[networkId].active, "network inactive");
        pools[poolId] = PoolInfo({poolId: poolId, networkId: networkId, payoutScript: payoutScript, active: true});
        poolsByOperator[operator].push(poolId);
        emit PoolRegistered(poolId, networkId, payoutScript);
    }

    // -------- Core: receiveReward (с poolId и txRaw)
    function receiveReward(
        bytes32 poolId,
        bytes calldata blockHeaderRaw,
        bytes calldata txRaw,
        uint32 vout,
        bytes32[] calldata merkleProof,
        uint8[] calldata directions
    ) external whenNotPaused onlyPool nonReentrant {
        PoolInfo memory P = pools[poolId];
        require(P.active, "pool inactive");
        NetworkConfig memory nc = networks[P.networkId];
        require(nc.active && nc.spv != address(0), "network/SPV missing");

        ISPVContract spv = ISPVContract(nc.spv);
        spv.addBlockHeader(blockHeaderRaw);

        // Получаем blockHash
        (, bytes32 blockHash) = BlockHeader.parseHeader(blockHeaderRaw);

        // Считаем txid (без свидетелей)
        bytes memory noWit = BitcoinTxParser.stripWitness(txRaw);
        bytes32 txIdBE = BitcoinTxParser.doubleSha256(noWit);
        bytes32 txId = BitcoinTxParser.flipBytes32(txIdBE);

        bool ok = spv.checkTxInclusion(blockHash, txId, merkleProof, directions);
        require(ok, "SPV: merkle invalid");
        require(spv.isMature(blockHash) && spv.isInMainchain(blockHash), "not mature/main");

        // Извлекаем vout и проверяем, что scriptPubKey совпадает с пуловым payoutScript
        (uint64 outValue, bytes memory spk) = _extractVout(txRaw, vout);
        require(keccak256(spk) == keccak256(P.payoutScript), "wrong payout script");

        // Сохраняем UTXO пер-пул
        poolUTXOs[P.networkId][poolId].push(UTXO({
            txId: txId,
            vout: vout,
            amount: outValue,
            spent: false
        }));

        // Обновляем резервы сети
        Backing storage b = backing[P.networkId];
        b.totalReceived += outValue;
        b.available = b.totalReceived > b.reserved ? (b.totalReceived - b.reserved) : 0;

        emit RewardReceived(P.networkId, poolId, txId, vout, outValue);
        emit UTXOAdded(P.networkId, poolId, txId, vout, outValue);
    }

    // -------- Core: mintSToken (legacy - mints from already-registered backing)
    function mintSToken(
        uint8 networkId,
        uint256 amount,
        address recipient
    ) external whenNotPaused nonReentrant onlyPool {
        require(amount > 0, "zero amount");
        NetworkConfig memory nc = networks[networkId];
        require(nc.active && nc.sToken != address(0), "token not set");

        Backing storage b = backing[networkId];
        uint256 available = b.totalReceived > b.reserved ? (b.totalReceived - b.reserved) : 0;
        require(amount <= available, "insufficient backing");

        b.reserved += amount;
        b.available = b.totalReceived - b.reserved;

        ISTokenMinimal(nc.sToken).mint(recipient, amount);
        emit STokensMinted(networkId, recipient, amount);
    }

    // -------- Core: mintSTokenWithProof (strict)
    function mintSTokenWithProof(
        bytes32 poolId,
        bytes calldata blockHeaderRaw,
        bytes calldata txRaw,
        uint32 vout,
        bytes32[] calldata merkleProof,
        uint8[] calldata directions,
        uint256 amount,
        address recipient
    ) external whenNotPaused nonReentrant {
        require(amount > 0, "zero amount");
        PoolInfo memory P = pools[poolId];
        require(P.active, "pool inactive");
        NetworkConfig memory nc = networks[P.networkId];
        require(nc.active && nc.spv != address(0) && nc.sToken != address(0), "network misconfig");

        ISPVContract spv = ISPVContract(nc.spv);
        spv.addBlockHeader(blockHeaderRaw);

        // Вычисляем txid (без свидетелей)
        bytes memory noWit = BitcoinTxParser.stripWitness(txRaw);
        bytes32 txIdBE = BitcoinTxParser.doubleSha256(noWit);
        bytes32 txId = BitcoinTxParser.flipBytes32(txIdBE);

        // Получаем blockHash
        (, bytes32 blockHash) = BlockHeader.parseHeader(blockHeaderRaw);

        bool ok = spv.checkTxInclusion(blockHash, txId, merkleProof, directions);
        require(ok, "SPV: merkle invalid");
        require(spv.isMature(blockHash) && spv.isInMainchain(blockHash), "not mature/main");

        // Извлекаем vout и проверяем, что scriptPubKey совпадает с пуловым payoutScript
        (uint64 outValue, bytes memory spk) = _extractVout(txRaw, vout);
        require(keccak256(spk) == keccak256(P.payoutScript), "wrong payout script");

        // Находим существующий UTXO или регистрируем новый
        UTXO[] storage arr = poolUTXOs[P.networkId][poolId];
        uint256 idx = type(uint256).max;
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i].txId == txId && arr[i].vout == vout) {
                idx = i;
                break;
            }
        }
        Backing storage b = backing[P.networkId];
        if (idx == type(uint256).max) {
            // Регистрируем новый UTXO
            arr.push(UTXO({txId: txId, vout: vout, amount: outValue, spent: false}));
            idx = arr.length - 1;
            b.totalReceived += outValue;
            b.available = b.totalReceived > b.reserved ? (b.totalReceived - b.reserved) : 0;
            emit UTXOAdded(P.networkId, poolId, txId, vout, outValue);
        }

        UTXO storage u = arr[idx];
        require(!u.spent, "utxo spent");
        require(u.amount >= amount, "utxo too small");

        // Используем amount из UTXO (разрешено частичное использование)
        u.amount = u.amount - uint64(amount);
        if (u.amount == 0) {
            u.spent = true;
        }

        // Резервируем backing и минтим
        b.reserved += amount;
        b.available = b.totalReceived > b.reserved ? (b.totalReceived - b.reserved) : 0;

        ISTokenMinimal(nc.sToken).mint(recipient, amount);
        emit STokensMinted(P.networkId, recipient, amount);
    }

    // -------- Core: burnAndRedeem + lock (комиссия невозвратна)
    function burnAndRedeem(
        uint8 networkId,
        uint256 amount,
        bytes calldata powScript
    ) external whenNotPaused nonReentrant returns (uint256 requestId) {
        require(amount > 0, "zero amount");
        NetworkConfig memory nc = networks[networkId];
        require(nc.active && nc.sToken != address(0), "network/token not set");

        // Сжигаем sTokens
        ISTokenMinimal(nc.sToken).burnFrom(msg.sender, amount);

        // Вычисляем чистую сумму после комиссии (упрощённая логика: фиксированный процент или фиксированная комиссия)
        uint256 fee = 0;
        uint256 netAmount = amount - fee;

        // Блокируем токены
        requestId = ++nextRequestId;
        LockedTokens storage L = redemptions[requestId];
        L.networkId = networkId;
        L.owner = msg.sender;
        L.amount = netAmount;
        L.powScript = powScript;
        L.txId = bytes32(0);
        L.createdAt = uint64(block.timestamp);
        L.deadline = uint64(block.timestamp + defaultRedemptionTimeout);
        L.status = RedemptionStatus.Locked;

        redemptionQueueByNetwork[networkId].push(requestId);
        feeAccrued[networkId] += fee;

        return requestId;
    }

    // -------- Fees
    function withdrawFees(uint8 networkId, address to, uint256 amount) external onlyAdmin nonReentrant {
        require(to != address(0), "to=0");
        require(amount > 0 && amount <= feeAccrued[networkId], "bad amount");
        feeAccrued[networkId] -= amount;
        emit FeesWithdrawn(networkId, to, amount);
    }

    // -------- UTXO helpers (internal)
    function _extractVout(bytes calldata raw, uint32 index)
        internal
        pure
        returns (uint64 value, bytes memory scriptPubKey)
    {
        if (raw.length < 10) revert("Invalid tx");
        uint256 offset = 0;

        offset += 4;
        bool hasWitness = false;
        if (offset + 2 <= raw.length && raw[offset] == 0x00 && raw[offset+1] == 0x01) {
            hasWitness = true;
            offset += 2;
        }

        (uint256 vinCount, uint256 sz) = _readVarInt(raw, offset);
        offset += sz;
        for (uint i = 0; i < vinCount; ++i) {
            offset += 36;
            (uint256 sl, uint256 sls) = _readVarInt(raw, offset);
            offset += sls + sl;
            offset += 4;
        }

        (uint256 voutCount, uint256 vsz) = _readVarInt(raw, offset);
        offset += vsz;
        require(index < voutCount, "vout OOB");

        for (uint32 i = 0; i < voutCount; ++i) {
            uint64 val = uint64(uint8(raw[offset])) |
                         (uint64(uint8(raw[offset+1])) << 8) |
                         (uint64(uint8(raw[offset+2])) << 16) |
                         (uint64(uint8(raw[offset+3])) << 24) |
                         (uint64(uint8(raw[offset+4])) << 32) |
                         (uint64(uint8(raw[offset+5])) << 40) |
                         (uint64(uint8(raw[offset+6])) << 48) |
                         (uint64(uint8(raw[offset+7])) << 56);
            offset += 8;

            (uint256 pkLen, uint256 pks) = _readVarInt(raw, offset);
            offset += pks;

            if (i == index) {
                bytes memory spk = raw[offset:offset+pkLen];
                return (val, spk);
            }
            offset += pkLen;
        }

        if (hasWitness) {
            for (uint256 i = 0; i < vinCount; ++i) {
                (uint256 wc, uint256 wcs) = _readVarInt(raw, offset);
                offset += wcs;
                for (uint256 j = 0; j < wc; ++j) {
                    (uint256 wl, uint256 wls) = _readVarInt(raw, offset);
                    offset += wls + wl;
                }
            }
        }

        revert("output not found");
    }

    function _readVarInt(bytes calldata raw, uint256 offset) internal pure returns (uint256 value, uint256 size) {
        if (offset >= raw.length) revert("Invalid VarInt");
        uint8 fb = uint8(raw[offset]);
        if (fb < 0xFD) return (fb, 1);
        if (fb == 0xFD) {
            if (offset + 3 > raw.length) revert("Invalid VarInt");
            uint16 v = uint16(uint8(raw[offset+1])) | (uint16(uint8(raw[offset+2])) << 8);
            return (v, 3);
        }
        if (fb == 0xFE) {
            if (offset + 5 > raw.length) revert("Invalid VarInt");
            uint32 v = uint32(uint8(raw[offset+1])) |
                       (uint32(uint8(raw[offset+2])) << 8) |
                       (uint32(uint8(raw[offset+3])) << 16) |
                       (uint32(uint8(raw[offset+4])) << 24);
            return (v, 5);
        }
        if (offset + 9 > raw.length) revert("Invalid VarInt");
        uint256 vv;
        unchecked {
            for (uint i = 0; i < 8; ++i) {
                vv |= uint256(uint8(raw[offset + 1 + i])) << (8 * i);
            }
        }
        return (vv, 9);
    }

    // -------- Security hooks (gap)
    uint256[37] private __gap;
}
