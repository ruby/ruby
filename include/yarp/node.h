#ifndef YARP_NODE_H
#define YARP_NODE_H

#include "yarp/defines.h"

#include "yarp.h"
#include "yarp/parser.h"

// Initialize a yp_token_list_t with its default values.
void
yp_token_list_init(yp_token_list_t *token_list);

// Append a token to the given list.
void
yp_token_list_append(yp_token_list_t *token_list, const yp_token_t *token);

// Checks if the current token list includes the given token.
bool
yp_token_list_includes(yp_token_list_t *token_list, const yp_token_t *token);

// Initiailize a list of nodes.
void
yp_node_list_init(yp_node_list_t *node_list);

// Append a new node onto the end of the node list.
void
yp_node_list_append(yp_parser_t *parser, yp_node_t *parent, yp_node_list_t *list, yp_node_t *node);

// Clear the node but preserves the location.
void
yp_node_clear(yp_node_t *node);

#define YP_EMPTY_NODE_LIST { .nodes = NULL, .size = 0, .capacity = 0 }

#define YP_EMPTY_TOKEN_LIST { .tokens = NULL, .size = 0, .capacity = 0 }

#endif // YARP_NODE_H
