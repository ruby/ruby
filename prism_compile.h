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

// A declaration for the struct that lives in compile.c.
struct iseq_link_anchor;

/**
 * A direct-indexed lookup table mapping constant IDs to local variable indices.
 * Regular constant IDs (1..constants_size) index directly. Special forwarding
 * parameter IDs (idMULT|FLAG, etc.) are mapped to 4 extra slots at the end.
 *
 * All lookups are O(1) — a single array dereference.
 * The table is arena-allocated for child scopes (no explicit free needed).
 */
typedef struct {
    /** Array of local indices, indexed by constant_id. -1 means not present. */
    int *values;

    /** Total number of slots (constants_size + PM_INDEX_LOOKUP_SPECIALS). */
    int capacity;

    /** Whether the values array is heap-allocated and needs explicit free. */
    bool owned;
} pm_index_lookup_table_t;

/** Number of extra slots for special forwarding parameter IDs. */
#define PM_INDEX_LOOKUP_SPECIALS 4

/** Slot offsets for special forwarding parameters (relative to constants_size). */
#define PM_SPECIAL_CONSTANT_FLAG ((pm_constant_id_t) (1 << 31))
#define PM_INDEX_LOOKUP_SPECIAL_MULT 0
#define PM_INDEX_LOOKUP_SPECIAL_POW 1
#define PM_INDEX_LOOKUP_SPECIAL_AND 2
#define PM_INDEX_LOOKUP_SPECIAL_DOT3 3

/**
 * Special constant IDs for forwarding parameters. These use bit 31 to
 * distinguish them from regular prism constant pool IDs. The lower bits
 * encode which special slot (0-3) they map to in the lookup table.
 */
#define PM_CONSTANT_MULT ((pm_constant_id_t) (PM_SPECIAL_CONSTANT_FLAG | PM_INDEX_LOOKUP_SPECIAL_MULT))
#define PM_CONSTANT_POW  ((pm_constant_id_t) (PM_SPECIAL_CONSTANT_FLAG | PM_INDEX_LOOKUP_SPECIAL_POW))
#define PM_CONSTANT_AND  ((pm_constant_id_t) (PM_SPECIAL_CONSTANT_FLAG | PM_INDEX_LOOKUP_SPECIAL_AND))
#define PM_CONSTANT_DOT3 ((pm_constant_id_t) (PM_SPECIAL_CONSTANT_FLAG | PM_INDEX_LOOKUP_SPECIAL_DOT3))

static inline int
pm_index_lookup_table_index(const pm_index_lookup_table_t *table, pm_constant_id_t key)
{
    if (LIKELY(!(key & PM_SPECIAL_CONSTANT_FLAG))) {
        return (int) key - 1;
    }
    return table->capacity - PM_INDEX_LOOKUP_SPECIALS + (int)(key & ~PM_SPECIAL_CONSTANT_FLAG);
}

static inline void
pm_index_lookup_table_insert(pm_index_lookup_table_t *table, pm_constant_id_t key, int value)
{
    int idx = pm_index_lookup_table_index(table, key);
    RUBY_ASSERT(idx >= 0 && idx < table->capacity);
    table->values[idx] = value;
}

static inline int
pm_index_lookup_table_lookup(const pm_index_lookup_table_t *table, pm_constant_id_t key, int *value)
{
    int idx = pm_index_lookup_table_index(table, key);
    RUBY_ASSERT(idx >= 0 && idx < table->capacity);
    if (table->values[idx] == -1) return 0;
    *value = table->values[idx];
    return 1;
}

