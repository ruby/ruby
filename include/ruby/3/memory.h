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
 * @brief      Memory management stuff.
 */
#ifndef  RUBY3_MEMORY_H
#define  RUBY3_MEMORY_H
#include "ruby/3/config.h"

#ifdef HAVE_STRING_H
# include <string.h>
#endif

/* Make alloca work the best possible way.  */
#ifdef __GNUC__
# ifndef alloca
#  define alloca __builtin_alloca
# endif
#else
# ifdef HAVE_ALLOCA_H
#  include <alloca.h>
# else
#  ifdef _AIX
#pragma alloca
#  else
#   ifndef alloca               /* predefined by HP cc +Olibcalls */
void *alloca();
#   endif
#  endif /* AIX */
# endif /* HAVE_ALLOCA_H */
#endif /* __GNUC__ */

#include "ruby/3/dllexport.h"
#include "ruby/3/xmalloc.h"
#include "ruby/backward/2/attributes.h"

RUBY3_SYMBOL_EXPORT_BEGIN()

#ifdef __GNUC__
#define RB_GC_GUARD(v) \
    (*__extension__ ({ \
        volatile VALUE *rb_gc_guarded_ptr = &(v); \
        __asm__("" : : "m"(rb_gc_guarded_ptr)); \
        rb_gc_guarded_ptr; \
    }))
#elif defined _MSC_VER
#pragma optimize("", off)
static inline volatile VALUE *rb_gc_guarded_ptr(volatile VALUE *ptr) {return ptr;}
#pragma optimize("", on)
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr(&(v)))
#else
volatile VALUE *rb_gc_guarded_ptr_val(volatile VALUE *ptr, VALUE val);
#define HAVE_RB_GC_GUARDED_PTR_VAL 1
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr_val(&(v),(v)))
#endif

#define RB_ALLOC_N(type,n) ((type*)ruby_xmalloc2((size_t)(n),sizeof(type)))
#define RB_ALLOC(type) ((type*)ruby_xmalloc(sizeof(type)))
#define RB_ZALLOC_N(type,n) ((type*)ruby_xcalloc((size_t)(n),sizeof(type)))
#define RB_ZALLOC(type) (RB_ZALLOC_N(type,1))
#define RB_REALLOC_N(var,type,n) ((var)=(type*)ruby_xrealloc2((char*)(var),(size_t)(n),sizeof(type)))

#define ALLOC_N(type,n) RB_ALLOC_N(type,n)
#define ALLOC(type) RB_ALLOC(type)
#define ZALLOC_N(type,n) RB_ZALLOC_N(type,n)
#define ZALLOC(type) RB_ZALLOC(type)
#define REALLOC_N(var,type,n) RB_REALLOC_N(var,type,n)

#if defined(HAVE_BUILTIN___BUILTIN_ALLOCA_WITH_ALIGN) && defined(RUBY_ALIGNOF)
/* I don't know why but __builtin_alloca_with_align's second argument
   takes bits rather than bytes. */
#define ALLOCA_N(type, n) \
    (type*)__builtin_alloca_with_align((sizeof(type)*(n)), \
        RUBY_ALIGNOF(type) * CHAR_BIT)
#else
#define ALLOCA_N(type,n) ((type*)alloca(sizeof(type)*(n)))
#endif

void *rb_alloc_tmp_buffer(volatile VALUE *store, long len) RUBY_ATTR_ALLOC_SIZE((2));
void *rb_alloc_tmp_buffer_with_count(volatile VALUE *store, size_t len,size_t count) RUBY_ATTR_ALLOC_SIZE((2,3));
void rb_free_tmp_buffer(volatile VALUE *store);
NORETURN(void ruby_malloc_size_overflow(size_t, size_t));
#if HAVE_LONG_LONG && SIZEOF_SIZE_T * 2 <= SIZEOF_LONG_LONG
# define DSIZE_T unsigned LONG_LONG
#elif defined(HAVE_INT128_T)
# define DSIZE_T uint128_t
#endif
static inline int
rb_mul_size_overflow(size_t a, size_t b, size_t max, size_t *c)
{
#ifdef DSIZE_T
# ifdef __GNUC__
    __extension__
# endif
    DSIZE_T c2 = (DSIZE_T)a * (DSIZE_T)b;
    if (c2 > max) return 1;
    *c = (size_t)c2;
#else
    if (b != 0 && a > max / b) return 1;
    *c = a * b;
#endif
    return 0;
}
static inline void *
rb_alloc_tmp_buffer2(volatile VALUE *store, long count, size_t elsize)
{
    size_t cnt = (size_t)count;
    if (elsize == sizeof(VALUE)) {
        if (RB_UNLIKELY(cnt > LONG_MAX / sizeof(VALUE))) {
            ruby_malloc_size_overflow(cnt, elsize);
        }
    }
    else {
        size_t size, max = LONG_MAX - sizeof(VALUE) + 1;
        if (RB_UNLIKELY(rb_mul_size_overflow(cnt, elsize, max, &size))) {
            ruby_malloc_size_overflow(cnt, elsize);
        }
        cnt = (size + sizeof(VALUE) - 1) / sizeof(VALUE);
    }
    return rb_alloc_tmp_buffer_with_count(store, cnt * sizeof(VALUE), cnt);
}
/* allocates _n_ bytes temporary buffer and stores VALUE including it
 * in _v_.  _n_ may be evaluated twice. */
#ifdef C_ALLOCA
# define RB_ALLOCV(v, n) rb_alloc_tmp_buffer(&(v), (n))
# define RB_ALLOCV_N(type, v, n) \
     rb_alloc_tmp_buffer2(&(v), (n), sizeof(type))
#else
# define RUBY_ALLOCV_LIMIT 1024
# define RB_ALLOCV(v, n) ((n) < RUBY_ALLOCV_LIMIT ? \
                       ((v) = 0, alloca(n)) : \
                       rb_alloc_tmp_buffer(&(v), (n)))
# define RB_ALLOCV_N(type, v, n) \
    ((type*)(((size_t)(n) < RUBY_ALLOCV_LIMIT / sizeof(type)) ? \
             ((v) = 0, alloca((size_t)(n) * sizeof(type))) : \
             rb_alloc_tmp_buffer2(&(v), (long)(n), sizeof(type))))
#endif
#define RB_ALLOCV_END(v) rb_free_tmp_buffer(&(v))

#define ALLOCV(v, n) RB_ALLOCV(v, n)
#define ALLOCV_N(type, v, n) RB_ALLOCV_N(type, v, n)
#define ALLOCV_END(v) RB_ALLOCV_END(v)

#define MEMZERO(p,type,n) memset((p), 0, sizeof(type)*(size_t)(n))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), sizeof(type)*(size_t)(n))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), sizeof(type)*(size_t)(n))
#define MEMCMP(p1,p2,type,n) memcmp((p1), (p2), sizeof(type)*(size_t)(n))
#ifdef __GLIBC__
static inline void *
ruby_nonempty_memcpy(void *dest, const void *src, size_t n)
{
    /* if nothing to be copied, src may be NULL */
    return (n ? memcpy(dest, src, n) : dest);
}
#define memcpy(p1,p2,n) ruby_nonempty_memcpy(p1, p2, n)
#endif

RUBY3_SYMBOL_EXPORT_END()

#endif /* RUBY3_MEMORY_H */
