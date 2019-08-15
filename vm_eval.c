/**********************************************************************

  vm_eval.c -

  $Author$
  created at: Sat May 24 16:02:32 JST 2008

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

struct local_var_list {
    VALUE tbl;
};

static inline VALUE method_missing(VALUE obj, ID id, int argc, const VALUE *argv, enum method_missing_reason call_status);
static inline VALUE vm_yield_with_cref(rb_execution_context_t *ec, int argc, const VALUE *argv, const rb_cref_t *cref, int is_lambda);
static inline VALUE vm_yield(rb_execution_context_t *ec, int argc, const VALUE *argv);
static inline VALUE vm_yield_with_block(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE block_handler);
static inline VALUE vm_yield_force_blockarg(rb_execution_context_t *ec, VALUE args);
VALUE vm_exec(rb_execution_context_t *ec, int mjit_enable_p);
static void vm_set_eval_stack(rb_execution_context_t * th, const rb_iseq_t *iseq, const rb_cref_t *cref, const struct rb_block *base_block);
static int vm_collect_local_variables_in_heap(const VALUE *dfp, const struct local_var_list *vars);

static VALUE rb_eUncaughtThrow;
static ID id_result, id_tag, id_value;
#define id_mesg idMesg

typedef enum call_type {
    CALL_PUBLIC,
    CALL_FCALL,
    CALL_VCALL,
    CALL_TYPE_MAX
} call_type;

static VALUE send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope);
static VALUE vm_call0_body(rb_execution_context_t* ec, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv);

#ifndef MJIT_HEADER

MJIT_FUNC_EXPORTED VALUE
rb_vm_call0(rb_execution_context_t *ec, VALUE recv, ID id, int argc, const VALUE *argv, const rb_callable_method_entry_t *me)
{
    struct rb_calling_info calling_entry, *calling;
    struct rb_call_info ci_entry;
    struct rb_call_cache cc_entry;

    calling = &calling_entry;

    ci_entry.flag = 0;
    ci_entry.mid = id;

    cc_entry.me = me;

    calling->recv = recv;
    calling->argc = argc;

    return vm_call0_body(ec, calling, &ci_entry, &cc_entry, argv);
}

static VALUE
vm_call0_cfunc_with_frame(rb_execution_context_t* ec, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    VALUE val;
    const rb_callable_method_entry_t *me = cc->me;
    const rb_method_cfunc_t *cfunc = UNALIGNED_MEMBER_PTR(me->def, body.cfunc);
    int len = cfunc->argc;
    VALUE recv = calling->recv;
    int argc = calling->argc;
    ID mid = ci->mid;
    VALUE block_handler = calling->block_handler;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec, me->owner, me->def->original_id);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_CALL, recv, me->def->original_id, mid, me->owner, Qnil);
    {
	rb_control_frame_t *reg_cfp = ec->cfp;

	vm_push_frame(ec, 0, VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL, recv,
		      block_handler, (VALUE)me,
		      0, reg_cfp->sp, 0, 0);

	if (len >= 0) rb_check_arity(argc, len, len);

        val = (*cfunc->invoker)(recv, argc, argv, cfunc->func);

	CHECK_CFP_CONSISTENCY("vm_call0_cfunc_with_frame");
	rb_vm_pop_frame(ec);
    }
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, recv, me->def->original_id, mid, me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);

    return val;
}

static VALUE
vm_call0_cfunc(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    return vm_call0_cfunc_with_frame(ec, calling, ci, cc, argv);
}

/* `ci' should point temporal value (on stack value) */
static VALUE
vm_call0_body(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    VALUE ret;

    calling->block_handler = vm_passed_block_handler(ec);

  again:
    switch (cc->me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
	{
	    rb_control_frame_t *reg_cfp = ec->cfp;
	    int i;

	    CHECK_VM_STACK_OVERFLOW(reg_cfp, calling->argc + 1);
            vm_check_canary(ec, reg_cfp->sp);

	    *reg_cfp->sp++ = calling->recv;
	    for (i = 0; i < calling->argc; i++) {
		*reg_cfp->sp++ = argv[i];
	    }

	    vm_call_iseq_setup(ec, reg_cfp, calling, ci, cc);
	    VM_ENV_FLAGS_SET(ec->cfp->ep, VM_FRAME_FLAG_FINISH);
	    return vm_exec(ec, TRUE); /* CHECK_INTS in this function */
	}
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
	ret = vm_call0_cfunc(ec, calling, ci, cc, argv);
	goto success;
      case VM_METHOD_TYPE_ATTRSET:
	rb_check_arity(calling->argc, 1, 1);
	ret = rb_ivar_set(calling->recv, cc->me->def->body.attr.id, argv[0]);
	goto success;
      case VM_METHOD_TYPE_IVAR:
	rb_check_arity(calling->argc, 0, 0);
	ret = rb_attr_get(calling->recv, cc->me->def->body.attr.id);
	goto success;
      case VM_METHOD_TYPE_BMETHOD:
	ret = vm_call_bmethod_body(ec, calling, ci, cc, argv);
	goto success;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_REFINED:
	{
	    const rb_method_type_t type = cc->me->def->type;
	    VALUE super_class = cc->me->defined_class;

	    if (type == VM_METHOD_TYPE_ZSUPER) {
		super_class = RCLASS_ORIGIN(super_class);
	    }
	    else if (cc->me->def->body.refined.orig_me) {
		cc->me = refined_method_callable_without_refinement(cc->me);
		goto again;
	    }

	    super_class = RCLASS_SUPER(super_class);

	    if (!super_class || !(cc->me = rb_callable_method_entry(super_class, ci->mid))) {
		enum method_missing_reason ex = (type == VM_METHOD_TYPE_ZSUPER) ? MISSING_SUPER : 0;
		ret = method_missing(calling->recv, ci->mid, calling->argc, argv, ex);
		goto success;
	    }
	    RUBY_VM_CHECK_INTS(ec);
	    goto again;
	}
      case VM_METHOD_TYPE_ALIAS:
	cc->me = aliased_callable_method_entry(cc->me);
	goto again;
      case VM_METHOD_TYPE_MISSING:
	{
	    vm_passed_block_handler_set(ec, calling->block_handler);
	    return method_missing(calling->recv, ci->mid, calling->argc,
				  argv, MISSING_NOENTRY);
	}
      case VM_METHOD_TYPE_OPTIMIZED:
	switch (cc->me->def->body.optimize_type) {
	  case OPTIMIZED_METHOD_TYPE_SEND:
	    ret = send_internal(calling->argc, argv, calling->recv, CALL_FCALL);
	    goto success;
	  case OPTIMIZED_METHOD_TYPE_CALL:
	    {
		rb_proc_t *proc;
		GetProcPtr(calling->recv, proc);
		ret = rb_vm_invoke_proc(ec, proc, calling->argc, argv, calling->block_handler);
		goto success;
	    }
	  default:
	    rb_bug("vm_call0: unsupported optimized method type (%d)", cc->me->def->body.optimize_type);
	}
	break;
      case VM_METHOD_TYPE_UNDEF:
	break;
    }
    rb_bug("vm_call0: unsupported method type (%d)", cc->me->def->type);
    return Qundef;

  success:
    RUBY_VM_CHECK_INTS(ec);
    return ret;
}

VALUE
rb_vm_call(rb_execution_context_t *ec, VALUE recv, VALUE id, int argc, const VALUE *argv, const rb_callable_method_entry_t *me)
{
    return rb_vm_call0(ec, recv, id, argc, argv, me);
}

static inline VALUE
vm_call_super(rb_execution_context_t *ec, int argc, const VALUE *argv)
{
    VALUE recv = ec->cfp->self;
    VALUE klass;
    ID id;
    rb_control_frame_t *cfp = ec->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    if (VM_FRAME_RUBYFRAME_P(cfp)) {
	rb_bug("vm_call_super: should not be reached");
    }

    klass = RCLASS_ORIGIN(me->defined_class);
    klass = RCLASS_SUPER(klass);
    id = me->def->original_id;
    me = rb_callable_method_entry(klass, id);

    if (!me) {
	return method_missing(recv, id, argc, argv, MISSING_SUPER);
    }
    else {
        return rb_vm_call0(ec, recv, id, argc, argv, me);
    }
}

VALUE
rb_call_super(int argc, const VALUE *argv)
{
    rb_execution_context_t *ec = GET_EC();
    PASS_PASSED_BLOCK_HANDLER_EC(ec);
    return vm_call_super(ec, argc, argv);
}

VALUE
rb_current_receiver(void)
{
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp;
    if (!ec || !(cfp = ec->cfp)) {
	rb_raise(rb_eRuntimeError, "no self, no life");
    }
    return cfp->self;
}

