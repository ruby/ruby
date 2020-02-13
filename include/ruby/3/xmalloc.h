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
 * @brief      Declares ::ruby_xmalloc().
 */
#ifndef  RUBY3_XMALLOC_H
#define  RUBY3_XMALLOC_H
#include "ruby/3/config.h"
#include "ruby/3/dllexport.h"
#include "ruby/backward/2/attributes.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#define xmalloc ruby_xmalloc
#define xmalloc2 ruby_xmalloc2
#define xcalloc ruby_xcalloc
#define xrealloc ruby_xrealloc
#define xrealloc2 ruby_xrealloc2
#define xfree ruby_xfree

void *ruby_xmalloc(size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1));
void *ruby_xmalloc2(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xcalloc(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xrealloc(void*,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2));
void *ruby_xrealloc2(void*,size_t,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2,3));
void ruby_xfree(void*);

#ifndef USE_GC_MALLOC_OBJ_INFO_DETAILS
#define USE_GC_MALLOC_OBJ_INFO_DETAILS 0
#endif

#if USE_GC_MALLOC_OBJ_INFO_DETAILS

void *ruby_xmalloc_body(size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1));
void *ruby_xmalloc2_body(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xcalloc_body(size_t,size_t) RUBY_ATTR_MALLOC RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((1,2));
void *ruby_xrealloc_body(void*,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2));
void *ruby_xrealloc2_body(void*,size_t,size_t) RUBY_ATTR_RETURNS_NONNULL RUBY_ATTR_ALLOC_SIZE((2,3));

#define ruby_xmalloc(s1)            ruby_xmalloc_with_location(s1, __FILE__, __LINE__)
#define ruby_xmalloc2(s1, s2)       ruby_xmalloc2_with_location(s1, s2, __FILE__, __LINE__)
#define ruby_xcalloc(s1, s2)        ruby_xcalloc_with_location(s1, s2, __FILE__, __LINE__)
#define ruby_xrealloc(ptr, s1)      ruby_xrealloc_with_location(ptr, s1, __FILE__, __LINE__)
#define ruby_xrealloc2(ptr, s1, s2) ruby_xrealloc2_with_location(ptr, s1, s2, __FILE__, __LINE__)

extern const char *ruby_malloc_info_file;
extern int ruby_malloc_info_line;

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

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_XMALLOC_H */
