#include "ruby.h"
#include "rubyspec.h"

#include <string.h>
#include <stdarg.h>

#include "ruby/encoding.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Make sure the RSTRING_PTR and the bytes are in native memory.
 * On TruffleRuby RSTRING_PTR and the bytes remain in managed memory
 * until they must be written to native memory.
 * In some specs we want to test using the native memory. */
#ifndef NATIVE_RSTRING_PTR
#define NATIVE_RSTRING_PTR(str) RSTRING_PTR(str)
#endif

VALUE string_spec_rb_cstr2inum(VALUE self, VALUE str, VALUE inum) {
  int num = FIX2INT(inum);
  return rb_cstr2inum(RSTRING_PTR(str), num);
}

static VALUE string_spec_rb_cstr_to_inum(VALUE self, VALUE str, VALUE inum, VALUE badcheck) {
  int num = FIX2INT(inum);
  return rb_cstr_to_inum(RSTRING_PTR(str), num, RTEST(badcheck));
}

VALUE string_spec_rb_str2inum(VALUE self, VALUE str, VALUE inum) {
  int num = FIX2INT(inum);
  return rb_str2inum(str, num);
}

VALUE string_spec_rb_str_append(VALUE self, VALUE str, VALUE str2) {
  return rb_str_append(str, str2);
}

VALUE string_spec_rb_str_set_len(VALUE self, VALUE str, VALUE len) {
  rb_str_set_len(str, NUM2LONG(len));

  return str;
}

VALUE string_spec_rb_str_set_len_RSTRING_LEN(VALUE self, VALUE str, VALUE len) {
  rb_str_set_len(str, NUM2LONG(len));

  return INT2FIX(RSTRING_LEN(str));
}

VALUE string_spec_rb_str_buf_new(VALUE self, VALUE len, VALUE str) {
  VALUE buf;

  buf = rb_str_buf_new(NUM2LONG(len));

  if(RTEST(str)) {
    snprintf(RSTRING_PTR(buf), NUM2LONG(len), "%s", RSTRING_PTR(str));
  }

  return buf;
}

VALUE string_spec_rb_str_capacity(VALUE self, VALUE str) {
  return SIZET2NUM(rb_str_capacity(str));
}

VALUE string_spec_rb_str_buf_new2(VALUE self) {
  return rb_str_buf_new2("hello\0invisible");
}

VALUE string_spec_rb_str_buf_cat(VALUE self, VALUE str) {
  const char *question_mark = "?";
  rb_str_buf_cat(str, question_mark, strlen(question_mark));
  return str;
}

VALUE string_spec_rb_str_cat(VALUE self, VALUE str) {
  return rb_str_cat(str, "?", 1);
}

VALUE string_spec_rb_str_cat2(VALUE self, VALUE str) {
  return rb_str_cat2(str, "?");
}

VALUE string_spec_rb_str_cmp(VALUE self, VALUE str1, VALUE str2) {
  return INT2NUM(rb_str_cmp(str1, str2));
}

VALUE string_spec_rb_str_conv_enc(VALUE self, VALUE str, VALUE from, VALUE to) {
  rb_encoding* from_enc;
  rb_encoding* to_enc;

  from_enc = rb_to_encoding(from);

  if(NIL_P(to)) {
    to_enc = 0;
  } else {
    to_enc = rb_to_encoding(to);
  }

  return rb_str_conv_enc(str, from_enc, to_enc);
}

VALUE string_spec_rb_str_conv_enc_opts(VALUE self, VALUE str, VALUE from, VALUE to,
                                       VALUE ecflags, VALUE ecopts)
{
  rb_encoding* from_enc;
  rb_encoding* to_enc;

  from_enc = rb_to_encoding(from);

  if(NIL_P(to)) {
    to_enc = 0;
  } else {
    to_enc = rb_to_encoding(to);
  }

  return rb_str_conv_enc_opts(str, from_enc, to_enc, FIX2INT(ecflags), ecopts);
}

