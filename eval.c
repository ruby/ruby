/**********************************************************************

  eval.c -

  $Author$
  created at: Thu Jun 10 14:22:17 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "internal.h"
#include "eval_intern.h"
#include "iseq.h"
#include "gc.h"
#include "ruby/vm.h"
#include "vm_core.h"
#include "probes_helper.h"

NORETURN(void rb_raise_jump(VALUE, VALUE));

VALUE rb_eLocalJumpError;
VALUE rb_eSysStackError;

ID ruby_static_id_signo, ruby_static_id_status;
static ID id_cause;
#define id_signo ruby_static_id_signo
#define id_status ruby_static_id_status

#define exception_error GET_VM()->special_exceptions[ruby_error_reenter]

#include "eval_error.c"
#include "eval_jump.c"

#define CLASS_OR_MODULE_P(obj) \
    (!SPECIAL_CONST_P(obj) && \
     (BUILTIN_TYPE(obj) == T_CLASS || BUILTIN_TYPE(obj) == T_MODULE))

/* Initializes the Ruby VM and builtin libraries.
 * @retval 0 if succeeded.
 * @retval non-zero an error occurred.
 */
int
ruby_setup(void)
{
    int state;

    if (GET_VM())
	return 0;

    ruby_init_stack((void *)&state);
    Init_BareVM();
    Init_heap();
    Init_vm_objects();

    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	rb_call_inits();
	ruby_prog_init();
	GET_VM()->running = 1;
    }
    POP_TAG();

    return state;
}

/* Calls ruby_setup() and check error.
 *
 * Prints errors and calls exit(3) if an error occurred.
 */
void
ruby_init(void)
{
    int state = ruby_setup();
    if (state) {
        if (RTEST(ruby_debug))
            error_print(GET_THREAD());
	exit(EXIT_FAILURE);
    }
}

/*! Processes command line arguments and compiles the Ruby source to execute.
 *
 * This function does:
 * \li Processes the given command line flags and arguments for ruby(1)
 * \li compiles the source code from the given argument, -e or stdin, and
 * \li returns the compiled source as an opaque pointer to an internal data structure
 *
 * @return an opaque pointer to the compiled source or an internal special value.
 * @sa ruby_executable_node().
 */
void *
ruby_options(int argc, char **argv)
{
    int state;
    void *volatile iseq = 0;

    ruby_init_stack((void *)&iseq);
    PUSH_TAG();
    if ((state = EXEC_TAG()) == 0) {
	SAVE_ROOT_JMPBUF(GET_THREAD(), iseq = ruby_process_options(argc, argv));
    }
    else {
	rb_clear_trace_func();
	state = error_handle(state);
	iseq = (void *)INT2FIX(state);
    }
    POP_TAG();
    return iseq;
}

static void
ruby_finalize_0(void)
{
    PUSH_TAG();
    if (EXEC_TAG() == 0) {
	rb_trap_exit();
    }
    POP_TAG();
    rb_exec_end_proc();
    rb_clear_trace_func();
}

static void
ruby_finalize_1(void)
{
    ruby_sig_finalize();
    GET_THREAD()->errinfo = Qnil;
    rb_gc_call_finalizer_at_exit();
}

/** Runs the VM finalization processes.
 *
 * <code>END{}</code> and procs registered by <code>Kernel.#at_exit</code> are
 * executed here. See the Ruby language spec for more details.
 *
 * @note This function is allowed to raise an exception if an error occurred.
 */
void
ruby_finalize(void)
{
    ruby_finalize_0();
    ruby_finalize_1();
}

/** Destructs the VM.
 *
 * Runs the VM finalization processes as well as ruby_finalize(), and frees
 * resources used by the VM.
 *
 * @param ex Default value to the return value.
 * @return If an error occurred returns a non-zero. If otherwise, returns the
 *         given ex.
 * @note This function does not raise any exception.
 */
int
ruby_cleanup(volatile int ex)
{
    int state;
    volatile VALUE errs[2];
    rb_thread_t *th = GET_THREAD();
    int nerr;
    volatile int sysex = EXIT_SUCCESS;
    volatile int step = 0;

    rb_threadptr_interrupt(th);
    rb_threadptr_check_signal(th);
    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	SAVE_ROOT_JMPBUF(th, { RUBY_VM_CHECK_INTS(th); });

      step_0: step++;
	errs[1] = th->errinfo;
	th->safe_level = 0;
	ruby_init_stack(&errs[STACK_UPPER(errs, 0, 1)]);

	SAVE_ROOT_JMPBUF(th, ruby_finalize_0());

      step_1: step++;
	/* protect from Thread#raise */
	th->status = THREAD_KILLED;

	errs[0] = th->errinfo;
	SAVE_ROOT_JMPBUF(th, rb_thread_terminate_all());
    }
    else {
	switch (step) {
	  case 0: goto step_0;
	  case 1: goto step_1;
	}
	if (ex == 0) ex = state;
    }
    th->errinfo = errs[1];
    sysex = error_handle(ex);

    state = 0;
    for (nerr = 0; nerr < numberof(errs); ++nerr) {
	VALUE err = ATOMIC_VALUE_EXCHANGE(errs[nerr], Qnil);

	if (!RTEST(err)) continue;

	/* th->errinfo contains a NODE while break'ing */
	if (THROW_DATA_P(err)) continue;

	if (rb_obj_is_kind_of(err, rb_eSystemExit)) {
	    sysex = sysexit_status(err);
	    break;
	}
	else if (rb_obj_is_kind_of(err, rb_eSignal)) {
	    VALUE sig = rb_ivar_get(err, id_signo);
	    state = NUM2INT(sig);
	    break;
	}
	else if (sysex == EXIT_SUCCESS) {
	    sysex = EXIT_FAILURE;
	}
    }

    ruby_finalize_1();

    /* unlock again if finalizer took mutexes. */
    rb_threadptr_unlock_all_locking_mutexes(GET_THREAD());
    TH_POP_TAG();
    rb_thread_stop_timer_thread();
    ruby_vm_destruct(GET_VM());
    if (state) ruby_default_signal(state);

    return sysex;
}

