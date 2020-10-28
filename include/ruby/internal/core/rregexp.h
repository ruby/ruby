#ifndef RBIMPL_RREGEXP_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RREGEXP_H
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
 * @brief      Defines struct ::RRegexp.
 */
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/core/rstring.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"

#define RREGEXP(obj)     RBIMPL_CAST((struct RRegexp *)(obj))
#define RREGEXP_PTR(obj) (RREGEXP(obj)->ptr)
/** @cond INTERNAL_MACRO */
#define RREGEXP_SRC      RREGEXP_SRC
#define RREGEXP_SRC_PTR  RREGEXP_SRC_PTR
#define RREGEXP_SRC_LEN  RREGEXP_SRC_LEN
#define RREGEXP_SRC_END  RREGEXP_SRC_END
/** @endcond */

struct re_patter_buffer; /* a.k.a. OnigRegexType, defined in onigmo.h */

struct RRegexp {
    struct RBasic basic;
    struct re_pattern_buffer *ptr;
    const VALUE src;
    unsigned long usecnt;
};

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline VALUE
RREGEXP_SRC(VALUE rexp)
{
    RBIMPL_ASSERT_TYPE(rexp, RUBY_T_REGEXP);
    VALUE ret = RREGEXP(rexp)->src;
    RBIMPL_ASSERT_TYPE(ret, RUBY_T_STRING);
    return ret;
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline char *
RREGEXP_SRC_PTR(VALUE rexp)
{
    return RSTRING_PTR(RREGEXP_SRC(rexp));
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline long
RREGEXP_SRC_LEN(VALUE rexp)
{
    return RSTRING_LEN(RREGEXP_SRC(rexp));
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline char *
RREGEXP_SRC_END(VALUE rexp)
{
    return RSTRING_END(RREGEXP_SRC(rexp));
}

#endif /* RBIMPL_RREGEXP_H */
