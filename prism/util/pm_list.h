// This struct represents an abstract linked list that provides common
// functionality. It is meant to be used any time a linked list is necessary to
// store data.
//
// The linked list itself operates off a set of pointers. Because the pointers
// are not necessarily sequential, they can be of any size. We use this fact to
// allow the consumer of this linked list to extend the node struct to include
// any data they want. This is done by using the yp_list_node_t as the first
// member of the struct.
//
// For example, if we want to store a list of integers, we can do the following:
//
//     typedef struct {
//       yp_list_node_t node;
//       int value;
//     } yp_int_node_t;
//
//     yp_list_t list = YP_LIST_EMPTY;
//     yp_int_node_t *node = malloc(sizeof(yp_int_node_t));
//     node->value = 5;
//
//     yp_list_append(&list, &node->node);
//
// The yp_list_t struct is used to represent the overall linked list. It
// contains a pointer to the head and tail of the list. This allows for easy
// iteration and appending of new nodes.

#ifndef YARP_LIST_H
#define YARP_LIST_H

#include "yarp/defines.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

// This represents a node in the linked list.
typedef struct yp_list_node {
    struct yp_list_node *next;
} yp_list_node_t;

// This represents the overall linked list. It keeps a pointer to the head and
// tail so that iteration is easy and pushing new nodes is easy.
typedef struct {
    size_t size;
    yp_list_node_t *head;
    yp_list_node_t *tail;
} yp_list_t;

// This represents an empty list. It's used to initialize a stack-allocated list
// as opposed to a method call.
#define YP_LIST_EMPTY ((yp_list_t) { .size = 0, .head = NULL, .tail = NULL })

// Returns true if the given list is empty.
YP_EXPORTED_FUNCTION bool yp_list_empty_p(yp_list_t *list);

// Returns the size of the list.
YP_EXPORTED_FUNCTION size_t yp_list_size(yp_list_t *list);

// Append a node to the given list.
void yp_list_append(yp_list_t *list, yp_list_node_t *node);

// Deallocate the internal state of the given list.
YP_EXPORTED_FUNCTION void yp_list_free(yp_list_t *list);

#endif
