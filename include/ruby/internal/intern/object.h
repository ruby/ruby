#ifndef RBIMPL_INTERN_OBJECT_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_OBJECT_H
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
 * @brief      Public APIs related to ::rb_cObject.
 */
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

#define RB_OBJ_INIT_COPY(obj, orig) \
    ((obj) != (orig) && (rb_obj_init_copy((obj), (orig)), 1))
#define OBJ_INIT_COPY(obj, orig) RB_OBJ_INIT_COPY(obj, orig)

VALUE rb_class_new_instance_pass_kw(int, const VALUE *, VALUE);
VALUE rb_class_new_instance(int, const VALUE*, VALUE);
VALUE rb_class_new_instance_kw(int, const VALUE*, VALUE, int);

/* object.c */
int rb_eql(VALUE, VALUE);
VALUE rb_any_to_s(VALUE);
VALUE rb_inspect(VALUE);
VALUE rb_obj_is_instance_of(VALUE, VALUE);
VALUE rb_obj_is_kind_of(VALUE, VALUE);
VALUE rb_obj_alloc(VALUE);
VALUE rb_obj_clone(VALUE);
VALUE rb_obj_clone_freeze(VALUE, VALUE);
VALUE rb_obj_dup(VALUE);
VALUE rb_obj_init_copy(VALUE,VALUE);
VALUE rb_obj_taint(VALUE);

RBIMPL_ATTR_PURE()
VALUE rb_obj_tainted(VALUE);
VALUE rb_obj_untaint(VALUE);
VALUE rb_obj_untrust(VALUE);

RBIMPL_ATTR_PURE()
VALUE rb_obj_untrusted(VALUE);
VALUE rb_obj_trust(VALUE);
VALUE rb_obj_freeze(VALUE);

RBIMPL_ATTR_PURE()
VALUE rb_obj_frozen_p(VALUE);

VALUE rb_obj_id(VALUE);
VALUE rb_memory_id(VALUE);
VALUE rb_obj_class(VALUE);

RBIMPL_ATTR_PURE()
VALUE rb_class_real(VALUE);

RBIMPL_ATTR_PURE()
VALUE rb_class_inherited_p(VALUE, VALUE);
VALUE rb_class_superclass(VALUE);
VALUE rb_class_get_superclass(VALUE);
VALUE rb_convert_type(VALUE,int,const char*,const char*);
VALUE rb_check_convert_type(VALUE,int,const char*,const char*);
VALUE rb_check_to_integer(VALUE, const char *);
VALUE rb_check_to_float(VALUE);
VALUE rb_to_int(VALUE);
VALUE rb_check_to_int(VALUE);
VALUE rb_Integer(VALUE);
VALUE rb_to_float(VALUE);
VALUE rb_Float(VALUE);
VALUE rb_String(VALUE);
VALUE rb_Array(VALUE);
VALUE rb_Hash(VALUE);
double rb_cstr_to_dbl(const char*, int);
double rb_str_to_dbl(VALUE, int);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_OBJECT_H */
