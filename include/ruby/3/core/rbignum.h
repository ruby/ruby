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
 * @brief      Routines to manipulate struct ::RBignum.
 */
#ifndef  RUBY3_RBIGNUM_H
#define  RUBY3_RBIGNUM_H
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"
#include "ruby/3/value_type.h"
#include "ruby/3/stdbool.h"

#define RBIGNUM_SIGN rb_big_sign

/** @cond INTERNAL_MACRO */
#define RBIGNUM_POSITIVE_P RBIGNUM_POSITIVE_P
#define RBIGNUM_NEGATIVE_P RBIGNUM_NEGATIVE_P
/** @endcond */

RUBY3_SYMBOL_EXPORT_BEGIN()
int rb_big_sign(VALUE num);
RUBY3_SYMBOL_EXPORT_END()

static inline bool
RBIGNUM_POSITIVE_P(VALUE b) {
    RUBY3_ASSERT_TYPE(b, RUBY_T_BIGNUM);
    return RBIGNUM_SIGN(b);
}

static inline bool
RBIGNUM_NEGATIVE_P(VALUE b) {
    RUBY3_ASSERT_TYPE(b, RUBY_T_BIGNUM);
    return ! RBIGNUM_POSITIVE_P(b);
}

#endif /* RUBY3_RBIGNUM_H */
