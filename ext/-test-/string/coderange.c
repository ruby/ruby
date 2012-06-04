#include "ruby/ruby.h"
#include "ruby/encoding.h"

static VALUE sym_7bit, sym_valid, sym_unknown, sym_broken;
static VALUE
str_coderange(VALUE str)
{
    switch (ENC_CODERANGE(str)) {
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

void
Init_coderange(VALUE klass)
{
    sym_7bit = ID2SYM(rb_intern("7bit"));
    sym_valid = ID2SYM(rb_intern("valid"));
    sym_unknown = ID2SYM(rb_intern("unknown"));
    sym_broken = ID2SYM(rb_intern("broken"));
    rb_define_method(klass, "coderange", str_coderange, 0);
}
