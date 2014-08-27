#include "ruby.h"

#define init(n) {void Init_##n(VALUE klass); Init_##n(klass);}

void
Init_float(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "Float", rb_cObject);
    TEST_INIT_FUNCS(init);
}
