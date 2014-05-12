/**********************************************************************

  vm_eval.c -

  $Author$
  created at: Sat May 24 16:02:32 JST 2008

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

static inline VALUE method_missing(VALUE obj, ID id, int argc, const VALUE *argv, int call_status);
static inline VALUE vm_yield_with_cref(rb_thread_t *th, int argc, const VALUE *argv, const NODE *cref);
static inline VALUE vm_yield(rb_thread_t *th, int argc, const VALUE *argv);
static inline VALUE vm_yield_with_block(rb_thread_t *th, int argc, const VALUE *argv, const rb_block_t *blockargptr);
static NODE *vm_cref_push(rb_thread_t *th, VALUE klass, int noex, rb_block_t *blockptr);
static VALUE vm_exec(rb_thread_t *th);
static void vm_set_eval_stack(rb_thread_t * th, VALUE iseqval, const NODE *cref, rb_block_t *base_block);
static int vm_collect_local_variables_in_heap(rb_thread_t *th, VALUE *dfp, VALUE ary);

/* vm_backtrace.c */
VALUE rb_vm_backtrace_str_ary(rb_thread_t *th, int lev, int n);

typedef enum call_type {
    CALL_PUBLIC,
    CALL_FCALL,
    CALL_VCALL,
    CALL_TYPE_MAX
} call_type;

static VALUE send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope);

static VALUE vm_call0_body(rb_thread_t* th, rb_call_info_t *ci, const VALUE *argv);

static VALUE
vm_call0(rb_thread_t* th, VALUE recv, ID id, int argc, const VALUE *argv,
	 const rb_method_entry_t *me, VALUE defined_class)
{
    rb_call_info_t ci_entry, *ci = &ci_entry;

    ci->flag = 0;
    ci->mid = id;
    ci->recv = recv;
    ci->defined_class = defined_class;
    ci->argc = argc;
    ci->me = me;

    return vm_call0_body(th, ci, argv);
}

#if OPT_CALL_CFUNC_WITHOUT_FRAME
static VALUE
vm_call0_cfunc(rb_thread_t* th, rb_call_info_t *ci, const VALUE *argv)
{
    VALUE val;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, ci->defined_class, ci->mid);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, ci->recv, ci->mid, ci->defined_class, Qnil);
    {
	rb_control_frame_t *reg_cfp = th->cfp;
	const rb_method_entry_t *me = ci->me;
	const rb_method_cfunc_t *cfunc = &me->def->body.cfunc;
	int len = cfunc->argc;

	if (len >= 0) rb_check_arity(ci->argc, len, len);

	th->passed_ci = ci;
	ci->aux.inc_sp = 0;
	VM_PROFILE_UP(2);
	val = (*cfunc->invoker)(cfunc->func, ci, argv);

	if (reg_cfp == th->cfp) {
	    if (UNLIKELY(th->passed_ci != ci)) {
		rb_bug("vm_call0_cfunc: passed_ci error (ci: %p, passed_ci: %p)", ci, th->passed_ci);
	    }
	    th->passed_ci = 0;
	}
	else {
	    if (reg_cfp != th->cfp + 1) {
		rb_bug("vm_call0_cfunc: cfp consistency error");
	    }
	    VM_PROFILE_UP(3);
	    vm_pop_frame(th);
	}
    }
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, ci->recv, ci->mid, ci->defined_class, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, ci->defined_class, ci->mid);

    return val;
}
#else
static VALUE
vm_call0_cfunc_with_frame(rb_thread_t* th, rb_call_info_t *ci, const VALUE *argv)
{
    VALUE val;
    const rb_method_entry_t *me = ci->me;
    const rb_method_cfunc_t *cfunc = &me->def->body.cfunc;
    int len = cfunc->argc;
    VALUE recv = ci->recv;
    VALUE defined_class = ci->defined_class;
    int argc = ci->argc;
    ID mid = ci->mid;
    rb_block_t *blockptr = ci->blockptr;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, defined_class, mid);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, mid, defined_class, Qnil);
    {
	rb_control_frame_t *reg_cfp = th->cfp;

	vm_push_frame(th, 0, VM_FRAME_MAGIC_CFUNC, recv, defined_class,
		      VM_ENVVAL_BLOCK_PTR(blockptr), 0, reg_cfp->sp, 1, me, 0);

	if (len >= 0) rb_check_arity(argc, len, len);

	VM_PROFILE_UP(2);
	val = (*cfunc->invoker)(cfunc->func, recv, argc, argv);

	if (UNLIKELY(reg_cfp != th->cfp + 1)) {
		rb_bug("vm_call0_cfunc_with_frame: cfp consistency error");
	}
	VM_PROFILE_UP(3);
	vm_pop_frame(th);
    }
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, mid, defined_class, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, defined_class, mid);

    return val;
}

static VALUE
vm_call0_cfunc(rb_thread_t* th, rb_call_info_t *ci, const VALUE *argv)
{
    return vm_call0_cfunc_with_frame(th, ci, argv);
}
#endif

