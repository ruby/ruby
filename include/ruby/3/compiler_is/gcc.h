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
 * @brief      Defines #RUBY3_COMPILER_IS_GCC.
 */
#include "ruby/3/compiler_is/apple.h"
#include "ruby/3/compiler_is/clang.h"
#include "ruby/3/compiler_is/intel.h"

#if defined(RUBY3_COMPILER_IS_GCC)
# /* Take that. */

#elif ! defined(__GNUC__)
# define RUBY3_COMPILER_IS_GCC 0

#elif RUBY3_COMPILER_IS(Apple)
# define RUBY3_COMPILER_IS_GCC 0

#elif RUBY3_COMPILER_IS(Clang)
# define RUBY3_COMPILER_IS_GCC 0

#elif RUBY3_COMPILER_IS(Intel)
# define RUBY3_COMPILER_IS_GCC 0

#else
# define RUBY3_COMPILER_IS_GCC 1
# define RUBY3_COMPILER_VERSION_MAJOR __GNUC__
# define RUBY3_COMPILER_VERSION_MINOR __GNUC_MINOR__
# define RUBY3_COMPILER_VERSION_PATCH __GNUC_PATCHLEVEL__
#endif
