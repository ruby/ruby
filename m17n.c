/**********************************************************************

  m17n.c -

  $Author$
  $Date$
  created at: Thu Dec 28 16:29:43 JST 2000

  Copyright (C) 1993-2001 Yukihiro Matsumoto

**********************************************************************/

#include "config.h"
#include <stdlib.h>
#ifdef HAVE_STRING_H
# include <string.h>
#else
# include <strings.h>
#endif
#include "m17n.h"

#define uchar unsigned char

static int num_encodings = 1;
m17n_encoding **m17n_encoding_table = 0;

static int any_strlen _((const uchar *p, const uchar *e, const m17n_encoding* enc));
static uchar *any_nth _((uchar *p, const uchar *e, int n, const m17n_encoding* enc));

m17n_encoding*
m17n_define_encoding(name)
    const char *name;
{
    m17n_encoding *enc;

    if (!m17n_encoding_table) {
	m17n_init();
    }
    num_encodings++;
    m17n_encoding_table = realloc(m17n_encoding_table,
				  sizeof(m17n_encoding*)*num_encodings);
    enc = malloc(sizeof(m17n_encoding));

    /* copy ASCII table */
    memcpy(enc, m17n_encoding_table[0], sizeof(m17n_encoding));
    /* ..but strlen() */
    m17n_encoding_func_strlen(enc, any_strlen);
    /* ..and nth() */
    m17n_encoding_func_nth(enc, any_nth);
    /* mbmaxlen is unknown (i.e. 0) */
    m17n_encoding_mbmaxlen(enc, 0);

    enc->name = name;
    enc->index = num_encodings-1;
    m17n_encoding_table[enc->index] = enc;
    return enc;
}

m17n_encoding *
m17n_find_encoding(name)
    const char *name;
{
    int i;

    for (i=0; i<num_encodings; i++) {
	if (strcmp(name, m17n_encoding_table[i]->name) == 0) {
	    return m17n_encoding_table[i];
	}
    }
    return 0;
}

static int
asc_strlen(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    return e - p;
}

static int
asc_mbclen(c, enc)
    int c;
    const m17n_encoding *enc;
{
    return 1;
}

static int
asc_codelen(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    return 1;
}

static int
asc_mbcspan(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    return 1;
}

static int
asc_islead(c, enc)
    int c;
    const m17n_encoding *enc;
{
    return 1;
}

static uchar*
asc_nth(p, e, n, enc)
    uchar *p;
    const uchar *e;
    int n;
    const m17n_encoding *enc;
{
    p += n;
    if (p <= e) return p;
    return 0;
}

static uchar asc_ctype_table [] = {
     32, 32, 32, 32, 32, 32, 32, 32, 32, 40, 40, 40, 40, 40, 32, 32,
     32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32,
     72, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    132,132,132,132,132,132,132,132,132,132, 16, 16, 16, 16, 16, 16,
     16,129,129,129,129,129,129,  1,  1,  1,  1,  1,  1,  1,  1,  1,
      1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1, 16, 16, 16, 16, 16,
     16,130,130,130,130,130,130,  2,  2,  2,  2,  2,  2,  2,  2,  2,
      2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2, 16, 16, 16, 16, 32,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
};

static int
asc_ctype(c, code, enc)
    unsigned int c, code;
    const m17n_encoding *enc;
{
    if (c > 0xff) return 0;
    return asc_ctype_table[c] & code;
}

static uchar asc_toupper_table[] = {
      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
     64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
     80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
     96, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
     80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,123,124,125,126,127,
};

static unsigned int
asc_toupper(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    if (c > 127) return c;
    return asc_toupper_table[c];
}

static uchar asc_tolower_table[] = {
      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
     64, 97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111,
    112,113,114,115,116,117,118,119,120,121,122, 91, 92, 93, 94, 95,
     96, 97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111,
    112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,
};

static unsigned int
asc_tolower(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    if (c > 127) return c;
    return asc_tolower_table[c];
}

static unsigned int
asc_codepoint(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    return *p;
}

static int
asc_firstbyte(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    return c;
}

static void
asc_mbcput(c, p, enc)
    unsigned int c;
    uchar *p;
    const m17n_encoding *enc;
{
    *p = (uchar)c;
}

