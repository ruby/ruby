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

#define USE_DPK

static ID id_cmp, id_le_p, id_ge_p, id_eqeq_p;
static VALUE cDate, cDateTime;
static VALUE half_days_in_day, unix_epoch_in_ajd, day_in_nanoseconds;
static double positive_inf, negative_inf;

#define HAVE_JD     (1 << 0)
#define HAVE_DF     (1 << 1)
#define HAVE_CIVIL  (1 << 2)
#define HAVE_TIME   (1 << 3)
#define COMPLEX_DAT (1 << 7)

#define have_jd_p(x) ((x)->flags & HAVE_JD)
#define have_df_p(x) ((x)->flags & HAVE_DF)
#define have_civil_p(x) ((x)->flags & HAVE_CIVIL)
#define have_time_p(x) ((x)->flags & HAVE_TIME)
#define complex_dat_p(x) ((x)->flags & COMPLEX_DAT)
#define simple_dat_p(x) (!complex_dat_p(x))

#define ITALY 2299161
#define ENGLAND 2361222
#define JULIAN positive_inf
#define GREGORIAN negative_inf
#define DEFAULT_SG ITALY

#define UNIX_EPOCH_IN_AJD unix_epoch_in_ajd /* 1970-01-01 */
#define UNIX_EPOCH_IN_CJD INT2FIX(2440588)

#define MINUTE_IN_SECONDS 60
#define HOUR_IN_SECONDS 3600
#define DAY_IN_SECONDS 86400
#define SECOND_IN_NANOSECONDS 1000000000

#define JC_PERIOD0      1461 /* 365.25 * 4 */
#define GC_PERIOD0 146097 /* 365.2425 * 400 */
#define CM_PERIOD0 71149239 /* (lcm 7 1461 146097) */
#define CM_PERIOD (0xfffffff / CM_PERIOD0 * CM_PERIOD0)
#define CM_PERIOD_JCY (CM_PERIOD / JC_PERIOD0 * 4)
#define CM_PERIOD_GCY (CM_PERIOD / GC_PERIOD0 * 400)

#ifdef USE_PACK
#define SEC_WIDTH  6
#define MIN_WIDTH  6
#define HOUR_WIDTH 5
#define MDAY_WIDTH 5
#define MON_WIDTH  4

#define SEC_SHIFT  0
#define MIN_SHIFT  SEC_WIDTH
#define HOUR_SHIFT (MIN_WIDTH + SEC_WIDTH)
#define MDAY_SHIFT (HOUR_WIDTH + MIN_WIDTH + SEC_WIDTH)
#define MON_SHIFT  (MDAY_WIDTH + HOUR_WIDTH + MIN_WIDTH + SEC_WIDTH)

#define PK_MASK(x) ((1 << (x)) - 1)

#define EX_SEC(x)  (((x) >> SEC_SHIFT)  & PK_MASK(SEC_WIDTH))
#define EX_MIN(x)  (((x) >> MIN_SHIFT)  & PK_MASK(MIN_WIDTH))
#define EX_HOUR(x) (((x) >> HOUR_SHIFT) & PK_MASK(HOUR_WIDTH))
#define EX_MDAY(x) (((x) >> MDAY_SHIFT) & PK_MASK(MDAY_WIDTH))
#define EX_MON(x)  (((x) >> MON_SHIFT)  & PK_MASK(MON_WIDTH))

#define PACK5(m,d,h,min,s) \
    (((m) << MON_SHIFT) | ((d) << MDAY_SHIFT) |\
     ((h) << HOUR_SHIFT) | ((min) << MIN_SHIFT) | ((s) << SEC_SHIFT))

#define PACK2(m,d) \
    (((m) << MON_SHIFT) | ((d) << MDAY_SHIFT))
#endif

struct SimpleDateData
{
    unsigned flags;
    VALUE nth;	/* not always canonicalized */
    int jd;	/* as utc */
    double sg;  /* -oo, 2299161..2451910 or +oo */
    /* decoded as utc=local */
    int year;	/* truncated */
#ifndef USE_PACK
    int mon;
    int mday;
#else
    /* packed civil */
    unsigned pd;
#endif
};

struct ComplexDateData
{
    unsigned flags;
    VALUE nth;	/* not always canonicalized */
    int jd; 	/* as utc */
    int df;	/* as utc, in secs */
    VALUE sf;	/* in nano secs */
    int of;	/* in secs */
    double sg;  /* -oo, 2299161..2451910 or +oo */
    /* decoded as local */
    int year;	/* truncated */
#ifndef USE_PACK
    int mon;
    int mday;
    int hour;
    int min;
    int sec;
#else
    /* packed civil */
    unsigned pd;
#endif
};

union DateData {
    unsigned flags;
    struct SimpleDateData s;
    struct ComplexDateData c;
};

#define get_d1(x)\
    union DateData *dat;\
    Data_Get_Struct(x, union DateData, dat);

#define get_d2(x,y)\
    union DateData *adat, *bdat;\
    Data_Get_Struct(x, union DateData, adat);\
    Data_Get_Struct(y, union DateData, bdat);

#define f_boolcast(x) ((x) ? Qtrue : Qfalse)

#define f_abs(x) rb_funcall(x, rb_intern("abs"), 0)
#define f_negate(x) rb_funcall(x, rb_intern("-@"), 0)
#define f_add(x,y) rb_funcall(x, '+', 1, y)
#define f_sub(x,y) rb_funcall(x, '-', 1, y)
#define f_mul(x,y) rb_funcall(x, '*', 1, y)
#define f_div(x,y) rb_funcall(x, '/', 1, y)
#define f_quo(x,y) rb_funcall(x, rb_intern("quo"), 1, y)
#define f_idiv(x,y) rb_funcall(x, rb_intern("div"), 1, y)
#define f_mod(x,y) rb_funcall(x, '%', 1, y)
#define f_remainder(x,y) rb_funcall(x, rb_intern("remainder"), 1, y)
#define f_expt(x,y) rb_funcall(x, rb_intern("**"), 1, y)
#define f_floor(x) rb_funcall(x, rb_intern("floor"), 0)
#define f_ceil(x) rb_funcall(x, rb_intern("ceil"), 0)
#define f_truncate(x) rb_funcall(x, rb_intern("truncate"), 0)
#define f_round(x) rb_funcall(x, rb_intern("round"), 0)

#define f_to_r(x) rb_funcall(x, rb_intern("to_r"), 0)
#define f_to_s(x) rb_funcall(x, rb_intern("to_s"), 0)
#define f_inspect(x) rb_funcall(x, rb_intern("inspect"), 0)

#define f_add3(x,y,z) f_add(f_add(x, y), z)
#define f_sub3(x,y,z) f_sub(f_sub(x, y), z)

inline static VALUE
f_cmp(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y)) {
	long c = FIX2LONG(x) - FIX2LONG(y);
	if (c > 0)
	    c = 1;
	else if (c < 0)
	    c = -1;
	return INT2FIX(c);
    }
    return rb_funcall(x, id_cmp, 1, y);
}

inline static VALUE
f_lt_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) < FIX2LONG(y));
    return rb_funcall(x, '<', 1, y);
}

inline static VALUE
f_gt_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) > FIX2LONG(y));
    return rb_funcall(x, '>', 1, y);
}

inline static VALUE
f_le_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) <= FIX2LONG(y));
    return rb_funcall(x, id_le_p, 1, y);
}

inline static VALUE
f_ge_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) >= FIX2LONG(y));
    return rb_funcall(x, rb_intern(">="), 1, y);
}

inline static VALUE
f_eqeq_p(VALUE x, VALUE y)
{
    if (FIXNUM_P(x) && FIXNUM_P(y))
	return f_boolcast(FIX2LONG(x) == FIX2LONG(y));
    return rb_funcall(x, rb_intern("=="), 1, y);
}

#define f_equal_p(x,y) rb_funcall(x, rb_intern("==="), 1, y)

inline static VALUE
f_zero_p(VALUE x)
{
    switch (TYPE(x)) {
      case T_FIXNUM:
	return f_boolcast(FIX2LONG(x) == 0);
      case T_BIGNUM:
	return Qfalse;
      case T_RATIONAL:
	{
	    VALUE num = RRATIONAL(x)->num;

	    return f_boolcast(FIXNUM_P(num) && FIX2LONG(num) == 0);
	}
    }
    return rb_funcall(x, id_eqeq_p, 1, INT2FIX(0));
}

#define f_nonzero_p(x) (!f_zero_p(x))

inline static VALUE
f_negative_p(VALUE x)
{
    if (FIXNUM_P(x))
	return f_boolcast(FIX2LONG(x) < 0);
    return rb_funcall(x, '<', 1, INT2FIX(0));
}

#define f_positive_p(x) (!f_negative_p(x))

#define f_ajd(x) rb_funcall(x, rb_intern("ajd"), 0)
#define f_jd(x) rb_funcall(x, rb_intern("jd"), 0)
#define f_year(x) rb_funcall(x, rb_intern("year"), 0)
#define f_mon(x) rb_funcall(x, rb_intern("mon"), 0)
#define f_mday(x) rb_funcall(x, rb_intern("mday"), 0)
#define f_wday(x) rb_funcall(x, rb_intern("wday"), 0)
#define f_hour(x) rb_funcall(x, rb_intern("hour"), 0)
#define f_min(x) rb_funcall(x, rb_intern("min"), 0)
#define f_sec(x) rb_funcall(x, rb_intern("sec"), 0)

#define f_compact(x) rb_funcall(x, rb_intern("compact"), 0)

/* copied from time.c */
#define NDIV(x,y) (-(-((x)+1)/(y))-1)
#define NMOD(x,y) ((y)-(-((x)+1)%(y))-1)
#define DIV(n,d) ((n)<0 ? NDIV((n),(d)) : (n)/(d))
#define MOD(n,d) ((n)<0 ? NMOD((n),(d)) : (n)%(d))

/* light base */

static int c_valid_civil_p(int, int, int, double,
			   int *, int *, int *, int *);

