#ifndef RBIMPL_INTERN_SELECT_WIN32_H                 /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SELECT_WIN32_H
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
#include "ruby/internal/dosish.h"      /* for rb_w32_select */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/dllexport.h"
#include "ruby/assert.h"

/**@cond INTERNAL_MACRO */
#define rb_fd_zero  rb_fd_zero
#define rb_fd_clr   rb_fd_clr
#define rb_fd_isset rb_fd_isset
#define rb_fd_copy  rb_fd_copy
#define rb_fd_dup   rb_fd_dup
#define rb_fd_ptr   rb_fd_ptr
#define rb_fd_max   rb_fd_max
/** @endcond */

RBIMPL_SYMBOL_EXPORT_BEGIN()

struct timeval;

typedef struct {
    int capa;
    fd_set *fdset;
} rb_fdset_t;

void rb_fd_init(rb_fdset_t *);
void rb_fd_term(rb_fdset_t *);
void rb_fd_set(int, rb_fdset_t *);
void rb_w32_fd_copy(rb_fdset_t *, const fd_set *, int);
void rb_w32_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);

RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_NOALIAS()
static inline void
rb_fd_zero(rb_fdset_t *f)
{
    f->fdset->fd_count = 0;
}

RBIMPL_ATTR_NONNULL(())
static inline void
rb_fd_clr(int n, rb_fdset_t *f)
{
    rb_w32_fdclr(n, f->fdset);
}

RBIMPL_ATTR_NONNULL(())
static inline int
rb_fd_isset(int n, rb_fdset_t *f)
{
    return rb_w32_fdisset(n, f->fdset);
}

RBIMPL_ATTR_NONNULL(())
static inline void
rb_fd_copy(rb_fdset_t *dst, const fd_set *src, int n)
{
    rb_w32_fd_copy(dst, src, n);
}

RBIMPL_ATTR_NONNULL(())
static inline void
rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src)
{
    rb_w32_fd_dup(dst, src);
}

static inline int
rb_fd_select(int n, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout)
{
    return rb_w32_select(
        n,
        rfds ? rfds->fdset : NULL,
        wfds ? wfds->fdset : NULL,
        efds ? efds->fdset : NULL,
        timeout);
}

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_PURE()
/* :TODO: can this function be __attribute__((returns_nonnull)) or not? */
static inline fd_set *
rb_fd_ptr(const rb_fdset_t *f)
{
    return f->fdset;
}

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_PURE()
static inline int
rb_fd_max(const rb_fdset_t *f)
{
    const fd_set *p = f->fdset;

    RBIMPL_ASSERT_OR_ASSUME(p);
    return p->fd_count;
}

#endif /* RBIMPL_INTERN_SELECT_WIN32_H */
