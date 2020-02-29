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
 * @brief      Public APIs to provide ::rb_fd_select().
 * @note       Functions  and  structs defined  in  this  header file  are  not
 *             necessarily ruby-specific.  They don't need ::VALUE etc.
 */
#ifndef  RUBY3_INTERN_SELECT_H
#define  RUBY3_INTERN_SELECT_H
#include "ruby/3/config.h"

#include "ruby/3/dosish.h"      /* for rb_w32_select */

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>          /* for struct timeval */
#endif

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>         /* for NFDBITS (BSD Net/2) */
#endif

#ifdef HAVE_SYS_SELECT_H
# include <sys/select.h>        /* for select(2) (modern POSIX) */
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>            /* for select(2) (archaic UNIX) */
#endif

#include "ruby/3/dllexport.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

/* thread.c */
#if defined(NFDBITS) && defined(HAVE_RB_FD_INIT)
typedef struct {
    int maxfd;
    fd_set *fdset;
} rb_fdset_t;

void rb_fd_init(rb_fdset_t *);
void rb_fd_term(rb_fdset_t *);
void rb_fd_zero(rb_fdset_t *);
void rb_fd_set(int, rb_fdset_t *);
void rb_fd_clr(int, rb_fdset_t *);
int rb_fd_isset(int, const rb_fdset_t *);
void rb_fd_copy(rb_fdset_t *, const fd_set *, int);
void rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);

int rb_fd_select(int, rb_fdset_t *, rb_fdset_t *, rb_fdset_t *, struct timeval *);

#define rb_fd_ptr(f)    ((f)->fdset)
#define rb_fd_max(f)    ((f)->maxfd)

#elif defined(_WIN32)

typedef struct {
    int capa;
    fd_set *fdset;
} rb_fdset_t;

void rb_fd_init(rb_fdset_t *);
void rb_fd_term(rb_fdset_t *);
#define rb_fd_zero(f)           ((f)->fdset->fd_count = 0)
void rb_fd_set(int, rb_fdset_t *);
#define rb_fd_clr(n, f)         rb_w32_fdclr((n), (f)->fdset)
#define rb_fd_isset(n, f)       rb_w32_fdisset((n), (f)->fdset)
#define rb_fd_copy(d, s, n)     rb_w32_fd_copy((d), (s), (n))
void rb_w32_fd_copy(rb_fdset_t *, const fd_set *, int);
#define rb_fd_dup(d, s) rb_w32_fd_dup((d), (s))
void rb_w32_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);
static inline int
rb_fd_select(int n, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout)
{
    return rb_w32_select(n,
                         rfds ? rfds->fdset : NULL,
                         wfds ? wfds->fdset : NULL,
                         efds ? efds->fdset : NULL,
                         timeout);
}
#define rb_fd_resize(n, f)      ((void)(f))

#define rb_fd_ptr(f)    ((f)->fdset)
#define rb_fd_max(f)    ((f)->fdset->fd_count)

#else

typedef fd_set rb_fdset_t;
#define rb_fd_zero(f)   FD_ZERO(f)
#define rb_fd_set(n, f) FD_SET((n), (f))
#define rb_fd_clr(n, f) FD_CLR((n), (f))
#define rb_fd_isset(n, f) FD_ISSET((n), (f))
#define rb_fd_copy(d, s, n) (*(d) = *(s))
#define rb_fd_dup(d, s) (*(d) = *(s))
#define rb_fd_resize(n, f)      ((void)(f))
#define rb_fd_ptr(f)    (f)
#define rb_fd_init(f)   FD_ZERO(f)
#define rb_fd_init_copy(d, s) (*(d) = *(s))
#define rb_fd_term(f)   ((void)(f))
#define rb_fd_max(f)    FD_SETSIZE
#define rb_fd_select(n, rfds, wfds, efds, timeout)      select((n), (rfds), (wfds), (efds), (timeout))

#endif

int rb_thread_fd_select(int, rb_fdset_t *, rb_fdset_t *, rb_fdset_t *, struct timeval *);

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_INTERN_SELECT_H */