static int
c_find_fdoy(int y, double sg, int *rjd, int *ns)
{
    int d, rm, rd;

    for (d = 1; d < 31; d++)
	if (c_valid_civil_p(y, 1, d, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}

static int
c_find_ldoy(int y, double sg, int *rjd, int *ns)
{
    int i, rm, rd;

    for (i = 0; i < 30; i++)
	if (c_valid_civil_p(y, 12, 31 - i, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}

#ifndef NDEBUG
static int
c_find_fdom(int y, int m, double sg, int *rjd, int *ns)
{
    int d, rm, rd;

    for (d = 1; d < 31; d++)
	if (c_valid_civil_p(y, m, d, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}
#endif

static int
c_find_ldom(int y, int m, double sg, int *rjd, int *ns)
{
    int i, rm, rd;

    for (i = 0; i < 30; i++)
	if (c_valid_civil_p(y, m, 31 - i, sg, &rm, &rd, rjd, ns))
	    return 1;
    return 0;
}

static void
c_civil_to_jd(int y, int m, int d, double sg, int *rjd, int *ns)
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

    *rjd = (int)jd;
}

static void
c_jd_to_civil(int jd, double sg, int *ry, int *rm, int *rdom)
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
c_ordinal_to_jd(int y, int d, double sg, int *rjd, int *ns)
{
    int ns2;

    c_find_fdoy(y, sg, rjd, &ns2);
    *rjd += d - 1;
    *ns = (*rjd < sg) ? 0 : 1;
}

static void
c_jd_to_ordinal(int jd, double sg, int *ry, int *rd)
{
    int rm2, rd2, rjd, ns;

    c_jd_to_civil(jd, sg, ry, &rm2, &rd2);
    c_find_fdoy(*ry, sg, &rjd, &ns);
    *rd = (jd - rjd) + 1;
}

static void
c_commercial_to_jd(int y, int w, int d, double sg, int *rjd, int *ns)
{
    int rjd2, ns2;

    c_find_fdoy(y, sg, &rjd2, &ns2);
    rjd2 += 3;
    *rjd =
	(rjd2 - MOD((rjd2 - 1) + 1, 7)) +
	7 * (w - 1) +
	(d - 1);
    *ns = (*rjd < sg) ? 0 : 1;
}

static void
c_jd_to_commercial(int jd, double sg, int *ry, int *rw, int *rd)
{
    int ry2, rm2, rd2, a, rjd2, ns2;

    c_jd_to_civil(jd - 3, sg, &ry2, &rm2, &rd2);
    a = ry2;
    c_commercial_to_jd(a + 1, 1, 1, sg, &rjd2, &ns2);
    if (jd >= rjd2)
	*ry = a + 1;
    else {
	c_commercial_to_jd(a, 1, 1, sg, &rjd2, &ns2);
	*ry = a;
    }
    *rw = 1 + DIV(jd - rjd2, 7);
    *rd = MOD(jd + 1, 7);
    if (*rd == 0)
	*rd = 7;
}

static void
c_weeknum_to_jd(int y, int w, int d, int f, double sg, int *rjd, int *ns)
{
    int rjd2, ns2;

    c_find_fdoy(y, sg, &rjd2, &ns2);
    rjd2 += 6;
    *rjd = (rjd2 - MOD(((rjd2 - f) + 1), 7) - 7) + 7 * w + d;
    *ns = (*rjd < sg) ? 0 : 1;
}

static void
c_jd_to_weeknum(int jd, int f, double sg, int *ry, int *rw, int *rd)
{
    int rm, rd2, rjd, ns, j;

    c_jd_to_civil(jd, sg, ry, &rm, &rd2);
    c_find_fdoy(*ry, sg, &rjd, &ns);
    rjd += 6;
    j = jd - (rjd - MOD((rjd - f) + 1, 7)) + 7;
    *rw = (int)DIV(j, 7);
    *rd = (int)MOD(j, 7);
}

#ifndef NDEBUG
static void
c_nth_kday_to_jd(int y, int m, int n, int k, double sg, int *rjd, int *ns)
{
    int rjd2, ns2;

    if (n > 0) {
	c_find_fdom(y, m, sg, &rjd2, &ns2);
	rjd2 -= 1;
    }
    else {
	c_find_ldom(y, m, sg, &rjd2, &ns2);
	rjd2 += 7;
    }
    *rjd = (rjd2 - MOD((rjd2 - k) + 1, 7)) + 7 * n;
    *ns = (*rjd < sg) ? 0 : 1;
}
#endif

inline static int
c_jd_to_wday(int jd)
{
    return MOD(jd + 1, 7);
}

#ifndef NDEBUG
static void
c_jd_to_nth_kday(int jd, double sg, int *ry, int *rm, int *rn, int *rk)
{
    int rd, rjd, ns2;

    c_jd_to_civil(jd, sg, ry, rm, &rd);
    c_find_fdom(*ry, *rm, sg, &rjd, &ns2);
    *rn = DIV(jd - rjd, 7) + 1;
    *rk = c_jd_to_wday(jd);
}
#endif

static int
c_valid_ordinal_p(int y, int d, double sg,
		  int *rd, int *rjd, int *ns)
{
    int ry2, rd2;

    if (d < 0) {
	int rjd2, ns2;

	if (!c_find_ldoy(y, sg, &rjd2, &ns2))
	    return 0;
	c_jd_to_ordinal(rjd2 + d + 1, sg, &ry2, &rd2);
	if (ry2 != y)
	    return 0;
	d = rd2;
    }
    c_ordinal_to_jd(y, d, sg, rjd, ns);
    c_jd_to_ordinal(*rjd, sg, &ry2, &rd2);
    if (ry2 != y || rd2 != d)
	return 0;
    return 1;
}

static const int monthtab[2][13] = {
    { 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
    { 0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
};

inline static int
c_leap_p(int y)
{
    return (MOD(y, 4) == 0 && y % 100 != 0) || (MOD(y, 400) == 0);
}

static int
c_last_day_of_month(int y, int m)
{
    return monthtab[c_leap_p(y) ? 1 : 0][m];
}

static int
c_valid_gregorian_p(int y, int m, int d, int *rm, int *rd)
{
    int last;

    if (m < 0)
	m += 13;
    last = c_last_day_of_month(y, m);
    if (d < 0)
	d = last + d + 1;

    *rm = m;
    *rd = d;

    return !(m < 0 || m > 12 ||
	     d < 1 || d > last);
}

static int
c_valid_civil_p(int y, int m, int d, double sg,
		int *rm, int *rd, int *rjd, int *ns)
{
    int ry;

    if (m < 0)
	m += 13;
    if (d < 0) {
	if (!c_find_ldom(y, m, sg, rjd, ns))
	    return 0;
	c_jd_to_civil(*rjd + d + 1, sg, &ry, rm, rd);
	if (ry != y || *rm != m)
	    return 0;
	d = *rd;
    }
    c_civil_to_jd(y, m, d, sg, rjd, ns);
    c_jd_to_civil(*rjd, sg, &ry, rm, rd);
    if (ry != y || *rm != m || *rd != d)
	return 0;
    return 1;
}

static int
c_valid_commercial_p(int y, int w, int d, double sg,
		     int *rw, int *rd, int *rjd, int *ns)
{
    int ns2, ry2, rw2, rd2;

    if (d < 0)
	d += 8;
    if (w < 0) {
	int rjd2;

	c_commercial_to_jd(y + 1, 1, 1, sg, &rjd2, &ns2);
	c_jd_to_commercial(rjd2 + w * 7, sg, &ry2, &rw2, &rd2);
	if (ry2 != y)
	    return 0;
	w = rw2;
    }
    c_commercial_to_jd(y, w, d, sg, rjd, ns);
    c_jd_to_commercial(*rjd, sg, &ry2, rw, rd);
    if (y != ry2 || w != *rw || d != *rd)
	return 0;
    return 1;
}

static int
c_valid_weeknum_p(int y, int w, int d, int f, double sg,
		  int *rw, int *rd, int *rjd, int *ns)
{
    int ns2, ry2, rw2, rd2;

    if (d < 0)
	d += 7;
    if (w < 0) {
	int rjd2;

	c_weeknum_to_jd(y + 1, 1, f, f, sg, &rjd2, &ns2);
	c_jd_to_weeknum(rjd2 + w * 7, f, sg, &ry2, &rw2, &rd2);
	if (ry2 != y)
	    return 0;
	w = rw2;
    }
    c_weeknum_to_jd(y, w, d, f, sg, rjd, ns);
    c_jd_to_weeknum(*rjd, f, sg, &ry2, rw, rd);
    if (y != ry2 || w != *rw || d != *rd)
	return 0;
    return 1;
}

#ifndef NDEBUG
static int
c_valid_nth_kday_p(int y, int m, int n, int k, double sg,
		   int *rm, int *rn, int *rk, int *rjd, int *ns)
{
    int ns2, ry2, rm2, rn2, rk2;

    if (k < 0)
	k += 7;
    if (n < 0) {
	int t, ny, nm, rjd2;

	t = y * 12 + m;
	ny = DIV(t, 12);
	nm = MOD(t, 12) + 1;

	c_nth_kday_to_jd(ny, nm, 1, k, sg, &rjd2, &ns2);
	c_jd_to_nth_kday(rjd2 + n * 7, sg, &ry2, &rm2, &rn2, &rk2);
	if (ry2 != y || rm2 != m)
	    return 0;
	n = rn2;
    }
    c_nth_kday_to_jd(y, m, n, k, sg, rjd, ns);
    c_jd_to_nth_kday(*rjd, sg, &ry2, rm, rn, rk);
    if (y != ry2 || m != *rm || n != *rn || k != *rk)
	return 0;
    return 1;
}
#endif

static int
c_valid_time_p(int h, int min, int s, int *rh, int *rmin, int *rs)
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

static int
c_valid_start_p(double sg)
{
    if (!isinf(sg)) {
	if (sg < ITALY)
	    return 0;
	if (sg > 2451910)
	    return 0;
    }
    return 1;
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

inline static int
jd_local_to_utc(int jd, int df, int of)
{
    df -= of;
    if (df < 0)
	jd -= 1;
    else if (df >= DAY_IN_SECONDS)
	jd += 1;
    return jd;
}

inline static int
jd_utc_to_local(int jd, int df, int of)
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
    return h * HOUR_IN_SECONDS + min * MINUTE_IN_SECONDS + s;
}

static VALUE
sec_to_day(VALUE s)
{
    return f_quo(s, INT2FIX(DAY_IN_SECONDS));
}

static VALUE
isec_to_day(int s)
{
    return sec_to_day(INT2FIX(s));
}

static VALUE
ns_to_day(VALUE n)
{
    return f_quo(n, day_in_nanoseconds);
}

static VALUE
ns_to_sec(VALUE n)
{
    return f_quo(n, INT2FIX(SECOND_IN_NANOSECONDS));
}

#ifndef NDEBUG
static VALUE
ins_to_day(int n)
{
    return ns_to_day(INT2FIX(n));
}
#endif

static VALUE
day_to_sec(VALUE d)
{
    return f_mul(d, INT2FIX(DAY_IN_SECONDS));
}

#ifndef NDEBUG
static VALUE
day_to_ns(VALUE d)
{
    return f_mul(d, day_in_nanoseconds);
}
#endif

static VALUE
sec_to_ns(VALUE s)
{
    return f_mul(s, INT2FIX(SECOND_IN_NANOSECONDS));
}

static VALUE
div_day(VALUE d, VALUE *f)
{
    if (f)
	*f = f_mod(d, INT2FIX(1));
    return f_floor(d);
}

static VALUE
div_df(VALUE d, VALUE *f)
{
    VALUE s = day_to_sec(d);

    if (f)
	*f = f_mod(s, INT2FIX(1));
    return f_floor(s);
}

#ifndef NDEBUG
static VALUE
div_sf(VALUE s, VALUE *f)
{
    VALUE n = sec_to_ns(s);

    if (f)
	*f = f_mod(n, INT2FIX(1));
    return f_floor(n);
}
#endif

static void
decode_day(VALUE d, VALUE *jd, VALUE *df, VALUE *sf)
{
    VALUE f;

    *jd = div_day(d, &f);
    *df = div_df(f, &f);
    *sf = sec_to_ns(f);
}

inline static double
s_sg(union DateData *x)
{
    if (isinf(x->s.sg))
	return x->s.sg;
    if (f_zero_p(x->s.nth))
	return x->s.sg;
    else if (f_negative_p(x->s.nth))
	return positive_inf;
    return negative_inf;
}

inline static double
c_sg(union DateData *x)
{
    if (isinf(x->c.sg))
	return x->c.sg;
    if (f_zero_p(x->c.nth))
	return x->c.sg;
    else if (f_negative_p(x->c.nth))
	return positive_inf;
    return negative_inf;
}

inline static void
get_s_jd(union DateData *x)
{
    assert(simple_dat_p(x));
    if (!have_jd_p(x)) {
	int jd, ns;

	assert(have_civil_p(x));
#ifndef USE_PACK
	c_civil_to_jd(x->s.year, x->s.mon, x->s.mday, s_sg(x), &jd, &ns);
#else
	c_civil_to_jd(x->s.year, EX_MON(x->s.pd), EX_MDAY(x->s.pd),
		      s_sg(x), &jd, &ns);
#endif
	x->s.jd = jd;
	x->s.flags |= HAVE_JD;
    }
}

inline static void
get_s_civil(union DateData *x)
{
    assert(simple_dat_p(x));
    if (!have_civil_p(x)) {
	int y, m, d;

	assert(have_jd_p(x));
	c_jd_to_civil(x->s.jd, s_sg(x), &y, &m, &d);
	x->s.year = y;
#ifndef USE_PACK
	x->s.mon = m;
	x->s.mday = d;
#else
	x->s.pd = PACK2(m, d);
#endif
	x->s.flags |= HAVE_CIVIL;
    }
}

inline static void
get_c_df(union DateData *x)
{
    assert(complex_dat_p(x));
    if (!have_df_p(x)) {
	assert(have_time_p(x));
#ifndef USE_PACK
	x->c.df = df_local_to_utc(time_to_df(x->c.hour, x->c.min, x->c.sec),
				  x->c.of);
#else
	x->c.df = df_local_to_utc(time_to_df(EX_HOUR(x->c.pd),
					     EX_MIN(x->c.pd),
					     EX_SEC(x->c.pd)),
				  x->c.of);
#endif
	x->c.flags |= HAVE_DF;
    }
}

inline static void
get_c_time(union DateData *x)
{
    assert(complex_dat_p(x));
    if (!have_time_p(x)) {
#ifndef USE_PACK
	int r;
	assert(have_df_p(x));
	r = df_utc_to_local(x->c.df, x->c.of);
	x->c.hour = r / HOUR_IN_SECONDS;
	r %= HOUR_IN_SECONDS;
	x->c.min = r / MINUTE_IN_SECONDS;
	x->c.sec = r % MINUTE_IN_SECONDS;
	x->c.flags |= HAVE_TIME;
#else
	int r, m, d, h, min, s;

	assert(have_df_p(x));
	r = df_utc_to_local(x->c.df, x->c.of);
	m = EX_MON(x->c.pd);
	d = EX_MDAY(x->c.pd);
	h = r / HOUR_IN_SECONDS;
	r %= HOUR_IN_SECONDS;
	min = r / MINUTE_IN_SECONDS;
	s = r % MINUTE_IN_SECONDS;
	x->c.pd = PACK5(m, d, h, min, s);
	x->c.flags |= HAVE_TIME;
#endif
    }
}

inline static void
get_c_jd(union DateData *x)
{
    assert(complex_dat_p(x));
    if (!have_jd_p(x)) {
	int jd, ns;

	assert(have_civil_p(x));
#ifndef USE_PACK
	c_civil_to_jd(x->c.year, x->c.mon, x->c.mday, c_sg(x), &jd, &ns);
#else
	c_civil_to_jd(x->c.year, EX_MON(x->c.pd), EX_MDAY(x->c.pd),
		      c_sg(x), &jd, &ns);
#endif

	get_c_time(x);
#ifndef USE_PACK
	x->c.jd = jd_local_to_utc(jd,
				  time_to_df(x->c.hour, x->c.min, x->c.sec),
				  x->c.of);
#else
	x->c.jd = jd_local_to_utc(jd,
				  time_to_df(EX_HOUR(x->c.pd),
					     EX_MIN(x->c.pd),
					     EX_SEC(x->c.pd)),
				  x->c.of);
#endif
	x->c.flags |= HAVE_JD;
    }
}

inline static void
get_c_civil(union DateData *x)
{
    assert(complex_dat_p(x));
    if (!have_civil_p(x)) {
#ifndef USE_PACK
	int jd, y, m, d;
#else
	int jd, y, m, d, h, min, s;
#endif

	assert(have_jd_p(x));
	get_c_df(x);
	jd = jd_utc_to_local(x->c.jd, x->c.df, x->c.of);
	c_jd_to_civil(jd, c_sg(x), &y, &m, &d);
	x->c.year = y;
#ifndef USE_PACK
	x->c.mon = m;
	x->c.mday = d;
#else
	h = EX_HOUR(x->c.pd);
	min = EX_MIN(x->c.pd);
	s = EX_SEC(x->c.pd);
	x->c.pd = PACK5(m, d, h, min, s);
#endif
	x->c.flags |= HAVE_CIVIL;
    }
}

inline static int
local_jd(union DateData *x)
{
    assert(complex_dat_p(x));
    assert(have_jd_p(x));
    assert(have_df_p(x));
    return jd_utc_to_local(x->c.jd, x->c.df, x->c.of);
}

inline static int
local_df(union DateData *x)
{
    assert(complex_dat_p(x));
    assert(have_df_p(x));
    return df_utc_to_local(x->c.df, x->c.of);
}

static void
decode_year(VALUE y, double style,
	    VALUE *nth, int *ry)
{
    int period;
    VALUE t;

    period = (style < 0) ?
	CM_PERIOD_GCY :
	CM_PERIOD_JCY;
    t = f_add(y, INT2FIX(4712)); /* shift */
    *nth = f_idiv(t, INT2FIX(period));
    if (f_nonzero_p(*nth))
	t = f_mod(t, INT2FIX(period));
    *ry = FIX2INT(t) - 4712; /* unshift */
}

static void
encode_year(VALUE nth, int y, double style,
	    VALUE *ry)
{
    int period;
    VALUE t;

    period = (style < 0) ?
	CM_PERIOD_GCY :
	CM_PERIOD_JCY;
    if (f_zero_p(nth))
	*ry = INT2FIX(y);
    else {
	t = f_mul(INT2FIX(period), nth);
	t = f_add(t, INT2FIX(y));
	*ry = t;
    }
}

static void
decode_jd(VALUE jd, VALUE *nth, int *rjd)
{
    *nth = f_idiv(jd, INT2FIX(CM_PERIOD));
    if (f_zero_p(*nth)) {
	*rjd = FIX2INT(jd);
	return;
    }
    *rjd = FIX2INT(f_mod(jd, INT2FIX(CM_PERIOD)));
}

static void
encode_jd(VALUE nth, int jd, VALUE *rjd)
{
    if (f_zero_p(nth)) {
	*rjd = INT2FIX(jd);
	return;
    }
    *rjd = f_add(f_mul(INT2FIX(CM_PERIOD), nth), INT2FIX(jd));
}

static double
style_p(VALUE y, double sg)
{
    double style = 0;

    if (isinf(sg))
	style = (sg < 0) ? negative_inf : positive_inf;
    else if (!FIXNUM_P(y))
	style = (f_positive_p(y)) ? negative_inf : positive_inf;
    else {
	if (f_lt_p(y, INT2FIX(1582)))
	    style = positive_inf;
	else if (f_gt_p(y, INT2FIX(2001)))
	    style = negative_inf;
    }
    return style;
}

static VALUE
m_nth(union DateData *x)
{
    if (simple_dat_p(x)) {
	return x->s.nth;
    }
    else {
	get_c_civil(x);
	return x->c.nth;
    }
}

static int
m_jd(union DateData *x)
{
    if (simple_dat_p(x)) {
	get_s_jd(x);
	return x->s.jd;
    }
    else {
	get_c_jd(x);
	return x->c.jd;
    }
}

static VALUE
m_real_jd(union DateData *x)
{
    VALUE nth, rjd;
    int jd;

    nth = m_nth(x);
    jd = m_jd(x);

    encode_jd(nth, jd, &rjd);
    return rjd;
}

static int
m_local_jd(union DateData *x)
{
    if (simple_dat_p(x)) {
	get_s_jd(x);
	return x->s.jd;
    }
    else {
	get_c_jd(x);
	get_c_df(x);
	return local_jd(x);
    }
}

static VALUE
m_real_local_jd(union DateData *x)
{
    VALUE nth, rjd;
    int jd;

    nth = m_nth(x);
    jd = m_local_jd(x);

    encode_jd(nth, jd, &rjd);
    return rjd;
}

static int
m_df(union DateData *x)
{
    if (simple_dat_p(x))
	return 0;
    else {
	get_c_df(x);
	return x->c.df;
    }
}

#ifndef NDEBUG
static VALUE
m_df_in_day(union DateData *x)
{
    return isec_to_day(m_df(x));
}
#endif

static int
m_local_df(union DateData *x)
{
    if (simple_dat_p(x))
	return 0;
    else {
	get_c_df(x);
	return local_df(x);
    }
}

#ifndef NDEBUG
static VALUE
m_local_df_in_day(union DateData *x)
{
    return isec_to_day(m_local_df(x));
}
#endif

static VALUE
m_sf(union DateData *x)
{
    if (simple_dat_p(x))
	return INT2FIX(0);
    else
	return x->c.sf;
}

#ifndef NDEBUG
static VALUE
m_sf_in_day(union DateData *x)
{
    return ns_to_day(m_sf(x));
}
#endif

static VALUE
m_sf_in_sec(union DateData *x)
{
    return ns_to_sec(m_sf(x));
}

static VALUE
m_fr(union DateData *x)
{
    if (simple_dat_p(x))
	return INT2FIX(0);
    else {
	int df;
	VALUE sf, fr;

	df = m_local_df(x);
	sf = m_sf(x);
	fr = isec_to_day(df);
	if (f_nonzero_p(sf))
	    fr = f_add(fr, ns_to_day(sf));
	return fr;
    }
}

static VALUE
m_ajd(union DateData *x)
{
    VALUE r, sf;
    int df;

    r = f_sub(m_real_jd(x), half_days_in_day);
    if (simple_dat_p(x))
	return r;

    df = m_df(x);
    if (df)
	r = f_add(r, isec_to_day(df));

    sf = m_sf(x);
    if (f_nonzero_p(sf))
	r = f_add(r, ns_to_day(sf));

    return r;
}

static int
m_of(union DateData *x)
{
    if (simple_dat_p(x))
	return 0;
    else {
	get_c_jd(x);
	return x->c.of;
    }
}

static VALUE
m_of_in_day(union DateData *x)
{
    return isec_to_day(m_of(x));
}

static double
m_sg(union DateData *x)
{
    if (simple_dat_p(x))
	return x->s.sg;
    else {
	get_c_jd(x);
	return x->c.sg;
    }
}

static int
m_julian_p(union DateData *x)
{
    int jd;
    double sg;

    if (simple_dat_p(x)) {
	jd = x->s.jd;
	sg = s_sg(x);
    }
    else {
	jd = x->c.jd;
	sg = c_sg(x);
    }
    if (isinf(sg))
	return sg == positive_inf;
    return jd < sg;
}

static int
m_gregorian_p(union DateData *x)
{
    return !m_julian_p(x);
}

static int
m_year(union DateData *x)
{
    if (simple_dat_p(x)) {
	get_s_civil(x);
	return x->s.year;
    }
    else {
	get_c_civil(x);
	return x->c.year;
    }
}

static VALUE
m_real_year(union DateData *x)
{
    VALUE nth, ry;
    int year;

    nth = m_nth(x);
    year = m_year(x);

    encode_year(nth, year,
		m_gregorian_p(x) ? -1 : +1,
		&ry);
    return ry;
}


#ifdef USE_PACK
static int
m_pd(union DateData *x)
{
    if (simple_dat_p(x)) {
	get_s_civil(x);
	return x->s.pd;
    }
    else {
	get_c_civil(x);
	return x->c.pd;
    }
}
#endif

static int
m_mon(union DateData *x)
{
    if (simple_dat_p(x)) {
	get_s_civil(x);
#ifndef USE_PACK
	return x->s.mon;
#else
	return EX_MON(x->s.pd);
#endif
    }
    else {
	get_c_civil(x);
#ifndef USE_PACK
	return x->c.mon;
#else
	return EX_MON(x->c.pd);
#endif
    }
}

static int
m_mday(union DateData *x)
{
    if (simple_dat_p(x)) {
	get_s_civil(x);
#ifndef USE_PACK
	return x->s.mday;
#else
	return EX_MDAY(x->s.pd);
#endif
    }
    else {
	get_c_civil(x);
#ifndef USE_PACK
	return x->c.mday;
#else
	return EX_MDAY(x->c.pd);
#endif
    }
}

static int
m_hour(union DateData *x)
{
    if (simple_dat_p(x))
	return 0;
    else {
	get_c_time(x);
#ifndef USE_PACK
	return x->c.hour;
#else
	return EX_HOUR(x->c.pd);
#endif
    }
}

static const int yeartab[2][13] = {
    { 0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 },
    { 0, 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 }
};

static int
c_gregorian_to_yday(int y, int m, int d)
{
    return yeartab[c_leap_p(y) ? 1 : 0][m] + d;
}

static void c_jd_to_ordinal(int, double, int *, int *);

static int
m_yday(union DateData *x)
{
    double sg;
    int jd, ry, rd;

    sg = m_sg(x);
    jd = m_local_jd(x);
    if ((isinf(sg) && sg < 0) ||
	(jd - sg) > 366)
	return c_gregorian_to_yday(m_year(x), m_mon(x), m_mday(x));
    c_jd_to_ordinal(jd, sg, &ry, &rd);
    return rd;
}

static int
m_min(union DateData *x)
{
    if (simple_dat_p(x))
	return 0;
    else {
	get_c_time(x);
#ifndef USE_PACK
	return x->c.min;
#else
	return EX_MIN(x->c.pd);
#endif
    }
}

static int
m_sec(union DateData *x)
{
    if (simple_dat_p(x))
	return 0;
    else {
	get_c_time(x);
#ifndef USE_PACK
	return x->c.sec;
#else
	return EX_SEC(x->c.pd);
#endif
    }
}

static int
m_wday(union DateData *x)
{
    return c_jd_to_wday(m_local_jd(x));
}

#define decode_offset(of,s,h,m)\
{\
    int a;\
    s = (of < 0) ? '-' : '+';\
    a = (of < 0) ? -of : of;\
    h = a / HOUR_IN_SECONDS;\
    m = a % HOUR_IN_SECONDS / MINUTE_IN_SECONDS;\
}

static VALUE
of2str(int of)
{
    int s, h, m;

    decode_offset(of, s, h, m);
    return rb_enc_sprintf(rb_usascii_encoding(), "%c%02d:%02d", s, h, m);
}

static VALUE
m_zone(union DateData *x)
{
    if (simple_dat_p(x))
	return rb_usascii_str_new2("+00:00");
    return of2str(m_of(x));
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

#ifndef NDEBUG
static void
civil_to_jd(VALUE y, int m, int d, double sg,
	    VALUE *nth, int *ry,
	    int *rjd,
	    int *ns)
{
    double style = style_p(y, sg);

    if (style == 0) {
	int jd;

	c_civil_to_jd(FIX2INT(y), m, d, sg, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	c_civil_to_jd(*ry, m, d, style, rjd, ns);
    }
}

static void
jd_to_civil(VALUE jd, double sg,
	    VALUE *nth, int *rjd,
	    int *ry, int *rm, int *rd)
{
    decode_jd(jd, nth, rjd);
    c_jd_to_civil(*rjd, sg, ry, rm, rd);
}

static void
ordinal_to_jd(VALUE y, int d, double sg,
	      VALUE *nth, int *ry,
	      int *rjd,
	      int *ns)
{
    double style = style_p(y, sg);

    if (style == 0) {
	int jd;

	c_ordinal_to_jd(FIX2INT(y), d, sg, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	c_ordinal_to_jd(*ry, d, style, rjd, ns);
    }
}

static void
jd_to_ordinal(VALUE jd, double sg,
	      VALUE *nth, int *rjd,
	      int *ry, int *rd)
{
    decode_jd(jd, nth, rjd);
    c_jd_to_ordinal(*rjd, sg, ry, rd);
}

static void
commercial_to_jd(VALUE y, int w, int d, double sg,
		 VALUE *nth, int *ry,
		 int *rjd,
		 int *ns)
{
    double style = style_p(y, sg);

    if (style == 0) {
	int jd;

	c_commercial_to_jd(FIX2INT(y), w, d, sg, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	c_commercial_to_jd(*ry, w, d, style, rjd, ns);
    }
}

static void
jd_to_commercial(VALUE jd, double sg,
		 VALUE *nth, int *rjd,
		 int *ry, int *rw, int *rd)
{
    decode_jd(jd, nth, rjd);
    c_jd_to_commercial(*rjd, sg, ry, rw, rd);
}

static void
weeknum_to_jd(VALUE y, int w, int d, int f, double sg,
	      VALUE *nth, int *ry,
	      int *rjd,
	      int *ns)
{
    double style = style_p(y, sg);

    if (style == 0) {
	int jd;

	c_weeknum_to_jd(FIX2INT(y), w, d, f, sg, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	c_weeknum_to_jd(*ry, w, d, f, style, rjd, ns);
    }
}

static void
jd_to_weeknum(VALUE jd, int f, double sg,
	      VALUE *nth, int *rjd,
	      int *ry, int *rw, int *rd)
{
    decode_jd(jd, nth, rjd);
    c_jd_to_weeknum(*rjd, f, sg, ry, rw, rd);
}

static void
nth_kday_to_jd(VALUE y, int m, int n, int k, double sg,
	       VALUE *nth, int *ry,
	       int *rjd,
	       int *ns)
{
    double style = style_p(y, sg);

    if (style == 0) {
	int jd;

	c_nth_kday_to_jd(FIX2INT(y), m, n, k, sg, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	c_nth_kday_to_jd(*ry, m, n, k, style, rjd, ns);
    }
}

static void
jd_to_nth_kday(VALUE jd, double sg,
	       VALUE *nth, int *rjd,
	       int *ry, int *rm, int *rn, int *rk)
{
    decode_jd(jd, nth, rjd);
    c_jd_to_nth_kday(*rjd, sg, ry, rm, rn, rk);
}
#endif

static int
valid_ordinal_p(VALUE y, int d, double sg,
		VALUE *nth, int *ry,
		int *rd, int *rjd,
		int *ns)
{
    double style = style_p(y, sg);
    int r;

    if (style == 0) {
	int jd;

	r = c_valid_ordinal_p(FIX2INT(y), d, sg, rd, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	r = c_valid_ordinal_p(*ry, d, style, rd, rjd, ns);
    }
    return r;
}

static int
valid_gregorian_p(VALUE y, int m, int d,
		  VALUE *nth, int *ry,
		  int *rm, int *rd)
{
    decode_year(y, -1, nth, ry);
    return c_valid_gregorian_p(*ry, m, d, rm, rd);
}

static int
valid_civil_p(VALUE y, int m, int d, double sg,
	      VALUE *nth, int *ry,
	      int *rm, int *rd, int *rjd,
	      int *ns)
{
    double style = style_p(y, sg);
    int r;

    if (style == 0) {
	int jd;

	r = c_valid_civil_p(FIX2INT(y), m, d, sg, rm, rd, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	r = c_valid_civil_p(*ry, m, d, style, rm, rd, rjd, ns);
    }
    return r;
}

static int
valid_commercial_p(VALUE y, int w, int d, double sg,
		   VALUE *nth, int *ry,
		   int *rw, int *rd, int *rjd,
		   int *ns)
{
    double style = style_p(y, sg);
    int r;

    if (style == 0) {
	int jd;

	r = c_valid_commercial_p(FIX2INT(y), w, d, sg, rw, rd, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	r = c_valid_commercial_p(*ry, w, d, style, rw, rd, rjd, ns);
    }
    return r;
}

static int
valid_weeknum_p(VALUE y, int w, int d, int f, double sg,
		VALUE *nth, int *ry,
		int *rw, int *rd, int *rjd,
		int *ns)
{
    double style = style_p(y, sg);
    int r;

    if (style == 0) {
	int jd;

	r = c_valid_weeknum_p(FIX2INT(y), w, d, f, sg, rw, rd, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	r = c_valid_weeknum_p(*ry, w, d, f, style, rw, rd, rjd, ns);
    }
    return r;
}

#ifndef NDEBUG
static int
valid_nth_kday_p(VALUE y, int m, int n, int k, double sg,
		 VALUE *nth, int *ry,
		 int *rm, int *rn, int *rk, int *rjd,
		 int *ns)
{
    double style = style_p(y, sg);
    int r;

    if (style == 0) {
	int jd;

	r = c_valid_nth_kday_p(FIX2INT(y), m, n, k, sg, rm, rn, rk, &jd, ns);
	decode_jd(INT2FIX(jd), nth, rjd);
	if (f_zero_p(*nth))
	    *ry = FIX2INT(y);
	else {
	    VALUE nth2;
	    decode_year(y, ns ? -1 : +1, &nth2, ry);
	}
    }
    else {
	decode_year(y, style, nth, ry);
	r = c_valid_nth_kday_p(*ry, m, n, k, style, rm, rn, rk, rjd, ns);
    }
    return r;
}
#endif

/* date light */

VALUE date_zone_to_diff(VALUE);

static int
offset_to_sec(VALUE vof, int *rof)
{
    switch (TYPE(vof)) {
      case T_FIXNUM:
	{
	    long n;

	    n = FIX2LONG(vof);
	    if (n != -1 && n != 0 && n != 1)
		return 0;
	    *rof = (int)n * DAY_IN_SECONDS;
	    return 1;
	}
      case T_FLOAT:
	{
	    double n;

	    n = NUM2DBL(vof) * DAY_IN_SECONDS;
	    if (n < -DAY_IN_SECONDS || n > DAY_IN_SECONDS)
		return 0;
	    *rof = round(n);
	    if (*rof != n)
		rb_warning("fraction of offset is ignored");
	    return 1;
	}
      case T_RATIONAL:
	{
	    VALUE vs = day_to_sec(vof);
	    VALUE vn = RRATIONAL(vs)->num;
	    VALUE vd = RRATIONAL(vs)->den;
	    long n;

	    if (FIXNUM_P(vn) && FIXNUM_P(vd) && (FIX2LONG(vd) == 1))
		n = FIX2LONG(vn);
	    else {
		vn = f_round(vs);
		if (!f_eqeq_p(vn, vs))
		    rb_warning("fraction of offset is ignored");
		if (!FIXNUM_P(vn))
		    return 0;
		n = FIX2LONG(vn);
		if (n < -DAY_IN_SECONDS || n > DAY_IN_SECONDS)
		    return 0;
	    }
	    *rof = (int)n;
	    return 1;
	}
      case T_STRING:
	{
	    VALUE vs = date_zone_to_diff(vof);
	    long n;

	    if (!FIXNUM_P(vs))
		return 0;
	    n = FIX2LONG(vs);
	    if (n < -DAY_IN_SECONDS || n > DAY_IN_SECONDS)
		return 0;
	    *rof = n;
	    return 1;
	}
    }
    return 0;
}

static VALUE
valid_jd_sub(int argc, VALUE *argv, VALUE klass, int need_jd)
{
    return argv[0];
}

#ifndef NDEBUG
static VALUE
date_s__valid_jd_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vsg;
    VALUE argv2[2];

    rb_scan_args(argc, argv, "11", &vjd, &vsg);

    argv2[0] = vjd;
    if (argc < 2)
	argv[1] = DBL2NUM(GREGORIAN);
    else
	argv[1] = vsg;

    return valid_jd_sub(2, argv2, klass, 1);
}
#endif

/*
 * call-seq:
 *    Date.valid_jd?(jd[, start=Date::ITALY])
 *
 * Is +jd+ a valid Julian Day Number?
 * Returns true or false.
 */
static VALUE
date_s_valid_jd_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vsg;
    VALUE argv2[2];

    rb_scan_args(argc, argv, "11", &vjd, &vsg);

    argv2[0] = vjd;
    if (argc < 2)
	argv[1] = INT2FIX(DEFAULT_SG);
    else
	argv[1] = vsg;

    if (NIL_P(valid_jd_sub(2, argv2, klass, 0)))
	return Qfalse;
    return Qtrue;
}

#define valid_sg(sg) \
{\
    if (!c_valid_start_p(sg)) {\
	sg = 0;\
	rb_warning("invalid start is ignored");\
    }\
}

static VALUE
valid_civil_sub(int argc, VALUE *argv, VALUE klass, int need_jd)
{
    VALUE nth, y;
    int m, d, ry, rm, rd;
    double sg;

    y = argv[0];
    m = NUM2INT(argv[1]);
    d = NUM2INT(argv[2]);
    sg = NUM2DBL(argv[3]);

    valid_sg(sg);

    if (!need_jd && isinf(sg) && sg < 0) {
	if (!valid_gregorian_p(y, m, d,
			       &nth, &ry,
			       &rm, &rd))
	    return Qnil;
	return INT2FIX(0); /* dummy */
    }
    else {
	int rjd, ns;
	VALUE rjd2;

	if (!valid_civil_p(y, m, d, sg,
			   &nth, &ry,
			   &rm, &rd, &rjd,
			   &ns))
	    return Qnil;
	if (!need_jd)
	    return INT2FIX(0); /* dummy */
	encode_jd(nth, rjd, &rjd2);
	return rjd2;
    }
}

#ifndef NDEBUG
static VALUE
date_s__valid_civil_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vd, vsg;
    VALUE argv2[4];

    rb_scan_args(argc, argv, "31", &vy, &vm, &vd, &vsg);

    argv2[0] = vy;
    argv2[1] = vm;
    argv2[2] = vd;
    if (argc < 4)
	argv2[3] = DBL2NUM(GREGORIAN);
    else
	argv2[3] = vsg;

    return valid_civil_sub(4, argv2, klass, 1);
}
#endif

/*
 * call-seq:
 *    Date.valid_civil?(year, month, mday[, start=Date::ITALY])
 *
 * Do +year+, +month+ and +mday+ (day-of-month) make a
 * valid Civil Date?  Returns true or false.
 *
 * +month+ and +mday+ can be negative, in which case they count
 * backwards from the end of the year and the end of the
 * month respectively.  No wraparound is performed, however,
 * and invalid values cause an ArgumentError to be raised.
 * A date falling in the period skipped in the Day of Calendar
 * Reform adjustment is not valid.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_valid_civil_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vd, vsg;
    VALUE argv2[4];

    rb_scan_args(argc, argv, "31", &vy, &vm, &vd, &vsg);

    argv2[0] = vy;
    argv2[1] = vm;
    argv2[2] = vd;
    if (argc < 4)
	argv2[3] = INT2FIX(DEFAULT_SG);
    else
	argv2[3] = vsg;

    if (NIL_P(valid_civil_sub(4, argv2, klass, 0)))
	return Qfalse;
    return Qtrue;
}

static VALUE
valid_ordinal_sub(int argc, VALUE *argv, VALUE klass, int need_jd)
{
    VALUE nth, y;
    int d, ry, rd;
    double sg;

    y = argv[0];
    d = NUM2INT(argv[1]);
    sg = NUM2DBL(argv[2]);

    valid_sg(sg);

    {
	int rjd, ns;
	VALUE rjd2;

	if (!valid_ordinal_p(y, d, sg,
			     &nth, &ry,
			     &rd, &rjd,
			     &ns))
	    return Qnil;
	if (!need_jd)
	    return INT2FIX(0); /* dummy */
	encode_jd(nth, rjd, &rjd2);
	return rjd2;
    }
}

#ifndef NDEBUG
static VALUE
date_s__valid_ordinal_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vd, vsg;
    VALUE argv2[3];

    rb_scan_args(argc, argv, "21", &vy, &vd, &vsg);

    argv2[0] = vy;
    argv2[1] = vd;
    if (argc < 3)
	argv2[2] = DBL2NUM(GREGORIAN);
    else
	argv2[2] = vsg;

    return valid_ordinal_sub(3, argv2, klass, 1);
}
#endif

/*
 * call-seq:
 *    Date.valid_ordinal?(year, yday[, start=Date::ITALY])
 *
 * Do the +year+ and +yday+ (day-of-year) make a valid Ordinal Date?
 * Returns true or false.
 *
 * +yday+ can be a negative number, in which case it counts backwards
 * from the end of the year (-1 being the last day of the year).
 * No year wraparound is performed, however, so valid values of
 * +yday+ are -365 .. -1, 1 .. 365 on a non-leap-year,
 * -366 .. -1, 1 .. 366 on a leap year.
 * A date falling in the period skipped in the Day of Calendar Reform
 * adjustment is not valid.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_valid_ordinal_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vd, vsg;
    VALUE argv2[3];

    rb_scan_args(argc, argv, "21", &vy, &vd, &vsg);

    argv2[0] = vy;
    argv2[1] = vd;
    if (argc < 3)
	argv2[2] = INT2FIX(DEFAULT_SG);
    else
	argv2[2] = vsg;

    if (NIL_P(valid_ordinal_sub(3, argv2, klass, 0)))
	return Qfalse;
    return Qtrue;
}

static VALUE
valid_commercial_sub(int argc, VALUE *argv, VALUE klass, int need_jd)
{
    VALUE nth, y;
    int w, d, ry, rw, rd;
    double sg;

    y = argv[0];
    w = NUM2INT(argv[1]);
    d = NUM2INT(argv[2]);
    sg = NUM2DBL(argv[3]);

    valid_sg(sg);

    {
	int rjd, ns;
	VALUE rjd2;

	if (!valid_commercial_p(y, w, d, sg,
				&nth, &ry,
				&rw, &rd, &rjd,
				&ns))
	    return Qnil;
	if (!need_jd)
	    return INT2FIX(0); /* dummy */
	encode_jd(nth, rjd, &rjd2);
	return rjd2;
    }
}

#ifndef NDEBUG
static VALUE
date_s__valid_commercial_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vsg;
    VALUE argv2[4];

    rb_scan_args(argc, argv, "31", &vy, &vw, &vd, &vsg);

    argv2[0] = vy;
    argv2[1] = vw;
    argv2[2] = vd;
    if (argc < 4)
	argv2[3] = DBL2NUM(GREGORIAN);
    else
	argv2[3] = vsg;

    return valid_commercial_sub(4, argv2, klass, 1);
}
#endif

/*
 * call-seq:
 *    Date.valid_commercial?(cwyear, cweek, cwday[, start=Date::ITALY])
 *
 * Do +cwyear+ (calendar-week-based-year), +cweek+ (week-of-year)
 * and +cwday+ (day-of-week) make a
 * valid Commercial Date?  Returns true or false.
 *
 * Monday is day-of-week 1; Sunday is day-of-week 7.
 *
 * +cweek+ and +cwday+ can be negative, in which case they count
 * backwards from the end of the year and the end of the
 * week respectively.  No wraparound is performed, however,
 * and invalid values cause an ArgumentError to be raised.
 * A date falling in the period skipped in the Day of Calendar
 * Reform adjustment is not valid.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_valid_commercial_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vsg;
    VALUE argv2[4];

    rb_scan_args(argc, argv, "31", &vy, &vw, &vd, &vsg);

    argv2[0] = vy;
    argv2[1] = vw;
    argv2[2] = vd;
    if (argc < 4)
	argv2[3] = INT2FIX(DEFAULT_SG);
    else
	argv2[3] = vsg;

    if (NIL_P(valid_commercial_sub(4, argv2, klass, 0)))
	return Qfalse;
    return Qtrue;
}

#ifndef NDEBUG
static VALUE
valid_weeknum_sub(int argc, VALUE *argv, VALUE klass, int need_jd)
{
    VALUE nth, y;
    int w, d, f, ry, rw, rd;
    double sg;

    y = argv[0];
    w = NUM2INT(argv[1]);
    d = NUM2INT(argv[2]);
    f = NUM2INT(argv[3]);
    sg = NUM2DBL(argv[4]);

    valid_sg(sg);

    {
	int rjd, ns;
	VALUE rjd2;

	if (!valid_weeknum_p(y, w, d, f, sg,
			     &nth, &ry,
			     &rw, &rd, &rjd,
			     &ns))
	    return Qnil;
	if (!need_jd)
	    return INT2FIX(0); /* dummy */
	encode_jd(nth, rjd, &rjd2);
	return rjd2;
    }
}

static VALUE
date_s__valid_weeknum_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vf, vsg;
    VALUE argv2[5];

    rb_scan_args(argc, argv, "41", &vy, &vw, &vd, &vf, &vsg);

    argv2[0] = vy;
    argv2[1] = vw;
    argv2[2] = vd;
    argv2[3] = vf;
    if (argc < 5)
	argv2[4] = DBL2NUM(GREGORIAN);
    else
	argv2[4] = vsg;

    return valid_weeknum_sub(5, argv2, klass, 1);
}

static VALUE
date_s_valid_weeknum_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vf, vsg;
    VALUE argv2[5];

    rb_scan_args(argc, argv, "41", &vy, &vw, &vd, &vf, &vsg);

    argv2[0] = vy;
    argv2[1] = vw;
    argv2[2] = vd;
    argv2[3] = vf;
    if (argc < 5)
	argv2[4] = INT2FIX(DEFAULT_SG);
    else
	argv2[4] = vsg;

    if (NIL_P(valid_weeknum_sub(5, argv2, klass, 0)))
	return Qfalse;
    return Qtrue;
}

static VALUE
valid_nth_kday_sub(int argc, VALUE *argv, VALUE klass, int need_jd)
{
    VALUE nth, y;
    int m, n, k, ry, rm, rn, rk;
    double sg;

    y = argv[0];
    m = NUM2INT(argv[1]);
    n = NUM2INT(argv[2]);
    k = NUM2INT(argv[3]);
    sg = NUM2DBL(argv[4]);

    {
	int rjd, ns;
	VALUE rjd2;

	if (!valid_nth_kday_p(y, m, n, k, sg,
			      &nth, &ry,
			      &rm, &rn, &rk, &rjd,
			      &ns))
	    return Qnil;
	if (!need_jd)
	    return INT2FIX(0); /* dummy */
	encode_jd(nth, rjd, &rjd2);
	return rjd2;
    }
}

static VALUE
date_s__valid_nth_kday_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vn, vk, vsg;
    VALUE argv2[5];

    rb_scan_args(argc, argv, "41", &vy, &vm, &vn, &vk, &vsg);

    argv2[0] = vy;
    argv2[1] = vm;
    argv2[2] = vn;
    argv2[3] = vk;
    if (argc < 5)
	argv2[4] = DBL2NUM(GREGORIAN);
    else
	argv2[4] = vsg;

    return valid_nth_kday_sub(5, argv2, klass, 1);
}

static VALUE
date_s_valid_nth_kday_p(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vn, vk, vsg;
    VALUE argv2[5];

    rb_scan_args(argc, argv, "41", &vy, &vm, &vn, &vk, &vsg);

    argv2[0] = vy;
    argv2[1] = vm;
    argv2[2] = vn;
    argv2[3] = vk;
    if (argc < 5)
	argv2[4] = INT2FIX(DEFAULT_SG);
    else
	argv2[4] = vsg;

    if (NIL_P(valid_nth_kday_sub(5, argv2, klass, 0)))
	return Qfalse;
    return Qtrue;
}

static VALUE
date_s_zone_to_diff(VALUE klass, VALUE str)
{
    return date_zone_to_diff(str);
}
#endif

/*
 * call-seq:
 *    Date.julian_leap?(year)
 *
 * Return true if the given year is a leap year on Julian calendar.
 */
static VALUE
date_s_julian_leap_p(VALUE klass, VALUE y)
{
    if (f_zero_p(f_mod(y, INT2FIX(4))))
	return Qtrue;
    return Qfalse;
}

/*
 * call-seq:
 *    Date.gregorian_leap?(year)
 *    Date.leap?(year)
 *
 * Return true if the given year is a leap year on Gregorian calendar.
 */
static VALUE
date_s_gregorian_leap_p(VALUE klass, VALUE y)
{
    if (f_zero_p(f_mod(y, INT2FIX(4))) &&
	f_nonzero_p(f_mod(y, INT2FIX(100))) ||
	f_zero_p(f_mod(y, INT2FIX(400))))
	return Qtrue;
    return Qfalse;
}

static void
d_simple_gc_mark(struct SimpleDateData *dat)
{
    rb_gc_mark(dat->nth);
}

inline static VALUE
d_simple_new_internal(VALUE klass,
		      VALUE nth, int jd,
		      double sg,
		      int y, int m, int d,
		      unsigned flags)
{
    struct SimpleDateData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, struct SimpleDateData,
			   d_simple_gc_mark, -1, dat);

    dat->nth = nth;
    dat->jd = jd;
    dat->sg = sg;
    dat->year = y;
#ifndef USE_PACK
    dat->mon = m;
    dat->mday = d;
#else
    dat->pd = PACK2(m, d);
#endif
    dat->flags = flags;

    assert(have_jd_p(dat) || have_civil_p(dat));

    return obj;
}

static void
d_complex_gc_mark(struct ComplexDateData *dat)
{
    rb_gc_mark(dat->nth);
    rb_gc_mark(dat->sf);
}

inline static VALUE
d_complex_new_internal(VALUE klass,
		       VALUE nth, int jd,
		       int df, VALUE sf,
		       int of, double sg,
		       int y, int m, int d,
		       int h, int min, int s,
		       unsigned flags)
{
    struct ComplexDateData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, struct ComplexDateData,
			   d_complex_gc_mark, -1, dat);

    dat->nth = nth;
    dat->jd = jd;
    dat->df = df;
    dat->sf = sf;
    dat->of = of;
    dat->sg = sg;
    dat->year = y;
#ifndef USE_PACK
    dat->mon = m;
    dat->mday = d;
    dat->hour = h;
    dat->min = min;
    dat->sec = s;
#else
    dat->pd = PACK5(m, d, h, min, s);
#endif
    dat->flags = flags | COMPLEX_DAT;

    assert(have_jd_p(dat) || have_civil_p(dat));
    assert(have_df_p(dat) || have_time_p(dat));

    return obj;
}

static void
d_date_gc_mark(union DateData *dat)
{
    if (simple_dat_p(dat))
	rb_gc_mark(dat->s.nth);
    else {
	rb_gc_mark(dat->c.nth);
	rb_gc_mark(dat->c.sf);
    }
}

inline static VALUE
d_date_new_internal(VALUE klass,
		    VALUE nth, int jd,
		    double sg,
		    int y, int m, int d,
		    unsigned flags)
{
    union DateData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateData,
			   d_date_gc_mark, -1, dat);

    dat->s.nth = nth;
    dat->s.jd = jd;
    dat->s.sg = sg;
    dat->s.year = y;
#ifndef USE_PACK
    dat->s.mon = m;
    dat->s.mday = d;
#else
    dat->s.pd = PACK2(m, d);
#endif
    dat->s.flags = flags;

    assert(have_jd_p(dat) || have_civil_p(dat));

    return obj;
}

