/************************************************

  bignum.c -

  $Author$
  $Date$
  created at: Fri Jun 10 00:48:55 JST 1994

************************************************/

#include "ruby.h"
#include <ctype.h>
#include <math.h>

extern VALUE cInteger;
VALUE cBignum;

#define BDIGITS(x) RBIGNUM(x)->digits
#define BITSPERDIG (sizeof(USHORT)*CHAR_BIT)
#define BIGRAD (1L << BITSPERDIG)
#define DIGSPERINT ((UINT)(sizeof(INT)/sizeof(USHORT)))
#define BIGUP(x) ((UINT)(x) << BITSPERDIG)
#define BIGDN(x) ((x) >> BITSPERDIG)
#define BIGLO(x) ((x) & (BIGRAD-1))

static VALUE
bignew_1(klass, len, sign)
    VALUE klass;
    UINT len;
    char sign;
{
    NEWOBJ(big, struct RBignum);
    OBJSETUP(big, klass, T_BIGNUM);
    big->sign = sign;
    big->len = len;
    BDIGITS(big) = ALLOC_N(USHORT, len);

    return (VALUE)big;
}

#define bignew(len,sign) bignew_1(cBignum,len,sign)

VALUE
big_clone(x)
    VALUE x;
{
    VALUE z = bignew_1(CLASS_OF(x), RBIGNUM(x)->len, RBIGNUM(x)->sign);

    MEMCPY(BDIGITS(z), BDIGITS(x), USHORT, RBIGNUM(x)->len);
    return z;
}

void
big_2comp(x)			/* get 2's complement */
    VALUE x;
{
    UINT i = RBIGNUM(x)->len;
    USHORT *ds = BDIGITS(x);
    long num;

    while (i--) ds[i] = ~ds[i];
    i = 0; num = 1;
    do {
	num += (long)ds[i];
	ds[i++] = BIGLO(num);
	num = BIGDN(num);
    } while (i < RBIGNUM(x)->len);
    if (ds[0] == 1 || ds[0] == 0) {
	for (i=1;i<RBIGNUM(x)->len;i++) {
	    if (ds[i] != 0) return;
	}
	REALLOC_N(BDIGITS(x), USHORT, RBIGNUM(x)->len++);
	ds = BDIGITS(x);
	ds[RBIGNUM(x)->len-1] = 1;
    }
}

static VALUE
bignorm(x)
    VALUE x;
{
    UINT len = RBIGNUM(x)->len;
    USHORT *ds = BDIGITS(x);

    while (len-- && !ds[len]) ;
    RBIGNUM(x)->len = ++len;

    if (len*sizeof(USHORT) < sizeof(VALUE) ||
	(len*sizeof(USHORT) == sizeof(VALUE) &&
	 ds[sizeof(VALUE)/sizeof(USHORT)-1] <= 0x3fff)) {
	long num = 0;
	while (len--) {
	    num = BIGUP(num) + ds[len];
	}
	if (RBIGNUM(x)->sign) {
	    if (POSFIXABLE(num)) return INT2FIX(num);
	}
	else if (NEGFIXABLE(-num)) return INT2FIX(-num);
    }
    return x;
}

VALUE
big_norm(x)
    VALUE x;
{
    return bignorm(RBIGNUM(x));
}

VALUE
uint2big(n)
    UINT n;
{
    UINT i = 0;
    USHORT *digits;
    VALUE big;

    i = 0;
    big = bignew(DIGSPERINT, 1);
    digits = BDIGITS(big);
    while (i < DIGSPERINT) {
	digits[i++] = BIGLO(n);
	n = BIGDN(n);
    }

    i = DIGSPERINT;
    while (i-- && !digits[i]) ;
    RBIGNUM(big)->len = i+1;
    return big;
}

