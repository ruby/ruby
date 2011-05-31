#include "ruby.h"

#define init(n) {void Init_##n(VALUE klass); Init_##n(klass);}

VALUE
bug_str_modify(VALUE str)
{
    rb_str_modify(str);
    return str;
}

void
Init_string(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "String", rb_cString);
    rb_define_method(klass, "modify!", bug_str_modify, 0);
    TEST_INIT_FUNCS(init);
}
