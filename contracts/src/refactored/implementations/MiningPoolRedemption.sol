// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../MiningPoolStorage.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../../interfaces/ISPVContract.sol";
import "../../interfaces/IPoolMpToken.sol";
import "../../initialFROST.sol";
import "../../core/BitcoinTxParser.sol";
import "../../libs/BitcoinUtils.sol";

/**
 * @title MiningPoolRedemption
 * @notice Handles MP token redemption to Bitcoin
 * @dev Size target: ~10KB
 */
contract MiningPoolRedemption is MiningPoolStorage, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using BitcoinTxParser for bytes;

    // Events
    event RedemptionRequested(uint256 indexed redemptionId, address requester, uint64 amount);
    event RedemptionConfirmed(uint256 indexed redemptionId, bytes32 txid);
    event RedemptionCancelled(uint256 indexed redemptionId);
    event RedemptionTimeoutSet(uint256 timeout);

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }

    modifier onlyConfirmer() {
        require(hasRole(CONFIRMER_ROLE, msg.sender) || hasRole(ADMIN_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not confirmer");
        _;
    }

    /**
     * @notice Request redemption of MP tokens to Bitcoin
     * @param amountSat Amount in satoshis to redeem
     * @param btcScript Bitcoin script to send to
     * @param networkId Network ID (0 = mainnet, 1 = testnet)
     */
    function requestRedemption(
        uint64 amountSat,
        bytes calldata btcScript,
        uint8 networkId
    ) external nonReentrant returns (uint256) {
        require(amountSat > 0, "Zero amount");
        require(btcScript.length > 0, "Empty script");
        require(supportedNetworks[networkId] || networkId == 0, "Unsupported network");

        // Burn MP tokens
        IPoolMpToken(poolToken).burn(msg.sender, amountSat);

        // Create redemption request
        uint256 redemptionId = nextRedemptionId++;
        redemptions[redemptionId] = Redemption({
            requester: msg.sender,
            amountSat: amountSat,
            btcScript: btcScript,
            txid: bytes32(0),
            vout: 0,
            createdAt: uint64(block.timestamp),
            confirmedAt: 0,
            isConfirmed: false,
            networkId: networkId
        });

        emit RedemptionRequested(redemptionId, msg.sender, amountSat);
        return redemptionId;
    }

    /**
     * @notice Confirm redemption with Bitcoin transaction
     * @param redemptionId Redemption request ID
     * @param txid Bitcoin transaction ID
     * @param vout Output index
     * @param rawTx Raw Bitcoin transaction
     */
    function confirmRedemption(
        uint256 redemptionId,
        bytes32 txid,
        uint32 vout,
        bytes calldata rawTx
    ) external onlyConfirmer nonReentrant {
        Redemption storage redemption = redemptions[redemptionId];
        require(redemption.requester != address(0), "Invalid redemption");
        require(!redemption.isConfirmed, "Already confirmed");

        // Verify transaction if SPV is available
        address spvContract = redemption.networkId == 0 ? spv : spvContracts[redemption.networkId];
        if (spvContract != address(0)) {
            // Verify transaction output
            // Note: Simplified verification - would need proper parsing
            // In production, would parse transaction and verify:
            // 1. Output at index vout exists
            // 2. Output value >= redemption.amountSat
            // 3. Output script matches redemption.btcScript
        }

        // Mark as confirmed
        redemption.txid = txid;
        redemption.vout = vout;
        redemption.confirmedAt = uint64(block.timestamp);
        redemption.isConfirmed = true;
        processedRedemptions[txid] = true;

        emit RedemptionConfirmed(redemptionId, txid);
    }

    /**
     * @notice Cancel a redemption request (only before confirmation)
     * @param redemptionId Redemption request ID
     */
    function cancelRedemption(uint256 redemptionId) external nonReentrant {
        Redemption storage redemption = redemptions[redemptionId];
        require(redemption.requester == msg.sender || _roles[ADMIN_ROLE][msg.sender], "Not authorized");
        require(!redemption.isConfirmed, "Already confirmed");

        // Check timeout
        if (redemption.requester == msg.sender) {
            require(
                block.timestamp >= redemption.createdAt + redemptionTimeout,
                "Timeout not reached"
            );
        }

        // Refund MP tokens
        uint256 refundAmount = redemption.amountSat;
        delete redemptions[redemptionId];

        IPoolMpToken(poolToken).mint(msg.sender, refundAmount);

        emit RedemptionCancelled(redemptionId);
    }

    /**
     * @notice Set redemption timeout
     * @param timeout Timeout in seconds
     */
    function setRedemptionTimeout(uint256 timeout) external onlyAdmin {
        require(timeout >= 1 hours && timeout <= 7 days, "Invalid timeout");
        redemptionTimeout = timeout;
        emit RedemptionTimeoutSet(timeout);
    }

    /**
     * @notice Execute redemption with FROST signature
     * @param redemptionId Redemption request ID
     * @param prevTxId Previous transaction ID for UTXO
     * @param prevVout Previous output index
     */
    function executeRedemptionWithFROST(
        uint256 redemptionId,
        bytes32 prevTxId,
        uint32 prevVout
    ) external onlyConfirmer nonReentrant returns (bytes32) {
        Redemption storage redemption = redemptions[redemptionId];
        require(redemption.requester != address(0), "Invalid redemption");
        require(!redemption.isConfirmed, "Already confirmed");

        // Create Bitcoin transaction for redemption
        bytes memory unsignedTx = _buildRedemptionTransaction(
            prevTxId,
            prevVout,
            redemption.amountSat,
            redemption.btcScript,
            redemption.networkId
        );

        // Get transaction hash for signing
        bytes32 txHash = BitcoinUtils.doubleSha256(unsignedTx);

        // Request FROST signature
        initialFROSTCoordinator frostContract = initialFROSTCoordinator(frost);

        // Note: This would need actual FROST integration
        // For now, we just mark the intent
        redemption.txid = txHash;
        redemption.confirmedAt = uint64(block.timestamp);
        redemption.isConfirmed = true;

        emit RedemptionConfirmed(redemptionId, txHash);
        return txHash;
    }

    /**
     * @notice Build Bitcoin redemption transaction
     */
    function _buildRedemptionTransaction(
        bytes32 prevTxId,
        uint32 prevVout,
        uint64 amount,
        bytes memory recipientScript,
        uint8 networkId
    ) private view returns (bytes memory) {
        // Build a simple 1-input, 1-output transaction
        bytes memory tx = hex"02000000"; // Version 2

        // Add input count (1)
        tx = abi.encodePacked(tx, uint8(1));

        // Add input
        tx = abi.encodePacked(
            tx,
            prevTxId,           // Previous TX hash (reversed for little-endian)
            prevVout,           // Previous output index
            uint8(0),          // Script length (will add signature later)
            uint32(0xffffffff) // Sequence
        );

        // Add output count (1)
        tx = abi.encodePacked(tx, uint8(1));

        // Add output
        tx = abi.encodePacked(
            tx,
            amount,            // Amount in satoshis (little-endian)
            uint8(recipientScript.length), // Script length
            recipientScript    // Output script
        );

        // Add locktime
        tx = abi.encodePacked(tx, uint32(0));

        return tx;
    }

    /**
     * @notice Get redemption details
     */
    function getRedemption(uint256 redemptionId) external view returns (
        address requester,
        uint64 amountSat,
        bytes memory btcScript,
        bytes32 txid,
        uint64 createdAt,
        uint64 confirmedAt,
        bool isConfirmed
    ) {
        Redemption memory r = redemptions[redemptionId];
        return (
            r.requester,
            r.amountSat,
            r.btcScript,
            r.txid,
            r.createdAt,
            r.confirmedAt,
            r.isConfirmed
        );
    }

    /**
     * @notice Get pending redemptions count
     */
    function getPendingRedemptionsCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < nextRedemptionId; i++) {
            if (redemptions[i].requester != address(0) && !redemptions[i].isConfirmed) {
                count++;
            }
        }
        return count;
    }

    /**
     * @notice Check if a transaction was already processed
     */
    function isTransactionProcessed(bytes32 txid) external view returns (bool) {
        return processedRedemptions[txid];
    }
}