/* `ci' should point temporal value (on stack value) */
static VALUE
vm_call0_body(rb_thread_t* th, rb_call_info_t *ci, const VALUE *argv)
{
    VALUE ret;

    if (!ci->me->def) return Qnil;

    if (th->passed_block) {
	ci->blockptr = (rb_block_t *)th->passed_block;
	th->passed_block = 0;
    }
    else {
	ci->blockptr = 0;
    }

  again:
    switch (ci->me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
	{
	    rb_control_frame_t *reg_cfp = th->cfp;
	    int i;

	    CHECK_VM_STACK_OVERFLOW(reg_cfp, ci->argc + 1);

	    *reg_cfp->sp++ = ci->recv;
	    for (i = 0; i < ci->argc; i++) {
		*reg_cfp->sp++ = argv[i];
	    }

	    vm_call_iseq_setup(th, reg_cfp, ci);
	    th->cfp->flag |= VM_FRAME_FLAG_FINISH;
	    return vm_exec(th); /* CHECK_INTS in this function */
	}
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
	ret = vm_call0_cfunc(th, ci, argv);
	goto success;
      case VM_METHOD_TYPE_ATTRSET:
	rb_check_arity(ci->argc, 1, 1);
	ret = rb_ivar_set(ci->recv, ci->me->def->body.attr.id, argv[0]);
	goto success;
      case VM_METHOD_TYPE_IVAR:
	rb_check_arity(ci->argc, 0, 0);
	ret = rb_attr_get(ci->recv, ci->me->def->body.attr.id);
	goto success;
      case VM_METHOD_TYPE_BMETHOD:
	ret = vm_call_bmethod_body(th, ci, argv);
	goto success;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_REFINED:
	{
	    if (ci->me->def->type == VM_METHOD_TYPE_REFINED &&
		ci->me->def->body.orig_me) {
		ci->me = ci->me->def->body.orig_me;
		goto again;
	    }

	    ci->defined_class = RCLASS_SUPER(ci->defined_class);

	    if (!ci->defined_class || !(ci->me = rb_method_entry(ci->defined_class, ci->mid, &ci->defined_class))) {
		ret = method_missing(ci->recv, ci->mid, ci->argc, argv, NOEX_SUPER);
		goto success;
	    }
	    RUBY_VM_CHECK_INTS(th);
	    if (!ci->me->def) return Qnil;
	    goto again;
	}
      case VM_METHOD_TYPE_MISSING:
	{
	    VALUE new_args = rb_ary_new4(ci->argc, argv);

	    RB_GC_GUARD(new_args);
	    rb_ary_unshift(new_args, ID2SYM(ci->mid));
	    th->passed_block = ci->blockptr;
	    return rb_funcall2(ci->recv, idMethodMissing, ci->argc+1, RARRAY_PTR(new_args));
	}
      case VM_METHOD_TYPE_OPTIMIZED:
	switch (ci->me->def->body.optimize_type) {
	  case OPTIMIZED_METHOD_TYPE_SEND:
	    ret = send_internal(ci->argc, argv, ci->recv, CALL_FCALL);
	    goto success;
	  case OPTIMIZED_METHOD_TYPE_CALL:
	    {
		rb_proc_t *proc;
		GetProcPtr(ci->recv, proc);
		ret = rb_vm_invoke_proc(th, proc, ci->argc, argv, ci->blockptr);
		goto success;
	    }
	  default:
	    rb_bug("vm_call0: unsupported optimized method type (%d)", ci->me->def->body.optimize_type);
	}
	break;
      case VM_METHOD_TYPE_UNDEF:
	break;
    }
    rb_bug("vm_call0: unsupported method type (%d)", ci->me->def->type);
    return Qundef;

  success:
    RUBY_VM_CHECK_INTS(th);
    return ret;
}

VALUE
rb_vm_call(rb_thread_t *th, VALUE recv, VALUE id, int argc, const VALUE *argv,
	   const rb_method_entry_t *me, VALUE defined_class)
{
    return vm_call0(th, recv, id, argc, argv, me, defined_class);
}

static inline VALUE
vm_call_super(rb_thread_t *th, int argc, const VALUE *argv)
{
    VALUE recv = th->cfp->self;
    VALUE klass;
    ID id;
    rb_method_entry_t *me;
    rb_control_frame_t *cfp = th->cfp;

    if (cfp->iseq || NIL_P(cfp->klass)) {
	rb_bug("vm_call_super: should not be reached");
    }

    klass = RCLASS_SUPER(cfp->klass);
    id = cfp->me->def->original_id;
    me = rb_method_entry(klass, id, &klass);
    if (!me) {
	return method_missing(recv, id, argc, argv, NOEX_SUPER);
    }

    return vm_call0(th, recv, id, argc, argv, me, klass);
}

VALUE
rb_call_super(int argc, const VALUE *argv)
{
    PASS_PASSED_BLOCK();
    return vm_call_super(GET_THREAD(), argc, argv);
}

static inline void
stack_check(void)
{
    rb_thread_t *th = GET_THREAD();

    if (!rb_thread_raised_p(th, RAISED_STACKOVERFLOW) && ruby_stack_check()) {
	rb_thread_raised_set(th, RAISED_STACKOVERFLOW);
	rb_exc_raise(sysstack_error);
    }
}

static inline rb_method_entry_t *
    rb_search_method_entry(VALUE recv, ID mid, VALUE *defined_class_ptr);
static inline int rb_method_call_status(rb_thread_t *th, const rb_method_entry_t *me, call_type scope, VALUE self);
#define NOEX_OK NOEX_NOSUPER

