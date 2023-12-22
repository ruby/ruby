#include "prism/util/pm_constant_pool.h"

/**
 * Initialize a list of constant ids.
 */
void
pm_constant_id_list_init(pm_constant_id_list_t *list) {
    list->ids = NULL;
    list->size = 0;
    list->capacity = 0;
}

/**
 * Append a constant id to a list of constant ids. Returns false if any
 * potential reallocations fail.
 */
bool
pm_constant_id_list_append(pm_constant_id_list_t *list, pm_constant_id_t id) {
    if (list->size >= list->capacity) {
        list->capacity = list->capacity == 0 ? 8 : list->capacity * 2;
        list->ids = (pm_constant_id_t *) realloc(list->ids, sizeof(pm_constant_id_t) * list->capacity);
        if (list->ids == NULL) return false;
    }

    list->ids[list->size++] = id;
    return true;
}

/**
 * Checks if the current constant id list includes the given constant id.
 */
bool
pm_constant_id_list_includes(pm_constant_id_list_t *list, pm_constant_id_t id) {
    for (size_t index = 0; index < list->size; index++) {
        if (list->ids[index] == id) return true;
    }
    return false;
}

/**
 * Get the memory size of a list of constant ids.
 */
size_t
pm_constant_id_list_memsize(pm_constant_id_list_t *list) {
    return sizeof(pm_constant_id_list_t) + (list->capacity * sizeof(pm_constant_id_t));
}

/**
 * Free the memory associated with a list of constant ids.
 */
void
pm_constant_id_list_free(pm_constant_id_list_t *list) {
    if (list->ids != NULL) {
        free(list->ids);
    }
}

/**
 * A relatively simple hash function (djb2) that is used to hash strings. We are
 * optimizing here for simplicity and speed.
 */
static inline uint32_t
pm_constant_pool_hash(const uint8_t *start, size_t length) {
    // This is a prime number used as the initial value for the hash function.
    uint32_t value = 5381;

    for (size_t index = 0; index < length; index++) {
        value = ((value << 5) + value) + start[index];
    }

    return value;
}

/**
 * https://graphics.stanford.edu/~seander/bithacks.html#RoundUpPowerOf2
 */
static uint32_t
next_power_of_two(uint32_t v) {
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
    v++;
    return v;
}

#ifndef NDEBUG
static bool
is_power_of_two(uint32_t size) {
    return (size & (size - 1)) == 0;
}
#endif

/**
 * Resize a constant pool to a given capacity.
 */
static inline bool
pm_constant_pool_resize(pm_constant_pool_t *pool) {
    assert(is_power_of_two(pool->capacity));

    uint32_t next_capacity = pool->capacity * 2;
    if (next_capacity < pool->capacity) return false;

    const uint32_t mask = next_capacity - 1;
    const size_t element_size = sizeof(pm_constant_pool_bucket_t) + sizeof(pm_constant_t);

    void *next = calloc(next_capacity, element_size);
    if (next == NULL) return false;

    pm_constant_pool_bucket_t *next_buckets = next;
    pm_constant_t *next_constants = (void *)(((char *) next) + next_capacity * sizeof(pm_constant_pool_bucket_t));

    // For each bucket in the current constant pool, find the index in the
    // next constant pool, and insert it.
    for (uint32_t index = 0; index < pool->capacity; index++) {
        pm_constant_pool_bucket_t *bucket = &pool->buckets[index];

        // If an id is set on this constant, then we know we have content here.
        // In this case we need to insert it into the next constant pool.
        if (bucket->id != 0) {
            uint32_t next_index = bucket->hash & mask;

            // This implements linear scanning to find the next available slot
            // in case this index is already taken. We don't need to bother
            // comparing the values since we know that the hash is unique.
            while (next_buckets[next_index].id != 0) {
                next_index = (next_index + 1) & mask;
            }

            // Here we copy over the entire bucket, which includes the id so
            // that they are consistent between resizes.
            next_buckets[next_index] = *bucket;
        }
    }

    // The constants are stable with respect to hash table resizes.
    memcpy(next_constants, pool->constants, pool->size * sizeof(pm_constant_t));

    // pool->constants and pool->buckets are allocated out of the same chunk
    // of memory, with the buckets coming first.
    free(pool->buckets);
    pool->constants = next_constants;
    pool->buckets = next_buckets;
    pool->capacity = next_capacity;
    return true;
}

/**
 * Initialize a new constant pool with a given capacity.
 */
bool
pm_constant_pool_init(pm_constant_pool_t *pool, uint32_t capacity) {
    const uint32_t maximum = (~((uint32_t) 0));
    if (capacity >= ((maximum / 2) + 1)) return false;

    capacity = next_power_of_two(capacity);
    const size_t element_size = sizeof(pm_constant_pool_bucket_t) + sizeof(pm_constant_t);
    void *memory = calloc(capacity, element_size);
    if (memory == NULL) return false;

    pool->buckets = memory;
    pool->constants = (void *)(((char *)memory) + capacity * sizeof(pm_constant_pool_bucket_t));
    pool->size = 0;
    pool->capacity = capacity;
    return true;
}