static int
ruby_exec_internal(void *n)
{
    volatile int state;
    rb_iseq_t *iseq = (rb_iseq_t *)n;
    rb_thread_t *th = GET_THREAD();

    if (!n) return 0;

    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	SAVE_ROOT_JMPBUF(th, {
	    rb_iseq_eval_main(iseq);
	});
    }
    TH_POP_TAG();
    return state;
}

/*! Calls ruby_cleanup() and exits the process */
void
ruby_stop(int ex)
{
    exit(ruby_cleanup(ex));
}

/*! Checks the return value of ruby_options().
 * @param n return value of ruby_options().
 * @param status pointer to the exit status of this process.
 *
 * ruby_options() sometimes returns a special value to indicate this process
 * should immediately exit. This function checks if the case. Also stores the
 * exit status that the caller have to pass to exit(3) into
 * <code>*status</code>.
 *
 * @retval non-zero if the given opaque pointer is actually a compiled source.
 * @retval 0 if the given value is such a special value.
 */
int
ruby_executable_node(void *n, int *status)
{
    VALUE v = (VALUE)n;
    int s;

    switch (v) {
      case Qtrue:  s = EXIT_SUCCESS; break;
      case Qfalse: s = EXIT_FAILURE; break;
      default:
	if (!FIXNUM_P(v)) return TRUE;
	s = FIX2INT(v);
    }
    if (status) *status = s;
    return FALSE;
}

/*! Runs the given compiled source and exits this process.
 * @retval 0 if successfully run the source
 * @retval non-zero if an error occurred.
*/
int
ruby_run_node(void *n)
{
    int status;
    if (!ruby_executable_node(n, &status)) {
	ruby_cleanup(0);
	return status;
    }
    return ruby_cleanup(ruby_exec_node(n));
}

/*! Runs the given compiled source */
int
ruby_exec_node(void *n)
{
    ruby_init_stack((void *)&n);
    return ruby_exec_internal(n);
}

/*
 *  call-seq:
 *     Module.nesting    -> array
 *
 *  Returns the list of +Modules+ nested at the point of call.
 *
 *     module M1
 *       module M2
 *         $a = Module.nesting
 *       end
 *     end
 *     $a           #=> [M1::M2, M1]
 *     $a[0].name   #=> "M1::M2"
 */

static VALUE
rb_mod_nesting(void)
{
    VALUE ary = rb_ary_new();
    const rb_cref_t *cref = rb_vm_cref();

    while (cref && CREF_NEXT(cref)) {
	VALUE klass = CREF_CLASS(cref);
	if (!CREF_PUSHED_BY_EVAL(cref) &&
	    !NIL_P(klass)) {
	    rb_ary_push(ary, klass);
	}
	cref = CREF_NEXT(cref);
    }
    return ary;
}

/*
 *  call-seq:
 *     Module.constants   -> array
 *     Module.constants(inherited)   -> array
 *
 *  In the first form, returns an array of the names of all
 *  constants accessible from the point of call.
 *  This list includes the names of all modules and classes
 *  defined in the global scope.
 *
 *     Module.constants.first(4)
 *        # => [:ARGF, :ARGV, :ArgumentError, :Array]
 *
 *     Module.constants.include?(:SEEK_SET)   # => false
 *
 *     class IO
 *       Module.constants.include?(:SEEK_SET) # => true
 *     end
 *
 *  The second form calls the instance method +constants+.
 */

static VALUE
rb_mod_s_constants(int argc, VALUE *argv, VALUE mod)
{
    const rb_cref_t *cref = rb_vm_cref();
    VALUE klass;
    VALUE cbase = 0;
    void *data = 0;

    if (argc > 0 || mod != rb_cModule) {
	return rb_mod_constants(argc, argv, mod);
    }

    while (cref) {
	klass = CREF_CLASS(cref);
	if (!CREF_PUSHED_BY_EVAL(cref) &&
	    !NIL_P(klass)) {
	    data = rb_mod_const_at(CREF_CLASS(cref), data);
	    if (!cbase) {
		cbase = klass;
	    }
	}
	cref = CREF_NEXT(cref);
    }

    if (cbase) {
	data = rb_mod_const_of(cbase, data);
    }
    return rb_const_list(data);
}

void
rb_frozen_class_p(VALUE klass)
{
    if (SPECIAL_CONST_P(klass)) {
      noclass:
	Check_Type(klass, T_CLASS);
    }
    if (OBJ_FROZEN(klass)) {
	const char *desc;

	if (FL_TEST(klass, FL_SINGLETON)) {
	    desc = "object";
	    klass = rb_ivar_get(klass, id__attached__);
	    if (!SPECIAL_CONST_P(klass)) {
		switch (BUILTIN_TYPE(klass)) {
		  case T_MODULE:
		  case T_ICLASS:
		    desc = "Module";
		    break;
		  case T_CLASS:
		    desc = "Class";
		    break;
		}
	    }
	}
	else {
	    switch (BUILTIN_TYPE(klass)) {
	      case T_MODULE:
	      case T_ICLASS:
		desc = "module";
		break;
	      case T_CLASS:
		desc = "class";
		break;
	      default:
		goto noclass;
	    }
	}
	rb_error_frozen(desc);
    }
}

NORETURN(static void rb_longjmp(int, volatile VALUE, VALUE));
static VALUE get_errinfo(void);
static VALUE get_thread_errinfo(rb_thread_t *th);

