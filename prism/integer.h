/**
 * @file integer.h
 *
 * This module provides functions for working with arbitrary-sized integers.
 */
#ifndef PRISM_INTEGER_H
#define PRISM_INTEGER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * A structure represents an arbitrary-sized integer.
 */
typedef struct {
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
     * Embedded value for small integer. This value is set to 0 if the value
     * does not fit into uint32_t.
     */
    uint32_t value;

    /**
     * Whether or not the integer is negative. It is stored this way so that a
     * zeroed pm_integer_t is always positive zero.
     */
    bool negative;
} pm_integer_t;

#endif
