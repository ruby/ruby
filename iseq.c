/**********************************************************************

  iseq.c -

  $Author$
  created at: 2006-07-11(Tue) 09:00:03 +0900

  Copyright (C) 2006 Koichi Sasada

**********************************************************************/

#include "internal.h"
#include "ruby/util.h"
#include "eval_intern.h"

#ifdef HAVE_DLADDR
# include <dlfcn.h>
#endif

#define RUBY_VM_INSNS_INFO 1
/* #define RUBY_MARK_FREE_DEBUG 1 */
#include "gc.h"
#include "vm_core.h"
#include "iseq.h"
#include "id_table.h"

#include "insns.inc"
#include "insns_info.inc"
#include "mjit.h"

VALUE rb_cISeq;
static VALUE iseqw_new(const rb_iseq_t *iseq);
static const rb_iseq_t *iseqw_check(VALUE iseqw);

#if VM_INSN_INFO_TABLE_IMPL == 2
static struct succ_index_table *succ_index_table_create(int max_pos, int *data, int size);
static unsigned int *succ_index_table_invert(int max_pos, struct succ_index_table *sd, int size);
static int succ_index_lookup(const struct succ_index_table *sd, int x);
#endif

#define hidden_obj_p(obj) (!SPECIAL_CONST_P(obj) && !RBASIC(obj)->klass)

static inline VALUE
obj_resurrect(VALUE obj)
{
    if (hidden_obj_p(obj)) {
	switch (BUILTIN_TYPE(obj)) {
	  case T_STRING:
	    obj = rb_str_resurrect(obj);
	    break;
	  case T_ARRAY:
	    obj = rb_ary_resurrect(obj);
	    break;
          case T_HASH:
            obj = rb_hash_resurrect(obj);
            break;
	}
    }
    return obj;
}

static void
compile_data_free(struct iseq_compile_data *compile_data)
{
    if (compile_data) {
	struct iseq_compile_data_storage *cur, *next;
	cur = compile_data->storage_head;
	while (cur) {
	    next = cur->next;
	    ruby_xfree(cur);
	    cur = next;
	}
	if (compile_data->ivar_cache_table) {
	    rb_id_table_free(compile_data->ivar_cache_table);
	}
	ruby_xfree(compile_data);
    }
}

void
rb_iseq_free(const rb_iseq_t *iseq)
{
    RUBY_FREE_ENTER("iseq");

    if (iseq && iseq->body) {
	struct rb_iseq_constant_body *const body = iseq->body;
	mjit_free_iseq(iseq); /* Notify MJIT */
	ruby_xfree((void *)body->iseq_encoded);
	ruby_xfree((void *)body->insns_info.body);
	if (body->insns_info.positions) ruby_xfree((void *)body->insns_info.positions);
#if VM_INSN_INFO_TABLE_IMPL == 2
	if (body->insns_info.succ_index_table) ruby_xfree(body->insns_info.succ_index_table);
#endif
        if (LIKELY(body->local_table != rb_iseq_shared_exc_local_tbl))
            ruby_xfree((void *)body->local_table);
	ruby_xfree((void *)body->is_entries);

	if (body->ci_entries) {
	    unsigned int i;
	    struct rb_call_info_with_kwarg *ci_kw_entries = (struct rb_call_info_with_kwarg *)&body->ci_entries[body->ci_size];
	    for (i=0; i<body->ci_kw_size; i++) {
		const struct rb_call_info_kw_arg *kw_arg = ci_kw_entries[i].kw_arg;
		ruby_xfree((void *)kw_arg);
	    }
	    ruby_xfree(body->ci_entries);
	    ruby_xfree(body->cc_entries);
	}
	ruby_xfree((void *)body->catch_table);
	ruby_xfree((void *)body->param.opt_table);

	if (body->param.keyword != NULL) {
	    ruby_xfree((void *)body->param.keyword->default_values);
	    ruby_xfree((void *)body->param.keyword);
	}
	compile_data_free(ISEQ_COMPILE_DATA(iseq));
	ruby_xfree(body);
    }

    if (iseq && ISEQ_EXECUTABLE_P(iseq) && iseq->aux.exec.local_hooks) {
        rb_hook_list_free(iseq->aux.exec.local_hooks);
    }

    RUBY_FREE_LEAVE("iseq");
}

#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
static VALUE
rb_vm_insn_addr2insn2(const void *addr)
{
    return (VALUE)rb_vm_insn_addr2insn(addr);
}
#endif

static VALUE
rb_vm_insn_null_translator(const void *addr)
{
    return (VALUE)addr;
}

typedef VALUE iseq_value_itr_t(void *ctx, VALUE obj);
typedef VALUE rb_vm_insns_translator_t(const void *addr);

static int
iseq_extract_values(VALUE *code, size_t pos, iseq_value_itr_t * func, void *data, rb_vm_insns_translator_t * translator)
{
    VALUE insn = translator((void *)code[pos]);
    int len = insn_len(insn);
    int op_no;
    const char *types = insn_op_types(insn);

    for (op_no = 0; types[op_no]; op_no++) {
	char type = types[op_no];
	switch (type) {
	    case TS_CDHASH:
	    case TS_ISEQ:
	    case TS_VALUE:
		{
		    VALUE op = code[pos + op_no + 1];
		    if (!SPECIAL_CONST_P(op)) {
                        VALUE newop = func(data, op);
                        if (newop != op) {
                            code[pos + op_no + 1] = newop;
                        }
		    }
		    break;
		}
	    case TS_ISE:
		{
		    union iseq_inline_storage_entry *const is = (union iseq_inline_storage_entry *)code[pos + op_no + 1];
		    if (is->once.value) {
                        VALUE nv = func(data, is->once.value);
                        if (is->once.value != nv) {
                            is->once.value = nv;
                        }
		    }
		    break;
		}
	    default:
		break;
	}
    }

    return len;
}

static void
rb_iseq_each_value(const rb_iseq_t *iseq, iseq_value_itr_t * func, void *data)
{
    unsigned int size;
    VALUE *code;
    size_t n;
    rb_vm_insns_translator_t * translator;
    const struct rb_iseq_constant_body *const body = iseq->body;

    size = body->iseq_size;
    code = body->iseq_encoded;

#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    if (FL_TEST(iseq, ISEQ_TRANSLATED)) {
	translator = rb_vm_insn_addr2insn2;
    }
    else {
	translator = rb_vm_insn_null_translator;
    }
#else
    translator = rb_vm_insn_null_translator;
#endif

    for (n = 0; n < size;) {
	n += iseq_extract_values(code, n, func, data, translator);
    }
}

static VALUE
update_each_insn_value(void *ctx, VALUE obj)
{
    return rb_gc_location(obj);
}

void
rb_iseq_update_references(rb_iseq_t *iseq)
{
    if (iseq->body) {
        struct rb_iseq_constant_body *body = iseq->body;

        body->variable.coverage = rb_gc_location(body->variable.coverage);
        body->variable.pc2branchindex = rb_gc_location(body->variable.pc2branchindex);
        body->location.label = rb_gc_location(body->location.label);
        body->location.base_label = rb_gc_location(body->location.base_label);
        body->location.pathobj = rb_gc_location(body->location.pathobj);
        if (body->local_iseq) {
            body->local_iseq = (struct rb_iseq_struct *)rb_gc_location((VALUE)body->local_iseq);
        }
        if (body->parent_iseq) {
            body->parent_iseq = (struct rb_iseq_struct *)rb_gc_location((VALUE)body->parent_iseq);
        }
        if (FL_TEST(iseq, ISEQ_MARKABLE_ISEQ)) {
            rb_iseq_each_value(iseq, update_each_insn_value, NULL);
        }

        if (body->param.flags.has_kw && ISEQ_COMPILE_DATA(iseq) == NULL) {
            int i, j;

            i = body->param.keyword->required_num;

            for (j = 0; i < body->param.keyword->num; i++, j++) {
                VALUE obj = body->param.keyword->default_values[j];
                if (obj != Qundef) {
                    body->param.keyword->default_values[j] = rb_gc_location(obj);
                }
            }
        }

        if (body->catch_table) {
            struct iseq_catch_table *table = body->catch_table;
            unsigned int i;
            for(i = 0; i < table->size; i++) {
                struct iseq_catch_table_entry *entry;
                entry = UNALIGNED_MEMBER_PTR(table, entries[i]);
                if (entry->iseq) {
                    entry->iseq = (rb_iseq_t *)rb_gc_location((VALUE)entry->iseq);
                }
            }
        }
#if USE_MJIT
        mjit_update_references(iseq);
#endif
    }
}

static VALUE
each_insn_value(void *ctx, VALUE obj)
{
    rb_gc_mark_movable(obj);
    return obj;
}

void
rb_iseq_mark(const rb_iseq_t *iseq)
{
    RUBY_MARK_ENTER("iseq");

    RUBY_MARK_UNLESS_NULL(iseq->wrapper);

    if (iseq->body) {
	const struct rb_iseq_constant_body *const body = iseq->body;

	if (FL_TEST(iseq, ISEQ_MARKABLE_ISEQ)) {
	    rb_iseq_each_value(iseq, each_insn_value, NULL);
	}

        rb_gc_mark_movable(body->variable.coverage);
        rb_gc_mark_movable(body->variable.pc2branchindex);
        rb_gc_mark_movable(body->location.label);
        rb_gc_mark_movable(body->location.base_label);
        rb_gc_mark_movable(body->location.pathobj);
        RUBY_MARK_NO_PIN_UNLESS_NULL((VALUE)body->parent_iseq);

	if (body->param.flags.has_kw && ISEQ_COMPILE_DATA(iseq) == NULL) {
	    const struct rb_iseq_param_keyword *const keyword = body->param.keyword;
	    int i, j;

	    i = keyword->required_num;

	    for (j = 0; i < keyword->num; i++, j++) {
		VALUE obj = keyword->default_values[j];
		if (!SPECIAL_CONST_P(obj)) {
                    rb_gc_mark_movable(obj);
		}
	    }
	}

	if (body->catch_table) {
	    const struct iseq_catch_table *table = body->catch_table;
	    unsigned int i;
	    for(i = 0; i < table->size; i++) {
		const struct iseq_catch_table_entry *entry;
		entry = UNALIGNED_MEMBER_PTR(table, entries[i]);
		if (entry->iseq) {
                    rb_gc_mark_movable((VALUE)entry->iseq);
		}
	    }
	}
    }

    if (FL_TEST_RAW(iseq, ISEQ_NOT_LOADED_YET)) {
	rb_gc_mark(iseq->aux.loader.obj);
    }
    else if (FL_TEST_RAW(iseq, ISEQ_USE_COMPILE_DATA)) {
	const struct iseq_compile_data *const compile_data = ISEQ_COMPILE_DATA(iseq);
        if (RTEST(compile_data->mark_ary)) {
            rb_gc_mark(compile_data->mark_ary);
        }
        RUBY_MARK_UNLESS_NULL(compile_data->err_info);
        if (RTEST(compile_data->catch_table_ary)) {
            rb_gc_mark(compile_data->catch_table_ary);
        }
        VM_ASSERT(compile_data != NULL);
    }
    else {
        /* executable */
        VM_ASSERT(ISEQ_EXECUTABLE_P(iseq));
        if (iseq->aux.exec.local_hooks) {
            rb_hook_list_mark(iseq->aux.exec.local_hooks);
        }
    }

    RUBY_MARK_LEAVE("iseq");
}

static size_t
param_keyword_size(const struct rb_iseq_param_keyword *pkw)
{
    size_t size = 0;

    if (!pkw) return size;

    size += sizeof(struct rb_iseq_param_keyword);
    size += sizeof(VALUE) * (pkw->num - pkw->required_num);

    return size;
}

size_t
rb_iseq_memsize(const rb_iseq_t *iseq)
{
    size_t size = 0; /* struct already counted as RVALUE size */
    const struct rb_iseq_constant_body *body = iseq->body;
    const struct iseq_compile_data *compile_data;

    /* TODO: should we count original_iseq? */

    if (ISEQ_EXECUTABLE_P(iseq) && body) {
        struct rb_call_info_with_kwarg *ci_kw_entries = (struct rb_call_info_with_kwarg *)&body->ci_entries[body->ci_size];

        size += sizeof(struct rb_iseq_constant_body);
        size += body->iseq_size * sizeof(VALUE);
        size += body->insns_info.size * (sizeof(struct iseq_insn_info_entry) + sizeof(unsigned int));
        size += body->local_table_size * sizeof(ID);
        if (body->catch_table) {
            size += iseq_catch_table_bytes(body->catch_table->size);
        }
        size += (body->param.opt_num + 1) * sizeof(VALUE);
        size += param_keyword_size(body->param.keyword);

        /* body->is_entries */
        size += body->is_size * sizeof(union iseq_inline_storage_entry);

        /* body->ci_entries */
        size += body->ci_size * sizeof(struct rb_call_info);
        size += body->ci_kw_size * sizeof(struct rb_call_info_with_kwarg);

        /* body->cc_entries */
        size += body->ci_size * sizeof(struct rb_call_cache);
        size += body->ci_kw_size * sizeof(struct rb_call_cache);

        if (ci_kw_entries) {
            unsigned int i;

            for (i = 0; i < body->ci_kw_size; i++) {
                const struct rb_call_info_kw_arg *kw_arg = ci_kw_entries[i].kw_arg;

                if (kw_arg) {
                    size += rb_call_info_kw_arg_bytes(kw_arg->keyword_len);
                }
            }
        }
    }

    compile_data = ISEQ_COMPILE_DATA(iseq);
    if (compile_data) {
	struct iseq_compile_data_storage *cur;

	size += sizeof(struct iseq_compile_data);

	cur = compile_data->storage_head;
	while (cur) {
	    size += cur->size + offsetof(struct iseq_compile_data_storage, buff);
	    cur = cur->next;
	}
    }

    return size;
}

static rb_iseq_t *
iseq_alloc(void)
{
    rb_iseq_t *iseq = iseq_imemo_alloc();
    iseq->body = ZALLOC(struct rb_iseq_constant_body);
    return iseq;
}

VALUE
rb_iseq_pathobj_new(VALUE path, VALUE realpath)
{
    VALUE pathobj;
    VM_ASSERT(RB_TYPE_P(path, T_STRING));
    VM_ASSERT(realpath == Qnil || RB_TYPE_P(realpath, T_STRING));

    if (path == realpath ||
	(!NIL_P(realpath) && rb_str_cmp(path, realpath) == 0)) {
	pathobj = rb_fstring(path);
    }
    else {
	if (!NIL_P(realpath)) realpath = rb_fstring(realpath);
	pathobj = rb_ary_new_from_args(2, rb_fstring(path), realpath);
	rb_obj_freeze(pathobj);
    }
    return pathobj;
}

void
rb_iseq_pathobj_set(const rb_iseq_t *iseq, VALUE path, VALUE realpath)
{
    RB_OBJ_WRITE(iseq, &iseq->body->location.pathobj,
		 rb_iseq_pathobj_new(path, realpath));
}

static rb_iseq_location_t *
iseq_location_setup(rb_iseq_t *iseq, VALUE name, VALUE path, VALUE realpath, VALUE first_lineno, const rb_code_location_t *code_location, const int node_id)
{
    rb_iseq_location_t *loc = &iseq->body->location;

    rb_iseq_pathobj_set(iseq, path, realpath);
    RB_OBJ_WRITE(iseq, &loc->label, name);
    RB_OBJ_WRITE(iseq, &loc->base_label, name);
    loc->first_lineno = first_lineno;
    if (code_location) {
        loc->node_id = node_id;
	loc->code_location = *code_location;
    }
    else {
	loc->code_location.beg_pos.lineno = 0;
	loc->code_location.beg_pos.column = 0;
	loc->code_location.end_pos.lineno = -1;
	loc->code_location.end_pos.column = -1;
    }

    return loc;
}

