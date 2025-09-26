# 🔍 ПОЛНАЯ ПРОВЕРКА ВСЕХ 26 КОНТРАКТОВ НА SEPOLIA

## Установка переменных
```bash
export RPC_URL="https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA"
export DEPLOYER="0xa03fbc32C4f52757dBE35480aeB2791b530E9927"
```

---

## 1. CORE INFRASTRUCTURE (3 контракта)

### 1.1 FROST Coordinator - 0x403C36f5e05Fb339bfC4f28f44B6c31f9DC8fB95
```bash
# Получить кастодианов
cast call 0x403C36f5e05Fb339bfC4f28f44B6c31f9DC8fB95 "getCustodians()" --rpc-url $RPC_URL

# Создать DKG сессию (требует транзакцию)
cast send 0x403C36f5e05Fb339bfC4f28f44B6c31f9DC8fB95 "createDKGSession(uint256,address[])" 2 "[0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222]" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### 1.2 SPV Contract - 0xa756B82e2e2031f3516BA09Dd3a7FaE3B817Bb7A
```bash
# Проверить существование блока
cast call 0xa756B82e2e2031f3516BA09Dd3a7FaE3B817Bb7A "blockExists(bytes32)" 0x0000000000000000000000000000000000000000000000000000000000000000 --rpc-url $RPC_URL

# Проверить блок в основной цепи
cast call 0xa756B82e2e2031f3516BA09Dd3a7FaE3B817Bb7A "isInMainchain(bytes32)" 0x0000000000000000000000000000000000000000000000000000000000000000 --rpc-url $RPC_URL
```

### 1.3 MultiPoolDAO - 0x71271B71B142BBF4De69F792b4f41B27681Bd6a5
```bash
# Получить ADMIN_ROLE
cast call 0x71271B71B142BBF4De69F792b4f41B27681Bd6a5 "ADMIN_ROLE()" --rpc-url $RPC_URL

# Получить POOL_ROLE
cast call 0x71271B71B142BBF4De69F792b4f41B27681Bd6a5 "POOL_ROLE()" --rpc-url $RPC_URL

# Проверить информацию о сети
cast call 0x71271B71B142BBF4De69F792b4f41B27681Bd6a5 "networks(uint8)" 1 --rpc-url $RPC_URL
```

---

## 2. FACTORY SYSTEM (3 контракта)

### 2.1 Factory Core - 0x6BfDF4BcA6Af2fFA2cC006C4c6005c7185928Ab2
```bash
# Получить количество пулов
cast call 0x6BfDF4BcA6Af2fFA2cC006C4c6005c7185928Ab2 "getPoolCount()" --rpc-url $RPC_URL

# Проверить валидность пула
cast call 0x6BfDF4BcA6Af2fFA2cC006C4c6005c7185928Ab2 "isValidPool(address)" 0xA2a1488C4bA6165b6D91b0789264845746241a96 --rpc-url $RPC_URL

# Получить пул по индексу
cast call 0x6BfDF4BcA6Af2fFA2cC006C4c6005c7185928Ab2 "getPoolAt(uint256)" 0 --rpc-url $RPC_URL
```

### 2.2 Pool Deployer - 0x39E28F9f6B67e8edab0F8249b56F787aCE03f305
```bash
# Проверить адрес factory
cast call 0x39E28F9f6B67e8edab0F8249b56F787aCE03f305 "factory()" --rpc-url $RPC_URL

# Получить байткод (подтверждение деплоя)
cast code 0x39E28F9f6B67e8edab0F8249b56F787aCE03f305 --rpc-url $RPC_URL | wc -c
```

### 2.3 Token Factory - 0x966f955AFFDDDF7e4B7e884d74574a2Db85986C6
```bash
# Получить POOL_FACTORY_ROLE
cast call 0x966f955AFFDDDF7e4B7e884d74574a2Db85986C6 "POOL_FACTORY_ROLE()" --rpc-url $RPC_URL

# Проверить байткод
cast code 0x966f955AFFDDDF7e4B7e884d74574a2Db85986C6 --rpc-url $RPC_URL | wc -c
```

---

## 3. CALCULATOR SYSTEM (5 контрактов)

### 3.1 Calculator Registry - 0x4f38B180b42Ec0C21dB931bA8aEB60fc7abcd08C
```bash
# Получить количество калькуляторов
cast call 0x4f38B180b42Ec0C21dB931bA8aEB60fc7abcd08C "getCalculatorCount()" --rpc-url $RPC_URL

