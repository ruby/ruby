#include "ruby.h"

#define	_AUTO		0
#define	_JIS		1
#define	_EUC		2
#define	_SJIS		3
#define	_BINARY		4
#define	_NOCONV		4
#define	_UNKNOWN	_AUTO

#undef getc
#undef ungetc
#define getc(f)   	(input_ctr<i_len?input[input_ctr++]:-1)
#define ungetc(c,f)	input_ctr--

#undef putchar
#define putchar(c)	rb_nkf_putchar(c)

#define INCSIZE		32
static int incsize;

static unsigned char *input, *output;
static int input_ctr, i_len;
static int output_ctr, o_len;

static VALUE dst;

static int
rb_nkf_putchar(c)
     unsigned int c;
{
  if (output_ctr >= o_len) {
    o_len += incsize;
    rb_str_cat(dst, 0, incsize);
    output = RSTRING(dst)->ptr;
    incsize *= 2;
  }
  output[output_ctr++] = c;

  return c;
}

#define PERL_XS 1
#include "nkf1.7/nkf.c"

static VALUE
rb_nkf_kconv(obj, opt, src)
     VALUE obj, opt, src;
{
  int i;
  char *opt_ptr, *opt_end;
  volatile VALUE v;

  reinit();
  opt_ptr = str2cstr(opt, &i);
  opt_end = opt_ptr + i;
  for (; opt_ptr < opt_end; opt_ptr++) {
    if (*opt_ptr != '-') {
      continue;
    }
    arguments(opt_ptr);
  }

  incsize = INCSIZE;

  input_ctr = 0; 
  input     = str2cstr(src, &i_len);
  dst = rb_str_new(0, i_len*3 + 10);
  v = dst;

  output_ctr = 0;
  output     = RSTRING(dst)->ptr;
  o_len      = RSTRING(dst)->len;
  *output    = '\0';

  if(iso8859_f && (oconv != j_oconv || !x0201_f )) {
    iso8859_f = FALSE;
  } 

  kanji_convert(NULL);
  RSTRING(dst)->ptr[output_ctr] = '\0';
  RSTRING(dst)->len = output_ctr;
  if(OBJ_TAINTED(src))
    OBJ_TAINT(dst);

  return dst;
}

/*
 * Character code detection - Algorithm described in:
 * Ken Lunde. `Understanding Japanese Information Processing'
 * Sebastopol, CA: O'Reilly & Associates.
 */

static VALUE
rb_nkf_guess(obj, src)
     VALUE obj, src;
{
  unsigned char *p;
  unsigned char *pend;
  int plen;
  int sequence_counter = 0;

  Check_Type(src, T_STRING);

  p = str2cstr(src, &plen);
  pend = p + plen;

#define INCR do {\
    p++;\
    if (p==pend) return INT2FIX(_UNKNOWN);\
    sequence_counter++;\
    if (sequence_counter % 2 == 1 && *p != 0xa4)\
	sequence_counter = 0;\
    if (6 <= sequence_counter) {\
	sequence_counter = 0;\
	return INT2FIX(_EUC);\
    }\
} while (0)

  if (*p == 0xa4)
    sequence_counter = 1;

  while (p<pend) {
    if (*p == '\033') {
      return INT2FIX(_JIS);
    }
    if (*p < '\006' || *p == 0x7f || *p == 0xff) {
      return INT2FIX(_BINARY);
    }
    if (0x81 <= *p && *p <= 0x8d) {
      return INT2FIX(_SJIS);
    }
    if (0x8f <= *p && *p <= 0x9f) {
      return INT2FIX(_SJIS);
    }
    if (*p == 0x8e) {	/* SS2 */
      INCR;
      if ((0x40 <= *p && *p <= 0x7e) ||
	  (0x80 <= *p && *p <= 0xa0) ||
	  (0xe0 <= *p && *p <= 0xfc))
	return INT2FIX(_SJIS);
    }
    else if (0xa1 <= *p && *p <= 0xdf) {
      INCR;
      if (0xf0 <= *p && *p <= 0xfe)
	return INT2FIX(_EUC);
      if (0xe0 <= *p && *p <= 0xef) {
	while (p < pend && *p >= 0x40) {
	  if (*p >= 0x81) {
	    if (*p <= 0x8d || (0x8f <= *p && *p <= 0x9f)) {
	      return INT2FIX(_SJIS);
	    }
	    else if (0xfd <= *p && *p <= 0xfe) {
	      return INT2FIX(_EUC);
	    }
	  }
	  INCR;
	}
      }
      else if (*p <= 0x9f) {
	return INT2FIX(_SJIS);
      }
    }
    else if (0xf0 <= *p && *p <= 0xfe) {
      return INT2FIX(_EUC);
    }
    else if (0xe0 <= *p && *p <= 0xef) {
      INCR;
      if ((0x40 <= *p && *p <= 0x7e) ||
	  (0x80 <= *p && *p <= 0xa0)) {
	return INT2FIX(_SJIS);
      }
      if (0xfd <= *p && *p <= 0xfe) {
	return INT2FIX(_EUC);
      }
    }
    INCR;
  }
  return INT2FIX(_UNKNOWN);
}

void
Init_nkf()
{
    VALUE mKconv = rb_define_module("NKF");

    rb_define_module_function(mKconv, "nkf", rb_nkf_kconv, 2);
    rb_define_module_function(mKconv, "guess", rb_nkf_guess, 1);

    rb_define_const(mKconv, "AUTO", INT2FIX(_AUTO));
    rb_define_const(mKconv, "JIS", INT2FIX(_JIS));
    rb_define_const(mKconv, "EUC", INT2FIX(_EUC));
    rb_define_const(mKconv, "SJIS", INT2FIX(_SJIS));
    rb_define_const(mKconv, "BINARY", INT2FIX(_BINARY));
    rb_define_const(mKconv, "NOCONV", INT2FIX(_NOCONV));
    rb_define_const(mKconv, "UNKNOWN", INT2FIX(_UNKNOWN));
}
