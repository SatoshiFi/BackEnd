# Guide to Registering Multiple Mining Pools with Workers

This document provides a comprehensive guide to registering multiple mining pools and their member workers in the decentralized Mining Pool System. It details the necessary contract interactions, call chains, and limitations, based on the system's architecture as described in the provided `README.md` and smart contract artifacts. The process involves creating pools via `MiningPoolFactory.sol`, registering workers with `PoolMembershipNFT.sol`, and configuring oracle providers via `StratumOracleRegistry.sol` to ensure accurate share tracking for reward distribution.

## Prerequisites

- **Web3 Interface**: Access to a Web3 provider (e.g., ethers.js, web3.js) connected to an Ethereum-compatible network where the contracts are deployed.
- **Permissions**: The caller must have appropriate roles (e.g., admin role in `MiningPoolFactory` or `StratumOracleRegistry`) to perform pool creation and configuration.
- **Contract Addresses**: Deployed addresses for `MiningPoolFactory.sol`, `PoolTokenFactory.sol`, `PoolMembershipNFT.sol`, `StratumOracleRegistry.sol`, and related contracts.
- **Funds**: Sufficient ETH for gas fees and staking requirements for oracle providers.
- **Data**: Prepared data for pool configurations (e.g., SPV settings, FROST thresholds) and worker addresses.

## System Components Involved

- **`MiningPoolFactory.sol`**: Deploys new `MiningPoolDAO` instances for each pool, configuring SPV, FROST, and token dependencies.
- **`PoolTokenFactory.sol`**: Creates `mp-token` (pool-specific ERC20 token) and `PoolMembershipNFT` for each pool.
- **`PoolMembershipNFT.sol`**: Issues soulbound NFTs to register workers, ensuring only authorized miners participate.
- **`StratumOracleRegistry.sol`**: Manages oracle providers for share and hashrate data, critical for reward distribution.
- **`MiningPoolDAO.sol`**: Manages individual pools, including worker registration and share tracking.

## Call Chains for Registering Multiple Pools and Workers

The process involves two main phases: (1) creating multiple pools and (2) registering workers for each pool. Below are the detailed call chains for each phase, assuming the use of ethers.js for contract interactions.

### Phase 1: Creating Multiple Mining Pools

**Description**: An admin uses `MiningPoolFactory.sol` to deploy multiple `MiningPoolDAO` instances, each with its own `mp-token` and `PoolMembershipNFT`. Each pool is configured with specific parameters (e.g., SPV settings, FROST threshold, reward calculator).

**Call Chain**:

1. **Deploy a New Pool**:
   - **Contract**: `MiningPoolFactory.sol`
   - **Function**: `createPool(spvContract, frostContract, tokenFactory, calculatorRegistry, poolConfig)`
   - **Parameters** (inferred from system architecture):
     - `spvContract`: Address of the `SPVContract.sol` (or `SPVContractDogecoin.sol` for Dogecoin).
     - `frostContract`: Address of the `FROSTCoordinator.sol`.
     - `tokenFactory`: Address of the `PoolTokenFactory.sol`.
     - `calculatorRegistry`: Address of the `CalculatorRegistry.sol`.
     - `poolConfig`: Struct or parameters defining pool settings (e.g., reward scheme ID, network type, FROST threshold).
   - **Action**: Admin calls this function to deploy a new `MiningPoolDAO` instance, which triggers the creation of associated tokens and NFTs.
   - **Example (ethers.js)**:
     ```javascript
     const miningPoolFactory = new ethers.Contract(factoryAddress, miningPoolFactoryABI, signer);
     const poolConfig = {
       rewardSchemeId: 1, // e.g., FPPS
       networkType: "BTC", // or "DOGE"
       frostThreshold: 3 // Number of signers for FROST
     };
     const tx = await miningPoolFactory.createPool(
       spvContractAddress,
       frostContractAddress,
       tokenFactoryAddress,
       calculatorRegistryAddress,
       poolConfig
     );
     const receipt = await tx.wait();
     const poolAddress = receipt.events.find(e => e.event === "PoolCreated")?.args.poolAddress;
     ```

2. **Create mp-token for the Pool**:
   - **Contract**: `PoolTokenFactory.sol`
   - **Function**: `createMpToken(poolAddress, tokenName, tokenSymbol)`
   - **Parameters**:
     - `poolAddress`: Address of the newly created `MiningPoolDAO`.
     - `tokenName`: Name of the `mp-token` (e.g., "Pool1 MP Token").
     - `tokenSymbol`: Symbol of the `mp-token` (e.g., "MP1").
   - **Action**: `MiningPoolFactory` internally calls `PoolTokenFactory` to create the pool’s ERC20 `mp-token`.
   - **Note**: This is an internal call triggered by `createPool`. The admin may need to verify the token address from the `PoolTokenFactory` event logs.
   - **Example (ethers.js, for verification)**:
     ```javascript
     const poolTokenFactory = new ethers.Contract(tokenFactoryAddress, poolTokenFactoryABI, signer);
     const mpTokenAddress = await poolTokenFactory.getMpToken(poolAddress);
     ```

