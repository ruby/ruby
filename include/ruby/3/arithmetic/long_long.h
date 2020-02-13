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
 * @brief      Arithmetic conversion between C's `long long` and Ruby's.
 */
#ifndef  RUBY3_ARITHMETIC_LONG_LONG_H
#define  RUBY3_ARITHMETIC_LONG_LONG_H
#include "ruby/3/config.h"
#include "ruby/3/value.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/special_consts.h"
#include "ruby/backward/2/long_long.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#ifdef HAVE_LONG_LONG
VALUE rb_ll2inum(LONG_LONG);
#define LL2NUM(v) rb_ll2inum(v)
VALUE rb_ull2inum(unsigned LONG_LONG);
#define ULL2NUM(v) rb_ull2inum(v)
#endif

#ifdef HAVE_LONG_LONG
LONG_LONG rb_num2ll(VALUE);
unsigned LONG_LONG rb_num2ull(VALUE);
static inline LONG_LONG
rb_num2ll_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return RB_FIX2LONG(x);
    else
        return rb_num2ll(x);
}
# define RB_NUM2LL(x) rb_num2ll_inline(x)
# define RB_NUM2ULL(x) rb_num2ull(x)
# define NUM2LL(x) RB_NUM2LL(x)
# define NUM2ULL(x) RB_NUM2ULL(x)
#endif

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_ARITHMETIC_LONG_LONG_H */
