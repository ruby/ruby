/**********************************************************************

  time.c -

  $Author$
  $Date$
  created at: Tue Dec 28 14:31:59 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

**********************************************************************/

#include "ruby.h"
#include <sys/types.h>

#include <time.h>
#ifndef NT
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
#define time_t long
struct timeval {
        time_t tv_sec;		/* seconds */
        time_t tv_usec;		/* and microseconds */
};
#endif
#endif /* NT */

#ifdef HAVE_SYS_TIMES_H
#include <sys/times.h>
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

VALUE rb_cTime;
#if defined(HAVE_TIMES) || defined(NT)
static VALUE S_Tms;
#endif

struct time_object {
    struct timeval tv;
    struct tm tm;
    int gmt;
    int tm_got;
};

#define GetTimeval(obj, tobj) {\
    Data_Get_Struct(obj, struct time_object, tobj);\
}

static VALUE
time_s_now(klass)
    VALUE klass;
{
    VALUE obj;
    struct time_object *tobj;

    obj = Data_Make_Struct(klass, struct time_object, 0, free, tobj);
    tobj->tm_got=0;

    if (gettimeofday(&tobj->tv, 0) < 0) {
	rb_sys_fail("gettimeofday");
    }

    return obj;
}

static VALUE
time_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE obj = time_s_now(klass);

    rb_obj_call_init(obj, argc, argv);
    return obj;
}

static VALUE
time_new_internal(klass, sec, usec)
    VALUE klass;
    time_t sec, usec;
{
    VALUE obj;
    struct time_object *tobj;

    if (sec < 0 || (sec == 0 && usec < 0))
	rb_raise(rb_eArgError, "time must be positive");

    obj = Data_Make_Struct(klass, struct time_object, 0, free, tobj);
    tobj->tm_got = 0;
    tobj->tv.tv_sec = sec;
    tobj->tv.tv_usec = usec;

    return obj;
}

VALUE
rb_time_new(sec, usec)
    time_t sec, usec;
{
    return time_new_internal(rb_cTime, sec, usec);
}

static struct timeval
time_timeval(time, interval)
    VALUE time;
    int interval;
{
    struct timeval t;

    switch (TYPE(time)) {
      case T_FIXNUM:
	t.tv_sec = FIX2LONG(time);
	if (t.tv_sec < 0)
	    rb_raise(rb_eArgError, "time must be positive");
	t.tv_usec = 0;
	break;

      case T_FLOAT:
	if (RFLOAT(time)->value < 0.0)
	    rb_raise(rb_eArgError, "time must be positive");
	t.tv_sec = (time_t)RFLOAT(time)->value;
	t.tv_usec = (time_t)((RFLOAT(time)->value - (double)t.tv_sec)*1e6);
	break;

      case T_BIGNUM:
	t.tv_sec = NUM2LONG(time);
	if (t.tv_sec < 0)
	    rb_raise(rb_eArgError, "time must be positive");
	t.tv_usec = 0;
	break;

      default:
	rb_raise(rb_eTypeError, "can't convert %s into Time%s",
		 rb_class2name(CLASS_OF(time)),
		 interval ? " interval" : "");
	break;
    }
    return t;
}

struct timeval
rb_time_interval(time)
    VALUE time;
{
    return time_timeval(time, Qtrue);
}

struct timeval
rb_time_timeval(time)
    VALUE time;
{
    struct time_object *tobj;
    struct timeval t;

    if (rb_obj_is_kind_of(time, rb_cTime)) {
	GetTimeval(time, tobj);
	t = tobj->tv;
	return t;
    }
    return time_timeval(time, Qfalse);
}

static VALUE
time_s_at(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    struct timeval tv;
    VALUE time, t;

    if (rb_scan_args(argc, argv, "11", &time, &t) == 2) {
	tv.tv_sec = NUM2INT(time);
	tv.tv_usec = NUM2INT(t);
    }
    else {
	tv = rb_time_timeval(time);
    }
    t = time_new_internal(klass, tv.tv_sec, tv.tv_usec);
    if (TYPE(time) == T_DATA) {
	struct time_object *tobj, *tobj2;

	GetTimeval(time, tobj);
	GetTimeval(t, tobj2);
	tobj2->gmt = tobj->gmt;
    }
    return t;
}

