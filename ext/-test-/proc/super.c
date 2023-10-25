#include "ruby.h"

static VALUE
bug_proc_call_super(RB_BLOCK_CALL_FUNC_ARGLIST(yieldarg, procarg))
{
    VALUE args[2];
    VALUE ret;
    args[0] = yieldarg;
    args[1] = procarg;
    ret = rb_call_super(2, args);
    if (!NIL_P(blockarg)) {
        ret = rb_proc_call(blockarg, ret);
    }
    return ret;
}

static VALUE
bug_proc_make_call_super(VALUE self, VALUE procarg)
{
    return rb_proc_new(bug_proc_call_super, procarg);
}

void
Init_super(VALUE klass)
{
    rb_define_singleton_method(klass, "make_call_super", bug_proc_make_call_super, 1);
}
