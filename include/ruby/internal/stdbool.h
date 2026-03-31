#ifndef RBIMPL_STDBOOL_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_STDBOOL_H
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
 *             extension libraries.  They could be written in C++98.
 * @brief      C99 shim for <stdbool.h>
 */
#include "ruby/internal/config.h"

#if defined(__bool_true_false_are_defined)
# /* Take that. */

#elif defined(__cplusplus)
# /* bool is a keyword in C++. */
# ifndef __bool_true_false_are_defined
#  define __bool_true_false_are_defined
# endif

#else
# /* Take stdbool.h definition. It exists since GCC 3.0 and VS 2015. */
# include <stdbool.h>
#endif

#endif /* RBIMPL_STDBOOL_H */
