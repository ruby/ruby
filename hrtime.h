#ifndef RB_HRTIME_H
#define RB_HRTIME_H
#include "ruby/ruby.h"
#include <time.h>
#if defined(HAVE_SYS_TIME_H)
#  include <sys/time.h>
#endif

/*
 * Hi-res monotonic clock.  It is currently nsec resolution, which has over
 * 500 years of range.
 *
 * TBD: Is nsec even necessary? usec resolution seems enough for userspace
 * and it'll be suitable for use with devices lasting over 500,000 years
 * (maybe some devices designed for long-term space travel)
 */
#define RB_HRTIME_PER_USEC ((rb_hrtime_t)1000)
#define RB_HRTIME_PER_MSEC (RB_HRTIME_PER_USEC * (rb_hrtime_t)1000)
#define RB_HRTIME_PER_SEC  (RB_HRTIME_PER_MSEC * (rb_hrtime_t)1000)
#define RB_HRTIME_MAX      UINT64_MAX

/*
 * Lets try to support time travelers.  Lets assume anybody with a time machine
 * also has access to a modern gcc or clang with 128-bit int support
 */
#ifdef MY_RUBY_BUILD_MAY_TIME_TRAVEL
typedef int128_t rb_hrtime_t;
#else
typedef uint64_t rb_hrtime_t;
#endif

/* thread.c */
rb_hrtime_t rb_hrtime_now(void);

static inline rb_hrtime_t
rb_hrtime_mul(rb_hrtime_t a, rb_hrtime_t b)
{
    rb_hrtime_t c;

#ifdef HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW
    if (__builtin_mul_overflow(a, b, &c))
        return RB_HRTIME_MAX;
#else
    if (b != 0 && b > RB_HRTIME_MAX / b) /* overflow */
        return RB_HRTIME_MAX;
    c = a * b;
#endif
    return c;
}

static inline rb_hrtime_t
rb_hrtime_add(rb_hrtime_t a, rb_hrtime_t b)
{
    rb_hrtime_t c;

#ifdef HAVE_BUILTIN___BUILTIN_ADD_OVERFLOW
    if (__builtin_add_overflow(a, b, &c))
        return RB_HRTIME_MAX;
#else
    c = a + b;
    if (c < a) /* overflow */
        return RB_HRTIME_MAX;
#endif
    return c;
}

static inline rb_hrtime_t
rb_timeval2hrtime(const struct timeval *tv)
{
    rb_hrtime_t s = rb_hrtime_mul((rb_hrtime_t)tv->tv_sec, RB_HRTIME_PER_SEC);
    rb_hrtime_t u = rb_hrtime_mul((rb_hrtime_t)tv->tv_usec, RB_HRTIME_PER_USEC);

    return rb_hrtime_add(s, u);
}

static inline rb_hrtime_t
rb_timespec2hrtime(const struct timespec *ts)
{
    rb_hrtime_t s = rb_hrtime_mul((rb_hrtime_t)ts->tv_sec, RB_HRTIME_PER_SEC);

    return rb_hrtime_add(s, (rb_hrtime_t)ts->tv_nsec);
}

static inline rb_hrtime_t
rb_msec2hrtime(unsigned long msec)
{
    return rb_hrtime_mul((rb_hrtime_t)msec, RB_HRTIME_PER_MSEC);
}

static inline rb_hrtime_t
rb_sec2hrtime(time_t sec)
{
    if (sec <= 0) return 0;

    return rb_hrtime_mul((rb_hrtime_t)sec, RB_HRTIME_PER_SEC);
}

static inline struct timespec *
rb_hrtime2timespec(struct timespec *ts, const rb_hrtime_t *hrt)
{
    if (hrt) {
        ts->tv_sec = *hrt / RB_HRTIME_PER_SEC;
        ts->tv_nsec = (int32_t)(*hrt % RB_HRTIME_PER_SEC);
        return ts;
    }
    return 0;
}

static inline struct timeval *
rb_hrtime2timeval(struct timeval *tv, const rb_hrtime_t *hrt)
{
    if (hrt) {
        tv->tv_sec = *hrt / RB_HRTIME_PER_SEC;
        tv->tv_usec = (int32_t)((*hrt % RB_HRTIME_PER_SEC)/RB_HRTIME_PER_USEC);

        return tv;
    }
    return 0;
}
#endif /* RB_HRTIME_H */