static inline void
pm_index_lookup_table_init_heap(pm_index_lookup_table_t *table, int constants_size)
{
    int cap = constants_size + PM_INDEX_LOOKUP_SPECIALS;
    table->values = (int *) ruby_xmalloc(cap * sizeof(int));
    memset(table->values, -1, cap * sizeof(int));
    table->capacity = cap;
    table->owned = true;
}

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
    const pm_options_t *options;
    const pm_line_offset_list_t *line_offsets;
    int32_t start_line;
    rb_encoding *encoding;

    /**
     * This is a pointer to the list of script lines for the ISEQs that will be
     * associated with this scope node. It is only set if
     * RubyVM.keep_script_lines is true. If it is set, it will be set to a
     * pointer to an array that is always stack allocated (so no GC marking is
     * needed by this struct). If it is not set, it will be NULL. It is
     * inherited by all child scopes.
     */
    VALUE *script_lines;

    /**
     * This is the encoding of the actual filepath object that will be used when
     * a __FILE__ node is compiled or when the path has to be set on a syntax
     * error.
     */
    rb_encoding *filepath_encoding;

    // The size of the local table on the iseq which includes locals and hidden
    // variables.
    int local_table_for_iseq_size;

    ID *constants;

    /**
     * A flat lookup table mapping constant IDs (or special IDs) to local
     * variable indices. When allocated from the compile data arena (child
     * scopes), no explicit free is needed. When heap-allocated (top-level
     * scope in pm_parse_process), owned is set to true so destroy can free it.
     */
    pm_index_lookup_table_t index_lookup_table;

    // The current coverage setting, passed down through the various scopes.
    int coverage_enabled;

    /**
     * This will only be set on the top-level scope node. It will contain all of
     * the instructions pertaining to BEGIN{} nodes.
     */
    struct iseq_link_anchor *pre_execution_anchor;

    /**
     * Cached line hint for line offset list lookups. Since the compiler walks
     * the AST roughly in source order, consecutive lookups tend to be for
     * nearby byte offsets. This avoids repeated binary searches.
     */
    size_t last_line;
} pm_scope_node_t;

void pm_scope_node_init(const pm_node_t *node, pm_scope_node_t *scope, pm_scope_node_t *previous);
void pm_scope_node_destroy(pm_scope_node_t *scope_node);

typedef struct {
    /** The arena allocator for AST-lifetime memory. */
    pm_arena_t *arena;

    /** The parser that will do the actual parsing. */
    pm_parser_t *parser;

    /** The options that will be passed to the parser. */
    pm_options_t *options;

    /** The source backing the parse (file, string, or stream). */
    pm_source_t *source;

    /** The resulting scope node that will hold the generated AST. */
    pm_scope_node_t node;

    /** Whether or not this parse result has performed its parsing yet. */
    bool parsed;
} pm_parse_result_t;

void pm_parse_result_init(pm_parse_result_t *result);
VALUE pm_load_file(pm_parse_result_t *result, VALUE filepath, bool load_error);
VALUE pm_parse_file(pm_parse_result_t *result, VALUE filepath, VALUE *script_lines);
VALUE pm_load_parse_file(pm_parse_result_t *result, VALUE filepath, VALUE *script_lines);
VALUE pm_parse_string(pm_parse_result_t *result, VALUE source, VALUE filepath, VALUE *script_lines);
VALUE pm_parse_stdin(pm_parse_result_t *result);
void pm_options_version_for_current_ruby_set(pm_options_t *options);
void pm_parse_result_free(pm_parse_result_t *result);

rb_iseq_t *pm_iseq_new(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent, enum rb_iseq_type, int *error_state);
rb_iseq_t *pm_iseq_new_top(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent, int *error_state);
rb_iseq_t *pm_iseq_new_main(pm_scope_node_t *node, VALUE path, VALUE realpath, const rb_iseq_t *parent, int opt, int *error_state);
rb_iseq_t *pm_iseq_new_eval(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, int first_lineno, const rb_iseq_t *parent, int isolated_depth, int *error_state);
rb_iseq_t *pm_iseq_new_with_opt(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, int first_lineno, const rb_iseq_t *parent, int isolated_depth, enum rb_iseq_type, const rb_compile_option_t *option, int *error_state);
rb_iseq_t *pm_iseq_build(pm_scope_node_t *node, VALUE name, VALUE path, VALUE realpath, int first_lineno, const rb_iseq_t *parent, int isolated_depth, enum rb_iseq_type, const rb_compile_option_t *option);

VALUE pm_iseq_compile_node(rb_iseq_t *iseq, pm_scope_node_t *node);
