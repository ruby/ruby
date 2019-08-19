#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE module_specs_test_method(VALUE self) {
  return ID2SYM(rb_intern("test_method"));
}

static VALUE module_specs_const_defined(VALUE self, VALUE klass, VALUE id) {
  return rb_const_defined(klass, SYM2ID(id)) ? Qtrue : Qfalse;
}

static VALUE module_specs_const_defined_at(VALUE self, VALUE klass, VALUE id) {
  return rb_const_defined_at(klass, SYM2ID(id)) ? Qtrue : Qfalse;
}

static VALUE module_specs_const_get(VALUE self, VALUE klass, VALUE val) {
  return rb_const_get(klass, SYM2ID(val));
}

static VALUE module_specs_const_get_at(VALUE self, VALUE klass, VALUE val) {
  return rb_const_get_at(klass, SYM2ID(val));
}

static VALUE module_specs_const_get_from(VALUE self, VALUE klass, VALUE val) {
  return rb_const_get_from(klass, SYM2ID(val));
}

static VALUE module_specs_const_set(VALUE self, VALUE klass, VALUE name, VALUE val) {
  rb_const_set(klass, SYM2ID(name), val);
  return Qnil;
}

static VALUE module_specs_rb_define_alias(VALUE self, VALUE obj,
  VALUE new_name, VALUE old_name) {

  rb_define_alias(obj, RSTRING_PTR(new_name), RSTRING_PTR(old_name));
  return Qnil;
}

static VALUE module_specs_rb_alias(VALUE self, VALUE obj,
  VALUE new_name, VALUE old_name) {

  rb_alias(obj, SYM2ID(new_name), SYM2ID(old_name));
  return Qnil;
}

static VALUE module_specs_rb_define_module(VALUE self, VALUE name) {
  return rb_define_module(RSTRING_PTR(name));
}

static VALUE module_specs_rb_define_module_under(VALUE self, VALUE outer, VALUE name) {
  return rb_define_module_under(outer, RSTRING_PTR(name));
}

static VALUE module_specs_define_const(VALUE self, VALUE klass, VALUE str_name, VALUE val) {
  rb_define_const(klass, RSTRING_PTR(str_name), val);
  return Qnil;
}

static VALUE module_specs_define_global_const(VALUE self, VALUE str_name, VALUE obj) {
  rb_define_global_const(RSTRING_PTR(str_name), obj);
  return Qnil;
}

static VALUE module_specs_rb_define_global_function(VALUE self, VALUE str_name) {
  rb_define_global_function(RSTRING_PTR(str_name), module_specs_test_method, 0);
  return Qnil;
}

static VALUE module_specs_rb_define_method(VALUE self, VALUE cls, VALUE str_name) {
  rb_define_method(cls, RSTRING_PTR(str_name), module_specs_test_method, 0);
  return Qnil;
}

static VALUE module_specs_rb_define_module_function(VALUE self, VALUE cls, VALUE str_name) {
  rb_define_module_function(cls, RSTRING_PTR(str_name), module_specs_test_method, 0);
  return Qnil;
}

static VALUE module_specs_rb_define_private_method(VALUE self, VALUE cls, VALUE str_name) {
  rb_define_private_method(cls, RSTRING_PTR(str_name), module_specs_test_method, 0);
  return Qnil;
}

static VALUE module_specs_rb_define_protected_method(VALUE self, VALUE cls, VALUE str_name) {
  rb_define_protected_method(cls, RSTRING_PTR(str_name), module_specs_test_method, 0);
  return Qnil;
}

static VALUE module_specs_rb_define_singleton_method(VALUE self, VALUE cls, VALUE str_name) {
  rb_define_singleton_method(cls, RSTRING_PTR(str_name), module_specs_test_method, 0);
  return Qnil;
}

static VALUE module_specs_rb_undef_method(VALUE self, VALUE cls, VALUE str_name) {
  rb_undef_method(cls, RSTRING_PTR(str_name));
  return Qnil;
}

static VALUE module_specs_rb_undef(VALUE self, VALUE cls, VALUE symbol_name) {
  rb_undef(cls, SYM2ID(symbol_name));
  return Qnil;
}

static VALUE module_specs_rbclass2name(VALUE self, VALUE klass) {
  return rb_str_new2(rb_class2name(klass));
}

static VALUE module_specs_rb_mod_ancestors(VALUE self, VALUE klass) {
  return rb_mod_ancestors(klass);
}

void Init_module_spec(void) {
  VALUE cls = rb_define_class("CApiModuleSpecs", rb_cObject);
  rb_define_method(cls, "rb_const_defined", module_specs_const_defined, 2);
  rb_define_method(cls, "rb_const_defined_at", module_specs_const_defined_at, 2);
  rb_define_method(cls, "rb_const_get", module_specs_const_get, 2);
  rb_define_method(cls, "rb_const_get_at", module_specs_const_get_at, 2);
  rb_define_method(cls, "rb_const_get_from", module_specs_const_get_from, 2);
  rb_define_method(cls, "rb_const_set", module_specs_const_set, 3);
  rb_define_method(cls, "rb_define_alias", module_specs_rb_define_alias, 3);
  rb_define_method(cls, "rb_alias", module_specs_rb_alias, 3);
  rb_define_method(cls, "rb_define_module", module_specs_rb_define_module, 1);
  rb_define_method(cls, "rb_define_module_under", module_specs_rb_define_module_under, 2);
  rb_define_method(cls, "rb_define_const", module_specs_define_const, 3);
  rb_define_method(cls, "rb_define_global_const", module_specs_define_global_const, 2);
  rb_define_method(cls, "rb_define_global_function",
      module_specs_rb_define_global_function, 1);

  rb_define_method(cls, "rb_define_method", module_specs_rb_define_method, 2);
  rb_define_method(cls, "rb_define_module_function",
      module_specs_rb_define_module_function, 2);

  rb_define_method(cls, "rb_define_private_method",
      module_specs_rb_define_private_method, 2);

  rb_define_method(cls, "rb_define_protected_method",
      module_specs_rb_define_protected_method, 2);

  rb_define_method(cls, "rb_define_singleton_method",
      module_specs_rb_define_singleton_method, 2);

  rb_define_method(cls, "rb_undef_method", module_specs_rb_undef_method, 2);
  rb_define_method(cls, "rb_undef", module_specs_rb_undef, 2);
  rb_define_method(cls, "rb_class2name", module_specs_rbclass2name, 1);
  rb_define_method(cls, "rb_mod_ancestors", module_specs_rb_mod_ancestors, 1);
}

#ifdef __cplusplus
}
#endif
