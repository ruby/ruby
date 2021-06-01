#ifndef RBIMPL_RARRAY_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RBIMPL_RARRAY_H
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
 * @brief      Defines struct ::RArray.
 */
#include "ruby/internal/arithmetic/long.h"
#include "ruby/internal/attr/artificial.h"
#include "ruby/internal/attr/constexpr.h"
#include "ruby/internal/attr/maybe_unused.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/cast.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/fl_type.h"
#include "ruby/internal/rgengc.h"
#include "ruby/internal/stdbool.h"
#include "ruby/internal/value.h"
#include "ruby/internal/value_type.h"
#include "ruby/assert.h"

#ifndef USE_TRANSIENT_HEAP
# define USE_TRANSIENT_HEAP 1
#endif

#define RARRAY(obj)            RBIMPL_CAST((struct RArray *)(obj))
#define RARRAY_EMBED_FLAG      RARRAY_EMBED_FLAG
#define RARRAY_EMBED_LEN_MASK  RARRAY_EMBED_LEN_MASK
#define RARRAY_EMBED_LEN_MAX   RARRAY_EMBED_LEN_MAX
#define RARRAY_EMBED_LEN_SHIFT RARRAY_EMBED_LEN_SHIFT
#if USE_TRANSIENT_HEAP
# define RARRAY_TRANSIENT_FLAG RARRAY_TRANSIENT_FLAG
#else
# define RARRAY_TRANSIENT_FLAG 0
#endif
#define RARRAY_LEN                 rb_array_len
#define RARRAY_CONST_PTR           rb_array_const_ptr
#define RARRAY_CONST_PTR_TRANSIENT rb_array_const_ptr_transient

/** @cond INTERNAL_MACRO */
#if defined(__fcc__) || defined(__fcc_version) || \
    defined(__FCC__) || defined(__FCC_VERSION)
/* workaround for old version of Fujitsu C Compiler (fcc) */
# define FIX_CONST_VALUE_PTR(x) ((const VALUE *)(x))
#else
# define FIX_CONST_VALUE_PTR(x) (x)
#endif

#define RARRAY_EMBED_LEN   RARRAY_EMBED_LEN
#define RARRAY_LENINT      RARRAY_LENINT
#define RARRAY_TRANSIENT_P RARRAY_TRANSIENT_P
#define RARRAY_ASET        RARRAY_ASET
#define RARRAY_PTR         RARRAY_PTR
/** @endcond */

enum ruby_rarray_flags {
    RARRAY_EMBED_FLAG      = RUBY_FL_USER1,
    /* RUBY_FL_USER2 is for ELTS_SHARED */
    RARRAY_EMBED_LEN_MASK  = RUBY_FL_USER4 | RUBY_FL_USER3
#if USE_TRANSIENT_HEAP
    ,
    RARRAY_TRANSIENT_FLAG  = RUBY_FL_USER13
#endif
};

enum ruby_rarray_consts {
    RARRAY_EMBED_LEN_SHIFT = RUBY_FL_USHIFT + 3,
    RARRAY_EMBED_LEN_MAX   = RBIMPL_EMBED_LEN_MAX_OF(VALUE)
};

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

RBIMPL_SYMBOL_EXPORT_BEGIN()
VALUE *rb_ary_ptr_use_start(VALUE ary);
void rb_ary_ptr_use_end(VALUE a);
#if USE_TRANSIENT_HEAP
void rb_ary_detransient(VALUE a);
#endif
RBIMPL_SYMBOL_EXPORT_END()

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline long
RARRAY_EMBED_LEN(VALUE ary)
{
    RBIMPL_ASSERT_TYPE(ary, RUBY_T_ARRAY);
    RBIMPL_ASSERT_OR_ASSUME(RB_FL_ANY_RAW(ary, RARRAY_EMBED_FLAG));

    VALUE f = RBASIC(ary)->flags;
    f &= RARRAY_EMBED_LEN_MASK;
    f >>= RARRAY_EMBED_LEN_SHIFT;
    return RBIMPL_CAST((long)f);
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
static inline long
rb_array_len(VALUE a)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);

    if (RB_FL_ANY_RAW(a, RARRAY_EMBED_FLAG)) {
        return RARRAY_EMBED_LEN(a);
    }
    else {
        return RARRAY(a)->as.heap.len;
    }
}

