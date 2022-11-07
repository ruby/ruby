#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE registered_tagged_value;
VALUE registered_reference_value;
VALUE registered_before_rb_gc_register_address;
VALUE registered_before_rb_global_variable;
VALUE rb_gc_register_address_outside_init;

static VALUE registered_tagged_address(VALUE self) {
  return registered_tagged_value;
}

static VALUE registered_reference_address(VALUE self) {
  return registered_reference_value;
}

static VALUE get_registered_before_rb_gc_register_address(VALUE self) {
  return registered_before_rb_gc_register_address;
}

static VALUE get_registered_before_rb_global_variable(VALUE self) {
  return registered_before_rb_global_variable;
}

static VALUE gc_spec_rb_gc_register_address(VALUE self) {
  rb_gc_register_address_outside_init = rb_str_new_cstr("rb_gc_register_address() outside Init_");
  rb_gc_register_address(&rb_gc_register_address_outside_init);
  return rb_gc_register_address_outside_init;
}

static VALUE gc_spec_rb_gc_unregister_address(VALUE self) {
  rb_gc_unregister_address(&rb_gc_register_address_outside_init);
  return Qnil;
}

static VALUE gc_spec_rb_gc_enable(VALUE self) {
  return rb_gc_enable();
}

static VALUE gc_spec_rb_gc_disable(VALUE self) {
  return rb_gc_disable();
}

static VALUE gc_spec_rb_gc(VALUE self) {
  rb_gc();
  return Qnil;
}

static VALUE gc_spec_rb_gc_latest_gc_info(VALUE self, VALUE hash_or_key){
  return rb_gc_latest_gc_info(hash_or_key);
}

static VALUE gc_spec_rb_gc_adjust_memory_usage(VALUE self, VALUE diff) {
  rb_gc_adjust_memory_usage(NUM2SSIZET(diff));
  return Qnil;
}

static VALUE gc_spec_rb_gc_register_mark_object(VALUE self, VALUE obj) {
  rb_gc_register_mark_object(obj);
  return Qnil;
}

void Init_gc_spec(void) {
  VALUE cls = rb_define_class("CApiGCSpecs", rb_cObject);
  registered_tagged_value    = INT2NUM(10);
  registered_reference_value = rb_str_new2("Globally registered data");

  rb_gc_register_address(&registered_tagged_value);
  rb_gc_register_address(&registered_reference_value);
  rb_gc_register_address(&registered_before_rb_gc_register_address);
  rb_global_variable(&registered_before_rb_global_variable);

  registered_before_rb_gc_register_address = rb_str_new_cstr("registered before rb_gc_register_address()");
  registered_before_rb_global_variable = rb_str_new_cstr("registered before rb_global_variable()");

  rb_define_method(cls, "registered_tagged_address", registered_tagged_address, 0);
  rb_define_method(cls, "registered_reference_address", registered_reference_address, 0);
  rb_define_method(cls, "registered_before_rb_gc_register_address", get_registered_before_rb_gc_register_address, 0);
  rb_define_method(cls, "registered_before_rb_global_variable", get_registered_before_rb_global_variable, 0);
  rb_define_method(cls, "rb_gc_register_address", gc_spec_rb_gc_register_address, 0);
  rb_define_method(cls, "rb_gc_unregister_address", gc_spec_rb_gc_unregister_address, 0);
  rb_define_method(cls, "rb_gc_enable", gc_spec_rb_gc_enable, 0);
  rb_define_method(cls, "rb_gc_disable", gc_spec_rb_gc_disable, 0);
  rb_define_method(cls, "rb_gc", gc_spec_rb_gc, 0);
  rb_define_method(cls, "rb_gc_adjust_memory_usage", gc_spec_rb_gc_adjust_memory_usage, 1);
  rb_define_method(cls, "rb_gc_register_mark_object", gc_spec_rb_gc_register_mark_object, 1);
  rb_define_method(cls, "rb_gc_latest_gc_info", gc_spec_rb_gc_latest_gc_info, 1);
}

#ifdef __cplusplus
}
#endif
