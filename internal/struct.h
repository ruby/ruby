#ifndef INTERNAL_STRUCT_H                                /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_STRUCT_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Struct.
 */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "internal/gc.h"        /* for RB_OBJ_WRITE */
#include "ruby/ruby.h"          /* for struct RBasic */

enum {
    RSTRUCT_EMBED_LEN_MAX = RVALUE_EMBED_LEN_MAX,
    RSTRUCT_EMBED_LEN_MASK = (RUBY_FL_USER2|RUBY_FL_USER1),
    RSTRUCT_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+1),
    RSTRUCT_TRANSIENT_FLAG = FL_USER3,
};

struct RStruct {
    struct RBasic basic;
    union {
        struct {
            long len;
            const VALUE *ptr;
        } heap;
        const VALUE ary[RSTRUCT_EMBED_LEN_MAX];
    } as;
};

#define RSTRUCT(obj) ((struct RStruct *)(obj))

#ifdef RSTRUCT_LEN
# undef RSTRUCT_LEN
#endif

#ifdef RSTRUCT_PTR
# undef RSTRUCT_PTR
#endif

#ifdef RSTRUCT_SET
# undef RSTRUCT_SET
#endif

#ifdef RSTRUCT_GET
# undef RSTRUCT_GET
#endif

#define RSTRUCT_LEN internal_RSTRUCT_LEN
#define RSTRUCT_SET internal_RSTRUCT_SET
#define RSTRUCT_GET internal_RSTRUCT_GET

/* struct.c */
VALUE rb_struct_init_copy(VALUE copy, VALUE s);
VALUE rb_struct_lookup(VALUE s, VALUE idx);
VALUE rb_struct_s_keyword_init(VALUE klass);
static inline const VALUE *rb_struct_const_heap_ptr(VALUE st);
static inline bool RSTRUCT_TRANSIENT_P(VALUE st);
static inline void RSTRUCT_TRANSIENT_SET(VALUE st);
static inline void RSTRUCT_TRANSIENT_UNSET(VALUE st);
static inline long RSTRUCT_EMBED_LEN(VALUE st);
static inline long RSTRUCT_LEN(VALUE st);
static inline int RSTRUCT_LENINT(VALUE st);
static inline const VALUE *RSTRUCT_CONST_PTR(VALUE st);
static inline void RSTRUCT_SET(VALUE st, long k, VALUE v);
static inline VALUE RSTRUCT_GET(VALUE st, long k);

static inline bool
RSTRUCT_TRANSIENT_P(VALUE st)
{
#if USE_TRANSIENT_HEAP
    return FL_TEST_RAW(st, RSTRUCT_TRANSIENT_FLAG);
#else
    return false;
#endif
}

static inline void
RSTRUCT_TRANSIENT_SET(VALUE st)
{
#if USE_TRANSIENT_HEAP
    FL_SET_RAW(st, RSTRUCT_TRANSIENT_FLAG);
#endif
}

static inline void
RSTRUCT_TRANSIENT_UNSET(VALUE st)
{
#if USE_TRANSIENT_HEAP
    FL_UNSET_RAW(st, RSTRUCT_TRANSIENT_FLAG);
#endif
}

static inline long
RSTRUCT_EMBED_LEN(VALUE st)
{
    long ret = FL_TEST_RAW(st, RSTRUCT_EMBED_LEN_MASK);
    ret >>= RSTRUCT_EMBED_LEN_SHIFT;
    return ret;
}

static inline long
RSTRUCT_LEN(VALUE st)
{
    if (FL_TEST_RAW(st, RSTRUCT_EMBED_LEN_MASK)) {
        return RSTRUCT_EMBED_LEN(st);
    }
    else {
        return RSTRUCT(st)->as.heap.len;
    }
}

static inline int
RSTRUCT_LENINT(VALUE st)
{
    return rb_long2int(RSTRUCT_LEN(st));
}

static inline const VALUE *
RSTRUCT_CONST_PTR(VALUE st)
{
    const struct RStruct *p = RSTRUCT(st);

    if (FL_TEST_RAW(st, RSTRUCT_EMBED_LEN_MASK)) {
        return p->as.ary;
    }
    else {
        return p->as.heap.ptr;
    }
}

static inline void
RSTRUCT_SET(VALUE st, long k,  VALUE v)
{
    RB_OBJ_WRITE(st, &RSTRUCT_CONST_PTR(st)[k], v);
}

static inline VALUE
RSTRUCT_GET(VALUE st, long k)
{
    return RSTRUCT_CONST_PTR(st)[k];
}

static inline const VALUE *
rb_struct_const_heap_ptr(VALUE st)
{
    /* TODO: check embed on debug mode */
    return RSTRUCT(st)->as.heap.ptr;
}

#endif /* INTERNAL_STRUCT_H */
