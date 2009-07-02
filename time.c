/**********************************************************************

  time.c -

  $Author$
  created at: Tue Dec 28 14:31:59 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include <sys/types.h>
#include <time.h>
#include <errno.h>
#include "ruby/encoding.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#include <float.h>
#include <math.h>

#include "timev.h"

#ifndef TYPEOF_TIMEVAL_TV_SEC
# define TYPEOF_TIMEVAL_TV_SEC time_t
#endif
#ifndef TYPEOF_TIMEVAL_TV_USEC
# if INT_MAX >= 1000000
# define TYPEOF_TIMEVAL_TV_USEC int
# else
# define TYPEOF_TIMEVAL_TV_USEC long
# endif
#endif

#if SIZEOF_TIME_T == SIZEOF_LONG
typedef unsigned long unsigned_time_t;
#elif SIZEOF_TIME_T == SIZEOF_INT
typedef unsigned int unsigned_time_t;
#elif SIZEOF_TIME_T == SIZEOF_LONG_LONG
typedef unsigned LONG_LONG unsigned_time_t;
#else
# error cannot find integer type which size is same as time_t.
#endif

VALUE rb_cTime;
static VALUE time_utc_offset _((VALUE));

static long obj2long(VALUE obj);
static VALUE obj2vint(VALUE obj);
static int month_arg(VALUE arg);
static void validate_utc_offset(VALUE utc_offset);
static void validate_vtm(struct vtm *vtm);

static VALUE time_gmtime(VALUE);
static VALUE time_localtime(VALUE);
static VALUE time_fixoff(VALUE);

static time_t timegm_noleapsecond(struct tm *tm);
static int tmcmp(struct tm *a, struct tm *b);
static int vtmcmp(struct vtm *a, struct vtm *b);
static const char *find_time_t(struct tm *tptr, int utc_p, time_t *tp);

static struct vtm *localtimev(VALUE timev, struct vtm *result);

static int leap_year_p(long y);
#define leap_year_v_p(y) leap_year_p(NUM2LONG(mod(v, INT2FIX(400))))

#define NDIV(x,y) (-(-((x)+1)/(y))-1)
#define NMOD(x,y) ((y)-(-((x)+1)%(y))-1)
#define DIV(n,d) ((n)<0 ? NDIV((n),(d)) : (n)/(d))

#ifdef HAVE_GMTIME_R
#define IF_HAVE_GMTIME_R(x) x
#define ASCTIME(tm, buf) asctime_r((tm), (buf))
#define GMTIME(tm, result) gmtime_r((tm), &(result))
#define LOCALTIME(tm, result) (tzset(),localtime_r((tm), &(result)))
#else
#define IF_HAVE_GMTIME_R(x) 	/* nothing */
#define ASCTIME(tm, buf) asctime(tm)
#define GMTIME(tm, result) rb_gmtime((tm), &(result))
#define LOCALTIME(tm, result) rb_localtime((tm), &(result))

static inline struct tm *
rb_gmtime(const time_t *tm, struct tm *result)
{
    struct tm *t = gmtime(tm);
    if (t) *result = *t;
    return t;
}

static inline struct tm *
rb_localtime(const time_t *tm, struct tm *result)
{
    struct tm *t = localtime(tm);
    if (t) *result = *t;
    return t;
}
#endif

static ID id_divmod, id_mul, id_submicro, id_subnano;
static ID id_eq, id_ne, id_quo, id_div, id_cmp, id_lshift;

#define eq(x,y) (rb_funcall((x), id_eq, 1, (y)))
#define ne(x,y) (rb_funcall((x), id_ne, 1, (y)))
#define lt(x,y) (RTEST(rb_funcall((x), '<', 1, (y))))
#define gt(x,y) (RTEST(rb_funcall((x), '>', 1, (y))))
#define le(x,y) (!gt(x,y))
#define ge(x,y) (!lt(x,y))
#define add(x,y) (rb_funcall((x), '+', 1, (y)))
#define sub(x,y) (rb_funcall((x), '-', 1, (y)))
#define mul(x,y) (rb_funcall((x), '*', 1, (y)))
#define div(x,y) (rb_funcall((x), id_div, 1, (y)))
#define mod(x,y) (rb_funcall((x), '%', 1, (y)))
#define neg(x) (sub(INT2FIX(0), (x)))
#define cmp(x,y) (rb_funcall((x), id_cmp, 1, (y)))
#define lshift(x,y) (rb_funcall((x), id_lshift, 1, (y)))

static VALUE
quo(VALUE x, VALUE y)
{
    VALUE ret;
    ret = rb_funcall((x), id_quo, 1, (y));
    if (TYPE(ret) == T_RATIONAL &&
        ((struct RRational *)ret)->den == INT2FIX(1)) {
        ret = ((struct RRational *)ret)->num;
    }
    return ret;
}

static void
divmodv(VALUE n, VALUE d, VALUE *q, VALUE *r)
{
    VALUE tmp, ary;
    tmp = rb_funcall(n, id_divmod, 1, d);
    ary = rb_check_array_type(tmp);
    if (NIL_P(ary)) {
        rb_raise(rb_eTypeError, "unexpected divmod result: into %s",
                 rb_obj_classname(tmp));
    }
    *q = rb_ary_entry(ary, 0);
    *r = rb_ary_entry(ary, 1);
}

static VALUE
num_exact(VALUE v)
{
    switch (TYPE(v)) {
      case T_FIXNUM:
      case T_BIGNUM:
      case T_RATIONAL:
        break;

      case T_FLOAT:
        v = rb_convert_type(v, T_RATIONAL, "Rational", "to_r");
        break;

      case T_NIL:
        goto typeerror;

      default: {
        VALUE tmp;
        if (!NIL_P(tmp = rb_check_convert_type(v, T_RATIONAL, "Rational", "to_r")))
            v = tmp;
        else if (!NIL_P(tmp = rb_check_to_integer(v, "to_int")))
            v = tmp;
        else {
          typeerror:
            rb_raise(rb_eTypeError, "can't convert %s into an exact number",
                                 rb_obj_classname(v));
        }
        break;
      }
    }
    return v;
}

static const int common_year_yday_offset[] = {
    -1,
    -1 + 31,
    -1 + 31 + 28,
    -1 + 31 + 28 + 31,
    -1 + 31 + 28 + 31 + 30,
    -1 + 31 + 28 + 31 + 30 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
    -1 + 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30
      /* 1    2    3    4    5    6    7    8    9    10   11 */
};
static const int leap_year_yday_offset[] = {
    -1,
    -1 + 31,
    -1 + 31 + 29,
    -1 + 31 + 29 + 31,
    -1 + 31 + 29 + 31 + 30,
    -1 + 31 + 29 + 31 + 30 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
    -1 + 31 + 29 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30
      /* 1    2    3    4    5    6    7    8    9    10   11 */
};

static const int common_year_days_in_month[] = {
    31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};
