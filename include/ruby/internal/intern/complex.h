#ifndef RBIMPL_INTERN_COMPLEX_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_COMPLEX_H
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
 * @brief      Public APIs related to ::rb_cComplex.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/arithmetic/long.h" /* INT2FIX is here. */

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* complex.c */
VALUE rb_complex_raw(VALUE, VALUE);
#define rb_complex_raw1(x) rb_complex_raw((x), INT2FIX(0))
#define rb_complex_raw2(x,y) rb_complex_raw((x), (y))
VALUE rb_complex_new(VALUE, VALUE);
#define rb_complex_new1(x) rb_complex_new((x), INT2FIX(0))
#define rb_complex_new2(x,y) rb_complex_new((x), (y))
VALUE rb_complex_new_polar(VALUE abs, VALUE arg);
DEPRECATED_BY(rb_complex_new_polar, VALUE rb_complex_polar(VALUE abs, VALUE arg));
VALUE rb_complex_real(VALUE z);
VALUE rb_complex_imag(VALUE z);
VALUE rb_complex_plus(VALUE x, VALUE y);
VALUE rb_complex_minus(VALUE x, VALUE y);
VALUE rb_complex_mul(VALUE x, VALUE y);
VALUE rb_complex_div(VALUE x, VALUE y);
VALUE rb_complex_uminus(VALUE z);
VALUE rb_complex_conjugate(VALUE z);
VALUE rb_complex_abs(VALUE z);
VALUE rb_complex_arg(VALUE z);
VALUE rb_complex_pow(VALUE base, VALUE exp);
VALUE rb_dbl_complex_new(double real, double imag);
#define rb_complex_add rb_complex_plus
#define rb_complex_sub rb_complex_minus
#define rb_complex_nagate rb_complex_uminus

VALUE rb_Complex(VALUE, VALUE);
#define rb_Complex1(x) rb_Complex((x), INT2FIX(0))
#define rb_Complex2(x,y) rb_Complex((x), (y))

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_COMPLEX_H */
