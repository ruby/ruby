#ifndef INTERNAL_RANGE_H                                  /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_RANGE_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Range.
 */
#include "internal/struct.h"    /* for RSTRUCT */

#define RANGE_FL_INIT FL_USER18
#define RANGE_FL_EXCL FL_USER19

/* range.c */
static inline VALUE RANGE_BEG(VALUE r);
static inline VALUE RANGE_END(VALUE r);
static inline VALUE RANGE_EXCL(VALUE r);

static inline VALUE
RANGE_BEG(VALUE r)
{
    return RSTRUCT_GET_RAW(r, 0);
}

static inline VALUE
RANGE_END(VALUE r)
{
    return RSTRUCT_GET_RAW(r, 1);
}

static inline VALUE
RANGE_EXCL(VALUE r)
{
    if (FL_TEST_RAW(r, RANGE_FL_INIT)) {
        return RBOOL(FL_TEST_RAW(r, RANGE_FL_EXCL));
    }
    return Qnil;
}

VALUE
rb_range_component_beg_len(VALUE b, VALUE e, int excl,
                           long *begp, long *lenp, long len, int err);

#endif /* INTERNAL_RANGE_H */
