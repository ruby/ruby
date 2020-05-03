#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static const VALUE VISIBLE_BITS = FL_TAINT | FL_FREEZE | ~(FL_USER0 - 1);

VALUE rbasic_spec_taint_flag(VALUE self) {
  return INT2FIX(RUBY_FL_TAINT);
}

VALUE rbasic_spec_freeze_flag(VALUE self) {
  return INT2FIX(RUBY_FL_FREEZE);
}

static VALUE spec_get_flags(const struct RBasic *b) {
  VALUE flags = b->flags & VISIBLE_BITS;
  return INT2FIX(flags);
}

static VALUE spec_set_flags(struct RBasic *b, VALUE flags) {
  flags &= VISIBLE_BITS;
  b->flags = (b->flags & ~VISIBLE_BITS) | flags;
  return INT2FIX(flags);
}

VALUE rbasic_spec_get_flags(VALUE self, VALUE val) {
  return spec_get_flags(RBASIC(val));
}

VALUE rbasic_spec_set_flags(VALUE self, VALUE val, VALUE flags) {
  return spec_set_flags(RBASIC(val), FIX2INT(flags));
}

VALUE rbasic_spec_copy_flags(VALUE self, VALUE to, VALUE from) {
  return spec_set_flags(RBASIC(to), RBASIC(from)->flags);
}

VALUE rbasic_spec_get_klass(VALUE self, VALUE val) {
  return RBASIC(val)->klass;
}

VALUE rbasic_rdata_spec_get_flags(VALUE self, VALUE structure) {
  return spec_get_flags(&RDATA(structure)->basic);
}

VALUE rbasic_rdata_spec_set_flags(VALUE self, VALUE structure, VALUE flags) {
  return spec_set_flags(&RDATA(structure)->basic, FIX2INT(flags));
}

VALUE rbasic_rdata_spec_copy_flags(VALUE self, VALUE to, VALUE from) {
  return spec_set_flags(&RDATA(to)->basic, RDATA(from)->basic.flags);
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
