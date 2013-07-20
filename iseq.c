/**********************************************************************

  iseq.c -

  $Author$
  created at: 2006-07-11(Tue) 09:00:03 +0900

  Copyright (C) 2006 Koichi Sasada

**********************************************************************/

#include "ruby/ruby.h"
#include "internal.h"
#include "eval_intern.h"

/* #define RUBY_MARK_FREE_DEBUG 1 */
#include "gc.h"
#include "vm_core.h"
#include "iseq.h"

#define numberof(array) (int)(sizeof(array) / sizeof((array)[0]))

#include "insns.inc"
#include "insns_info.inc"

#define ISEQ_MAJOR_VERSION 2
#define ISEQ_MINOR_VERSION 0

VALUE rb_cISeq;

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
	ruby_xfree(compile_data);
    }
}

static void
iseq_free(void *ptr)
{
    rb_iseq_t *iseq;
    RUBY_FREE_ENTER("iseq");

    if (ptr) {
	iseq = ptr;
	if (!iseq->orig) {
	    /* It's possible that strings are freed */
	    if (0) {
		RUBY_GC_INFO("%s @ %s\n", RSTRING_PTR(iseq->location.label),
					  RSTRING_PTR(iseq->location.path));
	    }

	    if (iseq->iseq != iseq->iseq_encoded) {
		RUBY_FREE_UNLESS_NULL(iseq->iseq_encoded);
	    }

	    RUBY_FREE_UNLESS_NULL(iseq->iseq);
	    RUBY_FREE_UNLESS_NULL(iseq->line_info_table);
	    RUBY_FREE_UNLESS_NULL(iseq->local_table);
	    RUBY_FREE_UNLESS_NULL(iseq->ic_entries);
	    RUBY_FREE_UNLESS_NULL(iseq->callinfo_entries);
	    RUBY_FREE_UNLESS_NULL(iseq->catch_table);
	    RUBY_FREE_UNLESS_NULL(iseq->arg_opt_table);
	    RUBY_FREE_UNLESS_NULL(iseq->arg_keyword_table);
	    compile_data_free(iseq->compile_data);
	}
	ruby_xfree(ptr);
    }
    RUBY_FREE_LEAVE("iseq");
}

static void
iseq_mark(void *ptr)
{
    RUBY_MARK_ENTER("iseq");

    if (ptr) {
	rb_iseq_t *iseq = ptr;

	RUBY_GC_INFO("%s @ %s\n", RSTRING_PTR(iseq->location.label), RSTRING_PTR(iseq->location.path));
	RUBY_MARK_UNLESS_NULL(iseq->mark_ary);

	RUBY_MARK_UNLESS_NULL(iseq->location.label);
	RUBY_MARK_UNLESS_NULL(iseq->location.base_label);
	RUBY_MARK_UNLESS_NULL(iseq->location.path);
	RUBY_MARK_UNLESS_NULL(iseq->location.absolute_path);

	RUBY_MARK_UNLESS_NULL((VALUE)iseq->cref_stack);
	RUBY_MARK_UNLESS_NULL(iseq->klass);
	RUBY_MARK_UNLESS_NULL(iseq->coverage);
#if 0
	RUBY_MARK_UNLESS_NULL((VALUE)iseq->node);
	RUBY_MARK_UNLESS_NULL(iseq->cached_special_block);
#endif
	RUBY_MARK_UNLESS_NULL(iseq->orig);

	if (iseq->compile_data != 0) {
	    struct iseq_compile_data *const compile_data = iseq->compile_data;
	    RUBY_MARK_UNLESS_NULL(compile_data->mark_ary);
	    RUBY_MARK_UNLESS_NULL(compile_data->err_info);
	    RUBY_MARK_UNLESS_NULL(compile_data->catch_table_ary);
	}
    }
    RUBY_MARK_LEAVE("iseq");
}

static size_t
iseq_memsize(const void *ptr)
{
    size_t size = sizeof(rb_iseq_t);
    const rb_iseq_t *iseq;

    if (ptr) {
	iseq = ptr;
	if (!iseq->orig) {
	    if (iseq->iseq != iseq->iseq_encoded) {
		size += iseq->iseq_size * sizeof(VALUE);
	    }

	    size += iseq->iseq_size * sizeof(VALUE);
	    size += iseq->line_info_size * sizeof(struct iseq_line_info_entry);
	    size += iseq->local_table_size * sizeof(ID);
	    size += iseq->catch_table_size * sizeof(struct iseq_catch_table_entry);
	    size += iseq->arg_opts * sizeof(VALUE);
	    size += iseq->ic_size * sizeof(struct iseq_inline_cache_entry);
	    size += iseq->callinfo_size * sizeof(rb_call_info_t);

	    if (iseq->compile_data) {
		struct iseq_compile_data_storage *cur;

		cur = iseq->compile_data->storage_head;
		while (cur) {
		    size += cur->size + sizeof(struct iseq_compile_data_storage);
		    cur = cur->next;
		}
		size += sizeof(struct iseq_compile_data);
	    }
	}
    }

    return size;
}

static const rb_data_type_t iseq_data_type = {
    "iseq",
    {
	iseq_mark,
	iseq_free,
	iseq_memsize,
    },
};

static VALUE
iseq_alloc(VALUE klass)
{
    rb_iseq_t *iseq;
    return TypedData_Make_Struct(klass, rb_iseq_t, &iseq_data_type, iseq);
}

static rb_iseq_location_t *
iseq_location_setup(rb_iseq_t *iseq, VALUE path, VALUE absolute_path, VALUE name, size_t first_lineno)
{
    rb_iseq_location_t *loc = &iseq->location;
    loc->path = path;
    if (RTEST(absolute_path) && rb_str_cmp(path, absolute_path) == 0)
	loc->absolute_path = path;
    else
	loc->absolute_path = absolute_path;
    loc->label = loc->base_label = name;
    loc->first_lineno = first_lineno;
    return loc;
}

