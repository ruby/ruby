#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif


VALUE rbasic_spec_taint_flag(VALUE self) {
  return INT2FIX(RUBY_FL_TAINT);
}

VALUE rbasic_spec_freeze_flag(VALUE self) {
  return INT2FIX(RUBY_FL_FREEZE);
}

VALUE rbasic_spec_get_flags(VALUE self, VALUE val) {
  return INT2FIX(RBASIC(val)->flags);
}

VALUE rbasic_spec_set_flags(VALUE self, VALUE val, VALUE flags) {
  RBASIC(val)->flags = FIX2INT(flags);
  return INT2FIX(RBASIC(val)->flags);
}

VALUE rbasic_spec_copy_flags(VALUE self, VALUE to, VALUE from) {
  RBASIC(to)->flags = RBASIC(from)->flags;
  return INT2FIX(RBASIC(to)->flags);
}

VALUE rbasic_spec_get_klass(VALUE self, VALUE val) {
  return RBASIC(val)->klass;
}

VALUE rbasic_rdata_spec_get_flags(VALUE self, VALUE structure) {
  return INT2FIX(RDATA(structure)->basic.flags);
}

VALUE rbasic_rdata_spec_set_flags(VALUE self, VALUE structure, VALUE flags) {
  RDATA(structure)->basic.flags = FIX2INT(flags);
  return INT2FIX(RDATA(structure)->basic.flags);
}

VALUE rbasic_rdata_spec_copy_flags(VALUE self, VALUE to, VALUE from) {
  RDATA(to)->basic.flags = RDATA(from)->basic.flags;
  return INT2FIX(RDATA(to)->basic.flags);
}

VALUE rbasic_rdata_spec_get_klass(VALUE self, VALUE structure) {
  return RDATA(structure)->basic.klass;
}

void Init_rbasic_spec(void) {
  VALUE cls = rb_define_class("CApiRBasicSpecs", rb_cObject);
  rb_define_method(cls, "taint_flag", rbasic_spec_taint_flag, 0);
  rb_define_method(cls, "freeze_flag", rbasic_spec_freeze_flag, 0);
  rb_define_method(cls, "get_flags", rbasic_spec_get_flags, 1);
  rb_define_method(cls, "set_flags", rbasic_spec_set_flags, 2);
  rb_define_method(cls, "copy_flags", rbasic_spec_copy_flags, 2);
  rb_define_method(cls, "get_klass", rbasic_spec_get_klass, 1);

  cls = rb_define_class("CApiRBasicRDataSpecs", rb_cObject);
  rb_define_method(cls, "get_flags", rbasic_rdata_spec_get_flags, 1);
  rb_define_method(cls, "set_flags", rbasic_rdata_spec_set_flags, 2);
  rb_define_method(cls, "copy_flags", rbasic_rdata_spec_copy_flags, 2);
  rb_define_method(cls, "get_klass", rbasic_rdata_spec_get_klass, 1);
}

#ifdef __cplusplus
}
#endif
