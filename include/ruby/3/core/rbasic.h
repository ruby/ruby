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
 * @brief      Defines struct ::RBasic.
 */
#ifndef  RUBY3_RBASIC_H
#define  RUBY3_RBASIC_H
#include "ruby/3/value.h"
#include "ruby/3/dllexport.h"
#include "ruby/backward/2/r_cast.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

struct RUBY_ALIGNAS(SIZEOF_VALUE) RBasic {
    VALUE flags;
    const VALUE klass;
};

#define RBASIC(obj)  (R_CAST(RBasic)(obj))
#define RBASIC_CLASS(obj) (RBASIC(obj)->klass)

#define RVALUE_EMBED_LEN_MAX RVALUE_EMBED_LEN_MAX
enum ruby_rvalue_flags {
    RVALUE_EMBED_LEN_MAX = 3
};

VALUE rb_obj_hide(VALUE obj);
VALUE rb_obj_reveal(VALUE obj, VALUE klass); /* do not use this API to change klass information */

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_RBASIC_H */
