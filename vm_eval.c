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
static inline VALUE vm_yield_with_cref(rb_thread_t *th, int argc, const VALUE *argv, const rb_cref_t *cref);
static inline VALUE vm_yield(rb_thread_t *th, int argc, const VALUE *argv);
static inline VALUE vm_yield_with_block(rb_thread_t *th, int argc, const VALUE *argv, const rb_block_t *blockargptr);
static VALUE vm_exec(rb_thread_t *th);
static void vm_set_eval_stack(rb_thread_t * th, const rb_iseq_t *iseq, const rb_cref_t *cref, rb_block_t *base_block);
static int vm_collect_local_variables_in_heap(rb_thread_t *th, const VALUE *dfp, const struct local_var_list *vars);

static VALUE rb_eUncaughtThrow;
static ID id_result, id_tag, id_value;
#define id_mesg idMesg

/* vm_backtrace.c */
VALUE rb_vm_backtrace_str_ary(rb_thread_t *th, int lev, int n);

typedef enum call_type {
    CALL_PUBLIC,
    CALL_FCALL,
    CALL_VCALL,
    CALL_TYPE_MAX
} call_type;

static VALUE send_internal(int argc, const VALUE *argv, VALUE recv, call_type scope);

static VALUE vm_call0_body(rb_thread_t* th, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv);

static VALUE
vm_call0(rb_thread_t* th, VALUE recv, ID id, int argc, const VALUE *argv, const rb_callable_method_entry_t *me)
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

    return vm_call0_body(th, calling, &ci_entry, &cc_entry, argv);
}

#if OPT_CALL_CFUNC_WITHOUT_FRAME
static VALUE
vm_call0_cfunc(rb_thread_t* th, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    VALUE val;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, cc->me->owner, ci->mid);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, calling->recv, ci->mid, cc->me->owner, Qnil);
    {
	rb_control_frame_t *reg_cfp = th->cfp;
	const rb_callable_method_entry_t *me = cc->me;
	const rb_method_cfunc_t *cfunc = &me->def->body.cfunc;
	int len = cfunc->argc;
	VALUE recv = calling->recv;
	int argc = calling->argc;

	if (len >= 0) rb_check_arity(argc, len, len);

	th->passed_ci = ci;
	cc->aux.inc_sp = 0;
	VM_PROFILE_UP(C2C_CALL);
	val = (*cfunc->invoker)(cfunc->func, recv, argc, argv);

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
	    VM_PROFILE_UP(C2C_POPF);
	    vm_pop_frame(th);
	}
    }
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, calling->recv, ci->mid, callnig->cc->me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, cc->me->owner, ci->mid);

    return val;
}
#else
static VALUE
vm_call0_cfunc_with_frame(rb_thread_t* th, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    VALUE val;
    const rb_callable_method_entry_t *me = cc->me;
    const rb_method_cfunc_t *cfunc = &me->def->body.cfunc;
    int len = cfunc->argc;
    VALUE recv = calling->recv;
    int argc = calling->argc;
    ID mid = ci->mid;
    rb_block_t *blockptr = calling->blockptr;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, me->owner, mid);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, mid, me->owner, Qnil);
    {
	rb_control_frame_t *reg_cfp = th->cfp;

	vm_push_frame(th, 0, VM_FRAME_MAGIC_CFUNC, recv,
		      VM_ENVVAL_BLOCK_PTR(blockptr), (VALUE)me,
		      0, reg_cfp->sp, 1, 0);

	if (len >= 0) rb_check_arity(argc, len, len);

	VM_PROFILE_UP(C2C_CALL);
	val = (*cfunc->invoker)(cfunc->func, recv, argc, argv);

	if (UNLIKELY(reg_cfp != th->cfp + 1)) {
		rb_bug("vm_call0_cfunc_with_frame: cfp consistency error");
	}
	VM_PROFILE_UP(C2C_POPF);
	vm_pop_frame(th);
    }
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, mid, me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, me->owner, mid);

    return val;
}

static VALUE
vm_call0_cfunc(rb_thread_t* th, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    return vm_call0_cfunc_with_frame(th, calling, ci, cc, argv);
}
#endif

