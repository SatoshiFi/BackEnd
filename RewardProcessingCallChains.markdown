# Call Chains for Receiving Rewards in mp-token, S-token, and Native Token

This document outlines the call chains for three critical scenarios in the decentralized Mining Pool System: (1) receiving rewards in pool-specific `mp-token`, (2) converting `mp-token` to network-wide `S-token`, and (3) redeeming tokens to a native token (e.g., BTC) on the native blockchain. These scenarios are based on the system architecture described in the provided `README.md` and smart contract artifacts, focusing on `MiningPoolDAO.sol`, `MultiPoolDAO.sol`, `SPVContract.sol`, `FROSTCoordinator.sol`, `PoolMpToken.sol`, and `PoolSToken.sol`. Each call chain includes detailed steps, example code (using ethers.js), and limitations to ensure robust execution.

## Prerequisites

- **Web3 Interface**: Access to a Web3 provider (e.g., ethers.js, web3.js) connected to an Ethereum-compatible network where the contracts are deployed.
- **Permissions**: The caller must be a registered miner (holding a `PoolMembershipNFT`) or an authorized entity (e.g., pool admin, oracle provider).
- **Contract Addresses**: Deployed addresses for `MiningPoolDAO`, `MultiPoolDAO`, `SPVContract`, `FROSTCoordinator`, `PoolMpToken`, `PoolSToken`, and `StratumOracleRegistry`.
- **Funds**: Sufficient ETH for gas fees and, where applicable, staked funds for oracle providers.
- **Data**: Prepared data for reward submission (e.g., block header, Merkle proof) and redemption (e.g., BTC payout script).

## System Components Involved

- **`MiningPoolDAO.sol`**: Manages pool operations, including reward submission, distribution, and redemption requests.
- **`MultiPoolDAO.sol`**: Coordinates cross-pool rewards, verifies UTXOs, and mints `S-token`.
- **`SPVContract.sol`**: Verifies coinbase transactions and UTXOs using Simplified Payment Verification (SPV).
- **`FROSTCoordinator.sol`**: Manages FROST threshold signatures for secure native token withdrawals.
- **`PoolMpToken.sol`**: ERC20 token for pool-specific rewards, minted and burned during reward distribution and redemption.
- **`PoolSToken`**: ERC20 token for cross-pool rewards, minted by `MultiPoolDAO`.
- **`StratumOracleRegistry.sol`**: Supplies validated share and hashrate data for reward calculations.
- **`CalculatorRegistry.sol`**, **`FPPSCalculator.sol`**, etc.: Calculate reward distributions based on shares.

## Call Chains for Reward Scenarios

Below are the detailed call chains for each scenario, assuming the use of ethers.js for contract interactions. Each scenario assumes the miner is registered (holds a `PoolMembershipNFT`) and that oracle providers have submitted validated share data.

### Scenario 1: Receiving Rewards in mp-token

**Description**: A miner submits a coinbase transaction to the pool, which verifies it via SPV and distributes `mp-token` to miners based on their shares, using a reward scheme (e.g., FPPS).

**Call Chain**:

1. **Submit Coinbase Transaction**:
   - **Contract**: `MiningPoolDAO.sol`
   - **Function**: `submitReward(blockHeader, txRaw, merkleProof, vout)`
   - **Parameters**:
     - `blockHeader`: Raw block header of the mined block (bytes).
     - `txRaw`: Raw coinbase transaction (bytes).
     - `merkleProof`: Array of hashes proving transaction inclusion.
     - `vout`: Output index of the coinbase transaction.
   - **Action**: Miner submits the coinbase transaction for verification.
   - **Example (ethers.js)**:

     ```javascript
     const miningPoolDAO = new ethers.Contract(miningPoolDAOAddress, miningPoolDAOABI, signer);
     const blockHeader = "0x..."; // Raw block header
     const txRaw = "0x..."; // Raw coinbase transaction
     const merkleProof = ["0x...", "0x..."]; // Merkle proof hashes
     const vout = 0; // Output index
     const tx = await miningPoolDAO.submitReward(blockHeader, txRaw, merkleProof, vout);
     await tx.wait();
     ```

