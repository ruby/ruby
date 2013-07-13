/**********************************************************************

  bignum.c -

  $Author$
  created at: Fri Jun 10 00:48:55 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "internal.h"

#ifdef HAVE_STRINGS_H
#include <strings.h>
#endif
#include <math.h>
#include <float.h>
#include <ctype.h>
#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif
#include <assert.h>

VALUE rb_cBignum;
const char ruby_digitmap[] = "0123456789abcdefghijklmnopqrstuvwxyz";

static VALUE big_three = Qnil;

#if defined __MINGW32__
#define USHORT _USHORT
#endif

#ifndef SIZEOF_BDIGIT_DBL
# if defined(HAVE_INT64_T) && defined(HAVE_INT128_T)
#  define SIZEOF_BDIGIT_DBL SIZEOF_INT128_T
# elif SIZEOF_INT*2 <= SIZEOF_LONG_LONG
#  define SIZEOF_BDIGIT_DBL SIZEOF_LONG_LONG
# else
#  define SIZEOF_BDIGIT_DBL SIZEOF_LONG
# endif
#endif

STATIC_ASSERT(sizeof_bdigit_dbl, sizeof(BDIGIT_DBL) == SIZEOF_BDIGIT_DBL);
STATIC_ASSERT(rbignum_embed_len_max, RBIGNUM_EMBED_LEN_MAX <= (RBIGNUM_EMBED_LEN_MASK >> RBIGNUM_EMBED_LEN_SHIFT));

#ifdef WORDS_BIGENDIAN
#   define HOST_BIGENDIAN_P 1
#else
#   define HOST_BIGENDIAN_P 0
#endif
#define ALIGNOF(type) ((int)offsetof(struct { char f1; type f2; }, f2))
/* (sizeof(d) * CHAR_BIT <= (n) ? 0 : (n)) is same as n but suppress a warning, C4293, by Visual Studio.  */
#define LSHIFTABLE(d, n) ((n) < sizeof(d) * CHAR_BIT)
#define LSHIFTX(d, n) (!LSHIFTABLE(d, n) ? 0 : ((d) << (!LSHIFTABLE(d, n) ? 0 : (n))))
#define CLEAR_LOWBITS(d, numbits) ((d) & LSHIFTX(~((d)*0), (numbits)))
#define FILL_LOWBITS(d, numbits) ((d) | (LSHIFTX(((d)*0+1), (numbits))-1))
#define POW2_P(x) (((x)&((x)-1))==0)

#define BDIGITS(x) (RBIGNUM_DIGITS(x))
#define BITSPERDIG (SIZEOF_BDIGITS*CHAR_BIT)
#define BIGRAD ((BDIGIT_DBL)1 << BITSPERDIG)
#define BIGRAD_HALF ((BDIGIT)(BIGRAD >> 1))
#define BDIGIT_MSB(d) (((d) & BIGRAD_HALF) != 0)
#define BIGUP(x) LSHIFTX(((x) + (BDIGIT_DBL)0), BITSPERDIG)
#define BIGDN(x) RSHIFT((x),BITSPERDIG)
#define BIGLO(x) ((BDIGIT)((x) & BDIGMAX))
#define BDIGMAX ((BDIGIT)(BIGRAD-1))
#define BDIGIT_DBL_MAX (~(BDIGIT_DBL)0)

#if SIZEOF_BDIGITS == 2
#   define swap_bdigit(x) swap16(x)
#elif SIZEOF_BDIGITS == 4
#   define swap_bdigit(x) swap32(x)
#elif SIZEOF_BDIGITS == 8
#   define swap_bdigit(x) swap64(x)
#endif

#define BIGZEROP(x) (RBIGNUM_LEN(x) == 0 || \
		     (BDIGITS(x)[0] == 0 && \
		      (RBIGNUM_LEN(x) == 1 || bigzero_p(x))))
#define BIGSIZE(x) (RBIGNUM_LEN(x) == 0 ? (size_t)0 : \
    BDIGITS(x)[RBIGNUM_LEN(x)-1] ? \
        (size_t)(RBIGNUM_LEN(x)*SIZEOF_BDIGITS - nlz(BDIGITS(x)[RBIGNUM_LEN(x)-1])/CHAR_BIT) : \
    rb_absint_size(x, NULL))

#define BIGDIVREM_EXTRA_WORDS 2
#define roomof(n, m) ((long)(((n)+(m)-1) / (m)))
#define bdigit_roomof(n) roomof(n, SIZEOF_BDIGITS)
#define BARY_ARGS(ary) ary, numberof(ary)

#define BARY_ADD(z, x, y) bary_add(BARY_ARGS(z), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_SUB(z, x, y) bary_sub(BARY_ARGS(z), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_MUL1(z, x, y) bary_mul1(BARY_ARGS(z), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_DIVMOD(q, r, x, y) bary_divmod(BARY_ARGS(q), BARY_ARGS(r), BARY_ARGS(x), BARY_ARGS(y))
#define BARY_ZERO_P(x) bary_zero_p(BARY_ARGS(x))

#define RBIGNUM_SET_NEGATIVE_SIGN(b) RBIGNUM_SET_SIGN(b, 0)
#define RBIGNUM_SET_POSITIVE_SIGN(b) RBIGNUM_SET_SIGN(b, 1)

#define bignew(len,sign) bignew_1(rb_cBignum,(len),(sign))

#define KARATSUBA_MUL_DIGITS 70
#define TOOM3_MUL_DIGITS 150

typedef void (mulfunc_t)(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl, BDIGIT *wds, size_t wl);

static mulfunc_t bary_mul_toom3_start;
static mulfunc_t bary_mul_karatsuba_start;
static void bary_divmod(BDIGIT *qds, size_t nq, BDIGIT *rds, size_t nr, BDIGIT *xds, size_t nx, BDIGIT *yds, size_t ny);

static VALUE bigmul0(VALUE x, VALUE y);
static VALUE bigmul1_toom3(VALUE x, VALUE y);
static VALUE bignew_1(VALUE klass, long len, int sign);
static inline VALUE bigtrunc(VALUE x);

static VALUE bigsqr(VALUE x);
static void bigdivmod(VALUE x, VALUE y, volatile VALUE *divp, volatile VALUE *modp);

static int
nlz16(uint16_t x)
{
    uint16_t y;
    int n = 16;
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
}

static int
nlz32(uint32_t x)
{
    uint32_t y;
    int n = 32;
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
}

#if defined(HAVE_UINT64_T)
static int
nlz64(uint64_t x)
{
    uint64_t y;
    int n = 64;
    y = x >> 32; if (y) {n -= 32; x = y;}
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
}
#endif

#if defined(HAVE_UINT128_T)
static int
nlz128(uint128_t x)
{
    uint128_t y;
    int n = 128;
    y = x >> 64; if (y) {n -= 64; x = y;}
    y = x >> 32; if (y) {n -= 32; x = y;}
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (int)(n - x);
}
#endif

#if SIZEOF_BDIGITS == 2
static int nlz(BDIGIT x) { return nlz16((uint16_t)x); }
#elif SIZEOF_BDIGITS == 4
static int nlz(BDIGIT x) { return nlz32((uint32_t)x); }
#elif SIZEOF_BDIGITS == 8
static int nlz(BDIGIT x) { return nlz64((uint64_t)x); }
#elif SIZEOF_BDIGITS == 16
static int nlz(BDIGIT x) { return nlz128((uint128_t)x); }
#endif

#if defined(HAVE_UINT128_T)
#   define bitsize(x) \
        (sizeof(x) <= 2 ? 16 - nlz16(x) : \
         sizeof(x) <= 4 ? 32 - nlz32(x) : \
         sizeof(x) <= 8 ? 64 - nlz64(x) : \
         128 - nlz128(x))
#elif defined(HAVE_UINT64_T)
#   define bitsize(x) \
        (sizeof(x) <= 2 ? 16 - nlz16(x) : \
         sizeof(x) <= 4 ? 32 - nlz32(x) : \
         64 - nlz64(x))
#else
#   define bitsize(x) \
        (sizeof(x) <= 2 ? 16 - nlz16(x) : \
         32 - nlz32(x))
#endif

#define U16(a) ((uint16_t)(a))
#define U32(a) ((uint32_t)(a))
#ifdef HAVE_UINT64_T
#define U64(a,b) (((uint64_t)(a) << 32) | (b))
#endif
#ifdef HAVE_UINT128_T
#define U128(a,b,c,d) (((uint128_t)U64(a,b) << 64) | U64(c,d))
#endif

/* The following scirpt, maxpow.rb, generates the tables follows.

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

#ifdef HAVE_UINT16_T
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
#endif
#ifdef HAVE_UINT32_T
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
#endif
#ifdef HAVE_UINT64_T
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
#endif
#ifdef HAVE_UINT128_T
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

    assert(2 <= base && base <= 36);

    {
#if   SIZEOF_BDIGIT_DBL == 0
#elif SIZEOF_BDIGIT_DBL == 2
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

static BDIGIT
maxpow_in_bdigit(int base, int *exp_ret)
{
    BDIGIT maxpow;
    int exponent;

    {
#if SIZEOF_BDIGITS == 0
#elif SIZEOF_BDIGITS == 2
        maxpow = maxpow16_num[base-2];
        exponent = maxpow16_exp[base-2];
#elif SIZEOF_BDIGITS == 4
        maxpow = maxpow32_num[base-2];
        exponent = maxpow32_exp[base-2];
#elif SIZEOF_BDIGITS == 8 && defined HAVE_UINT64_T
        maxpow = maxpow64_num[base-2];
        exponent = maxpow64_exp[base-2];
#elif SIZEOF_BDIGITS == 16 && defined HAVE_UINT128_T
        maxpow = maxpow128_num[base-2];
        exponent = maxpow128_exp[base-2];
#else
        maxpow = base;
        exponent = 1;
        while (maxpow <= BDIGMAX / base) {
            maxpow *= base;
            exponent++;
        }
#endif
    }

    *exp_ret = exponent;
    return maxpow;
}

static BDIGIT
bary_small_lshift(BDIGIT *zds, BDIGIT *xds, size_t n, int shift)
{
    size_t i;
    BDIGIT_DBL num = 0;
    assert(0 <= shift && shift < BITSPERDIG);

    for (i=0; i<n; i++) {
	num = num | (BDIGIT_DBL)*xds++ << shift;
	*zds++ = BIGLO(num);
	num = BIGDN(num);
    }
    return BIGLO(num);
}

static void
bary_small_rshift(BDIGIT *zds, BDIGIT *xds, size_t n, int shift, int sign_bit)
{
    BDIGIT_DBL num = 0;
    BDIGIT x;

    assert(0 <= shift && shift < BITSPERDIG);

    if (sign_bit) {
	num = (~(BDIGIT_DBL)0) << BITSPERDIG;
    }
    while (n--) {
	num = (num | xds[n]) >> shift;
        x = xds[n];
	zds[n] = BIGLO(num);
	num = BIGUP(x);
    }
}

static int
bary_zero_p(BDIGIT *xds, size_t nx)
{
    if (nx == 0)
        return 1;
    do {
	if (xds[--nx]) return 0;
    } while (nx);
    return 1;
}

static void
bary_neg(BDIGIT *ds, size_t n)
{
    while (n--)
        ds[n] = BIGLO(~ds[n]);
}

static int
bary_2comp(BDIGIT *ds, size_t n)
{
    size_t i;
    i = 0;
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

static int
bytes_2comp(unsigned char *buf, size_t len)
{
    size_t i;
    for (i = 0; i < len; i++)
        buf[i] = ~buf[i];
    for (i = 0; i < len; i++) {
        buf[i]++;
        if (buf[i] != 0)
            return 0;
    }
    return 1;
}

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
#if defined(HAVE_UINT16_T) && 2 <= SIZEOF_BDIGITS
                if (wordsize == 2 && (uintptr_t)words % ALIGNOF(uint16_t) == 0) {
                    uint16_t u = (uint16_t)(d = dp[0]);
                    if (need_swap) u = swap16(u);
                    *((uint16_t *)words) = u;
                    return ((1 < de - dp || CLEAR_LOWBITS(d, 16) != 0) ? 2 : 1) * sign;
                }
#endif
#if defined(HAVE_UINT32_T) && 4 <= SIZEOF_BDIGITS
                if (wordsize == 4 && (uintptr_t)words % ALIGNOF(uint32_t) == 0) {
                    uint32_t u = (uint32_t)(d = dp[0]);
                    if (need_swap) u = swap32(u);
                    *((uint32_t *)words) = u;
                    return ((1 < de - dp || CLEAR_LOWBITS(d, 32) != 0) ? 2 : 1) * sign;
                }
#endif
#if defined(HAVE_UINT64_T) && 8 <= SIZEOF_BDIGITS
                if (wordsize == 8 && (uintptr_t)words % ALIGNOF(uint64_t) == 0) {
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
#if defined(HAVE_UINT16_T) && 2 <= SIZEOF_BDIGITS
                if (wordsize == 2 && (uintptr_t)words % ALIGNOF(uint16_t) == 0) {
                    uint16_t u = (uint16_t)(d = -(BDIGIT_DBL_SIGNED)dp[0]);
                    if (need_swap) u = swap16(u);
                    *((uint16_t *)words) = u;
                    return (wordsize == SIZEOF_BDIGITS && de - dp == 2 && dp[1] == 1 && dp[0] == 0) ? -1 :
                        (1 < de - dp || FILL_LOWBITS(d, 16) != -1) ? -2 : -1;
                }
#endif
#if defined(HAVE_UINT32_T) && 4 <= SIZEOF_BDIGITS
                if (wordsize == 4 && (uintptr_t)words % ALIGNOF(uint32_t) == 0) {
                    uint32_t u = (uint32_t)(d = -(BDIGIT_DBL_SIGNED)dp[0]);
                    if (need_swap) u = swap32(u);
                    *((uint32_t *)words) = u;
                    return (wordsize == SIZEOF_BDIGITS && de - dp == 2 && dp[1] == 1 && dp[0] == 0) ? -1 :
                        (1 < de - dp || FILL_LOWBITS(d, 32) != -1) ? -2 : -1;
                }
#endif
#if defined(HAVE_UINT64_T) && 8 <= SIZEOF_BDIGITS
                if (wordsize == 8 && (uintptr_t)words % ALIGNOF(uint64_t) == 0) {
                    uint64_t u = (uint64_t)(d = -(BDIGIT_DBL_SIGNED)dp[0]);
                    if (need_swap) u = swap64(u);
                    *((uint64_t *)words) = u;
                    return (wordsize == SIZEOF_BDIGITS && de - dp == 2 && dp[1] == 1 && dp[0] == 0) ? -1 :
                        (1 < de - dp || FILL_LOWBITS(d, 64) != -1) ? -2 : -1;
                }
#endif
            }
        }
#if !defined(WORDS_BIGENDIAN)
        if (nails == 0 && SIZEOF_BDIGITS == sizeof(BDIGIT) &&
            (flags & INTEGER_PACK_WORDORDER_MASK) == INTEGER_PACK_LSWORD_FIRST &&
            (flags & INTEGER_PACK_BYTEORDER_MASK) != INTEGER_PACK_MSBYTE_FIRST) {
            size_t src_size = (de - dp) * SIZEOF_BDIGITS;
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
        if (nails == 0 && SIZEOF_BDIGITS == sizeof(BDIGIT) &&
            wordsize % SIZEOF_BDIGITS == 0 && (uintptr_t)words % ALIGNOF(BDIGIT) == 0) {
            size_t bdigits_per_word = wordsize / SIZEOF_BDIGITS;
            size_t src_num_bdigits = de - dp;
            size_t dst_num_bdigits = numwords * bdigits_per_word;
            int overflow = 0;
            int mswordfirst_p = (flags & INTEGER_PACK_MSWORD_FIRST) != 0;
            int msbytefirst_p = (flags & INTEGER_PACK_NATIVE_BYTE_ORDER) ? HOST_BIGENDIAN_P :
                (flags & INTEGER_PACK_MSBYTE_FIRST) != 0;
            if (src_num_bdigits <= dst_num_bdigits) {
                MEMCPY(words, dp, BDIGIT, src_num_bdigits);
                MEMZERO((BDIGIT*)words + src_num_bdigits, BDIGIT, dst_num_bdigits - src_num_bdigits);
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
            if (mswordfirst_p ?  !msbytefirst_p : msbytefirst_p) {
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
        unsigned char *buf;

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
    size_t num_bdigits = (num_bits + BITSPERDIG - 1) / BITSPERDIG;
    *nlp_bits_ret = (int)(num_bdigits * BITSPERDIG - num_bits);
    return num_bdigits;
}

static size_t
integer_unpack_num_bdigits_generic(size_t numwords, size_t wordsize, size_t nails, int *nlp_bits_ret)
{
    /* BITSPERDIG = SIZEOF_BDIGITS * CHAR_BIT */
    /* num_bits = (wordsize * CHAR_BIT - nails) * numwords */
    /* num_bdigits = (num_bits + BITSPERDIG - 1) / BITSPERDIG */

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
#ifdef DEBUG_INTEGER_PACK
        {
            int nlp_bits1;
            size_t num_bdigits1 = integer_unpack_num_bdigits_generic(numwords, wordsize, nails, &nlp_bits1);
            assert(num_bdigits == num_bdigits1);
            assert(*nlp_bits_ret == nlp_bits1);
        }
