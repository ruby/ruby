/**********************************************************************

  pack.c -

  $Author$
  created at: Thu Feb 10 15:17:05 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"
#include <sys/types.h>
#include <ctype.h>
#include <errno.h>

#define SIZE16 2
#define SIZE32 4

#if SIZEOF_SHORT != 2 || SIZEOF_LONG != 4
# define NATINT_PACK
#endif

#ifdef NATINT_PACK
# define OFF16B(p) ((char*)(p) + (natint?0:(sizeof(short) - SIZE16)))
# define OFF32B(p) ((char*)(p) + (natint?0:(sizeof(long) - SIZE32)))
# define NATINT_LEN(type,len) (natint?sizeof(type):(len))
# ifdef WORDS_BIGENDIAN
#   define OFF16(p) OFF16B(p)
#   define OFF32(p) OFF32B(p)
# endif
# define NATINT_HTOVS(x) (natint?htovs(x):htov16(x))
# define NATINT_HTOVL(x) (natint?htovl(x):htov32(x))
# define NATINT_HTONS(x) (natint?htons(x):hton16(x))
# define NATINT_HTONL(x) (natint?htonl(x):hton32(x))
#else
# define NATINT_LEN(type,len) sizeof(type)
# define NATINT_HTOVS(x) htovs(x)
# define NATINT_HTOVL(x) htovl(x)
# define NATINT_HTONS(x) htons(x)
# define NATINT_HTONL(x) htonl(x)
#endif

#ifndef OFF16
# define OFF16(p) (char*)(p)
# define OFF32(p) (char*)(p)
#endif
#ifndef OFF16B
# define OFF16B(p) (char*)(p)
# define OFF32B(p) (char*)(p)
#endif

#define define_swapx(x, xtype)		\
static xtype				\
TOKEN_PASTE(swap,x)(xtype z)		\
{					\
    xtype r;				\
    xtype *zp;				\
    unsigned char *s, *t;		\
    int i;				\
					\
    zp = xmalloc(sizeof(xtype));	\
    *zp = z;				\
    s = (unsigned char*)zp;		\
    t = xmalloc(sizeof(xtype));		\
    for (i=0; i<sizeof(xtype); i++) {	\
	t[sizeof(xtype)-i-1] = s[i];	\
    }					\
    r = *(xtype *)t;			\
    xfree(t);				\
    xfree(zp);				\
    return r;				\
}

#ifndef swap16
#define swap16(x)	((((x)&0xFF)<<8) | (((x)>>8)&0xFF))
#endif
#if SIZEOF_SHORT == 2
#define swaps(x)	swap16(x)
#else
#if SIZEOF_SHORT == 4
#define swaps(x)	((((x)&0xFF)<<24)	\
			|(((x)>>24)&0xFF)	\
			|(((x)&0x0000FF00)<<8)	\
			|(((x)&0x00FF0000)>>8)	)
#else
define_swapx(s,short)
#endif
#endif

#ifndef swap32
#define swap32(x)	((((x)&0xFF)<<24)	\
			|(((x)>>24)&0xFF)	\
			|(((x)&0x0000FF00)<<8)	\
			|(((x)&0x00FF0000)>>8)	)
#endif
#if SIZEOF_LONG == 4
#define swapl(x)	swap32(x)
#else
#if SIZEOF_LONG == 8
#define swapl(x)        ((((x)&0x00000000000000FF)<<56)	\
			|(((x)&0xFF00000000000000)>>56)	\
			|(((x)&0x000000000000FF00)<<40)	\
			|(((x)&0x00FF000000000000)>>40)	\
			|(((x)&0x0000000000FF0000)<<24)	\
			|(((x)&0x0000FF0000000000)>>24)	\
			|(((x)&0x00000000FF000000)<<8)	\
			|(((x)&0x000000FF00000000)>>8))
#else
define_swapx(l,long)
#endif
#endif

#if SIZEOF_FLOAT == 4
#if SIZEOF_LONG == 4	/* SIZEOF_FLOAT == 4 == SIZEOF_LONG */
#define swapf(x)	swapl(x)
#define FLOAT_SWAPPER	unsigned long
#else
#if SIZEOF_SHORT == 4	/* SIZEOF_FLOAT == 4 == SIZEOF_SHORT */
#define swapf(x)	swaps(x)
#define FLOAT_SWAPPER	unsigned short
#else	/* SIZEOF_FLOAT == 4 but undivide by known size of int */
define_swapx(f,float)
#endif	/* #if SIZEOF_SHORT == 4 */
#endif	/* #if SIZEOF_LONG == 4 */
#else	/* SIZEOF_FLOAT != 4 */
define_swapx(f,float)
#endif	/* #if SIZEOF_FLOAT == 4 */

#if SIZEOF_DOUBLE == 8
#if SIZEOF_LONG == 8	/* SIZEOF_DOUBLE == 8 == SIZEOF_LONG */
#define swapd(x)	swapl(x)
#define DOUBLE_SWAPPER	unsigned long
#else
#if SIZEOF_LONG == 4	/* SIZEOF_DOUBLE == 8 && 4 == SIZEOF_LONG */
static double
swapd(const double d)
{
    double dtmp = d;
    unsigned long utmp[2];
    unsigned long utmp0;

    utmp[0] = 0; utmp[1] = 0;
    memcpy(utmp,&dtmp,sizeof(double));
    utmp0 = utmp[0];
    utmp[0] = swapl(utmp[1]);
    utmp[1] = swapl(utmp0);
    memcpy(&dtmp,utmp,sizeof(double));
    return dtmp;
}
#else
#if SIZEOF_SHORT == 4	/* SIZEOF_DOUBLE == 8 && 4 == SIZEOF_SHORT */
static double
swapd(const double d)
{
    double dtmp = d;
    unsigned short utmp[2];
    unsigned short utmp0;

    utmp[0] = 0; utmp[1] = 0;
    memcpy(utmp,&dtmp,sizeof(double));
    utmp0 = utmp[0];
    utmp[0] = swaps(utmp[1]);
    utmp[1] = swaps(utmp0);
    memcpy(&dtmp,utmp,sizeof(double));
    return dtmp;
}
#else	/* SIZEOF_DOUBLE == 8 but undivied by known size of int */
define_swapx(d, double)
#endif	/* #if SIZEOF_SHORT == 4 */
#endif	/* #if SIZEOF_LONG == 4 */
#endif	/* #if SIZEOF_LONG == 8 */
#else	/* SIZEOF_DOUBLE != 8 */
define_swapx(d, double)
#endif	/* #if SIZEOF_DOUBLE == 8 */

#undef define_swapx

#ifdef DYNAMIC_ENDIAN
#ifdef ntohs
#undef ntohs
#undef ntohl
#undef htons
#undef htonl
#endif
static int
endian(void)
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
#define ntohf(x) (endian()?(x):swapf(x))
#define ntohd(x) (endian()?(x):swapd(x))
#define htons(x) (endian()?(x):swaps(x))
#define htonl(x) (endian()?(x):swapl(x))
#define htonf(x) (endian()?(x):swapf(x))
#define htond(x) (endian()?(x):swapd(x))
#define htovs(x) (endian()?swaps(x):(x))
#define htovl(x) (endian()?swapl(x):(x))
#define htovf(x) (endian()?swapf(x):(x))
#define htovd(x) (endian()?swapd(x):(x))
#define vtohs(x) (endian()?swaps(x):(x))
#define vtohl(x) (endian()?swapl(x):(x))
#define vtohf(x) (endian()?swapf(x):(x))
#define vtohd(x) (endian()?swapd(x):(x))
# ifdef NATINT_PACK
#define htov16(x) (endian()?swap16(x):(x))
#define htov32(x) (endian()?swap32(x):(x))
#define hton16(x) (endian()?(x):swap16(x))
#define hton32(x) (endian()?(x):swap32(x))
# endif
#else
#ifdef WORDS_BIGENDIAN
#ifndef ntohs
#define ntohs(x) (x)
#define ntohl(x) (x)
#define htons(x) (x)
#define htonl(x) (x)
#endif
#define ntohf(x) (x)
#define ntohd(x) (x)
#define htonf(x) (x)
#define htond(x) (x)
#define htovs(x) swaps(x)
#define htovl(x) swapl(x)
#define htovf(x) swapf(x)
#define htovd(x) swapd(x)
#define vtohs(x) swaps(x)
#define vtohl(x) swapl(x)
#define vtohf(x) swapf(x)
#define vtohd(x) swapd(x)
# ifdef NATINT_PACK
#define htov16(x) swap16(x)
#define htov32(x) swap32(x)
#define hton16(x) (x)
#define hton32(x) (x)
# endif
#else /* LITTLE ENDIAN */
#ifdef ntohs
#undef ntohs
#undef ntohl
#undef htons
#undef htonl
#endif
#define ntohs(x) swaps(x)
#define ntohl(x) swapl(x)
#define htons(x) swaps(x)
#define htonl(x) swapl(x)
#define ntohf(x) swapf(x)
#define ntohd(x) swapd(x)
#define htonf(x) swapf(x)
#define htond(x) swapd(x)
#define htovs(x) (x)
#define htovl(x) (x)
#define htovf(x) (x)
#define htovd(x) (x)
#define vtohs(x) (x)
#define vtohl(x) (x)
#define vtohf(x) (x)
#define vtohd(x) (x)
# ifdef NATINT_PACK
#define htov16(x) (x)
#define htov32(x) (x)
#define hton16(x) swap16(x)
#define hton32(x) swap32(x)
# endif
#endif
#endif

