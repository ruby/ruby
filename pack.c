/************************************************

  pack.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Thu Feb 10 15:17:05 JST 1994

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <ctype.h>
#include <sys/types.h>

#define swaps(x)	((((x)&0xFF)<<8) + (((x)>>8)&0xFF))
#define swapl(x)	((((x)&0xFF)<<24)	\
			+(((x)>>24)&0xFF)	\
			+(((x)&0x0000FF00)<<8)	\
			+(((x)&0x00FF0000)>>8)	)
#ifdef WORDS_BIGENDIAN
#define ntohs(x) (x)
#define ntohl(x) (x)
#define htons(x) (x)
#define htonl(x) (x)
#define htovs(x) swaps(x)
#define htovl(x) swapl(x)
#define vtohs(x) swaps(x)
#define vtohl(x) swapl(x)
#else /* LITTLE ENDIAN */
#define ntohs(x) swaps(x)
#define ntohl(x) swapl(x)
#define htons(x) swaps(x)
#define htonl(x) swapl(x)
#define htovs(x) (x)
#define htovl(x) (x)
#define vtohs(x) (x)
#define vtohl(x) (x)
#endif

extern VALUE C_String, C_Array;
double atof();

static char *toofew = "too few arguments";

int strtoul();
static void encodes();

static VALUE
Fpck_pack(ary, fmt)
    struct RArray *ary;
    struct RString *fmt;
{
    static char *nul10 = "\0\0\0\0\0\0\0\0\0\0";
    static char *spc10 = "          ";
    char *p, *pend;
    VALUE res, from;
    char type;
    int items, len, idx;
    char *ptr;
    int plen;

    Check_Type(fmt, T_STRING);

    p = fmt->ptr;
    pend = fmt->ptr + fmt->len;
    GC_LINK;
    GC_PRO2(from);
    GC_PRO3(res, str_new(0, 0));

    items = ary->len;
    idx = 0;

#define NEXTFROM (items-- > 0 ? ary->ptr[idx++] : Fail(toofew))