#endif
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
            ((size == SIZEOF_BDIGITS && u == 0) ? -2 : -1) :
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
#if defined(HAVE_UINT16_T) && 2 <= SIZEOF_BDIGITS
            if (wordsize == 2 && (uintptr_t)words % ALIGNOF(uint16_t) == 0) {
                BDIGIT u = *(uint16_t *)buf;
                return integer_unpack_single_bdigit(need_swap ? swap16(u) : u, sizeof(uint16_t), flags, dp);
            }
#endif
#if defined(HAVE_UINT32_T) && 4 <= SIZEOF_BDIGITS
            if (wordsize == 4 && (uintptr_t)words % ALIGNOF(uint32_t) == 0) {
                BDIGIT u = *(uint32_t *)buf;
                return integer_unpack_single_bdigit(need_swap ? swap32(u) : u, sizeof(uint32_t), flags, dp);
            }
#endif
#if defined(HAVE_UINT64_T) && 8 <= SIZEOF_BDIGITS
            if (wordsize == 8 && (uintptr_t)words % ALIGNOF(uint64_t) == 0) {
                BDIGIT u = *(uint64_t *)buf;
                return integer_unpack_single_bdigit(need_swap ? swap64(u) : u, sizeof(uint64_t), flags, dp);
            }
#endif
        }