static VALUE
exc_setup_cause(VALUE exc, VALUE cause)
{
#if SUPPORT_JOKE
    if (NIL_P(cause)) {
	ID id_true_cause;
	CONST_ID(id_true_cause, "true_cause");

	cause = rb_attr_get(rb_eFatal, id_true_cause);
	if (NIL_P(cause)) {
	    cause = rb_exc_new_cstr(rb_eFatal, "because using such Ruby");
	    rb_ivar_set(cause, id_cause, INT2FIX(42)); /* the answer */
	    OBJ_FREEZE(cause);
	    rb_ivar_set(rb_eFatal, id_true_cause, cause);
	}
    }
#endif
    if (!NIL_P(cause) && cause != exc) {
	rb_ivar_set(exc, id_cause, cause);
    }
    return exc;
}

static inline int
sysstack_error_p(VALUE exc)
{
    return exc == sysstack_error || (!SPECIAL_CONST_P(exc) && RBASIC_CLASS(exc) == rb_eSysStackError);
}

static void
setup_exception(rb_thread_t *th, int tag, volatile VALUE mesg, VALUE cause)
{
    VALUE e;
    const char *file = 0;
    int line;
    int nocause = 0;

    if (NIL_P(mesg)) {
	mesg = th->errinfo;
	if (INTERNAL_EXCEPTION_P(mesg)) TH_JUMP_TAG(th, TAG_FATAL);
	nocause = 1;
    }
    if (NIL_P(mesg)) {
	mesg = rb_exc_new(rb_eRuntimeError, 0, 0);
	nocause = 0;
    }
    if (cause != Qundef) {
	exc_setup_cause(mesg, cause);
    }
    else if (nocause) {
	exc_setup_cause(mesg, Qnil);
    }
    else if (!rb_ivar_defined(mesg, id_cause)) {
	exc_setup_cause(mesg, get_thread_errinfo(th));
    }

    file = rb_source_loc(&line);
    if (file && !NIL_P(mesg)) {
	VALUE at;
	if (sysstack_error_p(mesg)) {
	    if (NIL_P(rb_attr_get(mesg, idBt))) {
		at = rb_vm_backtrace_object();
		if (mesg == sysstack_error) {
		    mesg = ruby_vm_sysstack_error_copy();
		}
		rb_ivar_set(mesg, idBt, at);
		rb_ivar_set(mesg, idBt_locations, at);
	    }
	}
	else if (NIL_P(get_backtrace(mesg))) {
	    at = rb_vm_backtrace_object();
	    if (OBJ_FROZEN(mesg)) {
		mesg = rb_obj_dup(mesg);
	    }
	    rb_ivar_set(mesg, idBt_locations, at);
	    set_backtrace(mesg, at);
	}
    }

    if (!NIL_P(mesg)) {
	th->errinfo = mesg;
    }

    if (RTEST(ruby_debug) && !NIL_P(e = th->errinfo) &&
	!rb_obj_is_kind_of(e, rb_eSystemExit)) {
	int status;

	mesg = e;
	TH_PUSH_TAG(th);
	if ((status = EXEC_TAG()) == 0) {
	    th->errinfo = Qnil;
	    e = rb_obj_as_string(mesg);
	    th->errinfo = mesg;
	    if (file && line) {
		e = rb_sprintf("Exception `%"PRIsVALUE"' at %s:%d - %"PRIsVALUE"\n",
			       rb_obj_class(mesg), file, line, e);
	    }
	    else if (file) {
		e = rb_sprintf("Exception `%"PRIsVALUE"' at %s - %"PRIsVALUE"\n",
			       rb_obj_class(mesg), file, e);
	    }
	    else {
		e = rb_sprintf("Exception `%"PRIsVALUE"' - %"PRIsVALUE"\n",
			       rb_obj_class(mesg), e);
	    }
	    warn_print_str(e);
	}
	TH_POP_TAG();
	if (status == TAG_FATAL && th->errinfo == exception_error) {
	    th->errinfo = mesg;
	}
	else if (status) {
	    rb_threadptr_reset_raised(th);
	    TH_JUMP_TAG(th, status);
	}
    }

    if (rb_threadptr_set_raised(th)) {
	th->errinfo = exception_error;
	rb_threadptr_reset_raised(th);
	TH_JUMP_TAG(th, TAG_FATAL);
    }

    if (tag != TAG_FATAL) {
	RUBY_DTRACE_HOOK(RAISE, rb_obj_classname(th->errinfo));
	EXEC_EVENT_HOOK(th, RUBY_EVENT_RAISE, th->cfp->self, 0, 0, mesg);
    }
}

static void
rb_longjmp(int tag, volatile VALUE mesg, VALUE cause)
{
    rb_thread_t *th = GET_THREAD();
    setup_exception(th, tag, mesg, cause);
    rb_thread_raised_clear(th);
    TH_JUMP_TAG(th, tag);
}

static VALUE make_exception(int argc, const VALUE *argv, int isstr);

void
rb_exc_raise(VALUE mesg)
{
    if (!NIL_P(mesg)) {
	mesg = make_exception(1, &mesg, FALSE);
    }
    rb_longjmp(TAG_RAISE, mesg, Qundef);
}

void
rb_exc_fatal(VALUE mesg)
{
    if (!NIL_P(mesg)) {
	mesg = make_exception(1, &mesg, FALSE);
    }
    rb_longjmp(TAG_FATAL, mesg, Qnil);
}

void
rb_interrupt(void)
{
    rb_raise(rb_eInterrupt, "%s", "");
}

enum {raise_opt_cause, raise_max_opt};

static int
extract_raise_opts(int argc, const VALUE *argv, VALUE *opts)
{
    int i;
    if (argc > 0) {
	VALUE opt = argv[argc-1];
	if (RB_TYPE_P(opt, T_HASH)) {
	    if (!RHASH_EMPTY_P(opt)) {
		ID keywords[1];
		CONST_ID(keywords[0], "cause");
		rb_get_kwargs(opt, keywords, 0, -1-raise_max_opt, opts);
		if (RHASH_EMPTY_P(opt)) --argc;
		return argc;
	    }
	}
    }
    for (i = 0; i < raise_max_opt; ++i) {
	opts[i] = Qundef;
    }
    return argc;
}

