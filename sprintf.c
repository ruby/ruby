/**********************************************************************

  sprintf.c -

  $Author$
  created at: Fri Oct 15 10:39:26 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "internal.h"
#include "ruby/re.h"
#include "id.h"
#include <math.h>
#include <stdarg.h>

#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

#define BIT_DIGITS(N)   (((N)*146)/485 + 1)  /* log2(10) =~ 146/485 */

static void fmt_setup(char*,size_t,int,int,int,int);

static char
sign_bits(int base, const char *p)
{
    char c = '.';

    switch (base) {
      case 16:
	if (*p == 'X') c = 'F';
	else c = 'f';
	break;
      case 8:
	c = '7'; break;
      case 2:
	c = '1'; break;
    }
    return c;
}

#define FNONE  0
#define FSHARP 1
#define FMINUS 2
#define FPLUS  4
#define FZERO  8
#define FSPACE 16
#define FWIDTH 32
#define FPREC  64
#define FPREC0 128

#define CHECK(l) do {\
    int cr = ENC_CODERANGE(result);\
    while (blen + (l) >= bsiz) {\
	bsiz*=2;\
    }\
    rb_str_resize(result, bsiz);\
    ENC_CODERANGE_SET(result, cr);\
    buf = RSTRING_PTR(result);\
} while (0)

#define PUSH(s, l) do { \
    CHECK(l);\
    memcpy(&buf[blen], (s), (l));\
    blen += (l);\
} while (0)

#define FILL(c, l) do { \
    CHECK(l);\
    memset(&buf[blen], (c), (l));\
    blen += (l);\
} while (0)

#define GETARG() (nextvalue != Qundef ? nextvalue : \
		  GETNEXTARG())

#define GETNEXTARG() ( \
    check_next_arg(posarg, nextarg), \
    (posarg = nextarg++, GETNTHARG(posarg)))

#define GETPOSARG(n) ( \
    check_pos_arg(posarg, (n)), \
    (posarg = -1, GETNTHARG(n)))

#define GETNTHARG(nth) \
    (((nth) >= argc) ? (rb_raise(rb_eArgError, "too few arguments"), 0) : argv[(nth)])

#define CHECKNAMEARG(name, len, enc) ( \
    check_name_arg(posarg, name, len, enc), \
    posarg = -2)

