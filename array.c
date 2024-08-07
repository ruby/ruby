/**********************************************************************

  array.c -

  $Author$
  created at: Fri Aug  6 09:46:12 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "debug_counter.h"
#include "id.h"
#include "internal.h"
#include "internal/array.h"
#include "internal/compar.h"
#include "internal/enum.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/rational.h"
#include "internal/vm.h"
#include "probes.h"
#include "ruby/encoding.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "vm_core.h"
#include "builtin.h"

#if !ARRAY_DEBUG
# undef NDEBUG
# define NDEBUG
#endif
#include "ruby_assert.h"

VALUE rb_cArray;

/* Flags of RArray
 *
 * 1:   RARRAY_EMBED_FLAG
 *          The array is embedded (its contents follow the header, rather than
 *          being on a separately allocated buffer).
 * 2:   RARRAY_SHARED_FLAG (equal to ELTS_SHARED)
 *          The array is shared. The buffer this array points to is owned by
 *          another array (the shared root).
 * 3-9: RARRAY_EMBED_LEN
 *          The length of the array when RARRAY_EMBED_FLAG is set.
 * 12:  RARRAY_SHARED_ROOT_FLAG
 *          The array is a shared root that does reference counting. The buffer
 *          this array points to is owned by this array but may be pointed to
 *          by other arrays.
 *          Note: Frozen arrays may be a shared root without this flag being
 *                set. Frozen arrays do not have reference counting because
 *                they cannot be modified. Not updating the reference count
 *                improves copy-on-write performance. Their reference count is
 *                assumed to be infinity.
 * 14:  RARRAY_PTR_IN_USE_FLAG
 *          The buffer of the array is in use. This is only used during
 *          debugging.
 */

/* for OPTIMIZED_CMP: */
#define id_cmp idCmp

#define ARY_DEFAULT_SIZE 16
#define ARY_MAX_SIZE (LONG_MAX / (int)sizeof(VALUE))
#define SMALL_ARRAY_LEN 16

RBIMPL_ATTR_MAYBE_UNUSED()
static int
should_be_T_ARRAY(VALUE ary)
{
    return RB_TYPE_P(ary, T_ARRAY);
}

#define ARY_HEAP_PTR(a) (RUBY_ASSERT(!ARY_EMBED_P(a)), RARRAY(a)->as.heap.ptr)
#define ARY_HEAP_LEN(a) (RUBY_ASSERT(!ARY_EMBED_P(a)), RARRAY(a)->as.heap.len)
#define ARY_HEAP_CAPA(a) (RUBY_ASSERT(!ARY_EMBED_P(a)), RUBY_ASSERT(!ARY_SHARED_ROOT_P(a)), \
                          RARRAY(a)->as.heap.aux.capa)

#define ARY_EMBED_PTR(a) (RUBY_ASSERT(ARY_EMBED_P(a)), RARRAY(a)->as.ary)
#define ARY_EMBED_LEN(a) \
    (RUBY_ASSERT(ARY_EMBED_P(a)), \
     (long)((RBASIC(a)->flags >> RARRAY_EMBED_LEN_SHIFT) & \
         (RARRAY_EMBED_LEN_MASK >> RARRAY_EMBED_LEN_SHIFT)))
#define ARY_HEAP_SIZE(a) (RUBY_ASSERT(!ARY_EMBED_P(a)), RUBY_ASSERT(ARY_OWNS_HEAP_P(a)), ARY_CAPA(a) * sizeof(VALUE))

#define ARY_OWNS_HEAP_P(a) (RUBY_ASSERT(should_be_T_ARRAY((VALUE)(a))), \
                            !FL_TEST_RAW((a), RARRAY_SHARED_FLAG|RARRAY_EMBED_FLAG))

#define FL_SET_EMBED(a) do { \
    RUBY_ASSERT(!ARY_SHARED_P(a)); \
    FL_SET((a), RARRAY_EMBED_FLAG); \
    ary_verify(a); \
} while (0)

#define FL_UNSET_EMBED(ary) FL_UNSET((ary), RARRAY_EMBED_FLAG|RARRAY_EMBED_LEN_MASK)
#define FL_SET_SHARED(ary) do { \
    RUBY_ASSERT(!ARY_EMBED_P(ary)); \
    FL_SET((ary), RARRAY_SHARED_FLAG); \
} while (0)
#define FL_UNSET_SHARED(ary) FL_UNSET((ary), RARRAY_SHARED_FLAG)

#define ARY_SET_PTR(ary, p) do { \
    RUBY_ASSERT(!ARY_EMBED_P(ary)); \
    RUBY_ASSERT(!OBJ_FROZEN(ary)); \
    RARRAY(ary)->as.heap.ptr = (p); \
} while (0)
#define ARY_SET_EMBED_LEN(ary, n) do { \
    long tmp_n = (n); \
    RUBY_ASSERT(ARY_EMBED_P(ary)); \
    RBASIC(ary)->flags &= ~RARRAY_EMBED_LEN_MASK; \
    RBASIC(ary)->flags |= (tmp_n) << RARRAY_EMBED_LEN_SHIFT; \
} while (0)
#define ARY_SET_HEAP_LEN(ary, n) do { \
    RUBY_ASSERT(!ARY_EMBED_P(ary)); \
    RARRAY(ary)->as.heap.len = (n); \
} while (0)
#define ARY_SET_LEN(ary, n) do { \
    if (ARY_EMBED_P(ary)) { \
        ARY_SET_EMBED_LEN((ary), (n)); \
    } \
    else { \
        ARY_SET_HEAP_LEN((ary), (n)); \
    } \
    RUBY_ASSERT(RARRAY_LEN(ary) == (n)); \
} while (0)
#define ARY_INCREASE_PTR(ary, n) do  { \
    RUBY_ASSERT(!ARY_EMBED_P(ary)); \
    RUBY_ASSERT(!OBJ_FROZEN(ary)); \
    RARRAY(ary)->as.heap.ptr += (n); \
} while (0)
#define ARY_INCREASE_LEN(ary, n) do  { \
    RUBY_ASSERT(!OBJ_FROZEN(ary)); \
    if (ARY_EMBED_P(ary)) { \
        ARY_SET_EMBED_LEN((ary), RARRAY_LEN(ary)+(n)); \
    } \
    else { \
        RARRAY(ary)->as.heap.len += (n); \
    } \
} while (0)

#define ARY_CAPA(ary) (ARY_EMBED_P(ary) ? ary_embed_capa(ary) : \
                       ARY_SHARED_ROOT_P(ary) ? RARRAY_LEN(ary) : ARY_HEAP_CAPA(ary))
#define ARY_SET_CAPA(ary, n) do { \
    RUBY_ASSERT(!ARY_EMBED_P(ary)); \
    RUBY_ASSERT(!ARY_SHARED_P(ary)); \
    RUBY_ASSERT(!OBJ_FROZEN(ary)); \
    RARRAY(ary)->as.heap.aux.capa = (n); \
} while (0)

#define ARY_SHARED_ROOT_OCCUPIED(ary) (!OBJ_FROZEN(ary) && ARY_SHARED_ROOT_REFCNT(ary) == 1)
#define ARY_SET_SHARED_ROOT_REFCNT(ary, value) do { \
    RUBY_ASSERT(ARY_SHARED_ROOT_P(ary)); \
    RUBY_ASSERT(!OBJ_FROZEN(ary)); \
    RUBY_ASSERT((value) >= 0); \
    RARRAY(ary)->as.heap.aux.capa = (value); \
} while (0)
#define FL_SET_SHARED_ROOT(ary) do { \
    RUBY_ASSERT(!OBJ_FROZEN(ary)); \
    RUBY_ASSERT(!ARY_EMBED_P(ary)); \
    FL_SET((ary), RARRAY_SHARED_ROOT_FLAG); \
} while (0)

static inline void
ARY_SET(VALUE a, long i, VALUE v)
{
    RUBY_ASSERT(!ARY_SHARED_P(a));
    RUBY_ASSERT(!OBJ_FROZEN(a));

    RARRAY_ASET(a, i, v);
}
#undef RARRAY_ASET

static long
ary_embed_capa(VALUE ary)
{
    size_t size = rb_gc_obj_slot_size(ary) - offsetof(struct RArray, as.ary);
    RUBY_ASSERT(size % sizeof(VALUE) == 0);
    return size / sizeof(VALUE);
}

static size_t
ary_embed_size(long capa)
{
    return offsetof(struct RArray, as.ary) + (sizeof(VALUE) * capa);
}

static bool
ary_embeddable_p(long capa)
{
    return rb_gc_size_allocatable_p(ary_embed_size(capa));
}

bool
rb_ary_embeddable_p(VALUE ary)
{
    /* An array cannot be turned embeddable when the array is:
     *  - Shared root: other objects may point to the buffer of this array
     *    so we cannot make it embedded.
     *  - Frozen: this array may also be a shared root without the shared root
     *    flag.
     *  - Shared: we don't want to re-embed an array that points to a shared
     *    root (to save memory).
     */
    return !(ARY_SHARED_ROOT_P(ary) || OBJ_FROZEN(ary) || ARY_SHARED_P(ary));
}

size_t
rb_ary_size_as_embedded(VALUE ary)
{
    size_t real_size;

    if (ARY_EMBED_P(ary)) {
        real_size = ary_embed_size(ARY_EMBED_LEN(ary));
    }
    else if (rb_ary_embeddable_p(ary)) {
        real_size = ary_embed_size(ARY_HEAP_CAPA(ary));
    }
    else {
        real_size = sizeof(struct RArray);
    }
    return real_size;
}


#if ARRAY_DEBUG
#define ary_verify(ary) ary_verify_(ary, __FILE__, __LINE__)

static VALUE
ary_verify_(VALUE ary, const char *file, int line)
{
    RUBY_ASSERT(RB_TYPE_P(ary, T_ARRAY));

    if (ARY_SHARED_P(ary)) {
        VALUE root = ARY_SHARED_ROOT(ary);
        const VALUE *ptr = ARY_HEAP_PTR(ary);
        const VALUE *root_ptr = RARRAY_CONST_PTR(root);
        long len = ARY_HEAP_LEN(ary), root_len = RARRAY_LEN(root);
        RUBY_ASSERT(ARY_SHARED_ROOT_P(root) || OBJ_FROZEN(root));
        RUBY_ASSERT(root_ptr <= ptr && ptr + len <= root_ptr + root_len);
        ary_verify(root);
    }
    else if (ARY_EMBED_P(ary)) {
        RUBY_ASSERT(!ARY_SHARED_P(ary));
        RUBY_ASSERT(RARRAY_LEN(ary) <= ary_embed_capa(ary));
    }
    else {
        const VALUE *ptr = RARRAY_CONST_PTR(ary);
        long i, len = RARRAY_LEN(ary);
        volatile VALUE v;
        if (len > 1) len = 1; /* check only HEAD */
        for (i=0; i<len; i++) {
            v = ptr[i]; /* access check */
        }
        v = v;
    }

    return ary;
}

void
rb_ary_verify(VALUE ary)
{
    ary_verify(ary);
}
#else
#define ary_verify(ary) ((void)0)
#endif

VALUE *
rb_ary_ptr_use_start(VALUE ary)
{
#if ARRAY_DEBUG
    FL_SET_RAW(ary, RARRAY_PTR_IN_USE_FLAG);
#endif
    return (VALUE *)RARRAY_CONST_PTR(ary);
}

void
rb_ary_ptr_use_end(VALUE ary)
{
#if ARRAY_DEBUG
    FL_UNSET_RAW(ary, RARRAY_PTR_IN_USE_FLAG);
#endif
}

void
rb_mem_clear(VALUE *mem, long size)
{
    while (size--) {
        *mem++ = Qnil;
    }
}

static void
ary_mem_clear(VALUE ary, long beg, long size)
{
    RARRAY_PTR_USE(ary, ptr, {
        rb_mem_clear(ptr + beg, size);
    });
}

static inline void
memfill(register VALUE *mem, register long size, register VALUE val)
{
    while (size--) {
        *mem++ = val;
    }
}

static void
ary_memfill(VALUE ary, long beg, long size, VALUE val)
{
    RARRAY_PTR_USE(ary, ptr, {
        memfill(ptr + beg, size, val);
        RB_OBJ_WRITTEN(ary, Qundef, val);
    });
}

static void
ary_memcpy0(VALUE ary, long beg, long argc, const VALUE *argv, VALUE buff_owner_ary)
{
    RUBY_ASSERT(!ARY_SHARED_P(buff_owner_ary));

    if (argc > (int)(128/sizeof(VALUE)) /* is magic number (cache line size) */) {
        rb_gc_writebarrier_remember(buff_owner_ary);
        RARRAY_PTR_USE(ary, ptr, {
            MEMCPY(ptr+beg, argv, VALUE, argc);
        });
    }
    else {
        int i;
        RARRAY_PTR_USE(ary, ptr, {
            for (i=0; i<argc; i++) {
                RB_OBJ_WRITE(buff_owner_ary, &ptr[i+beg], argv[i]);
            }
        });
    }
}

static void
ary_memcpy(VALUE ary, long beg, long argc, const VALUE *argv)
{
    ary_memcpy0(ary, beg, argc, argv, ary);
}

static VALUE *
ary_heap_alloc_buffer(size_t capa)
{
    return ALLOC_N(VALUE, capa);
}

static void
ary_heap_free_ptr(VALUE ary, const VALUE *ptr, long size)
{
    ruby_sized_xfree((void *)ptr, size);
}

static void
ary_heap_free(VALUE ary)
{
    ary_heap_free_ptr(ary, ARY_HEAP_PTR(ary), ARY_HEAP_SIZE(ary));
}

static size_t
ary_heap_realloc(VALUE ary, size_t new_capa)
{
    RUBY_ASSERT(!OBJ_FROZEN(ary));
    SIZED_REALLOC_N(RARRAY(ary)->as.heap.ptr, VALUE, new_capa, ARY_HEAP_CAPA(ary));
    ary_verify(ary);

    return new_capa;
}

void
rb_ary_make_embedded(VALUE ary)
{
    RUBY_ASSERT(rb_ary_embeddable_p(ary));
    if (!ARY_EMBED_P(ary)) {
        const VALUE *buf = ARY_HEAP_PTR(ary);
        long len = ARY_HEAP_LEN(ary);

        FL_SET_EMBED(ary);
        ARY_SET_EMBED_LEN(ary, len);

        MEMCPY((void *)ARY_EMBED_PTR(ary), (void *)buf, VALUE, len);

        ary_heap_free_ptr(ary, buf, len * sizeof(VALUE));
    }
}

static void
ary_resize_capa(VALUE ary, long capacity)
{
    RUBY_ASSERT(RARRAY_LEN(ary) <= capacity);
    RUBY_ASSERT(!OBJ_FROZEN(ary));
    RUBY_ASSERT(!ARY_SHARED_P(ary));

    if (capacity > ary_embed_capa(ary)) {
        size_t new_capa = capacity;
        if (ARY_EMBED_P(ary)) {
            long len = ARY_EMBED_LEN(ary);
            VALUE *ptr = ary_heap_alloc_buffer(capacity);

            MEMCPY(ptr, ARY_EMBED_PTR(ary), VALUE, len);
            FL_UNSET_EMBED(ary);
            ARY_SET_PTR(ary, ptr);
            ARY_SET_HEAP_LEN(ary, len);
        }
        else {
            new_capa = ary_heap_realloc(ary, capacity);
        }
        ARY_SET_CAPA(ary, new_capa);
    }
    else {
        if (!ARY_EMBED_P(ary)) {
            long len = ARY_HEAP_LEN(ary);
            long old_capa = ARY_HEAP_CAPA(ary);
            const VALUE *ptr = ARY_HEAP_PTR(ary);

            if (len > capacity) len = capacity;
            MEMCPY((VALUE *)RARRAY(ary)->as.ary, ptr, VALUE, len);
            ary_heap_free_ptr(ary, ptr, old_capa);

            FL_SET_EMBED(ary);
            ARY_SET_LEN(ary, len);
        }
    }

    ary_verify(ary);
}

static inline void
ary_shrink_capa(VALUE ary)
{
    long capacity = ARY_HEAP_LEN(ary);
    long old_capa = ARY_HEAP_CAPA(ary);
    RUBY_ASSERT(!ARY_SHARED_P(ary));
    RUBY_ASSERT(old_capa >= capacity);
    if (old_capa > capacity) {
        size_t new_capa = ary_heap_realloc(ary, capacity);
        ARY_SET_CAPA(ary, new_capa);
    }

    ary_verify(ary);
}

static void
ary_double_capa(VALUE ary, long min)
{
    long new_capa = ARY_CAPA(ary) / 2;

    if (new_capa < ARY_DEFAULT_SIZE) {
        new_capa = ARY_DEFAULT_SIZE;
    }
    if (new_capa >= ARY_MAX_SIZE - min) {
        new_capa = (ARY_MAX_SIZE - min) / 2;
    }
    new_capa += min;
    ary_resize_capa(ary, new_capa);

    ary_verify(ary);
}

static void
rb_ary_decrement_share(VALUE shared_root)
{
    if (!OBJ_FROZEN(shared_root)) {
        long num = ARY_SHARED_ROOT_REFCNT(shared_root);
        ARY_SET_SHARED_ROOT_REFCNT(shared_root, num - 1);
    }
}

static void
rb_ary_unshare(VALUE ary)
{
    VALUE shared_root = ARY_SHARED_ROOT(ary);
    rb_ary_decrement_share(shared_root);
    FL_UNSET_SHARED(ary);
}

static void
rb_ary_reset(VALUE ary)
{
    if (ARY_OWNS_HEAP_P(ary)) {
        ary_heap_free(ary);
    }
    else if (ARY_SHARED_P(ary)) {
        rb_ary_unshare(ary);
    }

    FL_SET_EMBED(ary);
    ARY_SET_EMBED_LEN(ary, 0);
}

static VALUE
rb_ary_increment_share(VALUE shared_root)
{
    if (!OBJ_FROZEN(shared_root)) {
        long num = ARY_SHARED_ROOT_REFCNT(shared_root);
        RUBY_ASSERT(num >= 0);
        ARY_SET_SHARED_ROOT_REFCNT(shared_root, num + 1);
    }
    return shared_root;
}

static void
rb_ary_set_shared(VALUE ary, VALUE shared_root)
{
    RUBY_ASSERT(!ARY_EMBED_P(ary));
    RUBY_ASSERT(!OBJ_FROZEN(ary));
    RUBY_ASSERT(ARY_SHARED_ROOT_P(shared_root) || OBJ_FROZEN(shared_root));

    rb_ary_increment_share(shared_root);
    FL_SET_SHARED(ary);
    RB_OBJ_WRITE(ary, &RARRAY(ary)->as.heap.aux.shared_root, shared_root);

    RB_DEBUG_COUNTER_INC(obj_ary_shared_create);
}

static inline void
rb_ary_modify_check(VALUE ary)
{
    rb_check_frozen(ary);
    ary_verify(ary);
}

void
rb_ary_cancel_sharing(VALUE ary)
{
    if (ARY_SHARED_P(ary)) {
        long shared_len, len = RARRAY_LEN(ary);
        VALUE shared_root = ARY_SHARED_ROOT(ary);

        ary_verify(shared_root);

        if (len <= ary_embed_capa(ary)) {
            const VALUE *ptr = ARY_HEAP_PTR(ary);
            FL_UNSET_SHARED(ary);
            FL_SET_EMBED(ary);
            MEMCPY((VALUE *)ARY_EMBED_PTR(ary), ptr, VALUE, len);
            rb_ary_decrement_share(shared_root);
            ARY_SET_EMBED_LEN(ary, len);
        }
        else if (ARY_SHARED_ROOT_OCCUPIED(shared_root) && len > ((shared_len = RARRAY_LEN(shared_root))>>1)) {
            long shift = RARRAY_CONST_PTR(ary) - RARRAY_CONST_PTR(shared_root);
            FL_UNSET_SHARED(ary);
            ARY_SET_PTR(ary, RARRAY_CONST_PTR(shared_root));
            ARY_SET_CAPA(ary, shared_len);
            RARRAY_PTR_USE(ary, ptr, {
                MEMMOVE(ptr, ptr+shift, VALUE, len);
            });
            FL_SET_EMBED(shared_root);
            rb_ary_decrement_share(shared_root);
        }
        else {
            VALUE *ptr = ary_heap_alloc_buffer(len);
            MEMCPY(ptr, ARY_HEAP_PTR(ary), VALUE, len);
            rb_ary_unshare(ary);
            ARY_SET_CAPA(ary, len);
            ARY_SET_PTR(ary, ptr);
        }

        rb_gc_writebarrier_remember(ary);
    }
    ary_verify(ary);
}

void
rb_ary_modify(VALUE ary)
{
    rb_ary_modify_check(ary);
    rb_ary_cancel_sharing(ary);
}

static VALUE
ary_ensure_room_for_push(VALUE ary, long add_len)
{
    long old_len = RARRAY_LEN(ary);
    long new_len = old_len + add_len;
    long capa;

    if (old_len > ARY_MAX_SIZE - add_len) {
        rb_raise(rb_eIndexError, "index %ld too big", new_len);
    }
    if (ARY_SHARED_P(ary)) {
        if (new_len > ary_embed_capa(ary)) {
            VALUE shared_root = ARY_SHARED_ROOT(ary);
            if (ARY_SHARED_ROOT_OCCUPIED(shared_root)) {
                if (ARY_HEAP_PTR(ary) - RARRAY_CONST_PTR(shared_root) + new_len <= RARRAY_LEN(shared_root)) {
                    rb_ary_modify_check(ary);

                    ary_verify(ary);
                    ary_verify(shared_root);
                    return shared_root;
                }
                else {
                    /* if array is shared, then it is likely it participate in push/shift pattern */
                    rb_ary_modify(ary);
                    capa = ARY_CAPA(ary);
                    if (new_len > capa - (capa >> 6)) {
                        ary_double_capa(ary, new_len);
                    }
                    ary_verify(ary);
                    return ary;
                }
            }
        }
        ary_verify(ary);
        rb_ary_modify(ary);
    }
    else {
        rb_ary_modify_check(ary);
    }
    capa = ARY_CAPA(ary);
    if (new_len > capa) {
        ary_double_capa(ary, new_len);
    }

    ary_verify(ary);
    return ary;
}

/*
 *  call-seq:
 *    array.freeze -> self
 *
 *  Freezes +self+; returns +self+:
 *
 *    a = []
 *    a.frozen? # => false
 *    a.freeze
 *    a.frozen? # => true
 *
 *  An attempt to modify a frozen +Array+ raises FrozenError.
 */

VALUE
rb_ary_freeze(VALUE ary)
{
    RUBY_ASSERT(RB_TYPE_P(ary, T_ARRAY));

    if (OBJ_FROZEN(ary)) return ary;

    if (!ARY_EMBED_P(ary) && !ARY_SHARED_P(ary) && !ARY_SHARED_ROOT_P(ary)) {
        ary_shrink_capa(ary);
    }

    return rb_obj_freeze(ary);
}

/* This can be used to take a snapshot of an array (with
   e.g. rb_ary_replace) and check later whether the array has been
   modified from the snapshot.  The snapshot is cheap, though if
   something does modify the array it will pay the cost of copying
   it.  If Array#pop or Array#shift has been called, the array will
   be still shared with the snapshot, but the array length will
   differ. */
VALUE
rb_ary_shared_with_p(VALUE ary1, VALUE ary2)
{
    if (!ARY_EMBED_P(ary1) && ARY_SHARED_P(ary1) &&
            !ARY_EMBED_P(ary2) && ARY_SHARED_P(ary2) &&
            ARY_SHARED_ROOT(ary1) == ARY_SHARED_ROOT(ary2) &&
            ARY_HEAP_LEN(ary1) == ARY_HEAP_LEN(ary2)) {
        return Qtrue;
    }
    return Qfalse;
}

static VALUE
ary_alloc_embed(VALUE klass, long capa)
{
    size_t size = ary_embed_size(capa);
    RUBY_ASSERT(rb_gc_size_allocatable_p(size));
    NEWOBJ_OF(ary, struct RArray, klass,
                     T_ARRAY | RARRAY_EMBED_FLAG | (RGENGC_WB_PROTECTED_ARRAY ? FL_WB_PROTECTED : 0),
                     size, 0);
    /* Created array is:
     *   FL_SET_EMBED((VALUE)ary);
     *   ARY_SET_EMBED_LEN((VALUE)ary, 0);
     */
    return (VALUE)ary;
}

static VALUE
ary_alloc_heap(VALUE klass)
{
    NEWOBJ_OF(ary, struct RArray, klass,
                     T_ARRAY | (RGENGC_WB_PROTECTED_ARRAY ? FL_WB_PROTECTED : 0),
                     sizeof(struct RArray), 0);
    return (VALUE)ary;
}

static VALUE
empty_ary_alloc(VALUE klass)
{
    RUBY_DTRACE_CREATE_HOOK(ARRAY, 0);
    return ary_alloc_embed(klass, 0);
}

static VALUE
ary_new(VALUE klass, long capa)
{
    VALUE ary;

    if (capa < 0) {
        rb_raise(rb_eArgError, "negative array size (or size too big)");
    }
    if (capa > ARY_MAX_SIZE) {
        rb_raise(rb_eArgError, "array size too big");
    }

    RUBY_DTRACE_CREATE_HOOK(ARRAY, capa);

    if (ary_embeddable_p(capa)) {
        ary = ary_alloc_embed(klass, capa);
    }
    else {
        ary = ary_alloc_heap(klass);
        ARY_SET_CAPA(ary, capa);
        RUBY_ASSERT(!ARY_EMBED_P(ary));

        ARY_SET_PTR(ary, ary_heap_alloc_buffer(capa));
        ARY_SET_HEAP_LEN(ary, 0);
    }

    return ary;
}

VALUE
rb_ary_new_capa(long capa)
{
    return ary_new(rb_cArray, capa);
}

VALUE
rb_ary_new(void)
{
    return rb_ary_new_capa(0);
}

VALUE
(rb_ary_new_from_args)(long n, ...)
{
    va_list ar;
    VALUE ary;
    long i;

    ary = rb_ary_new2(n);

    va_start(ar, n);
    for (i=0; i<n; i++) {
        ARY_SET(ary, i, va_arg(ar, VALUE));
    }
    va_end(ar);

    ARY_SET_LEN(ary, n);
    return ary;
}

VALUE
rb_ary_tmp_new_from_values(VALUE klass, long n, const VALUE *elts)
{
    VALUE ary;

    ary = ary_new(klass, n);
    if (n > 0 && elts) {
        ary_memcpy(ary, 0, n, elts);
        ARY_SET_LEN(ary, n);
    }

    return ary;
}

VALUE
rb_ary_new_from_values(long n, const VALUE *elts)
{
    return rb_ary_tmp_new_from_values(rb_cArray, n, elts);
}

static VALUE
ec_ary_alloc_embed(rb_execution_context_t *ec, VALUE klass, long capa)
{
    size_t size = ary_embed_size(capa);
    RUBY_ASSERT(rb_gc_size_allocatable_p(size));
    NEWOBJ_OF(ary, struct RArray, klass,
            T_ARRAY | RARRAY_EMBED_FLAG | (RGENGC_WB_PROTECTED_ARRAY ? FL_WB_PROTECTED : 0),
            size, ec);
    /* Created array is:
     *   FL_SET_EMBED((VALUE)ary);
     *   ARY_SET_EMBED_LEN((VALUE)ary, 0);
     */
    return (VALUE)ary;
}

static VALUE
ec_ary_alloc_heap(rb_execution_context_t *ec, VALUE klass)
{
    NEWOBJ_OF(ary, struct RArray, klass,
            T_ARRAY | (RGENGC_WB_PROTECTED_ARRAY ? FL_WB_PROTECTED : 0),
            sizeof(struct RArray), ec);
    return (VALUE)ary;
}

static VALUE
ec_ary_new(rb_execution_context_t *ec, VALUE klass, long capa)
{
    VALUE ary;

    if (capa < 0) {
        rb_raise(rb_eArgError, "negative array size (or size too big)");
    }
    if (capa > ARY_MAX_SIZE) {
        rb_raise(rb_eArgError, "array size too big");
    }

    RUBY_DTRACE_CREATE_HOOK(ARRAY, capa);

    if (ary_embeddable_p(capa)) {
        ary = ec_ary_alloc_embed(ec, klass, capa);
    }
    else {
        ary = ec_ary_alloc_heap(ec, klass);
        ARY_SET_CAPA(ary, capa);
        RUBY_ASSERT(!ARY_EMBED_P(ary));

        ARY_SET_PTR(ary, ary_heap_alloc_buffer(capa));
        ARY_SET_HEAP_LEN(ary, 0);
    }

    return ary;
}

VALUE
rb_ec_ary_new_from_values(rb_execution_context_t *ec, long n, const VALUE *elts)
{
    VALUE ary;

    ary = ec_ary_new(ec, rb_cArray, n);
    if (n > 0 && elts) {
        ary_memcpy(ary, 0, n, elts);
        ARY_SET_LEN(ary, n);
    }

    return ary;
}

VALUE
rb_ary_hidden_new(long capa)
{
    VALUE ary = ary_new(0, capa);
    return ary;
}

VALUE
rb_ary_hidden_new_fill(long capa)
{
    VALUE ary = rb_ary_hidden_new(capa);
    ary_memfill(ary, 0, capa, Qnil);
    ARY_SET_LEN(ary, capa);
    return ary;
}

void
rb_ary_free(VALUE ary)
{
    if (ARY_OWNS_HEAP_P(ary)) {
        if (USE_DEBUG_COUNTER &&
            !ARY_SHARED_ROOT_P(ary) &&
            ARY_HEAP_CAPA(ary) > RARRAY_LEN(ary)) {
            RB_DEBUG_COUNTER_INC(obj_ary_extracapa);
        }

        RB_DEBUG_COUNTER_INC(obj_ary_ptr);
        ary_heap_free(ary);
    }
    else {
        RB_DEBUG_COUNTER_INC(obj_ary_embed);
    }

    if (ARY_SHARED_P(ary)) {
        RB_DEBUG_COUNTER_INC(obj_ary_shared);
    }
    if (ARY_SHARED_ROOT_P(ary) && ARY_SHARED_ROOT_OCCUPIED(ary)) {
        RB_DEBUG_COUNTER_INC(obj_ary_shared_root_occupied);
    }
}

VALUE
rb_setup_fake_ary(struct RArray *fake_ary, const VALUE *list, long len, bool freeze)
{
    fake_ary->basic.flags = T_ARRAY;
    VALUE ary = (VALUE)fake_ary;
    RBASIC_CLEAR_CLASS(ary);
    ARY_SET_PTR(ary, list);
    ARY_SET_HEAP_LEN(ary, len);
    ARY_SET_CAPA(ary, len);
    if (freeze) rb_ary_freeze(ary);
    return ary;
}

size_t
rb_ary_memsize(VALUE ary)
{
    if (ARY_OWNS_HEAP_P(ary)) {
        return ARY_CAPA(ary) * sizeof(VALUE);
    }
    else {
        return 0;
    }
}

static VALUE
ary_make_shared(VALUE ary)
{
    ary_verify(ary);

    if (ARY_SHARED_P(ary)) {
        return ARY_SHARED_ROOT(ary);
    }
    else if (ARY_SHARED_ROOT_P(ary)) {
        return ary;
    }
    else if (OBJ_FROZEN(ary)) {
        return ary;
    }
    else {
        long capa = ARY_CAPA(ary);
        long len = RARRAY_LEN(ary);

        /* Shared roots cannot be embedded because the reference count
         * (refcnt) is stored in as.heap.aux.capa. */
        VALUE shared = ary_alloc_heap(0);
        FL_SET_SHARED_ROOT(shared);

        if (ARY_EMBED_P(ary)) {
            VALUE *ptr = ary_heap_alloc_buffer(capa);
            ARY_SET_PTR(shared, ptr);
            ary_memcpy(shared, 0, len, RARRAY_CONST_PTR(ary));

            FL_UNSET_EMBED(ary);
            ARY_SET_HEAP_LEN(ary, len);
            ARY_SET_PTR(ary, ptr);
        }
        else {
            ARY_SET_PTR(shared, RARRAY_CONST_PTR(ary));
        }

        ARY_SET_LEN(shared, capa);
        ary_mem_clear(shared, len, capa - len);
        rb_ary_set_shared(ary, shared);

        ary_verify(shared);
        ary_verify(ary);

        return shared;
    }
}

static VALUE
ary_make_substitution(VALUE ary)
{
    long len = RARRAY_LEN(ary);

    if (ary_embeddable_p(len)) {
        VALUE subst = rb_ary_new_capa(len);
        RUBY_ASSERT(ARY_EMBED_P(subst));

        ary_memcpy(subst, 0, len, RARRAY_CONST_PTR(ary));
        ARY_SET_EMBED_LEN(subst, len);
        return subst;
    }
    else {
        return rb_ary_increment_share(ary_make_shared(ary));
    }
}

VALUE
rb_assoc_new(VALUE car, VALUE cdr)
{
    return rb_ary_new3(2, car, cdr);
}

VALUE
rb_to_array_type(VALUE ary)
{
    return rb_convert_type_with_id(ary, T_ARRAY, "Array", idTo_ary);
}
#define to_ary rb_to_array_type

VALUE
rb_check_array_type(VALUE ary)
{
    return rb_check_convert_type_with_id(ary, T_ARRAY, "Array", idTo_ary);
}

VALUE
rb_check_to_array(VALUE ary)
{
    return rb_check_convert_type_with_id(ary, T_ARRAY, "Array", idTo_a);
}

VALUE
rb_to_array(VALUE ary)
{
    return rb_convert_type_with_id(ary, T_ARRAY, "Array", idTo_a);
}

/*
 *  call-seq:
 *    Array.try_convert(object) -> object, new_array, or nil
 *
 *  Attempts to convert the given +object+ to an +Array+ object:
 *
 *  - If +object+ is an +Array+ object, returns +object+.
 *  - Otherwise if +object+ responds to <tt>:to_ary</tt>.
 *    calls <tt>object.to_ary</tt>:
 *
 *    - If the return value is an +Array+ or +nil+, returns that value.
 *    - Otherwise, raises TypeError.
 *
 *  - Otherwise returns +nil+.
 *
 */

static VALUE
rb_ary_s_try_convert(VALUE dummy, VALUE ary)
{
    return rb_check_array_type(ary);
}

