#include "ruby.h"
#include "rubyspec.h"

#include "ruby/re.h"

#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

VALUE regexp_spec_re(VALUE self, VALUE str, VALUE options) {
  char *cstr = StringValueCStr(str);
  int opts = FIX2INT(options);
  return rb_reg_new(cstr, strlen(cstr), opts);
}

VALUE regexp_spec_reg_1st_match(VALUE self, VALUE md) {
  return rb_reg_nth_match(1, md);
}

VALUE regexp_spec_rb_reg_options(VALUE self, VALUE regexp) {
  return INT2FIX(rb_reg_options(regexp));
}

VALUE regexp_spec_rb_reg_regcomp(VALUE self, VALUE str) {
  return rb_reg_regcomp(str);
}

VALUE regexp_spec_reg_match(VALUE self, VALUE re, VALUE str) {
  return rb_reg_match(re, str);
}

VALUE regexp_spec_backref_get(VALUE self) {
  return rb_backref_get();
}

static VALUE regexp_spec_backref_set(VALUE self, VALUE backref) {
  rb_backref_set(backref);
  return Qnil;
}

VALUE regexp_spec_reg_match_backref_get(VALUE self, VALUE re, VALUE str) {
  rb_reg_match(re, str);
  return rb_backref_get();
}

VALUE regexp_spec_match(VALUE self, VALUE regexp, VALUE str) {
  return rb_funcall(regexp, rb_intern("match"), 1, str);
}

VALUE regexp_spec_memcicmp(VALUE self, VALUE str1, VALUE str2) {
  long l1 = RSTRING_LEN(str1);
  long l2 = RSTRING_LEN(str2);
  return INT2FIX(rb_memcicmp(RSTRING_PTR(str1), RSTRING_PTR(str2), l1 < l2 ? l1 : l2));
}

void Init_regexp_spec(void) {
  VALUE cls = rb_define_class("CApiRegexpSpecs", rb_cObject);
  rb_define_method(cls, "match", regexp_spec_match, 2);
  rb_define_method(cls, "a_re", regexp_spec_re, 2);
  rb_define_method(cls, "a_re_1st_match", regexp_spec_reg_1st_match, 1);
  rb_define_method(cls, "rb_reg_match", regexp_spec_reg_match, 2);
  rb_define_method(cls, "rb_backref_get", regexp_spec_backref_get, 0);
  rb_define_method(cls, "rb_backref_set", regexp_spec_backref_set, 1);
  rb_define_method(cls, "rb_reg_match_backref_get", regexp_spec_reg_match_backref_get, 2);
  rb_define_method(cls, "rb_reg_options", regexp_spec_rb_reg_options, 1);
  rb_define_method(cls, "rb_reg_regcomp", regexp_spec_rb_reg_regcomp, 1);
  rb_define_method(cls, "rb_memcicmp", regexp_spec_memcicmp, 2);
}

#ifdef __cplusplus
}
#endif
