#ifndef INTERNAL_UTIL_H /* -*- C -*- */
#define INTERNAL_UTIL_H
/**
 * @file
 * @brief      Internal header corresponding util.c.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    DO NOT ADD RANDOM GARBAGE HERE THIS FILE IS FOR util.c
 */
#include "ruby/config.h"
#include <stddef.h>             /* for size_t */

#ifdef HAVE_SYS_TYPES_H
# include <sys/types.h>         /* for ssize_t (note: on Windows ssize_t is */
#endif                          /* `#define`d in ruby/config.h) */

/* util.c */
char *ruby_dtoa(double d_, int mode, int ndigits, int *decpt, int *sign, char **rve);
char *ruby_hdtoa(double d, const char *xdigs, int ndigits, int *decpt, int *sign, char **rve);

RUBY_SYMBOL_EXPORT_BEGIN
/* util.c (export) */
extern const signed char ruby_digit36_to_number_table[];
extern const char ruby_hexdigits[];
extern unsigned long ruby_scan_digits(const char *str, ssize_t len, int base, size_t *retlen, int *overflow);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_UTIL_H */