VALUE string_spec_rb_str_drop_bytes(VALUE self, VALUE str, VALUE len) {
  return rb_str_drop_bytes(str, NUM2LONG(len));
}

VALUE string_spec_rb_str_export(VALUE self, VALUE str) {
  return rb_str_export(str);
}

VALUE string_spec_rb_str_export_locale(VALUE self, VALUE str) {
  return rb_str_export_locale(str);
}

VALUE string_spec_rb_str_dup(VALUE self, VALUE str) {
  return rb_str_dup(str);
}

VALUE string_spec_rb_str_freeze(VALUE self, VALUE str) {
  return rb_str_freeze(str);
}

VALUE string_spec_rb_str_inspect(VALUE self, VALUE str) {
  return rb_str_inspect(str);
}

VALUE string_spec_rb_str_intern(VALUE self, VALUE str) {
  return rb_str_intern(str);
}

VALUE string_spec_rb_str_length(VALUE self, VALUE str) {
  return rb_str_length(str);
}

VALUE string_spec_rb_str_new(VALUE self, VALUE str, VALUE len) {
  return rb_str_new(RSTRING_PTR(str), FIX2INT(len));
}

VALUE string_spec_rb_str_new_native(VALUE self, VALUE str, VALUE len) {
  return rb_str_new(NATIVE_RSTRING_PTR(str), FIX2INT(len));
}

VALUE string_spec_rb_str_new_offset(VALUE self, VALUE str, VALUE offset, VALUE len) {
  return rb_str_new(RSTRING_PTR(str) + FIX2INT(offset), FIX2INT(len));
}

VALUE string_spec_rb_str_new2(VALUE self, VALUE str) {
  if(NIL_P(str)) {
    return rb_str_new2("");
  } else {
    return rb_str_new2(RSTRING_PTR(str));
  }
}

VALUE string_spec_rb_str_encode(VALUE self, VALUE str, VALUE enc, VALUE flags, VALUE opts) {
  return rb_str_encode(str, enc, FIX2INT(flags), opts);
}

VALUE string_spec_rb_str_export_to_enc(VALUE self, VALUE str, VALUE enc) {
  return rb_str_export_to_enc(str, rb_to_encoding(enc));
}

VALUE string_spec_rb_str_new_cstr(VALUE self, VALUE str) {
  if(NIL_P(str)) {
    return rb_str_new_cstr("");
  } else {
    return rb_str_new_cstr(RSTRING_PTR(str));
  }
}

VALUE string_spec_rb_external_str_new(VALUE self, VALUE str) {
  return rb_external_str_new(RSTRING_PTR(str), RSTRING_LEN(str));
}

VALUE string_spec_rb_external_str_new_cstr(VALUE self, VALUE str) {
  return rb_external_str_new_cstr(RSTRING_PTR(str));
}

VALUE string_spec_rb_external_str_new_with_enc(VALUE self, VALUE str, VALUE len, VALUE encoding) {
  return rb_external_str_new_with_enc(RSTRING_PTR(str), FIX2LONG(len), rb_to_encoding(encoding));
}

VALUE string_spec_rb_locale_str_new(VALUE self, VALUE str, VALUE len) {
  return rb_locale_str_new(RSTRING_PTR(str), FIX2INT(len));
}

VALUE string_spec_rb_locale_str_new_cstr(VALUE self, VALUE str) {
  return rb_locale_str_new_cstr(RSTRING_PTR(str));
}

VALUE string_spec_rb_str_new3(VALUE self, VALUE str) {
  return rb_str_new3(str);
}

VALUE string_spec_rb_str_new4(VALUE self, VALUE str) {
  return rb_str_new4(str);
}

VALUE string_spec_rb_str_new5(VALUE self, VALUE str, VALUE ptr, VALUE len) {
  return rb_str_new5(str, RSTRING_PTR(ptr), FIX2INT(len));
}

