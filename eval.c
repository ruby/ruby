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
#include "mjit.h"
#include "probes.h"
#include "probes_helper.h"
#ifdef HAVE_SYS_PRCTL_H
#include <sys/prctl.h>
#endif

NORETURN(void rb_raise_jump(VALUE, VALUE));
void rb_ec_clear_current_thread_trace_func(const rb_execution_context_t *ec);

static int rb_ec_cleanup(rb_execution_context_t *ec, volatile int ex);
static int rb_ec_exec_node(rb_execution_context_t *ec, void *n);

VALUE rb_eLocalJumpError;
VALUE rb_eSysStackError;

ID ruby_static_id_signo, ruby_static_id_status;
extern ID ruby_static_id_cause;
#define id_cause ruby_static_id_cause

#define exception_error GET_VM()->special_exceptions[ruby_error_reenter]

#include "eval_error.c"
#include "eval_jump.c"

#define CLASS_OR_MODULE_P(obj) \
    (!SPECIAL_CONST_P(obj) && \
     (BUILTIN_TYPE(obj) == T_CLASS || BUILTIN_TYPE(obj) == T_MODULE))

/*!
 * Initializes the VM and builtin libraries.
 * @retval 0 if succeeded.
 * @retval non-zero an error occurred.
 */
int
ruby_setup(void)
{
    enum ruby_tag_type state;

    if (GET_VM())
	return 0;

    ruby_init_stack((void *)&state);

    /*
     * Disable THP early before mallocs happen because we want this to
     * affect as many future pages as possible for CoW-friendliness
     */
#if defined(__linux__) && defined(PR_SET_THP_DISABLE)
    prctl(PR_SET_THP_DISABLE, 1, 0, 0, 0);
#endif
    Init_BareVM();
    Init_heap();
    rb_vm_encoded_insn_data_table_init();
    Init_vm_objects();

    EC_PUSH_TAG(GET_EC());
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	rb_call_inits();
	ruby_prog_init();
	GET_VM()->running = 1;
    }
    EC_POP_TAG();

    return state;
}

/*!
 * Calls ruby_setup() and check error.
 *
 * Prints errors and calls exit(3) if an error occurred.
 */
void
ruby_init(void)
{
    int state = ruby_setup();
    if (state) {
        if (RTEST(ruby_debug))
            error_print(GET_EC());
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
    rb_execution_context_t *ec = GET_EC();
    enum ruby_tag_type state;
    void *volatile iseq = 0;

    ruby_init_stack((void *)&iseq);
    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	SAVE_ROOT_JMPBUF(GET_THREAD(), iseq = ruby_process_options(argc, argv));
    }
    else {
        rb_ec_clear_current_thread_trace_func(ec);
        state = error_handle(ec, state);
	iseq = (void *)INT2FIX(state);
    }
    EC_POP_TAG();
    return iseq;
}

static void
rb_ec_teardown(rb_execution_context_t *ec)
{
    EC_PUSH_TAG(ec);
    if (EC_EXEC_TAG() == TAG_NONE) {
        rb_vm_trap_exit(rb_ec_vm_ptr(ec));
    }
    EC_POP_TAG();
    rb_ec_exec_end_proc(ec);
    rb_ec_clear_current_thread_trace_func(ec);
}

static void
rb_ec_finalize(rb_execution_context_t *ec)
{
    ruby_sig_finalize();
    ec->errinfo = Qnil;
    rb_objspace_call_finalizer(rb_ec_vm_ptr(ec)->objspace);
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
    rb_execution_context_t *ec = GET_EC();
    rb_ec_teardown(ec);
    rb_ec_finalize(ec);
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
    return rb_ec_cleanup(GET_EC(), ex);
}

static int
rb_ec_cleanup(rb_execution_context_t *ec, volatile int ex)
{
    int state;
    volatile VALUE errs[2] = { Qundef, Qundef };
    int nerr;
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    rb_thread_t *const volatile th0 = th;
    volatile int sysex = EXIT_SUCCESS;
    volatile int step = 0;

    rb_threadptr_interrupt(th);
    rb_threadptr_check_signal(th);
    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        th = th0;
        SAVE_ROOT_JMPBUF(th, { RUBY_VM_CHECK_INTS(ec); });

      step_0: step++;
        th = th0;
        errs[1] = ec->errinfo;
        if (THROW_DATA_P(ec->errinfo)) ec->errinfo = Qnil;
	rb_set_safe_level_force(0);
	ruby_init_stack(&errs[STACK_UPPER(errs, 0, 1)]);

        SAVE_ROOT_JMPBUF(th, rb_ec_teardown(ec));

      step_1: step++;
        th = th0;
	/* protect from Thread#raise */
	th->status = THREAD_KILLED;

        errs[0] = ec->errinfo;
	SAVE_ROOT_JMPBUF(th, rb_thread_terminate_all());
    }
    else {
	switch (step) {
	  case 0: goto step_0;
	  case 1: goto step_1;
	}
	if (ex == 0) ex = state;
    }
    th = th0;
    ec->errinfo = errs[1];
    sysex = error_handle(ec, ex);

    state = 0;
    for (nerr = 0; nerr < numberof(errs); ++nerr) {
	VALUE err = ATOMIC_VALUE_EXCHANGE(errs[nerr], Qnil);

	if (!RTEST(err)) continue;

        /* ec->errinfo contains a NODE while break'ing */
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

    mjit_finish(true); // We still need ISeqs here.

    rb_ec_finalize(ec);

    /* unlock again if finalizer took mutexes. */
    rb_threadptr_unlock_all_locking_mutexes(th);
    EC_POP_TAG();
    rb_thread_stop_timer_thread();
    ruby_vm_destruct(th->vm);
    if (state) ruby_default_signal(state);

    return sysex;
}

