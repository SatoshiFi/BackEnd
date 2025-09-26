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

success_count=0
fail_count=0

# Проверяем каждый контракт
for name in "${!contracts[@]}"; do
    address="${contracts[$name]}"
    size=$(cast codesize $address --rpc-url $RPC_URL 2>/dev/null)
    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
        echo "[OK] $name ($address): $size bytes"
        ((success_count++))
    else
        echo "[FAIL] $name ($address): НЕ НАЙДЕН"
        ((fail_count++))
    fi
done

echo "=========================================="
echo "Результат: $success_count успешно, $fail_count не найдено"
echo "Всего проверено: $((success_count + fail_count)) контрактов"