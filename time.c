/************************************************

  time.c -

  $Author$
  $Date$
  created at: Tue Dec 28 14:31:59 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <sys/types.h>

#ifdef HAVE_STRING_H
# include <string.h>
#endif

#include <time.h>
#ifndef NT
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif
#endif /* NT */

#ifdef HAVE_SYS_TIMES_H
#include <sys/times.h>
#endif
#include <math.h>

static VALUE cTime;
#if defined(HAVE_TIMES) || defined(NT)
static VALUE S_Tms;
#endif
extern VALUE mComparable;

struct time_object {
    struct timeval tv;
    struct tm tm;
#ifndef HAVE_TM_ZONE
    int gmt;
#endif
    int tm_got;
};

#define GetTimeval(obj, tobj) {\
    Data_Get_Struct(obj, struct time_object, tobj);\
}

static VALUE
time_s_now(class)
    VALUE class;
{
    VALUE obj;
    struct time_object *tobj;

    obj = Data_Make_Struct(class, struct time_object, 0, 0, tobj);
    tobj->tm_got=0;

    if (gettimeofday(&(tobj->tv), 0) == -1) {
	rb_sys_fail("gettimeofday");
    }

    return obj;
}

static VALUE
time_new_internal(class, sec, usec)
    VALUE class;
    int sec, usec;
{
    VALUE obj;
    struct time_object *tobj;

    obj = Data_Make_Struct(class, struct time_object, 0, 0, tobj);
    tobj->tm_got = 0;
    tobj->tv.tv_sec = sec;
    tobj->tv.tv_usec = usec;

    return obj;
}

VALUE
time_new(sec, usec)
    int sec, usec;
{
    return time_new_internal(cTime, sec, usec);
}

struct timeval
time_timeval(time)
    VALUE time;
{
    struct time_object *tobj;
    struct timeval t;

    switch (TYPE(time)) {
      case T_FIXNUM:
	t.tv_sec = FIX2UINT(time);
	if (t.tv_sec < 0)
	    ArgError("time must be positive");
	t.tv_usec = 0;
	break;

      case T_FLOAT:
	{
	    double seconds, microseconds;

	    if (RFLOAT(time)->value < 0.0)
		ArgError("time must be positive");
	    seconds = floor(RFLOAT(time)->value);
	    microseconds = (RFLOAT(time)->value - seconds) * 1000000.0;
	    t.tv_sec = seconds;
	    t.tv_usec = microseconds;
	}
	break;

      case T_BIGNUM:
	t.tv_sec = NUM2INT(time);
	t.tv_usec = 0;
	break;

      default:
	if (!obj_is_kind_of(time, cTime)) {
	    TypeError("Can't convert %s into Time",
		      rb_class2name(CLASS_OF(time)));
	}
	GetTimeval(time, tobj);
	t = tobj->tv;
	break;
    }
    return t;
}

static VALUE
time_s_at(class, time)
    VALUE class, time;
{
    struct timeval tv;

    tv = time_timeval(time);
    return time_new_internal(class, tv.tv_sec, tv.tv_usec);
}

static char *months [12] = {
    "jan", "feb", "mar", "apr", "may", "jun",
    "jul", "aug", "sep", "oct", "nov", "dec",
};

static void
time_arg(argc, argv, args)
    int argc;
    VALUE *argv;
    int *args;
{
    VALUE v[6];
    int i;

    rb_scan_args(argc, argv, "15", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]);

    args[0] = NUM2INT(v[0]);
    if (args[0] < 70) args[0] += 100;
    if (args[0] > 1900) args[0] -= 1900;
    if (v[1] == Qnil) {
	args[1] = 0;
    }
    else if (TYPE(v[1]) == T_STRING) {
	args[1] = -1;
	for (i=0; i<12; i++) {
	    if (strcasecmp(months[i], RSTRING(v[1])->ptr) == 0) {
		args[1] = i;
		break;
	    }
	}
	if (args[1] == -1) {
	    char c = RSTRING(v[1])->ptr[0];

	    if ('0' <= c && c <= '9') {
		args[1] = NUM2INT(v[1])-1;
	    }
	}
    }
    else {
	args[1] = NUM2INT(v[1]);
    }
    if (v[2] == Qnil) {
	args[2] = 1;
    }
    else {
	args[2] = NUM2INT(v[2]);
    }
    for (i=3;i<6;i++) {
	if (v[i] == Qnil) {
	    args[i] = 0;
	}
	else {
	    args[i] = NUM2INT(v[i]);
	}
    }

    /* value validation */
    if (   args[0] < 70|| args[1] > 137
	|| args[1] < 0 || args[1] > 11
	|| args[2] < 1 || args[2] > 31
	|| args[3] < 0 || args[3] > 23
	|| args[4] < 0 || args[4] > 60
	|| args[5] < 0 || args[5] > 61)
	ArgError("argument out of range");
}

