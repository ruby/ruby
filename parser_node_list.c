#include "parser_node_list.h"

/**
 * Attempts to grow the node list to the next size. If there is already
 * capacity in the list, this function does nothing. Otherwise it reallocates
 * the list to be twice as large as it was before. If the reallocation fails,
 * this function returns false, otherwise it returns true.
 */
static bool
rb_node_list_grow(rb_node_list2_t *list, size_t size) {
    size_t requested_size = list->size + size;

    // If the requested size caused overflow, return false.
    if (requested_size < list->size) return false;

    // If the requested size is within the existing capacity, return true.
    if (requested_size < list->capacity) return true;

    // Otherwise, reallocate the list to be twice as large as it was before.
    size_t next_capacity = list->capacity == 0 ? 4 : list->capacity * 2;

    // If multiplying by 2 caused overflow, return false.
    if (next_capacity < list->capacity) return false;

    // If we didn't get enough by doubling, keep doubling until we do.
    while (requested_size > next_capacity) {
        size_t double_capacity = next_capacity * 2;

        // Ensure we didn't overflow by multiplying by 2.
        if (double_capacity < next_capacity) return false;
        next_capacity = double_capacity;
    }

    rb_node_t **nodes = (rb_node_t **) xrealloc(list->nodes, sizeof(rb_node_t *) * next_capacity);
    if (nodes == NULL) return false;

    list->nodes = nodes;
    list->capacity = next_capacity;
    return true;
}

void
rb_node_list_init(rb_node_list2_t *list)
{
    list->size = 0;
    list->capacity = 0;
    list->nodes = NULL;
}

/**
 * Append a new node onto the end of the node list.
 */
void
rb_node_list_append(rb_node_list2_t *list, rb_node_t *node) {
    if (rb_node_list_grow(list, 1)) {
        list->nodes[list->size++] = node;
    }
}

/**
 * Prepend a new node onto the beginning of the node list.
 */
void
rb_node_list_prepend(rb_node_list2_t *list, rb_node_t *node) {
    if (rb_node_list_grow(list, 1)) {
        memmove(list->nodes + 1, list->nodes, list->size * sizeof(rb_node_t *));
        list->nodes[0] = node;
        list->size++;
    }
}

/**
 * Concatenate the given node list onto the end of the other node list.
 */
void
rb_node_list_concat(rb_node_list2_t *list, rb_node_list2_t *other) {
    if (other->size > 0 && rb_node_list_grow(list, other->size)) {
        memcpy(list->nodes + list->size, other->nodes, other->size * sizeof(rb_node_t *));
        list->size += other->size;
    }
}

/**
 * Free the internal memory associated with the given node list.
 */
void
rb_node_list_free(rb_node_list2_t *list) {
    if (list->capacity > 0) {
        xfree(list->nodes);
        *list = (rb_node_list2_t) { 0 };
    }
}
