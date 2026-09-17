#ifndef INTERNAL_VM_MAP_H
#define INTERNAL_VM_MAP_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the  conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Shared per-platform virtual memory mapping helpers.
 */
#include "ruby/internal/config.h"
#include <stddef.h>             /* for size_t */

#ifdef HAVE_SYS_MMAN_H
# include <sys/mman.h>
#endif
#ifdef HAVE_ERRNO_H
# include <errno.h>             /* for errno, EAGAIN */
#endif

// On Solaris, madvise() is NOT declared for SUS (XPG4v2) or later,
// but MADV_* macros are defined when __EXTENSIONS__ is defined.
#ifdef NEED_MADVICE_PROTOTYPE_USING_CADDR_T
#include <sys/types.h>
extern int madvise(caddr_t, size_t, int);
#endif

// Reduces RSS lazily if possible, otherwise does it immediately. Keeps the mapping.
static inline void
rb_vm_map_reusable_lazy(void *addr, size_t len, int advice)
{
#ifdef __wasi__
    /* WebAssembly doesn't support madvise. */
#elif defined(VM_CHECK_MODE) && VM_CHECK_MODE > 0 && defined(MADV_DONTNEED)
    if (!advice) advice = MADV_DONTNEED;
    madvise(addr, len, advice);
#elif defined(MADV_FREE_REUSABLE)
    /* Darwin / macOS / iOS.  Drops phys_footprint; pages stay in resident_size
     * until the kernel reclaims them.  Retry on EAGAIN. */
    if (!advice) advice = MADV_FREE_REUSABLE;
    while (madvise(addr, len, advice) == -1 && errno == EAGAIN);
#elif defined(MADV_FREE)
    /* Recent Linux. */
    if (!advice) advice = MADV_FREE;
    madvise(addr, len, advice);
#elif defined(MADV_DONTNEED)
    /* Old Linux. */
    if (!advice) advice = MADV_DONTNEED;
    madvise(addr, len, advice);
#elif defined(POSIX_MADV_DONTNEED)
    /* Solaris. */
    if (!advice) advice = POSIX_MADV_DONTNEED;
    posix_madvise(addr, len, advice);
#elif defined(_WIN32)
    VirtualAlloc(addr, len, MEM_RESET, PAGE_READWRITE);
#endif
}

// Reduces RSS immediately if possible, otherwise does it lazily. Keeps the mapping.
static inline void
rb_vm_map_reusable_immediate(void *addr, size_t len, int advice)
{
#ifdef __wasi__
    /* WebAssembly doesn't support madvise. */
#elif defined(MADV_FREE_REUSABLE)
    /* The most aggressive option is MADV_FREE_REUSABLE — same as _lazy.  It drops
     * phys_footprint immediately.  Retry on EAGAIN. */
    if (!advice) advice = MADV_FREE_REUSABLE;
    while (madvise(addr, len, advice) == -1 && errno == EAGAIN);
#elif defined(MADV_DONTNEED)
    /* Linux: kernel discards physical pages immediately; next touch
     * zero-faults and RSS drops at once. */
    if (!advice) advice = MADV_DONTNEED;
    madvise(addr, len, advice);
#elif defined(POSIX_MADV_DONTNEED)
    if (!advice) advice = POSIX_MADV_DONTNEED;
    posix_madvise(addr, len, advice);
#elif defined(_WIN32)
    // Does not reduce working set immediately. We would need 2 system calls to do this.
    VirtualAlloc(addr, len, MEM_RESET, PAGE_READWRITE);
#endif
}

/* Re-acquire pages previously given back. Only needed for certain platforms. */
static inline void
rb_vm_map_reuse(void *addr, size_t len)
{
#if defined(MADV_FREE_REUSE)
    /* Darwin: mandatory handshake with MADV_FREE_REUSABLE.  Retry on EAGAIN. */
    while (madvise(addr, len, MADV_FREE_REUSE) == -1 && errno == EAGAIN);
#endif
    /* Linux/Windows/wasi: no-op (fault re-materializes zero-filled pages). */
}

#endif /* INTERNAL_VM_MAP_H */
