/*
 * NKF Module for Ruby base on nkf 2.x
 *
 * original nkf2.0 is maintained at http://sourceforge.jp/projects/nkf/
 *
 */

static char *RVersion = "2.0.4.1r1";

#include "ruby.h"

/* Encoding Constants */
#define	_AUTO		0
#define	_JIS		1
#define	_EUC		2
#define	_SJIS		3
#define	_BINARY		4
#define	_NOCONV		4
#define	_ASCII		5
/* 0b011x is reserved for UTF-8 Family */
#define	_UTF8		6
/* 0b10xx is reserved for UTF-16 Family */
#define	_UTF16		8
/* 0b11xx is reserved for UTF-32 Family */
#define	_UTF32		12
#define	_OTHER		16
#define	_UNKNOWN	_AUTO

/* Replace nkf's getchar/putchar for variable modification */
/* we never use getc, ungetc */

#undef getc
#undef ungetc
#define getc(f)         (input_ctr>=i_len?-1:input[input_ctr++])
#define ungetc(c,f)     input_ctr--

#define INCSIZE         32
#undef putchar
#undef TRUE
#undef FALSE
#define putchar(c)      rb_nkf_putchar(c)

/* Input/Output pointers */

static unsigned char *output;
static unsigned char *input;
static int input_ctr;
static int i_len;
static int output_ctr;
static int o_len;
static int incsize;

static VALUE result;

static int
rb_nkf_putchar(c)
  unsigned int c;
{
  if (output_ctr >= o_len) {
    o_len += incsize;
    rb_str_resize(result, o_len);
    incsize *= 2;
    output = RSTRING(result)->ptr;
  }
  output[output_ctr++] = c;

  return c;
}

/* Include kanji filter main part */
/* getchar and putchar will be replaced during inclusion */

#define PERL_XS 1
#include "nkf-utf8/utf8tbl.c"
#include "nkf-utf8/nkf.c"

static VALUE
rb_nkf_kconv(obj, opt, src)
  VALUE obj, opt, src;
{
  char *opt_ptr, *opt_end;
  volatile VALUE v;

  reinit();
  StringValue(opt);
  opt_ptr = RSTRING(opt)->ptr;
  opt_end = opt_ptr + RSTRING(opt)->len;
  for (; opt_ptr < opt_end; opt_ptr++) {
    if (*opt_ptr != '-') {
      continue;
    }
    options(opt_ptr);
  }

  incsize = INCSIZE;

  input_ctr = 0;
  StringValue(src);
  input = RSTRING(src)->ptr;
  i_len = RSTRING(src)->len;
  result = rb_str_new(0, i_len*3 + 10);
  v = result;

  output_ctr = 0;
  output     = RSTRING(result)->ptr;
  o_len      = RSTRING(result)->len;
  *output    = '\0';

  if(x0201_f == WISH_TRUE)
    x0201_f = ((!iso2022jp_f)? TRUE : NO_X0201);

  kanji_convert(NULL);
  RSTRING(result)->ptr[output_ctr] = '\0';
  RSTRING(result)->len = output_ctr;
  OBJ_INFECT(result, src);

  return result;
}


/*
 * NKF.guess1
 *
 * Character code detection - Algorithm described in:
 * Ken Lunde. `Understanding Japanese Information Processing'
 * Sebastopol, CA: O'Reilly & Associates.
 */

static VALUE
rb_nkf_guess1(obj, src)
  VALUE obj, src;
{
  unsigned char *p;
  unsigned char *pend;
  int sequence_counter = 0;

  StringValue(src);
  p = RSTRING(src)->ptr;
  pend = p + RSTRING(src)->len;
  if (p == pend) return INT2FIX(_UNKNOWN);

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


/*
 * NKF.guess2
 *
 * Guess Encoding By NKF2.0 Routine 
 */

static VALUE
rb_nkf_guess2(obj, src)
  VALUE obj, src;
{
  int code = _BINARY;

  reinit();

  input_ctr = 0;
  StringValue(src);
  input = RSTRING(src)->ptr;
  i_len = RSTRING(src)->len;

  if(x0201_f == WISH_TRUE)
    x0201_f = ((!iso2022jp_f)? TRUE : NO_X0201);

  guess_f = TRUE;
  kanji_convert( NULL );
  guess_f = FALSE;

  if (!is_inputcode_mixed) {
    if (strcmp(input_codename, "") == 0) {
      code = _ASCII;
    } else if (strcmp(input_codename, "ISO-2022-JP") == 0) {
      code = _JIS;
    } else if (strcmp(input_codename, "EUC-JP") == 0) {
      code = _EUC;
    } else if (strcmp(input_codename, "Shift_JIS") == 0) {
      code = _SJIS;
    } else if (strcmp(input_codename, "UTF-8") == 0) {
      code = _UTF8;
    } else if (strcmp(input_codename, "UTF-16") == 0) {
      code = _UTF16;
    } else if (strlen(input_codename) > 0) {
      code = _UNKNOWN;
    }
  }

  return INT2FIX( code );
}


/* Initialize NKF Module */

void
Init_nkf()
{
  VALUE mKconv = rb_define_module("NKF");

  rb_define_module_function(mKconv, "nkf", rb_nkf_kconv, 2);
  rb_define_module_function(mKconv, "guess", rb_nkf_guess1, 1);
  rb_define_module_function(mKconv, "guess1", rb_nkf_guess1, 1);
  rb_define_module_function(mKconv, "guess2", rb_nkf_guess2, 1);

  rb_define_const(mKconv, "AUTO", INT2FIX(_AUTO));
  rb_define_const(mKconv, "JIS", INT2FIX(_JIS));
  rb_define_const(mKconv, "EUC", INT2FIX(_EUC));
  rb_define_const(mKconv, "SJIS", INT2FIX(_SJIS));
  rb_define_const(mKconv, "BINARY", INT2FIX(_BINARY));
  rb_define_const(mKconv, "NOCONV", INT2FIX(_NOCONV));
  rb_define_const(mKconv, "ASCII", INT2FIX(_ASCII));
  rb_define_const(mKconv, "UTF8", INT2FIX(_UTF8));
  rb_define_const(mKconv, "UTF16", INT2FIX(_UTF16));
  rb_define_const(mKconv, "UTF32", INT2FIX(_UTF32));
  rb_define_const(mKconv, "UNKNOWN", INT2FIX(_UNKNOWN));
  rb_define_const(mKconv, "VERSION", rb_str_new2(RVersion));
}
