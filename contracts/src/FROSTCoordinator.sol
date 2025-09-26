// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title FROSTCoordinator
 * @notice Ончейн-координатор FROST-сессий с поддержкой DKG и подписи:
 *  - Совместимость с MiningPoolDAO (createSessionWithId / finalizeSession(id,sig,msgHash))
 *  - Привязка messageHash позже (bind или в finalize)
 *  - Учёт отказов участников (refuse) для слешинга в DAO
 *  - Гибкая проверка порога (enforceSharesCheck true/false)
 *  - Поддержка внешнего верификатора (override на сессию)
 *  - Метаданные purpose/origin (тип операции и источник)
 *  - События-алиасы (SessionOpened) для старых агентов
 *  - Мультичейн поддержка (Schnorr для BTC/BCH/LTC, ECDSA для DOGE)
 *  - DKG с ончейн-хранением зашифрованных secret shares
 *
 * Валидация подписи делегирована IFROSTVerifier (BIP340 для Schnorr, ECDSA для DOGE).
 * Оффчейн агенты слушают события и исполняют MPC-протокол.
 */
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IFROSTCoordinator.sol";

interface IFROSTVerifier {
    function verify(
        bytes calldata groupPubkey,
        bytes32 messageHash,
        bytes calldata signature,
        string calldata signatureType
    ) external view returns (bool ok);
}

