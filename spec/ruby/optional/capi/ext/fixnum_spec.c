#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE fixnum_spec_FIX2INT(VALUE self, VALUE value) {
  int i = FIX2INT(value);
  return INT2NUM(i);
}

static VALUE fixnum_spec_FIX2UINT(VALUE self, VALUE value) {
  unsigned int i = FIX2UINT(value);
  return UINT2NUM(i);
}

#ifdef HAVE_RB_FIX2UINT
static VALUE fixnum_spec_rb_fix2uint(VALUE self, VALUE value) {
  unsigned long i = rb_fix2uint(value);
  return ULONG2NUM(i);
}
#endif

#ifdef HAVE_RB_FIX2INT
static VALUE fixnum_spec_rb_fix2int(VALUE self, VALUE value) {
  long i = rb_fix2int(value);
  return LONG2NUM(i);
}
#endif

void Init_fixnum_spec(void) {
  VALUE cls;
  cls = rb_define_class("CApiFixnumSpecs", rb_cObject);

  rb_define_method(cls, "FIX2INT", fixnum_spec_FIX2INT, 1);
  rb_define_method(cls, "FIX2UINT", fixnum_spec_FIX2UINT, 1);

#ifdef HAVE_RB_FIX2UINT
  rb_define_method(cls, "rb_fix2uint", fixnum_spec_rb_fix2uint, 1);
#endif

#ifdef HAVE_RB_FIX2INT
  rb_define_method(cls, "rb_fix2int", fixnum_spec_rb_fix2int, 1);
#endif

  (void)cls;
}

#ifdef __cplusplus
}
#endif
