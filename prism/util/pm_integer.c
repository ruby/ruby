#include "prism/util/pm_integer.h"

/**
 * Adds two positive pm_integer_t with the given base.
 * Return pm_integer_t with values allocated. Not normalized.
 */
static pm_integer_t
big_add(pm_integer_t left_, pm_integer_t right_, uint64_t base) {
    pm_integer_t left = left_.values ? left_ : (pm_integer_t) { 0, 1, &left_.value, false };
    pm_integer_t right = right_.values ? right_ : (pm_integer_t) { 0, 1, &right_.value, false };
    size_t length = left.length < right.length ? right.length : left.length;
    uint32_t *values = (uint32_t*) malloc(sizeof(uint32_t) * (length + 1));
    uint64_t carry = 0;
    for (size_t i = 0; i < length; i++) {
        uint64_t sum = carry + (i < left.length ? left.values[i] : 0) + (i < right.length ? right.values[i] : 0);
        values[i] = (uint32_t) (sum % base);
        carry = sum / base;
    }
    if (carry > 0) {
        values[length] = (uint32_t) carry;
        length++;
    }
    return (pm_integer_t) { 0, length, values, false };
}

/**
 * Internal use for karatsuba_multiply. Calculates `a - b - c` with the given
 * base. Assume a, b, c, a - b - c all to be poitive.
 * Return pm_integer_t with values allocated. Not normalized.
 */
static pm_integer_t
big_sub2(pm_integer_t a_, pm_integer_t b_, pm_integer_t c_, uint64_t base) {
    pm_integer_t a = a_.values ? a_ : (pm_integer_t) { 0, 1, &a_.value, false };
    pm_integer_t b = b_.values ? b_ : (pm_integer_t) { 0, 1, &b_.value, false };
    pm_integer_t c = c_.values ? c_ : (pm_integer_t) { 0, 1, &c_.value, false };
    size_t length = a.length;
    uint32_t *values = (uint32_t*) malloc(sizeof(uint32_t) * length);
    int64_t carry = 0;
    for (size_t i = 0; i < length; i++) {
        int64_t sub = carry + a.values[i] - (i < b.length ? b.values[i] : 0) - (i < c.length ? c.values[i] : 0);
        if (sub >= 0) {
            values[i] = (uint32_t) sub;
            carry = 0;
        } else {
            sub +=  2 * (int64_t) base;
            values[i] = (uint32_t) ((uint64_t) sub % base);
            carry = sub / (int64_t) base - 2;
        }
    }
    while (length > 1 && values[length - 1] == 0) length--;
    return (pm_integer_t) { 0, length, values, false };
}

/**
 * Multiply two positive integers with the given base using karatsuba algorithm.
 * Return pm_integer_t with values allocated. Not normalized.
 */
