// This struct represents an abstract linked list that provides common
// functionality. It is meant to be used any time a linked list is necessary to
// store data.
//
// The linked list itself operates off a set of pointers. Because the pointers
// are not necessarily sequential, they can be of any size. We use this fact to
// allow the consumer of this linked list to extend the node struct to include
// any data they want. This is done by using the pm_list_node_t as the first
// member of the struct.
//
// For example, if we want to store a list of integers, we can do the following:
//
//     typedef struct {
//       pm_list_node_t node;
//       int value;
//     } pm_int_node_t;
//
//     pm_list_t list = PM_LIST_EMPTY;
//     pm_int_node_t *node = malloc(sizeof(pm_int_node_t));
//     node->value = 5;
//
//     pm_list_append(&list, &node->node);
//
// The pm_list_t struct is used to represent the overall linked list. It
// contains a pointer to the head and tail of the list. This allows for easy
// iteration and appending of new nodes.

#ifndef PRISM_LIST_H
#define PRISM_LIST_H

#include "prism/defines.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

// This represents a node in the linked list.
typedef struct pm_list_node {
    struct pm_list_node *next;
} pm_list_node_t;

// This represents the overall linked list. It keeps a pointer to the head and
// tail so that iteration is easy and pushing new nodes is easy.
typedef struct {
    size_t size;
    pm_list_node_t *head;
    pm_list_node_t *tail;
} pm_list_t;

// This represents an empty list. It's used to initialize a stack-allocated list
// as opposed to a method call.
#define PM_LIST_EMPTY ((pm_list_t) { .size = 0, .head = NULL, .tail = NULL })

// Returns true if the given list is empty.
PRISM_EXPORTED_FUNCTION bool pm_list_empty_p(pm_list_t *list);

// Returns the size of the list.
PRISM_EXPORTED_FUNCTION size_t pm_list_size(pm_list_t *list);

// Append a node to the given list.
void pm_list_append(pm_list_t *list, pm_list_node_t *node);

// Deallocate the internal state of the given list.
PRISM_EXPORTED_FUNCTION void pm_list_free(pm_list_t *list);

#endif