#if !defined(WORDS_BIGENDIAN)
        if (nails == 0 && SIZEOF_BDIGITS == sizeof(BDIGIT) &&
            (flags & INTEGER_PACK_WORDORDER_MASK) == INTEGER_PACK_LSWORD_FIRST &&
            (flags & INTEGER_PACK_BYTEORDER_MASK) != INTEGER_PACK_MSBYTE_FIRST) {
            size_t src_size = numwords * wordsize;
            size_t dst_size = num_bdigits * SIZEOF_BDIGITS;
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
        if (nails == 0 && SIZEOF_BDIGITS == sizeof(BDIGIT) &&
            wordsize % SIZEOF_BDIGITS == 0) {
            size_t bdigits_per_word = wordsize / SIZEOF_BDIGITS;
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
        assert(dp <= de);
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

    assert(num_bdigits0 <= num_bdigits);

    sign = bary_unpack_internal(bdigits, num_bdigits0, words, numwords, wordsize, nails, flags, nlp_bits);

    if (num_bdigits0 < num_bdigits) {
        MEMZERO(bdigits + num_bdigits0, BDIGIT, num_bdigits - num_bdigits0);
        if (sign == -2) {
            bdigits[num_bdigits0] = 1;
        }
    }
}

static int
bary_subb(BDIGIT *zds, size_t zn, BDIGIT *xds, size_t xn, BDIGIT *yds, size_t yn, int borrow)
{
    BDIGIT_DBL_SIGNED num;
    size_t i;

    assert(yn <= xn);
    assert(xn <= zn);

    num = borrow ? -1 : 0;
    for (i = 0; i < yn; i++) {
	num += (BDIGIT_DBL_SIGNED)xds[i] - yds[i];
	zds[i] = BIGLO(num);
	num = BIGDN(num);
    }
    for (; i < xn; i++) {
        if (num == 0) goto num_is_zero;
	num += xds[i];
	zds[i] = BIGLO(num);
	num = BIGDN(num);
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
bary_sub(BDIGIT *zds, size_t zn, BDIGIT *xds, size_t xn, BDIGIT *yds, size_t yn)
{
    return bary_subb(zds, zn, xds, xn, yds, yn, 0);
}

static int
bary_sub_one(BDIGIT *zds, size_t zn)
{
    return bary_subb(zds, zn, zds, zn, NULL, 0, 1);
}

static int
bary_addc(BDIGIT *zds, size_t zn, BDIGIT *xds, size_t xn, BDIGIT *yds, size_t yn, int carry)
{
    BDIGIT_DBL num;
    size_t i;

    assert(xn <= zn);
    assert(yn <= zn);

    if (xn > yn) {
	BDIGIT *tds;
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
bary_add(BDIGIT *zds, size_t zn, BDIGIT *xds, size_t xn, BDIGIT *yds, size_t yn)
{
    return bary_addc(zds, zn, xds, xn, yds, yn, 0);
}

static int
bary_add_one(BDIGIT *ds, size_t n)
{
    size_t i;
    for (i = 0; i < n; i++) {
	ds[i] = BIGLO(ds[i]+1);
        if (ds[i] != 0)
            return 0;
    }
    return 1;
}

static void
bary_mul_single(BDIGIT *zds, size_t zl, BDIGIT x, BDIGIT y)
{
    BDIGIT_DBL n;

    assert(2 <= zl);

    n = (BDIGIT_DBL)x * y;
    zds[0] = BIGLO(n);
    zds[1] = (BDIGIT)BIGDN(n);

    MEMZERO(zds + 2, BDIGIT, zl - 2);
}

static int
bary_muladd_1xN(BDIGIT *zds, size_t zl, BDIGIT x, BDIGIT *yds, size_t yl)
{
    BDIGIT_DBL n;
    BDIGIT_DBL dd;
    size_t j;

    assert(zl > yl);

    if (x == 0)
        return 0;
    dd = x;
    n = 0;
    for (j = 0; j < yl; j++) {
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
    for (; j < zl; j++) {
        if (n == 0)
            break;
        n += zds[j];
        zds[j] = BIGLO(n);
        n = BIGDN(n);
    }
    return n != 0;
}

static void
bary_mul_normal(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl)
{
    size_t i;

    assert(xl + yl <= zl);

    MEMZERO(zds, BDIGIT, zl);
    for (i = 0; i < xl; i++) {
        bary_muladd_1xN(zds+i, zl-i, xds[i], yds, yl);
    }
}

VALUE
rb_big_mul_normal(VALUE x, VALUE y)
{
    size_t xn = RBIGNUM_LEN(x), yn = RBIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, RBIGNUM_SIGN(x)==RBIGNUM_SIGN(y));
    bary_mul_normal(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

/* efficient squaring (2 times faster than normal multiplication)
 * ref: Handbook of Applied Cryptography, Algorithm 14.16
 *      http://www.cacr.math.uwaterloo.ca/hac/about/chap14.pdf
 */
static void
bary_sq_fast(BDIGIT *zds, size_t zn, BDIGIT *xds, size_t xn)
{
    size_t i, j;
    BDIGIT_DBL c, v, w;

    assert(xn * 2 <= zn);

    MEMZERO(zds, BDIGIT, zn);
    for (i = 0; i < xn; i++) {
	v = (BDIGIT_DBL)xds[i];
	if (!v)
            continue;
	c = (BDIGIT_DBL)zds[i + i] + v * v;
	zds[i + i] = BIGLO(c);
	c = BIGDN(c);
	v *= 2;
	for (j = i + 1; j < xn; j++) {
	    w = (BDIGIT_DBL)xds[j];
	    c += (BDIGIT_DBL)zds[i + j] + BIGLO(v) * w;
	    zds[i + j] = BIGLO(c);
	    c = BIGDN(c);
	    if (BIGDN(v))
                c += w;
	}
	if (c) {
	    c += (BDIGIT_DBL)zds[i + xn];
	    zds[i + xn] = BIGLO(c);
	    c = BIGDN(c);
            assert(c == 0 || i != xn-1);
            if (c && i != xn-1)
                zds[i + xn + 1] += (BDIGIT)c;
	}
    }
}

VALUE
rb_big_sq_fast(VALUE x)
{
    size_t xn = RBIGNUM_LEN(x), zn = 2 * xn;
    VALUE z = bignew(zn, 1);
    bary_sq_fast(BDIGITS(z), zn, BDIGITS(x), xn);
    RB_GC_GUARD(x);
    return z;
}

/* balancing multiplication by slicing larger argument */
static void
bary_mul_balance_with_mulfunc(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl, BDIGIT *wds, size_t wl, mulfunc_t *mulfunc)
{
    VALUE work = 0;
    size_t yl0 = yl;
    size_t r, n;

    assert(xl + yl <= zl);
    assert(2 * xl <= yl || 3 * xl <= 2*(yl+2));

    MEMZERO(zds, BDIGIT, xl);

    n = 0;
    while (yl > 0) {
        BDIGIT *tds;
        size_t tl;
	r = xl > yl ? yl : xl;
        tl = xl + r;
        if (2 * (xl + r) <= zl - n) {
            tds = zds + n + xl + r;
            mulfunc(tds, tl, xds, xl, yds + n, r, wds, wl);
            MEMZERO(zds + n + xl, BDIGIT, r);
            bary_add(zds + n, tl,
                     zds + n, tl,
                     tds, tl);
        }
        else {
            if (wl < xl) {
                wl = xl;
                wds = ALLOCV_N(BDIGIT, work, wl);
            }
            tds = zds + n;
            MEMCPY(wds, zds + n, BDIGIT, xl);
            mulfunc(tds, tl, xds, xl, yds + n, r, wds-xl, wl-xl);
            bary_add(zds + n, tl,
                     zds + n, tl,
                     wds, xl);
        }
	yl -= r;
	n += r;
    }
    MEMZERO(zds+xl+yl0, BDIGIT, zl - (xl+yl0));

    if (work)
        ALLOCV_END(work);
}

VALUE
rb_big_mul_balance(VALUE x, VALUE y)
{
    size_t xn = RBIGNUM_LEN(x), yn = RBIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, RBIGNUM_SIGN(x)==RBIGNUM_SIGN(y));
    if (!(2 * xn <= yn || 3 * xn <= 2*(yn+2)))
        rb_raise(rb_eArgError, "invalid bignum length");
    bary_mul_balance_with_mulfunc(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn, NULL, 0, bary_mul_toom3_start);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

/* multiplication by karatsuba method */
static void
bary_mul_karatsuba(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl, BDIGIT *wds, size_t wl)
{
    VALUE work = 0;

    size_t n;
    int sub_p, borrow, carry1, carry2, carry3;

    int odd_y = 0;
    int odd_xy = 0;

    BDIGIT *xds0, *xds1, *yds0, *yds1, *zds0, *zds1, *zds2, *zds3;

    assert(xl + yl <= zl);
    assert(xl <= yl);
    assert(yl < 2 * xl);

    if (yl & 1) {
        odd_y = 1;
        yl--;
        if (yl < xl) {
            odd_xy = 1;
            xl--;
        }
    }

    n = yl / 2;

    assert(n < xl);

    if (wl < n) {
        /* This function itself needs only n BDIGITs for work area.
         * However this function calls bary_mul_karatsuba and
         * bary_mul_balance recursively.
         * 2n BDIGITs are enough to avoid allocations in
         * the recursively called functions.
         */
        wl = 2*n;
        wds = ALLOCV_N(BDIGIT, work, wl);
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

    if (bary_sub(zds0, n, xds, n, xds+n, xl-n)) {
        bary_2comp(zds0, n);
        sub_p = !sub_p;
    }

    /* zds0:|x1-x0| zds1:? zds2:? zds3:? wds:? */

    if (bary_sub(wds, n, yds, n, yds+n, n)) {
        bary_2comp(wds, n);
        sub_p = !sub_p;
    }

    /* zds0:|x1-x0| zds1:? zds2:? zds3:? wds:|y1-y0| */

    bary_mul_karatsuba_start(zds1, 2*n, zds0, n, wds, n, wds+n, wl-n);

    /* zds0:|x1-x0| zds1,zds2:|x1-x0|*|y1-y0| zds3:? wds:|y1-y0| */

    borrow = 0;
    if (sub_p) {
        borrow = !bary_2comp(zds1, 2*n);
    }
    /* zds0:|x1-x0| zds1,zds2:-?|x1-x0|*|y1-y0| zds3:? wds:|y1-y0| */

    MEMCPY(wds, zds1, BDIGIT, n);

    /* zds0:|x1-x0| zds1,zds2:-?|x1-x0|*|y1-y0| zds3:? wds:lo(-?|x1-x0|*|y1-y0|) */

    bary_mul_karatsuba_start(zds0, 2*n, xds0, n, yds0, n, wds+n, wl-n);

    /* zds0,zds1:x0*y0 zds2:hi(-?|x1-x0|*|y1-y0|) zds3:? wds:lo(-?|x1-x0|*|y1-y0|) */

    carry1 = bary_add(wds, n, wds, n, zds0, n);
    carry1 = bary_addc(zds2, n, zds2, n, zds1, n, carry1);

    /* zds0,zds1:x0*y0 zds2:hi(x0*y0-?|x1-x0|*|y1-y0|) zds3:? wds:lo(x0*y0-?|x1-x0|*|y1-y0|) */

    carry2 = bary_add(zds1, n, zds1, n, wds, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|) zds2:hi(x0*y0-?|x1-x0|*|y1-y0|) zds3:? wds:lo(x0*y0-?|x1-x0|*|y1-y0|) */

    MEMCPY(wds, zds2, BDIGIT, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|) zds2:_ zds3:? wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    bary_mul_karatsuba_start(zds2, zl-2*n, xds1, xl-n, yds1, n, wds+n, wl-n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|) zds2,zds3:x1*y1 wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    carry3 = bary_add(zds1, n, zds1, n, zds2, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|)+lo(x1*y1) zds2,zds3:x1*y1 wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    carry3 = bary_addc(zds2, n, zds2, n, zds3, (4*n < zl ? n : zl-3*n), carry3);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|)+lo(x1*y1) zds2,zds3:x1*y1+hi(x1*y1) wds:hi(x0*y0-?|x1-x0|*|y1-y0|) */

    bary_add(zds2, zl-2*n, zds2, zl-2*n, wds, n);

    /* zds0:lo(x0*y0) zds1:hi(x0*y0)+lo(x0*y0-?|x1-x0|*|y1-y0|)+lo(x1*y1) zds2,zds3:x1*y1+hi(x1*y1)+hi(x0*y0-?|x1-x0|*|y1-y0|) wds:_ */

    if (carry2)
        bary_add_one(zds2, zl-2*n);

    if (carry1 + carry3 - borrow < 0)
        bary_sub_one(zds3, zl-3*n);
    else if (carry1 + carry3 - borrow > 0) {
        BDIGIT c = carry1 + carry3 - borrow;
        bary_add(zds3, zl-3*n, zds3, zl-3*n, &c, 1);
    }

    /*
    if (SIZEOF_BDIGITS * zl <= 16) {
        uint128_t z, x, y;
        ssize_t i;
        for (x = 0, i = xl-1; 0 <= i; i--) { x <<= SIZEOF_BDIGITS*CHAR_BIT; x |= xds[i]; }
        for (y = 0, i = yl-1; 0 <= i; i--) { y <<= SIZEOF_BDIGITS*CHAR_BIT; y |= yds[i]; }
        for (z = 0, i = zl-1; 0 <= i; i--) { z <<= SIZEOF_BDIGITS*CHAR_BIT; z |= zds[i]; }
        assert(z == x * y);
    }
    */

    if (odd_xy) {
        bary_muladd_1xN(zds+yl, zl-yl, yds[yl], xds, xl);
        bary_muladd_1xN(zds+xl, zl-xl, xds[xl], yds, yl+1);
    }
    else if (odd_y) {
        bary_muladd_1xN(zds+yl, zl-yl, yds[yl], xds, xl);
    }

    if (work)
        ALLOCV_END(work);
}

VALUE
rb_big_mul_karatsuba(VALUE x, VALUE y)
{
    size_t xn = RBIGNUM_LEN(x), yn = RBIGNUM_LEN(y), zn = xn + yn;
    VALUE z = bignew(zn, RBIGNUM_SIGN(x)==RBIGNUM_SIGN(y));
    if (!(xn <= yn && yn < 2 * xn))
        rb_raise(rb_eArgError, "invalid bignum length");
    bary_mul_karatsuba(BDIGITS(z), zn, BDIGITS(x), xn, BDIGITS(y), yn, NULL, 0);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

static void
bary_mul1(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl)
{
    assert(xl + yl <= zl);

    if (xl == 1 && yl == 1) {
        bary_mul_single(zds, zl, xds[0], yds[0]);
    }
    else {
        bary_mul_normal(zds, zl, xds, xl, yds, yl);
        rb_thread_check_ints();
    }
}

/* determine whether a bignum is sparse or not by random sampling */
static inline int
bary_sparse_p(BDIGIT *ds, size_t n)
{
    long c = 0;

    if (          ds[rb_genrand_ulong_limited(n / 2) + n / 4]) c++;
    if (c <= 1 && ds[rb_genrand_ulong_limited(n / 2) + n / 4]) c++;
    if (c <= 1 && ds[rb_genrand_ulong_limited(n / 2) + n / 4]) c++;

    return (c <= 1) ? 1 : 0;
}

static int
bary_mul_precheck(BDIGIT **zdsp, size_t *zlp, BDIGIT **xdsp, size_t *xlp, BDIGIT **ydsp, size_t *ylp)
{
    size_t nlsz; /* number of least significant zero BDIGITs */

    BDIGIT *zds = *zdsp;
    size_t zl = *zlp;
    BDIGIT *xds = *xdsp;
    size_t xl = *xlp;
    BDIGIT *yds = *ydsp;
    size_t yl = *ylp;

    assert(xl + yl <= zl);

    while (0 < xl && xds[xl-1] == 0)
        xl--;
    while (0 < yl && yds[yl-1] == 0)
        yl--;

    nlsz = 0;
    while (0 < xl && xds[0] == 0) {
        xds++;
        xl--;
        nlsz++;
    }
    while (0 < yl && yds[0] == 0) {
        yds++;
        yl--;
        nlsz++;
    }
    if (nlsz) {
        MEMZERO(zds, BDIGIT, nlsz);
        zds += nlsz;
        zl -= nlsz;
    }

    /* make sure that y is longer than x */
    if (xl > yl) {
        BDIGIT *tds;
        size_t tl;
	tds = xds; xds = yds; yds = tds;
	tl = xl; xl = yl; yl = tl;
    }
    assert(xl <= yl);

    if (xl == 0) {
        MEMZERO(zds, BDIGIT, zl);
        return 1;
    }

    if (xl == 1) {
        if (xds[0] == 1) {
            MEMCPY(zds, yds, BDIGIT, yl);
            MEMZERO(zds+yl, BDIGIT, zl-yl);
            return 1;
        }
        if (POW2_P(xds[0])) {
            zds[yl] = bary_small_lshift(zds, yds, yl, bitsize(xds[0])-1);
            MEMZERO(zds+yl+1, BDIGIT, zl-yl-1);
            return 1;
        }
        if (yl == 1 && yds[0] == 1) {
            zds[0] = xds[0];
            MEMZERO(zds+1, BDIGIT, zl-1);
            return 1;
        }
        bary_mul_normal(zds, zl, xds, xl, yds, yl);
        return 1;
    }

    *zdsp = zds;
    *zlp = zl;
    *xdsp = xds;
    *xlp = xl;
    *ydsp = yds;
    *ylp = yl;

    return 0;
}

static void
bary_mul_karatsuba_branch(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl, BDIGIT *wds, size_t wl)
{
    /* normal multiplication when x is small */
    if (xl < KARATSUBA_MUL_DIGITS) {
      normal:
        if (xds == yds && xl == yl)
            bary_sq_fast(zds, zl, xds, xl);
        else
            bary_mul1(zds, zl, xds, xl, yds, yl);
        return;
    }

    /* normal multiplication when x or y is a sparse bignum */
    if (bary_sparse_p(xds, xl)) goto normal;
    if (bary_sparse_p(yds, yl)) {
        bary_mul1(zds, zl, yds, yl, xds, xl);
        return;
    }

    /* balance multiplication by slicing y when x is much smaller than y */
    if (2 * xl <= yl) {
        bary_mul_balance_with_mulfunc(zds, zl, xds, xl, yds, yl, wds, wl, bary_mul_karatsuba_start);
        return;
    }

    /* multiplication by karatsuba method */
    bary_mul_karatsuba(zds, zl, xds, xl, yds, yl, wds, wl);
}

static void
bary_mul_karatsuba_start(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl, BDIGIT *wds, size_t wl)
{
    if (bary_mul_precheck(&zds, &zl, &xds, &xl, &yds, &yl))
        return;

    bary_mul_karatsuba_branch(zds, zl, xds, xl, yds, yl, wds, wl);
}

static void
bary_mul_toom3_branch(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl, BDIGIT *wds, size_t wl)
{
    if (yl < TOOM3_MUL_DIGITS) {
        bary_mul_karatsuba_branch(zds, zl, xds, xl, yds, yl, wds, wl);
        return;
    }

    if (3*xl <= 2*(yl + 2)) {
        bary_mul_balance_with_mulfunc(zds, zl, xds, xl, yds, yl, wds, wl, bary_mul_toom3_start);
        return;
    }

    {
        VALUE x, y, z;
        x = bignew(xl, 1);
	MEMCPY(BDIGITS(x), xds, BDIGIT, xl);
        y = bignew(yl, 1);
	MEMCPY(BDIGITS(y), yds, BDIGIT, yl);
        z = bigtrunc(bigmul1_toom3(x, y));
        MEMCPY(zds, BDIGITS(z), BDIGIT, RBIGNUM_LEN(z));
        MEMZERO(zds + RBIGNUM_LEN(z), BDIGIT, zl - RBIGNUM_LEN(z));
        RB_GC_GUARD(z);
    }
}

static void
bary_mul_toom3_start(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl, BDIGIT *wds, size_t wl)
{
    if (bary_mul_precheck(&zds, &zl, &xds, &xl, &yds, &yl))
        return;

    bary_mul_toom3_branch(zds, zl, xds, xl, yds, yl, wds, wl);
}

static void
bary_mul(BDIGIT *zds, size_t zl, BDIGIT *xds, size_t xl, BDIGIT *yds, size_t yl)
{
    bary_mul_toom3_start(zds, zl, xds, xl, yds, yl, NULL, 0);
}

#define BIGNUM_DEBUG 0
#if BIGNUM_DEBUG
#define ON_DEBUG(x) do { x; } while (0)
static void
dump_bignum(VALUE x)
{
    long i;
    printf("%c0x0", RBIGNUM_SIGN(x) ? '+' : '-');
    for (i = RBIGNUM_LEN(x); i--; ) {
        printf("_%0*"PRIxBDIGIT, SIZEOF_BDIGITS*2, BDIGITS(x)[i]);
    }
    printf(", len=%lu", RBIGNUM_LEN(x));
    puts("");
}

static VALUE
rb_big_dump(VALUE x)
{
    dump_bignum(x);
    return x;
}
#else
#define ON_DEBUG(x)
#endif

static int
bigzero_p(VALUE x)
{
    return bary_zero_p(BDIGITS(x), RBIGNUM_LEN(x));
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
    if (RB_TYPE_P(val, T_BIGNUM)) {
	if (BIGZEROP(val)) return 0;
	if (RBIGNUM_SIGN(val)) return 1;
	return -1;
    }
    if (RTEST(rb_funcall(val, '>', 1, INT2FIX(0)))) return 1;
    if (RTEST(rb_funcall(val, '<', 1, INT2FIX(0)))) return -1;
    return 0;
}

#define RBIGNUM_SET_LEN(b,l) \
    ((RBASIC(b)->flags & RBIGNUM_EMBED_FLAG) ? \
     (void)(RBASIC(b)->flags = \
	    (RBASIC(b)->flags & ~RBIGNUM_EMBED_LEN_MASK) | \
	    ((l) << RBIGNUM_EMBED_LEN_SHIFT)) : \
     (void)(RBIGNUM(b)->as.heap.len = (l)))

static void
rb_big_realloc(VALUE big, long len)
{
    BDIGIT *ds;
    if (RBASIC(big)->flags & RBIGNUM_EMBED_FLAG) {
	if (RBIGNUM_EMBED_LEN_MAX < len) {
	    ds = ALLOC_N(BDIGIT, len);
	    MEMCPY(ds, RBIGNUM(big)->as.ary, BDIGIT, RBIGNUM_EMBED_LEN_MAX);
	    RBIGNUM(big)->as.heap.len = RBIGNUM_LEN(big);
	    RBIGNUM(big)->as.heap.digits = ds;
	    RBASIC(big)->flags &= ~RBIGNUM_EMBED_FLAG;
	}
    }
    else {
	if (len <= RBIGNUM_EMBED_LEN_MAX) {
	    ds = RBIGNUM(big)->as.heap.digits;
	    RBASIC(big)->flags |= RBIGNUM_EMBED_FLAG;
	    RBIGNUM_SET_LEN(big, len);
	    if (ds) {
		MEMCPY(RBIGNUM(big)->as.ary, ds, BDIGIT, len);
		xfree(ds);
	    }
	}
	else {
	    if (RBIGNUM_LEN(big) == 0) {
		RBIGNUM(big)->as.heap.digits = ALLOC_N(BDIGIT, len);
	    }
	    else {
		REALLOC_N(RBIGNUM(big)->as.heap.digits, BDIGIT, len);
	    }
	}
    }
}

void
rb_big_resize(VALUE big, long len)
{
    rb_big_realloc(big, len);
    RBIGNUM_SET_LEN(big, len);
}

static VALUE
bignew_1(VALUE klass, long len, int sign)
{
    NEWOBJ_OF(big, struct RBignum, klass, T_BIGNUM | (RGENGC_WB_PROTECTED_BIGNUM ? FL_WB_PROTECTED : 0));
    RBIGNUM_SET_SIGN(big, sign?1:0);
    if (len <= RBIGNUM_EMBED_LEN_MAX) {
	RBASIC(big)->flags |= RBIGNUM_EMBED_FLAG;
	RBIGNUM_SET_LEN(big, len);
    }
    else {
	RBIGNUM(big)->as.heap.digits = ALLOC_N(BDIGIT, len);
	RBIGNUM(big)->as.heap.len = len;
    }
    OBJ_FREEZE(big);
    return (VALUE)big;
}

VALUE
rb_big_new(long len, int sign)
{
    return bignew(len, sign != 0);
}

VALUE
rb_big_clone(VALUE x)
{
    long len = RBIGNUM_LEN(x);
    VALUE z = bignew_1(CLASS_OF(x), len, RBIGNUM_SIGN(x));

    MEMCPY(BDIGITS(z), BDIGITS(x), BDIGIT, len);
    return z;
}

static void
big_extend_carry(VALUE x)
{
    rb_big_resize(x, RBIGNUM_LEN(x)+1);
    BDIGITS(x)[RBIGNUM_LEN(x)-1] = 1;
}

/* modify a bignum by 2's complement */
static void
get2comp(VALUE x)
{
    long i = RBIGNUM_LEN(x);
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
    long n = RBIGNUM_LEN(x);
    BDIGIT *ds = BDIGITS(x);
    BDIGIT hibits = 0;

    while (0 < n && ds[n-1] == 0)
        n--;

    if (n != 0 && RBIGNUM_NEGATIVE_P(x)) {
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
    RBIGNUM_SET_SIGN(x, !hibits);
    if (hibits) {
        get2comp(x);
    }
}

static inline VALUE
bigtrunc(VALUE x)
{
    long len = RBIGNUM_LEN(x);
    BDIGIT *ds = BDIGITS(x);

    if (len == 0) return x;
    while (--len && !ds[len]);
    if (RBIGNUM_LEN(x) > len+1) {
	rb_big_resize(x, len+1);
    }
    return x;
}

static inline VALUE
bigfixize(VALUE x)
{
    long len = RBIGNUM_LEN(x);
    BDIGIT *ds = BDIGITS(x);

    if (len == 0) return INT2FIX(0);
    if (BIGSIZE(x) <= sizeof(long)) {
	long num = 0;
#if SIZEOF_BDIGITS >= SIZEOF_LONG
	num = (long)ds[0];
#else
	while (len--) {
	    num = (long)(BIGUP(num) + ds[len]);
	}
#endif
	if (num >= 0) {
	    if (RBIGNUM_SIGN(x)) {
		if (POSFIXABLE(num)) return LONG2FIX(num);
	    }
	    else {
		if (NEGFIXABLE(-num)) return LONG2FIX(-num);
	    }
	}
    }
    return x;
}

static VALUE
bignorm(VALUE x)
{
    if (RB_TYPE_P(x, T_BIGNUM)) {
	x = bigfixize(x);
        if (!FIXNUM_P(x))
            bigtrunc(x);
    }
    return x;
}

VALUE
rb_big_norm(VALUE x)
{
    return bignorm(x);
}

VALUE
rb_uint2big(VALUE n)
{
    long i;
    VALUE big = bignew(bdigit_roomof(SIZEOF_VALUE), 1);
    BDIGIT *digits = BDIGITS(big);

#if SIZEOF_BDIGITS >= SIZEOF_VALUE
    digits[0] = n;
#else
    for (i = 0; i < bdigit_roomof(SIZEOF_VALUE); i++) {
	digits[i] = BIGLO(n);
	n = BIGDN(n);
    }
#endif

    i = bdigit_roomof(SIZEOF_VALUE);
    while (--i && !digits[i]) ;
    RBIGNUM_SET_LEN(big, i+1);
    return big;
}

VALUE
rb_int2big(SIGNED_VALUE n)
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
	RBIGNUM_SET_SIGN(big, 0);
    }
    return big;
}

VALUE
rb_uint2inum(VALUE n)
{
    if (POSFIXABLE(n)) return LONG2FIX(n);
    return rb_uint2big(n);
}

VALUE
rb_int2inum(SIGNED_VALUE n)
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
#if SIZEOF_BDIGITS >= SIZEOF_LONG
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
        de = dp + RBIGNUM_LEN(val);
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
    return (de - dp) * SIZEOF_BDIGITS - num_leading_zeros / CHAR_BIT;
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
    BDIGIT numbytes_bary[bdigit_roomof(sizeof(numbytes))];
    BDIGIT char_bit[1] = { CHAR_BIT };
    BDIGIT val_numbits_bary[bdigit_roomof(sizeof(numbytes) + 1)];
    BDIGIT nlz_bits_in_msbyte_bary[1] = { nlz_bits_in_msbyte };
    BDIGIT word_numbits_bary[bdigit_roomof(sizeof(word_numbits))];
    BDIGIT div_bary[numberof(val_numbits_bary) + BIGDIVREM_EXTRA_WORDS];
    BDIGIT mod_bary[numberof(word_numbits_bary)];
    BDIGIT one[1] = { 1 };
    size_t nlz_bits;
    size_t mod;
    int sign;
    size_t numwords;

    /*
     * val_numbits = numbytes * CHAR_BIT - nlz_bits_in_msbyte
     * div, mod = val_numbits.divmod(word_numbits)
     * numwords = mod == 0 ? div : div + 1
     * nlz_bits = mod == 0 ? 0 : word_numbits - mod
     */

    bary_unpack(BARY_ARGS(numbytes_bary), &numbytes, 1, sizeof(numbytes), 0,
        INTEGER_PACK_NATIVE_BYTE_ORDER);
    BARY_MUL1(val_numbits_bary, numbytes_bary, char_bit);
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

    if (sign == 2)
        return (size_t)-1;
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
    size_t nlz_bits;

    if (word_numbits == 0)
        return (size_t)-1;

    numbytes = rb_absint_size(val, &nlz_bits_in_msbyte);

    if (numbytes <= SIZE_MAX / CHAR_BIT) {
        numwords = absint_numwords_small(numbytes, nlz_bits_in_msbyte, word_numbits, &nlz_bits);
#ifdef DEBUG_INTEGER_PACK
        {
            size_t numwords0, nlz_bits0;
            numwords0 = absint_numwords_generic(numbytes, nlz_bits_in_msbyte, word_numbits, &nlz_bits0);
            assert(numwords0 == numwords);
            assert(nlz_bits0 == nlz_bits);
        }
#endif
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
#if SIZEOF_BDIGITS >= SIZEOF_LONG
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
        de = dp + RBIGNUM_LEN(val);
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
#if SIZEOF_BDIGITS >= SIZEOF_LONG
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
        sign = RBIGNUM_POSITIVE_P(val) ? 1 : -1;
        ds = BDIGITS(val);
        num_bdigits = RBIGNUM_LEN(val);
    }

    return bary_pack(sign, ds, num_bdigits, words, numwords, wordsize, nails, flags);
}

/*
 * Import an integer into a buffer.
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
            return LONG2FIX(u);
	if (sign < 0 && BDIGIT_MSB(fixbuf[1]) == 0 &&
                NEGFIXABLE(-(BDIGIT_DBL_SIGNED)u))
            return LONG2FIX(-(BDIGIT_DBL_SIGNED)u);
        val = bignew((long)num_bdigits, 0 <= sign);
        MEMCPY(BDIGITS(val), fixbuf, BDIGIT, num_bdigits);
    }

    if ((flags & INTEGER_PACK_FORCE_BIGNUM) && sign != 0 &&
        bary_zero_p(BDIGITS(val), RBIGNUM_LEN(val)))
        sign = 0;
    RBIGNUM_SET_SIGN(val, 0 <= sign);

    if (flags & INTEGER_PACK_FORCE_BIGNUM)
        return bigtrunc(val);
    return bignorm(val);
}

#define QUAD_SIZE 8

void
rb_quad_pack(char *buf, VALUE val)
{
    rb_integer_pack(val, buf, 1, QUAD_SIZE, 0,
            INTEGER_PACK_NATIVE_BYTE_ORDER|
            INTEGER_PACK_2COMP);
}

VALUE
rb_quad_unpack(const char *buf, int signed_p)
{
    return rb_integer_unpack(buf, 1, QUAD_SIZE, 0,
            INTEGER_PACK_NATIVE_BYTE_ORDER|
            (signed_p ? INTEGER_PACK_2COMP : 0));
}

VALUE
rb_cstr_to_inum(const char *str, int base, int badcheck)
{
    const char *s = str;
    char sign = 1, nondigit = 0;
    int c;
    VALUE z;

    int bits_per_digit;
    size_t i;

    const char *digits_start, *digits_end, *p;
    size_t num_digits;
    size_t num_bdigits;

#undef ISDIGIT
#define ISDIGIT(c) ('0' <= (c) && (c) <= '9')
#define conv_digit(c) (ruby_digit36_to_number_table[(unsigned char)(c)])

    if (!str) {
	if (badcheck) goto bad;
	return INT2FIX(0);
    }
    while (ISSPACE(*str)) str++;

    if (str[0] == '+') {
	str++;
    }
    else if (str[0] == '-') {
	str++;
	sign = 0;
    }
    if (str[0] == '+' || str[0] == '-') {
	if (badcheck) goto bad;
	return INT2FIX(0);
    }
    if (base <= 0) {
	if (str[0] == '0') {
	    switch (str[1]) {
	      case 'x': case 'X':
		base = 16;
                str += 2;
		break;
	      case 'b': case 'B':
		base = 2;
                str += 2;
		break;
	      case 'o': case 'O':
		base = 8;
                str += 2;
		break;
	      case 'd': case 'D':
		base = 10;
                str += 2;
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
    else if (base == 2) {
	if (str[0] == '0' && (str[1] == 'b'||str[1] == 'B')) {
	    str += 2;
	}
    }
    else if (base == 8) {
	if (str[0] == '0' && (str[1] == 'o'||str[1] == 'O')) {
	    str += 2;
	}
    }
    else if (base == 10) {
	if (str[0] == '0' && (str[1] == 'd'||str[1] == 'D')) {
	    str += 2;
	}
    }
    else if (base == 16) {
	if (str[0] == '0' && (str[1] == 'x'||str[1] == 'X')) {
	    str += 2;
	}
    }
    if (base < 2 || 36 < base) {
        rb_raise(rb_eArgError, "invalid radix %d", base);
    }
    if (*str == '0') {		/* squeeze preceding 0s */
	int us = 0;
	while ((c = *++str) == '0' || c == '_') {
	    if (c == '_') {
		if (++us >= 2)
		    break;
	    } else
		us = 0;
	}
	if (!(c = *str) || ISSPACE(c)) --str;
    }
    c = *str;
    c = conv_digit(c);
    if (c < 0 || c >= base) {
	if (badcheck) goto bad;
	return INT2FIX(0);
    }

    bits_per_digit = bitsize(base-1);
    if (bits_per_digit * strlen(str) <= sizeof(long) * CHAR_BIT) {
        char *end;
	unsigned long val = STRTOUL(str, &end, base);

	if (str < end && *end == '_') goto bigparse;
	if (badcheck) {
	    if (end == str) goto bad; /* no number */
	    while (*end && ISSPACE(*end)) end++;
	    if (*end) goto bad;	      /* trailing garbage */
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
	    RBIGNUM_SET_SIGN(big, sign);
	    return bignorm(big);
	}
    }
  bigparse:
    if (badcheck && *str == '_') goto bad;

    num_digits = 0;
    digits_start = digits_end = str;
    while ((c = *str++) != 0) {
	if (c == '_') {
	    if (nondigit) {
		if (badcheck) goto bad;
		break;
	    }
	    nondigit = (char) c;
	    continue;
	}
	else if ((c = conv_digit(c)) < 0) {
	    break;
	}
	if (c >= base) break;
	nondigit = 0;
        num_digits++;
        digits_end = str;
    }
    if (badcheck) {
	str--;
	if (s+1 < str && str[-1] == '_') goto bad;
	while (*str && ISSPACE(*str)) str++;
	if (*str) {
	  bad:
	    rb_invalid_str(s, "Integer()");
	}
    }

    if (POW2_P(base)) {
        BDIGIT *dp;
        BDIGIT_DBL dd;
        int numbits;
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
        assert((size_t)(dp - BDIGITS(z)) == num_bdigits);
    }
    else {
        int digits_per_bdigits_dbl;
        BDIGIT_DBL power;
        power = maxpow_in_bdigit_dbl(base, &digits_per_bdigits_dbl);
        num_bdigits = roomof(num_digits, digits_per_bdigits_dbl)*2;

        if (num_bdigits < KARATSUBA_MUL_DIGITS) {
            size_t blen = 1;
            BDIGIT *zds;
            BDIGIT_DBL num;

            z = bignew(num_bdigits, sign);
            zds = BDIGITS(z);
            MEMZERO(zds, BDIGIT, num_bdigits);

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
                assert(blen <= num_bdigits);
            }
        }
        else {
            VALUE powerv;
            size_t unit;
            VALUE tmpuv = 0;
            BDIGIT *uds, *vds, *tds;
            BDIGIT_DBL dd;
            BDIGIT_DBL current_base;
            int m;

            uds = ALLOCV_N(BDIGIT, tmpuv, 2*num_bdigits);
            vds = uds + num_bdigits;

            powerv = bignew(2, 1);
            BDIGITS(powerv)[0] = BIGLO(power);
            BDIGITS(powerv)[1] = (BDIGIT)BIGDN(power);

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
            assert(i == num_bdigits);
            for (unit = 2; unit < num_bdigits; unit *= 2) {
                for (i = 0; i < num_bdigits; i += unit*2) {
                    if (2*unit <= num_bdigits - i) {
                        bary_mul(vds+i, unit*2, BDIGITS(powerv), RBIGNUM_LEN(powerv), uds+i+unit, unit);
                        bary_add(vds+i, unit*2, vds+i, unit*2, uds+i, unit);
                    }
                    else if (unit <= num_bdigits - i) {
                        bary_mul(vds+i, num_bdigits-i, BDIGITS(powerv), RBIGNUM_LEN(powerv), uds+i+unit, num_bdigits-(i+unit));
                        bary_add(vds+i, num_bdigits-i, vds+i, num_bdigits-i, uds+i, unit);
                    }
                    else {
                        MEMCPY(vds+i, uds+i, BDIGIT, num_bdigits-i);
                    }
                }
                powerv = bigtrunc(bigmul0(powerv, powerv));
                tds = vds;
                vds = uds;
                uds = tds;
            }
            while (0 < num_bdigits && uds[num_bdigits-1] == 0)
                num_bdigits--;
            z = bignew(num_bdigits, sign);
            MEMCPY(BDIGITS(z), uds, BDIGIT, num_bdigits);

            if (tmpuv)
                ALLOCV_END(tmpuv);
        }
    }

    return bignorm(z);
}

VALUE
rb_str_to_inum(VALUE str, int base, int badcheck)
{
    char *s;
    long len;
    VALUE v = 0;
    VALUE ret;

    StringValue(str);
    rb_must_asciicompat(str);
    if (badcheck) {
	s = StringValueCStr(str);
    }
    else {
	s = RSTRING_PTR(str);
    }
    if (s) {
	len = RSTRING_LEN(str);
	if (s[len]) {		/* no sentinel somehow */
	    char *p = ALLOCV(v, len+1);

	    MEMCPY(p, s, char, len);
	    p[len] = '\0';
	    s = p;
	}
    }
    ret = rb_cstr_to_inum(s, base, badcheck);
    if (v)
	ALLOCV_END(v);
    return ret;
}

#if HAVE_LONG_LONG

static VALUE
rb_ull2big(unsigned LONG_LONG n)
{
    long i;
    VALUE big = bignew(bdigit_roomof(SIZEOF_LONG_LONG), 1);
    BDIGIT *digits = BDIGITS(big);

#if SIZEOF_BDIGITS >= SIZEOF_LONG_LONG
    digits[0] = n;
#else
    for (i = 0; i < bdigit_roomof(SIZEOF_LONG_LONG); i++) {
	digits[i] = BIGLO(n);
	n = BIGDN(n);
    }
#endif

    i = bdigit_roomof(SIZEOF_LONG_LONG);
    while (i-- && !digits[i]) ;
    RBIGNUM_SET_LEN(big, i+1);
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
	RBIGNUM_SET_SIGN(big, 0);
    }
    return big;
}

VALUE
rb_ull2inum(unsigned LONG_LONG n)
{
    if (POSFIXABLE(n)) return LONG2FIX(n);
    return rb_ull2big(n);
}

VALUE
rb_ll2inum(LONG_LONG n)
{
    if (FIXABLE(n)) return LONG2FIX(n);
    return rb_ll2big(n);
}

#endif  /* HAVE_LONG_LONG */

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

    if (LONG_MAX < shift_numdigits) {
        rb_raise(rb_eArgError, "too big number");
    }

    s1 = shift_numdigits;
    s2 = shift_numbits;

    if (lshift_p) {
        xn = RBIGNUM_LEN(x);
        z = bignew(xn+s1+1, RBIGNUM_SIGN(x));
        zds = BDIGITS(z);
        MEMZERO(zds, BDIGIT, s1);
        xds = BDIGITS(x);
        zds[xn+s1] = bary_small_lshift(zds+s1, xds, xn, s2);
    }
    else {
        long zn;
        BDIGIT hibitsx;
        if (s1 >= RBIGNUM_LEN(x)) {
            if (RBIGNUM_POSITIVE_P(x) ||
                bary_zero_p(BDIGITS(x), RBIGNUM_LEN(x)))
                return INT2FIX(0);
            else
                return INT2FIX(-1);
        }
        hibitsx = abs2twocomp(&x, &xn);
        xds = BDIGITS(x);
        if (xn <= s1) {
            return hibitsx ? INT2FIX(-1) : INT2FIX(0);
        }
        zn = xn - s1;
        z = bignew(zn, 0);
        zds = BDIGITS(z);
        bary_small_rshift(zds, xds+s1, zn, s2, hibitsx != 0);
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

    assert(POW2_P(CHAR_BIT));
    assert(POW2_P(BITSPERDIG));

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
            return RBIGNUM_POSITIVE_P(x) ? INT2FIX(0) : INT2FIX(-1);
    }
    shift_numbits = lens[0] & (BITSPERDIG-1);
    shift_numdigits = (lens[0] >> bitsize(BITSPERDIG-1)) |
      (lens[1] << (CHAR_BIT*SIZEOF_SIZE_T - bitsize(BITSPERDIG-1)));
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

static inline int
ones(register unsigned long x)
{
#if GCC_VERSION_SINCE(3, 4, 0)
    return  __builtin_popcountl(x);
#else
#   if SIZEOF_LONG == 8
#       define MASK_55 0x5555555555555555UL
#       define MASK_33 0x3333333333333333UL
#       define MASK_0f 0x0f0f0f0f0f0f0f0fUL
#   else
#       define MASK_55 0x55555555UL
#       define MASK_33 0x33333333UL
#       define MASK_0f 0x0f0f0f0fUL
#   endif
    x -= (x >> 1) & MASK_55;
    x = ((x >> 2) & MASK_33) + (x & MASK_33);
    x = ((x >> 4) + x) & MASK_0f;
    x += (x >> 8);
    x += (x >> 16);
#   if SIZEOF_LONG == 8
    x += (x >> 32);
#   endif
    return (int)(x & 0x7f);
#   undef MASK_0f
#   undef MASK_33
#   undef MASK_55
#endif
}

static inline unsigned long
next_pow2(register unsigned long x)
{
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
#if SIZEOF_LONG == 8
    x |= x >> 32;
#endif
    return x + 1;
}

static inline int
floor_log2(register unsigned long x)
{
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
#if SIZEOF_LONG == 8
    x |= x >> 32;
#endif
    return (int)ones(x) - 1;
}

static inline int
ceil_log2(register unsigned long x)
{
    return floor_log2(x) + !POW2_P(x);
}

#define LOG2_KARATSUBA_DIGITS 7
#define KARATSUBA_DIGITS (1L<<LOG2_KARATSUBA_DIGITS)
#define MAX_BIG2STR_TABLE_ENTRIES 64

static VALUE big2str_power_cache[35][MAX_BIG2STR_TABLE_ENTRIES];

static void
power_cache_init(void)
{
    int i, j;
    for (i = 0; i < 35; ++i) {
	for (j = 0; j < MAX_BIG2STR_TABLE_ENTRIES; ++j) {
	    big2str_power_cache[i][j] = Qnil;
	}
    }
}

static inline VALUE
power_cache_get_power0(int base, int i)
{
    if (NIL_P(big2str_power_cache[base - 2][i])) {
	big2str_power_cache[base - 2][i] =
	    i == 0 ? rb_big_pow(rb_int2big(base), INT2FIX(KARATSUBA_DIGITS))
		   : bigsqr(power_cache_get_power0(base, i - 1));
	rb_gc_register_mark_object(big2str_power_cache[base - 2][i]);
    }
    return big2str_power_cache[base - 2][i];
}

static VALUE
power_cache_get_power(int base, long n1, long* m1)
{
    int i, m;
    long j;
    VALUE t;

    if (n1 <= KARATSUBA_DIGITS)
	rb_bug("n1 > KARATSUBA_DIGITS");

    m = ceil_log2(n1);
    if (m1) *m1 = 1 << m;
    i = m - LOG2_KARATSUBA_DIGITS;
    if (i >= MAX_BIG2STR_TABLE_ENTRIES)
	i = MAX_BIG2STR_TABLE_ENTRIES - 1;
    t = power_cache_get_power0(base, i);

    j = KARATSUBA_DIGITS*(1 << i);
    while (n1 > j) {
	t = bigsqr(t);
	j *= 2;
    }
    return t;
}

/* big2str_muraken_find_n1
 *
 * Let a natural number x is given by:
 * x = 2^0 * x_0 + 2^1 * x_1 + ... + 2^(B*n_0 - 1) * x_{B*n_0 - 1},
 * where B is BITSPERDIG (i.e. BDIGITS*CHAR_BIT) and n_0 is
 * RBIGNUM_LEN(x).
 *
 * Now, we assume n_1 = min_n \{ n | 2^(B*n_0/2) <= b_1^(n_1) \}, so
 * it is realized that 2^(B*n_0) <= {b_1}^{2*n_1}, where b_1 is a
 * given radix number. And then, we have n_1 <= (B*n_0) /
 * (2*log_2(b_1)), therefore n_1 is given by ceil((B*n_0) /
 * (2*log_2(b_1))).
 */
static long
big2str_find_n1(VALUE x, int base)
{
    static const double log_2[] = {
	1.0,              1.58496250072116, 2.0,
	2.32192809488736, 2.58496250072116, 2.8073549220576,
	3.0,              3.16992500144231, 3.32192809488736,
	3.4594316186373,  3.58496250072116, 3.70043971814109,
	3.8073549220576,  3.90689059560852, 4.0,
	4.08746284125034, 4.16992500144231, 4.24792751344359,
	4.32192809488736, 4.39231742277876, 4.4594316186373,
	4.52356195605701, 4.58496250072116, 4.64385618977472,
	4.70043971814109, 4.75488750216347, 4.8073549220576,
	4.85798099512757, 4.90689059560852, 4.95419631038688,
	5.0,              5.04439411935845, 5.08746284125034,
	5.12928301694497, 5.16992500144231
    };
    long bits;

    if (base < 2 || 36 < base)
	rb_bug("invalid radix %d", base);

    if (FIXNUM_P(x)) {
	bits = (SIZEOF_LONG*CHAR_BIT - 1)/2 + 1;
    }
    else if (BIGZEROP(x)) {
	return 0;
    }
    else if (RBIGNUM_LEN(x) >= LONG_MAX/BITSPERDIG) {
	rb_raise(rb_eRangeError, "bignum too big to convert into `string'");
    }
    else {
	bits = BITSPERDIG*RBIGNUM_LEN(x);
    }

    /* @shyouhei note: vvvvvvvvvvvvv this cast is suspicious.  But I believe it is OK, because if that cast loses data, this x value is too big, and should have raised RangeError. */
    return (long)ceil(((double)bits)/log_2[base - 2]);
}

static long
big2str_orig(VALUE x, int base, char* ptr, long len, BDIGIT hbase, int hbase_numdigits, int trim)
{
    long i = RBIGNUM_LEN(x), j = len;
    BDIGIT* ds = BDIGITS(x);

    while (i && j > 0) {
	long k = i;
	BDIGIT_DBL num = 0;

	while (k--) {               /* x / hbase */
	    num = BIGUP(num) + ds[k];
	    ds[k] = (BDIGIT)(num / hbase);
	    num %= hbase;
	}
	if (trim && ds[i-1] == 0) i--;
	k = hbase_numdigits;
	while (k--) {
	    ptr[--j] = ruby_digitmap[num % base];
	    num /= base;
	    if (j <= 0) break;
	    if (trim && i == 0 && num == 0) break;
	}
    }
    if (trim) {
	while (j < len && ptr[j] == '0') j++;
	MEMMOVE(ptr, ptr + j, char, len - j);
	len -= j;
    }
    return len;
}

static long
big2str_karatsuba(VALUE x, int base, char* ptr,
		  long n1, long len, BDIGIT hbase, int hbase_numdigits, int trim)
{
    long lh, ll, m1;
    VALUE b, q, r;

    if (BIGZEROP(x)) {
	if (trim) return 0;
	else {
	    memset(ptr, '0', len);
	    return len;
	}
    }

    if (n1 <= KARATSUBA_DIGITS) {
	return big2str_orig(x, base, ptr, len, hbase, hbase_numdigits, trim);
    }

    b = power_cache_get_power(base, n1, &m1);
    bigdivmod(x, b, &q, &r);
    rb_obj_hide(q);
    rb_obj_hide(r);
    lh = big2str_karatsuba(q, base, ptr, (len - m1)/2,
			   len - m1, hbase, hbase_numdigits, trim);
    rb_big_resize(q, 0);
    ll = big2str_karatsuba(r, base, ptr + lh, m1/2,
			   m1, hbase, hbase_numdigits, !lh && trim);
    rb_big_resize(r, 0);

    return lh + ll;
}

static VALUE
big2str_base_powerof2(VALUE x, size_t len, int base, int trim)
{
    int word_numbits = ffs(base) - 1;
    size_t numwords;
    VALUE result;
    char *ptr;
    numwords = trim ? rb_absint_numwords(x, word_numbits, NULL) : len;
    if (RBIGNUM_NEGATIVE_P(x) || !trim) {
        if (LONG_MAX-1 < numwords)
            rb_raise(rb_eArgError, "too big number");
        result = rb_usascii_str_new(0, 1+numwords);
        ptr = RSTRING_PTR(result);
        *ptr++ = RBIGNUM_POSITIVE_P(x) ? '+' : '-';
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
rb_big2str0(VALUE x, int base, int trim)
{
    int off;
    VALUE ss, xx;
    long n1, n2, len;
    BDIGIT hbase;
    int hbase_numdigits;
    char* ptr;

    if (FIXNUM_P(x)) {
	return rb_fix2str(x, base);
    }
    if (BIGZEROP(x)) {
	return rb_usascii_str_new2("0");
    }

    if (base < 2 || 36 < base)
	rb_raise(rb_eArgError, "invalid radix %d", base);

    n2 = big2str_find_n1(x, base);

    if (POW2_P(base)) {
        /* base == 2 || base == 4 || base == 8 || base == 16 || base == 32 */
        return big2str_base_powerof2(x, (size_t)n2, base, trim);
    }

    n1 = (n2 + 1) / 2;
    ss = rb_usascii_str_new(0, n2 + 1); /* plus one for sign */
    ptr = RSTRING_PTR(ss);
    ptr[0] = RBIGNUM_SIGN(x) ? '+' : '-';

    hbase = maxpow_in_bdigit(base, &hbase_numdigits);
    off = !(trim && RBIGNUM_SIGN(x)); /* erase plus sign if trim */
    xx = rb_big_clone(x);
    RBIGNUM_SET_SIGN(xx, 1);
    if (n1 <= KARATSUBA_DIGITS) {
	len = off + big2str_orig(xx, base, ptr + off, n2, hbase, hbase_numdigits, trim);
    }
    else {
	len = off + big2str_karatsuba(xx, base, ptr + off, n1,
				      n2, hbase, hbase_numdigits, trim);
    }
    rb_big_resize(xx, 0);

    ptr[len] = '\0';
    rb_str_resize(ss, len);

    return ss;
}

VALUE
rb_big2str(VALUE x, int base)
{
    return rb_big2str0(x, base, 1);
}

/*
 *  call-seq:
 *     big.to_s(base=10)   ->  string
 *
 *  Returns a string containing the representation of <i>big</i> radix
 *  <i>base</i> (2 through 36).
 *
 *     12345654321.to_s         #=> "12345654321"
 *     12345654321.to_s(2)      #=> "1011011111110110111011110000110001"
 *     12345654321.to_s(8)      #=> "133766736061"
 *     12345654321.to_s(16)     #=> "2dfdbbc31"
 *     78546939656932.to_s(36)  #=> "rubyrules"
 */

static VALUE
rb_big_to_s(int argc, VALUE *argv, VALUE x)
{
    int base;

    if (argc == 0) base = 10;
    else {
	VALUE b;

	rb_scan_args(argc, argv, "01", &b);
	base = NUM2INT(b);
    }
    return rb_big2str(x, base);
}

static unsigned long
big2ulong(VALUE x, const char *type)
{
    long len = RBIGNUM_LEN(x);
    unsigned long num;
    BDIGIT *ds;

    if (len == 0)
        return 0;
    if (BIGSIZE(x) > sizeof(long)) {
        rb_raise(rb_eRangeError, "bignum too big to convert into `%s'", type);
    }
    ds = BDIGITS(x);
#if SIZEOF_LONG <= SIZEOF_BDIGITS
    num = (unsigned long)ds[0];
#else
    num = 0;
    while (len--) {
	num <<= BITSPERDIG;
	num += (unsigned long)ds[len]; /* overflow is already checked */
    }
#endif
    return num;
}

VALUE
rb_big2ulong_pack(VALUE x)
{
    unsigned long num;
    rb_integer_pack(x, &num, 1, sizeof(num), 0,
        INTEGER_PACK_NATIVE_BYTE_ORDER|INTEGER_PACK_2COMP);
    return num;
}

VALUE
rb_big2ulong(VALUE x)
{
    unsigned long num = big2ulong(x, "unsigned long");

    if (RBIGNUM_POSITIVE_P(x)) {
        return num;
    }
    else {
        if (num <= LONG_MAX)
            return -(long)num;
        if (num == 1+(unsigned long)(-(LONG_MIN+1)))
            return LONG_MIN;
    }
    rb_raise(rb_eRangeError, "bignum out of range of unsigned long");
}

SIGNED_VALUE
rb_big2long(VALUE x)
{
    unsigned long num = big2ulong(x, "long");

    if (RBIGNUM_POSITIVE_P(x)) {
        if (num <= LONG_MAX)
            return num;
    }
    else {
        if (num <= LONG_MAX)
            return -(long)num;
        if (num == 1+(unsigned long)(-(LONG_MIN+1)))
            return LONG_MIN;
    }
    rb_raise(rb_eRangeError, "bignum too big to convert into `long'");
}

#if HAVE_LONG_LONG

static unsigned LONG_LONG
big2ull(VALUE x, const char *type)
{
    long len = RBIGNUM_LEN(x);
    unsigned LONG_LONG num;
    BDIGIT *ds = BDIGITS(x);

    if (len == 0)
        return 0;
    if (BIGSIZE(x) > SIZEOF_LONG_LONG)
	rb_raise(rb_eRangeError, "bignum too big to convert into `%s'", type);
#if SIZEOF_LONG_LONG <= SIZEOF_BDIGITS
    num = (unsigned LONG_LONG)ds[0];
#else
    num = 0;
    while (len--) {
	num = BIGUP(num);
	num += ds[len];
    }
#endif
    return num;
}

unsigned LONG_LONG
rb_big2ull(VALUE x)
{
    unsigned LONG_LONG num = big2ull(x, "unsigned long long");

    if (RBIGNUM_POSITIVE_P(x)) {
        return num;
    }
    else {
        if (num <= LLONG_MAX)
            return -(LONG_LONG)num;
        if (num == 1+(unsigned LONG_LONG)(-(LLONG_MIN+1)))
            return LLONG_MIN;
    }
    rb_raise(rb_eRangeError, "bignum out of range of unsigned long long");
}

LONG_LONG
rb_big2ll(VALUE x)
{
    unsigned LONG_LONG num = big2ull(x, "long long");

    if (RBIGNUM_POSITIVE_P(x)) {
        if (num <= LLONG_MAX)
            return num;
    }
    else {
        if (num <= LLONG_MAX)
            return -(LONG_LONG)num;
        if (num == 1+(unsigned LONG_LONG)(-(LLONG_MIN+1)))
            return LLONG_MIN;
    }
    rb_raise(rb_eRangeError, "bignum too big to convert into `long long'");
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

    while (!POSFIXABLE(u) || 0 != (long)u) {
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
    long i = (bigtrunc(x), RBIGNUM_LEN(x)), lo = 0, bits;
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
		    dl &= BDIGMAX << bits;
		    dl = BIGLO(dl + ((BDIGIT)1 << bits));
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
    if (!RBIGNUM_SIGN(x)) d = -d;
    return d;
}

double
rb_big2dbl(VALUE x)
{
    double d = big2dbl(x);

    if (isinf(d)) {
	rb_warning("Bignum out of Float range");
	if (d < 0.0)
	    d = -HUGE_VAL;
	else
	    d = HUGE_VAL;
    }
    return d;
}

/*
 *  call-seq:
 *     big.to_f -> float
 *
 *  Converts <i>big</i> to a <code>Float</code>. If <i>big</i> doesn't
 *  fit in a <code>Float</code>, the result is infinity.
 *
 */

static VALUE
rb_big_to_f(VALUE x)
{
    return DBL2NUM(rb_big2dbl(x));
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
        long xl, yl;
        if (yi < FIXNUM_MIN)
            return INT2FIX(1);
        if (FIXNUM_MAX+1 <= yi)
            return INT2FIX(-1);
        xl = FIX2LONG(x);
        yl = (long)yi;
        if (xl < yl)
            return INT2FIX(-1);
        if (xl > yl)
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

VALUE
rb_integer_float_eq(VALUE x, VALUE y)
{
    double yd = RFLOAT_VALUE(y);
    double yi, yf;

    if (isnan(yd) || isinf(yd))
        return Qfalse;
    yf = modf(yd, &yi);
    if (yf != 0)
        return Qfalse;
    if (FIXNUM_P(x)) {
#if SIZEOF_LONG * CHAR_BIT < DBL_MANT_DIG /* assume FLT_RADIX == 2 */
        double xd = (double)FIX2LONG(x);
        if (xd != yd)
            return Qfalse;
        return Qtrue;
#else
        long xl, yl;
        if (yi < LONG_MIN || LONG_MAX < yi)
            return Qfalse;
        xl = FIX2LONG(x);
        yl = (long)yi;
        if (xl != yl)
            return Qfalse;
        return Qtrue;
#endif
    }
    y = rb_dbl2big(yi);
    return rb_big_eq(x, y);
}

/*
 *  call-seq:
 *     big <=> numeric   -> -1, 0, +1 or nil
 *
 *  Comparison---Returns -1, 0, or +1 depending on whether +big+ is
 *  less than, equal to, or greater than +numeric+. This is the
 *  basis for the tests in Comparable.
 *
 *  +nil+ is returned if the two values are incomparable.
 *
 */

VALUE
rb_big_cmp(VALUE x, VALUE y)
{
    long xlen = RBIGNUM_LEN(x);
    BDIGIT *xds, *yds;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
        return rb_integer_float_cmp(x, y);

      default:
	return rb_num_coerce_cmp(x, y, rb_intern("<=>"));
    }

    if (RBIGNUM_SIGN(x) > RBIGNUM_SIGN(y)) return INT2FIX(1);
    if (RBIGNUM_SIGN(x) < RBIGNUM_SIGN(y)) return INT2FIX(-1);
    if (xlen < RBIGNUM_LEN(y))
	return (RBIGNUM_SIGN(x)) ? INT2FIX(-1) : INT2FIX(1);
    if (xlen > RBIGNUM_LEN(y))
	return (RBIGNUM_SIGN(x)) ? INT2FIX(1) : INT2FIX(-1);

    xds = BDIGITS(x);
    yds = BDIGITS(y);

    while (xlen-- && (xds[xlen]==yds[xlen]));
    if (-1 == xlen) return INT2FIX(0);
    return (xds[xlen] > yds[xlen]) ?
	(RBIGNUM_SIGN(x) ? INT2FIX(1) : INT2FIX(-1)) :
	    (RBIGNUM_SIGN(x) ? INT2FIX(-1) : INT2FIX(1));
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

    switch (TYPE(y)) {
      case T_FIXNUM:
      case T_BIGNUM:
	rel = rb_big_cmp(x, y);
	break;

      case T_FLOAT:
        rel = rb_integer_float_cmp(x, y);
        break;

      default:
	{
	    ID id = 0;
	    switch (op) {
		case big_op_gt: id = '>'; break;
		case big_op_ge: id = rb_intern(">="); break;
		case big_op_lt: id = '<'; break;
		case big_op_le: id = rb_intern("<="); break;
	    }
	    return rb_num_coerce_relop(x, y, id);
	}
    }

    if (NIL_P(rel)) return Qfalse;
    n = FIX2INT(rel);

    switch (op) {
	case big_op_gt: return n >  0 ? Qtrue : Qfalse;
	case big_op_ge: return n >= 0 ? Qtrue : Qfalse;
	case big_op_lt: return n <  0 ? Qtrue : Qfalse;
	case big_op_le: return n <= 0 ? Qtrue : Qfalse;
    }
    return Qundef;
}

/*
 * call-seq:
 *   big > real  ->  true or false
 *
 * Returns <code>true</code> if the value of <code>big</code> is
 * greater than that of <code>real</code>.
 */

static VALUE
big_gt(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_gt);
}

/*
 * call-seq:
 *   big >= real  ->  true or false
 *
 * Returns <code>true</code> if the value of <code>big</code> is
 * greater than or equal to that of <code>real</code>.
 */

static VALUE
big_ge(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_ge);
}

/*
 * call-seq:
 *   big < real  ->  true or false
 *
 * Returns <code>true</code> if the value of <code>big</code> is
 * less than that of <code>real</code>.
 */

static VALUE
big_lt(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_lt);
}

/*
 * call-seq:
 *   big <= real  ->  true or false
 *
 * Returns <code>true</code> if the value of <code>big</code> is
 * less than or equal to that of <code>real</code>.
 */

static VALUE
big_le(VALUE x, VALUE y)
{
    return big_op(x, y, big_op_le);
}

/*
 *  call-seq:
 *     big == obj  -> true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> has the same value
 *  as <i>big</i>. Contrast this with <code>Bignum#eql?</code>, which
 *  requires <i>obj</i> to be a <code>Bignum</code>.
 *
 *     68719476736 == 68719476736.0   #=> true
 */

VALUE
rb_big_eq(VALUE x, VALUE y)
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	if (bignorm(x) == y) return Qtrue;
	y = rb_int2big(FIX2LONG(y));
	break;
      case T_BIGNUM:
	break;
      case T_FLOAT:
        return rb_integer_float_eq(x, y);
      default:
	return rb_equal(y, x);
    }
    if (RBIGNUM_SIGN(x) != RBIGNUM_SIGN(y)) return Qfalse;
    if (RBIGNUM_LEN(x) != RBIGNUM_LEN(y)) return Qfalse;
    if (MEMCMP(BDIGITS(x),BDIGITS(y),BDIGIT,RBIGNUM_LEN(y)) != 0) return Qfalse;
    return Qtrue;
}