2. **Verify Transaction via SPV**:
   - **Contract**: `SPVContract.sol`
   - **Function**: `checkTxInclusion(blockHash, txId, merkleProof, vout)`
   - **Parameters**:
     - `blockHash`: Hash of the block containing the transaction.
     - `txId`: Transaction ID of the coinbase.
     - `merkleProof`: Merkle proof array.
     - `vout`: Output index.
   - **Action**: `MiningPoolDAO` internally calls `SPVContract` to verify the transaction’s inclusion and UTXO maturity (e.g., 100 confirmations for BTC).
   - **Note**: Internal call, not directly invoked by the user.

3. **Fetch Share Data**:
   - **Contract**: `StratumDataAggregator.sol`
   - **Function**: `getWorkerData(poolAddress)`
   - **Parameters**:
     - `poolAddress`: Address of the `MiningPoolDAO` contract.
   - **Action**: `MiningPoolDAO` requests validated share and hashrate data for the reward period.
   - **Note**: Internal call, relies on prior data submission via `StratumOracleRegistry.submitData(poolId, dataHash, signature)`.

4. **Validate Share Data**:
   - **Contract**: `StratumDataValidator.sol`
   - **Function**: `validateBatch(poolId, dataHash, signature)`
   - **Parameters**:
     - `poolId`: ID of the pool.
     - `dataHash`: Hash of the share and hashrate data.
     - `signature`: Signature from the oracle provider.
   - **Action**: Ensures data integrity before use in reward calculations.
   - **Note**: Internal call within `StratumDataAggregator`.

5. **Select Reward Calculator**:
   - **Contract**: `CalculatorRegistry.sol`
   - **Function**: `getCalculator(calculatorId)`
   - **Parameters**:
     - `calculatorId`: ID of the reward scheme (e.g., 1 for FPPS).
   - **Action**: Retrieves the address of the reward calculator contract (e.g., `FPPSCalculator`).
   - **Note**: Internal call.

6. **Calculate Rewards**:
   - **Contract**: `FPPSCalculator.sol` (or other calculator)
   - **Function**: `calculate(totalAmount, WorkerData[], params)`
   - **Parameters**:
     - `totalAmount`: Total reward amount from the coinbase transaction.
     - `WorkerData[]`: Array of miner addresses and their shares.
     - `params`: Configuration parameters for the reward scheme.
   - **Action**: Computes the reward distribution for each miner.
   - **Note**: Internal call.

7. **Mint mp-token**:
   - **Contract**: `PoolMpToken.sol`
   - **Function**: `mint(to, amount)`
   - **Parameters**:
     - `to`: Miner’s address.
     - `amount`: Amount of `mp-token` to mint.
   - **Action**: Mints `mp-token` for each miner based on the calculated distribution.
   - **Note**: Internal call triggered by `MiningPoolDAO`.
   - **Example (ethers.js, for verification)**:

     ```javascript
     const mpToken = new ethers.Contract(mpTokenAddress, poolMpTokenABI, signer);
     const balance = await mpToken.balanceOf(minerAddress);
     console.log(`mp-token balance: ${ethers.utils.formatEther(balance)}`);
     ```

**Outcome**: Miners receive `mp-token` proportional to their shares, as verified by the SPV and calculated by the reward scheme.

### Scenario 2: Converting mp-token to S-token

**Description**: A miner converts their pool-specific `mp-token` to network-wide `S-token` for cross-pool liquidity or DeFi use, involving verification by `MultiPoolDAO`.

**Call Chain**:

1. **Initiate Conversion**:
   - **Contract**: `MiningPoolDAO.sol`
   - **Function**: `convert(mpTokenAmount)`
   - **Parameters**:
     - `mpTokenAmount`: Amount of `mp-token` to convert (in wei).
   - **Action**: Miner initiates the conversion process, approving `MiningPoolDAO` to burn their `mp-token`.
   - **Example (ethers.js)**:

     ```javascript
     const mpToken = new ethers.Contract(mpTokenAddress, poolMpTokenABI, signer);
     const miningPoolDAO = new ethers.Contract(miningPoolDAOAddress, miningPoolDAOABI, signer);
     // Approve MiningPoolDAO to spend mp-token
     await mpToken.approve(miningPoolDAOAddress, mpTokenAmount);
     // Initiate conversion
     const tx = await miningPoolDAO.convert(mpTokenAmount);
     await tx.wait();
     ```

2. **Burn mp-token**:
   - **Contract**: `PoolMpToken.sol`
   - **Function**: `burn(from, amount)`
   - **Parameters**:
     - `from`: Miner’s address.
     - `amount`: Amount of `mp-token` to burn.
   - **Action**: `MiningPoolDAO` burns the miner’s `mp-token` to prevent double-spending.
   - **Note**: Internal call.

