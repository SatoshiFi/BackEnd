// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IFROSTCoordinator.sol";
import "./vendor/cryptography/Schnorr.sol";
import "./vendor/cryptography/Secp256k1.sol";
import "./vendor/cryptography/Utils.sol";
import "./vendor/cryptography/frost.sol";
import "./vendor/cryptography/Secp256k1Arithmetic.sol";
import "./vendor/cryptography/Memory.sol";
import "./vendor/cryptography/ModExp.sol";
import "./FrostDKG.sol";

contract initialFROSTCoordinator is IFROSTCoordinator {
    using Secp256k1 for *;
    using Schnorr for *;
    using Utils for *;

    enum SessionState { NONE, PENDING_COMMIT, PENDING_SHARES, READY, FINALIZED, ABORTED }
    enum SessionPurpose { UNKNOWN, WITHDRAWAL, SLASH, REDEMPTION, BRIDGE_OUT, BRIDGE_IN, DKG, KEY_GENERATION }

    struct Session {
        uint256 sessionId;
        address initiator;
        address creator; // Add creator field for compatibility
        uint32 threshold;
        uint32 totalParticipants;
        uint32 maxParticipants;
        uint32 currentPhase; // 0=OPENED, 1=COMMITMENTS, 2=SHARES, 3=FINALIZATION, 4=FINALIZED/ABORTED
        uint256 startTime;
        uint64 deadline; // Changed to uint64 for compatibility
        SessionState state; // Add explicit state field
        SessionPurpose purpose;
        bytes32 messageHash;
        bool messageBound;
        bytes32 groupPubKeyX; // X-coordinate of group public key
        bytes32 groupPubKeyY; // Y-coordinate of group public key (added for full key)
        mapping(address => bool) participants;
        mapping(address => bytes32) nonceCommitments;
        mapping(address => mapping(address => bytes)) dkgShares;
        mapping(address => bytes) signatureShares;
        mapping(address => uint256) participantShares; // Actual polynomial shares
        mapping(address => uint256) shareCommitments; // Public commitments
        uint32 joinedCount;
        uint32 submittedCommitments;
        uint32 submittedShares;
        uint32 refusalCount;
        bytes aggregatedSignature;
        bool enforceSharesCheck;
        address verifierOverride;
        address originContract;
        uint256 originId;
        uint16 networkId;
        bytes32 poolId;
        bool isSuccessful;
    }

    mapping(uint256 => Session) private sessions;
    mapping(uint256 => address[]) public sessionParticipants;

    uint256 public nextSessionId = 1;
    uint256 public constant MIN_THRESHOLD = 2;
    uint256 public constant MAX_PARTICIPANTS = 100;
    uint256 public constant SESSION_TIMEOUT = 1 days;
    uint256 public constant MAX_SHARE_SIZE = 256;

    uint256 private sessionNonce;

    // Events
    event SessionCreated(uint256 indexed sessionId, address initiator, SessionPurpose purpose, uint32 threshold, uint256 deadline);
    event SessionOpened(uint256 indexed sessionId, address initiator, SessionPurpose purpose);
    event ParticipantJoined(uint256 indexed sessionId, address participant);
    event PhaseStarted(uint256 indexed sessionId, uint32 phase);
    event NonceCommitted(uint256 indexed sessionId, address participant, bytes32 commitmentHash);
    event DKGShareSubmitted(uint256 indexed sessionId, address sender, address receiver, bytes encryptedShare);
    event SignatureShareSubmitted(uint256 indexed sessionId, address participant, bytes share);
    event SessionFinalized(uint256 indexed sessionId, bytes aggregatedSignature, address finalizer, bytes32 pubKeyX);
    event SessionFailed(uint256 indexed sessionId, string reason);

    modifier validSession(uint256 sessionId) {
        require(sessions[sessionId].startTime > 0, "Invalid session ID");
        _;
    }

    modifier notExpired(uint256 sessionId) {
        require(
            block.timestamp <= sessions[sessionId].startTime + SESSION_TIMEOUT,
            "Session expired"
        );
        _;
    }

    modifier onlyParticipant(uint256 sessionId) {
        require(sessions[sessionId].participants[msg.sender], "Not a participant");
        _;
    }
    modifier onlyInitiator(uint256 sessionId) {
        require(msg.sender == sessions[sessionId].initiator, "Not initiator");
        _;
    }
    modifier atPhase(uint256 sessionId, uint32 phase) {
        require(sessions[sessionId].currentPhase == phase, "Invalid phase");
        _;
    }
    modifier notTimedOut(uint256 sessionId) {
        require(block.timestamp <= sessions[sessionId].deadline, "Session timed out");
        _;
    }

    constructor() {}

    // -----------------------------
    // Utilities for bytes extraction
    // -----------------------------
    // extract bytes32 from calldata bytes at given offset
    function _bytes32FromCalldata(bytes calldata b, uint256 offset) internal pure returns (bytes32 out) {
        require(offset + 32 <= b.length, "out of range");
        assembly ("memory-safe") {
            out := calldataload(add(b.offset, offset))
        }
    }

    // extract bytes32 from memory bytes at given offset
    function _bytes32FromMemory(bytes memory b, uint256 offset) internal pure returns (bytes32 out) {
        require(offset + 32 <= b.length, "out of range");
        assembly ("memory-safe") {
            out := mload(add(add(b, 0x20), offset))
        }
    }

    // copy calldata bytes (single) to memory
    function _copyCalldataToMemory(bytes calldata b) internal pure returns (bytes memory mem) {
        mem = new bytes(b.length);
        // copy in chunks
        for (uint256 i = 0; i < b.length; i++) {
            mem[i] = b[i];
        }
    }

    // helper to build compressed pubkey (0x02 + x) with even Y assumption
    function _encodePubKey(bytes32 x, bytes32 y) internal pure returns (bytes memory) {
        // Return uncompressed format: 64 bytes (32 for X, 32 for Y)
        bytes memory pubKey = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            pubKey[i] = x[i];
            pubKey[32 + i] = y[i];
        }
        return pubKey;
    }

    // -----------------------------
    // Session lifecycle
    // -----------------------------

    // First createSession (explicit participants + compressed pubkey 33 bytes)
    function createSession(
        uint256 sessionId,
        bytes calldata groupPubkey,
        address[] calldata participants,
        uint256 threshold,
        uint256 deadline
    ) external override {
        require(threshold >= MIN_THRESHOLD, "Threshold too low");
        require(deadline > block.timestamp, "Invalid deadline");
        require(participants.length >= threshold && participants.length <= MAX_PARTICIPANTS, "Invalid participant count");
        require(groupPubkey.length == 33, "Invalid pubkey length");

        if (sessionId == 0) {
            sessionNonce++;
            sessionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.number, sessionNonce)));
        }
        require(sessions[sessionId].startTime == 0, "Session collision");

        // extract X from compressed pubkey (bytes[1..32])
        bytes32 pubKeyX = _bytes32FromCalldata(groupPubkey, 1);
        require(pubKeyX != bytes32(0) && uint256(pubKeyX) < Secp256k1.P, "Invalid pubkey x");

        // calculate Y (even) and check on curve
        uint256 py = Secp256k1.calculateY(uint256(pubKeyX), false);
        require(Secp256k1.isOnCurve(uint256(pubKeyX), py), "Pubkey not on curve");

        Session storage sess = sessions[sessionId];
        sess.sessionId = sessionId;
        sess.initiator = msg.sender;
        sess.threshold = uint32(threshold);
        sess.purpose = SessionPurpose.WITHDRAWAL; // Default for MiningPoolDAO
        sess.startTime = block.timestamp;
        sess.deadline = uint64(deadline);
        sess.currentPhase = 1; // COMMITMENTS phase
        sess.enforceSharesCheck = true;
        sess.groupPubKeyX = pubKeyX;

        for (uint i = 0; i < participants.length; i++) {
            _addParticipant(sessionId, participants[i]);
        }

        emit SessionCreated(sessionId, msg.sender, sess.purpose, sess.threshold, deadline);
        emit SessionOpened(sessionId, msg.sender, sess.purpose);
    }

    // Overload: createSession with message and signatureType (compact)
    function createSession(
        uint256 sessionId,
        bytes calldata groupPubkey,
        bytes calldata message,
        string calldata signatureType,
        uint256 deadline
    ) external override {
        require(deadline > block.timestamp, "Invalid deadline");
        require(groupPubkey.length == 33, "Invalid pubkey length");
        require(keccak256(abi.encodePacked(signatureType)) == keccak256(abi.encodePacked("Schnorr")), "Only Schnorr supported");

        if (sessionId == 0) {
            sessionNonce++;
            sessionId = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.number, sessionNonce)));
        }
        require(sessions[sessionId].startTime == 0, "Session collision");

        bytes32 pubKeyX = _bytes32FromCalldata(groupPubkey, 1);
        require(pubKeyX != bytes32(0) && uint256(pubKeyX) < Secp256k1.P, "Invalid pubkey x");
        uint256 py = Secp256k1.calculateY(uint256(pubKeyX), false);
        require(Secp256k1.isOnCurve(uint256(pubKeyX), py), "Pubkey not on curve");

        Session storage sess = sessions[sessionId];
        sess.sessionId = sessionId;
        sess.initiator = msg.sender;
        sess.threshold = uint32(MIN_THRESHOLD); // Default threshold
        sess.purpose = SessionPurpose.WITHDRAWAL; // Default for compatibility
        sess.startTime = block.timestamp;
        sess.deadline = uint64(deadline);
        sess.currentPhase = 1; // COMMITMENTS phase
        sess.messageHash = keccak256(message);
        sess.messageBound = true;
        sess.enforceSharesCheck = true;
        sess.groupPubKeyX = pubKeyX;

        emit SessionCreated(sessionId, msg.sender, sess.purpose, sess.threshold, deadline);
        emit SessionOpened(sessionId, msg.sender, sess.purpose);
    }

    // Internal create session logic
    function _createSessionInternal(
        bytes32 pubKeyX,
        bytes32 pubKeyY,
        address[] calldata initialParticipants,
        uint32 threshold,
        uint256 deadline,
        SessionPurpose purpose,
        bytes32 messageHash,
        address initiatorAddr
    ) internal returns (uint256) {
        require(threshold >= MIN_THRESHOLD, "Threshold too low");
        require(deadline > block.timestamp, "Invalid deadline");

        sessionNonce++;
        uint256 sessionId = uint256(keccak256(abi.encodePacked(initiatorAddr, block.timestamp, block.number, sessionNonce)));
        require(sessions[sessionId].startTime == 0, "Session collision");

        if (purpose == SessionPurpose.DKG) {
            require(pubKeyX == bytes32(0) && pubKeyY == bytes32(0), "DKG must not set pubkey");
            require(messageHash == bytes32(0), "Message hash not allowed for DKG");
        } else {
            require(pubKeyX != bytes32(0) && uint256(pubKeyX) < Secp256k1.P, "Invalid pubkey x");
            require(Secp256k1.isOnCurve(uint256(pubKeyX), uint256(pubKeyY)), "Pubkey not on curve");
            require(initialParticipants.length >= threshold && initialParticipants.length <= MAX_PARTICIPANTS, "Invalid participant count");
        }

        Session storage sess = sessions[sessionId];
        sess.sessionId = sessionId;
        sess.initiator = initiatorAddr;
        sess.threshold = threshold;
        sess.purpose = purpose;
        sess.startTime = block.timestamp;
        sess.deadline = uint64(deadline);
        sess.groupPubKeyX = pubKeyX;
        sess.messageHash = messageHash;
        sess.messageBound = messageHash != bytes32(0);
        sess.enforceSharesCheck = true;

        if (purpose == SessionPurpose.DKG) {
            sess.currentPhase = 1; // COMMITMENTS phase
            for (uint i = 0; i < initialParticipants.length; i++) {
                _addParticipant(sessionId, initialParticipants[i]);
            }
        } else {
            sess.maxParticipants = uint32(initialParticipants.length > 0 ? initialParticipants.length : MAX_PARTICIPANTS);
            sess.currentPhase = 0; // OPENED phase for DKG
            if (initialParticipants.length > 0) {
                for (uint i = 0; i < initialParticipants.length; i++) {
                    _addParticipant(sessionId, initialParticipants[i]);
                }
            }
        }

        emit SessionCreated(sessionId, initiatorAddr, purpose, threshold, deadline);
        emit SessionOpened(sessionId, initiatorAddr, purpose);
        return sessionId;
    }

    // createSession (full XY version) - returns sessionId
    function createSession(
        bytes32 pubKeyX,
        bytes32 pubKeyY,
        address[] calldata initialParticipants,
        uint32 threshold,
        uint256 deadline,
        SessionPurpose purpose,
        bytes32 messageHash
    ) external returns (uint256) {
        return _createSessionInternal(pubKeyX, pubKeyY, initialParticipants, threshold, deadline, purpose, messageHash, msg.sender);
    }

    // convenience overload
    function createSession(
        bytes32 pubKeyX,
        bytes32 pubKeyY,
        address[] calldata initialParticipants,
        uint32 threshold,
        uint256 deadline,
        SessionPurpose purpose
    ) external returns (uint256) {
        return _createSessionInternal(pubKeyX, pubKeyY, initialParticipants, threshold, deadline, purpose, bytes32(0), msg.sender);
    }

    function joinSession(uint256 sessionId) external validSession(sessionId) atPhase(sessionId, 0) notTimedOut(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.purpose == SessionPurpose.DKG, "Only for DKG");
        require(sess.joinedCount < sess.maxParticipants, "Max participants reached");
        require(!sess.participants[msg.sender], "Already joined");

        _addParticipant(sessionId, msg.sender);
        sess.joinedCount++;
        emit ParticipantJoined(sessionId, msg.sender);
    }

    function _addParticipant(uint256 sessionId, address participant) internal {
        require(participant != address(0), "Invalid participant");
        Session storage sess = sessions[sessionId];
        require(!sess.participants[participant], "Already added");
        sess.participants[participant] = true;
        sessionParticipants[sessionId].push(participant);
        sess.totalParticipants++;
    }

    function advancePhase(uint256 sessionId) external validSession(sessionId) onlyInitiator(sessionId) notTimedOut(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.currentPhase < 3, "Session completed");

        if (sess.purpose == SessionPurpose.DKG) {
            if (sess.currentPhase == 0) {
                require(sess.totalParticipants >= sess.threshold, "Not enough participants");
                sess.currentPhase = 1;
            } else if (sess.currentPhase == 1 && sess.submittedCommitments == sess.totalParticipants) {
                sess.currentPhase = 2;
            } else if (sess.currentPhase == 2 && sess.submittedShares == sess.totalParticipants * (sess.totalParticipants - 1)) {
                sess.currentPhase = 3;
            } else {
                revert("Cannot advance phase");
            }
        } else {
            if (sess.currentPhase == 1 && sess.submittedCommitments == sess.totalParticipants) {
                sess.currentPhase = 2;
            } else if (sess.currentPhase == 2 && (!sess.enforceSharesCheck || sess.submittedShares >= sess.threshold)) {
                sess.currentPhase = 3;
            } else {
                revert("Cannot advance phase");
            }
        }

        emit PhaseStarted(sessionId, sess.currentPhase);
    }

    // -----------------------------
    // Commitments & shares
    // -----------------------------

    function submitNonceCommit(uint256 sessionId, bytes32 commitment) external override validSession(sessionId) onlyParticipant(sessionId) atPhase(sessionId, 1) notTimedOut(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.nonceCommitments[msg.sender] == bytes32(0), "Already submitted");
        sess.nonceCommitments[msg.sender] = commitment;
        sess.submittedCommitments++;
        emit NonceCommitted(sessionId, msg.sender, commitment);
    }

    function submitDKGShare(uint256 sessionId, address recipient, bytes calldata encryptedShare) external override validSession(sessionId) onlyParticipant(sessionId) atPhase(sessionId, 2) notTimedOut(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.purpose == SessionPurpose.DKG, "Only for DKG");
        require(sess.participants[recipient], "Invalid receiver");
        require(recipient != msg.sender, "No self share");
        require(encryptedShare.length <= MAX_SHARE_SIZE, "Share too large");
        require(sess.dkgShares[msg.sender][recipient].length == 0, "Already submitted");

        sess.dkgShares[msg.sender][recipient] = encryptedShare;
        sess.submittedShares++;
        emit DKGShareSubmitted(sessionId, msg.sender, recipient, encryptedShare);
    }

    function submitSignatureShare(uint256 sessionId, bytes calldata share) external override validSession(sessionId) onlyParticipant(sessionId) atPhase(sessionId, 2) notTimedOut(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.purpose != SessionPurpose.DKG, "Only for signing");
        require(bytes(sess.signatureShares[msg.sender]).length == 0, "Already submitted");
        require(share.length == 64, "Invalid signature share size"); // (r, s) for Schnorr

        // copy to memory to avoid complicated calldata handling later
        bytes memory memShare = _copyCalldataToMemory(share);
        sess.signatureShares[msg.sender] = memShare;
        sess.submittedShares++;
        emit SignatureShareSubmitted(sessionId, msg.sender, memShare);
    }

    // -----------------------------
    // Finalization
    // -----------------------------

    // 1) Finalize with provided aggregated signature (off-chain aggregation)
    function finalizeSession(uint256 sessionId, bytes calldata signature, bytes32 messageHash) external override validSession(sessionId) atPhase(sessionId, 3) notTimedOut(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.purpose != SessionPurpose.DKG, "Only for signing");
        require(signature.length == 64, "Invalid signature size");
        require(!sess.messageBound || sess.messageHash == messageHash, "Invalid message hash");

        // parse r and s from calldata (32 + 32)
        bytes32 r;
        bytes32 s;
        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
        }

        // verify via Schnorr.verify (x-only)
        bool ok = Schnorr.verifyXonly(uint256(sess.groupPubKeyX), uint256(r), uint256(s), messageHash);
        require(ok, "Invalid aggregate signature");

        sess.aggregatedSignature = _copyCalldataToMemory(signature);
        sess.currentPhase = 4;
        sess.isSuccessful = true;

        emit SessionFinalized(sessionId, signature, msg.sender, sess.groupPubKeyX);
    }

    // 2) On-chain aggregation from shares[]: compute aggregated s, verify
    function finalizeSession(uint256 sessionId, bytes[] calldata shares, bytes calldata aggregatedSignature) external validSession(sessionId) atPhase(sessionId, 3) notTimedOut(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.purpose != SessionPurpose.DKG, "Only for signing");
        require(shares.length >= sess.threshold, "Not enough shares");
        require(aggregatedSignature.length == 64, "Invalid signature size");

        bytes memory computedSig = _aggregateSignatures(shares, sess.messageHash);

        // compare computedSig with provided aggregatedSignature (keccak)
        require(keccak256(computedSig) == keccak256(aggregatedSignature), "Invalid aggregated signature");

        // parse r and s from aggregatedSignature (calldata)
        bytes32 r;
        bytes32 s;
        assembly ("memory-safe") {
            r := calldataload(aggregatedSignature.offset)
            s := calldataload(add(aggregatedSignature.offset, 32))
        }

        bool ok = Schnorr.verifyXonly(uint256(sess.groupPubKeyX), uint256(r), uint256(s), sess.messageHash);
        require(ok, "Invalid aggregate signature");

        sess.aggregatedSignature = _copyCalldataToMemory(aggregatedSignature);
        sess.currentPhase = 4;
        sess.isSuccessful = true;

        emit SessionFinalized(sessionId, aggregatedSignature, msg.sender, sess.groupPubKeyX);
    }

    // Finalize DKG: set compressed pubkey (33 bytes) but store only X (x-only)
    function finalizeDKG(uint256 sessionId, bytes calldata groupPubkey) external override validSession(sessionId) onlyInitiator(sessionId) atPhase(sessionId, 3) {
        Session storage sess = sessions[sessionId];
        require(sess.purpose == SessionPurpose.DKG, "Only for DKG");
        require(groupPubkey.length == 33, "Invalid pubkey length");
        require(sess.groupPubKeyX == bytes32(0), "Pubkey already set");

        bytes32 pubKeyX = _bytes32FromCalldata(groupPubkey, 1);
        require(pubKeyX != bytes32(0) && uint256(pubKeyX) < Secp256k1.P, "Invalid pubkey x");
        uint256 py = Secp256k1.calculateY(uint256(pubKeyX), false);
        require(Secp256k1.isOnCurve(uint256(pubKeyX), py), "Pubkey not on curve");

        sess.groupPubKeyX = pubKeyX;
        sess.currentPhase = 4;
        sess.isSuccessful = true;

        emit SessionFinalized(sessionId, "", msg.sender, pubKeyX);
    }

    function rejectSignatureRequest(uint256 sessionId, string calldata reason) external override validSession(sessionId) onlyParticipant(sessionId) {
        Session storage sess = sessions[sessionId];
        require(sess.purpose != SessionPurpose.DKG, "Only for signing");
        sess.refusalCount++;
        sess.currentPhase = 4;
        sess.isSuccessful = false;
        emit SessionFailed(sessionId, reason);
    }

    // -----------------------------
    // Getters
    // -----------------------------

    function getCustodians() external view override returns (address[] memory) {
        // NOTE: original code returned sessionParticipants[0]; this is preserved for compatibility,
        // but in most deployments you'd store custodians separately.
        return sessionParticipants[0];
    }

    function getSession(uint256 sessionId)
        external
        view
        override
        validSession(sessionId)
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
        Session storage sess = sessions[sessionId];
        bytes memory pubKey = sess.groupPubKeyX == bytes32(0) ? new bytes(0) : _encodePubKey(sess.groupPubKeyX, sess.groupPubKeyY);
        uint256 stateRet = sess.isSuccessful ? 2 : (sess.currentPhase == 4 ? 3 : sess.currentPhase);
        return (
            sess.sessionId,
            sess.initiator,
            pubKey,
            sess.messageHash,
            sess.messageBound,
            sess.threshold,
            sess.totalParticipants,
            uint64(sess.deadline),
            sess.enforceSharesCheck,
            sess.verifierOverride,
            stateRet,
            sess.submittedCommitments,
            sess.submittedShares,
            sess.refusalCount,
            uint256(sess.purpose),
            sess.originContract,
            sess.originId,
            sess.networkId,
            sess.poolId,
            sess.submittedShares
        );
    }

    function getDKGShare(uint256 sessionId, address sender, address recipient) external view override returns (bytes memory) {
        return sessions[sessionId].dkgShares[sender][recipient];
    }

    function getNonceCommitment(uint256 sessionId, address participant) external view returns (bytes32) {
        return sessions[sessionId].nonceCommitments[participant];
    }

    function getSignatureShare(uint256 sessionId, address participant) external view  returns (bytes memory) {
        return sessions[sessionId].signatureShares[participant];
    }

    function getAggregatedSignature(uint256 sessionId) external view  returns (bytes memory) {
        return sessions[sessionId].aggregatedSignature;
    }

    function getGroupPubKey(uint256 sessionId) external view  returns (bytes32 pubKeyX, bytes32 pubKeyY) {
        Session storage sess = sessions[sessionId];
        uint256 y = sess.groupPubKeyX == bytes32(0) ? 0 : Secp256k1.calculateY(uint256(sess.groupPubKeyX), false);
        return (sess.groupPubKeyX, bytes32(y));
    }

    function getCompressedGroupPubKey(uint256 sessionId) external view validSession(sessionId) returns (bytes memory) {
        Session storage sess = sessions[sessionId];
        require(sess.groupPubKeyX != bytes32(0), "Pubkey not set");
        return _encodePubKey(sess.groupPubKeyX, sess.groupPubKeyY);
    }

    // -----------------------------
    // Internal helpers
    // -----------------------------

    // Aggregate shares: each share is bytes(64) with (r||s). We require r equal across shares.
    function _aggregateSignatures(bytes[] calldata shares, bytes32 /*messageHash*/) internal view returns (bytes memory) {
        require(shares.length > 0, "No shares provided");
        // copy first share to memory and read r
        bytes memory firstShare = _copyCalldataToMemory(shares[0]);
        require(firstShare.length == 64, "Invalid share format");
        bytes32 r = _bytes32FromMemory(firstShare, 0);

        uint256 s_sum = 0;
        for (uint i = 0; i < shares.length; i++) {
            bytes memory memShare = _copyCalldataToMemory(shares[i]);
            require(memShare.length == 64, "Invalid share format");
            bytes32 share_r = _bytes32FromMemory(memShare, 0);
            require(share_r == r, "Inconsistent r values");
            bytes32 s_b = _bytes32FromMemory(memShare, 32);
            uint256 s = uint256(s_b);
            s_sum = addmod(s_sum, s, Secp256k1.N);
        }

        bytes memory aggregatedSig = new bytes(64);
        // copy r
        for (uint j = 0; j < 32; j++) {
            aggregatedSig[j] = firstShare[j];
        }
        // copy s_sum as bytes32
        bytes32 s32 = bytes32(s_sum);
        for (uint j = 0; j < 32; j++) {
            aggregatedSig[32 + j] = s32[j];
        }
        return aggregatedSig;
    }

    // ==================== DKG Functions ====================

    /**
     * @dev Create a new DKG session
     * @param threshold The threshold for the session
     * @param participants Initial list of participants
     * @return sessionId The ID of the created session
     */
    function createDKGSession(
        uint256 threshold,
        address[] calldata participants
    ) external returns (uint256) {
        require(threshold >= MIN_THRESHOLD, "Threshold too low");
        require(threshold > 0, "Threshold must be positive");
        require(threshold <= participants.length, "Threshold exceeds participants");
        require(participants.length >= threshold, "Not enough participants");
        require(participants.length <= MAX_PARTICIPANTS, "Too many participants");

        uint256 sessionId = nextSessionId++;
        Session storage session = sessions[sessionId];

        session.state = SessionState.PENDING_COMMIT;
        session.threshold = uint32(threshold);
        session.totalParticipants = uint32(participants.length);
        session.deadline = uint64(block.timestamp + SESSION_TIMEOUT);
        session.startTime = block.timestamp; // Set start time for validation
        session.creator = msg.sender;
        session.purpose = SessionPurpose.KEY_GENERATION;

        // Store participants
        for (uint i = 0; i < participants.length; i++) {
            require(participants[i] != address(0), "Invalid participant");
            session.participants[participants[i]] = true;
            sessionParticipants[sessionId].push(participants[i]);
        }

        emit SessionCreated(
            sessionId,
            msg.sender,
            threshold,
            participants.length,
            SessionPurpose.KEY_GENERATION,
            uint64(block.timestamp + SESSION_TIMEOUT)
        );

        return sessionId;
    }

    /**
     * @dev Participants publish their nonce commitments
     * @param sessionId The session ID
     * @param commitment The nonce commitment
     */
    function publishNonceCommitment(
        uint256 sessionId,
        bytes32 commitment
    ) external validSession(sessionId) notExpired(sessionId) {
        Session storage session = sessions[sessionId];
        require(session.state == SessionState.PENDING_COMMIT, "Not in commit phase");
        require(session.participants[msg.sender], "Not a participant");
        require(session.nonceCommitments[msg.sender] == bytes32(0), "Already submitted");

        session.nonceCommitments[msg.sender] = commitment;
        session.submittedCommitments++;

        emit NonceCommitted(sessionId, msg.sender, commitment);

        // Check if all participants submitted
        if (session.submittedCommitments == session.totalParticipants) {
            session.state = SessionState.PENDING_SHARES;
            emit SessionProgressedToShares(sessionId);
        }
    }

    /**
     * @dev Participants exchange encrypted shares
     * @param sessionId The session ID
     * @param recipient The recipient of the share
     * @param encryptedShare The encrypted share
     */
    function publishEncryptedShare(
        uint256 sessionId,
        address recipient,
        bytes calldata encryptedShare
    ) external validSession(sessionId) notExpired(sessionId) {
        Session storage session = sessions[sessionId];
        require(session.state == SessionState.PENDING_SHARES, "Not in shares phase");
        require(session.participants[msg.sender], "Not a participant");
        require(session.participants[recipient], "Invalid recipient");
        require(encryptedShare.length <= MAX_SHARE_SIZE, "Share too large");

        session.dkgShares[msg.sender][recipient] = encryptedShare;

        // Count unique senders who have submitted all their shares
        uint256 completeCount = 0;
        for (uint i = 0; i < sessionParticipants[sessionId].length; i++) {
            address sender = sessionParticipants[sessionId][i];
            bool hasAllShares = true;

            for (uint j = 0; j < sessionParticipants[sessionId].length; j++) {
                address recip = sessionParticipants[sessionId][j];
                if (sender != recip && session.dkgShares[sender][recip].length == 0) {
                    hasAllShares = false;
                    break;
                }
            }

            if (hasAllShares) completeCount++;
        }

        if (completeCount == session.totalParticipants) {
            session.state = SessionState.READY;
            emit SessionReadyForFinalization(sessionId);
        }
    }

    /**
     * @dev Finalize the DKG session and compute group public key
     * @param sessionId The session ID
     */
    function finalizeDKG(uint256 sessionId) external validSession(sessionId) notExpired(sessionId) {
        Session storage session = sessions[sessionId];
        require(session.state == SessionState.READY, "Session not ready");
        require(msg.sender == session.creator, "Only creator can finalize");

        // Collect shares from participants who submitted
        address[] memory parts = sessionParticipants[sessionId];
        require(parts.length >= session.threshold, "Not enough participants");

        // Create shares array for aggregation
        FrostDKG.ParticipantShare[] memory shares = new FrostDKG.ParticipantShare[](session.threshold);
        uint256 shareCount = 0;

        // Generate a master secret for this DKG round (in real implementation, this is distributed)
        uint256 masterSecret = uint256(keccak256(abi.encodePacked(
            sessionId,
            block.timestamp,
            block.prevrandao,
            "FROST_MASTER"
        ))) % Secp256k1.N;

        // Generate shares for participants using Shamir secret sharing
        FrostDKG.ParticipantShare[] memory allShares = FrostDKG.generateShares(
            masterSecret,
            session.threshold,
            parts.length,
            sessionId
        );

        // Store shares for each participant
        for (uint256 i = 0; i < parts.length && shareCount < session.threshold; i++) {
            if (session.nonceCommitments[parts[i]] != bytes32(0)) {
                // Participant submitted nonce, include their share
                session.participantShares[parts[i]] = allShares[i].share;
                shares[shareCount] = allShares[i];
                shareCount++;
            }
        }

        // Aggregate public keys from shares
        (uint256 pubX, uint256 pubY) = FrostDKG.aggregatePublicKeys(
            shares,
            session.threshold
        );

        // Verify the generated public key is on the curve
        require(Secp256k1.isOnCurve(pubX, pubY), "Generated key not on curve");

        // Store the public key coordinates
        session.groupPubKeyX = bytes32(pubX);
        session.groupPubKeyY = bytes32(pubY);

        session.state = SessionState.FINALIZED;
        session.isSuccessful = true;

        emit SessionFinalized(sessionId, session.groupPubKeyX, true);
    }

    /**
     * @dev Cancel a DKG session (only creator or if expired)
     * @param sessionId The session ID
     */
    function cancelDKGSession(uint256 sessionId) external validSession(sessionId) {
        Session storage session = sessions[sessionId];
        require(session.state != SessionState.FINALIZED, "Already finalized");

        // Allow creator to cancel anytime, or anyone if session expired
        require(
            msg.sender == session.creator ||
            block.timestamp > session.startTime + SESSION_TIMEOUT,
            "Not authorized to cancel"
        );

        session.state = SessionState.FINALIZED;
        session.isSuccessful = false;

        emit SessionFailed(sessionId, "Session cancelled");
    }

    /**
     * @dev Get list of participants in a session
     * @param sessionId The session ID
     * @return participants Array of participant addresses
     */
    function getSessionParticipants(uint256 sessionId)
        external
        view
        validSession(sessionId)
        returns (address[] memory)
    {
        return sessionParticipants[sessionId];
    }

    /**
     * @dev Get detailed session info including participants
     * @param sessionId The session ID
     */
    function getSessionDetails(uint256 sessionId)
        external
        view
        validSession(sessionId)
        returns (
            SessionState state,
            uint256 threshold,
            uint256 totalParticipants,
            address creator,
            bytes32 groupPubKeyX,
            address[] memory participants
        )
    {
        Session storage session = sessions[sessionId];
        return (
            session.state,
            session.threshold,
            session.totalParticipants,
            session.creator,
            session.groupPubKeyX,
            sessionParticipants[sessionId]
        );
    }

    // ==================== Events ====================

    event SessionCreated(
        uint256 indexed sessionId,
        address indexed creator,
        uint256 threshold,
        uint256 totalParticipants,
        SessionPurpose purpose,
        uint64 deadline
    );


    event SessionProgressedToShares(uint256 indexed sessionId);
    event SessionReadyForFinalization(uint256 indexed sessionId);
    event SessionFinalized(uint256 indexed sessionId, bytes32 groupPubKey, bool success);
}