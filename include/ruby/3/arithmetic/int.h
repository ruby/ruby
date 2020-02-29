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
 * @brief      Arithmetic conversion between C's `int` and Ruby's.
 */
#ifndef  RUBY3_ARITHMETIC_INT_H
#define  RUBY3_ARITHMETIC_INT_H
#include "ruby/3/config.h"
#include "ruby/3/arithmetic/fixnum.h"
#include "ruby/3/arithmetic/intptr_t.h"
#include "ruby/3/arithmetic/long.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/special_consts.h"
#include "ruby/3/value.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

#if SIZEOF_INT < SIZEOF_LONG
long rb_num2int(VALUE);
long rb_fix2int(VALUE);
#define RB_FIX2INT(x) ((int)rb_fix2int((VALUE)(x)))

static inline int
rb_num2int_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return (int)rb_fix2int(x);
    else
        return (int)rb_num2int(x);
}
#define RB_NUM2INT(x) rb_num2int_inline(x)

unsigned long rb_num2uint(VALUE);
#define RB_NUM2UINT(x) ((unsigned int)rb_num2uint(x))
unsigned long rb_fix2uint(VALUE);
#define RB_FIX2UINT(x) ((unsigned int)rb_fix2uint(x))
#else /* SIZEOF_INT < SIZEOF_LONG */
#define RB_NUM2INT(x) ((int)RB_NUM2LONG(x))
#define RB_NUM2UINT(x) ((unsigned int)RB_NUM2ULONG(x))
#define RB_FIX2INT(x) ((int)RB_FIX2LONG(x))
#define RB_FIX2UINT(x) ((unsigned int)RB_FIX2ULONG(x))
#endif /* SIZEOF_INT < SIZEOF_LONG */
#define NUM2INT(x)  RB_NUM2INT(x)
#define NUM2UINT(x) RB_NUM2UINT(x)
#define FIX2INT(x)  RB_FIX2INT(x)
#define FIX2UINT(x) RB_FIX2UINT(x)

#if SIZEOF_INT < SIZEOF_LONG
# define RB_INT2NUM(v) RB_INT2FIX((int)(v))
# define RB_UINT2NUM(v) RB_LONG2FIX((unsigned int)(v))
#else
static inline VALUE
rb_int2num_inline(int v)
{
    if (RB_FIXABLE(v))
        return RB_INT2FIX(v);
    else
        return rb_int2big(v);
}
#define RB_INT2NUM(x) rb_int2num_inline(x)

static inline VALUE
rb_uint2num_inline(unsigned int v)
{
    if (RB_POSFIXABLE(v))
        return RB_LONG2FIX(v);
    else
        return rb_uint2big(v);
}
#define RB_UINT2NUM(x) rb_uint2num_inline(x)
#endif
#define INT2NUM(x) RB_INT2NUM(x)
#define UINT2NUM(x) RB_UINT2NUM(x)

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_ARITHMETIC_INT_H */
