#!/bin/bash

# Deploy script for Sepolia testnet

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Deploying to Sepolia Testnet        ${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Check if private key is provided
if [ -z "$1" ]; then
    echo -e "${YELLOW}Using default private key from command...${NC}"
    PRIVATE_KEY="524edd8063e12ad62457da01e4f1ec3b327dd54b97b5d5879744accb4ab779a7"
else
    PRIVATE_KEY="$1"
fi

# RPC URL for Sepolia
RPC_URL="https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA"

# Export for forge script
export PRIVATE_KEY=$PRIVATE_KEY

# Create deployments directory if it doesn't exist
mkdir -p deployments

echo -e "${YELLOW}Building contracts...${NC}"
forge build

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed! Please fix compilation errors.${NC}"
    exit 1
fi

echo -e "${GREEN}Build successful!${NC}\n"

echo -e "${YELLOW}Starting deployment...${NC}"
echo -e "RPC URL: $RPC_URL"
echo -e "Deployer address: $(cast wallet address --private-key $PRIVATE_KEY)\n"

# Check balance
BALANCE=$(cast balance --rpc-url $RPC_URL $(cast wallet address --private-key $PRIVATE_KEY))
echo -e "Deployer balance: $BALANCE ETH\n"

# Deploy contracts
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --legacy \
    --verify \
    --etherscan-api-key "YOUR_ETHERSCAN_API_KEY" \
    -vvvv

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}   Deployment Successful!               ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment addresses saved to: deployments/sepolia.json${NC}"
else
    echo -e "\n${RED}========================================${NC}"
    echo -e "${RED}   Deployment Failed!                   ${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi