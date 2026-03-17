/**
 * @file internal/node.h
 */
#ifndef PRISM_INTERNAL_NODE_H
#define PRISM_INTERNAL_NODE_H

#include "prism/arena.h"
#include "prism/ast.h"

/**
 * Prepend a new node onto the beginning of the node list.
 *
 * @param arena The arena to allocate from.
 * @param list The list to prepend to.
 * @param node The node to prepend.
 */
void pm_node_list_prepend(pm_arena_t *arena, pm_node_list_t *list, pm_node_t *node);

/**
 * Concatenate the given node list onto the end of the other node list.
 *
 * @param arena The arena to allocate from.
 * @param list The list to concatenate onto.
 * @param other The list to concatenate.
 */
void pm_node_list_concat(pm_arena_t *arena, pm_node_list_t *list, pm_node_list_t *other);

#endif