/* :nodoc: */
static VALUE
rb_ary_s_new(int argc, VALUE *argv, VALUE klass)
{
    VALUE ary;

    if (klass == rb_cArray) {
        long size = 0;
        if (argc > 0 && FIXNUM_P(argv[0])) {
            size = FIX2LONG(argv[0]);
            if (size < 0) size = 0;
        }

        ary = ary_new(klass, size);

        rb_obj_call_init_kw(ary, argc, argv, RB_PASS_CALLED_KEYWORDS);
    }
    else {
        ary = rb_class_new_instance_pass_kw(argc, argv, klass);
    }

    return ary;
}

/*
 *  call-seq:
 *    Array.new -> new_empty_array
 *    Array.new(array) -> new_array
 *    Array.new(size, default_value = nil) -> new_array
 *    Array.new(size = 0) {|index| ... } -> new_array
 *
 *  Returns a new array.
 *
 *  With no block and no argument given, returns a new empty array:
 *
 *    Array.new # => []
 *
 *  With no block and array argument given, returns a new array with the same elements:
 *
 *    Array.new([:foo, 'bar', 2]) # => [:foo, "bar", 2]
 *
 *  With no block and integer argument given, returns a new array containing
 *  that many instances of the given +default_value+:
 *
 *    Array.new(0)    # => []
 *    Array.new(3)    # => [nil, nil, nil]
 *    Array.new(2, 3) # => [3, 3]
 *
 *  With a block given, returns an array of the given +size+;
 *  calls the block with each +index+ in the range <tt>(0...size)</tt>;
 *  the element at that +index+ in the returned array is the blocks return value:
 *
 *    Array.new(3)  {|index| "Element #{index}" } # => ["Element 0", "Element 1", "Element 2"]
 *
 *  A common pitfall for new Rubyists is providing an expression as +default_value+:
 *
 *    array = Array.new(2, {})
 *    array # => [{}, {}]
 *    array[0][:a] = 1
 *    array # => [{a: 1}, {a: 1}], as array[0] and array[1] are same object
 *
 *  If you want the elements of the array to be distinct, you should pass a block:
 *
 *    array = Array.new(2) { {} }
 *    array # => [{}, {}]
 *    array[0][:a] = 1
 *    array # => [{a: 1}, {}], as array[0] and array[1] are different objects
 *
 *  Raises TypeError if the first argument is not either an array
 *  or an {integer-convertible object}[rdoc-ref:implicit_conversion.rdoc@Integer-Convertible+Objects]).
 *  Raises ArgumentError if the first argument is a negative integer.
 */

static VALUE
rb_ary_initialize(int argc, VALUE *argv, VALUE ary)
{
    long len;
    VALUE size, val;

    rb_ary_modify(ary);
    if (argc == 0) {
        rb_ary_reset(ary);
        RUBY_ASSERT(ARY_EMBED_P(ary));
        RUBY_ASSERT(ARY_EMBED_LEN(ary) == 0);
        if (rb_block_given_p()) {
            rb_warning("given block not used");
        }
        return ary;
    }
    rb_scan_args(argc, argv, "02", &size, &val);
    if (argc == 1 && !FIXNUM_P(size)) {
        val = rb_check_array_type(size);
        if (!NIL_P(val)) {
            rb_ary_replace(ary, val);
            return ary;
        }
    }

    len = NUM2LONG(size);
    /* NUM2LONG() may call size.to_int, ary can be frozen, modified, etc */
    if (len < 0) {
        rb_raise(rb_eArgError, "negative array size");
    }
    if (len > ARY_MAX_SIZE) {
        rb_raise(rb_eArgError, "array size too big");
    }
    /* recheck after argument conversion */
    rb_ary_modify(ary);
    ary_resize_capa(ary, len);
    if (rb_block_given_p()) {
        long i;

        if (argc == 2) {
            rb_warn("block supersedes default value argument");
        }
        for (i=0; i<len; i++) {
            rb_ary_store(ary, i, rb_yield(LONG2NUM(i)));
            ARY_SET_LEN(ary, i + 1);
        }
    }
    else {
        ary_memfill(ary, 0, len, val);
        ARY_SET_LEN(ary, len);
    }
    return ary;
}

/*
 * Returns a new +Array+ object, populated with the given objects:
 *
 *   Array[1, 'a', /^A/]    # => [1, "a", /^A/]
 *   Array[]                # => []
 *   Array.[](1, 'a', /^A/) # => [1, "a", /^A/]
 *
 */

static VALUE
rb_ary_s_create(int argc, VALUE *argv, VALUE klass)
{
    VALUE ary = ary_new(klass, argc);
    if (argc > 0 && argv) {
        ary_memcpy(ary, 0, argc, argv);
        ARY_SET_LEN(ary, argc);
    }

    return ary;
}

void
rb_ary_store(VALUE ary, long idx, VALUE val)
{
    long len = RARRAY_LEN(ary);

    if (idx < 0) {
        idx += len;
        if (idx < 0) {
            rb_raise(rb_eIndexError, "index %ld too small for array; minimum: %ld",
                     idx - len, -len);
        }
    }
    else if (idx >= ARY_MAX_SIZE) {
        rb_raise(rb_eIndexError, "index %ld too big", idx);
    }

    rb_ary_modify(ary);
    if (idx >= ARY_CAPA(ary)) {
        ary_double_capa(ary, idx);
    }
    if (idx > len) {
        ary_mem_clear(ary, len, idx - len + 1);
    }

    if (idx >= len) {
        ARY_SET_LEN(ary, idx + 1);
    }
    ARY_SET(ary, idx, val);
}

static VALUE
ary_make_partial(VALUE ary, VALUE klass, long offset, long len)
{
    RUBY_ASSERT(offset >= 0);
    RUBY_ASSERT(len >= 0);
    RUBY_ASSERT(offset+len <= RARRAY_LEN(ary));

    VALUE result = ary_alloc_heap(klass);
    size_t embed_capa = ary_embed_capa(result);
    if ((size_t)len <= embed_capa) {
        FL_SET_EMBED(result);
        ary_memcpy(result, 0, len, RARRAY_CONST_PTR(ary) + offset);
        ARY_SET_EMBED_LEN(result, len);
    }
    else {
        VALUE shared = ary_make_shared(ary);

        /* The ary_make_shared call may allocate, which can trigger a GC
         * compaction. This can cause the array to be embedded because it has
         * a length of 0. */
        FL_UNSET_EMBED(result);

        ARY_SET_PTR(result, RARRAY_CONST_PTR(ary));
        ARY_SET_LEN(result, RARRAY_LEN(ary));
        rb_ary_set_shared(result, shared);

        ARY_INCREASE_PTR(result, offset);
        ARY_SET_LEN(result, len);

        ary_verify(shared);
    }

    ary_verify(result);
    return result;
}

static VALUE
ary_make_partial_step(VALUE ary, VALUE klass, long offset, long len, long step)
{
    RUBY_ASSERT(offset >= 0);
    RUBY_ASSERT(len >= 0);
    RUBY_ASSERT(offset+len <= RARRAY_LEN(ary));
    RUBY_ASSERT(step != 0);

    const long orig_len = len;

    if (step > 0 && step >= len) {
        VALUE result = ary_new(klass, 1);
        VALUE *ptr = (VALUE *)ARY_EMBED_PTR(result);
        const VALUE *values = RARRAY_CONST_PTR(ary);

        RB_OBJ_WRITE(result, ptr, values[offset]);
        ARY_SET_EMBED_LEN(result, 1);
        return result;
    }
    else if (step < 0 && step < -len) {
        step = -len;
    }

    long ustep = (step < 0) ? -step : step;
    len = roomof(len, ustep);

    long i;
    long j = offset + ((step > 0) ? 0 : (orig_len - 1));

    VALUE result = ary_new(klass, len);
    if (ARY_EMBED_P(result)) {
        VALUE *ptr = (VALUE *)ARY_EMBED_PTR(result);
        const VALUE *values = RARRAY_CONST_PTR(ary);

        for (i = 0; i < len; ++i) {
            RB_OBJ_WRITE(result, ptr+i, values[j]);
            j += step;
        }
        ARY_SET_EMBED_LEN(result, len);
    }
    else {
        const VALUE *values = RARRAY_CONST_PTR(ary);

        RARRAY_PTR_USE(result, ptr, {
            for (i = 0; i < len; ++i) {
                RB_OBJ_WRITE(result, ptr+i, values[j]);
                j += step;
            }
        });
        ARY_SET_LEN(result, len);
    }

    return result;
}

static VALUE
ary_make_shared_copy(VALUE ary)
{
    return ary_make_partial(ary, rb_cArray, 0, RARRAY_LEN(ary));
}

enum ary_take_pos_flags
{
    ARY_TAKE_FIRST = 0,
    ARY_TAKE_LAST = 1
};

static VALUE
ary_take_first_or_last_n(VALUE ary, long n, enum ary_take_pos_flags last)
{
    long len = RARRAY_LEN(ary);
    long offset = 0;

    if (n > len) {
        n = len;
    }
    else if (n < 0) {
        rb_raise(rb_eArgError, "negative array size");
    }
    if (last) {
        offset = len - n;
    }
    return ary_make_partial(ary, rb_cArray, offset, n);
}

static VALUE
ary_take_first_or_last(int argc, const VALUE *argv, VALUE ary, enum ary_take_pos_flags last)
{
    argc = rb_check_arity(argc, 0, 1);
    /* the case optional argument is omitted should be handled in
     * callers of this function.  if another arity case is added,
     * this arity check needs to rewrite. */
    RUBY_ASSERT_ALWAYS(argc == 1);
    return ary_take_first_or_last_n(ary, NUM2LONG(argv[0]), last);
}

/*
 *  call-seq:
 *    array << object -> self
 *
 *  Appends +object+ to +self+; returns +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a << :baz # => [:foo, "bar", 2, :baz]
 *
 *  Appends +object+ as one element, even if it is another +Array+:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a << [3, 4]
 *    a1 # => [:foo, "bar", 2, [3, 4]]
 *
 */

VALUE
rb_ary_push(VALUE ary, VALUE item)
{
    long idx = RARRAY_LEN((ary_verify(ary), ary));
    VALUE target_ary = ary_ensure_room_for_push(ary, 1);
    RARRAY_PTR_USE(ary, ptr, {
        RB_OBJ_WRITE(target_ary, &ptr[idx], item);
    });
    ARY_SET_LEN(ary, idx + 1);
    ary_verify(ary);
    return ary;
}

VALUE
rb_ary_cat(VALUE ary, const VALUE *argv, long len)
{
    long oldlen = RARRAY_LEN(ary);
    VALUE target_ary = ary_ensure_room_for_push(ary, len);
    ary_memcpy0(ary, oldlen, len, argv, target_ary);
    ARY_SET_LEN(ary, oldlen + len);
    return ary;
}

/*
 *  call-seq:
 *    array.push(*objects) -> self
 *
 *  Appends trailing elements.
 *
 *  Appends each argument in +objects+ to +self+;  returns +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.push(:baz, :bat) # => [:foo, "bar", 2, :baz, :bat]
 *
 *  Appends each argument as one element, even if it is another +Array+:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.push([:baz, :bat], [:bam, :bad])
 *    a1 # => [:foo, "bar", 2, [:baz, :bat], [:bam, :bad]]
 *
 *  Related: #pop, #shift, #unshift.
 */

static VALUE
rb_ary_push_m(int argc, VALUE *argv, VALUE ary)
{
    return rb_ary_cat(ary, argv, argc);
}

VALUE
rb_ary_pop(VALUE ary)
{
    long n;
    rb_ary_modify_check(ary);
    n = RARRAY_LEN(ary);
    if (n == 0) return Qnil;
    if (ARY_OWNS_HEAP_P(ary) &&
        n * 3 < ARY_CAPA(ary) &&
        ARY_CAPA(ary) > ARY_DEFAULT_SIZE)
    {
        ary_resize_capa(ary, n * 2);
    }
    --n;
    ARY_SET_LEN(ary, n);
    ary_verify(ary);
    return RARRAY_AREF(ary, n);
}

/*
 *  call-seq:
 *    array.pop -> object or nil
 *    array.pop(n) -> new_array
 *
 *  Removes and returns trailing elements.
 *
 *  When no argument is given and +self+ is not empty,
 *  removes and returns the last element:
 *
 *    a = [:foo, 'bar', 2]
 *    a.pop # => 2
 *    a # => [:foo, "bar"]
 *
 *  Returns +nil+ if the array is empty.
 *
 *  When a non-negative Integer argument +n+ is given and is in range,
 *
 *  removes and returns the last +n+ elements in a new +Array+:
 *    a = [:foo, 'bar', 2]
 *    a.pop(2) # => ["bar", 2]
 *
 *  If +n+ is positive and out of range,
 *  removes and returns all elements:
 *
 *    a = [:foo, 'bar', 2]
 *    a.pop(50) # => [:foo, "bar", 2]
 *
 *  Related: #push, #shift, #unshift.
 */

static VALUE
rb_ary_pop_m(int argc, VALUE *argv, VALUE ary)
{
    VALUE result;

    if (argc == 0) {
        return rb_ary_pop(ary);
    }

    rb_ary_modify_check(ary);
    result = ary_take_first_or_last(argc, argv, ary, ARY_TAKE_LAST);
    ARY_INCREASE_LEN(ary, -RARRAY_LEN(result));
    ary_verify(ary);
    return result;
}

VALUE
rb_ary_shift(VALUE ary)
{
    VALUE top;
    long len = RARRAY_LEN(ary);

    if (len == 0) {
        rb_ary_modify_check(ary);
        return Qnil;
    }

    top = RARRAY_AREF(ary, 0);

    rb_ary_behead(ary, 1);

    return top;
}

/*
 *  call-seq:
 *     array.shift -> object or nil
 *     array.shift(n) -> new_array
 *
 *  Removes and returns leading elements.
 *
 *  When no argument is given, removes and returns the first element:
 *
 *    a = [:foo, 'bar', 2]
 *    a.shift # => :foo
 *    a # => ['bar', 2]
 *
 *  Returns +nil+ if +self+ is empty.
 *
 *  When positive Integer argument +n+ is given, removes the first +n+ elements;
 *  returns those elements in a new +Array+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.shift(2) # => [:foo, 'bar']
 *    a # => [2]
 *
 *  If +n+ is as large as or larger than <tt>self.length</tt>,
 *  removes all elements; returns those elements in a new +Array+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.shift(3) # => [:foo, 'bar', 2]
 *
 *  If +n+ is zero, returns a new empty +Array+; +self+ is unmodified.
 *
 *  Related: #push, #pop, #unshift.
 */

static VALUE
rb_ary_shift_m(int argc, VALUE *argv, VALUE ary)
{
    VALUE result;
    long n;

    if (argc == 0) {
        return rb_ary_shift(ary);
    }

    rb_ary_modify_check(ary);
    result = ary_take_first_or_last(argc, argv, ary, ARY_TAKE_FIRST);
    n = RARRAY_LEN(result);
    rb_ary_behead(ary,n);

    return result;
}

VALUE
rb_ary_behead(VALUE ary, long n)
{
    if (n <= 0) {
        return ary;
    }

    rb_ary_modify_check(ary);

    if (!ARY_SHARED_P(ary)) {
        if (ARY_EMBED_P(ary) || RARRAY_LEN(ary) < ARY_DEFAULT_SIZE) {
            RARRAY_PTR_USE(ary, ptr, {
                MEMMOVE(ptr, ptr + n, VALUE, RARRAY_LEN(ary) - n);
            }); /* WB: no new reference */
            ARY_INCREASE_LEN(ary, -n);
            ary_verify(ary);
            return ary;
        }

        ary_mem_clear(ary, 0, n);
        ary_make_shared(ary);
    }
    else if (ARY_SHARED_ROOT_OCCUPIED(ARY_SHARED_ROOT(ary))) {
        ary_mem_clear(ary, 0, n);
    }

    ARY_INCREASE_PTR(ary, n);
    ARY_INCREASE_LEN(ary, -n);
    ary_verify(ary);

    return ary;
}

static VALUE
make_room_for_unshift(VALUE ary, const VALUE *head, VALUE *sharedp, int argc, long capa, long len)
{
    if (head - sharedp < argc) {
        long room = capa - len - argc;

        room -= room >> 4;
        MEMMOVE((VALUE *)sharedp + argc + room, head, VALUE, len);
        head = sharedp + argc + room;
    }
    ARY_SET_PTR(ary, head - argc);
    RUBY_ASSERT(ARY_SHARED_ROOT_OCCUPIED(ARY_SHARED_ROOT(ary)));

    ary_verify(ary);
    return ARY_SHARED_ROOT(ary);
}

static VALUE
ary_modify_for_unshift(VALUE ary, int argc)
{
    long len = RARRAY_LEN(ary);
    long new_len = len + argc;
    long capa;
    const VALUE *head, *sharedp;

    rb_ary_modify(ary);
    capa = ARY_CAPA(ary);
    if (capa - (capa >> 6) <= new_len) {
        ary_double_capa(ary, new_len);
    }

    /* use shared array for big "queues" */
    if (new_len > ARY_DEFAULT_SIZE * 4 && !ARY_EMBED_P(ary)) {
        ary_verify(ary);

        /* make a room for unshifted items */
        capa = ARY_CAPA(ary);
        ary_make_shared(ary);

        head = sharedp = RARRAY_CONST_PTR(ary);
        return make_room_for_unshift(ary, head, (void *)sharedp, argc, capa, len);
    }
    else {
        /* sliding items */
        RARRAY_PTR_USE(ary, ptr, {
            MEMMOVE(ptr + argc, ptr, VALUE, len);
        });

        ary_verify(ary);
        return ary;
    }
}

static VALUE
ary_ensure_room_for_unshift(VALUE ary, int argc)
{
    long len = RARRAY_LEN(ary);
    long new_len = len + argc;

    if (len > ARY_MAX_SIZE - argc) {
        rb_raise(rb_eIndexError, "index %ld too big", new_len);
    }
    else if (! ARY_SHARED_P(ary)) {
        return ary_modify_for_unshift(ary, argc);
    }
    else {
        VALUE shared_root = ARY_SHARED_ROOT(ary);
        long capa = RARRAY_LEN(shared_root);

        if (! ARY_SHARED_ROOT_OCCUPIED(shared_root)) {
            return ary_modify_for_unshift(ary, argc);
        }
        else if (new_len > capa) {
            return ary_modify_for_unshift(ary, argc);
        }
        else {
            const VALUE * head = RARRAY_CONST_PTR(ary);
            void *sharedp = (void *)RARRAY_CONST_PTR(shared_root);

            rb_ary_modify_check(ary);
            return make_room_for_unshift(ary, head, sharedp, argc, capa, len);
        }
    }
}

/*
 *  call-seq:
 *    array.unshift(*objects) -> self
 *
 *  Prepends the given +objects+ to +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.unshift(:bam, :bat) # => [:bam, :bat, :foo, "bar", 2]
 *
 *  Related: #push, #pop, #shift.
 */

VALUE
rb_ary_unshift_m(int argc, VALUE *argv, VALUE ary)
{
    long len = RARRAY_LEN(ary);
    VALUE target_ary;

    if (argc == 0) {
        rb_ary_modify_check(ary);
        return ary;
    }

    target_ary = ary_ensure_room_for_unshift(ary, argc);
    ary_memcpy0(ary, 0, argc, argv, target_ary);
    ARY_SET_LEN(ary, len + argc);
    return ary;
}

VALUE
rb_ary_unshift(VALUE ary, VALUE item)
{
    return rb_ary_unshift_m(1, &item, ary);
}

/* faster version - use this if you don't need to treat negative offset */
static inline VALUE
rb_ary_elt(VALUE ary, long offset)
{
    long len = RARRAY_LEN(ary);
    if (len == 0) return Qnil;
    if (offset < 0 || len <= offset) {
        return Qnil;
    }
    return RARRAY_AREF(ary, offset);
}

VALUE
rb_ary_entry(VALUE ary, long offset)
{
    return rb_ary_entry_internal(ary, offset);
}

VALUE
rb_ary_subseq_step(VALUE ary, long beg, long len, long step)
{
    VALUE klass;
    long alen = RARRAY_LEN(ary);

    if (beg > alen) return Qnil;
    if (beg < 0 || len < 0) return Qnil;

    if (alen < len || alen < beg + len) {
        len = alen - beg;
    }
    klass = rb_cArray;
    if (len == 0) return ary_new(klass, 0);
    if (step == 0)
        rb_raise(rb_eArgError, "slice step cannot be zero");
    if (step == 1)
        return ary_make_partial(ary, klass, beg, len);
    else
        return ary_make_partial_step(ary, klass, beg, len, step);
}

VALUE
rb_ary_subseq(VALUE ary, long beg, long len)
{
    return rb_ary_subseq_step(ary, beg, len, 1);
}

static VALUE rb_ary_aref2(VALUE ary, VALUE b, VALUE e);

/*
 *  call-seq:
 *    array[index] -> object or nil
 *    array[start, length] -> object or nil
 *    array[range] -> object or nil
 *    array[aseq] -> object or nil
 *    array.slice(index) -> object or nil
 *    array.slice(start, length) -> object or nil
 *    array.slice(range) -> object or nil
 *    array.slice(aseq) -> object or nil
 *
 *  Returns elements from +self+; does not modify +self+.
 *
 *  In brief:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0]     # => :foo
 *    a[-1]    # => 2
 *    a[1, 2]  # => ["bar", 2]
 *    a[0..1]  # => [:foo, "bar"]
 *    a[0..-2] # => [:foo, "bar"]
 *    a[-2..2] # => ["bar", 2]
 *
 *  When a single Integer argument +index+ is given, returns the element at offset +index+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0] # => :foo
 *    a[2] # => 2
 *    a # => [:foo, "bar", 2]
 *
 *  If +index+ is negative, counts relative to the end of +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[-1] # => 2
 *    a[-2] # => "bar"
 *
 *  If +index+ is out of range, returns +nil+.
 *
 *  When two Integer arguments +start+ and +length+ are given,
 *  returns a new +Array+ of size +length+ containing successive elements beginning at offset +start+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0, 2] # => [:foo, "bar"]
 *    a[1, 2] # => ["bar", 2]
 *
 *  If <tt>start + length</tt> is greater than <tt>self.length</tt>,
 *  returns all elements from offset +start+ to the end:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0, 4] # => [:foo, "bar", 2]
 *    a[1, 3] # => ["bar", 2]
 *    a[2, 2] # => [2]
 *
 *  If <tt>start == self.size</tt> and <tt>length >= 0</tt>,
 *  returns a new empty +Array+.
 *
 *  If +length+ is negative, returns +nil+.
 *
 *  When a single Range argument +range+ is given,
 *  treats <tt>range.min</tt> as +start+ above
 *  and <tt>range.size</tt> as +length+ above:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0..1] # => [:foo, "bar"]
 *    a[1..2] # => ["bar", 2]
 *
 *  Special case: If <tt>range.start == a.size</tt>, returns a new empty +Array+.
 *
 *  If <tt>range.end</tt> is negative, calculates the end index from the end:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0..-1] # => [:foo, "bar", 2]
 *    a[0..-2] # => [:foo, "bar"]
 *    a[0..-3] # => [:foo]
 *
 *  If <tt>range.start</tt> is negative, calculates the start index from the end:
 *
 *    a = [:foo, 'bar', 2]
 *    a[-1..2] # => [2]
 *    a[-2..2] # => ["bar", 2]
 *    a[-3..2] # => [:foo, "bar", 2]
 *
 *  If <tt>range.start</tt> is larger than the array size, returns +nil+.
 *
 *    a = [:foo, 'bar', 2]
 *    a[4..1] # => nil
 *    a[4..0] # => nil
 *    a[4..-1] # => nil
 *
 *  When a single Enumerator::ArithmeticSequence argument +aseq+ is given,
 *  returns an +Array+ of elements corresponding to the indexes produced by
 *  the sequence.
 *
 *    a = ['--', 'data1', '--', 'data2', '--', 'data3']
 *    a[(1..).step(2)] # => ["data1", "data2", "data3"]
 *
 *  Unlike slicing with range, if the start or the end of the arithmetic sequence
 *  is larger than array size, throws RangeError.
 *
 *    a = ['--', 'data1', '--', 'data2', '--', 'data3']
 *    a[(1..11).step(2)]
 *    # RangeError (((1..11).step(2)) out of range)
 *    a[(7..).step(2)]
 *    # RangeError (((7..).step(2)) out of range)
 *
 *  If given a single argument, and its type is not one of the listed, tries to
 *  convert it to Integer, and raises if it is impossible:
 *
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a[:foo]
 *
 */

VALUE
rb_ary_aref(int argc, const VALUE *argv, VALUE ary)
{
    rb_check_arity(argc, 1, 2);
    if (argc == 2) {
        return rb_ary_aref2(ary, argv[0], argv[1]);
    }
    return rb_ary_aref1(ary, argv[0]);
}

static VALUE
rb_ary_aref2(VALUE ary, VALUE b, VALUE e)
{
    long beg = NUM2LONG(b);
    long len = NUM2LONG(e);
    if (beg < 0) {
        beg += RARRAY_LEN(ary);
    }
    return rb_ary_subseq(ary, beg, len);
}

VALUE
rb_ary_aref1(VALUE ary, VALUE arg)
{
    long beg, len, step;

    /* special case - speeding up */
    if (FIXNUM_P(arg)) {
        return rb_ary_entry(ary, FIX2LONG(arg));
    }
    /* check if idx is Range or ArithmeticSequence */
    switch (rb_arithmetic_sequence_beg_len_step(arg, &beg, &len, &step, RARRAY_LEN(ary), 0)) {
      case Qfalse:
        break;
      case Qnil:
        return Qnil;
      default:
        return rb_ary_subseq_step(ary, beg, len, step);
    }

    return rb_ary_entry(ary, NUM2LONG(arg));
}

/*
 *  call-seq:
 *    array.at(index) -> object
 *
 *  Returns the element at Integer offset +index+; does not modify +self+.
 *    a = [:foo, 'bar', 2]
 *    a.at(0) # => :foo
 *    a.at(2) # => 2
 *
 */

VALUE
rb_ary_at(VALUE ary, VALUE pos)
{
    return rb_ary_entry(ary, NUM2LONG(pos));
}

#if 0
static VALUE
rb_ary_first(int argc, VALUE *argv, VALUE ary)
{
    if (argc == 0) {
        if (RARRAY_LEN(ary) == 0) return Qnil;
        return RARRAY_AREF(ary, 0);
    }
    else {
        return ary_take_first_or_last(argc, argv, ary, ARY_TAKE_FIRST);
    }
}
#endif

static VALUE
ary_first(VALUE self)
{
    return (RARRAY_LEN(self) == 0) ? Qnil : RARRAY_AREF(self, 0);
}

static VALUE
ary_last(VALUE self)
{
    long len = RARRAY_LEN(self);
    return (len == 0) ? Qnil : RARRAY_AREF(self, len-1);
}

VALUE
rb_ary_last(int argc, const VALUE *argv, VALUE ary) // used by parse.y
{
    if (argc == 0) {
        return ary_last(ary);
    }
    else {
        return ary_take_first_or_last(argc, argv, ary, ARY_TAKE_LAST);
    }
}

/*
 *  call-seq:
 *    array.fetch(index) -> element
 *    array.fetch(index, default_value) -> element
 *    array.fetch(index) {|index| ... } -> element
 *
 *  Returns the element at offset  +index+.
 *
 *  With the single Integer argument +index+,
 *  returns the element at offset +index+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.fetch(1) # => "bar"
 *
 *  If +index+ is negative, counts from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a.fetch(-1) # => 2
 *    a.fetch(-2) # => "bar"
 *
 *  With arguments +index+ and +default_value+,
 *  returns the element at offset +index+ if index is in range,
 *  otherwise returns +default_value+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.fetch(1, nil) # => "bar"
 *
 *  With argument +index+ and a block,
 *  returns the element at offset +index+ if index is in range
 *  (and the block is not called); otherwise calls the block with index and returns its return value:
 *
 *    a = [:foo, 'bar', 2]
 *    a.fetch(1) {|index| raise 'Cannot happen' } # => "bar"
 *    a.fetch(50) {|index| "Value for #{index}" } # => "Value for 50"
 *
 */

static VALUE
rb_ary_fetch(int argc, VALUE *argv, VALUE ary)
{
    VALUE pos, ifnone;
    long block_given;
    long idx;

    rb_scan_args(argc, argv, "11", &pos, &ifnone);
    block_given = rb_block_given_p();
    if (block_given && argc == 2) {
        rb_warn("block supersedes default value argument");
    }
    idx = NUM2LONG(pos);

    if (idx < 0) {
        idx +=  RARRAY_LEN(ary);
    }
    if (idx < 0 || RARRAY_LEN(ary) <= idx) {
        if (block_given) return rb_yield(pos);
        if (argc == 1) {
            rb_raise(rb_eIndexError, "index %ld outside of array bounds: %ld...%ld",
                        idx - (idx < 0 ? RARRAY_LEN(ary) : 0), -RARRAY_LEN(ary), RARRAY_LEN(ary));
        }
        return ifnone;
    }
    return RARRAY_AREF(ary, idx);
}

/*
 *  call-seq:
 *    array.index(object) -> integer or nil
 *    array.index {|element| ... } -> integer or nil
 *    array.index -> new_enumerator
 *
 *  Returns the index of a specified element.
 *
 *  When argument +object+ is given but no block,
 *  returns the index of the first element +element+
 *  for which <tt>object == element</tt>:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.index('bar') # => 1
 *
 *  Returns +nil+ if no such element found.
 *
 *  When both argument +object+ and a block are given,
 *  calls the block with each successive element;
 *  returns the index of the first element for which the block returns a truthy value:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.index {|element| element == 'bar' } # => 1
 *
 *  Returns +nil+ if the block never returns a truthy value.
 *
 *  When neither an argument nor a block is given, returns a new Enumerator:
 *
 *    a = [:foo, 'bar', 2]
 *    e = a.index
 *    e # => #<Enumerator: [:foo, "bar", 2]:index>
 *    e.each {|element| element == 'bar' } # => 1
 *
 *  Related: #rindex.
 */

static VALUE
rb_ary_index(int argc, VALUE *argv, VALUE ary)
{
    VALUE val;
    long i;

    if (argc == 0) {
        RETURN_ENUMERATOR(ary, 0, 0);
        for (i=0; i<RARRAY_LEN(ary); i++) {
            if (RTEST(rb_yield(RARRAY_AREF(ary, i)))) {
                return LONG2NUM(i);
            }
        }
        return Qnil;
    }
    rb_check_arity(argc, 0, 1);
    val = argv[0];
    if (rb_block_given_p())
        rb_warn("given block not used");
    for (i=0; i<RARRAY_LEN(ary); i++) {
        VALUE e = RARRAY_AREF(ary, i);
        if (rb_equal(e, val)) {
            return LONG2NUM(i);
        }
    }
    return Qnil;
}

/*
 *  call-seq:
 *    array.rindex(object) -> integer or nil
 *    array.rindex {|element| ... } -> integer or nil
 *    array.rindex -> new_enumerator
 *
 *  Returns the index of the last element for which <tt>object == element</tt>.
 *
 *  When argument +object+ is given but no block, returns the index of the last such element found:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.rindex('bar') # => 3
 *
 *  Returns +nil+ if no such object found.
 *
 *  When a block is given but no argument, calls the block with each successive element;
 *  returns the index of the last element for which the block returns a truthy value:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.rindex {|element| element == 'bar' } # => 3
 *
 *  Returns +nil+ if the block never returns a truthy value.
 *
 *  When neither an argument nor a block is given, returns a new Enumerator:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    e = a.rindex
 *    e # => #<Enumerator: [:foo, "bar", 2, "bar"]:rindex>
 *    e.each {|element| element == 'bar' } # => 3
 *
 *  Related: #index.
 */

static VALUE
rb_ary_rindex(int argc, VALUE *argv, VALUE ary)
{
    VALUE val;
    long i = RARRAY_LEN(ary), len;

    if (argc == 0) {
        RETURN_ENUMERATOR(ary, 0, 0);
        while (i--) {
            if (RTEST(rb_yield(RARRAY_AREF(ary, i))))
                return LONG2NUM(i);
            if (i > (len = RARRAY_LEN(ary))) {
                i = len;
            }
        }
        return Qnil;
    }
    rb_check_arity(argc, 0, 1);
    val = argv[0];
    if (rb_block_given_p())
        rb_warn("given block not used");
    while (i--) {
        VALUE e = RARRAY_AREF(ary, i);
        if (rb_equal(e, val)) {
            return LONG2NUM(i);
        }
        if (i > RARRAY_LEN(ary)) {
            break;
        }
    }
    return Qnil;
}

VALUE
rb_ary_to_ary(VALUE obj)
{
    VALUE tmp = rb_check_array_type(obj);

    if (!NIL_P(tmp)) return tmp;
    return rb_ary_new3(1, obj);
}

static void
rb_ary_splice(VALUE ary, long beg, long len, const VALUE *rptr, long rlen)
{
    long olen;
    long rofs;

    if (len < 0) rb_raise(rb_eIndexError, "negative length (%ld)", len);
    olen = RARRAY_LEN(ary);
    if (beg < 0) {
        beg += olen;
        if (beg < 0) {
            rb_raise(rb_eIndexError, "index %ld too small for array; minimum: %ld",
                     beg - olen, -olen);
        }
    }
    if (olen < len || olen < beg + len) {
        len = olen - beg;
    }

    {
        const VALUE *optr = RARRAY_CONST_PTR(ary);
        rofs = (rptr >= optr && rptr < optr + olen) ? rptr - optr : -1;
    }

    if (beg >= olen) {
        VALUE target_ary;
        if (beg > ARY_MAX_SIZE - rlen) {
            rb_raise(rb_eIndexError, "index %ld too big", beg);
        }
        target_ary = ary_ensure_room_for_push(ary, rlen-len); /* len is 0 or negative */
        len = beg + rlen;
        ary_mem_clear(ary, olen, beg - olen);
        if (rlen > 0) {
            if (rofs != -1) rptr = RARRAY_CONST_PTR(ary) + rofs;
            ary_memcpy0(ary, beg, rlen, rptr, target_ary);
        }
        ARY_SET_LEN(ary, len);
    }
    else {
        long alen;

        if (olen - len > ARY_MAX_SIZE - rlen) {
            rb_raise(rb_eIndexError, "index %ld too big", olen + rlen - len);
        }
        rb_ary_modify(ary);
        alen = olen + rlen - len;
        if (alen >= ARY_CAPA(ary)) {
            ary_double_capa(ary, alen);
        }

        if (len != rlen) {
            RARRAY_PTR_USE(ary, ptr,
                                     MEMMOVE(ptr + beg + rlen, ptr + beg + len,
                                             VALUE, olen - (beg + len)));
            ARY_SET_LEN(ary, alen);
        }
        if (rlen > 0) {
            if (rofs == -1) {
                rb_gc_writebarrier_remember(ary);
            }
            else {
                /* In this case, we're copying from a region in this array, so
                 * we don't need to fire the write barrier. */
                rptr = RARRAY_CONST_PTR(ary) + rofs;
            }

            /* do not use RARRAY_PTR() because it can causes GC.
             * ary can contain T_NONE object because it is not cleared.
             */
            RARRAY_PTR_USE(ary, ptr,
                                     MEMMOVE(ptr + beg, rptr, VALUE, rlen));
        }
    }
}