# Получить калькулятор по ID
cast call 0x4f38B180b42Ec0C21dB931bA8aEB60fc7abcd08C "getCalculator(uint256)" 0 --rpc-url $RPC_URL
```

### 3.2 FPPS Calculator - 0x63D56662121125591BC3e3327604fB4531aB6E3a
```bash
# Получить название схемы
cast call 0x63D56662121125591BC3e3327604fB4531aB6E3a "schemeName()" --rpc-url $RPC_URL

# Проверить байткод
cast code 0x63D56662121125591BC3e3327604fB4531aB6E3a --rpc-url $RPC_URL | wc -c
```

### 3.3 PPLNS Calculator - 0x66b045b9Eda4D2c8e061CDe835DadcaB92bE9f45
```bash
# Получить название схемы
cast call 0x66b045b9Eda4D2c8e061CDe835DadcaB92bE9f45 "schemeName()" --rpc-url $RPC_URL

# Проверить байткод
cast code 0x66b045b9Eda4D2c8e061CDe835DadcaB92bE9f45 --rpc-url $RPC_URL | wc -c
```

### 3.4 PPS Calculator - 0xD8733811FC87b1B37F66A1851cb70471C844D62D
```bash
# Получить название схемы
cast call 0xD8733811FC87b1B37F66A1851cb70471C844D62D "schemeName()" --rpc-url $RPC_URL

# Проверить байткод
cast code 0xD8733811FC87b1B37F66A1851cb70471C844D62D --rpc-url $RPC_URL | wc -c
```

### 3.5 Score Calculator - 0xA103f070ed9bC0c16D0Af83dC4562ef6a8d3A128
```bash
# Проверить байткод
cast code 0xA103f070ed9bC0c16D0Af83dC4562ef6a8d3A128 --rpc-url $RPC_URL | wc -c
```

---

## 4. ORACLE INFRASTRUCTURE (3 контракта)

### 4.1 Oracle Registry - 0x0daB3289fe51dE1aa76f89a5808EDCc30B2F6615
```bash
# Получить количество оракулов
cast call 0x0daB3289fe51dE1aa76f89a5808EDCc30B2F6615 "getOracleCount()" --rpc-url $RPC_URL

# Проверить байткод
cast code 0x0daB3289fe51dE1aa76f89a5808EDCc30B2F6615 --rpc-url $RPC_URL | wc -c
```

### 4.2 Data Aggregator - 0xf6A1907c71C69C470fd0f6C14C1676b8398786c3
```bash
# Получить адрес registry
cast call 0xf6A1907c71C69C470fd0f6C14C1676b8398786c3 "oracleRegistry()" --rpc-url $RPC_URL

# Проверить байткод
cast code 0xf6A1907c71C69C470fd0f6C14C1676b8398786c3 --rpc-url $RPC_URL | wc -c
```

### 4.3 Data Validator - 0x722c75198AB995D4785baAd76CFEC1bE7D8e1d0C
```bash
# Получить адрес registry
cast call 0x722c75198AB995D4785baAd76CFEC1bE7D8e1d0C "oracleRegistry()" --rpc-url $RPC_URL

# Проверить байткод
cast code 0x722c75198AB995D4785baAd76CFEC1bE7D8e1d0C --rpc-url $RPC_URL | wc -c
```

---

## 5. SYNTHETIC TOKENS (3 контракта)

### 5.1 sBTC - 0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8
```bash
# Получить имя токена
cast call 0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8 "name()" --rpc-url $RPC_URL

# Получить символ
cast call 0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8 "symbol()" --rpc-url $RPC_URL

# Получить total supply
cast call 0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8 "totalSupply()" --rpc-url $RPC_URL

# Получить decimals
cast call 0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8 "decimals()" --rpc-url $RPC_URL
```

### 5.2 sDOGE - 0x8c244DdC5481e504Dde727e45414ea335877CB4F
```bash
# Получить имя токена
cast call 0x8c244DdC5481e504Dde727e45414ea335877CB4F "name()" --rpc-url $RPC_URL

# Получить символ
cast call 0x8c244DdC5481e504Dde727e45414ea335877CB4F "symbol()" --rpc-url $RPC_URL

