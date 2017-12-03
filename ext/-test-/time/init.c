#include "ruby.h"

#define init(n) {void Init_time_##n(VALUE klass); Init_time_##n(klass);}

void
Init_time(void)
{
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "Time", rb_cTime);
    TEST_INIT_FUNCS(init);
}
