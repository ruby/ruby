#include "ruby.h"

#define init(n) {void Init_##n(VALUE klass); Init_##n(module);}

void
Init_file(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE module = rb_define_module_under(mBug, "File");
    TEST_INIT_FUNCS(init);
}
