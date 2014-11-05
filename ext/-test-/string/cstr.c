#include "ruby.h"
#include "ruby/encoding.h"

static VALUE
bug_str_cstr_term(VALUE str)
{
    long len;
    char *s;
    int c;
    rb_encoding *enc;

    rb_str_modify(str);
    len = RSTRING_LEN(str);
    RSTRING_PTR(str)[len] = 'x';
    s = StringValueCStr(str);
    rb_gc();
    enc = rb_enc_get(str);
    c = rb_enc_codepoint(&s[len], &s[len+rb_enc_mbminlen(enc)], enc);
    return INT2NUM(c);
}

static VALUE
bug_str_cstr_term_char(VALUE str)
{
    long len;
    char *s;
    int c;
    rb_encoding *enc = rb_enc_get(str);

    RSTRING_GETMEM(str, s, len);
    c = rb_enc_codepoint(&s[len], &s[len+rb_enc_mbminlen(enc)], enc);
    return c ? rb_enc_uint_chr((unsigned int)c, enc) : Qnil;
}

void
Init_cstr(VALUE klass)
{
    rb_define_method(klass, "cstr_term", bug_str_cstr_term, 0);
    rb_define_method(klass, "cstr_term_char", bug_str_cstr_term_char, 0);
}
