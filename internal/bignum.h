#ifndef INTERNAL_BIGNUM_H /* -*- C -*- */
#define INTERNAL_BIGNUM_H
/**
 * @file
 * @brief      Internal header for Bignums.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/config.h"        /* for HAVE_LIBGMP */
#include <stddef.h>             /* for size_t */

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>         /* for ssize_t (note: on Windows ssize_t is */
#endif                          /* `#define`d in ruby/config.h) */

#include "internal/stdbool.h"   /* for bool */
#include "ruby/ruby.h"          /* for struct RBasic */
#include "ruby_assert.h"        /* for assert */

#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
# define USE_GMP
# include <gmp.h>
#endif

#ifndef BDIGIT
# if SIZEOF_INT*2 <= SIZEOF_LONG_LONG
#  define BDIGIT unsigned int
#  define SIZEOF_BDIGIT SIZEOF_INT
#  define BDIGIT_DBL unsigned LONG_LONG
#  define BDIGIT_DBL_SIGNED LONG_LONG
#  define PRI_BDIGIT_PREFIX ""
#  define PRI_BDIGIT_DBL_PREFIX PRI_LL_PREFIX
# elif SIZEOF_INT*2 <= SIZEOF_LONG
#  define BDIGIT unsigned int
#  define SIZEOF_BDIGIT SIZEOF_INT
#  define BDIGIT_DBL unsigned long
#  define BDIGIT_DBL_SIGNED long
#  define PRI_BDIGIT_PREFIX ""
#  define PRI_BDIGIT_DBL_PREFIX "l"
# elif SIZEOF_SHORT*2 <= SIZEOF_LONG
#  define BDIGIT unsigned short
#  define SIZEOF_BDIGIT SIZEOF_SHORT
#  define BDIGIT_DBL unsigned long
#  define BDIGIT_DBL_SIGNED long
#  define PRI_BDIGIT_PREFIX "h"
#  define PRI_BDIGIT_DBL_PREFIX "l"
# else
#  define BDIGIT unsigned short
#  define SIZEOF_BDIGIT (SIZEOF_LONG/2)
#  define SIZEOF_ACTUAL_BDIGIT SIZEOF_LONG
#  define BDIGIT_DBL unsigned long
#  define BDIGIT_DBL_SIGNED long
#  define PRI_BDIGIT_PREFIX "h"
#  define PRI_BDIGIT_DBL_PREFIX "l"
# endif
#endif

#ifndef SIZEOF_ACTUAL_BDIGIT
# define SIZEOF_ACTUAL_BDIGIT SIZEOF_BDIGIT
#endif

#ifdef PRI_BDIGIT_PREFIX
# define PRIdBDIGIT PRI_BDIGIT_PREFIX"d"
# define PRIiBDIGIT PRI_BDIGIT_PREFIX"i"
# define PRIoBDIGIT PRI_BDIGIT_PREFIX"o"
# define PRIuBDIGIT PRI_BDIGIT_PREFIX"u"
# define PRIxBDIGIT PRI_BDIGIT_PREFIX"x"
# define PRIXBDIGIT PRI_BDIGIT_PREFIX"X"
#endif

#ifdef PRI_BDIGIT_DBL_PREFIX
# define PRIdBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"d"
# define PRIiBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"i"
# define PRIoBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"o"
# define PRIuBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"u"
# define PRIxBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"x"
# define PRIXBDIGIT_DBL PRI_BDIGIT_DBL_PREFIX"X"
#endif

#define RBIGNUM(obj) (R_CAST(RBignum)(obj))
#define BIGNUM_SIGN_BIT FL_USER1
#define BIGNUM_EMBED_FLAG ((VALUE)FL_USER2)
#define BIGNUM_EMBED_LEN_NUMBITS 3
#define BIGNUM_EMBED_LEN_MASK \
    (~(~(VALUE)0U << BIGNUM_EMBED_LEN_NUMBITS) << BIGNUM_EMBED_LEN_SHIFT)
#define BIGNUM_EMBED_LEN_SHIFT \
    (FL_USHIFT+3) /* bit offset of BIGNUM_EMBED_LEN_MASK */
#ifndef BIGNUM_EMBED_LEN_MAX
# if (SIZEOF_VALUE*RVALUE_EMBED_LEN_MAX/SIZEOF_ACTUAL_BDIGIT) < (1 << BIGNUM_EMBED_LEN_NUMBITS)-1
#  define BIGNUM_EMBED_LEN_MAX (SIZEOF_VALUE*RVALUE_EMBED_LEN_MAX/SIZEOF_ACTUAL_BDIGIT)
# else
#  define BIGNUM_EMBED_LEN_MAX ((1 << BIGNUM_EMBED_LEN_NUMBITS)-1)
# endif
#endif