/*
 *  call-seq:
 *     big.eql?(obj)   -> true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> is a
 *  <code>Bignum</code> with the same value as <i>big</i>. Contrast this
 *  with <code>Bignum#==</code>, which performs type conversions.
 *
 *     68719476736.eql?(68719476736.0)   #=> false
 */

VALUE
rb_big_eql(VALUE x, VALUE y)
{
    if (!RB_TYPE_P(y, T_BIGNUM)) return Qfalse;
    if (RBIGNUM_SIGN(x) != RBIGNUM_SIGN(y)) return Qfalse;
    if (RBIGNUM_LEN(x) != RBIGNUM_LEN(y)) return Qfalse;
    if (MEMCMP(BDIGITS(x),BDIGITS(y),BDIGIT,RBIGNUM_LEN(y)) != 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    -big   ->  integer
 *
 * Unary minus (returns an integer whose value is 0-big)
 */

VALUE
rb_big_uminus(VALUE x)
{
    VALUE z = rb_big_clone(x);

    RBIGNUM_SET_SIGN(z, !RBIGNUM_SIGN(x));

    return bignorm(z);
}

/*
 * call-seq:
 *     ~big  ->  integer
 *
 * Inverts the bits in big. As Bignums are conceptually infinite
 * length, the result acts as if it had an infinite number of one
 * bits to the left. In hex representations, this is displayed
 * as two periods to the left of the digits.
 *
 *   sprintf("%X", ~0x1122334455)    #=> "..FEEDDCCBBAA"
 */

static VALUE
rb_big_neg(VALUE x)
{
    VALUE z = rb_big_clone(x);
    BDIGIT *ds = BDIGITS(z);
    long n = RBIGNUM_LEN(z);

    if (!n) return INT2FIX(-1);

    if (RBIGNUM_POSITIVE_P(z)) {
        if (bary_add_one(ds, n)) {
            big_extend_carry(z);
        }
        RBIGNUM_SET_NEGATIVE_SIGN(z);
    }
    else {
        bary_neg(ds, n);
        if (bary_add_one(ds, n))
            return INT2FIX(-1);
        bary_neg(ds, n);
        RBIGNUM_SET_POSITIVE_SIGN(z);
    }

    return bignorm(z);
}

static void
bigsub_core(BDIGIT *xds, long xn, BDIGIT *yds, long yn, BDIGIT *zds, long zn)
{
    bary_sub(zds, zn, xds, xn, yds, yn);
}

static VALUE
bigsub(VALUE x, VALUE y)
{
    VALUE z = 0;
    long i = RBIGNUM_LEN(x);
    BDIGIT *xds, *yds;

    /* if x is smaller than y, swap */
    if (RBIGNUM_LEN(x) < RBIGNUM_LEN(y)) {
	z = x; x = y; y = z;	/* swap x y */
    }
    else if (RBIGNUM_LEN(x) == RBIGNUM_LEN(y)) {
	xds = BDIGITS(x);
	yds = BDIGITS(y);
	while (i > 0) {
	    i--;
	    if (xds[i] > yds[i]) {
		break;
	    }
	    if (xds[i] < yds[i]) {
		z = x; x = y; y = z;	/* swap x y */
		break;
	    }
	}
    }

    z = bignew(RBIGNUM_LEN(x), z==0);
    bigsub_core(BDIGITS(x), RBIGNUM_LEN(x),
		BDIGITS(y), RBIGNUM_LEN(y),
		BDIGITS(z), RBIGNUM_LEN(z));

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
    xn = RBIGNUM_LEN(x);

    if (xn == 0)
        return LONG2NUM(-y0);

    zn = xn;
#if SIZEOF_BDIGITS < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    z = bignew(zn, RBIGNUM_SIGN(x));
    zds = BDIGITS(z);

#if SIZEOF_BDIGITS >= SIZEOF_LONG
    assert(xn == zn);
    num = (BDIGIT_DBL_SIGNED)xds[0] - y;
    if (xn == 1 && num < 0) {
	RBIGNUM_SET_SIGN(z, !RBIGNUM_SIGN(x));
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
#if SIZEOF_BDIGITS < SIZEOF_LONG
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
#if SIZEOF_BDIGITS < SIZEOF_LONG
    for (; i < zn; i++) {
      num_is_zero_z:
        zds[i] = 0;
    }
#endif
    goto finish;

  finish:
    assert(num == 0 || num == -1);
    if (num < 0) {
        get2comp(z);
	RBIGNUM_SET_SIGN(z, !RBIGNUM_SIGN(x));
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
    xn = RBIGNUM_LEN(x);

    if (xn == 0)
        return LONG2NUM(y);

    zn = xn;
#if SIZEOF_BDIGITS < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    zn++;

    z = bignew(zn, RBIGNUM_SIGN(x));
    zds = BDIGITS(z);

#if SIZEOF_BDIGITS >= SIZEOF_LONG
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

static void
bigadd_core(BDIGIT *xds, long xn, BDIGIT *yds, long yn, BDIGIT *zds, long zn)
{
    bary_add(zds, zn, xds, xn, yds, yn);
}

static VALUE
bigadd(VALUE x, VALUE y, int sign)
{
    VALUE z;
    long len;

    sign = (sign == RBIGNUM_SIGN(y));
    if (RBIGNUM_SIGN(x) != sign) {
	if (sign) return bigsub(y, x);
	return bigsub(x, y);
    }

    if (RBIGNUM_LEN(x) > RBIGNUM_LEN(y)) {
	len = RBIGNUM_LEN(x) + 1;
    }
    else {
	len = RBIGNUM_LEN(y) + 1;
    }
    z = bignew(len, sign);

    bigadd_core(BDIGITS(x), RBIGNUM_LEN(x),
		BDIGITS(y), RBIGNUM_LEN(y),
		BDIGITS(z), RBIGNUM_LEN(z));

    return z;
}

/*
 *  call-seq:
 *     big + other  -> Numeric
 *
 *  Adds big and other, returning the result.
 */

VALUE
rb_big_plus(VALUE x, VALUE y)
{
    long n;

    switch (TYPE(y)) {
      case T_FIXNUM:
	n = FIX2LONG(y);
	if ((n > 0) != RBIGNUM_SIGN(x)) {
	    if (n < 0) {
		n = -n;
	    }
	    return bigsub_int(x, n);
	}
	if (n < 0) {
	    n = -n;
	}
	return bigadd_int(x, n);

      case T_BIGNUM:
	return bignorm(bigadd(x, y, 1));

      case T_FLOAT:
	return DBL2NUM(rb_big2dbl(x) + RFLOAT_VALUE(y));

      default:
	return rb_num_coerce_bin(x, y, '+');
    }
}

/*
 *  call-seq:
 *     big - other  -> Numeric
 *
 *  Subtracts other from big, returning the result.
 */

VALUE
rb_big_minus(VALUE x, VALUE y)
{
    long n;

    switch (TYPE(y)) {
      case T_FIXNUM:
	n = FIX2LONG(y);
	if ((n > 0) != RBIGNUM_SIGN(x)) {
	    if (n < 0) {
		n = -n;
	    }
	    return bigadd_int(x, n);
	}
	if (n < 0) {
	    n = -n;
	}
	return bigsub_int(x, n);

      case T_BIGNUM:
	return bignorm(bigadd(x, y, 0));

      case T_FLOAT:
	return DBL2NUM(rb_big2dbl(x) - RFLOAT_VALUE(y));

      default:
	return rb_num_coerce_bin(x, y, '-');
    }
}

static long
big_real_len(VALUE x)
{
    long i = RBIGNUM_LEN(x);
    BDIGIT *xds = BDIGITS(x);
    while (--i && !xds[i]);
    return i + 1;
}


/* split a bignum into high and low bignums */
static void
big_split(VALUE v, long n, volatile VALUE *ph, volatile VALUE *pl)
{
    long hn = 0, ln = RBIGNUM_LEN(v);
    VALUE h, l;
    BDIGIT *vds = BDIGITS(v);

    if (ln > n) {
	hn = ln - n;
	ln = n;
    }

    if (!hn) {
	h = rb_uint2big(0);
    }
    else {
	while (--hn && !vds[hn + ln]);
	h = bignew(hn += 2, 1);
	MEMCPY(BDIGITS(h), vds + ln, BDIGIT, hn - 1);
	BDIGITS(h)[hn - 1] = 0; /* margin for carry */
    }

    while (--ln && !vds[ln]);
    l = bignew(ln += 2, 1);
    MEMCPY(BDIGITS(l), vds, BDIGIT, ln - 1);
    BDIGITS(l)[ln - 1] = 0; /* margin for carry */

    *pl = l;
    *ph = h;
}

static void
big_split3(VALUE v, long n, volatile VALUE* p0, volatile VALUE* p1, volatile VALUE* p2)
{
    VALUE v0, v12, v1, v2;

    big_split(v, n, &v12, &v0);
    big_split(v12, n, &v2, &v1);

    *p0 = bigtrunc(v0);
    *p1 = bigtrunc(v1);
    *p2 = bigtrunc(v2);
}

static VALUE bigdivrem(VALUE, VALUE, volatile VALUE*, volatile VALUE*);

static VALUE
bigmul1_toom3(VALUE x, VALUE y)
{
    long n, xn, yn, zn;
    VALUE x0, x1, x2, y0, y1, y2;
    VALUE u0, u1, u2, u3, u4, v1, v2, v3;
    VALUE z0, z1, z2, z3, z4, z, t;
    BDIGIT* zds;

    xn = RBIGNUM_LEN(x);
    yn = RBIGNUM_LEN(y);
    assert(xn <= yn);  /* assume y >= x */

    n = (yn + 2) / 3;
    big_split3(x, n, &x0, &x1, &x2);
    if (x == y) {
	y0 = x0; y1 = x1; y2 = x2;
    }
    else big_split3(y, n, &y0, &y1, &y2);

    /*
     * ref. http://en.wikipedia.org/wiki/Toom%E2%80%93Cook_multiplication
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
     * (Step2) interpolating z0, z1, z2, z3, z4, and z5.
     *
     * (Step3) Substituting base value into b of the polynomial z(b),
     */

    /*
     * [Step1] calculating 5 points z(b0), z(b1), z(b2), z(b3), z(b4)
     */

    /* u1 <- x0 + x2 */
    u1 = bigtrunc(bigadd(x0, x2, 1));

    /* x(-1) : u2 <- u1 - x1 = x0 - x1 + x2 */
    u2 = bigtrunc(bigsub(u1, x1));

    /* x(1) : u1 <- u1 + x1 = x0 + x1 + x2 */
    u1 = bigtrunc(bigadd(u1, x1, 1));

    /* x(-2) : u3 <- 2 * (u2 + x2) - x0 = x0 - 2 * (x1 - 2 * x2) */
    u3 = bigadd(u2, x2, 1);
    if (BDIGITS(u3)[RBIGNUM_LEN(u3)-1] & BIGRAD_HALF) {
	rb_big_resize(u3, RBIGNUM_LEN(u3) + 1);
	BDIGITS(u3)[RBIGNUM_LEN(u3)-1] = 0;
    }
    bary_small_lshift(BDIGITS(u3), BDIGITS(u3), RBIGNUM_LEN(u3), 1);
    u3 = bigtrunc(bigadd(bigtrunc(u3), x0, 0));

    if (x == y) {
	v1 = u1; v2 = u2; v3 = u3;
    }
    else {
	/* v1 <- y0 + y2 */
	v1 = bigtrunc(bigadd(y0, y2, 1));

	/* y(-1) : v2 <- v1 - y1 = y0 - y1 + y2 */
	v2 = bigtrunc(bigsub(v1, y1));

	/* y(1) : v1 <- v1 + y1 = y0 + y1 + y2 */
	v1 = bigtrunc(bigadd(v1, y1, 1));

	/* y(-2) : v3 <- 2 * (v2 + y2) - y0 = y0 - 2 * (y1 - 2 * y2) */
	v3 = bigadd(v2, y2, 1);
	if (BDIGITS(v3)[RBIGNUM_LEN(v3)-1] & BIGRAD_HALF) {
	    rb_big_resize(v3, RBIGNUM_LEN(v3) + 1);
	    BDIGITS(v3)[RBIGNUM_LEN(v3)-1] = 0;
	}
	bary_small_lshift(BDIGITS(v3), BDIGITS(v3), RBIGNUM_LEN(v3), 1);
	v3 = bigtrunc(bigadd(bigtrunc(v3), y0, 0));
    }

    /* z(0) : u0 <- x0 * y0 */
    u0 = bigtrunc(bigmul0(x0, y0));

    /* z(1) : u1 <- u1 * v1 */
    u1 = bigtrunc(bigmul0(u1, v1));

    /* z(-1) : u2 <- u2 * v2 */
    u2 = bigtrunc(bigmul0(u2, v2));

    /* z(-2) : u3 <- u3 * v3 */
    u3 = bigtrunc(bigmul0(u3, v3));

    /* z(inf) : u4 <- x2 * y2 */
    u4 = bigtrunc(bigmul0(x2, y2));

    /* for GC */
    v1 = v2 = v3 = Qnil;

    /*
     * [Step2] interpolating z0, z1, z2, z3, z4, and z5.
     */

    /* z0 <- z(0) == u0 */
    z0 = u0;

    /* z4 <- z(inf) == u4 */
    z4 = u4;

    /* z3 <- (z(-2) - z(1)) / 3 == (u3 - u1) / 3 */
    z3 = bigadd(u3, u1, 0);
    bigdivrem(z3, big_three, &z3, NULL); /* TODO: optimize */
    bigtrunc(z3);

    /* z1 <- (z(1) - z(-1)) / 2 == (u1 - u2) / 2 */
    z1 = bigtrunc(bigadd(u1, u2, 0));
    bary_small_rshift(BDIGITS(z1), BDIGITS(z1), RBIGNUM_LEN(z1), 1, 0);

    /* z2 <- z(-1) - z(0) == u2 - u0 */
    z2 = bigtrunc(bigadd(u2, u0, 0));

    /* z3 <- (z2 - z3) / 2 + 2 * z(inf) == (z2 - z3) / 2 + 2 * u4 */
    z3 = bigtrunc(bigadd(z2, z3, 0));
    bary_small_rshift(BDIGITS(z3), BDIGITS(z3), RBIGNUM_LEN(z3), 1, 0);
    t = big_lshift(u4, 1); /* TODO: combining with next addition */
    z3 = bigtrunc(bigadd(z3, t, 1));

    /* z2 <- z2 + z1 - z(inf) == z2 + z1 - u4 */
    z2 = bigtrunc(bigadd(z2, z1, 1));
    z2 = bigtrunc(bigadd(z2, u4, 0));

    /* z1 <- z1 - z3 */
    z1 = bigtrunc(bigadd(z1, z3, 0));

    /*
     * [Step3] Substituting base value into b of the polynomial z(b),
     */

    zn = 6*n + 1;
    z = bignew(zn, RBIGNUM_SIGN(x)==RBIGNUM_SIGN(y));
    zds = BDIGITS(z);
    MEMCPY(zds, BDIGITS(z0), BDIGIT, RBIGNUM_LEN(z0));
    MEMZERO(zds + RBIGNUM_LEN(z0), BDIGIT, zn - RBIGNUM_LEN(z0));
    bigadd_core(zds +   n, zn -   n, BDIGITS(z1), big_real_len(z1), zds +   n, zn -   n);
    bigadd_core(zds + 2*n, zn - 2*n, BDIGITS(z2), big_real_len(z2), zds + 2*n, zn - 2*n);
    bigadd_core(zds + 3*n, zn - 3*n, BDIGITS(z3), big_real_len(z3), zds + 3*n, zn - 3*n);
    bigadd_core(zds + 4*n, zn - 4*n, BDIGITS(z4), big_real_len(z4), zds + 4*n, zn - 4*n);

    return bignorm(z);
}

VALUE
rb_big_mul_toom3(VALUE x, VALUE y)
{
    return bigmul1_toom3(x, y);
}

static VALUE
bigmul0(VALUE x, VALUE y)
{
    long xn, yn, zn;
    VALUE z;
    BDIGIT *xds, *yds, *zds;

    xn = RBIGNUM_LEN(x);
    yn = RBIGNUM_LEN(y);
    zn = xn + yn;

    z = bignew(zn, RBIGNUM_SIGN(x)==RBIGNUM_SIGN(y));

    xds = BDIGITS(x);
    yds = BDIGITS(y);
    zds = BDIGITS(z);

    bary_mul(zds, zn, xds, xn, yds, yn);

    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return z;
}

/*
 *  call-seq:
 *     big * other  -> Numeric
 *
 *  Multiplies big and other, returning the result.
 */

VALUE
rb_big_mul(VALUE x, VALUE y)
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
	return DBL2NUM(rb_big2dbl(x) * RFLOAT_VALUE(y));

      default:
	return rb_num_coerce_bin(x, y, '*');
    }

    return bignorm(bigmul0(x, y));
}

struct big_div_struct {
    long nx, ny, j, nyzero;
    BDIGIT *yds, *zds;
    volatile VALUE stop;
};

static void *
bigdivrem1(void *ptr)
{
    struct big_div_struct *bds = (struct big_div_struct*)ptr;
    long ny = bds->ny;
    long i, j;
    BDIGIT *yds = bds->yds, *zds = bds->zds;
    BDIGIT_DBL t2;
    BDIGIT_DBL_SIGNED num;
    BDIGIT q;

    j = bds->j;
    do {
	if (bds->stop) {
	    bds->j = j;
	    return 0;
        }
	if (zds[j] ==  yds[ny-1]) q = BDIGMAX;
	else q = (BDIGIT)((BIGUP(zds[j]) + zds[j-1])/yds[ny-1]);
	if (q) {
           i = bds->nyzero; num = 0; t2 = 0;
	    do {			/* multiply and subtract */
		BDIGIT_DBL ee;
		t2 += (BDIGIT_DBL)yds[i] * q;
		ee = num - BIGLO(t2);
		num = (BDIGIT_DBL)zds[j - ny + i] + ee;
		if (ee) zds[j - ny + i] = BIGLO(num);
		num = BIGDN(num);
		t2 = BIGDN(t2);
	    } while (++i < ny);
	    num += zds[j - ny + i] - t2;/* borrow from high digit; don't update */
	    while (num) {		/* "add back" required */
		i = 0; num = 0; q--;
		do {
		    BDIGIT_DBL ee = num + yds[i];
		    num = (BDIGIT_DBL)zds[j - ny + i] + ee;
		    if (ee) zds[j - ny + i] = BIGLO(num);
		    num = BIGDN(num);
		} while (++i < ny);
		num--;
	    }
	}
	zds[j] = q;
    } while (--j >= ny);
    return 0;
}

static void
rb_big_stop(void *ptr)
{
    struct big_div_struct *bds = ptr;
    bds->stop = Qtrue;
}

static inline int
bigdivrem_num_extra_words(long nx, long ny)
{
    int ret = nx==ny ? 2 : 1;
    assert(ret <= BIGDIVREM_EXTRA_WORDS);
    return ret;
}

static BDIGIT
bigdivrem_single(BDIGIT *qds, BDIGIT *xds, long nx, BDIGIT y)
{
    long i;
    BDIGIT_DBL t2;
    t2 = 0;
    i = nx;
    while (i--) {
        t2 = BIGUP(t2) + xds[i];
        qds[i] = (BDIGIT)(t2 / y);
        t2 %= y;
    }
    return (BDIGIT)t2;
}

static void
bigdivrem_normal(BDIGIT *zds, long nz, BDIGIT *xds, long nx, BDIGIT *yds, long ny, int needs_mod)
{
    struct big_div_struct bds;
    BDIGIT q;
    int shift;

    q = yds[ny-1];
    shift = nlz(q);
    if (shift) {
        bary_small_lshift(yds, yds, ny, shift);
        zds[nx] = bary_small_lshift(zds, xds, nx, shift);
    }
    else {
        MEMCPY(zds, xds, BDIGIT, nx);
	zds[nx] = 0;
    }
    if (nx+1 < nz) zds[nx+1] = 0;

    bds.nx = nx;
    bds.ny = ny;
    bds.zds = zds;
    bds.yds = yds;
    bds.stop = Qfalse;
    bds.j = nz - 1;
    for (bds.nyzero = 0; !yds[bds.nyzero]; bds.nyzero++);
    if (nx > 10000 || ny > 10000) {
      retry:
	bds.stop = Qfalse;
	rb_thread_call_without_gvl(bigdivrem1, &bds, rb_big_stop, &bds);

	if (bds.stop == Qtrue) {
	    /* execute trap handler, but exception was not raised. */
	    goto retry;
	}
    }
    else {
	bigdivrem1(&bds);
    }

    if (needs_mod && shift) {
        bary_small_rshift(zds, zds, ny, shift, 0);
    }
}

static void
bary_divmod(BDIGIT *qds, size_t nq, BDIGIT *rds, size_t nr, BDIGIT *xds, size_t nx, BDIGIT *yds, size_t ny)
{
    assert(nx <= nq);
    assert(ny <= nr);

    while (0 < ny && !yds[ny-1]) ny--;
    if (ny == 0)
        rb_num_zerodiv();

    while (0 < nx && !xds[nx-1]) nx--;
    if (nx == 0) {
        MEMZERO(qds, BDIGIT, nq);
        MEMZERO(rds, BDIGIT, nr);
        return;
    }

    if (ny == 1) {
        MEMCPY(qds, xds, BDIGIT, nx);
        MEMZERO(qds+nx, BDIGIT, nq-nx);
        rds[0] = bigdivrem_single(qds, xds, nx, yds[0]);
        MEMZERO(rds+1, BDIGIT, nr-1);
    }
    else {
        int extra_words;
        long j;
        long nz;
        BDIGIT *zds;
        VALUE tmpz = 0;
        BDIGIT *tds;

        extra_words = bigdivrem_num_extra_words(nx, ny);
        nz = nx + extra_words;
        if (nx + extra_words <= nq)
            zds = qds;
        else
            zds = ALLOCV_N(BDIGIT, tmpz, nx + extra_words);
        MEMCPY(zds, xds, BDIGIT, nx);
        MEMZERO(zds+nx, BDIGIT, nz-nx);

        if (BDIGIT_MSB(yds[ny-1])) {
            /* bigdivrem_normal will not modify y.
             * So use yds directly.  */
            tds = yds;
        }
        else {
            /* bigdivrem_normal will modify y.
             * So use rds as a temporary buffer.  */
            MEMCPY(rds, yds, BDIGIT, ny);
            tds = rds;
        }

        bigdivrem_normal(zds, nz, xds, nx, tds, ny, 1);

        /* copy remainder */
        MEMCPY(rds, zds, BDIGIT, ny);
        MEMZERO(rds+ny, BDIGIT, nr-ny);

        /* move quotient */
        j = nz - ny;
        MEMMOVE(qds, zds+ny, BDIGIT, j);
        MEMZERO(qds+j, BDIGIT, nq-j);

        if (tmpz)
            ALLOCV_END(tmpz);
    }
}

static VALUE
bigdivrem(VALUE x, VALUE y, volatile VALUE *divp, volatile VALUE *modp)
{
    long nx = RBIGNUM_LEN(x), ny = RBIGNUM_LEN(y), nz;
    long j;
    VALUE z, zz;
    VALUE tmpy = 0, tmpz = 0;
    BDIGIT *xds, *yds, *zds, *tds;
    BDIGIT dd;

    yds = BDIGITS(y);
    while (0 < ny && !yds[ny-1]) ny--;
    if (ny == 0)
        rb_num_zerodiv();

    xds = BDIGITS(x);
    while (0 < nx && !xds[nx-1]) nx--;

    if (nx < ny || (nx == ny && xds[nx - 1] < yds[ny - 1])) {
	if (divp) *divp = rb_int2big(0);
	if (modp) *modp = x;
	return Qnil;
    }
    if (ny == 1) {
	dd = yds[0];
	z = bignew(nx, RBIGNUM_SIGN(x)==RBIGNUM_SIGN(y));
	zds = BDIGITS(z);
        dd = bigdivrem_single(zds, xds, nx, dd);
	if (modp) {
	    *modp = rb_uint2big((VALUE)dd);
	    RBIGNUM_SET_SIGN(*modp, RBIGNUM_SIGN(x));
	}
	if (divp) *divp = z;
	return Qnil;
    }

    if (BDIGIT_MSB(yds[ny-1]) == 0) {
        /* Make yds modifiable. */
        tds = ALLOCV_N(BDIGIT, tmpy, ny);
        MEMCPY(tds, yds, BDIGIT, ny);
        yds = tds;
    }

    nz = nx + bigdivrem_num_extra_words(nx, ny);
    zds = ALLOCV_N(BDIGIT, tmpz, nz);
    bigdivrem_normal(zds, nz, xds, nx, yds, ny, modp != NULL);

    if (divp) {			/* move quotient down in z */
        j = nz - ny;
	while (0 < j && !zds[j-1+ny])
            j--;
	*divp = zz = bignew(j, RBIGNUM_SIGN(x)==RBIGNUM_SIGN(y));
        MEMCPY(BDIGITS(zz), zds+ny, BDIGIT, j);
    }
    if (modp) {			/* normalize remainder */
	while (ny > 0 && !zds[ny-1]) --ny;
	*modp = zz = bignew(ny, RBIGNUM_SIGN(x));
	MEMCPY(BDIGITS(zz), zds, BDIGIT, ny);
    }
    if (tmpy)
        ALLOCV_END(tmpy);
    if (tmpz)
        ALLOCV_END(tmpz);
    return Qnil;
}

static void
bigdivmod(VALUE x, VALUE y, volatile VALUE *divp, volatile VALUE *modp)
{
    VALUE mod;

    bigdivrem(x, y, divp, &mod);
    if (RBIGNUM_SIGN(x) != RBIGNUM_SIGN(y) && !BIGZEROP(mod)) {
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

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
	{
	    if (op == '/') {
		return DBL2NUM(rb_big2dbl(x) / RFLOAT_VALUE(y));
	    }
	    else {
		double dy = RFLOAT_VALUE(y);
		if (dy == 0.0) rb_num_zerodiv();
		return rb_dbl2big(rb_big2dbl(x) / dy);
	    }
	}

      default:
	return rb_num_coerce_bin(x, y, op);
    }
    bigdivmod(x, y, &z, 0);

    return bignorm(z);
}

/*
 *  call-seq:
 *     big / other     -> Numeric
 *
 * Performs division: the class of the resulting object depends on
 * the class of <code>numeric</code> and on the magnitude of the
 * result.
 */

VALUE
rb_big_div(VALUE x, VALUE y)
{
    return rb_big_divide(x, y, '/');
}

/*
 *  call-seq:
 *     big.div(other)  -> integer
 *
 * Performs integer division: returns integer value.
 */

VALUE
rb_big_idiv(VALUE x, VALUE y)
{
    return rb_big_divide(x, y, rb_intern("div"));
}

/*
 *  call-seq:
 *     big % other         -> Numeric
 *     big.modulo(other)   -> Numeric
 *
 *  Returns big modulo other. See Numeric.divmod for more
 *  information.
 */

VALUE
rb_big_modulo(VALUE x, VALUE y)
{
    VALUE z;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return rb_num_coerce_bin(x, y, '%');
    }
    bigdivmod(x, y, 0, &z);

    return bignorm(z);
}

/*
 *  call-seq:
 *     big.remainder(numeric)    -> number
 *
 *  Returns the remainder after dividing <i>big</i> by <i>numeric</i>.
 *
 *     -1234567890987654321.remainder(13731)      #=> -6966
 *     -1234567890987654321.remainder(13731.24)   #=> -9906.22531493148
 */
static VALUE
rb_big_remainder(VALUE x, VALUE y)
{
    VALUE z;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return rb_num_coerce_bin(x, y, rb_intern("remainder"));
    }
    bigdivrem(x, y, 0, &z);

    return bignorm(z);
}

/*
 *  call-seq:
 *     big.divmod(numeric)   -> array
 *
 *  See <code>Numeric#divmod</code>.
 *
 */
VALUE
rb_big_divmod(VALUE x, VALUE y)
{
    VALUE div, mod;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return rb_num_coerce_bin(x, y, rb_intern("divmod"));
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

static VALUE
big_fdiv(VALUE x, VALUE y)
{
#define DBL_BIGDIG ((DBL_MANT_DIG + BITSPERDIG) / BITSPERDIG)
    VALUE z;
    long l, ex, ey;
    int i;

    bigtrunc(x);
    l = RBIGNUM_LEN(x);
    ex = l * BITSPERDIG - nlz(BDIGITS(x)[l-1]);
    ex -= 2 * DBL_BIGDIG * BITSPERDIG;
    if (ex) x = big_shift(x, ex);

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
      case T_BIGNUM:
	bigtrunc(y);
	l = RBIGNUM_LEN(y);
	ey = l * BITSPERDIG - nlz(BDIGITS(y)[l-1]);
	ey -= DBL_BIGDIG * BITSPERDIG;
	if (ey) y = big_shift(y, ey);
	break;
      case T_FLOAT:
	y = dbl2big(ldexp(frexp(RFLOAT_VALUE(y), &i), DBL_MANT_DIG));
	ey = i - DBL_MANT_DIG;
	break;
      default:
	rb_bug("big_fdiv");
    }
    bigdivrem(x, y, &z, 0);
    l = ex - ey;
#if SIZEOF_LONG > SIZEOF_INT
    {
	/* Visual C++ can't be here */
	if (l > INT_MAX) return DBL2NUM(INFINITY);
	if (l < INT_MIN) return DBL2NUM(0.0);
    }
#endif
    return DBL2NUM(ldexp(big2dbl(z), (int)l));
}

/*
 *  call-seq:
  *     big.fdiv(numeric) -> float
 *
 *  Returns the floating point result of dividing <i>big</i> by
 *  <i>numeric</i>.
 *
 *     -1234567890987654321.fdiv(13731)      #=> -89910996357705.5
 *     -1234567890987654321.fdiv(13731.24)   #=> -89909424858035.7
 *
 */


VALUE
rb_big_fdiv(VALUE x, VALUE y)
{
    double dx, dy;

    dx = big2dbl(x);
    switch (TYPE(y)) {
      case T_FIXNUM:
	dy = (double)FIX2LONG(y);
	if (isinf(dx))
	    return big_fdiv(x, y);
	break;

      case T_BIGNUM:
	dy = rb_big2dbl(y);
	if (isinf(dx) || isinf(dy))
	    return big_fdiv(x, y);
	break;

      case T_FLOAT:
	dy = RFLOAT_VALUE(y);
	if (isnan(dy))
	    return y;
	if (isinf(dx))
	    return big_fdiv(x, y);
	break;

      default:
	return rb_num_coerce_bin(x, y, rb_intern("fdiv"));
    }
    return DBL2NUM(dx / dy);
}

static VALUE
bigsqr(VALUE x)
{
    return bigtrunc(bigmul0(x, x));
}

/*
 *  call-seq:
 *     big ** exponent   -> numeric
 *
 *  Raises _big_ to the _exponent_ power (which may be an integer, float,
 *  or anything that will coerce to a number). The result may be
 *  a Fixnum, Bignum, or Float
 *
 *    123456789 ** 2      #=> 15241578750190521
 *    123456789 ** 1.2    #=> 5126464716.09932
 *    123456789 ** -2     #=> 6.5610001194102e-17
 */

VALUE
rb_big_pow(VALUE x, VALUE y)
{
    double d;
    SIGNED_VALUE yy;

  again:
    if (y == INT2FIX(0)) return INT2FIX(1);
    switch (TYPE(y)) {
      case T_FLOAT:
	d = RFLOAT_VALUE(y);
	if ((!RBIGNUM_SIGN(x) && !BIGZEROP(x)) && d != round(d))
	    return rb_funcall(rb_complex_raw1(x), rb_intern("**"), 1, y);
	break;

      case T_BIGNUM:
	y = bignorm(y);
	if (FIXNUM_P(y))
	    goto again;
	rb_warn("in a**b, b may be too big");
	d = rb_big2dbl(y);
	break;

      case T_FIXNUM:
	yy = FIX2LONG(y);

	if (yy < 0)
	    return rb_funcall(rb_rational_raw1(x), rb_intern("**"), 1, y);
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
		break;
	    }
	    for (mask = FIXNUM_MAX + 1; mask; mask >>= 1) {
		if (z) z = bigsqr(z);
		if (yy & mask) {
		    z = z ? bigtrunc(bigmul0(z, x)) : x;
		}
	    }
	    return bignorm(z);
	}
	/* NOTREACHED */
	break;

      default:
	return rb_num_coerce_bin(x, y, rb_intern("**"));
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
#if SIZEOF_BDIGITS >= SIZEOF_LONG
    if (!hibitsy) {
	y &= xds[0];
	return LONG2NUM(y);
    }
#endif

    zn = xn;
#if SIZEOF_BDIGITS < SIZEOF_LONG
    if (hibitsx && zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif

    z = bignew(zn, 0);
    zds = BDIGITS(z);

#if SIZEOF_BDIGITS >= SIZEOF_LONG
    i = 1;
    zds[0] = xds[0] & y;
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

/*
 * call-seq:
 *     big & numeric   ->  integer
 *
 * Performs bitwise +and+ between _big_ and _numeric_.
 */

VALUE
rb_big_and(VALUE x, VALUE y)
{
    VALUE z;
    BDIGIT *ds1, *ds2, *zds;
    long i, xl, yl, l1, l2;
    BDIGIT hibitsx, hibitsy;
    BDIGIT hibits1, hibits2;
    VALUE tmpv;
    BDIGIT tmph;
    long tmpl;

    if (!FIXNUM_P(y) && !RB_TYPE_P(y, T_BIGNUM)) {
	return rb_num_coerce_bit(x, y, '&');
    }

    hibitsx = abs2twocomp(&x, &xl);
    if (FIXNUM_P(y)) {
	return bigand_int(x, xl, hibitsx, FIX2LONG(y));
    }
    hibitsy = abs2twocomp(&y, &yl);
    if (xl > yl) {
        tmpv = x; x = y; y = tmpv;
        tmpl = xl; xl = yl; yl = tmpl;
        tmph = hibitsx; hibitsx = hibitsy; hibitsy = tmph;
    }
    l1 = xl;
    l2 = yl;
    ds1 = BDIGITS(x);
    ds2 = BDIGITS(y);
    hibits1 = hibitsx;
    hibits2 = hibitsy;

    if (!hibits1)
        l2 = l1;

    z = bignew(l2, 0);
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] & ds2[i];
    }
    for (; i<l2; i++) {
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

    zn = RBIGNUM_LEN(x);
#if SIZEOF_BDIGITS < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    z = bignew(zn, 0);
    zds = BDIGITS(z);

#if SIZEOF_BDIGITS >= SIZEOF_LONG
    i = 1;
    zds[0] = xds[0] | y;
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

/*
 * call-seq:
 *     big | numeric   ->  integer
 *
 * Performs bitwise +or+ between _big_ and _numeric_.
 */

VALUE
rb_big_or(VALUE x, VALUE y)
{
    VALUE z;
    BDIGIT *ds1, *ds2, *zds;
    long i, xl, yl, l1, l2;
    BDIGIT hibitsx, hibitsy;
    BDIGIT hibits1, hibits2;
    VALUE tmpv;
    BDIGIT tmph;
    long tmpl;

    if (!FIXNUM_P(y) && !RB_TYPE_P(y, T_BIGNUM)) {
	return rb_num_coerce_bit(x, y, '|');
    }

    hibitsx = abs2twocomp(&x, &xl);
    if (FIXNUM_P(y)) {
	return bigor_int(x, xl, hibitsx, FIX2LONG(y));
    }
    hibitsy = abs2twocomp(&y, &yl);
    if (xl > yl) {
        tmpv = x; x = y; y = tmpv;
        tmpl = xl; xl = yl; yl = tmpl;
        tmph = hibitsx; hibitsx = hibitsy; hibitsy = tmph;
    }
    l1 = xl;
    l2 = yl;
    ds1 = BDIGITS(x);
    ds2 = BDIGITS(y);
    hibits1 = hibitsx;
    hibits2 = hibitsy;

    if (hibits1)
        l2 = l1;

    z = bignew(l2, 0);
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] | ds2[i];
    }
    for (; i<l2; i++) {
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
    zn = RBIGNUM_LEN(x);
#if SIZEOF_BDIGITS < SIZEOF_LONG
    if (zn < bdigit_roomof(SIZEOF_LONG))
        zn = bdigit_roomof(SIZEOF_LONG);
#endif
    z = bignew(zn, 0);
    zds = BDIGITS(z);

#if SIZEOF_BDIGITS >= SIZEOF_LONG
    i = 1;
    zds[0] = xds[0] ^ y;
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
/*
 * call-seq:
 *     big ^ numeric   ->  integer
 *
 * Performs bitwise +exclusive or+ between _big_ and _numeric_.
 */

VALUE
rb_big_xor(VALUE x, VALUE y)
{
    VALUE z;
    BDIGIT *ds1, *ds2, *zds;
    long i, xl, yl, l1, l2;
    BDIGIT hibitsx, hibitsy;
    BDIGIT hibits1, hibits2;
    VALUE tmpv;
    BDIGIT tmph;
    long tmpl;

    if (!FIXNUM_P(y) && !RB_TYPE_P(y, T_BIGNUM)) {
	return rb_num_coerce_bit(x, y, '^');
    }

    hibitsx = abs2twocomp(&x, &xl);
    if (FIXNUM_P(y)) {
	return bigxor_int(x, xl, hibitsx, FIX2LONG(y));
    }
    hibitsy = abs2twocomp(&y, &yl);
    if (xl > yl) {
        tmpv = x; x = y; y = tmpv;
        tmpl = xl; xl = yl; yl = tmpl;
        tmph = hibitsx; hibitsx = hibitsy; hibitsy = tmph;
    }
    l1 = xl;
    l2 = yl;
    ds1 = BDIGITS(x);
    ds2 = BDIGITS(y);
    hibits1 = hibitsx;
    hibits2 = hibitsy;

    z = bignew(l2, 0);
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] ^ ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = hibitsx ^ ds2[i];
    }
    twocomp2abs_bang(z, (hibits1 ^ hibits2) != 0);
    RB_GC_GUARD(x);
    RB_GC_GUARD(y);
    return bignorm(z);
}

