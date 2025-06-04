#include "ruby/ruby.h"
#include "ruby/debug.h"

static VALUE
callback(const rb_debug_inspector_t *dbg_context, void *data)
{
    long i, len = rb_debug_inspector_frame_count(dbg_context);
    VALUE binds = rb_ary_new();
    for (i = 0; i < len; ++i) {
        VALUE entry = rb_ary_new();
        rb_ary_push(binds, entry);
        rb_ary_push(entry, rb_debug_inspector_frame_self_get(dbg_context, i));
        rb_ary_push(entry, rb_debug_inspector_frame_binding_get(dbg_context, i));
        rb_ary_push(entry, rb_debug_inspector_frame_class_get(dbg_context, i));
        rb_ary_push(entry, rb_debug_inspector_frame_iseq_get(dbg_context, i));
        rb_ary_push(entry, rb_debug_inspector_frame_loc_get(dbg_context, i));
    }
    return binds;
}

static VALUE
debug_inspector(VALUE self)
{
    return rb_debug_inspector_open(callback, NULL);
}

void
Init_inspector(VALUE klass)
{
    rb_define_module_function(klass, "inspector", debug_inspector, 0);
}
