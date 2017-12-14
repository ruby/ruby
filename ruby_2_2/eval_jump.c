/* -*-c-*- */
/*
 * from eval.c
 */

#include "eval_intern.h"

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

static struct end_proc_data *end_procs, *ephemeral_end_procs;

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
}

static void
exec_end_procs_chain(struct end_proc_data *volatile *procs, VALUE *errp)
{
    struct end_proc_data volatile endproc;
    struct end_proc_data *link;
    VALUE errinfo = *errp;

    while ((link = *procs) != 0) {
	*procs = link->next;
	endproc = *link;
	xfree(link);
	rb_set_safe_level_force(endproc.safe);
	(*endproc.func) (endproc.data);
	*errp = errinfo;
    }
}

void
rb_exec_end_proc(void)
{
    int status;
    volatile int safe = rb_safe_level();
    rb_thread_t *th = GET_THREAD();
    volatile VALUE errinfo = th->errinfo;

    PUSH_TAG();
    if ((status = EXEC_TAG()) == 0) {
      again:
	exec_end_procs_chain(&ephemeral_end_procs, &th->errinfo);
	exec_end_procs_chain(&end_procs, &th->errinfo);
    }
    else {
	VAR_INITIALIZED(th);
	TH_TMPPOP_TAG();
	error_handle(status);
	if (!NIL_P(th->errinfo)) errinfo = th->errinfo;
	TH_REPUSH_TAG();
	goto again;
    }
    POP_TAG();

    rb_set_safe_level_force(safe);
    th->errinfo = errinfo;
}

void
Init_jump(void)
{
    rb_define_global_function("at_exit", rb_f_at_exit, 0);
}
