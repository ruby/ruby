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
 * @brief      Handling of integers formerly known as Fixnums.
 */
#ifndef  RUBY3_ARITHMETIC_FIXNUM_H
#define  RUBY3_ARITHMETIC_FIXNUM_H
#include "ruby/backward/2/limits.h"

#define FIXABLE    RB_FIXABLE
#define FIXNUM_MAX RUBY_FIXNUM_MAX
#define FIXNUM_MIN RUBY_FIXNUM_MIN
#define NEGFIXABLE RB_NEGFIXABLE
#define POSFIXABLE RB_POSFIXABLE

/*
 * FIXABLE can be applied to anything, from double to intmax_t.  The problem is
 * double.   On a  64bit system  RUBY_FIXNUM_MAX is  4,611,686,018,427,387,903,
 * which is not representable by a double.  The nearest value that a double can
 * represent  is   4,611,686,018,427,387,904,  which   is  not   fixable.   The
 * seemingly-stragne "< FIXNUM_MAX + 1" expression below is due to this.
 */
#define RB_POSFIXABLE(_) ((_) <  RUBY_FIXNUM_MAX + 1)
#define RB_NEGFIXABLE(_) ((_) >= RUBY_FIXNUM_MIN)
#define RB_FIXABLE(_)    (RB_POSFIXABLE(_) && RB_NEGFIXABLE(_))
#define RUBY_FIXNUM_MAX  (LONG_MAX / 2)
#define RUBY_FIXNUM_MIN  (LONG_MIN / 2)

#endif /* RUBY3_ARITHMETIC_FIXNUM_H */
