/************************************************

  pack.c -

  $Author$
  $Date$
  created at: Thu Feb 10 15:17:05 JST 1994

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <ctype.h>
#include <sys/types.h>

#define swaps(x)	((((x)&0xFF)<<8) + (((x)>>8)&0xFF))
#define swapl(x)	((((x)&0xFF)<<24)	\
			+(((x)>>24)&0xFF)	\
			+(((x)&0x0000FF00)<<8)	\
			+(((x)&0x00FF0000)>>8)	)

#ifdef DYNAMIC_ENDIAN
#ifdef ntohs
#undef ntohs
#undef ntohl
#undef htons
#undef htonl
#endif
static int
endian()
{
    static int init = 0;
    static int endian_value;
    char *p;

    if (init) return endian_value;
    init = 1;
    p = (char*)&init;
    return endian_value = p[0]?0:1;
}

#define ntohs(x) (endian()?(x):swaps(x))
#define ntohl(x) (endian()?(x):swapl(x))
#define htons(x) (endian()?(x):swaps(x))
#define htonl(x) (endian()?(x):swapl(x))
#define htovs(x) (endian()?swaps(x):(x))
#define htovl(x) (endian()?swapl(x):(x))
#define vtohs(x) (endian()?swaps(x):(x))
#define vtohl(x) (endian()?swapl(x):(x))
#else
#ifdef WORDS_BIGENDIAN
#ifndef ntohs
#define ntohs(x) (x)
#define ntohl(x) (x)
#define htons(x) (x)
#define htonl(x) (x)
#endif
#define htovs(x) swaps(x)
#define htovl(x) swapl(x)
#define vtohs(x) swaps(x)
#define vtohl(x) swapl(x)
#else /* LITTLE ENDIAN */
#ifndef ntohs
#define ntohs(x) swaps(x)
#define ntohl(x) swapl(x)
#define htons(x) swaps(x)
#define htonl(x) swapl(x)
#endif
#define htovs(x) (x)
#define htovl(x) (x)
#define vtohs(x) (x)
#define vtohl(x) (x)
#endif
#endif

extern VALUE cString, cArray;
#ifndef atof
double atof();
#endif

static char *toofew = "too few arguments";

static void encodes();

static VALUE
pack_pack(ary, fmt)
    struct RArray *ary;
    struct RString *fmt;
{
    static char *nul10 = "\0\0\0\0\0\0\0\0\0\0";
    static char *spc10 = "          ";
    UCHAR *p, *pend;
    VALUE res, from;
    char type;
    int items, len, idx;
    UCHAR *ptr;
    int plen;

    Check_Type(fmt, T_STRING);

    p = fmt->ptr;
    pend = fmt->ptr + fmt->len;
    res = str_new(0, 0);

    items = ary->len;
    idx = 0;

#define NEXTFROM (items-- > 0 ? ary->ptr[idx++] : (ArgError(toofew),0))

