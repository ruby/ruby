#ifndef INTERNAL_STRING_H /* -*- C -*- */
#define INTERNAL_STRING_H
/**
 * @file
 * @brief      Internal header for String.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */


/* string.c */
VALUE rb_fstring(VALUE);
VALUE rb_fstring_new(const char *ptr, long len);
#define rb_fstring_lit(str) rb_fstring_new((str), rb_strlen_lit(str))
#define rb_fstring_literal(str) rb_fstring_lit(str)
VALUE rb_fstring_cstr(const char *str);
#ifdef HAVE_BUILTIN___BUILTIN_CONSTANT_P
# define rb_fstring_cstr(str) RB_GNUC_EXTENSION_BLOCK(  \
    (__builtin_constant_p(str)) ?               \
        rb_fstring_new((str), (long)strlen(str)) : \
        rb_fstring_cstr(str) \
)
#endif
#ifdef RUBY_ENCODING_H
VALUE rb_fstring_enc_new(const char *ptr, long len, rb_encoding *enc);
#define rb_fstring_enc_lit(str, enc) rb_fstring_enc_new((str), rb_strlen_lit(str), (enc))
#define rb_fstring_enc_literal(str, enc) rb_fstring_enc_lit(str, enc)
#endif
int rb_str_buf_cat_escaped_char(VALUE result, unsigned int c, int unicode_p);
int rb_str_symname_p(VALUE);
VALUE rb_str_quote_unprintable(VALUE);
VALUE rb_id_quote_unprintable(ID);
#define QUOTE(str) rb_str_quote_unprintable(str)
#define QUOTE_ID(id) rb_id_quote_unprintable(id)
char *rb_str_fill_terminator(VALUE str, const int termlen);
void rb_str_change_terminator_length(VALUE str, const int oldtermlen, const int termlen);
VALUE rb_str_locktmp_ensure(VALUE str, VALUE (*func)(VALUE), VALUE arg);
VALUE rb_str_chomp_string(VALUE str, VALUE chomp);
#ifdef RUBY_ENCODING_H
VALUE rb_external_str_with_enc(VALUE str, rb_encoding *eenc);
VALUE rb_str_cat_conv_enc_opts(VALUE newstr, long ofs, const char *ptr, long len,
                               rb_encoding *from, int ecflags, VALUE ecopts);
VALUE rb_enc_str_scrub(rb_encoding *enc, VALUE str, VALUE repl);
VALUE rb_str_initialize(VALUE str, const char *ptr, long len, rb_encoding *enc);
#endif
#define STR_NOEMBED      FL_USER1
#define STR_SHARED       FL_USER2 /* = ELTS_SHARED */
#define STR_EMBED_P(str) (!FL_TEST_RAW((str), STR_NOEMBED))
#define STR_SHARED_P(s)  FL_ALL_RAW((s), STR_NOEMBED|ELTS_SHARED)
#define is_ascii_string(str) (rb_enc_str_coderange(str) == ENC_CODERANGE_7BIT)
#define is_broken_string(str) (rb_enc_str_coderange(str) == ENC_CODERANGE_BROKEN)
size_t rb_str_memsize(VALUE);
VALUE rb_sym_proc_call(ID mid, int argc, const VALUE *argv, int kw_splat, VALUE passed_proc);
char *rb_str_to_cstr(VALUE str);
VALUE rb_str_eql(VALUE str1, VALUE str2);
VALUE rb_obj_as_string_result(VALUE str, VALUE obj);
const char *ruby_escaped_char(int c);
VALUE rb_str_opt_plus(VALUE, VALUE);

/* expect tail call optimization */
static inline VALUE
rb_str_eql_internal(const VALUE str1, const VALUE str2)
{
    const long len = RSTRING_LEN(str1);
    const char *ptr1, *ptr2;

    if (len != RSTRING_LEN(str2)) return Qfalse;
    if (!rb_str_comparable(str1, str2)) return Qfalse;
    if ((ptr1 = RSTRING_PTR(str1)) == (ptr2 = RSTRING_PTR(str2)))
        return Qtrue;
    if (memcmp(ptr1, ptr2, len) == 0)
        return Qtrue;
    return Qfalse;
}

RUBY_SYMBOL_EXPORT_BEGIN
/* string.c (export) */
VALUE rb_str_tmp_frozen_acquire(VALUE str);
void rb_str_tmp_frozen_release(VALUE str, VALUE tmp);
#ifdef RUBY_ENCODING_H
/* internal use */
VALUE rb_setup_fake_str(struct RString *fake_str, const char *name, long len, rb_encoding *enc);
#endif
VALUE rb_str_upto_each(VALUE, VALUE, int, int (*each)(VALUE, VALUE), VALUE);
VALUE rb_str_upto_endless_each(VALUE, int (*each)(VALUE, VALUE), VALUE);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_STRING_H */
