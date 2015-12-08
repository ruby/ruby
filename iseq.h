/**********************************************************************

  iseq.h -

  $Author$
  created at: 04/01/01 23:36:57 JST

  Copyright (C) 2004-2008 Koichi Sasada

**********************************************************************/

#ifndef RUBY_ISEQ_H
#define RUBY_ISEQ_H 1

#define ISEQ_MAJOR_VERSION 2
#define ISEQ_MINOR_VERSION 3

#ifndef rb_iseq_t
typedef struct rb_iseq_struct rb_iseq_t;
#define rb_iseq_t rb_iseq_t
#endif

static inline size_t
rb_call_info_kw_arg_bytes(int keyword_len)
{
    return sizeof(struct rb_call_info_kw_arg) + sizeof(VALUE) * (keyword_len - 1);
}

enum iseq_mark_ary_index {
    ISEQ_MARK_ARY_COVERAGE      = 0,
    ISEQ_MARK_ARY_FLIP_CNT      = 1,
    ISEQ_MARK_ARY_ORIGINAL_ISEQ = 2,
};

static inline VALUE
iseq_mark_ary_create(int flip_cnt)
{
    VALUE ary = rb_ary_tmp_new(3);
    rb_ary_push(ary, Qnil);              /* ISEQ_MARK_ARY_COVERAGE */
    rb_ary_push(ary, INT2FIX(flip_cnt)); /* ISEQ_MARK_ARY_FLIP_CNT */
    rb_ary_push(ary, Qnil);              /* ISEQ_MARK_ARY_ORIGINAL_ISEQ */
    return ary;
}

#define ISEQ_MARK_ARY(iseq)           (iseq)->body->mark_ary

#define ISEQ_COVERAGE(iseq)           RARRAY_AREF(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_COVERAGE)
#define ISEQ_COVERAGE_SET(iseq, cov)  RARRAY_ASET(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_COVERAGE, cov)

#define ISEQ_FLIP_CNT(iseq) FIX2INT(RARRAY_AREF(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_FLIP_CNT))

static inline int
ISEQ_FLIP_CNT_INCREMENT(const rb_iseq_t *iseq)
{
    int cnt = ISEQ_FLIP_CNT(iseq);
    RARRAY_ASET(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_FLIP_CNT, INT2FIX(cnt+1));
    return cnt;
}

static inline VALUE *
ISEQ_ORIGINAL_ISEQ(const rb_iseq_t *iseq)
{
    VALUE str = RARRAY_AREF(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_ORIGINAL_ISEQ);
    if (RTEST(str)) return (VALUE *)RSTRING_PTR(str);
    return NULL;
}

static inline VALUE *
ISEQ_ORIGINAL_ISEQ_ALLOC(const rb_iseq_t *iseq, long size)
{
    VALUE str = rb_str_tmp_new(size * sizeof(VALUE));
    RARRAY_ASET(ISEQ_MARK_ARY(iseq), ISEQ_MARK_ARY_ORIGINAL_ISEQ, str);
    return (VALUE *)RSTRING_PTR(str);
}

#define ISEQ_COMPILE_DATA(iseq)       (iseq)->aux.compile_data

static inline rb_iseq_t *
iseq_imemo_alloc(void)
{
    return (rb_iseq_t *)rb_imemo_new(imemo_iseq, 0, 0, 0, 0);
}

#define ISEQ_NOT_LOADED_YET   IMEMO_FL_USER1

VALUE iseq_ibf_dump(const rb_iseq_t *iseq, VALUE opt);
void ibf_load_iseq_complete(rb_iseq_t *iseq);
const rb_iseq_t *iseq_ibf_load(VALUE str);
VALUE iseq_ibf_load_extra_data(VALUE str);

RUBY_SYMBOL_EXPORT_BEGIN