static char *months [12] = {
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
};

static long
obj2long(obj)
    VALUE obj;
{
    if (TYPE(obj) == T_STRING) {
	obj = rb_str2inum(obj, 10);
    }

    return NUM2LONG(obj);
}

static void
time_arg(argc, argv, tm, usec)
    int argc;
    VALUE *argv;
    struct tm *tm;
    time_t *usec;
{
    VALUE v[7];
    int i;

    MEMZERO(tm, struct tm, 1);
    if (argc == 10) {
	v[0] = argv[5];
	v[1] = argv[4];
	v[2] = argv[3];
	v[3] = argv[2];
	v[4] = argv[1];
	v[5] = argv[0];
	*usec = 0;
	tm->tm_isdst = RTEST(argv[9]) ? 1 : 0;
    }
    else {
	rb_scan_args(argc, argv, "16", &v[0],&v[1],&v[2],&v[3],&v[4],&v[5],&v[6]);
	*usec = (argc == 7) ? NUM2INT(v[6]) : 0;
    }

    tm->tm_year = obj2long(v[0]);
    if (0 <= tm->tm_year && tm->tm_year < 69) tm->tm_year += 100;
    if (tm->tm_year >= 1900) tm->tm_year -= 1900;
    if (NIL_P(v[1])) {
	tm->tm_mon = 0;
    }
    else if (TYPE(v[1]) == T_STRING) {
	tm->tm_mon = -1;
	for (i=0; i<12; i++) {
	    if (RSTRING(v[1])->len == 3 &&
		strcasecmp(months[i], RSTRING(v[1])->ptr) == 0) {
		tm->tm_mon = i;
		break;
	    }
	}
	if (tm->tm_mon == -1) {
	    char c = RSTRING(v[1])->ptr[0];

	    if ('0' <= c && c <= '9') {
		tm->tm_mon = obj2long(v[1])-1;
	    }
	}
    }
    else {
	tm->tm_mon = obj2long(v[1]) - 1;
    }
    if (NIL_P(v[2])) {
	tm->tm_mday = 1;
    }
    else {
	tm->tm_mday = obj2long(v[2]);
    }
    tm->tm_hour = NIL_P(v[3])?0:obj2long(v[3]);
    tm->tm_min  = NIL_P(v[4])?0:obj2long(v[4]);
    tm->tm_sec  = NIL_P(v[5])?0:obj2long(v[5]);

    /* value validation */
    if (   tm->tm_year < 69
	|| tm->tm_mon  < 0 || tm->tm_mon  > 11
	|| tm->tm_mday < 1 || tm->tm_mday > 31
	|| tm->tm_hour < 0 || tm->tm_hour > 23
	|| tm->tm_min  < 0 || tm->tm_min  > 59
	|| tm->tm_sec  < 0 || tm->tm_sec  > 60)
	rb_raise(rb_eArgError, "argument out of range");
}

static VALUE time_gmtime _((VALUE));
static VALUE time_localtime _((VALUE));
static VALUE time_get_tm _((VALUE, int));

