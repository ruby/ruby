#ifndef RUBY_ISEQ_H
#define RUBY_ISEQ_H 1
/**********************************************************************

  iseq.h -

  $Author$
  created at: 04/01/01 23:36:57 JST

  Copyright (C) 2004-2008 Koichi Sasada

**********************************************************************/
#include "internal/coverage.h"
#include "internal/gc.h"
#include "shape.h"
#include "vm_core.h"
#include "prism_compile.h"

RUBY_EXTERN const int ruby_api_version[];
#define ISEQ_MAJOR_VERSION ((unsigned int)ruby_api_version[0])
#define ISEQ_MINOR_VERSION ((unsigned int)ruby_api_version[1])

#define ISEQ_MBITS_SIZE sizeof(iseq_bits_t)
#define ISEQ_MBITS_BITLENGTH (ISEQ_MBITS_SIZE * CHAR_BIT)
#define ISEQ_MBITS_SET(buf, i) (buf[(i) / ISEQ_MBITS_BITLENGTH] |= ((iseq_bits_t)1 << ((i) % ISEQ_MBITS_BITLENGTH)))
#define ISEQ_MBITS_SET_P(buf, i) ((buf[(i) / ISEQ_MBITS_BITLENGTH] >> ((i) % ISEQ_MBITS_BITLENGTH)) & 0x1)
#define ISEQ_MBITS_BUFLEN(size) roomof(size, ISEQ_MBITS_BITLENGTH)

#define ISEQ_LVAR_STATE_BITS 2
#define ISEQ_LVAR_STATES_PER_BYTE (CHAR_BIT / ISEQ_LVAR_STATE_BITS)
#define ISEQ_LVAR_STATES_BUFLEN(size) roomof(size, ISEQ_LVAR_STATES_PER_BYTE)
#define ISEQ_LVAR_STATES_EMBED_P(size) (ISEQ_LVAR_STATES_BUFLEN(size) <= sizeof(uint8_t *))
STATIC_ASSERT(lvar_state_fits_in_iseq_lvar_state_bits, lvar_reassigned < (1 << ISEQ_LVAR_STATE_BITS));

static inline enum lvar_state
iseq_lvar_state_get(const uint8_t *buf, unsigned int i)
{
    const unsigned int shift = (i % ISEQ_LVAR_STATES_PER_BYTE) * ISEQ_LVAR_STATE_BITS;
    return (enum lvar_state)((buf[i / ISEQ_LVAR_STATES_PER_BYTE] >> shift) & ((1 << ISEQ_LVAR_STATE_BITS) - 1));
}

static inline void
iseq_lvar_state_set(uint8_t *buf, unsigned int i, enum lvar_state state)
{
    uint8_t *const byte = &buf[i / ISEQ_LVAR_STATES_PER_BYTE];
    const unsigned int shift = (i % ISEQ_LVAR_STATES_PER_BYTE) * ISEQ_LVAR_STATE_BITS;
    *byte = (*byte & ~(((1 << ISEQ_LVAR_STATE_BITS) - 1) << shift)) | ((uint8_t)state << shift);
}

#ifndef USE_ISEQ_NODE_ID
#define USE_ISEQ_NODE_ID 1
#endif

#ifndef rb_iseq_t
typedef struct rb_iseq_struct rb_iseq_t;
#define rb_iseq_t rb_iseq_t
#endif
typedef void (*rb_iseq_callback)(const rb_iseq_t *, void *);

extern const ID rb_iseq_shared_exc_local_tbl[];

static inline bool
iseq_has_lvar_states_p(const struct rb_iseq_constant_body *body)
{
    return body->local_table_size > 0 && body->local_table != rb_iseq_shared_exc_local_tbl;
}

static inline uint8_t *
iseq_lvar_states(const struct rb_iseq_constant_body *body)
{
    if (ISEQ_LVAR_STATES_EMBED_P(body->local_table_size)) {
        return (uint8_t *)body->lvar_states.single;
    }
    else {
        return body->lvar_states.list;
    }
}