#ifdef FLOAT_SWAPPER
#define FLOAT_CONVWITH(y)	FLOAT_SWAPPER y;
#define HTONF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = htonf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#define HTOVF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = htovf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#define NTOHF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = ntohf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#define VTOHF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = vtohf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#else
#define FLOAT_CONVWITH(y)
#define HTONF(x,y)	htonf(x)
#define HTOVF(x,y)	htovf(x)
#define NTOHF(x,y)	ntohf(x)
#define VTOHF(x,y)	vtohf(x)
#endif

#ifdef DOUBLE_SWAPPER
#define DOUBLE_CONVWITH(y)	DOUBLE_SWAPPER y;
#define HTOND(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = htond((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#define HTOVD(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = htovd((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#define NTOHD(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = ntohd((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#define VTOHD(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = vtohd((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#else
#define DOUBLE_CONVWITH(y)
#define HTOND(x,y)	htond(x)
#define HTOVD(x,y)	htovd(x)
#define NTOHD(x,y)	ntohd(x)
#define VTOHD(x,y)	vtohd(x)
#endif

unsigned long rb_big2ulong_pack(VALUE x);

static unsigned long
num2i32(VALUE x)
{
    x = rb_to_int(x); /* is nil OK? (should not) */

    if (FIXNUM_P(x)) return FIX2LONG(x);
    if (TYPE(x) == T_BIGNUM) {
	return rb_big2ulong_pack(x);
    }
    rb_raise(rb_eTypeError, "can't convert %s to `integer'", rb_obj_classname(x));
    return 0;			/* not reached */
}

#if SIZEOF_LONG == SIZE32
# define EXTEND32(x)
#else
/* invariant in modulo 1<<31 */
# define EXTEND32(x) do { if (!natint) {(x) = (((1L<<31)-1-(x))^~(~0L<<31));}} while(0)
#endif
#if SIZEOF_SHORT == SIZE16
# define EXTEND16(x)
#else
# define EXTEND16(x) do { if (!natint) {(x) = (short)(((1<<15)-1-(x))^~(~0<<15));}} while(0)
#endif

#ifdef HAVE_LONG_LONG
# define QUAD_SIZE sizeof(LONG_LONG)
#else
# define QUAD_SIZE 8
#endif
static const char toofew[] = "too few arguments";

static void encodes(VALUE,const char*,long,int,int);
static void qpencode(VALUE,VALUE,long);

static unsigned long utf8_to_uv(const char*,long*);

/*
 *  call-seq:
 *     arr.pack ( aTemplateString ) -> aBinaryString
 *
 *  Packs the contents of <i>arr</i> into a binary sequence according to
 *  the directives in <i>aTemplateString</i> (see the table below)
 *  Directives ``A,'' ``a,'' and ``Z'' may be followed by a count,
 *  which gives the width of the resulting field. The remaining
 *  directives also may take a count, indicating the number of array
 *  elements to convert. If the count is an asterisk
 *  (``<code>*</code>''), all remaining array elements will be
 *  converted. Any of the directives ``<code>sSiIlL</code>'' may be
 *  followed by an underscore (``<code>_</code>'') to use the underlying
 *  platform's native size for the specified type; otherwise, they use a
 *  platform-independent size. Spaces are ignored in the template
 *  string. See also <code>String#unpack</code>.
 *
 *     a = [ "a", "b", "c" ]
 *     n = [ 65, 66, 67 ]
 *     a.pack("A3A3A3")   #=> "a  b  c  "
 *     a.pack("a3a3a3")   #=> "a\000\000b\000\000c\000\000"
 *     n.pack("ccc")      #=> "ABC"
 *
 *  Directives for +pack+.
 *
 *   Directive    Meaning
 *   ---------------------------------------------------------------
 *       @     |  Moves to absolute position
 *       A     |  arbitrary binary string (space padded, count is width)
 *       a     |  arbitrary binary string (null padded, count is width)
 *       B     |  Bit string (descending bit order)
 *       b     |  Bit string (ascending bit order)
 *       C     |  Unsigned byte (C unsigned char)
 *       c     |  Byte (C char)
 *       D, d  |  Double-precision float, native format
 *       E     |  Double-precision float, little-endian byte order
 *       e     |  Single-precision float, little-endian byte order
 *       F, f  |  Single-precision float, native format
 *       G     |  Double-precision float, network (big-endian) byte order
 *       g     |  Single-precision float, network (big-endian) byte order
 *       H     |  Hex string (high nibble first)
 *       h     |  Hex string (low nibble first)
 *       I     |  Unsigned integer
 *       i     |  Integer
 *       L     |  Unsigned long
 *       l     |  Long
 *       M     |  Quoted printable, MIME encoding (see RFC2045)
 *       m     |  Base64 encoded string (see RFC 2045, count is width)
 *             |  (if count is 0, no line feed are added, see RFC 4648)
 *       N     |  Long, network (big-endian) byte order
 *       n     |  Short, network (big-endian) byte-order
 *       P     |  Pointer to a structure (fixed-length string)
 *       p     |  Pointer to a null-terminated string
 *       Q, q  |  64-bit number
 *       S     |  Unsigned short
 *       s     |  Short
 *       U     |  UTF-8
 *       u     |  UU-encoded string
 *       V     |  Long, little-endian byte order
 *       v     |  Short, little-endian byte order
 *       w     |  BER-compressed integer\fnm
 *       X     |  Back up a byte
 *       x     |  Null byte
 *       Z     |  Same as ``a'', except that null is added with *
 */