static const int leap_year_days_in_month[] = {
    31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

static VALUE
timegmv_noleapsecond(struct vtm *vtm)
{
    VALUE year1900;
    VALUE q400, r400;
    int year_mod400;
    int yday = vtm->mday;
    long days_in400;
    VALUE ret;

    year1900 = sub(vtm->year, INT2FIX(1900));

    divmodv(year1900, INT2FIX(400), &q400, &r400);
    year_mod400 = NUM2INT(r400);

    if (leap_year_p(year_mod400 + 1900))
	yday += leap_year_yday_offset[vtm->mon-1];
    else
	yday += common_year_yday_offset[vtm->mon-1];

    /*
     *  `Seconds Since the Epoch' in SUSv3:
     *  tm_sec + tm_min*60 + tm_hour*3600 + tm_yday*86400 +
     *  (tm_year-70)*31536000 + ((tm_year-69)/4)*86400 -
     *  ((tm_year-1)/100)*86400 + ((tm_year+299)/400)*86400
     */
    ret = LONG2NUM(vtm->sec
                 + vtm->min*60
                 + vtm->hour*3600);
    days_in400 = yday
               - 70*365
               + DIV(year_mod400 - 69, 4)
               - DIV(year_mod400 - 1, 100)
               + (year_mod400 + 299) / 400;
    ret = add(ret, mul(LONG2NUM(days_in400), INT2FIX(86400)));
    ret = add(ret, mul(q400, INT2FIX(97*86400)));
    ret = add(ret, mul(year1900, INT2FIX(365*86400)));
    ret = add(ret, vtm->subsec);

    return ret;
}

static st_table *zone_table;

static const char *
zone_str(const char *s)
{
    st_data_t k, v;

    if (!zone_table)
        zone_table = st_init_strtable();

    k = (st_data_t)s;
    if (st_lookup(zone_table, k, &v)) {
        return (const char *)v;
    }
    s = strdup(s);
    k = (st_data_t)s;
    st_add_direct(zone_table, k, k);

    return s;
}

static void
gmtimev_noleapsecond(VALUE timev, struct vtm *vtm)
{
    VALUE v;
    int i, n, x, y;
    const int *yday_offset;
    int wday;

    vtm->isdst = 0;

    divmodv(timev, INT2FIX(1), &timev, &vtm->subsec);
    divmodv(timev, INT2FIX(86400), &timev, &v);

    wday = NUM2INT(mod(timev, INT2FIX(7)));
    vtm->wday = (wday + 4) % 7;

    n = NUM2INT(v);
    vtm->sec = n % 60; n = n / 60;
    vtm->min = n % 60; n = n / 60;
    vtm->hour = n;

    /* 97 leap days in the 400 year cycle */
    divmodv(timev, INT2FIX(400*365 + 97), &timev, &v);
    vtm->year = mul(timev, INT2FIX(400));

    /* n is the days in the 400 year cycle.
     * the start of the cycle is 1970-01-01. */

    n = NUM2INT(v);
    y = 1970;

    /* 30 years including 7 leap days (1972, 1976, ... 1996),
     * 31 days in January 2000 and
     * 29 days in Febrary 2000
     * from 1970-01-01 to 2000-02-29 */
    if (30*365+7+31+29-1 <= n) {
        /* 2000-02-29 or after */
        if (n < 31*365+8) {
            /* 2000-02-29 to 2000-12-31 */
            y += 30;
            n -= 30*365+7;
            goto found;
        }
        else {
            /* 2001-01-01 or after */
            n -= 1;
        }
    }

    x = n / (365*100 + 24);
    n = n % (365*100 + 24);
    y += x * 100;
    if (30*365+7+31+29-1 <= n) {
        if (n < 31*365+7) {
            y += 30;
            n -= 30*365+7;
            goto found;
        }
        else
            n += 1;
    }

    x = n / (365*4 + 1);
    n = n % (365*4 + 1);
    y += x * 4;
    if (365*2+31+29-1 <= n) {
        if (n < 365*2+366) {
            y += 2;
            n -= 365*2;
            goto found;
        }
        else
            n -= 1;
    }

    x = n / 365;
    n = n % 365;
    y += x;

  found:
    vtm->yday = n+1;
    vtm->year = add(vtm->year, INT2NUM(y));

    if (leap_year_p(y))
        yday_offset = leap_year_yday_offset;
    else
        yday_offset = common_year_yday_offset;

    for (i = 0; i < 12; i++) {
        if (yday_offset[i] < n) {
            vtm->mon = i+1;
            vtm->mday = n - yday_offset[i];
        }
        else
            break;
    }

    vtm->utc_offset = INT2FIX(0);
    vtm->zone = "UTC";
}

static struct tm *
gmtime_with_leapsecond(const time_t *timep, struct tm *result)
{
#if defined(HAVE_STRUCT_TM_TM_GMTOFF)
    /* 4.4BSD counts leap seconds only with localtime, not with gmtime. */
    struct tm *t;
    int sign;
    long gmtoff, gmtoff_sec, gmtoff_min, gmtoff_hour, gmtoff_day;
    t = localtime_r(timep, result);
    if (t == NULL)
        return NULL;

    /* subtract gmtoff */
    if (t->tm_gmtoff < 0) {
        sign = 1;
        gmtoff = -t->tm_gmtoff;
    }
    else {
        sign = -1;
        gmtoff = t->tm_gmtoff;
    }
    gmtoff_sec = gmtoff % 60;
    gmtoff = gmtoff / 60;
    gmtoff_min = gmtoff % 60;
    gmtoff = gmtoff / 60;
    gmtoff_hour = gmtoff;

    gmtoff_sec *= sign;
    gmtoff_min *= sign;
    gmtoff_hour *= sign;

    gmtoff_day = 0;

    if (gmtoff_sec) {
        /* If gmtoff_sec == 0, don't change result->tm_sec.
         * It may be 60 which is a leap second. */
        result->tm_sec += gmtoff_sec;
        if (result->tm_sec < 0) {
            result->tm_sec += 60;
            gmtoff_min -= 1;
        }
        if (60 <= result->tm_sec) {
            result->tm_sec -= 60;
            gmtoff_min += 1;
        }
    }
    if (gmtoff_min) {
        result->tm_min += gmtoff_min;
        if (result->tm_min < 0) {
            result->tm_min += 60;
            gmtoff_hour -= 1;
        }
        if (60 <= result->tm_min) {
            result->tm_min -= 60;
            gmtoff_hour += 1;
        }
    }
    if (gmtoff_hour) {
        result->tm_hour += gmtoff_hour;
        if (result->tm_hour < 0) {
            result->tm_hour += 24;
            gmtoff_day = -1;
        }
        if (24 <= result->tm_hour) {
            result->tm_hour -= 24;
            gmtoff_day = 1;
        }
    }

    if (gmtoff_day) {
        if (gmtoff_day < 0) {
            if (result->tm_yday == 0) {
                result->tm_mday = 31;
                result->tm_mon = 11; /* December */
                result->tm_year--;
                result->tm_yday = leap_year_p(result->tm_year + 1900) ? 365 : 364;
            }
            else if (result->tm_mday == 1) {
                const int *days_in_month = leap_year_p(result->tm_year + 1900) ?
                                           leap_year_days_in_month :
                                           common_year_days_in_month;
                result->tm_mon--;
                result->tm_mday = days_in_month[result->tm_mon];
                result->tm_yday--;
            }
            else {
                result->tm_mday--;
                result->tm_yday--;
            }
            result->tm_wday = (result->tm_wday + 6) % 7;
        }
        else {
            int leap = leap_year_p(result->tm_year + 1900);
            if (result->tm_yday == (leap ? 365 : 364)) {
                result->tm_year++;
                result->tm_mon = 0; /* January */
                result->tm_mday = 1;
                result->tm_yday = 0;
            }
            else if (result->tm_mday == (leap ? leap_year_days_in_month :
                                                common_year_days_in_month)[result->tm_mon]) {
                result->tm_mon++;
                result->tm_mday = 1;
                result->tm_yday++;
            }
            else {
                result->tm_mday++;
                result->tm_yday++;
            }
            result->tm_wday = (result->tm_wday + 1) % 7;
        }
    }
    result->tm_isdst = 0;
    result->tm_gmtoff = 0;
#if defined(HAVE_TM_ZONE)
    result->tm_zone = (char *)"UTC";
#endif
    return result;
#else
    return GMTIME(timep, *result);
#endif
}

static long this_year = 0;
static time_t known_leap_seconds_limit;
static int number_of_leap_seconds_known;

static void
init_leap_second_info()
{
    /*
     * leap seconds are determined by IERS.
     * It is announced 6 months before the leap second.
     * So no one knows leap seconds in the future after the next year.
     */
    if (this_year == 0) {
        time_t now, max;
        struct tm *tm, result;
        struct vtm vtm;
        VALUE timev;
        now = time(NULL);
        gmtime(&now);
        tm = gmtime_with_leapsecond(&now, &result);
        this_year = tm->tm_year;

        max = ~(time_t)0;
        if (max <= (time_t)0) {
            /* time_t is signed */
            max = (~(unsigned_time_t)0) >> 1;
        }
        if (max - now < (time_t)(366*86400))
            known_leap_seconds_limit = max;
        else
            known_leap_seconds_limit = now + (time_t)(366*86400);

        gmtime_with_leapsecond(&known_leap_seconds_limit, &result);

        vtm.year = LONG2NUM(result.tm_year + 1900);
        vtm.mon = result.tm_mon + 1;
        vtm.mday = result.tm_mday;
        vtm.hour = result.tm_hour;
        vtm.min = result.tm_min;
        vtm.sec = result.tm_sec;
        vtm.subsec = INT2FIX(0);
        vtm.utc_offset = INT2FIX(0);

        timev = timegmv_noleapsecond(&vtm);

        number_of_leap_seconds_known = NUM2INT(sub(TIMET2NUM(known_leap_seconds_limit), timev));
    }
}

static VALUE
timegmv(struct vtm *vtm)
{
    VALUE timev;
    struct tm tm;
    time_t t;
    const char *errmsg;

    /* The first leap second is 1972-06-30 23:59:60 UTC.
     * No leap seconds before. */
    if (RTEST(gt(INT2FIX(1972), vtm->year)))
        return timegmv_noleapsecond(vtm);

    init_leap_second_info();

    timev = timegmv_noleapsecond(vtm);

    if (RTEST(lt(TIMET2NUM(known_leap_seconds_limit), timev))) {
        return add(timev, INT2NUM(number_of_leap_seconds_known));
    }

    tm.tm_year = NUM2LONG(vtm->year) - 1900;
    tm.tm_mon = vtm->mon - 1;
    tm.tm_mday = vtm->mday;
    tm.tm_hour = vtm->hour;
    tm.tm_min = vtm->min;
    tm.tm_sec = vtm->sec;
    tm.tm_isdst = 0;

    errmsg = find_time_t(&tm, 1, &t);
    if (errmsg)
        rb_raise(rb_eArgError, "%s", errmsg);
    return add(TIMET2NUM(t), vtm->subsec);
}

static struct vtm *
gmtimev(VALUE timev, struct vtm *result)
{
    time_t t;
    struct tm tm;
    VALUE subsec;

    if (RTEST(lt(timev, INT2FIX(0)))) {
        gmtimev_noleapsecond(timev, result);
        return result;
    }

    init_leap_second_info();

    if (RTEST(lt(LONG2NUM(known_leap_seconds_limit), timev))) {
        timev = sub(timev, INT2NUM(number_of_leap_seconds_known));
        gmtimev_noleapsecond(timev, result);
        return result;
    }

    divmodv(timev, INT2FIX(1), &timev, &subsec);

    t = NUM2TIMET(timev);
    if (!gmtime_with_leapsecond(&t, &tm))
        return NULL;

    result->year = LONG2NUM((long)tm.tm_year + 1900);
    result->mon = tm.tm_mon + 1;
    result->mday = tm.tm_mday;
    result->hour = tm.tm_hour;
    result->min = tm.tm_min;
    result->sec = tm.tm_sec;
    result->subsec = subsec;
    result->utc_offset = INT2FIX(0);
    result->wday = tm.tm_wday;
    result->yday = tm.tm_yday+1;
    result->isdst = tm.tm_isdst;
    result->zone = "UTC";

    return result;
}

static struct tm *localtime_with_gmtoff(const time_t *t, struct tm *result, long *gmtoff);

/*
 * The idea is come from Perl:
 * http://use.perl.org/articles/08/02/07/197204.shtml
 *
 * compat_common_month_table is generated by following program.
 * This table finds the last month which start the same day of a week.
 * The year 2037 is not used because
 * http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=522949
 *
 *  #!/usr/bin/ruby 
 *
 *  require 'date'
 *
 *  h = {}
 *  2036.downto(2010) {|y|
 *    1.upto(12) {|m|
 *      next if m == 2 && y % 4 == 0
 *      d = Date.new(y,m,1)
 *      h[m] ||= {}
 *      h[m][d.wday] ||= y
 *    }   
 *  } 
 *
 *  1.upto(12) {|m|
 *    print "{"
 *    0.upto(6) {|w|
 *      y = h[m][w]
 *      print " #{y},"
 *    }
 *    puts "},"
 *  }
 *
 */
static int compat_common_month_table[12][7] = {
  /* Sun   Mon   Tue   Wed   Thu   Fri   Sat */
  { 2034, 2035, 2036, 2031, 2032, 2027, 2033 }, /* January */
  { 2026, 2027, 2033, 2034, 2035, 2030, 2031 }, /* February */
  { 2026, 2032, 2033, 2034, 2035, 2030, 2036 }, /* March */
  { 2035, 2030, 2036, 2026, 2032, 2033, 2034 }, /* April */
  { 2033, 2034, 2035, 2030, 2036, 2026, 2032 }, /* May */
  { 2036, 2026, 2032, 2033, 2034, 2035, 2030 }, /* June */
  { 2035, 2030, 2036, 2026, 2032, 2033, 2034 }, /* July */
  { 2032, 2033, 2034, 2035, 2030, 2036, 2026 }, /* August */
  { 2030, 2036, 2026, 2032, 2033, 2034, 2035 }, /* September */
  { 2034, 2035, 2030, 2036, 2026, 2032, 2033 }, /* October */
  { 2026, 2032, 2033, 2034, 2035, 2030, 2036 }, /* November */
  { 2030, 2036, 2026, 2032, 2033, 2034, 2035 }, /* December */
};

/*
 * compat_leap_month_table is generated by following program.
 *
 *  #!/usr/bin/ruby 
 * 
 *  require 'date'
 * 
 *  h = {}
 *  2037.downto(2010) {|y|
 *    1.upto(12) {|m|
 *      next unless m == 2 && y % 4 == 0
 *      d = Date.new(y,m,1)
 *      h[m] ||= {}
 *      h[m][d.wday] ||= y
 *    }
 *  }
 * 
 *  2.upto(2) {|m|
 *    0.upto(6) {|w|
 *      y = h[m][w]
 *      print " #{y},"
 *    }
 *    puts
 *  }
 */
static int compat_leap_month_table[7] = {
/* Sun   Mon   Tue   Wed   Thu   Fri   Sat */
  2032, 2016, 2028, 2012, 2024, 2036, 2020, /* February */
};

static int
calc_wday(int year, int month, int day)
{
    int a, y, m;
    int wday;

    a = (14 - month) / 12;
    y = year + 4800 - a;
    m = month + 12 * a - 3;
    wday = day + (153*m+2)/5 + 365*y + y/4 - y/100 + y/400 + 2;
    wday = wday % 7;
    return wday;
}

static VALUE
guess_local_offset(struct vtm *vtm_utc)
{
    VALUE off = INT2FIX(0);
    struct tm tm;
    long gmtoff;
    time_t t;
    struct vtm vtm2;
    VALUE timev;
    int y, wday;

# if defined(NEGATIVE_TIME_T)
    /* 1901-12-13 20:45:52 UTC : The oldest time in 32-bit signed time_t. */
    if (localtime_with_gmtoff((t = (time_t)0x80000000, &t), &tm, &gmtoff))
	off = LONG2FIX(gmtoff);
    else
# endif
    /* 1970-01-01 00:00:00 UTC : The Unix epoch - the oldest time in portable time_t. */
    if (localtime_with_gmtoff((t = 0, &t), &tm, &gmtoff))
	off = LONG2FIX(gmtoff);

    /* The first DST is at 1916 in German.
     * So we don't need to care DST before that. */
    if (lt(vtm_utc->year, INT2FIX(1916)))
        return off;

    /* It is difficult to guess future. */

    vtm2 = *vtm_utc;

    /* guess using a year before 2038. */
    y = NUM2INT(mod(vtm_utc->year, INT2FIX(400)));
    wday = calc_wday(y, vtm_utc->mon, 1);
    if (vtm_utc->mon == 2 && leap_year_p(y))
        vtm2.year = INT2FIX(compat_leap_month_table[wday]);
    else
        vtm2.year = INT2FIX(compat_common_month_table[vtm_utc->mon-1][wday]);

    timev = timegmv(&vtm2);
    t = NUM2TIMET(timev);
    if (localtime_with_gmtoff(&t, &tm, &gmtoff))
        return LONG2FIX(gmtoff);

    {
        /* Use the current time offset as a last resort. */
        static time_t now = 0;
        static long now_gmtoff = 0;
        if (now == 0) {
            now = time(NULL);
            localtime_with_gmtoff(&now, &tm, &now_gmtoff);
        }
        return LONG2FIX(now_gmtoff);
    }
}

static VALUE
small_vtm_sub(struct vtm *vtm1, struct vtm *vtm2)
{
    int off;

    off = vtm1->sec - vtm2->sec;
    off += (vtm1->min - vtm2->min) * 60;
    off += (vtm1->hour - vtm2->hour) * 3600;
    if (ne(vtm1->year, vtm2->year))
        off += lt(vtm1->year, vtm2->year) ? -24*3600 : 24*3600;
    else if (vtm1->mon != vtm2->mon)
        off += vtm1->mon < vtm2->mon ? -24*3600 : 24*3600;
    else if (vtm1->mday != vtm2->mday)
        off += vtm1->mday < vtm2->mday ? -24*3600 : 24*3600;

    return INT2FIX(off);
}

static VALUE
timelocalv(struct vtm *vtm)
{
    time_t t;
    struct tm tm;
    VALUE v;
    VALUE timev1, timev2;
    struct vtm vtm1, vtm2;
    int n;

    if (FIXNUM_P(vtm->year)) {
        long l = FIX2LONG(vtm->year) - 1900;
        if (l < INT_MIN || INT_MAX < l)
            goto no_localtime;
        tm.tm_year = l;
    }
    else {
        v = sub(vtm->year, INT2FIX(1900));
        if (lt(v, INT2NUM(INT_MIN)) || lt(INT2NUM(INT_MAX), v))
            goto no_localtime;
        tm.tm_year = NUM2INT(v);
    }

    tm.tm_mon = vtm->mon-1;
    tm.tm_mday = vtm->mday;
    tm.tm_hour = vtm->hour;
    tm.tm_min = vtm->min;
    tm.tm_sec = vtm->sec;
    tm.tm_isdst = vtm->isdst;

    if (find_time_t(&tm, 0, &t))
        goto no_localtime;
    return add(TIMET2NUM(t), vtm->subsec);

  no_localtime:
    timev1 = timegmv(vtm);

    if (!localtimev(timev1, &vtm1))
        rb_raise(rb_eArgError, "localtimev error");

    n = vtmcmp(vtm, &vtm1);
    if (n == 0) {
        timev1 = sub(timev1, INT2FIX(12*3600));
        if (!localtimev(timev1, &vtm1))
            rb_raise(rb_eArgError, "localtimev error");
        n = 1;
    }

    if (n < 0) {
        timev2 = timev1;
        vtm2 = vtm1;
        timev1 = sub(timev1, INT2FIX(24*3600));
        if (!localtimev(timev1, &vtm1))
            rb_raise(rb_eArgError, "localtimev error");
    }
    else {
        timev2 = add(timev1, INT2FIX(24*3600));
        if (!localtimev(timev2, &vtm2))
            rb_raise(rb_eArgError, "localtimev error");
    }
    timev1 = add(timev1, small_vtm_sub(vtm, &vtm1));
    timev2 = add(timev2, small_vtm_sub(vtm, &vtm2));

    if (eq(timev1, timev2))
        return timev1;

    if (!localtimev(timev1, &vtm1))
        rb_raise(rb_eArgError, "localtimev error");
    if (vtm->hour != vtm1.hour || vtm->min != vtm1.min || vtm->sec != vtm1.sec)
        return timev2;

    if (!localtimev(timev2, &vtm2))
        rb_raise(rb_eArgError, "localtimev error");
    if (vtm->hour != vtm2.hour || vtm->min != vtm2.min || vtm->sec != vtm2.sec)
        return timev1;

    if (vtm->isdst)
        return lt(vtm1.utc_offset, vtm2.utc_offset) ? timev2 : timev1;
    else
        return lt(vtm1.utc_offset, vtm2.utc_offset) ? timev1 : timev2;
}

#define TIMET_MAX (~(time_t)0 <= 0 ? (time_t)((~(unsigned_time_t)0) >> 1) : (~(unsigned_time_t)0))
#define TIMET_MIN (~(time_t)0 <= 0 ? (time_t)(((unsigned_time_t)1) << (sizeof(time_t) * CHAR_BIT - 1)) : (time_t)0)

static struct tm *
localtime_with_gmtoff(const time_t *t, struct tm *result, long *gmtoff)
{
    struct tm tm;

    if (LOCALTIME(t, tm)) {
#if defined(HAVE_STRUCT_TM_TM_GMTOFF)
	*gmtoff = tm.tm_gmtoff;
#else
	struct tm *u, *l;
	long off;
	struct tm tmbuf;
	l = &tm;
	u = GMTIME(t, tmbuf);
	if (!u)
	    return NULL;
	if (l->tm_year != u->tm_year)
	    off = l->tm_year < u->tm_year ? -1 : 1;
	else if (l->tm_mon != u->tm_mon)
	    off = l->tm_mon < u->tm_mon ? -1 : 1;
	else if (l->tm_mday != u->tm_mday)
	    off = l->tm_mday < u->tm_mday ? -1 : 1;
	else
	    off = 0;
	off = off * 24 + l->tm_hour - u->tm_hour;
	off = off * 60 + l->tm_min - u->tm_min;
	off = off * 60 + l->tm_sec - u->tm_sec;
	*gmtoff = off;
#endif
        *result = tm;
	return result;
    }
    return NULL;
}

static struct vtm *
localtimev(VALUE timev, struct vtm *result)
{
    VALUE subsec, offset;
    divmodv(timev, INT2FIX(1), &timev, &subsec);

    if (le(TIMET2NUM(TIMET_MIN), timev) &&
        le(timev, TIMET2NUM(TIMET_MAX))) {
        time_t t;
        struct tm tm;
	long gmtoff;
        t = NUM2TIMET(timev);

        if (localtime_with_gmtoff(&t, &tm, &gmtoff)) {
            result->year = LONG2NUM((long)tm.tm_year + 1900);
            result->mon = tm.tm_mon + 1;
            result->mday = tm.tm_mday;
            result->hour = tm.tm_hour;
            result->min = tm.tm_min;
            result->sec = tm.tm_sec;
            result->subsec = subsec;
            result->wday = tm.tm_wday;
            result->yday = tm.tm_yday+1;
            result->isdst = tm.tm_isdst;
            result->utc_offset = LONG2NUM(gmtoff);
#if defined(HAVE_TM_ZONE)
            result->zone = zone_str(tm.tm_zone);
#elif defined(HAVE_TZNAME) && defined(HAVE_DAYLIGHT)
            /* this needs tzset or localtime, instead of localtime_r */
            result->zone = zone_str(tzname[daylight && tm.tm_isdst]);
#else
            {
                char buf[64];
                strftime(buf, sizeof(buf), "%Z", &tm);
                result->zone = zone_str(buf);
            }
#endif

            return result;
        }
    }

    if (!gmtimev(timev, result))
        return NULL;

    offset = guess_local_offset(result);

    if (!gmtimev(add(timev, offset), result))
        return NULL;

    result->utc_offset = offset;

    return result;
}

struct time_object {
    VALUE timev;
    struct vtm vtm;
    int gmt;
    int tm_got;
};

#define GetTimeval(obj, tobj) \
    Data_Get_Struct(obj, struct time_object, tobj)

#define TIME_UTC_P(tobj) ((tobj)->gmt == 1)
#define TIME_SET_UTC(tobj) ((tobj)->gmt = 1)

#define TIME_LOCALTIME_P(tobj) ((tobj)->gmt == 0)
#define TIME_SET_LOCALTIME(tobj) ((tobj)->gmt = 0)

#define TIME_FIXOFF_P(tobj) ((tobj)->gmt == 2)
#define TIME_SET_FIXOFF(tobj, off) \
    ((tobj)->gmt = 2, \
     (tobj)->vtm.utc_offset = (off), \
     (tobj)->vtm.zone = NULL)

#define TIME_COPY_GMT(tobj1, tobj2) ((tobj1)->gmt = (tobj2)->gmt)

static VALUE time_get_tm(VALUE, struct time_object *);
#define MAKE_TM(time, tobj) \
  do { \
    if ((tobj)->tm_got == 0) { \
	time_get_tm((time), (tobj)); \
    } \
  } while (0)

static void
time_mark(void *ptr)
{
    struct time_object *tobj = ptr;
    if (!tobj) return;
    rb_gc_mark(tobj->timev);
    rb_gc_mark(tobj->vtm.year);
    rb_gc_mark(tobj->vtm.subsec);
    rb_gc_mark(tobj->vtm.utc_offset);
}

static void
time_free(void *tobj)
{
    if (tobj) xfree(tobj);
}

static VALUE
time_s_alloc(VALUE klass)
{
    VALUE obj;
    struct time_object *tobj;

    obj = Data_Make_Struct(klass, struct time_object, time_mark, time_free, tobj);
    tobj->tm_got=0;
    tobj->timev = INT2FIX(0);

    return obj;
}

static void
time_modify(VALUE time)
{
    rb_check_frozen(time);
    if (!OBJ_UNTRUSTED(time) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify Time");
}

static VALUE
timespec2timev(struct timespec *ts)
{
    VALUE timev;

    timev = TIMET2NUM(ts->tv_sec);
    if (ts->tv_nsec)
        timev = add(timev, quo(LONG2NUM(ts->tv_nsec), INT2FIX(1000000000)));
    return timev;
}

static struct timespec
timev2timespec(VALUE timev)
{
    VALUE subsec;
    struct timespec ts;

    divmodv(timev, INT2FIX(1), &timev, &subsec);
    if (lt(timev, TIMET2NUM(TIMET_MIN)) || lt(TIMET2NUM(TIMET_MAX), timev))
	rb_raise(rb_eArgError, "time out of system range");
    ts.tv_sec = NUM2TIMET(timev);
    ts.tv_nsec = NUM2LONG(mul(subsec, INT2FIX(1000000000)));
    return ts;
}

/*
 *  Document-method: now
 *
 *  Synonym for <code>Time.new</code>. Returns a +Time+ object
 *  initialized to the current system time.
 */

static VALUE
time_init_0(VALUE time)
{
    struct time_object *tobj;
    struct timespec ts;

    time_modify(time);
    GetTimeval(time, tobj);
    tobj->tm_got=0;
    tobj->timev = INT2FIX(0);
#ifdef HAVE_CLOCK_GETTIME
    if (clock_gettime(CLOCK_REALTIME, &ts) == -1) {
	rb_sys_fail("clock_gettime");
    }
#else
    {
        struct timeval tv;
        if (gettimeofday(&tv, 0) < 0) {
            rb_sys_fail("gettimeofday");
        }
        ts.tv_sec = tv.tv_sec;
        ts.tv_nsec = tv.tv_usec * 1000;
    }
#endif
    tobj->timev = timespec2timev(&ts);

    return time;
}

static VALUE
time_set_utc_offset(VALUE time, VALUE off)
{
    struct time_object *tobj;
    off = num_exact(off);

    time_modify(time);
    GetTimeval(time, tobj);

    tobj->tm_got = 0;
    TIME_SET_FIXOFF(tobj, off);

    return time;
}

static void
vtm_add_offset(struct vtm *vtm, VALUE off)
{
    int sign;
    VALUE subsec, v;
    int sec, min, hour;
    int day;

    vtm->utc_offset = sub(vtm->utc_offset, off);

    if (RTEST(lt(off, INT2FIX(0)))) {
        sign = -1;
        off = neg(off);
    }
    else {
        sign = 1;
    }
    divmodv(off, INT2FIX(1), &off, &subsec);
    divmodv(off, INT2FIX(60), &off, &v);
    sec = NUM2INT(v);
    divmodv(off, INT2FIX(60), &off, &v);
    min = NUM2INT(v);
    divmodv(off, INT2FIX(24), &off, &v);
    hour = NUM2INT(v);

    if (sign < 0) {
        subsec = neg(subsec);
        sec = -sec;
        min = -min;
        hour = -hour;
    }

    day = 0;

    if (!rb_equal(subsec, INT2FIX(0))) {
        vtm->subsec = add(vtm->subsec, subsec);
        if (lt(vtm->subsec, INT2FIX(0))) {
            vtm->subsec = add(vtm->subsec, INT2FIX(1));
            sec -= 1;
        }
        if (le(INT2FIX(1), vtm->subsec)) {
            vtm->subsec = sub(vtm->subsec, INT2FIX(1));
            sec += 1;
        }
        goto not_zero_sec;
    }
    if (sec) {
      not_zero_sec:
        /* If sec + subsec == 0, don't change vtm->sec.
         * It may be 60 which is a leap second. */
        vtm->sec += sec;
        if (vtm->sec < 0) {
            vtm->sec += 60;
            min -= 1;
        }
        if (60 <= vtm->sec) {
            vtm->sec -= 60;
            min += 1;
        }
    }
    if (min) {
        vtm->min += min;
        if (vtm->min < 0) {
            vtm->min += 60;
            hour -= 1;
        }
        if (60 <= vtm->min) {
            vtm->min -= 60;
            hour += 1;
        }
    }
    if (hour) {
        vtm->hour += hour;
        if (vtm->hour < 0) {
            vtm->hour += 24;
            day = -1;
        }
        if (24 <= vtm->hour) {
            vtm->hour -= 24;
            day = 1;
        }
    }

    if (day) {
        if (day < 0) {
            if (vtm->mon == 1 && vtm->mday == 1) {
                vtm->mday = 31;
                vtm->mon = 12; /* December */
                vtm->year = sub(vtm->year, INT2FIX(1));
                vtm->yday = leap_year_v_p(vtm->year) ? 365 : 364;
            }
            else if (vtm->mday == 1) {
                const int *days_in_month = leap_year_v_p(vtm->year) ?
                                           leap_year_days_in_month :
                                           common_year_days_in_month;
                vtm->mon--;
                vtm->mday = days_in_month[vtm->mon-1];
                vtm->yday--;
            }
            else {
                vtm->mday--;
                vtm->yday--;
            }
            vtm->wday = (vtm->wday + 6) % 7;
        }
        else {
            int leap = leap_year_v_p(vtm->year);
            if (vtm->mon == 12 && vtm->mday == 31) {
                vtm->year = add(vtm->year, INT2FIX(1));
                vtm->mon = 1; /* January */
                vtm->mday = 1;
                vtm->yday = 1;
            }
            else if (vtm->mday == (leap ? leap_year_days_in_month :
                                          common_year_days_in_month)[vtm->mon-1]) {
                vtm->mon++;
                vtm->mday = 1;
                vtm->yday++;
            }
            else {
                vtm->mday++;
                vtm->yday++;
            }
            vtm->wday = (vtm->wday + 1) % 7;
        }
    }
}

static VALUE
utc_offset_arg(VALUE arg)
{
    VALUE tmp;
    if (!NIL_P(tmp = rb_check_string_type(arg))) {
        int n;
        char *s = RSTRING_PTR(tmp);
        if (!rb_enc_str_asciicompat_p(tmp) ||
            RSTRING_LEN(tmp) != 6 ||
            (s[0] != '+' && s[0] != '-') ||
            !ISDIGIT(s[1]) ||
            !ISDIGIT(s[2]) ||
            s[3] != ':' ||
            !ISDIGIT(s[4]) ||
            !ISDIGIT(s[5]))
            rb_raise(rb_eArgError, "\"+HH:MM\" or \"-HH:MM\" expected for utc_offset");
        n = strtol(s+1, NULL, 10) * 3600;
        n += strtol(s+4, NULL, 10) * 60;
        if (s[0] == '-')
            n = -n;
        return INT2FIX(n);
    }
    else {
        return num_exact(arg);
    }
}

static VALUE
time_init_1(int argc, VALUE *argv, VALUE time)
{
    struct vtm vtm;
    VALUE v[7];
    struct time_object *tobj;

    vtm.wday = -1;
    vtm.yday = 0;
    vtm.zone = "";

    /*                             year  mon   mday  hour  min   sec   off */
    rb_scan_args(argc, argv, "16", &v[0],&v[1],&v[2],&v[3],&v[4],&v[5],&v[6]);

    vtm.year = obj2vint(v[0]);

    vtm.mon = NIL_P(v[1]) ? 1 : month_arg(v[1]);

    vtm.mday = NIL_P(v[2]) ? 1 : obj2long(v[2]);

    vtm.hour = NIL_P(v[3]) ? 0 : obj2long(v[3]);

    vtm.min  = NIL_P(v[4]) ? 0 : obj2long(v[4]);

    vtm.sec = 0;
    vtm.subsec = INT2FIX(0);
    if (!NIL_P(v[5])) {
        VALUE sec = num_exact(v[5]);
        VALUE subsec;
        divmodv(sec, INT2FIX(1), &sec, &subsec);
        vtm.sec = NUM2INT(sec);
        vtm.subsec = subsec;
    }

    vtm.isdst = -1;
    vtm.utc_offset = Qnil;
    if (!NIL_P(v[6])) {
        VALUE arg = v[6];
        if (arg == ID2SYM(rb_intern("dst")))
            vtm.isdst = 1;
        else if (arg == ID2SYM(rb_intern("std")))
            vtm.isdst = 0;
        else
            vtm.utc_offset = utc_offset_arg(arg);
    }

    validate_vtm(&vtm);

    time_modify(time);
    GetTimeval(time, tobj);
    tobj->tm_got=0;
    tobj->timev = INT2FIX(0);

    if (!NIL_P(vtm.utc_offset)) {
        VALUE off = vtm.utc_offset;
        vtm_add_offset(&vtm, neg(off));
        vtm.utc_offset = Qnil;
        tobj->timev = timegmv(&vtm);
        return time_set_utc_offset(time, off);
    }
    else {
        tobj->timev = timelocalv(&vtm);
        return time_localtime(time);
    }
}


/*
 *  call-seq:
 *     Time.new -> time
 *     Time.new(year) -> time
 *     Time.new(year, month) -> time
 *     Time.new(year, month, day) -> time
 *     Time.new(year, month, day, hour) -> time
 *     Time.new(year, month, day, hour, min) -> time
 *     Time.new(year, month, day, hour, min, sec) -> time
 *     Time.new(year, month, day, hour, min, sec, utc_offset) -> time
 *
 *  Returns a <code>Time</code> object.
 *
 *  It is initialized to the current system time if no argument.
 *  <b>Note:</b> The object created will be created using the
 *  resolution available on your system clock, and so may include
 *  fractional seconds.
 *
 *  If one or more arguments specified, the time is initialized
 *  to the specified time.
 *  _sec_ may have fraction if it is a rational.
 *
 *  _utc_offset_ is the offset from UTC.
 *  It is a string such as "+09:00" or a number of seconds such as 32400.
 *
 *     a = Time.new      #=> 2007-11-19 07:50:02 -0600
 *     b = Time.new      #=> 2007-11-19 07:50:02 -0600
 *     a == b            #=> false
 *     "%.6f" % a.to_f   #=> "1195480202.282373"
 *     "%.6f" % b.to_f   #=> "1195480202.283415"
 *
 *     Time.new(2008,6,21, 13,30,0, "+09:00") #=> 2008-06-21 13:30:00 +0900
 *
 */

static VALUE
time_init(int argc, VALUE *argv, VALUE time)
{
    if (argc == 0)
        return time_init_0(time);
    else
        return time_init_1(argc, argv, time);
}

static void
time_overflow_p(time_t *secp, long *nsecp)
{
    time_t tmp, sec = *secp;
    long nsec = *nsecp;

    if (nsec >= 1000000000) {	/* nsec positive overflow */
	tmp = sec + nsec / 1000000000;
	nsec %= 1000000000;
	if (sec > 0 && tmp < 0) {
	    rb_raise(rb_eRangeError, "out of Time range");
	}
	sec = tmp;
    }
    if (nsec < 0) {		/* nsec negative overflow */
	tmp = sec + NDIV(nsec,1000000000); /* negative div */
	nsec = NMOD(nsec,1000000000);      /* negative mod */
	if (sec < 0 && tmp > 0) {
	    rb_raise(rb_eRangeError, "out of Time range");
	}
	sec = tmp;
    }
#ifndef NEGATIVE_TIME_T
    if (sec < 0)
	rb_raise(rb_eArgError, "time must be positive");
#endif
    *secp = sec;
    *nsecp = nsec;
}

static VALUE nsec2timev(time_t sec, long nsec)
{
    struct timespec ts;
    time_overflow_p(&sec, &nsec);
    ts.tv_sec = sec;
    ts.tv_nsec = nsec;
    return timespec2timev(&ts);
}

static VALUE
time_new_internal(VALUE klass, VALUE timev)
{
    VALUE time = time_s_alloc(klass);
    struct time_object *tobj;

    GetTimeval(time, tobj);
    tobj->timev = num_exact(timev);

    return time;
}

VALUE
rb_time_new(time_t sec, long usec)
{
    return time_new_internal(rb_cTime, nsec2timev(sec, usec * 1000));
}

VALUE
rb_time_nano_new(time_t sec, long nsec)
{
    return time_new_internal(rb_cTime, nsec2timev(sec, nsec));
}

VALUE
rb_time_num_new(VALUE timev, VALUE off)
{
    VALUE time = time_new_internal(rb_cTime, timev);

    if (!NIL_P(off)) {
        off = utc_offset_arg(off);
        validate_utc_offset(off);
        time_set_utc_offset(time, off);
        return time;
    }

    return time;
}

static VALUE
time_new_timev(VALUE klass, VALUE timev)
{
    VALUE time = time_s_alloc(klass);
    struct time_object *tobj;

    GetTimeval(time, tobj);
    tobj->timev = timev;

    return time;
}

static struct timespec
time_timespec(VALUE num, int interval)
{
    struct timespec t;
    const char *tstr = interval ? "time interval" : "time";
    VALUE i, f, ary;

#ifndef NEGATIVE_TIME_T
    interval = 1;
#endif

    switch (TYPE(num)) {
      case T_FIXNUM:
	t.tv_sec = NUM2TIMET(num);
	if (interval && t.tv_sec < 0)
	    rb_raise(rb_eArgError, "%s must be positive", tstr);
	t.tv_nsec = 0;
	break;

      case T_FLOAT:
	if (interval && RFLOAT_VALUE(num) < 0.0)
	    rb_raise(rb_eArgError, "%s must be positive", tstr);
	else {
	    double f, d;

	    d = modf(RFLOAT_VALUE(num), &f);
            if (d < 0) {
                d += 1;
                f -= 1;
            }
	    t.tv_sec = (time_t)f;
	    if (f != t.tv_sec) {
		rb_raise(rb_eRangeError, "%f out of Time range", RFLOAT_VALUE(num));
	    }
	    t.tv_nsec = (int)(d*1e9+0.5);
	    if (t.tv_nsec >= 1000000000) {
		t.tv_nsec -= 1000000000;
		if (++t.tv_sec <= 0) {
		    --t.tv_nsec;
		    t.tv_nsec = 999999999;
		}
	    }
	}
	break;

      case T_BIGNUM:
	t.tv_sec = NUM2TIMET(num);
	if (interval && t.tv_sec < 0)
	    rb_raise(rb_eArgError, "%s must be positive", tstr);
	t.tv_nsec = 0;
	break;

      default:
        if (rb_respond_to(num, id_divmod)) {
            ary = rb_check_array_type(rb_funcall(num, id_divmod, 1, INT2FIX(1)));
            if (NIL_P(ary)) {
                goto typeerror;
            }
            i = rb_ary_entry(ary, 0);
            f = rb_ary_entry(ary, 1);
            t.tv_sec = NUM2TIMET(i);
            if (interval && t.tv_sec < 0)
                rb_raise(rb_eArgError, "%s must be positive", tstr);
            f = rb_funcall(f, id_mul, 1, INT2FIX(1000000000));
            t.tv_nsec = NUM2LONG(f);
        }
        else {
typeerror:
            rb_raise(rb_eTypeError, "can't convert %s into %s",
                     rb_obj_classname(num), tstr);
        }
	break;
    }
    return t;
}

static struct timeval
time_timeval(VALUE num, int interval)
{
    struct timespec ts;
    struct timeval tv;

    ts = time_timespec(num, interval);
    tv.tv_sec = (TYPEOF_TIMEVAL_TV_SEC)ts.tv_sec;
    tv.tv_usec = (TYPEOF_TIMEVAL_TV_USEC)(ts.tv_nsec / 1000);

    return tv;
}

struct timeval
rb_time_interval(VALUE num)
{
    return time_timeval(num, Qtrue);
}

struct timeval
rb_time_timeval(VALUE time)
{
    struct time_object *tobj;
    struct timeval t;
    struct timespec ts;

    if (TYPE(time) == T_DATA && RDATA(time)->dfree == time_free) {
	GetTimeval(time, tobj);
        ts = timev2timespec(tobj->timev);
        t.tv_sec = (TYPEOF_TIMEVAL_TV_SEC)ts.tv_sec;
        t.tv_usec = (TYPEOF_TIMEVAL_TV_USEC)(ts.tv_nsec / 1000);
	return t;
    }
    return time_timeval(time, Qfalse);
}

struct timespec
rb_time_timespec(VALUE time)
{
    struct time_object *tobj;
    struct timespec t;

    if (TYPE(time) == T_DATA && RDATA(time)->dfree == time_free) {
	GetTimeval(time, tobj);
        t = timev2timespec(tobj->timev);
	return t;
    }
    return time_timespec(time, Qfalse);
}

/*
 *  call-seq:
 *     Time.now => time
 *
 *  Creates a new time object for the current time.
 *
 *     Time.now            #=> 2009-06-24 12:39:54 +0900
 */

static VALUE
time_s_now(VALUE klass)
{
    return rb_class_new_instance(0, NULL, klass);
}

/*
 *  call-seq:
 *     Time.at(time) => time
 *     Time.at(seconds_with_frac) => time
 *     Time.at(seconds, microseconds_with_frac) => time
 *
 *  Creates a new time object with the value given by <i>time</i>,
 *  the given number of <i>seconds_with_frac</i>, or
 *  <i>seconds</i> and <i>microseconds_with_frac</i> from the Epoch.
 *  <i>seconds_with_frac</i> and <i>microseconds_with_frac</i>
 *  can be Integer, Float, Rational, or other Numeric.
 *  non-portable feature allows the offset to be negative on some systems.
 *
 *     Time.at(0)            #=> 1969-12-31 18:00:00 -0600
 *     Time.at(Time.at(0))   #=> 1969-12-31 18:00:00 -0600
 *     Time.at(946702800)    #=> 1999-12-31 23:00:00 -0600
 *     Time.at(-284061600)   #=> 1960-12-31 00:00:00 -0600
 *     Time.at(946684800.2).usec #=> 200000
 *     Time.at(946684800, 123456.789).nsec #=> 123456789
 */

static VALUE
time_s_at(int argc, VALUE *argv, VALUE klass)
{
    VALUE time, t, timev;

    if (rb_scan_args(argc, argv, "11", &time, &t) == 2) {
        time = num_exact(time);
        t = num_exact(t);
        timev = add(time, quo(t, INT2FIX(1000000)));
        t = time_new_timev(klass, timev);
    }
    else if (TYPE(time) == T_DATA && RDATA(time)->dfree == time_free) {
	struct time_object *tobj, *tobj2;
        GetTimeval(time, tobj);
        t = time_new_timev(klass, tobj->timev);
	GetTimeval(t, tobj2);
        TIME_COPY_GMT(tobj2, tobj);
    }
    else {
        timev = num_exact(time);
        t = time_new_timev(klass, timev);
    }

    return t;
}

static const char months[][4] = {
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
};

static long
obj2long(VALUE obj)
{
    if (TYPE(obj) == T_STRING) {
	obj = rb_str_to_inum(obj, 10, Qfalse);
    }

    return NUM2LONG(obj);
}

static VALUE
obj2vint(VALUE obj)
{
    if (TYPE(obj) == T_STRING) {
	obj = rb_str_to_inum(obj, 10, Qfalse);
    }
    else {
        obj = rb_to_int(obj);
    }

    return obj;
}

static long
obj2subsec(VALUE obj, VALUE *subsec)
{
    if (TYPE(obj) == T_STRING) {
	obj = rb_str_to_inum(obj, 10, Qfalse);
        *subsec = INT2FIX(0);
        return NUM2LONG(obj);
    }

    divmodv(num_exact(obj), INT2FIX(1), &obj, subsec);
    return NUM2LONG(obj);
}

static long
usec2subsec(VALUE obj)
{
    if (TYPE(obj) == T_STRING) {
	obj = rb_str_to_inum(obj, 10, Qfalse);
    }

    return quo(num_exact(obj), INT2FIX(1000000));
}

static int
month_arg(VALUE arg)
{
    int i, mon;

    VALUE s = rb_check_string_type(arg);
    if (!NIL_P(s)) {
        mon = 0;
        for (i=0; i<12; i++) {
            if (RSTRING_LEN(s) == 3 &&
                STRCASECMP(months[i], RSTRING_PTR(s)) == 0) {
                mon = i+1;
                break;
            }
        }
        if (mon == 0) {
            char c = RSTRING_PTR(s)[0];

            if ('0' <= c && c <= '9') {
                mon = obj2long(s);
            }
        }
    }
    else {
        mon = obj2long(arg);
    }
    return mon;
}

static void
validate_utc_offset(VALUE utc_offset)
{
    if (le(utc_offset, INT2FIX(-86400)) || ge(utc_offset, INT2FIX(86400)))
	rb_raise(rb_eArgError, "utc_offset out of range");
}

static void
validate_vtm(struct vtm *vtm)
{
    if (   vtm->mon  < 1 || vtm->mon  > 12
	|| vtm->mday < 1 || vtm->mday > 31
	|| vtm->hour < 0 || vtm->hour > 24
	|| (vtm->hour == 24 && (vtm->min > 0 || vtm->sec > 0))
	|| vtm->min  < 0 || vtm->min  > 59
	|| vtm->sec  < 0 || vtm->sec  > 60
        || lt(vtm->subsec, INT2FIX(0)) || ge(vtm->subsec, INT2FIX(1))
        || (!NIL_P(vtm->utc_offset) && (validate_utc_offset(vtm->utc_offset), 0)))
	rb_raise(rb_eArgError, "argument out of range");
}

static void
time_arg(int argc, VALUE *argv, struct vtm *vtm)
{
    VALUE v[8];

    vtm->year = INT2FIX(0);
    vtm->mon = 0;
    vtm->mday = 0;
    vtm->hour = 0;
    vtm->min = 0;
    vtm->sec = 0;
    vtm->subsec = INT2FIX(0);
    vtm->utc_offset = Qnil;
    vtm->wday = 0;
    vtm->yday = 0;
    vtm->isdst = 0;
    vtm->zone = "";

    if (argc == 10) {
	v[0] = argv[5];
	v[1] = argv[4];
	v[2] = argv[3];
	v[3] = argv[2];
	v[4] = argv[1];
	v[5] = argv[0];
	v[6] = Qnil;
	vtm->isdst = RTEST(argv[8]) ? 1 : 0;
    }
    else {
	rb_scan_args(argc, argv, "17", &v[0],&v[1],&v[2],&v[3],&v[4],&v[5],&v[6],&v[7]);
	/* v[6] may be usec or zone (parsedate) */
	/* v[7] is wday (parsedate; ignored) */
	vtm->wday = -1;
	vtm->isdst = -1;
    }

    vtm->year = obj2vint(v[0]);

    if (NIL_P(v[1])) {
        vtm->mon = 1;
    }
    else {
        vtm->mon = month_arg(v[1]);
    }

    if (NIL_P(v[2])) {
	vtm->mday = 1;
    }
    else {
	vtm->mday = obj2long(v[2]);
    }

    vtm->hour = NIL_P(v[3])?0:obj2long(v[3]);

    vtm->min  = NIL_P(v[4])?0:obj2long(v[4]);

    if (!NIL_P(v[6]) && argc == 7) {
        vtm->sec  = NIL_P(v[5])?0:obj2long(v[5]);
        vtm->subsec  = usec2subsec(v[6]);
    }
    else {
	/* when argc == 8, v[6] is timezone, but ignored */
        vtm->sec  = NIL_P(v[5])?0:obj2subsec(v[5], &vtm->subsec);
    }

    validate_vtm(vtm);
}

static int
leap_year_p(long y)
{
    return ((y % 4 == 0) && (y % 100 != 0)) || (y % 400 == 0);
}

static time_t
timegm_noleapsecond(struct tm *tm)
{
    long tm_year = tm->tm_year;
    int tm_yday = tm->tm_mday;
    if (leap_year_p(tm_year + 1900))
	tm_yday += leap_year_yday_offset[tm->tm_mon];
    else
	tm_yday += common_year_yday_offset[tm->tm_mon];

    /*
     *  `Seconds Since the Epoch' in SUSv3:
     *  tm_sec + tm_min*60 + tm_hour*3600 + tm_yday*86400 +
     *  (tm_year-70)*31536000 + ((tm_year-69)/4)*86400 -
     *  ((tm_year-1)/100)*86400 + ((tm_year+299)/400)*86400
     */
    return tm->tm_sec + tm->tm_min*60 + tm->tm_hour*3600 +
	   (time_t)(tm_yday +
		    (tm_year-70)*365 +
		    DIV(tm_year-69,4) -
		    DIV(tm_year-1,100) +
		    DIV(tm_year+299,400))*86400;
}

#ifdef FIND_TIME_NUMGUESS
static unsigned long long find_time_numguess;

static VALUE find_time_numguess_getter(void)
{
    return ULL2NUM(find_time_numguess);
}
#endif

static const char *
find_time_t(struct tm *tptr, int utc_p, time_t *tp)
{
    time_t guess, guess_lo, guess_hi;
    struct tm *tm, tm_lo, tm_hi;
    int d;
    int find_dst;
    struct tm result;
    int try_interpolation;
    unsigned long range = 0;

#ifdef FIND_TIME_NUMGUESS
#define GUESS(p) (find_time_numguess++, (utc_p ? gmtime_with_leapsecond(p, &result) : LOCALTIME(p, result)))
#else
#define GUESS(p) (utc_p ? gmtime_with_leapsecond(p, &result) : LOCALTIME(p, result))
#endif

    find_dst = 0 < tptr->tm_isdst;

#ifdef NEGATIVE_TIME_T
    guess_lo = (time_t)~((unsigned_time_t)~(time_t)0 >> 1);
#else
    guess_lo = 0;
#endif
    guess_hi = ((time_t)-1) < ((time_t)0) ?
	       (time_t)((unsigned_time_t)~(time_t)0 >> 1) :
	       ~(time_t)0;

    guess = timegm_noleapsecond(tptr);
    tm = GUESS(&guess);
    if (tm) {
	d = tmcmp(tptr, tm);
	if (d == 0) { goto found; }
	if (d < 0) {
	    guess_hi = guess;
	    guess -= 24 * 60 * 60;
	}
	else {
	    guess_lo = guess;
	    guess += 24 * 60 * 60;
	}
	if (guess_lo < guess && guess < guess_hi && (tm = GUESS(&guess)) != NULL) {
	    d = tmcmp(tptr, tm);
	    if (d == 0) { goto found; }
	    if (d < 0)
		guess_hi = guess;
	    else
		guess_lo = guess;
	}
    }

    tm = GUESS(&guess_lo);
    if (!tm) goto error;
    d = tmcmp(tptr, tm);
    if (d < 0) goto out_of_range;
    if (d == 0) { guess = guess_lo; goto found; }
    tm_lo = *tm;

    tm = GUESS(&guess_hi);
    if (!tm) goto error;
    d = tmcmp(tptr, tm);
    if (d > 0) goto out_of_range;
    if (d == 0) { guess = guess_hi; goto found; }
    tm_hi = *tm;

    try_interpolation = 1;

    while (guess_lo + 1 < guess_hi) {
        if (try_interpolation == 1) {
            int a, b;
            /* there is a gap between guess_lo and guess_hi. */
            range = 0;
            /*
              Try precious guess by a linear interpolation at first.
              `a' and `b' is a coefficient of guess_lo and guess_hi as:

                guess = (guess_lo * a + guess_hi * b) / (a + b)

              However this causes overflow in most cases, following assignment
              is used instead:

                guess = guess_lo / d * a + (guess_lo % d) * a / d
                        + guess_hi / d * b + (guess_hi % d) * b / d
                where d = a + b

              To avoid overflow in this assignment, `d' is restricted to less than
              sqrt(2**31).  By this restriction and other reasons, the guess is
              not accurate and some error is expected.  `range' approximates
              the maximum error.

              When these parameters are not suitable, i.e. guess is not within
              guess_lo and guess_hi, simple guess by binary search is used.
            */
            range = 366 * 24 * 60 * 60;
            a = (tm_hi.tm_year - tptr->tm_year);
            b = (tptr->tm_year - tm_lo.tm_year);
            /* 46000 is selected as `some big number less than sqrt(2**31)'. */
            if (a + b <= 46000 / 12) {
                range = 31 * 24 * 60 * 60;
                a *= 12;
                b *= 12;
                a += tm_hi.tm_mon - tptr->tm_mon;
                b += tptr->tm_mon - tm_lo.tm_mon;
                if (a + b <= 46000 / 31) {
                    range = 24 * 60 * 60;
                    a *= 31;
                    b *= 31;
                    a += tm_hi.tm_mday - tptr->tm_mday;
                    b += tptr->tm_mday - tm_lo.tm_mday;
                    if (a + b <= 46000 / 24) {
                        range = 60 * 60;
                        a *= 24;
                        b *= 24;
                        a += tm_hi.tm_hour - tptr->tm_hour;
                        b += tptr->tm_hour - tm_lo.tm_hour;
                        if (a + b <= 46000 / 60) {
                            range = 60;
                            a *= 60;
                            b *= 60;
                            a += tm_hi.tm_min - tptr->tm_min;
                            b += tptr->tm_min - tm_lo.tm_min;
                            if (a + b <= 46000 / 60) {
                                range = 1;
                                a *= 60;
                                b *= 60;
                                a += tm_hi.tm_sec - tptr->tm_sec;
                                b += tptr->tm_sec - tm_lo.tm_sec;
                            }
                        }
                    }
                }
            }
            if (a <= 0) a = 1;
            if (b <= 0) b = 1;
            d = a + b;
            /*
              Although `/' and `%' may produce unexpected result with negative
              argument, it doesn't cause serious problem because there is a
              fail safe.
            */
            guess = guess_lo / d * a + (guess_lo % d) * a / d
                    + guess_hi / d * b + (guess_hi % d) * b / d;
            try_interpolation = 2;
        }
        else if (try_interpolation == 2) {
            guess = guess - range;
            range = 0;
            try_interpolation = 1;
        }
        else if (try_interpolation == 3) {
            guess = guess + range;
            range = 0;
            try_interpolation = 1;
        }

        if (try_interpolation == 0 || guess <= guess_lo || guess_hi <= guess) {
            /* Precious guess is invalid. try binary search. */
            guess = guess_lo / 2 + guess_hi / 2;
            if (guess <= guess_lo)
                guess = guess_lo + 1;
            else if (guess >= guess_hi)
                guess = guess_hi - 1;
            range = 0;
            try_interpolation = 1;
        }

	tm = GUESS(&guess);
	if (!tm) goto error;

	d = tmcmp(tptr, tm);

        if (d < 0) {
            if (range)
                try_interpolation = 2;
            else if ((unsigned_time_t)(guess-guess_lo) > (unsigned_time_t)(guess_hi-guess))
                try_interpolation = 0;
            else
                try_interpolation = 1;
            guess_hi = guess;
            tm_hi = *tm;
        }
        else if (d > 0) {
            if (range)
                try_interpolation = 3;
            else if ((unsigned_time_t)(guess-guess_lo) < (unsigned_time_t)(guess_hi-guess))
                try_interpolation = 0;
            else
                try_interpolation = 1;
            guess_lo = guess;
            tm_lo = *tm;
        }
        else {
          found:
	    if (!utc_p) {
		/* If localtime is nonmonotonic, another result may exist. */
		time_t guess2;
		if (find_dst) {
		    guess2 = guess - 2 * 60 * 60;
		    tm = LOCALTIME(&guess2, result);
		    if (tm) {
			if (tptr->tm_hour != (tm->tm_hour + 2) % 24 ||
			    tptr->tm_min != tm->tm_min ||
			    tptr->tm_sec != tm->tm_sec) {
			    guess2 -= (tm->tm_hour - tptr->tm_hour) * 60 * 60 +
				      (tm->tm_min - tptr->tm_min) * 60 +
				      (tm->tm_sec - tptr->tm_sec);
			    if (tptr->tm_mday != tm->tm_mday)
				guess2 += 24 * 60 * 60;
			    if (guess != guess2) {
				tm = LOCALTIME(&guess2, result);
				if (tmcmp(tptr, tm) == 0) {
				    if (guess < guess2)
					*tp = guess;
				    else
					*tp = guess2;
                                    return NULL;
				}
			    }
			}
		    }
		}
		else {
		    guess2 = guess + 2 * 60 * 60;
		    tm = LOCALTIME(&guess2, result);
		    if (tm) {
			if ((tptr->tm_hour + 2) % 24 != tm->tm_hour ||
			    tptr->tm_min != tm->tm_min ||
			    tptr->tm_sec != tm->tm_sec) {
			    guess2 -= (tm->tm_hour - tptr->tm_hour) * 60 * 60 +
				      (tm->tm_min - tptr->tm_min) * 60 +
				      (tm->tm_sec - tptr->tm_sec);
			    if (tptr->tm_mday != tm->tm_mday)
				guess2 -= 24 * 60 * 60;
			    if (guess != guess2) {
				tm = LOCALTIME(&guess2, result);
				if (tmcmp(tptr, tm) == 0) {
				    if (guess < guess2)
					*tp = guess2;
				    else
					*tp = guess;
                                    return NULL;
				}
			    }
			}
		    }
		}
	    }
            *tp = guess;
            return NULL;
	}
    }
    /* Given argument has no corresponding time_t. Let's outerpolation. */
    if (tm_lo.tm_year == tptr->tm_year && tm_lo.tm_mon == tptr->tm_mon) {
	*tp = guess_lo +
	      (tptr->tm_mday - tm_lo.tm_mday) * 24 * 60 * 60 +
	      (tptr->tm_hour - tm_lo.tm_hour) * 60 * 60 +
	      (tptr->tm_min - tm_lo.tm_min) * 60 +
	      (tptr->tm_sec - tm_lo.tm_sec);
        return NULL;
    }
    else if (tm_hi.tm_year == tptr->tm_year && tm_hi.tm_mon == tptr->tm_mon) {
	*tp = guess_hi +
	      (tptr->tm_mday - tm_hi.tm_mday) * 24 * 60 * 60 +
	      (tptr->tm_hour - tm_hi.tm_hour) * 60 * 60 +
	      (tptr->tm_min - tm_hi.tm_min) * 60 +
	      (tptr->tm_sec - tm_hi.tm_sec);
        return NULL;
    }

  out_of_range:
    return "time out of range";

  error:
    return "gmtime/localtime error";
}

static int
vtmcmp(struct vtm *a, struct vtm *b)
{
    if (ne(a->year, b->year))
	return lt(a->year, b->year) ? -1 : 1;
    else if (a->mon != b->mon)
	return a->mon < b->mon ? -1 : 1;
    else if (a->mday != b->mday)
	return a->mday < b->mday ? -1 : 1;
    else if (a->hour != b->hour)
	return a->hour < b->hour ? -1 : 1;
    else if (a->min != b->min)
	return a->min < b->min ? -1 : 1;
    else if (a->sec != b->sec)
	return a->sec < b->sec ? -1 : 1;
    else if (ne(a->subsec, b->subsec))
	return lt(a->subsec, b->subsec) ? -1 : 1;
    else
        return 0;
}

static int
tmcmp(struct tm *a, struct tm *b)
{
    if (a->tm_year != b->tm_year)
	return a->tm_year < b->tm_year ? -1 : 1;
    else if (a->tm_mon != b->tm_mon)
	return a->tm_mon < b->tm_mon ? -1 : 1;
    else if (a->tm_mday != b->tm_mday)
	return a->tm_mday < b->tm_mday ? -1 : 1;
    else if (a->tm_hour != b->tm_hour)
	return a->tm_hour < b->tm_hour ? -1 : 1;
    else if (a->tm_min != b->tm_min)
	return a->tm_min < b->tm_min ? -1 : 1;
    else if (a->tm_sec != b->tm_sec)
	return a->tm_sec < b->tm_sec ? -1 : 1;
    else
        return 0;
}

static VALUE
time_utc_or_local(int argc, VALUE *argv, int utc_p, VALUE klass)
{
    struct vtm vtm;
    VALUE time;

    time_arg(argc, argv, &vtm);
    if (utc_p)
        time = time_new_timev(klass, timegmv(&vtm));
    else
        time = time_new_timev(klass, timelocalv(&vtm));
    if (utc_p) return time_gmtime(time);
    return time_localtime(time);
}

/*
 *  call-seq:
 *    Time.utc(year) => time
 *    Time.utc(year, month) => time
 *    Time.utc(year, month, day) => time
 *    Time.utc(year, month, day, hour) => time
 *    Time.utc(year, month, day, hour, min) => time
 *    Time.utc(year, month, day, hour, min, sec_with_frac) => time
 *    Time.utc(year, month, day, hour, min, sec, usec_with_frac) => time
 *    Time.utc(sec, min, hour, day, month, year, wday, yday, isdst, tz) => time
 *    Time.gm(year) => time
 *    Time.gm(year, month) => time
 *    Time.gm(year, month, day) => time
 *    Time.gm(year, month, day, hour) => time
 *    Time.gm(year, month, day, hour, min) => time
 *    Time.gm(year, month, day, hour, min, sec_with_frac) => time
 *    Time.gm(year, month, day, hour, min, sec, usec_with_frac) => time
 *    Time.gm(sec, min, hour, day, month, year, wday, yday, isdst, tz) => time
 *
 *  Creates a time based on given values, interpreted as UTC (GMT). The
 *  year must be specified. Other values default to the minimum value
 *  for that field (and may be <code>nil</code> or omitted). Months may
 *  be specified by numbers from 1 to 12, or by the three-letter English
 *  month names. Hours are specified on a 24-hour clock (0..23). Raises
 *  an <code>ArgumentError</code> if any values are out of range. Will
 *  also accept ten arguments in the order output by
 *  <code>Time#to_a</code>.
 *  <i>sec_with_frac</i> and <i>usec_with_frac</i> can have a fractional part.
 *
 *     Time.utc(2000,"jan",1,20,15,1)  #=> 2000-01-01 20:15:01 UTC
 *     Time.gm(2000,"jan",1,20,15,1)   #=> 2000-01-01 20:15:01 UTC
 */
static VALUE
time_s_mkutc(int argc, VALUE *argv, VALUE klass)
{
    return time_utc_or_local(argc, argv, Qtrue, klass);
}

/*
 *  call-seq:
 *   Time.local(year) => time
 *   Time.local(year, month) => time
 *   Time.local(year, month, day) => time
 *   Time.local(year, month, day, hour) => time
 *   Time.local(year, month, day, hour, min) => time
 *   Time.local(year, month, day, hour, min, sec_with_frac) => time
 *   Time.local(year, month, day, hour, min, sec, usec_with_frac) => time
 *   Time.local(sec, min, hour, day, month, year, wday, yday, isdst, tz) => time
 *   Time.mktime(year) => time
 *   Time.mktime(year, month) => time
 *   Time.mktime(year, month, day) => time
 *   Time.mktime(year, month, day, hour) => time
 *   Time.mktime(year, month, day, hour, min) => time
 *   Time.mktime(year, month, day, hour, min, sec_with_frac) => time
 *   Time.mktime(year, month, day, hour, min, sec, usec_with_frac) => time
 *   Time.mktime(sec, min, hour, day, month, year, wday, yday, isdst, tz) => time
 *
 *  Same as <code>Time::gm</code>, but interprets the values in the
 *  local time zone.
 *
 *     Time.local(2000,"jan",1,20,15,1)   #=> 2000-01-01 20:15:01 -0600
 */

static VALUE
time_s_mktime(int argc, VALUE *argv, VALUE klass)
{
    return time_utc_or_local(argc, argv, Qfalse, klass);
}

/*
 *  call-seq:
 *     time.to_i   => int
 *     time.tv_sec => int
 *
 *  Returns the value of <i>time</i> as an integer number of seconds
 *  since the Epoch.
 *
 *     t = Time.now
 *     "%10.5f" % t.to_f   #=> "1049896564.17839"
 *     t.to_i              #=> 1049896564
 */

static VALUE
time_to_i(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return div(tobj->timev, INT2FIX(1));
}

/*
 *  call-seq:
 *     time.to_f => float
 *
 *  Returns the value of <i>time</i> as a floating point number of
 *  seconds since the Epoch.
 *
 *     t = Time.now
 *     "%10.5f" % t.to_f   #=> "1049896564.13654"
 *     t.to_i              #=> 1049896564
 *
 *  Note that IEEE 754 double is not accurate enough to represent
 *  nanoseconds from the Epoch.
 */

static VALUE
time_to_f(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_Float(tobj->timev);
}

/*
 *  call-seq:
 *     time.to_r => Rational
 *
 *  Returns the value of <i>time</i> as a rational number of seconds
 *  since the Epoch.
 *
 *     t = Time.now
 *     p t.to_r            #=> (8807170717088293/8388608)
 *
 *  This methods is intended to be used to get an accurate value
 *  representing nanoseconds from the Epoch.  You can use this
 *  to convert time to another Epoch.
 */

static VALUE
time_to_r(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return tobj->timev;
}

/*
 *  call-seq:
 *     time.usec    => int
 *     time.tv_usec => int
 *
 *  Returns just the number of microseconds for <i>time</i>.
 *
 *     t = Time.now        #=> 2007-11-19 08:03:26 -0600
 *     "%10.6f" % t.to_f   #=> "1195481006.775195"
 *     t.usec              #=> 775195
 */

static VALUE
time_usec(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_to_int(mul(mod(tobj->timev, INT2FIX(1)), INT2FIX(1000000)));
}

/*
 *  call-seq:
 *     time.nsec    => int
 *     time.tv_nsec => int
 *
 *  Returns just the number of nanoseconds for <i>time</i>.
 *
 *     t = Time.now        #=> 2007-11-17 15:18:03 +0900
 *     "%10.9f" % t.to_f   #=> "1195280283.536151409"
 *     t.nsec              #=> 536151406
 *
 *  The lowest digit of to_f and nsec is different because
 *  IEEE 754 double is not accurate enough to represent
 *  nanoseconds from the Epoch.
 *  The accurate value is returned by nsec.
 */

static VALUE
time_nsec(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_to_int(mul(mod(tobj->timev, INT2FIX(1)), INT2FIX(1000000000)));
}

/*
 *  call-seq:
 *     time.subsec    => number
 *
 *  Returns just the fraction for <i>time</i>.
 *
 *  The result is possibly rational.
 *
 *     t = Time.now        #=> 2009-03-26 22:33:12 +0900
 *     "%10.9f" % t.to_f   #=> "1238074392.940563917"
 *     t.subsec            #=> (94056401/100000000)
 *
 *  The lowest digit of to_f and subsec is different because
 *  IEEE 754 double is not accurate enough to represent
 *  the rational.
 *  The accurate value is returned by subsec.
 */

static VALUE
time_subsec(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return mod(tobj->timev, INT2FIX(1));
}

/*
 *  call-seq:
 *     time <=> other_time => -1, 0, +1
 *
 *  Comparison---Compares <i>time</i> with <i>other_time</i>.
 *
 *     t = Time.now       #=> 2007-11-19 08:12:12 -0600
 *     t2 = t + 2592000   #=> 2007-12-19 08:12:12 -0600
 *     t <=> t2           #=> -1
 *     t2 <=> t           #=> 1
 *
 *     t = Time.now       #=> 2007-11-19 08:13:38 -0600
 *     t2 = t + 0.1       #=> 2007-11-19 08:13:38 -0600
 *     t.nsec             #=> 98222999
 *     t2.nsec            #=> 198222999
 *     t <=> t2           #=> -1
 *     t2 <=> t           #=> 1
 *     t <=> t            #=> 0
 */

static VALUE
time_cmp(VALUE time1, VALUE time2)
{
    struct time_object *tobj1, *tobj2;
    int n;

    GetTimeval(time1, tobj1);
    if (TYPE(time2) == T_DATA && RDATA(time2)->dfree == time_free) {
	GetTimeval(time2, tobj2);
	n = rb_cmpint(cmp(tobj1->timev, tobj2->timev), tobj1->timev, tobj2->timev);
    }
    else {
	VALUE cmp;

	cmp = rb_funcall(time2, rb_intern("<=>"), 1, time1);
	if (NIL_P(cmp)) return Qnil;

	n = -rb_cmpint(cmp, time1, time2);
    }
    if (n == 0) return INT2FIX(0);
    if (n > 0) return INT2FIX(1);
    return INT2FIX(-1);
}

/*
 * call-seq:
 *  time.eql?(other_time)
 *
 * Return <code>true</code> if <i>time</i> and <i>other_time</i> are
 * both <code>Time</code> objects with the same seconds and fractional
 * seconds.
 */

static VALUE
time_eql(VALUE time1, VALUE time2)
{
    struct time_object *tobj1, *tobj2;

    GetTimeval(time1, tobj1);
    if (TYPE(time2) == T_DATA && RDATA(time2)->dfree == time_free) {
	GetTimeval(time2, tobj2);
        return rb_equal(tobj1->timev, tobj2->timev);
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     time.utc? => true or false
 *     time.gmt? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents a time in UTC
 *  (GMT).
 *
 *     t = Time.now                        #=> 2007-11-19 08:15:23 -0600
 *     t.utc?                              #=> false
 *     t = Time.gm(2000,"jan",1,20,15,1)   #=> 2000-01-01 20:15:01 UTC
 *     t.utc?                              #=> true
 *
 *     t = Time.now                        #=> 2007-11-19 08:16:03 -0600
 *     t.gmt?                              #=> false
 *     t = Time.gm(2000,1,1,20,15,1)       #=> 2000-01-01 20:15:01 UTC
 *     t.gmt?                              #=> true
 */

static VALUE
time_utc_p(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (TIME_UTC_P(tobj)) return Qtrue;
    return Qfalse;
}

/*
 * call-seq:
 *   time.hash   => fixnum
 *
 * Return a hash code for this time object.
 */

static VALUE
time_hash(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_hash(tobj->timev);
}

/* :nodoc: */
static VALUE
time_init_copy(VALUE copy, VALUE time)
{
    struct time_object *tobj, *tcopy;

    if (copy == time) return copy;
    time_modify(copy);
    if (TYPE(time) != T_DATA || RDATA(time)->dfree != time_free) {
	rb_raise(rb_eTypeError, "wrong argument type");
    }
    GetTimeval(time, tobj);
    GetTimeval(copy, tcopy);
    MEMCPY(tcopy, tobj, struct time_object, 1);

    return copy;
}

static VALUE
time_dup(VALUE time)
{
    VALUE dup = time_s_alloc(CLASS_OF(time));
    time_init_copy(dup, time);
    return dup;
}

static VALUE
time_localtime(VALUE time)
{
    struct time_object *tobj;
    struct vtm vtm;

    GetTimeval(time, tobj);
    if (TIME_LOCALTIME_P(tobj)) {
	if (tobj->tm_got)
	    return time;
    }
    else {
	time_modify(time);
    }

    if (!localtimev(tobj->timev, &vtm))
	rb_raise(rb_eArgError, "localtime error");
    tobj->vtm = vtm;

    tobj->tm_got = 1;
    TIME_SET_LOCALTIME(tobj);
    return time;
}

/*
 *  call-seq:
 *     time.localtime => time
 *     time.localtime(utc_offset) => time
 *
 *  Converts <i>time</i> to local time (using the local time zone in
 *  effect for this process) modifying the receiver.
 *
 *  If _utc_offset_ is given, it is used instead of the local time.
 *
 *     t = Time.utc(2000, "jan", 1, 20, 15, 1) #=> 2000-01-01 20:15:01 UTC
 *     t.utc?                                  #=> true
 *
 *     t.localtime                             #=> 2000-01-01 14:15:01 -0600
 *     t.utc?                                  #=> false
 *
 *     t.localtime("+09:00")                   #=> 2000-01-02 05:15:01 +0900
 *     t.utc?                                  #=> false
 */

static VALUE
time_localtime_m(int argc, VALUE *argv, VALUE time)
{
    VALUE off;
    rb_scan_args(argc, argv, "01", &off);

    if (!NIL_P(off)) {
        off = utc_offset_arg(off);
        validate_utc_offset(off);

        time_set_utc_offset(time, off);
        return time_fixoff(time);
    }

    return time_localtime(time);
}

/*
 *  call-seq:
 *     time.gmtime    => time
 *     time.utc       => time
 *
 *  Converts <i>time</i> to UTC (GMT), modifying the receiver.
 *
 *     t = Time.now   #=> 2007-11-19 08:18:31 -0600
 *     t.gmt?         #=> false
 *     t.gmtime       #=> 2007-11-19 14:18:31 UTC
 *     t.gmt?         #=> true
 *
 *     t = Time.now   #=> 2007-11-19 08:18:51 -0600
 *     t.utc?         #=> false
 *     t.utc          #=> 2007-11-19 14:18:51 UTC
 *     t.utc?         #=> true
 */

static VALUE
time_gmtime(VALUE time)
{
    struct time_object *tobj;
    struct vtm vtm;

    GetTimeval(time, tobj);
    if (TIME_UTC_P(tobj)) {
	if (tobj->tm_got)
	    return time;
    }
    else {
	time_modify(time);
    }

    if (!gmtimev(tobj->timev, &vtm))
	rb_raise(rb_eArgError, "gmtime error");
    tobj->vtm = vtm;

    tobj->tm_got = 1;
    TIME_SET_UTC(tobj);
    return time;
}

static VALUE
time_fixoff(VALUE time)
{
    struct time_object *tobj;
    struct vtm vtm;
    VALUE off;

    GetTimeval(time, tobj);
    if (TIME_FIXOFF_P(tobj)) {
       if (tobj->tm_got)
           return time;
    }
    else {
       time_modify(time);
    }

    if (TIME_FIXOFF_P(tobj))
        off = tobj->vtm.utc_offset;
    else
        off = INT2FIX(0);

    if (!gmtimev(tobj->timev, &vtm))
       rb_raise(rb_eArgError, "gmtime error");

    tobj->vtm = vtm;
    vtm_add_offset(&tobj->vtm, off);

    tobj->tm_got = 1;
    TIME_SET_FIXOFF(tobj, off);
    return time;
}

/*
 *  call-seq:
 *     time.getlocal => new_time
 *     time.getlocal(utc_offset) => new_time
 *
 *  Returns a new <code>new_time</code> object representing <i>time</i> in
 *  local time (using the local time zone in effect for this process).
 *
 *  If _utc_offset_ is given, it is used instead of the local time.
 *
 *     t = Time.utc(2000,1,1,20,15,1)  #=> 2000-01-01 20:15:01 UTC
 *     t.utc?                          #=> true
 *
 *     l = t.getlocal                  #=> 2000-01-01 14:15:01 -0600
 *     l.utc?                          #=> false
 *     t == l                          #=> true
 *
 *     j = t.getlocal("+09:00")        #=> 2000-01-02 05:15:01 +0900
 *     j.utc?                          #=> false
 *     t == j                          #=> true
 */

static VALUE
time_getlocaltime(int argc, VALUE *argv, VALUE time)
{
    VALUE off;
    rb_scan_args(argc, argv, "01", &off);

    if (!NIL_P(off)) {
        off = utc_offset_arg(off);
        validate_utc_offset(off);

        time = time_dup(time);
        time_set_utc_offset(time, off);
        return time_fixoff(time);
    }

    return time_localtime(time_dup(time));
}

/*
 *  call-seq:
 *     time.getgm  => new_time
 *     time.getutc => new_time
 *
 *  Returns a new <code>new_time</code> object representing <i>time</i> in
 *  UTC.
 *
 *     t = Time.local(2000,1,1,20,15,1)   #=> 2000-01-01 20:15:01 -0600
 *     t.gmt?                             #=> false
 *     y = t.getgm                        #=> 2000-01-02 02:15:01 UTC
 *     y.gmt?                             #=> true
 *     t == y                             #=> true
 */

static VALUE
time_getgmtime(VALUE time)
{
    return time_gmtime(time_dup(time));
}

static VALUE
time_get_tm(VALUE time, struct time_object *tobj)
{
    if (TIME_UTC_P(tobj)) return time_gmtime(time);
    if (TIME_FIXOFF_P(tobj)) return time_fixoff(time);
    return time_localtime(time);
}

static VALUE strftimev(const char *fmt, VALUE time);

/*
 *  call-seq:
 *     time.asctime => string
 *     time.ctime   => string
 *
 *  Returns a canonical string representation of <i>time</i>.
 *
 *     Time.now.asctime   #=> "Wed Apr  9 08:56:03 2003"
 */

static VALUE
time_asctime(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return strftimev("%a %b %e %T %Y", time);
}

/*
 *  call-seq:
 *     time.inspect => string
 *     time.to_s    => string
 *
 *  Returns a string representing <i>time</i>. Equivalent to calling
 *  <code>Time#strftime</code> with a format string of
 *  ``<code>%Y-%m-%d</code> <code>%H:%M:%S</code> <code>%z</code>''
 *  for a local time and
 *  ``<code>%Y-%m-%d</code> <code>%H:%M:%S</code> <code>UTC</code>''
 *  for a UTC time.
 *
 *     Time.now.to_s       #=> "2007-10-05 16:09:51 +0900"
 *     Time.now.utc.to_s   #=> "2007-10-05 07:09:51 UTC"
 */

static VALUE
time_to_s(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (TIME_UTC_P(tobj))
        return strftimev("%Y-%m-%d %H:%M:%S UTC", time);
    else
        return strftimev("%Y-%m-%d %H:%M:%S %z", time);
}

static VALUE
time_add(struct time_object *tobj, VALUE offset, int sign)
{
    VALUE result;
    offset = num_exact(offset);
    if (sign < 0)
        result = time_new_timev(rb_cTime, sub(tobj->timev, offset));
    else
        result = time_new_timev(rb_cTime, add(tobj->timev, offset));
    if (TIME_UTC_P(tobj)) {
	GetTimeval(result, tobj);
        TIME_SET_UTC(tobj);
    }
    return result;
}

/*
 *  call-seq:
 *     time + numeric => time
 *
 *  Addition---Adds some number of seconds (possibly fractional) to
 *  <i>time</i> and returns that value as a new time.
 *
 *     t = Time.now         #=> 2007-11-19 08:22:21 -0600
 *     t + (60 * 60 * 24)   #=> 2007-11-20 08:22:21 -0600
 */

static VALUE
time_plus(VALUE time1, VALUE time2)
{
    struct time_object *tobj;
    GetTimeval(time1, tobj);

    if (TYPE(time2) == T_DATA && RDATA(time2)->dfree == time_free) {
	rb_raise(rb_eTypeError, "time + time?");
    }
    return time_add(tobj, time2, 1);
}

/*
 *  call-seq:
 *     time - other_time => float
 *     time - numeric    => time
 *
 *  Difference---Returns a new time that represents the difference
 *  between two times, or subtracts the given number of seconds in
 *  <i>numeric</i> from <i>time</i>.
 *
 *     t = Time.now       #=> 2007-11-19 08:23:10 -0600
 *     t2 = t + 2592000   #=> 2007-12-19 08:23:10 -0600
 *     t2 - t             #=> 2592000.0
 *     t2 - 2592000       #=> 2007-11-19 08:23:10 -0600
 */

static VALUE
time_minus(VALUE time1, VALUE time2)
{
    struct time_object *tobj;

    GetTimeval(time1, tobj);
    if (TYPE(time2) == T_DATA && RDATA(time2)->dfree == time_free) {
	struct time_object *tobj2;

	GetTimeval(time2, tobj2);
        return rb_Float(sub(tobj->timev, tobj2->timev));
    }
    return time_add(tobj, time2, -1);
}

/*
 * call-seq:
 *   time.succ   => new_time
 *
 * Return a new time object, one second later than <code>time</code>.
 *
 *     t = Time.now       #=> 2007-11-19 08:23:57 -0600
 *     t.succ             #=> 2007-11-19 08:23:58 -0600
 */

static VALUE
time_succ(VALUE time)
{
    struct time_object *tobj;
    struct time_object *tobj2;

    GetTimeval(time, tobj);
    time = time_new_timev(rb_cTime, add(tobj->timev, INT2FIX(1)));
    GetTimeval(time, tobj2);
    TIME_COPY_GMT(tobj2, tobj);
    return time;
}

VALUE
rb_time_succ(VALUE time)
{
    return time_succ(time);
}

/*
 *  call-seq:
 *     time.sec => fixnum
 *
 *  Returns the second of the minute (0..60)<em>[Yes, seconds really can
 *  range from zero to 60. This allows the system to inject leap seconds
 *  every now and then to correct for the fact that years are not really
 *  a convenient number of hours long.]</em> for <i>time</i>.
 *
 *     t = Time.now   #=> 2007-11-19 08:25:02 -0600
 *     t.sec          #=> 2
 */

static VALUE
time_sec(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.sec);
}

/*
 *  call-seq:
 *     time.min => fixnum
 *
 *  Returns the minute of the hour (0..59) for <i>time</i>.
 *
 *     t = Time.now   #=> 2007-11-19 08:25:51 -0600
 *     t.min          #=> 25
 */

static VALUE
time_min(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.min);
}

/*
 *  call-seq:
 *     time.hour => fixnum
 *
 *  Returns the hour of the day (0..23) for <i>time</i>.
 *
 *     t = Time.now   #=> 2007-11-19 08:26:20 -0600
 *     t.hour         #=> 8
 */

static VALUE
time_hour(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.hour);
}

/*
 *  call-seq:
 *     time.day  => fixnum
 *     time.mday => fixnum
 *
 *  Returns the day of the month (1..n) for <i>time</i>.
 *
 *     t = Time.now   #=> 2007-11-19 08:27:03 -0600
 *     t.day          #=> 19
 *     t.mday         #=> 19
 */

static VALUE
time_mday(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.mday);
}

