#ifndef PRISM_INTERNAL_NODE_H
#define PRISM_INTERNAL_NODE_H

#include "prism/node.h"

#include "prism/compiler/force_inline.h"
#include "prism/compiler/inline.h"

#include "prism/arena.h"
#include "prism/internal/assert.h"

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
 * A growable list of nodes for bookkeeping that never becomes part of the tree,
 * such as the block exits and implicit parameters that are tracked while
 * parsing. These lists are read, truncated, and edited in the middle while
 * they are still being built, so unlike node lists they keep a capacity and
 * grow by doubling.
 */
typedef struct {
    /* The number of nodes in the list. */
    uint32_t size;

    /* The number of nodes that fit in the list's array. */
    uint32_t capacity;

    /* The nodes in the list. */
    pm_node_t **nodes;
} pm_scratch_node_list_t;

/*
 * Slow path for pm_scratch_node_list_append: grow the list and append the
 * node. Do not call directly — use pm_scratch_node_list_append instead.
 */
void pm_scratch_node_list_append_slow(pm_arena_t *arena, pm_scratch_node_list_t *list, pm_node_t *node);

/*
 * Append a node onto the end of a scratch list, handling the common case inline
 * and growing the list through pm_scratch_node_list_append_slow.
 */
static PRISM_FORCE_INLINE void
pm_scratch_node_list_append(pm_arena_t *arena, pm_scratch_node_list_t *list, pm_node_t *node) {
    if (list->size < list->capacity) {
        list->nodes[list->size++] = node;
    } else {
        pm_scratch_node_list_append_slow(arena, list, node);
    }
}

/* Append every node of the other scratch list onto the end of the list. */
void pm_scratch_node_list_concat(pm_arena_t *arena, pm_scratch_node_list_t *list, const pm_scratch_node_list_t *other);

/*
 * A fixed-size piece of a node list that is still being built. It is exactly
 * eight pointers wide, so its size is a power of two. The type itself only
 * requires pointer alignment; pm_node_chunks_carve explicitly allocates each
 * batch aligned to the chunk size. Each chunk in the batch has that alignment
 * because the stride is also the chunk size. The link comes first, so a cursor
 * just past the last slot has zero low bits, the same as NULL. One mask test
 * then tells an append that the list needs a new chunk, whether the list is
 * empty or its last chunk is full.
 */
typedef struct pm_node_chunk {
    /* The previous chunk of the same list, or the next chunk on the freelist. */
    struct pm_node_chunk *prev;

    /* The nodes held by this chunk, in order. */
    pm_node_t *slots[7];
} pm_node_chunk_t;

/* The size of a chunk and the alignment requested when allocating its batch. */
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
static PRISM_INLINE void
pm_node_list_open_append(pm_node_chunks_t *chunks, pm_node_list_t *list, pm_node_t *node) {
    if (((uintptr_t) list->nodes & PM_NODE_CHUNK_MASK) != 0) {
        *list->nodes++ = node;
        list->size++;
    } else {
        pm_node_list_open_append_slow(chunks, list, node);
    }
}

/*
 * The last node in an open list, which must not be empty. The cursor is always
 * just past it, in the same chunk.
 */
static PRISM_INLINE pm_node_t *
pm_node_list_open_last(const pm_node_list_t *list) {
    return list->nodes[-1];
}

/*
 * Copy an open list into an array of exactly its size allocated from the given
 * arena, and return its chunks to the freelist. Afterward the list holds that
 * array, and it must not be appended to through pm_node_list_open_append or
 * finalized again.
 */
void pm_node_list_finalize(pm_node_chunks_t *chunks, pm_arena_t *arena, pm_node_list_t *list);

/*
 * A finalized list holding just the given node, in an array allocated from the
 * given arena without going through chunks.
 */
pm_node_list_t pm_node_list_single(pm_arena_t *arena, pm_node_t *node);

/*
 * Prepend a node onto the beginning of a finalized list, copying it into a new
 * array in the given arena of exactly the new size.
 */
void pm_node_list_prepend_finalized(pm_arena_t *arena, pm_node_list_t *list, pm_node_t *node);

/*
 * A finalized list of the size nodes starting at the given index of another
 * finalized list. It shares that list's array instead of copying it.
 */
static PRISM_INLINE pm_node_list_t
pm_node_list_slice(const pm_node_list_t *list, uint32_t start, uint32_t size) {
    PRISM_ASSERT(start + size <= list->size);
    return (pm_node_list_t) { .size = size, .nodes = size == 0 ? NULL : list->nodes + start };
}

#endif
