/**
 * @file constant_pool.h
 *
 * A data structure that stores a set of strings.
 *
 * Each string is assigned a unique id, which can be used to compare strings for
 * equality. This comparison ends up being much faster than strcmp, since it
 * only requires a single integer comparison.
 */
#ifndef PRISM_CONSTANT_POOL_H
#define PRISM_CONSTANT_POOL_H

#include "prism/compiler/exported.h"
#include "prism/compiler/nodiscard.h"
#include "prism/compiler/nonnull.h"

#include <stddef.h>
#include <stdint.h>

/**
 * A constant id is a unique identifier for a constant in the constant pool.
 */
typedef uint32_t pm_constant_id_t;

/**
 * A list of constant IDs. Usually used to represent a set of locals.
 */
typedef struct {
    /** The number of constant ids in the list. */
    size_t size;

    /** The number of constant ids that have been allocated in the list. */
    size_t capacity;

    /** The constant ids in the list. */
    pm_constant_id_t *ids;
} pm_constant_id_list_t;

/** A constant in the pool which effectively stores a string. */
typedef struct pm_constant_t pm_constant_t;

/** The overall constant pool, which stores constants found while parsing. */
typedef struct pm_constant_pool_t pm_constant_pool_t;

/**
 * Return a raw pointer to the start of a constant.
 *
 * @param constant The constant to get the start of.
 * @return A raw pointer to the start of the constant.
 */
PRISM_EXPORTED_FUNCTION const uint8_t * pm_constant_start(const pm_constant_t *constant) PRISM_NONNULL(1);

/**
 * Return the length of a constant.
 *
 * @param constant The constant to get the length of.
 * @return The length of the constant.
 */
PRISM_EXPORTED_FUNCTION size_t pm_constant_length(const pm_constant_t *constant) PRISM_NONNULL(1);

#endif
