#include "prism/util/pm_integer.h"

/**
 * Create a new node for an integer in the linked list.
 */
static pm_integer_word_t *
pm_integer_node_create(pm_integer_t *integer, uint32_t value) {
    integer->length++;

    pm_integer_word_t *node = xmalloc(sizeof(pm_integer_word_t));
    if (node == NULL) return NULL;

    *node = (pm_integer_word_t) { .next = NULL, .value = value };
    return node;
}

/**
 * Copy one integer onto another.
 */
static void
pm_integer_copy(pm_integer_t *dest, const pm_integer_t *src) {
    dest->negative = src->negative;
    dest->length = 0;

    dest->head.value = src->head.value;
    dest->head.next = NULL;

    pm_integer_word_t *dest_current = &dest->head;
    const pm_integer_word_t *src_current = src->head.next;

    while (src_current != NULL) {
        dest_current->next = pm_integer_node_create(dest, src_current->value);
        if (dest_current->next == NULL) return;

        dest_current = dest_current->next;
        src_current = src_current->next;
    }

    dest_current->next = NULL;
}

/**
 * Add a 32-bit integer to an integer.
 */
static void
pm_integer_add(pm_integer_t *integer, uint32_t addend) {
    uint32_t carry = addend;
    pm_integer_word_t *current = &integer->head;

    while (carry > 0) {
        uint64_t result = (uint64_t) current->value + carry;
        carry = (uint32_t) (result >> 32);
        current->value = (uint32_t) result;

        if (carry > 0) {
            if (current->next == NULL) {
                current->next = pm_integer_node_create(integer, carry);
                break;
            }

            current = current->next;
        }
    }
}

/**
 * Multiple an integer by a 32-bit integer. In practice, the multiplier is the
 * base of the integer, so this is 2, 8, 10, or 16.
 */
static void
pm_integer_multiply(pm_integer_t *integer, uint32_t multiplier) {
    uint32_t carry = 0;

    for (pm_integer_word_t *current = &integer->head; current != NULL; current = current->next) {
        uint64_t result = (uint64_t) current->value * multiplier + carry;
        carry = (uint32_t) (result >> 32);
        current->value = (uint32_t) result;

        if (carry > 0 && current->next == NULL) {
            current->next = pm_integer_node_create(integer, carry);
            break;
        }
    }
}

/**
 * Divide an individual word by a 32-bit integer. This will recursively divide
 * any subsequent nodes in the linked list.
 */
static uint32_t
pm_integer_divide_word(pm_integer_t *integer, pm_integer_word_t *word, uint32_t dividend) {
    uint32_t remainder = 0;
    if (word->next != NULL) {
        remainder = pm_integer_divide_word(integer, word->next, dividend);

        if (integer->length > 0 && word->next->value == 0) {
            xfree(word->next);
            word->next = NULL;
            integer->length--;
        }
    }

    uint64_t value = ((uint64_t) remainder << 32) | word->value;
    word->value = (uint32_t) (value / dividend);
    return (uint32_t) (value % dividend);
}

/**
 * Divide an integer by a 32-bit integer. In practice, this is only 10 so that
 * we can format it as a string. It returns the remainder of the division.
 */
static uint32_t
pm_integer_divide(pm_integer_t *integer, uint32_t dividend) {
    return pm_integer_divide_word(integer, &integer->head, dividend);
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

    // Add the first digit to the integer.
    pm_integer_add(integer, pm_integer_parse_digit(*start++));

    // Add the subsequent digits to the integer.
    for (; start < end; start++) {
        if (*start == '_') continue;
        pm_integer_multiply(integer, multiplier);
        pm_integer_add(integer, pm_integer_parse_digit(*start));
    }
}

/**
 * Return the memory size of the integer.
 */
size_t
pm_integer_memsize(const pm_integer_t *integer) {
    return sizeof(pm_integer_t) + integer->length * sizeof(pm_integer_word_t);
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

    if (left->length < right->length) return -1 * negative;
    if (left->length > right->length) return 1 * negative;

    for (
        const pm_integer_word_t *left_word = &left->head, *right_word = &right->head;
        left_word != NULL && right_word != NULL;
        left_word = left_word->next, right_word = right_word->next
    ) {
        if (left_word->value < right_word->value) return -1 * negative;
        if (left_word->value > right_word->value) return 1 * negative;
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

    switch (integer->length) {
        case 0: {
            const uint32_t value = integer->head.value;
            pm_buffer_append_format(buffer, "%" PRIu32, value);
            return;
        }
        case 1: {
            const uint64_t value = ((uint64_t) integer->head.value) | (((uint64_t) integer->head.next->value) << 32);
            pm_buffer_append_format(buffer, "%" PRIu64, value);
            return;
        }
        default: {
            // First, allocate a buffer that we'll copy the decimal digits into.
            size_t length = (integer->length + 1) * 10;
            char *digits = xcalloc(length, sizeof(char));
            if (digits == NULL) return;

            // Next, create a new integer that we'll use to store the result of
            // the division and modulo operations.
            pm_integer_t copy;
            pm_integer_copy(&copy, integer);

            // Then, iterate through the integer, dividing by 10 and storing the
            // result in the buffer.
            char *ending = digits + length - 1;
            char *current = ending;

            while (copy.length > 0 || copy.head.value > 0) {
                uint32_t remainder = pm_integer_divide(&copy, 10);
                *current-- = (char) ('0' + remainder);
            }

            // Finally, append the string to the buffer and free the digits.
            pm_buffer_append_string(buffer, current + 1, (size_t) (ending - current));
            xfree(digits);
            return;
        }
    }
}

/**
 * Recursively destroy the linked list of an integer.
 */
static void
pm_integer_word_destroy(pm_integer_word_t *integer) {
    if (integer->next != NULL) {
        pm_integer_word_destroy(integer->next);
    }

    xfree(integer);
}

/**
 * Free the internal memory of an integer. This memory will only be allocated if
 * the integer exceeds the size of a single node in the linked list.
 */
PRISM_EXPORTED_FUNCTION void
pm_integer_free(pm_integer_t *integer) {
    if (integer->head.next) {
        pm_integer_word_destroy(integer->head.next);
    }
}