static int
rb_ec_exec_node(rb_execution_context_t *ec, void *n)
{
    volatile int state;
    rb_iseq_t *iseq = (rb_iseq_t *)n;
    if (!n) return 0;

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        rb_thread_t *const th = rb_ec_thread_ptr(ec);
	SAVE_ROOT_JMPBUF(th, {
	    rb_iseq_eval_main(iseq);
	});
    }
    EC_POP_TAG();
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
    rb_execution_context_t *ec = GET_EC();
    int status;
    if (!ruby_executable_node(n, &status)) {
        rb_ec_cleanup(ec, 0);
	return status;
    }
    ruby_init_stack((void *)&status);
    return rb_ec_cleanup(ec, rb_ec_exec_node(ec, n));
}

/*! Runs the given compiled source */
int
ruby_exec_node(void *n)
{
    ruby_init_stack((void *)&n);
    return rb_ec_exec_node(GET_EC(), n);
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
rb_mod_nesting(VALUE _)
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

/*!
 * Asserts that \a klass is not a frozen class.
 * \param[in] klass a \c Module object
 * \exception RuntimeError if \a klass is not a class or frozen.
 * \ingroup class
 */
void
rb_class_modify_check(VALUE klass)
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
        rb_frozen_error_raise(klass, "can't modify frozen %s: %"PRIsVALUE, desc, klass);
    }
}

NORETURN(static void rb_longjmp(rb_execution_context_t *, int, volatile VALUE, VALUE));
static VALUE get_errinfo(void);
static VALUE get_ec_errinfo(const rb_execution_context_t *ec);

static VALUE
exc_setup_cause(VALUE exc, VALUE cause)
{
#if OPT_SUPPORT_JOKE
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
	if (!rb_ivar_defined(cause, id_cause)) {
	    rb_ivar_set(cause, id_cause, Qnil);
	}
    }
    return exc;
}

static inline VALUE
exc_setup_message(const rb_execution_context_t *ec, VALUE mesg, VALUE *cause)
{
    int nocause = 0;
    int nocircular = 0;

    if (NIL_P(mesg)) {
	mesg = ec->errinfo;
	if (INTERNAL_EXCEPTION_P(mesg)) EC_JUMP_TAG(ec, TAG_FATAL);
	nocause = 1;
    }
    if (NIL_P(mesg)) {
	mesg = rb_exc_new(rb_eRuntimeError, 0, 0);
	nocause = 0;
        nocircular = 1;
    }
    if (*cause == Qundef) {
	if (nocause) {
	    *cause = Qnil;
            nocircular = 1;
	}
	else if (!rb_ivar_defined(mesg, id_cause)) {
	    *cause = get_ec_errinfo(ec);
	}
        else {
            nocircular = 1;
        }
    }
    else if (!NIL_P(*cause) && !rb_obj_is_kind_of(*cause, rb_eException)) {
        rb_raise(rb_eTypeError, "exception object expected");
    }

    if (!nocircular && !NIL_P(*cause) && *cause != Qundef && *cause != mesg) {
        VALUE c = *cause;
        while (!NIL_P(c = rb_attr_get(c, id_cause))) {
            if (c == mesg) {
                rb_raise(rb_eArgError, "circular causes");
            }
        }
    }
    return mesg;
}

static void
setup_exception(rb_execution_context_t *ec, int tag, volatile VALUE mesg, VALUE cause)
{
    VALUE e;
    int line;
    const char *file = rb_source_location_cstr(&line);
    const char *const volatile file0 = file;

    if ((file && !NIL_P(mesg)) || (cause != Qundef))  {
	volatile int state = 0;

	EC_PUSH_TAG(ec);
	if (EC_EXEC_TAG() == TAG_NONE && !(state = rb_ec_set_raised(ec))) {
	    VALUE bt = rb_get_backtrace(mesg);
	    if (!NIL_P(bt) || cause == Qundef) {
		if (OBJ_FROZEN(mesg)) {
		    mesg = rb_obj_dup(mesg);
		}
	    }
            if (cause != Qundef && !THROW_DATA_P(cause)) {
		exc_setup_cause(mesg, cause);
	    }
	    if (NIL_P(bt)) {
		VALUE at = rb_ec_backtrace_object(ec);
		rb_ivar_set(mesg, idBt_locations, at);
		set_backtrace(mesg, at);
	    }
	    rb_ec_reset_raised(ec);
	}
	EC_POP_TAG();
        file = file0;
	if (state) goto fatal;
    }

    if (!NIL_P(mesg)) {
	ec->errinfo = mesg;
    }

    if (RTEST(ruby_debug) && !NIL_P(e = ec->errinfo) &&
	!rb_obj_is_kind_of(e, rb_eSystemExit)) {
	enum ruby_tag_type state;

	mesg = e;
	EC_PUSH_TAG(ec);
	if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	    ec->errinfo = Qnil;
	    e = rb_obj_as_string(mesg);
	    ec->errinfo = mesg;
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
	EC_POP_TAG();
	if (state == TAG_FATAL && ec->errinfo == exception_error) {
	    ec->errinfo = mesg;
	}
	else if (state) {
	    rb_ec_reset_raised(ec);
	    EC_JUMP_TAG(ec, state);
	}
    }

    if (rb_ec_set_raised(ec)) {
      fatal:
	ec->errinfo = exception_error;
	rb_ec_reset_raised(ec);
	EC_JUMP_TAG(ec, TAG_FATAL);
    }

    if (tag != TAG_FATAL) {
	RUBY_DTRACE_HOOK(RAISE, rb_obj_classname(ec->errinfo));
	EXEC_EVENT_HOOK(ec, RUBY_EVENT_RAISE, ec->cfp->self, 0, 0, 0, mesg);
    }
}