static VALUE
d_lite_s_alloc(VALUE klass)
{
    return d_date_new_internal(klass,
			       INT2FIX(0), 0,
			       DEFAULT_SG,
			       0, 0, 0,
			       HAVE_JD);
}

static void
old_to_new(VALUE ajd, VALUE of, VALUE sg,
	   VALUE *rnth, int *rjd, int *rdf, VALUE *rsf,
	   int *rof, double *rsg,
	   unsigned *flags)
{
    VALUE jd, df, sf, of2, t;

    decode_day(f_add(ajd, half_days_in_day),
	       &jd, &df, &sf);
    t = day_to_sec(of);
    of2 = f_round(t);

    if (!f_eqeq_p(of2, t))
	rb_warning("fraction of offset is ignored");

    decode_jd(jd, rnth, rjd);

    *rdf = NUM2INT(df);
    *rsf = sf;
    *rof = NUM2INT(of2);
    *rsg = NUM2DBL(sg);

    if (*rof < -1 || *rof > 1) {
	*rof = 0;
	rb_warning("invalid offset is ignored");
    }

    if (!c_valid_start_p(*rsg)) {
	*rsg = DEFAULT_SG;
	rb_warning("invalid start is ignored");
    }

    *flags = HAVE_JD | HAVE_DF | COMPLEX_DAT;
}

