/************************************************

  bignum.c -

  $Author: matz $
  $Date: 1994/06/27 15:48:21 $
  created at: Fri Jun 10 00:48:55 JST 1994

************************************************/

#include "ruby.h"
#include <ctype.h>

extern VALUE C_Integer;
VALUE C_Bignum;

#define BDIGITS(x) RBIGNUM(x)->digits
#define BITSPERDIG (sizeof(USHORT)*CHAR_BIT)
#define BIGRAD (1L << BITSPERDIG)
#define DIGSPERLONG ((UINT)(sizeof(long)/sizeof(USHORT)))
#define BIGUP(x) ((unsigned long)(x) << BITSPERDIG)
#define BIGDN(x) ((x) >> BITSPERDIG)
#define BIGLO(x) ((x) & (BIGRAD-1))

#define MAX(a,b) ((a)>(b)?(a):(b))
#define MIN(a,b) ((a)<(b)?(a):(b))

static VALUE
bignew_1(class, len, sign)
    VALUE class;
    UINT len;
    char sign;
{
    NEWOBJ(big, struct RBignum);
    OBJSETUP(big, C_Bignum, T_BIGNUM);
    big->sign = sign;
    big->len = len;
    BDIGITS(big) = ALLOC_N(USHORT, len);

    return (VALUE)big;
}

#define bignew(len,sign) bignew_1(C_Bignum,len,sign)

static VALUE
Fbig_new(class, y)
    VALUE class;
    struct RBignum *y;
{
    Check_Type(y, T_BIGNUM);
    return bignew_1(class, y->len, y->sign);
}

VALUE
Fbig_clone(x)
    struct RBignum *x;
{
    VALUE z = bignew_1(CLASS_OF(x), x->len, x->sign);

    bcopy(BDIGITS(x), BDIGITS(z), x->len*sizeof(USHORT));
    return (VALUE)z;
}

void
big_2comp(x)			/* get 2's complement */
    struct RBignum *x;
{
    UINT i = x->len;
    USHORT *ds = BDIGITS(x);
    long num;

    while (i--) ds[i] = ~ds[i];
    i = 0; num = 1;
    do {
	num += (long)ds[i];
	ds[i++] = BIGLO(num);
	num = BIGDN(num);
    } while (i < x->len);
}

VALUE
bignorm(x)
    struct RBignum *x;
{
    UINT len = x->len;
    USHORT *ds = BDIGITS(x);

    while (len-- && !ds[len]) ;
    x->len = ++len;
    if (len*sizeof(USHORT) <= sizeof(VALUE)) {
	long num = 0;
	while (len--) {
	    num = BIGUP(num) + ds[len];
	}
	if (x->sign) {
	    if (POSFIXABLE(num)) return INT2FIX(num);
	}
	else if (NEGFIXABLE(-num)) return INT2FIX(-num);
    }
    return (VALUE)x;
}

VALUE
uint2big(n)
    UINT n;
{
    UINT i = 0;
    USHORT *digits;
    struct RBignum *big;

    i = 0;
    big = (struct RBignum*)bignew(DIGSPERLONG, 1);
    digits = BDIGITS(big);
    while (i < DIGSPERLONG) {
	digits[i++] = BIGLO(n);
	n = BIGDN(n);
    }

    i = DIGSPERLONG;
    while (i-- && !digits[i]) ;
    big->len = i+1;
    return (VALUE)big;
}

VALUE
int2big(n)
    int n;
{
    int neg = 0;
    struct RBignum *big;

    if (n < 0) {
	n = -n;
	neg = 1;
    }
    big = (struct RBignum*)uint2big(n);
    if (neg) {
	big->sign = FALSE;
    }
    return (VALUE)big;
}

VALUE
uint2inum(n)
    UINT n;
{
    if (POSFIXABLE(n)) return INT2FIX(n);
    return uint2big(n);
}

VALUE
int2inum(n)
    int n;
{
    if (FIXABLE(n)) return INT2FIX(n);
    return int2big(n);
}

