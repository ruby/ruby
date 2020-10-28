#ifndef RBIMPL_INTERN_BIGNUM_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_BIGNUM_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
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
 * @brief      Public APIs related to so-called rb_cBignum.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/long_long.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* bignum.c */
VALUE rb_big_new(size_t, int);
int rb_bigzero_p(VALUE x);
VALUE rb_big_clone(VALUE);
void rb_big_2comp(VALUE);
VALUE rb_big_norm(VALUE);
void rb_big_resize(VALUE big, size_t len);
VALUE rb_cstr_to_inum(const char*, int, int);
VALUE rb_str_to_inum(VALUE, int, int);
VALUE rb_cstr2inum(const char*, int);
VALUE rb_str2inum(VALUE, int);
VALUE rb_big2str(VALUE, int);
long rb_big2long(VALUE);
#define rb_big2int(x) rb_big2long(x)
unsigned long rb_big2ulong(VALUE);
#define rb_big2uint(x) rb_big2ulong(x)
#if HAVE_LONG_LONG
LONG_LONG rb_big2ll(VALUE);
unsigned LONG_LONG rb_big2ull(VALUE);
#endif  /* HAVE_LONG_LONG */
void rb_big_pack(VALUE val, unsigned long *buf, long num_longs);
VALUE rb_big_unpack(unsigned long *buf, long num_longs);
int rb_uv_to_utf8(char[6],unsigned long);
VALUE rb_dbl2big(double);
double rb_big2dbl(VALUE);
VALUE rb_big_cmp(VALUE, VALUE);
VALUE rb_big_eq(VALUE, VALUE);
VALUE rb_big_eql(VALUE, VALUE);
VALUE rb_big_plus(VALUE, VALUE);
VALUE rb_big_minus(VALUE, VALUE);
VALUE rb_big_mul(VALUE, VALUE);
VALUE rb_big_div(VALUE, VALUE);
VALUE rb_big_idiv(VALUE, VALUE);
VALUE rb_big_modulo(VALUE, VALUE);
VALUE rb_big_divmod(VALUE, VALUE);
VALUE rb_big_pow(VALUE, VALUE);
VALUE rb_big_and(VALUE, VALUE);
VALUE rb_big_or(VALUE, VALUE);
VALUE rb_big_xor(VALUE, VALUE);
VALUE rb_big_lshift(VALUE, VALUE);
VALUE rb_big_rshift(VALUE, VALUE);

/* For rb_integer_pack and rb_integer_unpack: */
/* "MS" in MSWORD and MSBYTE means "most significant" */
/* "LS" in LSWORD and LSBYTE means "least significant" */
#define INTEGER_PACK_MSWORD_FIRST       0x01
#define INTEGER_PACK_LSWORD_FIRST       0x02
#define INTEGER_PACK_MSBYTE_FIRST       0x10
#define INTEGER_PACK_LSBYTE_FIRST       0x20
#define INTEGER_PACK_NATIVE_BYTE_ORDER  0x40
#define INTEGER_PACK_2COMP              0x80
#define INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION     0x400
/* For rb_integer_unpack: */
#define INTEGER_PACK_FORCE_BIGNUM       0x100
#define INTEGER_PACK_NEGATIVE           0x200
/* Combinations: */
#define INTEGER_PACK_LITTLE_ENDIAN \
    (INTEGER_PACK_LSWORD_FIRST | \
     INTEGER_PACK_LSBYTE_FIRST)
#define INTEGER_PACK_BIG_ENDIAN \
    (INTEGER_PACK_MSWORD_FIRST | \
     INTEGER_PACK_MSBYTE_FIRST)
int rb_integer_pack(VALUE val, void *words, size_t numwords, size_t wordsize, size_t nails, int flags);
VALUE rb_integer_unpack(const void *words, size_t numwords, size_t wordsize, size_t nails, int flags);
size_t rb_absint_size(VALUE val, int *nlz_bits_ret);
size_t rb_absint_numwords(VALUE val, size_t word_numbits, size_t *nlz_bits_ret);
int rb_absint_singlebit_p(VALUE val);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_BIGNUM_H */