/*
 *  call-seq:
 *     raise
 *     raise(string)
 *     raise(exception [, string [, array]])
 *     fail
 *     fail(string)
 *     fail(exception [, string [, array]])
 *
 *  With no arguments, raises the exception in <code>$!</code> or raises
 *  a <code>RuntimeError</code> if <code>$!</code> is +nil+.
 *  With a single +String+ argument, raises a
 *  +RuntimeError+ with the string as a message. Otherwise,
 *  the first parameter should be the name of an +Exception+
 *  class (or an object that returns an +Exception+ object when sent
 *  an +exception+ message). The optional second parameter sets the
 *  message associated with the exception, and the third parameter is an
 *  array of callback information. Exceptions are caught by the
 *  +rescue+ clause of <code>begin...end</code> blocks.
 *
 *     raise "Failed to create socket"
 *     raise ArgumentError, "No parameters", caller
 */

static VALUE
rb_f_raise(int argc, VALUE *argv)
{
    VALUE err;
    VALUE opts[raise_max_opt], *const cause = &opts[raise_opt_cause];

    argc = extract_raise_opts(argc, argv, opts);
    if (argc == 0) {
	if (*cause != Qundef) {
	    rb_raise(rb_eArgError, "only cause is given with no arguments");
	}
	err = get_errinfo();
	if (!NIL_P(err)) {
	    argc = 1;
	    argv = &err;
	}
    }
    rb_raise_jump(rb_make_exception(argc, argv), *cause);

    UNREACHABLE;
}

static VALUE
make_exception(int argc, const VALUE *argv, int isstr)
{
    VALUE mesg, exc;
    int n;

    mesg = Qnil;
    switch (argc) {
      case 0:
	break;
      case 1:
	exc = argv[0];
	if (NIL_P(exc))
	    break;
	if (isstr) {
	    mesg = rb_check_string_type(exc);
	    if (!NIL_P(mesg)) {
		mesg = rb_exc_new3(rb_eRuntimeError, mesg);
		break;
	    }
	}
	n = 0;
	goto exception_call;

      case 2:
      case 3:
	exc = argv[0];
	n = 1;
      exception_call:
	if (sysstack_error_p(exc)) return exc;
	mesg = rb_check_funcall(exc, idException, n, argv+1);
	if (mesg == Qundef) {
	    rb_raise(rb_eTypeError, "exception class/object expected");
	}
	break;
      default:
	rb_check_arity(argc, 0, 3);
	break;
    }
    if (argc > 0) {
	if (!rb_obj_is_kind_of(mesg, rb_eException))
	    rb_raise(rb_eTypeError, "exception object expected");
	if (argc > 2)
	    set_backtrace(mesg, argv[2]);
    }

    return mesg;
}

VALUE
rb_make_exception(int argc, const VALUE *argv)
{
    return make_exception(argc, argv, TRUE);
}

void
rb_raise_jump(VALUE mesg, VALUE cause)
{
    rb_thread_t *th = GET_THREAD();
    const rb_control_frame_t *cfp = th->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
    VALUE klass = me->owner;
    VALUE self = cfp->self;
    ID mid = me->called_id;

    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, self, mid, klass, Qnil);

    setup_exception(th, TAG_RAISE, mesg, cause);

    rb_thread_raised_clear(th);
    TH_JUMP_TAG(th, TAG_RAISE);
}

void
rb_jump_tag(int tag)
{
    if (UNLIKELY(tag < TAG_RETURN || tag > TAG_FATAL)) {
	unknown_longjmp_status(tag);
    }
    JUMP_TAG(tag);
}

int
rb_block_given_p(void)
{
    rb_thread_t *th = GET_THREAD();

    if (rb_vm_control_frame_block_ptr(th->cfp)) {
	return TRUE;
    }
    else {
	return FALSE;
    }
}

int
rb_iterator_p(void)
{
    return rb_block_given_p();
}

VALUE rb_eThreadError;

void
rb_need_block(void)
{
    if (!rb_block_given_p()) {
	rb_vm_localjump_error("no block given", Qnil, 0);
    }
}

VALUE
rb_rescue2(VALUE (* b_proc) (ANYARGS), VALUE data1,
	   VALUE (* r_proc) (ANYARGS), VALUE data2, ...)
{
    int state;
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    volatile VALUE result = Qfalse;
    volatile VALUE e_info = th->errinfo;
    va_list args;

    TH_PUSH_TAG(th);
    if ((state = TH_EXEC_TAG()) == 0) {
      retry_entry:
	result = (*b_proc) (data1);
    }
    else if (result) {
	/* escape from r_proc */
	if (state == TAG_RETRY) {
	    state = 0;
	    th->errinfo = Qnil;
	    result = Qfalse;
	    goto retry_entry;
	}
    }
    else {
	rb_vm_rewind_cfp(th, cfp);

	if (state == TAG_RAISE) {
	    int handle = FALSE;
	    VALUE eclass;

	    va_init_list(args, data2);
	    while ((eclass = va_arg(args, VALUE)) != 0) {
		if (rb_obj_is_kind_of(th->errinfo, eclass)) {
		    handle = TRUE;
		    break;
		}
	    }
	    va_end(args);

	    if (handle) {
		result = Qnil;
		state = 0;
		if (r_proc) {
		    result = (*r_proc) (data2, th->errinfo);
		}
		th->errinfo = e_info;
	    }
	}
    }
    TH_POP_TAG();
    if (state)
	TH_JUMP_TAG(th, state);

    return result;
}

VALUE
rb_rescue(VALUE (* b_proc)(ANYARGS), VALUE data1,
	  VALUE (* r_proc)(ANYARGS), VALUE data2)
{
    return rb_rescue2(b_proc, data1, r_proc, data2, rb_eStandardError,
		      (VALUE)0);
}

