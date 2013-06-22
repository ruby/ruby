#include "ruby.h"
#include "internal.h"

static VALUE
rb_integer_pack_raw_m(VALUE val, VALUE buf, VALUE numwords_arg, VALUE wordsize_arg, VALUE nails, VALUE flags)
{
  int sign;
  size_t numwords = 0;
  size_t wordsize = NUM2SIZET(wordsize_arg);

  StringValue(buf);
  rb_str_modify(buf);
  sign = rb_integer_pack(val,
      RSTRING_PTR(buf), NUM2SIZET(numwords_arg),
      NUM2SIZET(wordsize_arg), NUM2SIZET(nails), NUM2INT(flags));

  return rb_ary_new_from_args(2, INT2NUM(sign), rb_str_new(RSTRING_PTR(buf), wordsize * numwords));
}

static VALUE
rb_integer_pack_m(VALUE val, VALUE numwords_arg, VALUE wordsize_arg, VALUE nails, VALUE flags)
{
  int sign;
  size_t numwords = NUM2SIZET(numwords_arg);
  size_t wordsize = NUM2SIZET(wordsize_arg);
  VALUE buf;

  if (numwords != 0 && wordsize != 0 && LONG_MAX / wordsize < numwords)
      rb_raise(rb_eArgError, "too big numwords * wordsize");
  buf = rb_str_new(NULL, numwords * wordsize);
  sign = rb_integer_pack(val,
      RSTRING_PTR(buf), numwords,
      wordsize, NUM2SIZET(nails), NUM2INT(flags));

  return rb_assoc_new(INT2NUM(sign), buf);
}

static VALUE
rb_integer_unpack_m(VALUE klass, VALUE buf, VALUE numwords, VALUE wordsize, VALUE nails, VALUE flags)
{
    StringValue(buf);

    return rb_integer_unpack(RSTRING_PTR(buf),
            NUM2SIZET(numwords), NUM2SIZET(wordsize),
            NUM2SIZET(nails), NUM2INT(flags));
}

void
Init_pack(VALUE klass)
{
    rb_define_method(rb_cInteger, "test_pack_raw", rb_integer_pack_raw_m, 5);
    rb_define_method(rb_cInteger, "test_pack", rb_integer_pack_m, 4);
    rb_define_singleton_method(rb_cInteger, "test_unpack", rb_integer_unpack_m, 5);
    rb_define_const(rb_cInteger, "INTEGER_PACK_MSWORD_FIRST", INT2NUM(INTEGER_PACK_MSWORD_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_LSWORD_FIRST", INT2NUM(INTEGER_PACK_LSWORD_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_MSBYTE_FIRST", INT2NUM(INTEGER_PACK_MSBYTE_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_LSBYTE_FIRST", INT2NUM(INTEGER_PACK_LSBYTE_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_NATIVE_BYTE_ORDER", INT2NUM(INTEGER_PACK_NATIVE_BYTE_ORDER));
    rb_define_const(rb_cInteger, "INTEGER_PACK_2COMP", INT2NUM(INTEGER_PACK_2COMP));
    rb_define_const(rb_cInteger, "INTEGER_PACK_LITTLE_ENDIAN", INT2NUM(INTEGER_PACK_LITTLE_ENDIAN));
    rb_define_const(rb_cInteger, "INTEGER_PACK_BIG_ENDIAN", INT2NUM(INTEGER_PACK_BIG_ENDIAN));
    rb_define_const(rb_cInteger, "INTEGER_PACK_FORCE_BIGNUM", INT2NUM(INTEGER_PACK_FORCE_BIGNUM));
    rb_define_const(rb_cInteger, "INTEGER_PACK_NEGATIVE", INT2NUM(INTEGER_PACK_NEGATIVE));
    rb_define_const(rb_cInteger, "INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION", INT2NUM(INTEGER_PACK_FORCE_GENERIC_IMPLEMENTATION));
}
