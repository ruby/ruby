#ifndef RBIMPL_ARITHMETIC_LEN_T_H                    /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_ARITHMETIC_LEN_T_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Arithmetic conversion between ::rb_len_t and Ruby's.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/arithmetic/long_long.h"
#include "ruby/internal/assume.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/value.h"

#define FIX2LEN    RB_FIX2LEN             /**< @old{RB_FIX2LEN} */
#define FIX2ULEN   RB_FIX2ULEN            /**< @old{RB_FIX2ULEN} */
#define LEN2FIX    RB_LEN2FIX             /**< @old{RB_LEN2FIX} */
#define LEN2NUM    RB_LEN2NUM             /**< @old{RB_LEN2NUM} */
#define NUM2LEN    RB_NUM2LEN             /**< @old{RB_NUM2LEN} */
#define ULEN2NUM   RB_ULEN2NUM            /**< @old{RB_ULEN2NUM} */
#define NUM2ULEN   RB_NUM2ULEN            /**< @old{RB_NUM2ULEN} */
#define rb_len2int rb_len2int_inline      /**< @alias{rb_len2int_inline} */
#define rb_len2long rb_len2long_inline    /**< @alias{rb_len2long_inline} */

#if SIZEOF_RB_LEN_T > SIZEOF_LONG
# define RB_LEN2NUM RB_LL2NUM
# define RB_NUM2LEN RB_NUM2LL
# define RB_ULEN2NUM RB_ULL2NUM
# define RB_NUM2ULEN RB_NUM2ULL
#else
/** Converts a ::rb_len_t into an instance of ::rb_cInteger. */
# define RB_LEN2NUM RB_LONG2NUM

/** Converts an instance of ::rb_cNumeric into ::rb_len_t. */
# define RB_NUM2LEN RB_NUM2LONG

/** Converts a ::rb_ulen_t into an instance of ::rb_cInteger. */
# define RB_ULEN2NUM RB_ULONG2NUM

/** Converts an instance of ::rb_cNumeric into ::rb_len_t. */
# define RB_NUM2ULEN RB_NUM2ULONG
#endif

#define RB_FIX2LEN rb_fix2len
#define RB_FIX2ULEN rb_fix2ulen

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Converts a `rb_len_t` into an instance of ::rb_cInteger.
 *
 * @param[in]  i  FIXABLE `rb_len_t` value.
 * @return     An instance of ::rb_cInteger.
 * @note       Higher bit of i can be silently lost if not in Fixable range.
 */
static inline VALUE
rb_len2fix(rb_len_t i)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FIXABLE(i));

    /* :NOTE: rb_ulen_t should be same as VALUE. */
    const rb_ulen_t     j = RBIMPL_CAST((rb_ulen_t)i);
    const rb_ulen_t     k = (j << 1) + RUBY_FIXNUM_FLAG;
    const rb_len_t      l = RBIMPL_CAST((rb_len_t)k);
    const SIGNED_VALUE  m = l; /* Sign extend */
    const VALUE         n = RBIMPL_CAST((VALUE)m);

    RBIMPL_ASSERT_OR_ASSUME(RB_FIXNUM_P(n));
    return n;
}

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
RBIMPL_ATTR_ARTIFICIAL()
/**
 * Converts a C's `long` into an instance of ::rb_cInteger.
 *
 * @param[in]  i  Arbitrary `long` value.
 * @return     An instance of ::rb_cInteger.
 */
static inline VALUE
RB_INT2FIX(long i)
{
    return rb_len2fix(i);
}

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
/**
 * @private
 *
 * This  is an  implementation detail  of rb_fix2len().   People don't  use it
 * directly.
 *
 * @param[in]  x  A Fixnum.
 * @return     Identical value of type `rb_len_t`
 * @pre        Must not pass anything other than a Fixnum.
 */
static inline rb_len_t
rbimpl_fix2len_by_idiv(VALUE x)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FIXNUM_P(x));

    /* :NOTE: VALUE should be same size as `rb_len_t`.  (x-1)/2 never overflows
     * because RB_FIXNUM_P(x) holds.  Also it has no portability issue like
     * y>>1 below. */
    const SIGNED_VALUE y = RBIMPL_CAST((SIGNED_VALUE)(x - RUBY_FIXNUM_FLAG));
    const SIGNED_VALUE z = y / 2;
    const rb_len_t     w = RBIMPL_CAST((rb_len_t)z);

    RBIMPL_ASSERT_OR_ASSUME(RB_FIXABLE(w));
    return w;
}

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
/**
 * @private
 *
 * This  is an  implementation detail  of rb_fix2len().   People don't  use it
 * directly.
 *
 * @param[in]  x  A Fixnum.
 * @return     Identical value of type `rb_len_t`
 * @pre        Must not pass anything other than a Fixnum.
 */