static VALUE
pack_pack(VALUE ary, VALUE fmt)
{
    static const char nul10[] = "\0\0\0\0\0\0\0\0\0\0";
    static const char spc10[] = "          ";
    const char *p, *pend;
    VALUE res, from, associates = 0;
    char type;
    long items, len, idx, plen;
    const char *ptr;
    int enc_info = 1;		/* 0 - BINARY, 1 - US-ASCII, 2 - UTF-8 */
#ifdef NATINT_PACK
    int natint;		/* native integer */
#endif

    StringValue(fmt);
    p = RSTRING_PTR(fmt);
    pend = p + RSTRING_LEN(fmt);
    res = rb_str_buf_new(0);

    items = RARRAY_LEN(ary);
    idx = 0;

#define TOO_FEW (rb_raise(rb_eArgError, toofew), 0)
#define THISFROM (items > 0 ? RARRAY_PTR(ary)[idx] : TOO_FEW)
#define NEXTFROM (items-- > 0 ? RARRAY_PTR(ary)[idx++] : TOO_FEW)

    while (p < pend) {
	if (RSTRING_PTR(fmt) + RSTRING_LEN(fmt) != pend) {
	    rb_raise(rb_eRuntimeError, "format string modified");
	}
	type = *p++;		/* get data type */
#ifdef NATINT_PACK
	natint = 0;
#endif

	if (ISSPACE(type)) continue;
	if (type == '#') {
	    while ((p < pend) && (*p != '\n')) {
		p++;
	    }
	    continue;
	}
        if (*p == '_' || *p == '!') {
	    static const char natstr[] = "sSiIlL";

	    if (strchr(natstr, type)) {
#ifdef NATINT_PACK
		natint = 1;
#endif
		p++;
	    }
	    else {
		rb_raise(rb_eArgError, "'%c' allowed only after types %s", *p, natstr);
	    }
	}
	if (*p == '*') {	/* set data length */
	    len = strchr("@Xxu", type) ? 0
                : strchr("PMm", type) ? 1
                : items;
	    p++;
	}
	else if (ISDIGIT(*p)) {
	    errno = 0;
	    len = STRTOUL(p, (char**)&p, 10);
	    if (errno) {
		rb_raise(rb_eRangeError, "pack length too big");
	    }
	}
	else {
	    len = 1;
	}

	switch (type) {
	  case 'U':
	    /* if encoding is US-ASCII, upgrade to UTF-8 */
	    if (enc_info == 1) enc_info = 2;
	    break;
	  case 'm': case 'M': case 'u':
	    /* keep US-ASCII (do nothing) */
	    break;
	  default:
	    /* fall back to BINARY */
	    enc_info = 0;
	    break;
	}
	switch (type) {
	  case 'A': case 'a': case 'Z':
	  case 'B': case 'b':
	  case 'H': case 'h':
	    from = NEXTFROM;
	    if (NIL_P(from)) {
		ptr = "";
		plen = 0;
	    }
	    else {
		StringValue(from);
		ptr = RSTRING_PTR(from);
		plen = RSTRING_LEN(from);
		OBJ_INFECT(res, from);
	    }

	    if (p[-1] == '*')
		len = plen;

	    switch (type) {
	      case 'a':		/* arbitrary binary string (null padded)  */
	      case 'A':         /* arbitrary binary string (ASCII space padded) */
	      case 'Z':         /* null terminated string  */
		if (plen >= len) {
		    rb_str_buf_cat(res, ptr, len);
		    if (p[-1] == '*' && type == 'Z')
			rb_str_buf_cat(res, nul10, 1);
		}
		else {
		    rb_str_buf_cat(res, ptr, plen);
		    len -= plen;
		    while (len >= 10) {
			rb_str_buf_cat(res, (type == 'A')?spc10:nul10, 10);
			len -= 10;
		    }
		    rb_str_buf_cat(res, (type == 'A')?spc10:nul10, len);
		}
		break;

	      case 'b':		/* bit string (ascending) */
		{
		    int byte = 0;
		    long i, j = 0;

		    if (len > plen) {
			j = (len - plen + 1)/2;
			len = plen;
		    }
		    for (i=0; i++ < len; ptr++) {
			if (*ptr & 1)
			    byte |= 128;
			if (i & 7)
			    byte >>= 1;
			else {
			    char c = byte & 0xff;
			    rb_str_buf_cat(res, &c, 1);
			    byte = 0;
			}
		    }
		    if (len & 7) {
			char c;
			byte >>= 7 - (len & 7);
			c = byte & 0xff;
			rb_str_buf_cat(res, &c, 1);
		    }
		    len = j;
		    goto grow;
		}
		break;

	      case 'B':		/* bit string (descending) */
		{
		    int byte = 0;
		    long i, j = 0;

		    if (len > plen) {
			j = (len - plen + 1)/2;
			len = plen;
		    }
		    for (i=0; i++ < len; ptr++) {
			byte |= *ptr & 1;
			if (i & 7)
			    byte <<= 1;
			else {
			    char c = byte & 0xff;
			    rb_str_buf_cat(res, &c, 1);
			    byte = 0;
			}
		    }
		    if (len & 7) {
			char c;
			byte <<= 7 - (len & 7);
			c = byte & 0xff;
			rb_str_buf_cat(res, &c, 1);
		    }
		    len = j;
		    goto grow;
		}
		break;

	      case 'h':		/* hex string (low nibble first) */
		{
		    int byte = 0;
		    long i, j = 0;

		    if (len > plen) {
			j = (len + 1) / 2 - (plen + 1) / 2;
			len = plen;
		    }
		    for (i=0; i++ < len; ptr++) {
			if (ISALPHA(*ptr))
			    byte |= (((*ptr & 15) + 9) & 15) << 4;
			else
			    byte |= (*ptr & 15) << 4;
			if (i & 1)
			    byte >>= 4;
			else {
			    char c = byte & 0xff;
			    rb_str_buf_cat(res, &c, 1);
			    byte = 0;
			}
		    }
		    if (len & 1) {
			char c = byte & 0xff;
			rb_str_buf_cat(res, &c, 1);
		    }
		    len = j;
		    goto grow;
		}
		break;

	      case 'H':		/* hex string (high nibble first) */
		{
		    int byte = 0;
		    long i, j = 0;

		    if (len > plen) {
			j = (len + 1) / 2 - (plen + 1) / 2;
			len = plen;
		    }
		    for (i=0; i++ < len; ptr++) {
			if (ISALPHA(*ptr))
			    byte |= ((*ptr & 15) + 9) & 15;
			else
			    byte |= *ptr & 15;
			if (i & 1)
			    byte <<= 4;
			else {
			    char c = byte & 0xff;
			    rb_str_buf_cat(res, &c, 1);
			    byte = 0;
			}
		    }
		    if (len & 1) {
			char c = byte & 0xff;
			rb_str_buf_cat(res, &c, 1);
		    }
		    len = j;
		    goto grow;
		}
		break;
	    }
	    break;

	  case 'c':		/* signed char */
	  case 'C':		/* unsigned char */
	    while (len-- > 0) {
		char c;

		from = NEXTFROM;
		c = (char)num2i32(from);
		rb_str_buf_cat(res, &c, sizeof(char));
	    }
	    break;

	  case 's':		/* signed short */
	  case 'S':		/* unsigned short */
	    while (len-- > 0) {
		short s;

		from = NEXTFROM;
		s = (short)num2i32(from);
		rb_str_buf_cat(res, OFF16(&s), NATINT_LEN(short,2));
	    }
	    break;

	  case 'i':		/* signed int */
	  case 'I':		/* unsigned int */
	    while (len-- > 0) {
		int i;

		from = NEXTFROM;
		i = num2i32(from);
		rb_str_buf_cat(res, (char*)&i, sizeof(int));
	    }
	    break;

	  case 'l':		/* signed long */
	  case 'L':		/* unsigned long */
	    while (len-- > 0) {
		long l;

		from = NEXTFROM;
		l = num2i32(from);
		rb_str_buf_cat(res, OFF32(&l), NATINT_LEN(long,4));
	    }
	    break;

	  case 'q':		/* signed quad (64bit) int */
	  case 'Q':		/* unsigned quad (64bit) int */
	    while (len-- > 0) {
		char tmp[QUAD_SIZE];

		from = NEXTFROM;
		rb_quad_pack(tmp, from);
		rb_str_buf_cat(res, (char*)&tmp, QUAD_SIZE);
	    }
	    break;

	  case 'n':		/* unsigned short (network byte-order)  */
	    while (len-- > 0) {
		unsigned short s;

		from = NEXTFROM;
		s = (unsigned short)num2i32(from);
		s = NATINT_HTONS(s);
		rb_str_buf_cat(res, OFF16(&s), NATINT_LEN(short,2));
	    }
	    break;

	  case 'N':		/* unsigned long (network byte-order) */
	    while (len-- > 0) {
		unsigned long l;

		from = NEXTFROM;
		l = num2i32(from);
		l = NATINT_HTONL(l);
		rb_str_buf_cat(res, OFF32(&l), NATINT_LEN(long,4));
	    }
	    break;

	  case 'v':		/* unsigned short (VAX byte-order) */
	    while (len-- > 0) {
		unsigned short s;

		from = NEXTFROM;
		s = (unsigned short)num2i32(from);
		s = NATINT_HTOVS(s);
		rb_str_buf_cat(res, OFF16(&s), NATINT_LEN(short,2));
	    }
	    break;

	  case 'V':		/* unsigned long (VAX byte-order) */
	    while (len-- > 0) {
		unsigned long l;

		from = NEXTFROM;
		l = num2i32(from);
		l = NATINT_HTOVL(l);
		rb_str_buf_cat(res, OFF32(&l), NATINT_LEN(long,4));
	    }
	    break;

	  case 'f':		/* single precision float in native format */
	  case 'F':		/* ditto */
	    while (len-- > 0) {
		float f;

		from = NEXTFROM;
		f = (float)RFLOAT_VALUE(rb_to_float(from));
		rb_str_buf_cat(res, (char*)&f, sizeof(float));
	    }
	    break;

	  case 'e':		/* single precision float in VAX byte-order */
	    while (len-- > 0) {
		float f;
		FLOAT_CONVWITH(ftmp);

		from = NEXTFROM;
		f = (float)RFLOAT_VALUE(rb_to_float(from));
		f = HTOVF(f,ftmp);
		rb_str_buf_cat(res, (char*)&f, sizeof(float));
	    }
	    break;

	  case 'E':		/* double precision float in VAX byte-order */
	    while (len-- > 0) {
		double d;
		DOUBLE_CONVWITH(dtmp);

		from = NEXTFROM;
		d = RFLOAT_VALUE(rb_to_float(from));
		d = HTOVD(d,dtmp);
		rb_str_buf_cat(res, (char*)&d, sizeof(double));
	    }
	    break;

	  case 'd':		/* double precision float in native format */
	  case 'D':		/* ditto */
	    while (len-- > 0) {
		double d;

		from = NEXTFROM;
		d = RFLOAT_VALUE(rb_to_float(from));
		rb_str_buf_cat(res, (char*)&d, sizeof(double));
	    }
	    break;

	  case 'g':		/* single precision float in network byte-order */
	    while (len-- > 0) {
		float f;
		FLOAT_CONVWITH(ftmp);

		from = NEXTFROM;
		f = (float)RFLOAT_VALUE(rb_to_float(from));
		f = HTONF(f,ftmp);
		rb_str_buf_cat(res, (char*)&f, sizeof(float));
	    }
	    break;

	  case 'G':		/* double precision float in network byte-order */
	    while (len-- > 0) {
		double d;
		DOUBLE_CONVWITH(dtmp);

		from = NEXTFROM;
		d = RFLOAT_VALUE(rb_to_float(from));
		d = HTOND(d,dtmp);
		rb_str_buf_cat(res, (char*)&d, sizeof(double));
	    }
	    break;

	  case 'x':		/* null byte */
	  grow:
	    while (len >= 10) {
		rb_str_buf_cat(res, nul10, 10);
		len -= 10;
	    }
	    rb_str_buf_cat(res, nul10, len);
	    break;

	  case 'X':		/* back up byte */
	  shrink:
	    plen = RSTRING_LEN(res);
	    if (plen < len)
		rb_raise(rb_eArgError, "X outside of string");
	    rb_str_set_len(res, plen - len);
	    break;

	  case '@':		/* null fill to absolute position */
	    len -= RSTRING_LEN(res);
	    if (len > 0) goto grow;
	    len = -len;
	    if (len > 0) goto shrink;
	    break;

	  case '%':
	    rb_raise(rb_eArgError, "%% is not supported");
	    break;

	  case 'U':		/* Unicode character */
	    while (len-- > 0) {
		SIGNED_VALUE l;
		char buf[8];
		int le;

		from = NEXTFROM;
		from = rb_to_int(from);
		l = NUM2LONG(from);
		if (l < 0) {
		    rb_raise(rb_eRangeError, "pack(U): value out of range");
		}
		le = rb_uv_to_utf8(buf, l);
		rb_str_buf_cat(res, (char*)buf, le);
	    }
	    break;

	  case 'u':		/* uuencoded string */
	  case 'm':		/* base64 encoded string */
	    from = NEXTFROM;
	    StringValue(from);
	    ptr = RSTRING_PTR(from);
	    plen = RSTRING_LEN(from);

	    if (len == 0 && type == 'm') {
		encodes(res, ptr, plen, type, 0);
		ptr += plen;
		break;
	    }
	    if (len <= 2)
		len = 45;
	    else
		len = len / 3 * 3;
	    while (plen > 0) {
		long todo;

		if (plen > len)
		    todo = len;
		else
		    todo = plen;
		encodes(res, ptr, todo, type, 1);
		plen -= todo;
		ptr += todo;
	    }
	    break;

	  case 'M':		/* quoted-printable encoded string */
	    from = rb_obj_as_string(NEXTFROM);
	    if (len <= 1)
		len = 72;
	    qpencode(res, from, len);
	    break;

	  case 'P':		/* pointer to packed byte string */
	    from = THISFROM;
	    if (!NIL_P(from)) {
		StringValue(from);
		if (RSTRING_LEN(from) < len) {
		    rb_raise(rb_eArgError, "too short buffer for P(%ld for %ld)",
			     RSTRING_LEN(from), len);
		}
	    }
	    len = 1;
	    /* FALL THROUGH */
	  case 'p':		/* pointer to string */
	    while (len-- > 0) {
		char *t;
		from = NEXTFROM;
		if (NIL_P(from)) {
		    t = 0;
		}
		else {
		    t = StringValuePtr(from);
		}
		if (!associates) {
		    associates = rb_ary_new();
		}
		rb_ary_push(associates, from);
		rb_obj_taint(from);
		rb_str_buf_cat(res, (char*)&t, sizeof(char*));
	    }
	    break;

	  case 'w':		/* BER compressed integer  */
	    while (len-- > 0) {
		unsigned long ul;
		VALUE buf = rb_str_new(0, 0);
		char c, *bufs, *bufe;

		from = NEXTFROM;
		if (TYPE(from) == T_BIGNUM) {
		    VALUE big128 = rb_uint2big(128);
		    while (TYPE(from) == T_BIGNUM) {
			from = rb_big_divmod(from, big128);
			c = NUM2INT(RARRAY_PTR(from)[1]) | 0x80; /* mod */
			rb_str_buf_cat(buf, &c, sizeof(char));
			from = RARRAY_PTR(from)[0]; /* div */
		    }
		}

		{
		    long l = NUM2LONG(from);
		    if (l < 0) {
			rb_raise(rb_eArgError, "can't compress negative numbers");
		    }
		    ul = l;
		}

		while (ul) {
		    c = (char)(ul & 0x7f) | 0x80;
		    rb_str_buf_cat(buf, &c, sizeof(char));
		    ul >>=  7;
		}

		if (RSTRING_LEN(buf)) {
		    bufs = RSTRING_PTR(buf);
		    bufe = bufs + RSTRING_LEN(buf) - 1;
		    *bufs &= 0x7f; /* clear continue bit */
		    while (bufs < bufe) { /* reverse */
			c = *bufs;
			*bufs++ = *bufe;
			*bufe-- = c;
		    }
		    rb_str_buf_cat(res, RSTRING_PTR(buf), RSTRING_LEN(buf));
		}
		else {
		    c = 0;
		    rb_str_buf_cat(res, &c, sizeof(char));
		}
	    }
	    break;

	  default:
	    break;
	}
    }

    if (associates) {
	rb_str_associate(res, associates);
    }
    OBJ_INFECT(res, fmt);
    switch (enc_info) {
      case 1:
	ENCODING_CODERANGE_SET(res, rb_usascii_encindex(), ENC_CODERANGE_7BIT);
	break;
      case 2:
	rb_enc_set_index(res, rb_utf8_encindex());
	break;
      default:
	/* do nothing, keep ASCII-8BIT */
	break;
    }
    return res;
}

