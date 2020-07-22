#ifndef RUBY_UTIL_H                                  /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_UTIL_H 1
/**
 * @file
 * @author     $Author$
 * @date       Thu Mar  9 11:55:53 JST 1995
 * @copyright  Copyright (C) 1993-2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/config.h"
#include "ruby/internal/dllexport.h"
#include "ruby/defines.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

#define DECIMAL_SIZE_OF_BITS(n) (((n) * 3010 + 9998) / 9999)
/* an approximation of ceil(n * log10(2)), up to 65536 at least */

#define scan_oct(s,l,e) ((int)ruby_scan_oct((s),(l),(e)))
unsigned long ruby_scan_oct(const char *, size_t, size_t *);
#define scan_hex(s,l,e) ((int)ruby_scan_hex((s),(l),(e)))
unsigned long ruby_scan_hex(const char *, size_t, size_t *);

#ifdef HAVE_GNU_QSORT_R
# define ruby_qsort qsort_r
#else
void ruby_qsort(void *, const size_t, const size_t,
		int (*)(const void *, const void *, void *), void *);
#endif

void ruby_setenv(const char *, const char *);
void ruby_unsetenv(const char *);

char *ruby_strdup(const char *);
#undef strdup
#define strdup(s) ruby_strdup(s)

char *ruby_getcwd(void);

double ruby_strtod(const char *, char **);
#undef strtod
#define strtod(s,e) ruby_strtod((s),(e))

void ruby_each_words(const char *, void (*)(const char*, int, void*), void *);

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_UTIL_H */
