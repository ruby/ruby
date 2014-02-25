#ifndef RUBY_TIMEV_H
#define RUBY_TIMEV_H

PACKED_STRUCT_UNALIGNED(struct vtm {
    VALUE year; /* 2000 for example.  Integer. */
    VALUE subsecx; /* 0 <= subsecx < TIME_SCALE.  possibly Rational. */
    VALUE utc_offset; /* -3600 as -01:00 for example.  possibly Rational. */
    const char *zone; /* "JST", "EST", "EDT", etc. */
    uint16_t yday:9; /* 1..366 */
    uint8_t mon:4; /* 1..12 */
    uint8_t mday:5; /* 1..31 */
    uint8_t hour:5; /* 0..23 */
    uint8_t min:6; /* 0..59 */
    uint8_t sec:6; /* 0..60 */
    uint8_t wday:3; /* 0:Sunday, 1:Monday, ..., 6:Saturday 7:init */
    uint8_t isdst:2; /* 0:StandardTime 1:DayLightSavingTime 3:init */
});

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
