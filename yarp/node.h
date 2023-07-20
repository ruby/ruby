#ifndef YARP_NODE_H
#define YARP_NODE_H

#include "yarp/defines.h"
#include "yarp/parser.h"

// Append a token to the given list.
void yp_location_list_append(yp_location_list_t *list, const yp_token_t *token);

// Append a new node onto the end of the node list.
void yp_node_list_append(yp_node_list_t *list, yp_node_t *node);

// Clear the node but preserves the location.
void yp_node_clear(yp_node_t *node);

// Deallocate a node and all of its children.
YP_EXPORTED_FUNCTION void yp_node_destroy(yp_parser_t *parser, struct yp_node *node);

// This struct stores the information gathered by the yp_node_memsize function.
// It contains both the memory footprint and additionally metadata about the
// shape of the tree.
typedef struct {
    size_t memsize;
    size_t node_count;
} yp_memsize_t;

// Calculates the memory footprint of a given node.
YP_EXPORTED_FUNCTION void yp_node_memsize(yp_node_t *node, yp_memsize_t *memsize);

// Returns a string representation of the given node type.
YP_EXPORTED_FUNCTION const char * yp_node_type_to_str(yp_node_type_t node_type);

#define YP_EMPTY_NODE_LIST ((yp_node_list_t) { .nodes = NULL, .size = 0, .capacity = 0 })
#define YP_EMPTY_LOCATION_LIST ((yp_location_list_t) { .locations = NULL, .size = 0, .capacity = 0 })

#endif // YARP_NODE_H
