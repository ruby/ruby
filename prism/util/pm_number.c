#include "prism/util/pm_number.h"

/**
 * Create a new node for a number in the linked list.
 */
static pm_number_node_t *
pm_number_node_create(pm_number_t *number, uint32_t value) {
    number->length++;
    pm_number_node_t *node = malloc(sizeof(pm_number_node_t));
    *node = (pm_number_node_t) { .next = NULL, .value = value };
    return node;
}

/**
 * Add a 32-bit integer to a number.
 */
static void
pm_number_add(pm_number_t *number, uint32_t addend) {
    uint32_t carry = addend;
    pm_number_node_t *current = &number->head;

    while (carry > 0) {
        uint64_t result = (uint64_t) current->value + carry;
        carry = (uint32_t) (result >> 32);
        current->value = (uint32_t) result;

        if (carry > 0) {
            if (current->next == NULL) {
                current->next = pm_number_node_create(number, carry);
                break;
            }

            current = current->next;
        }
    }
}

/**
 * Multiple a number by a 32-bit integer. In practice, the multiplier is the
 * base of the number, so this is 2, 8, 10, or 16.
 */
static void
pm_number_multiply(pm_number_t *number, uint32_t multiplier) {
    uint32_t carry = 0;

    for (pm_number_node_t *current = &number->head; current != NULL; current = current->next) {
        uint64_t result = (uint64_t) current->value * multiplier + carry;
        carry = (uint32_t) (result >> 32);
        current->value = (uint32_t) result;

        if (carry > 0 && current->next == NULL) {
            current->next = pm_number_node_create(number, carry);
            break;
        }
    }
}

/**
 * Return the value of a digit in a number.
 */
static uint32_t
pm_number_parse_digit(const uint8_t character) {
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
        default: assert(false && "unreachable");
    }
}

/**
 * Parse a number from a string. This assumes that the format of the number has
 * already been validated, as internal validation checks are not performed here.
 */
PRISM_EXPORTED_FUNCTION void
pm_number_parse(pm_number_t *number, pm_number_base_t base, const uint8_t *start, const uint8_t *end) {
    // Ignore unary +. Unary + is parsed differently and will not end up here.
    // Instead, it will modify the parsed number later.
    if (*start == '+') start++;

    // Determine the multiplier from the base, and skip past any prefixes.
    uint32_t multiplier;
    switch (base) {
        case PM_NUMBER_BASE_BINARY:
            start += 2; // 0b
            multiplier = 2;
            break;
        case PM_NUMBER_BASE_OCTAL:
            start++; // 0
            if (*start == 'o' || *start == 'O') start++; // o
            multiplier = 8;
            break;
        case PM_NUMBER_BASE_DECIMAL:
            if (*start == '0' && (end - start) > 1) start += 2; // 0d
            multiplier = 10;
            break;
        case PM_NUMBER_BASE_HEXADECIMAL:
            start += 2; // 0x
            multiplier = 16;
            break;
        case PM_NUMBER_BASE_UNKNOWN:
            if (*start == '0' && (end - start) > 1) {
                switch (start[1]) {
                    case '0': case '1': case '2': case '3': case '4': case '5': case '6': case '7': start++; multiplier = 8; break;
                    case 'b': case 'B': start += 2; multiplier = 2; break;
                    case 'o': case 'O': start += 2; multiplier = 8; break;
                    case 'd': case 'D': start += 2; multiplier = 10; break;
                    case 'x': case 'X': start += 2; multiplier = 16; break;
                    default: assert(false && "unreachable");
                }
            } else {
                multiplier = 10;
            }
            break;
    }

    // It's possible that we've consumed everything at this point if there is an
    // invalid number. If this is the case, we'll just return 0.
    if (start >= end) return;

    // Add the first digit to the number.
    pm_number_add(number, pm_number_parse_digit(*start++));

    // Add the subsequent digits to the number.
    for (; start < end; start++) {
        if (*start == '_') continue;
        pm_number_multiply(number, multiplier);
        pm_number_add(number, pm_number_parse_digit(*start));
    }
}

/**
 * Return the memory size of the number.
 */
size_t
pm_number_memsize(const pm_number_t *number) {
    return sizeof(pm_number_t) + number->length * sizeof(pm_number_node_t);
}

/**
 * Recursively destroy the linked list of a number.
 */
static void
pm_number_node_destroy(pm_number_node_t *number) {
    if (number->next != NULL) {
        pm_number_node_destroy(number->next);
    }

    free(number);
}

/**
 * Free the internal memory of a number. This memory will only be allocated if
 * the number exceeds the size of a single node in the linked list.
 */
PRISM_EXPORTED_FUNCTION void
pm_number_free(pm_number_t *number) {
    if (number->head.next) {
        pm_number_node_destroy(number->head.next);
    }
}
