#ifndef INTERNAL_SORT_H                                  /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_SORT_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for sorting by numeric keys.
 */
#include "ruby/internal/config.h"
#include <limits.h>             /* for CHAR_BIT */
#include "internal/numeric.h"   /* for rb_float_value */
#include "ruby/ruby.h"          /* for VALUE and rb_len_t */

/*
 * Sorting by numeric keys without calling <=>.
 *
 * Fixnums and Floats can be ordered by their VALUEs alone, so the
 * comparison is inlined and no method is called during the sort.  The
 * caller must make sure that every key is of the given kind, and that
 * <=> of Integer and of Float are not redefined.
 *
 * The algorithm follows pattern-defeating quicksort by Orson Peters
 * (https://github.com/orlp/pdqsort), with a branchless partition:
 *
 * - when many elements are equal to the pivot, they are gathered and
 *   left out of the rest of the sort;
 * - after an unbalanced partition, the elements to be sampled for the
 *   next pivots are swapped with others;
 * - when a partition moved nothing, both parts are tried with an
 *   insertion sort that gives up early;
 * - and after too many unbalanced partitions, the part is sorted by
 *   heapsort, so that the worst case is O(n log n).
 *
 * The sort is not stable.
 *
 * rb_numsort() is meant to be inlined into a function for each kind of
 * keys and each width of elements, which must be compile time constants.
 */

enum rb_numsort_kind {
    RB_NUMSORT_FIXNUM,          /* Fixnums only */
    RB_NUMSORT_FLONUM,          /* flonums only */
    RB_NUMSORT_FLOAT,           /* Floats other than NaN */
    RB_NUMSORT_FIXNUM_OR_FLOAT  /* Fixnums, and Floats other than NaN */
};

/* A part of this size or less is sorted by insertion sort. */
#define NUMSORT_INSERTION_MAX 24

/* A part of this size or more has its pivot chosen from nine samples. */
#define NUMSORT_NINTHER_MIN 48

/* A part of this size or more is checked if it is partitioned already. */
#define NUMSORT_PARTITIONED_CHECK_MIN 128

/* The insertion sort that may give up does so over this many moves. */
#define NUMSORT_PARTIAL_INSERTION_MAX 8

/*
 * Exact comparisons of the value of a Fixnum and a double other than
 * NaN.  The conversion to double is monotonic, so the converted values
 * are in the same order as the originals unless they are equal; and if
 * they are equal, the double is integral and fits in long.
 */
static inline int
numsort_long_lt_dbl(long n, double d)
{
    const double dn = (double)n;
    return dn < d || (dn == d && n < (long)d);
}

static inline int
numsort_dbl_lt_long(double d, long n)
{
    const double dn = (double)n;
    return d < dn || (d == dn && (long)d < n);
}

ALWAYS_INLINE(static int numsort_lt(VALUE a, VALUE b,
                                    const enum rb_numsort_kind kind));
static inline int
numsort_lt(VALUE a, VALUE b, const enum rb_numsort_kind kind)
{
    switch (kind) {
      case RB_NUMSORT_FIXNUM:
        return (SIGNED_VALUE)a < (SIGNED_VALUE)b;
      case RB_NUMSORT_FLONUM:
        return rb_float_flonum_value(a) < rb_float_flonum_value(b);
      case RB_NUMSORT_FLOAT:
        return rb_float_value(a) < rb_float_value(b);
      case RB_NUMSORT_FIXNUM_OR_FLOAT:
        if (FIXNUM_P(a)) {
            if (FIXNUM_P(b)) return (SIGNED_VALUE)a < (SIGNED_VALUE)b;
            return numsort_long_lt_dbl(FIX2LONG(a), rb_float_value(b));
        }
        if (FIXNUM_P(b)) {
            return numsort_dbl_lt_long(rb_float_value(a), FIX2LONG(b));
        }
        return rb_float_value(a) < rb_float_value(b);
    }
    UNREACHABLE_RETURN(0);
}

/* An element is +w+ VALUEs wide, 1 or 2, and its first VALUE is the key. */
ALWAYS_INLINE(static void numsort_move(VALUE *dst, const VALUE *src,
                                       const int w));
static inline void
numsort_move(VALUE *dst, const VALUE *src, const int w)
{
    dst[0] = src[0];
    if (w > 1) dst[1] = src[1];
}

ALWAYS_INLINE(static void numsort_swap(VALUE *a, VALUE *b, const int w));
static inline void
numsort_swap(VALUE *a, VALUE *b, const int w)
{
    VALUE x[2];
    numsort_move(x, a, w);
    numsort_move(a, b, w);
    numsort_move(b, x, w);
}

ALWAYS_INLINE(static VALUE *numsort_med3(VALUE *a, VALUE *b, VALUE *c,
                                         const enum rb_numsort_kind kind));
