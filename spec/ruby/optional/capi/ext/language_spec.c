#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE language_spec_switch(VALUE self, VALUE value) {
  if (value == ID2SYM(rb_intern("undef"))) {
    value = Qundef;
  }

  switch (value) {
    case Qtrue:
      return ID2SYM(rb_intern("true"));
    case Qfalse:
      return ID2SYM(rb_intern("false"));
    case Qnil:
      return ID2SYM(rb_intern("nil"));
    case Qundef:
      return ID2SYM(rb_intern("undef"));
    default:
      return ID2SYM(rb_intern("default"));
  }
}

void Init_language_spec(void) {
  VALUE cls = rb_define_class("CApiLanguageSpecs", rb_cObject);
  rb_define_method(cls, "switch", language_spec_switch, 1);
}

#ifdef __cplusplus
}
#endif
