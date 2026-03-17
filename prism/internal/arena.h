/**
 * @file internal/arena.h
 *
 * A bump allocator for the prism parser.
 */
#ifndef PRISM_INTERNAL_ARENA_H
#define PRISM_INTERNAL_ARENA_H

#include "prism/compiler/exported.h"
#include "prism/compiler/inline.h"

#include "prism/arena.h"

#include <stddef.h>
#include <string.h>

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