VALUE
str2inum(str, base)
    char *str;
    int base;
{
    char sign = 1, c;
    unsigned long num;
    UINT len, blen = 1, i;
    VALUE z;
    USHORT *zds;

    while (isspace(*str)) str++;
    if (*str == '-') {
	str++;
	sign = 0;
    }
    if (base == 0) {
	if (*str == '0') {
	    str++;
	    if (*str == 'x' || *str == 'X') {
		str++;
		base = 16;
	    }
	    else {
		base = 8;
	    }
	    if (*str == '\0') return INT2FIX(0);
	}
	else {
	    base = 10;
	}
    }
    len = strlen(str);
    if (base == 8) {
	len = 3*len*sizeof(char);
    }
    else {			/* base == 10 or 16 */
	len = 4*len*sizeof(char);
    }

    if (len <= (sizeof(VALUE)*CHAR_BIT)) {
	int result = strtoul(str, Qnil, base);

	if (!sign) result = -result;
	if (FIXABLE(result)) return INT2FIX(result);
	return int2big(result);
    }
    len = (len/(sizeof(USHORT)*CHAR_BIT))+1;

    z = bignew(len, sign);
    zds = BDIGITS(z);
    for (i=len;i--;) zds[i]=0;
    while (c = *str++) {
	switch (c) {
	  case '0': case '1': case '2': case '3': case '4':
	  case '5': case '6': case '7': case '8': case '9':
	    c = c - '0';
	    break;
	  case 'a': case 'b': case 'c':
	  case 'd': case 'e': case 'f':
	    c = c - 'a' + 10;
	    break;
	  case 'A': case 'B': case 'C':
	  case 'D': case 'E': case 'F':
	    c = c - 'A' + 10;
	    break;
	  default:
	    c = base;
	    break;
	}
	if (c >= base) break;
	i = 0;
	num = c;
	for (;;) {
	    while (i<blen) {
		num += zds[i]*base;
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
    return bignorm(z);
}

static char hexmap[] = "0123456789abcdef";
VALUE
big2str(x, base)
    struct RBignum *x;
    int base;
{
    VALUE t;
    USHORT *ds;
    UINT i, j, hbase;
    VALUE ss;
    char *s, c;

    if (FIXNUM_P(x)) {
	return fix2str(x, base);
    }
    i = x->len;
    if (x->len == 0) return str_new2("0");
    if (base == 10) {
	j = (sizeof(USHORT)/sizeof(char)*CHAR_BIT*i*241L)/800+2;
	hbase = 10000;
    }
    else if (base == 16) {
	j = (sizeof(USHORT)/sizeof(char)*CHAR_BIT*i)/4+2;
	hbase = 0x10000;
    }
    else if (base == 8) {
	j = (sizeof(USHORT)/sizeof(char)*CHAR_BIT*i)+2;
	hbase = 010000;
    }
    else if (base == 2) {
	j = (sizeof(USHORT)*CHAR_BIT*i)+2;
	hbase = 020;
    }
    else {
	Fail("bignum cannot treat base %d", base);
    }

    GC_LINK;
    GC_PRO3(t, Fbig_clone(x));
    ds = BDIGITS(t);
    GC_PRO3(ss, str_new(0, j));
    s = RSTRING(ss)->ptr;

    s[0] = x->sign ? '+' : '-';
    while (i && j) {
	int k = i;
	unsigned long num = 0;
	while (k--) {
	    num = BIGUP(num) + ds[k];
	    ds[k] = num / hbase;
	    num %= hbase;
	}
	if (ds[i-1] == 0) i--;
	k = 4;
	while (k--) {
	    c = num % base;
	    s[--j] = hexmap[(int)c];
	    num /= base;
	    if (i == 0 && num == 0) break;
	}
    }
    while (s[j] == '0') j++;
    RSTRING(ss)->len -= x->sign?j:j-1;
    memmove(x->sign?s:s+1, s+j, RSTRING(ss)->len);
    s[RSTRING(ss)->len] = '\0';
    GC_UNLINK;
    return ss;
}

static VALUE
Fbig_to_s(x)
    struct RBignum *x;
{
    return big2str(x, 10);
}

int
big2int(x)
    struct RBignum *x;
{
    unsigned long num;
    UINT len = x->len;
    USHORT *ds;

    if (len > sizeof(long)/sizeof(USHORT))
	Fail("Bignum too big to convert into fixnum");
    ds = BDIGITS(x);
    num = 0;
    while (len--) {
	num = BIGUP(num);
	num += ds[len];
    }
    if (!x->sign) return -num;
    return num;
}

VALUE
Fbig_to_i(x)
    VALUE x;
{
    int v = big2int(x);

    if (FIXABLE(v)) {
	return INT2FIX(v);
    }
    return x;
}

VALUE
dbl2big(d)
    double d;
{
    UINT i = 0;
    long c;
    USHORT *digits;
    VALUE z;
    double u = (d < 0)?-d:d;

    while (0 != floor(u)) {
	u /= BIGRAD;
	i++;
    }
    GC_LINK;
    GC_PRO3(z, bignew(i, d>=0));
    digits = BDIGITS(z);
    while (i--) {
	u *= BIGRAD;
	c = floor(u);
	u -= c;
	digits[i] = c;
    }
    GC_UNLINK;
    return bignorm(z);
}

double
big2dbl(x)
    struct RBignum *x;
{
    double d = 0.0;
    UINT i = x->len;
    USHORT *ds = BDIGITS(x);

    while (i--) d = ds[i] + BIGRAD*d;
    if (!x->sign) d = -d;
    return d;
}

VALUE
Fbig_to_f(x)
    VALUE x;
{
    return float_new(big2dbl(x));
}

static VALUE
Fbig_uminus(x)
    struct RBignum *x;
{
    VALUE z = Fbig_clone(x);

    RBIGNUM(z)->sign = !x->sign;

    return bignorm(z);
}

static VALUE
bigadd(x, y, sign)
    struct RBignum *x, *y;
    char sign;
{
    struct RBignum *z;
    USHORT *zds;
    long num;
    UINT i, len;

    len = MAX(x->len, y->len) + 1;
    z = (struct RBignum*)bignew(len, sign==y->sign);
    zds = BDIGITS(z);

    i = len;
    while (i--) zds[i] = 0;
    i = y->len;
    while (i--) zds[i] = BDIGITS(y)[i];

    GC_LINK;
    GC_PRO(z);
    i = 0; num = 0;
    if (x->sign == z->sign) {
	do {
	    num += (long)zds[i] + BDIGITS(x)[i];
	    zds[i++] = BIGLO(num);
	    num = BIGDN(num);
	} while (i < x->len);
	if (num) {
	    while (i < y->len) {
		num += zds[i];
		zds[i++] = BIGLO(num);
		num = BIGDN(num);
	    }
	    BDIGITS(z)[i] = num;
	}
    }
    else {
	do {
	    num += (long)zds[i] - BDIGITS(x)[i];
	    if (num < 0) {
		zds[i] = num + BIGRAD;
		num = -1;
	    }
	    else {
		zds[i] = BIGLO(num);
		num = 0;
	    }
	} while (++i < x->len);
	if (num && x->len == y->len) {
	    num = 1; i = 0;
	    z->sign = 1;
	    do {
		num += (BIGRAD-1) - zds[i];
		zds[i++] = BIGLO(num);
		num = BIGDN(num);
	    } while (i < y->len);
	}
	else while (i < y->len) {
	    num += zds[i];
	    if (num < 0) {
		zds[i++] = num + BIGRAD;
		num = -1;
	    }
	    else {
		zds[i++] = BIGLO(num);
		num = 0;
	    }
	}
    }
    GC_UNLINK;
    return bignorm(z);
}

VALUE
Fbig_plus(x, y)
    VALUE x, y;
{
    VALUE z;

    GC_LINK;
    GC_PRO(y);
    if (FIXNUM_P(y)) y = int2big(FIX2INT(y));
    else {
	Check_Type(x, T_BIGNUM);
    }
    z = bigadd(x, y, 1);
    GC_UNLINK;
    return z;
}

VALUE
Fbig_minus(x, y)
    VALUE x, y;
{
    GC_LINK;
    GC_PRO(y);
    if (FIXNUM_P(y)) y = int2big(FIX2INT(y));
    else {
	Check_Type(y, T_BIGNUM);
    }
    x = bigadd(x, y, 0);
    GC_UNLINK;

    return x;
}

VALUE
Fbig_mul(x, y)
    struct RBignum *x, *y;
{
    UINT i = 0, j;
    unsigned long n = 0;
    VALUE z;
    USHORT *zds;

    GC_LINK;
    GC_PRO(y);
    if (FIXNUM_P(y)) y = (struct RBignum*)int2big(FIX2INT(y));
    else {
	Check_Type(y, T_BIGNUM);
    }

    j = x->len + y->len + 1;
    z = bignew(j, x->sign==y->sign);
    zds = BDIGITS(z);
    while (j--) zds[j] = 0;
    do {
	j = 0;
	if (BDIGITS(x)[i]) {
	    do {
		n += zds[i + j] + ((unsigned long)BDIGITS(x)[i]*BDIGITS(y)[j]);
		zds[i + j++] = BIGLO(n);
		n = BIGDN(n);
	    } while (j < y->len);
	    if (n) {
		zds[i + j] = n;
		n = 0;
	    }
	}
    } while (++i < x->len);
    GC_UNLINK;

    return bignorm(z);
}

static void
bigdivmod(x, y, div, mod)
    struct RBignum *x, *y;
    VALUE *div, *mod;
{
    UINT nx = x->len, ny = y->len, i, j;
    VALUE z;
    USHORT *xds, *yds, *zds, *tds;
    unsigned long t2;
    long num;
    USHORT dd, q;

    yds = BDIGITS(y);
    if (ny == 0 && yds[0] == 0) Fail("divided by 0");
    if (nx < ny) {
	if (div) *div = INT2FIX(0);
	if (mod) *mod = bignorm(x);
	return;
    }
    xds = BDIGITS(x);
    if (ny == 1) {
	dd = yds[0];
	GC_LINK;
	GC_PRO3(z, Fbig_clone(x));
	zds = BDIGITS(z);
	t2 = 0; i = nx;
	while(i--) {
	    t2 = BIGUP(t2) + zds[i];
	    zds[i] = t2 / dd;
	    t2 %= dd;
	}
	if (div) *div = bignorm(z);
	if (mod) {
	    if (!y->sign) t2 = -t2;
	    *mod = FIX2INT(t2);
	}
	GC_UNLINK;
	return;
    }
    GC_LINK;
    GC_PRO3(z, bignew(nx==ny?nx+2:nx+1, x->sign==y->sign));
    zds = BDIGITS(z);
    if (nx==ny) zds[nx+1] = 0;
    while (!yds[ny-1]) ny--;
    if ((dd = BIGRAD/(yds[ny-1]+1)) != 1) {
	GC_PRO3(y, (struct RBignum*)Fbig_clone(y));
	tds = BDIGITS(y);
	j = 0;
	num = 0;
	while (j<ny) {
	    num += (unsigned long)yds[j]*dd;
	    tds[j++] = BIGLO(num);
	    num = BIGDN(num);
	}
	yds = tds;
	j = 0;
	num = 0;
	while (j<nx) {
	    num += (unsigned long)xds[j]*dd;
	    zds[j++] = BIGLO(num);
	    num = BIGDN(num);
	}
	zds[j] = num;
    }
    else {
	zds[nx] = 0;
	j = nx;
	while (j--) zds[j] = xds[j];
    }
    j = nx==ny?nx+1:nx;
    do {
	if (zds[j] ==  yds[ny-1]) q = BIGRAD-1;
	else q = (BIGUP(zds[j]) + zds[j-1])/yds[ny-1];
	if (q) {
	    i = 0; num = 0; t2 = 0;
	    do {			/* multiply and subtract */
		t2 += (unsigned long)yds[i] * q;
		num += zds[j - ny + i] - BIGLO(t2);
		if (num < 0) {
		    zds[j - ny + i] = num + BIGRAD;
		    num = -1;
		}
		else {
		    zds[j - ny + i] = num;
		    num = 0;
		}
		t2 = BIGDN(t2);
	    } while (++i < ny);
	    num += zds[j - ny + i] - t2; /* borrow from high digit; don't update */
	    while (num) {		/* "add back" required */
		i = 0; num = 0; q--;
		do {
		    num += (long) zds[j - ny + i] + yds[i];
		    zds[j - ny + i] = BIGLO(num);
		    num = BIGDN(num);
		} while (++i < ny);
		num--;
	    }
	}
	zds[j] = q;
    } while (--j >= ny);
    if (div) {			/* move quotient down in z */
	*div = Fbig_clone(z);
	zds = BDIGITS(*div);
	j = (nx==ny ? nx+2 : nx+1) - ny;
	for (i = 0;i < j;i++) zds[i] = zds[i+ny];
	RBIGNUM(*div)->len = i;
	*div = bignorm(*div);
    }
    if (mod) {			/* just normalize remainder */
	*mod = Fbig_clone(z);
	if (dd) {
	    zds = BDIGITS(*mod);
	    t2 = 0; i = ny;
	    while(i--) {
		t2 = BIGUP(t2) + zds[i];
		zds[i] = t2 / dd;
		t2 %= dd;
	    }
	}
	RBIGNUM(*mod)->len = ny;
	RBIGNUM(*mod)->sign = y->sign;
	*mod = bignorm(*mod);
    }
    GC_UNLINK;
}

static VALUE
Fbig_div(x, y)
    VALUE x, y;
{
    VALUE z;

    GC_LINK;
    GC_PRO(y);
    if (FIXNUM_P(y)) y = int2big(FIX2INT(y));
    else {
	Check_Type(y, T_BIGNUM);
    }
    bigdivmod(x, y, &z, Qnil);
    GC_UNLINK;
    return z;
}

static VALUE
Fbig_mod(x, y)
    VALUE x, y;
{
    VALUE z;

    GC_LINK;
    GC_PRO(y);
    if (FIXNUM_P(y)) y = int2big(FIX2INT(y));
    else {
	Check_Type(y, T_BIGNUM);
    }
    bigdivmod(x, y, Qnil, &z);
    GC_UNLINK;
    return z;
}

static VALUE
Fbig_divmod(x, y)
    VALUE x, y;
{
    VALUE div, mod;

    GC_LINK;
    GC_PRO(y);
    if (FIXNUM_P(y)) y = int2big(FIX2INT(y));
    else {
	Check_Type(y, T_BIGNUM);
    }
    bigdivmod(x, y, &div, &mod);
    GC_UNLINK;

    return assoc_new(div, mod);;
}

static VALUE
Fbig_pow(x, y)
    VALUE x, y;
{
    extern double pow();
    double d1, d2;

    GC_LINK;
    GC_PRO(y);
    if (FIXNUM_P(y)) y = int2big(FIX2INT(y));
    else {
	Check_Type(y, T_BIGNUM);
    }

    d1 = big2dbl(x);
    d2 = big2dbl(y);
    d1 = pow(d1, d2);
    GC_UNLINK;

    return dbl2big(d1);
}

VALUE
Fbig_and(x, y)
    struct RBignum *x, *y;
{
    VALUE z;
    USHORT *ds1, *ds2, *zds;
    UINT i, l1, l2;
    char sign;

    if (FIXNUM_P(y)) {
	y = (struct RBignum*)int2big(FIX2INT(y));
    }
    else {
	Check_Type(y, T_BIGNUM);
    }

    GC_LINK;
    GC_PRO(y);
    if (!y->sign) {
	y = (struct RBignum*)Fbig_clone(y);
	big_2comp(y);
    }
    if (!x->sign) {
	GC_PRO3(x, (struct RBignum*)Fbig_clone(x));
	big_2comp(x);
    }
    if (x->len > y->len) {
	l1 = y->len;
	l2 = x->len;
	ds1 = BDIGITS(y);
	ds2 = BDIGITS(x);
	sign = y->sign;
    }
    else {
	l1 = x->len;
	l2 = y->len;
	ds1 = BDIGITS(x);
	ds2 = BDIGITS(y);
	sign = x->sign;
    }
    z = bignew(l2, x->sign && y->sign);
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] & ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?0:ds2[i];
    }
    if (!RBIGNUM(z)->sign) big_2comp(z);
    GC_UNLINK;
    return bignorm(z);
}

VALUE
Fbig_or(x, y)
    struct RBignum *x, *y;
{
    VALUE z;
    USHORT *ds1, *ds2, *zds;
    UINT i, l1, l2;
    char sign;

    if (FIXNUM_P(y)) {
	y = (struct RBignum*)int2big(FIX2INT(y));
    }
    else {
	Check_Type(y, T_BIGNUM);
    }

    GC_LINK;
    GC_PRO(y);
    if (!y->sign) {
	y = (struct RBignum*)Fbig_clone(y);
	big_2comp(y);
    }
    if (!x->sign) {
	GC_PRO3(x, (struct RBignum*)Fbig_clone(x));
	big_2comp(x);
    }
    if (x->len > y->len) {
	l1 = y->len;
	l2 = x->len;
	ds1 = BDIGITS(y);
	ds2 = BDIGITS(x);
	sign = y->sign;
    }
    else {
	l1 = x->len;
	l2 = y->len;
	ds1 = BDIGITS(x);
	ds2 = BDIGITS(y);
	sign = x->sign;
    }
    z = bignew(l2, x->sign || y->sign);
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] | ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?ds2[i]:(BIGRAD-1);
    }
    if (!RBIGNUM(z)->sign) big_2comp(z);
    GC_UNLINK;
    return bignorm(z);
}

