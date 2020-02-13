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
#include "ruby/3/value.h"
#include "ruby/3/dllexport.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

double rb_num2dbl(VALUE);
#define NUM2DBL(x) rb_num2dbl((VALUE)(x))

PUREFUNC(double rb_float_value(VALUE));
VALUE rb_float_new(double);
VALUE rb_float_new_in_heap(double);

#define RFLOAT_VALUE(v) rb_float_value(v)
#define DBL2NUM(dbl)  rb_float_new(dbl)

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_ARITHMETIC_DOUBLE_H */