static VALUE
time_gm_or_local(argc, argv, gm_or_local, class)
    int argc;
    VALUE *argv;
    int gm_or_local;
    VALUE class;
{
    int args[6];
    struct timeval tv;
    struct tm *tm;
    time_t guess, t;
    int diff;
    struct tm *(*fn)();

    fn = (gm_or_local) ? gmtime : localtime;
    time_arg(argc, argv, args);

    gettimeofday(&tv, 0);
    guess = tv.tv_sec;

    tm = (*fn)(&guess);
    if (!tm) goto error;
    t = args[0];
    while (diff = t - tm->tm_year) {
	guess += diff * 364 * 24 * 3600;
	if (guess < 0) ArgError("too far future");
	tm = (*fn)(&guess);
	if (!tm) goto error;
    }
    t = args[1];
    while (diff = t - tm->tm_mon) {
	guess += diff * 27 * 24 * 3600;
	tm = (*fn)(&guess);
	if (!tm) goto error;
    }
    guess += (args[2] - tm->tm_mday) * 3600 * 24;
    guess += (args[3] - tm->tm_hour) * 3600;
    guess += (args[4] - tm->tm_min) * 60;
    guess += args[5] - tm->tm_sec;

    return time_new_internal(class, guess, 0);

  error:
    ArgError("gmtime error");
}

static VALUE
time_s_timegm(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    return time_gm_or_local(argc, argv, 1, class);
}

static VALUE
time_s_timelocal(argc, argv, class)
    int argc;
    VALUE *argv;
    VALUE class;
{
    return time_gm_or_local(argc, argv, 0, class);
}

static VALUE
time_to_i(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return int2inum(tobj->tv.tv_sec);
}

static VALUE
time_to_f(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return float_new((double)tobj->tv.tv_sec+(double)tobj->tv.tv_usec/1000000);
}

static VALUE
time_usec(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return INT2FIX(tobj->tv.tv_usec);
}

static VALUE
time_cmp(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    int i;

    GetTimeval(time1, tobj1);
    switch (TYPE(time2)) {
      case T_FIXNUM:
	i = FIX2INT(time2);
	if (tobj1->tv.tv_sec == i) return INT2FIX(0);
	if (tobj1->tv.tv_sec > i) return INT2FIX(1);
	return FIX2INT(-1);
	
      case T_FLOAT:
	{
	    double t;

	    if (tobj1->tv.tv_sec == (int)RFLOAT(time2)->value) return INT2FIX(0);
	    t = (double)tobj1->tv.tv_sec + (double)tobj1->tv.tv_usec*1e-6;
	    if (tobj1->tv.tv_sec == RFLOAT(time2)->value) return INT2FIX(0);
	    if (tobj1->tv.tv_sec > RFLOAT(time2)->value) return INT2FIX(1);
	    return FIX2INT(-1);
	}
    }

    if (obj_is_instance_of(time2, cTime)) {
	GetTimeval(time2, tobj2);
	if (tobj1->tv.tv_sec == tobj2->tv.tv_sec) {
	    if (tobj1->tv.tv_usec == tobj2->tv.tv_usec) return INT2FIX(0);
	    if (tobj1->tv.tv_usec > tobj2->tv.tv_usec) return INT2FIX(1);
	    return FIX2INT(-1);
	}
	if (tobj1->tv.tv_sec > tobj2->tv.tv_sec) return INT2FIX(1);
	return FIX2INT(-1);
    }
    i = NUM2INT(time2);
    if (tobj1->tv.tv_sec == i) return INT2FIX(0);
    if (tobj1->tv.tv_sec > i) return INT2FIX(1);
    return FIX2INT(-1);
}

static VALUE
time_eql(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;

    GetTimeval(time1, tobj1);
    if (obj_is_instance_of(time2, cTime)) {
	GetTimeval(time2, tobj2);
	if (tobj1->tv.tv_sec == tobj2->tv.tv_sec) {
	    if (tobj1->tv.tv_usec == tobj2->tv.tv_usec) return TRUE;
	}
    }
    return FALSE;
}

static VALUE
time_hash(time)
    VALUE time;
{
    struct time_object *tobj;
    int hash;

    GetTimeval(time, tobj);
    hash = tobj->tv.tv_sec ^ tobj->tv.tv_usec;
    return INT2FIX(hash);
}

