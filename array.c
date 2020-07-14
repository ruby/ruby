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
#include "transient_heap.h"
#include "builtin.h"

#if !ARRAY_DEBUG
# undef NDEBUG
# define NDEBUG
#endif
#include "ruby_assert.h"

VALUE rb_cArray;

/* for OPTIMIZED_CMP: */
#define id_cmp idCmp

#define ARY_DEFAULT_SIZE 16
#define ARY_MAX_SIZE (LONG_MAX / (int)sizeof(VALUE))
#define SMALL_ARRAY_LEN 16

static int
should_be_T_ARRAY(VALUE ary)
{
    return RB_TYPE_P(ary, T_ARRAY);
}

static int
should_not_be_shared_and_embedded(VALUE ary)
{
    return !FL_TEST((ary), ELTS_SHARED) || !FL_TEST((ary), RARRAY_EMBED_FLAG);
}

#define ARY_SHARED_P(ary) \
  (assert(should_be_T_ARRAY((VALUE)(ary))), \
   assert(should_not_be_shared_and_embedded((VALUE)ary)), \
   FL_TEST_RAW((ary),ELTS_SHARED)!=0)

#define ARY_EMBED_P(ary) \
  (assert(should_be_T_ARRAY((VALUE)(ary))), \
   assert(should_not_be_shared_and_embedded((VALUE)ary)), \
   FL_TEST_RAW((ary), RARRAY_EMBED_FLAG) != 0)

#define ARY_HEAP_PTR(a) (assert(!ARY_EMBED_P(a)), RARRAY(a)->as.heap.ptr)
#define ARY_HEAP_LEN(a) (assert(!ARY_EMBED_P(a)), RARRAY(a)->as.heap.len)
#define ARY_HEAP_CAPA(a) (assert(!ARY_EMBED_P(a)), assert(!ARY_SHARED_ROOT_P(a)), \
                          RARRAY(a)->as.heap.aux.capa)

#define ARY_EMBED_PTR(a) (assert(ARY_EMBED_P(a)), RARRAY(a)->as.ary)
#define ARY_EMBED_LEN(a) \
    (assert(ARY_EMBED_P(a)), \
     (long)((RBASIC(a)->flags >> RARRAY_EMBED_LEN_SHIFT) & \
	 (RARRAY_EMBED_LEN_MASK >> RARRAY_EMBED_LEN_SHIFT)))
#define ARY_HEAP_SIZE(a) (assert(!ARY_EMBED_P(a)), assert(ARY_OWNS_HEAP_P(a)), ARY_CAPA(a) * sizeof(VALUE))

#define ARY_OWNS_HEAP_P(a) (assert(should_be_T_ARRAY((VALUE)(a))), \
                            !FL_TEST_RAW((a), ELTS_SHARED|RARRAY_EMBED_FLAG))

#define FL_SET_EMBED(a) do { \
    assert(!ARY_SHARED_P(a)); \
    FL_SET((a), RARRAY_EMBED_FLAG); \
    RARY_TRANSIENT_UNSET(a); \
    ary_verify(a); \
} while (0)

#define FL_UNSET_EMBED(ary) FL_UNSET((ary), RARRAY_EMBED_FLAG|RARRAY_EMBED_LEN_MASK)
#define FL_SET_SHARED(ary) do { \
    assert(!ARY_EMBED_P(ary)); \
    FL_SET((ary), ELTS_SHARED); \
} while (0)
#define FL_UNSET_SHARED(ary) FL_UNSET((ary), ELTS_SHARED)

#define ARY_SET_PTR(ary, p) do { \
    assert(!ARY_EMBED_P(ary)); \
    assert(!OBJ_FROZEN(ary)); \
    RARRAY(ary)->as.heap.ptr = (p); \
} while (0)
#define ARY_SET_EMBED_LEN(ary, n) do { \
    long tmp_n = (n); \
    assert(ARY_EMBED_P(ary)); \
    assert(!OBJ_FROZEN(ary)); \
    RBASIC(ary)->flags &= ~RARRAY_EMBED_LEN_MASK; \
    RBASIC(ary)->flags |= (tmp_n) << RARRAY_EMBED_LEN_SHIFT; \
} while (0)
#define ARY_SET_HEAP_LEN(ary, n) do { \
    assert(!ARY_EMBED_P(ary)); \
    RARRAY(ary)->as.heap.len = (n); \
} while (0)
#define ARY_SET_LEN(ary, n) do { \
    if (ARY_EMBED_P(ary)) { \
        ARY_SET_EMBED_LEN((ary), (n)); \
    } \
    else { \
        ARY_SET_HEAP_LEN((ary), (n)); \
    } \
    assert(RARRAY_LEN(ary) == (n)); \
} while (0)
#define ARY_INCREASE_PTR(ary, n) do  { \
    assert(!ARY_EMBED_P(ary)); \
    assert(!OBJ_FROZEN(ary)); \
    RARRAY(ary)->as.heap.ptr += (n); \
} while (0)
#define ARY_INCREASE_LEN(ary, n) do  { \
    assert(!OBJ_FROZEN(ary)); \
    if (ARY_EMBED_P(ary)) { \
        ARY_SET_EMBED_LEN((ary), RARRAY_LEN(ary)+(n)); \
    } \
    else { \
        RARRAY(ary)->as.heap.len += (n); \
    } \
} while (0)

#define ARY_CAPA(ary) (ARY_EMBED_P(ary) ? RARRAY_EMBED_LEN_MAX : \
                       ARY_SHARED_ROOT_P(ary) ? RARRAY_LEN(ary) : ARY_HEAP_CAPA(ary))
#define ARY_SET_CAPA(ary, n) do { \
    assert(!ARY_EMBED_P(ary)); \
    assert(!ARY_SHARED_P(ary)); \
    assert(!OBJ_FROZEN(ary)); \
    RARRAY(ary)->as.heap.aux.capa = (n); \
} while (0)

#define ARY_SHARED_ROOT(ary) (assert(ARY_SHARED_P(ary)), RARRAY(ary)->as.heap.aux.shared_root)
#define ARY_SET_SHARED(ary, value) do { \
    const VALUE _ary_ = (ary); \
    const VALUE _value_ = (value); \
    assert(!ARY_EMBED_P(_ary_)); \
    assert(ARY_SHARED_P(_ary_)); \
    assert(ARY_SHARED_ROOT_P(_value_)); \
    RB_OBJ_WRITE(_ary_, &RARRAY(_ary_)->as.heap.aux.shared_root, _value_); \
} while (0)
#define RARRAY_SHARED_ROOT_FLAG FL_USER5
#define ARY_SHARED_ROOT_P(ary) (assert(should_be_T_ARRAY((VALUE)(ary))), \
                                FL_TEST_RAW((ary), RARRAY_SHARED_ROOT_FLAG))
#define ARY_SHARED_ROOT_REFCNT(ary) \
    (assert(ARY_SHARED_ROOT_P(ary)), RARRAY(ary)->as.heap.aux.capa)
#define ARY_SHARED_ROOT_OCCUPIED(ary) (ARY_SHARED_ROOT_REFCNT(ary) == 1)
#define ARY_SET_SHARED_ROOT_REFCNT(ary, value) do { \
    assert(ARY_SHARED_ROOT_P(ary)); \
    RARRAY(ary)->as.heap.aux.capa = (value); \
} while (0)
#define FL_SET_SHARED_ROOT(ary) do { \
    assert(!ARY_EMBED_P(ary)); \
    assert(!RARRAY_TRANSIENT_P(ary)); \
    FL_SET((ary), RARRAY_SHARED_ROOT_FLAG); \
} while (0)

static inline void
ARY_SET(VALUE a, long i, VALUE v)
{
    assert(!ARY_SHARED_P(a));
    assert(!OBJ_FROZEN(a));

    RARRAY_ASET(a, i, v);
}
#undef RARRAY_ASET


#if ARRAY_DEBUG
#define ary_verify(ary) ary_verify_(ary, __FILE__, __LINE__)

static VALUE
ary_verify_(VALUE ary, const char *file, int line)
{
    assert(RB_TYPE_P(ary, T_ARRAY));

    if (FL_TEST(ary, ELTS_SHARED)) {
        VALUE root = RARRAY(ary)->as.heap.aux.shared_root;
        const VALUE *ptr = ARY_HEAP_PTR(ary);
        const VALUE *root_ptr = RARRAY_CONST_PTR_TRANSIENT(root);
        long len = ARY_HEAP_LEN(ary), root_len = RARRAY_LEN(root);
        assert(FL_TEST(root, RARRAY_SHARED_ROOT_FLAG));
        assert(root_ptr <= ptr && ptr + len <= root_ptr + root_len);
        ary_verify(root);
    }
    else if (ARY_EMBED_P(ary)) {
        assert(!RARRAY_TRANSIENT_P(ary));
        assert(!ARY_SHARED_P(ary));
        assert(RARRAY_LEN(ary) <= RARRAY_EMBED_LEN_MAX);
    }
    else {
#if 1
        const VALUE *ptr = RARRAY_CONST_PTR_TRANSIENT(ary);
        long i, len = RARRAY_LEN(ary);
        volatile VALUE v;
        if (len > 1) len = 1; /* check only HEAD */
        for (i=0; i<len; i++) {
            v = ptr[i]; /* access check */
        }
        v = v;
#endif
    }

#if USE_TRANSIENT_HEAP
    if (RARRAY_TRANSIENT_P(ary)) {
        assert(rb_transient_heap_managed_ptr_p(RARRAY_CONST_PTR_TRANSIENT(ary)));
    }
#endif

    rb_transient_heap_verify();

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
    return (VALUE *)RARRAY_CONST_PTR_TRANSIENT(ary);
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
    RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
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
    RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
	memfill(ptr + beg, size, val);
	RB_OBJ_WRITTEN(ary, Qundef, val);
    });
}