/*! \private */
void
rb_ec_setup_exception(const rb_execution_context_t *ec, VALUE mesg, VALUE cause)
{
    if (cause == Qundef) {
	cause = get_ec_errinfo(ec);
    }
    if (cause != mesg) {
	rb_ivar_set(mesg, id_cause, cause);
    }
}

static void
rb_longjmp(rb_execution_context_t *ec, int tag, volatile VALUE mesg, VALUE cause)
{
    mesg = exc_setup_message(ec, mesg, &cause);
    setup_exception(ec, tag, mesg, cause);
    rb_ec_raised_clear(ec);
    EC_JUMP_TAG(ec, tag);
}

static VALUE make_exception(int argc, const VALUE *argv, int isstr);

/*!
 * Raises an exception in the current thread.
 * \param[in] mesg an Exception class or an \c Exception object.
 * \exception always raises an instance of the given exception class or
 *   the given \c Exception object.
 * \ingroup exception
 */
void
rb_exc_raise(VALUE mesg)
{
    if (!NIL_P(mesg)) {
	mesg = make_exception(1, &mesg, FALSE);
    }
    rb_longjmp(GET_EC(), TAG_RAISE, mesg, Qundef);
}

/*!
 * Raises a fatal error in the current thread.
 *
 * Same as rb_exc_raise() but raises a fatal error, which Ruby codes
 * cannot rescue.
 * \ingroup exception
 */
void
rb_exc_fatal(VALUE mesg)
{
    if (!NIL_P(mesg)) {
	mesg = make_exception(1, &mesg, FALSE);
    }
    rb_longjmp(GET_EC(), TAG_FATAL, mesg, Qnil);
}

/*!
 * Raises an \c Interrupt exception.
 * \ingroup exception
 */
void
rb_interrupt(void)
{
    rb_exc_raise(rb_exc_new(rb_eInterrupt, 0, 0));
}

enum {raise_opt_cause, raise_max_opt}; /*< \private */

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

VALUE
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

    UNREACHABLE_RETURN(Qnil);
}

/*
 *  call-seq:
 *     raise
 *     raise(string, cause: $!)
 *     raise(exception [, string [, array]], cause: $!)
 *     fail
 *     fail(string, cause: $!)
 *     fail(exception [, string [, array]], cause: $!)
 *
 *  With no arguments, raises the exception in <code>$!</code> or raises
 *  a RuntimeError if <code>$!</code> is +nil+.  With a single +String+
 *  argument, raises a +RuntimeError+ with the string as a message. Otherwise,
 *  the first parameter should be an +Exception+ class (or another
 *  object that returns an +Exception+ object when sent an +exception+
 *  message).  The optional second parameter sets the message associated with
 *  the exception (accessible via Exception#message), and the third parameter
 *  is an array of callback information (accessible via Exception#backtrace).
 *  The +cause+ of the generated exception (accessible via Exception#cause)
 *  is automatically set to the "current" exception (<code>$!</code>), if any.
 *  An alternative value, either an +Exception+ object or +nil+, can be
 *  specified via the +:cause+ argument.
 *
 *  Exceptions are caught by the +rescue+ clause of
 *  <code>begin...end</code> blocks.
 *
 *     raise "Failed to create socket"
 *     raise ArgumentError, "No parameters", caller
 */

static VALUE
f_raise(int c, VALUE *v, VALUE _)
{
    return rb_f_raise(c, v);
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
	mesg = rb_check_funcall(exc, idException, n, argv+1);
	if (mesg == Qundef) {
	    rb_raise(rb_eTypeError, "exception class/object expected");
	}
	break;
      default:
        rb_error_arity(argc, 0, 3);
    }
    if (argc > 0) {
	if (!rb_obj_is_kind_of(mesg, rb_eException))
	    rb_raise(rb_eTypeError, "exception object expected");
	if (argc > 2)
	    set_backtrace(mesg, argv[2]);
    }

    return mesg;
}

