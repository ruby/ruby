#include "ruby.h"
#include "rubyspec.h"

#include "ruby/intern.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE struct_spec_rb_struct_aref(VALUE self, VALUE st, VALUE key) {
  return rb_struct_aref(st, key);
}

static VALUE struct_spec_rb_struct_getmember(VALUE self, VALUE st, VALUE key) {
  return rb_struct_getmember(st, SYM2ID(key));
}

static VALUE struct_spec_rb_struct_s_members(VALUE self, VALUE klass)
{
  return rb_ary_dup(rb_struct_s_members(klass));
}

static VALUE struct_spec_rb_struct_members(VALUE self, VALUE st)
{
  return rb_ary_dup(rb_struct_members(st));
}

static VALUE struct_spec_rb_struct_aset(VALUE self, VALUE st, VALUE key, VALUE value) {
  return rb_struct_aset(st, key, value);
}

/* Only allow setting three attributes, should be sufficient for testing. */
static VALUE struct_spec_struct_define(VALUE self, VALUE name,
  VALUE attr1, VALUE attr2, VALUE attr3) {

  const char *a1 = StringValuePtr(attr1);
  const char *a2 = StringValuePtr(attr2);
  const char *a3 = StringValuePtr(attr3);
  char *nm = NULL;

  if (name != Qnil) nm = StringValuePtr(name);

  return rb_struct_define(nm, a1, a2, a3, NULL);
}

/* Only allow setting three attributes, should be sufficient for testing. */
static VALUE struct_spec_struct_define_under(VALUE self, VALUE outer,
  VALUE name, VALUE attr1, VALUE attr2, VALUE attr3) {

  const char *nm = StringValuePtr(name);
  const char *a1 = StringValuePtr(attr1);
  const char *a2 = StringValuePtr(attr2);
  const char *a3 = StringValuePtr(attr3);

  return rb_struct_define_under(outer, nm, a1, a2, a3, NULL);
}

static VALUE struct_spec_rb_struct_new(VALUE self, VALUE klass,
                                       VALUE a, VALUE b, VALUE c)
{

  return rb_struct_new(klass, a, b, c);
}

static VALUE struct_spec_rb_struct_size(VALUE self, VALUE st)
{
  return rb_struct_size(st);
}

void Init_struct_spec(void) {
  VALUE cls = rb_define_class("CApiStructSpecs", rb_cObject);
  rb_define_method(cls, "rb_struct_aref", struct_spec_rb_struct_aref, 2);
  rb_define_method(cls, "rb_struct_getmember", struct_spec_rb_struct_getmember, 2);
  rb_define_method(cls, "rb_struct_s_members", struct_spec_rb_struct_s_members, 1);
  rb_define_method(cls, "rb_struct_members", struct_spec_rb_struct_members, 1);
  rb_define_method(cls, "rb_struct_aset", struct_spec_rb_struct_aset, 3);
  rb_define_method(cls, "rb_struct_define", struct_spec_struct_define, 4);
  rb_define_method(cls, "rb_struct_define_under", struct_spec_struct_define_under, 5);
  rb_define_method(cls, "rb_struct_new", struct_spec_rb_struct_new, 4);
  rb_define_method(cls, "rb_struct_size", struct_spec_rb_struct_size, 1);
}

#ifdef __cplusplus
}
#endif
