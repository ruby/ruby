#ifndef PRISM_NODE_H
#define PRISM_NODE_H

#include "prism/defines.h"
#include "prism/parser.h"

// Append a new node onto the end of the node list.
void pm_node_list_append(pm_node_list_t *list, pm_node_t *node);

// Clear the node but preserves the location.
void pm_node_clear(pm_node_t *node);

// Deallocate a node and all of its children.
PRISM_EXPORTED_FUNCTION void pm_node_destroy(pm_parser_t *parser, struct pm_node *node);

// This struct stores the information gathered by the pm_node_memsize function.
// It contains both the memory footprint and additionally metadata about the
// shape of the tree.
typedef struct {
    size_t memsize;
    size_t node_count;
} pm_memsize_t;

// Calculates the memory footprint of a given node.
PRISM_EXPORTED_FUNCTION void pm_node_memsize(pm_node_t *node, pm_memsize_t *memsize);

// Returns a string representation of the given node type.
PRISM_EXPORTED_FUNCTION const char * pm_node_type_to_str(pm_node_type_t node_type);

#define PM_EMPTY_NODE_LIST ((pm_node_list_t) { .nodes = NULL, .size = 0, .capacity = 0 })

// ScopeNodes are helper nodes, and will never be part of the AST. We manually
// declare them here to avoid generating them.
typedef struct pm_scope_node {
    pm_node_t base;
    struct pm_scope_node *previous;
    pm_node_t *ast_node;
    struct pm_parameters_node *parameters;
    pm_node_t *body;
    pm_constant_id_list_t locals;
    pm_parser_t *parser;

    // We don't have the CRuby types ID and st_table within Prism
    // so we use void *
    void *constants; // ID *constants
    void *index_lookup_table; // st_table *index_lookup_table
} pm_scope_node_t;

#endif // PRISM_NODE_H
