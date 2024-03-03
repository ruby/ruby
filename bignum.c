/**********************************************************************

  bignum.c -

  $Author$
  created at: Fri Jun 10 00:48:55 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/internal/config.h"

#include <ctype.h>
#include <float.h>
#include <math.h>

#ifdef HAVE_STRINGS_H
# include <strings.h>
#endif

#ifdef HAVE_IEEEFP_H
# include <ieeefp.h>
#endif

#if !defined(USE_GMP)
#if defined(HAVE_LIBGMP) && defined(HAVE_GMP_H)
# define USE_GMP 1
#else
# define USE_GMP 0
#endif
#endif
#if USE_GMP
# include <gmp.h>
#endif

#include "id.h"
#include "internal.h"
#include "internal/bignum.h"
#include "internal/complex.h"
#include "internal/gc.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/sanitizers.h"
#include "internal/variable.h"
#include "internal/warnings.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "ruby_assert.h"

static const bool debug_integer_pack = (
#ifdef DEBUG_INTEGER_PACK
    DEBUG_INTEGER_PACK+0
#else
    RUBY_DEBUG
#endif
    ) != 0;

const char ruby_digitmap[] = "0123456789abcdefghijklmnopqrstuvwxyz";

#ifndef SIZEOF_BDIGIT_DBL
# if SIZEOF_INT*2 <= SIZEOF_LONG_LONG
#  define SIZEOF_BDIGIT_DBL SIZEOF_LONG_LONG
# else
#  define SIZEOF_BDIGIT_DBL SIZEOF_LONG
# endif
#endif

STATIC_ASSERT(sizeof_bdigit_dbl, sizeof(BDIGIT_DBL) == SIZEOF_BDIGIT_DBL);
STATIC_ASSERT(sizeof_bdigit_dbl_signed, sizeof(BDIGIT_DBL_SIGNED) == SIZEOF_BDIGIT_DBL);
STATIC_ASSERT(sizeof_bdigit, SIZEOF_BDIGIT <= sizeof(BDIGIT));
STATIC_ASSERT(sizeof_bdigit_and_dbl, SIZEOF_BDIGIT*2 <= SIZEOF_BDIGIT_DBL);
STATIC_ASSERT(bdigit_signedness, 0 < (BDIGIT)-1);
STATIC_ASSERT(bdigit_dbl_signedness, 0 < (BDIGIT_DBL)-1);
STATIC_ASSERT(bdigit_dbl_signed_signedness, 0 > (BDIGIT_DBL_SIGNED)-1);
STATIC_ASSERT(rbignum_embed_len_max, BIGNUM_EMBED_LEN_MAX <= (BIGNUM_EMBED_LEN_MASK >> BIGNUM_EMBED_LEN_SHIFT));

#if SIZEOF_BDIGIT < SIZEOF_LONG
STATIC_ASSERT(sizeof_long_and_sizeof_bdigit, SIZEOF_LONG % SIZEOF_BDIGIT == 0);
#else
STATIC_ASSERT(sizeof_long_and_sizeof_bdigit, SIZEOF_BDIGIT % SIZEOF_LONG == 0);
#endif

#ifdef WORDS_BIGENDIAN
#   define HOST_BIGENDIAN_P 1
#else
#   define HOST_BIGENDIAN_P 0
#endif
/* (!LSHIFTABLE(d, n) ? 0 : (n)) is the same as n but suppress a warning, C4293, by Visual Studio.  */
#define LSHIFTABLE(d, n) ((n) < sizeof(d) * CHAR_BIT)
#define LSHIFTX(d, n) (!LSHIFTABLE(d, n) ? 0 : ((d) << (!LSHIFTABLE(d, n) ? 0 : (n))))
#define CLEAR_LOWBITS(d, numbits) ((d) & LSHIFTX(~((d)*0), (numbits)))
#define FILL_LOWBITS(d, numbits) ((d) | (LSHIFTX(((d)*0+1), (numbits))-1))
#define POW2_P(x) (((x)&((x)-1))==0)

#define BDIGITS(x) (BIGNUM_DIGITS(x))
#define BITSPERDIG (SIZEOF_BDIGIT*CHAR_BIT)
#define BIGRAD ((BDIGIT_DBL)1 << BITSPERDIG)
#define BIGRAD_HALF ((BDIGIT)(BIGRAD >> 1))
#define BDIGIT_MSB(d) (((d) & BIGRAD_HALF) != 0)
#define BIGUP(x) LSHIFTX(((x) + (BDIGIT_DBL)0), BITSPERDIG)
#define BIGDN(x) RSHIFT((x),BITSPERDIG)
#define BIGLO(x) ((BDIGIT)((x) & BDIGMAX))
#define BDIGMAX ((BDIGIT)(BIGRAD-1))
#define BDIGIT_DBL_MAX (~(BDIGIT_DBL)0)

#if SIZEOF_BDIGIT == 2
#   define swap_bdigit(x) swap16(x)
#elif SIZEOF_BDIGIT == 4
#   define swap_bdigit(x) swap32(x)
#elif SIZEOF_BDIGIT == 8
#   define swap_bdigit(x) swap64(x)
#endif

#define BIGZEROP(x) (BIGNUM_LEN(x) == 0 || \
                     (BDIGITS(x)[0] == 0 && \
                      (BIGNUM_LEN(x) == 1 || bigzero_p(x))))
#define BIGSIZE(x) (BIGNUM_LEN(x) == 0 ? (size_t)0 : \
    BDIGITS(x)[BIGNUM_LEN(x)-1] ? \
        (size_t)(BIGNUM_LEN(x)*SIZEOF_BDIGIT - nlz(BDIGITS(x)[BIGNUM_LEN(x)-1])/CHAR_BIT) : \
    rb_absint_size(x, NULL))

#define BIGDIVREM_EXTRA_WORDS 1
#define bdigit_roomof(n) roomof(n, SIZEOF_BDIGIT)
#define BARY_ARGS(ary) ary, numberof(ary)

#define BARY_ADD(z, x, y) bary_add(BARY_ARGS(z), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_SUB(z, x, y) bary_sub(BARY_ARGS(z), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_SHORT_MUL(z, x, y) bary_short_mul(BARY_ARGS(z), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_DIVMOD(q, r, x, y) bary_divmod(BARY_ARGS(q), BARY_ARGS(r), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_ZERO_P(x) bary_zero_p(BARY_ARGS(x))

#define BIGNUM_SET_NEGATIVE_SIGN(b) BIGNUM_SET_SIGN(b, 0)
#define BIGNUM_SET_POSITIVE_SIGN(b) BIGNUM_SET_SIGN(b, 1)

#define bignew(len,sign) bignew_1(rb_cInteger,(len),(sign))

#define BDIGITS_ZERO(ptr, n) do { \
  BDIGIT *bdigitz_zero_ptr = (ptr); \
  size_t bdigitz_zero_n = (n); \
  while (bdigitz_zero_n) { \
    *bdigitz_zero_ptr++ = 0; \
    bdigitz_zero_n--; \
  } \
} while (0)

#define BARY_TRUNC(ds, n) do { \
        while (0 < (n) && (ds)[(n)-1] == 0) \
            (n)--; \
    } while (0)

#define KARATSUBA_BALANCED(xn, yn) ((yn)/2 < (xn))
#define TOOM3_BALANCED(xn, yn) (((yn)+2)/3 * 2 < (xn))

#define GMP_MUL_DIGITS 20
#define KARATSUBA_MUL_DIGITS 70
#define TOOM3_MUL_DIGITS 150

#define GMP_DIV_DIGITS 20
#define GMP_BIG2STR_DIGITS 20
#define GMP_STR2BIG_DIGITS 20
#if USE_GMP
# define NAIVE_MUL_DIGITS GMP_MUL_DIGITS
#else
# define NAIVE_MUL_DIGITS KARATSUBA_MUL_DIGITS
#endif

typedef void (mulfunc_t)(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, BDIGIT *wds, size_t wn);

static mulfunc_t bary_mul_toom3_start;
static mulfunc_t bary_mul_karatsuba_start;
static BDIGIT bigdivrem_single(BDIGIT *qds, const BDIGIT *xds, size_t xn, BDIGIT y);

static VALUE bignew_1(VALUE klass, size_t len, int sign);
static inline VALUE bigtrunc(VALUE x);

static VALUE bigsq(VALUE x);
static inline VALUE power_cache_get_power(int base, int power_level, size_t *numdigits_ret);

#if SIZEOF_BDIGIT <= SIZEOF_INT
static int nlz(BDIGIT x) { return nlz_int((unsigned int)x) - (SIZEOF_INT-SIZEOF_BDIGIT) * CHAR_BIT; }
#elif SIZEOF_BDIGIT <= SIZEOF_LONG
static int nlz(BDIGIT x) { return nlz_long((unsigned long)x) - (SIZEOF_LONG-SIZEOF_BDIGIT) * CHAR_BIT; }
#elif SIZEOF_BDIGIT <= SIZEOF_LONG_LONG
static int nlz(BDIGIT x) { return nlz_long_long((unsigned LONG_LONG)x) - (SIZEOF_LONG_LONG-SIZEOF_BDIGIT) * CHAR_BIT; }
#elif SIZEOF_BDIGIT <= SIZEOF_INT128_T
static int nlz(BDIGIT x) { return nlz_int128((uint128_t)x) - (SIZEOF_INT128_T-SIZEOF_BDIGIT) * CHAR_BIT; }
#endif

#define U16(a) ((uint16_t)(a))
#define U32(a) ((uint32_t)(a))
#ifdef HAVE_UINT64_T
#define U64(a,b) (((uint64_t)(a) << 32) | (b))
#endif
#ifdef HAVE_UINT128_T
#define U128(a,b,c,d) (((uint128_t)U64(a,b) << 64) | U64(c,d))
#endif

/* The following script, maxpow.rb, generates the tables follows.

def big(n, bits)
  ns = []
  ((bits+31)/32).times {
    ns << sprintf("0x%08x", n & 0xffff_ffff)
    n >>= 32
  }
  "U#{bits}(" + ns.reverse.join(",") + ")"
end
def values(ary, width, indent)
  lines = [""]
  ary.each {|e|
    lines << "" if !ary.last.empty? && width < (lines.last + e + ", ").length
    lines.last << e + ", "
  }
  lines.map {|line| " " * indent + line.chomp(" ") + "\n" }.join
end
[16,32,64,128].each {|bits|
  max = 2**bits-1
  exps = []
  nums = []
  2.upto(36) {|base|
    exp = 0
    n = 1
    while n * base <= max
      exp += 1
      n *= base
    end
    exps << exp.to_s
    nums << big(n, bits)
  }
  puts "#ifdef HAVE_UINT#{bits}_T"
  puts "static const int maxpow#{bits}_exp[35] = {"
  print values(exps, 70, 4)
  puts "};"
  puts "static const uint#{bits}_t maxpow#{bits}_num[35] = {"
  print values(nums, 70, 4)
  puts "};"
  puts "#endif"
}

 */

#if SIZEOF_BDIGIT_DBL == 2
static const int maxpow16_exp[35] = {
    15, 10, 7, 6, 6, 5, 5, 5, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
};
static const uint16_t maxpow16_num[35] = {
    U16(0x00008000), U16(0x0000e6a9), U16(0x00004000), U16(0x00003d09),
    U16(0x0000b640), U16(0x000041a7), U16(0x00008000), U16(0x0000e6a9),
    U16(0x00002710), U16(0x00003931), U16(0x00005100), U16(0x00006f91),
    U16(0x00009610), U16(0x0000c5c1), U16(0x00001000), U16(0x00001331),
    U16(0x000016c8), U16(0x00001acb), U16(0x00001f40), U16(0x0000242d),
    U16(0x00002998), U16(0x00002f87), U16(0x00003600), U16(0x00003d09),
    U16(0x000044a8), U16(0x00004ce3), U16(0x000055c0), U16(0x00005f45),
    U16(0x00006978), U16(0x0000745f), U16(0x00008000), U16(0x00008c61),
    U16(0x00009988), U16(0x0000a77b), U16(0x0000b640),
};
#elif SIZEOF_BDIGIT_DBL == 4
static const int maxpow32_exp[35] = {
    31, 20, 15, 13, 12, 11, 10, 10, 9, 9, 8, 8, 8, 8, 7, 7, 7, 7, 7, 7,
    7, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
};
static const uint32_t maxpow32_num[35] = {
    U32(0x80000000), U32(0xcfd41b91), U32(0x40000000), U32(0x48c27395),
    U32(0x81bf1000), U32(0x75db9c97), U32(0x40000000), U32(0xcfd41b91),
    U32(0x3b9aca00), U32(0x8c8b6d2b), U32(0x19a10000), U32(0x309f1021),
    U32(0x57f6c100), U32(0x98c29b81), U32(0x10000000), U32(0x18754571),
    U32(0x247dbc80), U32(0x3547667b), U32(0x4c4b4000), U32(0x6b5a6e1d),
    U32(0x94ace180), U32(0xcaf18367), U32(0x0b640000), U32(0x0e8d4a51),
    U32(0x1269ae40), U32(0x17179149), U32(0x1cb91000), U32(0x23744899),
    U32(0x2b73a840), U32(0x34e63b41), U32(0x40000000), U32(0x4cfa3cc1),
    U32(0x5c13d840), U32(0x6d91b519), U32(0x81bf1000),
};
#elif SIZEOF_BDIGIT_DBL == 8 && defined HAVE_UINT64_T
static const int maxpow64_exp[35] = {
    63, 40, 31, 27, 24, 22, 21, 20, 19, 18, 17, 17, 16, 16, 15, 15, 15,
    15, 14, 14, 14, 14, 13, 13, 13, 13, 13, 13, 13, 12, 12, 12, 12, 12,
    12,
};
static const uint64_t maxpow64_num[35] = {
    U64(0x80000000,0x00000000), U64(0xa8b8b452,0x291fe821),
    U64(0x40000000,0x00000000), U64(0x6765c793,0xfa10079d),
    U64(0x41c21cb8,0xe1000000), U64(0x36427987,0x50226111),
    U64(0x80000000,0x00000000), U64(0xa8b8b452,0x291fe821),
    U64(0x8ac72304,0x89e80000), U64(0x4d28cb56,0xc33fa539),
    U64(0x1eca170c,0x00000000), U64(0x780c7372,0x621bd74d),
    U64(0x1e39a505,0x7d810000), U64(0x5b27ac99,0x3df97701),
    U64(0x10000000,0x00000000), U64(0x27b95e99,0x7e21d9f1),
    U64(0x5da0e1e5,0x3c5c8000), U64(0xd2ae3299,0xc1c4aedb),
    U64(0x16bcc41e,0x90000000), U64(0x2d04b7fd,0xd9c0ef49),
    U64(0x5658597b,0xcaa24000), U64(0xa0e20737,0x37609371),
    U64(0x0c29e980,0x00000000), U64(0x14adf4b7,0x320334b9),
    U64(0x226ed364,0x78bfa000), U64(0x383d9170,0xb85ff80b),
    U64(0x5a3c23e3,0x9c000000), U64(0x8e651373,0x88122bcd),
    U64(0xdd41bb36,0xd259e000), U64(0x0aee5720,0xee830681),
    U64(0x10000000,0x00000000), U64(0x172588ad,0x4f5f0981),
    U64(0x211e44f7,0xd02c1000), U64(0x2ee56725,0xf06e5c71),
    U64(0x41c21cb8,0xe1000000),
};
#elif SIZEOF_BDIGIT_DBL == 16 && defined HAVE_UINT128_T
static const int maxpow128_exp[35] = {
    127, 80, 63, 55, 49, 45, 42, 40, 38, 37, 35, 34, 33, 32, 31, 31, 30,
    30, 29, 29, 28, 28, 27, 27, 27, 26, 26, 26, 26, 25, 25, 25, 25, 24,
    24,
};
static const uint128_t maxpow128_num[35] = {
    U128(0x80000000,0x00000000,0x00000000,0x00000000),
    U128(0x6f32f1ef,0x8b18a2bc,0x3cea5978,0x9c79d441),
    U128(0x40000000,0x00000000,0x00000000,0x00000000),
    U128(0xd0cf4b50,0xcfe20765,0xfff4b4e3,0xf741cf6d),
    U128(0x6558e2a0,0x921fe069,0x42860000,0x00000000),
    U128(0x5080c7b7,0xd0e31ba7,0x5911a67d,0xdd3d35e7),
    U128(0x40000000,0x00000000,0x00000000,0x00000000),
    U128(0x6f32f1ef,0x8b18a2bc,0x3cea5978,0x9c79d441),
    U128(0x4b3b4ca8,0x5a86c47a,0x098a2240,0x00000000),
    U128(0xffd1390a,0x0adc2fb8,0xdabbb817,0x4d95c99b),
    U128(0x2c6fdb36,0x4c25e6c0,0x00000000,0x00000000),
    U128(0x384bacd6,0x42c343b4,0xe90c4272,0x13506d29),
    U128(0x31f5db32,0xa34aced6,0x0bf13a0e,0x00000000),
    U128(0x20753ada,0xfd1e839f,0x53686d01,0x3143ee01),
    U128(0x10000000,0x00000000,0x00000000,0x00000000),
    U128(0x68ca11d6,0xb4f6d1d1,0xfaa82667,0x8073c2f1),
    U128(0x223e493b,0xb3bb69ff,0xa4b87d6c,0x40000000),
    U128(0xad62418d,0x14ea8247,0x01c4b488,0x6cc66f59),
    U128(0x2863c1f5,0xcdae42f9,0x54000000,0x00000000),
    U128(0xa63fd833,0xb9386b07,0x36039e82,0xbe651b25),
    U128(0x1d1f7a9c,0xd087a14d,0x28cdf3d5,0x10000000),
    U128(0x651b5095,0xc2ea8fc1,0xb30e2c57,0x77aaf7e1),
    U128(0x0ddef20e,0xff760000,0x00000000,0x00000000),
    U128(0x29c30f10,0x29939b14,0x6664242d,0x97d9f649),
    U128(0x786a435a,0xe9558b0e,0x6aaf6d63,0xa8000000),
    U128(0x0c5afe6f,0xf302bcbf,0x94fd9829,0xd87f5079),
    U128(0x1fce575c,0xe1692706,0x07100000,0x00000000),
    U128(0x4f34497c,0x8597e144,0x36e91802,0x00528229),
    U128(0xbf3a8e1d,0x41ef2170,0x7802130d,0x84000000),
    U128(0x0e7819e1,0x7f1eb0fb,0x6ee4fb89,0x01d9531f),
    U128(0x20000000,0x00000000,0x00000000,0x00000000),
    U128(0x4510460d,0xd9e879c0,0x14a82375,0x2f22b321),
    U128(0x91abce3c,0x4b4117ad,0xe76d35db,0x22000000),
    U128(0x08973ea3,0x55d75bc2,0x2e42c391,0x727d69e1),
    U128(0x10e425c5,0x6daffabc,0x35c10000,0x00000000),
};
#endif

static BDIGIT_DBL
maxpow_in_bdigit_dbl(int base, int *exp_ret)
{
    BDIGIT_DBL maxpow;
    int exponent;

    RUBY_ASSERT(2 <= base && base <= 36);

    {
#if SIZEOF_BDIGIT_DBL == 2
        maxpow = maxpow16_num[base-2];
        exponent = maxpow16_exp[base-2];
#elif SIZEOF_BDIGIT_DBL == 4
        maxpow = maxpow32_num[base-2];
        exponent = maxpow32_exp[base-2];
#elif SIZEOF_BDIGIT_DBL == 8 && defined HAVE_UINT64_T
        maxpow = maxpow64_num[base-2];
        exponent = maxpow64_exp[base-2];
#elif SIZEOF_BDIGIT_DBL == 16 && defined HAVE_UINT128_T
        maxpow = maxpow128_num[base-2];
        exponent = maxpow128_exp[base-2];
#else
        maxpow = base;
        exponent = 1;
        while (maxpow <= BDIGIT_DBL_MAX / base) {
            maxpow *= base;
            exponent++;
        }
#endif
    }

    *exp_ret = exponent;
    return maxpow;
}

static inline BDIGIT_DBL
bary2bdigitdbl(const BDIGIT *ds, size_t n)
{
    RUBY_ASSERT(n <= 2);

    if (n == 2)
        return ds[0] | BIGUP(ds[1]);
    if (n == 1)
        return ds[0];
    return 0;
}

static inline void
bdigitdbl2bary(BDIGIT *ds, size_t n, BDIGIT_DBL num)
{
    RUBY_ASSERT(n == 2);

    ds[0] = BIGLO(num);
    ds[1] = (BDIGIT)BIGDN(num);
}

static int
bary_cmp(const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    size_t i;
    BARY_TRUNC(xds, xn);
    BARY_TRUNC(yds, yn);

    if (xn < yn)
        return -1;
    if (xn > yn)
        return 1;

    for (i = 0; i < xn; i++)
        if (xds[xn - i - 1] != yds[yn - i - 1])
            break;
    if (i == xn)
        return 0;
    return xds[xn - i - 1] < yds[yn - i - 1] ? -1 : 1;
}

static BDIGIT
bary_small_lshift(BDIGIT *zds, const BDIGIT *xds, size_t n, int shift)
{
    size_t i;
    BDIGIT_DBL num = 0;
    RUBY_ASSERT(0 <= shift && shift < BITSPERDIG);

    for (i=0; i<n; i++) {
        num = num | (BDIGIT_DBL)*xds++ << shift;
        *zds++ = BIGLO(num);
        num = BIGDN(num);
    }
    return BIGLO(num);
}

static void
bary_small_rshift(BDIGIT *zds, const BDIGIT *xds, size_t n, int shift, BDIGIT higher_bdigit)
{
    size_t i;
    BDIGIT_DBL num = 0;

    RUBY_ASSERT(0 <= shift && shift < BITSPERDIG);

    num = BIGUP(higher_bdigit);
    for (i = 0; i < n; i++) {
        BDIGIT x = xds[n - i - 1];
        num = (num | x) >> shift;
        zds[n - i - 1] = BIGLO(num);
        num = BIGUP(x);
    }
}

static int
bary_zero_p(const BDIGIT *xds, size_t xn)
{
    if (xn == 0)
        return 1;
    do {
        if (xds[--xn]) return 0;
    } while (xn);
    return 1;
}

static void
bary_neg(BDIGIT *ds, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++)
        ds[n - i - 1] = BIGLO(~ds[n - i - 1]);
}

static int
bary_2comp(BDIGIT *ds, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++) {
        if (ds[i] != 0) {
            goto non_zero;
        }
    }
    return 1;

  non_zero:
    ds[i] = BIGLO(~ds[i] + 1);
    i++;
    for (; i < n; i++) {
        ds[i] = BIGLO(~ds[i]);
    }
    return 0;
}

static void
bary_swap(BDIGIT *ds, size_t num_bdigits)
{
    BDIGIT *p1 = ds;
    BDIGIT *p2 = ds + num_bdigits - 1;
    for (; p1 < p2; p1++, p2--) {
        BDIGIT tmp = *p1;
        *p1 = *p2;
        *p2 = tmp;
    }
}

#define INTEGER_PACK_WORDORDER_MASK \
    (INTEGER_PACK_MSWORD_FIRST | \
     INTEGER_PACK_LSWORD_FIRST)
#define INTEGER_PACK_BYTEORDER_MASK \
    (INTEGER_PACK_MSBYTE_FIRST | \
     INTEGER_PACK_LSBYTE_FIRST | \
     INTEGER_PACK_NATIVE_BYTE_ORDER)

static void
validate_integer_pack_format(size_t numwords, size_t wordsize, size_t nails, int flags, int supported_flags)
{
    int wordorder_bits = flags & INTEGER_PACK_WORDORDER_MASK;
    int byteorder_bits = flags & INTEGER_PACK_BYTEORDER_MASK;

    if (flags & ~supported_flags) {
        rb_raise(rb_eArgError, "unsupported flags specified");
    }
    if (wordorder_bits == 0) {
        if (1 < numwords)
            rb_raise(rb_eArgError, "word order not specified");
    }
    else if (wordorder_bits != INTEGER_PACK_MSWORD_FIRST &&
        wordorder_bits != INTEGER_PACK_LSWORD_FIRST)
        rb_raise(rb_eArgError, "unexpected word order");
    if (byteorder_bits == 0) {
        rb_raise(rb_eArgError, "byte order not specified");
    }
    else if (byteorder_bits != INTEGER_PACK_MSBYTE_FIRST &&
        byteorder_bits != INTEGER_PACK_LSBYTE_FIRST &&
        byteorder_bits != INTEGER_PACK_NATIVE_BYTE_ORDER)
        rb_raise(rb_eArgError, "unexpected byte order");
    if (wordsize == 0)
        rb_raise(rb_eArgError, "invalid wordsize: %"PRI_SIZE_PREFIX"u", wordsize);
    if (SSIZE_MAX < wordsize)
        rb_raise(rb_eArgError, "too big wordsize: %"PRI_SIZE_PREFIX"u", wordsize);
    if (wordsize <= nails / CHAR_BIT)
        rb_raise(rb_eArgError, "too big nails: %"PRI_SIZE_PREFIX"u", nails);
    if (SIZE_MAX / wordsize < numwords)
        rb_raise(rb_eArgError, "too big numwords * wordsize: %"PRI_SIZE_PREFIX"u * %"PRI_SIZE_PREFIX"u", numwords, wordsize);
}

static void
integer_pack_loop_setup(
    size_t numwords, size_t wordsize, size_t nails, int flags,
    size_t *word_num_fullbytes_ret,
    int *word_num_partialbits_ret,
    size_t *word_start_ret,
    ssize_t *word_step_ret,
    size_t *word_last_ret,
    size_t *byte_start_ret,
    int *byte_step_ret)
{
    int wordorder_bits = flags & INTEGER_PACK_WORDORDER_MASK;
    int byteorder_bits = flags & INTEGER_PACK_BYTEORDER_MASK;
    size_t word_num_fullbytes;
    int word_num_partialbits;
    size_t word_start;
    ssize_t word_step;
    size_t word_last;
    size_t byte_start;
    int byte_step;

    word_num_partialbits = CHAR_BIT - (int)(nails % CHAR_BIT);
    if (word_num_partialbits == CHAR_BIT)
        word_num_partialbits = 0;
    word_num_fullbytes = wordsize - (nails / CHAR_BIT);
    if (word_num_partialbits != 0) {
        word_num_fullbytes--;
    }

    if (wordorder_bits == INTEGER_PACK_MSWORD_FIRST) {
        word_start = wordsize*(numwords-1);
        word_step = -(ssize_t)wordsize;
        word_last = 0;
    }
    else {
        word_start = 0;
        word_step = wordsize;
        word_last = wordsize*(numwords-1);
    }

    if (byteorder_bits == INTEGER_PACK_NATIVE_BYTE_ORDER) {
#ifdef WORDS_BIGENDIAN
        byteorder_bits = INTEGER_PACK_MSBYTE_FIRST;
#else
        byteorder_bits = INTEGER_PACK_LSBYTE_FIRST;
#endif
    }
    if (byteorder_bits == INTEGER_PACK_MSBYTE_FIRST) {
        byte_start = wordsize-1;
        byte_step = -1;
    }
    else {
        byte_start = 0;
        byte_step = 1;
    }

    *word_num_partialbits_ret = word_num_partialbits;
    *word_num_fullbytes_ret = word_num_fullbytes;
    *word_start_ret = word_start;
    *word_step_ret = word_step;
    *word_last_ret = word_last;
    *byte_start_ret = byte_start;
    *byte_step_ret = byte_step;
}

static inline void
integer_pack_fill_dd(BDIGIT **dpp, BDIGIT **dep, BDIGIT_DBL *ddp, int *numbits_in_dd_p)
{
    if (*dpp < *dep && BITSPERDIG <= (int)sizeof(*ddp) * CHAR_BIT - *numbits_in_dd_p) {
        *ddp |= (BDIGIT_DBL)(*(*dpp)++) << *numbits_in_dd_p;
        *numbits_in_dd_p += BITSPERDIG;
    }
    else if (*dpp == *dep) {
        /* higher bits are infinity zeros */
        *numbits_in_dd_p = (int)sizeof(*ddp) * CHAR_BIT;
    }
}

static inline BDIGIT_DBL
integer_pack_take_lowbits(int n, BDIGIT_DBL *ddp, int *numbits_in_dd_p)
{
    BDIGIT_DBL ret;
    ret = (*ddp) & (((BDIGIT_DBL)1 << n) - 1);
    *ddp >>= n;
    *numbits_in_dd_p -= n;
    return ret;
}

#if !defined(WORDS_BIGENDIAN)
static int
bytes_2comp(unsigned char *buf, size_t len)
{
    size_t i;
    for (i = 0; i < len; i++) {
        signed char c = buf[i];
        signed int d = ~c;
        unsigned int e = d & 0xFF;
        buf[i] = e;
    }
    for (i = 0; i < len; i++) {
        buf[i]++;
        if (buf[i] != 0)
            return 0;
    }
    return 1;
}
#endif