VALUE
int2big(n)
    INT n;
{
    INT neg = 0;
    VALUE big;

    if (n < 0) {
	n = -n;
	neg = 1;
    }
    big = uint2big(n);
    if (neg) {
	RBIGNUM(big)->sign = 0;
    }
    return big;
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
    INT n;
{
    if (FIXABLE(n)) return INT2FIX(n);
    return int2big(n);
}

VALUE
str2inum(str, base)
    UCHAR *str;
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
    if (base == 8) {
	while (str[0] == '0') str++;
	len = 3*strlen(str)*sizeof(char);
    }
    else {			/* base == 10 or 16 */
	if (base == 16 && str[0] == '0' && (str[1] == 'x'||str[1] == 'X')) {
	    str += 2;
	}
	while (str[0] == '0') str++;
	len = 4*strlen(str)*sizeof(char);
    }

    if (len <= (sizeof(VALUE)*CHAR_BIT)) {
	UINT val = strtoul((char*)str, 0, base);

	if (POSFIXABLE(val)) {
	    if (sign) return INT2FIX(val);
	    else {
		INT result = -(INT)val;
		return INT2FIX(result);
	    }
	}
	else {
	    VALUE big = uint2big(val);
	    RBIGNUM(big)->sign = sign;
	    return big;
	}
    }
    len = (len/BITSPERDIG)+1;

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
    VALUE x;
    int base;
{
    VALUE t;
    USHORT *ds;
    UINT i, j, hbase;
    VALUE ss;
    UCHAR *s, c;

    if (FIXNUM_P(x)) {
	return fix2str(x, base);
    }
    i = RBIGNUM(x)->len;
    if (i == 0) return str_new2("0");
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
	j = 0;
	hbase = 0;
	Fail("bignum cannot treat base %d", base);
    }

    t = big_clone(x);
    ds = BDIGITS(t);
    ss = str_new(0, j);
    s = RSTRING(ss)->ptr;

    s[0] = RBIGNUM(x)->sign ? '+' : '-';
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
    RSTRING(ss)->len -= RBIGNUM(x)->sign?j:j-1;
    memmove(RBIGNUM(x)->sign?s:s+1, s+j, RSTRING(ss)->len);
    s[RSTRING(ss)->len] = '\0';

    return ss;
}

static VALUE
big_to_s(x)
    VALUE x;
{
    return big2str(x, 10);
}

INT
big2int(x)
    VALUE x;
{
    UINT num;
    UINT len = RBIGNUM(x)->len;
    USHORT *ds;

    if (len > sizeof(long)/sizeof(USHORT))
	ArgError("Bignum too big to convert into fixnum");
    ds = BDIGITS(x);
    num = 0;
    while (len--) {
	num = BIGUP(num);
	num += ds[len];
    }
    if (!RBIGNUM(x)->sign) return -num;
    return num;
}

VALUE
big_to_i(x)
    VALUE x;
{
    return bignorm(x);
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

    while (0 != (long)u) {
	u /= (double)(BIGRAD);
	i++;
    }
    z = bignew(i, d>=0);
    digits = BDIGITS(z);
    while (i--) {
	u *= BIGRAD;
	c = (long)u;
	u -= c;
	digits[i] = c;
    }

    return bignorm(z);
}

double
big2dbl(x)
    VALUE x;
{
    double d = 0.0;
    UINT i = RBIGNUM(x)->len;
    USHORT *ds = BDIGITS(x);

    while (i--) {
	d = ds[i] + BIGRAD*d;
    }
    if (!RBIGNUM(x)->sign) d = -d;
    return d;
}

VALUE
big_to_f(x)
    VALUE x;
{
    return float_new(big2dbl(x));
}

