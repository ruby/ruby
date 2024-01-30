#include "prism/prism.h"

/**
 * the getlocal and setlocal instructions require two parameters. level is how
 * many hops up the iseq stack one needs to go before finding the correct local
 * table. The index is the index in that table where our variable is.
 *
 * Because these are always calculated and used together, we'll bind them
 * together as a tuple.
 */
typedef struct pm_local_index_struct {
    int index, level;
} pm_local_index_t;

// ScopeNodes are helper nodes, and will never be part of the AST. We manually
// declare them here to avoid generating them.
typedef struct pm_scope_node {
    pm_node_t base;
    struct pm_scope_node *previous;
    pm_node_t *ast_node;
    pm_node_t *parameters;
    pm_node_t *body;
    pm_constant_id_list_t locals;
    pm_parser_t *parser;

    // The size of the local table
    // on the iseq which includes
    // locals and hidden variables
    int local_table_for_iseq_size;

    ID *constants;
    st_table *index_lookup_table;
} pm_scope_node_t;

void pm_scope_node_init(const pm_node_t *node, pm_scope_node_t *scope, pm_scope_node_t *previous, pm_parser_t *parser);
void pm_scope_node_destroy(pm_scope_node_t *scope_node);
bool *rb_ruby_prism_ptr(void);
