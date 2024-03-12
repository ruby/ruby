#include "prism/prism.h"
#include "ruby/encoding.h"

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

    const pm_parser_t *parser;
    rb_encoding *encoding;

    // The size of the local table
    // on the iseq which includes
    // locals and hidden variables
    int local_table_for_iseq_size;

    ID *constants;
    st_table *index_lookup_table;
} pm_scope_node_t;

void pm_scope_node_init(const pm_node_t *node, pm_scope_node_t *scope, pm_scope_node_t *previous);
void pm_scope_node_destroy(pm_scope_node_t *scope_node);
bool *rb_ruby_prism_ptr(void);

typedef struct {
    pm_parser_t parser;
    pm_options_t options;
    pm_string_t input;
    pm_scope_node_t node;
    bool parsed;
} pm_parse_result_t;

VALUE pm_load_file(pm_parse_result_t *result, VALUE filepath);
VALUE pm_parse_file(pm_parse_result_t *result, VALUE filepath);
VALUE pm_load_parse_file(pm_parse_result_t *result, VALUE filepath);
VALUE pm_parse_string(pm_parse_result_t *result, VALUE source, VALUE filepath);
void pm_parse_result_free(pm_parse_result_t *result);

rb_iseq_t *pm_iseq_new(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent, enum rb_iseq_type);
rb_iseq_t *pm_iseq_new_top(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent);
rb_iseq_t *pm_iseq_new_main(pm_scope_node_t *node, VALUE path, VALUE realpath, const rb_iseq_t *parent, int opt);
rb_iseq_t *pm_iseq_new_eval(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, int first_lineno, const rb_iseq_t *parent, int isolated_depth);
rb_iseq_t *pm_iseq_new_with_opt(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, int first_lineno, const rb_iseq_t *parent, int isolated_depth, enum rb_iseq_type, const rb_compile_option_t*);

VALUE pm_iseq_compile_node(rb_iseq_t *iseq, pm_scope_node_t *node);
