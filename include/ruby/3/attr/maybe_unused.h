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
 * @brief      Defines #RUBY3_ATTR_MAYBE_UNUSED.
 */
#include "ruby/3/has/c_attribute.h"
#include "ruby/3/has/cpp_attribute.h"

/** Wraps  (or simulates)  `[[maybe_unused]]` */
#if defined(RUBY3_ATTR_MAYBE_UNUSED)
# /* Take that. */

#elif RUBY3_HAS_CPP_ATTRIBUTE(maybe_unused)
# define RUBY3_ATTR_MAYBE_UNUSED() [[maybe_unused]]

#elif RUBY3_HAS_C_ATTRIBUTE(maybe_unused)
# define RUBY3_ATTR_MAYBE_UNUSED() [[maybe_unused]]

#elif RUBY3_HAS_ATTRIBUTE(unused)
# define RUBY3_ATTR_MAYBE_UNUSED() __attribute__((__unused__))

#else
# define RUBY3_ATTR_MAYBE_UNUSED() /* void */
#endif