static VALUE
big_cmp(x, y)
    VALUE x, y;
{
    int xlen = RBIGNUM(x)->len;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = int2big(FIX2INT(y));
	break;

      case T_BIGNUM:
	break;

      default:
	return num_coerce_bin(x, y);
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

static VALUE
big_eq(x, y)
    VALUE x, y;
{
    if (big_cmp(x, y) == INT2FIX(0)) return TRUE;
    return FALSE;
}

static VALUE
big_uminus(x)
    VALUE x;
{
    VALUE z = big_clone(x);

    RBIGNUM(z)->sign = !RBIGNUM(x)->sign;

    return bignorm(z);
}

static VALUE
big_neg(x)
    VALUE x;
{
    VALUE z = big_clone(x);
    UINT i = RBIGNUM(x)->len;
    USHORT *ds = BDIGITS(z);

    if (!RBIGNUM(x)->sign) big_2comp(z);
    while (i--) ds[i] = ~ds[i];
    if (RBIGNUM(x)->sign) big_2comp(z);
    RBIGNUM(z)->sign = !RBIGNUM(z)->sign;

    return bignorm(z);
}

static VALUE
bigsub(x, y)
    VALUE x, y;
{
    VALUE z = 0;
    USHORT *zds;
    long num;
    UINT i;

    i = RBIGNUM(x)->len;
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

    z = bignew(RBIGNUM(x)->len, (z == 0)?1:0);
    zds = BDIGITS(z);

    for (i = 0, num = 0; i < RBIGNUM(y)->len; i++) { 
	num += (long)BDIGITS(x)[i] - BDIGITS(y)[i];
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
    
    return bignorm(z);
}

static VALUE
bigadd(x, y, sign)
    VALUE x, y;
    char sign;
{
    VALUE z;
    long num;
    UINT i, len;

    if (RBIGNUM(x)->sign == (RBIGNUM(y)->sign ^ sign)) {
	if (RBIGNUM(y)->sign == sign) return bigsub(y, x);
	return bigsub(x, y);
    }

    if (RBIGNUM(x)->len > RBIGNUM(y)->len) {
	len = RBIGNUM(x)->len + 1;
        z = x; x = y; y = z;
    }
    else {
	len = RBIGNUM(y)->len + 1;
    }
    z = bignew(len, sign==RBIGNUM(y)->sign);

    len = RBIGNUM(x)->len;
    for (i = 0, num = 0; i < len; i++) {
	num += (long)(BDIGITS(x)[i] + BDIGITS(y)[i]);
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
    BDIGITS(z)[i] = num;

    return bignorm(z);
}

VALUE
big_plus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = int2big(FIX2INT(y));
	/* fall through */
      case T_BIGNUM:
	return bigadd(x, y, 1);

      case T_FLOAT:
	return float_new(big2dbl(x) + RFLOAT(y)->value);

      default:
	return num_coerce_bin(x, y);
    }
}

VALUE
big_minus(x, y)
    VALUE x, y;
{
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = int2big(FIX2INT(y));
	/* fall through */
      case T_BIGNUM:
	return bigadd(x, y, 0);

      case T_FLOAT:
	return float_new(big2dbl(x) - RFLOAT(y)->value);

      default:
	return num_coerce_bin(x, y);
    }
}