# Получить total supply
cast call 0x8c244DdC5481e504Dde727e45414ea335877CB4F "totalSupply()" --rpc-url $RPC_URL
```

### 5.3 sLTC - 0xB967ba4E97B882b5B089419e6a2DDe891f8e5d72
```bash
# Получить имя токена
cast call 0xB967ba4E97B882b5B089419e6a2DDe891f8e5d72 "name()" --rpc-url $RPC_URL

# Получить символ
cast call 0xB967ba4E97B882b5B089419e6a2DDe891f8e5d72 "symbol()" --rpc-url $RPC_URL

# Получить total supply
cast call 0xB967ba4E97B882b5B089419e6a2DDe891f8e5d72 "totalSupply()" --rpc-url $RPC_URL
```

---

## 6. PROXY IMPLEMENTATIONS (4 контракта)

### 6.1 Core Implementation - 0xBaaC0AEaCbBC4f3E56f77736806890766b454202
```bash
# Проверить байткод
cast code 0xBaaC0AEaCbBC4f3E56f77736806890766b454202 --rpc-url $RPC_URL | wc -c

# Получить размер контракта
cast codesize 0xBaaC0AEaCbBC4f3E56f77736806890766b454202 --rpc-url $RPC_URL
```

### 6.2 Rewards Implementation - 0x3266d2651C46B34Af7dad9504474ED2Df447874a
```bash
# Проверить байткод
cast code 0x3266d2651C46B34Af7dad9504474ED2Df447874a --rpc-url $RPC_URL | wc -c

# Получить размер контракта
cast codesize 0x3266d2651C46B34Af7dad9504474ED2Df447874a --rpc-url $RPC_URL
```

### 6.3 Redemption Implementation - 0x475318faF78AA678370265d28B550de21C34Ec5D
```bash
# Проверить байткод
cast code 0x475318faF78AA678370265d28B550de21C34Ec5D --rpc-url $RPC_URL | wc -c

# Получить размер контракта
cast codesize 0x475318faF78AA678370265d28B550de21C34Ec5D --rpc-url $RPC_URL
```

### 6.4 Extensions Implementation - 0x8a4ebd2B36867cb576FF40536bDC5EA38310b36a
```bash
# Проверить байткод
cast code 0x8a4ebd2B36867cb576FF40536bDC5EA38310b36a --rpc-url $RPC_URL | wc -c

# Получить размер контракта
cast codesize 0x8a4ebd2B36867cb576FF40536bDC5EA38310b36a --rpc-url $RPC_URL
```

---

## 7. HANDLERS (2 контракта)

### 7.1 Reward Handler - 0x02DF59872ecEC5a56981F4d35D76a4B70BB23645
```bash
# Проверить байткод
cast code 0x02DF59872ecEC5a56981F4d35D76a4B70BB23645 --rpc-url $RPC_URL | wc -c

# Получить размер контракта
cast codesize 0x02DF59872ecEC5a56981F4d35D76a4B70BB23645 --rpc-url $RPC_URL
```

### 7.2 Redemption Handler - 0x5ed951ce8be081aF5DaB412c83a11cf4220D4a9b
```bash
# Проверить байткод
cast code 0x5ed951ce8be081aF5DaB412c83a11cf4220D4a9b --rpc-url $RPC_URL | wc -c

# Получить размер контракта
cast codesize 0x5ed951ce8be081aF5DaB412c83a11cf4220D4a9b --rpc-url $RPC_URL
```

---

## 8. ДОПОЛНИТЕЛЬНЫЕ КОНТРАКТЫ (из первого деплоя)

### 8.1 FROST (первый деплой) - 0x203a40F0a46A5f3B407B8557d7F2B9Dc8aDaa6b0
```bash
# Проверить байткод
cast code 0x203a40F0a46A5f3B407B8557d7F2B9Dc8aDaa6b0 --rpc-url $RPC_URL | wc -c
```

### 8.2 SPV (первый деплой) - 0xBeC4DE24267045823931f7b605b2D73bDF6912F1
```bash
# Проверить байткод
cast code 0xBeC4DE24267045823931f7b605b2D73bDF6912F1 --rpc-url $RPC_URL | wc -c
```

### 8.3 MultiPoolDAO (первый деплой) - 0xd26d1Ba7dFb8b0F274622378219fBc1B9357b507
```bash
# Проверить байткод
cast code 0xd26d1Ba7dFb8b0F274622378219fBc1B9357b507 --rpc-url $RPC_URL | wc -c
```

---

## 🔥 BATCH ПРОВЕРКА ВСЕХ КОНТРАКТОВ

### Скрипт для проверки всех 26 контрактов одной командой:
```bash
#!/bin/bash

