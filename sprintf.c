/************************************************

  sprintf.c -

  $Author$
  $Date$
  created at: Fri Oct 15 10:39:26 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <ctype.h>

static void fmt_setup _((char*,char,int,int,int));

static char*
remove_sign_bits(str, base)
    char *str;
    int base;
{
    char *s, *t, *end;
    
    s = t = str;
    end = str + strlen(str);

    if (base == 16) {
      x_retry:
	switch (*t) {
	  case 'c':
	    *t = '4';
	    break;
	  case 'd':
	    *t = '5';
	    break;
	  case 'e':
	    *t = '2';
	    break;
	  case 'f':
	    if (t[1] > '8') {
		t++;
		goto x_retry;
	    }
	    *t = '1';
	    break;
	  case '1':
	  case '3':
	  case '7':
	    if (t[1] > '8') {
		t++;
		goto x_retry;
	    }
	    break;
	}
	switch (*t) {
	  case '1': *t = 'f'; break;
	  case '2': *t = 'e'; break;
	  case '3': *t = 'f'; break;
	  case '4': *t = 'c'; break;
	  case '5': *t = 'd'; break;
	  case '6': *t = 'e'; break;
	  case '7': *t = 'f'; break;
	}
    }
    else if (base == 8) {
      o_retry:
	switch (*t) {
	  case '6':
	    *t = '2';
	    break;
	  case '7':
	    if (t[1] > '3') {
		t++;
		goto o_retry;
	    }
	    *t = '1';
	    break;
	  case '1':
	  case '3':
	    if (t[1] > '3') {
		t++;
		goto o_retry;
	    }
	    break;
	}
	switch (*t) {
	  case '1': *t = '7'; break;
	  case '2': *t = '6'; break;
	  case '3': *t = '7'; break;
	}
    }
    else if (base == 2) {
	while (t<end && *t == '1') t++;
	t--;
    }
    while (*t) *s++ = *t++;
    *s = '\0';

    return str;
}

double big2dbl _((VALUE));

VALUE
f_sprintf(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fmt;
    char *buf, *p, *end;
    int blen, bsiz;
    VALUE result;

#define FNONE  0
#define FSHARP 1
#define FMINUS 2
#define FPLUS  4
#define FZERO  8
#define FWIDTH 16
#define FPREC  32

    int width = 0, prec = 0, flags = FNONE;
    VALUE str;


#define CHECK(l) {\
    while (blen + (l) >= bsiz) {\
	REALLOC_N(buf, char, bsiz*2);\
	bsiz*=2;\
    }\
}

#define PUSH(s, l) { \
    CHECK(l);\
    memcpy(&buf[blen], s, l);\
    blen += (l);\
}

#define GETARG() \
    ((argc == 0)?(ArgError("too few argument."),0):(argc--,((argv++)[0])))

    fmt = GETARG();
    p = str2cstr(fmt, &blen);
    end = p + blen;
    blen = 0;
    bsiz = 120;
    buf = ALLOC_N(char, bsiz);

    for (; p < end; p++) {
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
	    if (ISPRINT(*p))
		ArgError("malformed format string - %%%c", *p);
	    else
		ArgError("malformed format string");
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
	    for (; p < end && ISDIGIT(*p); p++) {
		width = 10 * width + (*p - '0');
	    }
	    if (p >= end) {
		ArgError("malformed format string - %%[0-9]");
	    }
	    goto retry;

	  case '*':
	    if (flags & FWIDTH) {
		ArgError("width given twice");
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
		ArgError("precision given twice");
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

	    for (; p < end && ISDIGIT(*p); p++) {
		prec = 10 * prec + (*p - '0');
	    }
	    if (p >= end) {
		ArgError("malformed format string - %%.[0-9]");
	    }
	    if (prec > 0)
		flags |= FPREC;
	    goto retry;

	  case '\n':
	    p--;
	  case '\0':
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

		str = obj_as_string(arg);
		len = RSTRING(str)->len;
		if (flags&FPREC) {
		    if (prec < len) {
			CHECK(prec);
			memcpy(&buf[blen], RSTRING(str)->ptr, prec);
			blen += prec;
			break;
		    }
		}
		if (flags&FWIDTH) {
		    if (width > len) {
			width -= len;
			CHECK(width);
			if (!(flags&FMINUS)) {
			    while (width--) {
				buf[blen++] = ' ';
			    }
			}
			memcpy(&buf[blen], RSTRING(str)->ptr, len);
			blen += len;
			if (flags&FMINUS) {
			    while (width--) {
				buf[blen++] = ' ';
			    }
			}
			break;
		    }
		}
		CHECK(len);
		memcpy(&buf[blen], RSTRING(str)->ptr, len);
		blen += len;
	    }
	    break;

	  case 'b':
	  case 'B':
	  case 'o':
	  case 'x':
	  case 'u':
	    {
		volatile VALUE val = GETARG();
		char fbuf[32], nbuf[64], *s, *t;
		int v, base, bignum = 0;
		int len, slen, pos;

	      bin_retry:
		switch (TYPE(val)) {
		  case T_FIXNUM:
		    v = FIX2INT(val);
		    break;
		  case T_FLOAT:
		    val = dbl2big(RFLOAT(val)->value);
		    bignum = 1;
		    break;
		  case T_STRING:
		    val = str2inum(RSTRING(val)->ptr, 10);
		    goto bin_retry;
		  case T_BIGNUM:
		    bignum = 1;
		    break;
		  default:
		    Check_Type(val, T_FIXNUM);
		    break;
		}

		if (*p == 'x') base = 16;
		else if (*p == 'o') base = 8;
		else if (*p == 'u' || *p == 'd') base = 10;
		else if (*p == 'b' || *p == 'B') base = 2;
		if (!bignum) {
		    if (base == 2) {
			val = int2big(v);
		    }
		    else {
			s = nbuf;
			if (v < 0) {
			    strcpy(s, "..");
			    s += 2;
			    bignum = 2;
			}
			sprintf(fbuf, "%%%c", *p);
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
			goto unsigned_format;
		    }
		}
		if (*p != 'B' && !RBIGNUM(val)->sign) {
		    val = big_clone(val);
		    big_2comp(val);
		}
		val = big2str(val, base);
		s = RSTRING(val)->ptr;
		if (*s == '-' && *p != 'B') {
		    remove_sign_bits(++s, base);
		    val = str_new(0, 3+strlen(s));
		    t = RSTRING(val)->ptr;
		    strcpy(t, "..");
		    t += 2;
		    switch (base) {
		      case 16:
			if (s[0] != 'f') strcpy(t++, "f"); break;
		      case 8:
			if (s[0] != '7') strcpy(t++, "7"); break;
		    }
		    strcpy(t, s);
		    bignum = 2;
		}
		s  = RSTRING(val)->ptr;

	      unsigned_format:
		slen = len = strlen(s);
		pos = blen;
		if (flags&FWIDTH) {
		    if (width <= len) flags &= ~FWIDTH;
		    else {
			slen = width;
		    }
		}
		if (flags&FPREC) {
		    if (prec <= len) flags &= ~FPREC;
		    else {
			if (prec >= slen) {
			    flags &= ~FWIDTH;
			    slen = prec;
			}
		    }
		}
		if (slen > len) {
		    int n = slen-len;
		    char d = ' ';
		    if (flags & FZERO) d = '0';
		    if (s[0] == '.') d = '.';
		    CHECK(n);
		    while (n--) {
			buf[blen++] = d;
		    }
		}
		if ((flags&(FWIDTH|FPREC)) == (FWIDTH|FPREC)) {
		    if (prec < width) {
			pos = width - prec;
		    }
		}
		CHECK(len);
		strcpy(&buf[blen], s);
		blen += len;
		t = &buf[pos];
		if (bignum == 2) {
		    char d = '.';

		    switch (base) {
		      case 16:
			d = 'f'; break;
		      case 8:
			d = '7'; break;
		      case '2':
			d = '1'; break;
		    }

		    if ((flags & FPREC) == 0 || prec <= len-2) {
			*t++ = '.'; *t++ = '.';
		    }
		    while (*t == ' ' || *t == '.') {
			*t++ = d;
		    }
		}
		else if (flags & (FPREC|FZERO)) {
		    while (*t == ' ') {
			*t++ = '0';
		    }
		}
	    }
	    break;

	  case 'd':
	  case 'D':
	  case 'O':
	  case 'X':
	    {
		volatile VALUE val = GETARG();
		char fbuf[32], c = *p;
		int bignum = 0, base;
		int v;

		if (c == 'D') c = 'd';
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
		    val = num2fix(val);
		    goto int_retry;
		}

		if (bignum) {
		    char *s = RSTRING(val)->ptr;
		    int slen, len, pos_b, pos;

		    slen = len = strlen(s);
		    pos = pos_b = blen;
		    if (flags&FWIDTH) {
			if (width <= len) flags &= ~FWIDTH;
			else {
			    slen = width;
			}
		    }
		    if (flags&FPREC) {
			if (prec <= len) flags &= ~FPREC;
			else {
			    if (prec >= slen) {
				flags &= ~FWIDTH;
				slen = prec;
			    }
			}
		    }
		    if (slen > len) {
			int n = slen-len;
			CHECK(n);
			while (n--) {
			    buf[blen++] = ' ';
			}
		    }
		    if ((flags&(FWIDTH|FPREC)) == (FWIDTH|FPREC)) {
			if (prec < width) {
			    pos = width - prec;
			}
		    }
		    CHECK(len);
		    strcpy(&buf[blen], s);
		    blen += len;
		    if (flags & (FPREC|FZERO)) {
			char *t = &buf[pos];
			char *b = &buf[pos_b];

			if (s[0] == '-') {
			    if (slen > len && t != b ) t[-1] = '-';
			    else *t++ = '-';
			}
			while (*t == ' ' || *t == '-') {
			    *t++ = '0';
			}
		    }
		}
		else {
		    int max = 11;

		    if ((flags & FPREC) && prec > max) max = prec;
		    if ((flags & FWIDTH) && width > max) max = width;
		    CHECK(max);
		    if (v < 0 && (c == 'X' || c == 'O')) {
			v = -v;
			PUSH("-", 1);
		    }
		    fmt_setup(fbuf, c, flags, width, prec);
		    sprintf(&buf[blen], fbuf, v);
		    blen += strlen(&buf[blen]);
		}
	    }
	    break;

	  case 'f':
	  case 'g':
	  case 'e':
	    {
		VALUE val = GETARG();
		double fval;
		char fbuf[32];

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
		    Check_Type(val, T_FLOAT);
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
    if (RTEST(verbose) && argc > 1) {
	ArgError("too many argument for format string");
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