#ifndef NDEBUG
static VALUE
date_s_new_bang(int argc, VALUE *argv, VALUE klass)
{
    VALUE ajd, of, sg, nth, sf;
    int jd, df, rof;
    double rsg;
    unsigned flags;

    rb_scan_args(argc, argv, "03", &ajd, &of, &sg);

    switch (argc) {
      case 0:
	ajd = INT2FIX(0);
      case 1:
	of = INT2FIX(0);
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    old_to_new(ajd, of, sg,
	       &nth, &jd, &df, &sf, &rof, &rsg, &flags);

    return d_complex_new_internal(klass,
				  nth, jd,
				  df, sf,
				  rof, rsg,
				  0, 0, 0,
				  0, 0, 0,
				  flags);
}
#endif

inline static int
integer_p(VALUE x)
{
    if (FIXNUM_P(x))
	return 1;
    switch (TYPE(x)) {
      case T_BIGNUM:
	return 1;
      case T_FLOAT:
	{
	    double d = NUM2DBL(x);
	    if (round(d) == d)
		return 1;
	}
      case T_RATIONAL:
	{
	    if (RRATIONAL(x)->den == 1)
		return 1;
	}
    }
    return 0;
}

inline static VALUE
d_trunc(VALUE d, VALUE *fr)
{
    VALUE rd;

    if (integer_p(d)) {
	rd = d;
	*fr = INT2FIX(0);
    } else {
	rd = f_idiv(d, INT2FIX(1));
	*fr = f_mod(d, INT2FIX(1));
    }
    return rd;
}

#define jd_trunc d_trunc
#define k_trunc d_trunc

inline static VALUE
h_trunc(VALUE h, VALUE *fr)
{
    VALUE rh;

    if (integer_p(h)) {
	rh = h;
	*fr = INT2FIX(0);
    } else {
	rh = f_idiv(h, INT2FIX(1));
	*fr = f_mod(h, INT2FIX(1));
	*fr = f_quo(*fr, INT2FIX(24));
    }
    return rh;
}

inline static VALUE
min_trunc(VALUE min, VALUE *fr)
{
    VALUE rmin;

    if (integer_p(min)) {
	rmin = min;
	*fr = INT2FIX(0);
    } else {
	rmin = f_idiv(min, INT2FIX(1));
	*fr = f_mod(min, INT2FIX(1));
	*fr = f_quo(*fr, INT2FIX(1440));
    }
    return rmin;
}

inline static VALUE
s_trunc(VALUE s, VALUE *fr)
{
    VALUE rs;

    if (integer_p(s)) {
	rs = s;
	*fr = INT2FIX(0);
    } else {
	rs = f_idiv(s, INT2FIX(1));
	*fr = f_mod(s, INT2FIX(1));
	*fr = f_quo(*fr, INT2FIX(86400));
    }
    return rs;
}

#define num2num_with_frac(s,n) \
{\
    s = s##_trunc(v##s, &fr);\
    if (f_nonzero_p(fr)) {\
	if (argc > n)\
	    rb_raise(rb_eArgError, "invalid fraction");\
	fr2 = fr;\
    }\
}

#define num2int_with_frac(s,n) \
{\
    s = NUM2INT(s##_trunc(v##s, &fr));\
    if (f_nonzero_p(fr)) {\
	if (argc > n)\
	    rb_raise(rb_eArgError, "invalid fraction");\
	fr2 = fr;\
    }\
}

#define add_frac() \
{\
    if (f_nonzero_p(fr2))\
	ret = d_lite_plus(ret, fr2);\
}

#define val2sg(vsg,dsg) \
{\
    dsg = NUM2DBL(vsg);\
    if (!c_valid_start_p(dsg)) {\
	dsg = DEFAULT_SG;\
	rb_warning("invalid start is ignored");\
    }\
}

static VALUE d_lite_plus(VALUE, VALUE);

/*
 * call-seq:
 *    Date.jd([jd=0[, start=Date::ITALY]])
 *
 * Create a new Date object from a Julian Day Number.
 *
 * +jd+ is the Julian Day Number; if not specified, it defaults to 0.
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_jd(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vsg, jd, fr, fr2, ret;
    double sg;

    rb_scan_args(argc, argv, "02", &vjd, &vsg);

    jd = INT2FIX(0);
    fr2 = INT2FIX(0);
    sg = DEFAULT_SG;

    switch (argc) {
      case 2:
	val2sg(vsg, sg);
      case 1:
	num2num_with_frac(jd, positive_inf);
    }

    {
	VALUE nth;
	int rjd;

	decode_jd(jd, &nth, &rjd);

	ret = d_simple_new_internal(klass,
				    nth, rjd,
				    sg,
				    0, 0, 0,
				    HAVE_JD);
    }
    add_frac();
    return ret;
}

/*
 * call-seq:
 *    Date.ordinal([year=-4712[, yday=1[, start=Date::ITALY]]])
 *
 * Create a new Date object from an Ordinal Date, specified
 * by +year+ and +yday+ (day-of-year). +yday+ can be negative,
 * in which it counts backwards from the end of the year.
 * No year wraparound is performed, however.  An invalid
 * value for +yday+ results in an ArgumentError being raised.
 *
 * +year+ defaults to -4712, and +yday+ to 1; this is Julian Day
 * Number day 0.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_ordinal(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vd, vsg, y, fr, fr2, ret;
    int d;
    double sg;

    rb_scan_args(argc, argv, "03", &vy, &vd, &vsg);

    y = INT2FIX(-4712);
    d = 1;
    fr2 = INT2FIX(0);
    sg = DEFAULT_SG;

    switch (argc) {
      case 3:
	val2sg(vsg, sg);
      case 2:
	num2int_with_frac(d, positive_inf);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rd, rjd, ns;

	if (!valid_ordinal_p(y, d, sg,
			     &nth, &ry,
			     &rd, &rjd,
			     &ns))
	    rb_raise(rb_eArgError, "invalid date");

	ret = d_simple_new_internal(klass,
				     nth, rjd,
				     sg,
				     0, 0, 0,
				     HAVE_JD);
    }
    add_frac();
    return ret;
}

/*
 * call-seq:
 *    Date.civil([year=-4712[, month=1[, mday=1[, start=Date::ITALY]]]])
 *    Date.new([year=-4712[, month=1[, mday=1[, start=Date::ITALY]]]])
 *
 * Create a new Date object for the Civil Date specified by
 * +year+, +month+ and +mday+ (day-of-month).
 *
 * +month+ and +mday+ can be negative, in which case they count
 * backwards from the end of the year and the end of the
 * month respectively.  No wraparound is performed, however,
 * and invalid values cause an ArgumentError to be raised.
 * can be negative
 *
 * +year+ defaults to -4712, +month+ to 1, and +mday+ to 1; this is
 * Julian Day Number day 0.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_civil(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vd, vsg, y, fr, fr2, ret;
    int m, d;
    double sg;

    rb_scan_args(argc, argv, "04", &vy, &vm, &vd, &vsg);

    y = INT2FIX(-4712);
    m = 1;
    d = 1;
    fr2 = INT2FIX(0);
    sg = DEFAULT_SG;

    switch (argc) {
      case 4:
	val2sg(vsg, sg);
      case 3:
	num2int_with_frac(d, positive_inf);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = vy;
    }

    if (isinf(sg) && sg < 0) {
	VALUE nth;
	int ry, rm, rd;

	if (!valid_gregorian_p(y, m, d,
			       &nth, &ry,
			       &rm, &rd))
	    rb_raise(rb_eArgError, "invalid date");

	ret = d_simple_new_internal(klass,
				    nth, 0,
				    sg,
				    ry, rm, rd,
				    HAVE_CIVIL);
    }
    else {
	VALUE nth;
	int ry, rm, rd, rjd, ns;

	if (!valid_civil_p(y, m, d, sg,
			   &nth, &ry,
			   &rm, &rd, &rjd,
			   &ns))
	    rb_raise(rb_eArgError, "invalid date");

	ret = d_simple_new_internal(klass,
				    nth, rjd,
				    sg,
				    ry, rm, rd,
				    HAVE_JD | HAVE_CIVIL);
    }
    add_frac();
    return ret;
}

/*
 * call-seq:
 *    Date.commercial([cwyear=-4712[, cweek=1[, cwday=1[, start=Date::ITALY]]]])
 *
 * Create a new Date object for the Commercial Date specified by
 * +cwyear+ (calendar-week-based-year), +cweek+ (week-of-year)
 * and +cwday+ (day-of-week).
 *
 * Monday is day-of-week 1; Sunday is day-of-week 7.
 *
 * +cweek+ and +cwday+ can be negative, in which case they count
 * backwards from the end of the year and the end of the
 * week respectively.  No wraparound is performed, however,
 * and invalid values cause an ArgumentError to be raised.
 *
 * +cwyear+ defaults to -4712, +cweek+ to 1, and +cwday+ to 1; this is
 * Julian Day Number day 0.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_commercial(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vsg, y, fr, fr2, ret;
    int w, d;
    double sg;

    rb_scan_args(argc, argv, "04", &vy, &vw, &vd, &vsg);

    y = INT2FIX(-4712);
    w = 1;
    d = 1;
    fr2 = INT2FIX(0);
    sg = DEFAULT_SG;

    switch (argc) {
      case 4:
	val2sg(vsg, sg);
      case 3:
	num2int_with_frac(d, positive_inf);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rw, rd, rjd, ns;

	if (!valid_commercial_p(y, w, d, sg,
				&nth, &ry,
				&rw, &rd, &rjd,
				&ns))
	    rb_raise(rb_eArgError, "invalid date");

	ret = d_simple_new_internal(klass,
				    nth, rjd,
				    sg,
				    0, 0, 0,
				    HAVE_JD);
    }
    add_frac();
    return ret;
}

#ifndef NDEBUG
static VALUE
date_s_weeknum(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vf, vsg, y, fr, fr2, ret;
    int w, d, f;
    double sg;

    rb_scan_args(argc, argv, "05", &vy, &vw, &vd, &vf, &vsg);

    y = INT2FIX(-4712);
    w = 0;
    d = 1;
    f = 0;
    fr2 = INT2FIX(0);
    sg = DEFAULT_SG;

    switch (argc) {
      case 5:
	val2sg(vsg, sg);
      case 4:
	f = NUM2INT(vf);
      case 3:
	num2int_with_frac(d, positive_inf);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rw, rd, rjd, ns;

	if (!valid_weeknum_p(y, w, d, f, sg,
			     &nth, &ry,
			     &rw, &rd, &rjd,
			     &ns))
	    rb_raise(rb_eArgError, "invalid date");

	ret = d_simple_new_internal(klass,
				    nth, rjd,
				    sg,
				    0, 0, 0,
				    HAVE_JD);
    }
    add_frac();
    return ret;
}

static VALUE
date_s_nth_kday(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vn, vk, vsg, y, fr, fr2, ret;
    int m, n, k;
    double sg;

    rb_scan_args(argc, argv, "05", &vy, &vm, &vn, &vk, &vsg);

    y = INT2FIX(-4712);
    m = 1;
    n = 1;
    k = 1;
    fr2 = INT2FIX(0);
    sg = DEFAULT_SG;

    switch (argc) {
      case 5:
	val2sg(vsg, sg);
      case 4:
	num2int_with_frac(k, positive_inf);
      case 3:
	n = NUM2INT(vn);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rm, rn, rk, rjd, ns;

	if (!valid_nth_kday_p(y, m, n, k, sg,
			      &nth, &ry,
			      &rm, &rn, &rk, &rjd,
			      &ns))
	    rb_raise(rb_eArgError, "invalid date");

	ret = d_simple_new_internal(klass,
				    nth, rjd,
				    sg,
				    0, 0, 0,
				    HAVE_JD);
    }
    add_frac();
    return ret;
}
#endif

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

static void set_sg(union DateData *, double);

/*
 * call-seq:
 *    Date.today([start=Date::ITALY])
 *
 * Create a new Date object representing today.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_today(int argc, VALUE *argv, VALUE klass)
{
    VALUE vsg, nth, ret;
    double sg;
    time_t t;
    struct tm tm;
    int y, ry, m, d;

    rb_scan_args(argc, argv, "01", &vsg);

    if (argc < 1)
	sg = DEFAULT_SG;
    else
	val2sg(vsg, sg);

    if (time(&t) == -1)
	rb_sys_fail("time");
    localtime_r(&t, &tm);

    y = tm.tm_year + 1900;
    m = tm.tm_mon + 1;
    d = tm.tm_mday;

    decode_year(INT2FIX(y), -1, &nth, &ry);

    ret = d_simple_new_internal(klass,
				nth, 0,
				GREGORIAN,
				ry, m, d,
				HAVE_CIVIL);
    {
	get_d1(ret);
	set_sg(dat, sg);
    }
    return ret;
}

#define set_hash0(k,v) rb_hash_aset(hash, k, v)
#define ref_hash0(k) rb_hash_aref(hash, k)
#define del_hash0(k) rb_hash_delete(hash, k)

#define set_hash(k,v) rb_hash_aset(hash, ID2SYM(rb_intern(k)), v)
#define ref_hash(k) rb_hash_aref(hash, ID2SYM(rb_intern(k)))
#define del_hash(k) rb_hash_delete(hash, ID2SYM(rb_intern(k)))

static VALUE
rt_rewrite_frags(VALUE hash)
{
    VALUE seconds;

    if (NIL_P(hash))
	hash = rb_hash_new();

    seconds = ref_hash("seconds");
    if (!NIL_P(seconds)) {
	VALUE d, h, min, s, fr;

	d = f_idiv(seconds, INT2FIX(DAY_IN_SECONDS));
	fr = f_mod(seconds, INT2FIX(DAY_IN_SECONDS));

	h = f_idiv(fr, INT2FIX(HOUR_IN_SECONDS));
	fr = f_mod(fr, INT2FIX(HOUR_IN_SECONDS));

	min = f_idiv(fr, INT2FIX(MINUTE_IN_SECONDS));
	fr = f_mod(fr, INT2FIX(MINUTE_IN_SECONDS));

	s = f_idiv(fr, INT2FIX(1));
	fr = f_mod(fr, INT2FIX(1));

	set_hash("jd", f_add(UNIX_EPOCH_IN_CJD, d));
	set_hash("hour", h);
	set_hash("min", min);
	set_hash("sec", s);
	set_hash("sec_fraction", fr);
	del_hash("seconds");
	del_hash("offset");
    }
    return hash;
}

#define sym(x) ID2SYM(rb_intern(x))

static VALUE
fv_values_at(VALUE h, VALUE a)
{
    return rb_funcall2(h, rb_intern("values_at"),
			RARRAY_LENINT(a), RARRAY_PTR(a));
}

static VALUE d_lite_wday(VALUE);

static VALUE
rt_complete_frags(VALUE klass, VALUE hash)
{
    static VALUE tab = Qnil;
    VALUE t, l, g, d;

    if (NIL_P(tab)) {
	tab = rb_ary_new3(11,
			  rb_ary_new3(2,
				      sym("time"),
				      rb_ary_new3(3,
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      Qnil,
				      rb_ary_new3(1,
						  sym("jd"))),
			  rb_ary_new3(2,
				      sym("ordinal"),
				      rb_ary_new3(5,
						  sym("year"),
						  sym("yday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      sym("civil"),
				      rb_ary_new3(6,
						  sym("year"),
						  sym("mon"),
						  sym("mday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      sym("commercial"),
				      rb_ary_new3(6,
						  sym("cwyear"),
						  sym("cweek"),
						  sym("cwday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      sym("wday"),
				      rb_ary_new3(4,
						  sym("wday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      sym("wnum0"),
				      rb_ary_new3(6,
						  sym("year"),
						  sym("wnum0"),
						  sym("wday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      sym("wnum1"),
				      rb_ary_new3(6,
						  sym("year"),
						  sym("wnum1"),
						  sym("wday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      Qnil,
				      rb_ary_new3(6,
						  sym("cwyear"),
						  sym("cweek"),
						  sym("wday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      Qnil,
				      rb_ary_new3(6,
						  sym("year"),
						  sym("wnum0"),
						  sym("cwday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))),
			  rb_ary_new3(2,
				      Qnil,
				      rb_ary_new3(6,
						  sym("year"),
						  sym("wnum1"),
						  sym("cwday"),
						  sym("hour"),
						  sym("min"),
						  sym("sec"))));
	rb_gc_register_mark_object(tab);
    }

    {
	int i;

	t = rb_ary_new2(RARRAY_LEN(tab));

	for (i = 0; i < RARRAY_LENINT(tab); i++) {
	    VALUE x, k, a, e;

	    x = RARRAY_PTR(tab)[i];
	    k = RARRAY_PTR(x)[0];
	    a = RARRAY_PTR(x)[1];
	    e = f_compact(fv_values_at(hash, a));

	    if (RARRAY_LEN(e) > 0)
		rb_ary_push(t, rb_ary_new3(5,
					   INT2FIX(RARRAY_LENINT(e)),
					   INT2FIX(-i),
					   k, a, e));
	}

	if (RARRAY_LEN(t) == 0)
	    g = Qnil;
	else {
	    rb_ary_sort_bang(t);
	    l = RARRAY_PTR(t)[RARRAY_LENINT(t) - 1];
	    g = rb_ary_new3(3,
			    RARRAY_PTR(l)[2],
			    RARRAY_PTR(l)[3],
			    RARRAY_PTR(l)[4]);
	}
    }

    d = Qnil;

    if (!NIL_P(g) && !NIL_P(RARRAY_PTR(g)[0]) &&
	(RARRAY_LEN(RARRAY_PTR(g)[1]) -
	 RARRAY_LEN(RARRAY_PTR(g)[2]))) {
	VALUE k, a;

	if (NIL_P(d))
	    d = date_s_today(0, (VALUE *)0, cDate);

	k = RARRAY_PTR(g)[0];
	a = RARRAY_PTR(g)[1];

	if (k == sym("ordinal")) {
	    if (NIL_P(ref_hash("year")))
		set_hash("year", f_year(d));
	    if (NIL_P(ref_hash("yday")))
		set_hash("yday", INT2FIX(1));
	}
	else if (k == sym("civil")) {
	    int i;

	    for (i = 0; i < RARRAY_LENINT(a); i++) {
		VALUE e = RARRAY_PTR(a)[i];

		if (!NIL_P(ref_hash0(e)))
		    break;
		set_hash0(e, rb_funcall(d, SYM2ID(e), 0));
	    }
	    if (NIL_P(ref_hash("mon")))
		set_hash("mon", INT2FIX(1));
	    if (NIL_P(ref_hash("mday")))
		set_hash("mday", INT2FIX(1));
	}
	else if (k == sym("commercial")) {
	    int i;

	    for (i = 0; i < RARRAY_LENINT(a); i++) {
		VALUE e = RARRAY_PTR(a)[i];

		if (!NIL_P(ref_hash0(e)))
		    break;
		set_hash0(e, rb_funcall(d, SYM2ID(e), 0));
	    }
	    if (NIL_P(ref_hash("cweek")))
		set_hash("cweek", INT2FIX(1));
	    if (NIL_P(ref_hash("cwday")))
		set_hash("cwday", INT2FIX(1));
	}
	else if (k == sym("wday")) {
	    set_hash("jd", f_jd(f_add(f_sub(d,
					    d_lite_wday(d)),
				      ref_hash("wday"))));
	}
	else if (k == sym("wnum0")) {
	    int i;

	    for (i = 0; i < RARRAY_LENINT(a); i++) {
		VALUE e = RARRAY_PTR(a)[i];

		if (!NIL_P(ref_hash0(e)))
		    break;
		set_hash0(e, rb_funcall(d, SYM2ID(e), 0));
	    }
	    if (NIL_P(ref_hash("wnum0")))
		set_hash("wnum0", INT2FIX(0));
	    if (NIL_P(ref_hash("wday")))
		set_hash("wday", INT2FIX(0));
	}
	else if (k == sym("wnum1")) {
	    int i;

	    for (i = 0; i < RARRAY_LENINT(a); i++) {
		VALUE e = RARRAY_PTR(a)[i];

		if (!NIL_P(ref_hash0(e)))
		    break;
		set_hash0(e, rb_funcall(d, SYM2ID(e), 0));
	    }
	    if (NIL_P(ref_hash("wnum1")))
		set_hash("wnum1", INT2FIX(0));
	    if (NIL_P(ref_hash("wday")))
		set_hash("wday", INT2FIX(1));
	}
    }

    if (!NIL_P(g) && RARRAY_PTR(g)[0] == sym("time")) {
	if (f_le_p(klass, cDateTime)) {
	    if (NIL_P(d))
		d = date_s_today(0, (VALUE *)0, cDate);
	    if (NIL_P(ref_hash("jd")))
		set_hash("jd", f_jd(d));
	}
    }

    if (NIL_P(ref_hash("hour")))
	set_hash("hour", INT2FIX(0));
    if (NIL_P(ref_hash("min")))
	set_hash("min", INT2FIX(0));
    if (NIL_P(ref_hash("sec")))
	set_hash("sec", INT2FIX(0));
    else if (f_gt_p(ref_hash("sec"), INT2FIX(59)))
	set_hash("sec", INT2FIX(59));

    return hash;
}

#define f_values_at1(o,k1) rb_funcall(o, rb_intern("values_at"), 1, k1)
#define f_values_at2(o,k1,k2) rb_funcall(o, rb_intern("values_at"), 2, k1, k2)
#define f_values_at3(o,k1,k2,k3) rb_funcall(o, rb_intern("values_at"), 3,\
					    k1, k2, k3)

static VALUE
f_all_p(VALUE a)
{
    int i;

    for (i = 0; i < RARRAY_LENINT(a); i++)
	if (NIL_P(RARRAY_PTR(a)[i]))
	    return Qfalse;
    return Qtrue;
}

static VALUE
rt__valid_jd_p(VALUE jd, VALUE sg)
{
    return jd;
}

static VALUE
rt__valid_ordinal_p(VALUE y, VALUE d, VALUE sg)
{
    VALUE nth, rjd2;
    int ry, rd, rjd, ns;

    if (!valid_ordinal_p(y, NUM2INT(d), NUM2DBL(sg),
			 &nth, &ry,
			 &rd, &rjd,
			 &ns))
	return Qnil;
    encode_jd(nth, rjd, &rjd2);
    return rjd2;
}

static VALUE
rt__valid_civil_p(VALUE y, VALUE m, VALUE d, VALUE sg)
{
    VALUE nth, rjd2;
    int ry, rm, rd, rjd, ns;

    if (!valid_civil_p(y, NUM2INT(m), NUM2INT(d), NUM2DBL(sg),
		       &nth, &ry,
		       &rm, &rd, &rjd,
		       &ns))
	return Qnil;
    encode_jd(nth, rjd, &rjd2);
    return rjd2;
}

static VALUE
rt__valid_commercial_p(VALUE y, VALUE w, VALUE d, VALUE sg)
{
    VALUE nth, rjd2;
    int ry, rw, rd, rjd, ns;

    if (!valid_commercial_p(y, NUM2INT(w), NUM2INT(d), NUM2DBL(sg),
			    &nth, &ry,
			    &rw, &rd, &rjd,
			    &ns))
	return Qnil;
    encode_jd(nth, rjd, &rjd2);
    return rjd2;
}

static VALUE
rt__valid_weeknum_p(VALUE y, VALUE w, VALUE d, VALUE f, VALUE sg)
{
    VALUE nth, rjd2;
    int ry, rw, rd, rjd, ns;

    if (!valid_weeknum_p(y, NUM2INT(w), NUM2INT(d), NUM2INT(f), NUM2DBL(sg),
			 &nth, &ry,
			 &rw, &rd, &rjd,
			 &ns))
	return Qnil;
    encode_jd(nth, rjd, &rjd2);
    return rjd2;
}

static VALUE
rt__valid_date_frags_p(VALUE hash, VALUE sg)
{
    VALUE a;

    a = f_values_at1(hash, sym("jd"));
    if (f_all_p(a)) {
	VALUE jd = rt__valid_jd_p(RARRAY_PTR(a)[0],
				  sg);
	if (!NIL_P(jd))
	    return jd;
    }

    a = f_values_at2(hash, sym("year"), sym("yday"));
    if (f_all_p(a)) {
	VALUE jd = rt__valid_ordinal_p(RARRAY_PTR(a)[0],
				       RARRAY_PTR(a)[1],
				       sg);
	if (!NIL_P(jd))
	    return jd;
    }

    a = f_values_at3(hash, sym("year"), sym("mon"), sym("mday"));
    if (f_all_p(a)) {
	VALUE jd = rt__valid_civil_p(RARRAY_PTR(a)[0],
				     RARRAY_PTR(a)[1],
				     RARRAY_PTR(a)[2],
				     sg);
	if (!NIL_P(jd))
	    return jd;
    }

    a = f_values_at3(hash, sym("cwyear"), sym("cweek"), sym("cwday"));
    if (NIL_P(RARRAY_PTR(a)[2]) && !NIL_P(ref_hash("wday")))
	if (f_zero_p(ref_hash("wday")))
	    RARRAY_PTR(a)[2] = INT2FIX(7);
	else
	    RARRAY_PTR(a)[2] = ref_hash("wday");
    if (f_all_p(a)) {
	VALUE jd = rt__valid_commercial_p(RARRAY_PTR(a)[0],
					  RARRAY_PTR(a)[1],
					  RARRAY_PTR(a)[2],
					  sg);
	if (!NIL_P(jd))
	    return jd;
    }

    a = f_values_at3(hash, sym("year"), sym("wnum0"), sym("wday"));
    if (NIL_P(RARRAY_PTR(a)[2]) && !NIL_P(ref_hash("cwday")))
	RARRAY_PTR(a)[2] = f_mod(ref_hash("cwday"), INT2FIX(7));
    if (f_all_p(a)) {
	VALUE jd = rt__valid_weeknum_p(RARRAY_PTR(a)[0],
				       RARRAY_PTR(a)[1],
				       RARRAY_PTR(a)[2],
				       INT2FIX(0),
				       sg);
	if (!NIL_P(jd))
	    return jd;
    }

    a = f_values_at3(hash, sym("year"), sym("wnum1"), sym("wday"));
    if (!NIL_P(RARRAY_PTR(a)[2]))
	RARRAY_PTR(a)[2] = f_mod(f_sub(RARRAY_PTR(a)[2], INT2FIX(1)),
				 INT2FIX(7));
    if (NIL_P(RARRAY_PTR(a)[2]) && !NIL_P(ref_hash("cwday")))
	RARRAY_PTR(a)[2] = f_mod(f_sub(ref_hash("cwday"), INT2FIX(1)),
				 INT2FIX(7));
    if (f_all_p(a)) {
	VALUE jd = rt__valid_weeknum_p(RARRAY_PTR(a)[0],
				       RARRAY_PTR(a)[1],
				       RARRAY_PTR(a)[2],
				       INT2FIX(1),
				       sg);
	if (!NIL_P(jd))
	    return jd;
    }
    return Qnil;
}

static VALUE
d_new_by_frags(VALUE klass, VALUE hash, VALUE sg)
{
    VALUE jd;

    if (!c_valid_start_p(NUM2DBL(sg))) {
	sg = INT2FIX(DEFAULT_SG);
	rb_warning("invalid start is ignored");
    }

    hash = rt_rewrite_frags(hash);
    hash = rt_complete_frags(klass, hash);

    jd = rt__valid_date_frags_p(hash, sg);
    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");
    {
	VALUE nth;
	int rjd;

	decode_jd(jd, &nth, &rjd);

	return d_simple_new_internal(klass,
				     nth, rjd,
				     NUM2DBL(sg),
				     0, 0, 0,
				     HAVE_JD);
    }
}

VALUE
date__strptime(const char *str, size_t slen,
	       const char *fmt, size_t flen, VALUE hash);

static VALUE
date_s__strptime_internal(int argc, VALUE *argv, VALUE klass,
			  const char *default_fmt)
{
    VALUE vstr, vfmt, hash;
    const char *str, *fmt;
    size_t slen, flen;

    rb_scan_args(argc, argv, "11", &vstr, &vfmt);

    StringValue(vstr);
    if (!rb_enc_str_asciicompat_p(vstr))
	rb_raise(rb_eArgError,
		 "string should have ASCII compatible encoding");
    str = RSTRING_PTR(vstr);
    slen = RSTRING_LEN(vstr);
    if (argc < 2) {
	fmt = default_fmt;
	flen = strlen(default_fmt);
    }
    else {
	StringValue(vfmt);
	if (!rb_enc_str_asciicompat_p(vfmt))
	    rb_raise(rb_eArgError,
		     "format should have ASCII compatible encoding");
	fmt = RSTRING_PTR(vfmt);
	flen = RSTRING_LEN(vfmt);
    }
    hash = rb_hash_new();
    if (NIL_P(date__strptime(str, slen, fmt, flen, hash)))
	return Qnil;

    {
	VALUE zone = rb_hash_aref(hash, ID2SYM(rb_intern("zone")));
	VALUE left = rb_hash_aref(hash, ID2SYM(rb_intern("leftover")));

	if (!NIL_P(zone)) {
	    rb_enc_copy(zone, vstr);
	    OBJ_INFECT(zone, vstr);
	    rb_hash_aset(hash, ID2SYM(rb_intern("zone")), zone);
	}
	if (!NIL_P(left)) {
	    rb_enc_copy(left, vstr);
	    OBJ_INFECT(left, vstr);
	    rb_hash_aset(hash, ID2SYM(rb_intern("leftover")), left);
	}
    }

    return hash;
}

/*
 * call-seq:
 *    Date._strptime(string[, format="%F"])
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__strptime(int argc, VALUE *argv, VALUE klass)
{
    return date_s__strptime_internal(argc, argv, klass, "%F");
}

/*
 * call-seq:
 *    Date.strptime([string="-4712-01-01"[, format="%F"[,start=ITALY]]])
 *
 * Create a new Date object by parsing from a String
 * according to a specified format.
 *
 * +string+ is a String holding a date representation.
 * +format+ is the format that the date is in.
 *
 * The default +string+ is '-4712-01-01', and the default
 * +format+ is '%F', which means Year-Month-Day_of_Month.
 * This gives Julian Day Number day 0.
 *
 * +start+ specifies the Day of Calendar Reform.
 *
 * An ArgumentError will be raised if +string+ cannot be
 * parsed.
 */
static VALUE
date_s_strptime(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, fmt, sg;

    rb_scan_args(argc, argv, "03", &str, &fmt, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01");
      case 1:
	fmt = rb_str_new2("%F");
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = fmt;
	hash = date_s__strptime(2, argv2, klass);
	return d_new_by_frags(klass, hash, sg);
    }
}

VALUE
date__parse(VALUE str, VALUE comp);

static VALUE
date_s__parse_internal(int argc, VALUE *argv, VALUE klass)
{
    VALUE vstr, vcomp, hash;

    rb_scan_args(argc, argv, "11", &vstr, &vcomp);
    StringValue(vstr);
    if (!rb_enc_str_asciicompat_p(vstr))
	rb_raise(rb_eArgError,
		 "string should have ASCII compatible encoding");
    if (argc < 2)
	vcomp = Qtrue;

    hash = date__parse(vstr, vcomp);

    {
	VALUE zone = rb_hash_aref(hash, ID2SYM(rb_intern("zone")));

	if (!NIL_P(zone)) {
	    rb_enc_copy(zone, vstr);
	    OBJ_INFECT(zone, vstr);
	    rb_hash_aset(hash, ID2SYM(rb_intern("zone")), zone);
	}
    }

    return hash;
}

/*
 * call-seq:
 *    Date._parse(string[, comp=true])
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__parse(int argc, VALUE *argv, VALUE klass)
{
    return date_s__parse_internal(argc, argv, klass);
}

/*
 * call-seq:
 *    Date.parse(string="-4712-01-01"[, comp=true[,start=ITALY]])
 *
 * Create a new Date object by parsing from a String,
 * without specifying the format.
 *
 * +string+ is a String holding a date representation.
 * +comp+ specifies whether to interpret 2-digit years
 * as 19XX (>= 69) or 20XX (< 69); the default is to.
 * The method will attempt to parse a date from the String
 * using various heuristics.
 * If parsing fails, an ArgumentError will be raised.
 *
 * The default +string+ is '-4712-01-01'; this is Julian
 * Day Number day 0.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
date_s_parse(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = comp;
	hash = date_s__parse(2, argv2, klass);
	return d_new_by_frags(klass, hash, sg);
    }
}

VALUE date__iso8601(VALUE);
VALUE date__rfc3339(VALUE);
VALUE date__xmlschema(VALUE);
VALUE date__rfc2822(VALUE);
VALUE date__httpdate(VALUE);
VALUE date__jisx0301(VALUE);

/*
 * call-seq:
 *    Date._iso8601(string)
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__iso8601(VALUE klass, VALUE str)
{
    return date__iso8601(str);
}

/*
 * call-seq:
 *    Date.iso8601(string="-4712-01-01"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical ISO 8601 format.
 */
static VALUE
date_s_iso8601(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, sg;

    rb_scan_args(argc, argv, "02", &str, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01");
      case 1:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__iso8601(klass, str);
	return d_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    Date._rfc3339(string)
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__rfc3339(VALUE klass, VALUE str)
{
    return date__rfc3339(str);
}

/*
 * call-seq:
 *    Date.rfc3339(string="-4712-01-01T00:00:00+00:00"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical RFC 3339 format.
 */
static VALUE
date_s_rfc3339(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, sg;

    rb_scan_args(argc, argv, "02", &str, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01T00:00:00+00:00");
      case 1:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__rfc3339(klass, str);
	return d_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    Date._xmlschema(string)
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__xmlschema(VALUE klass, VALUE str)
{
    return date__xmlschema(str);
}

/*
 * call-seq:
 *    Date.xmlschema(string="-4712-01-01"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical XML Schema format.
 */
static VALUE
date_s_xmlschema(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, sg;

    rb_scan_args(argc, argv, "02", &str, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01");
      case 1:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__xmlschema(klass, str);
	return d_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    Date._rfc2822(string)
 *    Date._rfc822(string)
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__rfc2822(VALUE klass, VALUE str)
{
    return date__rfc2822(str);
}

/*
 * call-seq:
 *    Date.rfc2822(string="Mon, 1 Jan -4712 00:00:00 +0000"[,start=ITALY])
 *    Date.rfc822(string="Mon, 1 Jan -4712 00:00:00 +0000"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical RFC 2822 format.
 */
static VALUE
date_s_rfc2822(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, sg;

    rb_scan_args(argc, argv, "02", &str, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("Mon, 1 Jan -4712 00:00:00 +0000");
      case 1:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__rfc2822(klass, str);
	return d_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    Date._httpdate(string)
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__httpdate(VALUE klass, VALUE str)
{
    return date__httpdate(str);
}

/*
 * call-seq:
 *    Date.httpdate(string="Mon, 01 Jan -4712 00:00:00 GMT"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some RFC 2616 format.
 */
static VALUE
date_s_httpdate(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, sg;

    rb_scan_args(argc, argv, "02", &str, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("Mon, 01 Jan -4712 00:00:00 GMT");
      case 1:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__httpdate(klass, str);
	return d_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    Date._jisx0301(string)
 *
 * Return a hash of parsed elements.
 */
static VALUE
date_s__jisx0301(VALUE klass, VALUE str)
{
    return date__jisx0301(str);
}

/*
 * call-seq:
 *    Date.jisx0301(string="-4712-01-01"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical JIS X 0301 format.
 */
static VALUE
date_s_jisx0301(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, sg;

    rb_scan_args(argc, argv, "02", &str, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01");
      case 1:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__jisx0301(klass, str);
	return d_new_by_frags(klass, hash, sg);
    }
}

#ifndef NDEBUG
static VALUE
d_lite_fill(VALUE self)
{
    get_d1(self);

    if (simple_dat_p(dat)) {
	get_s_jd(dat);
	get_s_civil(dat);
    }
    else {
	get_c_jd(dat);
	get_c_civil(dat);
	get_c_df(dat);
	get_c_time(dat);
    }
    return self;
}
#endif

static VALUE
copy_obj(VALUE self)
{
    get_d1(self);

    if (simple_dat_p(dat))
	return d_simple_new_internal(CLASS_OF(self),
				     dat->s.nth,
				     dat->s.jd,
				     dat->s.sg,
				     dat->s.year,
#ifndef USE_PACK
				     dat->s.mon,
				     dat->s.mday,
#else
				     EX_MON(dat->s.pd),
				     EX_MDAY(dat->s.pd),
#endif
				     dat->s.flags);
    else
	return d_complex_new_internal(CLASS_OF(self),
				      dat->c.nth,
				      dat->c.jd,
				      dat->c.df,
				      dat->c.sf,
				      dat->c.of,
				      dat->c.sg,
				      dat->c.year,
#ifndef USE_PACK
				      dat->c.mon,
				      dat->c.mday,
				      dat->c.hour,
				      dat->c.min,
				      dat->c.sec,
#else
				      EX_MON(dat->c.pd),
				      EX_MDAY(dat->c.pd),
				      EX_HOUR(dat->c.pd),
				      EX_MIN(dat->c.pd),
				      EX_SEC(dat->c.pd),
#endif
				      dat->c.flags);
}

static VALUE
copy_obj_as_complex(VALUE self)
{
    get_d1(self);

    if (simple_dat_p(dat))
	return d_complex_new_internal(CLASS_OF(self),
				      dat->s.nth,
				      dat->s.jd,
				      0,
				      INT2FIX(0),
				      0,
				      dat->s.sg,
				      dat->s.year,
#ifndef USE_PACK
				      dat->s.mon,
				      dat->s.mday,
#else
				      EX_MON(dat->s.pd),
				      EX_MDAY(dat->s.pd),
#endif
				      0,
				      0,
				      0,
				      dat->s.flags | HAVE_DF);
    else
	return d_complex_new_internal(CLASS_OF(self),
				      dat->c.nth,
				      dat->c.jd,
				      dat->c.df,
				      dat->c.sf,
				      dat->c.of,
				      dat->c.sg,
				      dat->c.year,
#ifndef USE_PACK
				      dat->c.mon,
				      dat->c.mday,
				      dat->c.hour,
				      dat->c.min,
				      dat->c.sec,
#else
				      EX_MON(dat->c.pd),
				      EX_MDAY(dat->c.pd),
				      EX_HOUR(dat->c.pd),
				      EX_MIN(dat->c.pd),
				      EX_SEC(dat->c.pd),
#endif
				      dat->c.flags);
}

/* :nodoc: */
static VALUE
d_lite_initialize_copy(VALUE copy, VALUE date)
{
    if (copy == date)
	return copy;
    {
	get_d2(copy, date);
	if (simple_dat_p(bdat)) {
	    adat->s.nth = bdat->s.nth;
	    adat->s.jd = bdat->s.jd;
	    adat->s.sg = bdat->s.sg;
	    adat->s.year = bdat->s.year;
#ifndef USE_PACK
	    adat->s.mon = bdat->s.mon;
	    adat->s.mday = bdat->s.mday;
#else
	    adat->s.pd = bdat->s.pd;
#endif
	    adat->s.flags = bdat->s.flags;
	}
	else {
	    adat->c.nth = bdat->c.nth;
	    adat->c.jd = bdat->c.jd;
	    adat->c.df = bdat->c.df;
	    adat->c.sf = bdat->c.sf;
	    adat->c.of = bdat->c.of;
	    adat->c.sg = bdat->c.sg;
	    adat->c.year = bdat->c.year;
#ifndef USE_PACK
	    adat->c.mon = bdat->c.mon;
	    adat->c.mday = bdat->c.mday;
	    adat->c.hour = bdat->c.hour;
	    adat->c.min = bdat->c.min;
	    adat->c.sec = bdat->c.sec;
#else
	    adat->c.pd = bdat->c.pd;
#endif
	    adat->c.flags = bdat->c.flags | COMPLEX_DAT;
	}
    }
    return copy;
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
    return m_ajd(dat);
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
    VALUE r, sf;
    int df;

    get_d1(self);

    r = rb_rational_new1(f_sub(m_real_jd(dat), INT2FIX(2400001)));

    if (simple_dat_p(dat))
	return r;

    df = m_df(dat);
    if (df)
	r = f_add(r, isec_to_day(df));

    sf = m_sf(dat);
    if (f_nonzero_p(sf))
	r = f_add(r, ns_to_day(sf));
    return r;
}

#define return_once(k, expr)\
{\
    VALUE id, val;\
    get_d1(self);\
    id = ID2SYM(rb_intern(#k));\
    val = rb_hash_aref(dat->r.cache, id);\
    if (!NIL_P(val))\
	return val;\
    val = expr;\
    rb_hash_aset(dat->r.cache, id, val);\
    return val;\
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
    return m_real_local_jd(dat);
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
    return f_sub(m_real_local_jd(dat), INT2FIX(2400001));
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
    return f_sub(m_real_local_jd(dat), INT2FIX(2299160));
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
    return m_real_year(dat);
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
    return INT2FIX(m_yday(dat));
}

/*
 * call-seq:
 *    d.mon
 *    d.month
 *
 * Get the month of this date.
 *
 * January is month 1.
 */
static VALUE
d_lite_mon(VALUE self)
{
    get_d1(self);
    return INT2FIX(m_mon(dat));
}

/*
 * call-seq:
 *    d.mday
 *    d.day
 *
 * Get the day-of-the-month of this date.
 */
static VALUE
d_lite_mday(VALUE self)
{
    get_d1(self);
    return INT2FIX(m_mday(dat));
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
    if (simple_dat_p(dat))
	return INT2FIX(0);
    return m_fr(dat);
}

static VALUE
d_lite_wnum0(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    c_jd_to_weeknum(m_local_jd(dat), 0, m_sg(dat),
		    &ry, &rw, &rd);
    return INT2FIX(rw);
}

static VALUE
d_lite_wnum1(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    c_jd_to_weeknum(m_local_jd(dat), 1, m_sg(dat),
		    &ry, &rw, &rd);
    return INT2FIX(rw);
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
    return INT2FIX(m_hour(dat));
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
    return INT2FIX(m_min(dat));
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
    return INT2FIX(m_sec(dat));
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
    return m_sf_in_sec(dat);
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
    return m_of_in_day(dat);
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
    return m_zone(dat);
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
    VALUE ry2;

    get_d1(self);
    c_jd_to_commercial(m_local_jd(dat), m_sg(dat),
		       &ry, &rw, &rd);
    encode_year(m_nth(dat), ry, +1, &ry2);
    return ry2;
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
    c_jd_to_commercial(m_local_jd(dat), m_sg(dat),
		       &ry, &rw, &rd);
    return INT2FIX(rw);
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
    w = m_wday(dat);
    if (w == 0)
	w = 7;
    return INT2FIX(w);
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
    return INT2FIX(m_wday(dat));
}

/*
 * call-seq:
 *    d.sunday?
 *
 * Is the current date Sunday?
 */
static VALUE
d_lite_sunday_p(VALUE self)
{
    get_d1(self);
    return f_boolcast(m_wday(dat) == 0);
}

/*
 * call-seq:
 *    d.monday?
 *
 * Is the current date Monday?
 */
static VALUE
d_lite_monday_p(VALUE self)
{
    get_d1(self);
    return f_boolcast(m_wday(dat) == 1);
}

/*
 * call-seq:
 *    d.tuesday?
 *
 * Is the current date Tuesday?
 */
static VALUE
d_lite_tuesday_p(VALUE self)
{
    get_d1(self);
    return f_boolcast(m_wday(dat) == 2);
}

/*
 * call-seq:
 *    d.wednesday?
 *
 * Is the current date Wednesday?
 */
static VALUE
d_lite_wednesday_p(VALUE self)
{
    get_d1(self);
    return f_boolcast(m_wday(dat) == 3);
}

/*
 * call-seq:
 *    d.thursday?
 *
 * Is the current date Thursday?
 */
static VALUE
d_lite_thursday_p(VALUE self)
{
    get_d1(self);
    return f_boolcast(m_wday(dat) == 4);
}

/*
 * call-seq:
 *    d.friday?
 *
 * Is the current date Friday?
 */
static VALUE
d_lite_friday_p(VALUE self)
{
    get_d1(self);
    return f_boolcast(m_wday(dat) == 5);
}

/*
 * call-seq:
 *    d.saturday?
 *
 * Is the current date Saturday?
 */
static VALUE
d_lite_saturday_p(VALUE self)
{
    get_d1(self);
    return f_boolcast(m_wday(dat) == 6);
}

#ifndef NDEBUG
static VALUE
generic_nth_kday_p(VALUE self, VALUE n, VALUE k)
{
    int rjd, ns;

    get_d1(self);

    if (NUM2INT(k) != m_wday(dat))
	return Qfalse;

    c_nth_kday_to_jd(m_year(dat), m_mon(dat),
		     NUM2INT(n), NUM2INT(k), m_sg(dat),
		     &rjd, &ns);
    if (m_local_jd(dat) != rjd)
	return Qfalse;
    return Qtrue;
}
#endif

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
    return f_boolcast(m_julian_p(dat));
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
    return f_boolcast(m_gregorian_p(dat));
}

#define fix_style(dat) (m_julian_p(dat) ? JULIAN : GREGORIAN)

/*
 * call-seq:
 *    d.leap?
 *
 * Is this a leap year?
 */
static VALUE
d_lite_leap_p(VALUE self)
{
    double sg;
    int rjd, ns, ry, rm, rd;

    get_d1(self);
    sg = m_sg(dat);
    if (isinf(sg) && sg < 0)
	return f_boolcast(c_leap_p(m_year(dat)));

    c_civil_to_jd(m_year(dat), 3, 1, fix_style(dat),
		  &rjd, &ns);
    c_jd_to_civil(rjd - 1, fix_style(dat), &ry, &rm, &rd);
    return f_boolcast(rd == 29);
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
    return DBL2NUM(m_sg(dat));
}

static void
clear_civil(union DateData *x)
{
    if (simple_dat_p(x)) {
	x->s.year = 0;
#ifndef USE_PACK
	x->s.mon = 0;
	x->s.mday = 0;
#else
	x->s.pd = 0;
#endif
	x->s.flags &= ~HAVE_CIVIL;
    }
    else {
	x->c.year = 0;
#ifndef USE_PACK
	x->c.mon = 0;
	x->c.mday = 0;
	x->c.hour = 0;
	x->c.min = 0;
	x->c.sec = 0;
#else
	x->c.pd = 0;
#endif
	x->c.flags &= ~(HAVE_CIVIL | HAVE_TIME);
    }
}

static void
set_sg(union DateData *x, double sg)
{
    if (simple_dat_p(x)) {
	get_s_jd(x);
	clear_civil(x);
	x->s.sg = sg;
    } else {
	get_c_jd(x);
	get_c_df(x);
	clear_civil(x);
	x->c.sg = sg;
    }
}

static VALUE
copy_obj_with_new_start(VALUE obj, double sg)
{
    VALUE copy = copy_obj(obj);
    {
	get_d1(copy);
	set_sg(dat, sg);
    }
    return copy;
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

    rb_scan_args(argc, argv, "01", &vsg);

    sg = DEFAULT_SG;
    if (argc >= 1)
	val2sg(vsg, sg);

    return copy_obj_with_new_start(self, sg);
}

/*
 * call-seq:
 *    d.italy
 *
 * Create a copy of this Date object that uses the Italian/Catholic
 * Day of Calendar Reform.
 */
static VALUE
d_lite_italy(VALUE self)
{
    return copy_obj_with_new_start(self, ITALY);
}

/*
 * call-seq:
 *    d.england
 *
 * Create a copy of this Date object that uses the English/Colonial
 * Day of Calendar Reform.
 */
static VALUE
d_lite_england(VALUE self)
{
    return copy_obj_with_new_start(self, ENGLAND);
}

/*
 * call-seq:
 *    d.julian
 *
 * Create a copy of this Date object that always uses the Julian
 * Calendar.
 */
static VALUE
d_lite_julian(VALUE self)
{
    return copy_obj_with_new_start(self, JULIAN);
}

/*
 * call-seq:
 *    d.gregorian
 *
 * Create a copy of this Date object that always uses the Gregorian
 * Calendar.
 */
static VALUE
d_lite_gregorian(VALUE self)
{
    return copy_obj_with_new_start(self, GREGORIAN);
}

static void
set_of(union DateData *x, int of)
{
    assert(complex_dat_p(x));
    get_c_jd(x);
    get_c_df(x);
    clear_civil(x);
    x->c.of = of;
}

static VALUE
copy_obj_with_new_offset(VALUE obj, int of)
{
    VALUE copy = copy_obj_as_complex(obj);
    {
	get_d1(copy);
	set_of(dat, of);
    }
    return copy;
}

#define val2off(vof,iof) \
{\
    if (!offset_to_sec(vof, &iof)) {\
	iof = 0;\
	rb_warning("invalid offset is ignored");\
    }\
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

    rb_scan_args(argc, argv, "01", &vof);

    rof = 0;
    if (argc >= 1)
	val2off(vof, rof);

    return copy_obj_with_new_offset(self, rof);
}

/*
 * call-seq:
 *    d + other
 *
 * Return a new Date object that is +other+ days later than the
 * current one.
 *
 * +otehr+ may be a negative value, in which case the new Date
 * is earlier than the current one; however, #-() might be
 * more intuitive.
 *
 * If +other+ is not a Numeric, a TypeError will be thrown.  In
 * particular, two Dates cannot be added to each other.
 */
static VALUE
d_lite_plus(VALUE self, VALUE other)
{
    get_d1(self);

    switch (TYPE(other)) {
      case T_FIXNUM:
	{
	    VALUE nth;
	    long t;
	    int jd;

	    nth = m_nth(dat);
	    t = FIX2LONG(other);
	    if (DIV(t, CM_PERIOD)) {
		nth = f_add(nth, INT2FIX(DIV(t, CM_PERIOD)));
		t = MOD(t, CM_PERIOD);
	    }
	    jd = m_jd(dat) + (int)t;

	    if (jd < 0) {
		nth = f_sub(nth, INT2FIX(1));
		jd += CM_PERIOD;
	    }
	    else if (jd >= CM_PERIOD) {
		nth = f_add(nth, INT2FIX(1));
		jd -= CM_PERIOD;
	    }

	    if (simple_dat_p(dat))
		return d_simple_new_internal(CLASS_OF(self),
					     nth, jd,
					     m_sg(dat),
					     0, 0, 0,
					     (dat->s.flags | HAVE_JD) &
					     ~HAVE_CIVIL);
	    else
		return d_complex_new_internal(CLASS_OF(self),
					      nth, jd,
					      m_df(dat), m_sf(dat),
					      m_of(dat), m_sg(dat),
					      0, 0, 0,
					      m_hour(dat),
					      m_min(dat),
					      m_sec(dat),
					      (dat->c.flags | HAVE_JD) &
					      ~HAVE_CIVIL);
	}
	break;
      case T_BIGNUM:
	{
	    VALUE nth;
	    int jd, s;

	    if (f_positive_p(other))
		s = +1;
	    else {
		s = -1;
		other = f_negate(other);
	    }

	    nth = f_idiv(other, INT2FIX(CM_PERIOD));
	    jd = FIX2INT(f_mod(other, INT2FIX(CM_PERIOD)));

	    if (s < 0) {
		nth = f_negate(nth);
		jd = -jd;
	    }

	    jd = m_jd(dat) + jd;
	    if (jd < 0) {
		nth = f_sub(nth, INT2FIX(1));
		jd += CM_PERIOD;
	    }
	    else if (jd >= CM_PERIOD) {
		nth = f_add(nth, INT2FIX(1));
		jd -= CM_PERIOD;
	    }
	    nth = f_add(m_nth(dat), nth);

	    if (simple_dat_p(dat))
		return d_simple_new_internal(CLASS_OF(self),
					     nth, jd,
					     m_sg(dat),
					     0, 0, 0,
					     (dat->s.flags | HAVE_JD) &
					     ~HAVE_CIVIL);
	    else
		return d_complex_new_internal(CLASS_OF(self),
					      nth, jd,
					      m_df(dat), m_sf(dat),
					      m_of(dat), m_sg(dat),
					      0, 0, 0,
					      m_hour(dat),
					      m_min(dat),
					      m_sec(dat),
					      (dat->c.flags | HAVE_JD) &
					      ~HAVE_CIVIL);
	}
	break;
      case T_FLOAT:
	{
	    double jd, o, tmp;
	    int s, df;
	    VALUE nth, sf;

	    o = NUM2DBL(other);

	    if (o > 0)
		s = +1;
	    else {
		s = -1;
		o = -o;
	    }

	    o = modf(o, &tmp);

	    if (!floor(tmp / CM_PERIOD)) {
		nth = INT2FIX(0);
		jd = (int)tmp;
	    }
	    else {
		double i, f;

		f = modf(tmp / CM_PERIOD, &i);
		nth = f_floor(DBL2NUM(i));
		jd = (int)(f * CM_PERIOD);
	    }

	    o *= DAY_IN_SECONDS;
	    o = modf(o, &tmp);
	    df = (int)tmp;
	    o *= SECOND_IN_NANOSECONDS;
	    sf = INT2FIX((int)round(o));

	    if (s < 0) {
		jd = -jd;
		df = -df;
		sf = f_negate(sf);
	    }

	    sf = f_add(m_sf(dat), sf);
	    if (f_lt_p(sf, INT2FIX(0))) {
		df -= 1;
		sf = f_add(sf, INT2FIX(SECOND_IN_NANOSECONDS));
	    }
	    else if (f_ge_p(sf, INT2FIX(SECOND_IN_NANOSECONDS))) {
		df += 1;
		sf = f_sub(sf, INT2FIX(SECOND_IN_NANOSECONDS));
	    }

	    df = m_df(dat) + df;
	    if (df < 0) {
		jd -= 1;
		df += DAY_IN_SECONDS;
	    }
	    else if (df >= DAY_IN_SECONDS) {
		jd += 1;
		df -= DAY_IN_SECONDS;
	    }

	    jd = m_jd(dat) + jd;
	    if (jd < 0) {
		nth = f_sub(nth, INT2FIX(1));
		jd += CM_PERIOD;
	    }
	    else if (jd >= CM_PERIOD) {
		nth = f_add(nth, INT2FIX(1));
		jd -= CM_PERIOD;
	    }
	    nth = f_add(m_nth(dat), nth);

	    if (!df && f_zero_p(sf) && !m_of(dat))
		return d_simple_new_internal(CLASS_OF(self),
					     nth, jd,
					     m_sg(dat),
					     0, 0, 0,
					     (dat->s.flags | HAVE_JD) &
					     ~(HAVE_CIVIL | HAVE_TIME |
					       COMPLEX_DAT));
	    else
		return d_complex_new_internal(CLASS_OF(self),
					      nth, jd,
					      df, sf,
					      m_of(dat), m_sg(dat),
					      0, 0, 0,
					      0, 0, 0,
					      (dat->c.flags |
					       HAVE_JD | HAVE_DF) &
					      ~(HAVE_CIVIL | HAVE_TIME));
	}
	break;
      default:
	if (!k_numeric_p(other))
	    rb_raise(rb_eTypeError, "expected numeric");
	other = f_to_r(other);
      case T_RATIONAL:
	{
	    VALUE nth, sf, t;
	    int jd, df, s;

	    if (f_positive_p(other))
		s = +1;
	    else {
		s = -1;
		other = f_negate(other);
	    }

	    nth = f_idiv(other, INT2FIX(CM_PERIOD));
	    t = f_mod(other, INT2FIX(CM_PERIOD));

	    jd = FIX2INT(f_idiv(t, INT2FIX(1)));
	    t = f_mod(t, INT2FIX(1));

	    t = f_mul(t, INT2FIX(DAY_IN_SECONDS));
	    df = FIX2INT(f_idiv(t, INT2FIX(1)));
	    t = f_mod(t, INT2FIX(1));

	    sf = f_mul(t, INT2FIX(SECOND_IN_NANOSECONDS));

	    if (s < 0) {
		nth = f_negate(nth);
		jd = -jd;
		df = -df;
		sf = f_negate(sf);
	    }

	    sf = f_add(m_sf(dat), sf);
	    if (f_lt_p(sf, INT2FIX(0))) {
		df -= 1;
		sf = f_add(sf, INT2FIX(SECOND_IN_NANOSECONDS));
	    }
	    else if (f_ge_p(sf, INT2FIX(SECOND_IN_NANOSECONDS))) {
		df += 1;
		sf = f_sub(sf, INT2FIX(SECOND_IN_NANOSECONDS));
	    }

	    df = m_df(dat) + df;
	    if (df < 0) {
		jd -= 1;
		df += DAY_IN_SECONDS;
	    }
	    else if (df >= DAY_IN_SECONDS) {
		jd += 1;
		df -= DAY_IN_SECONDS;
	    }

	    jd = m_jd(dat) + jd;
	    if (jd < 0) {
		nth = f_sub(nth, INT2FIX(1));
		jd += CM_PERIOD;
	    }
	    else if (jd >= CM_PERIOD) {
		nth = f_add(nth, INT2FIX(1));
		jd -= CM_PERIOD;
	    }
	    nth = f_add(m_nth(dat), nth);

	    if (!df && f_zero_p(sf) && !m_of(dat))
		return d_simple_new_internal(CLASS_OF(self),
					     nth, jd,
					     m_sg(dat),
					     0, 0, 0,
					     (dat->s.flags | HAVE_JD) &
					     ~(HAVE_CIVIL | HAVE_TIME |
					       COMPLEX_DAT));
	    else
		return d_complex_new_internal(CLASS_OF(self),
					      nth, jd,
					      df, sf,
					      m_of(dat), m_sg(dat),
					      0, 0, 0,
					      0, 0, 0,
					      (dat->c.flags |
					       HAVE_JD | HAVE_DF) &
					      ~(HAVE_CIVIL | HAVE_TIME));
	}
	break;
    }
}

static VALUE
minus_dd(VALUE self, VALUE other)
{
    get_d2(self, other);

    {
	int d, df;
	VALUE n, sf, r;

	n = f_sub(m_nth(adat), m_nth(bdat));
	d = m_jd(adat) - m_jd(bdat);
	df = m_df(adat) - m_df(bdat);
	sf = f_sub(m_sf(adat), m_sf(bdat));

	if (d < 0) {
	    n = f_sub(n, INT2FIX(1));
	    d += CM_PERIOD;
	}
	else if (d >= CM_PERIOD) {
	    n = f_add(n, INT2FIX(1));
	    d -= CM_PERIOD;
	}

	if (df < 0) {
	    d -= 1;
	    df += DAY_IN_SECONDS;
	}
	else if (df >= DAY_IN_SECONDS) {
	    d += 1;
	    df -= DAY_IN_SECONDS;
	}

	if (f_lt_p(sf, INT2FIX(0))) {
	    df -= 1;
	    sf = f_add(sf, INT2FIX(SECOND_IN_NANOSECONDS));
	}
	else if (f_ge_p(sf, INT2FIX(SECOND_IN_NANOSECONDS))) {
	    df += 1;
	    sf = f_sub(sf, INT2FIX(SECOND_IN_NANOSECONDS));
	}

	if (f_zero_p(n))
	    r = INT2FIX(0);
	else
	    r = f_mul(n, INT2FIX(CM_PERIOD));

	if (d)
	    r = f_add(r, rb_rational_new1(INT2FIX(d)));
	if (df)
	    r = f_add(r, isec_to_day(df));
	if (f_nonzero_p(sf))
	    r = f_add(r, ns_to_day(sf));

	if (TYPE(r) == T_RATIONAL)
	    return r;
	return rb_rational_new1(r);
    }
}

/*
 * call-seq:
 *    d - other
 *
 * If +other+ is a Numeric value, create a new Date object that is
 * +other+ days earlier than the current one.
 *
 * If +other+ is a Date, return the number of days between the
 * two dates; or, more precisely, how many days later the current
 * date is than +other+.
 *
 * If +other+ is neither Numeric nor a Date, a TypeError is raised.
 */
static VALUE
d_lite_minus(VALUE self, VALUE other)
{
    if (k_date_p(other))
	return minus_dd(self, other);

    switch (TYPE(other)) {
      case T_FIXNUM:
	return d_lite_plus(self, LONG2NUM(-FIX2LONG(other)));
      case T_FLOAT:
	return d_lite_plus(self, DBL2NUM(-NUM2DBL(other)));
      default:
	if (!k_numeric_p(other))
	    rb_raise(rb_eTypeError, "expected numeric");
	return d_lite_plus(self, f_negate(other));
    }
}

/*
 * call-seq:
 *    d.next_day([n=1])
 *
 * Equivalent to d + n.
 */
static VALUE
d_lite_next_day(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return d_lite_plus(self, n);
}

/*
 * call-seq:
 *    d.prev_day([n=1])
 *
 * Equivalent to d - n.
 */
static VALUE
d_lite_prev_day(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return d_lite_minus(self, n);
}

/*
 * call-seq:
 *    d.next
 *
 * Return a new Date one day after this one.
 */
static VALUE
d_lite_next(VALUE self)
{
    return d_lite_next_day(0, (VALUE *)NULL, self);
}

/*
 * call-seq:
 *    d >> n
 *
 * Return a new Date object that is +n+ months later than
 * the current one.
 *
 * If the day-of-the-month of the current Date is greater
 * than the last day of the target month, the day-of-the-month
 * of the returned Date will be the last day of the target month.
 */
static VALUE
d_lite_rshift(VALUE self, VALUE other)
{
    VALUE t, y, nth, rjd2;
    int m, d, rjd;
    double sg;

    get_d1(self);
    t = f_add3(f_mul(m_real_year(dat), INT2FIX(12)),
	       f_sub(INT2FIX(m_mon(dat)), INT2FIX(1)),
	       other);
    y = f_idiv(t, INT2FIX(12));
    t = f_mod(t, INT2FIX(12));
    m = FIX2INT(f_add(t, INT2FIX(1)));
    d = m_mday(dat);
    sg = m_sg(dat);

    while (1) {
	int ry, rm, rd, ns;

	if (valid_civil_p(y, m, d, sg,
			  &nth, &ry,
			  &rm, &rd, &rjd, &ns))
	    break;
	if (--d < 1)
	    rb_raise(rb_eArgError, "invalid date");
    }
    encode_jd(nth, rjd, &rjd2);
    return f_add(self, f_sub(rjd2, m_real_local_jd(dat)));
}

/*
 * call-seq:
 *    d << n
 *
 * Return a new Date object that is +n+ months earlier than
 * the current one.
 *
 * If the day-of-the-month of the current Date is greater
 * than the last day of the target month, the day-of-the-month
 * of the returned Date will be the last day of the target month.
 */
static VALUE
d_lite_lshift(VALUE self, VALUE other)
{
    return d_lite_rshift(self, f_negate(other));
}

/*
 * call-seq:
 *    d.next_month([n=1])
 *
 * Equivalent to d >> n
 */
static VALUE
d_lite_next_month(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return d_lite_rshift(self, n);
}

/*
 * call-seq:
 *    d.prev_month([n=1])
 *
 * Equivalent to d << n
 */
static VALUE
d_lite_prev_month(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return d_lite_lshift(self, n);
}

/*
 * call-seq:
 *    d.next_year([n=1])
 *
 * Equivalent to d >> (n * 12)
 */
static VALUE
d_lite_next_year(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return d_lite_rshift(self, f_mul(n, INT2FIX(12)));
}

/*
 * call-seq:
 *    d.prev_year([n=1])
 *
 * Equivalent to d << (n * 12)
 */
static VALUE
d_lite_prev_year(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return d_lite_lshift(self, f_mul(n, INT2FIX(12)));
}

/*
 * call-seq:
 *    d.step(limit[, step=1])
 *    d.step(limit[, step=1]){|date| ...}
 *
 * Step the current date forward +step+ days at a
 * time (or backward, if +step+ is negative) until
 * we reach +limit+ (inclusive), yielding the resultant
 * date at each step.
 */
static VALUE
generic_step(int argc, VALUE *argv, VALUE self)
{
    VALUE limit, step, date;

    rb_scan_args(argc, argv, "11", &limit, &step);

    if (argc < 2)
	step = INT2FIX(1);

#if 0
    if (f_zero_p(step))
	rb_raise(rb_eArgError, "step can't be 0");
#endif

    RETURN_ENUMERATOR(self, argc, argv);

    date = self;
    switch (FIX2INT(f_cmp(step, INT2FIX(0)))) {
      case -1:
	while (f_ge_p(date, limit)) {
	    rb_yield(date);
	    date = f_add(date, step);
	}
	break;
      case 0:
	while (1)
	    rb_yield(date);
	break;
      case 1:
	while (f_le_p(date, limit)) {
	    rb_yield(date);
	    date = f_add(date, step);
	}
	break;
      default:
	abort();
    }
    return self;
}

/*
 * call-seq:
 *    d.upto(max)
 *    d.upto(max){|date| ...}
 *
 * Step forward one day at a time until we reach +max+
 * (inclusive), yielding each date as we go.
 */
static VALUE
generic_upto(VALUE self, VALUE max)
{
    VALUE date;

    RETURN_ENUMERATOR(self, 1, &max);

    date = self;
    while (f_le_p(date, max)) {
	rb_yield(date);
	date = f_add(date, INT2FIX(1));
    }
    return self;
}

/*
 * call-seq:
 *    d.downto(min)
 *    d.downto(min){|date| ...}
 *
 * Step backward one day at a time until we reach +min+
 * (inclusive), yielding each date as we go.
 */
static VALUE
generic_downto(VALUE self, VALUE min)
{
    VALUE date;

    RETURN_ENUMERATOR(self, 1, &min);

    date = self;
    while (f_ge_p(date, min)) {
	rb_yield(date);
	date = f_add(date, INT2FIX(-1));
    }
    return self;
}

static VALUE
cmp_gen(VALUE self, VALUE other)
{
    get_d1(self);

    if (k_numeric_p(other))
	return f_cmp(m_ajd(dat), other);
    else if (k_date_p(other))
	return f_cmp(m_ajd(dat), f_ajd(other));
    return rb_num_coerce_cmp(self, other, rb_intern("<=>"));
}

static VALUE
cmp_dd(VALUE self, VALUE other)
{
    get_d2(self, other);

    {
	VALUE a_nth, b_nth,
	    a_sf, b_sf;
	int a_jd, b_jd,
	    a_df, b_df;

	a_nth = m_nth(adat);
	b_nth = m_nth(bdat);
	if (f_eqeq_p(a_nth, b_nth)) {
	    a_jd = m_jd(adat);
	    b_jd = m_jd(bdat);
	    if (a_jd == b_jd) {
		a_df = m_df(adat);
		b_df = m_df(bdat);
		if (a_df == b_df) {
		    a_sf = m_sf(adat);
		    b_sf = m_sf(bdat);
		    if (f_eqeq_p(a_sf, b_sf)) {
			return INT2FIX(0);
		    }
		    else if (f_lt_p(a_sf, b_sf)) {
			return INT2FIX(-1);
		    }
		    else {
			return INT2FIX(1);
		    }
		}
		else if (a_df < b_df) {
		    return INT2FIX(-1);
		}
		else {
		    return INT2FIX(1);
		}
	    }
	    else if (a_jd < b_jd) {
		return INT2FIX(-1);
	    }
	    else {
		return INT2FIX(1);
	    }
	}
	else if (f_lt_p(a_nth, b_nth)) {
	    return INT2FIX(-1);
	}
	else {
	    return INT2FIX(1);
	}
    }
}

/*
 * call-seq:
 *    d <=> other
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
    if (!k_date_p(other))
	return cmp_gen(self, other);

    {
	get_d2(self, other);

	if (!(simple_dat_p(adat) && simple_dat_p(bdat) &&
	      m_gregorian_p(adat) == m_gregorian_p(bdat)))
	    return cmp_dd(self, other);

	if (have_jd_p(adat) &&
	    have_jd_p(bdat)) {
	    VALUE a_nth, b_nth;
	    int a_jd, b_jd;

	    a_nth = m_nth(adat);
	    b_nth = m_nth(bdat);
	    if (f_eqeq_p(a_nth, b_nth)) {
		a_jd = m_jd(adat);
		b_jd = m_jd(bdat);
		if (a_jd == b_jd) {
		    return INT2FIX(0);
		}
		else if (a_jd < b_jd) {
		    return INT2FIX(-1);
		}
		else {
		    return INT2FIX(1);
		}
	    }
	    else if (a_nth < b_nth) {
		return INT2FIX(-1);
	    }
	    else {
		return INT2FIX(1);
	    }
	}
	else {
#ifndef USE_PACK
	    VALUE a_nth, b_nth;
	    int a_year, b_year,
		a_mon, b_mon,
		a_mday, b_mday;
#else
	    VALUE a_nth, b_nth;
	    int a_year, b_year,
		a_pd, b_pd;
#endif

	    a_nth = m_nth(adat);
	    b_nth = m_nth(bdat);
	    if (f_eqeq_p(a_nth, b_nth)) {
		a_year = m_year(adat);
		b_year = m_year(bdat);
		if (a_year == b_year) {
#ifndef USE_PACK
		    a_mon = m_mon(adat);
		    b_mon = m_mon(bdat);
		    if (a_mon == b_mon) {
			a_mday = m_mday(adat);
			b_mday = m_mday(bdat);
			if (a_mday == b_mday) {
			    return INT2FIX(0);
			}
			else if (a_mday < b_mday) {
			    return INT2FIX(-1);
			}
			else {
			    return INT2FIX(1);
			}
		    }
		    else if (a_mon < b_mon) {
			return INT2FIX(-1);
		    }
		    else {
			return INT2FIX(1);
		    }
#else
		    a_pd = m_pd(adat);
		    b_pd = m_pd(bdat);
		    if (a_pd == b_pd) {
			return INT2FIX(0);
		    }
		    else if (a_pd < b_pd) {
			return INT2FIX(-1);
		    }
		    else {
			return INT2FIX(1);
		    }
#endif
		}
		else if (a_year < b_year) {
		    return INT2FIX(-1);
		}
		else {
		    return INT2FIX(1);
		}
	    }
	    else if (f_lt_p(a_nth, b_nth)) {
		return INT2FIX(-1);
	    }
	    else {
		return INT2FIX(1);
	    }
	}
    }
}

static VALUE
equal_gen(VALUE self, VALUE other)
{
    get_d1(self);

    if (k_numeric_p(other))
	return f_eqeq_p(m_real_local_jd(dat), other);
    else if (k_date_p(other))
	return f_eqeq_p(m_real_local_jd(dat), f_jd(other));
    return rb_num_coerce_cmp(self, other, rb_intern("=="));
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
    if (!k_date_p(other))
	return equal_gen(self, other);

    {
	get_d2(self, other);

	if (!(m_gregorian_p(adat) == m_gregorian_p(bdat)))
	    return equal_gen(self, other);

	if (have_jd_p(adat) &&
	    have_jd_p(bdat)) {
	    VALUE a_nth, b_nth;
	    int a_jd, b_jd;

	    a_nth = m_nth(adat);
	    b_nth = m_nth(bdat);
	    a_jd = m_local_jd(adat);
	    b_jd = m_local_jd(bdat);
	    if (f_eqeq_p(a_nth, b_nth) &&
		a_jd == b_jd)
		return Qtrue;
	    return Qfalse;
	}
	else {
#ifndef USE_PACK
	    VALUE a_nth, b_nth;
	    int a_year, b_year,
		a_mon, b_mon,
		a_mday, b_mday;
#else
	    VALUE a_nth, b_nth;
	    int a_year, b_year,
		a_pd, b_pd;
#endif

	    a_nth = m_nth(adat);
	    b_nth = m_nth(bdat);
	    if (f_eqeq_p(a_nth, b_nth)) {
		a_year = m_year(adat);
		b_year = m_year(bdat);
		if (a_year == b_year) {
#ifndef USE_PACK
		    a_mon = m_mon(adat);
		    b_mon = m_mon(bdat);
		    if (a_mon == b_mon) {
			a_mday = m_mday(adat);
			b_mday = m_mday(bdat);
			if (a_mday == b_mday)
			    return Qtrue;
		    }
#else
		    /* mon and mday only */
		    a_pd = (m_pd(adat) >> MDAY_SHIFT);
		    b_pd = (m_pd(bdat) >> MDAY_SHIFT);
		    if (a_pd == b_pd) {
			return Qtrue;
		    }
#endif
		}
	    }
	    return Qfalse;
	}
    }
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
    if (!k_date_p(other))
	return Qfalse;
    return f_zero_p(d_lite_cmp(self, other));
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
    return rb_hash(m_ajd(dat));
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

    if (f_zero_p(m_nth(dat)))
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "%.4d-%02d-%02d",
			      m_year(dat), m_mon(dat), m_mday(dat));
    else {
	VALUE argv[4];

	argv[0] = rb_usascii_str_new2("%.4d-%02d-%02d");
	argv[1] = m_real_year(dat);
	argv[2] = INT2FIX(m_mon(dat));
	argv[3] = INT2FIX(m_mday(dat));
	return rb_f_sprintf(4, argv);
    }
}

static VALUE
inspect_flags(VALUE self)
{
    get_d1(self);

    return rb_enc_sprintf(rb_usascii_encoding(),
			  "%c%c%c%c%c",
			  (dat->flags & COMPLEX_DAT) ? 'C' : 'S',
			  (dat->flags & HAVE_JD)     ? 'j' : '-',
			  (dat->flags & HAVE_DF)     ? 'd' : '-',
			  (dat->flags & HAVE_CIVIL)  ? 'c' : '-',
			  (dat->flags & HAVE_TIME)   ? 't' : '-');
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

    if (simple_dat_p(dat)) {
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "#<%s: %s "
			      "((%sth,%dj),+0s,%.0fj; "
			      "%dy%dm%dd; %s)>",
			      rb_obj_classname(self),
			      RSTRING_PTR(f_to_s(self)),
			      RSTRING_PTR(f_inspect(dat->s.nth)),
			      dat->s.jd, dat->s.sg,
#ifndef USE_PACK
			      dat->s.year, dat->s.mon, dat->s.mday,
#else
			      dat->s.year,
			      EX_MON(dat->s.pd), EX_MDAY(dat->s.pd),
#endif
			      RSTRING_PTR(inspect_flags(self)));
    }
    else {
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "#<%s: %s "
			      "((%sth,%dj,%ds,%sn),%+ds,%.0fj; "
			      "%dy%dm%dd %dh%dm%ds; %s)>",
			      rb_obj_classname(self),
			      RSTRING_PTR(f_to_s(self)),
			      RSTRING_PTR(f_inspect(dat->c.nth)),
			      dat->c.jd, dat->c.df,
			      RSTRING_PTR(f_inspect(dat->c.sf)),
			      dat->c.of, dat->c.sg,
#ifndef USE_PACK
			      dat->c.year, dat->c.mon, dat->c.mday,
			      dat->c.hour, dat->c.min, dat->c.sec,
#else
			      dat->c.year,
			      EX_MON(dat->c.pd), EX_MDAY(dat->c.pd),
			      EX_HOUR(dat->c.pd), EX_MIN(dat->c.pd),
			      EX_SEC(dat->c.pd),
#endif
			      RSTRING_PTR(inspect_flags(self)));
    }
}

#include <errno.h>
#include "date_tmx.h"

size_t
date_strftime(char *s, size_t maxsize, const char *format,
	      const struct tmx *tmx);

#define SMALLBUF 100
static size_t
date_strftime_alloc(char **buf, const char *format,
		    struct tmx *tmx)
{
    size_t size, len, flen;

    (*buf)[0] = '\0';
    flen = strlen(format);
    if (flen == 0) {
	return 0;
    }
    errno = 0;
    len = date_strftime(*buf, SMALLBUF, format, tmx);
    if (len != 0 || (**buf == '\0' && errno != ERANGE)) return len;
    for (size=1024; ; size*=2) {
	*buf = xmalloc(size);
	(*buf)[0] = '\0';
	len = date_strftime(*buf, size, format, tmx);
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
d_lite_set_tmx(VALUE self, struct tmx *tmx)
{
    get_d1(self);

    tmx->year = m_real_year(dat);
    tmx->yday = m_yday(dat);
    tmx->mon = m_mon(dat);
    tmx->mday = m_mday(dat);
    tmx->wday = m_wday(dat);

    if (simple_dat_p(dat)) {
	tmx->hour = 0;
	tmx->min = 0;
	tmx->sec = 0;
	tmx->offset = INT2FIX(0);
	tmx->zone = "+00:00";
	tmx->timev = day_to_sec(f_sub(m_real_jd(dat),
				      UNIX_EPOCH_IN_CJD));
    }
    else {
	tmx->hour = m_hour(dat);
	tmx->min = m_min(dat);
	tmx->sec = m_sec(dat);
	tmx->offset = INT2FIX(m_of(dat));
	tmx->zone = RSTRING_PTR(m_zone(dat));
	tmx->timev = day_to_sec(f_sub(m_ajd(dat),
				      UNIX_EPOCH_IN_AJD));
    }
}

static VALUE
date_strftime_internal(int argc, VALUE *argv, VALUE self,
		       const char *default_fmt,
		       void (*func)(VALUE, struct tmx *))
{
    {
	VALUE vfmt;
	const char *fmt;
	long len;
	char buffer[SMALLBUF], *buf = buffer;
	struct tmx tmx;
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
	(*func)(self, &tmx);
	if (memchr(fmt, '\0', len)) {
	    /* Ruby string may contain \0's. */
	    const char *p = fmt, *pe = fmt + len;

	    str = rb_str_new(0, 0);
	    while (p < pe) {
		len = date_strftime_alloc(&buf, p, &tmx);
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
	    len = date_strftime_alloc(&buf, fmt, &tmx);

	str = rb_str_new(buf, len);
	if (buf != buffer) xfree(buf);
	rb_enc_copy(str, vfmt);
	OBJ_INFECT(str, vfmt);
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
				  "%F", d_lite_set_tmx);
}

static VALUE
strftimev(const char *fmt, VALUE self,
	  void (*func)(VALUE, struct tmx *))
{
    char buffer[SMALLBUF], *buf = buffer;
    struct tmx tmx;
    long len;
    VALUE str;

    (*func)(self, &tmx);
    len = date_strftime_alloc(&buf, fmt, &tmx);
    str = rb_usascii_str_new(buf, len);
    if (buf != buffer) xfree(buf);
    return str;
}

/*
 * call-seq:
 *    d.asctime
 *    d.ctime
 *
 * Equivalent to strftime('%c').
 * See also asctime(3) or ctime(3).
 */
static VALUE
d_lite_asctime(VALUE self)
{
    return strftimev("%c", self, d_lite_set_tmx);
}

/*
 * call-seq:
 *    d.iso8601
 *    d.xmlschema
 *
 * Equivalent to strftime('%F').
 */
static VALUE
d_lite_iso8601(VALUE self)
{
    return strftimev("%F", self, d_lite_set_tmx);
}

/*
 * call-seq:
 *    d.rfc3339
 *
 * Equivalent to strftime('%FT%T%:z').
 */
static VALUE
d_lite_rfc3339(VALUE self)
{
    return strftimev("%FT%T%:z", self, d_lite_set_tmx);
}

/*
 * call-seq:
 *    d.rfc2822
 *    d.rfc822
 *
 * Equivalent to strftime('%a, %-d %b %Y %T %z').
 */
static VALUE
d_lite_rfc2822(VALUE self)
{
    return strftimev("%a, %-d %b %Y %T %z", self, d_lite_set_tmx);
}

/*
 * call-seq:
 *    d.httpdate
 *
 * Equivalent to strftime('%a, %d %b %Y %T GMT').
 * See also RFC 2616.
 */
static VALUE
d_lite_httpdate(VALUE self)
{
    VALUE d = copy_obj_with_new_offset(self, 0);
    return strftimev("%a, %d %b %Y %T GMT", d, d_lite_set_tmx);
}

static VALUE
gengo(VALUE jd, VALUE y, VALUE *a)
{
    if (f_lt_p(jd, INT2FIX(2405160)))
       return 0;
    if (f_lt_p(jd, INT2FIX(2419614))) {
	a[0] = rb_usascii_str_new2("M%02d");
	a[1] = f_sub(y, INT2FIX(1867));
    }
    else if (f_lt_p(jd, INT2FIX(2424875))) {
	a[0] = rb_usascii_str_new2("T%02d");
	a[1] = f_sub(y, INT2FIX(1911));
    }
    else if (f_lt_p(jd, INT2FIX(2447535))) {
	a[0] = rb_usascii_str_new2("S%02d");
	a[1] = f_sub(y, INT2FIX(1925));
    }
    else {
	a[0] = rb_usascii_str_new2("H%02d");
	a[1] = f_sub(y, INT2FIX(1988));
    }
    return 1;
}

/*
 * call-seq:
 *    d.jisx0301
 *
 * Return a string as a JIS X 0301 format.
 */
static VALUE
d_lite_jisx0301(VALUE self)
{
    VALUE argv[2];

    get_d1(self);

    if (!gengo(m_real_local_jd(dat),
	       m_real_year(dat),
	       argv))
	return strftimev("%F", self, d_lite_set_tmx);
    return f_add(rb_f_sprintf(2, argv),
		 strftimev(".%m.%d", self, d_lite_set_tmx));
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

    a = rb_ary_new3(6,
		    m_nth(dat),
		    INT2FIX(m_jd(dat)),
		    INT2FIX(m_df(dat)),
		    m_sf(dat),
		    INT2FIX(m_of(dat)),
		    DBL2NUM(m_sg(dat)));

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
	{
	    VALUE ajd, of, sg, nth, sf;
	    int jd, df, rof;
	    double rsg;
	    unsigned flags;

	    ajd = RARRAY_PTR(a)[0];
	    of = RARRAY_PTR(a)[1];
	    sg = RARRAY_PTR(a)[2];

	    old_to_new(ajd, of, sg,
		       &nth, &jd, &df, &sf, &rof, &rsg, &flags);

	    dat->c.nth = nth;
	    dat->c.jd = jd;
	    dat->c.df = df;
	    dat->c.sf = sf;
	    dat->c.of = rof;
	    dat->c.sg = rsg;
	    dat->c.year = 0;
#ifndef USE_PACK
	    dat->c.mon = 0;
	    dat->c.mday = 0;
	    dat->c.hour = 0;
	    dat->c.min = 0;
	    dat->c.sec = 0;
#else
	    dat->c.pd = 0;
#endif
	    dat->c.flags = flags;
	}
	break;
      case 6:
	{
	    VALUE nth, sf;
	    int jd, df, of;
	    double sg;

	    nth = RARRAY_PTR(a)[0];
	    jd = NUM2INT(RARRAY_PTR(a)[1]);
	    df = NUM2INT(RARRAY_PTR(a)[2]);
	    sf = RARRAY_PTR(a)[3];
	    of = NUM2INT(RARRAY_PTR(a)[4]);
	    sg = NUM2DBL(RARRAY_PTR(a)[5]);

	    if (!df && f_zero_p(sf) && !of) {
		dat->s.nth = nth;
		dat->s.jd = jd;
		dat->s.sg = sg;
		dat->s.year = 0;
#ifndef USE_PACK
		dat->s.mon = 0;
		dat->s.mday = 0;
#else
		dat->s.pd = 0;
#endif
		dat->s.flags = HAVE_JD;
	    }
	    else {
		dat->c.nth = nth;
		dat->c.jd = jd;
		dat->c.df = df;
		dat->c.sf = sf;
		dat->c.of = of;
		dat->c.sg = sg;
		dat->c.year = 0;
#ifndef USE_PACK
		dat->c.mon = 0;
		dat->c.mday = 0;
		dat->c.hour = 0;
		dat->c.min = 0;
		dat->c.sec = 0;
#else
		dat->c.pd = 0;
#endif
		dat->c.flags = HAVE_JD | HAVE_DF | COMPLEX_DAT;
	    }
	}
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


/* datetime light */

/*
 * call-seq:
 *    DateTime.jd([jd=0[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Julian Day Number +jd+, +hour+, +minute+ and +second+.
 *
 * The 24-hour clock is used.  Negative values of +hour+, +minute+, and
 * +second+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +minute+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +offset+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +start+ specifies the Day of Calendar Reform.
 *
 * All day/time values default to 0.
 */
static VALUE
datetime_s_jd(int argc, VALUE *argv, VALUE klass)
{
    VALUE vjd, vh, vmin, vs, vof, vsg, jd, fr, fr2, ret;
    int h, min, s, rof;
    double sg;

    rb_scan_args(argc, argv, "06", &vjd, &vh, &vmin, &vs, &vof, &vsg);

    jd = INT2FIX(0);

    h = min = s = 0;
    fr2 = INT2FIX(0);
    rof = 0;
    sg = DEFAULT_SG;

    switch (argc) {
      case 6:
	val2sg(vsg, sg);
      case 5:
	val2off(vof, rof);
      case 4:
	num2int_with_frac(s, positive_inf);
      case 3:
	num2int_with_frac(min, 3);
      case 2:
	num2int_with_frac(h, 2);
      case 1:
	num2num_with_frac(jd, 1);
    }

    {
	VALUE nth;
	int rh, rmin, rs, rjd, rjd2;

	if (!c_valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	decode_jd(jd, &nth, &rjd);
	rjd2 = jd_local_to_utc(rjd,
			       time_to_df(rh, rmin, rs),
			       rof);

	ret = d_complex_new_internal(klass,
				     nth, rjd2,
				     0, INT2FIX(0),
				     rof, sg,
				     0, 0, 0,
				     rh, rmin, rs,
				     HAVE_JD | HAVE_TIME);
    }
    add_frac();
    return ret;
}

/*
 * call-seq:
 *    DateTime.ordinal([year=-4712[, yday=1[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Ordinal Date, +hour+, +minute+ and +second+.
 *
 * The 24-hour clock is used.  Negative values of +hour+, +minute+, and
 * +second+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +minute+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +offset+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +start+ specifies the Day of Calendar Reform.
 *
 * +year+ defaults to -4712, and +yda+ to 1; this is Julian Day Number
 * day 0.  The time values default to 0.
*/
static VALUE
datetime_s_ordinal(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vd, vh, vmin, vs, vof, vsg, y, fr, fr2, ret;
    int d, h, min, s, rof;
    double sg;

    rb_scan_args(argc, argv, "07", &vy, &vd, &vh, &vmin, &vs, &vof, &vsg);

    y = INT2FIX(-4712);
    d = 1;

    h = min = s = 0;
    fr2 = INT2FIX(0);
    rof = 0;
    sg = DEFAULT_SG;

    switch (argc) {
      case 7:
	val2sg(vsg, sg);
      case 6:
	val2off(vof, rof);
      case 5:
	num2int_with_frac(s, positive_inf);
      case 4:
	num2int_with_frac(min, 4);
      case 3:
	num2int_with_frac(h, 3);
      case 2:
	num2int_with_frac(d, 2);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rd, rh, rmin, rs, rjd, rjd2, ns;

	if (!valid_ordinal_p(y, d, sg,
			     &nth, &ry,
			     &rd, &rjd,
			     &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!c_valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	rjd2 = jd_local_to_utc(rjd,
			       time_to_df(rh, rmin, rs),
			       rof);

	ret = d_complex_new_internal(klass,
				     nth, rjd2,
				     0, INT2FIX(0),
				     rof, sg,
				     0, 0, 0,
				     rh, rmin, rs,
				     HAVE_JD | HAVE_TIME);
    }
    add_frac();
    return ret;
}

/*
 * call-seq:
 *    DateTime.civil([year=-4712[, month=1[, mday=1[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]]]])
 *    DateTime.new([year=-4712[, month=1[, mday=1[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Civil Date, +hour+, +minute+ and +second+.
 *
 * The 24-hour clock is used.  Negative values of +hour+, +minute+, and
 * +second+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +minute+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +offset+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +start+ specifies the Day of Calendar Reform.
 *
 * +year+ defaults to -4712, +month+ to 1, and +mday+ to 1; this is Julian Day
 * Number day 0.  The time values default to 0.
 */
static VALUE
datetime_s_civil(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vd, vh, vmin, vs, vof, vsg, y, fr, fr2, ret;
    int m, d, h, min, s, rof;
    double sg;

    rb_scan_args(argc, argv, "08", &vy, &vm, &vd, &vh, &vmin, &vs, &vof, &vsg);

    y = INT2FIX(-4712);
    m = 1;
    d = 1;

    h = min = s = 0;
    fr2 = INT2FIX(0);
    rof = 0;
    sg = DEFAULT_SG;

    switch (argc) {
      case 8:
	val2sg(vsg, sg);
      case 7:
	val2off(vof, rof);
      case 6:
	num2int_with_frac(s, positive_inf);
      case 5:
	num2int_with_frac(min, 5);
      case 4:
	num2int_with_frac(h, 4);
      case 3:
	num2int_with_frac(d, 3);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = vy;
    }

    if (isinf(sg) && sg < 0) {
	VALUE nth;
	int ry, rm, rd, rh, rmin, rs;

	if (!valid_gregorian_p(y, m, d,
			       &nth, &ry,
			       &rm, &rd))
	    rb_raise(rb_eArgError, "invalid date");
	if (!c_valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	ret = d_complex_new_internal(klass,
				     nth, 0,
				     0, INT2FIX(0),
				     rof, sg,
				     ry, rm, rd,
				     rh, rmin, rs,
				     HAVE_CIVIL | HAVE_TIME);
    }
    else {
	VALUE nth;
	int ry, rm, rd, rh, rmin, rs, rjd, rjd2, ns;

	if (!valid_civil_p(y, m, d, sg,
			   &nth, &ry,
			   &rm, &rd, &rjd,
			   &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!c_valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	rjd2 = jd_local_to_utc(rjd,
			       time_to_df(rh, rmin, rs),
			       rof);

	ret = d_complex_new_internal(klass,
				     nth, rjd2,
				     0, INT2FIX(0),
				     rof, sg,
				     ry, rm, rd,
				     rh, rmin, rs,
				     HAVE_JD | HAVE_CIVIL | HAVE_TIME);
    }
    add_frac();
    return ret;
}

/*
 * call-seq:
 *    DateTime.commercial([cwyear=-4712[, cweek=1[, cwday=1[, hour=0[, minute=0[, second=0[, offset=0[, start=Date::ITALY]]]]]]]])
 *
 * Create a new DateTime object corresponding to the specified
 * Commercial Date, +hour+, +minute+ and +second+.
 *
 * The 24-hour clock is used.  Negative values of +hour+, +minute+, and
 * +second+ are treating as counting backwards from the end of the
 * next larger unit (e.g. a +minut+ of -2 is treated as 58).  No
 * wraparound is performed.  If an invalid time portion is specified,
 * an ArgumentError is raised.
 *
 * +offset+ is the offset from UTC as a fraction of a day (defaults to 0).
 * +start+ specifies the Day of Calendar Reform.
 *
 * +cwyear+ (calendar-week-based-year) defaults to -4712,
 * +cweek+ to 1, and +mday+ to 1; this is
 * Julian Day Number day 0.
 * The time values default to 0.
 */
static VALUE
datetime_s_commercial(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vh, vmin, vs, vof, vsg, y, fr, fr2, ret;
    int w, d, h, min, s, rof;
    double sg;

    rb_scan_args(argc, argv, "08", &vy, &vw, &vd, &vh, &vmin, &vs, &vof, &vsg);

    y = INT2FIX(-4712);
    w = 1;
    d = 1;

    h = min = s = 0;
    fr2 = INT2FIX(0);
    rof = 0;
    sg = DEFAULT_SG;

    switch (argc) {
      case 8:
	val2sg(vsg, sg);
      case 7:
	val2off(vof, rof);
      case 6:
	num2int_with_frac(s, positive_inf);
      case 5:
	num2int_with_frac(min, 5);
      case 4:
	num2int_with_frac(h, 4);
      case 3:
	num2int_with_frac(d, 3);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rw, rd, rh, rmin, rs, rjd, rjd2, ns;

	if (!valid_commercial_p(y, w, d, sg,
				&nth, &ry,
				&rw, &rd, &rjd,
				&ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!c_valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");


	rjd2 = jd_local_to_utc(rjd,
			       time_to_df(rh, rmin, rs),
			       rof);

	ret = d_complex_new_internal(klass,
				     nth, rjd2,
				     0, INT2FIX(0),
				     rof, sg,
				     0, 0, 0,
				     rh, rmin, rs,
				     HAVE_JD | HAVE_TIME);
    }
    add_frac();
    return ret;
}

#ifndef NDEBUG
static VALUE
datetime_s_weeknum(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vf, vh, vmin, vs, vof, vsg, y, fr, fr2, ret;
    int w, d, f, h, min, s, rof;
    double sg;

    rb_scan_args(argc, argv, "09", &vy, &vw, &vd, &vf,
		 &vh, &vmin, &vs, &vof, &vsg);

    y = INT2FIX(-4712);
    w = 0;
    d = 1;
    f = 0;

    h = min = s = 0;
    fr2 = INT2FIX(0);
    rof = 0;
    sg = DEFAULT_SG;

    switch (argc) {
      case 9:
	val2sg(vsg, sg);
      case 8:
	val2off(vof, rof);
      case 7:
	num2int_with_frac(s, positive_inf);
      case 6:
	num2int_with_frac(min, 6);
      case 5:
	num2int_with_frac(h, 5);
      case 4:
	f = NUM2INT(vf);
      case 3:
	num2int_with_frac(d, 4);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rw, rd, rh, rmin, rs, rjd, rjd2, ns;

	if (!valid_weeknum_p(y, w, d, f, sg,
			     &nth, &ry,
			     &rw, &rd, &rjd,
			     &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!c_valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	rjd2 = jd_local_to_utc(rjd,
			       time_to_df(rh, rmin, rs),
			       rof);

	ret = d_complex_new_internal(klass,
				     nth, rjd2,
				     0, INT2FIX(0),
				     rof, sg,
				     0, 0, 0,
				     rh, rmin, rs,
				     HAVE_JD | HAVE_TIME);
    }
    add_frac();
    return ret;
}

static VALUE
datetime_s_nth_kday(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vn, vk, vh, vmin, vs, vof, vsg, y, fr, fr2, ret;
    int m, n, k, h, min, s, rof;
    double sg;

    rb_scan_args(argc, argv, "09", &vy, &vm, &vn, &vk,
		 &vh, &vmin, &vs, &vof, &vsg);

    y = INT2FIX(-4712);
    m = 1;
    n = 1;
    k = 1;

    h = min = s = 0;
    fr2 = INT2FIX(0);
    rof = 0;
    sg = DEFAULT_SG;

    switch (argc) {
      case 9:
	val2sg(vsg, sg);
      case 8:
	val2off(vof, rof);
      case 7:
	num2int_with_frac(s, positive_inf);
      case 6:
	num2int_with_frac(min, 6);
      case 5:
	num2int_with_frac(h, 5);
      case 4:
	num2int_with_frac(k, 4);
      case 3:
	n = NUM2INT(vn);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = vy;
    }

    {
	VALUE nth;
	int ry, rm, rn, rk, rh, rmin, rs, rjd, rjd2, ns;

	if (!valid_nth_kday_p(y, m, n, k, sg,
			      &nth, &ry,
			      &rm, &rn, &rk, &rjd,
			      &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!c_valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	rjd2 = jd_local_to_utc(rjd,
			       time_to_df(rh, rmin, rs),
			       rof);

	ret = d_complex_new_internal(klass,
				     nth, rjd2,
				     0, INT2FIX(0),
				     rof, sg,
				     0, 0, 0,
				     rh, rmin, rs,
				     HAVE_JD | HAVE_TIME);
    }
    add_frac();
    return ret;
}
#endif

/*
 * call-seq:
 *    DateTime.now([start=Date::ITALY])
 *
 * Create a new DateTime object representing the current time.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
datetime_s_now(int argc, VALUE *argv, VALUE klass)
{
    VALUE vsg, nth, ret;
    double sg;
#ifdef HAVE_CLOCK_GETTIME
    struct timespec ts;
#else
    struct timeval tv;
#endif
    time_t sec;
    struct tm tm;
    long sf, of;
    int y, ry, m, d, h, min, s;

    rb_scan_args(argc, argv, "01", &vsg);

    if (argc < 1)
	sg = DEFAULT_SG;
    else
	sg = NUM2DBL(vsg);

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
    of = tm.tm_gmtoff;
#else
    of = -timezone;
#endif
#ifdef HAVE_CLOCK_GETTIME
    sf = ts.tv_nsec;
#else
    sf = tv.tv_usec * 1000;
#endif

    if (of < -DAY_IN_SECONDS || of > DAY_IN_SECONDS) {
	of = 0;
	rb_warning("invalid offset is ignored");
    }

    decode_year(INT2FIX(y), -1, &nth, &ry);

    ret = d_complex_new_internal(klass,
				 nth, 0,
				 0, LONG2NUM(sf),
				 (int)of, GREGORIAN,
				 ry, m, d,
				 h, min, s,
				 HAVE_CIVIL | HAVE_TIME);
    {
	get_d1(ret);
	set_sg(dat, sg);
    }
    return ret;
}

static VALUE
dt_new_by_frags(VALUE klass, VALUE hash, VALUE sg)
{
    VALUE jd, sf, t;
    int df, of;

    if (!c_valid_start_p(NUM2DBL(sg))) {
	sg = INT2FIX(DEFAULT_SG);
	rb_warning("invalid start is ignored");
    }

    hash = rt_rewrite_frags(hash);
    hash = rt_complete_frags(klass, hash);

    jd = rt__valid_date_frags_p(hash, sg);
    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");

    {
	int rh, rmin, rs;

	if (!c_valid_time_p(NUM2INT(ref_hash("hour")),
			    NUM2INT(ref_hash("min")),
			    NUM2INT(ref_hash("sec")),
			    &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	df = time_to_df(rh, rmin, rs);
    }

    t = ref_hash("sec_fraction");
    if (NIL_P(t))
	sf = INT2FIX(0);
    else
	sf = sec_to_ns(t);

    t = ref_hash("offset");
    if (NIL_P(t))
	of = 0;
    else {
	of = NUM2INT(t);
	if (of < -DAY_IN_SECONDS || of > DAY_IN_SECONDS) {
	    of = 0;
	    rb_warning("invalid offset is ignored");
	}
    }
    {
	VALUE nth;
	int rjd, rjd2;

	decode_jd(jd, &nth, &rjd);
	rjd2 = jd_local_to_utc(rjd, df, of);
	df = df_local_to_utc(df, of);

	return d_complex_new_internal(klass,
				      nth, rjd2,
				      df, sf,
				      of, NUM2DBL(sg),
				      0, 0, 0,
				      0, 0, 0,
				      HAVE_JD | HAVE_DF);
    }
}

/*
 * call-seq:
 *    DateTime._strptime(string[, format="%FT%T%z"])
 *
 * Return a hash of parsed elements.
 */
static VALUE
datetime_s__strptime(int argc, VALUE *argv, VALUE klass)
{
    return date_s__strptime_internal(argc, argv, klass, "%FT%T%z");
}

/*
 * call-seq:
 *    DateTime.strptime([string="-4712-01-01T00:00:00+00:00"[, format="%FT%T%z"[,start=ITALY]]])
 *
 * Create a new DateTime object by parsing from a String
 * according to a specified format.
 *
 * +string+ is a String holding a date-time representation.
 * +format+ is the format that the date-time is in.
 *
 * The default +string+ is '-4712-01-01T00:00:00+00:00', and the default
 * +fmt+ is '%FT%T%z'.  This gives midnight on Julian Day Number day 0.
 *
 * +start+ specifies the Day of Calendar Reform.
 *
 * An ArgumentError will be raised if +str+ cannot be
 * parsed.
 */
static VALUE
datetime_s_strptime(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, fmt, sg;

    rb_scan_args(argc, argv, "03", &str, &fmt, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01T00:00:00+00:00");
      case 1:
	fmt = rb_str_new2("%FT%T%z");
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = fmt;
	hash = date_s__strptime(2, argv2, klass);
	return dt_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    Date.parse(string="-4712-01-01T00:00:00+00:00"[, comp=true[,start=ITALY]])
 *
 * Create a new DateTime object by parsing from a String,
 * without specifying the format.
 *
 * +string+ is a String holding a date-time representation.
 * +comp+ specifies whether to interpret 2-digit years
 * as 19XX (>= 69) or 20XX (< 69); the default is to.
 * The method will attempt to parse a date-time from the String
 * using various heuristics.
 * If parsing fails, an ArgumentError will be raised.
 *
 * The default +string+ is '-4712-01-01T00:00:00+00:00'; this is Julian
 * Day Number day 0.
 *
 * +start+ specifies the Day of Calendar Reform.
 */
static VALUE
datetime_s_parse(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01T00:00:00+00:00");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = comp;
	hash = date_s__parse(2, argv2, klass);
	return dt_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    DateTime.iso8601(string="-4712-01-01T00:00:00+00:00"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical ISO 8601 format.
 */
static VALUE
datetime_s_iso8601(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01T00:00:00+00:00");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__iso8601(klass, str);
	return dt_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    DateTime.rfc3339(string="-4712-01-01T00:00:00+00:00"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical RFC 3339 format.
 */
static VALUE
datetime_s_rfc3339(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01T00:00:00+00:00");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__rfc3339(klass, str);
	return dt_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    DateTime.xmlschema(string="-4712-01-01T00:00:00+00:00"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical XML Schema format.
 */
static VALUE
datetime_s_xmlschema(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01T00:00:00+00:00");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__xmlschema(klass, str);
	return dt_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    DateTime.rfc2822(string="Mon, 1 Jan -4712 00:00:00 +0000"[,start=ITALY])
 *    DateTime.rfc822(string="Mon, 1 Jan -4712 00:00:00 +0000"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical RFC 2822 format.
 */
static VALUE
datetime_s_rfc2822(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("Mon, 1 Jan -4712 00:00:00 +0000");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__rfc2822(klass, str);
	return dt_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    DateTime.httpdate(string="Mon, 01 Jan -4712 00:00:00 GMT"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some RFC 2616 format.
 */
static VALUE
datetime_s_httpdate(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("Mon, 01 Jan -4712 00:00:00 GMT");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__httpdate(klass, str);
	return dt_new_by_frags(klass, hash, sg);
    }
}

/*
 * call-seq:
 *    DateTime.jisx0301(string="-4712-01-01T00:00:00+00:00"[,start=ITALY])
 *
 * Create a new Date object by parsing from a String
 * according to some typical JIS X 0301 format.
 */
static VALUE
datetime_s_jisx0301(int argc, VALUE *argv, VALUE klass)
{
    VALUE str, comp, sg;

    rb_scan_args(argc, argv, "03", &str, &comp, &sg);

    switch (argc) {
      case 0:
	str = rb_str_new2("-4712-01-01T00:00:00+00:00");
      case 1:
	comp = Qtrue;
      case 2:
	sg = INT2FIX(DEFAULT_SG);
    }

    {
	VALUE hash = date_s__jisx0301(klass, str);
	return dt_new_by_frags(klass, hash, sg);
    }
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
    get_d1(self);

    if (f_zero_p(m_nth(dat))) {
	int s, h, m;

	decode_offset(m_of(dat), s, h, m);
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "%.4d-%02d-%02dT"
			      "%02d:%02d:%02d"
			      "%c%02d:%02d",
			      m_year(dat), m_mon(dat), m_mday(dat),
			      m_hour(dat), m_min(dat), m_sec(dat),
			      s, h, m);
    }
    else {
	int s, h, m;
	VALUE argv[10];

	decode_offset(m_of(dat), s, h, m);
	argv[0] = rb_usascii_str_new2("%.4d-%02d-%02dT"
				      "%02d:%02d:%02d"
				      "%c%02d:%02d");
	argv[1] = m_real_year(dat);
	argv[2] = INT2FIX(m_mon(dat));
	argv[3] = INT2FIX(m_mday(dat));
	argv[4] = INT2FIX(m_hour(dat));
	argv[5] = INT2FIX(m_min(dat));
	argv[6] = INT2FIX(m_sec(dat));
	argv[7] = INT2FIX(s);
	argv[8] = INT2FIX(h);
	argv[9] = INT2FIX(m);
	return rb_f_sprintf(10, argv);
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
				  "%FT%T%:z", d_lite_set_tmx);
}

static VALUE
dt_lite_iso8601_timediv(VALUE self, VALUE n)
{
    VALUE f, fmt;

    if (f_lt_p(n, INT2FIX(1)))
	f = rb_usascii_str_new2("");
    else {
	VALUE argv[3];

	get_d1(self);

	argv[0] = rb_usascii_str_new2(".%0*d");
	argv[1] = n;
	argv[2] = f_round(f_quo(m_sf_in_sec(dat),
			    f_quo(INT2FIX(1),
				  f_expt(INT2FIX(10), n))));
	f = rb_f_sprintf(3, argv);
    }
    fmt = f_add3(rb_usascii_str_new2("T%T"),
		 f,
		 rb_usascii_str_new2("%:z"));
    return strftimev(RSTRING_PTR(fmt), self, d_lite_set_tmx);
}

/*
 * call-seq:
 *    dt.iso8601([n=0])
 *    dt.xmlschema([n=0])
 *
 * Equivalent to strftime('%FT%T').
 * The optional argument n is length of fractional seconds.
 */
static VALUE
dt_lite_iso8601(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);

    if (argc < 1)
	n = INT2FIX(0);

    return f_add(strftimev("%F", self, d_lite_set_tmx),
		 dt_lite_iso8601_timediv(self, n));
}

/*
 * call-seq:
 *    dt.rfc3339([n=0])
 *
 * Equivalent to strftime('%FT%T').
 * The optional argument n is length of fractional seconds.
 */
static VALUE
dt_lite_rfc3339(int argc, VALUE *argv, VALUE self)
{
    return dt_lite_iso8601(argc, argv, self);
}

/*
 * call-seq:
 *    dt.jisx0301
 *
 * Return a string as a JIS X 0301 format.
 */
static VALUE
dt_lite_jisx0301(int argc, VALUE *argv, VALUE self)
{
    VALUE n, argv2[2];

    rb_scan_args(argc, argv, "01", &n);

    if (argc < 1)
	n = INT2FIX(0);

    {
	get_d1(self);

	if (!gengo(m_real_local_jd(dat),
		   m_real_year(dat),
		   argv2))
	    return f_add(strftimev("%F", self, d_lite_set_tmx),
			 dt_lite_iso8601_timediv(self, n));
	return f_add(f_add(rb_f_sprintf(2, argv2),
			   strftimev(".%m.%d", self, d_lite_set_tmx)),
		     dt_lite_iso8601_timediv(self, n));
    }
}

/* conversions */

#define f_getlocal(x) rb_funcall(x, rb_intern("getlocal"), 0)
#define f_subsec(x) rb_funcall(x, rb_intern("subsec"), 0)
#define f_utc_offset(x) rb_funcall(x, rb_intern("utc_offset"), 0)
#define f_local3(x,y,m,d) rb_funcall(x, rb_intern("local"), 3, y, m, d)
#define f_utc6(x,y,m,d,h,min,s) rb_funcall(x, rb_intern("utc"), 6, y, m, d, h, min, s)

/*
 * call-seq:
 *    t.to_time
 *
 * Return a copy of self as local mode.
 */
static VALUE
time_to_time(VALUE self)
{
    return rb_funcall(self, rb_intern("getlocal"), 0);
}

/*
 * call-seq:
 *    t.to_date
 *
 * Return a Date object which denotes self.
 */
static VALUE
time_to_date(VALUE self)
{
    VALUE y, nth, ret;
    int ry, m, d;

    y = f_year(self);
    m = FIX2INT(f_mon(self));
    d = FIX2INT(f_mday(self));

    decode_year(y, -1, &nth, &ry);

    ret = d_simple_new_internal(cDate,
				nth, 0,
				GREGORIAN,
				ry, m, d,
				HAVE_CIVIL);
    {
	get_d1(ret);
	set_sg(dat, DEFAULT_SG);
    }
    return ret;
}

/*
 * call-seq:
 *    t.to_datetime
 *
 * Return a DateTime object which denotes self.
 */
static VALUE
time_to_datetime(VALUE self)
{
    VALUE y, sf, nth, ret;
    int ry, m, d, h, min, s, of;

    y = f_year(self);
    m = FIX2INT(f_mon(self));
    d = FIX2INT(f_mday(self));

    h = FIX2INT(f_hour(self));
    min = FIX2INT(f_min(self));
    s = FIX2INT(f_sec(self));
    if (s == 60)
	s = 59;

    sf = sec_to_ns(f_subsec(self));
    of = FIX2INT(f_utc_offset(self));

    decode_year(y, -1, &nth, &ry);

    ret = d_complex_new_internal(cDateTime,
				 nth, 0,
				 0, sf,
				 of, DEFAULT_SG,
				 ry, m, d,
				 h, min, s,
				 HAVE_CIVIL | HAVE_TIME);
    {
	get_d1(ret);
	set_sg(dat, DEFAULT_SG);
    }
    return ret;
}

/*
 * call-seq:
 *    d.to_time
 *
 * Return a Time object which denotes self.
 */
static VALUE
date_to_time(VALUE self)
{
    get_d1(self);

    return f_local3(rb_cTime,
		    m_real_year(dat),
		    INT2FIX(m_mon(dat)),
		    INT2FIX(m_mday(dat)));
}

/*
 * call-seq:
 *    d.to_date
 *
 * Return self;
 */
static VALUE
date_to_date(VALUE self)
{
    return self;
}

/*
 * call-seq:
 *    d.to_datetime
 *
 * Return a DateTime object which denotes self.
 */
static VALUE
date_to_datetime(VALUE self)
{
    get_d1(self);

    if (simple_dat_p(dat))
	return d_simple_new_internal(cDateTime,
				     dat->s.nth,
				     dat->s.jd,
				     dat->s.sg,
				     dat->s.year,
#ifndef USE_PACK
				     dat->s.mon,
				     dat->s.mday,
#else
				     EX_MON(dat->s.pd),
				     EX_MDAY(dat->s.pd),
#endif
				     dat->s.flags);
    else
	return d_complex_new_internal(cDateTime,
				      dat->c.nth,
				      dat->c.jd,
				      0,
				      INT2FIX(0),
				      dat->c.of,
				      dat->c.sg,
				      dat->c.year,
#ifndef USE_PACK
				      dat->c.mon,
				      dat->c.mday,
#else
				      EX_MON(dat->c.pd),
				      EX_MDAY(dat->c.pd),
#endif
				      0,
				      0,
				      0,
				      dat->c.flags | HAVE_DF | HAVE_TIME);
}

/*
 * call-seq:
 *    dt.to_time
 *
 * Return a Time object which denotes self.
 */
static VALUE
datetime_to_time(VALUE self)
{
    VALUE d, t;

    d = copy_obj_with_new_offset(self, 0);
    {
	get_d1(d);

	t = f_utc6(rb_cTime,
		   m_real_year(dat),
		   INT2FIX(m_mon(dat)),
		   INT2FIX(m_mday(dat)),
		   INT2FIX(m_hour(dat)),
		   INT2FIX(m_min(dat)),
		   f_add(INT2FIX(m_sec(dat)),
			 m_sf_in_sec(dat)));
	return f_getlocal(t);
    }
}

/*
 * call-seq:
 *    dt.to_date
 *
 * Return a Date object which denotes self.
 */
static VALUE
datetime_to_date(VALUE self)
{
    get_d1(self);

    if (simple_dat_p(dat))
	return d_simple_new_internal(cDate,
				     dat->s.nth,
				     m_local_jd(dat),
				     dat->s.sg,
				     dat->s.year,
#ifndef USE_PACK
				     dat->s.mon,
				     dat->s.mday,
#else
				     EX_MON(dat->s.pd),
				     EX_MDAY(dat->s.pd),
#endif
				     dat->s.flags);
    else
	return d_simple_new_internal(cDate,
				     dat->c.nth,
				     m_local_jd(dat),
				     dat->c.sg,
				     dat->c.year,
#ifndef USE_PACK
				     dat->c.mon,
				     dat->c.mday,
#else
				     EX_MON(dat->c.pd),
				     EX_MDAY(dat->c.pd),
#endif
				     dat->c.flags &
				     ~(HAVE_DF | HAVE_TIME | COMPLEX_DAT));
}

/*
 * call-seq:
 *    dt.to_datetime
 *
 * Return self.
 */
static VALUE
datetime_to_datetime(VALUE self)
{
    return self;
}

#ifndef NDEBUG
/* tests */

#define MIN_YEAR -4713
#define MAX_YEAR 1000000
#define MIN_JD -327
#define MAX_JD 366963925

static int
test_civil(int from, int to, double sg)
{
    int j;

    fprintf(stderr, "test_civil: %d...%d (%d) - %.0f\n",
	    from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, m, d, rj, ns;

	c_jd_to_civil(j, sg, &y, &m, &d);
	c_civil_to_jd(y, m, d, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%d != %d\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_civil(VALUE klass)
{
    if (!test_civil(MIN_JD, MIN_JD + 366, GREGORIAN))
	return Qfalse;
    if (!test_civil(2305814, 2598007, GREGORIAN))
	return Qfalse;
    if (!test_civil(MAX_JD - 366, MAX_JD, GREGORIAN))
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
test_ordinal(int from, int to, double sg)
{
    int j;

    fprintf(stderr, "test_ordinal: %d...%d (%d) - %.0f\n",
	    from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, d, rj, ns;

	c_jd_to_ordinal(j, sg, &y, &d);
	c_ordinal_to_jd(y, d, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%d != %d\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_ordinal(VALUE klass)
{
    if (!test_ordinal(MIN_JD, MIN_JD + 366, GREGORIAN))
	return Qfalse;
    if (!test_ordinal(2305814, 2598007, GREGORIAN))
	return Qfalse;
    if (!test_ordinal(MAX_JD - 366, MAX_JD, GREGORIAN))
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
test_commercial(int from, int to, double sg)
{
    int j;

    fprintf(stderr, "test_commercial: %d...%d (%d) - %.0f\n",
	    from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, w, d, rj, ns;

	c_jd_to_commercial(j, sg, &y, &w, &d);
	c_commercial_to_jd(y, w, d, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%d != %d\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_commercial(VALUE klass)
{
    if (!test_commercial(MIN_JD, MIN_JD + 366, GREGORIAN))
	return Qfalse;
    if (!test_commercial(2305814, 2598007, GREGORIAN))
	return Qfalse;
    if (!test_commercial(MAX_JD - 366, MAX_JD, GREGORIAN))
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
test_weeknum(int from, int to, int f, double sg)
{
    int j;

    fprintf(stderr, "test_weeknum: %d...%d (%d) - %.0f\n",
	    from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, w, d, rj, ns;

	c_jd_to_weeknum(j, f, sg, &y, &w, &d);
	c_weeknum_to_jd(y, w, d, f, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%d != %d\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_weeknum(VALUE klass)
{
    int f;

    for (f = 0; f <= 1; f++) {
	if (!test_weeknum(MIN_JD, MIN_JD + 366, f, GREGORIAN))
	    return Qfalse;
	if (!test_weeknum(2305814, 2598007, f, GREGORIAN))
	    return Qfalse;
	if (!test_weeknum(MAX_JD - 366, MAX_JD, f, GREGORIAN))
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
test_nth_kday(int from, int to, double sg)
{
    int j;

    fprintf(stderr, "test_nth_kday: %d...%d (%d) - %.0f\n",
	    from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	int y, m, n, k, rj, ns;

	c_jd_to_nth_kday(j, sg, &y, &m, &n, &k);
	c_nth_kday_to_jd(y, m, n, k, sg, &rj, &ns);
	if (j != rj) {
	    fprintf(stderr, "%d != %d\n", j, rj);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_nth_kday(VALUE klass)
{
    if (!test_nth_kday(MIN_JD, MIN_JD + 366, GREGORIAN))
	return Qfalse;
    if (!test_nth_kday(2305814, 2598007, GREGORIAN))
	return Qfalse;
    if (!test_nth_kday(MAX_JD - 366, MAX_JD, GREGORIAN))
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

static const char *monthnames[] = {
    NULL,
    "January", "February", "March",
    "April", "May", "June",
    "July", "August", "September",
    "October", "November", "December"
};

static const char *abbr_monthnames[] = {
    NULL,
    "Jan", "Feb", "Mar", "Apr",
    "May", "Jun", "Jul", "Aug",
    "Sep", "Oct", "Nov", "Dec"
};

static const char *daynames[] = {
    "Sunday", "Monday", "Tuesday", "Wednesday",
    "Thursday", "Friday", "Saturday"
};

static const char *abbr_daynames[] = {
    "Sun", "Mon", "Tue", "Wed",
    "Thu", "Fri", "Sat"
};

static VALUE
mk_ary_of_str(long len, const char *a[])
{
    VALUE o;
    long i;

    o = rb_ary_new2(len);
    for (i = 0; i < len; i++) {
	VALUE e;

	if (!a[i])
	    e = Qnil;
	else {
	    e = rb_str_new2(a[i]);
	    rb_obj_freeze(e);
	}
	rb_ary_push(o, e);
    }
    rb_obj_freeze(o);
    return o;
}

/*
 * date and time library
 *
 * Author: Tadayoshi Funaba 1998-2011
 *
 * Initial Documentation for bundled version of Date 2:
 *   William Webber <william@williamwebber.com>
 *
 * == Overview
 *
 * This file provides two classes for working with
 * dates and times.
 *
 * The first class, Date, represents dates.
 * It works with years, months, weeks, and days.
 * See the Date class documentation for more details.
 *
 * The second, DateTime, extends Date to include hours,
 * minutes, seconds, and fractions of a second.  It
 * provides basic support for time zones.  See the
 * DateTime class documentation for more details.
 *
 * === Ways of calculating the date.
 *
 * In common usage, the date is reckoned in years since or
 * before the Common Era (CE/BCE, also known as AD/BC), then
 * as a month and day-of-the-month within the current year.
 * This is known as the *Civil* *Date*, and abbreviated
 * as +civil+ in the Date class.
 *
 * Instead of year, month-of-the-year, and day-of-the-month,
 * the date can also be reckoned in terms of year and
 * day-of-the-year.  This is known as the *Ordinal* *Date*,
 * and is abbreviated as +ordinal+ in the Date class.  (Note
 * that referring to this as the Julian date is incorrect.)
 *
 * The date can also be reckoned in terms of year, week-of-the-year,
 * and day-of-the-week.  This is known as the *Commercial*
 * *Date*, and is abbreviated as +commercial+ in the
 * Date class.  The commercial week runs Monday (day-of-the-week
 * 1) to Sunday (day-of-the-week 7), in contrast to the civil
 * week which runs Sunday (day-of-the-week 0) to Saturday
 * (day-of-the-week 6).  The first week of the commercial year
 * starts on the Monday on or before January 1, and the commercial
 * year itself starts on this Monday, not January 1.
 *
 * For scientific purposes, it is convenient to refer to a date
 * simply as a day count, counting from an arbitrary initial
 * day.  The date first chosen for this was January 1, 4713 BCE.
 * A count of days from this date is the *Julian* *Day* *Number*
 * or *Julian* *Date*, which is abbreviated as +jd+ in the
 * Date class.  This is in local time, and counts from midnight
 * on the initial day.  The stricter usage is in UTC, and counts
 * from midday on the initial day.  This is referred to in the
 * Date class as the *Astronomical* *Julian* *Day* *Number*, and
 * abbreviated as +ajd+.  In the Date class, the Astronomical
 * Julian Day Number includes fractional days.
 *
 * Another absolute day count is the *Modified* *Julian* *Day*
 * *Number*, which takes November 17, 1858 as its initial day.
 * This is abbreviated as +mjd+ in the Date class.  There
 * is also an *Astronomical* *Modified* *Julian* *Day* *Number*,
 * which is in UTC and includes fractional days.  This is
 * abbreviated as +amjd+ in the Date class.  Like the Modified
 * Julian Day Number (and unlike the Astronomical Julian
 * Day Number), it counts from midnight.
 *
 * Alternative calendars such as the Ethiopic Solar Calendar,
 * the Islamic Lunar Calendar, or the French Revolutionary Calendar
 * are not supported by the Date class; nor are calendars that
 * are based on an Era different from the Common Era, such as
 * the Japanese Era.
 *
 * === Calendar Reform
 *
 * The standard civil year is 365 days long.  However, the
 * solar year is fractionally longer than this.  To account
 * for this, a *leap* *year* is occasionally inserted.  This
 * is a year with 366 days, the extra day falling on February 29.
 * In the early days of the civil calendar, every fourth
 * year without exception was a leap year.  This way of
 * reckoning leap years is the *Julian* *Calendar*.
 *
 * However, the solar year is marginally shorter than 365 1/4
 * days, and so the *Julian* *Calendar* gradually ran slow
 * over the centuries.  To correct this, every 100th year
 * (but not every 400th year) was excluded as a leap year.
 * This way of reckoning leap years, which we use today, is
 * the *Gregorian* *Calendar*.
 *
 * The Gregorian Calendar was introduced at different times
 * in different regions.  The day on which it was introduced
 * for a particular region is the *Day* *of* *Calendar*
 * *Reform* for that region.  This is abbreviated as +start+
 * (for Start of Gregorian calendar) in the Date class.
 *
 * Two such days are of particular
 * significance.  The first is October 15, 1582, which was
 * the Day of Calendar Reform for Italy and most Catholic
 * countries.  The second is September 14, 1752, which was
 * the Day of Calendar Reform for England and its colonies
 * (including what is now the United States).  These two
 * dates are available as the constants Date::ITALY and
 * Date::ENGLAND, respectively.  (By comparison, Germany and
 * Holland, less Catholic than Italy but less stubborn than
 * England, changed over in 1698; Sweden in 1753; Russia not
 * till 1918, after the Revolution; and Greece in 1923.  Many
 * Orthodox churches still use the Julian Calendar.  A complete
 * list of Days of Calendar Reform can be found at
 * http://www.polysyllabic.com/GregConv.html.)
 *
 * Switching from the Julian to the Gregorian calendar
 * involved skipping a number of days to make up for the
 * accumulated lag, and the later the switch was (or is)
 * done, the more days need to be skipped.  So in 1582 in Italy,
 * 4th October was followed by 15th October, skipping 10 days; in 1752
 * in England, 2nd September was followed by 14th September, skipping
 * 11 days; and if I decided to switch from Julian to Gregorian
 * Calendar this midnight, I would go from 27th July 2003 (Julian)
 * today to 10th August 2003 (Gregorian) tomorrow, skipping
 * 13 days.  The Date class is aware of this gap, and a supposed
 * date that would fall in the middle of it is regarded as invalid.
 *
 * The Day of Calendar Reform is relevant to all date representations
 * involving years.  It is not relevant to the Julian Day Numbers,
 * except for converting between them and year-based representations.
 *
 * In the Date and DateTime classes, the Day of Calendar Reform or
 * +start+ can be specified a number of ways.  First, it can be as
 * the Julian Day Number of the Day of Calendar Reform.  Second,
 * it can be using the constants Date::ITALY or Date::ENGLAND; these
 * are in fact the Julian Day Numbers of the Day of Calendar Reform
 * of the respective regions.  Third, it can be as the constant
 * Date::JULIAN, which means to always use the Julian Calendar.
 * Finally, it can be as the constant Date::GREGORIAN, which means
 * to always use the Gregorian Calendar.
 *
 * Note: in the Julian Calendar, New Years Day was March 25.  The
 * Date class does not follow this convention.
 *
 * === Offsets
 *
 * DateTime objects support a simple representation
 * of offsets.  Offsets are represented as an offset
 * from UTC (UTC is not identical GMT; GMT is a historical term),
 * as a fraction of a day.  This offset is the
 * how much local time is later (or earlier) than UTC.
 * As you travel east, the offset increases until you
 * reach the dateline in the middle of the Pacific Ocean;
 * as you travel west, the offset decreases.  This offset
 * is abbreviated as +offset+ in the Date class.
 *
 * This simple representation of offsets does not take
 * into account the common practice of Daylight Savings
 * Time or Summer Time.
 *
 * Most DateTime methods return the date and the
 * time in local time.  The two exceptions are
 * #ajd() and #amjd(), which return the date and time
 * in UTC time, including fractional days.
 *
 * The Date class does not support offsets, in that
 * there is no way to create a Date object with non-utc offset.
 *
 * == Examples of use
 *
 * === Print out the date of every Sunday between two dates.
 *
 *     def print_sundays(d1, d2)
 *         d1 += 1 until d1.sunday?
 *         d1.step(d2, 7) do |d|
 *             puts d.strftime('%B %-d')
 *         end
 *     end
 *
 *     print_sundays(Date.new(2003, 4, 8), Date.new(2003, 5, 23))
 */
void
Init_date_core(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    assert(fprintf(stderr, "assert() is now active\n"));

    id_cmp = rb_intern("<=>");
    id_le_p = rb_intern("<=");
    id_ge_p = rb_intern(">=");
    id_eqeq_p = rb_intern("==");

    half_days_in_day = rb_rational_new2(INT2FIX(1), INT2FIX(2));
    unix_epoch_in_ajd =  rb_rational_new2(INT2FIX(4881175), INT2FIX(2));

#if (LONG_MAX / DAY_IN_SECONDS) > SECOND_IN_NANOSECONDS
    day_in_nanoseconds = LONG2NUM((long)DAY_IN_SECONDS *
				  SECOND_IN_NANOSECONDS);
#elif defined HAVE_LONG_LONG
    day_in_nanoseconds = LL2NUM((LONG_LONG)DAY_IN_SECONDS *
				SECOND_IN_NANOSECONDS);
#else
    day_in_nanoseconds = f_mul(INT2FIX(DAY_IN_SECONDS),
			       INT2FIX(SECOND_IN_NANOSECONDS));
#endif

    rb_gc_register_mark_object(half_days_in_day);
    rb_gc_register_mark_object(unix_epoch_in_ajd);
    rb_gc_register_mark_object(day_in_nanoseconds);

    positive_inf = NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY")));
    negative_inf = -positive_inf;

    /*
     * Class representing a date.
     *
     * A new Date object is created using one of the object creation
     * class methods named after the corresponding date format, and the
     * arguments appropriate to that date format; for instance,
     * Date::civil() (aliased to Date::new()) with year, month,
     * and day-of-month, or Date::ordinal() with year and day-of-year.
     * All of these object creation class methods also take the
     * Day of Calendar Reform as an optional argument.
     *
     * Date objects are immutable once created.
     *
     * Once a Date has been created, date values
     * can be retrieved for the different date formats supported
     * using instance methods.  For instance, #mon() gives the
     * Civil month, #cwday() gives the Commercial day of the week,
     * and #yday() gives the Ordinal day of the year.  Date values
     * can be retrieved in any format, regardless of what format
     * was used to create the Date instance.
     *
     * The Date class includes the Comparable module, allowing
     * date objects to be compared and sorted, ranges of dates
     * to be created, and so forth.
     */
    cDate = rb_define_class("Date", rb_cObject);

    rb_include_module(cDate, rb_mComparable);

    /*
     * Full month names, in English.  Months count from 1 to 12; a
     * month's numerical representation indexed into this array
     * gives the name of that month (hence the first element is nil).
     */
    rb_define_const(cDate, "MONTHNAMES", mk_ary_of_str(13, monthnames));

    /* Abbreviated month names, in English.  */
    rb_define_const(cDate, "ABBR_MONTHNAMES",
		    mk_ary_of_str(13, abbr_monthnames));

    /*
     * Full names of days of the week, in English.  Days of the week
     * count from 0 to 6 (except in the commercial week); a day's numerical
     * representation indexed into this array gives the name of that day.
     */
    rb_define_const(cDate, "DAYNAMES", mk_ary_of_str(7, daynames));

    /* Abbreviated day names, in English.  */
    rb_define_const(cDate, "ABBR_DAYNAMES", mk_ary_of_str(7, abbr_daynames));

    /* The Julian Day Number of the Day of Calendar Reform for Italy
     * and the Catholic countries.
     */
    rb_define_const(cDate, "ITALY", INT2FIX(ITALY));

    /* The Julian Day Number of the Day of Calendar Reform for England
     * and her Colonies.
     */
    rb_define_const(cDate, "ENGLAND", INT2FIX(ENGLAND));
    /* A constant used to indicate that a Date should always use the
     * Julian calendar.
     */
    rb_define_const(cDate, "JULIAN", DBL2NUM(JULIAN));
    /* A constant used to indicate that a Date should always use the
     * Gregorian calendar.
     */
    rb_define_const(cDate, "GREGORIAN", DBL2NUM(GREGORIAN));

    rb_define_alloc_func(cDate, d_lite_s_alloc);

#ifndef NDEBUG
    rb_define_private_method(CLASS_OF(cDate), "_valid_jd?",
			     date_s__valid_jd_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "_valid_ordinal?",
			     date_s__valid_ordinal_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "_valid_civil?",
			     date_s__valid_civil_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "_valid_date?",
			     date_s__valid_civil_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "_valid_commercial?",
			     date_s__valid_commercial_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "_valid_weeknum?",
			     date_s__valid_weeknum_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "_valid_nth_kday?",
			     date_s__valid_nth_kday_p, -1);
#endif

    rb_define_singleton_method(cDate, "valid_jd?", date_s_valid_jd_p, -1);
    rb_define_singleton_method(cDate, "valid_ordinal?",
			       date_s_valid_ordinal_p, -1);
    rb_define_singleton_method(cDate, "valid_civil?", date_s_valid_civil_p, -1);
    rb_define_singleton_method(cDate, "valid_date?", date_s_valid_civil_p, -1);
    rb_define_singleton_method(cDate, "valid_commercial?",
			       date_s_valid_commercial_p, -1);

#ifndef NDEBUG
    rb_define_private_method(CLASS_OF(cDate), "valid_weeknum?",
			     date_s_valid_weeknum_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "valid_nth_kday?",
			     date_s_valid_nth_kday_p, -1);
    rb_define_private_method(CLASS_OF(cDate), "zone_to_diff",
			     date_s_zone_to_diff, 1);
#endif

    rb_define_singleton_method(cDate, "julian_leap?", date_s_julian_leap_p, 1);
    rb_define_singleton_method(cDate, "gregorian_leap?",
			       date_s_gregorian_leap_p, 1);
    rb_define_singleton_method(cDate, "leap?",
			       date_s_gregorian_leap_p, 1);

#ifndef NDEBUG
    rb_define_singleton_method(cDate, "new!", date_s_new_bang, -1);
#endif

    rb_define_singleton_method(cDate, "jd", date_s_jd, -1);
    rb_define_singleton_method(cDate, "ordinal", date_s_ordinal, -1);
    rb_define_singleton_method(cDate, "civil", date_s_civil, -1);
    rb_define_singleton_method(cDate, "new", date_s_civil, -1);
    rb_define_singleton_method(cDate, "commercial", date_s_commercial, -1);

#ifndef NDEBUG
    rb_define_singleton_method(cDate, "weeknum", date_s_weeknum, -1);
    rb_define_singleton_method(cDate, "nth_kday", date_s_nth_kday, -1);
#endif

    rb_define_singleton_method(cDate, "today", date_s_today, -1);
    rb_define_singleton_method(cDate, "_strptime", date_s__strptime, -1);
    rb_define_singleton_method(cDate, "strptime", date_s_strptime, -1);
    rb_define_singleton_method(cDate, "_parse", date_s__parse, -1);
    rb_define_singleton_method(cDate, "parse", date_s_parse, -1);
    rb_define_singleton_method(cDate, "_iso8601", date_s__iso8601, 1);
    rb_define_singleton_method(cDate, "iso8601", date_s_iso8601, -1);
    rb_define_singleton_method(cDate, "_rfc3339", date_s__rfc3339, 1);
    rb_define_singleton_method(cDate, "rfc3339", date_s_rfc3339, -1);
    rb_define_singleton_method(cDate, "_xmlschema", date_s__xmlschema, 1);
    rb_define_singleton_method(cDate, "xmlschema", date_s_xmlschema, -1);
    rb_define_singleton_method(cDate, "_rfc2822", date_s__rfc2822, 1);
    rb_define_singleton_method(cDate, "_rfc822", date_s__rfc2822, 1);
    rb_define_singleton_method(cDate, "rfc2822", date_s_rfc2822, -1);
    rb_define_singleton_method(cDate, "rfc822", date_s_rfc2822, -1);
    rb_define_singleton_method(cDate, "_httpdate", date_s__httpdate, 1);
    rb_define_singleton_method(cDate, "httpdate", date_s_httpdate, -1);
    rb_define_singleton_method(cDate, "_jisx0301", date_s__jisx0301, 1);
    rb_define_singleton_method(cDate, "jisx0301", date_s_jisx0301, -1);

#ifndef NDEBUG
    rb_define_method(cDate, "fill", d_lite_fill, 0);
#endif

    rb_define_method(cDate, "initialize_copy", d_lite_initialize_copy, 1);

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

    rb_define_method(cDate, "sunday?", d_lite_sunday_p, 0);
    rb_define_method(cDate, "monday?", d_lite_monday_p, 0);
    rb_define_method(cDate, "tuesday?", d_lite_tuesday_p, 0);
    rb_define_method(cDate, "wednesday?", d_lite_wednesday_p, 0);
    rb_define_method(cDate, "thursday?", d_lite_thursday_p, 0);
    rb_define_method(cDate, "friday?", d_lite_friday_p, 0);
    rb_define_method(cDate, "saturday?", d_lite_saturday_p, 0);

#ifndef NDEBUG
    rb_define_method(cDate, "nth_kday?", generic_nth_kday_p, 2);
#endif

    rb_define_method(cDate, "julian?", d_lite_julian_p, 0);
    rb_define_method(cDate, "gregorian?", d_lite_gregorian_p, 0);
    rb_define_method(cDate, "leap?", d_lite_leap_p, 0);

    rb_define_method(cDate, "start", d_lite_start, 0);
    rb_define_method(cDate, "new_start", d_lite_new_start, -1);
    rb_define_method(cDate, "italy", d_lite_italy, 0);
    rb_define_method(cDate, "england", d_lite_england, 0);
    rb_define_method(cDate, "julian", d_lite_julian, 0);
    rb_define_method(cDate, "gregorian", d_lite_gregorian, 0);

    rb_define_private_method(cDate, "new_offset", d_lite_new_offset, -1);

    rb_define_method(cDate, "+", d_lite_plus, 1);
    rb_define_method(cDate, "-", d_lite_minus, 1);

    rb_define_method(cDate, "next_day", d_lite_next_day, -1);
    rb_define_method(cDate, "prev_day", d_lite_prev_day, -1);
    rb_define_method(cDate, "next", d_lite_next, 0);
    rb_define_method(cDate, "succ", d_lite_next, 0);

    rb_define_method(cDate, ">>", d_lite_rshift, 1);
    rb_define_method(cDate, "<<", d_lite_lshift, 1);

    rb_define_method(cDate, "next_month", d_lite_next_month, -1);
    rb_define_method(cDate, "prev_month", d_lite_prev_month, -1);
    rb_define_method(cDate, "next_year", d_lite_next_year, -1);
    rb_define_method(cDate, "prev_year", d_lite_prev_year, -1);

    rb_define_method(cDate, "step", generic_step, -1);
    rb_define_method(cDate, "upto", generic_upto, 1);
    rb_define_method(cDate, "downto", generic_downto, 1);

    rb_define_method(cDate, "<=>", d_lite_cmp, 1);
    rb_define_method(cDate, "===", d_lite_equal, 1);
    rb_define_method(cDate, "eql?", d_lite_eql_p, 1);
    rb_define_method(cDate, "hash", d_lite_hash, 0);

    rb_define_method(cDate, "to_s", d_lite_to_s, 0);
    rb_define_method(cDate, "inspect", d_lite_inspect, 0);

    rb_define_method(cDate, "strftime", d_lite_strftime, -1);

    rb_define_method(cDate, "asctime", d_lite_asctime, 0);
    rb_define_method(cDate, "ctime", d_lite_asctime, 0);
    rb_define_method(cDate, "iso8601", d_lite_iso8601, 0);
    rb_define_method(cDate, "xmlschema", d_lite_iso8601, 0);
    rb_define_method(cDate, "rfc3339", d_lite_rfc3339, 0);
    rb_define_method(cDate, "rfc2822", d_lite_rfc2822, 0);
    rb_define_method(cDate, "rfc822", d_lite_rfc2822, 0);
    rb_define_method(cDate, "httpdate", d_lite_httpdate, 0);
    rb_define_method(cDate, "jisx0301", d_lite_jisx0301, 0);

    rb_define_method(cDate, "marshal_dump", d_lite_marshal_dump, 0);
    rb_define_method(cDate, "marshal_load", d_lite_marshal_load, 1);

    /* datetime */

    cDateTime = rb_define_class("DateTime", cDate);

    rb_undef_method(CLASS_OF(cDateTime), "today");

    rb_define_singleton_method(cDateTime, "jd", datetime_s_jd, -1);
    rb_define_singleton_method(cDateTime, "ordinal", datetime_s_ordinal, -1);
    rb_define_singleton_method(cDateTime, "civil", datetime_s_civil, -1);
    rb_define_singleton_method(cDateTime, "new", datetime_s_civil, -1);
    rb_define_singleton_method(cDateTime, "commercial",
			       datetime_s_commercial, -1);

#ifndef NDEBUG
    rb_define_singleton_method(cDateTime, "weeknum",
			       datetime_s_weeknum, -1);
    rb_define_singleton_method(cDateTime, "nth_kday",
			       datetime_s_nth_kday, -1);
#endif

    rb_define_singleton_method(cDateTime, "now", datetime_s_now, -1);
    rb_define_singleton_method(cDateTime, "_strptime",
			       datetime_s__strptime, -1);
    rb_define_singleton_method(cDateTime, "strptime",
			       datetime_s_strptime, -1);
    rb_define_singleton_method(cDateTime, "parse",
			       datetime_s_parse, -1);
    rb_define_singleton_method(cDateTime, "iso8601",
			       datetime_s_iso8601, -1);
    rb_define_singleton_method(cDateTime, "rfc3339",
			       datetime_s_rfc3339, -1);
    rb_define_singleton_method(cDateTime, "xmlschema",
			       datetime_s_xmlschema, -1);
    rb_define_singleton_method(cDateTime, "rfc2822",
			       datetime_s_rfc2822, -1);
    rb_define_singleton_method(cDateTime, "rfc822",
			       datetime_s_rfc2822, -1);
    rb_define_singleton_method(cDateTime, "httpdate",
			       datetime_s_httpdate, -1);
    rb_define_singleton_method(cDateTime, "jisx0301",
			       datetime_s_jisx0301, -1);

#define f_public(m,s) rb_funcall(m, rb_intern("public"), 1,\
				 ID2SYM(rb_intern(s)))

    f_public(cDateTime, "hour");
    f_public(cDateTime, "min");
    f_public(cDateTime, "minute");
    f_public(cDateTime, "sec");
    f_public(cDateTime, "second");
    f_public(cDateTime, "sec_fraction");
    f_public(cDateTime, "second_fraction");
    f_public(cDateTime, "offset");
    f_public(cDateTime, "zone");
    f_public(cDateTime, "new_offset");

    rb_define_method(cDateTime, "to_s", dt_lite_to_s, 0);

    rb_define_method(cDateTime, "strftime", dt_lite_strftime, -1);

    rb_define_method(cDateTime, "iso8601", dt_lite_iso8601, -1);
    rb_define_method(cDateTime, "xmlschema", dt_lite_iso8601, -1);
    rb_define_method(cDateTime, "rfc3339", dt_lite_rfc3339, -1);
    rb_define_method(cDateTime, "jisx0301", dt_lite_jisx0301, -1);

    /* conversions */

    rb_define_method(rb_cTime, "to_time", time_to_time, 0);
    rb_define_method(rb_cTime, "to_date", time_to_date, 0);
    rb_define_method(rb_cTime, "to_datetime", time_to_datetime, 0);

    rb_define_method(cDate, "to_time", date_to_time, 0);
    rb_define_method(cDate, "to_date", date_to_date, 0);
    rb_define_method(cDate, "to_datetime", date_to_datetime, 0);

    rb_define_method(cDateTime, "to_time", datetime_to_time, 0);
    rb_define_method(cDateTime, "to_date", datetime_to_date, 0);
    rb_define_method(cDateTime, "to_datetime", datetime_to_datetime, 0);

#ifndef NDEBUG
    /* tests */

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
