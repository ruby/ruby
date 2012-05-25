#include <ruby.h>
#include <ruby/encoding.h>

static VALUE
printf_test_i(VALUE self, VALUE obj)
{
    char buf[256];
    snprintf(buf, sizeof(buf), "<%"PRIsVALUE">", obj);
    return rb_usascii_str_new2(buf);
}

static VALUE
printf_test_s(VALUE self, VALUE obj)
{
    return rb_enc_sprintf(rb_usascii_encoding(), "<%"PRIsVALUE">", obj);
}

static VALUE
printf_test_v(VALUE self, VALUE obj)
{
    return rb_enc_sprintf(rb_usascii_encoding(), "{%+"PRIsVALUE"}", obj);
}

void
Init_printf(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Printf");
    rb_define_singleton_method(m, "i", printf_test_i, 1);
    rb_define_singleton_method(m, "s", printf_test_s, 1);
    rb_define_singleton_method(m, "v", printf_test_v, 1);
}
