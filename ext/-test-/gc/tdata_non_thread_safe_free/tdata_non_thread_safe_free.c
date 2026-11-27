#include <ruby.h>
#include <ruby/atomic.h>

/*
 * T_DATA types whose free functions are declared RUBY_TYPED_FREE_IMMEDIATELY but
 * deliberately NOT RUBY_TYPED_THREAD_SAFE_FREE. Without that flag the GC must
 * not invoke dfree concurrently with another dfree, even though Ractor-local GC
 * lets several Ractors mark/sweep in parallel. A genuinely non-thread-safe dfree
 * would touch shared process state without a lock and corrupt it under concurrent
 * invocation. Here we measure the unsafe precondition by counting how many threads
 * are inside the free at the same instant.
 *
 * A plain one plus an embeddable pair, small enough that the payload would fit in the
 * slot.  A deferred free has to outlive the slot, so the non-thread-safe half of the
 * pair must be denied embedding; the thread-safe half is identical apart from the flag
 * and must still be embedded.  A fourth wraps a NULL payload, which gets no dfree at all.
 */

static rb_atomic_t in_free_now;
static rb_atomic_t max_concurrent_free;
static rb_atomic_t total_frees;
static rb_atomic_t embeddable_frees;
static rb_atomic_t null_payload_frees;
static rb_atomic_t null_payload_null_frees;

/* How long to hold the free window open, in atomic-load spins, so a concurrent
 * free on another Ractor becomes observable. */
#define OVERLAP_WINDOW 128

static void
free_enter(void)
{
    rb_atomic_t cur = RUBY_ATOMIC_FETCH_ADD(in_free_now, 1) + 1;

    rb_atomic_t prev;
    do {
        prev = RUBY_ATOMIC_LOAD(max_concurrent_free);
        if (cur <= prev) break;
    } while (RUBY_ATOMIC_CAS(max_concurrent_free, prev, cur) != prev);

    for (int i = 0; i < OVERLAP_WINDOW; i++) {
        if (RUBY_ATOMIC_LOAD(in_free_now) >= 2) break;
    }
}

static void
free_leave(rb_atomic_t *counter)
{
    RUBY_ATOMIC_FETCH_SUB(in_free_now, 1);
    RUBY_ATOMIC_FETCH_ADD(*counter, 1);
}

static void
non_thread_safe_free(void *ptr)
{
    free_enter();
    free_leave(&total_frees);
    xfree(ptr);
}

/* No xfree: the GC frees the buffer of an embeddable type that was not embedded. */
static void
non_thread_safe_free_embeddable(void *ptr)
{
    free_enter();
    free_leave(&embeddable_frees);
}

static void
thread_safe_free_embeddable(void *ptr)
{
    /* Only here to make the control type differ from the one above by its flags alone. */
}

typedef struct {
    int payload;
} test_data;

typedef struct {
    char payload[8];
} embeddable_data;

/* intentionally NOT RUBY_TYPED_THREAD_SAFE_FREE */
static const rb_data_type_t non_thread_safe_free_type = {
    "tdata_non_thread_safe_free",
    {0, non_thread_safe_free, 0},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static const rb_data_type_t non_thread_safe_free_embeddable_type = {
    "tdata_non_thread_safe_free_embeddable",
    {0, non_thread_safe_free_embeddable, 0},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_EMBEDDABLE,
};

static const rb_data_type_t thread_safe_free_embeddable_type = {
    "tdata_thread_safe_free_embeddable",
    {0, thread_safe_free_embeddable, 0},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_THREAD_SAFE_FREE | RUBY_TYPED_EMBEDDABLE,
};

/* Mirrors an allocator that wraps a NULL pointer and fills it in during initialize.
 * rb_data_free runs no dfree at all for a NULL payload, so the deferred free path must
 * not queue one either; null_payload_null_frees counts the calls that must never happen. */
static void
null_payload_free(void *ptr)
{
    if (ptr == NULL) {
        RUBY_ATOMIC_FETCH_ADD(null_payload_null_frees, 1);
        return;
    }
    free_enter();
    free_leave(&null_payload_frees);
    xfree(ptr);
}

/* intentionally NOT RUBY_TYPED_THREAD_SAFE_FREE */
static const rb_data_type_t null_payload_type = {
    "tdata_null_payload",
    {0, null_payload_free, 0},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cEmbeddable, cThreadSafeEmbeddable, cNullPayload;

static bool
embedded_p(VALUE obj)
{
    return RTYPEDDATA_GET_DATA(obj) == (void *)&RTYPEDDATA(obj)->data;
}

static VALUE
test_alloc(VALUE klass)
{
    test_data *data;
    return TypedData_Make_Struct(klass, test_data, &non_thread_safe_free_type, data);
}

static VALUE
test_make(VALUE klass, VALUE num)
{
    unsigned long i, n = NUM2ULONG(num);
    for (i = 0; i < n; i++) {
        test_alloc(klass);
    }
    return Qnil;
}

static VALUE
test_make_embeddable(VALUE klass, VALUE num)
{
    unsigned long i, n = NUM2ULONG(num);
    for (i = 0; i < n; i++) {
        embeddable_data *data;
        TypedData_Make_Struct(cEmbeddable, embeddable_data,
                              &non_thread_safe_free_embeddable_type, data);
    }
    return Qnil;
}

static VALUE
test_embeddable_embedded_p(VALUE klass)
{
    embeddable_data *data;
    VALUE obj = TypedData_Make_Struct(cEmbeddable, embeddable_data,
                                      &non_thread_safe_free_embeddable_type, data);
    return embedded_p(obj) ? Qtrue : Qfalse;
}

static VALUE
test_thread_safe_embeddable_embedded_p(VALUE klass)
{
    embeddable_data *data;
    VALUE obj = TypedData_Make_Struct(cThreadSafeEmbeddable, embeddable_data,
                                      &thread_safe_free_embeddable_type, data);
    return embedded_p(obj) ? Qtrue : Qfalse;
}

static VALUE
null_payload_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &null_payload_type, 0);
}