static VALUE
time_localtime(time)
    VALUE time;
{
    struct time_object *tobj;
    struct tm *tm_tmp;

    GetTimeval(time, tobj);
    tm_tmp = localtime((const time_t*)&tobj->tv.tv_sec);
    tobj->tm = *tm_tmp;
    tobj->tm_got = 1;
#ifndef HAVE_TM_ZONE
    tobj->gmt = 0;
#endif
    return time;
}

static VALUE
time_gmtime(time)
    VALUE time;
{
    struct time_object *tobj;
    struct tm *tm_tmp;

    GetTimeval(time, tobj);
    tm_tmp = gmtime((const time_t*)&tobj->tv.tv_sec);
    tobj->tm = *tm_tmp;
    tobj->tm_got = 1;
#ifndef HAVE_TM_ZONE
    tobj->gmt = 1;
#endif
    return time;
}

static VALUE
time_asctime(time)
    VALUE time;
{
    struct time_object *tobj;
    char buf[64];
    int len;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
    }
#ifndef HAVE_TM_ZONE
    if (tobj->gmt == 1) {
	len = strftime(buf, 64, "%a %b %d %H:%M:%S GMT %Y", &(tobj->tm));
    }
    else
#endif
    {
	len = strftime(buf, 64, "%a %b %d %H:%M:%S %Z %Y", &(tobj->tm));
    }
    return str_new(buf, len);
}

static VALUE
time_coerce(time1, time2)
    VALUE time1, time2;
{
    if (TYPE(time2) == T_FLOAT) {
	double d = RFLOAT(time2)->value;
	unsigned int i = (unsigned int) d;

	return assoc_new(time_new(i, (int)((d - (double)i)*1e6)),time1);
    }

    return assoc_new(time_new(NUM2INT(time2), 0), time1);
}

static VALUE
time_plus(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    int sec, usec;

    GetTimeval(time1, tobj1);
    if (TYPE(time2) == T_FLOAT) {
	unsigned int nsec = (unsigned int)RFLOAT(time2)->value;
	sec = tobj1->tv.tv_sec + nsec;
	usec = tobj1->tv.tv_usec + (RFLOAT(time2)->value - (double)nsec)*1e6;
    }
    else if (obj_is_instance_of(time2, cTime)) {
	GetTimeval(time2, tobj2);
	sec = tobj1->tv.tv_sec + tobj2->tv.tv_sec;
	usec = tobj1->tv.tv_usec + tobj2->tv.tv_usec;
    }
    else {
	sec = tobj1->tv.tv_sec + NUM2INT(time2);
	usec = tobj1->tv.tv_usec;
    }

    if (usec >= 1000000) {	/* usec overflow */
	sec++;
	usec -= 1000000;
    }
    return time_new(sec, usec);
}

static VALUE
time_minus(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    int sec, usec;

    GetTimeval(time1, tobj1);
    if (obj_is_instance_of(time2, cTime)) {
	double f;

	GetTimeval(time2, tobj2);
	f = tobj1->tv.tv_sec - tobj2->tv.tv_sec;

	f += (tobj1->tv.tv_usec - tobj2->tv.tv_usec)*1e-6;

	return float_new(f);
    }
    else if (TYPE(time2) == T_FLOAT) {
	sec = tobj1->tv.tv_sec - (int)RFLOAT(time2)->value;
	usec = tobj1->tv.tv_usec - (RFLOAT(time2)->value - (double)sec)*1e6;
    }
    else {
	sec = tobj1->tv.tv_sec - NUM2INT(time2);
	usec = tobj1->tv.tv_usec;
    }

    if (usec < 0) {		/* usec underflow */
	sec--;
	usec += 1000000;
    }
    return time_new(sec, usec);
}

static VALUE
time_sec(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
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
	time_localtime(time);
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
	time_localtime(time);
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
	time_localtime(time);
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
	time_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_mon);
}

static VALUE
time_year(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_year);
}

static VALUE
time_wday(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
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
	time_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_yday);
}

static VALUE
time_isdst(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_isdst);
}

static VALUE
time_zone(time)
    VALUE time;
{
    struct time_object *tobj;
    char buf[10];
    int len;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
    }

    len = strftime(buf, 10, "%Z", &(tobj->tm));
    return str_new(buf, len);
}

static VALUE
time_to_a(time)
    VALUE time;
{
    struct time_object *tobj;
    VALUE ary;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
    }
    ary = ary_new3(9,
		   INT2FIX(tobj->tm.tm_sec),
		   INT2FIX(tobj->tm.tm_min),
		   INT2FIX(tobj->tm.tm_hour),
		   INT2FIX(tobj->tm.tm_mday),
		   INT2FIX(tobj->tm.tm_mon),
		   INT2FIX(tobj->tm.tm_year),
		   INT2FIX(tobj->tm.tm_wday),
		   INT2FIX(tobj->tm.tm_yday),
		   INT2FIX(tobj->tm.tm_isdst));
    return ary;
}