void
rb_ary_set_len(VALUE ary, long len)
{
    long capa;

    rb_ary_modify_check(ary);
    if (ARY_SHARED_P(ary)) {
        rb_raise(rb_eRuntimeError, "can't set length of shared ");
    }
    if (len > (capa = (long)ARY_CAPA(ary))) {
        rb_bug("probable buffer overflow: %ld for %ld", len, capa);
    }
    ARY_SET_LEN(ary, len);
}

VALUE
rb_ary_resize(VALUE ary, long len)
{
    long olen;

    rb_ary_modify(ary);
    olen = RARRAY_LEN(ary);
    if (len == olen) return ary;
    if (len > ARY_MAX_SIZE) {
        rb_raise(rb_eIndexError, "index %ld too big", len);
    }
    if (len > olen) {
        if (len >= ARY_CAPA(ary)) {
            ary_double_capa(ary, len);
        }
        ary_mem_clear(ary, olen, len - olen);
        ARY_SET_LEN(ary, len);
    }
    else if (ARY_EMBED_P(ary)) {
        ARY_SET_EMBED_LEN(ary, len);
    }
    else if (len <= ary_embed_capa(ary)) {
        const VALUE *ptr = ARY_HEAP_PTR(ary);
        long ptr_capa = ARY_HEAP_SIZE(ary);
        bool is_malloc_ptr = !ARY_SHARED_P(ary);

        FL_SET_EMBED(ary);

        MEMCPY((VALUE *)ARY_EMBED_PTR(ary), ptr, VALUE, len); /* WB: no new reference */
        ARY_SET_EMBED_LEN(ary, len);

        if (is_malloc_ptr) ruby_sized_xfree((void *)ptr, ptr_capa);
    }
    else {
        if (olen > len + ARY_DEFAULT_SIZE) {
            size_t new_capa = ary_heap_realloc(ary, len);
            ARY_SET_CAPA(ary, new_capa);
        }
        ARY_SET_HEAP_LEN(ary, len);
    }
    ary_verify(ary);
    return ary;
}

static VALUE
ary_aset_by_rb_ary_store(VALUE ary, long key, VALUE val)
{
    rb_ary_store(ary, key, val);
    return val;
}

static VALUE
ary_aset_by_rb_ary_splice(VALUE ary, long beg, long len, VALUE val)
{
    VALUE rpl = rb_ary_to_ary(val);
    rb_ary_splice(ary, beg, len, RARRAY_CONST_PTR(rpl), RARRAY_LEN(rpl));
    RB_GC_GUARD(rpl);
    return val;
}

/*
 *  call-seq:
 *    array[index] = object -> object
 *    array[start, length] = object -> object
 *    array[range] = object -> object
 *
 *  Assigns elements in +self+; returns the given +object+.
 *
 *  In brief:
 *
 *      a_orig = [:foo, 'bar', 2]
 *      # With argument index.
 *      a = a_orig.dup
 *      a[0] = 'foo' # => "foo"
 *      a # => ["foo", "bar", 2]
 *      a = a_orig.dup
 *      a[7] = 'foo' # => "foo"
 *      a # => [:foo, "bar", 2, nil, nil, nil, nil, "foo"]
 *      # With arguments start and length.
 *      a = a_orig.dup
 *      a[0, 2] = 'foo' # => "foo"
 *      a # => ["foo", 2]
 *      a = a_orig.dup
 *      a[6, 50] = 'foo' # => "foo"
 *      a # => [:foo, "bar", 2, nil, nil, nil, "foo"]
 *      # With argument range.
 *      a = a_orig.dup
 *      a[0..1] = 'foo' # => "foo"
 *      a # => ["foo", 2]
 *      a = a_orig.dup
 *      a[6..50] = 'foo' # => "foo"
 *      a # => [:foo, "bar", 2, nil, nil, nil, "foo"]
 *
 *  When Integer argument +index+ is given, assigns +object+ to an element in +self+.
 *
 *  If +index+ is non-negative, assigns +object+ the element at offset +index+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0] = 'foo' # => "foo"
 *    a # => ["foo", "bar", 2]
 *
 *  If +index+ is greater than <tt>self.length</tt>, extends the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a[7] = 'foo' # => "foo"
 *    a # => [:foo, "bar", 2, nil, nil, nil, nil, "foo"]
 *
 *  If +index+ is negative, counts backwards from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a[-1] = 'two' # => "two"
 *    a # => [:foo, "bar", "two"]
 *
 *  When Integer arguments +start+ and +length+ are given and +object+ is not an +Array+,
 *  removes <tt>length - 1</tt> elements beginning at offset +start+,
 *  and assigns +object+ at offset +start+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0, 2] = 'foo' # => "foo"
 *    a # => ["foo", 2]
 *
 *  If +start+ is negative, counts backwards from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a[-2, 2] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 *  If +start+ is non-negative and outside the array (<tt> >= self.size</tt>),
 *  extends the array with +nil+, assigns +object+ at offset +start+,
 *  and ignores +length+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[6, 50] = 'foo' # => "foo"
 *    a # => [:foo, "bar", 2, nil, nil, nil, "foo"]
 *
 *  If +length+ is zero, shifts elements at and following offset +start+
 *  and assigns +object+ at offset +start+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[1, 0] = 'foo' # => "foo"
 *    a # => [:foo, "foo", "bar", 2]
 *
 *  If +length+ is too large for the existing array, does not extend the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a[1, 5] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 *  When Range argument +range+ is given and +object+ is not an +Array+,
 *  removes <tt>length - 1</tt> elements beginning at offset +start+,
 *  and assigns +object+ at offset +start+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[0..1] = 'foo' # => "foo"
 *    a # => ["foo", 2]
 *
 *  if <tt>range.begin</tt> is negative, counts backwards from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a[-2..2] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 *  If the array length is less than <tt>range.begin</tt>,
 *  extends the array with +nil+, assigns +object+ at offset <tt>range.begin</tt>,
 *  and ignores +length+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[6..50] = 'foo' # => "foo"
 *    a # => [:foo, "bar", 2, nil, nil, nil, "foo"]
 *
 *  If <tt>range.end</tt> is zero, shifts elements at and following offset +start+
 *  and assigns +object+ at offset +start+:
 *
 *    a = [:foo, 'bar', 2]
 *    a[1..0] = 'foo' # => "foo"
 *    a # => [:foo, "foo", "bar", 2]
 *
 *  If <tt>range.end</tt> is negative, assigns +object+ at offset +start+,
 *  retains <tt>range.end.abs -1</tt> elements past that, and removes those beyond:
 *
 *    a = [:foo, 'bar', 2]
 *    a[1..-1] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *    a = [:foo, 'bar', 2]
 *    a[1..-2] = 'foo' # => "foo"
 *    a # => [:foo, "foo", 2]
 *    a = [:foo, 'bar', 2]
 *    a[1..-3] = 'foo' # => "foo"
 *    a # => [:foo, "foo", "bar", 2]
 *    a = [:foo, 'bar', 2]
 *
 *  If <tt>range.end</tt> is too large for the existing array,
 *  replaces array elements, but does not extend the array with +nil+ values:
 *
 *    a = [:foo, 'bar', 2]
 *    a[1..5] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 */

static VALUE
rb_ary_aset(int argc, VALUE *argv, VALUE ary)
{
    long offset, beg, len;

    rb_check_arity(argc, 2, 3);
    rb_ary_modify_check(ary);
    if (argc == 3) {
        beg = NUM2LONG(argv[0]);
        len = NUM2LONG(argv[1]);
        return ary_aset_by_rb_ary_splice(ary, beg, len, argv[2]);
    }
    if (FIXNUM_P(argv[0])) {
        offset = FIX2LONG(argv[0]);
        return ary_aset_by_rb_ary_store(ary, offset, argv[1]);
    }
    if (rb_range_beg_len(argv[0], &beg, &len, RARRAY_LEN(ary), 1)) {
        /* check if idx is Range */
        return ary_aset_by_rb_ary_splice(ary, beg, len, argv[1]);
    }

    offset = NUM2LONG(argv[0]);
    return ary_aset_by_rb_ary_store(ary, offset, argv[1]);
}

/*
 *  call-seq:
 *    array.insert(index, *objects) -> self
 *
 *  Inserts given +objects+ before or after the element at Integer index +offset+;
 *  returns +self+.
 *
 *  When +index+ is non-negative, inserts all given +objects+
 *  before the element at offset +index+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.insert(1, :bat, :bam) # => [:foo, :bat, :bam, "bar", 2]
 *
 *  Extends the array if +index+ is beyond the array (<tt>index >= self.size</tt>):
 *
 *    a = [:foo, 'bar', 2]
 *    a.insert(5, :bat, :bam)
 *    a # => [:foo, "bar", 2, nil, nil, :bat, :bam]
 *
 *  Does nothing if no objects given:
 *
 *    a = [:foo, 'bar', 2]
 *    a.insert(1)
 *    a.insert(50)
 *    a.insert(-50)
 *    a # => [:foo, "bar", 2]
 *
 *  When +index+ is negative, inserts all given +objects+
 *  _after_ the element at offset <tt>index+self.size</tt>:
 *
 *    a = [:foo, 'bar', 2]
 *    a.insert(-2, :bat, :bam)
 *    a # => [:foo, "bar", :bat, :bam, 2]
 *
 */

static VALUE
rb_ary_insert(int argc, VALUE *argv, VALUE ary)
{
    long pos;

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    rb_ary_modify_check(ary);
    pos = NUM2LONG(argv[0]);
    if (argc == 1) return ary;
    if (pos == -1) {
        pos = RARRAY_LEN(ary);
    }
    else if (pos < 0) {
        long minpos = -RARRAY_LEN(ary) - 1;
        if (pos < minpos) {
            rb_raise(rb_eIndexError, "index %ld too small for array; minimum: %ld",
                     pos, minpos);
        }
        pos++;
    }
    rb_ary_splice(ary, pos, 0, argv + 1, argc - 1);
    return ary;
}

static VALUE
rb_ary_length(VALUE ary);

static VALUE
ary_enum_length(VALUE ary, VALUE args, VALUE eobj)
{
    return rb_ary_length(ary);
}

// Primitive to avoid a race condition in Array#each.
// Return `true` and write `value` and `index` if the element exists.
static VALUE
ary_fetch_next(VALUE self, VALUE *index, VALUE *value)
{
    long i = NUM2LONG(*index);
    if (i >= RARRAY_LEN(self)) {
        return Qfalse;
    }
    *value = RARRAY_AREF(self, i);
    *index = LONG2NUM(i + 1);
    return Qtrue;
}

VALUE
rb_ary_each(VALUE ary)
{
    long i;
    ary_verify(ary);
    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    for (i=0; i<RARRAY_LEN(ary); i++) {
        rb_yield(RARRAY_AREF(ary, i));
    }
    return ary;
}

/*
 *  call-seq:
 *    array.each_index {|index| ... } -> self
 *    array.each_index -> Enumerator
 *
 *  Iterates over array indexes.
 *
 *  When a block given, passes each successive array index to the block;
 *  returns +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.each_index {|index|  puts "#{index} #{a[index]}" }
 *
 *  Output:
 *
 *    0 foo
 *    1 bar
 *    2 2
 *
 *  Allows the array to be modified during iteration:
 *
 *    a = [:foo, 'bar', 2]
 *    a.each_index {|index| puts index; a.clear if index > 0 }
 *
 *  Output:
 *
 *    0
 *    1
 *
 *  When no block given, returns a new Enumerator:
 *
 *    a = [:foo, 'bar', 2]
 *    e = a.each_index
 *    e # => #<Enumerator: [:foo, "bar", 2]:each_index>
 *    a1 = e.each {|index|  puts "#{index} #{a[index]}"}
 *
 *  Output:
 *
 *    0 foo
 *    1 bar
 *    2 2
 *
 *  Related: #each, #reverse_each.
 */

static VALUE
rb_ary_each_index(VALUE ary)
{
    long i;
    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);

    for (i=0; i<RARRAY_LEN(ary); i++) {
        rb_yield(LONG2NUM(i));
    }
    return ary;
}

/*
 *  call-seq:
 *    array.reverse_each {|element| ... } -> self
 *    array.reverse_each -> Enumerator
 *
 *  Iterates backwards over array elements.
 *
 *  When a block given, passes, in reverse order, each element to the block;
 *  returns +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.reverse_each {|element|  puts "#{element.class} #{element}" }
 *
 *  Output:
 *
 *    Integer 2
 *    String bar
 *    Symbol foo
 *
 *  Allows the array to be modified during iteration:
 *
 *    a = [:foo, 'bar', 2]
 *    a.reverse_each {|element| puts element; a.clear if element.to_s.start_with?('b') }
 *
 *  Output:
 *
 *    2
 *    bar
 *
 *  When no block given, returns a new Enumerator:
 *
 *    a = [:foo, 'bar', 2]
 *    e = a.reverse_each
 *    e # => #<Enumerator: [:foo, "bar", 2]:reverse_each>
 *    a1 = e.each {|element|  puts "#{element.class} #{element}" }
 *
 *  Output:
 *
 *    Integer 2
 *    String bar
 *    Symbol foo
 *
 *  Related: #each, #each_index.
 */

static VALUE
rb_ary_reverse_each(VALUE ary)
{
    long len;

    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    len = RARRAY_LEN(ary);
    while (len--) {
        long nlen;
        rb_yield(RARRAY_AREF(ary, len));
        nlen = RARRAY_LEN(ary);
        if (nlen < len) {
            len = nlen;
        }
    }
    return ary;
}

/*
 *  call-seq:
 *    array.length -> an_integer
 *
 *  Returns the count of elements in +self+.
 */

static VALUE
rb_ary_length(VALUE ary)
{
    long len = RARRAY_LEN(ary);
    return LONG2NUM(len);
}

/*
 *  call-seq:
 *    array.empty?  -> true or false
 *
 *  Returns +true+ if the count of elements in +self+ is zero,
 *  +false+ otherwise.
 */

static VALUE
rb_ary_empty_p(VALUE ary)
{
    return RBOOL(RARRAY_LEN(ary) == 0);
}

VALUE
rb_ary_dup(VALUE ary)
{
    long len = RARRAY_LEN(ary);
    VALUE dup = rb_ary_new2(len);
    ary_memcpy(dup, 0, len, RARRAY_CONST_PTR(ary));
    ARY_SET_LEN(dup, len);

    ary_verify(ary);
    ary_verify(dup);
    return dup;
}

VALUE
rb_ary_resurrect(VALUE ary)
{
    return ary_make_partial(ary, rb_cArray, 0, RARRAY_LEN(ary));
}

extern VALUE rb_output_fs;

static void ary_join_1(VALUE obj, VALUE ary, VALUE sep, long i, VALUE result, int *first);

static VALUE
recursive_join(VALUE obj, VALUE argp, int recur)
{
    VALUE *arg = (VALUE *)argp;
    VALUE ary = arg[0];
    VALUE sep = arg[1];
    VALUE result = arg[2];
    int *first = (int *)arg[3];

    if (recur) {
        rb_raise(rb_eArgError, "recursive array join");
    }
    else {
        ary_join_1(obj, ary, sep, 0, result, first);
    }
    return Qnil;
}

static long
ary_join_0(VALUE ary, VALUE sep, long max, VALUE result)
{
    long i;
    VALUE val;

    if (max > 0) rb_enc_copy(result, RARRAY_AREF(ary, 0));
    for (i=0; i<max; i++) {
        val = RARRAY_AREF(ary, i);
        if (!RB_TYPE_P(val, T_STRING)) break;
        if (i > 0 && !NIL_P(sep))
            rb_str_buf_append(result, sep);
        rb_str_buf_append(result, val);
    }
    return i;
}

static void
ary_join_1_str(VALUE dst, VALUE src, int *first)
{
    rb_str_buf_append(dst, src);
    if (*first) {
        rb_enc_copy(dst, src);
        *first = FALSE;
    }
}

static void
ary_join_1_ary(VALUE obj, VALUE ary, VALUE sep, VALUE result, VALUE val, int *first)
{
    if (val == ary) {
        rb_raise(rb_eArgError, "recursive array join");
    }
    else {
        VALUE args[4];

        *first = FALSE;
        args[0] = val;
        args[1] = sep;
        args[2] = result;
        args[3] = (VALUE)first;
        rb_exec_recursive(recursive_join, obj, (VALUE)args);
    }
}

static void
ary_join_1(VALUE obj, VALUE ary, VALUE sep, long i, VALUE result, int *first)
{
    VALUE val, tmp;

    for (; i<RARRAY_LEN(ary); i++) {
        if (i > 0 && !NIL_P(sep))
            rb_str_buf_append(result, sep);

        val = RARRAY_AREF(ary, i);
        if (RB_TYPE_P(val, T_STRING)) {
            ary_join_1_str(result, val, first);
        }
        else if (RB_TYPE_P(val, T_ARRAY)) {
            ary_join_1_ary(val, ary, sep, result, val, first);
        }
        else if (!NIL_P(tmp = rb_check_string_type(val))) {
            ary_join_1_str(result, tmp, first);
        }
        else if (!NIL_P(tmp = rb_check_array_type(val))) {
            ary_join_1_ary(val, ary, sep, result, tmp, first);
        }
        else {
            ary_join_1_str(result, rb_obj_as_string(val), first);
        }
    }
}

VALUE
rb_ary_join(VALUE ary, VALUE sep)
{
    long len = 1, i;
    VALUE val, tmp, result;

    if (RARRAY_LEN(ary) == 0) return rb_usascii_str_new(0, 0);

    if (!NIL_P(sep)) {
        StringValue(sep);
        len += RSTRING_LEN(sep) * (RARRAY_LEN(ary) - 1);
    }
    for (i=0; i<RARRAY_LEN(ary); i++) {
        val = RARRAY_AREF(ary, i);
        tmp = rb_check_string_type(val);

        if (NIL_P(tmp) || tmp != val) {
            int first;
            long n = RARRAY_LEN(ary);
            if (i > n) i = n;
            result = rb_str_buf_new(len + (n-i)*10);
            rb_enc_associate(result, rb_usascii_encoding());
            i = ary_join_0(ary, sep, i, result);
            first = i == 0;
            ary_join_1(ary, ary, sep, i, result, &first);
            return result;
        }

        len += RSTRING_LEN(tmp);
    }

    result = rb_str_new(0, len);
    rb_str_set_len(result, 0);

    ary_join_0(ary, sep, RARRAY_LEN(ary), result);

    return result;
}

/*
 *  call-seq:
 *    array.join ->new_string
 *    array.join(separator = $,) -> new_string
 *
 *  Returns the new String formed by joining the array elements after conversion.
 *  For each element +element+:
 *
 *  - Uses <tt>element.to_s</tt> if +element+ is not a <tt>kind_of?(Array)</tt>.
 *  - Uses recursive <tt>element.join(separator)</tt> if +element+ is a <tt>kind_of?(Array)</tt>.
 *
 *  With no argument, joins using the output field separator, <tt>$,</tt>:
 *
 *    a = [:foo, 'bar', 2]
 *    $, # => nil
 *    a.join # => "foobar2"
 *
 *  With \string argument +separator+, joins using that separator:
 *
 *    a = [:foo, 'bar', 2]
 *    a.join("\n") # => "foo\nbar\n2"
 *
 *  Joins recursively for nested Arrays:
 *
 *   a = [:foo, [:bar, [:baz, :bat]]]
 *   a.join # => "foobarbazbat"
 *
 */
static VALUE
rb_ary_join_m(int argc, VALUE *argv, VALUE ary)
{
    VALUE sep;

    if (rb_check_arity(argc, 0, 1) == 0 || NIL_P(sep = argv[0])) {
        sep = rb_output_fs;
        if (!NIL_P(sep)) {
            rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "$, is set to non-nil value");
        }
    }

    return rb_ary_join(ary, sep);
}

static VALUE
inspect_ary(VALUE ary, VALUE dummy, int recur)
{
    long i;
    VALUE s, str;

    if (recur) return rb_usascii_str_new_cstr("[...]");
    str = rb_str_buf_new2("[");
    for (i=0; i<RARRAY_LEN(ary); i++) {
        s = rb_inspect(RARRAY_AREF(ary, i));
        if (i > 0) rb_str_buf_cat2(str, ", ");
        else rb_enc_copy(str, s);
        rb_str_buf_append(str, s);
    }
    rb_str_buf_cat2(str, "]");
    return str;
}

/*
 *  call-seq:
 *    array.inspect -> new_string
 *
 *  Returns the new String formed by calling method <tt>#inspect</tt>
 *  on each array element:
 *
 *    a = [:foo, 'bar', 2]
 *    a.inspect # => "[:foo, \"bar\", 2]"
 *
 */

static VALUE
rb_ary_inspect(VALUE ary)
{
    if (RARRAY_LEN(ary) == 0) return rb_usascii_str_new2("[]");
    return rb_exec_recursive(inspect_ary, ary, 0);
}

VALUE
rb_ary_to_s(VALUE ary)
{
    return rb_ary_inspect(ary);
}

/*
 *  call-seq:
 *    to_a -> self or new_array
 *
 *  When +self+ is an instance of +Array+, returns +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.to_a # => [:foo, "bar", 2]
 *
 *  Otherwise, returns a new +Array+ containing the elements of +self+:
 *
 *    class MyArray < Array; end
 *    a = MyArray.new(['foo', 'bar', 'two'])
 *    a.instance_of?(Array) # => false
 *    a.kind_of?(Array) # => true
 *    a1 = a.to_a
 *    a1 # => ["foo", "bar", "two"]
 *    a1.class # => Array # Not MyArray
 *
 */

static VALUE
rb_ary_to_a(VALUE ary)
{
    if (rb_obj_class(ary) != rb_cArray) {
        VALUE dup = rb_ary_new2(RARRAY_LEN(ary));
        rb_ary_replace(dup, ary);
        return dup;
    }
    return ary;
}

/*
 *  call-seq:
 *    array.to_h -> new_hash
 *    array.to_h {|item| ... } -> new_hash
 *
 *  Returns a new Hash formed from +self+.
 *
 *  When a block is given, calls the block with each array element;
 *  the block must return a 2-element +Array+ whose two elements
 *  form a key-value pair in the returned Hash:
 *
 *    a = ['foo', :bar, 1, [2, 3], {baz: 4}]
 *    h = a.to_h {|item| [item, item] }
 *    h # => {"foo"=>"foo", :bar=>:bar, 1=>1, [2, 3]=>[2, 3], {:baz=>4}=>{:baz=>4}}
 *
 *  When no block is given, +self+ must be an +Array+ of 2-element sub-arrays,
 *  each sub-array is formed into a key-value pair in the new Hash:
 *
 *    [].to_h # => {}
 *    a = [['foo', 'zero'], ['bar', 'one'], ['baz', 'two']]
 *    h = a.to_h
 *    h # => {"foo"=>"zero", "bar"=>"one", "baz"=>"two"}
 *
 */

static VALUE
rb_ary_to_h(VALUE ary)
{
    long i;
    VALUE hash = rb_hash_new_with_size(RARRAY_LEN(ary));
    int block_given = rb_block_given_p();

    for (i=0; i<RARRAY_LEN(ary); i++) {
        const VALUE e = rb_ary_elt(ary, i);
        const VALUE elt = block_given ? rb_yield_force_blockarg(e) : e;
        const VALUE key_value_pair = rb_check_array_type(elt);
        if (NIL_P(key_value_pair)) {
            rb_raise(rb_eTypeError, "wrong element type %"PRIsVALUE" at %ld (expected array)",
                     rb_obj_class(elt), i);
        }
        if (RARRAY_LEN(key_value_pair) != 2) {
            rb_raise(rb_eArgError, "wrong array length at %ld (expected 2, was %ld)",
                i, RARRAY_LEN(key_value_pair));
        }
        rb_hash_aset(hash, RARRAY_AREF(key_value_pair, 0), RARRAY_AREF(key_value_pair, 1));
    }
    return hash;
}

/*
 *  call-seq:
 *    array.to_ary -> self
 *
 *  Returns +self+.
 */

static VALUE
rb_ary_to_ary_m(VALUE ary)
{
    return ary;
}

static void
ary_reverse(VALUE *p1, VALUE *p2)
{
    while (p1 < p2) {
        VALUE tmp = *p1;
        *p1++ = *p2;
        *p2-- = tmp;
    }
}

VALUE
rb_ary_reverse(VALUE ary)
{
    VALUE *p2;
    long len = RARRAY_LEN(ary);

    rb_ary_modify(ary);
    if (len > 1) {
        RARRAY_PTR_USE(ary, p1, {
            p2 = p1 + len - 1;	/* points last item */
            ary_reverse(p1, p2);
        }); /* WB: no new reference */
    }
    return ary;
}

/*
 *  call-seq:
 *    array.reverse! -> self
 *
 *  Reverses +self+ in place:
 *
 *    a = ['foo', 'bar', 'two']
 *    a.reverse! # => ["two", "bar", "foo"]
 *
 */

static VALUE
rb_ary_reverse_bang(VALUE ary)
{
    return rb_ary_reverse(ary);
}

/*
 *  call-seq:
 *    array.reverse -> new_array
 *
 *  Returns a new +Array+ with the elements of +self+ in reverse order:
 *
 *    a = ['foo', 'bar', 'two']
 *    a1 = a.reverse
 *    a1 # => ["two", "bar", "foo"]
 *
 */

static VALUE
rb_ary_reverse_m(VALUE ary)
{
    long len = RARRAY_LEN(ary);
    VALUE dup = rb_ary_new2(len);

    if (len > 0) {
        const VALUE *p1 = RARRAY_CONST_PTR(ary);
        VALUE *p2 = (VALUE *)RARRAY_CONST_PTR(dup) + len - 1;
        do *p2-- = *p1++; while (--len > 0);
    }
    ARY_SET_LEN(dup, RARRAY_LEN(ary));
    return dup;
}

static inline long
rotate_count(long cnt, long len)
{
    return (cnt < 0) ? (len - (~cnt % len) - 1) : (cnt % len);
}

static void
ary_rotate_ptr(VALUE *ptr, long len, long cnt)
{
    if (cnt == 1) {
        VALUE tmp = *ptr;
        memmove(ptr, ptr + 1, sizeof(VALUE)*(len - 1));
        *(ptr + len - 1) = tmp;
    }
    else if (cnt == len - 1) {
        VALUE tmp = *(ptr + len - 1);
        memmove(ptr + 1, ptr, sizeof(VALUE)*(len - 1));
        *ptr = tmp;
    }
    else {
        --len;
        if (cnt < len) ary_reverse(ptr + cnt, ptr + len);
        if (--cnt > 0) ary_reverse(ptr, ptr + cnt);
        if (len > 0) ary_reverse(ptr, ptr + len);
    }
}

VALUE
rb_ary_rotate(VALUE ary, long cnt)
{
    rb_ary_modify(ary);

    if (cnt != 0) {
        long len = RARRAY_LEN(ary);
        if (len > 1 && (cnt = rotate_count(cnt, len)) > 0) {
            RARRAY_PTR_USE(ary, ptr, ary_rotate_ptr(ptr, len, cnt));
            return ary;
        }
    }
    return Qnil;
}

/*
 *  call-seq:
 *    array.rotate! -> self
 *    array.rotate!(count) -> self
 *
 *  Rotates +self+ in place by moving elements from one end to the other; returns +self+.
 *
 *  When no argument given, rotates the first element to the last position:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.rotate! # => ["bar", 2, "bar", :foo]
 *
 *  When given a non-negative Integer +count+,
 *  rotates +count+ elements from the beginning to the end:
 *
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(2)
 *    a # => [2, :foo, "bar"]
 *
 *  If +count+ is large, uses <tt>count % array.size</tt> as the count:
 *
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(20)
 *    a # => [2, :foo, "bar"]
 *
 *  If +count+ is zero, returns +self+ unmodified:
 *
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(0)
 *    a # => [:foo, "bar", 2]
 *
 *  When given a negative Integer +count+, rotates in the opposite direction,
 *  from end to beginning:
 *
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(-2)
 *    a # => ["bar", 2, :foo]
 *
 *  If +count+ is small (far from zero), uses <tt>count % array.size</tt> as the count:
 *
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(-5)
 *    a # => ["bar", 2, :foo]
 *
 */

static VALUE
rb_ary_rotate_bang(int argc, VALUE *argv, VALUE ary)
{
    long n = (rb_check_arity(argc, 0, 1) ? NUM2LONG(argv[0]) : 1);
    rb_ary_rotate(ary, n);
    return ary;
}

/*
 *  call-seq:
 *    array.rotate -> new_array
 *    array.rotate(count) -> new_array
 *
 *  Returns a new +Array+ formed from +self+ with elements
 *  rotated from one end to the other.
 *
 *  When no argument given, returns a new +Array+ that is like +self+,
 *  except that the first element has been rotated to the last position:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    a1 = a.rotate
 *    a1 # => ["bar", 2, "bar", :foo]
 *
 *  When given a non-negative Integer +count+,
 *  returns a new +Array+ with +count+ elements rotated from the beginning to the end:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(2)
 *    a1 # => [2, :foo, "bar"]
 *
 *  If +count+ is large, uses <tt>count % array.size</tt> as the count:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(20)
 *    a1 # => [2, :foo, "bar"]
 *
 *  If +count+ is zero, returns a copy of +self+, unmodified:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(0)
 *    a1 # => [:foo, "bar", 2]
 *
 *  When given a negative Integer +count+, rotates in the opposite direction,
 *  from end to beginning:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(-2)
 *    a1 # => ["bar", 2, :foo]
 *
 *  If +count+ is small (far from zero), uses <tt>count % array.size</tt> as the count:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(-5)
 *    a1 # => ["bar", 2, :foo]
 *
 */

static VALUE
rb_ary_rotate_m(int argc, VALUE *argv, VALUE ary)
{
    VALUE rotated;
    const VALUE *ptr;
    long len;
    long cnt = (rb_check_arity(argc, 0, 1) ? NUM2LONG(argv[0]) : 1);

    len = RARRAY_LEN(ary);
    rotated = rb_ary_new2(len);
    if (len > 0) {
        cnt = rotate_count(cnt, len);
        ptr = RARRAY_CONST_PTR(ary);
        len -= cnt;
        ary_memcpy(rotated, 0, len, ptr + cnt);
        ary_memcpy(rotated, len, cnt, ptr);
    }
    ARY_SET_LEN(rotated, RARRAY_LEN(ary));
    return rotated;
}

struct ary_sort_data {
    VALUE ary;
    VALUE receiver;
};

static VALUE
sort_reentered(VALUE ary)
{
    if (RBASIC(ary)->klass) {
        rb_raise(rb_eRuntimeError, "sort reentered");
    }
    return Qnil;
}

static void
sort_returned(struct ary_sort_data *data)
{
    if (rb_obj_frozen_p(data->receiver)) {
        rb_raise(rb_eFrozenError, "array frozen during sort");
    }
    sort_reentered(data->ary);
}

static int
sort_1(const void *ap, const void *bp, void *dummy)
{
    struct ary_sort_data *data = dummy;
    VALUE retval = sort_reentered(data->ary);
    VALUE a = *(const VALUE *)ap, b = *(const VALUE *)bp;
    VALUE args[2];
    int n;

    args[0] = a;
    args[1] = b;
    retval = rb_yield_values2(2, args);
    n = rb_cmpint(retval, a, b);
    sort_returned(data);
    return n;
}

static int
sort_2(const void *ap, const void *bp, void *dummy)
{
    struct ary_sort_data *data = dummy;
    VALUE retval = sort_reentered(data->ary);
    VALUE a = *(const VALUE *)ap, b = *(const VALUE *)bp;
    int n;

    if (FIXNUM_P(a) && FIXNUM_P(b) && CMP_OPTIMIZABLE(INTEGER)) {
        if ((long)a > (long)b) return 1;
        if ((long)a < (long)b) return -1;
        return 0;
    }
    if (STRING_P(a) && STRING_P(b) && CMP_OPTIMIZABLE(STRING)) {
        return rb_str_cmp(a, b);
    }
    if (RB_FLOAT_TYPE_P(a) && CMP_OPTIMIZABLE(FLOAT)) {
        return rb_float_cmp(a, b);
    }

    retval = rb_funcallv(a, id_cmp, 1, &b);
    n = rb_cmpint(retval, a, b);
    sort_returned(data);

    return n;
}

/*
 *  call-seq:
 *    array.sort! -> self
 *    array.sort! {|a, b| ... } -> self
 *
 *  Returns +self+ with its elements sorted in place.
 *
 *  With no block, compares elements using operator <tt><=></tt>
 *  (see Comparable):
 *
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a.sort!
 *    a # => ["a", "b", "c", "d", "e"]
 *
 *  With a block, calls the block with each element pair;
 *  for each element pair +a+ and +b+, the block should return an integer:
 *
 *  - Negative when +b+ is to follow +a+.
 *  - Zero when +a+ and +b+ are equivalent.
 *  - Positive when +a+ is to follow +b+.
 *
 *  Example:
 *
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a.sort! {|a, b| a <=> b }
 *    a # => ["a", "b", "c", "d", "e"]
 *    a.sort! {|a, b| b <=> a }
 *    a # => ["e", "d", "c", "b", "a"]
 *
 *  When the block returns zero, the order for +a+ and +b+ is indeterminate,
 *  and may be unstable:
 *
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a.sort! {|a, b| 0 }
 *    a # => ["d", "e", "c", "a", "b"]
 *
 */