VALUE
big_mul(x, y)
    VALUE x, y;
{
    UINT i = 0, j;
    unsigned long n = 0;
    VALUE z;
    USHORT *zds;

    if (FIXNUM_P(x)) x = int2big(FIX2INT(x));
    switch (TYPE(y)) {
      case T_FIXNUM:
	y = int2big(FIX2INT(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
	return float_new(big2dbl(x) * RFLOAT(y)->value);

      default:
	return num_coerce_bin(x, y);
    }

    j = RBIGNUM(x)->len + RBIGNUM(y)->len + 1;
    z = bignew(j, RBIGNUM(x)->sign==RBIGNUM(y)->sign);
    zds = BDIGITS(z);
    while (j--) zds[j] = 0;
    for (i = 0; i < RBIGNUM(x)->len; i++) {
	unsigned long dd = BDIGITS(x)[i]; 
	if (dd == 0) continue;
	n = 0;
	for (j = 0; j < RBIGNUM(y)->len; j++) {
	    int ee = n + dd * BDIGITS(y)[j];
	    n = zds[i + j] + ee;
	    if (ee) zds[i + j] = BIGLO(n);
	    n = BIGDN(n);
	}
	if (n) {
	    zds[i + j] = n;
	}
    }

    return bignorm(z);
}

static void
bigdivmod(x, y, div, mod)
    VALUE x, y;
    VALUE *div, *mod;
{
    UINT nx = RBIGNUM(x)->len, ny = RBIGNUM(y)->len, i, j;
    VALUE z;
    USHORT *xds, *yds, *zds, *tds;
    unsigned long t2;
    long num;
    USHORT dd, q;

    yds = BDIGITS(y);
    if (ny == 0 && yds[0] == 0) num_zerodiv();
    if (nx < ny	|| nx == ny && BDIGITS(x)[nx - 1] < BDIGITS(y)[ny - 1]) {
	if (div) *div = INT2FIX(0);
	if (mod) *mod = bignorm(x);
	return;
    }
    xds = BDIGITS(x);
    if (ny == 1) {
	dd = yds[0];
	z = big_clone(x);
	zds = BDIGITS(z);
	t2 = 0; i = nx;
	while (i--) {
	    t2 = BIGUP(t2) + zds[i];
	    zds[i] = t2 / dd;
	    t2 %= dd;
	}
	if (div) *div = bignorm(z);
	if (mod) {
	    if (!RBIGNUM(y)->sign) t2 = -t2;
	    *mod = INT2FIX(t2);
	}
	return;
    }
    z = bignew(nx==ny?nx+2:nx+1, RBIGNUM(x)->sign==RBIGNUM(y)->sign);
    zds = BDIGITS(z);
    if (nx==ny) zds[nx+1] = 0;
    while (!yds[ny-1]) ny--;
    if ((dd = BIGRAD/(int)(yds[ny-1]+1)) != 1) {
	y = big_clone(y);
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
		int ee;
		t2 += (unsigned long)yds[i] * q;
		ee = num - BIGLO(t2);
		num = zds[j - ny + i] + ee;
		if (ee) zds[j - ny + i] = BIGLO(num);
		num = BIGDN(num);
		t2 = BIGDN(t2);
	    } while (++i < ny);
	    num += zds[j - ny + i] - t2; /* borrow from high digit; don't update */
	    while (num) {		/* "add back" required */
		i = 0; num = 0; q--;
		do {
		    int ee = num + yds[i];
		    num = (long) zds[j - ny + i] + ee;
		    if (ee) zds[j - ny + i] = BIGLO(num);
		    num = BIGDN(num);
		} while (++i < ny);
		num--;
	    }
	}
	zds[j] = q;
    } while (--j >= ny);
    if (div) {			/* move quotient down in z */
	*div = big_clone(z);
	zds = BDIGITS(*div);
	j = (nx==ny ? nx+2 : nx+1) - ny;
	for (i = 0;i < j;i++) zds[i] = zds[i+ny];
	RBIGNUM(*div)->len = i;
	*div = bignorm(*div);
    }
    if (mod) {			/* just normalize remainder */
	*mod = big_clone(z);
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
	RBIGNUM(*mod)->sign = RBIGNUM(y)->sign;
	*mod = bignorm(*mod);
    }
}

static VALUE
big_div(x, y)
    VALUE x, y;
{
    VALUE z;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = int2big(FIX2INT(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
	return float_new(big2dbl(x) / RFLOAT(y)->value);

      default:
	return num_coerce_bin(x, y);
    }
    bigdivmod(x, y, &z, 0);

    return z;
}

static VALUE
big_mod(x, y)
    VALUE x, y;
{
    VALUE z;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = int2big(FIX2INT(y));
	break;

      case T_BIGNUM:
	break;

      case T_FLOAT:
	y = dbl2big(RFLOAT(y)->value);
	break;

      default:
	return num_coerce_bin(x, y);
    }
    bigdivmod(x, y, 0, &z);

    return z;
}

static VALUE
big_divmod(x, y)
    VALUE x, y;
{
    VALUE div, mod;

    switch (TYPE(y)) {
      case T_FIXNUM:
	y = int2big(FIX2INT(y));
	break;

      case T_FLOAT:
	y = dbl2big(RFLOAT(y)->value);
	break;

      case T_BIGNUM:
	break;

      default:
	return num_coerce_bin(x, y);
    }
    bigdivmod(x, y, &div, &mod);

    return assoc_new(div, mod);;
}

VALUE
big_pow(x, y)
    VALUE x, y;
{
    double d;
    VALUE z;
    
    if (y == INT2FIX(0)) return INT2FIX(1);
    switch (TYPE(y)) {
      case T_FLOAT:
	d = RFLOAT(y)->value;
	break;

      case T_BIGNUM:
	if (RBIGNUM(y)->sign) goto pos_big;
	d = big2dbl(y);
	break;

      case T_FIXNUM:
	if (FIX2INT(y) > 0) goto pos_big;
	d = (double)FIX2INT(y);
	break;

      default:
	return num_coerce_bin(x, y);
    }
    return float_new(pow(big2dbl(x), d));

  pos_big:
    z = x;
    for (;;) {
	y = rb_funcall(y, '-', 1, INT2FIX(1));
	if (y == INT2FIX(0)) break;
	while (rb_funcall(y, '%', 1, INT2FIX(2)) == INT2FIX(0)) {
	    y = rb_funcall(y, '/', 1, INT2FIX(2));
	    x = big_mul(x, x);
	}
	z = big_mul(z, x);
    }
    return z;
}

