#ifndef INTERNAL_FLOAT_CONV_H                            /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_FLOAT_CONV_H
/**
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for float_conv.c.
 */
#include "ruby/internal/config.h"

/* The most digits that rb_float_shortest_digits() writes. */
#define RB_FLOAT_SHORTEST_DIGITS_MAX 17

/* float_conv.c */
int rb_float_shortest_digits(double d, char *buf, int *decpt);

#endif /* INTERNAL_FLOAT_CONV_H */
