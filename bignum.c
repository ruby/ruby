/**********************************************************************

  bignum.c -

  $Author$
  $Date$
  created at: Fri Jun 10 00:48:55 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include "rubysig.h"

#include <math.h>
#include <float.h>
#include <ctype.h>
#ifdef HAVE_IEEEFP_H
#include <ieeefp.h>
#endif

VALUE rb_cBignum;

#if defined __MINGW32__
#define USHORT _USHORT
#endif

#define BDIGITS(x) ((BDIGIT*)RBIGNUM(x)->digits)
#define BITSPERDIG (SIZEOF_BDIGITS*CHAR_BIT)
#define BIGRAD ((BDIGIT_DBL)1 << BITSPERDIG)
#define DIGSPERLONG ((unsigned int)(SIZEOF_LONG/SIZEOF_BDIGITS))
#if HAVE_LONG_LONG
# define DIGSPERLL ((unsigned int)(SIZEOF_LONG_LONG/SIZEOF_BDIGITS))
#endif
#define BIGUP(x) ((BDIGIT_DBL)(x) << BITSPERDIG)
#define BIGDN(x) RSHIFT(x,BITSPERDIG)
#define BIGLO(x) ((BDIGIT)((x) & (BIGRAD-1)))
#define BDIGMAX ((BDIGIT)-1)

#define BIGZEROP(x) (RBIGNUM(x)->len == 0 || \
		     (BDIGITS(x)[0] == 0 && \
		      (RBIGNUM(x)->len == 1 || bigzero_p(x))))

static int bigzero_p(VALUE);
static int
bigzero_p(x)
    VALUE x;
{
    long i;
    for (i = 0; i < RBIGNUM(x)->len; ++i) {
	if (BDIGITS(x)[i]) return 0;
    }
    return 1;
}

static VALUE
bignew_1(klass, len, sign)
    VALUE klass;
    long len;
    int sign;
{
    NEWOBJ(big, struct RBignum);
    OBJSETUP(big, klass, T_BIGNUM);
    big->sign = sign?1:0;
    big->len = len;
    big->digits = ALLOC_N(BDIGIT, len);

    return (VALUE)big;
}

#define bignew(len,sign) bignew_1(rb_cBignum,len,sign)

VALUE
rb_big_clone(x)
    VALUE x;
{
    VALUE z = bignew_1(CLASS_OF(x), RBIGNUM(x)->len, RBIGNUM(x)->sign);

    MEMCPY(BDIGITS(z), BDIGITS(x), BDIGIT, RBIGNUM(x)->len);
    return z;
}

/* modify a bignum by 2's complement */
static void
get2comp(x)
    VALUE x;
{
    long i = RBIGNUM(x)->len;
    BDIGIT *ds = BDIGITS(x);
    BDIGIT_DBL num;

    if (!i) return;
    while (i--) ds[i] = ~ds[i];
    i = 0; num = 1;
    do {
	num += ds[i];
	ds[i++] = BIGLO(num);
	num = BIGDN(num);
    } while (i < RBIGNUM(x)->len);
    if (num != 0) {
	REALLOC_N(RBIGNUM(x)->digits, BDIGIT, ++RBIGNUM(x)->len);
	ds = BDIGITS(x);
	ds[RBIGNUM(x)->len-1] = RBIGNUM(x)->sign ? ~0 : 1;
    }
}

void
rb_big_2comp(x)			/* get 2's complement */
    VALUE x;
{
    get2comp(x);
}

static VALUE
bigtrunc(x)
    VALUE x;
{
    long len = RBIGNUM(x)->len;
    BDIGIT *ds = BDIGITS(x);

    if (len == 0) return x;
    while (--len && !ds[len]);
    RBIGNUM(x)->len = ++len;
    return x;
}

static VALUE
bigfixize(x)
    VALUE x;
{
    long len = RBIGNUM(x)->len;
    BDIGIT *ds = BDIGITS(x);

    if (len*SIZEOF_BDIGITS <= sizeof(VALUE)) {
	long num = 0;
	while (len--) {
	    num = BIGUP(num) + ds[len];
	}
	if (num >= 0) {
	    if (RBIGNUM(x)->sign) {
		if (POSFIXABLE(num)) return LONG2FIX(num);
	    }
	    else {
		if (NEGFIXABLE(-(long)num)) return LONG2FIX(-(long)num);
	    }
	}
    }
    return x;
}

static VALUE
bignorm(x)
    VALUE x;
{
    if (!FIXNUM_P(x) && TYPE(x) == T_BIGNUM) {
	x = bigfixize(bigtrunc(x));
    }
    return x;
}

VALUE
rb_big_norm(x)
    VALUE x;
{
    return bignorm(x);
}

VALUE
rb_uint2big(n)
    unsigned long n;
{
    BDIGIT_DBL num = n;
    long i = 0;
    BDIGIT *digits;
    VALUE big;

    big = bignew(DIGSPERLONG, 1);
    digits = BDIGITS(big);
    while (i < DIGSPERLONG) {
	digits[i++] = BIGLO(num);
	num = BIGDN(num);
    }

    i = DIGSPERLONG;
    while (--i && !digits[i]) ;
    RBIGNUM(big)->len = i+1;
    return big;
}

VALUE
rb_int2big(n)
    long n;
{
    long neg = 0;
    VALUE big;

    if (n < 0) {
	n = -n;
	neg = 1;
    }
    big = rb_uint2big(n);
    if (neg) {
	RBIGNUM(big)->sign = 0;
    }
    return big;
}

VALUE
rb_uint2inum(n)
    unsigned long n;
{
    if (POSFIXABLE(n)) return LONG2FIX(n);
    return rb_uint2big(n);
}

VALUE
rb_int2inum(n)
    long n;
{
    if (FIXABLE(n)) return LONG2FIX(n);
    return rb_int2big(n);
}

#if SIZEOF_LONG % SIZEOF_BDIGITS != 0
# error unexpected SIZEOF_LONG : SIZEOF_BDIGITS ratio
#endif

/*
 * buf is an array of long integers.
 * buf is ordered from least significant word to most significant word.
 * buf[0] is the least significant word and
 * buf[num_longs-1] is the most significant word.
 * This means words in buf is little endian.
 * However each word in buf is native endian.
 * (buf[i]&1) is the least significant bit and
 * (buf[i]&(1<<(SIZEOF_LONG*CHAR_BIT-1))) is the most significant bit
 * for each 0 <= i < num_longs.
 * So buf is little endian at whole on a little endian machine.
 * But buf is mixed endian on a big endian machine.
 */
void
rb_big_pack(VALUE val, unsigned long *buf, long num_longs)
{
    val = rb_to_int(val);
    if (num_longs == 0)
        return;
    if (FIXNUM_P(val)) {
        long i;
        long tmp = FIX2LONG(val);
        buf[0] = (unsigned long)tmp;
        tmp = tmp < 0 ? ~0L : 0;
        for (i = 1; i < num_longs; i++)
            buf[i] = (unsigned long)tmp;
        return;
    }
    else {
        long len = RBIGNUM_LEN(val);
        BDIGIT *ds = BDIGITS(val), *dend = ds + len;
        long i, j;
        for (i = 0; i < num_longs && ds < dend; i++) {
            unsigned long l = 0;
            for (j = 0; j < DIGSPERLONG && ds < dend; j++, ds++) {
                l |= ((unsigned long)*ds << (j * BITSPERDIG));
            }
            buf[i] = l;
        }
        for (; i < num_longs; i++)
            buf[i] = 0;
        if (RBIGNUM_NEGATIVE_P(val)) {
            for (i = 0; i < num_longs; i++) {
                buf[i] = ~buf[i];
            }
            for (i = 0; i < num_longs; i++) {
                buf[i]++;
                if (buf[i] != 0)
                    return;
            }
        }
    }
}

/* See rb_big_pack comment for endianness of buf. */
VALUE
rb_big_unpack(unsigned long *buf, long num_longs)
{
    while (2 <= num_longs) {
        if (buf[num_longs-1] == 0 && (long)buf[num_longs-2] >= 0)
            num_longs--;
        else if (buf[num_longs-1] == ~0UL && (long)buf[num_longs-2] < 0)
            num_longs--;
        else
            break;
    }
    if (num_longs == 0)
        return INT2FIX(0);
    else if (num_longs == 1)
        return LONG2NUM((long)buf[0]);
    else {
        VALUE big;
        BDIGIT *ds;
        long len = num_longs * DIGSPERLONG;
        long i;
        big = bignew(len, 1);
        ds = BDIGITS(big);
        for (i = 0; i < num_longs; i++) {
            unsigned long d = buf[i];
#if SIZEOF_LONG == SIZEOF_BDIGITS
            *ds++ = d;
#else
            int j;
            for (j = 0; j < DIGSPERLONG; j++) {
                *ds++ = BIGLO(d);
                d = BIGDN(d);
            }
#endif
        }
        if ((long)buf[num_longs-1] < 0) {
            get2comp(big);
            RBIGNUM_SET_SIGN(big, 0);
        }
        return bignorm(big);
    }
}

