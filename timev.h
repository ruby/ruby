#ifndef RUBY_TIMEV_H
#define RUBY_TIMEV_H

struct vtm {
    VALUE year; /* 2000 for example.  Integer. */
    int mon; /* 1..12 */
    int mday; /* 1..31 */
    int hour; /* 0..23 */
    int min; /* 0..59 */
    int sec; /* 0..60 */
    VALUE subsecx; /* 0 <= subsecx < TIME_SCALE.  possibly Rational. */
    VALUE utc_offset; /* -3600 as -01:00 for example.  possibly Rational. */
    int wday; /* 0:Sunday, 1:Monday, ..., 6:Saturday */
    int yday; /* 1..366 */
    int isdst; /* 0:StandardTime 1:DayLightSavingTime */
    const char *zone; /* "JST", "EST", "EDT", etc. */
};

#define TIME_SCALE 1000000000

#ifndef TYPEOF_TIMEVAL_TV_SEC
# define TYPEOF_TIMEVAL_TV_SEC time_t
#endif
#ifndef TYPEOF_TIMEVAL_TV_USEC
# if INT_MAX >= 1000000
# define TYPEOF_TIMEVAL_TV_USEC int
# else
# define TYPEOF_TIMEVAL_TV_USEC long
# endif
#endif

#if SIZEOF_TIME_T == SIZEOF_LONG
typedef unsigned long unsigned_time_t;
#elif SIZEOF_TIME_T == SIZEOF_INT
typedef unsigned int unsigned_time_t;
#elif SIZEOF_TIME_T == SIZEOF_LONG_LONG
typedef unsigned LONG_LONG unsigned_time_t;
#else
# error cannot find integer type which size is same as time_t.
#endif

#endif
