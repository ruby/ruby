#ifndef INTERNAL_ARRAY_H /* -*- C -*- */
#define INTERNAL_ARRAY_H
/**
 * @file
 * @brief      Internal header for Array.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* array.c */

#ifndef ARRAY_DEBUG
#define ARRAY_DEBUG (0+RUBY_DEBUG)
#endif

#ifdef ARRAY_DEBUG
#define RARRAY_PTR_IN_USE_FLAG FL_USER14
#define ARY_PTR_USING_P(ary) FL_TEST_RAW((ary), RARRAY_PTR_IN_USE_FLAG)
#else

/* disable debug function */
#undef  RARRAY_PTR_USE_START_TRANSIENT
#undef  RARRAY_PTR_USE_END_TRANSIENT
#define RARRAY_PTR_USE_START_TRANSIENT(a) ((VALUE *)RARRAY_CONST_PTR_TRANSIENT(a))
#define RARRAY_PTR_USE_END_TRANSIENT(a)
#define ARY_PTR_USING_P(ary) 0

#endif

#if USE_TRANSIENT_HEAP
#define RARY_TRANSIENT_SET(ary) FL_SET_RAW((ary), RARRAY_TRANSIENT_FLAG);
#define RARY_TRANSIENT_UNSET(ary) FL_UNSET_RAW((ary), RARRAY_TRANSIENT_FLAG);
#else
#undef RARRAY_TRANSIENT_P
#define RARRAY_TRANSIENT_P(a) 0
#define RARY_TRANSIENT_SET(ary) ((void)0)
#define RARY_TRANSIENT_UNSET(ary) ((void)0)
#endif

VALUE rb_ary_last(int, const VALUE *, VALUE);
void rb_ary_set_len(VALUE, long);
void rb_ary_delete_same(VALUE, VALUE);
VALUE rb_ary_tmp_new_fill(long capa);
VALUE rb_ary_at(VALUE, VALUE);
VALUE rb_ary_aref1(VALUE ary, VALUE i);
size_t rb_ary_memsize(VALUE);
VALUE rb_to_array_type(VALUE obj);
VALUE rb_check_to_array(VALUE ary);
VALUE rb_ary_tmp_new_from_values(VALUE, long, const VALUE *);
VALUE rb_ary_behead(VALUE, long);
#if defined(__GNUC__) && defined(HAVE_VA_ARGS_MACRO)
#define rb_ary_new_from_args(n, ...) \
    __extension__ ({ \
        const VALUE args_to_new_ary[] = {__VA_ARGS__}; \
        if (__builtin_constant_p(n)) { \
            STATIC_ASSERT(rb_ary_new_from_args, numberof(args_to_new_ary) == (n)); \
        } \
        rb_ary_new_from_values(numberof(args_to_new_ary), args_to_new_ary); \
    })
#endif

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

RUBY_SYMBOL_EXPORT_BEGIN
/* array.c (export) */
void rb_ary_detransient(VALUE a);
VALUE *rb_ary_ptr_use_start(VALUE ary);
void rb_ary_ptr_use_end(VALUE ary);
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_ARRAY_H */
