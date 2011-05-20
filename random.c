/**********************************************************************

  random.c -

  $Author$
  $Date$
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

/*
This is based on trimmed version of MT19937.  To get the original version,
contact <http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html>.

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

/* initialize by an array with array-length */
/* init_key is the array for initializing keys */
/* key_length is its length */
/* slight change for C++, 2004/2/26 */
static void
init_by_array(unsigned long init_key[], int key_length)
{
    int i, j, k;
    init_genrand(19650218UL);
    i=1; j=0;
    k = (N>key_length ? N : key_length);
    for (; k; k--) {
        state[i] = (state[i] ^ ((state[i-1] ^ (state[i-1] >> 30)) * 1664525UL))
          + init_key[j] + j; /* non linear */
        state[i] &= 0xffffffffUL; /* for WORDSIZE > 32 machines */
        i++; j++;
        if (i>=N) { state[0] = state[N-1]; i=1; }
        if (j>=key_length) j=0;
    }
    for (k=N-1; k; k--) {
        state[i] = (state[i] ^ ((state[i-1] ^ (state[i-1] >> 30)) * 1566083941UL))
          - i; /* non linear */
        state[i] &= 0xffffffffUL; /* for WORDSIZE > 32 machines */
        i++;
        if (i>=N) { state[0] = state[N-1]; i=1; }
    }

    state[0] = 0x80000000UL; /* MSB is 1; assuring non-zero initial array */
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

/* generates a random number on [0,0xffffffff]-interval */
unsigned long
rb_genrand_int32(void)
{
    unsigned long y;

    if (--left == 0) next_state();
    y = *next++;

    /* Tempering */
    y ^= (y >> 11);
    y ^= (y << 7) & 0x9d2c5680UL;
    y ^= (y << 15) & 0xefc60000UL;
    y ^= (y >> 18);

    return y;
}

/* generates a random number on [0,1) with 53-bit resolution*/
double
rb_genrand_real(void)
{
    unsigned long a=rb_genrand_int32()>>5, b=rb_genrand_int32()>>6;
    return(a*67108864.0+b)*(1.0/9007199254740992.0);
}
/* These real versions are due to Isaku Wada, 2002/01/09 added */

#undef N
#undef M

/* These real versions are due to Isaku Wada, 2002/01/09 added */

#include "ruby.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif

static VALUE saved_seed = INT2FIX(0);

static VALUE
rand_init(vseed)
    VALUE vseed;
{
    volatile VALUE seed;
    VALUE old;
    long len;
    unsigned long *buf;

    seed = rb_to_int(vseed);
    switch (TYPE(seed)) {
      case T_FIXNUM:
          len = sizeof(VALUE);
          break;
      case T_BIGNUM:
          len = RBIGNUM(seed)->len * SIZEOF_BDIGITS;
          if (len == 0)
              len = 4;
          break;
      default:
          rb_raise(rb_eTypeError, "failed to convert %s into Integer",
                   rb_obj_classname(vseed));
    }
    len = (len + 3) / 4; /* number of 32bit words */
    buf = ALLOC_N(unsigned long, len); /* allocate longs for init_by_array */
    memset(buf, 0, len * sizeof(long));
    if (FIXNUM_P(seed)) {
        buf[0] = FIX2ULONG(seed) & 0xffffffff;
#if SIZEOF_LONG > 4
        buf[1] = FIX2ULONG(seed) >> 32;
#endif
    }
    else {
        int i, j;
        for (i = RBIGNUM(seed)->len-1; 0 <= i; i--) {
            j = i * SIZEOF_BDIGITS / 4;
#if SIZEOF_BDIGITS < 4
            buf[j] <<= SIZEOF_BDIGITS * 8;
#endif
            buf[j] |= ((BDIGIT *)RBIGNUM(seed)->digits)[i];
        }
    }
    while (1 < len && buf[len-1] == 0) {
        len--;
    }
    if (len <= 1) {
        init_genrand(buf[0]);
    }
    else {
        if (buf[len-1] == 1) /* remove leading-zero-guard */
            len--;
        init_by_array(buf, len);
    }
    old = saved_seed;
    saved_seed = seed;
    free(buf);
    return old;
}

static VALUE
random_seed()
{
    static int n = 0;
    struct timeval tv;
    int fd;
    struct stat statbuf;

    int seed_len;
    BDIGIT *digits;
    unsigned long *seed;
    NEWOBJ(big, struct RBignum);
    OBJSETUP(big, rb_cBignum, T_BIGNUM);

    seed_len = 4 * sizeof(long);
    big->sign = 1;
    big->len = seed_len / SIZEOF_BDIGITS + 1;
    digits = big->digits = ALLOC_N(BDIGIT, big->len);
    seed = (unsigned long *)big->digits;

    memset(digits, 0, big->len * SIZEOF_BDIGITS);

#ifdef S_ISCHR
    if ((fd = open("/dev/urandom", O_RDONLY
#ifdef O_NONBLOCK
            |O_NONBLOCK
#endif
#ifdef O_NOCTTY
            |O_NOCTTY
#endif
            )) >= 0) {
        if (fstat(fd, &statbuf) == 0 && S_ISCHR(statbuf.st_mode)) {
            read(fd, seed, seed_len);
        }
        close(fd);
    }
#endif

    gettimeofday(&tv, 0);
    seed[0] ^= tv.tv_usec;
    seed[1] ^= tv.tv_sec;
    seed[2] ^= getpid() ^ (n++ << 16);
    seed[3] ^= (unsigned long)&seed;

    /* set leading-zero-guard if need. */
    digits[big->len-1] = digits[big->len-2] <= 1 ? 1 : 0;

    return rb_big_norm((VALUE)big);
}

/*
 *  call-seq:
 *     srand(number=0)    => old_seed
 *
 *  Seeds the pseudorandom number generator to the value of
 *  <i>number</i>.<code>to_i.abs</code>. If <i>number</i> is omitted,
 *  seeds the generator using a combination of the time, the
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
    VALUE seed, old;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "01", &seed) == 0) {
	seed = random_seed();
    }
    old = rand_init(seed);

    return old;
}

static unsigned long
make_mask(unsigned long x)
{
    x = x | x >> 1;
    x = x | x >> 2;
    x = x | x >> 4;
    x = x | x >> 8;
    x = x | x >> 16;
#if 4 < SIZEOF_LONG
    x = x | x >> 32;
#endif
    return x;
}

static unsigned long
limited_rand(unsigned long limit)
{
    unsigned long mask = make_mask(limit);
    int i;
    unsigned long val;

  retry:
    val = 0;
    for (i = SIZEOF_LONG/4-1; 0 <= i; i--) {
        if (mask >> (i * 32)) {
            val |= rb_genrand_int32() << (i * 32);
            val &= mask;
            if (limit < val)
                goto retry;
        }
    }
    return val;
}

static VALUE
limited_big_rand(struct RBignum *limit)
{
    unsigned long mask, lim, rnd;
    struct RBignum *val;
    int i, len, boundary;

    len = (limit->len * SIZEOF_BDIGITS + 3) / 4;
    val = (struct RBignum *)rb_big_clone((VALUE)limit);
    val->sign = 1;
#if SIZEOF_BDIGITS == 2
# define BIG_GET32(big,i) (((BDIGIT *)(big)->digits)[(i)*2] | \
                           ((i)*2+1 < (big)->len ? (((BDIGIT *)(big)->digits)[(i)*2+1] << 16) \
                                                 : 0))
# define BIG_SET32(big,i,d) ((((BDIGIT *)(big)->digits)[(i)*2] = (d) & 0xffff), \
                             ((i)*2+1 < (big)->len ? (((BDIGIT *)(big)->digits)[(i)*2+1] = (d) >> 16) \
                                                   : 0))
#else
    /* SIZEOF_BDIGITS == 4 */
# define BIG_GET32(big,i) (((BDIGIT *)(big)->digits)[i])
# define BIG_SET32(big,i,d) (((BDIGIT *)(big)->digits)[i] = (d))
#endif
  retry:
    mask = 0;
    boundary = 1;
    for (i = len-1; 0 <= i; i--) {
        lim = BIG_GET32(limit, i);
        mask = mask ? 0xffffffff : make_mask(lim);
        if (mask) {
            rnd = rb_genrand_int32() & mask;
            if (boundary) {
                if (lim < rnd)
                    goto retry;
                if (rnd < lim)
                    boundary = 0;
            }
        }
        else {
            rnd = 0;
        }
        BIG_SET32(val, i, rnd);
    }
    return rb_big_norm((VALUE)val);
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
 *  Mersenne Twister with a period of 2**19937-1.
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
    switch (TYPE(vmax)) {
      case T_FLOAT:
	if (RFLOAT(vmax)->value <= LONG_MAX && RFLOAT(vmax)->value >= LONG_MIN) {
	    max = (long)RFLOAT(vmax)->value;
	    break;
	}
        if (RFLOAT(vmax)->value < 0)
            vmax = rb_dbl2big(-RFLOAT(vmax)->value);
        else
            vmax = rb_dbl2big(RFLOAT(vmax)->value);
	/* fall through */
      case T_BIGNUM:
      bignum:
        {
            struct RBignum *limit = (struct RBignum *)vmax;
            if (!limit->sign) {
                limit = (struct RBignum *)rb_big_clone(vmax);
                limit->sign = 1;
            }
            limit = (struct RBignum *)rb_big_minus((VALUE)limit, INT2FIX(1));
            if (FIXNUM_P((VALUE)limit)) {
                if (FIX2LONG((VALUE)limit) == -1)
                    return rb_float_new(rb_genrand_real());
                return LONG2NUM(limited_rand(FIX2LONG((VALUE)limit)));
            }
            return limited_big_rand(limit);
	}
      case T_NIL:
	max = 0;
	break;
      default:
	vmax = rb_Integer(vmax);
	if (TYPE(vmax) == T_BIGNUM) goto bignum;
	/* fall through */
      case T_FIXNUM:
	max = FIX2LONG(vmax);
	break;
    }

    if (max == 0) {
	return rb_float_new(rb_genrand_real());
    }
    if (max < 0) max = -max;
    val = limited_rand(max-1);
    return LONG2NUM(val);
}

void
rb_reset_random_seed()
{
    rand_init(random_seed());
}

void
Init_Random()
{
    rb_reset_random_seed();
    rb_define_global_function("srand", rb_f_srand, -1);
    rb_define_global_function("rand", rb_f_rand, -1);
    rb_global_variable(&saved_seed);
}