static pm_integer_t
karatsuba_multiply(pm_integer_t left_, pm_integer_t right_, uint64_t base) {
    pm_integer_t left = left_.values ? left_ : (pm_integer_t) { 0, 1, &left_.value, false };
    pm_integer_t right = right_.values ? right_ : (pm_integer_t) { 0, 1, &right_.value, false };
    if (left.length > right.length) {
        pm_integer_t temp = left;
        left = right;
        right = temp;
    }
    if (left.length <= 10) {
        size_t length = left.length + right.length;
        uint32_t *values = (uint32_t*) calloc(length, sizeof(uint32_t));
        for (size_t i = 0; i < left.length; i++) {
            uint32_t carry = 0;
            for (size_t j = 0; j < right.length; j++) {
                uint64_t product = (uint64_t) left.values[i] * right.values[j] + values[i + j] + carry;
                values[i + j] = (uint32_t) (product % base);
                carry = (uint32_t) (product / base);
            }
            values[i + right.length] = carry;
        }
        while (length > 1 && values[length - 1] == 0) length--;
        return (pm_integer_t) { 0, length, values, false };
    }
    if (left.length * 2 <= right.length) {
        uint32_t *values = (uint32_t*) calloc(left.length + right.length, sizeof(uint32_t));
        for (size_t start_offset = 0; start_offset < right.length; start_offset += left.length) {
            size_t end_offset = start_offset + left.length;
            if (end_offset > right.length) end_offset = right.length;
            pm_integer_t sliced_right = { 0, end_offset - start_offset, right.values + start_offset, false };
            pm_integer_t v = karatsuba_multiply(left, sliced_right, base);
            uint32_t carry = 0;
            for (size_t i = 0; i < v.length; i++) {
                uint64_t sum = (uint64_t) values[start_offset + i] + v.values[i] + carry;
                values[start_offset + i] = (uint32_t) (sum % base);
                carry = (uint32_t) (sum / base);
            }
            if (carry > 0) values[start_offset + v.length] += carry;
            pm_integer_free(&v);
        }
        return (pm_integer_t) { 0, left.length + right.length, values, false };
    }
    size_t half = left.length / 2;
    pm_integer_t x0 = { 0, half, left.values, false };
    pm_integer_t x1 = { 0, left.length - half, left.values + half, false };
    pm_integer_t y0 = { 0, half, right.values, false };
    pm_integer_t y1 = { 0, right.length - half, right.values + half, false };
    pm_integer_t z0 = karatsuba_multiply(x0, y0, base);
    pm_integer_t z2 = karatsuba_multiply(x1, y1, base);

    // For simplicity to avoid considering negative values,
    // use `z1 = (x0 + x1) * (y0 + y1) - z0 - z2` instead of original karatsuba algorithm.
    pm_integer_t x01 = big_add(x0, x1, base);
    pm_integer_t y01 = big_add(y0, y1, base);
    pm_integer_t xy = karatsuba_multiply(x01, y01, base);
    pm_integer_t z1 = big_sub2(xy, z0, z2, base);

    size_t length = left.length + right.length;
    uint32_t *values = (uint32_t*) calloc(length, sizeof(uint32_t));
    memcpy(values, z0.values, sizeof(uint32_t) * z0.length);
    memcpy(values + 2 * half, z2.values, sizeof(uint32_t) * z2.length);
    uint32_t carry = 0;
    for(size_t i = 0; i < z1.length; i++) {
        uint64_t sum = (uint64_t) carry + values[i + half] + z1.values[i];
        values[i + half] = (uint32_t) (sum % base);
        carry = (uint32_t) (sum / base);
    }
    for(size_t i = half + z1.length; carry > 0; i++) {
        uint64_t sum = (uint64_t) carry + values[i];
        values[i] = (uint32_t) (sum % base);
        carry = (uint32_t) (sum / base);
    }
    while (length > 1 && values[length - 1] == 0) length--;
    pm_integer_free(&z0);
    pm_integer_free(&z1);
    pm_integer_free(&z2);
    pm_integer_free(&x01);
    pm_integer_free(&y01);
    pm_integer_free(&xy);
    return (pm_integer_t) { 0, length, values, false };
}

/**
 * Return the value of a digit in a uint32_t.
 */
static uint32_t
pm_integer_parse_digit(const uint8_t character) {
    switch (character) {
        case '0': return 0;
        case '1': return 1;
        case '2': return 2;
        case '3': return 3;
        case '4': return 4;
        case '5': return 5;
        case '6': return 6;
        case '7': return 7;
        case '8': return 8;
        case '9': return 9;
        case 'a': case 'A': return 10;
        case 'b': case 'B': return 11;
        case 'c': case 'C': return 12;
        case 'd': case 'D': return 13;
        case 'e': case 'E': return 14;
        case 'f': case 'F': return 15;
        default: assert(false && "unreachable"); return 0;
    }
}

/**
 * Create a pm_integer_t from uint64_t with the given base.
 */