static inline rb_len_t
rbimpl_fix2len_by_shift(VALUE x)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FIXNUM_P(x));

    /* :NOTE:  VALUE should  be same  size as  `rb_len_t`.  If  right shift  is
     * arithmetic, this is noticeably faster than above. */
    const SIGNED_VALUE y = RBIMPL_CAST((SIGNED_VALUE)x);
    const SIGNED_VALUE z = y >> 1;
    const rb_len_t     w = RBIMPL_CAST((rb_len_t)z);

    RBIMPL_ASSERT_OR_ASSUME(RB_FIXABLE(w));
    return w;
}

/**
 * @private
 *
 * This  is an  implementation detail  of rb_fix2len().   People don't  use it
 * directly.
 *
 * true   This C compiler's right shift operator is arithmetic.
 * false  This C compiler's right shift operator is logical.
 */
static const bool rbimpl_right_shift_is_arithmetic_p = (-1 >> 1) == -1;

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
/**
 * Converts a Fixnum into `rb_len_t`.
 *
 * @param[in]  x  Some Fixnum.
 * @pre        Must not pass anything other than a Fixnum.
 * @return     The passed value converted into `rb_len_t`.
 */
static inline rb_len_t
rb_fix2len(VALUE x)
{
    if /* constexpr */ (rbimpl_right_shift_is_arithmetic_p) {
        return rbimpl_fix2len_by_shift(x);
    }
    else {
        return rbimpl_fix2len_by_idiv(x);
    }
}

RBIMPL_ATTR_CONST_UNLESS_DEBUG()
RBIMPL_ATTR_CONSTEXPR_UNLESS_DEBUG(CXX14)
/**
 * Converts a Fixnum into `rb_ulen_t`.
 *
 * @param[in]  x  Some Fixnum.
 * @pre        Must not pass anything other than a Fixnum.
 * @return     The passed value converted into `rb_ulen_t`.
 * @note       Negative fixnums will be converted into large `rb_ulen_t`.
 */
static inline rb_ulen_t
rb_fix2ulen(VALUE x)
{
    RBIMPL_ASSERT_OR_ASSUME(RB_FIXNUM_P(x));
    return RBIMPL_CAST((rb_ulen_t)rb_fix2len(x));
}

/**
 * Checks if `int` can hold the given integer.
 *
 * @param[in]  n               Arbitrary ::rb_len_t value.
 * @exception  rb_eRangeError  `n` is out of range of `int`.
 * @return     Identical value of type `int`
 */
static inline int
rb_len2int_inline(rb_len_t n)
{
    int i = RBIMPL_CAST((int)n);

    if /* constexpr */ (sizeof(rb_len_t) <= sizeof(int)) {
        RBIMPL_ASSUME(i == n);
    }

    if (i != n)
        rb_out_of_int(n);

    return i;
}

/**
 * Checks if `long` can hold the given integer.
 *
 * @param[in]  n               Arbitrary ::rb_len_t value.
 * @exception  rb_eRangeError  `n` is out of range of `long`.
 * @return     Identical value of type `long`
 */
static inline long
rb_len2long_inline(rb_len_t n)
{
    long l = RBIMPL_CAST((long)n);

    if /* constexpr */ (sizeof(rb_len_t) <= sizeof(long)) {
        RBIMPL_ASSUME(l == n);
    }

    if (l != n)
        rb_out_of_long(n);

    return l;
}

/**
 * Converts a Fixnum into C's `long`.
 *
 * @param[in]  x  Some Fixnum.
 * @pre        Must not pass anything other than a Fixnum.
 * @return     The passed value converted into C's `long`.
 */
static inline long
rb_fix2long(VALUE x)
{
    return rb_len2long(rb_fix2len(x));
}

/**
 * Converts a Fixnum into C's `unsigned long`.
 *
 * @param[in]  x  Some Fixnum.
 * @pre        Must not pass anything other than a Fixnum.
 * @return     The passed value converted into C's `unsigned long`.
 * @note       Negative fixnums will be converted into large unsigned longs.
 */
static inline unsigned long
rb_fix2ulong(VALUE x)
{
    return RBIMPL_CAST((unsigned long)rb_fix2ulen(x));
}

#endif /* RBIMPL_ARITHMETIC_LEN_T_H */
