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
 * @brief      Defines struct ::RArray.
 */
#ifndef  RUBY3_RARRAY_H
#define  RUBY3_RARRAY_H
#include "ruby/3/dllexport.h"
#include "ruby/3/value.h"
#include "ruby/3/fl_type.h"
#include "ruby/backward/2/r_cast.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#ifndef USE_TRANSIENT_HEAP
#define USE_TRANSIENT_HEAP 1
#endif

enum ruby_rarray_flags {
    RARRAY_EMBED_LEN_MAX = RVALUE_EMBED_LEN_MAX,
    RARRAY_EMBED_FLAG = RUBY_FL_USER1,
    /* RUBY_FL_USER2 is for ELTS_SHARED */
    RARRAY_EMBED_LEN_MASK = (RUBY_FL_USER4|RUBY_FL_USER3),
    RARRAY_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+3),

#if USE_TRANSIENT_HEAP
    RARRAY_TRANSIENT_FLAG = RUBY_FL_USER13,
#define RARRAY_TRANSIENT_FLAG RARRAY_TRANSIENT_FLAG
#else
#define RARRAY_TRANSIENT_FLAG 0
#endif

    RARRAY_ENUM_END
};
#define RARRAY_EMBED_FLAG (VALUE)RARRAY_EMBED_FLAG
#define RARRAY_EMBED_LEN_MASK (VALUE)RARRAY_EMBED_LEN_MASK
#define RARRAY_EMBED_LEN_MAX RARRAY_EMBED_LEN_MAX
#define RARRAY_EMBED_LEN_SHIFT RARRAY_EMBED_LEN_SHIFT

struct RArray {
    struct RBasic basic;
    union {
        struct {
            long len;
            union {
                long capa;
#if defined(__clang__)      /* <- clang++ is sane */ || \
    !defined(__cplusplus)   /* <- C99 is sane */     || \
    (__cplusplus > 199711L) /* <- C++11 is sane */
                const
#endif
                VALUE shared_root;
            } aux;
            const VALUE *ptr;
        } heap;
        const VALUE ary[RARRAY_EMBED_LEN_MAX];
    } as;
};
#define RARRAY_EMBED_LEN(a) \
    (long)((RBASIC(a)->flags >> RARRAY_EMBED_LEN_SHIFT) & \
           (RARRAY_EMBED_LEN_MASK >> RARRAY_EMBED_LEN_SHIFT))
#define RARRAY_LEN(a) rb_array_len(a)
#define RARRAY_LENINT(ary) rb_long2int(RARRAY_LEN(ary))
#define RARRAY_CONST_PTR(a) rb_array_const_ptr(a)
#define RARRAY_CONST_PTR_TRANSIENT(a) rb_array_const_ptr_transient(a)

#if USE_TRANSIENT_HEAP
#define RARRAY_TRANSIENT_P(ary) FL_TEST_RAW((ary), RARRAY_TRANSIENT_FLAG)
#else
#define RARRAY_TRANSIENT_P(ary) 0
#endif

#define RARRAY_PTR_USE_START_TRANSIENT(a) rb_array_ptr_use_start(a, 1)
#define RARRAY_PTR_USE_END_TRANSIENT(a) rb_array_ptr_use_end(a, 1)

#define RARRAY_PTR_USE_TRANSIENT(ary, ptr_name, expr) do { \
    const VALUE _ary = (ary); \
    VALUE *ptr_name = (VALUE *)RARRAY_PTR_USE_START_TRANSIENT(_ary); \
    expr; \
    RARRAY_PTR_USE_END_TRANSIENT(_ary); \
} while (0)

#define RARRAY_PTR_USE_START(a) rb_array_ptr_use_start(a, 0)
#define RARRAY_PTR_USE_END(a) rb_array_ptr_use_end(a, 0)

#define RARRAY_PTR_USE(ary, ptr_name, expr) do { \
    const VALUE _ary = (ary); \
    VALUE *ptr_name = (VALUE *)RARRAY_PTR_USE_START(_ary); \
    expr; \
    RARRAY_PTR_USE_END(_ary); \
} while (0)

#define RARRAY_AREF(a, i) (RARRAY_CONST_PTR_TRANSIENT(a)[i])
#define RARRAY_ASET(a, i, v) do { \
    const VALUE _ary = (a); \
    const VALUE _v = (v); \
    VALUE *ptr = (VALUE *)RARRAY_PTR_USE_START_TRANSIENT(_ary); \
    RB_OBJ_WRITE(_ary, &ptr[i], _v); \
    RARRAY_PTR_USE_END_TRANSIENT(_ary); \
} while (0)

#define RARRAY_PTR(a) ((VALUE *)RARRAY_CONST_PTR(RB_OBJ_WB_UNPROTECT_FOR(ARRAY, a)))

#define RARRAY(obj)  (R_CAST(RArray)(obj))

static inline long
rb_array_len(VALUE a)
{
    return (RBASIC(a)->flags & RARRAY_EMBED_FLAG) ?
        RARRAY_EMBED_LEN(a) : RARRAY(a)->as.heap.len;
}

#if defined(__fcc__) || defined(__fcc_version) || \
    defined(__FCC__) || defined(__FCC_VERSION)
/* workaround for old version of Fujitsu C Compiler (fcc) */
# define FIX_CONST_VALUE_PTR(x) ((const VALUE *)(x))
#else
# define FIX_CONST_VALUE_PTR(x) (x)
#endif

/* internal function. do not use this function */
static inline const VALUE *
rb_array_const_ptr_transient(VALUE a)
{
    return FIX_CONST_VALUE_PTR((RBASIC(a)->flags & RARRAY_EMBED_FLAG) ?
        RARRAY(a)->as.ary : RARRAY(a)->as.heap.ptr);
}

/* internal function. do not use this function */
static inline const VALUE *
rb_array_const_ptr(VALUE a)
{
#if USE_TRANSIENT_HEAP
    void rb_ary_detransient(VALUE a);

    if (RARRAY_TRANSIENT_P(a)) {
        rb_ary_detransient(a);
    }
#endif
    return rb_array_const_ptr_transient(a);
}

/* internal function. do not use this function */
static inline VALUE *
rb_array_ptr_use_start(VALUE a, int allow_transient)
{
    VALUE *rb_ary_ptr_use_start(VALUE ary);

#if USE_TRANSIENT_HEAP
    if (!allow_transient) {
        if (RARRAY_TRANSIENT_P(a)) {
            void rb_ary_detransient(VALUE a);
            rb_ary_detransient(a);
        }
    }
#endif
    (void)allow_transient;

    return rb_ary_ptr_use_start(a);
}

/* internal function. do not use this function */
static inline void
rb_array_ptr_use_end(VALUE a, int allow_transient)
{
    void rb_ary_ptr_use_end(VALUE a);
    rb_ary_ptr_use_end(a);
    (void)allow_transient;
}

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY3_RARRAY_H */
