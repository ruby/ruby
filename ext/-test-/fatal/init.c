#include "ruby.h"

#define init(n) {void Init_##n(VALUE klass); Init_##n(klass);}

void
Init_fatal(void)
{
    VALUE klass = rb_define_module("Bug");
    TEST_INIT_FUNCS(init);
}
