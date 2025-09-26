// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DistributionMath
 * @dev Библиотека математических функций для расчета распределения наград
 */
library DistributionMath {

    // Константы
    uint256 constant PRECISION = 1e18;
    uint256 constant BASIS_POINTS = 10000;

    error MathOverflow();
    error DivisionByZero();
    error InvalidInput();

    /**
     * @dev Безопасное умножение с проверкой переполнения
     */
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        if (c / a != b) revert MathOverflow();
        return c;
    }

    /**
     * @dev Безопасное деление с проверкой на ноль
     */
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return a / b;
    }

    /**
     * @dev Умножение с делением для избежания переполнения
     * Эквивалент (a * b) / c с защитой от переполнения
     */
    function mulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (c == 0) revert DivisionByZero();
        if (a == 0) return 0;

        // Проверка на переполнение
        uint256 result = a * b;
        if (result / a != b) {
            // Если произошло переполнение, используем более сложный алгоритм
            return mulDivOverflowSafe(a, b, c);
        }

        return result / c;
    }

    /**
     * @dev Безопасное умножение с делением при переполнении
     */
    function mulDivOverflowSafe(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        // Разбиваем числа на части для избежания переполнения
        uint256 aHigh = a >> 128;
        uint256 aLow = a & ((1 << 128) - 1);
        uint256 bHigh = b >> 128;
        uint256 bLow = b & ((1 << 128) - 1);

        uint256 result = 0;

        // Вычисляем частичные произведения
        if (aHigh > 0 && bHigh > 0) {
            result += (aHigh * bHigh) << 256;
        }

        if (aHigh > 0 && bLow > 0) {
            result += (aHigh * bLow) << 128;
        }

        if (aLow > 0 && bHigh > 0) {
            result += (aLow * bHigh) << 128;
        }

        if (aLow > 0 && bLow > 0) {
            result += aLow * bLow;
        }

        return result / c;
    }

    /**
     * @dev Расчет процента от суммы
     */
    function percentage(uint256 amount, uint256 percent) internal pure returns (uint256) {
        if (percent > BASIS_POINTS) revert InvalidInput();
        return mulDiv(amount, percent, BASIS_POINTS);
    }

    /**
     * @dev Расчет пропорциональной доли
     */
    function proportionalShare(
        uint256 totalAmount,
        uint256 userPart,
        uint256 totalPart
    ) internal pure returns (uint256) {
        if (totalPart == 0) revert DivisionByZero();
        return mulDiv(totalAmount, userPart, totalPart);
    }

    /**
     * @dev Средневзвешенное значение
     */
    function weightedAverage(
        uint256[] memory values,
        uint256[] memory weights
    ) internal pure returns (uint256) {
        if (values.length != weights.length) revert InvalidInput();
        if (values.length == 0) return 0;

        uint256 totalWeightedValue = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < values.length; i++) {
            totalWeightedValue += safeMul(values[i], weights[i]);
            totalWeight += weights[i];
        }

        if (totalWeight == 0) return 0;
        return safeDiv(totalWeightedValue, totalWeight);
    }

    /**
     * @dev Расчет сложных процентов
     */
    function compound(
        uint256 principal,
        uint256 rate,
        uint256 periods
    ) internal pure returns (uint256) {
        if (periods == 0) return principal;
        if (rate == 0) return principal;

        uint256 result = principal;
        uint256 rateWithPrecision = rate + PRECISION;

        for (uint256 i = 0; i < periods; i++) {
            result = mulDiv(result, rateWithPrecision, PRECISION);
        }

        return result;
    }

    /**
     * @dev Расчет корня квадратного (приближенный)
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        // Начальное приближение
        uint256 result = x;
        uint256 k = (x >> 1) + 1;

        // Метод Ньютона
        while (k < result) {
            result = k;
            k = (x / k + k) >> 1;
        }

        return result;
    }

    /**
     * @dev Расчет экспоненциального убывания
     */
    function exponentialDecay(
        uint256 initialValue,
        uint256 decayRate,
        uint256 timeElapsed
    ) internal pure returns (uint256) {
        if (timeElapsed == 0) return initialValue;
        if (decayRate == 0) return initialValue;

        // Приближенная формула: value * (1 - rate)^time
        uint256 decayFactor = PRECISION - decayRate;
        uint256 result = initialValue;

        for (uint256 i = 0; i < timeElapsed; i++) {
            result = mulDiv(result, decayFactor, PRECISION);
        }

        return result;
    }

    /**
     * @dev Нормализация массива значений
     */
    function normalize(uint256[] memory values) internal pure returns (uint256[] memory) {
        if (values.length == 0) return values;

        uint256 sum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i];
        }

        if (sum == 0) return values;

        uint256[] memory normalized = new uint256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            normalized[i] = mulDiv(values[i], PRECISION, sum);
        }

        return normalized;
    }

    /**
     * @dev Расчет минимального значения в массиве
     */
    function min(uint256[] memory values) internal pure returns (uint256) {
        if (values.length == 0) revert InvalidInput();

        uint256 minimum = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] < minimum) {
                minimum = values[i];
            }
        }

        return minimum;
    }

    /**
     * @dev Расчет максимального значения в массиве
     */
    function max(uint256[] memory values) internal pure returns (uint256) {
        if (values.length == 0) revert InvalidInput();

        uint256 maximum = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] > maximum) {
                maximum = values[i];
            }
        }

        return maximum;
    }

    /**
     * @dev Расчет среднего значения
     */
    function average(uint256[] memory values) internal pure returns (uint256) {
        if (values.length == 0) return 0;

        uint256 sum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            sum += values[i];
        }

        return sum / values.length;
    }

    /**
     * @dev Расчет медианы
     */
    function median(uint256[] memory values) internal pure returns (uint256) {
        if (values.length == 0) return 0;
        if (values.length == 1) return values[0];

        // Простая сортировка (неэффективно для больших массивов)
        uint256[] memory sorted = new uint256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            sorted[i] = values[i];
        }

        // Bubble sort
        for (uint256 i = 0; i < sorted.length - 1; i++) {
            for (uint256 j = 0; j < sorted.length - i - 1; j++) {
                if (sorted[j] > sorted[j + 1]) {
                    uint256 temp = sorted[j];
                    sorted[j] = sorted[j + 1];
                    sorted[j + 1] = temp;
                }
            }
        }

        uint256 middle = sorted.length / 2;
        if (sorted.length % 2 == 0) {
            return (sorted[middle - 1] + sorted[middle]) / 2;
        } else {
            return sorted[middle];
        }
    }

    /**
     * @dev Проверка, является ли число степенью двойки
     */
    function isPowerOfTwo(uint256 x) internal pure returns (bool) {
        return x > 0 && (x & (x - 1)) == 0;
    }

    /**
     * @dev Округление вверх до ближайшей степени двойки
     */
    function nextPowerOfTwo(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 1;
        if (isPowerOfTwo(x)) return x;

        uint256 result = 1;
        while (result < x) {
            result <<= 1;
        }

        return result;
    }
}
