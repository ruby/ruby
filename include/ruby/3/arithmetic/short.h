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
 * @brief      Arithmetic conversion between C's `short` and Ruby's.
 *
 * Shyouhei  wonders:  why  there  is   no  SHORT2NUM,  given  there  are  both
 * #USHORT2NUM and #CHR2FIX?
 */
#ifndef  RUBY3_ARITHMETIC_SHORT_H
#define  RUBY3_ARITHMETIC_SHORT_H
#include "ruby/3/value.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/special_consts.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

short rb_num2short(VALUE);
unsigned short rb_num2ushort(VALUE);
short rb_fix2short(VALUE);
unsigned short rb_fix2ushort(VALUE);
#define RB_FIX2SHORT(x) (rb_fix2short((VALUE)(x)))
#define FIX2SHORT(x) RB_FIX2SHORT(x)
static inline short
rb_num2short_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return rb_fix2short(x);
    else
        return rb_num2short(x);
}

#define RB_NUM2SHORT(x) rb_num2short_inline(x)
#define RB_NUM2USHORT(x) rb_num2ushort(x)
#define NUM2SHORT(x) RB_NUM2SHORT(x)
#define NUM2USHORT(x) RB_NUM2USHORT(x)

#define USHORT2NUM(x) RB_INT2FIX(x)

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_ARITHMETIC_SOHRT_H */