VALUE
rb_ary_sort_bang(VALUE ary)
{
    rb_ary_modify(ary);
    RUBY_ASSERT(!ARY_SHARED_P(ary));
    if (RARRAY_LEN(ary) > 1) {
        VALUE tmp = ary_make_substitution(ary); /* only ary refers tmp */
        struct ary_sort_data data;
        long len = RARRAY_LEN(ary);
        RBASIC_CLEAR_CLASS(tmp);
        data.ary = tmp;
        data.receiver = ary;
        RARRAY_PTR_USE(tmp, ptr, {
            ruby_qsort(ptr, len, sizeof(VALUE),
                       rb_block_given_p()?sort_1:sort_2, &data);
        }); /* WB: no new reference */
        rb_ary_modify(ary);
        if (ARY_EMBED_P(tmp)) {
            if (ARY_SHARED_P(ary)) { /* ary might be destructively operated in the given block */
                rb_ary_unshare(ary);
                FL_SET_EMBED(ary);
            }
            if (ARY_EMBED_LEN(tmp) > ARY_CAPA(ary)) {
                ary_resize_capa(ary, ARY_EMBED_LEN(tmp));
            }
            ary_memcpy(ary, 0, ARY_EMBED_LEN(tmp), ARY_EMBED_PTR(tmp));
            ARY_SET_LEN(ary, ARY_EMBED_LEN(tmp));
        }
        else {
            if (!ARY_EMBED_P(ary) && ARY_HEAP_PTR(ary) == ARY_HEAP_PTR(tmp)) {
                FL_UNSET_SHARED(ary);
                ARY_SET_CAPA(ary, RARRAY_LEN(tmp));
            }
            else {
                RUBY_ASSERT(!ARY_SHARED_P(tmp));
                if (ARY_EMBED_P(ary)) {
                    FL_UNSET_EMBED(ary);
                }
                else if (ARY_SHARED_P(ary)) {
                    /* ary might be destructively operated in the given block */
                    rb_ary_unshare(ary);
                }
                else {
                    ary_heap_free(ary);
                }
                ARY_SET_PTR(ary, ARY_HEAP_PTR(tmp));
                ARY_SET_HEAP_LEN(ary, len);
                ARY_SET_CAPA(ary, ARY_HEAP_LEN(tmp));
            }
            /* tmp was lost ownership for the ptr */
            FL_UNSET(tmp, FL_FREEZE);
            FL_SET_EMBED(tmp);
            ARY_SET_EMBED_LEN(tmp, 0);
            FL_SET(tmp, FL_FREEZE);
        }
        /* tmp will be GC'ed. */
        RBASIC_SET_CLASS_RAW(tmp, rb_cArray); /* rb_cArray must be marked */
    }
    ary_verify(ary);
    return ary;
}

/*
 *  call-seq:
 *    array.sort -> new_array
 *    array.sort {|a, b| ... } -> new_array
 *
 *  Returns a new +Array+ whose elements are those from +self+, sorted.
 *
 *  With no block, compares elements using operator <tt><=></tt>
 *  (see Comparable):
 *
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a1 = a.sort
 *    a1 # => ["a", "b", "c", "d", "e"]
 *
 *  With a block, calls the block with each element pair;
 *  for each element pair +a+ and +b+, the block should return an integer:
 *
 *  - Negative when +b+ is to follow +a+.
 *  - Zero when +a+ and +b+ are equivalent.
 *  - Positive when +a+ is to follow +b+.
 *
 *  Example:
 *
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a1 = a.sort {|a, b| a <=> b }
 *    a1 # => ["a", "b", "c", "d", "e"]
 *    a2 = a.sort {|a, b| b <=> a }
 *    a2 # => ["e", "d", "c", "b", "a"]
 *
 *  When the block returns zero, the order for +a+ and +b+ is indeterminate,
 *  and may be unstable:
 *
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a1 = a.sort {|a, b| 0 }
 *    a1 # =>  ["c", "e", "b", "d", "a"]
 *
 *  Related: Enumerable#sort_by.
 */

VALUE
rb_ary_sort(VALUE ary)
{
    ary = rb_ary_dup(ary);
    rb_ary_sort_bang(ary);
    return ary;
}

static VALUE rb_ary_bsearch_index(VALUE ary);

/*
 *  call-seq:
 *    array.bsearch {|element| ... } -> object
 *    array.bsearch -> new_enumerator
 *
 *  Returns an element from +self+ selected by a binary search.
 *
 *  See {Binary Searching}[rdoc-ref:bsearch.rdoc].
 */

static VALUE
rb_ary_bsearch(VALUE ary)
{
    VALUE index_result = rb_ary_bsearch_index(ary);

    if (FIXNUM_P(index_result)) {
        return rb_ary_entry(ary, FIX2LONG(index_result));
    }
    return index_result;
}

/*
 *  call-seq:
 *    array.bsearch_index {|element| ... } -> integer or nil
 *    array.bsearch_index -> new_enumerator
 *
 *  Searches +self+ as described at method #bsearch,
 *  but returns the _index_ of the found element instead of the element itself.
 */

static VALUE
rb_ary_bsearch_index(VALUE ary)
{
    long low = 0, high = RARRAY_LEN(ary), mid;
    int smaller = 0, satisfied = 0;
    VALUE v, val;

    RETURN_ENUMERATOR(ary, 0, 0);
    while (low < high) {
        mid = low + ((high - low) / 2);
        val = rb_ary_entry(ary, mid);
        v = rb_yield(val);
        if (FIXNUM_P(v)) {
            if (v == INT2FIX(0)) return INT2FIX(mid);
            smaller = (SIGNED_VALUE)v < 0; /* Fixnum preserves its sign-bit */
        }
        else if (v == Qtrue) {
            satisfied = 1;
            smaller = 1;
        }
        else if (!RTEST(v)) {
            smaller = 0;
        }
        else if (rb_obj_is_kind_of(v, rb_cNumeric)) {
            const VALUE zero = INT2FIX(0);
            switch (rb_cmpint(rb_funcallv(v, id_cmp, 1, &zero), v, zero)) {
              case 0: return INT2FIX(mid);
              case 1: smaller = 0; break;
              case -1: smaller = 1;
            }
        }
        else {
            rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE
                     " (must be numeric, true, false or nil)",
                     rb_obj_class(v));
        }
        if (smaller) {
            high = mid;
        }
        else {
            low = mid + 1;
        }
    }
    if (!satisfied) return Qnil;
    return INT2FIX(low);
}


static VALUE
sort_by_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, dummy))
{
    return rb_yield(i);
}

/*
 *  call-seq:
 *    array.sort_by! {|element| ... } -> self
 *    array.sort_by! -> new_enumerator
 *
 *  Sorts the elements of +self+ in place,
 *  using an ordering determined by the block; returns self.
 *
 *  Calls the block with each successive element;
 *  sorts elements based on the values returned from the block.
 *
 *  For duplicates returned by the block, the ordering is indeterminate, and may be unstable.
 *
 *  This example sorts strings based on their sizes:
 *
 *    a = ['aaaa', 'bbb', 'cc', 'd']
 *    a.sort_by! {|element| element.size }
 *    a # => ["d", "cc", "bbb", "aaaa"]
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = ['aaaa', 'bbb', 'cc', 'd']
 *    a.sort_by! # => #<Enumerator: ["aaaa", "bbb", "cc", "d"]:sort_by!>
 *
 */

static VALUE
rb_ary_sort_by_bang(VALUE ary)
{
    VALUE sorted;

    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    rb_ary_modify(ary);
    sorted = rb_block_call(ary, rb_intern("sort_by"), 0, 0, sort_by_i, 0);
    rb_ary_replace(ary, sorted);
    return ary;
}


/*
 *  call-seq:
 *    array.map {|element| ... } -> new_array
 *    array.map -> new_enumerator
 *
 *  Calls the block, if given, with each element of +self+;
 *  returns a new +Array+ whose elements are the return values from the block:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.map {|element| element.class }
 *    a1 # => [Symbol, String, Integer]
 *
 *  Returns a new Enumerator if no block given:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.map
 *    a1 # => #<Enumerator: [:foo, "bar", 2]:map>
 *
 */

static VALUE
rb_ary_collect(VALUE ary)
{
    long i;
    VALUE collect;

    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    collect = rb_ary_new2(RARRAY_LEN(ary));
    for (i = 0; i < RARRAY_LEN(ary); i++) {
        rb_ary_push(collect, rb_yield(RARRAY_AREF(ary, i)));
    }
    return collect;
}


/*
 *  call-seq:
 *    array.map! {|element| ... } -> self
 *    array.map! -> new_enumerator
 *
 *  Calls the block, if given, with each element;
 *  replaces the element with the block's return value:
 *
 *    a = [:foo, 'bar', 2]
 *    a.map! { |element| element.class } # => [Symbol, String, Integer]
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.map!
 *    a1 # => #<Enumerator: [:foo, "bar", 2]:map!>
 *
 */

static VALUE
rb_ary_collect_bang(VALUE ary)
{
    long i;

    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    rb_ary_modify(ary);
    for (i = 0; i < RARRAY_LEN(ary); i++) {
        rb_ary_store(ary, i, rb_yield(RARRAY_AREF(ary, i)));
    }
    return ary;
}

VALUE
rb_get_values_at(VALUE obj, long olen, int argc, const VALUE *argv, VALUE (*func) (VALUE, long))
{
    VALUE result = rb_ary_new2(argc);
    long beg, len, i, j;

    for (i=0; i<argc; i++) {
        if (FIXNUM_P(argv[i])) {
            rb_ary_push(result, (*func)(obj, FIX2LONG(argv[i])));
            continue;
        }
        /* check if idx is Range */
        if (rb_range_beg_len(argv[i], &beg, &len, olen, 1)) {
            long end = olen < beg+len ? olen : beg+len;
            for (j = beg; j < end; j++) {
                rb_ary_push(result, (*func)(obj, j));
            }
            if (beg + len > j)
                rb_ary_resize(result, RARRAY_LEN(result) + (beg + len) - j);
            continue;
        }
        rb_ary_push(result, (*func)(obj, NUM2LONG(argv[i])));
    }
    return result;
}

static VALUE
append_values_at_single(VALUE result, VALUE ary, long olen, VALUE idx)
{
    long beg, len;
    if (FIXNUM_P(idx)) {
        beg = FIX2LONG(idx);
    }
    /* check if idx is Range */
    else if (rb_range_beg_len(idx, &beg, &len, olen, 1)) {
        if (len > 0) {
            const VALUE *const src = RARRAY_CONST_PTR(ary);
            const long end = beg + len;
            const long prevlen = RARRAY_LEN(result);
            if (beg < olen) {
                rb_ary_cat(result, src + beg, end > olen ? olen-beg : len);
            }
            if (end > olen) {
                rb_ary_store(result, prevlen + len - 1, Qnil);
            }
        }
        return result;
    }
    else {
        beg = NUM2LONG(idx);
    }
    return rb_ary_push(result, rb_ary_entry(ary, beg));
}

/*
 *  call-seq:
 *    array.values_at(*indexes) -> new_array
 *
 *  Returns a new +Array+ whose elements are the elements
 *  of +self+ at the given Integer or Range +indexes+.
 *
 *  For each positive +index+, returns the element at offset +index+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, 2) # => [:foo, 2]
 *    a.values_at(0..1) # => [:foo, "bar"]
 *
 *  The given +indexes+ may be in any order, and may repeat:
 *
 *    a = [:foo, 'bar', 2]
 *    a.values_at(2, 0, 1, 0, 2) # => [2, :foo, "bar", :foo, 2]
 *    a.values_at(1, 0..2) # => ["bar", :foo, "bar", 2]
 *
 *  Assigns +nil+ for an +index+ that is too large:
 *
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, 3, 1, 3) # => [:foo, nil, "bar", nil]
 *
 *  Returns a new empty +Array+ if no arguments given.
 *
 *  For each negative +index+, counts backward from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a.values_at(-1, -3) # => [2, :foo]
 *
 *  Assigns +nil+ for an +index+ that is too small:
 *
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, -5, 1, -6, 2) # => [:foo, nil, "bar", nil, 2]
 *
 *  The given +indexes+ may have a mixture of signs:
 *
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, -2, 1, -1) # => [:foo, "bar", "bar", 2]
 *
 */

static VALUE
rb_ary_values_at(int argc, VALUE *argv, VALUE ary)
{
    long i, olen = RARRAY_LEN(ary);
    VALUE result = rb_ary_new_capa(argc);
    for (i = 0; i < argc; ++i) {
        append_values_at_single(result, ary, olen, argv[i]);
    }
    RB_GC_GUARD(ary);
    return result;
}


/*
 *  call-seq:
 *    array.select {|element| ... } -> new_array
 *    array.select -> new_enumerator
 *
 *  Calls the block, if given, with each element of +self+;
 *  returns a new +Array+ containing those elements of +self+
 *  for which the block returns a truthy value:
 *
 *    a = [:foo, 'bar', 2, :bam]
 *    a1 = a.select {|element| element.to_s.start_with?('b') }
 *    a1 # => ["bar", :bam]
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [:foo, 'bar', 2, :bam]
 *    a.select # => #<Enumerator: [:foo, "bar", 2, :bam]:select>
 *
 */

static VALUE
rb_ary_select(VALUE ary)
{
    VALUE result;
    long i;

    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    result = rb_ary_new2(RARRAY_LEN(ary));
    for (i = 0; i < RARRAY_LEN(ary); i++) {
        if (RTEST(rb_yield(RARRAY_AREF(ary, i)))) {
            rb_ary_push(result, rb_ary_elt(ary, i));
        }
    }
    return result;
}

struct select_bang_arg {
    VALUE ary;
    long len[2];
};

static VALUE
select_bang_i(VALUE a)
{
    volatile struct select_bang_arg *arg = (void *)a;
    VALUE ary = arg->ary;
    long i1, i2;

    for (i1 = i2 = 0; i1 < RARRAY_LEN(ary); arg->len[0] = ++i1) {
        VALUE v = RARRAY_AREF(ary, i1);
        if (!RTEST(rb_yield(v))) continue;
        if (i1 != i2) {
            rb_ary_store(ary, i2, v);
        }
        arg->len[1] = ++i2;
    }
    return (i1 == i2) ? Qnil : ary;
}

static VALUE
select_bang_ensure(VALUE a)
{
    volatile struct select_bang_arg *arg = (void *)a;
    VALUE ary = arg->ary;
    long len = RARRAY_LEN(ary);
    long i1 = arg->len[0], i2 = arg->len[1];

    if (i2 < len && i2 < i1) {
        long tail = 0;
        rb_ary_modify(ary);
        if (i1 < len) {
            tail = len - i1;
            RARRAY_PTR_USE(ary, ptr, {
                    MEMMOVE(ptr + i2, ptr + i1, VALUE, tail);
                });
        }
        ARY_SET_LEN(ary, i2 + tail);
    }
    return ary;
}

/*
 *  call-seq:
 *    array.select! {|element| ... } -> self or nil
 *    array.select! -> new_enumerator
 *
 *  Calls the block, if given  with each element of +self+;
 *  removes from +self+ those elements for which the block returns +false+ or +nil+.
 *
 *  Returns +self+ if any elements were removed:
 *
 *    a = [:foo, 'bar', 2, :bam]
 *    a.select! {|element| element.to_s.start_with?('b') } # => ["bar", :bam]
 *
 *  Returns +nil+ if no elements were removed.
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [:foo, 'bar', 2, :bam]
 *    a.select! # => #<Enumerator: [:foo, "bar", 2, :bam]:select!>
 *
 */

static VALUE
rb_ary_select_bang(VALUE ary)
{
    struct select_bang_arg args;

    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    rb_ary_modify(ary);

    args.ary = ary;
    args.len[0] = args.len[1] = 0;
    return rb_ensure(select_bang_i, (VALUE)&args, select_bang_ensure, (VALUE)&args);
}

/*
 *  call-seq:
 *    array.keep_if {|element| ... } -> self
 *    array.keep_if -> new_enumeration
 *
 *  Retains those elements for which the block returns a truthy value;
 *  deletes all other elements; returns +self+:
 *
 *    a = [:foo, 'bar', 2, :bam]
 *    a.keep_if {|element| element.to_s.start_with?('b') } # => ["bar", :bam]
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [:foo, 'bar', 2, :bam]
 *    a.keep_if # => #<Enumerator: [:foo, "bar", 2, :bam]:keep_if>
 *
 */

static VALUE
rb_ary_keep_if(VALUE ary)
{
    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    rb_ary_select_bang(ary);
    return ary;
}

static void
ary_resize_smaller(VALUE ary, long len)
{
    rb_ary_modify(ary);
    if (RARRAY_LEN(ary) > len) {
        ARY_SET_LEN(ary, len);
        if (len * 2 < ARY_CAPA(ary) &&
            ARY_CAPA(ary) > ARY_DEFAULT_SIZE) {
            ary_resize_capa(ary, len * 2);
        }
    }
}

/*
 *  call-seq:
 *    array.delete(obj) -> deleted_object
 *    array.delete(obj) {|nosuch| ... } -> deleted_object or block_return
 *
 *  Removes zero or more elements from +self+.
 *
 *  When no block is given,
 *  removes from +self+ each element +ele+ such that <tt>ele == obj</tt>;
 *  returns the last deleted element:
 *
 *    s1 = 'bar'; s2 = 'bar'
 *    a = [:foo, s1, 2, s2]
 *    a.delete('bar') # => "bar"
 *    a # => [:foo, 2]
 *
 *  Returns +nil+ if no elements removed.
 *
 *  When a block is given,
 *  removes from +self+ each element +ele+ such that <tt>ele == obj</tt>.
 *
 *  If any such elements are found, ignores the block
 *  and returns the last deleted element:
 *
 *    s1 = 'bar'; s2 = 'bar'
 *    a = [:foo, s1, 2, s2]
 *    deleted_obj = a.delete('bar') {|obj| fail 'Cannot happen' }
 *    a # => [:foo, 2]
 *
 *  If no such elements are found, returns the block's return value:
 *
 *    a = [:foo, 'bar', 2]
 *    a.delete(:nosuch) {|obj| "#{obj} not found" } # => "nosuch not found"
 *
 */

VALUE
rb_ary_delete(VALUE ary, VALUE item)
{
    VALUE v = item;
    long i1, i2;

    for (i1 = i2 = 0; i1 < RARRAY_LEN(ary); i1++) {
        VALUE e = RARRAY_AREF(ary, i1);

        if (rb_equal(e, item)) {
            v = e;
            continue;
        }
        if (i1 != i2) {
            rb_ary_store(ary, i2, e);
        }
        i2++;
    }
    if (RARRAY_LEN(ary) == i2) {
        if (rb_block_given_p()) {
            return rb_yield(item);
        }
        return Qnil;
    }

    ary_resize_smaller(ary, i2);

    ary_verify(ary);
    return v;
}

void
rb_ary_delete_same(VALUE ary, VALUE item)
{
    long i1, i2;

    for (i1 = i2 = 0; i1 < RARRAY_LEN(ary); i1++) {
        VALUE e = RARRAY_AREF(ary, i1);

        if (e == item) {
            continue;
        }
        if (i1 != i2) {
            rb_ary_store(ary, i2, e);
        }
        i2++;
    }
    if (RARRAY_LEN(ary) == i2) {
        return;
    }

    ary_resize_smaller(ary, i2);
}

VALUE
rb_ary_delete_at(VALUE ary, long pos)
{
    long len = RARRAY_LEN(ary);
    VALUE del;

    if (pos >= len) return Qnil;
    if (pos < 0) {
        pos += len;
        if (pos < 0) return Qnil;
    }

    rb_ary_modify(ary);
    del = RARRAY_AREF(ary, pos);
    RARRAY_PTR_USE(ary, ptr, {
        MEMMOVE(ptr+pos, ptr+pos+1, VALUE, len-pos-1);
    });
    ARY_INCREASE_LEN(ary, -1);
    ary_verify(ary);
    return del;
}

/*
 *  call-seq:
 *    array.delete_at(index) -> deleted_object or nil
 *
 *  Deletes an element from +self+, per the given Integer +index+.
 *
 *  When +index+ is non-negative, deletes the element at offset +index+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.delete_at(1) # => "bar"
 *    a # => [:foo, 2]
 *
 *  If index is too large, returns +nil+.
 *
 *  When +index+ is negative, counts backward from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a.delete_at(-2) # => "bar"
 *    a # => [:foo, 2]
 *
 *  If +index+ is too small (far from zero), returns nil.
 */

static VALUE
rb_ary_delete_at_m(VALUE ary, VALUE pos)
{
    return rb_ary_delete_at(ary, NUM2LONG(pos));
}

static VALUE
ary_slice_bang_by_rb_ary_splice(VALUE ary, long pos, long len)
{
    const long orig_len = RARRAY_LEN(ary);

    if (len < 0) {
        return Qnil;
    }
    else if (pos < -orig_len) {
        return Qnil;
    }
    else if (pos < 0) {
        pos += orig_len;
    }
    else if (orig_len < pos) {
        return Qnil;
    }
    if (orig_len < pos + len) {
        len = orig_len - pos;
    }
    if (len == 0) {
        return rb_ary_new2(0);
    }
    else {
        VALUE arg2 = rb_ary_new4(len, RARRAY_CONST_PTR(ary)+pos);
        rb_ary_splice(ary, pos, len, 0, 0);
        return arg2;
    }
}

/*
 *  call-seq:
 *    array.slice!(n) -> object or nil
 *    array.slice!(start, length) -> new_array or nil
 *    array.slice!(range) -> new_array or nil
 *
 *  Removes and returns elements from +self+.
 *
 *  When the only argument is an Integer +n+,
 *  removes and returns the _nth_ element in +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.slice!(1) # => "bar"
 *    a # => [:foo, 2]
 *
 *  If +n+ is negative, counts backwards from the end of +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.slice!(-1) # => 2
 *    a # => [:foo, "bar"]
 *
 *  If +n+ is out of range, returns +nil+.
 *
 *  When the only arguments are Integers +start+ and +length+,
 *  removes +length+ elements from +self+ beginning at offset  +start+;
 *  returns the deleted objects in a new +Array+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.slice!(0, 2) # => [:foo, "bar"]
 *    a # => [2]
 *
 *  If <tt>start + length</tt> exceeds the array size,
 *  removes and returns all elements from offset +start+ to the end:
 *
 *    a = [:foo, 'bar', 2]
 *    a.slice!(1, 50) # => ["bar", 2]
 *    a # => [:foo]
 *
 *  If <tt>start == a.size</tt> and +length+ is non-negative,
 *  returns a new empty +Array+.
 *
 *  If +length+ is negative, returns +nil+.
 *
 *  When the only argument is a Range object +range+,
 *  treats <tt>range.min</tt> as +start+ above and <tt>range.size</tt> as +length+ above:
 *
 *    a = [:foo, 'bar', 2]
 *    a.slice!(1..2) # => ["bar", 2]
 *    a # => [:foo]
 *
 *  If <tt>range.start == a.size</tt>, returns a new empty +Array+.
 *
 *  If <tt>range.start</tt> is larger than the array size, returns +nil+.
 *
 *  If <tt>range.end</tt> is negative, counts backwards from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a.slice!(0..-2) # => [:foo, "bar"]
 *    a # => [2]
 *
 *  If <tt>range.start</tt> is negative,
 *  calculates the start index backwards from the end of the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a.slice!(-2..2) # => ["bar", 2]
 *    a # => [:foo]
 *
 */

static VALUE
rb_ary_slice_bang(int argc, VALUE *argv, VALUE ary)
{
    VALUE arg1;
    long pos, len;

    rb_ary_modify_check(ary);
    rb_check_arity(argc, 1, 2);
    arg1 = argv[0];

    if (argc == 2) {
        pos = NUM2LONG(argv[0]);
        len = NUM2LONG(argv[1]);
        return ary_slice_bang_by_rb_ary_splice(ary, pos, len);
    }

    if (!FIXNUM_P(arg1)) {
        switch (rb_range_beg_len(arg1, &pos, &len, RARRAY_LEN(ary), 0)) {
          case Qtrue:
            /* valid range */
            return ary_slice_bang_by_rb_ary_splice(ary, pos, len);
          case Qnil:
            /* invalid range */
            return Qnil;
          default:
            /* not a range */
            break;
        }
    }

    return rb_ary_delete_at(ary, NUM2LONG(arg1));
}

static VALUE
ary_reject(VALUE orig, VALUE result)
{
    long i;

    for (i = 0; i < RARRAY_LEN(orig); i++) {
        VALUE v = RARRAY_AREF(orig, i);

        if (!RTEST(rb_yield(v))) {
            rb_ary_push(result, v);
        }
    }
    return result;
}

static VALUE
reject_bang_i(VALUE a)
{
    volatile struct select_bang_arg *arg = (void *)a;
    VALUE ary = arg->ary;
    long i1, i2;

    for (i1 = i2 = 0; i1 < RARRAY_LEN(ary); arg->len[0] = ++i1) {
        VALUE v = RARRAY_AREF(ary, i1);
        if (RTEST(rb_yield(v))) continue;
        if (i1 != i2) {
            rb_ary_store(ary, i2, v);
        }
        arg->len[1] = ++i2;
    }
    return (i1 == i2) ? Qnil : ary;
}

static VALUE
ary_reject_bang(VALUE ary)
{
    struct select_bang_arg args;
    rb_ary_modify_check(ary);
    args.ary = ary;
    args.len[0] = args.len[1] = 0;
    return rb_ensure(reject_bang_i, (VALUE)&args, select_bang_ensure, (VALUE)&args);
}

/*
 *  call-seq:
 *    array.reject! {|element| ... } -> self or nil
 *    array.reject! -> new_enumerator
 *
 *  Removes each element for which the block returns a truthy value.
 *
 *  Returns +self+ if any elements removed:
 *
 *    a = [:foo, 'bar', 2, 'bat']
 *    a.reject! {|element| element.to_s.start_with?('b') } # => [:foo, 2]
 *
 *  Returns +nil+ if no elements removed.
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [:foo, 'bar', 2]
 *    a.reject! # => #<Enumerator: [:foo, "bar", 2]:reject!>
 *
 */

static VALUE
rb_ary_reject_bang(VALUE ary)
{
    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    rb_ary_modify(ary);
    return ary_reject_bang(ary);
}

/*
 *  call-seq:
 *    array.reject {|element| ... } -> new_array
 *    array.reject -> new_enumerator
 *
 *  Returns a new +Array+ whose elements are all those from +self+
 *  for which the block returns +false+ or +nil+:
 *
 *    a = [:foo, 'bar', 2, 'bat']
 *    a1 = a.reject {|element| element.to_s.start_with?('b') }
 *    a1 # => [:foo, 2]
 *
 *  Returns a new Enumerator if no block given:
 *
 *     a = [:foo, 'bar', 2]
 *     a.reject # => #<Enumerator: [:foo, "bar", 2]:reject>
 *
 */

static VALUE
rb_ary_reject(VALUE ary)
{
    VALUE rejected_ary;

    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    rejected_ary = rb_ary_new();
    ary_reject(ary, rejected_ary);
    return rejected_ary;
}

/*
 *  call-seq:
 *    array.delete_if {|element| ... } -> self
 *    array.delete_if -> Enumerator
 *
 *  Removes each element in +self+ for which the block returns a truthy value;
 *  returns +self+:
 *
 *    a = [:foo, 'bar', 2, 'bat']
 *    a.delete_if {|element| element.to_s.start_with?('b') } # => [:foo, 2]
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [:foo, 'bar', 2]
 *    a.delete_if # => #<Enumerator: [:foo, "bar", 2]:delete_if>
 *
 */

static VALUE
rb_ary_delete_if(VALUE ary)
{
    ary_verify(ary);
    RETURN_SIZED_ENUMERATOR(ary, 0, 0, ary_enum_length);
    ary_reject_bang(ary);
    return ary;
}

static VALUE
take_i(RB_BLOCK_CALL_FUNC_ARGLIST(val, cbarg))
{
    VALUE *args = (VALUE *)cbarg;
    if (argc > 1) val = rb_ary_new4(argc, argv);
    rb_ary_push(args[0], val);
    if (--args[1] == 0) rb_iter_break();
    return Qnil;
}

static VALUE
take_items(VALUE obj, long n)
{
    VALUE result = rb_check_array_type(obj);
    VALUE args[2];

    if (n == 0) return result;
    if (!NIL_P(result)) return rb_ary_subseq(result, 0, n);
    result = rb_ary_new2(n);
    args[0] = result; args[1] = (VALUE)n;
    if (UNDEF_P(rb_check_block_call(obj, idEach, 0, 0, take_i, (VALUE)args)))
        rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (must respond to :each)",
                 rb_obj_class(obj));
    return result;
}


/*
 *  call-seq:
 *    array.zip(*other_arrays) -> new_array
 *    array.zip(*other_arrays) {|other_array| ... } -> nil
 *
 *  When no block given, returns a new +Array+ +new_array+ of size <tt>self.size</tt>
 *  whose elements are Arrays.
 *
 *  Each nested array <tt>new_array[n]</tt> is of size <tt>other_arrays.size+1</tt>,
 *  and contains:
 *
 *  - The _nth_ element of +self+.
 *  - The _nth_ element of each of the +other_arrays+.
 *
 *  If all +other_arrays+ and +self+ are the same size:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3]
 *    c = [:c0, :c1, :c2, :c3]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, :c2], [:a3, :b3, :c3]]
 *
 *  If any array in +other_arrays+ is smaller than +self+,
 *  fills to <tt>self.size</tt> with +nil+:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2]
 *    c = [:c0, :c1]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, nil], [:a3, nil, nil]]
 *
 *  If any array in +other_arrays+ is larger than +self+,
 *  its trailing elements are ignored:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3, :b4]
 *    c = [:c0, :c1, :c2, :c3, :c4, :c5]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, :c2], [:a3, :b3, :c3]]
 *
 *  If an argument is not an array, it extracts the values by calling #each:
 *
 *  a = [:a0, :a1, :a2, :a2]
 *  b = 1..4
 *  c = a.zip(b)
 *  c # => [[:a0, 1], [:a1, 2], [:a2, 3], [:a2, 4]]
 *
 *  When a block is given, calls the block with each of the sub-arrays (formed as above); returns +nil+:
 *
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3]
 *    c = [:c0, :c1, :c2, :c3]
 *    a.zip(b, c) {|sub_array| p sub_array} # => nil
 *
 *  Output:
 *
 *    [:a0, :b0, :c0]
 *    [:a1, :b1, :c1]
 *    [:a2, :b2, :c2]
 *    [:a3, :b3, :c3]
 *
 */

static VALUE
rb_ary_zip(int argc, VALUE *argv, VALUE ary)
{
    int i, j;
    long len = RARRAY_LEN(ary);
    VALUE result = Qnil;

    for (i=0; i<argc; i++) {
        argv[i] = take_items(argv[i], len);
    }

    if (rb_block_given_p()) {
        int arity = rb_block_arity();

        if (arity > 1) {
            VALUE work, *tmp;

            tmp = ALLOCV_N(VALUE, work, argc+1);

            for (i=0; i<RARRAY_LEN(ary); i++) {
                tmp[0] = RARRAY_AREF(ary, i);
                for (j=0; j<argc; j++) {
                    tmp[j+1] = rb_ary_elt(argv[j], i);
                }
                rb_yield_values2(argc+1, tmp);
            }

            if (work) ALLOCV_END(work);
        }
        else {
            for (i=0; i<RARRAY_LEN(ary); i++) {
                VALUE tmp = rb_ary_new2(argc+1);

                rb_ary_push(tmp, RARRAY_AREF(ary, i));
                for (j=0; j<argc; j++) {
                    rb_ary_push(tmp, rb_ary_elt(argv[j], i));
                }
                rb_yield(tmp);
            }
        }
    }
    else {
        result = rb_ary_new_capa(len);

        for (i=0; i<len; i++) {
            VALUE tmp = rb_ary_new_capa(argc+1);

            rb_ary_push(tmp, RARRAY_AREF(ary, i));
            for (j=0; j<argc; j++) {
                rb_ary_push(tmp, rb_ary_elt(argv[j], i));
            }
            rb_ary_push(result, tmp);
        }
    }

    return result;
}

/*
 *  call-seq:
 *    array.transpose -> new_array
 *
 *  Transposes the rows and columns in an +Array+ of Arrays;
 *  the nested Arrays must all be the same size:
 *
 *    a = [[:a0, :a1], [:b0, :b1], [:c0, :c1]]
 *    a.transpose # => [[:a0, :b0, :c0], [:a1, :b1, :c1]]
 *
 */

static VALUE
rb_ary_transpose(VALUE ary)
{
    long elen = -1, alen, i, j;
    VALUE tmp, result = 0;

    alen = RARRAY_LEN(ary);
    if (alen == 0) return rb_ary_dup(ary);
    for (i=0; i<alen; i++) {
        tmp = to_ary(rb_ary_elt(ary, i));
        if (elen < 0) {		/* first element */
            elen = RARRAY_LEN(tmp);
            result = rb_ary_new2(elen);
            for (j=0; j<elen; j++) {
                rb_ary_store(result, j, rb_ary_new2(alen));
            }
        }
        else if (elen != RARRAY_LEN(tmp)) {
            rb_raise(rb_eIndexError, "element size differs (%ld should be %ld)",
                     RARRAY_LEN(tmp), elen);
        }
        for (j=0; j<elen; j++) {
            rb_ary_store(rb_ary_elt(result, j), i, rb_ary_elt(tmp, j));
        }
    }
    return result;
}

/*
 *  call-seq:
 *    array.replace(other_array) -> self
 *
 *  Replaces the content of +self+ with the content of +other_array+; returns +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.replace(['foo', :bar, 3]) # => ["foo", :bar, 3]
 *
 */

VALUE
rb_ary_replace(VALUE copy, VALUE orig)
{
    rb_ary_modify_check(copy);
    orig = to_ary(orig);
    if (copy == orig) return copy;

    rb_ary_reset(copy);

    /* orig has enough space to embed the contents of orig. */
    if (RARRAY_LEN(orig) <= ary_embed_capa(copy)) {
        RUBY_ASSERT(ARY_EMBED_P(copy));
        ary_memcpy(copy, 0, RARRAY_LEN(orig), RARRAY_CONST_PTR(orig));
        ARY_SET_EMBED_LEN(copy, RARRAY_LEN(orig));
    }
    /* orig is embedded but copy does not have enough space to embed the
     * contents of orig. */
    else if (ARY_EMBED_P(orig)) {
        long len = ARY_EMBED_LEN(orig);
        VALUE *ptr = ary_heap_alloc_buffer(len);

        FL_UNSET_EMBED(copy);
        ARY_SET_PTR(copy, ptr);
        ARY_SET_LEN(copy, len);
        ARY_SET_CAPA(copy, len);

        // No allocation and exception expected that could leave `copy` in a
        // bad state from the edits above.
        ary_memcpy(copy, 0, len, RARRAY_CONST_PTR(orig));
    }
    /* Otherwise, orig is on heap and copy does not have enough space to embed
     * the contents of orig. */
    else {
        VALUE shared_root = ary_make_shared(orig);
        FL_UNSET_EMBED(copy);
        ARY_SET_PTR(copy, ARY_HEAP_PTR(orig));
        ARY_SET_LEN(copy, ARY_HEAP_LEN(orig));
        rb_ary_set_shared(copy, shared_root);
    }
    ary_verify(copy);
    return copy;
}

/*
 *  call-seq:
 *     array.clear -> self
 *
 *  Removes all elements from +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.clear # => []
 *
 */

