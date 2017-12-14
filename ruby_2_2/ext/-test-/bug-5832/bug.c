#include <ruby.h>

static VALUE
bug_funcall_callback(VALUE self, VALUE obj)
{
    return rb_funcall(obj, rb_intern("callback"), 0);
}

void
Init_bug(void)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "funcall_callback", bug_funcall_callback, 1);
}
