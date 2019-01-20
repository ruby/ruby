#include "ruby.h"
#include "rubyspec.h"

#include "ruby/encoding.h"

#ifdef __cplusplus
extern "C" {
#endif

static VALUE encoding_spec_ENC_CODERANGE_ASCIIONLY(VALUE self, VALUE obj) {
  if(ENC_CODERANGE_ASCIIONLY(obj)) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

static VALUE encoding_spec_rb_usascii_encoding(VALUE self) {
  return rb_str_new2(rb_usascii_encoding()->name);
}

static VALUE encoding_spec_rb_usascii_encindex(VALUE self) {
  return INT2NUM(rb_usascii_encindex());
}

static VALUE encoding_spec_rb_ascii8bit_encoding(VALUE self) {
  return rb_str_new2(rb_ascii8bit_encoding()->name);
}

static VALUE encoding_spec_rb_ascii8bit_encindex(VALUE self) {
  return INT2NUM(rb_ascii8bit_encindex());
}

static VALUE encoding_spec_rb_utf8_encoding(VALUE self) {
  return rb_str_new2(rb_utf8_encoding()->name);
}

static VALUE encoding_spec_rb_utf8_encindex(VALUE self) {
  return INT2NUM(rb_utf8_encindex());
}

static VALUE encoding_spec_rb_locale_encoding(VALUE self) {
  return rb_str_new2(rb_locale_encoding()->name);
}

static VALUE encoding_spec_rb_locale_encindex(VALUE self) {
  return INT2NUM(rb_locale_encindex());
}

static VALUE encoding_spec_rb_filesystem_encoding(VALUE self) {
  return rb_str_new2(rb_filesystem_encoding()->name);
}

static VALUE encoding_spec_rb_filesystem_encindex(VALUE self) {
  return INT2NUM(rb_filesystem_encindex());
}

static VALUE encoding_spec_rb_default_internal_encoding(VALUE self) {
  rb_encoding* enc = rb_default_internal_encoding();
  if(enc == 0) return Qnil;
  return rb_str_new2(enc->name);
}

static VALUE encoding_spec_rb_default_external_encoding(VALUE self) {
  rb_encoding* enc = rb_default_external_encoding();
  if(enc == 0) return Qnil;
  return rb_str_new2(enc->name);
}

#ifdef RUBY_VERSION_IS_2_6
static VALUE encoding_spec_rb_enc_alias(VALUE self, VALUE alias, VALUE orig) {
  return INT2NUM(rb_enc_alias(RSTRING_PTR(alias), RSTRING_PTR(orig)));
}
#endif

static VALUE encoding_spec_rb_enc_associate(VALUE self, VALUE obj, VALUE enc) {
  return rb_enc_associate(obj, NIL_P(enc) ? NULL : rb_enc_find(RSTRING_PTR(enc)));
}

static VALUE encoding_spec_rb_enc_associate_index(VALUE self, VALUE obj, VALUE index) {
  return rb_enc_associate_index(obj, FIX2INT(index));
}

static VALUE encoding_spec_rb_enc_compatible(VALUE self, VALUE a, VALUE b) {
  rb_encoding* enc = rb_enc_compatible(a, b);

  if(!enc) return INT2FIX(0);

  return rb_enc_from_encoding(enc);
}

static VALUE encoding_spec_rb_enc_copy(VALUE self, VALUE dest, VALUE src) {
  rb_enc_copy(dest, src);
  return dest;
}

static VALUE encoding_spec_rb_enc_find(VALUE self, VALUE name) {
  return rb_str_new2(rb_enc_find(RSTRING_PTR(name))->name);
}

static VALUE encoding_spec_rb_enc_find_index(VALUE self, VALUE name) {
  return INT2NUM(rb_enc_find_index(RSTRING_PTR(name)));
}

static VALUE encoding_spec_rb_enc_from_index(VALUE self, VALUE index) {
  return rb_str_new2(rb_enc_from_index(NUM2INT(index))->name);
}

static VALUE encoding_spec_rb_enc_from_encoding(VALUE self, VALUE name) {
  return rb_enc_from_encoding(rb_enc_find(RSTRING_PTR(name)));
}

static VALUE encoding_spec_rb_enc_get(VALUE self, VALUE obj) {
  return rb_str_new2(rb_enc_get(obj)->name);
}

static VALUE encoding_spec_rb_obj_encoding(VALUE self, VALUE obj) {
  return rb_obj_encoding(obj);
}

static VALUE encoding_spec_rb_enc_get_index(VALUE self, VALUE obj) {
  return INT2NUM(rb_enc_get_index(obj));
}

static VALUE encoding_spec_rb_enc_set_index(VALUE self, VALUE obj, VALUE index) {
  int i = NUM2INT(index);

  rb_encoding* enc = rb_enc_from_index(i);
  rb_enc_set_index(obj, i);

  return rb_ary_new3(2, rb_str_new2(rb_enc_name(enc)),
                     rb_str_new2(rb_enc_name(rb_enc_get(obj))));
}

static VALUE encoding_spec_rb_enc_str_coderange(VALUE self, VALUE str) {
  int coderange = rb_enc_str_coderange(str);

  switch(coderange) {
  case ENC_CODERANGE_UNKNOWN:
    return ID2SYM(rb_intern("coderange_unknown"));
  case ENC_CODERANGE_7BIT:
    return ID2SYM(rb_intern("coderange_7bit"));
  case ENC_CODERANGE_VALID:
    return ID2SYM(rb_intern("coderange_valid"));
  case ENC_CODERANGE_BROKEN:
    return ID2SYM(rb_intern("coderange_broken"));
  default:
    return ID2SYM(rb_intern("coderange_unrecognized"));
  }
}

static VALUE encoding_spec_rb_enc_str_new(VALUE self, VALUE str, VALUE len, VALUE enc) {
  return rb_enc_str_new(RSTRING_PTR(str), FIX2INT(len), rb_to_encoding(enc));
}

static VALUE encoding_spec_ENCODING_GET(VALUE self, VALUE obj) {
  return INT2NUM(ENCODING_GET(obj));
}

static VALUE encoding_spec_ENCODING_SET(VALUE self, VALUE obj, VALUE index) {
  int i = NUM2INT(index);

  rb_encoding* enc = rb_enc_from_index(i);
  ENCODING_SET(obj, i);

  return rb_ary_new3(2, rb_str_new2(rb_enc_name(enc)),
                     rb_str_new2(rb_enc_name(rb_enc_get(obj))));
}

static VALUE encoding_spec_rb_enc_to_index(VALUE self, VALUE name) {
  return INT2NUM(rb_enc_to_index(NIL_P(name) ? NULL : rb_enc_find(RSTRING_PTR(name))));
}

static VALUE encoding_spec_rb_to_encoding(VALUE self, VALUE obj) {
  return rb_str_new2(rb_to_encoding(obj)->name);
}

static VALUE encoding_spec_rb_to_encoding_index(VALUE self, VALUE obj) {
  return INT2NUM(rb_to_encoding_index(obj));
}

static VALUE encoding_spec_rb_enc_nth(VALUE self, VALUE str, VALUE index) {
  char* start = RSTRING_PTR(str);
  char* end = start + RSTRING_LEN(str);
  char* ptr = rb_enc_nth(start, end, FIX2LONG(index), rb_enc_get(str));
  return LONG2NUM(ptr - start);
}

static VALUE encoding_spec_rb_enc_codepoint_len(VALUE self, VALUE str) {
  char* start = RSTRING_PTR(str);
  char* end = start + RSTRING_LEN(str);

  int len;
  unsigned int codepoint = rb_enc_codepoint_len(start, end, &len, rb_enc_get(str));

  return rb_ary_new3(2, LONG2NUM(codepoint), LONG2NUM(len));
}

void Init_encoding_spec(void) {
  VALUE cls = rb_define_class("CApiEncodingSpecs", rb_cObject);
  rb_define_method(cls, "ENC_CODERANGE_ASCIIONLY",
                   encoding_spec_ENC_CODERANGE_ASCIIONLY, 1);

  rb_define_method(cls, "rb_usascii_encoding", encoding_spec_rb_usascii_encoding, 0);
  rb_define_method(cls, "rb_usascii_encindex", encoding_spec_rb_usascii_encindex, 0);
  rb_define_method(cls, "rb_ascii8bit_encoding", encoding_spec_rb_ascii8bit_encoding, 0);
  rb_define_method(cls, "rb_ascii8bit_encindex", encoding_spec_rb_ascii8bit_encindex, 0);
  rb_define_method(cls, "rb_utf8_encoding", encoding_spec_rb_utf8_encoding, 0);
  rb_define_method(cls, "rb_utf8_encindex", encoding_spec_rb_utf8_encindex, 0);
  rb_define_method(cls, "rb_locale_encoding", encoding_spec_rb_locale_encoding, 0);
  rb_define_method(cls, "rb_locale_encindex", encoding_spec_rb_locale_encindex, 0);
  rb_define_method(cls, "rb_filesystem_encoding", encoding_spec_rb_filesystem_encoding, 0);
  rb_define_method(cls, "rb_filesystem_encindex", encoding_spec_rb_filesystem_encindex, 0);
  rb_define_method(cls, "rb_default_internal_encoding",
                   encoding_spec_rb_default_internal_encoding, 0);

  rb_define_method(cls, "rb_default_external_encoding",
                   encoding_spec_rb_default_external_encoding, 0);

#ifdef RUBY_VERSION_IS_2_6
  rb_define_method(cls, "rb_enc_alias", encoding_spec_rb_enc_alias, 2);
#endif

  rb_define_method(cls, "rb_enc_associate", encoding_spec_rb_enc_associate, 2);
  rb_define_method(cls, "rb_enc_associate_index", encoding_spec_rb_enc_associate_index, 2);
  rb_define_method(cls, "rb_enc_compatible", encoding_spec_rb_enc_compatible, 2);
  rb_define_method(cls, "rb_enc_copy", encoding_spec_rb_enc_copy, 2);
  rb_define_method(cls, "rb_enc_find", encoding_spec_rb_enc_find, 1);
  rb_define_method(cls, "rb_enc_find_index", encoding_spec_rb_enc_find_index, 1);
  rb_define_method(cls, "rb_enc_from_index", encoding_spec_rb_enc_from_index, 1);
  rb_define_method(cls, "rb_enc_from_encoding", encoding_spec_rb_enc_from_encoding, 1);
  rb_define_method(cls, "rb_enc_get", encoding_spec_rb_enc_get, 1);
  rb_define_method(cls, "rb_obj_encoding", encoding_spec_rb_obj_encoding, 1);
  rb_define_method(cls, "rb_enc_get_index", encoding_spec_rb_enc_get_index, 1);
  rb_define_method(cls, "rb_enc_set_index", encoding_spec_rb_enc_set_index, 2);
  rb_define_method(cls, "rb_enc_str_coderange", encoding_spec_rb_enc_str_coderange, 1);
  rb_define_method(cls, "rb_enc_str_new", encoding_spec_rb_enc_str_new, 3);
  rb_define_method(cls, "ENCODING_GET", encoding_spec_ENCODING_GET, 1);
  rb_define_method(cls, "ENCODING_SET", encoding_spec_ENCODING_SET, 2);
  rb_define_method(cls, "rb_enc_to_index", encoding_spec_rb_enc_to_index, 1);
  rb_define_method(cls, "rb_to_encoding", encoding_spec_rb_to_encoding, 1);
  rb_define_method(cls, "rb_to_encoding_index", encoding_spec_rb_to_encoding_index, 1);
  rb_define_method(cls, "rb_enc_nth", encoding_spec_rb_enc_nth, 2);
  rb_define_method(cls, "rb_enc_codepoint_len", encoding_spec_rb_enc_codepoint_len, 1);
}

#ifdef __cplusplus
}
#endif