/*
 * call-seq:
 *     big << numeric   ->  integer
 *
 * Shifts big left _numeric_ positions (right if _numeric_ is negative).
 */

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
            shift_numbits = shift & (BITSPERDIG-1);
            shift_numdigits = shift >> bitsize(BITSPERDIG-1);
            return bignorm(big_shift3(x, lshift_p, shift_numdigits, shift_numbits));
	}
	else if (RB_TYPE_P(y, T_BIGNUM)) {
            return bignorm(big_shift2(x, 1, y));
	}
	y = rb_to_int(y);
    }
}


/*
 * call-seq:
 *     big >> numeric   ->  integer
 *
 * Shifts big right _numeric_ positions (left if _numeric_ is negative).
 */

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
            shift_numbits = shift & (BITSPERDIG-1);
            shift_numdigits = shift >> bitsize(BITSPERDIG-1);
            return bignorm(big_shift3(x, lshift_p, shift_numdigits, shift_numbits));
	}
	else if (RB_TYPE_P(y, T_BIGNUM)) {
            return bignorm(big_shift2(x, 0, y));
	}
	y = rb_to_int(y);
    }
}

/*
 *  call-seq:
 *     big[n] -> 0, 1
 *
 *  Bit Reference---Returns the <em>n</em>th bit in the (assumed) binary
 *  representation of <i>big</i>, where <i>big</i>[0] is the least
 *  significant bit.
 *
 *     a = 9**15
 *     50.downto(0) do |n|
 *       print a[n]
 *     end
 *
 *  <em>produces:</em>
 *
 *     000101110110100000111000011110010100111100010111001
 *
 */

