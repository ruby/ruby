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
 * @brief      Defines #NEWOBJ.
 */
#ifndef  RUBY3_NEWOBJ_H
#define  RUBY3_NEWOBJ_H
#include "ruby/3/core/rbasic.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/fl_type.h"
#include "ruby/3/value.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

VALUE rb_newobj(void);
VALUE rb_newobj_of(VALUE, VALUE);
VALUE rb_obj_setup(VALUE obj, VALUE klass, VALUE type);
VALUE rb_obj_class(VALUE);
VALUE rb_singleton_class_clone(VALUE);
void rb_singleton_class_attached(VALUE,VALUE);
void rb_copy_generic_ivar(VALUE,VALUE);
#define RB_NEWOBJ(obj,type) type *(obj) = (type*)rb_newobj()
#define RB_NEWOBJ_OF(obj,type,klass,flags) type *(obj) = (type*)rb_newobj_of(klass, flags)
#define NEWOBJ(obj,type) RB_NEWOBJ(obj,type)
#define NEWOBJ_OF(obj,type,klass,flags) RB_NEWOBJ_OF(obj,type,klass,flags) /* core has special NEWOBJ_OF() in internal.h */
#define OBJSETUP(obj,c,t) rb_obj_setup(obj, c, t) /* use NEWOBJ_OF instead of NEWOBJ()+OBJSETUP() */
#define CLONESETUP(clone,obj) rb_clone_setup(clone,obj)
#define DUPSETUP(dup,obj) rb_dup_setup(dup,obj)

static inline void
rb_clone_setup(VALUE clone, VALUE obj)
{
    rb_obj_setup(clone, rb_singleton_class_clone(obj),
                 RBASIC(obj)->flags & ~(FL_PROMOTED0|FL_PROMOTED1|FL_FINALIZE));
    rb_singleton_class_attached(RBASIC_CLASS(clone), clone);
    if (RB_FL_TEST(obj, RUBY_FL_EXIVAR)) rb_copy_generic_ivar(clone, obj);
}

static inline void
rb_dup_setup(VALUE dup, VALUE obj)
{
    rb_obj_setup(dup, rb_obj_class(obj), RB_FL_TEST_RAW(obj, RUBY_FL_DUPPED));
    if (RB_FL_TEST(obj, RUBY_FL_EXIVAR)) rb_copy_generic_ivar(dup, obj);
}

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_NEWOBJ_H */