#define GETNUM(n, val) \
    (!(p = get_num(p, end, enc, &(n))) ? \
     rb_raise(rb_eArgError, #val " too big") : (void)0)

#define GETASTER(val) do { \
    t = p++; \
    n = 0; \
    GETNUM(n, val); \
    if (*p == '$') { \
	tmp = GETPOSARG(n); \
    } \
    else { \
	tmp = GETNEXTARG(); \
	p = t; \
    } \
    (val) = NUM2INT(tmp); \
} while (0)

static const char *
get_num(const char *p, const char *end, rb_encoding *enc, int *valp)
{
    int next_n = *valp;
    for (; p < end && rb_enc_isdigit(*p, enc); p++) {
	if (MUL_OVERFLOW_INT_P(10, next_n))
	    return NULL;
	next_n *= 10;
	if (INT_MAX - (*p - '0') < next_n)
	    return NULL;
	next_n += *p - '0';
    }
    if (p >= end) {
	rb_raise(rb_eArgError, "malformed format string - %%*[0-9]");
    }
    *valp = next_n;
    return p;
}

static void
check_next_arg(int posarg, int nextarg)
{
    switch (posarg) {
      case -1:
	rb_raise(rb_eArgError, "unnumbered(%d) mixed with numbered", nextarg);
      case -2:
	rb_raise(rb_eArgError, "unnumbered(%d) mixed with named", nextarg);
    }
}

static void
check_pos_arg(int posarg, int n)
{
    if (posarg > 0) {
	rb_raise(rb_eArgError, "numbered(%d) after unnumbered(%d)", n, posarg);
    }
    if (posarg == -2) {
	rb_raise(rb_eArgError, "numbered(%d) after named", n);
    }
    if (n < 1) {
	rb_raise(rb_eArgError, "invalid index - %d$", n);
    }
}

static void
check_name_arg(int posarg, const char *name, int len, rb_encoding *enc)
{
    if (posarg > 0) {
	rb_enc_raise(enc, rb_eArgError, "named%.*s after unnumbered(%d)", len, name, posarg);
    }
    if (posarg == -1) {
	rb_enc_raise(enc, rb_eArgError, "named%.*s after numbered", len, name);
    }
}

static VALUE
get_hash(volatile VALUE *hash, int argc, const VALUE *argv)
{
    VALUE tmp;

    if (*hash != Qundef) return *hash;
    if (argc != 2) {
	rb_raise(rb_eArgError, "one hash required");
    }
    tmp = rb_check_hash_type(argv[1]);
    if (NIL_P(tmp)) {
	rb_raise(rb_eArgError, "one hash required");
    }
    return (*hash = tmp);
}

/*
 *  call-seq:
 *     format(format_string [, arguments...] )   -> string
 *     sprintf(format_string [, arguments...] )  -> string
 *
 *  Returns the string resulting from applying <i>format_string</i> to
 *  any additional arguments.  Within the format string, any characters
 *  other than format sequences are copied to the result.
 *
 *  The syntax of a format sequence is follows.
 *
 *    %[flags][width][.precision]type
 *
 *  A format
 *  sequence consists of a percent sign, followed by optional flags,
 *  width, and precision indicators, then terminated with a field type
 *  character.  The field type controls how the corresponding
 *  <code>sprintf</code> argument is to be interpreted, while the flags
 *  modify that interpretation.
 *
 *  The field type characters are:
 *
 *      Field |  Integer Format
 *      ------+--------------------------------------------------------------
 *        b   | Convert argument as a binary number.
 *            | Negative numbers will be displayed as a two's complement
 *            | prefixed with `..1'.
 *        B   | Equivalent to `b', but uses an uppercase 0B for prefix
 *            | in the alternative format by #.
 *        d   | Convert argument as a decimal number.
 *        i   | Identical to `d'.
 *        o   | Convert argument as an octal number.
 *            | Negative numbers will be displayed as a two's complement
 *            | prefixed with `..7'.
 *        u   | Identical to `d'.
 *        x   | Convert argument as a hexadecimal number.
 *            | Negative numbers will be displayed as a two's complement
 *            | prefixed with `..f' (representing an infinite string of
 *            | leading 'ff's).
 *        X   | Equivalent to `x', but uses uppercase letters.
 *
 *      Field |  Float Format
 *      ------+--------------------------------------------------------------
 *        e   | Convert floating point argument into exponential notation
 *            | with one digit before the decimal point as [-]d.dddddde[+-]dd.
 *            | The precision specifies the number of digits after the decimal
 *            | point (defaulting to six).
 *        E   | Equivalent to `e', but uses an uppercase E to indicate
 *            | the exponent.
 *        f   | Convert floating point argument as [-]ddd.dddddd,
 *            | where the precision specifies the number of digits after
 *            | the decimal point.
 *        g   | Convert a floating point number using exponential form
 *            | if the exponent is less than -4 or greater than or
 *            | equal to the precision, or in dd.dddd form otherwise.
 *            | The precision specifies the number of significant digits.
 *        G   | Equivalent to `g', but use an uppercase `E' in exponent form.
 *        a   | Convert floating point argument as [-]0xh.hhhhp[+-]dd,
 *            | which is consisted from optional sign, "0x", fraction part
 *            | as hexadecimal, "p", and exponential part as decimal.
 *        A   | Equivalent to `a', but use uppercase `X' and `P'.
 *
 *      Field |  Other Format
 *      ------+--------------------------------------------------------------
 *        c   | Argument is the numeric code for a single character or
 *            | a single character string itself.
 *        p   | The valuing of argument.inspect.
 *        s   | Argument is a string to be substituted.  If the format
 *            | sequence contains a precision, at most that many characters
 *            | will be copied.
 *        %   | A percent sign itself will be displayed.  No argument taken.
 *
 *  The flags modifies the behavior of the formats.
 *  The flag characters are:
 *
 *    Flag     | Applies to    | Meaning
 *    ---------+---------------+-----------------------------------------
 *    space    | bBdiouxX      | Leave a space at the start of
 *             | aAeEfgG       | non-negative numbers.
 *             | (numeric fmt) | For `o', `x', `X', `b' and `B', use
 *             |               | a minus sign with absolute value for
 *             |               | negative values.
 *    ---------+---------------+-----------------------------------------
 *    (digit)$ | all           | Specifies the absolute argument number
 *             |               | for this field.  Absolute and relative
 *             |               | argument numbers cannot be mixed in a
 *             |               | sprintf string.
 *    ---------+---------------+-----------------------------------------
 *     #       | bBoxX         | Use an alternative format.
 *             | aAeEfgG       | For the conversions `o', increase the precision
 *             |               | until the first digit will be `0' if
 *             |               | it is not formatted as complements.
 *             |               | For the conversions `x', `X', `b' and `B'
 *             |               | on non-zero, prefix the result with ``0x'',
 *             |               | ``0X'', ``0b'' and ``0B'', respectively.
 *             |               | For `a', `A', `e', `E', `f', `g', and 'G',
 *             |               | force a decimal point to be added,
 *             |               | even if no digits follow.
 *             |               | For `g' and 'G', do not remove trailing zeros.
 *    ---------+---------------+-----------------------------------------
 *    +        | bBdiouxX      | Add a leading plus sign to non-negative
 *             | aAeEfgG       | numbers.
 *             | (numeric fmt) | For `o', `x', `X', `b' and `B', use
 *             |               | a minus sign with absolute value for
 *             |               | negative values.
 *    ---------+---------------+-----------------------------------------
 *    -        | all           | Left-justify the result of this conversion.
 *    ---------+---------------+-----------------------------------------
 *    0 (zero) | bBdiouxX      | Pad with zeros, not spaces.
 *             | aAeEfgG       | For `o', `x', `X', `b' and `B', radix-1
 *             | (numeric fmt) | is used for negative numbers formatted as
 *             |               | complements.
 *    ---------+---------------+-----------------------------------------
 *    *        | all           | Use the next argument as the field width.
 *             |               | If negative, left-justify the result. If the
 *             |               | asterisk is followed by a number and a dollar
 *             |               | sign, use the indicated argument as the width.
 *
 *  Examples of flags:
 *
 *   # `+' and space flag specifies the sign of non-negative numbers.
 *   sprintf("%d", 123)  #=> "123"
 *   sprintf("%+d", 123) #=> "+123"
 *   sprintf("% d", 123) #=> " 123"
 *
 *   # `#' flag for `o' increases number of digits to show `0'.
 *   # `+' and space flag changes format of negative numbers.
 *   sprintf("%o", 123)   #=> "173"
 *   sprintf("%#o", 123)  #=> "0173"
 *   sprintf("%+o", -123) #=> "-173"
 *   sprintf("%o", -123)  #=> "..7605"
 *   sprintf("%#o", -123) #=> "..7605"
 *
 *   # `#' flag for `x' add a prefix `0x' for non-zero numbers.
 *   # `+' and space flag disables complements for negative numbers.
 *   sprintf("%x", 123)   #=> "7b"
 *   sprintf("%#x", 123)  #=> "0x7b"
 *   sprintf("%+x", -123) #=> "-7b"
 *   sprintf("%x", -123)  #=> "..f85"
 *   sprintf("%#x", -123) #=> "0x..f85"
 *   sprintf("%#x", 0)    #=> "0"
 *
 *   # `#' for `X' uses the prefix `0X'.
 *   sprintf("%X", 123)  #=> "7B"
 *   sprintf("%#X", 123) #=> "0X7B"
 *
 *   # `#' flag for `b' add a prefix `0b' for non-zero numbers.
 *   # `+' and space flag disables complements for negative numbers.
 *   sprintf("%b", 123)   #=> "1111011"
 *   sprintf("%#b", 123)  #=> "0b1111011"
 *   sprintf("%+b", -123) #=> "-1111011"
 *   sprintf("%b", -123)  #=> "..10000101"
 *   sprintf("%#b", -123) #=> "0b..10000101"
 *   sprintf("%#b", 0)    #=> "0"
 *
 *   # `#' for `B' uses the prefix `0B'.
 *   sprintf("%B", 123)  #=> "1111011"
 *   sprintf("%#B", 123) #=> "0B1111011"
 *
 *   # `#' for `e' forces to show the decimal point.
 *   sprintf("%.0e", 1)  #=> "1e+00"
 *   sprintf("%#.0e", 1) #=> "1.e+00"
 *
 *   # `#' for `f' forces to show the decimal point.
 *   sprintf("%.0f", 1234)  #=> "1234"
 *   sprintf("%#.0f", 1234) #=> "1234."
 *
 *   # `#' for `g' forces to show the decimal point.
 *   # It also disables stripping lowest zeros.
 *   sprintf("%g", 123.4)   #=> "123.4"
 *   sprintf("%#g", 123.4)  #=> "123.400"
 *   sprintf("%g", 123456)  #=> "123456"
 *   sprintf("%#g", 123456) #=> "123456."
 *
 *  The field width is an optional integer, followed optionally by a
 *  period and a precision.  The width specifies the minimum number of
 *  characters that will be written to the result for this field.
 *
 *  Examples of width:
 *
 *   # padding is done by spaces,       width=20
 *   # 0 or radix-1.             <------------------>
 *   sprintf("%20d", 123)   #=> "                 123"
 *   sprintf("%+20d", 123)  #=> "                +123"
 *   sprintf("%020d", 123)  #=> "00000000000000000123"
 *   sprintf("%+020d", 123) #=> "+0000000000000000123"
 *   sprintf("% 020d", 123) #=> " 0000000000000000123"
 *   sprintf("%-20d", 123)  #=> "123                 "
 *   sprintf("%-+20d", 123) #=> "+123                "
 *   sprintf("%- 20d", 123) #=> " 123                "
 *   sprintf("%020x", -123) #=> "..ffffffffffffffff85"
 *
 *  For
 *  numeric fields, the precision controls the number of decimal places
 *  displayed.  For string fields, the precision determines the maximum
 *  number of characters to be copied from the string.  (Thus, the format
 *  sequence <code>%10.10s</code> will always contribute exactly ten
 *  characters to the result.)
 *
 *  Examples of precisions:
 *
 *   # precision for `d', 'o', 'x' and 'b' is
 *   # minimum number of digits               <------>
 *   sprintf("%20.8d", 123)  #=> "            00000123"
 *   sprintf("%20.8o", 123)  #=> "            00000173"
 *   sprintf("%20.8x", 123)  #=> "            0000007b"
 *   sprintf("%20.8b", 123)  #=> "            01111011"
 *   sprintf("%20.8d", -123) #=> "           -00000123"
 *   sprintf("%20.8o", -123) #=> "            ..777605"
 *   sprintf("%20.8x", -123) #=> "            ..ffff85"
 *   sprintf("%20.8b", -11)  #=> "            ..110101"
 *
 *   # "0x" and "0b" for `#x' and `#b' is not counted for
 *   # precision but "0" for `#o' is counted.  <------>
 *   sprintf("%#20.8d", 123)  #=> "            00000123"
 *   sprintf("%#20.8o", 123)  #=> "            00000173"
 *   sprintf("%#20.8x", 123)  #=> "          0x0000007b"
 *   sprintf("%#20.8b", 123)  #=> "          0b01111011"
 *   sprintf("%#20.8d", -123) #=> "           -00000123"
 *   sprintf("%#20.8o", -123) #=> "            ..777605"
 *   sprintf("%#20.8x", -123) #=> "          0x..ffff85"
 *   sprintf("%#20.8b", -11)  #=> "          0b..110101"
 *
 *   # precision for `e' is number of
 *   # digits after the decimal point           <------>
 *   sprintf("%20.8e", 1234.56789) #=> "      1.23456789e+03"
 *
 *   # precision for `f' is number of
 *   # digits after the decimal point               <------>
 *   sprintf("%20.8f", 1234.56789) #=> "       1234.56789000"
 *
 *   # precision for `g' is number of
 *   # significant digits                          <------->
 *   sprintf("%20.8g", 1234.56789) #=> "           1234.5679"
 *
 *   #                                         <------->
 *   sprintf("%20.8g", 123456789)  #=> "       1.2345679e+08"
 *
 *   # precision for `s' is
 *   # maximum number of characters                    <------>
 *   sprintf("%20.8s", "string test") #=> "            string t"
 *
 *  Examples:
 *
 *     sprintf("%d %04x", 123, 123)               #=> "123 007b"
 *     sprintf("%08b '%4s'", 123, 123)            #=> "01111011 ' 123'"
 *     sprintf("%1$*2$s %2$d %1$s", "hello", 8)   #=> "   hello 8 hello"
 *     sprintf("%1$*2$s %2$d", "hello", -8)       #=> "hello    -8"
 *     sprintf("%+g:% g:%-g", 1.23, 1.23, 1.23)   #=> "+1.23: 1.23:1.23"
 *     sprintf("%u", -123)                        #=> "-123"
 *
 *  For more complex formatting, Ruby supports a reference by name.
 *  %<name>s style uses format style, but %{name} style doesn't.
 *
 *  Examples:
 *    sprintf("%<foo>d : %<bar>f", { :foo => 1, :bar => 2 })
 *      #=> 1 : 2.000000
 *    sprintf("%{foo}f", { :foo => 1 })
 *      # => "1f"
 */

VALUE
rb_f_sprintf(int argc, const VALUE *argv)
{
    return rb_str_format(argc - 1, argv + 1, GETNTHARG(0));
}

VALUE
rb_str_format(int argc, const VALUE *argv, VALUE fmt)
{
    enum {default_float_precision = 6};
    rb_encoding *enc;
    const char *p, *end;
    char *buf;
    long blen, bsiz;
    VALUE result;

    long scanned = 0;
    int coderange = ENC_CODERANGE_7BIT;
    int width, prec, flags = FNONE;
    int nextarg = 1;
    int posarg = 0;
    int tainted = 0;
    VALUE nextvalue;
    VALUE tmp;
    VALUE str;
    volatile VALUE hash = Qundef;

#define CHECK_FOR_WIDTH(f)				 \
    if ((f) & FWIDTH) {					 \
	rb_raise(rb_eArgError, "width given twice");	 \
    }							 \
    if ((f) & FPREC0) {					 \
	rb_raise(rb_eArgError, "width after precision"); \
    }
#define CHECK_FOR_FLAGS(f)				 \
    if ((f) & FWIDTH) {					 \
	rb_raise(rb_eArgError, "flag after width");	 \
    }							 \
    if ((f) & FPREC0) {					 \
	rb_raise(rb_eArgError, "flag after precision"); \
    }

    ++argc;
    --argv;
    if (OBJ_TAINTED(fmt)) tainted = 1;
    StringValue(fmt);
    enc = rb_enc_get(fmt);
    fmt = rb_str_new4(fmt);
    p = RSTRING_PTR(fmt);
    end = p + RSTRING_LEN(fmt);
    blen = 0;
    bsiz = 120;
    result = rb_str_buf_new(bsiz);
    rb_enc_copy(result, fmt);
    buf = RSTRING_PTR(result);
    memset(buf, 0, bsiz);
    ENC_CODERANGE_SET(result, coderange);

    for (; p < end; p++) {
	const char *t;
	int n;
	VALUE sym = Qnil;

	for (t = p; t < end && *t != '%'; t++) ;
	PUSH(p, t - p);
	if (coderange != ENC_CODERANGE_BROKEN && scanned < blen) {
	    scanned += rb_str_coderange_scan_restartable(buf+scanned, buf+blen, enc, &coderange);
	    ENC_CODERANGE_SET(result, coderange);
	}
	if (t >= end) {
	    /* end of fmt string */
	    goto sprint_exit;
	}
	p = t + 1;		/* skip `%' */

	width = prec = -1;
	nextvalue = Qundef;
      retry:
	switch (*p) {
	  default:
	    if (rb_enc_isprint(*p, enc))
		rb_raise(rb_eArgError, "malformed format string - %%%c", *p);
	    else
		rb_raise(rb_eArgError, "malformed format string");
	    break;

	  case ' ':
	    CHECK_FOR_FLAGS(flags);
	    flags |= FSPACE;
	    p++;
	    goto retry;

	  case '#':
	    CHECK_FOR_FLAGS(flags);
	    flags |= FSHARP;
	    p++;
	    goto retry;

	  case '+':
	    CHECK_FOR_FLAGS(flags);
	    flags |= FPLUS;
	    p++;
	    goto retry;

	  case '-':
	    CHECK_FOR_FLAGS(flags);
	    flags |= FMINUS;
	    p++;
	    goto retry;

	  case '0':
	    CHECK_FOR_FLAGS(flags);
	    flags |= FZERO;
	    p++;
	    goto retry;

	  case '1': case '2': case '3': case '4':
	  case '5': case '6': case '7': case '8': case '9':
	    n = 0;
	    GETNUM(n, width);
	    if (*p == '$') {
		if (nextvalue != Qundef) {
		    rb_raise(rb_eArgError, "value given twice - %d$", n);
		}
		nextvalue = GETPOSARG(n);
		p++;
		goto retry;
	    }
	    CHECK_FOR_WIDTH(flags);
	    width = n;
	    flags |= FWIDTH;
	    goto retry;

	  case '<':
	  case '{':
	    {
		const char *start = p;
		char term = (*p == '<') ? '>' : '}';
		int len;

		for (; p < end && *p != term; ) {
		    p += rb_enc_mbclen(p, end, enc);
		}
		if (p >= end) {
		    rb_raise(rb_eArgError, "malformed name - unmatched parenthesis");
		}
#if SIZEOF_INT < SIZEOF_SIZE_T
		if ((size_t)(p - start) >= INT_MAX) {
		    const int message_limit = 20;
		    len = (int)(rb_enc_right_char_head(start, start + message_limit, p, enc) - start);
		    rb_enc_raise(enc, rb_eArgError,
				 "too long name (%"PRIdSIZE" bytes) - %.*s...%c",
				 (size_t)(p - start - 2), len, start, term);
		}
#endif
		len = (int)(p - start + 1); /* including parenthesis */
		if (sym != Qnil) {
		    rb_enc_raise(enc, rb_eArgError, "named%.*s after <%"PRIsVALUE">",
				 len, start, rb_sym2str(sym));
		}
		CHECKNAMEARG(start, len, enc);
		get_hash(&hash, argc, argv);
		sym = rb_check_symbol_cstr(start + 1,
					   len - 2 /* without parenthesis */,
					   enc);
		if (!NIL_P(sym)) nextvalue = rb_hash_lookup2(hash, sym, Qundef);
		if (nextvalue == Qundef) {
		    if (NIL_P(sym)) {
			sym = rb_sym_intern(start + 1,
					    len - 2 /* without parenthesis */,
					    enc);
		    }
		    nextvalue = rb_hash_default_value(hash, sym);
		    if (NIL_P(nextvalue)) {
			rb_enc_raise(enc, rb_eKeyError, "key%.*s not found", len, start);
		    }
		}
		if (term == '}') goto format_s;
		p++;
		goto retry;
	    }

	  case '*':
	    CHECK_FOR_WIDTH(flags);
	    flags |= FWIDTH;
	    GETASTER(width);
	    if (width < 0) {
		flags |= FMINUS;
		width = -width;
	    }
	    p++;
	    goto retry;

	  case '.':
	    if (flags & FPREC0) {
		rb_raise(rb_eArgError, "precision given twice");
	    }
	    flags |= FPREC|FPREC0;

	    prec = 0;
	    p++;
	    if (*p == '*') {
		GETASTER(prec);
		if (prec < 0) {	/* ignore negative precision */
		    flags &= ~FPREC;
		}
		p++;
		goto retry;
	    }

	    GETNUM(prec, precision);
	    goto retry;

	  case '\n':
	  case '\0':
	    p--;
	  case '%':
	    if (flags != FNONE) {
		rb_raise(rb_eArgError, "invalid format character - %%");
	    }
	    PUSH("%", 1);
	    break;

	  case 'c':
	    {
		VALUE val = GETARG();
		VALUE tmp;
		unsigned int c;
		int n;

		tmp = rb_check_string_type(val);
		if (!NIL_P(tmp)) {
		    if (rb_enc_strlen(RSTRING_PTR(tmp),RSTRING_END(tmp),enc) != 1) {
			rb_raise(rb_eArgError, "%%c requires a character");
		    }
		    c = rb_enc_codepoint_len(RSTRING_PTR(tmp), RSTRING_END(tmp), &n, enc);
		    RB_GC_GUARD(tmp);
		}
		else {
		    c = NUM2INT(val);
		    n = rb_enc_codelen(c, enc);
		}
		if (n <= 0) {
		    rb_raise(rb_eArgError, "invalid character");
		}
		if (!(flags & FWIDTH)) {
		    CHECK(n);
		    rb_enc_mbcput(c, &buf[blen], enc);
		    blen += n;
		}
		else if ((flags & FMINUS)) {
		    CHECK(n);
		    rb_enc_mbcput(c, &buf[blen], enc);
		    blen += n;
		    if (width > 1) FILL(' ', width-1);
		}
		else {
		    if (width > 1) FILL(' ', width-1);
		    CHECK(n);
		    rb_enc_mbcput(c, &buf[blen], enc);
		    blen += n;
		}
	    }
	    break;

	  case 's':
	  case 'p':
	  format_s:
	    {
		VALUE arg = GETARG();
		long len, slen;

		if (*p == 'p') {
		    str = rb_inspect(arg);
		}
		else {
		    str = rb_obj_as_string(arg);
		}
		if (OBJ_TAINTED(str)) tainted = 1;
		len = RSTRING_LEN(str);
		rb_str_set_len(result, blen);
		if (coderange != ENC_CODERANGE_BROKEN && scanned < blen) {
		    int cr = coderange;
		    scanned += rb_str_coderange_scan_restartable(buf+scanned, buf+blen, enc, &cr);
		    ENC_CODERANGE_SET(result,
				      (cr == ENC_CODERANGE_UNKNOWN ?
				       ENC_CODERANGE_BROKEN : (coderange = cr)));
		}
		enc = rb_enc_check(result, str);
		if (flags&(FPREC|FWIDTH)) {
		    slen = rb_enc_strlen(RSTRING_PTR(str),RSTRING_END(str),enc);
		    if (slen < 0) {
			rb_raise(rb_eArgError, "invalid mbstring sequence");
		    }
		    if ((flags&FPREC) && (prec < slen)) {
			char *p = rb_enc_nth(RSTRING_PTR(str), RSTRING_END(str),
					     prec, enc);
			slen = prec;
			len = p - RSTRING_PTR(str);
		    }
		    /* need to adjust multi-byte string pos */
		    if ((flags&FWIDTH) && (width > slen)) {
			width -= (int)slen;
			if (!(flags&FMINUS)) {
			    CHECK(width);
			    while (width--) {
				buf[blen++] = ' ';
			    }
			}
			CHECK(len);
			memcpy(&buf[blen], RSTRING_PTR(str), len);
			RB_GC_GUARD(str);
			blen += len;
			if (flags&FMINUS) {
			    CHECK(width);
			    while (width--) {
				buf[blen++] = ' ';
			    }
			}
			rb_enc_associate(result, enc);
			break;
		    }
		}
		PUSH(RSTRING_PTR(str), len);
		RB_GC_GUARD(str);
		rb_enc_associate(result, enc);
	    }
	    break;

	  case 'd':
	  case 'i':
	  case 'o':
	  case 'x':
	  case 'X':
	  case 'b':
	  case 'B':
	  case 'u':
	    {
		volatile VALUE val = GETARG();
                int valsign;
		char nbuf[64], *s;
		const char *prefix = 0;
		int sign = 0, dots = 0;
		char sc = 0;
		long v = 0;
		int base, bignum = 0;
		int len;

		switch (*p) {
		  case 'd':
		  case 'i':
		  case 'u':
		    sign = 1; break;
		  case 'o':
		  case 'x':
		  case 'X':
		  case 'b':
		  case 'B':
		    if (flags&(FPLUS|FSPACE)) sign = 1;
		    break;
		}
		if (flags & FSHARP) {
		    switch (*p) {
		      case 'o':
			prefix = "0"; break;
		      case 'x':
			prefix = "0x"; break;
		      case 'X':
			prefix = "0X"; break;
		      case 'b':
			prefix = "0b"; break;
		      case 'B':
			prefix = "0B"; break;
		    }
		}

	      bin_retry:
		switch (TYPE(val)) {
		  case T_FLOAT:
		    if (FIXABLE(RFLOAT_VALUE(val))) {
			val = LONG2FIX((long)RFLOAT_VALUE(val));
			goto bin_retry;
		    }
		    val = rb_dbl2big(RFLOAT_VALUE(val));
		    if (FIXNUM_P(val)) goto bin_retry;
		    bignum = 1;
		    break;
		  case T_STRING:
		    val = rb_str_to_inum(val, 0, TRUE);
		    goto bin_retry;
		  case T_BIGNUM:
		    bignum = 1;
		    break;
		  case T_FIXNUM:
		    v = FIX2LONG(val);
		    break;
		  default:
		    val = rb_Integer(val);
		    goto bin_retry;
		}

		switch (*p) {
		  case 'o':
		    base = 8; break;
		  case 'x':
		  case 'X':
		    base = 16; break;
		  case 'b':
		  case 'B':
		    base = 2; break;
		  case 'u':
		  case 'd':
		  case 'i':
		  default:
		    base = 10; break;
		}

                if (base != 10) {
                    int numbits = ffs(base)-1;
                    size_t abs_nlz_bits;
                    size_t numdigits = rb_absint_numwords(val, numbits, &abs_nlz_bits);
                    long i;
                    if (INT_MAX-1 < numdigits) /* INT_MAX is used because rb_long2int is used later. */
                        rb_raise(rb_eArgError, "size too big");
                    if (sign) {
                        if (numdigits == 0)
                            numdigits = 1;
                        tmp = rb_str_new(NULL, numdigits);
                        valsign = rb_integer_pack(val, RSTRING_PTR(tmp), RSTRING_LEN(tmp),
                                1, CHAR_BIT-numbits, INTEGER_PACK_BIG_ENDIAN);
                        for (i = 0; i < RSTRING_LEN(tmp); i++)
                            RSTRING_PTR(tmp)[i] = ruby_digitmap[((unsigned char *)RSTRING_PTR(tmp))[i]];
                        s = RSTRING_PTR(tmp);
                        if (valsign < 0) {
                            sc = '-';
                            width--;
                        }
                        else if (flags & FPLUS) {
                            sc = '+';
                            width--;
                        }
                        else if (flags & FSPACE) {
                            sc = ' ';
                            width--;
                        }
                    }
                    else {
                        /* Following conditional "numdigits++" guarantees the
                         * most significant digit as
                         * - '1'(bin), '7'(oct) or 'f'(hex) for negative numbers
                         * - '0' for zero
                         * - not '0' for positive numbers.
                         *
                         * It also guarantees the most significant two
                         * digits will not be '11'(bin), '77'(oct), 'ff'(hex)
                         * or '00'.  */
                        if (numdigits == 0 ||
                                ((abs_nlz_bits != (size_t)(numbits-1) ||
                                  !rb_absint_singlebit_p(val)) &&
                                 (!bignum ? v < 0 : BIGNUM_NEGATIVE_P(val))))
                            numdigits++;
                        tmp = rb_str_new(NULL, numdigits);
                        valsign = rb_integer_pack(val, RSTRING_PTR(tmp), RSTRING_LEN(tmp),
                                1, CHAR_BIT-numbits, INTEGER_PACK_2COMP | INTEGER_PACK_BIG_ENDIAN);
                        for (i = 0; i < RSTRING_LEN(tmp); i++)
                            RSTRING_PTR(tmp)[i] = ruby_digitmap[((unsigned char *)RSTRING_PTR(tmp))[i]];
                        s = RSTRING_PTR(tmp);
                        dots = valsign < 0;
                    }
                    len = rb_long2int(RSTRING_END(tmp) - s);
                }
                else if (!bignum) {
                    valsign = 1;
                    if (v < 0) {
                        v = -v;
                        sc = '-';
                        width--;
                        valsign = -1;
                    }
                    else if (flags & FPLUS) {
                        sc = '+';
                        width--;
                    }
                    else if (flags & FSPACE) {
                        sc = ' ';
                        width--;
                    }
                    snprintf(nbuf, sizeof(nbuf), "%ld", v);
                    s = nbuf;
		    len = (int)strlen(s);
		}
		else {
                    tmp = rb_big2str(val, 10);
                    s = RSTRING_PTR(tmp);
                    valsign = 1;
                    if (s[0] == '-') {
                        s++;
                        sc = '-';
                        width--;
                        valsign = -1;
                    }
                    else if (flags & FPLUS) {
                        sc = '+';
                        width--;
                    }
                    else if (flags & FSPACE) {
                        sc = ' ';
                        width--;
                    }
		    len = rb_long2int(RSTRING_END(tmp) - s);
		}

		if (dots) {
		    prec -= 2;
		    width -= 2;
		}

		if (*p == 'X') {
		    char *pp = s;
		    int c;
		    while ((c = (int)(unsigned char)*pp) != 0) {
			*pp = rb_enc_toupper(c, enc);
			pp++;
		    }
		}
		if (prefix && !prefix[1]) { /* octal */
		    if (dots) {
			prefix = 0;
		    }
		    else if (len == 1 && *s == '0') {
			len = 0;
			if (flags & FPREC) prec--;
		    }
		    else if ((flags & FPREC) && (prec > len)) {
			prefix = 0;
		    }
		}
		else if (len == 1 && *s == '0') {
		    prefix = 0;
		}
		if (prefix) {
		    width -= (int)strlen(prefix);
		}
		if ((flags & (FZERO|FMINUS|FPREC)) == FZERO) {
		    prec = width;
		    width = 0;
		}
		else {
		    if (prec < len) {
			if (!prefix && prec == 0 && len == 1 && *s == '0') len = 0;
			prec = len;
		    }
		    width -= prec;
		}
		if (!(flags&FMINUS)) {
		    CHECK(width);
		    while (width-- > 0) {
			buf[blen++] = ' ';
		    }
		}
		if (sc) PUSH(&sc, 1);
		if (prefix) {
		    int plen = (int)strlen(prefix);
		    PUSH(prefix, plen);
		}
		CHECK(prec - len);
		if (dots) PUSH("..", 2);
		if (!sign && valsign < 0) {
		    char c = sign_bits(base, p);
		    while (len < prec--) {
			buf[blen++] = c;
		    }
		}
		else if ((flags & (FMINUS|FPREC)) != FMINUS) {
		    while (len < prec--) {
			buf[blen++] = '0';
		    }
		}
		PUSH(s, len);
		RB_GC_GUARD(tmp);
		CHECK(width);
		while (width-- > 0) {
		    buf[blen++] = ' ';
		}
	    }
	    break;

	  case 'f':
	    {
		VALUE val = GETARG(), num, den;
		int sign = (flags&FPLUS) ? 1 : 0, zero = 0;
		long len, done = 0;
		int prefix = 0;
		if (FIXNUM_P(val) || RB_TYPE_P(val, T_BIGNUM)) {
		    den = INT2FIX(1);
		    num = val;
		}
		else if (RB_TYPE_P(val, T_RATIONAL)) {
		    den = rb_rational_den(val);
		    num = rb_rational_num(val);
		}
		else {
		    nextvalue = val;
		    goto float_value;
		}
		if (!(flags&FPREC)) prec = default_float_precision;
		if (FIXNUM_P(num)) {
		    if ((SIGNED_VALUE)num < 0) {
			long n = -FIX2LONG(num);
			num = LONG2FIX(n);
			sign = -1;
		    }
		}
		else if (rb_num_negative_p(num)) {
		    sign = -1;
		    num = rb_funcallv(num, idUMinus, 0, 0);
		}
		if (den != INT2FIX(1) || prec > 1) {
		    const ID idDiv = rb_intern("div");
		    VALUE p10 = rb_int_positive_pow(10, prec);
		    VALUE den_2 = rb_funcall(den, idDiv, 1, INT2FIX(2));
		    num = rb_funcallv(num, '*', 1, &p10);
		    num = rb_funcallv(num, '+', 1, &den_2);
		    num = rb_funcallv(num, idDiv, 1, &den);
		}
		else if (prec >= 0) {
		    zero = prec;
		}
		val = rb_obj_as_string(num);
		len = RSTRING_LEN(val) + zero;
		if (prec >= len) len = prec + 1; /* integer part 0 */
		if (sign || (flags&FSPACE)) ++len;
		if (prec > 0) ++len; /* period */
		CHECK(len > width ? len : width);
		if (sign || (flags&FSPACE)) {
		    buf[blen++] = sign > 0 ? '+' : sign < 0 ? '-' : ' ';
		    prefix++;
		    done++;
		}
		len = RSTRING_LEN(val) + zero;
		t = RSTRING_PTR(val);
		if (len > prec) {
		    memcpy(&buf[blen], t, len - prec);
		    blen += len - prec;
		    done += len - prec;
		}
		else {
		    buf[blen++] = '0';
		    done++;
		}
		if (prec > 0) {
		    buf[blen++] = '.';
		    done++;
		}
		if (zero) {
		    FILL('0', zero);
		    done += zero;
		}
		else if (prec > len) {
		    FILL('0', prec - len);
		    memcpy(&buf[blen], t, len);
		    blen += len;
		    done += prec;
		}
		else if (prec > 0) {
		    memcpy(&buf[blen], t + len - prec, prec);
		    blen += prec;
		    done += prec;
		}
		if ((flags & FWIDTH) && width > done) {
		    int fill = ' ';
		    long shifting = 0;
		    if (!(flags&FMINUS)) {
			shifting = done;
			if (flags&FZERO) {
			    shifting -= prefix;
			    fill = '0';
			}
			blen -= shifting;
			memmove(&buf[blen + width - done], &buf[blen], shifting);
		    }
		    FILL(fill, width - done);
		    blen += shifting;
		}
		RB_GC_GUARD(val);
		break;
	    }
	  case 'g':
	  case 'G':
	  case 'e':
	  case 'E':
	    /* TODO: rational support */
	  case 'a':
	  case 'A':
	  float_value:
	    {
		VALUE val = GETARG();
		double fval;
		int i, need;
		char fbuf[32];

		fval = RFLOAT_VALUE(rb_Float(val));
		if (isnan(fval) || isinf(fval)) {
		    const char *expr;
		    int elen;
		    char sign = '\0';

		    if (isnan(fval)) {
			expr = "NaN";
		    }
		    else {
			expr = "Inf";
		    }
		    need = (int)strlen(expr);
		    elen = need;
		    i = 0;
		    if (!isnan(fval) && fval < 0.0)
			sign = '-';
		    else if (flags & (FPLUS|FSPACE))
			sign = (flags & FPLUS) ? '+' : ' ';
		    if (sign)
			++need;
		    if ((flags & FWIDTH) && need < width)
			need = width;

		    FILL(' ', need);
		    if (flags & FMINUS) {
			if (sign)
			    buf[blen - need--] = sign;
			memcpy(&buf[blen - need], expr, elen);
		    }
		    else {
			if (sign)
			    buf[blen - elen - 1] = sign;
			memcpy(&buf[blen - elen], expr, elen);
		    }
		    break;
		}

		fmt_setup(fbuf, sizeof(fbuf), *p, flags, width, prec);
		need = 0;
		if (*p != 'e' && *p != 'E') {
		    i = INT_MIN;
		    frexp(fval, &i);
		    if (i > 0)
			need = BIT_DIGITS(i);
		}
		need += (flags&FPREC) ? prec : default_float_precision;
		if ((flags&FWIDTH) && need < width)
		    need = width;
		need += 20;

		CHECK(need);
		snprintf(&buf[blen], need, fbuf, fval);
		blen += strlen(&buf[blen]);
	    }
	    break;
	}
	flags = FNONE;
    }

  sprint_exit:
    RB_GC_GUARD(fmt);
    /* XXX - We cannot validate the number of arguments if (digit)$ style used.
     */
    if (posarg >= 0 && nextarg < argc) {
	const char *mesg = "too many arguments for format string";
	if (RTEST(ruby_debug)) rb_raise(rb_eArgError, "%s", mesg);
	if (RTEST(ruby_verbose)) rb_warn("%s", mesg);
    }
    rb_str_resize(result, blen);

    if (tainted) OBJ_TAINT(result);
    return result;
}

static void
fmt_setup(char *buf, size_t size, int c, int flags, int width, int prec)
{
    char *end = buf + size;
    *buf++ = '%';
    if (flags & FSHARP) *buf++ = '#';
    if (flags & FPLUS)  *buf++ = '+';
    if (flags & FMINUS) *buf++ = '-';
    if (flags & FZERO)  *buf++ = '0';
    if (flags & FSPACE) *buf++ = ' ';

    if (flags & FWIDTH) {
	snprintf(buf, end - buf, "%d", width);
	buf += strlen(buf);
    }

    if (flags & FPREC) {
	snprintf(buf, end - buf, ".%d", prec);
	buf += strlen(buf);
    }

    *buf++ = c;
    *buf = '\0';
}

#undef FILE
#define FILE rb_printf_buffer
#define __sbuf rb_printf_sbuf
#define __sFILE rb_printf_sfile
#undef feof
#undef ferror
#undef clearerr
#undef fileno
#if SIZEOF_LONG < SIZEOF_VOIDP
# if  SIZEOF_LONG_LONG == SIZEOF_VOIDP
#  define _HAVE_SANE_QUAD_
#  define _HAVE_LLP64_
#  define quad_t LONG_LONG
#  define u_quad_t unsigned LONG_LONG
# endif
#elif SIZEOF_LONG != SIZEOF_LONG_LONG && SIZEOF_LONG_LONG == 8
# define _HAVE_SANE_QUAD_
# define quad_t LONG_LONG
# define u_quad_t unsigned LONG_LONG
#endif
#define FLOATING_POINT 1
#define BSD__dtoa ruby_dtoa
#define BSD__hdtoa ruby_hdtoa
#ifdef RUBY_PRI_VALUE_MARK
# define PRI_EXTRA_MARK RUBY_PRI_VALUE_MARK
#endif
#define lower_hexdigits (ruby_hexdigits+0)
#define upper_hexdigits (ruby_hexdigits+16)
#include "vsnprintf.c"

int
ruby_vsnprintf(char *str, size_t n, const char *fmt, va_list ap)
{
    int ret;
    rb_printf_buffer f;

    if ((int)n < 1)
	return (EOF);
    f._flags = __SWR | __SSTR;
    f._bf._base = f._p = (unsigned char *)str;
    f._bf._size = f._w = n - 1;
    f.vwrite = BSD__sfvwrite;
    f.vextra = 0;
    ret = (int)BSD_vfprintf(&f, fmt, ap);
    *f._p = 0;
    return ret;
}

int
ruby_snprintf(char *str, size_t n, char const *fmt, ...)
{
    int ret;
    va_list ap;

    if ((int)n < 1)
	return (EOF);

    va_start(ap, fmt);
    ret = ruby_vsnprintf(str, n, fmt, ap);
    va_end(ap);
    return ret;
}

typedef struct {
    rb_printf_buffer base;
    volatile VALUE value;
} rb_printf_buffer_extra;

static int
ruby__sfvwrite(register rb_printf_buffer *fp, register struct __suio *uio)
{
    struct __siov *iov;
    VALUE result = (VALUE)fp->_bf._base;
    char *buf = (char*)fp->_p;
    size_t len, n;
    size_t blen = buf - RSTRING_PTR(result), bsiz = fp->_w;

    if (RBASIC(result)->klass) {
	rb_raise(rb_eRuntimeError, "rb_vsprintf reentered");
    }
    if ((len = uio->uio_resid) == 0)
	return 0;
    CHECK(len);
    buf += blen;
    fp->_w = bsiz;
    for (iov = uio->uio_iov; len > 0; ++iov) {
	MEMCPY(buf, iov->iov_base, char, n = iov->iov_len);
	buf += n;
	len -= n;
    }
    fp->_p = (unsigned char *)buf;
    rb_str_set_len(result, buf - RSTRING_PTR(result));
    return 0;
}

static const char *
ruby__sfvextra(rb_printf_buffer *fp, size_t valsize, void *valp, long *sz, int sign)
{
    VALUE value, result = (VALUE)fp->_bf._base;
    rb_encoding *enc;
    char *cp;

    if (valsize != sizeof(VALUE)) return 0;
    value = *(VALUE *)valp;
    if (RBASIC(result)->klass) {
	rb_raise(rb_eRuntimeError, "rb_vsprintf reentered");
    }
    if (sign == '+') {
	if (RB_TYPE_P(value, T_CLASS)) {
# define LITERAL(str) (*sz = rb_strlen_lit(str), str)

	    if (value == rb_cNilClass) {
		return LITERAL("nil");
	    }
	    else if (value == rb_cFixnum) {
		return LITERAL("Fixnum");
	    }
	    else if (value == rb_cSymbol) {
		return LITERAL("Symbol");
	    }
	    else if (value == rb_cTrueClass) {
		return LITERAL("true");
	    }
	    else if (value == rb_cFalseClass) {
		return LITERAL("false");
	    }
# undef LITERAL
	}
	value = rb_inspect(value);
    }
    else {
	value = rb_obj_as_string(value);
	if (sign == ' ') value = QUOTE(value);
    }
    enc = rb_enc_compatible(result, value);
    if (enc) {
	rb_enc_associate(result, enc);
    }
    else {
	enc = rb_enc_get(result);
	value = rb_str_conv_enc_opts(value, rb_enc_get(value), enc,
				     ECONV_UNDEF_REPLACE|ECONV_INVALID_REPLACE,
				     Qnil);
	*(volatile VALUE *)valp = value;
    }
    StringValueCStr(value);
    RSTRING_GETMEM(value, cp, *sz);
    ((rb_printf_buffer_extra *)fp)->value = value;
    OBJ_INFECT(result, value);
    return cp;
}

VALUE
rb_enc_vsprintf(rb_encoding *enc, const char *fmt, va_list ap)
{
    rb_printf_buffer_extra buffer;
#define f buffer.base
    VALUE result;

    f._flags = __SWR | __SSTR;
    f._bf._size = 0;
    f._w = 120;
    result = rb_str_buf_new(f._w);
    if (enc) {
	if (rb_enc_mbminlen(enc) > 1) {
	    /* the implementation deeply depends on plain char */
	    rb_raise(rb_eArgError, "cannot construct wchar_t based encoding string: %s",
		     rb_enc_name(enc));
	}
	rb_enc_associate(result, enc);
    }
    f._bf._base = (unsigned char *)result;
    f._p = (unsigned char *)RSTRING_PTR(result);
    RBASIC_CLEAR_CLASS(result);
    f.vwrite = ruby__sfvwrite;
    f.vextra = ruby__sfvextra;
    buffer.value = 0;
    BSD_vfprintf(&f, fmt, ap);
    RBASIC_SET_CLASS_RAW(result, rb_cString);
    rb_str_resize(result, (char *)f._p - RSTRING_PTR(result));
#undef f

    return result;
}

VALUE
rb_enc_sprintf(rb_encoding *enc, const char *format, ...)
{
    VALUE result;
    va_list ap;

    va_start(ap, format);
    result = rb_enc_vsprintf(enc, format, ap);
    va_end(ap);

    return result;
}

VALUE
rb_vsprintf(const char *fmt, va_list ap)
{
    return rb_enc_vsprintf(NULL, fmt, ap);
}

VALUE
rb_sprintf(const char *format, ...)
{
    VALUE result;
    va_list ap;

    va_start(ap, format);
    result = rb_vsprintf(format, ap);
    va_end(ap);

    return result;
}

VALUE
rb_str_vcatf(VALUE str, const char *fmt, va_list ap)
{
    rb_printf_buffer_extra buffer;
#define f buffer.base
    VALUE klass;

    StringValue(str);
    rb_str_modify(str);
    f._flags = __SWR | __SSTR;
    f._bf._size = 0;
    f._w = rb_str_capacity(str);
    f._bf._base = (unsigned char *)str;
    f._p = (unsigned char *)RSTRING_END(str);
    klass = RBASIC(str)->klass;
    RBASIC_CLEAR_CLASS(str);
    f.vwrite = ruby__sfvwrite;
    f.vextra = ruby__sfvextra;
    buffer.value = 0;
    BSD_vfprintf(&f, fmt, ap);
    RBASIC_SET_CLASS_RAW(str, klass);
    rb_str_resize(str, (char *)f._p - RSTRING_PTR(str));
#undef f

    return str;
}

VALUE
rb_str_catf(VALUE str, const char *format, ...)
{
    va_list ap;

    va_start(ap, format);
    str = rb_str_vcatf(str, format, ap);
    va_end(ap);

    return str;
}
