#include "ruby.h"

#define init(n) \
    { \
        void Init_##n(VALUE klass); \
        Init_##n(klass); \
    }

void
Init_debug(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_module_under(mBug, "Debug");
    TEST_INIT_FUNCS(init);
}
