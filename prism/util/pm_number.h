/**
 * @file pm_number.h
 *
 * This module provides functions for working with arbitrary-sized numbers.
 */
#ifndef PRISM_NUMBER_H
#define PRISM_NUMBER_H

#include "prism/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * A node in the linked list of a pm_number_t.
 */
typedef struct pm_number_node {
    /** A pointer to the next node in the list. */
    struct pm_number_node *next;

    /** The value of the node. */
    uint32_t value;
} pm_number_node_t;

/**
 * This structure represents an arbitrary-sized number. It is implemented as a
 * linked list of 32-bit integers, with the least significant digit at the head
 * of the list.
 */
typedef struct {
    /**
     * The head of the linked list, embedded directly so that allocations do not
     * need to be performed for small numbers.
     */
    pm_number_node_t head;

    /** The number of nodes in the linked list that have been allocated. */
    size_t length;

    /**
     * Whether or not the number is negative. It is stored this way so that a
     * zeroed pm_number_t is always positive zero.
     */
    bool negative;
} pm_number_t;

/**
 * An enum controlling the base of a number. It is expected that the base is
 * already known before parsing the number, even though it could be derived from
 * the string itself.
 */
typedef enum {
    /** The binary base, indicated by a 0b or 0B prefix. */
    PM_NUMBER_BASE_BINARY,

    /** The octal base, indicated by a 0, 0o, or 0O prefix. */
    PM_NUMBER_BASE_OCTAL,

    /** The decimal base, indicated by a 0d, 0D, or empty prefix. */
    PM_NUMBER_BASE_DECIMAL,

    /** The hexidecimal base, indicated by a 0x or 0X prefix. */
    PM_NUMBER_BASE_HEXADECIMAL,

    /**
     * An unknown base, in which case pm_number_parse will derive it based on
     * the content of the string. This is less efficient and does more
     * comparisons, so if callers know the base ahead of time, they should use
     * that instead.
     */
    PM_NUMBER_BASE_UNKNOWN
} pm_number_base_t;

/**
 * Parse a number from a string. This assumes that the format of the number has
 * already been validated, as internal validation checks are not performed here.
 *
 * @param number The number to parse into.
 * @param base The base of the number.
 * @param start The start of the string.
 * @param end The end of the string.
 */
PRISM_EXPORTED_FUNCTION void pm_number_parse(pm_number_t *number, pm_number_base_t base, const uint8_t *start, const uint8_t *end);

/**
 * Free the internal memory of a number. This memory will only be allocated if
 * the number exceeds the size of a single node in the linked list.
 *
 * @param number The number to free.
 */
PRISM_EXPORTED_FUNCTION void pm_number_free(pm_number_t *number);

#endif