VALUE
big_and(x, y)
    VALUE x, y;
{
    VALUE z;
    USHORT *ds1, *ds2, *zds;
    UINT i, l1, l2;
    char sign;

    if (FIXNUM_P(y)) {
	y = int2big(FIX2INT(y));
    }
    else {
	Check_Type(y, T_BIGNUM);
    }

    if (!RBIGNUM(y)->sign) {
	y = big_clone(y);
	big_2comp(y);
    }
    if (!RBIGNUM(x)->sign) {
	x = big_clone(x);
	big_2comp(x);
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
	zds[i] = ds1[i] & ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?0:ds2[i];
    }
    if (!RBIGNUM(z)->sign) big_2comp(z);
    return bignorm(z);
}

VALUE
big_or(x, y)
    VALUE x, y;
{
    VALUE z;
    USHORT *ds1, *ds2, *zds;
    UINT i, l1, l2;
    char sign;

    if (FIXNUM_P(y)) {
	y = int2big(FIX2INT(y));
    }
    else {
	Check_Type(y, T_BIGNUM);
    }

    if (!RBIGNUM(y)->sign) {
	y = big_clone(y);
	big_2comp(y);
    }
    if (!RBIGNUM(x)->sign) {
	x = big_clone(x);
	big_2comp(x);
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
	zds[i] = ds1[i] | ds2[i];
    }
    for (; i<l2; i++) {
	zds[i] = sign?ds2[i]:(BIGRAD-1);
    }
    if (!RBIGNUM(z)->sign) big_2comp(z);

    return bignorm(z);
}

