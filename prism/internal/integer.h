/*
 * This module provides functions for working with arbitrary-sized integers.
 */
#ifndef PRISM_INTERNAL_INTEGER_H
#define PRISM_INTERNAL_INTEGER_H

#include "prism/arena.h"
#include "prism/buffer.h"
#include "prism/integer.h"

#include <stdint.h>

/* Return an integer holding the given non-negative value. */
static PRISM_INLINE pm_integer_t
pm_integer_uint64(uint64_t value) {
    return (pm_integer_t) {
        .length = value == 0 ? 0 : value <= UINT32_MAX ? 1 : 2,
        .words = { .value = { (uint32_t) value, (uint32_t) (value >> 32) } }
    };
}

/*
 * An enum controlling the base of an integer. It is expected that the base is
 * already known before parsing the integer, even though it could be derived
 * from the string itself.
 */
typedef enum {
    /* The binary base, indicated by a 0b or 0B prefix. */
    PM_INTEGER_BASE_BINARY = 2,

    /* The octal base, indicated by a 0, 0o, or 0O prefix. */
    PM_INTEGER_BASE_OCTAL = 8,

    /* The decimal base, indicated by a 0d, 0D, or empty prefix. */
    PM_INTEGER_BASE_DECIMAL = 10,

    /* The hexadecimal base, indicated by a 0x or 0X prefix. */
    PM_INTEGER_BASE_HEXADECIMAL = 16
} pm_integer_base_t;

/*
 * Parse an integer from a string. This assumes that the format of the integer
 * has already been validated, as internal validation checks are not performed
 * here. The words of an integer that does not fit in two words are allocated
 * from the given arena.
 */
void pm_integer_parse(pm_arena_t *arena, pm_integer_t *integer, pm_integer_base_t base, const uint8_t *start, const uint8_t *end);

/*
 * Compare two integers. This function returns -1 if the left integer is less
 * than the right integer, 0 if they are equal, and 1 if the left integer is
 * greater than the right integer.
 */
int pm_integer_compare(const pm_integer_t *left, const pm_integer_t *right);

/*
 * Parse a float rational literal like 1.5r, given its digits and decimal point
 * without the r suffix, into a numerator and denominator in lowest terms. Words
 * of either that do not fit in two words are allocated from the given arena.
 */
void pm_integer_parse_rational(pm_arena_t *arena, pm_integer_t *numerator, pm_integer_t *denominator, const uint8_t *start, const uint8_t *end);

/* Convert an integer to a decimal string. */
void pm_integer_string(pm_buffer_t *buffer, const pm_integer_t *integer);

#endif
