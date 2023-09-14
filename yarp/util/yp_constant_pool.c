#include "yarp/util/yp_constant_pool.h"

// Initialize a list of constant ids.
void
yp_constant_id_list_init(yp_constant_id_list_t *list) {
    list->ids = NULL;
    list->size = 0;
    list->capacity = 0;
}

// Append a constant id to a list of constant ids. Returns false if any
// potential reallocations fail.
bool
yp_constant_id_list_append(yp_constant_id_list_t *list, yp_constant_id_t id) {
    if (list->size >= list->capacity) {
        list->capacity = list->capacity == 0 ? 8 : list->capacity * 2;
        list->ids = (yp_constant_id_t *) realloc(list->ids, sizeof(yp_constant_id_t) * list->capacity);
        if (list->ids == NULL) return false;
    }

    list->ids[list->size++] = id;
    return true;
}

// Checks if the current constant id list includes the given constant id.
bool
yp_constant_id_list_includes(yp_constant_id_list_t *list, yp_constant_id_t id) {
    for (size_t index = 0; index < list->size; index++) {
        if (list->ids[index] == id) return true;
    }
    return false;
}

// Get the memory size of a list of constant ids.
size_t
yp_constant_id_list_memsize(yp_constant_id_list_t *list) {
    return sizeof(yp_constant_id_list_t) + (list->capacity * sizeof(yp_constant_id_t));
}

// Free the memory associated with a list of constant ids.
void
yp_constant_id_list_free(yp_constant_id_list_t *list) {
    if (list->ids != NULL) {
        free(list->ids);
    }
}

// A relatively simple hash function (djb2) that is used to hash strings. We are
// optimizing here for simplicity and speed.
static inline size_t
yp_constant_pool_hash(const uint8_t *start, size_t length) {
    // This is a prime number used as the initial value for the hash function.
    size_t value = 5381;

    for (size_t index = 0; index < length; index++) {
        value = ((value << 5) + value) + start[index];
    }

    return value;
}

// https://graphics.stanford.edu/~seander/bithacks.html#RoundUpPowerOf2
static size_t
next_power_of_two(size_t v) {
    // Avoid underflow in subtraction on next line.
    if (v == 0) {
        // 1 is the nearest power of 2 to 0 (2^0)
        return 1;
    }
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
#if defined(__LP64__) || defined(_WIN64)
    v |= v >> 32;
#endif
    v++;
    return v;
}

#ifndef NDEBUG
static bool
is_power_of_two(size_t size) {
    return (size & (size - 1)) == 0;
}
#endif

// Resize a constant pool to a given capacity.
static inline bool
yp_constant_pool_resize(yp_constant_pool_t *pool) {
    assert(is_power_of_two(pool->capacity));
    size_t next_capacity = pool->capacity * 2;
    if (next_capacity < pool->capacity) return false;

    const size_t mask = next_capacity - 1;
    yp_constant_t *next_constants = calloc(next_capacity, sizeof(yp_constant_t));
    if (next_constants == NULL) return false;

    // For each constant in the current constant pool, rehash the content, find
    // the index in the next constant pool, and insert it.
    for (size_t index = 0; index < pool->capacity; index++) {
        yp_constant_t *constant = &pool->constants[index];

        // If an id is set on this constant, then we know we have content here.
        // In this case we need to insert it into the next constant pool.
        if (constant->id != 0) {
            size_t next_index = constant->hash & mask;

            // This implements linear scanning to find the next available slot
            // in case this index is already taken. We don't need to bother
            // comparing the values since we know that the hash is unique.
            while (next_constants[next_index].id != 0) {
                next_index = (next_index + 1) & mask;
            }

            // Here we copy over the entire constant, which includes the id so
            // that they are consistent between resizes.
            next_constants[next_index] = *constant;
        }
    }

    free(pool->constants);
    pool->constants = next_constants;
    pool->capacity = next_capacity;
    return true;
}

// Initialize a new constant pool with a given capacity.
bool
yp_constant_pool_init(yp_constant_pool_t *pool, size_t capacity) {
    const size_t size_t_max = (~((size_t) 0));
    if (capacity >= ((size_t_max / 2) + 1)) return false;

    capacity = next_power_of_two(capacity);
    pool->constants = calloc(capacity, sizeof(yp_constant_t));
    if (pool->constants == NULL) return false;

    pool->size = 0;
    pool->capacity = capacity;
    return true;
}

// Insert a constant into a constant pool and return its index in the pool.
static inline yp_constant_id_t
yp_constant_pool_insert(yp_constant_pool_t *pool, const uint8_t *start, size_t length, bool owned) {
    if (pool->size >= (pool->capacity / 4 * 3)) {
        if (!yp_constant_pool_resize(pool)) return 0;
    }

    assert(is_power_of_two(pool->capacity));
    const size_t mask = pool->capacity - 1;
    size_t hash = yp_constant_pool_hash(start, length);
    size_t index = hash & mask;
    yp_constant_t *constant;

    while (constant = &pool->constants[index], constant->id != 0) {
        // If there is a collision, then we need to check if the content is the
        // same as the content we are trying to insert. If it is, then we can
        // return the id of the existing constant.
        if ((constant->length == length) && memcmp(constant->start, start, length) == 0) {
            // Since we have found a match, we need to check if this is
            // attempting to insert a shared or an owned constant. We want to
            // prefer shared constants since they don't require allocations.
            if (owned) {
                // If we're attempting to insert an owned constant and we have
                // an existing constant, then either way we don't want the given
                // memory. Either it's duplicated with the existing constant or
                // it's not necessary because we have a shared version.
                free((void *) start);
            } else if (constant->owned) {
                // If we're attempting to insert a shared constant and the
                // existing constant is owned, then we can free the owned
                // constant and replace it with the shared constant.
                free((void *) constant->start);
                constant->start = start;
                constant->owned = false;
            }

            return constant->id;
        }

        index = (index + 1) & mask;
    }

    pool->size++;
    assert(pool->size < ((size_t) (1 << 31)));

    *constant = (yp_constant_t) {
        .id = (unsigned int) (pool->size & 0x7FFFFFFF),
        .owned = owned,
        .start = start,
        .length = length,
        .hash = hash
    };

    return constant->id;
}

// Insert a constant into a constant pool. Returns the id of the constant, or 0
// if any potential calls to resize fail.
yp_constant_id_t
yp_constant_pool_insert_shared(yp_constant_pool_t *pool, const uint8_t *start, size_t length) {
    return yp_constant_pool_insert(pool, start, length, false);
}

// Insert a constant into a constant pool from memory that is now owned by the
// constant pool. Returns the id of the constant, or 0 if any potential calls to
// resize fail.
yp_constant_id_t
yp_constant_pool_insert_owned(yp_constant_pool_t *pool, const uint8_t *start, size_t length) {
    return yp_constant_pool_insert(pool, start, length, true);
}

// Free the memory associated with a constant pool.
void
yp_constant_pool_free(yp_constant_pool_t *pool) {
    // For each constant in the current constant pool, free the contents if the
    // contents are owned.
    for (uint32_t index = 0; index < pool->capacity; index++) {
        yp_constant_t *constant = &pool->constants[index];

        // If an id is set on this constant, then we know we have content here.
        if (constant->id != 0 && constant->owned) {
            free((void *) constant->start);
        }
    }

    free(pool->constants);
}
