/**********************************************************************

  iseq.h -

  $Author$
  created at: 04/01/01 23:36:57 JST

  Copyright (C) 2004-2008 Koichi Sasada

**********************************************************************/

#ifndef RUBY_ISEQ_H
#define RUBY_ISEQ_H 1

RUBY_EXTERN const int ruby_api_version[];
#define ISEQ_MAJOR_VERSION ((unsigned int)ruby_api_version[0])
#define ISEQ_MINOR_VERSION ((unsigned int)ruby_api_version[1])

#ifndef rb_iseq_t
typedef struct rb_iseq_struct rb_iseq_t;
#define rb_iseq_t rb_iseq_t
#endif

extern const ID rb_iseq_shared_exc_local_tbl[];

static inline size_t
rb_call_info_kw_arg_bytes(int keyword_len)
{
    return sizeof(struct rb_call_info_kw_arg) + sizeof(VALUE) * (keyword_len - 1);
}

#define ISEQ_COVERAGE(iseq)           iseq->body->variable.coverage
#define ISEQ_COVERAGE_SET(iseq, cov)  RB_OBJ_WRITE(iseq, &iseq->body->variable.coverage, cov)
#define ISEQ_LINE_COVERAGE(iseq)      RARRAY_AREF(ISEQ_COVERAGE(iseq), COVERAGE_INDEX_LINES)
#define ISEQ_BRANCH_COVERAGE(iseq)    RARRAY_AREF(ISEQ_COVERAGE(iseq), COVERAGE_INDEX_BRANCHES)

#define ISEQ_PC2BRANCHINDEX(iseq)         iseq->body->variable.pc2branchindex
#define ISEQ_PC2BRANCHINDEX_SET(iseq, h)  RB_OBJ_WRITE(iseq, &iseq->body->variable.pc2branchindex, h)

#define ISEQ_FLIP_CNT(iseq) (iseq)->body->variable.flip_count

static inline rb_snum_t
ISEQ_FLIP_CNT_INCREMENT(const rb_iseq_t *iseq)
{
    rb_snum_t cnt = iseq->body->variable.flip_count;
    iseq->body->variable.flip_count += 1;
    return cnt;
}

static inline VALUE *
ISEQ_ORIGINAL_ISEQ(const rb_iseq_t *iseq)
{
    return iseq->body->variable.original_iseq;
}

static inline void
ISEQ_ORIGINAL_ISEQ_CLEAR(const rb_iseq_t *iseq)
{
    void *ptr = iseq->body->variable.original_iseq;
    iseq->body->variable.original_iseq = NULL;
    if (ptr) {
        ruby_xfree(ptr);
    }
}

static inline VALUE *
ISEQ_ORIGINAL_ISEQ_ALLOC(const rb_iseq_t *iseq, long size)
{
    return iseq->body->variable.original_iseq =
        ruby_xmalloc2(size, sizeof(VALUE));
}

#define ISEQ_TRACE_EVENTS (RUBY_EVENT_LINE  | \
			   RUBY_EVENT_CLASS | \
			   RUBY_EVENT_END   | \
			   RUBY_EVENT_CALL  | \
			   RUBY_EVENT_RETURN| \
			   RUBY_EVENT_B_CALL| \
			   RUBY_EVENT_B_RETURN| \
                           RUBY_EVENT_COVERAGE_LINE| \
                           RUBY_EVENT_COVERAGE_BRANCH)

#define ISEQ_NOT_LOADED_YET   IMEMO_FL_USER1
#define ISEQ_USE_COMPILE_DATA IMEMO_FL_USER2
#define ISEQ_TRANSLATED       IMEMO_FL_USER3
#define ISEQ_MARKABLE_ISEQ    IMEMO_FL_USER4

#define ISEQ_EXECUTABLE_P(iseq) (FL_TEST_RAW((iseq), ISEQ_NOT_LOADED_YET | ISEQ_USE_COMPILE_DATA) == 0)

struct iseq_compile_data {
    /* GC is needed */
    const VALUE err_info;
    VALUE mark_ary;
    const VALUE catch_table_ary;	/* Array */

