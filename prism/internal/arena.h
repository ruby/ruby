#ifndef PRISM_INTERNAL_ARENA_H
#define PRISM_INTERNAL_ARENA_H

#include "prism/compiler/align.h"
#include "prism/compiler/branch.h"
#include "prism/compiler/flex_array.h"
#include "prism/compiler/force_inline.h"
#include "prism/compiler/inline.h"
#include "prism/compiler/noreturn.h"

#include "prism/arena.h"

#include <stddef.h>
#include <stdint.h>
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
 * the previous one. An allocation too large to share a block gets one of its
 * own on a separate chain, so it does not displace the current block. All
 * blocks are freed at once by walking both chains.
 */
struct pm_arena_t {
    /* The active block (allocate from here). */
    pm_arena_block_t *current;

    /* Blocks that each hold a single large allocation, never bumped into. */
    pm_arena_block_t *large;

    /*
     * The number of blocks allocated on the current chain, which sets the size
     * of the next one.
     */
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
 * Slow path for pm_arena_alloc: allocate a new block, either the next current
 * block or a block of its own for a large allocation, and return a pointer to
 * the first `size` bytes. Do not call directly — use pm_arena_alloc instead.
 */
void * pm_arena_alloc_slow(pm_arena_t *arena, size_t size);

/*
 * Report an array allocation whose total size does not fit in a size_t. This
 * goes through PRISM_OOM like any other allocation failure, and lives out of
 * line so this header does not need the headers PRISM_OOM depends on.
 */
PRISM_NORETURN void pm_arena_alloc_overflow(void);

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
 * Allocate memory from the arena whose address is aligned to the given power of
 * two. Unlike pm_arena_alloc, the alignment may exceed the alignment of the
 * arena's blocks, at the cost of a slower path that is not inlined.
 */
void * pm_arena_alloc_aligned(pm_arena_t *arena, size_t size, size_t alignment);

/*
 * Allocate memory for a single element of type T_ from the arena.
 */
#define PM_ARENA_ALLOC(arena_, T_) \
    ((T_ *) pm_arena_alloc(arena_, sizeof(T_), PRISM_ALIGNOF(T_)))

/*
 * Allocate an array of elements from the arena. The returned memory is NOT
 * zeroed. This function is infallible — it aborts on allocation failure.
 */
static PRISM_INLINE void *
pm_arena_alloc_array(pm_arena_t *arena, size_t count, size_t size, size_t alignment) {
    if (PRISM_UNLIKELY(count > SIZE_MAX / size)) pm_arena_alloc_overflow();
    return pm_arena_alloc(arena, count * size, alignment);
}

/*
 * Allocate an array of elements of type T_ from the arena.
 */
#define PM_ARENA_ALLOC_ARRAY(arena_, T_, count_) \
    ((T_ *) pm_arena_alloc_array(arena_, count_, sizeof(T_), PRISM_ALIGNOF(T_)))

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
 * Allocate a zero-initialized element of type T_ from the arena.
 */
#define PM_ARENA_ZALLOC(arena_, T_) \
    ((T_ *) pm_arena_zalloc(arena_, sizeof(T_), PRISM_ALIGNOF(T_)))

/*
 * Allocate a zero-initialized array of elements from the arena. This function
 * is infallible — it aborts on allocation failure.
 */
static PRISM_INLINE void *
pm_arena_zalloc_array(pm_arena_t *arena, size_t count, size_t size, size_t alignment) {
    void *ptr = pm_arena_alloc_array(arena, count, size, alignment);
    memset(ptr, 0, count * size);
    return ptr;
}

/*
 * Allocate a zero-initialized array of elements of type T_ from the arena.
 */
#define PM_ARENA_ZALLOC_ARRAY(arena_, T_, count_) \
    ((T_ *) pm_arena_zalloc_array(arena_, count_, sizeof(T_), PRISM_ALIGNOF(T_)))

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

/*
 * Reallocate an element of type T_ from the arena.
 */
#define PM_ARENA_REALLOC(arena_, ptr_, new_size_, old_size_, T_) \
    ((T_ *) pm_arena_realloc(arena_, ptr_, new_size_, old_size_, PRISM_ALIGNOF(T_)))

#endif
