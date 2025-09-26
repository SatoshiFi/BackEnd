# Mining Pool System Documentation

This document provides a comprehensive overview of the decentralized mining pool system, detailing its architecture, smart contracts, public functions, call chains for user scenarios, and limitations. It is based on the provided `README.md` and smart contract artifacts, focusing on the system's core functionality, reward distribution, and cross-chain operations.

## Introduction

The Mining Pool System is a decentralized platform designed to manage mining pools, distribute rewards, and facilitate cross-chain operations. It leverages **Solidity smart contracts**, **Stratum-based oracles**, **FROST threshold signatures**, **SPV (Simplified Payment Verification)**, and tokenomics for `mp-token` (pool-specific token) and `S-token` (global network token). The system supports multiple blockchain networks, including Bitcoin (BTC), Dogecoin (DOGE), and potentially Litecoin (LTC) or Bitcoin Cash (BCH). It provides modular reward calculators for schemes like FPPS (Full Pay Per Share), PPLNS (Pay Per Last N Shares), PPS (Pay Per Share), and score-based distribution.

### Key Features
- **On-chain Verification**: Uses SPV to verify coinbase transactions and UTXOs, ensuring trustless reward validation.
- **Tokenomics**: Issues `mp-token` for pool-specific rewards and `S-token` for cross-pool, DeFi-ready assets.
- **FROST Threshold Signatures**: Enables secure withdrawals to native networks (e.g., Bitcoin) using multi-signature schemes.
- **Decentralized Governance**: Managed by `MiningPoolDAO` and `MultiPoolDAO` for pool-specific and network-wide coordination.
- **Reward Distribution**: Supports multiple schemes (FPPS, PPLNS, etc.) for fair and flexible reward allocation.

## System Architecture

The system comprises several smart contracts and libraries, each serving a specific role in the mining pool ecosystem. Below is an overview of the core components and their interactions.

### Core Contracts
- **`MiningPoolDAO.sol`**: Manages individual mining pools, handling miner registration, share tracking, reward distribution, and withdrawals.
- **`MultiPoolDAO.sol`**: Coordinates rewards across multiple pools, verifies UTXOs via SPV, and mints `S-token`.
- **`MiningPoolFactory.sol`**: Deploys new `MiningPoolDAO` instances with configured dependencies (SPV, FROST, tokens).
- **`PoolTokenFactory.sol`**: Creates ERC20 tokens (`mp-token`, `S-token`) and soulbound NFTs for membership and roles.

### Tokens and Membership
- **`PoolMpToken.sol`**: ERC20 token for pool-specific rewards, minted and burned during reward distribution and withdrawals.
- **`PoolSToken.sol`**: ERC20 token for cross-pool rewards, minted by `MultiPoolDAO` after UTXO verification.
- **`PoolMembershipNFT.sol`**: Soulbound NFT ensuring only registered miners participate.
- **`PoolRoleBadgeNFT.sol`**: Soulbound NFT for role-based access (e.g., payout policy management).

### SPV Verification
- **`SPVContract.sol`**: Validates Bitcoin block headers, Merkle proofs, and UTXO maturity (100 confirmations).
- **`SPVContractDogecoin.sol`**: SPV tailored for Dogecoin.
- **`BlockHeader.sol`**, **`BitcoinTxParser.sol`**, **`TxMerkleProof.sol`**, **`BitcoinTxSerializer.sol`**, **`BitcoinUtils.sol`**, **`TargetsHelper.sol`**: Libraries for Bitcoin/Dogecoin-specific operations.

### Oracles
- **`StratumDataAggregator.sol`**, **`StratumDataProvider.sol`**, **`StratumDataValidator.sol`**, **`StratumOracleRegistry.sol`**: Handle Stratum protocol data for share and hashrate aggregation.

### Reward Calculators
- **`CalculatorRegistry.sol`**, **`FPPSCalculator.sol`**, **`PPLNSCalculator.sol`**, **`PPSCalculator.sol`**, **`ScoreCalculator.sol`**, **`IDistributionScheme.sol`**, **`DistributionMath.sol`**: Implement various reward distribution schemes.

### Cryptography and FROST
- **`FROSTCoordinator.sol`**, **`FROSTVerifier.sol`**, **`BIP340Adapter.sol`**, **`Secp256k1.sol`**, **`ECDSA.sol`**, **`Schnorr.sol`**: Manage and verify FROST threshold signatures for secure withdrawals.