    /* GC is not needed */
    struct iseq_label_data *start_label;
    struct iseq_label_data *end_label;
    struct iseq_label_data *redo_label;
    const rb_iseq_t *current_block;
    struct iseq_compile_data_ensure_node_stack *ensure_node_stack;
    struct iseq_compile_data_storage *storage_head;
    struct iseq_compile_data_storage *storage_current;
    int loopval_popped;	/* used by NODE_BREAK */
    int last_line;
    int label_no;
    int node_level;
    unsigned int ci_index;
    unsigned int ci_kw_index;
    const rb_compile_option_t *option;
    struct rb_id_table *ivar_cache_table;
#if SUPPORT_JOKE
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
    return (rb_iseq_t *)rb_imemo_new(imemo_iseq, 0, 0, 0, 0);
}

VALUE rb_iseq_ibf_dump(const rb_iseq_t *iseq, VALUE opt);
void rb_ibf_load_iseq_complete(rb_iseq_t *iseq);
const rb_iseq_t *rb_iseq_ibf_load(VALUE str);
VALUE rb_iseq_ibf_load_extra_data(VALUE str);
void rb_iseq_init_trace(rb_iseq_t *iseq);
int rb_iseq_add_local_tracepoint_recursively(const rb_iseq_t *iseq, rb_event_flag_t turnon_events, VALUE tpval, unsigned int target_line);
int rb_iseq_remove_local_tracepoint_recursively(const rb_iseq_t *iseq, VALUE tpval);
const rb_iseq_t *rb_iseq_load_iseq(VALUE fname);

#if VM_INSN_INFO_TABLE_IMPL == 2
unsigned int *rb_iseq_insns_info_decode_positions(const struct rb_iseq_constant_body *body);
#endif

RUBY_SYMBOL_EXPORT_BEGIN

/* compile.c */
VALUE rb_iseq_compile_node(rb_iseq_t *iseq, const NODE *node);
VALUE rb_iseq_compile_ifunc(rb_iseq_t *iseq, const struct vm_ifunc *ifunc);
int rb_iseq_translate_threaded_code(rb_iseq_t *iseq);
VALUE *rb_iseq_original_iseq(const rb_iseq_t *iseq);
void rb_iseq_build_from_ary(rb_iseq_t *iseq, VALUE misc,
			    VALUE locals, VALUE args,
			    VALUE exception, VALUE body);

/* iseq.c */
VALUE rb_iseq_load(VALUE data, VALUE parent, VALUE opt);
VALUE rb_iseq_parameters(const rb_iseq_t *iseq, int is_proc);
struct st_table *ruby_insn_make_insn_table(void);
unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);
void rb_iseq_trace_set(const rb_iseq_t *iseq, rb_event_flag_t turnon_events);
void rb_iseq_trace_set_all(rb_event_flag_t turnon_events);
void rb_iseq_trace_on_all(void);
void rb_iseq_insns_info_encode_positions(const rb_iseq_t *iseq);

VALUE rb_iseqw_new(const rb_iseq_t *iseq);
const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);

VALUE rb_iseq_absolute_path(const rb_iseq_t *iseq); /* obsolete */
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
    unsigned int stack_caching: 1;
    unsigned int frozen_string_literal: 1;
    unsigned int debug_frozen_string_literal: 1;
    unsigned int coverage_enabled: 1;
    int debug_level;
};

struct iseq_insn_info_entry {
    int line_no;
    rb_event_flag_t events;
};

struct iseq_catch_table_entry {
    enum catch_type {
	CATCH_TYPE_RESCUE = INT2FIX(1),
	CATCH_TYPE_ENSURE = INT2FIX(2),
	CATCH_TYPE_RETRY  = INT2FIX(3),
	CATCH_TYPE_BREAK  = INT2FIX(4),
	CATCH_TYPE_REDO   = INT2FIX(5),
	CATCH_TYPE_NEXT   = INT2FIX(6)
    } type;

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
    rb_iseq_t *iseq;

    unsigned int start;
    unsigned int end;
    unsigned int cont;
    unsigned int sp;
};

PACKED_STRUCT_UNALIGNED(struct iseq_catch_table {
    unsigned int size;
    struct iseq_catch_table_entry entries[FLEX_ARY_LEN];
});

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
    DEFINED_IVAR2,
    DEFINED_REF,
    DEFINED_FUNC
};

VALUE rb_iseq_defined_string(enum defined_type type);
void rb_iseq_make_compile_option(struct rb_compile_option_struct *option, VALUE opt);

/* vm.c */
VALUE rb_iseq_local_variables(const rb_iseq_t *iseq);

RUBY_SYMBOL_EXPORT_END

#endif /* RUBY_ISEQ_H */
