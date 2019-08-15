#include "ruby.h"
#include "rubyspec.h"

#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

static VALUE class_spec_call_super_method(VALUE self) {
  return rb_call_super(0, 0);
}

static VALUE class_spec_define_call_super_method(VALUE self, VALUE obj, VALUE str_name) {
  rb_define_method(obj, RSTRING_PTR(str_name), class_spec_call_super_method, 0);
  return Qnil;
}

static VALUE class_spec_rb_class_path(VALUE self, VALUE klass) {
  return rb_class_path(klass);
}

static VALUE class_spec_rb_class_name(VALUE self, VALUE klass) {
  return rb_class_name(klass);
}

static VALUE class_spec_rb_class2name(VALUE self, VALUE klass) {
  return rb_str_new2( rb_class2name(klass) );
}

static VALUE class_spec_rb_path2class(VALUE self, VALUE path) {
  return rb_path2class(RSTRING_PTR(path));
}

static VALUE class_spec_rb_path_to_class(VALUE self, VALUE path) {
  return rb_path_to_class(path);
}

static VALUE class_spec_rb_class_new(VALUE self, VALUE super) {
  return rb_class_new(super);
}

static VALUE class_spec_rb_class_new_instance(VALUE self,
                                      VALUE nargs, VALUE args,
                                      VALUE klass) {
  int c_nargs = FIX2INT(nargs);
  VALUE *c_args = alloca(sizeof(VALUE) * c_nargs);
  int i;

  for (i = 0; i < c_nargs; i++)
    c_args[i] = rb_ary_entry(args, i);

  return rb_class_new_instance(c_nargs, c_args, klass);
}

static VALUE class_spec_rb_class_real(VALUE self, VALUE object) {
  if(rb_type_p(object, T_FIXNUM)) {
    return INT2FIX(rb_class_real(FIX2INT(object)));
  } else {
    return rb_class_real(CLASS_OF(object));
  }
}

static VALUE class_spec_rb_class_superclass(VALUE self, VALUE klass) {
  return rb_class_superclass(klass);
}

static VALUE class_spec_cvar_defined(VALUE self, VALUE klass, VALUE id) {
  ID as_id = rb_intern(StringValuePtr(id));
  return rb_cvar_defined(klass, as_id);
}

static VALUE class_spec_cvar_get(VALUE self, VALUE klass, VALUE name) {
  return rb_cvar_get(klass, rb_intern(StringValuePtr(name)));
}

static VALUE class_spec_cvar_set(VALUE self, VALUE klass, VALUE name, VALUE val) {
  rb_cvar_set(klass, rb_intern(StringValuePtr(name)), val);
  return Qnil;
}

static VALUE class_spec_cv_get(VALUE self, VALUE klass, VALUE name) {
  return rb_cv_get(klass, StringValuePtr(name));
}

static VALUE class_spec_cv_set(VALUE self, VALUE klass, VALUE name, VALUE val) {
  rb_cv_set(klass, StringValuePtr(name), val);

  return Qnil;
}

VALUE class_spec_define_attr(VALUE self, VALUE klass, VALUE sym, VALUE read, VALUE write) {
  int int_read, int_write;
  int_read = read == Qtrue ? 1 : 0;
  int_write = write == Qtrue ? 1 : 0;
  rb_define_attr(klass, rb_id2name(SYM2ID(sym)), int_read, int_write);
  return Qnil;
}

static VALUE class_spec_rb_define_class(VALUE self, VALUE name, VALUE super) {
  if(NIL_P(super)) super = 0;
  return rb_define_class(RSTRING_PTR(name), super);
}

static VALUE class_spec_rb_define_class_under(VALUE self, VALUE outer,
                                                 VALUE name, VALUE super) {
  if(NIL_P(super)) super = 0;
  return rb_define_class_under(outer, RSTRING_PTR(name), super);
}

static VALUE class_spec_rb_define_class_id_under(VALUE self, VALUE outer,
                                                 VALUE name, VALUE super) {
  if(NIL_P(super)) super = 0;
  return rb_define_class_id_under(outer, SYM2ID(name), super);
}

static VALUE class_spec_define_class_variable(VALUE self, VALUE klass, VALUE name, VALUE val) {
  rb_define_class_variable(klass, StringValuePtr(name), val);
  return Qnil;
}

static VALUE class_spec_include_module(VALUE self, VALUE klass, VALUE module) {
  rb_include_module(klass, module);
  return klass;
}

static VALUE class_spec_method_var_args_1(int argc, VALUE *argv, VALUE self) {
  VALUE ary = rb_ary_new();
  int i;
  for (i = 0; i < argc; i++) {
    rb_ary_push(ary, argv[i]);
  }
  return ary;
}

static VALUE class_spec_method_var_args_2(VALUE self, VALUE argv) {
  return argv;
}

void Init_class_spec(void) {
  VALUE cls = rb_define_class("CApiClassSpecs", rb_cObject);
  rb_define_method(cls, "define_call_super_method", class_spec_define_call_super_method, 2);
  rb_define_method(cls, "rb_class_path", class_spec_rb_class_path, 1);
  rb_define_method(cls, "rb_class_name", class_spec_rb_class_name, 1);
  rb_define_method(cls, "rb_class2name", class_spec_rb_class2name, 1);
  rb_define_method(cls, "rb_path2class", class_spec_rb_path2class, 1);
  rb_define_method(cls, "rb_path_to_class", class_spec_rb_path_to_class, 1);
  rb_define_method(cls, "rb_class_new", class_spec_rb_class_new, 1);
  rb_define_method(cls, "rb_class_new_instance", class_spec_rb_class_new_instance, 3);
  rb_define_method(cls, "rb_class_real", class_spec_rb_class_real, 1);
  rb_define_method(cls, "rb_class_superclass", class_spec_rb_class_superclass, 1);
  rb_define_method(cls, "rb_cvar_defined", class_spec_cvar_defined, 2);
  rb_define_method(cls, "rb_cvar_get", class_spec_cvar_get, 2);
  rb_define_method(cls, "rb_cvar_set", class_spec_cvar_set, 3);
  rb_define_method(cls, "rb_cv_get", class_spec_cv_get, 2);
  rb_define_method(cls, "rb_cv_set", class_spec_cv_set, 3);
  rb_define_method(cls, "rb_define_attr", class_spec_define_attr, 4);
  rb_define_method(cls, "rb_define_class", class_spec_rb_define_class, 2);
  rb_define_method(cls, "rb_define_class_under", class_spec_rb_define_class_under, 3);
  rb_define_method(cls, "rb_define_class_id_under", class_spec_rb_define_class_id_under, 3);
  rb_define_method(cls, "rb_define_class_variable", class_spec_define_class_variable, 3);
  rb_define_method(cls, "rb_include_module", class_spec_include_module, 2);
  rb_define_method(cls, "rb_method_varargs_1", class_spec_method_var_args_1, -1);
  rb_define_method(cls, "rb_method_varargs_2", class_spec_method_var_args_2, -2);
}

#ifdef __cplusplus
}
#endif