3. **Create PoolMembershipNFT for the Pool**:
   - **Contract**: `PoolTokenFactory.sol`
   - **Function**: `createMembershipNFT(poolAddress, nftName, nftSymbol)`
   - **Parameters**:
     - `poolAddress`: Address of the `MiningPoolDAO`.
     - `nftName`: Name of the membership NFT (e.g., "Pool1 Membership").
     - `nftSymbol`: Symbol of the NFT (e.g., "PM1").
   - **Action**: `MiningPoolFactory` triggers the creation of a soulbound NFT contract for worker registration.
   - **Note**: Internal call within `createPool`. The admin verifies the NFT address via event logs.
   - **Example (ethers.js, for verification)**:
     ```javascript
     const nftAddress = await poolTokenFactory.getMembershipNFT(poolAddress);
     ```

4. **Repeat for Additional Pools**:
   - **Action**: Repeat steps 1–3 for each pool, varying `poolConfig` (e.g., different reward schemes or network types). Each pool will have a unique `MiningPoolDAO`, `mp-token`, and `PoolMembershipNFT`.
   - **Example**: Deploy pools for BTC and DOGE with different reward schemes (e.g., FPPS for Pool 1, PPLNS for Pool 2).

**Outcome**: Multiple `MiningPoolDAO` instances are deployed, each with its own `mp-token` and `PoolMembershipNFT`, ready for worker registration.

### Phase 2: Registering Workers for Each Pool

**Description**: Workers (miners) are registered in each pool by minting soulbound `PoolMembershipNFT`s, ensuring only authorized participants can contribute shares and receive rewards. Optionally, oracle providers are registered to supply share data.

**Call Chain**:

1. **Register a Worker**:
   - **Contract**: `PoolMembershipNFT.sol`
   - **Function**: `mint(address worker)`
   - **Parameters**:
     - `worker`: Address of the miner to register.
   - **Action**: The pool admin (or `MiningPoolDAO`) mints a soulbound NFT for the worker, granting them membership in the pool.
   - **Example (ethers.js)**:
     ```javascript
     const poolMembershipNFT = new ethers.Contract(nftAddress, poolMembershipNFTABI, signer);
     await poolMembershipNFT.mint(workerAddress);
     ```

2. **Verify Worker Registration**:
   - **Contract**: `PoolMembershipNFT.sol`
   - **Function**: `balanceOf(address worker)`
   - **Parameters**:
     - `worker`: Address of the miner.
   - **Action**: Checks if the worker has a membership NFT (balance >= 1 indicates registration).
   - **Example (ethers.js)**:
     ```javascript
     const balance = await poolMembershipNFT.balanceOf(workerAddress);
     console.log(`Worker registered: ${balance >= 1}`);
     ```

3. **Register Workers for Each Pool**:
   - **Action**: Repeat steps 1–2 for each worker in each pool. For example, Pool 1 might have workers A, B, C, while Pool 2 has workers D, E, F.
   - **Note**: Each worker receives a unique soulbound NFT specific to the pool’s `PoolMembershipNFT` contract.

4. **Optional: Register Oracle Providers for Share Tracking**:
   - **Contract**: `StratumOracleRegistry.sol`
   - **Function**: `registerProvider(string name, string endpoint, bytes32 publicKey)`
   - **Parameters**:
     - `name`: Name of the oracle provider.
     - `endpoint`: URL or endpoint for data submission.
     - `publicKey`: Public key for signing data.
   - **Action**: An oracle provider stakes the required amount (call `minimumStake()` to check) and registers to supply share and hashrate data for the pool.
   - **Example (ethers.js)**:
     ```javascript
     const stratumOracleRegistry = new ethers.Contract(oracleRegistryAddress, stratumOracleRegistryABI, signer);
     const minimumStake = await stratumOracleRegistry.minimumStake();
     await stratumOracleRegistry.registerProvider(
       "Provider1",
       "https://provider1.com/stratum",
       publicKey,
       { value: minimumStake }
     );
     ```

5. **Link Providers to Pools**:
   - **Contract**: `StratumOracleRegistry.sol`
   - **Function**: (Inferred) `addProviderToPool(address provider, uint256 poolId)`
   - **Parameters**:
     - `provider`: Address of the registered provider.
     - `poolId`: ID of the pool (retrieved from `MiningPoolDAO` deployment).
   - **Action**: Links the provider to the pool to enable data submission for reward calculations.
   - **Example (ethers.js)**:
     ```javascript
     await stratumOracleRegistry.addProviderToPool(providerAddress, poolId);
     ```

6. **Submit Share Data**:
   - **Contract**: `StratumOracleRegistry.sol`
   - **Function**: `submitData(uint256 poolId, bytes32 dataHash, bytes signature)`
   - **Parameters**:
     - `poolId`: ID of the pool.
     - `dataHash`: Hash of the share and hashrate data.
     - `signature`: Signed data for validation.
   - **Action**: The registered provider submits share data, which is validated and used by `MiningPoolDAO` for reward distribution.
   - **Example (ethers.js)**:
     ```javascript
     await stratumOracleRegistry.submitData(poolId, dataHash, signature);
     ```