contract FROSTCoordinator is AccessControl, IFROSTCoordinator {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    // Убраны роли SESSION_CREATOR_ROLE и CONFIRMER_ROLE как отдельные сущности с админ-управлением
    // Теперь создание сессий открыто для всех, а подтверждение (finalize) доступно участникам сессии

    enum SessionState { NONE, OPENED, FINALIZED, ABORTED }
    enum SessionPurpose {
        UNKNOWN,
        WITHDRAWAL,
        SLASH,
        REDEMPTION,
        BRIDGE_OUT,
        BRIDGE_IN,
        DKG
    }

    struct OriginMeta {
        address originContract;
        uint256 originId;
        uint16 networkId;
        bytes32 poolId;
    }

    struct Session {
        uint256 id;
        address creator;
        bytes groupPubkey;
        bytes32 messageHash;
        bool messageBound;
        string signatureType;
        uint256 threshold;
        uint256 total;
        uint64 deadline;
        bool enforceSharesCheck;
        address verifierOverride;
        SessionState state;
        bytes aggregatedSig;
        EnumerableSet.AddressSet participants;
        mapping(address => bytes32) nonceCommitments;
        mapping(address => bytes) signatureShares;
        mapping(address => bool) refused;
        uint256 commitsCount;
        uint256 sharesCount;
        uint256 refusalCount;
        SessionPurpose purpose;
        OriginMeta origin;
        mapping(address => mapping(address => bytes)) dkgShares;
        uint256 dkgSharesCount;
    }

    uint256 public nextSessionId;
    mapping(uint256 => Session) private sessions;
    IFROSTVerifier public immutable defaultVerifier;
    EnumerableSet.AddressSet private custodians;

    // Added mapping for user sessions
    mapping(address => uint256[]) private userSessions;

    event SessionCreated(
        uint256 indexed sessionId,
        address indexed creator,
        bytes groupPubkey,
        bytes message,
        string signatureType,
        uint256 threshold,
        uint256 total,
        uint64 deadline,
        bool enforceSharesCheck,
        address verifierOverride,
        SessionPurpose purpose,
        OriginMeta origin
    );
    event SessionOpened(
        uint256 indexed sessionId,
        address indexed creator,
        bytes groupPubkey,
        uint256 threshold,
        uint256 total,
        uint64 deadline
    );
    event MessageBound(uint256 indexed sessionId, bytes32 messageHash);
    event ParticipantRefused(uint256 indexed sessionId, address indexed participant, string reason);
    event DeadlineExtended(uint256 indexed sessionId, uint64 newDeadline);
    event SessionFinalized(uint256 indexed sessionId, bytes aggregatedSignature, bytes32 messageHash);
    event SessionAborted(uint256 indexed sessionId, string reason);
    event NonceCommitted(uint256 indexed sessionId, address indexed participant, bytes32 commitment);
    event SignatureShareSubmitted(uint256 indexed sessionId, address indexed participant, bytes share);
    event DKGShareSubmitted(uint256 indexed sessionId, address indexed sender, address indexed recipient, bytes encryptedShare);
    event DKGCompleted(uint256 indexed sessionId, bytes groupPubkey);
    event CustodianAdded(address indexed custodian);
    event CustodianRemoved(address indexed custodian);

    error NotParticipant();
    error NotCreator();
    error SessionNotOpen();
    error SessionExpired();
    error DuplicateCommit();
    error DuplicateShare();
    error DuplicateRefusal();
    error BadThreshold();
    error BadTotal();
    error DeadlineInPast();
    error AlreadyFinalized();
    error AlreadyAborted();
    error InvalidSignature();
    error MessageAlreadyBound();
    error MessageMismatch();
    error InvalidSignatureType();
    error InvalidGroupPubkey();
    error InvalidDKGShare();
    error InsufficientDKGShares();

    constructor(address _defaultVerifier) {
        require(_defaultVerifier != address(0), "verifier=0");
        defaultVerifier = IFROSTVerifier(_defaultVerifier);
        _grantRole(ADMIN_ROLE, msg.sender);
        // Убраны _setRoleAdmin для SESSION_CREATOR_ROLE и CONFIRMER_ROLE
    }

    // Добавленная функция для реализации интерфейса
    function getCustodians() external view override returns (address[] memory) {
        return custodians.values();
    }

    function createSession(
        uint256 sessionId,
        bytes calldata groupPubkey,
        address[] calldata participants,
        uint256 threshold,
        uint256 deadline
    ) external override {  // Убрано onlyRole(SESSION_CREATOR_ROLE)
        if (groupPubkey.length != 32 && groupPubkey.length != 64) revert InvalidGroupPubkey();
        if (participants.length == 0) revert BadTotal();
        if (threshold == 0 || threshold > participants.length) revert BadThreshold();
        if (deadline <= block.timestamp) revert DeadlineInPast();

        OriginMeta memory emptyOrigin = OriginMeta({
            originContract: address(0),
            originId: 0,
            networkId: 0,
            poolId: bytes32(0)
        });

        _createSessionInternal(
            sessionId,
            groupPubkey,
            participants,
            threshold,
            uint64(deadline),
            false,
            address(0),
            SessionPurpose.DKG,
            emptyOrigin,
            "",
            "Schnorr"
        );
    }

    function createSession(
        uint256 sessionId,
        bytes calldata groupPubkey,
        bytes calldata message,
        string calldata signatureType,
        uint256 deadline
    ) external override {  // Убрано onlyRole(SESSION_CREATOR_ROLE)
        if (keccak256(abi.encodePacked(signatureType)) != keccak256(abi.encodePacked("Schnorr")) &&
            keccak256(abi.encodePacked(signatureType)) != keccak256(abi.encodePacked("ECDSA"))) {
            revert InvalidSignatureType();
        }
        if (keccak256(abi.encodePacked(signatureType)) == keccak256(abi.encodePacked("Schnorr")) && groupPubkey.length != 32) {
            revert InvalidGroupPubkey();
        }
        if (keccak256(abi.encodePacked(signatureType)) == keccak256(abi.encodePacked("ECDSA")) && groupPubkey.length != 64) {
            revert InvalidGroupPubkey();
        }

        address[] memory participants = new address[](0);
        OriginMeta memory emptyOrigin = OriginMeta({
            originContract: address(0),
            originId: 0,
            networkId: 0,
            poolId: bytes32(0)
        });
        _createSessionInternal(
            sessionId,
            groupPubkey,
            participants,
            0,
            uint64(deadline),
            false,
            address(0),
            SessionPurpose.UNKNOWN,
            emptyOrigin,
            message,
            signatureType
        );
    }

    function submitNonceCommit(uint256 sessionId, bytes32 commitment) external override {
        Session storage s = sessions[sessionId];
        _requireSessionOpen(s);
        if (!isParticipant(sessionId, msg.sender)) revert NotParticipant();
        if (s.nonceCommitments[msg.sender] != bytes32(0)) revert DuplicateCommit();

        s.nonceCommitments[msg.sender] = commitment;
        s.commitsCount += 1;
        if (!s.participants.contains(msg.sender)) {
            if (s.participants.add(msg.sender)) {
                userSessions[msg.sender].push(sessionId);
                s.total = s.participants.length();
            }
        }

        emit NonceCommitted(sessionId, msg.sender, commitment);
    }

    function submitSignatureShare(uint256 sessionId, bytes calldata share) external override {
        Session storage s = sessions[sessionId];
        _requireSessionOpen(s);
        if (!isParticipant(sessionId, msg.sender)) revert NotParticipant();
        if (s.signatureShares[msg.sender].length != 0) revert DuplicateShare();

        s.signatureShares[msg.sender] = share;
        s.sharesCount += 1;

        emit SignatureShareSubmitted(sessionId, msg.sender, share);
    }

    function submitDKGShare(uint256 sessionId, address recipient, bytes calldata encryptedShare) external {
        Session storage s = sessions[sessionId];
        _requireSessionOpen(s);
        if (s.purpose != SessionPurpose.DKG) revert InvalidDKGShare();
        if (!isParticipant(sessionId, msg.sender)) revert NotParticipant();
        if (!isParticipant(sessionId, recipient)) revert NotParticipant();
        if (s.dkgShares[msg.sender][recipient].length != 0) revert DuplicateShare();
        if (encryptedShare.length > 256) revert InvalidDKGShare();

        s.dkgShares[msg.sender][recipient] = encryptedShare;
        s.dkgSharesCount += 1;

        emit DKGShareSubmitted(sessionId, msg.sender, recipient, encryptedShare);
    }

    function finalizeDKG(uint256 sessionId, bytes calldata groupPubkey) external {
        // Заменено onlyRole(CONFIRMER_ROLE) на проверку isParticipant
        if (!isParticipant(sessionId, msg.sender)) revert NotParticipant();
        Session storage s = sessions[sessionId];
        _requireCanFinalize(s);
        if (s.purpose != SessionPurpose.DKG) revert InvalidDKGShare();
        if (s.dkgSharesCount < s.total * (s.total - 1)) revert InsufficientDKGShares();

        s.groupPubkey = groupPubkey;
        s.state = SessionState.FINALIZED;

        emit DKGCompleted(sessionId, groupPubkey);
    }

    function rejectSignatureRequest(uint256 sessionId, string calldata reason) external override {
        Session storage s = sessions[sessionId];
        _requireSessionOpen(s);
        if (!isParticipant(sessionId, msg.sender)) revert NotParticipant();
        if (s.refused[msg.sender]) revert DuplicateRefusal();

        s.refused[msg.sender] = true;
        s.refusalCount += 1;

        emit ParticipantRefused(sessionId, msg.sender, reason);
    }

    function getSession(uint256 sessionId)
        external
        view
        override
        returns (
            uint256 id,
            address creator,
            bytes memory groupPubkey,
            bytes32 messageHash,
            bool messageBound,
            uint256 threshold,
            uint256 total,
            uint64 deadline,
            bool enforceSharesCheck,
            address verifierOverride,
            uint256 state,
            uint256 commitsCount,
            uint256 sharesCount,
            uint256 refusalCount,
            uint256 purpose,
            address originContract,
            uint256 originId,
            uint16 networkId,
            bytes32 poolId,
            uint256 dkgSharesCount
        )
    {
        Session storage s = sessions[sessionId];
        id = s.id;
        creator = s.creator;
        groupPubkey = s.groupPubkey;
        messageHash = s.messageHash;
        messageBound = s.messageBound;
        threshold = s.threshold;
        total = s.total;
        deadline = s.deadline;
        enforceSharesCheck = s.enforceSharesCheck;
        verifierOverride = s.verifierOverride;
        state = uint256(s.state);
        commitsCount = s.commitsCount;
        sharesCount = s.sharesCount;
        refusalCount = s.refusalCount;
        purpose = uint256(s.purpose);
        originContract = s.origin.originContract;
        originId = s.origin.originId;
        networkId = s.origin.networkId;
        poolId = s.origin.poolId;
        dkgSharesCount = s.dkgSharesCount;
    }

    function getDKGShare(uint256 sessionId, address sender, address recipient) external view returns (bytes memory) {
        return sessions[sessionId].dkgShares[sender][recipient];
    }

    function participantsOf(uint256 sessionId) external view returns (address[] memory) {
        return sessions[sessionId].participants.values();
    }

    function isParticipant(uint256 sessionId, address who) public view returns (bool) {
        return sessions[sessionId].participants.contains(who);
    }

    function hasCommitted(uint256 sessionId, address who) external view returns (bool) {
        return sessions[sessionId].nonceCommitments[who] != bytes32(0);
    }

    function hasSubmittedShare(uint256 sessionId, address who) external view returns (bool) {
        return sessions[sessionId].signatureShares[who].length != 0;
    }

    function hasRefused(uint256 sessionId, address who) external view returns (bool) {
        return sessions[sessionId].refused[who];
    }

    function isFinalized(uint256 sessionId) external view returns (bool) {
        return sessions[sessionId].state == SessionState.FINALIZED;
    }

    function getResult(uint256 sessionId) external view returns (bytes memory sig, bytes32 msgHash) {
        Session storage s = sessions[sessionId];
        require(s.state == SessionState.FINALIZED, "not finalized");
        return (s.aggregatedSig, s.messageHash);
    }

    function createSession(
        bytes calldata groupPubkey,
        address[] calldata participants,
        uint256 threshold,
        uint64 deadline,
        bool enforceSharesCheck,
        address verifierOverride,
        SessionPurpose purpose,
        OriginMeta calldata origin
    ) external returns (uint256 sessionId) {  // Убрано onlyRole(SESSION_CREATOR_ROLE)
        sessionId = _createSessionInternal(
            0,
            groupPubkey,
            participants,
            threshold,
            deadline,
            enforceSharesCheck,
            verifierOverride,
            purpose,
            origin,
            "",
            "Schnorr"
        );
    }

    function createSessionWithId(
        uint256 explicitId,
        bytes calldata groupPubkey,
        address[] calldata participants,
        uint256 threshold,
        uint64 deadline
    ) external {  // Убрано onlyRole(SESSION_CREATOR_ROLE)
        OriginMeta memory emptyOrigin = OriginMeta({
            originContract: address(0),
            originId: 0,
            networkId: 0,
            poolId: bytes32(0)
        });
        _createSessionInternal(
            explicitId,
            groupPubkey,
            participants,
            threshold,
            deadline,
            false,
            address(0),
            SessionPurpose.DKG,
            emptyOrigin,
            "",
            "Schnorr"
        );
    }

    function _createSessionInternal(
        uint256 explicitId,
        bytes calldata groupPubkey,
        address[] memory participants,
        uint256 threshold,
        uint64 deadline,
        bool enforceSharesCheck,
        address verifierOverride,
        SessionPurpose purpose,
        OriginMeta memory origin,
        bytes memory message,
        string memory signatureType
    ) internal returns (uint256 sessionId) {
        if (participants.length == 0 && explicitId == 0) revert BadTotal();
        if (threshold > participants.length) revert BadThreshold();
        if (deadline <= block.timestamp) revert DeadlineInPast();
        if (keccak256(abi.encodePacked(signatureType)) != keccak256(abi.encodePacked("Schnorr")) &&
            keccak256(abi.encodePacked(signatureType)) != keccak256(abi.encodePacked("ECDSA"))) {
            revert InvalidSignatureType();
        }
        if (keccak256(abi.encodePacked(signatureType)) == keccak256(abi.encodePacked("Schnorr")) && groupPubkey.length != 32) {
            revert InvalidGroupPubkey();
        }
        if (keccak256(abi.encodePacked(signatureType)) == keccak256(abi.encodePacked("ECDSA")) && groupPubkey.length != 64) {
            revert InvalidGroupPubkey();
        }

        sessionId = explicitId == 0 ? ++nextSessionId : explicitId;
        Session storage s = sessions[sessionId];
        require(s.id == 0, "session exists");

        if (explicitId != 0 && explicitId > nextSessionId) {
            nextSessionId = explicitId;
        }

        s.id = sessionId;
        s.creator = msg.sender;
        s.groupPubkey = groupPubkey;
        s.messageHash = message.length > 0 ? keccak256(message) : bytes32(0);
        s.messageBound = message.length > 0;
        s.signatureType = signatureType;
        s.threshold = threshold;
        s.deadline = deadline;
        s.enforceSharesCheck = enforceSharesCheck;
        s.verifierOverride = verifierOverride;
        s.state = SessionState.OPENED;
        s.purpose = purpose;
        s.origin = origin;

        uint256 actualTotal = 0;
        for (uint256 i = 0; i < participants.length; i++) {
            address p = participants[i];
            if (p != address(0) && s.participants.add(p)) {
                userSessions[p].push(sessionId);
                actualTotal++;
            }
        }
        s.total = actualTotal;

        emit SessionCreated(
            sessionId,
            msg.sender,
            groupPubkey,
            message,
            signatureType,
            threshold,
            actualTotal,
            deadline,
            enforceSharesCheck,
            verifierOverride,
            purpose,
            origin
        );
        emit SessionOpened(sessionId, msg.sender, groupPubkey, threshold, actualTotal, deadline);
    }

    function bindMessageHash(uint256 sessionId, bytes32 messageHash) external {
        Session storage s = sessions[sessionId];
        _requireSessionOpen(s);
        if (s.creator != msg.sender) {
            _checkRole(ADMIN_ROLE, msg.sender);  // Оставлено для админа, так как bind может требовать привилегий
        }
        if (s.messageBound) revert MessageAlreadyBound();

        s.messageHash = messageHash;
        s.messageBound = true;

        emit MessageBound(sessionId, messageHash);
    }

    function extendDeadline(uint256 sessionId, uint64 newDeadline) external {
        Session storage s = sessions[sessionId];
        require(msg.sender == s.creator, "only creator");
        require(newDeadline > s.deadline && newDeadline > block.timestamp, "bad new deadline");
        s.deadline = newDeadline;
        emit DeadlineExtended(sessionId, newDeadline);
    }

    function finalizeSession(uint256 sessionId, bytes calldata aggregatedSignature, bytes32 messageHash)
        external
        override
    {
        // Заменено onlyRole(CONFIRMER_ROLE) на проверку isParticipant
        if (!isParticipant(sessionId, msg.sender)) revert NotParticipant();
        Session storage s = sessions[sessionId];
        _requireCanFinalize(s);

        if (!s.messageBound) {
            s.messageHash = messageHash;
            s.messageBound = true;
            emit MessageBound(sessionId, messageHash);
        } else {
            if (s.messageHash != messageHash) revert MessageMismatch();
        }

        _verifyAndFinalize(s, aggregatedSignature);
    }

    function _verifyAndFinalize(Session storage s, bytes calldata aggregatedSignature) internal returns (bool) {
        if (s.enforceSharesCheck) {
            require(s.sharesCount >= s.threshold, "shares < threshold");
        }

        IFROSTVerifier v = s.verifierOverride != address(0)
            ? IFROSTVerifier(s.verifierOverride)
            : defaultVerifier;

        bool ok = v.verify(s.groupPubkey, s.messageHash, aggregatedSignature, s.signatureType);
        if (!ok) revert InvalidSignature();

        s.state = SessionState.FINALIZED;
        s.aggregatedSig = aggregatedSignature;

        emit SessionFinalized(s.id, aggregatedSignature, s.messageHash);
        return true;
    }

    function abortSession(uint256 sessionId, string calldata reason) external {
        Session storage s = sessions[sessionId];
        if (s.state == SessionState.FINALIZED) revert AlreadyFinalized();
        if (s.state == SessionState.ABORTED) revert AlreadyAborted();
        require(msg.sender == s.creator, "only creator");

        s.state = SessionState.ABORTED;
        emit SessionAborted(sessionId, reason);
    }

    function _addParticipant(uint256 sessionId, address participant) internal {
        require(participant != address(0), "Invalid participant");
        Session storage s = sessions[sessionId];
        _requireSessionOpen(s);
        if (s.participants.contains(participant)) revert DuplicateCommit();
        s.participants.add(participant);
        userSessions[participant].push(sessionId);
        s.total = s.participants.length();
    }

    function addSessionParticipant(uint256 sessionId, address participant) external {
        Session storage s = sessions[sessionId];
        require(msg.sender == s.creator, "only creator");
        _addParticipant(sessionId, participant);
    }

    function setSessionThreshold(uint256 sessionId, uint256 threshold) external onlyRole(ADMIN_ROLE) {
        Session storage s = sessions[sessionId];
        _requireSessionOpen(s);
        if (threshold == 0 || threshold > s.total) revert BadThreshold();
        s.threshold = threshold;
    }

    function addCustodian(address custodian) external {
        Session storage s = sessions[0]; // Поскольку addCustodian глобально, но по запросу - только creator сессии. Однако сессия не указана, так что, возможно, ошибка. Я сделал доступным для creator любой сессии, но это слабо. Альтернатива: оставить onlyRole(ADMIN_ROLE), но по запросу изменил на проверку, является ли msg.sender creator'ом хотя бы одной сессии.
        bool isCreator = false;
        uint256[] memory userS = userSessions[msg.sender];
        for (uint256 i = 0; i < userS.length; i++) {
            if (sessions[userS[i]].creator == msg.sender) {
                isCreator = true;
                break;
            }
        }
        if (!isCreator) revert NotCreator();
        require(custodian != address(0), "custodian=0");
        if (custodians.add(custodian)) {
            // Убрано _grantRole(CONFIRMER_ROLE, custodian), так как роль упразднена
            emit CustodianAdded(custodian);
        }
    }

    function removeCustodian(address custodian) external onlyRole(ADMIN_ROLE) {
        if (custodians.remove(custodian)) {
            // Убрано _revokeRole(CONFIRMER_ROLE, custodian)
            emit CustodianRemoved(custodian);
        }
    }

    function _requireSessionOpen(Session storage s) internal view {
        if (s.state != SessionState.OPENED) revert SessionNotOpen();
        if (block.timestamp > s.deadline) revert SessionExpired();
    }

    function _requireCanFinalize(Session storage s) internal view {
        if (s.state == SessionState.FINALIZED) revert AlreadyFinalized();
        if (s.state == SessionState.ABORTED) revert AlreadyAborted();
        if (s.state != SessionState.OPENED) revert SessionNotOpen();
    }

    function getSessionParticipants(uint256 sessionId) external view override returns (address[] memory) {
        Session storage s = sessions[sessionId];
        return s.participants.values();
    }

    // Added functions for userSessions
    function getUserSessions(address user) external view returns (uint256[] memory) {
        return userSessions[user];
    }

    function getUserSessionCount(address user) external view returns (uint256) {
        return userSessions[user].length;
    }

    function getUserSessionByIndex(address user, uint256 index) external view returns (uint256) {
        require(index < userSessions[user].length, "Index out of bounds");
        return userSessions[user][index];
    }
}