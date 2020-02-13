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
 * @brief      Arithmetic conversion between C's `size_t` and Ruby's.
 */
#ifndef  RUBY3_ARITHMERIC_SIZE_T_H
#define  RUBY3_ARITHMERIC_SIZE_T_H
#include "ruby/3/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef SYS_TYPES_H
# include <sys/types.h>
#endif

#include "ruby/3/arithmetic/int.h"
#include "ruby/3/arithmetic/long.h"
#include "ruby/3/arithmetic/long_long.h"
#include "ruby/3/value.h"
#include "ruby/backward/2/long_long.h"

#if SIZEOF_SIZE_T > SIZEOF_LONG && defined(HAVE_LONG_LONG)
# define SIZET2NUM(v) ULL2NUM(v)
# define SSIZET2NUM(v) LL2NUM(v)
#elif SIZEOF_SIZE_T == SIZEOF_LONG
# define SIZET2NUM(v) ULONG2NUM(v)
# define SSIZET2NUM(v) LONG2NUM(v)
#else
# define SIZET2NUM(v) UINT2NUM(v)
# define SSIZET2NUM(v) INT2NUM(v)
#endif

#if defined(HAVE_LONG_LONG) && SIZEOF_SIZE_T > SIZEOF_LONG
# define NUM2SIZET(x) ((size_t)NUM2ULL(x))
# define NUM2SSIZET(x) ((ssize_t)NUM2LL(x))
#else
# define NUM2SIZET(x) NUM2ULONG(x)
# define NUM2SSIZET(x) NUM2LONG(x)
#endif

#endif /* RUBY3_ARITHMERIC_SIZE_T_H */
