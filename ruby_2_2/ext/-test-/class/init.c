#include "ruby.h"

#define init(n) {void Init_##n(VALUE mod); Init_##n(mod);}

void
Init_class(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE mod = rb_define_module_under(mBug, "Class");
    TEST_INIT_FUNCS(init);
}
