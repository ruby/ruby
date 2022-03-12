/**********************************************************************

  random.c -

  $Author$
  created at: Fri Dec 24 16:39:21 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/internal/config.h"

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <float.h>
#include <time.h>

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_FCNTL_H
# include <fcntl.h>
#endif

#if defined(HAVE_SYS_TIME_H)
# include <sys/time.h>
#endif

#ifdef HAVE_SYSCALL_H
# include <syscall.h>
#elif defined HAVE_SYS_SYSCALL_H
# include <sys/syscall.h>
#endif

#ifdef _WIN32
# include <winsock2.h>
# include <windows.h>
# include <wincrypt.h>
#endif

#ifdef __OpenBSD__
/* to define OpenBSD for version check */
# include <sys/param.h>
#endif

#if defined HAVE_GETRANDOM
# include <sys/random.h>
#elif defined __linux__ && defined __NR_getrandom
# include <linux/random.h>
#endif

#if defined __APPLE__
# include <AvailabilityMacros.h>
#endif

#include "internal.h"
#include "internal/array.h"
#include "internal/compilers.h"
#include "internal/numeric.h"
#include "internal/random.h"
#include "internal/sanitizers.h"
#include "internal/variable.h"
#include "ruby_atomic.h"
#include "ruby/random.h"
#include "ruby/ractor.h"

typedef int int_must_be_32bit_at_least[sizeof(int) * CHAR_BIT < 32 ? -1 : 1];

#include "missing/mt19937.c"

/* generates a random number on [0,1) with 53-bit resolution*/
static double int_pair_to_real_exclusive(uint32_t a, uint32_t b);
static double
genrand_real(struct MT *mt)
{
    /* mt must be initialized */
    unsigned int a = genrand_int32(mt), b = genrand_int32(mt);
    return int_pair_to_real_exclusive(a, b);
}

static const double dbl_reduce_scale = /* 2**(-DBL_MANT_DIG) */
    (1.0
     / (double)(DBL_MANT_DIG > 2*31 ? (1ul<<31) : 1.0)
     / (double)(DBL_MANT_DIG > 1*31 ? (1ul<<31) : 1.0)
     / (double)(1ul<<(DBL_MANT_DIG%31)));

static double
int_pair_to_real_exclusive(uint32_t a, uint32_t b)
{
    static const int a_shift = DBL_MANT_DIG < 64 ?
        (64-DBL_MANT_DIG)/2 : 0;
    static const int b_shift = DBL_MANT_DIG < 64 ?
        (65-DBL_MANT_DIG)/2 : 0;
    a >>= a_shift;
    b >>= b_shift;
    return (a*(double)(1ul<<(32-b_shift))+b)*dbl_reduce_scale;
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
    rb_random_t base;
    struct MT mt;
} rb_random_mt_t;

#define DEFAULT_SEED_CNT 4

static VALUE rand_init(const rb_random_interface_t *, rb_random_t *, VALUE);
static VALUE random_seed(VALUE);
static void fill_random_seed(uint32_t *seed, size_t cnt);
static VALUE make_seed_value(uint32_t *ptr, size_t len);

RB_RANDOM_INTERFACE_DECLARE(rand_mt);
static const rb_random_interface_t random_mt_if = {
    DEFAULT_SEED_CNT * 32,
    RB_RANDOM_INTERFACE_DEFINE(rand_mt)
};

static rb_random_mt_t *
rand_mt_start(rb_random_mt_t *r)
{
    if (!genrand_initialized(&r->mt)) {
	r->base.seed = rand_init(&random_mt_if, &r->base, random_seed(Qundef));
    }
    return r;
}

static rb_random_t *
rand_start(rb_random_mt_t *r)
{
    return &rand_mt_start(r)->base;
}

static rb_ractor_local_key_t default_rand_key;

static void
default_rand_mark(void *ptr)
{
    rb_random_mt_t *rnd = (rb_random_mt_t *)ptr;
    rb_gc_mark(rnd->base.seed);
}

static const struct rb_ractor_local_storage_type default_rand_key_storage_type = {
    default_rand_mark,
    ruby_xfree,
};

static rb_random_mt_t *
default_rand(void)
{
    rb_random_mt_t *rnd;

    if ((rnd = rb_ractor_local_storage_ptr(default_rand_key)) == NULL) {
        rnd = ZALLOC(rb_random_mt_t);
        rb_ractor_local_storage_ptr_set(default_rand_key, rnd);
    }

    return rnd;
}

static rb_random_mt_t *
default_mt(void)
{
    return rand_mt_start(default_rand());
}

unsigned int
rb_genrand_int32(void)
{
    struct MT *mt = &default_mt()->mt;
    return genrand_int32(mt);
}