static inline VALUE *
numsort_med3(VALUE *a, VALUE *b, VALUE *c, const enum rb_numsort_kind kind)
{
    if (numsort_lt(*b, *a, kind)) {
        VALUE *t = a;
        a = b;
        b = t;
    }
    if (numsort_lt(*c, *b, kind)) {
        b = numsort_lt(*c, *a, kind) ? a : c;
    }
    return b;
}

ALWAYS_INLINE(static void numsort_insertion(VALUE *p, rb_len_t n,
                                            const enum rb_numsort_kind kind,
                                            const int w));
static inline void
numsort_insertion(VALUE *p, rb_len_t n, const enum rb_numsort_kind kind,
                  const int w)
{
    VALUE *const end = p + n * w, *i, *j;

    for (i = p + w; i < end; i += w) {
        VALUE x[2];
        numsort_move(x, i, w);
        for (j = i; j > p && numsort_lt(x[0], j[-w], kind); j -= w) {
            numsort_move(j, j - w, w);
        }
        numsort_move(j, x, w);
    }
}

/*
 * Insertion sort that gives up when it has moved the elements more than
 * NUMSORT_PARTIAL_INSERTION_MAX times.  Returns whether it finished.
 */
ALWAYS_INLINE(static bool
              numsort_partial_insertion(VALUE *p, rb_len_t n,
                                        const enum rb_numsort_kind kind,
                                        const int w));
static inline bool
numsort_partial_insertion(VALUE *p, rb_len_t n,
                          const enum rb_numsort_kind kind, const int w)
{
    VALUE *const end = p + n * w, *i, *j;
    rb_len_t moved = 0;

    for (i = p + w; i < end; i += w) {
        if (numsort_lt(i[0], i[-w], kind)) {
            VALUE x[2];
            numsort_move(x, i, w);
            j = i;
            do {
                numsort_move(j, j - w, w);
                j -= w;
            } while (j > p && numsort_lt(x[0], j[-w], kind));
            numsort_move(j, x, w);
            moved += (i - j) / w;
            if (moved > NUMSORT_PARTIAL_INSERTION_MAX) return false;
        }
    }
    return true;
}

/*
 * Swaps the elements that numsort_med3() would sample for the next
 * pivot with others, so that the pattern which led to an unbalanced
 * partition is not followed again.  +n+ must be greater than
 * NUMSORT_INSERTION_MAX.
 */
ALWAYS_INLINE(static void numsort_break_pattern(VALUE *p, rb_len_t n,
                                                const int w));
static inline void
numsort_break_pattern(VALUE *p, rb_len_t n, const int w)
{
    VALUE *const last = p + (n - 1) * w;

    if (n >= NUMSORT_NINTHER_MIN) {
        const rb_len_t s = (n / 8) * w, t = (n / 16) * w;
        numsort_swap(p, p + 3 * t, w);
        numsort_swap(p + s, p + 5 * t, w);
        numsort_swap(last, last - 3 * t, w);
        numsort_swap(last - s, last - 5 * t, w);
    }
    else {
        const rb_len_t t = (n / 4) * w;
        numsort_swap(p, p + t, w);
        numsort_swap(last, last - t, w);
    }
}

ALWAYS_INLINE(static void numsort_heap_sift(VALUE *p, rb_len_t root, rb_len_t n,
                                            const enum rb_numsort_kind kind,
                                            const int w));
static inline void
numsort_heap_sift(VALUE *p, rb_len_t root, rb_len_t n,
                  const enum rb_numsort_kind kind, const int w)
{
    VALUE x[2];
    rb_len_t child;

    numsort_move(x, p + root * w, w);
    while ((child = 2 * root + 1) < n) {
        if (child + 1 < n &&
            numsort_lt(p[child * w], p[(child + 1) * w], kind)) {
            child++;
        }
        if (!numsort_lt(x[0], p[child * w], kind)) break;
        numsort_move(p + root * w, p + child * w, w);
        root = child;
    }
    numsort_move(p + root * w, x, w);
}

ALWAYS_INLINE(static void numsort_heap(VALUE *p, rb_len_t n,
                                       const enum rb_numsort_kind kind,
                                       const int w));
static inline void
numsort_heap(VALUE *p, rb_len_t n, const enum rb_numsort_kind kind,
             const int w)
{
    rb_len_t i;

    for (i = n / 2; i-- > 0; ) {
        numsort_heap_sift(p, i, n, kind, w);
    }
    for (i = n; --i > 0; ) {
        numsort_swap(p, p + i * w, w);
        numsort_heap_sift(p, 0, i, kind, w);
    }
}

/*
 * Sorts +len+ elements at +base+ by their keys of +kind+.  Each element
 * is +w+ VALUEs wide and its first VALUE is the key.  +len+ must be 2 or
 * more.
 */
ALWAYS_INLINE(static void rb_numsort(VALUE *const base, const rb_len_t len,
                                     const enum rb_numsort_kind kind,
                                     const int w));
