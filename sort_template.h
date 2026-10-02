/**********************************************************************

  sort_template.h -

  Introsort, generic over the element type and the comparison.

  This is the sort that Enumerable#sort_by has used for uniform Fixnum
  and Float keys since [Feature #19643], lifted out of enum.c so that
  every core sort can share it.  Unlike qsort_r it allocates nothing, so
  a comparison that raises unwinds through it harmlessly.

  Include this file after defining:

    SORT_NAME             prefix for the generated functions
    SORT_ELEM             element type
    SORT_LESS(a, b, arg)  true when element a sorts before element b

  SORT_LESS need not be a consistent ordering: Array#sort hands it a block
  that may return anything at all.  The sort terminates and stays within
  the range whatever it answers, though of course the result is only
  sorted if it does describe an ordering.

  It defines

    static void SORT_NAME##_sort(SORT_ELEM *begin, SORT_ELEM *end, void *arg)

  and undefines the three inputs, so a translation unit may include it
  once per instantiation.  The comparison is expanded inline, which is
  the point: a sort reached through a function pointer cannot inline its
  comparison, and for Ruby's element types the comparison is most of the
  cost.

**********************************************************************/

#ifndef SORT_NAME
# error SORT_NAME must be defined before including sort_template.h
#endif
#ifndef SORT_ELEM
# error SORT_ELEM must be defined before including sort_template.h
#endif
#ifndef SORT_LESS
# error SORT_LESS must be defined before including sort_template.h
#endif

#define SORT_CAT1(x, y) x ## y
#define SORT_CAT(x, y) SORT_CAT1(x, y)
#define SORT_FUNC(suffix) SORT_CAT(SORT_NAME, suffix)

#define sort_less(a, b) SORT_LESS(a, b, arg)
#define sort_swap(a, b) do { \
    SORT_ELEM sort_swap_tmp = (a); (a) = (b); (b) = sort_swap_tmp; \
} while (0)
/* Median of the three elements pointed at, as a pointer to one of them. */
#define sort_med3(a, b, c) (sort_less(*(a), *(b)) ? \
                            (sort_less(*(b), *(c)) ? (b) : sort_less(*(c), *(a)) ? (a) : (c)) : \
                            (sort_less(*(c), *(b)) ? (b) : sort_less(*(a), *(c)) ? (a) : (c)))

/* Threshold below which insertion sort beats partitioning. */
#define SORT_INSERTION_MAX 16

/* Array#sort lets the block return anything it likes, so SORT_LESS need not be
 * a consistent ordering and the pivot cannot be relied on to stop a partition
 * scan.  Every scan below is bounded instead.  A separate unbounded variant for
 * the comparisons Ruby controls measured about 1% faster, which is not worth a
 * second path through the partition that no test for a lying comparator
 * reaches. */

static void
SORT_FUNC(_insertion_sort)(SORT_ELEM *begin, SORT_ELEM *end, void *arg)
{
    for (SORT_ELEM *index = begin + 1; index < end; index++) {
        SORT_ELEM tmp = *index;
        SORT_ELEM *j = index;
        while (j > begin && sort_less(tmp, j[-1])) {
            *j = j[-1];
            j--;
        }
        *j = tmp;
    }
}

static inline void
SORT_FUNC(_heap_down)(SORT_ELEM *begin, size_t offset, size_t len, void *arg)
{
    size_t c;
    SORT_ELEM tmp = begin[offset];
    while ((c = (offset << 1) + 1) <= len) {
        if (c < len && sort_less(begin[c], begin[c+1])) {
            c++;
        }
        if (!sort_less(tmp, begin[c])) break;
        begin[offset] = begin[c];
        offset = c;
    }
    begin[offset] = tmp;
}

static void
SORT_FUNC(_heap_sort)(SORT_ELEM *begin, SORT_ELEM *end, void *arg)
{
    size_t n = end - begin;
    if (n < 2) return;

    for (size_t offset = n >> 1; offset > 0;) {
        SORT_FUNC(_heap_down)(begin, --offset, n-1, arg);
    }
    for (size_t offset = n-1; offset > 0;) {
        sort_swap(*begin, begin[offset]);
        SORT_FUNC(_heap_down)(begin, 0, --offset, arg);
    }
}

