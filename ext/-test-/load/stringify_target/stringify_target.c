#include <ruby.h>
#include "stringify_target.h"

VALUE
stt_any_method(VALUE klass)
{
    return rb_str_new_cstr("from target");
}

void
Init_stringify_target(void)
{
    VALUE mod = rb_define_module("StringifyTarget");
    rb_define_singleton_method(mod, "any_method", stt_any_method, 0);
}
