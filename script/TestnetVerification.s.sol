// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/src/initialFROST.sol";
import "../contracts/src/SPVContractDogecoin.sol";
import "../contracts/src/MultiPoolDAO.sol";
import "../contracts/src/factory/MiningPoolFactoryCore.sol";
import "../contracts/src/factory/PoolTokenFactory.sol";
import "../contracts/src/calculators/CalculatorRegistry.sol";
import {SBTC} from "../contracts/src/tokens/SBTC.sol";
import {SDOGE} from "../contracts/src/tokens/SDOGE.sol";
import {SLTC} from "../contracts/src/tokens/SLTC.sol";
import "../contracts/src/tokens/PoolMpToken.sol";
import "../contracts/src/MiningPoolDAOCore.sol";

contract TestnetVerificationScript is Script {
    // Deployed addresses from our deployment
    address constant FROST_ADDR = 0x403C36f5e05Fb339bfC4f28f44B6c31f9DC8fB95;
    address constant SPV_ADDR = 0xa756B82e2e2031f3516BA09Dd3a7FaE3B817Bb7A;
    address constant MULTI_POOL_DAO_ADDR = 0x71271B71B142BBF4De69F792b4f41B27681Bd6a5;
    address constant FACTORY_ADDR = 0x6BfDF4BcA6Af2fFA2cC006C4c6005c7185928Ab2;
    address constant TOKEN_FACTORY_ADDR = 0x966f955AFFDDDF7e4B7e884d74574a2Db85986C6;
    address constant CALC_REGISTRY_ADDR = 0x4f38B180b42Ec0C21dB931bA8aEB60fc7abcd08C;
    address constant SBTC_ADDR = 0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8;
    address constant SDOGE_ADDR = 0x8c244DdC5481e504Dde727e45414ea335877CB4F;
    address constant SLTC_ADDR = 0xB967ba4E97B882b5B089419e6a2DDe891f8e5d72;

    // Test participants
    address alice;
    address bob;
    address charlie;

    // Test state
    uint256 sessionId;
    address poolAddress;
    address mpTokenAddress;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Generate test accounts
        alice = vm.addr(uint256(keccak256("alice")));
        bob = vm.addr(uint256(keccak256("bob")));
        charlie = vm.addr(uint256(keccak256("charlie")));

        console.log("==================================================");
        console.log("    TESTNET CONTRACT VERIFICATION");
        console.log("==================================================");
        console.log("Network: Sepolia");
        console.log("Deployer:", deployer);
        console.log("\nTest Participants:");
        console.log("  Alice:", alice);
        console.log("  Bob:", bob);
        console.log("  Charlie:", charlie);

        vm.startBroadcast(deployerKey);

        // Run all verification tests
        bool allTestsPassed = true;

        console.log("\n[TEST SUITE 1] Basic Contract Checks");
        console.log("======================================");
        if (!testBasicContracts()) allTestsPassed = false;

        console.log("\n[TEST SUITE 2] FROST DKG Session");
        console.log("======================================");
        if (!testFrostDKG()) allTestsPassed = false;

        console.log("\n[TEST SUITE 3] Factory Pool Creation");
        console.log("======================================");
        if (!testFactoryPoolCreation()) allTestsPassed = false;

        console.log("\n[TEST SUITE 4] MP Token Operations");
        console.log("======================================");
        if (!testMPTokenOperations()) allTestsPassed = false;

        console.log("\n[TEST SUITE 5] Synthetic Tokens");
        console.log("======================================");
        if (!testSyntheticTokens()) allTestsPassed = false;

        vm.stopBroadcast();

        // Final report
        console.log("\n==================================================");
        console.log("    VERIFICATION COMPLETE");
        console.log("==================================================");
        if (allTestsPassed) {
            console.log("[SUCCESS] ALL TESTS PASSED!");
            console.log("The deployed contracts are working correctly.");
        } else {
            console.log("[FAIL] SOME TESTS FAILED");
            console.log("Please check the logs above for details.");
        }
    }

    function testBasicContracts() internal returns (bool) {
        console.log("\n1. Checking FROST contract...");
        try initialFROSTCoordinator(FROST_ADDR).getCustodians() returns (address[] memory custodians) {
            console.log("   [OK] FROST is responsive, custodians count:", custodians.length);
        } catch {
            console.log("   [FAIL] FROST contract not responding");
            return false;
        }

        console.log("\n2. Checking SPV contract...");
        // Just check if contract is deployed by calling a simple function
        try SPVContractDogecoin(SPV_ADDR).blockExists(bytes32(0)) returns (bool exists) {
            console.log("   [OK] SPV is responsive, block check returned:", exists);
        } catch {
            console.log("   [FAIL] SPV contract not responding");
            return false;
        }

        console.log("\n3. Checking MultiPoolDAO...");
        // Check if role exists (basic check)
        bytes32 adminRole = MultiPoolDAO(MULTI_POOL_DAO_ADDR).ADMIN_ROLE();
        if (adminRole != bytes32(0)) {
            console.log("   [OK] MultiPoolDAO is responsive, admin role:", uint256(adminRole));
        } else {
            console.log("   [FAIL] MultiPoolDAO not responding");
            return false;
        }

        console.log("\n4. Checking Factory...");
        try MiningPoolFactoryCore(FACTORY_ADDR).getPoolCount() returns (uint256 count) {
            console.log("   [OK] Factory is responsive, pools created:", count);
        } catch {
            console.log("   [FAIL] Factory not responding");
            return false;
        }

        return true;
    }

    function testFrostDKG() internal returns (bool) {
        console.log("\n1. Creating DKG session...");

        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;

        try initialFROSTCoordinator(FROST_ADDR).createDKGSession(2, participants) returns (uint256 id) {
            sessionId = id;
            console.log("   [OK] Session created with ID:", sessionId);
        } catch Error(string memory reason) {
            console.log("   [FAIL] Failed to create session:", reason);
            return false;
        }

        console.log("\n2. Session created successfully");
        console.log("   Session can be used for DKG process");

        return true;
    }

    function testFactoryPoolCreation() internal returns (bool) {
        console.log("\n1. Creating pool through factory...");

        // Use dummy pubkey for testing
        uint256 pubX = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        uint256 pubY = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;

        MiningPoolFactoryCore.PoolParams memory params = MiningPoolFactoryCore.PoolParams({
            asset: "BTC",
            poolId: "TESTNET-POOL-001",
            pubX: pubX,
            pubY: pubY,
            mpName: "Test MP Token",
            mpSymbol: "tMP",
            restrictedMp: false,
            payoutScript: hex"76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac",
            calculatorId: 0
        });

        try MiningPoolFactoryCore(FACTORY_ADDR).createPool(params) returns (address pool, address mpToken) {
            poolAddress = pool;
            mpTokenAddress = mpToken;
            console.log("   [OK] Pool created at:", pool);
            console.log("   [OK] MP Token at:", mpToken);
        } catch Error(string memory reason) {
            console.log("   [FAIL] Pool creation failed:", reason);
            return false;
        }

        console.log("\n2. Verifying pool in factory registry...");
        uint256 poolCount = MiningPoolFactoryCore(FACTORY_ADDR).getPoolCount();
        console.log("   [OK] Total pools in factory:", poolCount);

        console.log("\n3. Checking if pool is valid...");
        if (MiningPoolFactoryCore(FACTORY_ADDR).isValidPool(poolAddress)) {
            console.log("   [OK] Pool is registered as valid");
        } else {
            console.log("   [FAIL] Pool not registered");
            return false;
        }

        return true;
    }

    function testMPTokenOperations() internal returns (bool) {
        if (mpTokenAddress == address(0)) {
            console.log("   [SKIP]  Skipping - no MP token created");
            return true;
        }

        console.log("\n1. Checking MP token properties...");
        PoolMpToken token = PoolMpToken(mpTokenAddress);

        try token.name() returns (string memory name) {
            console.log("   [OK] Token name:", name);
        } catch {
            console.log("   [FAIL] Cannot get token name");
            return false;
        }

        try token.symbol() returns (string memory symbol) {
            console.log("   [OK] Token symbol:", symbol);
        } catch {
            console.log("   [FAIL] Cannot get token symbol");
            return false;
        }

        try token.totalSupply() returns (uint256 supply) {
            console.log("   [OK] Total supply:", supply);
        } catch {
            console.log("   [FAIL] Cannot get total supply");
            return false;
        }

        console.log("\n2. Checking pool linkage...");
        MiningPoolDAOCore pool = MiningPoolDAOCore(poolAddress);
        try pool.poolToken() returns (address linkedToken) {
            if (linkedToken == mpTokenAddress) {
                console.log("   [OK] Token correctly linked to pool");
            } else {
                console.log("   [FAIL] Token not linked to pool");
                return false;
            }
        } catch {
            console.log("   [FAIL] Cannot check pool token");
            return false;
        }

        return true;
    }

    function testSyntheticTokens() internal returns (bool) {
        console.log("\n1. Testing sBTC token...");
        SBTC sbtc = SBTC(SBTC_ADDR);

        try sbtc.name() returns (string memory name) {
            console.log("   [OK] sBTC name:", name);
        } catch {
            console.log("   [FAIL] sBTC not accessible");
            return false;
        }

        try sbtc.symbol() returns (string memory symbol) {
            console.log("   [OK] sBTC symbol:", symbol);
        } catch {
            console.log("   [FAIL] Cannot get sBTC symbol");
            return false;
        }

        console.log("\n2. Testing sDOGE token...");
        SDOGE sdoge = SDOGE(SDOGE_ADDR);

        try sdoge.name() returns (string memory name) {
            console.log("   [OK] sDOGE name:", name);
        } catch {
            console.log("   [FAIL] sDOGE not accessible");
            return false;
        }

        console.log("\n3. Testing sLTC token...");
        SLTC sltc = SLTC(SLTC_ADDR);

        try sltc.name() returns (string memory name) {
            console.log("   [OK] sLTC name:", name);
        } catch {
            console.log("   [FAIL] sLTC not accessible");
            return false;
        }

        console.log("\n4. All synthetic tokens deployed and accessible");

        return true;
    }
}