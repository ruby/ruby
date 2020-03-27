/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Public APIs related to ::rb_cString.
 */
#ifndef  RUBY3_INTERN_STRING_H
#define  RUBY3_INTERN_STRING_H
#include "ruby/3/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#include "ruby/3/attr/nonnull.h"
#include "ruby/3/attr/pure.h"
#include "ruby/3/constant_p.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"
#include "ruby/3/variable.h" /* rb_gvar_setter_t */
#include "ruby/st.h"         /* st_index_t */

RUBY3_SYMBOL_EXPORT_BEGIN()

/* string.c */
VALUE rb_str_new(const char*, long);
VALUE rb_str_new_cstr(const char*);
VALUE rb_str_new_shared(VALUE);
VALUE rb_str_new_frozen(VALUE);
VALUE rb_str_new_with_class(VALUE, const char*, long);
VALUE rb_tainted_str_new_cstr(const char*);
VALUE rb_tainted_str_new(const char*, long);
VALUE rb_external_str_new(const char*, long);
VALUE rb_external_str_new_cstr(const char*);
VALUE rb_locale_str_new(const char*, long);
VALUE rb_locale_str_new_cstr(const char*);
VALUE rb_filesystem_str_new(const char*, long);
VALUE rb_filesystem_str_new_cstr(const char*);
VALUE rb_str_buf_new(long);
VALUE rb_str_buf_new_cstr(const char*);
VALUE rb_str_buf_new2(const char*);
VALUE rb_str_tmp_new(long);
VALUE rb_usascii_str_new(const char*, long);
VALUE rb_usascii_str_new_cstr(const char*);
VALUE rb_utf8_str_new(const char*, long);
VALUE rb_utf8_str_new_cstr(const char*);
VALUE rb_str_new_static(const char *, long);
VALUE rb_usascii_str_new_static(const char *, long);
VALUE rb_utf8_str_new_static(const char *, long);
void rb_str_free(VALUE);
void rb_str_shared_replace(VALUE, VALUE);
VALUE rb_str_buf_append(VALUE, VALUE);
VALUE rb_str_buf_cat(VALUE, const char*, long);
VALUE rb_str_buf_cat2(VALUE, const char*);
VALUE rb_str_buf_cat_ascii(VALUE, const char*);
VALUE rb_obj_as_string(VALUE);
VALUE rb_check_string_type(VALUE);
void rb_must_asciicompat(VALUE);
VALUE rb_str_dup(VALUE);
VALUE rb_str_resurrect(VALUE str);
VALUE rb_str_locktmp(VALUE);
VALUE rb_str_unlocktmp(VALUE);
VALUE rb_str_dup_frozen(VALUE);
#define rb_str_dup_frozen rb_str_new_frozen
VALUE rb_str_plus(VALUE, VALUE);
VALUE rb_str_times(VALUE, VALUE);
long rb_str_sublen(VALUE, long);
VALUE rb_str_substr(VALUE, long, long);
VALUE rb_str_subseq(VALUE, long, long);
char *rb_str_subpos(VALUE, long, long*);
void rb_str_modify(VALUE);
void rb_str_modify_expand(VALUE, long);
VALUE rb_str_freeze(VALUE);
void rb_str_set_len(VALUE, long);
VALUE rb_str_resize(VALUE, long);
VALUE rb_str_cat(VALUE, const char*, long);
VALUE rb_str_cat_cstr(VALUE, const char*);
VALUE rb_str_cat2(VALUE, const char*);
VALUE rb_str_append(VALUE, VALUE);
VALUE rb_str_concat(VALUE, VALUE);
st_index_t rb_memhash(const void *ptr, long len);
st_index_t rb_hash_start(st_index_t);
st_index_t rb_hash_uint32(st_index_t, uint32_t);
st_index_t rb_hash_uint(st_index_t, st_index_t);
st_index_t rb_hash_end(st_index_t);
#define rb_hash_uint32(h, i) st_hash_uint32((h), (i))
#define rb_hash_uint(h, i) st_hash_uint((h), (i))
#define rb_hash_end(h) st_hash_end(h)
st_index_t rb_str_hash(VALUE);
int rb_str_hash_cmp(VALUE,VALUE);
int rb_str_comparable(VALUE, VALUE);
int rb_str_cmp(VALUE, VALUE);
VALUE rb_str_equal(VALUE str1, VALUE str2);
VALUE rb_str_drop_bytes(VALUE, long);
void rb_str_update(VALUE, long, long, VALUE);
VALUE rb_str_replace(VALUE, VALUE);
VALUE rb_str_inspect(VALUE);
VALUE rb_str_dump(VALUE);
VALUE rb_str_split(VALUE, const char*);
rb_gvar_setter_t rb_str_setter;
VALUE rb_str_intern(VALUE);
VALUE rb_sym_to_s(VALUE);
long rb_str_strlen(VALUE);
VALUE rb_str_length(VALUE);
long rb_str_offset(VALUE, long);
RUBY3_ATTR_PURE()
size_t rb_str_capacity(VALUE);
VALUE rb_str_ellipsize(VALUE, long);
VALUE rb_str_scrub(VALUE, VALUE);
VALUE rb_str_succ(VALUE);

