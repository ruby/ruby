#ifndef RBIMPL_ARITHMETIC_LONG_LONG_H                /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_LONG_LONG_H
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
 * @brief      Arithmetic conversion between C's `long long` and Ruby's.
 */
#include "ruby/internal/value.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"
#include "ruby/backward/2/long_long.h"

#define RB_LL2NUM  rb_ll2inum
#define RB_ULL2NUM rb_ull2inum
#define LL2NUM     RB_LL2NUM
#define ULL2NUM    RB_ULL2NUM
#define RB_NUM2LL  rb_num2ll_inline
#define RB_NUM2ULL rb_num2ull
#define NUM2LL     RB_NUM2LL
#define NUM2ULL    RB_NUM2ULL

RBIMPL_SYMBOL_EXPORT_BEGIN()
VALUE rb_ll2inum(LONG_LONG);
VALUE rb_ull2inum(unsigned LONG_LONG);
LONG_LONG rb_num2ll(VALUE);
unsigned LONG_LONG rb_num2ull(VALUE);
RBIMPL_SYMBOL_EXPORT_END()

static inline LONG_LONG
rb_num2ll_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return RB_FIX2LONG(x);
    else
        return rb_num2ll(x);
}

#endif /* RBIMPL_ARITHMETIC_LONG_LONG_H */