VALUE string_spec_rb_tainted_str_new(VALUE self, VALUE str, VALUE len) {
  return rb_tainted_str_new(RSTRING_PTR(str), FIX2INT(len));
}

VALUE string_spec_rb_tainted_str_new2(VALUE self, VALUE str) {
  return rb_tainted_str_new2(RSTRING_PTR(str));
}

VALUE string_spec_rb_str_plus(VALUE self, VALUE str1, VALUE str2) {
  return rb_str_plus(str1, str2);
}

VALUE string_spec_rb_str_times(VALUE self, VALUE str, VALUE times) {
  return rb_str_times(str, times);
}

VALUE string_spec_rb_str_modify_expand(VALUE self, VALUE str, VALUE size) {
  rb_str_modify_expand(str, FIX2LONG(size));
  return str;
}

VALUE string_spec_rb_str_resize(VALUE self, VALUE str, VALUE size) {
  return rb_str_resize(str, FIX2INT(size));
}

VALUE string_spec_rb_str_resize_RSTRING_LEN(VALUE self, VALUE str, VALUE size) {
  VALUE modified = rb_str_resize(str, FIX2INT(size));
  return INT2FIX(RSTRING_LEN(modified));
}

VALUE string_spec_rb_str_split(VALUE self, VALUE str) {
  return rb_str_split(str, ",");
}

VALUE string_spec_rb_str_subseq(VALUE self, VALUE str, VALUE beg, VALUE len) {
  return rb_str_subseq(str, FIX2INT(beg), FIX2INT(len));
}

VALUE string_spec_rb_str_substr(VALUE self, VALUE str, VALUE beg, VALUE len) {
  return rb_str_substr(str, FIX2INT(beg), FIX2INT(len));
}

VALUE string_spec_rb_str_to_str(VALUE self, VALUE arg) {
  return rb_str_to_str(arg);
}

VALUE string_spec_RSTRING_LEN(VALUE self, VALUE str) {
  return INT2FIX(RSTRING_LEN(str));
}

VALUE string_spec_RSTRING_LENINT(VALUE self, VALUE str) {
  return INT2FIX(RSTRING_LENINT(str));
}

VALUE string_spec_RSTRING_PTR_iterate(VALUE self, VALUE str) {
  int i;
  char* ptr;

  ptr = RSTRING_PTR(str);
  for(i = 0; i < RSTRING_LEN(str); i++) {
    rb_yield(CHR2FIX(ptr[i]));
  }
  return Qnil;
}

VALUE string_spec_RSTRING_PTR_assign(VALUE self, VALUE str, VALUE chr) {
  int i;
  char c;
  char* ptr;

  ptr = RSTRING_PTR(str);
  c = FIX2INT(chr);

  for(i = 0; i < RSTRING_LEN(str); i++) {
    ptr[i] = c;
  }
  return Qnil;
}

VALUE string_spec_RSTRING_PTR_set(VALUE self, VALUE str, VALUE i, VALUE chr) {
  RSTRING_PTR(str)[FIX2INT(i)] = (char) FIX2INT(chr);
  return str;
}

VALUE string_spec_RSTRING_PTR_after_funcall(VALUE self, VALUE str, VALUE cb) {
  /* Silence gcc 4.3.2 warning about computed value not used */
  if(RSTRING_PTR(str)) { /* force it out */
    rb_funcall(cb, rb_intern("call"), 1, str);
  }

  return rb_str_new2(RSTRING_PTR(str));
}

VALUE string_spec_RSTRING_PTR_after_yield(VALUE self, VALUE str) {
  char* ptr = NATIVE_RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  VALUE from_rstring_ptr;

  ptr[0] = '1';
  rb_yield(str);
  ptr[2] = '2';

  from_rstring_ptr = rb_str_new(ptr, len);
  return from_rstring_ptr;
}

