#ifndef RBIMPL_NEWOBJ_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_NEWOBJ_H
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
 * @brief      Defines #NEWOBJ.
 */
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/special_consts.h"
#include "ruby/internal/value.h"
#include "ruby/assert.h"

#define RB_NEWOBJ(obj,type) type *(obj) = RBIMPL_CAST((type *)rb_newobj())
#define RB_NEWOBJ_OF(obj,type,klass,flags) type *(obj) = RBIMPL_CAST((type *)rb_newobj_of(klass, flags))

#define NEWOBJ     RB_NEWOBJ
#define NEWOBJ_OF  RB_NEWOBJ_OF /* core has special NEWOBJ_OF() in internal.h */
#define OBJSETUP   rb_obj_setup /* use NEWOBJ_OF instead of NEWOBJ()+OBJSETUP() */
#define CLONESETUP rb_clone_setup
#define DUPSETUP   rb_dup_setup

RBIMPL_SYMBOL_EXPORT_BEGIN()
VALUE rb_newobj(void);
VALUE rb_newobj_of(VALUE, VALUE);
VALUE rb_obj_setup(VALUE obj, VALUE klass, VALUE type);
VALUE rb_obj_class(VALUE);
VALUE rb_singleton_class_clone(VALUE);
void rb_singleton_class_attached(VALUE,VALUE);
void rb_copy_generic_ivar(VALUE,VALUE);
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_DEPRECATED(("This is no longer how Object#clone works."))
static inline void
rb_clone_setup(VALUE clone, VALUE obj)
{
    return;
}

RBIMPL_ATTR_DEPRECATED(("This is no longer how Object#dup works."))
static inline void
rb_dup_setup(VALUE dup, VALUE obj)
{
    return;
}

#endif /* RBIMPL_NEWOBJ_H */