static void
set_relation(rb_iseq_t *iseq, const VALUE parent)
{
    const VALUE type = iseq->type;
    rb_thread_t *th = GET_THREAD();
    rb_iseq_t *piseq;

    /* set class nest stack */
    if (type == ISEQ_TYPE_TOP) {
	/* toplevel is private */
	iseq->cref_stack = NEW_CREF(rb_cObject);
	iseq->cref_stack->nd_refinements = Qnil;
	iseq->cref_stack->nd_visi = NOEX_PRIVATE;
	if (th->top_wrapper) {
	    NODE *cref = NEW_CREF(th->top_wrapper);
	    cref->nd_refinements = Qnil;
	    cref->nd_visi = NOEX_PRIVATE;
	    cref->nd_next = iseq->cref_stack;
	    iseq->cref_stack = cref;
	}
	iseq->local_iseq = iseq;
    }
    else if (type == ISEQ_TYPE_METHOD || type == ISEQ_TYPE_CLASS) {
	iseq->cref_stack = NEW_CREF(0); /* place holder */
	iseq->cref_stack->nd_refinements = Qnil;
	iseq->local_iseq = iseq;
    }
    else if (RTEST(parent)) {
	GetISeqPtr(parent, piseq);
	iseq->cref_stack = piseq->cref_stack;
	iseq->local_iseq = piseq->local_iseq;
    }

    if (RTEST(parent)) {
	GetISeqPtr(parent, piseq);
	iseq->parent_iseq = piseq;
    }

    if (type == ISEQ_TYPE_MAIN) {
	iseq->local_iseq = iseq;
    }
}

void
rb_iseq_add_mark_object(rb_iseq_t *iseq, VALUE obj)
{
    if (!RTEST(iseq->mark_ary)) {
	iseq->mark_ary = rb_ary_tmp_new(3);
	OBJ_UNTRUST(iseq->mark_ary);
	RBASIC(iseq->mark_ary)->klass = 0;
    }
    rb_ary_push(iseq->mark_ary, obj);
}

static VALUE
prepare_iseq_build(rb_iseq_t *iseq,
		   VALUE name, VALUE path, VALUE absolute_path, VALUE first_lineno,
		   VALUE parent, enum iseq_type type, VALUE block_opt,
		   const rb_compile_option_t *option)
{
    iseq->type = type;
    iseq->arg_rest = -1;
    iseq->arg_block = -1;
    iseq->arg_keyword = -1;
    iseq->klass = 0;
    set_relation(iseq, parent);

    OBJ_FREEZE(name);
    OBJ_FREEZE(path);

    iseq_location_setup(iseq, path, absolute_path, name, first_lineno);
    if (iseq != iseq->local_iseq) {
	iseq->location.base_label = iseq->local_iseq->location.label;
    }

    iseq->defined_method_id = 0;
    iseq->mark_ary = 0;


    /*
     * iseq->special_block_builder = GC_GUARDED_PTR_REF(block_opt);
     * iseq->cached_special_block_builder = 0;
     * iseq->cached_special_block = 0;
     */

    iseq->compile_data = ALLOC(struct iseq_compile_data);
    MEMZERO(iseq->compile_data, struct iseq_compile_data, 1);
    iseq->compile_data->err_info = Qnil;
    iseq->compile_data->mark_ary = rb_ary_tmp_new(3);

    iseq->compile_data->storage_head = iseq->compile_data->storage_current =
      (struct iseq_compile_data_storage *)
	ALLOC_N(char, INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE +
		sizeof(struct iseq_compile_data_storage));

    iseq->compile_data->catch_table_ary = rb_ary_new();
    iseq->compile_data->storage_head->pos = 0;
    iseq->compile_data->storage_head->next = 0;
    iseq->compile_data->storage_head->size =
      INITIAL_ISEQ_COMPILE_DATA_STORAGE_BUFF_SIZE;
    iseq->compile_data->storage_head->buff =
      (char *)(&iseq->compile_data->storage_head->buff + 1);
    iseq->compile_data->option = option;
    iseq->compile_data->last_coverable_line = -1;

    iseq->coverage = Qfalse;
    if (!GET_THREAD()->parse_in_eval) {
	VALUE coverages = rb_get_coverages();
	if (RTEST(coverages)) {
	    iseq->coverage = rb_hash_lookup(coverages, path);
	    if (NIL_P(iseq->coverage)) iseq->coverage = Qfalse;
	}
    }

    return Qtrue;
}

static VALUE
cleanup_iseq_build(rb_iseq_t *iseq)
{
    struct iseq_compile_data *data = iseq->compile_data;
    VALUE err = data->err_info;
    iseq->compile_data = 0;
    compile_data_free(data);

    if (RTEST(err)) {
	rb_funcall2(err, rb_intern("set_backtrace"), 1, &iseq->location.path);
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
};
static const rb_compile_option_t COMPILE_OPTION_FALSE = {0};

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
	memset(option, 1, sizeof(rb_compile_option_t));
    }
    else if (CLASS_OF(opt) == rb_cHash) {
	*option = COMPILE_OPTION_DEFAULT;

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
	SET_COMPILE_OPTION_NUM(option, opt, debug_level);
#undef SET_COMPILE_OPTION
#undef SET_COMPILE_OPTION_NUM
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
	SET_COMPILE_OPTION_NUM(option, opt, debug_level);
    }
#undef SET_COMPILE_OPTION
#undef SET_COMPILE_OPTION_NUM
    return opt;
}

VALUE
rb_iseq_new(NODE *node, VALUE name, VALUE path, VALUE absolute_path,
	    VALUE parent, enum iseq_type type)
{
    return rb_iseq_new_with_opt(node, name, path, absolute_path, INT2FIX(0), parent, type,
				&COMPILE_OPTION_DEFAULT);
}

VALUE
rb_iseq_new_top(NODE *node, VALUE name, VALUE path, VALUE absolute_path, VALUE parent)
{
    return rb_iseq_new_with_opt(node, name, path, absolute_path, INT2FIX(0), parent, ISEQ_TYPE_TOP,
				&COMPILE_OPTION_DEFAULT);
}

VALUE
rb_iseq_new_main(NODE *node, VALUE path, VALUE absolute_path)
{
    rb_thread_t *th = GET_THREAD();
    VALUE parent = th->base_block->iseq->self;
    return rb_iseq_new_with_opt(node, rb_str_new2("<main>"), path, absolute_path, INT2FIX(0),
				parent, ISEQ_TYPE_MAIN, &COMPILE_OPTION_DEFAULT);
}

