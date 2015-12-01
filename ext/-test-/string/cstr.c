#include "ruby.h"
#include "ruby/encoding.h"

static VALUE
bug_str_cstr_term(VALUE str)
{
    long len;
    char *s;
    int c;
    rb_encoding *enc;

    len = RSTRING_LEN(str);
    s = StringValueCStr(str);
    rb_gc();
    enc = rb_enc_get(str);
    c = rb_enc_codepoint(&s[len], &s[len+rb_enc_mbminlen(enc)], enc);
    return INT2NUM(c);
}

static VALUE
bug_str_cstr_unterm(VALUE str, VALUE c)
{
    long len;

    rb_str_modify(str);
    len = RSTRING_LEN(str);
    RSTRING_PTR(str)[len] = NUM2CHR(c);
    return str;
}

static VALUE
bug_str_cstr_term_char(VALUE str)
{
    long len;
    char *s;
    int c;
    rb_encoding *enc = rb_enc_get(str);

    RSTRING_GETMEM(str, s, len);
    s += len;
    len = rb_enc_mbminlen(enc);
    c = rb_enc_precise_mbclen(s, s + len, enc);
    if (!MBCLEN_CHARFOUND_P(c)) {
	c = (unsigned char)*s;
    }
    else {
	c = rb_enc_mbc_to_codepoint(s, s + len, enc);
	if (!c) return Qnil;
    }
    return rb_enc_uint_chr((unsigned int)c, enc);
}

static VALUE
bug_str_s_cstr_term(VALUE self, VALUE str)
{
    Check_Type(str, T_STRING);
    return bug_str_cstr_term(str);
}

static VALUE
bug_str_s_cstr_unterm(VALUE self, VALUE str, VALUE c)
{
    Check_Type(str, T_STRING);
    return bug_str_cstr_unterm(str, c);
}

static VALUE
bug_str_s_cstr_term_char(VALUE self, VALUE str)
{
    Check_Type(str, T_STRING);
    return bug_str_cstr_term_char(str);
}

void
Init_cstr(VALUE klass)
{
    rb_define_method(klass, "cstr_term", bug_str_cstr_term, 0);
    rb_define_method(klass, "cstr_unterm", bug_str_cstr_unterm, 1);
    rb_define_method(klass, "cstr_term_char", bug_str_cstr_term_char, 0);
    rb_define_singleton_method(klass, "cstr_term", bug_str_s_cstr_term, 1);
    rb_define_singleton_method(klass, "cstr_unterm", bug_str_s_cstr_unterm, 2);
    rb_define_singleton_method(klass, "cstr_term_char", bug_str_s_cstr_term_char, 1);
}
