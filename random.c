/************************************************

  random.c -

  $Author$
  $Date$
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <time.h>
#ifndef NT
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif
#endif /* NT */

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

/*
 * Prefer to use drand48, otherwise use random, or rand as a last resort.
 */
#ifdef HAVE_DRAND48

#ifndef HAVE_DRAND48_DECL
double drand48 _((void));
void srand48 _((long));
#endif

#define SRANDOM(s)	srand48((long)(s))
#define RANDOM_NUMBER	drand48()

#else /* not HAVE_DRAND48 */

/*
 * The largest number returned by the random number generator is
 * RANDOM_MAX.  If we're using `rand' it's RAND_MAX, but if we're
 * using `random' it's 2^31-1.
 */
#ifndef RANDOM_MAX
# ifndef HAVE_RANDOM
#  define RANDOM_MAX	RAND_MAX
# else
#  define RANDOM_MAX	2147483647.0
# endif
#endif

#ifdef HAVE_RANDOM

#define RANDOM	random
#define SRANDOM	srandom

#else /* HAVE_RANDOM */

#define RANDOM	rand
#define SRANDOM	srand

#endif /* HAVE_RANDOM */

/* 0 <= RANDOM_NUMBER <= 1 */
#define RANDOM_NUMBER (((double)RANDOM())/((double)RANDOM_MAX+1))

#endif /* not HAVE_DRAND48 */

static int first = 1;
#ifdef HAVE_RANDOM
static char state[256];
#endif

static int
rand_init(seed)
    long seed;
{
    int old;
    static unsigned int saved_seed;

#ifdef HAVE_RANDOM
    if (first == 1) {
	initstate(1, state, sizeof state);
    }
    else {
	setstate(state);
    }
#endif
    first = 0;

    SRANDOM(seed);
    old = saved_seed;
    saved_seed = seed;

    return old;
}

static VALUE
rb_f_srand(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE a;
    unsigned int seed, old;

    if (rb_scan_args(argc, argv, "01", &a) == 0) {
	static int n = 0;
	struct timeval tv;

	gettimeofday(&tv, 0);
	seed = tv.tv_sec ^ tv.tv_usec ^ getpid() ^ n++;
    }
    else {
	seed = NUM2UINT(a);
    }
    old = rand_init(seed);

    return rb_uint2inum(old);
}

static VALUE
rb_f_rand(obj, vmax)
    VALUE obj, vmax;
{
    long val, max;

    if (first) {
	struct timeval tv;

	gettimeofday(&tv, 0);
	rand_init(tv.tv_sec ^ tv.tv_usec ^ getpid());
    }
    switch (TYPE(vmax)) {
      case T_FLOAT:
	if (RFLOAT(vmax)->value <= LONG_MAX && RFLOAT(vmax)->value >= LONG_MIN)
	    break;
	/* fall through */
      case T_BIGNUM:
	return rb_big_rand(vmax, RANDOM_NUMBER);
    }

    max = NUM2LONG(vmax);
    if (max == 0) {
	return rb_float_new(RANDOM_NUMBER);
    }
    val = max*RANDOM_NUMBER;

    if (val < 0) val = -val;
    return rb_int2inum(val);
}

void
Init_Random()
{
    rb_define_global_function("srand", rb_f_srand, -1);
    rb_define_global_function("rand", rb_f_rand, 1);
}
