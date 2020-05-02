#include "ruby.h"
#include "rubyspec.h"

#include <ruby/debug.h>

#ifdef __cplusplus
extern "C" {
#endif

static VALUE callback_called = Qnil;

static void callback(VALUE tpval, void *data) {
  callback_called = (VALUE) data;
}

static VALUE tracepoint_spec_rb_tracepoint_new(VALUE self, VALUE data) {
  return rb_tracepoint_new(Qnil, RUBY_EVENT_LINE, callback, (void*) data);
}

static VALUE tracepoint_spec_callback_called(VALUE self){
  return callback_called;
}

static VALUE tracepoint_spec_rb_tracepoint_disable(VALUE self, VALUE trace) {
  rb_tracepoint_disable(trace);
  return rb_tracepoint_enabled_p(trace);
}

static VALUE tracepoint_spec_rb_tracepoint_enable(VALUE self, VALUE trace) {
  rb_tracepoint_enable(trace);
  return rb_tracepoint_enabled_p(trace);
}

static VALUE tracepoint_spec_rb_tracepoint_enabled_p(VALUE self, VALUE trace) {
  return rb_tracepoint_enabled_p(trace);
}

void Init_tracepoint_spec(void) {
  VALUE cls = rb_define_class("CApiTracePointSpecs", rb_cObject);
  rb_define_method(cls, "rb_tracepoint_new", tracepoint_spec_rb_tracepoint_new, 1);
  rb_define_method(cls, "rb_tracepoint_disable", tracepoint_spec_rb_tracepoint_disable, 1);
  rb_define_method(cls, "rb_tracepoint_enable", tracepoint_spec_rb_tracepoint_enable, 1);
  rb_define_method(cls, "rb_tracepoint_enabled_p", tracepoint_spec_rb_tracepoint_enabled_p, 1);
  rb_define_method(cls, "callback_called?", tracepoint_spec_callback_called, 0);
}

#ifdef __cplusplus
}
#endif