static time_t
make_time_t(tptr, utc_or_local)
    struct tm *tptr;
    int utc_or_local;
{
    struct timeval tv;
    time_t oguess, guess;
    struct tm *tm;
    long t, diff;

    if (gettimeofday(&tv, 0) < 0) {
	rb_sys_fail("gettimeofday");
    }
    guess = tv.tv_sec;

    tm = gmtime(&guess);
    if (!tm) goto error;
    t = tptr->tm_year;
    if (t < 69) goto out_of_range;
    while (diff = t - tm->tm_year) {
	oguess = guess;
	guess += diff * 363 * 24 * 3600;
	if (diff > 0 && guess <= oguess) goto out_of_range;
	tm = gmtime(&guess);
	if (!tm) goto error;
    }
    t = tptr->tm_mon;
    while (diff = t - tm->tm_mon) {
	guess += diff * 27 * 24 * 3600;
	tm = gmtime(&guess);
	if (!tm) goto error;
	if (tptr->tm_year != tm->tm_year) goto out_of_range;
    }
    guess += (tptr->tm_mday - tm->tm_mday) * 24 * 3600;
    guess += (tptr->tm_hour - tm->tm_hour) * 3600;
    guess += (tptr->tm_min - tm->tm_min) * 60;
    guess += (tptr->tm_sec - tm->tm_sec);
    if (guess < 0) goto out_of_range;

    if (!utc_or_local) {	/* localtime zone adjust */
	struct tm gt, lt;
	long tzsec;

	t = 0;
	tm = gmtime(&guess);
	if (!tm) goto error;
	gt = *tm;
	tm = localtime(&guess);
	if (!tm) goto error;
	lt = *tm;
	tzsec = (gt.tm_min-lt.tm_min)*60 + (gt.tm_hour-lt.tm_hour)*3600;

	if (lt.tm_year > gt.tm_year) {
	    tzsec -= 24*3600;
	}
	else if(gt.tm_year > lt.tm_year) {
	    tzsec += 24*3600;
	}
	else {
	    tzsec += (gt.tm_yday - lt.tm_yday)*24*3600;
	}
	if (lt.tm_isdst) guess += 3600;
	guess += tzsec;
	if (guess < 0) {
	    goto out_of_range;
	}
	tm = localtime(&guess);
	if (!tm) goto error;
	if (lt.tm_isdst != tm->tm_isdst || tptr->tm_hour != tm->tm_hour) {
	    oguess = guess - 3600;
	    tm = localtime(&oguess);
	    if (!tm) goto error;
	    if (tptr->tm_hour == tm->tm_hour) {
		guess = oguess;
	    }
	}
	if (guess < 0) {
	    goto out_of_range;
	}
    }

    return guess;

  out_of_range:
    rb_raise(rb_eArgError, "time out of range");

  error:
    rb_raise(rb_eArgError, "gmtime/localtime error");
    return 0;			/* not reached */
}

static VALUE
time_utc_or_local(argc, argv, utc_p, klass)
    int argc;
    VALUE *argv;
    int utc_p;
    VALUE klass;
{
    struct tm tm;
    VALUE time;
    time_t usec;

    time_arg(argc, argv, &tm, &usec);
    time = time_new_internal(klass, make_time_t(&tm, utc_p), usec);
    if (utc_p) return time_gmtime(time);
    return time_localtime(time);
}

static VALUE
time_s_mkutc(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    return time_utc_or_local(argc, argv, Qtrue, klass);
}

static VALUE
time_s_mktime(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    return time_utc_or_local(argc, argv, Qfalse, klass);
}

static VALUE
time_to_i(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return INT2NUM(tobj->tv.tv_sec);
}

static VALUE
time_to_f(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return rb_float_new((double)tobj->tv.tv_sec+(double)tobj->tv.tv_usec/1e6);
}

static VALUE
time_usec(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return INT2NUM(tobj->tv.tv_usec);
}

