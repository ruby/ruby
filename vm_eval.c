/**********************************************************************

  vm_eval.c -

  $Author$
  created at: Sat May 24 16:02:32 JST 2008

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

static inline VALUE method_missing(VALUE obj, ID id, int argc, const VALUE *argv, int call_status);
static inline VALUE rb_vm_set_finish_env(rb_thread_t * th);
static inline VALUE vm_yield_with_cref(rb_thread_t *th, int argc, const VALUE *argv, const NODE *cref);
static inline VALUE vm_yield(rb_thread_t *th, int argc, const VALUE *argv);
static inline VALUE vm_backtrace(rb_thread_t *th, int lev);
static int vm_backtrace_each(rb_thread_t *th, int lev, rb_backtrace_iter_func *iter, void *arg);
static NODE *vm_cref_push(rb_thread_t *th, VALUE klass, int noex);
static VALUE vm_exec(rb_thread_t *th);
static void vm_set_eval_stack(rb_thread_t * th, VALUE iseqval, const NODE *cref);
static int vm_collect_local_variables_in_heap(rb_thread_t *th, VALUE *dfp, VALUE ary);

static inline VALUE
vm_call0(rb_thread_t * th, VALUE klass, VALUE recv, VALUE id, ID oid,
	 int argc, const VALUE *argv, const NODE *body, int nosuper)
{
    VALUE val;
    rb_block_t *blockptr = 0;

    if (0) printf("id: %s, nd: %s, argc: %d, passed: %p\n",
		  rb_id2name(id), ruby_node_name(nd_type(body)),
		  argc, (void *)th->passed_block);

    if (th->passed_block) {
	blockptr = th->passed_block;
	th->passed_block = 0;
    }
  again:
    switch (nd_type(body)) {
      case RUBY_VM_METHOD_NODE:{
	rb_control_frame_t *reg_cfp;
	VALUE iseqval = (VALUE)body->nd_body;
	int i;

	rb_vm_set_finish_env(th);
	reg_cfp = th->cfp;

	CHECK_STACK_OVERFLOW(reg_cfp, argc + 1);

	*reg_cfp->sp++ = recv;
	for (i = 0; i < argc; i++) {
	    *reg_cfp->sp++ = argv[i];
	}

	vm_setup_method(th, reg_cfp, argc, blockptr, 0, iseqval, recv);
	val = vm_exec(th);
	break;
      }
      case NODE_CFUNC: {
	EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, id, klass);
	{
	    rb_control_frame_t *reg_cfp = th->cfp;
	    rb_control_frame_t *cfp =
		vm_push_frame(th, 0, VM_FRAME_MAGIC_CFUNC,
			      recv, (VALUE)blockptr, 0, reg_cfp->sp, 0, 1);

	    cfp->method_id = oid;
	    cfp->method_class = klass;

	    val = call_cfunc(body->nd_cfnc, recv, (int)body->nd_argc, argc, argv);

	    if (reg_cfp != th->cfp + 1) {
		SDR2(reg_cfp);
		SDR2(th->cfp-5);
		rb_bug("cfp consistency error - call0");
		th->cfp = reg_cfp;
	    }
	    vm_pop_frame(th);
	}
	EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, id, klass);
	break;
      }
      case NODE_ATTRSET:{
	if (argc != 1) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", argc);
	}
	val = rb_ivar_set(recv, body->nd_vid, argv[0]);
	break;
      }
      case NODE_IVAR: {
	if (argc != 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)",
		     argc);
	}
	val = rb_attr_get(recv, body->nd_vid);
	break;
      }
      case NODE_BMETHOD:{
	val = vm_call_bmethod(th, oid, body->nd_cval,
			      recv, klass, argc, (VALUE *)argv, blockptr);
	break;
      }
      case NODE_ZSUPER:{
	klass = RCLASS_SUPER(klass);
	if (!klass || !(body = rb_method_node(klass, id))) {
	    return method_missing(recv, id, argc, argv, 0);
	}
	RUBY_VM_CHECK_INTS();
	nosuper = CALL_SUPER;
	body = body->nd_body;
	goto again;
      }
      default:
	rb_bug("unsupported: vm_call0(%s)", ruby_node_name(nd_type(body)));
    }
    RUBY_VM_CHECK_INTS();
    return val;
}

VALUE
rb_vm_call(rb_thread_t * th, VALUE klass, VALUE recv, VALUE id, ID oid,
	   int argc, const VALUE *argv, const NODE *body, int nosuper)
{
    return vm_call0(th, klass, recv, id, oid, argc, argv, body, nosuper);
}

static inline VALUE
vm_call_super(rb_thread_t * const th, const int argc, const VALUE * const argv)
{
    VALUE recv = th->cfp->self;
    VALUE klass;
    ID id;
    NODE *body;
    rb_control_frame_t *cfp = th->cfp;

    if (!cfp->iseq) {
	klass = cfp->method_class;
	klass = RCLASS_SUPER(klass);

	if (klass == 0) {
	    klass = vm_search_normal_superclass(cfp->method_class, recv);
	}

	id = cfp->method_id;
    }
    else {
	rb_bug("vm_call_super: should not be reached");
    }

    body = rb_method_node(klass, id);	/* this returns NODE_METHOD */
    if (!body) {
	return method_missing(recv, id, argc, argv, 0);
    }

    return vm_call0(th, klass, recv, id, (ID)body->nd_file,
		    argc, argv, body->nd_body, CALL_SUPER);
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