static void
set_relation(rb_iseq_t *iseq, const rb_iseq_t *piseq)
{
    struct rb_iseq_constant_body *const body = iseq->body;
    const VALUE type = body->type;

    /* set class nest stack */
    if (type == ISEQ_TYPE_TOP) {
	body->local_iseq = iseq;
    }
    else if (type == ISEQ_TYPE_METHOD || type == ISEQ_TYPE_CLASS) {
	body->local_iseq = iseq;
    }
    else if (piseq) {
	body->local_iseq = piseq->body->local_iseq;
    }

    if (piseq) {
	body->parent_iseq = piseq;
    }

    if (type == ISEQ_TYPE_MAIN) {
	body->local_iseq = iseq;
    }
}

static VALUE
prepare_iseq_build(rb_iseq_t *iseq,
                   VALUE name, VALUE path, VALUE realpath, VALUE first_lineno, const rb_code_location_t *code_location, const int node_id,
		   const rb_iseq_t *parent, enum iseq_type type,
		   const rb_compile_option_t *option)
{
    VALUE coverage = Qfalse;
    VALUE err_info = Qnil;
    struct rb_iseq_constant_body *const body = iseq->body;

    if (parent && (type == ISEQ_TYPE_MAIN || type == ISEQ_TYPE_TOP))
	err_info = Qfalse;

    body->type = type;
    set_relation(iseq, parent);

    name = rb_fstring(name);
    iseq_location_setup(iseq, name, path, realpath, first_lineno, code_location, node_id);
    if (iseq != body->local_iseq) {
	RB_OBJ_WRITE(iseq, &body->location.base_label, body->local_iseq->body->location.label);
    }
    ISEQ_COVERAGE_SET(iseq, Qnil);
    ISEQ_ORIGINAL_ISEQ_CLEAR(iseq);
    body->variable.flip_count = 0;

    ISEQ_COMPILE_DATA_ALLOC(iseq);
    RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->err_info, err_info);
    RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->mark_ary, rb_ary_tmp_new(3));

    ISEQ_COMPILE_DATA(iseq)->storage_head = ISEQ_COMPILE_DATA(iseq)->storage_current =
      (struct iseq_compile_data_storage *)
	ALLOC_N(char, INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE +
		offsetof(struct iseq_compile_data_storage, buff));

    RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->catch_table_ary, Qnil);
    ISEQ_COMPILE_DATA(iseq)->storage_head->pos = 0;
    ISEQ_COMPILE_DATA(iseq)->storage_head->next = 0;
    ISEQ_COMPILE_DATA(iseq)->storage_head->size =
      INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE;
    ISEQ_COMPILE_DATA(iseq)->option = option;

    ISEQ_COMPILE_DATA(iseq)->ivar_cache_table = NULL;

    if (option->coverage_enabled) {
	VALUE coverages = rb_get_coverages();
	if (RTEST(coverages)) {
	    coverage = rb_hash_lookup(coverages, rb_iseq_path(iseq));
	    if (NIL_P(coverage)) coverage = Qfalse;
	}
    }
    ISEQ_COVERAGE_SET(iseq, coverage);
    if (coverage && ISEQ_BRANCH_COVERAGE(iseq))
        ISEQ_PC2BRANCHINDEX_SET(iseq, rb_ary_tmp_new(0));

    return Qtrue;
}

#if VM_CHECK_MODE > 0 && VM_INSN_INFO_TABLE_IMPL > 0
static void validate_get_insn_info(const rb_iseq_t *iseq);
#endif

void
rb_iseq_insns_info_encode_positions(const rb_iseq_t *iseq)
{
#if VM_INSN_INFO_TABLE_IMPL == 2
    struct rb_iseq_constant_body *const body = iseq->body;
    int size = body->insns_info.size;
    int max_pos = body->iseq_size;
    int *data = (int *)body->insns_info.positions;
    if (body->insns_info.succ_index_table) ruby_xfree(body->insns_info.succ_index_table);
    body->insns_info.succ_index_table = succ_index_table_create(max_pos, data, size);
#if VM_CHECK_MODE == 0
    ruby_xfree(body->insns_info.positions);
    body->insns_info.positions = NULL;
#endif
#endif
}

#if VM_INSN_INFO_TABLE_IMPL == 2
unsigned int *
rb_iseq_insns_info_decode_positions(const struct rb_iseq_constant_body *body)
{
    int size = body->insns_info.size;
    int max_pos = body->iseq_size;
    struct succ_index_table *sd = body->insns_info.succ_index_table;
    return succ_index_table_invert(max_pos, sd, size);
}
#endif

void
rb_iseq_init_trace(rb_iseq_t *iseq)
{
    iseq->aux.exec.global_trace_events = 0;
    if (ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS) {
        rb_iseq_trace_set(iseq, ruby_vm_event_enabled_global_flags & ISEQ_TRACE_EVENTS);
    }
}

static VALUE
finish_iseq_build(rb_iseq_t *iseq)
{
    struct iseq_compile_data *data = ISEQ_COMPILE_DATA(iseq);
    const struct rb_iseq_constant_body *const body = iseq->body;
    VALUE err = data->err_info;
    ISEQ_COMPILE_DATA_CLEAR(iseq);
    compile_data_free(data);

#if VM_INSN_INFO_TABLE_IMPL == 2 /* succinct bitvector */
    /* create succ_index_table */
    if (body->insns_info.succ_index_table == NULL) {
	rb_iseq_insns_info_encode_positions(iseq);
    }
#endif

#if VM_CHECK_MODE > 0 && VM_INSN_INFO_TABLE_IMPL > 0
    validate_get_insn_info(iseq);
#endif

    if (RTEST(err)) {
	VALUE path = pathobj_path(body->location.pathobj);
	if (err == Qtrue) err = rb_exc_new_cstr(rb_eSyntaxError, "compile error");
	rb_funcallv(err, rb_intern("set_backtrace"), 1, &path);
	rb_exc_raise(err);
    }

    rb_iseq_init_trace(iseq);
    return Qtrue;
}

static rb_compile_option_t COMPILE_OPTION_DEFAULT = {
    OPT_INLINE_CONST_CACHE, /* int inline_const_cache; */
    OPT_PEEPHOLE_OPTIMIZATION, /* int peephole_optimization; */
    OPT_TAILCALL_OPTIMIZATION, /* int tailcall_optimization */
    OPT_SPECIALISED_INSTRUCTION, /* int specialized_instruction; */
    OPT_OPERANDS_UNIFICATION, /* int operands_unification; */
    OPT_INSTRUCTIONS_UNIFICATION, /* int instructions_unification; */
    OPT_STACK_CACHING, /* int stack_caching; */
    OPT_FROZEN_STRING_LITERAL,
    OPT_DEBUG_FROZEN_STRING_LITERAL,
    TRUE,			/* coverage_enabled */
};

static const rb_compile_option_t COMPILE_OPTION_FALSE = {0};

