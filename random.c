/************************************************

  random.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

static int first = 1;
static char state[256];

static VALUE
Fsrand(obj, args)
    VALUE obj, args;
{
    int seed, old;
#ifdef HAVE_RANDOM
    static int saved_seed;
#endif

    if (rb_scan_args(args, "01", &seed) == 0) {
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
Frand(obj, max)
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

Init_Random()
{
    extern VALUE C_Kernel;

    rb_define_func(C_Kernel, "srand", Fsrand, -2);
    rb_define_func(C_Kernel, "rand", Frand, 1);
}
