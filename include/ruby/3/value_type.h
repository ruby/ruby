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
#include "ruby/3/assume.h"
#include "ruby/3/attr/artificial.h"
#include "ruby/3/attr/cold.h"
#include "ruby/3/attr/enum_extensibility.h"
#include "ruby/3/attr/forceinline.h"
#include "ruby/3/attr/pure.h"
#include "ruby/3/cast.h"
#include "ruby/3/constant_p.h"
#include "ruby/3/core/rbasic.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/has/builtin.h"
#include "ruby/3/special_consts.h"
#include "ruby/3/stdbool.h"
#include "ruby/3/value.h"
#include "ruby/assert.h"

#if defined(T_DATA)
/*
 * :!BEWARE!: (Recent?)   Solaris' <nfs/nfs.h>  have conflicting  definition of
 * T_DATA.  Let us stop here.  Please have a workaround like this:
 *
 * ```C
 * #include <ruby/ruby.h> // <- Include this one first.
 * #undef T_DATA          // <- ... and stick to RUBY_T_DATA forever.
 * #include <nfs/nfs.h>   // <- OS-provided T_DATA introduced.
 * ```
 *
 * See also [ruby-core:4261]
 */
# error Bail out due to conflicting definition of T_DATA.
#endif

#define T_ARRAY    RUBY_T_ARRAY
#define T_BIGNUM   RUBY_T_BIGNUM
#define T_CLASS    RUBY_T_CLASS
#define T_COMPLEX  RUBY_T_COMPLEX
#define T_DATA     RUBY_T_DATA
#define T_FALSE    RUBY_T_FALSE
#define T_FILE     RUBY_T_FILE
#define T_FIXNUM   RUBY_T_FIXNUM
#define T_FLOAT    RUBY_T_FLOAT
#define T_HASH     RUBY_T_HASH
#define T_ICLASS   RUBY_T_ICLASS
#define T_IMEMO    RUBY_T_IMEMO
#define T_MASK     RUBY_T_MASK
#define T_MATCH    RUBY_T_MATCH
#define T_MODULE   RUBY_T_MODULE
#define T_MOVED    RUBY_T_MOVED
#define T_NIL      RUBY_T_NIL
#define T_NODE     RUBY_T_NODE
#define T_NONE     RUBY_T_NONE
#define T_OBJECT   RUBY_T_OBJECT
#define T_RATIONAL RUBY_T_RATIONAL
#define T_REGEXP   RUBY_T_REGEXP
#define T_STRING   RUBY_T_STRING
#define T_STRUCT   RUBY_T_STRUCT
#define T_SYMBOL   RUBY_T_SYMBOL
#define T_TRUE     RUBY_T_TRUE
#define T_UNDEF    RUBY_T_UNDEF
#define T_ZOMBIE   RUBY_T_ZOMBIE

#define BUILTIN_TYPE      RB_BUILTIN_TYPE
#define DYNAMIC_SYM_P     RB_DYNAMIC_SYM_P
#define RB_INTEGER_TYPE_P rb_integer_type_p
#define SYMBOL_P          RB_SYMBOL_P
#define rb_type_p         RB_TYPE_P

/** @cond INTERNAL_MACRO */
#define RB_BUILTIN_TYPE   RB_BUILTIN_TYPE
#define RB_DYNAMIC_SYM_P  RB_DYNAMIC_SYM_P
#define RB_FLOAT_TYPE_P   RB_FLOAT_TYPE_P
#define RB_SYMBOL_P       RB_SYMBOL_P
#define RB_TYPE_P         RB_TYPE_P
#define Check_Type        Check_Type

#if RUBY_NDEBUG
# define RUBY3_ASSERT_TYPE(v, t) RUBY3_ASSERT_OR_ASSUME(RB_TYPE_P((v), (t)))
#else
# define RUBY3_ASSERT_TYPE Check_Type
#endif
/** @endcond */

#define TYPE(_)           RUBY3_CAST((int)rb_type(_))

