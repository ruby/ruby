#ifndef RBIMPL_INTERN_PARSE_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_PARSE_H
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
 * @brief      Public APIs related to ::rb_cSymbol.
 */
#include "ruby/internal/attr/const.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* parse.y */
ID rb_id_attrset(ID);

RBIMPL_ATTR_CONST()
int rb_is_const_id(ID);

RBIMPL_ATTR_CONST()
int rb_is_global_id(ID);

RBIMPL_ATTR_CONST()
int rb_is_instance_id(ID);

RBIMPL_ATTR_CONST()
int rb_is_attrset_id(ID);

RBIMPL_ATTR_CONST()
int rb_is_class_id(ID);

RBIMPL_ATTR_CONST()
int rb_is_local_id(ID);

RBIMPL_ATTR_CONST()
int rb_is_junk_id(ID);
int rb_symname_p(const char*);
int rb_sym_interned_p(VALUE);
VALUE rb_backref_get(void);
void rb_backref_set(VALUE);
VALUE rb_lastline_get(void);
void rb_lastline_set(VALUE);

/* symbol.c */
VALUE rb_sym_all_symbols(void);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_PARSE_H */
