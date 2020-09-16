#ifndef RBIMPL_INTERN_PROC_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_PROC_H
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
 * @brief      Public APIs related to ::rb_cProc.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/iterator.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* proc.c */
VALUE rb_block_proc(void);
VALUE rb_block_lambda(void);
VALUE rb_proc_new(rb_block_call_func_t, VALUE);
VALUE rb_obj_is_proc(VALUE);
VALUE rb_proc_call(VALUE, VALUE);
VALUE rb_proc_call_kw(VALUE, VALUE, int);
VALUE rb_proc_call_with_block(VALUE, int argc, const VALUE *argv, VALUE);
VALUE rb_proc_call_with_block_kw(VALUE, int argc, const VALUE *argv, VALUE, int);
int rb_proc_arity(VALUE);
VALUE rb_proc_lambda_p(VALUE);
VALUE rb_binding_new(void);
VALUE rb_obj_method(VALUE, VALUE);
VALUE rb_obj_is_method(VALUE);
VALUE rb_method_call(int, const VALUE*, VALUE);
VALUE rb_method_call_kw(int, const VALUE*, VALUE, int);
VALUE rb_method_call_with_block(int, const VALUE *, VALUE, VALUE);
VALUE rb_method_call_with_block_kw(int, const VALUE *, VALUE, VALUE, int);
int rb_mod_method_arity(VALUE, ID);
int rb_obj_method_arity(VALUE, ID);
VALUE rb_callable_receiver(VALUE);
VALUE rb_protect(VALUE (*)(VALUE), VALUE, int*);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_PROC_H */