VALUE
rb_ary_clear(VALUE ary)
{
    rb_ary_modify_check(ary);
    if (ARY_SHARED_P(ary)) {
        if (!ARY_EMBED_P(ary)) {
            rb_ary_unshare(ary);
            FL_SET_EMBED(ary);
            ARY_SET_EMBED_LEN(ary, 0);
        }
    }
    else {
        ARY_SET_LEN(ary, 0);
        if (ARY_DEFAULT_SIZE * 2 < ARY_CAPA(ary)) {
            ary_resize_capa(ary, ARY_DEFAULT_SIZE * 2);
        }
    }
    ary_verify(ary);
    return ary;
}

/*
 *  call-seq:
 *    array.fill(obj) -> self
 *    array.fill(obj, start) -> self
 *    array.fill(obj, start, length) -> self
 *    array.fill(obj, range) -> self
 *    array.fill {|index| ... } -> self
 *    array.fill(start) {|index| ... } -> self
 *    array.fill(start, length) {|index| ... } -> self
 *    array.fill(range) {|index| ... } -> self
 *
 *  Replaces specified elements in +self+ with specified objects; returns +self+.
 *
 *  With argument +obj+ and no block given, replaces all elements with that one object:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a # => ["a", "b", "c", "d"]
 *    a.fill(:X) # => [:X, :X, :X, :X]
 *
 *  With arguments +obj+ and Integer +start+, and no block given,
 *  replaces elements based on the given start.
 *
 *  If +start+ is in range (<tt>0 <= start < array.size</tt>),
 *  replaces all elements from offset +start+ through the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 2) # => ["a", "b", :X, :X]
 *
 *  If +start+ is too large (<tt>start >= array.size</tt>), does nothing:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 4) # => ["a", "b", "c", "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 5) # => ["a", "b", "c", "d"]
 *
 *  If +start+ is negative, counts from the end (starting index is <tt>start + array.size</tt>):
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -2) # => ["a", "b", :X, :X]
 *
 *  If +start+ is too small (less than and far from zero), replaces all elements:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -6) # => [:X, :X, :X, :X]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -50) # => [:X, :X, :X, :X]
 *
 *  With arguments +obj+, Integer +start+, and Integer +length+, and no block given,
 *  replaces elements based on the given +start+ and +length+.
 *
 *  If +start+ is in range, replaces +length+ elements beginning at offset +start+:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 1, 1) # => ["a", :X, "c", "d"]
 *
 *  If +start+ is negative, counts from the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -2, 1) # => ["a", "b", :X, "d"]
 *
 *  If +start+ is large (<tt>start >= array.size</tt>), extends +self+ with +nil+:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 5, 0) # => ["a", "b", "c", "d", nil]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 5, 2) # => ["a", "b", "c", "d", nil, :X, :X]
 *
 *  If +length+ is zero or negative, replaces no elements:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 1, 0) # => ["a", "b", "c", "d"]
 *    a.fill(:X, 1, -1) # => ["a", "b", "c", "d"]
 *
 *  With arguments +obj+ and Range +range+, and no block given,
 *  replaces elements based on the given range.
 *
 *  If the range is positive and ascending (<tt>0 < range.begin <= range.end</tt>),
 *  replaces elements from <tt>range.begin</tt> to <tt>range.end</tt>:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (1..1)) # => ["a", :X, "c", "d"]
 *
 *  If <tt>range.first</tt> is negative, replaces no elements:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (-1..1)) # => ["a", "b", "c", "d"]
 *
 *  If <tt>range.last</tt> is negative, counts from the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (0..-2)) # => [:X, :X, :X, "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (1..-2)) # => ["a", :X, :X, "d"]
 *
 *  If <tt>range.last</tt> and <tt>range.last</tt> are both negative,
 *  both count from the end of the array:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (-1..-1)) # => ["a", "b", "c", :X]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (-2..-2)) # => ["a", "b", :X, "d"]
 *
 *  With no arguments and a block given, calls the block with each index;
 *  replaces the corresponding element with the block's return value:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "new_3"]
 *
 *  With argument +start+ and a block given, calls the block with each index
 *  from offset +start+ to the end; replaces the corresponding element
 *  with the block's return value.
 *
 *  If start is in range (<tt>0 <= start < array.size</tt>),
 *  replaces from offset +start+ to the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1) { |index| "new_#{index}" } # => ["a", "new_1", "new_2", "new_3"]
 *
 *  If +start+ is too large(<tt>start >= array.size</tt>), does nothing:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(4) { |index| fail 'Cannot happen' } # => ["a", "b", "c", "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(4) { |index| fail 'Cannot happen' } # => ["a", "b", "c", "d"]
 *
 *  If +start+ is negative, counts from the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-2) { |index| "new_#{index}" } # => ["a", "b", "new_2", "new_3"]
 *
 *  If start is too small (<tt>start <= -array.size</tt>, replaces all elements:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-6) { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "new_3"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-50) { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "new_3"]
 *
 *  With arguments +start+ and +length+, and a block given,
 *  calls the block for each index specified by start length;
 *  replaces the corresponding element with the block's return value.
 *
 *  If +start+ is in range, replaces +length+ elements beginning at offset +start+:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1, 1) { |index| "new_#{index}" } # => ["a", "new_1", "c", "d"]
 *
 *  If start is negative, counts from the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-2, 1) { |index| "new_#{index}" } # => ["a", "b", "new_2", "d"]
 *
 *  If +start+ is large (<tt>start >= array.size</tt>), extends +self+ with +nil+:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(5, 0) { |index| "new_#{index}" } # => ["a", "b", "c", "d", nil]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(5, 2) { |index| "new_#{index}" } # => ["a", "b", "c", "d", nil, "new_5", "new_6"]
 *
 *  If +length+ is zero or less, replaces no elements:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1, 0) { |index| "new_#{index}" } # => ["a", "b", "c", "d"]
 *    a.fill(1, -1) { |index| "new_#{index}" } # => ["a", "b", "c", "d"]
 *
 *  With arguments +obj+ and +range+, and a block given,
 *  calls the block with each index in the given range;
 *  replaces the corresponding element with the block's return value.
 *
 *  If the range is positive and ascending (<tt>range 0 < range.begin <= range.end</tt>,
 *  replaces elements from <tt>range.begin</tt> to <tt>range.end</tt>:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1..1) { |index| "new_#{index}" } # => ["a", "new_1", "c", "d"]
 *
 *  If +range.first+ is negative, does nothing:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-1..1) { |index| fail 'Cannot happen' } # => ["a", "b", "c", "d"]
 *
 *  If <tt>range.last</tt> is negative, counts from the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(0..-2) { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1..-2) { |index| "new_#{index}" } # => ["a", "new_1", "new_2", "d"]
 *
 *  If <tt>range.first</tt> and <tt>range.last</tt> are both negative,
 *  both count from the end:
 *
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-1..-1) { |index| "new_#{index}" } # => ["a", "b", "c", "new_3"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-2..-2) { |index| "new_#{index}" } # => ["a", "b", "new_2", "d"]
 *
 */

static VALUE
rb_ary_fill(int argc, VALUE *argv, VALUE ary)
{
    VALUE item = Qundef, arg1, arg2;
    long beg = 0, end = 0, len = 0;

    if (rb_block_given_p()) {
        rb_scan_args(argc, argv, "02", &arg1, &arg2);
        argc += 1;		/* hackish */
    }
    else {
        rb_scan_args(argc, argv, "12", &item, &arg1, &arg2);
    }
    switch (argc) {
      case 1:
        beg = 0;
        len = RARRAY_LEN(ary);
        break;
      case 2:
        if (rb_range_beg_len(arg1, &beg, &len, RARRAY_LEN(ary), 1)) {
            break;
        }
        /* fall through */
      case 3:
        beg = NIL_P(arg1) ? 0 : NUM2LONG(arg1);
        if (beg < 0) {
            beg = RARRAY_LEN(ary) + beg;
            if (beg < 0) beg = 0;
        }
        len = NIL_P(arg2) ? RARRAY_LEN(ary) - beg : NUM2LONG(arg2);
        break;
    }
    rb_ary_modify(ary);
    if (len < 0) {
        return ary;
    }
    if (beg >= ARY_MAX_SIZE || len > ARY_MAX_SIZE - beg) {
        rb_raise(rb_eArgError, "argument too big");
    }
    end = beg + len;
    if (RARRAY_LEN(ary) < end) {
        if (end >= ARY_CAPA(ary)) {
            ary_resize_capa(ary, end);
        }
        ary_mem_clear(ary, RARRAY_LEN(ary), end - RARRAY_LEN(ary));
        ARY_SET_LEN(ary, end);
    }

    if (UNDEF_P(item)) {
        VALUE v;
        long i;

        for (i=beg; i<end; i++) {
            v = rb_yield(LONG2NUM(i));
            if (i>=RARRAY_LEN(ary)) break;
            ARY_SET(ary, i, v);
        }
    }
    else {
        ary_memfill(ary, beg, len, item);
    }
    return ary;
}

/*
 *  call-seq:
 *    self + other_array -> new_array
 *
 *  Returns a new array containing all elements of +self+
 *  followed by all elements of +other_array+:
 *
 *    a = [0, 1] + [2, 3]
 *    a # => [0, 1, 2, 3]
 *
 *  Related: Array#concat, Array#*.
 */

VALUE
rb_ary_plus(VALUE x, VALUE y)
{
    VALUE z;
    long len, xlen, ylen;

    y = to_ary(y);
    xlen = RARRAY_LEN(x);
    ylen = RARRAY_LEN(y);
    len = xlen + ylen;
    z = rb_ary_new2(len);

    ary_memcpy(z, 0, xlen, RARRAY_CONST_PTR(x));
    ary_memcpy(z, xlen, ylen, RARRAY_CONST_PTR(y));
    ARY_SET_LEN(z, len);
    return z;
}

static VALUE
ary_append(VALUE x, VALUE y)
{
    long n = RARRAY_LEN(y);
    if (n > 0) {
        rb_ary_splice(x, RARRAY_LEN(x), 0, RARRAY_CONST_PTR(y), n);
    }
    RB_GC_GUARD(y);
    return x;
}

/*
 *  call-seq:
 *    array.concat(*other_arrays) -> self
 *
 *  Adds to +array+ all elements from each +Array+ in +other_arrays+; returns +self+:
 *
 *    a = [0, 1]
 *    a.concat([2, 3], [4, 5]) # => [0, 1, 2, 3, 4, 5]
 */

static VALUE
rb_ary_concat_multi(int argc, VALUE *argv, VALUE ary)
{
    rb_ary_modify_check(ary);

    if (argc == 1) {
        rb_ary_concat(ary, argv[0]);
    }
    else if (argc > 1) {
        int i;
        VALUE args = rb_ary_hidden_new(argc);
        for (i = 0; i < argc; i++) {
            rb_ary_concat(args, argv[i]);
        }
        ary_append(ary, args);
    }

    ary_verify(ary);
    return ary;
}

VALUE
rb_ary_concat(VALUE x, VALUE y)
{
    return ary_append(x, to_ary(y));
}

/*
 *  call-seq:
 *    array * n -> new_array
 *    array * string_separator -> new_string
 *
 *  When non-negative argument Integer +n+ is given,
 *  returns a new +Array+ built by concatenating the +n+ copies of +self+:
 *
 *    a = ['x', 'y']
 *    a * 3 # => ["x", "y", "x", "y", "x", "y"]
 *
 *  When String argument +string_separator+ is given,
 *  equivalent to <tt>array.join(string_separator)</tt>:
 *
 *    [0, [0, 1], {foo: 0}] * ', ' # => "0, 0, 1, {:foo=>0}"
 *
 */

static VALUE
rb_ary_times(VALUE ary, VALUE times)
{
    VALUE ary2, tmp;
    const VALUE *ptr;
    long t, len;

    tmp = rb_check_string_type(times);
    if (!NIL_P(tmp)) {
        return rb_ary_join(ary, tmp);
    }

    len = NUM2LONG(times);
    if (len == 0) {
        ary2 = ary_new(rb_cArray, 0);
        goto out;
    }
    if (len < 0) {
        rb_raise(rb_eArgError, "negative argument");
    }
    if (ARY_MAX_SIZE/len < RARRAY_LEN(ary)) {
        rb_raise(rb_eArgError, "argument too big");
    }
    len *= RARRAY_LEN(ary);

    ary2 = ary_new(rb_cArray, len);
    ARY_SET_LEN(ary2, len);

    ptr = RARRAY_CONST_PTR(ary);
    t = RARRAY_LEN(ary);
    if (0 < t) {
        ary_memcpy(ary2, 0, t, ptr);
        while (t <= len/2) {
            ary_memcpy(ary2, t, t, RARRAY_CONST_PTR(ary2));
            t *= 2;
        }
        if (t < len) {
            ary_memcpy(ary2, t, len-t, RARRAY_CONST_PTR(ary2));
        }
    }
  out:
    return ary2;
}

/*
 *  call-seq:
 *    array.assoc(obj) -> found_array or nil
 *
 *  Returns the first element in +self+ that is an +Array+
 *  whose first element <tt>==</tt> +obj+:
 *
 *    a = [{foo: 0}, [2, 4], [4, 5, 6], [4, 5]]
 *    a.assoc(4) # => [4, 5, 6]
 *
 *  Returns +nil+ if no such element is found.
 *
 *  Related: #rassoc.
 */

VALUE
rb_ary_assoc(VALUE ary, VALUE key)
{
    long i;
    VALUE v;

    for (i = 0; i < RARRAY_LEN(ary); ++i) {
        v = rb_check_array_type(RARRAY_AREF(ary, i));
        if (!NIL_P(v) && RARRAY_LEN(v) > 0 &&
            rb_equal(RARRAY_AREF(v, 0), key))
            return v;
    }
    return Qnil;
}

/*
 *  call-seq:
 *    array.rassoc(obj) -> found_array or nil
 *
 *  Returns the first element in +self+ that is an +Array+
 *  whose second element <tt>==</tt> +obj+:
 *
 *    a = [{foo: 0}, [2, 4], [4, 5, 6], [4, 5]]
 *    a.rassoc(4) # => [2, 4]
 *
 *  Returns +nil+ if no such element is found.
 *
 *  Related: #assoc.
 */

VALUE
rb_ary_rassoc(VALUE ary, VALUE value)
{
    long i;
    VALUE v;

    for (i = 0; i < RARRAY_LEN(ary); ++i) {
        v = rb_check_array_type(RARRAY_AREF(ary, i));
        if (RB_TYPE_P(v, T_ARRAY) &&
            RARRAY_LEN(v) > 1 &&
            rb_equal(RARRAY_AREF(v, 1), value))
            return v;
    }
    return Qnil;
}

static VALUE
recursive_equal(VALUE ary1, VALUE ary2, int recur)
{
    long i, len1;
    const VALUE *p1, *p2;

    if (recur) return Qtrue; /* Subtle! */

    /* rb_equal() can evacuate ptrs */
    p1 = RARRAY_CONST_PTR(ary1);
    p2 = RARRAY_CONST_PTR(ary2);
    len1 = RARRAY_LEN(ary1);

    for (i = 0; i < len1; i++) {
        if (*p1 != *p2) {
            if (rb_equal(*p1, *p2)) {
                len1 = RARRAY_LEN(ary1);
                if (len1 != RARRAY_LEN(ary2))
                    return Qfalse;
                if (len1 < i)
                    return Qtrue;
                p1 = RARRAY_CONST_PTR(ary1) + i;
                p2 = RARRAY_CONST_PTR(ary2) + i;
            }
            else {
                return Qfalse;
            }
        }
        p1++;
        p2++;
    }
    return Qtrue;
}

/*
 *  call-seq:
 *    array == other_array -> true or false
 *
 *  Returns +true+ if both <tt>array.size == other_array.size</tt>
 *  and for each index +i+ in +array+, <tt>array[i] == other_array[i]</tt>:
 *
 *    a0 = [:foo, 'bar', 2]
 *    a1 = [:foo, 'bar', 2.0]
 *    a1 == a0 # => true
 *    [] == [] # => true
 *
 *  Otherwise, returns +false+.
 *
 *  This method is different from method Array#eql?,
 *  which compares elements using <tt>Object#eql?</tt>.
 */

static VALUE
rb_ary_equal(VALUE ary1, VALUE ary2)
{
    if (ary1 == ary2) return Qtrue;
    if (!RB_TYPE_P(ary2, T_ARRAY)) {
        if (!rb_respond_to(ary2, idTo_ary)) {
            return Qfalse;
        }
        return rb_equal(ary2, ary1);
    }
    if (RARRAY_LEN(ary1) != RARRAY_LEN(ary2)) return Qfalse;
    if (RARRAY_CONST_PTR(ary1) == RARRAY_CONST_PTR(ary2)) return Qtrue;
    return rb_exec_recursive_paired(recursive_equal, ary1, ary2, ary2);
}

static VALUE
recursive_eql(VALUE ary1, VALUE ary2, int recur)
{
    long i;

    if (recur) return Qtrue; /* Subtle! */
    for (i=0; i<RARRAY_LEN(ary1); i++) {
        if (!rb_eql(rb_ary_elt(ary1, i), rb_ary_elt(ary2, i)))
            return Qfalse;
    }
    return Qtrue;
}

/*
 *  call-seq:
 *    array.eql?(other_array) -> true or false
 *
 *  Returns +true+ if +self+ and +other_array+ are the same size,
 *  and if, for each index +i+ in +self+, <tt>self[i].eql?(other_array[i])</tt>:
 *
 *    a0 = [:foo, 'bar', 2]
 *    a1 = [:foo, 'bar', 2]
 *    a1.eql?(a0) # => true
 *
 *  Otherwise, returns +false+.
 *
 *  This method is different from method Array#==,
 *  which compares using method <tt>Object#==</tt>.
 */

static VALUE
rb_ary_eql(VALUE ary1, VALUE ary2)
{
    if (ary1 == ary2) return Qtrue;
    if (!RB_TYPE_P(ary2, T_ARRAY)) return Qfalse;
    if (RARRAY_LEN(ary1) != RARRAY_LEN(ary2)) return Qfalse;
    if (RARRAY_CONST_PTR(ary1) == RARRAY_CONST_PTR(ary2)) return Qtrue;
    return rb_exec_recursive_paired(recursive_eql, ary1, ary2, ary2);
}

VALUE
rb_ary_hash_values(long len, const VALUE *elements)
{
    long i;
    st_index_t h;
    VALUE n;

    h = rb_hash_start(len);
    h = rb_hash_uint(h, (st_index_t)rb_ary_hash_values);
    for (i=0; i<len; i++) {
        n = rb_hash(elements[i]);
        h = rb_hash_uint(h, NUM2LONG(n));
    }
    h = rb_hash_end(h);
    return ST2FIX(h);
}

/*
 *  call-seq:
 *    array.hash -> integer
 *
 *  Returns the integer hash value for +self+.
 *
 *  Two arrays with the same content will have the same hash code (and will compare using #eql?):
 *
 *    [0, 1, 2].hash == [0, 1, 2].hash # => true
 *    [0, 1, 2].hash == [0, 1, 3].hash # => false
 *
 */

static VALUE
rb_ary_hash(VALUE ary)
{
    return rb_ary_hash_values(RARRAY_LEN(ary), RARRAY_CONST_PTR(ary));
}

/*
 *  call-seq:
 *    array.include?(obj) -> true or false
 *
 *  Returns +true+ if for some index +i+ in +self+, <tt>obj == self[i]</tt>;
 *  otherwise +false+:
 *
 *    [0, 1, 2].include?(2) # => true
 *    [0, 1, 2].include?(3) # => false
 */

VALUE
rb_ary_includes(VALUE ary, VALUE item)
{
    long i;
    VALUE e;

    for (i=0; i<RARRAY_LEN(ary); i++) {
        e = RARRAY_AREF(ary, i);
        if (rb_equal(e, item)) {
            return Qtrue;
        }
    }
    return Qfalse;
}

static VALUE
rb_ary_includes_by_eql(VALUE ary, VALUE item)
{
    long i;
    VALUE e;

    for (i=0; i<RARRAY_LEN(ary); i++) {
        e = RARRAY_AREF(ary, i);
        if (rb_eql(item, e)) {
            return Qtrue;
        }
    }
    return Qfalse;
}

static VALUE
recursive_cmp(VALUE ary1, VALUE ary2, int recur)
{
    long i, len;

    if (recur) return Qundef;	/* Subtle! */
    len = RARRAY_LEN(ary1);
    if (len > RARRAY_LEN(ary2)) {
        len = RARRAY_LEN(ary2);
    }
    for (i=0; i<len; i++) {
        VALUE e1 = rb_ary_elt(ary1, i), e2 = rb_ary_elt(ary2, i);
        VALUE v = rb_funcallv(e1, id_cmp, 1, &e2);
        if (v != INT2FIX(0)) {
            return v;
        }
    }
    return Qundef;
}

/*
 *  call-seq:
 *    array <=> other_array -> -1, 0, or 1
 *
 *  Returns -1, 0, or 1 as +self+ is less than, equal to, or greater than +other_array+.
 *  For each index +i+ in +self+, evaluates <tt>result = self[i] <=> other_array[i]</tt>.
 *
 *  Returns -1 if any result is -1:
 *
 *    [0, 1, 2] <=> [0, 1, 3] # => -1
 *
 *  Returns 1 if any result is 1:
 *
 *    [0, 1, 2] <=> [0, 1, 1] # => 1
 *
 *  When all results are zero:
 *
 *  - Returns -1 if +array+ is smaller than +other_array+:
 *
 *      [0, 1, 2] <=> [0, 1, 2, 3] # => -1
 *
 *  - Returns 1 if +array+ is larger than +other_array+:
 *
 *      [0, 1, 2] <=> [0, 1] # => 1
 *
 *  - Returns 0 if +array+ and +other_array+ are the same size:
 *
 *      [0, 1, 2] <=> [0, 1, 2] # => 0
 *
 */

VALUE
rb_ary_cmp(VALUE ary1, VALUE ary2)
{
    long len;
    VALUE v;

    ary2 = rb_check_array_type(ary2);
    if (NIL_P(ary2)) return Qnil;
    if (ary1 == ary2) return INT2FIX(0);
    v = rb_exec_recursive_paired(recursive_cmp, ary1, ary2, ary2);
    if (!UNDEF_P(v)) return v;
    len = RARRAY_LEN(ary1) - RARRAY_LEN(ary2);
    if (len == 0) return INT2FIX(0);
    if (len > 0) return INT2FIX(1);
    return INT2FIX(-1);
}

static VALUE
ary_add_hash(VALUE hash, VALUE ary)
{
    long i;

    for (i=0; i<RARRAY_LEN(ary); i++) {
        VALUE elt = RARRAY_AREF(ary, i);
        rb_hash_add_new_element(hash, elt, elt);
    }
    return hash;
}

static inline VALUE
ary_tmp_hash_new(VALUE ary)
{
    long size = RARRAY_LEN(ary);
    VALUE hash = rb_hash_new_with_size(size);

    RBASIC_CLEAR_CLASS(hash);
    return hash;
}

static VALUE
ary_make_hash(VALUE ary)
{
    VALUE hash = ary_tmp_hash_new(ary);
    return ary_add_hash(hash, ary);
}

static VALUE
ary_add_hash_by(VALUE hash, VALUE ary)
{
    long i;

    for (i = 0; i < RARRAY_LEN(ary); ++i) {
        VALUE v = rb_ary_elt(ary, i), k = rb_yield(v);
        rb_hash_add_new_element(hash, k, v);
    }
    return hash;
}

static VALUE
ary_make_hash_by(VALUE ary)
{
    VALUE hash = ary_tmp_hash_new(ary);
    return ary_add_hash_by(hash, ary);
}

/*
 *  call-seq:
 *    array - other_array -> new_array
 *
 *  Returns a new +Array+ containing only those elements from +array+
 *  that are not found in +Array+ +other_array+;
 *  items are compared using <tt>eql?</tt>;
 *  the order from +array+ is preserved:
 *
 *    [0, 1, 1, 2, 1, 1, 3, 1, 1] - [1] # => [0, 2, 3]
 *    [0, 1, 2, 3] - [3, 0] # => [1, 2]
 *    [0, 1, 2] - [4] # => [0, 1, 2]
 *
 *  Related: Array#difference.
 */

VALUE
rb_ary_diff(VALUE ary1, VALUE ary2)
{
    VALUE ary3;
    VALUE hash;
    long i;

    ary2 = to_ary(ary2);
    if (RARRAY_LEN(ary2) == 0) { return ary_make_shared_copy(ary1); }
    ary3 = rb_ary_new();

    if (RARRAY_LEN(ary1) <= SMALL_ARRAY_LEN || RARRAY_LEN(ary2) <= SMALL_ARRAY_LEN) {
        for (i=0; i<RARRAY_LEN(ary1); i++) {
            VALUE elt = rb_ary_elt(ary1, i);
            if (rb_ary_includes_by_eql(ary2, elt)) continue;
            rb_ary_push(ary3, elt);
        }
        return ary3;
    }

    hash = ary_make_hash(ary2);
    for (i=0; i<RARRAY_LEN(ary1); i++) {
        if (rb_hash_stlike_lookup(hash, RARRAY_AREF(ary1, i), NULL)) continue;
        rb_ary_push(ary3, rb_ary_elt(ary1, i));
    }

    return ary3;
}

/*
 *  call-seq:
 *    array.difference(*other_arrays) -> new_array
 *
 *  Returns a new +Array+ containing only those elements from +self+
 *  that are not found in any of the Arrays +other_arrays+;
 *  items are compared using <tt>eql?</tt>;  order from +self+ is preserved:
 *
 *    [0, 1, 1, 2, 1, 1, 3, 1, 1].difference([1]) # => [0, 2, 3]
 *    [0, 1, 2, 3].difference([3, 0], [1, 3]) # => [2]
 *    [0, 1, 2].difference([4]) # => [0, 1, 2]
 *
 *  Returns a copy of +self+ if no arguments given.
 *
 *  Related: Array#-.
 */

static VALUE
rb_ary_difference_multi(int argc, VALUE *argv, VALUE ary)
{
    VALUE ary_diff;
    long i, length;
    volatile VALUE t0;
    bool *is_hash = ALLOCV_N(bool, t0, argc);
    ary_diff = rb_ary_new();
    length = RARRAY_LEN(ary);

    for (i = 0; i < argc; i++) {
        argv[i] = to_ary(argv[i]);
        is_hash[i] = (length > SMALL_ARRAY_LEN && RARRAY_LEN(argv[i]) > SMALL_ARRAY_LEN);
        if (is_hash[i]) argv[i] = ary_make_hash(argv[i]);
    }

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        int j;
        VALUE elt = rb_ary_elt(ary, i);
        for (j = 0; j < argc; j++) {
            if (is_hash[j]) {
                if (rb_hash_stlike_lookup(argv[j], RARRAY_AREF(ary, i), NULL))
                    break;
            }
            else {
                if (rb_ary_includes_by_eql(argv[j], elt)) break;
            }
        }
        if (j == argc) rb_ary_push(ary_diff, elt);
    }

    ALLOCV_END(t0);

    return ary_diff;
}


/*
 *  call-seq:
 *    self & other_array -> new_array
 *
 *  Returns a new +Array+ object containing the _intersection_ of +self+ and +other_array+;
 *  that is, containing those elements found in both +self+ and +other_array+:
 *
 *    [0, 1, 2, 3] & [1, 2] # => [1, 2]
 *
 *  Omits duplicates:
 *
 *    [0, 1, 1, 0] & [0, 1] # => [0, 1]
 *
 *  Preserves order from +self+:
 *
 *    [0, 1, 2] & [3, 2, 1, 0] # => [0, 1, 2]
 *
 *  Identifies common elements using method <tt>#eql?</tt>
 *  (as defined in each element of +self+).
 *
 *  Related:
 *
 *  - Array#intersection: intersection of +self+ and multiple other arrays.
 *  - Array#|: union of +self+ and one other array.
 *  - Array#union: union of +self+ and multiple other arrays.
 *
 */


static VALUE
rb_ary_and(VALUE ary1, VALUE ary2)
{
    VALUE hash, ary3, v;
    st_data_t vv;
    long i;

    ary2 = to_ary(ary2);
    ary3 = rb_ary_new();
    if (RARRAY_LEN(ary1) == 0 || RARRAY_LEN(ary2) == 0) return ary3;

    if (RARRAY_LEN(ary1) <= SMALL_ARRAY_LEN && RARRAY_LEN(ary2) <= SMALL_ARRAY_LEN) {
        for (i=0; i<RARRAY_LEN(ary1); i++) {
            v = RARRAY_AREF(ary1, i);
            if (!rb_ary_includes_by_eql(ary2, v)) continue;
            if (rb_ary_includes_by_eql(ary3, v)) continue;
            rb_ary_push(ary3, v);
        }
        return ary3;
    }

    hash = ary_make_hash(ary2);

    for (i=0; i<RARRAY_LEN(ary1); i++) {
        v = RARRAY_AREF(ary1, i);
        vv = (st_data_t)v;
        if (rb_hash_stlike_delete(hash, &vv, 0)) {
            rb_ary_push(ary3, v);
        }
    }

    return ary3;
}

/*
 *  call-seq:
 *    array.intersection(*other_arrays) -> new_array
 *
 *  Returns a new +Array+ containing each element found both in +self+
 *  and in all of the given Arrays +other_arrays+;
 *  duplicates are omitted; items are compared using <tt>eql?</tt>
 *  (items must also implement +hash+ correctly):
 *
 *    [0, 1, 2, 3].intersection([0, 1, 2], [0, 1, 3]) # => [0, 1]
 *    [0, 0, 1, 1, 2, 3].intersection([0, 1, 2], [0, 1, 3]) # => [0, 1]
 *
 *  Preserves order from +self+:
 *
 *    [0, 1, 2].intersection([2, 1, 0]) # => [0, 1, 2]
 *
 *  Returns a copy of +self+ if no arguments given.
 *
 *  Related: Array#&.
 */

static VALUE
rb_ary_intersection_multi(int argc, VALUE *argv, VALUE ary)
{
    VALUE result = rb_ary_dup(ary);
    int i;

    for (i = 0; i < argc; i++) {
        result = rb_ary_and(result, argv[i]);
    }

    return result;
}

static int
ary_hash_orset(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    if (existing) return ST_STOP;
    *key = *value = (VALUE)arg;
    return ST_CONTINUE;
}

static void
rb_ary_union(VALUE ary_union, VALUE ary)
{
    long i;
    for (i = 0; i < RARRAY_LEN(ary); i++) {
        VALUE elt = rb_ary_elt(ary, i);
        if (rb_ary_includes_by_eql(ary_union, elt)) continue;
        rb_ary_push(ary_union, elt);
    }
}

static void
rb_ary_union_hash(VALUE hash, VALUE ary2)
{
    long i;
    for (i = 0; i < RARRAY_LEN(ary2); i++) {
        VALUE elt = RARRAY_AREF(ary2, i);
        if (!rb_hash_stlike_update(hash, (st_data_t)elt, ary_hash_orset, (st_data_t)elt)) {
            RB_OBJ_WRITTEN(hash, Qundef, elt);
        }
    }
}

/*
 *  call-seq:
 *    array | other_array -> new_array
 *
 *  Returns the union of +array+ and +Array+ +other_array+;
 *  duplicates are removed; order is preserved;
 *  items are compared using <tt>eql?</tt>:
 *
 *    [0, 1] | [2, 3] # => [0, 1, 2, 3]
 *    [0, 1, 1] | [2, 2, 3] # => [0, 1, 2, 3]
 *    [0, 1, 2] | [3, 2, 1, 0] # => [0, 1, 2, 3]
 *
 *  Related: Array#union.
 */

static VALUE
rb_ary_or(VALUE ary1, VALUE ary2)
{
    VALUE hash;

    ary2 = to_ary(ary2);
    if (RARRAY_LEN(ary1) + RARRAY_LEN(ary2) <= SMALL_ARRAY_LEN) {
        VALUE ary3 = rb_ary_new();
        rb_ary_union(ary3, ary1);
        rb_ary_union(ary3, ary2);
        return ary3;
    }

    hash = ary_make_hash(ary1);
    rb_ary_union_hash(hash, ary2);

    return rb_hash_values(hash);
}

/*
 *  call-seq:
 *    array.union(*other_arrays) -> new_array
 *
 *  Returns a new +Array+ that is the union of +self+ and all given Arrays +other_arrays+;
 *  duplicates are removed;  order is preserved;  items are compared using <tt>eql?</tt>:
 *
 *    [0, 1, 2, 3].union([4, 5], [6, 7]) # => [0, 1, 2, 3, 4, 5, 6, 7]
 *    [0, 1, 1].union([2, 1], [3, 1]) # => [0, 1, 2, 3]
 *    [0, 1, 2, 3].union([3, 2], [1, 0]) # => [0, 1, 2, 3]
 *
 *  Returns a copy of +self+ if no arguments given.
 *
 *  Related: Array#|.
 */

static VALUE
rb_ary_union_multi(int argc, VALUE *argv, VALUE ary)
{
    int i;
    long sum;
    VALUE hash;

    sum = RARRAY_LEN(ary);
    for (i = 0; i < argc; i++) {
        argv[i] = to_ary(argv[i]);
        sum += RARRAY_LEN(argv[i]);
    }

    if (sum <= SMALL_ARRAY_LEN) {
        VALUE ary_union = rb_ary_new();

        rb_ary_union(ary_union, ary);
        for (i = 0; i < argc; i++) rb_ary_union(ary_union, argv[i]);

        return ary_union;
    }

    hash = ary_make_hash(ary);
    for (i = 0; i < argc; i++) rb_ary_union_hash(hash, argv[i]);

    return rb_hash_values(hash);
}

/*
 *  call-seq:
 *     ary.intersect?(other_ary)   -> true or false
 *
 *  Returns +true+ if the array and +other_ary+ have at least one element in
 *  common, otherwise returns +false+:
 *
 *     a = [ 1, 2, 3 ]
 *     b = [ 3, 4, 5 ]
 *     c = [ 5, 6, 7 ]
 *     a.intersect?(b)   #=> true
 *     a.intersect?(c)   #=> false
 *
 *  +Array+ elements are compared using <tt>eql?</tt>
 *  (items must also implement +hash+ correctly).
 */

