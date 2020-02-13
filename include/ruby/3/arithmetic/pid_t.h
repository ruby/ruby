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
 * @brief      Arithmetic conversion between C's `pid_t` and Ruby's.
 */
#ifndef  RUBY3_ARITHMERIC_PID_T_H
#define  RUBY3_ARITHMERIC_PID_T_H
#include "ruby/3/config.h"

#ifdef SYS_TYPES_H
# include <sys/types.h>
#endif

#include "ruby/3/arithmetic/long.h"

#ifndef PIDT2NUM
#define PIDT2NUM(v) LONG2NUM(v)
#endif

#ifndef NUM2PIDT
#define NUM2PIDT(v) NUM2LONG(v)
#endif

#endif /* RUBY3_ARITHMERIC_PID_T_H */