VALUE
Fbig_xor(x, y)
    struct RBignum *x, *y;
{
    VALUE z;
    USHORT *ds1, *ds2, *zds;
    UINT i, l1, l2;
    char sign;

    if (FIXNUM_P(y)) {
	y = (struct RBignum*)int2big(FIX2INT(y));
    }
    else {
	Check_Type(y, T_BIGNUM);
    }

    GC_LINK;
    GC_PRO(y);
    if (!y->sign) {
	y = (struct RBignum*)Fbig_clone(y);
	big_2comp(y);
    }
    if (!x->sign) {
	GC_PRO3(x, (struct RBignum*)Fbig_clone(x));
	big_2comp(x);
    }
    if (x->len > y->len) {
	l1 = y->len;
	l2 = x->len;
	ds1 = BDIGITS(y);
	ds2 = BDIGITS(x);
	sign = y->sign;
    }
    else {
	l1 = x->len;
	l2 = y->len;
	ds1 = BDIGITS(x);
	ds2 = BDIGITS(y);
	sign = x->sign;
    }
    x->sign = x->sign?1:0;
    y->sign = y->sign?1:0;
    z = bignew(l2, !(x->sign ^ y->sign));
    zds = BDIGITS(z);

    for (i=0; i<l1; i++) {
	zds[i] = ds1[i] ^ ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?ds2[i]:~ds2[i];
    }
    if (!RBIGNUM(z)->sign) big_2comp(z);
    GC_UNLINK;
    return bignorm(z);
}

