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
 * @brief      Defines #RUBY3_HAS_DECLSPEC_ATTRIBUTE.
 */

/** Wraps (or simulates) `__has_declspec_attribute`. */
#if defined(RUBY3_HAS_DECLSPEC_ATTRIBUTE)
# /* Take that. */

#elif defined(__has_declspec_attribute)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE(_) __has_declspec_attribute(_)

#else
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE(_) RUBY3_TOKEN_PASTE(RUBY3_HAS_DECLSPEC_ATTRIBUTE_, _)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_align       RUBY3_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_deprecated  RUBY3_COMPILER_SINCE(MSVC,13, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_dllexport   RUBY3_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_dllimport   RUBY3_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_empty_bases RUBY3_COMPILER_SINCE(MSVC,19, 0, 23918)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_noalias     RUBY3_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_noinline    RUBY3_COMPILER_SINCE(MSVC,13, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_noreturn    RUBY3_COMPILER_SINCE(MSVC,11, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_nothrow     RUBY3_COMPILER_SINCE(MSVC, 8, 0, 0)
# define RUBY3_HAS_DECLSPEC_ATTRIBUTE_restrict    RUBY3_COMPILER_SINCE(MSVC,14, 0, 0)
# /* Note that "8, 0, 0" might be inaccurate. */
# if ! defined(__cplusplus)
#  /* Clang has this in both C/C++, but MSVC has this in C++ only.*/
#  undef RUBY3_HAS_DECLSPEC_ATTRIBUTE_nothrow
# endif
#endif
