#ifndef RBIMPL_INTERN_DECIMAL_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_DECIMAL_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met. Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon. They could
 *             rapidly appear then vanish. The name (path) of this header file
 *             is also an  implementation detail. Do not expect  it to persist
 *             at the place it is now. Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Public APIs related to ::rb_cDecimal.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

#if defined(HAVE_INT128_T) && SIZEOF_VALUE >= 8
/* decimal.c */

/**
 * Converts various values into a Decimal.
 *
 * @param[in]  val                Value to convert (Integer, Float, String,
 *                                Rational or Decimal).
 * @exception  rb_eTypeError      Passed something not convertible.
 * @exception  rb_eArgError       String is not a valid decimal representation.
 * @exception  rb_eRangeError     Value overflows 128-bit scaled integer.
 * @return     An instance of ::rb_cDecimal.
 */
VALUE rb_Decimal(VALUE val);

/**
 * Constructs a Decimal from a string representation.
 *
 * @param[in]  str                An instance of ::rb_cString.
 * @exception  rb_eArgError       `str` is not a valid decimal string.
 * @exception  rb_eRangeError     Value overflows 128-bit scaled integer.
 * @return     An instance of ::rb_cDecimal.
 */
VALUE rb_decimal_from_str(VALUE str);
#endif

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_DECIMAL_H */