static VALUE
Fbig_neg(x)
    struct RBignum *x;
{
    VALUE z = Fbig_clone(x);
    UINT i = x->len;
    USHORT *ds = BDIGITS(z);

    if (!x->sign) big_2comp(z);
    while (i--) ds[i] = ~ds[i];
    if (x->sign) big_2comp(z);
    RBIGNUM(z)->sign = !RBIGNUM(z)->sign;

    return bignorm(z);
}

static VALUE Fbig_rshift();

VALUE
Fbig_lshift(x, y)
    struct RBignum *x;
    VALUE y;
{
    USHORT *xds, *zds;
    UINT shift = NUM2INT(y);
    UINT s1 = shift/(sizeof(USHORT)*CHAR_BIT);
    UINT s2 = shift%(sizeof(USHORT)*CHAR_BIT);
    VALUE z;
    unsigned long num = 0;
    UINT len, i;

    if (shift < 0) return Fbig_rshift(x, INT2FIX(-shift));
    xds = BDIGITS(x);
    len = x->len;
    z = bignew(len+s1+1, x->sign);
    zds = BDIGITS(z);
    for (i=0; i<s1; i++) {
	*zds++ = 0;
    }
    for (i=0; i<len; i++) {
	num = num | *xds++<<s2;
	*zds++ = BIGLO(num);
	num = BIGDN(num);
    }
    *zds = BIGLO(num);
    return bignorm(z);
}

