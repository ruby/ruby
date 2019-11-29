#ifndef INTERNAL_BITS_H /* -*- C -*- */
#define INTERNAL_BITS_H
/**
 * @file
 * @brief      Internal header for bitwise integer algorithms.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* The most significant bit of the lower part of half-long integer.
 * If sizeof(long) == 4, this is 0x8000.
 * If sizeof(long) == 8, this is 0x80000000.
 */
#define HALF_LONG_MSB ((SIGNED_VALUE)1<<((SIZEOF_LONG*CHAR_BIT-1)/2))

#define SIGNED_INTEGER_TYPE_P(int_type) (0 > ((int_type)0)-1)
#define SIGNED_INTEGER_MAX(sint_type) \
  (sint_type) \
  ((((sint_type)1) << (sizeof(sint_type) * CHAR_BIT - 2)) | \
  ((((sint_type)1) << (sizeof(sint_type) * CHAR_BIT - 2)) - 1))
#define SIGNED_INTEGER_MIN(sint_type) (-SIGNED_INTEGER_MAX(sint_type)-1)
#define UNSIGNED_INTEGER_MAX(uint_type) (~(uint_type)0)
#ifdef HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW_P
#define MUL_OVERFLOW_P(a, b) \
    __builtin_mul_overflow_p((a), (b), (__typeof__(a * b))0)
#elif defined HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW
#define MUL_OVERFLOW_P(a, b) \
    RB_GNUC_EXTENSION_BLOCK(__typeof__(a) c; __builtin_mul_overflow((a), (b), &c))
#endif

#define MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, min, max) ( \
    (a) == 0 ? 0 : \
    (a) == -1 ? (b) < -(max) : \
    (a) > 0 ? \
      ((b) > 0 ? (max) / (a) < (b) : (min) / (a) > (b)) : \
      ((b) > 0 ? (min) / (a) < (b) : (max) / (a) > (b)))

#ifdef HAVE_BUILTIN___BUILTIN_MUL_OVERFLOW_P
/* __builtin_mul_overflow_p can take bitfield */
/* and GCC permits bitfields for integers other than int */
#define MUL_OVERFLOW_FIXNUM_P(a, b) RB_GNUC_EXTENSION_BLOCK( \
    struct { long fixnum : SIZEOF_LONG * CHAR_BIT - 1; } c; \
    __builtin_mul_overflow_p((a), (b), c.fixnum); \
)
#else
#define MUL_OVERFLOW_FIXNUM_P(a, b) MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, FIXNUM_MIN, FIXNUM_MAX)
#endif

#ifdef MUL_OVERFLOW_P
#define MUL_OVERFLOW_LONG_LONG_P(a, b) MUL_OVERFLOW_P(a, b)
#define MUL_OVERFLOW_LONG_P(a, b)      MUL_OVERFLOW_P(a, b)
#define MUL_OVERFLOW_INT_P(a, b)       MUL_OVERFLOW_P(a, b)
#else
#define MUL_OVERFLOW_LONG_LONG_P(a, b) MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, LLONG_MIN, LLONG_MAX)
#define MUL_OVERFLOW_LONG_P(a, b)      MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, LONG_MIN, LONG_MAX)
#define MUL_OVERFLOW_INT_P(a, b)       MUL_OVERFLOW_SIGNED_INTEGER_P(a, b, INT_MIN, INT_MAX)
#endif

#ifndef swap16
# ifdef HAVE_BUILTIN___BUILTIN_BSWAP16
#  define swap16(x) __builtin_bswap16(x)
# endif
#endif

#ifndef swap16
# define swap16(x)      ((uint16_t)((((x)&0xFF)<<8) | (((x)>>8)&0xFF)))
#endif

#ifndef swap32
# ifdef HAVE_BUILTIN___BUILTIN_BSWAP32
#  define swap32(x) __builtin_bswap32(x)
# endif
#endif

#ifndef swap32
# define swap32(x)      ((uint32_t)((((x)&0xFF)<<24)    \
                        |(((x)>>24)&0xFF)       \
                        |(((x)&0x0000FF00)<<8)  \
                        |(((x)&0x00FF0000)>>8)  ))
#endif

#ifndef swap64
# ifdef HAVE_BUILTIN___BUILTIN_BSWAP64
#  define swap64(x) __builtin_bswap64(x)
# endif
#endif