static VALUE
rb_big_aref(VALUE x, VALUE y)
{
    BDIGIT *xds;
    unsigned long shift;
    long i, s1, s2;
    BDIGIT bit;

    if (RB_TYPE_P(y, T_BIGNUM)) {
	if (!RBIGNUM_SIGN(y))
	    return INT2FIX(0);
	bigtrunc(y);
	if (BIGSIZE(y) > sizeof(long)) {
	  out_of_range:
	    return RBIGNUM_SIGN(x) ? INT2FIX(0) : INT2FIX(1);
	}
	shift = big2ulong(y, "long");
    }
    else {
	i = NUM2LONG(y);
	if (i < 0) return INT2FIX(0);
	shift = i;
    }
    s1 = shift/BITSPERDIG;
    s2 = shift%BITSPERDIG;
    bit = (BDIGIT)1 << s2;

    if (s1 >= RBIGNUM_LEN(x)) goto out_of_range;

    xds = BDIGITS(x);
    if (RBIGNUM_POSITIVE_P(x))
        return (xds[s1] & bit) ? INT2FIX(1) : INT2FIX(0);
    if (xds[s1] & (bit-1))
        return (xds[s1] & bit) ? INT2FIX(0) : INT2FIX(1);
    for (i = 0; i < s1; i++)
        if (xds[i])
            return (xds[s1] & bit) ? INT2FIX(0) : INT2FIX(1);
    return (xds[s1] & bit) ? INT2FIX(1) : INT2FIX(0);
}