static VALUE
rb_ary_intersect_p(VALUE ary1, VALUE ary2)
{
    VALUE hash, v, result, shorter, longer;
    st_data_t vv;
    long i;

    ary2 = to_ary(ary2);
    if (RARRAY_LEN(ary1) == 0 || RARRAY_LEN(ary2) == 0) return Qfalse;

    if (RARRAY_LEN(ary1) <= SMALL_ARRAY_LEN && RARRAY_LEN(ary2) <= SMALL_ARRAY_LEN) {
        for (i=0; i<RARRAY_LEN(ary1); i++) {
            v = RARRAY_AREF(ary1, i);
            if (rb_ary_includes_by_eql(ary2, v)) return Qtrue;
        }
        return Qfalse;
    }

    shorter = ary1;
    longer = ary2;
    if (RARRAY_LEN(ary1) > RARRAY_LEN(ary2)) {
        longer = ary1;
        shorter = ary2;
    }

    hash = ary_make_hash(shorter);
    result = Qfalse;

    for (i=0; i<RARRAY_LEN(longer); i++) {
        v = RARRAY_AREF(longer, i);
        vv = (st_data_t)v;
        if (rb_hash_stlike_lookup(hash, vv, 0)) {
            result = Qtrue;
            break;
        }
    }

    return result;
}

static VALUE
ary_max_generic(VALUE ary, long i, VALUE vmax)
{
    RUBY_ASSERT(i > 0 && i < RARRAY_LEN(ary));

    VALUE v;
    for (; i < RARRAY_LEN(ary); ++i) {
        v = RARRAY_AREF(ary, i);

        if (rb_cmpint(rb_funcallv(vmax, id_cmp, 1, &v), vmax, v) < 0) {
            vmax = v;
        }
    }

    return vmax;
}

static VALUE
ary_max_opt_fixnum(VALUE ary, long i, VALUE vmax)
{
    const long n = RARRAY_LEN(ary);
    RUBY_ASSERT(i > 0 && i < n);
    RUBY_ASSERT(FIXNUM_P(vmax));

    VALUE v;
    for (; i < n; ++i) {
        v = RARRAY_AREF(ary, i);

        if (FIXNUM_P(v)) {
            if ((long)vmax < (long)v) {
                vmax = v;
            }
        }
        else {
            return ary_max_generic(ary, i, vmax);
        }
    }

    return vmax;
}

static VALUE
ary_max_opt_float(VALUE ary, long i, VALUE vmax)
{
    const long n = RARRAY_LEN(ary);
    RUBY_ASSERT(i > 0 && i < n);
    RUBY_ASSERT(RB_FLOAT_TYPE_P(vmax));

    VALUE v;
    for (; i < n; ++i) {
        v = RARRAY_AREF(ary, i);

        if (RB_FLOAT_TYPE_P(v)) {
            if (rb_float_cmp(vmax, v) < 0) {
                vmax = v;
            }
        }
        else {
            return ary_max_generic(ary, i, vmax);
        }
    }

    return vmax;
}

static VALUE
ary_max_opt_string(VALUE ary, long i, VALUE vmax)
{
    const long n = RARRAY_LEN(ary);
    RUBY_ASSERT(i > 0 && i < n);
    RUBY_ASSERT(STRING_P(vmax));

    VALUE v;
    for (; i < n; ++i) {
        v = RARRAY_AREF(ary, i);

        if (STRING_P(v)) {
            if (rb_str_cmp(vmax, v) < 0) {
                vmax = v;
            }
        }
        else {
            return ary_max_generic(ary, i, vmax);
        }
    }

    return vmax;
}

/*
 *  call-seq:
 *    array.max -> element
 *    array.max {|a, b| ... } -> element
 *    array.max(n) -> new_array
 *    array.max(n) {|a, b| ... } -> new_array
 *
 *  Returns one of the following:
 *
 *  - The maximum-valued element from +self+.
 *  - A new +Array+ of maximum-valued elements selected from +self+.
 *
 *  When no block is given, each element in +self+ must respond to method <tt><=></tt>
 *  with an Integer.
 *
 *  With no argument and no block, returns the element in +self+
 *  having the maximum value per method <tt><=></tt>:
 *
 *    [0, 1, 2].max # => 2
 *
 *  With an argument Integer +n+ and no block, returns a new +Array+ with at most +n+ elements,
 *  in descending order per method <tt><=></tt>:
 *
 *    [0, 1, 2, 3].max(3) # => [3, 2, 1]
 *    [0, 1, 2, 3].max(6) # => [3, 2, 1, 0]
 *
 *  When a block is given, the block must return an Integer.
 *
 *  With a block and no argument, calls the block <tt>self.size-1</tt> times to compare elements;
 *  returns the element having the maximum value per the block:
 *
 *    ['0', '00', '000'].max {|a, b| a.size <=> b.size } # => "000"
 *
 *  With an argument +n+ and a block, returns a new +Array+ with at most +n+ elements,
 *  in descending order per the block:
 *
 *    ['0', '00', '000'].max(2) {|a, b| a.size <=> b.size } # => ["000", "00"]
 *
 */
static VALUE
rb_ary_max(int argc, VALUE *argv, VALUE ary)
{
    VALUE result = Qundef, v;
    VALUE num;
    long i;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(num = argv[0]))
       return rb_nmin_run(ary, num, 0, 1, 1);

    const long n = RARRAY_LEN(ary);
    if (rb_block_given_p()) {
        for (i = 0; i < RARRAY_LEN(ary); i++) {
           v = RARRAY_AREF(ary, i);
           if (UNDEF_P(result) || rb_cmpint(rb_yield_values(2, v, result), v, result) > 0) {
               result = v;
           }
        }
    }
    else if (n > 0) {
        result = RARRAY_AREF(ary, 0);
        if (n > 1) {
            if (FIXNUM_P(result) && CMP_OPTIMIZABLE(INTEGER)) {
                return ary_max_opt_fixnum(ary, 1, result);
            }
            else if (STRING_P(result) && CMP_OPTIMIZABLE(STRING)) {
                return ary_max_opt_string(ary, 1, result);
            }
            else if (RB_FLOAT_TYPE_P(result) && CMP_OPTIMIZABLE(FLOAT)) {
                return ary_max_opt_float(ary, 1, result);
            }
            else {
                return ary_max_generic(ary, 1, result);
            }
        }
    }
    if (UNDEF_P(result)) return Qnil;
    return result;
}

static VALUE
ary_min_generic(VALUE ary, long i, VALUE vmin)
{
    RUBY_ASSERT(i > 0 && i < RARRAY_LEN(ary));

    VALUE v;
    for (; i < RARRAY_LEN(ary); ++i) {
        v = RARRAY_AREF(ary, i);

        if (rb_cmpint(rb_funcallv(vmin, id_cmp, 1, &v), vmin, v) > 0) {
            vmin = v;
        }
    }

    return vmin;
}

static VALUE
ary_min_opt_fixnum(VALUE ary, long i, VALUE vmin)
{
    const long n = RARRAY_LEN(ary);
    RUBY_ASSERT(i > 0 && i < n);
    RUBY_ASSERT(FIXNUM_P(vmin));

    VALUE a;
    for (; i < n; ++i) {
        a = RARRAY_AREF(ary, i);

        if (FIXNUM_P(a)) {
            if ((long)vmin > (long)a) {
                vmin = a;
            }
        }
        else {
            return ary_min_generic(ary, i, vmin);
        }
    }

    return vmin;
}

static VALUE
ary_min_opt_float(VALUE ary, long i, VALUE vmin)
{
    const long n = RARRAY_LEN(ary);
    RUBY_ASSERT(i > 0 && i < n);
    RUBY_ASSERT(RB_FLOAT_TYPE_P(vmin));

    VALUE a;
    for (; i < n; ++i) {
        a = RARRAY_AREF(ary, i);

        if (RB_FLOAT_TYPE_P(a)) {
            if (rb_float_cmp(vmin, a) > 0) {
                vmin = a;
            }
        }
        else {
            return ary_min_generic(ary, i, vmin);
        }
    }

    return vmin;
}

static VALUE
ary_min_opt_string(VALUE ary, long i, VALUE vmin)
{
    const long n = RARRAY_LEN(ary);
    RUBY_ASSERT(i > 0 && i < n);
    RUBY_ASSERT(STRING_P(vmin));

    VALUE a;
    for (; i < n; ++i) {
        a = RARRAY_AREF(ary, i);

        if (STRING_P(a)) {
            if (rb_str_cmp(vmin, a) > 0) {
                vmin = a;
            }
        }
        else {
            return ary_min_generic(ary, i, vmin);
        }
    }

    return vmin;
}

/*
 *  call-seq:
 *    array.min -> element
 *    array.min { |a, b| ... } -> element
 *    array.min(n) -> new_array
 *    array.min(n) { |a, b| ... } -> new_array
 *
 *  Returns one of the following:
 *
 *  - The minimum-valued element from +self+.
 *  - A new +Array+ of minimum-valued elements selected from +self+.
 *
 *  When no block is given, each element in +self+ must respond to method <tt><=></tt>
 *  with an Integer.
 *
 *  With no argument and no block, returns the element in +self+
 *  having the minimum value per method <tt><=></tt>:
 *
 *    [0, 1, 2].min # => 0
 *
 *  With Integer argument +n+ and no block, returns a new +Array+ with at most +n+ elements,
 *  in ascending order per method <tt><=></tt>:
 *
 *    [0, 1, 2, 3].min(3) # => [0, 1, 2]
 *    [0, 1, 2, 3].min(6) # => [0, 1, 2, 3]
 *
 *  When a block is given, the block must return an Integer.
 *
 *  With a block and no argument, calls the block <tt>self.size-1</tt> times to compare elements;
 *  returns the element having the minimum value per the block:
 *
 *    ['0', '00', '000'].min { |a, b| a.size <=> b.size } # => "0"
 *
 *  With an argument +n+ and a block, returns a new +Array+ with at most +n+ elements,
 *  in ascending order per the block:
 *
 *    ['0', '00', '000'].min(2) {|a, b| a.size <=> b.size } # => ["0", "00"]
 *
 */
static VALUE
rb_ary_min(int argc, VALUE *argv, VALUE ary)
{
    VALUE result = Qundef, v;
    VALUE num;
    long i;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(num = argv[0]))
       return rb_nmin_run(ary, num, 0, 0, 1);

    const long n = RARRAY_LEN(ary);
    if (rb_block_given_p()) {
        for (i = 0; i < RARRAY_LEN(ary); i++) {
           v = RARRAY_AREF(ary, i);
           if (UNDEF_P(result) || rb_cmpint(rb_yield_values(2, v, result), v, result) < 0) {
               result = v;
           }
        }
    }
    else if (n > 0) {
        result = RARRAY_AREF(ary, 0);
        if (n > 1) {
            if (FIXNUM_P(result) && CMP_OPTIMIZABLE(INTEGER)) {
                return ary_min_opt_fixnum(ary, 1, result);
            }
            else if (STRING_P(result) && CMP_OPTIMIZABLE(STRING)) {
                return ary_min_opt_string(ary, 1, result);
            }
            else if (RB_FLOAT_TYPE_P(result) && CMP_OPTIMIZABLE(FLOAT)) {
                return ary_min_opt_float(ary, 1, result);
            }
            else {
                return ary_min_generic(ary, 1, result);
            }
        }
    }
    if (UNDEF_P(result)) return Qnil;
    return result;
}

/*
 *  call-seq:
 *    array.minmax -> [min_val, max_val]
 *    array.minmax {|a, b| ... } -> [min_val, max_val]
 *
 *  Returns a new 2-element +Array+ containing the minimum and maximum values
 *  from +self+, either per method <tt><=></tt> or per a given block:.
 *
 *  When no block is given, each element in +self+ must respond to method <tt><=></tt>
 *  with an Integer;
 *  returns a new 2-element +Array+ containing the minimum and maximum values
 *  from +self+, per method <tt><=></tt>:
 *
 *    [0, 1, 2].minmax # => [0, 2]
 *
 *  When a block is given, the block must return an Integer;
 *  the block is called <tt>self.size-1</tt> times to compare elements;
 *  returns a new 2-element +Array+ containing the minimum and maximum values
 *  from +self+, per the block:
 *
 *    ['0', '00', '000'].minmax {|a, b| a.size <=> b.size } # => ["0", "000"]
 *
 */
static VALUE
rb_ary_minmax(VALUE ary)
{
    if (rb_block_given_p()) {
        return rb_call_super(0, NULL);
    }
    return rb_assoc_new(rb_ary_min(0, 0, ary), rb_ary_max(0, 0, ary));
}

static int
push_value(st_data_t key, st_data_t val, st_data_t ary)
{
    rb_ary_push((VALUE)ary, (VALUE)val);
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *    array.uniq! -> self or nil
 *    array.uniq! {|element| ... } -> self or nil
 *
 *  Removes duplicate elements from +self+, the first occurrence always being retained;
 *  returns +self+ if any elements removed, +nil+ otherwise.
 *
 *  With no block given, identifies and removes elements using method <tt>eql?</tt>
 *  to compare.
 *
 *  Returns +self+ if any elements removed:
 *
 *    a = [0, 0, 1, 1, 2, 2]
 *    a.uniq! # => [0, 1, 2]
 *
 *  Returns +nil+ if no elements removed.
 *
 *  With a block given, calls the block for each element;
 *  identifies (using method <tt>eql?</tt>) and removes
 *  elements for which the block returns duplicate values.
 *
 *  Returns +self+ if any elements removed:
 *
 *    a = ['a', 'aa', 'aaa', 'b', 'bb', 'bbb']
 *    a.uniq! {|element| element.size } # => ['a', 'aa', 'aaa']
 *
 *  Returns +nil+ if no elements removed.
 */
static VALUE
rb_ary_uniq_bang(VALUE ary)
{
    VALUE hash;
    long hash_size;

    rb_ary_modify_check(ary);
    if (RARRAY_LEN(ary) <= 1)
        return Qnil;
    if (rb_block_given_p())
        hash = ary_make_hash_by(ary);
    else
        hash = ary_make_hash(ary);

    hash_size = RHASH_SIZE(hash);
    if (RARRAY_LEN(ary) == hash_size) {
        return Qnil;
    }
    rb_ary_modify_check(ary);
    ARY_SET_LEN(ary, 0);
    if (ARY_SHARED_P(ary) && !ARY_EMBED_P(ary)) {
        rb_ary_unshare(ary);
        FL_SET_EMBED(ary);
    }
    ary_resize_capa(ary, hash_size);
    rb_hash_foreach(hash, push_value, ary);

    return ary;
}

/*
 *  call-seq:
 *    array.uniq -> new_array
 *    array.uniq {|element| ... } -> new_array
 *
 *  Returns a new +Array+ containing those elements from +self+ that are not duplicates,
 *  the first occurrence always being retained.
 *
 *  With no block given, identifies and omits duplicates using method <tt>eql?</tt>
 *  to compare:
 *
 *    a = [0, 0, 1, 1, 2, 2]
 *    a.uniq # => [0, 1, 2]
 *
 *  With a block given, calls the block for each element;
 *  identifies (using method <tt>eql?</tt>) and omits duplicate values,
 *  that is, those elements for which the block returns the same value:
 *
 *    a = ['a', 'aa', 'aaa', 'b', 'bb', 'bbb']
 *    a.uniq {|element| element.size } # => ["a", "aa", "aaa"]
 *
 */

static VALUE
rb_ary_uniq(VALUE ary)
{
    VALUE hash, uniq;

    if (RARRAY_LEN(ary) <= 1) {
        hash = 0;
        uniq = rb_ary_dup(ary);
    }
    else if (rb_block_given_p()) {
        hash = ary_make_hash_by(ary);
        uniq = rb_hash_values(hash);
    }
    else {
        hash = ary_make_hash(ary);
        uniq = rb_hash_values(hash);
    }

    return uniq;
}

/*
 *  call-seq:
 *    array.compact! -> self or nil
 *
 *  Removes all +nil+ elements from +self+.
 *
 *  Returns +self+ if any elements removed, otherwise +nil+.
 */

static VALUE
rb_ary_compact_bang(VALUE ary)
{
    VALUE *p, *t, *end;
    long n;

    rb_ary_modify(ary);
    p = t = (VALUE *)RARRAY_CONST_PTR(ary); /* WB: no new reference */
    end = p + RARRAY_LEN(ary);

    while (t < end) {
        if (NIL_P(*t)) t++;
        else *p++ = *t++;
    }
    n = p - RARRAY_CONST_PTR(ary);
    if (RARRAY_LEN(ary) == n) {
        return Qnil;
    }
    ary_resize_smaller(ary, n);

    return ary;
}

/*
 *  call-seq:
 *    array.compact -> new_array
 *
 *  Returns a new +Array+ containing all non-+nil+ elements from +self+:
 *
 *    a = [nil, 0, nil, 1, nil, 2, nil]
 *    a.compact # => [0, 1, 2]
 */

static VALUE
rb_ary_compact(VALUE ary)
{
    ary = rb_ary_dup(ary);
    rb_ary_compact_bang(ary);
    return ary;
}

/*
 *  call-seq:
 *    array.count -> an_integer
 *    array.count(obj) -> an_integer
 *    array.count {|element| ... } -> an_integer
 *
 *  Returns a count of specified elements.
 *
 *  With no argument and no block, returns the count of all elements:
 *
 *    [0, 1, 2].count # => 3
 *    [].count # => 0
 *
 *  With argument +obj+, returns the count of elements <tt>==</tt> to +obj+:
 *
 *    [0, 1, 2, 0.0].count(0) # => 2
 *    [0, 1, 2].count(3) # => 0
 *
 *  With no argument and a block given, calls the block with each element;
 *  returns the count of elements for which the block returns a truthy value:
 *
 *    [0, 1, 2, 3].count {|element| element > 1} # => 2
 *
 *  With argument +obj+ and a block given, issues a warning, ignores the block,
 *  and returns the count of elements <tt>==</tt> to +obj+.
 */

static VALUE
rb_ary_count(int argc, VALUE *argv, VALUE ary)
{
    long i, n = 0;

    if (rb_check_arity(argc, 0, 1) == 0) {
        VALUE v;

        if (!rb_block_given_p())
            return LONG2NUM(RARRAY_LEN(ary));

        for (i = 0; i < RARRAY_LEN(ary); i++) {
            v = RARRAY_AREF(ary, i);
            if (RTEST(rb_yield(v))) n++;
        }
    }
    else {
        VALUE obj = argv[0];

        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            if (rb_equal(RARRAY_AREF(ary, i), obj)) n++;
        }
    }

    return LONG2NUM(n);
}

static VALUE
flatten(VALUE ary, int level)
{
    long i;
    VALUE stack, result, tmp = 0, elt;
    VALUE memo = Qfalse;

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        elt = RARRAY_AREF(ary, i);
        tmp = rb_check_array_type(elt);
        if (!NIL_P(tmp)) {
            break;
        }
    }
    if (i == RARRAY_LEN(ary)) {
        return ary;
    }

    result = ary_new(0, RARRAY_LEN(ary));
    ary_memcpy(result, 0, i, RARRAY_CONST_PTR(ary));
    ARY_SET_LEN(result, i);

    stack = ary_new(0, ARY_DEFAULT_SIZE);
    rb_ary_push(stack, ary);
    rb_ary_push(stack, LONG2NUM(i + 1));

    if (level < 0) {
        memo = rb_obj_hide(rb_ident_hash_new());
        rb_hash_aset(memo, ary, Qtrue);
        rb_hash_aset(memo, tmp, Qtrue);
    }

    ary = tmp;
    i = 0;

    while (1) {
        while (i < RARRAY_LEN(ary)) {
            elt = RARRAY_AREF(ary, i++);
            if (level >= 0 && RARRAY_LEN(stack) / 2 >= level) {
                rb_ary_push(result, elt);
                continue;
            }
            tmp = rb_check_array_type(elt);
            if (RBASIC(result)->klass) {
                if (RTEST(memo)) {
                    rb_hash_clear(memo);
                }
                rb_raise(rb_eRuntimeError, "flatten reentered");
            }
            if (NIL_P(tmp)) {
                rb_ary_push(result, elt);
            }
            else {
                if (memo) {
                    if (rb_hash_aref(memo, tmp) == Qtrue) {
                        rb_hash_clear(memo);
                        rb_raise(rb_eArgError, "tried to flatten recursive array");
                    }
                    rb_hash_aset(memo, tmp, Qtrue);
                }
                rb_ary_push(stack, ary);
                rb_ary_push(stack, LONG2NUM(i));
                ary = tmp;
                i = 0;
            }
        }
        if (RARRAY_LEN(stack) == 0) {
            break;
        }
        if (memo) {
            rb_hash_delete(memo, ary);
        }
        tmp = rb_ary_pop(stack);
        i = NUM2LONG(tmp);
        ary = rb_ary_pop(stack);
    }

    if (memo) {
        rb_hash_clear(memo);
    }

    RBASIC_SET_CLASS(result, rb_cArray);
    return result;
}

/*
 *  call-seq:
 *    array.flatten! -> self or nil
 *    array.flatten!(level) -> self or nil
 *
 *  Replaces each nested +Array+ in +self+ with the elements from that +Array+;
 *  returns +self+ if any changes, +nil+ otherwise.
 *
 *  With non-negative Integer argument +level+, flattens recursively through +level+ levels:
 *
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten!(1) # => [0, 1, [2, 3], 4, 5]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten!(2) # => [0, 1, 2, 3, 4, 5]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten!(3) # => [0, 1, 2, 3, 4, 5]
 *    [0, 1, 2].flatten!(1) # => nil
 *
 *  With no argument, a +nil+ argument, or with negative argument +level+, flattens all levels:
 *
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten! # => [0, 1, 2, 3, 4, 5]
 *    [0, 1, 2].flatten! # => nil
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten!(-1) # => [0, 1, 2, 3, 4, 5]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten!(-2) # => [0, 1, 2, 3, 4, 5]
 *    [0, 1, 2].flatten!(-1) # => nil
 *
 */

static VALUE
rb_ary_flatten_bang(int argc, VALUE *argv, VALUE ary)
{
    int mod = 0, level = -1;
    VALUE result, lv;

    lv = (rb_check_arity(argc, 0, 1) ? argv[0] : Qnil);
    rb_ary_modify_check(ary);
    if (!NIL_P(lv)) level = NUM2INT(lv);
    if (level == 0) return Qnil;

    result = flatten(ary, level);
    if (result == ary) {
        return Qnil;
    }
    if (!(mod = ARY_EMBED_P(result))) rb_ary_freeze(result);
    rb_ary_replace(ary, result);
    if (mod) ARY_SET_EMBED_LEN(result, 0);

    return ary;
}

/*
 *  call-seq:
 *    array.flatten -> new_array
 *    array.flatten(level) -> new_array
 *
 *  Returns a new +Array+ that is a recursive flattening of +self+:
 *  - Each non-Array element is unchanged.
 *  - Each +Array+ is replaced by its individual elements.
 *
 *  With non-negative Integer argument +level+, flattens recursively through +level+ levels:
 *
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten(0) # => [0, [1, [2, 3], 4], 5]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten(1) # => [0, 1, [2, 3], 4, 5]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten(2) # => [0, 1, 2, 3, 4, 5]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten(3) # => [0, 1, 2, 3, 4, 5]
 *
 *  With no argument, a +nil+ argument, or with negative argument +level+, flattens all levels:
 *
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten # => [0, 1, 2, 3, 4, 5]
 *    [0, 1, 2].flatten # => [0, 1, 2]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten(-1) # => [0, 1, 2, 3, 4, 5]
 *    a = [ 0, [ 1, [2, 3], 4 ], 5 ]
 *    a.flatten(-2) # => [0, 1, 2, 3, 4, 5]
 *    [0, 1, 2].flatten(-1) # => [0, 1, 2]
 *
 */

static VALUE
rb_ary_flatten(int argc, VALUE *argv, VALUE ary)
{
    int level = -1;
    VALUE result;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(argv[0])) {
        level = NUM2INT(argv[0]);
        if (level == 0) return ary_make_shared_copy(ary);
    }

    result = flatten(ary, level);
    if (result == ary) {
        result = ary_make_shared_copy(ary);
    }

    return result;
}

#define RAND_UPTO(max) (long)rb_random_ulong_limited((randgen), (max)-1)

static VALUE
rb_ary_shuffle_bang(rb_execution_context_t *ec, VALUE ary, VALUE randgen)
{
    long i, len;

    rb_ary_modify(ary);
    i = len = RARRAY_LEN(ary);
    RARRAY_PTR_USE(ary, ptr, {
        while (i) {
            long j = RAND_UPTO(i);
            VALUE tmp;
            if (len != RARRAY_LEN(ary) || ptr != RARRAY_CONST_PTR(ary)) {
                rb_raise(rb_eRuntimeError, "modified during shuffle");
            }
            tmp = ptr[--i];
            ptr[i] = ptr[j];
            ptr[j] = tmp;
        }
    }); /* WB: no new reference */
    return ary;
}

static VALUE
rb_ary_shuffle(rb_execution_context_t *ec, VALUE ary, VALUE randgen)
{
    ary = rb_ary_dup(ary);
    rb_ary_shuffle_bang(ec, ary, randgen);
    return ary;
}

static const rb_data_type_t ary_sample_memo_type = {
    .wrap_struct_name = "ary_sample_memo",
    .function = {
        .dfree = (RUBY_DATA_FUNC)st_free_table,
    },
    .flags = RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE
ary_sample(rb_execution_context_t *ec, VALUE ary, VALUE randgen, VALUE nv, VALUE to_array)
{
    VALUE result;
    long n, len, i, j, k, idx[10];
    long rnds[numberof(idx)];
    long memo_threshold;

    len = RARRAY_LEN(ary);
    if (!to_array) {
        if (len < 2)
            i = 0;
        else
            i = RAND_UPTO(len);

        return rb_ary_elt(ary, i);
    }
    n = NUM2LONG(nv);
    if (n < 0) rb_raise(rb_eArgError, "negative sample number");
    if (n > len) n = len;
    if (n <= numberof(idx)) {
        for (i = 0; i < n; ++i) {
            rnds[i] = RAND_UPTO(len - i);
        }
    }
    k = len;
    len = RARRAY_LEN(ary);
    if (len < k && n <= numberof(idx)) {
        for (i = 0; i < n; ++i) {
            if (rnds[i] >= len) return rb_ary_new_capa(0);
        }
    }
    if (n > len) n = len;
    switch (n) {
      case 0:
        return rb_ary_new_capa(0);
      case 1:
        i = rnds[0];
        return rb_ary_new_from_args(1, RARRAY_AREF(ary, i));
      case 2:
        i = rnds[0];
        j = rnds[1];
        if (j >= i) j++;
        return rb_ary_new_from_args(2, RARRAY_AREF(ary, i), RARRAY_AREF(ary, j));
      case 3:
        i = rnds[0];
        j = rnds[1];
        k = rnds[2];
        {
            long l = j, g = i;
            if (j >= i) l = i, g = ++j;
            if (k >= l && (++k >= g)) ++k;
        }
        return rb_ary_new_from_args(3, RARRAY_AREF(ary, i), RARRAY_AREF(ary, j), RARRAY_AREF(ary, k));
    }
    memo_threshold =
        len < 2560 ? len / 128 :
        len < 5120 ? len / 64 :
        len < 10240 ? len / 32 :
        len / 16;
    if (n <= numberof(idx)) {
        long sorted[numberof(idx)];
        sorted[0] = idx[0] = rnds[0];
        for (i=1; i<n; i++) {
            k = rnds[i];
            for (j = 0; j < i; ++j) {
                if (k < sorted[j]) break;
                ++k;
            }
            memmove(&sorted[j+1], &sorted[j], sizeof(sorted[0])*(i-j));
            sorted[j] = idx[i] = k;
        }
        result = rb_ary_new_capa(n);
        RARRAY_PTR_USE(result, ptr_result, {
            for (i=0; i<n; i++) {
                ptr_result[i] = RARRAY_AREF(ary, idx[i]);
            }
        });
    }
    else if (n <= memo_threshold / 2) {
        long max_idx = 0;
        VALUE vmemo = TypedData_Wrap_Struct(0, &ary_sample_memo_type, 0);
        st_table *memo = st_init_numtable_with_size(n);
        RTYPEDDATA_DATA(vmemo) = memo;
        result = rb_ary_new_capa(n);
        RARRAY_PTR_USE(result, ptr_result, {
            for (i=0; i<n; i++) {
                long r = RAND_UPTO(len-i) + i;
                ptr_result[i] = r;
                if (r > max_idx) max_idx = r;
            }
            len = RARRAY_LEN(ary);
            if (len <= max_idx) n = 0;
            else if (n > len) n = len;
            RARRAY_PTR_USE(ary, ptr_ary, {
                for (i=0; i<n; i++) {
                    long j2 = j = ptr_result[i];
                    long i2 = i;
                    st_data_t value;
                    if (st_lookup(memo, (st_data_t)i, &value)) i2 = (long)value;
                    if (st_lookup(memo, (st_data_t)j, &value)) j2 = (long)value;
                    st_insert(memo, (st_data_t)j, (st_data_t)i2);
                    ptr_result[i] = ptr_ary[j2];
                }
            });
        });
        RTYPEDDATA_DATA(vmemo) = 0;
        st_free_table(memo);
        RB_GC_GUARD(vmemo);
    }
    else {
        result = rb_ary_dup(ary);
        RBASIC_CLEAR_CLASS(result);
        RB_GC_GUARD(ary);
        RARRAY_PTR_USE(result, ptr_result, {
            for (i=0; i<n; i++) {
                j = RAND_UPTO(len-i) + i;
                nv = ptr_result[j];
                ptr_result[j] = ptr_result[i];
                ptr_result[i] = nv;
            }
        });
        RBASIC_SET_CLASS_RAW(result, rb_cArray);
    }
    ARY_SET_LEN(result, n);

    return result;
}

static VALUE
ary_sample0(rb_execution_context_t *ec, VALUE ary)
{
    return ary_sample(ec, ary, rb_cRandom, Qfalse, Qfalse);
}

static VALUE
rb_ary_cycle_size(VALUE self, VALUE args, VALUE eobj)
{
    long mul;
    VALUE n = Qnil;
    if (args && (RARRAY_LEN(args) > 0)) {
        n = RARRAY_AREF(args, 0);
    }
    if (RARRAY_LEN(self) == 0) return INT2FIX(0);
    if (NIL_P(n)) return DBL2NUM(HUGE_VAL);
    mul = NUM2LONG(n);
    if (mul <= 0) return INT2FIX(0);
    n = LONG2FIX(mul);
    return rb_fix_mul_fix(rb_ary_length(self), n);
}

/*
 *  call-seq:
 *    array.cycle {|element| ... } -> nil
 *    array.cycle(count) {|element| ... } -> nil
 *    array.cycle -> new_enumerator
 *    array.cycle(count) -> new_enumerator
 *
 *  When called with positive Integer argument +count+ and a block,
 *  calls the block with each element, then does so again,
 *  until it has done so +count+ times; returns +nil+:
 *
 *    output = []
 *    [0, 1].cycle(2) {|element| output.push(element) } # => nil
 *    output # => [0, 1, 0, 1]
 *
 *  If +count+ is zero or negative, does not call the block:
 *
 *    [0, 1].cycle(0) {|element| fail 'Cannot happen' } # => nil
 *    [0, 1].cycle(-1) {|element| fail 'Cannot happen' } # => nil
 *
 *  When a block is given, and argument is omitted or +nil+, cycles forever:
 *
 *    # Prints 0 and 1 forever.
 *    [0, 1].cycle {|element| puts element }
 *    [0, 1].cycle(nil) {|element| puts element }
 *
 *  When no block is given, returns a new Enumerator:
 *
 *    [0, 1].cycle(2) # => #<Enumerator: [0, 1]:cycle(2)>
 *    [0, 1].cycle # => # => #<Enumerator: [0, 1]:cycle>
 *    [0, 1].cycle.first(5) # => [0, 1, 0, 1, 0]
 *
 */
static VALUE
rb_ary_cycle(int argc, VALUE *argv, VALUE ary)
{
    long n, i;

    rb_check_arity(argc, 0, 1);

    RETURN_SIZED_ENUMERATOR(ary, argc, argv, rb_ary_cycle_size);
    if (argc == 0 || NIL_P(argv[0])) {
        n = -1;
    }
    else {
        n = NUM2LONG(argv[0]);
        if (n <= 0) return Qnil;
    }

    while (RARRAY_LEN(ary) > 0 && (n < 0 || 0 < n--)) {
        for (i=0; i<RARRAY_LEN(ary); i++) {
            rb_yield(RARRAY_AREF(ary, i));
        }
    }
    return Qnil;
}

/*
 * Build a ruby array of the corresponding values and yield it to the
 * associated block.
 * Return the class of +values+ for reentry check.
 */
static int
yield_indexed_values(const VALUE values, const long r, const long *const p)
{
    const VALUE result = rb_ary_new2(r);
    long i;

    for (i = 0; i < r; i++) ARY_SET(result, i, RARRAY_AREF(values, p[i]));
    ARY_SET_LEN(result, r);
    rb_yield(result);
    return !RBASIC(values)->klass;
}

/*
 * Compute permutations of +r+ elements of the set <code>[0..n-1]</code>.
 *
 * When we have a complete permutation of array indices, copy the values
 * at those indices into a new array and yield that array.
 *
 * n: the size of the set
 * r: the number of elements in each permutation
 * p: the array (of size r) that we're filling in
 * used: an array of booleans: whether a given index is already used
 * values: the Ruby array that holds the actual values to permute
 */
static void
permute0(const long n, const long r, long *const p, char *const used, const VALUE values)
{
    long i = 0, index = 0;

    for (;;) {
        const char *const unused = memchr(&used[i], 0, n-i);
        if (!unused) {
            if (!index) break;
            i = p[--index];                /* pop index */
            used[i++] = 0;                 /* index unused */
        }
        else {
            i = unused - used;
            p[index] = i;
            used[i] = 1;                   /* mark index used */
            ++index;
            if (index < r-1) {             /* if not done yet */
                p[index] = i = 0;
                continue;
            }
            for (i = 0; i < n; ++i) {
                if (used[i]) continue;
                p[index] = i;
                if (!yield_indexed_values(values, r, p)) {
                    rb_raise(rb_eRuntimeError, "permute reentered");
                }
            }
            i = p[--index];                /* pop index */
            used[i] = 0;                   /* index unused */
            p[index] = ++i;
        }
    }
}

/*
 * Returns the product of from, from-1, ..., from - how_many + 1.
 * https://en.wikipedia.org/wiki/Pochhammer_symbol
 */
static VALUE
descending_factorial(long from, long how_many)
{
    VALUE cnt;
    if (how_many > 0) {
        cnt = LONG2FIX(from);
        while (--how_many > 0) {
            long v = --from;
            cnt = rb_int_mul(cnt, LONG2FIX(v));
        }
    }
    else {
        cnt = LONG2FIX(how_many == 0);
    }
    return cnt;
}

static VALUE
binomial_coefficient(long comb, long size)
{
    VALUE r;
    long i;
    if (comb > size-comb) {
        comb = size-comb;
    }
    if (comb < 0) {
        return LONG2FIX(0);
    }
    else if (comb == 0) {
        return LONG2FIX(1);
    }
    r = LONG2FIX(size);
    for (i = 1; i < comb; ++i) {
        r = rb_int_mul(r, LONG2FIX(size - i));
        r = rb_int_idiv(r, LONG2FIX(i + 1));
    }
    return r;
}

static VALUE
rb_ary_permutation_size(VALUE ary, VALUE args, VALUE eobj)
{
    long n = RARRAY_LEN(ary);
    long k = (args && (RARRAY_LEN(args) > 0)) ? NUM2LONG(RARRAY_AREF(args, 0)) : n;

    return descending_factorial(n, k);
}

/*
 *  call-seq:
 *    array.permutation {|element| ... } -> self
 *    array.permutation(n) {|element| ... } -> self
 *    array.permutation -> new_enumerator
 *    array.permutation(n) -> new_enumerator
 *
 *  When invoked with a block, yield all permutations of elements of +self+; returns +self+.
 *  The order of permutations is indeterminate.
 *
 *  When a block and an in-range positive Integer argument +n+ (<tt>0 < n <= self.size</tt>)
 *  are given, calls the block with all +n+-tuple permutations of +self+.
 *
 *  Example:
 *
 *    a = [0, 1, 2]
 *    a.permutation(2) {|permutation| p permutation }
 *
 *  Output:
 *
 *    [0, 1]
 *    [0, 2]
 *    [1, 0]
 *    [1, 2]
 *    [2, 0]
 *    [2, 1]
 *
 *  Another example:
 *
 *    a = [0, 1, 2]
 *    a.permutation(3) {|permutation| p permutation }
 *
 *  Output:
 *
 *    [0, 1, 2]
 *    [0, 2, 1]
 *    [1, 0, 2]
 *    [1, 2, 0]
 *    [2, 0, 1]
 *    [2, 1, 0]
 *
 *  When +n+ is zero, calls the block once with a new empty +Array+:
 *
 *    a = [0, 1, 2]
 *    a.permutation(0) {|permutation| p permutation }
 *
 *  Output:
 *
 *    []
 *
 *  When +n+ is out of range (negative or larger than <tt>self.size</tt>),
 *  does not call the block:
 *
 *    a = [0, 1, 2]
 *    a.permutation(-1) {|permutation| fail 'Cannot happen' }
 *    a.permutation(4) {|permutation| fail 'Cannot happen' }
 *
 *  When a block given but no argument,
 *  behaves the same as <tt>a.permutation(a.size)</tt>:
 *
 *    a = [0, 1, 2]
 *    a.permutation {|permutation| p permutation }
 *
 *  Output:
 *
 *    [0, 1, 2]
 *    [0, 2, 1]
 *    [1, 0, 2]
 *    [1, 2, 0]
 *    [2, 0, 1]
 *    [2, 1, 0]
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [0, 1, 2]
 *    a.permutation # => #<Enumerator: [0, 1, 2]:permutation>
 *    a.permutation(2) # => #<Enumerator: [0, 1, 2]:permutation(2)>
 *
 */

static VALUE
rb_ary_permutation(int argc, VALUE *argv, VALUE ary)
{
    long r, n, i;

    n = RARRAY_LEN(ary);                  /* Array length */
    RETURN_SIZED_ENUMERATOR(ary, argc, argv, rb_ary_permutation_size);   /* Return enumerator if no block */
    r = n;
    if (rb_check_arity(argc, 0, 1) && !NIL_P(argv[0]))
        r = NUM2LONG(argv[0]);            /* Permutation size from argument */

    if (r < 0 || n < r) {
        /* no permutations: yield nothing */
    }
    else if (r == 0) { /* exactly one permutation: the zero-length array */
        rb_yield(rb_ary_new2(0));
    }
    else if (r == 1) { /* this is a special, easy case */
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            rb_yield(rb_ary_new3(1, RARRAY_AREF(ary, i)));
        }
    }
    else {             /* this is the general case */
        volatile VALUE t0;
        long *p = ALLOCV_N(long, t0, r+roomof(n, sizeof(long)));
        char *used = (char*)(p + r);
        VALUE ary0 = ary_make_shared_copy(ary); /* private defensive copy of ary */
        RBASIC_CLEAR_CLASS(ary0);

        MEMZERO(used, char, n); /* initialize array */

        permute0(n, r, p, used, ary0); /* compute and yield permutations */
        ALLOCV_END(t0);
        RBASIC_SET_CLASS_RAW(ary0, rb_cArray);
    }
    return ary;
}

