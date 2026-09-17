#ifndef RBIMPL_ARITHMETIC_LONG_T_H                   /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_LONG_T_H
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
 * @brief      Arithmetic conversion between ::rb_long_t and Ruby's.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/assume.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/value.h"

#define LONGT2NUM    RB_LONGT2NUM         /**< @old{RB_LONGT2NUM} */
#define NUM2LONGT    RB_NUM2LONGT         /**< @old{RB_NUM2LONGT} */
#define ULONGT2NUM   RB_ULONGT2NUM        /**< @old{RB_ULONGT2NUM} */
#define rb_longt2int rb_longt2int_inline  /**< @alias{rb_longt2int_inline} */

/** Converts a ::rb_long_t into an instance of ::rb_cInteger. */
#define RB_LONGT2NUM RB_LONG2NUM

/** Converts an instance of ::rb_cNumeric into ::rb_long_t. */
#define RB_NUM2LONGT RB_NUM2LONG

/** Converts a ::rb_ulong_t into an instance of ::rb_cInteger. */
#define RB_ULONGT2NUM RB_ULONG2NUM

/**
 * Checks if `int` can hold the given integer.
 *
 * @param[in]  n               Arbitrary ::rb_long_t value.
 * @exception  rb_eRangeError  `n` is out of range of `int`.
 * @return     Identical value of type `int`
 */
static inline int
rb_longt2int_inline(rb_long_t n)
{
    int i = RBIMPL_CAST((int)n);

    if /* constexpr */ (sizeof(rb_long_t) <= sizeof(int)) {
        RBIMPL_ASSUME(i == n);
    }

    if (i != n)
        rb_out_of_int(n);

    return i;
}

#endif /* RBIMPL_ARITHMETIC_LONG_T_H */