### Miscellaneous
- **`PoolPolicyTemplate.sol`**: Defines payout policies (e.g., immediate, threshold, periodic).
- **`BridgeInbox.sol`**, **`BridgeOutbox.sol`**: Handle cross-chain messaging.
- **`MerkleProofLib.sol`**, **`SafeMath.sol`**: Utility libraries for Merkle proofs and safe arithmetic.
- **`deploy.js`**: Deployment script for initializing contracts.

## Business Processes

The system supports several key business processes, as outlined in the `README.md`:

1. **Reward Submission and Verification**: Miners submit coinbase transactions, which are verified via SPV before issuing `mp-token` or forwarding to `MultiPoolDAO` for `S-token` minting.
2. **Reward Distribution**: Rewards are calculated using modular schemes (FPPS, PPLNS, etc.) and distributed as `mp-token` or `S-token`.
3. **Token Conversion**: Miners can convert `mp-token` to `S-token` for cross-pool liquidity.
4. **Redemption to Native Network**: Users can redeem tokens for native assets (e.g., BTC) using FROST threshold signatures.
5. **Pool Management**: Miners register, track shares, and manage roles via soulbound NFTs.

## Public Functions and Their Roles

Below is a detailed list of public functions from the provided smart contract artifacts, specifically from `StratumOracleRegistry.sol`, as it is the only contract with a complete ABI. Each function is mapped to its role in the business processes.

### StratumOracleRegistry.sol

This contract manages trusted oracle providers for Stratum data aggregation, ensuring reliable share and hashrate data for reward distribution.

#### Public Functions

1. **getProviderInfo(address provider)**
   - **Signature**: `getProviderInfo(address) returns (address providerAddress, string name, string endpoint, bytes32 publicKey, uint256 stake, uint8 status, uint256 reputation, uint256 registeredAt, uint256 lastActiveAt, uint256 totalDataSubmitted, uint256 validSubmissions, uint256 invalidSubmissions)`
   - **Purpose**: Retrieves detailed information about a registered oracle provider.
   - **Role in Business Process**:
     - **Reward Distribution**: Provides data about oracle providers to ensure only trusted providers supply share and hashrate data to `StratumDataAggregator.sol`, which feeds into reward calculations in `MiningPoolDAO.sol`.

2. **isRegisteredProvider(address provider)**
   - **Signature**: `isRegisteredProvider(address) returns (bool)`
   - **Purpose**: Checks if an address is a registered oracle provider.
   - **Role in Business Process**:
     - **Reward Distribution**: Verifies that only registered providers can submit data, maintaining data integrity for reward calculations.

3. **maxProviders()**
   - **Signature**: `maxProviders() returns (uint256)`
   - **Purpose**: Returns the maximum number of allowed oracle providers.
   - **Role in Business Process**:
     - **Pool Management**: Limits the number of providers to ensure scalability and manageability.

4. **minimumStake()**
   - **Signature**: `minimumStake() returns (uint256)`
   - **Purpose**: Returns the minimum stake required for provider registration.
   - **Role in Business Process**:
     - **Pool Management**: Enforces staking requirements to ensure provider accountability.

5. **poolFactory()**
   - **Signature**: `poolFactory() returns (address)`
   - **Purpose**: Returns the address of the `MiningPoolFactory.sol` contract.
   - **Role in Business Process**:
     - **Pool Management**: Links the oracle registry to the factory contract for pool creation.

6. **poolProviders(uint256, uint256)**
   - **Signature**: `poolProviders(uint256, uint256) returns (address)`
   - **Purpose**: Retrieves the address of a provider associated with a specific pool and index.
   - **Role in Business Process**:
     - **Reward Distribution**: Maps providers to pools, ensuring accurate data routing.

7. **providerCounter()**
   - **Signature**: `providerCounter() returns (uint256)`
   - **Purpose**: Returns the total number of registered providers.
   - **Role in Business Process**:
     - **Pool Management**: Tracks active providers for governance and monitoring.

8. **providerPools(address, uint256)**
   - **Signature**: `providerPools(address, uint256) returns (uint256)`
   - **Purpose**: Retrieves the pool ID associated with a provider at a specific index.
   - **Role in Business Process**:
     - **Reward Distribution**: Links providers to pools for data submission.

9. **providerSlashCount(address)**
   - **Signature**: `providerSlashCount(address) returns (uint256)`
   - **Purpose**: Returns the number of times a provider has been slashed.
   - **Role in Business Process**:
     - **Pool Management**: Tracks provider reliability to ensure data integrity.

