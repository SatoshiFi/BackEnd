#!/bin/bash

# Загрузите .env и экспортируйте переменные
set -a
source .env
set +a

# Используйте правильное имя переменной
RPC_URL=${SEPOLIA_RPC_URL}

# Адреса из config.js
NEW_FACTORY=0xb87DB5fF6802A8B0bd48fb314234916f1BA27C1a
SPV=0xD7f2293659A000b37Fd3973B06d4699935c511e9
FROST=0x4d195A05F2d79E27b310dFB24733d86ffb214867
CALC_REGISTRY=0x9bB85b0134847Ca4f1976A3C58BAbb6fD69fE8E9
AGGREGATOR=0x8BC17298773DCfC7D1BA7768f3F153E63bEE4bb7
VALIDATOR=0x65075C39BE930f605e6aca53add3852a1724cb64
ORACLE_REGISTRY=0x1E384f7112857C9e0437779f441F65853df7Eb26
TOKEN_FACTORY=0xfBf82b62d66B1a2a9aE90b50354abAa8d7a35134
MULTIPOOL_DAO=0x032fec1b5E4179377c92243Bdd34F8f1EEA131b6
DEPLOYER=0xE91630F1A8e315cb1400bAF7F6761BDc498dA222

YOUR_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)

echo "=== НАСТРОЙКА КОНТРАКТОВ ==="
echo "Factory: $NEW_FACTORY"
echo "Your address: $YOUR_ADDRESS"
echo "RPC: $RPC_URL"
echo ""

# 1. Установить dependencies в Factory
echo "1. Устанавливаем dependencies в Factory..."
cast send $NEW_FACTORY \
    "setDependencies(address,address,address,address,address,address,address,address)" \
    $SPV $FROST $CALC_REGISTRY $AGGREGATOR $VALIDATOR $ORACLE_REGISTRY $TOKEN_FACTORY $MULTIPOOL_DAO \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL

# 2. Установить deployer в Factory
echo "2. Устанавливаем deployer в Factory..."
cast send $NEW_FACTORY \
    "setPoolDeployer(address)" $DEPLOYER \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL

# 3. Выдать POOL_MANAGER_ROLE себе
echo "3. Выдаём POOL_MANAGER_ROLE..."
POOL_MANAGER_ROLE=$(cast call $NEW_FACTORY "POOL_MANAGER_ROLE()(bytes32)" --rpc-url $RPC_URL)
cast send $NEW_FACTORY \
    "grantRole(bytes32,address)" $POOL_MANAGER_ROLE $YOUR_ADDRESS \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL

# 4. Выдать POOL_FACTORY_ROLE в TokenFactory
echo "4. Выдаём POOL_FACTORY_ROLE новому Factory в TokenFactory..."
POOL_FACTORY_ROLE=$(cast keccak "POOL_FACTORY_ROLE()")
cast send $TOKEN_FACTORY \
    "grantRole(bytes32,address)" $POOL_FACTORY_ROLE $NEW_FACTORY \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL

echo ""
echo "=== ПРОВЕРКА ==="
echo "SPV в Factory: $(cast call $NEW_FACTORY 'spvContract()(address)' --rpc-url $RPC_URL)"
echo "FROST в Factory: $(cast call $NEW_FACTORY 'frostCoordinator()(address)' --rpc-url $RPC_URL)"
echo "Deployer в Factory: $(cast call $NEW_FACTORY 'poolDeployer()(address)' --rpc-url $RPC_URL)"
echo "POOL_MANAGER_ROLE: $(cast call $NEW_FACTORY 'hasRole(bytes32,address)(bool)' $POOL_MANAGER_ROLE $YOUR_ADDRESS --rpc-url $RPC_URL)"
echo ""
echo "✅ ГОТОВО! Можете создавать пулы"