static VALUE
Fbig_rshift(x, y)
    struct RBignum *x;
    VALUE y;
{
    USHORT *xds, *zds;
    UINT shift = NUM2INT(y);
    UINT s1 = shift/(sizeof(USHORT)*CHAR_BIT);
    UINT s2 = shift%(sizeof(USHORT)*CHAR_BIT);
    VALUE z;
    unsigned long num = 0;
    UINT i = x->len, j;

    if (shift < 0) return Fbig_lshift(x, INT2FIX(-shift));
    if (s1 > x->len) {
	if (x->sign)
	    return INT2FIX(0);
	else
	    return INT2FIX(-1);
    }
    xds = BDIGITS(x);
    i = x->len; j = i - s1;
    z = bignew(j, x->sign);
    zds = BDIGITS(z);
    while (i--, j--) {
	num = (num | xds[i]) >> s2;
	zds[j] = BIGLO(num);
	num = BIGUP(xds[i]);
    }
    return bignorm(z);
}

static VALUE
Fbig_aref(x, y)
    struct RBignum *x;
    VALUE y;
{
    USHORT *xds;
    int shift = NUM2INT(y);
    UINT s1, s2;

    if (shift < 0) return INT2FIX(0);
    s1 = shift/(sizeof(USHORT)*CHAR_BIT);
    s2 = shift%(sizeof(USHORT)*CHAR_BIT);

    if (!x->sign) {
	if (s1 >= x->len) return INT2FIX(1);
	x = (struct RBignum*)Fbig_clone(x);
	big_2comp(x);
    }
    else {
	if (s1 >= x->len) return INT2FIX(0);
    }
    xds = BDIGITS(x);
    if (xds[s1] & (1<<s2))
	return INT2FIX(1);
    return INT2FIX(0);
}