/* Ensure body->variable is allocated, returning the struct. */
struct rb_iseq_variable *rb_iseq_variable_ensure(rb_iseq_t *iseq);

static inline struct rb_iseq_variable *
ISEQ_BODY_VARIABLE(const rb_iseq_t *iseq)
{
    return ISEQ_BODY(iseq)->variable;
}

/* NULL-safe read accessors for body->variable fields. */
static inline VALUE
ISEQ_BODY_VARIABLE_SCRIPT_LINES(const rb_iseq_t *iseq)
{
    struct rb_iseq_variable *v = ISEQ_BODY_VARIABLE(iseq);
    return v ? v->script_lines : Qnil;
}

static inline VALUE
ISEQ_BODY_VARIABLE_COVERAGE(const rb_iseq_t *iseq)
{
    struct rb_iseq_variable *v = ISEQ_BODY_VARIABLE(iseq);
    return v ? v->coverage : Qfalse;
}

static inline VALUE
ISEQ_BODY_VARIABLE_PC2BRANCHINDEX(const rb_iseq_t *iseq)
{
    struct rb_iseq_variable *v = ISEQ_BODY_VARIABLE(iseq);
    return v ? v->pc2branchindex : Qfalse;
}

static inline rb_snum_t
ISEQ_BODY_VARIABLE_FLIP_CNT(const rb_iseq_t *iseq)
{
    struct rb_iseq_variable *v = ISEQ_BODY_VARIABLE(iseq);
    return v ? v->flip_count : 0;
}

static inline VALUE *
ISEQ_BODY_VARIABLE_ORIGINAL_ISEQ(const rb_iseq_t *iseq)
{
    struct rb_iseq_variable *v = ISEQ_BODY_VARIABLE(iseq);
    return v ? v->original_iseq : NULL;
}

/* Write accessors (lazily allocate variable as needed). */
void rb_iseq_coverage_set(rb_iseq_t *iseq, VALUE cov);
void rb_iseq_pc2branchindex_set(rb_iseq_t *iseq, VALUE h);
rb_snum_t rb_iseq_flip_cnt_increment(const rb_iseq_t *iseq);

/* Short macros for reading variable fields. */
#define ISEQ_VARIABLE(iseq)           ISEQ_BODY_VARIABLE(iseq)
#define ISEQ_SCRIPT_LINES(iseq)       ISEQ_BODY_VARIABLE_SCRIPT_LINES(iseq)
#define ISEQ_COVERAGE(iseq)           ISEQ_BODY_VARIABLE_COVERAGE(iseq)
#define ISEQ_COVERAGE_SET(iseq, cov)  rb_iseq_coverage_set(iseq, cov)
#define ISEQ_LINE_COVERAGE(iseq)      RARRAY_AREF(ISEQ_COVERAGE(iseq), COVERAGE_INDEX_LINES)
#define ISEQ_BRANCH_COVERAGE(iseq)    RARRAY_AREF(ISEQ_COVERAGE(iseq), COVERAGE_INDEX_BRANCHES)

#define ISEQ_PC2BRANCHINDEX(iseq)       ISEQ_BODY_VARIABLE_PC2BRANCHINDEX(iseq)
#define ISEQ_PC2BRANCHINDEX_SET(iseq,h) rb_iseq_pc2branchindex_set(iseq, h)

#define ISEQ_FLIP_CNT(iseq)             ISEQ_BODY_VARIABLE_FLIP_CNT(iseq)
#define ISEQ_FLIP_CNT_INCREMENT(iseq)   rb_iseq_flip_cnt_increment(iseq)
#define ISEQ_ORIGINAL_ISEQ(iseq)        ISEQ_BODY_VARIABLE_ORIGINAL_ISEQ(iseq)

#define ISEQ_FROZEN_STRING_LITERAL_ENABLED 1
#define ISEQ_FROZEN_STRING_LITERAL_DISABLED 0
#define ISEQ_FROZEN_STRING_LITERAL_UNSET -1