static int
any_strlen(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    int	c;

    if (m17n_mbmaxlen(enc) == 1) {
	return e - p;
    }

    for (c=0; p<e; c++) {
	int n = m17n_mbcspan(enc, p, e);

	if (n == 0) return -1;
	p += n;
    }
    return c;
}

static uchar*
any_nth(p, e, n, enc)
    uchar *p;
    const uchar *e;
    int n;
    const m17n_encoding *enc;
{
    int	c;

    if (m17n_mbmaxlen(enc) == 1) {
	p += n;
    }
    else {
	for (c=0; p<e && n--; c++) {
	    int n = m17n_mbcspan(enc, p, e);

	    if (n == 0) return (uchar*)-1;
	    p += n;
	}
    }
    if (p <= e) return p;
    return 0;
}

static uchar latin1_ctype_table[] = {
     32, 32, 32, 32, 32, 32, 32, 32, 32, 40, 40, 40, 40, 40, 32, 32,
     32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32,
     72, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    132,132,132,132,132,132,132,132,132,132, 16, 16, 16, 16, 16, 16,
     16,129,129,129,129,129,129,  1,  1,  1,  1,  1,  1,  1,  1,  1,
      1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1, 16, 16, 16, 16, 16,
     16,130,130,130,130,130,130,  2,  2,  2,  2,  2,  2,  2,  2,  2,
      2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2, 16, 16, 16, 16, 32,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
      0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
     72, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
     16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
      1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,
      1,  1,  1,  1,  1,  1,  1, 16,  1,  1,  1,  1,  1,  1,  1,  2,
      2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,
      2,  2,  2,  2,  2,  2,  2, 16,  2,  2,  2,  2,  2,  2,  2,  2
};

static int
latin1_ctype(c, code, enc)
    unsigned int c, code;
    const m17n_encoding *enc;
{
    if (c > 0xff) return 0;
    return latin1_ctype_table[c] & code;
}

uchar latin1_toupper_table[] = {
      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
     64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
     80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
     96, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
     80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,123,124,125,126,127,
    128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
    144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
    160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
    176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
    192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
    208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,
    192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,
    208,209,210,211,212,213,214,247,216,217,218,219,220,221,222,255
};

static unsigned int
latin1_toupper(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    if (c > 0xff) return c;
    return latin1_toupper_table[c];
}

uchar latin1_tolower_table[] = {
      0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
     16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
     32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
     48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
     64, 97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111,
    112,113,114,115,116,117,118,119,120,121,122, 91, 92, 93, 94, 95,
     96, 97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111,
    112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,
    128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,
    144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,
    160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,
    176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,
    224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
    240,241,242,243,244,245,246,215,248,249,250,251,252,253,254,223,
    224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,
    240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255
};

static unsigned int
latin1_tolower(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    if (c > 0xff) return c;
    return latin1_tolower_table[c];
}

static int
eucjp_mbclen(c, enc)
    int c;
    const m17n_encoding *enc;
{
    return c < 0x80 ? 1 :
	0xa1 <= c && c <= 0xfe ? 2 :
	c == 0x8e ? 2 :
	c == 0x8f ? 3 :
	1;
}

static int
eucjp_mbcspan(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    return *p < 0x80 ? 1 :
	   0xa1 <= *p && *p <= 0xfe && e-p >= 2 ? 2 :
	   *p == 0x8e && e-p >= 2 ? 2 :
	   *p == 0x8f && e-p >= 3 ? 3 :
	   0;
}

static int
eucjp_islead(c, enc)
    int c;
    const m17n_encoding *enc;
{
    if (0xa1 <= c && c <= 0xfe) return 0;
    return 1;
}

static unsigned int
jis_codepoint(p, e, enc)
    uchar *p, *e;
    const m17n_encoding *enc;
{
    int n;
    unsigned int c;

    if (p == e) return 0;
    if (*p < 0x80) return *p;
    n = m17n_mbcspan(enc, p, e);
    if (e-p < n) return *p;
    c = 0;
    while (n--) {
	c <<= 8;
	c |= *p++;
    }
    return c;
}

static int
jis_codelen(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    int n = 1;
    for (;;) {
	if (c < 0x100) return n;
	c >>= 8;
	n++;
    }
}

static int
jis_firstbyte(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    for (;;) {
	if (c < 0x100) return c;
	c >>= 8;
    }
}

