#ifndef RBIMPL_SPECIAL_CONSTS_H                      /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_SPECIAL_CONSTS_H
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
 * @brief      Defines enum ::ruby_special_consts.
 * @see        Sasada,  K.,  "A   Lighweight  Representation  of  Floting-Point
 *             Numbers  on  Ruby Interpreter",  in  proceedings  of 10th  JSSST
 *             SIGPPL  Workshop   on  Programming  and   Programming  Languages
 *             (PPL2008), pp. 9-16, 2008.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/enum_extensibility.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"

#if defined(USE_FLONUM)
# /* Take that. */
#elif SIZEOF_VALUE >= SIZEOF_DOUBLE
# define USE_FLONUM 1
#else
# define USE_FLONUM 0
#endif

#define RTEST           RB_TEST

#define FIXNUM_P        RB_FIXNUM_P
#define IMMEDIATE_P     RB_IMMEDIATE_P
#define NIL_P           RB_NIL_P
#define SPECIAL_CONST_P RB_SPECIAL_CONST_P
#define STATIC_SYM_P    RB_STATIC_SYM_P

#define Qfalse          RUBY_Qfalse
#define Qnil            RUBY_Qnil
#define Qtrue           RUBY_Qtrue
#define Qundef          RUBY_Qundef

/** @cond INTERNAL_MACRO */
#define FIXNUM_FLAG        RUBY_FIXNUM_FLAG
#define FLONUM_FLAG        RUBY_FLONUM_FLAG
#define FLONUM_MASK        RUBY_FLONUM_MASK
#define FLONUM_P           RB_FLONUM_P
#define IMMEDIATE_MASK     RUBY_IMMEDIATE_MASK
#define SYMBOL_FLAG        RUBY_SYMBOL_FLAG

#define RB_FIXNUM_P        RB_FIXNUM_P
#define RB_FLONUM_P        RB_FLONUM_P
#define RB_IMMEDIATE_P     RB_IMMEDIATE_P
#define RB_NIL_P           RB_NIL_P
#define RB_SPECIAL_CONST_P RB_SPECIAL_CONST_P
#define RB_STATIC_SYM_P    RB_STATIC_SYM_P
#define RB_TEST            RB_TEST
/** @endcond */

/** special constants - i.e. non-zero and non-fixnum constants */
enum
RBIMPL_ATTR_ENUM_EXTENSIBILITY(closed)
ruby_special_consts {
#if USE_FLONUM
    RUBY_Qfalse         = 0x00, /* ...0000 0000 */
    RUBY_Qtrue          = 0x14, /* ...0001 0100 */
    RUBY_Qnil           = 0x08, /* ...0000 1000 */
    RUBY_Qundef         = 0x34, /* ...0011 0100 */
    RUBY_IMMEDIATE_MASK = 0x07, /* ...0000 0111 */
    RUBY_FIXNUM_FLAG    = 0x01, /* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x03, /* ...0000 0011 */
    RUBY_FLONUM_FLAG    = 0x02, /* ...xxxx xx10 */
    RUBY_SYMBOL_FLAG    = 0x0c, /* ...xxxx 1100 */
#else
    RUBY_Qfalse         = 0x00, /* ...0000 0000 */
    RUBY_Qtrue          = 0x02, /* ...0000 0010 */
    RUBY_Qnil           = 0x04, /* ...0000 0100 */
    RUBY_Qundef         = 0x06, /* ...0000 0110 */
    RUBY_IMMEDIATE_MASK = 0x03, /* ...0000 0011 */
    RUBY_FIXNUM_FLAG    = 0x01, /* ...xxxx xxx1 */
    RUBY_FLONUM_MASK    = 0x00, /* any values ANDed with FLONUM_MASK cannot be FLONUM_FLAG */
    RUBY_FLONUM_FLAG    = 0x02, /* ...0000 0010 */
    RUBY_SYMBOL_FLAG    = 0x0e, /* ...0000 1110 */
#endif

    RUBY_SPECIAL_SHIFT  = 8 /** Least significant 8 bits are reserved. */
};

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
/*
 * :NOTE: rbimpl_test HAS to be  `__attribute__((const))` in order for clang to
 * properly deduce `__builtin_assume()`.
 */
static inline bool
RB_TEST(VALUE obj)
{
    /*
     *  Qfalse:  ....0000 0000
     *  Qnil:    ....0000 1000
     * ~Qnil:    ....1111 0111
     *  v        ....xxxx xxxx
     * ----------------------------
     *  RTEST(v) ....xxxx 0xxx
     *
     *  RTEST(v) can be 0 if and only if (v == Qfalse || v == Qnil).
     */
    return obj & ~RUBY_Qnil;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_NIL_P(VALUE obj)
{
    return obj == RUBY_Qnil;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_FIXNUM_P(VALUE obj)
{
    return obj & RUBY_FIXNUM_FLAG;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX14)
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_STATIC_SYM_P(VALUE obj)
{
    RBIMPL_ATTR_CONSTEXPR(CXX14)
    const VALUE mask = ~(RBIMPL_VALUE_FULL << RUBY_SPECIAL_SHIFT);
    return (obj & mask) == RUBY_SYMBOL_FLAG;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_FLONUM_P(VALUE obj)
{
#if USE_FLONUM
    return (obj & RUBY_FLONUM_MASK) == RUBY_FLONUM_FLAG;
#else
    return false;
#endif
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_IMMEDIATE_P(VALUE obj)
{
    return obj & RUBY_IMMEDIATE_MASK;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RB_SPECIAL_CONST_P(VALUE obj)
{
    return RB_IMMEDIATE_P(obj) || ! RB_TEST(obj);
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
/* This  function is  to mimic  old  rb_special_const_p macro  but have  anyone
 * actually used its return value?  Wasn't it just something no one needed? */
static inline VALUE
rb_special_const_p(VALUE obj)
{
    return RB_SPECIAL_CONST_P(obj) * RUBY_Qtrue;
}

/**
 * @cond INTERNAL_MACRO
 * See [ruby-dev:27513] for the following macros.
 */
#define RUBY_Qfalse RBIMPL_CAST((VALUE)RUBY_Qfalse)
#define RUBY_Qtrue  RBIMPL_CAST((VALUE)RUBY_Qtrue)
#define RUBY_Qnil   RBIMPL_CAST((VALUE)RUBY_Qnil)
#define RUBY_Qundef RBIMPL_CAST((VALUE)RUBY_Qundef)
/** @endcond */

#endif /* RBIMPL_SPECIAL_CONSTS_H */
