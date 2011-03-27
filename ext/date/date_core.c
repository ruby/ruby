/*
  date_core.c: Coded by Tadayoshi Funaba 2010, 2011
*/

#include "ruby.h"
#include "ruby/encoding.h"
#include <math.h>
#include <time.h>

#define NDEBUG
#include <assert.h>

#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

#define LIGHT_MODE (1 << 0)
#define HAVE_JD    (1 << 1)
#define HAVE_DF    (1 << 2)
#define HAVE_CIVIL (1 << 3)
#define HAVE_TIME  (1 << 4)

#define light_mode_p(x) ((x)->flags & LIGHT_MODE)
#define have_jd_p(x) ((x)->flags & HAVE_JD)
#define have_df_p(x) ((x)->flags & HAVE_DF)
#define have_civil_p(x) ((x)->flags & HAVE_CIVIL)
#define have_time_p(x) ((x)->flags & HAVE_TIME)

#define MIN_YEAR -4713
#define MAX_YEAR 1000000
#define MIN_JD -327
#define MAX_JD 366963925

#define LIGHTABLE_JD(j) (j >= MIN_JD && j <= MAX_JD)
#define LIGHTABLE_YEAR(y) (y >= MIN_YEAR && y <= MAX_YEAR)
#define LIGHTABLE_CWYEAR(y) LIGHTABLE_YEAR(y)

#define ITALY 2299161

#define DAY_IN_SECONDS 86400
#define SECOND_IN_NANOSECONDS 1000000000
#define DAY_IN_NANOSECONDS 86400000000000LL

/* copied from time.c */
#define NDIV(x,y) (-(-((x)+1)/(y))-1)
#define NMOD(x,y) ((y)-(-((x)+1)%(y))-1)
#define DIV(n,d) ((n)<0 ? NDIV((n),(d)) : (n)/(d))
#define MOD(n,d) ((n)<0 ? NMOD((n),(d)) : (n)%(d))

union DateData
{
    unsigned flags;
    struct {
	unsigned flags;
	VALUE ajd;
	VALUE of;
	VALUE sg;
	VALUE cache;
    } r;
    struct {
	unsigned flags;
	long jd;	/* as utc */
	double sg;
	/* decoded as utc=local */
	int year;
	int mon;
	int mday;
    } l;
};

union DateTimeData
{
    unsigned flags;
    struct {
	unsigned flags;
	VALUE ajd;
	VALUE of;
	VALUE sg;
	VALUE cache;
    } r;
    struct {
	unsigned flags;
	long jd;	/* as utc */
	int df;		/* as utc, in secs */
	long sf;	/* in nano secs */
	int of;		/* in secs */
	double sg;
	/* decoded as local */
	int year;
	int mon;
	int mday;
	int hour;
	int min;
	int sec;
    } l;
};

#define get_d1(x)\
    union DateData *dat;\
    Data_Get_Struct(x, union DateData, dat)

#define get_d2(x,y)\
    union DateData *adat, *bdat;\
    Data_Get_Struct(x, union DateData, adat);\
    Data_Get_Struct(y, union DateData, bdat)

#define get_d1_dt1(x,y)\
    union DateData *adat;\
    union DateTimeData *bdat;\
    Data_Get_Struct(x, union DateData, adat);\
    Data_Get_Struct(y, union DateTimeData, bdat)

#define get_dt1(x)\
    union DateTimeData *dat;\
    Data_Get_Struct(x, union DateTimeData, dat)

#define get_dt2(x,y)\
    union DateTimeData *adat, *bdat;\
    Data_Get_Struct(x, union DateTimeData, adat);\
    Data_Get_Struct(y, union DateTimeData, bdat)

#define get_dt1_d1(x,y)\
    union DateTimeData *adat;\
    union DateData *bdat;\
    Data_Get_Struct(x, union DateTimeData, adat);\
    Data_Get_Struct(y, union DateData, bdat)

#define get_dt2_cast(x,y)\
    union DateData *atmp, *btmp;\
    union DateTimeData abuf, bbuf, *adat, *bdat;\
    if (k_datetime_p(x))\
	Data_Get_Struct(x, union DateTimeData, adat);\
    else {\
	Data_Get_Struct(x, union DateData, atmp);\
	abuf.l.jd = atmp->l.jd;\
	abuf.l.df = 0;\
	abuf.l.sf = 0;\
	abuf.l.of = 0;\
	abuf.l.sg = atmp->l.sg;\
	abuf.l.year = atmp->l.year;\
	abuf.l.mon = atmp->l.mon;\
	abuf.l.mday = atmp->l.mday;\
	abuf.l.hour = 0;\
	abuf.l.min = 0;\
	abuf.l.sec = 0;\
	abuf.flags = HAVE_DF | HAVE_TIME | atmp->l.flags;\
	adat = &abuf;\
    }\
    if (k_datetime_p(y))\
	Data_Get_Struct(y, union DateTimeData, bdat);\
    else {\
	Data_Get_Struct(y, union DateData, btmp);\
	bbuf.l.jd = btmp->l.jd;\
	bbuf.l.df = 0;\
	bbuf.l.sf = 0;\
	bbuf.l.of = 0;\
	bbuf.l.sg = btmp->l.sg;\
	bbuf.l.year = btmp->l.year;\
	bbuf.l.mon = btmp->l.mon;\
	bbuf.l.mday = btmp->l.mday;\
	bbuf.l.hour = 0;\
	bbuf.l.min = 0;\
	bbuf.l.sec = 0;\
	bbuf.flags = HAVE_DF | HAVE_TIME | btmp->l.flags;\
	bdat = &bbuf;\
    }

#define f_add(x,y) rb_funcall(x, '+', 1, y)
#define f_sub(x,y) rb_funcall(x, '-', 1, y)
#define f_mul(x,y) rb_funcall(x, '*', 1, y)
#define f_div(x,y) rb_funcall(x, '/', 1, y)

#define forward0(k,m) rb_funcall(k, rb_intern(m), 0)
#define cforward0(m) forward0(klass, m)
#define iforward0(m) forward0(self, m)
#define forward1(k,m,a) rb_funcall(k, rb_intern(m), 1, a)
#define iforward1(m,a) forward1(self, m, a)
#define forwardv(k,m) rb_funcall2(k, rb_intern(m), argc, argv)
#define cforwardv(m) forwardv(klass, m)
#define iforwardv(m) forwardv(self, m)
#define forwardop(k,m) rb_funcall(k, rb_intern(m), 1, other)
#define iforwardop(m) forwardop(self, m)

static VALUE cDate, cDateTime;
static VALUE rzero, rhalf, day_in_nanoseconds;

static int valid_civil_p(int y, int m, int d, double sg,
			 int *rm, int *rd, long *rjd, int *ns);