#endif /* #ifndef MJIT_HEADER */

static inline void
stack_check(rb_execution_context_t *ec)
{
    if (!rb_ec_raised_p(ec, RAISED_STACKOVERFLOW) &&
	rb_ec_stack_check(ec)) {
	rb_ec_raised_set(ec, RAISED_STACKOVERFLOW);
	rb_ec_stack_overflow(ec, FALSE);
    }
}

#ifndef MJIT_HEADER

static inline const rb_callable_method_entry_t *rb_search_method_entry(VALUE recv, ID mid);
static inline enum method_missing_reason rb_method_call_status(rb_execution_context_t *ec, const rb_callable_method_entry_t *me, call_type scope, VALUE self);

/*!
 * \internal
 * calls the specified method.
 *
 * This function is called by functions in rb_call* family.
 * \param ec     current execution context
 * \param recv   receiver of the method
 * \param mid    an ID that represents the name of the method
 * \param argc   the number of method arguments
 * \param argv   a pointer to an array of method arguments
 * \param scope
 * \param self   self in the caller. Qundef means no self is considered and
 *               protected methods cannot be called
 *
 * \note \a self is used in order to controlling access to protected methods.
 */
static inline VALUE
rb_call0(rb_execution_context_t *ec,
	 VALUE recv, ID mid, int argc, const VALUE *argv,
	 call_type scope, VALUE self)
{
    const rb_callable_method_entry_t *me;
    enum method_missing_reason call_status;

    if (scope == CALL_PUBLIC) {
        me = rb_callable_method_entry_with_refinements(CLASS_OF(recv), mid, NULL);
    }
    else {
        me = rb_search_method_entry(recv, mid);
    }
    call_status = rb_method_call_status(ec, me, scope, self);

    if (call_status != MISSING_NONE) {
	return method_missing(recv, mid, argc, argv, call_status);
    }
    stack_check(ec);
    return rb_vm_call0(ec, recv, mid, argc, argv, me);
}

struct rescue_funcall_args {
    VALUE defined_class;
    VALUE recv;
    ID mid;
    rb_execution_context_t *ec;
    const rb_method_entry_t *me;
    unsigned int respond: 1;
    unsigned int respond_to_missing: 1;
    int argc;
    const VALUE *argv;
};

static VALUE
check_funcall_exec(struct rescue_funcall_args *args)
{
    return call_method_entry(args->ec, args->defined_class,
			     args->recv, idMethodMissing,
			     args->me, args->argc, args->argv);
}

static VALUE
check_funcall_failed(struct rescue_funcall_args *args, VALUE e)
{
    int ret = args->respond;
    if (!ret) {
	switch (rb_method_boundp(args->defined_class, args->mid,
				 BOUND_PRIVATE|BOUND_RESPONDS)) {
	  case 2:
	    ret = TRUE;
	    break;
	  case 0:
	    ret = args->respond_to_missing;
	    break;
	  default:
	    ret = FALSE;
	    break;
	}
    }
    if (ret) {
	rb_exc_raise(e);
    }
    return Qundef;
}

static int
check_funcall_respond_to(rb_execution_context_t *ec, VALUE klass, VALUE recv, ID mid)
{
    return vm_respond_to(ec, klass, recv, mid, TRUE);
}

static int
check_funcall_callable(rb_execution_context_t *ec, const rb_callable_method_entry_t *me)
{
    return rb_method_call_status(ec, me, CALL_FCALL, ec->cfp->self) == MISSING_NONE;
}

static VALUE
check_funcall_missing(rb_execution_context_t *ec, VALUE klass, VALUE recv, ID mid, int argc, const VALUE *argv, int respond, VALUE def)
{
    struct rescue_funcall_args args;
    const rb_method_entry_t *me;
    VALUE ret = Qundef;

    ret = basic_obj_respond_to_missing(ec, klass, recv,
				       ID2SYM(mid), Qtrue);
    if (!RTEST(ret)) return def;
    args.respond = respond > 0;
    args.respond_to_missing = (ret != Qundef);
    ret = def;
    me = method_entry_get(klass, idMethodMissing, &args.defined_class);
    if (me && !METHOD_ENTRY_BASIC(me)) {
	VALUE argbuf, *new_args = ALLOCV_N(VALUE, argbuf, argc+1);

	new_args[0] = ID2SYM(mid);
        #ifdef __GLIBC__
        if (!argv) {
            static const VALUE buf = Qfalse;
            VM_ASSERT(argc == 0);
            argv = &buf;
        }
        #endif
	MEMCPY(new_args+1, argv, VALUE, argc);
	ec->method_missing_reason = MISSING_NOENTRY;
	args.ec = ec;
	args.recv = recv;
	args.me = me;
	args.mid = mid;
	args.argc = argc + 1;
	args.argv = new_args;
	ret = rb_rescue2(check_funcall_exec, (VALUE)&args,
			 check_funcall_failed, (VALUE)&args,
			 rb_eNoMethodError, (VALUE)0);
	ALLOCV_END(argbuf);
    }
    return ret;
}

VALUE
rb_check_funcall(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_check_funcall_default(recv, mid, argc, argv, Qundef);
}

VALUE
rb_check_funcall_default(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE def)
{
    VALUE klass = CLASS_OF(recv);
    const rb_callable_method_entry_t *me;
    rb_execution_context_t *ec = GET_EC();
    int respond = check_funcall_respond_to(ec, klass, recv, mid);

    if (!respond)
	return def;

    me = rb_search_method_entry(recv, mid);
    if (!check_funcall_callable(ec, me)) {
	VALUE ret = check_funcall_missing(ec, klass, recv, mid, argc, argv,
					  respond, def);
	if (ret == Qundef) ret = def;
	return ret;
    }
    stack_check(ec);
    return rb_vm_call0(ec, recv, mid, argc, argv, me);
}

VALUE
rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, const VALUE *argv,
			   rb_check_funcall_hook *hook, VALUE arg)
{
    VALUE klass = CLASS_OF(recv);
    const rb_callable_method_entry_t *me;
    rb_execution_context_t *ec = GET_EC();
    int respond = check_funcall_respond_to(ec, klass, recv, mid);

    if (!respond) {
	(*hook)(FALSE, recv, mid, argc, argv, arg);
	return Qundef;
    }

    me = rb_search_method_entry(recv, mid);
    if (!check_funcall_callable(ec, me)) {
	VALUE ret = check_funcall_missing(ec, klass, recv, mid, argc, argv,
					  respond, Qundef);
	(*hook)(ret != Qundef, recv, mid, argc, argv, arg);
	return ret;
    }
    stack_check(ec);
    (*hook)(TRUE, recv, mid, argc, argv, arg);
    return rb_vm_call0(ec, recv, mid, argc, argv, me);
}

const char *
rb_type_str(enum ruby_value_type type)
{
#define type_case(t) t: return #t
    switch (type) {
      case type_case(T_NONE);
      case type_case(T_OBJECT);
      case type_case(T_CLASS);
      case type_case(T_MODULE);
      case type_case(T_FLOAT);
      case type_case(T_STRING);
      case type_case(T_REGEXP);
      case type_case(T_ARRAY);
      case type_case(T_HASH);
      case type_case(T_STRUCT);
      case type_case(T_BIGNUM);
      case type_case(T_FILE);
      case type_case(T_DATA);
      case type_case(T_MATCH);
      case type_case(T_COMPLEX);
      case type_case(T_RATIONAL);
      case type_case(T_NIL);
      case type_case(T_TRUE);
      case type_case(T_FALSE);
      case type_case(T_SYMBOL);
      case type_case(T_FIXNUM);
      case type_case(T_IMEMO);
      case type_case(T_UNDEF);
      case type_case(T_NODE);
      case type_case(T_ICLASS);
      case type_case(T_ZOMBIE);
      case type_case(T_MOVED);
      case T_MASK: break;
    }
#undef type_case
    return NULL;
}

NORETURN(static void uncallable_object(VALUE recv, ID mid));
static void
uncallable_object(VALUE recv, ID mid)
{
    VALUE flags;
    int type;
    const char *typestr;
    VALUE mname = rb_id2str(mid);

    if (SPECIAL_CONST_P(recv)) {
	rb_raise(rb_eNotImpError,
		 "method `%"PRIsVALUE"' called on unexpected immediate object (%p)",
		 mname, (void *)recv);
    }
    else if ((flags = RBASIC(recv)->flags) == 0) {
	rb_raise(rb_eNotImpError,
		 "method `%"PRIsVALUE"' called on terminated object (%p)",
		 mname, (void *)recv);
    }
    else if (!(typestr = rb_type_str(type = BUILTIN_TYPE(recv)))) {
	rb_raise(rb_eNotImpError,
		 "method `%"PRIsVALUE"' called on broken T_?""?""?(0x%02x) object"
		 " (%p flags=0x%"PRIxVALUE")",
		 mname, type, (void *)recv, flags);
    }
    else if (T_OBJECT <= type && type < T_NIL) {
	rb_raise(rb_eNotImpError,
		 "method `%"PRIsVALUE"' called on hidden %s object"
		 " (%p flags=0x%"PRIxVALUE")",
		 mname, typestr, (void *)recv, flags);
    }
    else {
	rb_raise(rb_eNotImpError,
		 "method `%"PRIsVALUE"' called on unexpected %s object"
		 " (%p flags=0x%"PRIxVALUE")",
		 mname, typestr, (void *)recv, flags);
    }
}