**Outcome**: Each pool has a set of registered workers with soulbound NFTs, and oracle providers are configured to supply share data for reward distribution.

## Example Workflow for Two Pools

**Scenario**: Create two pools (Pool 1 for BTC with FPPS, Pool 2 for DOGE with PPLNS) and register three workers per pool.

1. **Create Pool 1 (BTC, FPPS)**:
   - Call `MiningPoolFactory.createPool(spvContractBTC, frostContract, tokenFactory, calculatorRegistry, {rewardSchemeId: 1, networkType: "BTC", frostThreshold: 3})`.
   - Retrieve `pool1Address`, `mpToken1Address`, and `nft1Address` from event logs.

2. **Create Pool 2 (DOGE, PPLNS)**:
   - Call `MiningPoolFactory.createPool(spvContractDogecoin, frostContract, tokenFactory, calculatorRegistry, {rewardSchemeId: 2, networkType: "DOGE", frostThreshold: 3})`.
   - Retrieve `pool2Address`, `mpToken2Address`, and `nft2Address`.

3. **Register Workers for Pool 1**:
   - Call `PoolMembershipNFT(nft1Address).mint(workerA)`, `mint(workerB)`, `mint(workerC)`.
   - Verify with `balanceOf(workerA)`, etc.

4. **Register Workers for Pool 2**:
   - Call `PoolMembershipNFT(nft2Address).mint(workerD)`, `mint(workerE)`, `mint(workerF)`.
   - Verify with `balanceOf(workerD)`, etc.

5. **Register Oracle Provider**:
   - Call `StratumOracleRegistry.registerProvider("Provider1", "https://provider1.com", publicKey, {value: minimumStake})`.
   - Link to pools: `addProviderToPool(providerAddress, pool1Id)`, `addProviderToPool(providerAddress, pool2Id)`.

6. **Submit Share Data**:
   - Call `StratumOracleRegistry.submitData(pool1Id, dataHash1, signature1)` for Pool 1.
   - Call `StratumOracleRegistry.submitData(pool2Id, dataHash2, signature2)` for Pool 2.

## Limitations

1. **Manual Configuration**:
   - **Limitation**: Pool creation and worker registration require manual calls to `MiningPoolFactory` and `PoolMembershipNFT`, which can be error-prone without a UI.
   - **Impact**: Increases the risk of misconfiguration (e.g., incorrect SPV or FROST settings).
   - **Mitigation**: Develop a UI or script to automate pool creation and validation.

2. **Gas Costs**:
   - **Limitation**: Deploying multiple `MiningPoolDAO` instances and minting NFTs incur significant gas costs.
   - **Impact**: High costs may limit the number of pools or workers for small-scale operators.
   - **Mitigation**: Use layer-2 solutions or optimize contract deployment.

3. **Soulbound NFT Restrictions**:
   - **Limitation**: `PoolMembershipNFT` is soulbound, meaning workers cannot transfer membership, which may limit flexibility.
   - **Impact**: Workers cannot delegate or sell their membership, potentially reducing participation.
   - **Mitigation**: Allow admin-controlled NFT burning and re-minting for worker updates.

4. **Oracle Dependency**:
   - **Limitation**: Pools rely on registered oracle providers for share data, and insufficient providers may delay reward distribution.
   - **Impact**: New pools may face delays if providers are not registered or active.
   - **Mitigation**: Incentivize provider registration with lower stakes or rewards.

5. **Permission Management**:
   - **Limitation**: Only authorized callers (e.g., admins with specific roles) can create pools or mint NFTs, requiring proper access control setup.
   - **Impact**: Misconfigured roles can block pool creation or worker registration.
   - **Mitigation**: Use `AccessControlUpgradeable.sol` to manage roles and ensure admin access is correctly assigned.

6. **Scalability Constraints**:
   - **Limitation**: `StratumOracleRegistry.maxProviders()` limits the number of oracle providers, which may restrict data availability for multiple pools.
   - **Impact**: Large numbers of pools may overwhelm the oracle network.
   - **Mitigation**: Increase `maxProviders` via `updateSettings` or distribute providers across pools efficiently.

7. **Testing Gaps**:
   - **Limitation**: The MVP checklist indicates incomplete end-to-end tests, which may affect pool creation and worker registration reliability.
   - **Impact**: Potential bugs in `MiningPoolFactory` or `PoolMembershipNFT` could disrupt operations.
   - **Mitigation**: Complete comprehensive testing before deploying multiple pools.

## Conclusion

Registering multiple mining pools and their workers involves deploying `MiningPoolDAO` instances via `MiningPoolFactory`, creating `mp-token` and `PoolMembershipNFT` for each pool, and registering workers with soulbound NFTs. Oracle providers are configured via `StratumOracleRegistry` to supply share data. The call chains provide a clear path for manual execution, while the limitations highlight areas for optimization, such as automating processes and reducing gas costs. This guide ensures that users can set up and manage multiple pools effectively within the Mining Pool System.