/*
 * call-seq:
 *   big.hash   -> fixnum
 *
 * Compute a hash based on the value of _big_.
 */

static VALUE
rb_big_hash(VALUE x)
{
    st_index_t hash;

    hash = rb_memhash(BDIGITS(x), sizeof(BDIGIT)*RBIGNUM_LEN(x)) ^ RBIGNUM_SIGN(x);
    return INT2FIX(hash);
}

/*
 * call-seq:
 *   big.coerce(numeric)  ->  array
 *
 * Returns an array with both <i>aNumeric</i> and <i>big</i> represented
 * as <code>Bignum</code> objects.
 * This is achieved by converting <i>aNumeric</i> to a <code>Bignum</code>.
 * \exception TypeError if <i>aNumeric</i> is not a type of
 * <code>Fixnum</code> or <code>Bignum</code>.
 *
 *     (0x3FFFFFFFFFFFFFFF+1).coerce(42)   #=> [42, 4611686018427387904]
 */

static VALUE
rb_big_coerce(VALUE x, VALUE y)
{
    if (FIXNUM_P(y)) {
	y = rb_int2big(FIX2LONG(y));
    }
    else if (!RB_TYPE_P(y, T_BIGNUM)) {
	rb_raise(rb_eTypeError, "can't coerce %s to Bignum",
		 rb_obj_classname(y));
    }
    return rb_assoc_new(y, x);
}