10. **providers(address)**
    - **Signature**: `providers(address) returns (address providerAddress, string name, string endpoint, bytes32 publicKey, uint256 stake, uint8 status, uint256 reputation, uint256 registeredAt, uint256 lastActiveAt, uint256 totalDataSubmitted, uint256 validSubmissions, uint256 invalidSubmissions)`
    - **Purpose**: Alias for `getProviderInfo`, retrieving detailed provider information.
    - **Role in Business Process**:
      - **Reward Distribution**: Verifies provider trustworthiness.

11. **registerProvider(string name, string endpoint, bytes32 publicKey)**
    - **Signature**: `registerProvider(string, string, bytes32) payable`
    - **Purpose**: Registers a new oracle provider with a stake.
    - **Role in Business Process**:
      - **Pool Management**: Expands the oracle network for data submission.

12. **slashProvider(address provider, uint256 amount, string reason)**
    - **Signature**: `slashProvider(address, uint256, string)`
    - **Purpose**: Slashes a provider's stake for misbehavior.
    - **Role in Business Process**:
      - **Pool Management**: Penalizes inaccurate data submissions.

13. **slashingCounter()**
    - **Signature**: `slashingCounter() returns (uint256)`
    - **Purpose**: Returns the total number of slashing events.
    - **Role in Business Process**:
      - **Pool Management**: Tracks slashing events for transparency.

14. **slashingRecords(uint256)**
    - **Signature**: `slashingRecords(uint256) returns (address provider, uint256 amount, string reason, uint256 timestamp, address slasher)`
    - **Purpose**: Retrieves details of a slashing event.
    - **Role in Business Process**:
      - **Pool Management**: Ensures accountability in the oracle network.

15. **submitData(uint256 poolId, bytes32 dataHash, bytes signature)**
    - **Signature**: `submitData(uint256, bytes32, bytes)`
    - **Purpose**: Allows providers to submit Stratum data for a pool.
    - **Role in Business Process**:
      - **Reward Distribution**: Supplies validated data for reward calculations.

16. **updateSettings(uint256 _minimumStake, uint256 _maxProviders)**
    - **Signature**: `updateSettings(uint256, uint256)`
    - **Purpose**: Updates oracle registry settings.
    - **Role in Business Process**:
      - **Pool Management**: Adjusts parameters for scalability and security.

17. **withdrawSlashedFunds(uint256 amount)**
    - **Signature**: `withdrawSlashedFunds(uint256)`
    - **Purpose**: Allows withdrawal of slashed funds.
    - **Role in Business Process**:
      - **Pool Management**: Distributes slashed funds as incentives or penalties.

## Call Chains for User Scenarios

Below are detailed call chains for manually executing the key user scenarios outlined in the business processes. These chains guide users through the sequence of contract interactions required to achieve each scenario, assuming access to a Web3 interface (e.g., ethers.js, web3.js) and appropriate permissions (e.g., miner, admin roles).

### Scenario 1: Reward Submission and mpToken Issuance
**Description**: A miner submits a coinbase transaction to the pool, which verifies it via SPV and issues `mp-token` to participants.

**Call Chain**:
1. **Miner Submits Reward**:
   - Contract: `MiningPoolDAO.sol`
   - Function: `submitReward(blockHeader, txRaw, merkleProof, vout)`
   - Parameters:
     - `blockHeader`: Raw block header of the mined block.
     - `txRaw`: Raw coinbase transaction.
     - `merkleProof`: Merkle proof for transaction inclusion.
     - `vout`: Output index of the coinbase transaction.
   - Action: Miner calls this function with mined block data.
   - Example (ethers.js):
     ```javascript
     const miningPoolDAO = new ethers.Contract(miningPoolDAOAddress, miningPoolDAOABI, signer);
     await miningPoolDAO.submitReward(blockHeader, txRaw, merkleProof, vout);
     ```

2. **SPV Verification**:
   - Contract: `SPVContract.sol`
   - Function: `checkTxInclusion(blockHash, txId, merkleProof, ...)`
   - Parameters:
     - `blockHash`: Hash of the block containing the transaction.
     - `txId`: Transaction ID of the coinbase.
     - `merkleProof`: Merkle proof array.
   - Action: `MiningPoolDAO` internally calls `SPVContract` to verify transaction inclusion.
   - Note: This is an internal call, not directly invoked by the user.

3. **Mint mpToken**:
   - Contract: `PoolMpToken.sol`
   - Function: `mint(to, amount)`
   - Parameters:
     - `to`: Address of the miner.
     - `amount`: Amount of `mp-token` to mint.
   - Action: `MiningPoolDAO` calls `PoolMpToken` to mint tokens for miners based on verified rewards.
   - Note: This is an internal call triggered by `submitReward`.

