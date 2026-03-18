/**
 * @file arena.h
 *
 * A bump allocator for the prism parser.
 */
#ifndef PRISM_ARENA_H
#define PRISM_ARENA_H

#include "prism/compiler/exported.h"
#include "prism/compiler/flex_array.h"
#include "prism/compiler/force_inline.h"

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
 * Free all blocks in the arena. After this call, all pointers returned by
 * pm_arena_alloc and pm_arena_zalloc are invalid.
 *
 * @param arena The arena whose held memory should be freed.
 */
PRISM_EXPORTED_FUNCTION void pm_arena_cleanup(pm_arena_t *arena);

#endif
