/**
 * @file arena.h
 *
 * A bump allocator for the prism parser.
 */
#ifndef PRISM_ARENA_H
#define PRISM_ARENA_H

#include "prism/exported.h"
#include "prism/flex_array.h"
#include "prism/force_inline.h"

#include <stddef.h>

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
typedef struct {
    /** The active block (allocate from here). */
    pm_arena_block_t *current;

    /** The number of blocks allocated. */
    size_t block_count;
} pm_arena_t;

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
 * Free all blocks in the arena. After this call, all pointers returned by
 * pm_arena_alloc and pm_arena_zalloc are invalid.
 *
 * @param arena The arena to free.
 */
PRISM_EXPORTED_FUNCTION void pm_arena_free(pm_arena_t *arena);

#endif
