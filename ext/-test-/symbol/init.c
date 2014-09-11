#include "ruby.h"

#define init(n) {void Init_##n(VALUE klass); Init_##n(klass);}

static VALUE
sym_find(VALUE dummy, VALUE sym)
{
    return rb_check_symbol(&sym);
}

void
Init_symbol(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "Symbol", rb_cSymbol);
    rb_define_singleton_method(klass, "find", sym_find, 1);
    TEST_INIT_FUNCS(init);
}