static int
bary_pack(int sign, BDIGIT *ds, size_t num_bdigits, void *words, size_t numwords, size_t wordsize, size_t nails, int flags)
{
    BDIGIT *dp, *de;
    unsigned char *buf, *bufend;

    dp = ds;
    de = ds + num_bdigits;

    validate_integer_pack_format(numwords, wordsize, nails, flags,
            INTEGER_PACK_MSWORD_FIRST|
            INTEGER_PACK_LSWORD_FIRST|
            INTEGER_PACK_MSBYTE_FIRST|
            INTEGER_PACK_LSBYTE_FIRST|
            INTEGER_PACK_NATIVE_BYTE_ORDER|
            INTEGER_PACK_2COMP|
            INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION);

    while (dp < de && de[-1] == 0)
        de--;
    if (dp == de) {
        sign = 0;
    }

    if (!(flags & INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION)) {
        if (sign == 0) {
            MEMZERO(words, unsigned char, numwords * wordsize);
            return 0;
        }
        if (nails == 0 && numwords == 1) {
            int need_swap = wordsize != 1 &&
                (flags & INTEGER_PACK_BYTEORDER_MASK) != INTEGER_PACK_NATIVE_BYTE_ORDER &&
                ((flags & INTEGER_PACK_MSBYTE_FIRST) ? !HOST_BIGENDIAN_P : HOST_BIGENDIAN_P);
            if (0 < sign || !(flags & INTEGER_PACK_2COMP)) {
                BDIGIT d;
                if (wordsize == 1) {
                    *((unsigned char *)words) = (unsigned char)(d = dp[0]);
                    return ((1 < de - dp || CLEAR_LOWBITS(d, 8) != 0) ? 2 : 1) * sign;
                }
#if defined(HAVE_UINT16_T) && 2 <= SIZEOF_BDIGIT
                if (wordsize == 2 && (uintptr_t)words % RUBY_ALIGNOF(uint16_t) == 0) {
                    uint16_t u = (uint16_t)(d = dp[0]);
                    if (need_swap) u = swap16(u);
                    *((uint16_t *)words) = u;
                    return ((1 < de - dp || CLEAR_LOWBITS(d, 16) != 0) ? 2 : 1) * sign;
                }
#endif
#if defined(HAVE_UINT32_T) && 4 <= SIZEOF_BDIGIT
                if (wordsize == 4 && (uintptr_t)words % RUBY_ALIGNOF(uint32_t) == 0) {
                    uint32_t u = (uint32_t)(d = dp[0]);
                    if (need_swap) u = swap32(u);
                    *((uint32_t *)words) = u;
                    return ((1 < de - dp || CLEAR_LOWBITS(d, 32) != 0) ? 2 : 1) * sign;
                }
#endif
#if defined(HAVE_UINT64_T) && 8 <= SIZEOF_BDIGIT
                if (wordsize == 8 && (uintptr_t)words % RUBY_ALIGNOF(uint64_t) == 0) {
                    uint64_t u = (uint64_t)(d = dp[0]);
                    if (need_swap) u = swap64(u);
                    *((uint64_t *)words) = u;
                    return ((1 < de - dp || CLEAR_LOWBITS(d, 64) != 0) ? 2 : 1) * sign;
                }
#endif
            }
            else { /* sign < 0 && (flags & INTEGER_PACK_2COMP) */
                BDIGIT_DBL_SIGNED d;
                if (wordsize == 1) {
                    *((unsigned char *)words) = (unsigned char)(d = -(BDIGIT_DBL_SIGNED)dp[0]);
                    return (1 < de - dp || FILL_LOWBITS(d, 8) != -1) ? -2 : -1;
                }
#if defined(HAVE_UINT16_T) && 2 <= SIZEOF_BDIGIT
                if (wordsize == 2 && (uintptr_t)words % RUBY_ALIGNOF(uint16_t) == 0) {
                    uint16_t u = (uint16_t)(d = -(BDIGIT_DBL_SIGNED)dp[0]);
                    if (need_swap) u = swap16(u);
                    *((uint16_t *)words) = u;
                    return (wordsize == SIZEOF_BDIGIT && de - dp == 2 && dp[1] == 1 && dp[0] == 0) ? -1 :
                        (1 < de - dp || FILL_LOWBITS(d, 16) != -1) ? -2 : -1;
                }
#endif
#if defined(HAVE_UINT32_T) && 4 <= SIZEOF_BDIGIT
                if (wordsize == 4 && (uintptr_t)words % RUBY_ALIGNOF(uint32_t) == 0) {
                    uint32_t u = (uint32_t)(d = -(BDIGIT_DBL_SIGNED)dp[0]);
                    if (need_swap) u = swap32(u);
                    *((uint32_t *)words) = u;
                    return (wordsize == SIZEOF_BDIGIT && de - dp == 2 && dp[1] == 1 && dp[0] == 0) ? -1 :
                        (1 < de - dp || FILL_LOWBITS(d, 32) != -1) ? -2 : -1;
                }
#endif
#if defined(HAVE_UINT64_T) && 8 <= SIZEOF_BDIGIT
                if (wordsize == 8 && (uintptr_t)words % RUBY_ALIGNOF(uint64_t) == 0) {
                    uint64_t u = (uint64_t)(d = -(BDIGIT_DBL_SIGNED)dp[0]);
                    if (need_swap) u = swap64(u);
                    *((uint64_t *)words) = u;
                    return (wordsize == SIZEOF_BDIGIT && de - dp == 2 && dp[1] == 1 && dp[0] == 0) ? -1 :
                        (1 < de - dp || FILL_LOWBITS(d, 64) != -1) ? -2 : -1;
                }
#endif
            }
        }
#if !defined(WORDS_BIGENDIAN)
        if (nails == 0 && SIZEOF_BDIGIT == sizeof(BDIGIT) &&
            (flags & INTEGER_PACK_WORDORDER_MASK) == INTEGER_PACK_LSWORD_FIRST &&
            (flags & INTEGER_PACK_BYTEORDER_MASK) != INTEGER_PACK_MSBYTE_FIRST) {
            size_t src_size = (de - dp) * SIZEOF_BDIGIT;
            size_t dst_size = numwords * wordsize;
            int overflow = 0;
            while (0 < src_size && ((unsigned char *)ds)[src_size-1] == 0)
                src_size--;
            if (src_size <= dst_size) {
                MEMCPY(words, dp, char, src_size);
                MEMZERO((char*)words + src_size, char, dst_size - src_size);
            }
            else {
                MEMCPY(words, dp, char, dst_size);
                overflow = 1;
            }
            if (sign < 0 && (flags & INTEGER_PACK_2COMP)) {
                int zero_p = bytes_2comp(words, dst_size);
                if (zero_p && overflow) {
                    unsigned char *p = (unsigned char *)dp;
                    if (dst_size == src_size-1 &&
                        p[dst_size] == 1) {
                        overflow = 0;
                    }
                }
            }
            if (overflow)
                sign *= 2;
            return sign;
        }
#endif
        if (nails == 0 && SIZEOF_BDIGIT == sizeof(BDIGIT) &&
            wordsize % SIZEOF_BDIGIT == 0 && (uintptr_t)words % RUBY_ALIGNOF(BDIGIT) == 0) {
            size_t bdigits_per_word = wordsize / SIZEOF_BDIGIT;
            size_t src_num_bdigits = de - dp;
            size_t dst_num_bdigits = numwords * bdigits_per_word;
            int overflow = 0;
            int mswordfirst_p = (flags & INTEGER_PACK_MSWORD_FIRST) != 0;
            int msbytefirst_p = (flags & INTEGER_PACK_NATIVE_BYTE_ORDER) ? HOST_BIGENDIAN_P :
                (flags & INTEGER_PACK_MSBYTE_FIRST) != 0;
            if (src_num_bdigits <= dst_num_bdigits) {
                MEMCPY(words, dp, BDIGIT, src_num_bdigits);
                BDIGITS_ZERO((BDIGIT*)words + src_num_bdigits, dst_num_bdigits - src_num_bdigits);
            }
            else {
                MEMCPY(words, dp, BDIGIT, dst_num_bdigits);
                overflow = 1;
            }
            if (sign < 0 && (flags & INTEGER_PACK_2COMP)) {
                int zero_p = bary_2comp(words, dst_num_bdigits);
                if (zero_p && overflow &&
                    dst_num_bdigits == src_num_bdigits-1 &&
                    dp[dst_num_bdigits] == 1)
                    overflow = 0;
            }
            if (msbytefirst_p != HOST_BIGENDIAN_P) {
                size_t i;
                for (i = 0; i < dst_num_bdigits; i++) {
                    BDIGIT d = ((BDIGIT*)words)[i];
                    ((BDIGIT*)words)[i] = swap_bdigit(d);
                }
            }
            if (mswordfirst_p ? !msbytefirst_p : msbytefirst_p) {
                size_t i;
                BDIGIT *p = words;
                for (i = 0; i < numwords; i++) {
                    bary_swap(p, bdigits_per_word);
                    p += bdigits_per_word;
                }
            }
            if (mswordfirst_p) {
                bary_swap(words, dst_num_bdigits);
            }
            if (overflow)
                sign *= 2;
            return sign;
        }
    }

    buf = words;
    bufend = buf + numwords * wordsize;

    if (buf == bufend) {
        /* overflow if non-zero*/
        if (!(flags & INTEGER_PACK_2COMP) || 0 <= sign)
            sign *= 2;
        else {
            if (de - dp == 1 && dp[0] == 1)
                sign = -1; /* val == -1 == -2**(numwords*(wordsize*CHAR_BIT-nails)) */
            else
                sign = -2; /* val < -1 == -2**(numwords*(wordsize*CHAR_BIT-nails)) */
        }
    }
    else if (dp == de) {
        memset(buf, '\0', bufend - buf);
    }
    else if (dp < de && buf < bufend) {
        int word_num_partialbits;
        size_t word_num_fullbytes;

        ssize_t word_step;
        size_t byte_start;
        int byte_step;

        size_t word_start, word_last;
        unsigned char *wordp, *last_wordp;
        BDIGIT_DBL dd;
        int numbits_in_dd;

        integer_pack_loop_setup(numwords, wordsize, nails, flags,
            &word_num_fullbytes, &word_num_partialbits,
            &word_start, &word_step, &word_last, &byte_start, &byte_step);

        wordp = buf + word_start;
        last_wordp = buf + word_last;

        dd = 0;
        numbits_in_dd = 0;

#define FILL_DD \
    integer_pack_fill_dd(&dp, &de, &dd, &numbits_in_dd)
#define TAKE_LOWBITS(n) \
    integer_pack_take_lowbits(n, &dd, &numbits_in_dd)

        while (1) {
            size_t index_in_word = 0;
            unsigned char *bytep = wordp + byte_start;
            while (index_in_word < word_num_fullbytes) {
                FILL_DD;
                *bytep = TAKE_LOWBITS(CHAR_BIT);
                bytep += byte_step;
                index_in_word++;
            }
            if (word_num_partialbits) {
                FILL_DD;
                *bytep = TAKE_LOWBITS(word_num_partialbits);
                bytep += byte_step;
                index_in_word++;
            }
            while (index_in_word < wordsize) {
                *bytep = 0;
                bytep += byte_step;
                index_in_word++;
            }

            if (wordp == last_wordp)
                break;

            wordp += word_step;
        }
        FILL_DD;
        /* overflow tests */
        if (dp != de || 1 < dd) {
            /* 2**(numwords*(wordsize*CHAR_BIT-nails)+1) <= abs(val) */
            sign *= 2;
        }
        else if (dd == 1) {
            /* 2**(numwords*(wordsize*CHAR_BIT-nails)) <= abs(val) < 2**(numwords*(wordsize*CHAR_BIT-nails)+1) */
            if (!(flags & INTEGER_PACK_2COMP) || 0 <= sign)
                sign *= 2;
            else { /* overflow_2comp && sign == -1 */
                /* test lower bits are all zero. */
                dp = ds;
                while (dp < de && *dp == 0)
                    dp++;
                if (de - dp == 1 && /* only one non-zero word. */
                    POW2_P(*dp)) /* *dp contains only one bit set. */
                    sign = -1; /* val == -2**(numwords*(wordsize*CHAR_BIT-nails)) */
                else
                    sign = -2; /* val < -2**(numwords*(wordsize*CHAR_BIT-nails)) */
            }
        }
    }

    if ((flags & INTEGER_PACK_2COMP) && (sign < 0 && numwords != 0)) {
        int word_num_partialbits;
        size_t word_num_fullbytes;

        ssize_t word_step;
        size_t byte_start;
        int byte_step;

        size_t word_start, word_last;
        unsigned char *wordp, *last_wordp;

        unsigned int partialbits_mask;
        int carry;

        integer_pack_loop_setup(numwords, wordsize, nails, flags,
            &word_num_fullbytes, &word_num_partialbits,
            &word_start, &word_step, &word_last, &byte_start, &byte_step);

        partialbits_mask = (1 << word_num_partialbits) - 1;

        buf = words;
        wordp = buf + word_start;
        last_wordp = buf + word_last;

        carry = 1;
        while (1) {
            size_t index_in_word = 0;
            unsigned char *bytep = wordp + byte_start;
            while (index_in_word < word_num_fullbytes) {
                carry += (unsigned char)~*bytep;
                *bytep = (unsigned char)carry;
                carry >>= CHAR_BIT;
                bytep += byte_step;
                index_in_word++;
            }
            if (word_num_partialbits) {
                carry += (*bytep & partialbits_mask) ^ partialbits_mask;
                *bytep = carry & partialbits_mask;
                carry >>= word_num_partialbits;
                bytep += byte_step;
                index_in_word++;
            }

            if (wordp == last_wordp)
                break;

            wordp += word_step;
        }
    }

    return sign;
#undef FILL_DD
#undef TAKE_LOWBITS
}

static size_t
integer_unpack_num_bdigits_small(size_t numwords, size_t wordsize, size_t nails, int *nlp_bits_ret)
{
    /* nlp_bits stands for number of leading padding bits */
    size_t num_bits = (wordsize * CHAR_BIT - nails) * numwords;
    size_t num_bdigits = roomof(num_bits, BITSPERDIG);
    *nlp_bits_ret = (int)(num_bdigits * BITSPERDIG - num_bits);
    return num_bdigits;
}

static size_t
integer_unpack_num_bdigits_generic(size_t numwords, size_t wordsize, size_t nails, int *nlp_bits_ret)
{
    /* BITSPERDIG = SIZEOF_BDIGIT * CHAR_BIT */
    /* num_bits = (wordsize * CHAR_BIT - nails) * numwords */
    /* num_bdigits = roomof(num_bits, BITSPERDIG) */

    /* num_bits = CHAR_BIT * (wordsize * numwords) - nails * numwords = CHAR_BIT * num_bytes1 - nails * numwords */
    size_t num_bytes1 = wordsize * numwords;

    /* q1 * CHAR_BIT + r1 = numwords */
    size_t q1 = numwords / CHAR_BIT;
    size_t r1 = numwords % CHAR_BIT;

    /* num_bits = CHAR_BIT * num_bytes1 - nails * (q1 * CHAR_BIT + r1) = CHAR_BIT * num_bytes2 - nails * r1 */
    size_t num_bytes2 = num_bytes1 - nails * q1;

    /* q2 * CHAR_BIT + r2 = nails */
    size_t q2 = nails / CHAR_BIT;
    size_t r2 = nails % CHAR_BIT;

    /* num_bits = CHAR_BIT * num_bytes2 - (q2 * CHAR_BIT + r2) * r1 = CHAR_BIT * num_bytes3 - r1 * r2 */
    size_t num_bytes3 = num_bytes2 - q2 * r1;

    /* q3 * BITSPERDIG + r3 = num_bytes3 */
    size_t q3 = num_bytes3 / BITSPERDIG;
    size_t r3 = num_bytes3 % BITSPERDIG;

    /* num_bits = CHAR_BIT * (q3 * BITSPERDIG + r3) - r1 * r2 = BITSPERDIG * num_digits1 + CHAR_BIT * r3 - r1 * r2 */
    size_t num_digits1 = CHAR_BIT * q3;

    /*
     * if CHAR_BIT * r3 >= r1 * r2
     *   CHAR_BIT * r3 - r1 * r2 = CHAR_BIT * BITSPERDIG - (CHAR_BIT * BITSPERDIG - (CHAR_BIT * r3 - r1 * r2))
     *   q4 * BITSPERDIG + r4 = CHAR_BIT * BITSPERDIG - (CHAR_BIT * r3 - r1 * r2)
     *   num_bits = BITSPERDIG * num_digits1 + CHAR_BIT * BITSPERDIG - (q4 * BITSPERDIG + r4) = BITSPERDIG * num_digits2 - r4
     * else
     *   q4 * BITSPERDIG + r4 = -(CHAR_BIT * r3 - r1 * r2)
     *   num_bits = BITSPERDIG * num_digits1 - (q4 * BITSPERDIG + r4) = BITSPERDIG * num_digits2 - r4
     * end
     */

    if (CHAR_BIT * r3 >= r1 * r2) {
        size_t tmp1 = CHAR_BIT * BITSPERDIG - (CHAR_BIT * r3 - r1 * r2);
        size_t q4 = tmp1 / BITSPERDIG;
        int r4 = (int)(tmp1 % BITSPERDIG);
        size_t num_digits2 = num_digits1 + CHAR_BIT - q4;
        *nlp_bits_ret = r4;
        return num_digits2;
    }
    else {
        size_t tmp1 = r1 * r2 - CHAR_BIT * r3;
        size_t q4 = tmp1 / BITSPERDIG;
        int r4 = (int)(tmp1 % BITSPERDIG);
        size_t num_digits2 = num_digits1 - q4;
        *nlp_bits_ret = r4;
        return num_digits2;
    }
}

static size_t
integer_unpack_num_bdigits(size_t numwords, size_t wordsize, size_t nails, int *nlp_bits_ret)
{
    size_t num_bdigits;

    if (numwords <= (SIZE_MAX - (BITSPERDIG-1)) / CHAR_BIT / wordsize) {
        num_bdigits = integer_unpack_num_bdigits_small(numwords, wordsize, nails, nlp_bits_ret);
        if (debug_integer_pack) {
            int nlp_bits1;
            size_t num_bdigits1 = integer_unpack_num_bdigits_generic(numwords, wordsize, nails, &nlp_bits1);
            RUBY_ASSERT(num_bdigits == num_bdigits1);
            RUBY_ASSERT(*nlp_bits_ret == nlp_bits1);
            (void)num_bdigits1;
        }
    }
    else {
        num_bdigits = integer_unpack_num_bdigits_generic(numwords, wordsize, nails, nlp_bits_ret);
    }
    return num_bdigits;
}

static inline void
integer_unpack_push_bits(int data, int numbits, BDIGIT_DBL *ddp, int *numbits_in_dd_p, BDIGIT **dpp)
{
    (*ddp) |= ((BDIGIT_DBL)data) << (*numbits_in_dd_p);
    *numbits_in_dd_p += numbits;
    while (BITSPERDIG <= *numbits_in_dd_p) {
        *(*dpp)++ = BIGLO(*ddp);
        *ddp = BIGDN(*ddp);
        *numbits_in_dd_p -= BITSPERDIG;
    }
}

static int
integer_unpack_single_bdigit(BDIGIT u, size_t size, int flags, BDIGIT *dp)
{
    int sign;
    if (flags & INTEGER_PACK_2COMP) {
        sign = (flags & INTEGER_PACK_NEGATIVE) ?
            ((size == SIZEOF_BDIGIT && u == 0) ? -2 : -1) :
            ((u >> (size * CHAR_BIT - 1)) ? -1 : 1);
        if (sign < 0) {
            u |= LSHIFTX(BDIGMAX, size * CHAR_BIT);
            u = BIGLO(1 + ~u);
        }
    }
    else
        sign = (flags & INTEGER_PACK_NEGATIVE) ? -1 : 1;
    *dp = u;
    return sign;
}

#ifdef HAVE_BUILTIN___BUILTIN_ASSUME_ALIGNED
#define reinterpret_cast(type, value) (type) \
    __builtin_assume_aligned((value), sizeof(*(type)NULL));
#else
#define reinterpret_cast(type, value) (type)value
#endif

static int
bary_unpack_internal(BDIGIT *bdigits, size_t num_bdigits, const void *words, size_t numwords, size_t wordsize, size_t nails, int flags, int nlp_bits)
{
    int sign;
    const unsigned char *buf = words;
    BDIGIT *dp;
    BDIGIT *de;

    dp = bdigits;
    de = dp + num_bdigits;

    if (!(flags & INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION)) {
        if (nails == 0 && numwords == 1) {
            int need_swap = wordsize != 1 &&
                (flags & INTEGER_PACK_BYTEORDER_MASK) != INTEGER_PACK_NATIVE_BYTE_ORDER &&
                ((flags & INTEGER_PACK_MSBYTE_FIRST) ? !HOST_BIGENDIAN_P : HOST_BIGENDIAN_P);
            if (wordsize == 1) {
                return integer_unpack_single_bdigit(*(uint8_t *)buf, sizeof(uint8_t), flags, dp);
            }
#if defined(HAVE_UINT16_T) && 2 <= SIZEOF_BDIGIT
            if (wordsize == 2 && (uintptr_t)words % RUBY_ALIGNOF(uint16_t) == 0) {
                uint16_t u = *reinterpret_cast(const uint16_t *, buf);
                return integer_unpack_single_bdigit(need_swap ? swap16(u) : u, sizeof(uint16_t), flags, dp);
            }
#endif
#if defined(HAVE_UINT32_T) && 4 <= SIZEOF_BDIGIT
            if (wordsize == 4 && (uintptr_t)words % RUBY_ALIGNOF(uint32_t) == 0) {
                uint32_t u = *reinterpret_cast(const uint32_t *, buf);
                return integer_unpack_single_bdigit(need_swap ? swap32(u) : u, sizeof(uint32_t), flags, dp);
            }
#endif
#if defined(HAVE_UINT64_T) && 8 <= SIZEOF_BDIGIT
            if (wordsize == 8 && (uintptr_t)words % RUBY_ALIGNOF(uint64_t) == 0) {
                uint64_t u = *reinterpret_cast(const uint64_t *, buf);
                return integer_unpack_single_bdigit(need_swap ? swap64(u) : u, sizeof(uint64_t), flags, dp);
            }
#endif
#undef reinterpret_cast
        }
#if !defined(WORDS_BIGENDIAN)
        if (nails == 0 && SIZEOF_BDIGIT == sizeof(BDIGIT) &&
            (flags & INTEGER_PACK_WORDORDER_MASK) == INTEGER_PACK_LSWORD_FIRST &&
            (flags & INTEGER_PACK_BYTEORDER_MASK) != INTEGER_PACK_MSBYTE_FIRST) {
            size_t src_size = numwords * wordsize;
            size_t dst_size = num_bdigits * SIZEOF_BDIGIT;
            MEMCPY(dp, words, char, src_size);
            if (flags & INTEGER_PACK_2COMP) {
                if (flags & INTEGER_PACK_NEGATIVE) {
                    int zero_p;
                    memset((char*)dp + src_size, 0xff, dst_size - src_size);
                    zero_p = bary_2comp(dp, num_bdigits);
                    sign = zero_p ? -2 : -1;
                }
                else if (buf[src_size-1] >> (CHAR_BIT-1)) {
                    memset((char*)dp + src_size, 0xff, dst_size - src_size);
                    bary_2comp(dp, num_bdigits);
                    sign = -1;
                }
                else {
                    MEMZERO((char*)dp + src_size, char, dst_size - src_size);
                    sign = 1;
                }
            }
            else {
                MEMZERO((char*)dp + src_size, char, dst_size - src_size);
                sign = (flags & INTEGER_PACK_NEGATIVE) ? -1 : 1;
            }
            return sign;
        }
#endif
        if (nails == 0 && SIZEOF_BDIGIT == sizeof(BDIGIT) &&
            wordsize % SIZEOF_BDIGIT == 0) {
            size_t bdigits_per_word = wordsize / SIZEOF_BDIGIT;
            int mswordfirst_p = (flags & INTEGER_PACK_MSWORD_FIRST) != 0;
            int msbytefirst_p = (flags & INTEGER_PACK_NATIVE_BYTE_ORDER) ? HOST_BIGENDIAN_P :
                (flags & INTEGER_PACK_MSBYTE_FIRST) != 0;
            MEMCPY(dp, words, BDIGIT, numwords*bdigits_per_word);
            if (mswordfirst_p) {
                bary_swap(dp, num_bdigits);
            }
            if (mswordfirst_p ? !msbytefirst_p : msbytefirst_p) {
                size_t i;
                BDIGIT *p = dp;
                for (i = 0; i < numwords; i++) {
                    bary_swap(p, bdigits_per_word);
                    p += bdigits_per_word;
                }
            }
            if (msbytefirst_p != HOST_BIGENDIAN_P) {
                BDIGIT *p;
                for (p = dp; p < de; p++) {
                    BDIGIT d = *p;
                    *p = swap_bdigit(d);
                }
            }
            if (flags & INTEGER_PACK_2COMP) {
                if (flags & INTEGER_PACK_NEGATIVE) {
                    int zero_p = bary_2comp(dp, num_bdigits);
                    sign = zero_p ? -2 : -1;
                }
                else if (BDIGIT_MSB(de[-1])) {
                    bary_2comp(dp, num_bdigits);
                    sign = -1;
                }
                else {
                    sign = 1;
                }
            }
            else {
                sign = (flags & INTEGER_PACK_NEGATIVE) ? -1 : 1;
            }
            return sign;
        }
    }

    if (num_bdigits != 0) {
        int word_num_partialbits;
        size_t word_num_fullbytes;

        ssize_t word_step;
        size_t byte_start;
        int byte_step;

        size_t word_start, word_last;
        const unsigned char *wordp, *last_wordp;
        BDIGIT_DBL dd;
        int numbits_in_dd;

        integer_pack_loop_setup(numwords, wordsize, nails, flags,
            &word_num_fullbytes, &word_num_partialbits,
            &word_start, &word_step, &word_last, &byte_start, &byte_step);

        wordp = buf + word_start;
        last_wordp = buf + word_last;

        dd = 0;
        numbits_in_dd = 0;

#define PUSH_BITS(data, numbits) \
        integer_unpack_push_bits(data, numbits, &dd, &numbits_in_dd, &dp)

        while (1) {
            size_t index_in_word = 0;
            const unsigned char *bytep = wordp + byte_start;
            while (index_in_word < word_num_fullbytes) {
                PUSH_BITS(*bytep, CHAR_BIT);
                bytep += byte_step;
                index_in_word++;
            }
            if (word_num_partialbits) {
                PUSH_BITS(*bytep & ((1 << word_num_partialbits) - 1), word_num_partialbits);
                bytep += byte_step;
                index_in_word++;
            }

            if (wordp == last_wordp)
                break;

            wordp += word_step;
        }
        if (dd)
            *dp++ = (BDIGIT)dd;
        RUBY_ASSERT(dp <= de);
        while (dp < de)
            *dp++ = 0;
#undef PUSH_BITS
    }

    if (!(flags & INTEGER_PACK_2COMP)) {
        sign = (flags & INTEGER_PACK_NEGATIVE) ? -1 : 1;
    }
    else {
        if (nlp_bits) {
            if ((flags & INTEGER_PACK_NEGATIVE) ||
                (bdigits[num_bdigits-1] >> (BITSPERDIG - nlp_bits - 1))) {
                bdigits[num_bdigits-1] |= BIGLO(BDIGMAX << (BITSPERDIG - nlp_bits));
                sign = -1;
            }
            else {
                sign = 1;
            }
        }
        else {
            if (flags & INTEGER_PACK_NEGATIVE) {
                sign = bary_zero_p(bdigits, num_bdigits) ? -2 : -1;
            }
            else {
                if (num_bdigits != 0 && BDIGIT_MSB(bdigits[num_bdigits-1]))
                    sign = -1;
                else
                    sign = 1;
            }
        }
        if (sign == -1 && num_bdigits != 0) {
            bary_2comp(bdigits, num_bdigits);
        }
    }

    return sign;
}

static void
bary_unpack(BDIGIT *bdigits, size_t num_bdigits, const void *words, size_t numwords, size_t wordsize, size_t nails, int flags)
{
    size_t num_bdigits0;
    int nlp_bits;
    int sign;

    validate_integer_pack_format(numwords, wordsize, nails, flags,
            INTEGER_PACK_MSWORD_FIRST|
            INTEGER_PACK_LSWORD_FIRST|
            INTEGER_PACK_MSBYTE_FIRST|
            INTEGER_PACK_LSBYTE_FIRST|
            INTEGER_PACK_NATIVE_BYTE_ORDER|
            INTEGER_PACK_2COMP|
            INTEGER_PACK_FORCE_BIGNUM|
            INTEGER_PACK_NEGATIVE|
            INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION);

    num_bdigits0 = integer_unpack_num_bdigits(numwords, wordsize, nails, &nlp_bits);

    RUBY_ASSERT(num_bdigits0 <= num_bdigits);

    sign = bary_unpack_internal(bdigits, num_bdigits0, words, numwords, wordsize, nails, flags, nlp_bits);

    if (num_bdigits0 < num_bdigits) {
        BDIGITS_ZERO(bdigits + num_bdigits0, num_bdigits - num_bdigits0);
        if (sign == -2) {
            bdigits[num_bdigits0] = 1;
        }
    }
}

