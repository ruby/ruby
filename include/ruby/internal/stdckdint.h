#ifndef RBIMPL_STDCKDINT_H                           /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_STDCKDINT_H
/**
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
 *             extension libraries.  They could be written in C++98.
 * @brief      C23 shim for <stdckdint.h>
 */
#include "ruby/internal/config.h"
#include "ruby/internal/has/builtin.h"
#include "ruby/internal/stdbool.h"

#ifdef __has_include
# if __has_include(<stdckdint.h>)
#  /* Conforming C23 situation; e.g. recent clang */
#  define RBIMPL_HAVE_STDCKDINT_H
# endif
#endif

#ifdef HAVE_STDCKDINT_H
# /* Some OSes (most notably FreeBSD) have this file. */
# define RBIMPL_HAVE_STDCKDINT_H
#endif

#ifdef RBIMPL_HAVE_STDCKDINT_H
# /* Take that. */
# include <stdckdint.h>

#elif RBIMPL_HAS_BUILTIN(__builtin_add_overflow)
# define ckd_add(x, y, z) ((bool)__builtin_add_overflow((y), (z), (x)))
# define ckd_sub(x, y, z) ((bool)__builtin_sub_overflow((y), (z), (x)))
# define ckd_mul(x, y, z) ((bool)__builtin_mul_overflow((y), (z), (x)))
# define __STDC_VERSION_STDCKDINT_H__ 202311L

#/* elif defined(__cplusplus) */
#/* :TODO: if we assume C++11 we can use `<type_traits>` to implement them. */

#else
# /* intentionally leave them undefined */
# /* to make `#ifdef ckd_add` etc. work as intended. */
# undef ckd_add
# undef ckd_sub
# undef ckd_mul
# undef __STDC_VERSION_STDCKDINT_H__
#endif

#endif /* RBIMPL_STDCKDINT_H */