static pm_integer_t
pm_integer_from_uint64(uint64_t value, uint64_t base) {
    if (value < base) {
        return (pm_integer_t) { (uint32_t) value, 0, NULL, false };
    }
    uint64_t v = value;
    size_t len = 0;
    while (value > 0) { len++; value /= base; }
    uint32_t *values = (uint32_t*) malloc(sizeof(uint32_t) * len);
    for (size_t i = 0; i < len; i++) {
        values[i] = (uint32_t) (v % base);
        v /= base;
    }
    return (pm_integer_t) { 0, len, values, false };
}

/**
 * Normalize pm_integer_t.
 * Heading zero values will be removed. If the integer fits into uint32_t,
 * values is set to NULL, length is set to 0, and value field will be used.
 */
static void
pm_integer_normalize(pm_integer_t *integer) {
    if (integer->values == NULL) {
        return;
    }
    while (integer->length > 1 && integer->values[integer->length - 1] == 0) {
        integer->length--;
    }
    if (integer->length > 1) {
        return;
    }

    uint32_t value = integer->values[0];
    bool negative = integer->negative && value != 0;
    pm_integer_free(integer);
    *integer = (pm_integer_t) { value, 0, NULL, negative };
}

/**
 * Convert base of the integer.
 * In practice, it converts 10**9 to 1<<32 or 1<<32 to 10**9.
 */
static pm_integer_t
pm_integer_convert_base(pm_integer_t source_, uint64_t base_from, uint64_t base_to) {
    pm_integer_t source = source_.values ? source_ : (pm_integer_t) { 0, 1, &source_.value, source_.negative };
    size_t bigints_length = (source.length + 1) / 2;
    pm_integer_t *bigints = (pm_integer_t*) malloc(sizeof(pm_integer_t) * bigints_length);
    for (size_t i = 0; i < source.length; i += 2) {
        uint64_t v = source.values[i] + base_from * (i + 1 < source.length ? source.values[i + 1] : 0);
        bigints[i / 2] = pm_integer_from_uint64(v, base_to);
    }
    pm_integer_t base = pm_integer_from_uint64(base_from, base_to);
    while (bigints_length > 1) {
        size_t new_length = (bigints_length + 1) / 2;
        pm_integer_t new_base = karatsuba_multiply(base, base, base_to);
        pm_integer_free(&base);
        base = new_base;
        pm_integer_t *new_bigints = (pm_integer_t*) malloc(sizeof(pm_integer_t) * new_length);
        for (size_t i = 0; i < bigints_length; i += 2) {
            if (i + 1 == bigints_length) {
                new_bigints[i / 2] = bigints[i];
            } else {
                pm_integer_t multiplied = karatsuba_multiply(base, bigints[i + 1], base_to);
                new_bigints[i / 2] = big_add(bigints[i], multiplied, base_to);
                pm_integer_free(&bigints[i]);
                pm_integer_free(&bigints[i + 1]);
                pm_integer_free(&multiplied);
            }
        }
        free(bigints);
        bigints = new_bigints;
        bigints_length = new_length;
    }
    pm_integer_free(&base);
    pm_integer_t result = bigints[0];
    result.negative = source.negative;
    free(bigints);
    pm_integer_normalize(&result);
    return result;
}

/**
 * Convert digits to integer with the given power-of-two base.
 */
static void
pm_integer_parse_powof2(pm_integer_t *integer, uint32_t base, const uint8_t *digits, size_t digits_length) {
    size_t bit = 1;
    while (base > (uint32_t) (1 << bit)) bit++;
    size_t length = (digits_length * bit + 31) / 32;
    uint32_t *values = (uint32_t*) calloc(length, sizeof(uint32_t));
    for (size_t i = 0; i < digits_length; i++) {
        size_t bit_position = bit * (digits_length - i - 1);
        uint32_t value = digits[i];
        size_t index = bit_position / 32;
        size_t shift = bit_position % 32;
        values[index] |= value << shift;
        if (32 - shift < bit) values[index + 1] |= value >> (32 - shift);
    }
    while (length > 1 && values[length - 1] == 0) length--;
    *integer = (pm_integer_t) { 0, length, values, false };
    pm_integer_normalize(integer);
}

