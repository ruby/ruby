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

// Resize a constant pool to a given capacity.
static inline bool
yp_constant_pool_resize(yp_constant_pool_t *pool) {
    size_t next_capacity = pool->capacity * 2;
    yp_constant_t *next_constants = calloc(next_capacity, sizeof(yp_constant_t));
    if (next_constants == NULL) return false;

    // For each constant in the current constant pool, rehash the content, find
    // the index in the next constant pool, and insert it.
    for (size_t index = 0; index < pool->capacity; index++) {
        yp_constant_t *constant = &pool->constants[index];

        // If an id is set on this constant, then we know we have content here.
        // In this case we need to insert it into the next constant pool.
        if (constant->id != 0) {
            size_t next_index = constant->hash % next_capacity;

            // This implements linear scanning to find the next available slot
            // in case this index is already taken. We don't need to bother
            // comparing the values since we know that the hash is unique.
            while (next_constants[next_index].id != 0) {
                next_index = (next_index + 1) % next_capacity;
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
    pool->constants = calloc(capacity, sizeof(yp_constant_t));
    if (pool->constants == NULL) return false;

    pool->size = 0;
    pool->capacity = capacity;
    return true;
}

// Insert a constant into a constant pool and return its index in the pool.
static size_t
yp_constant_pool_insert(yp_constant_pool_t *pool, const uint8_t *start, size_t length) {
    if (pool->size >= (pool->capacity / 4 * 3)) {
        if (!yp_constant_pool_resize(pool)) return pool->capacity;
    }

    size_t hash = yp_constant_pool_hash(start, length);
    size_t index = hash % pool->capacity;
    yp_constant_t *constant;

    while (constant = &pool->constants[index], constant->id != 0) {
        // If there is a collision, then we need to check if the content is the
        // same as the content we are trying to insert. If it is, then we can
        // return the id of the existing constant.
        if ((constant->length == length) && memcmp(constant->start, start, length) == 0) {
            return index;
        }

        index = (index + 1) % pool->capacity;
    }

    pool->size++;
    assert(pool->size < ((size_t) (1 << 31)));

    pool->constants[index] = (yp_constant_t) {
        .id = (unsigned int) (pool->size & 0x7FFFFFFF),
        .start = start,
        .length = length,
        .hash = hash
    };

    return index;
}

// Insert a constant into a constant pool. Returns the id of the constant, or 0
// if any potential calls to resize fail.
yp_constant_id_t
yp_constant_pool_insert_shared(yp_constant_pool_t *pool, const uint8_t *start, size_t length) {
    size_t index = yp_constant_pool_insert(pool, start, length);
    return index == pool->capacity ? 0 : ((yp_constant_id_t) pool->constants[index].id);
}

// Insert a constant into a constant pool from memory that is now owned by the
// constant pool. Returns the id of the constant, or 0 if any potential calls to
// resize fail.
yp_constant_id_t
yp_constant_pool_insert_owned(yp_constant_pool_t *pool, const uint8_t *start, size_t length) {
    size_t index = yp_constant_pool_insert(pool, start, length);
    if (index == pool->capacity) return 0;

    yp_constant_t *constant = &pool->constants[index];
    constant->owned = true;
    return ((yp_constant_id_t) constant->id);
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