**Outcome**: Miners receive `mp-token` proportional to their shares in the pool.

### Scenario 2: Reward Distribution
**Description**: The pool distributes rewards to miners using a chosen reward scheme (e.g., FPPS).

**Call Chain**:
1. **Trigger Distribution**:
   - Contract: `MiningPoolDAO.sol`
   - Function: `distributeRewards(totalAmount, periodId, ...)`
   - Parameters:
     - `totalAmount`: Total reward amount to distribute.
     - `periodId`: Identifier for the reward period.
     - Additional parameters (e.g., calculator ID for FPPS).
   - Action: Pool admin or authorized caller initiates reward distribution.
   - Example (ethers.js):
     ```javascript
     const miningPoolDAO = new ethers.Contract(miningPoolDAOAddress, miningPoolDAOABI, signer);
     await miningPoolDAO.distributeRewards(totalAmount, periodId, calculatorId);
     ```

2. **Fetch Oracle Data**:
   - Contract: `StratumDataAggregator.sol`
   - Function: `getWorkerData(poolAddress)`
   - Parameters:
     - `poolAddress`: Address of the mining pool.
   - Action: `MiningPoolDAO` requests share and hashrate data from the aggregator.
   - Note: Internal call.

3. **Validate Data**:
   - Contract: `StratumDataValidator.sol`
   - Function: `validateBatch(poolId, dataHash, ...)`
   - Parameters:
     - `poolId`: ID of the pool.
     - `dataHash`: Hash of the submitted data.
   - Action: `StratumDataAggregator` validates data with `StratumDataValidator`.
   - Note: Internal call.

4. **Get Calculator**:
   - Contract: `CalculatorRegistry.sol`
   - Function: `getCalculator(calculatorId)`
   - Parameters:
     - `calculatorId`: ID of the reward scheme (e.g., FPPS).
   - Action: `MiningPoolDAO` retrieves the address of the reward calculator.
   - Note: Internal call.

5. **Calculate Rewards**:
   - Contract: `FPPSCalculator.sol` (or other calculator)
   - Function: `calculate(totalAmount, WorkerData[], params)`
   - Parameters:
     - `totalAmount`: Total reward amount.
     - `WorkerData[]`: Array of miner share data.
     - `params`: Configuration for the reward scheme.
   - Action: Calculates reward distribution for miners.
   - Note: Internal call.

6. **Mint mpToken**:
   - Contract: `PoolMpToken.sol`
   - Function: `mint(worker, amount)`
   - Parameters:
     - `worker`: Miner’s address.
     - `amount`: Amount of `mp-token` to mint.
   - Action: Mints tokens for each miner based on calculated rewards.
   - Note: Internal call.

**Outcome**: Miners receive `mp-token` based on their contributions in the reward period.

### Scenario 3: mpToken to S-token Conversion
**Description**: Miners convert their pool-specific `mp-token` to network-wide `S-token` for cross-pool liquidity.

**Call Chain**:
1. **Initiate Conversion**:
   - Contract: `MiningPoolDAO.sol`
   - Function: `convert(mpTokenAmount)`
   - Parameters:
     - `mpTokenAmount`: Amount of `mp-token` to convert.
   - Action: Miner calls to convert `mp-token` to `S-token`.
   - Example (ethers.js):
     ```javascript
     const miningPoolDAO = new ethers.Contract(miningPoolDAOAddress, miningPoolDAOABI, signer);
     await miningPoolDAO.convert(mpTokenAmount);
     ```

2. **Forward Reward**:
   - Contract: `MultiPoolDAO.sol`
   - Function: `receiveReward(poolId, blockHeader, txRaw, vout, proof)`
   - Parameters:
     - `poolId`: ID of the pool.
     - `blockHeader`, `txRaw`, `vout`, `proof`: SPV data for reward verification.
   - Action: `MiningPoolDAO` forwards verified reward data to `MultiPoolDAO`.
   - Note: Internal call.

3. **SPV Verification**:
   - Contract: `SPVContract.sol`
   - Function: `checkTxInclusion(blockHash, txId, merkleProof, ...)`
   - Action: `MultiPoolDAO` verifies the reward’s UTXO.
   - Note: Internal call.

