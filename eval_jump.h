/*
 * from eval.c
 */

#include "eval_intern.h"

NORETURN(static VALUE rb_f_throw _((int, VALUE *)));

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
    rb_thead_t *th = GET_THREAD();
    struct rb_vm_tag *tt = th->tag;

    rb_scan_args(argc, argv, "11", &tag, &value);
    tag = ID2SYM(rb_to_id(tag));

    while (tt) {
	if (tt->tag == tag) {
	    tt->retval = value;
	    break;
	}
	tt = tt->prev;
    }
    if (!tt) {
	rb_name_error(SYM2ID(tag), "uncaught throw `%s'",
		      rb_id2name(SYM2ID(tag)));
    }
    rb_trap_restore_mask();
    th->errinfo = tag;

    JUMP_TAG(TAG_THROW);
#ifndef __GNUC__
    return Qnil;		/* not reached */
#endif
}

void
rb_throw(const char *tag, VALUE val)
{
    VALUE argv[2];

    argv[0] = ID2SYM(rb_intern(tag));
    argv[1] = val;
    rb_f_throw(2, argv);
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
rb_f_catch(VALUE dmy, VALUE tag)
{
    int state;
    VALUE val = Qnil;		/* OK */
    rb_thead_t *th = GET_THREAD();

    tag = ID2SYM(rb_to_id(tag));
    PUSH_TAG(tag);

    th->tag->tag = tag;

    if ((state = EXEC_TAG()) == 0) {
	val = rb_yield_0(tag, 0, 0, 0, Qfalse);
    }
    else if (state == TAG_THROW && th->errinfo == tag) {
	val = th->tag->retval;
	th->errinfo = 0;
	state = 0;
    }
    POP_TAG();
    if (state)
	JUMP_TAG(state);

    return val;
}

static VALUE
catch_i(VALUE tag)
{
    return rb_funcall(Qnil, rb_intern("catch"), 1, tag);
}

VALUE
rb_catch(const char *tag, VALUE (*func)(), VALUE data)
{
    return rb_iterate((VALUE (*)_((VALUE)))catch_i, ID2SYM(rb_intern(tag)),
		      func, data);
}


/* exit */

NORETURN(static VALUE terminate_process _((int, const char *, long)));

static VALUE
terminate_process(int status, const char *mesg, long mlen)
{
    VALUE args[2];
    rb_vm_t *vm = GET_THREAD()->vm;

    args[0] = INT2NUM(status);
    args[1] = rb_str_new(mesg, mlen);

    vm->exit_code = status;
    rb_exc_raise(rb_class_new_instance(2, args, rb_eSystemExit));
}


void
rb_exit(int status)
{
    if (GET_THREAD()->tag) {
	terminate_process(status, "exit", 4);
    }
    ruby_finalize();
    exit(status);
}

/*
 *  call-seq:
 *     exit(integer=0)
 *     Kernel::exit(integer=0)
 *     Process::exit(integer=0)
 *  
 *  Initiates the termination of the Ruby script by raising the
 *  <code>SystemExit</code> exception. This exception may be caught. The
 *  optional parameter is used to return a status code to the invoking
 *  environment.
 *     
 *     begin
 *       exit
 *       puts "never get here"
 *     rescue SystemExit
 *       puts "rescued a SystemExit exception"
 *     end
 *     puts "after begin block"
 *     
 *  <em>produces:</em>
 *     
 *     rescued a SystemExit exception
 *     after begin block
 *     
 *  Just prior to termination, Ruby executes any <code>at_exit</code> functions
 *  (see Kernel::at_exit) and runs any object finalizers (see
 *  ObjectSpace::define_finalizer).
 *     
 *     at_exit { puts "at_exit function" }
 *     ObjectSpace.define_finalizer("string",  proc { puts "in finalizer" })
 *     exit
 *     
 *  <em>produces:</em>
 *     
 *     at_exit function
 *     in finalizer
 */

VALUE
rb_f_exit(int argc, VALUE *argv)
{
    VALUE status;
    int istatus;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "01", &status) == 1) {
	switch (status) {
	case Qtrue:
	    istatus = EXIT_SUCCESS;
	    break;
	case Qfalse:
	    istatus = EXIT_FAILURE;
	    break;
	default:
	    istatus = NUM2INT(status);
#if EXIT_SUCCESS != 0
	    if (istatus == 0)
		istatus = EXIT_SUCCESS;
#endif
	    break;
	}
    }
    else {
	istatus = EXIT_SUCCESS;
    }
    rb_exit(istatus);
    return Qnil;		/* not reached */
}


