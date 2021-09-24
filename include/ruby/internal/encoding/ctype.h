#ifndef RUBY_INTERNAL_ENCODING_CTYPE_H               /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_CTYPE_H
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
 *             extension libraries.  They could be written in C++98.
 * @brief      Routines to query chacater types.
 */

#include "ruby/onigmo.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/encoding/encoding.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * Queries if  the passed  pointer points  to a newline  character.  What  is a
 * newline and what is not depends on the passed encoding.
 *
 * @param[in]  p          Pointer to a possibly-middle of a character.
 * @param[in]  end        End of the string.
 * @param[in]  enc        Encoding.
 * @retval     0          It isn't.
 * @retval     otherwise  It is.
 */
#define rb_enc_is_newline(p,end,enc)  ONIGENC_IS_MBC_NEWLINE((enc),(UChar*)(p),(UChar*)(end))

/**
 * Queries if the passed  code point is of passed character  type in the passed
 * encoding.  The "character type" here is a set of macros defined in onigmo.h,
 * like `ONIGENC_CTYPE_PUNCT`.
 *
 * @param[in]  c    An `OnigCodePoint` value.
 * @param[in]  t    An `OnigCtype` value.
 * @param[in]  enc  A `rb_encoding*` value.
 * @retval     1    `c` is of `t` in `enc`.
 * @retval     0    Otherwise.
 */
#define rb_enc_isctype(c,t,enc) ONIGENC_IS_CODE_CTYPE((enc),(c),(t))

/**
 * Identical to rb_isascii(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     0    `c` is out of range of ASCII character set in `enc`.
 * @retval     1    Otherwise.
 *
 * @internal
 *
 * `enc` is  ignored.  This  is at least  an intentional  implementation detail
 * (not a bug).  But there could be rooms for future extensions.
 */
#define rb_enc_isascii(c,enc) ONIGENC_IS_CODE_ASCII(c)

/**
 * Identical to rb_isalpha(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "ALPHA".
 * @retval     0    Otherwise.
 */
#define rb_enc_isalpha(c,enc) ONIGENC_IS_CODE_ALPHA((enc),(c))

/**
 * Identical to rb_islower(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "LOWER".
 * @retval     0    Otherwise.
 */
#define rb_enc_islower(c,enc) ONIGENC_IS_CODE_LOWER((enc),(c))

/**
 * Identical to rb_isupper(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "UPPER".
 * @retval     0    Otherwise.
 */
#define rb_enc_isupper(c,enc) ONIGENC_IS_CODE_UPPER((enc),(c))

/**
 * Identical to rb_ispunct(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "PUNCT".
 * @retval     0    Otherwise.
 */
#define rb_enc_ispunct(c,enc) ONIGENC_IS_CODE_PUNCT((enc),(c))

/**
 * Identical to rb_isalnum(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "ANUM".
 * @retval     0    Otherwise.
 */
#define rb_enc_isalnum(c,enc) ONIGENC_IS_CODE_ALNUM((enc),(c))

/**
 * Identical to rb_isprint(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "PRINT".
 * @retval     0    Otherwise.
 */
#define rb_enc_isprint(c,enc) ONIGENC_IS_CODE_PRINT((enc),(c))

/**
 * Identical to rb_isspace(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "PRINT".
 * @retval     0    Otherwise.
 */
#define rb_enc_isspace(c,enc) ONIGENC_IS_CODE_SPACE((enc),(c))

/**
 * Identical to rb_isdigit(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @retval     1    `enc` classifies `c` as "DIGIT".
 * @retval     0    Otherwise.
 */
#define rb_enc_isdigit(c,enc) ONIGENC_IS_CODE_DIGIT((enc),(c))

RBIMPL_ATTR_CONST()
/**
 * Identical to rb_toupper(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @return     `c`'s (Ruby's definition of) upper case counterpart.
 *
 * @internal
 *
 * As `RBIMPL_ATTR_CONST` implies this function ignores `enc`.
 */
int rb_enc_toupper(int c, rb_encoding *enc);

RBIMPL_ATTR_CONST()
/**
 * Identical to rb_tolower(), except it additionally takes an encoding.
 *
 * @param[in]  c    A code point.
 * @param[in]  enc  An encoding.
 * @return     `c`'s (Ruby's definition of) lower case counterpart.
 *
 * @internal
 *
 * As `RBIMPL_ATTR_CONST` implies this function ignores `enc`.
 */
int rb_enc_tolower(int c, rb_encoding *enc);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_CTYPE_H */