/*
 *  call-seq:
 *     time.mon   => fixnum
 *     time.month => fixnum
 *
 *  Returns the month of the year (1..12) for <i>time</i>.
 *
 *     t = Time.now   #=> 2007-11-19 08:27:30 -0600
 *     t.mon          #=> 11
 *     t.month        #=> 11
 */

static VALUE
time_mon(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.mon);
}

/*
 *  call-seq:
 *     time.year => fixnum
 *
 *  Returns the year for <i>time</i> (including the century).
 *
 *     t = Time.now   #=> 2007-11-19 08:27:51 -0600
 *     t.year         #=> 2007
 */

static VALUE
time_year(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return tobj->vtm.year;
}

/*
 *  call-seq:
 *     time.wday => fixnum
 *
 *  Returns an integer representing the day of the week, 0..6, with
 *  Sunday == 0.
 *
 *     t = Time.now   #=> 2007-11-20 02:35:35 -0600
 *     t.wday         #=> 2
 *     t.sunday?      #=> false
 *     t.monday?      #=> false
 *     t.tuesday?     #=> true
 *     t.wednesday?   #=> false
 *     t.thursday?    #=> false
 *     t.friday?      #=> false
 *     t.saturday?    #=> false
 */

static VALUE
time_wday(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.wday);
}

