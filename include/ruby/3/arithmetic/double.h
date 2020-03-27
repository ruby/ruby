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
 * @brief      Arithmetic conversion between C's `double` and Ruby's.
 */
#ifndef  RUBY3_ARITHMETIC_DOUBLE_H
#define  RUBY3_ARITHMETIC_DOUBLE_H
#include "ruby/3/attr/pure.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"

#define NUM2DBL      rb_num2dbl
#define RFLOAT_VALUE rb_float_value
#define DBL2NUM      rb_float_new

RUBY3_SYMBOL_EXPORT_BEGIN()
double rb_num2dbl(VALUE);
RUBY3_ATTR_PURE()
double rb_float_value(VALUE);
VALUE rb_float_new(double);
VALUE rb_float_new_in_heap(double);
RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_ARITHMETIC_DOUBLE_H */
