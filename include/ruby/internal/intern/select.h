#ifndef RBIMPL_INTERN_SELECT_H                       /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SELECT_H
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
 * @brief      Public APIs to provide ::rb_fd_select().
 * @note       Functions  and  structs defined  in  this  header file  are  not
 *             necessarily ruby-specific.  They don't need ::VALUE etc.
 */
#include "ruby/internal/config.h"

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>         /* for NFDBITS (BSD Net/2) */
#endif

#include "ruby/internal/dllexport.h"

/* thread.c */
#if defined(NFDBITS) && defined(HAVE_RB_FD_INIT)
# include "ruby/internal/intern/select/largesize.h"
#elif defined(_WIN32)
# include "ruby/internal/intern/select/win32.h"
# define rb_fd_resize(n, f) ((void)(f))
#else
# include "ruby/internal/intern/select/posix.h"
# define rb_fd_resize(n, f) ((void)(f))
#endif

RBIMPL_SYMBOL_EXPORT_BEGIN()

struct timeval;

int rb_thread_fd_select(int, rb_fdset_t *, rb_fdset_t *, rb_fdset_t *, struct timeval *);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_INTERN_SELECT_H */
