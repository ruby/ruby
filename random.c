/**********************************************************************

  random.c -

  $Author$
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

/* 
This is based on trimmed version of MT19937.  To get the original version,
contact <http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html>.

The original copyright notice follows.

   A C-program for MT19937, with initialization improved 2002/2/10.
   Coded by Takuji Nishimura and Makoto Matsumoto.
   This is a faster version by taking Shawn Cokus's optimization,
   Matthe Bellew's simplification, Isaku Wada's real version.

   Before using, initialize the state by using init_genrand(mt, seed)
   or init_by_array(mt, init_key, key_length).

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

struct MT {
    unsigned long state[N]; /* the array for the state vector  */
    unsigned long *next;
    int left;
};

#define genrand_initialized(mt) ((mt)->next != 0)
#define uninit_genrand(mt) ((mt)->next = 0)

/* initializes state[N] with a seed */
static void
init_genrand(struct MT *mt, unsigned long s)
{
    int j;
    mt->state[0] = s & 0xffffffffUL;
    for (j=1; j<N; j++) {
        mt->state[j] = (1812433253UL * (mt->state[j-1] ^ (mt->state[j-1] >> 30)) + j);
        /* See Knuth TAOCP Vol2. 3rd Ed. P.106 for multiplier. */
        /* In the previous versions, MSBs of the seed affect   */
        /* only MSBs of the array state[].                        */
        /* 2002/01/09 modified by Makoto Matsumoto             */
        mt->state[j] &= 0xffffffffUL;  /* for >32 bit machines */
    }
    mt->left = 1;
    mt->next = mt->state + N - 1;
}

/* initialize by an array with array-length */
/* init_key is the array for initializing keys */
/* key_length is its length */
/* slight change for C++, 2004/2/26 */
static void
init_by_array(struct MT *mt, unsigned long init_key[], int key_length)
{
    int i, j, k;
    init_genrand(mt, 19650218UL);
    i=1; j=0;
    k = (N>key_length ? N : key_length);
    for (; k; k--) {
        mt->state[i] = (mt->state[i] ^ ((mt->state[i-1] ^ (mt->state[i-1] >> 30)) * 1664525UL))
          + init_key[j] + j; /* non linear */
        mt->state[i] &= 0xffffffffUL; /* for WORDSIZE > 32 machines */
        i++; j++;
        if (i>=N) { mt->state[0] = mt->state[N-1]; i=1; }
        if (j>=key_length) j=0;
    }
    for (k=N-1; k; k--) {
        mt->state[i] = (mt->state[i] ^ ((mt->state[i-1] ^ (mt->state[i-1] >> 30)) * 1566083941UL))
          - i; /* non linear */
        mt->state[i] &= 0xffffffffUL; /* for WORDSIZE > 32 machines */
        i++;
        if (i>=N) { mt->state[0] = mt->state[N-1]; i=1; }
    }

    mt->state[0] = 0x80000000UL; /* MSB is 1; assuring non-zero initial array */
}

static void
next_state(struct MT *mt)
{
    unsigned long *p = mt->state;
    int j;

    /* if init_genrand() has not been called, */
    /* a default initial seed is used         */
    if (!genrand_initialized(mt)) init_genrand(mt, 5489UL);

    mt->left = N;
    mt->next = mt->state;

    for (j=N-M+1; --j; p++)
        *p = p[M] ^ TWIST(p[0], p[1]);

    for (j=M; --j; p++)
        *p = p[M-N] ^ TWIST(p[0], p[1]);

    *p = p[M-N] ^ TWIST(p[0], mt->state[0]);
}

/* generates a random number on [0,0xffffffff]-interval */
static unsigned long
genrand_int32(struct MT *mt)
{
    unsigned long y;

    if (--mt->left <= 0) next_state(mt);
    y = *mt->next++;

    /* Tempering */
    y ^= (y >> 11);
    y ^= (y << 7) & 0x9d2c5680UL;
    y ^= (y << 15) & 0xefc60000UL;
    y ^= (y >> 18);

    return y;
}

/* generates a random number on [0,1) with 53-bit resolution*/
static double
genrand_real(struct MT *mt)
{
    unsigned long a=genrand_int32(mt)>>5, b=genrand_int32(mt)>>6;
    return(a*67108864.0+b)*(1.0/9007199254740992.0);
}
/* These real versions are due to Isaku Wada, 2002/01/09 added */

#undef N
#undef M

/* These real versions are due to Isaku Wada, 2002/01/09 added */

#include "ruby/ruby.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif

#define DEFAULT_SEED_CNT 4

struct RandSeed {
    VALUE value;
    unsigned long initial[DEFAULT_SEED_CNT];
};

struct Random {
    struct MT mt;
    struct RandSeed seed;
};

static struct Random default_mt;

static VALUE rand_init(struct MT *mt, VALUE vseed);
static VALUE random_seed(void);
static VALUE rand_srand(struct Random *rand, VALUE seed);