static void
jis_mbcput(c, p, enc)
    unsigned int c;
    uchar *p;
    const m17n_encoding *enc;
{
    unsigned int n;

    if (n = (c & 0xff0000)) {
	*p++ = (n >> 16) & 0xff;
    }
    if (n = (c & 0xff00)) {
	*p++ = (n >> 8) & 0xff;
    }
    if (n = (c & 0xff)) {
	*p++ = n & 0xff;
    }
}

#define issjis1(c) ((0x81<=(c) && (c)<=0x9f) || (0xe0<=(c) && (c)<=0xfc))
#define issjis2(c) ((0x40<=(c) && (c)<=0x7e) || (0x80<=(c) && (c)<=0xfc))

static int
sjis_mbclen(c, enc)
    int c;
    const m17n_encoding *enc;
{
    return issjis1(c) ? 2: 1;
}

static int
sjis_mbcspan(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    return issjis1(p[0]) && e-p >= 2 &&
	   issjis2(p[1]) ? 2 :
	   (p[0] & 0x80) ? 0 :
	   1;
}

static int
sjis_islead(c, enc)
    int c;
    const m17n_encoding *enc;
{
    return issjis2(c) ? 0: 1;
}

static int
sjis_ctype(c, code, enc)
    unsigned int c, code;
    const m17n_encoding *enc;
{
    if (0x9f < c && c < 0xe0) return 0020 & code;
    return asc_ctype_table[c] & code;
}

static const uchar utf8_mbctab[] = {
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
  3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
  4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 1, 1
};

static int
utf8_mbclen(c, enc)
    int c;
    const m17n_encoding *enc;
{
    return utf8_mbctab[c];
}

static int
utf8_codelen(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    if (c <= 0x7f) return 1;
    if (c <= 0x7ff) return 2;
    if (c <= 0xffff) return 3;
    if (c <= 0x1fffff) return 4;
    if (c <= 0x3ffffff) return 5;
    if (c <= 0x7fffffff) return 6;
    return 1;
}

static int
utf8_mbcspan(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    if (e-p < utf8_mbctab[*p]) return 0;
    return utf8_mbctab[*p];
}

static int
utf8_islead(c, enc)
    int c;
    const m17n_encoding *enc;
{
    if (c < 0x80 || (c & 0xc0) == 0xc0) return 1;
    return 0;
}

static unsigned int
utf8_codepoint(p, e, enc)
    const uchar *p, *e;
    const m17n_encoding *enc;
{
    int n;
    unsigned int c;

    if (p == e) return 0;
    if (*p < 0x80) return *p;
    c = *p++;
    n = utf8_mbctab[c];
    if (e-p < n) return 0;
    n--;
    c &= (1<<(6-n))-1;
    while (n--) {
	c = c << 6 | (*p++ & ((1<<6)-1));
    }
    return c;
}

static int
utf8_firstbyte(c, enc)
    unsigned int c;
    const m17n_encoding *enc;
{
    if (c < 0x80) return c;
    if (c <= 0x7ff) return ((c>>6)&0xff)|0xc0;
    if (c <= 0xffff) return ((c>>12)&0xff)|0xe0;
    if (c <= 0x1fffff) return ((c>>18)&0xff)|0xf0;
    if (c <= 0x3ffffff) return ((c>>24)&0xff)|0xf8;
    if (c <= 0x7fffffff) return ((c>>30)&0xff)|0xfc;
    return 0;
}

static void
utf8_mbcput(c, p, enc)
    unsigned int c;
    uchar *p;
    const m17n_encoding *enc;
{
    if (c < 0x80) *p = c;
    else if (c <= 0x7ff) {
	*p++ = ((c>>6)&0xff)|0xc0;
	*p =   (c & 0x3f)   |0x80;
    }
    else if (c <= 0xffff) {
	*p++ = ((c>>12)&0xff)|0xe0;
	*p++ = ((c>>6) &0x3f)|0x80;
	*p =   (c      &0x3f)|0x80;
    }
    else if (c <= 0x1fffff) {
	*p++ = ((c>>18)&0xff)|0xf0;
	*p++ = ((c>>12)&0x3f)|0xe0;
	*p++ = ((c>>6) &0x3f)|0x80;
	*p =   (c      &0x3f)|0x80;
    }
    else if (c <= 0x3ffffff) {
	*p++ = ((c>>24)&0xff)|0xf8;
	*p++ = ((c>>18)&0x3f)|0xf0;
	*p++ = ((c>>12)&0x3f)|0xe0;
	*p++ = ((c>>6) &0x3f)|0x80;
	*p =   (c      &0x3f)|0x80;
    }
    else if (c <= 0x7fffffff) {
	*p++ = ((c>>30)&0xff)|0xfc;
	*p++ = ((c>>24)&0x3f)|0xf8;
	*p++ = ((c>>18)&0x3f)|0xf0;
	*p++ = ((c>>12)&0x3f)|0xe0;
	*p++ = ((c>>6) &0x3f)|0x80;
	*p =   (c      &0x3f)|0x80;
    }
}

