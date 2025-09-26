// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/ISPVContract.sol";
import "./interfaces/IMultiPoolDAO.sol";
import "./libs/BlockHeader.sol";
import "./libs/BitcoinUtils.sol";
import "./core/BitcoinTxParser.sol";

/// @title BridgeInbox
/// @notice Receives PoW network deposits (BTC/DOGE/BCH/LTC), verifies via SPV, notifies MultiPoolDAO for S-token mint
contract BridgeInbox is AccessControl {
    bytes32 public constant SUBMITTER_ROLE = keccak256("SUBMITTER_ROLE");

    // Mapping of networkId to SPV contract (0: BTC, 1: DOGE, 2: BCH, 3: LTC)
    mapping(uint256 => ISPVContract) public spvContracts;
    // Reference to MultiPoolDAO for minting S-tokens
    IMultiPoolDAO public multiPoolDAO;
    // Mapping to prevent double-spending
    mapping(bytes32 => bool) public processedUTXOs;

    event DepositVerified(
        uint256 indexed networkId,
        bytes32 indexed txId,
        uint32 vout,
        uint64 amount,
        address recipient,
        bytes32 poolId
    );

    error InvalidNetworkId();
    error InvalidSPVContract();
    error UTXOAlreadyProcessed();
    error InvalidProof();
    error InvalidDestination();

    constructor(address admin, address _multiPoolDAO) {
        if (admin == address(0) || _multiPoolDAO == address(0)) revert InvalidSPVContract();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SUBMITTER_ROLE, admin);
        multiPoolDAO = IMultiPoolDAO(_multiPoolDAO);
    }

    /// @notice Set SPV contract for a specific network
    /// @param networkId 0 for BTC, 1 for DOGE, 2 for BCH, 3 for LTC
    /// @param spvAddress Address of the network-specific SPV contract
    function setSPVContract(uint256 networkId, address spvAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (spvAddress == address(0)) revert InvalidSPVContract();
        spvContracts[networkId] = ISPVContract(spvAddress);
    }

    /// @notice Submit deposit proof from PoW network, verify via SPV, notify MultiPoolDAO
    /// @param poolId Pool identifier
    /// @param networkId Network identifier (0: BTC, 1: DOGE, 2: BCH, 3: LTC)
    /// @param header Block header containing the transaction
    /// @param txRaw Raw transaction data
    /// @param merkleProof Merkle proof for transaction inclusion
    /// @param vout Output index
    /// @param directions Merkle proof directions (0 for left, 1 for right)
    /// @param amount Amount in satoshis
    /// @param destination EVM address to receive S-tokens
    function submitPoWDepositProof(
        bytes32 poolId,
        uint256 networkId,
        bytes calldata header,
        bytes calldata txRaw,
        bytes32[] calldata merkleProof,
        uint32 vout,
        uint8[] calldata directions,
        uint64 amount,
        address destination
    ) external onlyRole(SUBMITTER_ROLE) {
        if (address(spvContracts[networkId]) == address(0)) revert InvalidNetworkId();

        // Вычисление txId из txRaw
        bytes memory noWit = BitcoinTxParser.stripWitness(txRaw);
        bytes32 txIdBE = BitcoinTxParser.doubleSha256(noWit);
        bytes32 txId = BitcoinTxParser.flipBytes32(txIdBE);

        // Проверка на повторное использование UTXO
        bytes32 utxoKey = keccak256(abi.encodePacked(txId, vout));
        if (processedUTXOs[utxoKey]) revert UTXOAlreadyProcessed();
        processedUTXOs[utxoKey] = true;

        // Проверка заголовка блока
        ISPVContract spv = spvContracts[networkId];
        spv.addBlockHeader(header);
        (, bytes32 blockHash) = BlockHeader.parseHeader(header);

        // Проверка включения транзакции и зрелости блока
        if (!spv.checkTxInclusion(blockHash, txId, merkleProof, directions)) {
            revert InvalidProof();
        }
        if (!spv.isMature(blockHash)) {
            revert InvalidProof();
        }

        // Проверка amount
        (uint64 outValue, ) = BitcoinUtils._extractVout(txRaw, vout);
        if (outValue != amount) revert InvalidProof();

        // Проверка destination
        if (destination == address(0)) revert InvalidDestination();

        // Уведомление MultiPoolDAO
        multiPoolDAO.receiveReward(poolId, header, txRaw, vout, merkleProof, directions);

        emit DepositVerified(networkId, txId, vout, amount, destination, poolId);
    }
}