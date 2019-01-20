#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

VALUE file_spec_rb_file_open(VALUE self, VALUE name, VALUE mode) {
  return rb_file_open(RSTRING_PTR(name), RSTRING_PTR(mode));
}

VALUE file_spec_rb_file_open_str(VALUE self, VALUE name, VALUE mode) {
  return rb_file_open_str(name, RSTRING_PTR(mode));
}

VALUE file_spec_FilePathValue(VALUE self, VALUE obj) {
  return FilePathValue(obj);
}

void Init_file_spec(void) {
  VALUE cls = rb_define_class("CApiFileSpecs", rb_cObject);
  rb_define_method(cls, "rb_file_open", file_spec_rb_file_open, 2);
  rb_define_method(cls, "rb_file_open_str", file_spec_rb_file_open_str, 2);
  rb_define_method(cls, "FilePathValue", file_spec_FilePathValue, 1);
}

#ifdef __cplusplus
}
#endif