/* `ci' should point temporal value (on stack value) */
static VALUE
vm_call0_body(rb_thread_t* th, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    VALUE ret;

    if (th->passed_block) {
	calling->blockptr = (rb_block_t *)th->passed_block;
	th->passed_block = 0;
    }
    else {
	calling->blockptr = 0;
    }

  again:
    switch (cc->me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
	{
	    rb_control_frame_t *reg_cfp = th->cfp;
	    int i;

	    CHECK_VM_STACK_OVERFLOW(reg_cfp, calling->argc + 1);

	    *reg_cfp->sp++ = calling->recv;
	    for (i = 0; i < calling->argc; i++) {
		*reg_cfp->sp++ = argv[i];
	    }

	    vm_call_iseq_setup(th, reg_cfp, calling, ci, cc);
	    th->cfp->flag |= VM_FRAME_FLAG_FINISH;
	    return vm_exec(th); /* CHECK_INTS in this function */
	}
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
	ret = vm_call0_cfunc(th, calling, ci, cc, argv);
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
	ret = vm_call_bmethod_body(th, calling, ci, cc, argv);
	goto success;
      case VM_METHOD_TYPE_ZSUPER:
      case VM_METHOD_TYPE_REFINED:
	{
	    const rb_method_type_t type = cc->me->def->type;
	    VALUE super_class;

	    if (type == VM_METHOD_TYPE_REFINED && cc->me->def->body.refined.orig_me) {
		cc->me = refined_method_callable_without_refinement(cc->me);
		goto again;
	    }

	    super_class = RCLASS_SUPER(cc->me->defined_class);

	    if (!super_class || !(cc->me = rb_callable_method_entry(super_class, ci->mid))) {
		enum method_missing_reason ex = (type == VM_METHOD_TYPE_ZSUPER) ? MISSING_SUPER : 0;
		ret = method_missing(calling->recv, ci->mid, calling->argc, argv, ex);
		goto success;
	    }
	    RUBY_VM_CHECK_INTS(th);
	    goto again;
	}
      case VM_METHOD_TYPE_ALIAS:
	cc->me = aliased_callable_method_entry(cc->me);
	goto again;
      case VM_METHOD_TYPE_MISSING:
	{
	    th->passed_block = calling->blockptr;
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
		ret = rb_vm_invoke_proc(th, proc, calling->argc, argv, calling->blockptr);
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
    RUBY_VM_CHECK_INTS(th);
    return ret;
}

VALUE
rb_vm_call(rb_thread_t *th, VALUE recv, VALUE id, int argc, const VALUE *argv, const rb_callable_method_entry_t *me)
{
    return vm_call0(th, recv, id, argc, argv, me);
}

static inline VALUE
vm_call_super(rb_thread_t *th, int argc, const VALUE *argv)
{
    VALUE recv = th->cfp->self;
    VALUE klass;
    ID id;
    rb_control_frame_t *cfp = th->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
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
	return vm_call0(th, recv, id, argc, argv, me);
    }
}

VALUE
rb_call_super(int argc, const VALUE *argv)
{
    PASS_PASSED_BLOCK();
    return vm_call_super(GET_THREAD(), argc, argv);
}

VALUE
rb_current_receiver(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp;
    if (!th || !(cfp = th->cfp))
	rb_raise(rb_eRuntimeError, "no self, no life");
    return cfp->self;
}

static inline void
stack_check(rb_thread_t *th)
{
    if (!rb_thread_raised_p(th, RAISED_STACKOVERFLOW) && ruby_stack_check()) {
	rb_thread_raised_set(th, RAISED_STACKOVERFLOW);
	rb_exc_raise(sysstack_error);
    }
}

static inline const rb_callable_method_entry_t *rb_search_method_entry(VALUE recv, ID mid);
static inline enum method_missing_reason rb_method_call_status(rb_thread_t *th, const rb_callable_method_entry_t *me, call_type scope, VALUE self);

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
    const rb_callable_method_entry_t *me = rb_search_method_entry(recv, mid);
    rb_thread_t *th = GET_THREAD();
    enum method_missing_reason call_status = rb_method_call_status(th, me, scope, self);

    if (call_status != MISSING_NONE) {
	return method_missing(recv, mid, argc, argv, call_status);
    }
    stack_check(th);
    return vm_call0(th, recv, mid, argc, argv, me);
}

struct rescue_funcall_args {
    rb_thread_t *th;
    VALUE defined_class;
    VALUE recv;
    ID mid;
    const rb_method_entry_t *me;
    unsigned int respond: 1;
    unsigned int respond_to_missing: 1;
    int argc;
    const VALUE *argv;
};

