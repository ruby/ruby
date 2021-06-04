#ifndef RBIMPL_INTERN_NUMERIC_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_NUMERIC_H
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
 * @brief      Public APIs related to ::rb_cNumeric.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/backward/2/attributes.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* numeric.c */
NORETURN(void rb_num_zerodiv(void));
#define RB_NUM_COERCE_FUNCS_NEED_OPID 1
VALUE rb_num_coerce_bin(VALUE, VALUE, ID);
VALUE rb_num_coerce_cmp(VALUE, VALUE, ID);
VALUE rb_num_coerce_relop(VALUE, VALUE, ID);
VALUE rb_num_coerce_bit(VALUE, VALUE, ID);
VALUE rb_num2fix(VALUE);
VALUE rb_fix2str(VALUE, int);
CONSTFUNC(VALUE rb_dbl_cmp(double, double));

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_NUMERIC_H */
