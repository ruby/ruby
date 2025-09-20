#ifndef RB_NODE_COMPILE_H
#define RB_NODE_COMPILE_H

#include "prism/prism.h"
#include "iseq.h"
#include "ruby/encoding.h"

/**
 * the getlocal and setlocal instructions require two parameters. level is how
 * many hops up the iseq stack one needs to go before finding the correct local
 * table. The index is the index in that table where our variable is.
 *
 * Because these are always calculated and used together, we'll bind them
 * together as a tuple.
 */
typedef struct rb_local_index_struct {
    int index, level;
} rb_local_index_t;

// A declaration for the struct that lives in compile.c.
struct iseq_link_anchor;

// ScopeNodes are helper nodes, and will never be part of the AST. We manually
// declare them here to avoid generating them.
typedef struct rb_scope_node {
    rb_node_t base;
    struct rb_scope_node *previous;
    rb_node_t *ast_node;
    rb_node_t *parameters;
    rb_node_t *body;
    rb_ast_id_table_t *locals;

    // const pm_parser_t *parser;
    rb_ast_t *ast;

    /**
     * This is a pointer to the list of script lines for the ISEQs that will be
     * associated with this scope node. It is only set if
     * RubyVM.keep_script_lines is true. If it is set, it will be set to a
     * pointer to an array that is always stack allocated (so no GC marking is
     * needed by this struct). If it is not set, it will be NULL. It is
     * inherited by all child scopes.
     */
    // VALUE *script_lines;

    /**
     * This is the encoding of the actual filepath object that will be used when
     * a __FILE__ node is compiled or when the path has to be set on a syntax
     * error.
     */
    // rb_encoding *filepath_encoding;

    // The size of the local table on the iseq which includes locals and hidden
    // variables.
    int local_table_for_iseq_size;

    // ID *constants;
    st_table *index_lookup_table;

    // The current coverage setting, passed down through the various scopes.
    int coverage_enabled;

    /**
     * This will only be set on the top-level scope node. It will contain all of
     * the instructions pertaining to BEGIN{} nodes.
     */
    struct iseq_link_anchor *pre_execution_anchor;
} rb_scope_node_t;

typedef struct rb_ast_scope_struct {
    rb_ast_t *ast;
    rb_scope_node_t scope_node;
} rb_ast_scope_t;

void rb_scope_node_init(const rb_node_t *node, rb_scope_node_t *scope, rb_scope_node_t *previous);
void rb_scope_node_destroy(rb_scope_node_t *scope_node);

#define RB_SPECIAL_CONSTANT_FLAG ((pm_constant_id_t)(1 << 31))
#define RB_CONSTANT_AND ((pm_constant_id_t)(idAnd | RB_SPECIAL_CONSTANT_FLAG))
#define RB_CONSTANT_DOT3 ((pm_constant_id_t)(idDot3 | RB_SPECIAL_CONSTANT_FLAG))
#define RB_CONSTANT_MULT ((pm_constant_id_t)(idMULT | RB_SPECIAL_CONSTANT_FLAG))
#define RB_CONSTANT_POW ((pm_constant_id_t)(idPow | RB_SPECIAL_CONSTANT_FLAG))

// VALUE pm_load_file(pm_parse_result_t *result, VALUE filepath, bool load_error);
// VALUE pm_parse_file(pm_parse_result_t *result, VALUE filepath, VALUE *script_lines);
// VALUE pm_load_parse_file(pm_parse_result_t *result, VALUE filepath, VALUE *script_lines);
// VALUE pm_parse_string(pm_parse_result_t *result, VALUE source, VALUE filepath, VALUE *script_lines);
// VALUE pm_parse_stdin(pm_parse_result_t *result);
void pm_options_version_for_current_ruby_set(pm_options_t *options);
// void pm_parse_result_free(pm_parse_result_t *result);

rb_iseq_t *rb_node_iseq_new(rb_scope_node_t *scope_node, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent, enum rb_iseq_type, int *error_state);
rb_iseq_t *rb_node_iseq_new_top(rb_scope_node_t *scope_node, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent, int *error_state);
rb_iseq_t *rb_node_iseq_new_main(const VALUE ast_scope_value, VALUE path, VALUE realpath, const rb_iseq_t *parent, int opt);
rb_iseq_t *rb_node_iseq_new_eval(rb_scope_node_t *scope_node, VALUE name, VALUE path, VALUE realpath, int first_lineno, const rb_iseq_t *parent, int isolated_depth, int *error_state);
rb_iseq_t *rb_node_iseq_new_with_opt(rb_scope_node_t *scope_node, VALUE name, VALUE path, VALUE realpath, int first_lineno, const rb_iseq_t *parent, int isolated_depth, enum rb_iseq_type, const rb_compile_option_t *option, VALUE script_lines, int *error_state);

VALUE rb_node_iseq_compile_node(rb_iseq_t *iseq, rb_scope_node_t *scope_node);
VALUE rb_parse_process(rb_ast_scope_t *ast_scope, const rb_node_t *node);

#endif