static inline VALUE
rb_call0(VALUE klass, VALUE recv, ID mid, int argc, const VALUE *argv,
	 int scope, VALUE self)
{
    NODE *body, *method;
    int noex;
    ID id = mid;
    struct cache_entry *ent;
    rb_thread_t *th = GET_THREAD();

    if (!klass) {
	rb_raise(rb_eNotImpError,
		 "method `%s' called on terminated object (%p)",
		 rb_id2name(mid), (void *)recv);
    }
    /* is it in the method cache? */
    ent = cache + EXPR1(klass, mid);

    if (ent->mid == mid && ent->klass == klass) {
	if (!ent->method)
	    return method_missing(recv, mid, argc, argv,
				  scope == 2 ? NOEX_VCALL : 0);
	id = ent->mid0;
	noex = (int)ent->method->nd_noex;
	klass = ent->method->nd_clss;
	body = ent->method->nd_body;
    }
    else if ((method = rb_get_method_body(klass, id, &id)) != 0) {
	noex = (int)method->nd_noex;
	klass = method->nd_clss;
	body = method->nd_body;
    }
    else {
	if (scope == 3) {
	    return method_missing(recv, mid, argc, argv, NOEX_SUPER);
	}
	return method_missing(recv, mid, argc, argv,
			      scope == 2 ? NOEX_VCALL : 0);
    }

    if (mid != idMethodMissing) {
	/* receiver specified form for private method */
	if (UNLIKELY(noex)) {
	    if (((noex & NOEX_MASK) & NOEX_PRIVATE) && scope == 0) {
		return method_missing(recv, mid, argc, argv, NOEX_PRIVATE);
	    }

	    /* self must be kind of a specified form for protected method */
	    if (((noex & NOEX_MASK) & NOEX_PROTECTED) && scope == 0) {
		VALUE defined_class = klass;

		if (TYPE(defined_class) == T_ICLASS) {
		    defined_class = RBASIC(defined_class)->klass;
		}

		if (self == Qundef) {
		    self = th->cfp->self;
		}
		if (!rb_obj_is_kind_of(self, rb_class_real(defined_class))) {
		    return method_missing(recv, mid, argc, argv, NOEX_PROTECTED);
		}
	    }

	    if (NOEX_SAFE(noex) > th->safe_level) {
		rb_raise(rb_eSecurityError, "calling insecure method: %s", rb_id2name(mid));
	    }
	}
    }

    stack_check();
    return vm_call0(th, klass, recv, mid, id, argc, argv, body, noex & NOEX_NOSUPER);
}

