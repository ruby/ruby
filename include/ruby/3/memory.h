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

#ifdef STDC_HEADERS
# include <stddef.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#ifdef HAVE_STDINT_H
# include <stdint.h>
#endif

#ifdef HAVE_ALLOCA_H
# include <alloca.h>
#endif

#if defined(_MSC_VER) && defined(_WIN64)
# include <intrin.h>
# pragma intrinsic(_umul128)
#endif

#include "ruby/3/attr/alloc_size.h"
#include "ruby/3/attr/const.h"
#include "ruby/3/attr/constexpr.h"
#include "ruby/3/attr/noalias.h"
#include "ruby/3/attr/nonnull.h"
#include "ruby/3/attr/noreturn.h"
#include "ruby/3/attr/restrict.h"
#include "ruby/3/attr/returns_nonnull.h"
#include "ruby/3/cast.h"
#include "ruby/3/dllexport.h"
#include "ruby/3/has/builtin.h"
#include "ruby/3/stdalign.h"
#include "ruby/3/stdbool.h"
#include "ruby/3/xmalloc.h"
#include "ruby/backward/2/limits.h"
#include "ruby/backward/2/long_long.h"
#include "ruby/backward/2/assume.h"
#include "ruby/defines.h"

/* Make alloca work the best possible way.  */
#if defined(alloca)
# /* Take that. */
#elif RUBY3_HAS_BUILTIN(__builtin_alloca)
# define alloca __builtin_alloca
#elif defined(_AIX)
# pragma alloca
#elif defined(__cplusplus)
extern "C" void *alloca(size_t);
#else
extern void *alloca();
#endif

#if defined(HAVE_INT128_T) && SIZEOF_SIZE_T <= 8
# define DSIZE_T uint128_t
#elif SIZEOF_SIZE_T * 2 <= SIZEOF_LONG_LONG
# define DSIZE_T unsigned LONG_LONG
#endif

#ifdef C_ALLOCA
# define RUBY_ALLOCV_LIMIT 0
#else
# define RUBY_ALLOCV_LIMIT 1024
#endif

#ifdef __GNUC__
#define RB_GC_GUARD(v) \
    (*__extension__ ({ \
        volatile VALUE *rb_gc_guarded_ptr = &(v); \
        __asm__("" : : "m"(rb_gc_guarded_ptr)); \
        rb_gc_guarded_ptr; \
    }))
#elif defined _MSC_VER
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr(&(v)))
#else
#define HAVE_RB_GC_GUARDED_PTR_VAL 1
#define RB_GC_GUARD(v) (*rb_gc_guarded_ptr_val(&(v),(v)))
#endif

/* Casts needed because void* is NOT compaible with others in C++. */
#define RB_ALLOC_N(type,n)  RUBY3_CAST((type *)ruby_xmalloc2((n), sizeof(type)))
#define RB_ALLOC(type)      RUBY3_CAST((type *)ruby_xmalloc(sizeof(type)))
#define RB_ZALLOC_N(type,n) RUBY3_CAST((type *)ruby_xcalloc((n), sizeof(type)))
#define RB_ZALLOC(type)     (RB_ZALLOC_N(type, 1))
#define RB_REALLOC_N(var,type,n) \
    ((var) = RUBY3_CAST((type *)ruby_xrealloc2((void *)(var), (n), sizeof(type))))

/* I don't know why but __builtin_alloca_with_align's second argument
   takes bits rather than bytes. */
#if RUBY3_HAS_BUILTIN(__builtin_alloca_with_align)
# define ALLOCA_N(type, n)                              \
    RUBY3_CAST((type *)                                 \
        __builtin_alloca_with_align(                    \
            ruby3_size_mul_or_raise(sizeof(type), (n)), \
            RUBY_ALIGNOF(type) * CHAR_BIT))
#else
# define ALLOCA_N(type,n) \
    RUBY3_CAST((type *)alloca(ruby3_size_mul_or_raise(sizeof(type), (n))))
#endif

/* allocates _n_ bytes temporary buffer and stores VALUE including it
 * in _v_.  _n_ may be evaluated twice. */
#define RB_ALLOCV(v, n)        \
    ((n) < RUBY_ALLOCV_LIMIT ? \
     ((v) = 0, alloca(n)) :    \
     rb_alloc_tmp_buffer(&(v), (n)))
#define RB_ALLOCV_N(type, v, n)                             \
    RUBY3_CAST((type *)                                     \
        (((size_t)(n) < RUBY_ALLOCV_LIMIT / sizeof(type)) ? \
         ((v) = 0, alloca((n) * sizeof(type))) :            \
         rb_alloc_tmp_buffer2(&(v), (n), sizeof(type))))
#define RB_ALLOCV_END(v) rb_free_tmp_buffer(&(v))

#define MEMZERO(p,type,n) memset((p), 0, ruby3_size_mul_or_raise(sizeof(type), (n)))
#define MEMCPY(p1,p2,type,n) memcpy((p1), (p2), ruby3_size_mul_or_raise(sizeof(type), (n)))
#define MEMMOVE(p1,p2,type,n) memmove((p1), (p2), ruby3_size_mul_or_raise(sizeof(type), (n)))
#define MEMCMP(p1,p2,type,n) memcmp((p1), (p2), ruby3_size_mul_or_raise(sizeof(type), (n)))

