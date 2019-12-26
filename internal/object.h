#ifndef INTERNAL_OBJECT_H /* -*- C -*- */
#define INTERNAL_OBJECT_H
/**
 * @file
 * @brief      Internal header for Object.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/ruby.h"          /* for VALUE */

/* object.c */
VALUE rb_class_search_ancestor(VALUE klass, VALUE super);
NORETURN(void rb_undefined_alloc(VALUE klass));
double rb_num_to_dbl(VALUE val);
VALUE rb_obj_dig(int argc, VALUE *argv, VALUE self, VALUE notfound);
VALUE rb_immutable_obj_clone(int, VALUE *, VALUE);
VALUE rb_check_convert_type_with_id(VALUE,int,const char*,ID);
int rb_bool_expected(VALUE, const char *);
static inline void RBASIC_CLEAR_CLASS(VALUE obj);
static inline void RBASIC_SET_CLASS_RAW(VALUE obj, VALUE klass);
static inline void RBASIC_SET_CLASS(VALUE obj, VALUE klass);

RUBY_SYMBOL_EXPORT_BEGIN
/* object.c (export) */
int rb_opts_exception_p(VALUE opts, int default_value);
RUBY_SYMBOL_EXPORT_END

MJIT_SYMBOL_EXPORT_BEGIN
CONSTFUNC(VALUE rb_obj_equal(VALUE obj1, VALUE obj2));
CONSTFUNC(VALUE rb_obj_not(VALUE obj));
VALUE rb_obj_not_equal(VALUE obj1, VALUE obj2);
void rb_obj_copy_ivar(VALUE dest, VALUE obj);
VALUE rb_false(VALUE obj);
VALUE rb_convert_type_with_id(VALUE v, int t, const char* nam, ID mid);
MJIT_SYMBOL_EXPORT_END

static inline void
RBASIC_SET_CLASS_RAW(VALUE obj, VALUE klass)
{
    struct { VALUE flags; VALUE klass; } *ptr = (void *)obj;
    ptr->klass = klass;
}

static inline void
RBASIC_CLEAR_CLASS(VALUE obj)
{
    RBASIC_SET_CLASS_RAW(obj, 0);
}

static inline void
RBASIC_SET_CLASS(VALUE obj, VALUE klass)
{
    VALUE oldv = RBASIC_CLASS(obj);
    RBASIC_SET_CLASS_RAW(obj, klass);
    RB_OBJ_WRITTEN(obj, oldv, klass);
}
#endif /* INTERNAL_OBJECT_H */
