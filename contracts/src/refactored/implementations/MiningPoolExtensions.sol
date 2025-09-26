// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../MiningPoolStorage.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../../interfaces/IPoolMembership.sol";
import "../../GovernanceIntegrator.sol";

/**
 * @title MiningPoolExtensions
 * @notice Extended functionality including governance, membership, and custom features
 * @dev Size target: ~8KB
 */
contract MiningPoolExtensions is MiningPoolStorage, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // Events
    event GovernanceIntegratorSet(address integrator);
    event ExtensionDataSet(bytes32 key, bytes value);
    event UserPermissionSet(address user, bytes32 permission, bool granted);
    event CustomActionExecuted(bytes32 action, address executor, bytes data);
    event EmergencyWithdrawal(address token, uint256 amount, address to);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier onlyPoolManager() {
        require(hasRole(POOL_MANAGER_ROLE, msg.sender) || hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not pool manager");
        _;
    }

    /**
     * @notice Set governance integrator contract
     */
    function setGovernanceIntegrator(address _integrator) external onlyAdmin {
        governanceIntegrator = _integrator;
        emit GovernanceIntegratorSet(_integrator);
    }

    /**
     * @notice Store custom extension data
     */
    function setExtensionData(bytes32 key, bytes calldata value) external onlyAdmin {
        extensionData[key] = value;
        emit ExtensionDataSet(key, value);
    }

    /**
     * @notice Get extension data
     */
    function getExtensionData(bytes32 key) external view returns (bytes memory) {
        return extensionData[key];
    }

    /**
     * @notice Set user permissions for custom features
     */
    function setUserPermission(
        address user,
        bytes32 permission,
        bool granted
    ) external onlyPoolManager {
        userPermissions[user][permission] = granted;
        emit UserPermissionSet(user, permission, granted);
    }

    /**
     * @notice Check user permission
     */
    function hasUserPermission(address user, bytes32 permission) external view returns (bool) {
        return userPermissions[user][permission];
    }

    /**
     * @notice Get participant info with membership details
     */
    function getParticipantInfo(address participant) external view returns (
        bool registered,
        uint256 shares,
        uint256 claimed,
        uint256 membershipTokenId,
        address evmPayout
    ) {
        registered = isParticipant[participant];
        shares = minerShares[participant];
        claimed = claimedBalance[participant];

        // Get membership info if available
        if (membershipSBT != address(0)) {
            try IPoolMembership(membershipSBT).tokenOf(participant) returns (uint256 tokenId) {
                membershipTokenId = tokenId;

                // Get payout address
                try IPoolMembership(membershipSBT).payoutOf(tokenId) returns (
                    address _evmPayout,
                    string memory,
                    bytes32,
                    bytes20
                ) {
                    evmPayout = _evmPayout;
                } catch {}
            } catch {}
        }
    }

    /**
     * @notice Execute governance proposal
     */
    function executeGovernanceProposal(
        uint256 proposalId,
        bytes calldata data
    ) external nonReentrant {
        require(governanceIntegrator != address(0), "No governance");

        // Note: Simplified implementation - actual would integrate with governance
        // Execute the proposal
        (bool success, bytes memory result) = address(this).delegatecall(data);
        require(success, "Execution failed");

        emit CustomActionExecuted(bytes32(proposalId), msg.sender, data);
    }

    /**
     * @notice Update pool metadata
     */
    function updatePoolMetadata(
        string calldata _poolName,
        string calldata _asset
    ) external onlyAdmin {
        if (bytes(_poolName).length > 0) {
            poolName = _poolName;
        }
        if (bytes(_asset).length > 0) {
            asset = _asset;
        }
    }

    /**
     * @notice Get all participants
     */
    function getParticipants() external view returns (address[] memory) {
        address[] memory result = new address[](participantCount);
        for (uint256 i = 0; i < participantCount; i++) {
            result[i] = participants[i];
        }
        return result;
    }

    /**
     * @notice Get participants with shares
     */
    function getParticipantsWithShares() external view returns (
        address[] memory addrs,
        uint256[] memory shares
    ) {
        addrs = new address[](participantCount);
        shares = new uint256[](participantCount);

        for (uint256 i = 0; i < participantCount; i++) {
            addrs[i] = participants[i];
            shares[i] = minerShares[participants[i]];
        }
    }

    /**
     * @notice Batch update miner shares
     */
    function batchUpdateShares(
        address[] calldata miners,
        uint256[] calldata shares
    ) external onlyAdmin {
        require(miners.length == shares.length, "Length mismatch");

        for (uint256 i = 0; i < miners.length; i++) {
            minerShares[miners[i]] = shares[i];
        }
    }

    /**
     * @notice Emergency function to recover stuck tokens
     * @dev Only for recovering accidentally sent tokens, not pool funds
     */
    function emergencyTokenRecovery(
        address token,
        uint256 amount,
        address to
    ) external onlyAdmin nonReentrant {
        require(token != poolToken, "Cannot withdraw pool token");
        require(to != address(0), "Invalid recipient");

        // For native ETH
        if (token == address(0)) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // For ERC20 tokens
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSignature("transfer(address,uint256)", to, amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "Token transfer failed");
        }

        emit EmergencyWithdrawal(token, amount, to);
    }

    /**
     * @notice Get pool statistics
     */
    function getPoolStats() external view returns (
        uint256 _participantCount,
        uint256 _totalRewards,
        uint256 _totalDistributed,
        uint256 _lastDistribution,
        bool _isActive,
        uint256 pendingRedemptions
    ) {
        _participantCount = participantCount;
        _totalRewards = totalRewards;
        _totalDistributed = totalDistributed;
        _lastDistribution = lastDistribution;
        _isActive = isActive;

        // Count pending redemptions
        for (uint256 i = 0; i < nextRedemptionId; i++) {
            if (redemptions[i].requester != address(0) && !redemptions[i].isConfirmed) {
                pendingRedemptions++;
            }
        }
    }

    /**
     * @notice Check if an address is authorized for a specific action
     * @dev Can be extended with custom logic
     */
    function isAuthorized(address user, bytes32 action) external view returns (bool) {
        // Check role-based permissions
        if (action == keccak256("ADMIN") && _roles[ADMIN_ROLE][user]) return true;
        if (action == keccak256("MANAGER") && _roles[POOL_MANAGER_ROLE][user]) return true;
        if (action == keccak256("CONFIRMER") && _roles[CONFIRMER_ROLE][user]) return true;

        // Check custom permissions
        return userPermissions[user][action];
    }

    /**
     * @notice Migrate participant data (for upgrades)
     */
    function migrateParticipants(
        address[] calldata oldParticipants,
        uint256[] calldata oldShares
    ) external onlyAdmin {
        require(oldParticipants.length == oldShares.length, "Length mismatch");
        require(participantCount == 0, "Already has participants");

        for (uint256 i = 0; i < oldParticipants.length; i++) {
            address participant = oldParticipants[i];
            if (!isParticipant[participant]) {
                isParticipant[participant] = true;
                participants[participantCount++] = participant;
                minerShares[participant] = oldShares[i];
            }
        }
    }
}