static inline void
rb_numsort(VALUE *const base, const rb_len_t len,
           const enum rb_numsort_kind kind, const int w)
{
    struct {
        VALUE *lo, *hi;
        int limit;
    } stack[sizeof(rb_len_t) * CHAR_BIT], *sp = stack;
    VALUE *const end = base + len * w;
    VALUE *lo = base, *hi = end; /* sorts [lo, hi) */
    VALUE *p, *q, *r;
    int limit = 0; /* unbalanced partitions to tolerate before heapsort */
    rb_len_t i;

    /* nothing to do if sorted already, and only to reverse if reversed */
    p = base + 2 * w;
    if (numsort_lt(base[w], base[0], kind)) {
        while (p < end && !numsort_lt(p[-w], p[0], kind)) p += w;
        if (p == end) {
            for (p = base, q = end - w; p < q; p += w, q -= w) {
                numsort_swap(p, q, w);
            }
            return;
        }
    }
    else {
        while (p < end && !numsort_lt(p[0], p[-w], kind)) p += w;
        if (p == end) return;
    }

    for (i = len; i > 0; i >>= 1) limit++;

    for (;;) {
        const rb_len_t n = (hi - lo) / w;

        if (n <= NUMSORT_INSERTION_MAX) {
            numsort_insertion(lo, n, kind, w);
        }
        else if (limit == 0) {
            numsort_heap(lo, n, kind, w);
        }
        else {
            VALUE *mid = lo + (n / 2) * w, *const last = hi - w, pivot[2];
            rb_len_t nl, nr;
            bool partitioned = false;

            if (n >= NUMSORT_NINTHER_MIN) {
                const rb_len_t s = (n / 8) * w;
                VALUE *m1, *m2, *m3;
                m1 = numsort_med3(lo, lo + s, lo + 2 * s, kind);
                m2 = numsort_med3(mid - s, mid, mid + s, kind);
                m3 = numsort_med3(last - 2 * s, last - s, last, kind);
                mid = numsort_med3(m1, m2, m3, kind);
            }
            else {
                mid = numsort_med3(lo, mid, last, kind);
            }
            numsort_move(pivot, mid, w);
            numsort_move(mid, lo, w);
            numsort_move(lo, pivot, w);

            /*
             * lo[-w], if any, is already in place and nothing in
             * [lo, hi) is less than it.  If the pivot is not greater
             * than it either, the elements equal to the pivot are many;
             * gather them at the left, where they are in place.
             */
            if (lo > base && !numsort_lt(lo[-w], pivot[0], kind)) {
                for (p = q = lo + w; q < hi; q += w) {
                    VALUE x[2];
                    numsort_move(x, q, w);
                    numsort_move(q, p, w);
                    numsort_move(p, x, w);
                    p += w * !numsort_lt(pivot[0], x[0], kind);
                }
                lo = p;
                continue;
            }

            /*
             * Skip the elements at both ends that are placed already.
             * Where these loops end is hard to predict for the CPU,
             * which does not pay in a small part.
             */
            p = lo + w;
            q = last;
            if (n >= NUMSORT_PARTITIONED_CHECK_MIN) {
                while (p < hi && numsort_lt(p[0], pivot[0], kind)) p += w;
                while (q > lo && !numsort_lt(q[0], pivot[0], kind)) q -= w;
                partitioned = p > q;
            }

            /* [lo+w, p) < pivot <= [p, r) */
            for (r = p; r <= q; r += w) {
                VALUE x[2];
                numsort_move(x, r, w);
                numsort_move(r, p, w);
                numsort_move(p, x, w);
                p += w * numsort_lt(x[0], pivot[0], kind);
            }
            p -= w;
            numsort_move(lo, p, w);
            numsort_move(p, pivot, w);

            nl = (p - lo) / w;
            nr = (hi - (p + w)) / w;
            if ((nl < nr ? nl : nr) < n / 8) {
                limit--;
                if (nl > NUMSORT_INSERTION_MAX) {
                    numsort_break_pattern(lo, nl, w);
                }
                if (nr > NUMSORT_INSERTION_MAX) {
                    numsort_break_pattern(p + w, nr, w);
                }
            }
            else if (partitioned &&
                     numsort_partial_insertion(lo, nl, kind, w)) {
                /* nothing was moved, so the parts may be almost sorted */
                if (numsort_partial_insertion(p + w, nr, kind, w)) {
                    lo = hi;
                }
                else {
                    lo = p + w;
                }
                continue;
            }

            /* the smaller part goes first, to bound the stack depth */
            if (nl < nr) {
                sp->lo = p + w;
                sp->hi = hi;
                hi = p;
            }
            else {
                sp->lo = lo;
                sp->hi = p;
                lo = p + w;
            }
            sp->limit = limit;
            sp++;
            continue;
        }

        if (sp == stack) break;
        --sp;
        lo = sp->lo;
        hi = sp->hi;
        limit = sp->limit;
    }
}

#endif /* INTERNAL_SORT_H */