static inline const rb_callable_method_entry_t *
rb_search_method_entry(VALUE recv, ID mid)
{
    VALUE klass = CLASS_OF(recv);

    if (!klass) uncallable_object(recv, mid);
    return rb_callable_method_entry(klass, mid);
}

static inline enum method_missing_reason
rb_method_call_status(rb_execution_context_t *ec, const rb_callable_method_entry_t *me, call_type scope, VALUE self)
{
    VALUE klass;
    ID oid;
    rb_method_visibility_t visi;

    if (UNDEFINED_METHOD_ENTRY_P(me)) {
      undefined:
	return scope == CALL_VCALL ? MISSING_VCALL : MISSING_NOENTRY;
    }
    if (me->def->type == VM_METHOD_TYPE_REFINED) {
	me = rb_resolve_refined_method_callable(Qnil, me);
	if (UNDEFINED_METHOD_ENTRY_P(me)) goto undefined;
    }

    klass = me->owner;
    oid = me->def->original_id;
    visi = METHOD_ENTRY_VISI(me);

    if (oid != idMethodMissing) {
	/* receiver specified form for private method */
	if (UNLIKELY(visi != METHOD_VISI_PUBLIC)) {
	    if (visi == METHOD_VISI_PRIVATE && scope == CALL_PUBLIC) {
		return MISSING_PRIVATE;
	    }

	    /* self must be kind of a specified form for protected method */
	    if (visi == METHOD_VISI_PROTECTED && scope == CALL_PUBLIC) {
		VALUE defined_class = klass;

		if (RB_TYPE_P(defined_class, T_ICLASS)) {
		    defined_class = RBASIC(defined_class)->klass;
		}

		if (self == Qundef || !rb_obj_is_kind_of(self, defined_class)) {
		    return MISSING_PROTECTED;
		}
	    }
	}
    }

    return MISSING_NONE;
}


/*!
 * \internal
 * calls the specified method.
 *
 * This function is called by functions in rb_call* family.
 * \param recv   receiver
 * \param mid    an ID that represents the name of the method
 * \param argc   the number of method arguments
 * \param argv   a pointer to an array of method arguments
 * \param scope
 */
static inline VALUE
rb_call(VALUE recv, ID mid, int argc, const VALUE *argv, call_type scope)
{
    rb_execution_context_t *ec = GET_EC();
    return rb_call0(ec, recv, mid, argc, argv, scope, ec->cfp->self);
}

NORETURN(static void raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv,
					  VALUE obj, enum method_missing_reason call_status));

/*
 *  call-seq:
 *     obj.method_missing(symbol [, *args] )   -> result
 *
 *  Invoked by Ruby when <i>obj</i> is sent a message it cannot handle.
 *  <i>symbol</i> is the symbol for the method called, and <i>args</i>
 *  are any arguments that were passed to it. By default, the interpreter
 *  raises an error when this method is called. However, it is possible
 *  to override the method to provide more dynamic behavior.
 *  If it is decided that a particular method should not be handled, then
 *  <i>super</i> should be called, so that ancestors can pick up the
 *  missing method.
 *  The example below creates
 *  a class <code>Roman</code>, which responds to methods with names
 *  consisting of roman numerals, returning the corresponding integer
 *  values.
 *
 *     class Roman
 *       def roman_to_int(str)
 *         # ...
 *       end
 *       def method_missing(methId)
 *         str = methId.id2name
 *         roman_to_int(str)
 *       end
 *     end
 *
 *     r = Roman.new
 *     r.iv      #=> 4
 *     r.xxiii   #=> 23
 *     r.mm      #=> 2000
 */

static VALUE
rb_method_missing(int argc, const VALUE *argv, VALUE obj)
{
    rb_execution_context_t *ec = GET_EC();
    raise_method_missing(ec, argc, argv, obj, ec->method_missing_reason);
    UNREACHABLE_RETURN(Qnil);
}

MJIT_FUNC_EXPORTED VALUE
rb_make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
			    int argc, const VALUE *argv, int priv)
{
    VALUE name = argv[0];

    if (!format) {
	format = rb_fstring_lit("undefined method `%s' for %s%s%s");
    }
    if (exc == rb_eNoMethodError) {
	VALUE args = rb_ary_new4(argc - 1, argv + 1);
	return rb_nomethod_err_new(format, obj, name, args, priv);
    }
    else {
	return rb_name_err_new(format, obj, name);
    }
}

#endif /* #ifndef MJIT_HEADER */

static void
raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE obj,
		     enum method_missing_reason last_call_status)
{
    VALUE exc = rb_eNoMethodError;
    VALUE format = 0;

    if (UNLIKELY(argc == 0)) {
	rb_raise(rb_eArgError, "no method name given");
    }
    else if (UNLIKELY(!SYMBOL_P(argv[0]))) {
	const VALUE e = rb_eArgError; /* TODO: TypeError? */
	rb_raise(e, "method name must be a Symbol but %"PRIsVALUE" is given",
		 rb_obj_class(argv[0]));
    }

    stack_check(ec);

    if (last_call_status & MISSING_PRIVATE) {
	format = rb_fstring_lit("private method `%s' called for %s%s%s");
    }
    else if (last_call_status & MISSING_PROTECTED) {
	format = rb_fstring_lit("protected method `%s' called for %s%s%s");
    }
    else if (last_call_status & MISSING_VCALL) {
	format = rb_fstring_lit("undefined local variable or method `%s' for %s%s%s");
	exc = rb_eNameError;
    }
    else if (last_call_status & MISSING_SUPER) {
	format = rb_fstring_lit("super: no superclass method `%s' for %s%s%s");
    }

    {
	exc = rb_make_no_method_exception(exc, format, obj, argc, argv,
					  last_call_status & (MISSING_FCALL|MISSING_VCALL));
	if (!(last_call_status & MISSING_MISSING)) {
	    rb_vm_pop_cfunc_frame();
	}
	rb_exc_raise(exc);
    }
}

static void
vm_raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv,
			VALUE obj, int call_status)
{
    vm_passed_block_handler_set(ec, VM_BLOCK_HANDLER_NONE);
    raise_method_missing(ec, argc, argv, obj, call_status | MISSING_MISSING);
}

static inline VALUE
method_missing(VALUE obj, ID id, int argc, const VALUE *argv, enum method_missing_reason call_status)
{
    VALUE *nargv, result, work, klass;
    rb_execution_context_t *ec = GET_EC();
    VALUE block_handler = vm_passed_block_handler(ec);
    const rb_callable_method_entry_t *me;

    ec->method_missing_reason = call_status;

    if (id == idMethodMissing) {
      missing:
	raise_method_missing(ec, argc, argv, obj, call_status | MISSING_MISSING);
    }

    nargv = ALLOCV_N(VALUE, work, argc + 1);
    nargv[0] = ID2SYM(id);
    #ifdef __GLIBC__
    if (!argv) {
        static const VALUE buf = Qfalse;
        VM_ASSERT(argc == 0);
        argv = &buf;
    }
    #endif
    MEMCPY(nargv + 1, argv, VALUE, argc);
    ++argc;
    argv = nargv;

    klass = CLASS_OF(obj);
    if (!klass) goto missing;
    me = rb_callable_method_entry(klass, idMethodMissing);
    if (!me || METHOD_ENTRY_BASIC(me)) goto missing;
    vm_passed_block_handler_set(ec, block_handler);
    result = rb_vm_call0(ec, obj, idMethodMissing, argc, argv, me);
    if (work) ALLOCV_END(work);
    return result;
}

#ifndef MJIT_HEADER

/*!
 * Calls a method
 * \param recv   receiver of the method
 * \param mid    an ID that represents the name of the method
 * \param args   an Array object which contains method arguments
 *
 * \pre \a args must refer an Array object.
 */