enum rb_int_parse_flags {
    RB_INT_PARSE_SIGN       = 0x01,
    RB_INT_PARSE_UNDERSCORE = 0x02,
    RB_INT_PARSE_PREFIX     = 0x04,
    RB_INT_PARSE_ALL        = 0x07,
    RB_INT_PARSE_DEFAULT    = 0x07,
};

struct RBignum {
    struct RBasic basic;
    union {
#ifdef USE_GMP
        mpz_t mpz;
#else
        struct {
            size_t len;
            BDIGIT *digits;
        } heap;
#endif
        BDIGIT ary[BIGNUM_EMBED_LEN_MAX];
    } as;
};

/* bignum.c */
extern const char ruby_digitmap[];
double rb_big_fdiv_double(VALUE x, VALUE y);
VALUE rb_big_uminus(VALUE x);
VALUE rb_big_hash(VALUE);
VALUE rb_big_odd_p(VALUE);
VALUE rb_big_even_p(VALUE);
size_t rb_big_size(VALUE);
VALUE rb_integer_float_cmp(VALUE x, VALUE y);
VALUE rb_integer_float_eq(VALUE x, VALUE y);
VALUE rb_str_convert_to_inum(VALUE str, int base, int badcheck, int raise_exception);
VALUE rb_big_comp(VALUE x);
VALUE rb_big_aref(VALUE x, VALUE y);
VALUE rb_big_abs(VALUE x);
VALUE rb_big_size_m(VALUE big);
VALUE rb_big_bit_length(VALUE big);
VALUE rb_big_remainder(VALUE x, VALUE y);
VALUE rb_big_gt(VALUE x, VALUE y);
VALUE rb_big_ge(VALUE x, VALUE y);
VALUE rb_big_lt(VALUE x, VALUE y);
VALUE rb_big_le(VALUE x, VALUE y);
VALUE rb_int_powm(int const argc, VALUE * const argv, VALUE const num);
static inline bool BIGNUM_SIGN(VALUE b);
static inline bool BIGNUM_POSITIVE_P(VALUE b);
static inline bool BIGNUM_NEGATIVE_P(VALUE b);
static inline void BIGNUM_SET_SIGN(VALUE b, bool sign);
static inline void BIGNUM_NEGATE(VALUE b);
static inline size_t BIGNUM_LEN(VALUE b);
static inline BDIGIT *BIGNUM_DIGITS(VALUE b);
static inline int BIGNUM_LENINT(VALUE b);
static inline bool BIGNUM_EMBED_P(VALUE b);
#ifdef USE_GMP
size_t rb_absint_size_mpz(const mpz_t mx, int *nlz_bits_ret);
VALUE rb_big_gcd_mpz(mpz_t mx, VALUE y);
static inline mpz_t *BIGNUM_MPZ_PTR(VALUE b);
# ifdef _MSC_VER
#  define BIGNUM_MPZ(b) RBIGNUM(b)->as.mpz
# else
#  define BIGNUM_MPZ(b) *BIGNUM_MPZ_PTR(b)
# endif
static inline size_t BIGNUM_MPZ_LEN(const mpz_t mx);
static inline void BIGNUM_MPZ_NEGATE(VALUE b);
#endif

RUBY_SYMBOL_EXPORT_BEGIN
/* bignum.c (export) */
VALUE rb_big_mul_normal(VALUE x, VALUE y);
VALUE rb_big_mul_balance(VALUE x, VALUE y);
VALUE rb_big_mul_karatsuba(VALUE x, VALUE y);
VALUE rb_big_mul_toom3(VALUE x, VALUE y);
VALUE rb_big_sq_fast(VALUE x);
VALUE rb_big_divrem_normal(VALUE x, VALUE y);
VALUE rb_big2str_poweroftwo(VALUE x, int base);
VALUE rb_big2str_generic(VALUE x, int base);
VALUE rb_str2big_poweroftwo(VALUE arg, int base, int badcheck);
VALUE rb_str2big_normal(VALUE arg, int base, int badcheck);
VALUE rb_str2big_karatsuba(VALUE arg, int base, int badcheck);
#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
VALUE rb_big_mul_gmp(VALUE x, VALUE y);
VALUE rb_big_divrem_gmp(VALUE x, VALUE y);
VALUE rb_big2str_gmp(VALUE x, int base);
VALUE rb_str2big_gmp(VALUE arg, int base, int badcheck);
#endif
VALUE rb_int_parse_cstr(const char *str, ssize_t len, char **endp, size_t *ndigits, int base, int flags);
#ifdef USE_GMP
VALUE rb_big_new_mpz_set_bdigits(const BDIGIT *digits, size_t len);
#endif
RUBY_SYMBOL_EXPORT_END

