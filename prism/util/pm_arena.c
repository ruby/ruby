#include "prism/util/pm_arena.h"

/**
 * Compute the block allocation size using offsetof so it is correct regardless
 * of PM_FLEX_ARY_LEN.
 */
#define PM_ARENA_BLOCK_SIZE(data_size) (offsetof(pm_arena_block_t, data) + (data_size))

/** Initial block data size: 8 KB. */
#define PM_ARENA_INITIAL_SIZE 8192

/** Double the block size every this many blocks. */
#define PM_ARENA_GROWTH_INTERVAL 8

/** Maximum block data size: 1 MB. */
#define PM_ARENA_MAX_SIZE (1024 * 1024)

/**
 * Compute the data size for the next block.
 */
static size_t
pm_arena_next_block_size(const pm_arena_t *arena, size_t min_size) {
    size_t size = PM_ARENA_INITIAL_SIZE;

    for (size_t i = PM_ARENA_GROWTH_INTERVAL; i <= arena->block_count; i += PM_ARENA_GROWTH_INTERVAL) {
        if (size < PM_ARENA_MAX_SIZE) size *= 2;
    }

    return size > min_size ? size : min_size;
}

/**
 * Allocate memory from the arena. The returned memory is NOT zeroed. This
 * function is infallible — it aborts on allocation failure.
 */
void *
pm_arena_alloc(pm_arena_t *arena, size_t size, size_t alignment) {
    // Try current block.
    if (arena->current != NULL) {
        size_t used_aligned = (arena->current->used + alignment - 1) & ~(alignment - 1);
        size_t needed = used_aligned + size;

        // Guard against overflow in the alignment or size arithmetic.
        if (used_aligned >= arena->current->used && needed >= used_aligned && needed <= arena->current->capacity) {
            arena->current->used = needed;
            return arena->current->data + used_aligned;
        }
    }

    // Allocate new block via xmalloc — memory is NOT zeroed.
    // New blocks from xmalloc are max-aligned, so data[] starts aligned for
    // any C type. No padding needed at the start.
    size_t block_data_size = pm_arena_next_block_size(arena, size);
    pm_arena_block_t *block = (pm_arena_block_t *) xmalloc(PM_ARENA_BLOCK_SIZE(block_data_size));

    if (block == NULL) {
        fprintf(stderr, "prism: out of memory; aborting\n");
        abort();
    }

    block->capacity = block_data_size;
    block->used = size;
    block->prev = arena->current;
    arena->current = block;
    arena->block_count++;

    return block->data;
}

/**
 * Allocate zero-initialized memory from the arena. This function is infallible
 * — it aborts on allocation failure.
 */
void *
pm_arena_zalloc(pm_arena_t *arena, size_t size, size_t alignment) {
    void *ptr = pm_arena_alloc(arena, size, alignment);
    memset(ptr, 0, size);
    return ptr;
}

/**
 * Allocate memory from the arena and copy the given data into it.
 */
void *
pm_arena_memdup(pm_arena_t *arena, const void *src, size_t size, size_t alignment) {
    void *dst = pm_arena_alloc(arena, size, alignment);
    memcpy(dst, src, size);
    return dst;
}

/**
 * Free all blocks in the arena.
 */
void
pm_arena_free(pm_arena_t *arena) {
    pm_arena_block_t *block = arena->current;

    while (block != NULL) {
        pm_arena_block_t *prev = block->prev;
        xfree_sized(block, PM_ARENA_BLOCK_SIZE(block->capacity));
        block = prev;
    }

    *arena = (pm_arena_t) { 0 };
}
