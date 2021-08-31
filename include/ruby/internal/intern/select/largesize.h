#ifndef RBIMPL_INTERN_SELECT_LARGESIZE_H             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_INTERN_SELECT_LARGESIZE_H
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
 *
 * Several Unix  platforms support file  descriptors bigger than  FD_SETSIZE in
 * `select(2)` system call.
 *
 * - Linux 2.2.12 (?)
 *
 * - NetBSD 1.2 (src/sys/kern/sys_generic.c:1.25)
 *   `select(2)` documents how to allocate fd_set dynamically.
 *   http://netbsd.gw.com/cgi-bin/man-cgi?select++NetBSD-4.0
 *
 * - FreeBSD 2.2 (src/sys/kern/sys_generic.c:1.19)
 *
 * - OpenBSD 2.0 (src/sys/kern/sys_generic.c:1.4)
 *   `select(2)` documents how to allocate fd_set dynamically.
 *   http://www.openbsd.org/cgi-bin/man.cgi?query=select&manpath=OpenBSD+4.4
 *
 * - HP-UX documents how to allocate fd_set dynamically.
 *   http://docs.hp.com/en/B2355-60105/select.2.html
 *
 * - Solaris 8 has `select_large_fdset`
 *
 * - Mac OS X 10.7 (Lion)
 *   `select(2)` returns `EINVAL`  if `nfds` is greater  than `FD_SET_SIZE` and
 *   `_DARWIN_UNLIMITED_SELECT` (or `_DARWIN_C_SOURCE`) isn't defined.
 *   http://developer.apple.com/library/mac/#releasenotes/Darwin/SymbolVariantsRelNotes/_index.html
 *
 * When `fd_set` is not  big enough to hold big file  descriptors, it should be
 * allocated dynamically.   Note that  this assumes  `fd_set` is  structured as
 * bitmap.
 *
 * `rb_fd_init` allocates the memory.
 * `rb_fd_term` frees the memory.
 * `rb_fd_set` may re-allocate bitmap.
 *
 * So `rb_fd_set` doesn't reject file descriptors bigger than `FD_SETSIZE`.
 */
#include "ruby/internal/attr/nonnull.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/dllexport.h"

/**@cond INTERNAL_MACRO */
#define rb_fd_ptr rb_fd_ptr
#define rb_fd_max rb_fd_max
/** @endcond */

struct timeval;

typedef struct {
    int maxfd;
    fd_set *fdset;
} rb_fdset_t;

RBIMPL_SYMBOL_EXPORT_BEGIN()
void rb_fd_init(rb_fdset_t *);
void rb_fd_term(rb_fdset_t *);
void rb_fd_zero(rb_fdset_t *);
void rb_fd_set(int, rb_fdset_t *);
void rb_fd_clr(int, rb_fdset_t *);
int rb_fd_isset(int, const rb_fdset_t *);
void rb_fd_copy(rb_fdset_t *, const fd_set *, int);
void rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);
int rb_fd_select(int, rb_fdset_t *, rb_fdset_t *, rb_fdset_t *, struct timeval *);
RBIMPL_SYMBOL_EXPORT_END()

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
    return f->maxfd;
}

#endif /* RBIMPL_INTERN_SELECT_LARGESIZE_H */
