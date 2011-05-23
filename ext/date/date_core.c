/*
  date_core.c: Coded by Tadayoshi Funaba 2010, 2011
*/

#include "ruby.h"
#include "ruby/encoding.h"
#include <math.h>
#include <time.h>

#define NDEBUG
#include <assert.h>

/* #define FORCE_RIGHT */

#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif

#define LIGHT_MODE   (1 << 0)
#define HAVE_JD      (1 << 1)
#define HAVE_DF      (1 << 2)
#define HAVE_CIVIL   (1 << 3)
#define HAVE_TIME    (1 << 4)
#define DATETIME_OBJ (1 << 7)

#define light_mode_p(x) ((x)->flags & LIGHT_MODE)
#define have_jd_p(x) ((x)->flags & HAVE_JD)
#define have_df_p(x) ((x)->flags & HAVE_DF)
#define have_civil_p(x) ((x)->flags & HAVE_CIVIL)
#define have_time_p(x) ((x)->flags & HAVE_TIME)
#define datetime_obj_p(x) ((x)->flags & DATETIME_OBJ)
#define date_obj_p(x) (!datetime_obj_p(x))

#define MIN_YEAR -4713
#define MAX_YEAR 1000000
#define MIN_JD -327
#define MAX_JD 366963925

#define LIGHTABLE_JD(j) (j >= MIN_JD && j <= MAX_JD)
#define LIGHTABLE_YEAR(y) (y >= MIN_YEAR && y <= MAX_YEAR)
#define LIGHTABLE_CWYEAR(y) LIGHTABLE_YEAR(y)

#define ITALY 2299161
#define ENGLAND 2361222
#define JULIAN (NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY"))))
#define GREGORIAN (-NUM2DBL(rb_const_get(rb_cFloat, rb_intern("INFINITY"))))

#define MINUTE_IN_SECONDS 60
#define HOUR_IN_SECONDS 3600
#define DAY_IN_SECONDS 86400
#define SECOND_IN_NANOSECONDS 1000000000

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
    Data_Get_Struct(x, union DateData, dat);\
    assert(date_obj_p(dat))

#define get_d2(x,y)\
    union DateData *adat, *bdat;\
    Data_Get_Struct(x, union DateData, adat);\
    Data_Get_Struct(y, union DateData, bdat);\
    assert(date_obj_p(adat));\
    assert(date_obj_p(bdat))

#define get_d1_dt1(x,y)\
    union DateData *adat;\
    union DateTimeData *bdat;\
    Data_Get_Struct(x, union DateData, adat);\
    Data_Get_Struct(y, union DateTimeData, bdat)\
    assert(date_obj_p(adat));\
    assert(datetime_obj_p(bdat))

#define get_dt1(x)\
    union DateTimeData *dat;\
    Data_Get_Struct(x, union DateTimeData, dat);\
    assert(datetime_obj_p(dat))

#define get_dt2(x,y)\
    union DateTimeData *adat, *bdat;\
    Data_Get_Struct(x, union DateTimeData, adat);\
    Data_Get_Struct(y, union DateTimeData, bdat);\
    assert(datetime_obj_p(adat));\
    assert(datetime_obj_p(bdat))

#define get_dt1_d1(x,y)\
    union DateTimeData *adat;\
    union DateData *bdat;\
    Data_Get_Struct(x, union DateTimeData, adat);\
    Data_Get_Struct(y, union DateData, bdat);\
    assert(datetime_obj_p(adat));\
    assert(date_obj_p(bdat))

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
	abuf.flags = HAVE_DF | HAVE_TIME | DATETIME_OBJ | atmp->l.flags;\
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
	bbuf.flags = HAVE_DF | HAVE_TIME | DATETIME_OBJ | btmp->l.flags;\
	bdat = &bbuf;\
    }

#define f_abs(x) rb_funcall(x, rb_intern("abs"), 0)
#define f_negate(x) rb_funcall(x, rb_intern("-@"), 0)
#define f_add(x,y) rb_funcall(x, '+', 1, y)
#define f_sub(x,y) rb_funcall(x, '-', 1, y)
#define f_mul(x,y) rb_funcall(x, '*', 1, y)
#define f_div(x,y) rb_funcall(x, '/', 1, y)
#define f_idiv(x,y) rb_funcall(x, rb_intern("div"), 1, y)
#define f_mod(x,y) rb_funcall(x, '%', 1, y)
#define f_remainder(x,y) rb_funcall(x, rb_intern("remainder"), 1, y)
#define f_expt(x,y) rb_funcall(x, rb_intern("**"), 1, y)
#define f_floor(x) rb_funcall(x, rb_intern("floor"), 0)
#define f_ceil(x) rb_funcall(x, rb_intern("ceil"), 0)
#define f_truncate(x) rb_funcall(x, rb_intern("truncate"), 0)
#define f_round(x) rb_funcall(x, rb_intern("round"), 0)

#define f_add3(x,y,z) f_add(f_add(x, y), z)
#define f_sub3(x,y,z) f_sub(f_sub(x, y), z)

#define f_cmp(x,y) rb_funcall(x, rb_intern("<=>"), 1, y)
#define f_lt_p(x,y) rb_funcall(x, '<', 1, y)
#define f_gt_p(x,y) rb_funcall(x, '>', 1, y)
#define f_le_p(x,y) rb_funcall(x, rb_intern("<="), 1, y)
#define f_ge_p(x,y) rb_funcall(x, rb_intern(">="), 1, y)

#define f_eqeq_p(x,y) rb_funcall(x, rb_intern("=="), 1, y)
#define f_equal_p(x,y) rb_funcall(x, rb_intern("==="), 1, y)
#define f_zero_p(x) rb_funcall(x, rb_intern("zero?"), 0)
#define f_negative_p(x) f_lt_p(x, INT2FIX(0))
#define f_positive_p(x) (!f_negative_p(x))

#define f_compact(x) rb_funcall(x, rb_intern("compact"), 0)

#define f_ajd(x) rb_funcall(x, rb_intern("ajd"), 0)
#define f_jd(x) rb_funcall(x, rb_intern("jd"), 0)
#define f_year(x) rb_funcall(x, rb_intern("year"), 0)
#define f_mon(x) rb_funcall(x, rb_intern("mon"), 0)
#define f_mday(x) rb_funcall(x, rb_intern("mday"), 0)
#define f_wday(x) rb_funcall(x, rb_intern("wday"), 0)
#define f_hour(x) rb_funcall(x, rb_intern("hour"), 0)
#define f_min(x) rb_funcall(x, rb_intern("min"), 0)
#define f_sec(x) rb_funcall(x, rb_intern("sec"), 0)
#define f_start(x) rb_funcall(x, rb_intern("start"), 0)

static VALUE cDate, cDateTime;
static VALUE rzero, rhalf, day_in_nanoseconds;

/* right base */

#define HALF_DAYS_IN_DAY       rb_rational_new2(INT2FIX(1), INT2FIX(2))
#define HOURS_IN_DAY           rb_rational_new2(INT2FIX(1), INT2FIX(24))
#define MINUTES_IN_DAY         rb_rational_new2(INT2FIX(1), INT2FIX(1440))
#define SECONDS_IN_DAY         rb_rational_new2(INT2FIX(1), INT2FIX(86400))
#define MILLISECONDS_IN_DAY\
    rb_rational_new2(INT2FIX(1), f_mul(INT2FIX(86400), INT2FIX(1000)))
#define NANOSECONDS_IN_DAY\
    rb_rational_new2(INT2FIX(1), f_mul(INT2FIX(86400), INT2FIX(1000000000)))
#define MILLISECONDS_IN_SECOND rb_rational_new2(INT2FIX(1), INT2FIX(1000))
#define NANOSECONDS_IN_SECOND  rb_rational_new2(INT2FIX(1), INT2FIX(1000000000))

#define MJD_EPOCH_IN_AJD\
    rb_rational_new2(INT2FIX(4800001), INT2FIX(2)) /* 1858-11-17 */
#define UNIX_EPOCH_IN_AJD\
    rb_rational_new2(INT2FIX(4881175), INT2FIX(2)) /* 1970-01-01 */
#define MJD_EPOCH_IN_CJD       INT2FIX(2400001)
#define UNIX_EPOCH_IN_CJD      INT2FIX(2440588)
#define LD_EPOCH_IN_CJD        INT2FIX(2299160)

static VALUE rt__valid_civil_p(VALUE, VALUE, VALUE, VALUE);

static VALUE
rt_find_fdoy(VALUE y, VALUE sg)
{
    int d;

    for (d = 1; d < 31; d++) {
	VALUE j = rt__valid_civil_p(y, INT2FIX(1), INT2FIX(d), sg);
	if (!NIL_P(j))
	    return j;
    }
    return Qnil;
}

static VALUE
rt_find_ldoy(VALUE y, VALUE sg)
{
    int i;

    for (i = 0; i < 30; i++) {
	VALUE j = rt__valid_civil_p(y, INT2FIX(12), INT2FIX(31 - i), sg);
	if (!NIL_P(j))
	    return j;
    }
    return Qnil;
}

#ifndef NDEBUG
static VALUE
rt_find_fdom(VALUE y, VALUE m, VALUE sg)
{
    int d;

    for (d = 1; d < 31; d++) {
	VALUE j = rt__valid_civil_p(y, m, INT2FIX(d), sg);
	if (!NIL_P(j))
	    return j;
    }
    return Qnil;
}
#endif

static VALUE
rt_find_ldom(VALUE y, VALUE m, VALUE sg)
{
    int i;

    for (i = 0; i < 30; i++) {
	VALUE j = rt__valid_civil_p(y, m, INT2FIX(31 - i), sg);
	if (!NIL_P(j))
	    return j;
    }
    return Qnil;
}

static VALUE
rt_ordinal_to_jd(VALUE y, VALUE d, VALUE sg)
{
    return f_sub(f_add(rt_find_fdoy(y, sg), d), INT2FIX(1));
}

static VALUE rt_jd_to_civil(VALUE jd, VALUE sg);

static VALUE
rt_jd_to_ordinal(VALUE jd, VALUE sg)
{
    VALUE a, y, j, doy;

    a = rt_jd_to_civil(jd, sg);
    y = RARRAY_PTR(a)[0];
    j = rt_find_fdoy(y, sg);
    doy = f_add(f_sub(jd, j), INT2FIX(1));
    return rb_assoc_new(y, doy);
}

static VALUE
rt_civil_to_jd(VALUE y, VALUE m, VALUE d, VALUE sg)
{
    VALUE a, b, jd;

    if (f_le_p(m, INT2FIX(2))) {
	y = f_sub(y, INT2FIX(1));
	m = f_add(m, INT2FIX(12));
    }
    a = f_floor(f_div(y, DBL2NUM(100.0)));
    b = f_add(f_sub(INT2FIX(2), a), f_floor(f_div(a, DBL2NUM(4.0))));
    jd = f_add3(f_floor(f_mul(DBL2NUM(365.25), f_add(y, INT2FIX(4716)))),
		f_floor(f_mul(DBL2NUM(30.6001), f_add(m, INT2FIX(1)))),
		f_sub(f_add(d, b), INT2FIX(1524)));
    if (f_lt_p(jd, sg))
	jd = f_sub(jd, b);
    return jd;
}

static VALUE
rt_jd_to_civil(VALUE jd, VALUE sg)
{
    VALUE a, x, b, c, d, e, dom, m, y;

    if (f_lt_p(jd, sg))
	a = jd;
    else {
	x = f_floor(f_div(f_sub(jd, DBL2NUM(1867216.25)), DBL2NUM(36524.25)));
	a = f_sub(f_add3(jd, INT2FIX(1), x), f_floor(f_div(x, DBL2NUM(4.0))));
    }
    b = f_add(a, INT2FIX(1524));
    c = f_floor(f_div(f_sub(b, DBL2NUM(122.1)), DBL2NUM(365.25)));
    d = f_floor(f_mul(DBL2NUM(365.25), c));
    e = f_floor(f_div(f_sub(b, d), DBL2NUM(30.6001)));
    dom = f_sub3(b, d, f_floor(f_mul(DBL2NUM(30.6001), e)));
    if (f_le_p(e, INT2FIX(13))) {
	m = f_sub(e, INT2FIX(1));
	y = f_sub(c, INT2FIX(4716));
    }
    else {
	m = f_sub(e, INT2FIX(13));
	y = f_sub(c, INT2FIX(4715));
    }
    return rb_ary_new3(3, y, m, dom);
}

static VALUE
rt_commercial_to_jd(VALUE y, VALUE w, VALUE d, VALUE sg)
{
    VALUE j;

    j = f_add(rt_find_fdoy(y, sg), INT2FIX(3));
    return f_add3(f_sub(j, f_mod(j, INT2FIX(7))),
		  f_mul(INT2FIX(7), f_sub(w, INT2FIX(1))),
		  f_sub(d, INT2FIX(1)));
}

static VALUE
rt_jd_to_commercial(VALUE jd, VALUE sg)
{
    VALUE t, a, j, y, w, d;

    t = rt_jd_to_civil(f_sub(jd, INT2FIX(3)), sg);
    a = RARRAY_PTR(t)[0];
    j = rt_commercial_to_jd(f_add(a, INT2FIX(1)), INT2FIX(1), INT2FIX(1), sg);
    if (f_ge_p(jd, j))
	y = f_add(a, INT2FIX(1));
    else {
	j = rt_commercial_to_jd(a, INT2FIX(1), INT2FIX(1), sg);
	y = a;
    }
    w = f_add(INT2FIX(1), f_idiv(f_sub(jd, j), INT2FIX(7)));
    d = f_mod(f_add(jd, INT2FIX(1)), INT2FIX(7));
    if (f_zero_p(d))
	d = INT2FIX(7);
    return rb_ary_new3(3, y, w, d);
}

static VALUE
rt_weeknum_to_jd(VALUE y, VALUE w, VALUE d, VALUE f, VALUE sg)
{
    VALUE a;

    a = f_add(rt_find_fdoy(y, sg), INT2FIX(6));
    return f_add3(f_sub3(a,
			 f_mod(f_add(f_sub(a, f), INT2FIX(1)), INT2FIX(7)),
			 INT2FIX(7)),
		  f_mul(INT2FIX(7), w),
		  d);
}

static VALUE
rt_jd_to_weeknum(VALUE jd, VALUE f, VALUE sg)
{
    VALUE t, y, d, a, w;

    t = rt_jd_to_civil(jd, sg);
    y = RARRAY_PTR(t)[0];
    d = RARRAY_PTR(t)[2];
    a = f_add(rt_find_fdoy(y, sg), INT2FIX(6));
    t = f_add(f_sub(jd,
		    f_sub(a, f_mod(f_add(f_sub(a, f), INT2FIX(1)),
				   INT2FIX(7)))),
	      INT2FIX(7));
    w = f_idiv(t, INT2FIX(7));
    d = f_mod(t, INT2FIX(7));
    return rb_ary_new3(3, y, w, d);
}

#ifndef NDEBUG
static VALUE
rt_nth_kday_to_jd(VALUE y, VALUE m, VALUE n, VALUE k, VALUE sg)
{
    VALUE j;

    if (f_gt_p(n, INT2FIX(0)))
	j = f_sub(rt_find_fdom(y, m, sg), INT2FIX(1));
    else
	j = f_add(rt_find_ldom(y, m, sg), INT2FIX(7));
    return f_add(f_sub(j,
		       f_mod(f_add(f_sub(j, k), INT2FIX(1)), INT2FIX(7))),
		 f_mul(INT2FIX(7), n));
}

static VALUE rt_jd_to_wday(VALUE);

static VALUE
rt_jd_to_nth_kday(VALUE jd, VALUE sg)
{
    VALUE t, y, m, n, k, j;

    t = rt_jd_to_civil(jd, sg);
    y = RARRAY_PTR(t)[0];
    m = RARRAY_PTR(t)[1];
    j = rt_find_fdom(y, m, sg);
    n = f_add(f_idiv(f_sub(jd, j), INT2FIX(7)), INT2FIX(1));
    k = rt_jd_to_wday(jd);
    return rb_ary_new3(4, y, m, n, k);
}
#endif

static VALUE
rt_ajd_to_jd(VALUE ajd, VALUE of)
{
    VALUE t, jd, fr;

    t = f_add3(ajd, of, HALF_DAYS_IN_DAY);
    jd = f_idiv(t, INT2FIX(1));
    fr = f_mod(t, INT2FIX(1));
    return rb_assoc_new(jd, fr);
}

static VALUE
rt_jd_to_ajd(VALUE jd, VALUE fr, VALUE of)
{
    return f_sub3(f_add(jd, fr), of, HALF_DAYS_IN_DAY);
}

#ifndef NDEBUG
static VALUE
rt_day_fraction_to_time(VALUE fr)
{
    VALUE h, min, s, ss;

    ss = f_idiv(fr, SECONDS_IN_DAY);
    fr = f_mod(fr, SECONDS_IN_DAY);

    h = f_idiv(ss, INT2FIX(HOUR_IN_SECONDS));
    ss = f_mod(ss, INT2FIX(HOUR_IN_SECONDS));

    min = f_idiv(ss, INT2FIX(MINUTE_IN_SECONDS));
    s = f_mod(ss, INT2FIX(MINUTE_IN_SECONDS));

    return rb_ary_new3(4, h, min, s, f_mul(fr, INT2FIX(DAY_IN_SECONDS)));
}
#endif

static VALUE
rt_day_fraction_to_time_wo_sf(VALUE fr)
{
    VALUE h, min, s, ss;

    ss = f_idiv(fr, SECONDS_IN_DAY);

    h = f_idiv(ss, INT2FIX(HOUR_IN_SECONDS));
    ss = f_mod(ss, INT2FIX(HOUR_IN_SECONDS));

    min = f_idiv(ss, INT2FIX(MINUTE_IN_SECONDS));
    s = f_mod(ss, INT2FIX(MINUTE_IN_SECONDS));

    return rb_ary_new3(3, h, min, s);
}