static VALUE
check_funcall_exec(struct rescue_funcall_args *args)
{
    return call_method_entry(args->th, args->defined_class,
			     args->recv, idMethodMissing,
			     args->me, args->argc, args->argv);
}

#define PRIV Qfalse	 /* TODO: for rubyspec now, should be Qtrue */

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
check_funcall_respond_to(rb_thread_t *th, VALUE klass, VALUE recv, ID mid)
{
    return vm_respond_to(th, klass, recv, mid, TRUE);
}

static int
check_funcall_callable(rb_thread_t *th, const rb_callable_method_entry_t *me)
{
    return rb_method_call_status(th, me, CALL_FCALL, th->cfp->self) == MISSING_NONE;
}

static VALUE
check_funcall_missing(rb_thread_t *th, VALUE klass, VALUE recv, ID mid, int argc, const VALUE *argv, int respond, VALUE def)
{
    struct rescue_funcall_args args;
    const rb_method_entry_t *me;
    VALUE ret = Qundef;

    ret = basic_obj_respond_to_missing(th, klass, recv,
				       ID2SYM(mid), PRIV);
    if (!RTEST(ret)) return def;
    args.respond = respond > 0;
    args.respond_to_missing = (ret != Qundef);
    ret = def;
    me = method_entry_get(klass, idMethodMissing, &args.defined_class);
    if (me && !METHOD_ENTRY_BASIC(me)) {
	VALUE argbuf, *new_args = ALLOCV_N(VALUE, argbuf, argc+1);

	new_args[0] = ID2SYM(mid);
	MEMCPY(new_args+1, argv, VALUE, argc);
	th->method_missing_reason = MISSING_NOENTRY;
	args.th = th;
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
    rb_thread_t *th = GET_THREAD();
    int respond = check_funcall_respond_to(th, klass, recv, mid);

    if (!respond)
	return def;

    me = rb_search_method_entry(recv, mid);
    if (!check_funcall_callable(th, me)) {
	return check_funcall_missing(th, klass, recv, mid, argc, argv,
				     respond, def);
    }
    stack_check(th);
    return vm_call0(th, recv, mid, argc, argv, me);
}

VALUE
rb_check_funcall_with_hook(VALUE recv, ID mid, int argc, const VALUE *argv,
			   rb_check_funcall_hook *hook, VALUE arg)
{
    VALUE klass = CLASS_OF(recv);
    const rb_callable_method_entry_t *me;
    rb_thread_t *th = GET_THREAD();
    int respond = check_funcall_respond_to(th, klass, recv, mid);

    if (!respond) {
	(*hook)(FALSE, recv, mid, argc, argv, arg);
	return Qundef;
    }

    me = rb_search_method_entry(recv, mid);
    if (!check_funcall_callable(th, me)) {
	VALUE ret = check_funcall_missing(th, klass, recv, mid, argc, argv,
					  respond, Qundef);
	(*hook)(ret != Qundef, recv, mid, argc, argv, arg);
	return ret;
    }
    stack_check(th);
    (*hook)(TRUE, recv, mid, argc, argv, arg);
    return vm_call0(th, recv, mid, argc, argv, me);
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
      type_case(T_IMEMO)
      type_case(T_UNDEF)
      type_case(T_NODE)
      type_case(T_ICLASS)
      type_case(T_ZOMBIE)
      default: return NULL;
    }
#undef type_case
}