/*!
 * Make an \c Exception object from the list of arguments in a manner
 * similar to \c Kernel\#raise.
 *
 * \param[in] argc the number of arguments
 * \param[in] argv a pointer to the array of arguments.
 *
 * The first form of this function takes a \c String argument. Then
 * it returns a \c RuntimeError whose error message is the given value.
 *
 * The second from of this function takes an \c Exception object. Then
 * it just returns the given value.
 *
 * The last form takes an exception class, an optional error message and
 * an optional array of backtrace. Then it passes the optional arguments
 * to \c #exception method of the exception class.
 *
 * \return the exception object, or \c Qnil if \c argc is 0.
 * \ingroup exception
 */
VALUE
rb_make_exception(int argc, const VALUE *argv)
{
    return make_exception(argc, argv, TRUE);
}

/*! \private
 * \todo can be static?
 */
void
rb_raise_jump(VALUE mesg, VALUE cause)
{
    rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = ec->cfp;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
    VALUE klass = me->owner;
    VALUE self = cfp->self;
    ID mid = me->called_id;

    rb_vm_pop_frame(ec);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, self, me->def->original_id, mid, klass, Qnil);

    rb_longjmp(ec, TAG_RAISE, mesg, cause);
}

/*!
 * Continues the exception caught by rb_protect() and rb_eval_string_protect().
 *
 * This function never return to the caller.
 * \param[in] the value of \c *state which the protect function has set to the
 *   their last parameter.
 * \ingroup exception
 */
void
rb_jump_tag(int tag)
{
    if (UNLIKELY(tag < TAG_RETURN || tag > TAG_FATAL)) {
	unknown_longjmp_status(tag);
    }
    EC_JUMP_TAG(GET_EC(), tag);
}

/*! Determines if the current method is given a block.
 * \retval zero if not given
 * \retval non-zero if given
 * \ingroup defmethod
 */
int
rb_block_given_p(void)
{
    if (rb_vm_frame_block_handler(GET_EC()->cfp) == VM_BLOCK_HANDLER_NONE) {
	return FALSE;
    }
    else {
	return TRUE;
    }
}

int rb_vm_cframe_keyword_p(const rb_control_frame_t *cfp);

int
rb_keyword_given_p(void)
{
    return rb_vm_cframe_keyword_p(GET_EC()->cfp);
}

/* -- Remove In 3.0 -- */
int rb_vm_cframe_empty_keyword_p(const rb_control_frame_t *cfp);
int
rb_empty_keyword_given_p(void)
{
    return rb_vm_cframe_empty_keyword_p(GET_EC()->cfp);
}

VALUE rb_eThreadError;

/*! Declares that the current method needs a block.
 *
 * Raises a \c LocalJumpError if not given a block.
 * \ingroup defmethod
 */
void
rb_need_block(void)
{
    if (!rb_block_given_p()) {
	rb_vm_localjump_error("no block given", Qnil, 0);
    }
}

/*! An equivalent of \c rescue clause.
 *
 * Equivalent to <code>begin .. rescue err_type .. end</code>
 *
 * \param[in] b_proc a function which potentially raises an exception.
 * \param[in] data1 the argument of \a b_proc
 * \param[in] r_proc a function which rescues an exception in \a b_proc.
 * \param[in] data2 the first argument of \a r_proc
 * \param[in] ... 1 or more exception classes. Must be terminated by \c (VALUE)0.
 *
 * First it calls the function \a b_proc, with \a data1 as the argument.
 * When \a b_proc raises an exception, it calls \a r_proc with \a data2 and
 * the exception object if the exception is a kind of one of the given
 * exception classes.
 *
 * \return the return value of \a b_proc if no exception occurs,
 *   or the return value of \a r_proc if otherwise.
 * \sa rb_rescue
 * \sa rb_ensure
 * \sa rb_protect
 * \ingroup exception
 */
VALUE
rb_rescue2(VALUE (* b_proc) (VALUE), VALUE data1,
           VALUE (* r_proc) (VALUE, VALUE), VALUE data2, ...)
{
    va_list ap;
    va_start(ap, data2);
    VALUE ret = rb_vrescue2(b_proc, data1, r_proc, data2, ap);
    va_end(ap);
    return ret;
}

/*!
 * \copydoc rb_rescue2
 * \param[in] args exception classes, terminated by 0.
 */
VALUE
rb_vrescue2(VALUE (* b_proc) (VALUE), VALUE data1,
            VALUE (* r_proc) (VALUE, VALUE), VALUE data2,
            va_list args)
{
    enum ruby_tag_type state;
    rb_execution_context_t * volatile ec = GET_EC();
    rb_control_frame_t *volatile cfp = ec->cfp;
    volatile VALUE result = Qfalse;
    volatile VALUE e_info = ec->errinfo;

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
      retry_entry:
	result = (*b_proc) (data1);
    }
    else if (result) {
	/* escape from r_proc */
	if (state == TAG_RETRY) {
	    state = 0;
	    ec->errinfo = Qnil;
	    result = Qfalse;
	    goto retry_entry;
	}
    }
    else {
	rb_vm_rewind_cfp(ec, cfp);

	if (state == TAG_RAISE) {
	    int handle = FALSE;
	    VALUE eclass;

	    while ((eclass = va_arg(args, VALUE)) != 0) {
		if (rb_obj_is_kind_of(ec->errinfo, eclass)) {
		    handle = TRUE;
		    break;
		}
	    }

	    if (handle) {
		result = Qnil;
		state = 0;
		if (r_proc) {
		    result = (*r_proc) (data2, ec->errinfo);
		}
		ec->errinfo = e_info;
	    }
	}
    }
    EC_POP_TAG();
    if (state)
	EC_JUMP_TAG(ec, state);

    return result;
}

