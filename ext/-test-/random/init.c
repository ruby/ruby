#include "ruby.h"

#define init(n) {void Init_random_##n(VALUE mod, VALUE base); Init_random_##n(mod, base);}

void
Init_random(void)
{
    VALUE base = rb_const_get(rb_cRandom, rb_intern_const("Base"));
    VALUE mod = rb_define_module_under(rb_define_module("Bug"), "Random");
    TEST_INIT_FUNCS(init);
}