static const char uu_table[] =
"`!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_";
static const char b64_table[] =
"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void
encodes(VALUE str, const char *s, long len, int type, int tail_lf)
{
    char buff[4096];
    long i = 0;
    const char *trans = type == 'u' ? uu_table : b64_table;
    int padding;

    if (type == 'u') {
	buff[i++] = (char)len + ' ';
	padding = '`';
    }
    else {
	padding = '=';
    }
    while (len >= 3) {
        while (len >= 3 && sizeof(buff)-i >= 4) {
            buff[i++] = trans[077 & (*s >> 2)];
            buff[i++] = trans[077 & (((*s << 4) & 060) | ((s[1] >> 4) & 017))];
            buff[i++] = trans[077 & (((s[1] << 2) & 074) | ((s[2] >> 6) & 03))];
            buff[i++] = trans[077 & s[2]];
            s += 3;
            len -= 3;
        }
        if (sizeof(buff)-i < 4) {
            rb_str_buf_cat(str, buff, i);
            i = 0;
        }
    }

    if (len == 2) {
	buff[i++] = trans[077 & (*s >> 2)];
	buff[i++] = trans[077 & (((*s << 4) & 060) | ((s[1] >> 4) & 017))];
	buff[i++] = trans[077 & (((s[1] << 2) & 074) | (('\0' >> 6) & 03))];
	buff[i++] = padding;
    }
    else if (len == 1) {
	buff[i++] = trans[077 & (*s >> 2)];
	buff[i++] = trans[077 & (((*s << 4) & 060) | (('\0' >> 4) & 017))];
	buff[i++] = padding;
	buff[i++] = padding;
    }
    if (tail_lf) buff[i++] = '\n';
    rb_str_buf_cat(str, buff, i);
}

