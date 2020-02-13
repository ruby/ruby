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
#include "ruby/3/core/rbasic.h"
#include "ruby/3/value_type.h"
#include "ruby/backward/2/r_cast.h"

#ifdef __GNUC__
__extension__
#endif
enum ruby_fl_type {
    RUBY_FL_WB_PROTECTED = (1<<5),
    RUBY_FL_PROMOTED0 = (1<<5),
    RUBY_FL_PROMOTED1 = (1<<6),
    RUBY_FL_PROMOTED  = RUBY_FL_PROMOTED0|RUBY_FL_PROMOTED1,
    RUBY_FL_FINALIZE  = (1<<7),
    RUBY_FL_TAINT     = (1<<8),
    RUBY_FL_UNTRUSTED = RUBY_FL_TAINT,
    RUBY_FL_SEEN_OBJ_ID = (1<<9),
    RUBY_FL_EXIVAR    = (1<<10),
    RUBY_FL_FREEZE    = (1<<11),

    RUBY_FL_USHIFT    = 12,

#define RUBY_FL_USER_N(n) RUBY_FL_USER##n = (1<<(RUBY_FL_USHIFT+n))
    RUBY_FL_USER_N(0),
    RUBY_FL_USER_N(1),
    RUBY_FL_USER_N(2),
    RUBY_FL_USER_N(3),
    RUBY_FL_USER_N(4),
    RUBY_FL_USER_N(5),
    RUBY_FL_USER_N(6),
    RUBY_FL_USER_N(7),
    RUBY_FL_USER_N(8),
    RUBY_FL_USER_N(9),
    RUBY_FL_USER_N(10),
    RUBY_FL_USER_N(11),
    RUBY_FL_USER_N(12),
    RUBY_FL_USER_N(13),
    RUBY_FL_USER_N(14),
    RUBY_FL_USER_N(15),
    RUBY_FL_USER_N(16),
    RUBY_FL_USER_N(17),
    RUBY_FL_USER_N(18),
#if defined ENUM_OVER_INT || SIZEOF_INT*CHAR_BIT>12+19+1
    RUBY_FL_USER_N(19),
#else
#define RUBY_FL_USER19 (((VALUE)1)<<(RUBY_FL_USHIFT+19))
#endif

    RUBY_ELTS_SHARED = RUBY_FL_USER2,
    RUBY_FL_DUPPED = (RUBY_T_MASK|RUBY_FL_EXIVAR|RUBY_FL_TAINT),
    RUBY_FL_SINGLETON = RUBY_FL_USER0
};

#define FL_SINGLETON    ((VALUE)RUBY_FL_SINGLETON)
#define FL_WB_PROTECTED ((VALUE)RUBY_FL_WB_PROTECTED)
#define FL_PROMOTED0    ((VALUE)RUBY_FL_PROMOTED0)
#define FL_PROMOTED1    ((VALUE)RUBY_FL_PROMOTED1)
#define FL_FINALIZE     ((VALUE)RUBY_FL_FINALIZE)
#define FL_TAINT        ((VALUE)RUBY_FL_TAINT)
#define FL_UNTRUSTED    ((VALUE)RUBY_FL_UNTRUSTED)
#define FL_SEEN_OBJ_ID  ((VALUE)RUBY_FL_SEEN_OBJ_ID)
#define FL_EXIVAR       ((VALUE)RUBY_FL_EXIVAR)
#define FL_FREEZE       ((VALUE)RUBY_FL_FREEZE)

#define FL_USHIFT       ((VALUE)RUBY_FL_USHIFT)

#define FL_USER0        ((VALUE)RUBY_FL_USER0)
#define FL_USER1        ((VALUE)RUBY_FL_USER1)
#define FL_USER2        ((VALUE)RUBY_FL_USER2)
#define FL_USER3        ((VALUE)RUBY_FL_USER3)
#define FL_USER4        ((VALUE)RUBY_FL_USER4)
#define FL_USER5        ((VALUE)RUBY_FL_USER5)
#define FL_USER6        ((VALUE)RUBY_FL_USER6)
#define FL_USER7        ((VALUE)RUBY_FL_USER7)
#define FL_USER8        ((VALUE)RUBY_FL_USER8)
#define FL_USER9        ((VALUE)RUBY_FL_USER9)
#define FL_USER10       ((VALUE)RUBY_FL_USER10)
#define FL_USER11       ((VALUE)RUBY_FL_USER11)
#define FL_USER12       ((VALUE)RUBY_FL_USER12)
#define FL_USER13       ((VALUE)RUBY_FL_USER13)
#define FL_USER14       ((VALUE)RUBY_FL_USER14)
#define FL_USER15       ((VALUE)RUBY_FL_USER15)
#define FL_USER16       ((VALUE)RUBY_FL_USER16)
#define FL_USER17       ((VALUE)RUBY_FL_USER17)
#define FL_USER18       ((VALUE)RUBY_FL_USER18)
#define FL_USER19       ((VALUE)(unsigned int)RUBY_FL_USER19)

