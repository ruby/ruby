/**********************************************************************

  sprintf.c -

  $Author$
  $Date$
  created at: Fri Oct 15 10:39:26 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "re.h"
#include <ctype.h>
#include <math.h>

#define BIT_DIGITS(N)   (((N)*146)/485 + 1)  /* log2(10) =~ 146/485 */
#define BITSPERDIG (SIZEOF_BDIGITS*CHAR_BIT)
#define EXTENDSIGN(n, l) (((~0 << (n)) >> (((n)*(l)) % BITSPERDIG)) & ~(~0 << (n)))

static void fmt_setup _((char*,int,int,int,int));

static char*
remove_sign_bits(str, base)
    char *str;
    int base;
{
    char *s, *t;
    
    s = t = str;

    if (base == 16) {
	while (*t == 'f') {
	    t++;
	}
    }
    else if (base == 8) {
	*t |= EXTENDSIGN(3, strlen(t));
	while (*t == '7') {
	    t++;
	}
    }
    else if (base == 2) {
	while (*t == '1') {
	    t++;
	}
    }
    if (t > s) {
	while (*t) *s++ = *t++;
	*s = '\0';
    }

    return str;
}

static char
sign_bits(base, p)
    int base;
    const char *p;
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
    while (blen + (l) >= bsiz) {\
	bsiz*=2;\
    }\
    rb_str_resize(result, bsiz);\
    buf = RSTRING(result)->ptr;\
} while (0)

#define PUSH(s, l) do { \
    CHECK(l);\
    memcpy(&buf[blen], s, l);\
    blen += (l);\
} while (0)

#define GETARG() (nextvalue != Qundef ? nextvalue : \
    posarg < 0 ? \
    (rb_raise(rb_eArgError, "unnumbered(%d) mixed with numbered", nextarg), 0) : \
    (posarg = nextarg++, GETNTHARG(posarg)))

#define GETPOSARG(n) (posarg > 0 ? \
    (rb_raise(rb_eArgError, "numbered(%d) after unnumbered(%d)", n, posarg), 0) : \
    ((n < 1) ? (rb_raise(rb_eArgError, "invalid index - %d$", n), 0) : \
	       (posarg = -1, GETNTHARG(n))))

#define GETNTHARG(nth) \
    ((nth >= argc) ? (rb_raise(rb_eArgError, "too few arguments"), 0) : argv[nth])

#define GETNUM(n, val) \
    for (; p < end && ISDIGIT(*p); p++) { \
	int next_n = 10 * n + (*p - '0'); \
        if (next_n / 10 != n) {\
	    rb_raise(rb_eArgError, #val " too big"); \
	} \
	n = next_n; \
    } \
    if (p >= end) { \
	rb_raise(rb_eArgError, "malformed format string - %%*[0-9]"); \
    }

#define GETASTER(val) do { \
    t = p++; \
    n = 0; \
    GETNUM(n, val); \
    if (*p == '$') { \
	tmp = GETPOSARG(n); \
    } \
    else { \
	tmp = GETARG(); \
	p = t; \
    } \
    val = NUM2INT(tmp); \
} while (0)