VALUE
big_xor(x, y)
    VALUE x, y;
{
    VALUE z;
    USHORT *ds1, *ds2, *zds;
    UINT i, l1, l2;
    char sign;

    if (FIXNUM_P(y)) {
	y = int2big(FIX2INT(y));
    }
    else {
	Check_Type(y, T_BIGNUM);
    }

    if (!RBIGNUM(y)->sign) {
	y = big_clone(y);
	big_2comp(y);
    }
    if (!RBIGNUM(x)->sign) {
	x = big_clone(x);
	big_2comp(x);
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
    if (!RBIGNUM(z)->sign) big_2comp(z);

    return bignorm(z);
}

static VALUE big_rshift();

VALUE
big_lshift(x, y)
    VALUE x, y;
{
    USHORT *xds, *zds;
    int shift = NUM2INT(y);
    UINT s1 = shift/BITSPERDIG;
    UINT s2 = shift%BITSPERDIG;
    VALUE z;
    unsigned long num = 0;
    UINT len, i;

    if (shift < 0) return big_rshift(x, INT2FIX(-shift));
    xds = BDIGITS(x);
    len = RBIGNUM(x)->len;
    z = bignew(len+s1+1, RBIGNUM(x)->sign);
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
big_rshift(x, y)
    VALUE x, y;
{
    USHORT *xds, *zds;
    int shift = NUM2INT(y);
    UINT s1 = shift/BITSPERDIG;
    UINT s2 = shift%BITSPERDIG;
    VALUE z;
    unsigned long num = 0;
    UINT i = RBIGNUM(x)->len;
    UINT j;

    if (shift < 0) return big_lshift(x, INT2FIX(-shift));
    if (s1 > RBIGNUM(x)->len) {
	if (RBIGNUM(x)->sign)
	    return INT2FIX(0);
	else
	    return INT2FIX(-1);
    }
    xds = BDIGITS(x);
    i = RBIGNUM(x)->len; j = i - s1;
    z = bignew(j, RBIGNUM(x)->sign);
    zds = BDIGITS(z);
    while (i--, j--) {
	num = (num | xds[i]) >> s2;
	zds[j] = BIGLO(num);
	num = BIGUP(xds[i]);
    }
    return bignorm(z);
}

static VALUE
big_aref(x, y)
    VALUE x, y;
{
    USHORT *xds;
    int shift = NUM2INT(y);
    UINT s1, s2;

    if (shift < 0) return INT2FIX(0);
    s1 = shift/BITSPERDIG;
    s2 = shift%BITSPERDIG;

    if (!RBIGNUM(x)->sign) {
	if (s1 >= RBIGNUM(x)->len) return INT2FIX(1);
	x = big_clone(x);
	big_2comp(x);
    }
    else {
	if (s1 >= RBIGNUM(x)->len) return INT2FIX(0);
    }
    xds = BDIGITS(x);
    if (xds[s1] & (1<<s2))
	return INT2FIX(1);
    return INT2FIX(0);
}

static VALUE
big_hash(x)
    VALUE x;
{
    int i, len, key;
    USHORT *digits;

    key = 0; digits = BDIGITS(x);
    for (i=0,len=RBIGNUM(x)->len; i<RBIGNUM(x)->len; i++) {
	key ^= *digits++;
    }
    return INT2FIX(key);
}

static VALUE
big_coerce(x, y)
    VALUE x, y;
{
    if (FIXNUM_P(y)) {
	return assoc_new(int2big(FIX2INT(y)), x);
    }
    else {
	TypeError("can't coerce %s to Bignum", rb_class2name(CLASS_OF(y)));
    }
    /* not reached */
}

static VALUE
big_abs(x)
    VALUE x;
{
    if (!RBIGNUM(x)->sign) {
	x = big_clone(x);
	RBIGNUM(x)->sign = 1;
    }
    return (VALUE)x;
}

/* !!!warnig!!!!
   this is not really a random number!!
*/

VALUE
big_rand(max)
    VALUE max;
{
    struct RBignum *v;
    int len;

    len = RBIGNUM(max)->len;
    v = RBIGNUM(bignew(len,1));
    while (len--) {
#ifdef HAVE_RANDOM
	BDIGITS(v)[len] = random();
#else
	BDIGITS(v)[len] = rand();
#endif
    }

    return big_mod(v, max);
}

static VALUE
big_size(big)
    VALUE big;
{
    return INT2FIX(RBIGNUM(big)->len*sizeof(USHORT));
}

void
Init_Bignum()
{
    cBignum = rb_define_class("Bignum", cInteger);

    rb_undef_method(CLASS_OF(cBignum), "new");

    rb_define_method(cBignum, "to_s", big_to_s, 0);
    rb_define_method(cBignum, "coerce", big_coerce, 1);
    rb_define_method(cBignum, "-@", big_uminus, 0);
    rb_define_method(cBignum, "+", big_plus, 1);
    rb_define_method(cBignum, "-", big_minus, 1);
    rb_define_method(cBignum, "*", big_mul, 1);
    rb_define_method(cBignum, "/", big_div, 1);
    rb_define_method(cBignum, "%", big_mod, 1);
    rb_define_method(cBignum, "divmod", big_divmod, 1);
    rb_define_method(cBignum, "**", big_pow, 1);
    rb_define_method(cBignum, "&", big_and, 1);
    rb_define_method(cBignum, "|", big_or, 1);
    rb_define_method(cBignum, "^", big_xor, 1);
    rb_define_method(cBignum, "~", big_neg, 0);
    rb_define_method(cBignum, "<<", big_lshift, 1);
    rb_define_method(cBignum, ">>", big_rshift, 1);
    rb_define_method(cBignum, "[]", big_aref, 1);

    rb_define_method(cBignum, "<=>", big_cmp, 1);
    rb_define_method(cBignum, "==", big_eq, 1);
    rb_define_method(cBignum, "eql?", big_eq, 1);
    rb_define_method(cBignum, "hash", big_hash, 0);
    rb_define_method(cBignum, "to_i", big_to_i, 0);
    rb_define_method(cBignum, "to_f", big_to_f, 0);
    rb_define_method(cBignum, "abs", big_abs, 0);
    rb_define_method(cBignum, "size", big_size, 0);
}
