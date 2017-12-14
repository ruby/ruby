#include <ruby.h>
#include <ruby/encoding.h>

static VALUE
printf_test_s(VALUE self, VALUE obj)
{
    return rb_enc_sprintf(rb_usascii_encoding(), "<%"PRIsVALUE">", obj);
}

static VALUE
printf_test_v(VALUE self, VALUE obj)
{
    return rb_enc_sprintf(rb_usascii_encoding(), "{%+"PRIsVALUE"}", obj);
}

static VALUE
printf_test_q(VALUE self, VALUE obj)
{
    return rb_enc_sprintf(rb_usascii_encoding(), "[% "PRIsVALUE"]", obj);
}

static char *
uint_to_str(char *p, char *e, unsigned int x)
{
    char *e0 = e;
    if (e <= p) return p;
    do {
	*--e = x % 10 + '0';
    } while ((x /= 10) != 0 && e > p);
    memmove(p, e, e0 - e);
    return p + (e0 - e);
}

static VALUE
printf_test_call(int argc, VALUE *argv, VALUE self)
{
    VALUE opt, type, num, result;
    char format[sizeof(int) * 6 + 8], *p = format, cnv;
    int n = 0;
    const char *s = 0;

    rb_scan_args(argc, argv, "2:", &type, &num, &opt);
    Check_Type(type, T_STRING);
    if (RSTRING_LEN(type) != 1) rb_raise(rb_eArgError, "wrong length(%ld)", RSTRING_LEN(type));
    switch (cnv = RSTRING_PTR(type)[0]) {
      case 'd': case 'x': case 'o': case 'X':
	n = NUM2INT(num);
	break;
      case 's':
	s = StringValueCStr(num);
	break;
      default: rb_raise(rb_eArgError, "wrong conversion(%c)", cnv);
    }
    *p++ = '%';
    if (!NIL_P(opt)) {
	VALUE v;
	Check_Type(opt, T_HASH);
	if (RTEST(rb_hash_aref(opt, ID2SYM(rb_intern("space"))))) {
	    *p++ = ' ';
	}
	if (RTEST(rb_hash_aref(opt, ID2SYM(rb_intern("hash"))))) {
	    *p++ = '#';
	}
	if (RTEST(rb_hash_aref(opt, ID2SYM(rb_intern("plus"))))) {
	    *p++ = '+';
	}
	if (RTEST(rb_hash_aref(opt, ID2SYM(rb_intern("minus"))))) {
	    *p++ = '-';
	}
	if (RTEST(rb_hash_aref(opt, ID2SYM(rb_intern("zero"))))) {
	    *p++ = '0';
	}
	if (!NIL_P(v = rb_hash_aref(opt, ID2SYM(rb_intern("width"))))) {
	    p = uint_to_str(p, format + sizeof(format), NUM2UINT(v));
	}
	if (!NIL_P(v = rb_hash_aref(opt, ID2SYM(rb_intern("prec"))))) {
	    *p++ = '.';
	    if (FIXNUM_P(v))
		p = uint_to_str(p, format + sizeof(format), NUM2UINT(v));
	}
    }
    *p++ = cnv;
    *p++ = '\0';
    if (cnv == 's') {
	result = rb_enc_sprintf(rb_usascii_encoding(), format, s);
    }
    else {
	result = rb_enc_sprintf(rb_usascii_encoding(), format, n);
    }
    return rb_assoc_new(result, rb_usascii_str_new_cstr(format));
}

void
Init_printf(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Printf");
    rb_define_singleton_method(m, "s", printf_test_s, 1);
    rb_define_singleton_method(m, "v", printf_test_v, 1);
    rb_define_singleton_method(m, "q", printf_test_q, 1);
    rb_define_singleton_method(m, "call", printf_test_call, -1);
}
