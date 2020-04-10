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
 * @brief      #RUBY3_ATTR_CONSTEXPR.
 */
#include "ruby/3/has/feature.h"
#include "ruby/3/compiler_is.h"

/** @cond INTERNAL_MACRO*/
#if defined(RUBY3_ATTR_CONSTEXPR)
# /* Take that. */

#elif ! defined(__cplusplus)
# /* Makes no sense. */
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 0
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 0

#elif defined(__cpp_constexpr)
# /* https://isocpp.org/std/standing-documents/sd-6-sg10-feature-test-recommendations */
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 (__cpp_constexpr >= 200704L)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 (__cpp_constexpr >= 201304L)

#elif RUBY3_COMPILER_SINCE(MSVC, 19, 0, 0)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 RUBY3_COMPILER_SINCE(MSVC, 19, 00, 00)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 RUBY3_COMPILER_SINCE(MSVC, 19, 11, 00)

#elif RUBY3_COMPILER_SINCE(SunPro, 5, 13, 0)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 (__cplusplus >= 201103L)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 (__cplusplus >= 201402L)

#elif RUBY3_COMPILER_SINCE(GCC, 4, 9, 0)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 (__cplusplus >= 201103L)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 (__cplusplus >= 201402L)

#elif RUBY3_HAS_FEATURE(cxx_relaxed_constexpr)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 1
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 1

#elif RUBY3_HAS_FEATURE(cxx_constexpr)
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 1
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 0

#else
# /* :FIXME: icpc must have constexpr but don't know how to detect. */
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX11 0
# define RUBY3_HAS_ATTR_CONSTEXPR_CXX14 0
#endif
/** @endcond */

/** Wraps (or simulates) C++11 `constexpr`.  */
#if defined(RUBY3_ATTR_CONSTEXPR)
# /* Take that. */

#elif RUBY3_HAS_ATTR_CONSTEXPR_CXX14
# define RUBY3_ATTR_CONSTEXPR(_) constexpr

#elif RUBY3_HAS_ATTR_CONSTEXPR_CXX11
# define RUBY3_ATTR_CONSTEXPR(_) RUBY3_TOKEN_PASTE(RUBY3_ATTR_CONSTEXPR_, _)
# define RUBY3_ATTR_CONSTEXPR_CXX11 constexpr
# define RUBY3_ATTR_CONSTEXPR_CXX14 /* void */

#else
# define RUBY3_ATTR_CONSTEXPR(_) /* void */
#endif

/** Enables #RUBY3_ATTR_CONSTEXPR iff. #RUBY_NDEBUG. */
#if defined(RUBY3_ATTR_CONSTEXPR_ON_NDEBUG)
# /* Take that. */

#elif RUBY_NDEBUG
# define RUBY3_ATTR_CONSTEXPR_ON_NDEBUG(_) RUBY3_ATTR_CONSTEXPR(_)

#else
# define RUBY3_ATTR_CONSTEXPR_ON_NDEBUG(_) /* void */
#endif