VALUE string_spec_StringValue(VALUE self, VALUE str) {
  return StringValue(str);
}

static VALUE string_spec_SafeStringValue(VALUE self, VALUE str) {
  SafeStringValue(str);
  return str;
}

static VALUE string_spec_rb_str_hash(VALUE self, VALUE str) {
  st_index_t val = rb_str_hash(str);

#if SIZEOF_LONG == SIZEOF_VOIDP || SIZEOF_LONG_LONG == SIZEOF_VOIDP
  return LONG2FIX((long)val);
#else
#error unsupported platform
#endif
}

static VALUE string_spec_rb_str_update(VALUE self, VALUE str, VALUE beg, VALUE end, VALUE replacement) {
  rb_str_update(str, FIX2LONG(beg), FIX2LONG(end), replacement);
  return str;
}

static VALUE string_spec_rb_str_free(VALUE self, VALUE str) {
  rb_str_free(str);
  return Qnil;
}

static VALUE string_spec_rb_sprintf1(VALUE self, VALUE str, VALUE repl) {
  return rb_sprintf(RSTRING_PTR(str), RSTRING_PTR(repl));
}
static VALUE string_spec_rb_sprintf2(VALUE self, VALUE str, VALUE repl1, VALUE repl2) {
  return rb_sprintf(RSTRING_PTR(str), RSTRING_PTR(repl1), RSTRING_PTR(repl2));
}

static VALUE string_spec_rb_sprintf3(VALUE self, VALUE str) {
  return rb_sprintf("Result: %"PRIsVALUE".", str);
}

static VALUE string_spec_rb_sprintf4(VALUE self, VALUE str) {
  return rb_sprintf("Result: %+"PRIsVALUE".", str);
}

static VALUE string_spec_rb_vsprintf_worker(char* fmt, ...) {
  va_list varargs;
  VALUE str;

  va_start(varargs, fmt);
  str = rb_vsprintf(fmt, varargs);
  va_end(varargs);

  return str;
}

static VALUE string_spec_rb_vsprintf(VALUE self, VALUE fmt, VALUE str, VALUE i, VALUE f) {
  return string_spec_rb_vsprintf_worker(RSTRING_PTR(fmt), RSTRING_PTR(str),
      FIX2INT(i), RFLOAT_VALUE(f));
}

VALUE string_spec_rb_str_equal(VALUE self, VALUE str1, VALUE str2) {
  return rb_str_equal(str1, str2);
}

static VALUE string_spec_rb_usascii_str_new(VALUE self, VALUE str, VALUE len) {
  return rb_usascii_str_new(RSTRING_PTR(str), NUM2INT(len));
}

static VALUE string_spec_rb_usascii_str_new_cstr(VALUE self, VALUE str) {
  return rb_usascii_str_new_cstr(RSTRING_PTR(str));
}

static VALUE string_spec_rb_String(VALUE self, VALUE val) {
  return rb_String(val);
}

static VALUE string_spec_rb_string_value_cstr(VALUE self, VALUE str) {
  char *c_str = rb_string_value_cstr(&str);
  return c_str ? Qtrue : Qfalse;
}

static VALUE string_spec_rb_str_modify(VALUE self, VALUE str) {
  rb_str_modify(str);
  return str;
}

static VALUE string_spec_rb_utf8_str_new_static(VALUE self) {
  return rb_utf8_str_new_static("nokogiri", 8);
}

static VALUE string_spec_rb_utf8_str_new(VALUE self) {
  return rb_utf8_str_new("nokogiri", 8);
}

static VALUE string_spec_rb_utf8_str_new_cstr(VALUE self) {
  return rb_utf8_str_new_cstr("nokogiri");
}

