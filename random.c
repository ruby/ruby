/************************************************

  random.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:48 $
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

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
    int seed, old;
#ifdef HAVE_RANDOM
    static int saved_seed;
#endif

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
    old = srand(seed);
    return int2inum(old);
#endif
}

static VALUE
f_rand(obj, max)
    VALUE obj, max;
{
    int val;

#ifdef HAVE_RANDOM
    if (first == 1) {
	initstate(1, state, sizeof state);
	first = 0;
    }
    val = random() % NUM2INT(max);
#else
    val = rand() % NUM2INT(max);
#endif

    if (val < 0) val = -val;
    return int2inum(val);
}

void
Init_Random()
{
    extern VALUE cKernel;

    rb_define_private_method(cKernel, "srand", f_srand, -1);
    rb_define_private_method(cKernel, "rand", f_rand, 1);
}
