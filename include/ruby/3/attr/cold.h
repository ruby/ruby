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
 * @brief      Defines #RUBY3_ATTR_COLD.
 */
#include "ruby/3/compiler_is.h"

/** Wraps (or simulates) `__attribute__((cold))` */
#if defined(RUBY3_ATTR_COLD)
# /* Take that. */

#elif RUBY3_COMPILER_IS(SunPro)
# /* Recent SunPro has __has_attribute, and is borken. */
# /* It reports it has attribute cold, reality isn't (warnings issued). */
# define RUBY3_ATTR_COLD() /* void */

#elif RUBY3_HAS_ATTRIBUTE(cold)
# define RUBY3_ATTR_COLD() __attribute__((__cold__))

#else
# define RUBY3_ATTR_COLD() /* void */
#endif
