#ifndef RBIMPL_CTYPE_H                               /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_CTYPE_H
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
 *             extension libraries. They could be written in C++98.
 * @brief      Our own, locale independent, character handling routines.
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <ctype.h>
#endif

#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/dllexport.h"

#ifndef ISPRINT
# define ISASCII  rb_isascii
# define ISPRINT  rb_isprint
# define ISGRAPH  rb_isgraph
# define ISSPACE  rb_isspace
# define ISUPPER  rb_isupper
# define ISLOWER  rb_islower
# define ISALNUM  rb_isalnum
# define ISALPHA  rb_isalpha
# define ISDIGIT  rb_isdigit
# define ISXDIGIT rb_isxdigit
# define ISBLANK  rb_isblank
# define ISCNTRL  rb_iscntrl
# define ISPUNCT  rb_ispunct
#endif

#define TOUPPER     rb_toupper
#define TOLOWER     rb_tolower
#define STRCASECMP  st_locale_insensitive_strcasecmp
#define STRNCASECMP st_locale_insensitive_strncasecmp
#define STRTOUL     ruby_strtoul

RBIMPL_SYMBOL_EXPORT_BEGIN()
/* locale insensitive functions */
int st_locale_insensitive_strcasecmp(const char *s1, const char *s2);
int st_locale_insensitive_strncasecmp(const char *s1, const char *s2, size_t n);
unsigned long ruby_strtoul(const char *str, char **endptr, int base);
RBIMPL_SYMBOL_EXPORT_END()

/*
 * We are making  the functions below to return `int`  instead of `bool`.  They
 * have been as such since their birth at 5f237d79033b2109afb768bc889611fa9630.
 */

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isascii(int c)
{
    return '\0' <= c && c <= '\x7f';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isupper(int c)
{
    return 'A' <= c && c <= 'Z';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_islower(int c)
{
    return 'a' <= c && c <= 'z';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isalpha(int c)
{
    return rb_isupper(c) || rb_islower(c);
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isdigit(int c)
{
    return '0' <= c && c <= '9';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isalnum(int c)
{
    return rb_isalpha(c) || rb_isdigit(c);
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isxdigit(int c)
{
    return rb_isdigit(c) || ('A' <= c && c <= 'F') || ('a' <= c && c <= 'f');
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isblank(int c)
{
    return c == ' ' || c == '\t';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isspace(int c)
{
    return c == ' ' || ('\t' <= c && c <= '\r');
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_iscntrl(int c)
{
    return ('\0' <= c && c < ' ') || c == '\x7f';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isprint(int c)
{
    return ' ' <= c && c <= '\x7e';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_ispunct(int c)
{
    return !rb_isalnum(c);
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_isgraph(int c)
{
    return '!' <= c && c <= '\x7e';
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_tolower(int c)
{
    return rb_isupper(c) ? (c|0x20) : c;
}

RBIMPL_ATTR_CONST()
RBIMPL_ATTR_CONSTEXPR(CXX11)
RBIMPL_ATTR_ARTIFICIAL()
static inline int
rb_toupper(int c)
{
    return rb_islower(c) ? (c&0x5f) : c;
}

#endif /* RBIMPL_CTYPE_H */
