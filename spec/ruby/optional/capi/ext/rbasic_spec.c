#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef RBASIC_FLAGS
#define RBASIC_FLAGS(obj) (RBASIC(obj)->flags)
#endif

#ifndef RBASIC_SET_FLAGS
#define RBASIC_SET_FLAGS(obj, flags_to_set) (RBASIC(obj)->flags = flags_to_set)
#endif

#ifndef FL_SHAREABLE
static const VALUE VISIBLE_BITS = FL_TAINT | FL_FREEZE;
static const VALUE DATA_VISIBLE_BITS = FL_TAINT | FL_FREEZE | ~(FL_USER0 - 1);
#else
static const VALUE VISIBLE_BITS = FL_FREEZE;
static const VALUE DATA_VISIBLE_BITS = FL_FREEZE | ~(FL_USER0 - 1);
#endif

#if SIZEOF_VALUE == SIZEOF_LONG
#define VALUE2NUM(v) ULONG2NUM(v)
#define NUM2VALUE(n) NUM2ULONG(n)
#elif SIZEOF_VALUE == SIZEOF_LONG_LONG
#define VALUE2NUM(v) ULL2NUM(v)
#define NUM2VALUE(n) NUM2ULL(n)
#else
#error "unsupported"
#endif


#ifndef RUBY_VERSION_IS_3_1
VALUE rbasic_spec_taint_flag(VALUE self) {
  return VALUE2NUM(RUBY_FL_TAINT);
}
#endif

VALUE rbasic_spec_freeze_flag(VALUE self) {
  return VALUE2NUM(RUBY_FL_FREEZE);
}

static VALUE spec_get_flags(VALUE obj, VALUE visible_bits) {
  VALUE flags = RB_FL_TEST(obj, visible_bits);
  return VALUE2NUM(flags);
}

static VALUE spec_set_flags(VALUE obj, VALUE flags, VALUE visible_bits) {
  flags &= visible_bits;

  // Could also be done like:
  // RB_FL_UNSET(obj, visible_bits);
  // RB_FL_SET(obj, flags);
  // But that seems rather indirect
  RBASIC_SET_FLAGS(obj, (RBASIC_FLAGS(obj) & ~visible_bits) | flags);

  return VALUE2NUM(flags);
}

static VALUE rbasic_spec_get_flags(VALUE self, VALUE obj) {
  return spec_get_flags(obj, VISIBLE_BITS);
}

static VALUE rbasic_spec_set_flags(VALUE self, VALUE obj, VALUE flags) {
  return spec_set_flags(obj, NUM2VALUE(flags), VISIBLE_BITS);
}

static VALUE rbasic_spec_copy_flags(VALUE self, VALUE to, VALUE from) {
  return spec_set_flags(to, RBASIC_FLAGS(from), VISIBLE_BITS);
}

static VALUE rbasic_spec_get_klass(VALUE self, VALUE obj) {
  return RBASIC_CLASS(obj);
}

static VALUE rbasic_rdata_spec_get_flags(VALUE self, VALUE structure) {
  return spec_get_flags(structure, DATA_VISIBLE_BITS);
}

static VALUE rbasic_rdata_spec_set_flags(VALUE self, VALUE structure, VALUE flags) {
  return spec_set_flags(structure, NUM2VALUE(flags), DATA_VISIBLE_BITS);
}

static VALUE rbasic_rdata_spec_copy_flags(VALUE self, VALUE to, VALUE from) {
  return spec_set_flags(to, RBASIC_FLAGS(from), DATA_VISIBLE_BITS);
}

static VALUE rbasic_rdata_spec_get_klass(VALUE self, VALUE structure) {
  return RBASIC_CLASS(structure);
}

void Init_rbasic_spec(void) {
  VALUE cls = rb_define_class("CApiRBasicSpecs", rb_cObject);
#ifndef RUBY_VERSION_IS_3_1
  rb_define_method(cls, "taint_flag", rbasic_spec_taint_flag, 0);
#endif
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