static VALUE
time_cmp(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    long i;

    GetTimeval(time1, tobj1);
    switch (TYPE(time2)) {
      case T_FIXNUM:
	i = FIX2LONG(time2);
	if (tobj1->tv.tv_sec == i) return INT2FIX(0);
	if (tobj1->tv.tv_sec > i) return INT2FIX(1);
	return INT2FIX(-1);
	
      case T_FLOAT:
	{
	    double t;

	    t = (double)tobj1->tv.tv_sec + (double)tobj1->tv.tv_usec*1e-6;
	    if (t > RFLOAT(time2)->value)
		return INT2FIX(1);
	    if (t < RFLOAT(time2)->value)
		return INT2FIX(-1);
	    return INT2FIX(0);
	}
    }

    if (rb_obj_is_kind_of(time2, rb_cTime)) {
	GetTimeval(time2, tobj2);
	if (tobj1->tv.tv_sec == tobj2->tv.tv_sec) {
	    if (tobj1->tv.tv_usec == tobj2->tv.tv_usec) return INT2FIX(0);
	    if (tobj1->tv.tv_usec > tobj2->tv.tv_usec) return INT2FIX(1);
	    return INT2FIX(-1);
	}
	if (tobj1->tv.tv_sec > tobj2->tv.tv_sec) return INT2FIX(1);
	return INT2FIX(-1);
    }
    i = NUM2LONG(time2);
    if (tobj1->tv.tv_sec == i) return INT2FIX(0);
    if (tobj1->tv.tv_sec > i) return INT2FIX(1);
    return INT2FIX(-1);
}

static VALUE
time_eql(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;

    GetTimeval(time1, tobj1);
    if (rb_obj_is_kind_of(time2, rb_cTime)) {
	GetTimeval(time2, tobj2);
	if (tobj1->tv.tv_sec == tobj2->tv.tv_sec) {
	    if (tobj1->tv.tv_usec == tobj2->tv.tv_usec) return Qtrue;
	}
    }
    return Qfalse;
}

static VALUE
time_utc_p(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->gmt) return Qtrue;
    return Qfalse;
}

static VALUE
time_hash(time)
    VALUE time;
{
    struct time_object *tobj;
    long hash;

    GetTimeval(time, tobj);
    hash = tobj->tv.tv_sec ^ tobj->tv.tv_usec;
    return INT2FIX(hash);
}

static VALUE
time_clone(time)
    VALUE time;
{
    VALUE clone;
    struct time_object *tobj, *tclone;

    GetTimeval(time, tobj);
    clone = Data_Make_Struct(0, struct time_object, 0, free, tclone);
    CLONESETUP(clone, time);
    MEMCPY(tclone, tobj, struct time_object, 1);

    return clone;
}

