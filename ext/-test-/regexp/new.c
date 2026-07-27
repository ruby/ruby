#include <ruby.h>

static VALUE
reg_new_binary(VALUE self, VALUE src)
{
    StringValue(src);
    return rb_reg_new(RSTRING_PTR(src), RSTRING_LEN(src), 0);
}

void
Init_new(VALUE klass)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif
    rb_define_singleton_method(klass, "new_binary", reg_new_binary, 1);
}