RPC_URL="https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA"

echo "Проверка всех 26 контрактов на Sepolia..."
echo "=========================================="

# Массив всех контрактов
declare -A contracts=(
    ["FROST"]="0x403C36f5e05Fb339bfC4f28f44B6c31f9DC8fB95"
    ["SPV"]="0xa756B82e2e2031f3516BA09Dd3a7FaE3B817Bb7A"
    ["MultiPoolDAO"]="0x71271B71B142BBF4De69F792b4f41B27681Bd6a5"
    ["Factory"]="0x6BfDF4BcA6Af2fFA2cC006C4c6005c7185928Ab2"
    ["Deployer"]="0x39E28F9f6B67e8edab0F8249b56F787aCE03f305"
    ["TokenFactory"]="0x966f955AFFDDDF7e4B7e884d74574a2Db85986C6"
    ["CalcRegistry"]="0x4f38B180b42Ec0C21dB931bA8aEB60fc7abcd08C"
    ["FPPS"]="0x63D56662121125591BC3e3327604fB4531aB6E3a"
    ["PPLNS"]="0x66b045b9Eda4D2c8e061CDe835DadcaB92bE9f45"
    ["PPS"]="0xD8733811FC87b1B37F66A1851cb70471C844D62D"
    ["Score"]="0xA103f070ed9bC0c16D0Af83dC4562ef6a8d3A128"
    ["OracleReg"]="0x0daB3289fe51dE1aa76f89a5808EDCc30B2F6615"
    ["Aggregator"]="0xf6A1907c71C69C470fd0f6C14C1676b8398786c3"
    ["Validator"]="0x722c75198AB995D4785baAd76CFEC1bE7D8e1d0C"
    ["sBTC"]="0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8"
    ["sDOGE"]="0x8c244DdC5481e504Dde727e45414ea335877CB4F"
    ["sLTC"]="0xB967ba4E97B882b5B089419e6a2DDe891f8e5d72"
    ["CoreImpl"]="0xBaaC0AEaCbBC4f3E56f77736806890766b454202"
    ["RewardsImpl"]="0x3266d2651C46B34Af7dad9504474ED2Df447874a"
    ["RedemptionImpl"]="0x475318faF78AA678370265d28B550de21C34Ec5D"
    ["ExtensionsImpl"]="0x8a4ebd2B36867cb576FF40536bDC5EA38310b36a"
    ["RewardHandler"]="0x02DF59872ecEC5a56981F4d35D76a4B70BB23645"
    ["RedemptionHandler"]="0x5ed951ce8be081aF5DaB412c83a11cf4220D4a9b"
    ["FROST_old"]="0x203a40F0a46A5f3B407B8557d7F2B9Dc8aDaa6b0"
    ["SPV_old"]="0xBeC4DE24267045823931f7b605b2D73bDF6912F1"
    ["MultiPoolDAO_old"]="0xd26d1Ba7dFb8b0F274622378219fBc1B9357b507"
)

# Проверяем каждый контракт
for name in "${!contracts[@]}"; do
    address="${contracts[$name]}"
    size=$(cast codesize $address --rpc-url $RPC_URL 2>/dev/null)
    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
        echo "✅ $name ($address): $size bytes"
    else
        echo "❌ $name ($address): НЕ НАЙДЕН"
    fi
done

echo "=========================================="
echo "Проверка завершена!"
```

---

## 📝 ПРИМЕРЫ ТРАНЗАКЦИЙ

### Создать пул через Factory
```bash
cast send 0x6BfDF4BcA6Af2fFA2cC006C4c6005c7185928Ab2 \
  "createPool((string,string,uint256,uint256,string,string,bool,bytes,uint256))" \
  "(\"BTC\",\"TEST-002\",0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef,0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321,\"Test Token\",\"TT\",false,0x76a91489abcdefabbaabbaabbaabbaabbaabbaabbaabba88ac,0)" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

### Минт synthetic токенов (требует роль MINTER)
```bash
# Для sBTC
cast send 0x0A4a6688475200046c8aDFd3931F23fD67ACc3c8 \
  "mint(address,uint256)" \
  $YOUR_ADDRESS 1000000000000000000 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

---

## ✅ ИТОГО: 26 КОНТРАКТОВ

Все команды выше позволяют проверить каждый из 26 развернутых контрактов на Sepolia!