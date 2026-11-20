#include "ruby.h"
#include "internal/gc.h"
#include "internal/string.h"

static VALUE
bug_str_capacity(VALUE klass, VALUE str)
{
    if (!STR_EMBED_P(str) && STR_SHARED_P(str)) {
        return INT2FIX(0);
    }

    return LONG2FIX(rb_str_capacity(str));
}

static VALUE
bug_str_new_shared(VALUE klass, VALUE str)
{
    return rb_str_new_shared(str);
}

static VALUE
bug_str_tmp_frozen_acquire_release(VALUE klass, VALUE str)
{
    VALUE tmp = rb_str_tmp_frozen_acquire(str);
    rb_str_tmp_frozen_release(str, tmp);
    return str;
}

static VALUE
bug_str_no_gvl_safe_acquire_release(VALUE klass, VALUE str)
{
    VALUE tmp = rb_str_no_gvl_safe_acquire(str);
    rb_str_no_gvl_safe_release(str, tmp);
    return str;
}

static bool
ptr_in_slot_p(const char *ptr, VALUE obj)
{
    const char *slot = (const char *)obj;
    return slot <= ptr && ptr < slot + rb_gc_obj_slot_size(obj);
}

static VALUE
bug_str_no_gvl_safe_acquire_in_gc_slot_p(VALUE klass, VALUE str)
{
    VALUE tmp = rb_str_no_gvl_safe_acquire(str);
    const char *ptr = RSTRING_PTR(tmp);
    bool in_slot = ptr_in_slot_p(ptr, tmp) ||
        (STR_SHARED_P(tmp) && ptr_in_slot_p(ptr, RSTRING(tmp)->as.heap.aux.shared));
    rb_str_no_gvl_safe_release(str, tmp);
    return in_slot ? Qtrue : Qfalse;
}

static VALUE
bug_str_no_gvl_safe_acquire_terminated_p(VALUE klass, VALUE str)
{
    /* Free a dirty chunk the size of the copy, which malloc is likely to
     * return next. */
    char *garbage = ruby_xmalloc(RSTRING_LEN(str) + 1);
    memset(garbage, 'x', RSTRING_LEN(str) + 1);
    ruby_xfree(garbage);

    VALUE tmp = rb_str_no_gvl_safe_acquire(str);
    bool terminated = *RSTRING_END(tmp) == '\0';
    rb_str_no_gvl_safe_release(str, tmp);
    return terminated ? Qtrue : Qfalse;
}

void
Init_string_capacity(VALUE klass)
{
    rb_define_singleton_method(klass, "capacity", bug_str_capacity, 1);
    rb_define_singleton_method(klass, "rb_str_new_shared", bug_str_new_shared, 1);
    rb_define_singleton_method(klass, "tmp_frozen_acquire_release", bug_str_tmp_frozen_acquire_release, 1);
    rb_define_singleton_method(klass, "no_gvl_safe_acquire_release", bug_str_no_gvl_safe_acquire_release, 1);
    rb_define_singleton_method(klass, "no_gvl_safe_acquire_in_gc_slot?", bug_str_no_gvl_safe_acquire_in_gc_slot_p, 1);
    rb_define_singleton_method(klass, "no_gvl_safe_acquire_terminated?", bug_str_no_gvl_safe_acquire_terminated_p, 1);
}
