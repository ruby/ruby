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
 * @brief      Defines #RUBY3_ALIGNAS / #RUBY3_ALIGNOF
 */
#include "ruby/3/config.h"

#ifdef HAVE_STDALIGN_H
# include <stdalign.h>
#endif

#include "ruby/3/compiler_is.h"
#include "ruby/3/has/feature.h"
#include "ruby/3/has/extension.h"
#include "ruby/3/has/declspec_attribute.h"

/**
 * Wraps (or simulates) `alignas`. This is C++11's `alignas` and is _different_
 * from C11 `_Alignas`.  For instance,
 *
 * ```CXX
 * typedef struct alignas(128) foo { int foo } foo;
 * ```
 *
 * is a valid C++ while
 *
 * ```C
 * typedef struct _Alignas(128) foo { int foo } foo;
 * ```
 *
 * is an invalid C because:
 *
 * - You cannot `struct _Alignas`.
 * - A `typedef` cannot have alignments.
 */
#if defined(RUBY3_ALIGNAS)
# /* OK, take that. */

#elif defined(__cplusplus) && RUBY3_HAS_FEATURE(cxx_alignas)
# define RUBY3_ALIGNAS alignas

#elif defined(__cplusplus) && (__cplusplus >= 201103L)
# define RUBY3_ALIGNAS alignas

#elif defined(__INTEL_CXX11_MODE__)
# define RUBY3_ALIGNAS alignas

#elif defined(__GXX_EXPERIMENTAL_CXX0X__)
# define RUBY3_ALIGNAS alignas

#elif RUBY3_HAS_DECLSPEC_ATTRIBUTE(align)
# define RUBY3_ALIGNAS(_) __declspec(align(_))

#elif RUBY3_HAS_ATTRIBUTE(aliged)
# define RUBY3_ALIGNAS(_) __attribute__((__aligned__(_)))

#else
# define RUBY3_ALIGNAS(_) /* void */
#endif

/**
 * Wraps (or  simulates) `alignof`.   Unlike #RUBY3_ALIGNAS,  we can  safely say
 * both C/C++ definitions are effective.
 */
#ifdef RUBY3_ALIGNOF
# /* OK, take that. */

#elif defined(__cplusplus) && RUBY3_HAS_EXTENSION(cxx_alignof)
# define RUBY3_ALIGNOF __extension__ alignof

#elif defined(__cplusplus) && (__cplusplus >= 201103L)
# define RUBY3_ALIGNOF alignof

#elif defined(__INTEL_CXX11_MODE__)
# define RUBY3_ALIGNOF alignof

#elif defined(__GXX_EXPERIMENTAL_CXX0X__)
# define RUBY3_ALIGNOF alignof

#elif defined(__STDC_VERSION__) && RUBY3_HAS_EXTENSION(c_alignof)
# define RUBY3_ALIGNOF __extension__ _Alignof

#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
# define RUBY3_ALIGNOF _Alignof

#elif RUBY3_COMPILER_IS(MSVC)
# define RUBY3_ALIGNOF __alignof

#elif defined(__GNUC__)
# /* At least GCC 2.95 had this. */
# define RUBY3_ALIGNOF __extension__ __alignof__

#elif defined(__alignof_is_defined) || defined(__DOXYGEN__)
# /* OK, we can safely take <stdalign.h> definition. */
# define RUBY3_ALIGNOF alignof

#elif RUBY3_COMPILER_SINCE(SunPro, 5, 9, 0)
# /* According to their  manual, Sun Studio 12 introduced  __alignof__ for both
#  * C/C++. */
# define RUBY3_ALIGNOF __alignof__

#elif 0
# /* THIS IS NG, you cannot define a new type inside of offsetof. */
# /* see: http://www.open-std.org/jtc1/sc22/wg14/www/docs/n2350.htm */
# define RUBY3_ALIGNOF(T) offsetof(struct { char _; T t; }, t)

#else
# error :FIXME: add your compiler here to obtain an alignment.
#endif
