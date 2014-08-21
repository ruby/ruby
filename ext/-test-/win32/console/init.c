#include "ruby.h"

#define init(n) {void Init_##n(VALUE m); Init_##n(m);}

void
Init_console(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE m = rb_define_module_under(mBug, "Win32");
    TEST_INIT_FUNCS(init);
}
