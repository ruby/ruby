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

#include "ruby/ruby.h"
#include "internal.h"

#include <limits.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif
#include <math.h>
#include <errno.h>
#if defined(HAVE_SYS_TIME_H)
#include <sys/time.h>
#endif

#ifdef _WIN32
# if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0400
#  undef _WIN32_WINNT
#  define _WIN32_WINNT 0x400
#  undef __WINCRYPT_H__
# endif
#include <wincrypt.h>
#endif

typedef int int_must_be_32bit_at_least[sizeof(int) * CHAR_BIT < 32 ? -1 : 1];

/* Period parameters */
#define N 624
#define M 397
#define MATRIX_A 0x9908b0dfU	/* constant vector a */
#define UMASK 0x80000000U	/* most significant w-r bits */
#define LMASK 0x7fffffffU	/* least significant r bits */
#define MIXBITS(u,v) ( ((u) & UMASK) | ((v) & LMASK) )
#define TWIST(u,v) ((MIXBITS((u),(v)) >> 1) ^ ((v)&1U ? MATRIX_A : 0U))

enum {MT_MAX_STATE = N};

struct MT {
    /* assume int is enough to store 32bits */
    unsigned int state[N]; /* the array for the state vector  */
    unsigned int *next;
    int left;
};

#define genrand_initialized(mt) ((mt)->next != 0)
#define uninit_genrand(mt) ((mt)->next = 0)

/* initializes state[N] with a seed */
static void
init_genrand(struct MT *mt, unsigned int s)
{
    int j;
    mt->state[0] = s & 0xffffffffU;
    for (j=1; j<N; j++) {
        mt->state[j] = (1812433253U * (mt->state[j-1] ^ (mt->state[j-1] >> 30)) + j);
        /* See Knuth TAOCP Vol2. 3rd Ed. P.106 for multiplier. */
        /* In the previous versions, MSBs of the seed affect   */
        /* only MSBs of the array state[].                     */
        /* 2002/01/09 modified by Makoto Matsumoto             */
        mt->state[j] &= 0xffffffff;  /* for >32 bit machines */
    }
    mt->left = 1;
    mt->next = mt->state + N;
}

/* initialize by an array with array-length */
/* init_key is the array for initializing keys */
/* key_length is its length */
/* slight change for C++, 2004/2/26 */
static void
init_by_array(struct MT *mt, unsigned int init_key[], int key_length)
{
    int i, j, k;
    init_genrand(mt, 19650218U);
    i=1; j=0;
    k = (N>key_length ? N : key_length);
    for (; k; k--) {
        mt->state[i] = (mt->state[i] ^ ((mt->state[i-1] ^ (mt->state[i-1] >> 30)) * 1664525U))
          + init_key[j] + j; /* non linear */
        mt->state[i] &= 0xffffffffU; /* for WORDSIZE > 32 machines */
        i++; j++;
        if (i>=N) { mt->state[0] = mt->state[N-1]; i=1; }
        if (j>=key_length) j=0;
    }
    for (k=N-1; k; k--) {
        mt->state[i] = (mt->state[i] ^ ((mt->state[i-1] ^ (mt->state[i-1] >> 30)) * 1566083941U))
          - i; /* non linear */
        mt->state[i] &= 0xffffffffU; /* for WORDSIZE > 32 machines */
        i++;
        if (i>=N) { mt->state[0] = mt->state[N-1]; i=1; }
    }

    mt->state[0] = 0x80000000U; /* MSB is 1; assuring non-zero initial array */
}

static void
next_state(struct MT *mt)
{
    unsigned int *p = mt->state;
    int j;

    mt->left = N;
    mt->next = mt->state;

    for (j=N-M+1; --j; p++)
        *p = p[M] ^ TWIST(p[0], p[1]);

    for (j=M; --j; p++)
        *p = p[M-N] ^ TWIST(p[0], p[1]);

    *p = p[M-N] ^ TWIST(p[0], mt->state[0]);
}

/* generates a random number on [0,0xffffffff]-interval */
static unsigned int
genrand_int32(struct MT *mt)
{
    /* mt must be initialized */
    unsigned int y;

    if (--mt->left <= 0) next_state(mt);
    y = *mt->next++;

    /* Tempering */
    y ^= (y >> 11);
    y ^= (y << 7) & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= (y >> 18);

    return y;
}

/* generates a random number on [0,1) with 53-bit resolution*/
static double
genrand_real(struct MT *mt)
{
    /* mt must be initialized */
    unsigned int a = genrand_int32(mt)>>5, b = genrand_int32(mt)>>6;
    return(a*67108864.0+b)*(1.0/9007199254740992.0);
}

/* generates a random number on [0,1] with 53-bit resolution*/
static double int_pair_to_real_inclusive(uint32_t a, uint32_t b);
static double
genrand_real2(struct MT *mt)
{
    /* mt must be initialized */
    uint32_t a = genrand_int32(mt), b = genrand_int32(mt);
    return int_pair_to_real_inclusive(a, b);
}

/* These real versions are due to Isaku Wada, 2002/01/09 added */

#undef N
#undef M