#define wday_p(n) {\
    struct time_object *tobj;\
    GetTimeval(time, tobj);\
    MAKE_TM(time, tobj);\
    return (tobj->vtm.wday == (n)) ? Qtrue : Qfalse;\
}

/*
 *  call-seq:
 *     time.sunday? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents Sunday.
 *
 *     t = Time.local(1990, 4, 1)       #=> 1990-04-01 00:00:00 -0600
 *     t.sunday?                        #=> true
 */

static VALUE
time_sunday(VALUE time)
{
    wday_p(0);
}

/*
 *  call-seq:
 *     time.monday? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents Monday.
 *
 *     t = Time.local(2003, 8, 4)       #=> 2003-08-04 00:00:00 -0500
 *     p t.monday?                      #=> true
 */

static VALUE
time_monday(VALUE time)
{
    wday_p(1);
}

/*
 *  call-seq:
 *     time.tuesday? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents Tuesday.
 *
 *     t = Time.local(1991, 2, 19)      #=> 1991-02-19 00:00:00 -0600
 *     p t.tuesday?                     #=> true
 */

static VALUE
time_tuesday(VALUE time)
{
    wday_p(2);
}

/*
 *  call-seq:
 *     time.wednesday? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents Wednesday.
 *
 *     t = Time.local(1993, 2, 24)      #=> 1993-02-24 00:00:00 -0600
 *     p t.wednesday?                   #=> true
 */