double
rb_genrand_real(void)
{
    struct MT *mt = &default_mt()->mt;
    return genrand_real(mt);
}

#define SIZEOF_INT32 (31/CHAR_BIT + 1)

static double
int_pair_to_real_inclusive(uint32_t a, uint32_t b)
{
    double r;
    enum {dig = DBL_MANT_DIG};
    enum {dig_u = dig-32, dig_r64 = 64-dig, bmask = ~(~0u<<(dig_r64))};
#if defined HAVE_UINT128_T
    const uint128_t m = ((uint128_t)1 << dig) | 1;
    uint128_t x = ((uint128_t)a << 32) | b;
    r = (double)(uint64_t)((x * m) >> 64);
#elif defined HAVE_UINT64_T && !MSC_VERSION_BEFORE(1300)
    uint64_t x = ((uint64_t)a << dig_u) +
	(((uint64_t)b + (a >> dig_u)) >> dig_r64);
    r = (double)x;
#else
    /* shift then add to get rid of overflow */
    b = (b >> dig_r64) + (((a >> dig_u) + (b & bmask)) >> dig_r64);
    r = (double)a * (1 << dig_u) + b;
#endif
    return r * dbl_reduce_scale;
}

VALUE rb_cRandom;
#define id_minus '-'
#define id_plus  '+'
static ID id_rand, id_bytes;
NORETURN(static void domain_error(void));

/* :nodoc: */
#define random_mark rb_random_mark

void
random_mark(void *ptr)
{
    rb_gc_mark(((rb_random_t *)ptr)->seed);
}

#define random_free RUBY_TYPED_DEFAULT_FREE

static size_t
random_memsize(const void *ptr)
{
    return sizeof(rb_random_t);
}