RUBY3_ATTR_NONNULL(())
static inline long
ruby3_strlen(const char *str)
{
    return RUBY3_CAST((long)strlen(str));
}

static inline VALUE
ruby3_str_new(const char *str, long len)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_str_new(str, len);
    }
    else if  /* constexpr */ (! RUBY3_CONSTANT_P(len)) {
        return rb_str_new(str, len);
    }
    else {
        return rb_str_new_static(str, len);
    }
}

static inline VALUE
ruby3_str_new_cstr(const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_str_new_cstr(str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_str_new_static(str, len);
    }
}

static inline VALUE
ruby3_usascii_str_new(const char *str, long len)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_usascii_str_new(str, len);
    }
    else if  /* constexpr */ (! RUBY3_CONSTANT_P(len)) {
        return rb_usascii_str_new(str, len);
    }
    else {
        return rb_usascii_str_new_static(str, len);
    }
}

static inline VALUE
ruby3_utf8_str_new(const char *str, long len)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_utf8_str_new(str, len);
    }
    else if  /* constexpr */ (! RUBY3_CONSTANT_P(len)) {
        return rb_utf8_str_new(str, len);
    }
    else {
        return rb_utf8_str_new_static(str, len);
    }
}

static inline VALUE
ruby3_tainted_str_new_cstr(const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_tainted_str_new_cstr(str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_tainted_str_new(str, len);
    }
}

static inline VALUE
ruby3_usascii_str_new_cstr(const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_usascii_str_new_cstr(str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_usascii_str_new_static(str, len);
    }
}

static inline VALUE
ruby3_utf8_str_new_cstr(const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_utf8_str_new_cstr(str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_utf8_str_new_static(str, len);
    }
}

static inline VALUE
ruby3_external_str_new_cstr(const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_external_str_new_cstr(str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_external_str_new(str, len);
    }
}

static inline VALUE
ruby3_locale_str_new_cstr(const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_locale_str_new_cstr(str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_locale_str_new(str, len);
    }
}

static inline VALUE
ruby3_str_buf_new_cstr(const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_str_buf_new_cstr(str);
    }
    else {
        long len = ruby3_strlen(str);
        VALUE buf = rb_str_buf_new(len);
        return rb_str_buf_cat(buf, str, len);
    }
}

static inline VALUE
ruby3_str_cat_cstr(VALUE buf, const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_str_cat_cstr(buf, str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_str_cat(buf, str, len);
    }
}

static inline VALUE
ruby3_exc_new_cstr(VALUE exc, const char *str)
{
    if /* constexpr */ (! RUBY3_CONSTANT_P(str)) {
        return rb_exc_new_cstr(exc, str);
    }
    else {
        long len = ruby3_strlen(str);
        return rb_exc_new(exc, str, len);
    }
}

#define rb_str_new ruby3_str_new
#define rb_str_new_cstr ruby3_str_new_cstr
#define rb_usascii_str_new ruby3_usascii_str_new
#define rb_utf8_str_new ruby3_utf8_str_new
#define rb_tainted_str_new_cstr ruby3_tainted_str_new_cstr
#define rb_usascii_str_new_cstr ruby3_usascii_str_new_cstr
#define rb_utf8_str_new_cstr ruby3_utf8_str_new_cstr
#define rb_external_str_new_cstr ruby3_external_str_new_cstr
#define rb_locale_str_new_cstr ruby3_locale_str_new_cstr
#define rb_str_buf_new_cstr ruby3_str_buf_new_cstr
#define rb_str_cat_cstr ruby3_str_cat_cstr
#define rb_exc_new_cstr ruby3_exc_new_cstr
#define rb_str_new2 rb_str_new_cstr
#define rb_str_new3 rb_str_new_shared
#define rb_str_new4 rb_str_new_frozen
#define rb_str_new5 rb_str_new_with_class
#define rb_tainted_str_new2 rb_tainted_str_new_cstr
#define rb_str_buf_new2 rb_str_buf_new_cstr
#define rb_usascii_str_new2 rb_usascii_str_new_cstr
#define rb_str_buf_cat rb_str_cat
#define rb_str_buf_cat2 rb_str_cat_cstr
#define rb_str_cat2 rb_str_cat_cstr
#define rb_strlen_lit(str) (sizeof(str "") - 1)
#define rb_str_new_lit(str) rb_str_new_static((str), rb_strlen_lit(str))
#define rb_usascii_str_new_lit(str) rb_usascii_str_new_static((str), rb_strlen_lit(str))
#define rb_utf8_str_new_lit(str) rb_utf8_str_new_static((str), rb_strlen_lit(str))
#define rb_enc_str_new_lit(str, enc) rb_enc_str_new_static((str), rb_strlen_lit(str), (enc))
#define rb_str_new_literal(str) rb_str_new_lit(str)
#define rb_usascii_str_new_literal(str) rb_usascii_str_new_lit(str)
#define rb_utf8_str_new_literal(str) rb_utf8_str_new_lit(str)
#define rb_enc_str_new_literal(str, enc) rb_enc_str_new_lit(str, enc)

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_INTERN_STRING_H */