VALUE
rb_apply(VALUE recv, ID mid, VALUE args)
{
    int argc;
    VALUE *argv, ret;

    argc = RARRAY_LENINT(args);
    if (argc >= 0x100) {
	args = rb_ary_subseq(args, 0, argc);
	RBASIC_CLEAR_CLASS(args);
	OBJ_FREEZE(args);
	ret = rb_call(recv, mid, argc, RARRAY_CONST_PTR(args), CALL_FCALL);
	RB_GC_GUARD(args);
	return ret;
    }
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY_CONST_PTR_TRANSIENT(args), VALUE, argc);
    return rb_call(recv, mid, argc, argv, CALL_FCALL);
}

#undef rb_funcall
/*!
 * Calls a method
 * \param recv   receiver of the method
 * \param mid    an ID that represents the name of the method
 * \param n      the number of arguments
 * \param ...    arbitrary number of method arguments
 *
 * \pre each of arguments after \a n must be a VALUE.
 */
VALUE
rb_funcall(VALUE recv, ID mid, int n, ...)
{
    VALUE *argv;
    va_list ar;

    if (n > 0) {
	long i;

	va_init_list(ar, n);

	argv = ALLOCA_N(VALUE, n);

	for (i = 0; i < n; i++) {
	    argv[i] = va_arg(ar, VALUE);
	}
	va_end(ar);
    }
    else {
	argv = 0;
    }
    return rb_call(recv, mid, n, argv, CALL_FCALL);
}

/*!
 * Calls a method
 * \param recv   receiver of the method
 * \param mid    an ID that represents the name of the method
 * \param argc   the number of arguments
 * \param argv   pointer to an array of method arguments
 */
VALUE
rb_funcallv(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_call(recv, mid, argc, argv, CALL_FCALL);
}

/*!
 * Calls a method.
 *
 * Same as rb_funcallv but this function can call only public methods.
 * \param recv   receiver of the method
 * \param mid    an ID that represents the name of the method
 * \param argc   the number of arguments
 * \param argv   pointer to an array of method arguments
 */
VALUE
rb_funcallv_public(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_call(recv, mid, argc, argv, CALL_PUBLIC);
}

VALUE
rb_funcall_passing_block(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    PASS_PASSED_BLOCK_HANDLER();
    return rb_call(recv, mid, argc, argv, CALL_PUBLIC);
}

VALUE
rb_funcall_with_block(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE passed_procval)
{
    if (!NIL_P(passed_procval)) {
	vm_passed_block_handler_set(GET_EC(), passed_procval);
    }

    return rb_call(recv, mid, argc, argv, CALL_PUBLIC);
}

static VALUE *
current_vm_stack_arg(const rb_execution_context_t *ec, const VALUE *argv)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp);
    if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, prev_cfp)) return NULL;
    if (prev_cfp->sp + 1 != argv) return NULL;
    return prev_cfp->sp + 1;
}

static VALUE
send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope)
{
    ID id;
    VALUE vid;
    VALUE self;
    VALUE ret, vargv = 0;
    rb_execution_context_t *ec = GET_EC();

    if (scope == CALL_PUBLIC) {
	self = Qundef;
    }
    else {
	self = RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp)->self;
    }

    if (argc == 0) {
	rb_raise(rb_eArgError, "no method name given");
    }

    vid = *argv;

    id = rb_check_id(&vid);
    if (!id) {
	if (rb_method_basic_definition_p(CLASS_OF(recv), idMethodMissing)) {
	    VALUE exc = rb_make_no_method_exception(rb_eNoMethodError, 0,
						    recv, argc, argv,
						    scope != CALL_PUBLIC);
	    rb_exc_raise(exc);
	}
	if (!SYMBOL_P(*argv)) {
	    VALUE *tmp_argv = current_vm_stack_arg(ec, argv);
	    vid = rb_str_intern(vid);
	    if (tmp_argv) {
		tmp_argv[0] = vid;
	    }
	    else if (argc > 1) {
		tmp_argv = ALLOCV_N(VALUE, vargv, argc);
		tmp_argv[0] = vid;
		MEMCPY(tmp_argv+1, argv+1, VALUE, argc-1);
		argv = tmp_argv;
	    }
	    else {
		argv = &vid;
	    }
	}
	id = idMethodMissing;
	ec->method_missing_reason = MISSING_NOENTRY;
    }
    else {
	argv++; argc--;
    }
    PASS_PASSED_BLOCK_HANDLER_EC(ec);
    ret = rb_call0(ec, recv, id, argc, argv, scope, self);
    ALLOCV_END(vargv);
    return ret;
}

/*
 * call-seq:
 *    foo.send(symbol [, args...])       -> obj
 *    foo.__send__(symbol [, args...])   -> obj
 *    foo.send(string [, args...])       -> obj
 *    foo.__send__(string [, args...])   -> obj
 *
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. You can use <code>__send__</code> if the name
 *  +send+ clashes with an existing method in _obj_.
 *  When the method is identified by a string, the string is converted
 *  to a symbol.
 *
 *  BasicObject implements +__send__+, Kernel implements +send+.
 *
 *     class Klass
 *       def hello(*args)
 *         "Hello " + args.join(' ')
 *       end
 *     end
 *     k = Klass.new
 *     k.send :hello, "gentle", "readers"   #=> "Hello gentle readers"
 */

VALUE
rb_f_send(int argc, VALUE *argv, VALUE recv)
{
    return send_internal(argc, argv, recv, CALL_FCALL);
}

/*
 *  call-seq:
 *     obj.public_send(symbol [, args...])  -> obj
 *     obj.public_send(string [, args...])  -> obj
 *
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. Unlike send, public_send calls public
 *  methods only.
 *  When the method is identified by a string, the string is converted
 *  to a symbol.
 *
 *     1.public_send(:puts, "hello")  # causes NoMethodError
 */

static VALUE
rb_f_public_send(int argc, VALUE *argv, VALUE recv)
{
    return send_internal(argc, argv, recv, CALL_PUBLIC);
}

/* yield */

static inline VALUE
rb_yield_0(int argc, const VALUE * argv)
{
    return vm_yield(GET_EC(), argc, argv);
}

VALUE
rb_yield_1(VALUE val)
{
    return rb_yield_0(1, &val);
}

VALUE
rb_yield(VALUE val)
{
    if (val == Qundef) {
	return rb_yield_0(0, 0);
    }
    else {
	return rb_yield_1(val);
    }
}

#undef rb_yield_values
VALUE
rb_yield_values(int n, ...)
{
    if (n == 0) {
	return rb_yield_0(0, 0);
    }
    else {
	int i;
	VALUE *argv;
	va_list args;
	argv = ALLOCA_N(VALUE, n);

	va_init_list(args, n);
	for (i=0; i<n; i++) {
	    argv[i] = va_arg(args, VALUE);
	}
	va_end(args);

	return rb_yield_0(n, argv);
    }
}

VALUE
rb_yield_values2(int argc, const VALUE *argv)
{
    return rb_yield_0(argc, argv);
}

VALUE
rb_yield_splat(VALUE values)
{
    VALUE tmp = rb_check_array_type(values);
    VALUE v;
    if (NIL_P(tmp)) {
        rb_raise(rb_eArgError, "not an array");
    }
    v = rb_yield_0(RARRAY_LENINT(tmp), RARRAY_CONST_PTR(tmp));
    RB_GC_GUARD(tmp);
    return v;
}

VALUE
rb_yield_force_blockarg(VALUE values)
{
    return vm_yield_force_blockarg(GET_EC(), values);
}

VALUE
rb_yield_block(VALUE val, VALUE arg, int argc, const VALUE *argv, VALUE blockarg)
{
    return vm_yield_with_block(GET_EC(), argc, argv,
			       NIL_P(blockarg) ? VM_BLOCK_HANDLER_NONE : blockarg);
}

static VALUE
loop_i(void)
{
    for (;;) {
	rb_yield_0(0, 0);
    }
    return Qnil;
}

static VALUE
loop_stop(VALUE dummy, VALUE exc)
{
    return rb_attr_get(exc, id_result);
}

static VALUE
rb_f_loop_size(VALUE self, VALUE args, VALUE eobj)
{
    return DBL2NUM(HUGE_VAL);
}

/*
 *  call-seq:
 *     loop { block }
 *     loop            -> an_enumerator
 *
 *  Repeatedly executes the block.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     loop do
 *       print "Input: "
 *       line = gets
 *       break if !line or line =~ /^qQ/
 *       # ...
 *     end
 *
 *  StopIteration raised in the block breaks the loop.  In this case,
 *  loop returns the "result" value stored in the exception.
 *
 *     enum = Enumerator.new { |y|
 *       y << "one"
 *       y << "two"
 *       :ok
 *     }
 *
 *     result = loop {
 *       puts enum.next
 *     } #=> :ok
 */