static VALUE
time_wednesday(VALUE time)
{
    wday_p(3);
}

/*
 *  call-seq:
 *     time.thursday? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents Thursday.
 *
 *     t = Time.local(1995, 12, 21)     #=> 1995-12-21 00:00:00 -0600
 *     p t.thursday?                    #=> true
 */

static VALUE
time_thursday(VALUE time)
{
    wday_p(4);
}

/*
 *  call-seq:
 *     time.friday? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents Friday.
 *
 *     t = Time.local(1987, 12, 18)     #=> 1987-12-18 00:00:00 -0600
 *     t.friday?                        #=> true
 */

static VALUE
time_friday(VALUE time)
{
    wday_p(5);
}

/*
 *  call-seq:
 *     time.saturday? => true or false
 *
 *  Returns <code>true</code> if <i>time</i> represents Saturday.
 *
 *     t = Time.local(2006, 6, 10)      #=> 2006-06-10 00:00:00 -0500
 *     t.saturday?                      #=> true
 */

static VALUE
time_saturday(VALUE time)
{
    wday_p(6);
}

/*
 *  call-seq:
 *     time.yday => fixnum
 *
 *  Returns an integer representing the day of the year, 1..366.
 *
 *     t = Time.now   #=> 2007-11-19 08:32:31 -0600
 *     t.yday         #=> 323
 */

