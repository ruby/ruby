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
 * @brief      Arithmetic conversion between C's `long` and Ruby's.
 *
 * ### Q&A ###
 *
 * - Q: Why are INT2FIX etc. here, not in `int.h`?
 *
 * - A: Because they  are in fact  handling `long`.   It seems someone  did not
 *      understand the difference of `int`  and `long` when they designed those
 *      macros.
 */
#ifndef  RUBY3_ARITHMETIC_LONG_H
#define  RUBY3_ARITHMETIC_LONG_H
#include "ruby/3/config.h"
#include "ruby/3/special_consts.h"
#include "ruby/3/arithmetic/fixnum.h"
#include "ruby/3/arithmetic/intptr_t.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/special_consts.h"
#include "ruby/3/value.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#define RB_INT2FIX(i) (((VALUE)(i))<<1 | RUBY_FIXNUM_FLAG)
#define INT2FIX(i) RB_INT2FIX(i)
#define RB_LONG2FIX(i) RB_INT2FIX(i)
#define LONG2FIX(i) RB_INT2FIX(i)
#define rb_fix_new(v) RB_INT2FIX(v)

#if SIZEOF_INT < SIZEOF_VALUE
NORETURN(void rb_out_of_int(SIGNED_VALUE num));
#endif

#if SIZEOF_INT < SIZEOF_LONG
static inline int
rb_long2int_inline(long n)
{
    int i = (int)n;
    if ((long)i != n)
        rb_out_of_int(n);

    return i;
}
#define rb_long2int(n) rb_long2int_inline(n)
#else
#define rb_long2int(n) ((int)(n))
#endif

#define RB_FIX2LONG(x) ((long)RSHIFT((SIGNED_VALUE)(x),1))
static inline long
rb_fix2long(VALUE x)
{
    return RB_FIX2LONG(x);
}
#define RB_FIX2ULONG(x) ((unsigned long)RB_FIX2LONG(x))
static inline unsigned long
rb_fix2ulong(VALUE x)
{
    return RB_FIX2ULONG(x);
}
#define FIX2LONG(x) RB_FIX2LONG(x)
#define FIX2ULONG(x) RB_FIX2ULONG(x)

long rb_num2long(VALUE);
unsigned long rb_num2ulong(VALUE);
static inline long
rb_num2long_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return RB_FIX2LONG(x);
    else
        return rb_num2long(x);
}
#define RB_NUM2LONG(x) rb_num2long_inline(x)
#define NUM2LONG(x) RB_NUM2LONG(x)
static inline unsigned long
rb_num2ulong_inline(VALUE x)
{
    if (RB_FIXNUM_P(x))
        return RB_FIX2ULONG(x);
    else
        return rb_num2ulong(x);
}
#define RB_NUM2ULONG(x) rb_num2ulong_inline(x)
#define NUM2ULONG(x) RB_NUM2ULONG(x)

static inline VALUE
rb_long2num_inline(long v)
{
    if (RB_FIXABLE(v))
        return RB_LONG2FIX(v);
    else
        return rb_int2big(v);
}
#define RB_LONG2NUM(x) rb_long2num_inline(x)

static inline VALUE
rb_ulong2num_inline(unsigned long v)
{
    if (RB_POSFIXABLE(v))
        return RB_LONG2FIX(v);
    else
        return rb_uint2big(v);
}
#define RB_ULONG2NUM(x) rb_ulong2num_inline(x)

#define LONG2NUM(x) RB_LONG2NUM(x)
#define ULONG2NUM(x) RB_ULONG2NUM(x)

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_ARITHMETIC_LONG_H */
