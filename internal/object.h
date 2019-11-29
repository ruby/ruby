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


/* object.c */
void rb_obj_copy_ivar(VALUE dest, VALUE obj);
CONSTFUNC(VALUE rb_obj_equal(VALUE obj1, VALUE obj2));
CONSTFUNC(VALUE rb_obj_not(VALUE obj));
VALUE rb_class_search_ancestor(VALUE klass, VALUE super);
NORETURN(void rb_undefined_alloc(VALUE klass));
double rb_num_to_dbl(VALUE val);
VALUE rb_obj_dig(int argc, VALUE *argv, VALUE self, VALUE notfound);
VALUE rb_immutable_obj_clone(int, VALUE *, VALUE);
VALUE rb_obj_not_equal(VALUE obj1, VALUE obj2);
VALUE rb_convert_type_with_id(VALUE,int,const char*,ID);
VALUE rb_check_convert_type_with_id(VALUE,int,const char*,ID);
int rb_bool_expected(VALUE, const char *);

struct RBasicRaw {
    VALUE flags;
    VALUE klass;
};

#define RBASIC_CLEAR_CLASS(obj)        memset(&(((struct RBasicRaw *)((VALUE)(obj)))->klass), 0, sizeof(VALUE))
#define RBASIC_SET_CLASS_RAW(obj, cls) memcpy(&((struct RBasicRaw *)((VALUE)(obj)))->klass, &(cls), sizeof(VALUE))
#define RBASIC_SET_CLASS(obj, cls)     do { \
    VALUE _obj_ = (obj); \
    RB_OBJ_WRITE(_obj_, &((struct RBasicRaw *)(_obj_))->klass, cls); \
} while (0)

RUBY_SYMBOL_EXPORT_BEGIN
/* object.c (export) */
int rb_opts_exception_p(VALUE opts, int default_value);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_OBJECT_H */
