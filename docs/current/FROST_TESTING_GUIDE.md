# FROST Pool Creation Testing Guide

## Overview
This guide explains how to test the FROST (Flexible Round-Optimized Schnorr Threshold) pool creation flow with calculator assignment in the mining pool DAO system.

## Problem That Was Solved
The factory couldn't assign calculators to pools created from FROST sessions because:
1. `onlyPoolFactory` modifier in CalculatorRegistry was blocking access
2. Factory wasn't setting calculator in Rewards contract
3. Missing access control roles between contracts

## Solution Architecture

### Key Components
1. **FROSTCoordinator** - Manages distributed key generation (DKG) sessions
2. **MiningPoolFactory** - Creates mining pools with modular components
3. **CalculatorRegistry** - Manages reward calculation strategies (FPPS, PPS, etc.)
4. **Pool Components**:
   - MiningPoolCore - Main pool logic and FROST public key management
   - MiningPoolRewards - Reward distribution with calculator integration
   - MiningPoolExtensions - Additional features
   - MiningPoolRedemption - Bitcoin redemption handling

### Flow Diagram
```
DKG Session → FROST Coordinator → Group Public Key
                                        ↓
                              MiningPoolFactory
                                        ↓
                    Creates Pool Components with Calculator
                         ↓              ↓              ↓
                   Core Contract  Rewards Contract  mpToken
                         ↓              ↓
                   [Calculator ID] [Calculator ID]
```

## Installation & Setup

### Prerequisites
```bash
# Install Foundry if not already installed
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Navigate to project directory
cd /Users/exoldy/workspace/satohsi_test/web3
```

### Compilation
```bash
# Compile all contracts with optimizer enabled (required for stack depth)
forge build

# If you encounter stack too deep errors, ensure foundry.toml has:
# optimizer = true
# optimizer_runs = 1
# via_ir = true
```

## Running Tests

### Quick Test Commands

```bash
# Run all FROST pool creation tests
forge test --match-contract FROSTPoolCreationTest

# Run with verbose output to see details
forge test --match-contract FROSTPoolCreationTest -vv

# Run specific test
forge test --match-test testCreatePoolFromFrost -vv

# Run with gas reporting
forge test --match-contract FROSTPoolCreationTest --gas-report

# Run with coverage
forge coverage --match-contract FROSTPoolCreationTest
```

### Test Scenarios

#### 1. Calculator Registry Setup
```bash
forge test --match-test testCalculatorRegistrySetup -vv
```
**Tests**: Calculator registration, whitelisting, and retrieval
**Verifies**: Calculator can be accessed without factory restriction

#### 2. Pool Creation from FROST
```bash
forge test --match-test testCreatePoolFromFrost -vv
```
**Tests**: Complete pool creation flow from FROST session
**Verifies**:
- FROST session data extraction
- Pool component deployment
- Calculator assignment
- mpToken creation
- Pool registration

#### 3. Calculator Assignment
```bash
forge test --match-test testCalculatorAssignmentInPool -vv
```
**Tests**: Calculator properly assigned to both Core and Rewards
**Verifies**:
- Calculator ID set in Rewards contract
- Calculator address retrievable
- Both contracts have same calculator

#### 4. Multiple Pool Creation
```bash
forge test --match-test testMultiplePoolCreation -vv
```
**Tests**: Creating multiple pools with different parameters
**Verifies**:
- Different assets (BTC, ETH)
- Restricted vs unrestricted tokens
- Independent pool tracking

#### 5. Pool Management
```bash
forge test --match-test testPoolDeactivationAndReactivation -vv
```
**Tests**: Pool lifecycle management
**Verifies**:
- Deactivation by pool manager
- Reactivation by admin only
- State persistence

#### 6. Error Handling Tests
```bash
# Test invalid calculator rejection
forge test --match-test test_RevertWhen_CreatePoolWithInvalidCalculator -vv

# Test missing dependencies rejection
forge test --match-test test_RevertWhen_CreatePoolWithoutDependencies -vv
```

## Understanding the Solution

