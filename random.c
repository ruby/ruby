/**********************************************************************

  random.c -

  $Author$
  $Date$
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

/* 
This is based on trimmed version of MT19937.  To get the original version,
contact <http://www.math.keio.ac.jp/~matumoto/emt.html>.

The original copyright notice follows.

   A C-program for MT19937, with initialization improved 2002/2/10.
   Coded by Takuji Nishimura and Makoto Matsumoto.
   This is a faster version by taking Shawn Cokus's optimization,
   Matthe Bellew's simplification, Isaku Wada's real version.

   Before using, initialize the state by using init_genrand(seed) 
   or init_by_array(init_key, key_length).

   Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.                          

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

     1. Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

     2. Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

     3. The names of its contributors may not be used to endorse or promote 
        products derived from this software without specific prior written 
        permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


   Any feedback is very welcome.
   http://www.math.keio.ac.jp/matumoto/emt.html
   email: matumoto@math.keio.ac.jp
*/

/* Period parameters */  
#define N 624
#define M 397
#define MATRIX_A 0x9908b0dfUL   /* constant vector a */
#define UMASK 0x80000000UL /* most significant w-r bits */
#define LMASK 0x7fffffffUL /* least significant r bits */
#define MIXBITS(u,v) ( ((u) & UMASK) | ((v) & LMASK) )
#define TWIST(u,v) ((MIXBITS(u,v) >> 1) ^ ((v)&1UL ? MATRIX_A : 0UL))

static unsigned long state[N]; /* the array for the state vector  */
static int left = 1;
static int initf = 0;
static unsigned long *next;

/* initializes state[N] with a seed */
static void
init_genrand(s)
    unsigned long s;
{
    int j;
    state[0]= s & 0xffffffffUL;
    for (j=1; j<N; j++) {
        state[j] = (1812433253UL * (state[j-1] ^ (state[j-1] >> 30)) + j); 
        /* See Knuth TAOCP Vol2. 3rd Ed. P.106 for multiplier. */
        /* In the previous versions, MSBs of the seed affect   */
        /* only MSBs of the array state[].                        */
        /* 2002/01/09 modified by Makoto Matsumoto             */
        state[j] &= 0xffffffffUL;  /* for >32 bit machines */
    }
    left = 1; initf = 1;
}

static void
next_state()
{
    unsigned long *p=state;
    int j;

    /* if init_genrand() has not been called, */
    /* a default initial seed is used         */
    if (initf==0) init_genrand(5489UL);

    left = N;
    next = state;
    
    for (j=N-M+1; --j; p++) 
        *p = p[M] ^ TWIST(p[0], p[1]);

    for (j=M; --j; p++) 
        *p = p[M-N] ^ TWIST(p[0], p[1]);

    *p = p[M-N] ^ TWIST(p[0], state[0]);
}

/* generates a random number on [0,1)-real-interval */
static double
genrand_real()
{
    unsigned long y;

    if (--left == 0) next_state();
    y = *next++;

    /* Tempering */
    y ^= (y >> 11);
    y ^= (y << 7) & 0x9d2c5680UL;
    y ^= (y << 15) & 0xefc60000UL;
    y ^= (y >> 18);

    return (double)y * (1.0/4294967296.0); 
    /* divided by 2^32 */
}

#undef N
#undef M

/* These real versions are due to Isaku Wada, 2002/01/09 added */

#include "ruby.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <time.h>

static int first = 1;

static int
rand_init(seed)
    unsigned long seed;
{
    static unsigned long saved_seed;
    unsigned long old;

    first = 0;
    init_genrand(seed);
    old = saved_seed;
    saved_seed = seed;

    return old;
}

static unsigned long
random_seed()
{
    static int n = 0;
    struct timeval tv;

    gettimeofday(&tv, 0);
    return tv.tv_sec ^ tv.tv_usec ^ getpid() ^ n++;
}

/*
 *  call-seq:
 *     srand(number=0)    => old_seed
 *  
 *  Seeds the pseudorandom number generator to the value of
 *  <i>number</i>.<code>to_i.abs</code>. If <i>number</i> is omitted
 *  or zero, seeds the generator using a combination of the time, the
 *  process id, and a sequence number. (This is also the behavior if
 *  <code>Kernel::rand</code> is called without previously calling
 *  <code>srand</code>, but without the sequence.) By setting the seed
 *  to a known value, scripts can be made deterministic during testing.
 *  The previous seed value is returned. Also see <code>Kernel::rand</code>.
 */

static VALUE
rb_f_srand(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE sd;
    unsigned long seed, old;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "01", &sd) == 0) {
	seed = random_seed();
    }
    else {
	seed = NUM2ULONG(sd);
    }
    old = rand_init(seed);

    return ULONG2NUM(old);
}

/*
 *  call-seq:
 *     rand(max=0)    => number
 *  
 *  Converts <i>max</i> to an integer using max1 =
 *  max<code>.to_i.abs</code>. If the result is zero, returns a
 *  pseudorandom floating point number greater than or equal to 0.0 and
 *  less than 1.0. Otherwise, returns a pseudorandom integer greater
 *  than or equal to zero and less than max1. <code>Kernel::srand</code>
 *  may be used to ensure repeatable sequences of random numbers between
 *  different runs of the program. Ruby currently uses a modified
 *  Mersenne Twister with a period of 219937-1.
 *     
 *     srand 1234                 #=> 0
 *     [ rand,  rand ]            #=> [0.191519450163469, 0.49766366626136]
 *     [ rand(10), rand(1000) ]   #=> [6, 817]
 *     srand 1234                 #=> 1234
 *     [ rand,  rand ]            #=> [0.191519450163469, 0.49766366626136]
 */

static VALUE
rb_f_rand(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE vmax;
    long val, max;

    rb_scan_args(argc, argv, "01", &vmax);
    if (first) {
	rand_init(random_seed());
    }
    switch (TYPE(vmax)) {
      case T_FLOAT:
	if (RFLOAT(vmax)->value <= LONG_MAX && RFLOAT(vmax)->value >= LONG_MIN) {
	    max = (long)RFLOAT(vmax)->value;
	    break;
	}
	vmax = rb_dbl2big(RFLOAT(vmax)->value);
	/* fall through */
      case T_BIGNUM:
      bignum:
        {
	    long len = RBIGNUM(vmax)->len;
	    double *buf = ALLOCA_N(double, len);

	    while (len--) {
		buf[len] = genrand_real();
	    }
	    return rb_big_rand(vmax, buf);
	}
      case T_NIL:
	max = 0;
	break;
      default:
	vmax = rb_Integer(vmax);
	if (TYPE(vmax) == T_BIGNUM) goto bignum;
      case T_FIXNUM:
	max = NUM2LONG(vmax);
	break;
    }

    if (max == 0) {
	return rb_float_new(genrand_real());
    }
    if (max < 0) max = -max;
    val = max*genrand_real();

    return LONG2NUM(val);
}

void
Init_Random()
{
    rb_define_global_function("srand", rb_f_srand, -1);
    rb_define_global_function("rand", rb_f_rand, -1);
}
