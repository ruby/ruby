// The constant pool is a data structure that stores a set of strings. Each
// string is assigned a unique id, which can be used to compare strings for
// equality. This comparison ends up being much faster than strcmp, since it
// only requires a single integer comparison.

#ifndef PRISM_CONSTANT_POOL_H
#define PRISM_CONSTANT_POOL_H

#include "prism/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uint32_t pm_constant_id_t;

typedef struct {
    pm_constant_id_t *ids;
    size_t size;
    size_t capacity;
} pm_constant_id_list_t;

// Initialize a list of constant ids.
void pm_constant_id_list_init(pm_constant_id_list_t *list);

// Append a constant id to a list of constant ids. Returns false if any
// potential reallocations fail.
bool pm_constant_id_list_append(pm_constant_id_list_t *list, pm_constant_id_t id);

// Checks if the current constant id list includes the given constant id.
bool
pm_constant_id_list_includes(pm_constant_id_list_t *list, pm_constant_id_t id);

// Get the memory size of a list of constant ids.
size_t pm_constant_id_list_memsize(pm_constant_id_list_t *list);

// Free the memory associated with a list of constant ids.
void pm_constant_id_list_free(pm_constant_id_list_t *list);

// Constant pool buckets can have a couple of different types.
typedef unsigned int pm_constant_pool_bucket_type_t;

// By default, each constant is a slice of the source.
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_DEFAULT = 0;

// An owned constant is one for which memory has been allocated.
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_OWNED = 1;

// A constant constant is known at compile time.
static const pm_constant_pool_bucket_type_t PM_CONSTANT_POOL_BUCKET_CONSTANT = 2;

typedef struct {
    unsigned int id: 30;
    pm_constant_pool_bucket_type_t type: 2;
    uint32_t hash;
} pm_constant_pool_bucket_t;

typedef struct {
    const uint8_t *start;
    size_t length;
} pm_constant_t;

typedef struct {
    pm_constant_pool_bucket_t *buckets;
    pm_constant_t *constants;
    uint32_t size;
    uint32_t capacity;
} pm_constant_pool_t;

// Define an empty constant pool.
#define PM_CONSTANT_POOL_EMPTY ((pm_constant_pool_t) { .buckets = NULL, .constants = NULL, .size = 0, .capacity = 0 })

// Initialize a new constant pool with a given capacity.
bool pm_constant_pool_init(pm_constant_pool_t *pool, uint32_t capacity);

// Return a pointer to the constant indicated by the given constant id.
pm_constant_t * pm_constant_pool_id_to_constant(pm_constant_pool_t *pool, pm_constant_id_t constant_id);

// Insert a constant into a constant pool that is a slice of a source string.
// Returns the id of the constant, or 0 if any potential calls to resize fail.
pm_constant_id_t pm_constant_pool_insert_shared(pm_constant_pool_t *pool, const uint8_t *start, size_t length);

// Insert a constant into a constant pool from memory that is now owned by the
// constant pool. Returns the id of the constant, or 0 if any potential calls to
// resize fail.
pm_constant_id_t pm_constant_pool_insert_owned(pm_constant_pool_t *pool, const uint8_t *start, size_t length);

// Insert a constant into a constant pool from memory that is constant. Returns
// the id of the constant, or 0 if any potential calls to resize fail.
pm_constant_id_t pm_constant_pool_insert_constant(pm_constant_pool_t *pool, const uint8_t *start, size_t length);

// Free the memory associated with a constant pool.
void pm_constant_pool_free(pm_constant_pool_t *pool);

#endif
