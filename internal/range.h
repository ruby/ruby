#ifndef INTERNAL_RANGE_H /* -*- C -*- */
#define INTERNAL_RANGE_H
/**
 * @file
 * @brief      Internal header for Range.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "internal/struct.h"    /* for RSTRUCT */

/* range.c */
static inline VALUE RANGE_BEG(VALUE r);
static inline VALUE RANGE_END(VALUE r);
static inline VALUE RANGE_EXCL(VALUE r);

static inline VALUE
RANGE_BEG(VALUE r)
{
    return RSTRUCT(r)->as.ary[0];
}

static inline VALUE
RANGE_END(VALUE r)
{
    return RSTRUCT(r)->as.ary[1];
}

static inline VALUE
RANGE_EXCL(VALUE r)
{
    return RSTRUCT(r)->as.ary[2];
}

#endif /* INTERNAL_RANGE_H */
