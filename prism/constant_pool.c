#include "prism/internal/constant_pool.h"

#include "prism/compiler/align.h"
#include "prism/compiler/inline.h"
#include "prism/internal/arena.h"

#include <assert.h>
#include <stdbool.h>

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
 * Initialize a list of constant ids with a given capacity.
 */
void
pm_constant_id_list_init_capacity(pm_arena_t *arena, pm_constant_id_list_t *list, size_t capacity) {
    if (capacity) {
        list->ids = (pm_constant_id_t *) pm_arena_zalloc(arena, capacity * sizeof(pm_constant_id_t), PRISM_ALIGNOF(pm_constant_id_t));
    } else {
        list->ids = NULL;
    }

    list->size = 0;
    list->capacity = capacity;
}

/**
 * Append a constant id to a list of constant ids.
 */
void
pm_constant_id_list_append(pm_arena_t *arena, pm_constant_id_list_t *list, pm_constant_id_t id) {
    if (list->size >= list->capacity) {
        size_t new_capacity = list->capacity == 0 ? 8 : list->capacity * 2;
        pm_constant_id_t *new_ids = (pm_constant_id_t *) pm_arena_alloc(arena, sizeof(pm_constant_id_t) * new_capacity, PRISM_ALIGNOF(pm_constant_id_t));

        if (list->size > 0) {
            memcpy(new_ids, list->ids, list->size * sizeof(pm_constant_id_t));
        }

        list->ids = new_ids;
        list->capacity = new_capacity;
    }

    list->ids[list->size++] = id;
}

/**
 * Insert a constant id into a list of constant ids at the specified index.
 */