/*! An equivalent of \c rescue clause.
 *
 * Equivalent to <code>begin .. rescue .. end</code>.
 *
 * It is same as
 * \code{cpp}
 * rb_rescue2(b_proc, data1, r_proc, data2, rb_eStandardError, (VALUE)0);
 * \endcode
 *
 * \sa rb_rescue2
 * \sa rb_ensure
 * \sa rb_protect
 * \ingroup exception
 */
VALUE
rb_rescue(VALUE (* b_proc)(VALUE), VALUE data1,
          VALUE (* r_proc)(VALUE, VALUE), VALUE data2)
{
    return rb_rescue2(b_proc, data1, r_proc, data2, rb_eStandardError,
		      (VALUE)0);
}

/*! Protects a function call from potential global escapes from the function.
 *
 * Such global escapes include exceptions, \c Kernel\#throw, \c break in
 * an iterator, for example.
 * It first calls the function func with arg as the argument.
 * If no exception occurred during func, it returns the result of func and
 * *state is zero.
 * Otherwise, it returns Qnil and sets *state to nonzero.
 * If state is NULL, it is not set in both cases.
 *
 * You have to clear the error info with rb_set_errinfo(Qnil) when
 * ignoring the caught exception.
 * \ingroup exception
 * \sa rb_rescue
 * \sa rb_rescue2
 * \sa rb_ensure
 */
VALUE
rb_protect(VALUE (* proc) (VALUE), VALUE data, int *pstate)
{
    volatile VALUE result = Qnil;
    volatile enum ruby_tag_type state;
    rb_execution_context_t * volatile ec = GET_EC();
    rb_control_frame_t *volatile cfp = ec->cfp;
    struct rb_vm_protect_tag protect_tag;
    rb_jmpbuf_t org_jmpbuf;

    protect_tag.prev = ec->protect_tag;

    EC_PUSH_TAG(ec);
    ec->protect_tag = &protect_tag;
    MEMCPY(&org_jmpbuf, &rb_ec_thread_ptr(ec)->root_jmpbuf, rb_jmpbuf_t, 1);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	SAVE_ROOT_JMPBUF(rb_ec_thread_ptr(ec), result = (*proc) (data));
    }
    else {
	rb_vm_rewind_cfp(ec, cfp);
    }
    MEMCPY(&rb_ec_thread_ptr(ec)->root_jmpbuf, &org_jmpbuf, rb_jmpbuf_t, 1);
    ec->protect_tag = protect_tag.prev;
    EC_POP_TAG();

    if (pstate != NULL) *pstate = state;
    return result;
}

/*!
 * An equivalent to \c ensure clause.
 *
 * Equivalent to <code>begin .. ensure .. end</code>.
 *
 * Calls the function \a b_proc with \a data1 as the argument,
 * then calls \a e_proc with \a data2 when execution terminated.
 * \return The return value of \a b_proc if no exception occurred,
 *   or \c Qnil if otherwise.
 * \sa rb_rescue
 * \sa rb_rescue2
 * \sa rb_protect
 * \ingroup exception
 */
VALUE
rb_ensure(VALUE (*b_proc)(VALUE), VALUE data1, VALUE (*e_proc)(VALUE), VALUE data2)
{
    int state;
    volatile VALUE result = Qnil;
    VALUE errinfo;
    rb_execution_context_t * volatile ec = GET_EC();
    rb_ensure_list_t ensure_list;
    ensure_list.entry.marker = 0;
    ensure_list.entry.e_proc = e_proc;
    ensure_list.entry.data2 = data2;
    ensure_list.next = ec->ensure_list;
    ec->ensure_list = &ensure_list;
    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	result = (*b_proc) (data1);
    }
    EC_POP_TAG();
    errinfo = ec->errinfo;
    if (!NIL_P(errinfo) && !RB_TYPE_P(errinfo, T_OBJECT)) {
	ec->errinfo = Qnil;
    }
    ec->ensure_list=ensure_list.next;
    (*ensure_list.entry.e_proc)(ensure_list.entry.data2);
    ec->errinfo = errinfo;
    if (state)
	EC_JUMP_TAG(ec, state);
    return result;
}

static ID
frame_func_id(const rb_control_frame_t *cfp)
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

/*!
 * The original name of the current method.
 *
 * The function returns the original name of the method even if
 * an alias of the method is called.
 * The function can also return 0 if it is not in a method. This
 * case can happen in a toplevel of a source file, for example.
 *
 * \returns the ID of the name or 0
 * \sa rb_frame_callee
 * \ingroup defmethod
 */
ID
rb_frame_this_func(void)
{
    return frame_func_id(GET_EC()->cfp);
}