/** C-level type of an object. */
enum
RUBY3_ATTR_ENUM_EXTENSIBILITY(closed)
ruby_value_type {
    RUBY_T_NONE     = 0x00, /**< Non-object (sweeped etc.) */

    RUBY_T_OBJECT   = 0x01, /**< @see struct ::RObject */
    RUBY_T_CLASS    = 0x02, /**< @see struct ::RClass and ::rb_cClass */
    RUBY_T_MODULE   = 0x03, /**< @see struct ::RClass and ::rb_cModule */
    RUBY_T_FLOAT    = 0x04, /**< @see struct ::RFloat */
    RUBY_T_STRING   = 0x05, /**< @see struct ::RString */
    RUBY_T_REGEXP   = 0x06, /**< @see struct ::RRegexp */
    RUBY_T_ARRAY    = 0x07, /**< @see struct ::RArray */
    RUBY_T_HASH     = 0x08, /**< @see struct ::RHash */
    RUBY_T_STRUCT   = 0x09, /**< @see struct ::RStruct */
    RUBY_T_BIGNUM   = 0x0a, /**< @see struct ::RBignum */
    RUBY_T_FILE     = 0x0b, /**< @see struct ::RFile */
    RUBY_T_DATA     = 0x0c, /**< @see struct ::RTypedData */
    RUBY_T_MATCH    = 0x0d, /**< @see struct ::RMatch */
    RUBY_T_COMPLEX  = 0x0e, /**< @see struct ::RComplex */
    RUBY_T_RATIONAL = 0x0f, /**< @see struct ::RRational */

    RUBY_T_NIL      = 0x11, /**< @see ::RUBY_Qnil */
    RUBY_T_TRUE     = 0x12, /**< @see ::RUBY_Qfalse */
    RUBY_T_FALSE    = 0x13, /**< @see ::RUBY_Qtrue */
    RUBY_T_SYMBOL   = 0x14, /**< @see struct ::RSymbol */
    RUBY_T_FIXNUM   = 0x15, /**< Integers formerly known as Fixnums. */
    RUBY_T_UNDEF    = 0x16, /**< @see ::RUBY_Qundef */

    RUBY_T_IMEMO    = 0x1a, /**< @see struct ::RIMemo */
    RUBY_T_NODE     = 0x1b, /**< @see struct ::RNode */
    RUBY_T_ICLASS   = 0x1c, /**< Hidden classes known as IClasses. */
    RUBY_T_ZOMBIE   = 0x1d, /**< @see struct ::RZombie */
    RUBY_T_MOVED    = 0x1e, /**< @see struct ::RMoved */

    RUBY_T_MASK     = 0x1f
};

RUBY3_SYMBOL_EXPORT_BEGIN()
RUBY3_ATTR_COLD()
void rb_check_type(VALUE obj, int t);
RUBY3_SYMBOL_EXPORT_END()

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline enum ruby_value_type
RB_BUILTIN_TYPE(VALUE obj)
{
    RUBY3_ASSERT_OR_ASSUME(! RB_SPECIAL_CONST_P(obj));

    VALUE ret = RBASIC(obj)->flags & RUBY_T_MASK;
    return RUBY3_CAST((enum ruby_value_type)ret);
}

