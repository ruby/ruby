#ifndef RBIMPL_XMALLOC_H                             /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_XMALLOC_H
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
 * @brief      Declares ::ruby_xmalloc().
 */
#include "ruby/internal/config.h"

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#include "ruby/internal/attr/alloc_size.h"
#include "ruby/internal/attr/nodiscard.h"
#include "ruby/internal/attr/noexcept.h"
#include "ruby/internal/attr/restrict.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/dllexport.h"

#ifndef USE_GC_MALLOC_OBJ_INFO_DETAILS
# define USE_GC_MALLOC_OBJ_INFO_DETAILS 0
#endif

#define xmalloc ruby_xmalloc
#define xmalloc2 ruby_xmalloc2
#define xcalloc ruby_xcalloc
#define xrealloc ruby_xrealloc
#define xrealloc2 ruby_xrealloc2
#define xfree ruby_xfree

RBIMPL_SYMBOL_EXPORT_BEGIN()

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1))
void *ruby_xmalloc(size_t size)
RBIMPL_ATTR_NOEXCEPT(malloc(size))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
void *ruby_xmalloc2(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(malloc(nelems * elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
void *ruby_xcalloc(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(calloc(nelems, elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2))
void *ruby_xrealloc(void *ptr, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2,3))
void *ruby_xrealloc2(void *ptr, size_t newelems, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newelems * newsiz))
;

void ruby_xfree(void *ptr)
RBIMPL_ATTR_NOEXCEPT(free(ptr))
;

#if USE_GC_MALLOC_OBJ_INFO_DETAILS || defined(__DOXYGEN)
# define ruby_xmalloc(s1)            ruby_xmalloc_with_location(s1, __FILE__, __LINE__)
# define ruby_xmalloc2(s1, s2)       ruby_xmalloc2_with_location(s1, s2, __FILE__, __LINE__)
# define ruby_xcalloc(s1, s2)        ruby_xcalloc_with_location(s1, s2, __FILE__, __LINE__)
# define ruby_xrealloc(ptr, s1)      ruby_xrealloc_with_location(ptr, s1, __FILE__, __LINE__)
# define ruby_xrealloc2(ptr, s1, s2) ruby_xrealloc2_with_location(ptr, s1, s2, __FILE__, __LINE__)

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1))
void *ruby_xmalloc_body(size_t size)
RBIMPL_ATTR_NOEXCEPT(malloc(size))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
void *ruby_xmalloc2_body(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(malloc(nelems * elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RESTRICT()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((1,2))
void *ruby_xcalloc_body(size_t nelems, size_t elemsiz)
RBIMPL_ATTR_NOEXCEPT(calloc(nelems, elemsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2))
void *ruby_xrealloc_body(void *ptr, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newsiz))
;

RBIMPL_ATTR_NODISCARD()
RBIMPL_ATTR_RETURNS_NONNULL()
RBIMPL_ATTR_ALLOC_SIZE((2,3))
void *ruby_xrealloc2_body(void *ptr, size_t newelems, size_t newsiz)
RBIMPL_ATTR_NOEXCEPT(realloc(ptr, newelems * newsiz))
;

RUBY_EXTERN const char *ruby_malloc_info_file;
RUBY_EXTERN int ruby_malloc_info_line;

static inline void *
ruby_xmalloc_with_location(size_t s, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xmalloc_body(s);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xmalloc2_with_location(size_t s1, size_t s2, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xmalloc2_body(s1, s2);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xcalloc_with_location(size_t s1, size_t s2, const char *file, int line)
{
    void *ptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    ptr = ruby_xcalloc_body(s1, s2);
    ruby_malloc_info_file = NULL;
    return ptr;
}

static inline void *
ruby_xrealloc_with_location(void *ptr, size_t s, const char *file, int line)
{
    void *rptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    rptr = ruby_xrealloc_body(ptr, s);
    ruby_malloc_info_file = NULL;
    return rptr;
}

static inline void *
ruby_xrealloc2_with_location(void *ptr, size_t s1, size_t s2, const char *file, int line)
{
    void *rptr;
    ruby_malloc_info_file = file;
    ruby_malloc_info_line = line;
    rptr = ruby_xrealloc2_body(ptr, s1, s2);
    ruby_malloc_info_file = NULL;
    return rptr;
}
#endif

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RBIMPL_XMALLOC_H */
