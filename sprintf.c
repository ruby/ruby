/************************************************

  sprintf.c -

  $Author: matz $
  $Date: 1994/06/27 15:48:40 $
  created at: Fri Oct 15 10:39:26 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <ctype.h>

static void fmt_setup();

VALUE
Fsprintf(argc, argv)
    int argc;
    VALUE *argv;
{
    struct RString *fmt;
    char *buf, *p, *end;
    int i, blen, bsiz;
    VALUE result;

#define FNONE  0
#define FSHARP 1
#define FMINUS 2
#define FPLUS  4
#define FZERO  8
#define FWIDTH 16
#define FPREC  32

    int width, prec, flags = FNONE;
    VALUE str;

    GC_LINK;
    GC_PRO2(str);

#define CHECK(l) {\
    while (blen + (l) >= bsiz) {\
	REALLOC_N(buf, char, bsiz*2);\
	bsiz*=2;\
    }\
}

#define PUSH(s, l) { \
    CHECK(l);\
    memmove(&buf[blen], s, l);\
    blen += (l);\
}

#define GETARG() \
    ((argc == 1)?Fail("too few argument."):(argc--, argv++, argv[0]))

    fmt = (struct RString*)GETARG();
    Check_Type(fmt, T_STRING);

    blen = 0;
    bsiz = 120;
    buf = ALLOC_N(char, bsiz);
    end = fmt->ptr + fmt->len;

    for (p = fmt->ptr; p < end; p++) {
	char *t;

	for (t = p; t < end && *t != '%'; t++) ;
	CHECK(t - p);
	PUSH(p, t - p);
	if (t >= end) {
	    /* end of fmt string */
	    goto sprint_exit;
	}
	p = t + 1;		/* skip `%' */

      retry:
	switch (*p) {
	  default:
	    if (isprint(*p))
		Fail("malformed format string - %%%c", *p);
	    else
		Fail("malformed format string");
	    break;

	  case ' ':
	    p++;
	    goto retry;

	  case '#':
	    flags |= FSHARP;
	    p++;
	    goto retry;

	  case '+':
	    flags |= FPLUS;
	    p++;
	    goto retry;

	  case '-':
	    flags |= FMINUS;
	    p++;
	    goto retry;

	  case '0':
	    flags |= FZERO;
	    p++;
	    goto retry;

	  case '1': case '2': case '3': case '4':
	  case '5': case '6': case '7': case '8': case '9':
	    flags |= FWIDTH;
	    width = 0;
	    for (p; p < end && isdigit(*p); p++) {
		width = 10 * width + (*p - '0');
	    }
	    if (p >= end) {
		Fail("malformed format string - %%[0-9]");
	    }
	    goto retry;

	  case '*':
	    if (flags & FWIDTH) {
		Fail("width given twice");
	    }

	    flags |= FWIDTH;
	    width = GETARG();
	    width = NUM2INT(width);
	    if (width < 0) {
		flags |= FMINUS;
		width = - width;
	    }
	    p++;
	    goto retry;

	  case '.':
	    if (flags & FPREC) {
		Fail("precision given twice");
	    }

	    prec = 0;
	    p++;
	    if (*p == '0') flags |= FZERO;
	    if (*p == '*') {
		prec = GETARG();
		prec = NUM2INT(prec);
		if (prec > 0)
		    flags |= FPREC;
		p++;
		goto retry;
	    }

	    for (p; p < end && isdigit(*p); p++) {
		prec = 10 * prec + (*p - '0');
	    }
	    if (p >= end) {
		Fail("malformed format string - %%.[0-9]");
	    }
	    if (prec > 0)
		flags |= FPREC;
	    goto retry;

	  case '%':
	    PUSH("%", 1);
	    break;

	  case 'c':
	    {
		VALUE val = GETARG();
		char c;

		c = NUM2INT(val) & 0xff;
		PUSH(&c, 1);
	    }
	    break;

	  case 's':
	    {
		VALUE arg = GETARG();
		int len;
		char fbuf[32];
#define 	MIN(a,b) ((a)<(b)?(a):(b))

		str = obj_as_string(arg);
		fmt_setup(fbuf, 's', flags, width, prec);
		if (flags&FPREC) {
		    CHECK(prec);
		}
		else if ((flags&FWIDTH) && width > RSTRING(str)->len) {
		    CHECK(width);
		}
		else {
		    CHECK(RSTRING(str)->len);
		}
		sprintf(&buf[blen], fbuf, RSTRING(str)->ptr);
		blen += strlen(&buf[blen]);
	    }
	    break;

	  case 'b':
	  case 'B':
	  case 'o':
	  case 'x':
	    {
		VALUE val = GETARG();
		char fbuf[32], *s, *t, *end;
		int v, base;

		GC_LINK;
		GC_PRO(val);
	      bin_retry:
		switch (TYPE(val)) {
		  case T_FIXNUM:
		    v = FIX2INT(val);
		    val = int2big(v);
		    break;
		  case T_FLOAT:
		    v = RFLOAT(val)->value;
		    val = int2big(v);
		    break;
		  case T_STRING:
		    val = str2inum(RSTRING(val)->ptr, 0);
		    goto bin_retry;
		  case T_BIGNUM:
		    val = Fbig_clone(val);
		    break;
		  default:
		    WrongType(val, T_FIXNUM);
		    break;
		}
		if (*p == 'x') base = 16;
		else if (*p == 'o') base = 8;
		else if (*p == 'b' || *p == 'B') base = 2;
		if (*p != 'B' && !RBIGNUM(val)->sign) big_2comp(val);
		val = big2str(val, base);
		fmt_setup(fbuf, 's', flags, width, prec);

		s = t = RSTRING(val)->ptr;
		end = s + RSTRING(val)->len;
		if (*s == '-' && *p != 'B') {
		    s++; t++;
		    if (base == 16) {
			while (t<end && *t == 'f') t++;
			if (*t == 'e') {
			    *t = '2';
			}
			else if (*t == 'd') {
			    *t = '5';
			}
			else if (*t == 'c') {
			    *t = '4';
			}
			else if (*t < '8') {
			    *--t = '1';
			}
		    }
		    if (base == 8) {
			while (t<end && *t == '7') t++;
			if (*t == '6') {
			    *t = '2';
			}
			else if (*t < '4') {
			    *--t = '1';
			}
		    }
		    if (base == 2) {
			while (t<end && *t == '1') t++;
			t--;
		    }
		    while (t<end) *s++ = *t++;
		    *s = '\0';
		}
		s  = RSTRING(val)->ptr;
		if (flags&FPREC) {
		    CHECK(prec);
		}
		else if ((flags&FWIDTH) && width > end - s) {
		    CHECK(width);
		}
		else {
		    CHECK(s - end);
		}
		sprintf(&buf[blen], fbuf, s);
		blen += strlen(&buf[blen]);
		obj_free(val);
		GC_UNLINK;
	    }
	    break;
	    
	  case 'd':
	  case 'D':
	  case 'O':
	  case 'X':
	    {
		VALUE val = GETARG();
		char fbuf[32], c = *p;
		int bignum = 0, base;
		int v;

		if (c == 'D') c = 'd';
		GC_LINK;
		GC_PRO(val);
	      int_retry:
		switch (TYPE(val)) {
		  case T_FIXNUM:
		    v = FIX2INT(val);
		    break;
		  case T_FLOAT:
		    v = RFLOAT(val)->value;
		    break;
		  case T_STRING:
		    val = str2inum(RSTRING(val)->ptr, 0);
		    goto int_retry;
		  case T_BIGNUM:
		    if (c == 'd') base = 10;
		    else if (c == 'X') base = 16;
		    else if (c == 'O') base = 8;
		    val = big2str(val, base);
		    bignum = 1;
		    break;
		  default:
		    WrongType(val, T_FIXNUM);
		    break;
		}

		if (bignum) {
		    fmt_setup(fbuf, 's', flags, width, prec);

		    if (flags&FPREC) {
			CHECK(prec);
		    }
		    else if ((flags&FWIDTH) && width > RSTRING(val)->len) {
			CHECK(width);
		    }
		    else {
			CHECK(RSTRING(val)->len);
		    }
		    sprintf(&buf[blen], fbuf, RSTRING(val)->ptr);
		    blen += strlen(&buf[blen]);
		}
		else {
		    fmt_setup(fbuf, c, flags, width, prec);

		    CHECK(11);
		    if (v < 0 && (c == 'X' || c == 'O')) {
			v = -v;
			PUSH("-", 1);
		    }
		    sprintf(&buf[blen], fbuf, v);
		    blen += strlen(&buf[blen]);
		}
		GC_UNLINK;
	    }
	    break;

	  case 'f':
	  case 'g':
	  case 'e':
	    {
		VALUE val = GETARG();
		double fval;
		char fbuf[32];
		double big2dbl();
		double atof();

		switch (TYPE(val)) {
		  case T_FIXNUM:
		    fval = FIX2INT(val);
		    break;
		  case T_FLOAT:
		    fval = RFLOAT(val)->value;
		    break;
		  case T_BIGNUM:
		    fval = big2dbl(val);
		    break;
		  case T_STRING:
		    fval = atof(RSTRING(val)->ptr);
		    break;
		  default:
		    WrongType(val, T_FLOAT);
		    break;
		}

		fmt_setup(fbuf, *p, flags, width, prec);

		CHECK(22);
		sprintf(&buf[blen], fbuf, fval);
		blen += strlen(&buf[blen]);
	    }
	    break;
	}
	flags = FNONE;
    }

  sprint_exit:
    GC_UNLINK;
    if (verbose && argc > 1) {
	Fail("too many argument for format string");
    }
    result = str_new(buf, blen);
    free(buf);

    return result;
}

static void
fmt_setup(buf, c, flags, width, prec)
    char *buf, c;
    int flags, width, prec;
{
    *buf++ = '%';
    if (flags & FSHARP) *buf++ = '#';
    if (flags & FPLUS)  *buf++ = '+';
    if (flags & FMINUS) *buf++ = '-';
    if (flags & FZERO)  *buf++ = '0';

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
