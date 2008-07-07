/* x68 compatibility functions -- follows Ruby's license */

#include "config.h"

#if !HAVE_SELECT
#include "x68/select.c"
#endif
#if MISSING__DTOS18
#include "x68/_dtos18.c"
#endif
#if MISSING_FCONVERT
#include "x68/_round.c"
#include "x68/fconvert.c"
#endif

/* missing some basic syscalls */
int
link(const char *src, const char *dst)
{
    return symlink(src, dst);
}

#ifndef HAVE_GETTIMEOFDAY
#include <time.h>
#include <sys/time.h>

struct timezone {
    int tz_minuteswest;
    int tz_dsttime;
};

int
gettimeofday(struct timeval *tv, struct timezone *tz)
{
    tv->tv_sec = (long)time((time_t*)0);
    tv->tv_usec = 0;

    return 0;
}
#endif
