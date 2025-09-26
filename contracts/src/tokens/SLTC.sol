// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SLTC
 * @dev S-токен для LTC с полной DeFi совместимостью
 */
contract SLTC {

    // Стандартные переменные ERC20
    string public constant name = "SatoshiFi Litecoin";
    string public constant symbol = "SLTC";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    // Переменные управления
    address public multiPoolDAO;
    address public admin;
    bool public isPaused;
    bool public mintingEnabled;
    bool public burningEnabled;

    // Маппинги ERC20
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Расширенные маппинги
    mapping(address => uint256) public lockedBalances;     // Заблокированные для redemption
    mapping(address => bool) public authorizedMinters;     // Авторизованные для минтинга
    mapping(address => bool) public authorizedBurners;     // Авторизованные для сжигания
    mapping(address => bool) public blacklistedAddresses;  // Черный список
    mapping(address => uint256) public stakingBalances;    // Балансы в стейкинге

    // Структура для истории операций
    struct Transaction {
        address from;
        address to;
        uint256 amount;
        string txType;      // "mint", "burn", "transfer", "lock", "unlock", "stake", "unstake"
        uint256 timestamp;
        bytes32 externalRef;  // Ссылка на Bitcoin транзакцию
    }

    Transaction[] public transactionHistory;
    mapping(address => uint256[]) public userTransactions;

    // Структура информации о стейкинге
    struct StakingInfo {
        uint256 stakedAmount;    // Заставленная сумма
        uint256 rewardDebt;      // Долг по наградам
        uint256 lastStakeTime;   // Время последнего стейкинга
        uint256 lockUntil;       // Заблокировано до
    }

    mapping(address => StakingInfo) public stakingInfo;

    // Переменные для стейкинга
    uint256 public totalStaked;
    uint256 public rewardPerToken;
    uint256 public lastRewardTime;
    uint256 public stakingRewardRate;    // Награда за токен в секунду

    // События ERC20
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // Дополнительные события
    event Mint(address indexed to, uint256 amount, bytes32 indexed btcTxHash);
    event Burn(address indexed from, uint256 amount, bytes32 indexed btcTxHash);
    event BalanceLocked(address indexed account, uint256 amount, string reason);
    event BalanceUnlocked(address indexed account, uint256 amount);
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event RewardClaimed(address indexed account, uint256 amount);
    event ContractPaused(bool paused);
    event AuthorizationChanged(address indexed account, string role, bool authorized);

    // Модификаторы
    modifier onlyMultiPoolDAO() {
        require(msg.sender == multiPoolDAO, "Only MultiPoolDAO");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyAuthorizedMinter() {
        require(authorizedMinters[msg.sender], "Not authorized minter");
        _;
    }

    modifier onlyAuthorizedBurner() {
        require(authorizedBurners[msg.sender], "Not authorized burner");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    modifier whenMintingEnabled() {
        require(mintingEnabled, "Minting disabled");
        _;
    }

    modifier whenBurningEnabled() {
        require(burningEnabled, "Burning disabled");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklistedAddresses[account], "Address blacklisted");
        _;
    }

    modifier validAddress(address account) {
        require(account != address(0), "Invalid address");
        _;
    }

    constructor(address _multiPoolDAO, address _admin) {
        multiPoolDAO = _multiPoolDAO;
        admin = _admin;

        // Начальные настройки
        isPaused = false;
        mintingEnabled = true;
        burningEnabled = true;

        // Авторизация MultiPoolDAO
        authorizedMinters[_multiPoolDAO] = true;
        authorizedBurners[_multiPoolDAO] = true;

        // Инициализация стейкинга
        stakingRewardRate = 1e15; // 0.001 SBTC за токен в секунду (пример)
        lastRewardTime = block.timestamp;
    }

    /**
     * @dev Минтинг SBTC токенов (обеспечены Bitcoin)
     */
    function mint(address to, uint256 amount, bytes32 btcTxHash)
    external
    onlyAuthorizedMinter
    whenNotPaused
    whenMintingEnabled
    validAddress(to)
    notBlacklisted(to)
    {
        require(amount > 0, "Amount must be positive");

        totalSupply += amount;
        balanceOf[to] += amount;

        // Запись в историю
        _recordTransaction(address(0), to, amount, "mint", btcTxHash);

        emit Transfer(address(0), to, amount);
        emit Mint(to, amount, btcTxHash);
    }

    /**
     * @dev Сжигание SBTC токенов для вывода Bitcoin
     */
    function burn(address from, uint256 amount, bytes32 btcTxHash)
    external
    onlyAuthorizedBurner
    whenNotPaused
    whenBurningEnabled
    validAddress(from)
    {
        require(amount > 0, "Amount must be positive");
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(_getAvailableBalance(from) >= amount, "Insufficient unlocked balance");

        balanceOf[from] -= amount;
        totalSupply -= amount;

        // Запись в историю
        _recordTransaction(from, address(0), amount, "burn", btcTxHash);

        emit Transfer(from, address(0), amount);
        emit Burn(from, amount, btcTxHash);
    }

    /**
     * @dev Стандартный перевод ERC20
     */
    function transfer(address to, uint256 amount)
    external
    whenNotPaused
    validAddress(to)
    notBlacklisted(msg.sender)
    notBlacklisted(to)
    returns (bool)
    {
        return _transfer(msg.sender, to, amount);
    }

    /**
     * @dev Перевод от имени другого адреса
     */
    function transferFrom(address from, address to, uint256 amount)
    external
    whenNotPaused
    validAddress(to)
    notBlacklisted(from)
    notBlacklisted(to)
    returns (bool)
    {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }

    /**
     * @dev Внутренняя функция перевода
     */
    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(amount > 0, "Amount must be positive");
        require(_getAvailableBalance(from) >= amount, "Insufficient available balance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        // Запись в историю
        _recordTransaction(from, to, amount, "transfer", bytes32(0));

        emit Transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Одобрение трат
     */
    function approve(address spender, uint256 amount)
    external
    whenNotPaused
    validAddress(spender)
    notBlacklisted(msg.sender)
    notBlacklisted(spender)
    returns (bool)
    {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev Блокировка баланса для redemption
     */
    function lock(address account, uint256 amount, string memory reason)
    external
    onlyMultiPoolDAO
    whenNotPaused
    validAddress(account)
    {
        require(amount > 0, "Amount must be positive");
        require(_getAvailableBalance(account) >= amount, "Insufficient available balance");

        lockedBalances[account] += amount;

        // Запись в историю
        _recordTransaction(account, account, amount, "lock", bytes32(0));

        emit BalanceLocked(account, amount, reason);
    }

    /**
     * @dev Разблокировка баланса
     */
    function unlock(address account, uint256 amount)
    external
    onlyMultiPoolDAO
    whenNotPaused
    validAddress(account)
    {
        require(amount > 0, "Amount must be positive");
        require(lockedBalances[account] >= amount, "Insufficient locked balance");

        lockedBalances[account] -= amount;

        // Запись в историю
        _recordTransaction(account, account, amount, "unlock", bytes32(0));

        emit BalanceUnlocked(account, amount);
    }

    /**
     * @dev Стейкинг SBTC токенов
     */
    function stake(uint256 amount) external whenNotPaused notBlacklisted(msg.sender) {
        require(amount > 0, "Amount must be positive");
        require(_getAvailableBalance(msg.sender) >= amount, "Insufficient available balance");

        // Обновление наград перед изменением стейка
        _updateRewards(msg.sender);

        balanceOf[msg.sender] -= amount;
        stakingBalances[msg.sender] += amount;
        totalStaked += amount;

        StakingInfo storage info = stakingInfo[msg.sender];
        info.stakedAmount += amount;
        info.lastStakeTime = block.timestamp;

        // Запись в историю
        _recordTransaction(msg.sender, address(this), amount, "stake", bytes32(0));

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Анстейкинг SBTC токенов
     */
    function unstake(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be positive");
        require(stakingBalances[msg.sender] >= amount, "Insufficient staked balance");

        StakingInfo storage info = stakingInfo[msg.sender];
        require(block.timestamp >= info.lockUntil, "Staking is locked");

        // Обновление наград перед изменением стейка
        _updateRewards(msg.sender);

        stakingBalances[msg.sender] -= amount;
        balanceOf[msg.sender] += amount;
        totalStaked -= amount;

        info.stakedAmount -= amount;

        // Запись в историю
        _recordTransaction(address(this), msg.sender, amount, "unstake", bytes32(0));

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @dev Получение наград за стейкинг
     */
    function claimRewards() external whenNotPaused returns (uint256 reward) {
        _updateRewards(msg.sender);

        StakingInfo storage info = stakingInfo[msg.sender];
        reward = info.rewardDebt;

        if (reward > 0) {
            info.rewardDebt = 0;
            balanceOf[msg.sender] += reward;
            totalSupply += reward; // Награды увеличивают общее предложение

            emit RewardClaimed(msg.sender, reward);
            emit Transfer(address(0), msg.sender, reward);
        }

        return reward;
    }

    /**
     * @dev Обновление наград за стейкинг
     */
    function _updateRewards(address account) internal {
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 totalReward = timeElapsed * stakingRewardRate;

        if (totalReward > 0) {
            rewardPerToken += (totalReward * 1e18) / totalStaked;
        }

        lastRewardTime = block.timestamp;

        StakingInfo storage info = stakingInfo[account];
        if (info.stakedAmount > 0) {
            uint256 userReward = (info.stakedAmount * rewardPerToken) / 1e18 - info.rewardDebt;
            info.rewardDebt += userReward;
        }
    }

    /**
     * @dev Запись транзакции в историю
     */
    function _recordTransaction(
        address from,
        address to,
        uint256 amount,
        string memory txType,
        bytes32 externalRef
    ) internal {
        uint256 txIndex = transactionHistory.length;

        transactionHistory.push(Transaction({
            from: from,
            to: to,
            amount: amount,
            txType: txType,
            timestamp: block.timestamp,
            externalRef: externalRef
        }));

        // Добавление в пользовательские истории
        if (from != address(0)) {
            userTransactions[from].push(txIndex);
        }
        if (to != address(0) && to != from) {
            userTransactions[to].push(txIndex);
        }
    }

    /**
     * @dev Получение доступного баланса (не заблокированного и не в стейкинге)
     */
    function _getAvailableBalance(address account) internal view returns (uint256) {
        return balanceOf[account] - lockedBalances[account];
    }

    /**
     * @dev Получение доступного баланса (внешняя функция)
     */
    function availableBalanceOf(address account) external view returns (uint256) {
        return _getAvailableBalance(account);
    }

    /**
     * @dev Управление авторизацией минтеров
     */
    function setMinterAuthorization(address minter, bool authorized)
    external
    onlyAdmin
    validAddress(minter)
    {
        authorizedMinters[minter] = authorized;
        emit AuthorizationChanged(minter, "minter", authorized);
    }

    /**
     * @dev Управление авторизацией burner'ов
     */
    function setBurnerAuthorization(address burner, bool authorized)
    external
    onlyAdmin
    validAddress(burner)
    {
        authorizedBurners[burner] = authorized;
        emit AuthorizationChanged(burner, "burner", authorized);
    }

    /**
     * @dev Пауза/возобновление контракта
     */
    function setPaused(bool paused) external onlyAdmin {
        isPaused = paused;
        emit ContractPaused(paused);
    }

    /**
     * @dev Включение/выключение минтинга
     */
    function setMintingEnabled(bool enabled) external onlyAdmin {
        mintingEnabled = enabled;
    }

    /**
     * @dev Включение/выключение сжигания
     */
    function setBurningEnabled(bool enabled) external onlyAdmin {
        burningEnabled = enabled;
    }

    /**
     * @dev Управление черным списком
     */
    function setBlacklisted(address account, bool blacklisted)
    external
    onlyAdmin
    validAddress(account)
    {
        blacklistedAddresses[account] = blacklisted;
    }

    /**
     * @dev Установка ставки наград за стейкинг
     */
    function setStakingRewardRate(uint256 newRate) external onlyAdmin {
        _updateRewards(address(0)); // Обновление глобальных наград
        stakingRewardRate = newRate;
    }

    /**
     * @dev Получение истории транзакций пользователя
     */
    function getUserTransactions(address user) external view returns (uint256[] memory) {
        return userTransactions[user];
    }

    /**
     * @dev Получение общего количества транзакций
     */
    function getTransactionCount() external view returns (uint256) {
        return transactionHistory.length;
    }

    /**
     * @dev Получение ожидающих наград за стейкинг
     */
    function getPendingRewards(address account) external view returns (uint256) {
        if (totalStaked == 0) {
            return stakingInfo[account].rewardDebt;
        }

        uint256 timeElapsed = block.timestamp - lastRewardTime;
        uint256 totalReward = timeElapsed * stakingRewardRate;
        uint256 newRewardPerToken = rewardPerToken + (totalReward * 1e18) / totalStaked;

        StakingInfo memory info = stakingInfo[account];
        return info.rewardDebt + (info.stakedAmount * newRewardPerToken) / 1e18;
    }

    /**
     * @dev Получение статистики токена
     */
    function getTokenStats() external view returns (
        uint256 _totalSupply,
        uint256 _totalStaked,
        uint256 _totalLocked,
        uint256 _circulatingSupply,
        uint256 _stakingAPY
    ) {
        // Подсчет общих заблокированных средств (упрощенная версия)
        uint256 totalLocked = 0;

        // Расчет APY (упрощенная версия)
        uint256 annualReward = stakingRewardRate * 365 days;
        uint256 stakingAPY = totalStaked > 0 ? (annualReward * 10000) / totalStaked : 0;

        return (
            totalSupply,
            totalStaked,
            totalLocked,
            totalSupply - totalStaked - totalLocked,
            stakingAPY
        );
    }

    /**
     * @dev Смена администратора
     */
    function transferAdmin(address newAdmin) external onlyAdmin validAddress(newAdmin) {
        admin = newAdmin;
    }

    /**
     * @dev Экстренное восстановление средств
     */
    function emergencyRecovery(address account, uint256 amount)
    external
    onlyAdmin
    validAddress(account)
    {
        require(amount > 0, "Amount must be positive");
        require(amount <= balanceOf[account], "Amount exceeds balance");

        // Экстренная разблокировка всех средств
        lockedBalances[account] = 0;

        emit BalanceUnlocked(account, lockedBalances[account]);
    }
}
