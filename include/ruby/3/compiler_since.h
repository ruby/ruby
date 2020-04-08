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
 * @brief      Defines #RUBY3_COMPILER_SINCE.
 */
#include "ruby/3/compiler_is.h"
#ifndef RUBY3_COMPILER_SINCE

/**
 * @brief   Checks if the compiler is of given brand and is newer than or equal
 *          to the passed version.
 * @param   cc     Compiler brand, like `MSVC`.
 * @param   x      Major version.
 * @param   y      Minor version.
 * @param   z      Patchlevel.
 * @retval  true   cc >= x.y.z.
 * @retval  false  oherwise.
 */
#define RUBY3_COMPILER_SINCE(cc, x, y, z)     \
     (RUBY3_COMPILER_IS(cc)                && \
    ((RUBY3_COMPILER_VERSION_MAJOR >  (x)) || \
    ((RUBY3_COMPILER_VERSION_MAJOR == (x)) && \
    ((RUBY3_COMPILER_VERSION_MINOR >  (y)) || \
    ((RUBY3_COMPILER_VERSION_MINOR == (y)) && \
     (RUBY3_COMPILER_VERSION_PATCH >= (z)))))))

/**
 * @brief   Checks if  the compiler  is of  given brand and  is older  than the
 *          passed version.
 * @param   cc     Compiler brand, like `MSVC`.
 * @param   x      Major version.
 * @param   y      Minor version.
 * @param   z      Patchlevel.
 * @retval  true   cc < x.y.z.
 * @retval  false  oherwise.
 */
#define RUBY3_COMPILER_BEFORE(cc, x, y, z)    \
     (RUBY3_COMPILER_IS(cc)                && \
    ((RUBY3_COMPILER_VERSION_MAJOR <  (x)) || \
    ((RUBY3_COMPILER_VERSION_MAJOR == (x)) && \
    ((RUBY3_COMPILER_VERSION_MINOR <  (y)) || \
    ((RUBY3_COMPILER_VERSION_MINOR == (y)) && \
     (RUBY3_COMPILER_VERSION_PATCH <  (z)))))))

#endif /* RUBY3_COMPILER_SINCE */