static VALUE
rb_iseq_new_with_bopt_and_opt(NODE *node, VALUE name, VALUE path, VALUE absolute_path, VALUE first_lineno,
				VALUE parent, enum iseq_type type, VALUE bopt,
				const rb_compile_option_t *option)
{
    rb_iseq_t *iseq;
    VALUE self = iseq_alloc(rb_cISeq);

    GetISeqPtr(self, iseq);
    iseq->self = self;

    prepare_iseq_build(iseq, name, path, absolute_path, first_lineno, parent, type, bopt, option);
    rb_iseq_compile_node(self, node);
    cleanup_iseq_build(iseq);
    return self;
}

VALUE
rb_iseq_new_with_opt(NODE *node, VALUE name, VALUE path, VALUE absolute_path, VALUE first_lineno,
		     VALUE parent, enum iseq_type type,
		     const rb_compile_option_t *option)
{
    /* TODO: argument check */
    return rb_iseq_new_with_bopt_and_opt(node, name, path, absolute_path, first_lineno, parent, type,
					   Qfalse, option);
}

VALUE
rb_iseq_new_with_bopt(NODE *node, VALUE name, VALUE path, VALUE absolute_path, VALUE first_lineno,
		       VALUE parent, enum iseq_type type, VALUE bopt)
{
    /* TODO: argument check */
    return rb_iseq_new_with_bopt_and_opt(node, name, path, absolute_path, first_lineno, parent, type,
					   bopt, &COMPILE_OPTION_DEFAULT);
}

#define CHECK_ARRAY(v)   rb_convert_type((v), T_ARRAY, "Array", "to_ary")
#define CHECK_STRING(v)  rb_convert_type((v), T_STRING, "String", "to_str")
#define CHECK_SYMBOL(v)  rb_convert_type((v), T_SYMBOL, "Symbol", "to_sym")
static inline VALUE CHECK_INTEGER(VALUE v) {(void)NUM2LONG(v); return v;}
static VALUE
iseq_load(VALUE self, VALUE data, VALUE parent, VALUE opt)
{
    VALUE iseqval = iseq_alloc(self);

    VALUE magic, version1, version2, format_type, misc;
    VALUE name, path, absolute_path, first_lineno;
    VALUE type, body, locals, args, exception;

    st_data_t iseq_type;
    struct st_table *type_map = 0;
    rb_iseq_t *iseq;
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
    misc        = rb_ary_entry(data, i++); /* TODO */
    ((void)magic, (void)version1, (void)version2, (void)format_type, (void)misc);

    name        = CHECK_STRING(rb_ary_entry(data, i++));
    path        = CHECK_STRING(rb_ary_entry(data, i++));
    absolute_path = rb_ary_entry(data, i++);
    absolute_path = NIL_P(absolute_path) ? Qnil : CHECK_STRING(absolute_path);
    first_lineno = CHECK_INTEGER(rb_ary_entry(data, i++));

    type        = CHECK_SYMBOL(rb_ary_entry(data, i++));
    locals      = CHECK_ARRAY(rb_ary_entry(data, i++));

    args        = rb_ary_entry(data, i++);
    if (FIXNUM_P(args) || (args = CHECK_ARRAY(args))) {
	/* */
    }

    exception   = CHECK_ARRAY(rb_ary_entry(data, i++));
    body        = CHECK_ARRAY(rb_ary_entry(data, i++));

    GetISeqPtr(iseqval, iseq);
    iseq->self = iseqval;

    if (type_map == 0) {
	type_map = st_init_numtable();
	st_insert(type_map, ID2SYM(rb_intern("top")), ISEQ_TYPE_TOP);
	st_insert(type_map, ID2SYM(rb_intern("method")), ISEQ_TYPE_METHOD);
	st_insert(type_map, ID2SYM(rb_intern("block")), ISEQ_TYPE_BLOCK);
	st_insert(type_map, ID2SYM(rb_intern("class")), ISEQ_TYPE_CLASS);
	st_insert(type_map, ID2SYM(rb_intern("rescue")), ISEQ_TYPE_RESCUE);
	st_insert(type_map, ID2SYM(rb_intern("ensure")), ISEQ_TYPE_ENSURE);
	st_insert(type_map, ID2SYM(rb_intern("eval")), ISEQ_TYPE_EVAL);
	st_insert(type_map, ID2SYM(rb_intern("main")), ISEQ_TYPE_MAIN);
	st_insert(type_map, ID2SYM(rb_intern("defined_guard")), ISEQ_TYPE_DEFINED_GUARD);
    }

    if (st_lookup(type_map, type, &iseq_type) == 0) {
	ID typeid = SYM2ID(type);
	VALUE typename = rb_id2str(typeid);
	if (typename)
	    rb_raise(rb_eTypeError, "unsupport type: :%"PRIsVALUE, typename);
	else
	    rb_raise(rb_eTypeError, "unsupport type: %p", (void *)typeid);
    }

    if (parent == Qnil) {
	parent = 0;
    }

    make_compile_option(&option, opt);
    prepare_iseq_build(iseq, name, path, absolute_path, first_lineno,
		       parent, (enum iseq_type)iseq_type, 0, &option);

    rb_iseq_build_from_ary(iseq, locals, args, exception, body);

    cleanup_iseq_build(iseq);
    return iseqval;
}

/*
 * :nodoc:
 */
static VALUE
iseq_s_load(int argc, VALUE *argv, VALUE self)
{
    VALUE data, opt=Qnil;
    rb_scan_args(argc, argv, "11", &data, &opt);

    return iseq_load(self, data, 0, opt);
}

VALUE
rb_iseq_load(VALUE data, VALUE parent, VALUE opt)
{
    return iseq_load(rb_cISeq, data, parent, opt);
}

static NODE *
parse_string(VALUE str, const char *file, int line)
{
    VALUE parser = rb_parser_new();
    NODE *node = rb_parser_compile_string(parser, file, str, line);

    if (!node) {
	rb_exc_raise(GET_THREAD()->errinfo);	/* TODO: check err */
    }
    return node;
}

