#ifndef RBIMPL_INTERN_SELECT_POSIX_H                 /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SELECT_POSIX_H
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
 */
#include "ruby/internal/config.h"

#ifdef HAVE_SYS_SELECT_H
# include <sys/select.h>        /* for select(2) (modern POSIX) */
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>            /* for select(2) (archaic UNIX) */
#endif

#include "ruby/internal/attr/pure.h"
#include "ruby/internal/attr/const.h"

typedef fd_set rb_fdset_t;

#define rb_fd_zero   FD_ZERO
#define rb_fd_set    FD_SET
#define rb_fd_clr    FD_CLR
#define rb_fd_isset  FD_ISSET
#define rb_fd_init   FD_ZERO
#define rb_fd_select select
/**@cond INTERNAL_MACRO */
#define rb_fd_copy  rb_fd_copy
#define rb_fd_dup   rb_fd_dup
#define rb_fd_ptr   rb_fd_ptr
#define rb_fd_max   rb_fd_max
/** @endcond */

static inline void
rb_fd_copy(rb_fdset_t *dst, const fd_set *src, int n)
{
    *dst = *src;
}

static inline void
rb_fd_dup(rb_fdset_t *dst, const fd_set *src, int n)
{
    *dst = *src;
}

RBIMPL_ATTR_PURE()
/* :TODO: can this function be __attribute__((returns_nonnull)) or not? */
static inline fd_set *
rb_fd_ptr(rb_fdset_t *f)
{
    return f;
}

RBIMPL_ATTR_CONST()
static inline int
rb_fd_max(const rb_fdset_t *f)
{
    return FD_SETSIZE;
}

/* :FIXME: What are these?  They don't exist for shibling implementations. */
#define rb_fd_init_copy(d, s) (*(d) = *(s))
#define rb_fd_term(f)   ((void)(f))

#endif /* RBIMPL_INTERN_SELECT_POSIX_H */
