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
 * @brief      Defines struct ::RTypedData.
 */
#ifndef  RUBY3_RTYPEDDATA_H
#define  RUBY3_RTYPEDDATA_H
#include "ruby/3/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/3/core/rdata.h"
#include "ruby/3/dllexport.h"
#include "ruby/backward/2/r_cast.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

#define RTYPEDDATA(obj)   (R_CAST(RTypedData)(obj))

typedef struct rb_data_type_struct rb_data_type_t;

struct rb_data_type_struct {
    const char *wrap_struct_name;
    struct {
        void (*dmark)(void*);
        void (*dfree)(void*);
        size_t (*dsize)(const void *);
        void (*dcompact)(void*);
        void *reserved[1]; /* For future extension.
                              This array *must* be filled with ZERO. */
    } function;
    const rb_data_type_t *parent;
    void *data;        /* This area can be used for any purpose
                          by a programmer who define the type. */
    VALUE flags;       /* RUBY_FL_WB_PROTECTED */
};

#define HAVE_TYPE_RB_DATA_TYPE_T 1
#define HAVE_RB_DATA_TYPE_T_FUNCTION 1
#define HAVE_RB_DATA_TYPE_T_PARENT 1

struct RTypedData {
    struct RBasic basic;
    const rb_data_type_t *type;
    VALUE typed_flag; /* 1 or not */
    void *data;
};

#define RTYPEDDATA_P(v)    (RTYPEDDATA(v)->typed_flag == 1)
#define RTYPEDDATA_TYPE(v) (RTYPEDDATA(v)->type)
#define RTYPEDDATA_DATA(v) (RTYPEDDATA(v)->data)

VALUE rb_data_typed_object_wrap(VALUE klass, void *datap, const rb_data_type_t *);
VALUE rb_data_typed_object_zalloc(VALUE klass, size_t size, const rb_data_type_t *type);
int rb_typeddata_inherited_p(const rb_data_type_t *child, const rb_data_type_t *parent);
int rb_typeddata_is_kind_of(VALUE, const rb_data_type_t *);
void *rb_check_typeddata(VALUE, const rb_data_type_t *);
#define Check_TypedStruct(v,t) rb_check_typeddata((VALUE)(v),(t))

#define RUBY_TYPED_DEFAULT_FREE RUBY_DEFAULT_FREE
#define RUBY_TYPED_NEVER_FREE   RUBY_NEVER_FREE

/* bits for rb_data_type_struct::flags */
#define RUBY_TYPED_FREE_IMMEDIATELY  1 /* TYPE field */
#define RUBY_TYPED_WB_PROTECTED      RUBY_FL_WB_PROTECTED /* THIS FLAG DEPENDS ON Ruby version */
#define RUBY_TYPED_PROMOTED1         RUBY_FL_PROMOTED1    /* THIS FLAG DEPENDS ON Ruby version */

#define TypedData_Wrap_Struct(klass,data_type,sval)\
  rb_data_typed_object_wrap((klass),(sval),(data_type))

#define TypedData_Make_Struct0(result, klass, type, size, data_type, sval) \
    VALUE result = rb_data_typed_object_zalloc(klass, size, data_type); \
    (void)((sval) = (type *)DATA_PTR(result));

#ifdef __GNUC__
#define TypedData_Make_Struct(klass, type, data_type, sval) RB_GNUC_EXTENSION_BLOCK(\
    TypedData_Make_Struct0(data_struct_obj, klass, type, sizeof(type), data_type, sval); \
    data_struct_obj \
)
#else
#define TypedData_Make_Struct(klass, type, data_type, sval) (\
    rb_data_typed_object_make((klass),(data_type),(void **)&(sval),sizeof(type)) \
)
#endif

#define TypedData_Get_Struct(obj,type,data_type,sval) \
    ((sval) = (type*)rb_check_typeddata((obj), (data_type)))

static inline VALUE
rb_data_typed_object_make(VALUE klass, const rb_data_type_t *type, void **datap, size_t size)
{
    TypedData_Make_Struct0(result, klass, void, size, type, *datap);
    return result;
}

#ifndef rb_data_typed_object_alloc
DEPRECATED_BY(rb_data_typed_object_wrap, static inline VALUE rb_data_typed_object_alloc(VALUE,void*,const rb_data_type_t*));
static inline VALUE
rb_data_typed_object_alloc(VALUE klass, void *datap, const rb_data_type_t *type)
{
    return rb_data_typed_object_wrap(klass, datap, type);
}
#endif

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_RTYPEDDATA_H */