static void
time_modify(time)
    VALUE time;
{
    if (OBJ_FROZEN(time)) rb_error_frozen("Time");
    if (!OBJ_TAINTED(time) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: can't modify Time");
}

static VALUE
time_localtime(time)
    VALUE time;
{
    struct time_object *tobj;
    struct tm *tm_tmp;
    time_t t;

    GetTimeval(time, tobj);
    if (tobj->tm_got && !tobj->gmt) {
	return time;
    }
    time_modify(time);
    t = tobj->tv.tv_sec;
    tm_tmp = localtime(&t);
    tobj->tm = *tm_tmp;
    tobj->tm_got = 1;
    tobj->gmt = 0;
    return time;
}

static VALUE
time_gmtime(time)
    VALUE time;
{
    struct time_object *tobj;
    struct tm *tm_tmp;
    time_t t;

    GetTimeval(time, tobj);
    if (tobj->tm_got && tobj->gmt) {
	return time;
    }
    time_modify(time);
    t = tobj->tv.tv_sec;
    tm_tmp = gmtime(&t);
    tobj->tm = *tm_tmp;
    tobj->tm_got = 1;
    tobj->gmt = 1;
    return time;
}

static VALUE
time_get_tm(time, gmt)
    VALUE time;
    int gmt;
{
    if (gmt) return time_gmtime(time);
    return time_localtime(time);
}

static VALUE
time_asctime(time)
    VALUE time;
{
    struct time_object *tobj;
    char *s;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    s = asctime(&tobj->tm);
    if (s[24] == '\n') s[24] = '\0';

    return rb_str_new2(s);
}

static VALUE
time_to_s(time)
    VALUE time;
{
    struct time_object *tobj;
    char buf[128];
    int len;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    if (tobj->gmt == 1) {
	len = strftime(buf, 128, "%a %b %d %H:%M:%S UTC %Y", &tobj->tm);
    }
    else {
	len = strftime(buf, 128, "%a %b %d %H:%M:%S %Z %Y", &tobj->tm);
    }
    return rb_str_new(buf, len);
}

static VALUE
time_plus(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj;
    time_t sec, usec;
    double f;

    GetTimeval(time1, tobj);

    if (rb_obj_is_kind_of(time2, rb_cTime)) {
	rb_raise(rb_eTypeError, "time + time?");
    }
    f = NUM2DBL(time2);
    sec = (time_t)f;
    usec = tobj->tv.tv_usec + (time_t)((f - (double)sec)*1e6);
    sec = tobj->tv.tv_sec + sec;

    if (usec >= 1000000) {	/* usec overflow */
	sec++;
	usec -= 1000000;
    }
    if (usec < 0) {		/* usec underflow */
	sec--;
	usec += 1000000;
    }
    time2 = rb_time_new(sec, usec);
    if (tobj->gmt) {
	GetTimeval(time2, tobj);
	tobj->gmt = 1;
    }
    return time2;
}

static VALUE
time_minus(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj;
    time_t sec, usec;
    double f;

    GetTimeval(time1, tobj);
    if (rb_obj_is_kind_of(time2, rb_cTime)) {
	struct time_object *tobj2;

	GetTimeval(time2, tobj2);
	f = tobj->tv.tv_sec - tobj2->tv.tv_sec;
	f += (tobj->tv.tv_usec - tobj2->tv.tv_usec)*1e-6;

	return rb_float_new(f);
    }
    else {
	f = NUM2DBL(time2);
	sec = (time_t)f;
	usec = tobj->tv.tv_usec - (time_t)((f - (double)sec)*1e6);
	sec = tobj->tv.tv_sec - sec;
    }

    if (usec >= 1000000) {	/* usec overflow */
	sec++;
	usec -= 1000000;
    }
    if (usec < 0) {		/* usec underflow */
	sec--;
	usec += 1000000;
    }
    time2 = rb_time_new(sec, usec);
    if (tobj->gmt) {
	GetTimeval(time2, tobj);
	tobj->gmt = 1;
    }
    return time2;
}

static VALUE
time_sec(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_sec);
}

static VALUE
time_min(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_min);
}

static VALUE
time_hour(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_hour);
}

static VALUE
time_mday(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_mday);
}

static VALUE
time_mon(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_mon+1);
}

static VALUE
time_year(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_year+1900);
}

static VALUE
time_wday(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_wday);
}

static VALUE
time_yday(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return INT2FIX(tobj->tm.tm_yday+1);
}

static VALUE
time_isdst(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return tobj->tm.tm_isdst?Qtrue:Qfalse;
}

static VALUE
time_zone(time)
    VALUE time;
{
    struct time_object *tobj;
    char buf[64];
    int len;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }

#if defined(HAVE_TM_ZONE)
    return rb_str_new2(tobj->tm.tm_zone);
#elif defined(HAVE_TZNAME) && defined(HAVE_DAYLIGHT)
    return rb_str_new2(tzname[daylight && tobj->tm.tm_isdst]);
#else
    len = strftime(buf, 64, "%Z", &tobj->tm);
    return rb_str_new(buf, len);
#endif
}

static VALUE
time_to_a(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    return rb_ary_new3(10,
		    INT2FIX(tobj->tm.tm_sec),
		    INT2FIX(tobj->tm.tm_min),
		    INT2FIX(tobj->tm.tm_hour),
		    INT2FIX(tobj->tm.tm_mday),
		    INT2FIX(tobj->tm.tm_mon+1),
		    INT2FIX(tobj->tm.tm_year+1900),
		    INT2FIX(tobj->tm.tm_wday),
		    INT2FIX(tobj->tm.tm_yday+1),
		    tobj->tm.tm_isdst?Qtrue:Qfalse,
		    time_zone(time));
}

#define SMALLBUF 100
static int
rb_strftime(buf, format, time)
    char ** volatile buf;
    char * volatile format;
    struct tm * volatile time;
{
    volatile int size;
    int len, flen;