/*!
 * The name of the current method.
 *
 * The function returns the alias if an alias of the method is called.
 * The function can also return 0 if it is not in a method. This
 * case can happen in a toplevel of a source file, for example.
 *
 * \returns the ID of the name or 0.
 * \sa rb_frame_this_func
 * \ingroup defmethod
 */
ID
rb_frame_callee(void)
{
    return frame_called_id(GET_EC()->cfp);
}

static rb_control_frame_t *
previous_frame(const rb_execution_context_t *ec)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp);
    /* check if prev_cfp can be accessible */
    if ((void *)(ec->vm_stack + ec->vm_stack_size) == (void *)(prev_cfp)) {
        return 0;
    }
    return prev_cfp;
}

static ID
prev_frame_callee(void)
{
    rb_control_frame_t *prev_cfp = previous_frame(GET_EC());
    if (!prev_cfp) return 0;
    return frame_called_id(prev_cfp);
}

static ID
prev_frame_func(void)
{
    rb_control_frame_t *prev_cfp = previous_frame(GET_EC());
    if (!prev_cfp) return 0;
    return frame_func_id(prev_cfp);
}

/*!
 * \private
 * Returns the ID of the last method in the call stack.
 * \sa rb_frame_this_func
 * \ingroup defmethod
 */
ID
rb_frame_last_func(void)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = ec->cfp;
    ID mid;

    while (!(mid = frame_func_id(cfp)) &&
	   (cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp),
	    !RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)));
    return mid;
}

/*
 *  call-seq:
 *     append_features(mod)   -> mod
 *
 *  When this module is included in another, Ruby calls
 *  #append_features in this module, passing it the receiving module
 *  in _mod_. Ruby's default implementation is to add the constants,
 *  methods, and module variables of this module to _mod_ if this
 *  module has not already been added to _mod_ or one of its
 *  ancestors. See also Module#include.
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
 *  Invokes Module.append_features on each parameter in reverse order.
 */

