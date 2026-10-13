#include "ruby.h"
#include "internal/gc.h"

/* GC.disable continues the cycle in progress (rb_gc_disable calls rb_gc_impl_gc_rest), so it
 * cannot guard a window that has to stay mid-mark. These expose the other variant: it suppresses
 * collection for the calling Ractor's objspace alone and leaves an incremental cycle running.
 * Used by the ractor-local incremental marking tests. */

static VALUE
gc_local_disable_no_rest(VALUE self)
{
    return rb_gc_local_disable_no_rest();
}

static VALUE
gc_local_enable(VALUE self)
{
    return rb_gc_local_enable();
}

void
Init_disable(void)
{
    rb_ext_ractor_safe(true);

    VALUE mBug = rb_define_module("Bug");
    VALUE mGC = rb_define_module_under(mBug, "GC");
    rb_define_singleton_method(mGC, "local_disable_no_rest", gc_local_disable_no_rest, 0);
    rb_define_singleton_method(mGC, "local_enable", gc_local_enable, 0);
}