/*!
 * \internal
 * calls the specified method.
 *
 * This function is called by functions in rb_call* family.
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
rb_call0(VALUE recv, ID mid, int argc, const VALUE *argv,
	 call_type scope, VALUE self)
{
    VALUE defined_class;
    rb_method_entry_t *me =
	rb_search_method_entry(recv, mid, &defined_class);
    rb_thread_t *th = GET_THREAD();
    int call_status = rb_method_call_status(th, me, scope, self);

    if (call_status != NOEX_OK) {
	return method_missing(recv, mid, argc, argv, call_status);
    }
    stack_check();
    return vm_call0(th, recv, mid, argc, argv, me, defined_class);
}

struct rescue_funcall_args {
    VALUE recv;
    VALUE sym;
    int argc;
    const VALUE *argv;
};

static VALUE
check_funcall_exec(struct rescue_funcall_args *args)
{
    VALUE new_args = rb_ary_new4(args->argc, args->argv);

    RB_GC_GUARD(new_args);
    rb_ary_unshift(new_args, args->sym);
    return rb_funcall2(args->recv, idMethodMissing,
		       args->argc+1, RARRAY_PTR(new_args));
}

static VALUE
check_funcall_failed(struct rescue_funcall_args *args, VALUE e)
{
    if (rb_respond_to(args->recv, SYM2ID(args->sym))) {
	rb_exc_raise(e);
    }
    return Qundef;
}

static int
check_funcall_respond_to(rb_thread_t *th, VALUE klass, VALUE recv, ID mid)
{
    VALUE defined_class;
    const rb_method_entry_t *me = rb_method_entry(klass, idRespond_to, &defined_class);

    if (me && !(me->flag & NOEX_BASIC)) {
	const rb_block_t *passed_block = th->passed_block;
	VALUE args[2], result;
	int arity = rb_method_entry_arity(me);

	if (arity > 2)
	    rb_raise(rb_eArgError, "respond_to? must accept 1 or 2 arguments (requires %d)", arity);

	if (arity < 1) arity = 2;

	args[0] = ID2SYM(mid);
	args[1] = Qtrue;
	result = vm_call0(th, recv, idRespond_to, arity, args, me, defined_class);
	th->passed_block = passed_block;
	if (!RTEST(result)) {
	    return FALSE;
	}
    }
    return TRUE;
}

static int
check_funcall_callable(rb_thread_t *th, const rb_method_entry_t *me)
{
    return rb_method_call_status(th, me, CALL_FCALL, th->cfp->self) == NOEX_OK;
}

static VALUE
check_funcall_missing(rb_thread_t *th, VALUE klass, VALUE recv, ID mid, int argc, const VALUE *argv)
{
    if (rb_method_basic_definition_p(klass, idMethodMissing)) {
	return Qundef;
    }
    else {
	struct rescue_funcall_args args;

	th->method_missing_reason = 0;
	args.recv = recv;
	args.sym = ID2SYM(mid);
	args.argc = argc;
	args.argv = argv;
	return rb_rescue2(check_funcall_exec, (VALUE)&args,
			  check_funcall_failed, (VALUE)&args,
			  rb_eNoMethodError, (VALUE)0);
    }
}

VALUE
rb_check_funcall(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    VALUE klass = CLASS_OF(recv);
    const rb_method_entry_t *me;
    rb_thread_t *th = GET_THREAD();
    VALUE defined_class;

    if (!check_funcall_respond_to(th, klass, recv, mid))
	return Qundef;

    me = rb_search_method_entry(recv, mid, &defined_class);
    if (check_funcall_callable(th, me) != NOEX_OK) {
	return check_funcall_missing(th, klass, recv, mid, argc, argv);
    }
    stack_check();
    return vm_call0(th, recv, mid, argc, argv, me, defined_class);
}

VALUE
rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, const VALUE *argv,
			   rb_check_funcall_hook *hook, VALUE arg)
{
    VALUE klass = CLASS_OF(recv);
    const rb_method_entry_t *me;
    rb_thread_t *th = GET_THREAD();
    VALUE defined_class;

    if (!check_funcall_respond_to(th, klass, recv, mid))
	return Qundef;

    me = rb_search_method_entry(recv, mid, &defined_class);
    if (check_funcall_callable(th, me) != NOEX_OK) {
	(*hook)(FALSE, recv, mid, argc, argv, arg);
	return check_funcall_missing(th, klass, recv, mid, argc, argv);
    }
    stack_check();
    (*hook)(TRUE, recv, mid, argc, argv, arg);
    return vm_call0(th, recv, mid, argc, argv, me, defined_class);
}

static const char *
rb_type_str(enum ruby_value_type type)
{
#define type_case(t) case t: return #t;
    switch (type) {
      type_case(T_NONE)
      type_case(T_OBJECT)
      type_case(T_CLASS)
      type_case(T_MODULE)
      type_case(T_FLOAT)
      type_case(T_STRING)
      type_case(T_REGEXP)
      type_case(T_ARRAY)
      type_case(T_HASH)
      type_case(T_STRUCT)
      type_case(T_BIGNUM)
      type_case(T_FILE)
      type_case(T_DATA)
      type_case(T_MATCH)
      type_case(T_COMPLEX)
      type_case(T_RATIONAL)
      type_case(T_NIL)
      type_case(T_TRUE)
      type_case(T_FALSE)
      type_case(T_SYMBOL)
      type_case(T_FIXNUM)
      type_case(T_UNDEF)
      type_case(T_NODE)
      type_case(T_ICLASS)
      type_case(T_ZOMBIE)
      default: return NULL;
    }
#undef type_case
}

static inline rb_method_entry_t *
rb_search_method_entry(VALUE recv, ID mid, VALUE *defined_class_ptr)
{
    VALUE klass = CLASS_OF(recv);

    if (!klass) {
        VALUE flags, klass;
        if (IMMEDIATE_P(recv)) {
            rb_raise(rb_eNotImpError,
                     "method `%s' called on unexpected immediate object (%p)",
                     rb_id2name(mid), (void *)recv);
        }
        flags = RBASIC(recv)->flags;
        klass = RBASIC(recv)->klass;
        if (flags == 0) {
            rb_raise(rb_eNotImpError,
                     "method `%s' called on terminated object"
                     " (%p flags=0x%"PRIxVALUE" klass=0x%"PRIxVALUE")",
                     rb_id2name(mid), (void *)recv, flags, klass);
        }
        else {
            int type = BUILTIN_TYPE(recv);
            const char *typestr = rb_type_str(type);
            if (typestr && T_OBJECT <= type && type < T_NIL)
                rb_raise(rb_eNotImpError,
                         "method `%s' called on hidden %s object"
                         " (%p flags=0x%"PRIxVALUE" klass=0x%"PRIxVALUE")",
                         rb_id2name(mid), typestr, (void *)recv, flags, klass);
            if (typestr)
                rb_raise(rb_eNotImpError,
                         "method `%s' called on unexpected %s object"
                         " (%p flags=0x%"PRIxVALUE" klass=0x%"PRIxVALUE")",
                         rb_id2name(mid), typestr, (void *)recv, flags, klass);
            else
                rb_raise(rb_eNotImpError,
                         "method `%s' called on broken T_???" "(0x%02x) object"
                         " (%p flags=0x%"PRIxVALUE" klass=0x%"PRIxVALUE")",
                         rb_id2name(mid), type, (void *)recv, flags, klass);
        }
    }
    return rb_method_entry(klass, mid, defined_class_ptr);
}

static inline int
rb_method_call_status(rb_thread_t *th, const rb_method_entry_t *me, call_type scope, VALUE self)
{
    VALUE klass;
    ID oid;
    int noex;

    if (UNDEFINED_METHOD_ENTRY_P(me)) {
	return scope == CALL_VCALL ? NOEX_VCALL : 0;
    }
    klass = me->klass;
    oid = me->def->original_id;
    noex = me->flag;

    if (oid != idMethodMissing) {
	/* receiver specified form for private method */
	if (UNLIKELY(noex)) {
	    if (((noex & NOEX_MASK) & NOEX_PRIVATE) && scope == CALL_PUBLIC) {
		return NOEX_PRIVATE;
	    }

	    /* self must be kind of a specified form for protected method */
	    if (((noex & NOEX_MASK) & NOEX_PROTECTED) && scope == CALL_PUBLIC) {
		VALUE defined_class = klass;

		if (RB_TYPE_P(defined_class, T_ICLASS)) {
		    defined_class = RBASIC(defined_class)->klass;
		}

		if (self == Qundef || !rb_obj_is_kind_of(self, defined_class)) {
		    return NOEX_PROTECTED;
		}
	    }

	    if (NOEX_SAFE(noex) > th->safe_level) {
		rb_raise(rb_eSecurityError, "calling insecure method: %s",
			 rb_id2name(me->called_id));
	    }
	}
    }
    return NOEX_OK;
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
    rb_thread_t *th = GET_THREAD();
    return rb_call0(recv, mid, argc, argv, scope, th->cfp->self);
}