static int
bary_subb(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, int borrow)
{
    BDIGIT_DBL_SIGNED num;
    size_t i;
    size_t sn;

    RUBY_ASSERT(xn <= zn);
    RUBY_ASSERT(yn <= zn);

    sn = xn < yn ? xn : yn;

    num = borrow ? -1 : 0;
    for (i = 0; i < sn; i++) {
        num += (BDIGIT_DBL_SIGNED)xds[i] - yds[i];
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
    if (yn <= xn) {
        for (; i < xn; i++) {
            if (num == 0) goto num_is_zero;
            num += xds[i];
            zds[i] = BIGLO(num);
            num = BIGDN(num);
        }
    }
    else {
        for (; i < yn; i++) {
            num -= yds[i];
            zds[i] = BIGLO(num);
            num = BIGDN(num);
        }
    }
    if (num == 0) goto num_is_zero;
    for (; i < zn; i++) {
        zds[i] = BDIGMAX;
    }
    return 1;

  num_is_zero:
    if (xds == zds && xn == zn)
        return 0;
    for (; i < xn; i++) {
        zds[i] = xds[i];
    }
    for (; i < zn; i++) {
        zds[i] = 0;
    }
    return 0;
}

static int
bary_sub(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    return bary_subb(zds, zn, xds, xn, yds, yn, 0);
}

static int
bary_sub_one(BDIGIT *zds, size_t zn)
{
    return bary_subb(zds, zn, zds, zn, NULL, 0, 1);
}

static int
bary_addc(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, int carry)
{
    BDIGIT_DBL num;
    size_t i;

    RUBY_ASSERT(xn <= zn);
    RUBY_ASSERT(yn <= zn);

    if (xn > yn) {
        const BDIGIT *tds;
        tds = xds; xds = yds; yds = tds;
        i = xn; xn = yn; yn = i;
    }

    num = carry ? 1 : 0;
    for (i = 0; i < xn; i++) {
        num += (BDIGIT_DBL)xds[i] + yds[i];
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
    for (; i < yn; i++) {
        if (num == 0) goto num_is_zero;
        num += yds[i];
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
    for (; i < zn; i++) {
        if (num == 0) goto num_is_zero;
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
    return num != 0;

  num_is_zero:
    if (yds == zds && yn == zn)
        return 0;
    for (; i < yn; i++) {
        zds[i] = yds[i];
    }
    for (; i < zn; i++) {
        zds[i] = 0;
    }
    return 0;
}

static int
bary_add(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    return bary_addc(zds, zn, xds, xn, yds, yn, 0);
}

static int
bary_add_one(BDIGIT *ds, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++) {
        BDIGIT_DBL n = ds[i];
        n += 1;
        ds[i] = BIGLO(n);
        if (ds[i] != 0)
            return 0;
    }
    return 1;
}

static void
bary_mul_single(BDIGIT *zds, size_t zn, BDIGIT x, BDIGIT y)
{
    BDIGIT_DBL n;

    RUBY_ASSERT(2 <= zn);

    n = (BDIGIT_DBL)x * y;
    bdigitdbl2bary(zds, 2, n);
    BDIGITS_ZERO(zds + 2, zn - 2);
}

static int
bary_muladd_1xN(BDIGIT *zds, size_t zn, BDIGIT x, const BDIGIT *yds, size_t yn)
{
    BDIGIT_DBL n;
    BDIGIT_DBL dd;
    size_t j;

    RUBY_ASSERT(zn > yn);

    if (x == 0)
        return 0;
    dd = x;
    n = 0;
    for (j = 0; j < yn; j++) {
        BDIGIT_DBL ee = n + dd * yds[j];
        if (ee) {
            n = zds[j] + ee;
            zds[j] = BIGLO(n);
            n = BIGDN(n);
        }
        else {
            n = 0;
        }

    }
    for (; j < zn; j++) {
        if (n == 0)
            break;
        n += zds[j];
        zds[j] = BIGLO(n);
        n = BIGDN(n);
    }
    return n != 0;
}

static BDIGIT_DBL_SIGNED
bigdivrem_mulsub(BDIGIT *zds, size_t zn, BDIGIT x, const BDIGIT *yds, size_t yn)
{
    size_t i;
    BDIGIT_DBL t2;
    BDIGIT_DBL_SIGNED num;

    RUBY_ASSERT(zn == yn + 1);

    num = 0;
    t2 = 0;
    i = 0;

    do {
        BDIGIT_DBL_SIGNED ee;
        t2 += (BDIGIT_DBL)yds[i] * x;
        ee = num - BIGLO(t2);
        num = (BDIGIT_DBL_SIGNED)zds[i] + ee;
        if (ee) zds[i] = BIGLO(num);
        num = BIGDN(num);
        t2 = BIGDN(t2);
    } while (++i < yn);
    num -= (BDIGIT_DBL_SIGNED)t2;
    num += (BDIGIT_DBL_SIGNED)zds[yn]; /* borrow from high digit; don't update */
    return num;
}

static int
bary_mulsub_1xN(BDIGIT *zds, size_t zn, BDIGIT x, const BDIGIT *yds, size_t yn)
{
    BDIGIT_DBL_SIGNED num;

    RUBY_ASSERT(zn == yn + 1);

    num = bigdivrem_mulsub(zds, zn, x, yds, yn);
    zds[yn] = BIGLO(num);
    if (BIGDN(num))
        return 1;
    return 0;
}

static void
bary_mul_normal(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    size_t i;

    RUBY_ASSERT(xn + yn <= zn);

    BDIGITS_ZERO(zds, zn);
    for (i = 0; i < xn; i++) {
        bary_muladd_1xN(zds+i, zn-i, xds[i], yds, yn);
    }
}

VALUE
rb_big_mul_normal(VALUE x, VALUE y)
{
    size_t xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
    bary_mul_normal(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

/* efficient squaring (2 times faster than normal multiplication)
 * ref: Handbook of Applied Cryptography, Algorithm 14.16
 *      https://www.cacr.math.uwaterloo.ca/hac/about/chap14.pdf
 */
static void
bary_sq_fast(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn)
{
    size_t i, j;
    BDIGIT_DBL c, v, w;
    BDIGIT vl;
    int vh;

    RUBY_ASSERT(xn * 2 <= zn);

    BDIGITS_ZERO(zds, zn);

    if (xn == 0)
        return;

    for (i = 0; i < xn-1; i++) {
        v = (BDIGIT_DBL)xds[i];
        if (!v)
            continue;
        c = (BDIGIT_DBL)zds[i + i] + v * v;
        zds[i + i] = BIGLO(c);
        c = BIGDN(c);
        v *= 2;
        vl = BIGLO(v);
        vh = (int)BIGDN(v);
        for (j = i + 1; j < xn; j++) {
            w = (BDIGIT_DBL)xds[j];
            c += (BDIGIT_DBL)zds[i + j] + vl * w;
            zds[i + j] = BIGLO(c);
            c = BIGDN(c);
            if (vh)
                c += w;
        }
        if (c) {
            c += (BDIGIT_DBL)zds[i + xn];
            zds[i + xn] = BIGLO(c);
            c = BIGDN(c);
            if (c)
                zds[i + xn + 1] += (BDIGIT)c;
        }
    }

    /* i == xn-1 */
    v = (BDIGIT_DBL)xds[i];
    if (!v)
        return;
    c = (BDIGIT_DBL)zds[i + i] + v * v;
    zds[i + i] = BIGLO(c);
    c = BIGDN(c);
    if (c) {
        zds[i + xn] += BIGLO(c);
    }
}

VALUE
rb_big_sq_fast(VALUE x)
{
    size_t xn = BIGNUM_LEN(x), zn = 2 * xn;
    VALUE z = bignew(zn, 1);
    bary_sq_fast(BDIGITS(z), zn, BDIGITS(x), xn);
    RB_GC_GUARD(x);
    return z;
}

static inline size_t
max_size(size_t a, size_t b)
{
    return (a > b ? a : b);
}

/* balancing multiplication by slicing larger argument */
static void
bary_mul_balance_with_mulfunc(BDIGIT *const zds, const size_t zn,
                              const BDIGIT *const xds, const size_t xn,
                              const BDIGIT *const yds, const size_t yn,
                              BDIGIT *wds, size_t wn, mulfunc_t *const mulfunc)
{
    VALUE work = 0;
    size_t n;

    RUBY_ASSERT(xn + yn <= zn);
    RUBY_ASSERT(xn <= yn);
    RUBY_ASSERT(!KARATSUBA_BALANCED(xn, yn) || !TOOM3_BALANCED(xn, yn));

    BDIGITS_ZERO(zds, xn);

    if (wn < xn) {
        /* The condition when a new buffer is needed:
         * 1. (2(xn+r) > zn-(yn-r)) => (2xn+r > zn-yn), at the last
         *    iteration (or r == 0)
         * 2. (2(xn+xn) > zn-(yn-r-xn)) => (3xn-r > zn-yn), at the
         *    previous iteration.
         */
        const size_t r = yn % xn;
        if (2*xn + yn + max_size(xn-r, r) > zn) {
            wn = xn;
            wds = ALLOCV_N(BDIGIT, work, wn);
        }
    }

    n = 0;
    while (yn > n) {
        const size_t r = (xn > (yn - n) ? (yn - n) : xn);
        const size_t tn = (xn + r);
        if (2 * (xn + r) <= zn - n) {
            BDIGIT *const tds = zds + n + xn + r;
            mulfunc(tds, tn, xds, xn, yds + n, r, wds, wn);
            BDIGITS_ZERO(zds + n + xn, r);
            bary_add(zds + n, tn,
                     zds + n, tn,
                     tds, tn);
        }
        else {
            BDIGIT *const tds = zds + n;
            if (wn < xn) {
                /* xn is invariant, only once here */
#if 0
                wn = xn;
                wds = ALLOCV_N(BDIGIT, work, wn);
#else
                rb_bug("wds is not enough: %" PRIdSIZE " for %" PRIdSIZE, wn, xn);
#endif
            }
            MEMCPY(wds, zds + n, BDIGIT, xn);
            mulfunc(tds, tn, xds, xn, yds + n, r, wds+xn, wn-xn);
            bary_add(zds + n, tn,
                     zds + n, tn,
                     wds, xn);
        }
        n += r;
    }
    BDIGITS_ZERO(zds+xn+yn, zn - (xn+yn));

    if (work)
        ALLOCV_END(work);
}

VALUE
rb_big_mul_balance(VALUE x, VALUE y)
{
    size_t xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
    bary_mul_balance_with_mulfunc(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn, NULL, 0, bary_mul_toom3_start);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

/* multiplication by karatsuba method */
static void
bary_mul_karatsuba(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, BDIGIT *wds, size_t wn)
{
    VALUE work = 0;

    size_t n;
    int sub_p, borrow, carry1, carry2, carry3;

    int odd_y = 0;
    int odd_xy = 0;
    int sq;

    const BDIGIT *xds0, *xds1, *yds0, *yds1;
    BDIGIT *zds0, *zds1, *zds2, *zds3;

    RUBY_ASSERT(xn + yn <= zn);
    RUBY_ASSERT(xn <= yn);
    RUBY_ASSERT(yn < 2 * xn);

    sq = xds == yds && xn == yn;

    if (yn & 1) {
        odd_y = 1;
        yn--;
        if (yn < xn) {
            odd_xy = 1;
            xn--;
        }
    }

    n = yn / 2;

    RUBY_ASSERT(n < xn);

    if (wn < n) {
        /* This function itself needs only n BDIGITs for work area.
         * However this function calls bary_mul_karatsuba and
         * bary_mul_balance recursively.
         * 2n BDIGITs are enough to avoid allocations in
         * the recursively called functions.
         */
        wn = 2*n;
        wds = ALLOCV_N(BDIGIT, work, wn);
    }

    /* Karatsuba algorithm:
     *
     * x = x0 + r*x1
     * y = y0 + r*y1
     * z = x*y
     *   = (x0 + r*x1) * (y0 + r*y1)
     *   = x0*y0 + r*(x1*y0 + x0*y1) + r*r*x1*y1
     *   = x0*y0 + r*(x0*y0 + x1*y1 - (x1-x0)*(y1-y0)) + r*r*x1*y1
     *   = x0*y0 + r*(x0*y0 + x1*y1 - (x0-x1)*(y0-y1)) + r*r*x1*y1
     */

    xds0 = xds;
    xds1 = xds + n;
    yds0 = yds;
    yds1 = yds + n;
    zds0 = zds;
    zds1 = zds + n;
    zds2 = zds + 2*n;
    zds3 = zds + 3*n;

    sub_p = 1;

    /* zds0:? zds1:? zds2:? zds3:? wds:? */

    if (bary_sub(zds0, n, xds, n, xds+n, xn-n)) {
        bary_2comp(zds0, n);
        sub_p = !sub_p;
    }

    /* zds0:|x1-x0| zds1:? zds2:? zds3:? wds:? */

    if (sq) {
        sub_p = 1;
        bary_mul_karatsuba_start(zds1, 2*n, zds0, n, zds0, n, wds, wn);
    }
    else {
        if (bary_sub(wds, n, yds, n, yds+n, n)) {
            bary_2comp(wds, n);
            sub_p = !sub_p;
        }

        /* zds0:|x1-x0| zds1:? zds2:? zds3:? wds:|y1-y0| */

        bary_mul_karatsuba_start(zds1, 2*n, zds0, n, wds, n, wds+n, wn-n);
    }

    /* zds0:|x1-x0| zds1,zds2:|x1-x0|*|y1-y0| zds3:? wds:|y1-y0| */

    borrow = 0;
    if (sub_p) {
        borrow = !bary_2comp(zds1, 2*n);
    }
    /* zds0:|x1-x0| zds1,zds2:-?|x1-x0|*|y1-y0| zds3:? wds:|y1-y0| */

    MEMCPY(wds, zds1, BDIGIT, n);

    /* zds0:|x1-x0| zds1,zds2:-?|x1-x0|*|y1-y0| zds3:? wds:lo(-?|x1-x0|*|y1-y0|) */

    bary_mul_karatsuba_start(zds0, 2*n, xds0, n, yds0, n, wds+n, wn-n);

    /* zds0,zds1:x0*y0 zds2:hi(-?|x1-x0|*|y1-y0|) zds3:? wds:lo(-?|x1-x0|*|y1-y0|) */

    carry1 = bary_add(wds, n, wds, n, zds0, n);
    carry1 = bary_addc(zds2, n, zds2, n, zds1, n, carry1);

    /* zds0,zds1:x0*y0 zds2:hi(x0*y0-?|x1-x0|*|y1-y0|) zds3:? wds:lo(x0*y0-?|x1-x0|*|y1-y0|) */

    carry2 = bary_add(zds1, n, zds1, n, wds, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|) zds2:hi(x0*y0-?|x1-x0|*|y1-y0|) zds3:? wds:lo(x0*y0-?|x1-x0|*|y1-y0|) */

    MEMCPY(wds, zds2, BDIGIT, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|) zds2:_ zds3:? wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    bary_mul_karatsuba_start(zds2, zn-2*n, xds1, xn-n, yds1, n, wds+n, wn-n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|) zds2,zds3:x1*y1 wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    carry3 = bary_add(zds1, n, zds1, n, zds2, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|)+lo(x1*y1) zds2,zds3:x1*y1 wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    carry3 = bary_addc(zds2, n, zds2, n, zds3, (4*n < zn ? n : zn-3*n), carry3);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|)+lo(x1*y1) zds2,zds3:x1*y1+hi(x1*y1) wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    bary_add(zds2, zn-2*n, zds2, zn-2*n, wds, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|)+lo(x1*y1) zds2,zds3:x1*y1+hi(x1*y1)+hi(x0*y0-?|x1-x0|*|y1-y0|) wds:_ */

    if (carry2)
        bary_add_one(zds2, zn-2*n);

    if (carry1 + carry3 - borrow < 0)
        bary_sub_one(zds3, zn-3*n);
    else if (carry1 + carry3 - borrow > 0) {
        BDIGIT c = carry1 + carry3 - borrow;
        bary_add(zds3, zn-3*n, zds3, zn-3*n, &c, 1);
    }

    /*
    if (SIZEOF_BDIGIT * zn <= 16) {
        uint128_t z, x, y;
        ssize_t i;
        for (x = 0, i = xn-1; 0 <= i; i--) { x <<= SIZEOF_BDIGIT*CHAR_BIT; x |= xds[i]; }
        for (y = 0, i = yn-1; 0 <= i; i--) { y <<= SIZEOF_BDIGIT*CHAR_BIT; y |= yds[i]; }
        for (z = 0, i = zn-1; 0 <= i; i--) { z <<= SIZEOF_BDIGIT*CHAR_BIT; z |= zds[i]; }
        RUBY_ASSERT(z == x * y);
    }
    */

    if (odd_xy) {
        bary_muladd_1xN(zds+yn, zn-yn, yds[yn], xds, xn);
        bary_muladd_1xN(zds+xn, zn-xn, xds[xn], yds, yn+1);
    }
    else if (odd_y) {
        bary_muladd_1xN(zds+yn, zn-yn, yds[yn], xds, xn);
    }

    if (work)
        ALLOCV_END(work);
}

VALUE
rb_big_mul_karatsuba(VALUE x, VALUE y)
{
    size_t xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
    if (!((xn <= yn && yn < 2) || KARATSUBA_BALANCED(xn, yn)))
        rb_raise(rb_eArgError, "unexpected bignum length for karatsuba");
    bary_mul_karatsuba(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn, NULL, 0);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

static void
bary_mul_toom3(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, BDIGIT *wds, size_t wn)
{
    size_t n;
    size_t wnc;
    VALUE work = 0;

    /* "p" stands for "positive".  Actually it means "non-negative", though. */
    size_t x0n; const BDIGIT *x0ds;
    size_t x1n; const BDIGIT *x1ds;
    size_t x2n; const BDIGIT *x2ds;
    size_t y0n; const BDIGIT *y0ds;
    size_t y1n; const BDIGIT *y1ds;
    size_t y2n; const BDIGIT *y2ds;

    size_t u1n; BDIGIT *u1ds; int u1p;
    size_t u2n; BDIGIT *u2ds; int u2p;
    size_t u3n; BDIGIT *u3ds; int u3p;

    size_t v1n; BDIGIT *v1ds; int v1p;
    size_t v2n; BDIGIT *v2ds; int v2p;
    size_t v3n; BDIGIT *v3ds; int v3p;

    size_t t0n; BDIGIT *t0ds; int t0p;
    size_t t1n; BDIGIT *t1ds; int t1p;
    size_t t2n; BDIGIT *t2ds; int t2p;
    size_t t3n; BDIGIT *t3ds; int t3p;
    size_t t4n; BDIGIT *t4ds; int t4p;

    size_t z0n; BDIGIT *z0ds;
    size_t z1n; BDIGIT *z1ds; int z1p;
    size_t z2n; BDIGIT *z2ds; int z2p;
    size_t z3n; BDIGIT *z3ds; int z3p;
    size_t z4n; BDIGIT *z4ds;

    size_t zzn; BDIGIT *zzds;

    int sq = xds == yds && xn == yn;

    RUBY_ASSERT(xn <= yn);  /* assume y >= x */
    RUBY_ASSERT(xn + yn <= zn);

    n = (yn + 2) / 3;
    RUBY_ASSERT(2*n < xn);

    wnc = 0;

    wnc += (u1n = n+1); /* BITSPERDIG*n+2 bits */
    wnc += (u2n = n+1); /* BITSPERDIG*n+1 bits */
    wnc += (u3n = n+1); /* BITSPERDIG*n+3 bits */
    wnc += (v1n = n+1); /* BITSPERDIG*n+2 bits */
    wnc += (v2n = n+1); /* BITSPERDIG*n+1 bits */
    wnc += (v3n = n+1); /* BITSPERDIG*n+3 bits */

    wnc += (t0n = 2*n); /* BITSPERDIG*2*n bits */
    wnc += (t1n = 2*n+2); /* BITSPERDIG*2*n+4 bits but bary_mul needs u1n+v1n */
    wnc += (t2n = 2*n+2); /* BITSPERDIG*2*n+2 bits but bary_mul needs u2n+v2n */
    wnc += (t3n = 2*n+2); /* BITSPERDIG*2*n+6 bits but bary_mul needs u3n+v3n */
    wnc += (t4n = 2*n); /* BITSPERDIG*2*n bits */

    wnc += (z1n = 2*n+1); /* BITSPERDIG*2*n+5 bits */
    wnc += (z2n = 2*n+1); /* BITSPERDIG*2*n+6 bits */
    wnc += (z3n = 2*n+1); /* BITSPERDIG*2*n+8 bits */

    if (wn < wnc) {
        wn = wnc * 3 / 2; /* Allocate working memory for whole recursion at once. */
        wds = ALLOCV_N(BDIGIT, work, wn);
    }

    u1ds = wds; wds += u1n;
    u2ds = wds; wds += u2n;
    u3ds = wds; wds += u3n;

    v1ds = wds; wds += v1n;
    v2ds = wds; wds += v2n;
    v3ds = wds; wds += v3n;

    t0ds = wds; wds += t0n;
    t1ds = wds; wds += t1n;
    t2ds = wds; wds += t2n;
    t3ds = wds; wds += t3n;
    t4ds = wds; wds += t4n;

    z1ds = wds; wds += z1n;
    z2ds = wds; wds += z2n;
    z3ds = wds; wds += z3n;

    wn -= wnc;

    zzds = u1ds;
    zzn = 6*n+1;

    x0n = n;
    x1n = n;
    x2n = xn - 2*n;
    x0ds = xds;
    x1ds = xds + n;
    x2ds = xds + 2*n;

    if (sq) {
        y0n = x0n;
        y1n = x1n;
        y2n = x2n;
        y0ds = x0ds;
        y1ds = x1ds;
        y2ds = x2ds;
    }
    else {
        y0n = n;
        y1n = n;
        y2n = yn - 2*n;
        y0ds = yds;
        y1ds = yds + n;
        y2ds = yds + 2*n;
    }

    /*
     * ref. https://en.wikipedia.org/wiki/Toom%E2%80%93Cook_multiplication
     *
     * x(b) = x0 * b^0 + x1 * b^1 + x2 * b^2
     * y(b) = y0 * b^0 + y1 * b^1 + y2 * b^2
     *
     * z(b) = x(b) * y(b)
     * z(b) = z0 * b^0 + z1 * b^1 + z2 * b^2 + z3 * b^3 + z4 * b^4
     * where:
     *   z0 = x0 * y0
     *   z1 = x0 * y1 + x1 * y0
     *   z2 = x0 * y2 + x1 * y1 + x2 * y0
     *   z3 = x1 * y2 + x2 * y1
     *   z4 = x2 * y2
     *
     * Toom3 method (a.k.a. Toom-Cook method):
     * (Step1) calculating 5 points z(b0), z(b1), z(b2), z(b3), z(b4),
     * where:
     *   b0 = 0, b1 = 1, b2 = -1, b3 = -2, b4 = inf,
     *   z(0)   = x(0)   * y(0)   = x0 * y0
     *   z(1)   = x(1)   * y(1)   = (x0 + x1 + x2) * (y0 + y1 + y2)
     *   z(-1)  = x(-1)  * y(-1)  = (x0 - x1 + x2) * (y0 - y1 + y2)
     *   z(-2)  = x(-2)  * y(-2)  = (x0 - 2 * (x1 - 2 * x2)) * (y0 - 2 * (y1 - 2 * y2))
     *   z(inf) = x(inf) * y(inf) = x2 * y2
     *
     * (Step2) interpolating z0, z1, z2, z3 and z4.
     *
     * (Step3) Substituting base value into b of the polynomial z(b),
     */

    /*
     * [Step1] calculating 5 points z(b0), z(b1), z(b2), z(b3), z(b4)
     */

    /* u1 <- x0 + x2 */
    bary_add(u1ds, u1n, x0ds, x0n, x2ds, x2n);
    u1p = 1;

    /* x(-1) : u2 <- u1 - x1 = x0 - x1 + x2 */
    if (bary_sub(u2ds, u2n, u1ds, u1n, x1ds, x1n)) {
        bary_2comp(u2ds, u2n);
        u2p = 0;
    }
    else {
        u2p = 1;
    }

    /* x(1) : u1 <- u1 + x1 = x0 + x1 + x2 */
    bary_add(u1ds, u1n, u1ds, u1n, x1ds, x1n);

    /* x(-2) : u3 <- 2 * (u2 + x2) - x0 = x0 - 2 * (x1 - 2 * x2) */
    u3p = 1;
    if (u2p) {
        bary_add(u3ds, u3n, u2ds, u2n, x2ds, x2n);
    }
    else if (bary_sub(u3ds, u3n, x2ds, x2n, u2ds, u2n)) {
        bary_2comp(u3ds, u3n);
        u3p = 0;
    }
    bary_small_lshift(u3ds, u3ds, u3n, 1);
    if (!u3p) {
        bary_add(u3ds, u3n, u3ds, u3n, x0ds, x0n);
    }
    else if (bary_sub(u3ds, u3n, u3ds, u3n, x0ds, x0n)) {
        bary_2comp(u3ds, u3n);
        u3p = 0;
    }

    if (sq) {
        v1n = u1n; v1ds = u1ds; v1p = u1p;
        v2n = u2n; v2ds = u2ds; v2p = u2p;
        v3n = u3n; v3ds = u3ds; v3p = u3p;
    }
    else {
        /* v1 <- y0 + y2 */
        bary_add(v1ds, v1n, y0ds, y0n, y2ds, y2n);
        v1p = 1;

        /* y(-1) : v2 <- v1 - y1 = y0 - y1 + y2 */
        v2p = 1;
        if (bary_sub(v2ds, v2n, v1ds, v1n, y1ds, y1n)) {
            bary_2comp(v2ds, v2n);
            v2p = 0;
        }

        /* y(1) : v1 <- v1 + y1 = y0 + y1 + y2 */
        bary_add(v1ds, v1n, v1ds, v1n, y1ds, y1n);

        /* y(-2) : v3 <- 2 * (v2 + y2) - y0 = y0 - 2 * (y1 - 2 * y2) */
        v3p = 1;
        if (v2p) {
            bary_add(v3ds, v3n, v2ds, v2n, y2ds, y2n);
        }
        else if (bary_sub(v3ds, v3n, y2ds, y2n, v2ds, v2n)) {
            bary_2comp(v3ds, v3n);
            v3p = 0;
        }
        bary_small_lshift(v3ds, v3ds, v3n, 1);
        if (!v3p) {
            bary_add(v3ds, v3n, v3ds, v3n, y0ds, y0n);
        }
        else if (bary_sub(v3ds, v3n, v3ds, v3n, y0ds, y0n)) {
            bary_2comp(v3ds, v3n);
            v3p = 0;
        }
    }

    /* z(0) : t0 <- x0 * y0 */
    bary_mul_toom3_start(t0ds, t0n, x0ds, x0n, y0ds, y0n, wds, wn);
    t0p = 1;

    /* z(1) : t1 <- u1 * v1 */
    bary_mul_toom3_start(t1ds, t1n, u1ds, u1n, v1ds, v1n, wds, wn);
    t1p = u1p == v1p;
    RUBY_ASSERT(t1ds[t1n-1] == 0);
    t1n--;

    /* z(-1) : t2 <- u2 * v2 */
    bary_mul_toom3_start(t2ds, t2n, u2ds, u2n, v2ds, v2n, wds, wn);
    t2p = u2p == v2p;
    RUBY_ASSERT(t2ds[t2n-1] == 0);
    t2n--;

    /* z(-2) : t3 <- u3 * v3 */
    bary_mul_toom3_start(t3ds, t3n, u3ds, u3n, v3ds, v3n, wds, wn);
    t3p = u3p == v3p;
    RUBY_ASSERT(t3ds[t3n-1] == 0);
    t3n--;

    /* z(inf) : t4 <- x2 * y2 */
    bary_mul_toom3_start(t4ds, t4n, x2ds, x2n, y2ds, y2n, wds, wn);
    t4p = 1;

    /*
     * [Step2] interpolating z0, z1, z2, z3 and z4.
     */

    /* z0 <- z(0) == t0 */
    z0n = t0n; z0ds = t0ds;

    /* z4 <- z(inf) == t4 */
    z4n = t4n; z4ds = t4ds;

    /* z3 <- (z(-2) - z(1)) / 3 == (t3 - t1) / 3 */
    if (t3p == t1p) {
        z3p = t3p;
        if (bary_sub(z3ds, z3n, t3ds, t3n, t1ds, t1n)) {
            bary_2comp(z3ds, z3n);
            z3p = !z3p;
        }
    }
    else {
        z3p = t3p;
        bary_add(z3ds, z3n, t3ds, t3n, t1ds, t1n);
    }
    bigdivrem_single(z3ds, z3ds, z3n, 3);

    /* z1 <- (z(1) - z(-1)) / 2 == (t1 - t2) / 2 */
    if (t1p == t2p) {
        z1p = t1p;
        if (bary_sub(z1ds, z1n, t1ds, t1n, t2ds, t2n)) {
            bary_2comp(z1ds, z1n);
            z1p = !z1p;
        }
    }
    else {
        z1p = t1p;
        bary_add(z1ds, z1n, t1ds, t1n, t2ds, t2n);
    }
    bary_small_rshift(z1ds, z1ds, z1n, 1, 0);

    /* z2 <- z(-1) - z(0) == t2 - t0 */
    if (t2p == t0p) {
        z2p = t2p;
        if (bary_sub(z2ds, z2n, t2ds, t2n, t0ds, t0n)) {
            bary_2comp(z2ds, z2n);
            z2p = !z2p;
        }
    }
    else {
        z2p = t2p;
        bary_add(z2ds, z2n, t2ds, t2n, t0ds, t0n);
    }

    /* z3 <- (z2 - z3) / 2 + 2 * z(inf) == (z2 - z3) / 2 + 2 * t4 */
    if (z2p == z3p) {
        z3p = z2p;
        if (bary_sub(z3ds, z3n, z2ds, z2n, z3ds, z3n)) {
            bary_2comp(z3ds, z3n);
            z3p = !z3p;
        }
    }
    else {
        z3p = z2p;
        bary_add(z3ds, z3n, z2ds, z2n, z3ds, z3n);
    }
    bary_small_rshift(z3ds, z3ds, z3n, 1, 0);
    if (z3p == t4p) {
        bary_muladd_1xN(z3ds, z3n, 2, t4ds, t4n);
    }
    else {
        if (bary_mulsub_1xN(z3ds, z3n, 2, t4ds, t4n)) {
            bary_2comp(z3ds, z3n);
            z3p = !z3p;
        }
    }

    /* z2 <- z2 + z1 - z(inf) == z2 + z1 - t4 */
    if (z2p == z1p) {
        bary_add(z2ds, z2n, z2ds, z2n, z1ds, z1n);
    }
    else {
        if (bary_sub(z2ds, z2n, z2ds, z2n, z1ds, z1n)) {
            bary_2comp(z2ds, z2n);
            z2p = !z2p;
        }
    }

    if (z2p == t4p) {
        if (bary_sub(z2ds, z2n, z2ds, z2n, t4ds, t4n)) {
            bary_2comp(z2ds, z2n);
            z2p = !z2p;
        }
    }
    else {
        bary_add(z2ds, z2n, z2ds, z2n, t4ds, t4n);
    }

    /* z1 <- z1 - z3 */
    if (z1p == z3p) {
        if (bary_sub(z1ds, z1n, z1ds, z1n, z3ds, z3n)) {
            bary_2comp(z1ds, z1n);
            z1p = !z1p;
        }
    }
    else {
        bary_add(z1ds, z1n, z1ds, z1n, z3ds, z3n);
    }

    /*
     * [Step3] Substituting base value into b of the polynomial z(b),
     */

    MEMCPY(zzds, z0ds, BDIGIT, z0n);
    BDIGITS_ZERO(zzds + z0n, 4*n - z0n);
    MEMCPY(zzds + 4*n, z4ds, BDIGIT, z4n);
    BDIGITS_ZERO(zzds + 4*n + z4n, zzn - (4*n + z4n));
    if (z1p)
        bary_add(zzds +   n, zzn -   n, zzds +   n, zzn -   n, z1ds, z1n);
    else
        bary_sub(zzds +   n, zzn -   n, zzds +   n, zzn -   n, z1ds, z1n);
    if (z2p)
        bary_add(zzds + 2*n, zzn - 2*n, zzds + 2*n, zzn - 2*n, z2ds, z2n);
    else
        bary_sub(zzds + 2*n, zzn - 2*n, zzds + 2*n, zzn - 2*n, z2ds, z2n);
    if (z3p)
        bary_add(zzds + 3*n, zzn - 3*n, zzds + 3*n, zzn - 3*n, z3ds, z3n);
    else
        bary_sub(zzds + 3*n, zzn - 3*n, zzds + 3*n, zzn - 3*n, z3ds, z3n);

    BARY_TRUNC(zzds, zzn);
    MEMCPY(zds, zzds, BDIGIT, zzn);
    BDIGITS_ZERO(zds + zzn, zn - zzn);

    if (work)
        ALLOCV_END(work);
}

VALUE
rb_big_mul_toom3(VALUE x, VALUE y)
{
    size_t xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
    if (xn > yn || yn < 3 || !TOOM3_BALANCED(xn,yn))
        rb_raise(rb_eArgError, "unexpected bignum length for toom3");
    bary_mul_toom3(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn, NULL, 0);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

#if USE_GMP
static inline void
bdigits_to_mpz(mpz_t mp, const BDIGIT *digits, size_t len)
{
    const size_t nails = (sizeof(BDIGIT)-SIZEOF_BDIGIT)*CHAR_BIT;
    mpz_import(mp, len, -1, sizeof(BDIGIT), 0, nails, digits);
}

static inline void
bdigits_from_mpz(mpz_t mp, BDIGIT *digits, size_t *len)
{
    const size_t nails = (sizeof(BDIGIT)-SIZEOF_BDIGIT)*CHAR_BIT;
    mpz_export(digits, len, -1, sizeof(BDIGIT), 0, nails, mp);
}

static void
bary_mul_gmp(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    mpz_t x, y, z;
    size_t count;

    RUBY_ASSERT(xn + yn <= zn);

    mpz_init(x);
    mpz_init(y);
    mpz_init(z);
    bdigits_to_mpz(x, xds, xn);
    if (xds == yds && xn == yn) {
        mpz_mul(z, x, x);
    }
    else {
        bdigits_to_mpz(y, yds, yn);
        mpz_mul(z, x, y);
    }
    bdigits_from_mpz(z, zds, &count);
    BDIGITS_ZERO(zds+count, zn-count);
    mpz_clear(x);
    mpz_clear(y);
    mpz_clear(z);
}

VALUE
rb_big_mul_gmp(VALUE x, VALUE y)
{
    size_t xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
    bary_mul_gmp(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}
#endif

static void
bary_short_mul(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    RUBY_ASSERT(xn + yn <= zn);

    if (xn == 1 && yn == 1) {
        bary_mul_single(zds, zn, xds[0], yds[0]);
    }
    else {
        bary_mul_normal(zds, zn, xds, xn, yds, yn);
        rb_thread_check_ints();
    }
}

/* determine whether a bignum is sparse or not by random sampling */
static inline int
bary_sparse_p(const BDIGIT *ds, size_t n)
{
    long c = 0;

    if (          ds[2 * n / 5]) c++;
    if (c <= 1 && ds[    n / 2]) c++;
    if (c <= 1 && ds[3 * n / 5]) c++;

    return (c <= 1) ? 1 : 0;
}

static int
bary_mul_precheck(BDIGIT **zdsp, size_t *znp, const BDIGIT **xdsp, size_t *xnp, const BDIGIT **ydsp, size_t *ynp)
{
    size_t nlsz; /* number of least significant zero BDIGITs */

    BDIGIT *zds = *zdsp;
    size_t zn = *znp;
    const BDIGIT *xds = *xdsp;
    size_t xn = *xnp;
    const BDIGIT *yds = *ydsp;
    size_t yn = *ynp;

    RUBY_ASSERT(xn + yn <= zn);

    nlsz = 0;

    while (0 < xn) {
        if (xds[xn-1] == 0) {
            xn--;
        }
        else {
            do {
                if (xds[0] != 0)
                    break;
                xds++;
                xn--;
                nlsz++;
            } while (0 < xn);
            break;
        }
    }

    while (0 < yn) {
        if (yds[yn-1] == 0) {
            yn--;
        }
        else {
            do {
                if (yds[0] != 0)
                    break;
                yds++;
                yn--;
                nlsz++;
            } while (0 < yn);
            break;
        }
    }

    if (nlsz) {
        BDIGITS_ZERO(zds, nlsz);
        zds += nlsz;
        zn -= nlsz;
    }

    /* make sure that y is longer than x */
    if (xn > yn) {
        const BDIGIT *tds;
        size_t tn;
        tds = xds; xds = yds; yds = tds;
        tn = xn; xn = yn; yn = tn;
    }
    RUBY_ASSERT(xn <= yn);

    if (xn <= 1) {
        if (xn == 0) {
            BDIGITS_ZERO(zds, zn);
            return 1;
        }

        if (xds[0] == 1) {
            MEMCPY(zds, yds, BDIGIT, yn);
            BDIGITS_ZERO(zds+yn, zn-yn);
            return 1;
        }
        if (POW2_P(xds[0])) {
            zds[yn] = bary_small_lshift(zds, yds, yn, bit_length(xds[0])-1);
            BDIGITS_ZERO(zds+yn+1, zn-yn-1);
            return 1;
        }
        if (yn == 1 && yds[0] == 1) {
            zds[0] = xds[0];
            BDIGITS_ZERO(zds+1, zn-1);
            return 1;
        }
        bary_mul_normal(zds, zn, xds, xn, yds, yn);
        return 1;
    }

    *zdsp = zds;
    *znp = zn;
    *xdsp = xds;
    *xnp = xn;
    *ydsp = yds;
    *ynp = yn;

    return 0;
}

static void
bary_mul_karatsuba_branch(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, BDIGIT *wds, size_t wn)
{
    /* normal multiplication when x is small */
    if (xn < KARATSUBA_MUL_DIGITS) {
        goto normal;
    }

    /* normal multiplication when x or y is a sparse bignum */
    if (bary_sparse_p(xds, xn)) goto normal;
    if (bary_sparse_p(yds, yn)) {
        bary_short_mul(zds, zn, yds, yn, xds, xn);
        return;
    }

    /* balance multiplication by slicing y when x is much smaller than y */
    if (!KARATSUBA_BALANCED(xn, yn)) {
        bary_mul_balance_with_mulfunc(zds, zn, xds, xn, yds, yn, wds, wn, bary_mul_karatsuba_start);
        return;
    }

    /* multiplication by karatsuba method */
    bary_mul_karatsuba(zds, zn, xds, xn, yds, yn, wds, wn);
    return;

  normal:
    if (xds == yds && xn == yn) {
        bary_sq_fast(zds, zn, xds, xn);
    }
    else {
        bary_short_mul(zds, zn, xds, xn, yds, yn);
    }
}

static void
bary_mul_karatsuba_start(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, BDIGIT *wds, size_t wn)
{
    if (bary_mul_precheck(&zds, &zn, &xds, &xn, &yds, &yn))
        return;

    bary_mul_karatsuba_branch(zds, zn, xds, xn, yds, yn, wds, wn);
}

static void
bary_mul_toom3_branch(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, BDIGIT *wds, size_t wn)
{
    if (xn < TOOM3_MUL_DIGITS) {
        bary_mul_karatsuba_branch(zds, zn, xds, xn, yds, yn, wds, wn);
        return;
    }

    if (!TOOM3_BALANCED(xn, yn)) {
        bary_mul_balance_with_mulfunc(zds, zn, xds, xn, yds, yn, wds, wn, bary_mul_toom3_start);
        return;
    }

    bary_mul_toom3(zds, zn, xds, xn, yds, yn, wds, wn);
}

static void
bary_mul_toom3_start(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, BDIGIT *wds, size_t wn)
{
    if (bary_mul_precheck(&zds, &zn, &xds, &xn, &yds, &yn))
        return;

    bary_mul_toom3_branch(zds, zn, xds, xn, yds, yn, wds, wn);
}

static void
bary_mul(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    if (xn <= yn) {
        if (xn < NAIVE_MUL_DIGITS) {
            if (xds == yds && xn == yn)
                bary_sq_fast(zds, zn, xds, xn);
            else
                bary_short_mul(zds, zn, xds, xn, yds, yn);
            return;
        }
    }
    else {
        if (yn < NAIVE_MUL_DIGITS) {
            bary_short_mul(zds, zn, yds, yn, xds, xn);
            return;
        }
    }

#if USE_GMP
    bary_mul_gmp(zds, zn, xds, xn, yds, yn);
#else
    bary_mul_toom3_start(zds, zn, xds, xn, yds, yn, NULL, 0);
#endif
}

struct big_div_struct {
    size_t yn, zn;
    BDIGIT *yds, *zds;
    volatile VALUE stop;
};

static void *
bigdivrem1(void *ptr)
{
    struct big_div_struct *bds = (struct big_div_struct*)ptr;
    size_t yn = bds->yn;
    size_t zn = bds->zn;
    BDIGIT *yds = bds->yds, *zds = bds->zds;
    BDIGIT_DBL_SIGNED num;
    BDIGIT q;

    do {
        if (bds->stop) {
            bds->zn = zn;
            return 0;
        }
        if (zds[zn-1] == yds[yn-1]) q = BDIGMAX;
        else q = (BDIGIT)((BIGUP(zds[zn-1]) + zds[zn-2])/yds[yn-1]);
        if (q) {
            num = bigdivrem_mulsub(zds+zn-(yn+1), yn+1,
                                   q,
                                   yds, yn);
            while (num) { /* "add back" required */
                q--;
                num = bary_add(zds+zn-(yn+1), yn,
                               zds+zn-(yn+1), yn,
                               yds, yn);
                num--;
            }
        }
        zn--;
        zds[zn] = q;
    } while (zn > yn);
    return 0;
}

/* async-signal-safe */
static void
rb_big_stop(void *ptr)
{
    struct big_div_struct *bds = ptr;
    bds->stop = Qtrue;
}

static BDIGIT
bigdivrem_single1(BDIGIT *qds, const BDIGIT *xds, size_t xn, BDIGIT x_higher_bdigit, BDIGIT y)
{
    RUBY_ASSERT(0 < xn);
    RUBY_ASSERT(x_higher_bdigit < y);
    if (POW2_P(y)) {
        BDIGIT r;
        r = xds[0] & (y-1);
        bary_small_rshift(qds, xds, xn, bit_length(y)-1, x_higher_bdigit);
        return r;
    }
    else {
        size_t i;
        BDIGIT_DBL t2;
        t2 = x_higher_bdigit;
        for (i = 0; i < xn; i++) {
            t2 = BIGUP(t2) + xds[xn - i - 1];
            qds[xn - i - 1] = (BDIGIT)(t2 / y);
            t2 %= y;
        }
        return (BDIGIT)t2;
    }
}

static BDIGIT
bigdivrem_single(BDIGIT *qds, const BDIGIT *xds, size_t xn, BDIGIT y)
{
    return bigdivrem_single1(qds, xds, xn, 0, y);
}

static void
bigdivrem_restoring(BDIGIT *zds, size_t zn, BDIGIT *yds, size_t yn)
{
    struct big_div_struct bds;
    size_t ynzero;

    RUBY_ASSERT(yn < zn);
    RUBY_ASSERT(BDIGIT_MSB(yds[yn-1]));
    RUBY_ASSERT(zds[zn-1] < yds[yn-1]);

    for (ynzero = 0; !yds[ynzero]; ynzero++);

    if (ynzero+1 == yn) {
        BDIGIT r;
        r = bigdivrem_single1(zds+yn, zds+ynzero, zn-yn, zds[zn-1], yds[ynzero]);
        zds[ynzero] = r;
        return;
    }

    bds.yn = yn - ynzero;
    bds.zds = zds + ynzero;
    bds.yds = yds + ynzero;
    bds.stop = Qfalse;
    bds.zn = zn - ynzero;
    if (bds.zn > 10000 || bds.yn > 10000) {
      retry:
        bds.stop = Qfalse;
        rb_nogvl(bigdivrem1, &bds, rb_big_stop, &bds, RB_NOGVL_UBF_ASYNC_SAFE);

        if (bds.stop == Qtrue) {
            /* execute trap handler, but exception was not raised. */
            goto retry;
        }
    }
    else {
        bigdivrem1(&bds);
    }
}

static void
bary_divmod_normal(BDIGIT *qds, size_t qn, BDIGIT *rds, size_t rn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    int shift;
    BDIGIT *zds, *yyds;
    size_t zn;
    VALUE tmpyz = 0;

    RUBY_ASSERT(yn < xn || (xn == yn && yds[yn - 1] <= xds[xn - 1]));
    RUBY_ASSERT(qds ? (xn - yn + 1) <= qn : 1);
    RUBY_ASSERT(rds ? yn <= rn : 1);

    zn = xn + BIGDIVREM_EXTRA_WORDS;

    shift = nlz(yds[yn-1]);
    if (shift) {
        int alloc_y = !rds;
        int alloc_z = !qds || qn < zn;
        if (alloc_y && alloc_z) {
            yyds = ALLOCV_N(BDIGIT, tmpyz, yn+zn);
            zds = yyds + yn;
        }
        else {
            yyds = alloc_y ? ALLOCV_N(BDIGIT, tmpyz, yn) : rds;
            zds = alloc_z ? ALLOCV_N(BDIGIT, tmpyz, zn) : qds;
        }
        zds[xn] = bary_small_lshift(zds, xds, xn, shift);
        bary_small_lshift(yyds, yds, yn, shift);
    }
    else {
        if (qds && zn <= qn)
            zds = qds;
        else
            zds = ALLOCV_N(BDIGIT, tmpyz, zn);
        MEMCPY(zds, xds, BDIGIT, xn);
        zds[xn] = 0;
        /* bigdivrem_restoring will not modify y.
         * So use yds directly.  */
        yyds = (BDIGIT *)yds;
    }

    bigdivrem_restoring(zds, zn, yyds, yn);

    if (rds) {
        if (shift)
            bary_small_rshift(rds, zds, yn, shift, 0);
        else
            MEMCPY(rds, zds, BDIGIT, yn);
        BDIGITS_ZERO(rds+yn, rn-yn);
    }

    if (qds) {
        size_t j = zn - yn;
        MEMMOVE(qds, zds+yn, BDIGIT, j);
        BDIGITS_ZERO(qds+j, qn-j);
    }

    if (tmpyz)
        ALLOCV_END(tmpyz);
}

VALUE
rb_big_divrem_normal(VALUE x, VALUE y)
{
    size_t xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y), qn, rn;
    BDIGIT *xds = BDIGITS(x), *yds = BDIGITS(y), *qds, *rds;
    VALUE q, r;

    BARY_TRUNC(yds, yn);
    if (yn == 0)
        rb_num_zerodiv();
    BARY_TRUNC(xds, xn);

    if (xn < yn || (xn == yn && xds[xn - 1] < yds[yn - 1]))
        return rb_assoc_new(LONG2FIX(0), x);

    qn = xn + BIGDIVREM_EXTRA_WORDS;
    q = bignew(qn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
    qds = BDIGITS(q);

    rn = yn;
    r = bignew(rn, BIGNUM_SIGN(x));
    rds = BDIGITS(r);

    bary_divmod_normal(qds, qn, rds, rn, xds, xn, yds, yn);

    bigtrunc(q);
    bigtrunc(r);

    RB_GC_GUARD(x);
    RB_GC_GUARD(y);

    return rb_assoc_new(q, r);
}

#if USE_GMP
static void
bary_divmod_gmp(BDIGIT *qds, size_t qn, BDIGIT *rds, size_t rn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    mpz_t x, y, q, r;
    size_t count;

    RUBY_ASSERT(yn < xn || (xn == yn && yds[yn - 1] <= xds[xn - 1]));
    RUBY_ASSERT(qds ? (xn - yn + 1) <= qn : 1);
    RUBY_ASSERT(rds ? yn <= rn : 1);
    RUBY_ASSERT(qds || rds);

    mpz_init(x);
    mpz_init(y);
    if (qds) mpz_init(q);
    if (rds) mpz_init(r);

    bdigits_to_mpz(x, xds, xn);
    bdigits_to_mpz(y, yds, yn);

    if (!rds) {
        mpz_fdiv_q(q, x, y);
    }
    else if (!qds) {
        mpz_fdiv_r(r, x, y);
    }
    else {
        mpz_fdiv_qr(q, r, x, y);
    }

    mpz_clear(x);
    mpz_clear(y);

    if (qds) {
        bdigits_from_mpz(q, qds, &count);
        BDIGITS_ZERO(qds+count, qn-count);
        mpz_clear(q);
    }

    if (rds) {
        bdigits_from_mpz(r, rds, &count);
        BDIGITS_ZERO(rds+count, rn-count);
        mpz_clear(r);
    }
}

VALUE
rb_big_divrem_gmp(VALUE x, VALUE y)
{
    size_t xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y), qn, rn;
    BDIGIT *xds = BDIGITS(x), *yds = BDIGITS(y), *qds, *rds;
    VALUE q, r;

    BARY_TRUNC(yds, yn);
    if (yn == 0)
        rb_num_zerodiv();
    BARY_TRUNC(xds, xn);

    if (xn < yn || (xn == yn && xds[xn - 1] < yds[yn - 1]))
        return rb_assoc_new(LONG2FIX(0), x);

    qn = xn - yn + 1;
    q = bignew(qn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
    qds = BDIGITS(q);

    rn = yn;
    r = bignew(rn, BIGNUM_SIGN(x));
    rds = BDIGITS(r);

    bary_divmod_gmp(qds, qn, rds, rn, xds, xn, yds, yn);

    bigtrunc(q);
    bigtrunc(r);

    RB_GC_GUARD(x);
    RB_GC_GUARD(y);

    return rb_assoc_new(q, r);
}
#endif

static void
bary_divmod_branch(BDIGIT *qds, size_t qn, BDIGIT *rds, size_t rn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
#if USE_GMP
    if (GMP_DIV_DIGITS < xn) {
        bary_divmod_gmp(qds, qn, rds, rn, xds, xn, yds, yn);
        return;
    }
#endif
    bary_divmod_normal(qds, qn, rds, rn, xds, xn, yds, yn);
}

static void
bary_divmod(BDIGIT *qds, size_t qn, BDIGIT *rds, size_t rn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn)
{
    RUBY_ASSERT(xn <= qn);
    RUBY_ASSERT(yn <= rn);

    BARY_TRUNC(yds, yn);
    if (yn == 0)
        rb_num_zerodiv();

    BARY_TRUNC(xds, xn);
    if (xn == 0) {
        BDIGITS_ZERO(qds, qn);
        BDIGITS_ZERO(rds, rn);
        return;
    }

    if (xn < yn || (xn == yn && xds[xn - 1] < yds[yn - 1])) {
        MEMCPY(rds, xds, BDIGIT, xn);
        BDIGITS_ZERO(rds+xn, rn-xn);
        BDIGITS_ZERO(qds, qn);
    }
    else if (yn == 1) {
        MEMCPY(qds, xds, BDIGIT, xn);
        BDIGITS_ZERO(qds+xn, qn-xn);
        rds[0] = bigdivrem_single(qds, xds, xn, yds[0]);
        BDIGITS_ZERO(rds+1, rn-1);
    }
    else if (xn == 2 && yn == 2) {
        BDIGIT_DBL x = bary2bdigitdbl(xds, 2);
        BDIGIT_DBL y = bary2bdigitdbl(yds, 2);
        BDIGIT_DBL q = x / y;
        BDIGIT_DBL r = x % y;
        qds[0] = BIGLO(q);
        qds[1] = BIGLO(BIGDN(q));
        BDIGITS_ZERO(qds+2, qn-2);
        rds[0] = BIGLO(r);
        rds[1] = BIGLO(BIGDN(r));
        BDIGITS_ZERO(rds+2, rn-2);
    }
    else {
        bary_divmod_branch(qds, qn, rds, rn, xds, xn, yds, yn);
    }
}


#ifndef BIGNUM_DEBUG
# define BIGNUM_DEBUG (0+RUBY_DEBUG)
#endif

static int
bigzero_p(VALUE x)
{
    return bary_zero_p(BDIGITS(x), BIGNUM_LEN(x));
}

int
rb_bigzero_p(VALUE x)
{
    return BIGZEROP(x);
}

int
rb_cmpint(VALUE val, VALUE a, VALUE b)
{
    if (NIL_P(val)) {
        rb_cmperr(a, b);
    }
    if (FIXNUM_P(val)) {
        long l = FIX2LONG(val);
        if (l > 0) return 1;
        if (l < 0) return -1;
        return 0;
    }
    if (RB_BIGNUM_TYPE_P(val)) {
        if (BIGZEROP(val)) return 0;
        if (BIGNUM_SIGN(val)) return 1;
        return -1;
    }
    if (RTEST(rb_funcall(val, '>', 1, INT2FIX(0)))) return 1;
    if (RTEST(rb_funcall(val, '<', 1, INT2FIX(0)))) return -1;
    return 0;
}

#define BIGNUM_SET_LEN(b,l) \
    (BIGNUM_EMBED_P(b) ? \
     (void)(RBASIC(b)->flags = \
            (RBASIC(b)->flags & ~BIGNUM_EMBED_LEN_MASK) | \
            ((l) << BIGNUM_EMBED_LEN_SHIFT)) : \
     (void)(RBIGNUM(b)->as.heap.len = (l)))

static void
rb_big_realloc(VALUE big, size_t len)
{
    BDIGIT *ds;
    if (BIGNUM_EMBED_P(big)) {
        if (BIGNUM_EMBED_LEN_MAX < len) {
            ds = ALLOC_N(BDIGIT, len);
            MEMCPY(ds, RBIGNUM(big)->as.ary, BDIGIT, BIGNUM_EMBED_LEN_MAX);
            RBIGNUM(big)->as.heap.len = BIGNUM_LEN(big);
            RBIGNUM(big)->as.heap.digits = ds;
            FL_UNSET_RAW(big, BIGNUM_EMBED_FLAG);
        }
    }
    else {
        if (len <= BIGNUM_EMBED_LEN_MAX) {
            ds = RBIGNUM(big)->as.heap.digits;
            FL_SET_RAW(big, BIGNUM_EMBED_FLAG);
            BIGNUM_SET_LEN(big, len);
            (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)RBIGNUM(big)->as.ary, sizeof(RBIGNUM(big)->as.ary));
            if (ds) {
                MEMCPY(RBIGNUM(big)->as.ary, ds, BDIGIT, len);
                xfree(ds);
            }
        }
        else {
            if (BIGNUM_LEN(big) == 0) {
                RBIGNUM(big)->as.heap.digits = ALLOC_N(BDIGIT, len);
            }
            else {
                REALLOC_N(RBIGNUM(big)->as.heap.digits, BDIGIT, len);
            }
        }
    }
}

void
rb_big_resize(VALUE big, size_t len)
{
    rb_big_realloc(big, len);
    BIGNUM_SET_LEN(big, len);
}

static VALUE
bignew_1(VALUE klass, size_t len, int sign)
{
    NEWOBJ_OF(big, struct RBignum, klass,
            T_BIGNUM | (RGENGC_WB_PROTECTED_BIGNUM ? FL_WB_PROTECTED : 0), sizeof(struct RBignum), 0);
    VALUE bigv = (VALUE)big;
    BIGNUM_SET_SIGN(bigv, sign);
    if (len <= BIGNUM_EMBED_LEN_MAX) {
        FL_SET_RAW(bigv, BIGNUM_EMBED_FLAG);
        BIGNUM_SET_LEN(bigv, len);
        (void)VALGRIND_MAKE_MEM_UNDEFINED((void*)big->as.ary, sizeof(big->as.ary));
    }
    else {
        big->as.heap.digits = ALLOC_N(BDIGIT, len);
        big->as.heap.len = len;
    }
    OBJ_FREEZE(bigv);
    return bigv;
}

VALUE
rb_big_new(size_t len, int sign)
{
    return bignew(len, sign != 0);
}

VALUE
rb_big_clone(VALUE x)
{
    size_t len = BIGNUM_LEN(x);
    VALUE z = bignew_1(CLASS_OF(x), len, BIGNUM_SIGN(x));

    MEMCPY(BDIGITS(z), BDIGITS(x), BDIGIT, len);
    return z;
}

static void
big_extend_carry(VALUE x)
{
    rb_big_resize(x, BIGNUM_LEN(x)+1);
    BDIGITS(x)[BIGNUM_LEN(x)-1] = 1;
}

/* modify a bignum by 2's complement */
static void
get2comp(VALUE x)
{
    long i = BIGNUM_LEN(x);
    BDIGIT *ds = BDIGITS(x);

    if (bary_2comp(ds, i)) {
        big_extend_carry(x);
    }
}

void
rb_big_2comp(VALUE x)			/* get 2's complement */
{
    get2comp(x);
}

static BDIGIT
abs2twocomp(VALUE *xp, long *n_ret)
{
    VALUE x = *xp;
    long n = BIGNUM_LEN(x);
    BDIGIT *ds = BDIGITS(x);
    BDIGIT hibits = 0;

    BARY_TRUNC(ds, n);

    if (n != 0 && BIGNUM_NEGATIVE_P(x)) {
        VALUE z = bignew_1(CLASS_OF(x), n, 0);
        MEMCPY(BDIGITS(z), ds, BDIGIT, n);
        bary_2comp(BDIGITS(z), n);
        hibits = BDIGMAX;
        *xp = z;
    }
    *n_ret = n;
    return hibits;
}

static void
twocomp2abs_bang(VALUE x, int hibits)
{
    BIGNUM_SET_SIGN(x, !hibits);
    if (hibits) {
        get2comp(x);
    }
}

static inline VALUE
bigtrunc(VALUE x)
{
    size_t len = BIGNUM_LEN(x);
    BDIGIT *ds = BDIGITS(x);

    if (len == 0) return x;
    while (--len && !ds[len]);
    if (BIGNUM_LEN(x) > len+1) {
        rb_big_resize(x, len+1);
    }
    return x;
}

static inline VALUE
bigfixize(VALUE x)
{
    size_t n = BIGNUM_LEN(x);
    BDIGIT *ds = BDIGITS(x);
#if SIZEOF_BDIGIT < SIZEOF_LONG
    unsigned long u;
#else
    BDIGIT u;
#endif

    BARY_TRUNC(ds, n);

    if (n == 0) return INT2FIX(0);

#if SIZEOF_BDIGIT < SIZEOF_LONG
    if (sizeof(long)/SIZEOF_BDIGIT < n)
        goto return_big;
    else {
        int i = (int)n;
        u = 0;
        while (i--) {
            u = (unsigned long)(BIGUP(u) + ds[i]);
        }
    }
#else /* SIZEOF_BDIGIT >= SIZEOF_LONG */
    if (1 < n)
        goto return_big;
    else
        u = ds[0];
#endif

    if (BIGNUM_POSITIVE_P(x)) {
        if (POSFIXABLE(u)) return LONG2FIX((long)u);
    }
    else {
        if (u <= -FIXNUM_MIN) return LONG2FIX(-(long)u);
    }

  return_big:
    rb_big_resize(x, n);
    return x;
}

static VALUE
bignorm(VALUE x)
{
    if (RB_BIGNUM_TYPE_P(x)) {
        x = bigfixize(x);
    }
    return x;
}

VALUE
rb_big_norm(VALUE x)
{
    return bignorm(x);
}

VALUE
rb_uint2big(uintptr_t n)
{
    long i;
    VALUE big = bignew(bdigit_roomof(SIZEOF_VALUE), 1);
    BDIGIT *digits = BDIGITS(big);

#if SIZEOF_BDIGIT >= SIZEOF_VALUE
    digits[0] = n;
#else
    for (i = 0; i < bdigit_roomof(SIZEOF_VALUE); i++) {
        digits[i] = BIGLO(n);
        n = BIGDN(n);
    }
#endif

    i = bdigit_roomof(SIZEOF_VALUE);
    while (--i && !digits[i]) ;
    BIGNUM_SET_LEN(big, i+1);
    return big;
}

VALUE
rb_int2big(intptr_t n)
{
    long neg = 0;
    VALUE u;
    VALUE big;

    if (n < 0) {
        u = 1 + (VALUE)(-(n + 1)); /* u = -n avoiding overflow */
        neg = 1;
    }
    else {
        u = n;
    }
    big = rb_uint2big(u);
    if (neg) {
        BIGNUM_SET_NEGATIVE_SIGN(big);
    }
    return big;
}

VALUE
rb_uint2inum(uintptr_t n)
{
    if (POSFIXABLE(n)) return LONG2FIX(n);
    return rb_uint2big(n);
}

VALUE
rb_int2inum(intptr_t n)
{
    if (FIXABLE(n)) return LONG2FIX(n);
    return rb_int2big(n);
}

void
rb_big_pack(VALUE val, unsigned long *buf, long num_longs)
{
    rb_integer_pack(val, buf, num_longs, sizeof(long), 0,
            INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER|
            INTEGER_PACK_2COMP);
}

VALUE
rb_big_unpack(unsigned long *buf, long num_longs)
{
    return rb_integer_unpack(buf, num_longs, sizeof(long), 0,
            INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER|
            INTEGER_PACK_2COMP);
}

/*
 * Calculate the number of bytes to be required to represent
 * the absolute value of the integer given as _val_.
 *
 * [val] an integer.
 * [nlz_bits_ret] number of leading zero bits in the most significant byte is returned if not NULL.
 *
 * This function returns ((val_numbits * CHAR_BIT + CHAR_BIT - 1) / CHAR_BIT)
 * where val_numbits is the number of bits of abs(val).
 * This function should not overflow.
 *
 * If nlz_bits_ret is not NULL,
 * (return_value * CHAR_BIT - val_numbits) is stored in *nlz_bits_ret.
 * In this case, 0 <= *nlz_bits_ret < CHAR_BIT.
 *
 */
size_t
rb_absint_size(VALUE val, int *nlz_bits_ret)
{
    BDIGIT *dp;
    BDIGIT *de;
    BDIGIT fixbuf[bdigit_roomof(sizeof(long))];

    int num_leading_zeros;

    val = rb_to_int(val);

    if (FIXNUM_P(val)) {
        long v = FIX2LONG(val);
        if (v < 0) {
            v = -v;
        }
#if SIZEOF_BDIGIT >= SIZEOF_LONG
        fixbuf[0] = v;
#else
        {
            int i;
            for (i = 0; i < numberof(fixbuf); i++) {
                fixbuf[i] = BIGLO(v);
                v = BIGDN(v);
            }
        }
#endif
        dp = fixbuf;
        de = fixbuf + numberof(fixbuf);
    }
    else {
        dp = BDIGITS(val);
        de = dp + BIGNUM_LEN(val);
    }
    while (dp < de && de[-1] == 0)
        de--;
    if (dp == de) {
        if (nlz_bits_ret)
            *nlz_bits_ret = 0;
        return 0;
    }
    num_leading_zeros = nlz(de[-1]);
    if (nlz_bits_ret)
        *nlz_bits_ret = num_leading_zeros % CHAR_BIT;
    return (de - dp) * SIZEOF_BDIGIT - num_leading_zeros / CHAR_BIT;
}

static size_t
absint_numwords_small(size_t numbytes, int nlz_bits_in_msbyte, size_t word_numbits, size_t *nlz_bits_ret)
{
    size_t val_numbits = numbytes * CHAR_BIT - nlz_bits_in_msbyte;
    size_t div = val_numbits / word_numbits;
    size_t mod = val_numbits % word_numbits;
    size_t numwords;
    size_t nlz_bits;
    numwords = mod == 0 ? div : div + 1;
    nlz_bits = mod == 0 ? 0 : word_numbits - mod;
    *nlz_bits_ret = nlz_bits;
    return numwords;
}

static size_t
absint_numwords_generic(size_t numbytes, int nlz_bits_in_msbyte, size_t word_numbits, size_t *nlz_bits_ret)
{
    static const BDIGIT char_bit[1] = { CHAR_BIT };
    BDIGIT numbytes_bary[bdigit_roomof(sizeof(numbytes))];
    BDIGIT val_numbits_bary[bdigit_roomof(sizeof(numbytes) + 1)];
    BDIGIT nlz_bits_in_msbyte_bary[1];
    BDIGIT word_numbits_bary[bdigit_roomof(sizeof(word_numbits))];
    BDIGIT div_bary[numberof(val_numbits_bary) + BIGDIVREM_EXTRA_WORDS];
    BDIGIT mod_bary[numberof(word_numbits_bary)];
    BDIGIT one[1] = { 1 };
    size_t nlz_bits;
    size_t mod;
    int sign;
    size_t numwords;

    nlz_bits_in_msbyte_bary[0] = nlz_bits_in_msbyte;

    /*
     * val_numbits = numbytes * CHAR_BIT - nlz_bits_in_msbyte
     * div, mod = val_numbits.divmod(word_numbits)
     * numwords = mod == 0 ? div : div + 1
     * nlz_bits = mod == 0 ? 0 : word_numbits - mod
     */

    bary_unpack(BARY_ARGS(numbytes_bary), &numbytes, 1, sizeof(numbytes), 0,
        INTEGER_PACK_NATIVE_BYTE_ORDER);
    BARY_SHORT_MUL(val_numbits_bary, numbytes_bary, char_bit);
    if (nlz_bits_in_msbyte)
        BARY_SUB(val_numbits_bary, val_numbits_bary, nlz_bits_in_msbyte_bary);
    bary_unpack(BARY_ARGS(word_numbits_bary), &word_numbits, 1, sizeof(word_numbits), 0,
        INTEGER_PACK_NATIVE_BYTE_ORDER);
    BARY_DIVMOD(div_bary, mod_bary, val_numbits_bary, word_numbits_bary);
    if (BARY_ZERO_P(mod_bary)) {
        nlz_bits = 0;
    }
    else {
        BARY_ADD(div_bary, div_bary, one);
        bary_pack(+1, BARY_ARGS(mod_bary), &mod, 1, sizeof(mod), 0,
            INTEGER_PACK_NATIVE_BYTE_ORDER);
        nlz_bits = word_numbits - mod;
    }
    sign = bary_pack(+1, BARY_ARGS(div_bary), &numwords, 1, sizeof(numwords), 0,
        INTEGER_PACK_NATIVE_BYTE_ORDER);

    if (sign == 2) {
#if defined __GNUC__ && (__GNUC__ == 4 && __GNUC_MINOR__ == 4)
        *nlz_bits_ret = 0;
#endif
        return (size_t)-1;
    }
    *nlz_bits_ret = nlz_bits;
    return numwords;
}

/*
 * Calculate the number of words to be required to represent
 * the absolute value of the integer given as _val_.
 *
 * [val] an integer.
 * [word_numbits] number of bits in a word.
 * [nlz_bits_ret] number of leading zero bits in the most significant word is returned if not NULL.
 *
 * This function returns ((val_numbits * CHAR_BIT + word_numbits - 1) / word_numbits)
 * where val_numbits is the number of bits of abs(val).
 *
 * This function can overflow.
 * When overflow occur, (size_t)-1 is returned.
 *
 * If nlz_bits_ret is not NULL and overflow is not occur,
 * (return_value * word_numbits - val_numbits) is stored in *nlz_bits_ret.
 * In this case, 0 <= *nlz_bits_ret < word_numbits.
 *
 */
size_t
rb_absint_numwords(VALUE val, size_t word_numbits, size_t *nlz_bits_ret)
{
    size_t numbytes;
    int nlz_bits_in_msbyte;
    size_t numwords;
    size_t nlz_bits = 0;

    if (word_numbits == 0)
        return (size_t)-1;

    numbytes = rb_absint_size(val, &nlz_bits_in_msbyte);

    if (numbytes <= SIZE_MAX / CHAR_BIT) {
        numwords = absint_numwords_small(numbytes, nlz_bits_in_msbyte, word_numbits, &nlz_bits);
        if (debug_integer_pack) {
            size_t numwords0, nlz_bits0;
            numwords0 = absint_numwords_generic(numbytes, nlz_bits_in_msbyte, word_numbits, &nlz_bits0);
            RUBY_ASSERT(numwords0 == numwords);
            RUBY_ASSERT(nlz_bits0 == nlz_bits);
            (void)numwords0;
        }
    }
    else {
        numwords = absint_numwords_generic(numbytes, nlz_bits_in_msbyte, word_numbits, &nlz_bits);
    }
    if (numwords == (size_t)-1)
        return numwords;

    if (nlz_bits_ret)
        *nlz_bits_ret = nlz_bits;

    return numwords;
}

/* Test abs(val) consists only a bit or not.
 *
 * Returns 1 if abs(val) == 1 << n for some n >= 0.
 * Returns 0 otherwise.
 *
 * rb_absint_singlebit_p can be used to determine required buffer size
 * for rb_integer_pack used with INTEGER_PACK_2COMP (two's complement).
 *
 * Following example calculates number of bits required to
 * represent val in two's complement number, without sign bit.
 *
 *   size_t size;
 *   int neg = FIXNUM_P(val) ? FIX2LONG(val) < 0 : BIGNUM_NEGATIVE_P(val);
 *   size = rb_absint_numwords(val, 1, NULL)
 *   if (size == (size_t)-1) ...overflow...
 *   if (neg && rb_absint_singlebit_p(val))
 *     size--;
 *
 * Following example calculates number of bytes required to
 * represent val in two's complement number, with sign bit.
 *
 *   size_t size;
 *   int neg = FIXNUM_P(val) ? FIX2LONG(val) < 0 : BIGNUM_NEGATIVE_P(val);
 *   int nlz_bits;
 *   size = rb_absint_size(val, &nlz_bits);
 *   if (nlz_bits == 0 && !(neg && rb_absint_singlebit_p(val)))
 *     size++;
 */
int
rb_absint_singlebit_p(VALUE val)
{
    BDIGIT *dp;
    BDIGIT *de;
    BDIGIT fixbuf[bdigit_roomof(sizeof(long))];
    BDIGIT d;

    val = rb_to_int(val);

    if (FIXNUM_P(val)) {
        long v = FIX2LONG(val);
        if (v < 0) {
            v = -v;
        }
#if SIZEOF_BDIGIT >= SIZEOF_LONG
        fixbuf[0] = v;
#else
        {
            int i;
            for (i = 0; i < numberof(fixbuf); i++) {
                fixbuf[i] = BIGLO(v);
                v = BIGDN(v);
            }
        }
#endif
        dp = fixbuf;
        de = fixbuf + numberof(fixbuf);
    }
    else {
        dp = BDIGITS(val);
        de = dp + BIGNUM_LEN(val);
    }
    while (dp < de && de[-1] == 0)
        de--;
    while (dp < de && dp[0] == 0)
        dp++;
    if (dp == de) /* no bit set. */
        return 0;
    if (dp != de-1) /* two non-zero words. two bits set, at least. */
        return 0;
    d = *dp;
    return POW2_P(d);
}


/*
 * Export an integer into a buffer.
 *
 * This function fills the buffer specified by _words_ and _numwords_ as
 * val in the format specified by _wordsize_, _nails_ and _flags_.
 *
 * [val] Fixnum, Bignum or another integer like object which has to_int method.
 * [words] buffer to export abs(val).
 * [numwords] the size of given buffer as number of words.
 * [wordsize] the size of word as number of bytes.
 * [nails] number of padding bits in a word.
 *   Most significant nails bits of each word are filled by zero.
 * [flags] bitwise or of constants which name starts "INTEGER_PACK_".
 *
 * flags:
 * [INTEGER_PACK_MSWORD_FIRST] Store the most significant word as the first word.
 * [INTEGER_PACK_LSWORD_FIRST] Store the least significant word as the first word.
 * [INTEGER_PACK_MSBYTE_FIRST] Store the most significant byte in a word as the first byte in the word.
 * [INTEGER_PACK_LSBYTE_FIRST] Store the least significant byte in a word as the first byte in the word.
 * [INTEGER_PACK_NATIVE_BYTE_ORDER] INTEGER_PACK_MSBYTE_FIRST or INTEGER_PACK_LSBYTE_FIRST corresponding to the host's endian.
 * [INTEGER_PACK_2COMP] Use 2's complement representation.
 * [INTEGER_PACK_LITTLE_ENDIAN] Same as INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_LSBYTE_FIRST
 * [INTEGER_PACK_BIG_ENDIAN] Same as INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_MSBYTE_FIRST
 * [INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION] Use generic implementation (for test and debug).
 *
 * This function fills the buffer specified by _words_
 * as abs(val) if INTEGER_PACK_2COMP is not specified in _flags_.
 * If INTEGER_PACK_2COMP is specified, 2's complement representation of val is
 * filled in the buffer.
 *
 * This function returns the signedness and overflow condition.
 * The overflow condition depends on INTEGER_PACK_2COMP.
 *
 * INTEGER_PACK_2COMP is not specified:
 *   -2 : negative overflow.  val <= -2**(numwords*(wordsize*CHAR_BIT-nails))
 *   -1 : negative without overflow.  -2**(numwords*(wordsize*CHAR_BIT-nails)) < val < 0
 *   0 : zero.  val == 0
 *   1 : positive without overflow.  0 < val < 2**(numwords*(wordsize*CHAR_BIT-nails))
 *   2 : positive overflow.  2**(numwords*(wordsize*CHAR_BIT-nails)) <= val
 *
 * INTEGER_PACK_2COMP is specified:
 *   -2 : negative overflow.  val < -2**(numwords*(wordsize*CHAR_BIT-nails))
 *   -1 : negative without overflow.  -2**(numwords*(wordsize*CHAR_BIT-nails)) <= val < 0
 *   0 : zero.  val == 0
 *   1 : positive without overflow.  0 < val < 2**(numwords*(wordsize*CHAR_BIT-nails))
 *   2 : positive overflow.  2**(numwords*(wordsize*CHAR_BIT-nails)) <= val
 *
 * The value, -2**(numwords*(wordsize*CHAR_BIT-nails)), is representable
 * in 2's complement representation but not representable in absolute value.
 * So -1 is returned for the value if INTEGER_PACK_2COMP is specified
 * but returns -2 if INTEGER_PACK_2COMP is not specified.
 *
 * The least significant words are filled in the buffer when overflow occur.
 */

int
rb_integer_pack(VALUE val, void *words, size_t numwords, size_t wordsize, size_t nails, int flags)
{
    int sign;
    BDIGIT *ds;
    size_t num_bdigits;
    BDIGIT fixbuf[bdigit_roomof(sizeof(long))];

    RB_GC_GUARD(val) = rb_to_int(val);

    if (FIXNUM_P(val)) {
        long v = FIX2LONG(val);
        if (v < 0) {
            sign = -1;
            v = -v;
        }
        else {
            sign = 1;
        }
#if SIZEOF_BDIGIT >= SIZEOF_LONG
        fixbuf[0] = v;
#else
        {
            int i;
            for (i = 0; i < numberof(fixbuf); i++) {
                fixbuf[i] = BIGLO(v);
                v = BIGDN(v);
            }
        }
#endif
        ds = fixbuf;
        num_bdigits = numberof(fixbuf);
    }
    else {
        sign = BIGNUM_POSITIVE_P(val) ? 1 : -1;
        ds = BDIGITS(val);
        num_bdigits = BIGNUM_LEN(val);
    }

    return bary_pack(sign, ds, num_bdigits, words, numwords, wordsize, nails, flags);
}

/*
 * Import an integer from a buffer.
 *
 * [words] buffer to import.
 * [numwords] the size of given buffer as number of words.
 * [wordsize] the size of word as number of bytes.
 * [nails] number of padding bits in a word.
 *   Most significant nails bits of each word are ignored.
 * [flags] bitwise or of constants which name starts "INTEGER_PACK_".
 *
 * flags:
 * [INTEGER_PACK_MSWORD_FIRST] Interpret the first word as the most significant word.
 * [INTEGER_PACK_LSWORD_FIRST] Interpret the first word as the least significant word.
 * [INTEGER_PACK_MSBYTE_FIRST] Interpret the first byte in a word as the most significant byte in the word.
 * [INTEGER_PACK_LSBYTE_FIRST] Interpret the first byte in a word as the least significant byte in the word.
 * [INTEGER_PACK_NATIVE_BYTE_ORDER] INTEGER_PACK_MSBYTE_FIRST or INTEGER_PACK_LSBYTE_FIRST corresponding to the host's endian.
 * [INTEGER_PACK_2COMP] Use 2's complement representation.
 * [INTEGER_PACK_LITTLE_ENDIAN] Same as INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_LSBYTE_FIRST
 * [INTEGER_PACK_BIG_ENDIAN] Same as INTEGER_PACK_MSWORD_FIRST|INTEGER_PACK_MSBYTE_FIRST
 * [INTEGER_PACK_FORCE_BIGNUM] the result will be a Bignum
 *   even if it is representable as a Fixnum.
 * [INTEGER_PACK_NEGATIVE] Returns non-positive value.
 *   (Returns non-negative value if not specified.)
 * [INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION] Use generic implementation (for test and debug).
 *
 * This function returns the imported integer as Fixnum or Bignum.
 *
 * The range of the result value depends on INTEGER_PACK_2COMP and INTEGER_PACK_NEGATIVE.
 *
 * INTEGER_PACK_2COMP is not set:
 *   0 <= val < 2**(numwords*(wordsize*CHAR_BIT-nails)) if !INTEGER_PACK_NEGATIVE
 *   -2**(numwords*(wordsize*CHAR_BIT-nails)) < val <= 0 if INTEGER_PACK_NEGATIVE
 *
 * INTEGER_PACK_2COMP is set:
 *   -2**(numwords*(wordsize*CHAR_BIT-nails)-1) <= val <= 2**(numwords*(wordsize*CHAR_BIT-nails)-1)-1 if !INTEGER_PACK_NEGATIVE
 *   -2**(numwords*(wordsize*CHAR_BIT-nails)) <= val <= -1 if INTEGER_PACK_NEGATIVE
 *
 * INTEGER_PACK_2COMP without INTEGER_PACK_NEGATIVE means sign extension.
 * INTEGER_PACK_2COMP with INTEGER_PACK_NEGATIVE mean assuming the higher bits are 1.
 *
 * Note that this function returns 0 when numwords is zero and
 * INTEGER_PACK_2COMP is set but INTEGER_PACK_NEGATIVE is not set.
 */

VALUE
rb_integer_unpack(const void *words, size_t numwords, size_t wordsize, size_t nails, int flags)
{
    VALUE val;
    size_t num_bdigits;
    int sign;
    int nlp_bits;
    BDIGIT *ds;
    BDIGIT fixbuf[2] = { 0, 0 };

    validate_integer_pack_format(numwords, wordsize, nails, flags,
            INTEGER_PACK_MSWORD_FIRST|
            INTEGER_PACK_LSWORD_FIRST|
            INTEGER_PACK_MSBYTE_FIRST|
            INTEGER_PACK_LSBYTE_FIRST|
            INTEGER_PACK_NATIVE_BYTE_ORDER|
            INTEGER_PACK_2COMP|
            INTEGER_PACK_FORCE_BIGNUM|
            INTEGER_PACK_NEGATIVE|
            INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION);

    num_bdigits = integer_unpack_num_bdigits(numwords, wordsize, nails, &nlp_bits);

    if (LONG_MAX-1 < num_bdigits)
        rb_raise(rb_eArgError, "too big to unpack as an integer");
    if (num_bdigits <= numberof(fixbuf) && !(flags & INTEGER_PACK_FORCE_BIGNUM)) {
        val = Qfalse;
        ds = fixbuf;
    }
    else {
        val = bignew((long)num_bdigits, 0);
        ds = BDIGITS(val);
    }
    sign = bary_unpack_internal(ds, num_bdigits, words, numwords, wordsize, nails, flags, nlp_bits);

    if (sign == -2) {
        if (val) {
            big_extend_carry(val);
        }
        else if (num_bdigits == numberof(fixbuf)) {
            val = bignew((long)num_bdigits+1, 0);
            MEMCPY(BDIGITS(val), fixbuf, BDIGIT, num_bdigits);
            BDIGITS(val)[num_bdigits++] = 1;
        }
        else {
            ds[num_bdigits++] = 1;
        }
    }

    if (!val) {
        BDIGIT_DBL u = fixbuf[0] + BIGUP(fixbuf[1]);
        if (u == 0)
            return LONG2FIX(0);
        if (0 < sign && POSFIXABLE(u))
            return LONG2FIX((long)u);
        if (sign < 0 && BDIGIT_MSB(fixbuf[1]) == 0 &&
                NEGFIXABLE(-(BDIGIT_DBL_SIGNED)u))
            return LONG2FIX((long)-(BDIGIT_DBL_SIGNED)u);
        val = bignew((long)num_bdigits, 0 <= sign);
        MEMCPY(BDIGITS(val), fixbuf, BDIGIT, num_bdigits);
    }

    if ((flags & INTEGER_PACK_FORCE_BIGNUM) && sign != 0 &&
        bary_zero_p(BDIGITS(val), BIGNUM_LEN(val)))
        sign = 0;
    BIGNUM_SET_SIGN(val, 0 <= sign);

    if (flags & INTEGER_PACK_FORCE_BIGNUM)
        return bigtrunc(val);
    return bignorm(val);
}

#define conv_digit(c) (ruby_digit36_to_number_table[(unsigned char)(c)])

NORETURN(static inline void invalid_radix(int base));
NORETURN(static inline void invalid_integer(VALUE s));

static inline int
valid_radix_p(int base)
{
    return (1 < base && base <= 36);
}

static inline void
invalid_radix(int base)
{
    rb_raise(rb_eArgError, "invalid radix %d", base);
}

static inline void
invalid_integer(VALUE s)
{
    rb_raise(rb_eArgError, "invalid value for Integer(): %+"PRIsVALUE, s);
}

static int
str2big_scan_digits(const char *s, const char *str, int base, int badcheck, size_t *num_digits_p, ssize_t *len_p)
{
    char nondigit = 0;
    size_t num_digits = 0;
    const char *digits_start = str;
    const char *digits_end = str;
    ssize_t len = *len_p;

    int c;

    if (!len) {
        *num_digits_p = 0;
        *len_p = 0;
        return TRUE;
    }

    if (badcheck && *str == '_') return FALSE;

    while ((c = *str++) != 0) {
        if (c == '_') {
            if (nondigit) {
                if (badcheck) return FALSE;
                break;
            }
            nondigit = (char) c;
        }
        else if ((c = conv_digit(c)) < 0 || c >= base) {
            break;
        }
        else {
            nondigit = 0;
            num_digits++;
            digits_end = str;
        }
        if (len > 0 && !--len) break;
    }
    if (badcheck && nondigit) return FALSE;
    if (badcheck && len) {
        str--;
        while (*str && ISSPACE(*str)) {
            str++;
            if (len > 0 && !--len) break;
        }
        if (len && *str) {
            return FALSE;
        }
    }
    *num_digits_p = num_digits;
    *len_p = digits_end - digits_start;
    return TRUE;
}

static VALUE
str2big_poweroftwo(
    int sign,
    const char *digits_start,
    const char *digits_end,
    size_t num_digits,
    int bits_per_digit)
{
    BDIGIT *dp;
    BDIGIT_DBL dd;
    int numbits;

    size_t num_bdigits;
    const char *p;
    int c;
    VALUE z;

    num_bdigits = (num_digits / BITSPERDIG) * bits_per_digit + roomof((num_digits % BITSPERDIG) * bits_per_digit, BITSPERDIG);
    z = bignew(num_bdigits, sign);
    dp = BDIGITS(z);
    dd = 0;
    numbits = 0;
    for (p = digits_end; digits_start < p; p--) {
        if ((c = conv_digit(p[-1])) < 0)
            continue;
        dd |= (BDIGIT_DBL)c << numbits;
        numbits += bits_per_digit;
        if (BITSPERDIG <= numbits) {
            *dp++ = BIGLO(dd);
            dd = BIGDN(dd);
            numbits -= BITSPERDIG;
        }
    }
    if (numbits) {
        *dp++ = BIGLO(dd);
    }
    RUBY_ASSERT((size_t)(dp - BDIGITS(z)) == num_bdigits);

    return z;
}

static VALUE
str2big_normal(
    int sign,
    const char *digits_start,
    const char *digits_end,
    size_t num_bdigits,
    int base)
{
    size_t blen = 1;
    BDIGIT *zds;
    BDIGIT_DBL num;

    size_t i;
    const char *p;
    int c;
    VALUE z;

    z = bignew(num_bdigits, sign);
    zds = BDIGITS(z);
    BDIGITS_ZERO(zds, num_bdigits);

    for (p = digits_start; p < digits_end; p++) {
        if ((c = conv_digit(*p)) < 0)
            continue;
        num = c;
        i = 0;
        for (;;) {
            while (i<blen) {
                num += (BDIGIT_DBL)zds[i]*base;
                zds[i++] = BIGLO(num);
                num = BIGDN(num);
            }
            if (num) {
                blen++;
                continue;
            }
            break;
        }
        RUBY_ASSERT(blen <= num_bdigits);
    }

    return z;
}

static VALUE
str2big_karatsuba(
    int sign,
    const char *digits_start,
    const char *digits_end,
    size_t num_digits,
    size_t num_bdigits,
    int digits_per_bdigits_dbl,
    int base)
{
    VALUE powerv;
    size_t unit;
    VALUE tmpuv = 0;
    BDIGIT *uds, *vds, *tds;
    BDIGIT_DBL dd;
    BDIGIT_DBL current_base;
    int m;
    int power_level = 0;

    size_t i;
    const char *p;
    int c;
    VALUE z;

    uds = ALLOCV_N(BDIGIT, tmpuv, 2*num_bdigits);
    vds = uds + num_bdigits;

    powerv = power_cache_get_power(base, power_level, NULL);

    i = 0;
    dd = 0;
    current_base = 1;
    m = digits_per_bdigits_dbl;
    if (num_digits < (size_t)m)
        m = (int)num_digits;
    for (p = digits_end; digits_start < p; p--) {
        if ((c = conv_digit(p[-1])) < 0)
            continue;
        dd = dd + c * current_base;
        current_base *= base;
        num_digits--;
        m--;
        if (m == 0) {
            uds[i++] = BIGLO(dd);
            uds[i++] = (BDIGIT)BIGDN(dd);
            dd = 0;
            m = digits_per_bdigits_dbl;
            if (num_digits < (size_t)m)
                m = (int)num_digits;
            current_base = 1;
        }
    }
    RUBY_ASSERT(i == num_bdigits);
    for (unit = 2; unit < num_bdigits; unit *= 2) {
        for (i = 0; i < num_bdigits; i += unit*2) {
            if (2*unit <= num_bdigits - i) {
                bary_mul(vds+i, unit*2, BDIGITS(powerv), BIGNUM_LEN(powerv), uds+i+unit, unit);
                bary_add(vds+i, unit*2, vds+i, unit*2, uds+i, unit);
            }
            else if (unit <= num_bdigits - i) {
                bary_mul(vds+i, num_bdigits-i, BDIGITS(powerv), BIGNUM_LEN(powerv), uds+i+unit, num_bdigits-(i+unit));
                bary_add(vds+i, num_bdigits-i, vds+i, num_bdigits-i, uds+i, unit);
            }
            else {
                MEMCPY(vds+i, uds+i, BDIGIT, num_bdigits-i);
            }
        }
        power_level++;
        powerv = power_cache_get_power(base, power_level, NULL);
        tds = vds;
        vds = uds;
        uds = tds;
    }
    BARY_TRUNC(uds, num_bdigits);
    z = bignew(num_bdigits, sign);
    MEMCPY(BDIGITS(z), uds, BDIGIT, num_bdigits);

    if (tmpuv)
        ALLOCV_END(tmpuv);

    return z;
}

#if USE_GMP
static VALUE
str2big_gmp(
    int sign,
    const char *digits_start,
    const char *digits_end,
    size_t num_digits,
    size_t num_bdigits,
    int base)
{
    char *buf, *p;
    const char *q;
    VALUE tmps;
    mpz_t mz;
    VALUE z;
    BDIGIT *zds;
    size_t zn, count;

    buf = ALLOCV_N(char, tmps, num_digits+1);
    p = buf;
    for (q = digits_start; q < digits_end; q++) {
        if (conv_digit(*q) < 0)
            continue;
        *p++ = *q;
    }
    *p = '\0';

    mpz_init(mz);
    mpz_set_str(mz, buf, base);
    zn = num_bdigits;
    z = bignew(zn, sign);
    zds = BDIGITS(z);
    bdigits_from_mpz(mz, BDIGITS(z), &count);
    BDIGITS_ZERO(zds+count, zn-count);
    mpz_clear(mz);

    if (tmps)
        ALLOCV_END(tmps);

    return z;
}
#endif

static VALUE rb_cstr_parse_inum(const char *str, ssize_t len, char **endp, int base);

/*
 * Parse +str+ as Ruby Integer, i.e., underscores, 0d and 0b prefixes.
 *
 * str:      pointer to the string to be parsed.
 *	     should be NUL-terminated.
 * base:     base of conversion, must be 2..36, or -36..0.
 *           if +base+ > 0, the conversion is done according to the +base+
 *           and unmatched prefix is parsed as a part of the result if
 *           present.
 *           if +base+ <= 0, the conversion is done according to the
 *           prefix if present, in base <code>-base</code> if +base+ < -1,
 *           or in base 10.
 * badcheck: if non-zero, +ArgumentError+ is raised when +str+ is not
 *           valid as an Integer.  if zero, Fixnum 0 is returned in
 *           that case.
 */
VALUE
rb_cstr_to_inum(const char *str, int base, int badcheck)
{
    char *end;
    VALUE ret = rb_cstr_parse_inum(str, -1, (badcheck ? NULL : &end), base);
    if (NIL_P(ret)) {
        if (badcheck) rb_invalid_str(str, "Integer()");
        ret = INT2FIX(0);
    }
    return ret;
}

/*
 * Parse +str+ as Ruby Integer, i.e., underscores, 0d and 0b prefixes.
 *
 * str:  pointer to the string to be parsed.
 *       should be NUL-terminated if +len+ is negative.
 * len:  length of +str+ if >= 0.  if +len+ is negative, +str+ should
 *       be NUL-terminated.
 * endp: if non-NULL, the address after parsed part is stored.  if
 *       NULL, Qnil is returned when +str+ is not valid as an Integer.
 * ndigits: if non-NULL, the number of parsed digits is stored.
 * base: see +rb_cstr_to_inum+
 * flags: bitwise OR of below flags:
 *       RB_INT_PARSE_SIGN: allow preceding spaces and +/- sign
 *       RB_INT_PARSE_UNDERSCORE: allow an underscore between digits
 *       RB_INT_PARSE_PREFIX: allow preceding prefix
 */

VALUE
rb_int_parse_cstr(const char *str, ssize_t len, char **endp, size_t *ndigits,
                  int base, int flags)
{
    const char *const s = str;
    char sign = 1;
    int c;
    VALUE z = Qnil;

    unsigned long val;
    int ov;

    const char *digits_start, *digits_end;
    size_t num_digits = 0;
    size_t num_bdigits;
    const ssize_t len0 = len;
    const int badcheck = !endp;

#define ADV(n) do {\
        if (len > 0 && len <= (n)) goto bad; \
        str += (n); \
        len -= (n); \
    } while (0)
#define ASSERT_LEN() do {\
        RUBY_ASSERT(len != 0); \
        if (len0 >= 0) RUBY_ASSERT(s + len0 == str + len); \
    } while (0)

    if (!str) {
        goto bad;
    }
    if (len && (flags & RB_INT_PARSE_SIGN)) {
        while (ISSPACE(*str)) ADV(1);

        if (str[0] == '+') {
            ADV(1);
        }
        else if (str[0] == '-') {
            ADV(1);
            sign = 0;
        }
        ASSERT_LEN();
    }
    if (base <= 0) {
        if (str[0] == '0' && len > 1) {
            switch (str[1]) {
              case 'x': case 'X':
                base = 16;
                ADV(2);
                break;
              case 'b': case 'B':
                base = 2;
                ADV(2);
                break;
              case 'o': case 'O':
                base = 8;
                ADV(2);
                break;
              case 'd': case 'D':
                base = 10;
                ADV(2);
                break;
              default:
                base = 8;
            }
        }
        else if (base < -1) {
            base = -base;
        }
        else {
            base = 10;
        }
    }
    else if (len == 1 || !(flags & RB_INT_PARSE_PREFIX)) {
        /* no prefix */
    }
    else if (base == 2) {
        if (str[0] == '0' && (str[1] == 'b'||str[1] == 'B')) {
            ADV(2);
        }
    }
    else if (base == 8) {
        if (str[0] == '0' && (str[1] == 'o'||str[1] == 'O')) {
            ADV(2);
        }
    }
    else if (base == 10) {
        if (str[0] == '0' && (str[1] == 'd'||str[1] == 'D')) {
            ADV(2);
        }
    }
    else if (base == 16) {
        if (str[0] == '0' && (str[1] == 'x'||str[1] == 'X')) {
            ADV(2);
        }
    }
    if (!valid_radix_p(base)) {
        invalid_radix(base);
    }
    if (!len) goto bad;
    num_digits = str - s;
    if (*str == '0' && len != 1) { /* squeeze preceding 0s */
        int us = 0;
        const char *end = len < 0 ? NULL : str + len;
        ++num_digits;
        while ((c = *++str) == '0' ||
               ((flags & RB_INT_PARSE_UNDERSCORE) && c == '_')) {
            if (c == '_') {
                if (++us >= 2)
                    break;
            }
            else {
                ++num_digits;
                us = 0;
            }
            if (str == end) break;
        }
        if (!c || ISSPACE(c)) --str;
        if (end) len = end - str;
    }
    c = *str;
    c = conv_digit(c);
    if (c < 0 || c >= base) {
        if (!badcheck && num_digits) z = INT2FIX(0);
        goto bad;
    }

    if (ndigits) *ndigits = num_digits;
    val = ruby_scan_digits(str, len, base, &num_digits, &ov);
    if (!ov) {
        const char *end = &str[num_digits];
        if (num_digits > 0 && *end == '_' && (flags & RB_INT_PARSE_UNDERSCORE))
            goto bigparse;
        if (endp) *endp = (char *)end;
        if (ndigits) *ndigits += num_digits;
        if (badcheck) {
            if (num_digits == 0) return Qnil; /* no number */
            while (len < 0 ? *end : end < str + len) {
                if (!ISSPACE(*end)) return Qnil; /* trailing garbage */
                end++;
            }
        }

        if (POSFIXABLE(val)) {
            if (sign) return LONG2FIX(val);
            else {
                long result = -(long)val;
                return LONG2FIX(result);
            }
        }
        else {
            VALUE big = rb_uint2big(val);
            BIGNUM_SET_SIGN(big, sign);
            return bignorm(big);
        }
    }

  bigparse:
    digits_start = str;
    if (!str2big_scan_digits(s, str, base, badcheck, &num_digits, &len))
        goto bad;
    if (endp) *endp = (char *)(str + len);
    if (ndigits) *ndigits += num_digits;
    digits_end = digits_start + len;

    if (POW2_P(base)) {
        z = str2big_poweroftwo(sign, digits_start, digits_end, num_digits,
                               bit_length(base-1));
    }
    else {
        int digits_per_bdigits_dbl;
        maxpow_in_bdigit_dbl(base, &digits_per_bdigits_dbl);
        num_bdigits = roomof(num_digits, digits_per_bdigits_dbl)*2;

#if USE_GMP
        if (GMP_STR2BIG_DIGITS < num_bdigits) {
            z = str2big_gmp(sign, digits_start, digits_end, num_digits,
                    num_bdigits, base);
        }
        else
#endif
        if (num_bdigits < KARATSUBA_MUL_DIGITS) {
            z = str2big_normal(sign, digits_start, digits_end,
                    num_bdigits, base);
        }
        else {
            z = str2big_karatsuba(sign, digits_start, digits_end, num_digits,
                    num_bdigits, digits_per_bdigits_dbl, base);
        }
    }

    return bignorm(z);

  bad:
    if (endp) *endp = (char *)str;
    if (ndigits) *ndigits = num_digits;
    return z;
}

static VALUE
rb_cstr_parse_inum(const char *str, ssize_t len, char **endp, int base)
{
    return rb_int_parse_cstr(str, len, endp, NULL, base,
                             RB_INT_PARSE_DEFAULT);
}

VALUE
rb_str_convert_to_inum(VALUE str, int base, int badcheck, int raise_exception)
{
    VALUE ret;
    const char *s;
    long len;
    char *end;

    StringValue(str);
    rb_must_asciicompat(str);
    RSTRING_GETMEM(str, s, len);
    ret = rb_cstr_parse_inum(s, len, (badcheck ? NULL : &end), base);
    if (NIL_P(ret)) {
        if (badcheck) {
            if (!raise_exception) return Qnil;
            invalid_integer(str);
        }
        ret = INT2FIX(0);
    }
    return ret;
}

VALUE
rb_str_to_inum(VALUE str, int base, int badcheck)
{
    return rb_str_convert_to_inum(str, base, badcheck, TRUE);
}

VALUE
rb_str2big_poweroftwo(VALUE arg, int base, int badcheck)
{
    int positive_p = 1;
    const char *s, *str;
    const char *digits_start, *digits_end;
    size_t num_digits;
    ssize_t len;
    VALUE z;

    if (!valid_radix_p(base) || !POW2_P(base)) {
        invalid_radix(base);
    }

    rb_must_asciicompat(arg);
    s = str = StringValueCStr(arg);
    len = RSTRING_LEN(arg);
    if (*str == '-') {
        len--;
        str++;
        positive_p = 0;
    }

    digits_start = str;
    if (!str2big_scan_digits(s, str, base, badcheck, &num_digits, &len))
        invalid_integer(arg);
    digits_end = digits_start + len;

    z = str2big_poweroftwo(positive_p, digits_start, digits_end, num_digits,
            bit_length(base-1));

    RB_GC_GUARD(arg);

    return bignorm(z);
}

VALUE
rb_str2big_normal(VALUE arg, int base, int badcheck)
{
    int positive_p = 1;
    const char *s, *str;
    const char *digits_start, *digits_end;
    size_t num_digits;
    ssize_t len;
    VALUE z;

    int digits_per_bdigits_dbl;
    size_t num_bdigits;

    if (!valid_radix_p(base)) {
        invalid_radix(base);
    }

    rb_must_asciicompat(arg);
    s = str = StringValuePtr(arg);
    len = RSTRING_LEN(arg);
    if (len > 0 && *str == '-') {
        len--;
        str++;
        positive_p = 0;
    }

    digits_start = str;
    if (!str2big_scan_digits(s, str, base, badcheck, &num_digits, &len))
        invalid_integer(arg);
    digits_end = digits_start + len;

    maxpow_in_bdigit_dbl(base, &digits_per_bdigits_dbl);
    num_bdigits = roomof(num_digits, digits_per_bdigits_dbl)*2;

    z = str2big_normal(positive_p, digits_start, digits_end,
            num_bdigits, base);

    RB_GC_GUARD(arg);

    return bignorm(z);
}

VALUE
rb_str2big_karatsuba(VALUE arg, int base, int badcheck)
{
    int positive_p = 1;
    const char *s, *str;
    const char *digits_start, *digits_end;
    size_t num_digits;
    ssize_t len;
    VALUE z;

    int digits_per_bdigits_dbl;
    size_t num_bdigits;

    if (!valid_radix_p(base)) {
        invalid_radix(base);
    }

    rb_must_asciicompat(arg);
    s = str = StringValuePtr(arg);
    len = RSTRING_LEN(arg);
    if (len > 0 && *str == '-') {
        len--;
        str++;
        positive_p = 0;
    }

    digits_start = str;
    if (!str2big_scan_digits(s, str, base, badcheck, &num_digits, &len))
        invalid_integer(arg);
    digits_end = digits_start + len;

    maxpow_in_bdigit_dbl(base, &digits_per_bdigits_dbl);
    num_bdigits = roomof(num_digits, digits_per_bdigits_dbl)*2;

    z = str2big_karatsuba(positive_p, digits_start, digits_end, num_digits,
            num_bdigits, digits_per_bdigits_dbl, base);

    RB_GC_GUARD(arg);

    return bignorm(z);
}

#if USE_GMP
VALUE
rb_str2big_gmp(VALUE arg, int base, int badcheck)
{
    int positive_p = 1;
    const char *s, *str;
    const char *digits_start, *digits_end;
    size_t num_digits;
    ssize_t len;
    VALUE z;

    int digits_per_bdigits_dbl;
    size_t num_bdigits;

    if (!valid_radix_p(base)) {
        invalid_radix(base);
    }

    rb_must_asciicompat(arg);
    s = str = StringValuePtr(arg);
    len = RSTRING_LEN(arg);
    if (len > 0 && *str == '-') {
        len--;
        str++;
        positive_p = 0;
    }

    digits_start = str;
    if (!str2big_scan_digits(s, str, base, badcheck, &num_digits, &len))
        invalid_integer(arg);
    digits_end = digits_start + len;

    maxpow_in_bdigit_dbl(base, &digits_per_bdigits_dbl);
    num_bdigits = roomof(num_digits, digits_per_bdigits_dbl)*2;

    z = str2big_gmp(positive_p, digits_start, digits_end, num_digits, num_bdigits, base);

    RB_GC_GUARD(arg);

    return bignorm(z);
}
#endif

#if HAVE_LONG_LONG

static VALUE
rb_ull2big(unsigned LONG_LONG n)
{
    long i;
    VALUE big = bignew(bdigit_roomof(SIZEOF_LONG_LONG), 1);
    BDIGIT *digits = BDIGITS(big);

#if SIZEOF_BDIGIT >= SIZEOF_LONG_LONG
    digits[0] = n;
#else
    for (i = 0; i < bdigit_roomof(SIZEOF_LONG_LONG); i++) {
        digits[i] = BIGLO(n);
        n = BIGDN(n);
    }
#endif

    i = bdigit_roomof(SIZEOF_LONG_LONG);
    while (i-- && !digits[i]) ;
    BIGNUM_SET_LEN(big, i+1);
    return big;
}

static VALUE
rb_ll2big(LONG_LONG n)
{
    long neg = 0;
    unsigned LONG_LONG u;
    VALUE big;

    if (n < 0) {
        u = 1 + (unsigned LONG_LONG)(-(n + 1)); /* u = -n avoiding overflow */
        neg = 1;
    }
    else {
        u = n;
    }
    big = rb_ull2big(u);
    if (neg) {
        BIGNUM_SET_NEGATIVE_SIGN(big);
    }
    return big;
}

VALUE
rb_ull2inum(unsigned LONG_LONG n)
{
    if (POSFIXABLE(n)) return LONG2FIX((long)n);
    return rb_ull2big(n);
}

VALUE
rb_ll2inum(LONG_LONG n)
{
    if (FIXABLE(n)) return LONG2FIX((long)n);
    return rb_ll2big(n);
}

#endif  /* HAVE_LONG_LONG */

#ifdef HAVE_INT128_T
static VALUE
rb_uint128t2big(uint128_t n)
{
    long i;
    VALUE big = bignew(bdigit_roomof(SIZEOF_INT128_T), 1);
    BDIGIT *digits = BDIGITS(big);

    for (i = 0; i < bdigit_roomof(SIZEOF_INT128_T); i++) {
        digits[i] = BIGLO(RSHIFT(n ,BITSPERDIG*i));
    }

    i = bdigit_roomof(SIZEOF_INT128_T);
    while (i-- && !digits[i]) ;
    BIGNUM_SET_LEN(big, i+1);
    return big;
}

VALUE
rb_int128t2big(int128_t n)
{
    int neg = 0;
    uint128_t u;
    VALUE big;

    if (n < 0) {
        u = 1 + (uint128_t)(-(n + 1)); /* u = -n avoiding overflow */
        neg = 1;
    }
    else {
        u = n;
    }
    big = rb_uint128t2big(u);
    if (neg) {
        BIGNUM_SET_NEGATIVE_SIGN(big);
    }
    return big;
}
#endif

VALUE
rb_cstr2inum(const char *str, int base)
{
    return rb_cstr_to_inum(str, base, base==0);
}

VALUE
rb_str2inum(VALUE str, int base)
{
    return rb_str_to_inum(str, base, base==0);
}

static VALUE
big_shift3(VALUE x, int lshift_p, size_t shift_numdigits, int shift_numbits)
{
    BDIGIT *xds, *zds;
    long s1;
    int s2;
    VALUE z;
    long xn;

    if (lshift_p) {
        if (LONG_MAX < shift_numdigits) {
          too_big:
            rb_raise(rb_eRangeError, "shift width too big");
        }
        s1 = shift_numdigits;
        s2 = shift_numbits;
        if ((size_t)s1 != shift_numdigits) goto too_big;
        xn = BIGNUM_LEN(x);
        if (LONG_MAX/SIZEOF_BDIGIT <= xn+s1) goto too_big;
        z = bignew(xn+s1+1, BIGNUM_SIGN(x));
        zds = BDIGITS(z);
        BDIGITS_ZERO(zds, s1);
        xds = BDIGITS(x);
        zds[xn+s1] = bary_small_lshift(zds+s1, xds, xn, s2);
    }
    else {
        long zn;
        BDIGIT hibitsx;
        if (LONG_MAX < shift_numdigits || (size_t)BIGNUM_LEN(x) <= shift_numdigits) {
            if (BIGNUM_POSITIVE_P(x) ||
                bary_zero_p(BDIGITS(x), BIGNUM_LEN(x)))
                return INT2FIX(0);
            else
                return INT2FIX(-1);
        }
        s1 = shift_numdigits;
        s2 = shift_numbits;
        hibitsx = abs2twocomp(&x, &xn);
        xds = BDIGITS(x);
        if (xn <= s1) {
            return hibitsx ? INT2FIX(-1) : INT2FIX(0);
        }
        zn = xn - s1;
        z = bignew(zn, 0);
        zds = BDIGITS(z);
        bary_small_rshift(zds, xds+s1, zn, s2, hibitsx != 0 ? BDIGMAX : 0);
        twocomp2abs_bang(z, hibitsx != 0);
    }
    RB_GC_GUARD(x);
    return z;
}

static VALUE
big_shift2(VALUE x, int lshift_p, VALUE y)
{
    int sign;
    size_t lens[2];
    size_t shift_numdigits;
    int shift_numbits;

    RUBY_ASSERT(POW2_P(CHAR_BIT));
    RUBY_ASSERT(POW2_P(BITSPERDIG));

    if (BIGZEROP(x))
        return INT2FIX(0);
    sign = rb_integer_pack(y, lens, numberof(lens), sizeof(size_t), 0,
        INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
    if (sign < 0) {
        lshift_p = !lshift_p;
        sign = -sign;
    }
    if (lshift_p) {
        if (1 < sign || CHAR_BIT <= lens[1])
            rb_raise(rb_eRangeError, "shift width too big");
    }
    else {
        if (1 < sign || CHAR_BIT <= lens[1])
            return BIGNUM_POSITIVE_P(x) ? INT2FIX(0) : INT2FIX(-1);
    }
    shift_numbits = (int)(lens[0] & (BITSPERDIG-1));
    shift_numdigits = (lens[0] >> bit_length(BITSPERDIG-1)) |
      (lens[1] << (CHAR_BIT*SIZEOF_SIZE_T - bit_length(BITSPERDIG-1)));
    return big_shift3(x, lshift_p, shift_numdigits, shift_numbits);
}

static VALUE
big_lshift(VALUE x, unsigned long shift)
{
    long s1 = shift/BITSPERDIG;
    int s2 = (int)(shift%BITSPERDIG);
    return big_shift3(x, 1, s1, s2);
}

static VALUE
big_rshift(VALUE x, unsigned long shift)
{
    long s1 = shift/BITSPERDIG;
    int s2 = (int)(shift%BITSPERDIG);
    return big_shift3(x, 0, s1, s2);
}

#define MAX_BASE36_POWER_TABLE_ENTRIES (SIZEOF_SIZE_T * CHAR_BIT + 1)

static VALUE base36_power_cache[35][MAX_BASE36_POWER_TABLE_ENTRIES];
static size_t base36_numdigits_cache[35][MAX_BASE36_POWER_TABLE_ENTRIES];

static void
power_cache_init(void)
{
}

static inline VALUE
power_cache_get_power(int base, int power_level, size_t *numdigits_ret)
{
    /*
     * MAX_BASE36_POWER_TABLE_ENTRIES is big enough to that
     * base36_power_cache[base][MAX_BASE36_POWER_TABLE_ENTRIES-1] fills whole memory.
     * So MAX_BASE36_POWER_TABLE_ENTRIES <= power_level is not possible to calculate.
     *
     * number-of-bytes =
     * log256(base36_power_cache[base][MAX_BASE36_POWER_TABLE_ENTRIES-1]) =
     * log256(maxpow_in_bdigit_dbl(base)**(2**(MAX_BASE36_POWER_TABLE_ENTRIES-1))) =
     * log256(maxpow_in_bdigit_dbl(base)**(2**(SIZEOF_SIZE_T*CHAR_BIT))) =
     * (2**(SIZEOF_SIZE_T*CHAR_BIT))*log256(maxpow_in_bdigit_dbl(base)) =
     * (256**SIZEOF_SIZE_T)*log256(maxpow_in_bdigit_dbl(base)) >
     * (256**SIZEOF_SIZE_T)*(sizeof(BDIGIT_DBL)-1) >
     * 256**SIZEOF_SIZE_T
     */
    if (MAX_BASE36_POWER_TABLE_ENTRIES <= power_level)
        rb_bug("too big power number requested: maxpow_in_bdigit_dbl(%d)**(2**%d)", base, power_level);

    VALUE power = base36_power_cache[base - 2][power_level];
    if (!power) {
        size_t numdigits;
        if (power_level == 0) {
            int numdigits0;
            BDIGIT_DBL dd = maxpow_in_bdigit_dbl(base, &numdigits0);
            power = bignew(2, 1);
            bdigitdbl2bary(BDIGITS(power), 2, dd);
            numdigits = numdigits0;
        }
        else {
            power = bigtrunc(bigsq(power_cache_get_power(base, power_level - 1, &numdigits)));
            numdigits *= 2;
        }
        rb_obj_hide(power);
        base36_power_cache[base - 2][power_level] = power;
        base36_numdigits_cache[base - 2][power_level] = numdigits;
        rb_vm_register_global_object(power);
    }
    if (numdigits_ret)
        *numdigits_ret = base36_numdigits_cache[base - 2][power_level];
    return power;
}

struct big2str_struct {
    int negative;
    int base;
    BDIGIT_DBL hbase2;
    int hbase2_numdigits;
    VALUE result;
    char *ptr;
};

static void
big2str_alloc(struct big2str_struct *b2s, size_t len)
{
    if (LONG_MAX-1 < len)
        rb_raise(rb_eArgError, "too big number");
    b2s->result = rb_usascii_str_new(0, (long)(len + 1)); /* plus one for sign */
    b2s->ptr = RSTRING_PTR(b2s->result);
    if (b2s->negative)
        *b2s->ptr++ = '-';
}

static void
big2str_2bdigits(struct big2str_struct *b2s, BDIGIT *xds, size_t xn, size_t taillen)
{
    size_t j;
    BDIGIT_DBL num;
    char buf[SIZEOF_BDIGIT_DBL*CHAR_BIT], *p;
    int beginning = !b2s->ptr;
    size_t len = 0;

    RUBY_ASSERT(xn <= 2);
    num = bary2bdigitdbl(xds, xn);

    if (beginning) {
        if (num == 0)
            return;
        p = buf;
        j = sizeof(buf);
        do {
            BDIGIT_DBL idx = num % b2s->base;
            num /= b2s->base;
            p[--j] = ruby_digitmap[idx];
        } while (num);
        len = sizeof(buf) - j;
        big2str_alloc(b2s, len + taillen);
        MEMCPY(b2s->ptr, buf + j, char, len);
    }
    else {
        p = b2s->ptr;
        j = b2s->hbase2_numdigits;
        do {
            BDIGIT_DBL idx = num % b2s->base;
            num /= b2s->base;
            p[--j] = ruby_digitmap[idx];
        } while (j);
        len = b2s->hbase2_numdigits;
    }
    b2s->ptr += len;
}

static void
big2str_karatsuba(struct big2str_struct *b2s, BDIGIT *xds, size_t xn, size_t wn,
                  int power_level, size_t taillen)
{
    VALUE b;
    size_t half_numdigits, lower_numdigits;
    int lower_power_level;
    size_t bn;
    const BDIGIT *bds;
    size_t len;

    /*
     * Precondition:
     * abs(x) < maxpow**(2**power_level)
     * where
     *   maxpow = maxpow_in_bdigit_dbl(base, &numdigits)
     *
     * This function generates sequence of zeros, and then stringized abs(x) into b2s->ptr.
     *
     * b2s->ptr can be NULL.
     * It is allocated when the first character is generated via big2str_alloc.
     *
     * The prefix zeros should be generated if and only if b2s->ptr is not NULL.
     * When the zeros are generated, the zeros and abs(x) consists
     * numdigits*(2**power_level) characters at total.
     *
     * Note:
     * power_cache_get_power(base, power_level, &len) may not be cached yet. It should not be called.
     * power_cache_get_power(base, power_level-1, &len) should be cached already if 0 <= power_level-1.
     */

    if (xn == 0 || bary_zero_p(xds, xn)) {
        if (b2s->ptr) {
            /* When x is zero, power_cache_get_power(base, power_level) should be cached already. */
            power_cache_get_power(b2s->base, power_level, &len);
            memset(b2s->ptr, '0', len);
            b2s->ptr += len;
        }
        return;
    }

    if (power_level == 0) {
        big2str_2bdigits(b2s, xds, xn, taillen);
        return;
    }

    lower_power_level = power_level-1;
    b = power_cache_get_power(b2s->base, lower_power_level, &lower_numdigits);
    bn = BIGNUM_LEN(b);
    bds = BDIGITS(b);

    half_numdigits = lower_numdigits;

    while (0 < lower_power_level &&
            (xn < bn ||
             (xn == bn && bary_cmp(xds, xn, bds, bn) < 0))) {
        lower_power_level--;
        b = power_cache_get_power(b2s->base, lower_power_level, &lower_numdigits);
        bn = BIGNUM_LEN(b);
        bds = BDIGITS(b);
    }

    if (lower_power_level == 0 &&
            (xn < bn ||
             (xn == bn && bary_cmp(xds, xn, bds, bn) < 0))) {
        if (b2s->ptr) {
            len = half_numdigits * 2 - lower_numdigits;
            memset(b2s->ptr, '0', len);
            b2s->ptr += len;
        }
        big2str_2bdigits(b2s, xds, xn, taillen);
    }
    else {
        BDIGIT *qds, *rds;
        size_t qn, rn;
        BDIGIT *tds;
        int shift;

        if (lower_power_level != power_level-1 && b2s->ptr) {
            len = (half_numdigits - lower_numdigits) * 2;
            memset(b2s->ptr, '0', len);
            b2s->ptr += len;
        }

        shift = nlz(bds[bn-1]);

        qn = xn + BIGDIVREM_EXTRA_WORDS;

        if (shift == 0) {
            /* bigdivrem_restoring will not modify y.
             * So use bds directly.  */
            tds = (BDIGIT *)bds;
            xds[xn] = 0;
        }
        else {
            /* bigdivrem_restoring will modify y.
             * So use temporary buffer.  */
            tds = xds + qn;
            RUBY_ASSERT(qn + bn <= xn + wn);
            bary_small_lshift(tds, bds, bn, shift);
            xds[xn] = bary_small_lshift(xds, xds, xn, shift);
        }

        bigdivrem_restoring(xds, qn, tds, bn);

        rds = xds;
        rn = bn;

        qds = xds + bn;
        qn = qn - bn;

        if (shift) {
            bary_small_rshift(rds, rds, rn, shift, 0);
        }

        BARY_TRUNC(qds, qn);
        RUBY_ASSERT(qn <= bn);
        big2str_karatsuba(b2s, qds, qn, xn+wn - (rn+qn), lower_power_level, lower_numdigits+taillen);
        BARY_TRUNC(rds, rn);
        big2str_karatsuba(b2s, rds, rn, xn+wn - rn, lower_power_level, taillen);
    }
}

static VALUE
big2str_base_poweroftwo(VALUE x, int base)
{
    int word_numbits = ffs(base) - 1;
    size_t numwords;
    VALUE result;
    char *ptr;
    numwords = rb_absint_numwords(x, word_numbits, NULL);
    if (BIGNUM_NEGATIVE_P(x)) {
        if (LONG_MAX-1 < numwords)
            rb_raise(rb_eArgError, "too big number");
        result = rb_usascii_str_new(0, 1+numwords);
        ptr = RSTRING_PTR(result);
        *ptr++ = BIGNUM_POSITIVE_P(x) ? '+' : '-';
    }
    else {
        if (LONG_MAX < numwords)
            rb_raise(rb_eArgError, "too big number");
        result = rb_usascii_str_new(0, numwords);
        ptr = RSTRING_PTR(result);
    }
    rb_integer_pack(x, ptr, numwords, 1, CHAR_BIT-word_numbits,
                    INTEGER_PACK_BIG_ENDIAN);
    while (0 < numwords) {
        *ptr = ruby_digitmap[*(unsigned char *)ptr];
        ptr++;
        numwords--;
    }
    return result;
}

VALUE
rb_big2str_poweroftwo(VALUE x, int base)
{
    return big2str_base_poweroftwo(x, base);
}

static VALUE
big2str_generic(VALUE x, int base)
{
    BDIGIT *xds;
    size_t xn;
    struct big2str_struct b2s_data;
    int power_level;
    VALUE power;

    xds = BDIGITS(x);
    xn = BIGNUM_LEN(x);
    BARY_TRUNC(xds, xn);

    if (xn == 0) {
        return rb_usascii_str_new2("0");
    }

    if (!valid_radix_p(base))
        invalid_radix(base);

    if (xn >= LONG_MAX/BITSPERDIG) {
        rb_raise(rb_eRangeError, "bignum too big to convert into 'string'");
    }

    power_level = 0;
    power = power_cache_get_power(base, power_level, NULL);
    while (power_level < MAX_BASE36_POWER_TABLE_ENTRIES &&
           (size_t)BIGNUM_LEN(power) <= (xn+1)/2) {
        power_level++;
        power = power_cache_get_power(base, power_level, NULL);
    }
    RUBY_ASSERT(power_level != MAX_BASE36_POWER_TABLE_ENTRIES);

    if ((size_t)BIGNUM_LEN(power) <= xn) {
        /*
         * This increment guarantees x < power_cache_get_power(base, power_level)
         * without invoking it actually.
         * (power_cache_get_power(base, power_level) can be slow and not used
         * in big2str_karatsuba.)
         *
         * Although it is possible that x < power_cache_get_power(base, power_level-1),
         * it is no problem because big2str_karatsuba checks it and
         * doesn't affect the result when b2s_data.ptr is NULL.
         */
        power_level++;
    }

    b2s_data.negative = BIGNUM_NEGATIVE_P(x);
    b2s_data.base = base;
    b2s_data.hbase2 = maxpow_in_bdigit_dbl(base, &b2s_data.hbase2_numdigits);

    b2s_data.result = Qnil;
    b2s_data.ptr = NULL;

    if (power_level == 0) {
        big2str_2bdigits(&b2s_data, xds, xn, 0);
    }
    else {
        VALUE tmpw = 0;
        BDIGIT *wds;
        size_t wn;
        wn = power_level * BIGDIVREM_EXTRA_WORDS + BIGNUM_LEN(power);
        wds = ALLOCV_N(BDIGIT, tmpw, xn + wn);
        MEMCPY(wds, xds, BDIGIT, xn);
        big2str_karatsuba(&b2s_data, wds, xn, wn, power_level, 0);
        if (tmpw)
            ALLOCV_END(tmpw);
    }
    RB_GC_GUARD(x);

    *b2s_data.ptr = '\0';
    rb_str_resize(b2s_data.result, (long)(b2s_data.ptr - RSTRING_PTR(b2s_data.result)));

    RB_GC_GUARD(x);
    return b2s_data.result;
}

VALUE
rb_big2str_generic(VALUE x, int base)
{
    return big2str_generic(x, base);
}

#if USE_GMP
static VALUE
big2str_gmp(VALUE x, int base)
{
    mpz_t mx;
    size_t size;
    VALUE str;
    BDIGIT *xds = BDIGITS(x);
    size_t xn = BIGNUM_LEN(x);

    mpz_init(mx);
    bdigits_to_mpz(mx, xds, xn);

    size = mpz_sizeinbase(mx, base);

    if (BIGNUM_NEGATIVE_P(x)) {
        mpz_neg(mx, mx);
        str = rb_usascii_str_new(0, size+1);
    }
    else {
        str = rb_usascii_str_new(0, size);
    }
    mpz_get_str(RSTRING_PTR(str), base, mx);
    mpz_clear(mx);

    if (RSTRING_PTR(str)[RSTRING_LEN(str)-1] == '\0') {
        rb_str_set_len(str, RSTRING_LEN(str)-1);
    }

    RB_GC_GUARD(x);
    return str;
}

VALUE
rb_big2str_gmp(VALUE x, int base)
{
    return big2str_gmp(x, base);
}
#endif

static VALUE
rb_big2str1(VALUE x, int base)
{
    BDIGIT *xds;
    size_t xn;

    if (FIXNUM_P(x)) {
        return rb_fix2str(x, base);
    }

    bigtrunc(x);
    xds = BDIGITS(x);
    xn = BIGNUM_LEN(x);
    BARY_TRUNC(xds, xn);

    if (xn == 0) {
        return rb_usascii_str_new2("0");
    }

    if (!valid_radix_p(base))
        invalid_radix(base);

    if (xn >= LONG_MAX/BITSPERDIG) {
        rb_raise(rb_eRangeError, "bignum too big to convert into 'string'");
    }

    if (POW2_P(base)) {
        /* base == 2 || base == 4 || base == 8 || base == 16 || base == 32 */
        return big2str_base_poweroftwo(x, base);
    }

#if USE_GMP
    if (GMP_BIG2STR_DIGITS < xn) {
        return big2str_gmp(x, base);
    }
#endif

    return big2str_generic(x, base);
}

VALUE
rb_big2str(VALUE x, int base)
{
    return rb_big2str1(x, base);
}

static unsigned long
big2ulong(VALUE x, const char *type)
{
#if SIZEOF_LONG > SIZEOF_BDIGIT
    size_t i;
#endif
    size_t len = BIGNUM_LEN(x);
    unsigned long num;
    BDIGIT *ds;

    if (len == 0)
        return 0;
    if (BIGSIZE(x) > sizeof(long)) {
        rb_raise(rb_eRangeError, "bignum too big to convert into '%s'", type);
    }
    ds = BDIGITS(x);
#if SIZEOF_LONG <= SIZEOF_BDIGIT
    num = (unsigned long)ds[0];
#else
    num = 0;
    for (i = 0; i < len; i++) {
        num <<= BITSPERDIG;
        num += (unsigned long)ds[len - i - 1]; /* overflow is already checked */
    }
#endif
    return num;
}

unsigned long
rb_big2ulong(VALUE x)
{
    unsigned long num = big2ulong(x, "unsigned long");

    if (BIGNUM_POSITIVE_P(x)) {
        return num;
    }
    else {
        if (num <= 1+(unsigned long)(-(LONG_MIN+1)))
            return -(long)(num-1)-1;
    }
    rb_raise(rb_eRangeError, "bignum out of range of unsigned long");
}

long
rb_big2long(VALUE x)
{
    unsigned long num = big2ulong(x, "long");

    if (BIGNUM_POSITIVE_P(x)) {
        if (num <= LONG_MAX)
            return num;
    }
    else {
        if (num <= 1+(unsigned long)(-(LONG_MIN+1)))
            return -(long)(num-1)-1;
    }
    rb_raise(rb_eRangeError, "bignum too big to convert into 'long'");
}

#if HAVE_LONG_LONG

static unsigned LONG_LONG
big2ull(VALUE x, const char *type)
{
#if SIZEOF_LONG_LONG > SIZEOF_BDIGIT
    size_t i;
#endif
    size_t len = BIGNUM_LEN(x);
    unsigned LONG_LONG num;
    BDIGIT *ds = BDIGITS(x);

    if (len == 0)
        return 0;
    if (BIGSIZE(x) > SIZEOF_LONG_LONG)
        rb_raise(rb_eRangeError, "bignum too big to convert into '%s'", type);
#if SIZEOF_LONG_LONG <= SIZEOF_BDIGIT
    num = (unsigned LONG_LONG)ds[0];
#else
    num = 0;
    for (i = 0; i < len; i++) {
        num = BIGUP(num);
        num += ds[len - i - 1];
    }
#endif
    return num;
}

unsigned LONG_LONG
rb_big2ull(VALUE x)
{
    unsigned LONG_LONG num = big2ull(x, "unsigned long long");

    if (BIGNUM_POSITIVE_P(x)) {
        return num;
    }
    else {
        if (num <= 1+(unsigned LONG_LONG)(-(LLONG_MIN+1)))
            return -(LONG_LONG)(num-1)-1;
    }
    rb_raise(rb_eRangeError, "bignum out of range of unsigned long long");
}

LONG_LONG
rb_big2ll(VALUE x)
{
    unsigned LONG_LONG num = big2ull(x, "long long");

    if (BIGNUM_POSITIVE_P(x)) {
        if (num <= LLONG_MAX)
            return num;
    }
    else {
        if (num <= 1+(unsigned LONG_LONG)(-(LLONG_MIN+1)))
            return -(LONG_LONG)(num-1)-1;
    }
    rb_raise(rb_eRangeError, "bignum too big to convert into 'long long'");
}

#endif  /* HAVE_LONG_LONG */

static VALUE
dbl2big(double d)
{
    long i = 0;
    BDIGIT c;
    BDIGIT *digits;
    VALUE z;
    double u = (d < 0)?-d:d;

    if (isinf(d)) {
        rb_raise(rb_eFloatDomainError, d < 0 ? "-Infinity" : "Infinity");
    }
    if (isnan(d)) {
        rb_raise(rb_eFloatDomainError, "NaN");
    }

    while (1.0 <= u) {
        u /= (double)(BIGRAD);
        i++;
    }
    z = bignew(i, d>=0);
    digits = BDIGITS(z);
    while (i--) {
        u *= BIGRAD;
        c = (BDIGIT)u;
        u -= c;
        digits[i] = c;
    }

    return z;
}

VALUE
rb_dbl2big(double d)
{
    return bignorm(dbl2big(d));
}

static double
big2dbl(VALUE x)
{
    double d = 0.0;
    long i = (bigtrunc(x), BIGNUM_LEN(x)), lo = 0, bits;
    BDIGIT *ds = BDIGITS(x), dl;

    if (i) {
        bits = i * BITSPERDIG - nlz(ds[i-1]);
        if (bits > DBL_MANT_DIG+DBL_MAX_EXP) {
            d = HUGE_VAL;
        }
        else {
            if (bits > DBL_MANT_DIG+1)
                lo = (bits -= DBL_MANT_DIG+1) / BITSPERDIG;
            else
                bits = 0;
            while (--i > lo) {
                d = ds[i] + BIGRAD*d;
            }
            dl = ds[i];
            if (bits && (dl & ((BDIGIT)1 << (bits %= BITSPERDIG)))) {
                int carry = (dl & ~(BDIGMAX << bits)) != 0;
                if (!carry) {
                    while (i-- > 0) {
                        carry = ds[i] != 0;
                        if (carry) break;
                    }
                }
                if (carry) {
                    BDIGIT mask = BDIGMAX;
                    BDIGIT bit = 1;
                    mask <<= bits;
                    bit <<= bits;
                    dl &= mask;
                    dl += bit;
                    dl = BIGLO(dl);
                    if (!dl) d += 1;
                }
            }
            d = dl + BIGRAD*d;
            if (lo) {
                if (lo > INT_MAX / BITSPERDIG)
                    d = HUGE_VAL;
                else if (lo < INT_MIN / BITSPERDIG)
                    d = 0.0;
                else
                    d = ldexp(d, (int)(lo * BITSPERDIG));
            }
        }
    }
    if (BIGNUM_NEGATIVE_P(x)) d = -d;
    return d;
}

double
rb_big2dbl(VALUE x)
{
    double d = big2dbl(x);

    if (isinf(d)) {
        rb_warning("Integer out of Float range");
        if (d < 0.0)
            d = -HUGE_VAL;
        else
            d = HUGE_VAL;
    }
    return d;
}

VALUE
rb_integer_float_cmp(VALUE x, VALUE y)
{
    double yd = RFLOAT_VALUE(y);
    double yi, yf;
    VALUE rel;

    if (isnan(yd))
        return Qnil;
    if (isinf(yd)) {
        if (yd > 0.0) return INT2FIX(-1);
        else return INT2FIX(1);
    }
    yf = modf(yd, &yi);
    if (FIXNUM_P(x)) {
#if SIZEOF_LONG * CHAR_BIT < DBL_MANT_DIG /* assume FLT_RADIX == 2 */
        double xd = (double)FIX2LONG(x);
        if (xd < yd)
            return INT2FIX(-1);
        if (xd > yd)
            return INT2FIX(1);
        return INT2FIX(0);
#else
        long xn, yn;
        if (yi < FIXNUM_MIN)
            return INT2FIX(1);
        if (FIXNUM_MAX+1 <= yi)
            return INT2FIX(-1);
        xn = FIX2LONG(x);
        yn = (long)yi;
        if (xn < yn)
            return INT2FIX(-1);
        if (xn > yn)
            return INT2FIX(1);
        if (yf < 0.0)
            return INT2FIX(1);
        if (0.0 < yf)
            return INT2FIX(-1);
        return INT2FIX(0);
#endif
    }
    y = rb_dbl2big(yi);
    rel = rb_big_cmp(x, y);
    if (yf == 0.0 || rel != INT2FIX(0))
        return rel;
    if (yf < 0.0)
        return INT2FIX(1);
    return INT2FIX(-1);
}

#if SIZEOF_LONG * CHAR_BIT >= DBL_MANT_DIG /* assume FLT_RADIX == 2 */
COMPILER_WARNING_PUSH
#if __has_warning("-Wimplicit-int-float-conversion")
COMPILER_WARNING_IGNORED(-Wimplicit-int-float-conversion)
#endif
static const double LONG_MAX_as_double = LONG_MAX;
COMPILER_WARNING_POP
#endif

VALUE
rb_integer_float_eq(VALUE x, VALUE y)
{
    double yd = RFLOAT_VALUE(y);
    double yi, yf;

    if (!isfinite(yd))
        return Qfalse;
    yf = modf(yd, &yi);
    if (yf != 0)
        return Qfalse;
    if (FIXNUM_P(x)) {
#if SIZEOF_LONG * CHAR_BIT < DBL_MANT_DIG /* assume FLT_RADIX == 2 */
        double xd = (double)FIX2LONG(x);
        return RBOOL(xd == yd);
#else
        long xn, yn;
        if (yi < LONG_MIN || LONG_MAX_as_double <= yi)
            return Qfalse;
        xn = FIX2LONG(x);
        yn = (long)yi;
        return RBOOL(xn == yn);
#endif
    }
    y = rb_dbl2big(yi);
    return rb_big_eq(x, y);
}


VALUE
rb_big_cmp(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        x = bigfixize(x);
        if (FIXNUM_P(x)) {
            /* SIGNED_VALUE and Fixnum have same sign-bits, same
             * order */
            SIGNED_VALUE sx = (SIGNED_VALUE)x, sy = (SIGNED_VALUE)y;
            if (sx < sy) return INT2FIX(-1);
            return INT2FIX(sx > sy);
        }
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        if (BIGNUM_SIGN(x) == BIGNUM_SIGN(y)) {
            int cmp = bary_cmp(BDIGITS(x), BIGNUM_LEN(x), BDIGITS(y), BIGNUM_LEN(y));
            return INT2FIX(BIGNUM_SIGN(x) ? cmp : -cmp);
        }
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return rb_integer_float_cmp(x, y);
    }
    else {
        return rb_num_coerce_cmp(x, y, idCmp);
    }
    return INT2FIX(BIGNUM_SIGN(x) ? 1 : -1);
}

enum big_op_t {
    big_op_gt,
    big_op_ge,
    big_op_lt,
    big_op_le
};

static VALUE
big_op(VALUE x, VALUE y, enum big_op_t op)
{
    VALUE rel;
    int n;

    if (RB_INTEGER_TYPE_P(y)) {
        rel = rb_big_cmp(x, y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        rel = rb_integer_float_cmp(x, y);
    }
    else {
        ID id = 0;
        switch (op) {
          case big_op_gt: id = '>'; break;
          case big_op_ge: id = idGE; break;
          case big_op_lt: id = '<'; break;
          case big_op_le: id = idLE; break;
        }
        return rb_num_coerce_relop(x, y, id);
    }

    if (NIL_P(rel)) return Qfalse;
    n = FIX2INT(rel);

    switch (op) {
      case big_op_gt: return RBOOL(n >  0);
      case big_op_ge: return RBOOL(n >= 0);
      case big_op_lt: return RBOOL(n <  0);
      case big_op_le: return RBOOL(n <= 0);
    }
    return Qundef;
}

VALUE
rb_big_gt(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_gt);
}

VALUE
rb_big_ge(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_ge);
}

VALUE
rb_big_lt(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_lt);
}

VALUE
rb_big_le(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_le);
}

/*
 *  call-seq:
 *     big == obj  -> true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> has the same value
 *  as <i>big</i>. Contrast this with Integer#eql?, which requires
 *  <i>obj</i> to be an Integer.
 *
 *     68719476736 == 68719476736.0   #=> true
 */

VALUE
rb_big_eq(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        return RBOOL(bignorm(x) == y);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return rb_integer_float_eq(x, y);
    }
    else {
        return rb_equal(y, x);
    }
    if (BIGNUM_SIGN(x) != BIGNUM_SIGN(y)) return Qfalse;
    if (BIGNUM_LEN(x) != BIGNUM_LEN(y)) return Qfalse;
    return RBOOL(MEMCMP(BDIGITS(x),BDIGITS(y),BDIGIT,BIGNUM_LEN(y)) == 0);
}

VALUE
rb_big_eql(VALUE x, VALUE y)
{
    if (!RB_BIGNUM_TYPE_P(y)) return Qfalse;
    if (BIGNUM_SIGN(x) != BIGNUM_SIGN(y)) return Qfalse;
    if (BIGNUM_LEN(x) != BIGNUM_LEN(y)) return Qfalse;
    return RBOOL(MEMCMP(BDIGITS(x),BDIGITS(y),BDIGIT,BIGNUM_LEN(y)) == 0);
}

VALUE
rb_big_uminus(VALUE x)
{
    VALUE z = rb_big_clone(x);

    BIGNUM_NEGATE(z);

    return bignorm(z);
}

VALUE
rb_big_comp(VALUE x)
{
    VALUE z = rb_big_clone(x);
    BDIGIT *ds = BDIGITS(z);
    long n = BIGNUM_LEN(z);

    if (!n) return INT2FIX(-1);

    if (BIGNUM_POSITIVE_P(z)) {
        if (bary_add_one(ds, n)) {
            big_extend_carry(z);
        }
        BIGNUM_SET_NEGATIVE_SIGN(z);
    }
    else {
        bary_neg(ds, n);
        if (bary_add_one(ds, n))
            return INT2FIX(-1);
        bary_neg(ds, n);
        BIGNUM_SET_POSITIVE_SIGN(z);
    }

    return bignorm(z);
}

static VALUE
bigsub(VALUE x, VALUE y)
{
    VALUE z;
    BDIGIT *xds, *yds, *zds;
    long xn, yn, zn;

    xn = BIGNUM_LEN(x);
    yn = BIGNUM_LEN(y);
    zn = xn < yn ? yn : xn;

    z = bignew(zn, 1);

    xds = BDIGITS(x);
    yds = BDIGITS(y);
    zds = BDIGITS(z);

    if (bary_sub(zds, zn, xds, xn, yds, yn)) {
        bary_2comp(zds, zn);
        BIGNUM_SET_NEGATIVE_SIGN(z);
    }

    return z;
}

static VALUE bigadd_int(VALUE x, long y);

static VALUE
bigsub_int(VALUE x, long y0)
{
    VALUE z;
    BDIGIT *xds, *zds;
    long xn, zn;
    BDIGIT_DBL_SIGNED num;
    long i, y;

    y = y0;
    xds = BDIGITS(x);
    xn = BIGNUM_LEN(x);

    if (xn == 0)
        return LONG2NUM(-y0);

    zn = xn;
#if SIZEOF_BDIGIT < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    z = bignew(zn, BIGNUM_SIGN(x));
    zds = BDIGITS(z);

#if SIZEOF_BDIGIT >= SIZEOF_LONG
    RUBY_ASSERT(xn == zn);
    num = (BDIGIT_DBL_SIGNED)xds[0] - y;
    if (xn == 1 && num < 0) {
        BIGNUM_NEGATE(z);
        zds[0] = (BDIGIT)-num;
        RB_GC_GUARD(x);
        return bignorm(z);
    }
    zds[0] = BIGLO(num);
    num = BIGDN(num);
    i = 1;
    if (i < xn)
        goto y_is_zero_x;
    goto finish;
#else
    num = 0;
    for (i=0; i < xn; i++) {
        if (y == 0) goto y_is_zero_x;
        num += (BDIGIT_DBL_SIGNED)xds[i] - BIGLO(y);
        zds[i] = BIGLO(num);
        num = BIGDN(num);
        y = BIGDN(y);
    }
    for (; i < zn; i++) {
        if (y == 0) goto y_is_zero_z;
        num -= BIGLO(y);
        zds[i] = BIGLO(num);
        num = BIGDN(num);
        y = BIGDN(y);
    }
    goto finish;
#endif

    for (; i < xn; i++) {
      y_is_zero_x:
        if (num == 0) goto num_is_zero_x;
        num += xds[i];
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
#if SIZEOF_BDIGIT < SIZEOF_LONG
    for (; i < zn; i++) {
      y_is_zero_z:
        if (num == 0) goto num_is_zero_z;
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
#endif
    goto finish;

    for (; i < xn; i++) {
      num_is_zero_x:
        zds[i] = xds[i];
    }
#if SIZEOF_BDIGIT < SIZEOF_LONG
    for (; i < zn; i++) {
      num_is_zero_z:
        zds[i] = 0;
    }
#endif
    goto finish;

  finish:
    RUBY_ASSERT(num == 0 || num == -1);
    if (num < 0) {
        get2comp(z);
        BIGNUM_NEGATE(z);
    }
    RB_GC_GUARD(x);
    return bignorm(z);
}

static VALUE
bigadd_int(VALUE x, long y)
{
    VALUE z;
    BDIGIT *xds, *zds;
    long xn, zn;
    BDIGIT_DBL num;
    long i;

    xds = BDIGITS(x);
    xn = BIGNUM_LEN(x);

    if (xn == 0)
        return LONG2NUM(y);

    zn = xn;
#if SIZEOF_BDIGIT < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    zn++;

    z = bignew(zn, BIGNUM_SIGN(x));
    zds = BDIGITS(z);

#if SIZEOF_BDIGIT >= SIZEOF_LONG
    num = (BDIGIT_DBL)xds[0] + y;
    zds[0] = BIGLO(num);
    num = BIGDN(num);
    i = 1;
    if (i < xn)
        goto y_is_zero_x;
    goto y_is_zero_z;
#else
    num = 0;
    for (i=0; i < xn; i++) {
        if (y == 0) goto y_is_zero_x;
        num += (BDIGIT_DBL)xds[i] + BIGLO(y);
        zds[i] = BIGLO(num);
        num = BIGDN(num);
        y = BIGDN(y);
    }
    for (; i < zn; i++) {
        if (y == 0) goto y_is_zero_z;
        num += BIGLO(y);
        zds[i] = BIGLO(num);
        num = BIGDN(num);
        y = BIGDN(y);
    }
    goto finish;

#endif

    for (;i < xn; i++) {
      y_is_zero_x:
        if (num == 0) goto num_is_zero_x;
        num += (BDIGIT_DBL)xds[i];
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
    for (; i < zn; i++) {
      y_is_zero_z:
        if (num == 0) goto num_is_zero_z;
        zds[i] = BIGLO(num);
        num = BIGDN(num);
    }
    goto finish;

    for (;i < xn; i++) {
      num_is_zero_x:
        zds[i] = xds[i];
    }
    for (; i < zn; i++) {
      num_is_zero_z:
        zds[i] = 0;
    }
    goto finish;

  finish:
    RB_GC_GUARD(x);
    return bignorm(z);
}

static VALUE
bigadd(VALUE x, VALUE y, int sign)
{
    VALUE z;
    size_t len;

    sign = (sign == BIGNUM_SIGN(y));
    if (BIGNUM_SIGN(x) != sign) {
        if (sign) return bigsub(y, x);
        return bigsub(x, y);
    }

    if (BIGNUM_LEN(x) > BIGNUM_LEN(y)) {
        len = BIGNUM_LEN(x) + 1;
    }
    else {
        len = BIGNUM_LEN(y) + 1;
    }
    z = bignew(len, sign);

    bary_add(BDIGITS(z), BIGNUM_LEN(z),
             BDIGITS(x), BIGNUM_LEN(x),
             BDIGITS(y), BIGNUM_LEN(y));

    return z;
}

VALUE
rb_big_plus(VALUE x, VALUE y)
{
    long n;

    if (FIXNUM_P(y)) {
        n = FIX2LONG(y);
        if ((n > 0) != BIGNUM_SIGN(x)) {
            if (n < 0) {
                n = -n;
            }
            return bigsub_int(x, n);
        }
        if (n < 0) {
            n = -n;
        }
        return bigadd_int(x, n);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return bignorm(bigadd(x, y, 1));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM(rb_big2dbl(x) + RFLOAT_VALUE(y));
    }
    else {
        return rb_num_coerce_bin(x, y, '+');
    }
}

VALUE
rb_big_minus(VALUE x, VALUE y)
{
    long n;

    if (FIXNUM_P(y)) {
        n = FIX2LONG(y);
        if ((n > 0) != BIGNUM_SIGN(x)) {
            if (n < 0) {
                n = -n;
            }
            return bigadd_int(x, n);
        }
        if (n < 0) {
            n = -n;
        }
        return bigsub_int(x, n);
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return bignorm(bigadd(x, y, 0));
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM(rb_big2dbl(x) - RFLOAT_VALUE(y));
    }
    else {
        return rb_num_coerce_bin(x, y, '-');
    }
}

static VALUE
bigsq(VALUE x)
{
    long xn, zn;
    VALUE z;
    BDIGIT *xds, *zds;

    xn = BIGNUM_LEN(x);
    zn = 2 * xn;

    z = bignew(zn, 1);

    xds = BDIGITS(x);
    zds = BDIGITS(z);

    if (xn < NAIVE_MUL_DIGITS)
        bary_sq_fast(zds, zn, xds, xn);
    else
        bary_mul(zds, zn, xds, xn, xds, xn);

    RB_GC_GUARD(x);
    return z;
}

static VALUE
bigmul0(VALUE x, VALUE y)
{
    long xn, yn, zn;
    VALUE z;
    BDIGIT *xds, *yds, *zds;

    if (x == y)
        return bigsq(x);

    xn = BIGNUM_LEN(x);
    yn = BIGNUM_LEN(y);
    zn = xn + yn;

    z = bignew(zn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));

    xds = BDIGITS(x);
    yds = BDIGITS(y);
    zds = BDIGITS(z);

    bary_mul(zds, zn, xds, xn, yds, yn);

    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

VALUE
rb_big_mul(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
        y = rb_int2big(FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        return DBL2NUM(rb_big2dbl(x) * RFLOAT_VALUE(y));
    }
    else {
        return rb_num_coerce_bin(x, y, '*');
    }

    return bignorm(bigmul0(x, y));
}

static VALUE
bigdivrem(VALUE x, VALUE y, volatile VALUE *divp, volatile VALUE *modp)
{
    long xn = BIGNUM_LEN(x), yn = BIGNUM_LEN(y);
    VALUE z;
    BDIGIT *xds, *yds, *zds;
    BDIGIT dd;

    VALUE q = Qnil, r = Qnil;
    BDIGIT *qds, *rds;
    long qn, rn;

    yds = BDIGITS(y);
    BARY_TRUNC(yds, yn);
    if (yn == 0)
        rb_num_zerodiv();

    xds = BDIGITS(x);
    BARY_TRUNC(xds, xn);

    if (xn < yn || (xn == yn && xds[xn - 1] < yds[yn - 1])) {
        if (divp) *divp = rb_int2big(0);
        if (modp) *modp = x;
        return Qnil;
    }
    if (yn == 1) {
        dd = yds[0];
        z = bignew(xn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
        zds = BDIGITS(z);
        dd = bigdivrem_single(zds, xds, xn, dd);
        if (modp) {
            *modp = rb_uint2big((uintptr_t)dd);
            BIGNUM_SET_SIGN(*modp, BIGNUM_SIGN(x));
        }
        if (divp) *divp = z;
        return Qnil;
    }
    if (xn == 2 && yn == 2) {
        BDIGIT_DBL x0 = bary2bdigitdbl(xds, 2);
        BDIGIT_DBL y0 = bary2bdigitdbl(yds, 2);
        BDIGIT_DBL q0 = x0 / y0;
        BDIGIT_DBL r0 = x0 % y0;
        if (divp) {
            z = bignew(bdigit_roomof(sizeof(BDIGIT_DBL)), BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
            zds = BDIGITS(z);
            zds[0] = BIGLO(q0);
            zds[1] = BIGLO(BIGDN(q0));
            *divp = z;
        }
        if (modp) {
            z = bignew(bdigit_roomof(sizeof(BDIGIT_DBL)), BIGNUM_SIGN(x));
            zds = BDIGITS(z);
            zds[0] = BIGLO(r0);
            zds[1] = BIGLO(BIGDN(r0));
            *modp = z;
        }
        return Qnil;
    }

    if (divp) {
        qn = xn + BIGDIVREM_EXTRA_WORDS;
        q = bignew(qn, BIGNUM_SIGN(x)==BIGNUM_SIGN(y));
        qds = BDIGITS(q);
    }
    else {
        qn = 0;
        qds = NULL;
    }

    if (modp) {
        rn = yn;
        r = bignew(rn, BIGNUM_SIGN(x));
        rds = BDIGITS(r);
    }
    else {
        rn = 0;
        rds = NULL;
    }

    bary_divmod_branch(qds, qn, rds, rn, xds, xn, yds, yn);

    if (divp) {
        bigtrunc(q);
        *divp = q;
    }
    if (modp) {
        bigtrunc(r);
        *modp = r;
    }

    return Qnil;
}

static void
bigdivmod(VALUE x, VALUE y, volatile VALUE *divp, volatile VALUE *modp)
{
    VALUE mod;

    bigdivrem(x, y, divp, &mod);
    if (BIGNUM_SIGN(x) != BIGNUM_SIGN(y) && !BIGZEROP(mod)) {
        if (divp) *divp = bigadd(*divp, rb_int2big(1), 0);
        if (modp) *modp = bigadd(mod, y, 1);
    }
    else if (modp) {
        *modp = mod;
    }
}


static VALUE
rb_big_divide(VALUE x, VALUE y, ID op)
{
    VALUE z;

    if (FIXNUM_P(y)) {
        y = rb_int2big(FIX2LONG(y));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        if (op == '/') {
            double dx = rb_big2dbl(x);
            return rb_flo_div_flo(DBL2NUM(dx), y);
        }
        else {
            VALUE v;
            double dy = RFLOAT_VALUE(y);
            if (dy == 0.0) rb_num_zerodiv();
            v = rb_big_divide(x, y, '/');
            return rb_dbl2big(RFLOAT_VALUE(v));
        }
    }
    else {
        return rb_num_coerce_bin(x, y, op);
    }
    bigdivmod(x, y, &z, 0);

    return bignorm(z);
}

VALUE
rb_big_div(VALUE x, VALUE y)
{
    return rb_big_divide(x, y, '/');
}

VALUE
rb_big_idiv(VALUE x, VALUE y)
{
    return rb_big_divide(x, y, idDiv);
}

VALUE
rb_big_modulo(VALUE x, VALUE y)
{
    VALUE z;

    if (FIXNUM_P(y)) {
        y = rb_int2big(FIX2LONG(y));
    }
    else if (!RB_BIGNUM_TYPE_P(y)) {
        return rb_num_coerce_bin(x, y, '%');
    }
    bigdivmod(x, y, 0, &z);

    return bignorm(z);
}

VALUE
rb_big_remainder(VALUE x, VALUE y)
{
    VALUE z;

    if (FIXNUM_P(y)) {
        y = rb_int2big(FIX2LONG(y));
    }
    else if (!RB_BIGNUM_TYPE_P(y)) {
        return rb_num_coerce_bin(x, y, rb_intern("remainder"));
    }
    bigdivrem(x, y, 0, &z);

    return bignorm(z);
}

VALUE
rb_big_divmod(VALUE x, VALUE y)
{
    VALUE div, mod;

    if (FIXNUM_P(y)) {
        y = rb_int2big(FIX2LONG(y));
    }
    else if (!RB_BIGNUM_TYPE_P(y)) {
        return rb_num_coerce_bin(x, y, idDivmod);
    }
    bigdivmod(x, y, &div, &mod);

    return rb_assoc_new(bignorm(div), bignorm(mod));
}

static VALUE
big_shift(VALUE x, long n)
{
    if (n < 0)
        return big_lshift(x, 1+(unsigned long)(-(n+1)));
    else if (n > 0)
        return big_rshift(x, (unsigned long)n);
    return x;
}

enum {DBL_BIGDIG = ((DBL_MANT_DIG + BITSPERDIG) / BITSPERDIG)};

static double
big_fdiv(VALUE x, VALUE y, long ey)
{
    VALUE z;
    long l, ex;

    bigtrunc(x);
    l = BIGNUM_LEN(x);
    ex = l * BITSPERDIG - nlz(BDIGITS(x)[l-1]);
    ex -= 2 * DBL_BIGDIG * BITSPERDIG;
    if (ex > BITSPERDIG) ex -= BITSPERDIG;
    else if (ex > 0) ex = 0;
    if (ex) x = big_shift(x, ex);

    bigdivrem(x, y, &z, 0);
    l = ex - ey;
#if SIZEOF_LONG > SIZEOF_INT
    {
        /* Visual C++ can't be here */
        if (l > INT_MAX) return HUGE_VAL;
        if (l < INT_MIN) return 0.0;
    }
#endif
    return ldexp(big2dbl(z), (int)l);
}

static double
big_fdiv_int(VALUE x, VALUE y)
{
    long l, ey;
    bigtrunc(y);
    l = BIGNUM_LEN(y);
    ey = l * BITSPERDIG - nlz(BDIGITS(y)[l-1]);
    ey -= DBL_BIGDIG * BITSPERDIG;
    if (ey) y = big_shift(y, ey);
    return big_fdiv(x, y, ey);
}

static double
big_fdiv_float(VALUE x, VALUE y)
{
    int i;
    y = dbl2big(ldexp(frexp(RFLOAT_VALUE(y), &i), DBL_MANT_DIG));
    return big_fdiv(x, y, i - DBL_MANT_DIG);
}

double
rb_big_fdiv_double(VALUE x, VALUE y)
{
    double dx, dy;
    VALUE v;

    dx = big2dbl(x);
    if (FIXNUM_P(y)) {
        dy = (double)FIX2LONG(y);
        if (isinf(dx))
            return big_fdiv_int(x, rb_int2big(FIX2LONG(y)));
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        return big_fdiv_int(x, y);
    }
    else if (RB_FLOAT_TYPE_P(y)) {
        dy = RFLOAT_VALUE(y);
        if (isnan(dy))
            return dy;
        if (isinf(dx))
            return big_fdiv_float(x, y);
    }
    else {
        return NUM2DBL(rb_num_coerce_bin(x, y, idFdiv));
    }
    v = rb_flo_div_flo(DBL2NUM(dx), DBL2NUM(dy));
    return NUM2DBL(v);
}

VALUE
rb_big_fdiv(VALUE x, VALUE y)
{
    return DBL2NUM(rb_big_fdiv_double(x, y));
}

VALUE
rb_big_pow(VALUE x, VALUE y)
{
    double d;
    SIGNED_VALUE yy;

  again:
    if (y == INT2FIX(0)) return INT2FIX(1);
    if (y == INT2FIX(1)) return x;
    if (RB_FLOAT_TYPE_P(y)) {
        d = RFLOAT_VALUE(y);
        if ((BIGNUM_NEGATIVE_P(x) && !BIGZEROP(x))) {
            return rb_dbl_complex_new_polar_pi(pow(-rb_big2dbl(x), d), d);
        }
    }
    else if (RB_BIGNUM_TYPE_P(y)) {
        y = bignorm(y);
        if (FIXNUM_P(y))
            goto again;
        rb_warn("in a**b, b may be too big");
        d = rb_big2dbl(y);
    }
    else if (FIXNUM_P(y)) {
        yy = FIX2LONG(y);

        if (yy < 0) {
            x = rb_big_pow(x, LONG2NUM(-yy));
            if (RB_INTEGER_TYPE_P(x))
                return rb_rational_raw(INT2FIX(1), x);
            else
                return DBL2NUM(1.0 / NUM2DBL(x));
        }
        else {
            VALUE z = 0;
            SIGNED_VALUE mask;
            const size_t xbits = rb_absint_numwords(x, 1, NULL);
            const size_t BIGLEN_LIMIT = 32*1024*1024;

            if (xbits == (size_t)-1 ||
                (xbits > BIGLEN_LIMIT) ||
                (xbits * yy > BIGLEN_LIMIT)) {
                rb_warn("in a**b, b may be too big");
                d = (double)yy;
            }
            else {
                for (mask = FIXNUM_MAX + 1; mask; mask >>= 1) {
                    if (z) z = bigsq(z);
                    if (yy & mask) {
                        z = z ? bigtrunc(bigmul0(z, x)) : x;
                    }
                }
                return bignorm(z);
            }
        }
    }
    else {
        return rb_num_coerce_bin(x, y, idPow);
    }
    return DBL2NUM(pow(rb_big2dbl(x), d));
}

static VALUE
bigand_int(VALUE x, long xn, BDIGIT hibitsx, long y)
{
    VALUE z;
    BDIGIT *xds, *zds;
    long zn;
    long i;
    BDIGIT hibitsy;

    if (y == 0) return INT2FIX(0);
    if (xn == 0) return hibitsx ? LONG2NUM(y) : 0;
    hibitsy = 0 <= y ? 0 : BDIGMAX;
    xds = BDIGITS(x);
#if SIZEOF_BDIGIT >= SIZEOF_LONG
    if (!hibitsy) {
        y &= xds[0];
        return LONG2NUM(y);
    }
#endif

    zn = xn;
#if SIZEOF_BDIGIT < SIZEOF_LONG
    if (hibitsx && zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif

    z = bignew(zn, 0);
    zds = BDIGITS(z);

#if SIZEOF_BDIGIT >= SIZEOF_LONG
    i = 1;
    zds[0] = xds[0] & BIGLO(y);
#else
    for (i=0; i < xn; i++) {
        if (y == 0 || y == -1) break;
        zds[i] = xds[i] & BIGLO(y);
        y = BIGDN(y);
    }
    for (; i < zn; i++) {
        if (y == 0 || y == -1) break;
        zds[i] = hibitsx & BIGLO(y);
        y = BIGDN(y);
    }
#endif
    for (;i < xn; i++) {
        zds[i] = xds[i] & hibitsy;
    }
    for (;i < zn; i++) {
        zds[i] = hibitsx & hibitsy;
    }
    twocomp2abs_bang(z, hibitsx && hibitsy);
    RB_GC_GUARD(x);
    return bignorm(z);
}

VALUE
rb_big_and(VALUE x, VALUE y)
{
    VALUE z;
    BDIGIT *ds1, *ds2, *zds;
    long i, xn, yn, n1, n2;
    BDIGIT hibitsx, hibitsy;
    BDIGIT hibits1, hibits2;
    VALUE tmpv;
    BDIGIT tmph;
    long tmpn;

    if (!RB_INTEGER_TYPE_P(y)) {
        return rb_num_coerce_bit(x, y, '&');
    }

    hibitsx = abs2twocomp(&x, &xn);
    if (FIXNUM_P(y)) {
        return bigand_int(x, xn, hibitsx, FIX2LONG(y));
    }
    hibitsy = abs2twocomp(&y, &yn);
    if (xn > yn) {
        tmpv = x; x = y; y = tmpv;
        tmpn = xn; xn = yn; yn = tmpn;
        tmph = hibitsx; hibitsx = hibitsy; hibitsy = tmph;
    }
    n1 = xn;
    n2 = yn;
    ds1 = BDIGITS(x);
    ds2 = BDIGITS(y);
    hibits1 = hibitsx;
    hibits2 = hibitsy;

    if (!hibits1)
        n2 = n1;

    z = bignew(n2, 0);
    zds = BDIGITS(z);

    for (i=0; i<n1; i++) {
        zds[i] = ds1[i] & ds2[i];
    }
    for (; i<n2; i++) {
        zds[i] = hibits1 & ds2[i];
    }
    twocomp2abs_bang(z, hibits1 && hibits2);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return bignorm(z);
}

static VALUE
bigor_int(VALUE x, long xn, BDIGIT hibitsx, long y)
{
    VALUE z;
    BDIGIT *xds, *zds;
    long zn;
    long i;
    BDIGIT hibitsy;

    if (y == -1) return INT2FIX(-1);
    if (xn == 0) return hibitsx ? INT2FIX(-1) : LONG2FIX(y);
    hibitsy = 0 <= y ? 0 : BDIGMAX;
    xds = BDIGITS(x);

    zn = BIGNUM_LEN(x);
#if SIZEOF_BDIGIT < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    z = bignew(zn, 0);
    zds = BDIGITS(z);

#if SIZEOF_BDIGIT >= SIZEOF_LONG
    i = 1;
    zds[0] = xds[0] | BIGLO(y);
    if (i < zn)
        goto y_is_fixed_point;
    goto finish;
#else
    for (i=0; i < xn; i++) {
        if (y == 0 || y == -1) goto y_is_fixed_point;
        zds[i] = xds[i] | BIGLO(y);
        y = BIGDN(y);
    }
    if (hibitsx)
        goto fill_hibits;
    for (; i < zn; i++) {
        if (y == 0 || y == -1) goto y_is_fixed_point;
        zds[i] = BIGLO(y);
        y = BIGDN(y);
    }
  goto finish;
#endif

  y_is_fixed_point:
    if (hibitsy)
        goto fill_hibits;
    for (; i < xn; i++) {
        zds[i] = xds[i];
    }
    if (hibitsx)
        goto fill_hibits;
    for (; i < zn; i++) {
        zds[i] = 0;
    }
  goto finish;

  fill_hibits:
    for (; i < zn; i++) {
        zds[i] = BDIGMAX;
    }

  finish:
    twocomp2abs_bang(z, hibitsx || hibitsy);
    RB_GC_GUARD(x);
    return bignorm(z);
}

VALUE
rb_big_or(VALUE x, VALUE y)
{
    VALUE z;
    BDIGIT *ds1, *ds2, *zds;
    long i, xn, yn, n1, n2;
    BDIGIT hibitsx, hibitsy;
    BDIGIT hibits1, hibits2;
    VALUE tmpv;
    BDIGIT tmph;
    long tmpn;

    if (!RB_INTEGER_TYPE_P(y)) {
        return rb_num_coerce_bit(x, y, '|');
    }

    hibitsx = abs2twocomp(&x, &xn);
    if (FIXNUM_P(y)) {
        return bigor_int(x, xn, hibitsx, FIX2LONG(y));
    }
    hibitsy = abs2twocomp(&y, &yn);
    if (xn > yn) {
        tmpv = x; x = y; y = tmpv;
        tmpn = xn; xn = yn; yn = tmpn;
        tmph = hibitsx; hibitsx = hibitsy; hibitsy = tmph;
    }
    n1 = xn;
    n2 = yn;
    ds1 = BDIGITS(x);
    ds2 = BDIGITS(y);
    hibits1 = hibitsx;
    hibits2 = hibitsy;

    if (hibits1)
        n2 = n1;

    z = bignew(n2, 0);
    zds = BDIGITS(z);

    for (i=0; i<n1; i++) {
        zds[i] = ds1[i] | ds2[i];
    }
    for (; i<n2; i++) {
        zds[i] = hibits1 | ds2[i];
    }
    twocomp2abs_bang(z, hibits1 || hibits2);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return bignorm(z);
}

static VALUE
bigxor_int(VALUE x, long xn, BDIGIT hibitsx, long y)
{
    VALUE z;
    BDIGIT *xds, *zds;
    long zn;
    long i;
    BDIGIT hibitsy;

    hibitsy = 0 <= y ? 0 : BDIGMAX;
    xds = BDIGITS(x);
    zn = BIGNUM_LEN(x);
#if SIZEOF_BDIGIT < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    z = bignew(zn, 0);
    zds = BDIGITS(z);

#if SIZEOF_BDIGIT >= SIZEOF_LONG
    i = 1;
    zds[0] = xds[0] ^ BIGLO(y);
#else
    for (i = 0; i < xn; i++) {
        zds[i] = xds[i] ^ BIGLO(y);
        y = BIGDN(y);
    }
    for (; i < zn; i++) {
        zds[i] = hibitsx ^ BIGLO(y);
        y = BIGDN(y);
    }
#endif
    for (; i < xn; i++) {
        zds[i] = xds[i] ^ hibitsy;
    }
    for (; i < zn; i++) {
        zds[i] = hibitsx ^ hibitsy;
    }
    twocomp2abs_bang(z, (hibitsx ^ hibitsy) != 0);
    RB_GC_GUARD(x);
    return bignorm(z);
}

VALUE
rb_big_xor(VALUE x, VALUE y)
{
    VALUE z;
    BDIGIT *ds1, *ds2, *zds;
    long i, xn, yn, n1, n2;
    BDIGIT hibitsx, hibitsy;
    BDIGIT hibits1, hibits2;
    VALUE tmpv;
    BDIGIT tmph;
    long tmpn;

    if (!RB_INTEGER_TYPE_P(y)) {
        return rb_num_coerce_bit(x, y, '^');
    }

    hibitsx = abs2twocomp(&x, &xn);
    if (FIXNUM_P(y)) {
        return bigxor_int(x, xn, hibitsx, FIX2LONG(y));
    }
    hibitsy = abs2twocomp(&y, &yn);
    if (xn > yn) {
        tmpv = x; x = y; y = tmpv;
        tmpn = xn; xn = yn; yn = tmpn;
        tmph = hibitsx; hibitsx = hibitsy; hibitsy = tmph;
    }
    n1 = xn;
    n2 = yn;
    ds1 = BDIGITS(x);
    ds2 = BDIGITS(y);
    hibits1 = hibitsx;
    hibits2 = hibitsy;

    z = bignew(n2, 0);
    zds = BDIGITS(z);

    for (i=0; i<n1; i++) {
        zds[i] = ds1[i] ^ ds2[i];
    }
    for (; i<n2; i++) {
        zds[i] = hibitsx ^ ds2[i];
    }
    twocomp2abs_bang(z, (hibits1 ^ hibits2) != 0);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return bignorm(z);
}

VALUE
rb_big_lshift(VALUE x, VALUE y)
{
    int lshift_p;
    size_t shift_numdigits;
    int shift_numbits;

    for (;;) {
        if (FIXNUM_P(y)) {
            long l = FIX2LONG(y);
            unsigned long shift;
            if (0 <= l) {
                lshift_p = 1;
                shift = l;
            }
            else {
                lshift_p = 0;
                shift = 1+(unsigned long)(-(l+1));
            }
            shift_numbits = (int)(shift & (BITSPERDIG-1));
            shift_numdigits = shift >> bit_length(BITSPERDIG-1);
            return bignorm(big_shift3(x, lshift_p, shift_numdigits, shift_numbits));
        }
        else if (RB_BIGNUM_TYPE_P(y)) {
            return bignorm(big_shift2(x, 1, y));
        }
        y = rb_to_int(y);
    }
}

VALUE
rb_big_rshift(VALUE x, VALUE y)
{
    int lshift_p;
    size_t shift_numdigits;
    int shift_numbits;

    for (;;) {
        if (FIXNUM_P(y)) {
            long l = FIX2LONG(y);
            unsigned long shift;
            if (0 <= l) {
                lshift_p = 0;
                shift = l;
            }
            else {
                lshift_p = 1;
                shift = 1+(unsigned long)(-(l+1));
            }
            shift_numbits = (int)(shift & (BITSPERDIG-1));
            shift_numdigits = shift >> bit_length(BITSPERDIG-1);
            return bignorm(big_shift3(x, lshift_p, shift_numdigits, shift_numbits));
        }
        else if (RB_BIGNUM_TYPE_P(y)) {
            return bignorm(big_shift2(x, 0, y));
        }
        y = rb_to_int(y);
    }
}

VALUE
rb_big_aref(VALUE x, VALUE y)
{
    BDIGIT *xds;
    size_t shift;
    size_t i, s1, s2;
    long l;
    BDIGIT bit;

    if (RB_BIGNUM_TYPE_P(y)) {
        if (BIGNUM_NEGATIVE_P(y))
            return INT2FIX(0);
        bigtrunc(y);
        if (BIGSIZE(y) > sizeof(size_t)) {
            return BIGNUM_SIGN(x) ? INT2FIX(0) : INT2FIX(1);
        }
#if SIZEOF_SIZE_T <= SIZEOF_LONG
        shift = big2ulong(y, "long");
#else
        shift = big2ull(y, "long long");
#endif
    }
    else {
        l = NUM2LONG(y);
        if (l < 0) return INT2FIX(0);
        shift = (size_t)l;
    }
    s1 = shift/BITSPERDIG;
    s2 = shift%BITSPERDIG;
    bit = (BDIGIT)1 << s2;

    if (s1 >= BIGNUM_LEN(x))
        return BIGNUM_SIGN(x) ? INT2FIX(0) : INT2FIX(1);

    xds = BDIGITS(x);
    if (BIGNUM_POSITIVE_P(x))
        return (xds[s1] & bit) ? INT2FIX(1) : INT2FIX(0);
    if (xds[s1] & (bit-1))
        return (xds[s1] & bit) ? INT2FIX(0) : INT2FIX(1);
    for (i = 0; i < s1; i++)
        if (xds[i])
            return (xds[s1] & bit) ? INT2FIX(0) : INT2FIX(1);
    return (xds[s1] & bit) ? INT2FIX(1) : INT2FIX(0);
}

VALUE
rb_big_hash(VALUE x)
{
    st_index_t hash;

    hash = rb_memhash(BDIGITS(x), sizeof(BDIGIT)*BIGNUM_LEN(x)) ^ BIGNUM_SIGN(x);
    return ST2FIX(hash);
}

/*
 * call-seq:
 *   int.coerce(numeric)  ->  array
 *
 * Returns an array with both a +numeric+ and a +int+ represented as
 * Integer objects or Float objects.
 *
 * This is achieved by converting +numeric+ to an Integer or a Float.
 *
 * A TypeError is raised if the +numeric+ is not an Integer or a Float
 * type.
 *
 *     (0x3FFFFFFFFFFFFFFF+1).coerce(42)   #=> [42, 4611686018427387904]
 */

static VALUE
rb_int_coerce(VALUE x, VALUE y)
{
    if (RB_INTEGER_TYPE_P(y)) {
        return rb_assoc_new(y, x);
    }
    else {
        x = rb_Float(x);
        y = rb_Float(y);
        return rb_assoc_new(y, x);
    }
}

VALUE
rb_big_abs(VALUE x)
{
    if (BIGNUM_NEGATIVE_P(x)) {
        x = rb_big_clone(x);
        BIGNUM_SET_POSITIVE_SIGN(x);
    }
    return x;
}

int
rb_big_sign(VALUE x)
{
    return BIGNUM_SIGN(x);
}

size_t
rb_big_size(VALUE big)
{
    return BIGSIZE(big);
}

VALUE
rb_big_size_m(VALUE big)
{
    return SIZET2NUM(rb_big_size(big));
}

VALUE
rb_big_bit_length(VALUE big)
{
    int nlz_bits;
    size_t numbytes;

    static const BDIGIT char_bit[1] = { CHAR_BIT };
    BDIGIT numbytes_bary[bdigit_roomof(sizeof(size_t))];
    BDIGIT nlz_bary[1];
    BDIGIT result_bary[bdigit_roomof(sizeof(size_t)+1)];

    numbytes = rb_absint_size(big, &nlz_bits);

    if (numbytes == 0)
        return LONG2FIX(0);

    if (BIGNUM_NEGATIVE_P(big) && rb_absint_singlebit_p(big)) {
        if (nlz_bits != CHAR_BIT-1) {
            nlz_bits++;
        }
        else {
            nlz_bits = 0;
            numbytes--;
        }
    }

    if (numbytes <= SIZE_MAX / CHAR_BIT) {
        return SIZET2NUM(numbytes * CHAR_BIT - nlz_bits);
    }

    nlz_bary[0] = nlz_bits;

    bary_unpack(BARY_ARGS(numbytes_bary), &numbytes, 1, sizeof(numbytes), 0,
            INTEGER_PACK_NATIVE_BYTE_ORDER);
    BARY_SHORT_MUL(result_bary, numbytes_bary, char_bit);
    BARY_SUB(result_bary, result_bary, nlz_bary);

    return rb_integer_unpack(result_bary, numberof(result_bary), sizeof(BDIGIT), 0,
            INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER);
}

VALUE
rb_big_odd_p(VALUE num)
{
    return RBOOL(BIGNUM_LEN(num) != 0 && BDIGITS(num)[0] & 1);
}

VALUE
rb_big_even_p(VALUE num)
{
    if (BIGNUM_LEN(num) != 0 && BDIGITS(num)[0] & 1) {
        return Qfalse;
    }
    return Qtrue;
}

unsigned long rb_ulong_isqrt(unsigned long);
#if SIZEOF_BDIGIT*2 > SIZEOF_LONG
BDIGIT rb_bdigit_dbl_isqrt(BDIGIT_DBL);
# ifdef ULL_TO_DOUBLE
#   define BDIGIT_DBL_TO_DOUBLE(n) ULL_TO_DOUBLE(n)
# endif
#else
# define rb_bdigit_dbl_isqrt(x) (BDIGIT)rb_ulong_isqrt(x)
#endif
#ifndef BDIGIT_DBL_TO_DOUBLE
# define BDIGIT_DBL_TO_DOUBLE(n) (double)(n)
#endif

static BDIGIT *
estimate_initial_sqrt(VALUE *xp, const size_t xn, const BDIGIT *nds, size_t len)
{
    enum {dbl_per_bdig = roomof(DBL_MANT_DIG,BITSPERDIG)};
    const int zbits = nlz(nds[len-1]);
    VALUE x = *xp = bignew_1(0, xn, 1); /* division may release the GVL */
    BDIGIT *xds = BDIGITS(x);
    BDIGIT_DBL d = bary2bdigitdbl(nds+len-dbl_per_bdig, dbl_per_bdig);
    BDIGIT lowbits = 1;
    int rshift = (int)((BITSPERDIG*2-zbits+(len&BITSPERDIG&1) - DBL_MANT_DIG + 1) & ~1);
    double f;

    if (rshift > 0) {
        lowbits = (BDIGIT)d & ~(~(BDIGIT)1U << rshift);
        d >>= rshift;
    }
    else if (rshift < 0) {
        d <<= -rshift;
        d |= nds[len-dbl_per_bdig-1] >> (BITSPERDIG+rshift);
    }
    f = sqrt(BDIGIT_DBL_TO_DOUBLE(d));
    d = (BDIGIT_DBL)ceil(f);
    if (BDIGIT_DBL_TO_DOUBLE(d) == f) {
        if (lowbits || (lowbits = !bary_zero_p(nds, len-dbl_per_bdig)))
            ++d;
    }
    else {
        lowbits = 1;
    }
    rshift /= 2;
    rshift += (2-(len&1))*BITSPERDIG/2;
    if (rshift >= 0) {
        if (nlz((BDIGIT)d) + rshift >= BITSPERDIG) {
            /* (d << rshift) does cause overflow.
             * example: Integer.sqrt(0xffff_ffff_ffff_ffff ** 2)
             */
            d = ~(BDIGIT_DBL)0;
        }
        else {
            d <<= rshift;
        }
    }
    BDIGITS_ZERO(xds, xn-2);
    bdigitdbl2bary(&xds[xn-2], 2, d);

    if (!lowbits) return NULL; /* special case, exact result */
    return xds;
}

VALUE
rb_big_isqrt(VALUE n)
{
    BDIGIT *nds = BDIGITS(n);
    size_t len = BIGNUM_LEN(n);
    size_t xn = (len+1) / 2;
    VALUE x;
    BDIGIT *xds;

    if (len <= 2) {
        BDIGIT sq = rb_bdigit_dbl_isqrt(bary2bdigitdbl(nds, len));
#if SIZEOF_BDIGIT > SIZEOF_LONG
        return ULL2NUM(sq);
#else
        return ULONG2NUM(sq);
#endif
    }
    else if ((xds = estimate_initial_sqrt(&x, xn, nds, len)) != 0) {
        size_t tn = xn + BIGDIVREM_EXTRA_WORDS;
        VALUE t = bignew_1(0, tn, 1);
        BDIGIT *tds = BDIGITS(t);
        tn = BIGNUM_LEN(t);

        /* t = n/x */
        while (bary_divmod_branch(tds, tn, NULL, 0, nds, len, xds, xn),
               bary_cmp(tds, tn, xds, xn) < 0) {
            int carry;
            BARY_TRUNC(tds, tn);
            /* x = (x+t)/2 */
            carry = bary_add(xds, xn, xds, xn, tds, tn);
            bary_small_rshift(xds, xds, xn, 1, carry);
            tn = BIGNUM_LEN(t);
        }
    }
    RBASIC_SET_CLASS_RAW(x, rb_cInteger);
    return x;
}

#if USE_GMP
static void
bary_powm_gmp(BDIGIT *zds, size_t zn, const BDIGIT *xds, size_t xn, const BDIGIT *yds, size_t yn, const BDIGIT *mds, size_t mn)
{
    mpz_t z, x, y, m;
    size_t count;
    mpz_init(x);
    mpz_init(y);
    mpz_init(m);
    mpz_init(z);
    bdigits_to_mpz(x, xds, xn);
    bdigits_to_mpz(y, yds, yn);
    bdigits_to_mpz(m, mds, mn);
    mpz_powm(z, x, y, m);
    bdigits_from_mpz(z, zds, &count);
    BDIGITS_ZERO(zds+count, zn-count);
    mpz_clear(x);
    mpz_clear(y);
    mpz_clear(m);
    mpz_clear(z);
}
#endif

static VALUE
int_pow_tmp3(VALUE x, VALUE y, VALUE m, int nega_flg)
{
#if USE_GMP
    VALUE z;
    size_t xn, yn, mn, zn;

    if (FIXNUM_P(x)) {
       x = rb_int2big(FIX2LONG(x));
    }
    if (FIXNUM_P(y)) {
       y = rb_int2big(FIX2LONG(y));
    }
    RUBY_ASSERT(RB_BIGNUM_TYPE_P(m));
    xn = BIGNUM_LEN(x);
    yn = BIGNUM_LEN(y);
    mn = BIGNUM_LEN(m);
    zn = mn;
    z = bignew(zn, 1);
    bary_powm_gmp(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn, BDIGITS(m), mn);
    if (nega_flg & BIGNUM_POSITIVE_P(z)) {
        z = rb_big_minus(z, m);
    }
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    RB_GC_GUARD(m);
    return rb_big_norm(z);
#else
    VALUE tmp = LONG2FIX(1L);
    long yy;

    for (/*NOP*/; ! FIXNUM_P(y); y = rb_big_rshift(y, LONG2FIX(1L))) {
        if (RTEST(rb_int_odd_p(y))) {
            tmp = rb_int_mul(tmp, x);
            tmp = rb_int_modulo(tmp, m);
        }
        x = rb_int_mul(x, x);
        x = rb_int_modulo(x, m);
    }
    for (yy = FIX2LONG(y); yy; yy >>= 1L) {
        if (yy & 1L) {
            tmp = rb_int_mul(tmp, x);
            tmp = rb_int_modulo(tmp, m);
        }
        x = rb_int_mul(x, x);
        x = rb_int_modulo(x, m);
    }

    if (nega_flg && rb_int_positive_p(tmp)) {
        tmp = rb_int_minus(tmp, m);
    }
    return tmp;
#endif
}

/*
 * Integer#pow
 */

static VALUE
int_pow_tmp1(VALUE x, VALUE y, long mm, int nega_flg)
{
    long xx = FIX2LONG(x);
    long tmp = 1L;
    long yy;

    for (/*NOP*/; ! FIXNUM_P(y); y = rb_big_rshift(y, LONG2FIX(1L))) {
        if (RTEST(rb_int_odd_p(y))) {
            tmp = (tmp * xx) % mm;
        }
        xx = (xx * xx) % mm;
    }
    for (yy = FIX2LONG(y); yy; yy >>= 1L) {
        if (yy & 1L) {
            tmp = (tmp * xx) % mm;
        }
        xx = (xx * xx) % mm;
    }

    if (nega_flg && tmp) {
        tmp -= mm;
    }
    return LONG2FIX(tmp);
}

static VALUE
int_pow_tmp2(VALUE x, VALUE y, long mm, int nega_flg)
{
    long tmp = 1L;
    long yy;
#ifdef DLONG
    const DLONG m = mm;
    long tmp2 = tmp;
    long xx = FIX2LONG(x);
# define MUL_MODULO(a, b, c) (long)(((DLONG)(a) * (DLONG)(b)) % (c))
#else
    const VALUE m = LONG2FIX(mm);
    VALUE tmp2 = LONG2FIX(tmp);
    VALUE xx = x;
# define MUL_MODULO(a, b, c) rb_int_modulo(rb_fix_mul_fix((a), (b)), (c))
#endif

    for (/*NOP*/; ! FIXNUM_P(y); y = rb_big_rshift(y, LONG2FIX(1L))) {
        if (RTEST(rb_int_odd_p(y))) {
            tmp2 = MUL_MODULO(tmp2, xx, m);
        }
        xx = MUL_MODULO(xx, xx, m);
    }
    for (yy = FIX2LONG(y); yy; yy >>= 1L) {
        if (yy & 1L) {
            tmp2 = MUL_MODULO(tmp2, xx, m);
        }
        xx = MUL_MODULO(xx, xx, m);
    }

#ifdef DLONG
    tmp = tmp2;
#else
    tmp = FIX2LONG(tmp2);
#endif
    if (nega_flg && tmp) {
        tmp -= mm;
    }
    return LONG2FIX(tmp);
}

/*
 * Document-method: Integer#pow
 * call-seq:
 *    integer.pow(numeric)           ->  numeric
 *    integer.pow(integer, integer)  ->  integer
 *
 * Returns (modular) exponentiation as:
 *
 *   a.pow(b)     #=> same as a**b
 *   a.pow(b, m)  #=> same as (a**b) % m, but avoids huge temporary values
 */
VALUE
rb_int_powm(int const argc, VALUE * const argv, VALUE const num)
{
    rb_check_arity(argc, 1, 2);

    if (argc == 1) {
        return rb_int_pow(num, argv[0]);
    }
    else {
        VALUE const a = num;
        VALUE const b = argv[0];
        VALUE m = argv[1];
        int nega_flg = 0;
        if ( ! RB_INTEGER_TYPE_P(b)) {
            rb_raise(rb_eTypeError, "Integer#pow() 2nd argument not allowed unless a 1st argument is integer");
        }
        if (rb_int_negative_p(b)) {
            rb_raise(rb_eRangeError, "Integer#pow() 1st argument cannot be negative when 2nd argument specified");
        }
        if (!RB_INTEGER_TYPE_P(m)) {
            rb_raise(rb_eTypeError, "Integer#pow() 2nd argument not allowed unless all arguments are integers");
        }

        if (rb_int_negative_p(m)) {
            m = rb_int_uminus(m);
            nega_flg = 1;
        }

        if (FIXNUM_P(m)) {
            long const half_val = (long)HALF_LONG_MSB;
            long const mm = FIX2LONG(m);
            if (!mm) rb_num_zerodiv();
            if (mm == 1) return INT2FIX(0);
            if (mm <= half_val) {
                return int_pow_tmp1(rb_int_modulo(a, m), b, mm, nega_flg);
            }
            else {
                return int_pow_tmp2(rb_int_modulo(a, m), b, mm, nega_flg);
            }
        }
        else {
            if (rb_bigzero_p(m)) rb_num_zerodiv();
            if (bignorm(m) == INT2FIX(1)) return INT2FIX(0);
            return int_pow_tmp3(rb_int_modulo(a, m), b, m, nega_flg);
        }
    }
    UNREACHABLE_RETURN(Qnil);
}

/*
 *  Bignum objects hold integers outside the range of
 *  Fixnum. Bignum objects are created
 *  automatically when integer calculations would otherwise overflow a
 *  Fixnum. When a calculation involving
 *  Bignum objects returns a result that will fit in a
 *  Fixnum, the result is automatically converted.
 *
 *  For the purposes of the bitwise operations and <code>[]</code>, a
 *  Bignum is treated as if it were an infinite-length
 *  bitstring with 2's complement representation.
 *
 *  While Fixnum values are immediate, Bignum
 *  objects are not---assignment and parameter passing work with
 *  references to objects, not the objects themselves.
 *
 */

void
Init_Bignum(void)
{
    rb_define_method(rb_cInteger, "coerce", rb_int_coerce, 1);

#if USE_GMP
    /* The version of loaded GMP. */
    rb_define_const(rb_cInteger, "GMP_VERSION", rb_sprintf("GMP %s", gmp_version));
#endif

    power_cache_init();
}