static inline void
ISEQ_ORIGINAL_ISEQ_CLEAR(const rb_iseq_t *iseq)
{
    struct rb_iseq_variable *v = ISEQ_BODY_VARIABLE(iseq);
    if (v) {
        VALUE *ptr = v->original_iseq;
        if (ptr) {
            v->original_iseq = NULL;
            SIZED_FREE_N(ptr, ISEQ_BODY(iseq)->iseq_size);
        }
    }
}

#define ISEQ_TRACE_EVENTS (RUBY_EVENT_LINE  | \
                           RUBY_EVENT_CLASS | \
                           RUBY_EVENT_END   | \
                           RUBY_EVENT_CALL  | \
                           RUBY_EVENT_RETURN| \
                           RUBY_EVENT_C_CALL| \
                           RUBY_EVENT_C_RETURN | \
                           RUBY_EVENT_B_CALL   | \
                           RUBY_EVENT_B_RETURN | \
                           RUBY_EVENT_RESCUE   | \
                           RUBY_EVENT_COVERAGE_LINE| \
                           RUBY_EVENT_COVERAGE_BRANCH)

#define ISEQ_NOT_LOADED_YET   IMEMO_FL_USER1
#define ISEQ_USE_COMPILE_DATA IMEMO_FL_USER2
#define ISEQ_TRANSLATED       IMEMO_FL_USER3
/* set on every iseq of a subtree copied for Proc#refined */
#define ISEQ_REFINED_COPY     IMEMO_FL_USER4

#define ISEQ_EXECUTABLE_P(iseq) (FL_TEST_RAW(((VALUE)iseq), ISEQ_NOT_LOADED_YET | ISEQ_USE_COMPILE_DATA) == 0)

struct iseq_compile_data {
    /* GC is needed */
    const VALUE err_info;
    const VALUE catch_table_ary;	/* Array */

    /* Mirror fields from ISEQ_BODY so they are accessible during iseq setup */
    unsigned int iseq_size;
    VALUE *iseq_encoded; /* half-encoded iseq (insn addr and operands) */
    bool is_single_mark_bit; /* identifies whether mark bits are single or a list */

    union {
        iseq_bits_t * list; /* Find references for GC */
        iseq_bits_t single;
    } mark_bits;

    /* GC is not needed */
    struct iseq_label_data *start_label;
    struct iseq_label_data *end_label;
    struct iseq_label_data *redo_label;
    const rb_iseq_t *current_block;
    struct iseq_compile_data_ensure_node_stack *ensure_node_stack;
    struct {
      struct iseq_compile_data_storage *storage_head;
      struct iseq_compile_data_storage *storage_current;
    } node;
    struct {
      struct iseq_compile_data_storage *storage_head;
      struct iseq_compile_data_storage *storage_current;
    } insn;
    bool in_rescue;
    int loopval_popped;	/* used by NODE_BREAK */
    int last_line;
    int label_no;
    int node_level;
    int isolated_depth;
    unsigned int ci_index;
    unsigned int ic_index;
    const rb_compile_option_t *option;
    struct rb_id_table *ivar_cache_table;
    const struct rb_builtin_function *builtin_function_table;
    const NODE *root_node;
    bool catch_except_p; // If a frame of this ISeq may catch exception, set true.
#if OPT_SUPPORT_JOKE
    st_table *labels_table;
#endif
};

static inline struct iseq_compile_data *
ISEQ_COMPILE_DATA(const rb_iseq_t *iseq)
{
    if (iseq->flags & ISEQ_USE_COMPILE_DATA) {
        return iseq->aux.compile_data;
    }
    else {
        return NULL;
    }
}

static inline void
ISEQ_COMPILE_DATA_ALLOC(rb_iseq_t *iseq)
{
    iseq->aux.compile_data = ZALLOC(struct iseq_compile_data);
    iseq->flags |= ISEQ_USE_COMPILE_DATA;
}

static inline void
ISEQ_COMPILE_DATA_CLEAR(rb_iseq_t *iseq)
{
    iseq->flags &= ~ISEQ_USE_COMPILE_DATA;
    iseq->aux.compile_data = NULL;
}

