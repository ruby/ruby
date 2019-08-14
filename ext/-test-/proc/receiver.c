#include "ruby.h"

VALUE rb_current_receiver(void);

static VALUE
bug_proc_call_receiver(RB_BLOCK_CALL_FUNC_ARGLIST(yieldarg, procarg))
{
    return rb_current_receiver();
}

static VALUE
bug_proc_make_call_receiver(VALUE self, VALUE procarg)
{
    return rb_proc_new(bug_proc_call_receiver, procarg);
}

void
Init_receiver(VALUE klass)
{
    rb_define_singleton_method(klass, "make_call_receiver", bug_proc_make_call_receiver, 1);
}