static void
SORT_FUNC(_quick_sort)(SORT_ELEM *begin, SORT_ELEM *end, size_t d, void *arg)
{
    if (end - begin <= SORT_INSERTION_MAX) {
        SORT_FUNC(_insertion_sort)(begin, end, arg);
        return;
    }
    if (d == 0) {
        /* Partitioning has gone quadratic; fall back to guaranteed O(n log n). */
        SORT_FUNC(_heap_sort)(begin, end, arg);
        return;
    }

    /* Pivot selection, widening with the range exactly as ruby_qsort does in
     * util.c.  Median of three is not enough: on input made of a few ascending
     * runs it keeps choosing a near-minimum, and on random input the resulting
     * imbalance costs comparisons, which is the whole budget when the
     * comparison is a Ruby call. */
    size_t n = end - begin;
    SORT_ELEM *m = begin + (n >> 1);
    SORT_ELEM *lo, *hi;

    if (n >= 200) {
        size_t s = n >> 3;
        lo = sort_med3(begin + s, begin + 2*s, begin + 3*s);
        hi = sort_med3(m + s, m + 2*s, m + 3*s);
    }
    else if (n >= 60) {
        size_t s = n >> 2;
        lo = begin + s;
        hi = m + s;
    }
    else {
        lo = begin;
        hi = end - 1;
    }

    SORT_ELEM x = *sort_med3(lo, m, hi);
    SORT_ELEM *i = begin;
    SORT_ELEM *j = end - 1;

    do {
        while (i < end - 1 && sort_less(*i, x)) i++;
        while (j > begin && sort_less(x, *j)) j--;
        if (i <= j) {
            sort_swap(*i, *j);
            i++;
            j--;
        }
    } while (i <= j);
    j++;

    /* A consistent comparison leaves the two halves covering the range with at
     * most one element of overlap.  More than that means the comparison is not
     * an ordering, and recursing would repeat most of the range on both sides.
     * Heapsort reaches an answer whatever the comparison does. */
    if ((i - begin) + (end - j) > (end - begin) + 1) {
        SORT_FUNC(_heap_sort)(begin, end, arg);
        return;
    }

    if (end - j > 1)   SORT_FUNC(_quick_sort)(j, end, d-1, arg);
    if (i - begin > 1) SORT_FUNC(_quick_sort)(begin, i, d-1, arg);
}

/**
 * Sort [begin, end) in place.
 * @param[in,out] begin  First element.
 * @param[in]     end    One past the last element.
 * @param[in]     arg    Opaque context handed to SORT_LESS.
 */
static void
SORT_FUNC(_sort)(SORT_ELEM *begin, SORT_ELEM *end, void *arg)
{
    size_t n = end - begin;
    if (n < 2) return;

    /* Ordered input is common enough to be worth one pass to find, and both
     * orderings are then free.  The descending case reverses only when every
     * adjacent pair is strictly descending, so no equal elements have their
     * order disturbed by it. */
    SORT_ELEM *p = begin + 1;
    while (p < end && !sort_less(*p, *(p-1))) p++;
    if (p == end) return;

    if (p == begin + 1) {
        SORT_ELEM *q = begin + 2;
        while (q < end && sort_less(*q, *(q-1))) q++;
        if (q == end) {
            for (SORT_ELEM *l = begin, *r = end - 1; l < r; l++, r--) {
                sort_swap(*l, *r);
            }
            return;
        }
    }

    size_t d = CHAR_BIT * sizeof(n) - nlz_intptr(n) - 1;
    SORT_FUNC(_quick_sort)(begin, end, d << 1, arg);
}

#undef SORT_INSERTION_MAX
#undef sort_med3
#undef sort_swap
#undef sort_less
#undef SORT_FUNC
#undef SORT_CAT
#undef SORT_CAT1
#undef SORT_LESS
#undef SORT_ELEM
#undef SORT_NAME