static inline rb_iseq_t *
iseq_imemo_alloc(void)
{
    rb_iseq_t *iseq = SHAREABLE_IMEMO_NEW(rb_iseq_t, imemo_iseq, 0);

    // Clear out the whole iseq except for the flags.
    memset((char *)iseq + sizeof(VALUE), 0, sizeof(rb_iseq_t) - sizeof(VALUE));

    return iseq;
}

VALUE rb_iseq_ibf_dump(const rb_iseq_t *iseq, VALUE opt);
void rb_ibf_load_iseq_complete(rb_iseq_t *iseq);
const rb_iseq_t *rb_iseq_ibf_load(VALUE str);
const rb_iseq_t *rb_iseq_ibf_load_bytes(const char *cstr, size_t);
VALUE rb_iseq_ibf_load_extra_data(VALUE str);
const rb_iseq_t *rb_iseq_dup_with_independent_caches(const rb_iseq_t *iseq);
void rb_iseq_init_trace(rb_iseq_t *iseq);
int rb_iseq_add_local_tracepoint_recursively(const rb_iseq_t *iseq, rb_event_flag_t turnon_events, VALUE tpval, unsigned int target_line, bool target_bmethod);
int rb_iseq_remove_local_tracepoint_recursively(const rb_iseq_t *iseq, VALUE tpval, rb_ractor_t *r);
const rb_iseq_t *rb_iseq_load_iseq(VALUE fname);
const rb_iseq_t *rb_iseq_compile_iseq(VALUE str, VALUE fname);
int rb_iseq_opt_frozen_string_literal(void);
rb_hook_list_t *rb_iseq_local_hooks(const rb_iseq_t *iseq, rb_ractor_t *r, bool create);


#if VM_INSN_INFO_TABLE_IMPL == 2
unsigned int *rb_iseq_insns_info_decode_positions(const struct rb_iseq_constant_body *body);
#endif

int rb_vm_insn_addr2opcode(const void *addr);

RUBY_SYMBOL_EXPORT_BEGIN

/* compile.c */
VALUE rb_iseq_compile_node(rb_iseq_t *iseq, const NODE *node);
VALUE rb_iseq_compile_callback(rb_iseq_t *iseq, const struct rb_iseq_new_with_callback_callback_func * ifunc);
VALUE *rb_iseq_original_iseq(const rb_iseq_t *iseq);
void rb_iseq_build_from_ary(rb_iseq_t *iseq, VALUE misc,
                            VALUE locals, VALUE args,
                            VALUE exception, VALUE body);
void rb_iseq_mark_and_move_insn_storage(struct iseq_compile_data_storage *arena);

VALUE rb_iseq_load(VALUE data, VALUE parent, VALUE opt);
VALUE rb_iseq_parameters(const rb_iseq_t *iseq, int is_proc);
unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);
#ifdef USE_ISEQ_NODE_ID
int rb_iseq_node_id(const rb_iseq_t *iseq, size_t pos);
#endif
void rb_iseq_trace_set(const rb_iseq_t *iseq, rb_event_flag_t turnon_events);
void rb_iseq_trace_set_all(rb_event_flag_t turnon_events);
void rb_iseq_insns_info_encode_positions(const rb_iseq_t *iseq);

struct rb_iseq_constant_body *rb_iseq_constant_body_alloc(void);
VALUE rb_iseqw_new(const rb_iseq_t *iseq);
const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);

VALUE rb_iseq_absolute_path(const rb_iseq_t *iseq); /* obsolete */
int rb_iseq_from_eval_p(const rb_iseq_t *iseq);
VALUE rb_iseq_type(const rb_iseq_t *iseq);
VALUE rb_iseq_label(const rb_iseq_t *iseq);
VALUE rb_iseq_base_label(const rb_iseq_t *iseq);
VALUE rb_iseq_first_lineno(const rb_iseq_t *iseq);
VALUE rb_iseq_method_name(const rb_iseq_t *iseq);
void rb_iseq_code_location(const rb_iseq_t *iseq, int *first_lineno, int *first_column, int *last_lineno, int *last_column);