    (*buf)[0] = '\0';
    flen = strlen(format);
    if (flen == 0) {
	return 0;
    }
    len = strftime(*buf, SMALLBUF, format, time);
    if (len != 0 || **buf == '\0') return len;
    for (size=1024; ; size*=2) {
	*buf = xmalloc(size);
	(*buf)[0] = '\0';
	len = strftime(*buf, size, format, time);
	/*
	 * buflen can be zero EITHER because there's not enough
	 * room in the string, or because the control command
	 * goes to the empty string. Make a reasonable guess that
	 * if the buffer is 1024 times bigger than the length of the
	 * format string, it's not failing for lack of room.
	 */
	if (len > 0 || len >= 1024 * flen) return len;
	free(*buf);
    }
    /* not reached */
}

static VALUE
time_strftime(time, format)
    VALUE time, format;
{
    struct time_object *tobj;
    char buffer[SMALLBUF];
    char *fmt;
    char *buf = buffer;
    int len;
    VALUE str;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_get_tm(time, tobj->gmt);
    }
    fmt = rb_str2cstr(format, &len);
    if (len == 0) {
	rb_warning("strftime called with empty format string");
    }
    if (strlen(fmt) < len) {
	/* Ruby string may contain \0's. */
	char *p = fmt, *pe = fmt + len;

	str = rb_str_new(0, 0);
	while (p < pe) {
	    len = rb_strftime(&buf, p, &tobj->tm);
	    rb_str_cat(str, buf, len);
	    p += strlen(p) + 1;
	    if (p <= pe)
		rb_str_cat(str, "\0", 1);
	    if (len > SMALLBUF) free(buf);
	}
	return str;
    }
    len = rb_strftime(&buf, RSTRING(format)->ptr, &tobj->tm);
    str = rb_str_new(buf, len);
    if (buf != buffer) free(buf);
    return str;
}

static VALUE
time_s_times(obj)
    VALUE obj;
{
#if defined(HAVE_TIMES) && !defined(__CHECKER__)
#ifndef HZ
# ifdef CLK_TCK
#   define HZ CLK_TCK
# else
#   define HZ 60
# endif
#endif /* HZ */
    struct tms buf;

    if (times(&buf) == -1) rb_sys_fail(0);
    return rb_struct_new(S_Tms,
			 rb_float_new((double)buf.tms_utime / HZ),
			 rb_float_new((double)buf.tms_stime / HZ),
			 rb_float_new((double)buf.tms_cutime / HZ),
			 rb_float_new((double)buf.tms_cstime / HZ));
#else
    rb_notimplement();
#endif
}

static VALUE
time_dump(argc, argv, time)
    int argc;
    VALUE *argv;
    VALUE time;
{
    VALUE dummy;
    struct time_object *tobj;
    struct tm *tm;
    unsigned long p, s;
    unsigned char buf[8];
    time_t t;
    int i;

    rb_scan_args(argc, argv, "01", &dummy);
    GetTimeval(time, tobj);

    t = tobj->tv.tv_sec;
    tm = gmtime(&t);

    p = 0x1          << 31 | /*  1 */
	tm->tm_year  << 14 | /* 17 */
	tm->tm_mon   << 10 | /*  4 */
	tm->tm_mday  <<  5 | /*  5 */
	tm->tm_hour;         /*  5 */
    s = tm->tm_min   << 26 | /*  6 */
	tm->tm_sec   << 20 | /*  6 */
	tobj->tv.tv_usec;    /* 20 */

    for (i=0; i<4; i++) {
	buf[i] = p & 0xff;
	p = RSHIFT(p, 8);
    }
    for (i=4; i<8; i++) {
	buf[i] = s & 0xff;
	s = RSHIFT(s, 8);
    }

    return rb_str_new(buf, 8);
}