    while (p < pend) {
	type = *p++;		/* get data type */

	if (*p == '*') {	/* set data length */
	    len = strchr("@Xxu", type) ? 0 : items;
            p++;
	}
	else if (isdigit(*p)) {
	    len = strtoul(p, (char**)&p, 10);
	}
	else {
	    len = 1;
	}

	switch (type) {
	  case 'A': case 'a':
	  case 'B': case 'b':
	  case 'H': case 'h':
	    from = NEXTFROM;
	    if (NIL_P(from)) {
		ptr = 0;
		plen = 0;
	    }
	    else {
		from = obj_as_string(from);
		ptr = RSTRING(from)->ptr;
		plen = RSTRING(from)->len;
	    }

	    if (p[-1] == '*')
		len = plen;

	    switch (type) {
	      case 'a':
	      case 'A':
		if (plen >= len)
		    str_cat(res, ptr, len);
		else {
		    str_cat(res, ptr, plen);
		    len -= plen;
		    while (len >= 10) {
			str_cat(res, (type == 'A')?spc10:nul10, 10);
			len -= 10;
		    }
		    str_cat(res, (type == 'A')?spc10:nul10, len);
		}
		break;

	      case 'b':
		{
		    int byte = 0;
		    int i;

		    for (i=0; i++ < len; ptr++) {
			if (*ptr & 1)
			    byte |= 128;
			if (i & 7)
			    byte >>= 1;
			else {
			    char c = byte & 0xff;
			    str_cat(res, &c, 1);
			    byte = 0;
			}
		    }
		    if (len & 7) {
			char c;
			byte >>= 7 - (len & 7);
			c = byte & 0xff;
			str_cat(res, &c, 1);
		    }
		}
		break;

	      case 'B':
		{
		    int byte = 0;
		    int i;

		    for (i=0; i++ < len; ptr++) {
			byte |= *ptr & 1;
			if (i & 7)
			    byte <<= 1;
			else {
			    char c = byte & 0xff;
			    str_cat(res, &c, 1);
			    byte = 0;
			}
		    }
		    if (len & 7) {
			char c;
			byte <<= 7 - (len & 7);
			c = byte & 0xff;
			str_cat(res, &c, 1);
		    }
		}
		break;

	      case 'h':
		{
		    int byte = 0;
		    int i;

		    for (i=0; i++ < len; ptr++) {
			if (isxdigit(*ptr)) {
			    if (isalpha(*ptr))
				byte |= (((*ptr & 15) + 9) & 15) << 4;
			    else
				byte |= (*ptr & 15) << 4;
			    if (i & 1)
				byte >>= 4;
			    else {
				char c = byte & 0xff;
				str_cat(res, &c, 1);
				byte = 0;
			    }
			}
		    }
		    if (len & 1) {
			char c = byte & 0xff;
			str_cat(res, &c, 1);
		    }
		}
		break;

	      case 'H':
		{
		    int byte = 0;
		    int i;

		    for (i=0; i++ < len; ptr++) {
			if (isxdigit(*ptr)) {
			    if (isalpha(*ptr))
				byte |= ((*ptr & 15) + 9) & 15;
			    else
				byte |= *ptr & 15;
			    if (i & 1)
				byte <<= 4;
			    else {
				char c = byte & 0xff;
				str_cat(res, &c, 1);
				byte = 0;
			    }
			}
		    }
		    if (len & 1) {
			char c = byte & 0xff;
			str_cat(res, &c, 1);
		    }
		}
		break;
	    }
	    break;

	  case 'c':
	  case 'C':
	    while (len-- > 0) {
		char c;

		from = NEXTFROM;
		if (NIL_P(from)) c = 0;
		else {
		    c = NUM2INT(from);
		}
		str_cat(res, &c, sizeof(char));
	    }
	    break;

	  case 's':
	  case 'S':
	    while (len-- > 0) {
		short s;

		from = NEXTFROM;
		if (NIL_P(from)) s = 0;
		else {
		    s = NUM2INT(from);
		}
		str_cat(res, &s, sizeof(short));
	    }
	    break;

	  case 'i':
	  case 'I':
	    while (len-- > 0) {
		int i;

		from = NEXTFROM;
		if (NIL_P(from)) i = 0;
		else {
		    i = NUM2INT(from);
		}
		str_cat(res, &i, sizeof(int));
	    }
	    break;

	  case 'l':
	  case 'L':
	    while (len-- > 0) {
		long l;

		from = NEXTFROM;
		if (NIL_P(from)) l = 0;
		else {
		    l = NUM2INT(from);
		}
		str_cat(res, &l, sizeof(long));
	    }
	    break;

	  case 'n':
	    while (len-- > 0) {
		unsigned short s;

		from = NEXTFROM;
		if (NIL_P(from)) s = 0;
		else {
		    s = NUM2INT(from);
		}
		s = htons(s);
		str_cat(res, &s, sizeof(short));
	    }
	    break;

	  case 'N':
	    while (len-- > 0) {
		unsigned long l;

		from = NEXTFROM;
		if (NIL_P(from)) l = 0;
		else {
		    l = NUM2INT(from);
		}
		l = htonl(l);
		str_cat(res, &l, sizeof(long));
	    }
	    break;

	  case 'v':
	    while (len-- > 0) {
		unsigned short s;

		from = NEXTFROM;
		if (NIL_P(from)) s = 0;
		else {
		    s = NUM2INT(from);
		}
		s = htovs(s);
		str_cat(res, &s, sizeof(short));
	    }
	    break;

	  case 'V':
	    while (len-- > 0) {
		unsigned long l;

		from = NEXTFROM;
		if (NIL_P(from)) l = 0;
		else {
		    l = NUM2INT(from);
		}
		l = htovl(l);
		str_cat(res, &l, sizeof(long));
	    }
	    break;

	  case 'f':
	  case 'F':
	    while (len-- > 0) {
		float f;

		from = NEXTFROM;
		switch (TYPE(from)) {
		  case T_FLOAT:
		    f = RFLOAT(from)->value;
		    break;
		  case T_STRING:
		    f = atof(RSTRING(from)->ptr);
		  default:
		    f = (float)NUM2INT(from);
		    break;
		}
		str_cat(res, &f, sizeof(float));
	    }
	    break;

	  case 'd':
	  case 'D':
	    while (len-- > 0) {
		double d;

		from = NEXTFROM;
		switch (TYPE(from)) {
		  case T_FLOAT:
		    d = RFLOAT(from)->value;
		    break;
		  case T_STRING:
		    d = atof(RSTRING(from)->ptr);
		  default:
		    d = (double)NUM2INT(from);
		    break;
		}
		str_cat(res, &d, sizeof(double));
	    }
	    break;

	  case 'x':
	  grow:
	    while (len >= 10) {
		str_cat(res, nul10, 10);
		len -= 10;
	    }
	    str_cat(res, nul10, len);
	    break;

	  case 'X':
	  shrink:
	    if (RSTRING(res)->len < len)
		ArgError("X outside of string");
	    RSTRING(res)->len -= len;
	    RSTRING(res)->ptr[RSTRING(res)->len] = '\0';
	    break;

	  case '@':
	    len -= RSTRING(res)->len;
	    if (len > 0) goto grow;
	    len = -len;
	    if (len > 0) goto shrink;
	    break;

	  case '%':
	    ArgError("% may only be used in unpack");
	    break;

	  case 'u':
	    from = obj_as_string(NEXTFROM);
	    ptr = RSTRING(from)->ptr;
	    plen = RSTRING(from)->len;

	    if (len <= 1)
		len = 45;
	    else
		len = len / 3 * 3;
	    while (plen > 0) {
		int todo;

		if (plen > len)
		    todo = len;
		else
		    todo = plen;
		encodes(res, ptr, todo);
		plen -= todo;
		ptr += todo;
	    }
	    break;

	  default:
	    break;
	}
    }

