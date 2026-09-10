#include <ruby.h>
#include <ruby/atomic.h>

/*
 * A T_DATA type whose free function is declared RUBY_TYPED_FREE_IMMEDIATELY but
 * deliberately NOT RUBY_TYPED_THREAD_SAFE_FREE. Without that flag the GC must
 * not invoke dfree concurrently with another dfree, even though Ractor-local GC
 * lets several Ractors mark/sweep in parallel. A genuinely non-thread-safe dfree
 * would touch shared process state without a lock and corrupt it under concurrent
 * invocation. Here we measure the unsafe precondition by counting how many threads
 * are inside the free at the same instant.
 */

static rb_atomic_t in_free_now;
static rb_atomic_t max_concurrent_free;
static rb_atomic_t total_frees;

/* How long to hold the free window open, in atomic-load spins, so a concurrent
 * free on another Ractor becomes observable. */
#define OVERLAP_WINDOW 128

static void
non_thread_safe_free(void *ptr)
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

    RUBY_ATOMIC_FETCH_SUB(in_free_now, 1);
    RUBY_ATOMIC_FETCH_ADD(total_frees, 1);

    xfree(ptr);
}

typedef struct {
    int payload;
} test_data;

static const rb_data_type_t non_thread_safe_free_type = {
    "tdata_non_thread_safe_free",
    {0, non_thread_safe_free, 0},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY, /* intentionally NOT RUBY_TYPED_THREAD_SAFE_FREE */
};

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
test_reset(VALUE klass)
{
    RUBY_ATOMIC_SET(in_free_now, 0);
    RUBY_ATOMIC_SET(max_concurrent_free, 0);
    RUBY_ATOMIC_SET(total_frees, 0);
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
    rb_define_singleton_method(klass, "max_concurrent_free", test_max_concurrent_free, 0);
    rb_define_singleton_method(klass, "total_frees", test_total_frees, 0);
    rb_define_singleton_method(klass, "reset", test_reset, 0);
}