3. **Forward Reward Data to MultiPoolDAO**:
   - **Contract**: `MultiPoolDAO.sol`
   - **Function**: `receiveReward(poolId, blockHeader, txRaw, vout, proof)`
   - **Parameters**:
     - `poolId`: ID of the pool.
     - `blockHeader`: Block header of the original coinbase transaction.
     - `txRaw`: Raw coinbase transaction.
     - `vout`: Output index.
     - `proof`: Merkle proof for verification.
   - **Action**: `MiningPoolDAO` forwards the verified reward data to `MultiPoolDAO` for cross-pool validation.
   - **Note**: Internal call, reuses data from the original `submitReward`.

4. **Verify Reward via SPV**:
   - **Contract**: `SPVContract.sol`
   - **Function**: `checkTxInclusion(blockHash, txId, merkleProof, vout)`
   - **Parameters**:
     - `blockHash`, `txId`, `merkleProof`, `vout`: Same as in Scenario 1.
   - **Action**: `MultiPoolDAO` re-verifies the coinbase transaction to ensure validity across pools.
   - **Note**: Internal call.

5. **Mint S-token**:
   - **Contract**: `PoolSToken.sol`
   - **Function**: `mint(to, amount)`
   - **Parameters**:
     - `to`: Miner’s address.
     - `amount`: Amount of `S-token` to mint (based on `mp-token` value and conversion rate).
   - **Action**: `MultiPoolDAO` mints `S-token` for the miner.
   - **Note**: Internal call.
   - **Example (ethers.js, for verification)**:

     ```javascript
     const sToken = new ethers.Contract(sTokenAddress, poolSTokenABI, signer);
     const balance = await sToken.balanceOf(minerAddress);
     console.log(`S-token balance: ${ethers.utils.formatEther(balance)}`);
     ```

**Outcome**: The miner’s `mp-token` is burned, and they receive `S-token`, which is usable across pools or in DeFi protocols.

### Scenario 3: Redeeming to Native Token (e.g., BTC)

**Description**: A miner redeems their `mp-token` or `S-token` for a native token (e.g., BTC) on the native blockchain, using FROST threshold signatures for secure withdrawal.

**Call Chain**:

1. **Initiate Redemption**:
   - **Contract**: `MiningPoolDAO.sol`
   - **Function**: `redeem(amount, btcScript)`
   - **Parameters**:
     - `amount`: Amount of `mp-token` or `S-token` to redeem (in wei).
     - `btcScript`: Bitcoin script for the payout address (e.g., P2PKH scriptPubKey).
   - **Action**: Miner initiates redemption, approving token burning and specifying the BTC payout address.
   - **Example (ethers.js)**:

     ```javascript
     const token = new ethers.Contract(tokenAddress, tokenABI, signer); // mpToken or sToken
     const miningPoolDAO = new ethers.Contract(miningPoolDAOAddress, miningPoolDAOABI, signer);
     // Approve token for burning
     await token.approve(miningPoolDAOAddress, amount);
     // Initiate redemption
     const btcScript = "0x..."; // Bitcoin scriptPubKey
     const tx = await miningPoolDAO.redeem(amount, btcScript);
     await tx.wait();
     ```

2. **Burn Tokens**:

   - **Contract**: `PoolMpToken.sol` or `PoolSToken.sol`
   - **Function**: `burn(from, amount)`
   - **Parameters**:
     - `from`: Miner’s address.
     - `amount`: Amount of tokens to burn.
   - **Action**: Burns the specified tokens to prevent double-spending.
   - **Note**: Internal call.

3. **Create FROST Session**:
   - **Contract**: `FROSTCoordinator.sol`
   - **Function**: `createSession(sessionId, participants, threshold)`
   - **Parameters**:
     - `sessionId`: Unique identifier for the signature session.
     - `participants`: Array of signer addresses.
     - `threshold`: Number of signatures required (e.g., 3 of 5).
   - **Action**: Initiates a FROST signature session for the withdrawal transaction.
   - **Note**: Internal call, requires off-chain coordination for signer participation.

4. **Submit Partial Signatures**:
   - **Contract**: `FROSTCoordinator.sol`
   - **Function**: `submitPartialSignature(sessionId, signer, signature)`
   - **Parameters**:
     - `sessionId`: Session identifier.
     - `signer`: Address of the signer.
     - `signature`: Partial signature from the signer.
   - **Action**: Signers submit their partial signatures for the BTC transaction.
   - **Note**: Requires off-chain coordination (e.g., via API or messaging system) to collect signatures.

