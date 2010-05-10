/**********************************************************************

  pack.c -

  $Author$
  $Date$
  created at: Thu Feb 10 15:17:05 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include <sys/types.h>
#include <ctype.h>

#define GCC_VERSION_SINCE(major, minor, patchlevel) \
  (defined(__GNUC__) && !defined(__INTEL_COMPILER) && \
   ((__GNUC__ > (major)) ||  \
    (__GNUC__ == (major) && __GNUC_MINOR__ > (minor)) || \
    (__GNUC__ == (major) && __GNUC_MINOR__ == (minor) && __GNUC_PATCHLEVEL__ >= (patchlevel))))

#define SIZE16 2
#define SIZE32 4

#if SIZEOF_SHORT != 2 || SIZEOF_LONG != 4
# define NATINT_PACK
#endif

#ifdef DYNAMIC_ENDIAN
 /* for universal binary of NEXTSTEP and MacOS X */
 /* useless since autoconf 2.63? */
 static int
 is_bigendian(void)
 {
     static int init = 0;
     static int endian_value;
     char *p;

     if (init) return endian_value;
     init = 1;
     p = (char*)&init;
     return endian_value = p[0]?0:1;
 }
# define BIGENDIAN_P() (is_bigendian())
#elif defined(WORDS_BIGENDIAN)
# define BIGENDIAN_P() 1
#else
# define BIGENDIAN_P() 0
#endif

#ifdef NATINT_PACK
# define NATINT_LEN(type,len) (natint?(int)sizeof(type):(int)(len))
#else
# define NATINT_LEN(type,len) ((int)sizeof(type))
#endif

#if SIZEOF_LONG == 8
# define INT64toNUM(x) LONG2NUM(x)
# define UINT64toNUM(x) ULONG2NUM(x)
#elif defined(HAVE_LONG_LONG) && SIZEOF_LONG_LONG == 8
# define INT64toNUM(x) LL2NUM(x)
# define UINT64toNUM(x) ULL2NUM(x)
#endif

#define define_swapx(x, xtype)		\
static xtype				\
TOKEN_PASTE(swap,x)(z)			\
    xtype z;				\
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
    free(t);				\
    free(zp);				\
    return r;				\
}

#if GCC_VERSION_SINCE(4,3,0)
# define swap32(x) __builtin_bswap32(x)
# define swap64(x) __builtin_bswap64(x)
#endif

#ifndef swap16
# define swap16(x)	((((x)&0xFF)<<8) | (((x)>>8)&0xFF))
#endif

#ifndef swap32
# define swap32(x)      ((((x)&0xFF)<<24)       \
			|(((x)>>24)&0xFF)	\
			|(((x)&0x0000FF00)<<8)	\
			|(((x)&0x00FF0000)>>8)	)
#endif

#ifndef swap64
# ifdef HAVE_INT64_T
#  define byte_in_64bit(n) ((uint64_t)0xff << (n))
#  define swap64(x)       ((((x)&byte_in_64bit(0))<<56)         \
                           |(((x)>>56)&0xFF)                    \
                           |(((x)&byte_in_64bit(8))<<40)        \
                           |(((x)&byte_in_64bit(48))>>40)       \
                           |(((x)&byte_in_64bit(16))<<24)       \
                           |(((x)&byte_in_64bit(40))>>24)       \
                           |(((x)&byte_in_64bit(24))<<8)        \
                           |(((x)&byte_in_64bit(32))>>8))
# endif
#endif

#if SIZEOF_SHORT == 2
# define swaps(x)       swap16(x)
#elif SIZEOF_SHORT == 4
# define swaps(x)       swap32(x)
#else
  define_swapx(s,short)
#endif

#if SIZEOF_INT == 2
# define swapi(x)       swap16(x)
#elif SIZEOF_INT == 4
# define swapi(x)       swap32(x)
#else
  define_swapx(i,int)
#endif

#if SIZEOF_LONG == 4
# define swapl(x)       swap32(x)
#elif SIZEOF_LONG == 8
# define swapl(x)       swap64(x)
#else
  define_swapx(l,long)
#endif

#ifdef HAVE_LONG_LONG
# if SIZEOF_LONG_LONG == 8
#  define swapll(x)        swap64(x)
# else
   define_swapx(ll,LONG_LONG)
# endif
#endif

#if SIZEOF_FLOAT == 4
# ifdef HAVE_UINT32_T
#  define swapf(x)     swap32(x)
#  define FLOAT_SWAPPER        uint32_t
# else /* SIZEOF_FLOAT == 4 but undivide by known size of int */
   define_swapx(f,float)
# endif
#else	/* SIZEOF_FLOAT != 4 */
  define_swapx(f,float)
#endif	/* #if SIZEOF_FLOAT == 4 */