static inline const rb_callable_method_entry_t *
rb_search_method_entry(VALUE recv, ID mid)
{
    VALUE klass = CLASS_OF(recv);

    if (!klass) {
        VALUE flags;
        if (SPECIAL_CONST_P(recv)) {
            rb_raise(rb_eNotImpError,
                     "method `%"PRIsVALUE"' called on unexpected immediate object (%p)",
                     rb_id2str(mid), (void *)recv);
        }
        flags = RBASIC(recv)->flags;
        if (flags == 0) {
            rb_raise(rb_eNotImpError,
                     "method `%"PRIsVALUE"' called on terminated object"
                     " (%p flags=0x%"PRIxVALUE")",
                     rb_id2str(mid), (void *)recv, flags);
        }
        else {
            int type = BUILTIN_TYPE(recv);
            const char *typestr = rb_type_str(type);
            if (typestr && T_OBJECT <= type && type < T_NIL)
                rb_raise(rb_eNotImpError,
                         "method `%"PRIsVALUE"' called on hidden %s object"
                         " (%p flags=0x%"PRIxVALUE")",
                         rb_id2str(mid), typestr, (void *)recv, flags);
            if (typestr)
                rb_raise(rb_eNotImpError,
                         "method `%"PRIsVALUE"' called on unexpected %s object"
                         " (%p flags=0x%"PRIxVALUE")",
                         rb_id2str(mid), typestr, (void *)recv, flags);
            else
                rb_raise(rb_eNotImpError,
                         "method `%"PRIsVALUE"' called on broken T_???" "(0x%02x) object"
                         " (%p flags=0x%"PRIxVALUE")",
                         rb_id2str(mid), type, (void *)recv, flags);
        }
    }
    return rb_callable_method_entry(klass, mid);
}

static inline enum method_missing_reason
rb_method_call_status(rb_thread_t *th, const rb_callable_method_entry_t *me, call_type scope, VALUE self)
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
    rb_thread_t *th = GET_THREAD();
    return rb_call0(recv, mid, argc, argv, scope, th->cfp->self);
}

NORETURN(static void raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv,
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
    rb_thread_t *th = GET_THREAD();
    raise_method_missing(th, argc, argv, obj, th->method_missing_reason);
    UNREACHABLE;
}

static VALUE
make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
			 int argc, const VALUE *argv, int priv)
{
    int n = 0;
    enum {
	arg_mesg,
	arg_name,
	arg_args,
	arg_priv,
	args_size
    };
    VALUE args[args_size];

    if (!format) {
	format = rb_fstring_cstr("undefined method `%s' for %s%s%s");
    }
    args[n++] = rb_name_err_mesg_new(format, obj, argv[0]);
    args[n++] = argv[0];
    if (exc == rb_eNoMethodError) {
	args[n++] = rb_ary_new4(argc - 1, argv + 1);
	args[n++] = priv ? Qtrue : Qfalse;
    }
    return rb_class_new_instance(n, args, exc);
}

static void
raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv, VALUE obj,
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

    stack_check(th);

    if (last_call_status & MISSING_PRIVATE) {
	format = rb_fstring_cstr("private method `%s' called for %s%s%s");
    }
    else if (last_call_status & MISSING_PROTECTED) {
	format = rb_fstring_cstr("protected method `%s' called for %s%s%s");
    }
    else if (last_call_status & MISSING_VCALL) {
	format = rb_fstring_cstr("undefined local variable or method `%s' for %s%s%s");
	exc = rb_eNameError;
    }
    else if (last_call_status & MISSING_SUPER) {
	format = rb_fstring_cstr("super: no superclass method `%s' for %s%s%s");
    }

    {
	exc = make_no_method_exception(exc, format, obj, argc, argv,
				       last_call_status & (MISSING_FCALL|MISSING_VCALL));
	if (!(last_call_status & MISSING_MISSING)) {
	    rb_vm_pop_cfunc_frame();
	}
	rb_exc_raise(exc);
    }
}

static inline VALUE
method_missing(VALUE obj, ID id, int argc, const VALUE *argv, enum method_missing_reason call_status)
{
    VALUE *nargv, result, work, klass;
    rb_thread_t *th = GET_THREAD();
    const rb_block_t *blockptr = th->passed_block;
    const rb_callable_method_entry_t *me;

    th->method_missing_reason = call_status;
    th->passed_block = 0;

    if (id == idMethodMissing) {
      missing:
	raise_method_missing(th, argc, argv, obj, call_status | MISSING_MISSING);
    }

    nargv = ALLOCV_N(VALUE, work, argc + 1);
    nargv[0] = ID2SYM(id);
    MEMCPY(nargv + 1, argv, VALUE, argc);
    ++argc;
    argv = nargv;

    klass = CLASS_OF(obj);
    if (!klass) goto missing;
    me = rb_callable_method_entry(klass, idMethodMissing);
    if (!me || METHOD_ENTRY_BASIC(me)) goto missing;
    th->passed_block = blockptr;
    result = vm_call0(th, obj, idMethodMissing, argc, argv, me);
    if (work) ALLOCV_END(work);
    return result;
}