static const char hex_table[] = "0123456789ABCDEF";

static void
qpencode(VALUE str, VALUE from, long len)
{
    char buff[1024];
    long i = 0, n = 0, prev = EOF;
    unsigned char *s = (unsigned char*)RSTRING_PTR(from);
    unsigned char *send = s + RSTRING_LEN(from);

    while (s < send) {
        if ((*s > 126) ||
	    (*s < 32 && *s != '\n' && *s != '\t') ||
	    (*s == '=')) {
	    buff[i++] = '=';
	    buff[i++] = hex_table[*s >> 4];
	    buff[i++] = hex_table[*s & 0x0f];
            n += 3;
            prev = EOF;
        }
	else if (*s == '\n') {
            if (prev == ' ' || prev == '\t') {
		buff[i++] = '=';
		buff[i++] = *s;
            }
	    buff[i++] = *s;
            n = 0;
            prev = *s;
        }
	else {
	    buff[i++] = *s;
            n++;
            prev = *s;
        }
        if (n > len) {
	    buff[i++] = '=';
	    buff[i++] = '\n';
            n = 0;
            prev = '\n';
        }
	if (i > 1024 - 5) {
	    rb_str_buf_cat(str, buff, i);
	    i = 0;
	}
	s++;
    }
    if (n > 0) {
	buff[i++] = '=';
	buff[i++] = '\n';
    }
    if (i > 0) {
	rb_str_buf_cat(str, buff, i);
    }
}

static inline int
hex2num(char c)
{
    switch (c) {
      case '0': case '1': case '2': case '3': case '4':
      case '5': case '6': case '7': case '8': case '9':
        return c - '0';
      case 'a': case 'b': case 'c':
      case 'd': case 'e': case 'f':
	return c - 'a' + 10;
      case 'A': case 'B': case 'C':
      case 'D': case 'E': case 'F':
	return c - 'A' + 10;
      default:
	return -1;
    }
}

#define PACK_LENGTH_ADJUST_SIZE(sz) do {	\
    tmp = 0;					\
    if (len > (long)((send-s)/sz)) {		\
        if (!star) {				\
	    tmp = len-(send-s)/sz;		\
        }					\
	len = (send-s)/sz;			\
    }						\
} while (0)

#ifdef NATINT_PACK
#define PACK_LENGTH_ADJUST(type,sz) do {	\
    int t__len = NATINT_LEN(type,(sz));		\
    PACK_LENGTH_ADJUST_SIZE(t__len);		\
} while (0)
#else
#define PACK_LENGTH_ADJUST(type,sz) 		\
    PACK_LENGTH_ADJUST_SIZE(sizeof(type))
#endif

#define PACK_ITEM_ADJUST() while (tmp--) rb_ary_push(ary, Qnil)

static VALUE
infected_str_new(const char *ptr, long len, VALUE str)
{
    VALUE s = rb_str_new(ptr, len);

    OBJ_INFECT(s, str);
    return s;
}

/*
 *  call-seq:
 *     str.unpack(format)   => anArray
 *
 *  Decodes <i>str</i> (which may contain binary data) according to the
 *  format string, returning an array of each value extracted. The
 *  format string consists of a sequence of single-character directives,
 *  summarized in the table at the end of this entry.
 *  Each directive may be followed
 *  by a number, indicating the number of times to repeat with this
 *  directive. An asterisk (``<code>*</code>'') will use up all
 *  remaining elements. The directives <code>sSiIlL</code> may each be
 *  followed by an underscore (``<code>_</code>'') to use the underlying
 *  platform's native size for the specified type; otherwise, it uses a
 *  platform-independent consistent size. Spaces are ignored in the
 *  format string. See also <code>Array#pack</code>.
 *
 *     "abc \0\0abc \0\0".unpack('A6Z6')   #=> ["abc", "abc "]
 *     "abc \0\0".unpack('a3a3')           #=> ["abc", " \000\000"]
 *     "abc \0abc \0".unpack('Z*Z*')       #=> ["abc ", "abc "]
 *     "aa".unpack('b8B8')                 #=> ["10000110", "01100001"]
 *     "aaa".unpack('h2H2c')               #=> ["16", "61", 97]
 *     "\xfe\xff\xfe\xff".unpack('sS')     #=> [-2, 65534]
 *     "now=20is".unpack('M*')             #=> ["now is"]
 *     "whole".unpack('xax2aX2aX1aX2a')    #=> ["h", "e", "l", "l", "o"]
 *
 *  This table summarizes the various formats and the Ruby classes
 *  returned by each.
 *
 *     Format | Returns | Function
 *     -------+---------+-----------------------------------------
 *       A    | String  | arbitrary binary string with trailing
 *            |         | nulls and ASCII spaces removed
 *     -------+---------+-----------------------------------------
 *       a    | String  | arbitrary binary string
 *     -------+---------+-----------------------------------------
 *       B    | String  | extract bits from each character (msb first)
 *     -------+---------+-----------------------------------------
 *       b    | String  | extract bits from each character (lsb first)
 *     -------+---------+-----------------------------------------
 *       C    | Fixnum  | extract a byte (C char) as an unsigned integer
 *     -------+---------+-----------------------------------------
 *       c    | Fixnum  | extract a byte (C char) as an integer
 *     -------+---------+-----------------------------------------
 *       d,D  | Float   | treat sizeof(double) characters as
 *            |         | a native double
 *     -------+---------+-----------------------------------------
 *       E    | Float   | treat sizeof(double) characters as
 *            |         | a double in little-endian byte order
 *     -------+---------+-----------------------------------------
 *       e    | Float   | treat sizeof(float) characters as
 *            |         | a float in little-endian byte order
 *     -------+---------+-----------------------------------------
 *       f,F  | Float   | treat sizeof(float) characters as
 *            |         | a native float
 *     -------+---------+-----------------------------------------
 *       G    | Float   | treat sizeof(double) characters as
 *            |         | a double in network byte order
 *     -------+---------+-----------------------------------------
 *       g    | Float   | treat sizeof(float) characters as a
 *            |         | float in network byte order
 *     -------+---------+-----------------------------------------
 *       H    | String  | extract hex nibbles from each character
 *            |         | (most significant first)
 *     -------+---------+-----------------------------------------
 *       h    | String  | extract hex nibbles from each character
 *            |         | (least significant first)
 *     -------+---------+-----------------------------------------
 *       I    | Integer | treat sizeof(int) (modified by _)
 *            |         | successive characters as an unsigned
 *            |         | native integer
 *     -------+---------+-----------------------------------------
 *       i    | Integer | treat sizeof(int) (modified by _)
 *            |         | successive characters as a signed
 *            |         | native integer
 *     -------+---------+-----------------------------------------
 *       L    | Integer | treat four (modified by _) successive
 *            |         | characters as an unsigned native
 *            |         | long integer
 *     -------+---------+-----------------------------------------
 *       l    | Integer | treat four (modified by _) successive
 *            |         | characters as a signed native
 *            |         | long integer
 *     -------+---------+-----------------------------------------
 *       M    | String  | quoted-printable
 *     -------+---------+-----------------------------------------
 *       m    | String  | base64-encoded (RFC 2045) (default)
 *            |         | base64-encoded (RFC 4648) if followed by 0
 *     -------+---------+-----------------------------------------
 *       N    | Integer | treat four characters as an unsigned
 *            |         | long in network byte order
 *     -------+---------+-----------------------------------------
 *       n    | Fixnum  | treat two characters as an unsigned
 *            |         | short in network byte order
 *     -------+---------+-----------------------------------------
 *       P    | String  | treat sizeof(char *) characters as a
 *            |         | pointer, and  return \emph{len} characters
 *            |         | from the referenced location
 *     -------+---------+-----------------------------------------
 *       p    | String  | treat sizeof(char *) characters as a
 *            |         | pointer to a  null-terminated string
 *     -------+---------+-----------------------------------------
 *       Q    | Integer | treat 8 characters as an unsigned
 *            |         | quad word (64 bits)
 *     -------+---------+-----------------------------------------
 *       q    | Integer | treat 8 characters as a signed
 *            |         | quad word (64 bits)
 *     -------+---------+-----------------------------------------
 *       S    | Fixnum  | treat two (different if _ used)
 *            |         | successive characters as an unsigned
 *            |         | short in native byte order
 *     -------+---------+-----------------------------------------
 *       s    | Fixnum  | Treat two (different if _ used)
 *            |         | successive characters as a signed short
 *            |         | in native byte order
 *     -------+---------+-----------------------------------------
 *       U    | Integer | UTF-8 characters as unsigned integers
 *     -------+---------+-----------------------------------------
 *       u    | String  | UU-encoded
 *     -------+---------+-----------------------------------------
 *       V    | Fixnum  | treat four characters as an unsigned
 *            |         | long in little-endian byte order
 *     -------+---------+-----------------------------------------
 *       v    | Fixnum  | treat two characters as an unsigned
 *            |         | short in little-endian byte order
 *     -------+---------+-----------------------------------------
 *       w    | Integer | BER-compressed integer (see Array.pack)
 *     -------+---------+-----------------------------------------
 *       X    | ---     | skip backward one character
 *     -------+---------+-----------------------------------------
 *       x    | ---     | skip forward one character
 *     -------+---------+-----------------------------------------
 *       Z    | String  | with trailing nulls removed
 *            |         | upto first null with *
 *     -------+---------+-----------------------------------------
 *       @    | ---     | skip to the offset given by the
 *            |         | length argument
 *     -------+---------+-----------------------------------------
 */

