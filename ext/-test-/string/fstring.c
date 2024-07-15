#include "ruby.h"
#include "ruby/encoding.h"

VALUE rb_fstring(VALUE str);

VALUE
bug_s_fstring(VALUE self, VALUE str)
{
    return rb_fstring(str);
}

VALUE
bug_s_rb_enc_interned_str(VALUE self, VALUE encoding)
{
    return rb_enc_interned_str("foo", 3, NIL_P(encoding) ? NULL : RDATA(encoding)->data);
}

VALUE
bug_s_rb_enc_str_new(VALUE self, VALUE encoding)
{
    return rb_enc_str_new("foo", 3, NIL_P(encoding) ? NULL : RDATA(encoding)->data);
}

void
Init_string_fstring(VALUE klass)
{
    rb_define_singleton_method(klass, "fstring", bug_s_fstring, 1);
    rb_define_singleton_method(klass, "rb_enc_interned_str", bug_s_rb_enc_interned_str, 1);
    rb_define_singleton_method(klass, "rb_enc_str_new", bug_s_rb_enc_str_new, 1);
}
