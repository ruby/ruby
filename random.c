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

#ifdef HAVE_SYSCALL_H
#include <syscall.h>
#elif defined HAVE_SYS_SYSCALL_H
#include <sys/syscall.h>
#endif

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#endif
#include "ruby_atomic.h"

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
    uint32_t state[N]; /* the array for the state vector  */
    uint32_t *next;
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
init_by_array(struct MT *mt, uint32_t init_key[], int key_length)
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
    uint32_t *p = mt->state;
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
static double int_pair_to_real_exclusive(uint32_t a, uint32_t b);
static double
genrand_real(struct MT *mt)
{
    /* mt must be initialized */
    unsigned int a = genrand_int32(mt), b = genrand_int32(mt);
    return int_pair_to_real_exclusive(a, b);
}

static double
int_pair_to_real_exclusive(uint32_t a, uint32_t b)
{
    a >>= 5;
    b >>= 6;
    return(a*67108864.0+b)*(1.0/9007199254740992.0);
}

/* generates a random number on [0,1] with 53-bit resolution*/
static double int_pair_to_real_inclusive(uint32_t a, uint32_t b);
#if 0
static double
genrand_real2(struct MT *mt)
{
    /* mt must be initialized */
    uint32_t a = genrand_int32(mt), b = genrand_int32(mt);
    return int_pair_to_real_inclusive(a, b);
}
#endif

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
    return sizeof(rb_random_t);
}

