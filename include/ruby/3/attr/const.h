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
 * @brief      Defines #RUBY3_ATTR_CONST.
 */
#include "ruby/3/has/declspec_attribute.h"

/** Wraps (or simulates) `__attribute__((const))` */
#if defined(RUBY3_ATTR_CONST)
# /* Take that. */

#elif RUBY3_HAS_ATTRIBUTE(const)
# define RUBY3_ATTR_CONST() __attribute__((__const__))

#elif RUBY3_HAS_DECLSPEC_ATTRIBUTE(noalias)
# /* If a function can be a const, that is also a noalias. */
# define RUBY3_ATTR_CONST() __declspec(noalias)

#elif RUBY3_COMPILER_SINCE(SunPro, 5, 10, 0)
# define RUBY3_ATTR_CONST() _Pragma("no_side_effect")

#else
# define RUBY3_ATTR_CONST() /* void */
#endif

/** Enables #RUBY3_ATTR_CONST iff. #RUBY_NDEBUG. */
#if defined(RUBY3_ATTR_CONST_ON_NDEBUG)
# /* Take that. */

#elif RUBY_NDEBUG
# define RUBY3_ATTR_CONST_ON_NDEBUG() RUBY3_ATTR_CONST()

#else
# define RUBY3_ATTR_CONST_ON_NDEBUG() /* void */
#endif
