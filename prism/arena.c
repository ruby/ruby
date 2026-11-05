#include "prism/internal/arena.h"

#include "prism/internal/allocator.h"
#include "prism/internal/assert.h"
#include "prism/internal/oom.h"

#include <stdlib.h>

/**
 * Compute the block allocation size using offsetof so it is correct regardless
 * of PM_FLEX_ARRAY_LENGTH.
 */
#define PM_ARENA_BLOCK_SIZE(data_size) (offsetof(pm_arena_block_t, data) + (data_size))

/**
 * Initial block data size: 8 KB. An embedder on a small heap can define a
 * smaller one; a parse of a short program then takes blocks of that size.
 */
#ifndef PM_ARENA_INITIAL_SIZE
#define PM_ARENA_INITIAL_SIZE 8192
#endif

/** Double the block size every this many blocks. */
#define PM_ARENA_GROWTH_INTERVAL 8

/** Maximum block data size: 1 MB. */
#define PM_ARENA_MAX_SIZE (1024 * 1024)

/**
 * An allocation that does not fit in the current block and is larger than this
 * fraction of the next block gets a block of its own. The current block keeps
 * its free space for the allocations after it, so a block is only given up
 * when a small allocation does not fit, with less than that much left unused.
 */
#define PM_ARENA_LARGE_DIVISOR 2

/**
 * Compute the data size for the next block.
 */
static size_t
pm_arena_next_block_size(const pm_arena_t *arena) {
    size_t size = PM_ARENA_INITIAL_SIZE;

    for (size_t exp = PM_ARENA_GROWTH_INTERVAL; exp <= arena->block_count; exp += PM_ARENA_GROWTH_INTERVAL) {
        if (size < PM_ARENA_MAX_SIZE) size *= 2;
    }

    return size;
}

/**
 * Allocate a block with the given data capacity and initial usage, linked to
 * the given previous block. Aborts on allocation failure.
 */
static pm_arena_block_t *
pm_arena_block_alloc(pm_arena_block_t *prev, size_t data_size, size_t initial_used) {
    PRISM_ASSERT(initial_used <= data_size);
    pm_arena_block_t *block = (pm_arena_block_t *) xmalloc(PM_ARENA_BLOCK_SIZE(data_size));
    if (block == NULL) PRISM_OOM();

    block->capacity = data_size;
    block->used = initial_used;
    block->prev = prev;

    return block;
}

/**
 * Allocate a new block with the given data capacity and initial usage, make it
 * the current block, and return it.
 */
static pm_arena_block_t *
pm_arena_block_new(pm_arena_t *arena, size_t data_size, size_t initial_used) {
    pm_arena_block_t *block = pm_arena_block_alloc(arena->current, data_size, initial_used);
    arena->current = block;
    arena->block_count++;
    return block;
}

/**
 * Free every block in a chain linked through prev.
 */
static void
pm_arena_blocks_free(pm_arena_block_t *block) {
    while (block != NULL) {
        pm_arena_block_t *prev = block->prev;
        xfree_sized(block, PM_ARENA_BLOCK_SIZE(block->capacity));
        block = prev;
    }
}

/**
 * Ensure the arena has at least `capacity` bytes available in its current
 * block, allocating a new block if necessary. This allows callers to
 * pre-size the arena to avoid repeated small block allocations.
 */
void
pm_arena_reserve(pm_arena_t *arena, size_t capacity) {
    if (capacity <= PM_ARENA_INITIAL_SIZE) return;
    if (arena->current != NULL && (arena->current->capacity - arena->current->used) >= capacity) return;
    pm_arena_block_new(arena, capacity, 0);
}

/**
 * Slow path for pm_arena_alloc: allocate a new block and return a pointer to
 * the first `size` bytes. Called when the current block has insufficient space.
 * A large allocation goes in a block of exactly its size on the large list,
 * which leaves the current block in place.
 */
void *
pm_arena_alloc_slow(pm_arena_t *arena, size_t size) {
    size_t block_data_size = pm_arena_next_block_size(arena);

    if (size > block_data_size / PM_ARENA_LARGE_DIVISOR) {
        arena->large = pm_arena_block_alloc(arena->large, size, size);
        return arena->large->data;
    }

    pm_arena_block_t *block = pm_arena_block_new(arena, block_data_size, size);
    return block->data;
}

/**
 * Returns a newly allocated and initialized arena.
 */
pm_arena_t *
pm_arena_new(void) {
    pm_arena_t *arena = (pm_arena_t *) xcalloc(1, sizeof(pm_arena_t));
    if (arena == NULL) PRISM_OOM();
    return arena;
}

/**
 * Free all blocks in the arena.
 */
void
pm_arena_cleanup(pm_arena_t *arena) {
    pm_arena_blocks_free(arena->current);
    pm_arena_blocks_free(arena->large);
    *arena = (pm_arena_t) { 0 };
}

/**
 * Frees both the held memory and the arena itself.
 */
void
pm_arena_free(pm_arena_t *arena) {
    pm_arena_cleanup(arena);
    xfree_sized(arena, sizeof(pm_arena_t));
}
