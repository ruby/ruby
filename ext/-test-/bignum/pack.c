#include "ruby.h"
#include "internal.h"

static VALUE
rb_integer_pack_m(VALUE val, VALUE buf, VALUE wordsize_arg, VALUE nails, VALUE flags)
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
      wordsize, NUM2SIZET(nails), NUM2INT(flags));

  return rb_ary_new_from_args(3, INT2NUM(sign), ret ? rb_str_new(ret, wordsize * count) : Qnil, SIZET2NUM(count));
}

static VALUE
rb_integer_unpack_m(VALUE klass, VALUE sign, VALUE buf, VALUE wordcount, VALUE wordsize, VALUE nails, VALUE flags)
{
    StringValue(buf);

    return rb_integer_unpack(NUM2INT(sign), RSTRING_PTR(buf),
            NUM2SIZET(wordcount), NUM2SIZET(wordsize),
            NUM2SIZET(nails), NUM2INT(flags));
}

void
Init_pack(VALUE klass)
{
    rb_define_method(rb_cInteger, "test_pack", rb_integer_pack_m, 4);
    rb_define_singleton_method(rb_cInteger, "test_unpack", rb_integer_unpack_m, 6);
    rb_define_const(rb_cInteger, "INTEGER_PACK_MSWORD_FIRST", INT2NUM(INTEGER_PACK_MSWORD_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_LSWORD_FIRST", INT2NUM(INTEGER_PACK_LSWORD_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_MSBYTE_FIRST", INT2NUM(INTEGER_PACK_MSBYTE_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_LSBYTE_FIRST", INT2NUM(INTEGER_PACK_LSBYTE_FIRST));
    rb_define_const(rb_cInteger, "INTEGER_PACK_NATIVE_BYTE_ORDER", INT2NUM(INTEGER_PACK_NATIVE_BYTE_ORDER));
    rb_define_const(rb_cInteger, "INTEGER_PACK_LITTLE_ENDIAN", INT2NUM(INTEGER_PACK_LITTLE_ENDIAN));
    rb_define_const(rb_cInteger, "INTEGER_PACK_BIG_ENDIAN", INT2NUM(INTEGER_PACK_BIG_ENDIAN));
}