const rb_data_type_t rb_random_data_type = {
    "random",
    {
	random_mark,
	random_free,
	random_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#define random_mt_mark rb_random_mark

static void
random_mt_free(void *ptr)
{
    rb_random_mt_t *rnd = rb_ractor_local_storage_ptr(default_rand_key);
    if (ptr != rnd)
	xfree(ptr);
}

static size_t
random_mt_memsize(const void *ptr)
{
    return sizeof(rb_random_mt_t);
}

static const rb_data_type_t random_mt_type = {
    "random/MT",
    {
	random_mt_mark,
	random_mt_free,
	random_mt_memsize,
    },
    &rb_random_data_type,
    (void *)&random_mt_if,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static rb_random_t *
get_rnd(VALUE obj)
{
    rb_random_t *ptr;
    TypedData_Get_Struct(obj, rb_random_t, &rb_random_data_type, ptr);
    if (RTYPEDDATA_TYPE(obj) == &random_mt_type)
        return rand_start((rb_random_mt_t *)ptr);
    return ptr;
}

static rb_random_mt_t *
get_rnd_mt(VALUE obj)
{
    rb_random_mt_t *ptr;
    TypedData_Get_Struct(obj, rb_random_mt_t, &random_mt_type, ptr);
    return ptr;
}

static rb_random_t *
try_get_rnd(VALUE obj)
{
    if (obj == rb_cRandom) {
	return rand_start(default_rand());
    }
    if (!rb_typeddata_is_kind_of(obj, &rb_random_data_type)) return NULL;
    if (RTYPEDDATA_TYPE(obj) == &random_mt_type)
        return rand_start(DATA_PTR(obj));
    rb_random_t *rnd = DATA_PTR(obj);
    if (!rnd) {
        rb_raise(rb_eArgError, "uninitialized random: %s",
                 RTYPEDDATA_TYPE(obj)->wrap_struct_name);
    }
    return rnd;
}

static const rb_random_interface_t *
try_rand_if(VALUE obj, rb_random_t *rnd)
{
    if (rnd == &default_rand()->base) {
	return &random_mt_if;
    }
    return rb_rand_if(obj);
}

/* :nodoc: */
void
rb_random_base_init(rb_random_t *rnd)
{
    rnd->seed = INT2FIX(0);
}

/* :nodoc: */
static VALUE
random_alloc(VALUE klass)
{
    rb_random_mt_t *rnd;
    VALUE obj = TypedData_Make_Struct(klass, rb_random_mt_t, &random_mt_type, rnd);
    rb_random_base_init(&rnd->base);
    return obj;
}

static VALUE
rand_init_default(const rb_random_interface_t *rng, rb_random_t *rnd)
{
    VALUE seed, buf0 = 0;
    size_t len = roomof(rng->default_seed_bits, 32);
    uint32_t *buf = ALLOCV_N(uint32_t, buf0, len+1);

    fill_random_seed(buf, len);
    rng->init(rnd, buf, len);
    seed = make_seed_value(buf, len);
    explicit_bzero(buf, len * sizeof(*buf));
    ALLOCV_END(buf0);
    return seed;
}

static VALUE
rand_init(const rb_random_interface_t *rng, rb_random_t *rnd, VALUE seed)
{
    uint32_t *buf;
    VALUE buf0 = 0;
    size_t len;
    int sign;

    len = rb_absint_numwords(seed, 32, NULL);
    if (len == 0) len = 1;
    buf = ALLOCV_N(uint32_t, buf0, len);
    sign = rb_integer_pack(seed, buf, len, sizeof(uint32_t), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
    if (sign < 0)
        sign = -sign;
    if (len > 1) {
        if (sign != 2 && buf[len-1] == 1) /* remove leading-zero-guard */
            len--;
    }
    rng->init(rnd, buf, len);
    explicit_bzero(buf, len * sizeof(*buf));
    ALLOCV_END(buf0);
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
    rb_random_t *rnd = try_get_rnd(obj);
    const rb_random_interface_t *rng = rb_rand_if(obj);

    if (!rng) {
        rb_raise(rb_eTypeError, "undefined random interface: %s",
                 RTYPEDDATA_TYPE(obj)->wrap_struct_name);
    }
    argc = rb_check_arity(argc, 0, 1);
    rb_check_frozen(obj);
    if (argc == 0) {
        rnd->seed = rand_init_default(rng, rnd);
    }
    else {
        rnd->seed = rand_init(rng, rnd, rb_to_int(argv[0]));
    }
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
    size_t offset = 0;

    if (fd < 0) return -1;
    rb_update_max_fd(fd);
    if (fstat(fd, &statbuf) == 0 && S_ISCHR(statbuf.st_mode)) {
	do {
	    ret = read(fd, ((char*)seed) + offset, size - offset);
	    if (ret < 0) {
		close(fd);
		return -1;
	    }
	    offset += (size_t)ret;
	} while (offset < size);
    }
    close(fd);
    return 0;
}
#else
# define fill_random_bytes_urandom(seed, size) -1
#endif

#if ! defined HAVE_GETRANDOM && defined __linux__ && defined __NR_getrandom
# ifndef GRND_NONBLOCK
#   define GRND_NONBLOCK 0x0001	/* not defined in musl libc */
# endif
# define getrandom(ptr, size, flags) \
    (ssize_t)syscall(__NR_getrandom, (ptr), (size), (flags))
# define HAVE_GETRANDOM 1
#endif

#if 0
#elif defined MAC_OS_X_VERSION_10_7 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7
#include <Security/Security.h>

static int
fill_random_bytes_syscall(void *seed, size_t size, int unused)
{
    int status = SecRandomCopyBytes(kSecRandomDefault, size, seed);

    if (status != errSecSuccess) {
# if 0
        CFStringRef s = SecCopyErrorMessageString(status, NULL);
        const char *m = s ? CFStringGetCStringPtr(s, kCFStringEncodingUTF8) : NULL;
        fprintf(stderr, "SecRandomCopyBytes failed: %d: %s\n", status,
                m ? m : "unknown");
        if (s) CFRelease(s);
# endif
        return -1;
    }
    return 0;
}
#elif defined(HAVE_ARC4RANDOM_BUF)
static int
fill_random_bytes_syscall(void *buf, size_t size, int unused)
{
#if (defined(__OpenBSD__) && OpenBSD >= 201411) || \
    (defined(__NetBSD__)  && __NetBSD_Version__ >= 700000000) || \
    (defined(__FreeBSD__) && __FreeBSD_version >= 1200079)
    arc4random_buf(buf, size);
    return 0;
#else
    return -1;
#endif
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
	if (LIKELY(!old_prov)) { /* no other threads acquired */
	    if (prov != (HCRYPTPROV)INVALID_HANDLE_VALUE) {
#undef RUBY_UNTYPED_DATA_WARNING
#define RUBY_UNTYPED_DATA_WARNING 0
		rb_gc_register_mark_object(Data_Wrap_Struct(0, 0, release_crypt, &perm_prov));
	    }
	}
	else {			/* another thread acquired */
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
#elif defined HAVE_GETRANDOM
static int
fill_random_bytes_syscall(void *seed, size_t size, int need_secure)
{
    static rb_atomic_t try_syscall = 1;
    if (try_syscall) {
	size_t offset = 0;
	int flags = 0;
	if (!need_secure)
	    flags = GRND_NONBLOCK;
	do {
	    errno = 0;
            ssize_t ret = getrandom(((char*)seed) + offset, size - offset, flags);
	    if (ret == -1) {
		ATOMIC_SET(try_syscall, 0);
		return -1;
	    }
	    offset += (size_t)ret;
	} while (offset < size);
	return 0;
    }
    return -1;
}
#else
# define fill_random_bytes_syscall(seed, size, need_secure) -1
#endif

int
ruby_fill_random_bytes(void *seed, size_t size, int need_secure)
{
    int ret = fill_random_bytes_syscall(seed, size, need_secure);
    if (ret == 0) return ret;
    return fill_random_bytes_urandom(seed, size);
}

#define fill_random_bytes ruby_fill_random_bytes

/* cnt must be 4 or more */
static void
fill_random_seed(uint32_t *seed, size_t cnt)
{
    static int n = 0;
#if defined HAVE_CLOCK_GETTIME
    struct timespec tv;
#elif defined HAVE_GETTIMEOFDAY
    struct timeval tv;
#endif
    size_t len = cnt * sizeof(*seed);

    memset(seed, 0, len);

    fill_random_bytes(seed, len, FALSE);

#if defined HAVE_CLOCK_GETTIME
    clock_gettime(CLOCK_REALTIME, &tv);
    seed[0] ^= tv.tv_nsec;
#elif defined HAVE_GETTIMEOFDAY
    gettimeofday(&tv, 0);
    seed[0] ^= tv.tv_usec;
#endif
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
make_seed_value(uint32_t *ptr, size_t len)
{
    VALUE seed;

    if (ptr[len-1] <= 1) {
        /* set leading-zero-guard */
        ptr[len++] = 1;
    }

    seed = rb_integer_unpack(ptr, len, sizeof(uint32_t), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);

    return seed;
}

#define with_random_seed(size, add) \
    for (uint32_t seedbuf[(size)+(add)], loop = (fill_random_seed(seedbuf, (size)), 1); \
         loop; explicit_bzero(seedbuf, (size)*sizeof(seedbuf[0])), loop = 0)

/*
 * call-seq: Random.new_seed -> integer
 *
 * Returns an arbitrary seed value. This is used by Random.new
 * when no seed value is specified as an argument.
 *
 *   Random.new_seed  #=> 115032730400174366788466674494640623225
 */
static VALUE
random_seed(VALUE _)
{
    VALUE v;
    with_random_seed(DEFAULT_SEED_CNT, 1) {
        v = make_seed_value(seedbuf, DEFAULT_SEED_CNT);
    }
    return v;
}

/*
 * call-seq: Random.urandom(size) -> string
 *
 * Returns a string, using platform providing features.
 * Returned value is expected to be a cryptographically secure
 * pseudo-random number in binary form.
 * This method raises a RuntimeError if the feature provided by platform
 * failed to prepare the result.
 *
 * In 2017, Linux manpage random(7) writes that "no cryptographic
 * primitive available today can hope to promise more than 256 bits of
 * security".  So it might be questionable to pass size > 32 to this
 * method.
 *
 *   Random.urandom(8)  #=> "\x78\x41\xBA\xAF\x7D\xEA\xD8\xEA"
 */
static VALUE
random_raw_seed(VALUE self, VALUE size)
{
    long n = NUM2ULONG(size);
    VALUE buf = rb_str_new(0, n);
    if (n == 0) return buf;
    if (fill_random_bytes(RSTRING_PTR(buf), n, TRUE))
	rb_raise(rb_eRuntimeError, "failed to get urandom");
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
rand_mt_copy(VALUE obj, VALUE orig)
{
    rb_random_mt_t *rnd1, *rnd2;
    struct MT *mt;

    if (!OBJ_INIT_COPY(obj, orig)) return obj;

    rnd1 = get_rnd_mt(obj);
    rnd2 = get_rnd_mt(orig);
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
rand_mt_state(VALUE obj)
{
    rb_random_mt_t *rnd = get_rnd_mt(obj);
    return mt_state(&rnd->mt);
}

/* :nodoc: */
static VALUE
random_s_state(VALUE klass)
{
    return mt_state(&default_rand()->mt);
}

/* :nodoc: */
static VALUE
rand_mt_left(VALUE obj)
{
    rb_random_mt_t *rnd = get_rnd_mt(obj);
    return INT2FIX(rnd->mt.left);
}

/* :nodoc: */
static VALUE
random_s_left(VALUE klass)
{
    return INT2FIX(default_rand()->mt.left);
}

/* :nodoc: */
static VALUE
rand_mt_dump(VALUE obj)
{
    rb_random_mt_t *rnd = rb_check_typeddata(obj, &random_mt_type);
    VALUE dump = rb_ary_new2(3);

    rb_ary_push(dump, mt_state(&rnd->mt));
    rb_ary_push(dump, INT2FIX(rnd->mt.left));
    rb_ary_push(dump, rnd->base.seed);

    return dump;
}

/* :nodoc: */
static VALUE
rand_mt_load(VALUE obj, VALUE dump)
{
    rb_random_mt_t *rnd = rb_check_typeddata(obj, &random_mt_type);
    struct MT *mt = &rnd->mt;
    VALUE state, left = INT2FIX(1), seed = INT2FIX(0);
    unsigned long x;

    rb_check_copyable(obj, dump);
    Check_Type(dump, T_ARRAY);
    switch (RARRAY_LEN(dump)) {
      case 3:
        seed = RARRAY_AREF(dump, 2);
      case 2:
        left = RARRAY_AREF(dump, 1);
      case 1:
        state = RARRAY_AREF(dump, 0);
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
    rnd->base.seed = rb_to_int(seed);

    return obj;
}

static void
rand_mt_init(rb_random_t *rnd, const uint32_t *buf, size_t len)
{
    struct MT *mt = &((rb_random_mt_t *)rnd)->mt;
    if (len <= 1) {
        init_genrand(mt, len ? buf[0] : 0);
    }
    else {
        init_by_array(mt, buf, (int)len);
    }
}

static unsigned int
rand_mt_get_int32(rb_random_t *rnd)
{
    struct MT *mt = &((rb_random_mt_t *)rnd)->mt;
    return genrand_int32(mt);
}

static void
rand_mt_get_bytes(rb_random_t *rnd, void *ptr, size_t n)
{
    rb_rand_bytes_int32(rand_mt_get_int32, rnd, ptr, n);
}

/*
 * call-seq:
 *   srand(number = Random.new_seed) -> old_seed
 *
 * Seeds the system pseudo-random number generator, with +number+.
 * The previous seed value is returned.
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
    rb_random_mt_t *r = rand_mt_start(default_rand());

    if (rb_check_arity(argc, 0, 1) == 0) {
        seed = random_seed(obj);
    }
    else {
	seed = rb_to_int(argv[0]);
    }
    old = r->base.seed;
    rand_init(&random_mt_if, &r->base, seed);
    r->base.seed = seed;

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
limited_rand(const rb_random_interface_t *rng, rb_random_t *rnd, unsigned long limit)
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
                val |= (unsigned long)rng->get_int32(rnd) << (i * 32);
                val &= mask;
                if (limit < val)
                    goto retry;
            }
        }
        return val;
    }
#endif

    do {
        val = rng->get_int32(rnd) & mask;
    } while (limit < val);
    return val;
}

static VALUE
limited_big_rand(const rb_random_interface_t *rng, rb_random_t *rnd, VALUE limit)
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
        uint32_t r = 0;
        uint32_t lim = lim_array[i];
        mask = mask ? 0xffffffff : (uint32_t)make_mask(lim);
        if (mask) {
            r = rng->get_int32(rnd) & mask;
            if (boundary) {
                if (lim < r)
                    goto retry;
                if (r < lim)
                    boundary = 0;
            }
        }
        rnd_array[i] = r;
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
    rb_random_mt_t *mt = default_mt();
    return limited_rand(&random_mt_if, &mt->base, limit);
}

static VALUE
obj_random_bytes(VALUE obj, void *p, long n)
{
    VALUE len = LONG2NUM(n);
    VALUE v = rb_funcallv_public(obj, id_bytes, 1, &len);
    long l;
    Check_Type(v, T_STRING);
    l = RSTRING_LEN(v);
    if (l < n)
	rb_raise(rb_eRangeError, "random data too short %ld", l);
    else if (l > n)
	rb_raise(rb_eRangeError, "random data too long %ld", l);
    if (p) memcpy(p, RSTRING_PTR(v), n);
    return v;
}

static unsigned int
random_int32(const rb_random_interface_t *rng, rb_random_t *rnd)
{
    return rng->get_int32(rnd);
}

unsigned int
rb_random_int32(VALUE obj)
{
    rb_random_t *rnd = try_get_rnd(obj);
    if (!rnd) {
	uint32_t x;
	obj_random_bytes(obj, &x, sizeof(x));
	return (unsigned int)x;
    }
    return random_int32(try_rand_if(obj, rnd), rnd);
}

static double
random_real(VALUE obj, rb_random_t *rnd, int excl)
{
    uint32_t a, b;

    if (!rnd) {
	uint32_t x[2] = {0, 0};
	obj_random_bytes(obj, x, sizeof(x));
	a = x[0];
	b = x[1];
    }
    else {
        const rb_random_interface_t *rng = try_rand_if(obj, rnd);
        if (rng->get_real) return rng->get_real(rnd, excl);
        a = random_int32(rng, rnd);
        b = random_int32(rng, rnd);
    }
    return rb_int_pair_to_real(a, b, excl);
}

double
rb_int_pair_to_real(uint32_t a, uint32_t b, int excl)
{
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
	VALUE v = rb_funcallv(obj, id_rand, 0, 0);
	double d = NUM2DBL(v);
	if (d < 0.0) {
	    rb_raise(rb_eRangeError, "random number too small %g", d);
	}
	else if (d >= 1.0) {
	    rb_raise(rb_eRangeError, "random number too big %g", d);
	}
	return d;
    }
    return random_real(obj, rnd, TRUE);
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
    if (!limit) return 0;
    if (!rnd) {
	const int w = sizeof(limit) * CHAR_BIT - nlz_long(limit);
	const int n = w > 32 ? sizeof(unsigned long) : sizeof(uint32_t);
	const unsigned long mask = ~(~0UL << w);
	const unsigned long full =
	    (size_t)n >= sizeof(unsigned long) ? ~0UL :
	    ~(~0UL << n * CHAR_BIT);
	unsigned long val, bits = 0, rest = 0;
	do {
	    if (mask & ~rest) {
		union {uint32_t u32; unsigned long ul;} buf;
		obj_random_bytes(obj, &buf, n);
		rest = full;
		bits = (n == sizeof(uint32_t)) ? buf.u32 : buf.ul;
	    }
	    val = bits;
	    bits >>= w;
	    rest >>= w;
	    val &= mask;
	} while (limit < val);
	return val;
    }
    return limited_rand(try_rand_if(obj, rnd), rnd, limit);
}

unsigned long
rb_random_ulong_limited(VALUE obj, unsigned long limit)
{
    rb_random_t *rnd = try_get_rnd(obj);
    if (!rnd) {
	VALUE lim = ulong_to_num_plus_1(limit);
	VALUE v = rb_to_int(rb_funcallv_public(obj, id_rand, 1, &lim));
	unsigned long r = NUM2ULONG(v);
	if (rb_num_negative_p(v)) {
	    rb_raise(rb_eRangeError, "random number too small %ld", r);
	}
	if (r > limit) {
	    rb_raise(rb_eRangeError, "random number too big %ld", r);
	}
	return r;
    }
    return limited_rand(try_rand_if(obj, rnd), rnd, limit);
}

static VALUE
random_ulong_limited_big(VALUE obj, rb_random_t *rnd, VALUE vmax)
{
    if (!rnd) {
	VALUE v, vtmp;
	size_t i, nlz, len = rb_absint_numwords(vmax, 32, &nlz);
	uint32_t *tmp = ALLOCV_N(uint32_t, vtmp, len * 2);
	uint32_t mask = (uint32_t)~0 >> nlz;
	uint32_t *lim_array = tmp;
	uint32_t *rnd_array = tmp + len;
	int flag = INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER;
	rb_integer_pack(vmax, lim_array, len, sizeof(uint32_t), 0, flag);

      retry:
	obj_random_bytes(obj, rnd_array, len * sizeof(uint32_t));
	rnd_array[0] &= mask;
	for (i = 0; i < len; ++i) {
	    if (lim_array[i] < rnd_array[i])
		goto retry;
	    if (rnd_array[i] < lim_array[i])
		break;
	}
	v = rb_integer_unpack(rnd_array, len, sizeof(uint32_t), 0, flag);
	ALLOCV_END(vtmp);
	return v;
    }
    return limited_big_rand(try_rand_if(obj, rnd), rnd, vmax);
}

static VALUE
rand_bytes(const rb_random_interface_t *rng, rb_random_t *rnd, long n)
{
    VALUE bytes;
    char *ptr;

    bytes = rb_str_new(0, n);
    ptr = RSTRING_PTR(bytes);
    rb_rand_bytes_int32(rng->get_int32, rnd, ptr, n);
    return bytes;
}

/*
 * call-seq: prng.bytes(size) -> string
 *
 * Returns a random binary string containing +size+ bytes.
 *
 *   random_string = Random.new.bytes(10) # => "\xD7:R\xAB?\x83\xCE\xFAkO"
 *   random_string.size                   # => 10
 */
static VALUE
random_bytes(VALUE obj, VALUE len)
{
    rb_random_t *rnd = try_get_rnd(obj);
    return rand_bytes(rb_rand_if(obj), rnd, NUM2LONG(rb_to_int(len)));
}

void
rb_rand_bytes_int32(rb_random_get_int32_func *get_int32,
                    rb_random_t *rnd, void *p, size_t n)
{
    char *ptr = p;
    unsigned int r, i;
    for (; n >= SIZEOF_INT32; n -= SIZEOF_INT32) {
        r = get_int32(rnd);
	i = SIZEOF_INT32;
	do {
	    *ptr++ = (char)r;
	    r >>= CHAR_BIT;
        } while (--i);
    }
    if (n > 0) {
        r = get_int32(rnd);
	do {
	    *ptr++ = (char)r;
	    r >>= CHAR_BIT;
	} while (--n);
    }
}

VALUE
rb_random_bytes(VALUE obj, long n)
{
    rb_random_t *rnd = try_get_rnd(obj);
    if (!rnd) {
	return obj_random_bytes(obj, NULL, n);
    }
    return rand_bytes(try_rand_if(obj, rnd), rnd, n);
}

/*
 * call-seq: Random.bytes(size) -> string
 *
 * Returns a random binary string.
 * The argument +size+ specifies the length of the returned string.
 */
static VALUE
random_s_bytes(VALUE obj, VALUE len)
{
    rb_random_t *rnd = rand_start(default_rand());
    return rand_bytes(&random_mt_if, rnd, NUM2LONG(rb_to_int(len)));
}

static VALUE
random_s_seed(VALUE obj)
{
    rb_random_mt_t *rnd = rand_mt_start(default_rand());
    return rnd->base.seed;
}

static VALUE
range_values(VALUE vmax, VALUE *begp, VALUE *endp, int *exclp)
{
    VALUE beg, end;

    if (!rb_range_values(vmax, &beg, &end, exclp)) return Qfalse;
    if (begp) *begp = beg;
    if (NIL_P(beg)) return Qnil;
    if (endp) *endp = end;
    if (NIL_P(end)) return Qnil;
    return rb_check_funcall_default(end, id_minus, 1, begp, Qfalse);
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
    if (NIL_P(v)) domain_error();
    if (!RB_TYPE_P(vmax, T_FLOAT) && (v = rb_check_to_int(vmax), !NIL_P(v))) {
	long max;
	vmax = v;
	v = Qnil;
      fixnum:
	if (FIXNUM_P(vmax)) {
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
	return rb_funcallv(beg, id_plus, 1, &v);
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
    VALUE v = rand_random(argc, argv, obj, try_get_rnd(obj));
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

/*
 * call-seq:
 *   prng.random_number      -> float
 *   prng.random_number(max) -> number
 *   prng.rand               -> float
 *   prng.rand(max)          -> number
 *
 * Generates formatted random number from raw random bytes.
 * See Random#rand.
 */
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
rand_mt_equal(VALUE self, VALUE other)
{
    rb_random_mt_t *r1, *r2;
    if (rb_obj_class(self) != rb_obj_class(other)) return Qfalse;
    r1 = get_rnd_mt(self);
    r2 = get_rnd_mt(other);
    if (memcmp(r1->mt.state, r2->mt.state, sizeof(r1->mt.state))) return Qfalse;
    if ((r1->mt.next - r1->mt.state) != (r2->mt.next - r2->mt.state)) return Qfalse;
    if (r1->mt.left != r2->mt.left) return Qfalse;
    return rb_equal(r1->base.seed, r2->base.seed);
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
    rb_random_t *rnd = rand_start(default_rand());

    if (rb_check_arity(argc, 0, 1) && !NIL_P(vmax = argv[0])) {
        VALUE v = rand_range(obj, rnd, vmax);
	if (v != Qfalse) return v;
	vmax = rb_to_int(vmax);
	if (vmax != INT2FIX(0)) {
            v = rand_int(obj, rnd, vmax, 0);
	    if (!NIL_P(v)) return v;
	}
    }
    return DBL2NUM(random_real(obj, rnd, TRUE));
}

/*
 * call-seq:
 *   Random.rand -> float
 *   Random.rand(max) -> number
 */

static VALUE
random_s_rand(int argc, VALUE *argv, VALUE obj)
{
    VALUE v = rand_random(argc, argv, Qnil, rand_start(default_rand()));
    check_random_number(v, argv);
    return v;
}

#define SIP_HASH_STREAMING 0
#define sip_hash13 ruby_sip_hash13
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

typedef struct {
    st_index_t hash;
    uint8_t sip[16];
} hash_salt_t;

static union {
    hash_salt_t key;
    uint32_t u32[type_roomof(hash_salt_t, uint32_t)];
} hash_salt;

static void
init_hash_salt(struct MT *mt)
{
    int i;

    for (i = 0; i < numberof(hash_salt.u32); ++i)
	hash_salt.u32[i] = genrand_int32(mt);
}

NO_SANITIZE("unsigned-integer-overflow", extern st_index_t rb_hash_start(st_index_t h));
st_index_t
rb_hash_start(st_index_t h)
{
    return st_hash_start(hash_salt.key.hash + h);
}

st_index_t
rb_memhash(const void *ptr, long len)
{
    sip_uint64_t h = sip_hash13(hash_salt.key.sip, ptr, len);
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
    if (!fill_random_bytes(&hash_salt, sizeof(hash_salt), FALSE)) return;

    /*
      If failed to fill siphash's salt with random data, expand less random
      data with MT.

      Don't reuse this MT for default_rand(). default_rand()::seed shouldn't
      provide a hint that an attacker guess siphash's seed.
    */
    struct MT mt;

    with_random_seed(DEFAULT_SEED_CNT, 0) {
        init_by_array(&mt, seedbuf, DEFAULT_SEED_CNT);
    }

    init_hash_salt(&mt);
    explicit_bzero(&mt, sizeof(mt));
}

void
rb_reset_random_seed(void)
{
    rb_random_mt_t *r = default_rand();
    uninit_genrand(&r->mt);
    r->base.seed = INT2FIX(0);
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
 * interfaces to the Ruby system PRNG.
 *
 * Random.new will create a new PRNG with a state independent of the Ruby
 * system PRNG, allowing multiple generators with different seed values or
 * sequence positions to exist simultaneously. Random objects can be
 * marshaled, allowing sequences to be saved and resumed.
 *
 * PRNGs are currently implemented as a modified Mersenne Twister with a period
 * of 2**19937-1.  As this algorithm is _not_ for cryptographical use, you must
 * use SecureRandom for security purpose, instead of this PRNG.
 */

void
InitVM_Random(void)
{
    VALUE base;
    ID id_base = rb_intern_const("Base");

    rb_define_global_function("srand", rb_f_srand, -1);
    rb_define_global_function("rand", rb_f_rand, -1);

    base = rb_define_class_id(id_base, rb_cObject);
    rb_undef_alloc_func(base);
    rb_cRandom = rb_define_class("Random", base);
    rb_const_set(rb_cRandom, id_base, base);
    rb_define_alloc_func(rb_cRandom, random_alloc);
    rb_define_method(base, "initialize", random_init, -1);
    rb_define_method(base, "rand", random_rand, -1);
    rb_define_method(base, "bytes", random_bytes, 1);
    rb_define_method(base, "seed", random_get_seed, 0);
    rb_define_method(rb_cRandom, "initialize_copy", rand_mt_copy, 1);
    rb_define_private_method(rb_cRandom, "marshal_dump", rand_mt_dump, 0);
    rb_define_private_method(rb_cRandom, "marshal_load", rand_mt_load, 1);
    rb_define_private_method(rb_cRandom, "state", rand_mt_state, 0);
    rb_define_private_method(rb_cRandom, "left", rand_mt_left, 0);
    rb_define_method(rb_cRandom, "==", rand_mt_equal, 1);

#if 0 /* for RDoc: it can't handle unnamed base class */
    rb_define_method(rb_cRandom, "initialize", random_init, -1);
    rb_define_method(rb_cRandom, "rand", random_rand, -1);
    rb_define_method(rb_cRandom, "bytes", random_bytes, 1);
    rb_define_method(rb_cRandom, "seed", random_get_seed, 0);
#endif

    rb_define_const(rb_cRandom, "DEFAULT", rb_cRandom);
    rb_deprecate_constant(rb_cRandom, "DEFAULT");

    rb_define_singleton_method(rb_cRandom, "srand", rb_f_srand, -1);
    rb_define_singleton_method(rb_cRandom, "rand", random_s_rand, -1);
    rb_define_singleton_method(rb_cRandom, "bytes", random_s_bytes, 1);
    rb_define_singleton_method(rb_cRandom, "seed", random_s_seed, 0);
    rb_define_singleton_method(rb_cRandom, "new_seed", random_seed, 0);
    rb_define_singleton_method(rb_cRandom, "urandom", random_raw_seed, 1);
    rb_define_private_method(CLASS_OF(rb_cRandom), "state", random_s_state, 0);
    rb_define_private_method(CLASS_OF(rb_cRandom), "left", random_s_left, 0);

    {
	/* Format raw random number as Random does */
	VALUE m = rb_define_module_under(rb_cRandom, "Formatter");
	rb_include_module(base, m);
	rb_extend_object(base, m);
	rb_define_method(m, "random_number", rand_random_number, -1);
	rb_define_method(m, "rand", rand_random_number, -1);
    }

    default_rand_key = rb_ractor_local_storage_ptr_newkey(&default_rand_key_storage_type);
}

#undef rb_intern
void
Init_Random(void)
{
    id_rand = rb_intern("rand");
    id_bytes = rb_intern("bytes");

    InitVM(Random);
}