/*
 *  call-seq:
 *     format(format_string [, arguments...] )   => string
 *     sprintf(format_string [, arguments...] )  => string
 *  
 *  Returns the string resulting from applying <i>format_string</i> to
 *  any additional arguments. Within the format string, any characters
 *  other than format sequences are copied to the result. A format
 *  sequence consists of a percent sign, followed by optional flags,
 *  width, and precision indicators, then terminated with a field type
 *  character. The field type controls how the corresponding
 *  <code>sprintf</code> argument is to be interpreted, while the flags
 *  modify that interpretation. The field type characters are listed
 *  in the table at the end of this section. The flag characters are:
 *
 *    Flag     | Applies to   | Meaning
 *    ---------+--------------+-----------------------------------------
 *    space    | bdeEfgGiouxX | Leave a space at the start of 
 *             |              | positive numbers.
 *    ---------+--------------+-----------------------------------------
 *    (digit)$ | all          | Specifies the absolute argument number
 *             |              | for this field. Absolute and relative
 *             |              | argument numbers cannot be mixed in a
 *             |              | sprintf string.
 *    ---------+--------------+-----------------------------------------
 *     #       | beEfgGoxX    | Use an alternative format. For the
 *             |              | conversions `o', `x', `X', and `b', 
 *             |              | prefix the result with ``0'', ``0x'', ``0X'',
 *             |              |  and ``0b'', respectively. For `e',
 *             |              | `E', `f', `g', and 'G', force a decimal
 *             |              | point to be added, even if no digits follow.
 *             |              | For `g' and 'G', do not remove trailing zeros.
 *    ---------+--------------+-----------------------------------------
 *    +        | bdeEfgGiouxX | Add a leading plus sign to positive numbers.
 *    ---------+--------------+-----------------------------------------
 *    -        | all          | Left-justify the result of this conversion.
 *    ---------+--------------+-----------------------------------------
 *    0 (zero) | bdeEfgGiouxX | Pad with zeros, not spaces.
 *    ---------+--------------+-----------------------------------------
 *    *        | all          | Use the next argument as the field width. 
 *             |              | If negative, left-justify the result. If the
 *             |              | asterisk is followed by a number and a dollar 
 *             |              | sign, use the indicated argument as the width.
 *
 *     
 *  The field width is an optional integer, followed optionally by a
 *  period and a precision. The width specifies the minimum number of
 *  characters that will be written to the result for this field. For
 *  numeric fields, the precision controls the number of decimal places
 *  displayed. For string fields, the precision determines the maximum
 *  number of characters to be copied from the string. (Thus, the format
 *  sequence <code>%10.10s</code> will always contribute exactly ten
 *  characters to the result.)
 *
 *  The field types are:
 *
 *      Field |  Conversion
 *      ------+--------------------------------------------------------------
 *        b   | Convert argument as a binary number.
 *        c   | Argument is the numeric code for a single character.
 *        d   | Convert argument as a decimal number.
 *        E   | Equivalent to `e', but uses an uppercase E to indicate
 *            | the exponent.
 *        e   | Convert floating point argument into exponential notation 
 *            | with one digit before the decimal point. The precision
 *            | determines the number of fractional digits (defaulting to six).
 *        f   | Convert floating point argument as [-]ddd.ddd, 
 *            |  where the precision determines the number of digits after
 *            | the decimal point.
 *        G   | Equivalent to `g', but use an uppercase `E' in exponent form.
 *        g   | Convert a floating point number using exponential form
 *            | if the exponent is less than -4 or greater than or
 *            | equal to the precision, or in d.dddd form otherwise.
 *        i   | Identical to `d'.
 *        o   | Convert argument as an octal number.
 *        p   | The valuing of argument.inspect.
 *        s   | Argument is a string to be substituted. If the format
 *            | sequence contains a precision, at most that many characters
 *            | will be copied.
 *        u   | Treat argument as an unsigned decimal number. Negative integers
 *            | are displayed as a 32 bit two's complement plus one for the
 *            | underlying architecture; that is, 2 ** 32 + n.  However, since
 *            | Ruby has no inherent limit on bits used to represent the
 *            | integer, this value is preceded by two dots (..) in order to
 *            | indicate a infinite number of leading sign bits.
 *        X   | Convert argument as a hexadecimal number using uppercase
 *            | letters. Negative numbers will be displayed with two
 *            | leading periods (representing an infinite string of
 *            | leading 'FF's.
 *        x   | Convert argument as a hexadecimal number.
 *            | Negative numbers will be displayed with two
 *            | leading periods (representing an infinite string of
 *            | leading 'ff's.
 *     
 *  Examples:
 *
 *     sprintf("%d %04x", 123, 123)               #=> "123 007b"
 *     sprintf("%08b '%4s'", 123, 123)            #=> "01111011 ' 123'"
 *     sprintf("%1$*2$s %2$d %1$s", "hello", 8)   #=> "   hello 8 hello"
 *     sprintf("%1$*2$s %2$d", "hello", -8)       #=> "hello    -8"
 *     sprintf("%+g:% g:%-g", 1.23, 1.23, 1.23)   #=> "+1.23: 1.23:1.23"
 *     sprintf("%u", -123)                        #=> "..4294967173"
 */

VALUE
rb_f_sprintf(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_str_format(argc - 1, argv + 1, GETNTHARG(0));
}

