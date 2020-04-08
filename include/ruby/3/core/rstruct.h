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
 * @brief      Routines to manipulate struct ::RStruct.
 */
#ifndef  RUBY3_RSTRUCT_H
#define  RUBY3_RSTRUCT_H
#include "ruby/3/attr/artificial.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"
#include "ruby/3/value_type.h"
#include "ruby/3/arithmetic/long.h"
#include "ruby/3/arithmetic/int.h"
#if !defined RUBY_EXPORT && !defined RUBY_NO_OLD_COMPATIBILITY
# include "ruby/backward.h"
#endif

#define RSTRUCT_PTR(st) rb_struct_ptr(st)
/** @cond INTERNAL_MACRO */
#define RSTRUCT_LEN RSTRUCT_LEN
#define RSTRUCT_SET RSTRUCT_SET
#define RSTRUCT_GET RSTRUCT_GET
/** @endcond */

RUBY3_SYMBOL_EXPORT_BEGIN()
VALUE rb_struct_size(VALUE s);
VALUE rb_struct_aref(VALUE, VALUE);
VALUE rb_struct_aset(VALUE, VALUE, VALUE);
RUBY3_SYMBOL_EXPORT_END()

RUBY3_ATTR_ARTIFICIAL()
static inline long
RSTRUCT_LEN(VALUE st)
{
    RUBY3_ASSERT_TYPE(st, RUBY_T_STRUCT);

    return RB_NUM2LONG(rb_struct_size(st));
}

RUBY3_ATTR_ARTIFICIAL()
static inline VALUE
RSTRUCT_SET(VALUE st, int k, VALUE v)
{
    RUBY3_ASSERT_TYPE(st, RUBY_T_STRUCT);

    return rb_struct_aset(st, INT2NUM(k), (v));
}

RUBY3_ATTR_ARTIFICIAL()
static inline VALUE
RSTRUCT_GET(VALUE st, int k)
{
    RUBY3_ASSERT_TYPE(st, RUBY_T_STRUCT);

    return rb_struct_aref(st, INT2NUM(k));
}

#endif /* RUBY3_RSTRUCT_H */