#define QUAD_SIZE 8

#if SIZEOF_LONG_LONG == QUAD_SIZE && SIZEOF_BDIGITS*2 == SIZEOF_LONG_LONG

void
rb_quad_pack(buf, val)
    char *buf;
    VALUE val;
{
    LONG_LONG q;

    val = rb_to_int(val);
    if (FIXNUM_P(val)) {
	q = FIX2LONG(val);
    }
    else {
	long len = RBIGNUM(val)->len;
	BDIGIT *ds;

	if (len > SIZEOF_LONG_LONG/SIZEOF_BDIGITS)
	    rb_raise(rb_eRangeError, "bignum too big to convert into `quad int'");
	ds = BDIGITS(val);
	q = 0;
	while (len--) {
	    q = BIGUP(q);
	    q += ds[len];
	}
	if (!RBIGNUM(val)->sign) q = -q;
    }
    memcpy(buf, (char*)&q, SIZEOF_LONG_LONG);
}

VALUE
rb_quad_unpack(buf, sign)
    const char *buf;
    int sign;
{
    unsigned LONG_LONG q;
    long neg = 0;
    long i;
    BDIGIT *digits;
    VALUE big;

    memcpy(&q, buf, SIZEOF_LONG_LONG);
    if (sign) {
	if (FIXABLE((LONG_LONG)q)) return LONG2FIX((LONG_LONG)q);
	if ((LONG_LONG)q < 0) {
	    q = -(LONG_LONG)q;
	    neg = 1;
	}
    }
    else {
	if (POSFIXABLE(q)) return LONG2FIX(q);
    }

    i = 0;
    big = bignew(DIGSPERLL, 1);
    digits = BDIGITS(big);
    while (i < DIGSPERLL) {
	digits[i++] = BIGLO(q);
	q = BIGDN(q);
    }

    i = DIGSPERLL;
    while (i-- && !digits[i]) ;
    RBIGNUM(big)->len = i+1;

    if (neg) {
	RBIGNUM(big)->sign = 0;
    }
    return bignorm(big);
}

#else

static int
quad_buf_complement(char *buf, size_t len)
{
    size_t i;
    for (i = 0; i < len; i++)
        buf[i] = ~buf[i];
    for (i = 0; i < len; i++) {
        buf[i]++;
        if (buf[i] != 0)
            return 0;
    }
    return 1;
}

void
rb_quad_pack(buf, val)
    char *buf;
    VALUE val;
{
    long len;

    memset(buf, 0, QUAD_SIZE);
    val = rb_to_int(val);
    if (FIXNUM_P(val)) {
	val = rb_int2big(FIX2LONG(val));
    }
    len = RBIGNUM(val)->len * SIZEOF_BDIGITS;
    if (len > QUAD_SIZE) {
	rb_raise(rb_eRangeError, "bignum too big to convert into `quad int'");
    }
    memcpy(buf, (char*)BDIGITS(val), len);
    if (RBIGNUM_NEGATIVE_P(val)) {
        quad_buf_complement(buf, QUAD_SIZE);
    }
}

#define BNEG(b) (RSHIFT(((BDIGIT*)b)[QUAD_SIZE/SIZEOF_BDIGITS-1],BITSPERDIG-1) != 0)

VALUE
rb_quad_unpack(buf, sign)
    const char *buf;
    int sign;
{
    VALUE big = bignew(QUAD_SIZE/SIZEOF_BDIGITS, 1);

    memcpy((char*)BDIGITS(big), buf, QUAD_SIZE);
    if (sign && BNEG(buf)) {
	char *tmp = (char*)BDIGITS(big);

	RBIGNUM(big)->sign = 0;
        quad_buf_complement(tmp, QUAD_SIZE);
    }

    return bignorm(big);
}

#endif

VALUE
rb_cstr_to_inum(str, base, badcheck)
    const char *str;
    int base;
    int badcheck;
{
    const char *s = str;
    char *end;
    char sign = 1, nondigit = 0;
    int c;
    BDIGIT_DBL num;
    long len, blen = 1;
    long i;
    VALUE z;
    BDIGIT *zds;

#define conv_digit(c) \
    (!ISASCII(c) ? -1 : \
     isdigit(c) ? ((c) - '0') : \
     islower(c) ? ((c) - 'a' + 10) : \
     isupper(c) ? ((c) - 'A' + 10) : \
     -1)

    if (!str) {
	if (badcheck) goto bad;
	return INT2FIX(0);
    }
    if (badcheck) {
	while (ISSPACE(*str)) str++;
    }
    else {
	while (ISSPACE(*str) || *str == '_') str++;
    }

    if (str[0] == '+') {
	str++;
    }
    else if (str[0] == '-') {
	str++;
	sign = 0;
    }
    if (str[0] == '+' || str[0] == '-') {
	if (badcheck) goto bad;
	return INT2FIX(0);
    }
    if (base <= 0) {
	if (str[0] == '0') {
	    switch (str[1]) {
	      case 'x': case 'X':
		base = 16;
		break;
	      case 'b': case 'B':
		base = 2;
		break;
	      case 'o': case 'O':
		base = 8;
		break;
	      case 'd': case 'D':
		base = 10;
		break;
	      default:
		base = 8;
	    }
	}
	else if (base < -1) {
	    base = -base;
	}
	else {
	    base = 10;
	}
    }
    switch (base) {
      case 2:
	len = 1;
	if (str[0] == '0' && (str[1] == 'b'||str[1] == 'B')) {
	    str += 2;
	}
	break;
      case 3:
	len = 2;
	break;
      case 8:
	if (str[0] == '0' && (str[1] == 'o'||str[1] == 'O')) {
	    str += 2;
	}
      case 4: case 5: case 6: case 7:
	len = 3;
	break;
      case 10:
	if (str[0] == '0' && (str[1] == 'd'||str[1] == 'D')) {
	    str += 2;
	}
      case 9: case 11: case 12: case 13: case 14: case 15:
	len = 4;
	break;
      case 16:
	len = 4;
	if (str[0] == '0' && (str[1] == 'x'||str[1] == 'X')) {
	    str += 2;
	}
	break;
      default:
	if (base < 2 || 36 < base) {
	    rb_raise(rb_eArgError, "illegal radix %d", base);
	}
	if (base <= 32) {
	    len = 5;
	}
	else {
	    len = 6;
	}
	break;
    }
    if (*str == '0') {		/* squeeze preceeding 0s */
	int us = 0;
	while ((c = *++str) == '0' || c == '_') {
	    if (c == '_') {
		if (++us >= 2)
		    break;
	    } else
		us = 0;
	}
	if (!(c = *str) || ISSPACE(c)) --str;
    }
    c = *str;
    c = conv_digit(c);
    if (c < 0 || c >= base) {
	if (badcheck) goto bad;
	return INT2FIX(0);
    }
    len *= strlen(str)*sizeof(char);

    if (len <= (sizeof(VALUE)*CHAR_BIT)) {
	unsigned long val = strtoul((char*)str, &end, base);

	if (*end == '_') goto bigparse;
	if (badcheck) {
	    if (end == str) goto bad; /* no number */
	    while (*end && ISSPACE(*end)) end++;
	    if (*end) goto bad;	      /* trailing garbage */
	}

	if (POSFIXABLE(val)) {
	    if (sign) return LONG2FIX(val);
	    else {
		long result = -(long)val;
		return LONG2FIX(result);
	    }
	}
	else {
	    VALUE big = rb_uint2big(val);
	    RBIGNUM(big)->sign = sign;
	    return bignorm(big);
	}
    }
  bigparse:
    len = (len/BITSPERDIG)+1;
    if (badcheck && *str == '_') goto bad;

    z = bignew(len, sign);
    zds = BDIGITS(z);
    for (i=len;i--;) zds[i]=0;
    while ((c = *str++) != 0) {
	if (c == '_') {
	    if (nondigit) {
		if (badcheck) goto bad;
		break;
	    }
	    nondigit = c;
	    continue;
	}
	else if ((c = conv_digit(c)) < 0) {
	    break;
	}
	if (c >= base) break;
	nondigit = 0;
	i = 0;
	num = c;
	for (;;) {
	    while (i<blen) {
		num += (BDIGIT_DBL)zds[i]*base;
		zds[i++] = BIGLO(num);
		num = BIGDN(num);
	    }
	    if (num) {
		blen++;
		continue;
	    }
	    break;
	}
    }
    if (badcheck) {
	str--;
	if (s+1 < str && str[-1] == '_') goto bad;
	while (*str && ISSPACE(*str)) str++;
	if (*str) {
	  bad:
	    rb_invalid_str(s, "Integer");
	}
    }

    return bignorm(z);
}

