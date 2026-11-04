#ifndef PRISM_INTERNAL_NODE_H
#define PRISM_INTERNAL_NODE_H

#include "prism/node.h"

#include "prism/compiler/force_inline.h"

#include "prism/arena.h"

#include <stddef.h>
#include <stdint.h>

/* The offset of the start of the given location. */
#define PM_LOCATION_START(location_) ((location_)->start)

/* The offset just past the end of the given location. */
#define PM_LOCATION_END(location_) ((location_)->start + (location_)->length)

/* Return the span covering two initialized locations. Read both endpoints
 * before changing either field, so moving the start preserves the old end.
 * An unset location must be initialized separately from the first child. */
static PRISM_FORCE_INLINE pm_location_t
pm_location_join(pm_location_t left, pm_location_t right) {
    uint32_t start = left.start < right.start ? left.start : right.start;
    uint32_t left_end = PM_LOCATION_END(&left);
    uint32_t right_end = PM_LOCATION_END(&right);
    uint32_t end = left_end > right_end ? left_end : right_end;
    pm_location_t location = { .start = start, .length = end - start };
    return location;
}

/*
 * Slow path for pm_node_list_append_inline: grow the list and append the node.
 * Do not call directly — use pm_node_list_append_inline instead.
 */
void pm_node_list_append_slow(pm_arena_t *arena, pm_node_list_t *list, pm_node_t *node);

/*
 * Append a new node onto the end of the node list, handling the common case
 * inline and growing the list through pm_node_list_append_slow. This is the
 * version for prism's own code; others call the exported pm_node_list_append.
 */
static PRISM_FORCE_INLINE void
pm_node_list_append_inline(pm_arena_t *arena, pm_node_list_t *list, pm_node_t *node) {
    if (list->size < list->capacity) {
        list->nodes[list->size++] = node;
    } else {
        pm_node_list_append_slow(arena, list, node);
    }
}

/* Prepend a new node onto the beginning of the node list. */
void pm_node_list_prepend(pm_arena_t *arena, pm_node_list_t *list, pm_node_t *node);

/* Concatenate the given node list onto the end of the other node list. */
void pm_node_list_concat(pm_arena_t *arena, pm_node_list_t *list, pm_node_list_t *other);

/*
 * A fixed-size piece of a node list that is still being built. It is exactly
 * eight pointers wide, so its size is a power of two, and every chunk is
 * aligned to that size. The link comes first, so a cursor just past the last
 * slot has zero low bits, the same as NULL. One mask test then tells an append
 * that the list needs a new chunk, whether the list is empty or its last chunk
 * is full.
 */
typedef struct pm_node_chunk {
    /* The previous chunk of the same list, or the next chunk on the freelist. */
    struct pm_node_chunk *prev;

    /* The nodes held by this chunk, in order. */
    pm_node_t *slots[7];
} pm_node_chunk_t;

/* The size of a chunk, which is also its alignment. */
#define PM_NODE_CHUNK_SIZE sizeof(pm_node_chunk_t)

/* The low bits of an address that give its offset within a chunk. */
#define PM_NODE_CHUNK_MASK ((uintptr_t) (PM_NODE_CHUNK_SIZE - 1))

/* The number of nodes that fit in a chunk. */
#define PM_NODE_CHUNK_SLOTS (sizeof(((pm_node_chunk_t *) 0)->slots) / sizeof(pm_node_t *))

/* The chunk that contains the given address. */
#define PM_NODE_CHUNK_OF(pointer_) ((pm_node_chunk_t *) ((uintptr_t) (pointer_) & ~PM_NODE_CHUNK_MASK))

/* The number of chunks carved out of the arena at once. */
#define PM_NODE_CHUNK_BATCH 32

/*
 * The source of chunks for open node lists. Chunks are reused through the
 * freelist, and new ones come from a batch that has been carved out of the
 * arena but not yet handed out. They are never freed individually; they are
 * all released together when the arena is cleaned up.
 */
typedef struct {
    /* Chunks returned by finalized lists, linked through prev. */
    pm_node_chunk_t *free;

    /* The next chunk in the current batch that has not been handed out. */
    pm_node_chunk_t *next;

    /* One past the last chunk in the current batch. */
    pm_node_chunk_t *end;

    /* The arena that batches are carved from. */
    pm_arena_t *arena;
} pm_node_chunks_t;

/*
 * Slow path for pm_node_list_open_append: link a new chunk onto the end of the
 * list and append the node to it. Do not call directly — use
 * pm_node_list_open_append instead.
 */
void pm_node_list_open_append_slow(pm_node_chunks_t *chunks, pm_node_list_t *list, pm_node_t *node);

/*
 * Append a node onto the end of an open list. While a list is open, its nodes
 * field is a cursor to the next free slot of its last chunk, or NULL when the
 * list is empty. A zeroed list is an empty open list.
 */
static PRISM_FORCE_INLINE void
pm_node_list_open_append(pm_node_chunks_t *chunks, pm_node_list_t *list, pm_node_t *node) {
    if (((uintptr_t) list->nodes & PM_NODE_CHUNK_MASK) != 0) {
        *list->nodes++ = node;
        list->size++;
    } else {
        pm_node_list_open_append_slow(chunks, list, node);
    }
}

/*
 * Copy an open list into an array of exactly its size allocated from the given
 * arena, and return its chunks to the freelist. Afterward the list holds that
 * array, and it must not be appended to through pm_node_list_open_append or
 * finalized again.
 */
void pm_node_list_finalize(pm_node_chunks_t *chunks, pm_arena_t *arena, pm_node_list_t *list);

#endif
