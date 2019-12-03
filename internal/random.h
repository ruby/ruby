#ifndef INTERNAL_RANDOM_H /* -*- C -*- */
#define INTERNAL_RANDOM_H
/**
 * @file
 * @brief      Internal header for Random.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include <stddef.h>             /* for size_t */

/* random.c */
int ruby_fill_random_bytes(void *, size_t, int);

#endif /* INTERNAL_RANDOM_H */