static void
set_compile_option_from_hash(rb_compile_option_t *option, VALUE opt)
{
#define SET_COMPILE_OPTION(o, h, mem) \
  { VALUE flag = rb_hash_aref((h), ID2SYM(rb_intern(#mem))); \
      if (flag == Qtrue)  { (o)->mem = 1; } \
      else if (flag == Qfalse)  { (o)->mem = 0; } \
  }
#define SET_COMPILE_OPTION_NUM(o, h, mem) \
  { VALUE num = rb_hash_aref(opt, ID2SYM(rb_intern(#mem))); \
      if (!NIL_P(num)) (o)->mem = NUM2INT(num); \
  }
    SET_COMPILE_OPTION(option, opt, inline_const_cache);
    SET_COMPILE_OPTION(option, opt, peephole_optimization);
    SET_COMPILE_OPTION(option, opt, tailcall_optimization);
    SET_COMPILE_OPTION(option, opt, specialized_instruction);
    SET_COMPILE_OPTION(option, opt, operands_unification);
    SET_COMPILE_OPTION(option, opt, instructions_unification);
    SET_COMPILE_OPTION(option, opt, stack_caching);
    SET_COMPILE_OPTION(option, opt, frozen_string_literal);
    SET_COMPILE_OPTION(option, opt, debug_frozen_string_literal);
    SET_COMPILE_OPTION(option, opt, coverage_enabled);
    SET_COMPILE_OPTION_NUM(option, opt, debug_level);
#undef SET_COMPILE_OPTION
#undef SET_COMPILE_OPTION_NUM
}

void
rb_iseq_make_compile_option(rb_compile_option_t *option, VALUE opt)
{
    Check_Type(opt, T_HASH);
    set_compile_option_from_hash(option, opt);
}

static void
make_compile_option(rb_compile_option_t *option, VALUE opt)
{
    if (opt == Qnil) {
	*option = COMPILE_OPTION_DEFAULT;
    }
    else if (opt == Qfalse) {
	*option = COMPILE_OPTION_FALSE;
    }
    else if (opt == Qtrue) {
	int i;
	for (i = 0; i < (int)(sizeof(rb_compile_option_t) / sizeof(int)); ++i)
	    ((int *)option)[i] = 1;
    }
    else if (RB_TYPE_P(opt, T_HASH)) {
	*option = COMPILE_OPTION_DEFAULT;
	set_compile_option_from_hash(option, opt);
    }
    else {
	rb_raise(rb_eTypeError, "Compile option must be Hash/true/false/nil");
    }
}

static VALUE
make_compile_option_value(rb_compile_option_t *option)
{
    VALUE opt = rb_hash_new();
#define SET_COMPILE_OPTION(o, h, mem) \
  rb_hash_aset((h), ID2SYM(rb_intern(#mem)), (o)->mem ? Qtrue : Qfalse)
#define SET_COMPILE_OPTION_NUM(o, h, mem) \
  rb_hash_aset((h), ID2SYM(rb_intern(#mem)), INT2NUM((o)->mem))
    {
	SET_COMPILE_OPTION(option, opt, inline_const_cache);
	SET_COMPILE_OPTION(option, opt, peephole_optimization);
	SET_COMPILE_OPTION(option, opt, tailcall_optimization);
	SET_COMPILE_OPTION(option, opt, specialized_instruction);
	SET_COMPILE_OPTION(option, opt, operands_unification);
	SET_COMPILE_OPTION(option, opt, instructions_unification);
	SET_COMPILE_OPTION(option, opt, stack_caching);
	SET_COMPILE_OPTION(option, opt, frozen_string_literal);
	SET_COMPILE_OPTION(option, opt, debug_frozen_string_literal);
	SET_COMPILE_OPTION(option, opt, coverage_enabled);
	SET_COMPILE_OPTION_NUM(option, opt, debug_level);
    }
#undef SET_COMPILE_OPTION
#undef SET_COMPILE_OPTION_NUM
    return opt;
}

rb_iseq_t *
rb_iseq_new(const rb_ast_body_t *ast, VALUE name, VALUE path, VALUE realpath,
	    const rb_iseq_t *parent, enum iseq_type type)
{
    return rb_iseq_new_with_opt(ast, name, path, realpath, INT2FIX(0), parent, type,
				&COMPILE_OPTION_DEFAULT);
}

rb_iseq_t *
rb_iseq_new_top(const rb_ast_body_t *ast, VALUE name, VALUE path, VALUE realpath, const rb_iseq_t *parent)
{
    VALUE coverages = rb_get_coverages();
    if (RTEST(coverages)) {
        if (ast->line_count >= 0) {
            int len = (rb_get_coverage_mode() & COVERAGE_TARGET_ONESHOT_LINES) ? 0 : ast->line_count;
            VALUE coverage = rb_default_coverage(len);
            rb_hash_aset(coverages, path, coverage);
        }
    }

    return rb_iseq_new_with_opt(ast, name, path, realpath, INT2FIX(0), parent, ISEQ_TYPE_TOP,
				&COMPILE_OPTION_DEFAULT);
}

rb_iseq_t *
rb_iseq_new_main(const rb_ast_body_t *ast, VALUE path, VALUE realpath, const rb_iseq_t *parent)
{
    return rb_iseq_new_with_opt(ast, rb_fstring_lit("<main>"),
				path, realpath, INT2FIX(0),
				parent, ISEQ_TYPE_MAIN, &COMPILE_OPTION_DEFAULT);
}

static inline rb_iseq_t *
iseq_translate(rb_iseq_t *iseq)
{
    if (rb_respond_to(rb_cISeq, rb_intern("translate"))) {
	VALUE v1 = iseqw_new(iseq);
	VALUE v2 = rb_funcall(rb_cISeq, rb_intern("translate"), 1, v1);
	if (v1 != v2 && CLASS_OF(v2) == rb_cISeq) {
	    iseq = (rb_iseq_t *)iseqw_check(v2);
	}
    }

    return iseq;
}

rb_iseq_t *
rb_iseq_new_with_opt(const rb_ast_body_t *ast, VALUE name, VALUE path, VALUE realpath,
		     VALUE first_lineno, const rb_iseq_t *parent,
		     enum iseq_type type, const rb_compile_option_t *option)
{
    const NODE *node = ast ? ast->root : 0;
    /* TODO: argument check */
    rb_iseq_t *iseq = iseq_alloc();
    rb_compile_option_t new_opt;

    new_opt = option ? *option : COMPILE_OPTION_DEFAULT;
    if (ast && ast->compile_option) rb_iseq_make_compile_option(&new_opt, ast->compile_option);

    prepare_iseq_build(iseq, name, path, realpath, first_lineno, node ? &node->nd_loc : NULL, node ? nd_node_id(node) : -1, parent, type, &new_opt);

    rb_iseq_compile_node(iseq, node);
    finish_iseq_build(iseq);

    return iseq_translate(iseq);
}

rb_iseq_t *
rb_iseq_new_ifunc(const struct vm_ifunc *ifunc, VALUE name, VALUE path, VALUE realpath,
		       VALUE first_lineno, const rb_iseq_t *parent,
		       enum iseq_type type, const rb_compile_option_t *option)
{
    /* TODO: argument check */
    rb_iseq_t *iseq = iseq_alloc();

    if (!option) option = &COMPILE_OPTION_DEFAULT;
    prepare_iseq_build(iseq, name, path, realpath, first_lineno, NULL, -1, parent, type, option);

    rb_iseq_compile_ifunc(iseq, ifunc);
    finish_iseq_build(iseq);

    return iseq_translate(iseq);
}

const rb_iseq_t *
rb_iseq_load_iseq(VALUE fname)
{
    VALUE iseqv = rb_check_funcall(rb_cISeq, rb_intern("load_iseq"), 1, &fname);

    if (!SPECIAL_CONST_P(iseqv) && RBASIC_CLASS(iseqv) == rb_cISeq) {
	return  iseqw_check(iseqv);
    }

    return NULL;
}

#define CHECK_ARRAY(v)   rb_to_array_type(v)
#define CHECK_HASH(v)    rb_to_hash_type(v)
#define CHECK_STRING(v)  rb_str_to_str(v)
#define CHECK_SYMBOL(v)  rb_to_symbol_type(v)
static inline VALUE CHECK_INTEGER(VALUE v) {(void)NUM2LONG(v); return v;}

static enum iseq_type
iseq_type_from_sym(VALUE type)
{
    const ID id_top = rb_intern("top");
    const ID id_method = rb_intern("method");
    const ID id_block = rb_intern("block");
    const ID id_class = rb_intern("class");
    const ID id_rescue = rb_intern("rescue");
    const ID id_ensure = rb_intern("ensure");
    const ID id_eval = rb_intern("eval");
    const ID id_main = rb_intern("main");
    const ID id_plain = rb_intern("plain");
    /* ensure all symbols are static or pinned down before
     * conversion */
    const ID typeid = rb_check_id(&type);
    if (typeid == id_top) return ISEQ_TYPE_TOP;
    if (typeid == id_method) return ISEQ_TYPE_METHOD;
    if (typeid == id_block) return ISEQ_TYPE_BLOCK;
    if (typeid == id_class) return ISEQ_TYPE_CLASS;
    if (typeid == id_rescue) return ISEQ_TYPE_RESCUE;
    if (typeid == id_ensure) return ISEQ_TYPE_ENSURE;
    if (typeid == id_eval) return ISEQ_TYPE_EVAL;
    if (typeid == id_main) return ISEQ_TYPE_MAIN;
    if (typeid == id_plain) return ISEQ_TYPE_PLAIN;
    return (enum iseq_type)-1;
}

static VALUE
iseq_load(VALUE data, const rb_iseq_t *parent, VALUE opt)
{
    rb_iseq_t *iseq = iseq_alloc();

    VALUE magic, version1, version2, format_type, misc;
    VALUE name, path, realpath, first_lineno, code_location, node_id;
    VALUE type, body, locals, params, exception;

    st_data_t iseq_type;
    rb_compile_option_t option;
    int i = 0;
    rb_code_location_t tmp_loc = { {0, 0}, {-1, -1} };

    /* [magic, major_version, minor_version, format_type, misc,
     *  label, path, first_lineno,
     *  type, locals, args, exception_table, body]
     */

    data        = CHECK_ARRAY(data);

    magic       = CHECK_STRING(rb_ary_entry(data, i++));
    version1    = CHECK_INTEGER(rb_ary_entry(data, i++));
    version2    = CHECK_INTEGER(rb_ary_entry(data, i++));
    format_type = CHECK_INTEGER(rb_ary_entry(data, i++));
    misc        = CHECK_HASH(rb_ary_entry(data, i++));
    ((void)magic, (void)version1, (void)version2, (void)format_type);

    name        = CHECK_STRING(rb_ary_entry(data, i++));
    path        = CHECK_STRING(rb_ary_entry(data, i++));
    realpath    = rb_ary_entry(data, i++);
    realpath    = NIL_P(realpath) ? Qnil : CHECK_STRING(realpath);
    first_lineno = CHECK_INTEGER(rb_ary_entry(data, i++));

    type        = CHECK_SYMBOL(rb_ary_entry(data, i++));
    locals      = CHECK_ARRAY(rb_ary_entry(data, i++));
    params      = CHECK_HASH(rb_ary_entry(data, i++));
    exception   = CHECK_ARRAY(rb_ary_entry(data, i++));
    body        = CHECK_ARRAY(rb_ary_entry(data, i++));

    iseq->body->local_iseq = iseq;

    iseq_type = iseq_type_from_sym(type);
    if (iseq_type == (enum iseq_type)-1) {
	rb_raise(rb_eTypeError, "unsupport type: :%"PRIsVALUE, rb_sym2str(type));
    }

    node_id = rb_hash_aref(misc, ID2SYM(rb_intern("node_id")));

    code_location = rb_hash_aref(misc, ID2SYM(rb_intern("code_location")));
    if (RB_TYPE_P(code_location, T_ARRAY) && RARRAY_LEN(code_location) == 4) {
	tmp_loc.beg_pos.lineno = NUM2INT(rb_ary_entry(code_location, 0));
	tmp_loc.beg_pos.column = NUM2INT(rb_ary_entry(code_location, 1));
	tmp_loc.end_pos.lineno = NUM2INT(rb_ary_entry(code_location, 2));
	tmp_loc.end_pos.column = NUM2INT(rb_ary_entry(code_location, 3));
    }

    make_compile_option(&option, opt);
    option.peephole_optimization = FALSE; /* because peephole optimization can modify original iseq */
    prepare_iseq_build(iseq, name, path, realpath, first_lineno, &tmp_loc, NUM2INT(node_id),
		       parent, (enum iseq_type)iseq_type, &option);

    rb_iseq_build_from_ary(iseq, misc, locals, params, exception, body);

    finish_iseq_build(iseq);

    return iseqw_new(iseq);
}

/*
 * :nodoc:
 */
static VALUE
iseq_s_load(int argc, VALUE *argv, VALUE self)
{
    VALUE data, opt=Qnil;
    rb_scan_args(argc, argv, "11", &data, &opt);
    return iseq_load(data, NULL, opt);
}

VALUE
rb_iseq_load(VALUE data, VALUE parent, VALUE opt)
{
    return iseq_load(data, RTEST(parent) ? (rb_iseq_t *)parent : NULL, opt);
}

rb_iseq_t *
rb_iseq_compile_with_option(VALUE src, VALUE file, VALUE realpath, VALUE line, const struct rb_block *base_block, VALUE opt)
{
    rb_iseq_t *iseq = NULL;
    const rb_iseq_t *const parent = base_block ? vm_block_iseq(base_block) : NULL;
    rb_compile_option_t option;
    const enum iseq_type type = parent ? ISEQ_TYPE_EVAL : ISEQ_TYPE_TOP;
#if !defined(__GNUC__) || (__GNUC__ == 4 && __GNUC_MINOR__ == 8)
# define INITIALIZED volatile /* suppress warnings by gcc 4.8 */
#else
# define INITIALIZED /* volatile */
#endif
    rb_ast_t *(*parse)(VALUE vparser, VALUE fname, VALUE file, int start);
    int ln;
    rb_ast_t *INITIALIZED ast;

    /* safe results first */
    make_compile_option(&option, opt);
    ln = NUM2INT(line);
    StringValueCStr(file);
    if (RB_TYPE_P(src, T_FILE)) {
	parse = rb_parser_compile_file_path;
    }
    else {
	parse = rb_parser_compile_string_path;
	StringValue(src);
    }
    {
	const VALUE parser = rb_parser_new();
	rb_parser_set_context(parser, base_block, FALSE);
	ast = (*parse)(parser, file, src, ln);
    }

    if (!ast->body.root) {
	rb_ast_dispose(ast);
	rb_exc_raise(GET_EC()->errinfo);
    }
    else {
	INITIALIZED VALUE label = parent ?
	    parent->body->location.label :
	    rb_fstring_lit("<compiled>");
	iseq = rb_iseq_new_with_opt(&ast->body, label, file, realpath, line,
				    parent, type, &option);
	rb_ast_dispose(ast);
    }

    return iseq;
}

rb_iseq_t *
rb_iseq_compile(VALUE src, VALUE file, VALUE line)
{
    return rb_iseq_compile_with_option(src, file, Qnil, line, 0, Qnil);
}

rb_iseq_t *
rb_iseq_compile_on_base(VALUE src, VALUE file, VALUE line, const struct rb_block *base_block)
{
    return rb_iseq_compile_with_option(src, file, Qnil, line, base_block, Qnil);
}

VALUE
rb_iseq_path(const rb_iseq_t *iseq)
{
    return pathobj_path(iseq->body->location.pathobj);
}

VALUE
rb_iseq_realpath(const rb_iseq_t *iseq)
{
    return pathobj_realpath(iseq->body->location.pathobj);
}

VALUE
rb_iseq_absolute_path(const rb_iseq_t *iseq)
{
    return rb_iseq_realpath(iseq);
}

VALUE
rb_iseq_label(const rb_iseq_t *iseq)
{
    return iseq->body->location.label;
}

VALUE
rb_iseq_base_label(const rb_iseq_t *iseq)
{
    return iseq->body->location.base_label;
}

VALUE
rb_iseq_first_lineno(const rb_iseq_t *iseq)
{
    return iseq->body->location.first_lineno;
}

VALUE
rb_iseq_method_name(const rb_iseq_t *iseq)
{
    struct rb_iseq_constant_body *const body = iseq->body->local_iseq->body;

    if (body->type == ISEQ_TYPE_METHOD) {
	return body->location.base_label;
    }
    else {
	return Qnil;
    }
}

void
rb_iseq_code_location(const rb_iseq_t *iseq, int *beg_pos_lineno, int *beg_pos_column, int *end_pos_lineno, int *end_pos_column)
{
    const rb_code_location_t *loc = &iseq->body->location.code_location;
    if (beg_pos_lineno) *beg_pos_lineno = loc->beg_pos.lineno;
    if (beg_pos_column) *beg_pos_column = loc->beg_pos.column;
    if (end_pos_lineno) *end_pos_lineno = loc->end_pos.lineno;
    if (end_pos_column) *end_pos_column = loc->end_pos.column;
}

VALUE
rb_iseq_coverage(const rb_iseq_t *iseq)
{
    return ISEQ_COVERAGE(iseq);
}

static int
remove_coverage_i(void *vstart, void *vend, size_t stride, void *data)
{
    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        void *ptr = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);

	if (rb_obj_is_iseq(v)) {
            rb_iseq_t *iseq = (rb_iseq_t *)v;
            ISEQ_COVERAGE_SET(iseq, Qnil);
	}

        asan_poison_object_if(ptr, v);
    }
    return 0;
}

void
rb_iseq_remove_coverage_all(void)
{
    rb_objspace_each_objects(remove_coverage_i, NULL);
}

/* define wrapper class methods (RubyVM::InstructionSequence) */

static void
iseqw_mark(void *ptr)
{
    rb_gc_mark((VALUE)ptr);
}

static size_t
iseqw_memsize(const void *ptr)
{
    return rb_iseq_memsize((const rb_iseq_t *)ptr);
}

static const rb_data_type_t iseqw_data_type = {
    "T_IMEMO/iseq",
    {iseqw_mark, NULL, iseqw_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static VALUE
iseqw_new(const rb_iseq_t *iseq)
{
    if (iseq->wrapper) {
        return iseq->wrapper;
    }
    else {
        union { const rb_iseq_t *in; void *out; } deconst;
        VALUE obj;
        deconst.in = iseq;
        obj = TypedData_Wrap_Struct(rb_cISeq, &iseqw_data_type, deconst.out);
        RB_OBJ_WRITTEN(obj, Qundef, iseq);

        /* cache a wrapper object */
        RB_OBJ_WRITE((VALUE)iseq, &iseq->wrapper, obj);
        RB_OBJ_FREEZE((VALUE)iseq);

        return obj;
    }
}

VALUE
rb_iseqw_new(const rb_iseq_t *iseq)
{
    return iseqw_new(iseq);
}

/*
 *  call-seq:
 *     InstructionSequence.compile(source[, file[, path[, line[, options]]]]) -> iseq
 *     InstructionSequence.new(source[, file[, path[, line[, options]]]]) -> iseq
 *
 *  Takes +source+, a String of Ruby code and compiles it to an
 *  InstructionSequence.
 *
 *  Optionally takes +file+, +path+, and +line+ which describe the filename,
 *  absolute path and first line number of the ruby code in +source+ which are
 *  metadata attached to the returned +iseq+.
 *
 *  +options+, which can be +true+, +false+ or a +Hash+, is used to
 *  modify the default behavior of the Ruby iseq compiler.
 *
 *  For details regarding valid compile options see ::compile_option=.
 *
 *     RubyVM::InstructionSequence.compile("a = 1 + 2")
 *     #=> <RubyVM::InstructionSequence:<compiled>@<compiled>>
 *
 */
static VALUE
iseqw_s_compile(int argc, VALUE *argv, VALUE self)
{
    VALUE src, file = Qnil, path = Qnil, line = INT2FIX(1), opt = Qnil;
    int i;

    rb_secure(1);

    i = rb_scan_args(argc, argv, "1*:", &src, NULL, &opt);
    if (i > 4+NIL_P(opt)) rb_error_arity(argc, 1, 5);
    switch (i) {
      case 5: opt = argv[--i];
      case 4: line = argv[--i];
      case 3: path = argv[--i];
      case 2: file = argv[--i];
    }

    if (NIL_P(file)) file = rb_fstring_lit("<compiled>");
    if (NIL_P(path)) path = file;
    if (NIL_P(line)) line = INT2FIX(1);

    Check_Type(path, T_STRING);
    Check_Type(file, T_STRING);

    return iseqw_new(rb_iseq_compile_with_option(src, file, path, line, 0, opt));
}

/*
 *  call-seq:
 *      InstructionSequence.compile_file(file[, options]) -> iseq
 *
 *  Takes +file+, a String with the location of a Ruby source file, reads,
 *  parses and compiles the file, and returns +iseq+, the compiled
 *  InstructionSequence with source location metadata set.
 *
 *  Optionally takes +options+, which can be +true+, +false+ or a +Hash+, to
 *  modify the default behavior of the Ruby iseq compiler.
 *
 *  For details regarding valid compile options see ::compile_option=.
 *
 *      # /tmp/hello.rb
 *      puts "Hello, world!"
 *
 *      # elsewhere
 *      RubyVM::InstructionSequence.compile_file("/tmp/hello.rb")
 *      #=> <RubyVM::InstructionSequence:<main>@/tmp/hello.rb>
 */
static VALUE
iseqw_s_compile_file(int argc, VALUE *argv, VALUE self)
{
    VALUE file, line = INT2FIX(1), opt = Qnil;
    VALUE parser, f, exc = Qnil, ret;
    rb_ast_t *ast;
    rb_compile_option_t option;
    int i;

    rb_secure(1);
    i = rb_scan_args(argc, argv, "1*:", &file, NULL, &opt);
    if (i > 1+NIL_P(opt)) rb_error_arity(argc, 1, 2);
    switch (i) {
      case 2: opt = argv[--i];
    }
    FilePathValue(file);
    file = rb_fstring(file); /* rb_io_t->pathv gets frozen anyways */

    f = rb_file_open_str(file, "r");

    parser = rb_parser_new();
    rb_parser_set_context(parser, NULL, FALSE);
    ast = rb_parser_compile_file_path(parser, file, f, NUM2INT(line));
    if (!ast->body.root) exc = GET_EC()->errinfo;

    rb_io_close(f);
    if (!ast->body.root) {
	rb_ast_dispose(ast);
	rb_exc_raise(exc);
    }

    make_compile_option(&option, opt);

    ret = iseqw_new(rb_iseq_new_with_opt(&ast->body, rb_fstring_lit("<main>"),
					 file,
					 rb_realpath_internal(Qnil, file, 1),
					 line, NULL, ISEQ_TYPE_TOP, &option));
    rb_ast_dispose(ast);
    return ret;
}

/*
 *  call-seq:
 *     InstructionSequence.compile_option = options
 *
 *  Sets the default values for various optimizations in the Ruby iseq
 *  compiler.
 *
 *  Possible values for +options+ include +true+, which enables all options,
 *  +false+ which disables all options, and +nil+ which leaves all options
 *  unchanged.
 *
 *  You can also pass a +Hash+ of +options+ that you want to change, any
 *  options not present in the hash will be left unchanged.
 *
 *  Possible option names (which are keys in +options+) which can be set to
 *  +true+ or +false+ include:
 *
 *  * +:inline_const_cache+
 *  * +:instructions_unification+
 *  * +:operands_unification+
 *  * +:peephole_optimization+
 *  * +:specialized_instruction+
 *  * +:stack_caching+
 *  * +:tailcall_optimization+
 *
 *  Additionally, +:debug_level+ can be set to an integer.
 *
 *  These default options can be overwritten for a single run of the iseq
 *  compiler by passing any of the above values as the +options+ parameter to
 *  ::new, ::compile and ::compile_file.
 */
static VALUE
iseqw_s_compile_option_set(VALUE self, VALUE opt)
{
    rb_compile_option_t option;
    rb_secure(1);
    make_compile_option(&option, opt);
    COMPILE_OPTION_DEFAULT = option;
    return opt;
}

/*
 *  call-seq:
 *     InstructionSequence.compile_option -> options
 *
 *  Returns a hash of default options used by the Ruby iseq compiler.
 *
 *  For details, see InstructionSequence.compile_option=.
 */
static VALUE
iseqw_s_compile_option_get(VALUE self)
{
    return make_compile_option_value(&COMPILE_OPTION_DEFAULT);
}

static const rb_iseq_t *
iseqw_check(VALUE iseqw)
{
    rb_iseq_t *iseq = DATA_PTR(iseqw);

    if (!iseq->body) {
	rb_ibf_load_iseq_complete(iseq);
    }

    if (!iseq->body->location.label) {
	rb_raise(rb_eTypeError, "uninitialized InstructionSequence");
    }
    return iseq;
}

const rb_iseq_t *
rb_iseqw_to_iseq(VALUE iseqw)
{
    return iseqw_check(iseqw);
}

/*
 *  call-seq:
 *     iseq.eval -> obj
 *
 *  Evaluates the instruction sequence and returns the result.
 *
 *      RubyVM::InstructionSequence.compile("1 + 2").eval #=> 3
 */
static VALUE
iseqw_eval(VALUE self)
{
    rb_secure(1);
    return rb_iseq_eval(iseqw_check(self));
}

/*
 *  Returns a human-readable string representation of this instruction
 *  sequence, including the #label and #path.
 */
static VALUE
iseqw_inspect(VALUE self)
{
    const rb_iseq_t *iseq = iseqw_check(self);
    const struct rb_iseq_constant_body *const body = iseq->body;
    VALUE klass = rb_class_name(rb_obj_class(self));

    if (!body->location.label) {
	return rb_sprintf("#<%"PRIsVALUE": uninitialized>", klass);
    }
    else {
	return rb_sprintf("<%"PRIsVALUE":%"PRIsVALUE"@%"PRIsVALUE":%d>",
			  klass,
			  body->location.label, rb_iseq_path(iseq),
			  FIX2INT(rb_iseq_first_lineno(iseq)));
    }
}

/*
 *  Returns the path of this instruction sequence.
 *
 *  <code><compiled></code> if the iseq was evaluated from a string.
 *
 *  For example, using irb:
 *
 *	iseq = RubyVM::InstructionSequence.compile('num = 1 + 2')
 *	#=> <RubyVM::InstructionSequence:<compiled>@<compiled>>
 *	iseq.path
 *	#=> "<compiled>"
 *
 *  Using ::compile_file:
 *
 *	# /tmp/method.rb
 *	def hello
 *	  puts "hello, world"
 *	end
 *
 *	# in irb
 *	> iseq = RubyVM::InstructionSequence.compile_file('/tmp/method.rb')
 *	> iseq.path #=> /tmp/method.rb
 */
static VALUE
iseqw_path(VALUE self)
{
    return rb_iseq_path(iseqw_check(self));
}

/*
 *  Returns the absolute path of this instruction sequence.
 *
 *  +nil+ if the iseq was evaluated from a string.
 *
 *  For example, using ::compile_file:
 *
 *	# /tmp/method.rb
 *	def hello
 *	  puts "hello, world"
 *	end
 *
 *	# in irb
 *	> iseq = RubyVM::InstructionSequence.compile_file('/tmp/method.rb')
 *	> iseq.absolute_path #=> /tmp/method.rb
 */
static VALUE
iseqw_absolute_path(VALUE self)
{
    return rb_iseq_realpath(iseqw_check(self));
}

/*  Returns the label of this instruction sequence.
 *
 *  <code><main></code> if it's at the top level, <code><compiled></code> if it
 *  was evaluated from a string.
 *
 *  For example, using irb:
 *
 *	iseq = RubyVM::InstructionSequence.compile('num = 1 + 2')
 *	#=> <RubyVM::InstructionSequence:<compiled>@<compiled>>
 *	iseq.label
 *	#=> "<compiled>"
 *
 *  Using ::compile_file:
 *
 *	# /tmp/method.rb
 *	def hello
 *	  puts "hello, world"
 *	end
 *
 *	# in irb
 *	> iseq = RubyVM::InstructionSequence.compile_file('/tmp/method.rb')
 *	> iseq.label #=> <main>
 */
static VALUE
iseqw_label(VALUE self)
{
    return rb_iseq_label(iseqw_check(self));
}

/*  Returns the base label of this instruction sequence.
 *
 *  For example, using irb:
 *
 *	iseq = RubyVM::InstructionSequence.compile('num = 1 + 2')
 *	#=> <RubyVM::InstructionSequence:<compiled>@<compiled>>
 *	iseq.base_label
 *	#=> "<compiled>"
 *
 *  Using ::compile_file:
 *
 *	# /tmp/method.rb
 *	def hello
 *	  puts "hello, world"
 *	end
 *
 *	# in irb
 *	> iseq = RubyVM::InstructionSequence.compile_file('/tmp/method.rb')
 *	> iseq.base_label #=> <main>
 */
static VALUE
iseqw_base_label(VALUE self)
{
    return rb_iseq_base_label(iseqw_check(self));
}

/*  Returns the number of the first source line where the instruction sequence
 *  was loaded from.
 *
 *  For example, using irb:
 *
 *	iseq = RubyVM::InstructionSequence.compile('num = 1 + 2')
 *	#=> <RubyVM::InstructionSequence:<compiled>@<compiled>>
 *	iseq.first_lineno
 *	#=> 1
 */
static VALUE
iseqw_first_lineno(VALUE self)
{
    return rb_iseq_first_lineno(iseqw_check(self));
}

static VALUE iseq_data_to_ary(const rb_iseq_t *iseq);

/*
 *  call-seq:
 *     iseq.to_a -> ary
 *
 *  Returns an Array with 14 elements representing the instruction sequence
 *  with the following data:
 *
 *  [magic]
 *    A string identifying the data format. <b>Always
 *    +YARVInstructionSequence/SimpleDataFormat+.</b>
 *
 *  [major_version]
 *    The major version of the instruction sequence.
 *
 *  [minor_version]
 *    The minor version of the instruction sequence.
 *
 *  [format_type]
 *    A number identifying the data format. <b>Always 1</b>.
 *
 *  [misc]
 *    A hash containing:
 *
 *    [+:arg_size+]
 *	the total number of arguments taken by the method or the block (0 if
 *	_iseq_ doesn't represent a method or block)
 *    [+:local_size+]
 *	the number of local variables + 1
 *    [+:stack_max+]
 *	used in calculating the stack depth at which a SystemStackError is
 *	thrown.
 *
 *  [#label]
 *    The name of the context (block, method, class, module, etc.) that this
 *    instruction sequence belongs to.
 *
 *    <code><main></code> if it's at the top level, <code><compiled></code> if
 *    it was evaluated from a string.
 *
 *  [#path]
 *    The relative path to the Ruby file where the instruction sequence was
 *    loaded from.
 *
 *    <code><compiled></code> if the iseq was evaluated from a string.
 *
 *  [#absolute_path]
 *    The absolute path to the Ruby file where the instruction sequence was
 *    loaded from.
 *
 *    +nil+ if the iseq was evaluated from a string.
 *
 *  [#first_lineno]
 *    The number of the first source line where the instruction sequence was
 *    loaded from.
 *
 *  [type]
 *    The type of the instruction sequence.
 *
 *    Valid values are +:top+, +:method+, +:block+, +:class+, +:rescue+,
 *    +:ensure+, +:eval+, +:main+, and +plain+.
 *
 *  [locals]
 *    An array containing the names of all arguments and local variables as
 *    symbols.
 *
 *  [params]
 *    An Hash object containing parameter information.
 *
 *    More info about these values can be found in +vm_core.h+.
 *
 *  [catch_table]
 *    A list of exceptions and control flow operators (rescue, next, redo,
 *    break, etc.).
 *
 *  [bytecode]
 *    An array of arrays containing the instruction names and operands that
 *    make up the body of the instruction sequence.
 *
 *  Note that this format is MRI specific and version dependent.
 *
 */
static VALUE
iseqw_to_a(VALUE self)
{
    const rb_iseq_t *iseq = iseqw_check(self);
    rb_secure(1);
    return iseq_data_to_ary(iseq);
}

#if VM_INSN_INFO_TABLE_IMPL == 1 /* binary search */
static const struct iseq_insn_info_entry *
get_insn_info_binary_search(const rb_iseq_t *iseq, size_t pos)
{
    const struct rb_iseq_constant_body *const body = iseq->body;
    size_t size = body->insns_info.size;
    const struct iseq_insn_info_entry *insns_info = body->insns_info.body;
    const unsigned int *positions = body->insns_info.positions;
    const int debug = 0;

    if (debug) {
	printf("size: %"PRIuSIZE"\n", size);
	printf("insns_info[%"PRIuSIZE"]: position: %d, line: %d, pos: %"PRIuSIZE"\n",
	       (size_t)0, positions[0], insns_info[0].line_no, pos);
    }

    if (size == 0) {
	return NULL;
    }
    else if (size == 1) {
	return &insns_info[0];
    }
    else {
	size_t l = 1, r = size - 1;
	while (l <= r) {
	    size_t m = l + (r - l) / 2;
	    if (positions[m] == pos) {
		return &insns_info[m];
	    }
	    if (positions[m] < pos) {
		l = m + 1;
	    }
	    else {
		r = m - 1;
	    }
	}
	if (l >= size) {
	    return &insns_info[size-1];
	}
	if (positions[l] > pos) {
	    return &insns_info[l-1];
	}
	return &insns_info[l];
    }
}

static const struct iseq_insn_info_entry *
get_insn_info(const rb_iseq_t *iseq, size_t pos)
{
    return get_insn_info_binary_search(iseq, pos);
}
#endif

#if VM_INSN_INFO_TABLE_IMPL == 2 /* succinct bitvector */
static const struct iseq_insn_info_entry *
get_insn_info_succinct_bitvector(const rb_iseq_t *iseq, size_t pos)
{
    const struct rb_iseq_constant_body *const body = iseq->body;
    size_t size = body->insns_info.size;
    const struct iseq_insn_info_entry *insns_info = body->insns_info.body;
    const int debug = 0;

    if (debug) {
#if VM_CHECK_MODE > 0
        const unsigned int *positions = body->insns_info.positions;
        printf("size: %"PRIuSIZE"\n", size);
        printf("insns_info[%"PRIuSIZE"]: position: %d, line: %d, pos: %"PRIuSIZE"\n",
               (size_t)0, positions[0], insns_info[0].line_no, pos);
#else
        printf("size: %"PRIuSIZE"\n", size);
        printf("insns_info[%"PRIuSIZE"]: line: %d, pos: %"PRIuSIZE"\n",
               (size_t)0, insns_info[0].line_no, pos);
#endif
    }

    if (size == 0) {
	return NULL;
    }
    else if (size == 1) {
	return &insns_info[0];
    }
    else {
	int index;
	VM_ASSERT(body->insns_info.succ_index_table != NULL);
	index = succ_index_lookup(body->insns_info.succ_index_table, (int)pos);
	return &insns_info[index-1];
    }
}

static const struct iseq_insn_info_entry *
get_insn_info(const rb_iseq_t *iseq, size_t pos)
{
    return get_insn_info_succinct_bitvector(iseq, pos);
}
#endif

#if VM_CHECK_MODE > 0 || VM_INSN_INFO_TABLE_IMPL == 0
static const struct iseq_insn_info_entry *
get_insn_info_linear_search(const rb_iseq_t *iseq, size_t pos)
{
    const struct rb_iseq_constant_body *const body = iseq->body;
    size_t i = 0, size = body->insns_info.size;
    const struct iseq_insn_info_entry *insns_info = body->insns_info.body;
    const unsigned int *positions = body->insns_info.positions;
    const int debug = 0;

    if (debug) {
	printf("size: %"PRIuSIZE"\n", size);
	printf("insns_info[%"PRIuSIZE"]: position: %d, line: %d, pos: %"PRIuSIZE"\n",
	       i, positions[i], insns_info[i].line_no, pos);
    }

    if (size == 0) {
	return NULL;
    }
    else if (size == 1) {
	return &insns_info[0];
    }
    else {
	for (i=1; i<size; i++) {
	    if (debug) printf("insns_info[%"PRIuSIZE"]: position: %d, line: %d, pos: %"PRIuSIZE"\n",
			      i, positions[i], insns_info[i].line_no, pos);

	    if (positions[i] == pos) {
		return &insns_info[i];
	    }
	    if (positions[i] > pos) {
		return &insns_info[i-1];
	    }
	}
    }
    return &insns_info[i-1];
}
#endif

#if VM_INSN_INFO_TABLE_IMPL == 0 /* linear search */
static const struct iseq_insn_info_entry *
get_insn_info(const rb_iseq_t *iseq, size_t pos)
{
    return get_insn_info_linear_search(iseq, pos);
}
#endif

#if VM_CHECK_MODE > 0 && VM_INSN_INFO_TABLE_IMPL > 0
static void
validate_get_insn_info(const rb_iseq_t *iseq)
{
    const struct rb_iseq_constant_body *const body = iseq->body;
    size_t i;
    for (i = 0; i < body->iseq_size; i++) {
	if (get_insn_info_linear_search(iseq, i) != get_insn_info(iseq, i)) {
	    rb_bug("validate_get_insn_info: get_insn_info_linear_search(iseq, %"PRIuSIZE") != get_insn_info(iseq, %"PRIuSIZE")", i, i);
	}
    }
}
#endif

unsigned int
rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos)
{
    const struct iseq_insn_info_entry *entry = get_insn_info(iseq, pos);

    if (entry) {
	return entry->line_no;
    }
    else {
	return 0;
    }
}

MJIT_FUNC_EXPORTED rb_event_flag_t
rb_iseq_event_flags(const rb_iseq_t *iseq, size_t pos)
{
    const struct iseq_insn_info_entry *entry = get_insn_info(iseq, pos);
    if (entry) {
	return entry->events;
    }
    else {
	return 0;
    }
}

void
rb_iseq_clear_event_flags(const rb_iseq_t *iseq, size_t pos, rb_event_flag_t reset)
{
    struct iseq_insn_info_entry *entry = (struct iseq_insn_info_entry *)get_insn_info(iseq, pos);
    if (entry) {
        entry->events &= ~reset;
        if (!(entry->events & iseq->aux.exec.global_trace_events)) {
            void rb_iseq_trace_flag_cleared(const rb_iseq_t *iseq, size_t pos);
            rb_iseq_trace_flag_cleared(iseq, pos);
        }
    }
}

static VALUE
local_var_name(const rb_iseq_t *diseq, VALUE level, VALUE op)
{
    VALUE i;
    VALUE name;
    ID lid;
    int idx;

    for (i = 0; i < level; i++) {
	diseq = diseq->body->parent_iseq;
    }
    idx = diseq->body->local_table_size - (int)op - 1;
    lid = diseq->body->local_table[idx];
    name = rb_id2str(lid);
    if (!name) {
	name = rb_str_new_cstr("?");
    }
    else if (!rb_str_symname_p(name)) {
	name = rb_str_inspect(name);
    }
    else {
	name = rb_str_dup(name);
    }
    rb_str_catf(name, "@%d", idx);
    return name;
}

int rb_insn_unified_local_var_level(VALUE);

VALUE
rb_insn_operand_intern(const rb_iseq_t *iseq,
		       VALUE insn, int op_no, VALUE op,
		       int len, size_t pos, const VALUE *pnop, VALUE child)
{
    const char *types = insn_op_types(insn);
    char type = types[op_no];
    VALUE ret = Qundef;

    switch (type) {
      case TS_OFFSET:		/* LONG */
	ret = rb_sprintf("%"PRIdVALUE, (VALUE)(pos + len + op));
	break;

      case TS_NUM:		/* ULONG */
	if (insn == BIN(defined) && op_no == 0) {
	    enum defined_type deftype = (enum defined_type)op;
	    if (deftype == DEFINED_FUNC) {
		ret = rb_fstring_lit("func"); break;
	    }
	    if (deftype == DEFINED_REF) {
		ret = rb_fstring_lit("ref"); break;
	    }
	    ret = rb_iseq_defined_string(deftype);
	    if (ret) break;
	}
	else if (insn == BIN(checktype) && op_no == 0) {
	    const char *type_str = rb_type_str((enum ruby_value_type)op);
	    if (type_str) {
		ret = rb_str_new_cstr(type_str); break;
	    }
	}
	ret = rb_sprintf("%"PRIuVALUE, op);
	break;

      case TS_LINDEX:{
	int level;
	if (types[op_no+1] == TS_NUM && pnop) {
	    ret = local_var_name(iseq, *pnop, op - VM_ENV_DATA_SIZE);
	}
	else if ((level = rb_insn_unified_local_var_level(insn)) >= 0) {
	    ret = local_var_name(iseq, (VALUE)level, op - VM_ENV_DATA_SIZE);
	}
	else {
	    ret = rb_inspect(INT2FIX(op));
	}
	break;
      }
      case TS_ID:		/* ID (symbol) */
	ret = rb_inspect(ID2SYM(op));
	break;

      case TS_VALUE:		/* VALUE */
	op = obj_resurrect(op);
	if (insn == BIN(defined) && op_no == 1 && FIXNUM_P(op)) {
	    /* should be DEFINED_REF */
	    int type = NUM2INT(op);
	    if (type) {
		if (type & 1) {
		    ret = rb_sprintf(":$%c", (type >> 1));
		}
		else {
		    ret = rb_sprintf(":$%d", (type >> 1));
		}
		break;
	    }
	}
	ret = rb_inspect(op);
	if (CLASS_OF(op) == rb_cISeq) {
	    if (child) {
		rb_ary_push(child, op);
	    }
	}
	break;

      case TS_ISEQ:		/* iseq */
	{
	    if (op) {
		const rb_iseq_t *iseq = rb_iseq_check((rb_iseq_t *)op);
		ret = iseq->body->location.label;
		if (child) {
		    rb_ary_push(child, (VALUE)iseq);
		}
	    }
	    else {
		ret = rb_str_new2("nil");
	    }
	    break;
	}
      case TS_GENTRY:
	{
	    struct rb_global_entry *entry = (struct rb_global_entry *)op;
	    ret = rb_str_dup(rb_id2str(entry->id));
	}
	break;

      case TS_IC:
      case TS_ISE:
	ret = rb_sprintf("<is:%"PRIdPTRDIFF">", (union iseq_inline_storage_entry *)op - iseq->body->is_entries);
	break;

      case TS_CALLINFO:
	{
	    struct rb_call_info *ci = (struct rb_call_info *)op;
	    VALUE ary = rb_ary_new();

	    if (ci->mid) {
		rb_ary_push(ary, rb_sprintf("mid:%"PRIsVALUE, rb_id2str(ci->mid)));
	    }

	    rb_ary_push(ary, rb_sprintf("argc:%d", ci->orig_argc));

	    if (ci->flag & VM_CALL_KWARG) {
		struct rb_call_info_kw_arg *kw_args = ((struct rb_call_info_with_kwarg *)ci)->kw_arg;
		VALUE kw_ary = rb_ary_new_from_values(kw_args->keyword_len, kw_args->keywords);
		rb_ary_push(ary, rb_sprintf("kw:[%"PRIsVALUE"]", rb_ary_join(kw_ary, rb_str_new2(","))));
	    }

	    if (ci->flag) {
		VALUE flags = rb_ary_new();
# define CALL_FLAG(n) if (ci->flag & VM_CALL_##n) rb_ary_push(flags, rb_str_new2(#n))
		CALL_FLAG(ARGS_SPLAT);
		CALL_FLAG(ARGS_BLOCKARG);
		CALL_FLAG(FCALL);
		CALL_FLAG(VCALL);
		CALL_FLAG(ARGS_SIMPLE);
		CALL_FLAG(BLOCKISEQ);
		CALL_FLAG(TAILCALL);
		CALL_FLAG(SUPER);
		CALL_FLAG(ZSUPER);
		CALL_FLAG(KWARG);
		CALL_FLAG(KW_SPLAT);
		CALL_FLAG(OPT_SEND); /* maybe not reachable */
		rb_ary_push(ary, rb_ary_join(flags, rb_str_new2("|")));
	    }
	    ret = rb_sprintf("<callinfo!%"PRIsVALUE">", rb_ary_join(ary, rb_str_new2(", ")));
	}
	break;

      case TS_CALLCACHE:
	ret = rb_str_new2("<callcache>");
	break;

      case TS_CDHASH:
	ret = rb_str_new2("<cdhash>");
	break;

      case TS_FUNCPTR:
	{
#ifdef HAVE_DLADDR
	    Dl_info info;
	    if (dladdr((void *)op, &info) && info.dli_sname) {
		ret = rb_str_new_cstr(info.dli_sname);
		break;
	    }
#endif
	    ret = rb_str_new2("<funcptr>");
	}
	break;

      default:
	rb_bug("unknown operand type: %c", type);
    }
    return ret;
}

static VALUE
right_strip(VALUE str)
{
    const char *beg = RSTRING_PTR(str), *end = RSTRING_END(str);
    while (end-- > beg && *end == ' ');
    rb_str_set_len(str, end - beg + 1);
    return str;
}

/**
 * Disassemble a instruction
 * Iseq -> Iseq inspect object
 */
int
rb_iseq_disasm_insn(VALUE ret, const VALUE *code, size_t pos,
		    const rb_iseq_t *iseq, VALUE child)
{
    VALUE insn = code[pos];
    int len = insn_len(insn);
    int j;
    const char *types = insn_op_types(insn);
    VALUE str = rb_str_new(0, 0);
    const char *insn_name_buff;

    insn_name_buff = insn_name(insn);
    if (1) {
	extern const int rb_vm_max_insn_name_size;
	rb_str_catf(str, "%04"PRIuSIZE" %-*s ", pos, rb_vm_max_insn_name_size, insn_name_buff);
    }
    else {
	rb_str_catf(str, "%04"PRIuSIZE" %-28.*s ", pos,
		    (int)strcspn(insn_name_buff, "_"), insn_name_buff);
    }

    for (j = 0; types[j]; j++) {
	VALUE opstr = rb_insn_operand_intern(iseq, insn, j, code[pos + j + 1],
					     len, pos, &code[pos + j + 2],
					     child);
	rb_str_concat(str, opstr);

	if (types[j + 1]) {
	    rb_str_cat2(str, ", ");
	}
    }

    {
	unsigned int line_no = rb_iseq_line_no(iseq, pos);
	unsigned int prev = pos == 0 ? 0 : rb_iseq_line_no(iseq, pos - 1);
	if (line_no && line_no != prev) {
	    long slen = RSTRING_LEN(str);
	    slen = (slen > 70) ? 0 : (70 - slen);
	    str = rb_str_catf(str, "%*s(%4d)", (int)slen, "", line_no);
	}
    }

    {
	rb_event_flag_t events = rb_iseq_event_flags(iseq, pos);
	if (events) {
            str = rb_str_catf(str, "[%s%s%s%s%s%s%s%s%s%s%s]",
			      events & RUBY_EVENT_LINE     ? "Li" : "",
			      events & RUBY_EVENT_CLASS    ? "Cl" : "",
			      events & RUBY_EVENT_END      ? "En" : "",
			      events & RUBY_EVENT_CALL     ? "Ca" : "",
			      events & RUBY_EVENT_RETURN   ? "Re" : "",
			      events & RUBY_EVENT_C_CALL   ? "Cc" : "",
			      events & RUBY_EVENT_C_RETURN ? "Cr" : "",
			      events & RUBY_EVENT_B_CALL   ? "Bc" : "",
                              events & RUBY_EVENT_B_RETURN ? "Br" : "",
                              events & RUBY_EVENT_COVERAGE_LINE   ? "Cli" : "",
                              events & RUBY_EVENT_COVERAGE_BRANCH ? "Cbr" : "");
	}
    }

    right_strip(str);
    if (ret) {
	rb_str_cat2(str, "\n");
	rb_str_concat(ret, str);
    }
    else {
	printf("%.*s\n", (int)RSTRING_LEN(str), RSTRING_PTR(str));
    }
    return len;
}

static const char *
catch_type(int type)
{
    switch (type) {
      case CATCH_TYPE_RESCUE:
	return "rescue";
      case CATCH_TYPE_ENSURE:
	return "ensure";
      case CATCH_TYPE_RETRY:
	return "retry";
      case CATCH_TYPE_BREAK:
	return "break";
      case CATCH_TYPE_REDO:
	return "redo";
      case CATCH_TYPE_NEXT:
	return "next";
      default:
	rb_bug("unknown catch type: %d", type);
	return 0;
    }
}

static VALUE
iseq_inspect(const rb_iseq_t *iseq)
{
    const struct rb_iseq_constant_body *const body = iseq->body;
    if (!body->location.label) {
	return rb_sprintf("#<ISeq: uninitialized>");
    }
    else {
	const rb_code_location_t *loc = &body->location.code_location;
	return rb_sprintf("#<ISeq:%"PRIsVALUE"@%"PRIsVALUE":%d (%d,%d)-(%d,%d)>",
			  body->location.label, rb_iseq_path(iseq),
			  loc->beg_pos.lineno,
			  loc->beg_pos.lineno,
			  loc->beg_pos.column,
			  loc->end_pos.lineno,
			  loc->end_pos.column);
    }
}

static VALUE
rb_iseq_disasm_recursive(const rb_iseq_t *iseq, VALUE indent)
{
    const struct rb_iseq_constant_body *const body = iseq->body;
    VALUE *code;
    VALUE str = rb_str_new(0, 0);
    VALUE child = rb_ary_tmp_new(3);
    unsigned int size;
    unsigned int i;
    long l;
    size_t n;
    enum {header_minlen = 72};
    st_table *done_iseq = 0;
    const char *indent_str;
    long indent_len;

    rb_secure(1);

    size = body->iseq_size;

    indent_len = RSTRING_LEN(indent);
    indent_str = RSTRING_PTR(indent);

    rb_str_cat(str, indent_str, indent_len);
    rb_str_cat2(str, "== disasm: ");

    rb_str_append(str, iseq_inspect(iseq));
    rb_str_catf(str, " (catch: %s)", body->catch_except_p ? "TRUE" : "FALSE");
    if ((l = RSTRING_LEN(str) - indent_len) < header_minlen) {
	rb_str_modify_expand(str, header_minlen - l);
	memset(RSTRING_END(str), '=', header_minlen - l);
    }
    rb_str_cat2(str, "\n");

    /* show catch table information */
    if (body->catch_table) {
	rb_str_cat(str, indent_str, indent_len);
	rb_str_cat2(str, "== catch table\n");
    }
    if (body->catch_table) {
	rb_str_cat_cstr(indent, "| ");
	indent_str = RSTRING_PTR(indent);
	for (i = 0; i < body->catch_table->size; i++) {
	    const struct iseq_catch_table_entry *entry =
		UNALIGNED_MEMBER_PTR(body->catch_table, entries[i]);
	    rb_str_cat(str, indent_str, indent_len);
	    rb_str_catf(str,
			"| catch type: %-6s st: %04d ed: %04d sp: %04d cont: %04d\n",
			catch_type((int)entry->type), (int)entry->start,
			(int)entry->end, (int)entry->sp, (int)entry->cont);
	    if (entry->iseq && !(done_iseq && st_is_member(done_iseq, (st_data_t)entry->iseq))) {
		rb_str_concat(str, rb_iseq_disasm_recursive(rb_iseq_check(entry->iseq), indent));
		if (!done_iseq) done_iseq = st_init_numtable();
		st_insert(done_iseq, (st_data_t)entry->iseq, (st_data_t)0);
		indent_str = RSTRING_PTR(indent);
	    }
	}
	rb_str_resize(indent, indent_len);
	indent_str = RSTRING_PTR(indent);
    }
    if (body->catch_table) {
	rb_str_cat(str, indent_str, indent_len);
	rb_str_cat2(str, "|-------------------------------------"
		    "-----------------------------------\n");
    }

    /* show local table information */
    if (body->local_table) {
	const struct rb_iseq_param_keyword *const keyword = body->param.keyword;
	rb_str_cat(str, indent_str, indent_len);
	rb_str_catf(str,
		    "local table (size: %d, argc: %d "
		    "[opts: %d, rest: %d, post: %d, block: %d, kw: %d@%d, kwrest: %d])\n",
		    body->local_table_size,
		    body->param.lead_num,
		    body->param.opt_num,
		    body->param.flags.has_rest ? body->param.rest_start : -1,
		    body->param.post_num,
		    body->param.flags.has_block ? body->param.block_start : -1,
		    body->param.flags.has_kw ? keyword->num : -1,
		    body->param.flags.has_kw ? keyword->required_num : -1,
		    body->param.flags.has_kwrest ? keyword->rest_start : -1);

	for (i = body->local_table_size; i > 0;) {
	    int li = body->local_table_size - --i - 1;
	    long width;
	    VALUE name = local_var_name(iseq, 0, i);
            char argi[0x100];
            char opti[0x100];

            opti[0] = '\0';
	    if (body->param.flags.has_opt) {
		int argc = body->param.lead_num;
		int opts = body->param.opt_num;
		if (li >= argc && li < argc + opts) {
		    snprintf(opti, sizeof(opti), "Opt=%"PRIdVALUE,
			     body->param.opt_table[li - argc]);
		}
	    }

	    snprintf(argi, sizeof(argi), "%s%s%s%s%s%s",	/* arg, opts, rest, post, kwrest, block */
		     body->param.lead_num > li ? "Arg" : "",
		     opti,
		     (body->param.flags.has_rest && body->param.rest_start == li) ? "Rest" : "",
		     (body->param.flags.has_post && body->param.post_start <= li && li < body->param.post_start + body->param.post_num) ? "Post" : "",
		     (body->param.flags.has_kwrest && keyword->rest_start == li) ? "Kwrest" : "",
		     (body->param.flags.has_block && body->param.block_start == li) ? "Block" : "");

	    rb_str_cat(str, indent_str, indent_len);
	    rb_str_catf(str, "[%2d] ", i + 1);
	    width = RSTRING_LEN(str) + 11;
	    rb_str_append(str, name);
	    if (*argi) rb_str_catf(str, "<%s>", argi);
	    if ((width -= RSTRING_LEN(str)) > 0) rb_str_catf(str, "%*s", (int)width, "");
	}
	rb_str_cat_cstr(right_strip(str), "\n");
    }

    /* show each line */
    code = rb_iseq_original_iseq(iseq);
    for (n = 0; n < size;) {
	rb_str_cat(str, indent_str, indent_len);
	n += rb_iseq_disasm_insn(str, code, n, iseq, child);
    }

    for (l = 0; l < RARRAY_LEN(child); l++) {
	VALUE isv = rb_ary_entry(child, l);
	if (done_iseq && st_is_member(done_iseq, (st_data_t)isv)) continue;
	rb_str_cat_cstr(str, "\n");
	rb_str_concat(str, rb_iseq_disasm_recursive(rb_iseq_check((rb_iseq_t *)isv), indent));
	indent_str = RSTRING_PTR(indent);
    }
    if (done_iseq) st_free_table(done_iseq);

    return str;
}

VALUE
rb_iseq_disasm(const rb_iseq_t *iseq)
{
    return rb_iseq_disasm_recursive(iseq, rb_str_new(0, 0));
}

/*
 *  call-seq:
 *     iseq.disasm -> str
 *     iseq.disassemble -> str
 *
 *  Returns the instruction sequence as a +String+ in human readable form.
 *
 *    puts RubyVM::InstructionSequence.compile('1 + 2').disasm
 *
 *  Produces:
 *
 *    == disasm: <RubyVM::InstructionSequence:<compiled>@<compiled>>==========
 *    0000 trace            1                                               (   1)
 *    0002 putobject        1
 *    0004 putobject        2
 *    0006 opt_plus         <ic:1>
 *    0008 leave
 */
static VALUE
iseqw_disasm(VALUE self)
{
    return rb_iseq_disasm(iseqw_check(self));
}

static int
iseq_iterate_children(const rb_iseq_t *iseq, void (*iter_func)(const rb_iseq_t *child_iseq, void *data), void *data)
{
    unsigned int i;
    VALUE *code = rb_iseq_original_iseq(iseq);
    const struct rb_iseq_constant_body *const body = iseq->body;
    const rb_iseq_t *child;
    VALUE all_children = rb_obj_hide(rb_ident_hash_new());

    if (body->catch_table) {
        for (i = 0; i < body->catch_table->size; i++) {
            const struct iseq_catch_table_entry *entry =
                UNALIGNED_MEMBER_PTR(body->catch_table, entries[i]);
            child = entry->iseq;
            if (child) {
                if (rb_hash_aref(all_children, (VALUE)child) == Qnil) {
                    rb_hash_aset(all_children, (VALUE)child, Qtrue);
                    (*iter_func)(child, data);
                }
            }
        }
    }

    for (i=0; i<body->iseq_size;) {
        VALUE insn = code[i];
        int len = insn_len(insn);
        const char *types = insn_op_types(insn);
        int j;

        for (j=0; types[j]; j++) {
            switch (types[j]) {
              case TS_ISEQ:
                child = (const rb_iseq_t *)code[i+j+1];
                if (child) {
                    if (rb_hash_aref(all_children, (VALUE)child) == Qnil) {
                        rb_hash_aset(all_children, (VALUE)child, Qtrue);
                        (*iter_func)(child, data);
                    }
                }
                break;
              default:
                break;
            }
        }
        i += len;
    }

    return (int)RHASH_SIZE(all_children);
}

static void
yield_each_children(const rb_iseq_t *child_iseq, void *data)
{
    rb_yield(iseqw_new(child_iseq));
}

/*
 *  call-seq:
 *     iseq.each_child{|child_iseq| ...} -> iseq
 *
 *  Iterate all direct child instruction sequences.
 *  Iteration order is implementation/version defined
 *  so that people should not rely on the order.
 */
static VALUE
iseqw_each_child(VALUE self)
{
    const rb_iseq_t *iseq = iseqw_check(self);
    iseq_iterate_children(iseq, yield_each_children, NULL);
    return self;
}

static void
push_event_info(const rb_iseq_t *iseq, rb_event_flag_t events, int line, VALUE ary)
{
#define C(ev, cstr, l) if (events & ev) rb_ary_push(ary, rb_ary_new_from_args(2, l, ID2SYM(rb_intern(cstr))));
    C(RUBY_EVENT_CLASS,    "class",    rb_iseq_first_lineno(iseq));
    C(RUBY_EVENT_CALL,     "call",     rb_iseq_first_lineno(iseq));
    C(RUBY_EVENT_B_CALL,   "b_call",   rb_iseq_first_lineno(iseq));
    C(RUBY_EVENT_LINE,     "line",     INT2FIX(line));
    C(RUBY_EVENT_END,      "end",      INT2FIX(line));
    C(RUBY_EVENT_RETURN,   "return",   INT2FIX(line));
    C(RUBY_EVENT_B_RETURN, "b_return", INT2FIX(line));
#undef C
}

/*
 *  call-seq:
 *     iseq.trace_points -> ary
 *
 *  Return trace points in the instruction sequence.
 *  Return an array of [line, event_symbol] pair.
 */
static VALUE
iseqw_trace_points(VALUE self)
{
    const rb_iseq_t *iseq = iseqw_check(self);
    const struct rb_iseq_constant_body *const body = iseq->body;
    unsigned int i;
    VALUE ary = rb_ary_new();

    for (i=0; i<body->insns_info.size; i++) {
	const struct iseq_insn_info_entry *entry = &body->insns_info.body[i];
	if (entry->events) {
	    push_event_info(iseq, entry->events, entry->line_no, ary);
	}
    }
    return ary;
}

/*
 *  Returns the instruction sequence containing the given proc or method.
 *
 *  For example, using irb:
 *
 *	# a proc
 *	> p = proc { num = 1 + 2 }
 *	> RubyVM::InstructionSequence.of(p)
 *	> #=> <RubyVM::InstructionSequence:block in irb_binding@(irb)>
 *
 *	# for a method
 *	> def foo(bar); puts bar; end
 *	> RubyVM::InstructionSequence.of(method(:foo))
 *	> #=> <RubyVM::InstructionSequence:foo@(irb)>
 *
 *  Using ::compile_file:
 *
 *	# /tmp/iseq_of.rb
 *	def hello
 *	  puts "hello, world"
 *	end
 *
 *	$a_global_proc = proc { str = 'a' + 'b' }
 *
 *	# in irb
 *	> require '/tmp/iseq_of.rb'
 *
 *	# first the method hello
 *	> RubyVM::InstructionSequence.of(method(:hello))
 *	> #=> #<RubyVM::InstructionSequence:0x007fb73d7cb1d0>
 *
 *	# then the global proc
 *	> RubyVM::InstructionSequence.of($a_global_proc)
 *	> #=> #<RubyVM::InstructionSequence:0x007fb73d7caf78>
 */
static VALUE
iseqw_s_of(VALUE klass, VALUE body)
{
    const rb_iseq_t *iseq = NULL;

    rb_secure(1);

    if (rb_obj_is_proc(body)) {
        iseq = vm_proc_iseq(body);

        if (!rb_obj_is_iseq((VALUE)iseq)) {
            iseq = NULL;
        }
    }
    else if (rb_obj_is_method(body)) {
        iseq = rb_method_iseq(body);
    }
    else if (rb_typeddata_is_instance_of(body, &iseqw_data_type)) {
        return body;
    }

    return iseq ? iseqw_new(iseq) : Qnil;
}

/*
 *  call-seq:
 *     InstructionSequence.disasm(body) -> str
 *     InstructionSequence.disassemble(body) -> str
 *
 *  Takes +body+, a Method or Proc object, and returns a String with the
 *  human readable instructions for +body+.
 *
 *  For a Method object:
 *
 *    # /tmp/method.rb
 *    def hello
 *      puts "hello, world"
 *    end
 *
 *    puts RubyVM::InstructionSequence.disasm(method(:hello))
 *
 *  Produces:
 *
 *    == disasm: <RubyVM::InstructionSequence:hello@/tmp/method.rb>============
 *    0000 trace            8                                               (   1)
 *    0002 trace            1                                               (   2)
 *    0004 putself
 *    0005 putstring        "hello, world"
 *    0007 send             :puts, 1, nil, 8, <ic:0>
 *    0013 trace            16                                              (   3)
 *    0015 leave                                                            (   2)
 *
 *  For a Proc:
 *
 *    # /tmp/proc.rb
 *    p = proc { num = 1 + 2 }
 *    puts RubyVM::InstructionSequence.disasm(p)
 *
 *  Produces:
 *
 *    == disasm: <RubyVM::InstructionSequence:block in <main>@/tmp/proc.rb>===
 *    == catch table
 *    | catch type: redo   st: 0000 ed: 0012 sp: 0000 cont: 0000
 *    | catch type: next   st: 0000 ed: 0012 sp: 0000 cont: 0012
 *    |------------------------------------------------------------------------
 *    local table (size: 2, argc: 0 [opts: 0, rest: -1, post: 0, block: -1] s1)
 *    [ 2] num
 *    0000 trace            1                                               (   1)
 *    0002 putobject        1
 *    0004 putobject        2
 *    0006 opt_plus         <ic:1>
 *    0008 dup
 *    0009 setlocal         num, 0
 *    0012 leave
 *
 */
static VALUE
iseqw_s_disasm(VALUE klass, VALUE body)
{
    VALUE iseqw = iseqw_s_of(klass, body);
    return NIL_P(iseqw) ? Qnil : rb_iseq_disasm(iseqw_check(iseqw));
}

const char *
ruby_node_name(int node)
{
    switch (node) {
#include "node_name.inc"
      default:
	rb_bug("unknown node: %d", node);
	return 0;
    }
}

#define DECL_SYMBOL(name) \
  static ID sym_##name

#define INIT_SYMBOL(name) \
  sym_##name = rb_intern(#name)

static VALUE
register_label(struct st_table *table, unsigned long idx)
{
    VALUE sym = rb_str_intern(rb_sprintf("label_%lu", idx));
    st_insert(table, idx, sym);
    return sym;
}

static VALUE
exception_type2symbol(VALUE type)
{
    ID id;
    switch (type) {
      case CATCH_TYPE_RESCUE: CONST_ID(id, "rescue"); break;
      case CATCH_TYPE_ENSURE: CONST_ID(id, "ensure"); break;
      case CATCH_TYPE_RETRY:  CONST_ID(id, "retry");  break;
      case CATCH_TYPE_BREAK:  CONST_ID(id, "break");  break;
      case CATCH_TYPE_REDO:   CONST_ID(id, "redo");   break;
      case CATCH_TYPE_NEXT:   CONST_ID(id, "next");   break;
      default:
	rb_bug("unknown exception type: %d", (int)type);
    }
    return ID2SYM(id);
}

static int
cdhash_each(VALUE key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, obj_resurrect(key));
    rb_ary_push(ary, value);
    return ST_CONTINUE;
}

static VALUE
iseq_data_to_ary(const rb_iseq_t *iseq)
{
    unsigned int i;
    long l;
    const struct rb_iseq_constant_body *const iseq_body = iseq->body;
    const struct iseq_insn_info_entry *prev_insn_info;
    unsigned int pos;
    int last_line = 0;
    VALUE *seq, *iseq_original;

    VALUE val = rb_ary_new();
    ID type; /* Symbol */
    VALUE locals = rb_ary_new();
    VALUE params = rb_hash_new();
    VALUE body = rb_ary_new(); /* [[:insn1, ...], ...] */
    VALUE nbody;
    VALUE exception = rb_ary_new(); /* [[....]] */
    VALUE misc = rb_hash_new();

    static ID insn_syms[VM_INSTRUCTION_SIZE/2]; /* w/o-trace only */
    struct st_table *labels_table = st_init_numtable();

    DECL_SYMBOL(top);
    DECL_SYMBOL(method);
    DECL_SYMBOL(block);
    DECL_SYMBOL(class);
    DECL_SYMBOL(rescue);
    DECL_SYMBOL(ensure);
    DECL_SYMBOL(eval);
    DECL_SYMBOL(main);
    DECL_SYMBOL(plain);

    if (sym_top == 0) {
	int i;
	for (i=0; i<numberof(insn_syms); i++) {
            insn_syms[i] = rb_intern(insn_name(i));
	}
	INIT_SYMBOL(top);
	INIT_SYMBOL(method);
	INIT_SYMBOL(block);
	INIT_SYMBOL(class);
	INIT_SYMBOL(rescue);
	INIT_SYMBOL(ensure);
	INIT_SYMBOL(eval);
	INIT_SYMBOL(main);
	INIT_SYMBOL(plain);
    }

    /* type */
    switch (iseq_body->type) {
      case ISEQ_TYPE_TOP:    type = sym_top;    break;
      case ISEQ_TYPE_METHOD: type = sym_method; break;
      case ISEQ_TYPE_BLOCK:  type = sym_block;  break;
      case ISEQ_TYPE_CLASS:  type = sym_class;  break;
      case ISEQ_TYPE_RESCUE: type = sym_rescue; break;
      case ISEQ_TYPE_ENSURE: type = sym_ensure; break;
      case ISEQ_TYPE_EVAL:   type = sym_eval;   break;
      case ISEQ_TYPE_MAIN:   type = sym_main;   break;
      case ISEQ_TYPE_PLAIN:  type = sym_plain;  break;
      default: rb_bug("unsupported iseq type: %d", (int)iseq_body->type);
    };

    /* locals */
    for (i=0; i<iseq_body->local_table_size; i++) {
	ID lid = iseq_body->local_table[i];
	if (lid) {
	    if (rb_id2str(lid)) {
		rb_ary_push(locals, ID2SYM(lid));
	    }
	    else { /* hidden variable from id_internal() */
		rb_ary_push(locals, ULONG2NUM(iseq_body->local_table_size-i+1));
	    }
	}
	else {
	    rb_ary_push(locals, ID2SYM(rb_intern("#arg_rest")));
	}
    }

    /* params */
    {
	const struct rb_iseq_param_keyword *const keyword = iseq_body->param.keyword;
	int j;

	if (iseq_body->param.flags.has_opt) {
	    int len = iseq_body->param.opt_num + 1;
	    VALUE arg_opt_labels = rb_ary_new2(len);

	    for (j = 0; j < len; j++) {
		VALUE l = register_label(labels_table, iseq_body->param.opt_table[j]);
		rb_ary_push(arg_opt_labels, l);
	    }
	    rb_hash_aset(params, ID2SYM(rb_intern("opt")), arg_opt_labels);
        }

	/* commit */
	if (iseq_body->param.flags.has_lead) rb_hash_aset(params, ID2SYM(rb_intern("lead_num")), INT2FIX(iseq_body->param.lead_num));
	if (iseq_body->param.flags.has_post) rb_hash_aset(params, ID2SYM(rb_intern("post_num")), INT2FIX(iseq_body->param.post_num));
	if (iseq_body->param.flags.has_post) rb_hash_aset(params, ID2SYM(rb_intern("post_start")), INT2FIX(iseq_body->param.post_start));
	if (iseq_body->param.flags.has_rest) rb_hash_aset(params, ID2SYM(rb_intern("rest_start")), INT2FIX(iseq_body->param.rest_start));
	if (iseq_body->param.flags.has_block) rb_hash_aset(params, ID2SYM(rb_intern("block_start")), INT2FIX(iseq_body->param.block_start));
	if (iseq_body->param.flags.has_kw) {
	    VALUE keywords = rb_ary_new();
	    int i, j;
	    for (i=0; i<keyword->required_num; i++) {
		rb_ary_push(keywords, ID2SYM(keyword->table[i]));
	    }
	    for (j=0; i<keyword->num; i++, j++) {
		VALUE key = rb_ary_new_from_args(1, ID2SYM(keyword->table[i]));
		if (keyword->default_values[j] != Qundef) {
		    rb_ary_push(key, keyword->default_values[j]);
		}
		rb_ary_push(keywords, key);
	    }

	    rb_hash_aset(params, ID2SYM(rb_intern("kwbits")),
	                 INT2FIX(keyword->bits_start));
	    rb_hash_aset(params, ID2SYM(rb_intern("keyword")), keywords);
	}
	if (iseq_body->param.flags.has_kwrest) rb_hash_aset(params, ID2SYM(rb_intern("kwrest")), INT2FIX(keyword->rest_start));
	if (iseq_body->param.flags.ambiguous_param0) rb_hash_aset(params, ID2SYM(rb_intern("ambiguous_param0")), Qtrue);
    }

    /* body */
    iseq_original = rb_iseq_original_iseq((rb_iseq_t *)iseq);

    for (seq = iseq_original; seq < iseq_original + iseq_body->iseq_size; ) {
	VALUE insn = *seq++;
	int j, len = insn_len(insn);
	VALUE *nseq = seq + len - 1;
	VALUE ary = rb_ary_new2(len);

        rb_ary_push(ary, ID2SYM(insn_syms[insn%numberof(insn_syms)]));
	for (j=0; j<len-1; j++, seq++) {
	    switch (insn_op_type(insn, j)) {
	      case TS_OFFSET: {
		unsigned long idx = nseq - iseq_original + *seq;
		rb_ary_push(ary, register_label(labels_table, idx));
		break;
	      }
	      case TS_LINDEX:
	      case TS_NUM:
		rb_ary_push(ary, INT2FIX(*seq));
		break;
	      case TS_VALUE:
		rb_ary_push(ary, obj_resurrect(*seq));
		break;
	      case TS_ISEQ:
		{
		    const rb_iseq_t *iseq = (rb_iseq_t *)*seq;
		    if (iseq) {
			VALUE val = iseq_data_to_ary(rb_iseq_check(iseq));
			rb_ary_push(ary, val);
		    }
		    else {
			rb_ary_push(ary, Qnil);
		    }
		}
		break;
	      case TS_GENTRY:
		{
		    struct rb_global_entry *entry = (struct rb_global_entry *)*seq;
		    rb_ary_push(ary, ID2SYM(entry->id));
		}
		break;
	      case TS_IC:
	      case TS_ISE:
		{
		    union iseq_inline_storage_entry *is = (union iseq_inline_storage_entry *)*seq;
		    rb_ary_push(ary, INT2FIX(is - iseq_body->is_entries));
		}
		break;
	      case TS_CALLINFO:
		{
		    struct rb_call_info *ci = (struct rb_call_info *)*seq;
		    VALUE e = rb_hash_new();
		    int orig_argc = ci->orig_argc;

		    rb_hash_aset(e, ID2SYM(rb_intern("mid")), ci->mid ? ID2SYM(ci->mid) : Qnil);
		    rb_hash_aset(e, ID2SYM(rb_intern("flag")), UINT2NUM(ci->flag));

		    if (ci->flag & VM_CALL_KWARG) {
			struct rb_call_info_with_kwarg *ci_kw = (struct rb_call_info_with_kwarg *)ci;
			int i;
			VALUE kw = rb_ary_new2((long)ci_kw->kw_arg->keyword_len);

			orig_argc -= ci_kw->kw_arg->keyword_len;
			for (i = 0; i < ci_kw->kw_arg->keyword_len; i++) {
			    rb_ary_push(kw, ci_kw->kw_arg->keywords[i]);
			}
			rb_hash_aset(e, ID2SYM(rb_intern("kw_arg")), kw);
		    }

		    rb_hash_aset(e, ID2SYM(rb_intern("orig_argc")),
				INT2FIX(orig_argc));
		    rb_ary_push(ary, e);
	        }
		break;
	      case TS_CALLCACHE:
		rb_ary_push(ary, Qfalse);
		break;
	      case TS_ID:
		rb_ary_push(ary, ID2SYM(*seq));
		break;
	      case TS_CDHASH:
		{
		    VALUE hash = *seq;
		    VALUE val = rb_ary_new();
		    int i;

		    rb_hash_foreach(hash, cdhash_each, val);

		    for (i=0; i<RARRAY_LEN(val); i+=2) {
			VALUE pos = FIX2INT(rb_ary_entry(val, i+1));
			unsigned long idx = nseq - iseq_original + pos;

			rb_ary_store(val, i+1,
				     register_label(labels_table, idx));
		    }
		    rb_ary_push(ary, val);
		}
		break;
	      case TS_FUNCPTR:
		{
#if SIZEOF_VALUE <= SIZEOF_LONG
		    VALUE val = LONG2NUM((SIGNED_VALUE)*seq);
#else
		    VALUE val = LL2NUM((SIGNED_VALUE)*seq);
#endif
		    rb_ary_push(ary, val);
		}
		break;
	      default:
		rb_bug("unknown operand: %c", insn_op_type(insn, j));
	    }
	}
	rb_ary_push(body, ary);
    }

    nbody = body;

    /* exception */
    if (iseq_body->catch_table) for (i=0; i<iseq_body->catch_table->size; i++) {
	VALUE ary = rb_ary_new();
	const struct iseq_catch_table_entry *entry =
	    UNALIGNED_MEMBER_PTR(iseq_body->catch_table, entries[i]);
	rb_ary_push(ary, exception_type2symbol(entry->type));
	if (entry->iseq) {
	    rb_ary_push(ary, iseq_data_to_ary(rb_iseq_check(entry->iseq)));
	}
	else {
	    rb_ary_push(ary, Qnil);
	}
	rb_ary_push(ary, register_label(labels_table, entry->start));
	rb_ary_push(ary, register_label(labels_table, entry->end));
	rb_ary_push(ary, register_label(labels_table, entry->cont));
	rb_ary_push(ary, UINT2NUM(entry->sp));
	rb_ary_push(exception, ary);
    }

    /* make body with labels and insert line number */
    body = rb_ary_new();
    prev_insn_info = NULL;

    for (l=0, pos=0; l<RARRAY_LEN(nbody); l++) {
	const struct iseq_insn_info_entry *info;
	VALUE ary = RARRAY_AREF(nbody, l);
	st_data_t label;

	if (st_lookup(labels_table, pos, &label)) {
	    rb_ary_push(body, (VALUE)label);
	}

	info = get_insn_info(iseq, pos);

	if (prev_insn_info != info) {
	    int line = info->line_no;
	    rb_event_flag_t events = info->events;

	    if (line > 0 && last_line != line) {
		rb_ary_push(body, INT2FIX(line));
		last_line = line;
	    }
#define CHECK_EVENT(ev) if (events & ev) rb_ary_push(body, ID2SYM(rb_intern(#ev)));
	    CHECK_EVENT(RUBY_EVENT_LINE);
	    CHECK_EVENT(RUBY_EVENT_CLASS);
	    CHECK_EVENT(RUBY_EVENT_END);
	    CHECK_EVENT(RUBY_EVENT_CALL);
	    CHECK_EVENT(RUBY_EVENT_RETURN);
	    CHECK_EVENT(RUBY_EVENT_B_CALL);
	    CHECK_EVENT(RUBY_EVENT_B_RETURN);
#undef CHECK_EVENT
	    prev_insn_info = info;
	}

	rb_ary_push(body, ary);
	pos += RARRAY_LENINT(ary); /* reject too huge data */
    }
    RB_GC_GUARD(nbody);

    st_free_table(labels_table);

    rb_hash_aset(misc, ID2SYM(rb_intern("arg_size")), INT2FIX(iseq_body->param.size));
    rb_hash_aset(misc, ID2SYM(rb_intern("local_size")), INT2FIX(iseq_body->local_table_size));
    rb_hash_aset(misc, ID2SYM(rb_intern("stack_max")), INT2FIX(iseq_body->stack_max));
    rb_hash_aset(misc, ID2SYM(rb_intern("node_id")), INT2FIX(iseq_body->location.node_id));
    rb_hash_aset(misc, ID2SYM(rb_intern("code_location")),
	    rb_ary_new_from_args(4,
		INT2FIX(iseq_body->location.code_location.beg_pos.lineno),
		INT2FIX(iseq_body->location.code_location.beg_pos.column),
		INT2FIX(iseq_body->location.code_location.end_pos.lineno),
		INT2FIX(iseq_body->location.code_location.end_pos.column)));

    /*
     * [:magic, :major_version, :minor_version, :format_type, :misc,
     *  :name, :path, :absolute_path, :start_lineno, :type, :locals, :args,
     *  :catch_table, :bytecode]
     */
    rb_ary_push(val, rb_str_new2("YARVInstructionSequence/SimpleDataFormat"));
    rb_ary_push(val, INT2FIX(ISEQ_MAJOR_VERSION)); /* major */
    rb_ary_push(val, INT2FIX(ISEQ_MINOR_VERSION)); /* minor */
    rb_ary_push(val, INT2FIX(1));
    rb_ary_push(val, misc);
    rb_ary_push(val, iseq_body->location.label);
    rb_ary_push(val, rb_iseq_path(iseq));
    rb_ary_push(val, rb_iseq_realpath(iseq));
    rb_ary_push(val, iseq_body->location.first_lineno);
    rb_ary_push(val, ID2SYM(type));
    rb_ary_push(val, locals);
    rb_ary_push(val, params);
    rb_ary_push(val, exception);
    rb_ary_push(val, body);
    return val;
}

VALUE
rb_iseq_parameters(const rb_iseq_t *iseq, int is_proc)
{
    int i, r;
    const struct rb_iseq_constant_body *const body = iseq->body;
    const struct rb_iseq_param_keyword *const keyword = body->param.keyword;
    VALUE a, args = rb_ary_new2(body->param.size);
    ID req, opt, rest, block, key, keyrest;
#define PARAM_TYPE(type) rb_ary_push(a = rb_ary_new2(2), ID2SYM(type))
#define PARAM_ID(i) body->local_table[(i)]
#define PARAM(i, type) (		      \
	PARAM_TYPE(type),		      \
	rb_id2str(PARAM_ID(i)) ?	      \
	rb_ary_push(a, ID2SYM(PARAM_ID(i))) : \
	a)

    CONST_ID(req, "req");
    CONST_ID(opt, "opt");
    if (is_proc) {
	for (i = 0; i < body->param.lead_num; i++) {
	    PARAM_TYPE(opt);
	    rb_ary_push(a, rb_id2str(PARAM_ID(i)) ? ID2SYM(PARAM_ID(i)) : Qnil);
	    rb_ary_push(args, a);
	}
    }
    else {
	for (i = 0; i < body->param.lead_num; i++) {
	    rb_ary_push(args, PARAM(i, req));
	}
    }
    r = body->param.lead_num + body->param.opt_num;
    for (; i < r; i++) {
	PARAM_TYPE(opt);
	if (rb_id2str(PARAM_ID(i))) {
	    rb_ary_push(a, ID2SYM(PARAM_ID(i)));
	}
	rb_ary_push(args, a);
    }
    if (body->param.flags.has_rest) {
	CONST_ID(rest, "rest");
	rb_ary_push(args, PARAM(body->param.rest_start, rest));
    }
    r = body->param.post_start + body->param.post_num;
    if (is_proc) {
	for (i = body->param.post_start; i < r; i++) {
	    PARAM_TYPE(opt);
	    rb_ary_push(a, rb_id2str(PARAM_ID(i)) ? ID2SYM(PARAM_ID(i)) : Qnil);
	    rb_ary_push(args, a);
	}
    }
    else {
	for (i = body->param.post_start; i < r; i++) {
	    rb_ary_push(args, PARAM(i, req));
	}
    }
    if (body->param.flags.has_kw) {
	i = 0;
	if (keyword->required_num > 0) {
	    ID keyreq;
	    CONST_ID(keyreq, "keyreq");
	    for (; i < keyword->required_num; i++) {
		PARAM_TYPE(keyreq);
		if (rb_id2str(keyword->table[i])) {
		    rb_ary_push(a, ID2SYM(keyword->table[i]));
		}
		rb_ary_push(args, a);
	    }
	}
	CONST_ID(key, "key");
	for (; i < keyword->num; i++) {
	    PARAM_TYPE(key);
	    if (rb_id2str(keyword->table[i])) {
		rb_ary_push(a, ID2SYM(keyword->table[i]));
	    }
	    rb_ary_push(args, a);
	}
    }
    if (body->param.flags.has_kwrest) {
	CONST_ID(keyrest, "keyrest");
	rb_ary_push(args, PARAM(keyword->rest_start, keyrest));
    }
    if (body->param.flags.has_block) {
	CONST_ID(block, "block");
	rb_ary_push(args, PARAM(body->param.block_start, block));
    }
    return args;
}

VALUE
rb_iseq_defined_string(enum defined_type type)
{
    static const char expr_names[][18] = {
	"nil",
	"instance-variable",
	"local-variable",
	"global-variable",
	"class variable",
	"constant",
	"method",
	"yield",
	"super",
	"self",
	"true",
	"false",
	"assignment",
	"expression",
    };
    const char *estr;
    VALUE *defs, str;

    if ((unsigned)(type - 1) >= (unsigned)numberof(expr_names)) return 0;
    estr = expr_names[type - 1];
    if (!estr[0]) return 0;
    defs = GET_VM()->defined_strings;
    if (!defs) {
	defs = ruby_xcalloc(numberof(expr_names), sizeof(VALUE));
	GET_VM()->defined_strings = defs;
    }
    str = defs[type-1];
    if (!str) {
	str = rb_str_new_cstr(estr);
	OBJ_FREEZE(str);
	defs[type-1] = str;
	rb_gc_register_mark_object(str);
    }
    return str;
}

/* A map from encoded_insn to insn_data: decoded insn number, its len,
 * non-trace version of encoded insn, and trace version. */

static st_table *encoded_insn_data;
typedef struct insn_data_struct {
    int insn;
    int insn_len;
    void *notrace_encoded_insn;
    void *trace_encoded_insn;
} insn_data_t;
static insn_data_t insn_data[VM_INSTRUCTION_SIZE/2];

void
rb_vm_encoded_insn_data_table_init(void)
{
#if OPT_DIRECT_THREADED_CODE || OPT_CALL_THREADED_CODE
    const void * const *table = rb_vm_get_insns_address_table();
#define INSN_CODE(insn) ((VALUE)table[insn])
#else
#define INSN_CODE(insn) (insn)
#endif
    st_data_t insn;
    encoded_insn_data = st_init_numtable_with_size(VM_INSTRUCTION_SIZE / 2);

    for (insn = 0; insn < VM_INSTRUCTION_SIZE/2; insn++) {
        st_data_t key1 = (st_data_t)INSN_CODE(insn);
        st_data_t key2 = (st_data_t)INSN_CODE(insn + VM_INSTRUCTION_SIZE/2);

        insn_data[insn].insn = (int)insn;
        insn_data[insn].insn_len = insn_len(insn);
        insn_data[insn].notrace_encoded_insn = (void *) key1;
        insn_data[insn].trace_encoded_insn = (void *) key2;

        st_add_direct(encoded_insn_data, key1, (st_data_t)&insn_data[insn]);
        st_add_direct(encoded_insn_data, key2, (st_data_t)&insn_data[insn]);
    }
}

int
rb_vm_insn_addr2insn(const void *addr)
{
    st_data_t key = (st_data_t)addr;
    st_data_t val;

    if (st_lookup(encoded_insn_data, key, &val)) {
        insn_data_t *e = (insn_data_t *)val;
        return (int)e->insn;
    }

    rb_bug("rb_vm_insn_addr2insn: invalid insn address: %p", addr);
}

static inline int
encoded_iseq_trace_instrument(VALUE *iseq_encoded_insn, rb_event_flag_t turnon)
{
    st_data_t key = (st_data_t)*iseq_encoded_insn;
    st_data_t val;

    if (st_lookup(encoded_insn_data, key, &val)) {
        insn_data_t *e = (insn_data_t *)val;
        *iseq_encoded_insn = (VALUE) (turnon ? e->trace_encoded_insn : e->notrace_encoded_insn);
        return e->insn_len;
    }

    rb_bug("trace_instrument: invalid insn address: %p", (void *)*iseq_encoded_insn);
}

void
rb_iseq_trace_flag_cleared(const rb_iseq_t *iseq, size_t pos)
{
    const struct rb_iseq_constant_body *const body = iseq->body;
    VALUE *iseq_encoded = (VALUE *)body->iseq_encoded;
    encoded_iseq_trace_instrument(&iseq_encoded[pos], 0);
}

static int
iseq_add_local_tracepoint(const rb_iseq_t *iseq, rb_event_flag_t turnon_events, VALUE tpval, unsigned int target_line)
{
    unsigned int pc;
    int n = 0;
    const struct rb_iseq_constant_body *const body = iseq->body;
    VALUE *iseq_encoded = (VALUE *)body->iseq_encoded;

    VM_ASSERT(ISEQ_EXECUTABLE_P(iseq));

    for (pc=0; pc<body->iseq_size;) {
        const struct iseq_insn_info_entry *entry = get_insn_info(iseq, pc);
        rb_event_flag_t pc_events = entry->events;
        rb_event_flag_t target_events = turnon_events;
        unsigned int line = (int)entry->line_no;

        if (target_line == 0 || target_line == line) {
            /* ok */
        }
        else {
            target_events &= ~RUBY_EVENT_LINE;
        }

        if (pc_events & target_events) {
            n++;
        }
        pc += encoded_iseq_trace_instrument(&iseq_encoded[pc], pc_events & (target_events | iseq->aux.exec.global_trace_events));
    }

    if (n > 0) {
        if (iseq->aux.exec.local_hooks == NULL) {
            ((rb_iseq_t *)iseq)->aux.exec.local_hooks = RB_ZALLOC(rb_hook_list_t);
        }
        rb_hook_list_connect_tracepoint((VALUE)iseq, iseq->aux.exec.local_hooks, tpval, target_line);
    }

    return n;
}

struct trace_set_local_events_struct {
    rb_event_flag_t turnon_events;
    VALUE tpval;
    unsigned int target_line;
    int n;
};

static void
iseq_add_local_tracepoint_i(const rb_iseq_t *iseq, void *p)
{
    struct trace_set_local_events_struct *data = (struct trace_set_local_events_struct *)p;
    data->n += iseq_add_local_tracepoint(iseq, data->turnon_events, data->tpval, data->target_line);
    iseq_iterate_children(iseq, iseq_add_local_tracepoint_i, p);
}

int
rb_iseq_add_local_tracepoint_recursively(const rb_iseq_t *iseq, rb_event_flag_t turnon_events, VALUE tpval, unsigned int target_line)
{
    struct trace_set_local_events_struct data;
    data.turnon_events = turnon_events;
    data.tpval = tpval;
    data.target_line = target_line;
    data.n = 0;

    iseq_add_local_tracepoint_i(iseq, (void *)&data);
    if (0) rb_funcall(Qnil, rb_intern("puts"), 1, rb_iseq_disasm(iseq)); /* for debug */
    return data.n;
}

static int
iseq_remove_local_tracepoint(const rb_iseq_t *iseq, VALUE tpval)
{
    int n = 0;

    if (iseq->aux.exec.local_hooks) {
        unsigned int pc;
        const struct rb_iseq_constant_body *const body = iseq->body;
        VALUE *iseq_encoded = (VALUE *)body->iseq_encoded;
        rb_event_flag_t local_events = 0;

        rb_hook_list_remove_tracepoint(iseq->aux.exec.local_hooks, tpval);
        local_events = iseq->aux.exec.local_hooks->events;

        if (local_events == 0) {
            if (iseq->aux.exec.local_hooks->running == 0) {
                rb_hook_list_free(iseq->aux.exec.local_hooks);
            }
            ((rb_iseq_t *)iseq)->aux.exec.local_hooks = NULL;
        }

        for (pc = 0; pc<body->iseq_size;) {
            rb_event_flag_t pc_events = rb_iseq_event_flags(iseq, pc);
            pc += encoded_iseq_trace_instrument(&iseq_encoded[pc], pc_events & (local_events | iseq->aux.exec.global_trace_events));
        }
    }
    return n;
}

struct trace_clear_local_events_struct {
    VALUE tpval;
    int n;
};

static void
iseq_remove_local_tracepoint_i(const rb_iseq_t *iseq, void *p)
{
    struct trace_clear_local_events_struct *data = (struct trace_clear_local_events_struct *)p;
    data->n += iseq_remove_local_tracepoint(iseq, data->tpval);
    iseq_iterate_children(iseq, iseq_remove_local_tracepoint_i, p);
}

int
rb_iseq_remove_local_tracepoint_recursively(const rb_iseq_t *iseq, VALUE tpval)
{
    struct trace_clear_local_events_struct data;
    data.tpval = tpval;
    data.n = 0;

    iseq_remove_local_tracepoint_i(iseq, (void *)&data);
    return data.n;
}

void
rb_iseq_trace_set(const rb_iseq_t *iseq, rb_event_flag_t turnon_events)
{
    if (iseq->aux.exec.global_trace_events == turnon_events) {
	return;
    }

    if (!ISEQ_EXECUTABLE_P(iseq)) {
	/* this is building ISeq */
	return;
    }
    else {
        unsigned int pc;
	const struct rb_iseq_constant_body *const body = iseq->body;
	VALUE *iseq_encoded = (VALUE *)body->iseq_encoded;
        rb_event_flag_t enabled_events;
        rb_event_flag_t local_events = iseq->aux.exec.local_hooks ? iseq->aux.exec.local_hooks->events : 0;
        ((rb_iseq_t *)iseq)->aux.exec.global_trace_events = turnon_events;
        enabled_events = turnon_events | local_events;

        for (pc=0; pc<body->iseq_size;) {
            rb_event_flag_t pc_events = rb_iseq_event_flags(iseq, pc);
            pc += encoded_iseq_trace_instrument(&iseq_encoded[pc], pc_events & enabled_events);
	}
    }
}

static int
trace_set_i(void *vstart, void *vend, size_t stride, void *data)
{
    rb_event_flag_t turnon_events = *(rb_event_flag_t *)data;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        void *ptr = asan_poisoned_object_p(v);
        asan_unpoison_object(v, false);

	if (rb_obj_is_iseq(v)) {
	    rb_iseq_trace_set(rb_iseq_check((rb_iseq_t *)v), turnon_events);
	}

        asan_poison_object_if(ptr, v);
    }
    return 0;
}

void
rb_iseq_trace_set_all(rb_event_flag_t turnon_events)
{
    rb_objspace_each_objects(trace_set_i, &turnon_events);
}

/* This is exported since Ruby 2.5 but not internally used for now. If you're going to use this, please
   update `ruby_vm_event_enabled_global_flags` and set `mjit_call_p = FALSE` as well to cancel MJIT code. */
void
rb_iseq_trace_on_all(void)
{
    rb_iseq_trace_set_all(RUBY_EVENT_TRACEPOINT_ALL);
}

VALUE
rb_iseqw_local_variables(VALUE iseqval)
{
    return rb_iseq_local_variables(iseqw_check(iseqval));
}

/*
 *  call-seq:
 *     iseq.to_binary(extra_data = nil) -> binary str
 *
 *  Returns serialized iseq binary format data as a String object.
 *  A corresponding iseq object is created by
 *  RubyVM::InstructionSequence.load_from_binary() method.
 *
 *  String extra_data will be saved with binary data.
 *  You can access this data with
 *  RubyVM::InstructionSequence.load_from_binary_extra_data(binary).
 *
 *  Note that the translated binary data is not portable.
 *  You can not move this binary data to another machine.
 *  You can not use the binary data which is created by another
 *  version/another architecture of Ruby.
 */
static VALUE
iseqw_to_binary(int argc, VALUE *argv, VALUE self)
{
    VALUE opt = !rb_check_arity(argc, 0, 1) ? Qnil : argv[0];
    return rb_iseq_ibf_dump(iseqw_check(self), opt);
}

/*
 *  call-seq:
 *     RubyVM::InstructionSequence.load_from_binary(binary) -> iseq
 *
 *  Load an iseq object from binary format String object
 *  created by RubyVM::InstructionSequence.to_binary.
 *
 *  This loader does not have a verifier, so that loading broken/modified
 *  binary causes critical problem.
 *
 *  You should not load binary data provided by others.
 *  You should use binary data translated by yourself.
 */
static VALUE
iseqw_s_load_from_binary(VALUE self, VALUE str)
{
    return iseqw_new(rb_iseq_ibf_load(str));
}

/*
 *  call-seq:
 *     RubyVM::InstructionSequence.load_from_binary_extra_data(binary) -> str
 *
 *  Load extra data embed into binary format String object.
 */
static VALUE
iseqw_s_load_from_binary_extra_data(VALUE self, VALUE str)
{
    return rb_iseq_ibf_load_extra_data(str);
}

#if VM_INSN_INFO_TABLE_IMPL == 2

/* An implementation of succinct bit-vector for insn_info table.
 *
 * A succinct bit-vector is a small and efficient data structure that provides
 * a bit-vector augmented with an index for O(1) rank operation:
 *
 *   rank(bv, n): the number of 1's within a range from index 0 to index n
 *
 * This can be used to lookup insn_info table from PC.
 * For example, consider the following iseq and insn_info_table:
 *
 *  iseq               insn_info_table
 *  PC  insn+operand   position  lineno event
 *   0: insn1                 0: 1      [Li]
 *   2: insn2                 2: 2      [Li]  <= (A)
 *   5: insn3                 8: 3      [Li]  <= (B)
 *   8: insn4
 *
 * In this case, a succinct bit-vector whose indexes 0, 2, 8 is "1" and
 * other indexes is "0", i.e., "101000001", is created.
 * To lookup the lineno of insn2, calculate rank("10100001", 2) = 2, so
 * the line (A) is the entry in question.
 * To lookup the lineno of insn4, calculate rank("10100001", 8) = 3, so
 * the line (B) is the entry in question.
 *
 * A naive implementatoin of succinct bit-vector works really well
 * not only for large size but also for small size.  However, it has
 * tiny overhead for very small size.  So, this implementation consist
 * of two parts: one part is the "immediate" table that keeps rank result
 * as a raw table, and the other part is a normal succinct bit-vector.
 */

#define IMMEDIATE_TABLE_SIZE 54 /* a multiple of 9, and < 128 */

struct succ_index_table {
    uint64_t imm_part[IMMEDIATE_TABLE_SIZE / 9];
    struct succ_dict_block {
	unsigned int rank;
	uint64_t small_block_ranks; /* 9 bits * 7 = 63 bits */
	uint64_t bits[512/64];
    } succ_part[FLEX_ARY_LEN];
};

#define imm_block_rank_set(v, i, r) (v) |= (uint64_t)(r) << (7 * (i))
#define imm_block_rank_get(v, i) (((int)((v) >> ((i) * 7))) & 0x7f)
#define small_block_rank_set(v, i, r) (v) |= (uint64_t)(r) << (9 * ((i) - 1))
#define small_block_rank_get(v, i) ((i) == 0 ? 0 : (((int)((v) >> (((i) - 1) * 9))) & 0x1ff))

static struct succ_index_table *
succ_index_table_create(int max_pos, int *data, int size)
{
    const int imm_size = (max_pos < IMMEDIATE_TABLE_SIZE ? max_pos + 8 : IMMEDIATE_TABLE_SIZE) / 9;
    const int succ_size = (max_pos < IMMEDIATE_TABLE_SIZE ? 0 : (max_pos - IMMEDIATE_TABLE_SIZE + 511)) / 512;
    struct succ_index_table *sd = ruby_xcalloc(imm_size * sizeof(uint64_t) + succ_size * sizeof(struct succ_dict_block), 1); /* zero cleared */
    int i, j, k, r;

    r = 0;
    for (j = 0; j < imm_size; j++) {
	for (i = 0; i < 9; i++) {
	    if (r < size && data[r] == j * 9 + i) r++;
	    imm_block_rank_set(sd->imm_part[j], i, r);
	}
    }
    for (k = 0; k < succ_size; k++) {
	struct succ_dict_block *sd_block = &sd->succ_part[k];
	int small_rank = 0;
	sd_block->rank = r;
	for (j = 0; j < 8; j++) {
	    uint64_t bits = 0;
	    if (j) small_block_rank_set(sd_block->small_block_ranks, j, small_rank);
	    for (i = 0; i < 64; i++) {
		if (r < size && data[r] == k * 512 + j * 64 + i + IMMEDIATE_TABLE_SIZE) {
		    bits |= ((uint64_t)1) << i;
		    r++;
		}
	    }
	    sd_block->bits[j] = bits;
	    small_rank += rb_popcount64(bits);
	}
    }
    return sd;
}

static unsigned int *
succ_index_table_invert(int max_pos, struct succ_index_table *sd, int size)
{
    const int imm_size = (max_pos < IMMEDIATE_TABLE_SIZE ? max_pos + 8 : IMMEDIATE_TABLE_SIZE) / 9;
    const int succ_size = (max_pos < IMMEDIATE_TABLE_SIZE ? 0 : (max_pos - IMMEDIATE_TABLE_SIZE + 511)) / 512;
    unsigned int *positions = ruby_xmalloc(sizeof(unsigned int) * size), *p;
    int i, j, k, r = -1;
    p = positions;
    for (j = 0; j < imm_size; j++) {
	for (i = 0; i < 9; i++) {
	    int nr = imm_block_rank_get(sd->imm_part[j], i);
	    if (r != nr) *p++ = j * 9 + i;
	    r = nr;
	}
    }
    for (k = 0; k < succ_size; k++) {
	for (j = 0; j < 8; j++) {
	    for (i = 0; i < 64; i++) {
		if (sd->succ_part[k].bits[j] & (((uint64_t)1) << i)) {
		    *p++ = k * 512 + j * 64 + i + IMMEDIATE_TABLE_SIZE;
		}
	    }
	}
    }
    return positions;
}

static int
succ_index_lookup(const struct succ_index_table *sd, int x)
{
    if (x < IMMEDIATE_TABLE_SIZE) {
	const int i = x / 9;
	const int j = x % 9;
	return imm_block_rank_get(sd->imm_part[i], j);
    }
    else {
	const int block_index = (x - IMMEDIATE_TABLE_SIZE) / 512;
	const struct succ_dict_block *block = &sd->succ_part[block_index];
	const int block_bit_index = (x - IMMEDIATE_TABLE_SIZE) % 512;
	const int small_block_index = block_bit_index / 64;
	const int small_block_popcount = small_block_rank_get(block->small_block_ranks, small_block_index);
	const int popcnt = rb_popcount64(block->bits[small_block_index] << (63 - block_bit_index % 64));

	return block->rank + small_block_popcount + popcnt;
    }
}
#endif

/*
 *  Document-class: RubyVM::InstructionSequence
 *
 *  The InstructionSequence class represents a compiled sequence of
 *  instructions for the Ruby Virtual Machine. Not all implementations of Ruby
 *  may implement this class, and for the implementations that implement it,
 *  the methods defined and behavior of the methods can change in any version.
 *
 *  With it, you can get a handle to the instructions that make up a method or
 *  a proc, compile strings of Ruby code down to VM instructions, and
 *  disassemble instruction sequences to strings for easy inspection. It is
 *  mostly useful if you want to learn how the Ruby VM works, but it also lets
 *  you control various settings for the Ruby iseq compiler.
 *
 *  You can find the source for the VM instructions in +insns.def+ in the Ruby
 *  source.
 *
 *  The instruction sequence results will almost certainly change as Ruby
 *  changes, so example output in this documentation may be different from what
 *  you see.
 */

void
Init_ISeq(void)
{
    /* declare ::RubyVM::InstructionSequence */
    rb_cISeq = rb_define_class_under(rb_cRubyVM, "InstructionSequence", rb_cObject);
    rb_undef_alloc_func(rb_cISeq);
    rb_define_method(rb_cISeq, "inspect", iseqw_inspect, 0);
    rb_define_method(rb_cISeq, "disasm", iseqw_disasm, 0);
    rb_define_method(rb_cISeq, "disassemble", iseqw_disasm, 0);
    rb_define_method(rb_cISeq, "to_a", iseqw_to_a, 0);
    rb_define_method(rb_cISeq, "eval", iseqw_eval, 0);

    rb_define_method(rb_cISeq, "to_binary", iseqw_to_binary, -1);
    rb_define_singleton_method(rb_cISeq, "load_from_binary", iseqw_s_load_from_binary, 1);
    rb_define_singleton_method(rb_cISeq, "load_from_binary_extra_data", iseqw_s_load_from_binary_extra_data, 1);


    /* location APIs */
    rb_define_method(rb_cISeq, "path", iseqw_path, 0);
    rb_define_method(rb_cISeq, "absolute_path", iseqw_absolute_path, 0);
    rb_define_method(rb_cISeq, "label", iseqw_label, 0);
    rb_define_method(rb_cISeq, "base_label", iseqw_base_label, 0);
    rb_define_method(rb_cISeq, "first_lineno", iseqw_first_lineno, 0);
    rb_define_method(rb_cISeq, "trace_points", iseqw_trace_points, 0);
    rb_define_method(rb_cISeq, "each_child", iseqw_each_child, 0);

#if 0 /* TBD */
    rb_define_private_method(rb_cISeq, "marshal_dump", iseqw_marshal_dump, 0);
    rb_define_private_method(rb_cISeq, "marshal_load", iseqw_marshal_load, 1);
    /* disable this feature because there is no verifier. */
    rb_define_singleton_method(rb_cISeq, "load", iseq_s_load, -1);
#endif
    (void)iseq_s_load;

    rb_define_singleton_method(rb_cISeq, "compile", iseqw_s_compile, -1);
    rb_define_singleton_method(rb_cISeq, "new", iseqw_s_compile, -1);
    rb_define_singleton_method(rb_cISeq, "compile_file", iseqw_s_compile_file, -1);
    rb_define_singleton_method(rb_cISeq, "compile_option", iseqw_s_compile_option_get, 0);
    rb_define_singleton_method(rb_cISeq, "compile_option=", iseqw_s_compile_option_set, 1);
    rb_define_singleton_method(rb_cISeq, "disasm", iseqw_s_disasm, 1);
    rb_define_singleton_method(rb_cISeq, "disassemble", iseqw_s_disasm, 1);
    rb_define_singleton_method(rb_cISeq, "of", iseqw_s_of, 1);

    rb_undef_method(CLASS_OF(rb_cISeq), "translate");
    rb_undef_method(CLASS_OF(rb_cISeq), "load_iseq");
}