VALUE
rb_protect(VALUE (* proc) (VALUE), VALUE data, int * state)
{
    volatile VALUE result = Qnil;
    volatile int status;
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    struct rb_vm_protect_tag protect_tag;
    rb_jmpbuf_t org_jmpbuf;

    protect_tag.prev = th->protect_tag;

    TH_PUSH_TAG(th);
    th->protect_tag = &protect_tag;
    MEMCPY(&org_jmpbuf, &(th)->root_jmpbuf, rb_jmpbuf_t, 1);
    if ((status = TH_EXEC_TAG()) == 0) {
	SAVE_ROOT_JMPBUF(th, result = (*proc) (data));
    }
    else {
	rb_vm_rewind_cfp(th, cfp);
    }
    MEMCPY(&(th)->root_jmpbuf, &org_jmpbuf, rb_jmpbuf_t, 1);
    th->protect_tag = protect_tag.prev;
    TH_POP_TAG();

    if (state) {
	*state = status;
    }

    return result;
}

VALUE
rb_ensure(VALUE (*b_proc)(ANYARGS), VALUE data1, VALUE (*e_proc)(ANYARGS), VALUE data2)
{
    int state;
    volatile VALUE result = Qnil;
    volatile VALUE errinfo;
    rb_thread_t *const th = GET_THREAD();
    rb_ensure_list_t ensure_list;
    ensure_list.entry.marker = 0;
    ensure_list.entry.e_proc = e_proc;
    ensure_list.entry.data2 = data2;
    ensure_list.next = th->ensure_list;
    th->ensure_list = &ensure_list;
    TH_PUSH_TAG(th);
    if ((state = EXEC_TAG()) == 0) {
	result = (*b_proc) (data1);
    }
    TH_POP_TAG();
    errinfo = th->errinfo;
    th->ensure_list=ensure_list.next;
    (*ensure_list.entry.e_proc)(ensure_list.entry.data2);
    th->errinfo = errinfo;
    if (state)
	TH_JUMP_TAG(th, state);
    return result;
}

static ID
frame_func_id(rb_control_frame_t *cfp)
{
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    if (me) {
	return me->def->original_id;
    }
    else {
	return 0;
    }
}

static ID
frame_called_id(rb_control_frame_t *cfp)
{
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);

    if (me) {
	return me->called_id;
    }
    else {
	return 0;
    }
}

ID
rb_frame_this_func(void)
{
    return frame_func_id(GET_THREAD()->cfp);
}

ID
rb_frame_callee(void)
{
    return frame_called_id(GET_THREAD()->cfp);
}

static rb_control_frame_t *
previous_frame(rb_thread_t *th)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);
    /* check if prev_cfp can be accessible */
    if ((void *)(th->stack + th->stack_size) == (void *)(prev_cfp)) {
        return 0;
    }
    return prev_cfp;
}

static ID
prev_frame_callee(void)
{
    rb_control_frame_t *prev_cfp = previous_frame(GET_THREAD());
    if (!prev_cfp) return 0;
    return frame_called_id(prev_cfp);
}

static ID
prev_frame_func(void)
{
    rb_control_frame_t *prev_cfp = previous_frame(GET_THREAD());
    if (!prev_cfp) return 0;
    return frame_func_id(prev_cfp);
}

ID
rb_frame_last_func(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = th->cfp;
    ID mid;

    while (!(mid = frame_func_id(cfp)) &&
	   (cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp),
	    !RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)));
    return mid;
}

/*
 *  call-seq:
 *     append_features(mod)   -> mod
 *
 *  When this module is included in another, Ruby calls
 *  <code>append_features</code> in this module, passing it the
 *  receiving module in _mod_. Ruby's default implementation is
 *  to add the constants, methods, and module variables of this module
 *  to _mod_ if this module has not already been added to
 *  _mod_ or one of its ancestors. See also <code>Module#include</code>.
 */

static VALUE
rb_mod_append_features(VALUE module, VALUE include)
{
    if (!CLASS_OR_MODULE_P(include)) {
	Check_Type(include, T_CLASS);
    }
    rb_include_module(include, module);

    return module;
}

/*
 *  call-seq:
 *     include(module, ...)    -> self
 *
 *  Invokes <code>Module.append_features</code> on each parameter in reverse order.
 */

static VALUE
rb_mod_include(int argc, VALUE *argv, VALUE module)
{
    int i;
    ID id_append_features, id_included;

    CONST_ID(id_append_features, "append_features");
    CONST_ID(id_included, "included");

    for (i = 0; i < argc; i++)
	Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], id_append_features, 1, module);
	rb_funcall(argv[argc], id_included, 1, module);
    }
    return module;
}

/*
 *  call-seq:
 *     prepend_features(mod)   -> mod
 *
 *  When this module is prepended in another, Ruby calls
 *  <code>prepend_features</code> in this module, passing it the
 *  receiving module in _mod_. Ruby's default implementation is
 *  to overlay the constants, methods, and module variables of this module
 *  to _mod_ if this module has not already been added to
 *  _mod_ or one of its ancestors. See also <code>Module#prepend</code>.
 */

static VALUE
rb_mod_prepend_features(VALUE module, VALUE prepend)
{
    if (!CLASS_OR_MODULE_P(prepend)) {
	Check_Type(prepend, T_CLASS);
    }
    rb_prepend_module(prepend, module);

    return module;
}

/*
 *  call-seq:
 *     prepend(module, ...)    -> self
 *
 *  Invokes <code>Module.prepend_features</code> on each parameter in reverse order.
 */

static VALUE
rb_mod_prepend(int argc, VALUE *argv, VALUE module)
{
    int i;
    ID id_prepend_features, id_prepended;

    CONST_ID(id_prepend_features, "prepend_features");
    CONST_ID(id_prepended, "prepended");
    for (i = 0; i < argc; i++)
	Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], id_prepend_features, 1, module);
	rb_funcall(argv[argc], id_prepended, 1, module);
    }
    return module;
}