VALUE
rb_str_to_inum(str, base, badcheck)
    VALUE str;
    int base;
    int badcheck;
{
    char *s;
    long len;

    StringValue(str);
    if (badcheck) {
	s = StringValueCStr(str);
    }
    else {
	s = RSTRING(str)->ptr;
    }
    if (s) {
	len = RSTRING(str)->len;
	if (s[len]) {		/* no sentinel somehow */
	    char *p = ALLOCA_N(char, len+1);

	    MEMCPY(p, s, char, len);
	    p[len] = '\0';
	    s = p;
	}
    }
    return rb_cstr_to_inum(s, base, badcheck);
}

#if HAVE_LONG_LONG

VALUE
rb_ull2big(n)
    unsigned LONG_LONG n;
{
    BDIGIT_DBL num = n;
    long i = 0;
    BDIGIT *digits;
    VALUE big;

    big = bignew(DIGSPERLL, 1);
    digits = BDIGITS(big);
    while (i < DIGSPERLL) {
	digits[i++] = BIGLO(num);
	num = BIGDN(num);
    }

    i = DIGSPERLL;
    while (i-- && !digits[i]) ;
    RBIGNUM(big)->len = i+1;
    return big;
}

VALUE
rb_ll2big(n)
    LONG_LONG n;
{
    long neg = 0;
    VALUE big;

    if (n < 0) {
	n = -n;
	neg = 1;
    }
    big = rb_ull2big(n);
    if (neg) {
	RBIGNUM(big)->sign = 0;
    }
    return big;
}

VALUE
rb_ull2inum(n)
    unsigned LONG_LONG n;
{
    if (POSFIXABLE(n)) return LONG2FIX(n);
    return rb_ull2big(n);
}

VALUE
rb_ll2inum(n)
    LONG_LONG n;
{
    if (FIXABLE(n)) return LONG2FIX(n);
    return rb_ll2big(n);
}

#endif  /* HAVE_LONG_LONG */

VALUE
rb_cstr2inum(str, base)
    const char *str;
    int base;
{
    return rb_cstr_to_inum(str, base, base==0);
}

VALUE
rb_str2inum(str, base)
    VALUE str;
    int base;
{
    return rb_str_to_inum(str, base, base==0);
}

const char ruby_digitmap[] = "0123456789abcdefghijklmnopqrstuvwxyz";
VALUE
rb_big2str0(x, base, trim)
    VALUE x;
    int base;
    int trim;
{
    volatile VALUE t;
    BDIGIT *ds;
    long i, j, hbase;
    VALUE ss;
    char *s;

    if (FIXNUM_P(x)) {
	return rb_fix2str(x, base);
    }
    i = RBIGNUM(x)->len;
    if (BIGZEROP(x)) {
	return rb_str_new2("0");
    }
    if (i >= LONG_MAX/SIZEOF_BDIGITS/CHAR_BIT) {
	rb_raise(rb_eRangeError, "bignum too big to convert into `string'");
    }
    j = SIZEOF_BDIGITS*CHAR_BIT*i;
    switch (base) {
      case 2: break;
      case 3:
	j = j * 53L / 84 + 1;
	break;
      case 4: case 5: case 6: case 7:
	j = (j + 1) / 2;
	break;
      case 8: case 9:
	j = (j + 2) / 3;
	break;
      case 10: case 11: case 12: case 13: case 14: case 15:
	j = j * 28L / 93 + 1;
	break;
      case 16: case 17: case 18: case 19: case 20: case 21:
      case 22: case 23: case 24: case 25: case 26: case 27:
      case 28: case 29: case 30: case 31:
	j = (j + 3) / 4;
	break;
      case 32: case 33: case 34: case 35: case 36:
	j = (j + 4) / 5;
	break;
      default:
	rb_raise(rb_eArgError, "illegal radix %d", base);
	break;
    }
    j++;			/* space for sign */

    hbase = base * base;
#if SIZEOF_BDIGITS > 2
    hbase *= hbase;
#endif

    t = rb_big_clone(x);
    ds = BDIGITS(t);
    ss = rb_str_new(0, j+1);
    s = RSTRING(ss)->ptr;

    s[0] = RBIGNUM(x)->sign ? '+' : '-';
    TRAP_BEG;
    while (i && j > 1) {
	long k = i;
	BDIGIT_DBL num = 0;

	while (k--) {
	    num = BIGUP(num) + ds[k];
	    ds[k] = (BDIGIT)(num / hbase);
	    num %= hbase;
	}
	if (trim && ds[i-1] == 0) i--;
	k = SIZEOF_BDIGITS;
	while (k--) {
	    s[--j] = ruby_digitmap[num % base];
	    num /= base;
	    if (!trim && j <= 1) break;
	    if (trim && i == 0 && num == 0) break;
	}
    }
    if (trim) {while (s[j] == '0') j++;}
    i = RSTRING(ss)->len - j;
    if (RBIGNUM(x)->sign) {
	memmove(s, s+j, i);
	RSTRING(ss)->len = i-1;
    }
    else {
	memmove(s+1, s+j, i);
	RSTRING(ss)->len = i;
    }
    s[RSTRING(ss)->len] = '\0';
    TRAP_END;

    return ss;
}

VALUE
rb_big2str(x, base)
    VALUE x;
    int base;
{
    return rb_big2str0(x, base, Qtrue);
}

/*
 *  call-seq:
 *     big.to_s(base=10)   =>  string
 *
 *  Returns a string containing the representation of <i>big</i> radix
 *  <i>base</i> (2 through 36).
 *
 *     12345654321.to_s         #=> "12345654321"
 *     12345654321.to_s(2)      #=> "1011011111110110111011110000110001"
 *     12345654321.to_s(8)      #=> "133766736061"
 *     12345654321.to_s(16)     #=> "2dfdbbc31"
 *     78546939656932.to_s(36)  #=> "rubyrules"
 */

static VALUE
rb_big_to_s(argc, argv, x)
    int argc;
    VALUE *argv;
    VALUE x;
{
    VALUE b;
    int base;

    rb_scan_args(argc, argv, "01", &b);
    if (argc == 0) base = 10;
    else base = NUM2INT(b);
    return rb_big2str(x, base);
}

static unsigned long
big2ulong(x, type)
    VALUE x;
    const char *type;
{
    long len = RBIGNUM(x)->len;
    BDIGIT_DBL num;
    BDIGIT *ds;

    if (len > SIZEOF_LONG/SIZEOF_BDIGITS)
	rb_raise(rb_eRangeError, "bignum too big to convert into `%s'", type);
    ds = BDIGITS(x);
    num = 0;
    while (len--) {
	num = BIGUP(num);
	num += ds[len];
    }
    return num;
}

unsigned long
rb_big2ulong_pack(x)
    VALUE x;
{
    unsigned long num = big2ulong(x, "unsigned long");
    if (!RBIGNUM(x)->sign) {
	return -num;
    }
    return num;
}

unsigned long
rb_big2ulong(x)
    VALUE x;
{
    unsigned long num = big2ulong(x, "unsigned long");

    if (!RBIGNUM(x)->sign) {
	if ((long)num < 0) {
	    rb_raise(rb_eRangeError, "bignum out of range of unsigned long");
	}
	return -num;
    }
    return num;
}

long
rb_big2long(x)
    VALUE x;
{
    unsigned long num = big2ulong(x, "long");

    if ((long)num < 0 && (RBIGNUM(x)->sign || (long)num != LONG_MIN)) {
	rb_raise(rb_eRangeError, "bignum too big to convert into `long'");
    }
    if (!RBIGNUM(x)->sign) return -(long)num;
    return num;
}

#if HAVE_LONG_LONG

static unsigned LONG_LONG
big2ull(x, type)
    VALUE x;
    const char *type;
{
    long len = RBIGNUM(x)->len;
    BDIGIT_DBL num;
    BDIGIT *ds;

    if (len > SIZEOF_LONG_LONG/SIZEOF_BDIGITS)
	rb_raise(rb_eRangeError, "bignum too big to convert into `%s'", type);
    ds = BDIGITS(x);
    num = 0;
    while (len--) {
	num = BIGUP(num);
	num += ds[len];
    }
    return num;
}

