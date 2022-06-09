#include "internal.h"
#include "internal/string.h"
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
bug_str_unterminated_substring(VALUE str, VALUE vbeg, VALUE vlen)
{
    long beg = NUM2LONG(vbeg);
    long len = NUM2LONG(vlen);
    rb_str_modify(str);
    if (len < 0) rb_raise(rb_eArgError, "negative length: %ld", len);
    if (RSTRING_LEN(str) < beg) rb_raise(rb_eIndexError, "beg: %ld", beg);
    if (RSTRING_LEN(str) < beg + len) rb_raise(rb_eIndexError, "end: %ld", beg + len);
    str = rb_str_new_shared(str);
    if (STR_EMBED_P(str)) {
#if USE_RVARGC
        RSTRING(str)->as.embed.len = (short)len;
#else
	RSTRING(str)->basic.flags &= ~RSTRING_EMBED_LEN_MASK;
	RSTRING(str)->basic.flags |= len << RSTRING_EMBED_LEN_SHIFT;
#endif
        memmove(RSTRING(str)->as.embed.ary, RSTRING(str)->as.embed.ary + beg, len);
    }
    else {
	RSTRING(str)->as.heap.ptr += beg;
	RSTRING(str)->as.heap.len = len;
    }
    return str;
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

#define TERM_LEN(str) rb_enc_mbminlen(rb_enc_get(str))
#define TERM_FILL(ptr, termlen) do {\
    char *const term_fill_ptr = (ptr);\
    const int term_fill_len = (termlen);\
    *term_fill_ptr = '\0';\
    if (UNLIKELY(term_fill_len > 1))\
	memset(term_fill_ptr, 0, term_fill_len);\
} while (0)

static VALUE
bug_str_s_cstr_noembed(VALUE self, VALUE str)
{
    VALUE str2 = rb_str_new(NULL, 0);
    long capacity = RSTRING_LEN(str) + TERM_LEN(str);
    char *buf = ALLOC_N(char, capacity);
    Check_Type(str, T_STRING);
    FL_SET((str2), STR_NOEMBED);
    memcpy(buf, RSTRING_PTR(str), capacity);
#if USE_RVARGC
    RBASIC(str2)->flags &= ~(STR_SHARED | FL_USER5 | FL_USER6);
#else
    RBASIC(str2)->flags &= ~RSTRING_EMBED_LEN_MASK;
#endif
    RSTRING(str2)->as.heap.aux.capa = capacity;
    RSTRING(str2)->as.heap.ptr = buf;
    RSTRING(str2)->as.heap.len = RSTRING_LEN(str);
    TERM_FILL(RSTRING_END(str2), TERM_LEN(str));
    return str2;
}

static VALUE
bug_str_s_cstr_embedded_p(VALUE self, VALUE str)
{
    return STR_EMBED_P(str) ? Qtrue : Qfalse;
}

static VALUE
bug_str_s_rb_str_new_frozen(VALUE self, VALUE str)
{
    return rb_str_new_frozen(str);
}

void
Init_string_cstr(VALUE klass)
{
    rb_define_method(klass, "cstr_term", bug_str_cstr_term, 0);
    rb_define_method(klass, "cstr_unterm", bug_str_cstr_unterm, 1);
    rb_define_method(klass, "cstr_term_char", bug_str_cstr_term_char, 0);
    rb_define_method(klass, "unterminated_substring", bug_str_unterminated_substring, 2);
    rb_define_singleton_method(klass, "cstr_term", bug_str_s_cstr_term, 1);
    rb_define_singleton_method(klass, "cstr_unterm", bug_str_s_cstr_unterm, 2);
    rb_define_singleton_method(klass, "cstr_term_char", bug_str_s_cstr_term_char, 1);
    rb_define_singleton_method(klass, "cstr_noembed", bug_str_s_cstr_noembed, 1);
    rb_define_singleton_method(klass, "cstr_embedded?", bug_str_s_cstr_embedded_p, 1);
    rb_define_singleton_method(klass, "rb_str_new_frozen", bug_str_s_rb_str_new_frozen, 1);
}
