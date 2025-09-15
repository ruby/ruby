#ifndef PARSER_NODE_LIST_H
#define PARSER_NODE_LIST_H

#include "parser_ast.h"

/**
 * Loop through each node in the node list, writing each node to the given
 * rb_node_t pointer.
 */
#define RB_NODE_LIST_FOREACH(list, index, node) \
    for (size_t index = 0; index < (list)->size && ((node) = (list)->nodes[index]); index++)

void rb_node_list_init(rb_node_list2_t *list);

/**
 * Append a new node onto the end of the node list.
 *
 * @param list The list to append to.
 * @param node The node to append.
 */
void rb_node_list_append(rb_node_list2_t *list, rb_node_t *node);

/**
 * Prepend a new node onto the beginning of the node list.
 *
 * @param list The list to prepend to.
 * @param node The node to prepend.
 */
void rb_node_list_prepend(rb_node_list2_t *list, rb_node_t *node);

/**
 * Concatenate the given node list onto the end of the other node list.
 *
 * @param list The list to concatenate onto.
 * @param other The list to concatenate.
 */
void rb_node_list_concat(rb_node_list2_t *list, rb_node_list2_t *other);

/**
 * Free the internal memory associated with the given node list.
 *
 * @param list The list to free.
 */
void rb_node_list_free(rb_node_list2_t *list);


#endif