static void
combinate0(const long len, const long n, long *const stack, const VALUE values)
{
    long lev = 0;

    MEMZERO(stack+1, long, n);
    stack[0] = -1;
    for (;;) {
        for (lev++; lev < n; lev++) {
            stack[lev+1] = stack[lev]+1;
        }
        if (!yield_indexed_values(values, n, stack+1)) {
            rb_raise(rb_eRuntimeError, "combination reentered");
        }
        do {
            if (lev == 0) return;
            stack[lev--]++;
        } while (stack[lev+1]+n == len+lev+1);
    }
}

static VALUE
rb_ary_combination_size(VALUE ary, VALUE args, VALUE eobj)
{
    long n = RARRAY_LEN(ary);
    long k = NUM2LONG(RARRAY_AREF(args, 0));

    return binomial_coefficient(k, n);
}

/*
 *  call-seq:
 *    array.combination(n) {|element| ... } -> self
 *    array.combination(n) -> new_enumerator
 *
 *  Calls the block, if given, with combinations of elements of +self+;
 *  returns +self+. The order of combinations is indeterminate.
 *
 *  When a block and an in-range positive Integer argument +n+ (<tt>0 < n <= self.size</tt>)
 *  are given, calls the block with all +n+-tuple combinations of +self+.
 *
 *  Example:
 *
 *    a = [0, 1, 2]
 *    a.combination(2) {|combination| p combination }
 *
 *  Output:
 *
 *    [0, 1]
 *    [0, 2]
 *    [1, 2]
 *
 *  Another example:
 *
 *    a = [0, 1, 2]
 *    a.combination(3) {|combination| p combination }
 *
 *  Output:
 *
 *    [0, 1, 2]
 *
 *  When +n+ is zero, calls the block once with a new empty +Array+:
 *
 *    a = [0, 1, 2]
 *    a1 = a.combination(0) {|combination| p combination }
 *
 *  Output:
 *
 *    []
 *
 *  When +n+ is out of range (negative or larger than <tt>self.size</tt>),
 *  does not call the block:
 *
 *    a = [0, 1, 2]
 *    a.combination(-1) {|combination| fail 'Cannot happen' }
 *    a.combination(4) {|combination| fail 'Cannot happen' }
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [0, 1, 2]
 *    a.combination(2) # => #<Enumerator: [0, 1, 2]:combination(2)>
 *
 */

static VALUE
rb_ary_combination(VALUE ary, VALUE num)
{
    long i, n, len;

    n = NUM2LONG(num);
    RETURN_SIZED_ENUMERATOR(ary, 1, &num, rb_ary_combination_size);
    len = RARRAY_LEN(ary);
    if (n < 0 || len < n) {
        /* yield nothing */
    }
    else if (n == 0) {
        rb_yield(rb_ary_new2(0));
    }
    else if (n == 1) {
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            rb_yield(rb_ary_new3(1, RARRAY_AREF(ary, i)));
        }
    }
    else {
        VALUE ary0 = ary_make_shared_copy(ary); /* private defensive copy of ary */
        volatile VALUE t0;
        long *stack = ALLOCV_N(long, t0, n+1);

        RBASIC_CLEAR_CLASS(ary0);
        combinate0(len, n, stack, ary0);
        ALLOCV_END(t0);
        RBASIC_SET_CLASS_RAW(ary0, rb_cArray);
    }
    return ary;
}

/*
 * Compute repeated permutations of +r+ elements of the set
 * <code>[0..n-1]</code>.
 *
 * When we have a complete repeated permutation of array indices, copy the
 * values at those indices into a new array and yield that array.
 *
 * n: the size of the set
 * r: the number of elements in each permutation
 * p: the array (of size r) that we're filling in
 * values: the Ruby array that holds the actual values to permute
 */
static void
rpermute0(const long n, const long r, long *const p, const VALUE values)
{
    long i = 0, index = 0;

    p[index] = i;
    for (;;) {
        if (++index < r-1) {
            p[index] = i = 0;
            continue;
        }
        for (i = 0; i < n; ++i) {
            p[index] = i;
            if (!yield_indexed_values(values, r, p)) {
                rb_raise(rb_eRuntimeError, "repeated permute reentered");
            }
        }
        do {
            if (index <= 0) return;
        } while ((i = ++p[--index]) >= n);
    }
}

static VALUE
rb_ary_repeated_permutation_size(VALUE ary, VALUE args, VALUE eobj)
{
    long n = RARRAY_LEN(ary);
    long k = NUM2LONG(RARRAY_AREF(args, 0));

    if (k < 0) {
        return LONG2FIX(0);
    }
    if (n <= 0) {
        return LONG2FIX(!k);
    }
    return rb_int_positive_pow(n, (unsigned long)k);
}

/*
 *  call-seq:
 *    array.repeated_permutation(n) {|permutation| ... } -> self
 *    array.repeated_permutation(n) -> new_enumerator
 *
 *  Calls the block with each repeated permutation of length +n+ of the elements of +self+;
 *  each permutation is an +Array+;
 *  returns +self+. The order of the permutations is indeterminate.
 *
 *  When a block and a positive Integer argument +n+ are given, calls the block with each
 *  +n+-tuple repeated permutation of the elements of +self+.
 *  The number of permutations is <tt>self.size**n</tt>.
 *
 *  +n+ = 1:
 *
 *    a = [0, 1, 2]
 *    a.repeated_permutation(1) {|permutation| p permutation }
 *
 *  Output:
 *
 *    [0]
 *    [1]
 *    [2]
 *
 *  +n+ = 2:
 *
 *    a.repeated_permutation(2) {|permutation| p permutation }
 *
 *  Output:
 *
 *    [0, 0]
 *    [0, 1]
 *    [0, 2]
 *    [1, 0]
 *    [1, 1]
 *    [1, 2]
 *    [2, 0]
 *    [2, 1]
 *    [2, 2]
 *
 *  If +n+ is zero, calls the block once with an empty +Array+.
 *
 *  If +n+ is negative, does not call the block:
 *
 *    a.repeated_permutation(-1) {|permutation| fail 'Cannot happen' }
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [0, 1, 2]
 *    a.repeated_permutation(2) # => #<Enumerator: [0, 1, 2]:permutation(2)>
 *
 *  Using Enumerators, it's convenient to show the permutations and counts
 *  for some values of +n+:
 *
 *    e = a.repeated_permutation(0)
 *    e.size # => 1
 *    e.to_a # => [[]]
 *    e = a.repeated_permutation(1)
 *    e.size # => 3
 *    e.to_a # => [[0], [1], [2]]
 *    e = a.repeated_permutation(2)
 *    e.size # => 9
 *    e.to_a # => [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2], [2, 0], [2, 1], [2, 2]]
 *
 */
static VALUE
rb_ary_repeated_permutation(VALUE ary, VALUE num)
{
    long r, n, i;

    n = RARRAY_LEN(ary);                  /* Array length */
    RETURN_SIZED_ENUMERATOR(ary, 1, &num, rb_ary_repeated_permutation_size);      /* Return Enumerator if no block */
    r = NUM2LONG(num);                    /* Permutation size from argument */

    if (r < 0) {
        /* no permutations: yield nothing */
    }
    else if (r == 0) { /* exactly one permutation: the zero-length array */
        rb_yield(rb_ary_new2(0));
    }
    else if (r == 1) { /* this is a special, easy case */
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            rb_yield(rb_ary_new3(1, RARRAY_AREF(ary, i)));
        }
    }
    else {             /* this is the general case */
        volatile VALUE t0;
        long *p = ALLOCV_N(long, t0, r);
        VALUE ary0 = ary_make_shared_copy(ary); /* private defensive copy of ary */
        RBASIC_CLEAR_CLASS(ary0);

        rpermute0(n, r, p, ary0); /* compute and yield repeated permutations */
        ALLOCV_END(t0);
        RBASIC_SET_CLASS_RAW(ary0, rb_cArray);
    }
    return ary;
}

static void
rcombinate0(const long n, const long r, long *const p, const long rest, const VALUE values)
{
    long i = 0, index = 0;

    p[index] = i;
    for (;;) {
        if (++index < r-1) {
            p[index] = i;
            continue;
        }
        for (; i < n; ++i) {
            p[index] = i;
            if (!yield_indexed_values(values, r, p)) {
                rb_raise(rb_eRuntimeError, "repeated combination reentered");
            }
        }
        do {
            if (index <= 0) return;
        } while ((i = ++p[--index]) >= n);
    }
}

static VALUE
rb_ary_repeated_combination_size(VALUE ary, VALUE args, VALUE eobj)
{
    long n = RARRAY_LEN(ary);
    long k = NUM2LONG(RARRAY_AREF(args, 0));
    if (k == 0) {
        return LONG2FIX(1);
    }
    return binomial_coefficient(k, n + k - 1);
}

/*
 *  call-seq:
 *    array.repeated_combination(n) {|combination| ... } -> self
 *    array.repeated_combination(n) -> new_enumerator
 *
 *  Calls the block with each repeated combination of length +n+ of the elements of +self+;
 *  each combination is an +Array+;
 *  returns +self+. The order of the combinations is indeterminate.
 *
 *  When a block and a positive Integer argument +n+ are given, calls the block with each
 *  +n+-tuple repeated combination of the elements of +self+.
 *  The number of combinations is <tt>(n+1)(n+2)/2</tt>.
 *
 *  +n+ = 1:
 *
 *    a = [0, 1, 2]
 *    a.repeated_combination(1) {|combination| p combination }
 *
 *  Output:
 *
 *    [0]
 *    [1]
 *    [2]
 *
 *  +n+ = 2:
 *
 *    a.repeated_combination(2) {|combination| p combination }
 *
 *  Output:
 *
 *    [0, 0]
 *    [0, 1]
 *    [0, 2]
 *    [1, 1]
 *    [1, 2]
 *    [2, 2]
 *
 *  If +n+ is zero, calls the block once with an empty +Array+.
 *
 *  If +n+ is negative, does not call the block:
 *
 *    a.repeated_combination(-1) {|combination| fail 'Cannot happen' }
 *
 *  Returns a new Enumerator if no block given:
 *
 *    a = [0, 1, 2]
 *    a.repeated_combination(2) # => #<Enumerator: [0, 1, 2]:combination(2)>
 *
 *  Using Enumerators, it's convenient to show the combinations and counts
 *  for some values of +n+:
 *
 *    e = a.repeated_combination(0)
 *    e.size # => 1
 *    e.to_a # => [[]]
 *    e = a.repeated_combination(1)
 *    e.size # => 3
 *    e.to_a # => [[0], [1], [2]]
 *    e = a.repeated_combination(2)
 *    e.size # => 6
 *    e.to_a # => [[0, 0], [0, 1], [0, 2], [1, 1], [1, 2], [2, 2]]
 *
 */

static VALUE
rb_ary_repeated_combination(VALUE ary, VALUE num)
{
    long n, i, len;

    n = NUM2LONG(num);                 /* Combination size from argument */
    RETURN_SIZED_ENUMERATOR(ary, 1, &num, rb_ary_repeated_combination_size);   /* Return enumerator if no block */
    len = RARRAY_LEN(ary);
    if (n < 0) {
        /* yield nothing */
    }
    else if (n == 0) {
        rb_yield(rb_ary_new2(0));
    }
    else if (n == 1) {
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            rb_yield(rb_ary_new3(1, RARRAY_AREF(ary, i)));
        }
    }
    else if (len == 0) {
        /* yield nothing */
    }
    else {
        volatile VALUE t0;
        long *p = ALLOCV_N(long, t0, n);
        VALUE ary0 = ary_make_shared_copy(ary); /* private defensive copy of ary */
        RBASIC_CLEAR_CLASS(ary0);

        rcombinate0(len, n, p, n, ary0); /* compute and yield repeated combinations */
        ALLOCV_END(t0);
        RBASIC_SET_CLASS_RAW(ary0, rb_cArray);
    }
    return ary;
}

/*
 *  call-seq:
 *    array.product(*other_arrays) -> new_array
 *    array.product(*other_arrays) {|combination| ... } -> self
 *
 *  Computes and returns or yields all combinations of elements from all the Arrays,
 *  including both +self+ and +other_arrays+:
 *
 *  - The number of combinations is the product of the sizes of all the arrays,
 *    including both +self+ and +other_arrays+.
 *  - The order of the returned combinations is indeterminate.
 *
 *  When no block is given, returns the combinations as an +Array+ of Arrays:
 *
 *    a = [0, 1, 2]
 *    a1 = [3, 4]
 *    a2 = [5, 6]
 *    p = a.product(a1)
 *    p.size # => 6 # a.size * a1.size
 *    p # => [[0, 3], [0, 4], [1, 3], [1, 4], [2, 3], [2, 4]]
 *    p = a.product(a1, a2)
 *    p.size # => 12 # a.size * a1.size * a2.size
 *    p # => [[0, 3, 5], [0, 3, 6], [0, 4, 5], [0, 4, 6], [1, 3, 5], [1, 3, 6], [1, 4, 5], [1, 4, 6], [2, 3, 5], [2, 3, 6], [2, 4, 5], [2, 4, 6]]
 *
 *  If any argument is an empty +Array+, returns an empty +Array+.
 *
 *  If no argument is given, returns an +Array+ of 1-element Arrays,
 *  each containing an element of +self+:
 *
 *    a.product # => [[0], [1], [2]]
 *
 *  When a block is given, yields each combination as an +Array+; returns +self+:
 *
 *    a.product(a1) {|combination| p combination }
 *
 *  Output:
 *
 *    [0, 3]
 *    [0, 4]
 *    [1, 3]
 *    [1, 4]
 *    [2, 3]
 *    [2, 4]
 *
 *  If any argument is an empty +Array+, does not call the block:
 *
 *    a.product(a1, a2, []) {|combination| fail 'Cannot happen' }
 *
 *  If no argument is given, yields each element of +self+ as a 1-element +Array+:
 *
 *    a.product {|combination| p combination }
 *
 *  Output:
 *
 *    [0]
 *    [1]
 *    [2]
 *
 */

static VALUE
rb_ary_product(int argc, VALUE *argv, VALUE ary)
{
    int n = argc+1;    /* How many arrays we're operating on */
    volatile VALUE t0 = rb_ary_hidden_new(n);
    volatile VALUE t1 = Qundef;
    VALUE *arrays = RARRAY_PTR(t0); /* The arrays we're computing the product of */
    int *counters = ALLOCV_N(int, t1, n); /* The current position in each one */
    VALUE result = Qnil;      /* The array we'll be returning, when no block given */
    long i,j;
    long resultlen = 1;

    RBASIC_CLEAR_CLASS(t0);

    /* initialize the arrays of arrays */
    ARY_SET_LEN(t0, n);
    arrays[0] = ary;
    for (i = 1; i < n; i++) arrays[i] = Qnil;
    for (i = 1; i < n; i++) arrays[i] = to_ary(argv[i-1]);

    /* initialize the counters for the arrays */
    for (i = 0; i < n; i++) counters[i] = 0;

    /* Otherwise, allocate and fill in an array of results */
    if (rb_block_given_p()) {
        /* Make defensive copies of arrays; exit if any is empty */
        for (i = 0; i < n; i++) {
            if (RARRAY_LEN(arrays[i]) == 0) goto done;
            arrays[i] = ary_make_shared_copy(arrays[i]);
        }
    }
    else {
        /* Compute the length of the result array; return [] if any is empty */
        for (i = 0; i < n; i++) {
            long k = RARRAY_LEN(arrays[i]);
            if (k == 0) {
                result = rb_ary_new2(0);
                goto done;
            }
            if (MUL_OVERFLOW_LONG_P(resultlen, k))
                rb_raise(rb_eRangeError, "too big to product");
            resultlen *= k;
        }
        result = rb_ary_new2(resultlen);
    }
    for (;;) {
        int m;
        /* fill in one subarray */
        VALUE subarray = rb_ary_new2(n);
        for (j = 0; j < n; j++) {
            rb_ary_push(subarray, rb_ary_entry(arrays[j], counters[j]));
        }

        /* put it on the result array */
        if (NIL_P(result)) {
            FL_SET(t0, RARRAY_SHARED_ROOT_FLAG);
            rb_yield(subarray);
            if (!FL_TEST(t0, RARRAY_SHARED_ROOT_FLAG)) {
                rb_raise(rb_eRuntimeError, "product reentered");
            }
            else {
                FL_UNSET(t0, RARRAY_SHARED_ROOT_FLAG);
            }
        }
        else {
            rb_ary_push(result, subarray);
        }

        /*
         * Increment the last counter.  If it overflows, reset to 0
         * and increment the one before it.
         */
        m = n-1;
        counters[m]++;
        while (counters[m] == RARRAY_LEN(arrays[m])) {
            counters[m] = 0;
            /* If the first counter overflows, we are done */
            if (--m < 0) goto done;
            counters[m]++;
        }
    }

done:
    ALLOCV_END(t1);

    return NIL_P(result) ? ary : result;
}

/*
 *  call-seq:
 *    array.take(n) -> new_array
 *
 *  Returns a new +Array+ containing the first +n+ element of +self+,
 *  where +n+ is a non-negative Integer;
 *  does not modify +self+.
 *
 *  Examples:
 *
 *    a = [0, 1, 2, 3, 4, 5]
 *    a.take(1) # => [0]
 *    a.take(2) # => [0, 1]
 *    a.take(50) # => [0, 1, 2, 3, 4, 5]
 *    a # => [0, 1, 2, 3, 4, 5]
 *
 */

static VALUE
rb_ary_take(VALUE obj, VALUE n)
{
    long len = NUM2LONG(n);
    if (len < 0) {
        rb_raise(rb_eArgError, "attempt to take negative size");
    }
    return rb_ary_subseq(obj, 0, len);
}

/*
 *  call-seq:
 *    array.take_while {|element| ... } -> new_array
 *    array.take_while -> new_enumerator
 *
 *  Returns a new +Array+ containing zero or more leading elements of +self+;
 *  does not modify +self+.
 *
 *  With a block given, calls the block with each successive element of +self+;
 *  stops if the block returns +false+ or +nil+;
 *  returns a new +Array+ containing those elements for which the block returned a truthy value:
 *
 *    a = [0, 1, 2, 3, 4, 5]
 *    a.take_while {|element| element < 3 } # => [0, 1, 2]
 *    a.take_while {|element| true } # => [0, 1, 2, 3, 4, 5]
 *    a # => [0, 1, 2, 3, 4, 5]
 *
 *  With no block given, returns a new Enumerator:
 *
 *    [0, 1].take_while # => #<Enumerator: [0, 1]:take_while>
 *
 */

static VALUE
rb_ary_take_while(VALUE ary)
{
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    for (i = 0; i < RARRAY_LEN(ary); i++) {
        if (!RTEST(rb_yield(RARRAY_AREF(ary, i)))) break;
    }
    return rb_ary_take(ary, LONG2FIX(i));
}

/*
 *  call-seq:
 *    array.drop(n) -> new_array
 *
 *  Returns a new +Array+ containing all but the first +n+ element of +self+,
 *  where +n+ is a non-negative Integer;
 *  does not modify +self+.
 *
 *  Examples:
 *
 *    a = [0, 1, 2, 3, 4, 5]
 *    a.drop(0) # => [0, 1, 2, 3, 4, 5]
 *    a.drop(1) # => [1, 2, 3, 4, 5]
 *    a.drop(2) # => [2, 3, 4, 5]
 *
 */

static VALUE
rb_ary_drop(VALUE ary, VALUE n)
{
    VALUE result;
    long pos = NUM2LONG(n);
    if (pos < 0) {
        rb_raise(rb_eArgError, "attempt to drop negative size");
    }

    result = rb_ary_subseq(ary, pos, RARRAY_LEN(ary));
    if (NIL_P(result)) result = rb_ary_new();
    return result;
}

/*
 *  call-seq:
 *    array.drop_while {|element| ... } -> new_array
 *    array.drop_while -> new_enumerator

 *  Returns a new +Array+ containing zero or more trailing elements of +self+;
 *  does not modify +self+.
 *
 *  With a block given, calls the block with each successive element of +self+;
 *  stops if the block returns +false+ or +nil+;
 *  returns a new +Array+ _omitting_ those elements for which the block returned a truthy value:
 *
 *    a = [0, 1, 2, 3, 4, 5]
 *    a.drop_while {|element| element < 3 } # => [3, 4, 5]
 *
 *  With no block given, returns a new Enumerator:
 *
 *    [0, 1].drop_while # => # => #<Enumerator: [0, 1]:drop_while>
 *
 */

static VALUE
rb_ary_drop_while(VALUE ary)
{
    long i;

    RETURN_ENUMERATOR(ary, 0, 0);
    for (i = 0; i < RARRAY_LEN(ary); i++) {
        if (!RTEST(rb_yield(RARRAY_AREF(ary, i)))) break;
    }
    return rb_ary_drop(ary, LONG2FIX(i));
}

/*
 *  call-seq:
 *    array.any? -> true or false
 *    array.any? {|element| ... } -> true or false
 *    array.any?(obj) -> true or false
 *
 *  Returns +true+ if any element of +self+ meets a given criterion.
 *
 *  If +self+ has no element, returns +false+ and argument or block
 *  are not used.
 *
 *  With no block given and no argument, returns +true+ if +self+ has any truthy element,
 *  +false+ otherwise:
 *
 *    [nil, 0, false].any? # => true
 *    [nil, false].any? # => false
 *    [].any? # => false
 *
 *  With a block given and no argument, calls the block with each element in +self+;
 *  returns +true+ if the block returns any truthy value, +false+ otherwise:
 *
 *    [0, 1, 2].any? {|element| element > 1 } # => true
 *    [0, 1, 2].any? {|element| element > 2 } # => false
 *
 *  If argument +obj+ is given, returns +true+ if +obj+.<tt>===</tt> any element,
 *  +false+ otherwise:
 *
 *    ['food', 'drink'].any?(/foo/) # => true
 *    ['food', 'drink'].any?(/bar/) # => false
 *    [].any?(/foo/) # => false
 *    [0, 1, 2].any?(1) # => true
 *    [0, 1, 2].any?(3) # => false
 *
 *  Related: Enumerable#any?
 */

static VALUE
rb_ary_any_p(int argc, VALUE *argv, VALUE ary)
{
    long i, len = RARRAY_LEN(ary);

    rb_check_arity(argc, 0, 1);
    if (!len) return Qfalse;
    if (argc) {
        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (RTEST(rb_funcall(argv[0], idEqq, 1, RARRAY_AREF(ary, i)))) return Qtrue;
        }
    }
    else if (!rb_block_given_p()) {
        for (i = 0; i < len; ++i) {
            if (RTEST(RARRAY_AREF(ary, i))) return Qtrue;
        }
    }
    else {
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (RTEST(rb_yield(RARRAY_AREF(ary, i)))) return Qtrue;
        }
    }
    return Qfalse;
}

/*
 *  call-seq:
 *    array.all? -> true or false
 *    array.all? {|element| ... } -> true or false
 *    array.all?(obj) -> true or false
 *
 *  Returns +true+ if all elements of +self+ meet a given criterion.
 *
 *  If +self+ has no element, returns +true+ and argument or block
 *  are not used.
 *
 *  With no block given and no argument, returns +true+ if +self+ contains only truthy elements,
 *  +false+ otherwise:
 *
 *    [0, 1, :foo].all? # => true
 *    [0, nil, 2].all? # => false
 *    [].all? # => true
 *
 *  With a block given and no argument, calls the block with each element in +self+;
 *  returns +true+ if the block returns only truthy values, +false+ otherwise:
 *
 *    [0, 1, 2].all? { |element| element < 3 } # => true
 *    [0, 1, 2].all? { |element| element < 2 } # => false
 *
 *  If argument +obj+ is given, returns +true+ if <tt>obj.===</tt> every element, +false+ otherwise:
 *
 *    ['food', 'fool', 'foot'].all?(/foo/) # => true
 *    ['food', 'drink'].all?(/bar/) # => false
 *    [].all?(/foo/) # => true
 *    [0, 0, 0].all?(0) # => true
 *    [0, 1, 2].all?(1) # => false
 *
 *  Related: Enumerable#all?
 */

static VALUE
rb_ary_all_p(int argc, VALUE *argv, VALUE ary)
{
    long i, len = RARRAY_LEN(ary);

    rb_check_arity(argc, 0, 1);
    if (!len) return Qtrue;
    if (argc) {
        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (!RTEST(rb_funcall(argv[0], idEqq, 1, RARRAY_AREF(ary, i)))) return Qfalse;
        }
    }
    else if (!rb_block_given_p()) {
        for (i = 0; i < len; ++i) {
            if (!RTEST(RARRAY_AREF(ary, i))) return Qfalse;
        }
    }
    else {
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (!RTEST(rb_yield(RARRAY_AREF(ary, i)))) return Qfalse;
        }
    }
    return Qtrue;
}

/*
 *  call-seq:
 *    array.none? -> true or false
 *    array.none? {|element| ... } -> true or false
 *    array.none?(obj) -> true or false
 *
 *  Returns +true+ if no element of +self+ meet a given criterion.
 *
 *  With no block given and no argument, returns +true+ if +self+ has no truthy elements,
 *  +false+ otherwise:
 *
 *    [nil, false].none? # => true
 *    [nil, 0, false].none? # => false
 *    [].none? # => true
 *
 *  With a block given and no argument, calls the block with each element in +self+;
 *  returns +true+ if the block returns no truthy value, +false+ otherwise:
 *
 *    [0, 1, 2].none? {|element| element > 3 } # => true
 *    [0, 1, 2].none? {|element| element > 1 } # => false
 *
 *  If argument +obj+ is given, returns +true+ if <tt>obj.===</tt> no element, +false+ otherwise:
 *
 *    ['food', 'drink'].none?(/bar/) # => true
 *    ['food', 'drink'].none?(/foo/) # => false
 *    [].none?(/foo/) # => true
 *    [0, 1, 2].none?(3) # => true
 *    [0, 1, 2].none?(1) # => false
 *
 *  Related: Enumerable#none?
 */

static VALUE
rb_ary_none_p(int argc, VALUE *argv, VALUE ary)
{
    long i, len = RARRAY_LEN(ary);

    rb_check_arity(argc, 0, 1);
    if (!len) return Qtrue;
    if (argc) {
        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (RTEST(rb_funcall(argv[0], idEqq, 1, RARRAY_AREF(ary, i)))) return Qfalse;
        }
    }
    else if (!rb_block_given_p()) {
        for (i = 0; i < len; ++i) {
            if (RTEST(RARRAY_AREF(ary, i))) return Qfalse;
        }
    }
    else {
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (RTEST(rb_yield(RARRAY_AREF(ary, i)))) return Qfalse;
        }
    }
    return Qtrue;
}

/*
 *  call-seq:
 *    array.one? -> true or false
 *    array.one? {|element| ... } -> true or false
 *    array.one?(obj) -> true or false
 *
 *  Returns +true+ if exactly one element of +self+ meets a given criterion.
 *
 *  With no block given and no argument, returns +true+ if +self+ has exactly one truthy element,
 *  +false+ otherwise:
 *
 *    [nil, 0].one? # => true
 *    [0, 0].one? # => false
 *    [nil, nil].one? # => false
 *    [].one? # => false
 *
 *  With a block given and no argument, calls the block with each element in +self+;
 *  returns +true+ if the block a truthy value for exactly one element, +false+ otherwise:
 *
 *    [0, 1, 2].one? {|element| element > 0 } # => false
 *    [0, 1, 2].one? {|element| element > 1 } # => true
 *    [0, 1, 2].one? {|element| element > 2 } # => false
 *
 *  If argument +obj+ is given, returns +true+ if <tt>obj.===</tt> exactly one element,
 *  +false+ otherwise:
 *
 *    [0, 1, 2].one?(0) # => true
 *    [0, 0, 1].one?(0) # => false
 *    [1, 1, 2].one?(0) # => false
 *    ['food', 'drink'].one?(/bar/) # => false
 *    ['food', 'drink'].one?(/foo/) # => true
 *    [].one?(/foo/) # => false
 *
 *  Related: Enumerable#one?
 */

static VALUE
rb_ary_one_p(int argc, VALUE *argv, VALUE ary)
{
    long i, len = RARRAY_LEN(ary);
    VALUE result = Qfalse;

    rb_check_arity(argc, 0, 1);
    if (!len) return Qfalse;
    if (argc) {
        if (rb_block_given_p()) {
            rb_warn("given block not used");
        }
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (RTEST(rb_funcall(argv[0], idEqq, 1, RARRAY_AREF(ary, i)))) {
                if (result) return Qfalse;
                result = Qtrue;
            }
        }
    }
    else if (!rb_block_given_p()) {
        for (i = 0; i < len; ++i) {
            if (RTEST(RARRAY_AREF(ary, i))) {
                if (result) return Qfalse;
                result = Qtrue;
            }
        }
    }
    else {
        for (i = 0; i < RARRAY_LEN(ary); ++i) {
            if (RTEST(rb_yield(RARRAY_AREF(ary, i)))) {
                if (result) return Qfalse;
                result = Qtrue;
            }
        }
    }
    return result;
}

/*
 *  call-seq:
 *    array.dig(index, *identifiers) -> object
 *
 *  Finds and returns the object in nested objects
 *  that is specified by +index+ and +identifiers+.
 *  The nested objects may be instances of various classes.
 *  See {Dig Methods}[rdoc-ref:dig_methods.rdoc].
 *
 *  Examples:
 *
 *    a = [:foo, [:bar, :baz, [:bat, :bam]]]
 *    a.dig(1) # => [:bar, :baz, [:bat, :bam]]
 *    a.dig(1, 2) # => [:bat, :bam]
 *    a.dig(1, 2, 0) # => :bat
 *    a.dig(1, 2, 3) # => nil
 *
 */

static VALUE
rb_ary_dig(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    self = rb_ary_at(self, *argv);
    if (!--argc) return self;
    ++argv;
    return rb_obj_dig(argc, argv, self, Qnil);
}

static inline VALUE
finish_exact_sum(long n, VALUE r, VALUE v, int z)
{
    if (n != 0)
        v = rb_fix_plus(LONG2FIX(n), v);
    if (!UNDEF_P(r)) {
        v = rb_rational_plus(r, v);
    }
    else if (!n && z) {
        v = rb_fix_plus(LONG2FIX(0), v);
    }
    return v;
}

