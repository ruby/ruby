// The constant pool is a data structure that stores a set of strings. Each
// string is assigned a unique id, which can be used to compare strings for
// equality. This comparison ends up being much faster than strcmp, since it
// only requires a single integer comparison.

#ifndef YP_CONSTANT_POOL_H
#define YP_CONSTANT_POOL_H

#include "yarp/defines.h"

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uint32_t yp_constant_id_t;

typedef struct {
    yp_constant_id_t *ids;
    size_t size;
    size_t capacity;
} yp_constant_id_list_t;

// Initialize a list of constant ids.
void yp_constant_id_list_init(yp_constant_id_list_t *list);

// Append a constant id to a list of constant ids. Returns false if any
// potential reallocations fail.
bool yp_constant_id_list_append(yp_constant_id_list_t *list, yp_constant_id_t id);

// Checks if the current constant id list includes the given constant id.
bool
yp_constant_id_list_includes(yp_constant_id_list_t *list, yp_constant_id_t id);

// Get the memory size of a list of constant ids.
size_t yp_constant_id_list_memsize(yp_constant_id_list_t *list);

// Free the memory associated with a list of constant ids.
void yp_constant_id_list_free(yp_constant_id_list_t *list);

typedef struct {
    unsigned int id: 31;
    bool owned: 1;
    const uint8_t *start;
    size_t length;
    size_t hash;
} yp_constant_t;

typedef struct {
    yp_constant_t *constants;
    size_t size;
    size_t capacity;
} yp_constant_pool_t;

// Define an empty constant pool.
#define YP_CONSTANT_POOL_EMPTY ((yp_constant_pool_t) { .constants = NULL, .size = 0, .capacity = 0 })

// Initialize a new constant pool with a given capacity.
bool yp_constant_pool_init(yp_constant_pool_t *pool, size_t capacity);

// Insert a constant into a constant pool that is a slice of a source string.
// Returns the id of the constant, or 0 if any potential calls to resize fail.
yp_constant_id_t yp_constant_pool_insert_shared(yp_constant_pool_t *pool, const uint8_t *start, size_t length);

// Insert a constant into a constant pool from memory that is now owned by the
// constant pool. Returns the id of the constant, or 0 if any potential calls to
// resize fail.
yp_constant_id_t yp_constant_pool_insert_owned(yp_constant_pool_t *pool, const uint8_t *start, size_t length);

// Free the memory associated with a constant pool.
void yp_constant_pool_free(yp_constant_pool_t *pool);

#endif