void
rb_raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv,
			VALUE obj, int call_status)
{
    th->passed_block = 0;
    raise_method_missing(th, argc, argv, obj, call_status | MISSING_MISSING);
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
	ret = rb_call(recv, mid, argc, RARRAY_CONST_PTR(args), CALL_FCALL);
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
    PASS_PASSED_BLOCK();

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

static VALUE *
current_vm_stack_arg(rb_thread_t *th, const VALUE *argv)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
    if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, prev_cfp)) return NULL;
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

    vid = *argv;

    id = rb_check_id(&vid);
    if (!id) {
	if (rb_method_basic_definition_p(CLASS_OF(recv), idMethodMissing)) {
	    VALUE exc = make_no_method_exception(rb_eNoMethodError, 0,
						 recv, argc, argv,
						 scope != CALL_PUBLIC);
	    rb_exc_raise(exc);
	}
	if (!SYMBOL_P(*argv)) {
	    VALUE *tmp_argv = current_vm_stack_arg(th, argv);
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
	th->method_missing_reason = MISSING_NOENTRY;
    }
    else {
	argv++; argc--;
    }
    PASS_PASSED_BLOCK_TH(th);
    ret = rb_call0(recv, id, argc, argv, scope, self);
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
    RB_GC_GUARD(tmp);
    return v;
}

VALUE
rb_yield_block(VALUE val, VALUE arg, int argc, const VALUE *argv, VALUE blockarg)
{
    const rb_block_t *blockptr = NULL;
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
loop_stop(VALUE dummy, VALUE exc)
{
    return rb_attr_get(exc, id_result);
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
	    rb_thread_t *const th)
{
    int state;
    volatile VALUE retval = Qnil;
    rb_control_frame_t *const cfp = th->cfp;

    TH_PUSH_TAG(th);
    state = TH_EXEC_TAG();
    if (state == 0) {
      iter_retry:
	{
	    rb_block_t *blockptr;
	    if (ifunc) {
		blockptr = RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp);
		blockptr->iseq = (void *)ifunc;
		blockptr->proc = 0;
	    }
	    else {
		blockptr = VM_CF_BLOCK_PTR(cfp);
	    }
	    th->passed_block = blockptr;
	}
	retval = (*it_proc) (data1);
    }
    else if (state == TAG_BREAK || state == TAG_RETRY) {
	const struct vm_throw_data *const err = (struct vm_throw_data *)th->errinfo;
	const rb_control_frame_t *const escape_cfp = THROW_DATA_CATCH_FRAME(err);

	if (cfp == escape_cfp) {
	    rb_vm_rewind_cfp(th, cfp);

	    state = 0;
	    th->state = 0;
	    th->errinfo = Qnil;

	    if (state == TAG_RETRY) goto iter_retry;
	    retval = THROW_DATA_VAL(err);
	}
	else if (0) {
	    SDR(); fprintf(stderr, "%p, %p\n", cfp, escape_cfp);
	}
    }
    TH_POP_TAG();

    if (state) {
	TH_JUMP_TAG(th, state);
    }
    return retval;
}