/*
 *  call-seq:
 *     abort
 *     Kernel::abort
 *     Process::abort
 *  
 *  Terminate execution immediately, effectively by calling
 *  <code>Kernel.exit(1)</code>. If _msg_ is given, it is written
 *  to STDERR prior to terminating.
 */

VALUE
rb_f_abort(int argc, VALUE *argv)
{
    rb_secure(4);
    if (argc == 0) {
	if (!NIL_P(GET_THREAD()->errinfo)) {
	    error_print();
	}
	rb_exit(EXIT_FAILURE);
    }
    else {
	VALUE mesg;

	rb_scan_args(argc, argv, "1", &mesg);
	StringValue(argv[0]);
	rb_io_puts(argc, argv, rb_stderr);
	terminate_process(EXIT_FAILURE, RSTRING_PTR(argv[0]),
			  RSTRING_LEN(argv[0]));
    }
    return Qnil;		/* not reached */
}

static void call_end_proc _((VALUE data));

static void
call_end_proc(VALUE data)
{
    /* TODO: fix me */
    proc_invoke(data, rb_ary_new2(0), Qundef, 0);
}

/*
 *  call-seq:
 *     at_exit { block } -> proc
 *  
 *  Converts _block_ to a +Proc+ object (and therefore
 *  binds it at the point of call) and registers it for execution when
 *  the program exits. If multiple handlers are registered, they are
 *  executed in reverse order of registration.
 *     
 *     def do_at_exit(str1)
 *       at_exit { print str1 }
 *     end
 *     at_exit { puts "cruel world" }
 *     do_at_exit("goodbye ")
 *     exit
 *     
 *  <em>produces:</em>
 *     
 *     goodbye cruel world
 */

static VALUE
rb_f_at_exit(void)
{
    VALUE proc;

    if (!rb_block_given_p()) {
	rb_raise(rb_eArgError, "called without a block");
    }
    proc = rb_block_proc();
    rb_set_end_proc(call_end_proc, proc);
    return proc;
}

struct end_proc_data {
    void (*func) ();
    VALUE data;
    int safe;
    struct end_proc_data *next;
};

static struct end_proc_data *end_procs, *ephemeral_end_procs, *tmp_end_procs;

void
rb_set_end_proc(void (*func)(VALUE), VALUE data)
{
    struct end_proc_data *link = ALLOC(struct end_proc_data);
    struct end_proc_data **list;

    if (ruby_wrapper) {
	list = &ephemeral_end_procs;
    }
    else {
	list = &end_procs;
    }
    link->next = *list;
    link->func = func;
    link->data = data;
    link->safe = rb_safe_level();
    *list = link;
}

void
rb_mark_end_proc(void)
{
    struct end_proc_data *link;

    link = end_procs;
    while (link) {
	rb_gc_mark(link->data);
	link = link->next;
    }
    link = ephemeral_end_procs;
    while (link) {
	rb_gc_mark(link->data);
	link = link->next;
    }
    link = tmp_end_procs;
    while (link) {
	rb_gc_mark(link->data);
	link = link->next;
    }
}

void
rb_exec_end_proc(void)
{
    struct end_proc_data *link, *tmp;
    int status;
    volatile int safe = rb_safe_level();

    while (ephemeral_end_procs) {
	tmp_end_procs = link = ephemeral_end_procs;
	ephemeral_end_procs = 0;
	while (link) {
	    PUSH_TAG(PROT_NONE);
	    if ((status = EXEC_TAG()) == 0) {
		rb_set_safe_level_force(link->safe);
		(*link->func) (link->data);
	    }
	    POP_TAG();
	    if (status) {
		error_handle(status);
	    }
	    tmp = link;
	    tmp_end_procs = link = link->next;
	    free(tmp);
	}
    }
    while (end_procs) {
	tmp_end_procs = link = end_procs;
	end_procs = 0;
	while (link) {
	    PUSH_TAG(PROT_NONE);
	    if ((status = EXEC_TAG()) == 0) {
		rb_set_safe_level_force(link->safe);
		(*link->func) (link->data);
	    }
	    POP_TAG();
	    if (status) {
		error_handle(status);
	    }
	    tmp = link;
	    tmp_end_procs = link = link->next;
	    free(tmp);
	}
    }
    rb_set_safe_level_force(safe);
}

void
Init_jump()
{
    rb_define_global_function("catch", rb_f_catch, 1);
    rb_define_global_function("throw", rb_f_throw, -1);
    rb_define_global_function("exit", rb_f_exit, -1);
    rb_define_global_function("abort", rb_f_abort, -1);
    rb_define_global_function("at_exit", rb_f_at_exit, 0);
}