static VALUE
Fbig_cmp(x, y)
    struct RBignum *x, *y;
{
    int xlen = x->len;

    Check_Type(x, T_BIGNUM);
    if (x->sign > y->sign) return INT2FIX(1);
    if (x->sign < y->sign) return INT2FIX(-1);
    if (xlen < y->len)
	return (x->sign) ? INT2FIX(-1) : INT2FIX(1);
    if (xlen > y->len)
	return (x->sign) ? INT2FIX(1) : INT2FIX(-1);

    while(xlen-- && (BDIGITS(x)[xlen]==BDIGITS(y)[xlen]));
    if (-1 == xlen) return INT2FIX(0);
    return (BDIGITS(x)[xlen] < BDIGITS(y)[xlen]) ?
	(x->sign ? INT2FIX(1) : INT2FIX(-1)) :
	    (x->sign ? INT2FIX(-1) : INT2FIX(1));
}

static VALUE
Fbig_hash(x)
    struct RBignum *x;
{
    int i, len, key;
    USHORT *digits;

    key = 0; digits = BDIGITS(x);
    for (i=0,len=x->len; i<x->len; i++) {
	key ^= *digits++;
    }
    return INT2FIX(key);
}

static VALUE
Fbig_coerce(x, y)
    struct RBignum *x;
    VALUE y;
{
    if (FIXNUM_P(y)) {
	return int2big(FIX2INT(y));
    }
    else {
	Fail("can't coerce %s to Bignum", rb_class2name(CLASS_OF(y)));
    }
    /* not reached */
    return Qnil;
}

