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
 * @brief      Routines to manipulate struct ::RClass.
 */
#ifndef  RUBY3_RCLASS_H
#define  RUBY3_RCLASS_H
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

VALUE rb_class_get_superclass(VALUE);
#define RCLASS_SUPER(c) rb_class_get_superclass(c)
#define RMODULE_IS_OVERLAID RMODULE_IS_OVERLAID
#define RMODULE_IS_REFINEMENT RMODULE_IS_REFINEMENT
#define RMODULE_INCLUDED_INTO_REFINEMENT RMODULE_INCLUDED_INTO_REFINEMENT
enum ruby_rmodule_flags {
    RMODULE_IS_OVERLAID = RUBY_FL_USER2,
    RMODULE_IS_REFINEMENT = RUBY_FL_USER3,
    RMODULE_INCLUDED_INTO_REFINEMENT = RUBY_FL_USER4,

    RMODULE_ENUM_END
};

#define RCLASS(obj)  (R_CAST(RClass)(obj))
#define RMODULE(obj) RCLASS(obj)

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_RCLASS_H */
