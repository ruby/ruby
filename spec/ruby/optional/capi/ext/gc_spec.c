#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE registered_tagged_value;
VALUE registered_reference_value;

static VALUE registered_tagged_address(VALUE self) {
  return registered_tagged_value;
}

static VALUE registered_reference_address(VALUE self) {
  return registered_reference_value;
}

static VALUE gc_spec_rb_gc_enable() {
  return rb_gc_enable();
}

static VALUE gc_spec_rb_gc_disable() {
  return rb_gc_disable();
}

static VALUE gc_spec_rb_gc() {
  rb_gc();
  return Qnil;
}

static VALUE gc_spec_rb_gc_adjust_memory_usage(VALUE self, VALUE diff) {
  rb_gc_adjust_memory_usage(NUM2SSIZET(diff));
  return Qnil;
}

void Init_gc_spec(void) {
  VALUE cls = rb_define_class("CApiGCSpecs", rb_cObject);
  registered_tagged_value    = INT2NUM(10);
  registered_reference_value = rb_str_new2("Globally registered data");

  rb_gc_register_address(&registered_tagged_value);
  rb_gc_register_address(&registered_reference_value);

  rb_define_method(cls, "registered_tagged_address", registered_tagged_address, 0);
  rb_define_method(cls, "registered_reference_address", registered_reference_address, 0);
  rb_define_method(cls, "rb_gc_enable", gc_spec_rb_gc_enable, 0);
  rb_define_method(cls, "rb_gc_disable", gc_spec_rb_gc_disable, 0);
  rb_define_method(cls, "rb_gc", gc_spec_rb_gc, 0);
  rb_define_method(cls, "rb_gc_adjust_memory_usage", gc_spec_rb_gc_adjust_memory_usage, 1);
}

#ifdef __cplusplus
}
#endif