NORETURN(static void raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv,
					  VALUE obj, int call_status));

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
    rb_thread_t *th = GET_THREAD();
    raise_method_missing(th, argc, argv, obj, th->method_missing_reason);
    UNREACHABLE;
}

#define NOEX_MISSING   0x80

static VALUE
make_no_method_exception(VALUE exc, const char *format, VALUE obj, int argc, const VALUE *argv)
{
    int n = 0;
    VALUE mesg;
    VALUE args[3];

    if (!format) {
	format = "undefined method `%s' for %s";
    }
    mesg = rb_const_get(exc, rb_intern("message"));
    if (rb_method_basic_definition_p(CLASS_OF(mesg), '!')) {
	args[n++] = rb_name_err_mesg_new(mesg, rb_str_new2(format), obj, argv[0]);
    }
    else {
	args[n++] = rb_funcall(mesg, '!', 3, rb_str_new2(format), obj, argv[0]);
    }
    args[n++] = argv[0];
    if (exc == rb_eNoMethodError) {
	args[n++] = rb_ary_new4(argc - 1, argv + 1);
    }
    return rb_class_new_instance(n, args, exc);
}

static void
raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv, VALUE obj,
		     int last_call_status)
{
    VALUE exc = rb_eNoMethodError;
    const char *format = 0;

    if (argc == 0 || !SYMBOL_P(argv[0])) {
	rb_raise(rb_eArgError, "no id given");
    }

    stack_check();

    if (last_call_status & NOEX_PRIVATE) {
	format = "private method `%s' called for %s";
    }
    else if (last_call_status & NOEX_PROTECTED) {
	format = "protected method `%s' called for %s";
    }
    else if (last_call_status & NOEX_VCALL) {
	format = "undefined local variable or method `%s' for %s";
	exc = rb_eNameError;
    }
    else if (last_call_status & NOEX_SUPER) {
	format = "super: no superclass method `%s' for %s";
    }

    {
	exc = make_no_method_exception(exc, format, obj, argc, argv);
	if (!(last_call_status & NOEX_MISSING)) {
	    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
	}
	rb_exc_raise(exc);
    }
}

static inline VALUE
method_missing(VALUE obj, ID id, int argc, const VALUE *argv, int call_status)
{
    VALUE *nargv, result, argv_ary = 0;
    rb_thread_t *th = GET_THREAD();
    const rb_block_t *blockptr = th->passed_block;

    th->method_missing_reason = call_status;
    th->passed_block = 0;

    if (id == idMethodMissing) {
	raise_method_missing(th, argc, argv, obj, call_status | NOEX_MISSING);
    }

    if (argc < 0x100) {
	nargv = ALLOCA_N(VALUE, argc + 1);
    }
    else {
	argv_ary = rb_ary_tmp_new(argc + 1);
	nargv = RARRAY_PTR(argv_ary);
    }
    nargv[0] = ID2SYM(id);
    MEMCPY(nargv + 1, argv, VALUE, argc);
    if (argv_ary) rb_ary_set_len(argv_ary, argc + 1);

    if (rb_method_basic_definition_p(CLASS_OF(obj) , idMethodMissing)) {
	raise_method_missing(th, argc+1, nargv, obj, call_status | NOEX_MISSING);
    }
    th->passed_block = blockptr;
    result = rb_funcall2(obj, idMethodMissing, argc + 1, nargv);
    if (argv_ary) rb_ary_clear(argv_ary);
    return result;
}

void
rb_raise_method_missing(rb_thread_t *th, int argc, VALUE *argv,
			VALUE obj, int call_status)
{
    th->passed_block = 0;
    raise_method_missing(th, argc, argv, obj, call_status | NOEX_MISSING);
}

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
	ret = rb_call(recv, mid, argc, RARRAY_PTR(args), CALL_FCALL);
	RB_GC_GUARD(args);
	return ret;
    }
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY_CONST_PTR(args), VALUE, argc);
    return rb_call(recv, mid, argc, argv, CALL_FCALL);
}

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
 * Same as rb_funcall2 but this function can call only public methods.
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
    PASS_PASSED_BLOCK_TH(GET_THREAD());

    return rb_call(recv, mid, argc, argv, CALL_PUBLIC);
}

VALUE
rb_funcall_with_block(VALUE recv, ID mid, int argc, const VALUE *argv, VALUE pass_procval)
{
    if (!NIL_P(pass_procval)) {
	rb_thread_t *th = GET_THREAD();
	rb_block_t *block = 0;

	rb_proc_t *pass_proc;
	GetProcPtr(pass_procval, pass_proc);
	block = &pass_proc->block;

	th->passed_block = block;
    }

    return rb_call(recv, mid, argc, argv, CALL_PUBLIC);
}