typedef struct {
    VALUE seed;
    struct MT mt;
} rb_random_t;

#define DEFAULT_SEED_CNT 4

static rb_random_t default_rand;

static VALUE rand_init(struct MT *mt, VALUE vseed);
static VALUE random_seed(void);

static rb_random_t *
rand_start(rb_random_t *r)
{
    struct MT *mt = &r->mt;
    if (!genrand_initialized(mt)) {
	r->seed = rand_init(mt, random_seed());
    }
    return r;
}

static struct MT *
default_mt(void)
{
    return &rand_start(&default_rand)->mt;
}

unsigned int
rb_genrand_int32(void)
{
    struct MT *mt = default_mt();
    return genrand_int32(mt);
}

double
rb_genrand_real(void)
{
    struct MT *mt = default_mt();
    return genrand_real(mt);
}

#define SIZEOF_INT32 (31/CHAR_BIT + 1)

static double
int_pair_to_real_inclusive(uint32_t a, uint32_t b)
{
    VALUE x;
    VALUE m;
    uint32_t xary[2], mary[2];
    double r;

    /* (a << 32) | b */
    xary[0] = a;
    xary[1] = b;
    x = rb_integer_unpack(xary, 2, sizeof(uint32_t), 0,
        INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER|
        INTEGER_PACK_FORCE_BIGNUM);

    /* (1 << 53) | 1 */
    mary[0] = 0x00200000;
    mary[1] = 0x00000001;
    m = rb_integer_unpack(mary, 2, sizeof(uint32_t), 0,
        INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER|
        INTEGER_PACK_FORCE_BIGNUM);

    x = rb_big_mul(x, m);
    if (FIXNUM_P(x)) {
#if CHAR_BIT * SIZEOF_LONG > 64
	r = (double)(FIX2ULONG(x) >> 64);
#else
	return 0.0;
#endif
    }
    else {
        uint32_t uary[4];
        rb_integer_pack(x, uary, numberof(uary), sizeof(uint32_t), 0,
                INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
        /* r = x >> 64 */
        r = (double)uary[0] * (0x10000 * (double)0x10000) + (double)uary[1];
    }
    return ldexp(r, -53);
}

VALUE rb_cRandom;
#define id_minus '-'
#define id_plus  '+'
static ID id_rand, id_bytes;

/* :nodoc: */
static void
random_mark(void *ptr)
{
    rb_gc_mark(((rb_random_t *)ptr)->seed);
}

static void
random_free(void *ptr)
{
    if (ptr != &default_rand)
	xfree(ptr);
}

static size_t
random_memsize(const void *ptr)
{
    return ptr ? sizeof(rb_random_t) : 0;
}

static const rb_data_type_t random_data_type = {
    "random",
    {
	random_mark,
	random_free,
	random_memsize,
    },
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
};

static rb_random_t *
get_rnd(VALUE obj)
{
    rb_random_t *ptr;
    TypedData_Get_Struct(obj, rb_random_t, &random_data_type, ptr);
    return ptr;
}

static rb_random_t *
try_get_rnd(VALUE obj)
{
    if (obj == rb_cRandom) {
	return rand_start(&default_rand);
    }
    if (!rb_typeddata_is_kind_of(obj, &random_data_type)) return NULL;
    return DATA_PTR(obj);
}

/* :nodoc: */
static VALUE
random_alloc(VALUE klass)
{
    rb_random_t *rnd;
    VALUE obj = TypedData_Make_Struct(klass, rb_random_t, &random_data_type, rnd);
    rnd->seed = INT2FIX(0);
    return obj;
}

static VALUE
rand_init(struct MT *mt, VALUE vseed)
{
    volatile VALUE seed;
    uint32_t buf0[SIZEOF_LONG / SIZEOF_INT32 * 4], *buf = buf0;
    size_t len;
    int sign;

    seed = rb_to_int(vseed);

    len = rb_absint_numwords(seed, 32, NULL);
    if (len > numberof(buf0))
        buf = ALLOC_N(unsigned int, len);
    sign = rb_integer_pack(seed, buf, len, sizeof(uint32_t), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
    if (sign < 0)
        sign = -sign;
    if (len == 0) {
        buf[0] = 0;
        len = 1;
    }
    if (len <= 1) {
        init_genrand(mt, buf[0]);
    }
    else {
        if (sign != 2 && buf[len-1] == 1) /* remove leading-zero-guard */
            len--;
        init_by_array(mt, buf, (int)len);
    }
    if (buf != buf0) xfree(buf);
    return seed;
}

/*
 * call-seq:
 *   Random.new(seed = Random.new_seed) -> prng
 *
 * Creates a new PRNG using +seed+ to set the initial state. If +seed+ is
 * omitted, the generator is initialized with Random.new_seed.
 *
 * See Random.srand for more information on the use of seed values.
 */
static VALUE
random_init(int argc, VALUE *argv, VALUE obj)
{
    VALUE vseed;
    rb_random_t *rnd = get_rnd(obj);

    if (argc == 0) {
	rb_check_frozen(obj);
	vseed = random_seed();
    }
    else {
	rb_scan_args(argc, argv, "01", &vseed);
	rb_check_copyable(obj, vseed);
    }
    rnd->seed = rand_init(&rnd->mt, vseed);
    return obj;
}

#define DEFAULT_SEED_LEN (DEFAULT_SEED_CNT * (int)sizeof(int32_t))

#if defined(S_ISCHR) && !defined(DOSISH)
# define USE_DEV_URANDOM 1
#else
# define USE_DEV_URANDOM 0
#endif

static void
fill_random_seed(uint32_t seed[DEFAULT_SEED_CNT])
{
    static int n = 0;
    struct timeval tv;
#if USE_DEV_URANDOM
    int fd;
    struct stat statbuf;
#elif defined(_WIN32)
    HCRYPTPROV prov;
#endif

    memset(seed, 0, DEFAULT_SEED_LEN);

#if USE_DEV_URANDOM
    if ((fd = rb_cloexec_open("/dev/urandom", O_RDONLY
#ifdef O_NONBLOCK
            |O_NONBLOCK
#endif
#ifdef O_NOCTTY
            |O_NOCTTY
#endif
            , 0)) >= 0) {
        rb_update_max_fd(fd);
        if (fstat(fd, &statbuf) == 0 && S_ISCHR(statbuf.st_mode)) {
	    if (read(fd, seed, DEFAULT_SEED_LEN) < DEFAULT_SEED_LEN) {
		/* abandon */;
	    }
        }
        close(fd);
    }
#elif defined(_WIN32)
    if (CryptAcquireContext(&prov, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT)) {
	CryptGenRandom(prov, DEFAULT_SEED_LEN, (void *)seed);
	CryptReleaseContext(prov, 0);
    }
#endif

    gettimeofday(&tv, 0);
    seed[0] ^= tv.tv_usec;
    seed[1] ^= (unsigned int)tv.tv_sec;
#if SIZEOF_TIME_T > SIZEOF_INT
    seed[0] ^= (unsigned int)((time_t)tv.tv_sec >> SIZEOF_INT * CHAR_BIT);
#endif
    seed[2] ^= getpid() ^ (n++ << 16);
    seed[3] ^= (unsigned int)(VALUE)&seed;
#if SIZEOF_VOIDP > SIZEOF_INT
    seed[2] ^= (unsigned int)((VALUE)&seed >> SIZEOF_INT * CHAR_BIT);
#endif
}

static VALUE
make_seed_value(const uint32_t *ptr)
{
    VALUE seed;
    size_t len;
    uint32_t buf[DEFAULT_SEED_CNT+1];

    if (ptr[DEFAULT_SEED_CNT-1] <= 1) {
        /* set leading-zero-guard */
        MEMCPY(buf, ptr, uint32_t, DEFAULT_SEED_CNT);
        buf[DEFAULT_SEED_CNT] = 1;
        ptr = buf;
        len = DEFAULT_SEED_CNT+1;
    }
    else {
        len = DEFAULT_SEED_CNT;
    }

    seed = rb_integer_unpack(ptr, len, sizeof(uint32_t), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);

    return seed;
}

/*
 * call-seq: Random.new_seed -> integer
 *
 * Returns an arbitrary seed value. This is used by Random.new
 * when no seed value is specified as an argument.
 *
 *   Random.new_seed  #=> 115032730400174366788466674494640623225
 */
static VALUE
random_seed(void)
{
    uint32_t buf[DEFAULT_SEED_CNT];
    fill_random_seed(buf);
    return make_seed_value(buf);
}

/*
 * call-seq: prng.seed -> integer
 *
 * Returns the seed value used to initialize the generator. This may be used to
 * initialize another generator with the same state at a later time, causing it
 * to produce the same sequence of numbers.
 *
 *   prng1 = Random.new(1234)
 *   prng1.seed       #=> 1234
 *   prng1.rand(100)  #=> 47
 *
 *   prng2 = Random.new(prng1.seed)
 *   prng2.rand(100)  #=> 47
 */
static VALUE
random_get_seed(VALUE obj)
{
    return get_rnd(obj)->seed;
}

/* :nodoc: */
static VALUE
random_copy(VALUE obj, VALUE orig)
{
    rb_random_t *rnd1, *rnd2;
    struct MT *mt;

    if (!OBJ_INIT_COPY(obj, orig)) return obj;

    rnd1 = get_rnd(obj);
    rnd2 = get_rnd(orig);
    mt = &rnd1->mt;

    *rnd1 = *rnd2;
    mt->next = mt->state + numberof(mt->state) - mt->left + 1;
    return obj;
}

static VALUE
mt_state(const struct MT *mt)
{
    return rb_integer_unpack(mt->state, numberof(mt->state),
        sizeof(*mt->state), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
}

/* :nodoc: */
static VALUE
random_state(VALUE obj)
{
    rb_random_t *rnd = get_rnd(obj);
    return mt_state(&rnd->mt);
}

/* :nodoc: */
static VALUE
random_s_state(VALUE klass)
{
    return mt_state(&default_rand.mt);
}

/* :nodoc: */
static VALUE
random_left(VALUE obj)
{
    rb_random_t *rnd = get_rnd(obj);
    return INT2FIX(rnd->mt.left);
}

/* :nodoc: */
static VALUE
random_s_left(VALUE klass)
{
    return INT2FIX(default_rand.mt.left);
}

/* :nodoc: */
static VALUE
random_dump(VALUE obj)
{
    rb_random_t *rnd = get_rnd(obj);
    VALUE dump = rb_ary_new2(3);

    rb_ary_push(dump, mt_state(&rnd->mt));
    rb_ary_push(dump, INT2FIX(rnd->mt.left));
    rb_ary_push(dump, rnd->seed);

    return dump;
}

/* :nodoc: */
static VALUE
random_load(VALUE obj, VALUE dump)
{
    rb_random_t *rnd = get_rnd(obj);
    struct MT *mt = &rnd->mt;
    VALUE state, left = INT2FIX(1), seed = INT2FIX(0);
    const VALUE *ary;
    unsigned long x;

    rb_check_copyable(obj, dump);
    Check_Type(dump, T_ARRAY);
    ary = RARRAY_CONST_PTR(dump);
    switch (RARRAY_LEN(dump)) {
      case 3:
	seed = ary[2];
      case 2:
	left = ary[1];
      case 1:
	state = ary[0];
	break;
      default:
	rb_raise(rb_eArgError, "wrong dump data");
    }
    rb_integer_pack(state, mt->state, numberof(mt->state),
        sizeof(*mt->state), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
    x = NUM2ULONG(left);
    if (x > numberof(mt->state)) {
	rb_raise(rb_eArgError, "wrong value");
    }
    mt->left = (unsigned int)x;
    mt->next = mt->state + numberof(mt->state) - x + 1;
    rnd->seed = rb_to_int(seed);

    return obj;
}

/*
 * call-seq:
 *   srand(number = Random.new_seed) -> old_seed
 *
 * Seeds the system pseudo-random number generator, Random::DEFAULT, with
 * +number+.  The previous seed value is returned.
 *
 * If +number+ is omitted, seeds the generator using a source of entropy
 * provided by the operating system, if available (/dev/urandom on Unix systems
 * or the RSA cryptographic provider on Windows), which is then combined with
 * the time, the process id, and a sequence number.
 *
 * srand may be used to ensure repeatable sequences of pseudo-random numbers
 * between different runs of the program. By setting the seed to a known value,
 * programs can be made deterministic during testing.
 *
 *   srand 1234               # => 268519324636777531569100071560086917274
 *   [ rand, rand ]           # => [0.1915194503788923, 0.6221087710398319]
 *   [ rand(10), rand(1000) ] # => [4, 664]
 *   srand 1234               # => 1234
 *   [ rand, rand ]           # => [0.1915194503788923, 0.6221087710398319]
 */

static VALUE
rb_f_srand(int argc, VALUE *argv, VALUE obj)
{
    VALUE seed, old;
    rb_random_t *r = &default_rand;

    if (argc == 0) {
	seed = random_seed();
    }
    else {
	rb_scan_args(argc, argv, "01", &seed);
    }
    old = r->seed;
    r->seed = rand_init(&r->mt, seed);

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
limited_rand(struct MT *mt, unsigned long limit)
{
    /* mt must be initialized */
    int i;
    unsigned long val, mask;

    if (!limit) return 0;
    mask = make_mask(limit);
  retry:
    val = 0;
    for (i = SIZEOF_LONG/SIZEOF_INT32-1; 0 <= i; i--) {
        if ((mask >> (i * 32)) & 0xffffffff) {
            val |= (unsigned long)genrand_int32(mt) << (i * 32);
            val &= mask;
            if (limit < val)
                goto retry;
        }
    }
    return val;
}

static VALUE
limited_big_rand(struct MT *mt, VALUE limit)
{
    /* mt must be initialized */

    uint32_t mask;
    long i;
    int boundary;

    size_t len;
    uint32_t *tmp, *lim_array, *rnd_array;
    VALUE vtmp;
    VALUE val;

    len = rb_absint_numwords(limit, 32, NULL);
    tmp = ALLOCV_N(uint32_t, vtmp, len*2);
    lim_array = tmp;
    rnd_array = tmp + len;
    rb_integer_pack(limit, lim_array, len, sizeof(uint32_t), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);

  retry:
    mask = 0;
    boundary = 1;
    for (i = len-1; 0 <= i; i--) {
	uint32_t rnd;
        uint32_t lim = lim_array[i];
        mask = mask ? 0xffffffff : (uint32_t)make_mask(lim);
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
        rnd_array[i] = rnd;
    }
    val = rb_integer_unpack(rnd_array, len, sizeof(uint32_t), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
    ALLOCV_END(vtmp);

    return val;
}

/*
 * Returns random unsigned long value in [0, +limit+].
 *
 * Note that +limit+ is included, and the range of the argument and the
 * return value depends on environments.
 */
unsigned long
rb_genrand_ulong_limited(unsigned long limit)
{
    return limited_rand(default_mt(), limit);
}

unsigned int
rb_random_int32(VALUE obj)
{
    rb_random_t *rnd = try_get_rnd(obj);
    if (!rnd) {
#if SIZEOF_LONG * CHAR_BIT > 32
	VALUE lim = ULONG2NUM(0x100000000UL);
#elif defined HAVE_LONG_LONG
	VALUE lim = ULL2NUM((LONG_LONG)0xffffffff+1);
#else
	VALUE lim = rb_big_plus(ULONG2NUM(0xffffffff), INT2FIX(1));
#endif
	return (unsigned int)NUM2ULONG(rb_funcall2(obj, id_rand, 1, &lim));
    }
    return genrand_int32(&rnd->mt);
}

double
rb_random_real(VALUE obj)
{
    rb_random_t *rnd = try_get_rnd(obj);
    if (!rnd) {
	VALUE v = rb_funcall2(obj, id_rand, 0, 0);
	double d = NUM2DBL(v);
	if (d < 0.0) {
	    rb_raise(rb_eRangeError, "random number too small %g", d);
	}
	else if (d >= 1.0) {
	    rb_raise(rb_eRangeError, "random number too big %g", d);
	}
	return d;
    }
    return genrand_real(&rnd->mt);
}

static inline VALUE
ulong_to_num_plus_1(unsigned long n)
{
#if HAVE_LONG_LONG
    return ULL2NUM((LONG_LONG)n+1);
#else
    if (n >= ULONG_MAX) {
	return rb_big_plus(ULONG2NUM(n), INT2FIX(1));
    }
    return ULONG2NUM(n+1);
#endif
}

unsigned long
rb_random_ulong_limited(VALUE obj, unsigned long limit)
{
    rb_random_t *rnd = try_get_rnd(obj);
    if (!rnd) {
	extern int rb_num_negative_p(VALUE);
	VALUE lim = ulong_to_num_plus_1(limit);
	VALUE v = rb_to_int(rb_funcall2(obj, id_rand, 1, &lim));
	unsigned long r = NUM2ULONG(v);
	if (rb_num_negative_p(v)) {
	    rb_raise(rb_eRangeError, "random number too small %ld", r);
	}
	if (r > limit) {
	    rb_raise(rb_eRangeError, "random number too big %ld", r);
	}
	return r;
    }
    return limited_rand(&rnd->mt, limit);
}

/*
 * call-seq: prng.bytes(size) -> a_string
 *
 * Returns a random binary string containing +size+ bytes.
 *
 *   random_string = Random.new.bytes(10) # => "\xD7:R\xAB?\x83\xCE\xFAkO"
 *   random_string.size                   # => 10
 */
static VALUE
random_bytes(VALUE obj, VALUE len)
{
    return rb_random_bytes(obj, NUM2LONG(rb_to_int(len)));
}

VALUE
rb_random_bytes(VALUE obj, long n)
{
    rb_random_t *rnd = try_get_rnd(obj);
    VALUE bytes;
    char *ptr;
    unsigned int r, i;

    if (!rnd) {
	VALUE len = LONG2NUM(n);
	return rb_funcall2(obj, id_bytes, 1, &len);
    }
    bytes = rb_str_new(0, n);
    ptr = RSTRING_PTR(bytes);
    for (; n >= SIZEOF_INT32; n -= SIZEOF_INT32) {
	r = genrand_int32(&rnd->mt);
	i = SIZEOF_INT32;
	do {
	    *ptr++ = (char)r;
	    r >>= CHAR_BIT;
        } while (--i);
    }
    if (n > 0) {
	r = genrand_int32(&rnd->mt);
	do {
	    *ptr++ = (char)r;
	    r >>= CHAR_BIT;
	} while (--n);
    }
    return bytes;
}

static VALUE
range_values(VALUE vmax, VALUE *begp, VALUE *endp, int *exclp)
{
    VALUE end, r;

    if (!rb_range_values(vmax, begp, &end, exclp)) return Qfalse;
    if (endp) *endp = end;
    if (!rb_respond_to(end, id_minus)) return Qfalse;
    r = rb_funcall2(end, id_minus, 1, begp);
    if (NIL_P(r)) return Qfalse;
    return r;
}

static VALUE
rand_int(struct MT *mt, VALUE vmax, int restrictive)
{
    /* mt must be initialized */
    long max;
    unsigned long r;

    if (FIXNUM_P(vmax)) {
	max = FIX2LONG(vmax);
	if (!max) return Qnil;
	if (max < 0) {
	    if (restrictive) return Qnil;
	    max = -max;
	}
	r = limited_rand(mt, (unsigned long)max - 1);
	return ULONG2NUM(r);
    }
    else {
	VALUE ret;
	if (rb_bigzero_p(vmax)) return Qnil;
	if (!RBIGNUM_SIGN(vmax)) {
	    if (restrictive) return Qnil;
            vmax = rb_big_uminus(vmax);
	}
	vmax = rb_big_minus(vmax, INT2FIX(1));
	if (FIXNUM_P(vmax)) {
	    max = FIX2LONG(vmax);
	    if (max == -1) return Qnil;
	    r = limited_rand(mt, max);
	    return LONG2NUM(r);
	}
	ret = limited_big_rand(mt, vmax);
	RB_GC_GUARD(vmax);
	return ret;
    }
}

static inline double
float_value(VALUE v)
{
    double x = RFLOAT_VALUE(v);
    if (isinf(x) || isnan(x)) {
	VALUE error = INT2FIX(EDOM);
	rb_exc_raise(rb_class_new_instance(1, &error, rb_eSystemCallError));
    }
    return x;
}

static inline VALUE
rand_range(struct MT* mt, VALUE range)
{
    VALUE beg = Qundef, end = Qundef, vmax, v;
    int excl = 0;

    if ((v = vmax = range_values(range, &beg, &end, &excl)) == Qfalse)
	return Qfalse;
    if (!RB_TYPE_P(vmax, T_FLOAT) && (v = rb_check_to_integer(vmax, "to_int"), !NIL_P(v))) {
	long max;
	vmax = v;
	v = Qnil;
	if (FIXNUM_P(vmax)) {
	  fixnum:
	    if ((max = FIX2LONG(vmax) - excl) >= 0) {
		unsigned long r = limited_rand(mt, (unsigned long)max);
		v = ULONG2NUM(r);
	    }
	}
	else if (BUILTIN_TYPE(vmax) == T_BIGNUM && RBIGNUM_SIGN(vmax) && !rb_bigzero_p(vmax)) {
	    vmax = excl ? rb_big_minus(vmax, INT2FIX(1)) : rb_big_norm(vmax);
	    if (FIXNUM_P(vmax)) {
		excl = 0;
		goto fixnum;
	    }
	    v = limited_big_rand(mt, vmax);
	}
    }
    else if (v = rb_check_to_float(vmax), !NIL_P(v)) {
	int scale = 1;
	double max = RFLOAT_VALUE(v), mid = 0.5, r;
	if (isinf(max)) {
	    double min = float_value(rb_to_float(beg)) / 2.0;
	    max = float_value(rb_to_float(end)) / 2.0;
	    scale = 2;
	    mid = max + min;
	    max -= min;
	}
	else {
	    float_value(v);
	}
	v = Qnil;
	if (max > 0.0) {
	    if (excl) {
		r = genrand_real(mt);
	    }
	    else {
		r = genrand_real2(mt);
	    }
	    if (scale > 1) {
		return rb_float_new(+(+(+(r - 0.5) * max) * scale) + mid);
	    }
	    v = rb_float_new(r * max);
	}
	else if (max == 0.0 && !excl) {
	    v = rb_float_new(0.0);
	}
    }

    if (FIXNUM_P(beg) && FIXNUM_P(v)) {
	long x = FIX2LONG(beg) + FIX2LONG(v);
	return LONG2NUM(x);
    }
    switch (TYPE(v)) {
      case T_NIL:
	break;
      case T_BIGNUM:
	return rb_big_plus(v, beg);
      case T_FLOAT: {
	VALUE f = rb_check_to_float(beg);
	if (!NIL_P(f)) {
	    return DBL2NUM(RFLOAT_VALUE(v) + RFLOAT_VALUE(f));
	}
      }
      default:
	return rb_funcall2(beg, id_plus, 1, &v);
    }

    return v;
}

static VALUE rand_random(int argc, VALUE *argv, rb_random_t *rnd);

/*
 * call-seq:
 *   prng.rand -> float
 *   prng.rand(max) -> number
 *
 * When +max+ is an Integer, +rand+ returns a random integer greater than
 * or equal to zero and less than +max+. Unlike Kernel.rand, when +max+
 * is a negative integer or zero, +rand+ raises an ArgumentError.
 *
 *   prng = Random.new
 *   prng.rand(100)       # => 42
 *
 * When +max+ is a Float, +rand+ returns a random floating point number
 * between 0.0 and +max+, including 0.0 and excluding +max+.
 *
 *   prng.rand(1.5)       # => 1.4600282860034115
 *
 * When +max+ is a Range, +rand+ returns a random number where
 * range.member?(number) == true.
 *
 *   prng.rand(5..9)      # => one of [5, 6, 7, 8, 9]
 *   prng.rand(5...9)     # => one of [5, 6, 7, 8]
 *   prng.rand(5.0..9.0)  # => between 5.0 and 9.0, including 9.0
 *   prng.rand(5.0...9.0) # => between 5.0 and 9.0, excluding 9.0
 *
 * Both the beginning and ending values of the range must respond to subtract
 * (<tt>-</tt>) and add (<tt>+</tt>)methods, or rand will raise an
 * ArgumentError.
 */
static VALUE
random_rand(int argc, VALUE *argv, VALUE obj)
{
    return rand_random(argc, argv, get_rnd(obj));
}

static VALUE
rand_random(int argc, VALUE *argv, rb_random_t *rnd)
{
    VALUE vmax, v;

    if (argc == 0) {
	return rb_float_new(genrand_real(&rnd->mt));
    }
    else {
	rb_check_arity(argc, 0, 1);
    }
    vmax = argv[0];
    if (NIL_P(vmax)) {
	v = Qnil;
    }
    else if (!RB_TYPE_P(vmax, T_FLOAT) && (v = rb_check_to_integer(vmax, "to_int"), !NIL_P(v))) {
	v = rand_int(&rnd->mt, v, 1);
    }
    else if (v = rb_check_to_float(vmax), !NIL_P(v)) {
	double max = float_value(v);
	if (max > 0.0)
	    v = rb_float_new(max * genrand_real(&rnd->mt));
	else
	    v = Qnil;
    }
    else if ((v = rand_range(&rnd->mt, vmax)) != Qfalse) {
	/* nothing to do */
    }
    else {
	v = Qnil;
	(void)NUM2LONG(vmax);
    }
    if (NIL_P(v)) {
	VALUE mesg = rb_str_new_cstr("invalid argument - ");
	rb_str_append(mesg, rb_obj_as_string(argv[0]));
	rb_exc_raise(rb_exc_new3(rb_eArgError, mesg));
    }

    return v;
}

/*
 * call-seq:
 *   prng1 == prng2 -> true or false
 *
 * Returns true if the two generators have the same internal state, otherwise
 * false.  Equivalent generators will return the same sequence of
 * pseudo-random numbers.  Two generators will generally have the same state
 * only if they were initialized with the same seed
 *
 *   Random.new == Random.new             # => false
 *   Random.new(1234) == Random.new(1234) # => true
 *
 * and have the same invocation history.
 *
 *   prng1 = Random.new(1234)
 *   prng2 = Random.new(1234)
 *   prng1 == prng2 # => true
 *
 *   prng1.rand     # => 0.1915194503788923
 *   prng1 == prng2 # => false
 *
 *   prng2.rand     # => 0.1915194503788923
 *   prng1 == prng2 # => true
 */
static VALUE
random_equal(VALUE self, VALUE other)
{
    rb_random_t *r1, *r2;
    if (rb_obj_class(self) != rb_obj_class(other)) return Qfalse;
    r1 = get_rnd(self);
    r2 = get_rnd(other);
    if (!RTEST(rb_funcall2(r1->seed, rb_intern("=="), 1, &r2->seed))) return Qfalse;
    if (memcmp(r1->mt.state, r2->mt.state, sizeof(r1->mt.state))) return Qfalse;
    if ((r1->mt.next - r1->mt.state) != (r2->mt.next - r2->mt.state)) return Qfalse;
    if (r1->mt.left != r2->mt.left) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *   rand(max=0)    -> number
 *
 * If called without an argument, or if <tt>max.to_i.abs == 0</tt>, rand
 * returns a pseudo-random floating point number between 0.0 and 1.0,
 * including 0.0 and excluding 1.0.
 *
 *   rand        #=> 0.2725926052826416
 *
 * When +max.abs+ is greater than or equal to 1, +rand+ returns a pseudo-random
 * integer greater than or equal to 0 and less than +max.to_i.abs+.
 *
 *   rand(100)   #=> 12
 *
 * When +max+ is a Range, +rand+ returns a random number where
 * range.member?(number) == true.
 *
 * Negative or floating point values for +max+ are allowed, but may give
 * surprising results.
 *
 *   rand(-100) # => 87
 *   rand(-0.5) # => 0.8130921818028143
 *   rand(1.9)  # equivalent to rand(1), which is always 0
 *
 * Kernel.srand may be used to ensure that sequences of random numbers are
 * reproducible between different runs of a program.
 *
 * See also Random.rand.
 */

static VALUE
rb_f_rand(int argc, VALUE *argv, VALUE obj)
{
    VALUE v, vmax, r;
    struct MT *mt = default_mt();

    if (argc == 0) goto zero_arg;
    rb_scan_args(argc, argv, "01", &vmax);
    if (NIL_P(vmax)) goto zero_arg;
    if ((v = rand_range(mt, vmax)) != Qfalse) {
	return v;
    }
    vmax = rb_to_int(vmax);
    if (vmax == INT2FIX(0) || NIL_P(r = rand_int(mt, vmax, 0))) {
      zero_arg:
	return DBL2NUM(genrand_real(mt));
    }
    return r;
}

/*
 * call-seq:
 *   Random.rand -> float
 *   Random.rand(max) -> number
 *
 * Alias of Random::DEFAULT.rand.
 */

static VALUE
random_s_rand(int argc, VALUE *argv, VALUE obj)
{
    return rand_random(argc, argv, rand_start(&default_rand));
}

#define SIP_HASH_STREAMING 0
#define sip_hash24 ruby_sip_hash24
#if !defined _WIN32 && !defined BYTE_ORDER
# ifdef WORDS_BIGENDIAN
#   define BYTE_ORDER BIG_ENDIAN
# else
#   define BYTE_ORDER LITTLE_ENDIAN
# endif
# ifndef LITTLE_ENDIAN
#   define LITTLE_ENDIAN 1234
# endif
# ifndef BIG_ENDIAN
#   define BIG_ENDIAN    4321
# endif
#endif
#include "siphash.c"

static st_index_t hashseed;
static union {
    uint8_t key[16];
    uint32_t u32[(16 * sizeof(uint8_t) - 1) / sizeof(uint32_t)];
} sipseed;

static VALUE
init_randomseed(struct MT *mt, uint32_t initial[DEFAULT_SEED_CNT])
{
    VALUE seed;
    fill_random_seed(initial);
    init_by_array(mt, initial, DEFAULT_SEED_CNT);
    seed = make_seed_value(initial);
    memset(initial, 0, DEFAULT_SEED_LEN);
    return seed;
}

void
Init_RandomSeed(void)
{
    rb_random_t *r = &default_rand;
    uint32_t initial[DEFAULT_SEED_CNT];
    struct MT *mt = &r->mt;
    VALUE seed = init_randomseed(mt, initial);
    int i;

    hashseed = genrand_int32(mt);
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 4*8
    hashseed <<= 32;
    hashseed |= genrand_int32(mt);
#endif
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 8*8
    hashseed <<= 32;
    hashseed |= genrand_int32(mt);
#endif
#if SIZEOF_ST_INDEX_T*CHAR_BIT > 12*8
    hashseed <<= 32;
    hashseed |= genrand_int32(mt);
#endif

    for (i = 0; i < numberof(sipseed.u32); ++i)
	sipseed.u32[i] = genrand_int32(mt);

    rb_global_variable(&r->seed);
    r->seed = seed;
}

st_index_t
rb_hash_start(st_index_t h)
{
    return st_hash_start(hashseed + h);
}

st_index_t
rb_memhash(const void *ptr, long len)
{
    sip_uint64_t h = sip_hash24(sipseed.key, ptr, len);
#ifdef HAVE_UINT64_T
    return (st_index_t)h;
#else
    return (st_index_t)(h.u32[0] ^ h.u32[1]);
#endif
}

static void
Init_RandomSeed2(void)
{
    VALUE seed = default_rand.seed;

    if (RB_TYPE_P(seed, T_BIGNUM)) {
	rb_obj_reveal(seed, rb_cBignum);
    }
}

void
rb_reset_random_seed(void)
{
    rb_random_t *r = &default_rand;
    uninit_genrand(&r->mt);
    r->seed = INT2FIX(0);
}

/*
 * Document-class: Random
 *
 * Random provides an interface to Ruby's pseudo-random number generator, or
 * PRNG.  The PRNG produces a deterministic sequence of bits which approximate
 * true randomness. The sequence may be represented by integers, floats, or
 * binary strings.
 *
 * The generator may be initialized with either a system-generated or
 * user-supplied seed value by using Random.srand.
 *
 * The class method Random.rand provides the base functionality of Kernel.rand
 * along with better handling of floating point values. These are both
 * interfaces to Random::DEFAULT, the Ruby system PRNG.
 *
 * Random.new will create a new PRNG with a state independent of
 * Random::DEFAULT, allowing multiple generators with different seed values or
 * sequence positions to exist simultaneously. Random objects can be
 * marshaled, allowing sequences to be saved and resumed.
 *
 * PRNGs are currently implemented as a modified Mersenne Twister with a period
 * of 2**19937-1.
 */

void
Init_Random(void)
{
    Init_RandomSeed2();
    rb_define_global_function("srand", rb_f_srand, -1);
    rb_define_global_function("rand", rb_f_rand, -1);

    rb_cRandom = rb_define_class("Random", rb_cObject);
    rb_define_alloc_func(rb_cRandom, random_alloc);
    rb_define_method(rb_cRandom, "initialize", random_init, -1);
    rb_define_method(rb_cRandom, "rand", random_rand, -1);
    rb_define_method(rb_cRandom, "bytes", random_bytes, 1);
    rb_define_method(rb_cRandom, "seed", random_get_seed, 0);
    rb_define_method(rb_cRandom, "initialize_copy", random_copy, 1);
    rb_define_private_method(rb_cRandom, "marshal_dump", random_dump, 0);
    rb_define_private_method(rb_cRandom, "marshal_load", random_load, 1);
    rb_define_private_method(rb_cRandom, "state", random_state, 0);
    rb_define_private_method(rb_cRandom, "left", random_left, 0);
    rb_define_method(rb_cRandom, "==", random_equal, 1);

    {
	VALUE rand_default = TypedData_Wrap_Struct(rb_cRandom, &random_data_type, &default_rand);
	rb_gc_register_mark_object(rand_default);
	/* Direct access to Ruby's Pseudorandom number generator (PRNG). */
	rb_define_const(rb_cRandom, "DEFAULT", rand_default);
    }

    rb_define_singleton_method(rb_cRandom, "srand", rb_f_srand, -1);
    rb_define_singleton_method(rb_cRandom, "rand", random_s_rand, -1);
    rb_define_singleton_method(rb_cRandom, "new_seed", random_seed, 0);
    rb_define_private_method(CLASS_OF(rb_cRandom), "state", random_s_state, 0);
    rb_define_private_method(CLASS_OF(rb_cRandom), "left", random_s_left, 0);

    id_rand = rb_intern("rand");
    id_bytes = rb_intern("bytes");
}
