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

/**
 * The type of bucket in the constant pool hash map. This determines how the
 * bucket should be freed.
 */
typedef unsigned int pm_constant_pool_bucket_type_t;

/** By default, each constant is a slice of the source. */
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_DEFAULT = 0;

/** An owned constant is one for which memory has been allocated. */
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_OWNED = 1;

/** A constant constant is known at compile time. */
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_CONSTANT = 2;

/** A bucket in the hash map. */
typedef struct {
    /** The incremental ID used for indexing back into the pool. */
    unsigned int id: 30;

    /** The type of the bucket, which determines how to free it. */
    pm_constant_pool_bucket_type_t type: 2;

    /** The hash of the bucket. */
    uint32_t hash;

    /**
     * A pointer to the start of the string, stored directly in the bucket to
     * avoid a pointer chase to the constants array during probing.
     */
    const uint8_t *start;

    /** The length of the string. */
    size_t length;
} pm_constant_pool_bucket_t;

/** A constant in the pool which effectively stores a string. */
typedef struct {
    /** A pointer to the start of the string. */
    const uint8_t *start;

    /** The length of the string. */
    size_t length;
} pm_constant_t;

/** The overall constant pool, which stores constants found while parsing. */
typedef struct {
    /** The buckets in the hash map. */
    pm_constant_pool_bucket_t *buckets;

    /** The constants that are stored in the buckets. */
    pm_constant_t *constants;

    /** The number of buckets in the hash map. */
    uint32_t size;

    /** The number of buckets that have been allocated in the hash map. */
    uint32_t capacity;
} pm_constant_pool_t;

#endif
