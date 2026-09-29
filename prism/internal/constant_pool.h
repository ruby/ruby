#ifndef PRISM_INTERNAL_CONSTANT_POOL_H
#define PRISM_INTERNAL_CONSTANT_POOL_H

#include "prism/constant_pool.h"

#include "prism/arena.h"
#include "prism/compiler/inline.h"

#include <stdbool.h>

/* A constant in the pool which effectively stores a string. */
struct pm_constant_t {
    /* A pointer to the start of the string. */
    const uint8_t *start;

    /* The length of the string. */
    size_t length;
};

/*
 * The type of bucket in the constant pool hash map. This determines how the
 * bucket should be freed.
 */
typedef unsigned int pm_constant_pool_bucket_type_t;

/* By default, each constant is a slice of the source. */
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_DEFAULT = 0;

/* An owned constant is one for which memory has been allocated. */
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_OWNED = 1;

/* A constant constant is known at compile time. */
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_CONSTANT = 2;

/* A bucket in the hash map. */
typedef struct {
    /* The incremental ID used for indexing back into the pool. */
    unsigned int id: 30;

    /* The type of the bucket, which determines how to free it. */
    pm_constant_pool_bucket_type_t type: 2;

    /* The hash of the bucket. */
    uint32_t hash;

    /*
     * A pointer to the start of the string, stored directly in the bucket to
     * avoid a pointer chase to the constants array during probing.
     */
    const uint8_t *start;

    /* The length of the string. */
    size_t length;
} pm_constant_pool_bucket_t;

/* The overall constant pool, which stores constants found while parsing. */
struct pm_constant_pool_t {
    /* The buckets in the hash map. */
    pm_constant_pool_bucket_t *buckets;

    /* The constants that are stored in the buckets. */
    pm_constant_t *constants;

    /* The number of buckets in the hash map. */
    uint32_t size;

    /* The number of buckets that have been allocated in the hash map. */
    uint32_t capacity;
};

/*
 * When we allocate constants into the pool, we reserve 0 to mean that the slot
 * is not yet filled. This constant is reused in other places to indicate the
 * lack of a constant id.
 */
#define PM_CONSTANT_ID_UNSET 0

/* Initialize a list of constant ids with a given capacity. */
void pm_constant_id_list_init_capacity(pm_arena_t *arena, pm_constant_id_list_t *list, size_t capacity);

/* Insert a constant id into a list of constant ids at the specified index. */
void pm_constant_id_list_insert(pm_constant_id_list_t *list, size_t index, pm_constant_id_t id);

/*
 * Mix the bits of a constant id so that ids which are close together, as
 * sequentially assigned ids are, land in unrelated slots of a hash table.
 */
static PRISM_INLINE uint32_t
pm_constant_id_hash(pm_constant_id_t id) {
    id = ((id >> 16) ^ id) * 0x45d9f3b;
    id = ((id >> 16) ^ id) * 0x45d9f3b;
    id = (id >> 16) ^ id;
    return id;
}

/*
 * A set of constant ids, for where the parser only needs to know whether it has
 * already seen a name, as with the variables a pattern captures or the named
 * capture groups of a regular expression.
 */
typedef struct {
    /* The number of ids in the set. */
    size_t size;

    /* The number of slots in `ids`, either zero or a power of two. */
    size_t capacity;

    /*
     * An open-addressed table of the ids in the set, where PM_CONSTANT_ID_UNSET
     * marks an empty slot. It is NULL until the first id is added.
     */
    pm_constant_id_t *ids;
} pm_constant_id_set_t;

/*
 * Add a constant id, which must not be PM_CONSTANT_ID_UNSET, to the set.
 * Returns whether the set did not already contain it.
 */
bool pm_constant_id_set_insert(pm_arena_t *arena, pm_constant_id_set_t *set, pm_constant_id_t id);

/* Initialize a new constant pool with a given capacity. */
void pm_constant_pool_init(pm_arena_t *arena, pm_constant_pool_t *pool, uint32_t capacity);

/* Return a pointer to the constant indicated by the given constant id. */
pm_constant_t * pm_constant_pool_id_to_constant(const pm_constant_pool_t *pool, pm_constant_id_t constant_id);

/*
 * Find a constant in a constant pool. Returns the id of the constant, or 0 if
 * the constant is not found.
 */
pm_constant_id_t pm_constant_pool_find(const pm_constant_pool_t *pool, const uint8_t *start, size_t length);

/*
 * Insert a constant into a constant pool that is a slice of a source string.
 * Returns the id of the constant, or 0 if any potential calls to resize fail.
 */
pm_constant_id_t pm_constant_pool_insert_shared(pm_arena_t *arena, pm_constant_pool_t *pool, const uint8_t *start, size_t length);

/*
 * Insert a constant into a constant pool from memory that is now owned by the
 * constant pool. Returns the id of the constant, or 0 if any potential calls to
 * resize fail.
 */
pm_constant_id_t pm_constant_pool_insert_owned(pm_arena_t *arena, pm_constant_pool_t *pool, uint8_t *start, size_t length);

/*
 * Insert a constant into a constant pool from memory that is constant. Returns
 * the id of the constant, or 0 if any potential calls to resize fail.
 */
pm_constant_id_t pm_constant_pool_insert_constant(pm_arena_t *arena, pm_constant_pool_t *pool, const uint8_t *start, size_t length);

#endif
