#ifndef INTERNAL_STRUCT_H /* -*- C -*- */
#define INTERNAL_STRUCT_H
/**
 * @file
 * @brief      Internal header for Struct.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

#define RSTRUCT_EMBED_LEN_MAX RSTRUCT_EMBED_LEN_MAX
#define RSTRUCT_EMBED_LEN_MASK RSTRUCT_EMBED_LEN_MASK
#define RSTRUCT_EMBED_LEN_SHIFT RSTRUCT_EMBED_LEN_SHIFT

enum {
    RSTRUCT_EMBED_LEN_MAX = RVALUE_EMBED_LEN_MAX,
    RSTRUCT_EMBED_LEN_MASK = (RUBY_FL_USER2|RUBY_FL_USER1),
    RSTRUCT_EMBED_LEN_SHIFT = (RUBY_FL_USHIFT+1),
    RSTRUCT_TRANSIENT_FLAG = FL_USER3,

    RSTRUCT_ENUM_END
};

#if USE_TRANSIENT_HEAP
#define RSTRUCT_TRANSIENT_P(st) FL_TEST_RAW((obj), RSTRUCT_TRANSIENT_FLAG)
#define RSTRUCT_TRANSIENT_SET(st) FL_SET_RAW((st), RSTRUCT_TRANSIENT_FLAG)
#define RSTRUCT_TRANSIENT_UNSET(st) FL_UNSET_RAW((st), RSTRUCT_TRANSIENT_FLAG)
#else
#define RSTRUCT_TRANSIENT_P(st) 0
#define RSTRUCT_TRANSIENT_SET(st) ((void)0)
#define RSTRUCT_TRANSIENT_UNSET(st) ((void)0)
#endif

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

#undef RSTRUCT_LEN
#undef RSTRUCT_PTR
#undef RSTRUCT_SET
#undef RSTRUCT_GET
#define RSTRUCT_EMBED_LEN(st)                               \
    (long)((RBASIC(st)->flags >> RSTRUCT_EMBED_LEN_SHIFT) & \
           (RSTRUCT_EMBED_LEN_MASK >> RSTRUCT_EMBED_LEN_SHIFT))
#define RSTRUCT_LEN(st) rb_struct_len(st)
#define RSTRUCT_LENINT(st) rb_long2int(RSTRUCT_LEN(st))
#define RSTRUCT_CONST_PTR(st) rb_struct_const_ptr(st)
#define RSTRUCT_PTR(st) ((VALUE *)RSTRUCT_CONST_PTR(RB_OBJ_WB_UNPROTECT_FOR(STRUCT, st)))
#define RSTRUCT_SET(st, idx, v) RB_OBJ_WRITE(st, &RSTRUCT_CONST_PTR(st)[idx], (v))
#define RSTRUCT_GET(st, idx)    (RSTRUCT_CONST_PTR(st)[idx])
#define RSTRUCT(obj) (R_CAST(RStruct)(obj))

/* struct.c */
VALUE rb_struct_init_copy(VALUE copy, VALUE s);
VALUE rb_struct_lookup(VALUE s, VALUE idx);
VALUE rb_struct_s_keyword_init(VALUE klass);

static inline long
rb_struct_len(VALUE st)
{
    return (RBASIC(st)->flags & RSTRUCT_EMBED_LEN_MASK) ?
        RSTRUCT_EMBED_LEN(st) : RSTRUCT(st)->as.heap.len;
}

static inline const VALUE *
rb_struct_const_ptr(VALUE st)
{
    return FIX_CONST_VALUE_PTR((RBASIC(st)->flags & RSTRUCT_EMBED_LEN_MASK) ?
        RSTRUCT(st)->as.ary : RSTRUCT(st)->as.heap.ptr);
}

static inline const VALUE *
rb_struct_const_heap_ptr(VALUE st)
{
    /* TODO: check embed on debug mode */
    return RSTRUCT(st)->as.heap.ptr;
}

#endif /* INTERNAL_STRUCT_H */