unsigned LONG_LONG
rb_big2ull(x)
    VALUE x;
{
    unsigned LONG_LONG num = big2ull(x, "unsigned long long");

    if (!RBIGNUM(x)->sign) return -num;
    return num;
}

LONG_LONG
rb_big2ll(x)
    VALUE x;
{
    unsigned LONG_LONG num = big2ull(x, "long long");

    if ((LONG_LONG)num < 0 && (RBIGNUM(x)->sign
			       || (LONG_LONG)num != LLONG_MIN)) {
	rb_raise(rb_eRangeError, "bignum too big to convert into `long long'");
    }
    if (!RBIGNUM(x)->sign) return -(LONG_LONG)num;
    return num;
}

#endif  /* HAVE_LONG_LONG */

static VALUE
dbl2big(d)
    double d;
{
    long i = 0;
    BDIGIT c;
    BDIGIT *digits;
    VALUE z;
    double u = (d < 0)?-d:d;

    if (isinf(d)) {
	rb_raise(rb_eFloatDomainError, d < 0 ? "-Infinity" : "Infinity");
    }
    if (isnan(d)) {
	rb_raise(rb_eFloatDomainError, "NaN");
    }

    while (!POSFIXABLE(u) || 0 != (long)u) {
	u /= (double)(BIGRAD);
	i++;
    }
    z = bignew(i, d>=0);
    digits = BDIGITS(z);
    while (i--) {
	u *= BIGRAD;
	c = (BDIGIT)u;
	u -= c;
	digits[i] = c;
    }

    return z;
}

VALUE
rb_dbl2big(d)
    double d;
{
    return bignorm(dbl2big(d));
}

static double
big2dbl(x)
    VALUE x;
{
    double d = 0.0;
    long i = RBIGNUM(x)->len;
    BDIGIT *ds = BDIGITS(x);

    while (i--) {
	d = ds[i] + BIGRAD*d;
    }
    if (!RBIGNUM(x)->sign) d = -d;
    return d;
}

double
rb_big2dbl(x)
    VALUE x;
{
    double d = big2dbl(x);

    if (isinf(d)) {
	rb_warn("Bignum out of Float range");
	d = HUGE_VAL;
    }
    return d;
}

/*
 *  call-seq:
 *     big.to_f -> float
 *
 *  Converts <i>big</i> to a <code>Float</code>. If <i>big</i> doesn't
 *  fit in a <code>Float</code>, the result is infinity.
 *
 */

static VALUE
rb_big_to_f(x)
    VALUE x;
{
    return rb_float_new(rb_big2dbl(x));
}

/*
 *  call-seq:
 *     big <=> numeric   => -1, 0, +1 or nil
 *
 *  Comparison---Returns -1, 0, or +1 depending on whether <i>big</i> is
 *  less than, equal to, or greater than <i>numeric</i>. This is the
 *  basis for the tests in <code>Comparable</code>.
 *
 */

static VALUE
rb_big_cmp(x, y)
    VALUE x, y;
{
    long xlen = RBIGNUM(x)->len;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
	return rb_dbl_cmp(rb_big2dbl(x), RFLOAT(y)->value);

      default:
	return rb_num_coerce_cmp(x, y);
    }

    if (RBIGNUM(x)->sign > RBIGNUM(y)->sign) return INT2FIX(1);
    if (RBIGNUM(x)->sign < RBIGNUM(y)->sign) return INT2FIX(-1);
    if (xlen < RBIGNUM(y)->len)
	return (RBIGNUM(x)->sign) ? INT2FIX(-1) : INT2FIX(1);
    if (xlen > RBIGNUM(y)->len)
	return (RBIGNUM(x)->sign) ? INT2FIX(1) : INT2FIX(-1);

    while(xlen-- && (BDIGITS(x)[xlen]==BDIGITS(y)[xlen]));
    if (-1 == xlen) return INT2FIX(0);
    return (BDIGITS(x)[xlen] > BDIGITS(y)[xlen]) ?
	(RBIGNUM(x)->sign ? INT2FIX(1) : INT2FIX(-1)) :
	    (RBIGNUM(x)->sign ? INT2FIX(-1) : INT2FIX(1));
}

/*
 *  call-seq:
 *     big == obj  => true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> has the same value
 *  as <i>big</i>. Contrast this with <code>Bignum#eql?</code>, which
 *  requires <i>obj</i> to be a <code>Bignum</code>.
 *
 *     68719476736 == 68719476736.0   #=> true
 */

static VALUE
rb_big_eq(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;
      case T_BIGNUM:
	break;
      case T_FLOAT:
        {
	    volatile double a, b;

	    a = RFLOAT(y)->value;
	    if (isnan(a)) return Qfalse;
	    b = rb_big2dbl(x);
	    return (a == b)?Qtrue:Qfalse;
	}
      default:
	return rb_equal(y, x);
    }
    if (RBIGNUM(x)->sign != RBIGNUM(y)->sign) return Qfalse;
    if (RBIGNUM(x)->len != RBIGNUM(y)->len) return Qfalse;
    if (MEMCMP(BDIGITS(x),BDIGITS(y),BDIGIT,RBIGNUM(y)->len) != 0) return Qfalse;
    return Qtrue;
}

/*
 *  call-seq:
 *     big.eql?(obj)   => true or false
 *
 *  Returns <code>true</code> only if <i>obj</i> is a
 *  <code>Bignum</code> with the same value as <i>big</i>. Contrast this
 *  with <code>Bignum#==</code>, which performs type conversions.
 *
 *     68719476736.eql?(68719476736.0)   #=> false
 */

static VALUE
rb_big_eql(x, y)
    VALUE x, y;
{
    if (TYPE(y) != T_BIGNUM) return Qfalse;
    if (RBIGNUM(x)->sign != RBIGNUM(y)->sign) return Qfalse;
    if (RBIGNUM(x)->len != RBIGNUM(y)->len) return Qfalse;
    if (MEMCMP(BDIGITS(x),BDIGITS(y),BDIGIT,RBIGNUM(y)->len) != 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    -big   =>  other_big
 *
 * Unary minus (returns a new Bignum whose value is 0-big)
 */

static VALUE
rb_big_uminus(x)
    VALUE x;
{
    VALUE z = rb_big_clone(x);

    RBIGNUM(z)->sign = !RBIGNUM(x)->sign;

    return bignorm(z);
}

/*
 * call-seq:
 *     ~big  =>  integer
 *
 * Inverts the bits in big. As Bignums are conceptually infinite
 * length, the result acts as if it had an infinite number of one
 * bits to the left. In hex representations, this is displayed
 * as two periods to the left of the digits.
 *
 *   sprintf("%X", ~0x1122334455)    #=> "..FEEDDCCBBAA"
 */

static VALUE
rb_big_neg(x)
    VALUE x;
{
    VALUE z = rb_big_clone(x);
    long i;
    BDIGIT *ds;

    if (!RBIGNUM(x)->sign) get2comp(z);
    ds = BDIGITS(z);
    i = RBIGNUM(x)->len;
    if (!i) return INT2FIX(~0);
    while (i--) ds[i] = ~ds[i];
    RBIGNUM(z)->sign = !RBIGNUM(z)->sign;
    if (RBIGNUM(x)->sign) get2comp(z);

    return bignorm(z);
}

static VALUE
bigsub(x, y)
    VALUE x, y;
{
    VALUE z = 0;
    BDIGIT *zds;
    BDIGIT_DBL_SIGNED num;
    long i = RBIGNUM(x)->len;

    /* if x is larger than y, swap */
    if (RBIGNUM(x)->len < RBIGNUM(y)->len) {
	z = x; x = y; y = z;	/* swap x y */
    }
    else if (RBIGNUM(x)->len == RBIGNUM(y)->len) {
	while (i > 0) {
	    i--;
	    if (BDIGITS(x)[i] > BDIGITS(y)[i]) {
		break;
	    }
	    if (BDIGITS(x)[i] < BDIGITS(y)[i]) {
		z = x; x = y; y = z;	/* swap x y */
		break;
	    }
	}
    }

    z = bignew(RBIGNUM(x)->len, z==0);
    zds = BDIGITS(z);

    for (i = 0, num = 0; i < RBIGNUM(y)->len; i++) {
	num += (BDIGIT_DBL_SIGNED)BDIGITS(x)[i] - BDIGITS(y)[i];
	zds[i] = BIGLO(num);
	num = BIGDN(num);
    }
    while (num && i < RBIGNUM(x)->len) {
	num += BDIGITS(x)[i];
	zds[i++] = BIGLO(num);
	num = BIGDN(num);
    }
    while (i < RBIGNUM(x)->len) {
	zds[i] = BDIGITS(x)[i];
	i++;
    }

    return z;
}

static VALUE
bigadd(x, y, sign)
    VALUE x, y;
    int sign;
{
    VALUE z;
    BDIGIT_DBL num;
    long i, len;

    sign = (sign == RBIGNUM(y)->sign);
    if (RBIGNUM(x)->sign != sign) {
	if (sign) return bigsub(y, x);
	return bigsub(x, y);
    }

    if (RBIGNUM(x)->len > RBIGNUM(y)->len) {
	len = RBIGNUM(x)->len + 1;
        z = x; x = y; y = z;
    }
    else {
	len = RBIGNUM(y)->len + 1;
    }
    z = bignew(len, sign);

    len = RBIGNUM(x)->len;
    for (i = 0, num = 0; i < len; i++) {
	num += (BDIGIT_DBL)BDIGITS(x)[i] + BDIGITS(y)[i];
	BDIGITS(z)[i] = BIGLO(num);
	num = BIGDN(num);
    }
    len = RBIGNUM(y)->len;
    while (num && i < len) {
	num += BDIGITS(y)[i];
	BDIGITS(z)[i++] = BIGLO(num);
	num = BIGDN(num);
    }
    while (i < len) {
	BDIGITS(z)[i] = BDIGITS(y)[i];
	i++;
    }
    BDIGITS(z)[i] = (BDIGIT)num;

    return z;
}

/*
 *  call-seq:
 *     big + other  => Numeric
 *
 *  Adds big and other, returning the result.
 */

VALUE
rb_big_plus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	/* fall through */
      case T_BIGNUM:
	return bignorm(bigadd(x, y, 1));

      case T_FLOAT:
	return rb_float_new(rb_big2dbl(x) + RFLOAT(y)->value);

      default:
	return rb_num_coerce_bin(x, y);
    }
}