unsigned long
rb_genrand_int32(void)
{
    struct MT *mt = &default_mt.mt;
    if (!genrand_initialized(mt)) {
        rand_srand(&default_mt, random_seed());
    }
    return genrand_int32(mt);
}

double
rb_genrand_real(void)
{
    struct MT *mt = &default_mt.mt;
    if (!genrand_initialized(mt)) {
        rand_srand(&default_mt, random_seed());
    }
    return genrand_real(mt);
}

static VALUE
rand_init(struct MT *mt, VALUE vseed)
{
    volatile VALUE seed;
    long len;
    unsigned long *buf;

    seed = rb_to_int(vseed);
    switch (TYPE(seed)) {
      case T_FIXNUM:
          len = sizeof(VALUE);
          break;
      case T_BIGNUM:
          len = RBIGNUM_LEN(seed) * SIZEOF_BDIGITS;
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
        for (i = RBIGNUM_LEN(seed)-1; 0 <= i; i--) {
            j = i * SIZEOF_BDIGITS / 4;
#if SIZEOF_BDIGITS < 4
            buf[j] <<= SIZEOF_BDIGITS * 8;
#endif
            buf[j] |= RBIGNUM_DIGITS(seed)[i];
        }
    }
    while (1 < len && buf[len-1] == 0) {
        len--;
    }
    if (len <= 1) {
        init_genrand(mt, buf[0]);
    }
    else {
        if (buf[len-1] == 1) /* remove leading-zero-guard */
            len--;
        init_by_array(mt, buf, len);
    }
    xfree(buf);
    return seed;
}

#define DEFAULT_SEED_LEN (DEFAULT_SEED_CNT * sizeof(long))

static void
fill_random_seed(unsigned long seed[DEFAULT_SEED_CNT])
{
    static int n = 0;
    struct timeval tv;
    int fd;
    struct stat statbuf;

    memset(seed, 0, DEFAULT_SEED_LEN);

#ifdef S_ISCHR
    if ((fd = open("/dev/urandom", O_RDONLY
#ifdef O_NONBLOCK
            |O_NONBLOCK
#endif
#ifdef O_NOCTTY
            |O_NOCTTY
#endif
#ifdef O_NOFOLLOW
            |O_NOFOLLOW
#endif
            )) >= 0) {
        if (fstat(fd, &statbuf) == 0 && S_ISCHR(statbuf.st_mode)) {
            read(fd, seed, DEFAULT_SEED_LEN);
        }
        close(fd);
    }
#endif

    gettimeofday(&tv, 0);
    seed[0] ^= tv.tv_usec;
    seed[1] ^= tv.tv_sec;
    seed[2] ^= getpid() ^ (n++ << 16);
    seed[3] ^= (unsigned long)&seed;
}

static VALUE
make_seed_value(const void *ptr)
{
    BDIGIT *digits;
    NEWOBJ(big, struct RBignum);
    OBJSETUP(big, rb_cBignum, T_BIGNUM);

    RBIGNUM_SET_SIGN(big, 1);
    rb_big_resize((VALUE)big, DEFAULT_SEED_LEN / SIZEOF_BDIGITS + 1);
    digits = RBIGNUM_DIGITS(big);

    MEMCPY((char *)RBIGNUM_DIGITS(big), ptr, char, DEFAULT_SEED_LEN);

    /* set leading-zero-guard if need. */
    digits[RBIGNUM_LEN(big)-1] = digits[RBIGNUM_LEN(big)-2] <= 1 ? 1 : 0;

    return rb_big_norm((VALUE)big);
}

static VALUE
random_seed(void)
{
    unsigned long buf[DEFAULT_SEED_CNT];
    fill_random_seed(buf);
    return make_seed_value(buf);
}

static VALUE
rand_srand(struct Random *rand, VALUE seed)
{
    VALUE old = rand->seed.value;
    rand->seed.value = rand_init(&rand->mt, seed);

    return old;
}

/*
 *  call-seq:
 *     srand(number=0)    => old_seed
 *  
 *  Seeds the pseudorandom number generator to the value of
 *  <i>number</i>. If <i>number</i> is omitted
 *  or zero, seeds the generator using a combination of the time, the
 *  process id, and a sequence number. (This is also the behavior if
 *  <code>Kernel::rand</code> is called without previously calling
 *  <code>srand</code>, but without the sequence.) By setting the seed
 *  to a known value, scripts can be made deterministic during testing.
 *  The previous seed value is returned. Also see <code>Kernel::rand</code>.
 */

