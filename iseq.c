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

/* #define RUBY_MARK_FREE_DEBUG 1 */
#include "gc.h"
#include "vm_core.h"
#include "iseq.h"
#include "id_table.h"

#include "insns.inc"
#include "insns_info.inc"

VALUE rb_cISeq;
static VALUE iseqw_new(const rb_iseq_t *iseq);
static const rb_iseq_t *iseqw_check(VALUE iseqw);

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

    if (iseq) {
	if (iseq->body) {
	    ruby_xfree((void *)iseq->body->iseq_encoded);
	    ruby_xfree((void *)iseq->body->line_info_table);
	    ruby_xfree((void *)iseq->body->local_table);
	    ruby_xfree((void *)iseq->body->is_entries);

	    if (iseq->body->ci_entries) {
		unsigned int i;
		struct rb_call_info_with_kwarg *ci_kw_entries = (struct rb_call_info_with_kwarg *)&iseq->body->ci_entries[iseq->body->ci_size];
		for (i=0; i<iseq->body->ci_kw_size; i++) {
		    const struct rb_call_info_kw_arg *kw_arg = ci_kw_entries[i].kw_arg;
		    ruby_xfree((void *)kw_arg);
		}
		ruby_xfree(iseq->body->ci_entries);
		ruby_xfree(iseq->body->cc_entries);
	    }
	    ruby_xfree((void *)iseq->body->catch_table);
	    ruby_xfree((void *)iseq->body->param.opt_table);

	    if (iseq->body->param.keyword != NULL) {
		ruby_xfree((void *)iseq->body->param.keyword->default_values);
		ruby_xfree((void *)iseq->body->param.keyword);
	    }
	    compile_data_free(ISEQ_COMPILE_DATA(iseq));
	    ruby_xfree(iseq->body);
	}
    }
    RUBY_FREE_LEAVE("iseq");
}