static VALUE
send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope)
{
    ID id;
    VALUE vid;
    VALUE self;
    rb_thread_t *th = GET_THREAD();

    if (scope == CALL_PUBLIC) {
	self = Qundef;
    }
    else {
	self = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp)->self;
    }

    if (argc == 0) {
	rb_raise(rb_eArgError, "no method name given");
    }

    vid = *argv++; argc--;

    id = rb_check_id(&vid);
    if (!id) {
	if (rb_method_basic_definition_p(CLASS_OF(recv), idMethodMissing)) {
	    VALUE exc = make_no_method_exception(rb_eNoMethodError, NULL,
						 recv, ++argc, --argv);
	    rb_exc_raise(exc);
	}
	id = rb_to_id(vid);
    }
    PASS_PASSED_BLOCK_TH(th);
    return rb_call0(recv, id, argc, argv, scope, self);
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

VALUE
rb_f_public_send(int argc, VALUE *argv, VALUE recv)
{
    return send_internal(argc, argv, recv, CALL_PUBLIC);
}

/* yield */

static inline VALUE
rb_yield_0(int argc, const VALUE * argv)
{
    return vm_yield(GET_THREAD(), argc, argv);
}

VALUE
rb_yield(VALUE val)
{
    if (val == Qundef) {
	return rb_yield_0(0, 0);
    }
    else {
	return rb_yield_0(1, &val);
    }
}

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
    volatile VALUE v;
    if (NIL_P(tmp)) {
        rb_raise(rb_eArgError, "not an array");
    }
    v = rb_yield_0(RARRAY_LENINT(tmp), RARRAY_CONST_PTR(tmp));
    return v;
}

VALUE
rb_yield_block(VALUE val, VALUE arg, int argc, const VALUE *argv, VALUE blockarg)
{
    const rb_block_t *blockptr = 0;
    if (!NIL_P(blockarg)) {
	rb_proc_t *blockproc;
	GetProcPtr(blockarg, blockproc);
	blockptr = &blockproc->block;
    }
    return vm_yield_with_block(GET_THREAD(), argc, argv, blockptr);
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
rb_f_loop_size(VALUE self, VALUE args, VALUE eobj)
{
    return DBL2NUM(INFINITY);
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
 *  StopIteration raised in the block breaks the loop.
 */

static VALUE
rb_f_loop(VALUE self)
{
    RETURN_SIZED_ENUMERATOR(self, 0, 0, rb_f_loop_size);
    rb_rescue2(loop_i, (VALUE)0, 0, 0, rb_eStopIteration, (VALUE)0);
    return Qnil;		/* dummy */
}

#if VMDEBUG
static const char *
vm_frametype_name(const rb_control_frame_t *cfp);
#endif

VALUE
rb_iterate(VALUE (* it_proc) (VALUE), VALUE data1,
	   VALUE (* bl_proc) (ANYARGS), VALUE data2)
{
    int state;
    volatile VALUE retval = Qnil;
    NODE *node = NEW_IFUNC(bl_proc, data2);
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *volatile cfp = th->cfp;

    node->nd_aid = rb_frame_this_func();
    TH_PUSH_TAG(th);
    state = TH_EXEC_TAG();
    if (state == 0) {
      iter_retry:
	{
	    rb_block_t *blockptr;
	    if (bl_proc) {
		blockptr = RUBY_VM_GET_BLOCK_PTR_IN_CFP(th->cfp);
		blockptr->iseq = (void *)node;
		blockptr->proc = 0;
	    }
	    else {
		blockptr = VM_CF_BLOCK_PTR(th->cfp);
	    }
	    th->passed_block = blockptr;
	}
	retval = (*it_proc) (data1);
    }
    else {
	VALUE err = th->errinfo;
	if (state == TAG_BREAK) {
	    VALUE *escape_ep = GET_THROWOBJ_CATCH_POINT(err);
	    VALUE *cep = cfp->ep;

	    if (cep == escape_ep) {
		state = 0;
		th->state = 0;
		th->errinfo = Qnil;
		retval = GET_THROWOBJ_VAL(err);

		/* check skipped frame */
		while (th->cfp != cfp) {
#if VMDEBUG
		    printf("skipped frame: %s\n", vm_frametype_name(th->cfp));
#endif
		    if (UNLIKELY(VM_FRAME_TYPE(th->cfp) == VM_FRAME_MAGIC_CFUNC)) {
			const rb_method_entry_t *me = th->cfp->me;
			EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, th->cfp->self, me->called_id, me->klass, Qnil);
			RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, me->klass, me->called_id);
		    }

		    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
		}
	    }
	    else{
		/* SDR(); printf("%p, %p\n", cdfp, escape_dfp); */
	    }
	}
	else if (state == TAG_RETRY) {
	    VALUE *escape_ep = GET_THROWOBJ_CATCH_POINT(err);
	    VALUE *cep = cfp->ep;

	    if (cep == escape_ep) {
		state = 0;
		th->state = 0;
		th->errinfo = Qnil;
		th->cfp = cfp;
		goto iter_retry;
	    }
	}
    }
    TH_POP_TAG();

    switch (state) {
      case 0:
	break;
      default:
	TH_JUMP_TAG(th, state);
    }
    return retval;
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

static VALUE
eval_string_with_cref(VALUE self, VALUE src, VALUE scope, NODE *const cref_arg, volatile VALUE file, volatile int line)
{
    int state;
    VALUE result = Qundef;
    VALUE envval;
    rb_thread_t *th = GET_THREAD();
    rb_env_t *env = NULL;
    rb_block_t block, *base_block;
    volatile int parse_in_eval;
    volatile int mild_compile_error;
    NODE *orig_cref;
    VALUE crefval;

    if (file == 0) {
	file = rb_sourcefilename();
	line = rb_sourceline();
    }

    parse_in_eval = th->parse_in_eval;
    mild_compile_error = th->mild_compile_error;
    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	NODE *cref = cref_arg;
	rb_binding_t *bind = 0;
	rb_iseq_t *iseq;
	volatile VALUE iseqval;
	VALUE absolute_path = Qnil;
	VALUE fname;

	if (file != Qundef) {
	    absolute_path = file;
	}

	if (scope != Qnil) {
	    bind = Check_TypedStruct(scope, &ruby_binding_data_type);
	    {
		envval = bind->env;
		if (NIL_P(absolute_path) && !NIL_P(bind->path)) {
		    file = bind->path;
		    line = bind->first_lineno;
		    absolute_path = rb_current_realfilepath();
		}
	    }
	    GetEnvPtr(envval, env);
	    base_block = &env->block;
	}
	else {
	    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

	    if (cfp != 0) {
		block = *RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp);
		base_block = &block;
		base_block->self = self;
		base_block->iseq = cfp->iseq;	/* TODO */
	    }
	    else {
		rb_raise(rb_eRuntimeError, "Can't eval on top of Fiber or Thread");
	    }
	}

	if ((fname = file) == Qundef) {
	    fname = rb_usascii_str_new_cstr("(eval)");
	}

	if (RTEST(fname))
	    fname = rb_fstring(fname);
	if (RTEST(absolute_path))
	    absolute_path = rb_fstring(absolute_path);

	/* make eval iseq */
	th->parse_in_eval++;
	th->mild_compile_error++;
	iseqval = rb_iseq_compile_with_option(src, fname, absolute_path, INT2FIX(line), base_block, Qnil);
	th->mild_compile_error--;
	th->parse_in_eval--;

	if (!cref && base_block->iseq) {
	    orig_cref = rb_vm_get_cref(base_block->iseq, base_block->ep);
	    cref = NEW_CREF(Qnil);
	    crefval = (VALUE) cref;
	    COPY_CREF(cref, orig_cref);
	}
	vm_set_eval_stack(th, iseqval, cref, base_block);
	RB_GC_GUARD(crefval);

	if (0) {		/* for debug */
	    VALUE disasm = rb_iseq_disasm(iseqval);
	    printf("%s\n", StringValuePtr(disasm));
	}

	/* save new env */
	GetISeqPtr(iseqval, iseq);
	if (bind && iseq->local_table_size > 0) {
	    bind->env = rb_vm_make_env_object(th, th->cfp);
	}

	/* kick */
	result = vm_exec(th);
    }
    TH_POP_TAG();
    th->mild_compile_error = mild_compile_error;
    th->parse_in_eval = parse_in_eval;

    if (state) {
	if (state == TAG_RAISE) {
	    VALUE errinfo = th->errinfo;
	    if (file == Qundef) {
		VALUE mesg, errat, bt2;
		ID id_mesg;

		CONST_ID(id_mesg, "mesg");
		errat = rb_get_backtrace(errinfo);
		mesg = rb_attr_get(errinfo, id_mesg);
		if (!NIL_P(errat) && RB_TYPE_P(errat, T_ARRAY) &&
		    (bt2 = rb_vm_backtrace_str_ary(th, 0, 0), RARRAY_LEN(bt2) > 0)) {
		    if (!NIL_P(mesg) && RB_TYPE_P(mesg, T_STRING) && !RSTRING_LEN(mesg)) {
			if (OBJ_FROZEN(mesg)) {
			    VALUE m = rb_str_cat(rb_str_dup(RARRAY_AREF(errat, 0)), ": ", 2);
			    rb_ivar_set(errinfo, id_mesg, rb_str_append(m, mesg));
			}
			else {
			    rb_str_update(mesg, 0, 0, rb_str_new2(": "));
			    rb_str_update(mesg, 0, 0, RARRAY_AREF(errat, 0));
			}
		    }
		    RARRAY_ASET(errat, 0, RARRAY_AREF(bt2, 0));
		}
	    }
	    rb_exc_raise(errinfo);
	}
	JUMP_TAG(state);
    }
    return result;
}