static VALUE
time_strftime(time, format)
    VALUE time, format;
{
    struct time_object *tobj;
    char buf[100];
    int len;

    Check_Type(format, T_STRING);
    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
    }
    if (strlen(RSTRING(format)->ptr) < RSTRING(format)->len) {
	/* Ruby string contains \0. */
	VALUE str;
	int l;
	char *p = RSTRING(format)->ptr, *pe = p + RSTRING(format)->len;

	str = str_new(0, 0);
	while (p < pe) {
	    len = strftime(buf, 100, p, &(tobj->tm));
	    str_cat(str, buf, len);
	    l = strlen(p);
	    p += l + 1;
	}
	return str;
    }
    len = strftime(buf, 100, RSTRING(format)->ptr, &(tobj->tm));
    return str_new(buf, len);
}

static VALUE
time_s_times(obj)
    VALUE obj;
{
#ifdef HAVE_TIMES
#ifndef HZ
#define HZ 60 /* Universal constant :-) */
#endif /* HZ */
    struct tms buf;

    if (times(&buf) == -1) rb_sys_fail(0);
    return struct_new(S_Tms,
		      float_new((double)buf.tms_utime / HZ),
		      float_new((double)buf.tms_stime / HZ),
		      float_new((double)buf.tms_cutime / HZ),
		      float_new((double)buf.tms_cstime / HZ));
#else
#ifdef NT
    FILETIME create, exit, kernel, user;
    HANDLE hProc;

    hProc = GetCurrentProcess();
    GetProcessTimes(hProc,&create, &exit, &kernel, &user);
    return struct_new(S_Tms,
      float_new((double)(kernel.dwHighDateTime*2e32+kernel.dwLowDateTime)/2e6),
      float_new((double)(user.dwHighDateTime*2e32+user.dwLowDateTime)/2e6),
      float_new((double)0),
      float_new((double)0));
#else
    rb_notimplement();
#endif
#endif
}

void
Init_Time()
{
    cTime = rb_define_class("Time", cObject);
    rb_include_module(cTime, mComparable);

    rb_define_singleton_method(cTime, "now", time_s_now, 0);
    rb_define_singleton_method(cTime, "new", time_s_now, 0);
    rb_define_singleton_method(cTime, "at", time_s_at, 1);
    rb_define_singleton_method(cTime, "gm", time_s_timegm, -1);
    rb_define_singleton_method(cTime, "local", time_s_timelocal, -1);
    rb_define_singleton_method(cTime, "mktime", time_s_timelocal, -1);

    rb_define_singleton_method(cTime, "times", time_s_times, 0);

    rb_define_method(cTime, "to_i", time_to_i, 0);
    rb_define_method(cTime, "to_f", time_to_f, 0);
    rb_define_method(cTime, "<=>", time_cmp, 1);
    rb_define_method(cTime, "eql?", time_eql, 0);
    rb_define_method(cTime, "hash", time_hash, 0);

    rb_define_method(cTime, "localtime", time_localtime, 0);
    rb_define_method(cTime, "gmtime", time_gmtime, 0);
    rb_define_method(cTime, "ctime", time_asctime, 0);
    rb_define_method(cTime, "asctime", time_asctime, 0);
    rb_define_method(cTime, "to_s", time_asctime, 0);
    rb_define_method(cTime, "inspect", time_asctime, 0);
    rb_define_method(cTime, "to_a", time_to_a, 0);
    rb_define_method(cTime, "coerce", time_coerce, 1);

    rb_define_method(cTime, "+", time_plus, 1);
    rb_define_method(cTime, "-", time_minus, 1);

    rb_define_method(cTime, "sec", time_sec, 0);
    rb_define_method(cTime, "min", time_min, 0);
    rb_define_method(cTime, "hour", time_hour, 0);
    rb_define_method(cTime, "mday", time_mday, 0);
    rb_define_method(cTime, "mon", time_mon, 0);
    rb_define_method(cTime, "year", time_year, 0);
    rb_define_method(cTime, "wday", time_wday, 0);
    rb_define_method(cTime, "yday", time_yday, 0);
    rb_define_method(cTime, "isdst", time_isdst, 0);
    rb_define_method(cTime, "zone", time_zone, 0);

    rb_define_method(cTime, "tv_sec", time_to_i, 0);
    rb_define_method(cTime, "tv_usec", time_usec, 0);
    rb_define_method(cTime, "usec", time_usec, 0);

    rb_define_method(cTime, "strftime", time_strftime, 1);

#if defined(HAVE_TIMES) || defined(NT)
    S_Tms = struct_define("Tms", "utime", "stime", "cutime", "cstime", 0);
#endif
}
