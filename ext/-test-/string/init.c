#include "ruby.h"

#define init(n) {void Init_string_##n(VALUE klass); Init_string_##n(klass);}

void
Init_string(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "String", rb_cString);
    TEST_INIT_FUNCS(init);
}
