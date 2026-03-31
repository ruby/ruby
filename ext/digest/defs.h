/* -*- C -*-
 * $Id$
 */

#ifndef DEFS_H
#define DEFS_H

#include "ruby.h"
#include <sys/types.h>

#if defined(HAVE_SYS_CDEFS_H)
# include <sys/cdefs.h>
#endif
#if !defined(__BEGIN_DECLS)
# define __BEGIN_DECLS
# define __END_DECLS
#endif

#define RB_DIGEST_DIAGNOSTIC(compiler, op, flag) _Pragma(STRINGIZE(compiler diagnostic op flag))
#ifdef RBIMPL_WARNING_IGNORED
# define RB_DIGEST_WARNING_IGNORED(flag) RBIMPL_WARNING_IGNORED(flag)
# define RB_DIGEST_WARNING_PUSH() RBIMPL_WARNING_PUSH()
# define RB_DIGEST_WARNING_POP() RBIMPL_WARNING_POP()
#elif defined(__clang__)
# define RB_DIGEST_WARNING_IGNORED(flag) RB_DIGEST_DIAGNOSTIC(clang, ignored, #flag)
# define RB_DIGEST_WARNING_PUSH() _Pragma("clang diagnostic push")
# define RB_DIGEST_WARNING_POP() _Pragma("clang diagnostic pop")
#else /* __GNUC__ */
# define RB_DIGEST_WARNING_IGNORED(flag) RB_DIGEST_DIAGNOSTIC(GCC, ignored, #flag)
# define RB_DIGEST_WARNING_PUSH() _Pragma("GCC diagnostic push")
# define RB_DIGEST_WARNING_POP() _Pragma("GCC diagnostic pop")
#endif
#ifdef RBIMPL_HAS_WARNING
# define RB_DIGEST_HAS_WARNING(_) RBIMPL_HAS_WARNING(_)
#elif defined(__has_warning)
# define RB_DIGEST_HAS_WARNING(_) __has_warning(_)
#else
# define RB_DIGEST_HAS_WARNING(_) 0
#endif

#endif /* DEFS_H */
