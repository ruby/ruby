/************************************************

  random.c -

  $Author$
  $Date$
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

static int first = 1;
static char state[256];

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
	seed = time(0);
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

#ifdef HAVE_RANDOM
    if (first == 1) {
	initstate(1, state, sizeof state);
	first = 0;
    }
#endif

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