#define RB_FL_ABLE(x) (!RB_SPECIAL_CONST_P(x) && RB_BUILTIN_TYPE(x) != RUBY_T_NODE)
#define RB_FL_TEST_RAW(x,f) (RBASIC(x)->flags&(f))
#define RB_FL_TEST(x,f) (RB_FL_ABLE(x)?RB_FL_TEST_RAW((x),(f)):0)
#define RB_FL_ANY_RAW(x,f) RB_FL_TEST_RAW((x),(f))
#define RB_FL_ANY(x,f) RB_FL_TEST((x),(f))
#define RB_FL_ALL_RAW(x,f) (RB_FL_TEST_RAW((x),(f)) == (f))
#define RB_FL_ALL(x,f) (RB_FL_TEST((x),(f)) == (f))
#define RB_FL_SET_RAW(x,f) (void)(RBASIC(x)->flags |= (f))
#define RB_FL_SET(x,f) (RB_FL_ABLE(x) ? RB_FL_SET_RAW(x, f) : (void)0)
#define RB_FL_UNSET_RAW(x,f) (void)(RBASIC(x)->flags &= ~(VALUE)(f))
#define RB_FL_UNSET(x,f) (RB_FL_ABLE(x) ? RB_FL_UNSET_RAW(x, f) : (void)0)
#define RB_FL_REVERSE_RAW(x,f) (void)(RBASIC(x)->flags ^= (f))
#define RB_FL_REVERSE(x,f) (RB_FL_ABLE(x) ? RB_FL_REVERSE_RAW(x, f) : (void)0)

#define RB_OBJ_TAINTABLE(x) (RB_FL_ABLE(x) && RB_BUILTIN_TYPE(x) != RUBY_T_BIGNUM && RB_BUILTIN_TYPE(x) != RUBY_T_FLOAT)
#define RB_OBJ_TAINTED_RAW(x) RB_FL_TEST_RAW(x, RUBY_FL_TAINT)
#define RB_OBJ_TAINTED(x) (!!RB_FL_TEST((x), RUBY_FL_TAINT))
#define RB_OBJ_TAINT_RAW(x) RB_FL_SET_RAW(x, RUBY_FL_TAINT)
#define RB_OBJ_TAINT(x) (RB_OBJ_TAINTABLE(x) ? RB_OBJ_TAINT_RAW(x) : (void)0)
#define RB_OBJ_UNTRUSTED(x) RB_OBJ_TAINTED(x)
#define RB_OBJ_UNTRUST(x) RB_OBJ_TAINT(x)
#define RB_OBJ_INFECT_RAW(x,s) RB_FL_SET_RAW(x, RB_OBJ_TAINTED_RAW(s))
#define RB_OBJ_INFECT(x,s) ( \
    (RB_OBJ_TAINTABLE(x) && RB_FL_ABLE(s)) ? \
    RB_OBJ_INFECT_RAW(x, s) : (void)0)

#define RB_OBJ_FROZEN_RAW(x) (RBASIC(x)->flags&RUBY_FL_FREEZE)
#define RB_OBJ_FROZEN(x) (!RB_FL_ABLE(x) || RB_OBJ_FROZEN_RAW(x))
#define RB_OBJ_FREEZE_RAW(x) (void)(RBASIC(x)->flags |= RUBY_FL_FREEZE)
#define RB_OBJ_FREEZE(x) rb_obj_freeze_inline((VALUE)x)

/*!
 * \defgroup deprecated_macros deprecated macro APIs
 * \{
 * \par These macros are deprecated. Prefer their `RB_`-prefixed versions.
 */
#define FL_ABLE(x) RB_FL_ABLE(x)
#define FL_TEST_RAW(x,f) RB_FL_TEST_RAW(x,f)
#define FL_TEST(x,f) RB_FL_TEST(x,f)
#define FL_ANY_RAW(x,f) RB_FL_ANY_RAW(x,f)
#define FL_ANY(x,f) RB_FL_ANY(x,f)
#define FL_ALL_RAW(x,f) RB_FL_ALL_RAW(x,f)
#define FL_ALL(x,f) RB_FL_ALL(x,f)
#define FL_SET_RAW(x,f) RB_FL_SET_RAW(x,f)
#define FL_SET(x,f) RB_FL_SET(x,f)
#define FL_UNSET_RAW(x,f) RB_FL_UNSET_RAW(x,f)
#define FL_UNSET(x,f) RB_FL_UNSET(x,f)
#define FL_REVERSE_RAW(x,f) RB_FL_REVERSE_RAW(x,f)
#define FL_REVERSE(x,f) RB_FL_REVERSE(x,f)

#define OBJ_TAINTABLE(x) RB_OBJ_TAINTABLE(x)
#define OBJ_TAINTED_RAW(x) RB_OBJ_TAINTED_RAW(x)
#define OBJ_TAINTED(x) RB_OBJ_TAINTED(x)
#define OBJ_TAINT_RAW(x) RB_OBJ_TAINT_RAW(x)
#define OBJ_TAINT(x) RB_OBJ_TAINT(x)
#define OBJ_UNTRUSTED(x) RB_OBJ_UNTRUSTED(x)
#define OBJ_UNTRUST(x) RB_OBJ_UNTRUST(x)
#define OBJ_INFECT_RAW(x,s) RB_OBJ_INFECT_RAW(x,s)
#define OBJ_INFECT(x,s) RB_OBJ_INFECT(x,s)
#define OBJ_FROZEN_RAW(x) RB_OBJ_FROZEN_RAW(x)
#define OBJ_FROZEN(x) RB_OBJ_FROZEN(x)
#define OBJ_FREEZE_RAW(x) RB_OBJ_FREEZE_RAW(x)
#define OBJ_FREEZE(x) RB_OBJ_FREEZE(x)

/* \} */

#define RUBY_ELTS_SHARED RUBY_ELTS_SHARED
#define ELTS_SHARED RUBY_ELTS_SHARED

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

void rb_obj_infect(VALUE victim, VALUE carrier);

void rb_freeze_singleton_class(VALUE klass);

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

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_FL_TYPE_H */