static VALUE
rb_f_loop(VALUE self)
{
    RETURN_SIZED_ENUMERATOR(self, 0, 0, rb_f_loop_size);
    return rb_rescue2(loop_i, (VALUE)0, loop_stop, (VALUE)0, rb_eStopIteration, (VALUE)0);
}

#if VMDEBUG
static const char *
vm_frametype_name(const rb_control_frame_t *cfp);
#endif

static VALUE
rb_iterate0(VALUE (* it_proc) (VALUE), VALUE data1,
	    const struct vm_ifunc *const ifunc,
	    rb_execution_context_t *ec)
{
    enum ruby_tag_type state;
    volatile VALUE retval = Qnil;
    rb_control_frame_t *const cfp = ec->cfp;

    EC_PUSH_TAG(ec);
    state = EC_EXEC_TAG();
    if (state == 0) {
      iter_retry:
	{
	    VALUE block_handler;

	    if (ifunc) {
		struct rb_captured_block *captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
		captured->code.ifunc = ifunc;
		block_handler = VM_BH_FROM_IFUNC_BLOCK(captured);
	    }
	    else {
		block_handler = VM_CF_BLOCK_HANDLER(cfp);
	    }
	    vm_passed_block_handler_set(ec, block_handler);
	}
	retval = (*it_proc) (data1);
    }
    else if (state == TAG_BREAK || state == TAG_RETRY) {
	const struct vm_throw_data *const err = (struct vm_throw_data *)ec->errinfo;
	const rb_control_frame_t *const escape_cfp = THROW_DATA_CATCH_FRAME(err);

	if (cfp == escape_cfp) {
	    rb_vm_rewind_cfp(ec, cfp);

	    state = 0;
	    ec->tag->state = TAG_NONE;
	    ec->errinfo = Qnil;

	    if (state == TAG_RETRY) goto iter_retry;
	    retval = THROW_DATA_VAL(err);
	}
	else if (0) {
	    SDR(); fprintf(stderr, "%p, %p\n", (void *)cfp, (void *)escape_cfp);
	}
    }
    EC_POP_TAG();

    if (state) {
	EC_JUMP_TAG(ec, state);
    }
    return retval;
}

VALUE
rb_iterate(VALUE (* it_proc)(VALUE), VALUE data1,
	   VALUE (* bl_proc)(ANYARGS), VALUE data2)
{
    return rb_iterate0(it_proc, data1,
		       bl_proc ? rb_vm_ifunc_proc_new(bl_proc, (void *)data2) : 0,
		       GET_EC());
}

struct iter_method_arg {
    VALUE obj;
    ID mid;
    int argc;
    const VALUE *argv;
};

static VALUE
iterate_method(VALUE obj)
{
    const struct iter_method_arg * arg =
      (struct iter_method_arg *) obj;

    return rb_call(arg->obj, arg->mid, arg->argc, arg->argv, CALL_FCALL);
}

VALUE
rb_block_call(VALUE obj, ID mid, int argc, const VALUE * argv,
	      VALUE (*bl_proc) (ANYARGS), VALUE data2)
{
    struct iter_method_arg arg;

    arg.obj = obj;
    arg.mid = mid;
    arg.argc = argc;
    arg.argv = argv;
    return rb_iterate(iterate_method, (VALUE)&arg, bl_proc, data2);
}

VALUE
rb_lambda_call(VALUE obj, ID mid, int argc, const VALUE *argv,
	       rb_block_call_func_t bl_proc, int min_argc, int max_argc,
	       VALUE data2)
{
    struct iter_method_arg arg;
    struct vm_ifunc *block;

    if (!bl_proc) rb_raise(rb_eArgError, "NULL lambda function");
    arg.obj = obj;
    arg.mid = mid;
    arg.argc = argc;
    arg.argv = argv;
    block = rb_vm_ifunc_new(bl_proc, (void *)data2, min_argc, max_argc);
    return rb_iterate0(iterate_method, (VALUE)&arg, block, GET_EC());
}

static VALUE
iterate_check_method(VALUE obj)
{
    const struct iter_method_arg * arg =
      (struct iter_method_arg *) obj;

    return rb_check_funcall(arg->obj, arg->mid, arg->argc, arg->argv);
}

VALUE
rb_check_block_call(VALUE obj, ID mid, int argc, const VALUE *argv,
		    VALUE (*bl_proc) (ANYARGS), VALUE data2)
{
    struct iter_method_arg arg;

    arg.obj = obj;
    arg.mid = mid;
    arg.argc = argc;
    arg.argv = argv;
    return rb_iterate(iterate_check_method, (VALUE)&arg, bl_proc, data2);
}

VALUE
rb_each(VALUE obj)
{
    return rb_call(obj, idEach, 0, 0, CALL_FCALL);
}

void rb_parser_warn_location(VALUE, int);
static const rb_iseq_t *
eval_make_iseq(VALUE src, VALUE fname, int line, const rb_binding_t *bind,
	       const struct rb_block *base_block)
{
    const VALUE parser = rb_parser_new();
    const rb_iseq_t *const parent = vm_block_iseq(base_block);
    VALUE realpath = Qnil;
    rb_iseq_t *iseq = 0;
    rb_ast_t *ast;

    if (!fname) {
	fname = rb_source_location(&line);
    }

    if (fname != Qundef) {
        if (!NIL_P(fname)) fname = rb_fstring(fname);
	realpath = fname;
    }
    else if (bind) {
	fname = pathobj_path(bind->pathobj);
	realpath = pathobj_realpath(bind->pathobj);
	line = bind->first_lineno;
	rb_parser_warn_location(parser, TRUE);
    }
    else {
        fname = rb_fstring_lit("(eval)");
    }

    rb_parser_set_context(parser, base_block, FALSE);
    ast = rb_parser_compile_string_path(parser, fname, src, line);
    if (ast->body.root) {
	iseq = rb_iseq_new_with_opt(&ast->body,
				    parent->body->location.label,
				    fname, realpath, INT2FIX(line),
				    parent, ISEQ_TYPE_EVAL, NULL);
    }
    rb_ast_dispose(ast);

    if (0 && iseq) {		/* for debug */
	VALUE disasm = rb_iseq_disasm(iseq);
	printf("%s\n", StringValuePtr(disasm));
    }

    rb_exec_event_hook_script_compiled(GET_EC(), iseq, src);

    return iseq;
}

static VALUE
eval_string_with_cref(VALUE self, VALUE src, rb_cref_t *cref, VALUE file, int line)
{
    rb_execution_context_t *ec = GET_EC();
    struct rb_block block;
    const rb_iseq_t *iseq;
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    if (!cfp) {
	rb_raise(rb_eRuntimeError, "Can't eval on top of Fiber or Thread");
    }

    block.as.captured = *VM_CFP_TO_CAPTURED_BLOCK(cfp);
    block.as.captured.self = self;
    block.as.captured.code.iseq = cfp->iseq;
    block.type = block_type_iseq;

    iseq = eval_make_iseq(src, file, line, NULL, &block);
    if (!iseq) {
	rb_exc_raise(ec->errinfo);
    }

    /* TODO: what the code checking? */
    if (!cref && block.as.captured.code.val) {
        rb_cref_t *orig_cref = vm_get_cref(vm_block_ep(&block));
	cref = vm_cref_dup(orig_cref);
    }
    vm_set_eval_stack(ec, iseq, cref, &block);

    /* kick */
    return vm_exec(ec, TRUE);
}

static VALUE
eval_string_with_scope(VALUE scope, VALUE src, VALUE file, int line)
{
    rb_execution_context_t *ec = GET_EC();
    rb_binding_t *bind = Check_TypedStruct(scope, &ruby_binding_data_type);
    const rb_iseq_t *iseq = eval_make_iseq(src, file, line, bind, &bind->block);
    if (!iseq) {
	rb_exc_raise(ec->errinfo);
    }

    vm_set_eval_stack(ec, iseq, NULL, &bind->block);

    /* save new env */
    if (iseq->body->local_table_size > 0) {
	vm_bind_update_env(scope, bind, vm_make_env_object(ec, ec->cfp));
    }

    /* kick */
    return vm_exec(ec, TRUE);
}

/*
 *  call-seq:
 *     eval(string [, binding [, filename [,lineno]]])  -> obj
 *
 *  Evaluates the Ruby expression(s) in <em>string</em>. If
 *  <em>binding</em> is given, which must be a Binding object, the
 *  evaluation is performed in its context. If the optional
 *  <em>filename</em> and <em>lineno</em> parameters are present, they
 *  will be used when reporting syntax errors.
 *
 *     def get_binding(str)
 *       return binding
 *     end
 *     str = "hello"
 *     eval "str + ' Fred'"                      #=> "hello Fred"
 *     eval "str + ' Fred'", get_binding("bye")  #=> "bye Fred"
 */

