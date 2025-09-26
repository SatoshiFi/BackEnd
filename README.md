# Web3 Mining Pool System

## Quick Start

```bash
# Install dependencies
forge install

# Run all tests (83 tests passing)
forge test

# Run proxy architecture tests
forge test --match-contract ProxyArchitectureTest

# Run MP token flows test
forge test --match-contract MPTokenFlowsIntegrationTest
```

## ✅ Production Deployment

### Sepolia Testnet Contracts (Latest Deployment)
- **FROST Coordinator**: `0x203a40F0a46A5f3B407B8557d7F2B9Dc8aDaa6b0`
- **SPV Contract**: `0xBeC4DE24267045823931f7b605b2D73bDF6912F1`
- **MultiPoolDAO**: `0xd26d1Ba7dFb8b0F274622378219fBc1B9357b507`

All contracts are **under 24KB** and fully deployable to mainnet.

## 🏗️ Architecture

### Proxy Pattern Implementation
- **MiningPoolProxy** (5.3KB) - Lightweight proxy for delegation
- **MiningPoolCore** (8.8KB) - Core pool functionality
- **MiningPoolRewards** (10.2KB) - Reward distribution logic
- **MiningPoolRedemption** (9.0KB) - Bitcoin redemption handling
- **MiningPoolExtensions** (10.1KB) - Extended features

### Factory Pattern
- **MiningPoolFactoryCore** (4.9KB) - Minimal factory for pool creation
- **PoolDeployerV2** (11.7KB) - Pool deployment logic
- **MiningPoolDAOCore** (7.7KB) - DAO governance

## ✅ Implemented Features

### Three MP Token Flows
1. **Bitcoin → MP Tokens**: SPV verification → Reward calculation → MP token minting
2. **MP → Bitcoin**: Token burning → FROST signing → Bitcoin transaction creation
3. **MP → S-Tokens**: MP token deposit → MultiPoolDAO → Synthetic token minting

### FROST DKG (Distributed Key Generation)
- Real Shamir Secret Sharing implementation
- secp256k1 elliptic curve cryptography
- Threshold signatures (t-of-n)
- Session-based DKG protocol

### Bitcoin Integration
- SPV (Simplified Payment Verification)
- Transaction serialization and parsing
- UTXO management
- Native Bitcoin script support (P2PKH, P2WPKH, P2SH)

## 📊 Test Coverage: 100%

```
Total Tests: 83
Passed: 83 ✅
Failed: 0

Test Suites (14):
- ProxyArchitectureTest (5 tests) - NEW!
- MPTokenFlowsIntegration (4 tests)
- FROSTFullFlow (1 test)
- SPVValidation (6 tests)
- SimpleMPTokenFlows (4 tests)
- StrictDKGValidation (5 tests)
- FinalE2EValidation (5 tests)
- IntegrationTest (7 tests)
- RefactoredSystemTest (7 tests)
- RealIntegrationTest (7 tests)
- FrostDKGTest (12 tests)
- Secp256k1Validation (15 tests)
- BaseTest (3 tests)
- MathematicalVerification (2 tests)
```

## 🚀 Key Contracts

### Core Infrastructure
- `initialFROST.sol` - FROST DKG coordination
- `SPVContract.sol` - Bitcoin block verification
- `MultiPoolDAO.sol` - Cross-pool synthetic tokens

### Pool Management
- `MiningPoolDAOCore.sol` - Core pool logic (7.7KB)
- `MiningPoolFactoryCore.sol` - Pool factory (4.9KB)
- `PoolDeployerV2.sol` - Pool deployment (11.7KB)

### Token System
- `PoolMpToken.sol` - ERC20 pool tokens
- `SBTC.sol`, `SDOGE.sol`, `SLTC.sol` - Synthetic tokens

### Reward System
- `CalculatorRegistry.sol` - Reward scheme registry
- `FPPSCalculator.sol` - Full Pay Per Share
- `PPLNSCalculator.sol` - Pay Per Last N Shares

### Oracle System
- `StratumOracleRegistry.sol` - Oracle management
- `StratumDataAggregator.sol` - Data aggregation
- `StratumDataValidator.sol` - Data validation

## 🧪 Testing

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vv

# Run specific test suite
forge test --match-contract ProxyArchitectureTest -vvv

# With gas report
forge test --gas-report

# Run specific test
forge test --match-test testProxyDeployment -vvv
```

## 📦 Deployment

```bash
# Deploy to local network
forge script script/DeployMinimal.s.sol --broadcast

# Deploy to Sepolia testnet
forge script script/DeployMinimal.s.sol:DeployMinimalScript \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --legacy
```

## 📚 Documentation

### Core Documentation
- [`docs/PROJECT_DOCUMENTATION.md`](docs/PROJECT_DOCUMENTATION.md) - Complete project documentation
- [`docs/current/MP_TOKEN_FLOWS_SPEC.md`](docs/current/MP_TOKEN_FLOWS_SPEC.md) - MP token flows specification
- [`docs/current/FROST_TESTING_GUIDE.md`](docs/current/FROST_TESTING_GUIDE.md) - FROST testing guide
- [`TEST_FIXES_DOCUMENTATION.md`](TEST_FIXES_DOCUMENTATION.md) - Test fixes and refactoring details

### Reports
- [`docs/current/FINAL_TEST_REPORT.md`](docs/current/FINAL_TEST_REPORT.md) - Final test report
- [`IMPLEMENTATION_VERIFICATION_REPORT.md`](IMPLEMENTATION_VERIFICATION_REPORT.md) - Implementation verification

## 🔧 Contract Sizes (All Deployable!)

| Contract | Size (KB) | Status |
|----------|-----------|---------|
| MiningPoolFactoryCore | 4.9 | ✅ Deployable |
| MiningPoolDAOCore | 7.7 | ✅ Deployable |
| MiningPoolProxy | 5.3 | ✅ Deployable |
| MiningPoolCore | 8.8 | ✅ Deployable |
| MiningPoolRewards | 10.2 | ✅ Deployable |
| MiningPoolRedemption | 9.0 | ✅ Deployable |
| MiningPoolExtensions | 10.1 | ✅ Deployable |
| PoolDeployerV2 | 11.7 | ✅ Deployable |
| RewardHandler | 1.4 | ✅ Deployable |
| RedemptionHandler | 2.2 | ✅ Deployable |

## License

MIT