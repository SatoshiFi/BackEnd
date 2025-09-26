// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IBitcoinTxSerializer {
    function serializeTaprootTransaction(
        bytes32 utxoTxId,
        uint32 utxoVout,
        bytes calldata destinationScript,
        uint64 amountSat,
        uint32 sequence,
        uint32 version,
        uint32 locktime
    ) external pure returns (bytes memory rawTx);

    function parseTxId(bytes calldata rawTx) external pure returns (bytes32 txId);

    function getOutputScript(bytes calldata btcAddress) external pure returns (bytes memory script);
}