4. **Mint S-token**:
   - Contract: `PoolSToken.sol`
   - Function: `mint(to, amount)`
   - Parameters:
     - `to`: Miner’s address.
     - `amount`: Amount of `S-token` to mint.
   - Action: `MultiPoolDAO` mints `S-token` for the miner.
   - Note: Internal call.

**Outcome**: Miner receives `S-token`, which is liquid across pools and DeFi-ready.

### Scenario 4: Redemption to Native Network
**Description**: A user redeems `mp-token` or `S-token` for native assets (e.g., BTC) using FROST signatures.

**Call Chain**:
1. **Initiate Redemption**:
   - Contract: `MiningPoolDAO.sol`
   - Function: `redeem(amount, btcScript)`
   - Parameters:
     - `amount`: Amount of tokens to redeem.
     - `btcScript`: Bitcoin script for the payout address.
   - Action: User initiates redemption.
   - Example (ethers.js):
     ```javascript
     const miningPoolDAO = new ethers.Contract(miningPoolDAOAddress, miningPoolDAOABI, signer);
     await miningPoolDAO.redeem(amount, btcScript);
     ```

2. **Burn Tokens**:
   - Contract: `PoolMpToken.sol` or `PoolSToken.sol`
   - Function: `burn(amount)`
   - Parameters:
     - `amount`: Amount of tokens to burn.
   - Action: Burns the user’s tokens.
   - Note: Internal call.

3. **Create FROST Session**:
   - Contract: `FROSTCoordinator.sol`
   - Function: `createSession(...)`
   - Action: Initiates a FROST signature session.
   - Note: Internal call.

4. **Aggregate Signature**:
   - Contract: `FROSTCoordinator.sol`
   - Function: `aggregateSignature(...)`
   - Action: Collects partial signatures and aggregates them.
   - Note: Internal call, requires off-chain coordination among signers.

5. **Verify Transaction**:
   - Contract: `SPVContract.sol`
   - Function: `checkTxInclusion(txid)`
   - Parameters:
     - `txid`: Transaction ID of the redemption transaction.
   - Action: Verifies the transaction’s inclusion in the Bitcoin blockchain.
   - Note: Internal call.

**Outcome**: User receives native BTC in their specified address.

## System Limitations

The Mining Pool System, while robust, has several limitations that users and developers should consider:

1. **Incomplete UI and Off-chain Integration**:
   - **Limitation**: The MVP checklist indicates that the UI and off-chain agent integration for automated signature submission are not yet implemented.
   - **Impact**: Manual execution of scenarios (e.g., FROST signature coordination) requires technical expertise and external tools, limiting accessibility for non-technical users.
   - **Mitigation**: Develop a user-friendly interface and automate off-chain processes like FROST signature collection.

2. **Gas Costs**:
   - **Limitation**: Complex operations like SPV verification, FROST signature aggregation, and reward distribution involve multiple contract calls, leading to high gas costs on Ethereum.
   - **Impact**: High transaction fees may deter small-scale miners or frequent interactions.
   - **Mitigation**: Deploy on layer-2 solutions (e.g., Optimism, Arbitrum) or optimize contract logic to reduce gas consumption.

3. **SPV Verification Constraints**:
   - **Limitation**: SPV requires 100 confirmations for UTXO maturity, delaying reward processing.
   - **Impact**: Miners face delays in receiving `mp-token` or `S-token` after mining a block.
   - **Mitigation**: Communicate expected delays to users and explore faster verification methods where secure.

4. **FROST Coordination Complexity**:
   - **Limitation**: FROST threshold signatures require coordination among multiple parties to produce partial signatures, which is not yet automated.
   - **Impact**: Redemption to native networks is slow and requires manual coordination, increasing operational overhead.
   - **Mitigation**: Implement off-chain agents to automate signature collection and submission.

5. **Centralization Risk in MultiPoolDAO**:
   - **Limitation**: The `MultiPoolDAO` acts as a central coordinator for cross-pool rewards, creating a potential single point of failure or governance risk.
   - **Impact**: Compromise or mismanagement of `MultiPoolDAO` could disrupt `S-token` minting and cross-pool operations.
   - **Mitigation**: Implement robust governance mechanisms and decentralize `MultiPoolDAO` operations further.

6. **Limited Network Support**:
   - **Limitation**: The system currently supports BTC and DOGE, with potential for LTC/BCH, but other networks are not yet integrated.
   - **Impact**: Restricts the system’s applicability to other cryptocurrencies.
   - **Mitigation**: Expand SPV and token support for additional networks as needed.

