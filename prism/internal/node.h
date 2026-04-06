#ifndef PRISM_INTERNAL_NODE_H
#define PRISM_INTERNAL_NODE_H

#include "prism/node.h"

#include "prism/compiler/force_inline.h"

#include "prism/arena.h"

/*
 * Slow path for pm_node_list_append: grow the list and append the node.
 * Do not call directly — use pm_node_list_append instead.
 */
void pm_node_list_append_slow(pm_arena_t *arena, pm_node_list_t *list, pm_node_t *node);

/* Append a new node onto the end of the node list. */
static PRISM_FORCE_INLINE void
pm_node_list_append(pm_arena_t *arena, pm_node_list_t *list, pm_node_t *node) {
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