    while (p < pend) {
	type = *p++;		/* get data type */

	if (*p == '*') {	/* set data length */
	    len = index("@Xxu", type) ? 0 : items;
            p++;
	}
	else if (isdigit(*p)) {
	    len = strtoul(p, &p, 10);
	}
	else {
	    len = 1;
	}

	switch (type) {
	  case 'A': case 'a':
	  case 'B': case 'b':
	  case 'H': case 'h':
	    from = NEXTFROM;
	    if (from == Qnil) {
		ptr = Qnil;
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
		if (plen > len)
		    str_cat(res, ptr, len);
		else {
		    str_cat(res, ptr, plen);
		    len == plen;
		    while (len >= 10) {
			str_cat(res, nul10, 10);
			len -= 10;
		    }
		    str_cat(res, nul10, len);
		}
		break;

	      case 'A':
		if (plen > len)
		    str_cat(res, ptr, len);
		else {
		    str_cat(res, ptr, plen);
		    len == plen;
		    while (len >= 10) {
			str_cat(res, spc10, 10);
			len -= 10;
		    }
		    str_cat(res, spc10, len);
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
		if (from == Qnil) c = 0;
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
		if (from == Qnil) s = 0;
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
		if (from == Qnil) i = 0;
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
		if (from == Qnil) l = 0;
		else {
		    l = NUM2INT(from);
		}
		str_cat(res, &l, sizeof(long));
	    }
	    break;

	  case 'n':
	    while (len-- > 0) {
		short s;

		from = NEXTFROM;
		if (from == Qnil) s = 0;
		else {
		    s = NUM2INT(from);
		}
		s = htons(s);
		str_cat(res, &s, sizeof(short));
	    }
	    break;

	  case 'N':
	    while (len-- > 0) {
		long l;

		from = NEXTFROM;
		if (from == Qnil) l = 0;
		else {
		    l = NUM2INT(from);
		}
		l = htonl(l);
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

	  case 'v':
	    while (len-- > 0) {
		short s;

		from = NEXTFROM;
		if (from == Qnil) s = 0;
		else {
		    s = NUM2INT(from);
		}
		s = htovs(s);
		str_cat(res, &s, sizeof(short));
	    }
	    break;

	  case 'V':
	    while (len-- > 0) {
		long l;

		from = NEXTFROM;
		if (from == Qnil) l = 0;
		else {
		    l = NUM2INT(from);
		}
		l = htovl(l);
		str_cat(res, &l, sizeof(long));
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
		Fail("X outside of string");
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
	    Fail("% may only be used in unpack");
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
    GC_UNLINK;

    return res;
}

static void
encodes(str, s, len)
    struct RString *str;
    char *s;
    int len;
{
    char hunk[4];
    char *p, *pend;

    p = str->ptr + str->len;
    *hunk = len + ' ';
    str_cat(str, hunk, 1);
    while (len > 0) {
	hunk[0] = ' ' + (077 & (*s >> 2));
	hunk[1] = ' ' + (077 & ((*s << 4) & 060 | (s[1] >> 4) & 017));
	hunk[2] = ' ' + (077 & ((s[1] << 2) & 074 | (s[2] >> 6) & 03));
	hunk[3] = ' ' + (077 & (s[2] & 077));
	str_cat(str, hunk, 4);
	s += 3;
	len -= 3;
    }
    pend = str->ptr + str->len;
    while (p < pend) {
	if (*p == ' ')
	    *p = '`';
	p++;
    }
    str_cat(str, "\n", 1);
}

static VALUE
Fpck_unpack(str, fmt)
    struct RString *str, *fmt;
{
    static char *hexdigits = "0123456789abcdef0123456789ABCDEFx";
    char *s, *send;
    char *p, *pend;
    VALUE ary;
    char type;
    int len;

    Check_Type(fmt, T_STRING);

    s = str->ptr;
    send = s + str->len;
    p = fmt->ptr;
    pend = p + fmt->len;

    GC_LINK;
    GC_PRO3(ary, ary_new());
    while (p < pend) {
      retry:
	type = *p++;
	if (*p == '*') {
	    len = send - s;
	    p++;
	}
	else if (isdigit(*p)) {
	    len = strtoul(p, &p, 10);
	}
	else {
	    len = (type != '@');
	}

	switch (type) {
	  case '%':
	    Fail("% is not supported(yet)");
	    break;

	  case 'A':
	    if (len > send - s) len = send - s;
	    {
		char *t = s + len - 1;

		while (t >= s) {
		    if (*t != ' ' && *t != '\0') break;
		    t--;
		    len--;
		}
	    }
	  case 'a':
	    if (len > send - s) len = send - s;
	    Fary_push(ary, str_new(s, len));
	    s += len;
	    break;

	  case 'b':
	    {
		VALUE bitstr;
		char *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 8)
		    len = (send - s) * 8;
		Fary_push(ary, bitstr = str_new(0, len + 1));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 7) bits >>= 1;
		    else bits = *s++;
		    *t++ = (bits & 1) ? '1' : '0';
		}
		*t = '\0';
	    }
	    break;

	  case 'B':
	    {
		VALUE bitstr;
		char *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 8)
		    len = (send - s) * 8;
		Fary_push(ary, bitstr = str_new(0, len + 1));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 7) bits <<= 1;
		    else bits = *s++;
		    *t++ = (bits & 128) ? '1' : '0';
		}
		*t = '\0';
	    }
	    break;

	  case 'h':
	    {
		VALUE bitstr;
		char *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		Fary_push(ary, bitstr = str_new(0, len + 1));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 1)
			bits >>= 4;
		    else
			bits = *s++;
		    *t++ = hexdigits[bits & 15];
		}
		*t = '\0';
	    }
	    break;

	  case 'H':
	    {
		VALUE bitstr;
		char *t;
		int bits, i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		Fary_push(ary, bitstr = str_new(0, len + 1));
		t = RSTRING(bitstr)->ptr;
		for (i=0; i<len; i++) {
		    if (i & 1)
			bits <<= 4;
		    else
			bits = *s++;
		    *t++ = hexdigits[(bits >> 4) & 15];
		}
		*t = '\0';
	    }
	    break;

	  case 'c':
	    if (len > send - s)
		len = send - s;
	    while (len-- > 0) {
		char c = *s++;
		Fary_push(ary, INT2FIX(c));
	    }
	    break;

	  case 'C':
	    if (len > send - s)
		len = send - s;
	    while (len-- > 0) {
		unsigned char c = *s++;
		Fary_push(ary, INT2FIX(c));
	    }
	    break;

	  case 's':
	    if (len >= (send - s) / sizeof(short))
		len = (send - s) / sizeof(short);
	    while (len-- > 0) {
		short tmp;
		memcpy(&tmp, s, sizeof(short));
		s += sizeof(short);
		Fary_push(ary, INT2FIX(tmp));
	    }
	    break;

	  case 'S':
	    if (len >= (send - s) / sizeof(unsigned short))
		len = (send - s) / sizeof(unsigned short);
	    while (len-- > 0) {
		unsigned short tmp;
		memcpy(&tmp, s, sizeof(unsigned short));
		s += sizeof(unsigned short);
		Fary_push(ary, INT2FIX(tmp));
	    }
	    break;

	  case 'i':
	    if (len >= (send - s) / sizeof(int))
		len = (send - s) / sizeof(int);
	    while (len-- > 0) {
		int tmp;
		memcpy(&tmp, s, sizeof(int));
		s += sizeof(int);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'I':
	    if (len >= (send - s) / sizeof(unsigned int))
		len = (send - s) / sizeof(unsigned int);
	    while (len-- > 0) {
		unsigned int tmp;
		memcpy(&tmp, s, sizeof(unsigned int));
		s += sizeof(unsigned int);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'l':
	    if (len >= (send - s) / sizeof(long))
		len = (send - s) / sizeof(long);
	    while (len-- > 0) {
		long tmp;
		memcpy(&tmp, s, sizeof(long));
		s += sizeof(long);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'L':
	    if (len >= (send - s) / sizeof(unsigned long))
		len = (send - s) / sizeof(unsigned long);
	    while (len-- > 0) {
		unsigned long tmp;
		memcpy(&tmp, s, sizeof(unsigned long));
		s += sizeof(unsigned long);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'n':
	    if (len >= (send - s) / sizeof(short))
		len = (send - s) / sizeof(short);
	    while (len-- > 0) {
		short tmp;
		memcpy(&tmp, s, sizeof(short));
		s += sizeof(short);
		tmp = ntohs(tmp);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'N':
	    if (len >= (send - s) / sizeof(long))
		len = (send - s) / sizeof(long);
	    while (len-- > 0) {
		long tmp;
		memcpy(&tmp, s, sizeof(long));
		s += sizeof(long);
		tmp = ntohl(tmp);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'F':
	  case 'f':
	    if (len >= (send - s) / sizeof(float))
		len = (send - s) / sizeof(float);
	    while (len-- > 0) {
		float tmp;
		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		Fary_push(ary, float_new((double)tmp));
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
		Fary_push(ary, float_new(tmp));
	    }
	    break;

	  case 'v':
	    if (len >= (send - s) / sizeof(short))
		len = (send - s) / sizeof(short);
	    while (len-- > 0) {
		short tmp;
		memcpy(&tmp, s, sizeof(short));
		s += sizeof(short);
		tmp = vtohs(tmp);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'V':
	    if (len >= (send - s) / sizeof(long))
		len = (send - s) / sizeof(long);
	    while (len-- > 0) {
		long tmp;
		memcpy(&tmp, s, sizeof(long));
		s += sizeof(long);
		tmp = vtohl(tmp);
		Fary_push(ary, int2inum(tmp));
	    }
	    break;

	  case 'u':
	    {
		VALUE str = str_new(0, (send - s)*3/4);
		char *ptr = RSTRING(str)->ptr;

		while (s < send && *s > ' ' && *s < 'a') {
		    int a,b,c,d;
		    char hunk[4];

		    hunk[3] = '\0';
		    len = (*s++ - ' ') & 077;
		    while (len > 0) {
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
			memcpy(ptr, hunk, len > 3 ? 3 : len);
			ptr += 3;
			len -= 3;
		    }
		    if (s[0] == '\n')
			s++;
		    else if (s[1] == '\n') /* possible checksum byte */
			s += 2;
		}
		Fary_push(ary, str);
	    }
	    break;

	  case '@':
	    s = str->ptr + len;
	    break;

	  case 'X':
	    if (len > s - str->ptr)
		Fail("X outside of string");
	    s -= len;
	    break;

	  case 'x':
	    if (len > send - s)
		Fail("x outside of string");
	    s += len;
	    break;

	  default:
	    break;
	}
    }

    GC_UNLINK;
    return ary;
}

Init_pack()
{
    rb_define_method(C_Array, "pack", Fpck_pack, 1);
    rb_define_method(C_String, "unpack", Fpck_unpack, 1);
}