/*
 *  call-seq:
 *     big - other  => Numeric
 *
 *  Subtracts other from big, returning the result.
 */

VALUE
rb_big_minus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	/* fall through */
      case T_BIGNUM:
	return bignorm(bigadd(x, y, 0));

      case T_FLOAT:
	return rb_float_new(rb_big2dbl(x) - RFLOAT(y)->value);

      default:
	return rb_num_coerce_bin(x, y);
    }
}

VALUE
rb_big_mul0(x, y)
    VALUE x, y;
{
    long i, j;
    BDIGIT_DBL n = 0;
    VALUE z;
    BDIGIT *zds;

    if (FIXNUM_P(x)) x = rb_int2big(FIX2LONG(x));
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
	return rb_float_new(rb_big2dbl(x) * RFLOAT(y)->value);

      default:
	return rb_num_coerce_bin(x, y);
    }

    j = RBIGNUM(x)->len + RBIGNUM(y)->len + 1;
    z = bignew(j, RBIGNUM(x)->sign==RBIGNUM(y)->sign);
    zds = BDIGITS(z);
    while (j--) zds[j] = 0;
    for (i = 0; i < RBIGNUM(x)->len; i++) {
	BDIGIT_DBL dd = BDIGITS(x)[i];
	if (dd == 0) continue;
	n = 0;
	for (j = 0; j < RBIGNUM(y)->len; j++) {
	    BDIGIT_DBL ee = n + (BDIGIT_DBL)dd * BDIGITS(y)[j];
	    n = zds[i + j] + ee;
	    if (ee) zds[i + j] = BIGLO(n);
	    n = BIGDN(n);
	}
	if (n) {
	    zds[i + j] = n;
	}
    }

    return z;
}

/*
 *  call-seq:
 *     big * other  => Numeric
 *
 *  Multiplies big and other, returning the result.
 */

VALUE
rb_big_mul(x, y)
    VALUE x, y;
{
    return bignorm(rb_big_mul0(x, y));
}

static void
bigdivrem(x, y, divp, modp)
    VALUE x, y;
    VALUE *divp, *modp;
{
    long nx = RBIGNUM(x)->len, ny = RBIGNUM(y)->len;
    long i, j;
    VALUE yy, z;
    BDIGIT *xds, *yds, *zds, *tds;
    BDIGIT_DBL t2;
    BDIGIT_DBL_SIGNED num;
    BDIGIT dd, q;

    if (BIGZEROP(y)) rb_num_zerodiv();
    yds = BDIGITS(y);
    if (nx < ny || (nx == ny && BDIGITS(x)[nx - 1] < BDIGITS(y)[ny - 1])) {
	if (divp) *divp = rb_int2big(0);
	if (modp) *modp = x;
	return;
    }
    xds = BDIGITS(x);
    if (ny == 1) {
	dd = yds[0];
	z = rb_big_clone(x);
	zds = BDIGITS(z);
	t2 = 0; i = nx;
	while (i--) {
	    t2 = BIGUP(t2) + zds[i];
	    zds[i] = (BDIGIT)(t2 / dd);
	    t2 %= dd;
	}
	RBIGNUM(z)->sign = RBIGNUM(x)->sign==RBIGNUM(y)->sign;
	if (modp) {
	    *modp = rb_uint2big((unsigned long)t2);
	    RBIGNUM(*modp)->sign = RBIGNUM(x)->sign;
	}
	if (divp) *divp = z;
	return;
    }
    z = bignew(nx==ny?nx+2:nx+1, RBIGNUM(x)->sign==RBIGNUM(y)->sign);
    zds = BDIGITS(z);
    if (nx==ny) zds[nx+1] = 0;
    while (!yds[ny-1]) ny--;

    dd = 0;
    q = yds[ny-1];
    while ((q & (1U<<(BITSPERDIG-1))) == 0) {
	q <<= 1;
	dd++;
    }
    if (dd) {
	yy = rb_big_clone(y);
	tds = BDIGITS(yy);
	j = 0;
	t2 = 0;
	while (j<ny) {
	    t2 += (BDIGIT_DBL)yds[j]<<dd;
	    tds[j++] = BIGLO(t2);
	    t2 = BIGDN(t2);
	}
	yds = tds;
	j = 0;
	t2 = 0;
	while (j<nx) {
	    t2 += (BDIGIT_DBL)xds[j]<<dd;
	    zds[j++] = BIGLO(t2);
	    t2 = BIGDN(t2);
	}
	zds[j] = (BDIGIT)t2;
    }
    else {
	zds[nx] = 0;
	j = nx;
	while (j--) zds[j] = xds[j];
    }

    j = nx==ny?nx+1:nx;
    do {
	if (zds[j] ==  yds[ny-1]) q = BIGRAD-1;
	else q = (BDIGIT)((BIGUP(zds[j]) + zds[j-1])/yds[ny-1]);
	if (q) {
	    i = 0; num = 0; t2 = 0;
	    do {			/* multiply and subtract */
		BDIGIT_DBL ee;
		t2 += (BDIGIT_DBL)yds[i] * q;
		ee = num - BIGLO(t2);
		num = (BDIGIT_DBL)zds[j - ny + i] + ee;
		if (ee) zds[j - ny + i] = BIGLO(num);
		num = BIGDN(num);
		t2 = BIGDN(t2);
	    } while (++i < ny);
	    num += zds[j - ny + i] - t2;/* borrow from high digit; don't update */
	    while (num) {		/* "add back" required */
		i = 0; num = 0; q--;
		do {
		    BDIGIT_DBL ee = num + yds[i];
		    num = (BDIGIT_DBL)zds[j - ny + i] + ee;
		    if (ee) zds[j - ny + i] = BIGLO(num);
		    num = BIGDN(num);
		} while (++i < ny);
		num--;
	    }
	}
	zds[j] = q;
    } while (--j >= ny);
    if (divp) {			/* move quotient down in z */
	*divp = rb_big_clone(z);
	zds = BDIGITS(*divp);
	j = (nx==ny ? nx+2 : nx+1) - ny;
	for (i = 0;i < j;i++) zds[i] = zds[i+ny];
	RBIGNUM(*divp)->len = i;
    }
    if (modp) {			/* normalize remainder */
	*modp = rb_big_clone(z);
	zds = BDIGITS(*modp);
	while (--ny && !zds[ny]); ++ny;
	if (dd) {
	    t2 = 0; i = ny;
	    while(i--) {
		t2 = (t2 | zds[i]) >> dd;
		q = zds[i];
		zds[i] = BIGLO(t2);
		t2 = BIGUP(q);
	    }
	}
	RBIGNUM(*modp)->len = ny;
	RBIGNUM(*modp)->sign = RBIGNUM(x)->sign;
    }
}

