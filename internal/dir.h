#ifndef INTERNAL_DIR_H                                   /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_DIR_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Dir.
 */
#include "ruby/ruby.h"          /* for VALUE */

#include <string.h>             /* for strlen */

#if defined HAVE_DIRENT_H && !defined _WIN32
# include <dirent.h>
#elif defined HAVE_DIRECT_H && !defined _WIN32
# include <direct.h>
#else
# define dirent direct
# ifdef HAVE_SYS_NDIR_H
#  include <sys/ndir.h>
# endif
# ifdef HAVE_SYS_DIR_H
#  include <sys/dir.h>
# endif
# ifdef HAVE_NDIR_H
#  include <ndir.h>
# endif
# ifdef _WIN32
#  include "win32/dir.h"
# endif
#endif

#undef HAVE_DIRENT_NAMLEN
#if defined(HAVE_STRUCT_DIRENT_D_NAMLEN) || defined(_WIN32) || \
    (!defined(HAVE_DIRENT_H) && !defined(HAVE_DIRECT_H))
# define NAMLEN(dirent) ((dirent)->d_namlen)
# define HAVE_DIRENT_NAMLEN 1
#else
# define NAMLEN(dirent) strlen((dirent)->d_name)
#endif

/* safe to use without GVL */
static inline int
dirent_dot_p(const struct dirent *dp)
{
    const char *name = dp->d_name;
    if (name[0] != '.') return FALSE;
#ifdef HAVE_DIRENT_NAMLEN
    switch (NAMLEN(dp)) {
      case 2:
        if (name[1] != '.') return FALSE;
      case 1:
        return TRUE;
      default:
        break;
    }
#else
    if (!name[1]) return TRUE;
    if (name[1] != '.') return FALSE;
    if (!name[2]) return TRUE;
#endif
    return FALSE;
}


/* dir.c */
VALUE rb_dir_getwd_ospath(void);

#endif /* INTERNAL_DIR_H */
