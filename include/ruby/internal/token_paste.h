#ifndef RBIMPL_TOKEN_PASTE_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_TOKEN_PASTE_H
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
 * @brief      Defines #RBIMPL_TOKEN_PASTE.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/has/warning.h"
#include "ruby/internal/warning_push.h"

/* :TODO: add your  compiler here.  There are many compilers  that can suppress
 * warnings via pragmas, but not all of them accept such things inside of `#if`
 * and  variants'  conditions.   And  such nitpicking  behavours  tend  not  be
 * documented.  Please  improve this file when  you are really sure  about your
 * compiler's behaviour. */

#if RBIMPL_COMPILER_SINCE(GCC, 4, 2, 0)
# /* GCC is one of such compiler who  cannot write `_Pragma` inside of a `#if`.
#  * Cannot but globally kill everything.  This  is of course a very bad thing.
#  * If you know how to reroute this please tell us. */
# /* https://gcc.godbolt.org/z/K2xr7X */
# define RBIMPL_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
# pragma GCC diagnostic ignored "-Wundef"
# /* > warning: "symbol" is not defined, evaluates to 0 [-Wundef] */

#elif RBIMPL_COMPILER_IS(Intel)
# /* Ditto for icc. */
# /* https://gcc.godbolt.org/z/pTwDxE */
# define RBIMPL_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
# pragma warning(disable: 193)
# /* > warning #193: zero used for undefined preprocessing identifier */

#elif RBIMPL_COMPILER_BEFORE(MSVC, 19, 14, 26428)
# /* :FIXME: is 19.14 the exact version they supported this? */
# define RBIMPL_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
# pragma warning(disable: 4668)
# /* > warning C4668: 'symbol' is not defined as a preprocessor macro */

#elif RBIMPL_COMPILER_IS(MSVC)
# define RBIMPL_TOKEN_PASTE(x, y) \
    RBIMPL_WARNING_PUSH()         \
    RBIMPL_WARNING_IGNORED(4668)  \
    TOKEN_PASTE(x, y)            \
    RBIMPL_WARNING_POP()

#elif RBIMPL_HAS_WARNING("-Wundef")
# define RBIMPL_TOKEN_PASTE(x, y)   \
    RBIMPL_WARNING_PUSH()           \
    RBIMPL_WARNING_IGNORED(-Wundef) \
    TOKEN_PASTE(x, y)              \
    RBIMPL_WARNING_POP()

#else
# /* No way. */
# define RBIMPL_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
#endif

#endif /* RBIMPL_TOKEN_PASTE_H */
