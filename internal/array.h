#ifndef INTERNAL_ARRAY_H                                 /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_ARRAY_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Array.
 */
#include "ruby/internal/config.h"
#include <stddef.h>                 /* for size_t */
#include "internal/static_assert.h" /* for STATIC_ASSERT */
#include "ruby/internal/stdbool.h"         /* for bool */
#include "ruby/ruby.h"              /* for RARRAY_LEN */

#ifndef ARRAY_DEBUG
# define ARRAY_DEBUG (0+RUBY_DEBUG)
#endif

#define RARRAY_PTR_IN_USE_FLAG FL_USER14

/* array.c */
VALUE rb_ary_last(int, const VALUE *, VALUE);
void rb_ary_set_len(VALUE, long);
void rb_ary_delete_same(VALUE, VALUE);
VALUE rb_ary_tmp_new_fill(long capa);
VALUE rb_ary_at(VALUE, VALUE);
size_t rb_ary_memsize(VALUE);
VALUE rb_to_array_type(VALUE obj);
void rb_ary_cancel_sharing(VALUE ary);

static inline VALUE rb_ary_entry_internal(VALUE ary, long offset);
static inline bool ARY_PTR_USING_P(VALUE ary);
static inline void RARY_TRANSIENT_SET(VALUE ary);
static inline void RARY_TRANSIENT_UNSET(VALUE ary);

RUBY_SYMBOL_EXPORT_BEGIN
/* array.c (export) */
void rb_ary_detransient(VALUE a);
VALUE *rb_ary_ptr_use_start(VALUE ary);
void rb_ary_ptr_use_end(VALUE ary);
RUBY_SYMBOL_EXPORT_END

MJIT_SYMBOL_EXPORT_BEGIN
VALUE rb_ary_tmp_new_from_values(VALUE, long, const VALUE *);
VALUE rb_check_to_array(VALUE ary);
VALUE rb_ary_behead(VALUE, long);
VALUE rb_ary_aref1(VALUE ary, VALUE i);
MJIT_SYMBOL_EXPORT_END

static inline VALUE
rb_ary_entry_internal(VALUE ary, long offset)
{
    long len = RARRAY_LEN(ary);
    const VALUE *ptr = RARRAY_CONST_PTR_TRANSIENT(ary);
    if (len == 0) return Qnil;
    if (offset < 0) {
        offset += len;
        if (offset < 0) return Qnil;
    }
    else if (len <= offset) {
        return Qnil;
    }
    return ptr[offset];
}

static inline bool
ARY_PTR_USING_P(VALUE ary)
{
    return FL_TEST_RAW(ary, RARRAY_PTR_IN_USE_FLAG);
}

static inline void
RARY_TRANSIENT_SET(VALUE ary)
{
#if USE_TRANSIENT_HEAP
    FL_SET_RAW(ary, RARRAY_TRANSIENT_FLAG);
#endif
}

static inline void
RARY_TRANSIENT_UNSET(VALUE ary)
{
#if USE_TRANSIENT_HEAP
    FL_UNSET_RAW(ary, RARRAY_TRANSIENT_FLAG);
#endif
}

#undef rb_ary_new_from_args
#if RBIMPL_HAS_WARNING("-Wgnu-zero-variadic-macro-arguments")
# /* Skip it; clang -pedantic doesn't like the following */
#elif defined(__GNUC__) && defined(HAVE_VA_ARGS_MACRO)
#define rb_ary_new_from_args(n, ...) \
    __extension__ ({ \
        const VALUE args_to_new_ary[] = {__VA_ARGS__}; \
        if (__builtin_constant_p(n)) { \
            STATIC_ASSERT(rb_ary_new_from_args, numberof(args_to_new_ary) == (n)); \
        } \
        rb_ary_new_from_values(numberof(args_to_new_ary), args_to_new_ary); \
    })
#endif

#undef RARRAY_AREF
RBIMPL_ATTR_PURE_UNLESS_DEBUG()
RBIMPL_ATTR_ARTIFICIAL()
static inline VALUE
RARRAY_AREF(VALUE ary, long i)
{
    RBIMPL_ASSERT_TYPE(ary, RUBY_T_ARRAY);

    return RARRAY_CONST_PTR_TRANSIENT(ary)[i];
}

#endif /* INTERNAL_ARRAY_H */