static VALUE
eval_string(VALUE self, VALUE src, VALUE scope, VALUE file, int line)
{
    return eval_string_with_cref(self, src, scope, 0, file, line);
}

/*
 *  call-seq:
 *     eval(string [, binding [, filename [,lineno]]])  -> obj
 *
 *  Evaluates the Ruby expression(s) in <em>string</em>. If
 *  <em>binding</em> is given, which must be a <code>Binding</code>
 *  object, the evaluation is performed in its context. If the
 *  optional <em>filename</em> and <em>lineno</em> parameters are
 *  present, they will be used when reporting syntax errors.
 *
 *     def get_binding(str)
 *       return binding
 *     end
 *     str = "hello"
 *     eval "str + ' Fred'"                      #=> "hello Fred"
 *     eval "str + ' Fred'", get_binding("bye")  #=> "bye Fred"
 */

VALUE
rb_f_eval(int argc, VALUE *argv, VALUE self)
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
    return eval_string(self, src, scope, file, line);
}

/** @note This function name is not stable. */
VALUE
ruby_eval_string_from_file(const char *str, const char *filename)
{
    VALUE file = filename ? rb_str_new_cstr(filename) : 0;
    return eval_string(rb_vm_top_self(), rb_str_new2(str), Qnil, file, 1);
}

struct eval_string_from_file_arg {
    VALUE str;
    VALUE filename;
};

static VALUE
eval_string_from_file_helper(VALUE data)
{
    const struct eval_string_from_file_arg *const arg = (struct eval_string_from_file_arg*)data;
    return eval_string(rb_vm_top_self(), arg->str, Qnil, arg->filename, 1);
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
rb_eval_string_protect(const char *str, int *state)
{
    return rb_protect((VALUE (*)(VALUE))rb_eval_string, (VALUE)str, state);
}

/**
 * Evaluates the given string under a module binding in an isolated binding.
 * This is same as the binding for required libraries on "require('foo', true)".
 *
 * __FILE__ will be "(eval)", and __LINE__ starts from 1 in the evaluation.
 *
 * @sa rb_eval_string
 * @param str Ruby code to evaluate.
 * @param state Being set to zero if succeeded. Nonzero if an error occurred.
 * @return The evaluated result if succeeded, an undefined value if otherwise.
 */
VALUE
rb_eval_string_wrap(const char *str, int *state)
{
    int status;
    rb_thread_t *th = GET_THREAD();
    VALUE self = th->top_self;
    VALUE wrapper = th->top_wrapper;
    VALUE val;

    th->top_wrapper = rb_module_new();
    th->top_self = rb_obj_clone(rb_vm_top_self());
    rb_extend_object(th->top_self, th->top_wrapper);

    val = rb_eval_string_protect(str, &status);

    th->top_self = self;
    th->top_wrapper = wrapper;

    if (state) {
	*state = status;
    }
    else if (status) {
	JUMP_TAG(status);
    }
    return val;
}

VALUE
rb_eval_cmd(VALUE cmd, VALUE arg, int level)
{
    int state;
    volatile VALUE val = Qnil;		/* OK */
    volatile int safe = rb_safe_level();

    if (OBJ_TAINTED(cmd)) {
	level = 4;
    }

    if (!RB_TYPE_P(cmd, T_STRING)) {
	PUSH_TAG();
	rb_set_safe_level_force(level);
	if ((state = EXEC_TAG()) == 0) {
	    val = rb_funcall2(cmd, rb_intern("call"), RARRAY_LENINT(arg),
			      RARRAY_PTR(arg));
	}
	POP_TAG();

	rb_set_safe_level_force(safe);

	if (state)
	    JUMP_TAG(state);
	return val;
    }

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	val = eval_string(rb_vm_top_self(), cmd, Qnil, 0, 0);
    }
    POP_TAG();

    rb_set_safe_level_force(safe);
    if (state) JUMP_TAG(state);
    return val;
}

