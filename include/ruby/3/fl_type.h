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
 * @brief      Defines enum ::ruby_fl_type.
 */
#ifndef  RUBY3_FL_TYPE_H
#define  RUBY3_FL_TYPE_H
#include "ruby/3/config.h"      /* for ENUM_OVER_INT */
#include "ruby/3/attr/artificial.h"
#include "ruby/3/attr/flag_enum.h"
#include "ruby/3/attr/forceinline.h"
#include "ruby/3/attr/noalias.h"
#include "ruby/3/attr/pure.h"
#include "ruby/3/cast.h"
#include "ruby/3/core/rbasic.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/special_consts.h"
#include "ruby/3/stdbool.h"
#include "ruby/3/value.h"
#include "ruby/3/value_type.h"
#include "ruby/assert.h"
#include "ruby/defines.h"

/** @cond INTERNAL_MACRO */
#ifdef ENUM_OVER_INT
# define RUBY3_WIDER_ENUM 1
#elif SIZEOF_INT * CHAR_BIT > 12+19+1
# define RUBY3_WIDER_ENUM 1
#else
# define RUBY3_WIDER_ENUM 0
#endif
/** @endcond */

#define FL_SINGLETON    RUBY3_CAST((VALUE)RUBY_FL_SINGLETON)
#define FL_WB_PROTECTED RUBY3_CAST((VALUE)RUBY_FL_WB_PROTECTED)
#define FL_PROMOTED0    RUBY3_CAST((VALUE)RUBY_FL_PROMOTED0)
#define FL_PROMOTED1    RUBY3_CAST((VALUE)RUBY_FL_PROMOTED1)
#define FL_FINALIZE     RUBY3_CAST((VALUE)RUBY_FL_FINALIZE)
#define FL_TAINT        RUBY3_CAST((VALUE)RUBY_FL_TAINT)
#define FL_UNTRUSTED    RUBY3_CAST((VALUE)RUBY_FL_UNTRUSTED)
#define FL_SEEN_OBJ_ID  RUBY3_CAST((VALUE)RUBY_FL_SEEN_OBJ_ID)
#define FL_EXIVAR       RUBY3_CAST((VALUE)RUBY_FL_EXIVAR)
#define FL_FREEZE       RUBY3_CAST((VALUE)RUBY_FL_FREEZE)

#define FL_USHIFT       RUBY3_CAST((VALUE)RUBY_FL_USHIFT)

#define FL_USER0        RUBY3_CAST((VALUE)RUBY_FL_USER0)
#define FL_USER1        RUBY3_CAST((VALUE)RUBY_FL_USER1)
#define FL_USER2        RUBY3_CAST((VALUE)RUBY_FL_USER2)
#define FL_USER3        RUBY3_CAST((VALUE)RUBY_FL_USER3)
#define FL_USER4        RUBY3_CAST((VALUE)RUBY_FL_USER4)
#define FL_USER5        RUBY3_CAST((VALUE)RUBY_FL_USER5)
#define FL_USER6        RUBY3_CAST((VALUE)RUBY_FL_USER6)
#define FL_USER7        RUBY3_CAST((VALUE)RUBY_FL_USER7)
#define FL_USER8        RUBY3_CAST((VALUE)RUBY_FL_USER8)
#define FL_USER9        RUBY3_CAST((VALUE)RUBY_FL_USER9)
#define FL_USER10       RUBY3_CAST((VALUE)RUBY_FL_USER10)
#define FL_USER11       RUBY3_CAST((VALUE)RUBY_FL_USER11)
#define FL_USER12       RUBY3_CAST((VALUE)RUBY_FL_USER12)
#define FL_USER13       RUBY3_CAST((VALUE)RUBY_FL_USER13)
#define FL_USER14       RUBY3_CAST((VALUE)RUBY_FL_USER14)
#define FL_USER15       RUBY3_CAST((VALUE)RUBY_FL_USER15)
#define FL_USER16       RUBY3_CAST((VALUE)RUBY_FL_USER16)
#define FL_USER17       RUBY3_CAST((VALUE)RUBY_FL_USER17)
#define FL_USER18       RUBY3_CAST((VALUE)RUBY_FL_USER18)
#define FL_USER19       RUBY3_CAST((VALUE)(unsigned int)RUBY_FL_USER19)