MJIT_SYMBOL_EXPORT_BEGIN
#if defined(HAVE_INT128_T)
VALUE rb_int128t2big(int128_t n);
#endif
MJIT_SYMBOL_EXPORT_END

/* sign: positive:1, negative:0 */
static inline bool
BIGNUM_SIGN(VALUE b)
{
#ifdef USE_GMP
    if (! BIGNUM_EMBED_P(b)) {
        return mpz_sgn(BIGNUM_MPZ(b)) >= 0;
    }
#endif
    return FL_TEST_RAW(b, BIGNUM_SIGN_BIT);
}

static inline bool
BIGNUM_POSITIVE_P(VALUE b)
{
    return BIGNUM_SIGN(b);
}

static inline bool
BIGNUM_NEGATIVE_P(VALUE b)
{
    return ! BIGNUM_POSITIVE_P(b);
}

static inline void
BIGNUM_SET_SIGN(VALUE b, bool sign)
{
#ifdef USE_GMP
    if (! BIGNUM_EMBED_P(b)) {
        if (BIGNUM_POSITIVE_P(b) != sign) {
            BIGNUM_MPZ_NEGATE(b);
        }
    }
    else
#endif
    if (sign) {
        FL_SET_RAW(b, BIGNUM_SIGN_BIT);
    }
    else {
        FL_UNSET_RAW(b, BIGNUM_SIGN_BIT);
    }
}

static inline void
BIGNUM_NEGATE(VALUE b)
{
#ifdef USE_GMP
    if (! BIGNUM_EMBED_P(b)) {
        BIGNUM_MPZ_NEGATE(b);
    }
    else
#endif
    FL_REVERSE_RAW(b, BIGNUM_SIGN_BIT);
}

static inline size_t
BIGNUM_LEN(VALUE b)
{
    if (! BIGNUM_EMBED_P(b)) {
#ifdef USE_GMP
        return BIGNUM_MPZ_LEN(BIGNUM_MPZ(b));
#else
        return RBIGNUM(b)->as.heap.len;
#endif
    }
    else
    {
        size_t ret = RBASIC(b)->flags;
        ret &= BIGNUM_EMBED_LEN_MASK;
        ret >>= BIGNUM_EMBED_LEN_SHIFT;
        return ret;
    }
}

static inline int
BIGNUM_LENINT(VALUE b)
{
    return rb_long2int(BIGNUM_LEN(b));
}

/* LSB:BIGNUM_DIGITS(b)[0], MSB:BIGNUM_DIGITS(b)[BIGNUM_LEN(b)-1] */
static inline BDIGIT *
BIGNUM_DIGITS(VALUE b)
{
#ifdef USE_GMP
    assert(BIGNUM_EMBED_P(b));
#else
    if (! BIGNUM_EMBED_P(b)) {
        return RBIGNUM(b)->as.heap.digits;
    }
    else
#endif
    return RBIGNUM(b)->as.ary;
}

static inline bool
BIGNUM_EMBED_P(VALUE b)
{
    return FL_TEST_RAW(b, BIGNUM_EMBED_FLAG);
}

#ifdef USE_GMP
static inline mpz_t *
BIGNUM_MPZ_PTR(VALUE b)
{
    assert(! BIGNUM_EMBED_P(b));
    return &RBIGNUM(b)->as.mpz;
}

// Return the size of mpz in the number of BDIGITs
static inline size_t
BIGNUM_MPZ_LEN(const mpz_t mx)
{
    const size_t BITS_OF_BDIGIT = SIZEOF_BDIGIT*CHAR_BIT;
    const size_t bits_of_mpz = mpz_sizeinbase(mx, 2);
    const size_t length = (bits_of_mpz + BITS_OF_BDIGIT - 1) / BITS_OF_BDIGIT;
    return length;
}

static inline void
BIGNUM_MPZ_NEGATE(VALUE b)
{
    assert(! BIGNUM_EMBED_P(b));
    mpz_neg(BIGNUM_MPZ(b), BIGNUM_MPZ(b));
}
#endif

#endif /* INTERNAL_BIGNUM_H */
