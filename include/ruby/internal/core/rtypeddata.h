#ifndef RBIMPL_RTYPEDDATA_H                          /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RTYPEDDATA_H
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
 * @brief      Defines struct ::RTypedData.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#include "ruby/internal/assume.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/core/rdata.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/error.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value_type.h"

#define HAVE_TYPE_RB_DATA_TYPE_T     1
#define HAVE_RB_DATA_TYPE_T_FUNCTION 1
#define HAVE_RB_DATA_TYPE_T_PARENT   1
#define RUBY_TYPED_DEFAULT_FREE      RUBY_DEFAULT_FREE
#define RUBY_TYPED_NEVER_FREE        RUBY_NEVER_FREE
#define RTYPEDDATA(obj)              RBIMPL_CAST((struct RTypedData *)(obj))
#define RTYPEDDATA_DATA(v)           (RTYPEDDATA(v)->data)
#define Check_TypedStruct(v, t)      \
    rb_check_typeddata(RBIMPL_CAST((VALUE)(v)), (t))

/** @cond INTERNAL_MACRO */
#define RTYPEDDATA_P                 RTYPEDDATA_P
#define RTYPEDDATA_TYPE              RTYPEDDATA_TYPE
#define RUBY_TYPED_FREE_IMMEDIATELY  RUBY_TYPED_FREE_IMMEDIATELY
#define RUBY_TYPED_WB_PROTECTED      RUBY_TYPED_WB_PROTECTED
#define RUBY_TYPED_PROMOTED1         RUBY_TYPED_PROMOTED1
/** @endcond */

/* bits for rb_data_type_struct::flags */
enum rbimpl_typeddata_flags {
    RUBY_TYPED_FREE_IMMEDIATELY = 1,
    RUBY_TYPED_WB_PROTECTED     = RUBY_FL_WB_PROTECTED, /* THIS FLAG DEPENDS ON Ruby version */
    RUBY_TYPED_PROMOTED1        = RUBY_FL_PROMOTED1     /* THIS FLAG DEPENDS ON Ruby version */
};

typedef struct rb_data_type_struct rb_data_type_t;

struct rb_data_type_struct {
    const char *wrap_struct_name;
    struct {
        RUBY_DATA_FUNC dmark;
        RUBY_DATA_FUNC dfree;
        size_t (*dsize)(const void *);
        RUBY_DATA_FUNC dcompact;
        void *reserved[1]; /* For future extension.
                              This array *must* be filled with ZERO. */
    } function;
    const rb_data_type_t *parent;
    void *data;        /* This area can be used for any purpose
                          by a programmer who define the type. */
    VALUE flags;       /* RUBY_FL_WB_PROTECTED */
};

struct RTypedData {
    struct RBasic basic;
    const rb_data_type_t *type;
    VALUE typed_flag; /* 1 or not */
    void *data;
};

RBIMPL_SYMBOL_EXPORT_BEGIN()
VALUE rb_data_typed_object_wrap(VALUE klass, void *datap, const rb_data_type_t *);
VALUE rb_data_typed_object_zalloc(VALUE klass, size_t size, const rb_data_type_t *type);
int rb_typeddata_inherited_p(const rb_data_type_t *child, const rb_data_type_t *parent);
int rb_typeddata_is_kind_of(VALUE obj, const rb_data_type_t *data_type);
void *rb_check_typeddata(VALUE obj, const rb_data_type_t *data_type);
RBIMPL_SYMBOL_EXPORT_END()

#define TypedData_Wrap_Struct(klass,data_type,sval)\
  rb_data_typed_object_wrap((klass),(sval),(data_type))

#define TypedData_Make_Struct0(result, klass, type, size, data_type, sval) \
    VALUE result = rb_data_typed_object_zalloc(klass, size, data_type);    \
    (sval) = RBIMPL_CAST((type *)RTYPEDDATA_DATA(result));                  \
    RBIMPL_CAST(/*suppress unused variable warnings*/(void)(sval))

#ifdef HAVE_STMT_AND_DECL_IN_EXPR
#define TypedData_Make_Struct(klass, type, data_type, sval) \
    RB_GNUC_EXTENSION({         \
        TypedData_Make_Struct0( \
            data_struct_obj,    \
            klass,              \
            type,               \
            sizeof(type),       \
            data_type,          \
            sval);              \
        data_struct_obj;        \
    })
#else
#define TypedData_Make_Struct(klass, type, data_type, sval) \
    rb_data_typed_object_make(        \
        (klass),                      \
        (data_type),                  \
        RBIMPL_CAST((void **)&(sval)), \
        sizeof(type))
#endif

#define TypedData_Get_Struct(obj,type,data_type,sval) \
    ((sval) = RBIMPL_CAST((type *)rb_check_typeddata((obj), (data_type))))

RBIMPL_ATTR_PURE()
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
rbimpl_rtypeddata_p(VALUE obj)
{
    return RTYPEDDATA(obj)->typed_flag == 1;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RTYPEDDATA_P(VALUE obj)
{
#if RUBY_DEBUG
    if (RB_UNLIKELY(! RB_TYPE_P(obj, RUBY_T_DATA))) {
        Check_Type(obj, RUBY_T_DATA);
        RBIMPL_UNREACHABLE_RETURN(false);
    }
#endif

    return rbimpl_rtypeddata_p(obj);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
/* :TODO: can this function be __attribute__((returns_nonnull)) or not? */
static inline const struct rb_data_type_struct *
RTYPEDDATA_TYPE(VALUE obj)
{
#if RUBY_DEBUG
    if (RB_UNLIKELY(! RTYPEDDATA_P(obj))) {
        rb_unexpected_type(obj, RUBY_T_DATA);
        RBIMPL_UNREACHABLE_RETURN(NULL);
    }
#endif

    return RTYPEDDATA(obj)->type;
}

static inline VALUE
rb_data_typed_object_make(VALUE klass, const rb_data_type_t *type, void **datap, size_t size)
{
    TypedData_Make_Struct0(result, klass, void, size, type, *datap);
    return result;
}

RBIMPL_ATTR_DEPRECATED(("by: rb_data_typed_object_wrap"))
static inline VALUE
rb_data_typed_object_alloc(VALUE klass, void *datap, const rb_data_type_t *type)
{
    return rb_data_typed_object_wrap(klass, datap, type);
}

#endif /* RBIMPL_RTYPEDDATA_H */
