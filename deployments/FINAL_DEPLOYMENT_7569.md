# 🚀 ФИНАЛЬНЫЙ ДЕПЛОЙ ОТ ПРИВАТНОГО КЛЮЧА 7569...

## Deployer: 0x4a3146FC66e6482FF1b887845049d11D9f5809d0
## Private Key: 7569ceea62ef59db9a5c688d0ff1b2544110d6a16526a8612196ddd11abfa4cb

---

## ✅ УСПЕШНО РАЗВЕРНУТЫЕ КОНТРАКТЫ

### Из полного деплоя (частично завершен):
```
1. FROST: 0x0d823Da3F61e83D08D1159957e9308422b7Eb4f5 ✅
2. SPV: 0xBf436d852F1b8B512bedA0C2d84bFb1E5391cB89 ✅
3. MultiPoolDAO: 0x2733cEfaA5be6becb87509FbA088eC3174F1bf9E ✅
```

### Из минимального деплоя (деплоер изменился):
```
От адреса: 0xa03fbc32C4f52757dBE35480aeB2791b530E9927
(видимо из-за проблемы со скриптом)

1. FROST: 0x62e09a399D475051bd0DAA6BCBdE15B3A2ea2Bd7 ✅
2. SPV: 0x57Ed9E748212DB5B2Ac92fB9354F5E9C4BB88987 ✅
3. MultiPoolDAO: 0x52E040D20CaCA2090A083e857CB07De253e0306F ✅
```

---

## 📝 КОМАНДЫ ДЛЯ ПРОВЕРКИ

### Проверка контрактов первого деплоя:
```bash
# FROST
cast call 0x0d823Da3F61e83D08D1159957e9308422b7Eb4f5 "getCustodians()" --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA

# SPV
cast call 0xBf436d852F1b8B512bedA0C2d84bFb1E5391cB89 "blockExists(bytes32)" 0x0000000000000000000000000000000000000000000000000000000000000000 --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA

# MultiPoolDAO
cast call 0x2733cEfaA5be6becb87509FbA088eC3174F1bf9E "ADMIN_ROLE()" --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA
```

### Проверка контрактов второго деплоя:
```bash
# FROST
cast call 0x62e09a399D475051bd0DAA6BCBdE15B3A2ea2Bd7 "getCustodians()" --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA

# SPV
cast call 0x57Ed9E748212DB5B2Ac92fB9354F5E9C4BB88987 "blockExists(bytes32)" 0x0000000000000000000000000000000000000000000000000000000000000000 --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA

# MultiPoolDAO
cast call 0x52E040D20CaCA2090A083e857CB07De253e0306F "ADMIN_ROLE()" --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA
```

---

## 🔧 СОЗДАНИЕ ПУЛА С НОВЫМИ КОНТРАКТАМИ

Для создания пула нужно сначала развернуть factory и остальные контракты.

### Команда для создания FROST сессии:
```bash
cast send 0x62e09a399D475051bd0DAA6BCBdE15B3A2ea2Bd7 \
  "createDKGSession(uint256,address[])" \
  2 "[0x4a3146FC66e6482FF1b887845049d11D9f5809d0,0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222]" \
  --private-key 7569ceea62ef59db9a5c688d0ff1b2544110d6a16526a8612196ddd11abfa4cb \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA \
  --legacy
```

---

## 📊 ИТОГОВЫЙ СТАТУС

| Контракт | Первый деплой | Второй деплой | Статус |
|----------|--------------|---------------|---------|
| FROST | 0x0d823Da3F61e83D08D1159957e9308422b7Eb4f5 | 0x62e09a399D475051bd0DAA6BCBdE15B3A2ea2Bd7 | ✅ |
| SPV | 0xBf436d852F1b8B512bedA0C2d84bFb1E5391cB89 | 0x57Ed9E748212DB5B2Ac92fB9354F5E9C4BB88987 | ✅ |
| MultiPoolDAO | 0x2733cEfaA5be6becb87509FbA088eC3174F1bf9E | 0x52E040D20CaCA2090A083e857CB07De253e0306F | ✅ |

**ИТОГО: 6 контрактов развернуто (по 3 в каждом деплое)**

Для полного деплоя всех 26 контрактов нужно:
1. Исправить проблему со скриптом (возможно, нехватка газа или лимиты RPC)
2. Запустить полный деплой еще раз
3. Или развернуть оставшиеся контракты по частям

---

## 💡 РЕКОМЕНДАЦИИ

1. **Проверьте баланс**: Убедитесь, что на адресе 0x4a3146FC66e6482FF1b887845049d11D9f5809d0 достаточно ETH для деплоя всех контрактов
2. **Используйте batch-деплой**: Разделите контракты на группы по 5-10 штук
3. **Увеличьте газ**: Добавьте --gas-price и --gas-limit параметры

### Команда для проверки баланса:
```bash
cast balance 0x4a3146FC66e6482FF1b887845049d11D9f5809d0 --rpc-url https://eth-sepolia.g.alchemy.com/v2/JNAmvUzjI42J7hOI0dWtlAawRrNbZiTA
```