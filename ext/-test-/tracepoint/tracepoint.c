#include "ruby/ruby.h"
#include "ruby/debug.h"

static size_t newobj_count;
static size_t free_count;
static size_t gc_start_count;
static size_t gc_end_count;
static size_t objects_count;
static VALUE objects[10];

void
tracepoint_track_objspace_events_i(VALUE tpval, void *data)
{
    rb_trace_arg_t *tparg = rb_tracearg_from_tracepoint(tpval);
    switch (rb_tracearg_event_flag(tparg)) {
      case RUBY_INTERNAL_EVENT_NEWOBJ:
	{
	    VALUE obj = rb_tracearg_object(tparg);
	    if (objects_count < sizeof(objects)/sizeof(VALUE)) objects[objects_count++] = obj;
	    newobj_count++;
	    break;
	}
      case RUBY_INTERNAL_EVENT_FREEOBJ:
	{
	    free_count++;
	    break;
	}
      case RUBY_INTERNAL_EVENT_GC_START:
	{
	    gc_start_count++;
	    break;
	}
      case RUBY_INTERNAL_EVENT_GC_END:
	{
	    gc_end_count++;
	    break;
	}
      default:
	rb_raise(rb_eRuntimeError, "unknown event");
    }
}

VALUE
tracepoint_track_objspace_events(VALUE self)
{
    VALUE tpval = rb_tracepoint_new(0, RUBY_INTERNAL_EVENT_NEWOBJ | RUBY_INTERNAL_EVENT_FREEOBJ |
				    RUBY_INTERNAL_EVENT_GC_START | RUBY_INTERNAL_EVENT_GC_END,
				    tracepoint_track_objspace_events_i, 0);
    VALUE result = rb_ary_new();
    size_t i;

    newobj_count = free_count = gc_start_count = objects_count = 0;

    rb_tracepoint_enable(tpval);
    rb_yield(Qundef);
    rb_tracepoint_disable(tpval);

    rb_ary_push(result, SIZET2NUM(newobj_count));
    rb_ary_push(result, SIZET2NUM(free_count));
    rb_ary_push(result, SIZET2NUM(gc_start_count));
    rb_ary_push(result, SIZET2NUM(gc_end_count));
    for (i=0; i<objects_count; i++) {
	rb_ary_push(result, objects[i]);
    }

    return result;
}

void
Init_tracepoint(void)
{
    size_t i;
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "tracepoint_track_objspace_events", tracepoint_track_objspace_events, 0);
    for (i=0; i<sizeof(objects)/sizeof(VALUE); i++) {
	rb_global_variable(objects+i);
    }
}