static inline VALUE
rb_call(VALUE klass, VALUE recv, ID mid, int argc, const VALUE *argv, int scope)
{
    return rb_call0(klass, recv, mid, argc, argv, scope, Qundef);
}

NORETURN(static void raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv,
					  VALUE obj, int call_status));

/*
 *  call-seq:
 *     obj.method_missing(symbol [, *args] )   => result
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
 *       def romanToInt(str)
 *         # ...
 *       end
 *       def method_missing(methId)
 *         str = methId.id2name
 *         romanToInt(str)
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
    return Qnil;		/* not reached */
}

#define NOEX_MISSING   0x80

static void
raise_method_missing(rb_thread_t *th, int argc, const VALUE *argv, VALUE obj,
		     int last_call_status)
{
    ID id;
    VALUE exc = rb_eNoMethodError;
    const char *format = 0;

    if (argc == 0 || !SYMBOL_P(argv[0])) {
	rb_raise(rb_eArgError, "no id given");
    }

    stack_check();

    id = SYM2ID(argv[0]);

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
    if (!format) {
	format = "undefined method `%s' for %s";
    }

    {
	int n = 0;
	VALUE args[3];
	args[n++] = rb_funcall(rb_const_get(exc, rb_intern("message")), '!',
			       3, rb_str_new2(format), obj, argv[0]);
	args[n++] = argv[0];
	if (exc == rb_eNoMethodError) {
	    args[n++] = rb_ary_new4(argc - 1, argv + 1);
	}
	exc = rb_class_new_instance(n, args, exc);

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

    th->method_missing_reason = call_status;
    th->passed_block = 0;

    if (id == idMethodMissing) {
	raise_method_missing(th, argc, argv, obj, call_status | NOEX_MISSING);
    }
    else if (id == ID_ALLOCATOR) {
	rb_raise(rb_eTypeError, "allocator undefined for %s",
		 rb_class2name(obj));
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

VALUE
rb_apply(VALUE recv, ID mid, VALUE args)
{
    int argc;
    VALUE *argv;

    argc = RARRAY_LEN(args);	/* Assigns LONG, but argc is INT */
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, RARRAY_PTR(args), VALUE, argc);
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, CALL_FCALL);
}

VALUE
rb_funcall(VALUE recv, ID mid, int n, ...)
{
    VALUE *argv;
    va_list ar;
    va_init_list(ar, n);

    if (n > 0) {
	long i;

	argv = ALLOCA_N(VALUE, n);

	for (i = 0; i < n; i++) {
	    argv[i] = va_arg(ar, VALUE);
	}
	va_end(ar);
    }
    else {
	argv = 0;
    }
    return rb_call(CLASS_OF(recv), recv, mid, n, argv, CALL_FCALL);
}

VALUE
rb_funcall2(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, CALL_FCALL);
}

VALUE
rb_funcall3(VALUE recv, ID mid, int argc, const VALUE *argv)
{
    return rb_call(CLASS_OF(recv), recv, mid, argc, argv, CALL_PUBLIC);
}

static VALUE
send_internal(int argc, VALUE *argv, VALUE recv, int scope)
{
    VALUE vid;
    VALUE self = RUBY_VM_PREVIOUS_CONTROL_FRAME(GET_THREAD()->cfp)->self;
    rb_thread_t *th = GET_THREAD();

    if (argc == 0) {
	rb_raise(rb_eArgError, "no method name given");
    }

    vid = *argv++; argc--;
    PASS_PASSED_BLOCK_TH(th);

    return rb_call0(CLASS_OF(recv), recv, rb_to_id(vid), argc, argv, scope, self);
}

