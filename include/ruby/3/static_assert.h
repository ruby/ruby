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
 * @brief      Defines #RUBY3_STATIC_ASSERT.
 */
#include <assert.h>
#include "ruby/3/has/extension.h"

/** @cond INTERNAL_MACRO */
#if defined(RUBY3_STATIC_ASSERT0)
# /* Take that. */

#elif defined(__cplusplus) && defined(__cpp_static_assert)
# /* https://isocpp.org/std/standing-documents/sd-6-sg10-feature-test-recommendations */
# define RUBY3_STATIC_ASSERT0 static_assert

#elif defined(__cplusplus) && RUBY3_COMPILER_SINCE(MSVC, 16, 0, 0)
# define RUBY3_STATIC_ASSERT0 static_assert

#elif defined(__INTEL_CXX11_MODE__)
# define RUBY3_STATIC_ASSERT0 static_assert

#elif defined(__cplusplus) && __cplusplus >= 201103L
# define RUBY3_STATIC_ASSERT0 static_assert

#elif defined(__cplusplus) && RUBY3_HAS_EXTENSION(cxx_static_assert)
# define RUBY3_STATIC_ASSERT0 __extension__ static_assert

#elif defined(__GXX_EXPERIMENTAL_CXX0X__) && __GXX_EXPERIMENTAL_CXX0X__
# define RUBY3_STATIC_ASSERT0 __extension__ static_assert

#elif defined(__STDC_VERSION__) && RUBY3_HAS_EXTENSION(c_static_assert)
# define RUBY3_STATIC_ASSERT0 __extension__ _Static_assert

#elif defined(__STDC_VERSION__) && RUBY3_COMPILER_SINCE(GCC, 4, 6, 0)
# define RUBY3_STATIC_ASSERT0 __extension__ _Static_assert

#elif defined(static_assert)
# /* Take <assert.h> definition */
# define RUBY3_STATIC_ASSERT0 static_assert
#endif
/** @endcond */

/**
 * @brief  Wraps (or simulates) `static_assert`
 * @param  name  Valid C/C++ identifier, describing the assertion.
 * @param  expr  Expression to assert.
 * @note   `name` shall not be a string literal.
 */
#if defined(RUBY3_STATIC_ASSERT)
# /* Take that. */

#elif defined(__DOXYGEN__)
# define RUBY3_STATIC_ASSERT static_assert

#elif defined(RUBY3_STATIC_ASSERT0)
# define RUBY3_STATIC_ASSERT(name, expr) \
    RUBY3_STATIC_ASSERT0(expr, # name ": " # expr)

#else
# define RUBY3_STATIC_ASSERT(name, expr) \
    typedef int static_assert_ ## name ## _check[1 - 2 * !(expr)]
#endif