7. **Testing and Documentation Gaps**:
   - **Limitation**: The MVP checklist notes incomplete end-to-end tests and investor documentation.
   - **Impact**: Potential vulnerabilities in untested scenarios and lack of clarity for stakeholders.
   - **Mitigation**: Complete comprehensive testing and develop detailed investor documentation.

8. **Oracle Reliability**:
   - **Limitation**: The system relies on Stratum oracles for share and hashrate data, which could be manipulated if providers collude or submit invalid data.
   - **Impact**: Inaccurate data could lead to unfair reward distribution.
   - **Mitigation**: Strengthen slashing mechanisms and increase the number of trusted providers to reduce collusion risks.

## Process Flowcharts

### Reward Distribution Flow
```mermaid
sequenceDiagram
    participant Miner
    participant MiningPoolDAO
    participant StratumDataAggregator
    participant StratumDataValidator
    participant CalculatorRegistry
    participant FPPSCalculator
    participant PoolMpToken
    participant MultiPoolDAO
    participant SPVContract
    participant PoolSToken

    Miner->>MiningPoolDAO: distributeRewards(totalAmount, periodId, ...)
    MiningPoolDAO->>StratumDataAggregator: getWorkerData(poolAddress)
    StratumDataAggregator->>StratumDataValidator: validateBatch(poolId, dataHash, ...)
    StratumDataValidator->>StratumDataAggregator: ValidationResult
    StratumDataAggregator->>MiningPoolDAO: WorkerData[]
    MiningPoolDAO->>CalculatorRegistry: getCalculator(calculatorId)
    CalculatorRegistry->>MiningPoolDAO: FPPSCalculator address
    MiningPoolDAO->>FPPSCalculator: calculate(totalAmount, WorkerData[], params)
    FPPSCalculator->>MiningPoolDAO: DistributionResult[], distributed, remainder
    MiningPoolDAO->>PoolMpToken: mint(worker, amount)
    MiningPoolDAO->>MultiPoolDAO: receiveReward(poolId, blockHeaderRaw, txRaw, ...)
    MultiPoolDAO->>SPVContract: checkTxInclusion(blockHash, txId, merkleProof, ...)
    SPVContract->>MultiPoolDAO: Verified
    MultiPoolDAO->>PoolSToken: mint(recipient, amount)
    MiningPoolDAO->>Miner: Emit RewardsDistributed
```

### Redemption Flow
```mermaid
sequenceDiagram
    participant User
    participant MiningPoolDAO
    participant FROSTCoordinator
    participant SPV
    User->>MiningPoolDAO: redeem(amount, btcScript)
    MiningPoolDAO->>FROSTCoordinator: createSession
    FROSTCoordinator-->>MiningPoolDAO: aggregated signature
    MiningPoolDAO->>SPV: validate spend (tx inclusion)
    SPV-->>MiningPoolDAO: ok
    MiningPoolDAO-->>User: BTC UTXO released
```

## Tokenomics

| Token       | Level      | Purpose                                                                 |
|-------------|------------|-------------------------------------------------------------------------|
| **mpToken** | Pool       | Represents a miner's share in a specific pool's rewards.                 |
| **S-token** | Global     | Represents consolidated network assets, suitable for DeFi and staking.   |

- **mpToken**: Minted by `MiningPoolDAO` after SPV verification, used for internal pool accounting.
- **S-token**: Minted by `MultiPoolDAO` after cross-pool verification, providing network-wide liquidity.

## MVP Checklist
- [x] Contracts: `MiningPoolDAO`, `MultiPoolDAO`, `SPVContract`, `FROSTCoordinator`, `mpToken`, `S-token`.
- [x] Reward distribution and oracle aggregation.
- [x] Staking and slashing mechanisms for oracle providers.
- [ ] UI and off-chain agent integration for automated signature submission.
- [ ] Comprehensive end-to-end tests.
- [ ] Investor documentation (tokenomics, roadmap).

## Value Proposition
- **Miners**: Transparent reward distribution and secure withdrawals.
- **Investors**: Liquid `S-token` backed by on-chain SPV verification, DeFi-ready.
- **System**: Decentralized, trustless model with reduced fraud risk.

## Conclusion

The Mining Pool System provides a robust framework for managing mining pools, distributing rewards, and enabling cross-chain operations. The call chains provide a clear path for users to execute key scenarios, while the limitations highlight areas for future improvement. By leveraging SPV, FROST, and modular reward calculators, the system ensures transparency, security, and flexibility, with `StratumOracleRegistry.sol` playing a critical role in maintaining reliable data for reward distribution.