static VALUE
rb_f_srand(int argc, VALUE *argv, VALUE obj)
{
    VALUE seed;

    rb_secure(4);
    if (argc == 0) {
	seed = random_seed();
    }
    else {
	rb_scan_args(argc, argv, "01", &seed);
    }
    return rand_srand(&default_mt, seed);
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
limited_rand(struct MT *mt, unsigned long limit)
{
    unsigned long mask = make_mask(limit);
    int i;
    unsigned long val;

  retry:
    val = 0;
    for (i = SIZEOF_LONG/4-1; 0 <= i; i--) {
        if (mask >> (i * 32)) {
            val |= genrand_int32(mt) << (i * 32);
            val &= mask;
            if (limit < val)
                goto retry;
        }
    }
    return val;
}

static VALUE
limited_big_rand(struct MT *mt, struct RBignum *limit)
{
    unsigned long mask, lim, rnd;
    struct RBignum *val;
    int i, len, boundary;

    len = (RBIGNUM_LEN(limit) * SIZEOF_BDIGITS + 3) / 4;
    val = (struct RBignum *)rb_big_clone((VALUE)limit);
    RBIGNUM_SET_SIGN(val, 1);
#if SIZEOF_BDIGITS == 2
# define BIG_GET32(big,i) \
    (RBIGNUM_DIGITS(big)[(i)*2] | \
     ((i)*2+1 < RBIGNUM_LEN(big) ? \
      (RBIGNUM_DIGITS(big)[(i)*2+1] << 16) : \
      0))
# define BIG_SET32(big,i,d) \
    ((RBIGNUM_DIGITS(big)[(i)*2] = (d) & 0xffff), \
     ((i)*2+1 < RBIGNUM_LEN(big) ? \
      (RBIGNUM_DIGITS(big)[(i)*2+1] = (d) >> 16) : \
      0))
#else
    /* SIZEOF_BDIGITS == 4 */
# define BIG_GET32(big,i) (RBIGNUM_DIGITS(big)[i])
# define BIG_SET32(big,i,d) (RBIGNUM_DIGITS(big)[i] = (d))
#endif
  retry:
    mask = 0;
    boundary = 1;
    for (i = len-1; 0 <= i; i--) {
        lim = BIG_GET32(limit, i);
        mask = mask ? 0xffffffff : make_mask(lim);
        if (mask) {
            rnd = genrand_int32(mt) & mask;
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
rb_f_rand(int argc, VALUE *argv, VALUE obj)
{
    VALUE vmax;
    long val, max;
    struct MT *mt = &default_mt.mt;

    rb_scan_args(argc, argv, "01", &vmax);
    if (!genrand_initialized(mt)) {
        rand_srand(&default_mt, random_seed());
    }
    switch (TYPE(vmax)) {
      case T_FLOAT:
	if (RFLOAT_VALUE(vmax) <= LONG_MAX && RFLOAT_VALUE(vmax) >= LONG_MIN) {
	    max = (long)RFLOAT_VALUE(vmax);
	    break;
	}
        if (RFLOAT_VALUE(vmax) < 0)
            vmax = rb_dbl2big(-RFLOAT_VALUE(vmax));
        else
            vmax = rb_dbl2big(RFLOAT_VALUE(vmax));
	/* fall through */
      case T_BIGNUM:
      bignum:
        {
            struct RBignum *limit = (struct RBignum *)vmax;
            if (!RBIGNUM_SIGN(limit)) {
                limit = (struct RBignum *)rb_big_clone(vmax);
                RBIGNUM_SET_SIGN(limit, 1);
            }
            limit = (struct RBignum *)rb_big_minus((VALUE)limit, INT2FIX(1));
            if (FIXNUM_P((VALUE)limit)) {
                if (FIX2LONG((VALUE)limit) == -1)
                    return DBL2NUM(genrand_real(mt));
                return LONG2NUM(limited_rand(mt, FIX2LONG((VALUE)limit)));
            }
            return limited_big_rand(mt, limit);
	}
      case T_NIL:
	max = 0;
	break;
      default:
	vmax = rb_Integer(vmax);
	if (TYPE(vmax) == T_BIGNUM) goto bignum;
      case T_FIXNUM:
	max = FIX2LONG(vmax);
	break;
    }

    if (max == 0) {
	return DBL2NUM(genrand_real(mt));
    }
    if (max < 0) max = -max;
    val = limited_rand(mt, max-1);
    return LONG2NUM(val);
}

void
Init_RandomSeed(void)
{
    fill_random_seed(default_mt.seed.initial);
    init_by_array(&default_mt.mt, default_mt.seed.initial, DEFAULT_SEED_CNT);
}

static void
Init_RandomSeed2(void)
{
    default_mt.seed.value = make_seed_value(default_mt.seed.initial);
    memset(default_mt.seed.initial, 0, DEFAULT_SEED_LEN);
}

void
rb_reset_random_seed(void)
{
    uninit_genrand(&default_mt.mt);
    default_mt.seed.value = INT2FIX(0);
}

void
Init_Random(void)
{
    Init_RandomSeed2();
    rb_define_global_function("srand", rb_f_srand, -1);
    rb_define_global_function("rand", rb_f_rand, -1);
    rb_global_variable(&default_mt.seed.value);
}
