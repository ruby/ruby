/**********************************************************************

  sprintf.c -

  $Author$
  created at: Fri Oct 15 10:39:26 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#include <math.h>
#include <stdarg.h>

#ifdef HAVE_IEEEFP_H
# include <ieeefp.h>
#endif

#include "id.h"
#include "internal.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/sanitizers.h"
#include "internal/symbol.h"
#include "internal/util.h"
#include "ruby/encoding.h"
#include "ruby/re.h"

#define BIT_DIGITS(N)   (((N)*146)/485 + 1)  /* log2(10) =~ 146/485 */

static char *fmt_setup(char*,size_t,int,int,int,int);
static char *ruby_ultoa(unsigned long val, char *endp, int base, int octzero);

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
    while ((l) >= bsiz - blen) {\
	bsiz*=2;\
	if (bsiz<0) rb_raise(rb_eArgError, "too big specifier");\
    }\
    rb_str_resize(result, bsiz);\
    ENC_CODERANGE_SET(result, cr);\
    buf = RSTRING_PTR(result);\
} while (0)

#define PUSH(s, l) do { \
    CHECK(l);\
    PUSH_(s, l);\
} while (0)

#define PUSH_(s, l) do { \
    memcpy(&buf[blen], (s), (l));\
    blen += (l);\
} while (0)

#define FILL(c, l) do { \
    if ((l) <= 0) break;\
    CHECK(l);\
    FILL_(c, l);\
} while (0)

#define FILL_(c, l) do { \
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
    VALUE nextvalue;
    VALUE tmp;
    VALUE orig;
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
    StringValue(fmt);
    enc = rb_enc_get(fmt);
    orig = fmt;
    fmt = rb_str_tmp_frozen_acquire(fmt);
    p = RSTRING_PTR(fmt);
    end = p + RSTRING_LEN(fmt);
    blen = 0;
    bsiz = 120;
    result = rb_str_buf_new(bsiz);
    rb_enc_associate(result, enc);
    buf = RSTRING_PTR(result);
    memset(buf, 0, bsiz);
    ENC_CODERANGE_SET(result, coderange);

    for (; p < end; p++) {
	const char *t;
	int n;
	VALUE sym = Qnil;

	for (t = p; t < end && *t != '%'; t++) ;
	if (t + 1 == end) {
	    rb_raise(rb_eArgError, "incomplete format specifier; use %%%% (double %%) instead");
	}
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
				 "too long name (%"PRIuSIZE" bytes) - %.*s...%c",
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
			rb_key_err_raise(rb_enc_sprintf(enc, "key%.*s not found", len, start), hash, sym);
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
		if (width < 0) rb_raise(rb_eArgError, "width too big");
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
            /* fall through */
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
			    FILL(' ', width);
			    width = 0;
			}
			CHECK(len);
			memcpy(&buf[blen], RSTRING_PTR(str), len);
			RB_GC_GUARD(str);
			blen += len;
			if (flags&FMINUS) {
			    FILL(' ', width);
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
		char nbuf[BIT_DIGITS(SIZEOF_LONG*CHAR_BIT)+2], *s;
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
		    s = ruby_ultoa((unsigned long)v, nbuf + sizeof(nbuf), 10, 0);
		    len = (int)(nbuf + sizeof(nbuf) - s);
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
		    FILL(' ', width);
		    width = 0;
		}
		if (sc) PUSH(&sc, 1);
		if (prefix) {
		    int plen = (int)strlen(prefix);
		    PUSH(prefix, plen);
		}
		if (dots) PUSH("..", 2);
		if (prec > len) {
		    CHECK(prec - len);
		    if (!sign && valsign < 0) {
			char c = sign_bits(base, p);
			FILL_(c, prec - len);
		    }
		    else if ((flags & (FMINUS|FPREC)) != FMINUS) {
			FILL_('0', prec - len);
		    }
		}
		PUSH(s, len);
		RB_GC_GUARD(tmp);
		FILL(' ', width);
	    }
	    break;

	  case 'f':
	    {
		VALUE val = GETARG(), num, den;
		int sign = (flags&FPLUS) ? 1 : 0, zero = 0;
		long len, fill;
		if (RB_INTEGER_TYPE_P(val)) {
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
		else if (BIGNUM_NEGATIVE_P(num)) {
		    sign = -1;
		    num = rb_big_uminus(num);
		}
		if (den != INT2FIX(1)) {
		    num = rb_int_mul(num, rb_int_positive_pow(10, prec));
		    num = rb_int_plus(num, rb_int_idiv(den, INT2FIX(2)));
		    num = rb_int_idiv(num, den);
		}
		else if (prec >= 0) {
		    zero = prec;
		}
		val = rb_int2str(num, 10);
		len = RSTRING_LEN(val) + zero;
		if (prec >= len) len = prec + 1; /* integer part 0 */
		if (sign || (flags&FSPACE)) ++len;
		if (prec > 0) ++len; /* period */
		fill = width > len ? width - len : 0;
		CHECK(fill + len);
		if (fill && !(flags&(FMINUS|FZERO))) {
		    FILL_(' ', fill);
		}
		if (sign || (flags&FSPACE)) {
		    buf[blen++] = sign > 0 ? '+' : sign < 0 ? '-' : ' ';
		}
		if (fill && (flags&(FMINUS|FZERO)) == FZERO) {
		    FILL_('0', fill);
		}
		len = RSTRING_LEN(val) + zero;
		t = RSTRING_PTR(val);
		if (len > prec) {
		    PUSH_(t, len - prec);
		}
		else {
		    buf[blen++] = '0';
		}
		if (prec > 0) {
		    buf[blen++] = '.';
		}
		if (zero) {
		    FILL_('0', zero);
		}
		else if (prec > len) {
		    FILL_('0', prec - len);
		    PUSH_(t, len);
		}
		else if (prec > 0) {
		    PUSH_(t + len - prec, prec);
		}
		if (fill && (flags&FMINUS)) {
		    FILL_(' ', fill);
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

		fval = RFLOAT_VALUE(rb_Float(val));
		if (isnan(fval) || isinf(fval)) {
		    const char *expr;
		    int need;
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
		else {
		    int cr = ENC_CODERANGE(result);
		    char fbuf[2*BIT_DIGITS(SIZEOF_INT*CHAR_BIT)+10];
		    char *fmt = fmt_setup(fbuf, sizeof(fbuf), *p, flags, width, prec);
		    rb_str_set_len(result, blen);
		    rb_str_catf(result, fmt, fval);
		    ENC_CODERANGE_SET(result, cr);
		    bsiz = rb_str_capacity(result);
		    RSTRING_GETMEM(result, buf, blen);
		}
	    }
	    break;
	}
	flags = FNONE;
    }

  sprint_exit:
    rb_str_tmp_frozen_release(orig, fmt);
    /* XXX - We cannot validate the number of arguments if (digit)$ style used.
     */
    if (posarg >= 0 && nextarg < argc) {
	const char *mesg = "too many arguments for format string";
	if (RTEST(ruby_debug)) rb_raise(rb_eArgError, "%s", mesg);
	if (RTEST(ruby_verbose)) rb_warn("%s", mesg);
    }
    rb_str_resize(result, blen);

    return result;
}

