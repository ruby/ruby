#ifndef RBIMPL_STDALIGN_H                            /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_STDALIGN_H
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
 * @brief      Defines #RBIMPL_ALIGNAS / #RBIMPL_ALIGNOF
 */
#include "ruby/internal/config.h"

#ifdef HAVE_STDALIGN_H
# include <stdalign.h>
#endif

#include "ruby/internal/compiler_is.h"
#include "ruby/internal/compiler_since.h"
#include "ruby/internal/has/feature.h"
#include "ruby/internal/has/extension.h"
#include "ruby/internal/has/attribute.h"
#include "ruby/internal/has/declspec_attribute.h"

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
#if defined(__cplusplus) && RBIMPL_HAS_FEATURE(cxx_alignas)
# define RBIMPL_ALIGNAS alignas

#elif defined(__cplusplus) && (__cplusplus >= 201103L)
# define RBIMPL_ALIGNAS alignas

#elif defined(__INTEL_CXX11_MODE__)
# define RBIMPL_ALIGNAS alignas

#elif defined(__GXX_EXPERIMENTAL_CXX0X__)
# define RBIMPL_ALIGNAS alignas

#elif RBIMPL_HAS_DECLSPEC_ATTRIBUTE(align)
# define RBIMPL_ALIGNAS(_) __declspec(align(_))

#elif RBIMPL_HAS_ATTRIBUTE(aliged)
# define RBIMPL_ALIGNAS(_) __attribute__((__aligned__(_)))

#else
# define RBIMPL_ALIGNAS(_) /* void */
#endif

/**
 * Wraps (or simulates)  `alignof`.  Unlike #RBIMPL_ALIGNAS, we  can safely say
 * both C/C++ definitions are effective.
 */
#if defined(__cplusplus) && RBIMPL_HAS_EXTENSION(cxx_alignof)
# define RBIMPL_ALIGNOF __extension__ alignof

#elif defined(__cplusplus) && (__cplusplus >= 201103L)
# define RBIMPL_ALIGNOF alignof

#elif defined(__INTEL_CXX11_MODE__)
# define RBIMPL_ALIGNOF alignof

#elif defined(__GXX_EXPERIMENTAL_CXX0X__)
# define RBIMPL_ALIGNOF alignof

#elif defined(__STDC_VERSION__) && RBIMPL_HAS_EXTENSION(c_alignof)
# define RBIMPL_ALIGNOF __extension__ _Alignof

#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
# define RBIMPL_ALIGNOF _Alignof

#elif RBIMPL_COMPILER_IS(MSVC)
# define RBIMPL_ALIGNOF __alignof

#elif defined(__GNUC__)
# /* At least GCC 2.95 had this. */
# define RBIMPL_ALIGNOF __extension__ __alignof__

#elif defined(__alignof_is_defined) || defined(__DOXYGEN__)
# /* OK, we can safely take <stdalign.h> definition. */
# define RBIMPL_ALIGNOF alignof

#elif RBIMPL_COMPILER_SINCE(SunPro, 5, 9, 0)
# /* According to their  manual, Sun Studio 12 introduced  __alignof__ for both
#  * C/C++. */
# define RBIMPL_ALIGNOF __alignof__

#elif 0
# /* THIS IS NG, you cannot define a new type inside of offsetof. */
# /* see: http://www.open-std.org/jtc1/sc22/wg14/www/docs/n2350.htm */
# define RBIMPL_ALIGNOF(T) offsetof(struct { char _; T t; }, t)

#else
# error :FIXME: add your compiler here to obtain an alignment.
#endif

#endif /* RBIMPL_STDALIGN_H */
