#ifndef RBIMPL_RCLASS_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RCLASS_H
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
 * @brief      Routines to manipulate struct ::RClass.
 */
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/cast.h"

#define RMODULE_IS_OVERLAID              RMODULE_IS_OVERLAID
#define RMODULE_IS_REFINEMENT            RMODULE_IS_REFINEMENT
#define RMODULE_INCLUDED_INTO_REFINEMENT RMODULE_INCLUDED_INTO_REFINEMENT

#define RCLASS(obj)  RBIMPL_CAST((struct RClass *)(obj))
#define RMODULE      RCLASS
#define RCLASS_SUPER rb_class_get_superclass

enum ruby_rmodule_flags {
    RMODULE_IS_OVERLAID              = RUBY_FL_USER2,
    RMODULE_IS_REFINEMENT            = RUBY_FL_USER3,
    RMODULE_INCLUDED_INTO_REFINEMENT = RUBY_FL_USER4
};

struct RClass; /* Opaque, declared here for RCLASS() macro. */

RBIMPL_SYMBOL_EXPORT_BEGIN()
VALUE rb_class_get_superclass(VALUE);
RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_RCLASS_H */