static void
bigdivmod(x, y, divp, modp)
    VALUE x, y;
    VALUE *divp, *modp;
{
    VALUE mod;

    bigdivrem(x, y, divp, &mod);
    if (RBIGNUM(x)->sign != RBIGNUM(y)->sign && !BIGZEROP(mod)) {
	if (divp) *divp = bigadd(*divp, rb_int2big(1), 0);
	if (modp) *modp = bigadd(mod, y, 1);
    }
    else {
	if (divp) *divp = *divp;
	if (modp) *modp = mod;
    }
}

/*
 *  call-seq:
 *     big / other     => Numeric
 *     big.div(other)  => Numeric
 *
 *  Divides big by other, returning the result.
 */

static VALUE
rb_big_div(x, y)
    VALUE x, y;
{
    VALUE z;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return rb_num_coerce_bin(x, y);
    }
    bigdivmod(x, y, &z, 0);

    return bignorm(z);
}

/*
 *  call-seq:
 *     big % other         => Numeric
 *     big.modulo(other)   => Numeric
 *
 *  Returns big modulo other. See Numeric.divmod for more
 *  information.
 */

static VALUE
rb_big_modulo(x, y)
    VALUE x, y;
{
    VALUE z;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return rb_num_coerce_bin(x, y);
    }
    bigdivmod(x, y, 0, &z);

    return bignorm(z);
}

/*
 *  call-seq:
 *     big.remainder(numeric)    => number
 *
 *  Returns the remainder after dividing <i>big</i> by <i>numeric</i>.
 *
 *     -1234567890987654321.remainder(13731)      #=> -6966
 *     -1234567890987654321.remainder(13731.24)   #=> -9906.22531493148
 */
static VALUE
rb_big_remainder(x, y)
    VALUE x, y;
{
    VALUE z;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return rb_num_coerce_bin(x, y);
    }
    bigdivrem(x, y, 0, &z);

    return bignorm(z);
}

static int
bdigbitsize(BDIGIT x)
{
    int size = 1;
    int nb = BITSPERDIG / 2;
    BDIGIT bits = (~0 << nb);

    if (!x) return 0;
    while (x > 1) {
	if (x & bits) {
	    size += nb;
	    x >>= nb;
	}
	x &= ~bits;
	nb /= 2;
	bits >>= nb;
    }

    return size;
}

static VALUE big_lshift _((VALUE, unsigned long));
static VALUE big_rshift _((VALUE, unsigned long));

static VALUE big_shift(x, n)
    VALUE x;
    int n;
{
    if (n < 0)
	return big_lshift(x, (unsigned int)n);
    else if (n > 0)
	return big_rshift(x, (unsigned int)n);
    return x;
}

/*
 *  call-seq:
 *     big.divmod(numeric)   => array
 *
 *  See <code>Numeric#divmod</code>.
 *
 */
VALUE
rb_big_divmod(x, y)
    VALUE x, y;
{
    VALUE div, mod;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = rb_int2big(FIX2LONG(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return rb_num_coerce_bin(x, y);
    }
    bigdivmod(x, y, &div, &mod);

    return rb_assoc_new(bignorm(div), bignorm(mod));
}

/*
 *  call-seq:
 *     big.quo(numeric) -> float
 *     big.fdiv(numeric) -> float
 *
 *  Returns the floating point result of dividing <i>big</i> by
 *  <i>numeric</i>.
 *
 *     -1234567890987654321.quo(13731)      #=> -89910996357705.5
 *     -1234567890987654321.quo(13731.24)   #=> -89909424858035.7
 *
 */

static VALUE
rb_big_quo(x, y)
    VALUE x, y;
{
    double dx = big2dbl(x);
    double dy;

    if (isinf(dx)) {
#define DBL_BIGDIG ((DBL_MANT_DIG + BITSPERDIG) / BITSPERDIG)
	VALUE z;
	int ex, ey;

	ex = (RBIGNUM(bigtrunc(x))->len - 1) * BITSPERDIG;
	ex += bdigbitsize(BDIGITS(x)[RBIGNUM(x)->len - 1]);
	ex -= 2 * DBL_BIGDIG * BITSPERDIG;
	if (ex) x = big_shift(x, ex);

	switch (TYPE(y)) {
	  case T_FIXNUM:
	    y = rb_int2big(FIX2LONG(y));
	  case T_BIGNUM: {
	    ey = (RBIGNUM(bigtrunc(y))->len - 1) * BITSPERDIG;
	    ey += bdigbitsize(BDIGITS(y)[RBIGNUM(y)->len - 1]);
	    ey -= DBL_BIGDIG * BITSPERDIG;
	    if (ey) y = big_shift(y, ey);
	  bignum:
	    bigdivrem(x, y, &z, 0);
	    return rb_float_new(ldexp(big2dbl(z), ex - ey));
	  }
	  case T_FLOAT:
	    y = dbl2big(ldexp(frexp(RFLOAT(y)->value, &ey), DBL_MANT_DIG));
	    ey -= DBL_MANT_DIG;
	    goto bignum;
	}
    }
    switch (TYPE(y)) {
      case T_FIXNUM:
	dy = (double)FIX2LONG(y);
	break;

      case T_BIGNUM:
	dy = rb_big2dbl(y);
	break;

      case T_FLOAT:
	dy = RFLOAT(y)->value;
	break;

      default:
	return rb_num_coerce_bin(x, y);
    }
    return rb_float_new(dx / dy);
}

static VALUE
bigsqr(x)
    VALUE x;
{
    long len = RBIGNUM(x)->len, k = len / 2, i;
    VALUE a, b, a2, z;
    BDIGIT_DBL num;

    if (len < 4000 / BITSPERDIG) {
	return rb_big_mul0(x, x);
    }

    a = bignew(len - k, 1);
    MEMCPY(BDIGITS(a), BDIGITS(x) + k, BDIGIT, len - k);
    b = bignew(k, 1);
    MEMCPY(BDIGITS(b), BDIGITS(x), BDIGIT, k);

    a2 = bigtrunc(bigsqr(a));
    z = bigsqr(b);
    REALLOC_N(RBIGNUM(z)->digits, BDIGIT, (len = 2 * k + RBIGNUM(a2)->len) + 1);
    while (RBIGNUM(z)->len < 2 * k) BDIGITS(z)[RBIGNUM(z)->len++] = 0;
    MEMCPY(BDIGITS(z) + 2 * k, BDIGITS(a2), BDIGIT, RBIGNUM(a2)->len);
    RBIGNUM(z)->len = len;
    a2 = bigtrunc(rb_big_mul0(a, b));
    len = RBIGNUM(a2)->len;
    TRAP_BEG;
    for (i = 0, num = 0; i < len; i++) {
	num += (BDIGIT_DBL)BDIGITS(z)[i + k] + ((BDIGIT_DBL)BDIGITS(a2)[i] << 1);
	BDIGITS(z)[i + k] = BIGLO(num);
	num = BIGDN(num);
    }
    TRAP_END;
    if (num) {
	len = RBIGNUM(z)->len;
	for (i += k; i < len && num; ++i) {
	    num += (BDIGIT_DBL)BDIGITS(z)[i];
	    BDIGITS(z)[i] = BIGLO(num);
	    num = BIGDN(num);
	}
	if (num) {
	    BDIGITS(z)[RBIGNUM(z)->len++] = BIGLO(num);
	}
    }
    return bigtrunc(z);
}

/*
 *  call-seq:
 *     big ** exponent   #=> numeric
 *
 *  Raises _big_ to the _exponent_ power (which may be an integer, float,
 *  or anything that will coerce to a number). The result may be
 *  a Fixnum, Bignum, or Float
 *
 *    123456789 ** 2      #=> 15241578750190521
 *    123456789 ** 1.2    #=> 5126464716.09932
 *    123456789 ** -2     #=> 6.5610001194102e-17
 */

VALUE
rb_big_pow(x, y)
    VALUE x, y;
{
    double d;
    long yy;

    if (y == INT2FIX(0)) return INT2FIX(1);
    switch (TYPE(y)) {
      case T_FLOAT:
	d = RFLOAT(y)->value;
	break;

      case T_BIGNUM:
	rb_warn("in a**b, b may be too big");
	d = rb_big2dbl(y);
	break;

      case T_FIXNUM:
	yy = FIX2LONG(y);
	if (yy > 0) {
	    VALUE z = 0;
	    long mask;
	    const long BIGLEN_LIMIT = 1024*1024 / SIZEOF_BDIGITS;

	    if ((RBIGNUM(x)->len > BIGLEN_LIMIT) ||
		(RBIGNUM(x)->len > BIGLEN_LIMIT / yy)) {
		rb_warn("in a**b, b may be too big");
		d = (double)yy;
		break;
	    }
	    for (mask = FIXNUM_MAX + 1; mask; mask >>= 1) {
		if (z) z = bigtrunc(bigsqr(z));
		if (yy & mask) {
		    z = z ? bigtrunc(rb_big_mul0(z, x)) : x;
		}
	    }
	    return bignorm(z);
	}
	d = (double)yy;
	break;

      default:
	return rb_num_coerce_bin(x, y);
    }
    return rb_float_new(pow(rb_big2dbl(x), d));
}

/*
 * call-seq:
 *     big & numeric   =>  integer
 *
 * Performs bitwise +and+ between _big_ and _numeric_.
 */

VALUE
rb_big_and(xx, yy)
    VALUE xx, yy;
{
    volatile VALUE x, y, z;
    BDIGIT *ds1, *ds2, *zds;
    long i, l1, l2;
    char sign;

    x = xx;
    y = rb_to_int(yy);
    if (FIXNUM_P(y)) {
	y = rb_int2big(FIX2LONG(y));
    }
    if (!RBIGNUM(y)->sign) {
	y = rb_big_clone(y);
	get2comp(y);
    }
    if (!RBIGNUM(x)->sign) {
	x = rb_big_clone(x);
	get2comp(x);
    }
    if (RBIGNUM(x)->len > RBIGNUM(y)->len) {
	l1 = RBIGNUM(y)->len;
	l2 = RBIGNUM(x)->len;
	ds1 = BDIGITS(y);
	ds2 = BDIGITS(x);
	sign = RBIGNUM(y)->sign;
    }
    else {
	l1 = RBIGNUM(x)->len;
	l2 = RBIGNUM(y)->len;
	ds1 = BDIGITS(x);
	ds2 = BDIGITS(y);
	sign = RBIGNUM(x)->sign;
    }
    z = bignew(l2, RBIGNUM(x)->sign || RBIGNUM(y)->sign);
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] & ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?0:ds2[i];
    }
    if (!RBIGNUM(z)->sign) get2comp(z);
    return bignorm(z);
}

