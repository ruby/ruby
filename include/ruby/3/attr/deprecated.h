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
 * @brief      Defines #RUBY3_ATTR_DEPRECATED.
 */
#include "ruby/3/has/c_attribute.h"
#include "ruby/3/has/cpp_attribute.h"
#include "ruby/3/has/declspec_attribute.h"
#include "ruby/3/has/extension.h"

/** Wraps (or simulates) `[[deprecated]]` */
#if defined(RUBY3_ATTR_DEPRECATED)
# /* Take that. */

#elif RUBY3_HAS_EXTENSION(attribute_deprecated_with_message)
# define RUBY3_ATTR_DEPRECATED(msg) __attribute__((__deprecated__ msg))

#elif RUBY3_COMPILER_SINCE(GCC, 4, 5, 0)
# define RUBY3_ATTR_DEPRECATED(msg) __attribute__((__deprecated__ msg))

#elif RUBY3_COMPILER_SINCE(Intel, 13, 0, 0)
# define RUBY3_ATTR_DEPRECATED(msg) __attribute__((__deprecated__ msg))

#elif RUBY3_HAS_ATTRIBUTE(deprecated) /* but not with message. */
# define RUBY3_ATTR_DEPRECATED(msg) __attribute__((__deprecated__))

#elif RUBY3_COMPILER_SINCE(MSVC, 14, 0, 0)
# define RUBY3_ATTR_DEPRECATED(msg) __declspec(deprecated msg)

#elif RUBY3_HAS_DECLSPEC_ATTRIBUTE(deprecated)
# define RUBY3_ATTR_DEPRECATED(msg) __declspec(deprecated)

#elif RUBY3_HAS_CPP_ATTRIBUTE(deprecated)
# define RUBY3_ATTR_DEPRECATED(msg) [[deprecated msg]]

#elif RUBY3_HAS_C_ATTRIBUTE(deprecated)
# define RUBY3_ATTR_DEPRECATED(msg) [[deprecated msg]]

#else
# define RUBY3_ATTR_DEPRECATED(msg) /* void */
#endif