VALUE
rb_f_eval(int argc, const VALUE *argv, VALUE self)
{
    VALUE src, scope, vfile, vline;
    VALUE file = Qundef;
    int line = 1;

    rb_scan_args(argc, argv, "13", &src, &scope, &vfile, &vline);
    SafeStringValue(src);
    if (argc >= 3) {
	StringValue(vfile);
    }
    if (argc >= 4) {
	line = NUM2INT(vline);
    }

    if (!NIL_P(vfile))
	file = vfile;

    if (NIL_P(scope))
	return eval_string_with_cref(self, src, NULL, file, line);
    else
	return eval_string_with_scope(scope, src, file, line);
}

/** @note This function name is not stable. */
VALUE
ruby_eval_string_from_file(const char *str, const char *filename)
{
    VALUE file = filename ? rb_str_new_cstr(filename) : 0;
    return eval_string_with_cref(rb_vm_top_self(), rb_str_new2(str), NULL, file, 1);
}

struct eval_string_from_file_arg {
    VALUE str;
    VALUE filename;
};

static VALUE
eval_string_from_file_helper(VALUE data)
{
    const struct eval_string_from_file_arg *const arg = (struct eval_string_from_file_arg*)data;
    return eval_string_with_cref(rb_vm_top_self(), arg->str, NULL, arg->filename, 1);
}

VALUE
ruby_eval_string_from_file_protect(const char *str, const char *filename, int *state)
{
    struct eval_string_from_file_arg arg;
    arg.str = rb_str_new_cstr(str);
    arg.filename = filename ? rb_str_new_cstr(filename) : 0;
    return rb_protect(eval_string_from_file_helper, (VALUE)&arg, state);
}

/**
 * Evaluates the given string in an isolated binding.
 *
 * Here "isolated" means the binding does not inherit any other binding. This
 * behaves same as the binding for required libraries.
 *
 * __FILE__ will be "(eval)", and __LINE__ starts from 1 in the evaluation.
 *
 * @param str Ruby code to evaluate.
 * @return The evaluated result.
 * @throw Exception   Raises an exception on error.
 */
VALUE
rb_eval_string(const char *str)
{
    return ruby_eval_string_from_file(str, "eval");
}

static VALUE
eval_string_protect(VALUE str)
{
    return rb_eval_string((char *)str);
}

/**
 * Evaluates the given string in an isolated binding.
 *
 * __FILE__ will be "(eval)", and __LINE__ starts from 1 in the evaluation.
 *
 * @sa rb_eval_string
 * @param str Ruby code to evaluate.
 * @param state Being set to zero if succeeded. Nonzero if an error occurred.
 * @return The evaluated result if succeeded, an undefined value if otherwise.
 */
VALUE
rb_eval_string_protect(const char *str, int *pstate)
{
    return rb_protect(eval_string_protect, (VALUE)str, pstate);
}

/**
 * Evaluates the given string under a module binding in an isolated binding.
 * This is same as the binding for loaded libraries on "load('foo', true)".
 *
 * __FILE__ will be "(eval)", and __LINE__ starts from 1 in the evaluation.
 *
 * @sa rb_eval_string
 * @param str Ruby code to evaluate.
 * @param state Being set to zero if succeeded. Nonzero if an error occurred.
 * @return The evaluated result if succeeded, an undefined value if otherwise.
 */
VALUE
rb_eval_string_wrap(const char *str, int *pstate)
{
    int state;
    rb_thread_t *th = GET_THREAD();
    VALUE self = th->top_self;
    VALUE wrapper = th->top_wrapper;
    VALUE val;

    th->top_wrapper = rb_module_new();
    th->top_self = rb_obj_clone(rb_vm_top_self());
    rb_extend_object(th->top_self, th->top_wrapper);

    val = rb_eval_string_protect(str, &state);

    th->top_self = self;
    th->top_wrapper = wrapper;

    if (pstate) {
	*pstate = state;
    }
    else if (state != TAG_NONE) {
	EC_JUMP_TAG(th->ec, state);
    }
    return val;
}

VALUE
rb_eval_cmd(VALUE cmd, VALUE arg, int level)
{
    enum ruby_tag_type state;
    volatile VALUE val = Qnil;		/* OK */
    const int VAR_NOCLOBBERED(current_safe_level) = rb_safe_level();
    rb_execution_context_t * volatile ec = GET_EC();

    if (OBJ_TAINTED(cmd)) {
	level = RUBY_SAFE_LEVEL_MAX;
    }

    EC_PUSH_TAG(ec);
    rb_set_safe_level_force(level);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	if (!RB_TYPE_P(cmd, T_STRING)) {
	    val = rb_funcallv(cmd, idCall, RARRAY_LENINT(arg),
			      RARRAY_CONST_PTR(arg));
	}
	else {
	    val = eval_string_with_cref(rb_vm_top_self(), cmd, NULL, 0, 0);
	}
    }
    EC_POP_TAG();

    rb_set_safe_level_force(current_safe_level);
    if (state) EC_JUMP_TAG(ec, state);
    return val;
}

/* block eval under the class/module context */

static VALUE
yield_under(VALUE under, VALUE self, int argc, const VALUE *argv)
{
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    VALUE block_handler = VM_CF_BLOCK_HANDLER(cfp);
    VALUE new_block_handler = 0;
    const struct rb_captured_block *captured = NULL;
    struct rb_captured_block new_captured;
    const VALUE *ep = NULL;
    rb_cref_t *cref;
    int is_lambda = FALSE;

    if (block_handler != VM_BLOCK_HANDLER_NONE) {
      again:
	switch (vm_block_handler_type(block_handler)) {
	  case block_handler_type_iseq:
	    captured = VM_BH_TO_CAPT_BLOCK(block_handler);
	    new_captured = *captured;
	    new_block_handler = VM_BH_FROM_ISEQ_BLOCK(&new_captured);
	    break;
	  case block_handler_type_ifunc:
	    captured = VM_BH_TO_CAPT_BLOCK(block_handler);
	    new_captured = *captured;
	    new_block_handler = VM_BH_FROM_IFUNC_BLOCK(&new_captured);
	    break;
	  case block_handler_type_proc:
	    is_lambda = rb_proc_lambda_p(block_handler) != Qfalse;
	    block_handler = vm_proc_to_block_handler(VM_BH_TO_PROC(block_handler));
	    goto again;
	  case block_handler_type_symbol:
	    return rb_sym_proc_call(SYM2ID(VM_BH_TO_SYMBOL(block_handler)),
				    argc, argv, VM_BLOCK_HANDLER_NONE);
	}

	new_captured.self = self;
	ep = captured->ep;

	VM_FORCE_WRITE_SPECIAL_CONST(&VM_CF_LEP(ec->cfp)[VM_ENV_DATA_INDEX_SPECVAL], new_block_handler);
    }

    cref = vm_cref_push(ec, under, ep, TRUE);
    return vm_yield_with_cref(ec, argc, argv, cref, is_lambda);
}

VALUE
rb_yield_refine_block(VALUE refinement, VALUE refinements)
{
    rb_execution_context_t *ec = GET_EC();
    VALUE block_handler = VM_CF_BLOCK_HANDLER(ec->cfp);

    if (vm_block_handler_type(block_handler) != block_handler_type_iseq) {
	rb_bug("rb_yield_refine_block: an iseq block is required");
    }
    else {
	const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(block_handler);
	struct rb_captured_block new_captured = *captured;
	VALUE new_block_handler = VM_BH_FROM_ISEQ_BLOCK(&new_captured);
	const VALUE *ep = captured->ep;
	rb_cref_t *cref = vm_cref_push(ec, refinement, ep, TRUE);
	CREF_REFINEMENTS_SET(cref, refinements);
	VM_FORCE_WRITE_SPECIAL_CONST(&VM_CF_LEP(ec->cfp)[VM_ENV_DATA_INDEX_SPECVAL], new_block_handler);
	new_captured.self = refinement;
	return vm_yield_with_cref(ec, 0, NULL, cref, FALSE);
    }
}

/* string eval under the class/module context */
static VALUE
eval_under(VALUE under, VALUE self, VALUE src, VALUE file, int line)
{
    rb_cref_t *cref = vm_cref_push(GET_EC(), under, NULL, SPECIAL_CONST_P(self) && !NIL_P(under));
    SafeStringValue(src);
    return eval_string_with_cref(self, src, cref, file, line);
}