#define ELTS_SHARED          RUBY_ELTS_SHARED
#define RUBY_ELTS_SHARED     RUBY_ELTS_SHARED
#define RB_OBJ_FREEZE        rb_obj_freeze_inline

/** @cond INTERNAL_MACRO */
#define RB_FL_ABLE           RB_FL_ABLE
#define RB_FL_ALL            RB_FL_ALL
#define RB_FL_ALL_RAW        RB_FL_ALL_RAW
#define RB_FL_ANY            RB_FL_ANY
#define RB_FL_ANY_RAW        RB_FL_ANY_RAW
#define RB_FL_REVERSE        RB_FL_REVERSE
#define RB_FL_REVERSE_RAW    RB_FL_REVERSE_RAW
#define RB_FL_SET            RB_FL_SET
#define RB_FL_SET_RAW        RB_FL_SET_RAW
#define RB_FL_TEST           RB_FL_TEST
#define RB_FL_TEST_RAW       RB_FL_TEST_RAW
#define RB_FL_UNSET          RB_FL_UNSET
#define RB_FL_UNSET_RAW      RB_FL_UNSET_RAW
#define RB_OBJ_FREEZE_RAW    RB_OBJ_FREEZE_RAW
#define RB_OBJ_FROZEN        RB_OBJ_FROZEN
#define RB_OBJ_FROZEN_RAW    RB_OBJ_FROZEN_RAW
#define RB_OBJ_INFECT        RB_OBJ_INFECT
#define RB_OBJ_INFECT_RAW    RB_OBJ_INFECT_RAW
#define RB_OBJ_TAINT         RB_OBJ_TAINT
#define RB_OBJ_TAINTABLE     RB_OBJ_TAINTABLE
#define RB_OBJ_TAINTED       RB_OBJ_TAINTED
#define RB_OBJ_TAINTED_RAW   RB_OBJ_TAINTED_RAW
#define RB_OBJ_TAINT_RAW     RB_OBJ_TAINT_RAW
#define RB_OBJ_UNTRUST       RB_OBJ_UNTRUST
#define RB_OBJ_UNTRUSTED     RB_OBJ_UNTRUSTED
/** @endcond */

/**
 * @defgroup deprecated_macros deprecated macro APIs
 * @{
 * These macros are deprecated. Prefer their `RB_`-prefixed versions.
 */
#define FL_ABLE         RB_FL_ABLE
#define FL_ALL          RB_FL_ALL
#define FL_ALL_RAW      RB_FL_ALL_RAW
#define FL_ANY          RB_FL_ANY
#define FL_ANY_RAW      RB_FL_ANY_RAW
#define FL_REVERSE      RB_FL_REVERSE
#define FL_REVERSE_RAW  RB_FL_REVERSE_RAW
#define FL_SET          RB_FL_SET
#define FL_SET_RAW      RB_FL_SET_RAW
#define FL_TEST         RB_FL_TEST
#define FL_TEST_RAW     RB_FL_TEST_RAW
#define FL_UNSET        RB_FL_UNSET
#define FL_UNSET_RAW    RB_FL_UNSET_RAW
#define OBJ_FREEZE      RB_OBJ_FREEZE
#define OBJ_FREEZE_RAW  RB_OBJ_FREEZE_RAW
#define OBJ_FROZEN      RB_OBJ_FROZEN
#define OBJ_FROZEN_RAW  RB_OBJ_FROZEN_RAW
#define OBJ_INFECT      RB_OBJ_INFECT
#define OBJ_INFECT_RAW  RB_OBJ_INFECT_RAW
#define OBJ_TAINT       RB_OBJ_TAINT
#define OBJ_TAINTABLE   RB_OBJ_TAINTABLE
#define OBJ_TAINTED     RB_OBJ_TAINTED
#define OBJ_TAINTED_RAW RB_OBJ_TAINTED_RAW
#define OBJ_TAINT_RAW   RB_OBJ_TAINT_RAW
#define OBJ_UNTRUST     RB_OBJ_UNTRUST
#define OBJ_UNTRUSTED   RB_OBJ_UNTRUSTED
/** @} */

/* This is an enum because GDB wants it (rather than a macro) */
enum { RUBY_FL_USHIFT = 12 };

