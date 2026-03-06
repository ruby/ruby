/**
 * @file debug_allocator.h
 *
 * Decorate allocation function to ensure sizes are correct.
 */
#ifndef PRISM_DEBUG_ALLOCATOR_H
#define PRISM_DEBUG_ALLOCATOR_H

#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static inline void *
pm_debug_malloc(size_t size)
{
    size_t *memory = xmalloc(size + sizeof(size_t));
    memory[0] = size;
    return memory + 1;
}

static inline void *
pm_debug_calloc(size_t nmemb, size_t size)
{
    size_t total_size = nmemb * size;
    void *ptr = pm_debug_malloc(total_size);
    memset(ptr, 0, total_size);
    return ptr;
}

static inline void *
pm_debug_realloc(void *ptr, size_t size)
{
    if (ptr == NULL) {
        return pm_debug_malloc(size);
    }

    size_t *memory = (size_t *)ptr;
    void *raw_memory = memory - 1;
    memory = (size_t *)xrealloc(raw_memory, size + sizeof(size_t));
    memory[0] = size;
    return memory + 1;
}

static inline void
pm_debug_free(void *ptr)
{
    if (ptr != NULL) {
        size_t *memory = (size_t *)ptr;
        xfree(memory - 1);
    }
}

static inline void
pm_debug_free_sized(void *ptr, size_t old_size)
{
    if (ptr != NULL) {
        size_t *memory = (size_t *)ptr;
        if (old_size != memory[-1]) {
            fprintf(stderr, "[BUG] buffer %p was allocated with size %lu but freed with size %lu\n", ptr, memory[-1], old_size);
            abort();
        }
        xfree_sized(memory - 1, old_size + sizeof(size_t));
    }
}

static inline void *
pm_debug_realloc_sized(void *ptr, size_t size, size_t old_size)
{
    if (ptr == NULL) {
        if (old_size != 0) {
            fprintf(stderr, "[BUG] realloc_sized called with NULL pointer and old size %lu\n", old_size);
            abort();
        }
        return pm_debug_malloc(size);
    }

    size_t *memory = (size_t *)ptr;
    if (old_size != memory[-1]) {
        fprintf(stderr, "[BUG] buffer %p was allocated with size %lu but realloced with size %lu\n", ptr, memory[-1], old_size);
        abort();
    }
    return pm_debug_realloc(ptr, size);
}

#undef xmalloc
#undef xrealloc
#undef xcalloc
#undef xfree
#undef xrealloc_sized
#undef xfree_sized

#define xmalloc          pm_debug_malloc
#define xrealloc         pm_debug_realloc
#define xcalloc          pm_debug_calloc
#define xfree            pm_debug_free
#define xrealloc_sized   pm_debug_realloc_sized
#define xfree_sized      pm_debug_free_sized

#endif