RBIMPL_ATTR_ARTIFICIAL()
static inline int
RARRAY_LENINT(VALUE ary)
{
    return rb_long2int(RARRAY_LEN(ary));
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline bool
RARRAY_TRANSIENT_P(VALUE ary)
{
    RBIMPL_ASSERT_TYPE(ary, RUBY_T_ARRAY);

#if USE_TRANSIENT_HEAP
    return RB_FL_ANY_RAW(ary, RARRAY_TRANSIENT_FLAG);
#else
    return false;
#endif
}

RBIMPL_ATTR_PURE_UNLESS_DEBUG()
/* internal function. do not use this function */
static inline const VALUE *
rb_array_const_ptr_transient(VALUE a)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);

    if (RB_FL_ANY_RAW(a, RARRAY_EMBED_FLAG)) {
        return FIX_CONST_VALUE_PTR(RARRAY(a)->as.ary);
    }
    else {
        return FIX_CONST_VALUE_PTR(RARRAY(a)->as.heap.ptr);
    }
}

#if ! USE_TRANSIENT_HEAP
RBIMPL_ATTR_PURE_UNLESS_DEBUG()
#endif
/* internal function. do not use this function */
static inline const VALUE *
rb_array_const_ptr(VALUE a)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);

#if USE_TRANSIENT_HEAP
    if (RARRAY_TRANSIENT_P(a)) {
        rb_ary_detransient(a);
    }
#endif
    return rb_array_const_ptr_transient(a);
}

/* internal function. do not use this function */
static inline VALUE *
rb_array_ptr_use_start(VALUE a,
                       RBIMPL_ATTR_MAYBE_UNUSED()
                       int allow_transient)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);

#if USE_TRANSIENT_HEAP
    if (!allow_transient) {
        if (RARRAY_TRANSIENT_P(a)) {
            rb_ary_detransient(a);
        }
    }
#endif

    return rb_ary_ptr_use_start(a);
}

/* internal function. do not use this function */
static inline void
rb_array_ptr_use_end(VALUE a,
                     RBIMPL_ATTR_MAYBE_UNUSED()
                     int allow_transient)
{
    RBIMPL_ASSERT_TYPE(a, RUBY_T_ARRAY);
    rb_ary_ptr_use_end(a);
}

#define RBIMPL_RARRAY_STMT(flag, ary, var, expr) do {        \
    RBIMPL_ASSERT_TYPE((ary), RUBY_T_ARRAY);                 \
    const VALUE rbimpl_ary = (ary);                          \
    VALUE *var = rb_array_ptr_use_start(rbimpl_ary, (flag)); \
    expr;                                                   \
    rb_array_ptr_use_end(rbimpl_ary, (flag));                \
} while (0)

#define RARRAY_PTR_USE_START(a) rb_array_ptr_use_start(a, 0)
#define RARRAY_PTR_USE_END(a) rb_array_ptr_use_end(a, 0)
#define RARRAY_PTR_USE(ary, ptr_name, expr) \
    RBIMPL_RARRAY_STMT(0, ary, ptr_name, expr)

#define RARRAY_PTR_USE_START_TRANSIENT(a) rb_array_ptr_use_start(a, 1)
#define RARRAY_PTR_USE_END_TRANSIENT(a) rb_array_ptr_use_end(a, 1)
#define RARRAY_PTR_USE_TRANSIENT(ary, ptr_name, expr) \
    RBIMPL_RARRAY_STMT(1, ary, ptr_name, expr)

static inline VALUE *
RARRAY_PTR(VALUE ary)
{
    RBIMPL_ASSERT_TYPE(ary, RUBY_T_ARRAY);

    VALUE tmp = RB_OBJ_WB_UNPROTECT_FOR(ARRAY, ary);
    return RBIMPL_CAST((VALUE *)RARRAY_CONST_PTR(tmp));
}

static inline void
RARRAY_ASET(VALUE ary, long i, VALUE v)
{
    RARRAY_PTR_USE_TRANSIENT(ary, ptr,
        RB_OBJ_WRITE(ary, &ptr[i], v));
}

/*
 * :FIXME: we want to convert RARRAY_AREF into an inline function (to add rooms
 * for more sanity checks).  However there were situations where the address of
 * this macro is taken i.e. &RARRAY_AREF(...).  They cannot be possible if this
 * is not a  macro.  Such usages are abuse, and  we eliminated them internally.
 * However we are afraid  of similar things to remain in  the wild.  This macro
 * remains as  it is due to  that.  If we could  warn such usages we  can set a
 * transition path, but currently no way is found to do so.
 */
#define RARRAY_AREF(a, i) RARRAY_CONST_PTR_TRANSIENT(a)[i]

#endif /* RBIMPL_RARRAY_H */