    return res;
}

static void
encodes(str, s, len)
    struct RString *str;
    UCHAR *s;
    int len;
{
    char hunk[4];
    UCHAR *p, *pend;

    *hunk = len + ' ';
    str_cat(str, hunk, 1);
    while (len > 0) {
	hunk[0] = ' ' + (077 & (*s >> 2));
	hunk[1] = ' ' + (077 & (((*s << 4) & 060) | ((s[1] >> 4) & 017)));
	hunk[2] = ' ' + (077 & (((s[1] << 2) & 074) | ((s[2] >> 6) & 03)));
	hunk[3] = ' ' + (077 & (s[2] & 077));
	str_cat(str, hunk, 4);
	s += 3;
	len -= 3;
    }
    p = str->ptr;
    pend = str->ptr + str->len;
    while (p < pend) {
	if (*p == ' ')
	    *p = '`';
	p++;
    }
    str_cat(str, "\n", 1);
}

static VALUE
pack_unpack(str, fmt)
    struct RString *str, *fmt;
{
    static char *hexdigits = "0123456789abcdef0123456789ABCDEFx";
    UCHAR *s, *send;
    UCHAR *p, *pend;
    VALUE ary;
    char type;
    int len;

    Check_Type(fmt, T_STRING);

    s = str->ptr;
    send = s + str->len;
    p = fmt->ptr;
    pend = p + fmt->len;

