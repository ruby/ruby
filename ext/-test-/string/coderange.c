#include "ruby/ruby.h"
#include "ruby/encoding.h"

static VALUE sym_7bit, sym_valid, sym_unknown, sym_broken;

static VALUE
coderange_int2sym(int coderange)
{
    switch (coderange) {
      case ENC_CODERANGE_7BIT:
	return sym_7bit;
      case ENC_CODERANGE_VALID:
	return sym_valid;
      case ENC_CODERANGE_UNKNOWN:
	return sym_unknown;
      case ENC_CODERANGE_BROKEN:
	return sym_broken;
    }
    rb_bug("wrong condition of coderange");
    UNREACHABLE;
}

/* return coderange without scan */
static VALUE
str_coderange(VALUE str)
{
    return coderange_int2sym(ENC_CODERANGE(str));
}

/* scan coderange and return the result */
static VALUE
str_coderange_scan(VALUE str)
{
    ENC_CODERANGE_SET(str, ENC_CODERANGE_UNKNOWN);
    return coderange_int2sym(rb_enc_str_coderange(str));
}

void
Init_coderange(VALUE klass)
{
    sym_7bit = ID2SYM(rb_intern("7bit"));
    sym_valid = ID2SYM(rb_intern("valid"));
    sym_unknown = ID2SYM(rb_intern("unknown"));
    sym_broken = ID2SYM(rb_intern("broken"));
    rb_define_method(klass, "coderange", str_coderange, 0);
    rb_define_method(klass, "coderange_scan", str_coderange_scan, 0);
}