void
pm_constant_id_list_insert(pm_constant_id_list_t *list, size_t index, pm_constant_id_t id) {
    assert(index < list->capacity);
    assert(list->ids[index] == PM_CONSTANT_ID_UNSET);

    list->ids[index] = id;
    list->size++;
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
 * A multiply-xorshift hash that processes input a word at a time. This is
 * significantly faster than the byte-at-a-time djb2 hash for the short strings
 * typical in Ruby source (~15 bytes average). Each word is mixed into the hash
 * by XOR followed by multiplication by a large odd constant, which spreads
 * entropy across all bits. A final xorshift fold produces the 32-bit result.
 */
static PRISM_INLINE uint32_t
pm_constant_pool_hash(const uint8_t *start, size_t length) {
    // This constant is borrowed from wyhash. It is a 64-bit odd integer with
    // roughly equal 0/1 bits, chosen for good avalanche behavior when used in
    // multiply-xorshift sequences.
    static const uint64_t secret = 0x517cc1b727220a95ULL;
    uint64_t hash = (uint64_t) length;

    if (length <= 8) {
        // Short strings: read first and last 4 bytes (overlapping for len < 8).
        // This covers the majority of Ruby identifiers with a single multiply.
        if (length >= 4) {
            uint32_t a, b;
            memcpy(&a, start, 4);
            memcpy(&b, start + length - 4, 4);
            hash ^= (uint64_t) a | ((uint64_t) b << 32);
        } else if (length > 0) {
            hash ^= (uint64_t) start[0] | ((uint64_t) start[length >> 1] << 8) | ((uint64_t) start[length - 1] << 16);
        }
        hash *= secret;
    } else if (length <= 16) {
        // Medium strings: read first and last 8 bytes (overlapping).
        // Two multiplies instead of the three the loop-based approach needs.
        uint64_t word;
        memcpy(&word, start, 8);
        hash ^= word;
        hash *= secret;
        memcpy(&word, start + length - 8, 8);
        hash ^= word;
        hash *= secret;
    } else {
        const uint8_t *ptr = start;
        size_t remaining = length;

        while (remaining >= 8) {
            uint64_t word;
            memcpy(&word, ptr, 8);
            hash ^= word;
            hash *= secret;
            ptr += 8;
            remaining -= 8;
        }

        if (remaining > 0) {
            // Read the last 8 bytes (overlapping with already-processed data).
            uint64_t word;
            memcpy(&word, start + length - 8, 8);
            hash ^= word;
            hash *= secret;
        }
    }

    hash ^= hash >> 32;
    return (uint32_t) hash;
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
static PRISM_INLINE void
pm_constant_pool_resize(pm_arena_t *arena, pm_constant_pool_t *pool) {
    assert(is_power_of_two(pool->capacity));

    uint32_t next_capacity = pool->capacity * 2;
    const uint32_t mask = next_capacity - 1;

    pm_constant_pool_bucket_t *next_buckets = (pm_constant_pool_bucket_t *) pm_arena_zalloc(arena, next_capacity * sizeof(pm_constant_pool_bucket_t), PRISM_ALIGNOF(pm_constant_pool_bucket_t));
    pm_constant_t *next_constants = (pm_constant_t *) pm_arena_alloc(arena, next_capacity * sizeof(pm_constant_t), PRISM_ALIGNOF(pm_constant_t));

    // For each bucket in the current constant pool, find the index in the
    // next constant pool, and insert it.
    for (uint32_t index = 0; index < pool->capacity; index++) {
        pm_constant_pool_bucket_t *bucket = &pool->buckets[index];

        // If an id is set on this constant, then we know we have content here.
        // In this case we need to insert it into the next constant pool.
        if (bucket->id != PM_CONSTANT_ID_UNSET) {
            uint32_t next_index = bucket->hash & mask;

            // This implements linear scanning to find the next available slot
            // in case this index is already taken. We don't need to bother
            // comparing the values since we know that the hash is unique.
            while (next_buckets[next_index].id != PM_CONSTANT_ID_UNSET) {
                next_index = (next_index + 1) & mask;
            }

            // Here we copy over the entire bucket, which includes the id so
            // that they are consistent between resizes.
            next_buckets[next_index] = *bucket;
        }
    }

    // The constants are stable with respect to hash table resizes.
    memcpy(next_constants, pool->constants, pool->size * sizeof(pm_constant_t));

    pool->constants = next_constants;
    pool->buckets = next_buckets;
    pool->capacity = next_capacity;
}

/**
 * Initialize a new constant pool with a given capacity.
 */
void
pm_constant_pool_init(pm_arena_t *arena, pm_constant_pool_t *pool, uint32_t capacity) {
    capacity = next_power_of_two(capacity);

    pool->buckets = (pm_constant_pool_bucket_t *) pm_arena_zalloc(arena, capacity * sizeof(pm_constant_pool_bucket_t), PRISM_ALIGNOF(pm_constant_pool_bucket_t));
    pool->constants = (pm_constant_t *) pm_arena_alloc(arena, capacity * sizeof(pm_constant_t), PRISM_ALIGNOF(pm_constant_t));
    pool->size = 0;
    pool->capacity = capacity;
}

/**
 * Return a pointer to the constant indicated by the given constant id.
 */
pm_constant_t *
pm_constant_pool_id_to_constant(const pm_constant_pool_t *pool, pm_constant_id_t constant_id) {
    assert(constant_id != PM_CONSTANT_ID_UNSET && constant_id <= pool->size);
    return &pool->constants[constant_id - 1];
}

/**
 * Find a constant in a constant pool. Returns the id of the constant, or 0 if
 * the constant is not found.
 */
pm_constant_id_t
pm_constant_pool_find(const pm_constant_pool_t *pool, const uint8_t *start, size_t length) {
    assert(is_power_of_two(pool->capacity));
    const uint32_t mask = pool->capacity - 1;

    uint32_t hash = pm_constant_pool_hash(start, length);
    uint32_t index = hash & mask;
    pm_constant_pool_bucket_t *bucket;

    while (bucket = &pool->buckets[index], bucket->id != PM_CONSTANT_ID_UNSET) {
        if ((bucket->length == length) && memcmp(bucket->start, start, length) == 0) {
            return bucket->id;
        }

        index = (index + 1) & mask;
    }

    return PM_CONSTANT_ID_UNSET;
}

/**
 * Insert a constant into a constant pool and return its index in the pool.
 */
static PRISM_INLINE pm_constant_id_t
pm_constant_pool_insert(pm_arena_t *arena, pm_constant_pool_t *pool, const uint8_t *start, size_t length, pm_constant_pool_bucket_type_t type) {
    if (pool->size >= (pool->capacity / 4 * 3)) {
        pm_constant_pool_resize(arena, pool);
    }

    assert(is_power_of_two(pool->capacity));
    const uint32_t mask = pool->capacity - 1;

    uint32_t hash = pm_constant_pool_hash(start, length);
    uint32_t index = hash & mask;
    pm_constant_pool_bucket_t *bucket;

    while (bucket = &pool->buckets[index], bucket->id != PM_CONSTANT_ID_UNSET) {
        // If there is a collision, then we need to check if the content is the
        // same as the content we are trying to insert. If it is, then we can
        // return the id of the existing constant.
        if ((bucket->length == length) && memcmp(bucket->start, start, length) == 0) {
            // Since we have found a match, we need to check if this is
            // attempting to insert a shared or an owned constant. We want to
            // prefer shared constants since they don't require allocations.
            if (type != PM_CONSTANT_POOL_BUCKET_OWNED && bucket->type == PM_CONSTANT_POOL_BUCKET_OWNED) {
                // If we're attempting to insert a shared constant and the
                // existing constant is owned, then we can replace it with the
                // shared constant to prefer non-owned references.
                bucket->start = start;
                bucket->type = (unsigned int) (type & 0x3);
                pool->constants[bucket->id - 1].start = start;
            }

            return bucket->id;
        }

        index = (index + 1) & mask;
    }

    // IDs are allocated starting at 1, since the value 0 denotes a non-existent
    // constant.
    uint32_t id = ++pool->size;
    assert(pool->size < ((uint32_t) (1 << 30)));

    *bucket = (pm_constant_pool_bucket_t) {
        .id = (unsigned int) (id & 0x3fffffff),
        .type = (unsigned int) (type & 0x3),
        .hash = hash,
        .start = start,
        .length = length
    };

    pool->constants[id - 1] = (pm_constant_t) {
        .start = start,
        .length = length,
    };

    return id;
}

/**
 * Insert a constant into a constant pool. Returns the id of the constant, or
 * PM_CONSTANT_ID_UNSET if any potential calls to resize fail.
 */
pm_constant_id_t
pm_constant_pool_insert_shared(pm_arena_t *arena, pm_constant_pool_t *pool, const uint8_t *start, size_t length) {
    return pm_constant_pool_insert(arena, pool, start, length, PM_CONSTANT_POOL_BUCKET_DEFAULT);
}

/**
 * Insert a constant into a constant pool from memory that is now owned by the
 * constant pool. Returns the id of the constant, or PM_CONSTANT_ID_UNSET if any
 * potential calls to resize fail.
 */
pm_constant_id_t
pm_constant_pool_insert_owned(pm_arena_t *arena, pm_constant_pool_t *pool, uint8_t *start, size_t length) {
    return pm_constant_pool_insert(arena, pool, start, length, PM_CONSTANT_POOL_BUCKET_OWNED);
}

/**
 * Insert a constant into a constant pool from memory that is constant. Returns
 * the id of the constant, or PM_CONSTANT_ID_UNSET if any potential calls to
 * resize fail.
 */
pm_constant_id_t
pm_constant_pool_insert_constant(pm_arena_t *arena, pm_constant_pool_t *pool, const uint8_t *start, size_t length) {
    return pm_constant_pool_insert(arena, pool, start, length, PM_CONSTANT_POOL_BUCKET_CONSTANT);
}

/**
 * Return a raw pointer to the start of a constant.
 */
const uint8_t *
pm_constant_start(const pm_constant_t *constant) {
    return constant->start;
}

/**
 * Return the length of a constant.
 */
size_t pm_constant_length(const pm_constant_t *constant) {
    return constant->length;
}