#define ALLOC_N    RB_ALLOC_N
#define ALLOC      RB_ALLOC
#define ZALLOC_N   RB_ZALLOC_N
#define ZALLOC     RB_ZALLOC
#define REALLOC_N  RB_REALLOC_N
#define ALLOCV     RB_ALLOCV
#define ALLOCV_N   RB_ALLOCV_N
#define ALLOCV_END RB_ALLOCV_END

/* Expecting this struct to be eliminated by function inlinings */
struct ruby3_size_mul_overflow_tag {
    bool left;
    size_t right;
};

RUBY3_SYMBOL_EXPORT_BEGIN()
RUBY3_ATTR_RESTRICT()
RUBY3_ATTR_RETURNS_NONNULL()
RUBY3_ATTR_ALLOC_SIZE((2))
void *rb_alloc_tmp_buffer(volatile VALUE *store, long len);

RUBY3_ATTR_RESTRICT()
RUBY3_ATTR_RETURNS_NONNULL()
RUBY3_ATTR_ALLOC_SIZE((2,3))
void *rb_alloc_tmp_buffer_with_count(volatile VALUE *store, size_t len,size_t count);

void rb_free_tmp_buffer(volatile VALUE *store);

RUBY3_ATTR_NORETURN()
void ruby_malloc_size_overflow(size_t, size_t);

#ifdef HAVE_RB_GC_GUARDED_PTR_VAL
volatile VALUE *rb_gc_guarded_ptr_val(volatile VALUE *ptr, VALUE val);
#endif
RUBY3_SYMBOL_EXPORT_END()

#ifdef _MSC_VER
# pragma optimize("", off)

static inline volatile VALUE *
rb_gc_guarded_ptr(volatile VALUE *ptr)
{
    return ptr;
}

# pragma optimize("", on)
#endif

/* Does anyone use it?  Just here for backwards compatibility. */
static inline int
rb_mul_size_overflow(size_t a, size_t b, size_t max, size_t *c)
{
#ifdef DSIZE_T
    RB_GNUC_EXTENSION DSIZE_T da, db, c2;
    da = a;
    db = b;
    c2 = da * db;
    if (c2 > max) return 1;
    *c = RUBY3_CAST((size_t)c2);
#else
    if (b != 0 && a > max / b) return 1;
    *c = a * b;
#endif
    return 0;
}

#if RUBY3_COMPILER_SINCE(GCC, 7, 0, 0)
RUBY3_ATTR_CONSTEXPR(CXX14) /* https://gcc.gnu.org/bugzilla/show_bug.cgi?id=70507 */
#elif RUBY3_COMPILER_SINCE(Clang, 7, 0, 0)
RUBY3_ATTR_CONSTEXPR(CXX14) /* https://bugs.llvm.org/show_bug.cgi?id=37633 */
#endif
RUBY3_ATTR_CONST()
static inline struct ruby3_size_mul_overflow_tag
ruby3_size_mul_overflow(size_t x, size_t y)
{
    struct ruby3_size_mul_overflow_tag ret = { false,  0, };

#if RUBY3_HAS_BUILTIN(__builtin_mul_overflow)
    ret.left = __builtin_mul_overflow(x, y, &ret.right);

#elif defined(DSIZE_T)
    RB_GNUC_EXTENSION DSIZE_T dx = x;
    RB_GNUC_EXTENSION DSIZE_T dy = y;
    RB_GNUC_EXTENSION DSIZE_T dz = dx * dy;
    ret.left  = dz > SIZE_MAX;
    ret.right = RUBY3_CAST((size_t)dz);

#elif defined(_MSC_VER) && defined(_WIN64)
    unsigned __int64 dp = 0;
    unsigned __int64 dz = _umul128(x, y, &dp);
    ret.left  = RUBY3_CAST((bool)dp);
    ret.right = RUBY3_CAST((size_t)dz);

#else
    /* https://wiki.sei.cmu.edu/confluence/display/c/INT30-C.+Ensure+that+unsigned+integer+operations+do+not+wrap */
    ret.left  = (y != 0) && (x > SIZE_MAX / y);
    ret.right = x * y;
#endif

    return ret;
}

static inline size_t
ruby3_size_mul_or_raise(size_t x, size_t y)
{
    struct ruby3_size_mul_overflow_tag size =
        ruby3_size_mul_overflow(x, y);

    if (RB_LIKELY(! size.left)) {
        return size.right;
    }
    else {
        ruby_malloc_size_overflow(x, y);
        RUBY3_UNREACHABLE_RETURN(0);
    }
}

static inline void *
rb_alloc_tmp_buffer2(volatile VALUE *store, long count, size_t elsize)
{
    return rb_alloc_tmp_buffer_with_count(
        store, ruby3_size_mul_or_raise(count, elsize), count);
}

RUBY3_ATTR_NOALIAS()
RUBY3_ATTR_NONNULL((1))
RUBY3_ATTR_RETURNS_NONNULL()
/* At least since 2004, glibc's <string.h> annotates memcpy to be
 * __attribute__((__nonnull__(1, 2))).  However it is safe to pass NULL to the
 * source pointer, if n is 0.  Let's wrap memcpy. */
static inline void *
ruby_nonempty_memcpy(void *dest, const void *src, size_t n)
{
    if (n) {
        return memcpy(dest, src, n);
    }
    else {
        return dest;
    }
}
#undef memcpy
#define memcpy ruby_nonempty_memcpy

#endif /* RUBY3_MEMORY_H */
