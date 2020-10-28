#ifndef RBIMPL_ARITHMETIC_SHORT_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_SHORT_H
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
 * @brief      Arithmetic conversion between C's `short` and Ruby's.
 *
 * Shyouhei  wonders:  why  there  is   no  SHORT2NUM,  given  there  are  both
 * #USHORT2NUM and #CHR2FIX?
 */
#include "ruby/internal/value.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"

#define RB_NUM2SHORT  rb_num2short_inline
#define RB_NUM2USHORT rb_num2ushort
#define NUM2SHORT     RB_NUM2SHORT
#define NUM2USHORT    RB_NUM2USHORT
#define USHORT2NUM    RB_INT2FIX
#define RB_FIX2SHORT  rb_fix2short
#define FIX2SHORT     RB_FIX2SHORT

RBIMPL_SYMBOL_EXPORT_BEGIN()
short rb_num2short(VALUE);
unsigned short rb_num2ushort(VALUE);
short rb_fix2short(VALUE);
unsigned short rb_fix2ushort(VALUE);
RBIMPL_SYMBOL_EXPORT_END()

static inline short
rb_num2short_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return rb_fix2short(x);
    else
        return rb_num2short(x);
}

#endif /* RBIMPL_ARITHMETIC_SOHRT_H */
