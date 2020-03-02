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
 * @brief      Defines #RUBY3_COMPILER_IS_SunPro.
 */
#if defined(RUBY3_COMPILER_IS_SunPro)
# /* Take that. */

#elif ! (defined(__SUNPRO_C) || defined(__SUNPRO_CC))
# define RUBY3_COMPILER_IS_SunPro 0

#elif defined(__SUNPRO_C) && __SUNPRO_C >= 0x5100
# define RUBY3_COMPILER_IS_SunPro 1
# /* __SUNPRO_C = 0xXYYZ */
# define TERSE_COMPILER_VERSION_MAJOR  (__SUNPRO_C >> 12)
# define TERSE_COMPILER_VERSION_MINOR ((__SUNPRO_C >> 8 & 0xF) * 10 + (__SUNPRO_C >> 4 & 0xF))
# define TERSE_COMPILER_VERSION_PATCH  (__SUNPRO_C      & 0xF)

#elif defined(__SUNPRO_CC) && __SUNPRO_CC >= 0x5100
# define RUBY3_COMPILER_IS_SunPro 1
# /* __SUNPRO_CC = 0xXYYZ */
# define TERSE_COMPILER_VERSION_MAJOR  (__SUNPRO_CC >> 12)
# define TERSE_COMPILER_VERSION_MINOR ((__SUNPRO_CC >> 8 & 0xF) * 10 + (__SUNPRO_CC >> 4 & 0xF))
# define TERSE_COMPILER_VERSION_PATCH  (__SUNPRO_CC      & 0xF)

#elif defined(__SUNPRO_C)
# define RUBY3_COMPILER_IS_SunPro 1
# /* __SUNPRO_C = 0xXYZ */
# define TERSE_COMPILER_VERSION_MAJOR (__SUNPRO_C >> 8)
# define TERSE_COMPILER_VERSION_MINOR (__SUNPRO_C >> 4 & 0xF)
# define TERSE_COMPILER_VERSION_PATCH (__SUNPRO_C      & 0xF)

#else
# define RUBY3_COMPILER_IS_SunPro 1
# /* __SUNPRO_CC = 0xXYZ */
# define TERSE_COMPILER_VERSION_MAJOR (__SUNPRO_CC >> 8)
# define TERSE_COMPILER_VERSION_MINOR (__SUNPRO_CC >> 4 & 0xF)
# define TERSE_COMPILER_VERSION_PATCH (__SUNPRO_CC      & 0xF)
#endif