static VALUE
rt_time_to_day_fraction(VALUE h, VALUE min, VALUE s)
{
    return rb_Rational(f_add3(f_mul(h, INT2FIX(HOUR_IN_SECONDS)),
			      f_mul(min, INT2FIX(MINUTE_IN_SECONDS)),
			      s),
		       INT2FIX(DAY_IN_SECONDS));
}

#ifndef NDEBUG
static VALUE
rt_amjd_to_ajd(VALUE amjd)
{
    return f_add(amjd, MJD_EPOCH_IN_AJD);
}
#endif

static VALUE
rt_ajd_to_amjd(VALUE ajd)
{
    return f_sub(ajd, MJD_EPOCH_IN_AJD);
}

#ifndef NDEBUG
static VALUE
rt_mjd_to_jd(VALUE mjd)
{
    return f_add(mjd, MJD_EPOCH_IN_CJD);
}
#endif

static VALUE
rt_jd_to_mjd(VALUE jd)
{
    return f_sub(jd, MJD_EPOCH_IN_CJD);
}

#ifndef NDEBUG
static VALUE
rt_ld_to_jd(VALUE ld)
{
    return f_add(ld, LD_EPOCH_IN_CJD);
}
#endif

static VALUE
rt_jd_to_ld(VALUE jd)
{
    return f_sub(jd, LD_EPOCH_IN_CJD);
}

static VALUE
rt_jd_to_wday(VALUE jd)
{
    return f_mod(f_add(jd, INT2FIX(1)), INT2FIX(7));
}

static VALUE
rt__valid_jd_p(VALUE jd, VALUE sg)
{
    return jd;
}

static VALUE
rt__valid_ordinal_p(VALUE y, VALUE d, VALUE sg)
{
    VALUE jd, t, ny, nd;

    if (f_negative_p(d)) {
	VALUE j;

	j = rt_find_ldoy(y, sg);
	if (NIL_P(j))
	    return Qnil;
	t = rt_jd_to_ordinal(f_add3(j, d, INT2FIX(1)), sg);
	ny = RARRAY_PTR(t)[0];
	nd = RARRAY_PTR(t)[1];
	if (!f_eqeq_p(ny, y))
	    return Qnil;
	d = nd;
    }
    jd = rt_ordinal_to_jd(y, d, sg);
    t = rt_jd_to_ordinal(jd, sg);
    ny = RARRAY_PTR(t)[0];
    nd = RARRAY_PTR(t)[1];
    if (!f_eqeq_p(y, ny))
	return Qnil;
    if (!f_eqeq_p(d, nd))
	return Qnil;
    return jd;
}

static VALUE
rt__valid_civil_p(VALUE y, VALUE m, VALUE d, VALUE sg)
{
    VALUE t, ny, nm, nd, jd;

    if (f_negative_p(m))
	m = f_add(m, INT2FIX(13));
    if (f_negative_p(d)) {
	VALUE j;

	j = rt_find_ldom(y, m, sg);
	if (NIL_P(j))
	    return Qnil;
	t = rt_jd_to_civil(f_add3(j, d, INT2FIX(1)), sg);
	ny = RARRAY_PTR(t)[0];
	nm = RARRAY_PTR(t)[1];
	nd = RARRAY_PTR(t)[2];
	if (!f_eqeq_p(ny, y))
	    return Qnil;
	if (!f_eqeq_p(nm, m))
	    return Qnil;
	d = nd;
    }
    jd = rt_civil_to_jd(y, m, d, sg);
    t = rt_jd_to_civil(jd, sg);
    ny = RARRAY_PTR(t)[0];
    nm = RARRAY_PTR(t)[1];
    nd = RARRAY_PTR(t)[2];
    if (!f_eqeq_p(y, ny))
	return Qnil;
    if (!f_eqeq_p(m, nm))
	return Qnil;
    if (!f_eqeq_p(d, nd))
	return Qnil;
    return jd;
}

static VALUE
rt__valid_commercial_p(VALUE y, VALUE w, VALUE d, VALUE sg)
{
    VALUE t, ny, nw, nd, jd;

    if (f_negative_p(d))
	d = f_add(d, INT2FIX(8));
    if (f_negative_p(w)) {
	VALUE j;

	j = rt_commercial_to_jd(f_add(y, INT2FIX(1)),
				INT2FIX(1), INT2FIX(1), sg);
	t = rt_jd_to_commercial(f_add(j, f_mul(w, INT2FIX(7))), sg);
	ny = RARRAY_PTR(t)[0];
	nw = RARRAY_PTR(t)[1];
	if (!f_eqeq_p(ny, y))
	    return Qnil;
	w = nw;
    }
    jd = rt_commercial_to_jd(y, w, d, sg);
    t = rt_jd_to_commercial(jd, sg);
    ny = RARRAY_PTR(t)[0];
    nw = RARRAY_PTR(t)[1];
    nd = RARRAY_PTR(t)[2];
    if (!f_eqeq_p(ny, y))
	return Qnil;
    if (!f_eqeq_p(nw, w))
	return Qnil;
    if (!f_eqeq_p(nd, d))
	return Qnil;
    return jd;
}

static VALUE
rt__valid_weeknum_p(VALUE y, VALUE w, VALUE d, VALUE f, VALUE sg)
{
    VALUE t, ny, nw, nd, jd;

    if (f_negative_p(d))
	d = f_add(d, INT2FIX(7));
    if (f_negative_p(w)) {
	VALUE j;

	j = rt_weeknum_to_jd(f_add(y, INT2FIX(1)),
			     INT2FIX(1), f, f, sg);
	t = rt_jd_to_weeknum(f_add(j, f_mul(w, INT2FIX(7))), f, sg);
	ny = RARRAY_PTR(t)[0];
	nw = RARRAY_PTR(t)[1];
	if (!f_eqeq_p(ny, y))
	    return Qnil;
	w = nw;
    }
    jd = rt_weeknum_to_jd(y, w, d, f, sg);
    t = rt_jd_to_weeknum(jd, f, sg);
    ny = RARRAY_PTR(t)[0];
    nw = RARRAY_PTR(t)[1];
    nd = RARRAY_PTR(t)[2];
    if (!f_eqeq_p(ny, y))
	return Qnil;
    if (!f_eqeq_p(nw, w))
	return Qnil;
    if (!f_eqeq_p(nd, d))
	return Qnil;
    return jd;
}

#ifndef NDEBUG
static VALUE
rt__valid_nth_kday_p(VALUE y, VALUE m, VALUE n, VALUE k, VALUE sg)
{
    VALUE t, ny, nm, nn, nk, jd;

    if (f_negative_p(k))
	k = f_add(k, INT2FIX(7));
    if (f_negative_p(n)) {
	VALUE j;

	t = f_add(f_mul(y, INT2FIX(12)), m);
	ny = f_idiv(t, INT2FIX(12));
	nm = f_mod(t, INT2FIX(12));
	nm = f_floor(f_add(nm, INT2FIX(1)));

	j = rt_nth_kday_to_jd(ny, nm, INT2FIX(1), k, sg);
	t = rt_jd_to_nth_kday(f_add(j, f_mul(n, INT2FIX(7))), sg);
	ny = RARRAY_PTR(t)[0];
	nm = RARRAY_PTR(t)[1];
	nn = RARRAY_PTR(t)[2];
	if (!f_eqeq_p(ny, y))
	    return Qnil;
	if (!f_eqeq_p(nm, m))
	    return Qnil;
	n = nn;
    }
    jd = rt_nth_kday_to_jd(y, m, n, k, sg);
    t = rt_jd_to_nth_kday(jd, sg);
    ny = RARRAY_PTR(t)[0];
    nm = RARRAY_PTR(t)[1];
    nn = RARRAY_PTR(t)[2];
    nk = RARRAY_PTR(t)[3];
    if (!f_eqeq_p(ny, y))
	return Qnil;
    if (!f_eqeq_p(nm, m))
	return Qnil;
    if (!f_eqeq_p(nn, n))
	return Qnil;
    if (!f_eqeq_p(nk, k))
	return Qnil;
    return jd;
}
#endif

static VALUE
rt__valid_time_p(VALUE h, VALUE min, VALUE s)
{
    if (f_negative_p(h))
	h = f_add(h, INT2FIX(24));
    if (f_negative_p(min))
	min = f_add(min, INT2FIX(MINUTE_IN_SECONDS));
    if (f_negative_p(s))
	s = f_add(s, INT2FIX(MINUTE_IN_SECONDS));
    if (f_eqeq_p(h, INT2FIX(24))) {
	if (!f_eqeq_p(min, INT2FIX(0)))
	    return Qnil;
	if (!f_eqeq_p(s, INT2FIX(0)))
	    return Qnil;
    }
    else {
	if (f_lt_p(h, INT2FIX(0)) || f_ge_p(h, INT2FIX(24)))
	    return Qnil;
	if (f_lt_p(min, INT2FIX(0)) || f_ge_p(min, INT2FIX(60)))
	    return Qnil;
	if (f_lt_p(s, INT2FIX(0)) || f_ge_p(s, INT2FIX(60)))
	    return Qnil;
    }
    return rt_time_to_day_fraction(h, min, s);
}

/* light base */

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
    return (MOD(y, 4) == 0 && y % 100 != 0) || (MOD(y, 400) == 0);
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

#ifndef NDEBUG
static int
valid_weeknum_p(int y, int w, int d, int f, double sg,
		int *rw, int *rd, long *rjd, int *ns)
{
    int ns2, ry2, rw2, rd2;

    if (d < 0)
	d += 7;
    if (w < 0) {
	long rjd2;

	weeknum_to_jd(y + 1, 1, f, f, sg, &rjd2, &ns2);
	jd_to_weeknum(rjd2 + w * 7, f, sg, &ry2, &rw2, &rd2);
	if (ry2 != y)
	    return 0;
	w = rw2;
    }
    weeknum_to_jd(y, w, d, f, sg, rjd, ns);
    jd_to_weeknum(*rjd, f, sg, &ry2, rw, rd);
    if (y != ry2 || w != *rw || d != *rd)
	return 0;
    return 1;
}

static int
valid_nth_kday_p(int y, int m, int n, int k, double sg,
		 int *rm, int *rn, int *rk, long *rjd, int *ns)
{
    int ns2, ry2, rm2, rn2, rk2;

    if (k < 0)
	k += 7;
    if (n < 0) {
	long rjd2;
	int t, ny, nm;

	t = y * 12 + m;
	ny = DIV(t, 12);
	nm = MOD(t, 12) + 1;

	nth_kday_to_jd(ny, nm, 1, k, sg, &rjd2, &ns2);
	jd_to_nth_kday(rjd2 + n * 7, sg, &ry2, &rm2, &rn2, &rk2);
	if (ry2 != y || rm2 != m)
	    return 0;
	n = rn2;
    }
    nth_kday_to_jd(y, m, n, k, sg, rjd, ns);
    jd_to_nth_kday(*rjd, sg, &ry2, rm, rn, rk);
    if (y != ry2 || m != *rm || n != *rn || k != *rk)
	return 0;
    return 1;
}
#endif

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
    return h * HOUR_IN_SECONDS + min * MINUTE_IN_SECONDS + s;
}

inline static int
jd_to_wday(long jd)
{
    return (int)MOD(jd + 1, 7);
}

VALUE date_zone_to_diff(VALUE);

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
	    VALUE vs = date_zone_to_diff(vof);
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
	x->l.hour = r / HOUR_IN_SECONDS;
	r %= HOUR_IN_SECONDS;
	x->l.min = r / MINUTE_IN_SECONDS;
	x->l.sec = r % MINUTE_IN_SECONDS;
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

/* date light */

static VALUE
rtv__valid_jd_p(int argc, VALUE *argv)
{
    assert(argc == 2);
    return rt__valid_jd_p(argv[0], argv[1]);
}

static VALUE
valid_jd_sub(int argc, VALUE *argv, VALUE klass)
{
    return rtv__valid_jd_p(argc, argv);
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

    return valid_jd_sub(2, argv2, klass);
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
	argv[1] = INT2FIX(ITALY);
    else
	argv[1] = vsg;

    if (NIL_P(valid_jd_sub(2, argv2, klass)))
	return Qfalse;
    return Qtrue;
}

static VALUE
rtv__valid_civil_p(int argc, VALUE *argv)
{
    assert(argc == 4);
    return rt__valid_civil_p(argv[0], argv[1], argv[2], argv[3]);
}