VALUE
rb_iterate(VALUE (* it_proc)(VALUE), VALUE data1,
	   VALUE (* bl_proc)(ANYARGS), VALUE data2)
{
    return rb_iterate0(it_proc, data1,
		       bl_proc ? IFUNC_NEW(bl_proc, data2, rb_frame_this_func()) : 0,
		       GET_THREAD());
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
adjust_backtrace_in_eval(rb_thread_t *th, VALUE errinfo)
{
    VALUE errat = rb_get_backtrace(errinfo);
    VALUE mesg = rb_attr_get(errinfo, id_mesg);
    if (RB_TYPE_P(errat, T_ARRAY)) {
	VALUE bt2 = rb_vm_backtrace_str_ary(th, 0, 0);
	if (RARRAY_LEN(bt2) > 0) {
	    if (RB_TYPE_P(mesg, T_STRING) && !RSTRING_LEN(mesg)) {
		rb_ivar_set(errinfo, id_mesg, RARRAY_AREF(errat, 0));
	    }
	    RARRAY_ASET(errat, 0, RARRAY_AREF(bt2, 0));
	}
    }
    return errinfo;
}

static VALUE
eval_string_with_cref(VALUE self, VALUE src, VALUE scope, rb_cref_t *const cref_arg,
		      VALUE filename, int lineno)
{
    int state;
    VALUE result = Qundef;
    VALUE envval;
    rb_thread_t *th = GET_THREAD();
    rb_env_t *env = NULL;
    rb_block_t block, *base_block;
    volatile VALUE file;
    volatile int line;

    file = filename ? filename : rb_source_location(&lineno);
    line = lineno;

    {
	rb_cref_t *cref = cref_arg;
	rb_binding_t *bind = 0;
	const rb_iseq_t *iseq;
	VALUE absolute_path = Qnil;
	VALUE fname;

	if (file != Qundef) {
	    absolute_path = file;
	}

	if (!NIL_P(scope)) {
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
	iseq = rb_iseq_compile_with_option(src, fname, absolute_path, INT2FIX(line), base_block, Qnil);

	if (!iseq) {
	    rb_exc_raise(adjust_backtrace_in_eval(th, th->errinfo));
	}

	if (!cref && base_block->iseq) {
	    if (NIL_P(scope)) {
		rb_cref_t *orig_cref = rb_vm_get_cref(base_block->ep);
		cref = vm_cref_dup(orig_cref);
	    }
	    else {
		cref = NULL; /* use stacked CREF */
	    }
	}
	vm_set_eval_stack(th, iseq, cref, base_block);

	if (0) {		/* for debug */
	    VALUE disasm = rb_iseq_disasm(iseq);
	    printf("%s\n", StringValuePtr(disasm));
	}

	/* save new env */
	if (bind && iseq->body->local_table_size > 0) {
	    bind->env = vm_make_env_object(th, th->cfp);
	}
    }

    if (file != Qundef) {
	/* kick */
	return vm_exec(th);
    }

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	result = vm_exec(th);
    }
    TH_POP_TAG();

    if (state) {
	if (state == TAG_RAISE) {
	    adjust_backtrace_in_eval(th, th->errinfo);
	}
	TH_JUMP_TAG(th, state);
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
	TH_JUMP_TAG(th, status);
    }
    return val;
}

VALUE
rb_eval_cmd(VALUE cmd, VALUE arg, int level)
{
    int state;
    volatile VALUE val = Qnil;		/* OK */
    volatile int safe = rb_safe_level();
    rb_thread_t *th = GET_THREAD();

    if (OBJ_TAINTED(cmd)) {
	level = RUBY_SAFE_LEVEL_MAX;
    }

    if (!RB_TYPE_P(cmd, T_STRING)) {
	TH_PUSH_TAG(th);
	rb_set_safe_level_force(level);
	if ((state = TH_EXEC_TAG()) == 0) {
	    val = rb_funcall2(cmd, idCall, RARRAY_LENINT(arg),
			      RARRAY_CONST_PTR(arg));
	}
	TH_POP_TAG();

	rb_set_safe_level_force(safe);

	if (state)
	    TH_JUMP_TAG(th, state);
	return val;
    }

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
	val = eval_string(rb_vm_top_self(), cmd, Qnil, 0, 0);
    }
    TH_POP_TAG();

    rb_set_safe_level_force(safe);
    if (state) TH_JUMP_TAG(th, state);
    return val;
}

/* block eval under the class/module context */

static VALUE
yield_under(VALUE under, VALUE self, VALUE values)
{
    rb_thread_t *th = GET_THREAD();
    rb_block_t block, *blockptr;
    rb_cref_t *cref;

    if ((blockptr = VM_CF_BLOCK_PTR(th->cfp)) != 0) {
	block = *blockptr;
	block.self = self;
	VM_CF_LEP(th->cfp)[0] = VM_ENVVAL_BLOCK_PTR(&block);
    }
    cref = vm_cref_push(th, under, blockptr, TRUE);

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
    rb_cref_t *cref;

    if ((blockptr = VM_CF_BLOCK_PTR(th->cfp)) != 0) {
	block = *blockptr;
	block.self = refinement;
	VM_CF_LEP(th->cfp)[0] = VM_ENVVAL_BLOCK_PTR(&block);
    }
    cref = vm_cref_push(th, refinement, blockptr, TRUE);
    CREF_REFINEMENTS_SET(cref, refinements);

    return vm_yield_with_cref(th, 0, NULL, cref);
}

