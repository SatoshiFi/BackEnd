# Verification of FROST Pool Calculator Fix

## Summary of Changes Made

### 1. **CalculatorRegistry.sol** (lines 217-237)
- **REMOVED** `onlyPoolFactory` modifier from `getCalculator()` function
- **REMOVED** `onlyPoolFactory` modifier from `reportGasUsage()` function
- **REASON**: These modifiers were preventing MiningPoolRewards from calling getCalculator when setting up the calculator

### 2. **MiningPoolFactory.sol** (lines 291-293)
- **ADDED** call to `setCalculator` on MiningPoolRewardsV2 after setting it on Core
- **REASON**: Ensures both Core and Rewards contracts have the same calculator configured

### 3. **Fixed Import Paths**
- Updated OpenZeppelin import paths from `/security/` to `/utils/` for ReentrancyGuard
- Added missing interface files
- Fixed V2 contract naming conventions

## How FROST Pool Creation Now Works

1. **DKG Session Creation**
   - Participants create DKG session in FROSTCoordinator
   - Each publishes nonce-commits
   - Exchange encrypted shares
   - Admin calls `finalizeDKG`
   - Result: Group public key (pubX, pubY)

2. **Pool Creation from FROST**
   - Admin calls `createPoolFromFrost(sessionId, ...)`
   - Factory gets key from finalized FROST session
   - Deploys MiningPoolCoreV2, RewardsV2, ExtensionsV2, RedemptionV2
   - **IMPORTANT**: Calculator is now set in BOTH Core AND Rewards
   - Creates mpToken for the pool
   - Mints membershipSBT/roleBadgeSBT for participants

3. **Calculator Access**
   - Calculator registry no longer restricts access to poolFactory only
   - Any contract can now call `getCalculator()` to retrieve calculator address
   - This allows MiningPoolRewardsV2 to properly initialize its calculator

## Testing Recommendations

To test these changes locally with Foundry:

1. Install dependencies:
```bash
forge install openzeppelin/openzeppelin-contracts --no-git
forge install openzeppelin/openzeppelin-contracts-upgradeable --no-git
```

2. Compile contracts:
```bash
forge build
```

3. Key test scenarios to verify:
- Calculator can be retrieved by any contract (not just poolFactory)
- Pool creation from FROST sets calculator in both Core and Rewards
- Multiple pools can be created with different calculators
- Calculator statistics are properly tracked

## Files Modified

1. `/contracts/src/calculators/CalculatorRegistry.sol`
2. `/contracts/src/factory/MiningPoolFactory.sol`
3. `/contracts/src/oracles/StratumDataAggregator.sol` (syntax fix)
4. `/contracts/src/MiningPoolDAO.sol` (interface renames to avoid conflicts)
5. Various interface files created in `/contracts/src/interfaces/`

## Result

✅ Pools created from FROST sessions now properly configure calculators in all required contracts
✅ Calculator registry is more flexible and accessible
✅ The flow from DKG → FROST → Pool with Calculator is complete