RUBY3_ATTR_PURE_ON_NDEBUG()
static inline bool
rb_integer_type_p(VALUE obj)
{
    if (RB_FIXNUM_P(obj)) {
        return true;
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_BIGNUM;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
static inline enum ruby_value_type
rb_type(VALUE obj)
{
    if (! RB_SPECIAL_CONST_P(obj)) {
        return RB_BUILTIN_TYPE(obj);
    }
    else if (obj == RUBY_Qfalse) {
        return RUBY_T_FALSE;
    }
    else if (obj == RUBY_Qnil) {
        return RUBY_T_NIL;
    }
    else if (obj == RUBY_Qtrue) {
        return RUBY_T_TRUE;
    }
    else if (obj == RUBY_Qundef) {
        return RUBY_T_UNDEF;
    }
    else if (RB_FIXNUM_P(obj)) {
        return RUBY_T_FIXNUM;
    }
    else if (RB_STATIC_SYM_P(obj)) {
        return RUBY_T_SYMBOL;
    }
    else {
        RUBY3_ASSUME(RB_FLONUM_P(obj));
        return RUBY_T_FLOAT;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_FLOAT_TYPE_P(VALUE obj)
{
    if (RB_FLONUM_P(obj)) {
        return true;
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_FLOAT;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_DYNAMIC_SYM_P(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else {
        return RB_BUILTIN_TYPE(obj) == RUBY_T_SYMBOL;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_SYMBOL_P(VALUE obj)
{
    return RB_STATIC_SYM_P(obj) || RB_DYNAMIC_SYM_P(obj);
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
RUBY3_ATTR_FORCEINLINE()
static bool
ruby3_RB_TYPE_P_fastpath(VALUE obj, enum ruby_value_type t)
{
    if (t == RUBY_T_TRUE) {
        return obj == RUBY_Qtrue;
    }
    else if (t == RUBY_T_FALSE) {
        return obj == RUBY_Qfalse;
    }
    else if (t == RUBY_T_NIL) {
        return obj == RUBY_Qnil;
    }
    else if (t == RUBY_T_UNDEF) {
        return obj == RUBY_Qundef;
    }
    else if (t == RUBY_T_FIXNUM) {
        return RB_FIXNUM_P(obj);
    }
    else if (t == RUBY_T_SYMBOL) {
        return RB_SYMBOL_P(obj);
    }
    else if (t == RUBY_T_FLOAT) {
        return RB_FLOAT_TYPE_P(obj);
    }
    else if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else if (t == RB_BUILTIN_TYPE(obj)) {
        return true;
    }
    else {
        return false;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_TYPE_P(VALUE obj, enum ruby_value_type t)
{
    if (RUBY3_CONSTANT_P(t)) {
        return ruby3_RB_TYPE_P_fastpath(obj, t);
    }
    else {
        return t == rb_type(obj);
    }
}

/** @cond INTERNAL_MACRO */
/* Clang, unlike GCC, cannot propagate __builtin_constant_p beyond function
 * boundary. */
#if defined(__clang__)
# undef RB_TYPE_P
# define RB_TYPE_P(obj, t)                  \
    (RUBY3_CONSTANT_P(t)                  ? \
     ruby3_RB_TYPE_P_fastpath((obj), (t)) : \
     (RB_TYPE_P)((obj), (t)))
#endif

/* clang 3.x (4.2 compatible) can't eliminate CSE of RB_BUILTIN_TYPE
 * in inline function and caller function
 * See also 8998c06461ea0bef11b3aeb30b6d2ab71c8762ba
 */
#if RUBY3_COMPILER_BEFORE(Clang, 4, 0, 0)
# undef rb_integer_type_p
# define rb_integer_type_p(obj)                                 \
    __extension__ ({                                            \
        const VALUE integer_type_obj = (obj);                   \
        (RB_FIXNUM_P(integer_type_obj) ||                       \
         (!RB_SPECIAL_CONST_P(integer_type_obj) &&              \
          RB_BUILTIN_TYPE(integer_type_obj) == RUBY_T_BIGNUM)); \
    })
#endif
/** @endcond */

RUBY3_ATTR_PURE()
RUBY3_ATTR_ARTIFICIAL()
/* Defined in ruby/3/core/rtypeddata.h */
static inline bool ruby3_rtypeddata_p(VALUE obj);

RUBY3_ATTR_ARTIFICIAL()
static inline void
Check_Type(VALUE v, enum ruby_value_type t)
{
    if (RB_UNLIKELY(! RB_TYPE_P(v, t))) {
        goto slowpath;
    }
    else if (t != RUBY_T_DATA) {
        goto fastpath;
    }
    else if (ruby3_rtypeddata_p(v)) {
        /* The intention itself is not necessarily clear to me, but at least it
         * is  intentional   to  rule   out  typed   data  here.    See  commit
         * a7c32bf81d3391cfb78cfda278f469717d0fb794. */
        goto slowpath;
    }
    else {
        goto fastpath;
    }

  fastpath:
    return;

  slowpath: /* <- :TODO: mark this label as cold. */
    rb_check_type(v, t);
}

#endif /* RUBY3_VALUE_TYPE_H */