VALUE
rb_str_format(argc, argv, fmt)
    int argc;
    VALUE *argv;
    VALUE fmt;
{
    const char *p, *end;
    char *buf;
    int blen, bsiz;
    VALUE result;

    int width, prec, flags = FNONE;
    int nextarg = 1;
    int posarg = 0;
    int tainted = 0;
    VALUE nextvalue;
    VALUE tmp;
    VALUE str;

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
    fmt = rb_str_new4(fmt);
    p = RSTRING(fmt)->ptr;
    end = p + RSTRING(fmt)->len;
    blen = 0;
    bsiz = 120;
    result = rb_str_buf_new(bsiz);
    buf = RSTRING(result)->ptr;

    for (; p < end; p++) {
	const char *t;
	int n;

	for (t = p; t < end && *t != '%'; t++) ;
	PUSH(p, t - p);
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
	    if (ISPRINT(*p))
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
		rb_raise(rb_eArgError, "illegal format character - %%");
	    }
	    PUSH("%", 1);
	    break;

	  case 'c':
	    {
		VALUE val = GETARG();
		char c;

		if (!(flags & FMINUS))
		    while (--width > 0)
			PUSH(" ", 1);
		c = NUM2INT(val) & 0xff;
		PUSH(&c, 1);
		while (--width > 0)
		    PUSH(" ", 1);
	    }
	    break;

	  case 's':
	  case 'p':
	    {
		VALUE arg = GETARG();
		long len;

		if (*p == 'p') arg = rb_inspect(arg);
		str = rb_obj_as_string(arg);
		if (OBJ_TAINTED(str)) tainted = 1;
		len = RSTRING(str)->len;
		if (flags&FPREC) {
		    if (prec < len) {
			len = prec;
		    }
		}
		/* need to adjust multi-byte string pos */
		if (flags&FWIDTH) {
		    if (width > len) {
			CHECK(width);
			width -= len;
			if (!(flags&FMINUS)) {
			    while (width--) {
				buf[blen++] = ' ';
			    }
			}
			memcpy(&buf[blen], RSTRING_PTR(str), len);
			blen += len;
			if (flags&FMINUS) {
			    while (width--) {
				buf[blen++] = ' ';
			    }
			}
			break;
		    }
		}
		PUSH(RSTRING(str)->ptr, len);
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
		char fbuf[32], nbuf[64], *s, *t;
		const char *prefix = 0;
		int sign = 0;
		char sc = 0;
		long v = 0;
		int base, bignum = 0;
		int len, pos;
		volatile VALUE tmp;
                volatile VALUE tmp1;

		switch (*p) {
		  case 'd':
		  case 'i':
		    sign = 1; break;
		  case 'o':
		  case 'x':
		  case 'X':
		  case 'b':
		  case 'B':
		  case 'u':
		  default:
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
		    if (prefix) {
			width -= strlen(prefix);
		    }
		}

	      bin_retry:
		switch (TYPE(val)) {
		  case T_FLOAT:
		    val = rb_dbl2big(RFLOAT(val)->value);
		    if (FIXNUM_P(val)) goto bin_retry;
		    bignum = 1;
		    break;
		  case T_STRING:
		    val = rb_str_to_inum(val, 0, Qtrue);
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

		if (!bignum) {
		    if (base == 2) {
			val = rb_int2big(v);
			goto bin_retry;
		    }
		    if (sign) {
			char c = *p;
			if (c == 'i') c = 'd'; /* %d and %i are identical */
			if (v < 0) {
			    v = -v;
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
			sprintf(fbuf, "%%l%c", c);
			sprintf(nbuf, fbuf, v);
			s = nbuf;
			goto format_integer;
		    }
		    s = nbuf;
		    if (v < 0) {
			if (base == 10) {
			    rb_warning("negative number for %%u specifier");
			}
			if (!(flags&(FPREC|FZERO))) {
			    strcpy(s, "..");
			    s += 2;
			}
		    }
		    sprintf(fbuf, "%%l%c", *p == 'X' ? 'x' : *p);
		    sprintf(s, fbuf, v);
		    if (v < 0) {
			char d = 0;

			remove_sign_bits(s, base);
			switch (base) {
			  case 16:
			    d = 'f'; break;
			  case 8:
			    d = '7'; break;
			}
			if (d && *s != d) {
			    memmove(s+1, s, strlen(s)+1);
			    *s = d;
			}
		    }
		    s = nbuf;
		    goto format_integer;
		}

		if (sign) {
		    tmp = rb_big2str(val, base);
		    s = RSTRING(tmp)->ptr;
		    if (s[0] == '-') {
			s++;
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
		    goto format_integer;
		}
		if (!RBIGNUM(val)->sign) {
		    val = rb_big_clone(val);
		    rb_big_2comp(val);
		}
		tmp1 = tmp = rb_big2str0(val, base, RBIGNUM(val)->sign);
		s = RSTRING(tmp)->ptr;
		if (*s == '-') {
		    if (base == 10) {
			rb_warning("negative number for %%u specifier");
		    }
		    remove_sign_bits(++s, base);
		    tmp = rb_str_new(0, 3+strlen(s));
		    t = RSTRING(tmp)->ptr;
		    if (!(flags&(FPREC|FZERO))) {
			strcpy(t, "..");
			t += 2;
		    }
		    switch (base) {
		      case 16:
			if (s[0] != 'f') strcpy(t++, "f"); break;
		      case 8:
			if (s[0] != '7') strcpy(t++, "7"); break;
		      case 2:
			if (s[0] != '1') strcpy(t++, "1"); break;
		    }
		    strcpy(t, s);
		    bignum = 2;
		}
		s = RSTRING(tmp)->ptr;

	      format_integer:
		pos = -1;
		len = strlen(s);

		if (*p == 'X') {
		    char *pp = s;
		    while (*pp) {
			*pp = toupper(*pp);
			pp++;
		    }
		}
		if ((flags&(FZERO|FPREC)) == FZERO) {
		    prec = width;
		    width = 0;
		}
		else {
		    if (prec < len) prec = len;
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
		    int plen = strlen(prefix);
		    PUSH(prefix, plen);
		}
		CHECK(prec - len);
		if (!bignum && v < 0) {
		    char c = sign_bits(base, p);
		    while (len < prec--) {
			buf[blen++] = c;
		    }
		}
		else {
		    char c;

		    if (!sign && bignum && !RBIGNUM(val)->sign)
			c = sign_bits(base, p);
		    else
			c = '0';
		    while (len < prec--) {
			buf[blen++] = c;
		    }
		}
		PUSH(s, len);
		CHECK(width);
		while (width-- > 0) {
		    buf[blen++] = ' ';
		}
	    }
	    break;

	  case 'f':
	  case 'g':
	  case 'G':
	  case 'e':
	  case 'E':
	    {
		VALUE val = GETARG();
		double fval;
		int i, need = 6;
		char fbuf[32];

		fval = RFLOAT(rb_Float(val))->value;
#if defined(_WIN32) && !defined(__BORLANDC__)
		if (isnan(fval) || isinf(fval)) {
		    const char *expr;

		    if  (isnan(fval)) {
			expr = "NaN";
		    }
		    else {
			expr = "Inf";
		    }
		    need = strlen(expr);
		    if ((!isnan(fval) && fval < 0.0) || (flags & FPLUS))
			need++;
		    else if (flags & FSPACE)
			need++;
		    if ((flags & FWIDTH) && need < width)
			need = width;

		    CHECK(need);
		    sprintf(&buf[blen], "%*s", need, "");
		    if (flags & FMINUS) {
			if (!isnan(fval) && fval < 0.0)
			    buf[blen++] = '-';
			else if (flags & FPLUS)
			    buf[blen++] = '+';
			else if (flags & FSPACE)
			    blen++;
			strncpy(&buf[blen], expr, strlen(expr));
		    }
		    else if (flags & FZERO) {
			if (!isnan(fval) && fval < 0.0) {
			    buf[blen++] = '-';
			    need--;
			}
			else if (flags & FPLUS) {
			    buf[blen++] = '+';
			    need--;
			}
			else if (flags & FSPACE) {
			    blen++;
			    need--;
			}
			while (need-- - strlen(expr) > 0) {
			    buf[blen++] = '0';
			}
			strncpy(&buf[blen], expr, strlen(expr));
		    }
		    else {
			if (!isnan(fval) && fval < 0.0)
			    buf[blen + need - strlen(expr) - 1] = '-';
			else if (flags & FPLUS)
			    buf[blen + need - strlen(expr) - 1] = '+';
			strncpy(&buf[blen + need - strlen(expr)], expr,
				strlen(expr));
		    }
		    blen += strlen(&buf[blen]);
		    break;
		}
#endif	/* defined(_WIN32) && !defined(__BORLANDC__) */
		fmt_setup(fbuf, *p, flags, width, prec);
		need = 0;
		if (*p != 'e' && *p != 'E') {
		    i = INT_MIN;
		    frexp(fval, &i);
		    if (i > 0)
			need = BIT_DIGITS(i);
		}
		need += (flags&FPREC) ? prec : 6;
		if ((flags&FWIDTH) && need < width)
		    need = width;
		need += 20;

		CHECK(need);
		sprintf(&buf[blen], fbuf, fval);
		blen += strlen(&buf[blen]);
	    }
	    break;
	}
	flags = FNONE;
    }

  sprint_exit:
    /* XXX - We cannot validiate the number of arguments if (digit)$ style used.
     */
    if (posarg >= 0 && nextarg < argc) {
	const char *mesg = "too many arguments for format string";
	if (RTEST(ruby_debug)) rb_raise(rb_eArgError, mesg);
	if (RTEST(ruby_verbose)) rb_warn(mesg);
    }
    rb_str_resize(result, blen);

    if (tainted) OBJ_TAINT(result);
    return result;
}

static void
fmt_setup(buf, c, flags, width, prec)
    char *buf;
    int c;
    int flags, width, prec;
{
    *buf++ = '%';
    if (flags & FSHARP) *buf++ = '#';
    if (flags & FPLUS)  *buf++ = '+';
    if (flags & FMINUS) *buf++ = '-';
    if (flags & FZERO)  *buf++ = '0';
    if (flags & FSPACE) *buf++ = ' ';

    if (flags & FWIDTH) {
	sprintf(buf, "%d", width);
	buf += strlen(buf);
    }

    if (flags & FPREC) {
	sprintf(buf, ".%d", prec);
	buf += strlen(buf);
    }

    *buf++ = c;
    *buf = '\0';
}