/*
 * call-seq:
 *     big | numeric   =>  integer
 *
 * Performs bitwise +or+ between _big_ and _numeric_.
 */

VALUE
rb_big_or(xx, yy)
    VALUE xx, yy;
{
    volatile VALUE x, y, z;
    BDIGIT *ds1, *ds2, *zds;
    long i, l1, l2;
    char sign;

    x = xx;
    y = rb_to_int(yy);
    if (FIXNUM_P(y)) {
	y = rb_int2big(FIX2LONG(y));
    }
    if (!RBIGNUM(y)->sign) {
	y = rb_big_clone(y);
	get2comp(y);
    }
    if (!RBIGNUM(x)->sign) {
	x = rb_big_clone(x);
	get2comp(x);
    }
    if (RBIGNUM(x)->len > RBIGNUM(y)->len) {
	l1 = RBIGNUM(y)->len;
	l2 = RBIGNUM(x)->len;
	ds1 = BDIGITS(y);
	ds2 = BDIGITS(x);
	sign = RBIGNUM(y)->sign;
    }
    else {
	l1 = RBIGNUM(x)->len;
	l2 = RBIGNUM(y)->len;
	ds1 = BDIGITS(x);
	ds2 = BDIGITS(y);
	sign = RBIGNUM(x)->sign;
    }
    z = bignew(l2, RBIGNUM(x)->sign && RBIGNUM(y)->sign);
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] | ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?ds2[i]:(BIGRAD-1);
    }
    if (!RBIGNUM(z)->sign) get2comp(z);

    return bignorm(z);
}

/*
 * call-seq:
 *     big ^ numeric   =>  integer
 *
 * Performs bitwise +exclusive or+ between _big_ and _numeric_.
 */

VALUE
rb_big_xor(xx, yy)
    VALUE xx, yy;
{
    volatile VALUE x, y;
    VALUE z;
    BDIGIT *ds1, *ds2, *zds;
    long i, l1, l2;
    char sign;

    x = xx;
    y = rb_to_int(yy);
    if (FIXNUM_P(y)) {
	y = rb_int2big(FIX2LONG(y));
    }
    if (!RBIGNUM(y)->sign) {
	y = rb_big_clone(y);
	get2comp(y);
    }
    if (!RBIGNUM(x)->sign) {
	x = rb_big_clone(x);
	get2comp(x);
    }
    if (RBIGNUM(x)->len > RBIGNUM(y)->len) {
	l1 = RBIGNUM(y)->len;
	l2 = RBIGNUM(x)->len;
	ds1 = BDIGITS(y);
	ds2 = BDIGITS(x);
	sign = RBIGNUM(y)->sign;
    }
    else {
	l1 = RBIGNUM(x)->len;
	l2 = RBIGNUM(y)->len;
	ds1 = BDIGITS(x);
	ds2 = BDIGITS(y);
	sign = RBIGNUM(x)->sign;
    }
    RBIGNUM(x)->sign = RBIGNUM(x)->sign?1:0;
    RBIGNUM(y)->sign = RBIGNUM(y)->sign?1:0;
    z = bignew(l2, !(RBIGNUM(x)->sign ^ RBIGNUM(y)->sign));
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] ^ ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?ds2[i]:~ds2[i];
    }
    if (!RBIGNUM(z)->sign) get2comp(z);

    return bignorm(z);
}

static VALUE check_shiftdown _((VALUE, VALUE));
static VALUE
check_shiftdown(y, x)
    VALUE y, x;
{
    if (!RBIGNUM(x)->len) return INT2FIX(0);
    if (RBIGNUM(y)->len > SIZEOF_LONG / SIZEOF_BDIGITS) {
	return RBIGNUM(x)->sign ? INT2FIX(0) : INT2FIX(-1);
    }
    return Qnil;
}

/*
 * call-seq:
 *     big << numeric   =>  integer
 *
 * Shifts big left _numeric_ positions (right if _numeric_ is negative).
 */

VALUE
rb_big_lshift(x, y)
    VALUE x, y;
{
    long shift;
    int neg = 0;

    for (;;) {
	if (FIXNUM_P(y)) {
	    shift = FIX2LONG(y);
	    if (shift < 0) {
		neg = 1;
		shift = -shift;
	    }
	    break;
	}
	else if (TYPE(y) == T_BIGNUM) {
	    if (!RBIGNUM(y)->sign) {
		VALUE t = check_shiftdown(y, x);
		if (!NIL_P(t)) return t;
		neg = 1;
	    }
	    shift = big2ulong(y, "long");
	    break;
	}
	y = rb_to_int(y);
    }

    x = neg ? big_rshift(x, shift) : big_lshift(x, shift);
    return bignorm(x);
}

static VALUE
big_lshift(x, shift)
    VALUE x;
    unsigned long shift;
{
    BDIGIT *xds, *zds;
    long s1 = shift/BITSPERDIG;
    int s2 = shift%BITSPERDIG;
    VALUE z;
    BDIGIT_DBL num = 0;
    long len, i;

    len = RBIGNUM(x)->len;
    z = bignew(len+s1+1, RBIGNUM(x)->sign);
    zds = BDIGITS(z);
    for (i=0; i<s1; i++) {
	*zds++ = 0;
    }
    xds = BDIGITS(x);
    for (i=0; i<len; i++) {
	num = num | (BDIGIT_DBL)*xds++<<s2;
	*zds++ = BIGLO(num);
	num = BIGDN(num);
    }
    *zds = BIGLO(num);
    return z;
}

/*
 * call-seq:
 *     big >> numeric   =>  integer
 *
 * Shifts big right _numeric_ positions (left if _numeric_ is negative).
 */

VALUE
rb_big_rshift(x, y)
    VALUE x, y;
{
    long shift;
    int neg = 0;

    for (;;) {
	if (FIXNUM_P(y)) {
	    shift = FIX2LONG(y);
	    if (shift < 0) {
		neg = 1;
		shift = -shift;
	    }
	    break;
	}
	else if (TYPE(y) == T_BIGNUM) {
	    if (RBIGNUM(y)->sign) {
		VALUE t = check_shiftdown(y, x);
		if (!NIL_P(t)) return t;
	    }
	    else {
		neg = 1;
	    }
	    shift = big2ulong(y, "long");
	    break;
	}
	y = rb_to_int(y);
    }

    x = neg ? big_lshift(x, shift) : big_rshift(x, shift);
    return bignorm(x);
}

