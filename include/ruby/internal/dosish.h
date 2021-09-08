#ifndef RBIMPL_DOSISH_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_DOSISH_H
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
 *             extension libraries.  They could be written in C++98.
 * @brief      Support for so-called dosish systems.
 */
#ifdef __CYGWIN__
#undef _WIN32
#endif

#if defined(_WIN32)
/*
  DOSISH mean MS-Windows style filesystem.
  But you should use more precise macros like DOSISH_DRIVE_LETTER, PATH_SEP,
  ENV_IGNORECASE or CASEFOLD_FILESYSTEM.
 */
#define DOSISH 1
# define DOSISH_DRIVE_LETTER
#endif

#ifdef _WIN32
#include "ruby/win32.h"
#endif

#if defined(DOSISH)
#define PATH_SEP ";"
#else
#define PATH_SEP ":"
#endif

#define PATH_SEP_CHAR PATH_SEP[0]

#define PATH_ENV "PATH"

#if defined(DOSISH)
#define ENV_IGNORECASE
#endif

#ifndef CASEFOLD_FILESYSTEM
# if defined DOSISH
#   define CASEFOLD_FILESYSTEM 1
# else
#   define CASEFOLD_FILESYSTEM 0
# endif
#endif

#endif /* RBIMPL_DOSISH_H */