static VALUE
time_load(klass, str)
    VALUE klass, str;
{
    unsigned long p, s;
    time_t sec, usec;
    unsigned char *buf;
    struct tm tm;
    int i;

    buf = rb_str2cstr(str, &i);
    if (i != 8) {
	rb_raise(rb_eTypeError, "marshaled time format differ");
    }

    p = s = 0;
    for (i=0; i<4; i++) {
	p |= buf[i]<<(8*i);
    }
    for (i=4; i<8; i++) {
	s |= buf[i]<<(8*(i-4));
    }

    if ((p & (1<<31)) == 0) {
	return time_new_internal(klass, p, s);
    }
    p &= ~(1<<31);
    tm.tm_year = (p >> 14) & 0x1ffff;
    tm.tm_mon  = (p >> 10) & 0xf;
    tm.tm_mday = (p >>  5) & 0x1f;
    tm.tm_hour =  p        & 0x1f;
    tm.tm_min  = (s >> 26) & 0x3f;
    tm.tm_sec  = (s >> 20) & 0x3f;

    sec = make_time_t(&tm, gmtime);
    usec = (time_t) s & 0xfffff;

    return time_new_internal(klass, sec, usec);
}

void
Init_Time()
{
    rb_cTime = rb_define_class("Time", rb_cObject);
    rb_include_module(rb_cTime, rb_mComparable);

    rb_define_singleton_method(rb_cTime, "now", time_s_now, 0);
    rb_define_singleton_method(rb_cTime, "new", time_s_new, -1);
    rb_define_singleton_method(rb_cTime, "at", time_s_at, -1);
    rb_define_singleton_method(rb_cTime, "utc", time_s_mkutc, -1);
    rb_define_singleton_method(rb_cTime, "gm", time_s_mkutc, -1);
    rb_define_singleton_method(rb_cTime, "local", time_s_mktime, -1);
    rb_define_singleton_method(rb_cTime, "mktime", time_s_mktime, -1);

    rb_define_singleton_method(rb_cTime, "times", time_s_times, 0);

    rb_define_method(rb_cTime, "to_i", time_to_i, 0);
    rb_define_method(rb_cTime, "to_f", time_to_f, 0);
    rb_define_method(rb_cTime, "<=>", time_cmp, 1);
    rb_define_method(rb_cTime, "eql?", time_eql, 1);
    rb_define_method(rb_cTime, "hash", time_hash, 0);
    rb_define_method(rb_cTime, "clone", time_clone, 0);

    rb_define_method(rb_cTime, "localtime", time_localtime, 0);
    rb_define_method(rb_cTime, "gmtime", time_gmtime, 0);
    rb_define_method(rb_cTime, "utc", time_gmtime, 0);
    rb_define_method(rb_cTime, "ctime", time_asctime, 0);
    rb_define_method(rb_cTime, "asctime", time_asctime, 0);
    rb_define_method(rb_cTime, "to_s", time_to_s, 0);
    rb_define_method(rb_cTime, "inspect", time_to_s, 0);
    rb_define_method(rb_cTime, "to_a", time_to_a, 0);

    rb_define_method(rb_cTime, "+", time_plus, 1);
    rb_define_method(rb_cTime, "-", time_minus, 1);

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

    rb_define_method(rb_cTime, "utc?", time_utc_p, 0);
    rb_define_method(rb_cTime, "gmt?", time_utc_p, 0);

    rb_define_method(rb_cTime, "tv_sec", time_to_i, 0);
    rb_define_method(rb_cTime, "tv_usec", time_usec, 0);
    rb_define_method(rb_cTime, "usec", time_usec, 0);

    rb_define_method(rb_cTime, "strftime", time_strftime, 1);

#if defined(HAVE_TIMES) || defined(NT)
    S_Tms = rb_struct_define("Tms", "utime", "stime", "cutime", "cstime", 0);
#endif

    /* methods for marshaling */
    rb_define_method(rb_cTime, "_dump", time_dump, -1);
    rb_define_singleton_method(rb_cTime, "_load", time_load, 1);
}
