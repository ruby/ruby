#include "ruby.h"
#include "internal.h"

static VALUE
rb_integer_pack_m(VALUE val, VALUE buf, VALUE wordorder, VALUE wordsize_arg, VALUE endian, VALUE nails)
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

  ret = rb_integer_pack(val,
      &sign, &count, NIL_P(buf) ? NULL : RSTRING_PTR(buf), count,
      NUM2INT(wordorder), wordsize, NUM2INT(endian), NUM2INT(nails));

  return rb_ary_new_from_args(3, INT2NUM(sign), ret ? rb_str_new(ret, wordsize * count) : Qnil, SIZET2NUM(count));
}

static VALUE
rb_integer_unpack_m(VALUE klass, VALUE sign, VALUE buf, VALUE wordcount, VALUE wordorder, VALUE wordsize, VALUE endian, VALUE nails)
{
    StringValue(buf);

    return rb_integer_unpack(NUM2INT(sign), RSTRING_PTR(buf),
            NUM2SIZET(wordcount), NUM2INT(wordorder), NUM2SIZET(wordsize),
            NUM2INT(endian), NUM2SIZET(nails));
}

void
Init_pack(VALUE klass)
{
    rb_define_method(rb_cInteger, "test_pack", rb_integer_pack_m, 5);
    rb_define_singleton_method(rb_cInteger, "test_unpack", rb_integer_unpack_m, 7);
}
