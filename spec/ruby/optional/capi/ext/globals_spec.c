#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE g_hooked_var;

VALUE var_2x_getter(ID id, VALUE *data) {
  return *data;
}

void var_2x_setter(VALUE val, ID id, VALUE *var) {
  *var = INT2NUM(NUM2INT(val) * 2);
}

static VALUE sb_define_hooked_variable(VALUE self, VALUE var_name) {
  rb_define_hooked_variable(StringValuePtr(var_name), &g_hooked_var, var_2x_getter, var_2x_setter);
  return Qnil;
}

static VALUE sb_define_hooked_variable_default_accessors(VALUE self, VALUE var_name) {
  rb_define_hooked_variable(StringValuePtr(var_name), &g_hooked_var, (rb_gvar_getter_t*) NULL, (rb_gvar_setter_t*) NULL);
  return Qnil;
}

static VALUE sb_define_hooked_variable_null_var(VALUE self, VALUE var_name) {
    rb_define_hooked_variable(StringValuePtr(var_name), NULL, (rb_gvar_getter_t*) NULL, (rb_gvar_setter_t*) NULL);
    return Qnil;
}

VALUE g_ro_var;

static VALUE sb_define_readonly_variable(VALUE self, VALUE var_name, VALUE val) {
  g_ro_var = val;
  rb_define_readonly_variable(StringValuePtr(var_name), &g_ro_var);
  return Qnil;
}

VALUE g_var;

static VALUE sb_get_global_value(VALUE self) {
  return g_var;
}

static VALUE sb_define_variable(VALUE self, VALUE var_name, VALUE val) {
  g_var = val;
  rb_define_variable(StringValuePtr(var_name), &g_var);
  return Qnil;
}

long virtual_var_storage;

VALUE incrementing_getter(ID id, VALUE *data) {
  return LONG2FIX(virtual_var_storage++);
}

void incrementing_setter(VALUE val, ID id, VALUE *data) {
  virtual_var_storage = FIX2LONG(val);
}

static VALUE sb_define_virtual_variable_default_accessors(VALUE self, VALUE name) {
  rb_define_virtual_variable(StringValuePtr(name), (rb_gvar_getter_t*) NULL, (rb_gvar_setter_t*) NULL);
  return Qnil;
}

static VALUE sb_define_virtual_variable_incrementing_accessors(VALUE self, VALUE name) {
  rb_define_virtual_variable(StringValuePtr(name), incrementing_getter, incrementing_setter);
  return Qnil;
}

static VALUE sb_f_global_variables(VALUE self) {
  return rb_f_global_variables();
}

static VALUE sb_gv_get(VALUE self, VALUE var) {
  return rb_gv_get(StringValuePtr(var));
}

static VALUE sb_gv_set(VALUE self, VALUE var, VALUE val) {
  return rb_gv_set(StringValuePtr(var), val);
}

static VALUE global_spec_rb_stdin(VALUE self) {
  return rb_stdin;
}

static VALUE global_spec_rb_stdout(VALUE self) {
  return rb_stdout;
}

static VALUE global_spec_rb_stderr(VALUE self) {
  return rb_stderr;
}

static VALUE global_spec_rb_defout(VALUE self) {
  return rb_defout;
}

static VALUE global_spec_rb_fs(VALUE self) {
  return rb_fs;
}

static VALUE global_spec_rb_rs(VALUE self) {
  return rb_rs;
}

static VALUE global_spec_rb_default_rs(VALUE self) {
  return rb_default_rs;
}

static VALUE global_spec_rb_output_rs(VALUE self) {
  return rb_output_rs;
}

static VALUE global_spec_rb_output_fs(VALUE self) {
  return rb_output_fs;
}

static VALUE global_spec_rb_lastline_set(VALUE self, VALUE line) {
  rb_lastline_set(line);
  return Qnil;
}

static VALUE global_spec_rb_lastline_get(VALUE self) {
  return rb_lastline_get();
}

void Init_globals_spec(void) {
  VALUE cls = rb_define_class("CApiGlobalSpecs", rb_cObject);
  g_hooked_var = Qnil;
  rb_define_method(cls, "rb_define_hooked_variable_2x", sb_define_hooked_variable, 1);
  rb_define_method(cls, "rb_define_hooked_variable_default_accessors", sb_define_hooked_variable_default_accessors, 1);
  rb_define_method(cls, "rb_define_hooked_variable_null_var", sb_define_hooked_variable_null_var, 1);
  g_ro_var = Qnil;
  rb_define_method(cls, "rb_define_readonly_variable", sb_define_readonly_variable, 2);
  g_var = Qnil;
  rb_define_method(cls, "rb_define_variable", sb_define_variable, 2);
  rb_define_method(cls, "rb_define_virtual_variable_default_accessors", sb_define_virtual_variable_default_accessors, 1);
  rb_define_method(cls, "rb_define_virtual_variable_incrementing_accessors", sb_define_virtual_variable_incrementing_accessors, 1);
  rb_define_method(cls, "sb_get_global_value", sb_get_global_value, 0);
  rb_define_method(cls, "rb_f_global_variables", sb_f_global_variables, 0);
  rb_define_method(cls, "sb_gv_get", sb_gv_get, 1);
  rb_define_method(cls, "sb_gv_set", sb_gv_set, 2);
  rb_define_method(cls, "rb_stdin", global_spec_rb_stdin, 0);
  rb_define_method(cls, "rb_stdout", global_spec_rb_stdout, 0);
  rb_define_method(cls, "rb_stderr", global_spec_rb_stderr, 0);
  rb_define_method(cls, "rb_defout", global_spec_rb_defout, 0);
  rb_define_method(cls, "rb_fs", global_spec_rb_fs, 0);
  rb_define_method(cls, "rb_rs", global_spec_rb_rs, 0);
  rb_define_method(cls, "rb_default_rs", global_spec_rb_default_rs, 0);
  rb_define_method(cls, "rb_output_rs", global_spec_rb_output_rs, 0);
  rb_define_method(cls, "rb_output_fs", global_spec_rb_output_fs, 0);
  rb_define_method(cls, "rb_lastline_set", global_spec_rb_lastline_set, 1);
  rb_define_method(cls, "rb_lastline_get", global_spec_rb_lastline_get, 0);
}

#ifdef __cplusplus
}
#endif