/**
 * Convert decimal digits to pm_integer_t.
 */
static void
pm_integer_parse_decimal(pm_integer_t *integer, const uint8_t *digits, size_t digits_length) {
    // Construct a bigdecimal with base = 10**9 from the digits
    const size_t batch = 9;
    size_t values_length = (digits_length + batch - 1) / batch;
    pm_integer_t decimal = { 0, values_length, (uint32_t*) calloc(values_length, sizeof(uint32_t)), false };
    uint32_t v = 0;
    for (size_t i = 0; i < digits_length; i++) {
        v = v * 10 + digits[i];
        size_t reverse_index = digits_length - i - 1;
        if (reverse_index % batch == 0) {
            decimal.values[reverse_index / batch] = v;
            v = 0;
        }
    }
    // Convert base from 10**9 to 1<<32.
    *integer = pm_integer_convert_base(decimal, 1000000000, ((uint64_t) 1 << 32));
    pm_integer_free(&decimal);
}

/**
 * Parse a large integer from a string that does not fit into uint32_t.
 */
static void
pm_integer_parse_big(pm_integer_t *integer, uint32_t multiplier, const uint8_t *start, const uint8_t *end) {
    // Allocate an array to store digits.
    uint8_t *digits = malloc(sizeof(uint8_t) * (size_t) (end - start));
    size_t digits_length = 0;
    for (; start < end; start++) {
        if (*start == '_') continue;
        digits[digits_length++] = (uint8_t) pm_integer_parse_digit(*start);
    }
    // Construct pm_integer_t from the digits.
    if (multiplier == 10) {
        pm_integer_parse_decimal(integer, digits, digits_length);
    } else {
        pm_integer_parse_powof2(integer, multiplier, digits, digits_length);
    }
    free(digits);
}

/**
 * Parse an integer from a string. This assumes that the format of the integer
 * has already been validated, as internal validation checks are not performed
 * here.
 */
PRISM_EXPORTED_FUNCTION void
pm_integer_parse(pm_integer_t *integer, pm_integer_base_t base, const uint8_t *start, const uint8_t *end) {
    // Ignore unary +. Unary + is parsed differently and will not end up here.
    // Instead, it will modify the parsed integer later.
    if (*start == '+') start++;

    // Determine the multiplier from the base, and skip past any prefixes.
    uint32_t multiplier = 10;
    switch (base) {
        case PM_INTEGER_BASE_BINARY:
            start += 2; // 0b
            multiplier = 2;
            break;
        case PM_INTEGER_BASE_OCTAL:
            start++; // 0
            if (*start == '_' || *start == 'o' || *start == 'O') start++; // o
            multiplier = 8;
            break;
        case PM_INTEGER_BASE_DECIMAL:
            if (*start == '0' && (end - start) > 1) start += 2; // 0d
            break;
        case PM_INTEGER_BASE_HEXADECIMAL:
            start += 2; // 0x
            multiplier = 16;
            break;
        case PM_INTEGER_BASE_UNKNOWN:
            if (*start == '0' && (end - start) > 1) {
                switch (start[1]) {
                    case '_': start += 2; multiplier = 8; break;
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': start++; multiplier = 8; break;
                    case 'b': case 'B': start += 2; multiplier = 2; break;
                    case 'o': case 'O': start += 2; multiplier = 8; break;
                    case 'd': case 'D': start += 2; break;
                    case 'x': case 'X': start += 2; multiplier = 16; break;
                    default: assert(false && "unreachable"); break;
                }
            }
            break;
    }

    // It's possible that we've consumed everything at this point if there is an
    // invalid integer. If this is the case, we'll just return 0.
    if (start >= end) return;

    const uint8_t *ptr = start;
    uint64_t value = pm_integer_parse_digit(*ptr++);
    for (; ptr < end; ptr++) {
        if (*ptr == '_') continue;
        value = value * multiplier + pm_integer_parse_digit(*ptr);
        if (value > UINT32_MAX) {
            // If the integer is too large to fit into a single uint32_t, then we'll
            // parse it as a big integer.
            pm_integer_parse_big(integer, multiplier, start, end);
            return;
        }
    }
    integer->value = (uint32_t) value;
}