/* block eval under the class/module context */

static VALUE
yield_under(VALUE under, VALUE self, VALUE values)
{
    rb_thread_t *th = GET_THREAD();
    rb_block_t block, *blockptr;
    NODE *cref;

    if ((blockptr = VM_CF_BLOCK_PTR(th->cfp)) != 0) {
	block = *blockptr;
	block.self = self;
	VM_CF_LEP(th->cfp)[0] = VM_ENVVAL_BLOCK_PTR(&block);
    }
    cref = vm_cref_push(th, under, NOEX_PUBLIC, blockptr);
    cref->flags |= NODE_FL_CREF_PUSHED_BY_EVAL;

    if (values == Qundef) {
	return vm_yield_with_cref(th, 1, &self, cref);
    }
    else {
	return vm_yield_with_cref(th, RARRAY_LENINT(values), RARRAY_CONST_PTR(values), cref);
    }
}

VALUE
rb_yield_refine_block(VALUE refinement, VALUE refinements)
{
    rb_thread_t *th = GET_THREAD();
    rb_block_t block, *blockptr;
    NODE *cref;

    if ((blockptr = VM_CF_BLOCK_PTR(th->cfp)) != 0) {
	block = *blockptr;
	block.self = refinement;
	VM_CF_LEP(th->cfp)[0] = VM_ENVVAL_BLOCK_PTR(&block);
    }
    cref = vm_cref_push(th, refinement, NOEX_PUBLIC, blockptr);
    cref->flags |= NODE_FL_CREF_PUSHED_BY_EVAL;
    RB_OBJ_WRITE(cref, &cref->nd_refinements, refinements);

    return vm_yield_with_cref(th, 0, NULL, cref);
}

/* string eval under the class/module context */
static VALUE
eval_under(VALUE under, VALUE self, VALUE src, VALUE file, int line)
{
    NODE *cref = vm_cref_push(GET_THREAD(), under, NOEX_PUBLIC, NULL);

    if (SPECIAL_CONST_P(self) && !NIL_P(under)) {
	cref->flags |= NODE_FL_CREF_PUSHED_BY_EVAL;
    }
    SafeStringValue(src);

    return eval_string_with_cref(self, src, Qnil, cref, file, line);
}

static VALUE
specific_eval(int argc, VALUE *argv, VALUE klass, VALUE self)
{
    if (rb_block_given_p()) {
	rb_check_arity(argc, 0, 0);
	return yield_under(klass, self, Qundef);
    }
    else {
	VALUE file = Qundef;
	int line = 1;

	rb_check_arity(argc, 1, 3);
	SafeStringValue(argv[0]);
	if (argc > 2)
	    line = NUM2INT(argv[2]);
	if (argc > 1) {
	    file = argv[1];
	    if (!NIL_P(file)) StringValue(file);
	}
	return eval_under(klass, self, argv[0], file, line);
    }
}

/*
 *  call-seq:
 *     obj.instance_eval(string [, filename [, lineno]] )   -> obj
 *     obj.instance_eval {| | block }                       -> obj
 *
 *  Evaluates a string containing Ruby source code, or the given block,
 *  within the context of the receiver (_obj_). In order to set the
 *  context, the variable +self+ is set to _obj_ while
 *  the code is executing, giving the code access to _obj_'s
 *  instance variables. In the version of <code>instance_eval</code>
 *  that takes a +String+, the optional second and third
 *  parameters supply a filename and starting line number that are used
 *  when reporting compilation errors.
 *
 *     class KlassWithSecret
 *       def initialize
 *         @secret = 99
 *       end
 *     end
 *     k = KlassWithSecret.new
 *     k.instance_eval { @secret }   #=> 99
 */

