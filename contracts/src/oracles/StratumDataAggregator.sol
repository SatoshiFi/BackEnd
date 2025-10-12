// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title StratumDataAggregator
 */
contract StratumDataAggregator
{
    struct WorkerData {
        address workerAddress;
        uint256 totalShares;
        uint256 validShares;
        uint256 lastSubmission;
        bool isActive;
    }

    struct AggregatedData {
        uint256 poolId;
        uint256 periodStart;
        uint256 periodEnd;
        uint256 totalShares;
        uint256 validShares;
        uint256 uniqueWorkers;
        uint256 avgDifficulty;
        bytes32 consensusHash;
        uint256 providerCount;
        uint256 agreedProviders;
        bool isFinalized;
        uint256 finalizedAt;
    }

    struct ProviderSubmission {
        address provider;
        bytes32 dataHash;
        uint256 totalShares;
        uint256 validShares;
        uint256 submittedAt;
        bool isValid;
    }

    struct AggregationPeriod {
        uint256 periodId;
        uint256 poolId;
        uint256 startTime;
        uint256 endTime;
        uint256 submissionDeadline;
        ProviderSubmission[] submissions;
        AggregatedData result;
        bool isActive;
    }

    struct MemberData
    {
        address member;
        address payoutAddress;
        uint256 aggregatedValidShares;
        uint256 aggregatedTotalShares;
        uint256 aggregatedHashRate;
        uint256 lastActivity;
        bool isActive;
        string workerId;
        uint256 hashRate;
    }

    address public oracleRegistry;
    address public admin;
    uint256 public periodCounter;
    uint256 public minProviders;
    uint256 public consensusThreshold;
    uint256 public submissionWindow;

    mapping(uint256 => AggregationPeriod) public periods;
    mapping(uint256 => uint256[]) public poolPeriods;
    mapping(address => bool) public authorizedProviders;
    mapping(bytes32 => uint256) public hashSubmissions;

    mapping(address => WorkerData) public workerData;
    mapping(address => address) public workerOwner;
    address[] public allWorkers;
    mapping(address => bool) internal isWorkerRegistered;

    mapping(address => address[]) public poolWorkers;
    mapping(address => mapping(address => bool)) internal isWorkerInPool;

    mapping(address => string) public workerBitcoinAddress;
    mapping(string => address) public workerIdToAddress;
    mapping(address => address[]) public minerWorkers;
    mapping(address => uint256) public workerLastActivity;

    event PeriodStarted(uint256 indexed periodId, uint256 indexed poolId, uint256 startTime, uint256 endTime);
    event DataSubmitted(uint256 indexed periodId, address indexed provider, bytes32 dataHash, uint256 totalShares);
    event ConsensusReached(uint256 indexed periodId, bytes32 consensusHash, uint256 agreedProviders);
    event PeriodFinalized(uint256 indexed periodId);
    event ProviderAuthorized(address indexed provider, bool authorized);
    event WorkerOwnerSet(address indexed worker, address indexed member);
    event WorkerRegisteredToPool(address indexed pool, address indexed worker);
    event WorkerDeregisteredFromPool(address indexed pool, address indexed worker);

    event WorkerRegisteredFull(
        address indexed workerAddress,
        address indexed minerAddress,
        string bitcoinAddress,
        string workerId
    );
    event WorkerStatsUpdated(
        address indexed workerAddress,
        uint256 totalShares,
        uint256 validShares
    );
    event BitcoinAddressUpdated(
        address indexed workerAddress,
        string newBitcoinAddress
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyOracleRegistry() {
        require(msg.sender == oracleRegistry, "Only oracle registry");
        _;
    }

    modifier onlyAuthorizedProvider() {
        require(authorizedProviders[msg.sender], "Not authorized provider");
        _;
    }

    modifier validPeriod(uint256 periodId) {
        require(periodId < periodCounter, "Invalid period ID");
        _;
    }

    modifier activePeriod(uint256 periodId) {
        require(periods[periodId].isActive, "Period not active");
        _;
    }

    constructor(address _oracleRegistry, address _admin) {
        oracleRegistry = _oracleRegistry;
        admin = _admin;
        periodCounter = 0;
        minProviders = 3;
        consensusThreshold = 6667;
        submissionWindow = 10 minutes;
    }

    function registerWorkerFull(
        address workerAddress,
        address minerAddress,
        string memory bitcoinAddress,
        string memory workerId
    ) external onlyAdmin {
        require(minerAddress != address(0), "Invalid miner address");
        require(bytes(bitcoinAddress).length > 0, "Invalid bitcoin address");
        require(bytes(workerId).length > 0, "Invalid worker ID");

        // If worker already has an owner, remove from old owner's array
        address currentOwner = workerOwner[workerAddress];
        if (currentOwner != address(0) && currentOwner != minerAddress) {
            address[] storage oldWorkers = minerWorkers[currentOwner];
            for (uint256 i = 0; i < oldWorkers.length; i++) {
                if (oldWorkers[i] == workerAddress) {
                    oldWorkers[i] = oldWorkers[oldWorkers.length - 1];
                    oldWorkers.pop();
                    break;
                }
            }
        }

        // Update ownership (overwrites if exists)
        workerOwner[workerAddress] = minerAddress;
        workerBitcoinAddress[workerAddress] = bitcoinAddress;
        workerIdToAddress[workerId] = workerAddress;

        // Add to new owner's array only if not already there
        if (currentOwner != minerAddress) {
            minerWorkers[minerAddress].push(workerAddress);
        }

        if (!isWorkerRegistered[workerAddress]) {
            allWorkers.push(workerAddress);
            isWorkerRegistered[workerAddress] = true;
        }

        workerLastActivity[workerAddress] = block.timestamp;

        emit WorkerRegisteredFull(workerAddress, minerAddress, bitcoinAddress, workerId);
    }

    function getWorkerOwnerByWorkerId(string memory workerId)
    external
    view
    returns (bool registered, address workerAddress, address minerAddress)
    {
        address wAddr = workerIdToAddress[workerId];
        if (wAddr == address(0)) {
            return (false, address(0), address(0));
        }
        address miner = workerOwner[wAddr];
        return (miner != address(0), wAddr, miner);
    }

    function getWorkersByMiner(address minerAddress)
    external
    view
    returns (address[] memory)
    {
        return minerWorkers[minerAddress];
    }

    function getMinerWorkerCount(address minerAddress)
    external
    view
    returns (uint256)
    {
        return minerWorkers[minerAddress].length;
    }

    function getWorkerBitcoinAddress(address workerAddress)
    external
    view
    returns (string memory)
    {
        return workerBitcoinAddress[workerAddress];
    }

    function getBitcoinAddressByWorkerId(string memory workerId)
    external
    view
    returns (string memory)
    {
        address wAddr = workerIdToAddress[workerId];
        require(wAddr != address(0), "Worker not found");
        return workerBitcoinAddress[wAddr];
    }

    function getWorkerInfo(address workerAddress)
    external
    view
    returns (
        bool registered,
        address owner,
        string memory bitcoinAddress,
        uint256 totalShares,
        uint256 validShares,
        uint256 lastActivity
    )
    {
        address currentOwner = workerOwner[workerAddress];
        WorkerData memory wd = workerData[workerAddress];
        return (
            currentOwner != address(0),
                currentOwner,
                workerBitcoinAddress[workerAddress],
                wd.totalShares,
                wd.validShares,
                workerLastActivity[workerAddress]
        );
    }

    function getWorkerInfoByWorkerId(string memory workerId)
    external
    view
    returns (
        bool registered,
        address workerAddress,
        address owner,
        string memory bitcoinAddress,
        uint256 totalShares,
        uint256 validShares,
        uint256 lastActivity
    )
    {
        address wAddr = workerIdToAddress[workerId];
        if (wAddr == address(0)) {
            return (false, address(0), address(0), "", 0, 0, 0);
        }

        address currentOwner = workerOwner[wAddr];
        WorkerData memory wd = workerData[wAddr];
        return (
            currentOwner != address(0),
                wAddr,
                currentOwner,
                workerBitcoinAddress[wAddr],
                wd.totalShares,
                wd.validShares,
                workerLastActivity[wAddr]
        );
    }

    function getTotalWorkersCount()
    external
    view
    returns (uint256)
    {
        return allWorkers.length;
    }

    function updateWorkerBitcoinAddress(
        address workerAddress,
        string memory newBitcoinAddress
    ) external {
        require(workerOwner[workerAddress] == msg.sender, "Not worker owner");
        require(bytes(newBitcoinAddress).length > 0, "Invalid bitcoin address");

        workerBitcoinAddress[workerAddress] = newBitcoinAddress;

        emit BitcoinAddressUpdated(workerAddress, newBitcoinAddress);
    }

    function setWorkerOwner(address worker, address member) external onlyAdmin {
        require(worker != address(0), "Invalid worker");
        require(member != address(0), "Invalid member");
        workerOwner[worker] = member;
        emit WorkerOwnerSet(worker, member);
    }

    function registerWorkerToPool(address pool, address worker) external onlyAuthorizedProvider {
        require(pool != address(0), "pool=0");
        require(worker != address(0), "worker=0");
        if (!isWorkerInPool[pool][worker]) {
            poolWorkers[pool].push(worker);
            isWorkerInPool[pool][worker] = true;
            emit WorkerRegisteredToPool(pool, worker);
        }
    }

    function deregisterWorkerFromPool(address pool, address worker) external onlyAdmin {
        require(isWorkerInPool[pool][worker], "not in pool");
        address[] storage arr = poolWorkers[pool];
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == worker) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                isWorkerInPool[pool][worker] = false;
                emit WorkerDeregisteredFromPool(pool, worker);
                return;
            }
        }
    }

    function aggregateMembers(uint256 /*poolId*/) external view returns (MemberData[] memory members) {
        if (allWorkers.length == 0) {
            return new MemberData[](0);
        }

        MemberData[] memory tmp = new MemberData[](allWorkers.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < allWorkers.length; i++) {
            address wAddr = allWorkers[i];
            WorkerData memory wd = workerData[wAddr];
            address owner = workerOwner[wAddr];
            if (owner == address(0)) continue;

            bool found = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tmp[j].member == owner) {
                    tmp[j].aggregatedTotalShares += wd.totalShares;
                    tmp[j].aggregatedValidShares += wd.validShares;
                    if (wd.lastSubmission > tmp[j].lastActivity) {
                        tmp[j].lastActivity = wd.lastSubmission;
                    }
                    if (wd.isActive) tmp[j].isActive = true;
                    found = true;
                    break;
                }
            }

            if (!found) {
                tmp[uniqueCount] = MemberData({
                    member: owner,
                    payoutAddress: owner,
                    aggregatedValidShares: wd.validShares,
                    aggregatedTotalShares: wd.totalShares,
                    aggregatedHashRate: 0,
                    lastActivity: wd.lastSubmission,
                    isActive: wd.isActive,
                    workerId: "",
                    hashRate: 0
                });
                uniqueCount++;
            }
        }

        members = new MemberData[](uniqueCount);
        for (uint256 k = 0; k < uniqueCount; k++) {
            members[k] = tmp[k];
        }
        return members;
    }

    function startAggregationPeriod(
        uint256 poolId,
        uint256 startTime,
        uint256 endTime
    )
    external onlyOracleRegistry returns (uint256 periodId)
    {
        require(endTime > startTime, "Invalid time range");
        require(startTime <= block.timestamp, "Start time in future");

        periodId = periodCounter++;

        periods[periodId] = AggregationPeriod({
            periodId: periodId,
            poolId: poolId,
            startTime: startTime,
            endTime: endTime,
            submissionDeadline: block.timestamp + submissionWindow,
            submissions: new ProviderSubmission[](0),
                                              result: AggregatedData({
                                                  poolId: poolId,
                                                  periodStart: startTime,
                                                  periodEnd: endTime,
                                                  totalShares: 0,
                                                  validShares: 0,
                                                  uniqueWorkers: 0,
                                                  avgDifficulty: 0,
                                                  consensusHash: bytes32(0),
                                                                     providerCount: 0,
                                                                     agreedProviders: 0,
                                                                     isFinalized: false,
                                                                     finalizedAt: 0
                                              }),
                                              isActive: true
        });

        poolPeriods[poolId].push(periodId);

        emit PeriodStarted(periodId, poolId, startTime, endTime);
        return periodId;
    }

    function submitData(
        uint256 periodId,
        bytes32 dataHash,
        uint256 totalShares,
        uint256 validShares,
        bytes memory signature
    ) external onlyAuthorizedProvider validPeriod(periodId) activePeriod(periodId) {
        AggregationPeriod storage period = periods[periodId];
        require(block.timestamp <= period.submissionDeadline, "Submission deadline passed");

        for (uint256 i = 0; i < period.submissions.length; i++) {
            require(period.submissions[i].provider != msg.sender, "Already submitted");
        }

        bool isValid = _validateSubmission(dataHash, totalShares, validShares, signature);

        period.submissions.push(ProviderSubmission({
            provider: msg.sender,
            dataHash: dataHash,
            totalShares: totalShares,
            validShares: validShares,
            submittedAt: block.timestamp,
            isValid: isValid
        }));

        hashSubmissions[dataHash]++;

        emit DataSubmitted(periodId, msg.sender, dataHash, totalShares);

        _checkConsensus(periodId);
    }

    function _validateSubmission(bytes32 dataHash, uint256 totalShares, uint256 validShares, bytes memory signature)
    internal pure returns (bool)
    {
        if (dataHash == bytes32(0)) return false;
        if (validShares > totalShares) return false;
        if (signature.length == 0) return false;
        return true;
    }

    function _checkConsensus(uint256 periodId) internal {
        AggregationPeriod storage period = periods[periodId];
        if (period.submissions.length < minProviders) return;

        (bytes32 consensusHash, uint256 agreedCount) = _findConsensusHash(periodId);
        uint256 requiredAgreement = (period.submissions.length * consensusThreshold) / 10000;

        if (agreedCount >= requiredAgreement) {
            period.result.consensusHash = consensusHash;
            period.result.agreedProviders = agreedCount;
            period.result.providerCount = period.submissions.length;

            emit ConsensusReached(periodId, consensusHash, agreedCount);
            _finalizePeriod(periodId);
        }
    }

    function _findConsensusHash(uint256 periodId) internal view returns (bytes32 consensusHash, uint256 maxCount) {
        AggregationPeriod storage period = periods[periodId];
        bytes32[] memory uniqueHashes = new bytes32[](period.submissions.length);
        uint256[] memory hashCounts = new uint256[](period.submissions.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < period.submissions.length; i++) {
            if (!period.submissions[i].isValid) continue;
            bytes32 hash = period.submissions[i].dataHash;
            bool found = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (uniqueHashes[j] == hash) {
                    hashCounts[j]++;
                    found = true;
                    break;
                }
            }
            if (!found) {
                uniqueHashes[uniqueCount] = hash;
                hashCounts[uniqueCount] = 1;
                uniqueCount++;
            }
        }

        for (uint256 i = 0; i < uniqueCount; i++) {
            if (hashCounts[i] > maxCount) {
                maxCount = hashCounts[i];
                consensusHash = uniqueHashes[i];
            }
        }

        return (consensusHash, maxCount);
    }

    function _finalizePeriod(uint256 periodId) internal {
        AggregationPeriod storage period = periods[periodId];
        (uint256 totalShares, uint256 validShares, uint256 avgDifficulty) = _aggregateConsensusData(periodId);

        period.result.totalShares = totalShares;
        period.result.validShares = validShares;
        period.result.avgDifficulty = avgDifficulty;
        period.result.isFinalized = true;
        period.result.finalizedAt = block.timestamp;
        period.isActive = false;

        emit PeriodFinalized(periodId);
    }

    function _aggregateConsensusData(uint256 periodId) internal view returns (uint256 avgTotalShares, uint256 avgValidShares, uint256 avgDifficulty) {
        AggregationPeriod storage period = periods[periodId];
        bytes32 consensusHash = period.result.consensusHash;

        uint256 consensusProviders = 0;
        uint256 sumTotalShares = 0;
        uint256 sumValidShares = 0;

        for (uint256 i = 0; i < period.submissions.length; i++) {
            ProviderSubmission memory submission = period.submissions[i];
            if (submission.isValid && submission.dataHash == consensusHash) {
                sumTotalShares += submission.totalShares;
                sumValidShares += submission.validShares;
                consensusProviders++;
            }
        }

        if (consensusProviders > 0) {
            avgTotalShares = sumTotalShares / consensusProviders;
            avgValidShares = sumValidShares / consensusProviders;
            avgDifficulty = avgValidShares > 0 ? (avgTotalShares * 1000) / avgValidShares : 0;
        }

        return (avgTotalShares, avgValidShares, avgDifficulty);
    }

    function finalizePeriod(uint256 periodId) external onlyAdmin validPeriod(periodId) activePeriod(periodId) {
        require(block.timestamp > periods[periodId].submissionDeadline, "Submission window not closed");
        _finalizePeriod(periodId);
    }

    function authorizeProvider(address provider, bool authorized) external onlyAdmin {
        authorizedProviders[provider] = authorized;
        emit ProviderAuthorized(provider, authorized);
    }

    function getAggregatedData(uint256 periodId) external view validPeriod(periodId) returns (AggregatedData memory) {
        return periods[periodId].result;
    }

    function getPeriodSubmissions(uint256 periodId) external view validPeriod(periodId) returns (ProviderSubmission[] memory) {
        return periods[periodId].submissions;
    }

    function getPoolPeriods(uint256 poolId) external view returns (uint256[] memory) {
        return poolPeriods[poolId];
    }

    function analyzeConsensusQuality(uint256 periodId) external view validPeriod(periodId) returns (uint256 totalProviders, uint256 validSubmissions, uint256 consensusStrength, uint256 disagreementCount) {
        AggregationPeriod storage period = periods[periodId];
        totalProviders = period.submissions.length;
        bytes32 consensusHash = period.result.consensusHash;
        uint256 agreedProviders = 0;

        for (uint256 i = 0; i < period.submissions.length; i++) {
            if (period.submissions[i].isValid) {
                validSubmissions++;
                if (period.submissions[i].dataHash == consensusHash) {
                    agreedProviders++;
                }
            }
        }

        consensusStrength = validSubmissions > 0 ? (agreedProviders * 10000) / validSubmissions : 0;
        disagreementCount = validSubmissions - agreedProviders;

        return (totalProviders, validSubmissions, consensusStrength, disagreementCount);
    }

    function updateParameters(uint256 _minProviders, uint256 _consensusThreshold, uint256 _submissionWindow) external onlyAdmin {
        require(_minProviders >= 1, "Min providers too low");
        require(_consensusThreshold >= 5000 && _consensusThreshold <= 10000, "Invalid threshold");
        require(_submissionWindow >= 1 minutes, "Submission window too short");
        minProviders = _minProviders;
        consensusThreshold = _consensusThreshold;
        submissionWindow = _submissionWindow;
    }

    function getAggregatorStats() external view returns (uint256 totalPeriods, uint256 finalizedPeriods, uint256 activePeriods, uint256 avgProvidersPerPeriod) {
        totalPeriods = periodCounter;
        uint256 totalProviders = 0;
        for (uint256 i = 0; i < periodCounter; i++) {
            if (periods[i].result.isFinalized) finalizedPeriods++;
            if (periods[i].isActive) activePeriods++;
            totalProviders += periods[i].submissions.length;
        }
        avgProvidersPerPeriod = totalPeriods > 0 ? totalProviders / totalPeriods : 0;
        return (totalPeriods, finalizedPeriods, activePeriods, avgProvidersPerPeriod);
    }

    function getWorkerData(address pool) external view returns (WorkerData[] memory) {
        address[] storage workers = poolWorkers[pool];
        if (workers.length == 0) {
            return new WorkerData[](0);
        }
        WorkerData[] memory result = new WorkerData[](workers.length);
        for (uint256 i = 0; i < workers.length; i++) {
            result[i] = workerData[workers[i]];
        }
        return result;
    }

    function updateWorkerData(address worker, uint256 totalShares, uint256 validShares, bool isActive) external onlyAuthorizedProvider {
        if (!isWorkerRegistered[worker]) {
            allWorkers.push(worker);
            isWorkerRegistered[worker] = true;
        }
        workerData[worker] = WorkerData({
            workerAddress: worker,
            totalShares: totalShares,
            validShares: validShares,
            lastSubmission: block.timestamp,
            isActive: isActive
        });
        workerLastActivity[worker] = block.timestamp;
        emit WorkerStatsUpdated(worker, totalShares, validShares);
    }

    function getAllWorkers() external view returns (address[] memory) {
        return allWorkers;
    }
}
