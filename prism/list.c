#include "prism/list.h"

/**
 * Returns the size of the list.
 */
size_t
pm_list_size(pm_list_t *list) {
    return list->size;
}

/**
 * Append a node to the given list.
 */
void
pm_list_append(pm_list_t *list, pm_list_node_t *node) {
    if (list->head == NULL) {
        list->head = node;
    } else {
        list->tail->next = node;
    }

    list->tail = node;
    list->size++;
}