/*
 *  call-seq:
 *     obj.send(symbol [, args...])        => obj
 *     obj.__send__(symbol [, args...])      => obj
 *
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. You can use <code>__send__</code> if the name
 *  +send+ clashes with an existing method in _obj_.
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
    return send_internal(argc, argv, recv, NOEX_NOSUPER | NOEX_PRIVATE);
}

/*
 *  call-seq:
 *     obj.public_send(symbol [, args...])  => obj
 *
 *  Invokes the method identified by _symbol_, passing it any
 *  arguments specified. Unlike send, public_send calls public
 *  methods only.
 *
 *     1.public_send(:puts, "hello")  # causes NoMethodError
 */

VALUE
rb_f_public_send(int argc, VALUE *argv, VALUE recv)
{
    return send_internal(argc, argv, recv, NOEX_PUBLIC);
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
    v = rb_yield_0(RARRAY_LEN(tmp), RARRAY_PTR(tmp));
    return v;
}

static VALUE
loop_i(void)
{
    for (;;) {
	rb_yield_0(0, 0);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     loop {|| block }
 *
 *  Repeatedly executes the block.
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
    RETURN_ENUMERATOR(self, 0, 0);
    rb_rescue2(loop_i, (VALUE)0, 0, 0, rb_eStopIteration, (VALUE)0);
    return Qnil;		/* dummy */
}

VALUE
rb_iterate(VALUE (* it_proc) (VALUE), VALUE data1,
	   VALUE (* bl_proc) (ANYARGS), VALUE data2)
{
    int state;
    volatile VALUE retval = Qnil;
    NODE *node = NEW_IFUNC(bl_proc, data2);
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *volatile cfp = th->cfp;

    TH_PUSH_TAG(th);
    state = TH_EXEC_TAG();
    if (state == 0) {
      iter_retry:
	{
	    rb_block_t *blockptr = RUBY_VM_GET_BLOCK_PTR_IN_CFP(th->cfp);
	    blockptr->iseq = (void *)node;
	    blockptr->proc = 0;
	    th->passed_block = blockptr;
	}
	retval = (*it_proc) (data1);
    }
    else {
	VALUE err = th->errinfo;
	if (state == TAG_BREAK) {
	    VALUE *escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
	    VALUE *cdfp = cfp->dfp;

	    if (cdfp == escape_dfp) {
		state = 0;
		th->state = 0;
		th->errinfo = Qnil;
		th->cfp = cfp;
	    }
	    else{
		/* SDR(); printf("%p, %p\n", cdfp, escape_dfp); */
	    }
	}
	else if (state == TAG_RETRY) {
	    VALUE *escape_dfp = GET_THROWOBJ_CATCH_POINT(err);
	    VALUE *cdfp = cfp->dfp;

	    if (cdfp == escape_dfp) {
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
    VALUE *argv;
};

static VALUE
iterate_method(VALUE obj)
{
    const struct iter_method_arg * arg =
      (struct iter_method_arg *) obj;

    return rb_call(CLASS_OF(arg->obj), arg->obj, arg->mid,
		   arg->argc, arg->argv, CALL_FCALL);
}

VALUE
rb_block_call(VALUE obj, ID mid, int argc, VALUE * argv,
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
rb_each(VALUE obj)
{
    return rb_call(CLASS_OF(obj), obj, idEach, 0, 0, CALL_FCALL);
}

static VALUE
eval_string_with_cref(VALUE self, VALUE src, VALUE scope, NODE *cref, const char *volatile file, volatile int line)
{
    int state;
    VALUE result = Qundef;
    VALUE envval;
    rb_binding_t *bind = 0;
    rb_thread_t *th = GET_THREAD();
    rb_env_t *env = NULL;
    rb_block_t block;
    volatile int parse_in_eval;
    volatile int mild_compile_error;

    if (file == 0) {
	file = rb_sourcefile();
	line = rb_sourceline();
    }

    parse_in_eval = th->parse_in_eval;
    mild_compile_error = th->mild_compile_error;
    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	rb_iseq_t *iseq;
	volatile VALUE iseqval;

	if (scope != Qnil) {
	    if (rb_obj_is_kind_of(scope, rb_cBinding)) {
		GetBindingPtr(scope, bind);
		envval = bind->env;
	    }
	    else {
		rb_raise(rb_eTypeError,
			 "wrong argument type %s (expected Binding)",
			 rb_obj_classname(scope));
	    }
	    GetEnvPtr(envval, env);
	    th->base_block = &env->block;
	}
	else {
	    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

	    if (cfp != 0) {
		block = *RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp);
		th->base_block = &block;
		th->base_block->self = self;
		th->base_block->iseq = cfp->iseq;	/* TODO */
	    }
	    else {
		rb_raise(rb_eRuntimeError, "Can't eval on top of Fiber or Thread");
	    }
	}

	/* make eval iseq */
	th->parse_in_eval++;
	th->mild_compile_error++;
	iseqval = rb_iseq_compile(src, rb_str_new2(file), INT2FIX(line));
	th->mild_compile_error--;
	th->parse_in_eval--;

	vm_set_eval_stack(th, iseqval, cref);
	th->base_block = 0;

	if (0) {		/* for debug */
	    printf("%s\n", RSTRING_PTR(rb_iseq_disasm(iseqval)));
	}

	/* save new env */
	GetISeqPtr(iseqval, iseq);
	if (bind && iseq->local_size > 0) {
	    bind->env = rb_vm_make_env_object(th, th->cfp);
	}

	/* kick */
	CHECK_STACK_OVERFLOW(th->cfp, iseq->stack_max);
	result = vm_exec(th);
    }
    POP_TAG();
    th->mild_compile_error = mild_compile_error;
    th->parse_in_eval = parse_in_eval;

    if (state) {
	if (state == TAG_RAISE) {
	    VALUE errinfo = th->errinfo;
	    if (strcmp(file, "(eval)") == 0) {
		VALUE mesg, errat, bt2;
		extern VALUE rb_get_backtrace(VALUE info);
		ID id_mesg;

		CONST_ID(id_mesg, "mesg");
		errat = rb_get_backtrace(errinfo);
		mesg = rb_attr_get(errinfo, id_mesg);
		if (!NIL_P(errat) && TYPE(errat) == T_ARRAY &&
		    (bt2 = vm_backtrace(th, -2), RARRAY_LEN(bt2) > 0)) {
		    if (!NIL_P(mesg) && TYPE(mesg) == T_STRING && !RSTRING_LEN(mesg)) {
			if (OBJ_FROZEN(mesg)) {
			    VALUE m = rb_str_cat(rb_str_dup(RARRAY_PTR(errat)[0]), ": ", 2);
			    rb_ivar_set(errinfo, id_mesg, rb_str_append(m, mesg));
			}
			else {
			    rb_str_update(mesg, 0, 0, rb_str_new2(": "));
			    rb_str_update(mesg, 0, 0, RARRAY_PTR(errat)[0]);
			}
		    }
		    RARRAY_PTR(errat)[0] = RARRAY_PTR(bt2)[0];
		}
	    }
	    rb_exc_raise(errinfo);
	}
	JUMP_TAG(state);
    }
    return result;
}

static VALUE
eval_string(VALUE self, VALUE src, VALUE scope, const char *file, int line)
{
    return eval_string_with_cref(self, src, scope, 0, file, line);
}

/*
 *  call-seq:
 *     eval(string [, binding [, filename [,lineno]]])  => obj
 *
 *  Evaluates the Ruby expression(s) in <em>string</em>. If
 *  <em>binding</em> is given, the evaluation is performed in its
 *  context. The binding may be a <code>Binding</code> object or a
 *  <code>Proc</code> object. If the optional <em>filename</em> and
 *  <em>lineno</em> parameters are present, they will be used when
 *  reporting syntax errors.
 *
 *     def getBinding(str)
 *       return binding
 *     end
 *     str = "hello"
 *     eval "str + ' Fred'"                      #=> "hello Fred"
 *     eval "str + ' Fred'", getBinding("bye")   #=> "bye Fred"
 */

VALUE
rb_f_eval(int argc, VALUE *argv, VALUE self)
{
    VALUE src, scope, vfile, vline;
    const char *file = "(eval)";
    int line = 1;

    rb_scan_args(argc, argv, "13", &src, &scope, &vfile, &vline);
    if (rb_safe_level() >= 4) {
	StringValue(src);
	if (!NIL_P(scope) && !OBJ_TAINTED(scope)) {
	    rb_raise(rb_eSecurityError,
		     "Insecure: can't modify trusted binding");
	}
    }
    else {
	SafeStringValue(src);
    }
    if (argc >= 3) {
	StringValue(vfile);
    }
    if (argc >= 4) {
	line = NUM2INT(vline);
    }

    if (!NIL_P(vfile))
	file = RSTRING_PTR(vfile);
    return eval_string(self, src, scope, file, line);
}

VALUE
rb_eval_string(const char *str)
{
    return eval_string(rb_vm_top_self(), rb_str_new2(str), Qnil, "(eval)", 1);
}

VALUE
rb_eval_string_protect(const char *str, int *state)
{
    return rb_protect((VALUE (*)(VALUE))rb_eval_string, (VALUE)str, state);
}

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
    VALUE val = Qnil;		/* OK */
    volatile int safe = rb_safe_level();

    if (OBJ_TAINTED(cmd)) {
	level = 4;
    }

    if (TYPE(cmd) != T_STRING) {
	PUSH_TAG();
	rb_set_safe_level_force(level);
	if ((state = EXEC_TAG()) == 0) {
	    val = rb_funcall2(cmd, rb_intern("call"), RARRAY_LEN(arg),
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
    if (state) rb_vm_jump_tag_but_local_jump(state, val);
    return val;
}

/* block eval under the class/module context */

static VALUE
yield_under(VALUE under, VALUE self, VALUE values)
{
    rb_thread_t *th = GET_THREAD();
    rb_block_t block, *blockptr;
    NODE *cref = vm_cref_push(th, under, NOEX_PUBLIC);

    if ((blockptr = GC_GUARDED_PTR_REF(th->cfp->lfp[0])) != 0) {
	block = *blockptr;
	block.self = self;
	th->cfp->lfp[0] = GC_GUARDED_PTR(&block);
    }

    if (values == Qundef) {
	return vm_yield_with_cref(th, 0, 0, cref);
    }
    else {
	return vm_yield_with_cref(th, RARRAY_LEN(values), RARRAY_PTR(values), cref);
    }
}

/* string eval under the class/module context */
static VALUE
eval_under(VALUE under, VALUE self, VALUE src, const char *file, int line)
{
    NODE *cref = vm_cref_push(GET_THREAD(), under, NOEX_PUBLIC);

    if (rb_safe_level() >= 4) {
	StringValue(src);
    }
    else {
	SafeStringValue(src);
    }

    return eval_string_with_cref(self, src, Qnil, cref, file, line);
}

static VALUE
specific_eval(int argc, VALUE *argv, VALUE klass, VALUE self)
{
    if (rb_block_given_p()) {
	if (argc > 0) {
	    rb_raise(rb_eArgError, "wrong number of arguments (%d for 0)", argc);
	}
	return yield_under(klass, self, Qundef);
    }
    else {
	const char *file = "(eval)";
	int line = 1;

	if (argc == 0) {
	    rb_raise(rb_eArgError, "block not supplied");
	}
	else {
	    if (rb_safe_level() >= 4) {
		StringValue(argv[0]);
	    }
	    else {
		SafeStringValue(argv[0]);
	    }
	    if (argc > 3) {
		const char *name = rb_id2name(rb_frame_callee());
		rb_raise(rb_eArgError,
			 "wrong number of arguments: %s(src) or %s{..}",
			 name, name);
	    }
	    if (argc > 2)
		line = NUM2INT(argv[2]);
	    if (argc > 1) {
		file = StringValuePtr(argv[1]);
	    }
	}
	return eval_under(klass, self, argv[0], file, line);
    }
}

/*
 *  call-seq:
 *     obj.instance_eval(string [, filename [, lineno]] )   => obj
 *     obj.instance_eval {| | block }                       => obj
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
	klass = Qnil;
    }
    else {
	klass = rb_singleton_class(self);
    }
    return specific_eval(argc, argv, klass, self);
}

/*
 *  call-seq:
 *     obj.instance_exec(arg...) {|var...| block }                       => obj
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
	klass = Qnil;
    }
    else {
	klass = rb_singleton_class(self);
    }
    return yield_under(klass, self, rb_ary_new4(argc, argv));
}

/*
 *  call-seq:
 *     mod.class_eval(string [, filename [, lineno]])  => obj
 *     mod.module_eval {|| block }                     => obj
 *
 *  Evaluates the string or block in the context of _mod_. This can
 *  be used to add methods to a class. <code>module_eval</code> returns
 *  the result of evaluating its argument. The optional _filename_
 *  and _lineno_ parameters set the text for error messages.
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
 *     mod.module_exec(arg...) {|var...| block }       => obj
 *     mod.class_exec(arg...) {|var...| block }        => obj
 *
 *  Evaluates the given block in the context of the class/module.
 *  The method defined in the block will belong to the receiver.
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
 *     throw(symbol [, obj])
 *
 *  Transfers control to the end of the active +catch+ block
 *  waiting for _symbol_. Raises +NameError+ if there
 *  is no +catch+ block for the symbol. The optional second
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
    return Qnil;		/* not reached */
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
	rb_raise(rb_eArgError, "uncaught throw %s", RSTRING_PTR(desc));
    }
    rb_trap_restore_mask();
    th->errinfo = NEW_THROW_OBJECT(tag, 0, TAG_THROW);

    JUMP_TAG(TAG_THROW);
}

void
rb_throw(const char *tag, VALUE val)
{
    rb_throw_obj(ID2SYM(rb_intern(tag)), val);
}

/*
 *  call-seq:
 *     catch(symbol) {| | block }  > obj
 *
 *  +catch+ executes its block. If a +throw+ is
 *  executed, Ruby searches up its stack for a +catch+ block
 *  with a tag corresponding to the +throw+'s
 *  _symbol_. If found, that block is terminated, and
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
 */

static VALUE
rb_f_catch(int argc, VALUE *argv)
{
    VALUE tag;
    int state;
    volatile VALUE val = Qnil;		/* OK */
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *saved_cfp = th->cfp;

    if (argc == 0) {
	tag = rb_obj_alloc(rb_cObject);
    }
    else {
	rb_scan_args(argc, argv, "01", &tag);
    }
    PUSH_TAG();

    th->tag->tag = tag;

    if ((state = EXEC_TAG()) == 0) {
	val = rb_yield_0(1, &tag);
    }
    else if (state == TAG_THROW && RNODE(th->errinfo)->u1.value == tag) {
	th->cfp = saved_cfp;
	val = th->tag->retval;
	th->errinfo = Qnil;
	state = 0;
    }
    POP_TAG();
    if (state)
	JUMP_TAG(state);

    return val;
}

static VALUE
catch_null_i(VALUE dmy)
{
    return rb_funcall(Qnil, rb_intern("catch"), 0, 0);
}

static VALUE
catch_i(VALUE tag)
{
    return rb_funcall(Qnil, rb_intern("catch"), 1, tag);
}

VALUE
rb_catch(const char *tag, VALUE (*func)(), VALUE data)
{
    if (!tag) {
	return rb_iterate(catch_null_i, 0, func, data);
    }
    return rb_iterate(catch_i, ID2SYM(rb_intern(tag)), func, data);
}

VALUE
rb_catch_obj(VALUE tag, VALUE (*func)(), VALUE data)
{
    return rb_iterate((VALUE (*)_((VALUE)))catch_i, tag, func, data);
}

/*
 *  call-seq:
 *     caller(start=1)    => array
 *
 *  Returns the current execution stack---an array containing strings in
 *  the form ``<em>file:line</em>'' or ``<em>file:line: in
 *  `method'</em>''. The optional _start_ parameter
 *  determines the number of initial stack entries to omit from the
 *  result.
 *
 *     def a(skip)
 *       caller(skip)
 *     end
 *     def b(skip)
 *       a(skip)
 *     end
 *     def c(skip)
 *       b(skip)
 *     end
 *     c(0)   #=> ["prog:2:in `a'", "prog:5:in `b'", "prog:8:in `c'", "prog:10"]
 *     c(1)   #=> ["prog:5:in `b'", "prog:8:in `c'", "prog:11"]
 *     c(2)   #=> ["prog:8:in `c'", "prog:12"]
 *     c(3)   #=> ["prog:13"]
 */

static VALUE
rb_f_caller(int argc, VALUE *argv)
{
    VALUE level;
    int lev;

    rb_scan_args(argc, argv, "01", &level);

    if (NIL_P(level))
	lev = 1;
    else
	lev = NUM2INT(level);
    if (lev < 0)
	rb_raise(rb_eArgError, "negative level (%d)", lev);

    return vm_backtrace(GET_THREAD(), lev);
}

static int
print_backtrace(void *arg, const char *file, int line, const char *method)
{
    fprintf((FILE *)arg, "\tfrom %s:%d:in `%s'\n", file, line, method);
    return Qfalse;
}

void
rb_backtrace(void)
{
    vm_backtrace_each(GET_THREAD(), -1, print_backtrace, stdout);
}

VALUE
rb_make_backtrace(void)
{
    return vm_backtrace(GET_THREAD(), -1);
}

VALUE
rb_backtrace_each(rb_backtrace_iter_func *iter, void *arg)
{
    return vm_backtrace_each(GET_THREAD(), -1, iter, arg);
}

/*
 *  call-seq:
 *     local_variables    => array
 *
 *  Returns the names of the current local variables.
 *
 *     fred = 1
 *     for i in 1..10
 *        # ...
 *     end
 *     local_variables   #=> ["fred", "i"]
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
	if (cfp->lfp != cfp->dfp) {
	    /* block */
	    VALUE *dfp = GC_GUARDED_PTR_REF(cfp->dfp[0]);

	    if (vm_collect_local_variables_in_heap(th, dfp, ary)) {
		break;
	    }
	    else {
		while (cfp->dfp != dfp) {
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
 *     block_given?   => true or false
 *     iterator?      => true or false
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

    if (cfp != 0 &&
	(cfp->lfp[0] & 0x02) == 0 &&
	GC_GUARDED_PTR_REF(cfp->lfp[0])) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
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

    rb_define_method(rb_cBasicObject, "__send__", rb_f_send, -1);
    rb_define_method(rb_mKernel, "send", rb_f_send, -1);
    rb_define_method(rb_mKernel, "public_send", rb_f_public_send, -1);

    rb_define_method(rb_cModule, "module_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "class_exec", rb_mod_module_exec, -1);
    rb_define_method(rb_cModule, "module_eval", rb_mod_module_eval, -1);
    rb_define_method(rb_cModule, "class_eval", rb_mod_module_eval, -1);

    rb_define_global_function("caller", rb_f_caller, -1);
}