static VALUE
pack_unpack(VALUE str, VALUE fmt)
{
    static const char hexdigits[] = "0123456789abcdef";
    char *s, *send;
    char *p, *pend;
    VALUE ary;
    char type;
    long len;
    int tmp, star;
#ifdef NATINT_PACK
    int natint;			/* native integer */
#endif
    int block_p = rb_block_given_p();
#define UNPACK_PUSH(item) do {\
	VALUE item_val = (item);\
	if (block_p) {\
	    rb_yield(item_val);\
	}\
	else {\
	    rb_ary_push(ary, item_val);\
	}\
    } while (0)

    StringValue(str);
    StringValue(fmt);
    s = RSTRING_PTR(str);
    send = s + RSTRING_LEN(str);
    p = RSTRING_PTR(fmt);
    pend = p + RSTRING_LEN(fmt);

    ary = block_p ? Qnil : rb_ary_new();
    while (p < pend) {
	type = *p++;
#ifdef NATINT_PACK
	natint = 0;
#endif

	if (ISSPACE(type)) continue;
	if (type == '#') {
	    while ((p < pend) && (*p != '\n')) {
		p++;
	    }
	    continue;
	}
	star = 0;
	if (*p == '_' || *p == '!') {
	    static const char natstr[] = "sSiIlL";

	    if (strchr(natstr, type)) {
#ifdef NATINT_PACK
		natint = 1;
#endif
		p++;
	    }
	    else {
		rb_raise(rb_eArgError, "'%c' allowed only after types %s", *p, natstr);
	    }
	}
	if (p >= pend)
	    len = 1;
	else if (*p == '*') {
	    star = 1;
	    len = send - s;
	    p++;
	}
	else if (ISDIGIT(*p)) {
	    errno = 0;
	    len = STRTOUL(p, (char**)&p, 10);
	    if (errno) {
		rb_raise(rb_eRangeError, "pack length too big");
	    }
	}
	else {
	    len = (type != '@');
	}

	switch (type) {
	  case '%':
	    rb_raise(rb_eArgError, "%% is not supported");
	    break;

	  case 'A':
	    if (len > send - s) len = send - s;
	    {
		long end = len;
		char *t = s + len - 1;

		while (t >= s) {
		    if (*t != ' ' && *t != '\0') break;
		    t--; len--;
		}
		UNPACK_PUSH(infected_str_new(s, len, str));
		s += end;
	    }
	    break;

	  case 'Z':
	    {
		char *t = s;

		if (len > send-s) len = send-s;
		while (t < s+len && *t) t++;
		UNPACK_PUSH(infected_str_new(s, t-s, str));
		if (t < send) t++;
		s = star ? t : s+len;
	    }
	    break;

	  case 'a':
	    if (len > send - s) len = send - s;
	    UNPACK_PUSH(infected_str_new(s, len, str));
	    s += len;
	    break;

	  case 'b':
	    {
		VALUE bitstr;
		char *t;
		int bits;
		long i;

		if (p[-1] == '*' || len > (send - s) * 8)
		    len = (send - s) * 8;
		bits = 0;
		UNPACK_PUSH(bitstr = rb_str_new(0, len));
		t = RSTRING_PTR(bitstr);
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
		char *t;
		int bits;
		long i;

		if (p[-1] == '*' || len > (send - s) * 8)
		    len = (send - s) * 8;
		bits = 0;
		UNPACK_PUSH(bitstr = rb_str_new(0, len));
		t = RSTRING_PTR(bitstr);
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
		char *t;
		int bits;
		long i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		bits = 0;
		UNPACK_PUSH(bitstr = rb_str_new(0, len));
		t = RSTRING_PTR(bitstr);
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
		char *t;
		int bits;
		long i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		bits = 0;
		UNPACK_PUSH(bitstr = rb_str_new(0, len));
		t = RSTRING_PTR(bitstr);
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
	    PACK_LENGTH_ADJUST(char,sizeof(char));
	    while (len-- > 0) {
                int c = *s++;
                if (c > (char)127) c-=256;
		UNPACK_PUSH(INT2FIX(c));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'C':
	    PACK_LENGTH_ADJUST(unsigned char,sizeof(unsigned char));
	    while (len-- > 0) {
		unsigned char c = *s++;
		UNPACK_PUSH(INT2FIX(c));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 's':
	    PACK_LENGTH_ADJUST(short,2);
	    while (len-- > 0) {
		short tmp = 0;
		memcpy(OFF16(&tmp), s, NATINT_LEN(short,2));
		EXTEND16(tmp);
		s += NATINT_LEN(short,2);
		UNPACK_PUSH(INT2FIX(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'S':
	    PACK_LENGTH_ADJUST(unsigned short,2);
	    while (len-- > 0) {
		unsigned short tmp = 0;
		memcpy(OFF16(&tmp), s, NATINT_LEN(unsigned short,2));
		s += NATINT_LEN(unsigned short,2);
		UNPACK_PUSH(INT2FIX(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'i':
	    PACK_LENGTH_ADJUST(int,sizeof(int));
	    while (len-- > 0) {
		int tmp;
		memcpy(&tmp, s, sizeof(int));
		s += sizeof(int);
		UNPACK_PUSH(INT2NUM(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'I':
	    PACK_LENGTH_ADJUST(unsigned int,sizeof(unsigned int));
	    while (len-- > 0) {
		unsigned int tmp;
		memcpy(&tmp, s, sizeof(unsigned int));
		s += sizeof(unsigned int);
		UNPACK_PUSH(UINT2NUM(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'l':
	    PACK_LENGTH_ADJUST(long,4);
	    while (len-- > 0) {
		long tmp = 0;
		memcpy(OFF32(&tmp), s, NATINT_LEN(long,4));
		EXTEND32(tmp);
		s += NATINT_LEN(long,4);
		UNPACK_PUSH(LONG2NUM(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;
	  case 'L':
	    PACK_LENGTH_ADJUST(unsigned long,4);
	    while (len-- > 0) {
		unsigned long tmp = 0;
		memcpy(OFF32(&tmp), s, NATINT_LEN(unsigned long,4));
		s += NATINT_LEN(unsigned long,4);
		UNPACK_PUSH(ULONG2NUM(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'q':
	    PACK_LENGTH_ADJUST_SIZE(QUAD_SIZE);
	    while (len-- > 0) {
		char *tmp = (char*)s;
		s += QUAD_SIZE;
		UNPACK_PUSH(rb_quad_unpack(tmp, 1));
	    }
	    PACK_ITEM_ADJUST();
	    break;
	  case 'Q':
	    PACK_LENGTH_ADJUST_SIZE(QUAD_SIZE);
	    while (len-- > 0) {
		char *tmp = (char*)s;
		s += QUAD_SIZE;
		UNPACK_PUSH(rb_quad_unpack(tmp, 0));
	    }
	    break;

	  case 'n':
	    PACK_LENGTH_ADJUST(unsigned short,2);
	    while (len-- > 0) {
		unsigned short tmp = 0;
		memcpy(OFF16B(&tmp), s, NATINT_LEN(unsigned short,2));
		s += NATINT_LEN(unsigned short,2);
		UNPACK_PUSH(UINT2NUM(ntohs(tmp)));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'N':
	    PACK_LENGTH_ADJUST(unsigned long,4);
	    while (len-- > 0) {
		unsigned long tmp = 0;
		memcpy(OFF32B(&tmp), s, NATINT_LEN(unsigned long,4));
		s += NATINT_LEN(unsigned long,4);
		UNPACK_PUSH(ULONG2NUM(ntohl(tmp)));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'v':
	    PACK_LENGTH_ADJUST(unsigned short,2);
	    while (len-- > 0) {
		unsigned short tmp = 0;
		memcpy(&tmp, s, NATINT_LEN(unsigned short,2));
		s += NATINT_LEN(unsigned short,2);
		UNPACK_PUSH(UINT2NUM(vtohs(tmp)));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'V':
	    PACK_LENGTH_ADJUST(unsigned long,4);
	    while (len-- > 0) {
		unsigned long tmp = 0;
		memcpy(&tmp, s, NATINT_LEN(long,4));
		s += NATINT_LEN(long,4);
		UNPACK_PUSH(ULONG2NUM(vtohl(tmp)));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'f':
	  case 'F':
	    PACK_LENGTH_ADJUST(float,sizeof(float));
	    while (len-- > 0) {
		float tmp;
		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		UNPACK_PUSH(DBL2NUM((double)tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'e':
	    PACK_LENGTH_ADJUST(float,sizeof(float));
	    while (len-- > 0) {
	        float tmp;
		FLOAT_CONVWITH(ftmp);

		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		tmp = VTOHF(tmp,ftmp);
		UNPACK_PUSH(DBL2NUM((double)tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'E':
	    PACK_LENGTH_ADJUST(double,sizeof(double));
	    while (len-- > 0) {
		double tmp;
		DOUBLE_CONVWITH(dtmp);

		memcpy(&tmp, s, sizeof(double));
		s += sizeof(double);
		tmp = VTOHD(tmp,dtmp);
		UNPACK_PUSH(DBL2NUM(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'D':
	  case 'd':
	    PACK_LENGTH_ADJUST(double,sizeof(double));
	    while (len-- > 0) {
		double tmp;
		memcpy(&tmp, s, sizeof(double));
		s += sizeof(double);
		UNPACK_PUSH(DBL2NUM(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'g':
	    PACK_LENGTH_ADJUST(float,sizeof(float));
	    while (len-- > 0) {
	        float tmp;
		FLOAT_CONVWITH(ftmp;)

		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		tmp = NTOHF(tmp,ftmp);
		UNPACK_PUSH(DBL2NUM((double)tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'G':
	    PACK_LENGTH_ADJUST(double,sizeof(double));
	    while (len-- > 0) {
		double tmp;
		DOUBLE_CONVWITH(dtmp);

		memcpy(&tmp, s, sizeof(double));
		s += sizeof(double);
		tmp = NTOHD(tmp,dtmp);
		UNPACK_PUSH(DBL2NUM(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'U':
	    if (len > send - s) len = send - s;
	    while (len > 0 && s < send) {
		long alen = send - s;
		unsigned long l;

		l = utf8_to_uv(s, &alen);
		s += alen; len--;
		UNPACK_PUSH(ULONG2NUM(l));
	    }
	    break;

	  case 'u':
	    {
		VALUE buf = infected_str_new(0, (send - s)*3/4, str);
		char *ptr = RSTRING_PTR(buf);
		long total = 0;

		while (s < send && *s > ' ' && *s < 'a') {
		    long a,b,c,d;
		    char hunk[4];

		    hunk[3] = '\0';
		    len = (*s++ - ' ') & 077;
		    total += len;
		    if (total > RSTRING_LEN(buf)) {
			len -= total - RSTRING_LEN(buf);
			total = RSTRING_LEN(buf);
		    }

		    while (len > 0) {
			long mlen = len > 3 ? 3 : len;

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
			hunk[0] = (char)(a << 2 | b >> 4);
			hunk[1] = (char)(b << 4 | c >> 2);
			hunk[2] = (char)(c << 6 | d);
			memcpy(ptr, hunk, mlen);
			ptr += mlen;
			len -= mlen;
		    }
		    if (*s == '\r') s++;
		    if (*s == '\n') s++;
		    else if (s < send && (s+1 == send || s[1] == '\n'))
			s += 2;	/* possible checksum byte */
		}

		rb_str_set_len(buf, total);
		UNPACK_PUSH(buf);
	    }
	    break;

	  case 'm':
	    {
		VALUE buf = infected_str_new(0, (send - s)*3/4, str);
		char *ptr = RSTRING_PTR(buf);
		int a = -1,b = -1,c = 0,d = 0;
		static signed char b64_xtable[256];

		if (b64_xtable['/'] <= 0) {
		    int i;

		    for (i = 0; i < 256; i++) {
			b64_xtable[i] = -1;
		    }
		    for (i = 0; i < 64; i++) {
			b64_xtable[(unsigned char)b64_table[i]] = i;
		    }
		}
		if (len == 0) {
		    while (s < send) {
			a = b = c = d = -1;
			a = b64_xtable[(unsigned char)*s++];
			if (s >= send || a == -1) rb_raise(rb_eArgError, "invalid base64");
			b = b64_xtable[(unsigned char)*s++];
			if (s >= send || b == -1) rb_raise(rb_eArgError, "invalid base64");
			if (*s == '=') {
			    if (s + 2 == send && *(s + 1) == '=') break;
			    rb_raise(rb_eArgError, "invalid base64");
			}
			c = b64_xtable[(unsigned char)*s++];
			if (s >= send || c == -1) rb_raise(rb_eArgError, "invalid base64");
			if (s + 1 == send && *s == '=') break;
			d = b64_xtable[(unsigned char)*s++];
			if (d == -1) rb_raise(rb_eArgError, "invalid base64");
			*ptr++ = a << 2 | b >> 4;
			*ptr++ = b << 4 | c >> 2;
			*ptr++ = c << 6 | d;
		    }
		    if (c == -1) {
			*ptr++ = a << 2 | b >> 4;
			if (b & 0xf) rb_raise(rb_eArgError, "invalid base64");
		    }
		    else if (d == -1) {
			*ptr++ = a << 2 | b >> 4;
			*ptr++ = b << 4 | c >> 2;
			if (c & 0x3) rb_raise(rb_eArgError, "invalid base64");
		    }
		}
		else {
		    while (s < send) {
			a = b = c = d = -1;
			while ((a = b64_xtable[(unsigned char)*s]) == -1 && s < send) {s++;}
			if (s >= send) break;
			s++;
			while ((b = b64_xtable[(unsigned char)*s]) == -1 && s < send) {s++;}
			if (s >= send) break;
			s++;
			while ((c = b64_xtable[(unsigned char)*s]) == -1 && s < send) {if (*s == '=') break; s++;}
			if (*s == '=' || s >= send) break;
			s++;
			while ((d = b64_xtable[(unsigned char)*s]) == -1 && s < send) {if (*s == '=') break; s++;}
			if (*s == '=' || s >= send) break;
			s++;
			*ptr++ = a << 2 | b >> 4;
			*ptr++ = b << 4 | c >> 2;
			*ptr++ = c << 6 | d;
		    }
		    if (a != -1 && b != -1) {
			if (c == -1 && *s == '=')
			    *ptr++ = a << 2 | b >> 4;
			else if (c != -1 && *s == '=') {
			    *ptr++ = a << 2 | b >> 4;
			    *ptr++ = b << 4 | c >> 2;
			}
		    }
		}
		rb_str_set_len(buf, ptr - RSTRING_PTR(buf));
		UNPACK_PUSH(buf);
	    }
	    break;

	  case 'M':
	    {
		VALUE buf = infected_str_new(0, send - s, str);
		char *ptr = RSTRING_PTR(buf);
		int c1, c2;

		while (s < send) {
		    if (*s == '=') {
			if (++s == send) break;
                       if (s+1 < send && *s == '\r' && *(s+1) == '\n')
                         s++;
			if (*s != '\n') {
			    if ((c1 = hex2num(*s)) == -1) break;
			    if (++s == send) break;
			    if ((c2 = hex2num(*s)) == -1) break;
			    *ptr++ = c1 << 4 | c2;
			}
		    }
		    else {
			*ptr++ = *s;
		    }
		    s++;
		}
		rb_str_set_len(buf, ptr - RSTRING_PTR(buf));
		ENCODING_CODERANGE_SET(buf, rb_usascii_encindex(), ENC_CODERANGE_7BIT);
		UNPACK_PUSH(buf);
	    }
	    break;

	  case '@':
	    if (len > RSTRING_LEN(str))
		rb_raise(rb_eArgError, "@ outside of string");
	    s = RSTRING_PTR(str) + len;
	    break;

	  case 'X':
	    if (len > s - RSTRING_PTR(str))
		rb_raise(rb_eArgError, "X outside of string");
	    s -= len;
	    break;

	  case 'x':
	    if (len > send - s)
		rb_raise(rb_eArgError, "x outside of string");
	    s += len;
	    break;

	  case 'P':
	    if (sizeof(char *) <= send - s) {
		VALUE tmp = Qnil;
		char *t;

		memcpy(&t, s, sizeof(char *));
		s += sizeof(char *);

		if (t) {
		    VALUE a, *p, *pend;

		    if (!(a = rb_str_associated(str))) {
			rb_raise(rb_eArgError, "no associated pointer");
		    }
		    p = RARRAY_PTR(a);
		    pend = p + RARRAY_LEN(a);
		    while (p < pend) {
			if (TYPE(*p) == T_STRING && RSTRING_PTR(*p) == t) {
			    if (len < RSTRING_LEN(*p)) {
				tmp = rb_tainted_str_new(t, len);
				rb_str_associate(tmp, a);
			    }
			    else {
				tmp = *p;
			    }
			    break;
			}
			p++;
		    }
		    if (p == pend) {
			rb_raise(rb_eArgError, "non associated pointer");
		    }
		}
		UNPACK_PUSH(tmp);
	    }
	    break;

	  case 'p':
	    if (len > (long)((send - s) / sizeof(char *)))
		len = (send - s) / sizeof(char *);
	    while (len-- > 0) {
		if (send - s < sizeof(char *))
		    break;
		else {
		    VALUE tmp = Qnil;
		    char *t;

		    memcpy(&t, s, sizeof(char *));
		    s += sizeof(char *);

		    if (t) {
			VALUE a, *p, *pend;

			if (!(a = rb_str_associated(str))) {
			    rb_raise(rb_eArgError, "no associated pointer");
			}
			p = RARRAY_PTR(a);
			pend = p + RARRAY_LEN(a);
			while (p < pend) {
			    if (TYPE(*p) == T_STRING && RSTRING_PTR(*p) == t) {
				tmp = *p;
				break;
			    }
			    p++;
			}
			if (p == pend) {
			    rb_raise(rb_eArgError, "non associated pointer");
			}
		    }
		    UNPACK_PUSH(tmp);
		}
	    }
	    break;

	  case 'w':
	    {
		unsigned long ul = 0;
		unsigned long ulmask = 0xfeUL << ((sizeof(unsigned long) - 1) * 8);

		while (len > 0 && s < send) {
		    ul <<= 7;
		    ul |= (*s & 0x7f);
		    if (!(*s++ & 0x80)) {
			UNPACK_PUSH(ULONG2NUM(ul));
			len--;
			ul = 0;
		    }
		    else if (ul & ulmask) {
			VALUE big = rb_uint2big(ul);
			VALUE big128 = rb_uint2big(128);
			while (s < send) {
			    big = rb_big_mul(big, big128);
			    big = rb_big_plus(big, rb_uint2big(*s & 0x7f));
			    if (!(*s++ & 0x80)) {
				UNPACK_PUSH(big);
				len--;
				ul = 0;
				break;
			    }
			}
		    }
		}
	    }
	    break;

	  default:
	    break;
	}
    }

    return ary;
}

#define BYTEWIDTH 8

int
rb_uv_to_utf8(char buf[6], unsigned long uv)
{
    if (uv <= 0x7f) {
	buf[0] = (char)uv;
	return 1;
    }
    if (uv <= 0x7ff) {
	buf[0] = (char)((uv>>6)&0xff)|0xc0;
	buf[1] = (char)(uv&0x3f)|0x80;
	return 2;
    }
    if (uv <= 0xffff) {
	buf[0] = (char)((uv>>12)&0xff)|0xe0;
	buf[1] = (char)((uv>>6)&0x3f)|0x80;
	buf[2] = (char)(uv&0x3f)|0x80;
	return 3;
    }
    if (uv <= 0x1fffff) {
	buf[0] = (char)((uv>>18)&0xff)|0xf0;
	buf[1] = (char)((uv>>12)&0x3f)|0x80;
	buf[2] = (char)((uv>>6)&0x3f)|0x80;
	buf[3] = (char)(uv&0x3f)|0x80;
	return 4;
    }
    if (uv <= 0x3ffffff) {
	buf[0] = (char)((uv>>24)&0xff)|0xf8;
	buf[1] = (char)((uv>>18)&0x3f)|0x80;
	buf[2] = (char)((uv>>12)&0x3f)|0x80;
	buf[3] = (char)((uv>>6)&0x3f)|0x80;
	buf[4] = (char)(uv&0x3f)|0x80;
	return 5;
    }
    if (uv <= 0x7fffffff) {
	buf[0] = (char)((uv>>30)&0xff)|0xfc;
	buf[1] = (char)((uv>>24)&0x3f)|0x80;
	buf[2] = (char)((uv>>18)&0x3f)|0x80;
	buf[3] = (char)((uv>>12)&0x3f)|0x80;
	buf[4] = (char)((uv>>6)&0x3f)|0x80;
	buf[5] = (char)(uv&0x3f)|0x80;
	return 6;
    }
    rb_raise(rb_eRangeError, "pack(U): value out of range");
}

static const unsigned long utf8_limits[] = {
    0x0,			/* 1 */
    0x80,			/* 2 */
    0x800,			/* 3 */
    0x10000,			/* 4 */
    0x200000,			/* 5 */
    0x4000000,			/* 6 */
    0x80000000,			/* 7 */
};

static unsigned long
utf8_to_uv(const char *p, long *lenp)
{
    int c = *p++ & 0xff;
    unsigned long uv = c;
    long n;

    if (!(uv & 0x80)) {
	*lenp = 1;
        return uv;
    }
    if (!(uv & 0x40)) {
	*lenp = 1;
	rb_raise(rb_eArgError, "malformed UTF-8 character");
    }

    if      (!(uv & 0x20)) { n = 2; uv &= 0x1f; }
    else if (!(uv & 0x10)) { n = 3; uv &= 0x0f; }
    else if (!(uv & 0x08)) { n = 4; uv &= 0x07; }
    else if (!(uv & 0x04)) { n = 5; uv &= 0x03; }
    else if (!(uv & 0x02)) { n = 6; uv &= 0x01; }
    else {
	*lenp = 1;
	rb_raise(rb_eArgError, "malformed UTF-8 character");
    }
    if (n > *lenp) {
	rb_raise(rb_eArgError, "malformed UTF-8 character (expected %ld bytes, given %ld bytes)",
		 n, *lenp);
    }
    *lenp = n--;
    if (n != 0) {
	while (n--) {
	    c = *p++ & 0xff;
	    if ((c & 0xc0) != 0x80) {
		*lenp -= n + 1;
		rb_raise(rb_eArgError, "malformed UTF-8 character");
	    }
	    else {
		c &= 0x3f;
		uv = uv << 6 | c;
	    }
	}
    }
    n = *lenp - 1;
    if (uv < utf8_limits[n]) {
	rb_raise(rb_eArgError, "redundant UTF-8 sequence");
    }
    return uv;
}

void
Init_pack(void)
{
    rb_define_method(rb_cArray, "pack", pack_pack, 1);
    rb_define_method(rb_cString, "unpack", pack_unpack, 1);
}
