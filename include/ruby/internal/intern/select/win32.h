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
 *             extension libraries.  They could be written in C++98.
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

/**
 * The data  structure which wraps the  fd_set bitmap used by  select(2).  This
 * allows Ruby to use FD sets  larger than that allowed by historic limitations
 * on modern platforms.
 */
typedef struct {
    int capa;                   /**< Maximum allowed number of FDs. */
    fd_set *fdset;              /**< File descriptors buffer. */
} rb_fdset_t;

RBIMPL_ATTR_NONNULL(())
/**
 * (Re-)initialises a  fdset.  One must  be initialised before  other `rb_fd_*`
 * operations.  Analogous to calling `malloc(3)` to allocate an `fd_set`.
 *
 * @param[out]  f  An fdset to squash.
 * @post        `f` holds no file descriptors.
 *
 * @internal
 *
 * Can't this leak memory if the same `f` is passed twice...?
 */
void rb_fd_init(rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
/**
 * Destroys the ::rb_fdset_t,  releasing any memory and resources  it used.  It
 * must be  reinitialised using rb_fd_init()  before future use.   Analogous to
 * calling `free(3)` to release memory for an `fd_set`.
 *
 * @param[out]  f  An fdset to squash.
 * @post        `f` holds no file descriptors.
 */
void rb_fd_term(rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
/**
 * Sets an fd to a fdset.
 *
 * @param[in]   fd  A file descriptor.
 * @param[out]  f   Target fdset.
 * @post        `f` holds `fd`.
 */
void rb_fd_set(int fd, rb_fdset_t *f);

RBIMPL_ATTR_NONNULL(())
/**
 * Destructively overwrites an fdset with another.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @param[in]   max   Maximum number of file descriptors to copy.
 * @post        `dst` is a copy of `src`.
 */
void rb_w32_fd_copy(rb_fdset_t *dst, const fd_set *src, int max);

RBIMPL_ATTR_NONNULL(())
/**
 * Identical to  rb_w32_fd_copy(), except  it copies  unlimited number  of file
 * descriptors.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @post        `dst` is a copy of `src`.
 */
void rb_w32_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src);

RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_NOALIAS()
/**
 * Wipes out the current set of FDs.
 *
 * @param[out]  f  The fdset to clear.
 * @post        `f` has no FDs.
 */
static inline void
rb_fd_zero(rb_fdset_t *f)
{
    f->fdset->fd_count = 0;
}

RBIMPL_ATTR_NONNULL(())
/**
 * Releases a specific FD from the given fdset.
 *
 * @param[in]   n  Target FD.
 * @param[out]  f  The fdset that holds `n`.
 * @post        `f` doesn't hold n.
 */
static inline void
rb_fd_clr(int n, rb_fdset_t *f)
{
    rb_w32_fdclr(n, f->fdset);
}

RBIMPL_ATTR_NONNULL(())
/**
 * Queries if the given FD is in the given set.
 *
 * @param[in]  n  Target FD.
 * @param[in]  f  The fdset to scan.
 * @retval     1  Yes there is.
 * @retval     0  No there isn't.
 */
static inline int
rb_fd_isset(int n, rb_fdset_t *f)
{
    return rb_w32_fdisset(n, f->fdset);
}

RBIMPL_ATTR_NONNULL(())
/**
 * Destructively overwrites an fdset with another.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @param[in]   n     Maximum number of file descriptors to copy.
 * @post        `dst` is a copy of `src`.
 */
static inline void
rb_fd_copy(rb_fdset_t *dst, const fd_set *src, int n)
{
    rb_w32_fd_copy(dst, src, n);
}

RBIMPL_ATTR_NONNULL(())
/**
 * Identical  to  rb_fd_copy(),  except  it copies  unlimited  number  of  file
 * descriptors.
 *
 * @param[out]  dst   Target fdset.
 * @param[in]   src   Source fdset.
 * @post        `dst` is a copy of `src`.
 */
static inline void
rb_fd_dup(rb_fdset_t *dst, const rb_fdset_t *src)
{
    rb_w32_fd_dup(dst, src);
}

/**
 * Waits for multiple file descriptors at once.
 *
 * @param[in]      n          Max FD in everything passed, plus one.
 * @param[in,out]  rfds       Set of FDs to wait for reads.
 * @param[in,out]  wfds       Set of FDs to wait for writes.
 * @param[in,out]  efds       Set of FDs to wait for OOBs.
 * @param[in,out]  timeout    Max blocking duration.
 * @retval         -1         Failed, errno set.
 * @retval          0         Timeout exceeded.
 * @retval         otherwise  Total number of file descriptors returned.
 * @post           `rfds` contains readable FDs.
 * @post           `wfds` contains writable FDs.
 * @post           `efds` contains exceptional FDs.
 * @post           `timeout` is the time left.
 * @note           All pointers are allowed to be null pointers.
 *
 * @internal
 *
 * This can wait for  `SOCKET` and `HANDLE` at once.  In  order to achieve that
 * property  we heavily  touch  the  internals of  MSVCRT.   We `CreateFile`  a
 * `"NUL"` alongside of  a socket and directly manipulate  its `struct ioinfo`.
 * This is of  course a very dirty hack.   If we could design the  API today we
 * could use `CancelIoEx`.  But we are older than that Win32 API.
 */
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
/**
 * Raw pointer to `fd_set`.
 *
 * @param[in]  f         Target fdset.
 * @retval     NULL      `f` is already terminated by rb_fd_term().
 * @retval     otherwise  Underlying fd_set.
 *
 * @internal
 *
 * Extension library  must not touch  raw pointers.  It was  a bad idea  to let
 * them use it.
 */
static inline fd_set *
rb_fd_ptr(const rb_fdset_t *f)
{
    return f->fdset;
}

RBIMPL_ATTR_NONNULL(())
RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/**
 * It seems this function has no use.  Maybe just remove?
 *
 * @param[in]  f  A set.
 * @return     Number of file descriptors stored.
 */
static inline int
rb_fd_max(const rb_fdset_t *f)
{
    const fd_set *p = f->fdset;

    RBIMPL_ASSERT_OR_ASSUME(p);
    return RBIMPL_CAST((int)p->fd_count);
}

#endif /* RBIMPL_INTERN_SELECT_WIN32_H */