/**
 * Return a pointer to the constant indicated by the given constant id.
 */
pm_constant_t *
pm_constant_pool_id_to_constant(const pm_constant_pool_t *pool, pm_constant_id_t constant_id) {
    assert(constant_id > 0 && constant_id <= pool->size);
    return &pool->constants[constant_id - 1];
}

/**
 * Insert a constant into a constant pool and return its index in the pool.
 */
static inline pm_constant_id_t
pm_constant_pool_insert(pm_constant_pool_t *pool, const uint8_t *start, size_t length, pm_constant_pool_bucket_type_t type) {
    if (pool->size >= (pool->capacity / 4 * 3)) {
        if (!pm_constant_pool_resize(pool)) return 0;
    }

    assert(is_power_of_two(pool->capacity));
    const uint32_t mask = pool->capacity - 1;

    uint32_t hash = pm_constant_pool_hash(start, length);
    uint32_t index = hash & mask;
    pm_constant_pool_bucket_t *bucket;

    while (bucket = &pool->buckets[index], bucket->id != 0) {
        // If there is a collision, then we need to check if the content is the
        // same as the content we are trying to insert. If it is, then we can
        // return the id of the existing constant.
        pm_constant_t *constant = &pool->constants[bucket->id - 1];

        if ((constant->length == length) && memcmp(constant->start, start, length) == 0) {
            // Since we have found a match, we need to check if this is
            // attempting to insert a shared or an owned constant. We want to
            // prefer shared constants since they don't require allocations.
            if (type == PM_CONSTANT_POOL_BUCKET_OWNED) {
                // If we're attempting to insert an owned constant and we have
                // an existing constant, then either way we don't want the given
                // memory. Either it's duplicated with the existing constant or
                // it's not necessary because we have a shared version.
                free((void *) start);
            } else if (bucket->type == PM_CONSTANT_POOL_BUCKET_OWNED) {
                // If we're attempting to insert a shared constant and the
                // existing constant is owned, then we can free the owned
                // constant and replace it with the shared constant.
                free((void *) constant->start);
                constant->start = start;
                bucket->type = (unsigned int) (PM_CONSTANT_POOL_BUCKET_DEFAULT & 0x3);
            }

            return bucket->id;
        }

        index = (index + 1) & mask;
    }

    // IDs are allocated starting at 1, since the value 0 denotes a non-existant
    // constant.
    uint32_t id = ++pool->size;
    assert(pool->size < ((uint32_t) (1 << 30)));

    *bucket = (pm_constant_pool_bucket_t) {
        .id = (unsigned int) (id & 0x3fffffff),
        .type = (unsigned int) (type & 0x3),
        .hash = hash
    };

    pool->constants[id - 1] = (pm_constant_t) {
        .start = start,
        .length = length,
    };

    return id;
}

/**
 * Insert a constant into a constant pool. Returns the id of the constant, or 0
 * if any potential calls to resize fail.
 */
pm_constant_id_t
pm_constant_pool_insert_shared(pm_constant_pool_t *pool, const uint8_t *start, size_t length) {
    return pm_constant_pool_insert(pool, start, length, PM_CONSTANT_POOL_BUCKET_DEFAULT);
}

/**
 * Insert a constant into a constant pool from memory that is now owned by the
 * constant pool. Returns the id of the constant, or 0 if any potential calls to
 * resize fail.
 */
pm_constant_id_t
pm_constant_pool_insert_owned(pm_constant_pool_t *pool, const uint8_t *start, size_t length) {
    return pm_constant_pool_insert(pool, start, length, PM_CONSTANT_POOL_BUCKET_OWNED);
}

/**
 * Insert a constant into a constant pool from memory that is constant. Returns
 * the id of the constant, or 0 if any potential calls to resize fail.
 */
pm_constant_id_t
pm_constant_pool_insert_constant(pm_constant_pool_t *pool, const uint8_t *start, size_t length) {
    return pm_constant_pool_insert(pool, start, length, PM_CONSTANT_POOL_BUCKET_CONSTANT);
}

/**
 * Free the memory associated with a constant pool.
 */
void
pm_constant_pool_free(pm_constant_pool_t *pool) {
    // For each constant in the current constant pool, free the contents if the
    // contents are owned.
    for (uint32_t index = 0; index < pool->capacity; index++) {
        pm_constant_pool_bucket_t *bucket = &pool->buckets[index];

        // If an id is set on this constant, then we know we have content here.
        if (bucket->id != 0 && bucket->type == PM_CONSTANT_POOL_BUCKET_OWNED) {
            pm_constant_t *constant = &pool->constants[bucket->id - 1];
            free((void *) constant->start);
        }
    }

    free(pool->buckets);
}