static VALUE
valid_civil_sub(int argc, VALUE *argv, VALUE klass, int need_jd)
{
    int y, m, d, rm, rd;
    double sg;

#ifdef FORCE_RIGHT
    return rtv__valid_civil_p(argc, argv);
#endif

    if (!(FIXNUM_P(argv[0]) &&
	  FIXNUM_P(argv[1]) &&
	  FIXNUM_P(argv[2])))
	return rtv__valid_civil_p(argc, argv);

    y = NUM2INT(argv[0]);
    if (!LIGHTABLE_YEAR(y))
	return rtv__valid_civil_p(argc, argv);

    m = NUM2INT(argv[1]);
    d = NUM2INT(argv[2]);
    sg = NUM2DBL(argv[3]);

    if (!need_jd && isinf(sg) && sg < 0) {
	if (!valid_gregorian_p(y, m, d, &rm, &rd))
	    return Qnil;
	return INT2FIX(0); /* dummy */
    }
    else {
	long jd;
	int ns;

	if (!valid_civil_p(y, m, d, sg, &rm, &rd, &jd, &ns))
	    return Qnil;
	return LONG2NUM(jd);
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
	argv2[3] = INT2FIX(ITALY);
    else
	argv2[3] = vsg;

    if (NIL_P(valid_civil_sub(4, argv2, klass, 0)))
	return Qfalse;
    return Qtrue;
}

static VALUE
rtv__valid_ordinal_p(int argc, VALUE *argv)
{
    assert(argc == 3);
    return rt__valid_ordinal_p(argv[0], argv[1], argv[2]);
}

static VALUE
valid_ordinal_sub(int argc, VALUE *argv, VALUE klass)
{
    int y, d, rd;
    double sg;

#ifdef FORCE_RIGHT
    return rtv__valid_ordinal_p(argc, argv);
#endif

    if (!(FIXNUM_P(argv[0]) &&
	  FIXNUM_P(argv[1])))
	return rtv__valid_ordinal_p(argc, argv);

    y = NUM2INT(argv[0]);
    if (!LIGHTABLE_YEAR(y))
	return rtv__valid_ordinal_p(argc, argv);

    d = NUM2INT(argv[1]);
    sg = NUM2DBL(argv[2]);

    {
	long jd;
	int ns;

	if (!valid_ordinal_p(y, d, sg, &rd, &jd, &ns))
	    return Qnil;
	return LONG2NUM(jd);
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

    return valid_ordinal_sub(3, argv2, klass);
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
	argv2[2] = INT2FIX(ITALY);
    else
	argv2[2] = vsg;

    if (NIL_P(valid_ordinal_sub(3, argv2, klass)))
	return Qfalse;
    return Qtrue;
}

static VALUE
rtv__valid_commercial_p(int argc, VALUE *argv)
{
    assert(argc == 4);
    return rt__valid_commercial_p(argv[0], argv[1], argv[2], argv[3]);
}

static VALUE
valid_commercial_sub(int argc, VALUE *argv, VALUE klass)
{
    int y, w, d, rw, rd;
    double sg;

#ifdef FORCE_RIGHT
    return rtv__valid_commercial_p(argc, argv);
#endif

    if (!(FIXNUM_P(argv[0]) &&
	  FIXNUM_P(argv[1]) &&
	  FIXNUM_P(argv[2])))
	return rtv__valid_commercial_p(argc, argv);

    y = NUM2INT(argv[0]);
    if (!LIGHTABLE_CWYEAR(y))
	return rtv__valid_commercial_p(argc, argv);

    w = NUM2INT(argv[1]);
    d = NUM2INT(argv[2]);
    sg = NUM2DBL(argv[3]);

    {
	long jd;
	int ns;

	if (!valid_commercial_p(y, w, d, sg, &rw, &rd, &jd, &ns))
	    return Qnil;
	return LONG2NUM(jd);
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

    return valid_commercial_sub(4, argv2, klass);
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
	argv2[3] = INT2FIX(ITALY);
    else
	argv2[3] = vsg;

    if (NIL_P(valid_commercial_sub(4, argv2, klass)))
	return Qfalse;
    return Qtrue;
}

#ifndef NDEBUG
static VALUE
rtv__valid_weeknum_p(int argc, VALUE *argv)
{
    assert(argc == 5);
    return rt__valid_weeknum_p(argv[0], argv[1], argv[2], argv[3], argv[4]);
}

static VALUE
valid_weeknum_sub(int argc, VALUE *argv, VALUE klass)
{
    int y, w, d, f, rw, rd;
    double sg;

#ifdef FORCE_RIGHT
    return rtv__valid_weeknum_p(argc, argv);
#endif

    if (!(FIXNUM_P(argv[0]) &&
	  FIXNUM_P(argv[1]) &&
	  FIXNUM_P(argv[2]) &&
	  FIXNUM_P(argv[3])))
	return rtv__valid_weeknum_p(argc, argv);

    y = NUM2INT(argv[0]);
    if (!LIGHTABLE_YEAR(y))
	return rtv__valid_weeknum_p(argc, argv);

    w = NUM2INT(argv[1]);
    d = NUM2INT(argv[2]);
    f = NUM2INT(argv[3]);
    sg = NUM2DBL(argv[4]);

    {
	long jd;
	int ns;

	if (!valid_weeknum_p(y, w, d, f, sg, &rw, &rd, &jd, &ns))
	    return Qnil;
	return LONG2NUM(jd);
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

    return valid_weeknum_sub(5, argv2, klass);
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
	argv2[4] = INT2FIX(ITALY);
    else
	argv2[4] = vsg;

    if (NIL_P(valid_weeknum_sub(5, argv2, klass)))
	return Qfalse;
    return Qtrue;
}

static VALUE
rtv__valid_nth_kday_p(int argc, VALUE *argv)
{
    assert(argc == 5);
    return rt__valid_nth_kday_p(argv[0], argv[1], argv[2], argv[3], argv[4]);
}
static VALUE
valid_nth_kday_sub(int argc, VALUE *argv, VALUE klass)
{
    int y, m, n, k, rm, rn, rk;
    double sg;

#ifdef FORCE_RIGHT
    return rtv__valid_nth_kday_p(argc, argv);
#endif

    if (!(FIXNUM_P(argv[0]) &&
	  FIXNUM_P(argv[1]) &&
	  FIXNUM_P(argv[2]) &&
	  FIXNUM_P(argv[3])))
	return rtv__valid_nth_kday_p(argc, argv);

    y = NUM2INT(argv[0]);
    if (!LIGHTABLE_YEAR(y))
	return rtv__valid_nth_kday_p(argc, argv);

    m = NUM2INT(argv[1]);
    n = NUM2INT(argv[2]);
    k = NUM2INT(argv[3]);
    sg = NUM2DBL(argv[4]);

    {
	long jd;
	int ns;

	if (!valid_nth_kday_p(y, m, n, k, sg, &rm, &rn, &rk, &jd, &ns))
	    return Qnil;
	return LONG2NUM(jd);
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

    return valid_nth_kday_sub(5, argv2, klass);
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
	argv2[4] = INT2FIX(ITALY);
    else
	argv2[4] = vsg;

    if (NIL_P(valid_nth_kday_sub(5, argv2, klass)))
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
	!f_zero_p(f_mod(y, INT2FIX(100))) ||
	f_zero_p(f_mod(y, INT2FIX(400))))
	return Qtrue;
    return Qfalse;
}

static void
d_right_gc_mark(union DateData *dat)
{
    assert(!light_mode_p(dat));
    rb_gc_mark(dat->r.ajd);
    rb_gc_mark(dat->r.of);
    rb_gc_mark(dat->r.sg);
    rb_gc_mark(dat->r.cache);
}

#define d_lite_gc_mark 0

inline static VALUE
d_right_new_internal(VALUE klass, VALUE ajd, VALUE of, VALUE sg,
		     unsigned flags)
{
    union DateData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateData,
			   d_right_gc_mark, -1, dat);

    dat->r.ajd = ajd;
    dat->r.of = of;
    dat->r.sg = sg;
    dat->r.cache = rb_hash_new();
    dat->r.flags = flags;

    return obj;
}

inline static VALUE
d_lite_new_internal(VALUE klass, long jd, double sg,
		    int y, int m, int d, unsigned flags)
{
    union DateData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateData,
			   d_lite_gc_mark, -1, dat);

    dat->l.jd = jd;
    dat->l.sg = sg;
    dat->l.year = y;
    dat->l.mon = m;
    dat->l.mday = d;
    dat->l.flags = flags | LIGHT_MODE;

    return obj;
}

static VALUE
d_lite_new_internal_wo_civil(VALUE klass, long jd, double sg,
			       unsigned flags)
{
    return d_lite_new_internal(klass, jd, sg, 0, 0, 0, flags);
}

static VALUE
d_lite_s_alloc(VALUE klass)
{
    return d_lite_new_internal_wo_civil(klass, 0, 0, 0);
}

static VALUE
d_right_new(VALUE klass, VALUE ajd, VALUE of, VALUE sg)
{
    return d_right_new_internal(klass, ajd, of, sg, 0);
}

static VALUE
d_lite_new(VALUE klass, VALUE jd, VALUE sg)
{
    return d_lite_new_internal_wo_civil(klass,
					NUM2LONG(jd),
					NUM2DBL(sg),
					HAVE_JD);
}

static VALUE
d_switch_new(VALUE klass, VALUE ajd, VALUE of, VALUE sg)
{
    VALUE t, jd, df;

    t = rt_ajd_to_jd(ajd, INT2FIX(0)); /* as utc */
    jd = RARRAY_PTR(t)[0];
    df = RARRAY_PTR(t)[1];

#ifdef FORCE_RIGHT
    if (1)
#else
    if (!FIXNUM_P(jd) ||
	f_lt_p(jd, sg) || !f_zero_p(df) || !f_zero_p(of) ||
	!LIGHTABLE_JD(NUM2LONG(jd)))
#endif
	return d_right_new(klass, ajd, of, sg);
    else
	return d_lite_new(klass, jd, sg);
}

#ifndef NDEBUG
static VALUE
d_right_new_m(int argc, VALUE *argv, VALUE klass)
{
    VALUE ajd, of, sg;

    rb_scan_args(argc, argv, "03", &ajd, &of, &sg);

    switch (argc) {
      case 0:
	ajd = INT2FIX(0);
      case 1:
	of = INT2FIX(0);
      case 2:
	sg = INT2FIX(ITALY);
    }

    return d_right_new(klass, ajd, of, sg);
}

static VALUE
d_lite_new_m(int argc, VALUE *argv, VALUE klass)
{
    VALUE jd, sg;

    rb_scan_args(argc, argv, "02", &jd, &sg);

    switch (argc) {
      case 0:
	jd = INT2FIX(0);
      case 1:
	sg = INT2FIX(ITALY);
    }

    return d_lite_new(klass, jd, sg);
}

static VALUE
d_switch_new_m(int argc, VALUE *argv, VALUE klass)
{
    VALUE ajd, of, sg;

    rb_scan_args(argc, argv, "03", &ajd, &of, &sg);

    switch (argc) {
      case 0:
	ajd = INT2FIX(0);
      case 1:
	of = INT2FIX(0);
      case 2:
	sg = INT2FIX(ITALY);
    }

    return d_switch_new(klass, ajd, of, sg);
}
#endif

static VALUE
d_right_new_jd(VALUE klass, VALUE jd, VALUE sg)
{
    return d_right_new(klass,
		       rt_jd_to_ajd(jd, INT2FIX(0), INT2FIX(0)),
		       INT2FIX(0),
		       sg);
}

#ifndef NDEBUG
static VALUE
d_lite_new_jd(VALUE klass, VALUE jd, VALUE sg)
{
    return d_lite_new(klass, jd, sg);
}
#endif

static VALUE
d_switch_new_jd(VALUE klass, VALUE jd, VALUE sg)
{
    return d_switch_new(klass,
			rt_jd_to_ajd(jd, INT2FIX(0), INT2FIX(0)),
			INT2FIX(0),
			sg);
}

#ifndef NDEBUG
static VALUE
date_s_new_r_bang(int argc, VALUE *argv, VALUE klass)
{
    return d_right_new_m(argc, argv, klass);
}

static VALUE
date_s_new_l_bang(int argc, VALUE *argv, VALUE klass)
{
    return d_lite_new_m(argc, argv, klass);
}

static VALUE
date_s_new_bang(int argc, VALUE *argv, VALUE klass)
{
    return d_switch_new_m(argc, argv, klass);
}
#endif

#define c_cforwardv(m) rt_date_s_##m(argc, argv, klass)

static VALUE
rt_date_s_jd(int argc, VALUE *argv, VALUE klass)
{
    VALUE jd, sg;

    rb_scan_args(argc, argv, "02", &jd, &sg);

    switch (argc) {
      case 0:
	jd = INT2FIX(0);
      case 1:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_jd_p(jd, sg);

    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");

    return d_right_new_jd(klass, jd, sg);
}

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
    VALUE vjd, vsg;
    long jd;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(jd);
#endif

    rb_scan_args(argc, argv, "02", &vjd, &vsg);

    if (!FIXNUM_P(vjd))
	return c_cforwardv(jd);

    jd = 0;
    sg = ITALY;

    switch (argc) {
      case 2:
	sg = NUM2DBL(vsg);
      case 1:
	jd = NUM2LONG(vjd);
	if (!LIGHTABLE_JD(jd))
	    return c_cforwardv(jd);
    }

    if (jd < sg)
	return c_cforwardv(jd);

    return d_lite_new_internal_wo_civil(klass, jd, sg, HAVE_JD);
}

static VALUE
rt_date_s_ordinal(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, d, sg, jd;

    rb_scan_args(argc, argv, "03", &y, &d, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	d = INT2FIX(1);
      case 2:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_ordinal_p(y, d, sg);

    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");

    return d_right_new_jd(klass, jd, sg);
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
    VALUE vy, vd, vsg;
    int y, d, rd;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(ordinal);
#endif

    rb_scan_args(argc, argv, "03", &vy, &vd, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vd) || FIXNUM_P(vd))))
	return c_cforwardv(ordinal);

    y = -4712;
    d = 1;
    sg = ITALY;

    switch (argc) {
      case 3:
	sg = NUM2DBL(vsg);
      case 2:
	d = NUM2INT(vd);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return c_cforwardv(ordinal);
    }

    {
	long jd;
	int ns;

	if (!valid_ordinal_p(y, d, sg, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(ordinal);

	return d_lite_new_internal_wo_civil(klass, jd, sg,
					    HAVE_JD);
    }
}

static VALUE
rt_date_s_civil(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, m, d, sg, jd;

    rb_scan_args(argc, argv, "04", &y, &m, &d, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	m = INT2FIX(1);
      case 2:
	d = INT2FIX(1);
      case 3:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_civil_p(y, m, d, sg);

    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");

    return d_right_new_jd(klass, jd, sg);
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
    VALUE vy, vm, vd, vsg;
    int y, m, d, rm, rd;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(civil);
#endif

    rb_scan_args(argc, argv, "04", &vy, &vm, &vd, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vm) || FIXNUM_P(vm)) &&
	  (NIL_P(vd) || FIXNUM_P(vd))))
	return c_cforwardv(civil);

    y = -4712;
    m = 1;
    d = 1;
    sg = ITALY;

    switch (argc) {
      case 4:
	sg = NUM2DBL(vsg);
      case 3:
	d = NUM2INT(vd);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return c_cforwardv(civil);
    }

    if (isinf(sg) && sg < 0) {
	if (!valid_gregorian_p(y, m, d, &rm, &rd))
	    rb_raise(rb_eArgError, "invalid date");

	return d_lite_new_internal(klass, 0, sg, y, rm, rd,
				   HAVE_CIVIL);
    }
    else {
	long jd;
	int ns;

	if (!valid_civil_p(y, m, d, sg, &rm, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(civil);

	return d_lite_new_internal(klass, jd, sg, y, rm, rd,
				   HAVE_JD | HAVE_CIVIL);
    }
}

static VALUE
rt_date_s_commercial(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, w, d, sg, jd;

    rb_scan_args(argc, argv, "04", &y, &w, &d, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	w = INT2FIX(1);
      case 2:
	d = INT2FIX(1);
      case 3:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_commercial_p(y, w, d, sg);

    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");

    return d_right_new_jd(klass, jd, sg);
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
    VALUE vy, vw, vd, vsg;
    int y, w, d, rw, rd;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(commercial);
#endif

    rb_scan_args(argc, argv, "04", &vy, &vw, &vd, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vw) || FIXNUM_P(vw)) &&
	  (NIL_P(vd) || FIXNUM_P(vd))))
	return c_cforwardv(commercial);

    y = -4712;
    w = 1;
    d = 1;
    sg = ITALY;

    switch (argc) {
      case 4:
	sg = NUM2DBL(vsg);
      case 3:
	d = NUM2INT(vd);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_CWYEAR(y))
	    return c_cforwardv(commercial);
    }

    {
	long jd;
	int ns;

	if (!valid_commercial_p(y, w, d, sg, &rw, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(commercial);

	return d_lite_new_internal_wo_civil(klass, jd, sg,
					    HAVE_JD);
    }
}

#ifndef NDEBUG
static VALUE
rt_date_s_weeknum(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, w, d, f, sg, jd;

    rb_scan_args(argc, argv, "05", &y, &w, &d, &f, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	w = INT2FIX(0);
      case 2:
	d = INT2FIX(1);
      case 3:
	f = INT2FIX(0);
      case 4:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_weeknum_p(y, w, d, f, sg);

    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");

    return d_right_new_jd(klass, jd, sg);
}

static VALUE
date_s_weeknum(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vf, vsg;
    int y, w, d, f, rw, rd;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(weeknum);
#endif

    rb_scan_args(argc, argv, "05", &vy, &vw, &vd, &vf, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vw) || FIXNUM_P(vw)) &&
	  (NIL_P(vd) || FIXNUM_P(vd)) &&
	  (NIL_P(vf) || FIXNUM_P(vf))))
	return c_cforwardv(weeknum);

    y = -4712;
    w = 0;
    d = 1;
    f = 0;
    sg = ITALY;

    switch (argc) {
      case 5:
	sg = NUM2DBL(vsg);
      case 4:
	f = NUM2INT(vf);
      case 3:
	d = NUM2INT(vd);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return c_cforwardv(weeknum);
    }

    {
	long jd;
	int ns;

	if (!valid_weeknum_p(y, w, d, f, sg, &rw, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(weeknum);

	return d_lite_new_internal_wo_civil(klass, jd, sg,
					    HAVE_JD);
    }
}

static VALUE
rt_date_s_nth_kday(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, m, n, k, sg, jd;

    rb_scan_args(argc, argv, "05", &y, &m, &n, &k, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	m = INT2FIX(1);
      case 2:
	n = INT2FIX(1);
      case 3:
	k = INT2FIX(1);
      case 4:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_nth_kday_p(y, m, n, k, sg);

    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");

    return d_right_new_jd(klass, jd, sg);
}

static VALUE
date_s_nth_kday(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vn, vk, vsg;
    int y, m, n, k, rm, rn, rk;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(nth_kday);
#endif

    rb_scan_args(argc, argv, "05", &vy, &vm, &vn, &vk, &vsg);

    if (!((NIL_P(vy) || FIXNUM_P(vy)) &&
	  (NIL_P(vm) || FIXNUM_P(vm)) &&
	  (NIL_P(vn) || FIXNUM_P(vn)) &&
	  (NIL_P(vk) || FIXNUM_P(vk))))
	return c_cforwardv(nth_kday);

    y = -4712;
    m = 1;
    n = 1;
    k = 1;
    sg = ITALY;

    switch (argc) {
      case 5:
	sg = NUM2DBL(vsg);
      case 4:
	k = NUM2INT(vk);
      case 3:
	n = NUM2INT(vn);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return c_cforwardv(nth_kday);
    }

    {
	long jd;
	int ns;

	if (!valid_nth_kday_p(y, m, n, k, sg, &rm, &rn, &rk, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(nth_kday);

	return d_lite_new_internal_wo_civil(klass, jd, sg,
					    HAVE_JD);
    }
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
    VALUE vsg;
    double sg;
    time_t t;
    struct tm tm;
    int y;
    int m, d;

    rb_scan_args(argc, argv, "01", &vsg);

    if (argc < 1)
	sg = ITALY;
    else
	sg = NUM2DBL(vsg);

    if (time(&t) == -1)
	rb_sys_fail("time");
    localtime_r(&t, &tm);

    y = tm.tm_year + 1900;
    m = tm.tm_mon + 1;
    d = tm.tm_mday;

#ifdef FORCE_RIGHT
    goto right;
#endif

    if (!LIGHTABLE_YEAR(y))
	goto right;

    if (isinf(sg) && sg < 0)
	return d_lite_new_internal(klass, 0, sg, y, m, d,
				   HAVE_CIVIL);
    else {
	long jd;
	int ns;

	civil_to_jd(y, m, d, sg, &jd, &ns);

	return d_lite_new_internal(klass, jd, sg, y, m, d,
				   HAVE_JD | HAVE_CIVIL);
    }
  right:
    {
	VALUE jd, ajd;

	jd = rt_civil_to_jd(INT2FIX(y), INT2FIX(m), INT2FIX(d), DBL2NUM(sg));
	ajd = rt_jd_to_ajd(jd, INT2FIX(0), INT2FIX(0));
	return d_right_new(klass, ajd, INT2FIX(0), DBL2NUM(sg));
    }
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
	    set_hash("jd", f_jd(f_add(f_sub(d, f_wday(d)), ref_hash("wday"))));
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
#define f_values_at3(o,k1,k2,k3) rb_funcall(o, rb_intern("values_at"), 3, k1, k2, k3)

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
rt__valid_time_frags_p(VALUE hash)
{
    VALUE a;

    a = f_values_at3(hash, sym("hour"), sym("min"), sym("sec"));
    return rt__valid_time_p(RARRAY_PTR(a)[0],
			    RARRAY_PTR(a)[1],
			    RARRAY_PTR(a)[2]);
}

static VALUE
d_switch_new_by_frags(VALUE klass, VALUE hash, VALUE sg)
{
    VALUE jd;

    hash = rt_rewrite_frags(hash);
    hash = rt_complete_frags(klass, hash);
    jd = rt__valid_date_frags_p(hash, sg);
    if (NIL_P(jd))
	rb_raise(rb_eArgError, "invalid date");
    return d_switch_new_jd(klass, jd, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = fmt;
	hash = date_s__strptime(2, argv2, klass);
	return d_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = comp;
	hash = date_s__parse(2, argv2, klass);
	return d_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__iso8601(klass, str);
	return d_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__rfc3339(klass, str);
	return d_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__xmlschema(klass, str);
	return d_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__rfc2822(klass, str);
	return d_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__httpdate(klass, str);
	return d_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__jisx0301(klass, str);
	return d_switch_new_by_frags(klass, hash, sg);
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

#define c_iforward0(m) d_right_##m(self)
#define c_iforwardv(m) d_right_##m(argc, argv, self)
#define c_iforwardop(m) d_right_##m(self, other)

static VALUE
d_right_amjd(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return rt_ajd_to_amjd(dat->r.ajd);
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
	return c_iforward0(amjd);
    {
	get_d_jd(dat);
	return rb_rational_new1(LONG2NUM(dat->l.jd - 2400001L));
    }
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

static VALUE
d_right_daynum(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(daynum, rt_ajd_to_jd(dat->r.ajd, dat->r.of));
}

static VALUE
d_right_jd(VALUE self)
{
    return RARRAY_PTR(c_iforward0(daynum))[0];
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
	return c_iforward0(jd);
    {
	get_d_jd(dat);
	return INT2FIX(dat->l.jd);
    }
}

static VALUE
d_right_mjd(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return rt_jd_to_mjd(d_right_jd(self));
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
	return c_iforward0(mjd);
    {
	get_d_jd(dat);
	return LONG2NUM(dat->l.jd - 2400001L);
    }
}

static VALUE
d_right_ld(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return rt_jd_to_ld(d_right_jd(self));
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
	return c_iforward0(ld);
    {
	get_d_jd(dat);
	return LONG2NUM(dat->l.jd - 2299160L);
    }
}

static VALUE
d_right_civil(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(civil, rt_jd_to_civil(d_right_jd(self), dat->r.sg));
}

static VALUE
d_right_year(VALUE self)
{
    return RARRAY_PTR(c_iforward0(civil))[0];
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
	return c_iforward0(year);
    {
	get_d_civil(dat);
	return INT2FIX(dat->l.year);
    }
}

static VALUE
d_right_ordinal(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(ordinal, rt_jd_to_ordinal(d_right_jd(self), dat->r.sg));
}

static VALUE
d_right_yday(VALUE self)
{
    return RARRAY_PTR(c_iforward0(ordinal))[1];
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
	return c_iforward0(yday);
    {
	get_d_civil(dat);
	return INT2FIX(civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday));
    }
}

static VALUE
d_right_mon(VALUE self)
{
    return RARRAY_PTR(c_iforward0(civil))[1];
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
    if (!light_mode_p(dat))
	return c_iforward0(mon);
    {
	get_d_civil(dat);
	return INT2FIX(dat->l.mon);
    }
}

static VALUE
d_right_mday(VALUE self)
{
    return RARRAY_PTR(c_iforward0(civil))[2];
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
    if (!light_mode_p(dat))
	return c_iforward0(mday);
    {
	get_d_civil(dat);
	return INT2FIX(dat->l.mday);
    }
}

static VALUE
d_right_day_fraction(VALUE self)
{
    return RARRAY_PTR(c_iforward0(daynum))[1];
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
	return c_iforward0(day_fraction);
    return INT2FIX(0);
}

static VALUE
d_right_weeknum0(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(weeknum0, rt_jd_to_weeknum(d_right_jd(self),
					   INT2FIX(0), dat->r.sg));
}

static VALUE
d_right_wnum0(VALUE self)
{
    return RARRAY_PTR(c_iforward0(weeknum0))[1];
}

static VALUE
d_lite_wnum0(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    if (!light_mode_p(dat))
	return c_iforward0(wnum0);
    {
	get_d_jd(dat);
	jd_to_weeknum(dat->l.jd, 0, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

static VALUE
d_right_weeknum1(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(weeknum1, rt_jd_to_weeknum(d_right_jd(self),
					   INT2FIX(1), dat->r.sg));
}

static VALUE
d_right_wnum1(VALUE self)
{
    return RARRAY_PTR(c_iforward0(weeknum1))[1];
}

static VALUE
d_lite_wnum1(VALUE self)
{
    int ry, rw, rd;

    get_d1(self);
    if (!light_mode_p(dat))
	return c_iforward0(wnum1);
    {
	get_d_jd(dat);
	jd_to_weeknum(dat->l.jd, 1, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

#ifndef NDEBUG
static VALUE
d_right_time(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(time, rt_day_fraction_to_time(d_right_day_fraction(self)));
}
#endif

static VALUE
d_right_time_wo_sf(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(time_wo_sf,
		rt_day_fraction_to_time_wo_sf(d_right_day_fraction(self)));
}

static VALUE
d_right_time_sf(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(time_sf, f_mul(f_mod(d_right_day_fraction(self),
				     SECONDS_IN_DAY),
			       INT2FIX(DAY_IN_SECONDS)));
}

static VALUE
d_right_hour(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[0];
#else
    return RARRAY_PTR(c_iforward0(time_wo_sf))[0];
#endif
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
	return c_iforward0(hour);
    return INT2FIX(0);
}

static VALUE
d_right_min(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[1];
#else
    return RARRAY_PTR(c_iforward0(time_wo_sf))[1];
#endif
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
	return c_iforward0(min);
    return INT2FIX(0);
}

static VALUE
d_right_sec(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[2];
#else
    return RARRAY_PTR(c_iforward0(time_wo_sf))[2];
#endif
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
	return c_iforward0(sec);
    return INT2FIX(0);
}

static VALUE
d_right_sec_fraction(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[3];
#else
    return c_iforward0(time_sf);
#endif
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
	return c_iforward0(sec_fraction);
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

static VALUE
d_right_zone(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    {
	int sign;
	VALUE hh, mm, ss, fr;

	if (f_negative_p(dat->r.of)) {
	    sign = '-';
	    fr = f_abs(dat->r.of);
	}
	else {
	    sign = '+';
	    fr = dat->r.of;
	}
	ss = f_div(fr, SECONDS_IN_DAY);

	hh = f_idiv(ss, INT2FIX(HOUR_IN_SECONDS));
	ss = f_mod(ss, INT2FIX(HOUR_IN_SECONDS));

	mm = f_idiv(ss, INT2FIX(MINUTE_IN_SECONDS));

	return rb_enc_sprintf(rb_usascii_encoding(),
			      "%c%02d:%02d",
			      sign, NUM2INT(hh), NUM2INT(mm));
    }
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
	return c_iforward0(zone);
    return rb_usascii_str_new2("+00:00");
}

static VALUE
d_right_commercial(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return_once(commercial, rt_jd_to_commercial(d_right_jd(self), dat->r.sg));
}

static VALUE
d_right_cwyear(VALUE self)
{
    return RARRAY_PTR(c_iforward0(commercial))[0];
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
	return c_iforward0(cwyear);
    {
	get_d_jd(dat);
	jd_to_commercial(dat->l.jd, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(ry);
    }
}

static VALUE
d_right_cweek(VALUE self)
{
    return RARRAY_PTR(c_iforward0(commercial))[1];
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
	return c_iforward0(cweek);
    {
	get_d_jd(dat);
	jd_to_commercial(dat->l.jd, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

static VALUE
d_right_cwday(VALUE self)
{
    return RARRAY_PTR(c_iforward0(commercial))[2];
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
	return c_iforward0(cwday);
    {
	get_d_jd(dat);
	w = jd_to_wday(dat->l.jd);
	if (w == 0)
	    w = 7;
	return INT2FIX(w);
    }
}

static VALUE
d_right_wday(VALUE self)
{
    return rt_jd_to_wday(d_right_jd(self));
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
	return c_iforward0(wday);
    {
	get_d_jd(dat);
	return INT2FIX(jd_to_wday(dat->l.jd));
    }
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
    return f_eqeq_p(d_lite_wday(self), INT2FIX(0));
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
    return f_eqeq_p(d_lite_wday(self), INT2FIX(1));
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
    return f_eqeq_p(d_lite_wday(self), INT2FIX(2));
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
    return f_eqeq_p(d_lite_wday(self), INT2FIX(3));
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
    return f_eqeq_p(d_lite_wday(self), INT2FIX(4));
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
    return f_eqeq_p(d_lite_wday(self), INT2FIX(5));
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
    return f_eqeq_p(d_lite_wday(self), INT2FIX(6));
}

#ifndef NDEBUG
static VALUE
generic_nth_kday_p(VALUE self, VALUE n, VALUE k)
{
    if (f_eqeq_p(k, f_wday(self)) &&
	f_equal_p(f_jd(self), rt_nth_kday_to_jd(f_year(self),
						f_mon(self),
						n, k,
						f_start(self))))
	return Qtrue;
    return Qfalse;
}
#endif

static VALUE
d_right_julian_p(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return f_lt_p(d_right_jd(self), dat->r.sg);
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
	return c_iforward0(julian_p);
    return Qfalse;
}

static VALUE
d_right_gregorian_p(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return d_right_julian_p(self) ? Qfalse : Qtrue;
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
	return c_iforward0(gregorian_p);
    return Qtrue;
}

static VALUE
d_right_fix_style(VALUE self)
{
    if (d_right_julian_p(self))
	return DBL2NUM(JULIAN);
    return DBL2NUM(GREGORIAN);
}

static VALUE
d_right_leap_p(VALUE self)
{
    VALUE style, a;

    style = d_right_fix_style(self);
    a = rt_jd_to_civil(f_sub(rt_civil_to_jd(d_right_year(self),
					    INT2FIX(3), INT2FIX(1), style),
			     INT2FIX(1)),
		       style);
    if (f_eqeq_p(RARRAY_PTR(a)[2], INT2FIX(29)))
	return Qtrue;
    return Qfalse;
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
	return c_iforward0(leap_p);
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

static VALUE
d_right_new_start(int argc, VALUE *argv, VALUE self)
{
    get_d1(self);
    return d_right_new(CLASS_OF(self),
		       d_lite_ajd(self),
		       d_lite_offset(self),
		       (argc >= 1) ? argv[0] : INT2FIX(ITALY));
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
	return c_iforwardv(new_start);

    rb_scan_args(argc, argv, "01", &vsg);

    sg = ITALY;
    if (argc >= 1)
	sg = NUM2DBL(vsg);

    {
	get_d_jd(dat);

	if (dat->l.jd < sg)
	    return c_iforwardv(new_start);

	return d_lite_new_internal_wo_civil(CLASS_OF(self),
					    dat->l.jd,
					    sg,
					    HAVE_JD);
    }
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
    VALUE argv[1];
    argv[0] = INT2FIX(ITALY);
    return d_lite_new_start(1, argv, self);
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
    VALUE argv[1];
    argv[0] = INT2FIX(ENGLAND);
    return d_lite_new_start(1, argv, self);
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
    VALUE argv[1];
    argv[0] = DBL2NUM(JULIAN);
    return d_lite_new_start(1, argv, self);
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
    VALUE argv[1];
    argv[0] = DBL2NUM(GREGORIAN);
    return d_lite_new_start(1, argv, self);
}

static VALUE
sof2nof(VALUE of)
{
    if (TYPE(of) == T_STRING) {
	VALUE n = date_zone_to_diff(of);
	if (NIL_P(n))
	    of = INT2FIX(0);
	else
	    of = rb_rational_new2(n, INT2FIX(DAY_IN_SECONDS));
    }
    else if (TYPE(of) == T_FLOAT) {
	of = rb_rational_new2(f_truncate(f_mul(of, INT2FIX(DAY_IN_SECONDS))),
			      INT2FIX(DAY_IN_SECONDS));
    }
    return of;
}

static VALUE
d_right_new_offset(int argc, VALUE *argv, VALUE self)
{
    get_d1(self);
    return d_right_new(CLASS_OF(self),
		       d_lite_ajd(self),
		       (argc >= 1) ? sof2nof(argv[0]) : INT2FIX(0),
		       d_lite_start(self));
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
	return c_iforwardv(new_offset);

    rb_scan_args(argc, argv, "01", &vof);

    if (NIL_P(vof))
	rof = 0;
    else {
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof) || rof != 0)
	    return c_iforwardv(new_offset);
    }

    {
	get_d_jd(dat);

	return d_lite_new_internal_wo_civil(CLASS_OF(self),
					    dat->l.jd,
					    dat->l.sg,
					    HAVE_JD);
    }
}

static VALUE
d_right_plus(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_d1(self);
	if (TYPE(other) == T_FLOAT)
	    other = rb_rational_new2(f_round(f_mul(other, day_in_nanoseconds)),
				     day_in_nanoseconds);
	return d_right_new(CLASS_OF(self),
			   f_add(d_lite_ajd(self), other),
			   d_lite_offset(self),
			   d_lite_start(self));
    }
    rb_raise(rb_eTypeError, "expected numeric");
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

    if (!light_mode_p(dat))
	return c_iforwardop(plus);

    switch (TYPE(other)) {
      case T_FIXNUM:
	{
	    long jd;

	    get_d_jd(dat);

	    jd = dat->l.jd + FIX2LONG(other);

	    if (LIGHTABLE_JD(jd) && jd >= dat->l.sg)
		return d_lite_new_internal(CLASS_OF(self),
					   jd, dat->l.sg,
					   0, 0, 0,
					   (dat->l.flags | HAVE_JD) &
					   ~HAVE_CIVIL);
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
    return c_iforwardop(plus);
}

static VALUE
d_right_minus(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_d1(self);
	if (TYPE(other) == T_FLOAT)
	    other = rb_rational_new2(f_round(f_mul(other, day_in_nanoseconds)),
				     day_in_nanoseconds);
	return d_right_new(CLASS_OF(self),
			   f_sub(d_lite_ajd(self), other),
			   d_lite_offset(self),
			   d_lite_start(self));

    }
    else if (k_date_p(other)) {
	return f_sub(d_lite_ajd(self), f_ajd(other));
    }
    rb_raise(rb_eTypeError, "expected numeric");
}

static VALUE dt_right_minus(VALUE, VALUE);

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
	    r = f_add(r, rb_rational_new2(LONG2NUM(sf), day_in_nanoseconds));
	return r;
    }
    if (!k_datetime_p(self))
	return d_right_minus(self, other);
    return dt_right_minus(self, other);
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
    return c_iforwardop(minus);
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
    VALUE t, y, m, d, sg, j;

    t = f_add3(f_mul(d_lite_year(self), INT2FIX(12)),
	       f_sub(d_lite_mon(self), INT2FIX(1)),
	       other);
    y = f_idiv(t, INT2FIX(12));
    m = f_mod(t, INT2FIX(12));
    m = f_add(m, INT2FIX(1));
    d = d_lite_mday(self);
    sg = d_lite_start(self);

    while (NIL_P(j = rt__valid_civil_p(y, m, d, sg))) {
	d = f_sub(d, INT2FIX(1));
	if (f_lt_p(d, INT2FIX(1)))
	    rb_raise(rb_eArgError, "invalid date");
    }
    return f_add(self, f_sub(j, d_lite_jd(self)));
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
d_right_cmp(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_d1(self);
	return f_cmp(d_lite_ajd(self), other);
    }
    else if (k_date_p(other)) {
	return f_cmp(d_lite_ajd(self), f_ajd(other));
    }
    return rb_num_coerce_cmp(self, other, rb_intern("<=>"));
}

static VALUE dt_right_cmp(VALUE, VALUE);

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
    if (!k_datetime_p(self))
	return d_right_cmp(self, other);
    return dt_right_cmp(self, other);
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
    return c_iforwardop(cmp);
}

static VALUE
d_right_equal(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_d1(self);
	return f_eqeq_p(d_lite_jd(self), other);
    }
    else if (k_date_p(other)) {
	return f_eqeq_p(d_lite_jd(self), f_jd(other));
    }
    return rb_num_coerce_cmp(self, other, rb_intern("=="));
}

static VALUE dt_right_equal(VALUE, VALUE);

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
    if (!k_datetime_p(self))
	return d_right_equal(self, other);
    return dt_right_equal(self, other);
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
    return c_iforwardop(equal);
}

static VALUE
d_right_eql_p(VALUE self, VALUE other)
{
    if (k_date_p(other) && f_eqeq_p(self, other))
	return Qtrue;
    return Qfalse;
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
    return c_iforwardop(eql_p);
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
    return c_iforwardop(eql_p);
}

static VALUE
d_right_hash(VALUE self)
{
    get_d1(self);
    assert(!light_mode_p(dat));
    return rb_hash(dat->r.ajd);
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
	return c_iforward0(hash);
    return rb_hash(d_lite_ajd(self));
}

static VALUE
d_right_to_s(VALUE self)
{
    VALUE a, argv[4];

    get_d1(self);
    assert(!light_mode_p(dat));

    argv[0] = rb_usascii_str_new2("%.4d-%02d-%02d");
    a = d_right_civil(self);
    argv[1] = RARRAY_PTR(a)[0];
    argv[2] = RARRAY_PTR(a)[1];
    argv[3] = RARRAY_PTR(a)[2];
    return rb_f_sprintf(4, argv);
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
	return c_iforward0(to_s);
    {
	get_d_civil(dat);
	return rb_enc_sprintf(rb_usascii_encoding(),
			      "%.4d-%02d-%02d",
			      dat->l.year, dat->l.mon, dat->l.mday);
    }
}

static VALUE
d_right_inspect(VALUE self)
{
    VALUE argv[6];

    get_d1(self);
    assert(!light_mode_p(dat));

    argv[0] = rb_usascii_str_new2("#<%s[R]: %s (%s,%s,%s)>");
    argv[1] = rb_class_name(CLASS_OF(self));
    argv[2] = d_right_to_s(self);
    argv[3] = dat->r.ajd;
    argv[4] = dat->r.of;
    argv[5] = dat->r.sg;
    return rb_f_sprintf(6, argv);
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
	return c_iforward0(inspect);
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

    if (!light_mode_p(dat)) {
	tmx->year = d_right_year(self);
	tmx->yday = FIX2INT(d_right_yday(self));
	tmx->mon = FIX2INT(d_right_mon(self));
	tmx->mday = FIX2INT(d_right_mday(self));
	tmx->hour = FIX2INT(d_right_hour(self));
	tmx->min = FIX2INT(d_right_min(self));
	tmx->sec = FIX2INT(d_right_sec(self));
	tmx->wday = FIX2INT(d_right_wday(self));
	tmx->offset = f_mul(dat->r.of, INT2FIX(DAY_IN_SECONDS));
	tmx->zone = RSTRING_PTR(d_right_zone(self));
	tmx->timev = f_mul(f_sub(dat->r.ajd, UNIX_EPOCH_IN_AJD),
			   INT2FIX(DAY_IN_SECONDS));
    }
    else {
	get_d_jd(dat);
	get_d_civil(dat);

	tmx->year = LONG2NUM(dat->l.year);
	tmx->yday = civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday);
	tmx->mon = dat->l.mon;
	tmx->mday = dat->l.mday;
	tmx->hour = 0;
	tmx->min = 0;
	tmx->sec = 0;
	tmx->wday = jd_to_wday(dat->l.jd);
	tmx->offset = INT2FIX(0);
	tmx->zone = "+00:00";
	tmx->timev = f_mul(INT2FIX(dat->l.jd - 2440588),
			   INT2FIX(DAY_IN_SECONDS));
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
    VALUE argv[1], d;

    argv[0] = INT2FIX(0);
    d = d_lite_new_offset(1, argv, self);
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

    if (!gengo(d_lite_jd(self),
	       d_lite_year(self),
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

/* datetime light */

static void
dt_right_gc_mark(union DateTimeData *dat)
{
    assert(!light_mode_p(dat));
    rb_gc_mark(dat->r.ajd);
    rb_gc_mark(dat->r.of);
    rb_gc_mark(dat->r.sg);
    rb_gc_mark(dat->r.cache);
}

#define dt_lite_gc_mark 0

inline static VALUE
dt_right_new_internal(VALUE klass, VALUE ajd, VALUE of, VALUE sg,
		      unsigned flags)
{
    union DateTimeData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateTimeData,
			   dt_right_gc_mark, -1, dat);

    dat->r.ajd = ajd;
    dat->r.of = of;
    dat->r.sg = sg;
    dat->r.cache = rb_hash_new();
    dat->r.flags = flags | DATETIME_OBJ;

    return obj;
}

inline static VALUE
dt_lite_new_internal(VALUE klass, long jd, int df,
		     long sf, int of, double sg,
		     int y, int m, int d,
		     int h, int min, int s,
		     unsigned flags)
{
    union DateTimeData *dat;
    VALUE obj;

    obj = Data_Make_Struct(klass, union DateTimeData,
			   dt_lite_gc_mark, -1, dat);

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
    dat->l.flags = flags | LIGHT_MODE | DATETIME_OBJ;

    return obj;
}

static VALUE
dt_lite_new_internal_wo_civil(VALUE klass, long jd, int df,
			      long sf, int of, double sg,
			      unsigned flags)
{
    return dt_lite_new_internal(klass, jd, df, sf, of, sg,
				  0, 0, 0, 0, 0, 0, flags);
}

static VALUE
dt_lite_s_alloc(VALUE klass)
{
    return dt_lite_new_internal_wo_civil(klass, 0, 0, 0, 0, 0, 0);
}

static VALUE
dt_right_new(VALUE klass, VALUE ajd, VALUE of, VALUE sg)
{
    return dt_right_new_internal(klass, ajd, of, sg, 0);
}

static VALUE
dt_lite_new(VALUE klass, VALUE jd, VALUE df, VALUE sf, VALUE of, VALUE sg)
{
    return dt_lite_new_internal_wo_civil(klass,
					 NUM2LONG(jd),
					 FIX2INT(df),
					 NUM2LONG(sf),
					 FIX2INT(of),
					 NUM2DBL(sg),
					 HAVE_JD | HAVE_DF);
}

static VALUE
dt_switch_new(VALUE klass, VALUE ajd, VALUE of, VALUE sg)
{
    VALUE t, jd, df, sf, ssf, odf, osf;

    t = rt_ajd_to_jd(ajd, INT2FIX(0)); /* as utc */
    jd = RARRAY_PTR(t)[0];
    df = RARRAY_PTR(t)[1];

    t = f_mul(df, INT2FIX(DAY_IN_SECONDS));
    df = f_idiv(t, INT2FIX(1));
    sf = f_mod(t, INT2FIX(1));

    t = f_mul(sf, INT2FIX(SECOND_IN_NANOSECONDS));
    sf = f_idiv(t, INT2FIX(1));
    ssf = f_mod(t, INT2FIX(1));

    t = f_mul(of, INT2FIX(DAY_IN_SECONDS));
    odf = f_truncate(t);
    osf = f_remainder(t, INT2FIX(1));

#ifdef FORCE_RIGHT
    if (1)
#else
    if (!FIXNUM_P(jd) ||
	f_lt_p(jd, sg) || !f_zero_p(ssf) || !f_zero_p(osf) ||
	!LIGHTABLE_JD(NUM2LONG(jd)))
#endif
	return dt_right_new(klass, ajd, of, sg);
    else
	return dt_lite_new(klass, jd, df, sf, odf, sg);
}

#ifndef NDEBUG
static VALUE
dt_right_new_m(int argc, VALUE *argv, VALUE klass)
{
    VALUE ajd, of, sg;

    rb_scan_args(argc, argv, "03", &ajd, &of, &sg);

    switch (argc) {
      case 0:
	ajd = INT2FIX(0);
      case 1:
	of = INT2FIX(0);
      case 2:
	sg = INT2FIX(ITALY);
    }

    return dt_right_new(klass, ajd, of, sg);
}

static VALUE
dt_lite_new_m(int argc, VALUE *argv, VALUE klass)
{
    VALUE jd, df, sf, of, sg;

    rb_scan_args(argc, argv, "05", &jd, &df, &sf, &of, &sg);

    switch (argc) {
      case 0:
	jd = INT2FIX(0);
      case 1:
	df = INT2FIX(0);
      case 2:
	sf = INT2FIX(0);
      case 3:
	of = INT2FIX(0);
      case 4:
	sg = INT2FIX(ITALY);
    }

    return dt_lite_new(klass, jd, df, sf, of, sg);
}

static VALUE
dt_switch_new_m(int argc, VALUE *argv, VALUE klass)
{
    VALUE ajd, of, sg;

    rb_scan_args(argc, argv, "03", &ajd, &of, &sg);

    switch (argc) {
      case 0:
	ajd = INT2FIX(0);
      case 1:
	of = INT2FIX(0);
      case 2:
	sg = INT2FIX(ITALY);
    }

    return dt_switch_new(klass, ajd, of, sg);
}
#endif

static VALUE
dt_right_new_jd(VALUE klass, VALUE jd, VALUE fr, VALUE of, VALUE sg)
{
    return dt_right_new(klass,
			rt_jd_to_ajd(jd, fr, of),
			of,
			sg);
}

#ifndef NDEBUG
static VALUE
dt_lite_new_jd(VALUE klass, VALUE jd, VALUE fr, VALUE of, VALUE sg)
{
    VALUE n, df, sf;

    n = f_mul(fr, INT2FIX(DAY_IN_SECONDS));
    df = f_idiv(n, INT2FIX(1));
    sf = f_mod(n, INT2FIX(1));
    n = f_mul(sf, INT2FIX(SECOND_IN_NANOSECONDS));
    sf = f_idiv(n, INT2FIX(1));
    return dt_lite_new(klass, jd, df, sf, of, sg);
}
#endif

static VALUE
dt_switch_new_jd(VALUE klass, VALUE jd, VALUE fr, VALUE of, VALUE sg)
{
    return dt_switch_new(klass,
			 rt_jd_to_ajd(jd, fr, of),
			 of,
			 sg);
}

#ifndef NDEBUG
static VALUE
datetime_s_new_r_bang(int argc, VALUE *argv, VALUE klass)
{
    return dt_right_new_m(argc, argv, klass);
}

static VALUE
datetime_s_new_l_bang(int argc, VALUE *argv, VALUE klass)
{
    return dt_lite_new_m(argc, argv, klass);
}

static VALUE
datetime_s_new_bang(int argc, VALUE *argv, VALUE klass)
{
    return dt_switch_new_m(argc, argv, klass);
}
#endif

#undef c_cforwardv
#define c_cforwardv(m) rt_datetime_s_##m(argc, argv, klass)

static VALUE
rt_datetime_s_jd(int argc, VALUE *argv, VALUE klass)
{
    VALUE jd, h, min, s, of, sg, fr;

    rb_scan_args(argc, argv, "06", &jd, &h, &min, &s, &of, &sg);

    switch (argc) {
      case 0:
	jd = INT2FIX(0);
      case 1:
	h = INT2FIX(0);
      case 2:
	min = INT2FIX(0);
      case 3:
	s = INT2FIX(0);
      case 4:
	of = INT2FIX(0);
      case 5:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_jd_p(jd, sg);
    fr = rt__valid_time_p(h, min, s);

    if (NIL_P(jd) || NIL_P(fr))
	rb_raise(rb_eArgError, "invalid date");

    of = sof2nof(of);

    return dt_right_new_jd(klass, jd, fr, of, sg);
}

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
    VALUE vjd, vh, vmin, vs, vof, vsg;
    long jd;
    int h, min, s, rh, rmin, rs, rof;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(jd);
#endif

    rb_scan_args(argc, argv, "06", &vjd, &vh, &vmin, &vs, &vof, &vsg);

    if (!FIXNUM_P(vjd))
	return c_cforwardv(jd);

    jd = h = min = s = 0;
    rof = 0;
    sg = ITALY;

    switch (argc) {
      case 6:
	sg = NUM2DBL(vsg);
      case 5:
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof))
	    return c_cforwardv(jd);
      case 4:
	s = NUM2INT(vs);
      case 3:
	min = NUM2INT(vmin);
      case 2:
	h = NUM2INT(vh);
      case 1:
	jd = NUM2LONG(vjd);
	if (!LIGHTABLE_JD(jd))
	    return c_cforwardv(jd);
    }

    if (jd < sg)
	return c_cforwardv(jd);

    if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	rb_raise(rb_eArgError, "invalid date");

    return dt_lite_new_internal(klass,
				jd_local_to_utc(jd,
						time_to_df(rh, rmin, rs),
						rof),
				0, 0, rof, sg, 0, 0, 0, rh, rmin, rs,
				HAVE_JD | HAVE_TIME);
}

static VALUE
rt_datetime_s_ordinal(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, d, h, min, s, of, sg, jd, fr;

    rb_scan_args(argc, argv, "07", &y, &d, &h, &min, &s, &of, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	d = INT2FIX(1);
      case 2:
	h = INT2FIX(0);
      case 3:
	min = INT2FIX(0);
      case 4:
	s = INT2FIX(0);
      case 5:
	of = INT2FIX(0);
      case 6:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_ordinal_p(y, d, sg);
    fr = rt__valid_time_p(h, min, s);

    if (NIL_P(jd) || NIL_P(fr))
	rb_raise(rb_eArgError, "invalid date");

    of = sof2nof(of);

    return dt_right_new_jd(klass, jd, fr, of, sg);
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
    VALUE vy, vd, vh, vmin, vs, vof, vsg;
    int y, d, rd, h, min, s, rh, rmin, rs, rof;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(ordinal);
#endif

    rb_scan_args(argc, argv, "07", &vy, &vd, &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vd)   || FIXNUM_P(vd)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return c_cforwardv(ordinal);

    y = -4712;
    d = 1;

    h = min = s = 0;
    rof = 0;
    sg = ITALY;

    switch (argc) {
      case 7:
	sg = NUM2DBL(vsg);
      case 6:
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof))
	    return c_cforwardv(ordinal);
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
	    return c_cforwardv(ordinal);
    }

    {
	long jd;
	int ns;

	if (!valid_ordinal_p(y, d, sg, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(ordinal);

	return dt_lite_new_internal(klass,
				    jd_local_to_utc(jd,
						    time_to_df(rh, rmin, rs),
						    rof),
				    0, 0, rof, sg,
				    0, 0, 0, rh, rmin, rs,
				    HAVE_JD | HAVE_TIME);
    }
}

static VALUE
rt_datetime_s_civil(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, m, d, h, min, s, of, sg, jd, fr;

    rb_scan_args(argc, argv, "08", &y, &m, &d, &h, &min, &s, &of, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	m = INT2FIX(1);
      case 2:
	d = INT2FIX(1);
      case 3:
	h = INT2FIX(0);
      case 4:
	min = INT2FIX(0);
      case 5:
	s = INT2FIX(0);
      case 6:
	of = INT2FIX(0);
      case 7:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_civil_p(y, m, d, sg);
    fr = rt__valid_time_p(h, min, s);

    if (NIL_P(jd) || NIL_P(fr))
	rb_raise(rb_eArgError, "invalid date");

    of = sof2nof(of);

    return dt_right_new_jd(klass, jd, fr, of, sg);
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
    VALUE vy, vm, vd, vh, vmin, vs, vof, vsg;
    int y, m, d, rm, rd, h, min, s, rh, rmin, rs, rof;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(civil);
#endif

    rb_scan_args(argc, argv, "08", &vy, &vm, &vd, &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vm)   || FIXNUM_P(vm)) &&
	  (NIL_P(vd)   || FIXNUM_P(vd)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return c_cforwardv(civil);

    y = -4712;
    m = 1;
    d = 1;

    h = min = s = 0;
    rof = 0;
    sg = ITALY;

    switch (argc) {
      case 8:
	sg = NUM2DBL(vsg);
      case 7:
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof))
	    return c_cforwardv(civil);
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
	    return c_cforwardv(civil);
    }

    if (isinf(sg) && sg < 0) {
	if (!valid_gregorian_p(y, m, d, &rm, &rd))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	return dt_lite_new_internal(klass, 0, 0, 0, rof, sg,
				    y, rm, rd, rh, rmin, rs,
				    HAVE_CIVIL | HAVE_TIME);
    }
    else {
	long jd;
	int ns;

	if (!valid_civil_p(y, m, d, sg, &rm, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(civil);

	return dt_lite_new_internal(klass,
				    jd_local_to_utc(jd,
						    time_to_df(rh, rmin, rs),
						    rof),
				    0, 0, rof, sg,
				    y, rm, rd, rh, rmin, rs,
				    HAVE_JD | HAVE_CIVIL | HAVE_TIME);
    }
}

static VALUE
rt_datetime_s_commercial(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, w, d, h, min, s, of, sg, jd, fr;

    rb_scan_args(argc, argv, "08", &y, &w, &d, &h, &min, &s, &of, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	w = INT2FIX(1);
      case 2:
	d = INT2FIX(1);
      case 3:
	h = INT2FIX(0);
      case 4:
	min = INT2FIX(0);
      case 5:
	s = INT2FIX(0);
      case 6:
	of = INT2FIX(0);
      case 7:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_commercial_p(y, w, d, sg);
    fr = rt__valid_time_p(h, min, s);

    if (NIL_P(jd) || NIL_P(fr))
	rb_raise(rb_eArgError, "invalid date");

    of = sof2nof(of);

    return dt_right_new_jd(klass, jd, fr, of, sg);
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
    VALUE vy, vw, vd, vh, vmin, vs, vof, vsg;
    int y, w, d, rw, rd, h, min, s, rh, rmin, rs, rof;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(commercial);
#endif

    rb_scan_args(argc, argv, "08", &vy, &vw, &vd, &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vw)   || FIXNUM_P(vw)) &&
	  (NIL_P(vd)   || FIXNUM_P(vd)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return c_cforwardv(commercial);

    y = -4712;
    w = 1;
    d = 1;

    h = min = s = 0;
    rof = 0;
    sg = ITALY;

    switch (argc) {
      case 8:
	sg = NUM2DBL(vsg);
      case 7:
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof))
	    return c_cforwardv(commercial);
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
	    return c_cforwardv(commercial);
    }

    {
	long jd;
	int ns;

	if (!valid_commercial_p(y, w, d, sg, &rw, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(commercial);

	return dt_lite_new_internal(klass,
				    jd_local_to_utc(jd,
						    time_to_df(rh, rmin, rs),
						    rof),
				    0, 0, rof, sg,
				    0, 0, 0, rh, rmin, rs,
				    HAVE_JD | HAVE_TIME);
    }
}

#ifndef NDEBUG
static VALUE
rt_datetime_s_weeknum(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, w, d, f, h, min, s, of, sg, jd, fr;

    rb_scan_args(argc, argv, "09", &y, &w, &d, &f, &h, &min, &s, &of, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	w = INT2FIX(0);
      case 2:
	d = INT2FIX(1);
      case 3:
	f = INT2FIX(0);
      case 4:
	h = INT2FIX(0);
      case 5:
	min = INT2FIX(0);
      case 6:
	s = INT2FIX(0);
      case 7:
	of = INT2FIX(0);
      case 8:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_weeknum_p(y, w, d, f, sg);
    fr = rt__valid_time_p(h, min, s);

    if (NIL_P(jd) || NIL_P(fr))
	rb_raise(rb_eArgError, "invalid date");

    of = sof2nof(of);

    return dt_right_new_jd(klass, jd, fr, of, sg);
}

static VALUE
datetime_s_weeknum(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vw, vd, vf, vh, vmin, vs, vof, vsg;
    int y, w, d, f, rw, rd, h, min, s, rh, rmin, rs, rof;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(weeknum);
#endif

    rb_scan_args(argc, argv, "09", &vy, &vw, &vd, &vf,
		 &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vw)   || FIXNUM_P(vw)) &&
	  (NIL_P(vd)   || FIXNUM_P(vd)) &&
	  (NIL_P(vf)   || FIXNUM_P(vf)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return c_cforwardv(weeknum);

    y = -4712;
    w = 0;
    d = 1;
    f = 0;

    h = min = s = 0;
    rof = 0;
    sg = ITALY;

    switch (argc) {
      case 9:
	sg = NUM2DBL(vsg);
      case 8:
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof))
	    return c_cforwardv(weeknum);
      case 7:
	s = NUM2INT(vs);
      case 6:
	min = NUM2INT(vmin);
      case 5:
	h = NUM2INT(vh);
      case 4:
	f = NUM2INT(vf);
      case 3:
	d = NUM2INT(vd);
      case 2:
	w = NUM2INT(vw);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return c_cforwardv(weeknum);
    }

    {
	long jd;
	int ns;

	if (!valid_weeknum_p(y, w, d, f, sg, &rw, &rd, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(weeknum);

	return dt_lite_new_internal(klass,
				    jd_local_to_utc(jd,
						    time_to_df(rh, rmin, rs),
						    rof),
				    0, 0, rof, sg,
				    0, 0, 0, rh, rmin, rs,
				    HAVE_JD | HAVE_TIME);
    }
}

static VALUE
rt_datetime_s_nth_kday(int argc, VALUE *argv, VALUE klass)
{
    VALUE y, m, n, k, h, min, s, of, sg, jd, fr;

    rb_scan_args(argc, argv, "09", &y, &m, &n, &k, &h, &min, &s, &of, &sg);

    switch (argc) {
      case 0:
	y = INT2FIX(-4712);
      case 1:
	m = INT2FIX(1);
      case 2:
	n = INT2FIX(1);
      case 3:
	k = INT2FIX(1);
      case 4:
	h = INT2FIX(0);
      case 5:
	min = INT2FIX(0);
      case 6:
	s = INT2FIX(0);
      case 7:
	of = INT2FIX(0);
      case 8:
	sg = INT2FIX(ITALY);
    }

    jd = rt__valid_nth_kday_p(y, m, n, k, sg);
    fr = rt__valid_time_p(h, min, s);

    if (NIL_P(jd) || NIL_P(fr))
	rb_raise(rb_eArgError, "invalid date");

    of = sof2nof(of);

    return dt_right_new_jd(klass, jd, fr, of, sg);
}

static VALUE
datetime_s_nth_kday(int argc, VALUE *argv, VALUE klass)
{
    VALUE vy, vm, vn, vk, vh, vmin, vs, vof, vsg;
    int y, m, n, k, rm, rn, rk, h, min, s, rh, rmin, rs, rof;
    double sg;

#ifdef FORCE_RIGHT
    return c_cforwardv(nth_kday);
#endif

    rb_scan_args(argc, argv, "09", &vy, &vm, &vn, &vk,
		 &vh, &vmin, &vs, &vof, &vsg);

    if (!((NIL_P(vy)   || FIXNUM_P(vy)) &&
	  (NIL_P(vm)   || FIXNUM_P(vm)) &&
	  (NIL_P(vn)   || FIXNUM_P(vn)) &&
	  (NIL_P(vk)   || FIXNUM_P(vk)) &&
	  (NIL_P(vh)   || FIXNUM_P(vh)) &&
	  (NIL_P(vmin) || FIXNUM_P(vmin)) &&
	  (NIL_P(vs)   || FIXNUM_P(vs))))
	return c_cforwardv(nth_kday);

    y = -4712;
    m = 1;
    n = 1;
    k = 1;

    h = min = s = 0;
    rof = 0;
    sg = ITALY;

    switch (argc) {
      case 9:
	sg = NUM2DBL(vsg);
      case 8:
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof))
	    return c_cforwardv(nth_kday);
      case 7:
	s = NUM2INT(vs);
      case 6:
	min = NUM2INT(vmin);
      case 5:
	h = NUM2INT(vh);
      case 4:
	k = NUM2INT(vk);
      case 3:
	n = NUM2INT(vn);
      case 2:
	m = NUM2INT(vm);
      case 1:
	y = NUM2INT(vy);
	if (!LIGHTABLE_YEAR(y))
	    return c_cforwardv(nth_kday);
    }

    {
	long jd;
	int ns;

	if (!valid_nth_kday_p(y, m, n, k, sg, &rm, &rn, &rk, &jd, &ns))
	    rb_raise(rb_eArgError, "invalid date");
	if (!valid_time_p(h, min, s, &rh, &rmin, &rs))
	    rb_raise(rb_eArgError, "invalid date");

	if (!LIGHTABLE_JD(jd) || !ns)
	    return c_cforwardv(nth_kday);

	return dt_lite_new_internal(klass,
				    jd_local_to_utc(jd,
						    time_to_df(rh, rmin, rs),
						    rof),
				    0, 0, rof, sg,
				    0, 0, 0, rh, rmin, rs,
				    HAVE_JD | HAVE_TIME);
    }
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
    VALUE vsg;
    double sg;
#ifdef HAVE_CLOCK_GETTIME
    struct timespec ts;
#else
    struct timeval tv;
#endif
    time_t sec;
    struct tm tm;
    long sf, of;
    int y, m, d, h, min, s;

    rb_scan_args(argc, argv, "01", &vsg);

    if (argc < 1)
	sg = ITALY;
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

#ifdef FORCE_RIGHT
    goto right;
#endif

    if (!LIGHTABLE_YEAR(y))
	goto right;

    if (of < -DAY_IN_SECONDS || of > DAY_IN_SECONDS)
	goto right;

    if (isinf(sg) && sg < 0)
	return dt_lite_new_internal(klass, 0, 0, sf, (int)of, sg,
				    y, m, d, h, min, s,
				    HAVE_CIVIL | HAVE_TIME);
    else {
	long jd;
	int ns;

	civil_to_jd(y, m, d, sg, &jd, &ns);

	return dt_lite_new_internal(klass,
				    jd_local_to_utc(jd,
						    time_to_df(h, min, s),
						    of),
				    0, sf, of, sg,
				    y, m, d, h, min, s,
				    HAVE_JD | HAVE_CIVIL | HAVE_TIME);
    }
  right:
    {
	VALUE jd, fr, vof, ajd;

	jd = rt_civil_to_jd(INT2FIX(y), INT2FIX(m), INT2FIX(d), DBL2NUM(sg));
	fr = rt_time_to_day_fraction(INT2FIX(h), INT2FIX(min), INT2FIX(s));
	fr = f_add(fr, rb_rational_new(LONG2NUM(sf), day_in_nanoseconds));
	vof = rb_rational_new(LONG2NUM(of), INT2FIX(DAY_IN_SECONDS));
	ajd = rt_jd_to_ajd(jd, fr, vof);
	return dt_right_new(klass, ajd, vof, DBL2NUM(sg));
    }
}

static VALUE
dt_switch_new_by_frags(VALUE klass, VALUE hash, VALUE sg)
{
    VALUE jd, fr, of, t;

    hash = rt_rewrite_frags(hash);
    hash = rt_complete_frags(klass, hash);
    jd = rt__valid_date_frags_p(hash, sg);
    fr = rt__valid_time_frags_p(hash);
    if (NIL_P(jd) || NIL_P(fr))
	rb_raise(rb_eArgError, "invalid date");
    t = ref_hash("sec_fraction");
    if (!NIL_P(t))
	fr = f_add(fr, f_div(t, INT2FIX(DAY_IN_SECONDS)));
    t = ref_hash("offset");
    if (NIL_P(t))
	of = INT2FIX(0);
    else
	of = rb_rational_new2(t, INT2FIX(DAY_IN_SECONDS));
    return dt_switch_new_jd(klass, jd, fr, of, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = fmt;
	hash = date_s__strptime(2, argv2, klass);
	return dt_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE argv2[2], hash;

	argv2[0] = str;
	argv2[1] = comp;
	hash = date_s__parse(2, argv2, klass);
	return dt_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__iso8601(klass, str);
	return dt_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__rfc3339(klass, str);
	return dt_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__xmlschema(klass, str);
	return dt_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__rfc2822(klass, str);
	return dt_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__httpdate(klass, str);
	return dt_switch_new_by_frags(klass, hash, sg);
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
	sg = INT2FIX(ITALY);
    }

    {
	VALUE hash = date_s__jisx0301(klass, str);
	return dt_switch_new_by_frags(klass, hash, sg);
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

#undef c_iforward0
#undef c_iforwardv
#undef c_iforwardop
#define c_iforward0(m) dt_right_##m(self)
#define c_iforwardv(m) dt_right_##m(argc, argv, self)
#define c_iforwardop(m) dt_right_##m(self, other)

static VALUE
dt_right_amjd(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return rt_ajd_to_amjd(dat->r.ajd);
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
	return c_iforward0(amjd);
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

#undef return_once
#define return_once(k, expr)\
{\
    VALUE id, val;\
    get_dt1(self);\
    id = ID2SYM(rb_intern(#k));\
    val = rb_hash_aref(dat->r.cache, id);\
    if (!NIL_P(val))\
	return val;\
    val = expr;\
    rb_hash_aset(dat->r.cache, id, val);\
    return val;\
}

static VALUE
dt_right_daynum(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(daynum, rt_ajd_to_jd(dat->r.ajd, dat->r.of));
}

static VALUE
dt_right_jd(VALUE self)
{
    return RARRAY_PTR(c_iforward0(daynum))[0];
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
	return c_iforward0(jd);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	return INT2FIX(local_jd(dat));
    }
}

static VALUE
dt_right_mjd(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return rt_jd_to_mjd(dt_right_jd(self));
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
	return c_iforward0(mjd);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	return LONG2NUM(local_jd(dat) - 2400001L);
    }
}

static VALUE
dt_right_ld(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return rt_jd_to_ld(dt_right_jd(self));
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
	return c_iforward0(ld);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	return LONG2NUM(local_jd(dat) - 2299160L);
    }
}

static VALUE
dt_right_civil(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(civil, rt_jd_to_civil(dt_right_jd(self), dat->r.sg));
}

static VALUE
dt_right_year(VALUE self)
{
    return RARRAY_PTR(c_iforward0(civil))[0];
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
	return c_iforward0(year);
    {
	get_dt_civil(dat);
	return INT2FIX(dat->l.year);
    }
}

static VALUE
dt_right_ordinal(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(ordinal, rt_jd_to_ordinal(dt_right_jd(self), dat->r.sg));
}

static VALUE
dt_right_yday(VALUE self)
{
    return RARRAY_PTR(c_iforward0(ordinal))[1];
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
	return c_iforward0(yday);
    {
	get_dt_civil(dat);
	return INT2FIX(civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday));
    }
}

static VALUE
dt_right_mon(VALUE self)
{
    return RARRAY_PTR(c_iforward0(civil))[1];
}

/*
 * call-seq:
 *    dt.mon
 *    dt.month
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
	return c_iforward0(mon);
    {
	get_dt_civil(dat);
	return INT2FIX(dat->l.mon);
    }
}

static VALUE
dt_right_mday(VALUE self)
{
    return RARRAY_PTR(c_iforward0(civil))[2];
}

/*
 * call-seq:
 *    dt.mday
 *    dt.day
 *
 * Get the day-of-the-month of this date.
 */
static VALUE
dt_lite_mday(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return c_iforward0(mday);
    {
	get_dt_civil(dat);
	return INT2FIX(dat->l.mday);
    }
}

static VALUE
dt_right_day_fraction(VALUE self)
{
    return RARRAY_PTR(c_iforward0(daynum))[1];
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
	return c_iforward0(day_fraction);
    {
	get_dt_df(dat);
	return rb_rational_new2(INT2FIX(local_df(dat)),
				INT2FIX(DAY_IN_SECONDS));
    }
}

static VALUE
dt_right_weeknum0(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(weeknum0, rt_jd_to_weeknum(dt_right_jd(self),
					   INT2FIX(0), dat->r.sg));
}

static VALUE
dt_right_wnum0(VALUE self)
{
    return RARRAY_PTR(c_iforward0(weeknum0))[1];
}

static VALUE
dt_lite_wnum0(VALUE self)
{
    int ry, rw, rd;

    get_dt1(self);
    if (!light_mode_p(dat))
	return c_iforward0(wnum0);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_weeknum(local_jd(dat), 0, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

static VALUE
dt_right_weeknum1(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(weeknum1, rt_jd_to_weeknum(dt_right_jd(self),
					   INT2FIX(1), dat->r.sg));
}

static VALUE
dt_right_wnum1(VALUE self)
{
    return RARRAY_PTR(c_iforward0(weeknum1))[1];
}

static VALUE
dt_lite_wnum1(VALUE self)
{
    int ry, rw, rd;

    get_dt1(self);
    if (!light_mode_p(dat))
	return c_iforward0(wnum1);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_weeknum(local_jd(dat), 1, dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

#ifndef NDEBUG
static VALUE
dt_right_time(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(time, rt_day_fraction_to_time(dt_right_day_fraction(self)));
}
#endif

static VALUE
dt_right_time_wo_sf(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(time_wo_sf,
		rt_day_fraction_to_time_wo_sf(dt_right_day_fraction(self)));
}

static VALUE
dt_right_time_sf(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(time_sf, f_mul(f_mod(dt_right_day_fraction(self),
				     SECONDS_IN_DAY),
			       INT2FIX(DAY_IN_SECONDS)));
}

static VALUE
dt_right_hour(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[0];
#else
    return RARRAY_PTR(c_iforward0(time_wo_sf))[0];
#endif
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
	return c_iforward0(hour);
    {
	get_dt_time(dat);
	return INT2FIX(dat->l.hour);
    }
}

static VALUE
dt_right_min(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[1];
#else
    return RARRAY_PTR(c_iforward0(time_wo_sf))[1];
#endif
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
	return c_iforward0(min);
    {
	get_dt_time(dat);
	return INT2FIX(dat->l.min);
    }
}

static VALUE
dt_right_sec(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[2];
#else
    return RARRAY_PTR(c_iforward0(time_wo_sf))[2];
#endif
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
	return c_iforward0(sec);
    {
	get_dt_time(dat);
	return INT2FIX(dat->l.sec);
    }
}

static VALUE
dt_right_sec_fraction(VALUE self)
{
#if 0
    return RARRAY_PTR(c_iforward0(time))[3];
#else
    return c_iforward0(time_sf);
#endif
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
	return c_iforward0(sec_fraction);
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
    h = a / HOUR_IN_SECONDS;\
    m = a % HOUR_IN_SECONDS / MINUTE_IN_SECONDS;\
}

static VALUE
dt_right_zone(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    {
	int sign;
	VALUE hh, mm, ss, fr;

	if (f_negative_p(dat->r.of)) {
	    sign = '-';
	    fr = f_abs(dat->r.of);
	}
	else {
	    sign = '+';
	    fr = dat->r.of;
	}
	ss = f_div(fr, SECONDS_IN_DAY);

	hh = f_idiv(ss, INT2FIX(HOUR_IN_SECONDS));
	ss = f_mod(ss, INT2FIX(HOUR_IN_SECONDS));

	mm = f_idiv(ss, INT2FIX(MINUTE_IN_SECONDS));

	return rb_enc_sprintf(rb_usascii_encoding(),
			      "%c%02d:%02d",
			      sign, NUM2INT(hh), NUM2INT(mm));
    }
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
	return c_iforward0(zone);
    decode_offset(dat->l.of, s, h, m);
    return rb_enc_sprintf(rb_usascii_encoding(), "%c%02d:%02d", s, h, m);
}

static VALUE
dt_right_commercial(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return_once(commercial, rt_jd_to_commercial(dt_right_jd(self), dat->r.sg));
}

static VALUE
dt_right_cwyear(VALUE self)
{
    return RARRAY_PTR(c_iforward0(commercial))[0];
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
	return c_iforward0(cwyear);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_commercial(local_jd(dat), dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(ry);
    }
}

static VALUE
dt_right_cweek(VALUE self)
{
    return RARRAY_PTR(c_iforward0(commercial))[1];
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
	return c_iforward0(cweek);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	jd_to_commercial(local_jd(dat), dat->l.sg, &ry, &rw, &rd);
	return INT2FIX(rw);
    }
}

static VALUE
dt_right_cwday(VALUE self)
{
    return RARRAY_PTR(c_iforward0(commercial))[2];
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
	return c_iforward0(cwday);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	w = jd_to_wday(local_jd(dat));
	if (w == 0)
	    w = 7;
	return INT2FIX(w);
    }
}

static VALUE
dt_right_wday(VALUE self)
{
    return rt_jd_to_wday(dt_right_jd(self));
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
	return c_iforward0(wday);
    {
	get_dt_jd(dat);
	get_dt_df(dat);
	w = jd_to_wday(local_jd(dat));
	return INT2FIX(w);
    }
}

/*
 * call-seq:
 *    dt.monday?
 *
 * Is the current date Monday?
 */
static VALUE
dt_lite_sunday_p(VALUE self)
{
    return f_eqeq_p(dt_lite_wday(self), INT2FIX(0));
}

/*
 * call-seq:
 *    dt.monday?
 *
 * Is the current date Monday?
 */
static VALUE
dt_lite_monday_p(VALUE self)
{
    return f_eqeq_p(dt_lite_wday(self), INT2FIX(1));
}

/*
 * call-seq:
 *    dt.tuesday?
 *
 * Is the current date Tuesday?
 */
static VALUE
dt_lite_tuesday_p(VALUE self)
{
    return f_eqeq_p(dt_lite_wday(self), INT2FIX(2));
}

/*
 * call-seq:
 *    dt.wednesday?
 *
 * Is the current date Wednesday?
 */
static VALUE
dt_lite_wednesday_p(VALUE self)
{
    return f_eqeq_p(dt_lite_wday(self), INT2FIX(3));
}

/*
 * call-seq:
 *    dt.thursday?
 *
 * Is the current date Thursday?
 */
static VALUE
dt_lite_thursday_p(VALUE self)
{
    return f_eqeq_p(dt_lite_wday(self), INT2FIX(4));
}

/*
 * call-seq:
 *    dt.friday?
 *
 * Is the current date Friday?
 */
static VALUE
dt_lite_friday_p(VALUE self)
{
    return f_eqeq_p(dt_lite_wday(self), INT2FIX(5));
}

/*
 * call-seq:
 *    dt.saturday?
 *
 * Is the current date Saturday?
 */
static VALUE
dt_lite_saturday_p(VALUE self)
{
    return f_eqeq_p(dt_lite_wday(self), INT2FIX(6));
}

static VALUE
dt_right_julian_p(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return f_lt_p(dt_right_jd(self), dat->r.sg);
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
	return c_iforward0(julian_p);
    return Qfalse;
}

static VALUE
dt_right_gregorian_p(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return dt_right_julian_p(self) ? Qfalse : Qtrue;
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
	return c_iforward0(gregorian_p);
    return Qtrue;
}

static VALUE
dt_right_fix_style(VALUE self)
{
    if (dt_right_julian_p(self))
	return DBL2NUM(JULIAN);
    return DBL2NUM(GREGORIAN);
}

static VALUE
dt_right_leap_p(VALUE self)
{
    VALUE style, a;

    style = dt_right_fix_style(self);
    a = rt_jd_to_civil(f_sub(rt_civil_to_jd(dt_right_year(self),
					    INT2FIX(3), INT2FIX(1), style),
			     INT2FIX(1)),
		       style);
    if (f_eqeq_p(RARRAY_PTR(a)[2], INT2FIX(29)))
	return Qtrue;
    return Qfalse;
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
	return c_iforward0(leap_p);
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

static VALUE
dt_right_new_start(int argc, VALUE *argv, VALUE self)
{
    get_dt1(self);
    return dt_right_new(CLASS_OF(self),
			dt_lite_ajd(self),
			dt_lite_offset(self),
			(argc >= 1) ? argv[0] : INT2FIX(ITALY));
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
	return c_iforwardv(new_start);

    rb_scan_args(argc, argv, "01", &vsg);

    sg = ITALY;
    if (argc >= 1)
	sg = NUM2DBL(vsg);

    {
	get_dt_jd(dat);
	get_dt_df(dat);

	if (dat->l.jd < sg)
	    return c_iforwardv(new_start);

	return dt_lite_new_internal_wo_civil(CLASS_OF(self),
					     dat->l.jd,
					     dat->l.df,
					     dat->l.sf,
					     dat->l.of,
					     sg,
					     HAVE_JD | HAVE_DF);
    }
}

/*
 * call-seq:
 *    dt.italy
 *
 * Create a copy of this Date object that uses the Italian/Catholic
 * Day of Calendar Reform.
 */
static VALUE
dt_lite_italy(VALUE self)
{
    VALUE argv[1];
    argv[0] = INT2FIX(ITALY);
    return dt_lite_new_start(1, argv, self);
}

/*
 * call-seq:
 *    dt.england
 *
 * Create a copy of this Date object that uses the English/Colonial
 * Day of Calendar Reform.
 */
static VALUE
dt_lite_england(VALUE self)
{
    VALUE argv[1];
    argv[0] = INT2FIX(ENGLAND);
    return dt_lite_new_start(1, argv, self);
}

/*
 * call-seq:
 *    dt.julian
 *
 * Create a copy of this Date object that always uses the Julian
 * Calendar.
 */
static VALUE
dt_lite_julian(VALUE self)
{
    VALUE argv[1];
    argv[0] = DBL2NUM(JULIAN);
    return dt_lite_new_start(1, argv, self);
}

/*
 * call-seq:
 *    dt.gregorian
 *
 * Create a copy of this Date object that always uses the Gregorian
 * Calendar.
 */
static VALUE
dt_lite_gregorian(VALUE self)
{
    VALUE argv[1];
    argv[0] = DBL2NUM(GREGORIAN);
    return dt_lite_new_start(1, argv, self);
}

static VALUE
dt_right_new_offset(int argc, VALUE *argv, VALUE self)
{
    get_dt1(self);
    return dt_right_new(CLASS_OF(self),
			dt_lite_ajd(self),
			(argc >= 1) ? sof2nof(argv[0]) : INT2FIX(0),
			dt_lite_start(self));
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
	return c_iforwardv(new_offset);

    rb_scan_args(argc, argv, "01", &vof);

    if (NIL_P(vof))
	rof = 0;
    else {
	vof = sof2nof(vof);
	if (!daydiff_to_sec(vof, &rof))
	    return c_iforwardv(new_offset);
    }

    {
	get_dt_jd(dat);
	get_dt_df(dat);

	return dt_lite_new_internal_wo_civil(CLASS_OF(self),
					     dat->l.jd,
					     dat->l.df,
					     dat->l.sf,
					     rof,
					     dat->l.sg,
					     HAVE_JD | HAVE_DF);
    }
}

static VALUE
dt_right_plus(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_dt1(self);
	if (TYPE(other) == T_FLOAT)
	    other = rb_rational_new2(f_round(f_mul(other, day_in_nanoseconds)),
				     day_in_nanoseconds);
	return dt_right_new(CLASS_OF(self),
			    f_add(dt_lite_ajd(self), other),
			    dt_lite_offset(self),
			    dt_lite_start(self));
    }
    rb_raise(rb_eTypeError, "expected numeric");
}

/*
 * call-seq:
 *    dt + other
 *
 * Return a new Date object that is +other+ days later than the
 * current one.
 *
 * +other+ may be a negative value, in which case the new Date
 * is earlier than the current one; however, #-() might be
 * more intuitive.
 *
 * If +other+ is not a Numeric, a TypeError will be thrown.  In
 * particular, two Dates cannot be added to each other.
 */
static VALUE
dt_lite_plus(VALUE self, VALUE other)
{
    get_dt1(self);

    if (!light_mode_p(dat))
	return c_iforwardop(plus);

    switch (TYPE(other)) {
      case T_FIXNUM:
	{
	    long jd;

	    get_dt1(self);
	    get_dt_jd(dat);
	    get_dt_df(dat);

	    jd = dat->l.jd + FIX2LONG(other);

	    if (LIGHTABLE_JD(jd) && jd >= dat->l.sg)
		return dt_lite_new_internal(CLASS_OF(self),
					    jd,
					    dat->l.df,
					    dat->l.sf,
					    dat->l.of,
					    dat->l.sg,
					    0, 0, 0,
					    dat->l.hour,
					    dat->l.min,
					    dat->l.sec,
					    (dat->l.flags | HAVE_JD) &
					    ~HAVE_CIVIL);
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
		return dt_lite_new_internal(CLASS_OF(self),
					    (long)jd,
					    df,
					    sf,
					    dat->l.of,
					    dat->l.sg,
					    0, 0, 0,
					    dat->l.hour,
					    dat->l.min,
					    dat->l.sec,
					    (dat->l.flags |
					     HAVE_JD | HAVE_DF) &
					    ~HAVE_CIVIL &
					    ~HAVE_TIME);
	}
	break;
    }
    return c_iforwardop(plus);
}

static VALUE
dt_right_minus(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_dt1(self);
	if (TYPE(other) == T_FLOAT)
	    other = rb_rational_new2(f_round(f_mul(other, day_in_nanoseconds)),
				     day_in_nanoseconds);
	return dt_right_new(CLASS_OF(self),
			    f_sub(dt_lite_ajd(self), other),
			    dt_lite_offset(self),
			    dt_lite_start(self));
    }
    else if (k_date_p(other)) {
	return f_sub(dt_lite_ajd(self), f_ajd(other));
    }
    rb_raise(rb_eTypeError, "expected numeric");
}

/*
 * call-seq:
 *    dt - other
 *
 * If +other+ is a Numeric value, create a new Date object that is
 * +x+ days earlier than the current one.
 *
 * If +other+ is a Date, return the number of days between the
 * two dates; or, more precisely, how many days later the current
 * date is than +other+.
 *
 * If +ohter+ is neither Numeric nor a Date, a TypeError is raised.
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
    return c_iforwardop(minus);
}

/*
 * call-seq:
 *    dt.next_day([n=1])
 *
 * Equivalent to dt + n.
 */
static VALUE
dt_lite_next_day(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return dt_lite_plus(self, n);
}

/*
 * call-seq:
 *    dt.prev_day([n=1])
 *
 * Equivalent to dt - n.
 */
static VALUE
dt_lite_prev_day(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return dt_lite_minus(self, n);
}

/*
 * call-seq:
 *    dt.next
 *
 * Return a new Date one day after this one.
 */
static VALUE
dt_lite_next(VALUE self)
{
    return dt_lite_next_day(0, (VALUE *)NULL, self);
}

/*
 * call-seq:
 *    dt >> n
 *
 * Return a new Date object that is +n+ months later than
 * the current one.
 *
 * If the day-of-the-month of the current Date is greater
 * than the last day of the target month, the day-of-the-month
 * of the returned Date will be the last day of the target month.
 */
static VALUE
dt_lite_rshift(VALUE self, VALUE other)
{
    VALUE t, y, m, d, sg, j;

    t = f_add3(f_mul(dt_lite_year(self), INT2FIX(12)),
	       f_sub(dt_lite_mon(self), INT2FIX(1)),
	       other);
    y = f_idiv(t, INT2FIX(12));
    m = f_mod(t, INT2FIX(12));
    m = f_add(m, INT2FIX(1));
    d = dt_lite_mday(self);
    sg = dt_lite_start(self);

    while (NIL_P(j = rt__valid_civil_p(y, m, d, sg))) {
	d = f_sub(d, INT2FIX(1));
	if (f_lt_p(d, INT2FIX(1)))
	    rb_raise(rb_eArgError, "invalid date");
    }
    return f_add(self, f_sub(j, dt_lite_jd(self)));
}

/*
 * call-seq:
 *    dt << n
 *
 * Return a new Date object that is +n+ months earlier than
 * the current one.
 *
 * If the day-of-the-month of the current Date is greater
 * than the last day of the target month, the day-of-the-month
 * of the returned Date will be the last day of the target month.
 */
static VALUE
dt_lite_lshift(VALUE self, VALUE other)
{
    return dt_lite_rshift(self, f_negate(other));
}

/*
 * call-seq:
 *    dt.next_month([n=1])
 *
 * Equivalent to dt >> n
 */
static VALUE
dt_lite_next_month(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return dt_lite_rshift(self, n);
}

/*
 * call-seq:
 *    dt.prev_month([n=1])
 *
 * Equivalent to dt << n
 */
static VALUE
dt_lite_prev_month(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return dt_lite_lshift(self, n);
}

/*
 * call-seq:
 *    dt.next_year([n=1])
 *
 * Equivalent to dt >> (n * 12)
 */
static VALUE
dt_lite_next_year(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return dt_lite_rshift(self, f_mul(n, INT2FIX(12)));
}

/*
 * call-seq:
 *    dt.prev_year([n=1])
 *
 * Equivalent to dt << (n * 12)
 */
static VALUE
dt_lite_prev_year(int argc, VALUE *argv, VALUE self)
{
    VALUE n;

    rb_scan_args(argc, argv, "01", &n);
    if (argc < 1)
	n = INT2FIX(1);
    return dt_lite_lshift(self, f_mul(n, INT2FIX(12)));
}

static VALUE
dt_right_cmp(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_dt1(self);
	return f_cmp(dt_lite_ajd(self), other);
    }
    else if (k_date_p(other)) {
	return f_cmp(dt_lite_ajd(self), f_ajd(other));
    }
    return rb_num_coerce_cmp(self, other, rb_intern("<=>"));
}
/*
 * call-seq:
 *    dt <=> other
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
    return c_iforwardop(cmp);
}

static VALUE
dt_right_equal(VALUE self, VALUE other)
{
    if (k_numeric_p(other)) {
	get_dt1(self);
	return f_eqeq_p(dt_lite_jd(self), other);
    }
    else if (k_date_p(other)) {
	return f_eqeq_p(dt_lite_jd(self), f_jd(other));
    }
    return rb_num_coerce_cmp(self, other, rb_intern("=="));
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
    return c_iforwardop(equal);
}

static VALUE
dt_right_eql_p(VALUE self, VALUE other)
{
    if (k_date_p(other) && f_eqeq_p(self, other))
	return Qtrue;
    return Qfalse;
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
    return c_iforwardop(eql_p);
}

static VALUE
dt_right_hash(VALUE self)
{
    get_dt1(self);
    assert(!light_mode_p(dat));
    return rb_hash(dat->r.ajd);
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
	return c_iforward0(hash);
    return rb_hash(dt_lite_ajd(self));
}

static VALUE
dt_right_to_s(VALUE self)
{
    VALUE a, b, c, argv[8];

    get_dt1(self);
    assert(!light_mode_p(dat));

    argv[0] = rb_usascii_str_new2("%.4d-%02d-%02dT%02d:%02d:%02d%s");
    a = dt_right_civil(self);
    b = dt_right_time_wo_sf(self);
    c = dt_right_zone(self);
    argv[1] = RARRAY_PTR(a)[0];
    argv[2] = RARRAY_PTR(a)[1];
    argv[3] = RARRAY_PTR(a)[2];
    argv[4] = RARRAY_PTR(b)[0];
    argv[5] = RARRAY_PTR(b)[1];
    argv[6] = RARRAY_PTR(b)[2];
    argv[7] = c;
    return rb_f_sprintf(8, argv);
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
	return c_iforward0(to_s);
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

static VALUE
dt_right_inspect(VALUE self)
{
    VALUE argv[6];

    get_dt1(self);
    assert(!light_mode_p(dat));

    argv[0] = rb_usascii_str_new2("#<%s[R]: %s (%s,%s,%s)>");
    argv[1] = rb_class_name(CLASS_OF(self));
    argv[2] = dt_right_to_s(self);
    argv[3] = dat->r.ajd;
    argv[4] = dat->r.of;
    argv[5] = dat->r.sg;
    return rb_f_sprintf(6, argv);
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
	return c_iforward0(inspect);
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
dt_lite_set_tmx(VALUE self, struct tmx *tmx)
{
    get_dt1(self);

    if (!light_mode_p(dat)) {
	tmx->year = dt_right_year(self);
	tmx->yday = FIX2INT(dt_right_yday(self));
	tmx->mon = FIX2INT(dt_right_mon(self));
	tmx->mday = FIX2INT(dt_right_mday(self));
	tmx->hour = FIX2INT(dt_right_hour(self));
	tmx->min = FIX2INT(dt_right_min(self));
	tmx->sec = FIX2INT(dt_right_sec(self));
	tmx->wday = FIX2INT(dt_right_wday(self));
	tmx->offset = f_mul(dat->r.of, INT2FIX(DAY_IN_SECONDS));
	tmx->zone = RSTRING_PTR(dt_right_zone(self));
	tmx->timev = f_mul(f_sub(dat->r.ajd, UNIX_EPOCH_IN_AJD),
			   INT2FIX(DAY_IN_SECONDS));
    }
    else {
	get_dt_jd(dat);
	get_dt_df(dat);
	get_dt_civil(dat);
	get_dt_time(dat);

	tmx->year = LONG2NUM(dat->l.year);
	tmx->yday = civil_to_yday(dat->l.year, dat->l.mon, dat->l.mday);
	tmx->mon = dat->l.mon;
	tmx->mday = dat->l.mday;
	tmx->hour = dat->l.hour;
	tmx->min = dat->l.min;
	tmx->sec = dat->l.sec;
	tmx->wday = jd_to_wday(local_jd(dat));
	tmx->offset = INT2FIX(dat->l.of);
	tmx->zone = RSTRING_PTR(dt_lite_zone(self));
	tmx->timev = f_mul(f_sub(dt_lite_ajd(self), UNIX_EPOCH_IN_AJD),
			   INT2FIX(DAY_IN_SECONDS));
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
				  "%FT%T%:z", dt_lite_set_tmx);
}

static VALUE
dt_lite_iso8601_timediv(VALUE self, VALUE n)
{
    VALUE f, fmt;

    if (f_lt_p(n, INT2FIX(1)))
	f = rb_usascii_str_new2("");
    else {
	VALUE argv[3];

	argv[0] = rb_usascii_str_new2(".%0*d");
	argv[1] = n;
	argv[2] = f_round(f_div(dt_lite_sec_fraction(self),
			    rb_rational_new2(INT2FIX(1),
					     f_expt(INT2FIX(10), n))));
	f = rb_f_sprintf(3, argv);
    }
    fmt = f_add3(rb_usascii_str_new2("T%T"),
		 f,
		 rb_usascii_str_new2("%:z"));
    return strftimev(RSTRING_PTR(fmt), self, dt_lite_set_tmx);
}

/*
 * call-seq:
 *    dt.asctime
 *    dt.ctime
 *
 * Equivalent to strftime('%c').
 * See also asctime(3) or ctime(3).
 */
static VALUE
dt_lite_asctime(VALUE self)
{
    return strftimev("%c", self, dt_lite_set_tmx);
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

    return f_add(strftimev("%F", self, dt_lite_set_tmx),
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
 *    dt.rfc2822
 *    dt.rfc822
 *
 * Equivalent to strftime('%a, %-d %b %Y %T %z').
 */
static VALUE
dt_lite_rfc2822(VALUE self)
{
    return strftimev("%a, %-d %b %Y %T %z", self, dt_lite_set_tmx);
}

/*
 * call-seq:
 *    dt.httpdate
 *
 * Equivalent to strftime('%a, %d %b %Y %T GMT').
 * See also RFC 2616.
 */
static VALUE
dt_lite_httpdate(VALUE self)
{
    VALUE argv[1], d;

    argv[0] = INT2FIX(0);
    d = dt_lite_new_offset(1, argv, self);
    return strftimev("%a, %d %b %Y %T GMT", d, dt_lite_set_tmx);
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

    if (!gengo(dt_lite_jd(self),
	       dt_lite_year(self),
	       argv2))
	return f_add(strftimev("%F", self, dt_lite_set_tmx),
		     dt_lite_iso8601_timediv(self, n));
    return f_add(f_add(rb_f_sprintf(2, argv2),
		       strftimev(".%m.%d", self, dt_lite_set_tmx)),
		 dt_lite_iso8601_timediv(self, n));
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
	dat->r.flags = DATETIME_OBJ;
	break;
      case 5:
	dat->l.jd = NUM2LONG(RARRAY_PTR(a)[0]);
	dat->l.df = FIX2INT(RARRAY_PTR(a)[1]);
	dat->l.sf = NUM2LONG(RARRAY_PTR(a)[2]);
	dat->l.of = FIX2INT(RARRAY_PTR(a)[3]);
	dat->l.sg = NUM2DBL(RARRAY_PTR(a)[4]);
	dat->l.year = 0;
	dat->l.mon = 0;
	dat->l.mday = 0;
	dat->l.hour = 0;
	dat->l.min = 0;
	dat->l.sec = 0;
	dat->l.flags = LIGHT_MODE | HAVE_JD | HAVE_DF | DATETIME_OBJ;
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
    VALUE jd;

    jd = rt_civil_to_jd(f_year(self), f_mon(self), f_mday(self),
			INT2FIX(ITALY));
    return d_switch_new_jd(cDate, jd, INT2FIX(ITALY));
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
    VALUE jd, sec, fr, of;

    jd = rt_civil_to_jd(f_year(self), f_mon(self), f_mday(self),
			INT2FIX(ITALY));
    sec = f_sec(self);
    if (f_gt_p(sec, INT2FIX(59)))
	sec = INT2FIX(59);
    fr = rt_time_to_day_fraction(f_hour(self), f_min(self), sec);
    fr = f_add(fr, rb_Rational(f_subsec(self), INT2FIX(DAY_IN_SECONDS)));
    of = rb_rational_new2(f_utc_offset(self), INT2FIX(DAY_IN_SECONDS));
    return dt_switch_new_jd(cDateTime, jd, fr, of, INT2FIX(ITALY));
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
    return f_local3(rb_cTime,
		    d_lite_year(self),
		    d_lite_mon(self),
		    d_lite_mday(self));
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
    return dt_switch_new_jd(cDateTime,
			    d_lite_jd(self),
			    INT2FIX(0),
			    d_lite_offset(self),
			    d_lite_start(self));
}

#ifndef NDEBUG
static VALUE
date_to_right(VALUE self)
{
    get_d1(self);
    if (!light_mode_p(dat))
	return self;
    return d_right_new(CLASS_OF(self),
		       d_lite_ajd(self),
		       d_lite_offset(self),
		       d_lite_start(self));
}

static VALUE
date_to_light(VALUE self)
{
    get_d1(self);
    if (light_mode_p(dat))
	return self;
    {
	VALUE t, jd, df;

	t = rt_ajd_to_jd(dat->r.ajd, INT2FIX(0)); /* as utc */
	jd = RARRAY_PTR(t)[0];
	df = RARRAY_PTR(t)[1];

	if (!LIGHTABLE_JD(NUM2LONG(jd)))
	    rb_raise(rb_eRangeError, "jd too big to convert into light");

	if (!f_zero_p(df))
	    rb_warning("day fraction is ignored");

	if (!f_zero_p(dat->r.of))
	    rb_warning("nonzero offset is ignored");

	return d_lite_new(CLASS_OF(self), jd, dat->r.sg);
    }
}
#endif

/*
 * call-seq:
 *    dt.to_time
 *
 * Return a Time object which denotes self.
 */
static VALUE
datetime_to_time(VALUE self)
{
    VALUE argv[1], d;

    argv[0] = INT2FIX(0);
    d = dt_lite_new_offset(1, argv, self);
    d = f_utc6(rb_cTime,
	       dt_lite_year(d),
	       dt_lite_mon(d),
	       dt_lite_mday(d),
	       dt_lite_hour(d),
	       dt_lite_min(d),
	       f_add(dt_lite_sec(d), dt_lite_sec_fraction(d)));
    return f_getlocal(d);
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
    return d_switch_new_jd(cDate,
			   dt_lite_jd(self),
			   dt_lite_start(self));
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
static VALUE
datetime_to_right(VALUE self)
{
    get_dt1(self);
    if (!light_mode_p(dat))
	return self;
    return dt_right_new(CLASS_OF(self),
			dt_lite_ajd(self),
			dt_lite_offset(self),
			dt_lite_start(self));
}

static VALUE
datetime_to_light(VALUE self)
{
    get_dt1(self);
    if (light_mode_p(dat))
	return self;
    {
	VALUE t, jd, df, sf, odf;

	t = rt_ajd_to_jd(dat->r.ajd, INT2FIX(0)); /* as utc */
	jd = RARRAY_PTR(t)[0];
	df = RARRAY_PTR(t)[1];

	if (!LIGHTABLE_JD(NUM2LONG(jd)))
	    rb_raise(rb_eRangeError, "jd too big to convert into light");

	if (f_lt_p(dat->r.of, INT2FIX(-1)) ||
	    f_gt_p(dat->r.of, INT2FIX(1)))
	    rb_raise(rb_eRangeError, "offset too big to convert into light");

	t = f_mul(df, INT2FIX(DAY_IN_SECONDS));
	df = f_idiv(t, INT2FIX(1));
	sf = f_mod(t, INT2FIX(1));

	t = f_mul(sf, INT2FIX(SECOND_IN_NANOSECONDS));
	sf = f_idiv(t, INT2FIX(1));

	if (f_eqeq_p(t, sf))
	    rb_warning("second fraction is truncated");

	t = f_mul(dat->r.of, INT2FIX(DAY_IN_SECONDS));
	odf = f_truncate(t);

	if (f_eqeq_p(t, odf))
	    rb_warning("offset is truncated");

	return dt_lite_new(CLASS_OF(self),
			   jd, df, sf, odf, dat->r.sg);
    }
}
#endif

#ifndef NDEBUG
/* tests */

static int
test_civil(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "test_civil: %ld...%ld (%ld) - %.0f\n",
	    from, to, to - from, sg);
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
test_ordinal(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "test_ordinal: %ld...%ld (%ld) - %.0f\n",
	    from, to, to - from, sg);
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
test_commercial(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "test_commercial: %ld...%ld (%ld) - %.0f\n",
	    from, to, to - from, sg);
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
test_weeknum(long from, long to, int f, double sg)
{
    long j;

    fprintf(stderr, "test_weeknum: %ld...%ld (%ld) - %.0f\n",
	    from, to, to - from, sg);
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
test_nth_kday(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "test_nth_kday: %ld...%ld (%ld) - %.0f\n",
	    from, to, to - from, sg);
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

static int
print_emesg(VALUE x, VALUE y)
{
    VALUE argv[3];
    argv[0] = rb_usascii_str_new2("%s != %s\n");
    argv[1] = x;
    argv[2] = y;
    return fputs(RSTRING_PTR(rb_f_sprintf(3, argv)), stderr);
}

static int
test_d_switch_new(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "test_d_switch_new: %ld...%ld (%ld) - %.0f\n",
	    from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	VALUE jd, ajd, rd, sd;

	jd = LONG2NUM(j);
	ajd = rt_jd_to_ajd(jd, INT2FIX(0), INT2FIX(0));
	rd = d_right_new(cDate, ajd, INT2FIX(0), DBL2NUM(sg));
	sd = d_switch_new(cDate, ajd, INT2FIX(0), DBL2NUM(sg));
	if (!f_eqeq_p(rd, sd)) {
	    print_emesg(rd, sd);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_d_switch_new(VALUE klass)
{
    if (!test_d_switch_new(MIN_JD, MIN_JD + 366, GREGORIAN))
	return Qfalse;
    if (!test_d_switch_new(2305814, 2598007, GREGORIAN))
	return Qfalse;
    if (!test_d_switch_new(MAX_JD - 366, MAX_JD, GREGORIAN))
	return Qfalse;

    if (!test_d_switch_new(MIN_JD, MIN_JD + 366, ITALY))
	return Qfalse;
    if (!test_d_switch_new(2305814, 2598007, ITALY))
	return Qfalse;
    if (!test_d_switch_new(MAX_JD - 366, MAX_JD, ITALY))
	return Qfalse;

    return Qtrue;
}

static int
test_dt_switch_new(long from, long to, double sg)
{
    long j;

    fprintf(stderr, "test_dt_switch_new: %ld...%ld (%ld) - %.0f\n",
	    from, to, to - from, sg);
    for (j = from; j <= to; j++) {
	VALUE jd, vof, ajd, rd, sd;
	int of, df;
	long sf;

	jd = LONG2NUM(j);
	ajd = rt_jd_to_ajd(jd, INT2FIX(0), INT2FIX(0));
	rd = dt_right_new(cDateTime, ajd, INT2FIX(0), DBL2NUM(sg));
	sd = dt_switch_new(cDateTime, ajd, INT2FIX(0), DBL2NUM(sg));
	if (!f_eqeq_p(rd, sd)) {
	    print_emesg(rd, sd);
	    return 0;
	}

	of = (int)((labs(j) % (DAY_IN_SECONDS * 2)) - DAY_IN_SECONDS);
	vof = rb_rational_new2(INT2FIX(of), INT2FIX(DAY_IN_SECONDS));
	df = time_to_df(4, 5, 6);
	sf = 123456789L;
	ajd = rt_jd_to_ajd(jd,
			   f_add(rb_rational_new2(INT2FIX(df),
						  INT2FIX(DAY_IN_SECONDS)),
				 rb_rational_new2(LONG2NUM(sf),
						  day_in_nanoseconds)),
			   vof);
	rd = dt_right_new(cDateTime, ajd, vof, DBL2NUM(sg));
	sd = dt_switch_new(cDateTime, ajd, vof, DBL2NUM(sg));
	if (!f_eqeq_p(rd, sd)) {
	    print_emesg(rd, sd);
	    return 0;
	}
    }
    return 1;
}

static VALUE
date_s_test_dt_switch_new(VALUE klass)
{
    if (!test_dt_switch_new(MIN_JD, MIN_JD + 366, GREGORIAN))
	return Qfalse;
    if (!test_dt_switch_new(2305814, 2598007, GREGORIAN))
	return Qfalse;
    if (!test_dt_switch_new(MAX_JD - 366, MAX_JD, GREGORIAN))
	return Qfalse;

    if (!test_dt_switch_new(MIN_JD, MIN_JD + 366, ITALY))
	return Qfalse;
    if (!test_dt_switch_new(2305814, 2598007, ITALY))
	return Qfalse;
    if (!test_dt_switch_new(MAX_JD - 366, MAX_JD, ITALY))
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
    if (date_s_test_d_switch_new(klass) == Qfalse)
	return Qfalse;
    if (date_s_test_dt_switch_new(klass) == Qfalse)
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
 * Instead of year, month-of-the-year,  and day-of-the-month,
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
    assert(fprintf(stderr, "assert() is now active\n"));

    rzero = rb_rational_new1(INT2FIX(0));
    rhalf = rb_rational_new2(INT2FIX(1), INT2FIX(2));

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

    rb_gc_register_mark_object(rzero);
    rb_gc_register_mark_object(rhalf);
    rb_gc_register_mark_object(day_in_nanoseconds);

    /*
     * Class representing a date.
     *
     * Internally, the date is represented as an Astronomical
     * Julian Day Number, +ajd+.  The Day of Calendar Reform, +start+, is
     * also stored, for conversions to other date formats.  (There
     * is also an +offset+ field for a time zone offset, but this
     * is only for the use of the DateTime subclass.)
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
    rb_define_singleton_method(cDate, "new_r!", date_s_new_r_bang, -1);
    rb_define_singleton_method(cDate, "new_l!", date_s_new_l_bang, -1);
    rb_define_singleton_method(cDate, "new!", date_s_new_bang, -1);
#endif

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

    rb_define_alloc_func(cDateTime, dt_lite_s_alloc);

#ifndef NDEBUG
    rb_define_singleton_method(cDateTime, "new_r!", datetime_s_new_r_bang, -1);
    rb_define_singleton_method(cDateTime, "new_l!", datetime_s_new_l_bang, -1);
    rb_define_singleton_method(cDateTime, "new!", datetime_s_new_bang, -1);
#endif

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

    rb_define_method(cDateTime, "sunday?", dt_lite_sunday_p, 0);
    rb_define_method(cDateTime, "monday?", dt_lite_monday_p, 0);
    rb_define_method(cDateTime, "tuesday?", dt_lite_tuesday_p, 0);
    rb_define_method(cDateTime, "wednesday?", dt_lite_wednesday_p, 0);
    rb_define_method(cDateTime, "thursday?", dt_lite_thursday_p, 0);
    rb_define_method(cDateTime, "friday?", dt_lite_friday_p, 0);
    rb_define_method(cDateTime, "saturday?", dt_lite_saturday_p, 0);

    rb_define_method(cDateTime, "julian?", dt_lite_julian_p, 0);
    rb_define_method(cDateTime, "gregorian?", dt_lite_gregorian_p, 0);
    rb_define_method(cDateTime, "leap?", dt_lite_leap_p, 0);

    rb_define_method(cDateTime, "start", dt_lite_start, 0);
    rb_define_method(cDateTime, "new_start", dt_lite_new_start, -1);
    rb_define_method(cDateTime, "italy", dt_lite_italy, 0);
    rb_define_method(cDateTime, "england", dt_lite_england, 0);
    rb_define_method(cDateTime, "julian", dt_lite_julian, 0);
    rb_define_method(cDateTime, "gregorian", dt_lite_gregorian, 0);
    rb_define_method(cDateTime, "new_offset", dt_lite_new_offset, -1);

    rb_define_method(cDateTime, "+", dt_lite_plus, 1);
    rb_define_method(cDateTime, "-", dt_lite_minus, 1);

    rb_define_method(cDateTime, "next_day", dt_lite_next_day, -1);
    rb_define_method(cDateTime, "prev_day", dt_lite_prev_day, -1);
    rb_define_method(cDateTime, "next", dt_lite_next, 0);
    rb_define_method(cDateTime, "succ", dt_lite_next, 0);

    rb_define_method(cDateTime, ">>", dt_lite_rshift, 1);
    rb_define_method(cDateTime, "<<", dt_lite_lshift, 1);

    rb_define_method(cDateTime, "next_month", dt_lite_next_month, -1);
    rb_define_method(cDateTime, "prev_month", dt_lite_prev_month, -1);
    rb_define_method(cDateTime, "next_year", dt_lite_next_year, -1);
    rb_define_method(cDateTime, "prev_year", dt_lite_prev_year, -1);

    rb_define_method(cDateTime, "<=>", dt_lite_cmp, 1);
    rb_define_method(cDateTime, "===", dt_lite_equal, 1);
    rb_define_method(cDateTime, "eql?", dt_lite_eql_p, 1);
    rb_define_method(cDateTime, "hash", dt_lite_hash, 0);

    rb_define_method(cDateTime, "to_s", dt_lite_to_s, 0);
    rb_define_method(cDateTime, "inspect", dt_lite_inspect, 0);
    rb_define_method(cDateTime, "strftime", dt_lite_strftime, -1);

    rb_define_method(cDateTime, "asctime", dt_lite_asctime, 0);
    rb_define_method(cDateTime, "ctime", dt_lite_asctime, 0);
    rb_define_method(cDateTime, "iso8601", dt_lite_iso8601, -1);
    rb_define_method(cDateTime, "xmlschema", dt_lite_iso8601, -1);
    rb_define_method(cDateTime, "rfc3339", dt_lite_rfc3339, -1);
    rb_define_method(cDateTime, "rfc2822", dt_lite_rfc2822, 0);
    rb_define_method(cDateTime, "rfc822", dt_lite_rfc2822, 0);
    rb_define_method(cDateTime, "httpdate", dt_lite_httpdate, 0);
    rb_define_method(cDateTime, "jisx0301", dt_lite_jisx0301, -1);

    rb_define_method(cDateTime, "marshal_dump", dt_lite_marshal_dump, 0);
    rb_define_method(cDateTime, "marshal_load", dt_lite_marshal_load, 1);

    /* conversions */

    rb_define_method(rb_cTime, "to_time", time_to_time, 0);
    rb_define_method(rb_cTime, "to_date", time_to_date, 0);
    rb_define_method(rb_cTime, "to_datetime", time_to_datetime, 0);

    rb_define_method(cDate, "to_time", date_to_time, 0);
    rb_define_method(cDate, "to_date", date_to_date, 0);
    rb_define_method(cDate, "to_datetime", date_to_datetime, 0);

#ifndef NDEBUG
    rb_define_method(cDate, "to_right", date_to_right, 0);
    rb_define_method(cDate, "to_light", date_to_light, 0);
#endif

    rb_define_method(cDateTime, "to_time", datetime_to_time, 0);
    rb_define_method(cDateTime, "to_date", datetime_to_date, 0);
    rb_define_method(cDateTime, "to_datetime", datetime_to_datetime, 0);

#ifndef NDEBUG
    rb_define_method(cDateTime, "to_right", datetime_to_right, 0);
    rb_define_method(cDateTime, "to_light", datetime_to_light, 0);
#endif

#ifndef NDEBUG
    /* tests */

    rb_define_singleton_method(cDate, "test_civil", date_s_test_civil, 0);
    rb_define_singleton_method(cDate, "test_ordinal", date_s_test_ordinal, 0);
    rb_define_singleton_method(cDate, "test_commercial",
			       date_s_test_commercial, 0);
    rb_define_singleton_method(cDate, "test_weeknum", date_s_test_weeknum, 0);
    rb_define_singleton_method(cDate, "test_nth_kday", date_s_test_nth_kday, 0);
    rb_define_singleton_method(cDate, "test_d_switch_new",
			       date_s_test_d_switch_new, 0);
    rb_define_singleton_method(cDate, "test_dt_switch_new",
			       date_s_test_dt_switch_new, 0);
    rb_define_singleton_method(cDate, "test_all", date_s_test_all, 0);
#endif
}

/*
Local variables:
c-file-style: "ruby"
End:
*/
