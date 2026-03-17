/**
 * @file internal/list.h
 *
 * An abstract linked list.
 */
#ifndef PRISM_INTERNAL_LIST_H
#define PRISM_INTERNAL_LIST_H

#include "prism/list.h"

/**
 * Returns the size of the list.
 *
 * @param list The list to check.
 * @return The size of the list.
 */
size_t pm_list_size(pm_list_t *list);

/**
 * Append a node to the given list.
 *
 * @param list The list to append to.
 * @param node The node to append.
 */
void pm_list_append(pm_list_t *list, pm_list_node_t *node);

#endif