/* > The expression that defines the value  of an enumeration constant shall be
 * > an integer constant expression that has a value representable as an `int`.
 *
 * -- ISO/IEC 9899:2018 section 6.7.2.2
 *
 * So ENUM_OVER_INT situation is an extension to the standard.  Note however
 * that we do not support 16 bit `int` environment. */
RB_GNUC_EXTENSION
enum
RUBY3_ATTR_FLAG_ENUM()
ruby_fl_type {
    RUBY_FL_WB_PROTECTED = (1<<5),
    RUBY_FL_PROMOTED0    = (1<<5),
    RUBY_FL_PROMOTED1    = (1<<6),
    RUBY_FL_PROMOTED     = RUBY_FL_PROMOTED0 | RUBY_FL_PROMOTED1,
    RUBY_FL_FINALIZE     = (1<<7),
    RUBY_FL_TAINT        = (1<<8),
    RUBY_FL_UNTRUSTED    = RUBY_FL_TAINT,
    RUBY_FL_SEEN_OBJ_ID  = (1<<9),
    RUBY_FL_EXIVAR       = (1<<10),
    RUBY_FL_FREEZE       = (1<<11),

#define RUBY3_FL_USER_N(n) RUBY_FL_USER##n = (1<<(RUBY_FL_USHIFT+n))
    RUBY3_FL_USER_N(0),
    RUBY3_FL_USER_N(1),
    RUBY3_FL_USER_N(2),
    RUBY3_FL_USER_N(3),
    RUBY3_FL_USER_N(4),
    RUBY3_FL_USER_N(5),
    RUBY3_FL_USER_N(6),
    RUBY3_FL_USER_N(7),
    RUBY3_FL_USER_N(8),
    RUBY3_FL_USER_N(9),
    RUBY3_FL_USER_N(10),
    RUBY3_FL_USER_N(11),
    RUBY3_FL_USER_N(12),
    RUBY3_FL_USER_N(13),
    RUBY3_FL_USER_N(14),
    RUBY3_FL_USER_N(15),
    RUBY3_FL_USER_N(16),
    RUBY3_FL_USER_N(17),
    RUBY3_FL_USER_N(18),
#if ENUM_OVER_INT
    RUBY3_FL_USER_N(19),
#else
# define RUBY_FL_USER19 (RUBY3_VALUE_ONE<<(RUBY_FL_USHIFT+19))
#endif
#undef RUBY3_FL_USER_N
#undef RUBY3_WIDER_ENUM

    RUBY_ELTS_SHARED  = RUBY_FL_USER2,
    RUBY_FL_SINGLETON = RUBY_FL_USER0,
};

enum { RUBY_FL_DUPPED = RUBY_T_MASK | RUBY_FL_EXIVAR | RUBY_FL_TAINT };

