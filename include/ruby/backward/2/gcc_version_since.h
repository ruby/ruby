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
 * @brief      Defines old #GCC_VERSION_SINCE
 */

#ifndef GCC_VERSION_SINCE
# if defined(__GNUC__) && !defined(__INTEL_COMPILER) && !defined(__clang__)
#  define GCC_VERSION_SINCE(major, minor, patchlevel) \
    ((__GNUC__ > (major)) ||  \
     ((__GNUC__ == (major) && \
       ((__GNUC_MINOR__ > (minor)) || \
        (__GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ >= (patchlevel))))))
# else
#  define GCC_VERSION_SINCE(major, minor, patchlevel) 0
# endif
#endif

#ifndef GCC_VERSION_BEFORE
# if defined(__GNUC__) && !defined(__INTEL_COMPILER) && !defined(__clang__)
#  define GCC_VERSION_BEFORE(major, minor, patchlevel) \
    ((__GNUC__ < (major)) ||  \
     ((__GNUC__ == (major) && \
       ((__GNUC_MINOR__ < (minor)) || \
        (__GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ <= (patchlevel))))))
# else
#  define GCC_VERSION_BEFORE(major, minor, patchlevel) 0
# endif
#endif
