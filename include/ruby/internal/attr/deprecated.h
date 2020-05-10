#ifndef RBIMPL_ATTR_DEPRECATED_H                     /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ATTR_DEPRECATED_H
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
 * @brief      Defines #RBIMPL_ATTR_DEPRECATED.
 */
#include "ruby/impl/compiler_since.h"
#include "ruby/impl/has/attribute.h"
#include "ruby/impl/has/c_attribute.h"
#include "ruby/impl/has/cpp_attribute.h"
#include "ruby/impl/has/declspec_attribute.h"
#include "ruby/impl/has/extension.h"

/** Wraps (or simulates) `[[deprecated]]` */
#if RBIMPL_HAS_EXTENSION(attribute_deprecated_with_message)
# define RBIMPL_ATTR_DEPRECATED(msg) __attribute__((__deprecated__ msg))

#elif RBIMPL_COMPILER_SINCE(GCC, 4, 5, 0)
# define RBIMPL_ATTR_DEPRECATED(msg) __attribute__((__deprecated__ msg))

#elif RBIMPL_COMPILER_SINCE(Intel, 13, 0, 0)
# define RBIMPL_ATTR_DEPRECATED(msg) __attribute__((__deprecated__ msg))

#elif RBIMPL_HAS_ATTRIBUTE(deprecated) /* but not with message. */
# define RBIMPL_ATTR_DEPRECATED(msg) __attribute__((__deprecated__))

#elif RBIMPL_COMPILER_SINCE(MSVC, 14, 0, 0)
# define RBIMPL_ATTR_DEPRECATED(msg) __declspec(deprecated msg)

#elif RBIMPL_HAS_DECLSPEC_ATTRIBUTE(deprecated)
# define RBIMPL_ATTR_DEPRECATED(msg) __declspec(deprecated)

#elif RBIMPL_HAS_CPP_ATTRIBUTE(deprecated)
# define RBIMPL_ATTR_DEPRECATED(msg) [[deprecated msg]]

#elif RBIMPL_HAS_C_ATTRIBUTE(deprecated)
# define RBIMPL_ATTR_DEPRECATED(msg) [[deprecated msg]]

#else
# define RBIMPL_ATTR_DEPRECATED(msg) /* void */
#endif

#endif /* RBIMPL_ATTR_DEPRECATED_H */