RUBY3_SYMBOL_EXPORT_BEGIN()
void rb_obj_infect(VALUE victim, VALUE carrier);
void rb_freeze_singleton_class(VALUE klass);
RUBY3_SYMBOL_EXPORT_END()

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
RUBY3_ATTR_FORCEINLINE()
static bool
RB_FL_ABLE(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        return false;
    }
    else if (RB_TYPE_P(obj, RUBY_T_NODE)) {
        return false;
    }
    else {
        return true;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline VALUE
RB_FL_TEST_RAW(VALUE obj, VALUE flags)
{
    RUBY3_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    return RBASIC(obj)->flags & flags;
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline VALUE
RB_FL_TEST(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        return RB_FL_TEST_RAW(obj, flags);
    }
    else {
        return RUBY3_VALUE_NULL;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_FL_ANY_RAW(VALUE obj, VALUE flags)
{
    return RB_FL_TEST_RAW(obj, flags);
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_FL_ANY(VALUE obj, VALUE flags)
{
    return RB_FL_TEST(obj, flags);
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_FL_ALL_RAW(VALUE obj, VALUE flags)
{
    return RB_FL_TEST_RAW(obj, flags) == flags;
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_FL_ALL(VALUE obj, VALUE flags)
{
    return RB_FL_TEST(obj, flags) == flags;
}

RUBY3_ATTR_NOALIAS()
RUBY3_ATTR_ARTIFICIAL()
static inline void
ruby3_fl_set_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags |= flags;
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_FL_SET_RAW(VALUE obj, VALUE flags)
{
    RUBY3_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    ruby3_fl_set_raw_raw(RBASIC(obj), flags);
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_FL_SET(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_SET_RAW(obj, flags);
    }
}

RUBY3_ATTR_NOALIAS()
RUBY3_ATTR_ARTIFICIAL()
static inline void
ruby3_fl_unset_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags &= ~flags;
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_FL_UNSET_RAW(VALUE obj, VALUE flags)
{
    RUBY3_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    ruby3_fl_unset_raw_raw(RBASIC(obj), flags);
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_FL_UNSET(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_UNSET_RAW(obj, flags);
    }
}

RUBY3_ATTR_NOALIAS()
RUBY3_ATTR_ARTIFICIAL()
static inline void
ruby3_fl_reverse_raw_raw(struct RBasic *obj, VALUE flags)
{
    obj->flags ^= flags;
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_FL_REVERSE_RAW(VALUE obj, VALUE flags)
{
    RUBY3_ASSERT_OR_ASSUME(RB_FL_ABLE(obj));
    ruby3_fl_reverse_raw_raw(RBASIC(obj), flags);
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_FL_REVERSE(VALUE obj, VALUE flags)
{
    if (RB_FL_ABLE(obj)) {
        RB_FL_REVERSE_RAW(obj, flags);
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_OBJ_TAINTABLE(VALUE obj)
{
    if (! RB_FL_ABLE(obj)) {
        return false;
    }
    else if (RB_TYPE_P(obj, RUBY_T_BIGNUM)) {
        return false;
    }
    else if (RB_TYPE_P(obj, RUBY_T_FLOAT)) {
        return false;
    }
    else {
        return true;
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline VALUE
RB_OBJ_TAINTED_RAW(VALUE obj)
{
    return RB_FL_TEST_RAW(obj, RUBY_FL_TAINT);
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_OBJ_TAINTED(VALUE obj)
{
    return RB_FL_ANY(obj, RUBY_FL_TAINT);
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_OBJ_TAINT_RAW(VALUE obj)
{
    RB_FL_SET_RAW(obj, RUBY_FL_TAINT);
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_OBJ_TAINT(VALUE obj)
{
    if (RB_OBJ_TAINTABLE(obj)) {
        RB_OBJ_TAINT_RAW(obj);
    }
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_OBJ_INFECT_RAW(VALUE dst, VALUE src)
{
    RUBY3_ASSERT_OR_ASSUME(RB_OBJ_TAINTABLE(dst));
    RUBY3_ASSERT_OR_ASSUME(RB_FL_ABLE(src));
    RB_FL_SET_RAW(dst, RB_OBJ_TAINTED_RAW(src));
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_OBJ_INFECT(VALUE dst, VALUE src)
{
    if (RB_OBJ_TAINTABLE(dst) && RB_FL_ABLE(src)) {
        RB_OBJ_INFECT_RAW(dst, src);
    }
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
/* It is  intentional not to return  bool here. There  is a place in  ruby core
 * (namely class.c:singleton_class_of()) where return value of this function is
 * verbatimly passed to RB_FL_SET_RAW. */
static inline VALUE
RB_OBJ_FROZEN_RAW(VALUE obj)
{
    return RB_FL_TEST_RAW(obj, RUBY_FL_FREEZE);
}

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_ARTIFICIAL()
static inline bool
RB_OBJ_FROZEN(VALUE obj)
{
    if (! RB_FL_ABLE(obj)) {
        return true;
    }
    else {
        return RB_OBJ_FROZEN_RAW(obj);
    }
}

RUBY3_ATTR_ARTIFICIAL()
static inline void
RB_OBJ_FREEZE_RAW(VALUE obj)
{
    RB_FL_SET_RAW(obj, RUBY_FL_FREEZE);
}

static inline void
rb_obj_freeze_inline(VALUE x)
{
    if (RB_FL_ABLE(x)) {
        RB_OBJ_FREEZE_RAW(x);
        if (RBASIC_CLASS(x) && !(RBASIC(x)->flags & RUBY_FL_SINGLETON)) {
            rb_freeze_singleton_class(x);
        }
    }
}

#endif /* RUBY3_FL_TYPE_H */