static char *
fmt_setup(char *buf, size_t size, int c, int flags, int width, int prec)
{
    buf += size;
    *--buf = '\0';
    *--buf = c;

    if (flags & FPREC) {
	buf = ruby_ultoa(prec, buf, 10, 0);
	*--buf = '.';
    }

    if (flags & FWIDTH) {
	buf = ruby_ultoa(width, buf, 10, 0);
    }

    if (flags & FSPACE) *--buf = ' ';
    if (flags & FZERO)  *--buf = '0';
    if (flags & FMINUS) *--buf = '-';
    if (flags & FPLUS)  *--buf = '+';
    if (flags & FSHARP) *--buf = '#';
    *--buf = '%';
    return buf;
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
#if defined RUBY_USE_SETJMPEX && RUBY_USE_SETJMPEX
# undef MAYBE_UNUSED
# define MAYBE_UNUSED(x) x = 0
#endif
#include "vsnprintf.c"

static char *
ruby_ultoa(unsigned long val, char *endp, int base, int flags)
{
    const char *xdigs = lower_hexdigits;
    int octzero = flags & FSHARP;
    return BSD__ultoa(val, endp, base, octzero, xdigs);
}

static int ruby_do_vsnprintf(char *str, size_t n, const char *fmt, va_list ap);

int
ruby_vsnprintf(char *str, size_t n, const char *fmt, va_list ap)
{
    if (str && (ssize_t)n < 1)
	return (EOF);
    return ruby_do_vsnprintf(str, n, fmt, ap);
}

static int
ruby_do_vsnprintf(char *str, size_t n, const char *fmt, va_list ap)
{
    ssize_t ret;
    rb_printf_buffer f;

    f._flags = __SWR | __SSTR;
    f._bf._base = f._p = (unsigned char *)str;
    f._bf._size = f._w = str ? (n - 1) : 0;
    f.vwrite = BSD__sfvwrite;
    f.vextra = 0;
    ret = BSD_vfprintf(&f, fmt, ap);
    if (str) *f._p = 0;
#if SIZEOF_SIZE_T > SIZEOF_INT
    if (n > INT_MAX) return INT_MAX;
#endif
    return (int)ret;
}

int
ruby_snprintf(char *str, size_t n, char const *fmt, ...)
{
    int ret;
    va_list ap;

    if (str && (ssize_t)n < 1)
	return (EOF);

    va_start(ap, fmt);
    ret = ruby_do_vsnprintf(str, n, fmt, ap);
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
    long len, n;
    long blen = buf - RSTRING_PTR(result), bsiz = fp->_w;

    if (RBASIC(result)->klass) {
	rb_raise(rb_eRuntimeError, "rb_vsprintf reentered");
    }
    if (uio->uio_resid == 0)
	return 0;
#if SIZE_MAX > LONG_MAX
    if (uio->uio_resid >= LONG_MAX)
	rb_raise(rb_eRuntimeError, "too big string");
#endif
    len = (long)uio->uio_resid;
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
	    else if (value == rb_cInteger) {
		return LITERAL("Integer");
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
    else if (SYMBOL_P(value)) {
	value = rb_sym2str(value);
	if (sign == ' ' && !rb_str_symname_p(value)) {
	    value = rb_str_inspect(value);
	}
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
