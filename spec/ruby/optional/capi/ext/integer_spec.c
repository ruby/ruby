#include "ruby.h"
#include "rubyspec.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE integer_spec_rb_integer_pack(VALUE self, VALUE value,
    VALUE words, VALUE numwords, VALUE wordsize, VALUE nails, VALUE flags) {
  int result = rb_integer_pack(value, (void*)RSTRING_PTR(words), FIX2INT(numwords),
      FIX2INT(wordsize), FIX2INT(nails), FIX2INT(flags));
  return INT2FIX(result);
}

RUBY_EXTERN VALUE rb_int_positive_pow(long x, unsigned long y); /* internal.h, used in ripper */

static VALUE integer_spec_rb_int_positive_pow(VALUE self, VALUE a, VALUE b) {
  return rb_int_positive_pow(FIX2INT(a), FIX2INT(b));
}

#ifdef RUBY_VERSION_IS_4_1
static VALUE integer_spec_rb_int_parse_cstr(VALUE self, VALUE str, VALUE len, VALUE base, VALUE flags) {
  const char *s = RSTRING_PTR(str);
  ssize_t n = NIL_P(len) ? RSTRING_LEN(str) : NUM2SSIZET(len);
  int b = NUM2INT(base), f = NUM2INT(flags);
  char *end = NULL;
  size_t ndigits = 0;
  VALUE result[3];
  result[0] = rb_int_parse_cstr(s, n, &end, &ndigits, b, f);
  result[1] = SIZET2NUM(end - s);
  result[2] = SIZET2NUM(ndigits);
  return rb_ary_new_from_values(3, result);
}
#endif

void Init_integer_spec(void) {
  VALUE cls = rb_define_class("CApiIntegerSpecs", rb_cObject);
  rb_define_const(cls, "MSWORD", INT2NUM(INTEGER_PACK_MSWORD_FIRST));
  rb_define_const(cls, "LSWORD", INT2NUM(INTEGER_PACK_LSWORD_FIRST));
  rb_define_const(cls, "MSBYTE", INT2NUM(INTEGER_PACK_MSBYTE_FIRST));
  rb_define_const(cls, "LSBYTE", INT2NUM(INTEGER_PACK_LSBYTE_FIRST));
  rb_define_const(cls, "NATIVE", INT2NUM(INTEGER_PACK_NATIVE_BYTE_ORDER));
  rb_define_const(cls, "PACK_2COMP", INT2NUM(INTEGER_PACK_2COMP));
  rb_define_const(cls, "LITTLE_ENDIAN", INT2NUM(INTEGER_PACK_LITTLE_ENDIAN));
  rb_define_const(cls, "BIG_ENDIAN", INT2NUM(INTEGER_PACK_BIG_ENDIAN));
  rb_define_const(cls, "FORCE_BIGNUM", INT2NUM(INTEGER_PACK_FORCE_BIGNUM));
  rb_define_const(cls, "NEGATIVE", INT2NUM(INTEGER_PACK_NEGATIVE));
#ifdef RUBY_VERSION_IS_4_1
  rb_define_const(cls, "RB_INT_PARSE_SIGN", INT2NUM(RB_INT_PARSE_SIGN));
  rb_define_const(cls, "RB_INT_PARSE_UNDERSCORE", INT2NUM(RB_INT_PARSE_UNDERSCORE));
  rb_define_const(cls, "RB_INT_PARSE_PREFIX", INT2NUM(RB_INT_PARSE_PREFIX));
  rb_define_const(cls, "RB_INT_PARSE_ALL", INT2NUM(RB_INT_PARSE_ALL));
  rb_define_const(cls, "RB_INT_PARSE_DEFAULT", INT2NUM(RB_INT_PARSE_DEFAULT));
#endif

  rb_define_method(cls, "rb_integer_pack", integer_spec_rb_integer_pack, 6);
  rb_define_method(cls, "rb_int_positive_pow", integer_spec_rb_int_positive_pow, 2);
#ifdef RUBY_VERSION_IS_4_1
  rb_define_method(cls, "rb_int_parse_cstr", integer_spec_rb_int_parse_cstr, 4);
#endif
}

#ifdef __cplusplus
}
#endif
