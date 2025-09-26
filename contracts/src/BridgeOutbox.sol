// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IMultiPoolDAO.sol";
import "./interfaces/IFROSTCoordinator.sol";
import "./BitcoinTxSerializer.sol";
import "./libs/BitcoinUtils.sol";
import "./libs/BlockHeader.sol";

/// @title BridgeOutbox
/// @notice Handles redemption of S-tokens to PoW network (BTC/DOGE/BCH/LTC) with FROST-signed tx
contract BridgeOutbox is AccessControl {
    bytes32 public constant REQUESTER_ROLE = keccak256("REQUESTER_ROLE");

    // Reference to MultiPoolDAO for burning S-tokens and UTXO selection
    IMultiPoolDAO public multiPoolDAO;
    // Reference to FROSTCoordinator for threshold signing
    IFROSTCoordinator public frostCoordinator;
    // Mapping networkId to FROST group key (x-only for Schnorr, full for ECDSA)
    mapping(uint256 => bytes) public networkGroupKeys;
    // Track redemption requests
    mapping(bytes32 => bool) public processedRedemptions;
    // Store redemption request data
    struct RedemptionRequest {
        bytes32 poolId;
        uint256 networkId;
        uint64 amount;
        bytes powAddress;
        bytes32 prevTxId;
        uint32 vout;
    }
    mapping(bytes32 => RedemptionRequest) public redemptionRequests;

    event RedemptionRequested(
        bytes32 indexed requestId,
        uint256 indexed networkId,
        address indexed requester,
        bytes powAddress,
        uint64 amount,
        bytes32 poolId
    );
    event RedemptionFinalized(
        bytes32 indexed requestId,
        uint256 indexed networkId,
        bytes32 txId,
        bytes rawTx
    );

    error InvalidNetworkId();
    error InvalidGroupKey();
    error RedemptionAlreadyProcessed();
    error InvalidPoWAddress();
    error InvalidAmount();
    error SignatureFailed();
    error NoAvailableUTXO();
    error InvalidUTXO();
    error InvalidSPVContract(); 

    constructor(address admin, address _multiPoolDAO, address _frostCoordinator) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REQUESTER_ROLE, admin);
        multiPoolDAO = IMultiPoolDAO(_multiPoolDAO);
        frostCoordinator = IFROSTCoordinator(_frostCoordinator);
    }

    /// @notice Set FROST group key for a specific network
    /// @param networkId 0 for BTC, 1 for DOGE, 2 for BCH, 3 for LTC
    /// @param groupKey x-only pubkey (32 bytes) for Schnorr, full pubkey for ECDSA
    function setNetworkGroupKey(uint256 networkId, bytes calldata groupKey) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (groupKey.length != 32 && groupKey.length != 64) revert InvalidGroupKey();
        networkGroupKeys[networkId] = groupKey;
    }

    /// @notice Submit redemption request: burn S-tokens, build PoW tx, start FROST session
    /// @param poolId Pool identifier
    /// @param networkId Network identifier (0: BTC, 1: DOGE, 2: BCH, 3: LTC)
    /// @param amount Amount in satoshis
    /// @param powAddress Destination PoW address (P2TR/P2WPKH for BTC, etc.)
    function submitRedemptionRequest(
        bytes32 poolId,
        uint256 networkId,
        uint64 amount,
        bytes calldata powAddress
    ) external onlyRole(REQUESTER_ROLE) returns (bytes32 requestId) {
        if (amount == 0) revert InvalidAmount();
        if (powAddress.length == 0 || powAddress.length > 128) revert InvalidPoWAddress();
        if (networkGroupKeys[networkId].length == 0) revert InvalidNetworkId();

        // Get UTXO from MultiPoolDAO
        (bytes32 prevTxId, uint32 vout) = multiPoolDAO.selectUTXO(poolId, uint8(networkId), amount);
        if (prevTxId == bytes32(0)) revert NoAvailableUTXO();

        // Generate unique request ID
        requestId = keccak256(abi.encodePacked(msg.sender, poolId, networkId, amount, block.timestamp));
        if (processedRedemptions[requestId]) revert RedemptionAlreadyProcessed();
        processedRedemptions[requestId] = true;

        // Store request data
        redemptionRequests[requestId] = RedemptionRequest({
            poolId: poolId,
            networkId: networkId,
            amount: amount,
            powAddress: powAddress,
            prevTxId: prevTxId,
            vout: vout
        });

        // Burn S-tokens via MultiPoolDAO
        multiPoolDAO.burnAndRedeem(poolId, uint8(networkId), amount, msg.sender);

        // Build raw transaction
        BitcoinTxSerializer.Tx memory tx = _buildRedemptionTx(networkId, amount, powAddress, prevTxId, vout);
        bytes memory rawTx = BitcoinTxSerializer.serializeTx(tx);

        // Start FROST signing session
        frostCoordinator.createSession(
            uint256(requestId),
            networkGroupKeys[networkId],
            rawTx,
            networkId == 1 ? "ECDSA" : "Schnorr", // DOGE uses ECDSA, others Schnorr
            block.timestamp + 24 hours
        );

        emit RedemptionRequested(requestId, networkId, msg.sender, powAddress, amount, poolId);
    }

    /// @notice Finalize redemption with FROST signature
    /// @param requestId Redemption request ID
    /// @param networkId Network identifier
    /// @param signature Aggregated FROST signature
    function finalizeRedemption(
        bytes32 requestId,
        uint256 networkId,
        bytes calldata signature
    ) external onlyRole(REQUESTER_ROLE) {
        if (!processedRedemptions[requestId]) revert RedemptionAlreadyProcessed();

        // Reconstruct tx from stored request
        BitcoinTxSerializer.Tx memory tx = _rebuildTxFromRequest(requestId);
        bytes memory rawTx = BitcoinTxSerializer.serializeTx(tx);
        bytes32 txId = BitcoinUtils.doubleSha256(rawTx);

        // Verify signature via FROSTCoordinator
        // Note: finalizeSession reverts on failure, no return value
        frostCoordinator.finalizeSession(
            uint256(requestId),
            signature,
            keccak256(abi.encodePacked(networkId == 1 ? "ECDSA" : "Schnorr"))
        );

        // Clear request data to save storage
        delete redemptionRequests[requestId];

        emit RedemptionFinalized(requestId, networkId, txId, rawTx);
    }

    /// @notice Internal: Build redemption transaction
    function _buildRedemptionTx(
        uint256 networkId,
        uint64 amount,
        bytes memory powAddress,
        bytes32 prevTxId,
        uint32 vout
    ) private pure returns (BitcoinTxSerializer.Tx memory) {
        BitcoinTxSerializer.Tx memory tx;
        tx.version = 2;
        tx.segwit = true;
        tx.locktime = 0;

        // Input: Use provided pool's UTXO
        BitcoinTxSerializer.TxInput memory input = BitcoinTxSerializer.getStakeInput(prevTxId, vout);
        input.witness = new bytes[](1); // Placeholder for FROST signature
        tx.vin = new BitcoinTxSerializer.TxInput[](1);
        tx.vin[0] = input;

        // Output: To user's PoW address
        BitcoinTxSerializer.TxOutput memory output;
        if (networkId == 0 || networkId == 2 || networkId == 3) {
            // BTC/BCH/LTC: P2TR (32-byte witness program)
            if (powAddress.length != 32) revert InvalidPoWAddress();
            output = BitcoinTxSerializer.buildP2TROutput(amount, bytes32(powAddress));
        } else if (networkId == 1) {
            // DOGE: P2WPKH (20-byte hash160)
            if (powAddress.length != 20) revert InvalidPoWAddress();
            output = BitcoinTxSerializer.buildP2WPKHOutput(amount, bytes20(powAddress));
        } else {
            revert InvalidNetworkId();
        }
        tx.vout = new BitcoinTxSerializer.TxOutput[](1);
        tx.vout[0] = output;

        return tx;
    }

    /// @notice Internal: Rebuild tx for signature verification
    function _rebuildTxFromRequest(bytes32 requestId) private view returns (BitcoinTxSerializer.Tx memory) {
        RedemptionRequest memory req = redemptionRequests[requestId];
        return _buildRedemptionTx(req.networkId, req.amount, req.powAddress, req.prevTxId, req.vout);
    }

    /// @notice Update MultiPoolDAO address
    function setMultiPoolDAO(address _multiPoolDAO) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_multiPoolDAO == address(0)) revert InvalidSPVContract();
        multiPoolDAO = IMultiPoolDAO(_multiPoolDAO);
    }

    /// @notice Update FROSTCoordinator address
    function setFROSTCoordinator(address _frostCoordinator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_frostCoordinator == address(0)) revert InvalidSPVContract();
        frostCoordinator = IFROSTCoordinator(_frostCoordinator);
    }
}