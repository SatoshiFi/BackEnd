// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SafeMath
 * @dev Безопасные математические операции для SatoshiFi с защитой от переполнения
 */
library SafeMath {

    // Ошибки для более детальной диагностики
    error SafeMathOverflow(string operation, uint256 a, uint256 b);
    error SafeMathUnderflow(string operation, uint256 a, uint256 b);
    error SafeMathDivisionByZero(string operation, uint256 a);
    error SafeMathModuloByZero(string operation, uint256 a);

    /**
     * @dev Безопасное сложение
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        if (c < a) {
            revert SafeMathOverflow("add", a, b);
        }
        return c;
    }

    /**
     * @dev Безопасное вычитание
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) {
            revert SafeMathUnderflow("sub", a, b);
        }
        return a - b;
    }

    /**
     * @dev Безопасное умножение
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        if (c / a != b) {
            revert SafeMathOverflow("mul", a, b);
        }

        return c;
    }

    /**
     * @dev Безопасное деление
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert SafeMathDivisionByZero("div", a);
        }
        return a / b;
    }

    /**
     * @dev Безопасный остаток от деления
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert SafeMathModuloByZero("mod", a);
        }
        return a % b;
    }

    /**
     * @dev Безопасное возведение в степень
     */
    function pow(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            return 1;
        }
        if (a == 0) {
            return 0;
        }

        uint256 result = 1;
        uint256 base = a;

        while (b > 0) {
            if (b % 2 == 1) {
                result = mul(result, base);
            }
            base = mul(base, base);
            b = b / 2;
        }

        return result;
    }

    /**
     * @dev Расчет процента от числа
     * @param amount Исходная сумма
     * @param percent Процент (в базисных пунктах, где 10000 = 100%)
     */
    function percentage(uint256 amount, uint256 percent) internal pure returns (uint256) {
        return mul(amount, percent) / 10000;
    }

    /**
     * @dev Расчет процента с округлением вверх
     */
    function percentageCeil(uint256 amount, uint256 percent) internal pure returns (uint256) {
        uint256 numerator = mul(amount, percent);
        return (numerator + 9999) / 10000;
    }

    /**
     * @dev Безопасное деление с округлением вверх
     */
    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert SafeMathDivisionByZero("divCeil", a);
        }
        return (a + b - 1) / b;
    }

    /**
     * @dev Минимум из двух чисел
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Максимум из двух чисел
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Среднее арифметическое
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b) / 2;
    }

    /**
     * @dev Абсолютная разность
     */
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /**
     * @dev Квадратный корень (метод Ньютона)
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 x = a;
        uint256 y = (a + 1) / 2;

        while (y < x) {
            x = y;
            y = (a / x + x) / 2;
        }

        return x;
    }

    /**
     * @dev Проверка на переполнение при сложении
     */
    function canAdd(uint256 a, uint256 b) internal pure returns (bool) {
        return a <= type(uint256).max - b;
    }

    /**
     * @dev Проверка на подтекание при вычитании
     */
    function canSub(uint256 a, uint256 b) internal pure returns (bool) {
        return a >= b;
    }

    /**
     * @dev Проверка на переполнение при умножении
     */
    function canMul(uint256 a, uint256 b) internal pure returns (bool) {
        if (a == 0) return true;
        return type(uint256).max / a >= b;
    }

    /**
     * @dev Безопасное сложение с проверкой лимита
     */
    function addWithLimit(uint256 a, uint256 b, uint256 limit) internal pure returns (uint256) {
        uint256 result = add(a, b);
        return min(result, limit);
    }

    /**
     * @dev Пропорциональное распределение
     */
    function proportionalDistribution(
        uint256 totalAmount,
        uint256 part,
        uint256 total
    ) internal pure returns (uint256) {
        if (total == 0) {
            revert SafeMathDivisionByZero("proportionalDistribution", totalAmount);
        }
        return mul(totalAmount, part) / total;
    }

    /**
     * @dev Взвешенное среднее
     */
    function weightedAverage(
        uint256 value1,
        uint256 weight1,
        uint256 value2,
        uint256 weight2
    ) internal pure returns (uint256) {
        uint256 totalWeight = add(weight1, weight2);
        if (totalWeight == 0) {
            return 0;
        }

        uint256 weightedSum = add(
            mul(value1, weight1),
                                  mul(value2, weight2)
        );

        return div(weightedSum, totalWeight);
    }

    /**
     * @dev Линейная интерполяция
     */
    function lerp(
        uint256 a,
        uint256 b,
        uint256 t,
        uint256 tMax
    ) internal pure returns (uint256) {
        if (tMax == 0) {
            return a;
        }

        uint256 interpolated = add(
            mul(a, sub(tMax, t)),
                                   mul(b, t)
        );

        return div(interpolated, tMax);
    }

    /**
     * @dev Compound interest calculation
     * @param principal Основная сумма
     * @param rate Годовая ставка в базисных пунктах
     * @param periods Количество периодов
     */
    function compoundInterest(
        uint256 principal,
        uint256 rate,
        uint256 periods
    ) internal pure returns (uint256) {
        if (periods == 0) {
            return principal;
        }

        uint256 ratePerPeriod = add(10000, rate); // 10000 + rate basis points
        uint256 compound = pow(ratePerPeriod, periods);

        return mul(principal, compound) / pow(10000, periods);
    }

    /**
     * @dev Расчет сложного процента с точностью до дня
     */
    function dailyCompoundInterest(
        uint256 principal,
        uint256 annualRate,
        uint256 dayCount
    ) internal pure returns (uint256) {
        uint256 dailyRate = annualRate / 365; // Дневная ставка
        return compoundInterest(principal, dailyRate, dayCount);
    }

    /**
     * @dev Проверка числа на четность
     */
    function isEven(uint256 n) internal pure returns (bool) {
        return n % 2 == 0;
    }

    /**
     * @dev Проверка числа на нечетность
     */
    function isOdd(uint256 n) internal pure returns (bool) {
        return n % 2 == 1;
    }

    /**
     * @dev Ограничение значения в диапазоне
     */
    function clamp(uint256 value, uint256 minValue, uint256 maxValue) internal pure returns (uint256) {
        if (minValue > maxValue) {
            revert SafeMathOverflow("clamp", minValue, maxValue);
        }
        return min(max(value, minValue), maxValue);
    }

    /**
     * @dev Проверка попадания в диапазон
     */
    function inRange(uint256 value, uint256 minValue, uint256 maxValue) internal pure returns (bool) {
        return value >= minValue && value <= maxValue;
    }

    /**
     * @dev Безопасное приведение к uint128
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        if (value > type(uint128).max) {
            revert SafeMathOverflow("toUint128", value, type(uint128).max);
        }
        return uint128(value);
    }

    /**
     * @dev Безопасное приведение к uint64
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        if (value > type(uint64).max) {
            revert SafeMathOverflow("toUint64", value, type(uint64).max);
        }
        return uint64(value);
    }

    /**
     * @dev Безопасное приведение к uint32
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        if (value > type(uint32).max) {
            revert SafeMathOverflow("toUint32", value, type(uint32).max);
        }
        return uint32(value);
    }

    /**
     * @dev Расчет скидки
     */
    function applyDiscount(uint256 amount, uint256 discountPercent) internal pure returns (uint256) {
        if (discountPercent >= 10000) {
            return 0;
        }
        uint256 discount = percentage(amount, discountPercent);
        return sub(amount, discount);
    }

    /**
     * @dev Расчет наценки
     */
    function applyMarkup(uint256 amount, uint256 markupPercent) internal pure returns (uint256) {
        uint256 markup = percentage(amount, markupPercent);
        return add(amount, markup);
    }

    /**
     * @dev Безопасный факториал (ограничен для предотвращения переполнения)
     */
    function factorial(uint256 n) internal pure returns (uint256) {
        if (n > 20) {
            revert SafeMathOverflow("factorial", n, 20);
        }

        uint256 result = 1;
        for (uint256 i = 2; i <= n; i++) {
            result = mul(result, i);
        }

        return result;
    }

    /**
     * @dev Наибольший общий делитель (алгоритм Евклида)
     */
    function gcd(uint256 a, uint256 b) internal pure returns (uint256) {
        while (b != 0) {
            uint256 temp = b;
            b = a % b;
            a = temp;
        }
        return a;
    }

    /**
     * @dev Наименьшее общее кратное
     */
    function lcm(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        return div(mul(a, b), gcd(a, b));
    }
}
