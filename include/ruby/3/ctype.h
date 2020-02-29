/**                                                     \noop-*-C++-*-vi:ft=cpp
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed   with   either  `RUBY3`   or   `ruby3`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries. They could be written in C++98.
 * @brief      Our own, locale independent, character handling routines.
 */
#ifndef  RUBY3_CTYPE_H
#define  RUBY3_CTYPE_H
#include "ruby/3/config.h"

#ifdef STDC_HEADERS
# include <ctype.h>
#endif

#include "ruby/3/dllexport.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

/* locale insensitive functions */

static inline int rb_isascii(int c){ return '\0' <= c && c <= '\x7f'; }
static inline int rb_isupper(int c){ return 'A' <= c && c <= 'Z'; }
static inline int rb_islower(int c){ return 'a' <= c && c <= 'z'; }
static inline int rb_isalpha(int c){ return rb_isupper(c) || rb_islower(c); }
static inline int rb_isdigit(int c){ return '0' <= c && c <= '9'; }
static inline int rb_isalnum(int c){ return rb_isalpha(c) || rb_isdigit(c); }
static inline int rb_isxdigit(int c){ return rb_isdigit(c) || ('A' <= c && c <= 'F') || ('a' <= c && c <= 'f'); }
static inline int rb_isblank(int c){ return c == ' ' || c == '\t'; }
static inline int rb_isspace(int c){ return c == ' ' || ('\t' <= c && c <= '\r'); }
static inline int rb_iscntrl(int c){ return ('\0' <= c && c < ' ') || c == '\x7f'; }
static inline int rb_isprint(int c){ return ' ' <= c && c <= '\x7e'; }
static inline int rb_ispunct(int c){ return !rb_isalnum(c); }
static inline int rb_isgraph(int c){ return '!' <= c && c <= '\x7e'; }
static inline int rb_tolower(int c) { return rb_isupper(c) ? (c|0x20) : c; }
static inline int rb_toupper(int c) { return rb_islower(c) ? (c&0x5f) : c; }

#ifndef ISPRINT
#define ISASCII(c) rb_isascii(c)
#define ISPRINT(c) rb_isprint(c)
#define ISGRAPH(c) rb_isgraph(c)
#define ISSPACE(c) rb_isspace(c)
#define ISUPPER(c) rb_isupper(c)
#define ISLOWER(c) rb_islower(c)
#define ISALNUM(c) rb_isalnum(c)
#define ISALPHA(c) rb_isalpha(c)
#define ISDIGIT(c) rb_isdigit(c)
#define ISXDIGIT(c) rb_isxdigit(c)
#define ISBLANK(c) rb_isblank(c)
#define ISCNTRL(c) rb_iscntrl(c)
#define ISPUNCT(c) rb_ispunct(c)
#endif
#define TOUPPER(c) rb_toupper(c)
#define TOLOWER(c) rb_tolower(c)

int st_locale_insensitive_strcasecmp(const char *s1, const char *s2);
int st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n);
#define STRCASECMP(s1, s2) (st_locale_insensitive_strcasecmp((s1), (s2)))
#define STRNCASECMP(s1, s2, n) (st_locale_insensitive_strncasecmp((s1), (s2), (n)))

unsigned long ruby_strtoul(const char *str, char **endptr, int base);
#define STRTOUL(str, endptr, base) (ruby_strtoul((str), (endptr), (base)))

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_CTYPE_H */
