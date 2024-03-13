/**
 * @file pm_integer.h
 *
 * This module provides functions for working with arbitrary-sized integers.
 */
#ifndef PRISM_NUMBER_H
#define PRISM_NUMBER_H

#include "prism/defines.h"
#include "prism/util/pm_buffer.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * A structure represents an arbitrary-sized integer.
 */
typedef struct {
    /**
     * Embedded value for small integer. This value is set to 0 if the value
     * does not fit into uint32_t.
     */
    uint32_t value;

    /**
     * The number of allocated values. length is set to 0 if the integer fits
     * into uint32_t.
     */
    size_t length;

    /**
     * List of 32-bit integers. Set to NULL if the integer fits into uint32_t.
     */
    uint32_t *values;

    /**
     * Whether or not the integer is negative. It is stored this way so that a
     * zeroed pm_integer_t is always positive zero.
     */
    bool negative;
} pm_integer_t;

/**
 * An enum controlling the base of an integer. It is expected that the base is
 * already known before parsing the integer, even though it could be derived
 * from the string itself.
 */
typedef enum {
    /** The binary base, indicated by a 0b or 0B prefix. */
    PM_INTEGER_BASE_BINARY,

    /** The octal base, indicated by a 0, 0o, or 0O prefix. */
    PM_INTEGER_BASE_OCTAL,

    /** The decimal base, indicated by a 0d, 0D, or empty prefix. */
    PM_INTEGER_BASE_DECIMAL,

    /** The hexadecimal base, indicated by a 0x or 0X prefix. */
    PM_INTEGER_BASE_HEXADECIMAL,

    /**
     * An unknown base, in which case pm_integer_parse will derive it based on
     * the content of the string. This is less efficient and does more
     * comparisons, so if callers know the base ahead of time, they should use
     * that instead.
     */
    PM_INTEGER_BASE_UNKNOWN
} pm_integer_base_t;

/**
 * Parse an integer from a string. This assumes that the format of the integer
 * has already been validated, as internal validation checks are not performed
 * here.
 *
 * @param integer The integer to parse into.
 * @param base The base of the integer.
 * @param start The start of the string.
 * @param end The end of the string.
 */
PRISM_EXPORTED_FUNCTION void pm_integer_parse(pm_integer_t *integer, pm_integer_base_t base, const uint8_t *start, const uint8_t *end);

/**
 * Return the memory size of the integer.
 *
 * @param integer The integer to get the memory size of.
 * @return The size of the memory associated with the integer.
 */
size_t pm_integer_memsize(const pm_integer_t *integer);

/**
 * Compare two integers. This function returns -1 if the left integer is less
 * than the right integer, 0 if they are equal, and 1 if the left integer is
 * greater than the right integer.
 *
 * @param left The left integer to compare.
 * @param right The right integer to compare.
 * @return The result of the comparison.
 */
int pm_integer_compare(const pm_integer_t *left, const pm_integer_t *right);

/**
 * Convert an integer to a decimal string.
 *
 * @param buffer The buffer to append the string to.
 * @param integer The integer to convert to a string.
 */
PRISM_EXPORTED_FUNCTION void pm_integer_string(pm_buffer_t *buffer, const pm_integer_t *integer);

/**
 * Free the internal memory of an integer. This memory will only be allocated if
 * the integer exceeds the size of a single node in the linked list.
 *
 * @param integer The integer to free.
 */
PRISM_EXPORTED_FUNCTION void pm_integer_free(pm_integer_t *integer);

#endif
