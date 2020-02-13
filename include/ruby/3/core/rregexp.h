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
 * @brief      Defines struct ::RRegexp.
 */
#ifndef  RUBY3_RREGEXP_H
#define  RUBY3_RREGEXP_H
#include "ruby/3/core/rbasic.h"
#include "ruby/3/core/rstring.h"
#include "ruby/3/value.h"
#include "ruby/backward/2/r_cast.h"

struct RRegexp {
    struct RBasic basic;
    struct re_pattern_buffer *ptr;
    const VALUE src;
    unsigned long usecnt;
};
#define RREGEXP_PTR(r) (RREGEXP(r)->ptr)
#define RREGEXP_SRC(r) (RREGEXP(r)->src)
#define RREGEXP_SRC_PTR(r) RSTRING_PTR(RREGEXP(r)->src)
#define RREGEXP_SRC_LEN(r) RSTRING_LEN(RREGEXP(r)->src)
#define RREGEXP_SRC_END(r) RSTRING_END(RREGEXP(r)->src)

#define RREGEXP(obj) (R_CAST(RRegexp)(obj))

#endif /* RUBY3_RREGEXP_H */