/* compile.c */
VALUE rb_iseq_compile_node(rb_iseq_t *iseq, NODE *node);
int rb_iseq_translate_threaded_code(rb_iseq_t *iseq);
VALUE *rb_iseq_original_iseq(const rb_iseq_t *iseq);
void rb_iseq_build_from_ary(rb_iseq_t *iseq, VALUE misc,
			    VALUE locals, VALUE args,
			    VALUE exception, VALUE body);

/* iseq.c */
void rb_iseq_add_mark_object(const rb_iseq_t *iseq, VALUE obj);
VALUE rb_iseq_load(VALUE data, VALUE parent, VALUE opt);
VALUE rb_iseq_parameters(const rb_iseq_t *iseq, int is_proc);
struct st_table *ruby_insn_make_insn_table(void);
unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);

int rb_iseqw_line_trace_each(VALUE iseqval, int (*func)(int line, rb_event_flag_t *events_ptr, void *d), void *data);
VALUE rb_iseqw_line_trace_all(VALUE iseqval);
VALUE rb_iseqw_line_trace_specify(VALUE iseqval, VALUE pos, VALUE set);
VALUE rb_iseqw_new(const rb_iseq_t *iseq);
const rb_iseq_t *rb_iseqw_to_iseq(VALUE iseqw);

VALUE rb_iseq_path(const rb_iseq_t *iseq);
VALUE rb_iseq_absolute_path(const rb_iseq_t *iseq);
VALUE rb_iseq_label(const rb_iseq_t *iseq);
VALUE rb_iseq_base_label(const rb_iseq_t *iseq);
VALUE rb_iseq_first_lineno(const rb_iseq_t *iseq);
VALUE rb_iseq_method_name(const rb_iseq_t *iseq);

/* proc.c */
const rb_iseq_t *rb_method_iseq(VALUE body);
const rb_iseq_t *rb_proc_get_iseq(VALUE proc, int *is_proc);

struct rb_compile_option_struct {
    int inline_const_cache;
    int peephole_optimization;
    int tailcall_optimization;
    int specialized_instruction;
    int operands_unification;
    int instructions_unification;
    int stack_caching;
    int trace_instruction;
    int frozen_string_literal;
    int debug_frozen_string_literal;
    int debug_level;
};

struct iseq_line_info_entry {
    unsigned int position;
    unsigned int line_no;
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
    const rb_iseq_t *iseq;
    unsigned int start;
    unsigned int end;
    unsigned int cont;
    unsigned int sp;
};

PACKED_STRUCT_UNALIGNED(struct iseq_catch_table {
    unsigned int size;
    struct iseq_catch_table_entry entries[1]; /* flexible array */
});

static inline int
iseq_catch_table_bytes(int n)
{
    enum {
	catch_table_entries_max = (INT_MAX - sizeof(struct iseq_catch_table)) / sizeof(struct iseq_catch_table_entry)
    };
    if (n > catch_table_entries_max) rb_fatal("too large iseq_catch_table - %d", n);
    return (int)(sizeof(struct iseq_catch_table) +
		 (n - 1) * sizeof(struct iseq_catch_table_entry));
}

#define INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE (512)

struct iseq_compile_data_storage {
    struct iseq_compile_data_storage *next;
    unsigned int pos;
    unsigned int size;
    char buff[1]; /* flexible array */
};

/* account for flexible array */
#define SIZEOF_ISEQ_COMPILE_DATA_STORAGE \
    (sizeof(struct iseq_compile_data_storage) - 1)

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
    VALUE ensure_node;
    VALUE for_iseq;
    struct iseq_compile_data_ensure_node_stack *ensure_node_stack;
    int loopval_popped;	/* used by NODE_BREAK */
    int cached_const;
    struct iseq_compile_data_storage *storage_head;
    struct iseq_compile_data_storage *storage_current;
    int last_line;
    int last_coverable_line;
    int label_no;
    int node_level;
    unsigned int ci_index;
    unsigned int ci_kw_index;
    const rb_compile_option_t *option;
#if SUPPORT_JOKE
    st_table *labels_table;
#endif
};

/* defined? */

enum defined_type {
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
