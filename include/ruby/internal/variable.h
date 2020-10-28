#ifndef RBIMPL_VARIABLE_H                            /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_VARIABLE_H
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
 * @brief      C-function backended Ruby-global variables.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/attr/noreturn.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

typedef VALUE rb_gvar_getter_t(ID id, VALUE *data);
typedef void  rb_gvar_setter_t(VALUE val, ID id, VALUE *data);
typedef void  rb_gvar_marker_t(VALUE *var);

rb_gvar_getter_t rb_gvar_undef_getter;
rb_gvar_setter_t rb_gvar_undef_setter;
rb_gvar_marker_t rb_gvar_undef_marker;

rb_gvar_getter_t rb_gvar_val_getter;
rb_gvar_setter_t rb_gvar_val_setter;
rb_gvar_marker_t rb_gvar_val_marker;

rb_gvar_getter_t rb_gvar_var_getter;
rb_gvar_setter_t rb_gvar_var_setter;
rb_gvar_marker_t rb_gvar_var_marker;

RBIMPL_ATTR_NORETURN()
rb_gvar_setter_t rb_gvar_readonly_setter;

void rb_define_variable(const char*,VALUE*);
void rb_define_virtual_variable(const char*,rb_gvar_getter_t*,rb_gvar_setter_t*);
void rb_define_hooked_variable(const char*,VALUE*,rb_gvar_getter_t*,rb_gvar_setter_t*);
void rb_define_readonly_variable(const char*,const VALUE*);
void rb_define_const(VALUE,const char*,VALUE);
void rb_define_global_const(const char*,VALUE);

VALUE rb_gv_set(const char*, VALUE);
VALUE rb_gv_get(const char*);
VALUE rb_iv_get(VALUE, const char*);
VALUE rb_iv_set(VALUE, const char*, VALUE);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_VARIABLE_H */
