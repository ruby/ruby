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
 * @brief      Arithmetic conversion between C's `st_data_t` and Ruby's.
 */
#ifndef  RUBY3_ARITHMERIC_ST_DATA_T_H
#define  RUBY3_ARITHMERIC_ST_DATA_T_H
#include "ruby/3/arithmetic/fixnum.h"
#include "ruby/3/arithmetic/long.h"
#include "ruby/3/attr/artificial.h"
#include "ruby/3/attr/const.h"
#include "ruby/3/attr/constexpr.h"
#include "ruby/3/cast.h"
#include "ruby/3/value.h"
#include "ruby/assert.h"
#include "ruby/st.h"

#define ST2FIX    RB_ST2FIX
/** @cond INTERNAL_MACRO */
#define RB_ST2FIX RB_ST2FIX
/** @endcond */

RUBY3_ATTR_CONST_ON_NDEBUG()
RUBY3_ATTR_CONSTEXPR_ON_NDEBUG(CXX14)
RUBY3_ATTR_ARTIFICIAL()
/* See also [ruby-core:84395] [Bug #14218] [ruby-core:82687] [Bug #13877] */
static inline VALUE
RB_ST2FIX(st_data_t i)
{
    SIGNED_VALUE x = i;

    if (x >= 0) {
        x &= RUBY_FIXNUM_MAX;
    }
    else {
        x |= RUBY_FIXNUM_MIN;
    }

    RUBY3_ASSERT_OR_ASSUME(RB_FIXABLE(x));
    unsigned long y = RUBY3_CAST((unsigned long)x);
    return RB_LONG2FIX(y);
}

#endif /* RUBY3_ARITHMERIC_ST_DATA_T_H */