static void
ary_memcpy0(VALUE ary, long beg, long argc, const VALUE *argv, VALUE buff_owner_ary)
{
    assert(!ARY_SHARED_P(buff_owner_ary));

    if (argc > (int)(128/sizeof(VALUE)) /* is magic number (cache line size) */) {
        rb_gc_writebarrier_remember(buff_owner_ary);
        RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
            MEMCPY(ptr+beg, argv, VALUE, argc);
        });
    }
    else {
        int i;
        RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
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
ary_heap_alloc(VALUE ary, size_t capa)
{
    VALUE *ptr = rb_transient_heap_alloc(ary, sizeof(VALUE) * capa);

    if (ptr != NULL) {
        RARY_TRANSIENT_SET(ary);
    }
    else {
        RARY_TRANSIENT_UNSET(ary);
        ptr = ALLOC_N(VALUE, capa);
    }

    return ptr;
}

static void
ary_heap_free_ptr(VALUE ary, const VALUE *ptr, long size)
{
    if (RARRAY_TRANSIENT_P(ary)) {
        /* ignore it */
    }
    else {
        ruby_sized_xfree((void *)ptr, size);
    }
}

static void
ary_heap_free(VALUE ary)
{
    if (RARRAY_TRANSIENT_P(ary)) {
        RARY_TRANSIENT_UNSET(ary);
    }
    else {
        ary_heap_free_ptr(ary, ARY_HEAP_PTR(ary), ARY_HEAP_SIZE(ary));
    }
}

static void
ary_heap_realloc(VALUE ary, size_t new_capa)
{
    size_t old_capa = ARY_HEAP_CAPA(ary);

    if (RARRAY_TRANSIENT_P(ary)) {
        if (new_capa <= old_capa) {
            /* do nothing */
        }
        else {
            VALUE *new_ptr = rb_transient_heap_alloc(ary, sizeof(VALUE) * new_capa);

            if (new_ptr == NULL) {
                new_ptr = ALLOC_N(VALUE, new_capa);
                RARY_TRANSIENT_UNSET(ary);
            }

            MEMCPY(new_ptr, ARY_HEAP_PTR(ary), VALUE, old_capa);
            ARY_SET_PTR(ary, new_ptr);
        }
    }
    else {
        SIZED_REALLOC_N(RARRAY(ary)->as.heap.ptr, VALUE, new_capa, old_capa);
    }
    ary_verify(ary);
}

#if USE_TRANSIENT_HEAP
static inline void
rb_ary_transient_heap_evacuate_(VALUE ary, int transient, int promote)
{
    if (transient) {
        VALUE *new_ptr;
        const VALUE *old_ptr = ARY_HEAP_PTR(ary);
        long capa = ARY_HEAP_CAPA(ary);
        long len  = ARY_HEAP_LEN(ary);

        if (ARY_SHARED_ROOT_P(ary)) {
            capa = len;
        }

        assert(ARY_OWNS_HEAP_P(ary));
        assert(RARRAY_TRANSIENT_P(ary));
        assert(!ARY_PTR_USING_P(ary));

        if (promote) {
            new_ptr = ALLOC_N(VALUE, capa);
            RARY_TRANSIENT_UNSET(ary);
        }
        else {
            new_ptr = ary_heap_alloc(ary, capa);
        }

        MEMCPY(new_ptr, old_ptr, VALUE, capa);
        /* do not use ARY_SET_PTR() because they assert !frozen */
        RARRAY(ary)->as.heap.ptr = new_ptr;
    }

    ary_verify(ary);
}

void
rb_ary_transient_heap_evacuate(VALUE ary, int promote)
{
    rb_ary_transient_heap_evacuate_(ary, RARRAY_TRANSIENT_P(ary), promote);
}

void
rb_ary_detransient(VALUE ary)
{
    assert(RARRAY_TRANSIENT_P(ary));
    rb_ary_transient_heap_evacuate_(ary, TRUE, TRUE);
}
#else
void
rb_ary_detransient(VALUE ary)
{
    /* do nothing */
}
#endif

static void
ary_resize_capa(VALUE ary, long capacity)
{
    assert(RARRAY_LEN(ary) <= capacity);
    assert(!OBJ_FROZEN(ary));
    assert(!ARY_SHARED_P(ary));

    if (capacity > RARRAY_EMBED_LEN_MAX) {
        if (ARY_EMBED_P(ary)) {
            long len = ARY_EMBED_LEN(ary);
            VALUE *ptr = ary_heap_alloc(ary, capacity);

            MEMCPY(ptr, ARY_EMBED_PTR(ary), VALUE, len);
            FL_UNSET_EMBED(ary);
            ARY_SET_PTR(ary, ptr);
            ARY_SET_HEAP_LEN(ary, len);
        }
        else {
            ary_heap_realloc(ary, capacity);
        }
        ARY_SET_CAPA(ary, capacity);
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
    assert(!ARY_SHARED_P(ary));
    assert(old_capa >= capacity);
    if (old_capa > capacity) ary_heap_realloc(ary, capacity);

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
    if (shared_root) {
        long num = ARY_SHARED_ROOT_REFCNT(shared_root) - 1;
	if (num == 0) {
            rb_ary_free(shared_root);
            rb_gc_force_recycle(shared_root);
	}
	else if (num > 0) {
            ARY_SET_SHARED_ROOT_REFCNT(shared_root, num);
	}
    }
}

static void
rb_ary_unshare(VALUE ary)
{
    VALUE shared_root = RARRAY(ary)->as.heap.aux.shared_root;
    rb_ary_decrement_share(shared_root);
    FL_UNSET_SHARED(ary);
}

static inline void
rb_ary_unshare_safe(VALUE ary)
{
    if (ARY_SHARED_P(ary) && !ARY_EMBED_P(ary)) {
	rb_ary_unshare(ary);
    }
}

static VALUE
rb_ary_increment_share(VALUE shared_root)
{
    long num = ARY_SHARED_ROOT_REFCNT(shared_root);
    if (num >= 0) {
        ARY_SET_SHARED_ROOT_REFCNT(shared_root, num + 1);
    }
    return shared_root;
}

static void
rb_ary_set_shared(VALUE ary, VALUE shared_root)
{
    rb_ary_increment_share(shared_root);
    FL_SET_SHARED(ary);
    RB_DEBUG_COUNTER_INC(obj_ary_shared_create);
    ARY_SET_SHARED(ary, shared_root);
}

static inline void
rb_ary_modify_check(VALUE ary)
{
    rb_check_frozen(ary);
    ary_verify(ary);
}

void
rb_ary_modify(VALUE ary)
{
    rb_ary_modify_check(ary);
    if (ARY_SHARED_P(ary)) {
	long shared_len, len = RARRAY_LEN(ary);
        VALUE shared_root = ARY_SHARED_ROOT(ary);

        ary_verify(shared_root);

        if (len <= RARRAY_EMBED_LEN_MAX) {
	    const VALUE *ptr = ARY_HEAP_PTR(ary);
            FL_UNSET_SHARED(ary);
            FL_SET_EMBED(ary);
	    MEMCPY((VALUE *)ARY_EMBED_PTR(ary), ptr, VALUE, len);
            rb_ary_decrement_share(shared_root);
            ARY_SET_EMBED_LEN(ary, len);
        }
        else if (ARY_SHARED_ROOT_OCCUPIED(shared_root) && len > ((shared_len = RARRAY_LEN(shared_root))>>1)) {
            long shift = RARRAY_CONST_PTR_TRANSIENT(ary) - RARRAY_CONST_PTR_TRANSIENT(shared_root);
	    FL_UNSET_SHARED(ary);
            ARY_SET_PTR(ary, RARRAY_CONST_PTR_TRANSIENT(shared_root));
	    ARY_SET_CAPA(ary, shared_len);
            RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
		MEMMOVE(ptr, ptr+shift, VALUE, len);
	    });
            FL_SET_EMBED(shared_root);
            rb_ary_decrement_share(shared_root);
	}
        else {
            VALUE *ptr = ary_heap_alloc(ary, len);
            MEMCPY(ptr, ARY_HEAP_PTR(ary), VALUE, len);
            rb_ary_unshare(ary);
            ARY_SET_CAPA(ary, len);
            ARY_SET_PTR(ary, ptr);
        }

	rb_gc_writebarrier_remember(ary);
    }
    ary_verify(ary);
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
	if (new_len > RARRAY_EMBED_LEN_MAX) {
            VALUE shared_root = ARY_SHARED_ROOT(ary);
            if (ARY_SHARED_ROOT_OCCUPIED(shared_root)) {
                if (ARY_HEAP_PTR(ary) - RARRAY_CONST_PTR_TRANSIENT(shared_root) + new_len <= RARRAY_LEN(shared_root)) {
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
 *    a = []
 *    a.frozen? # => false
 *    a1 = a.freeze # => []
 *    a.frozen? # => true
 *    a1.equal?(a) # => true # Returned self
 *
 *  An attempt to modify a frozen \Array raises an exception:
 *    # Raises FrozenError (can't modify frozen Array: [:foo, "bar", 2]):
 *    [:foo, 'bar', 2].freeze.push(:foo)
 */

VALUE
rb_ary_freeze(VALUE ary)
{
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
        RARRAY(ary1)->as.heap.aux.shared_root == RARRAY(ary2)->as.heap.aux.shared_root &&
	RARRAY(ary1)->as.heap.len == RARRAY(ary2)->as.heap.len) {
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
ary_alloc(VALUE klass)
{
    NEWOBJ_OF(ary, struct RArray, klass, T_ARRAY | RARRAY_EMBED_FLAG | (RGENGC_WB_PROTECTED_ARRAY ? FL_WB_PROTECTED : 0));
    /* Created array is:
     *   FL_SET_EMBED((VALUE)ary);
     *   ARY_SET_EMBED_LEN((VALUE)ary, 0);
     */
    return (VALUE)ary;
}

static VALUE
empty_ary_alloc(VALUE klass)
{
    RUBY_DTRACE_CREATE_HOOK(ARRAY, 0);
    return ary_alloc(klass);
}

static VALUE
ary_new(VALUE klass, long capa)
{
    VALUE ary,*ptr;

    if (capa < 0) {
	rb_raise(rb_eArgError, "negative array size (or size too big)");
    }
    if (capa > ARY_MAX_SIZE) {
	rb_raise(rb_eArgError, "array size too big");
    }

    RUBY_DTRACE_CREATE_HOOK(ARRAY, capa);

    ary = ary_alloc(klass);
    if (capa > RARRAY_EMBED_LEN_MAX) {
        ptr = ary_heap_alloc(ary, capa);
        FL_UNSET_EMBED(ary);
        ARY_SET_PTR(ary, ptr);
        ARY_SET_CAPA(ary, capa);
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
    return rb_ary_new2(RARRAY_EMBED_LEN_MAX);
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

MJIT_FUNC_EXPORTED VALUE
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

VALUE
rb_ary_tmp_new(long capa)
{
    VALUE ary = ary_new(0, capa);
    rb_ary_transient_heap_evacuate(ary, TRUE);
    return ary;
}

VALUE
rb_ary_tmp_new_fill(long capa)
{
    VALUE ary = ary_new(0, capa);
    ary_memfill(ary, 0, capa, Qnil);
    ARY_SET_LEN(ary, capa);
    rb_ary_transient_heap_evacuate(ary, TRUE);
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

        if (RARRAY_TRANSIENT_P(ary)) {
            RB_DEBUG_COUNTER_INC(obj_ary_transient);
        }
        else {
            RB_DEBUG_COUNTER_INC(obj_ary_ptr);
            ary_heap_free(ary);
        }
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

RUBY_FUNC_EXPORTED size_t
rb_ary_memsize(VALUE ary)
{
    if (ARY_OWNS_HEAP_P(ary)) {
	return ARY_CAPA(ary) * sizeof(VALUE);
    }
    else {
	return 0;
    }
}

static inline void
ary_discard(VALUE ary)
{
    rb_ary_free(ary);
    RBASIC(ary)->flags |= RARRAY_EMBED_FLAG;
    RBASIC(ary)->flags &= ~(RARRAY_EMBED_LEN_MASK | RARRAY_TRANSIENT_FLAG);
}

static VALUE
ary_make_shared(VALUE ary)
{
    assert(!ARY_EMBED_P(ary));
    ary_verify(ary);

    if (ARY_SHARED_P(ary)) {
        return ARY_SHARED_ROOT(ary);
    }
    else if (ARY_SHARED_ROOT_P(ary)) {
	return ary;
    }
    else if (OBJ_FROZEN(ary)) {
        rb_ary_transient_heap_evacuate(ary, TRUE);
	ary_shrink_capa(ary);
	FL_SET_SHARED_ROOT(ary);
        ARY_SET_SHARED_ROOT_REFCNT(ary, 1);
	return ary;
    }
    else {
	long capa = ARY_CAPA(ary), len = RARRAY_LEN(ary);
        const VALUE *ptr;
	NEWOBJ_OF(shared, struct RArray, 0, T_ARRAY | (RGENGC_WB_PROTECTED_ARRAY ? FL_WB_PROTECTED : 0));
        VALUE vshared = (VALUE)shared;

        rb_ary_transient_heap_evacuate(ary, TRUE);
        ptr = ARY_HEAP_PTR(ary);

        FL_UNSET_EMBED(vshared);
        ARY_SET_LEN(vshared, capa);
        ARY_SET_PTR(vshared, ptr);
        ary_mem_clear(vshared, len, capa - len);
        FL_SET_SHARED_ROOT(vshared);
        ARY_SET_SHARED_ROOT_REFCNT(vshared, 1);
	FL_SET_SHARED(ary);
        RB_DEBUG_COUNTER_INC(obj_ary_shared_create);
        ARY_SET_SHARED(ary, vshared);
        OBJ_FREEZE(vshared);

        ary_verify(vshared);
        ary_verify(ary);

        return vshared;
    }
}

static VALUE
ary_make_substitution(VALUE ary)
{
    long len = RARRAY_LEN(ary);

    if (len <= RARRAY_EMBED_LEN_MAX) {
	VALUE subst = rb_ary_new2(len);
        ary_memcpy(subst, 0, len, RARRAY_CONST_PTR_TRANSIENT(ary));
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

MJIT_FUNC_EXPORTED VALUE
rb_check_to_array(VALUE ary)
{
    return rb_check_convert_type_with_id(ary, T_ARRAY, "Array", idTo_a);
}

/*
 *  call-seq:
 *    Array.try_convert(object) -> new_array or nil
 *
 *  Tries to convert +object+ to an \Array.
 *
 *  When +object+ is an
 *  {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects]
 *  (implements +to_ary+),
 *  returns the \Array object created by converting it:
 *
 *    class ToAryReturnsArray < Set
 *      def to_ary
 *        self.to_a
 *      end
 *    end
 *    as = ToAryReturnsArray.new([:foo, :bar, :baz])
 *    Array.try_convert(as) # => [:foo, :bar, :baz]
 *
 *  Returns +nil+ if +object+ is not \Array-convertible:
 *
 *    Array.try_convert(:foo) # => nil
 */

static VALUE
rb_ary_s_try_convert(VALUE dummy, VALUE ary)
{
    return rb_check_array_type(ary);
}

/*
 *  call-seq:
 *    Array.new -> new_empty_array
 *    Array.new(array) -> new_array
 *    Array.new(size) -> new_array
 *    Array.new(size, default_value) -> new_array
 *    Array.new(size) {|index| ... } -> new_array
 *
 *  Returns a new \Array.
 *
 *  Argument +array+, if given, must be an
 *  {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects]
 *  (implements +to_ary+).
 *
 *  Argument +size+, if given must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects]
 *  (implements +to_int+).
 *
 *  Argument +default_value+ may be any object.
 *
 *  ---
 *
 *  With no block and no arguments, returns a new empty \Array object:
 *
 *    a = Array.new
 *    a # => []
 *
 *  With no block and a single argument +array+,
 *  returns a new \Array formed from +array+:
 *
 *    a = Array.new([:foo, 'bar', 2])
 *    a.class # => Array
 *    a # => [:foo, "bar", 2]
 *
 *  With no block and a single argument +size+,
 *  returns a new \Array of the given size
 *  whose elements are all +nil+:
 *
 *    a = Array.new(0)
 *    a # => []
 *    a = Array.new(3)
 *    a # => [nil, nil, nil]
 *
 *  With no block and arguments +size+ and  +default_value+,
 *  returns an \Array of the given size;
 *  each element is that same +default_value+:
 *
 *    a = Array.new(3, 'x')
 *    a # => ['x', 'x', 'x']
 *    a[1].equal?(a[0]) # => true # Identity check.
 *    a[2].equal?(a[0]) # => true # Identity check.
 *
 *  With a block and argument +size+,
 *  returns an \Array of the given size;
 *  the block is called with each successive integer +index+;
 *  the element for that +index+ is the return value from the block:
 *
 *    a = Array.new(3) { |index| "Element #{index}" }
 *    a # => ["Element 0", "Element 1", "Element 2"]
 *
 *  With a block and no argument,
 *  or a single argument +0+,
 *  ignores the block and returns a new empty \Array:
 *
 *    a = Array.new(0) { |n| raise 'Cannot happen' }
 *    a # => []
 *    a = Array.new { |n| raise 'Cannot happen' }
 *    a # => []
 *
 *  With a block and arguments +size+ and +default_value+,
 *  gives a warning message
 *  ('warning: block supersedes default value argument'),
 *  and assigns elements from the block's return values:
 *
 *    Array.new(4, :default) {} # => [nil, nil, nil, nil]
 *
 *  ---
 *
 *  Raises an exception if +size+ is a negative integer:
 *
 *    # Raises ArgumentError (negative array size):
 *    Array.new(-1)
 *    # Raises ArgumentError (negative array size):
 *    Array.new(-1, :default)
 *    # Raises ArgumentError (negative array size):
 *    Array.new(-1) { |n| }
 *
 *  Raises an exception if the single argument is neither \Array-convertible
 *  nor \Integer-convertible.
 *
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    Array.new(:foo)
 */

static VALUE
rb_ary_initialize(int argc, VALUE *argv, VALUE ary)
{
    long len;
    VALUE size, val;

    rb_ary_modify(ary);
    if (argc == 0) {
        if (ARY_OWNS_HEAP_P(ary) && ARY_HEAP_PTR(ary) != NULL) {
            ary_heap_free(ary);
	}
        rb_ary_unshare_safe(ary);
        FL_SET_EMBED(ary);
	ARY_SET_EMBED_LEN(ary, 0);
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
 * Returns a new array populated with the given objects.
 *
 *   Array.[]( 1, 'a', /^A/)  # => [1, "a", /^A/]
 *   Array[ 1, 'a', /^A/ ]    # => [1, "a", /^A/]
 *   [ 1, 'a', /^A/ ]         # => [1, "a", /^A/]
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
    assert(offset >= 0);
    assert(len >= 0);
    assert(offset+len <= RARRAY_LEN(ary));

    if (len <= RARRAY_EMBED_LEN_MAX) {
        VALUE result = ary_alloc(klass);
        ary_memcpy(result, 0, len, RARRAY_CONST_PTR_TRANSIENT(ary) + offset);
        ARY_SET_EMBED_LEN(result, len);
        return result;
    }
    else {
        VALUE shared, result = ary_alloc(klass);
        FL_UNSET_EMBED(result);

        shared = ary_make_shared(ary);
        ARY_SET_PTR(result, RARRAY_CONST_PTR_TRANSIENT(ary));
        ARY_SET_LEN(result, RARRAY_LEN(ary));
        rb_ary_set_shared(result, shared);

        ARY_INCREASE_PTR(result, offset);
        ARY_SET_LEN(result, len);

        ary_verify(shared);
        ary_verify(result);
        return result;
    }
}

static VALUE
ary_make_shared_copy(VALUE ary)
{
    return ary_make_partial(ary, rb_obj_class(ary), 0, RARRAY_LEN(ary));
}

enum ary_take_pos_flags
{
    ARY_TAKE_FIRST = 0,
    ARY_TAKE_LAST = 1
};

static VALUE
ary_take_first_or_last(int argc, const VALUE *argv, VALUE ary, enum ary_take_pos_flags last)
{
    long n;
    long len;
    long offset = 0;

    argc = rb_check_arity(argc, 0, 1);
    /* the case optional argument is omitted should be handled in
     * callers of this function.  if another arity case is added,
     * this arity check needs to rewrite. */
    RUBY_ASSERT_ALWAYS(argc == 1);

    n = NUM2LONG(argv[0]);
    len = RARRAY_LEN(ary);
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

/*
 *  call-seq:
 *    array << object -> self
 *
 *  Appends +object+ to +self+; returns +self+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a << :baz
 *    a1 # => [:foo, "bar", 2, :baz]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Appends +object+ as one element, even if it is another \Array:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a << [3, 4]
 *    a1 # => [:foo, "bar", 2, [3, 4]]
 */

VALUE
rb_ary_push(VALUE ary, VALUE item)
{
    long idx = RARRAY_LEN((ary_verify(ary), ary));
    VALUE target_ary = ary_ensure_room_for_push(ary, 1);
    RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
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
 *    array.append(*objects) -> self
 *
 *  Array#append is an alias for \Array#push.
 *
 *  Appends trailing elements.
 *
 *  See also:
 *  - #pop:  Removes and returns trailing elements.
 *  - #shift:  Removes and returns leading elements.
 *  - #unshift:  Prepends leading elements.
 *
 *  Appends each argument in +objects+ to +self+;  returns +self+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.push(:baz, :bat)
 *    a1 # => [:foo, "bar", 2, :baz, :bat]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Appends each argument as one element, even if it is another \Array:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.push([:baz, :bat], [:bam, :bad])
 *    a1 # => [:foo, "bar", 2, [:baz, :bat], [:bam, :bad]]
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
 *  See also:
 *  - #push:  Appends trailing elements.
 *  - #shift:  Removes and returns leading elements.
 *  - #unshift:  Prepends leading elements.
 *
 *  Argument +n+, if given, must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects]
 *  (implements +to_int+).
 *
 *  ---
 *
 *  When no argument is given and the array is not empty,
 *  removes and returns the last element in the array:
 *
 *    a = [:foo, 'bar', 2]
 *    a.pop # => 2
 *    a # => [:foo, "bar"]
 *
 *  Returns +nil+ if the array is empty:
 *
 *    a = []
 *    a.pop # => nil
 *
 *  ---
 *
 *  When argument +n+ is given and is non-negative and in range,
 *
 *  removes and returns the last +n+ elements in a new \Array:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.pop(2)
 *    a1 # => ["bar", 2]
 *    a # => [:foo]
 *    a.pop(0) # => []
 *
 *  If +n+ is positive and out of range,
 *  removes and returns all elements:
 *
 *    a = [:foo, 'bar', 2]
 *    a1 = a.pop(50)
 *    a1 # => [:foo, "bar", 2]
 *    a # => []
 *    a.pop(1) # => []
 *
 *  ---
 *
 *  Raises an exception if +n+ is negative:
 *
 *    a = [:foo, 'bar', 2]
 *    # Raises ArgumentError (negative array size):
 *    a1 = a.pop(-1)
 *
 *  Raises an exception if +n+ is not \Integer-convertible (implements +to_int+):
 *
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of String into Integer):
 *    a1 = a.pop('x')
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

    rb_ary_modify_check(ary);
    if (len == 0) return Qnil;
    top = RARRAY_AREF(ary, 0);
    if (!ARY_SHARED_P(ary)) {
	if (len < ARY_DEFAULT_SIZE) {
            RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
		MEMMOVE(ptr, ptr+1, VALUE, len-1);
	    }); /* WB: no new reference */
            ARY_INCREASE_LEN(ary, -1);
            ary_verify(ary);
	    return top;
	}
        assert(!ARY_EMBED_P(ary)); /* ARY_EMBED_LEN_MAX < ARY_DEFAULT_SIZE */

	ARY_SET(ary, 0, Qnil);
	ary_make_shared(ary);
    }
    else if (ARY_SHARED_ROOT_OCCUPIED(ARY_SHARED_ROOT(ary))) {
        RARRAY_PTR_USE_TRANSIENT(ary, ptr, ptr[0] = Qnil);
    }
    ARY_INCREASE_PTR(ary, 1);		/* shift ptr */
    ARY_INCREASE_LEN(ary, -1);

    ary_verify(ary);

    return top;
}

/*
 *  call-seq:
 *     array.shift -> object or nil
 *     array.shift(n) -> new_array
 *
 *  Removes and returns leading elements.
 *
 *  See also:
 *  - #push:  Appends trailing elements.
 *  - #pop:  Removes and returns trailing elements.
 *  - #unshift:  Prepends leading elements.
 *
 *  Argument +n+, if given, must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects]
 *
 *  ---
 *
 *  When no argument is given, removes and returns the first element:
 *    a = [:foo, 'bar', 2]
 *    a.shift # => :foo
 *    a # => ['bar', 2]
 *
 *  Returns +nil+ if +self+ is empty:
 *    [].shift # => nil
 *
 *  ---
 *
 *  When argument +n+ is given, removes the first +n+ elements;
 *  returns those elements in a new \Array:
 *    a = [:foo, 'bar', 2]
 *    a.shift(2) # => [:foo, 'bar']
 *    a # => [2]
 *
 *  If +n+ is as large as or larger than <tt>self.length</tt>,
 *  removes all elements; returns those elements in a new \Array:
 *    a = [:foo, 'bar', 2]
 *    a.shift(3) # => [:foo, 'bar', 2]
 *    a # => []
 *
 *  If +n+ is zero, returns a new empty \Array; +self+ is unmodified:
 *    a = [:foo, 'bar', 2]
 *    a.shift(0) # => []
 *    a # => [:foo, 'bar', 2]
 *
 *  ---
 *
 *  Raises an exception if +n+ is negative:
 *    a = [:foo, 'bar', 2]
 *    # Raises ArgumentError (negative array size):
 *    a1 = a.shift(-1)
 *
 *  Raises an exception if +n+ is not an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects]:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.shift(:foo)
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

static VALUE
behead_shared(VALUE ary, long n)
{
    assert(ARY_SHARED_P(ary));
    rb_ary_modify_check(ary);
    if (ARY_SHARED_ROOT_OCCUPIED(ARY_SHARED_ROOT(ary))) {
        ary_mem_clear(ary, 0, n);
    }
    ARY_INCREASE_PTR(ary, n);
    ARY_INCREASE_LEN(ary, -n);
    ary_verify(ary);
    return ary;
}

static VALUE
behead_transient(VALUE ary, long n)
{
    rb_ary_modify_check(ary);
    RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
        MEMMOVE(ptr, ptr+n, VALUE, RARRAY_LEN(ary)-n);
    }); /* WB: no new reference */
    ARY_INCREASE_LEN(ary, -n);
    ary_verify(ary);
    return ary;
}

MJIT_FUNC_EXPORTED VALUE
rb_ary_behead(VALUE ary, long n)
{
    if (n <= 0) {
        return ary;
    }
    else if (ARY_SHARED_P(ary)) {
        return behead_shared(ary, n);
    }
    else if (RARRAY_LEN(ary) >= ARY_DEFAULT_SIZE) {
        ary_make_shared(ary);
        return behead_shared(ary, n);
    }
    else {
        return behead_transient(ary, n);
    }
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
    assert(ARY_SHARED_ROOT_OCCUPIED(ARY_SHARED_ROOT(ary)));

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
    if (new_len > ARY_DEFAULT_SIZE * 4) {
        ary_verify(ary);

        /* make a room for unshifted items */
	capa = ARY_CAPA(ary);
	ary_make_shared(ary);

        head = sharedp = RARRAY_CONST_PTR_TRANSIENT(ary);
        return make_room_for_unshift(ary, head, (void *)sharedp, argc, capa, len);
    }
    else {
	/* sliding items */
        RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
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
            const VALUE * head = RARRAY_CONST_PTR_TRANSIENT(ary);
            void *sharedp = (void *)RARRAY_CONST_PTR_TRANSIENT(shared_root);

            rb_ary_modify_check(ary);
            return make_room_for_unshift(ary, head, sharedp, argc, capa, len);
        }
    }
}

/*
 *  call-seq:
 *    array.unshift(*objects) -> self
 *    array.prepend(*objects) -> self
 *
 *  Array#prepend is an alias for Array#unshift.
 *
 *  Prepends leading elements.
 *
 *  See also:
 *  - #push:  Appends trailing elements.
 *  - #pop:  Removes and returns trailing elements.
 *  - #shift:  Removes and returns leading elements.
 *
 *  Prepends the given +objects+ to +self+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.unshift(:bam, :bat)
 *    a1 # => [:bam, :bat, :foo, "bar", 2]
 *    a1.equal?(a) # => true # Returned self
 */

static VALUE
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
    return rb_ary_unshift_m(1,&item,ary);
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
rb_ary_subseq(VALUE ary, long beg, long len)
{
    VALUE klass;
    long alen = RARRAY_LEN(ary);

    if (beg > alen) return Qnil;
    if (beg < 0 || len < 0) return Qnil;

    if (alen < len || alen < beg + len) {
	len = alen - beg;
    }
    klass = rb_obj_class(ary);
    if (len == 0) return ary_new(klass, 0);

    return ary_make_partial(ary, klass, beg, len);
}

static VALUE rb_ary_aref2(VALUE ary, VALUE b, VALUE e);

/*
 *  call-seq:
 *    array[index] -> object or nil
 *    array[start, length] -> object or nil
 *    array[range] -> object or nil
 *    array.slice(index) -> object or nil
 *    array.slice(start, length) -> object or nil
 *    array.slice(range) -> object or nil
 *
 *  Returns elements from +self+; does not modify +self+.
 *
 *  - Arguments +index+, +start+, and +length+, if given, must be
 *    {Integer-convertible objects}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *  - Argument +range+, if given, must be a \Range object.
 *
 *  ---
 *
 *  When a single argument +index+ is given, returns the element at offset +index+:
 *    a = [:foo, 'bar', 2]
 *    a[0] # => :foo
 *    a[2] # => 2
 *    a # => [:foo, "bar", 2]
 *
 *  If +index+ is negative, counts relative to the end of +self+:
 *    a = [:foo, 'bar', 2]
 *    a[-1] # => 2
 *    a[-2] # => "bar"
 *
 *  If +index+ is out of range, returns +nil+:
 *    a = [:foo, 'bar', 2]
 *    a[50] # => nil
 *    a[-50] # => nil
 *
 *  ---
 *
 *  When two arguments +start+ and +length+ are given,
 *  returns a new \Array of size +length+ containing successive elements beginning at offset +start+:
 *    a = [:foo, 'bar', 2]
 *    a[0, 2] # => [:foo, "bar"]
 *    a[1, 2] # => ["bar", 2]
 *
 *  If <tt>start + length</tt> is greater than <tt>self.length</tt>,
 *  returns all elements from offset +start+ to the end:
 *    a = [:foo, 'bar', 2]
 *    a[0, 4] # => [:foo, "bar", 2]
 *    a[1, 3] # => ["bar", 2]
 *    a[2, 2] # => [2]
 *
 *  If <tt>start == self.size</tt> and <tt>length >= 0</tt>,
 *  returns a new empty \Array:
 *    a = [:foo, 'bar', 2]
 *    a[a.size, 0] # => []
 *    a[a.size, 50] # => []
 *
 *  If +length+ is negative, returns +nil+:
 *    a = [:foo, 'bar', 2]
 *    a[2, -1] # => nil
 *    a[1, -2] # => nil
 *
 *  ---
 *
 *  When a single argument +range+ is given,
 *  treats <tt>range.min</tt> as +start+ above
 *  and <tt>range.size</tt> as +length+ above:
 *    a = [:foo, 'bar', 2]
 *    a[0..1] # => [:foo, "bar"]
 *    a[1..2] # => ["bar", 2]
 *
 *  Special case: If <tt>range.start == a.size</tt>, returns a new empty \Array:
 *    a = [:foo, 'bar', 2]
 *    a[a.size..0] # => []
 *    a[a.size..50] # => []
 *    a[a.size..-1] # => []
 *    a[a.size..-50] # => []
 *
 *  If <tt>range.end</tt> is negative, calculates the end index from the end:
 *    a = [:foo, 'bar', 2]
 *    a[0..-1] # => [:foo, "bar", 2]
 *    a[0..-2] # => [:foo, "bar"]
 *    a[0..-3] # => [:foo]
 *    a[0..-4] # => []
 *
 *  If <tt>range.start</tt> is negative, calculates the start index from the end:
 *    a = [:foo, 'bar', 2]
 *    a[-1..2] # => [2]
 *    a[-2..2] # => ["bar", 2]
 *    a[-3..2] # => [:foo, "bar", 2]
 *
 *  If <tt>range.start</tt> is larger than the array size, returns +nil+:
 *    a = [:foo, 'bar', 2]
 *    a[4..1] # => nil
 *    a[4..0] # => nil
 *    a[4..-1] # => nil
 *
 *  ---
 *
 *  Raises an exception if given a single argument
 *  that is not an \Integer-convertible object or a \Range object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a[:foo]
 *
 *  Raises an exception if given two arguments that are not both \Integer-convertible objects:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a[:foo, 3]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a[1, :bar]
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

MJIT_FUNC_EXPORTED VALUE
rb_ary_aref1(VALUE ary, VALUE arg)
{
    long beg, len;

    /* special case - speeding up */
    if (FIXNUM_P(arg)) {
	return rb_ary_entry(ary, FIX2LONG(arg));
    }
    /* check if idx is Range */
    switch (rb_range_beg_len(arg, &beg, &len, RARRAY_LEN(ary), 0)) {
      case Qfalse:
	break;
      case Qnil:
	return Qnil;
      default:
	return rb_ary_subseq(ary, beg, len);
    }
    return rb_ary_entry(ary, NUM2LONG(arg));
}

/*
 *  call-seq:
 *    array.at(index) -> object
 *
 *  Argument +index+ must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  Returns the element at offset +index+; does not modify +self+.
 *    a = [:foo, 'bar', 2]
 *    a.at(0) # => :foo
 *    a.at(2) # => 2
 *
 *  ---
 *
 *  Raises an exception if +index+ is not an \Integer-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.at(:foo)
 */

VALUE
rb_ary_at(VALUE ary, VALUE pos)
{
    return rb_ary_entry(ary, NUM2LONG(pos));
}

/*
 *  call-seq:
 *    array.first -> object or nil
 *    array.first(n) -> new_array
 *
 *  Returns elements from +self+; does not modify +self+.
 *  See also #last.
 *
 *  Argument +n+, if given, must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  ---
 *
 *  When no argument is given, returns the first element:
 *    a = [:foo, 'bar', 2]
 *    a.first # => :foo
 *    a # => [:foo, "bar", 2]
 *
 *  If +self+ is empty, returns +nil+:
 *    [].first # => nil
 *
 *  ---
 *
 *  When argument +n+ is given, returns the first +n+ elements in a new \Array:
 *    a = [:foo, 'bar', 2]
 *    a.first(2) # => [:foo, "bar"]
 *
 *  If <tt>n >= ary.size</tt>, returns all elements:
 *    a = [:foo, 'bar', 2]
 *    a.first(50) # => [:foo, "bar", 2]
 *
 *  If <tt>n == 0</tt> returns an new empty \Array:
 *    a = [:foo, 'bar', 2]
 *    a.first(0) # []
 *
 *  ---
 *
 *  Raises an exception if +n+ is negative:
 *    a = [:foo, 'bar', 2]
 *    # Raises ArgumentError (negative array size):
 *    a.first(-1)
 *
 *  Raises an exception if +n+ is not an \Integer-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of String into Integer):
 *    a.first(:X)
 */
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

/*
 *  call-seq:
 *    array.last  -> object or nil
 *    array.last(n) -> new_array
 *
 *  Returns elements from +self+; +self+ is not modified.
 *  See also #first.
 *
 *  Argument +n+, if given, must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  ---
 *
 *  When no argument is given, returns the last element:
 *    a = [:foo, 'bar', 2]
 *    a.last # => 2
 *    a # => [:foo, "bar", 2]
 *
 *  If +self+ is empty, returns +nil+:
 *    [].last # => nil
 *
 *  ---
 *
 *  When argument +n+ is given, returns the last +n+ elements in a new \Array:
 *    a = [:foo, 'bar', 2]
 *    a.last(2) # => ["bar", 2]
 *
 *  If <tt>n >= ary.size</tt>, returns all elements:
 *    a = [:foo, 'bar', 2]
 *    a.last(50) # => [:foo, "bar", 2]
 *
 *  If <tt>n == 0</tt>, returns an new empty \Array:
 *    a = [:foo, 'bar', 2]
 *    a.last(0) # []
 *
 *  ---
 *
 *  Raises an exception if +n+ is negative:
 *    a = [:foo, 'bar', 2]
 *    # Raises ArgumentError (negative array size):
 *    a.last(-1)
 *
 *  Raises an exception if +n+ is not an \Integer-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.last(:X)
 */

VALUE
rb_ary_last(int argc, const VALUE *argv, VALUE ary)
{
    if (argc == 0) {
	long len = RARRAY_LEN(ary);
	if (len == 0) return Qnil;
	return RARRAY_AREF(ary, len-1);
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
 *  Argument +index+ must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects]
 *
 *  ---
 *
 *  With the single argument +index+, returns the element at offset +index+:
 *    a = [:foo, 'bar', 2]
 *    a.fetch(1) # => "bar"
 *
 *  If +index+ is negative, counts from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a.fetch(-1) # => 2
 *    a.fetch(-2) # => "bar"
 *
 *  ---
 *
 *  With arguments +index+ and +default_value+,
 *  returns the element at offset +index+ if index is in range,
 *  otherwise returns +default_value+:
 *    a = [:foo, 'bar', 2]
 *    a.fetch(1, nil) # => "bar"
 *    a.fetch(50, nil) # => nil
 *
 *  ---
 *
 *  With argument +index+ and a block,
 *  returns the element at offset +index+ if index is in range
 *  (and the block is not called); otherwise calls the block with index and returns its return value:
 *
 *    a = [:foo, 'bar', 2]
 *    a.fetch(1) { |index| raise 'Cannot happen' } # => "bar"
 *    a.fetch(50) { |index| "Value for #{index}" } # => "Value for 50"
 *
 *  ---
 *
 *  Raises an exception if +index+ is not an \Integer-convertible object.
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.fetch(:foo)
 *
 *  Raises an exception if +index+ is out of range and neither default_value nor a block given:
 *    a = [:foo, 'bar', 2]
 *    # Raises IndexError (index 50 outside of array bounds: -3...3):
 *    a.fetch(50)
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
 *    array.find_index(object) -> integer or nil
 *    array.find_index {|element| ... } -> integer or nil
 *    array.find_index -> new_enumerator
 *
 *  Array#find_index is an alias for Array#index.
 *  See also Array#rindex.
 *
 *  Returns the index of a specified element.
 *
 *  ---
 *
 *  When argument +object+ is given but no block,
 *  returns the index of the first element +element+
 *  for which <tt>object == element</tt>:
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.index('bar') # => 1
 *
 *  Returns +nil+ if no such element found:
 *    a = [:foo, 'bar', 2]
 *    a.index(:nosuch) # => nil
 *
 *  ---
 *
 *  When both argument +object+ and a block are given,
 *  calls the block with each successive element;
 *  returns the index of the first element for which the block returns a truthy value:
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.index { |element| element == 'bar' } # => 1
 *
 *  Returns +nil+ if the block never returns a truthy value:
 *    a = [:foo, 'bar', 2]
 *    a.index { |element| element == :X } # => nil
 *
 *  ---
 *
 *  When neither an argument nor a block is given, returns a new Enumerator:
 *    a = [:foo, 'bar', 2]
 *    e = a.index
 *    e # => #<Enumerator: [:foo, "bar", 2]:index>
 *    e.each { |element| element == 'bar' } # => 1
 *
 *  ---
 *
 *  When both an argument and a block given, gives a warning (warning: given block not used)
 *  and ignores the block:
 *    a = [:foo, 'bar', 2, 'bar']
 *    index = a.index('bar') { raise 'Cannot happen' }
 *    index # => 1
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
 *  ---
 *
 *  When argument +object+ is given but no block, returns the index of the last such element found:
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.rindex('bar') # => 3
 *
 *  Returns +nil+ if no such object found:
 *    a = [:foo, 'bar', 2]
 *    a.rindex(:nosuch) # => nil
 *
 *  ---
 *
 *  When a block is given but no argument, calls the block with each successive element;
 *  returns the index of the last element for which the block returns a truthy value:
 *    a = [:foo, 'bar', 2, 'bar']
 *    a.rindex {|element| element == 'bar' } # => 3
 *
 *  Returns +nil+ if the block never returns a truthy value:
 *
 *    a = [:foo, 'bar', 2]
 *    a.rindex {|element| element == :X } # => nil
 *
 *  ---
 *
 *  When neither an argument nor a block is given, returns a new \Enumerator:
 *
 *    a = [:foo, 'bar', 2, 'bar']
 *    e = a.rindex
 *    e # => #<Enumerator: [:foo, "bar", 2, "bar"]:rindex>
 *    e.each { |element| element == 'bar' } # => 3
 *
 *  ---
 *
 *  When both an argument and a block given, gives a warning (warning: given block not used)
 *  and ignores the block:
 *    a = [:foo, 'bar', 2, 'bar']
 *    index = a.rindex('bar') { raise 'Cannot happen' }
 *    index # => 3
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
        const VALUE *optr = RARRAY_CONST_PTR_TRANSIENT(ary);
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
            if (rofs != -1) rptr = RARRAY_CONST_PTR_TRANSIENT(ary) + rofs;
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
            RARRAY_PTR_USE_TRANSIENT(ary, ptr,
                                     MEMMOVE(ptr + beg + rlen, ptr + beg + len,
                                             VALUE, olen - (beg + len)));
	    ARY_SET_LEN(ary, alen);
	}
	if (rlen > 0) {
            if (rofs != -1) rptr = RARRAY_CONST_PTR_TRANSIENT(ary) + rofs;
            /* give up wb-protected ary */
            RB_OBJ_WB_UNPROTECT_FOR(ARRAY, ary);

            /* do not use RARRAY_PTR() because it can causes GC.
             * ary can contain T_NONE object because it is not cleared.
             */
            RARRAY_PTR_USE_TRANSIENT(ary, ptr,
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

/*!
 * expands or shrinks \a ary to \a len elements.
 * expanded region will be filled with Qnil.
 * \param ary  an array
 * \param len  new size
 * \return     \a ary
 * \post       the size of \a ary is \a len.
 */
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
    else if (len <= RARRAY_EMBED_LEN_MAX) {
	VALUE tmp[RARRAY_EMBED_LEN_MAX];
	MEMCPY(tmp, ARY_HEAP_PTR(ary), VALUE, len);
	ary_discard(ary);
	MEMCPY((VALUE *)ARY_EMBED_PTR(ary), tmp, VALUE, len); /* WB: no new reference */
        ARY_SET_EMBED_LEN(ary, len);
    }
    else {
	if (olen > len + ARY_DEFAULT_SIZE) {
            ary_heap_realloc(ary, len);
	    ARY_SET_CAPA(ary, len);
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
    rb_ary_splice(ary, beg, len, RARRAY_CONST_PTR_TRANSIENT(rpl), RARRAY_LEN(rpl));
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
 *  - Arguments +index+, +start+, and +length+, if given, must be
 *    {Integer-convertible objects}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *  - Argument +range+, if given, must be a \Range object.
 *  - If +object+ is an
 *    {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects]
 *    it will be converted to an \Array.
 *
 *  ---
 *
 *  When +index+ is given, assigns +object+ to an element in +self+.
 *
 *  If +index+ is non-negative, assigns +object+ the element at offset +index+:
 *    a = [:foo, 'bar', 2]
 *    a[0] = 'foo' # => "foo"
 *    a # => ["foo", "bar", 2]
 *
 *  If +index+ is greater than <tt>self.length</tt>, extends the array:
 *    a = [:foo, 'bar', 2]
 *    a[7] = 'foo' # => "foo"
 *    a # => [:foo, "bar", 2, nil, nil, nil, nil, "foo"]
 *
 *  If +index+ is negative, counts backwards from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a[-1] = 'two' # => "two"
 *    a # => [:foo, "bar", "two"]
 *
 *  ---
 *
 *  When +start+ and +length+ are given and +object+ is not an Array-convertible object,
 *  removes <tt>length - 1</tt> elements beginning at offset +start+,
 *  and assigns +object+ at offset +start+:
 *    a = [:foo, 'bar', 2]
 *    a[0, 2] = 'foo' # => "foo"
 *    a # => ["foo", 2]
 *
 *  If +start+ is negative, counts backwards from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a[-2, 2] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 *  If +start+ is non-negative and outside the array (<tt> >= self.size</tt>),
 *  extends the array with +nil+, assigns +object+ at offset +start+,
 *  and ignores +length+:
 *    a = [:foo, 'bar', 2]
 *    a[6, 50] = 'foo' # => "foo"
 *    a # => [:foo, "bar", 2, nil, nil, nil, "foo"]
 *
 *  If +length+ is zero, shifts elements at and following offset +start+
 *  and assigns +object+ at offset +start+:
 *    a = [:foo, 'bar', 2]
 *    a[1, 0] = 'foo' # => "foo"
 *    a # => [:foo, "foo", "bar", 2]
 *
 *  If +length+ is too large for the existing array, does not extend the array:
 *    a = [:foo, 'bar', 2]
 *    a[1, 5] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 *  ---
 *
 *  When +range+ is given and +object+ is an \Array-convertible object,
 *  removes <tt>length - 1</tt> elements beginning at offset +start+,
 *  and assigns +object+ at offset +start+:
 *    a = [:foo, 'bar', 2]
 *    a[0..1] = 'foo' # => "foo"
 *    a # => ["foo", 2]
 *
 *  if <tt>range.begin</tt> is negative, counts backwards from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a[-2..2] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 *  If the array length is less than <tt>range.begin</tt>,
 *  assigns +object+ at offset <tt>range.begin</tt>, and ignores +length+:
 *    a = [:foo, 'bar', 2]
 *    a[6..50] = 'foo' # => "foo"
 *    a # => [:foo, "bar", 2, nil, nil, nil, "foo"]
 *
 *  If <tt>range.end</tt> is zero, shifts elements at and following offset +start+
 *  and assigns +object+ at offset +start+:
 *    a = [:foo, 'bar', 2]
 *    a[1..0] = 'foo' # => "foo"
 *    a # => [:foo, "foo", "bar", 2]
 *
 *  If <tt>range.end</tt> is negative, assigns +object+ at offset +start+,
 *  retains <tt>range.end.abs -1</tt> elements past that, and removes those beyond:
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
 *    a = [:foo, 'bar', 2]
 *    a[1..5] = 'foo' # => "foo"
 *    a # => [:foo, "foo"]
 *
 *  ---
 *
 *  Raises an exception if given a single argument
 *  that is not an \Integer-convertible object or a \Range:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a[:nosuch] = 'two'
 *
 *  Raises an exception if given two arguments that are not both \Integer-convertible objects:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a[:nosuch, 2] = 'two'
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a[0, :nosuch] = 'two'
 *
 *  Raises an exception if a negative +index+ is out of range:
 *    a = [:foo, 'bar', 2]
 *    # Raises IndexError (index -4 too small for array; minimum: -3):
 *    a[-4] = 'two'
 *
 *  Raises an exception if +start+ is too small for the array:
 *    a = [:foo, 'bar', 2]
 *    # Raises IndexError (index -5 too small for array; minimum: -3):
 *    a[-5, 2] = 'foo'
 *
 *  Raises an exception if +length+ is negative:
 *    a = [:foo, 'bar', 2]
 *    # Raises IndexError (negative length (-1)):
 *    a[1, -1] = 'foo'
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
 *  Inserts given +objects+ before or after the element at +offset+ index;
 *  returns +self+.
 *
 *  Argument +index+ must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  ---
 *
 *  When +index+ is non-negative, inserts all given +objects+
 *  before the element at offset +index+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.insert(1, :bat, :bam)
 *    a # => [:foo, :bat, :bam, "bar", 2]
 *    a1.object_id == a.object_id # => true
 *
 *  Extends the array if +index+ is beyond the array (<tt>index >= self.size</tt>):
 *    a = [:foo, 'bar', 2]
 *    a.insert(5, :bat, :bam)
 *    a # => [:foo, "bar", 2, nil, nil, :bat, :bam]
 *
 *  Does nothing if no objects given:
 *    a = [:foo, 'bar', 2]
 *    a.insert(1)
 *    a.insert(50)
 *    a.insert(-50)
 *    a # => [:foo, "bar", 2]
 *
 *  ---
 *
 *  When +index+ is negative, inserts all given +objects+
 *  _after_ the element at offset <tt>index+self.size</tt>:
 *    a = [:foo, 'bar', 2]
 *    a.insert(-2, :bat, :bam)
 *    a # => [:foo, "bar", :bat, :bam, 2]
 *
 *  ---
 *
 *  Raises an exception if +index+ is not an Integer-convertible object:
 *    a = [:foo, 'bar', 2, 'bar']
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.insert(:foo)
 *
 *  Raises an exception if +index+ is too small (<tt>index+self.size < 0</tt>):
 *    a = [:foo, 'bar', 2]
 *    # Raises IndexError (index -5 too small for array; minimum: -4):
 *    a.insert(-5, :bat, :bam)
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

/*
 *  call-seq:
 *    array.each {|element| ... } -> self
 *    array.each -> Enumerator
 *
 *  Iterates over array elements.
 *
 *  ---
 *
 *  When a block given, passes each successive array element to the block;
 *  returns +self+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.each {|element|  puts "#{element.class} #{element}" }
 *    a1.equal?(a) # => true # Returned self
 *
 *  Output:
 *    Symbol foo
 *    String bar
 *    Integer 2
 *
 *  Allows the array to be modified during iteration:
 *    a = [:foo, 'bar', 2]
 *    a.each {|element| puts element; a.clear if element.to_s.start_with?('b') }
 *    a # => []
 *
 *  Output:
 *    foo
 *    bar
 *
 *  ---
 *
 *  When no block given, returns a new \Enumerator:
 *    a = [:foo, 'bar', 2]
 *    e = a.each
 *    e # => #<Enumerator: [:foo, "bar", 2]:each>
 *    a1 = e.each { |element|  puts "#{element.class} #{element}" }
 *
 *  Output:
 *    Symbol foo
 *    String bar
 *    Integer 2
 */

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
 *  ---
 *
 *  When a block given, passes each successive array index to the block;
 *  returns +self+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.each_index {|index|  puts "#{index} #{a[index]}" }
 *    a1.equal?(a) # => true # Returned self
 *
 *  Output:
 *    0 foo
 *    1 bar
 *    2 2
 *
 *  Allows the array to be modified during iteration:
 *    a = [:foo, 'bar', 2]
 *    a.each_index {|index| puts index; a.clear if index > 0 }
 *    a # => []
 *
 *  Output:
 *    0
 *    1
 *
 *  ---
 *
 *  When no block given, returns a new \Enumerator:
 *    a = [:foo, 'bar', 2]
 *    e = a.each_index
 *    e # => #<Enumerator: [:foo, "bar", 2]:each_index>
 *    a1 = e.each {|index|  puts "#{index} #{a[index]}"}
 *
 *  Output:
 *    0 foo
 *    1 bar
 *    2 2
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
 *  ---
 *
 *  When a block given, passes, in reverse order, each element to the block;
 *  returns +self+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.reverse_each {|element|  puts "#{element.class} #{element}" }
 *    a1.equal?(a) # => true # Returned self
 *
 *  Output:
 *    Integer 2
 *    String bar
 *    Symbol foo
 *
 *  Allows the array to be modified during iteration:
 *    a = [:foo, 'bar', 2]
 *    a.reverse_each {|element| puts element; a.clear if element.to_s.start_with?('b') }
 *    a # => []
 *
 *  Output:
 *    2
 *    bar
 *
 *  ---
 *
 *  When no block given, returns a new \Enumerator:
 *    a = [:foo, 'bar', 2]
 *    e = a.reverse_each
 *    e # => #<Enumerator: [:foo, "bar", 2]:reverse_each>
 *    a1 = e.each { |element|  puts "#{element.class} #{element}" }
 *  Output:
 *    Integer 2
 *    String bar
 *    Symbol foo
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
 *  Returns the count of elements in the array:
 *    a = [:foo, 'bar', 2]
 *    a.length # => 3
 *    [].length # => 0
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
 *  Returns +true+ if the count of elements in the array is zero,
 *  +false+ otherwise:
 *    [].empty? # => true
 *    [:foo, 'bar', 2].empty? # => false
 */

static VALUE
rb_ary_empty_p(VALUE ary)
{
    if (RARRAY_LEN(ary) == 0)
	return Qtrue;
    return Qfalse;
}

VALUE
rb_ary_dup(VALUE ary)
{
    long len = RARRAY_LEN(ary);
    VALUE dup = rb_ary_new2(len);
    ary_memcpy(dup, 0, len, RARRAY_CONST_PTR_TRANSIENT(ary));
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
 *  Returns the new \String formed by joining the array elements after conversion.
 *  For each element +element+
 *  - Uses <tt>element.to_s</tt> if +element+ is not a <tt>kind_of?(Array)</tt>.
 *  - Uses recursive <tt>element.join(separator)</tt> if +element+ is a <tt>kind_of?(Array)</tt>.
 *
 *  Argument +separator+, if given, must be a
 *  {String-convertible object}[doc/implicit_conversion_rdoc.html#label-String-Convertible+Objects].
 *
 *  ---
 *
 *  With no argument, joins using the output field separator, <tt>$,</tt>:
 *    a = [:foo, 'bar', 2]
 *    $, # => nil
 *    a.join # => "foobar2"
 *
 *  With argument +separator+, joins using that separator:
 *    a = [:foo, 'bar', 2]
 *    a.join("\n") # => "foo\nbar\n2"
 *
 *  ---
 *
 *  Joins recursively for nested Arrays:
 *   a = [:foo, [:bar, [:baz, :bat]]]
 *   a.join # => "foobarbazbat"
 *
 *  ---
 *
 *  Raises an exception if +separator+ is not a String-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into String):
 *    a.join(:foo)
 *
 *  Raises an exception if any element lacks instance method +#to_s+:
 *    a = [:foo, 'bar', 2, BasicObject.new]
 *    # Raises NoMethodError (undefined method `to_s' for #<BasicObject>):
 *    a.join
 */
static VALUE
rb_ary_join_m(int argc, VALUE *argv, VALUE ary)
{
    VALUE sep;

    if (rb_check_arity(argc, 0, 1) == 0 || NIL_P(sep = argv[0])) {
        sep = rb_output_fs;
        if (!NIL_P(sep)) {
            rb_warn("$, is set to non-nil value");
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
 *    array.to_s => new_string
 *
 *  Array#to_s is an alias for Array#inspect.
 *
 *  Returns the new \String formed by calling method <tt>#inspect</tt>
 *  on each array element:
 *    a = [:foo, 'bar', 2]
 *    a.inspect # => "[:foo, \"bar\", 2]"
 *
 *  Raises an exception if any element lacks instance method <tt>#inspect</tt>:
 *    a = [:foo, 'bar', 2, BasicObject.new]
 *    a.inspect
 *    # Raises NoMethodError (undefined method `inspect' for #<BasicObject>)
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
 *  When +self+ is an instance of \Array, returns +self+:
 *    a = [:foo, 'bar', 2]
 *    a.instance_of?(Array) # => true
 *    a1 = a.to_a
 *    a1.equal?(a) # => true # Returned self
 *
 *  Otherwise, returns a new \Array containing the elements of +self+:
 *    class MyArray < Array; end
 *    a = MyArray.new(['foo', 'bar', 'two'])
 *    a.instance_of?(Array) # => false
 *    a.kind_of?(Array) # => true
 *    a1 = a.to_a
 *    a1 # => ["foo", "bar", "two"]
 *    a1.class # => Array # Not MyArray
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
 *  Returns a new \Hash formed from +self+.
 *
 *  When a block is given, calls the block with each array element;
 *  the block must return a 2-element \Array whose two elements
 *  form a key-value pair in the returned \Hash:
 *    a = ['foo', :bar, 1, [2, 3], {baz: 4}]
 *    h = a.to_h {|item| [item, item] }
 *    h # => {"foo"=>"foo", :bar=>:bar, 1=>1, [2, 3]=>[2, 3], {:baz=>4}=>{:baz=>4}}
 *
 *  When no block is given, +self+ must be an \Array of 2-element sub-arrays,
 *  each sub-array is formed into a key-value pair in the new \Hash:
 *    [].to_h # => {}
 *    a = [['foo', 'zero'], ['bar', 'one'], ['baz', 'two']]
 *    h = a.to_h
 *    h # => {"foo"=>"zero", "bar"=>"one", "baz"=>"two"}
 *
 *  ---
 *
 *  Raises an exception if no block is given
 *  and any element in +self+ is not a 2-element \Array:
 *    # Raises TypeError (wrong element type Symbol at 0 (expected array):
 *    [:foo].to_h
 *    # Raises ArgumentError (wrong array length at 0 (expected 2, was 1)):
 *    [[:foo]].to_h
 *
 *  Raises an exception if for some 2-element \Array +element+ in +self+,
 *  <tt>element.first</tt> would be an invalid hash key:
 *    # Raises NoMethodError (undefined method `hash' for #<BasicObject:>):
 *    [[BasicObject.new, 0]].to_h
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
 *  Returns +self+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.to_ary
 *    a1.equal?(a) # => true # Returned self
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
        RARRAY_PTR_USE_TRANSIENT(ary, p1, {
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
 *    a = ['foo', 'bar', 'two']
 *    a1 = a.reverse!
 *    a1 # => ["two", "bar", "foo"]
 *    a1.equal?(a) # => true # Returned self
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
 *  Returns a new \Array whose elements are in reverse order:
 *    a = ['foo', 'bar', 'two']
 *    a1 = a.reverse
 *    a1 # => ["two", "bar", "foo"]
 */

static VALUE
rb_ary_reverse_m(VALUE ary)
{
    long len = RARRAY_LEN(ary);
    VALUE dup = rb_ary_new2(len);

    if (len > 0) {
        const VALUE *p1 = RARRAY_CONST_PTR_TRANSIENT(ary);
        VALUE *p2 = (VALUE *)RARRAY_CONST_PTR_TRANSIENT(dup) + len - 1;
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
    } else if (cnt == len - 1) {
        VALUE tmp = *(ptr + len - 1);
        memmove(ptr + 1, ptr, sizeof(VALUE)*(len - 1));
        *ptr = tmp;
    } else {
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
            RARRAY_PTR_USE_TRANSIENT(ary, ptr, ary_rotate_ptr(ptr, len, cnt));
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
 *  Argument +count+, if given, must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  ---
 *
 *  When no argument given, rotates the first element to the last position:
 *    a = [:foo, 'bar', 2, 'bar']
 *    a1 = a.rotate!
 *    a1 # => ["bar", 2, "bar", :foo]
 *    a1.equal?(a1) # => true # Retruned self
 *
 *  ---
 *
 *  When given a non-negative +count+, rotates +count+ elements from the beginning to the end:
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(2)
 *    a # => [2, :foo, "bar"]
 *
 *  If +count+ is large, uses <tt>count % ary.size</tt> as the count:
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(20)
 *    a # => [2, :foo, "bar"]
 *
 *  If +count+ is zero, returns +self+ unmodified:
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(0)
 *    a # => [:foo, "bar", 2]
 *
 *  ---
 *
 *  When given a negative +count+, rotates in the opposite direction,
 *  from end to beginning:
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(-2)
 *    a # => ["bar", 2, :foo]
 *
 *  If +count+ is small (far from zero), uses <tt>count % ary.size</tt> as the count:
 *    a = [:foo, 'bar', 2]
 *    a.rotate!(-5)
 *    a # => ["bar", 2, :foo]
 *
 *  ---
 *
 *  Raises an exception if +count+ is not an Integer-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a1 = a.rotate!(:foo)
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
 *  Returns a new \Array formed from +self+ with elements
 *  rotated from one end to the other.
 *
 *  Argument +count+, if given, must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  ---
 *  When no argument given, returns a new \Array that is like +self+,
 *  except that the first element has been rotated to the last position:
 *    a = [:foo, 'bar', 2, 'bar']
 *    a1 = a.rotate
 *    a1 # => ["bar", 2, "bar", :foo]
 *
 *  ---
 *
 *  When given a non-negative +count+,
 *  returns a new \Array with +count+ elements rotated from the beginning to the end:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(2)
 *    a1 # => [2, :foo, "bar"]
 *
 *  If +count+ is large, uses <tt>count % ary.size</tt> as the count:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(20)
 *    a1 # => [2, :foo, "bar"]
 *
 *  If +count+ is zero, returns a copy of +self+, unmodified:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(0)
 *    a1 # => [:foo, "bar", 2]
 *
 *  ---
 *
 *  When given a negative +count+, rotates in the opposite direction,
 *  from end to beginning:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(-2)
 *    a1 # => ["bar", 2, :foo]
 *
 *  If +count+ is small (far from zero), uses <tt>count % ary.size</tt> as the count:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.rotate(-5)
 *    a1 # => ["bar", 2, :foo]
 *
 *  ---
 *
 *  Raises an exception if +count+ is not an Integer-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a1 = a.rotate(:foo)
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
        ptr = RARRAY_CONST_PTR_TRANSIENT(ary);
	len -= cnt;
	ary_memcpy(rotated, 0, len, ptr + cnt);
	ary_memcpy(rotated, len, cnt, ptr);
    }
    ARY_SET_LEN(rotated, RARRAY_LEN(ary));
    return rotated;
}

struct ary_sort_data {
    VALUE ary;
    struct cmp_opt_data cmp_opt;
};

static VALUE
sort_reentered(VALUE ary)
{
    if (RBASIC(ary)->klass) {
	rb_raise(rb_eRuntimeError, "sort reentered");
    }
    return Qnil;
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
    sort_reentered(data->ary);
    return n;
}

static int
sort_2(const void *ap, const void *bp, void *dummy)
{
    struct ary_sort_data *data = dummy;
    VALUE retval = sort_reentered(data->ary);
    VALUE a = *(const VALUE *)ap, b = *(const VALUE *)bp;
    int n;

    if (FIXNUM_P(a) && FIXNUM_P(b) && CMP_OPTIMIZABLE(data->cmp_opt, Integer)) {
	if ((long)a > (long)b) return 1;
	if ((long)a < (long)b) return -1;
	return 0;
    }
    if (STRING_P(a) && STRING_P(b) && CMP_OPTIMIZABLE(data->cmp_opt, String)) {
	return rb_str_cmp(a, b);
    }
    if (RB_FLOAT_TYPE_P(a) && CMP_OPTIMIZABLE(data->cmp_opt, Float)) {
	return rb_float_cmp(a, b);
    }

    retval = rb_funcallv(a, id_cmp, 1, &b);
    n = rb_cmpint(retval, a, b);
    sort_reentered(data->ary);

    return n;
}

/*
 *  call-seq:
 *    array.sort! -> self
 *    array.sort! {|a, b| ... } -> self
 *
 *  Returns +self+ with its elements sorted in place.
 *
 *  ---
 *
 *  With no block, compares elements using operator <tt><=></tt>
 *  (see Comparable):
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a.sort!
 *    a # => ["a", "b", "c", "d", "e"]
 *
 *  ---
 *
 *  With a block, calls the block with each element pair;
 *  for each element pair +a+ and +b+, the block should return an integer:
 *  - Negative when +b+ is to follow +a+.
 *  - Zero when +a+ and +b+ are equivalent.
 *  - Positive when +a+ is to follow +b+.
 *
 *  Example:
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a.sort! {|a, b| a <=> b }
 *    a # => ["a", "b", "c", "d", "e"]
 *    a.sort! {|a, b| b <=> a }
 *    a # => ["e", "d", "c", "b", "a"]
 *
 *  When the block returns zero, the order for +a+ and +b+ is indeterminate,
 *  and may be unstable:
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a.sort! {|a, b| 0 }
 *    a # => ["d", "e", "c", "a", "b"]
 *
 *  ---
 *
 *  Raises an exception if the block returns a non-Integer:
 *    a = 'abcde'.split('').shuffle
 *    # Raises ArgumentError (comparison of Symbol with 0 failed):
 *    a1 = a.sort! {|a, b| :foo }
 */

VALUE
rb_ary_sort_bang(VALUE ary)
{
    rb_ary_modify(ary);
    assert(!ARY_SHARED_P(ary));
    if (RARRAY_LEN(ary) > 1) {
	VALUE tmp = ary_make_substitution(ary); /* only ary refers tmp */
	struct ary_sort_data data;
	long len = RARRAY_LEN(ary);
	RBASIC_CLEAR_CLASS(tmp);
	data.ary = tmp;
	data.cmp_opt.opt_methods = 0;
	data.cmp_opt.opt_inited = 0;
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
	    ary_memcpy(ary, 0, ARY_EMBED_LEN(tmp), ARY_EMBED_PTR(tmp));
            ARY_SET_LEN(ary, ARY_EMBED_LEN(tmp));
        }
        else {
            if (!ARY_EMBED_P(ary) && ARY_HEAP_PTR(ary) == ARY_HEAP_PTR(tmp)) {
                FL_UNSET_SHARED(ary);
                ARY_SET_CAPA(ary, RARRAY_LEN(tmp));
            }
            else {
                assert(!ARY_SHARED_P(tmp));
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
 *  Returns a new \Array whose elements are those from +self+, sorted.
 *
 *  See also Enumerable#sort_by.
 *
 *  ---
 *
 *  With no block, compares elements using operator <tt><=></tt>
 *  (see Comparable):
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a1 = a.sort
 *    a1 # => ["a", "b", "c", "d", "e"]
 *
 *  ---
 *
 *  With a block, calls the block with each element pair;
 *  for each element pair +a+ and +b+, the block should return an integer:
 *  - Negative when +b+ is to follow +a+.
 *  - Zero when +a+ and +b+ are equivalent.
 *  - Positive when +a+ is to follow +b+.
 *
 *  Example:
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a1 = a.sort {|a, b| a <=> b }
 *    a1 # => ["a", "b", "c", "d", "e"]
 *    a2 = a.sort {|a, b| b <=> a }
 *    a2 # => ["e", "d", "c", "b", "a"]
 *
 *  When the block returns zero, the order for +a+ and +b+ is indeterminate,
 *  and may be unstable:
 *    a = 'abcde'.split('').shuffle
 *    a # => ["e", "b", "d", "a", "c"]
 *    a1 = a.sort {|a, b| 0 }
 *    a1 # =>  ["c", "e", "b", "d", "a"]
 *
 *  ---
 *
 *  Raises an exception if the block returns a non-Integer:
 *    a = 'abcde'.split('').shuffle
 *    # Raises ArgumentError (comparison of Symbol with 0 failed):
 *    a1 = a.sort {|a, b| :foo }
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
 *  +self+ should be sorted, but this is not checked.
 *
 *  By using binary search, finds a value from this array which meets
 *  the given condition in <tt>O(log n)</tt> where +n+ is the size of the array.
 *
 *  There are two search modes:
 *  - <b>Find-minimum mode</b>: the block should return +true+ or +false+.
 *  - <b>Find-any mode</b>: the block should return a numeric value.
 *
 *  The block should not mix the modes by and sometimes returning +true+ or +false+
 *  and sometimes returning a numeric value, but this is not checked.
 *
 *  ====== Find-Minimum Mode
 *
 *  In find-minimum mode, the block always returns +true+ or +false+.
 *  The further requirement (though not checked) is that
 *  there are no indexes +i+ and +j+ such that:
 *  - <tt>0 <= i < j <= self.size</tt>.
 *  - The block returns +true+ for <tt>self[i]</tt> and +false+ for <tt>self[j]</tt>.
 *
 *  In find-minimum mode, method bsearch returns the first element for which the block returns true.
 *
 *  Examples:
 *    a = [0, 4, 7, 10, 12]
 *    a.bsearch {|x| x >= 4 } # => 4
 *    a.bsearch {|x| x >= 6 } # => 7
 *    a.bsearch {|x| x >= -1 } # => 0
 *    a.bsearch {|x| x >= 100 } # => nil
 *
 *  Less formally: the block is such that all +false+-evaluating elements
 *  precede all +true+-evaluating elements.
 *
 *  These make sense as blocks in find-minimum mode:
 *    a = [0, 4, 7, 10, 12]
 *    a.map {|x| x >= 4 } # => [false, true, true, true, true]
 *    a.map {|x| x >= 6 } # => [false, false, true, true, true]
 *    a.map {|x| x >= -1 } # => [true, true, true, true, true]
 *    a.map {|x| x >= 100 } # => [false, false, false, false, false]
 *
 *  This would not make sense:
 *    a = [0, 4, 7, 10, 12]
 *    a.map {|x| x == 7 } # => [false, false, true, false, false]
 *
 *  ====== Find-Any Mode
 *
 *  In find-any mode, the block always returns a numeric value.
 *  The further requirement (though not checked) is that
 *  there are no indexes +i+ and +j+ such that:
 *  - <tt>0 <= i < j <= self.size</tt>.
 *  - The block returns a negative value for <tt>self[i]</tt>
 *    and a positive value for <tt>self[j]</tt>.
 *  - The block returns a negative value for <tt>self[i]</tt> and zero <tt>self[j]</tt>.
 *  - The block returns zero for <tt>self[i]</tt> and a positive value for <tt>self[j]</tt>.
 *
 *  In find-any mode, method bsearch returns some element
 *  for which the block returns zero, or +nil+ if no such element is found.
 *
 *  Examples:
 *    a = [0, 4, 7, 10, 12]
 *    a.bsearch {|element| 7 <=> element } # => 7
 *    a.bsearch {|element| -1 <=> element } # => nil
 *    a.bsearch {|element| 5 <=> element } # => nil
 *    a.bsearch {|element| 15 <=> element } # => nil
 *
 *  Less formally: the block is such that:
 *  - All positive-evaluating elements precede all zero-evaluating elements.
 *  - All positive-evaluating elements precede all negative-evaluating elements.
 *  - All zero-evaluating elements precede all negative-evaluating elements.
 *
 *  These make sense as blocks in find-any mode:
 *    a = [0, 4, 7, 10, 12]
 *    a.map {|element| 7 <=> element } # => [1, 1, 0, -1, -1]
 *    a.map {|element| -1 <=> element } # => [-1, -1, -1, -1, -1]
 *    a.map {|element| 5 <=> element } # => [1, 1, -1, -1, -1]
 *    a.map {|element| 15 <=> element } # => [1, 1, 1, 1, 1]
 *
 *  This would not make sense:
 *    a = [0, 4, 7, 10, 12]
 *    a.map {|element| element <=> 7 } # => [-1, -1, 0, 1, 1]
 *
 *  ---
 *
 *  Returns an enumerator if no block given:
 *    a = [0, 4, 7, 10, 12]
 *    a.bsearch # => #<Enumerator: [0, 4, 7, 10, 12]:bsearch>
 *
 *  ---
 *
 *  Raises an exception if the block returns an invalid value:
 *    a = 'abcde'.split('').shuffle
 *    # Raises TypeError (wrong argument type Symbol (must be numeric, true, false or nil)):
 *    a.bsearch {|element| :foo }
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
	else if (v == Qfalse || v == Qnil) {
	    smaller = 0;
	}
	else if (rb_obj_is_kind_of(v, rb_cNumeric)) {
	    const VALUE zero = INT2FIX(0);
	    switch (rb_cmpint(rb_funcallv(v, id_cmp, 1, &zero), v, zero)) {
	      case 0: return INT2FIX(mid);
	      case 1: smaller = 1; break;
	      case -1: smaller = 0;
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
 *    a = ['aaaa', 'bbb', 'cc', 'd']
 *    a.sort_by! {|element| element.size }
 *    a # => ["d", "cc", "bbb", "aaaa"]
 *
 *  ---
 *
 *  Returns a new \Enumerator if no block given:
 *
 *    a = ['aaaa', 'bbb', 'cc', 'd']
 *    a.sort_by! # => #<Enumerator: ["aaaa", "bbb", "cc", "d"]:sort_by!>
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
 *    array.collect {|element| ... } -> new_array
 *    array.collect -> new_enumerator
 *
 *  Array#map is an alias for Array#collect.
 *
 *  Calls the block, if given, with each element of +self+;
 *  returns a new \Array whose elements are the return values from the block:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.collect {|element| element.class }
 *    a1 # => [Symbol, String, Integer]
 *
 *  ---
 *
 *  Returns a new \Enumerator if no block given:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.collect
 *    a1 # => #<Enumerator: [:foo, "bar", 2]:collect>
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
 *    array.collect! {|element| ... } -> self
 *    array.collect! -> new_enumerator
 *
 *  Array#map! is an alias for Array#collect!.
 *
 *  Calls the block, if given, with each element;
 *  replaces the element with the block's return value:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.collect! { |element| element.class }
 *    a1 # => [Symbol, String, Integer]
 *    a1.equal?(a) # => true # Returned self
 *
 *  ---
 *
 *  Returns a new \Enumerator if no block given:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.collect!
 *    a1 # => #<Enumerator: [:foo, "bar", 2]:collect!>
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
            const VALUE *const src = RARRAY_CONST_PTR_TRANSIENT(ary);
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
 *  Returns a new \Array whose elements are the elements
 *  of +self+ at the given +indexes+.
 *
 *  Each +index+ given in +indexes+ must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  ---
 *
 *  For each positive +index+, returns the element at offset +index+:
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, 2) # => [:foo, 2]
 *
 *  The given +indexes+ may be in any order, and may repeat:
 *    a = [:foo, 'bar', 2]
 *    a.values_at(2, 0, 1, 0, 2) # => [2, :foo, "bar", :foo, 2]
 *
 *  Assigns +nil+ for an +index+ that is too large:
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, 3, 1, 3) # => [:foo, nil, "bar", nil]
 *
 *  Returns a new empty \Array if no arguments given:
 *    [].values_at # => []
 *
 *  ---
 *
 *  For each negative +index+, counts backward from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a.values_at(-1, -3) # => [2, :foo]
 *
 *  Assigns +nil+ for an +index+ that is too small:
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, -5, 1, -6, 2) # => [:foo, nil, "bar", nil, 2]
 *
 *  The given +indexes+ may have a mixture of signs:
 *    a = [:foo, 'bar', 2]
 *    a.values_at(0, -2, 1, -1) # => [:foo, "bar", "bar", 2]
 *
 *  ---
 *
 *  Raises an exception if any +index+ is not an Integer-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.values_at(0, :foo)
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
 *    array.filter {|element| ... } -> new_array
 *    array.filter -> new_enumerator
 *
 *  Array#filter is an alias for Array#select.
 *
 *  Calls the block, if given, with each element of +self+;
 *  returns a new \Array containing those elements of +self+
 *  for which the block returns a truthy value:
 *    a = [:foo, 'bar', 2, :bam]
 *    a1 = a.select {|element| element.to_s.start_with?('b') }
 *    a1 # => ["bar", :bam]
 *
 *  ---
 *
 *  Returns a new \Enumerator if no block given:
 *    a = [:foo, 'bar', 2, :bam]
 *    a.select # => #<Enumerator: [:foo, "bar", 2, :bam]:select>
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
	if (i1 < len) {
	    tail = len - i1;
            RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
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
 *    array.filter! {|element| ... } -> self or nil
 *    array.filter! -> new_enumerator
 *
 *  Array#filter! is an alias for Array#select!.
 *
 *  Calls the block, if given  with each element of +self+;
 *  removes from +self+ those elements for which the block returns +false+ or +nil+.
 *
 *  Returns +self+ if any elements were removed:
 *    a = [:foo, 'bar', 2, :bam]
 *    a1 = a.select! {|element| element.to_s.start_with?('b') }
 *    a1 # => ["bar", :bam]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Returns +nil+ if no elements were removed:
 *    a = [:foo, 'bar', 2, :bam]
 *    a.select! { |element| element.kind_of?(Object) } # => nil
 *
 *  ---
 *
 *  Returns a new \Enumerator if no block given:
 *    a = [:foo, 'bar', 2, :bam]
 *    a.select! # => #<Enumerator: [:foo, "bar", 2, :bam]:select!>
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
 *    a = [:foo, 'bar', 2, :bam]
 *    a1 = a.keep_if {|element| element.to_s.start_with?('b') }
 *    a1 # => ["bar", :bam]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Returns a new \Enumerator if no block given:
 *    a = [:foo, 'bar', 2, :bam]
 *    a.keep_if # => #<Enumerator: [:foo, "bar", 2, :bam]:keep_if>
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
 *  Removes zero or more elements from +self+; returns +self+.
 *
 *  ---
 *
 *  When no block is given,
 *  removes from +self+ each element +ele+ such that <tt>ele == obj</tt>;
 *  returns the last deleted element:
 *    s1 = 'bar'; s2 = 'bar'
 *    a = [:foo, s1, 2, s2]
 *    deleted_obj = a.delete('bar')
 *    a # => [:foo, 2]
 *    deleted_obj.equal?(s2) # => true # Returned self
 *
 *  Returns +nil+ if no elements removed:
 *    a = [:foo, 'bar', 2]
 *    a.delete(:nosuch) # => nil
 *
 *  ---
 *
 *  When a block is given,
 *  removes from +self+ each element +ele+ such that <tt>ele == obj</tt>.
 *
 *  If any such elements are found, ignores the block
 *  and returns the last deleted element:
 *    s1 = 'bar'; s2 = 'bar'
 *    a = [:foo, s1, 2, s2]
 *    deleted_obj = a.delete('bar') {|obj| fail 'Cannot happen' }
 *    a # => [:foo, 2]
 *    deleted_obj.object_id == s2.object_id # => true
 *
 *  If no such elements are found, returns the block's return value:
 *    a = [:foo, 'bar', 2]
 *    a.delete(:nosuch) {|obj| "#{obj} not found" } # => "nosuch not found"
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
    RARRAY_PTR_USE_TRANSIENT(ary, ptr, {
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
 *  Deletes an element from +self+, per the given +index+.
 *
 *  The given +index+ must be an
 *  {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *
 *  ---
 *
 *  When +index+ is non-negative, deletes the element at offset +index+:
 *    a = [:foo, 'bar', 2]
 *    a.delete_at(1) # => "bar"
 *    a # => [:foo, 2]
 *
 *  If index is too large, returns nil:
 *    a = [:foo, 'bar', 2]
 *    a.delete_at(5) # => nil
 *
 *  ---
 *
 *  When +index+ is negative, counts backward from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a.delete_at(-2) # => "bar"
 *    a # => [:foo, 2]
 *
 *  If +index+ is too small (far from zero), returns nil:
 *    a = [:foo, 'bar', 2]
 *    a.delete_at(-5) # => nil
 *
 *  ---
 *
 *  Raises an exception if index is not an Integer-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.delete_at(:foo)
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
    else if (orig_len < pos + len) {
        len = orig_len - pos;
    }
    if (len == 0) {
        return rb_ary_new2(0);
    }
    else {
        VALUE arg2 = rb_ary_new4(len, RARRAY_CONST_PTR_TRANSIENT(ary)+pos);
        RBASIC_SET_CLASS(arg2, rb_obj_class(ary));
        rb_ary_splice(ary, pos, len, 0, 0);
        return arg2;
    }
}

/*
 *  call-seq:
 *    array.slice!(n) -> obj or nil
 *    array.slice!(start, length) -> new_array or nil
 *    array.slice!(range) -> new_array or nil
 *
 *  Removes and returns elements from +self+.
 *
 *  - Argument +n+, if given must be an \Integer object.
 *  - Arguments +start+ and +length+, if given must be \Integer objects.
 *  - Argument +range+, if given, must be a \Range object.
 *
 *  ---
 *
 *  When the only argument is an \Integer +n+,
 *  removes and returns the _nth_ element in +self+:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(1) # => "bar"
 *    a # => [:foo, 2]
 *
 *  If +n+ is negative, counts backwards from the end of +self+:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(-1) # => 2
 *    a # => [:foo, "bar"]
 *
 *  If +n+ is out of range, returns +nil+:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(50) # => nil
 *    a.slice!(-50) # => nil
 *    a # => [:foo, "bar", 2]
 *
 *  ---
 *
 *  When the only arguments are Integers +start+ and +length+,
 *  removes +length+ elements from +self+ beginning at offset  +start+;
 *  returns the deleted objects in a new Array:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(0, 2) # => [:foo, "bar"]
 *    a # => [2]
 *
 *  If <tt>start + length</tt> exceeds the array size,
 *  removes and returns all elements from offset +start+ to the end:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(1, 50) # => ["bar", 2]
 *    a # => [:foo]
 *
 *  If <tt>start == a.size</tt> and +length+ is non-negative,
 *  returns a new empty \Array:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(a.size, 0) # => []
 *    a.slice!(a.size, 50) # => []
 *    a # => [:foo, "bar", 2]
 *
 *  If +length+ is negative, returns +nil+:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(2, -1) # => nil
 *    a.slice!(1, -2) # => nil
 *    a # => [:foo, "bar", 2]
 *
 *  ---
 *
 *  When the only argument is a \Range object +range+,
 *  treats <tt>range.min</tt> as +start+ above and <tt>range.size</tt> as +length+ above:
 *    a = [:foo, 'bar', 2]
 *     a.slice!(1..2) # => ["bar", 2]
 *    a # => [:foo]
 *
 *  If <tt>range.start == a.size</tt>, returns a new empty \Array:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(a.size..0) # => []
 *    a.slice!(a.size..50) # => []
 *    a.slice!(a.size..-1) # => []
 *    a.slice!(a.size..-50) # => []
 *    a # => [:foo, "bar", 2]
 *
 *  If <tt>range.start</tt> is larger than the array size, returns +nil+:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(4..1) # => nil
 *    a.slice!(4..0) # => nil
 *    a.slice!(4..-1) # => nil
 *
 *  If <tt>range.end</tt> is negative, counts backwards from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(0..-2) # => [:foo, "bar"]
 *    a # => [2]
 *
 *  If <tt>range.start</tt> is negative,
 *  calculates the start index backwards from the end of the array:
 *    a = [:foo, 'bar', 2]
 *    a.slice!(-2..2) # => ["bar", 2]
 *    a # => [:foo]
 *
 *  ---
 *
 *  Raises an exception if given a single argument that is not an \Integer or a \Range:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.slice!(:foo)
 *
 *  Raises an exception if given two arguments that are not both Integers:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.slice!(:foo, 3)
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    a.slice!(1, :bar)
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
 *    a = [:foo, 'bar', 2, 'bat']
 *    a1 = a.reject! {|element| element.to_s.start_with?('b') }
 *    a1 # => [:foo, 2]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Returns +nil+ if no elements removed:
 *    a = [:foo, 'bar', 2]
 *    a.reject! {|element| false } # => nil
 *
 *  Returns a new \Enumerator if no block given:
 *    a = [:foo, 'bar', 2]
 *    a.reject! # => #<Enumerator: [:foo, "bar", 2]:reject!>
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
 *  Returns a new \Array whose elements are all those from +self+
 *  for which the block returns +false+ or +nil+:
 *    a = [:foo, 'bar', 2, 'bat']
 *    a1 = a.reject { |element| element.to_s.start_with?('b') }
 *    a1 # => [:foo, 2]
 *
 *  Returns a new \Enumerator if no block given:
 *     a = [:foo, 'bar', 2]
 *     a.reject # => #<Enumerator: [:foo, "bar", 2]:reject>
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
 *    a = [:foo, 'bar', 2, 'bat']
 *    a1 = a.delete_if {|element| element.to_s.start_with?('b') }
 *    a1 # => [:foo, 2]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Returns a new \Enumerator if no block given:
 *    a = [:foo, 'bar', 2]
 *    a.delete_if # => #<Enumerator: [:foo, "bar", 2]:delete_if>
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
    if (args[1] == 0) rb_iter_break();
    else args[1]--;
    if (argc > 1) val = rb_ary_new4(argc, argv);
    rb_ary_push(args[0], val);
    return Qnil;
}

static VALUE
take_items(VALUE obj, long n)
{
    VALUE result = rb_check_array_type(obj);
    VALUE args[2];

    if (!NIL_P(result)) return rb_ary_subseq(result, 0, n);
    result = rb_ary_new2(n);
    args[0] = result; args[1] = (VALUE)n;
    if (rb_check_block_call(obj, idEach, 0, 0, take_i, (VALUE)args) == Qundef)
	rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (must respond to :each)",
		 rb_obj_class(obj));
    return result;
}


/*
 *  call-seq:
 *    array.zip(*other_arrays) -> new_array
 *    array.zip(*other_arrays) {|other_array| ... } -> nil
 *
 *  Each object in +other_arrays+ must be an
 *  {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects].
 *
 *  ---
 *
 *  When no block given, returns a new \Array +new_array+ of size <tt>self.size</tt>
 *  whose elements are Arrays.
 *
 *  Each nested array <tt>new_array[n]</tt> is of size <tt>other_arrays.size+1</tt>,
 *  and contains:
 *  - The _nth_ element of +self+.
 *  - The _nth_ element of each of the +other_arrays+.
 *
 *  If all +other_arrays+ and +self+ are the same size:
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3]
 *    c = [:c0, :c1, :c2, :c3]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, :c2], [:a3, :b3, :c3]]
 *
 *  If any array in +other_arrays+ is smaller than +self+,
 *  fills to <tt>self.size</tt> with +nil+:
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2]
 *    c = [:c0, :c1]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, nil], [:a3, nil, nil]]
 *
 *  If any array in +other_arrays+ is larger than +self+,
 *  its trailing elements are ignored:
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3, :b4]
 *    c = [:c0, :c1, :c2, :c3, :c4, :c5]
 *    d = a.zip(b, c)
 *    d # => [[:a0, :b0, :c0], [:a1, :b1, :c1], [:a2, :b2, :c2], [:a3, :b3, :c3]]
 *
 *  ---
 *
 *  When a block is given, calls the block with each of the sub-arrays (formed as above); returns nil
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3]
 *    c = [:c0, :c1, :c2, :c3]
 *    a.zip(b, c) {|sub_array| p sub_array} # => nil
 *
 *  Output:
 *    [:a0, :b0, :c0]
 *    [:a1, :b1, :c1]
 *    [:a2, :b2, :c2]
 *    [:a3, :b3, :c3]
 *
 *  ---
 *
 *  Raises an exception if any object in +other_arrays+ is not an Array-convertible object:
 *    a = [:a0, :a1, :a2, :a3]
 *    b = [:b0, :b1, :b2, :b3]
 *    c = [:c0, :c1, :c2, :c3]
 *    # Raises TypeError (wrong argument type Symbol (must respond to :each)):
 *    d = a.zip(a, b, c, :foo)
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
 *  Transposes the rows and columns in an array of arrays.
 *
 *  Each element in +self+ must be an
 *  {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects].
 *
 *    a = [[:a0, :a1], [:b0, :b1], [:c0, :c1]]
 *    a.transpose # => [[:a0, :b0, :c0], [:a1, :b1, :c1]]
 *
 *  ---
 *
 *  Raises an exception if any element in +self+ is not an Array-convertible object:
 *    a = [[:a0, :a1], [:b0, :b1], :foo]
 *    # Raises TypeError (no implicit conversion of Symbol into Array):
 *    a.transpose
 *
 *  Raises an exception if the elements in +self+ are of differing sizes:
 *    a = [[:a0, :a1], [:b0, :b1], [:c0, :c1, :c2]]
 *    # Raises IndexError (element size differs (3 should be 2)):
 *    a.transpose
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
 *  Replaces the content of +self+ with the content of +other_array+; returns +self+.
 *
 *  Argument +other_array+ must be an
 *  {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects].
 *
 *  ---
 *
 *  Replaces the content of +self+ with the content of +other_array+:
 *    a = [:foo, 'bar', 2]
 *    a1 = a.replace(['foo', :bar, 3])
 *    a1 # => ["foo", :bar, 3]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Ignores the size of +self+:
 *
 *    a = [:foo, 'bar', 2]
 *    a.replace([]) # => []
 *    a.replace([:foo, 'bar', 2]) # => [:foo, "bar", 2]
 *
 *  ---
 *
 *  Raises an exception if +other_array+ is not an Array-convertible object:
 *    a = [:foo, 'bar', 2]
 *    # Raises TypeError (no implicit conversion of Symbol into Array):
 *    a.replace(:foo)
 */

VALUE
rb_ary_replace(VALUE copy, VALUE orig)
{
    rb_ary_modify_check(copy);
    orig = to_ary(orig);
    if (copy == orig) return copy;

    if (RARRAY_LEN(orig) <= RARRAY_EMBED_LEN_MAX) {
        VALUE shared_root = 0;

        if (ARY_OWNS_HEAP_P(copy)) {
            ary_heap_free(copy);
	}
        else if (ARY_SHARED_P(copy)) {
            shared_root = ARY_SHARED_ROOT(copy);
            FL_UNSET_SHARED(copy);
        }
        FL_SET_EMBED(copy);
        ary_memcpy(copy, 0, RARRAY_LEN(orig), RARRAY_CONST_PTR_TRANSIENT(orig));
        if (shared_root) {
            rb_ary_decrement_share(shared_root);
        }
        ARY_SET_LEN(copy, RARRAY_LEN(orig));
    }
    else {
        VALUE shared_root = ary_make_shared(orig);
        if (ARY_OWNS_HEAP_P(copy)) {
            ary_heap_free(copy);
        }
        else {
            rb_ary_unshare_safe(copy);
        }
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
 *    a = [:foo, 'bar', 2]
 *    a1 = a.clear
 *    a1 # => []
 *    a1.equal?(a) # => true # Returned self
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
 *    array.fill { |index| ... } -> self
 *    array.fill(start) { |index| ... } -> self
 *    array.fill(start, length) { |index| ... } -> self
 *    array.fill(range) { |index| ... } -> self
 *
 *  Replaces specified elements in +self+ with specified objects; returns +self+.
 *
 *  - Arguments +start+ and +length+, if given, must be
 *    {Integer-convertible objects}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *  - Argument +range+, if given, must be a \Range object.
 *
 *  ---
 *
 *  With argument +obj+ and no block given, replaces all elements with that one object:
 *    a = ['a', 'b', 'c', 'd']
 *    a # => ["a", "b", "c", "d"]
 *    a1 = a.fill(:X)
 *    a1 # => [:X, :X, :X, :X]
 *    a.equal?(a) #  => true # Retrurned self
 *
 *  ---
 *
 *  With arguments +obj+ and +start+, and no block given, replaces elements based on the given start.
 *
 *  If +start+ is in range (<tt>0 <= start < ary.size</tt>),
 *  replaces all elements from offset +start+ through the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 2) # => ["a", "b", :X, :X]
 *
 *  If +start+ is too large (<tt>start >= ary.size</tt>), does nothing:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 4) # => ["a", "b", "c", "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 5) # => ["a", "b", "c", "d"]
 *
 *  If +start+ is negative, counts from the end (starting index is <tt>start + ary.size</tt>):
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -2) # => ["a", "b", :X, :X]
 *
 *  If +start+ is too small (less than and far from zero), replaces all elements:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -6) # => [:X, :X, :X, :X]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -50) # => [:X, :X, :X, :X]
 *
 *  ---
 *
 *  With arguments +obj+, +start+, and +length+, and no block given,
 *  replaces elements based on the given +start+ and +length+.
 *
 *  If +start+ is in range, replaces +length+ elements beginning at offset +start+:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 1, 1) # => ["a", :X, "c", "d"]
 *
 *  If +start+ is negative, counts from the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, -2, 1) # => ["a", "b", :X, "d"]
 *
 *  If +start+ is large (<tt>start >= ary.size</tt>), extends +self+ with +nil+:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 5, 0) # => ["a", "b", "c", "d", nil]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 5, 2) # => ["a", "b", "c", "d", nil, :X, :X]
 *
 *  ---
 *
 *  If +length+ is zero or negative, replaces no elements:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, 1, 0) # => ["a", "b", "c", "d"]
 *    a.fill(:X, 1, -1) # => ["a", "b", "c", "d"]
 *
 *  ---
 *
 *  With arguments +obj+ and +range+, and no block given,
 *  replaces elements based on the given range.
 *
 *  If the range is positive and ascending (<tt>0 < range.begin <= range.end</tt>),
 *  replaces elements from <tt>range.begin</tt> to <tt>range.end</tt>:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (1..1)) # => ["a", :X, "c", "d"]
 *
 *  If <tt>range.first</tt> is negative, replaces no elements:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (-1..1)) # => ["a", "b", "c", "d"]
 *
 *  If <tt>range.last</tt> is negative, counts from the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (0..-2)) # => [:X, :X, :X, "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (1..-2)) # => ["a", :X, :X, "d"]
 *
 *  If <tt>range.last</tt> and <tt>range.last</tt> are both negative,
 *  both count from the end of the array:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (-1..-1)) # => ["a", "b", "c", :X]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(:X, (-2..-2)) # => ["a", "b", :X, "d"]
 *
 *  ---
 *
 *  With no arguments and a block given, calls the block with each index;
 *  replaces the corresponding element with the block's return value:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "new_3"]
 *
 *  ---
 *
 *  With argument +start+ and a block given, calls the block with each index
 *  from offset +start+ to the end; replaces the corresponding element
 *  with the block's return value:
 *
 *  If start is in range (<tt>0 <= start < ary.size</tt>),
 *  replaces from offset +start+ to the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1) { |index| "new_#{index}" } # => ["a", "new_1", "new_2", "new_3"]
 *
 *  If +start+ is too large(<tt>start >= ary.size</tt>), does nothing:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(4) { |index| fail 'Cannot happen' } # => ["a", "b", "c", "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(4) { |index| fail 'Cannot happen' } # => ["a", "b", "c", "d"]
 *
 *  If +start+ is negative, counts from the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-2) { |index| "new_#{index}" } # => ["a", "b", "new_2", "new_3"]
 *
 *  If start is too small (<tt>start <= -ary.size</tt>, replaces all elements:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-6) { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "new_3"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-50) { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "new_3"]
 *
 *  ---
 *
 *  With arguments +start+ and +length+, and a block given,
 *  calls the block for each index specified by start length;
 *  replaces the corresponding element with the block's return value.
 *
 *  If +start+ is in range, replaces +length+ elements beginning at offset +start+:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1, 1) { |index| "new_#{index}" } # => ["a", "new_1", "c", "d"]
 *
 *  If start is negative, counts from the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-2, 1) { |index| "new_#{index}" } # => ["a", "b", "new_2", "d"]
 *
 *  If +start+ is large (<tt>start >= ary.size</tt>), extends +self+ with +nil+:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(5, 0) { |index| "new_#{index}" } # => ["a", "b", "c", "d", nil]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(5, 2) { |index| "new_#{index}" } # => ["a", "b", "c", "d", nil, "new_5", "new_6"]
 *
 *  If +length+ is zero or less, replaces no elements:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1, 0) { |index| "new_#{index}" } # => ["a", "b", "c", "d"]
 *    a.fill(1, -1) { |index| "new_#{index}" } # => ["a", "b", "c", "d"]
 *
 *  ---
 *
 *  With arguments +obj+ and +range+, and a block given,
 *  calls the block with each index in the given range;
 *  replaces the corresponding element with the block's return value.
 *
 *  If the range is positive and ascending (<tt>range 0 < range.begin <= range.end</tt>,
 *  replaces elements from <tt>range.begin</tt> to <tt>range.end</tt>:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1..1) { |index| "new_#{index}" } # => ["a", "new_1", "c", "d"]
 *
 *  If +range.first+ is negative, does nothing:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-1..1) { |index| fail 'Cannot happen' } # => ["a", "b", "c", "d"]
 *
 *  If <tt>range.last</tt> is negative, counts from the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(0..-2) { |index| "new_#{index}" } # => ["new_0", "new_1", "new_2", "d"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(1..-2) { |index| "new_#{index}" } # => ["a", "new_1", "new_2", "d"]
 *
 *  If <tt>range.first</tt> and <tt>range.last</tt> are both negative,
 *  both count from the end:
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-1..-1) { |index| "new_#{index}" } # => ["a", "b", "c", "new_3"]
 *    a = ['a', 'b', 'c', 'd']
 *    a.fill(-2..-2) { |index| "new_#{index}" } # => ["a", "b", "new_2", "d"]
 *
 *  ---
 *
 *  Raises an exception if no block is given and the second argument is not a Range
 *  or an Integer-convertible object,
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    [].fill(:X, :x)
 *
 *  Raises an exception if no is block given, three arguments are given,
 *  and the second or third argument not an Integer-convertible object:
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    [].fill(:X, :x, 1)
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    [].fill(:X, 1, :x)
 *
 *  Raises an exception if a block is given, one argument is given,
 *  and that argument is not a \Range or an Integer-convertible object:
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    [].fill(:x) { }
 *
 *  Raises an exception if a block is given, two arguments are given,
 *  and either argument is not an Integer-convertible object:
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    [].fill(:x, 1) { }
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    [].fill(1, :x) { }
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

    if (item == Qundef) {
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
 *    array + other_array -> new_array
 *
 *  Returns the concatenation of +array+ and +other_array+ in a new \Array.
 *
 *  Argument +other_array+ must be an
 *  {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects].
 *
 *  Returns a new \Array containing all elements of +array+
 *  followed by all elements of +other_array+:
 *    a = [0, 1] + [2, 3]
 *    a # => [0, 1, 2, 3]
 *
 *  See also #concat.
 *  ---
 *
 *  Raises an exception if +other_array+ is not an Array-convertible object:
 *    # Raises TypeError (no implicit conversion of Symbol into Array):
 *    [] + :foo
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

    ary_memcpy(z, 0, xlen, RARRAY_CONST_PTR_TRANSIENT(x));
    ary_memcpy(z, xlen, ylen, RARRAY_CONST_PTR_TRANSIENT(y));
    ARY_SET_LEN(z, len);
    return z;
}

static VALUE
ary_append(VALUE x, VALUE y)
{
    long n = RARRAY_LEN(y);
    if (n > 0) {
        rb_ary_splice(x, RARRAY_LEN(x), 0, RARRAY_CONST_PTR_TRANSIENT(y), n);
    }
    return x;
}

/*
 *  call-seq:
 *    array.concat(*other_arrays) -> self
 *
 *  The given +other_arrays+ must be
 *  {Array-convertible objects}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects].
 *
 *  Adds to +array+ all elements from each array in +other_arrays+; returns +self+:
 *    a = [0, 1]
 *    a1 = a.concat([2, 3], [4, 5])
 *    a1 # => [0, 1, 2, 3, 4, 5]
 *    a1.equal?(a) # => true # Returned self
 *
 *  Returns +self+ unmodified if no arguments given:
 *    a = [0, 1]
 *    a.concat
 *    a # => [0, 1]
 *
 *  ---
 *
 *  Raises an exception if any argument is not an Array-convertible object:
 *    # Raises TypeError (no implicit conversion of Symbol into Array):
 *    [].concat([], :foo)
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
	VALUE args = rb_ary_tmp_new(argc);
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
 *  - Argument +n+, if given, must be an
 *    {Integer-convertible object}[doc/implicit_conversion_rdoc.html#label-Integer-Convertible+Objects].
 *  - Argument +string_separator+, if given, myst be a
 *    {String-convertible object}[doc/implicit_conversion_rdoc.html#label-String-Convertible+Objects].
 *
 *  ---
 *
 *  When argument +n+ is given, returns a new concatenated \Array.
 *
 *  If +n+ is positive, returns the concatenation of +n+ repetitions of +self+:
 *    a = ['x', 'y']
 *    a * 3 # => ["x", "y", "x", "y", "x", "y"]
 *
 *  If +n+ is zero, returns an new empty \Array:
 *    a = [0, 1]
 *    a * 0 # => []
 *
 *  ---
 *
 *  When argument +string_separator+ is given,
 *  returns a new \String equivalent to the result of <tt>array.join(string_separator)</tt>.
 *
 *  If +array+ is non-empty, returns the join of each element's +to_s+ value:
 *    [0, [0, 1], {foo: 0}] * ', ' # => "0, 0, 1, {:foo=>0}"
 *
 *  If +array+ is empty, returns a new empty \String:
 *    [] * ',' # => ""
 *  ---
 *
 *  Raises an exception if the argument is not an Integer-convertible object
 *  or a String-convertible object:
 *    # Raises TypeError (no implicit conversion of Symbol into Integer):
 *    [] * :foo
 *
 *  Raises an exception if +n+ is negative:
 *    # Raises ArgumentError (negative argument):
 *    [] * -1
 *
 *  Raises an exception if argument +string_separator+ is given,
 *  and any array element lacks instance method +to_s+:
 *    # Raises NoMethodError (undefined method `to_s' for #<BasicObject:>):
 *    [BasicObject.new] * ','
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
	ary2 = ary_new(rb_obj_class(ary), 0);
	goto out;
    }
    if (len < 0) {
	rb_raise(rb_eArgError, "negative argument");
    }
    if (ARY_MAX_SIZE/len < RARRAY_LEN(ary)) {
	rb_raise(rb_eArgError, "argument too big");
    }
    len *= RARRAY_LEN(ary);

    ary2 = ary_new(rb_obj_class(ary), len);
    ARY_SET_LEN(ary2, len);

    ptr = RARRAY_CONST_PTR_TRANSIENT(ary);
    t = RARRAY_LEN(ary);
    if (0 < t) {
	ary_memcpy(ary2, 0, t, ptr);
	while (t <= len/2) {
            ary_memcpy(ary2, t, t, RARRAY_CONST_PTR_TRANSIENT(ary2));
            t *= 2;
        }
        if (t < len) {
            ary_memcpy(ary2, t, len-t, RARRAY_CONST_PTR_TRANSIENT(ary2));
        }
    }
  out:
    return ary2;
}

/*
 *  call-seq:
 *    array.assoc(obj) -> found_array or nil
 *
 *  Returns the first element in +self+ that is an \Array
 *  whose first element <tt>==</tt> +obj+:
 *    a = [{foo: 0}, [2, 4], [4, 5, 6], [4, 5]]
 *    a.assoc(4) # => [4, 5, 6]
 *
 *  Returns +nil+ if no such element is found:
 *    a = [{foo: 0}, [2, 4], [4, 5, 6], [4, 5]]
 *    a.assoc(:nosuch) # => nil
 *
 *  See also #rassoc.
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
 *  Returns the first element in +self+ that is an \Array
 *  whose second element <tt>==</tt> +obj+:
 *    a = [{foo: 0}, [2, 4], [4, 5, 6], [4, 5]]
 *    a.rassoc(4) # => [2, 4]
 *
 *  Returns +nil+ if no such element is found:
 *    a = [{foo: 0}, [2, 4], [4, 5, 6], [4, 5]]
 *    a.rassoc(:nosuch) # => nil
 *
 *  See also #assoc.
 */

VALUE
rb_ary_rassoc(VALUE ary, VALUE value)
{
    long i;
    VALUE v;

    for (i = 0; i < RARRAY_LEN(ary); ++i) {
	v = RARRAY_AREF(ary, i);
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
 *     ary == other_ary   ->   bool
 *
 *  Equality --- Two arrays are equal if they contain the same number of
 *  elements and if each element is equal to (according to Object#==) the
 *  corresponding element in +other_ary+.
 *
 *     [ "a", "c" ]    == [ "a", "c", 7 ]     #=> false
 *     [ "a", "c", 7 ] == [ "a", "c", 7 ]     #=> true
 *     [ "a", "c", 7 ] == [ "a", "d", "f" ]   #=> false
 *
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
    if (RARRAY_CONST_PTR_TRANSIENT(ary1) == RARRAY_CONST_PTR_TRANSIENT(ary2)) return Qtrue;
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
 *     ary.eql?(other)  -> true or false
 *
 *  Returns +true+ if +self+ and +other+ are the same object,
 *  or are both arrays with the same content (according to Object#eql?).
 */

static VALUE
rb_ary_eql(VALUE ary1, VALUE ary2)
{
    if (ary1 == ary2) return Qtrue;
    if (!RB_TYPE_P(ary2, T_ARRAY)) return Qfalse;
    if (RARRAY_LEN(ary1) != RARRAY_LEN(ary2)) return Qfalse;
    if (RARRAY_CONST_PTR_TRANSIENT(ary1) == RARRAY_CONST_PTR_TRANSIENT(ary2)) return Qtrue;
    return rb_exec_recursive_paired(recursive_eql, ary1, ary2, ary2);
}

/*
 *  call-seq:
 *     ary.hash   -> integer
 *
 *  Compute a hash-code for this array.
 *
 *  Two arrays with the same content will have the same hash code (and will
 *  compare using #eql?).
 *
 *  See also Object#hash.
 */

static VALUE
rb_ary_hash(VALUE ary)
{
    long i;
    st_index_t h;
    VALUE n;

    h = rb_hash_start(RARRAY_LEN(ary));
    h = rb_hash_uint(h, (st_index_t)rb_ary_hash);
    for (i=0; i<RARRAY_LEN(ary); i++) {
	n = rb_hash(RARRAY_AREF(ary, i));
	h = rb_hash_uint(h, NUM2LONG(n));
    }
    h = rb_hash_end(h);
    return ST2FIX(h);
}

/*
 *  call-seq:
 *     ary.include?(object)   -> true or false
 *
 *  Returns +true+ if the given +object+ is present in +self+ (that is, if any
 *  element <code>==</code> +object+), otherwise returns +false+.
 *
 *     a = [ "a", "b", "c" ]
 *     a.include?("b")   #=> true
 *     a.include?("z")   #=> false
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
 *     ary <=> other_ary   ->  -1, 0, +1 or nil
 *
 *  Comparison --- Returns an integer (+-1+, +0+, or <code>+1</code>) if this
 *  array is less than, equal to, or greater than +other_ary+.
 *
 *  Each object in each array is compared (using the <=> operator).
 *
 *  Arrays are compared in an "element-wise" manner; the first element of +ary+
 *  is compared with the first one of +other_ary+ using the <=> operator, then
 *  each of the second elements, etc...
 *  As soon as the result of any such comparison is non zero (i.e. the two
 *  corresponding elements are not equal), that result is returned for the
 *  whole array comparison.
 *
 *  If all the elements are equal, then the result is based on a comparison of
 *  the array lengths. Thus, two arrays are "equal" according to Array#<=> if,
 *  and only if, they have the same length and the value of each element is
 *  equal to the value of the corresponding element in the other array.
 *
 *  +nil+ is returned if the +other_ary+ is not an array or if the comparison
 *  of two elements returned +nil+.
 *
 *     [ "a", "a", "c" ]    <=> [ "a", "b", "c" ]   #=> -1
 *     [ 1, 2, 3, 4, 5, 6 ] <=> [ 1, 2 ]            #=> +1
 *     [ 1, 2 ]             <=> [ 1, :two ]         #=> nil
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
    if (v != Qundef) return v;
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

static inline void
ary_recycle_hash(VALUE hash)
{
    assert(RBASIC_CLASS(hash) == 0);
    if (RHASH_ST_TABLE_P(hash)) {
        st_table *tbl = RHASH_ST_TABLE(hash);
	st_free_table(tbl);
        RHASH_ST_CLEAR(hash);
    }
}

/*
 *  call-seq:
 *     ary - other_ary    -> new_ary
 *
 *  Array Difference
 *
 *  Returns a new array that is a copy of the original array, removing all
 *  occurrences of any item that also appear in +other_ary+. The order is
 *  preserved from the original array.
 *
 *  It compares elements using their #hash and #eql? methods for efficiency.
 *
 *     [ 1, 1, 2, 2, 3, 3, 4, 5 ] - [ 1, 2, 4 ]  #=>  [ 3, 3, 5 ]
 *
 *  Note that while 1 and 2 were only present once in the array argument, and
 *  were present twice in the receiver array, all occurrences of each Integer are
 *  removed in the returned array.
 *
 *  If you need set-like behavior, see the library class Set.
 *
 *  See also Array#difference.
 */

static VALUE
rb_ary_diff(VALUE ary1, VALUE ary2)
{
    VALUE ary3;
    VALUE hash;
    long i;

    ary2 = to_ary(ary2);
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
    ary_recycle_hash(hash);
    return ary3;
}

/*
 *  call-seq:
 *     ary.difference(other_ary1, other_ary2, ...)   -> new_ary
 *
 *  Array Difference
 *
 *  Returns a new array that is a copy of the original array, removing all
 *  occurrences of any item that also appear in +other_ary+. The order is
 *  preserved from the original array.
 *
 *  It compares elements using their #hash and #eql? methods for efficiency.
 *
 *     [ 1, 1, 2, 2, 3, 3, 4, 5 ].difference([ 1, 2, 4 ])     #=> [ 3, 3, 5 ]
 *
 *  Note that while 1 and 2 were only present once in the array argument, and
 *  were present twice in the receiver array, all occurrences of each Integer are
 *  removed in the returned array.
 *
 *  Multiple array arguments can be supplied and all occurrences of any element
 *  in those supplied arrays that match the receiver will be removed from the
 *  returned array.
 *
 *     [ 1, 'c', :s, 'yep' ].difference([ 1 ], [ 'a', 'c' ])  #=> [ :s, "yep" ]
 *
 *  If you need set-like behavior, see the library class Set.
 *
 *  See also Array#-.
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
 *     ary & other_ary      -> new_ary
 *
 *  Set Intersection --- Returns a new array containing unique elements common to the
 *  two arrays. The order is preserved from the original array.
 *
 *  It compares elements using their #hash and #eql? methods for efficiency.
 *
 *     [ 1, 1, 3, 5 ] & [ 3, 2, 1 ]                 #=> [ 1, 3 ]
 *     [ 'a', 'b', 'b', 'z' ] & [ 'a', 'b', 'c' ]   #=> [ 'a', 'b' ]
 *
 *  See also Array#uniq.
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
    ary_recycle_hash(hash);

    return ary3;
}

/*
 *  call-seq:
 *     ary.intersection(other_ary1, other_ary2, ...)      -> new_ary
 *
 *  Set Intersection --- Returns a new array containing unique elements common
 *  to +self+ and <code>other_ary</code>s. Order is preserved from the original
 *  array.
 *
 *  It compares elements using their #hash and #eql? methods for efficiency.
 *
 *     [ 1, 1, 3, 5 ].intersection([ 3, 2, 1 ])                    # => [ 1, 3 ]
 *     [ "a", "b", "z" ].intersection([ "a", "b", "c" ], [ "b" ])  # => [ "b" ]
 *     [ "a" ].intersection #=> [ "a" ]
 *
 *  See also Array#&.
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
 *     ary | other_ary     -> new_ary
 *
 *  Set Union --- Returns a new array by joining +ary+ with +other_ary+,
 *  excluding any duplicates and preserving the order from the given arrays.
 *
 *  It compares elements using their #hash and #eql? methods for efficiency.
 *
 *     [ "a", "b", "c" ] | [ "c", "d", "a" ]    #=> [ "a", "b", "c", "d" ]
 *     [ "c", "d", "a" ] | [ "a", "b", "c" ]    #=> [ "c", "d", "a", "b" ]
 *
 *  See also Array#union.
 */

static VALUE
rb_ary_or(VALUE ary1, VALUE ary2)
{
    VALUE hash, ary3;

    ary2 = to_ary(ary2);
    if (RARRAY_LEN(ary1) + RARRAY_LEN(ary2) <= SMALL_ARRAY_LEN) {
	ary3 = rb_ary_new();
        rb_ary_union(ary3, ary1);
        rb_ary_union(ary3, ary2);
	return ary3;
    }

    hash = ary_make_hash(ary1);
    rb_ary_union_hash(hash, ary2);

    ary3 = rb_hash_values(hash);
    ary_recycle_hash(hash);
    return ary3;
}

/*
 *  call-seq:
 *     ary.union(other_ary1, other_ary2, ...)   -> new_ary
 *
 *  Set Union --- Returns a new array by joining <code>other_ary</code>s with +self+,
 *  excluding any duplicates and preserving the order from the given arrays.
 *
 *  It compares elements using their #hash and #eql? methods for efficiency.
 *
 *     [ "a", "b", "c" ].union( [ "c", "d", "a" ] )    #=> [ "a", "b", "c", "d" ]
 *     [ "a" ].union( ["e", "b"], ["a", "c", "b"] )    #=> [ "a", "e", "b", "c" ]
 *     [ "a" ].union #=> [ "a" ]
 *
 *  See also Array#|.
 */

static VALUE
rb_ary_union_multi(int argc, VALUE *argv, VALUE ary)
{
    int i;
    long sum;
    VALUE hash, ary_union;

    sum = RARRAY_LEN(ary);
    for (i = 0; i < argc; i++) {
        argv[i] = to_ary(argv[i]);
        sum += RARRAY_LEN(argv[i]);
    }

    if (sum <= SMALL_ARRAY_LEN) {
        ary_union = rb_ary_new();

        rb_ary_union(ary_union, ary);
        for (i = 0; i < argc; i++) rb_ary_union(ary_union, argv[i]);

        return ary_union;
    }

    hash = ary_make_hash(ary);
    for (i = 0; i < argc; i++) rb_ary_union_hash(hash, argv[i]);

    ary_union = rb_hash_values(hash);
    ary_recycle_hash(hash);
    return ary_union;
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
 *     ary.max                     -> obj
 *     ary.max {|a, b| block}      -> obj
 *     ary.max(n)                  -> array
 *     ary.max(n) {|a, b| block}   -> array
 *
 *  Returns the object in _ary_ with the maximum value. The
 *  first form assumes all objects implement <code><=></code>;
 *  the second uses the block to return <em>a <=> b</em>.
 *
 *     ary = %w(albatross dog horse)
 *     ary.max                                   #=> "horse"
 *     ary.max {|a, b| a.length <=> b.length}    #=> "albatross"
 *
 *  If the +n+ argument is given, maximum +n+ elements are returned
 *  as an array.
 *
 *     ary = %w[albatross dog horse]
 *     ary.max(2)                                  #=> ["horse", "dog"]
 *     ary.max(2) {|a, b| a.length <=> b.length }  #=> ["albatross", "horse"]
 */
static VALUE
rb_ary_max(int argc, VALUE *argv, VALUE ary)
{
    struct cmp_opt_data cmp_opt = { 0, 0 };
    VALUE result = Qundef, v;
    VALUE num;
    long i;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(num = argv[0]))
       return rb_nmin_run(ary, num, 0, 1, 1);

    const long n = RARRAY_LEN(ary);
    if (rb_block_given_p()) {
	for (i = 0; i < RARRAY_LEN(ary); i++) {
	   v = RARRAY_AREF(ary, i);
	   if (result == Qundef || rb_cmpint(rb_yield_values(2, v, result), v, result) > 0) {
	       result = v;
	   }
	}
    }
    else if (n > 0) {
        result = RARRAY_AREF(ary, 0);
        if (n > 1) {
            if (FIXNUM_P(result) && CMP_OPTIMIZABLE(cmp_opt, Integer)) {
                return ary_max_opt_fixnum(ary, 1, result);
            }
            else if (STRING_P(result) && CMP_OPTIMIZABLE(cmp_opt, String)) {
                return ary_max_opt_string(ary, 1, result);
            }
            else if (RB_FLOAT_TYPE_P(result) && CMP_OPTIMIZABLE(cmp_opt, Float)) {
                return ary_max_opt_float(ary, 1, result);
            }
            else {
                return ary_max_generic(ary, 1, result);
            }
        }
    }
    if (result == Qundef) return Qnil;
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
 *     ary.min                     -> obj
 *     ary.min {| a,b | block }    -> obj
 *     ary.min(n)                  -> array
 *     ary.min(n) {| a,b | block } -> array
 *
 *  Returns the object in _ary_ with the minimum value. The
 *  first form assumes all objects implement <code><=></code>;
 *  the second uses the block to return <em>a <=> b</em>.
 *
 *     ary = %w(albatross dog horse)
 *     ary.min                                   #=> "albatross"
 *     ary.min {|a, b| a.length <=> b.length}    #=> "dog"
 *
 *  If the +n+ argument is given, minimum +n+ elements are returned
 *  as an array.
 *
 *     ary = %w[albatross dog horse]
 *     ary.min(2)                                  #=> ["albatross", "dog"]
 *     ary.min(2) {|a, b| a.length <=> b.length }  #=> ["dog", "horse"]
 */
static VALUE
rb_ary_min(int argc, VALUE *argv, VALUE ary)
{
    struct cmp_opt_data cmp_opt = { 0, 0 };
    VALUE result = Qundef, v;
    VALUE num;
    long i;

    if (rb_check_arity(argc, 0, 1) && !NIL_P(num = argv[0]))
       return rb_nmin_run(ary, num, 0, 0, 1);

    const long n = RARRAY_LEN(ary);
    if (rb_block_given_p()) {
	for (i = 0; i < RARRAY_LEN(ary); i++) {
	   v = RARRAY_AREF(ary, i);
	   if (result == Qundef || rb_cmpint(rb_yield_values(2, v, result), v, result) < 0) {
	       result = v;
	   }
	}
    }
    else if (n > 0) {
        result = RARRAY_AREF(ary, 0);
        if (n > 1) {
            if (FIXNUM_P(result) && CMP_OPTIMIZABLE(cmp_opt, Integer)) {
                return ary_min_opt_fixnum(ary, 1, result);
            }
            else if (STRING_P(result) && CMP_OPTIMIZABLE(cmp_opt, String)) {
                return ary_min_opt_string(ary, 1, result);
            }
            else if (RB_FLOAT_TYPE_P(result) && CMP_OPTIMIZABLE(cmp_opt, Float)) {
                return ary_min_opt_float(ary, 1, result);
            }
            else {
                return ary_min_generic(ary, 1, result);
            }
        }
    }
    if (result == Qundef) return Qnil;
    return result;
}

/*
 *  call-seq:
 *     ary.minmax                       -> [obj, obj]
 *     ary.minmax {| a,b | block }      -> [obj, obj]
 *
 *  Returns a two element array which contains the minimum and the
 *  maximum value in the array.
 *
 *  Can be given an optional block to override the default comparison
 *  method <code>a <=> b</code>.
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
 *     ary.uniq!                -> ary or nil
 *     ary.uniq! {|item| ...}   -> ary or nil
 *
 *  Removes duplicate elements from +self+.
 *
 *  If a block is given, it will use the return value of the block for
 *  comparison.
 *
 *  It compares values using their #hash and #eql? methods for efficiency.
 *
 *  +self+ is traversed in order, and the first occurrence is kept.
 *
 *  Returns +nil+ if no changes are made (that is, no duplicates are found).
 *
 *     a = [ "a", "a", "b", "b", "c" ]
 *     a.uniq!   # => ["a", "b", "c"]
 *
 *     b = [ "a", "b", "c" ]
 *     b.uniq!   # => nil
 *
 *     c = [["student","sam"], ["student","george"], ["teacher","matz"]]
 *     c.uniq! {|s| s.first}   # => [["student", "sam"], ["teacher", "matz"]]
 *
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
    ary_recycle_hash(hash);

    return ary;
}

/*
 *  call-seq:
 *     ary.uniq                -> new_ary
 *     ary.uniq {|item| ...}   -> new_ary
 *
 *  Returns a new array by removing duplicate values in +self+.
 *
 *  If a block is given, it will use the return value of the block for comparison.
 *
 *  It compares values using their #hash and #eql? methods for efficiency.
 *
 *  +self+ is traversed in order, and the first occurrence is kept.
 *
 *     a = [ "a", "a", "b", "b", "c" ]
 *     a.uniq   # => ["a", "b", "c"]
 *
 *     b = [["student","sam"], ["student","george"], ["teacher","matz"]]
 *     b.uniq {|s| s.first}   # => [["student", "sam"], ["teacher", "matz"]]
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
    RBASIC_SET_CLASS(uniq, rb_obj_class(ary));
    if (hash) {
        ary_recycle_hash(hash);
    }

    return uniq;
}

/*
 *  call-seq:
 *     ary.compact!    -> ary  or  nil
 *
 *  Removes +nil+ elements from the array.
 *
 *  Returns +nil+ if no changes were made, otherwise returns the array.
 *
 *     [ "a", nil, "b", nil, "c" ].compact! #=> [ "a", "b", "c" ]
 *     [ "a", "b", "c" ].compact!           #=> nil
 */

static VALUE
rb_ary_compact_bang(VALUE ary)
{
    VALUE *p, *t, *end;
    long n;

    rb_ary_modify(ary);
    p = t = (VALUE *)RARRAY_CONST_PTR_TRANSIENT(ary); /* WB: no new reference */
    end = p + RARRAY_LEN(ary);

    while (t < end) {
	if (NIL_P(*t)) t++;
	else *p++ = *t++;
    }
    n = p - RARRAY_CONST_PTR_TRANSIENT(ary);
    if (RARRAY_LEN(ary) == n) {
	return Qnil;
    }
    ary_resize_smaller(ary, n);

    return ary;
}

/*
 *  call-seq:
 *     ary.compact     -> new_ary
 *
 *  Returns a copy of +self+ with all +nil+ elements removed.
 *
 *     [ "a", nil, "b", nil, "c", nil ].compact
 *                       #=> [ "a", "b", "c" ]
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
 *     ary.count                   -> int
 *     ary.count(obj)              -> int
 *     ary.count {|item| block}    -> int
 *
 *  Returns the number of elements.
 *
 *  If an argument is given, counts the number of elements which equal +obj+
 *  using <code>==</code>.
 *
 *  If a block is given, counts the number of elements for which the block
 *  returns a true value.
 *
 *     ary = [1, 2, 4, 2]
 *     ary.count                  #=> 4
 *     ary.count(2)               #=> 2
 *     ary.count {|x| x%2 == 0}   #=> 3
 *
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
    VALUE stack, result, tmp = 0, elt, vmemo;
    st_table *memo;
    st_data_t id;

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        elt = RARRAY_AREF(ary, i);
        tmp = rb_check_array_type(elt);
        if (!NIL_P(tmp)) {
            break;
        }
    }
    if (i == RARRAY_LEN(ary)) {
        return ary;
    } else if (tmp == ary) {
        rb_raise(rb_eArgError, "tried to flatten recursive array");
    }

    result = ary_new(0, RARRAY_LEN(ary));
    ary_memcpy(result, 0, i, RARRAY_CONST_PTR_TRANSIENT(ary));
    ARY_SET_LEN(result, i);

    stack = ary_new(0, ARY_DEFAULT_SIZE);
    rb_ary_push(stack, ary);
    rb_ary_push(stack, LONG2NUM(i + 1));

    vmemo = rb_hash_new();
    RBASIC_CLEAR_CLASS(vmemo);
    memo = st_init_numtable();
    rb_hash_st_table_set(vmemo, memo);
    st_insert(memo, (st_data_t)ary, (st_data_t)Qtrue);
    st_insert(memo, (st_data_t)tmp, (st_data_t)Qtrue);

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
                RB_GC_GUARD(vmemo);
                st_clear(memo);
		rb_raise(rb_eRuntimeError, "flatten reentered");
	    }
	    if (NIL_P(tmp)) {
		rb_ary_push(result, elt);
	    }
	    else {
		id = (st_data_t)tmp;
		if (st_is_member(memo, id)) {
                    st_clear(memo);
		    rb_raise(rb_eArgError, "tried to flatten recursive array");
		}
		st_insert(memo, id, (st_data_t)Qtrue);
		rb_ary_push(stack, ary);
		rb_ary_push(stack, LONG2NUM(i));
		ary = tmp;
		i = 0;
	    }
	}
	if (RARRAY_LEN(stack) == 0) {
	    break;
	}
	id = (st_data_t)ary;
	st_delete(memo, &id, 0);
	tmp = rb_ary_pop(stack);
	i = NUM2LONG(tmp);
	ary = rb_ary_pop(stack);
    }

    st_clear(memo);

    RBASIC_SET_CLASS(result, rb_obj_class(ary));
    return result;
}

/*
 *  call-seq:
 *     ary.flatten!        -> ary or nil
 *     ary.flatten!(level) -> ary or nil
 *
 *  Flattens +self+ in place.
 *
 *  Returns +nil+ if no modifications were made (i.e., the array contains no
 *  subarrays.)
 *
 *  The optional +level+ argument determines the level of recursion to flatten.
 *
 *     a = [ 1, 2, [3, [4, 5] ] ]
 *     a.flatten!   #=> [1, 2, 3, 4, 5]
 *     a.flatten!   #=> nil
 *     a            #=> [1, 2, 3, 4, 5]
 *     a = [ 1, 2, [3, [4, 5] ] ]
 *     a.flatten!(1) #=> [1, 2, 3, [4, 5]]
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
    if (!(mod = ARY_EMBED_P(result))) rb_obj_freeze(result);
    rb_ary_replace(ary, result);
    if (mod) ARY_SET_EMBED_LEN(result, 0);

    return ary;
}

/*
 *  call-seq:
 *     ary.flatten -> new_ary
 *     ary.flatten(level) -> new_ary
 *
 *  Returns a new array that is a one-dimensional flattening of +self+
 *  (recursively).
 *
 *  That is, for every element that is an array, extract its elements into
 *  the new array.
 *
 *  The optional +level+ argument determines the level of recursion to
 *  flatten.
 *
 *     s = [ 1, 2, 3 ]           #=> [1, 2, 3]
 *     t = [ 4, 5, 6, [7, 8] ]   #=> [4, 5, 6, [7, 8]]
 *     a = [ s, t, 9, 10 ]       #=> [[1, 2, 3], [4, 5, 6, [7, 8]], 9, 10]
 *     a.flatten                 #=> [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
 *     a = [ 1, 2, [3, [4, 5] ] ]
 *     a.flatten(1)              #=> [1, 2, 3, [4, 5]]
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
            if (len != RARRAY_LEN(ary) || ptr != RARRAY_CONST_PTR_TRANSIENT(ary)) {
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

static VALUE
rb_ary_sample(rb_execution_context_t *ec, VALUE ary, VALUE randgen, VALUE nv, VALUE to_array)
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
	return rb_ary_new_from_values(1, &RARRAY_AREF(ary, i));
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
        RARRAY_PTR_USE_TRANSIENT(result, ptr_result, {
	    for (i=0; i<n; i++) {
		ptr_result[i] = RARRAY_AREF(ary, idx[i]);
	    }
	});
    }
    else if (n <= memo_threshold / 2) {
	long max_idx = 0;
#undef RUBY_UNTYPED_DATA_WARNING
#define RUBY_UNTYPED_DATA_WARNING 0
	VALUE vmemo = Data_Wrap_Struct(0, 0, st_free_table, 0);
	st_table *memo = st_init_numtable_with_size(n);
	DATA_PTR(vmemo) = memo;
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
            RARRAY_PTR_USE_TRANSIENT(ary, ptr_ary, {
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
	DATA_PTR(vmemo) = 0;
	st_free_table(memo);
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
rb_ary_cycle_size(VALUE self, VALUE args, VALUE eobj)
{
    long mul;
    VALUE n = Qnil;
    if (args && (RARRAY_LEN(args) > 0)) {
	n = RARRAY_AREF(args, 0);
    }
    if (RARRAY_LEN(self) == 0) return INT2FIX(0);
    if (n == Qnil) return DBL2NUM(HUGE_VAL);
    mul = NUM2LONG(n);
    if (mul <= 0) return INT2FIX(0);
    n = LONG2FIX(mul);
    return rb_fix_mul_fix(rb_ary_length(self), n);
}

/*
 *  call-seq:
 *     ary.cycle(n=nil) {|obj| block}    -> nil
 *     ary.cycle(n=nil)                  -> Enumerator
 *
 *  Calls the given block for each element +n+ times or forever if +nil+ is
 *  given.
 *
 *  Does nothing if a non-positive number is given or the array is empty.
 *
 *  Returns +nil+ if the loop has finished without getting interrupted.
 *
 *  If no block is given, an Enumerator is returned instead.
 *
 *     a = ["a", "b", "c"]
 *     a.cycle {|x| puts x}       # print, a, b, c, a, b, c,.. forever.
 *     a.cycle(2) {|x| puts x}    # print, a, b, c, a, b, c.
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

#define tmpary(n) rb_ary_tmp_new(n)
#define tmpary_discard(a) (ary_discard(a), RBASIC_SET_CLASS_RAW(a, rb_cArray))

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
 * http://en.wikipedia.org/wiki/Pochhammer_symbol
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
 *     ary.permutation {|p| block}            -> ary
 *     ary.permutation                        -> Enumerator
 *     ary.permutation(n) {|p| block}         -> ary
 *     ary.permutation(n)                     -> Enumerator
 *
 * When invoked with a block, yield all permutations of length +n+ of the
 * elements of the array, then return the array itself.
 *
 * If +n+ is not specified, yield all permutations of all elements.
 *
 * The implementation makes no guarantees about the order in which the
 * permutations are yielded.
 *
 * If no block is given, an Enumerator is returned instead.
 *
 * Examples:
 *
 *   a = [1, 2, 3]
 *   a.permutation.to_a    #=> [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
 *   a.permutation(1).to_a #=> [[1],[2],[3]]
 *   a.permutation(2).to_a #=> [[1,2],[1,3],[2,1],[2,3],[3,1],[3,2]]
 *   a.permutation(3).to_a #=> [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]
 *   a.permutation(0).to_a #=> [[]] # one permutation of length 0
 *   a.permutation(4).to_a #=> []   # no permutations of length 4
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
 *     ary.combination(n) {|c| block}      -> ary
 *     ary.combination(n)                  -> Enumerator
 *
 * When invoked with a block, yields all combinations of length +n+ of elements
 * from the array and then returns the array itself.
 *
 * The implementation makes no guarantees about the order in which the
 * combinations are yielded.
 *
 * If no block is given, an Enumerator is returned instead.
 *
 * Examples:
 *
 *     a = [1, 2, 3, 4]
 *     a.combination(1).to_a  #=> [[1],[2],[3],[4]]
 *     a.combination(2).to_a  #=> [[1,2],[1,3],[1,4],[2,3],[2,4],[3,4]]
 *     a.combination(3).to_a  #=> [[1,2,3],[1,2,4],[1,3,4],[2,3,4]]
 *     a.combination(4).to_a  #=> [[1,2,3,4]]
 *     a.combination(0).to_a  #=> [[]] # one combination of length 0
 *     a.combination(5).to_a  #=> []   # no combinations of length 5
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
 *     ary.repeated_permutation(n) {|p| block}   -> ary
 *     ary.repeated_permutation(n)               -> Enumerator
 *
 * When invoked with a block, yield all repeated permutations of length +n+ of
 * the elements of the array, then return the array itself.
 *
 * The implementation makes no guarantees about the order in which the repeated
 * permutations are yielded.
 *
 * If no block is given, an Enumerator is returned instead.
 *
 * Examples:
 *
 *     a = [1, 2]
 *     a.repeated_permutation(1).to_a  #=> [[1], [2]]
 *     a.repeated_permutation(2).to_a  #=> [[1,1],[1,2],[2,1],[2,2]]
 *     a.repeated_permutation(3).to_a  #=> [[1,1,1],[1,1,2],[1,2,1],[1,2,2],
 *                                     #    [2,1,1],[2,1,2],[2,2,1],[2,2,2]]
 *     a.repeated_permutation(0).to_a  #=> [[]] # one permutation of length 0
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
 *     ary.repeated_combination(n) {|c| block}   -> ary
 *     ary.repeated_combination(n)               -> Enumerator
 *
 * When invoked with a block, yields all repeated combinations of length +n+ of
 * elements from the array and then returns the array itself.
 *
 * The implementation makes no guarantees about the order in which the repeated
 * combinations are yielded.
 *
 * If no block is given, an Enumerator is returned instead.
 *
 * Examples:
 *
 *   a = [1, 2, 3]
 *   a.repeated_combination(1).to_a  #=> [[1], [2], [3]]
 *   a.repeated_combination(2).to_a  #=> [[1,1],[1,2],[1,3],[2,2],[2,3],[3,3]]
 *   a.repeated_combination(3).to_a  #=> [[1,1,1],[1,1,2],[1,1,3],[1,2,2],[1,2,3],
 *                                   #    [1,3,3],[2,2,2],[2,2,3],[2,3,3],[3,3,3]]
 *   a.repeated_combination(4).to_a  #=> [[1,1,1,1],[1,1,1,2],[1,1,1,3],[1,1,2,2],[1,1,2,3],
 *                                   #    [1,1,3,3],[1,2,2,2],[1,2,2,3],[1,2,3,3],[1,3,3,3],
 *                                   #    [2,2,2,2],[2,2,2,3],[2,2,3,3],[2,3,3,3],[3,3,3,3]]
 *   a.repeated_combination(0).to_a  #=> [[]] # one combination of length 0
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
 *     ary.product(other_ary, ...)                -> new_ary
 *     ary.product(other_ary, ...) {|p| block}    -> ary
 *
 *  Returns an array of all combinations of elements from all arrays.
 *
 *  The length of the returned array is the product of the length of +self+ and
 *  the argument arrays.
 *
 *  If given a block, #product will yield all combinations and return +self+
 *  instead.
 *
 *     [1,2,3].product([4,5])     #=> [[1,4],[1,5],[2,4],[2,5],[3,4],[3,5]]
 *     [1,2].product([1,2])       #=> [[1,1],[1,2],[2,1],[2,2]]
 *     [1,2].product([3,4],[5,6]) #=> [[1,3,5],[1,3,6],[1,4,5],[1,4,6],
 *                                #     [2,3,5],[2,3,6],[2,4,5],[2,4,6]]
 *     [1,2].product()            #=> [[1],[2]]
 *     [1,2].product([])          #=> []
 */

static VALUE
rb_ary_product(int argc, VALUE *argv, VALUE ary)
{
    int n = argc+1;    /* How many arrays we're operating on */
    volatile VALUE t0 = tmpary(n);
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
	    FL_SET(t0, FL_USER5);
	    rb_yield(subarray);
	    if (! FL_TEST(t0, FL_USER5)) {
		rb_raise(rb_eRuntimeError, "product reentered");
	    }
	    else {
		FL_UNSET(t0, FL_USER5);
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
    tmpary_discard(t0);
    ALLOCV_END(t1);

    return NIL_P(result) ? ary : result;
}

/*
 *  call-seq:
 *     ary.take(n)               -> new_ary
 *
 *  Returns first +n+ elements from the array.
 *
 *  If a negative number is given, raises an ArgumentError.
 *
 *  See also Array#drop
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.take(3)             #=> [1, 2, 3]
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
 *     ary.take_while {|obj| block}    -> new_ary
 *     ary.take_while                  -> Enumerator
 *
 *  Passes elements to the block until the block returns +nil+ or +false+, then
 *  stops iterating and returns an array of all prior elements.
 *
 *  If no block is given, an Enumerator is returned instead.
 *
 *  See also Array#drop_while
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.take_while {|i| i < 3}    #=> [1, 2]
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
 *     ary.drop(n)               -> new_ary
 *
 *  Drops first +n+ elements from +ary+ and returns the rest of the elements in
 *  an array.
 *
 *  If a negative number is given, raises an ArgumentError.
 *
 *  See also Array#take
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.drop(3)             #=> [4, 5, 0]
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
    if (result == Qnil) result = rb_ary_new();
    return result;
}

/*
 *  call-seq:
 *     ary.drop_while {|obj| block}     -> new_ary
 *     ary.drop_while                  -> Enumerator
 *
 *  Drops elements up to, but not including, the first element for which the
 *  block returns +nil+ or +false+ and returns an array containing the
 *  remaining elements.
 *
 *  If no block is given, an Enumerator is returned instead.
 *
 *  See also Array#take_while
 *
 *     a = [1, 2, 3, 4, 5, 0]
 *     a.drop_while {|i| i < 3 }   #=> [3, 4, 5, 0]
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
 *     ary.any? [{|obj| block}  ]   -> true or false
 *     ary.any?(pattern)            -> true or false
 *
 *  See also Enumerable#any?
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
 *     ary.all? [{|obj| block}  ]   -> true or false
 *     ary.all?(pattern)            -> true or false
 *
 *  See also Enumerable#all?
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
 *     ary.none? [{|obj| block}  ]   -> true or false
 *     ary.none?(pattern)            -> true or false
 *
 *  See also Enumerable#none?
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
 *     ary.one? [{|obj| block}  ]   -> true or false
 *     ary.one?(pattern)            -> true or false
 *
 *  See also Enumerable#one?
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
 * call-seq:
 *   ary.dig(idx, ...)                 -> object
 *
 * Extracts the nested value specified by the sequence of <i>idx</i>
 * objects by calling +dig+ at each step, returning +nil+ if any
 * intermediate step is +nil+.
 *
 *   a = [[1, [2, 3]]]
 *
 *   a.dig(0, 1, 1)                    #=> 3
 *   a.dig(1, 2, 3)                    #=> nil
 *   a.dig(0, 0, 0)                    #=> TypeError: Integer does not have #dig method
 *   [42, {foo: :bar}].dig(1, :foo)    #=> :bar
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
    if (r != Qundef) {
	/* r can be an Integer when mathn is loaded */
	if (FIXNUM_P(r))
	    v = rb_fix_plus(r, v);
	else if (RB_TYPE_P(r, T_BIGNUM))
	    v = rb_big_plus(r, v);
	else
	    v = rb_rational_plus(r, v);
    }
    else if (!n && z) {
        v = rb_fix_plus(LONG2FIX(0), v);
    }
    return v;
}

/*
 * call-seq:
 *   ary.sum(init=0)                    -> number
 *   ary.sum(init=0) {|e| expr }        -> number
 *
 * Returns the sum of elements.
 * For example, [e1, e2, e3].sum returns init + e1 + e2 + e3.
 *
 * If a block is given, the block is applied to each element
 * before addition.
 *
 * If <i>ary</i> is empty, it returns <i>init</i>.
 *
 *   [].sum                             #=> 0
 *   [].sum(0.0)                        #=> 0.0
 *   [1, 2, 3].sum                      #=> 6
 *   [3, 5.5].sum                       #=> 8.5
 *   [2.5, 3.0].sum(0.0) {|e| e * e }   #=> 15.25
 *   [Object.new].sum                   #=> TypeError
 *
 * The (arithmetic) mean value of an array can be obtained as follows.
 *
 *   mean = ary.sum(0.0) / ary.length
 *
 * This method can be used for non-numeric objects by
 * explicit <i>init</i> argument.
 *
 *   ["a", "b", "c"].sum("")            #=> "abc"
 *   [[1], [[2]], [3]].sum([])          #=> [1, [2], 3]
 *
 * However, Array#join and Array#flatten is faster than Array#sum for
 * array of strings and array of arrays.
 *
 *   ["a", "b", "c"].join               #=> "abc"
 *   [[1], [[2]], [3]].flatten(1)       #=> [1, [2], 3]
 *
 *
 * Array#sum method may not respect method redefinition of "+" methods
 * such as Integer#+.
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
        else if (RB_TYPE_P(e, T_BIGNUM))
            v = rb_big_plus(e, v);
        else if (RB_TYPE_P(e, T_RATIONAL)) {
            if (r == Qundef)
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
         * See http://link.springer.com/article/10.1007/s00607-005-0139-x
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
            else if (RB_TYPE_P(e, T_BIGNUM))
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
    for (; i < RARRAY_LEN(ary); i++) {
        e = RARRAY_AREF(ary, i);
        if (block_given)
            e = rb_yield(e);
      has_some_value:
        v = rb_funcall(v, idPLUS, 1, e);
    }
    return v;
}

static VALUE
rb_ary_deconstruct(VALUE ary)
{
    return ary;
}

/*
 *  An \Array is an ordered, integer-indexed collection of objects,
 *  called _elements_.  Any object may be an \Array element.
 *
 *  == \Array Indexes
 *
 *  \Array indexing starts at 0, as in C or Java.
 *
 *  A positive index is an offset from the first element:
 *  - Index 0 indicates the first element.
 *  - Index 1 indicates the second element.
 *  - ...
 *
 *  A negative index is an offset, backwards, from the end of the array:
 *  - Index -1 indicates the last element.
 *  - Index -2 indicates the next-to-last element.
 *  - ...
 *
 *  A non-negative index is <i>in range</i> if it is smaller than
 *  the size of the array.  For a 3-element array:
 *  - Indexes 0 through 2 are in range.
 *  - Index 3 is out of range.
 *
 *  A negative index is <i>in range</i> if its absolute value is
 *  not larger than the size of the array.  For a 3-element array:
 *  - Indexes -1 through -3 are in range.
 *  - Index -4 is out of range.
 *
 *  == Creating Arrays
 *
 *  A new array can be created by using the literal constructor
 *  <code>[]</code>.  Arrays can contain different types of objects.  For
 *  example, the array below contains an Integer, a String and a Float:
 *
 *     ary = [1, "two", 3.0] #=> [1, "two", 3.0]
 *
 *  An array can also be created by explicitly calling Array.new with zero, one
 *  (the initial size of the Array) or two arguments (the initial size and a
 *  default object).
 *
 *     ary = Array.new    #=> []
 *     Array.new(3)       #=> [nil, nil, nil]
 *     Array.new(3, true) #=> [true, true, true]
 *
 *  Note that the second argument populates the array with references to the
 *  same object.  Therefore, it is only recommended in cases when you need to
 *  instantiate arrays with natively immutable objects such as Symbols,
 *  numbers, true or false.
 *
 *  To create an array with separate objects a block can be passed instead.
 *  This method is safe to use with mutable objects such as hashes, strings or
 *  other arrays:
 *
 *     Array.new(4) {Hash.new}    #=> [{}, {}, {}, {}]
 *     Array.new(4) {|i| i.to_s } #=> ["0", "1", "2", "3"]
 *
 *  This is also a quick way to build up multi-dimensional arrays:
 *
 *     empty_table = Array.new(3) {Array.new(3)}
 *     #=> [[nil, nil, nil], [nil, nil, nil], [nil, nil, nil]]
 *
 *  An array can also be created by using the Array() method, provided by
 *  Kernel, which tries to call #to_ary, then #to_a on its argument.
 *
 *	Array({:a => "a", :b => "b"}) #=> [[:a, "a"], [:b, "b"]]
 *
 *  == Example Usage
 *
 *  In addition to the methods it mixes in through the Enumerable module, the
 *  Array class has proprietary methods for accessing, searching and otherwise
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
 *  == Obtaining Information about an Array
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
 *  == Removing Items from an Array
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
 *  Like all classes that include the Enumerable module, Array has an each
 *  method, which defines what elements should be iterated over and how.  In
 *  case of Array's #each, all elements in the Array instance are yielded to
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
 *  == Selecting Items from an Array
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
 */

void
Init_Array(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    rb_cArray  = rb_define_class("Array", rb_cObject);
    rb_include_module(rb_cArray, rb_mEnumerable);

    rb_define_alloc_func(rb_cArray, empty_ary_alloc);
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
    rb_define_method(rb_cArray, "first", rb_ary_first, -1);
    rb_define_method(rb_cArray, "last", rb_ary_last, -1);
    rb_define_method(rb_cArray, "concat", rb_ary_concat_multi, -1);
    rb_define_method(rb_cArray, "union", rb_ary_union_multi, -1);
    rb_define_method(rb_cArray, "difference", rb_ary_difference_multi, -1);
    rb_define_method(rb_cArray, "intersection", rb_ary_intersection_multi, -1);
    rb_define_method(rb_cArray, "<<", rb_ary_push, 1);
    rb_define_method(rb_cArray, "push", rb_ary_push_m, -1);
    rb_define_alias(rb_cArray,  "append", "push");
    rb_define_method(rb_cArray, "pop", rb_ary_pop_m, -1);
    rb_define_method(rb_cArray, "shift", rb_ary_shift_m, -1);
    rb_define_method(rb_cArray, "unshift", rb_ary_unshift_m, -1);
    rb_define_alias(rb_cArray,  "prepend", "unshift");
    rb_define_method(rb_cArray, "insert", rb_ary_insert, -1);
    rb_define_method(rb_cArray, "each", rb_ary_each, 0);
    rb_define_method(rb_cArray, "each_index", rb_ary_each_index, 0);
    rb_define_method(rb_cArray, "reverse_each", rb_ary_reverse_each, 0);
    rb_define_method(rb_cArray, "length", rb_ary_length, 0);
    rb_define_alias(rb_cArray,  "size", "length");
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

    rb_define_method(rb_cArray, "deconstruct", rb_ary_deconstruct, 0);
}

#include "array.rbinc"
