/**
 * @file pm_arena.h
 *
 * A bump allocator for the prism parser.
 */
#ifndef PRISM_ARENA_H
#define PRISM_ARENA_H

#include "prism/defines.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
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
    char data[PM_FLEX_ARY_LEN];
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
 * Allocate memory from the arena. The returned memory is NOT zeroed. This
 * function is infallible — it aborts on allocation failure.
 *
 * @param arena The arena to allocate from.
 * @param size The number of bytes to allocate.
 * @param alignment The required alignment (must be a power of 2).
 * @returns A pointer to the allocated memory.
 */
void * pm_arena_alloc(pm_arena_t *arena, size_t size, size_t alignment);

/**
 * Allocate zero-initialized memory from the arena. This function is infallible
 * — it aborts on allocation failure.
 *
 * @param arena The arena to allocate from.
 * @param size The number of bytes to allocate.
 * @param alignment The required alignment (must be a power of 2).
 * @returns A pointer to the allocated, zero-initialized memory.
 */
void * pm_arena_zalloc(pm_arena_t *arena, size_t size, size_t alignment);

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
void * pm_arena_memdup(pm_arena_t *arena, const void *src, size_t size, size_t alignment);

/**
 * Free all blocks in the arena. After this call, all pointers returned by
 * pm_arena_alloc and pm_arena_zalloc are invalid.
 *
 * @param arena The arena to free.
 */
PRISM_EXPORTED_FUNCTION void pm_arena_free(pm_arena_t *arena);

#endif
