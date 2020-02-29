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
 * @brief      Defines enum ::ruby_value_type.
 */
#ifndef  RUBY3_VALUE_TYPE_H
#define  RUBY3_VALUE_TYPE_H
#include "ruby/3/core/rbasic.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/special_consts.h"
#include "ruby/3/value.h"
#include "ruby/backward/2/gcc_version_since.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

enum ruby_value_type {
    RUBY_T_NONE   = 0x00,

    RUBY_T_OBJECT = 0x01,
    RUBY_T_CLASS  = 0x02,
    RUBY_T_MODULE = 0x03,
    RUBY_T_FLOAT  = 0x04,
    RUBY_T_STRING = 0x05,
    RUBY_T_REGEXP = 0x06,
    RUBY_T_ARRAY  = 0x07,
    RUBY_T_HASH   = 0x08,
    RUBY_T_STRUCT = 0x09,
    RUBY_T_BIGNUM = 0x0a,
    RUBY_T_FILE   = 0x0b,
    RUBY_T_DATA   = 0x0c,
    RUBY_T_MATCH  = 0x0d,
    RUBY_T_COMPLEX  = 0x0e,
    RUBY_T_RATIONAL = 0x0f,

    RUBY_T_NIL    = 0x11,
    RUBY_T_TRUE   = 0x12,
    RUBY_T_FALSE  = 0x13,
    RUBY_T_SYMBOL = 0x14,
    RUBY_T_FIXNUM = 0x15,
    RUBY_T_UNDEF  = 0x16,

    RUBY_T_IMEMO  = 0x1a, /*!< @see imemo_type */
    RUBY_T_NODE   = 0x1b,
    RUBY_T_ICLASS = 0x1c,
    RUBY_T_ZOMBIE = 0x1d,
    RUBY_T_MOVED  = 0x1e,

    RUBY_T_MASK   = 0x1f
};

#define T_NONE   RUBY_T_NONE
#define T_NIL    RUBY_T_NIL
#define T_OBJECT RUBY_T_OBJECT
#define T_CLASS  RUBY_T_CLASS
#define T_ICLASS RUBY_T_ICLASS
#define T_MODULE RUBY_T_MODULE
#define T_FLOAT  RUBY_T_FLOAT
#define T_STRING RUBY_T_STRING
#define T_REGEXP RUBY_T_REGEXP
#define T_ARRAY  RUBY_T_ARRAY
#define T_HASH   RUBY_T_HASH
#define T_STRUCT RUBY_T_STRUCT
#define T_BIGNUM RUBY_T_BIGNUM
#define T_FILE   RUBY_T_FILE
#define T_FIXNUM RUBY_T_FIXNUM
#define T_TRUE   RUBY_T_TRUE
#define T_FALSE  RUBY_T_FALSE
#define T_DATA   RUBY_T_DATA
#define T_MATCH  RUBY_T_MATCH
#define T_SYMBOL RUBY_T_SYMBOL
#define T_RATIONAL RUBY_T_RATIONAL
#define T_COMPLEX RUBY_T_COMPLEX
#define T_IMEMO  RUBY_T_IMEMO
#define T_UNDEF  RUBY_T_UNDEF
#define T_NODE   RUBY_T_NODE
#define T_ZOMBIE RUBY_T_ZOMBIE
#define T_MOVED RUBY_T_MOVED
#define T_MASK   RUBY_T_MASK

#define RB_BUILTIN_TYPE(x) (int)(((struct RBasic*)(x))->flags & RUBY_T_MASK)
#define BUILTIN_TYPE(x) RB_BUILTIN_TYPE(x)

static inline int rb_type(VALUE obj);
#define TYPE(x) rb_type((VALUE)(x))

#define RB_FLOAT_TYPE_P(obj) (\
        RB_FLONUM_P(obj) || \
        (!RB_SPECIAL_CONST_P(obj) && RB_BUILTIN_TYPE(obj) == RUBY_T_FLOAT))

