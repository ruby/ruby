#include <ruby.h>
#include <ruby/encoding.h>

static VALUE
enc_raise(VALUE exc, VALUE encoding, VALUE mesg)
{
    rb_enc_raise(rb_to_encoding(encoding), exc, "%s", StringValueCStr(mesg));
    UNREACHABLE_RETURN(Qnil);
}

void
Init_enc_raise(VALUE klass)
{
    rb_define_module_function(klass, "enc_raise", enc_raise, 2);
}