VALUE
rb_obj_instance_eval(int argc, VALUE *argv, VALUE self)
{
    VALUE klass;

    if (SPECIAL_CONST_P(self)) {
	klass = rb_special_singleton_class(self);
    }
    else {
	klass = rb_singleton_class(self);
    }
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
rb_obj_instance_exec(int argc, VALUE *argv, VALUE self)
{
    VALUE klass;

    if (SPECIAL_CONST_P(self)) {
	klass = rb_special_singleton_class(self);
    }
    else {
	klass = rb_singleton_class(self);
    }
    return yield_under(klass, self, rb_ary_new4(argc, argv));
}

/*
 *  call-seq:
 *     mod.class_eval(string [, filename [, lineno]])  -> obj
 *     mod.module_eval {|| block }                     -> obj
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
rb_mod_module_eval(int argc, VALUE *argv, VALUE mod)
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
rb_mod_module_exec(int argc, VALUE *argv, VALUE mod)
{
    return yield_under(mod, mod, rb_ary_new4(argc, argv));
}

/*
 *  call-seq:
 *     throw(tag [, obj])
 *
 *  Transfers control to the end of the active +catch+ block
 *  waiting for _tag_. Raises +ArgumentError+ if there
 *  is no +catch+ block for the _tag_. The optional second
 *  parameter supplies a return value for the +catch+ block,
 *  which otherwise defaults to +nil+. For examples, see
 *  <code>Kernel::catch</code>.
 */

static VALUE
rb_f_throw(int argc, VALUE *argv)
{
    VALUE tag, value;

    rb_scan_args(argc, argv, "11", &tag, &value);
    rb_throw_obj(tag, value);
    UNREACHABLE;
}

void
rb_throw_obj(VALUE tag, VALUE value)
{
    rb_thread_t *th = GET_THREAD();
    struct rb_vm_tag *tt = th->tag;

    while (tt) {
	if (tt->tag == tag) {
	    tt->retval = value;
	    break;
	}
	tt = tt->prev;
    }
    if (!tt) {
	VALUE desc = rb_inspect(tag);
	rb_raise(rb_eArgError, "uncaught throw %"PRIsVALUE, desc);
    }
    th->errinfo = NEW_THROW_OBJECT(tag, 0, TAG_THROW);

    JUMP_TAG(TAG_THROW);
}

void
rb_throw(const char *tag, VALUE val)
{
    rb_throw_obj(ID2SYM(rb_intern(tag)), val);
}

static VALUE
catch_i(VALUE tag, VALUE data)
{
    return rb_yield_0(1, &tag);
}

/*
 *  call-seq:
 *     catch([arg]) {|tag| block }  -> obj
 *
 *  +catch+ executes its block. If a +throw+ is
 *  executed, Ruby searches up its stack for a +catch+ block
 *  with a tag corresponding to the +throw+'s
 *  _tag_. If found, that block is terminated, and
 *  +catch+ returns the value given to +throw+. If
 *  +throw+ is not called, the block terminates normally, and
 *  the value of +catch+ is the value of the last expression
 *  evaluated. +catch+ expressions may be nested, and the
 *  +throw+ call need not be in lexical scope.
 *
 *     def routine(n)
 *       puts n
 *       throw :done if n <= 0
 *       routine(n-1)
 *     end
 *
 *
 *     catch(:done) { routine(3) }
 *
 *  <em>produces:</em>
 *
 *     3
 *     2
 *     1
 *     0
 *
 *  when _arg_ is given, +catch+ yields it as is, or when no
 *  _arg_ is given, +catch+ assigns a new unique object to
 *  +throw+.  this is useful for nested +catch+.  _arg_ can
 *  be an arbitrary object, not only Symbol.
 *
 */

static VALUE
rb_f_catch(int argc, VALUE *argv)
{
    VALUE tag;

    if (argc == 0) {
	tag = rb_obj_alloc(rb_cObject);
    }
    else {
	rb_scan_args(argc, argv, "01", &tag);
    }
    return rb_catch_obj(tag, catch_i, 0);
}

VALUE
rb_catch(const char *tag, VALUE (*func)(), VALUE data)
{
    VALUE vtag = tag ? ID2SYM(rb_intern(tag)) : rb_obj_alloc(rb_cObject);
    return rb_catch_obj(vtag, func, data);
}

VALUE
rb_catch_obj(VALUE t, VALUE (*func)(), VALUE data)
{
    int state;
    VALUE val = rb_catch_protect(t, (rb_block_call_func *)func, data, &state);
    if (state)
	JUMP_TAG(state);
    return val;
}

VALUE
rb_catch_protect(VALUE t, rb_block_call_func *func, VALUE data, int *stateptr)
{
    int state;
    volatile VALUE val = Qnil;		/* OK */
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *saved_cfp = th->cfp;
    volatile VALUE tag = t;

    TH_PUSH_TAG(th);

    _tag.tag = tag;

    if ((state = TH_EXEC_TAG()) == 0) {
	/* call with argc=1, argv = [tag], block = Qnil to insure compatibility */
	val = (*func)(tag, data, 1, (const VALUE *)&tag, Qnil);
    }
    else if (state == TAG_THROW && RNODE(th->errinfo)->u1.value == tag) {
	th->cfp = saved_cfp;
	val = th->tag->retval;
	th->errinfo = Qnil;
	state = 0;
    }
    TH_POP_TAG();
    if (stateptr)
	*stateptr = state;

    return val;
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
    VALUE ary = rb_ary_new();
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp =
	vm_get_ruby_level_caller_cfp(th, RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp));
    int i;

    while (cfp) {
	if (cfp->iseq) {
	    for (i = 0; i < cfp->iseq->local_table_size; i++) {
		ID lid = cfp->iseq->local_table[i];
		if (lid) {
		    const char *vname = rb_id2name(lid);
		    /* should skip temporary variable */
		    if (vname) {
			rb_ary_push(ary, ID2SYM(lid));
		    }
		}
	    }
	}
	if (!VM_EP_LEP_P(cfp->ep)) {
	    /* block */
	    VALUE *ep = VM_CF_PREV_EP(cfp);

	    if (vm_collect_local_variables_in_heap(th, ep, ary)) {
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
    return ary;
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


VALUE
rb_f_block_given_p(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    cfp = vm_get_ruby_level_caller_cfp(th, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));

    if (cfp != 0 && VM_CF_BLOCK_PTR(cfp)) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

VALUE
rb_current_realfilepath(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    cfp = vm_get_ruby_level_caller_cfp(th, RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));
    if (cfp != 0) return cfp->iseq->location.absolute_path;
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
    rb_add_method(rb_cBasicObject, rb_intern("__send__"),
		  VM_METHOD_TYPE_OPTIMIZED, (void *)OPTIMIZED_METHOD_TYPE_SEND, 0);
    rb_add_method(rb_mKernel, rb_intern("send"),
		  VM_METHOD_TYPE_OPTIMIZED, (void *)OPTIMIZED_METHOD_TYPE_SEND, 0);
#else
    rb_define_method(rb_cBasicObject, "__send__", rb_f_send, -1);
    rb_define_method(rb_mKernel, "send", rb_f_send, -1);
#endif
    rb_define_method(rb_mKernel, "public_send", rb_f_public_send, -1);

    rb_define_method(rb_cModule, "module_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "class_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "module_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "class_eval", rb_mod_module_eval, -1);
}
