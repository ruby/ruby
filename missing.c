/*
 * Do all necessary includes here, so that we don't have to worry about
 * overlapping includes in the files in missing.d.
 */

#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/types.h>

#include "ruby.h"

#ifndef __STDC__
#define const
#endif /* !__STDC__ */

#ifdef STDC_HEADERS
#include <string.h>
#endif

#ifndef HAVE_MEMMOVE
#include "missing/memmove.c"
#endif

#ifndef HAVE_STRERROR
#include "missing/strerror.c"
#endif

#ifndef HAVE_STRTOUL
#include "missing/strtoul.c"
#endif

#ifndef HAVE_STRFTIME
#include "missing/strftime.c"
#endif

#ifndef HAVE_STRSTR
#include "missing/strstr.c"
#endif

#ifndef HAVE_GETOPT_LONG
#include "missing/getopt.h"
#include "missing/getopt.c"
#include "missing/getopt1.c"
#endif

#ifndef HAVE_MKDIR
#include "missing/mkdir.c"
#endif

#ifndef HAVE_STRDUP
char *
strdup(str)
    char *str;
{
    extern char *xmalloc();
    char *tmp;
    int len = strlen(str) + 1;

    tmp = xmalloc(len);
    if (tmp == NULL) return NULL;
    bcopy(str, tmp, len);

    return tmp;
}
#endif
