/************************************************

  random.c -

  $Author$
  $Date$
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

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

static int first = 1;
#ifdef HAVE_RANDOM
static char state[256];
#endif

static VALUE
f_srand(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE seed;
    int old;
    static int saved_seed;

    if (rb_scan_args(argc, argv, "01", &seed) == 0) {
	struct timeval tv;

	gettimeofday(&tv, 0);
	seed = tv.tv_usec;
    }
    else {
	seed = NUM2INT(seed);
    }

#ifdef HAVE_RANDOM
    if (first == 1) {
	initstate(1, state, sizeof state);
	first = 0;
    }
    else {
	setstate(state);
    }

    srandom(seed);
    old = saved_seed;
    saved_seed = seed;

    return int2inum(old);
#else
    srand(seed);
    old = saved_seed;
    saved_seed = seed;

    return int2inum(old);
#endif
}

static VALUE
f_rand(obj, vmax)
    VALUE obj, vmax;
{
    int val, max;

    if (first == 1) {
	f_srand(0, 0, 0);
    }

    switch (TYPE(vmax)) {
      case T_BIGNUM:
	return big_rand(vmax);
	
      case T_FLOAT:
	if (RFLOAT(vmax)->value > LONG_MAX || RFLOAT(vmax)->value < LONG_MIN)
	    return big_rand(dbl2big(RFLOAT(vmax)->value));
	break;
    }

    max = NUM2INT(vmax);
    if (max == 0) ArgError("rand(0)");

#ifdef HAVE_RANDOM
    val = random() % max;
#else
    val = rand() % max;
#endif

    if (val < 0) val = -val;
    return int2inum(val);
}

void
Init_Random()
{
    extern VALUE mKernel;

    rb_define_global_function("srand", f_srand, -1);
    rb_define_global_function("rand", f_rand, 1);
}