static VALUE
test_make_null_payload(VALUE klass, VALUE num)
{
    unsigned long i, n = NUM2ULONG(num);
    for (i = 0; i < n; i++) {
        null_payload_alloc(cNullPayload);
    }
    return Qnil;
}

/* The same type carrying a real payload, so a test can tell "dfree was never called with
 * NULL" apart from "dfree was never called". */
static VALUE
test_make_filled_payload(VALUE klass, VALUE num)
{
    unsigned long i, n = NUM2ULONG(num);
    for (i = 0; i < n; i++) {
        test_data *data;
        TypedData_Make_Struct(cNullPayload, test_data, &null_payload_type, data);
    }
    return Qnil;
}

static VALUE
test_null_payload_frees(VALUE klass)
{
    return UINT2NUM(RUBY_ATOMIC_LOAD(null_payload_frees));
}

static VALUE
test_null_payload_null_frees(VALUE klass)
{
    return UINT2NUM(RUBY_ATOMIC_LOAD(null_payload_null_frees));
}

static VALUE
test_max_concurrent_free(VALUE klass)
{
    return UINT2NUM(RUBY_ATOMIC_LOAD(max_concurrent_free));
}

static VALUE
test_total_frees(VALUE klass)
{
    return UINT2NUM(RUBY_ATOMIC_LOAD(total_frees));
}

static VALUE
test_embeddable_frees(VALUE klass)
{
    return UINT2NUM(RUBY_ATOMIC_LOAD(embeddable_frees));
}

static VALUE
test_reset(VALUE klass)
{
    RUBY_ATOMIC_SET(in_free_now, 0);
    RUBY_ATOMIC_SET(max_concurrent_free, 0);
    RUBY_ATOMIC_SET(total_frees, 0);
    RUBY_ATOMIC_SET(embeddable_frees, 0);
    RUBY_ATOMIC_SET(null_payload_frees, 0);
    RUBY_ATOMIC_SET(null_payload_null_frees, 0);
    return Qnil;
}

void
Init_tdata_non_thread_safe_free(void)
{
    rb_ext_ractor_safe(true);

    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_class_under(mBug, "TDataNonThreadSafeFree", rb_cObject);
    rb_define_alloc_func(klass, test_alloc);
    rb_define_singleton_method(klass, "make", test_make, 1);
    rb_define_singleton_method(klass, "make_embeddable", test_make_embeddable, 1);
    rb_define_singleton_method(klass, "embeddable_embedded?", test_embeddable_embedded_p, 0);
    rb_define_singleton_method(klass, "thread_safe_embeddable_embedded?",
                               test_thread_safe_embeddable_embedded_p, 0);
    rb_define_singleton_method(klass, "max_concurrent_free", test_max_concurrent_free, 0);
    rb_define_singleton_method(klass, "total_frees", test_total_frees, 0);
    rb_define_singleton_method(klass, "embeddable_frees", test_embeddable_frees, 0);
    rb_define_singleton_method(klass, "make_null_payload", test_make_null_payload, 1);
    rb_define_singleton_method(klass, "make_filled_payload", test_make_filled_payload, 1);
    rb_define_singleton_method(klass, "null_payload_frees", test_null_payload_frees, 0);
    rb_define_singleton_method(klass, "null_payload_null_frees",
                               test_null_payload_null_frees, 0);
    rb_define_singleton_method(klass, "reset", test_reset, 0);

    rb_gc_register_address(&cEmbeddable);
    rb_gc_register_address(&cThreadSafeEmbeddable);
    rb_gc_register_address(&cNullPayload);
    cEmbeddable = rb_define_class_under(klass, "Embeddable", rb_cObject);
    cThreadSafeEmbeddable = rb_define_class_under(klass, "ThreadSafeEmbeddable", rb_cObject);
    cNullPayload = rb_define_class_under(klass, "NullPayload", rb_cObject);
    rb_define_alloc_func(cNullPayload, null_payload_alloc);
    /* Wrapped but never allocated from Ruby: without this the first wrap trips
     * rb_data_object_check, which undefines the inherited allocator and warns. */
    rb_undef_alloc_func(cEmbeddable);
    rb_undef_alloc_func(cThreadSafeEmbeddable);
}
