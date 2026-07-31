#include "ruby/ruby.h"

static VALUE
eval_string(VALUE self, VALUE str)
{
    return rb_eval_string(StringValueCStr(str));
}

static VALUE
iseq_load_from_binary(VALUE self, VALUE str)
{
    return rb_iseq_load_from_binary(RSTRING_PTR(str), RSTRING_LEN(str));
}

void
Init_eval(void)
{
    rb_define_global_function("rb_eval_string", eval_string, 1);
    rb_define_global_function("rb_iseq_load_from_binary", iseq_load_from_binary, 1);
}
