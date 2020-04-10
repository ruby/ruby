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
 * @brief      Defines #RUBY3_TOKEN_PASTE.
 */
#include "ruby/3/config.h"

/* :TODO: add your  compiler here.  There are many compilers  that can suppress
 * warnings via pragmas, but not all of them accept such things inside of `#if`
 * and  variants'  conditions.   And  such nitpicking  behavours  tend  not  be
 * documented.  Please  improve this file when  you are really sure  about your
 * compiler's behaviour. */

#if defined(RUBY3_TOKEN_PASTE)
# /* Take that. */

#elif RUBY3_COMPILER_SINCE(GCC, 4, 2, 0)
# /* GCC is one of such compiler who  cannot write `_Pragma` inside of a `#if`.
#  * Cannot but globally kill everything.  This  is of course a very bad thing.
#  * If you know how to reroute this please tell us. */
# /* https://gcc.godbolt.org/z/K2xr7X */
# define RUBY3_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
# pragma GCC diagnostic ignored "-Wundef"
# /* > warning: "symbol" is not defined, evaluates to 0 [-Wundef] */

#elif RUBY3_COMPILER_IS(Intel)
# /* Ditto for icc. */
# /* https://gcc.godbolt.org/z/pTwDxE */
# define RUBY3_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
# pragma warning(disable: 193)
# /* > warning #193: zero used for undefined preprocessing identifier */

#elif RUBY3_COMPILER_BEFORE(MSVC, 19, 14, 26428)
# /* :FIXME: is 19.14 the exact version they supported this? */
# define RUBY3_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
# pragma warning(disable: 4668)
# /* > warning C4668: 'symbol' is not defined as a preprocessor macro */

#elif RUBY3_COMPILER_IS(MSVC)
# define RUBY3_TOKEN_PASTE(x, y) \
    RUBY3_WARNING_PUSH()         \
    RUBY3_WARNING_IGNORED(4668)  \
    TOKEN_PASTE(x, y)            \
    RUBY3_WARNING_POP()

#elif RUBY3_HAS_WARNING("-Wundef")
# define RUBY3_TOKEN_PASTE(x, y)   \
    RUBY3_WARNING_PUSH()           \
    RUBY3_WARNING_IGNORED(-Wundef) \
    TOKEN_PASTE(x, y)              \
    RUBY3_WARNING_POP()

#else
# /* No way. */
# define RUBY3_TOKEN_PASTE(x, y) TOKEN_PASTE(x, y)
#endif