VALUE
rb_iseq_compile_with_option(VALUE src, VALUE file, VALUE absolute_path, VALUE line, rb_block_t *base_block, VALUE opt)
{
    int state;
    rb_thread_t *th = GET_THREAD();
    rb_block_t *prev_base_block = th->base_block;
    VALUE iseqval = Qundef;

    th->base_block = base_block;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	int ln = NUM2INT(line);
	const char *fn = StringValueCStr(file);
	NODE *node;
	rb_compile_option_t option;

	make_compile_option(&option, opt);

	if (RB_TYPE_P((src), T_FILE))
	    node = rb_compile_file(fn, src, ln);
	else
	    node = parse_string(StringValue(src), fn, ln);

	if (base_block && base_block->iseq) {
	    iseqval = rb_iseq_new_with_opt(node, base_block->iseq->location.label,
					   file, absolute_path, line, base_block->iseq->self,
					   ISEQ_TYPE_EVAL, &option);
	}
	else {
	    iseqval = rb_iseq_new_with_opt(node, rb_str_new2("<compiled>"), file, absolute_path, line, Qfalse,
					   ISEQ_TYPE_TOP, &option);
	}
    }
    TH_POP_TAG();

    th->base_block = prev_base_block;

    if (state) {
	JUMP_TAG(state);
    }

    return iseqval;
}

VALUE
rb_iseq_compile(VALUE src, VALUE file, VALUE line)
{
    return rb_iseq_compile_with_option(src, file, Qnil, line, 0, Qnil);
}