    ary = ary_new();
    while (p < pend) {
	type = *p++;
	if (*p == '*') {
	    len = send - s;
	    p++;
	}
	else if (isdigit(*p)) {
	    len = strtoul(p, (char**)&p, 10);
	}
	else {
	    len = (type != '@');
	}

	switch (type) {
	  case '%':
	    ArgError("% is not supported(yet)");
	    break;

	  case 'A':
	    if (len > send - s) len = send - s;
	    {
		int end = len;
		UCHAR *t = s + len - 1;

		while (t >= s) {
		    if (*t != ' ' && *t != '\0') break;
		    t--;
		    len--;
		}
		ary_push(ary, str_new(s, len));
		s += end;
	    }
	    break;

	  case 'a':
	    if (len > send - s) len = send - s;
	    ary_push(ary, str_new(s, len));
	    s += len;
	    break;

	  case 'b':
	    {
		VALUE bitstr;
		UCHAR *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 8)
		    len = (send - s) * 8;
		bits = 0;
		ary_push(ary, bitstr = str_new(0, len));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 7) bits >>= 1;
		    else bits = *s++;
		    *t++ = (bits & 1) ? '1' : '0';
		}
	    }
	    break;

	  case 'B':
	    {
		VALUE bitstr;
		UCHAR *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 8)
		    len = (send - s) * 8;
		bits = 0;
		ary_push(ary, bitstr = str_new(0, len));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 7) bits <<= 1;
		    else bits = *s++;
		    *t++ = (bits & 128) ? '1' : '0';
		}
	    }
	    break;

	  case 'h':
	    {
		VALUE bitstr;
		UCHAR *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		bits = 0;
		ary_push(ary, bitstr = str_new(0, len));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 1)
			bits >>= 4;
		    else
			bits = *s++;
		    *t++ = hexdigits[bits & 15];
		}
	    }
	    break;

	  case 'H':
	    {
		VALUE bitstr;
		UCHAR *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		bits = 0;
		ary_push(ary, bitstr = str_new(0, len));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 1)
			bits <<= 4;
		    else
			bits = *s++;
		    *t++ = hexdigits[(bits >> 4) & 15];
		}
	    }
	    break;

	  case 'c':
	    if (len > send - s)
		len = send - s;
	    while (len-- > 0) {
                int c = *s++;
                if (c > (char)127) c-=256;
		ary_push(ary, INT2FIX(c));
	    }
	    break;

	  case 'C':
	    if (len > send - s)
		len = send - s;
	    while (len-- > 0) {
		UCHAR c = *s++;
		ary_push(ary, INT2FIX(c));
	    }
	    break;

	  case 's':
	    if (len >= (send - s) / sizeof(short))
		len = (send - s) / sizeof(short);
	    while (len-- > 0) {
		short tmp;
		memcpy(&tmp, s, sizeof(short));
		s += sizeof(short);
		ary_push(ary, INT2FIX(tmp));
	    }
	    break;

	  case 'S':
	    if (len >= (send - s) / sizeof(short))
		len = (send - s) / sizeof(short);
	    while (len-- > 0) {
		unsigned short tmp;
		memcpy(&tmp, s, sizeof(short));
		s += sizeof(short);
		ary_push(ary, INT2FIX(tmp));
	    }
	    break;

	  case 'i':
	    if (len >= (send - s) / sizeof(int))
		len = (send - s) / sizeof(int);
	    while (len-- > 0) {
		int tmp;
		memcpy(&tmp, s, sizeof(int));
		s += sizeof(int);
		ary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'I':
	    if (len >= (send - s) / sizeof(int))
		len = (send - s) / sizeof(int);
	    while (len-- > 0) {
		unsigned int tmp;
		memcpy(&tmp, s, sizeof(int));
		s += sizeof(int);
		ary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'l':
	    if (len >= (send - s) / sizeof(long))
		len = (send - s) / sizeof(long);
	    while (len-- > 0) {
		long tmp;
		memcpy(&tmp, s, sizeof(long));
		s += sizeof(long);
		ary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'L':
	    if (len >= (send - s) / sizeof(long))
		len = (send - s) / sizeof(long);
	    while (len-- > 0) {
		unsigned long tmp;
		memcpy(&tmp, s, sizeof(long));
		s += sizeof(long);
		ary_push(ary, uint2inum(tmp));
	    }
	    break;

	  case 'n':
	    if (len >= (send - s) / sizeof(short))
		len = (send - s) / sizeof(short);
	    while (len-- > 0) {
		unsigned short tmp;
		memcpy(&tmp, s, sizeof(short));
		s += sizeof(short);
		tmp = ntohs(tmp);
		ary_push(ary, uint2inum(tmp));
	    }
	    break;

	  case 'N':
	    if (len >= (send - s) / sizeof(long))
		len = (send - s) / sizeof(long);
	    while (len-- > 0) {
		unsigned long tmp;
		memcpy(&tmp, s, sizeof(long));
		s += sizeof(long);
		tmp = ntohl(tmp);
		ary_push(ary, uint2inum(tmp));
	    }
	    break;

	  case 'v':
	    if (len >= (send - s) / sizeof(short))
		len = (send - s) / sizeof(short);
	    while (len-- > 0) {
		unsigned short tmp;
		memcpy(&tmp, s, sizeof(short));
		s += sizeof(short);
		tmp = vtohs(tmp);
		ary_push(ary, uint2inum(tmp));
	    }
	    break;

	  case 'V':
	    if (len >= (send - s) / sizeof(long))
		len = (send - s) / sizeof(long);
	    while (len-- > 0) {
		unsigned long tmp;
		memcpy(&tmp, s, sizeof(long));
		s += sizeof(long);
		tmp = vtohl(tmp);
		ary_push(ary, uint2inum(tmp));
	    }
	    break;

	  case 'f':
	  case 'F':
	    if (len >= (send - s) / sizeof(float))
		len = (send - s) / sizeof(float);
	    while (len-- > 0) {
		float tmp;
		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		ary_push(ary, float_new((double)tmp));
	    }
	    break;

	  case 'D':
	  case 'd':
	    if (len >= (send - s) / sizeof(double))
		len = (send - s) / sizeof(double);
	    while (len-- > 0) {
		double tmp;
		memcpy(&tmp, s, sizeof(double));
		s += sizeof(double);
		ary_push(ary, float_new(tmp));
	    }
	    break;

	  case 'u':
	    {
		VALUE str = str_new(0, (send - s)*3/4);
		UCHAR *ptr = RSTRING(str)->ptr;
		int total = 0;

		while (s < send && *s > ' ' && *s < 'a') {
		    long a,b,c,d;
		    char hunk[4];

		    hunk[3] = '\0';
		    len = (*s++ - ' ') & 077;
		    total += len;
		    if (total > RSTRING(str)->len) {
			len -= total - RSTRING(str)->len;
			total = RSTRING(str)->len;
		    }

		    while (len > 0) {
			int mlen = len > 3 ? 3 : len;

			if (s < send && *s >= ' ')
			    a = (*s++ - ' ') & 077;
			else
			    a = 0;
			if (s < send && *s >= ' ')
			    b = (*s++ - ' ') & 077;
			else
			    b = 0;
			if (s < send && *s >= ' ')
			    c = (*s++ - ' ') & 077;
			else
			    c = 0;
			if (s < send && *s >= ' ')
			    d = (*s++ - ' ') & 077;
			else
			    d = 0;
			hunk[0] = a << 2 | b >> 4;
			hunk[1] = b << 4 | c >> 2;
			hunk[2] = c << 6 | d;
			memcpy(ptr, hunk, mlen);
			ptr += mlen;
			len -= mlen;
		    }
		    if (*s == '\r') s++;
		    if (*s == '\n') s++;
		    else if (s < send && (s+1 == send || s[1] == '\n'))
			s += 2;	/* possible checksum byte */
		}
		RSTRING(str)->len = total;
		ary_push(ary, str);
	    }
	    break;

	  case '@':
	    s = str->ptr + len;
	    break;

	  case 'X':
	    if (len > s - str->ptr)
		ArgError("X outside of string");
	    s -= len;
	    break;

	  case 'x':
	    if (len > send - s)
		ArgError("x outside of string");
	    s += len;
	    break;

	  default:
	    break;
	}
    }

    return ary;
}

void
Init_pack()
{
    rb_define_method(cArray, "pack", pack_pack, 1);
    rb_define_method(cString, "unpack", pack_unpack, 1);
}
