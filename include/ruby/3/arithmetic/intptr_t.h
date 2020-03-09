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
 * @brief      Arithmetic conversion between C's `intptr_t` and Ruby's.
 */
#ifndef  RUBY3_ARITHMETIC_INTPTR_T_H
#define  RUBY3_ARITHMETIC_INTPTR_T_H
#include "ruby/3/config.h"

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#include "ruby/3/value.h"
#include "ruby/3/dllexport.h"

#define rb_int_new  rb_int2inum
#define rb_uint_new rb_uint2inum

RUBY3_SYMBOL_EXPORT_BEGIN()
VALUE rb_int2big(intptr_t i);
VALUE rb_int2inum(intptr_t i);
VALUE rb_uint2big(uintptr_t i);
VALUE rb_uint2inum(uintptr_t i);
RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_ARITHMETIC_INTPTR_T_H */
