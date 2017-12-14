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

static VALUE
rb_integer_test_numbits_2comp_without_sign(VALUE val)
{
  size_t size;
  int neg = FIXNUM_P(val) ? FIX2LONG(val) < 0 : BIGNUM_NEGATIVE_P(val);
  size = rb_absint_numwords(val, 1, NULL) - (neg && rb_absint_singlebit_p(val));
  return SIZET2NUM(size);
}

static VALUE
rb_integer_test_numbytes_2comp_with_sign(VALUE val)
{
  int neg = FIXNUM_P(val) ? FIX2LONG(val) < 0 : BIGNUM_NEGATIVE_P(val);
  int nlz_bits;
  size_t size = rb_absint_size(val, &nlz_bits);
  if (nlz_bits == 0 && !(neg && rb_absint_singlebit_p(val)))
    size++;
  return SIZET2NUM(size);
}

void
Init_intpack(VALUE klass)
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

    rb_define_method(rb_cInteger, "test_numbits_2comp_without_sign", rb_integer_test_numbits_2comp_without_sign, 0);
    rb_define_method(rb_cInteger, "test_numbytes_2comp_with_sign", rb_integer_test_numbytes_2comp_with_sign, 0);
}