#if SIZEOF_DOUBLE == 8
# ifdef HAVE_UINT64_T  /* SIZEOF_DOUBLE == 8 == SIZEOF_UINT64_T */
#  define swapd(x)     swap64(x)
#  define DOUBLE_SWAPPER       uint64_t
# else
#  if SIZEOF_LONG == 4 /* SIZEOF_DOUBLE == 8 && 4 == SIZEOF_LONG */
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
#  elif SIZEOF_SHORT == 4      /* SIZEOF_DOUBLE == 8 && 4 == SIZEOF_SHORT */
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
#  else        /* SIZEOF_DOUBLE == 8 but undivide by known size of int */
    define_swapx(d, double)
#  endif
# endif        /* #if SIZEOF_LONG == 8 */
#else	/* SIZEOF_DOUBLE != 8 */
  define_swapx(d, double)
#endif	/* #if SIZEOF_DOUBLE == 8 */

#undef define_swapx

#define rb_ntohf(x) (BIGENDIAN_P()?(x):swapf(x))
#define rb_ntohd(x) (BIGENDIAN_P()?(x):swapd(x))
#define rb_htonf(x) (BIGENDIAN_P()?(x):swapf(x))
#define rb_htond(x) (BIGENDIAN_P()?(x):swapd(x))
#define rb_htovf(x) (BIGENDIAN_P()?swapf(x):(x))
#define rb_htovd(x) (BIGENDIAN_P()?swapd(x):(x))
#define rb_vtohf(x) (BIGENDIAN_P()?swapf(x):(x))
#define rb_vtohd(x) (BIGENDIAN_P()?swapd(x):(x))

#ifdef FLOAT_SWAPPER
#define FLOAT_CONVWITH(y)	FLOAT_SWAPPER y;
#define HTONF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = rb_htonf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#define HTOVF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = rb_htovf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#define NTOHF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = rb_ntohf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#define VTOHF(x,y)	(memcpy(&y,&x,sizeof(float)),	\
			 y = rb_vtohf((FLOAT_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(float)),	\
			 x)
#else
#define FLOAT_CONVWITH(y)
# define HTONF(x,y)    rb_htonf(x)
# define HTOVF(x,y)    rb_htovf(x)
# define NTOHF(x,y)    rb_ntohf(x)
# define VTOHF(x,y)    rb_vtohf(x)
#endif

#ifdef DOUBLE_SWAPPER
#define DOUBLE_CONVWITH(y)	DOUBLE_SWAPPER y;
#define HTOND(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = rb_htond((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#define HTOVD(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = rb_htovd((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#define NTOHD(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = rb_ntohd((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#define VTOHD(x,y)	(memcpy(&y,&x,sizeof(double)),	\
			 y = rb_vtohd((DOUBLE_SWAPPER)y),	\
			 memcpy(&x,&y,sizeof(double)),	\
			 x)
#else
#define DOUBLE_CONVWITH(y)
# define HTOND(x,y)    rb_htond(x)
# define HTOVD(x,y)    rb_htovd(x)
# define NTOHD(x,y)    rb_ntohd(x)
# define VTOHD(x,y)    rb_vtohd(x)
#endif

unsigned long rb_big2ulong_pack _((VALUE x));

static unsigned long
num2i32(x)
    VALUE x;
{
    x = rb_to_int(x); /* is nil OK? (should not) */

    if (FIXNUM_P(x)) return FIX2LONG(x);
    if (TYPE(x) == T_BIGNUM) {
	return rb_big2ulong_pack(x);
    }
    rb_raise(rb_eTypeError, "can't convert %s to `integer'", rb_obj_classname(x));
    return 0;			/* not reached */
}

#define QUAD_SIZE 8
#define MAX_INTEGER_PACK_SIZE 8
/* #define FORCE_BIG_PACK */

static const char toofew[] = "too few arguments";

static void encodes _((VALUE,const char*,long,int));
static void qpencode _((VALUE,VALUE,long));

