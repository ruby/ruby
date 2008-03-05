/* -*-c-*- */
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
    rb_thread_t *th = GET_THREAD();
    struct rb_vm_tag *tt = th->tag;

    rb_scan_args(argc, argv, "11", &tag, &value);
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

void
rb_throw_obj(VALUE tag, VALUE val)
{
    VALUE argv[2];

    argv[0] = tag;
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
rb_f_catch(int argc, VALUE *argv)
{
    VALUE tag;
    int state;
    VALUE val = Qnil;		/* OK */
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


/* exit */

void
rb_call_end_proc(VALUE data)
{
    rb_proc_call(data, rb_ary_new());
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
    rb_set_end_proc(rb_call_end_proc, proc);
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
    rb_thread_t *th = GET_THREAD();

    if (th->top_wrapper) {
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
	    PUSH_TAG();
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
	    PUSH_TAG();
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
Init_jump(void)
{
    rb_define_global_function("catch", rb_f_catch, -1);
    rb_define_global_function("throw", rb_f_throw, -1);
    rb_define_global_function("at_exit", rb_f_at_exit, 0);
}