static int
find_fdoy(int y, double sg, long *rjd, int *ns)
{
    int d, rm, rd;

    for (d = 1; d < 31; d++)
	if (valid_civil_p(y, 1, d, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}

static int
find_ldoy(int y, double sg, long *rjd, int *ns)
{
    int i, rm, rd;

    for (i = 0; i < 30; i++)
	if (valid_civil_p(y, 12, 31 - i, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}

#ifndef NDEBUG
static int
find_fdom(int y, int m, double sg, long *rjd, int *ns)
{
    int d, rm, rd;

    for (d = 1; d < 31; d++)
	if (valid_civil_p(y, m, d, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}
#endif

static int
find_ldom(int y, int m, double sg, long *rjd, int *ns)
{
    int i, rm, rd;

    for (i = 0; i < 30; i++)
	if (valid_civil_p(y, m, 31 - i, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}

static void
civil_to_jd(int y, int m, int d, double sg, long *rjd, int *ns)
{
    double a, b, jd;

    if (m <= 2) {
	y -= 1;
	m += 12;
    }
    a = floor(y / 100.0);
    b = 2 - a + floor(a / 4.0);
    jd = floor(365.25 * (y + 4716)) +
	floor(30.6001 * (m + 1)) +
	d + b - 1524;
    if (jd < sg) {
	jd -= b;
	*ns = 0;
    }
    else
	*ns = 1;

    *rjd = (long)jd;
}

static void
jd_to_civil(long jd, double sg, int *ry, int *rm, int *rdom)
{
    double x, a, b, c, d, e, y, m, dom;

    if (jd < sg)
	a = jd;
    else {
	x = floor((jd - 1867216.25) / 36524.25);
	a = jd + 1 + x - floor(x / 4.0);
    }
    b = a + 1524;
    c = floor((b - 122.1) / 365.25);
    d = floor(365.25 * c);
    e = floor((b - d) / 30.6001);
    dom = b - d - floor(30.6001 * e);
    if (e <= 13) {
	m = e - 1;
	y = c - 4716;
    }
    else {
	m = e - 13;
	y = c - 4715;
    }

    *ry = (int)y;
    *rm = (int)m;
    *rdom = (int)dom;
}

static void
ordinal_to_jd(int y, int d, double sg, long *rjd, int *ns)
{
    int ns2;

    find_fdoy(y, sg, rjd, &ns2);
    *rjd += d - 1;
    *ns = (*rjd < sg) ? 0 : 1;
}

static void
jd_to_ordinal(long jd, double sg, int *ry, int *rd)
{
    int rm2, rd2, ns;
    long rjd;

    jd_to_civil(jd, sg, ry, &rm2, &rd2);
    find_fdoy(*ry, sg, &rjd, &ns);
    *rd = (int)(jd - rjd) + 1;
}

static void
commercial_to_jd(int y, int w, int d, double sg, long *rjd, int *ns)
{
    long rjd2;
    int ns2;

    find_fdoy(y, sg, &rjd2, &ns2);
    rjd2 += 3;
    *rjd =
	(rjd2 - MOD((rjd2 - 1) + 1, 7)) +
	7 * (w - 1) +
	(d - 1);
    *ns = (*rjd < sg) ? 0 : 1;
}

static void
jd_to_commercial(long jd, double sg, int *ry, int *rw, int *rd)
{
    int ry2, rm2, rd2, a, ns2;
    long rjd2;

    jd_to_civil(jd - 3, sg, &ry2, &rm2, &rd2);
    a = ry2;
    commercial_to_jd(a + 1, 1, 1, sg, &rjd2, &ns2);
    if (jd >= rjd2)
	*ry = a + 1;
    else {
	commercial_to_jd(a, 1, 1, sg, &rjd2, &ns2);
	*ry = a;
    }
    *rw = 1 + (int)DIV(jd - rjd2,  7);
    *rd = (int)MOD(jd + 1, 7);
    if (*rd == 0)
	*rd = 7;
}

#ifndef NDEBUG
static void
weeknum_to_jd(int y, int w, int d, int f, double sg, long *rjd, int *ns)
{
    long rjd2;
    int ns2;

    find_fdoy(y, sg, &rjd2, &ns2);
    rjd2 += 6;
    *rjd = (rjd2 - MOD(((rjd2 - f) + 1), 7) - 7) + 7 * w + d;
    *ns = (*rjd < sg) ? 0 : 1;
}
#endif

static void
jd_to_weeknum(long jd, int f, double sg, int *ry, int *rw, int *rd)
{
    int rm, rd2, ns;
    long rjd, j;

    jd_to_civil(jd, sg, ry, &rm, &rd2);
    find_fdoy(*ry, sg, &rjd, &ns);
    rjd += 6;
    j = jd - (rjd - MOD((rjd - f) + 1, 7)) + 7;
    *rw = (int)DIV(j, 7);
    *rd = (int)MOD(j, 7);
}

#ifndef NDEBUG
static void
nth_kday_to_jd(int y, int m, int n, int k, double sg, long *rjd, int *ns)
{
    long rjd2;
    int ns2;

    if (n > 0) {
	find_fdom(y, m, sg, &rjd2, &ns2);
	rjd2 -= 1;
    }
    else {
	find_ldom(y, m, sg, &rjd2, &ns2);
	rjd2 += 7;
    }
    *rjd = (rjd2 - MOD((rjd2 - k) + 1, 7)) + 7 * n;
    *ns = (*rjd < sg) ? 0 : 1;
}
#endif

#ifndef NDEBUG
inline static int jd_to_wday(long jd);

static void
jd_to_nth_kday(long jd, double sg, int *ry, int *rm, int *rn, int *rk)
{
    int rd, ns2;
    long rjd;

    jd_to_civil(jd, sg, ry, rm, &rd);
    find_fdom(*ry, *rm, sg, &rjd, &ns2);
    *rn = (int)DIV(jd - rjd, 7) + 1;
    *rk = jd_to_wday(jd);
}
#endif

static int
valid_ordinal_p(int y, int d, double sg,
		int *rd, long *rjd, int *ns)
{
    int ry2, rd2;

    if (d < 0) {
	long rjd2;
	int ns2;

	if (!find_ldoy(y, sg, &rjd2, &ns2))
	    return 0;
	jd_to_ordinal(rjd2 + d + 1, sg, &ry2, &rd2);
	if (ry2 != y)
	    return 0;
	d = rd2;
    }
    ordinal_to_jd(y, d, sg, rjd, ns);
    jd_to_ordinal(*rjd, sg, &ry2, &rd2);
    if (ry2 != y || rd2 != d)
	return 0;
    return 1;
}

static const int monthtab[2][13] = {
    { 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
    { 0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
};

inline static int
leap_p(int y)
{
    return MOD(y, 4) == 0 && y % 100 != 0 || MOD(y, 400) == 0;
}

static int
last_day_of_month(int y, int m)
{
    return monthtab[leap_p(y) ? 1 : 0][m];
}

static int
valid_gregorian_p(int y, int m, int d, int *rm, int *rd)
{
    int last;

    if (m < 0)
	m += 13;
    last = last_day_of_month(y, m);
    if (d < 0)
	d = last + d + 1;

    *rm = m;
    *rd = d;

    return !(m < 0 || m > 12 ||
	     d < 1 || d > last);
}

static int
valid_civil_p(int y, int m, int d, double sg,
	      int *rm, int *rd, long *rjd, int *ns)
{
    int ry;

    if (m < 0)
	m += 13;
    if (d < 0) {
	if (!find_ldom(y, m, sg, rjd, ns))
	    return 0;
	jd_to_civil(*rjd + d + 1, sg, &ry, rm, rd);
	if (ry != y || *rm != m)
	    return 0;
	d = *rd;
    }
    civil_to_jd(y, m, d, sg, rjd, ns);
    jd_to_civil(*rjd, sg, &ry, rm, rd);
    if (ry != y || *rm != m || *rd != d)
	return 0;
    return 1;
}

static int
valid_commercial_p(int y, int w, int d, double sg,
		   int *rw, int *rd, long *rjd, int *ns)
{
    int ns2, ry2, rw2, rd2;

    if (d < 0)
	d += 8;
    if (w < 0) {
	long rjd2;

	commercial_to_jd(y + 1, 1, 1, sg, &rjd2, &ns2);
	jd_to_commercial(rjd2 + w * 7, sg, &ry2, &rw2, &rd2);
	if (ry2 != y)
	    return 0;
	w = rw2;
    }
    commercial_to_jd(y, w, d, sg, rjd, ns);
    jd_to_commercial(*rjd, sg, &ry2, rw, rd);
    if (y != ry2 || w != *rw || d != *rd)
	return 0;
    return 1;
}

static int
valid_time_p(int h, int min, int s, int *rh, int *rmin, int *rs)
{
    if (h < 0)
	h += 24;
    if (min < 0)
	min += 60;
    if (s < 0)
	s += 60;
    *rh = h;
    *rmin = min;
    *rs = s;
    return !(h   < 0 || h   > 24 ||
	     min < 0 || min > 59 ||
	     s   < 0 || s   > 59 ||
	     (h == 24 && (min > 0 || s > 0)));
}

inline static int
df_local_to_utc(int df, int of)
{
    df -= of;
    if (df < 0)
	df += DAY_IN_SECONDS;
    else if (df >= DAY_IN_SECONDS)
	df -= DAY_IN_SECONDS;
    return df;
}

inline static int
df_utc_to_local(int df, int of)
{
    df += of;
    if (df < 0)
	df += DAY_IN_SECONDS;
    else if (df >= DAY_IN_SECONDS)
	df -= DAY_IN_SECONDS;
    return df;
}

inline static long
jd_local_to_utc(long jd, int df, int of)
{
    df -= of;
    if (df < 0)
	jd -= 1;
    else if (df >= DAY_IN_SECONDS)
	jd += 1;
    return jd;
}

inline static long
jd_utc_to_local(long jd, int df, int of)
{
    df += of;
    if (df < 0)
	jd -= 1;
    else if (df >= DAY_IN_SECONDS)
	jd += 1;
    return jd;
}

inline static int
time_to_df(int h, int min, int s)
{
    return h * 3600 + min * 60 + s;
}

inline static int
jd_to_wday(long jd)
{
    return (int)MOD(jd + 1, 7);
}

static int
daydiff_to_sec(VALUE vof, int *rof)
{
    switch (TYPE(vof)) {
      case T_FIXNUM:
	{
	    int n;

	    n = FIX2INT(vof);
	    if (n != -1 && n != 0 && n != 1)
		return 0;
	    *rof = n * DAY_IN_SECONDS;
	    return 1;
	}
      case T_FLOAT:
	{
	    double n;

	    n = NUM2DBL(vof);
	    if (n < -DAY_IN_SECONDS || n > DAY_IN_SECONDS)
		return 0;
	    *rof = round(n * DAY_IN_SECONDS);
	    return 1;
	}
      case T_RATIONAL:
	{
	    VALUE vs = f_mul(vof, INT2FIX(DAY_IN_SECONDS));
	    VALUE vn = RRATIONAL(vs)->num;
	    VALUE vd = RRATIONAL(vs)->den;
	    int n, d;

	    if (!FIXNUM_P(vn) || !FIXNUM_P(vd))
		return 0;
	    n = FIX2INT(vn);
	    d = FIX2INT(vd);
	    if (d != 1)
		return 0;
	    if (n < -DAY_IN_SECONDS || n > DAY_IN_SECONDS)
		return 0;
	    *rof = n;
	    return 1;
	}
      case T_STRING:
	{
	    VALUE vs = rb_funcall(cDate, rb_intern("zone_to_diff"), 1, vof);
	    int n;

	    if (!FIXNUM_P(vs))
		return 0;
	    n = FIX2INT(vs);
	    if (n < -DAY_IN_SECONDS || n > DAY_IN_SECONDS)
		return 0;
	    *rof = n;
	    return 1;
	}
    }
    return 0;
}

inline static void
get_d_jd(union DateData *x)
{
    if (!have_jd_p(x)) {
	long jd;
	int ns;

	assert(have_civil_p(x));

	civil_to_jd(x->l.year, x->l.mon, x->l.mday, x->l.sg, &jd, &ns);
	x->l.jd = jd;
	x->l.flags |= HAVE_JD;
    }
}

inline static void
get_d_civil(union DateData *x)
{
    if (!have_civil_p(x)) {
	int y, m, d;

	assert(have_jd_p(x));

	jd_to_civil(x->l.jd, x->l.sg, &y, &m, &d);
	x->l.year = y;
	x->l.mon = m;
	x->l.mday = d;
	x->l.flags |= HAVE_CIVIL;
    }
}

inline static void
get_dt_df(union DateTimeData *x)
{
    if (!have_df_p(x)) {
	assert(have_time_p(x));

	x->l.df = df_local_to_utc(time_to_df(x->l.hour, x->l.min, x->l.sec),
				  x->l.of);
	x->l.flags |= HAVE_DF;
    }
}

inline static void
get_dt_time(union DateTimeData *x)
{
    int r;

    if (!have_time_p(x)) {
	assert(have_df_p(x));

	r = df_utc_to_local(x->l.df, x->l.of);
	x->l.hour = r / 3600;
	r %= 3600;
	x->l.min = r / 60;
	x->l.sec = r % 60;
	x->l.flags |= HAVE_TIME;
    }
}

inline static void
get_dt_jd(union DateTimeData *x)
{
    if (!have_jd_p(x)) {
	long jd;
	int ns;

	assert(have_civil_p(x));

	civil_to_jd(x->l.year, x->l.mon, x->l.mday, x->l.sg, &jd, &ns);

	get_dt_time(x);
	x->l.jd = jd_local_to_utc(jd,
				  time_to_df(x->l.hour, x->l.min, x->l.sec),
				  x->l.of);
	x->l.flags |= HAVE_JD;
    }
}

inline static void
get_dt_civil(union DateTimeData *x)
{
    if (!have_civil_p(x)) {
	long jd;
	int y, m, d;

	assert(have_jd_p(x));

	get_dt_df(x);
	jd = jd_utc_to_local(x->l.jd, x->l.df, x->l.of);
	jd_to_civil(jd, x->l.sg, &y, &m, &d);
	x->l.year = y;
	x->l.mon = m;
	x->l.mday = d;
	x->l.flags |= HAVE_CIVIL;
    }
}

inline static long
local_jd(union DateTimeData *x)
{
    assert(have_jd_p(x));
    assert(have_df_p(x));
    return jd_utc_to_local(x->l.jd, x->l.df, x->l.of);
}

inline static int
local_df(union DateTimeData *x)
{
    assert(have_df_p(x));
    return df_utc_to_local(x->l.df, x->l.of);
}

inline static VALUE
f_kind_of_p(VALUE x, VALUE c)
{
    return rb_obj_is_kind_of(x, c);
}

inline static VALUE
k_date_p(VALUE x)
{
    return f_kind_of_p(x, cDate);
}

inline static VALUE
k_datetime_p(VALUE x)
{
    return f_kind_of_p(x, cDateTime);
}

inline static VALUE
k_numeric_p(VALUE x)
{
    return f_kind_of_p(x, rb_cNumeric);
}

static VALUE
date_s_valid_jd_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vsg;

    rb_scan_args(argc, argv, "11", &vjd, &vsg);

    return Qtrue;
}

static VALUE
date_s_valid_civil_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vd, vsg;
    int y, m, d, rm, rd;
    double sg;

    rb_scan_args(argc, argv, "31", &vy, &vm, &vd, &vsg);

    if (!(FIXNUM_P(vy) &&
	  FIXNUM_P(vm) &&
	  FIXNUM_P(vd)))
	return cforwardv("valid_civil_r?");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    m = 1;
    d = 1;

    switch (argc) {
      case 4:
      case 3:
	d = NUM2INT(vd);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return cforwardv("valid_civil_r?");
    }

    if (isinf(sg) && sg < 0) {
	if (!valid_gregorian_p(y, m, d, &rm, &rd))
	    return Qfalse;
	return Qtrue;
    }
    else {
	long jd;
	int ns;

	if (!valid_civil_p(y, m, d, sg, &rm, &rd, &jd, &ns))
	    return Qfalse;
	return Qtrue;
    }
}

static VALUE
date_s_valid_ordinal_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vd, vsg;
    int y, d, rd;
    double sg;

    rb_scan_args(argc, argv, "21", &vy, &vd, &vsg);

    if (!(FIXNUM_P(vy) &&
	  FIXNUM_P(vd)))
	return cforwardv("valid_ordinal_r?");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    d = 1;

    switch (argc) {
      case 3:
      case 2:
	d = NUM2INT(vd);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return cforwardv("valid_ordinal_r?");
    }

    {
	long jd;
	int ns;

	if (!valid_ordinal_p(y, d, sg, &rd, &jd, &ns))
	    return Qfalse;
	return Qtrue;
    }
}

static VALUE
date_s_valid_commercial_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vsg;
    int y, w, d, rw, rd;
    double sg;

    rb_scan_args(argc, argv, "31", &vy, &vw, &vd, &vsg);

    if (!(FIXNUM_P(vy) &&
	  FIXNUM_P(vw) &&
	  FIXNUM_P(vd)))
	return cforwardv("valid_commercial_r?");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    w = 1;
    d = 1;

    switch (argc) {
      case 4:
      case 3:
	d = NUM2INT(vd);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_CWYEAR(y))
	    return cforwardv("valid_commercial_r?");
    }

    {
	long jd;
	int ns;

	if (!valid_commercial_p(y, w, d, sg, &rw, &rd, &jd, &ns))
	    return Qfalse;
	return Qtrue;
    }
}

static void
d_right_gc_mark(union DateData *dat)
{
    if (!light_mode_p(dat)) {
	rb_gc_mark(dat->r.ajd);
	rb_gc_mark(dat->r.of);
	rb_gc_mark(dat->r.sg);
	rb_gc_mark(dat->r.cache);
    }
}

inline static VALUE
d_right_s_new_internal(VALUE klass, VALUE ajd, VALUE of, VALUE sg,
		       unsigned flags)
{
    union DateData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateData, d_right_gc_mark, -1, dat);

    dat->r.ajd = ajd;
    dat->r.of = of;
    dat->r.sg = sg;
    dat->r.cache = rb_hash_new();
    dat->r.flags = flags;

    return obj;
}

inline static VALUE
d_lite_s_new_internal(VALUE klass, long jd, double sg,
		      int y, int m, int d, unsigned flags)
{
    union DateData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateData, d_right_gc_mark, -1, dat);

    dat->l.jd = jd;
    dat->l.sg = sg;
    dat->l.year = y;
    dat->l.mon = m;
    dat->l.mday = d;
    dat->l.flags = flags;

    return obj;
}

static VALUE
d_lite_s_new_internal_wo_civil(VALUE klass, long jd, double sg,
			       unsigned flags)
{
    return d_lite_s_new_internal(klass, jd, sg, 0, 0, 0, flags);
}

static VALUE
d_lite_s_alloc(VALUE klass)
{
    return d_lite_s_new_internal_wo_civil(klass, 0, 0, LIGHT_MODE);
}

static VALUE
d_right_s_new_r_bang(int argc, VALUE *argv, VALUE klass)
{
    VALUE vajd, vof, vsg;

    rb_scan_args(argc, argv, "03", &vajd, &vof, &vsg);

    if (argc < 1)
	vajd = INT2FIX(0);
    if (argc < 2)
	vof = INT2FIX(0);
    if (argc < 3)
	vsg = DBL2NUM(ITALY);

    return d_right_s_new_internal(klass, vajd, vof, vsg, 0);
}

static VALUE
d_lite_s_new_l_bang(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vsg;
    long jd;
    double sg;

    rb_scan_args(argc, argv, "02", &vjd, &vsg);

    if (argc < 1)
	jd = 0;
    else {
	if (!FIXNUM_P(vjd))
	    rb_raise(rb_eArgError, "cannot create");
	jd = NUM2LONG(vjd);
	if (!LIGHTABLE_JD(jd))
	    rb_raise(rb_eArgError, "cannot create");
    }
    if (argc < 2)
	sg = 0;
    else
	sg = NUM2DBL(vsg);

    return d_lite_s_new_internal_wo_civil(klass,
					  jd,
					  sg,
					  LIGHT_MODE | HAVE_JD);
}

static VALUE
date_s_new_r_bang(int argc, VALUE *argv, VALUE klass)
{
    return d_right_s_new_r_bang(argc, argv, klass);
}

static VALUE
date_s_new_l_bang(int argc, VALUE *argv, VALUE klass)
{
    return d_lite_s_new_l_bang(argc, argv, klass);
}

/*
 * call-seq:
 *    Date.jd([jd=0[, start=Date::ITALY]])
 *
 * Create a new Date object from a Julian Day Number.
 *
 * +jd+ is the Julian Day Number; if not specified, it defaults to 0.
 * +sg+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_jd(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vsg;
    long jd;
    double sg;

    rb_scan_args(argc, argv, "02", &vjd, &vsg);

    if (!FIXNUM_P(vjd))
	return cforwardv("jd_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    if (argc >= 1) {
	jd = NUM2LONG(vjd);
	if (!LIGHTABLE_JD(jd))
	    return cforwardv("jd_r");
    }
    else
	jd = 0;

    if (jd < sg)
	return cforwardv("jd_r");

    return d_lite_s_new_internal_wo_civil(klass, jd, sg, LIGHT_MODE | HAVE_JD);
}

/*
 * call-seq:
 *    Date.ordinal([year=-4712[, yday=1[, start=Date::ITALY]]])
 *
 * Create a new Date object from an Ordinal Date, specified
 * by year +y+ and day-of-year +d+. +d+ can be negative,
 * in which it counts backwards from the end of the year.
 * No year wraparound is performed, however.  An invalid
 * value for +d+ results in an ArgumentError being raised.
 *
 * +y+ defaults to -4712, and +d+ to 1; this is Julian Day
 * Number day 0.
 *
 * +sg+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_ordinal(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vd, vsg;
    int y, d, rd;
    double sg;

    rb_scan_args(argc, argv, "03", &vy, &vd, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vd) || FIXNUM_P(vd))))
	return cforwardv("ordinal_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    d = 1;

    switch (argc) {
      case 3:
      case 2:
	d = NUM2INT(vd);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return cforwardv("ordinal_r");
    }

    {
	long jd;
	int ns;

	if (!valid_ordinal_p(y, d, sg, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return cforwardv("ordinal_r");

	return d_lite_s_new_internal_wo_civil(klass, jd, sg,
					      LIGHT_MODE | HAVE_JD);
    }
}

/*
 * call-seq:
 *    Date.civil([year=-4712[, mon=1[, mday=1[, start=Date::ITALY]]]])
 *    Date.new([year=-4712[, mon=1[, mday=1[, start=Date::ITALY]]]])
 *
 * Create a new Date object for the Civil Date specified by
 * year +y+, month +m+, and day-of-month +d+.
 *
 * +m+ and +d+ can be negative, in which case they count
 * backwards from the end of the year and the end of the
 * month respectively.  No wraparound is performed, however,
 * and invalid values cause an ArgumentError to be raised.
 * can be negative
 *
 * +y+ defaults to -4712, +m+ to 1, and +d+ to 1; this is
 * Julian Day Number day 0.
 *
 * +sg+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_civil(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vd, vsg;
    int y, m, d, rm, rd;
    double sg;

    rb_scan_args(argc, argv, "04", &vy, &vm, &vd, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vm) || FIXNUM_P(vm)) &&
	  (NIL_P(vd) || FIXNUM_P(vd))))
	return cforwardv("civil_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    m = 1;
    d = 1;

    switch (argc) {
      case 4:
      case 3:
	d = NUM2INT(vd);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return cforwardv("civil_r");
    }

    if (isinf(sg) && sg < 0) {
	if (!valid_gregorian_p(y, m, d, &rm, &rd))
	    rb_raise(rb_eArgError, "invalid date");

	return d_lite_s_new_internal(klass, 0, sg, y, rm, rd,
				     LIGHT_MODE | HAVE_CIVIL);
    }
    else {
	long jd;
	int ns;

	if (!valid_civil_p(y, m, d, sg, &rm, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return cforwardv("civil_r");

	return d_lite_s_new_internal(klass, jd, sg, y, rm, rd,
				     LIGHT_MODE | HAVE_JD | HAVE_CIVIL);
    }
}

/*
 * call-seq:
 *    Date.commercial([cwyear=-4712[, cweek=1[, cwday=1[, start=Date::ITALY]]]])
 *
 * Create a new Date object for the Commercial Date specified by
 * year +y+, week-of-year +w+, and day-of-week +d+.
 *
 * Monday is day-of-week 1; Sunday is day-of-week 7.
 *
 * +w+ and +d+ can be negative, in which case they count
 * backwards from the end of the year and the end of the
 * week respectively.  No wraparound is performed, however,
 * and invalid values cause an ArgumentError to be raised.
 *
 * +y+ defaults to -4712, +w+ to 1, and +d+ to 1; this is
 * Julian Day Number day 0.
 *
 * +sg+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_commercial(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vsg;
    int y, w, d, rw, rd;
    double sg;

    rb_scan_args(argc, argv, "04", &vy, &vw, &vd, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vw) || FIXNUM_P(vw)) &&
	  (NIL_P(vd) || FIXNUM_P(vd))))
	return cforwardv("commercial_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    w = 1;
    d = 1;

    switch (argc) {
      case 4:
      case 3:
	d = NUM2INT(vd);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_CWYEAR(y))
	    return cforwardv("commercial_r");
    }

    {
	long jd;
	int ns;

	if (!valid_commercial_p(y, w, d, sg, &rw, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return cforwardv("commercial_r");

	return d_lite_s_new_internal_wo_civil(klass, jd, sg,
					      LIGHT_MODE | HAVE_JD);
    }
}

#if !defined(HAVE_GMTIME_R)
static struct tm*
localtime_r(const time_t *t, struct tm *tm)
{
    auto struct tm *tmp = localtime(t);
    if (tmp)
	*tm = *tmp;
    return tmp;
}
#endif

/*
 * call-seq:
 *    Date.today([start=Date::ITALY])
 *
 * Create a new Date object representing today.
 *
 * +sg+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_today(int argc, VALUE *argv, VALUE klass)
{
    VALUE vsg;
    double sg;
    time_t t;
    struct tm tm;
    long y;
    int m, d;

    rb_scan_args(argc, argv, "01", &vsg);

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    if (time(&t) == -1)
	rb_sys_fail("time");
    localtime_r(&t, &tm);

    y = tm.tm_year + 1900;
    m = tm.tm_mon + 1;
    d = tm.tm_mday;

    if (!LIGHTABLE_YEAR(y))
	rb_raise(rb_eArgError, "cannot create");

    if (isinf(sg) && sg < 0)
	return d_lite_s_new_internal(klass, 0, sg, (int)y, m, d,
				     LIGHT_MODE | HAVE_CIVIL);
    else {
	long jd;
	int ns;

	civil_to_jd((int)y, m, d, sg, &jd, &ns);

	return d_lite_s_new_internal(klass, jd, sg, (int)y, m, d,
				     LIGHT_MODE | HAVE_JD | HAVE_CIVIL);
    }
}

/*
 * call-seq:
 *    d.ajd
 *
 * Get the date as an Astronomical Julian Day Number.
 */
static VALUE
d_lite_ajd(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return dat->r.ajd;
    {
	get_d_jd(dat);
	return f_sub(INT2FIX(dat->l.jd), rhalf);
    }
}

/*
 * call-seq:
 *    d.amjd
 *
 * Get the date as an Astronomical Modified Julian Day Number.
 */
static VALUE
d_lite_amjd(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("amjd_r");
    {
	get_d_jd(dat);
	return rb_rational_new1(LONG2NUM(dat->l.jd - 2400001L));
    }
}

/*
 * call-seq:
 *    d.jd
 *
 * Get the date as a Julian Day Number.
 */
static VALUE
d_lite_jd(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("jd_r");
    {
	get_d_jd(dat);
	return INT2FIX(dat->l.jd);
    }
}

/*
 * call-seq:
 *    d.mjd
 *
 * Get the date as a Modified Julian Day Number.
 */
static VALUE
d_lite_mjd(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("mjd_r");
    {
	get_d_jd(dat);
	return LONG2NUM(dat->l.jd - 2400001L);
    }
}

/*
 * call-seq:
 *    d.ld
 *
 * Get the date as a Lilian Day Number.
 */
static VALUE
d_lite_ld(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("ld_r");
    {
	get_d_jd(dat);
	return LONG2NUM(dat->l.jd - 2299160L);
    }
}

/*
 * call-seq:
 *    d.year
 *
 * Get the year of this date.
 */
static VALUE
d_lite_year(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("year_r");
    {
	get_d_civil(dat);
	return INT2FIX(dat->l.year);
    }
}

static const int yeartab[2][13] = {
    { 0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 },
    { 0, 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 }
};

static int
civil_to_yday(int y, int m, int d)
{
    return yeartab[leap_p(y) ? 1 : 0][m] + d;
}

/*
 * call-seq:
 *    d.yday
 *
 * Get the day-of-the-year of this date.
 *
 * January 1 is day-of-the-year 1
 */
static VALUE
d_lite_yday(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("yday_r");
    {
	get_d_civil(dat);
	return INT2FIX(civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday));
    }
}

/*
 * call-seq:
 *    d.mon
 *
 * Get the month of this date.
 *
 * January is month 1.
 */
static VALUE
d_lite_mon(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("mon_r");
    {
	get_d_civil(dat);
	return INT2FIX(dat->l.mon);
    }
}

/*
 * call-seq:
 *    d.mday
 *
 * Get the day-of-the-month of this date.
 */
static VALUE
d_lite_mday(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("mday_r");
    {
	get_d_civil(dat);
	return INT2FIX(dat->l.mday);
    }
}

/*
 * call-seq:
 *    d.day_fraction
 *
 * Get any fractional day part of the date.
 */
static VALUE
d_lite_day_fraction(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("day_fraction_r");
    return INT2FIX(0);
}

static VALUE
d_lite_wnum0(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("wnum0_r");
    {
	get_d_jd(dat);
	jd_to_weeknum(dat->l.jd, 0, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

static VALUE
d_lite_wnum1(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("wnum1_r");
    {
	get_d_jd(dat);
	jd_to_weeknum(dat->l.jd, 1, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

/*
 * call-seq:
 *    d.hour
 *
 * Get the hour of this date.
 */
static VALUE
d_lite_hour(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("hour_r");
    return INT2FIX(0);
}

/*
 * call-seq:
 *    d.min
 *    d.minute
 *
 * Get the minute of this date.
 */
static VALUE
d_lite_min(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("min_r");
    return INT2FIX(0);
}

/*
 * call-seq:
 *    d.sec
 *    d.second
 *
 * Get the second of this date.
 */
static VALUE
d_lite_sec(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("sec_r");
    return INT2FIX(0);
}

/*
 * call-seq:
 *    d.sec_fraction
 *    d.second_fraction
 *
 * Get the fraction-of-a-second of this date.
 */
static VALUE
d_lite_sec_fraction(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("sec_fraction_r");
    return INT2FIX(0);
}

/*
 * call-seq:
 *    d.offset
 *
 * Get the offset of this date.
 */
static VALUE
d_lite_offset(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return dat->r.of;
    return INT2FIX(0);
}

/*
 * call-seq:
 *    d.zone
 *
 * Get the zone name of this date.
 */
static VALUE
d_lite_zone(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("zone_r");
    return rb_usascii_str_new2("+00:00");
}

/*
 * call-seq:
 *    d.cwyear
 *
 * Get the commercial year of this date.  See *Commercial* *Date*
 * in the introduction for how this differs from the normal year.
 */
static VALUE
d_lite_cwyear(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("cwyear_r");
    {
	get_d_jd(dat);
	jd_to_commercial(dat->l.jd, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(ry);
    }
}

/*
 * call-seq:
 *    d.cweek
 *
 * Get the commercial week of the year of this date.
 */
static VALUE
d_lite_cweek(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("cweek_r");
    {
	get_d_jd(dat);
	jd_to_commercial(dat->l.jd, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

/*
 * call-seq:
 *    d.cwday
 *
 * Get the commercial day of the week of this date.  Monday is
 * commercial day-of-week 1; Sunday is commercial day-of-week 7.
 */
static VALUE
d_lite_cwday(VALUE self)
{
    int w;

    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("cwday_r");
    {
	get_d_jd(dat);
	w = jd_to_wday(dat->l.jd);
	if (w == 0)
	    w = 7;
	return INT2FIX(w);
    }
}

/*
 * call-seq:
 *    d.wday
 *
 * Get the week day of this date.  Sunday is day-of-week 0;
 * Saturday is day-of-week 6.
 */
static VALUE
d_lite_wday(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("wday_r");
    {
	get_d_jd(dat);
	return INT2FIX(jd_to_wday(dat->l.jd));
    }
}

/*
 * call-seq:
 *    d.julian?
 *
 * Is the current date old-style (Julian Calendar)?
 */
static VALUE
d_lite_julian_p(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("julian_r?");
    return Qfalse;
}

/*
 * call-seq:
 *    d.gregorian?
 *
 * Is the current date new-style (Gregorian Calendar)?
 */
static VALUE
d_lite_gregorian_p(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("gregorian_r?");
    return Qtrue;
}

/*
 * call-seq:
 *    d.leap?
 *
 * Is this a leap year?
 */
static VALUE
d_lite_leap_p(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("leap_r?");
    {
	get_d_civil(dat);
	return leap_p(dat->l.year) ? Qtrue : Qfalse;
    }
}

/*
 * call-seq:
 *    d.start
 *
 * When is the Day of Calendar Reform for this Date object?
 */
static VALUE
d_lite_start(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return dat->r.sg;
    return DBL2NUM(dat->l.sg);
}

/*
 * call-seq:
 *    d.new_start([start=Date::ITALY])
 *
 * Create a copy of this Date object using a new Day of Calendar Reform.
 */
static VALUE
d_lite_new_start(int argc, VALUE *argv, VALUE self)
{
    VALUE vsg;
    double sg;

    get_d1(self);

    if (!light_mode_p(dat))
	return iforwardv("new_start_r");

    rb_scan_args(argc, argv, "01", &vsg);

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    {
	get_d_jd(dat);

	if (dat->l.jd < sg)
	    return iforwardv("new_start_r");

	return d_lite_s_new_internal_wo_civil(CLASS_OF(self),
					      dat->l.jd,
					      sg,
					      LIGHT_MODE | HAVE_JD);
    }
}

/*
 * call-seq:
 *    d.new_offset([offset=0])
 *
 * Create a copy of this Date object using a new offset.
 */
static VALUE
d_lite_new_offset(int argc, VALUE *argv, VALUE self)
{
    VALUE vof;
    int rof;

    get_d1(self);

    if (!light_mode_p(dat))
	return iforwardv("new_offset_r");

    rb_scan_args(argc, argv, "01", &vof);

    if (NIL_P(vof))
	rof = 0;
    else {
	if (!daydiff_to_sec(vof, &rof) || rof != 0)
	    return iforwardv("new_offset_r");
    }

    {
	get_d_jd(dat);

	return d_lite_s_new_internal_wo_civil(CLASS_OF(self),
					      dat->l.jd,
					      dat->l.sg,
					      LIGHT_MODE | HAVE_JD);
    }
}

/*
 * call-seq:
 *    d + n
 *
 * Return a new Date object that is +n+ days later than the
 * current one.
 *
 * +n+ may be a negative value, in which case the new Date
 * is earlier than the current one; however, #-() might be
 * more intuitive.
 *
 * If +n+ is not a Numeric, a TypeError will be thrown.  In
 * particular, two Dates cannot be added to each other.
 */
static VALUE
d_lite_plus(VALUE self, VALUE other)
{
    get_d1(self);

    if (!light_mode_p(dat))
	return iforwardop("plus_r");

    switch (TYPE(other)) {
      case T_FIXNUM:
	{
	    long jd;

	    get_d_jd(dat);

	    jd = dat->l.jd + FIX2LONG(other);

	    if (LIGHTABLE_JD(jd) && jd >= dat->l.sg)
		return d_lite_s_new_internal(CLASS_OF(self),
					     jd, dat->l.sg,
					     0, 0, 0,
					     dat->l.flags & ~HAVE_CIVIL);
	}
	break;
      case T_FLOAT:
	{
	    double d = NUM2DBL(other);
	    long l = round(d);
	    if (l == d && LIGHTABLE_JD(l))
		return d_lite_plus(self, INT2FIX(l));
	}
	break;
    }
    return iforwardop("plus_r");
}

static VALUE
minus_dd(VALUE self, VALUE other)
{
    get_dt2_cast(self, other);

    if (light_mode_p(adat) &&
	light_mode_p(bdat)) {
	long d, sf;
	int df;
	VALUE r;

	get_dt_jd(adat);
	get_dt_jd(bdat);
	get_dt_df(adat);
	get_dt_df(bdat);

	d = adat->l.jd - bdat->l.jd;
	df = adat->l.df - bdat->l.df;
	sf = adat->l.sf - bdat->l.sf;
	if (df < 0) {
	    d -= 1;
	    df += DAY_IN_SECONDS;
	}
	else if (df >= DAY_IN_SECONDS) {
	    d += 1;
	    df -= DAY_IN_SECONDS;
	}
	if (sf < 0) {
	    df -= 1;
	    sf += SECOND_IN_NANOSECONDS;
	}
	else if (sf >= SECOND_IN_NANOSECONDS) {
	    df += 1;
	    sf -= SECOND_IN_NANOSECONDS;
	}
	r = rb_rational_new1(LONG2NUM(d));
	if (df)
	    r = f_add(r, rb_rational_new2(INT2FIX(df),
					  INT2FIX(DAY_IN_SECONDS)));
	if (sf)
	    r = f_add(r, rb_rational_new2(INT2FIX(sf), day_in_nanoseconds));
	return r;
    }
    return iforwardop("minus_r");
}

/*
 * call-seq:
 *    d - n
 *    d - d2
 *
 * If +x+ is a Numeric value, create a new Date object that is
 * +x+ days earlier than the current one.
 *
 * If +x+ is a Date, return the number of days between the
 * two dates; or, more precisely, how many days later the current
 * date is than +x+.
 *
 * If +x+ is neither Numeric nor a Date, a TypeError is raised.
 */
static VALUE
d_lite_minus(VALUE self, VALUE other)
{
    if (k_datetime_p(other))
	return minus_dd(self, other);

    assert(!k_datetime_p(other));
    if (k_date_p(other)) {
	get_d2(self, other);

	if (light_mode_p(adat) &&
	    light_mode_p(bdat)) {
	    long d;

	    get_d_jd(adat);
	    get_d_jd(bdat);

	    d = adat->l.jd - bdat->l.jd;
	    return rb_rational_new1(LONG2NUM(d));
	}
    }

    switch (TYPE(other)) {
      case T_FIXNUM:
	return d_lite_plus(self, LONG2NUM(-FIX2LONG(other)));
      case T_FLOAT:
	return d_lite_plus(self, DBL2NUM(-NUM2DBL(other)));
    }
    return iforwardop("minus_r");
}

static VALUE
cmp_dd(VALUE self, VALUE other)
{
    get_dt2_cast(self, other);

    if (light_mode_p(adat) &&
	light_mode_p(bdat)) {
	get_dt_jd(adat);
	get_dt_jd(bdat);
	get_dt_df(adat);
	get_dt_df(bdat);

	if (adat->l.jd == bdat->l.jd) {
	    if (adat->l.df == bdat->l.df) {
		if (adat->l.sf == bdat->l.sf) {
		    return INT2FIX(0);
		}
		else if (adat->l.sf < bdat->l.sf) {
		    return INT2FIX(-1);
		}
		else {
		    return INT2FIX(1);
		}
	    }
	    else if (adat->l.df < bdat->l.df) {
		return INT2FIX(-1);
	    }
	    else {
		return INT2FIX(1);
	    }
	}
	else if (adat->l.jd < bdat->l.jd) {
	    return INT2FIX(-1);
	}
	else {
	    return INT2FIX(1);
	}
    }
    return iforwardop("cmp_r");
}

/*
 * call-seq:
 *    d <=> n
 *    d <=> d2
 *
 * Compare this date with another date.
 *
 * +other+ can also be a Numeric value, in which case it is
 * interpreted as an Astronomical Julian Day Number.
 *
 * Comparison is by Astronomical Julian Day Number, including
 * fractional days.  This means that both the time and the
 * offset are taken into account when comparing
 * two DateTime instances.  When comparing a DateTime instance
 * with a Date instance, the time of the latter will be
 * considered as falling on midnight UTC.
 */
static VALUE
d_lite_cmp(VALUE self, VALUE other)
{
    if (k_datetime_p(other))
	return cmp_dd(self, other);

    assert(!k_datetime_p(other));
    if (k_date_p(other)) {
	get_d2(self, other);

	if (light_mode_p(adat) &&
	    light_mode_p(bdat)) {
	    if (have_jd_p(adat) &&
		have_jd_p(bdat)) {
		if (adat->l.jd == bdat->l.jd)
		    return INT2FIX(0);
		if (adat->l.jd < bdat->l.jd)
		    return INT2FIX(-1);
		return INT2FIX(1);
	    }
	    else {
		get_d_civil(adat);
		get_d_civil(bdat);

		if (adat->l.year == bdat->l.year) {
		    if (adat->l.mon == bdat->l.mon) {
			if (adat->l.mday == bdat->l.mday) {
			    return INT2FIX(0);
			}
			else if (adat->l.mday < bdat->l.mday) {
			    return INT2FIX(-1);
			}
			else {
			    return INT2FIX(1);
			}
		    }
		    else if (adat->l.mon < bdat->l.mon) {
			return INT2FIX(-1);
		    }
		    else {
			return INT2FIX(1);
		    }
		}
		else if (adat->l.year < bdat->l.year) {
		    return INT2FIX(-1);
		}
		else {
		    return INT2FIX(1);
		}
	    }
	}
    }
    return iforwardop("cmp_r");
}

static VALUE
equal_dd(VALUE self, VALUE other)
{
    get_dt2_cast(self, other);

    if (light_mode_p(adat) &&
	light_mode_p(bdat)) {
	get_dt_jd(adat);
	get_dt_jd(bdat);
	get_dt_df(adat);
	get_dt_df(bdat);

	if (local_jd(adat) == local_jd(bdat))
	    return Qtrue;
	return Qfalse;
    }
    return iforwardop("equal_r");
}

/*
 * call-seq:
 *    d == other
 *
 * The relationship operator for Date.
 *
 * Compares dates by Julian Day Number.  When comparing
 * two DateTime instances, or a DateTime with a Date,
 * the instances will be regarded as equivalent if they
 * fall on the same date in local time.
 */
static VALUE
d_lite_equal(VALUE self, VALUE other)
{
    if (k_datetime_p(other))
	return equal_dd(self, other);

    assert(!k_datetime_p(other));
    if (k_date_p(other)) {
	get_d2(self, other);

	if (light_mode_p(adat) &&
	    light_mode_p(bdat)) {
	    if (have_jd_p(adat) &&
		have_jd_p(bdat)) {
		if (adat->l.jd == bdat->l.jd)
		    return Qtrue;
		return Qfalse;
	    }
	    else {
		get_d_civil(adat);
		get_d_civil(bdat);

		if (adat->l.year == bdat->l.year)
		    if (adat->l.mon == bdat->l.mon)
			if (adat->l.mday == bdat->l.mday)
			    return Qtrue;
		return Qfalse;
	    }
	}
    }
    return iforwardop("equal_r");
}

static VALUE
eql_p_dd(VALUE self, VALUE other)
{
    get_dt2_cast(self, other);

    if (light_mode_p(adat) &&
	light_mode_p(bdat)) {
	get_dt_jd(adat);
	get_dt_jd(bdat);
	get_dt_df(adat);
	get_dt_df(bdat);

	if (adat->l.jd == bdat->l.jd)
	    if (adat->l.df == bdat->l.df)
		if (adat->l.sf == bdat->l.sf)
		    return Qtrue;
	return Qfalse;
    }
    return iforwardop("eql_r?");
}

/*
 * call-seq:
 *    d.eql?(other)
 *
 * Is this Date equal to +other+?
 *
 * +other+ must both be a Date object, and represent the same date.
 */
static VALUE
d_lite_eql_p(VALUE self, VALUE other)
{
    if (k_datetime_p(other))
	return eql_p_dd(self, other);

    assert(!k_datetime_p(other));
    if (k_date_p(other)) {
	get_d2(self, other);

	if (light_mode_p(adat) &&
	    light_mode_p(bdat)) {
	    if (have_jd_p(adat) &&
		have_jd_p(bdat)) {
		if (adat->l.jd == bdat->l.jd)
		    return Qtrue;
		return Qfalse;
	    }
	    else {
		get_d_civil(adat);
		get_d_civil(bdat);

		if (adat->l.year == bdat->l.year)
		    if (adat->l.mon == bdat->l.mon)
			if (adat->l.mday == bdat->l.mday)
			    return Qtrue;
		return Qfalse;
	    }
	}
    }
    return iforwardop("eql_r?");
}

/*
 * call-seq:
 *    d.hash
 *
 * Calculate a hash value for this date.
 */
static VALUE
d_lite_hash(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("hash_r");
    return rb_hash(d_lite_ajd(self));
}

/*
 * call-seq:
 *    d.to_s
 *
 * Return the date as a human-readable string.
 */
static VALUE
d_lite_to_s(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("to_s_r");
    {
	get_d_civil(dat);
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "%.4d-%02d-%02d",
			      dat->l.year, dat->l.mon, dat->l.mday);
    }
}

/*
 * call-seq:
 *    d.inspect
 *
 * Return internal object state as a programmer-readable string.
 */
static VALUE
d_lite_inspect(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return iforward0("inspect_r");
    {
	get_d_civil(dat);
	get_d_jd(dat);
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "#<%s[L]: %.4d-%02d-%02d (%ldj,0,%.0f)>",
			      rb_obj_classname(self),
			      dat->l.year, dat->l.mon, dat->l.mday,
			      dat->l.jd, dat->l.sg);
    }
}

#include <errno.h>
#include "timev.h"

size_t
date_strftime(char *s, size_t maxsize, const char *format,
	      const struct vtm *vtm, VALUE timev);

#define SMALLBUF 100
static size_t
date_strftime_alloc(char **buf, const char *format,
		    struct vtm *vtm, VALUE timev)
{
    size_t size, len, flen;

    (*buf)[0] = '\0';
    flen = strlen(format);
    if (flen == 0) {
	return 0;
    }
    errno = 0;
    len = date_strftime(*buf, SMALLBUF, format, vtm, timev);
    if (len != 0 || (**buf == '\0' && errno != ERANGE)) return len;
    for (size=1024; ; size*=2) {
	*buf = xmalloc(size);
	(*buf)[0] = '\0';
	len = date_strftime(*buf, size, format, vtm, timev);
	/*
	 * buflen can be zero EITHER because there's not enough
	 * room in the string, or because the control command
	 * goes to the empty string. Make a reasonable guess that
	 * if the buffer is 1024 times bigger than the length of the
	 * format string, it's not failing for lack of room.
	 */
	if (len > 0 || size >= 1024 * flen) break;
	xfree(*buf);
    }
    return len;
}

static void
d_lite_set_vtm_and_timev(VALUE self, struct vtm *vtm, VALUE *timev)
{
    get_d1(self);

    if (!light_mode_p(dat)) {
	vtm->year = iforward0("year_r");
	vtm->mon = FIX2INT(iforward0("mon_r"));
	vtm->mday = FIX2INT(iforward0("mday_r"));
	vtm->hour = FIX2INT(iforward0("hour_r"));
	vtm->min = FIX2INT(iforward0("min_r"));
	vtm->sec = FIX2INT(iforward0("sec_r"));
	vtm->subsecx = iforward0("sec_fraction_r");
	vtm->utc_offset = INT2FIX(0);
	vtm->wday = FIX2INT(iforward0("wday_r"));
	vtm->yday = FIX2INT(iforward0("yday_r"));
	vtm->isdst = 0;
	vtm->zone = RSTRING_PTR(iforward0("zone_r"));
	*timev = f_mul(f_sub(dat->r.ajd,
			     rb_rational_new2(INT2FIX(4881175), INT2FIX(2))),
		       INT2FIX(86400));
    }
    else {
	get_d_jd(dat);
	get_d_civil(dat);

	vtm->year = LONG2NUM(dat->l.year);
	vtm->mon = dat->l.mon;
	vtm->mday = dat->l.mday;
	vtm->hour = 0;
	vtm->min = 0;
	vtm->sec = 0;
	vtm->subsecx = INT2FIX(0);
	vtm->utc_offset = INT2FIX(0);
	vtm->wday = jd_to_wday(dat->l.jd);
	vtm->yday = civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday);
	vtm->isdst = 0;
	vtm->zone = "+00:00";
	*timev = f_mul(INT2FIX(dat->l.jd - 2440588),
		       INT2FIX(86400));
    }
}

static VALUE
date_strftime_internal(int argc, VALUE *argv, VALUE self,
		       const char *default_fmt,
		       void (*func)(VALUE, struct vtm *, VALUE *))
{
    get_d1(self);
    {
	VALUE vfmt;
	const char *fmt;
	long len;
	char buffer[SMALLBUF], *buf = buffer;
	struct vtm vtm;
	VALUE timev;
	VALUE str;

	rb_scan_args(argc, argv, "01", &vfmt);

	if (argc < 1)
	    vfmt = rb_usascii_str_new2(default_fmt);
	else {
	    StringValue(vfmt);
	    if (!rb_enc_str_asciicompat_p(vfmt)) {
		rb_raise(rb_eArgError,
			 "format should have ASCII compatible encoding");
	    }
	}
	fmt = RSTRING_PTR(vfmt);
	len = RSTRING_LEN(vfmt);
	(*func)(self, &vtm, &timev);
	if (memchr(fmt, '\0', len)) {
	    /* Ruby string may contain \0's. */
	    const char *p = fmt, *pe = fmt + len;

	    str = rb_str_new(0, 0);
	    while (p < pe) {
		len = date_strftime_alloc(&buf, p, &vtm, timev);
		rb_str_cat(str, buf, len);
		p += strlen(p);
		if (buf != buffer) {
		    xfree(buf);
		    buf = buffer;
		}
		for (fmt = p; p < pe && !*p; ++p);
		if (p > fmt) rb_str_cat(str, fmt, p - fmt);
	    }
	    return str;
	}
	else
	    len = date_strftime_alloc(&buf, fmt, &vtm, timev);

	str = rb_str_new(buf, len);
	if (buf != buffer) xfree(buf);
	rb_enc_copy(str, vfmt);
	return str;
    }
}

/*
 * call-seq:
 *    d.strftime([format="%F"])
 *
 * Return a formatted string.
 */
static VALUE
d_lite_strftime(int argc, VALUE *argv, VALUE self)
{
    return date_strftime_internal(argc, argv, self,
				  "%F", d_lite_set_vtm_and_timev);
}

/*
 * call-seq:
 *    d.marshal_dump
 *
 * Dump to Marshal format.
 */
static VALUE
d_lite_marshal_dump(VALUE self)
{
    VALUE a;

    get_d1(self);

    if (!light_mode_p(dat))
	a = rb_ary_new3(3, dat->r.ajd, dat->r.of, dat->r.sg);
    else {
	get_d_jd(dat);
	a = rb_assoc_new(LONG2NUM(dat->l.jd), DBL2NUM(dat->l.sg));
    }

    if (FL_TEST(self, FL_EXIVAR)) {
	rb_copy_generic_ivar(a, self);
	FL_SET(a, FL_EXIVAR);
    }

    return a;
}

/*
 * call-seq:
 *    d.marshal_load(ary)
 *
 * Load from Marshal format.
 */
static VALUE
d_lite_marshal_load(VALUE self, VALUE a)
{
    get_d1(self);

    if (TYPE(a) != T_ARRAY)
	rb_raise(rb_eTypeError, "expected an array");

    switch (RARRAY_LEN(a)) {
      case 3:
	dat->r.ajd = RARRAY_PTR(a)[0];
	dat->r.of = RARRAY_PTR(a)[1];
	dat->r.sg = RARRAY_PTR(a)[2];
	dat->r.cache = rb_hash_new();
	dat->r.flags = 0;
	break;
      case 2:
	dat->l.jd = NUM2LONG(RARRAY_PTR(a)[0]);
	dat->l.sg = NUM2DBL(RARRAY_PTR(a)[1]);
	dat->l.year = 0;
	dat->l.mon = 0;
	dat->l.mday = 0;
	dat->l.flags = LIGHT_MODE | HAVE_JD;
	break;
      default:
	rb_raise(rb_eTypeError, "invalid size");
	break;
    }

    if (FL_TEST(a, FL_EXIVAR)) {
	rb_copy_generic_ivar(self, a);
	FL_SET(self, FL_EXIVAR);
    }

    return self;
}

static VALUE
d_right_cache(VALUE self)
{
    get_d1(self);
    if (light_mode_p(dat))
	return Qnil;
    return dat->r.cache;
}

/* datetime light */

inline static VALUE
dt_lite_s_new_internal(VALUE klass, long jd, int df,
		       long sf, int of, double sg,
		       int y, int m, int d,
		       int h, int min, int s,
		       unsigned flags)
{
    union DateTimeData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateTimeData, 0, -1, dat);

    dat->l.jd = jd;
    dat->l.df = df;
    dat->l.sf = sf;
    dat->l.of = of;
    dat->l.sg = sg;
    dat->l.year = y;
    dat->l.mon = m;
    dat->l.mday = d;
    dat->l.hour = h;
    dat->l.min = min;
    dat->l.sec = s;
    dat->l.flags = flags;

    return obj;
}

static VALUE
dt_lite_s_new_internal_wo_civil(VALUE klass, long jd, int df,
				long sf, int of, double sg,
				unsigned flags)
{
    return dt_lite_s_new_internal(klass, jd, df, sf, of, sg,
				  0, 0, 0, 0, 0, 0, flags);
}

static VALUE
dt_lite_s_alloc(VALUE klass)
{
    return dt_lite_s_new_internal_wo_civil(klass, 0, 0, 0, 0, 0, LIGHT_MODE);
}

static VALUE
dt_lite_s_new_l_bang(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vdf, vsf, vof, vsg;
    long jd;

    rb_scan_args(argc, argv, "05", &vjd, &vdf, &vsf, &vof, &vsg);

    if (argc < 1)
	vjd = INT2FIX(0);
    if (argc < 2)
	vdf = INT2FIX(0);
    if (argc < 3)
	vsf = INT2FIX(0);
    if (argc < 4)
	vof = INT2FIX(0);
    if (argc < 5)
	vsg = INT2FIX(0);

    if (!FIXNUM_P(vjd) ||
	!FIXNUM_P(vdf) ||
	!FIXNUM_P(vsf) ||
	!FIXNUM_P(vof))
	rb_raise(rb_eArgError, "cannot create");
    jd = NUM2LONG(vjd);
    if (!LIGHTABLE_JD(jd))
	rb_raise(rb_eArgError, "cannot create");

    return dt_lite_s_new_internal_wo_civil(klass,
					   jd,
					   FIX2INT(vdf),
					   FIX2INT(vsf),
					   FIX2INT(vof),
					   NUM2DBL(vsg),
					   LIGHT_MODE | HAVE_JD | HAVE_DF);
}

static VALUE
datetime_s_new_l_bang(int argc, VALUE *argv, VALUE klass)
{
    return dt_lite_s_new_l_bang(argc, argv, klass);
}

/*
 * call-seq:
 *    DateTime.jd([jd=0[, hour=0[, min=0[, sec=0[, offset=0[, start=Date::ITALY]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Julian Day Number +jd+ and hour +h+, minute +min+, second +s+.
 *
 * The 24-hour clock is used.  Negative values of +h+, +min+, and
 * +sec+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +min+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +of+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +sg+ specifies the Day of Calendar Reform.
 *
 * All day/time values default to 0.
 */
static VALUE
datetime_s_jd(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vh, vmin, vs, vof, vsg;
    long jd;
    int h, min, s, rh, rmin, rs, rof;
    double sg;

    rb_scan_args(argc, argv, "06", &vjd, &vh, &vmin, &vs, &vof, &vsg);

    if (!FIXNUM_P(vjd))
	return cforwardv("jd_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    jd = h = min = s = 0;
    rof = 0;

    switch (argc) {
      case 6:
      case 5:
	if (!daydiff_to_sec(vof, &rof))
	    return cforwardv("jd_r");
      case 4:
	s = NUM2INT(vs);
      case 3:
	min = NUM2INT(vmin);
      case 2:
	h = NUM2INT(vh);
      case 1:
	jd = NUM2LONG(vjd);
	if (!LIGHTABLE_JD(jd))
	    return cforwardv("jd_r");
    }

    if (jd < sg)
	return cforwardv("jd_r");

    if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	rb_raise(rb_eArgError, "invalid date");

    return dt_lite_s_new_internal(klass,
				  jd_local_to_utc(jd,
						  time_to_df(rh, rmin, rs),
						  rof),
				  0, 0, rof, sg, 0, 0, 0, rh, rmin, rs,
				  LIGHT_MODE | HAVE_JD | HAVE_TIME);
}

/*
 * call-seq:
 *    DateTime.ordinal([year=-4712[, yday=1[, hour=0[, min=0[, sec=0[, offset=0[, start=Date::ITALY]]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Ordinal Date and hour +h+, minute +min+, second +s+.
 *
 * The 24-hour clock is used.  Negative values of +h+, +min+, and
 * +sec+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +min+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +of+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +sg+ specifies the Day of Calendar Reform.
 *
 * +y+ defaults to -4712, and +d+ to 1; this is Julian Day Number
 * day 0.  The time values default to 0.
*/
static VALUE
datetime_s_ordinal(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vd, vh, vmin, vs, vof, vsg;
    int y, d, rd, h, min, s, rh, rmin, rs, rof;
    double sg;

    rb_scan_args(argc, argv, "07", &vy, &vd, &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vd)   || FIXNUM_P(vd)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return cforwardv("ordinal_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    d = 1;

    h = min = s = 0;
    rof = 0;

    switch (argc) {
      case 7:
      case 6:
	if (!daydiff_to_sec(vof, &rof))
	    return cforwardv("ordinal_r");
      case 5:
	s = NUM2INT(vs);
      case 4:
	min = NUM2INT(vmin);
      case 3:
	h = NUM2INT(vh);
      case 2:
	d = NUM2INT(vd);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return cforwardv("ordinal_r");
    }

    {
	long jd;
	int ns;

	if (!valid_ordinal_p(y, d, sg, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return cforwardv("ordinal_r");

	return dt_lite_s_new_internal(klass,
				      jd_local_to_utc(jd,
						      time_to_df(rh, rmin, rs),
						      rof),
				      0, 0, rof, sg,
				      0, 0, 0, rh, rmin, rs,
				      LIGHT_MODE | HAVE_JD | HAVE_TIME);
    }
}

/*
 * call-seq:
 *    DateTime.civil([year=-4712[, mon=1[, mday=1[, hour=0[, min=0[, sec=0[, offset=0[, start=Date::ITALY]]]]]]]])
 *    DateTime.new([year=-4712[, mon=1[, mday=1[, hour=0[, min=0[, sec=0[, offset=0[, start=Date::ITALY]]]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Civil Date and hour +h+, minute +min+, second +s+.
 *
 * The 24-hour clock is used.  Negative values of +h+, +min+, and
 * +sec+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +min+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +of+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +sg+ specifies the Day of Calendar Reform.
 *
 * +y+ defaults to -4712, +m+ to 1, and +d+ to 1; this is Julian Day
 * Number day 0.  The time values default to 0.
 */
static VALUE
datetime_s_civil(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vd, vh, vmin, vs, vof, vsg;
    int y, m, d, rm, rd, h, min, s, rh, rmin, rs, rof;
    double sg;

    rb_scan_args(argc, argv, "08", &vy, &vm, &vd, &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vm)   || FIXNUM_P(vm)) &&
	  (NIL_P(vd)   || FIXNUM_P(vd)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return cforwardv("civil_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    m = 1;
    d = 1;

    h = min = s = 0;
    rof = 0;

    switch (argc) {
      case 8:
      case 7:
	if (!daydiff_to_sec(vof, &rof))
	    return cforwardv("civil_r");
      case 6:
	s = NUM2INT(vs);
      case 5:
	min = NUM2INT(vmin);
      case 4:
	h = NUM2INT(vh);
      case 3:
	d = NUM2INT(vd);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return cforwardv("civil_r");
    }

    if (isinf(sg) && sg < 0) {
	if (!valid_gregorian_p(y, m, d, &rm, &rd))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	return dt_lite_s_new_internal(klass, 0, 0, 0, rof, sg,
				      y, rm, rd, rh, rmin, rs,
				      LIGHT_MODE | HAVE_CIVIL | HAVE_TIME);
    }
    else {
	long jd;
	int ns;

	if (!valid_civil_p(y, m, d, sg, &rm, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return cforwardv("civil_r");

	return dt_lite_s_new_internal(klass,
				      jd_local_to_utc(jd,
						      time_to_df(rh, rmin, rs),
						      rof),
				      0, 0, rof, sg,
				      y, rm, rd, rh, rmin, rs,
				      LIGHT_MODE | HAVE_JD |
				      HAVE_CIVIL | HAVE_TIME);
    }
}

/*
 * call-seq:
 *    DateTime.commercial([cwyear=-4712[, cweek=1[, cwday=1[, hour=0[, min=0[, sec=0[, offset=0[, start=Date::ITALY]]]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Commercial Date and hour +h+, minute +min+, second +s+.
 *
 * The 24-hour clock is used.  Negative values of +h+, +min+, and
 * +sec+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +min+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +of+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +sg+ specifies the Day of Calendar Reform.
 *
 * +y+ defaults to -4712, +w+ to 1, and +d+ to 1; this is
 * Julian Day Number day 0.
 * The time values default to 0.
 */
static VALUE
datetime_s_commercial(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vh, vmin, vs, vof, vsg;
    int y, w, d, rw, rd, h, min, s, rh, rmin, rs, rof;
    double sg;

    rb_scan_args(argc, argv, "08", &vy, &vw, &vd, &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vw)   || FIXNUM_P(vw)) &&
	  (NIL_P(vd)   || FIXNUM_P(vd)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return cforwardv("commercial_r");

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    y = -4712;
    w = 1;
    d = 1;

    h = min = s = 0;
    rof = 0;

    switch (argc) {
      case 8:
      case 7:
	if (!daydiff_to_sec(vof, &rof))
	    return cforwardv("commercial_r");
      case 6:
	s = NUM2INT(vs);
      case 5:
	min = NUM2INT(vmin);
      case 4:
	h = NUM2INT(vh);
      case 3:
	d = NUM2INT(vd);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_CWYEAR(y))
	    return cforwardv("commercial_r");
    }

    {
	long jd;
	int ns;

	if (!valid_commercial_p(y, w, d, sg, &rw, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return cforwardv("commercial_r");

	return dt_lite_s_new_internal(klass,
				      jd_local_to_utc(jd,
						      time_to_df(rh, rmin, rs),
						      rof),
				      0, 0, rof, sg,
				      0, 0, 0, rh, rmin, rs,
				      LIGHT_MODE | HAVE_JD | HAVE_TIME);
    }
}

/*
 * call-seq:
 *    DateTime.now([start=Date::ITALY])
 *
 * Create a new DateTime object representing the current time.
 *
 * +sg+ specifies the Day of Calendar Reform.
 */
static VALUE
datetime_s_now(int argc, VALUE *argv, VALUE klass)
{
    VALUE vsg;
    double sg;
#ifdef HAVE_CLOCK_GETTIME
    struct timespec ts;
#else
    struct timeval tv;
#endif
    time_t sec;
    struct tm tm;
    long y, sf;
    int m, d, h, min, s, of;

    rb_scan_args(argc, argv, "01", &vsg);

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

#ifdef HAVE_CLOCK_GETTIME
    if (clock_gettime(CLOCK_REALTIME, &ts) == -1)
	rb_sys_fail("clock_gettime");
    sec = ts.tv_sec;
#else
    if (gettimeofday(&tv, NULL) == -1)
	rb_sys_fail("gettimeofday");
    sec = tv.tv_sec;
#endif
    localtime_r(&sec, &tm);

    y = tm.tm_year + 1900;
    m = tm.tm_mon + 1;
    d = tm.tm_mday;
    h = tm.tm_hour;
    min = tm.tm_min;
    s = tm.tm_sec;
    if (s == 60)
	s = 59;
#ifdef HAVE_STRUCT_TM_TM_GMTOFF
    of = (int)tm.tm_gmtoff;
#else
    of = (int)-timezone;
#endif
#ifdef HAVE_CLOCK_GETTIME
    sf = ts.tv_nsec;
#else
    sf = tv.tv_usec * 1000;
#endif

    if (!LIGHTABLE_YEAR(y))
	rb_raise(rb_eArgError, "cannot create");

    if (isinf(sg) && sg < 0)
	return dt_lite_s_new_internal(klass, 0, 0, sf, of, sg,
				      (int)y, m, d, h, min, s,
				      LIGHT_MODE | HAVE_CIVIL | HAVE_TIME);
    else {
	long jd;
	int ns;

	civil_to_jd((int)y, m, d, sg, &jd, &ns);

	return dt_lite_s_new_internal(klass,
				      jd_local_to_utc(jd,
						      time_to_df(h, min, s),
						      of),
				      0, sf, of, sg,
				      (int)y, m, d, h, min, s,
				      LIGHT_MODE | HAVE_JD |
				      HAVE_CIVIL | HAVE_TIME);
    }
}

/*
 * call-seq:
 *    dt.ajd
 *
 * Get the date as an Astronomical Julian Day Number.
 */
static VALUE
dt_lite_ajd(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return dat->r.ajd;
    {
	VALUE r;

	get_dt_jd(dat);
	get_dt_df(dat);
	r = f_sub(INT2FIX(dat->l.jd), rhalf);
	if (dat->l.df)
	    r = f_add(r, rb_rational_new2(INT2FIX(dat->l.df),
					  INT2FIX(DAY_IN_SECONDS)));
	if (dat->l.sf)
	    r = f_add(r, rb_rational_new2(INT2FIX(dat->l.sf),
					  day_in_nanoseconds));
	return r;
    }
}

/*
 * call-seq:
 *    dt.amjd
 *
 * Get the date as an Astronomical Modified Julian Day Number.
 */
static VALUE
dt_lite_amjd(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("amjd_r");
    {
	VALUE r;

	get_dt_jd(dat);
	get_dt_df(dat);
	r = rb_rational_new1(LONG2NUM(dat->l.jd - 2400001L));
	if (dat->l.df)
	    r = f_add(r, rb_rational_new2(INT2FIX(dat->l.df),
					  INT2FIX(DAY_IN_SECONDS)));
	if (dat->l.sf)
	    r = f_add(r, rb_rational_new2(INT2FIX(dat->l.sf),
					  day_in_nanoseconds));
	return r;
    }
}

/*
 * call-seq:
 *    dt.jd
 *
 * Get the date as a Julian Day Number.
 */
static VALUE
dt_lite_jd(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("jd_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	return INT2FIX(local_jd(dat));
    }
}

/*
 * call-seq:
 *    dt.mjd
 *
 * Get the date as a Modified Julian Day Number.
 */
static VALUE
dt_lite_mjd(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("mjd_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	return LONG2NUM(local_jd(dat) - 2400001L);
    }
}

/*
 * call-seq:
 *    dt.ld
 *
 * Get the date as a Lilian Day Number.
 */
static VALUE
dt_lite_ld(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("ld_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	return LONG2NUM(local_jd(dat) - 2299160L);
    }
}

/*
 * call-seq:
 *    dt.year
 *
 * Get the year of this date.
 */
static VALUE
dt_lite_year(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("year_r");
    {
	get_dt_civil(dat);
	return INT2FIX(dat->l.year);
    }
}

/*
 * call-seq:
 *    dt.yday
 *
 * Get the day-of-the-year of this date.
 *
 * January 1 is day-of-the-year 1
 */
static VALUE
dt_lite_yday(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("yday_r");
    {
	get_dt_civil(dat);
	return INT2FIX(civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday));
    }
}

/*
 * call-seq:
 *    dt.mon
 *
 * Get the month of this date.
 *
 * January is month 1.
 */
static VALUE
dt_lite_mon(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("mon_r");
    {
	get_dt_civil(dat);
	return INT2FIX(dat->l.mon);
    }
}

/*
 * call-seq:
 *    dt.mday
 *
 * Get the day-of-the-month of this date.
 */
static VALUE
dt_lite_mday(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("mday_r");
    {
	get_dt_civil(dat);
	return INT2FIX(dat->l.mday);
    }
}

/*
 * call-seq:
 *    dt.day_fraction
 *
 * Get any fractional day part of the date.
 */
static VALUE
dt_lite_day_fraction(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("day_fraction_r");
    {
	get_dt_df(dat);
	return rb_rational_new2(INT2FIX(local_df(dat)),
				INT2FIX(DAY_IN_SECONDS));
    }
}

static VALUE
dt_lite_wnum0(VALUE self)
{
    int ry, rw, rd;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("wnum0_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_weeknum(local_jd(dat), 0, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

static VALUE
dt_lite_wnum1(VALUE self)
{
    int ry, rw, rd;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("wnum1_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_weeknum(local_jd(dat), 1, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

/*
 * call-seq:
 *    dt.hour
 *
 * Get the hour of this date.
 */
static VALUE
dt_lite_hour(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("hour_r");
    {
	get_dt_time(dat);
	return INT2FIX(dat->l.hour);
    }
}

/*
 * call-seq:
 *    dt.min
 *    dt.minute
 *
 * Get the minute of this date.
 */
static VALUE
dt_lite_min(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("min_r");
    {
	get_dt_time(dat);
	return INT2FIX(dat->l.min);
    }
}

/*
 * call-seq:
 *    dt.sec
 *    dt.second
 *
 * Get the second of this date.
 */
static VALUE
dt_lite_sec(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("sec_r");
    {
	get_dt_time(dat);
	return INT2FIX(dat->l.sec);
    }
}

/*
 * call-seq:
 *    dt.sec_fraction
 *    dt.second_fraction
 *
 * Get the fraction-of-a-second of this date.
 */
static VALUE
dt_lite_sec_fraction(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("sec_fraction_r");
    return rb_rational_new2(INT2FIX(dat->l.sf), INT2FIX(SECOND_IN_NANOSECONDS));
}

/*
 * call-seq:
 *    dt.offset
 *
 * Get the offset of this date.
 */
static VALUE
dt_lite_offset(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return dat->r.of;
    return rb_rational_new2(INT2FIX(dat->l.of), INT2FIX(DAY_IN_SECONDS));
}

#define decode_offset(of,s,h,m)\
{\
    int a;\
    s = (of < 0) ? '-' : '+';\
    a = (of < 0) ? -of : of;\
    h = a / 3600;\
    m = a % 3600 / 60;\
}

/*
 * call-seq:
 *    dt.zone
 *
 * Get the zone name of this date.
 */
static VALUE
dt_lite_zone(VALUE self)
{
    int s, h, m;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("zone_r");
    decode_offset(dat->l.of, s, h, m);
    return rb_enc_sprintf(rb_usascii_encoding(), "%c%02d:%02d", s, h, m);
}

/*
 * call-seq:
 *    dt.cwyear
 *
 * Get the commercial year of this date.  See *Commercial* *Date*
 * in the introduction for how this differs from the normal year.
 */
static VALUE
dt_lite_cwyear(VALUE self)
{
    int ry, rw, rd;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("cwyear_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_commercial(local_jd(dat), dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(ry);
    }
}

/*
 * call-seq:
 *    dt.cweek
 *
 * Get the commercial week of the year of this date.
 */
static VALUE
dt_lite_cweek(VALUE self)
{
    int ry, rw, rd;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("cweek_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_commercial(local_jd(dat), dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

/*
 * call-seq:
 *    dt.cwday
 *
 * Get the commercial day of the week of this date.  Monday is
 * commercial day-of-week 1; Sunday is commercial day-of-week 7.
 */
static VALUE
dt_lite_cwday(VALUE self)
{
    int w;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("cwday_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	w = jd_to_wday(local_jd(dat));
	if (w == 0)
	    w = 7;
	return INT2FIX(w);
    }
}

/*
 * call-seq:
 *    dt.wday
 *
 * Get the week day of this date.  Sunday is day-of-week 0;
 * Saturday is day-of-week 6.
 */
static VALUE
dt_lite_wday(VALUE self)
{
    int w;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("wday_r");
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	w = jd_to_wday(local_jd(dat));
	return INT2FIX(w);
    }
}

/*
 * call-seq:
 *    dt.julian?
 *
 * Is the current date old-style (Julian Calendar)?
 */
static VALUE
dt_lite_julian_p(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("julian_r?");
    return Qfalse;
}

/*
 * call-seq:
 *    dt.gregorian?
 *
 * Is the current date new-style (Gregorian Calendar)?
 */
static VALUE
dt_lite_gregorian_p(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("gregorian_r?");
    return Qtrue;
}

/*
 * call-seq:
 *    dt.leap?
 *
 * Is this a leap year?
 */
static VALUE
dt_lite_leap_p(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("leap_r?");
    {
	get_dt_civil(dat);
	return leap_p(dat->l.year) ? Qtrue : Qfalse;
    }
}

/*
 * call-seq:
 *    dt.start
 *
 * When is the Day of Calendar Reform for this Date object?
 */
static VALUE
dt_lite_start(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return dat->r.sg;
    return DBL2NUM(dat->l.sg);
}

/*
 * call-seq:
 *    dt.new_start([start=Date::ITALY])
 *
 * Create a copy of this Date object using a new Day of Calendar Reform.
 */
static VALUE
dt_lite_new_start(int argc, VALUE *argv, VALUE self)
{
    VALUE vsg;
    double sg;

    get_dt1(self);

    if (!light_mode_p(dat))
	return iforwardv("new_start_r");

    rb_scan_args(argc, argv, "01", &vsg);

    if (!NIL_P(vsg))
	sg = NUM2DBL(vsg);
    else
	sg = ITALY;

    {
	get_dt_jd(dat);
	get_dt_df(dat);

	if (dat->l.jd < sg)
	    return iforwardv("new_start_r");

	return dt_lite_s_new_internal_wo_civil(CLASS_OF(self),
					       dat->l.jd,
					       dat->l.df,
					       dat->l.sf,
					       dat->l.of,
					       sg,
					       LIGHT_MODE | HAVE_JD | HAVE_DF);
    }
}

/*
 * call-seq:
 *    dt.new_offset([offset=0])
 *
 * Create a copy of this Date object using a new offset.
 */
static VALUE
dt_lite_new_offset(int argc, VALUE *argv, VALUE self)
{
    VALUE vof;
    int rof;

    get_dt1(self);

    if (!light_mode_p(dat))
	return iforwardv("new_offset_r");

    rb_scan_args(argc, argv, "01", &vof);

    if (NIL_P(vof))
	rof = 0;
    else {
	if (!daydiff_to_sec(vof, &rof))
	    return iforwardv("new_offset_r");
    }

    {
	get_dt_jd(dat);
	get_dt_df(dat);

	return dt_lite_s_new_internal_wo_civil(CLASS_OF(self),
					       dat->l.jd,
					       dat->l.df,
					       dat->l.sf,
					       rof,
					       dat->l.sg,
					       LIGHT_MODE | HAVE_JD | HAVE_DF);
    }
}

/*
 * call-seq:
 *    dt + n
 *
 * Return a new Date object that is +n+ days later than the
 * current one.
 *
 * +n+ may be a negative value, in which case the new Date
 * is earlier than the current one; however, #-() might be
 * more intuitive.
 *
 * If +n+ is not a Numeric, a TypeError will be thrown.  In
 * particular, two Dates cannot be added to each other.
 */
static VALUE
dt_lite_plus(VALUE self, VALUE other)
{
    get_dt1(self);

    if (!light_mode_p(dat))
	return iforwardop("plus_r");

    switch (TYPE(other)) {
      case T_FIXNUM:
	{
	    long jd;

	    get_dt1(self);
	    get_dt_jd(dat);
	    get_dt_df(dat);

	    jd = dat->l.jd + FIX2LONG(other);

	    if (LIGHTABLE_JD(jd) && jd >= dat->l.sg)
		return dt_lite_s_new_internal(CLASS_OF(self),
					      jd,
					      dat->l.df,
					      dat->l.sf,
					      dat->l.of,
					      dat->l.sg,
					      0, 0, 0,
					      dat->l.hour,
					      dat->l.min,
					      dat->l.sec,
					      dat->l.flags & ~HAVE_CIVIL);
	}
	break;
      case T_FLOAT:
	{
	    long sf;
	    double jd, o, tmp;
	    int s, df;

	    get_dt1(self);
	    get_dt_jd(dat);
	    get_dt_df(dat);

	    jd = dat->l.jd;
	    o = NUM2DBL(other);

	    if (o < 0) {
		s = -1;
		o = -o;
	    }
	    else
		s = +1;

	    o = modf(o, &jd);
	    o *= DAY_IN_SECONDS;
	    o = modf(o, &tmp);
	    df = (int)tmp;
	    o *= SECOND_IN_NANOSECONDS;
	    sf = (long)round(o);

	    if (s < 0) {
		jd = -jd;
		df = -df;
		sf = -sf;
	    }

	    sf = dat->l.sf + sf;
	    if (sf < 0) {
		df -= 1;
		sf += SECOND_IN_NANOSECONDS;
	    }
	    else if (sf >= SECOND_IN_NANOSECONDS) {
		df += 1;
		sf -= SECOND_IN_NANOSECONDS;
	    }

	    df = dat->l.df + df;
	    if (df < 0) {
		jd -= 1;
		df += DAY_IN_SECONDS;
	    }
	    else if (df >= DAY_IN_SECONDS) {
		jd += 1;
		df -= DAY_IN_SECONDS;
	    }

	    jd = dat->l.jd + jd;

	    if (LIGHTABLE_JD(jd) && jd >= dat->l.sg)
		return dt_lite_s_new_internal(CLASS_OF(self),
					      (long)jd,
					      df,
					      sf,
					      dat->l.of,
					      dat->l.sg,
					      0, 0, 0,
					      dat->l.hour,
					      dat->l.min,
					      dat->l.sec,
					      dat->l.flags &
					      ~HAVE_CIVIL &
					      ~HAVE_TIME);
	}
	break;
    }
    return iforwardop("plus_r");
}

/*
 * call-seq:
 *    dt - n
 *    dt - dt2
 *
 * If +x+ is a Numeric value, create a new Date object that is
 * +x+ days earlier than the current one.
 *
 * If +x+ is a Date, return the number of days between the
 * two dates; or, more precisely, how many days later the current
 * date is than +x+.
 *
 * If +x+ is neither Numeric nor a Date, a TypeError is raised.
 */
static VALUE
dt_lite_minus(VALUE self, VALUE other)
{
    if (k_date_p(other))
	return minus_dd(self, other);

    switch (TYPE(other)) {
      case T_FIXNUM:
	return dt_lite_plus(self, LONG2NUM(-FIX2LONG(other)));
      case T_FLOAT:
	return dt_lite_plus(self, DBL2NUM(-NUM2DBL(other)));
    }
    return iforwardop("minus_r");
}

/*
 * call-seq:
 *    dt <=> n
 *    dt <=> d2
 *
 * Compare this date with another date.
 *
 * +other+ can also be a Numeric value, in which case it is
 * interpreted as an Astronomical Julian Day Number.
 *
 * Comparison is by Astronomical Julian Day Number, including
 * fractional days.  This means that both the time and the
 * offset are taken into account when comparing
 * two DateTime instances.  When comparing a DateTime instance
 * with a Date instance, the time of the latter will be
 * considered as falling on midnight UTC.
 */
static VALUE
dt_lite_cmp(VALUE self, VALUE other)
{
    if (k_date_p(other))
	return cmp_dd(self, other);
    return iforwardop("cmp_r");
}

/*
 * call-seq:
 *    dt == other
 *
 * The relationship operator for Date.
 *
 * Compares dates by Julian Day Number.  When comparing
 * two DateTime instances, or a DateTime with a Date,
 * the instances will be regarded as equivalent if they
 * fall on the same date in local time.
 */
static VALUE
dt_lite_equal(VALUE self, VALUE other)
{
    if (k_date_p(other))
	return equal_dd(self, other);
    return iforwardop("equal_r");
}

/*
 * call-seq:
 *    dt.eql?(other)
 *
 * Is this Date equal to +other+?
 *
 * +other+ must both be a Date object, and represent the same date.
 */
static VALUE
dt_lite_eql_p(VALUE self, VALUE other)
{
    if (k_date_p(other))
	return eql_p_dd(self, other);
    return iforwardop("eql_r?");
}

/*
 * call-seq:
 *    dt.hash
 *
 * Calculate a hash value for this date.
 */
static VALUE
dt_lite_hash(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("hash_r");
    return rb_hash(dt_lite_ajd(self));
}

/*
 * call-seq:
 *    dt.to_s
 *
 * Return the date as a human-readable string.
 */
static VALUE
dt_lite_to_s(VALUE self)
{
    int s, h, m;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("to_s_r");
    {
	get_dt_civil(dat);
	get_dt_time(dat);
	decode_offset(dat->l.of, s, h, m);
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "%.4d-%02d-%02dT%02d:%02d:%02d%c%02d:%02d",
			      dat->l.year, dat->l.mon, dat->l.mday,
			      dat->l.hour, dat->l.min, dat->l.sec,
			      s, h, m);
    }
}

/*
 * call-seq:
 *    dt.inspect
 *
 * Return internal object state as a programmer-readable string.
 */
static VALUE
dt_lite_inspect(VALUE self)
{
    int s, h, m;

    get_dt1(self);
    if (!light_mode_p(dat))
	return iforward0("inspect_r");
    {
	get_dt_civil(dat);
	get_dt_time(dat);
	get_dt_jd(dat);
	get_dt_df(dat);
	decode_offset(dat->l.of, s, h, m);
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "#<%s[L]: "
			      "%.4d-%02d-%02dT%02d:%02d:%02d%c%02d:%02d "
			      "((%ldj,%ds,%.0fn),%d/86400,%.0f)>",
			      rb_obj_classname(self),
			      dat->l.year, dat->l.mon, dat->l.mday,
			      dat->l.hour, dat->l.min, dat->l.sec,
			      s, h, m,
			      dat->l.jd, dat->l.df, (double)dat->l.sf,
			      dat->l.of, dat->l.sg);
    }
}

static void
dt_lite_set_vtm_and_timev(VALUE self, struct vtm *vtm, VALUE *timev)
{
    get_dt1(self);

    if (!light_mode_p(dat)) {
	vtm->year = iforward0("year_r");
	vtm->mon = FIX2INT(iforward0("mon_r"));
	vtm->mday = FIX2INT(iforward0("mday_r"));
	vtm->hour = FIX2INT(iforward0("hour_r"));
	vtm->min = FIX2INT(iforward0("min_r"));
	vtm->sec = FIX2INT(iforward0("sec_r"));
	vtm->subsecx = iforward0("sec_fraction_r");
	vtm->utc_offset = INT2FIX(0);
	vtm->wday = FIX2INT(iforward0("wday_r"));
	vtm->yday = FIX2INT(iforward0("yday_r"));
	vtm->isdst = 0;
	vtm->zone = RSTRING_PTR(iforward0("zone_r"));
	*timev = f_mul(f_sub(dat->r.ajd,
			     rb_rational_new2(INT2FIX(4881175), INT2FIX(2))),
		       INT2FIX(86400));
    }
    else {
	get_dt_jd(dat);
	get_dt_civil(dat);
	get_dt_time(dat);

	vtm->year = LONG2NUM(dat->l.year);
	vtm->mon = dat->l.mon;
	vtm->mday = dat->l.mday;
	vtm->hour = dat->l.hour;
	vtm->min = dat->l.min;
	vtm->sec = dat->l.sec;
	vtm->subsecx = LONG2NUM(dat->l.sf);
	vtm->utc_offset = INT2FIX(dat->l.of);
	vtm->wday = jd_to_wday(local_jd(dat));
	vtm->yday = civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday);
	vtm->isdst = 0;
	vtm->zone = RSTRING_PTR(dt_lite_zone(self));
	*timev = f_mul(f_sub(dt_lite_ajd(self),
			     rb_rational_new2(INT2FIX(4881175), INT2FIX(2))),
		       INT2FIX(86400));
    }
}

/*
 * call-seq:
 *    dt.strftime([format="%FT%T%:z"])
 *
 * Return a formatted string.
 */
static VALUE
dt_lite_strftime(int argc, VALUE *argv, VALUE self)
{
    return date_strftime_internal(argc, argv, self,
				  "%FT%T%:z", dt_lite_set_vtm_and_timev);
}

/*
 * call-seq:
 *    dt.marshal_dump
 *
 * Dump to Marshal format.
 */
static VALUE
dt_lite_marshal_dump(VALUE self)
{
    VALUE a;

    get_dt1(self);

    if (!light_mode_p(dat))
	a = rb_ary_new3(3, dat->r.ajd, dat->r.of, dat->r.sg);
    else {
	get_dt_jd(dat);
	get_dt_df(dat);
	a = rb_ary_new3(5,
			LONG2NUM(dat->l.jd), INT2FIX(dat->l.df),
			INT2FIX(dat->l.sf),
			INT2FIX(dat->l.of), DBL2NUM(dat->l.sg));
    }

    if (FL_TEST(self, FL_EXIVAR)) {
	rb_copy_generic_ivar(a, self);
	FL_SET(a, FL_EXIVAR);
    }

    return a;
}

/*
 * call-seq:
 *    dt.marshal_load(ary)
 *
 * Load from Marshal format.
 */
static VALUE
dt_lite_marshal_load(VALUE self, VALUE a)
{
    get_dt1(self);

    if (TYPE(a) != T_ARRAY)
	rb_raise(rb_eTypeError, "expected an array");

    switch (RARRAY_LEN(a)) {
      case 3:
	dat->r.ajd = RARRAY_PTR(a)[0];
	dat->r.of = RARRAY_PTR(a)[1];
	dat->r.sg = RARRAY_PTR(a)[2];
	dat->r.cache = rb_hash_new();
	dat->r.flags = 0;
	break;
      case 5:
	dat->l.jd = NUM2LONG(RARRAY_PTR(a)[0]);
	dat->l.df = FIX2INT(RARRAY_PTR(a)[1]);
	dat->l.sf = FIX2INT(RARRAY_PTR(a)[2]);
	dat->l.of = FIX2INT(RARRAY_PTR(a)[3]);
	dat->l.sg = NUM2DBL(RARRAY_PTR(a)[4]);
	dat->l.year = 0;
	dat->l.mon = 0;
	dat->l.mday = 0;
	dat->l.hour = 0;
	dat->l.min = 0;
	dat->l.sec = 0;
	dat->l.flags = LIGHT_MODE | HAVE_JD | HAVE_DF;
	break;
      default:
	rb_raise(rb_eTypeError, "invalid size");
	break;
    }

    if (FL_TEST(a, FL_EXIVAR)) {
	rb_copy_generic_ivar(self, a);
	FL_SET(self, FL_EXIVAR);
    }

    return self;
}

static VALUE
dt_right_cache(VALUE self)
{
    get_dt1(self);
    if (light_mode_p(dat))
	return Qnil;
    return dat->r.cache;
}

#ifndef NDEBUG
static int
test_civil(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "%ld...%ld (%ld) - %.0f\n", from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, m, d, ns;
	long rj;

	jd_to_civil(j, sg, &y, &m, &d);
	civil_to_jd(y, m, d, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%ld != %ld\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_civil(VALUE klass)
{
    double greg = -NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY")));

    if (!test_civil(MIN_JD, MIN_JD + 366, greg))
	return Qfalse;
    if (!test_civil(2305814, 2598007, greg))
	return Qfalse;
    if (!test_civil(MAX_JD - 366, MAX_JD, greg))
	return Qfalse;

    if (!test_civil(MIN_JD, MIN_JD + 366, ITALY))
	return Qfalse;
    if (!test_civil(2305814, 2598007, ITALY))
	return Qfalse;
    if (!test_civil(MAX_JD - 366, MAX_JD, ITALY))
	return Qfalse;

    return Qtrue;
}

static int
test_ordinal(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "%ld...%ld (%ld) - %.0f\n", from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, d, ns;
	long rj;

	jd_to_ordinal(j, sg, &y, &d);
	ordinal_to_jd(y, d, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%ld != %ld\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_ordinal(VALUE klass)
{
    double greg = -NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY")));

    if (!test_ordinal(MIN_JD, MIN_JD + 366, greg))
	return Qfalse;
    if (!test_ordinal(2305814, 2598007, greg))
	return Qfalse;
    if (!test_ordinal(MAX_JD - 366, MAX_JD, greg))
	return Qfalse;

    if (!test_ordinal(MIN_JD, MIN_JD + 366, ITALY))
	return Qfalse;
    if (!test_ordinal(2305814, 2598007, ITALY))
	return Qfalse;
    if (!test_ordinal(MAX_JD - 366, MAX_JD, ITALY))
	return Qfalse;

    return Qtrue;
}

static int
test_commercial(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "%ld...%ld (%ld) - %.0f\n", from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, w, d, ns;
	long rj;

	jd_to_commercial(j, sg, &y, &w, &d);
	commercial_to_jd(y, w, d, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%ld != %ld\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_commercial(VALUE klass)
{
    double greg = -NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY")));

    if (!test_commercial(MIN_JD, MIN_JD + 366, greg))
	return Qfalse;
    if (!test_commercial(2305814, 2598007, greg))
	return Qfalse;
    if (!test_commercial(MAX_JD - 366, MAX_JD, greg))
	return Qfalse;

    if (!test_commercial(MIN_JD, MIN_JD + 366, ITALY))
	return Qfalse;
    if (!test_commercial(2305814, 2598007, ITALY))
	return Qfalse;
    if (!test_commercial(MAX_JD - 366, MAX_JD, ITALY))
	return Qfalse;

    return Qtrue;
}

static int
test_weeknum(long from, long to, int f, double sg)
{
    long j;

    fprintf(stderr, "%ld...%ld (%ld) - %.0f\n", from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, w, d, ns;
	long rj;

	jd_to_weeknum(j, f, sg, &y, &w, &d);
	weeknum_to_jd(y, w, d, f, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%ld != %ld\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_weeknum(VALUE klass)
{
    double greg = -NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY")));
    int f;

    for (f = 0; f <= 1; f++) {
	if (!test_weeknum(MIN_JD, MIN_JD + 366, f, greg))
	    return Qfalse;
	if (!test_weeknum(2305814, 2598007, f, greg))
	    return Qfalse;
	if (!test_weeknum(MAX_JD - 366, MAX_JD, f, greg))
	    return Qfalse;

	if (!test_weeknum(MIN_JD, MIN_JD + 366, f, ITALY))
	    return Qfalse;
	if (!test_weeknum(2305814, 2598007, f, ITALY))
	    return Qfalse;
	if (!test_weeknum(MAX_JD - 366, MAX_JD, f, ITALY))
	    return Qfalse;
    }

    return Qtrue;
}


static int
test_nth_kday(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "%ld...%ld (%ld) - %.0f\n", from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, m, n, k, ns;
	long rj;

	jd_to_nth_kday(j, sg, &y, &m, &n, &k);
	nth_kday_to_jd(y, m, n, k, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%ld != %ld\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_nth_kday(VALUE klass)
{
    double greg = -NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY")));

    if (!test_nth_kday(MIN_JD, MIN_JD + 366, greg))
	return Qfalse;
    if (!test_nth_kday(2305814, 2598007, greg))
	return Qfalse;
    if (!test_nth_kday(MAX_JD - 366, MAX_JD, greg))
	return Qfalse;

    if (!test_nth_kday(MIN_JD, MIN_JD + 366, ITALY))
	return Qfalse;
    if (!test_nth_kday(2305814, 2598007, ITALY))
	return Qfalse;
    if (!test_nth_kday(MAX_JD - 366, MAX_JD, ITALY))
	return Qfalse;

    return Qtrue;
}

static VALUE
date_s_test_all(VALUE klass)
{
    if (date_s_test_civil(klass) == Qfalse)
	return Qfalse;
    if (date_s_test_ordinal(klass) == Qfalse)
	return Qfalse;
    if (date_s_test_commercial(klass) == Qfalse)
	return Qfalse;
    if (date_s_test_weeknum(klass) == Qfalse)
	return Qfalse;
    if (date_s_test_nth_kday(klass) == Qfalse)
	return Qfalse;
    return Qtrue;
}
#endif

void
Init_date_core(void)
{
    assert(fprintf(stderr, "assert() is now active\n"));

    rzero = rb_rational_new1(INT2FIX(0));
    rhalf = rb_rational_new2(INT2FIX(1), INT2FIX(2));
    day_in_nanoseconds = rb_ll2inum(DAY_IN_NANOSECONDS);

    rb_gc_register_mark_object(rzero);
    rb_gc_register_mark_object(rhalf);
    rb_gc_register_mark_object(day_in_nanoseconds);

    /* date */

    cDate = rb_define_class("Date", rb_cObject);

    rb_define_alloc_func(cDate, d_lite_s_alloc);
    rb_define_singleton_method(cDate, "new_r!", date_s_new_r_bang, -1);
    rb_define_singleton_method(cDate, "new_l!", date_s_new_l_bang, -1);

    rb_define_singleton_method(cDate, "valid_jd?", date_s_valid_jd_p, -1);
    rb_define_singleton_method(cDate, "valid_ordinal?",
			       date_s_valid_ordinal_p, -1);
    rb_define_singleton_method(cDate, "valid_civil?", date_s_valid_civil_p, -1);
    rb_define_singleton_method(cDate, "valid_date?", date_s_valid_civil_p, -1);
    rb_define_singleton_method(cDate, "valid_commercial?",
			       date_s_valid_commercial_p, -1);
    rb_define_singleton_method(cDate, "jd", date_s_jd, -1);
    rb_define_singleton_method(cDate, "ordinal", date_s_ordinal, -1);
    rb_define_singleton_method(cDate, "civil", date_s_civil, -1);
    rb_define_singleton_method(cDate, "new", date_s_civil, -1);
    rb_define_singleton_method(cDate, "commercial", date_s_commercial, -1);
    rb_define_singleton_method(cDate, "today", date_s_today, -1);

    rb_define_method(cDate, "ajd", d_lite_ajd, 0);
    rb_define_method(cDate, "amjd", d_lite_amjd, 0);
    rb_define_method(cDate, "jd", d_lite_jd, 0);
    rb_define_method(cDate, "mjd", d_lite_mjd, 0);
    rb_define_method(cDate, "ld", d_lite_ld, 0);

    rb_define_method(cDate, "year", d_lite_year, 0);
    rb_define_method(cDate, "yday", d_lite_yday, 0);
    rb_define_method(cDate, "mon", d_lite_mon, 0);
    rb_define_method(cDate, "month", d_lite_mon, 0);
    rb_define_method(cDate, "mday", d_lite_mday, 0);
    rb_define_method(cDate, "day", d_lite_mday, 0);
    rb_define_method(cDate, "day_fraction", d_lite_day_fraction, 0);

    rb_define_private_method(cDate, "wnum0", d_lite_wnum0, 0);
    rb_define_private_method(cDate, "wnum1", d_lite_wnum1, 0);

    rb_define_private_method(cDate, "hour", d_lite_hour, 0);
    rb_define_private_method(cDate, "min", d_lite_min, 0);
    rb_define_private_method(cDate, "minute", d_lite_min, 0);
    rb_define_private_method(cDate, "sec", d_lite_sec, 0);
    rb_define_private_method(cDate, "second", d_lite_sec, 0);
    rb_define_private_method(cDate, "sec_fraction", d_lite_sec_fraction, 0);
    rb_define_private_method(cDate, "second_fraction", d_lite_sec_fraction, 0);
    rb_define_private_method(cDate, "offset", d_lite_offset, 0);
    rb_define_private_method(cDate, "zone", d_lite_zone, 0);

    rb_define_method(cDate, "cwyear", d_lite_cwyear, 0);
    rb_define_method(cDate, "cweek", d_lite_cweek, 0);
    rb_define_method(cDate, "cwday", d_lite_cwday, 0);

    rb_define_method(cDate, "wday", d_lite_wday, 0);

    rb_define_method(cDate, "julian?", d_lite_julian_p, 0);
    rb_define_method(cDate, "gregorian?", d_lite_gregorian_p, 0);
    rb_define_method(cDate, "leap?", d_lite_leap_p, 0);

    rb_define_method(cDate, "start", d_lite_start, 0);
    rb_define_method(cDate, "new_start", d_lite_new_start, -1);
    rb_define_private_method(cDate, "new_offset", d_lite_new_offset, -1);

    rb_define_method(cDate, "+", d_lite_plus, 1);
    rb_define_method(cDate, "-", d_lite_minus, 1);

    rb_define_method(cDate, "<=>", d_lite_cmp, 1);
    rb_define_method(cDate, "===", d_lite_equal, 1);
    rb_define_method(cDate, "eql?", d_lite_eql_p, 1);
    rb_define_method(cDate, "hash", d_lite_hash, 0);

    rb_define_method(cDate, "to_s", d_lite_to_s, 0);
    rb_define_method(cDate, "inspect", d_lite_inspect, 0);
    rb_define_method(cDate, "strftime", d_lite_strftime, -1);

    rb_define_method(cDate, "marshal_dump", d_lite_marshal_dump, 0);
    rb_define_method(cDate, "marshal_load", d_lite_marshal_load, 1);

    rb_define_private_method(cDate, "__ca__", d_right_cache, 0);

    /* datetime */

    cDateTime = rb_define_class("DateTime", cDate);

    rb_define_alloc_func(cDateTime, dt_lite_s_alloc);
    rb_define_singleton_method(cDateTime, "new_l!", datetime_s_new_l_bang, -1);

    rb_undef_method(CLASS_OF(cDateTime), "today");

    rb_define_singleton_method(cDateTime, "jd", datetime_s_jd, -1);
    rb_define_singleton_method(cDateTime, "ordinal", datetime_s_ordinal, -1);
    rb_define_singleton_method(cDateTime, "civil", datetime_s_civil, -1);
    rb_define_singleton_method(cDateTime, "new", datetime_s_civil, -1);
    rb_define_singleton_method(cDateTime, "commercial",
			       datetime_s_commercial, -1);
    rb_define_singleton_method(cDateTime, "now", datetime_s_now, -1);

    rb_define_method(cDateTime, "ajd", dt_lite_ajd, 0);
    rb_define_method(cDateTime, "amjd", dt_lite_amjd, 0);
    rb_define_method(cDateTime, "jd", dt_lite_jd, 0);
    rb_define_method(cDateTime, "mjd", dt_lite_mjd, 0);
    rb_define_method(cDateTime, "ld", dt_lite_ld, 0);

    rb_define_method(cDateTime, "year", dt_lite_year, 0);
    rb_define_method(cDateTime, "yday", dt_lite_yday, 0);
    rb_define_method(cDateTime, "mon", dt_lite_mon, 0);
    rb_define_method(cDateTime, "month", dt_lite_mon, 0);
    rb_define_method(cDateTime, "mday", dt_lite_mday, 0);
    rb_define_method(cDateTime, "day", dt_lite_mday, 0);
    rb_define_method(cDateTime, "day_fraction", dt_lite_day_fraction, 0);

    rb_define_private_method(cDateTime, "wnum0", dt_lite_wnum0, 0);
    rb_define_private_method(cDateTime, "wnum1", dt_lite_wnum1, 0);

    rb_define_method(cDateTime, "hour", dt_lite_hour, 0);
    rb_define_method(cDateTime, "min", dt_lite_min, 0);
    rb_define_method(cDateTime, "minute", dt_lite_min, 0);
    rb_define_method(cDateTime, "sec", dt_lite_sec, 0);
    rb_define_method(cDateTime, "second", dt_lite_sec, 0);
    rb_define_method(cDateTime, "sec_fraction", dt_lite_sec_fraction, 0);
    rb_define_method(cDateTime, "second_fraction", dt_lite_sec_fraction, 0);
    rb_define_method(cDateTime, "offset", dt_lite_offset, 0);
    rb_define_method(cDateTime, "zone", dt_lite_zone, 0);

    rb_define_method(cDateTime, "cwyear", dt_lite_cwyear, 0);
    rb_define_method(cDateTime, "cweek", dt_lite_cweek, 0);
    rb_define_method(cDateTime, "cwday", dt_lite_cwday, 0);

    rb_define_method(cDateTime, "wday", dt_lite_wday, 0);

    rb_define_method(cDateTime, "julian?", dt_lite_julian_p, 0);
    rb_define_method(cDateTime, "gregorian?", dt_lite_gregorian_p, 0);
    rb_define_method(cDateTime, "leap?", dt_lite_leap_p, 0);

    rb_define_method(cDateTime, "start", dt_lite_start, 0);
    rb_define_method(cDateTime, "new_start", dt_lite_new_start, -1);
    rb_define_method(cDateTime, "new_offset", dt_lite_new_offset, -1);

    rb_define_method(cDateTime, "+", dt_lite_plus, 1);
    rb_define_method(cDateTime, "-", dt_lite_minus, 1);

    rb_define_method(cDateTime, "<=>", dt_lite_cmp, 1);
    rb_define_method(cDateTime, "===", dt_lite_equal, 1);
    rb_define_method(cDateTime, "eql?", dt_lite_eql_p, 1);
    rb_define_method(cDateTime, "hash", dt_lite_hash, 0);

    rb_define_method(cDateTime, "to_s", dt_lite_to_s, 0);
    rb_define_method(cDateTime, "inspect", dt_lite_inspect, 0);
    rb_define_method(cDateTime, "strftime", dt_lite_strftime, -1);

    rb_define_method(cDateTime, "marshal_dump", dt_lite_marshal_dump, 0);
    rb_define_method(cDateTime, "marshal_load", dt_lite_marshal_load, 1);

    rb_define_private_method(cDateTime, "__ca__", dt_right_cache, 0);

#ifndef NDEBUG
    rb_define_singleton_method(cDate, "test_civil", date_s_test_civil, 0);
    rb_define_singleton_method(cDate, "test_ordinal", date_s_test_ordinal, 0);
    rb_define_singleton_method(cDate, "test_commercial",
			       date_s_test_commercial, 0);
    rb_define_singleton_method(cDate, "test_weeknum", date_s_test_weeknum, 0);
    rb_define_singleton_method(cDate, "test_nth_kday", date_s_test_nth_kday, 0);
    rb_define_singleton_method(cDate, "test_all", date_s_test_all, 0);
#endif
}

/*
Local variables:
c-file-style: "ruby"
End:
*/