static VALUE
time_yday(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return INT2FIX(tobj->vtm.yday);
}

/*
 *  call-seq:
 *     time.isdst => true or false
 *     time.dst?  => true or false
 *
 *  Returns <code>true</code> if <i>time</i> occurs during Daylight
 *  Saving Time in its time zone.
 *
 *   # CST6CDT:
 *     Time.local(2000, 1, 1).zone    #=> "CST"
 *     Time.local(2000, 1, 1).isdst   #=> false
 *     Time.local(2000, 1, 1).dst?    #=> false
 *     Time.local(2000, 7, 1).zone    #=> "CDT"
 *     Time.local(2000, 7, 1).isdst   #=> true
 *     Time.local(2000, 7, 1).dst?    #=> true
 *
 *   # Asia/Tokyo:
 *     Time.local(2000, 1, 1).zone    #=> "JST"
 *     Time.local(2000, 1, 1).isdst   #=> false
 *     Time.local(2000, 1, 1).dst?    #=> false
 *     Time.local(2000, 7, 1).zone    #=> "JST"
 *     Time.local(2000, 7, 1).isdst   #=> false
 *     Time.local(2000, 7, 1).dst?    #=> false
 */

static VALUE
time_isdst(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return tobj->vtm.isdst ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     time.zone => string
 *
 *  Returns the name of the time zone used for <i>time</i>. As of Ruby
 *  1.8, returns ``UTC'' rather than ``GMT'' for UTC times.
 *
 *     t = Time.gm(2000, "jan", 1, 20, 15, 1)
 *     t.zone   #=> "UTC"
 *     t = Time.local(2000, "jan", 1, 20, 15, 1)
 *     t.zone   #=> "CST"
 */

static VALUE
time_zone(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);

    if (TIME_UTC_P(tobj)) {
	return rb_str_new2("UTC");
    }
    if (tobj->vtm.zone == NULL)
        return Qnil;
    return rb_str_new2(tobj->vtm.zone);
}

