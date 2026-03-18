/**
 * @file arena.h
 *
 * A bump allocator for the prism parser.
 */
#ifndef PRISM_ARENA_H
#define PRISM_ARENA_H

#include "prism/compiler/exported.h"

#include <stddef.h>

/**
 * An opaque pointer to an arena that is used for allocations.
 */
typedef struct pm_arena_t pm_arena_t;

/**
 * Returns a newly allocated and initialized arena. If the arena cannot be
 * allocated, this function aborts the process.
 *
 * @return A pointer to the newly allocated arena. It is the responsibility of
 *     the caller to free the arena using pm_arena_free when it is no longer
 *     needed.
 */
PRISM_EXPORTED_FUNCTION pm_arena_t * pm_arena_new(void);

/**
 * Frees both the held memory and the arena itself.
 *
 * @param arena The arena to free.
 */
PRISM_EXPORTED_FUNCTION void pm_arena_free(pm_arena_t *arena);

#endif
