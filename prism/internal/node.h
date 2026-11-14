#ifndef PRISM_INTERNAL_NODE_H
#define PRISM_INTERNAL_NODE_H

#include "prism/node.h"

#include "prism/compiler/force_inline.h"

#include "prism/arena.h"

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

#endif
