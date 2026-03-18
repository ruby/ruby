/**
 * @file internal/arena.h
 *
 * A bump allocator for the prism parser.
 */
#ifndef PRISM_INTERNAL_ARENA_H
#define PRISM_INTERNAL_ARENA_H

#include "prism/compiler/exported.h"
#include "prism/compiler/flex_array.h"
#include "prism/compiler/force_inline.h"
#include "prism/compiler/inline.h"

#include "prism/arena.h"

#include <stddef.h>
#include <string.h>

/**
 * A single block of memory in the arena. Blocks are linked via prev pointers so
 * they can be freed by walking the chain.
 */
typedef struct pm_arena_block {
    /** The previous block in the chain (for freeing). */
    struct pm_arena_block *prev;

    /** The total usable bytes in data[]. */
    size_t capacity;

    /** The number of bytes consumed so far. */
    size_t used;

    /** The block's data. */
    char data[PM_FLEX_ARRAY_LENGTH];
} pm_arena_block_t;

/**
 * A bump allocator. Allocations are made by bumping a pointer within the
 * current block. When a block is full, a new block is allocated and linked to
 * the previous one. All blocks are freed at once by walking the chain.
 */
struct pm_arena_t {
    /** The active block (allocate from here). */
    pm_arena_block_t *current;

    /** The number of blocks allocated. */
    size_t block_count;
};

/**
 * Free all blocks in the arena. After this call, all pointers returned by
 * pm_arena_alloc and pm_arena_zalloc are invalid.
 *
 * @param arena The arena whose held memory should be freed.
 */
void pm_arena_cleanup(pm_arena_t *arena);

/**
 * Ensure the arena has at least `capacity` bytes available in its current
 * block, allocating a new block if necessary. This allows callers to
 * pre-size the arena to avoid repeated small block allocations.
 *
 * @param arena The arena to pre-size.
 * @param capacity The minimum number of bytes to ensure are available.
 */
void pm_arena_reserve(pm_arena_t *arena, size_t capacity);

/**
 * Slow path for pm_arena_alloc: allocate a new block and return a pointer to
 * the first `size` bytes. Do not call directly — use pm_arena_alloc instead.
 *
 * @param arena The arena to allocate from.
 * @param size The number of bytes to allocate.
 * @returns A pointer to the allocated memory.
 */
void * pm_arena_alloc_slow(pm_arena_t *arena, size_t size);

/**
 * Allocate memory from the arena. The returned memory is NOT zeroed. This
 * function is infallible — it aborts on allocation failure.
 *
 * The fast path (bump pointer within the current block) is inlined at each
 * call site. The slow path (new block allocation) is out-of-line.
 *
 * @param arena The arena to allocate from.
 * @param size The number of bytes to allocate.
 * @param alignment The required alignment (must be a power of 2).
 * @returns A pointer to the allocated memory.
 */
static PRISM_FORCE_INLINE void *
pm_arena_alloc(pm_arena_t *arena, size_t size, size_t alignment) {
    if (arena->current != NULL) {
        size_t used_aligned = (arena->current->used + alignment - 1) & ~(alignment - 1);
        size_t needed = used_aligned + size;

        if (used_aligned >= arena->current->used && needed >= used_aligned && needed <= arena->current->capacity) {
            arena->current->used = needed;
            return arena->current->data + used_aligned;
        }
    }

    return pm_arena_alloc_slow(arena, size);
}

/**
 * Allocate zero-initialized memory from the arena. This function is infallible
 * — it aborts on allocation failure.
 *
 * @param arena The arena to allocate from.
 * @param size The number of bytes to allocate.
 * @param alignment The required alignment (must be a power of 2).
 * @returns A pointer to the allocated, zero-initialized memory.
 */
static PRISM_INLINE void *
pm_arena_zalloc(pm_arena_t *arena, size_t size, size_t alignment) {
    void *ptr = pm_arena_alloc(arena, size, alignment);
    memset(ptr, 0, size);
    return ptr;
}

/**
 * Allocate memory from the arena and copy the given data into it. This is a
 * convenience wrapper around pm_arena_alloc + memcpy.
 *
 * @param arena The arena to allocate from.
 * @param src The source data to copy.
 * @param size The number of bytes to allocate and copy.
 * @param alignment The required alignment (must be a power of 2).
 * @returns A pointer to the allocated copy.
 */
static PRISM_INLINE void *
pm_arena_memdup(pm_arena_t *arena, const void *src, size_t size, size_t alignment) {
    void *dst = pm_arena_alloc(arena, size, alignment);
    memcpy(dst, src, size);
    return dst;
}

#endif