#ifndef swap64
# ifdef HAVE_INT64_T
#  define byte_in_64bit(n) ((uint64_t)0xff << (n))
#  define swap64(x)       ((uint64_t)((((x)&byte_in_64bit(0))<<56)      \
                           |(((x)>>56)&0xFF)                    \
                           |(((x)&byte_in_64bit(8))<<40)        \
                           |(((x)&byte_in_64bit(48))>>40)       \
                           |(((x)&byte_in_64bit(16))<<24)       \
                           |(((x)&byte_in_64bit(40))>>24)       \
                           |(((x)&byte_in_64bit(24))<<8)        \
                           |(((x)&byte_in_64bit(32))>>8)))
# endif
#endif

static inline unsigned int
nlz_int(unsigned int x)
{
#if defined(HAVE_BUILTIN___BUILTIN_CLZ)
    if (x == 0) return SIZEOF_INT * CHAR_BIT;
    return (unsigned int)__builtin_clz(x);
#else
    unsigned int y;
# if 64 < SIZEOF_INT * CHAR_BIT
    unsigned int n = 128;
# elif 32 < SIZEOF_INT * CHAR_BIT
    unsigned int n = 64;
# else
    unsigned int n = 32;
# endif
# if 64 < SIZEOF_INT * CHAR_BIT
    y = x >> 64; if (y) {n -= 64; x = y;}
# endif
# if 32 < SIZEOF_INT * CHAR_BIT
    y = x >> 32; if (y) {n -= 32; x = y;}
# endif
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (unsigned int)(n - x);
#endif
}

static inline unsigned int
nlz_long(unsigned long x)
{
#if defined(HAVE_BUILTIN___BUILTIN_CLZL)
    if (x == 0) return SIZEOF_LONG * CHAR_BIT;
    return (unsigned int)__builtin_clzl(x);
#else
    unsigned long y;
# if 64 < SIZEOF_LONG * CHAR_BIT
    unsigned int n = 128;
# elif 32 < SIZEOF_LONG * CHAR_BIT
    unsigned int n = 64;
# else
    unsigned int n = 32;
# endif
# if 64 < SIZEOF_LONG * CHAR_BIT
    y = x >> 64; if (y) {n -= 64; x = y;}
# endif
# if 32 < SIZEOF_LONG * CHAR_BIT
    y = x >> 32; if (y) {n -= 32; x = y;}
# endif
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (unsigned int)(n - x);
#endif
}

#ifdef HAVE_LONG_LONG
static inline unsigned int
nlz_long_long(unsigned LONG_LONG x)
{
#if defined(HAVE_BUILTIN___BUILTIN_CLZLL)
    if (x == 0) return SIZEOF_LONG_LONG * CHAR_BIT;
    return (unsigned int)__builtin_clzll(x);
#else
    unsigned LONG_LONG y;
# if 64 < SIZEOF_LONG_LONG * CHAR_BIT
    unsigned int n = 128;
# elif 32 < SIZEOF_LONG_LONG * CHAR_BIT
    unsigned int n = 64;
# else
    unsigned int n = 32;
# endif
# if 64 < SIZEOF_LONG_LONG * CHAR_BIT
    y = x >> 64; if (y) {n -= 64; x = y;}
# endif
# if 32 < SIZEOF_LONG_LONG * CHAR_BIT
    y = x >> 32; if (y) {n -= 32; x = y;}
# endif
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (unsigned int)(n - x);
#endif
}
#endif

#ifdef HAVE_UINT128_T
static inline unsigned int
nlz_int128(uint128_t x)
{
    uint128_t y;
    unsigned int n = 128;
    y = x >> 64; if (y) {n -= 64; x = y;}
    y = x >> 32; if (y) {n -= 32; x = y;}
    y = x >> 16; if (y) {n -= 16; x = y;}
    y = x >>  8; if (y) {n -=  8; x = y;}
    y = x >>  4; if (y) {n -=  4; x = y;}
    y = x >>  2; if (y) {n -=  2; x = y;}
    y = x >>  1; if (y) {return n - 2;}
    return (unsigned int)(n - x);
}
#endif

static inline unsigned int
nlz_intptr(uintptr_t x)
{
#if SIZEOF_UINTPTR_T == SIZEOF_INT
    return nlz_int(x);
#elif SIZEOF_UINTPTR_T == SIZEOF_LONG
    return nlz_long(x);
#elif SIZEOF_UINTPTR_T == SIZEOF_LONG_LONG
    return nlz_long_long(x);
#else
    #error no known integer type corresponds uintptr_t
    return /* sane compiler */ ~0;
#endif
}

