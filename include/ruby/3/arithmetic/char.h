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
 * @brief      Arithmetic conversion between C's `char` and Ruby's.
 */
#ifndef  RUBY3_ARITHMETIC_CHAR_H
#define  RUBY3_ARITHMETIC_CHAR_H
#include "ruby/3/arithmetic/int.h"
#include "ruby/3/core/rstring.h"
#include "ruby/3/value_type.h"

static inline char
rb_num2char_inline(VALUE x)
{
    if (RB_TYPE_P(x, RUBY_T_STRING) && (RSTRING_LEN(x)>=1))
        return RSTRING_PTR(x)[0];
    else
        return (char)(NUM2INT(x) & 0xff);
}
#define RB_NUM2CHR(x) rb_num2char_inline(x)
#define RB_CHR2FIX(x) RB_INT2FIX((long)((x)&0xff))

#define NUM2CHR(x) RB_NUM2CHR(x)
#define CHR2FIX(x) RB_CHR2FIX(x)

#endif /* RUBY3_ARITHMETIC_CHAR_H */