static int uv_to_utf8 _((char*,unsigned long));

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
 *       A     |  ASCII string (space padded, count is width)
 *       a     |  ASCII string (null padded, count is width)
 *       B     |  Bit string (descending bit order)
 *       b     |  Bit string (ascending bit order)
 *       C     |  Unsigned char
 *       c     |  Char
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
 *       m     |  Base64 encoded string
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
pack_pack(ary, fmt)
    VALUE ary, fmt;
{
    static const char nul10[] = "\0\0\0\0\0\0\0\0\0\0";
    static const char spc10[] = "          ";
    char *p, *pend;
    VALUE res, from, associates = 0;
    char type;
    long items, len, idx, plen;
    const char *ptr;
#ifdef NATINT_PACK
    int natint;		/* native integer */
#endif
    int signed_p, integer_size, bigendian_p;

    StringValue(fmt);
    p = RSTRING(fmt)->ptr;
    pend = p + RSTRING(fmt)->len;
    res = rb_str_buf_new(0);

    items = RARRAY(ary)->len;
    idx = 0;

#define TOO_FEW (rb_raise(rb_eArgError, toofew), 0)
#define THISFROM (items > 0 ? RARRAY(ary)->ptr[idx] : TOO_FEW)
#define NEXTFROM (items-- > 0 ? RARRAY(ary)->ptr[idx++] : TOO_FEW)

    while (p < pend) {
	if (RSTRING(fmt)->ptr + RSTRING(fmt)->len != pend) {
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
	    const char *natstr = "sSiIlL";

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
	    len = strtoul(p, (char**)&p, 10);
	}
	else {
	    len = 1;
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
		ptr = RSTRING(from)->ptr;
		plen = RSTRING(from)->len;
		OBJ_INFECT(res, from);
	    }

	    if (p[-1] == '*')
		len = plen;

	    switch (type) {
	      case 'a':		/* arbitrary binary string (null padded)  */
	      case 'A':		/* ASCII string (space padded) */
	      case 'Z':		/* null terminated ASCII string  */
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
		c = num2i32(from);
		rb_str_buf_cat(res, &c, sizeof(char));
	    }
	    break;

	  case 's':		/* signed short */
            signed_p = 1;
            integer_size = NATINT_LEN(short, 2);
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'S':		/* unsigned short */
            signed_p = 0;
            integer_size = NATINT_LEN(short, 2);
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'i':		/* signed int */
            signed_p = 1;
            integer_size = (int)sizeof(int);
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'I':		/* unsigned int */
            signed_p = 0;
            integer_size = (int)sizeof(int);
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'l':		/* signed long */
            signed_p = 1;
            integer_size = NATINT_LEN(long, 4);
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'L':		/* unsigned long */
            signed_p = 0;
            integer_size = NATINT_LEN(long, 4);
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'q':		/* signed quad (64bit) int */
            signed_p = 1;
            integer_size = 8;
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'Q':		/* unsigned quad (64bit) int */
            signed_p = 0;
            integer_size = 8;
            bigendian_p = BIGENDIAN_P();
            goto pack_integer;

	  case 'n':		/* unsigned short (network byte-order)  */
            signed_p = 0;
            integer_size = 2;
            bigendian_p = 1;
            goto pack_integer;

	  case 'N':		/* unsigned long (network byte-order) */
            signed_p = 0;
            integer_size = 4;
            bigendian_p = 1;
            goto pack_integer;

	  case 'v':		/* unsigned short (VAX byte-order) */
            signed_p = 0;
            integer_size = 2;
            bigendian_p = 0;
            goto pack_integer;

	  case 'V':		/* unsigned long (VAX byte-order) */
            signed_p = 0;
            integer_size = 4;
            bigendian_p = 0;
            goto pack_integer;

          pack_integer:
            switch (integer_size) {
#if defined(HAVE_INT16_T) && !defined(FORCE_BIG_PACK)
              case SIZEOF_INT16_T:
                while (len-- > 0) {
                    union {
                        int16_t i;
                        char a[sizeof(int16_t)];
                    } v;

                    from = NEXTFROM;
                    v.i = (int16_t)num2i32(from);
                    if (bigendian_p != BIGENDIAN_P()) v.i = swap16(v.i);
                    rb_str_buf_cat(res, v.a, sizeof(int16_t));
                }
                break;
#endif

#if defined(HAVE_INT32_T) && !defined(FORCE_BIG_PACK)
              case SIZEOF_INT32_T:
                while (len-- > 0) {
                    union {
                        int32_t i;
                        char a[sizeof(int32_t)];
                    } v;

                    from = NEXTFROM;
                    v.i = (int32_t)num2i32(from);
                    if (bigendian_p != BIGENDIAN_P()) v.i = swap32(v.i);
                    rb_str_buf_cat(res, v.a, sizeof(int32_t));
                }
                break;
#endif

#if defined(HAVE_INT64_T) && SIZEOF_LONG == SIZEOF_INT64_T && !defined(FORCE_BIG_PACK)
              case SIZEOF_INT64_T:
                while (len-- > 0) {
                    union {
                        int64_t i;
                        char a[sizeof(int64_t)];
                    } v;

                    from = NEXTFROM;
                    v.i = num2i32(from); /* can return 64bit value if SIZEOF_LONG == SIZEOF_INT64_T */
                    if (bigendian_p != BIGENDIAN_P()) v.i = swap64(v.i);
                    rb_str_buf_cat(res, v.a, sizeof(int64_t));
                }
                break;
#endif

              default:
                if (integer_size > MAX_INTEGER_PACK_SIZE)
                    rb_bug("unexpected intger size for pack: %d", integer_size);
                while (len-- > 0) {
                    union {
                        unsigned long i[(MAX_INTEGER_PACK_SIZE+SIZEOF_LONG-1)/SIZEOF_LONG];
                        char a[(MAX_INTEGER_PACK_SIZE+SIZEOF_LONG-1)/SIZEOF_LONG*SIZEOF_LONG];
                    } v;
                    int num_longs = (integer_size+SIZEOF_LONG-1)/SIZEOF_LONG;
                    int i;

                    from = NEXTFROM;
                    rb_big_pack(from, v.i, num_longs);
                    if (bigendian_p) {
                        for (i = 0; i < num_longs/2; i++) {
                            unsigned long t = v.i[i];
                            v.i[i] = v.i[num_longs-1-i];
                            v.i[num_longs-1-i] = t;
                        }
                    }
                    if (bigendian_p != BIGENDIAN_P()) {
                        for (i = 0; i < num_longs; i++)
                            v.i[i] = swapl(v.i[i]);
                    }
                    rb_str_buf_cat(res,
                                   bigendian_p ?
                                     v.a + sizeof(long)*num_longs - integer_size :
                                     v.a,
                                   integer_size);
                }
                break;
            }
            break;

	  case 'f':		/* single precision float in native format */
	  case 'F':		/* ditto */
	    while (len-- > 0) {
		float f;

		from = NEXTFROM;
		f = RFLOAT(rb_Float(from))->value;
		rb_str_buf_cat(res, (char*)&f, sizeof(float));
	    }
	    break;

	  case 'e':		/* single precision float in VAX byte-order */
	    while (len-- > 0) {
		float f;
		FLOAT_CONVWITH(ftmp);

		from = NEXTFROM;
		f = RFLOAT(rb_Float(from))->value;
		f = HTOVF(f,ftmp);
		rb_str_buf_cat(res, (char*)&f, sizeof(float));
	    }
	    break;

	  case 'E':		/* double precision float in VAX byte-order */
	    while (len-- > 0) {
		double d;
		DOUBLE_CONVWITH(dtmp);

		from = NEXTFROM;
		d = RFLOAT(rb_Float(from))->value;
		d = HTOVD(d,dtmp);
		rb_str_buf_cat(res, (char*)&d, sizeof(double));
	    }
	    break;

	  case 'd':		/* double precision float in native format */
	  case 'D':		/* ditto */
	    while (len-- > 0) {
		double d;

		from = NEXTFROM;
		d = RFLOAT(rb_Float(from))->value;
		rb_str_buf_cat(res, (char*)&d, sizeof(double));
	    }
	    break;

	  case 'g':		/* single precision float in network byte-order */
	    while (len-- > 0) {
		float f;
		FLOAT_CONVWITH(ftmp);

		from = NEXTFROM;
		f = RFLOAT(rb_Float(from))->value;
		f = HTONF(f,ftmp);
		rb_str_buf_cat(res, (char*)&f, sizeof(float));
	    }
	    break;

	  case 'G':		/* double precision float in network byte-order */
	    while (len-- > 0) {
		double d;
		DOUBLE_CONVWITH(dtmp);

		from = NEXTFROM;
		d = RFLOAT(rb_Float(from))->value;
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
	    plen = RSTRING(res)->len;
	    if (plen < len)
		rb_raise(rb_eArgError, "X outside of string");
	    RSTRING(res)->len = plen - len;
	    RSTRING(res)->ptr[plen - len] = '\0';
	    break;

	  case '@':		/* null fill to absolute position */
	    len -= RSTRING(res)->len;
	    if (len > 0) goto grow;
	    len = -len;
	    if (len > 0) goto shrink;
	    break;

	  case '%':
	    rb_raise(rb_eArgError, "%% is not supported");
	    break;

	  case 'U':		/* Unicode character */
	    while (len-- > 0) {
		long l;
		char buf[8];
		int le;

		from = NEXTFROM;
		from = rb_to_int(from);
		l = NUM2INT(from);
		if (l < 0) {
		    rb_raise(rb_eRangeError, "pack(U): value out of range");
		}
		le = uv_to_utf8(buf, l);
		rb_str_buf_cat(res, (char*)buf, le);
	    }
	    break;

	  case 'u':		/* uuencoded string */
	  case 'm':		/* base64 encoded string */
	    from = NEXTFROM;
	    StringValue(from);
	    ptr = RSTRING(from)->ptr;
	    plen = RSTRING(from)->len;

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
		encodes(res, ptr, todo, type);
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
		if (RSTRING(from)->len < len) {
		    rb_raise(rb_eArgError, "too short buffer for P(%ld for %ld)",
			     RSTRING(from)->len, len);
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
			c = NUM2INT(RARRAY(from)->ptr[1]) | 0x80; /* mod */
			rb_str_buf_cat(buf, &c, sizeof(char));
			from = RARRAY(from)->ptr[0]; /* div */
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
		    c = ((ul & 0x7f) | 0x80);
		    rb_str_buf_cat(buf, &c, sizeof(char));
		    ul >>=  7;
		}

		if (RSTRING(buf)->len) {
		    bufs = RSTRING(buf)->ptr;
		    bufe = bufs + RSTRING(buf)->len - 1;
		    *bufs &= 0x7f; /* clear continue bit */
		    while (bufs < bufe) { /* reverse */
			c = *bufs;
			*bufs++ = *bufe;
			*bufe-- = c;
		    }
		    rb_str_buf_cat(res, RSTRING(buf)->ptr, RSTRING(buf)->len);
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
    return res;
}

static const char uu_table[] =
"`!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_";
static const char b64_table[] =
"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void
encodes(str, s, len, type)
    VALUE str;
    const char *s;
    long len;
    int type;
{
    char *buff = ALLOCA_N(char, len * 4 / 3 + 6);
    long i = 0;
    const char *trans = type == 'u' ? uu_table : b64_table;
    int padding;

    if (type == 'u') {
	buff[i++] = len + ' ';
	padding = '`';
    }
    else {
	padding = '=';
    }
    while (len >= 3) {
	buff[i++] = trans[077 & (*s >> 2)];
	buff[i++] = trans[077 & (((*s << 4) & 060) | ((s[1] >> 4) & 017))];
	buff[i++] = trans[077 & (((s[1] << 2) & 074) | ((s[2] >> 6) & 03))];
	buff[i++] = trans[077 & s[2]];
	s += 3;
	len -= 3;
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
    buff[i++] = '\n';
    rb_str_buf_cat(str, buff, i);
}

static char hex_table[] = "0123456789ABCDEF";

static void
qpencode(str, from, len)
    VALUE str, from;
    long len;
{
    char buff[1024];
    long i = 0, n = 0, prev = EOF;
    unsigned char *s = (unsigned char*)RSTRING(from)->ptr;
    unsigned char *send = s + RSTRING(from)->len;

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
hex2num(c)
    char c;
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
    tmp_len = 0;				\
    if (len > (long)((send-s)/sz)) {		\
        if (!star) {				\
	    tmp_len = len-(send-s)/sz;		\
        }					\
	len = (send-s)/sz;			\
    }						\
} while (0)

#define PACK_ITEM_ADJUST() do { \
    if (tmp_len > 0) \
        rb_ary_store(ary, RARRAY_LEN(ary)+tmp_len-1, Qnil); \
} while (0)

static VALUE
infected_str_new(ptr, len, str)
    const char *ptr;
    long len;
    VALUE str;
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
 *       A    | String  | with trailing nulls and spaces removed
 *     -------+---------+-----------------------------------------
 *       a    | String  | string
 *     -------+---------+-----------------------------------------
 *       B    | String  | extract bits from each character (msb first)
 *     -------+---------+-----------------------------------------
 *       b    | String  | extract bits from each character (lsb first)
 *     -------+---------+-----------------------------------------
 *       C    | Fixnum  | extract a character as an unsigned integer
 *     -------+---------+-----------------------------------------
 *       c    | Fixnum  | extract a character as an integer
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
 *       m    | String  | base64-encoded
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
pack_unpack(str, fmt)
    VALUE str, fmt;
{
    static const char hexdigits[] = "0123456789abcdef";
    char *s, *send;
    char *p, *pend;
    VALUE ary;
    char type;
    long len, tmp_len;
    int star;
#ifdef NATINT_PACK
    int natint;			/* native integer */
#endif
    int signed_p, integer_size, bigendian_p;

    StringValue(str);
    StringValue(fmt);
    s = RSTRING(str)->ptr;
    send = s + RSTRING(str)->len;
    p = RSTRING(fmt)->ptr;
    pend = p + RSTRING(fmt)->len;

    ary = rb_ary_new();
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
	    len = strtoul(p, (char**)&p, 10);
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
		rb_ary_push(ary, infected_str_new(s, len, str));
		s += end;
	    }
	    break;

	  case 'Z':
	    {
		char *t = s;

		if (len > send-s) len = send-s;
		while (t < s+len && *t) t++;
		rb_ary_push(ary, infected_str_new(s, t-s, str));
		if (t < send) t++;
		s = star ? t : s+len;
	    }
	    break;

	  case 'a':
	    if (len > send - s) len = send - s;
	    rb_ary_push(ary, infected_str_new(s, len, str));
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
		rb_ary_push(ary, bitstr = rb_str_new(0, len));
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
		char *t;
		int bits;
		long i;

		if (p[-1] == '*' || len > (send - s) * 8)
		    len = (send - s) * 8;
		bits = 0;
		rb_ary_push(ary, bitstr = rb_str_new(0, len));
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
		char *t;
		int bits;
		long i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		bits = 0;
		rb_ary_push(ary, bitstr = rb_str_new(0, len));
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
		char *t;
		int bits;
		long i;

		if (p[-1] == '*' || len > (send - s) * 2)
		    len = (send - s) * 2;
		bits = 0;
		rb_ary_push(ary, bitstr = rb_str_new(0, len));
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
	    PACK_LENGTH_ADJUST_SIZE(sizeof(char));
	    while (len-- > 0) {
                int c = *s++;
                if (c > (char)127) c-=256;
		rb_ary_push(ary, INT2FIX(c));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'C':
	    PACK_LENGTH_ADJUST_SIZE(sizeof(unsigned char));
	    while (len-- > 0) {
		unsigned char c = *s++;
		rb_ary_push(ary, INT2FIX(c));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 's':
            signed_p = 1;
            integer_size = NATINT_LEN(short, 2);
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

	  case 'S':
            signed_p = 0;
            integer_size = NATINT_LEN(short, 2);
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

	  case 'i':
            signed_p = 1;
            integer_size = (int)sizeof(int);
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

	  case 'I':
            signed_p = 0;
            integer_size = (int)sizeof(int);
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

	  case 'l':
            signed_p = 1;
            integer_size = NATINT_LEN(long, 4);
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

          case 'L':
            signed_p = 0;
            integer_size = NATINT_LEN(long, 4);
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

          case 'q':
            signed_p = 1;
            integer_size = QUAD_SIZE;
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

          case 'Q':
            signed_p = 0;
            integer_size = QUAD_SIZE;
            bigendian_p = BIGENDIAN_P();
            goto unpack_integer;

          case 'n':
            signed_p = 0;
            integer_size = 2;
            bigendian_p = 1;
            goto unpack_integer;

          case 'N':
            signed_p = 0;
            integer_size = 4;
            bigendian_p = 1;
            goto unpack_integer;

          case 'v':
            signed_p = 0;
            integer_size = 2;
            bigendian_p = 0;
            goto unpack_integer;

          case 'V':
            signed_p = 0;
            integer_size = 4;
            bigendian_p = 0;
            goto unpack_integer;

          unpack_integer:
            switch (integer_size) {
#if defined(HAVE_INT16_T) && !defined(FORCE_BIG_PACK)
              case SIZEOF_INT16_T:
                if (signed_p) {
                    PACK_LENGTH_ADJUST_SIZE(sizeof(int16_t));
                    while (len-- > 0) {
                        union {
                            int16_t i;
                            char a[sizeof(int16_t)];
                        } v;
                        memcpy(v.a, s, sizeof(int16_t));
                        if (bigendian_p != BIGENDIAN_P()) v.i = swap16(v.i);
                        s += sizeof(int16_t);
                        rb_ary_push(ary, INT2FIX(v.i));
                    }
                    PACK_ITEM_ADJUST();
                }
                else {
                    PACK_LENGTH_ADJUST_SIZE(sizeof(uint16_t));
                    while (len-- > 0) {
                        union {
                            uint16_t i;
                            char a[sizeof(uint16_t)];
                        } v;
                        memcpy(v.a, s, sizeof(uint16_t));
                        if (bigendian_p != BIGENDIAN_P()) v.i = swap16(v.i);
                        s += sizeof(uint16_t);
                        rb_ary_push(ary, INT2FIX(v.i));
                    }
                    PACK_ITEM_ADJUST();
                }
                break;
#endif

#if defined(HAVE_INT32_T) && !defined(FORCE_BIG_PACK)
              case SIZEOF_INT32_T:
                if (signed_p) {
                    PACK_LENGTH_ADJUST_SIZE(sizeof(int32_t));
                    while (len-- > 0) {
                        union {
                            int32_t i;
                            char a[sizeof(int32_t)];
                        } v;
                        memcpy(v.a, s, sizeof(int32_t));
                        if (bigendian_p != BIGENDIAN_P()) v.i = swap32(v.i);
                        s += sizeof(int32_t);
                        rb_ary_push(ary, INT2NUM(v.i));
                    }
                    PACK_ITEM_ADJUST();
                }
                else {
                    PACK_LENGTH_ADJUST_SIZE(sizeof(uint32_t));
                    while (len-- > 0) {
                        union {
                            uint32_t i;
                            char a[sizeof(uint32_t)];
                        } v;
                        memcpy(v.a, s, sizeof(uint32_t));
                        if (bigendian_p != BIGENDIAN_P()) v.i = swap32(v.i);
                        s += sizeof(uint32_t);
                        rb_ary_push(ary, UINT2NUM(v.i));
                    }
                    PACK_ITEM_ADJUST();
                }
                break;
#endif

#if defined(HAVE_INT64_T) && !defined(FORCE_BIG_PACK)
              case SIZEOF_INT64_T:
                if (signed_p) {
                    PACK_LENGTH_ADJUST_SIZE(sizeof(int64_t));
                    while (len-- > 0) {
                        union {
                            int64_t i;
                            char a[sizeof(int64_t)];
                        } v;
                        memcpy(v.a, s, sizeof(int64_t));
                        if (bigendian_p != BIGENDIAN_P()) v.i = swap64(v.i);
                        s += sizeof(int64_t);
                        rb_ary_push(ary, INT64toNUM(v.i));
                    }
                    PACK_ITEM_ADJUST();
                }
                else {
                    PACK_LENGTH_ADJUST_SIZE(sizeof(uint64_t));
                    while (len-- > 0) {
                        union {
                            uint64_t i;
                            char a[sizeof(uint64_t)];
                        } v;
                        memcpy(v.a, s, sizeof(uint64_t));
                        if (bigendian_p != BIGENDIAN_P()) v.i = swap64(v.i);
                        s += sizeof(uint64_t);
                        rb_ary_push(ary, UINT64toNUM(v.i));
                    }
                    PACK_ITEM_ADJUST();
                }
                break;
#endif


              default:
                if (integer_size > MAX_INTEGER_PACK_SIZE)
                    rb_bug("unexpected intger size for pack: %d", integer_size);
                PACK_LENGTH_ADJUST_SIZE(integer_size);
                while (len-- > 0) {
                    union {
                        unsigned long i[(MAX_INTEGER_PACK_SIZE+SIZEOF_LONG)/SIZEOF_LONG];
                        char a[(MAX_INTEGER_PACK_SIZE+SIZEOF_LONG)/SIZEOF_LONG*SIZEOF_LONG];
                    } v;
                    int num_longs = (integer_size+SIZEOF_LONG)/SIZEOF_LONG;
                    int i;

                    if (signed_p && (signed char)s[bigendian_p ? 0 : (integer_size-1)] < 0)
                        memset(v.a, 0xff, sizeof(long)*num_longs);
                    else
                        memset(v.a, 0, sizeof(long)*num_longs);
                    if (bigendian_p)
                        memcpy(v.a + sizeof(long)*num_longs - integer_size, s, integer_size);
                    else
                        memcpy(v.a, s, integer_size);
                    if (bigendian_p) {
                        for (i = 0; i < num_longs/2; i++) {
                            unsigned long t = v.i[i];
                            v.i[i] = v.i[num_longs-1-i];
                            v.i[num_longs-1-i] = t;
                        }
                    }
                    if (bigendian_p != BIGENDIAN_P()) {
                        for (i = 0; i < num_longs; i++)
                            v.i[i] = swapl(v.i[i]);
                    }
                    s += integer_size;
                    rb_ary_push(ary, rb_big_unpack(v.i, num_longs));
                }
                PACK_ITEM_ADJUST();
                break;
            }
            break;

	  case 'f':
	  case 'F':
	    PACK_LENGTH_ADJUST_SIZE(sizeof(float));
	    while (len-- > 0) {
		float tmp;
		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		rb_ary_push(ary, rb_float_new((double)tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'e':
	    PACK_LENGTH_ADJUST_SIZE(sizeof(float));
	    while (len-- > 0) {
	        float tmp;
		FLOAT_CONVWITH(ftmp);

		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		tmp = VTOHF(tmp,ftmp);
		rb_ary_push(ary, rb_float_new((double)tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'E':
	    PACK_LENGTH_ADJUST_SIZE(sizeof(double));
	    while (len-- > 0) {
		double tmp;
		DOUBLE_CONVWITH(dtmp);

		memcpy(&tmp, s, sizeof(double));
		s += sizeof(double);
		tmp = VTOHD(tmp,dtmp);
		rb_ary_push(ary, rb_float_new(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'D':
	  case 'd':
	    PACK_LENGTH_ADJUST_SIZE(sizeof(double));
	    while (len-- > 0) {
		double tmp;
		memcpy(&tmp, s, sizeof(double));
		s += sizeof(double);
		rb_ary_push(ary, rb_float_new(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'g':
	    PACK_LENGTH_ADJUST_SIZE(sizeof(float));
	    while (len-- > 0) {
	        float tmp;
		FLOAT_CONVWITH(ftmp;)

		memcpy(&tmp, s, sizeof(float));
		s += sizeof(float);
		tmp = NTOHF(tmp,ftmp);
		rb_ary_push(ary, rb_float_new((double)tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'G':
	    PACK_LENGTH_ADJUST_SIZE(sizeof(double));
	    while (len-- > 0) {
		double tmp;
		DOUBLE_CONVWITH(dtmp);

		memcpy(&tmp, s, sizeof(double));
		s += sizeof(double);
		tmp = NTOHD(tmp,dtmp);
		rb_ary_push(ary, rb_float_new(tmp));
	    }
	    PACK_ITEM_ADJUST();
	    break;

	  case 'U':
	    if (len > send - s) len = send - s;
	    while (len > 0 && s < send) {
		long alen = send - s;
		unsigned long l;

		l = rb_utf8_to_uv(s, &alen);
		s += alen; len--;
		rb_ary_push(ary, ULONG2NUM(l));
	    }
	    break;

	  case 'u':
	    {
		VALUE buf = infected_str_new(0, (send - s)*3/4, str);
		char *ptr = RSTRING(buf)->ptr;
		long total = 0;

		while (s < send && *s > ' ' && *s < 'a') {
		    long a,b,c,d;
		    char hunk[4];

		    hunk[3] = '\0';
		    len = (*s++ - ' ') & 077;
		    total += len;
		    if (total > RSTRING(buf)->len) {
			len -= total - RSTRING(buf)->len;
			total = RSTRING(buf)->len;
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

		RSTRING(buf)->ptr[total] = '\0';
		RSTRING(buf)->len = total;
		rb_ary_push(ary, buf);
	    }
	    break;

	  case 'm':
	    {
		VALUE buf = infected_str_new(0, (send - s)*3/4, str);
		char *ptr = RSTRING(buf)->ptr;
		int a = -1,b = -1,c = 0,d;
		static int first = 1;
		static int b64_xtable[256];

		if (first) {
		    int i;
		    first = 0;

		    for (i = 0; i < 256; i++) {
			b64_xtable[i] = -1;
		    }
		    for (i = 0; i < 64; i++) {
			b64_xtable[(int)b64_table[i]] = i;
		    }
		}
		while (s < send) {
		    a = b = c = d = -1;
		    while((a = b64_xtable[(int)(*(unsigned char*)s)]) == -1 && s < send) { s++; }
		    if( s >= send ) break;
		    s++;
		    while((b = b64_xtable[(int)(*(unsigned char*)s)]) == -1 && s < send) { s++; }
		    if( s >= send ) break;
		    s++;
		    while((c = b64_xtable[(int)(*(unsigned char*)s)]) == -1 && s < send) { if( *s == '=' ) break; s++; }
		    if( *s == '=' || s >= send ) break;
		    s++;
		    while((d = b64_xtable[(int)(*(unsigned char*)s)]) == -1 && s < send) { if( *s == '=' ) break; s++; }
		    if( *s == '=' || s >= send ) break;
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
		*ptr = '\0';
		RSTRING(buf)->len = ptr - RSTRING(buf)->ptr;
		rb_ary_push(ary, buf);
	    }
	    break;

	  case 'M':
	    {
		VALUE buf = infected_str_new(0, send - s, str);
		char *ptr = RSTRING(buf)->ptr;
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
		*ptr = '\0';
		RSTRING(buf)->len = ptr - RSTRING(buf)->ptr;
		rb_ary_push(ary, buf);
	    }
	    break;

	  case '@':
	    if (len > RSTRING(str)->len)
		rb_raise(rb_eArgError, "@ outside of string");
	    s = RSTRING(str)->ptr + len;
	    break;

	  case 'X':
	    if (len > s - RSTRING(str)->ptr)
		rb_raise(rb_eArgError, "X outside of string");
	    s -= len;
	    break;

	  case 'x':
	    if (len > send - s)
		rb_raise(rb_eArgError, "x outside of string");
	    s += len;
	    break;

	  case 'P':
	    if (sizeof(char *) <= (size_t)(send - s)) {
		VALUE tmp = Qnil;
		char *t;

		memcpy(&t, s, sizeof(char *));
		s += sizeof(char *);

		if (t) {
		    VALUE a, *p, *pend;

		    if (!(a = rb_str_associated(str))) {
			rb_raise(rb_eArgError, "no associated pointer");
		    }
		    p = RARRAY(a)->ptr;
		    pend = p + RARRAY(a)->len;
		    while (p < pend) {
			if (TYPE(*p) == T_STRING && RSTRING(*p)->ptr == t) {
			    if (len < RSTRING(*p)->len) {
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
		rb_ary_push(ary, tmp);
	    }
	    break;

	  case 'p':
	    if (len > (send - s) / sizeof(char *))
		len = (send - s) / sizeof(char *);
	    while (len-- > 0) {
		if ((size_t)(send - s) < sizeof(char *))
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
			p = RARRAY(a)->ptr;
			pend = p + RARRAY(a)->len;
			while (p < pend) {
			    if (TYPE(*p) == T_STRING && RSTRING(*p)->ptr == t) {
				tmp = *p;
				break;
			    }
			    p++;
			}
			if (p == pend) {
			    rb_raise(rb_eArgError, "non associated pointer");
			}
		    }
		    rb_ary_push(ary, tmp);
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
			rb_ary_push(ary, ULONG2NUM(ul));
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
				rb_ary_push(ary, big);
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

static int
uv_to_utf8(buf, uv)
    char *buf;
    unsigned long uv;
{
    if (uv <= 0x7f) {
	buf[0] = (char)uv;
	return 1;
    }
    if (uv <= 0x7ff) {
	buf[0] = ((uv>>6)&0xff)|0xc0;
	buf[1] = (uv&0x3f)|0x80;
	return 2;
    }
    if (uv <= 0xffff) {
	buf[0] = ((uv>>12)&0xff)|0xe0;
	buf[1] = ((uv>>6)&0x3f)|0x80;
	buf[2] = (uv&0x3f)|0x80;
	return 3;
    }
    if (uv <= 0x1fffff) {
	buf[0] = ((uv>>18)&0xff)|0xf0;
	buf[1] = ((uv>>12)&0x3f)|0x80;
	buf[2] = ((uv>>6)&0x3f)|0x80;
	buf[3] = (uv&0x3f)|0x80;
	return 4;
    }
    if (uv <= 0x3ffffff) {
	buf[0] = ((uv>>24)&0xff)|0xf8;
	buf[1] = ((uv>>18)&0x3f)|0x80;
	buf[2] = ((uv>>12)&0x3f)|0x80;
	buf[3] = ((uv>>6)&0x3f)|0x80;
	buf[4] = (uv&0x3f)|0x80;
	return 5;
    }
    if (uv <= 0x7fffffff) {
	buf[0] = ((uv>>30)&0xff)|0xfc;
	buf[1] = ((uv>>24)&0x3f)|0x80;
	buf[2] = ((uv>>18)&0x3f)|0x80;
	buf[3] = ((uv>>12)&0x3f)|0x80;
	buf[4] = ((uv>>6)&0x3f)|0x80;
	buf[5] = (uv&0x3f)|0x80;
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

unsigned long
rb_utf8_to_uv(p, lenp)
    char *p;
    long *lenp;
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
	rb_raise(rb_eArgError, "malformed UTF-8 character (expected %d bytes, given %d bytes)",
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
Init_pack()
{
    rb_define_method(rb_cArray, "pack", pack_pack, 1);
    rb_define_method(rb_cString, "unpack", pack_unpack, 1);
}
