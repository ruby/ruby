/**********************************************************************

  sprintf.c -

  $Author$
  $Date$
  created at: Fri Oct 15 10:39:26 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include <ctype.h>
#include <math.h>
#include "util.h"

#define BIT_DIGITS(N)   (((N)*146)/485 + 1)  /* log2(10) =~ 146/485 */

static void fmt_setup _((char*,int,int,int,int));

static char*
remove_sign_bits(str, base)
    char *str;
    int base;
{
    char *s, *t, *end;
    unsigned long len;
    
    s = t = str;
    len = strlen(str);
    end = str + len;

    if (base == 16) {
	while (t<end && *t == 'f') {
	    t++;
	}
    }
    else if (base == 8) {
	while (t<end && *t == '7') {
	    t++;
	}
    }
    else if (base == 2) {
	while (t<end && *t == '1') {
	    t++;
	}
    }
    while (*t) *s++ = *t++;
    *s = '\0';

    return str;
}

#define FNONE  0
#define FSHARP 1
#define FMINUS 2
#define FPLUS  4
#define FZERO  8
#define FSPACE 16
#define FWIDTH 32
#define FPREC  64

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
    ((nth >= argc) ? (rb_raise(rb_eArgError, "too few argument."), 0) : argv[nth])

#define GETASTER(val) do { \
    t = p++; \
    n = 0; \
    for (; p < end && ISDIGIT(*p); p++) { \
	n = 10 * n + (*p - '0'); \
    } \
    if (p >= end) { \
	rb_raise(rb_eArgError, "malformed format string - %%*[0-9]"); \
    } \
    if (*p == '$') { \
	tmp = GETPOSARG(n); \
    } \
    else { \
	tmp = GETARG(); \
	p = t; \
    } \
    val = NUM2INT(tmp); \
} while (0)

VALUE
rb_f_sprintf(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fmt;
    char *buf, *p, *end;
    int blen, bsiz;
    VALUE result;

    int width, prec, flags = FNONE;
    int nextarg = 1;
    int posarg = 0;
    int tainted = 0;
    VALUE nextvalue;
    VALUE tmp;
    VALUE str;

    fmt = GETNTHARG(0);
    if (OBJ_TAINTED(fmt)) tainted = 1;
    p = rb_str2cstr(fmt, &blen);
    end = p + blen;
    blen = 0;
    bsiz = 120;
    result = rb_str_new(0, bsiz);
    buf = RSTRING(result)->ptr;

    for (; p < end; p++) {
	char *t;
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
	    flags |= FSPACE;
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
	    n = 0;
	    for (; p < end && ISDIGIT(*p); p++) {
		n = 10 * n + (*p - '0');
	    }
	    if (p >= end) {
		rb_raise(rb_eArgError, "malformed format string - %%[0-9]");
	    }
	    if (*p == '$') {
		if (nextvalue != Qundef) {
		    rb_raise(rb_eArgError, "value given twice - %d$", n);
		}
		nextvalue = GETPOSARG(n);
		p++;
		goto retry;
	    }
	    width = n;
	    flags |= FWIDTH;
	    goto retry;

	  case '*':
	    if (flags & FWIDTH) {
		rb_raise(rb_eArgError, "width given twice");
	    }

	    flags |= FWIDTH;
	    GETASTER(width);
	    if (width < 0) {
		flags |= FMINUS;
		width = -width;
	    }
	    p++;
	    goto retry;

	  case '.':
	    if (flags & FPREC) {
		rb_raise(rb_eArgError, "precision given twice");
	    }
	    flags |= FPREC;

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

	    for (; p < end && ISDIGIT(*p); p++) {
		prec = 10 * prec + (*p - '0');
	    }
	    if (p >= end) {
		rb_raise(rb_eArgError, "malformed format string - %%.[0-9]");
	    }
	    goto retry;

	  case '\n':
	    p--;
	  case '\0':
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
	    {
		VALUE arg = GETARG();
		long len;

		str = rb_obj_as_string(arg);
		if (OBJ_TAINTED(str)) tainted = 1;
		len = RSTRING(str)->len;
		if (flags&FPREC) {
		    if (prec < len) {
			len = prec;
		    }
		}
		if (flags&FWIDTH) {
		    if (width > len) {
			CHECK(width);
			width -= len;
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
		char *prefix = 0;
		int sign = 0;
		char sc = 0;
		long v = 0;
		int base, bignum = 0;
		int len, pos;

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
		    val = rb_str2inum(val, 0);
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
			else if (!(flags&FPREC)) {
			    strcpy(s, "..");
			    s += 2;
			}
		    }
		    sprintf(fbuf, "%%l%c", *p);
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
		    val = rb_big2str(val, base);
		    s = RSTRING(val)->ptr;
		    if (s[0] == '-') {
			s++;
			sc = '-';
		    }
		    else if (flags & FPLUS) {
			sc = '+';
		    }
		    else if (flags & FSPACE) {
			sc = ' ';
		    }
		    width--;
		    goto format_integer;
		}
		if (!RBIGNUM(val)->sign) {
		    val = rb_big_clone(val);
		    rb_big_2comp(val);
		}
		val = rb_big2str(val, base);
		s = RSTRING(val)->ptr;
		if (*s == '-') {
		    if (base == 10) {
			rb_warning("negative number for %%u specifier");
			s++;
		    }
		    else {
			remove_sign_bits(++s, base);
			val = rb_str_new(0, 3+strlen(s));
			t = RSTRING(val)->ptr;
			if (!(flags&FPREC)) {
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
		}
		s  = RSTRING(val)->ptr;

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
		    while (len < prec--) {
			buf[blen++] = c;
		    }
		}
		else {
		    while (len < prec--) {
			buf[blen++] = '0';
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
#if 0
    /* XXX - We cannot validiate the number of arguments because
     *       the format string may contain `n$'-style argument selector.
     */
    if (RTEST(ruby_verbose) && nextarg < argc) {
	rb_raise(rb_eArgError, "too many argument for format string");
    }
#endif
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
