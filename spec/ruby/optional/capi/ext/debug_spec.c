#include "ruby.h"
#include "rubyspec.h"
#include "ruby/debug.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE callback_data = Qfalse;

static VALUE rb_debug_inspector_open_callback(const rb_debug_inspector_t *dc, void *ptr) {
    if (!dc) {
      rb_raise(rb_eRuntimeError, "rb_debug_inspector_t should not be NULL");
    }

    VALUE locations = rb_debug_inspector_backtrace_locations(dc);
    int len = RARRAY_LENINT(locations);
    VALUE results = rb_ary_new2(len);
    for (int i = 0; i < len; i++) {
        VALUE ary = rb_ary_new2(5); // [self, klass, binding, iseq, backtrace_location]
        rb_ary_store(ary, 0, rb_debug_inspector_frame_self_get(dc, i));
        rb_ary_store(ary, 1, rb_debug_inspector_frame_class_get(dc, i));
        rb_ary_store(ary, 2, rb_debug_inspector_frame_binding_get(dc, i));
        rb_ary_store(ary, 3, rb_debug_inspector_frame_iseq_get(dc, i));
        rb_ary_store(ary, 4, rb_ary_entry(locations, i));
        rb_ary_push(results, ary);
    }
    callback_data = (VALUE)ptr;
    return results;
}

static VALUE rb_debug_inspector_frame_self_get_callback(const rb_debug_inspector_t *dc, void *ptr) {
  return rb_debug_inspector_frame_self_get(dc, NUM2LONG((VALUE) ptr));
}

static VALUE rb_debug_inspector_frame_class_get_callback(const rb_debug_inspector_t *dc, void *ptr) {
  return rb_debug_inspector_frame_class_get(dc, NUM2LONG((VALUE) ptr));
}

static VALUE rb_debug_inspector_frame_binding_get_callback(const rb_debug_inspector_t *dc, void *ptr) {
  return rb_debug_inspector_frame_binding_get(dc, NUM2LONG((VALUE) ptr));
}

static VALUE rb_debug_inspector_frame_iseq_get_callback(const rb_debug_inspector_t *dc, void *ptr) {
  return rb_debug_inspector_frame_iseq_get(dc, NUM2LONG((VALUE) ptr));
}

static VALUE debug_spec_callback_data(VALUE self) {
  return callback_data;
}

VALUE debug_spec_rb_debug_inspector_open(VALUE self, VALUE index) {
  return rb_debug_inspector_open(rb_debug_inspector_open_callback, (void *)index);
}

VALUE debug_spec_rb_debug_inspector_frame_self_get(VALUE self, VALUE index) {
  return rb_debug_inspector_open(rb_debug_inspector_frame_self_get_callback, (void *)index);
}

VALUE debug_spec_rb_debug_inspector_frame_class_get(VALUE self, VALUE index) {
  return rb_debug_inspector_open(rb_debug_inspector_frame_class_get_callback, (void *)index);
}

VALUE debug_spec_rb_debug_inspector_frame_binding_get(VALUE self, VALUE index) {
  return rb_debug_inspector_open(rb_debug_inspector_frame_binding_get_callback, (void *)index);
}

VALUE debug_spec_rb_debug_inspector_frame_iseq_get(VALUE self, VALUE index) {
  return rb_debug_inspector_open(rb_debug_inspector_frame_iseq_get_callback, (void *)index);
}

static VALUE rb_debug_inspector_backtrace_locations_func(const rb_debug_inspector_t *dc, void *ptr) {
  return rb_debug_inspector_backtrace_locations(dc);
}

VALUE debug_spec_rb_debug_inspector_backtrace_locations(VALUE self) {
  return rb_debug_inspector_open(rb_debug_inspector_backtrace_locations_func, (void *)self);
}

void Init_debug_spec(void) {
  VALUE cls = rb_define_class("CApiDebugSpecs", rb_cObject);
  rb_define_method(cls, "rb_debug_inspector_open", debug_spec_rb_debug_inspector_open, 1);
  rb_define_method(cls, "rb_debug_inspector_frame_self_get", debug_spec_rb_debug_inspector_frame_self_get, 1);
  rb_define_method(cls, "rb_debug_inspector_frame_class_get", debug_spec_rb_debug_inspector_frame_class_get, 1);
  rb_define_method(cls, "rb_debug_inspector_frame_binding_get", debug_spec_rb_debug_inspector_frame_binding_get, 1);
  rb_define_method(cls, "rb_debug_inspector_frame_iseq_get", debug_spec_rb_debug_inspector_frame_iseq_get, 1);
  rb_define_method(cls, "rb_debug_inspector_backtrace_locations", debug_spec_rb_debug_inspector_backtrace_locations, 0);
  rb_define_method(cls, "debug_spec_callback_data", debug_spec_callback_data, 0);
}

#ifdef __cplusplus
}
#endif
