#ifndef PRISM_INTERNAL_ARENA_H
#define PRISM_INTERNAL_ARENA_H

#include "prism/compiler/exported.h"
#include "prism/compiler/flex_array.h"
#include "prism/compiler/force_inline.h"
#include "prism/compiler/inline.h"

#include "prism/arena.h"

#include <stddef.h>
#include <string.h>

/*
 * A single block of memory in the arena. Blocks are linked via prev pointers so
 * they can be freed by walking the chain.
 */
typedef struct pm_arena_block {
    /* The previous block in the chain (for freeing). */
    struct pm_arena_block *prev;

    /* The total usable bytes in data[]. */
    size_t capacity;

    /* The number of bytes consumed so far. */
    size_t used;

    /* The block's data. */
    char data[PM_FLEX_ARRAY_LENGTH];
} pm_arena_block_t;

/*
 * A bump allocator. Allocations are made by bumping a pointer within the
 * current block. When a block is full, a new block is allocated and linked to
 * the previous one. All blocks are freed at once by walking the chain.
 */
struct pm_arena_t {
    /* The active block (allocate from here). */
    pm_arena_block_t *current;

    /* The number of blocks allocated. */
    size_t block_count;
};

/*
 * Free all blocks in the arena. After this call, all pointers returned by
 * pm_arena_alloc and pm_arena_zalloc are invalid.
 */
void pm_arena_cleanup(pm_arena_t *arena);

/*
 * Ensure the arena has at least `capacity` bytes available in its current
 * block, allocating a new block if necessary. This allows callers to
 * pre-size the arena to avoid repeated small block allocations.
 */
void pm_arena_reserve(pm_arena_t *arena, size_t capacity);

/*
 * Slow path for pm_arena_alloc: allocate a new block and return a pointer to
 * the first `size` bytes. Do not call directly — use pm_arena_alloc instead.
 */
void * pm_arena_alloc_slow(pm_arena_t *arena, size_t size);

/*
 * Allocate memory from the arena. The returned memory is NOT zeroed. This
 * function is infallible — it aborts on allocation failure.
 *
 * The fast path (bump pointer within the current block) is inlined at each
 * call site. The slow path (new block allocation) is out-of-line.
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

/*
 * Allocate zero-initialized memory from the arena. This function is infallible
 * — it aborts on allocation failure.
 */
static PRISM_INLINE void *
pm_arena_zalloc(pm_arena_t *arena, size_t size, size_t alignment) {
    void *ptr = pm_arena_alloc(arena, size, alignment);
    memset(ptr, 0, size);
    return ptr;
}

/*
 * Allocate memory from the arena and copy the given data into it. This is a
 * convenience wrapper around pm_arena_alloc + memcpy.
 */
static PRISM_INLINE void *
pm_arena_memdup(pm_arena_t *arena, const void *src, size_t size, size_t alignment) {
    void *dst = pm_arena_alloc(arena, size, alignment);
    memcpy(dst, src, size);
    return dst;
}

/*
 * Resize an allocation from the arena from old_size to new_size bytes and
 * return where it now lives. The sizes are in the same order as xrealloc_sized.
 * An old_size of 0 means there is no allocation yet, so ptr may be NULL and a
 * new allocation is returned.
 *
 * The most recent allocation in the current block ends exactly where the
 * block's used bytes do, so it is resized in place when the block has room. Any
 * other allocation stays where it is when it shrinks, and is copied into a new
 * allocation when it grows, leaving the old one behind in the arena.
 */
static PRISM_INLINE void *
pm_arena_realloc(pm_arena_t *arena, void *ptr, size_t new_size, size_t old_size, size_t alignment) {
    void *result;

    if (old_size == 0) {
        result = pm_arena_alloc(arena, new_size, alignment);
    } else {
        pm_arena_block_t *block = arena->current;

        if (block != NULL && (char *) ptr + old_size == block->data + block->used) {
            size_t start = block->used - old_size;

            if (new_size <= block->capacity - start) {
                block->used = start + new_size;
                return ptr;
            }
        }

        if (new_size <= old_size) return ptr;

        result = pm_arena_alloc(arena, new_size, alignment);
        memcpy(result, ptr, old_size);
    }

    return result;
}

#endif