/* string eval under the class/module context */
static VALUE
eval_under(VALUE under, VALUE self, VALUE src, VALUE file, int line)
{
    rb_cref_t *cref = vm_cref_push(GET_THREAD(), under, NULL, SPECIAL_CONST_P(self) && !NIL_P(under));
    SafeStringValue(src);
    return eval_string_with_cref(self, src, Qnil, cref, file, line);
}

static VALUE
specific_eval(int argc, const VALUE *argv, VALUE klass, VALUE self)
{
    if (rb_block_given_p()) {
	rb_check_arity(argc, 0, 0);
	return yield_under(klass, self, Qundef);
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
    return yield_under(klass, self, rb_ary_new4(argc, argv));
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
    return yield_under(mod, mod, rb_ary_new4(argc, argv));
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
	VALUE desc[3];
	desc[0] = tag;
	desc[1] = value;
	desc[2] = rb_str_new_cstr("uncaught throw %p");
	rb_exc_raise(rb_class_new_instance(numberof(desc), desc, rb_eUncaughtThrow));
    }

    th->errinfo = (VALUE)THROW_DATA_NEW(tag, NULL, TAG_THROW);
    TH_JUMP_TAG(th, TAG_THROW);
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
    VALUE vtag = tag ? rb_sym_intern_ascii_cstr(tag) : rb_obj_alloc(rb_cObject);
    return rb_catch_obj(vtag, func, data);
}

static VALUE vm_catch_protect(VALUE, rb_block_call_func *, VALUE, int *, rb_thread_t *);

VALUE
rb_catch_obj(VALUE t, VALUE (*func)(), VALUE data)
{
    int state;
    rb_thread_t *th = GET_THREAD();
    VALUE val = vm_catch_protect(t, (rb_block_call_func *)func, data, &state, th);
    if (state)
	TH_JUMP_TAG(th, state);
    return val;
}

VALUE
rb_catch_protect(VALUE t, rb_block_call_func *func, VALUE data, int *stateptr)
{
    return vm_catch_protect(t, func, data, stateptr, GET_THREAD());
}

static VALUE
vm_catch_protect(VALUE tag, rb_block_call_func *func, VALUE data,
		 int *stateptr, rb_thread_t *th)
{
    int state;
    VALUE val = Qnil;		/* OK */
    rb_control_frame_t *saved_cfp = th->cfp;

    TH_PUSH_TAG(th);

    _tag.tag = tag;

    if ((state = TH_EXEC_TAG()) == 0) {
	/* call with argc=1, argv = [tag], block = Qnil to insure compatibility */
	val = (*func)(tag, data, 1, (const VALUE *)&tag, Qnil);
    }
    else if (state == TAG_THROW && THROW_DATA_VAL((struct vm_throw_data *)th->errinfo) == tag) {
	rb_vm_rewind_cfp(th, saved_cfp);
	val = th->tag->retval;
	th->errinfo = Qnil;
	state = 0;
    }
    TH_POP_TAG();
    if (stateptr)
	*stateptr = state;

    return val;
}

static void
local_var_list_init(struct local_var_list *vars)
{
    vars->tbl = rb_hash_new();
    RHASH(vars->tbl)->ntbl = st_init_numtable(); /* compare_by_identity */
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
	st_table *tbl = RHASH_TBL_RAW(vars->tbl);
	st_data_t idx = 0;	/* tbl->num_entries */
	st_update(tbl, ID2SYM(lid), local_var_list_update, idx);
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
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp =
	vm_get_ruby_level_caller_cfp(th, RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp));
    unsigned int i;

    local_var_list_init(&vars);
    while (cfp) {
	if (cfp->iseq) {
	    for (i = 0; i < cfp->iseq->body->local_table_size; i++) {
		local_var_list_add(&vars, cfp->iseq->body->local_table[i]);
	    }
	}
	if (!VM_EP_LEP_P(cfp->ep)) {
	    /* block */
	    VALUE *ep = VM_CF_PREV_EP(cfp);

	    if (vm_collect_local_variables_in_heap(th, ep, &vars)) {
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
    if (cfp != 0) return cfp->iseq->body->location.absolute_path;
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
		  VM_METHOD_TYPE_OPTIMIZED, (void *)OPTIMIZED_METHOD_TYPE_SEND, METHOD_VISI_PUBLIC);
    rb_add_method(rb_mKernel, rb_intern("send"),
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
