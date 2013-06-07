#include "ruby.h"
#include "internal.h"

static VALUE
rb_int_export_m(VALUE val, VALUE buf, VALUE wordorder, VALUE wordsize_arg, VALUE endian, VALUE nails)
{
  int sign;
  size_t count = 0;
  void *ret;
  size_t wordsize = NUM2SIZET(wordsize_arg);

  if (!NIL_P(buf)) {
      StringValue(buf);
      rb_str_modify(buf);
      count = RSTRING_LEN(buf) / wordsize;
  }

  ret = rb_int_export(val,
      &sign, &count, NIL_P(buf) ? NULL : RSTRING_PTR(buf), count,
      NUM2INT(wordorder), wordsize, NUM2INT(endian), NUM2INT(nails));

  return rb_ary_new_from_args(3, INT2NUM(sign), ret ? rb_str_new(ret, wordsize * count) : Qnil, SIZET2NUM(count));
}

void
Init_export(VALUE klass)
{
    rb_define_method(rb_cInteger, "test_export", rb_int_export_m, 5);
}
