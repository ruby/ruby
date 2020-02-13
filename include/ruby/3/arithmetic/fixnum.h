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
#include "ruby/3/config.h"
#include "ruby/backward/2/limits.h"

#define RUBY_FIXNUM_MAX (LONG_MAX>>1)
#define RUBY_FIXNUM_MIN RSHIFT((long)LONG_MIN,1)
#define FIXNUM_MAX RUBY_FIXNUM_MAX
#define FIXNUM_MIN RUBY_FIXNUM_MIN
#define RB_POSFIXABLE(f) ((f) < RUBY_FIXNUM_MAX+1)
#define RB_NEGFIXABLE(f) ((f) >= RUBY_FIXNUM_MIN)
#define RB_FIXABLE(f) (RB_POSFIXABLE(f) && RB_NEGFIXABLE(f))
#define POSFIXABLE(f) RB_POSFIXABLE(f)
#define NEGFIXABLE(f) RB_NEGFIXABLE(f)
#define FIXABLE(f) RB_FIXABLE(f)

#endif /* RUBY3_ARITHMETIC_FIXNUM_H */