static VALUE
rb_mod_include(int argc, VALUE *argv, VALUE module)
{
    int i;
    ID id_append_features, id_included;

    CONST_ID(id_append_features, "append_features");
    CONST_ID(id_included, "included");

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
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
 *  #prepend_features in this module, passing it the receiving module
 *  in _mod_. Ruby's default implementation is to overlay the
 *  constants, methods, and module variables of this module to _mod_
 *  if this module has not already been added to _mod_ or one of its
 *  ancestors. See also Module#prepend.
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
 *  Invokes Module.prepend_features on each parameter in reverse order.
 */

static VALUE
rb_mod_prepend(int argc, VALUE *argv, VALUE module)
{
    int i;
    ID id_prepend_features, id_prepended;

    CONST_ID(id_prepend_features, "prepend_features");
    CONST_ID(id_prepended, "prepended");

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    for (i = 0; i < argc; i++)
	Check_Type(argv[i], T_MODULE);
    while (argc--) {
	rb_funcall(argv[argc], id_prepend_features, 1, module);
	rb_funcall(argv[argc], id_prepended, 1, module);
    }
    return module;
}

static void
ensure_class_or_module(VALUE obj)
{
    if (!RB_TYPE_P(obj, T_CLASS) && !RB_TYPE_P(obj, T_MODULE)) {
	rb_raise(rb_eTypeError,
		 "wrong argument type %"PRIsVALUE" (expected Class or Module)",
		 rb_obj_class(obj));
    }
}

static VALUE
hidden_identity_hash_new(void)
{
    VALUE hash = rb_ident_hash_new();

    RBASIC_CLEAR_CLASS(hash); /* hide from ObjectSpace */
    return hash;
}

static VALUE
refinement_superclass(VALUE superclass)
{
    if (RB_TYPE_P(superclass, T_MODULE)) {
	/* FIXME: Should ancestors of superclass be used here? */
	return rb_include_class_new(superclass, rb_cBasicObject);
    }
    else {
	return superclass;
    }
}

/*!
 * \private
 * \todo can be static?
 */
void
rb_using_refinement(rb_cref_t *cref, VALUE klass, VALUE module)
{
    VALUE iclass, c, superclass = klass;

    ensure_class_or_module(klass);
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
    superclass = refinement_superclass(superclass);
    c = iclass = rb_include_class_new(module, superclass);
    RB_OBJ_WRITE(c, &RCLASS_REFINED_CLASS(c), klass);

    RCLASS_M_TBL(OBJ_WB_UNPROTECT(c)) =
      RCLASS_M_TBL(OBJ_WB_UNPROTECT(module)); /* TODO: check unprotecting */

    module = RCLASS_SUPER(module);
    while (module && module != klass) {
	FL_SET(module, RMODULE_IS_OVERLAID);
	c = RCLASS_SET_SUPER(c, rb_include_class_new(module, RCLASS_SUPER(c)));
        RB_OBJ_WRITE(c, &RCLASS_REFINED_CLASS(c), klass);
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

/*!
 * \private
 * \todo can be static?
 */
void
rb_using_module(const rb_cref_t *cref, VALUE module)
{
    Check_Type(module, T_MODULE);
    using_module_recursive(cref, module);
    rb_clear_method_cache_by_class(rb_cObject);
}

/*! \private */
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
    superclass = refinement_superclass(superclass);
    c = iclass = rb_include_class_new(refinement, superclass);
    RB_OBJ_WRITE(c, &RCLASS_REFINED_CLASS(c), klass);
    refinement = RCLASS_SUPER(refinement);
    while (refinement && refinement != klass) {
	FL_SET(refinement, RMODULE_IS_OVERLAID);
	c = RCLASS_SET_SUPER(c, rb_include_class_new(refinement, RCLASS_SUPER(c)));
        RB_OBJ_WRITE(c, &RCLASS_REFINED_CLASS(c), klass);
	refinement = RCLASS_SUPER(refinement);
    }
    rb_hash_aset(activated_refinements, klass, iclass);
}

/*
 *  call-seq:
 *     refine(mod) { block }   -> module
 *
 *  Refine <i>mod</i> in the receiver.
 *
 *  Returns a module, where refined methods are defined.
 */

static VALUE
rb_mod_refine(VALUE module, VALUE klass)
{
    VALUE refinement;
    ID id_refinements, id_activated_refinements,
       id_refined_class, id_defined_at;
    VALUE refinements, activated_refinements;
    rb_thread_t *th = GET_THREAD();
    VALUE block_handler = rb_vm_frame_block_handler(th->ec->cfp);

    if (block_handler == VM_BLOCK_HANDLER_NONE) {
	rb_raise(rb_eArgError, "no block given");
    }
    if (vm_block_handler_type(block_handler) != block_handler_type_iseq) {
	rb_raise(rb_eArgError, "can't pass a Proc as a block to Module#refine");
    }

    ensure_class_or_module(klass);
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
	VALUE superclass = refinement_superclass(klass);
	refinement = rb_module_new();
	RCLASS_SET_SUPER(refinement, superclass);
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
    Check_Type(module, T_MODULE);
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
    rb_control_frame_t *prev_cfp = previous_frame(GET_EC());

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

static int
used_modules_i(VALUE _, VALUE mod, VALUE ary)
{
    ID id_defined_at;
    CONST_ID(id_defined_at, "__defined_at__");
    while (FL_TEST(rb_class_of(mod), RMODULE_IS_REFINEMENT)) {
	rb_ary_push(ary, rb_attr_get(rb_class_of(mod), id_defined_at));
	mod = RCLASS_SUPER(mod);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     used_modules -> array
 *
 *  Returns an array of all modules used in the current scope. The ordering
 *  of modules in the resulting array is not defined.
 *
 *     module A
 *       refine Object do
 *       end
 *     end
 *
 *     module B
 *       refine Object do
 *       end
 *     end
 *
 *     using A
 *     using B
 *     p Module.used_modules
 *
 *  <em>produces:</em>
 *
 *     [B, A]
 */
static VALUE
rb_mod_s_used_modules(VALUE _)
{
    const rb_cref_t *cref = rb_vm_cref();
    VALUE ary = rb_ary_new();

    while (cref) {
	if (!NIL_P(CREF_REFINEMENTS(cref))) {
	    rb_hash_foreach(CREF_REFINEMENTS(cref), used_modules_i, ary);
	}
	cref = CREF_NEXT(cref);
    }

    return rb_funcall(ary, rb_intern("uniq"), 0);
}

/*!
 * Calls \c #initialize method of \a obj with the given arguments.
 *
 * It also forwards the given block to \c #initialize if given.
 *
 * \param[in] obj the receiver object
 * \param[in] argc the number of arguments
 * \param[in] argv a pointer to the array of arguments
 * \ingroup object
 */
void
rb_obj_call_init(VALUE obj, int argc, const VALUE *argv)
{
    PASS_PASSED_BLOCK_HANDLER();
    rb_funcallv_kw(obj, idInitialize, argc, argv, RB_NO_KEYWORDS);
}

void
rb_obj_call_init_kw(VALUE obj, int argc, const VALUE *argv, int kw_splat)
{
    PASS_PASSED_BLOCK_HANDLER();
    rb_funcallv_kw(obj, idInitialize, argc, argv, kw_splat);
}

/*!
 * Extend the object with the module.
 *
 * Same as \c Module\#extend_object.
 * \ingroup class
 */
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
 *  method used by Object#extend.
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
 *  Invokes Module.append_features on each parameter in turn.
 *  Effectively adds the methods and constants in each module to the
 *  receiver.
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
 *  #using is called.
 */

static VALUE
top_using(VALUE self, VALUE module)
{
    const rb_cref_t *cref = rb_vm_cref();
    rb_control_frame_t *prev_cfp = previous_frame(GET_EC());

    if (CREF_NEXT(cref) || (prev_cfp && rb_vm_frame_method_entry(prev_cfp))) {
	rb_raise(rb_eRuntimeError, "main.using is permitted only at toplevel");
    }
    if (rb_block_given_p()) {
	ignored_block(module, "main.");
    }
    rb_using_module(rb_vm_cref_replace_with_duplicated_cref(), module);
    return self;
}

static const VALUE *
errinfo_place(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = ec->cfp;
    const rb_control_frame_t *end_cfp = RUBY_VM_END_CONTROL_FRAME(ec);

    while (RUBY_VM_VALID_CONTROL_FRAME_P(cfp, end_cfp)) {
	if (VM_FRAME_RUBYFRAME_P(cfp)) {
	    if (cfp->iseq->body->type == ISEQ_TYPE_RESCUE) {
		return &cfp->ep[VM_ENV_INDEX_LAST_LVAR];
	    }
	    else if (cfp->iseq->body->type == ISEQ_TYPE_ENSURE &&
		     !THROW_DATA_P(cfp->ep[VM_ENV_INDEX_LAST_LVAR]) &&
		     !FIXNUM_P(cfp->ep[VM_ENV_INDEX_LAST_LVAR])) {
		return &cfp->ep[VM_ENV_INDEX_LAST_LVAR];
	    }
	}
	cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    }
    return 0;
}

static VALUE
get_ec_errinfo(const rb_execution_context_t *ec)
{
    const VALUE *ptr = errinfo_place(ec);
    if (ptr) {
	return *ptr;
    }
    else {
	return ec->errinfo;
    }
}

static VALUE
get_errinfo(void)
{
    return get_ec_errinfo(GET_EC());
}

static VALUE
errinfo_getter(ID id, VALUE *_)
{
    return get_errinfo();
}

/*! The current exception in the current thread.
 *
 * Same as \c $! in Ruby.
 * \return the current exception or \c Qnil
 * \ingroup exception
 */
VALUE
rb_errinfo(void)
{
    return GET_EC()->errinfo;
}

/*! Sets the current exception (\c $!) to the given value
 *
 * \param[in] err an \c Exception object or \c Qnil.
 * \exception TypeError if \a err is neither an exception nor \c nil.
 * \note this function does not raise the exception.
 *   Use \c rb_raise() when you want to raise.
 * \ingroup exception
 */
void
rb_set_errinfo(VALUE err)
{
    if (!NIL_P(err) && !rb_obj_is_kind_of(err, rb_eException)) {
	rb_raise(rb_eTypeError, "assigning non-exception to $!");
    }
    GET_EC()->errinfo = err;
}

static VALUE
errat_getter(ID id, VALUE *_)
{
    VALUE err = get_errinfo();
    if (!NIL_P(err)) {
	return rb_get_backtrace(err);
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
rb_f_method_name(VALUE _)
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
rb_f_callee_name(VALUE _)
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
f_current_dirname(VALUE _)
{
    VALUE base = rb_current_realfilepath();
    if (NIL_P(base)) {
	return Qnil;
    }
    base = rb_file_dirname(base);
    return base;
}

/*
 *  call-seq:
 *     global_variables    -> array
 *
 *  Returns an array of the names of global variables.
 *
 *     global_variables.grep /std/   #=> [:$stdin, :$stdout, :$stderr]
 */

static VALUE
f_global_variables(VALUE _)
{
    return rb_f_global_variables();
}

/*
 *  call-seq:
 *     trace_var(symbol, cmd )             -> nil
 *     trace_var(symbol) {|val| block }    -> nil
 *
 *  Controls tracing of assignments to global variables. The parameter
 *  +symbol+ identifies the variable (as either a string name or a
 *  symbol identifier). _cmd_ (which may be a string or a
 *  +Proc+ object) or block is executed whenever the variable
 *  is assigned. The block or +Proc+ object receives the
 *  variable's new value as a parameter. Also see
 *  Kernel::untrace_var.
 *
 *     trace_var :$_, proc {|v| puts "$_ is now '#{v}'" }
 *     $_ = "hello"
 *     $_ = ' there'
 *
 *  <em>produces:</em>
 *
 *     $_ is now 'hello'
 *     $_ is now ' there'
 */

static VALUE
f_trace_var(int c, const VALUE *a, VALUE _)
{
    return rb_f_trace_var(c, a);
}

/*
 *  call-seq:
 *     untrace_var(symbol [, cmd] )   -> array or nil
 *
 *  Removes tracing for the specified command on the given global
 *  variable and returns +nil+. If no command is specified,
 *  removes all tracing for that variable and returns an array
 *  containing the commands actually removed.
 */

static VALUE
f_untrace_var(int c, const VALUE *a, VALUE _)
{
    return rb_f_untrace_var(c, a);
}

void
Init_eval(void)
{
    rb_define_virtual_variable("$@", errat_getter, errat_setter);
    rb_define_virtual_variable("$!", errinfo_getter, 0);

    rb_define_global_function("raise", f_raise, -1);
    rb_define_global_function("fail", f_raise, -1);

    rb_define_global_function("global_variables", f_global_variables, 0);

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
    rb_define_singleton_method(rb_cModule, "used_modules",
			       rb_mod_s_used_modules, 0);
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

    rb_define_global_function("trace_var", f_trace_var, -1);
    rb_define_global_function("untrace_var", f_untrace_var, -1);

    rb_vm_register_special_exception(ruby_error_reenter, rb_eFatal, "exception reentered");
    rb_vm_register_special_exception(ruby_error_stackfatal, rb_eFatal, "machine stack overflow in critical region");

    id_signo = rb_intern_const("signo");
    id_status = rb_intern_const("status");
}