/*
 * call-seq:
 *   array.sum(init = 0) -> object
 *   array.sum(init = 0) {|element| ... } -> object
 *
 *  When no block is given, returns the object equivalent to:
 *
 *    sum = init
 *    array.each {|element| sum += element }
 *    sum
 *
 *  For example, <tt>[e1, e2, e3].sum</tt> returns <tt>init + e1 + e2 + e3</tt>.
 *
 *  Examples:
 *
 *    a = [0, 1, 2, 3]
 *    a.sum # => 6
 *    a.sum(100) # => 106
 *
 *  The elements need not be numeric, but must be <tt>+</tt>-compatible
 *  with each other and with +init+:
 *
 *    a = ['abc', 'def', 'ghi']
 *    a.sum('jkl') # => "jklabcdefghi"
 *
 *  When a block is given, it is called with each element
 *  and the block's return value (instead of the element itself) is used as the addend:
 *
 *    a = ['zero', 1, :two]
 *    s = a.sum('Coerced and concatenated: ') {|element| element.to_s }
 *    s # => "Coerced and concatenated: zero1two"
 *
 *  Notes:
 *
 *  - Array#join and Array#flatten may be faster than Array#sum
 *    for an +Array+ of Strings or an +Array+ of Arrays.
 *  - Array#sum method may not respect method redefinition of "+" methods such as Integer#+.
 *
 */

static VALUE
rb_ary_sum(int argc, VALUE *argv, VALUE ary)
{
    VALUE e, v, r;
    long i, n;
    int block_given;

    v = (rb_check_arity(argc, 0, 1) ? argv[0] : LONG2FIX(0));

    block_given = rb_block_given_p();

    if (RARRAY_LEN(ary) == 0)
        return v;

    n = 0;
    r = Qundef;

    if (!FIXNUM_P(v) && !RB_BIGNUM_TYPE_P(v) && !RB_TYPE_P(v, T_RATIONAL)) {
        i = 0;
        goto init_is_a_value;
    }

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        e = RARRAY_AREF(ary, i);
        if (block_given)
            e = rb_yield(e);
        if (FIXNUM_P(e)) {
            n += FIX2LONG(e); /* should not overflow long type */
            if (!FIXABLE(n)) {
                v = rb_big_plus(LONG2NUM(n), v);
                n = 0;
            }
        }
        else if (RB_BIGNUM_TYPE_P(e))
            v = rb_big_plus(e, v);
        else if (RB_TYPE_P(e, T_RATIONAL)) {
            if (UNDEF_P(r))
                r = e;
            else
                r = rb_rational_plus(r, e);
        }
        else
            goto not_exact;
    }
    v = finish_exact_sum(n, r, v, argc!=0);
    return v;

  not_exact:
    v = finish_exact_sum(n, r, v, i!=0);

    if (RB_FLOAT_TYPE_P(e)) {
        /*
         * Kahan-Babuska balancing compensated summation algorithm
         * See https://link.springer.com/article/10.1007/s00607-005-0139-x
         */
        double f, c;
        double x, t;

        f = NUM2DBL(v);
        c = 0.0;
        goto has_float_value;
        for (; i < RARRAY_LEN(ary); i++) {
            e = RARRAY_AREF(ary, i);
            if (block_given)
                e = rb_yield(e);
            if (RB_FLOAT_TYPE_P(e))
              has_float_value:
                x = RFLOAT_VALUE(e);
            else if (FIXNUM_P(e))
                x = FIX2LONG(e);
            else if (RB_BIGNUM_TYPE_P(e))
                x = rb_big2dbl(e);
            else if (RB_TYPE_P(e, T_RATIONAL))
                x = rb_num2dbl(e);
            else
                goto not_float;

            if (isnan(f)) continue;
            if (isnan(x)) {
                f = x;
                continue;
            }
            if (isinf(x)) {
                if (isinf(f) && signbit(x) != signbit(f))
                    f = NAN;
                else
                    f = x;
                continue;
            }
            if (isinf(f)) continue;

            t = f + x;
            if (fabs(f) >= fabs(x))
                c += ((f - t) + x);
            else
                c += ((x - t) + f);
            f = t;
        }
        f += c;
        return DBL2NUM(f);

      not_float:
        v = DBL2NUM(f);
    }

    goto has_some_value;
    init_is_a_value:
    for (; i < RARRAY_LEN(ary); i++) {
        e = RARRAY_AREF(ary, i);
        if (block_given)
            e = rb_yield(e);
      has_some_value:
        v = rb_funcall(v, idPLUS, 1, e);
    }
    return v;
}

/* :nodoc: */
static VALUE
rb_ary_deconstruct(VALUE ary)
{
    return ary;
}

/*
 *  An +Array+ is an ordered, integer-indexed collection of objects, called _elements_.
 *  Any object (even another array) may be an array element,
 *  and an array can contain objects of different types.
 *
 *  == +Array+ Indexes
 *
 *  +Array+ indexing starts at 0, as in C or Java.
 *
 *  A positive index is an offset from the first element:
 *
 *  - Index 0 indicates the first element.
 *  - Index 1 indicates the second element.
 *  - ...
 *
 *  A negative index is an offset, backwards, from the end of the array:
 *
 *  - Index -1 indicates the last element.
 *  - Index -2 indicates the next-to-last element.
 *  - ...
 *
 *  A non-negative index is <i>in range</i> if and only if it is smaller than
 *  the size of the array.  For a 3-element array:
 *
 *  - Indexes 0 through 2 are in range.
 *  - Index 3 is out of range.
 *
 *  A negative index is <i>in range</i> if and only if its absolute value is
 *  not larger than the size of the array.  For a 3-element array:
 *
 *  - Indexes -1 through -3 are in range.
 *  - Index -4 is out of range.
 *
 *  Although the effective index into an array is always an integer,
 *  some methods (both within and outside of class +Array+)
 *  accept one or more non-integer arguments that are
 *  {integer-convertible objects}[rdoc-ref:implicit_conversion.rdoc@Integer-Convertible+Objects].
 *
 *
 *  == Creating Arrays
 *
 *  You can create an +Array+ object explicitly with:
 *
 *  - An {array literal}[rdoc-ref:literals.rdoc@Array+Literals]:
 *
 *      [1, 'one', :one, [2, 'two', :two]]
 *
 *  - A {%w or %W: string-array Literal}[rdoc-ref:literals.rdoc@25w+and+-25W-3A+String-Array+Literals]:
 *
 *      %w[foo bar baz] # => ["foo", "bar", "baz"]
 *      %w[1 % *]       # => ["1", "%", "*"]
 *
 *  - A {%i pr %I: symbol-array Literal}[rdoc-ref:literals.rdoc@25i+and+-25I-3A+Symbol-Array+Literals]:
 *
 *      %i[foo bar baz] # => [:foo, :bar, :baz]
 *      %i[1 % *]       # => [:"1", :%, :*]
 *
 *  - \Method Kernel#Array:
 *
 *      Array(["a", "b"])             # => ["a", "b"]
 *      Array(1..5)                   # => [1, 2, 3, 4, 5]
 *      Array(key: :value)            # => [[:key, :value]]
 *      Array(nil)                    # => []
 *      Array(1)                      # => [1]
 *      Array({:a => "a", :b => "b"}) # => [[:a, "a"], [:b, "b"]]
 *
 *  - \Method Array.new:
 *
 *      Array.new               # => []
 *      Array.new(3)            # => [nil, nil, nil]
 *      Array.new(4) {Hash.new} # => [{}, {}, {}, {}]
 *      Array.new(3, true)      # => [true, true, true]
 *
 *    Note that the last example above populates the array
 *    with references to the same object.
 *    This is recommended only in cases where that object is a natively immutable object
 *    such as a symbol, a numeric, +nil+, +true+, or +false+.
 *
 *    Another way to create an array with various objects, using a block;
 *    this usage is safe for mutable objects such as hashes, strings or
 *    other arrays:
 *
 *      Array.new(4) {|i| i.to_s } # => ["0", "1", "2", "3"]
 *
 *    Here is a way to create a multi-dimensional array:
 *
 *      Array.new(3) {Array.new(3)}
 *      # => [[nil, nil, nil], [nil, nil, nil], [nil, nil, nil]]
 *
 *  A number of Ruby methods, both in the core and in the standard library,
 *  provide instance method +to_a+, which converts an object to an array.
 *
 *  - ARGF#to_a
 *  - Array#to_a
 *  - Enumerable#to_a
 *  - Hash#to_a
 *  - MatchData#to_a
 *  - NilClass#to_a
 *  - OptionParser#to_a
 *  - Range#to_a
 *  - Set#to_a
 *  - Struct#to_a
 *  - Time#to_a
 *  - Benchmark::Tms#to_a
 *  - CSV::Table#to_a
 *  - Enumerator::Lazy#to_a
 *  - Gem::List#to_a
 *  - Gem::NameTuple#to_a
 *  - Gem::Platform#to_a
 *  - Gem::RequestSet::Lockfile::Tokenizer#to_a
 *  - Gem::SourceList#to_a
 *  - OpenSSL::X509::Extension#to_a
 *  - OpenSSL::X509::Name#to_a
 *  - Racc::ISet#to_a
 *  - Rinda::RingFinger#to_a
 *  - Ripper::Lexer::Elem#to_a
 *  - RubyVM::InstructionSequence#to_a
 *  - YAML::DBM#to_a
 *
 *  == Example Usage
 *
 *  In addition to the methods it mixes in through the Enumerable module, the
 *  +Array+ class has proprietary methods for accessing, searching and otherwise
 *  manipulating arrays.
 *
 *  Some of the more common ones are illustrated below.
 *
 *  == Accessing Elements
 *
 *  Elements in an array can be retrieved using the Array#[] method.  It can
 *  take a single integer argument (a numeric index), a pair of arguments
 *  (start and length) or a range. Negative indices start counting from the end,
 *  with -1 being the last element.
 *
 *     arr = [1, 2, 3, 4, 5, 6]
 *     arr[2]    #=> 3
 *     arr[100]  #=> nil
 *     arr[-3]   #=> 4
 *     arr[2, 3] #=> [3, 4, 5]
 *     arr[1..4] #=> [2, 3, 4, 5]
 *     arr[1..-3] #=> [2, 3, 4]
 *
 *  Another way to access a particular array element is by using the #at method
 *
 *     arr.at(0) #=> 1
 *
 *  The #slice method works in an identical manner to Array#[].
 *
 *  To raise an error for indices outside of the array bounds or else to
 *  provide a default value when that happens, you can use #fetch.
 *
 *     arr = ['a', 'b', 'c', 'd', 'e', 'f']
 *     arr.fetch(100) #=> IndexError: index 100 outside of array bounds: -6...6
 *     arr.fetch(100, "oops") #=> "oops"
 *
 *  The special methods #first and #last will return the first and last
 *  elements of an array, respectively.
 *
 *     arr.first #=> 1
 *     arr.last  #=> 6
 *
 *  To return the first +n+ elements of an array, use #take
 *
 *     arr.take(3) #=> [1, 2, 3]
 *
 *  #drop does the opposite of #take, by returning the elements after +n+
 *  elements have been dropped:
 *
 *     arr.drop(3) #=> [4, 5, 6]
 *
 *  == Obtaining Information about an +Array+
 *
 *  Arrays keep track of their own length at all times.  To query an array
 *  about the number of elements it contains, use #length, #count or #size.
 *
 *    browsers = ['Chrome', 'Firefox', 'Safari', 'Opera', 'IE']
 *    browsers.length #=> 5
 *    browsers.count #=> 5
 *
 *  To check whether an array contains any elements at all
 *
 *    browsers.empty? #=> false
 *
 *  To check whether a particular item is included in the array
 *
 *    browsers.include?('Konqueror') #=> false
 *
 *  == Adding Items to Arrays
 *
 *  Items can be added to the end of an array by using either #push or #<<
 *
 *    arr = [1, 2, 3, 4]
 *    arr.push(5) #=> [1, 2, 3, 4, 5]
 *    arr << 6    #=> [1, 2, 3, 4, 5, 6]
 *
 *  #unshift will add a new item to the beginning of an array.
 *
 *     arr.unshift(0) #=> [0, 1, 2, 3, 4, 5, 6]
 *
 *  With #insert you can add a new element to an array at any position.
 *
 *     arr.insert(3, 'apple')  #=> [0, 1, 2, 'apple', 3, 4, 5, 6]
 *
 *  Using the #insert method, you can also insert multiple values at once:
 *
 *     arr.insert(3, 'orange', 'pear', 'grapefruit')
 *     #=> [0, 1, 2, "orange", "pear", "grapefruit", "apple", 3, 4, 5, 6]
 *
 *  == Removing Items from an +Array+
 *
 *  The method #pop removes the last element in an array and returns it:
 *
 *     arr =  [1, 2, 3, 4, 5, 6]
 *     arr.pop #=> 6
 *     arr #=> [1, 2, 3, 4, 5]
 *
 *  To retrieve and at the same time remove the first item, use #shift:
 *
 *     arr.shift #=> 1
 *     arr #=> [2, 3, 4, 5]
 *
 *  To delete an element at a particular index:
 *
 *     arr.delete_at(2) #=> 4
 *     arr #=> [2, 3, 5]
 *
 *  To delete a particular element anywhere in an array, use #delete:
 *
 *     arr = [1, 2, 2, 3]
 *     arr.delete(2) #=> 2
 *     arr #=> [1,3]
 *
 *  A useful method if you need to remove +nil+ values from an array is
 *  #compact:
 *
 *     arr = ['foo', 0, nil, 'bar', 7, 'baz', nil]
 *     arr.compact  #=> ['foo', 0, 'bar', 7, 'baz']
 *     arr          #=> ['foo', 0, nil, 'bar', 7, 'baz', nil]
 *     arr.compact! #=> ['foo', 0, 'bar', 7, 'baz']
 *     arr          #=> ['foo', 0, 'bar', 7, 'baz']
 *
 *  Another common need is to remove duplicate elements from an array.
 *
 *  It has the non-destructive #uniq, and destructive method #uniq!
 *
 *     arr = [2, 5, 6, 556, 6, 6, 8, 9, 0, 123, 556]
 *     arr.uniq #=> [2, 5, 6, 556, 8, 9, 0, 123]
 *
 *  == Iterating over Arrays
 *
 *  Like all classes that include the Enumerable module, +Array+ has an each
 *  method, which defines what elements should be iterated over and how.  In
 *  case of Array's #each, all elements in the +Array+ instance are yielded to
 *  the supplied block in sequence.
 *
 *  Note that this operation leaves the array unchanged.
 *
 *     arr = [1, 2, 3, 4, 5]
 *     arr.each {|a| print a -= 10, " "}
 *     # prints: -9 -8 -7 -6 -5
 *     #=> [1, 2, 3, 4, 5]
 *
 *  Another sometimes useful iterator is #reverse_each which will iterate over
 *  the elements in the array in reverse order.
 *
 *     words = %w[first second third fourth fifth sixth]
 *     str = ""
 *     words.reverse_each {|word| str += "#{word} "}
 *     p str #=> "sixth fifth fourth third second first "
 *
 *  The #map method can be used to create a new array based on the original
 *  array, but with the values modified by the supplied block:
 *
 *     arr.map {|a| 2*a}     #=> [2, 4, 6, 8, 10]
 *     arr                   #=> [1, 2, 3, 4, 5]
 *     arr.map! {|a| a**2}   #=> [1, 4, 9, 16, 25]
 *     arr                   #=> [1, 4, 9, 16, 25]
 *
 *
 *  == Selecting Items from an +Array+
 *
 *  Elements can be selected from an array according to criteria defined in a
 *  block.  The selection can happen in a destructive or a non-destructive
 *  manner.  While the destructive operations will modify the array they were
 *  called on, the non-destructive methods usually return a new array with the
 *  selected elements, but leave the original array unchanged.
 *
 *  === Non-destructive Selection
 *
 *     arr = [1, 2, 3, 4, 5, 6]
 *     arr.select {|a| a > 3}       #=> [4, 5, 6]
 *     arr.reject {|a| a < 3}       #=> [3, 4, 5, 6]
 *     arr.drop_while {|a| a < 4}   #=> [4, 5, 6]
 *     arr                          #=> [1, 2, 3, 4, 5, 6]
 *
 *  === Destructive Selection
 *
 *  #select! and #reject! are the corresponding destructive methods to #select
 *  and #reject
 *
 *  Similar to #select vs. #reject, #delete_if and #keep_if have the exact
 *  opposite result when supplied with the same block:
 *
 *     arr.delete_if {|a| a < 4}   #=> [4, 5, 6]
 *     arr                         #=> [4, 5, 6]
 *
 *     arr = [1, 2, 3, 4, 5, 6]
 *     arr.keep_if {|a| a < 4}   #=> [1, 2, 3]
 *     arr                       #=> [1, 2, 3]
 *
 *  == What's Here
 *
 *  First, what's elsewhere. \Class +Array+:
 *
 *  - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
 *  - Includes {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here],
 *    which provides dozens of additional methods.
 *
 *  Here, class +Array+ provides methods that are useful for:
 *
 *  - {Creating an Array}[rdoc-ref:Array@Methods+for+Creating+an+Array]
 *  - {Querying}[rdoc-ref:Array@Methods+for+Querying]
 *  - {Comparing}[rdoc-ref:Array@Methods+for+Comparing]
 *  - {Fetching}[rdoc-ref:Array@Methods+for+Fetching]
 *  - {Assigning}[rdoc-ref:Array@Methods+for+Assigning]
 *  - {Deleting}[rdoc-ref:Array@Methods+for+Deleting]
 *  - {Combining}[rdoc-ref:Array@Methods+for+Combining]
 *  - {Iterating}[rdoc-ref:Array@Methods+for+Iterating]
 *  - {Converting}[rdoc-ref:Array@Methods+for+Converting]
 *  - {And more....}[rdoc-ref:Array@Other+Methods]
 *
 *  === Methods for Creating an +Array+
 *
 *  - ::[]: Returns a new array populated with given objects.
 *  - ::new: Returns a new array.
 *  - ::try_convert: Returns a new array created from a given object.
 *
 *  === Methods for Querying
 *
 *  - #length, #size: Returns the count of elements.
 *  - #include?: Returns whether any element <tt>==</tt> a given object.
 *  - #empty?: Returns whether there are no elements.
 *  - #all?: Returns whether all elements meet a given criterion.
 *  - #any?: Returns whether any element meets a given criterion.
 *  - #none?: Returns whether no element <tt>==</tt> a given object.
 *  - #one?: Returns whether exactly one element <tt>==</tt> a given object.
 *  - #count: Returns the count of elements that meet a given criterion.
 *  - #find_index, #index: Returns the index of the first element that meets a given criterion.
 *  - #rindex: Returns the index of the last element that meets a given criterion.
 *  - #hash: Returns the integer hash code.
 *
 *  === Methods for Comparing
 *
 *  - #<=>: Returns -1, 0, or 1 * as +self+ is less than, equal to, or
 *    greater than a given object.
 *  - #==: Returns whether each element in +self+ is <tt>==</tt> to the corresponding element
 *    in a given object.
 *  - #eql?: Returns whether each element in +self+ is <tt>eql?</tt> to the corresponding
 *    element in a given object.

 *  === Methods for Fetching
 *
 *  These methods do not modify +self+.
 *
 *  - #[]: Returns one or more elements.
 *  - #fetch: Returns the element at a given offset.
 *  - #first: Returns one or more leading elements.
 *  - #last: Returns one or more trailing elements.
 *  - #max: Returns one or more maximum-valued elements,
 *    as determined by <tt><=></tt> or a given block.
 *  - #min: Returns one or more minimum-valued elements,
 *    as determined by <tt><=></tt> or a given block.
 *  - #minmax: Returns the minimum-valued and maximum-valued elements,
 *    as determined by <tt><=></tt> or a given block.
 *  - #assoc: Returns the first element that is an array
 *    whose first element <tt>==</tt> a given object.
 *  - #rassoc: Returns the first element that is an array
 *    whose second element <tt>==</tt> a given object.
 *  - #at: Returns the element at a given offset.
 *  - #values_at: Returns the elements at given offsets.
 *  - #dig: Returns the object in nested objects
 *    that is specified by a given index and additional arguments.
 *  - #drop: Returns trailing elements as determined by a given index.
 *  - #take: Returns leading elements as determined by a given index.
 *  - #drop_while: Returns trailing elements as determined by a given block.
 *  - #take_while: Returns leading elements as determined by a given block.
 *  - #slice: Returns consecutive elements as determined by a given argument.
 *  - #sort: Returns all elements in an order determined by <tt><=></tt> or a given block.
 *  - #reverse: Returns all elements in reverse order.
 *  - #compact: Returns an array containing all non-+nil+ elements.
 *  - #select, #filter: Returns an array containing elements selected by a given block.
 *  - #uniq: Returns an array containing non-duplicate elements.
 *  - #rotate: Returns all elements with some rotated from one end to the other.
 *  - #bsearch: Returns an element selected via a binary search
 *    as determined by a given block.
 *  - #bsearch_index: Returns the index of an element selected via a binary search
 *    as determined by a given block.
 *  - #sample: Returns one or more random elements.
 *  - #shuffle: Returns elements in a random order.
 *
 *  === Methods for Assigning
 *
 *  These methods add, replace, or reorder elements in +self+.
 *
 *  - #[]=: Assigns specified elements with a given object.
 *  - #push, #append, #<<: Appends trailing elements.
 *  - #unshift, #prepend: Prepends leading elements.
 *  - #insert: Inserts given objects at a given offset; does not replace elements.
 *  - #concat: Appends all elements from given arrays.
 *  - #fill: Replaces specified elements with specified objects.
 *  - #replace: Replaces the content of +self+ with the content of a given array.
 *  - #reverse!: Replaces +self+ with its elements reversed.
 *  - #rotate!: Replaces +self+ with its elements rotated.
 *  - #shuffle!: Replaces +self+ with its elements in random order.
 *  - #sort!: Replaces +self+ with its elements sorted,
 *    as determined by <tt><=></tt> or a given block.
 *  - #sort_by!: Replaces +self+ with its elements sorted, as determined by a given block.
 *
 *  === Methods for Deleting
 *
 *  Each of these methods removes elements from +self+:
 *
 *  - #pop: Removes and returns the last element.
 *  - #shift:  Removes and returns the first element.
 *  - #compact!: Removes all +nil+ elements.
 *  - #delete: Removes elements equal to a given object.
 *  - #delete_at: Removes the element at a given offset.
 *  - #delete_if: Removes elements specified by a given block.
 *  - #keep_if: Removes elements not specified by a given block.
 *  - #reject!: Removes elements specified by a given block.
 *  - #select!, #filter!: Removes elements not specified by a given block.
 *  - #slice!: Removes and returns a sequence of elements.
 *  - #uniq!: Removes duplicates.
 *
 *  === Methods for Combining
 *
 *  - #&: Returns an array containing elements found both in +self+ and a given array.
 *  - #intersection: Returns an array containing elements found both in +self+
 *    and in each given array.
 *  - #+: Returns an array containing all elements of +self+ followed by all elements of a given array.
 *  - #-: Returns an array containing all elements of +self+ that are not found in a given array.
 *  - #|: Returns an array containing all elements of +self+ and all elements of a given array,
 *    duplicates removed.
 *  - #union: Returns an array containing all elements of +self+ and all elements of given arrays,
 *    duplicates removed.
 *  - #difference: Returns an array containing all elements of +self+ that are not found
 *    in any of the given arrays..
 *  - #product: Returns or yields all combinations of elements from +self+ and given arrays.
 *
 *  === Methods for Iterating
 *
 *  - #each: Passes each element to a given block.
 *  - #reverse_each:  Passes each element, in reverse order, to a given block.
 *  - #each_index: Passes each element index to a given block.
 *  - #cycle: Calls a given block with each element, then does so again,
 *    for a specified number of times, or forever.
 *  - #combination: Calls a given block with combinations of elements of +self+;
 *    a combination does not use the same element more than once.
 *  - #permutation: Calls a given block with permutations of elements of +self+;
 *    a permutation does not use the same element more than once.
 *  - #repeated_combination: Calls a given block with combinations of elements of +self+;
 *    a combination may use the same element more than once.
 *  - #repeated_permutation: Calls a given block with permutations of elements of +self+;
 *    a permutation may use the same element more than once.
 *
 *  === Methods for Converting
 *
 *  - #map, #collect: Returns an array containing the block return-value for each element.
 *  - #map!, #collect!: Replaces each element with a block return-value.
 *  - #flatten: Returns an array that is a recursive flattening of +self+.
 *  - #flatten!: Replaces each nested array in +self+ with the elements from that array.
 *  - #inspect, #to_s: Returns a new String containing the elements.
 *  - #join: Returns a newsString containing the elements joined by the field separator.
 *  - #to_a: Returns +self+ or a new array containing all elements.
 *  - #to_ary: Returns +self+.
 *  - #to_h: Returns a new hash formed from the elements.
 *  - #transpose: Transposes +self+, which must be an array of arrays.
 *  - #zip: Returns a new array of arrays containing +self+ and given arrays;
 *    follow the link for details.
 *
 *  === Other Methods
 *
 *  - #*: Returns one of the following:
 *
 *    - With integer argument +n+, a new array that is the concatenation
 *      of +n+ copies of +self+.
 *    - With string argument +field_separator+, a new string that is equivalent to
 *      <tt>join(field_separator)</tt>.
 *
 *  - #abbrev: Returns a hash of unambiguous abbreviations for elements.
 *  - #pack: Packs the elements into a binary sequence.
 *  - #sum: Returns a sum of elements according to either <tt>+</tt> or a given block.
 */

void
Init_Array(void)
{
    rb_cArray  = rb_define_class("Array", rb_cObject);
    rb_include_module(rb_cArray, rb_mEnumerable);

    rb_define_alloc_func(rb_cArray, empty_ary_alloc);
    rb_define_singleton_method(rb_cArray, "new", rb_ary_s_new, -1);
    rb_define_singleton_method(rb_cArray, "[]", rb_ary_s_create, -1);
    rb_define_singleton_method(rb_cArray, "try_convert", rb_ary_s_try_convert, 1);
    rb_define_method(rb_cArray, "initialize", rb_ary_initialize, -1);
    rb_define_method(rb_cArray, "initialize_copy", rb_ary_replace, 1);

    rb_define_method(rb_cArray, "inspect", rb_ary_inspect, 0);
    rb_define_alias(rb_cArray,  "to_s", "inspect");
    rb_define_method(rb_cArray, "to_a", rb_ary_to_a, 0);
    rb_define_method(rb_cArray, "to_h", rb_ary_to_h, 0);
    rb_define_method(rb_cArray, "to_ary", rb_ary_to_ary_m, 0);

    rb_define_method(rb_cArray, "==", rb_ary_equal, 1);
    rb_define_method(rb_cArray, "eql?", rb_ary_eql, 1);
    rb_define_method(rb_cArray, "hash", rb_ary_hash, 0);

    rb_define_method(rb_cArray, "[]", rb_ary_aref, -1);
    rb_define_method(rb_cArray, "[]=", rb_ary_aset, -1);
    rb_define_method(rb_cArray, "at", rb_ary_at, 1);
    rb_define_method(rb_cArray, "fetch", rb_ary_fetch, -1);
    rb_define_method(rb_cArray, "concat", rb_ary_concat_multi, -1);
    rb_define_method(rb_cArray, "union", rb_ary_union_multi, -1);
    rb_define_method(rb_cArray, "difference", rb_ary_difference_multi, -1);
    rb_define_method(rb_cArray, "intersection", rb_ary_intersection_multi, -1);
    rb_define_method(rb_cArray, "intersect?", rb_ary_intersect_p, 1);
    rb_define_method(rb_cArray, "<<", rb_ary_push, 1);
    rb_define_method(rb_cArray, "push", rb_ary_push_m, -1);
    rb_define_alias(rb_cArray,  "append", "push");
    rb_define_method(rb_cArray, "pop", rb_ary_pop_m, -1);
    rb_define_method(rb_cArray, "shift", rb_ary_shift_m, -1);
    rb_define_method(rb_cArray, "unshift", rb_ary_unshift_m, -1);
    rb_define_alias(rb_cArray,  "prepend", "unshift");
    rb_define_method(rb_cArray, "insert", rb_ary_insert, -1);
    rb_define_method(rb_cArray, "each_index", rb_ary_each_index, 0);
    rb_define_method(rb_cArray, "reverse_each", rb_ary_reverse_each, 0);
    rb_define_method(rb_cArray, "length", rb_ary_length, 0);
    rb_define_method(rb_cArray, "size", rb_ary_length, 0);
    rb_define_method(rb_cArray, "empty?", rb_ary_empty_p, 0);
    rb_define_method(rb_cArray, "find_index", rb_ary_index, -1);
    rb_define_method(rb_cArray, "index", rb_ary_index, -1);
    rb_define_method(rb_cArray, "rindex", rb_ary_rindex, -1);
    rb_define_method(rb_cArray, "join", rb_ary_join_m, -1);
    rb_define_method(rb_cArray, "reverse", rb_ary_reverse_m, 0);
    rb_define_method(rb_cArray, "reverse!", rb_ary_reverse_bang, 0);
    rb_define_method(rb_cArray, "rotate", rb_ary_rotate_m, -1);
    rb_define_method(rb_cArray, "rotate!", rb_ary_rotate_bang, -1);
    rb_define_method(rb_cArray, "sort", rb_ary_sort, 0);
    rb_define_method(rb_cArray, "sort!", rb_ary_sort_bang, 0);
    rb_define_method(rb_cArray, "sort_by!", rb_ary_sort_by_bang, 0);
    rb_define_method(rb_cArray, "collect", rb_ary_collect, 0);
    rb_define_method(rb_cArray, "collect!", rb_ary_collect_bang, 0);
    rb_define_method(rb_cArray, "map", rb_ary_collect, 0);
    rb_define_method(rb_cArray, "map!", rb_ary_collect_bang, 0);
    rb_define_method(rb_cArray, "select", rb_ary_select, 0);
    rb_define_method(rb_cArray, "select!", rb_ary_select_bang, 0);
    rb_define_method(rb_cArray, "filter", rb_ary_select, 0);
    rb_define_method(rb_cArray, "filter!", rb_ary_select_bang, 0);
    rb_define_method(rb_cArray, "keep_if", rb_ary_keep_if, 0);
    rb_define_method(rb_cArray, "values_at", rb_ary_values_at, -1);
    rb_define_method(rb_cArray, "delete", rb_ary_delete, 1);
    rb_define_method(rb_cArray, "delete_at", rb_ary_delete_at_m, 1);
    rb_define_method(rb_cArray, "delete_if", rb_ary_delete_if, 0);
    rb_define_method(rb_cArray, "reject", rb_ary_reject, 0);
    rb_define_method(rb_cArray, "reject!", rb_ary_reject_bang, 0);
    rb_define_method(rb_cArray, "zip", rb_ary_zip, -1);
    rb_define_method(rb_cArray, "transpose", rb_ary_transpose, 0);
    rb_define_method(rb_cArray, "replace", rb_ary_replace, 1);
    rb_define_method(rb_cArray, "clear", rb_ary_clear, 0);
    rb_define_method(rb_cArray, "fill", rb_ary_fill, -1);
    rb_define_method(rb_cArray, "include?", rb_ary_includes, 1);
    rb_define_method(rb_cArray, "<=>", rb_ary_cmp, 1);

    rb_define_method(rb_cArray, "slice", rb_ary_aref, -1);
    rb_define_method(rb_cArray, "slice!", rb_ary_slice_bang, -1);

    rb_define_method(rb_cArray, "assoc", rb_ary_assoc, 1);
    rb_define_method(rb_cArray, "rassoc", rb_ary_rassoc, 1);

    rb_define_method(rb_cArray, "+", rb_ary_plus, 1);
    rb_define_method(rb_cArray, "*", rb_ary_times, 1);

    rb_define_method(rb_cArray, "-", rb_ary_diff, 1);
    rb_define_method(rb_cArray, "&", rb_ary_and, 1);
    rb_define_method(rb_cArray, "|", rb_ary_or, 1);

    rb_define_method(rb_cArray, "max", rb_ary_max, -1);
    rb_define_method(rb_cArray, "min", rb_ary_min, -1);
    rb_define_method(rb_cArray, "minmax", rb_ary_minmax, 0);

    rb_define_method(rb_cArray, "uniq", rb_ary_uniq, 0);
    rb_define_method(rb_cArray, "uniq!", rb_ary_uniq_bang, 0);
    rb_define_method(rb_cArray, "compact", rb_ary_compact, 0);
    rb_define_method(rb_cArray, "compact!", rb_ary_compact_bang, 0);
    rb_define_method(rb_cArray, "flatten", rb_ary_flatten, -1);
    rb_define_method(rb_cArray, "flatten!", rb_ary_flatten_bang, -1);
    rb_define_method(rb_cArray, "count", rb_ary_count, -1);
    rb_define_method(rb_cArray, "cycle", rb_ary_cycle, -1);
    rb_define_method(rb_cArray, "permutation", rb_ary_permutation, -1);
    rb_define_method(rb_cArray, "combination", rb_ary_combination, 1);
    rb_define_method(rb_cArray, "repeated_permutation", rb_ary_repeated_permutation, 1);
    rb_define_method(rb_cArray, "repeated_combination", rb_ary_repeated_combination, 1);
    rb_define_method(rb_cArray, "product", rb_ary_product, -1);

    rb_define_method(rb_cArray, "take", rb_ary_take, 1);
    rb_define_method(rb_cArray, "take_while", rb_ary_take_while, 0);
    rb_define_method(rb_cArray, "drop", rb_ary_drop, 1);
    rb_define_method(rb_cArray, "drop_while", rb_ary_drop_while, 0);
    rb_define_method(rb_cArray, "bsearch", rb_ary_bsearch, 0);
    rb_define_method(rb_cArray, "bsearch_index", rb_ary_bsearch_index, 0);
    rb_define_method(rb_cArray, "any?", rb_ary_any_p, -1);
    rb_define_method(rb_cArray, "all?", rb_ary_all_p, -1);
    rb_define_method(rb_cArray, "none?", rb_ary_none_p, -1);
    rb_define_method(rb_cArray, "one?", rb_ary_one_p, -1);
    rb_define_method(rb_cArray, "dig", rb_ary_dig, -1);
    rb_define_method(rb_cArray, "sum", rb_ary_sum, -1);
    rb_define_method(rb_cArray, "freeze", rb_ary_freeze, 0);

    rb_define_method(rb_cArray, "deconstruct", rb_ary_deconstruct, 0);
}

#include "array.rbinc"
