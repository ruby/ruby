#ifndef RBIMPL_ARITHMETIC_INT_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_INT_H
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
 * @brief      Arithmetic conversion between C's `int` and Ruby's.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/arithmetic/fixnum.h"
#include "ruby/internal/arithmetic/intptr_t.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/compiler_is.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/value.h"
#include "ruby/internal/warning_push.h"
#include "ruby/assert.h"

#define RB_INT2NUM  rb_int2num_inline
#define RB_NUM2INT  rb_num2int_inline
#define RB_UINT2NUM rb_uint2num_inline

#define FIX2INT    RB_FIX2INT
#define FIX2UINT   RB_FIX2UINT
#define INT2NUM    RB_INT2NUM
#define NUM2INT    RB_NUM2INT
#define NUM2UINT   RB_NUM2UINT
#define UINT2NUM   RB_UINT2NUM

/** @cond INTERNAL_MACRO */
#define RB_FIX2INT  RB_FIX2INT
#define RB_NUM2UINT RB_NUM2UINT
#define RB_FIX2UINT RB_FIX2UINT
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()
long rb_num2int(VALUE);
long rb_fix2int(VALUE);
unsigned long rb_num2uint(VALUE);
unsigned long rb_fix2uint(VALUE);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_ARTIFICIAL()
static inline int
RB_FIX2INT(VALUE x)
{
    /* "FIX2INT raises a  TypeError if passed nil", says rubyspec.  Not sure if
     * that is a desired behaviour but just preserve backwards compatilibily.
     */
#if 0
    RBIMPL_ASSERT_OR_ASSUME(RB_FIXNUM_P(x));
#endif
    long ret;

    if /* constexpr */ (sizeof(int) < sizeof(long)) {
        ret = rb_fix2int(x);
    }
    else {
        ret = RB_FIX2LONG(x);
    }

    return RBIMPL_CAST((int)ret);
}

static inline int
rb_num2int_inline(VALUE x)
{
    long ret;

    if /* constexpr */ (sizeof(int) == sizeof(long)) {
        ret = RB_NUM2LONG(x);
    }
    else if (RB_FIXNUM_P(x)) {
        ret = rb_fix2int(x);
    }
    else {
        ret = rb_num2int(x);
    }

    return RBIMPL_CAST((int)ret);
}

RBIMPL_ATTR_ARTIFICIAL()
static inline unsigned int
RB_NUM2UINT(VALUE x)
{
    unsigned long ret;

    if /* constexpr */ (sizeof(int) < sizeof(long)) {
        ret = rb_num2uint(x);
    }
    else {
        ret = RB_NUM2ULONG(x);
    }

    return RBIMPL_CAST((unsigned int)ret);
}

RBIMPL_ATTR_ARTIFICIAL()
static inline unsigned int
RB_FIX2UINT(VALUE x)
{
#if 0 /* Ditto for RB_FIX2INT. */
    RBIMPL_ASSERT_OR_ASSUME(RB_FIXNUM_P(x));
#endif
    unsigned long ret;

    if /* constexpr */ (sizeof(int) < sizeof(long)) {
        ret = rb_fix2uint(x);
    }
    else {
        ret = RB_FIX2ULONG(x);
    }

    return RBIMPL_CAST((unsigned int)ret);
}

RBIMPL_WARNING_PUSH()
#if RBIMPL_COMPILER_IS(GCC)
RBIMPL_WARNING_IGNORED(-Wtype-limits) /* We can ignore them here. */
#elif RBIMPL_HAS_WARNING("-Wtautological-constant-out-of-range-compare")
RBIMPL_WARNING_IGNORED(-Wtautological-constant-out-of-range-compare)
#endif

static inline VALUE
rb_int2num_inline(int v)
{
    if (RB_FIXABLE(v))
        return RB_INT2FIX(v);
    else
        return rb_int2big(v);
}

static inline VALUE
rb_uint2num_inline(unsigned int v)
{
    if (RB_POSFIXABLE(v))
        return RB_LONG2FIX(v);
    else
        return rb_uint2big(v);
}

RBIMPL_WARNING_POP()

#endif /* RBIMPL_ARITHMETIC_INT_H */