5. **Aggregate Signatures**:
   - **Contract**: `FROSTCoordinator.sol`
   - **Function**: `aggregateSignature(sessionId, partialSignatures)`
   - **Parameters**:
     - `sessionId`: Session identifier.
     - `partialSignatures`: Array of collected signatures.
   - **Action**: Aggregates partial signatures into a valid Schnorr signature for the BTC transaction.
   - **Note**: Internal call.

6. **Broadcast Transaction**:
   - **Contract**: None (off-chain action)
   - **Action**: The aggregated signature is used to construct and broadcast a BTC transaction to the miner’s specified address.
   - **Note**: Requires an off-chain agent to interact with the Bitcoin network.

7. **Verify Transaction Inclusion**:
   - **Contract**: `SPVContract.sol`
   - **Function**: `checkTxInclusion(blockHash, txId, merkleProof, vout)`
   - **Parameters**:
     - `blockHash`, `txId`, `merkleProof`, `vout`: Data for the redemption transaction.
   - **Action**: Verifies that the BTC transaction is included in the Bitcoin blockchain.
   - **Note**: Internal call, triggered by `MiningPoolDAO` to confirm payout.

**Outcome**: The miner’s tokens are burned, and they receive BTC in their specified address, secured by FROST signatures and verified by SPV.

## Limitations

1. **SPV Verification Delays**:
   - **Limitation**: SPV requires 100 confirmations for UTXO maturity (e.g., ~16 hours for BTC at 10 min/block).
   - **Impact**: Delays reward distribution (`mp-token`) and conversion (`S-token`) until the coinbase transaction is mature.
   - **Mitigation**: Inform miners of expected delays and explore faster verification where secure.

2. **FROST Coordination Complexity**:
   - **Limitation**: FROST signature collection requires off-chain coordination among signers, which is not yet automated.
   - **Impact**: Redemption to native tokens is slow and manual, increasing operational overhead.
   - **Mitigation**: Develop off-chain agents to automate signature collection (e.g., via API).

3. **Gas Costs**:
   - **Limitation**: Multiple contract calls (SPV, token burning, FROST) incur high gas costs on Ethereum.
   - **Impact**: High fees may deter small-scale miners or frequent conversions/redemptions.
   - **Mitigation**: Deploy on layer-2 solutions (e.g., Optimism) or optimize contract logic.

4. **Oracle Data Dependency**:
   - **Limitation**: Reward distribution relies on validated share data from `StratumOracleRegistry`, which could be delayed or inaccurate if providers are offline or malicious.
   - **Impact**: Inaccurate data may lead to unfair reward distribution.
   - **Mitigation**: Increase provider diversity and enforce slashing for invalid submissions.

5. **Cross-Chain Bridging Risks**:
   - **Limitation**: Redemption to native tokens involves cross-chain operations, which are susceptible to bridge vulnerabilities or network-specific issues (e.g., Bitcoin reorgs).
   - **Impact**: Potential loss of funds or delays in redemption.
   - **Mitigation**: Use robust bridge contracts (`BridgeOutbox`) and monitor chain stability.

6. **Incomplete UI**:
   - **Limitation**: The MVP lacks a UI, requiring manual contract calls for reward submission, conversion, and redemption.
   - **Impact**: Limits accessibility for non-technical users.
   - **Mitigation**: Develop a user-friendly interface for these scenarios.

7. **Testing Gaps**:
   - **Limitation**: End-to-end tests are incomplete, increasing the risk of bugs in reward distribution or redemption.
   - **Impact**: Potential errors in token minting or BTC payouts.
   - **Mitigation**: Complete comprehensive testing, including edge cases (e.g., zero shares, invalid proofs).

## Conclusion

The call chains for receiving `mp-token`, converting to `S-token`, and redeeming to native tokens (e.g., BTC) provide a clear path for miners to process rewards in the Mining Pool System. These scenarios leverage `MiningPoolDAO`, `MultiPoolDAO`, `SPVContract`, and `FROSTCoordinator` to ensure secure and transparent operations. The limitations highlight areas for improvement, such as automating FROST coordination and reducing gas costs, which are critical for scalability and user adoption. This guide is ideal for demonstrating the system’s functionality to investors, showcasing its decentralized and trustless reward processing.