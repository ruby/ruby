#include "ruby.h"

static VALUE
bug_proc_call_super(VALUE yieldarg, VALUE procarg)
{
    VALUE args[2];
    args[0] = yieldarg;
    args[1] = procarg;
    return rb_call_super(2, args);
}

static VALUE
bug_proc_make_caller(VALUE self, VALUE procarg)
{
    return rb_proc_new(bug_proc_call_super, procarg);
}

void
Init_call_super(VALUE klass)
{
    rb_define_method(klass, "call_super", bug_proc_call_super, 1);
    rb_define_singleton_method(klass, "make_caller", bug_proc_make_caller, 1);
}