static VALUE
specific_eval(int argc, const VALUE *argv, VALUE klass, VALUE self)
{
    if (rb_block_given_p()) {
	rb_check_arity(argc, 0, 0);
	return yield_under(klass, self, 1, &self);
    }
    else {
	VALUE file = Qundef;
	int line = 1;
	VALUE code;

	rb_check_arity(argc, 1, 3);
	code = argv[0];
	SafeStringValue(code);
	if (argc > 2)
	    line = NUM2INT(argv[2]);
	if (argc > 1) {
	    file = argv[1];
	    if (!NIL_P(file)) StringValue(file);
	}
	return eval_under(klass, self, code, file, line);
    }
}

static VALUE
singleton_class_for_eval(VALUE self)
{
    if (SPECIAL_CONST_P(self)) {
	return rb_special_singleton_class(self);
    }
    switch (BUILTIN_TYPE(self)) {
      case T_FLOAT: case T_BIGNUM: case T_SYMBOL:
	return Qnil;
      case T_STRING:
	if (FL_TEST_RAW(self, RSTRING_FSTR)) return Qnil;
      default:
	return rb_singleton_class(self);
    }
}

/*
 *  call-seq:
 *     obj.instance_eval(string [, filename [, lineno]] )   -> obj
 *     obj.instance_eval {|obj| block }                     -> obj
 *
 *  Evaluates a string containing Ruby source code, or the given block,
 *  within the context of the receiver (_obj_). In order to set the
 *  context, the variable +self+ is set to _obj_ while
 *  the code is executing, giving the code access to _obj_'s
 *  instance variables and private methods.
 *
 *  When <code>instance_eval</code> is given a block, _obj_ is also
 *  passed in as the block's only argument.
 *
 *  When <code>instance_eval</code> is given a +String+, the optional
 *  second and third parameters supply a filename and starting line number
 *  that are used when reporting compilation errors.
 *
 *     class KlassWithSecret
 *       def initialize
 *         @secret = 99
 *       end
 *       private
 *       def the_secret
 *         "Ssssh! The secret is #{@secret}."
 *       end
 *     end
 *     k = KlassWithSecret.new
 *     k.instance_eval { @secret }          #=> 99
 *     k.instance_eval { the_secret }       #=> "Ssssh! The secret is 99."
 *     k.instance_eval {|obj| obj == self } #=> true
 */

VALUE
rb_obj_instance_eval(int argc, const VALUE *argv, VALUE self)
{
    VALUE klass = singleton_class_for_eval(self);
    return specific_eval(argc, argv, klass, self);
}

/*
 *  call-seq:
 *     obj.instance_exec(arg...) {|var...| block }                       -> obj
 *
 *  Executes the given block within the context of the receiver
 *  (_obj_). In order to set the context, the variable +self+ is set
 *  to _obj_ while the code is executing, giving the code access to
 *  _obj_'s instance variables.  Arguments are passed as block parameters.
 *
 *     class KlassWithSecret
 *       def initialize
 *         @secret = 99
 *       end
 *     end
 *     k = KlassWithSecret.new
 *     k.instance_exec(5) {|x| @secret+x }   #=> 104
 */

VALUE
rb_obj_instance_exec(int argc, const VALUE *argv, VALUE self)
{
    VALUE klass = singleton_class_for_eval(self);
    return yield_under(klass, self, argc, argv);
}

/*
 *  call-seq:
 *     mod.class_eval(string [, filename [, lineno]])  -> obj
 *     mod.class_eval {|mod| block }                   -> obj
 *     mod.module_eval(string [, filename [, lineno]]) -> obj
 *     mod.module_eval {|mod| block }                  -> obj
 *
 *  Evaluates the string or block in the context of _mod_, except that when
 *  a block is given, constant/class variable lookup is not affected. This
 *  can be used to add methods to a class. <code>module_eval</code> returns
 *  the result of evaluating its argument. The optional _filename_ and
 *  _lineno_ parameters set the text for error messages.
 *
 *     class Thing
 *     end
 *     a = %q{def hello() "Hello there!" end}
 *     Thing.module_eval(a)
 *     puts Thing.new.hello()
 *     Thing.module_eval("invalid code", "dummy", 123)
 *
 *  <em>produces:</em>
 *
 *     Hello there!
 *     dummy:123:in `module_eval': undefined local variable
 *         or method `code' for Thing:Class
 */

VALUE
rb_mod_module_eval(int argc, const VALUE *argv, VALUE mod)
{
    return specific_eval(argc, argv, mod, mod);
}

/*
 *  call-seq:
 *     mod.module_exec(arg...) {|var...| block }       -> obj
 *     mod.class_exec(arg...) {|var...| block }        -> obj
 *
 *  Evaluates the given block in the context of the class/module.
 *  The method defined in the block will belong to the receiver.
 *  Any arguments passed to the method will be passed to the block.
 *  This can be used if the block needs to access instance variables.
 *
 *     class Thing
 *     end
 *     Thing.class_exec{
 *       def hello() "Hello there!" end
 *     }
 *     puts Thing.new.hello()
 *
 *  <em>produces:</em>
 *
 *     Hello there!
 */

VALUE
rb_mod_module_exec(int argc, const VALUE *argv, VALUE mod)
{
    return yield_under(mod, mod, argc, argv);
}

/*
 *  Document-class: UncaughtThrowError
 *
 *  Raised when +throw+ is called with a _tag_ which does not have
 *  corresponding +catch+ block.
 *
 *     throw "foo", "bar"
 *
 *  <em>raises the exception:</em>
 *
 *     UncaughtThrowError: uncaught throw "foo"
 */

static VALUE
uncaught_throw_init(int argc, const VALUE *argv, VALUE exc)
{
    rb_check_arity(argc, 2, UNLIMITED_ARGUMENTS);
    rb_call_super(argc - 2, argv + 2);
    rb_ivar_set(exc, id_tag, argv[0]);
    rb_ivar_set(exc, id_value, argv[1]);
    return exc;
}

/*
 * call-seq:
 *   uncaught_throw.tag   -> obj
 *
 * Return the tag object which was called for.
 */

static VALUE
uncaught_throw_tag(VALUE exc)
{
    return rb_ivar_get(exc, id_tag);
}

/*
 * call-seq:
 *   uncaught_throw.value   -> obj
 *
 * Return the return value which was called for.
 */

static VALUE
uncaught_throw_value(VALUE exc)
{
    return rb_ivar_get(exc, id_value);
}

/*
 * call-seq:
 *   uncaught_throw.to_s   ->  string
 *
 * Returns formatted message with the inspected tag.
 */

static VALUE
uncaught_throw_to_s(VALUE exc)
{
    VALUE mesg = rb_attr_get(exc, id_mesg);
    VALUE tag = uncaught_throw_tag(exc);
    return rb_str_format(1, &tag, mesg);
}

/*
 *  call-seq:
 *     throw(tag [, obj])
 *
 *  Transfers control to the end of the active +catch+ block
 *  waiting for _tag_. Raises +UncaughtThrowError+ if there
 *  is no +catch+ block for the _tag_. The optional second
 *  parameter supplies a return value for the +catch+ block,
 *  which otherwise defaults to +nil+. For examples, see
 *  Kernel::catch.
 */

static VALUE
rb_f_throw(int argc, VALUE *argv)
{
    VALUE tag, value;

    rb_scan_args(argc, argv, "11", &tag, &value);
    rb_throw_obj(tag, value);
    UNREACHABLE_RETURN(Qnil);
}

void
rb_throw_obj(VALUE tag, VALUE value)
{
    rb_execution_context_t *ec = GET_EC();
    struct rb_vm_tag *tt = ec->tag;

    while (tt) {
	if (tt->tag == tag) {
	    tt->retval = value;
	    break;
	}
	tt = tt->prev;
    }
    if (!tt) {
	VALUE desc[3];
	desc[0] = tag;
	desc[1] = value;
	desc[2] = rb_str_new_cstr("uncaught throw %p");
	rb_exc_raise(rb_class_new_instance(numberof(desc), desc, rb_eUncaughtThrow));
    }

    ec->errinfo = (VALUE)THROW_DATA_NEW(tag, NULL, TAG_THROW);
    EC_JUMP_TAG(ec, TAG_THROW);
}

void
rb_throw(const char *tag, VALUE val)
{
    rb_throw_obj(rb_sym_intern_ascii_cstr(tag), val);
}

static VALUE
catch_i(VALUE tag, VALUE data)
{
    return rb_yield_0(1, &tag);
}