#define RB_DYNAMIC_SYM_P(x) (!RB_SPECIAL_CONST_P(x) && RB_BUILTIN_TYPE(x) == (RUBY_T_SYMBOL))
#define RB_SYMBOL_P(x) (RB_STATIC_SYM_P(x)||RB_DYNAMIC_SYM_P(x))
#define DYNAMIC_SYM_P(x) RB_DYNAMIC_SYM_P(x)
#define SYMBOL_P(x) RB_SYMBOL_P(x)

#define RB_INTEGER_TYPE_P(obj) rb_integer_type_p(obj)
#if defined __GNUC__ && !GCC_VERSION_SINCE(4, 3, 0)
/* clang 3.x (4.2 compatible) can't eliminate CSE of RB_BUILTIN_TYPE
 * in inline function and caller function */
#define rb_integer_type_p(obj) \
    __extension__ ({ \
        const VALUE integer_type_obj = (obj); \
        (RB_FIXNUM_P(integer_type_obj) || \
         (!RB_SPECIAL_CONST_P(integer_type_obj) && \
          RB_BUILTIN_TYPE(integer_type_obj) == RUBY_T_BIGNUM)); \
    })
#else
static inline int
rb_integer_type_p(VALUE obj)
{
    return (RB_FIXNUM_P(obj) ||
            (!RB_SPECIAL_CONST_P(obj) &&
             RB_BUILTIN_TYPE(obj) == RUBY_T_BIGNUM));
}
#endif

#define RB_TYPE_P(obj, type) ( \
        ((type) == RUBY_T_FIXNUM) ? RB_FIXNUM_P(obj) : \
        ((type) == RUBY_T_TRUE) ? ((obj) == RUBY_Qtrue) : \
        ((type) == RUBY_T_FALSE) ? ((obj) == RUBY_Qfalse) : \
        ((type) == RUBY_T_NIL) ? ((obj) == RUBY_Qnil) : \
        ((type) == RUBY_T_UNDEF) ? ((obj) == RUBY_Qundef) : \
        ((type) == RUBY_T_SYMBOL) ? RB_SYMBOL_P(obj) : \
        ((type) == RUBY_T_FLOAT) ? RB_FLOAT_TYPE_P(obj) : \
        (!RB_SPECIAL_CONST_P(obj) && RB_BUILTIN_TYPE(obj) == (type)))

static inline int
rb_type(VALUE obj)
{
    if (RB_IMMEDIATE_P(obj)) {
        if (RB_FIXNUM_P(obj)) return RUBY_T_FIXNUM;
        if (RB_FLONUM_P(obj)) return RUBY_T_FLOAT;
        if (obj == RUBY_Qtrue)  return RUBY_T_TRUE;
        if (RB_STATIC_SYM_P(obj)) return RUBY_T_SYMBOL;
        if (obj == RUBY_Qundef) return RUBY_T_UNDEF;
    }
    else if (!RB_TEST(obj)) {
        if (obj == RUBY_Qnil)   return RUBY_T_NIL;
        if (obj == RUBY_Qfalse) return RUBY_T_FALSE;
    }
    return RB_BUILTIN_TYPE(obj);
}

#ifdef __GNUC__
#define rb_type_p(obj, type) \
    __extension__ (__builtin_constant_p(type) ? RB_TYPE_P((obj), (type)) : \
                   rb_type(obj) == (type))
#else
#define rb_type_p(obj, type) (rb_type(obj) == (type))
#endif

#ifdef __GNUC__
#define rb_special_const_p(obj) \
    __extension__ ({ \
        VALUE special_const_obj = (obj); \
        (int)(RB_SPECIAL_CONST_P(special_const_obj) ? RUBY_Qtrue : RUBY_Qfalse); \
    })
#else
static inline int
rb_special_const_p(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return (int)RUBY_Qtrue;
    return (int)RUBY_Qfalse;
}
#endif

void rb_check_type(VALUE,int);
#define Check_Type(v,t) rb_check_type((VALUE)(v),(t))

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_VALUE_TYPE_H */
