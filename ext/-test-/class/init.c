#include "ruby.h"

#define init(n) {void Init_##n(VALUE mod); Init_##n(mod);}

void
Init_class(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE mod = rb_define_module_under(mBug, "Class");
    rb_define_class_under(mod, "TestClassDefinedInC", rb_cObject);
    TEST_INIT_FUNCS(init);
}
