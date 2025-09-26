#!/bin/bash

# Install Foundry if not present
if ! command -v forge &> /dev/null; then
    echo "Installing Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    source ~/.bashrc 2>/dev/null || source ~/.zshrc 2>/dev/null || true
    foundryup
fi

# Navigate to web3 directory
cd /Users/exoldy/workspace/satohsi_test/web3

# Install dependencies
echo "Installing dependencies..."
forge install openzeppelin/openzeppelin-contracts --no-commit
forge install openzeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install foundry-rs/forge-std --no-commit

# Run tests
echo "Running FROST Pool Creation tests..."
forge test --match-contract FROSTPoolCreationTest -vvv

# Run specific tests with gas report
echo ""
echo "Running specific tests with gas report..."
forge test --match-test testCreatePoolFromFrost --gas-report

echo ""
echo "Testing calculator assignment..."
forge test --match-test testCalculatorAssignmentInPool -vv