/*
 *  call-seq:
 *     big.abs -> aBignum
 *     big.magnitude -> aBignum
 *
 *  Returns the absolute value of <i>big</i>.
 *
 *     -1234567890987654321.abs   #=> 1234567890987654321
 */

static VALUE
rb_big_abs(VALUE x)
{
    if (!RBIGNUM_SIGN(x)) {
	x = rb_big_clone(x);
	RBIGNUM_SET_SIGN(x, 1);
    }
    return x;
}

/*
 *  call-seq:
 *     big.size -> integer
 *
 *  Returns the number of bytes in the machine representation of
 *  <i>big</i>.
 *
 *     (256**10 - 1).size   #=> 12
 *     (256**20 - 1).size   #=> 20
 *     (256**40 - 1).size   #=> 40
 */

static VALUE
rb_big_size(VALUE big)
{
    return LONG2FIX(RBIGNUM_LEN(big)*SIZEOF_BDIGITS);
}

/*
 *  call-seq:
 *     big.odd? -> true or false
 *
 *  Returns <code>true</code> if <i>big</i> is an odd number.
 */

static VALUE
rb_big_odd_p(VALUE num)
{
    if (BDIGITS(num)[0] & 1) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     big.even? -> true or false
 *
 *  Returns <code>true</code> if <i>big</i> is an even number.
 */

static VALUE
rb_big_even_p(VALUE num)
{
    if (BDIGITS(num)[0] & 1) {
	return Qfalse;
    }
    return Qtrue;
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
    rb_cBignum = rb_define_class("Bignum", rb_cInteger);

    rb_define_method(rb_cBignum, "to_s", rb_big_to_s, -1);
    rb_define_alias(rb_cBignum, "inspect", "to_s");
    rb_define_method(rb_cBignum, "coerce", rb_big_coerce, 1);
    rb_define_method(rb_cBignum, "-@", rb_big_uminus, 0);
    rb_define_method(rb_cBignum, "+", rb_big_plus, 1);
    rb_define_method(rb_cBignum, "-", rb_big_minus, 1);
    rb_define_method(rb_cBignum, "*", rb_big_mul, 1);
    rb_define_method(rb_cBignum, "/", rb_big_div, 1);
    rb_define_method(rb_cBignum, "%", rb_big_modulo, 1);
    rb_define_method(rb_cBignum, "div", rb_big_idiv, 1);
    rb_define_method(rb_cBignum, "divmod", rb_big_divmod, 1);
    rb_define_method(rb_cBignum, "modulo", rb_big_modulo, 1);
    rb_define_method(rb_cBignum, "remainder", rb_big_remainder, 1);
    rb_define_method(rb_cBignum, "fdiv", rb_big_fdiv, 1);
    rb_define_method(rb_cBignum, "**", rb_big_pow, 1);
    rb_define_method(rb_cBignum, "&", rb_big_and, 1);
    rb_define_method(rb_cBignum, "|", rb_big_or, 1);
    rb_define_method(rb_cBignum, "^", rb_big_xor, 1);
    rb_define_method(rb_cBignum, "~", rb_big_neg, 0);
    rb_define_method(rb_cBignum, "<<", rb_big_lshift, 1);
    rb_define_method(rb_cBignum, ">>", rb_big_rshift, 1);
    rb_define_method(rb_cBignum, "[]", rb_big_aref, 1);

    rb_define_method(rb_cBignum, "<=>", rb_big_cmp, 1);
    rb_define_method(rb_cBignum, "==", rb_big_eq, 1);
    rb_define_method(rb_cBignum, ">", big_gt, 1);
    rb_define_method(rb_cBignum, ">=", big_ge, 1);
    rb_define_method(rb_cBignum, "<", big_lt, 1);
    rb_define_method(rb_cBignum, "<=", big_le, 1);
    rb_define_method(rb_cBignum, "===", rb_big_eq, 1);
    rb_define_method(rb_cBignum, "eql?", rb_big_eql, 1);
    rb_define_method(rb_cBignum, "hash", rb_big_hash, 0);
    rb_define_method(rb_cBignum, "to_f", rb_big_to_f, 0);
    rb_define_method(rb_cBignum, "abs", rb_big_abs, 0);
    rb_define_method(rb_cBignum, "magnitude", rb_big_abs, 0);
    rb_define_method(rb_cBignum, "size", rb_big_size, 0);
    rb_define_method(rb_cBignum, "odd?", rb_big_odd_p, 0);
    rb_define_method(rb_cBignum, "even?", rb_big_even_p, 0);

    power_cache_init();

    big_three = rb_uint2big(3);
    rb_gc_register_mark_object(big_three);
}