void Init_string_spec(void) {
  VALUE cls = rb_define_class("CApiStringSpecs", rb_cObject);
  rb_define_method(cls, "rb_cstr2inum", string_spec_rb_cstr2inum, 2);
  rb_define_method(cls, "rb_cstr_to_inum", string_spec_rb_cstr_to_inum, 3);
  rb_define_method(cls, "rb_str2inum", string_spec_rb_str2inum, 2);
  rb_define_method(cls, "rb_str_append", string_spec_rb_str_append, 2);
  rb_define_method(cls, "rb_str_buf_new", string_spec_rb_str_buf_new, 2);
  rb_define_method(cls, "rb_str_capacity", string_spec_rb_str_capacity, 1);
  rb_define_method(cls, "rb_str_buf_new2", string_spec_rb_str_buf_new2, 0);
  rb_define_method(cls, "rb_str_buf_cat", string_spec_rb_str_buf_cat, 1);
  rb_define_method(cls, "rb_str_cat", string_spec_rb_str_cat, 1);
  rb_define_method(cls, "rb_str_cat2", string_spec_rb_str_cat2, 1);
  rb_define_method(cls, "rb_str_cmp", string_spec_rb_str_cmp, 2);
  rb_define_method(cls, "rb_str_conv_enc", string_spec_rb_str_conv_enc, 3);
  rb_define_method(cls, "rb_str_conv_enc_opts", string_spec_rb_str_conv_enc_opts, 5);
  rb_define_method(cls, "rb_str_drop_bytes", string_spec_rb_str_drop_bytes, 2);
  rb_define_method(cls, "rb_str_export", string_spec_rb_str_export, 1);
  rb_define_method(cls, "rb_str_export_locale", string_spec_rb_str_export_locale, 1);
  rb_define_method(cls, "rb_str_dup", string_spec_rb_str_dup, 1);
  rb_define_method(cls, "rb_str_freeze", string_spec_rb_str_freeze, 1);
  rb_define_method(cls, "rb_str_inspect", string_spec_rb_str_inspect, 1);
  rb_define_method(cls, "rb_str_intern", string_spec_rb_str_intern, 1);
  rb_define_method(cls, "rb_str_length", string_spec_rb_str_length, 1);
  rb_define_method(cls, "rb_str_new", string_spec_rb_str_new, 2);
  rb_define_method(cls, "rb_str_new_native", string_spec_rb_str_new_native, 2);
  rb_define_method(cls, "rb_str_new_offset", string_spec_rb_str_new_offset, 3);
  rb_define_method(cls, "rb_str_new2", string_spec_rb_str_new2, 1);
  rb_define_method(cls, "rb_str_encode", string_spec_rb_str_encode, 4);
  rb_define_method(cls, "rb_str_export_to_enc", string_spec_rb_str_export_to_enc, 2);
  rb_define_method(cls, "rb_str_new_cstr", string_spec_rb_str_new_cstr, 1);
  rb_define_method(cls, "rb_external_str_new", string_spec_rb_external_str_new, 1);
  rb_define_method(cls, "rb_external_str_new_cstr", string_spec_rb_external_str_new_cstr, 1);
  rb_define_method(cls, "rb_external_str_new_with_enc", string_spec_rb_external_str_new_with_enc, 3);
  rb_define_method(cls, "rb_locale_str_new", string_spec_rb_locale_str_new, 2);
  rb_define_method(cls, "rb_locale_str_new_cstr", string_spec_rb_locale_str_new_cstr, 1);
  rb_define_method(cls, "rb_str_new3", string_spec_rb_str_new3, 1);
  rb_define_method(cls, "rb_str_new4", string_spec_rb_str_new4, 1);
  rb_define_method(cls, "rb_str_new5", string_spec_rb_str_new5, 3);
  rb_define_method(cls, "rb_tainted_str_new", string_spec_rb_tainted_str_new, 2);
  rb_define_method(cls, "rb_tainted_str_new2", string_spec_rb_tainted_str_new2, 1);
  rb_define_method(cls, "rb_str_plus", string_spec_rb_str_plus, 2);
  rb_define_method(cls, "rb_str_times", string_spec_rb_str_times, 2);
  rb_define_method(cls, "rb_str_modify_expand", string_spec_rb_str_modify_expand, 2);
  rb_define_method(cls, "rb_str_resize", string_spec_rb_str_resize, 2);
  rb_define_method(cls, "rb_str_resize_RSTRING_LEN", string_spec_rb_str_resize_RSTRING_LEN, 2);
  rb_define_method(cls, "rb_str_set_len", string_spec_rb_str_set_len, 2);
  rb_define_method(cls, "rb_str_set_len_RSTRING_LEN", string_spec_rb_str_set_len_RSTRING_LEN, 2);
  rb_define_method(cls, "rb_str_split", string_spec_rb_str_split, 1);
  rb_define_method(cls, "rb_str_subseq", string_spec_rb_str_subseq, 3);
  rb_define_method(cls, "rb_str_substr", string_spec_rb_str_substr, 3);
  rb_define_method(cls, "rb_str_to_str", string_spec_rb_str_to_str, 1);
  rb_define_method(cls, "RSTRING_LEN", string_spec_RSTRING_LEN, 1);
  rb_define_method(cls, "RSTRING_LENINT", string_spec_RSTRING_LENINT, 1);
  rb_define_method(cls, "RSTRING_PTR_iterate", string_spec_RSTRING_PTR_iterate, 1);
  rb_define_method(cls, "RSTRING_PTR_assign", string_spec_RSTRING_PTR_assign, 2);
  rb_define_method(cls, "RSTRING_PTR_set", string_spec_RSTRING_PTR_set, 3);
  rb_define_method(cls, "RSTRING_PTR_after_funcall", string_spec_RSTRING_PTR_after_funcall, 2);
  rb_define_method(cls, "RSTRING_PTR_after_yield", string_spec_RSTRING_PTR_after_yield, 1);
  rb_define_method(cls, "StringValue", string_spec_StringValue, 1);
  rb_define_method(cls, "SafeStringValue", string_spec_SafeStringValue, 1);
  rb_define_method(cls, "rb_str_hash", string_spec_rb_str_hash, 1);
  rb_define_method(cls, "rb_str_update", string_spec_rb_str_update, 4);
  rb_define_method(cls, "rb_str_free", string_spec_rb_str_free, 1);
  rb_define_method(cls, "rb_sprintf1", string_spec_rb_sprintf1, 2);
  rb_define_method(cls, "rb_sprintf2", string_spec_rb_sprintf2, 3);
  rb_define_method(cls, "rb_sprintf3", string_spec_rb_sprintf3, 1);
  rb_define_method(cls, "rb_sprintf4", string_spec_rb_sprintf4, 1);
  rb_define_method(cls, "rb_vsprintf", string_spec_rb_vsprintf, 4);
  rb_define_method(cls, "rb_str_equal", string_spec_rb_str_equal, 2);
  rb_define_method(cls, "rb_usascii_str_new", string_spec_rb_usascii_str_new, 2);
  rb_define_method(cls, "rb_usascii_str_new_cstr", string_spec_rb_usascii_str_new_cstr, 1);
  rb_define_method(cls, "rb_String", string_spec_rb_String, 1);
  rb_define_method(cls, "rb_string_value_cstr", string_spec_rb_string_value_cstr, 1);
  rb_define_method(cls, "rb_str_modify", string_spec_rb_str_modify, 1);
  rb_define_method(cls, "rb_utf8_str_new_static", string_spec_rb_utf8_str_new_static, 0);
  rb_define_method(cls, "rb_utf8_str_new", string_spec_rb_utf8_str_new, 0);
  rb_define_method(cls, "rb_utf8_str_new_cstr", string_spec_rb_utf8_str_new_cstr, 0);
}

#ifdef __cplusplus
}
#endif