static VALUE
Fbig_abs(x)
    struct RBignum *x;
{
    if (!x->sign) {
	x = (struct RBignum*)Fbig_clone(x);
	x->sign = 1;
    }
    return (VALUE)x;
}

Init_Bignum()
{
    C_Bignum = rb_define_class("Bignum", C_Integer);
    rb_define_single_method(C_Bignum, "new", Fbig_new, 1);
    rb_define_method(C_Bignum, "clone", Fbig_clone, 0);
    rb_define_method(C_Bignum, "to_s", Fbig_to_s, 0);
    rb_define_method(C_Bignum, "coerce", Fbig_coerce, 1);
    rb_define_method(C_Bignum, "-@", Fbig_uminus, 0);
    rb_define_method(C_Bignum, "+", Fbig_plus, 1);
    rb_define_method(C_Bignum, "-", Fbig_minus, 1);
    rb_define_method(C_Bignum, "*", Fbig_mul, 1);
    rb_define_method(C_Bignum, "/", Fbig_div, 1);
    rb_define_method(C_Bignum, "%", Fbig_mod, 1);
    rb_define_method(C_Bignum, "divmod", Fbig_divmod, 1);
    rb_define_method(C_Bignum, "**", Fbig_pow, 1);
    rb_define_method(C_Bignum, "&", Fbig_and, 1);
    rb_define_method(C_Bignum, "|", Fbig_or, 1);
    rb_define_method(C_Bignum, "^", Fbig_xor, 1);
    rb_define_method(C_Bignum, "~", Fbig_neg, 0);
    rb_define_method(C_Bignum, "<<", Fbig_lshift, 1);
    rb_define_method(C_Bignum, ">>", Fbig_rshift, 1);
    rb_define_method(C_Bignum, "[]", Fbig_aref, 1);

    rb_define_method(C_Bignum, "<=>", Fbig_cmp, 1);
    rb_define_method(C_Bignum, "hash", Fbig_hash, 0);
    rb_define_method(C_Bignum, "to_i", Fbig_to_i, 0);
    rb_define_method(C_Bignum, "to_f", Fbig_to_f, 0);
    rb_define_method(C_Bignum, "abs_f", Fbig_abs, 0);
}