/*
 *  call-seq:
 *     time.gmt_offset => fixnum
 *     time.gmtoff     => fixnum
 *     time.utc_offset => fixnum
 *
 *  Returns the offset in seconds between the timezone of <i>time</i>
 *  and UTC.
 *
 *     t = Time.gm(2000,1,1,20,15,1)   #=> 2000-01-01 20:15:01 UTC
 *     t.gmt_offset                    #=> 0
 *     l = t.getlocal                  #=> 2000-01-01 14:15:01 -0600
 *     l.gmt_offset                    #=> -21600
 */

static VALUE
time_utc_offset(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);

    if (TIME_UTC_P(tobj)) {
	return INT2FIX(0);
    }
    else {
	return tobj->vtm.utc_offset;
    }
}

/*
 *  call-seq:
 *     time.to_a => array
 *
 *  Returns a ten-element <i>array</i> of values for <i>time</i>:
 *  {<code>[ sec, min, hour, day, month, year, wday, yday, isdst, zone
 *  ]</code>}. See the individual methods for an explanation of the
 *  valid ranges of each value. The ten elements can be passed directly
 *  to <code>Time::utc</code> or <code>Time::local</code> to create a
 *  new <code>Time</code>.
 *
 *     t = Time.now     #=> 2007-11-19 08:36:01 -0600
 *     now = t.to_a     #=> [1, 36, 8, 19, 11, 2007, 1, 323, false, "CST"]
 */

static VALUE
time_to_a(VALUE time)
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    return rb_ary_new3(10,
		    INT2FIX(tobj->vtm.sec),
		    INT2FIX(tobj->vtm.min),
		    INT2FIX(tobj->vtm.hour),
		    INT2FIX(tobj->vtm.mday),
		    INT2FIX(tobj->vtm.mon),
		    tobj->vtm.year,
		    INT2FIX(tobj->vtm.wday),
		    INT2FIX(tobj->vtm.yday),
		    tobj->vtm.isdst?Qtrue:Qfalse,
		    time_zone(time));
}

size_t
rb_strftime(char *s, size_t maxsize, const char *format,
            const struct vtm *vtm, VALUE timev,
            int gmt);

#define SMALLBUF 100
static int
rb_strftime_alloc(char **buf, const char *format,
                  struct vtm *vtm, VALUE timev, int gmt)
{
    int size, len, flen;

    (*buf)[0] = '\0';
    flen = strlen(format);
    if (flen == 0) {
	return 0;
    }
    errno = 0;
    len = rb_strftime(*buf, SMALLBUF, format, vtm, timev, gmt);
    if (len != 0 || (**buf == '\0' && errno != ERANGE)) return len;
    for (size=1024; ; size*=2) {
	*buf = xmalloc(size);
	(*buf)[0] = '\0';
	len = rb_strftime(*buf, size, format, vtm, timev, gmt);
	/*
	 * buflen can be zero EITHER because there's not enough
	 * room in the string, or because the control command
	 * goes to the empty string. Make a reasonable guess that
	 * if the buffer is 1024 times bigger than the length of the
	 * format string, it's not failing for lack of room.
	 */
	if (len > 0 || size >= 1024 * flen) return len;
	xfree(*buf);
    }
    /* not reached */
}

static VALUE
strftimev(const char *fmt, VALUE time)
{
    struct time_object *tobj;
    char buffer[SMALLBUF], *buf = buffer;
    long len;
    VALUE str;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    len = rb_strftime_alloc(&buf, fmt, &tobj->vtm, tobj->timev, TIME_UTC_P(tobj));
    str = rb_str_new(buf, len);
    if (buf != buffer) xfree(buf);
    return str;
}

/*
 *  call-seq:
 *     time.strftime( string ) => string
 *
 *  Formats <i>time</i> according to the directives in the given format
 *  string. Any text not listed as a directive will be passed through
 *  to the output string.
 *
 *  Format meaning:
 *    %a - The abbreviated weekday name (``Sun'')
 *    %A - The  full  weekday  name (``Sunday'')
 *    %b - The abbreviated month name (``Jan'')
 *    %B - The  full  month  name (``January'')
 *    %c - The preferred local date and time representation
 *    %C - Century (20 in 2009)
 *    %d - Day of the month (01..31)
 *    %D - Date (%m/%d/%y)
 *    %e - Day of the month, blank-padded ( 1..31) 
 *    %F - Equivalent to %Y-%m-%d (the ISO 8601 date format)
 *    %h - Equivalent to %b
 *    %H - Hour of the day, 24-hour clock (00..23)
 *    %I - Hour of the day, 12-hour clock (01..12)
 *    %j - Day of the year (001..366)
 *    %k - hour, 24-hour clock, blank-padded ( 0..23) 
 *    %l - hour, 12-hour clock, blank-padded ( 0..12)
 *    %L - Millisecond of the second (000..999)
 *    %m - Month of the year (01..12)
 *    %M - Minute of the hour (00..59)
 *    %n - Newline (\n)
 *    %N - Fractional seconds digits, default is 9 digits (nanosecond)
 *            %3N  millisecond (3 digits)
 *            %6N  microsecond (6 digits)
 *            %9N  nanosecond (9 digits)
 *    %p - Meridian indicator (``AM''  or  ``PM'')
 *    %P - Meridian indicator (``am''  or  ``pm'')
 *    %r - time, 12-hour (same as %I:%M:%S %p)
 *    %R - time, 24-hour (%H:%M)
 *    %s - Number of seconds since 1970-01-01 00:00:00 UTC.
 *    %S - Second of the minute (00..60)
 *    %t - Tab character (\t)
 *    %T - time, 24-hour (%H:%M:%S)
 *    %u - Day of the week as a decimal, Monday being 1. (1..7)
 *    %U - Week  number  of the current year,
 *            starting with the first Sunday as the first
 *            day of the first week (00..53)
 *    %v - VMS date (%e-%b-%Y)
 *    %V - Week number of year according to ISO 8601 (01..53)
 *    %W - Week  number  of the current year,
 *            starting with the first Monday as the first
 *            day of the first week (00..53)
 *    %w - Day of the week (Sunday is 0, 0..6)
 *    %x - Preferred representation for the date alone, no time
 *    %X - Preferred representation for the time alone, no date
 *    %y - Year without a century (00..99)
 *    %Y - Year with century
 *    %z - Time zone as  hour offset from UTC (e.g. +0900)
 *    %Z - Time zone name
 *    %% - Literal ``%'' character
 *
 *     t = Time.now                        #=> 2007-11-19 08:37:48 -0600
 *     t.strftime("Printed on %m/%d/%Y")   #=> "Printed on 11/19/2007"
 *     t.strftime("at %I:%M%p")            #=> "at 08:37AM"
 */