static inline unsigned int
rb_popcount32(uint32_t x)
{
#ifdef HAVE_BUILTIN___BUILTIN_POPCOUNT
    return (unsigned int)__builtin_popcount(x);
#else
    x = (x & 0x55555555) + (x >> 1 & 0x55555555);
    x = (x & 0x33333333) + (x >> 2 & 0x33333333);
    x = (x & 0x0f0f0f0f) + (x >> 4 & 0x0f0f0f0f);
    x = (x & 0x001f001f) + (x >> 8 & 0x001f001f);
    return (x & 0x0000003f) + (x >>16 & 0x0000003f);
#endif
}

static inline int
rb_popcount64(uint64_t x)
{
#ifdef HAVE_BUILTIN___BUILTIN_POPCOUNT
    return __builtin_popcountll(x);
#else
    x = (x & 0x5555555555555555) + (x >> 1 & 0x5555555555555555);
    x = (x & 0x3333333333333333) + (x >> 2 & 0x3333333333333333);
    x = (x & 0x0707070707070707) + (x >> 4 & 0x0707070707070707);
    x = (x & 0x001f001f001f001f) + (x >> 8 & 0x001f001f001f001f);
    x = (x & 0x0000003f0000003f) + (x >>16 & 0x0000003f0000003f);
    return (x & 0x7f) + (x >>32 & 0x7f);
#endif
}

static inline int
rb_popcount_intptr(uintptr_t x)
{
#if SIZEOF_VOIDP == 8
    return rb_popcount64(x);
#elif SIZEOF_VOIDP == 4
    return rb_popcount32(x);
#endif
}

static inline int
ntz_int32(uint32_t x)
{
#ifdef HAVE_BUILTIN___BUILTIN_CTZ
    return __builtin_ctz(x);
#else
    return rb_popcount32((~x) & (x-1));
#endif
}

static inline int
ntz_int64(uint64_t x)
{
#ifdef HAVE_BUILTIN___BUILTIN_CTZLL
    return __builtin_ctzll(x);
#else
    return rb_popcount64((~x) & (x-1));
#endif
}

static inline int
ntz_intptr(uintptr_t x)
{
#if SIZEOF_VOIDP == 8
    return ntz_int64(x);
#elif SIZEOF_VOIDP == 4
    return ntz_int32(x);
#endif
}

#if defined(HAVE_UINT128_T) && defined(HAVE_LONG_LONG)
#   define bit_length(x) \
    (unsigned int) \
    (sizeof(x) <= SIZEOF_INT ? SIZEOF_INT * CHAR_BIT - nlz_int((unsigned int)(x)) : \
     sizeof(x) <= SIZEOF_LONG ? SIZEOF_LONG * CHAR_BIT - nlz_long((unsigned long)(x)) : \
     sizeof(x) <= SIZEOF_LONG_LONG ? SIZEOF_LONG_LONG * CHAR_BIT - nlz_long_long((unsigned LONG_LONG)(x)) : \
     SIZEOF_INT128_T * CHAR_BIT - nlz_int128((uint128_t)(x)))
#elif defined(HAVE_UINT128_T)
#   define bit_length(x) \
    (unsigned int) \
    (sizeof(x) <= SIZEOF_INT ? SIZEOF_INT * CHAR_BIT - nlz_int((unsigned int)(x)) : \
     sizeof(x) <= SIZEOF_LONG ? SIZEOF_LONG * CHAR_BIT - nlz_long((unsigned long)(x)) : \
     SIZEOF_INT128_T * CHAR_BIT - nlz_int128((uint128_t)(x)))
#elif defined(HAVE_LONG_LONG)
#   define bit_length(x) \
    (unsigned int) \
    (sizeof(x) <= SIZEOF_INT ? SIZEOF_INT * CHAR_BIT - nlz_int((unsigned int)(x)) : \
     sizeof(x) <= SIZEOF_LONG ? SIZEOF_LONG * CHAR_BIT - nlz_long((unsigned long)(x)) : \
     SIZEOF_LONG_LONG * CHAR_BIT - nlz_long_long((unsigned LONG_LONG)(x)))
#else
#   define bit_length(x) \
    (unsigned int) \
    (sizeof(x) <= SIZEOF_INT ? SIZEOF_INT * CHAR_BIT - nlz_int((unsigned int)(x)) : \
     SIZEOF_LONG * CHAR_BIT - nlz_long((unsigned long)(x)))
#endif

#if USE_FLONUM
#define RUBY_BIT_ROTL(v, n) (((v) << (n)) | ((v) >> ((sizeof(v) * 8) - n)))
#define RUBY_BIT_ROTR(v, n) (((v) >> (n)) | ((v) << ((sizeof(v) * 8) - n)))
#endif
#endif /* INTERNAL_BITS_H */
