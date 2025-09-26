# MP Token Flows Analysis

## Обзор трёх основных потоков работы с MP токенами

### Поток 1: Bitcoin → MP Tokens (Распределение наград)

**Шаги:**
1. **Bitcoin транзакция приходит в пул** (coinbase награда)
2. **SPV верификация через `SPVContract`:**
   - `addBlockHeader()` - добавление блок хедера
   - `checkTxInclusion()` - проверка включения транзакции в блок
   - `isMature()` - проверка зрелости (100+ подтверждений)
3. **Регистрация UTXO в `MiningPoolCore`:**
   - `registerRewardStrict()` - регистрация coinbase UTXO
4. **Распределение через `MiningPoolRewards`:**
   - `distributeRewardsStrict()` - основная функция распределения
   - Получение данных воркеров из `StratumDataAggregator`
   - Валидация через `StratumDataValidator`
   - Расчёт долей через `Calculator` (FPPS/PPLNS/etc)
5. **Минтинг MP токенов:**
   ```solidity
   IPoolMpToken(poolToken).mint(evmPayout, amount);
   ```

**Реализовано:** ✅
- SPVContract.sol: строки 62-67 (maturity check)
- MiningPoolCore.sol: строки 364-383 (distributeRewardsStrict)
- MiningPoolRewards.sol: строки 119-263 (полный флоу распределения)

---

### Поток 2: MP Tokens → Bitcoin (Вывод средств)

**Шаги:**
1. **Пользователь инициирует вывод в `MiningPoolRedemption`:**
   ```solidity
   function redeem(
       uint64 amountSat,
       bytes calldata btcScript,
       ...
   )
   ```
2. **Сжигание MP токенов:**
   ```solidity
   IPoolMpToken(poolToken).burn(msg.sender, amountSat); // строка 243
   ```
3. **Создание FROST сессии для подписи:**
   - Создаётся структура `Redemption` с данными вывода
   - Инициируется FROST сессия для мультиподписи
4. **Создание Bitcoin транзакции:**
   - Использует UTXO из пула
   - Создаёт выход на адрес пользователя
   - Требует подпись через FROST

**Реализовано:** ✅
- MiningPoolRedemption.sol: строки 208-265 (redeem function)
- Сжигание MP токенов реализовано
- FROST интеграция присутствует

---

### Поток 3: MP Tokens → S-Tokens (Стейкинг в MultiPoolDAO)

**Шаги:**
1. **Пользователь предоставляет SPV proof транзакции:**
   ```solidity
   function mintSTokenWithProof(
       bytes32 poolId,
       bytes calldata blockHeaderRaw,
       bytes calldata txRaw,
       ...
   )
   ```
2. **SPV верификация:**
   - Проверка включения транзакции в блок
   - Проверка зрелости блока
   - Проверка что payoutScript совпадает с пулом
3. **Регистрация или использование UTXO:**
   ```solidity
   // Находим существующий UTXO или регистрируем новый
   UTXO[] storage arr = poolUTXOs[P.networkId][poolId];
   ```
4. **Резервирование backing и минтинг S-токенов:**
   ```solidity
   b.reserved += amount;
   ISTokenMinimal(nc.sToken).mint(recipient, amount);
   ```
5. **Обратный процесс - burnAndRedeem:**
   ```solidity
   ISTokenMinimal(nc.sToken).burnFrom(msg.sender, amount);
   ```

**Реализовано:** ✅
- MultiPoolDAO.sol: строки 223-293 (mintSTokenWithProof)
- MultiPoolDAO.sol: строки 296-320 (burnAndRedeem)

---

## Текущий статус реализации

### ✅ Полностью реализовано:
1. **SPV верификация** - работает через SPVContract
2. **Maturity проверка** - 100 блоков подтверждения
3. **Распределение MP токенов** - через калькуляторы
4. **Минтинг MP токенов** - IPoolMpToken.mint()
5. **Сжигание MP для вывода** - IPoolMpToken.burn()
6. **FROST интеграция** - для мультиподписей
7. **S-токены минтинг** - через SPV proof

### ⚠️ Требует внимания:
1. **Автоматизация процессов** - сейчас многие вызовы требуют ручного запуска
2. **Оракулы для данных майнинга** - зависимость от StratumDataAggregator
3. **Комиссии за транзакции** - логика расчёта fee в Bitcoin транзакциях

---

## Ключевые контракты и функции

### Для потока 1 (Bitcoin → MP):
- `SPVContract.isMature()`
- `MiningPoolCore.registerRewardStrict()`
- `MiningPoolRewards.distributeRewardsStrict()`
- `IPoolMpToken.mint()`

### Для потока 2 (MP → Bitcoin):
- `MiningPoolRedemption.redeem()`
- `IPoolMpToken.burn()`
- `FROSTCoordinator` (для подписей)

### Для потока 3 (MP → S-Tokens):
- `MultiPoolDAO.mintSTokenWithProof()`
- `MultiPoolDAO.burnAndRedeem()`
- `ISTokenMinimal.mint()/burn()`

---

## Выводы

Все три потока реализованы в контрактах:

1. ✅ **Bitcoin → MP**: Полный цикл от получения coinbase до распределения токенов
2. ✅ **MP → Bitcoin**: Сжигание токенов и создание вывода через FROST
3. ✅ **MP → S-Tokens**: Обмен через SPV proof с резервированием backing

Система готова для:
- Приёма Bitcoin транзакций через SPV
- Распределения наград в виде MP токенов
- Вывода Bitcoin через сжигание MP
- Обмена MP на S-токены в MultiPoolDAO