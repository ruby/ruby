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
 * @brief      Defines struct ::RMatch.
 */
#ifndef  RUBY3_RMATCH_H
#define  RUBY3_RMATCH_H
#include "ruby/3/attr/artificial.h"
#include "ruby/3/attr/pure.h"
#include "ruby/3/attr/returns_nonnull.h"
#include "ruby/3/cast.h"
#include "ruby/3/core/rbasic.h"
#include "ruby/3/value.h"
#include "ruby/3/value_type.h"
#include "ruby/assert.h"

#define RMATCH(obj) RUBY3_CAST((struct RMatch *)(obj))
/** @cond INTERNAL_MACRO */
#define RMATCH_REGS RMATCH_REGS
/** @endcond */

struct re_patter_buffer; /* a.k.a. OnigRegexType, defined in onigmo.h */
struct re_registers;     /* Also in onigmo.h */

/* @shyouhei wonders: is anyone actively using this typedef ...? */
typedef struct re_pattern_buffer Regexp;

struct rmatch_offset {
    long beg;
    long end;
};

struct rmatch {
    struct re_registers regs;

    struct rmatch_offset *char_offset;
    int char_offset_num_allocated;
};

struct RMatch {
    struct RBasic basic;
    VALUE str;
    struct rmatch *rmatch;
    VALUE regexp;  /* RRegexp */
};

RUBY3_ATTR_PURE_ON_NDEBUG()
RUBY3_ATTR_RETURNS_NONNULL()
RUBY3_ATTR_ARTIFICIAL()
static inline struct re_registers *
RMATCH_REGS(VALUE match)
{
    RUBY3_ASSERT_TYPE(match, RUBY_T_MATCH);
    RUBY3_ASSERT_OR_ASSUME(RMATCH(match)->rmatch != NULL);
    return &RMATCH(match)->rmatch->regs;
}

#endif /* RUBY3_RMATCH_H */