void
m17n_init()
{
    m17n_encoding *enc;

    if (m17n_encoding_table) return; /* already initialized */

    m17n_encoding_table = malloc(sizeof(m17n_encoding*)*4);
    enc = malloc(sizeof(m17n_encoding));
    m17n_encoding_table[0] = enc;
    enc->name = "ascii";

    m17n_encoding_mbmaxlen(enc, 1);
    m17n_encoding_func_strlen(enc, asc_strlen);
    m17n_encoding_func_mbclen(enc, asc_mbclen);
    m17n_encoding_func_codelen(enc, asc_codelen);
    m17n_encoding_func_mbcspan(enc, asc_mbcspan);
    m17n_encoding_func_islead(enc, asc_islead);
    m17n_encoding_func_nth(enc, asc_nth);
    m17n_encoding_func_ctype(enc, asc_ctype);
    m17n_encoding_func_toupper(enc, asc_toupper);
    m17n_encoding_func_tolower(enc, asc_tolower);
    m17n_encoding_func_codepoint(enc, asc_codepoint);
    m17n_encoding_func_firstbyte(enc, asc_firstbyte);
    m17n_encoding_func_mbcput(enc, asc_mbcput);

    enc = m17n_define_encoding("latin1");
    m17n_encoding_mbmaxlen(enc, 1);
    m17n_encoding_func_ctype(enc, latin1_ctype);
    m17n_encoding_func_toupper(enc, latin1_toupper);
    m17n_encoding_func_tolower(enc, latin1_tolower);

    enc = m17n_define_encoding("euc-jp");
    m17n_encoding_mbmaxlen(enc, 3);
    m17n_encoding_func_mbclen(enc, eucjp_mbclen);
    m17n_encoding_func_codelen(enc, jis_codelen);
    m17n_encoding_func_mbcspan(enc, eucjp_mbcspan);
    m17n_encoding_func_islead(enc, eucjp_islead);
    m17n_encoding_func_codepoint(enc, jis_codepoint);
    m17n_encoding_func_firstbyte(enc, jis_firstbyte);
    m17n_encoding_func_mbcput(enc, jis_mbcput);

    enc = m17n_define_encoding("sjis");
    m17n_encoding_mbmaxlen(enc, 2);
    m17n_encoding_func_mbclen(enc, sjis_mbclen);
    m17n_encoding_func_codelen(enc, jis_codelen);
    m17n_encoding_func_mbcspan(enc, sjis_mbcspan);
    m17n_encoding_func_islead(enc, sjis_islead);
    m17n_encoding_func_ctype(enc, sjis_ctype);
    m17n_encoding_func_codepoint(enc, jis_codepoint);
    m17n_encoding_func_firstbyte(enc, jis_firstbyte);
    m17n_encoding_func_mbcput(enc, jis_mbcput);

    enc = m17n_define_encoding("utf-8");
    m17n_encoding_mbmaxlen(enc, 6);
    m17n_encoding_func_mbclen(enc, utf8_mbclen);
    m17n_encoding_func_codelen(enc, utf8_codelen);
    m17n_encoding_func_mbcspan(enc, utf8_mbcspan);
    m17n_encoding_func_islead(enc, utf8_islead);
    m17n_encoding_func_codepoint(enc, utf8_codepoint);
    m17n_encoding_func_firstbyte(enc, utf8_firstbyte);
    m17n_encoding_func_mbcput(enc, utf8_mbcput);
}

int
m17n_memcmp(p1, p2, len, enc)
    const char *p1, *p2;
    long len;
    const m17n_encoding *enc;
{
    int tmp;

    while (len--) {
	if (tmp = m17n_toupper(enc, (unsigned)*p1++) -
	          m17n_toupper(enc, (unsigned)*p2++))
	    return tmp;
    }
    return 0;
}