/**
 * Return the memory size of the integer.
 */
size_t
pm_integer_memsize(const pm_integer_t *integer) {
    return sizeof(pm_integer_t) + integer->length * sizeof(uint32_t);
}

/**
 * Compare two integers. This function returns -1 if the left integer is less
 * than the right integer, 0 if they are equal, and 1 if the left integer is
 * greater than the right integer.
 */
int
pm_integer_compare(const pm_integer_t *left, const pm_integer_t *right) {
    if (left->negative != right->negative) return left->negative ? -1 : 1;
    int negative = left->negative ? -1 : 1;

    if (left->values == right->values) {
        if (left->value < right->value) return -1 * negative;
        if (left->value > right->value) return 1 * negative;
        return 0;
    }

    if (left->values == NULL || left->length < right->length) return -1 * negative;
    if (right->values == NULL || left->length > right->length) return 1 * negative;

    for (size_t i = 0; i < left->length; i++) {
        size_t index = left->length - i - 1;
        uint32_t l = left->values[index];
        uint32_t r = right->values[index];
        if (l < r) return -1 * negative;
        if (l > r) return 1 * negative;
    }

    return 0;
}

/**
 * Convert an integer to a decimal string.
 */
PRISM_EXPORTED_FUNCTION void
pm_integer_string(pm_buffer_t *buffer, const pm_integer_t *integer) {
    if (integer->negative) {
        pm_buffer_append_byte(buffer, '-');
    }

    if (integer->values == NULL) {
        pm_buffer_append_format(buffer, "%" PRIu32, integer->value);
        return;
    }
    if (integer->length == 2) {
        const uint64_t value = ((uint64_t) integer->values[0]) | ((uint64_t) integer->values[1] << 32);
        pm_buffer_append_format(buffer, "%" PRIu64, value);
        return;
    }

    // Convert base from 1<<32 to 10**9.
    pm_integer_t converted = pm_integer_convert_base(*integer, (uint64_t) 1 << 32, 1000000000);

    if (converted.values == NULL) {
        pm_buffer_append_format(buffer, "%" PRIu32, converted.value);
        pm_integer_free(&converted);
        return;
    }

    // Allocate a buffer that we'll copy the decimal digits into.
    size_t char_length = converted.length * 9;
    char *digits = calloc(char_length, sizeof(char));
    if (digits == NULL) return;

    // Pack bigdecimal to digits.
    for (size_t i = 0; i < converted.length; i++) {
        uint32_t v = converted.values[i];
        for (size_t j = 0; j < 9; j++) {
            digits[char_length - 9 * i - j - 1] = (char) ('0' + v % 10);
            v /= 10;
        }
    }
    size_t start_offset = 0;
    while (start_offset < char_length - 1 && digits[start_offset] == '0') start_offset++;

    // Finally, append the string to the buffer and free the digits.
    pm_buffer_append_string(buffer, digits + start_offset, char_length - start_offset);
    free(digits);
    pm_integer_free(&converted);
}

/**
 * Free the internal memory of an integer. This memory will only be allocated if
 * the integer exceeds the size of a single uint32_t.
 */
PRISM_EXPORTED_FUNCTION void
pm_integer_free(pm_integer_t *integer) {
    if (integer->values) {
        free(integer->values);
    }
}