### 1. Removed Access Restriction
**File**: `contracts/src/calculators/CalculatorRegistry.sol`
```solidity
// BEFORE: Only factory could get calculator
function getCalculator(uint256 calculatorId)
    external
    onlyPoolFactory  // ← This was blocking access
    returns (address)

// AFTER: Any contract can get calculator
function getCalculator(uint256 calculatorId)
    external
    validCalculator(calculatorId)
    activeCalculator(calculatorId)
    returns (address)
```

### 2. Added Calculator to Rewards
**File**: `contracts/src/factory/MiningPoolFactory.sol`
```solidity
// Now sets calculator in both Core AND Rewards
MiningPoolCoreV2(poolCore).setCalculator(params.calculatorId);

// NEW: Also set in Rewards contract
MiningPoolRewardsV2(poolRewards).setCalculator(params.calculatorId);
```

### 3. Proper Access Control Setup
**File**: `test/FROSTPoolCreation.t.sol`
```solidity
// Grant factory permission to create tokens
poolTokenFactory.grantRole(
    poolTokenFactory.POOL_FACTORY_ROLE(),
    address(factory)
);
```

## Debugging Tips

### View Detailed Test Output
```bash
# Maximum verbosity (-vvvv)
forge test --match-test testCreatePoolFromFrost -vvvv

# With stack traces
forge test --match-test testCreatePoolFromFrost -vvv --gas-report
```

### Check Specific Failures
```bash
# If a test fails, run with -vvv to see the revert reason
forge test --match-test <failing_test_name> -vvv

# Example output will show:
# [FAIL: AccessControlUnauthorizedAccount(address, bytes32)]
# This indicates missing role assignment
```

### Verify Contract State
```bash
# Use forge script to interact with deployed contracts
forge script script/CheckPoolState.s.sol --rpc-url local
```

## Expected Test Output

Successful run should show:
```
Ran 8 tests for test/FROSTPoolCreation.t.sol:FROSTPoolCreationTest
[PASS] testCalculatorAssignmentInPool() (gas: ~16M)
[PASS] testCalculatorRegistrySetup() (gas: ~39K)
[PASS] testCreatePoolFromFrost() (gas: ~16M)
[PASS] testGetCalculatorWithoutPoolFactory() (gas: ~65K)
[PASS] testMultiplePoolCreation() (gas: ~32M)
[PASS] testPoolDeactivationAndReactivation() (gas: ~16M)
[PASS] test_RevertWhen_CreatePoolWithInvalidCalculator() (gas: ~45K)
[PASS] test_RevertWhen_CreatePoolWithoutDependencies() (gas: ~16M)

Suite result: ok. 8 passed; 0 failed; 0 skipped
```

## Integration Testing

### Local Deployment Test
```bash
# Deploy contracts locally
forge script script/Deploy.s.sol --rpc-url local --broadcast

# Run integration tests
forge test --fork-url local --match-contract Integration
```

### Mainnet Fork Testing
```bash
# Test against mainnet fork
forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY
```

## Common Issues & Solutions

### Issue: Stack too deep
**Solution**: Enable via_ir optimizer in foundry.toml
```toml
[profile.default]
optimizer = true
optimizer_runs = 1
via_ir = true
```

### Issue: AccessControl errors
**Solution**: Ensure all role grants are in place:
- Factory needs POOL_FACTORY_ROLE on PoolTokenFactory
- Factory needs ADMIN_ROLE on itself
- Test accounts need proper roles

### Issue: Calculator not found
**Solution**: Verify calculator is:
1. Registered in CalculatorRegistry
2. Whitelisted by admin
3. Active status

## Summary

The FROST pool creation system now successfully:
- ✅ Creates pools from FROST DKG sessions
- ✅ Assigns calculators to both Core and Rewards contracts
- ✅ Manages pool lifecycle (create, deactivate, reactivate)
- ✅ Handles multiple pools with different parameters
- ✅ Properly validates and rejects invalid operations

All tests pass, confirming the complete flow works end-to-end.