static VALUE
hidden_identity_hash_new(void)
{
    VALUE hash = rb_ident_hash_new();

    RBASIC_CLEAR_CLASS(hash); /* hide from ObjectSpace */
    return hash;
}

void
rb_using_refinement(rb_cref_t *cref, VALUE klass, VALUE module)
{
    VALUE iclass, c, superclass = klass;

    Check_Type(klass, T_CLASS);
    Check_Type(module, T_MODULE);
    if (NIL_P(CREF_REFINEMENTS(cref))) {
	CREF_REFINEMENTS_SET(cref, hidden_identity_hash_new());
    }
    else {
	if (CREF_OMOD_SHARED(cref)) {
	    CREF_REFINEMENTS_SET(cref, rb_hash_dup(CREF_REFINEMENTS(cref)));
	    CREF_OMOD_SHARED_UNSET(cref);
	}
	if (!NIL_P(c = rb_hash_lookup(CREF_REFINEMENTS(cref), klass))) {
	    superclass = c;
	    while (c && RB_TYPE_P(c, T_ICLASS)) {
		if (RBASIC(c)->klass == module) {
		    /* already used refinement */
		    return;
		}
		c = RCLASS_SUPER(c);
	    }
	}
    }
    FL_SET(module, RMODULE_IS_OVERLAID);
    c = iclass = rb_include_class_new(module, superclass);
    RCLASS_REFINED_CLASS(c) = klass;

    RCLASS_M_TBL(OBJ_WB_UNPROTECT(c)) =
      RCLASS_M_TBL(OBJ_WB_UNPROTECT(module)); /* TODO: check unprotecting */

    module = RCLASS_SUPER(module);
    while (module && module != klass) {
	FL_SET(module, RMODULE_IS_OVERLAID);
	c = RCLASS_SET_SUPER(c, rb_include_class_new(module, RCLASS_SUPER(c)));
	RCLASS_REFINED_CLASS(c) = klass;
	module = RCLASS_SUPER(module);
    }
    rb_hash_aset(CREF_REFINEMENTS(cref), klass, iclass);
}

static int
using_refinement(VALUE klass, VALUE module, VALUE arg)
{
    rb_cref_t *cref = (rb_cref_t *) arg;

    rb_using_refinement(cref, klass, module);
    return ST_CONTINUE;
}

static void
using_module_recursive(const rb_cref_t *cref, VALUE klass)
{
    ID id_refinements;
    VALUE super, module, refinements;

    super = RCLASS_SUPER(klass);
    if (super) {
	using_module_recursive(cref, super);
    }
    switch (BUILTIN_TYPE(klass)) {
      case T_MODULE:
	module = klass;
	break;

      case T_ICLASS:
	module = RBASIC(klass)->klass;
	break;

      default:
	rb_raise(rb_eTypeError, "wrong argument type %s (expected Module)",
		 rb_obj_classname(klass));
	break;
    }
    CONST_ID(id_refinements, "__refinements__");
    refinements = rb_attr_get(module, id_refinements);
    if (NIL_P(refinements)) return;
    rb_hash_foreach(refinements, using_refinement, (VALUE) cref);
}

void
rb_using_module(const rb_cref_t *cref, VALUE module)
{
    Check_Type(module, T_MODULE);
    using_module_recursive(cref, module);
    rb_clear_method_cache_by_class(rb_cObject);
}

VALUE
rb_refinement_module_get_refined_class(VALUE module)
{
    ID id_refined_class;

    CONST_ID(id_refined_class, "__refined_class__");
    return rb_attr_get(module, id_refined_class);
}

static void
add_activated_refinement(VALUE activated_refinements,
			 VALUE klass, VALUE refinement)
{
    VALUE iclass, c, superclass = klass;

    if (!NIL_P(c = rb_hash_lookup(activated_refinements, klass))) {
	superclass = c;
	while (c && RB_TYPE_P(c, T_ICLASS)) {
	    if (RBASIC(c)->klass == refinement) {
		/* already used refinement */
		return;
	    }
	    c = RCLASS_SUPER(c);
	}
    }
    FL_SET(refinement, RMODULE_IS_OVERLAID);
    c = iclass = rb_include_class_new(refinement, superclass);
    RCLASS_REFINED_CLASS(c) = klass;
    refinement = RCLASS_SUPER(refinement);
    while (refinement && refinement != klass) {
	FL_SET(refinement, RMODULE_IS_OVERLAID);
	c = RCLASS_SET_SUPER(c, rb_include_class_new(refinement, RCLASS_SUPER(c)));
	RCLASS_REFINED_CLASS(c) = klass;
	refinement = RCLASS_SUPER(refinement);
    }
    rb_hash_aset(activated_refinements, klass, iclass);
}

/*
 *  call-seq:
 *     refine(klass) { block }   -> module
 *
 *  Refine <i>klass</i> in the receiver.
 *
 *  Returns an overlaid module.
 */

static VALUE
rb_mod_refine(VALUE module, VALUE klass)
{
    VALUE refinement;
    ID id_refinements, id_activated_refinements,
       id_refined_class, id_defined_at;
    VALUE refinements, activated_refinements;
    rb_thread_t *th = GET_THREAD();
    rb_block_t *block = rb_vm_control_frame_block_ptr(th->cfp);

    if (!block) {
        rb_raise(rb_eArgError, "no block given");
    }
    if (block->proc) {
        rb_raise(rb_eArgError,
		 "can't pass a Proc as a block to Module#refine");
    }
    Check_Type(klass, T_CLASS);
    CONST_ID(id_refinements, "__refinements__");
    refinements = rb_attr_get(module, id_refinements);
    if (NIL_P(refinements)) {
	refinements = hidden_identity_hash_new();
	rb_ivar_set(module, id_refinements, refinements);
    }
    CONST_ID(id_activated_refinements, "__activated_refinements__");
    activated_refinements = rb_attr_get(module, id_activated_refinements);
    if (NIL_P(activated_refinements)) {
	activated_refinements = hidden_identity_hash_new();
	rb_ivar_set(module, id_activated_refinements,
		    activated_refinements);
    }
    refinement = rb_hash_lookup(refinements, klass);
    if (NIL_P(refinement)) {
	refinement = rb_module_new();
	RCLASS_SET_SUPER(refinement, klass);
	FL_SET(refinement, RMODULE_IS_REFINEMENT);
	CONST_ID(id_refined_class, "__refined_class__");
	rb_ivar_set(refinement, id_refined_class, klass);
	CONST_ID(id_defined_at, "__defined_at__");
	rb_ivar_set(refinement, id_defined_at, module);
	rb_hash_aset(refinements, klass, refinement);
	add_activated_refinement(activated_refinements, klass, refinement);
    }
    rb_yield_refine_block(refinement, activated_refinements);
    return refinement;
}

