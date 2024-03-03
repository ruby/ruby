#include "ruby.h"
#include "ruby/encoding.h"
#include "internal/string.h"

VALUE
bug_s_fstring(VALUE self, VALUE str)
{
    return rb_str_to_interned_str(str);
}

VALUE
bug_s_fstring_fake_str(VALUE self)
{
    static const char literal[] = "abcdefghijklmnopqrstuvwxyz";
    struct RString fake_str;
    return rb_str_to_interned_str(rb_setup_fake_str(&fake_str, literal, sizeof(literal) - 1, 0));
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
    rb_define_singleton_method(klass, "fstring_fake_str", bug_s_fstring_fake_str, 0);
    rb_define_singleton_method(klass, "rb_enc_interned_str", bug_s_rb_enc_interned_str, 1);
    rb_define_singleton_method(klass, "rb_enc_str_new", bug_s_rb_enc_str_new, 1);
}