static VALUE
time_strftime(VALUE time, VALUE format)
{
    void rb_enc_copy(VALUE, VALUE);
    struct time_object *tobj;
    char buffer[SMALLBUF], *buf = buffer;
    const char *fmt;
    long len;
    VALUE str;

    GetTimeval(time, tobj);
    MAKE_TM(time, tobj);
    StringValue(format);
    if (!rb_enc_str_asciicompat_p(format)) {
	rb_raise(rb_eArgError, "format should have ASCII compatible encoding");
    }
    format = rb_str_new4(format);
    fmt = RSTRING_PTR(format);
    len = RSTRING_LEN(format);
    if (len == 0) {
	rb_warning("strftime called with empty format string");
    }
    else if (memchr(fmt, '\0', len)) {
	/* Ruby string may contain \0's. */
	const char *p = fmt, *pe = fmt + len;

	str = rb_str_new(0, 0);
	while (p < pe) {
	    len = rb_strftime_alloc(&buf, p, &tobj->vtm, tobj->timev, TIME_UTC_P(tobj));
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
    else {
	len = rb_strftime_alloc(&buf, RSTRING_PTR(format),
			       	&tobj->vtm, tobj->timev, TIME_UTC_P(tobj));
    }
    str = rb_str_new(buf, len);
    if (buf != buffer) xfree(buf);
    rb_enc_copy(str, format);
    return str;
}

/*
 * undocumented
 */

static VALUE
time_mdump(VALUE time)
{
    struct time_object *tobj;
    unsigned long p, s;
    char buf[8];
    int i;
    VALUE str;

    struct vtm vtm;
    long year;
    long usec, nsec;
    VALUE subsec, subnano, v;

    GetTimeval(time, tobj);

    gmtimev(tobj->timev, &vtm);

    if (FIXNUM_P(vtm.year)) {
        year = FIX2LONG(vtm.year);
        if (year < 1900 || 1900+0xffff < year)
            rb_raise(rb_eArgError, "year too big to marshal: %ld", year);
    }
    else {
        rb_raise(rb_eArgError, "year too big to marshal");
    }

    subsec = vtm.subsec;

    subsec = mul(subsec, INT2FIX(1000000000));
    divmodv(subsec, INT2FIX(1), &v, &subnano);
    nsec = FIX2LONG(v);
    usec = nsec / 1000;
    nsec = nsec % 1000;

    p = 0x1UL            << 31 | /*  1 */
	TIME_UTC_P(tobj) << 30 | /*  1 */
	(year-1900)      << 14 | /* 16 */
	(vtm.mon-1)      << 10 | /*  4 */
	vtm.mday         <<  5 | /*  5 */
	vtm.hour;                /*  5 */
    s = vtm.min          << 26 | /*  6 */
	vtm.sec          << 20 | /*  6 */
	usec;    /* 20 */

    for (i=0; i<4; i++) {
	buf[i] = (unsigned char)p;
	p = RSHIFT(p, 8);
    }
    for (i=4; i<8; i++) {
	buf[i] = (unsigned char)s;
	s = RSHIFT(s, 8);
    }

    str = rb_str_new(buf, 8);
    rb_copy_generic_ivar(str, time);
    if (nsec) {
        /*
         * submicro is formatted in fixed-point packed BCD (without sign).
         * It represent digits under microsecond.
         * For nanosecond resolution, 3 digits (2 bytes) are used.
         * However it can be longer.
         * Extra digits are ignored for loading.
         */
        unsigned char buf[2];
        int len = sizeof(buf);
        buf[1] = (nsec % 10) << 4;
        nsec /= 10;
        buf[0] = nsec % 10;
        nsec /= 10;
        buf[0] |= (nsec % 10) << 4;
        if (buf[1] == 0)
            len = 1;
        rb_ivar_set(str, id_submicro, rb_str_new((char *)buf, len));
    }
    if (!rb_equal(subnano, INT2FIX(0))) {
        rb_ivar_set(str, id_subnano, subnano);
    }
    return str;
}

/*
 * call-seq:
 *   time._dump   => string
 *
 * Dump _time_ for marshaling.
 */

static VALUE
time_dump(int argc, VALUE *argv, VALUE time)
{
    VALUE str;

    rb_scan_args(argc, argv, "01", 0);
    str = time_mdump(time);

    return str;
}

/*
 * undocumented
 */

static VALUE
time_mload(VALUE time, VALUE str)
{
    struct time_object *tobj;
    unsigned long p, s;
    time_t sec;
    long usec;
    unsigned char *buf;
    struct vtm vtm;
    int i, gmt;
    long nsec;
    VALUE timev, submicro, subnano;

    time_modify(time);

    submicro = rb_attr_get(str, id_submicro);
    if (submicro != Qnil) {
        st_delete(rb_generic_ivar_table(str), (st_data_t*)&id_submicro, 0);
    }
    subnano = rb_attr_get(str, id_subnano);
    if (subnano != Qnil) {
        st_delete(rb_generic_ivar_table(str), (st_data_t*)&id_subnano, 0);
    }
    rb_copy_generic_ivar(time, str);

    StringValue(str);
    buf = (unsigned char *)RSTRING_PTR(str);
    if (RSTRING_LEN(str) != 8) {
	rb_raise(rb_eTypeError, "marshaled time format differ");
    }

    p = s = 0;
    for (i=0; i<4; i++) {
	p |= buf[i]<<(8*i);
    }
    for (i=4; i<8; i++) {
	s |= buf[i]<<(8*(i-4));
    }

    if ((p & (1UL<<31)) == 0) {
        gmt = 0;
	sec = p;
	usec = s;
        nsec = usec * 1000;
        timev = add(TIMET2NUM(sec), quo(LONG2FIX(usec), LONG2FIX(1000000)));
    }
    else {
	p &= ~(1UL<<31);
	gmt        = (p >> 30) & 0x1;

	vtm.year = INT2FIX(((p >> 14) & 0xffff) + 1900);
	vtm.mon  = ((p >> 10) & 0xf) + 1;
	vtm.mday = (p >>  5) & 0x1f;
	vtm.hour =  p        & 0x1f;
	vtm.min  = (s >> 26) & 0x3f;
	vtm.sec  = (s >> 20) & 0x3f;
        vtm.utc_offset = INT2FIX(0);
	vtm.yday = vtm.wday = 0;
	vtm.isdst = 0;
	vtm.zone = "";

	usec = (long)(s & 0xfffff);
        nsec = usec * 1000;

        if (submicro != Qnil) {
            unsigned char *ptr;
            long len;
            int digit;
            ptr = (unsigned char*)StringValuePtr(submicro);
            len = RSTRING_LEN(submicro);
            if (0 < len) {
                if (10 <= (digit = ptr[0] >> 4)) goto end_submicro;
                nsec += digit * 100;
                if (10 <= (digit = ptr[0] & 0xf)) goto end_submicro;
                nsec += digit * 10;
            }
            if (1 < len) {
                if (10 <= (digit = ptr[1] >> 4)) goto end_submicro;
                nsec += digit;
            }
end_submicro: ;
        }

        vtm.subsec = quo(LONG2FIX(nsec), LONG2FIX(1000000000));
        if (subnano != Qnil) {
            subnano = num_exact(subnano);
            vtm.subsec = add(vtm.subsec, quo(subnano, LONG2FIX(1000000000)));
        }
        timev = timegmv(&vtm);
    }

    GetTimeval(time, tobj);
    tobj->tm_got = 0;
    if (gmt) TIME_SET_UTC(tobj);
    tobj->timev = timev;

    return time;
}

/*
 * call-seq:
 *   Time._load(string)   => time
 *
 * Unmarshal a dumped +Time+ object.
 */

static VALUE
time_load(VALUE klass, VALUE str)
{
    VALUE time = time_s_alloc(klass);

    time_mload(time, str);
    return time;
}

/*
 *  <code>Time</code> is an abstraction of dates and times. Time is
 *  stored internally as the number of seconds with fraction since
 *  the <em>Epoch</em>, January 1, 1970 00:00 UTC.
 *  Also see the library modules <code>Date</code>.
 *  The <code>Time</code> class treats GMT (Greenwich Mean Time) and
 *  UTC (Coordinated Universal Time)<em>[Yes, UTC really does stand for
 *  Coordinated Universal Time. There was a committee involved.]</em>
 *  as equivalent.  GMT is the older way of referring to these
 *  baseline times but persists in the names of calls on POSIX
 *  systems.
 *
 *  All times may have fraction. Be aware of
 *  this fact when comparing times with each other---times that are
 *  apparently equal when displayed may be different when compared.
 */

void
Init_Time(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

    id_eq = rb_intern("==");
    id_ne = rb_intern("!=");
    id_quo = rb_intern("quo");
    id_div = rb_intern("div");
    id_cmp = rb_intern("<=>");
    id_lshift = rb_intern("<<");
    id_divmod = rb_intern("divmod");
    id_mul = rb_intern("*");
    id_submicro = rb_intern("submicro");
    id_subnano = rb_intern("subnano");

    rb_cTime = rb_define_class("Time", rb_cObject);
    rb_include_module(rb_cTime, rb_mComparable);

    rb_define_alloc_func(rb_cTime, time_s_alloc);
    rb_define_singleton_method(rb_cTime, "now", time_s_now, 0);
    rb_define_singleton_method(rb_cTime, "at", time_s_at, -1);
    rb_define_singleton_method(rb_cTime, "utc", time_s_mkutc, -1);
    rb_define_singleton_method(rb_cTime, "gm", time_s_mkutc, -1);
    rb_define_singleton_method(rb_cTime, "local", time_s_mktime, -1);
    rb_define_singleton_method(rb_cTime, "mktime", time_s_mktime, -1);

    rb_define_method(rb_cTime, "to_i", time_to_i, 0);
    rb_define_method(rb_cTime, "to_f", time_to_f, 0);
    rb_define_method(rb_cTime, "to_r", time_to_r, 0);
    rb_define_method(rb_cTime, "<=>", time_cmp, 1);
    rb_define_method(rb_cTime, "eql?", time_eql, 1);
    rb_define_method(rb_cTime, "hash", time_hash, 0);
    rb_define_method(rb_cTime, "initialize", time_init, -1);
    rb_define_method(rb_cTime, "initialize_copy", time_init_copy, 1);

    rb_define_method(rb_cTime, "localtime", time_localtime_m, -1);
    rb_define_method(rb_cTime, "gmtime", time_gmtime, 0);
    rb_define_method(rb_cTime, "utc", time_gmtime, 0);
    rb_define_method(rb_cTime, "getlocal", time_getlocaltime, -1);
    rb_define_method(rb_cTime, "getgm", time_getgmtime, 0);
    rb_define_method(rb_cTime, "getutc", time_getgmtime, 0);

    rb_define_method(rb_cTime, "ctime", time_asctime, 0);
    rb_define_method(rb_cTime, "asctime", time_asctime, 0);
    rb_define_method(rb_cTime, "to_s", time_to_s, 0);
    rb_define_method(rb_cTime, "inspect", time_to_s, 0);
    rb_define_method(rb_cTime, "to_a", time_to_a, 0);

    rb_define_method(rb_cTime, "+", time_plus, 1);
    rb_define_method(rb_cTime, "-", time_minus, 1);

    rb_define_method(rb_cTime, "succ", time_succ, 0);
    rb_define_method(rb_cTime, "sec", time_sec, 0);
    rb_define_method(rb_cTime, "min", time_min, 0);
    rb_define_method(rb_cTime, "hour", time_hour, 0);
    rb_define_method(rb_cTime, "mday", time_mday, 0);
    rb_define_method(rb_cTime, "day", time_mday, 0);
    rb_define_method(rb_cTime, "mon", time_mon, 0);
    rb_define_method(rb_cTime, "month", time_mon, 0);
    rb_define_method(rb_cTime, "year", time_year, 0);
    rb_define_method(rb_cTime, "wday", time_wday, 0);
    rb_define_method(rb_cTime, "yday", time_yday, 0);
    rb_define_method(rb_cTime, "isdst", time_isdst, 0);
    rb_define_method(rb_cTime, "dst?", time_isdst, 0);
    rb_define_method(rb_cTime, "zone", time_zone, 0);
    rb_define_method(rb_cTime, "gmtoff", time_utc_offset, 0);
    rb_define_method(rb_cTime, "gmt_offset", time_utc_offset, 0);
    rb_define_method(rb_cTime, "utc_offset", time_utc_offset, 0);

    rb_define_method(rb_cTime, "utc?", time_utc_p, 0);
    rb_define_method(rb_cTime, "gmt?", time_utc_p, 0);

    rb_define_method(rb_cTime, "sunday?", time_sunday, 0);
    rb_define_method(rb_cTime, "monday?", time_monday, 0);
    rb_define_method(rb_cTime, "tuesday?", time_tuesday, 0);
    rb_define_method(rb_cTime, "wednesday?", time_wednesday, 0);
    rb_define_method(rb_cTime, "thursday?", time_thursday, 0);
    rb_define_method(rb_cTime, "friday?", time_friday, 0);
    rb_define_method(rb_cTime, "saturday?", time_saturday, 0);

    rb_define_method(rb_cTime, "tv_sec", time_to_i, 0);
    rb_define_method(rb_cTime, "tv_usec", time_usec, 0);
    rb_define_method(rb_cTime, "usec", time_usec, 0);
    rb_define_method(rb_cTime, "tv_nsec", time_nsec, 0);
    rb_define_method(rb_cTime, "nsec", time_nsec, 0);
    rb_define_method(rb_cTime, "subsec", time_subsec, 0);

    rb_define_method(rb_cTime, "strftime", time_strftime, 1);

    /* methods for marshaling */
    rb_define_method(rb_cTime, "_dump", time_dump, -1);
    rb_define_singleton_method(rb_cTime, "_load", time_load, 1);
#if 0
    /* Time will support marshal_dump and marshal_load in the future (1.9 maybe) */
    rb_define_method(rb_cTime, "marshal_dump", time_mdump, 0);
    rb_define_method(rb_cTime, "marshal_load", time_mload, 1);
#endif

#ifdef FIND_TIME_NUMGUESS
    rb_define_virtual_variable("$find_time_numguess", find_time_numguess_getter, NULL);
#endif
}
