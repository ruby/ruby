#include <ruby.h>

static VALUE
bug_str_resize(VALUE self, VALUE init, VALUE repl)
{
    long initlen = NUM2LONG(init);
    VALUE s = rb_str_buf_new(initlen);
    return rb_str_resize(s, strlcpy(RSTRING_PTR(s), StringValueCStr(repl), (size_t)initlen));
}

void
Init_bug(void)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "str_resize", bug_str_resize, 2);
}
