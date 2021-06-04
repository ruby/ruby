#include <ruby.h>

static VALUE
bug_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, arg))
{
    rb_notimplement();
    return ID2SYM(rb_frame_this_func());
}

static VALUE
bug_start(VALUE self)
{
    VALUE ary = rb_ary_new3(1, Qnil);
    rb_block_call(ary, rb_intern("map"), 0, 0, bug_i, self);
    return ary;
}

void
Init_bug_3571(void)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "start", bug_start, 0);
}