static void
ignored_block(VALUE module, const char *klass)
{
    const char *anon = "";
    if (!RTEST(rb_search_class_path(module))) {
	anon = ", maybe for Module.new";
    }
    rb_warn("%s""using doesn't call the given block""%s.", klass, anon);
}

/*
 *  call-seq:
 *     using(module)    -> self
 *
 *  Import class refinements from <i>module</i> into the current class or
 *  module definition.
 */

static VALUE
mod_using(VALUE self, VALUE module)
{
    rb_control_frame_t *prev_cfp = previous_frame(GET_THREAD());

    if (prev_frame_func()) {
	rb_raise(rb_eRuntimeError,
		 "Module#using is not permitted in methods");
    }
    if (prev_cfp && prev_cfp->self != self) {
	rb_raise(rb_eRuntimeError, "Module#using is not called on self");
    }
    if (rb_block_given_p()) {
	ignored_block(module, "Module#");
    }
    rb_using_module(rb_vm_cref_replace_with_duplicated_cref(), module);
    return self;
}

void
rb_obj_call_init(VALUE obj, int argc, const VALUE *argv)
{
    PASS_PASSED_BLOCK();
    rb_funcall2(obj, idInitialize, argc, argv);
}

void
rb_extend_object(VALUE obj, VALUE module)
{
    rb_include_module(rb_singleton_class(obj), module);
}

/*
 *  call-seq:
 *     extend_object(obj)    -> obj
 *
 *  Extends the specified object by adding this module's constants and
 *  methods (which are added as singleton methods). This is the callback
 *  method used by <code>Object#extend</code>.
 *
 *     module Picky
 *       def Picky.extend_object(o)
 *         if String === o
 *           puts "Can't add Picky to a String"
 *         else
 *           puts "Picky added to #{o.class}"
 *           super
 *         end
 *       end
 *     end
 *     (s = Array.new).extend Picky  # Call Object.extend
 *     (s = "quick brown fox").extend Picky
 *
 *  <em>produces:</em>
 *
 *     Picky added to Array
 *     Can't add Picky to a String
 */

static VALUE
rb_mod_extend_object(VALUE mod, VALUE obj)
{
    rb_extend_object(obj, mod);
    return obj;
}

/*
 *  call-seq:
 *     obj.extend(module, ...)    -> obj
 *
 *  Adds to _obj_ the instance methods from each module given as a
 *  parameter.
 *
 *     module Mod
 *       def hello
 *         "Hello from Mod.\n"
 *       end
 *     end
 *
 *     class Klass
 *       def hello
 *         "Hello from Klass.\n"
 *       end
 *     end
 *
 *     k = Klass.new
 *     k.hello         #=> "Hello from Klass.\n"
 *     k.extend(Mod)   #=> #<Klass:0x401b3bc8>
 *     k.hello         #=> "Hello from Mod.\n"
 */

static VALUE
rb_obj_extend(int argc, VALUE *argv, VALUE obj)
{
    int i;
    ID id_extend_object, id_extended;

    CONST_ID(id_extend_object, "extend_object");
    CONST_ID(id_extended, "extended");

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    for (i = 0; i < argc; i++)
	Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], id_extend_object, 1, obj);
	rb_funcall(argv[argc], id_extended, 1, obj);
    }
    return obj;
}

/*
 *  call-seq:
 *     include(module, ...)   -> self
 *
 *  Invokes <code>Module.append_features</code>
 *  on each parameter in turn. Effectively adds the methods and constants
 *  in each module to the receiver.
 */

static VALUE
top_include(int argc, VALUE *argv, VALUE self)
{
    rb_thread_t *th = GET_THREAD();

    if (th->top_wrapper) {
	rb_warning("main.include in the wrapped load is effective only in wrapper module");
	return rb_mod_include(argc, argv, th->top_wrapper);
    }
    return rb_mod_include(argc, argv, rb_cObject);
}

/*
 *  call-seq:
 *     using(module)    -> self
 *
 *  Import class refinements from <i>module</i> into the scope where
 *  <code>using</code> is called.
 */

static VALUE
top_using(VALUE self, VALUE module)
{
    const rb_cref_t *cref = rb_vm_cref();
    rb_control_frame_t *prev_cfp = previous_frame(GET_THREAD());

    if (CREF_NEXT(cref) || (prev_cfp && rb_vm_frame_method_entry(prev_cfp))) {
	rb_raise(rb_eRuntimeError, "main.using is permitted only at toplevel");
    }
    if (rb_block_given_p()) {
	ignored_block(module, "main.");
    }
    rb_using_module(rb_vm_cref_replace_with_duplicated_cref(), module);
    return self;
}