/*
 *  call-seq:
 *     catch([tag]) {|tag| block }  -> obj
 *
 *  +catch+ executes its block. If +throw+ is not called, the block executes
 *  normally, and +catch+ returns the value of the last expression evaluated.
 *
 *     catch(1) { 123 }            # => 123
 *
 *  If <code>throw(tag2, val)</code> is called, Ruby searches up its stack for
 *  a +catch+ block whose +tag+ has the same +object_id+ as _tag2_. When found,
 *  the block stops executing and returns _val_ (or +nil+ if no second argument
 *  was given to +throw+).
 *
 *     catch(1) { throw(1, 456) }  # => 456
 *     catch(1) { throw(1) }       # => nil
 *
 *  When +tag+ is passed as the first argument, +catch+ yields it as the
 *  parameter of the block.
 *
 *     catch(1) {|x| x + 2 }       # => 3
 *
 *  When no +tag+ is given, +catch+ yields a new unique object (as from
 *  +Object.new+) as the block parameter. This object can then be used as the
 *  argument to +throw+, and will match the correct +catch+ block.
 *
 *     catch do |obj_A|
 *       catch do |obj_B|
 *         throw(obj_B, 123)
 *         puts "This puts is not reached"
 *       end
 *
 *       puts "This puts is displayed"
 *       456
 *     end
 *
 *     # => 456
 *
 *     catch do |obj_A|
 *       catch do |obj_B|
 *         throw(obj_A, 123)
 *         puts "This puts is still not reached"
 *       end
 *
 *       puts "Now this puts is also not reached"
 *       456
 *     end
 *
 *     # => 123
 */

static VALUE
rb_f_catch(int argc, VALUE *argv, VALUE self)
{
    VALUE tag = rb_check_arity(argc, 0, 1) ? argv[0] : rb_obj_alloc(rb_cObject);
    return rb_catch_obj(tag, catch_i, 0);
}

VALUE
rb_catch(const char *tag, VALUE (*func)(), VALUE data)
{
    VALUE vtag = tag ? rb_sym_intern_ascii_cstr(tag) : rb_obj_alloc(rb_cObject);
    return rb_catch_obj(vtag, func, data);
}

static VALUE
vm_catch_protect(VALUE tag, rb_block_call_func *func, VALUE data,
		 enum ruby_tag_type *stateptr, rb_execution_context_t *volatile ec)
{
    enum ruby_tag_type state;
    VALUE val = Qnil;		/* OK */
    rb_control_frame_t *volatile saved_cfp = ec->cfp;

    EC_PUSH_TAG(ec);

    _tag.tag = tag;

    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	/* call with argc=1, argv = [tag], block = Qnil to insure compatibility */
	val = (*func)(tag, data, 1, (const VALUE *)&tag, Qnil);
    }
    else if (state == TAG_THROW && THROW_DATA_VAL((struct vm_throw_data *)ec->errinfo) == tag) {
	rb_vm_rewind_cfp(ec, saved_cfp);
	val = ec->tag->retval;
	ec->errinfo = Qnil;
	state = 0;
    }
    EC_POP_TAG();
    if (stateptr)
	*stateptr = state;

    return val;
}

VALUE
rb_catch_protect(VALUE t, rb_block_call_func *func, VALUE data, enum ruby_tag_type *stateptr)
{
    return vm_catch_protect(t, func, data, stateptr, GET_EC());
}

VALUE
rb_catch_obj(VALUE t, VALUE (*func)(), VALUE data)
{
    enum ruby_tag_type state;
    rb_execution_context_t *ec = GET_EC();
    VALUE val = vm_catch_protect(t, (rb_block_call_func *)func, data, &state, ec);
    if (state) EC_JUMP_TAG(ec, state);
    return val;
}

static void
local_var_list_init(struct local_var_list *vars)
{
    vars->tbl = rb_ident_hash_new();
    RBASIC_CLEAR_CLASS(vars->tbl);
}

static VALUE
local_var_list_finish(struct local_var_list *vars)
{
    /* TODO: not to depend on the order of st_table */
    VALUE ary = rb_hash_keys(vars->tbl);
    rb_hash_clear(vars->tbl);
    vars->tbl = 0;
    return ary;
}

static int
local_var_list_update(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    if (existing) return ST_STOP;
    *value = (st_data_t)Qtrue;	/* INT2FIX(arg) */
    return ST_CONTINUE;
}

static void
local_var_list_add(const struct local_var_list *vars, ID lid)
{
    if (lid && rb_is_local_id(lid)) {
        /* should skip temporary variable */
        st_data_t idx = 0;	/* tbl->num_entries */
        rb_hash_stlike_update(vars->tbl, ID2SYM(lid), local_var_list_update, idx);
    }
}

/*
 *  call-seq:
 *     local_variables    -> array
 *
 *  Returns the names of the current local variables.
 *
 *     fred = 1
 *     for i in 1..10
 *        # ...
 *     end
 *     local_variables   #=> [:fred, :i]
 */

static VALUE
rb_f_local_variables(void)
{
    struct local_var_list vars;
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(ec, RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp));
    unsigned int i;

    local_var_list_init(&vars);
    while (cfp) {
	if (cfp->iseq) {
	    for (i = 0; i < cfp->iseq->body->local_table_size; i++) {
		local_var_list_add(&vars, cfp->iseq->body->local_table[i]);
	    }
	}
	if (!VM_ENV_LOCAL_P(cfp->ep)) {
	    /* block */
	    const VALUE *ep = VM_CF_PREV_EP(cfp);

	    if (vm_collect_local_variables_in_heap(ep, &vars)) {
		break;
	    }
	    else {
		while (cfp->ep != ep) {
		    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
		}
	    }
	}
	else {
	    break;
	}
    }
    return local_var_list_finish(&vars);
}

/*
 *  call-seq:
 *     block_given?   -> true or false
 *     iterator?      -> true or false
 *
 *  Returns <code>true</code> if <code>yield</code> would execute a
 *  block in the current context. The <code>iterator?</code> form
 *  is mildly deprecated.
 *
 *     def try
 *       if block_given?
 *         yield
 *       else
 *         "no block"
 *       end
 *     end
 *     try                  #=> "no block"
 *     try { "hello" }      #=> "hello"
 *     try do "hello" end   #=> "hello"
 */


static VALUE
rb_f_block_given_p(void)
{
    rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    cfp = vm_get_ruby_level_caller_cfp(ec, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));

    if (cfp != NULL && VM_CF_BLOCK_HANDLER(cfp) != VM_BLOCK_HANDLER_NONE) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

VALUE
rb_current_realfilepath(void)
{
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = ec->cfp;
    cfp = vm_get_ruby_level_caller_cfp(ec, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));
    if (cfp != 0) return rb_iseq_realpath(cfp->iseq);
    return Qnil;
}

void
Init_vm_eval(void)
{
    rb_define_global_function("eval", rb_f_eval, -1);
    rb_define_global_function("local_variables", rb_f_local_variables, 0);
    rb_define_global_function("iterator?", rb_f_block_given_p, 0);
    rb_define_global_function("block_given?", rb_f_block_given_p, 0);

    rb_define_global_function("catch", rb_f_catch, -1);
    rb_define_global_function("throw", rb_f_throw, -1);

    rb_define_global_function("loop", rb_f_loop, 0);

    rb_define_method(rb_cBasicObject, "instance_eval", rb_obj_instance_eval, -1);
    rb_define_method(rb_cBasicObject, "instance_exec", rb_obj_instance_exec, -1);
    rb_define_private_method(rb_cBasicObject, "method_missing", rb_method_missing, -1);

#if 1
    rb_add_method(rb_cBasicObject, id__send__,
		  VM_METHOD_TYPE_OPTIMIZED, (void *)OPTIMIZED_METHOD_TYPE_SEND, METHOD_VISI_PUBLIC);
    rb_add_method(rb_mKernel, idSend,
		  VM_METHOD_TYPE_OPTIMIZED, (void *)OPTIMIZED_METHOD_TYPE_SEND, METHOD_VISI_PUBLIC);
#else
    rb_define_method(rb_cBasicObject, "__send__", rb_f_send, -1);
    rb_define_method(rb_mKernel, "send", rb_f_send, -1);
#endif
    rb_define_method(rb_mKernel, "public_send", rb_f_public_send, -1);

    rb_define_method(rb_cModule, "module_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "class_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "module_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "class_eval", rb_mod_module_eval, -1);

    rb_eUncaughtThrow = rb_define_class("UncaughtThrowError", rb_eArgError);
    rb_define_method(rb_eUncaughtThrow, "initialize", uncaught_throw_init, -1);
    rb_define_method(rb_eUncaughtThrow, "tag", uncaught_throw_tag, 0);
    rb_define_method(rb_eUncaughtThrow, "value", uncaught_throw_value, 0);
    rb_define_method(rb_eUncaughtThrow, "to_s", uncaught_throw_to_s, 0);

    id_result = rb_intern_const("result");
    id_tag = rb_intern_const("tag");
    id_value = rb_intern_const("value");
}

#endif /* #ifndef MJIT_HEADER */
