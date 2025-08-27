#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

#define RBOOL(x) ((x) ? Qtrue : Qfalse)

int yield_element_and_arg(VALUE element, VALUE arg) {
  return RTEST(rb_yield_values(2, element, arg)) ? ST_CONTINUE : ST_STOP;
}

VALUE set_spec_rb_set_foreach(VALUE self, VALUE set, VALUE arg) {
  rb_set_foreach(set, yield_element_and_arg, arg);
  return Qnil;
}

VALUE set_spec_rb_set_new(VALUE self) {
  return rb_set_new();
}

VALUE set_spec_rb_set_new_capa(VALUE self, VALUE capa) {
  return rb_set_new_capa(NUM2INT(capa));
}

VALUE set_spec_rb_set_lookup(VALUE self, VALUE set, VALUE element) {
  return RBOOL(rb_set_lookup(set, element));
}

VALUE set_spec_rb_set_add(VALUE self, VALUE set, VALUE element) {
  return RBOOL(rb_set_add(set, element));
}

VALUE set_spec_rb_set_clear(VALUE self, VALUE set) {
  return rb_set_clear(set);
}

VALUE set_spec_rb_set_delete(VALUE self, VALUE set, VALUE element) {
  return RBOOL(rb_set_delete(set, element));
}

VALUE set_spec_rb_set_size(VALUE self, VALUE set) {
  return SIZET2NUM(rb_set_size(set));
}

void Init_set_spec(void) {
  VALUE cls = rb_define_class("CApiSetSpecs", rb_cObject);
  rb_define_method(cls, "rb_set_foreach", set_spec_rb_set_foreach, 2);
  rb_define_method(cls, "rb_set_new", set_spec_rb_set_new, 0);
  rb_define_method(cls, "rb_set_new_capa", set_spec_rb_set_new_capa, 1);
  rb_define_method(cls, "rb_set_lookup", set_spec_rb_set_lookup, 2);
  rb_define_method(cls, "rb_set_add", set_spec_rb_set_add, 2);
  rb_define_method(cls, "rb_set_clear", set_spec_rb_set_clear, 1);
  rb_define_method(cls, "rb_set_delete", set_spec_rb_set_delete, 2);
  rb_define_method(cls, "rb_set_size", set_spec_rb_set_size, 1);
}

#ifdef __cplusplus
}
#endif