static VALUE *
errinfo_place(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    rb_control_frame_t *end_cfp = RUBY_VM_END_CONTROL_FRAME(th);

    while (RUBY_VM_VALID_CONTROL_FRAME_P(cfp, end_cfp)) {
	if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	    if (cfp->iseq->body->type == ISEQ_TYPE_RESCUE) {
		return &cfp->ep[-2];
	    }
	    else if (cfp->iseq->body->type == ISEQ_TYPE_ENSURE &&
		     !THROW_DATA_P(cfp->ep[-2]) &&
		     !FIXNUM_P(cfp->ep[-2])) {
		return &cfp->ep[-2];
	    }
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

static VALUE
get_thread_errinfo(rb_thread_t *th)
{
    VALUE *ptr = errinfo_place(th);
    if (ptr) {
	return *ptr;
    }
    else {
	return th->errinfo;
    }
}

static VALUE
get_errinfo(void)
{
    return get_thread_errinfo(GET_THREAD());
}

static VALUE
errinfo_getter(ID id)
{
    return get_errinfo();
}

#if 0
static void
errinfo_setter(VALUE val, ID id, VALUE *var)
{
    if (!NIL_P(val) && !rb_obj_is_kind_of(val, rb_eException)) {
	rb_raise(rb_eTypeError, "assigning non-exception to $!");
    }
    else {
	VALUE *ptr = errinfo_place(GET_THREAD());
	if (ptr) {
	    *ptr = val;
	}
	else {
	    rb_raise(rb_eRuntimeError, "errinfo_setter: not in rescue clause.");
	}
    }
}
#endif

VALUE
rb_errinfo(void)
{
    rb_thread_t *th = GET_THREAD();
    return th->errinfo;
}

void
rb_set_errinfo(VALUE err)
{
    if (!NIL_P(err) && !rb_obj_is_kind_of(err, rb_eException)) {
	rb_raise(rb_eTypeError, "assigning non-exception to $!");
    }
    GET_THREAD()->errinfo = err;
}

VALUE
rb_rubylevel_errinfo(void)
{
    return get_errinfo();
}

static VALUE
errat_getter(ID id)
{
    VALUE err = get_errinfo();
    if (!NIL_P(err)) {
	return get_backtrace(err);
    }
    else {
	return Qnil;
    }
}

static void
errat_setter(VALUE val, ID id, VALUE *var)
{
    VALUE err = get_errinfo();
    if (NIL_P(err)) {
	rb_raise(rb_eArgError, "$! not set");
    }
    set_backtrace(err, val);
}

/*
 *  call-seq:
 *     __method__         -> symbol
 *
 *  Returns the name at the definition of the current method as a
 *  Symbol.
 *  If called outside of a method, it returns <code>nil</code>.
 *
 */

static VALUE
rb_f_method_name(void)
{
    ID fname = prev_frame_func(); /* need *method* ID */

    if (fname) {
	return ID2SYM(fname);
    }
    else {
	return Qnil;
    }
}

/*
 *  call-seq:
 *     __callee__         -> symbol
 *
 *  Returns the called name of the current method as a Symbol.
 *  If called outside of a method, it returns <code>nil</code>.
 *
 */

static VALUE
rb_f_callee_name(void)
{
    ID fname = prev_frame_callee(); /* need *callee* ID */

    if (fname) {
	return ID2SYM(fname);
    }
    else {
	return Qnil;
    }
}

/*
 *  call-seq:
 *     __dir__         -> string
 *
 *  Returns the canonicalized absolute path of the directory of the file from
 *  which this method is called. It means symlinks in the path is resolved.
 *  If <code>__FILE__</code> is <code>nil</code>, it returns <code>nil</code>.
 *  The return value equals to <code>File.dirname(File.realpath(__FILE__))</code>.
 *
 */
static VALUE
f_current_dirname(void)
{
    VALUE base = rb_current_realfilepath();
    if (NIL_P(base)) {
	return Qnil;
    }
    base = rb_file_dirname(base);
    return base;
}

void
Init_eval(void)
{
    rb_define_virtual_variable("$@", errat_getter, errat_setter);
    rb_define_virtual_variable("$!", errinfo_getter, 0);

    rb_define_global_function("raise", rb_f_raise, -1);
    rb_define_global_function("fail", rb_f_raise, -1);

    rb_define_global_function("global_variables", rb_f_global_variables, 0);	/* in variable.c */

    rb_define_global_function("__method__", rb_f_method_name, 0);
    rb_define_global_function("__callee__", rb_f_callee_name, 0);
    rb_define_global_function("__dir__", f_current_dirname, 0);

    rb_define_method(rb_cModule, "include", rb_mod_include, -1);
    rb_define_method(rb_cModule, "prepend", rb_mod_prepend, -1);

    rb_define_private_method(rb_cModule, "append_features", rb_mod_append_features, 1);
    rb_define_private_method(rb_cModule, "extend_object", rb_mod_extend_object, 1);
    rb_define_private_method(rb_cModule, "prepend_features", rb_mod_prepend_features, 1);
    rb_define_private_method(rb_cModule, "refine", rb_mod_refine, 1);
    rb_define_private_method(rb_cModule, "using", mod_using, 1);
    rb_undef_method(rb_cClass, "refine");

    rb_undef_method(rb_cClass, "module_function");

    Init_vm_eval();
    Init_eval_method();

    rb_define_singleton_method(rb_cModule, "nesting", rb_mod_nesting, 0);
    rb_define_singleton_method(rb_cModule, "constants", rb_mod_s_constants, -1);

    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
			     "include", top_include, -1);
    rb_define_private_method(rb_singleton_class(rb_vm_top_self()),
			     "using", top_using, 1);

    rb_define_method(rb_mKernel, "extend", rb_obj_extend, -1);

    rb_define_global_function("trace_var", rb_f_trace_var, -1);	/* in variable.c */
    rb_define_global_function("untrace_var", rb_f_untrace_var, -1);	/* in variable.c */

    rb_vm_register_special_exception(ruby_error_reenter, rb_eFatal, "exception reentered");

    id_signo = rb_intern_const("signo");
    id_status = rb_intern_const("status");
    id_cause = rb_intern_const("cause");
}
