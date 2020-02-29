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
 * @brief      Tewaking visibility of C variables/functions.
 */
#ifndef  RUBY3_DLLEXPORT_H
#define  RUBY3_DLLEXPORT_H
#include "ruby/3/config.h"

#ifndef RUBY_SYMBOL_EXPORT_BEGIN
# define RUBY_SYMBOL_EXPORT_BEGIN /* begin */
# define RUBY_SYMBOL_EXPORT_END   /* end */
#endif

#ifdef RUBY_EXPORT
#undef RUBY_EXTERN
#endif

#ifndef RUBY_FUNC_EXPORTED
#define RUBY_FUNC_EXPORTED
#endif

/* These macros are used for functions which are exported only for MJIT
   and NOT ensured to be exported in future versions. */
#define MJIT_FUNC_EXPORTED RUBY_FUNC_EXPORTED
#define MJIT_SYMBOL_EXPORT_BEGIN RUBY_SYMBOL_EXPORT_BEGIN
#define MJIT_SYMBOL_EXPORT_END RUBY_SYMBOL_EXPORT_END

#if defined(MJIT_HEADER) && defined(_MSC_VER)
# undef MJIT_FUNC_EXPORTED
# define MJIT_FUNC_EXPORTED static
#endif

#ifndef RUBY_EXTERN
#define RUBY_EXTERN extern
#endif

/* For MinGW, we need __declspec(dllimport) for RUBY_EXTERN on MJIT.
   mswin's RUBY_EXTERN already has that. See also: win32/Makefile.sub */
#if defined(MJIT_HEADER) && defined(_WIN32) && defined(__GNUC__)
# undef RUBY_EXTERN
# define RUBY_EXTERN extern __declspec(dllimport)
#endif

/* On mswin, MJIT header transformation can't be used since cl.exe can't output
   preprocessed output preserving macros. So this `MJIT_STATIC` is needed
   to force non-static function to static on MJIT header to avoid symbol conflict. */
#ifdef MJIT_HEADER
# define MJIT_STATIC static
#else
# define MJIT_STATIC
#endif

/** Shortcut macro equivalent to `RUBY_SYMBOL_EXPORT_BEGIN extern "C" {`.
 * \@shyouhei finds it handy. */
#if defined(__DOXYGEN__)
# define RUBY3_SYMBOL_EXPORT_BEGIN() /* void */
#elif defined(__cplusplus)
# define RUBY3_SYMBOL_EXPORT_BEGIN() RUBY_SYMBOL_EXPORT_BEGIN extern "C" {
#else
# define RUBY3_SYMBOL_EXPORT_BEGIN() RUBY_SYMBOL_EXPORT_BEGIN
#endif

/** Counterpart of #RUBY3_SYMBOL_EXPORT_BEGIN */
#if defined(__DOXYGEN__)
# define RUBY3_SYMBOL_EXPORT_END() /* void */
#elif defined(__cplusplus)
# define RUBY3_SYMBOL_EXPORT_END() } RUBY_SYMBOL_EXPORT_END
#else
# define RUBY3_SYMBOL_EXPORT_END()   RUBY_SYMBOL_EXPORT_END
#endif


#endif /* RUBY3_DLLEXPORT_H */