void rb_iseq_remove_coverage_all(void);

/* proc.c */
const rb_iseq_t *rb_method_iseq(VALUE body);
const rb_iseq_t *rb_proc_get_iseq(VALUE proc, int *is_proc);

struct rb_compile_option_struct {
    unsigned int inline_const_cache: 1;
    unsigned int peephole_optimization: 1;
    unsigned int tailcall_optimization: 1;
    unsigned int specialized_instruction: 1;
    unsigned int operands_unification: 1;
    unsigned int instructions_unification: 1;
    signed int frozen_string_literal: 2; /* -1: not specified, 0: false, 1: true */
    unsigned int debug_frozen_string_literal: 1;
    unsigned int coverage_enabled: 1;
    int debug_level;
};

struct iseq_insn_info_entry {
    int line_no;
#ifdef USE_ISEQ_NODE_ID
    int node_id;
#endif
    rb_event_flag_t events;
};

/*
 * iseq type:
 *   CATCH_TYPE_RESCUE, CATCH_TYPE_ENSURE:
 *     use iseq as continuation.
 *
 *   CATCH_TYPE_BREAK (iter):
 *     use iseq as key.
 *
 *   CATCH_TYPE_BREAK (while), CATCH_TYPE_RETRY,
 *   CATCH_TYPE_REDO, CATCH_TYPE_NEXT:
 *     NULL.
 */
enum rb_catch_type {
    CATCH_TYPE_RESCUE = INT2FIX(1),
    CATCH_TYPE_ENSURE = INT2FIX(2),
    CATCH_TYPE_RETRY  = INT2FIX(3),
    CATCH_TYPE_BREAK  = INT2FIX(4),
    CATCH_TYPE_REDO   = INT2FIX(5),
    CATCH_TYPE_NEXT   = INT2FIX(6)
};

struct iseq_catch_table_entry {
    enum rb_catch_type type;
    rb_iseq_t *iseq;

    unsigned int start;
    unsigned int end;
    unsigned int cont;
    unsigned int sp;
};

RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_BEGIN()
struct iseq_catch_table {
    unsigned int size;
    struct iseq_catch_table_entry entries[FLEX_ARY_LEN];
} RBIMPL_ATTR_PACKED_STRUCT_UNALIGNED_END();

static inline int
iseq_catch_table_bytes(int n)
{
    enum {
        catch_table_entry_size = sizeof(struct iseq_catch_table_entry),
        catch_table_entries_max = (INT_MAX - offsetof(struct iseq_catch_table, entries)) / catch_table_entry_size
    };
    if (n > catch_table_entries_max) rb_fatal("too large iseq_catch_table - %d", n);
    return (int)(offsetof(struct iseq_catch_table, entries) +
                 n * catch_table_entry_size);
}

#define INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE (512)

struct iseq_compile_data_storage {
    struct iseq_compile_data_storage *next;
    unsigned int pos;
    unsigned int size;
    char buff[FLEX_ARY_LEN];
};

/* defined? */

enum defined_type {
    DEFINED_NOT_DEFINED,
    DEFINED_NIL = 1,
    DEFINED_IVAR,
    DEFINED_LVAR,
    DEFINED_GVAR,
    DEFINED_CVAR,
    DEFINED_CONST,
    DEFINED_METHOD,
    DEFINED_YIELD,
    DEFINED_ZSUPER,
    DEFINED_SELF,
    DEFINED_TRUE,
    DEFINED_FALSE,
    DEFINED_ASGN,
    DEFINED_EXPR,
    DEFINED_REF,
    DEFINED_FUNC,
    DEFINED_CONST_FROM
};

VALUE rb_iseq_defined_string(enum defined_type type);

/* vm.c */
VALUE rb_iseq_local_variables(const rb_iseq_t *iseq);

attr_index_t rb_estimate_iv_count(VALUE klass, const rb_iseq_t * initialize_iseq);

void rb_free_encoded_insn_data(void);

RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_ISEQ_H */
