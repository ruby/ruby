#ifndef  RBIMPL_INTERN_LOAD_H                        /*-*-C++-*-vi:se ft=cpp:*/
#define  RBIMPL_INTERN_LOAD_H
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
 * @brief      Public APIs related to ::rb_f_require().
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/* load.c */
void rb_load(VALUE, int);
void rb_load_protect(VALUE, int, int*);
int rb_provided(const char*);
int rb_feature_provided(const char *, const char **);
void rb_provide(const char*);
VALUE rb_f_require(VALUE, VALUE);
VALUE rb_require_string(VALUE);

// extension configuration
void rb_ext_ractor_safe(bool flag);
#define RB_EXT_RACTOR_SAFE(f) rb_ext_ractor_safe(f)
#define HAVE_RB_EXT_RACTOR_SAFE 1

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_LOAD_H */