static const rb_data_type_t random_data_type = {
    "random",
    {
	random_mark,
	random_free,
	random_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
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
rand_init(struct MT *mt, VALUE seed)
{
    uint32_t buf0[SIZEOF_LONG / SIZEOF_INT32 * 4], *buf = buf0;
    size_t len;
    int sign;

    seed = rb_to_int(seed);

    len = rb_absint_numwords(seed, 32, NULL);
    if (len > numberof(buf0))
        buf = ALLOC_N(uint32_t, len);
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

    if (rb_check_arity(argc, 0, 1) == 0) {
	rb_check_frozen(obj);
	vseed = random_seed();
    }
    else {
	vseed = argv[0];
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

#if USE_DEV_URANDOM
static int
fill_random_bytes_urandom(void *seed, size_t size)
{
    /*
      O_NONBLOCK and O_NOCTTY is meaningless if /dev/urandom correctly points
      to a urandom device. But it protects from several strange hazard if
      /dev/urandom is not a urandom device.
    */
    int fd = rb_cloexec_open("/dev/urandom",
# ifdef O_NONBLOCK
			     O_NONBLOCK|
# endif
# ifdef O_NOCTTY
			     O_NOCTTY|
# endif
			     O_RDONLY, 0);
    struct stat statbuf;
    ssize_t ret = 0;

    if (fd < 0) return -1;
    rb_update_max_fd(fd);
    if (fstat(fd, &statbuf) == 0 && S_ISCHR(statbuf.st_mode)) {
	ret = read(fd, seed, size);
    }
    close(fd);
    if (ret < 0 || (size_t)ret < size) return -1;
    return 0;
}
#else
# define fill_random_bytes_urandom(seed, size) -1
#endif

#if 0
#elif defined(HAVE_ARC4RANDOM_BUF)
static int
fill_random_bytes_syscall(void *buf, size_t size, int unused)
{
    arc4random_buf(buf, size);
    return 0;
}
#elif defined(_WIN32)
static void
release_crypt(void *p)
{
    HCRYPTPROV prov = (HCRYPTPROV)ATOMIC_PTR_EXCHANGE(*(HCRYPTPROV *)p, INVALID_HANDLE_VALUE);
    if (prov && prov != (HCRYPTPROV)INVALID_HANDLE_VALUE) {
	CryptReleaseContext(prov, 0);
    }
}

static int
fill_random_bytes_syscall(void *seed, size_t size, int unused)
{
    static HCRYPTPROV perm_prov;
    HCRYPTPROV prov = perm_prov, old_prov;
    if (!prov) {
	if (!CryptAcquireContext(&prov, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT)) {
	    prov = (HCRYPTPROV)INVALID_HANDLE_VALUE;
	}
	old_prov = (HCRYPTPROV)ATOMIC_PTR_CAS(perm_prov, 0, prov);
	if (LIKELY(!old_prov)) { /* no other threads acquried */
	    if (prov != (HCRYPTPROV)INVALID_HANDLE_VALUE) {
		rb_gc_register_mark_object(Data_Wrap_Struct(0, 0, release_crypt, &perm_prov));
	    }
	}
	else {			/* another thread acquried */
	    if (prov != (HCRYPTPROV)INVALID_HANDLE_VALUE) {
		CryptReleaseContext(prov, 0);
	    }
	    prov = old_prov;
	}
    }
    if (prov == (HCRYPTPROV)INVALID_HANDLE_VALUE) return -1;
    CryptGenRandom(prov, size, seed);
    return 0;
}
#elif defined __linux__ && defined SYS_getrandom
#include <linux/random.h>

# ifndef GRND_NONBLOCK
#   define GRND_NONBLOCK 0x0001	/* not defined in musl libc */
# endif

static int
fill_random_bytes_syscall(void *seed, size_t size, int need_secure)
{
    static rb_atomic_t try_syscall = 1;
    if (try_syscall) {
	long ret;
	int flags = 0;
	if (!need_secure)
	    flags = GRND_NONBLOCK;
	errno = 0;
	ret = syscall(SYS_getrandom, seed, size, flags);
	if (errno == ENOSYS) {
	    ATOMIC_SET(try_syscall, 0);
	    return -1;
	}
	if ((size_t)ret == size) return 0;
    }
    return -1;
}
#else
# define fill_random_bytes_syscall(seed, size, need_secure) -1
#endif

static int
fill_random_bytes(void *seed, size_t size, int need_secure)
{
    int ret = fill_random_bytes_syscall(seed, size, need_secure);
    if (ret == 0) return ret;
    return fill_random_bytes_urandom(seed, size);
}

static void
fill_random_seed(uint32_t seed[DEFAULT_SEED_CNT])
{
    static int n = 0;
    struct timeval tv;

    memset(seed, 0, DEFAULT_SEED_LEN);

    fill_random_bytes(seed, DEFAULT_SEED_LEN, TRUE);

    gettimeofday(&tv, 0);
    seed[0] ^= tv.tv_usec;
    seed[1] ^= (uint32_t)tv.tv_sec;
#if SIZEOF_TIME_T > SIZEOF_INT
    seed[0] ^= (uint32_t)((time_t)tv.tv_sec >> SIZEOF_INT * CHAR_BIT);
#endif
    seed[2] ^= getpid() ^ (n++ << 16);
    seed[3] ^= (uint32_t)(VALUE)&seed;
#if SIZEOF_VOIDP > SIZEOF_INT
    seed[2] ^= (uint32_t)((VALUE)&seed >> SIZEOF_INT * CHAR_BIT);
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
 * call-seq: Random.raw_seed(size) -> string
 *
 * Returns a raw seed string, using platform providing features.
 *
 *   Random.raw_seed(8)  #=> "\x78\x41\xBA\xAF\x7D\xEA\xD8\xEA"
 */
static VALUE
random_raw_seed(VALUE self, VALUE size)
{
    long n = NUM2ULONG(size);
    VALUE buf = rb_str_new(0, n);
    if (n == 0) return buf;
    if (fill_random_bytes(RSTRING_PTR(buf), n, FALSE)) return Qnil;
    return buf;
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

    if (rb_check_arity(argc, 0, 1) == 0) {
	seed = random_seed();
    }
    else {
	seed = argv[0];
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
    unsigned long val, mask;

    if (!limit) return 0;
    mask = make_mask(limit);

#if 4 < SIZEOF_LONG
    if (0xffffffff < limit) {
        int i;
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
#endif

    do {
        val = genrand_int32(mt) & mask;
    } while (limit < val);
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

static unsigned int
random_int32(VALUE obj, rb_random_t *rnd)
{
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

unsigned int
rb_random_int32(VALUE obj)
{
    return random_int32(obj, try_get_rnd(obj));
}

static double
random_real(VALUE obj, rb_random_t *rnd, int excl)
{
    uint32_t a = random_int32(obj, rnd);
    uint32_t b = random_int32(obj, rnd);
    if (excl) {
	return int_pair_to_real_exclusive(a, b);
    }
    else {
	return int_pair_to_real_inclusive(a, b);
    }
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

static unsigned long
random_ulong_limited(VALUE obj, rb_random_t *rnd, unsigned long limit)
{
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

static VALUE
random_ulong_limited_big(VALUE obj, rb_random_t *rnd, VALUE vmax)
{
    if (!rnd) {
	extern int rb_num_negative_p(VALUE);
	VALUE lim = rb_big_plus(vmax, INT2FIX(1));
	VALUE v = rb_to_int(rb_funcall2(obj, id_rand, 1, &lim));
	if (rb_num_negative_p(v)) {
	    rb_raise(rb_eRangeError, "random number too small %"PRIsVALUE, v);
	}
	if (FIX2LONG(rb_big_cmp(vmax, v)) < 0) {
	    rb_raise(rb_eRangeError, "random number too big %"PRIsVALUE, v);
	}
	return v;
    }
    return limited_big_rand(&rnd->mt, vmax);
}

unsigned long
rb_random_ulong_limited(VALUE obj, unsigned long limit)
{
    return random_ulong_limited(obj, try_get_rnd(obj), limit);
}

static VALUE genrand_bytes(rb_random_t *rnd, long n);

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
    return genrand_bytes(get_rnd(obj), NUM2LONG(rb_to_int(len)));
}

static VALUE
genrand_bytes(rb_random_t *rnd, long n)
{
    VALUE bytes;
    char *ptr;
    unsigned int r, i;

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

VALUE
rb_random_bytes(VALUE obj, long n)
{
    rb_random_t *rnd = try_get_rnd(obj);
    if (!rnd) {
	VALUE len = LONG2NUM(n);
	return rb_funcall2(obj, id_bytes, 1, &len);
    }
    return genrand_bytes(rnd, n);
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
rand_int(VALUE obj, rb_random_t *rnd, VALUE vmax, int restrictive)
{
    /* mt must be initialized */
    unsigned long r;

    if (FIXNUM_P(vmax)) {
	long max = FIX2LONG(vmax);
	if (!max) return Qnil;
	if (max < 0) {
	    if (restrictive) return Qnil;
	    max = -max;
	}
	r = random_ulong_limited(obj, rnd, (unsigned long)max - 1);
	return ULONG2NUM(r);
    }
    else {
	VALUE ret;
	if (rb_bigzero_p(vmax)) return Qnil;
	if (!BIGNUM_SIGN(vmax)) {
	    if (restrictive) return Qnil;
            vmax = rb_big_uminus(vmax);
	}
	vmax = rb_big_minus(vmax, INT2FIX(1));
	if (FIXNUM_P(vmax)) {
	    long max = FIX2LONG(vmax);
	    if (max == -1) return Qnil;
	    r = random_ulong_limited(obj, rnd, max);
	    return LONG2NUM(r);
	}
	ret = random_ulong_limited_big(obj, rnd, vmax);
	RB_GC_GUARD(vmax);
	return ret;
    }
}

NORETURN(static void domain_error(void));
static void
domain_error(void)
{
    VALUE error = INT2FIX(EDOM);
    rb_exc_raise(rb_class_new_instance(1, &error, rb_eSystemCallError));
}

NORETURN(static void invalid_argument(VALUE));
static void
invalid_argument(VALUE arg0)
{
    rb_raise(rb_eArgError, "invalid argument - %"PRIsVALUE, arg0);
}

static VALUE
check_random_number(VALUE v, const VALUE *argv)
{
    switch (v) {
      case Qfalse:
	(void)NUM2LONG(argv[0]);
	break;
      case Qnil:
	invalid_argument(argv[0]);
    }
    return v;
}

static inline double
float_value(VALUE v)
{
    double x = RFLOAT_VALUE(v);
    if (isinf(x) || isnan(x)) {
	domain_error();
    }
    return x;
}

static inline VALUE
rand_range(VALUE obj, rb_random_t* rnd, VALUE range)
{
    VALUE beg = Qundef, end = Qundef, vmax, v;
    int excl = 0;

    if ((v = vmax = range_values(range, &beg, &end, &excl)) == Qfalse)
	return Qfalse;
    if (!RB_TYPE_P(vmax, T_FLOAT) && (v = rb_check_to_int(vmax), !NIL_P(v))) {
	long max;
	vmax = v;
	v = Qnil;
	if (FIXNUM_P(vmax)) {
	  fixnum:
	    if ((max = FIX2LONG(vmax) - excl) >= 0) {
		unsigned long r = random_ulong_limited(obj, rnd, (unsigned long)max);
		v = ULONG2NUM(r);
	    }
	}
	else if (BUILTIN_TYPE(vmax) == T_BIGNUM && BIGNUM_SIGN(vmax) && !rb_bigzero_p(vmax)) {
	    vmax = excl ? rb_big_minus(vmax, INT2FIX(1)) : rb_big_norm(vmax);
	    if (FIXNUM_P(vmax)) {
		excl = 0;
		goto fixnum;
	    }
	    v = random_ulong_limited_big(obj, rnd, vmax);
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
	else if (isnan(max)) {
	    domain_error();
	}
	v = Qnil;
	if (max > 0.0) {
	    r = random_real(obj, rnd, excl);
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

static VALUE rand_random(int argc, VALUE *argv, VALUE obj, rb_random_t *rnd);

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
    VALUE v = rand_random(argc, argv, obj, get_rnd(obj));
    check_random_number(v, argv);
    return v;
}

static VALUE
rand_random(int argc, VALUE *argv, VALUE obj, rb_random_t *rnd)
{
    VALUE vmax, v;

    if (rb_check_arity(argc, 0, 1) == 0) {
	return rb_float_new(random_real(obj, rnd, TRUE));
    }
    vmax = argv[0];
    if (NIL_P(vmax)) return Qnil;
    if (!RB_TYPE_P(vmax, T_FLOAT)) {
	v = rb_check_to_int(vmax);
	if (!NIL_P(v)) return rand_int(obj, rnd, v, 1);
    }
    v = rb_check_to_float(vmax);
    if (!NIL_P(v)) {
	const double max = float_value(v);
	if (max < 0.0) {
	    return Qnil;
	}
	else {
	    double r = random_real(obj, rnd, TRUE);
	    if (max > 0.0) r *= max;
	    return rb_float_new(r);
	}
    }
    return rand_range(obj, rnd, vmax);
}

static VALUE
rand_random_number(int argc, VALUE *argv, VALUE obj)
{
    rb_random_t *rnd = try_get_rnd(obj);
    VALUE v = rand_random(argc, argv, obj, rnd);
    if (NIL_P(v)) v = rand_random(0, 0, obj, rnd);
    else if (!v) invalid_argument(argv[0]);
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
    VALUE vmax;
    rb_random_t *rnd = rand_start(&default_rand);

    if (rb_check_arity(argc, 0, 1) && !NIL_P(vmax = argv[0])) {
	VALUE v = rand_range(Qnil, rnd, vmax);
	if (v != Qfalse) return v;
	vmax = rb_to_int(vmax);
	if (vmax != INT2FIX(0)) {
	    v = rand_int(Qnil, rnd, vmax, 0);
	    if (!NIL_P(v)) return v;
	}
    }
    return DBL2NUM(genrand_real(&rnd->mt));
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
    VALUE v = rand_random(argc, argv, Qnil, rand_start(&default_rand));
    check_random_number(v, argv);
    return v;
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
typedef uint8_t sipseed_keys_t[16];
static union {
    sipseed_keys_t key;
    uint32_t u32[type_roomof(sipseed_keys_t, uint32_t)];
} sipseed;

static void
init_hashseed(struct MT *mt)
{
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
}

static void
init_siphash(struct MT *mt)
{
    int i;

    for (i = 0; i < numberof(sipseed.u32); ++i)
	sipseed.u32[i] = genrand_int32(mt);
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

/* Initialize Ruby internal seeds. This function is called at very early stage
 * of Ruby startup. Thus, you can't use Ruby's object. */
void
Init_RandomSeedCore(void)
{
    /*
      Don't reuse this MT for Random::DEFAULT. Random::DEFAULT::seed shouldn't
      provide a hint that an attacker guess siphash's seed.
    */
    struct MT mt;
    uint32_t initial_seed[DEFAULT_SEED_CNT];

    fill_random_seed(initial_seed);
    init_by_array(&mt, initial_seed, DEFAULT_SEED_CNT);

    init_hashseed(&mt);
    init_siphash(&mt);

    explicit_bzero(initial_seed, DEFAULT_SEED_LEN);
}

static VALUE
init_randomseed(struct MT *mt)
{
    uint32_t initial[DEFAULT_SEED_CNT];
    VALUE seed;

    fill_random_seed(initial);
    init_by_array(mt, initial, DEFAULT_SEED_CNT);
    seed = make_seed_value(initial);
    explicit_bzero(initial, DEFAULT_SEED_LEN);
    return seed;
}

/* construct Random::DEFAULT bits */
static VALUE
Init_Random_default(void)
{
    rb_random_t *r = &default_rand;
    struct MT *mt = &r->mt;
    VALUE v = TypedData_Wrap_Struct(rb_cRandom, &random_data_type, r);

    rb_gc_register_mark_object(v);
    r->seed = init_randomseed(mt);

    return v;
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
InitVM_Random(void)
{
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
	/* Direct access to Ruby's Pseudorandom number generator (PRNG). */
	VALUE rand_default = Init_Random_default();
	rb_define_const(rb_cRandom, "DEFAULT", rand_default);
    }

    rb_define_singleton_method(rb_cRandom, "srand", rb_f_srand, -1);
    rb_define_singleton_method(rb_cRandom, "rand", random_s_rand, -1);
    rb_define_singleton_method(rb_cRandom, "new_seed", random_seed, 0);
    rb_define_singleton_method(rb_cRandom, "raw_seed", random_raw_seed, 1);
    rb_define_private_method(CLASS_OF(rb_cRandom), "state", random_s_state, 0);
    rb_define_private_method(CLASS_OF(rb_cRandom), "left", random_s_left, 0);

    {
	VALUE m = rb_define_module_under(rb_cRandom, "Formatter");
	rb_include_module(rb_cRandom, m);
	rb_define_method(m, "random_number", rand_random_number, -1);
    }
}

#undef rb_intern
void
Init_Random(void)
{
    id_rand = rb_intern("rand");
    id_bytes = rb_intern("bytes");

    InitVM(Random);
}