VALUE
rb_iseq_compile_on_base(VALUE src, VALUE file, VALUE line, rb_block_t *base_block)
{
    return rb_iseq_compile_with_option(src, file, Qnil, line, base_block, Qnil);
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
iseq_s_compile(int argc, VALUE *argv, VALUE self)
{
    VALUE src, file = Qnil, path = Qnil, line = INT2FIX(1), opt = Qnil;

    rb_secure(1);

    rb_scan_args(argc, argv, "14", &src, &file, &path, &line, &opt);
    if (NIL_P(file)) file = rb_str_new2("<compiled>");
    if (NIL_P(line)) line = INT2FIX(1);

    return rb_iseq_compile_with_option(src, file, path, line, 0, opt);
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
iseq_s_compile_file(int argc, VALUE *argv, VALUE self)
{
    VALUE file, line = INT2FIX(1), opt = Qnil;
    VALUE parser;
    VALUE f;
    NODE *node;
    const char *fname;
    rb_compile_option_t option;

    rb_secure(1);
    rb_scan_args(argc, argv, "11", &file, &opt);
    FilePathValue(file);
    fname = StringValueCStr(file);

    f = rb_file_open_str(file, "r");

    parser = rb_parser_new();
    node = rb_parser_compile_file(parser, fname, f, NUM2INT(line));
    make_compile_option(&option, opt);
    return rb_iseq_new_with_opt(node, rb_str_new2("<main>"), file,
				rb_realpath_internal(Qnil, file, 1), line, Qfalse,
				ISEQ_TYPE_TOP, &option);
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
iseq_s_compile_option_set(VALUE self, VALUE opt)
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
iseq_s_compile_option_get(VALUE self)
{
    return make_compile_option_value(&COMPILE_OPTION_DEFAULT);
}

static rb_iseq_t *
iseq_check(VALUE val)
{
    rb_iseq_t *iseq;
    GetISeqPtr(val, iseq);
    if (!iseq->location.label) {
	rb_raise(rb_eTypeError, "uninitialized InstructionSequence");
    }
    return iseq;
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
iseq_eval(VALUE self)
{
    rb_secure(1);
    return rb_iseq_eval(self);
}

/*
 *  Returns a human-readable string representation of this instruction
 *  sequence, including the #label and #path.
 */
static VALUE
iseq_inspect(VALUE self)
{
    rb_iseq_t *iseq;
    GetISeqPtr(self, iseq);
    if (!iseq->location.label) {
        return rb_sprintf("#<%s: uninitialized>", rb_obj_classname(self));
    }

    return rb_sprintf("<%s:%s@%s>",
                      rb_obj_classname(self),
		      RSTRING_PTR(iseq->location.label), RSTRING_PTR(iseq->location.path));
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
iseq_path(VALUE self)
{
    rb_iseq_t *iseq;
    GetISeqPtr(self, iseq);
    return iseq->location.path;
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
iseq_absolute_path(VALUE self)
{
    rb_iseq_t *iseq;
    GetISeqPtr(self, iseq);
    return iseq->location.absolute_path;
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
iseq_label(VALUE self)
{
    rb_iseq_t *iseq;
    GetISeqPtr(self, iseq);
    return iseq->location.label;
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
iseq_base_label(VALUE self)
{
    rb_iseq_t *iseq;
    GetISeqPtr(self, iseq);
    return iseq->location.base_label;
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
iseq_first_lineno(VALUE self)
{
    rb_iseq_t *iseq;
    GetISeqPtr(self, iseq);
    return iseq->location.first_lineno;
}

static
VALUE iseq_data_to_ary(rb_iseq_t *iseq);

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
 *  [args]
 *    The arity if the method or block only has required arguments.
 *
 *    Otherwise an array of:
 *
 *      [required_argc, [optional_arg_labels, ...],
 *       splat_index, post_splat_argc, post_splat_index,
 *       block_index, simple]
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
 */
static VALUE
iseq_to_a(VALUE self)
{
    rb_iseq_t *iseq = iseq_check(self);
    rb_secure(1);
    return iseq_data_to_ary(iseq);
}

int
rb_iseq_first_lineno(const rb_iseq_t *iseq)
{
    return FIX2INT(iseq->location.first_lineno);
}

/* TODO: search algorithm is brute force.
         this should be binary search or so. */

static struct iseq_line_info_entry *
get_line_info(const rb_iseq_t *iseq, size_t pos)
{
    size_t i = 0, size = iseq->line_info_size;
    struct iseq_line_info_entry *table = iseq->line_info_table;
    const int debug = 0;

    if (debug) {
	printf("size: %"PRIdSIZE"\n", size);
	printf("table[%"PRIdSIZE"]: position: %d, line: %d, pos: %"PRIdSIZE"\n",
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
	    if (debug) printf("table[%"PRIdSIZE"]: position: %d, line: %d, pos: %"PRIdSIZE"\n",
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
    struct iseq_line_info_entry *entry = get_line_info(iseq, pos);
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
insn_operand_intern(rb_iseq_t *iseq,
		    VALUE insn, int op_no, VALUE op,
		    int len, size_t pos, VALUE *pnop, VALUE child)
{
    const char *types = insn_op_types(insn);
    char type = types[op_no];
    VALUE ret;

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
		rb_iseq_t *diseq = iseq;
		VALUE level = *pnop, i;

		for (i = 0; i < level; i++) {
		    diseq = diseq->parent_iseq;
		}
		ret = id_to_name(diseq->local_table[diseq->local_size - op], INT2FIX('*'));
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
	    rb_iseq_t *iseq = (rb_iseq_t *)op;
	    if (iseq) {
		ret = iseq->location.label;
		if (child) {
		    rb_ary_push(child, iseq->self);
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
	ret = rb_sprintf("<ic:%"PRIdPTRDIFF">", (struct iseq_inline_cache_entry *)op - iseq->ic_entries);
	break;

      case TS_CALLINFO:
	{
	    rb_call_info_t *ci = (rb_call_info_t *)op;
	    VALUE ary = rb_ary_new();

	    if (ci->mid) {
		rb_ary_push(ary, rb_sprintf("mid:%s", rb_id2name(ci->mid)));
	    }

	    rb_ary_push(ary, rb_sprintf("argc:%d", ci->orig_argc));

	    if (ci->blockiseq) {
		if (child) {
		    rb_ary_push(child, ci->blockiseq->self);
		}
		rb_ary_push(ary, rb_sprintf("block:%"PRIsVALUE, ci->blockiseq->location.label));
	    }

	    if (ci->flag) {
		VALUE flags = rb_ary_new();
		if (ci->flag & VM_CALL_ARGS_SPLAT) rb_ary_push(flags, rb_str_new2("ARGS_SPLAT"));
		if (ci->flag & VM_CALL_ARGS_BLOCKARG) rb_ary_push(flags, rb_str_new2("ARGS_BLOCKARG"));
		if (ci->flag & VM_CALL_FCALL) rb_ary_push(flags, rb_str_new2("FCALL"));
		if (ci->flag & VM_CALL_VCALL) rb_ary_push(flags, rb_str_new2("VCALL"));
		if (ci->flag & VM_CALL_TAILCALL) rb_ary_push(flags, rb_str_new2("TAILCALL"));
		if (ci->flag & VM_CALL_SUPER) rb_ary_push(flags, rb_str_new2("SUPER"));
		if (ci->flag & VM_CALL_OPT_SEND) rb_ary_push(flags, rb_str_new2("SNED")); /* maybe not reachable */
		if (ci->flag & VM_CALL_ARGS_SKIP_SETUP) rb_ary_push(flags, rb_str_new2("ARGS_SKIP")); /* maybe not reachable */
		rb_ary_push(ary, rb_ary_join(flags, rb_str_new2("|")));
	    }
	    ret = rb_sprintf("<callinfo!%"PRIsVALUE">", rb_ary_join(ary, rb_str_new2(", ")));
	}
	break;

      case TS_CDHASH:
	ret = rb_str_new2("<cdhash>");
	break;

      case TS_FUNCPTR:
	ret = rb_str_new2("<funcptr>");
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
rb_iseq_disasm_insn(VALUE ret, VALUE *iseq, size_t pos,
		    rb_iseq_t *iseqdat, VALUE child)
{
    VALUE insn = iseq[pos];
    int len = insn_len(insn);
    int j;
    const char *types = insn_op_types(insn);
    VALUE str = rb_str_new(0, 0);
    const char *insn_name_buff;

    insn_name_buff = insn_name(insn);
    if (1) {
	rb_str_catf(str, "%04"PRIdSIZE" %-16s ", pos, insn_name_buff);
    }
    else {
	rb_str_catf(str, "%04"PRIdSIZE" %-16.*s ", pos,
		    (int)strcspn(insn_name_buff, "_"), insn_name_buff);
    }

    for (j = 0; types[j]; j++) {
	const char *types = insn_op_types(insn);
	VALUE opstr = insn_operand_intern(iseqdat, insn, j, iseq[pos + j + 1],
					  len, pos, &iseq[pos + j + 2],
					  child);
	rb_str_concat(str, opstr);

	if (types[j + 1]) {
	    rb_str_cat2(str, ", ");
	}
    }

    {
	unsigned int line_no = find_line_no(iseqdat, pos);
	unsigned int prev = pos == 0 ? 0 : find_line_no(iseqdat, pos - 1);
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
VALUE
rb_iseq_disasm(VALUE self)
{
    rb_iseq_t *iseqdat = iseq_check(self);
    VALUE *iseq;
    VALUE str = rb_str_new(0, 0);
    VALUE child = rb_ary_new();
    unsigned long size;
    int i;
    long l;
    ID *tbl;
    size_t n;
    enum {header_minlen = 72};

    rb_secure(1);

    iseq = iseqdat->iseq;
    size = iseqdat->iseq_size;

    rb_str_cat2(str, "== disasm: ");

    rb_str_concat(str, iseq_inspect(iseqdat->self));
    if ((l = RSTRING_LEN(str)) < header_minlen) {
	rb_str_resize(str, header_minlen);
	memset(RSTRING_PTR(str) + l, '=', header_minlen - l);
    }
    rb_str_cat2(str, "\n");

    /* show catch table information */
    if (iseqdat->catch_table_size != 0) {
	rb_str_cat2(str, "== catch table\n");
    }
    for (i = 0; i < iseqdat->catch_table_size; i++) {
	struct iseq_catch_table_entry *entry = &iseqdat->catch_table[i];
	rb_str_catf(str,
		    "| catch type: %-6s st: %04d ed: %04d sp: %04d cont: %04d\n",
		    catch_type((int)entry->type), (int)entry->start,
		    (int)entry->end, (int)entry->sp, (int)entry->cont);
	if (entry->iseq) {
	    rb_str_concat(str, rb_iseq_disasm(entry->iseq));
	}
    }
    if (iseqdat->catch_table_size != 0) {
	rb_str_cat2(str, "|-------------------------------------"
		    "-----------------------------------\n");
    }

    /* show local table information */
    tbl = iseqdat->local_table;

    if (tbl) {
	rb_str_catf(str,
		    "local table (size: %d, argc: %d "
		    "[opts: %d, rest: %d, post: %d, block: %d] s%d)\n",
		    iseqdat->local_size, iseqdat->argc,
		    iseqdat->arg_opts, iseqdat->arg_rest,
		    iseqdat->arg_post_len, iseqdat->arg_block,
		    iseqdat->arg_simple);

	for (i = 0; i < iseqdat->local_table_size; i++) {
	    long width;
	    VALUE name = id_to_name(tbl[i], 0);
	    char argi[0x100] = "";
	    char opti[0x100] = "";

	    if (iseqdat->arg_opts) {
		int argc = iseqdat->argc;
		int opts = iseqdat->arg_opts;
		if (i >= argc && i < argc + opts - 1) {
		    snprintf(opti, sizeof(opti), "Opt=%"PRIdVALUE,
			     iseqdat->arg_opt_table[i - argc]);
		}
	    }

	    snprintf(argi, sizeof(argi), "%s%s%s%s%s",	/* arg, opts, rest, post  block */
		     iseqdat->argc > i ? "Arg" : "",
		     opti,
		     iseqdat->arg_rest == i ? "Rest" : "",
		     (iseqdat->arg_post_start <= i &&
		      i < iseqdat->arg_post_start + iseqdat->arg_post_len) ? "Post" : "",
		     iseqdat->arg_block == i ? "Block" : "");

	    rb_str_catf(str, "[%2d] ", iseqdat->local_size - i);
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
    for (n = 0; n < size;) {
	n += rb_iseq_disasm_insn(str, iseq, n, iseqdat, child);
    }

    for (i = 0; i < RARRAY_LEN(child); i++) {
	VALUE isv = rb_ary_entry(child, i);
	rb_str_concat(str, rb_iseq_disasm(isv));
    }

    return str;
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
iseq_s_of(VALUE klass, VALUE body)
{
    VALUE ret = Qnil;
    rb_iseq_t *iseq;

    rb_secure(1);

    if (rb_obj_is_proc(body)) {
	rb_proc_t *proc;
	GetProcPtr(body, proc);
	iseq = proc->block.iseq;
	if (RUBY_VM_NORMAL_ISEQ_P(iseq)) {
	    ret = iseq->self;
	}
    }
    else if ((iseq = rb_method_get_iseq(body)) != 0) {
	ret = iseq->self;
    }
    return ret;
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
iseq_s_disasm(VALUE klass, VALUE body)
{
    VALUE iseqval = iseq_s_of(klass, body);
    return NIL_P(iseqval) ? Qnil : rb_iseq_disasm(iseqval);
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
    VALUE sym;
    char buff[8 + (sizeof(idx) * CHAR_BIT * 32 / 100)];

    snprintf(buff, sizeof(buff), "label_%lu", idx);
    sym = ID2SYM(rb_intern(buff));
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
	rb_bug("...");
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
iseq_data_to_ary(rb_iseq_t *iseq)
{
    long i;
    size_t ti;
    unsigned int pos;
    unsigned int line = 0;
    VALUE *seq;

    VALUE val = rb_ary_new();
    VALUE type; /* Symbol */
    VALUE locals = rb_ary_new();
    VALUE args = rb_ary_new();
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
    switch (iseq->type) {
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
    for (i=0; i<iseq->local_table_size; i++) {
	ID lid = iseq->local_table[i];
	if (lid) {
	    if (rb_id2str(lid)) rb_ary_push(locals, ID2SYM(lid));
	}
	else {
	    rb_ary_push(locals, ID2SYM(rb_intern("#arg_rest")));
	}
    }

    /* args */
    {
	/*
	 * [argc,                 # argc
	 *  [label1, label2, ...] # opts
	 *  rest index,
	 *  post_len
	 *  post_start
	 *  block index,
	 *  simple,
         * ]
	 */
	VALUE arg_opt_labels = rb_ary_new();
	int j;

	for (j=0; j<iseq->arg_opts; j++) {
	    rb_ary_push(arg_opt_labels,
			register_label(labels_table, iseq->arg_opt_table[j]));
	}

	/* commit */
	if (iseq->arg_simple == 1) {
	    args = INT2FIX(iseq->argc);
	}
	else {
	    rb_ary_push(args, INT2FIX(iseq->argc));
	    rb_ary_push(args, arg_opt_labels);
	    rb_ary_push(args, INT2FIX(iseq->arg_post_len));
	    rb_ary_push(args, INT2FIX(iseq->arg_post_start));
	    rb_ary_push(args, INT2FIX(iseq->arg_rest));
	    rb_ary_push(args, INT2FIX(iseq->arg_block));
	    rb_ary_push(args, INT2FIX(iseq->arg_simple));
	}
    }

    /* body */
    for (seq = iseq->iseq; seq < iseq->iseq + iseq->iseq_size; ) {
	VALUE insn = *seq++;
	int j, len = insn_len(insn);
	VALUE *nseq = seq + len - 1;
	VALUE ary = rb_ary_new2(len);

	rb_ary_push(ary, insn_syms[insn]);
	for (j=0; j<len-1; j++, seq++) {
	    switch (insn_op_type(insn, j)) {
	      case TS_OFFSET: {
		unsigned long idx = nseq - iseq->iseq + *seq;
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
		    rb_iseq_t *iseq = (rb_iseq_t *)*seq;
		    if (iseq) {
			VALUE val = iseq_data_to_ary(iseq);
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
	      case TS_IC: {
		  struct iseq_inline_cache_entry *ic = (struct iseq_inline_cache_entry *)*seq;
		    rb_ary_push(ary, INT2FIX(ic - iseq->ic_entries));
	        }
		break;
	      case TS_CALLINFO:
		{
		    rb_call_info_t *ci = (rb_call_info_t *)*seq;
		    VALUE e = rb_hash_new();
		    rb_hash_aset(e, ID2SYM(rb_intern("mid")), ci->mid ? ID2SYM(ci->mid) : Qnil);
		    rb_hash_aset(e, ID2SYM(rb_intern("flag")), ULONG2NUM(ci->flag));
		    rb_hash_aset(e, ID2SYM(rb_intern("orig_argc")), INT2FIX(ci->orig_argc));
		    rb_hash_aset(e, ID2SYM(rb_intern("blockptr")), ci->blockiseq ? iseq_data_to_ary(ci->blockiseq) : Qnil);
		    rb_ary_push(ary, e);
	        }
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
			unsigned long idx = nseq - iseq->iseq + pos;

			rb_ary_store(val, i+1,
				     register_label(labels_table, idx));
		    }
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
    for (i=0; i<iseq->catch_table_size; i++) {
	VALUE ary = rb_ary_new();
	struct iseq_catch_table_entry *entry = &iseq->catch_table[i];
	rb_ary_push(ary, exception_type2symbol(entry->type));
	if (entry->iseq) {
	    rb_iseq_t *eiseq;
	    GetISeqPtr(entry->iseq, eiseq);
	    rb_ary_push(ary, iseq_data_to_ary(eiseq));
	}
	else {
	    rb_ary_push(ary, Qnil);
	}
	rb_ary_push(ary, register_label(labels_table, entry->start));
	rb_ary_push(ary, register_label(labels_table, entry->end));
	rb_ary_push(ary, register_label(labels_table, entry->cont));
	rb_ary_push(ary, INT2FIX(entry->sp));
	rb_ary_push(exception, ary);
    }

    /* make body with labels and insert line number */
    body = rb_ary_new();
    ti = 0;

    for (i=0, pos=0; i<RARRAY_LEN(nbody); i++) {
	VALUE ary = RARRAY_PTR(nbody)[i];
	st_data_t label;

	if (st_lookup(labels_table, pos, &label)) {
	    rb_ary_push(body, (VALUE)label);
	}

	if (ti < iseq->line_info_size && iseq->line_info_table[ti].position == pos) {
	    line = iseq->line_info_table[ti].line_no;
	    rb_ary_push(body, INT2FIX(line));
	    ti++;
	}

	rb_ary_push(body, ary);
	pos += RARRAY_LENINT(ary); /* reject too huge data */
    }

    st_free_table(labels_table);

    rb_hash_aset(misc, ID2SYM(rb_intern("arg_size")), INT2FIX(iseq->arg_size));
    rb_hash_aset(misc, ID2SYM(rb_intern("local_size")), INT2FIX(iseq->local_size));
    rb_hash_aset(misc, ID2SYM(rb_intern("stack_max")), INT2FIX(iseq->stack_max));

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
    rb_ary_push(val, iseq->location.label);
    rb_ary_push(val, iseq->location.path);
    rb_ary_push(val, iseq->location.absolute_path);
    rb_ary_push(val, iseq->location.first_lineno);
    rb_ary_push(val, type);
    rb_ary_push(val, locals);
    rb_ary_push(val, args);
    rb_ary_push(val, exception);
    rb_ary_push(val, body);
    return val;
}

VALUE
rb_iseq_clone(VALUE iseqval, VALUE newcbase)
{
    VALUE newiseq = iseq_alloc(rb_cISeq);
    rb_iseq_t *iseq0, *iseq1;

    GetISeqPtr(iseqval, iseq0);
    GetISeqPtr(newiseq, iseq1);

    *iseq1 = *iseq0;
    iseq1->self = newiseq;
    if (!iseq1->orig) {
	iseq1->orig = iseqval;
    }
    if (iseq0->local_iseq == iseq0) {
	iseq1->local_iseq = iseq1;
    }
    if (newcbase) {
	iseq1->cref_stack = NEW_CREF(newcbase);
	iseq1->cref_stack->nd_refinements = iseq0->cref_stack->nd_refinements;
	iseq1->cref_stack->nd_visi = iseq0->cref_stack->nd_visi;
	if (iseq0->cref_stack->nd_next) {
	    iseq1->cref_stack->nd_next = iseq0->cref_stack->nd_next;
	}
	iseq1->klass = newcbase;
    }

    return newiseq;
}

VALUE
rb_iseq_parameters(const rb_iseq_t *iseq, int is_proc)
{
    int i, r;
    VALUE a, args = rb_ary_new2(iseq->arg_size);
    ID req, opt, rest, block, key, keyrest;
#define PARAM_TYPE(type) rb_ary_push(a = rb_ary_new2(2), ID2SYM(type))
#define PARAM_ID(i) iseq->local_table[(i)]
#define PARAM(i, type) (		      \
	PARAM_TYPE(type),		      \
	rb_id2str(PARAM_ID(i)) ?	      \
	rb_ary_push(a, ID2SYM(PARAM_ID(i))) : \
	a)

    CONST_ID(req, "req");
    CONST_ID(opt, "opt");
    if (is_proc) {
	for (i = 0; i < iseq->argc; i++) {
	    PARAM_TYPE(opt);
	    rb_ary_push(a, rb_id2str(PARAM_ID(i)) ? ID2SYM(PARAM_ID(i)) : Qnil);
	    rb_ary_push(args, a);
	}
    }
    else {
	for (i = 0; i < iseq->argc; i++) {
	    rb_ary_push(args, PARAM(i, req));
	}
    }
    r = iseq->argc + iseq->arg_opts - 1;
    for (; i < r; i++) {
	PARAM_TYPE(opt);
	if (rb_id2str(PARAM_ID(i))) {
	    rb_ary_push(a, ID2SYM(PARAM_ID(i)));
	}
	rb_ary_push(args, a);
    }
    if (iseq->arg_rest != -1) {
	CONST_ID(rest, "rest");
	rb_ary_push(args, PARAM(iseq->arg_rest, rest));
    }
    r = iseq->arg_post_start + iseq->arg_post_len;
    if (is_proc) {
	for (i = iseq->arg_post_start; i < r; i++) {
	    PARAM_TYPE(opt);
	    rb_ary_push(a, rb_id2str(PARAM_ID(i)) ? ID2SYM(PARAM_ID(i)) : Qnil);
	    rb_ary_push(args, a);
	}
    }
    else {
	for (i = iseq->arg_post_start; i < r; i++) {
	    rb_ary_push(args, PARAM(i, req));
	}
    }
    if (iseq->arg_keyword != -1) {
	CONST_ID(key, "key");
	for (i = 0; i < iseq->arg_keywords; i++) {
	    PARAM_TYPE(key);
	    if (rb_id2str(iseq->arg_keyword_table[i])) {
		rb_ary_push(a, ID2SYM(iseq->arg_keyword_table[i]));
	    }
	    rb_ary_push(args, a);
	}
	if (rb_id2str(iseq->local_table[iseq->arg_keyword])) {
	    CONST_ID(keyrest, "keyrest");
	    rb_ary_push(args, PARAM(iseq->arg_keyword, keyrest));
	}
    }
    if (iseq->arg_block != -1) {
	CONST_ID(block, "block");
	rb_ary_push(args, PARAM(iseq->arg_block, block));
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
	str = rb_str_new_cstr(estr);;
	OBJ_FREEZE(str);
	defs[type-1] = str;
    }
    return str;
}

/* ruby2cext */

VALUE
rb_iseq_build_for_ruby2cext(
    const rb_iseq_t *iseq_template,
    const rb_insn_func_t *func,
    const struct iseq_line_info_entry *line_info_table,
    const char **local_table,
    const VALUE *arg_opt_table,
    const struct iseq_catch_table_entry *catch_table,
    const char *name,
    const char *path,
    const unsigned short first_lineno)
{
    unsigned long i;
    VALUE iseqval = iseq_alloc(rb_cISeq);
    rb_iseq_t *iseq;
    GetISeqPtr(iseqval, iseq);

    /* copy iseq */
    *iseq = *iseq_template;
    iseq->location.label = rb_str_new2(name);
    iseq->location.path = rb_str_new2(path);
    iseq->location.first_lineno = first_lineno;
    iseq->mark_ary = 0;
    iseq->self = iseqval;

    iseq->iseq = ALLOC_N(VALUE, iseq->iseq_size);

    for (i=0; i<iseq->iseq_size; i+=2) {
	iseq->iseq[i] = BIN(opt_call_c_function);
	iseq->iseq[i+1] = (VALUE)func;
    }

    rb_iseq_translate_threaded_code(iseq);

#define ALLOC_AND_COPY(dst, src, type, size) do { \
  if (size) { \
      (dst) = ALLOC_N(type, (size)); \
      MEMCPY((dst), (src), type, (size)); \
  } \
} while (0)

    ALLOC_AND_COPY(iseq->line_info_table, line_info_table,
		   struct iseq_line_info_entry, iseq->line_info_size);

    ALLOC_AND_COPY(iseq->catch_table, catch_table,
		   struct iseq_catch_table_entry, iseq->catch_table_size);

    ALLOC_AND_COPY(iseq->arg_opt_table, arg_opt_table,
		   VALUE, iseq->arg_opts);

    set_relation(iseq, 0);

    return iseqval;
}

/* Experimental tracing support: trace(line) -> trace(specified_line)
 * MRI Specific.
 */

int
rb_iseq_line_trace_each(VALUE iseqval, int (*func)(int line, rb_event_flag_t *events_ptr, void *d), void *data)
{
    int trace_num = 0;
    size_t pos, insn;
    rb_iseq_t *iseq;
    int cont = 1;
    GetISeqPtr(iseqval, iseq);

    for (pos = 0; cont && pos < iseq->iseq_size; pos += insn_len(insn)) {
	insn = iseq->iseq[pos];

	if (insn == BIN(trace)) {
	    rb_event_flag_t current_events = (VALUE)iseq->iseq[pos+1];

	    if (current_events & RUBY_EVENT_LINE) {
		rb_event_flag_t events = current_events & RUBY_EVENT_SPECIFIED_LINE;
		trace_num++;

		if (func) {
		    int line = find_line_no(iseq, pos);
		    /* printf("line: %d\n", line); */
		    cont = (*func)(line, &events, data);
		    if (current_events != events) {
			iseq->iseq[pos+1] = iseq->iseq_encoded[pos+1] =
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
rb_iseq_line_trace_all(VALUE iseqval)
{
    VALUE result = rb_ary_new();
    rb_iseq_line_trace_each(iseqval, collect_trace, (void *)result);
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
rb_iseq_line_trace_specify(VALUE iseqval, VALUE pos, VALUE set)
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

    rb_iseq_line_trace_each(iseqval, line_trace_specify, (void *)&data);

    if (data.prev == 0) {
	rb_raise(rb_eTypeError, "`pos' is out of range.");
    }
    return data.prev == 1 ? Qtrue : Qfalse;
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
    rb_define_alloc_func(rb_cISeq, iseq_alloc);
    rb_define_method(rb_cISeq, "inspect", iseq_inspect, 0);
    rb_define_method(rb_cISeq, "disasm", rb_iseq_disasm, 0);
    rb_define_method(rb_cISeq, "disassemble", rb_iseq_disasm, 0);
    rb_define_method(rb_cISeq, "to_a", iseq_to_a, 0);
    rb_define_method(rb_cISeq, "eval", iseq_eval, 0);

    /* location APIs */
    rb_define_method(rb_cISeq, "path", iseq_path, 0);
    rb_define_method(rb_cISeq, "absolute_path", iseq_absolute_path, 0);
    rb_define_method(rb_cISeq, "label", iseq_label, 0);
    rb_define_method(rb_cISeq, "base_label", iseq_base_label, 0);
    rb_define_method(rb_cISeq, "first_lineno", iseq_first_lineno, 0);

#if 0
    /* Now, it is experimental. No discussions, no tests. */
    /* They can be used from C level. Please give us feedback. */
    rb_define_method(rb_cISeq, "line_trace_all", rb_iseq_line_trace_all, 0);
    rb_define_method(rb_cISeq, "line_trace_specify", rb_iseq_line_trace_specify, 2);
#else
    (void)rb_iseq_line_trace_all;
    (void)rb_iseq_line_trace_specify;
#endif

#if 0 /* TBD */
    rb_define_private_method(rb_cISeq, "marshal_dump", iseq_marshal_dump, 0);
    rb_define_private_method(rb_cISeq, "marshal_load", iseq_marshal_load, 1);
#endif

    /* disable this feature because there is no verifier. */
    /* rb_define_singleton_method(rb_cISeq, "load", iseq_s_load, -1); */
    (void)iseq_s_load;

    rb_define_singleton_method(rb_cISeq, "compile", iseq_s_compile, -1);
    rb_define_singleton_method(rb_cISeq, "new", iseq_s_compile, -1);
    rb_define_singleton_method(rb_cISeq, "compile_file", iseq_s_compile_file, -1);
    rb_define_singleton_method(rb_cISeq, "compile_option", iseq_s_compile_option_get, 0);
    rb_define_singleton_method(rb_cISeq, "compile_option=", iseq_s_compile_option_set, 1);
    rb_define_singleton_method(rb_cISeq, "disasm", iseq_s_disasm, 1);
    rb_define_singleton_method(rb_cISeq, "disassemble", iseq_s_disasm, 1);
    rb_define_singleton_method(rb_cISeq, "of", iseq_s_of, 1);
}
