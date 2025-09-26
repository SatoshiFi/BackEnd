// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IFROSTCoordinator.sol";
import "./initialFROST.sol";

/**
 * @title FrostSessionReader
 * @notice Utility contract for reading and validating FROST DKG session data
 * @dev Used by MiningPoolFactoryV6 to extract participant info from completed DKG sessions
 */
contract FrostSessionReader {

    struct FrostSessionData {
        bool isValid;
        bool isSuccessful;
        uint256 groupPubkeyX;
        uint256 groupPubkeyY;
        address[] participants;
        uint256 threshold;
        uint256 total;
        address creator;
        uint256 sessionId;
    }

    initialFROSTCoordinator public immutable initialFrost;

    error InvalidSession();
    error SessionNotFinalized();
    error SessionNotSuccessful();
    error InvalidPubkey();

    event SessionDataExtracted(uint256 indexed sessionId, uint256 participantCount);

    constructor(address _initialFrost) {
        require(_initialFrost != address(0), "initialFrost=0");
        initialFrost = initialFROSTCoordinator(_initialFrost);
    }

    /**
     * @notice Extract complete session data from a finalized DKG session
     * @param sessionId The FROST session ID to read
     * @return data Complete session data structure
     */
    function getFrostSessionData(uint256 sessionId) external view returns (FrostSessionData memory data) {
        // Get session info from initialFROST
        (
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
        ) = initialFrost.getSession(sessionId);

        // Validate session exists and is DKG
        if (id == 0) revert InvalidSession();
        if (purpose != 6) revert InvalidSession(); // SessionPurpose.DKG = 6
        if (state != 2) revert SessionNotFinalized(); // state 2 = successful

        // Extract pubkey coordinates from bytes - getGroupPubKey returns (bytes32, bytes32)
        (bytes32 pubXBytes, bytes32 pubYBytes) = initialFrost.getGroupPubKey(sessionId);
        uint256 pubX = uint256(pubXBytes);
        uint256 pubY = uint256(pubYBytes);
        if (pubX == 0) revert InvalidPubkey();

        // Get participants list using sessionParticipants mapping
        address[] memory participants = _getSessionParticipants(sessionId, total);

        data = FrostSessionData({
            isValid: true,
            isSuccessful: true,
            groupPubkeyX: pubX,
            groupPubkeyY: pubY,
            participants: participants,
            threshold: threshold,
            total: total,
            creator: creator,
            sessionId: sessionId
        });

        return data;
    }

    /**
     * @notice Quick validation of FROST session status
     * @param sessionId Session to validate
     * @return isValid True if session is ready for pool creation
     */
    function validateFrostSession(uint256 sessionId) external view returns (bool isValid) {
        try this.getFrostSessionData(sessionId) returns (FrostSessionData memory data) {
            return data.isValid && data.isSuccessful && data.participants.length >= 2;
        } catch {
            return false;
        }
    }

    /**
     * @notice Get list of session participants
     * @param sessionId Session to query
     * @return participants Array of participant addresses
     */
    function getSessionParticipants(uint256 sessionId) external view returns (address[] memory participants) {
        (, , , , , , uint256 total, , , , , , , , , , , , , ) = initialFrost.getSession(sessionId);
        return _getSessionParticipants(sessionId, total);
    }

    /**
     * @notice Get session governance threshold
     * @param sessionId Session to query
     * @return threshold Minimum signatures required
     * @return total Total participants
     */
    function getSessionThreshold(uint256 sessionId) external view returns (uint256 threshold, uint256 total) {
        (, , , , , threshold, total, , , , , , , , , , , , , ) = initialFrost.getSession(sessionId);
    }

    /**
     * @notice Check if address was participant in session
     * @param sessionId Session to check
     * @param participant Address to verify
     * @return isParticipant True if address participated
     */
    function isSessionParticipant(uint256 sessionId, address participant) external view returns (bool isParticipant) {
        address[] memory participants = this.getSessionParticipants(sessionId);
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == participant) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Internal function to get participants list via sessionParticipants mapping
     * @param sessionId The session ID
     * @param totalCount Total number of participants to read
     */
    function _getSessionParticipants(uint256 sessionId, uint256 totalCount) internal view returns (address[] memory) {
        address[] memory participants = new address[](totalCount);
        uint256 validCount = 0;

        // Read participants using sessionParticipants(sessionId, index)
        for (uint256 i = 0; i < totalCount; i++) {
            try initialFrost.sessionParticipants(sessionId, i) returns (address participant) {
                if (participant != address(0)) {
                    participants[validCount] = participant;
                    validCount++;
                }
            } catch {
                // Skip invalid indices
            }
        }

        // Resize array to actual participant count
        assembly {
            mstore(participants, validCount)
        }

        return participants;
    }
}
