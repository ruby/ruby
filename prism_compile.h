#include "prism/prism.h"

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

    ID *constants;
    st_table *index_lookup_table;
} pm_scope_node_t;

void pm_scope_node_init(const pm_node_t *node, pm_scope_node_t *scope, pm_scope_node_t *previous, pm_parser_t *parser);