static VALUE
big_rshift(x, shift)
    VALUE x;
    unsigned long shift;
{
    BDIGIT *xds, *zds;
    long s1 = shift/BITSPERDIG;
    int s2 = shift%BITSPERDIG;
    VALUE z;
    BDIGIT_DBL num = 0;
    long i, j;
    volatile VALUE save_x;

    if (s1 > RBIGNUM(x)->len) {
	if (RBIGNUM(x)->sign)
	    return INT2FIX(0);
	else
	    return INT2FIX(-1);
    }
    if (!RBIGNUM(x)->sign) {
	save_x = x = rb_big_clone(x);
	get2comp(x);
    }
    xds = BDIGITS(x);
    i = RBIGNUM(x)->len; j = i - s1;
    if (j == 0) {
	if (RBIGNUM(x)->sign) return INT2FIX(0);
	else return INT2FIX(-1);
    }
    z = bignew(j, RBIGNUM(x)->sign);
    if (!RBIGNUM(x)->sign) {
	num = ((BDIGIT_DBL)~0) << BITSPERDIG;
    }
    zds = BDIGITS(z);
    while (i--, j--) {
	num = (num | xds[i]) >> s2;
	zds[j] = BIGLO(num);
	num = BIGUP(xds[i]);
    }
    if (!RBIGNUM(x)->sign) {
	get2comp(z);
    }
    return z;
}

/*
 *  call-seq:
 *     big[n] -> 0, 1
 *
 *  Bit Reference---Returns the <em>n</em>th bit in the (assumed) binary
 *  representation of <i>big</i>, where <i>big</i>[0] is the least
 *  significant bit.
 *
 *     a = 9**15
 *     50.downto(0) do |n|
 *       print a[n]
 *     end
 *
 *  <em>produces:</em>
 *
 *     000101110110100000111000011110010100111100010111001
 *
 */

static VALUE
rb_big_aref(x, y)
    VALUE x, y;
{
    BDIGIT *xds;
    BDIGIT_DBL num;
    unsigned long shift;
    long i, s1, s2;

    if (TYPE(y) == T_BIGNUM) {
	if (!RBIGNUM(y)->sign)
	    return INT2FIX(0);
	if (RBIGNUM(bigtrunc(y))->len > SIZEOF_LONG/SIZEOF_BDIGITS) {
	  out_of_range:
	    return RBIGNUM(x)->sign ? INT2FIX(0) : INT2FIX(1);
	}
	shift = big2ulong(y, "long");
    }
    else {
	i = NUM2LONG(y);
	if (i < 0) return INT2FIX(0);
	shift = (VALUE)i;
    }
    s1 = shift/BITSPERDIG;
    s2 = shift%BITSPERDIG;

    if (s1 >= RBIGNUM(x)->len) goto out_of_range;
    if (!RBIGNUM(x)->sign) {
	xds = BDIGITS(x);
	i = 0; num = 1;
	while (num += ~xds[i], ++i <= s1) {
	    num = BIGDN(num);
	}
    }
    else {
	num = BDIGITS(x)[s1];
    }
    if (num & ((BDIGIT_DBL)1<<s2))
	return INT2FIX(1);
    return INT2FIX(0);
}

/*
 * call-seq:
 *   big.hash   => fixnum
 *
 * Compute a hash based on the value of _big_.
 */

static VALUE
rb_big_hash(x)
    VALUE x;
{
    long i, len, key;
    BDIGIT *digits;

    key = 0; digits = BDIGITS(x); len = RBIGNUM(x)->len;
    for (i=0; i<len; i++) {
	key ^= *digits++;
    }
    return LONG2FIX(key);
}

/*
 * MISSING: documentation
 */

static VALUE
rb_big_coerce(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	return rb_assoc_new(rb_int2big(FIX2LONG(y)), x);
    }
    else if (TYPE(y) == T_BIGNUM) {
       return rb_assoc_new(y, x);
    }
    else {
	rb_raise(rb_eTypeError, "can't coerce %s to Bignum",
		 rb_obj_classname(y));
    }
    /* not reached */
    return Qnil;
}

/*
 *  call-seq:
 *     big.abs -> aBignum
 *
 *  Returns the absolute value of <i>big</i>.
 *
 *     -1234567890987654321.abs   #=> 1234567890987654321
 */

static VALUE
rb_big_abs(x)
    VALUE x;
{
    if (!RBIGNUM(x)->sign) {
	x = rb_big_clone(x);
	RBIGNUM(x)->sign = 1;
    }
    return x;
}

VALUE
rb_big_rand(max, rand_buf)
    VALUE max;
    double *rand_buf;
{
    VALUE v;
    long len = RBIGNUM(max)->len;

    if (BIGZEROP(max)) {
	return rb_float_new(rand_buf[0]);
    }
    v = bignew(len,1);
    len--;
    BDIGITS(v)[len] = BDIGITS(max)[len] * rand_buf[len];
    while (len--) {
	BDIGITS(v)[len] = ((BDIGIT)~0) * rand_buf[len];
    }

    return v;
}

/*
 *  call-seq:
 *     big.size -> integer
 *
 *  Returns the number of bytes in the machine representation of
 *  <i>big</i>.
 *
 *     (256**10 - 1).size   #=> 12
 *     (256**20 - 1).size   #=> 20
 *     (256**40 - 1).size   #=> 40
 */

static VALUE
rb_big_size(big)
    VALUE big;
{
    return LONG2FIX(RBIGNUM(big)->len*SIZEOF_BDIGITS);
}

/*
 *  Bignum objects hold integers outside the range of
 *  Fixnum. Bignum objects are created
 *  automatically when integer calculations would otherwise overflow a
 *  Fixnum. When a calculation involving
 *  Bignum objects returns a result that will fit in a
 *  Fixnum, the result is automatically converted.
 *
 *  For the purposes of the bitwise operations and <code>[]</code>, a
 *  Bignum is treated as if it were an infinite-length
 *  bitstring with 2's complement representation.
 *
 *  While Fixnum values are immediate, Bignum
 *  objects are not---assignment and parameter passing work with
 *  references to objects, not the objects themselves.
 *
 */

void
Init_Bignum()
{
    rb_cBignum = rb_define_class("Bignum", rb_cInteger);

    rb_define_method(rb_cBignum, "to_s", rb_big_to_s, -1);
    rb_define_method(rb_cBignum, "coerce", rb_big_coerce, 1);
    rb_define_method(rb_cBignum, "-@", rb_big_uminus, 0);
    rb_define_method(rb_cBignum, "+", rb_big_plus, 1);
    rb_define_method(rb_cBignum, "-", rb_big_minus, 1);
    rb_define_method(rb_cBignum, "*", rb_big_mul, 1);
    rb_define_method(rb_cBignum, "/", rb_big_div, 1);
    rb_define_method(rb_cBignum, "%", rb_big_modulo, 1);
    rb_define_method(rb_cBignum, "div", rb_big_div, 1);
    rb_define_method(rb_cBignum, "divmod", rb_big_divmod, 1);
    rb_define_method(rb_cBignum, "modulo", rb_big_modulo, 1);
    rb_define_method(rb_cBignum, "remainder", rb_big_remainder, 1);
    rb_define_method(rb_cBignum, "quo", rb_big_quo, 1);
    rb_define_method(rb_cBignum, "fdiv", rb_big_quo, 1);
    rb_define_method(rb_cBignum, "**", rb_big_pow, 1);
    rb_define_method(rb_cBignum, "&", rb_big_and, 1);
    rb_define_method(rb_cBignum, "|", rb_big_or, 1);
    rb_define_method(rb_cBignum, "^", rb_big_xor, 1);
    rb_define_method(rb_cBignum, "~", rb_big_neg, 0);
    rb_define_method(rb_cBignum, "<<", rb_big_lshift, 1);
    rb_define_method(rb_cBignum, ">>", rb_big_rshift, 1);
    rb_define_method(rb_cBignum, "[]", rb_big_aref, 1);

    rb_define_method(rb_cBignum, "<=>", rb_big_cmp, 1);
    rb_define_method(rb_cBignum, "==", rb_big_eq, 1);
    rb_define_method(rb_cBignum, "eql?", rb_big_eql, 1);
    rb_define_method(rb_cBignum, "hash", rb_big_hash, 0);
    rb_define_method(rb_cBignum, "to_f", rb_big_to_f, 0);
    rb_define_method(rb_cBignum, "abs", rb_big_abs, 0);
    rb_define_method(rb_cBignum, "size", rb_big_size, 0);
}
