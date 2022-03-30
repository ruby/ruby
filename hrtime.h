#ifndef RB_HRTIME_H
#define RB_HRTIME_H
#include "ruby/ruby.h"
#include <time.h>
#if defined(HAVE_SYS_TIME_H)
#  include <sys/time.h>
#endif

/*
 * Hi-res monotonic clock.  It is currently nsec resolution, which has over
 * 500 years of range (with an unsigned 64-bit integer).  Developers
 * targeting small systems may try 32-bit and low-resolution (milliseconds).
 *
 * TBD: Is nsec even necessary? usec resolution seems enough for userspace
 * and it'll be suitable for use with devices lasting over 500,000 years
 * (maybe some devices designed for long-term space travel)
 *
 * Current API:
 *
 *	* rb_hrtime_now      - current clock value (monotonic if available)
 *	* rb_hrtime_mul      - multiply with overflow check
 *	* rb_hrtime_add      - add with overflow check
 *	* rb_timeval2hrtime  - convert from timeval
 *	* rb_timespec2hrtime - convert from timespec
 *	* rb_msec2hrtime     - convert from millisecond
 *	* rb_sec2hrtime      - convert from time_t (seconds)
 *	* rb_hrtime2timeval  - convert to timeval
 *	* rb_hrtime2timespec - convert to timespec
 *
 * Note: no conversion to milliseconds is provided here because different
 * functions have different limits (e.g. epoll_wait vs w32_wait_events).
 * So we provide RB_HRTIME_PER_MSEC and similar macros for implementing
 * this for each use case.
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
/* returns the value of the monotonic clock (if available) */
rb_hrtime_t rb_hrtime_now(void);

/*
 * multiply @a and @b with overflow check and return the
 * (clamped to RB_HRTIME_MAX) result.
 */
static inline rb_hrtime_t
rb_hrtime_mul(rb_hrtime_t a, rb_hrtime_t b)
{
    rb_hrtime_t c;

#ifdef HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW
    if (__builtin_mul_overflow(a, b, &c))
        return RB_HRTIME_MAX;
#else
    if (b != 0 && a > RB_HRTIME_MAX / b) /* overflow */
        return RB_HRTIME_MAX;
    c = a * b;
#endif
    return c;
}

/*
 * add @a and @b with overflow check and return the
 * (clamped to RB_HRTIME_MAX) result.
 */
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

/*
 * convert a timeval struct to rb_hrtime_t, clamping at RB_HRTIME_MAX
 */
static inline rb_hrtime_t
rb_timeval2hrtime(const struct timeval *tv)
{
    rb_hrtime_t s = rb_hrtime_mul((rb_hrtime_t)tv->tv_sec, RB_HRTIME_PER_SEC);
    rb_hrtime_t u = rb_hrtime_mul((rb_hrtime_t)tv->tv_usec, RB_HRTIME_PER_USEC);

    return rb_hrtime_add(s, u);
}

/*
 * convert a timespec struct to rb_hrtime_t, clamping at RB_HRTIME_MAX
 */
static inline rb_hrtime_t
rb_timespec2hrtime(const struct timespec *ts)
{
    rb_hrtime_t s = rb_hrtime_mul((rb_hrtime_t)ts->tv_sec, RB_HRTIME_PER_SEC);

    return rb_hrtime_add(s, (rb_hrtime_t)ts->tv_nsec);
}

/*
 * convert a millisecond value to rb_hrtime_t, clamping at RB_HRTIME_MAX
 */
static inline rb_hrtime_t
rb_msec2hrtime(unsigned long msec)
{
    return rb_hrtime_mul((rb_hrtime_t)msec, RB_HRTIME_PER_MSEC);
}

/*
 * convert a time_t value to rb_hrtime_t, clamping at RB_HRTIME_MAX
 * Negative values will be clamped at 0.
 */
static inline rb_hrtime_t
rb_sec2hrtime(time_t sec)
{
    if (sec <= 0) return 0;

    return rb_hrtime_mul((rb_hrtime_t)sec, RB_HRTIME_PER_SEC);
}

/*
 * convert a rb_hrtime_t value to a timespec, suitable for calling
 * functions like ppoll(2) or kevent(2)
 */
static inline struct timespec *
rb_hrtime2timespec(struct timespec *ts, const rb_hrtime_t *hrt)
{
    if (hrt) {
        ts->tv_sec = (time_t)(*hrt / RB_HRTIME_PER_SEC);
        ts->tv_nsec = (int32_t)(*hrt % RB_HRTIME_PER_SEC);
        return ts;
    }
    return 0;
}

/*
 * convert a rb_hrtime_t value to a timeval, suitable for calling
 * functions like select(2)
 */
static inline struct timeval *
rb_hrtime2timeval(struct timeval *tv, const rb_hrtime_t *hrt)
{
    if (hrt) {
        tv->tv_sec = (time_t)(*hrt / RB_HRTIME_PER_SEC);
        tv->tv_usec = (int32_t)((*hrt % RB_HRTIME_PER_SEC)/RB_HRTIME_PER_USEC);

        return tv;
    }
    return 0;
}

#include "internal/warnings.h"
#include "internal/time.h"

/*
 * Back when we used "struct timeval", not all platforms implemented
 * tv_sec as time_t.  Nowadays we use "struct timespec" and tv_sec
 * seems to be implemented more consistently across platforms.
 * At least other parts of our code hasn't had to deal with non-time_t
 * tv_sec in timespec...
 */
#define TIMESPEC_SEC_MAX TIMET_MAX
#define TIMESPEC_SEC_MIN TIMET_MIN

COMPILER_WARNING_PUSH
#if __has_warning("-Wimplicit-int-float-conversion")
COMPILER_WARNING_IGNORED(-Wimplicit-int-float-conversion)
#elif defined(_MSC_VER)
/* C4305: 'initializing': truncation from '__int64' to 'const double' */
COMPILER_WARNING_IGNORED(4305)
#endif
static const double TIMESPEC_SEC_MAX_as_double = TIMESPEC_SEC_MAX;
COMPILER_WARNING_POP

static inline rb_hrtime_t *
double2hrtime(rb_hrtime_t *hrt, double d)
{
    /* assume timespec.tv_sec has same signedness as time_t */
    const double TIMESPEC_SEC_MAX_PLUS_ONE = 2.0 * (TIMESPEC_SEC_MAX_as_double / 2.0 + 1.0);

    if (TIMESPEC_SEC_MAX_PLUS_ONE <= d) {
        return NULL;
    }
    else if (d <= 0) {
        *hrt = 0;
    }
    else {
        *hrt = (rb_hrtime_t)(d * (double)RB_HRTIME_PER_SEC);
    }
    return hrt;
}

static inline double
hrtime2double(rb_hrtime_t hrt)
{
    return (double)hrt / (double)RB_HRTIME_PER_SEC;
}

#endif /* RB_HRTIME_H */