void
rb_iseq_mark(const rb_iseq_t *iseq)
{
    RUBY_MARK_ENTER("iseq");

    RUBY_GC_INFO("%s @ %s\n", RSTRING_PTR(iseq->body->location.label), RSTRING_PTR(iseq->body->location.path));

    if (iseq->body) {
	const struct rb_iseq_constant_body *body = iseq->body;

	RUBY_MARK_UNLESS_NULL(body->mark_ary);
	rb_gc_mark(body->location.label);
	rb_gc_mark(body->location.base_label);
	rb_gc_mark(body->location.path);
	RUBY_MARK_UNLESS_NULL(body->location.absolute_path);
	RUBY_MARK_UNLESS_NULL((VALUE)body->parent_iseq);
    }

    if (FL_TEST(iseq, ISEQ_NOT_LOADED_YET)) {
	rb_gc_mark(iseq->aux.loader.obj);
    }
    else if (ISEQ_COMPILE_DATA(iseq) != 0) {
	const struct iseq_compile_data *const compile_data = ISEQ_COMPILE_DATA(iseq);
	RUBY_MARK_UNLESS_NULL(compile_data->mark_ary);
	RUBY_MARK_UNLESS_NULL(compile_data->err_info);
	RUBY_MARK_UNLESS_NULL(compile_data->catch_table_ary);
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

static size_t
iseq_memsize(const rb_iseq_t *iseq)
{
    size_t size = 0; /* struct already counted as RVALUE size */
    const struct rb_iseq_constant_body *body = iseq->body;
    const struct iseq_compile_data *compile_data;

    /* TODO: should we count original_iseq? */

    if (body) {
	struct rb_call_info_with_kwarg *ci_kw_entries = (struct rb_call_info_with_kwarg *)&body->ci_entries[body->ci_size];

	size += sizeof(struct rb_iseq_constant_body);
	size += body->iseq_size * sizeof(VALUE);
	size += body->line_info_size * sizeof(struct iseq_line_info_entry);
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
	    size += cur->size + SIZEOF_ISEQ_COMPILE_DATA_STORAGE;
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

static rb_iseq_location_t *
iseq_location_setup(rb_iseq_t *iseq, VALUE path, VALUE absolute_path, VALUE name, VALUE first_lineno)
{
    rb_iseq_location_t *loc = &iseq->body->location;
    RB_OBJ_WRITE(iseq, &loc->path, path);
    if (RTEST(absolute_path) && rb_str_cmp(path, absolute_path) == 0) {
	RB_OBJ_WRITE(iseq, &loc->absolute_path, path);
    }
    else {
	RB_OBJ_WRITE(iseq, &loc->absolute_path, absolute_path);
    }
    RB_OBJ_WRITE(iseq, &loc->label, name);
    RB_OBJ_WRITE(iseq, &loc->base_label, name);
    loc->first_lineno = first_lineno;
    return loc;
}

static void
set_relation(rb_iseq_t *iseq, const rb_iseq_t *piseq)
{
    const VALUE type = iseq->body->type;

    /* set class nest stack */
    if (type == ISEQ_TYPE_TOP) {
	iseq->body->local_iseq = iseq;
    }
    else if (type == ISEQ_TYPE_METHOD || type == ISEQ_TYPE_CLASS) {
	iseq->body->local_iseq = iseq;
    }
    else if (piseq) {
	iseq->body->local_iseq = piseq->body->local_iseq;
    }

    if (piseq) {
	iseq->body->parent_iseq = piseq;
    }

    if (type == ISEQ_TYPE_MAIN) {
	iseq->body->local_iseq = iseq;
    }
}

void
rb_iseq_add_mark_object(const rb_iseq_t *iseq, VALUE obj)
{
    /* TODO: check dedup */
    rb_ary_push(ISEQ_MARK_ARY(iseq), obj);
}

static VALUE
prepare_iseq_build(rb_iseq_t *iseq,
		   VALUE name, VALUE path, VALUE absolute_path, VALUE first_lineno,
		   const rb_iseq_t *parent, enum iseq_type type,
		   const rb_compile_option_t *option)
{
    VALUE coverage = Qfalse;

    iseq->body->type = type;
    set_relation(iseq, parent);

    name = rb_fstring(name);
    path = rb_fstring(path);
    if (RTEST(absolute_path)) absolute_path = rb_fstring(absolute_path);
    iseq_location_setup(iseq, path, absolute_path, name, first_lineno);
    if (iseq != iseq->body->local_iseq) {
	RB_OBJ_WRITE(iseq, &iseq->body->location.base_label, iseq->body->local_iseq->body->location.label);
    }
    RB_OBJ_WRITE(iseq, &iseq->body->mark_ary, iseq_mark_ary_create(0));

    ISEQ_COMPILE_DATA(iseq) = ZALLOC(struct iseq_compile_data);
    RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->err_info, Qnil);
    RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->mark_ary, rb_ary_tmp_new(3));

    ISEQ_COMPILE_DATA(iseq)->storage_head = ISEQ_COMPILE_DATA(iseq)->storage_current =
      (struct iseq_compile_data_storage *)
	ALLOC_N(char, INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE +
		SIZEOF_ISEQ_COMPILE_DATA_STORAGE);

    RB_OBJ_WRITE(iseq, &ISEQ_COMPILE_DATA(iseq)->catch_table_ary, rb_ary_tmp_new(3));
    ISEQ_COMPILE_DATA(iseq)->storage_head->pos = 0;
    ISEQ_COMPILE_DATA(iseq)->storage_head->next = 0;
    ISEQ_COMPILE_DATA(iseq)->storage_head->size =
      INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE;
    ISEQ_COMPILE_DATA(iseq)->option = option;
    ISEQ_COMPILE_DATA(iseq)->last_coverable_line = -1;

    ISEQ_COMPILE_DATA(iseq)->ivar_cache_table = NULL;

    if (option->coverage_enabled) {
	VALUE coverages = rb_get_coverages();
	if (RTEST(coverages)) {
	    coverage = rb_hash_lookup(coverages, path);
	    if (NIL_P(coverage)) coverage = Qfalse;
	}
    }
    ISEQ_COVERAGE_SET(iseq, coverage);

    return Qtrue;
}

static VALUE
cleanup_iseq_build(rb_iseq_t *iseq)
{
    struct iseq_compile_data *data = ISEQ_COMPILE_DATA(iseq);
    VALUE err = data->err_info;
    ISEQ_COMPILE_DATA(iseq) = 0;
    compile_data_free(data);

    if (RTEST(err)) {
	rb_funcallv(err, rb_intern("set_backtrace"), 1, &iseq->body->location.path);
	rb_exc_raise(err);
    }
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
    OPT_TRACE_INSTRUCTION, /* int trace_instruction */
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
    SET_COMPILE_OPTION(option, opt, trace_instruction);
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
	SET_COMPILE_OPTION(option, opt, trace_instruction);
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
rb_iseq_new(NODE *node, VALUE name, VALUE path, VALUE absolute_path,
	    const rb_iseq_t *parent, enum iseq_type type)
{
    return rb_iseq_new_with_opt(node, name, path, absolute_path, INT2FIX(0), parent, type,
				&COMPILE_OPTION_DEFAULT);
}

rb_iseq_t *
rb_iseq_new_top(NODE *node, VALUE name, VALUE path, VALUE absolute_path, const rb_iseq_t *parent)
{
    return rb_iseq_new_with_opt(node, name, path, absolute_path, INT2FIX(0), parent, ISEQ_TYPE_TOP,
				&COMPILE_OPTION_DEFAULT);
}

rb_iseq_t *
rb_iseq_new_main(NODE *node, VALUE path, VALUE absolute_path, const rb_iseq_t *parent)
{
    return rb_iseq_new_with_opt(node, rb_fstring_cstr("<main>"),
				path, absolute_path, INT2FIX(0),
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
rb_iseq_new_with_opt(NODE *node, VALUE name, VALUE path, VALUE absolute_path,
		     VALUE first_lineno, const rb_iseq_t *parent,
		     enum iseq_type type, const rb_compile_option_t *option)
{
    /* TODO: argument check */
    rb_iseq_t *iseq = iseq_alloc();

    if (!option) option = &COMPILE_OPTION_DEFAULT;
    prepare_iseq_build(iseq, name, path, absolute_path, first_lineno, parent, type, option);

    rb_iseq_compile_node(iseq, node);
    cleanup_iseq_build(iseq);

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

#define CHECK_ARRAY(v)   rb_convert_type((v), T_ARRAY, "Array", "to_ary")
#define CHECK_HASH(v)    rb_convert_type((v), T_HASH, "Hash", "to_hash")
#define CHECK_STRING(v)  rb_convert_type((v), T_STRING, "String", "to_str")
#define CHECK_SYMBOL(v)  rb_convert_type((v), T_SYMBOL, "Symbol", "to_sym")
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
    const ID id_defined_guard = rb_intern("defined_guard");
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
    if (typeid == id_defined_guard) return ISEQ_TYPE_DEFINED_GUARD;
    return (enum iseq_type)-1;
}

static VALUE
iseq_load(VALUE data, const rb_iseq_t *parent, VALUE opt)
{
    rb_iseq_t *iseq = iseq_alloc();

    VALUE magic, version1, version2, format_type, misc;
    VALUE name, path, absolute_path, first_lineno;
    VALUE type, body, locals, params, exception;

    st_data_t iseq_type;
    rb_compile_option_t option;
    int i = 0;

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
    absolute_path = rb_ary_entry(data, i++);
    absolute_path = NIL_P(absolute_path) ? Qnil : CHECK_STRING(absolute_path);
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

    make_compile_option(&option, opt);
    option.peephole_optimization = FALSE; /* because peephole optimization can modify original iseq */
    prepare_iseq_build(iseq, name, path, absolute_path, first_lineno,
		       parent, (enum iseq_type)iseq_type, &option);

    rb_iseq_build_from_ary(iseq, misc, locals, params, exception, body);

    cleanup_iseq_build(iseq);

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
rb_iseq_compile_with_option(VALUE src, VALUE file, VALUE absolute_path, VALUE line, const struct rb_block *base_block, VALUE opt)
{
    rb_thread_t *th = GET_THREAD();
    rb_iseq_t *iseq = NULL;
    const rb_iseq_t *const parent = base_block ? vm_block_iseq(base_block) : NULL;
    rb_compile_option_t option;
    const enum iseq_type type = parent ? ISEQ_TYPE_EVAL : ISEQ_TYPE_TOP;
#if !defined(__GNUC__) || (__GNUC__ == 4 && __GNUC_MINOR__ == 8)
# define INITIALIZED volatile /* suppress warnings by gcc 4.8 */
#else
# define INITIALIZED /* volatile */
#endif
    NODE *(*parse)(VALUE vparser, VALUE fname, VALUE file, int start);
    int ln;
    NODE *INITIALIZED node;

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
	node = (*parse)(parser, file, src, ln);
    }

    if (!node) {
	rb_exc_raise(th->errinfo);
    }
    else {
	INITIALIZED VALUE label = parent ?
	    parent->body->location.label :
	    rb_fstring_cstr("<compiled>");
	iseq = rb_iseq_new_with_opt(node, label, file, absolute_path, line,
				    parent, type, &option);
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
    return iseq->body->location.path;
}

VALUE
rb_iseq_absolute_path(const rb_iseq_t *iseq)
{
    return iseq->body->location.absolute_path;
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
    const rb_iseq_t *local_iseq;

    local_iseq = iseq->body->local_iseq;

    if (local_iseq->body->type == ISEQ_TYPE_METHOD) {
	return local_iseq->body->location.base_label;
    }
    else {
	return Qnil;
    }
}

VALUE
rb_iseq_coverage(const rb_iseq_t *iseq)
{
    return ISEQ_COVERAGE(iseq);
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
    return iseq_memsize((const rb_iseq_t *)ptr);
}

static const rb_data_type_t iseqw_data_type = {
    "T_IMEMO/iseq",
    {iseqw_mark, NULL, iseqw_memsize,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED
};

static VALUE
iseqw_new(const rb_iseq_t *iseq)
{
    union { const rb_iseq_t *in; void *out; } deconst;
    VALUE obj;

    deconst.in = iseq;
    obj = TypedData_Wrap_Struct(rb_cISeq, &iseqw_data_type, deconst.out);
    RB_OBJ_WRITTEN(obj, Qundef, iseq);

    return obj;
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
    if (NIL_P(file)) file = rb_fstring_cstr("<compiled>");
    if (NIL_P(line)) line = INT2FIX(1);

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
    VALUE parser, f, exc = Qnil;
    NODE *node;
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
    node = rb_parser_compile_file_path(parser, file, f, NUM2INT(line));
    if (!node) exc = GET_THREAD()->errinfo;

    rb_io_close(f);
    if (!node) rb_exc_raise(exc);

    make_compile_option(&option, opt);

    return iseqw_new(rb_iseq_new_with_opt(node, rb_fstring_cstr("<main>"),
					  file,
					  rb_realpath_internal(Qnil, file, 1),
					  line, NULL, ISEQ_TYPE_TOP, &option));
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
 *  * +:trace_instruction+
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
	ibf_load_iseq_complete(iseq);
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

    if (!iseq->body->location.label) {
        return rb_sprintf("#<%s: uninitialized>", rb_obj_classname(self));
    }
    else {
	return rb_sprintf("<%s:%s@%s>",
			  rb_obj_classname(self),
			  RSTRING_PTR(iseq->body->location.label), RSTRING_PTR(iseq->body->location.path));
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
    return rb_iseq_absolute_path(iseqw_check(self));
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
 *    +:ensure+, +:eval+, +:main+, and +:defined_guard+.
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

/* TODO: search algorithm is brute force.
         this should be binary search or so. */

static const struct iseq_line_info_entry *
get_line_info(const rb_iseq_t *iseq, size_t pos)
{
    size_t i = 0, size = iseq->body->line_info_size;
    const struct iseq_line_info_entry *table = iseq->body->line_info_table;
    const int debug = 0;

    if (debug) {
	printf("size: %"PRIuSIZE"\n", size);
	printf("table[%"PRIuSIZE"]: position: %d, line: %d, pos: %"PRIuSIZE"\n",
	       i, table[i].position, table[i].line_no, pos);
    }

    if (size == 0) {
	return 0;
    }
    else if (size == 1) {
	return &table[0];
    }
    else {
	for (i=1; i<size; i++) {
	    if (debug) printf("table[%"PRIuSIZE"]: position: %d, line: %d, pos: %"PRIuSIZE"\n",
			      i, table[i].position, table[i].line_no, pos);

	    if (table[i].position == pos) {
		return &table[i];
	    }
	    if (table[i].position > pos) {
		return &table[i-1];
	    }
	}
    }
    return &table[i-1];
}

static unsigned int
find_line_no(const rb_iseq_t *iseq, size_t pos)
{
    const struct iseq_line_info_entry *entry = get_line_info(iseq, pos);

    if (entry) {
	return entry->line_no;
    }
    else {
	return 0;
    }
}

unsigned int
rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos)
{
    if (pos == 0) {
	return find_line_no(iseq, pos);
    }
    else {
	return find_line_no(iseq, pos - 1);
    }
}

static VALUE
id_to_name(ID id, VALUE default_value)
{
    VALUE str = rb_id2str(id);
    if (!str) {
	str = default_value;
    }
    else if (!rb_str_symname_p(str)) {
	str = rb_str_inspect(str);
    }
    return str;
}

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
	ret = rb_sprintf("%"PRIuVALUE, op);
	break;

      case TS_LINDEX:{
	if (insn == BIN(getlocal) || insn == BIN(setlocal)) {
	    if (pnop) {
		const rb_iseq_t *diseq = iseq;
		VALUE level = *pnop, i;
		ID lid;

		for (i = 0; i < level; i++) {
		    diseq = diseq->body->parent_iseq;
		}
		lid = diseq->body->local_table[diseq->body->local_table_size +
					       VM_ENV_DATA_SIZE - 1 - op];
		ret = id_to_name(lid, INT2FIX('*'));
	    }
	    else {
		ret = rb_sprintf("%"PRIuVALUE, op);
	    }
	}
	else {
	    ret = rb_inspect(INT2FIX(op));
	}
	break;
      }
      case TS_ID:		/* ID (symbol) */
	op = ID2SYM(op);

      case TS_VALUE:		/* VALUE */
	op = obj_resurrect(op);
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
		if (ci->flag & VM_CALL_ARGS_SPLAT) rb_ary_push(flags, rb_str_new2("ARGS_SPLAT"));
		if (ci->flag & VM_CALL_ARGS_BLOCKARG) rb_ary_push(flags, rb_str_new2("ARGS_BLOCKARG"));
		if (ci->flag & VM_CALL_FCALL) rb_ary_push(flags, rb_str_new2("FCALL"));
		if (ci->flag & VM_CALL_VCALL) rb_ary_push(flags, rb_str_new2("VCALL"));
		if (ci->flag & VM_CALL_TAILCALL) rb_ary_push(flags, rb_str_new2("TAILCALL"));
		if (ci->flag & VM_CALL_SUPER) rb_ary_push(flags, rb_str_new2("SUPER"));
		if (ci->flag & VM_CALL_KWARG) rb_ary_push(flags, rb_str_new2("KWARG"));
		if (ci->flag & VM_CALL_OPT_SEND) rb_ary_push(flags, rb_str_new2("SNED")); /* maybe not reachable */
		if (ci->flag & VM_CALL_ARGS_SIMPLE) rb_ary_push(flags, rb_str_new2("ARGS_SIMPLE")); /* maybe not reachable */
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
	rb_bug("insn_operand_intern: unknown operand type: %c", type);
    }
    return ret;
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
	rb_str_catf(str, "%04"PRIuSIZE" %-16s ", pos, insn_name_buff);
    }
    else {
	rb_str_catf(str, "%04"PRIuSIZE" %-16.*s ", pos,
		    (int)strcspn(insn_name_buff, "_"), insn_name_buff);
    }

    for (j = 0; types[j]; j++) {
	const char *types = insn_op_types(insn);
	VALUE opstr = rb_insn_operand_intern(iseq, insn, j, code[pos + j + 1],
					     len, pos, &code[pos + j + 2],
					     child);
	rb_str_concat(str, opstr);

	if (types[j + 1]) {
	    rb_str_cat2(str, ", ");
	}
    }

    {
	unsigned int line_no = find_line_no(iseq, pos);
	unsigned int prev = pos == 0 ? 0 : find_line_no(iseq, pos - 1);
	if (line_no && line_no != prev) {
	    long slen = RSTRING_LEN(str);
	    slen = (slen > 70) ? 0 : (70 - slen);
	    str = rb_str_catf(str, "%*s(%4d)", (int)slen, "", line_no);
	}
    }

    if (ret) {
	rb_str_cat2(str, "\n");
	rb_str_concat(ret, str);
    }
    else {
	printf("%s\n", RSTRING_PTR(str));
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
	rb_bug("unknown catch type (%d)", type);
	return 0;
    }
}

static VALUE
iseq_inspect(const rb_iseq_t *iseq)
{
    if (!iseq->body->location.label) {
	return rb_sprintf("#<ISeq: uninitialized>");
    }
    else {
	return rb_sprintf("#<ISeq:%s@%s>", RSTRING_PTR(iseq->body->location.label), RSTRING_PTR(iseq->body->location.path));
    }
}

VALUE
rb_iseq_disasm(const rb_iseq_t *iseq)
{
    VALUE *code;
    VALUE str = rb_str_new(0, 0);
    VALUE child = rb_ary_tmp_new(3);
    unsigned int size;
    unsigned int i;
    long l;
    const ID *tbl;
    size_t n;
    enum {header_minlen = 72};

    rb_secure(1);

    size = iseq->body->iseq_size;

    rb_str_cat2(str, "== disasm: ");

    rb_str_concat(str, iseq_inspect(iseq));
    if ((l = RSTRING_LEN(str)) < header_minlen) {
	rb_str_resize(str, header_minlen);
	memset(RSTRING_PTR(str) + l, '=', header_minlen - l);
    }
    rb_str_cat2(str, "\n");

    /* show catch table information */
    if (iseq->body->catch_table) {
	rb_str_cat2(str, "== catch table\n");
    }
    if (iseq->body->catch_table) {
	for (i = 0; i < iseq->body->catch_table->size; i++) {
	    const struct iseq_catch_table_entry *entry = &iseq->body->catch_table->entries[i];
	    rb_str_catf(str,
			"| catch type: %-6s st: %04d ed: %04d sp: %04d cont: %04d\n",
			catch_type((int)entry->type), (int)entry->start,
			(int)entry->end, (int)entry->sp, (int)entry->cont);
	    if (entry->iseq) {
		rb_str_concat(str, rb_iseq_disasm(rb_iseq_check(entry->iseq)));
	    }
	}
    }
    if (iseq->body->catch_table) {
	rb_str_cat2(str, "|-------------------------------------"
		    "-----------------------------------\n");
    }

    /* show local table information */
    tbl = iseq->body->local_table;

    if (tbl) {
	rb_str_catf(str,
		    "local table (size: %d, argc: %d "
		    "[opts: %d, rest: %d, post: %d, block: %d, kw: %d@%d, kwrest: %d])\n",
		    iseq->body->local_table_size,
		    iseq->body->param.lead_num,
		    iseq->body->param.opt_num,
		    iseq->body->param.flags.has_rest ? iseq->body->param.rest_start : -1,
		    iseq->body->param.post_num,
		    iseq->body->param.flags.has_block ? iseq->body->param.block_start : -1,
		    iseq->body->param.flags.has_kw ? iseq->body->param.keyword->num : -1,
		    iseq->body->param.flags.has_kw ? iseq->body->param.keyword->required_num : -1,
		    iseq->body->param.flags.has_kwrest ? iseq->body->param.keyword->rest_start : -1);

	for (i = 0; i < iseq->body->local_table_size; i++) {
	    int li = (int)i;
	    long width;
	    VALUE name = id_to_name(tbl[i], 0);
	    char argi[0x100] = "";
	    char opti[0x100] = "";

	    if (iseq->body->param.flags.has_opt) {
		int argc = iseq->body->param.lead_num;
		int opts = iseq->body->param.opt_num;
		if (li >= argc && li < argc + opts) {
		    snprintf(opti, sizeof(opti), "Opt=%"PRIdVALUE,
			     iseq->body->param.opt_table[li - argc]);
		}
	    }

	    snprintf(argi, sizeof(argi), "%s%s%s%s%s",	/* arg, opts, rest, post  block */
		     iseq->body->param.lead_num > li ? "Arg" : "",
		     opti,
		     (iseq->body->param.flags.has_rest && iseq->body->param.rest_start == li) ? "Rest" : "",
		     (iseq->body->param.flags.has_post && iseq->body->param.post_start <= li && li < iseq->body->param.post_start + iseq->body->param.post_num) ? "Post" : "",
		     (iseq->body->param.flags.has_block && iseq->body->param.block_start == li) ? "Block" : "");

	    rb_str_catf(str, "[%2d] ", iseq->body->local_table_size - i);
	    width = RSTRING_LEN(str) + 11;
	    if (name)
		rb_str_append(str, name);
	    else
		rb_str_cat2(str, "?");
	    if (*argi) rb_str_catf(str, "<%s>", argi);
	    if ((width -= RSTRING_LEN(str)) > 0) rb_str_catf(str, "%*s", (int)width, "");
	}
	rb_str_cat2(str, "\n");
    }

    /* show each line */
    code = rb_iseq_original_iseq(iseq);
    for (n = 0; n < size;) {
	n += rb_iseq_disasm_insn(str, code, n, iseq, child);
    }

    for (l = 0; l < RARRAY_LEN(child); l++) {
	VALUE isv = rb_ary_entry(child, l);
	rb_str_concat(str, rb_iseq_disasm(rb_iseq_check((rb_iseq_t *)isv)));
    }

    return str;
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
    else {
	iseq = rb_method_iseq(body);
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
	rb_bug("unknown node (%d)", node);
	return 0;
    }
}

#define DECL_SYMBOL(name) \
  static VALUE sym_##name

#define INIT_SYMBOL(name) \
  sym_##name = ID2SYM(rb_intern(#name))

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
	rb_bug("exception_type2symbol: unknown type %d", (int)type);
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
    size_t ti;
    unsigned int pos;
    unsigned int line = 0;
    VALUE *seq, *iseq_original;

    VALUE val = rb_ary_new();
    VALUE type; /* Symbol */
    VALUE locals = rb_ary_new();
    VALUE params = rb_hash_new();
    VALUE body = rb_ary_new(); /* [[:insn1, ...], ...] */
    VALUE nbody;
    VALUE exception = rb_ary_new(); /* [[....]] */
    VALUE misc = rb_hash_new();

    static VALUE insn_syms[VM_INSTRUCTION_SIZE];
    struct st_table *labels_table = st_init_numtable();

    DECL_SYMBOL(top);
    DECL_SYMBOL(method);
    DECL_SYMBOL(block);
    DECL_SYMBOL(class);
    DECL_SYMBOL(rescue);
    DECL_SYMBOL(ensure);
    DECL_SYMBOL(eval);
    DECL_SYMBOL(main);
    DECL_SYMBOL(defined_guard);

    if (sym_top == 0) {
	int i;
	for (i=0; i<VM_INSTRUCTION_SIZE; i++) {
	    insn_syms[i] = ID2SYM(rb_intern(insn_name(i)));
	}
	INIT_SYMBOL(top);
	INIT_SYMBOL(method);
	INIT_SYMBOL(block);
	INIT_SYMBOL(class);
	INIT_SYMBOL(rescue);
	INIT_SYMBOL(ensure);
	INIT_SYMBOL(eval);
	INIT_SYMBOL(main);
	INIT_SYMBOL(defined_guard);
    }

    /* type */
    switch (iseq->body->type) {
      case ISEQ_TYPE_TOP:    type = sym_top;    break;
      case ISEQ_TYPE_METHOD: type = sym_method; break;
      case ISEQ_TYPE_BLOCK:  type = sym_block;  break;
      case ISEQ_TYPE_CLASS:  type = sym_class;  break;
      case ISEQ_TYPE_RESCUE: type = sym_rescue; break;
      case ISEQ_TYPE_ENSURE: type = sym_ensure; break;
      case ISEQ_TYPE_EVAL:   type = sym_eval;   break;
      case ISEQ_TYPE_MAIN:   type = sym_main;   break;
      case ISEQ_TYPE_DEFINED_GUARD: type = sym_defined_guard; break;
      default: rb_bug("unsupported iseq type");
    };

    /* locals */
    for (i=0; i<iseq->body->local_table_size; i++) {
	ID lid = iseq->body->local_table[i];
	if (lid) {
	    if (rb_id2str(lid)) {
		rb_ary_push(locals, ID2SYM(lid));
	    }
	    else { /* hidden variable from id_internal() */
		rb_ary_push(locals, ULONG2NUM(iseq->body->local_table_size-i+1));
	    }
	}
	else {
	    rb_ary_push(locals, ID2SYM(rb_intern("#arg_rest")));
	}
    }

    /* params */
    {
	int j;

	if (iseq->body->param.flags.has_opt) {
          int len = iseq->body->param.opt_num + 1;
          VALUE arg_opt_labels = rb_ary_new2(len);

          for (j = 0; j < len; j++) {
              VALUE l = register_label(labels_table, iseq->body->param.opt_table[j]);
              rb_ary_push(arg_opt_labels, l);
          }
          rb_hash_aset(params, ID2SYM(rb_intern("opt")), arg_opt_labels);
        }

	/* commit */
	if (iseq->body->param.flags.has_lead) rb_hash_aset(params, ID2SYM(rb_intern("lead_num")), INT2FIX(iseq->body->param.lead_num));
	if (iseq->body->param.flags.has_post) rb_hash_aset(params, ID2SYM(rb_intern("post_num")), INT2FIX(iseq->body->param.post_num));
	if (iseq->body->param.flags.has_post) rb_hash_aset(params, ID2SYM(rb_intern("post_start")), INT2FIX(iseq->body->param.post_start));
	if (iseq->body->param.flags.has_rest) rb_hash_aset(params, ID2SYM(rb_intern("rest_start")), INT2FIX(iseq->body->param.rest_start));
	if (iseq->body->param.flags.has_block) rb_hash_aset(params, ID2SYM(rb_intern("block_start")), INT2FIX(iseq->body->param.block_start));
	if (iseq->body->param.flags.has_kw) {
	    VALUE keywords = rb_ary_new();
	    int i, j;
	    for (i=0; i<iseq->body->param.keyword->required_num; i++) {
		rb_ary_push(keywords, ID2SYM(iseq->body->param.keyword->table[i]));
	    }
	    for (j=0; i<iseq->body->param.keyword->num; i++, j++) {
		VALUE key = rb_ary_new_from_args(1, ID2SYM(iseq->body->param.keyword->table[i]));
		if (iseq->body->param.keyword->default_values[j] != Qundef) {
		    rb_ary_push(key, iseq->body->param.keyword->default_values[j]);
		}
		rb_ary_push(keywords, key);
	    }

	    rb_hash_aset(params, ID2SYM(rb_intern("kwbits")),
	                 INT2FIX(iseq->body->param.keyword->bits_start));
	    rb_hash_aset(params, ID2SYM(rb_intern("keyword")), keywords);
	}
	if (iseq->body->param.flags.has_kwrest) rb_hash_aset(params, ID2SYM(rb_intern("kwrest")), INT2FIX(iseq->body->param.keyword->rest_start));
	if (iseq->body->param.flags.ambiguous_param0) rb_hash_aset(params, ID2SYM(rb_intern("ambiguous_param0")), Qtrue);
    }

    /* body */
    iseq_original = rb_iseq_original_iseq((rb_iseq_t *)iseq);

    for (seq = iseq_original; seq < iseq_original + iseq->body->iseq_size; ) {
	VALUE insn = *seq++;
	int j, len = insn_len(insn);
	VALUE *nseq = seq + len - 1;
	VALUE ary = rb_ary_new2(len);

	rb_ary_push(ary, insn_syms[insn]);
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
		{
		    union iseq_inline_storage_entry *is = (union iseq_inline_storage_entry *)*seq;
		    rb_ary_push(ary, INT2FIX(is - iseq->body->is_entries));
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
    if (iseq->body->catch_table) for (i=0; i<iseq->body->catch_table->size; i++) {
	VALUE ary = rb_ary_new();
	const struct iseq_catch_table_entry *entry = &iseq->body->catch_table->entries[i];
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
    ti = 0;

    for (l=0, pos=0; l<RARRAY_LEN(nbody); l++) {
	VALUE ary = RARRAY_AREF(nbody, l);
	st_data_t label;

	if (st_lookup(labels_table, pos, &label)) {
	    rb_ary_push(body, (VALUE)label);
	}

	if (ti < iseq->body->line_info_size && iseq->body->line_info_table[ti].position == pos) {
	    line = iseq->body->line_info_table[ti].line_no;
	    rb_ary_push(body, INT2FIX(line));
	    ti++;
	}

	rb_ary_push(body, ary);
	pos += RARRAY_LENINT(ary); /* reject too huge data */
    }
    RB_GC_GUARD(nbody);

    st_free_table(labels_table);

    rb_hash_aset(misc, ID2SYM(rb_intern("arg_size")), INT2FIX(iseq->body->param.size));
    rb_hash_aset(misc, ID2SYM(rb_intern("local_size")), INT2FIX(iseq->body->local_table_size));
    rb_hash_aset(misc, ID2SYM(rb_intern("stack_max")), INT2FIX(iseq->body->stack_max));

    /* TODO: compatibility issue */
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
    rb_ary_push(val, iseq->body->location.label);
    rb_ary_push(val, iseq->body->location.path);
    rb_ary_push(val, iseq->body->location.absolute_path);
    rb_ary_push(val, iseq->body->location.first_lineno);
    rb_ary_push(val, type);
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
    VALUE a, args = rb_ary_new2(iseq->body->param.size);
    ID req, opt, rest, block, key, keyrest;
#define PARAM_TYPE(type) rb_ary_push(a = rb_ary_new2(2), ID2SYM(type))
#define PARAM_ID(i) iseq->body->local_table[(i)]
#define PARAM(i, type) (		      \
	PARAM_TYPE(type),		      \
	rb_id2str(PARAM_ID(i)) ?	      \
	rb_ary_push(a, ID2SYM(PARAM_ID(i))) : \
	a)

    CONST_ID(req, "req");
    CONST_ID(opt, "opt");
    if (is_proc) {
	for (i = 0; i < iseq->body->param.lead_num; i++) {
	    PARAM_TYPE(opt);
	    rb_ary_push(a, rb_id2str(PARAM_ID(i)) ? ID2SYM(PARAM_ID(i)) : Qnil);
	    rb_ary_push(args, a);
	}
    }
    else {
	for (i = 0; i < iseq->body->param.lead_num; i++) {
	    rb_ary_push(args, PARAM(i, req));
	}
    }
    r = iseq->body->param.lead_num + iseq->body->param.opt_num;
    for (; i < r; i++) {
	PARAM_TYPE(opt);
	if (rb_id2str(PARAM_ID(i))) {
	    rb_ary_push(a, ID2SYM(PARAM_ID(i)));
	}
	rb_ary_push(args, a);
    }
    if (iseq->body->param.flags.has_rest) {
	CONST_ID(rest, "rest");
	rb_ary_push(args, PARAM(iseq->body->param.rest_start, rest));
    }
    r = iseq->body->param.post_start + iseq->body->param.post_num;
    if (is_proc) {
	for (i = iseq->body->param.post_start; i < r; i++) {
	    PARAM_TYPE(opt);
	    rb_ary_push(a, rb_id2str(PARAM_ID(i)) ? ID2SYM(PARAM_ID(i)) : Qnil);
	    rb_ary_push(args, a);
	}
    }
    else {
	for (i = iseq->body->param.post_start; i < r; i++) {
	    rb_ary_push(args, PARAM(i, req));
	}
    }
    if (iseq->body->param.flags.has_kw) {
	i = 0;
	if (iseq->body->param.keyword->required_num > 0) {
	    ID keyreq;
	    CONST_ID(keyreq, "keyreq");
	    for (; i < iseq->body->param.keyword->required_num; i++) {
		PARAM_TYPE(keyreq);
		if (rb_id2str(iseq->body->param.keyword->table[i])) {
		    rb_ary_push(a, ID2SYM(iseq->body->param.keyword->table[i]));
		}
		rb_ary_push(args, a);
	    }
	}
	CONST_ID(key, "key");
	for (; i < iseq->body->param.keyword->num; i++) {
	    PARAM_TYPE(key);
	    if (rb_id2str(iseq->body->param.keyword->table[i])) {
		rb_ary_push(a, ID2SYM(iseq->body->param.keyword->table[i]));
	    }
	    rb_ary_push(args, a);
	}
    }
    if (iseq->body->param.flags.has_kwrest) {
	CONST_ID(keyrest, "keyrest");
	rb_ary_push(args, PARAM(iseq->body->param.keyword->rest_start, keyrest));
    }
    if (iseq->body->param.flags.has_block) {
	CONST_ID(block, "block");
	rb_ary_push(args, PARAM(iseq->body->param.block_start, block));
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

/* Experimental tracing support: trace(line) -> trace(specified_line)
 * MRI Specific.
 */

int
rb_iseqw_line_trace_each(VALUE iseqw, int (*func)(int line, rb_event_flag_t *events_ptr, void *d), void *data)
{
    int trace_num = 0;
    unsigned int pos;
    size_t insn;
    const rb_iseq_t *iseq = iseqw_check(iseqw);
    int cont = 1;
    VALUE *iseq_original;

    iseq_original = rb_iseq_original_iseq(iseq);
    for (pos = 0; cont && pos < iseq->body->iseq_size; pos += insn_len(insn)) {
	insn = iseq_original[pos];

	if (insn == BIN(trace)) {
	    rb_event_flag_t current_events;

	    current_events = (rb_event_flag_t)iseq_original[pos+1];

	    if (current_events & RUBY_EVENT_LINE) {
		rb_event_flag_t events = current_events & RUBY_EVENT_SPECIFIED_LINE;
		trace_num++;

		if (func) {
		    int line = find_line_no(iseq, pos);
		    /* printf("line: %d\n", line); */
		    cont = (*func)(line, &events, data);
		    if (current_events != events) {
			VALUE *encoded = (VALUE *)iseq->body->iseq_encoded;
			iseq_original[pos+1] = encoded[pos+1] =
			  (VALUE)(current_events | (events & RUBY_EVENT_SPECIFIED_LINE));
		    }
		}
	    }
	}
    }
    return trace_num;
}

static int
collect_trace(int line, rb_event_flag_t *events_ptr, void *ptr)
{
    VALUE result = (VALUE)ptr;
    rb_ary_push(result, INT2NUM(line));
    return 1;
}

/*
 * <b>Experimental MRI specific feature, only available as C level api.</b>
 *
 * Returns all +specified_line+ events.
 */
VALUE
rb_iseqw_line_trace_all(VALUE iseqw)
{
    VALUE result = rb_ary_new();
    rb_iseqw_line_trace_each(iseqw, collect_trace, (void *)result);
    return result;
}

struct set_specifc_data {
    int pos;
    int set;
    int prev; /* 1: set, 2: unset, 0: not found */
};

static int
line_trace_specify(int line, rb_event_flag_t *events_ptr, void *ptr)
{
    struct set_specifc_data *data = (struct set_specifc_data *)ptr;

    if (data->pos == 0) {
	data->prev = *events_ptr & RUBY_EVENT_SPECIFIED_LINE ? 1 : 2;
	if (data->set) {
	    *events_ptr = *events_ptr | RUBY_EVENT_SPECIFIED_LINE;
	}
	else {
	    *events_ptr = *events_ptr & ~RUBY_EVENT_SPECIFIED_LINE;
	}
	return 0; /* found */
    }
    else {
	data->pos--;
	return 1;
    }
}

/*
 * <b>Experimental MRI specific feature, only available as C level api.</b>
 *
 * Set a +specified_line+ event at the given line position, if the +set+
 * parameter is +true+.
 *
 * This method is useful for building a debugger breakpoint at a specific line.
 *
 * A TypeError is raised if +set+ is not boolean.
 *
 * If +pos+ is a negative integer a TypeError exception is raised.
 */
VALUE
rb_iseqw_line_trace_specify(VALUE iseqval, VALUE pos, VALUE set)
{
    struct set_specifc_data data;

    data.prev = 0;
    data.pos = NUM2INT(pos);
    if (data.pos < 0) rb_raise(rb_eTypeError, "`pos' is negative");

    switch (set) {
      case Qtrue:  data.set = 1; break;
      case Qfalse: data.set = 0; break;
      default:
	rb_raise(rb_eTypeError, "`set' should be true/false");
    }

    rb_iseqw_line_trace_each(iseqval, line_trace_specify, (void *)&data);

    if (data.prev == 0) {
	rb_raise(rb_eTypeError, "`pos' is out of range.");
    }
    return data.prev == 1 ? Qtrue : Qfalse;
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
    VALUE opt;
    rb_scan_args(argc, argv, "01", &opt);
    return iseq_ibf_dump(iseqw_check(self), opt);
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
    return iseqw_new(iseq_ibf_load(str));
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
    return  iseq_ibf_load_extra_data(str);
}

/*
 *  Document-class: RubyVM::InstructionSequence
 *
 *  The InstructionSequence class represents a compiled sequence of
 *  instructions for the Ruby Virtual Machine.
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

#if 0
    /* Now, it is experimental. No discussions, no tests. */
    /* They can be used from C level. Please give us feedback. */
    rb_define_method(rb_cISeq, "line_trace_all", rb_iseqw_line_trace_all, 0);
    rb_define_method(rb_cISeq, "line_trace_specify", rb_iseqw_line_trace_specify, 2);
#else
    (void)rb_iseqw_line_trace_all;
    (void)rb_iseqw_line_trace_specify;
#endif

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
