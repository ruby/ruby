/************************************************

  time.c -

  $Author: matz $
  $Date: 1994/12/06 09:30:28 $
  created at: Tue Dec 28 14:31:59 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <sys/types.h>

#include <time.h>
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif

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

static ID id_tv;

#define GetTimeval(obj, tobj) {\
    if (!id_tv) id_tv = rb_intern("tv");\
    Get_Data_Struct(obj, id_tv, struct time_object, tobj);\
}

#define MakeTimeval(obj,tobj) {\
    if (!id_tv) id_tv = rb_intern("tv");\
    Make_Data_Struct(obj, id_tv, struct time_object, 0, 0, tobj);\
    tobj->tm_got=0;\
}

static VALUE
time_s_now(class)
    VALUE class;
{
    VALUE obj = obj_alloc(class);
    struct time_object *tobj;

    MakeTimeval(obj, tobj);

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
    VALUE obj = obj_alloc(class);
    struct time_object *tobj;

    MakeTimeval(obj, tobj);
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

struct timeval*
time_timeval(time)
    VALUE time;
{
    struct time_object *tobj;
    static struct timeval t;

    switch (TYPE(time)) {
      case T_FIXNUM:
	t.tv_sec = FIX2UINT(time);
	if (t.tv_sec < 0)
	    Fail("time must be positive");
	t.tv_usec = 0;
	break;

      case T_FLOAT:
	{
	    double seconds, microseconds;

	    if (RFLOAT(time)->value < 0.0)
		Fail("time must be positive");
	    seconds = floor(RFLOAT(time)->value);
	    microseconds = (RFLOAT(time)->value - seconds) * 1000000.0;
	    t.tv_sec = seconds;
	    t.tv_usec = microseconds;
	}
	break;

      default:
	if (!obj_is_kind_of(time, cTime)) {
	    Fail("Can't convert %s into Time", rb_class2name(CLASS_OF(time)));
	}
	GetTimeval(time, tobj);
	t = tobj->tv;
	break;
    }
    return &t;
}

static VALUE
time_s_at(class, time)
    VALUE class, time;
{
    struct timeval *tp;

    tp = time_timeval(time);
    return time_new_internal(class, tp->tv_sec, tp->tv_usec);

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
    tm_tmp = localtime(&tobj->tv.tv_sec);
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
    tm_tmp = gmtime(&tobj->tv.tv_sec);
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
    char buf[32];
    int len;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	time_localtime(time);
    }
#ifndef HAVE_TM_ZONE
    if (tobj->gmt == 1)
	len = strftime(buf, 32, "%a %b %d %H:%M:%S GMT %Y", &(tobj->tm));
    else
#endif
    {
	len = strftime(buf, 32, "%a %b %d %H:%M:%S %Z %Y", &(tobj->tm));
    }
    return str_new(buf, len);
}

static VALUE
time_coerce(time1, time2)
    VALUE time1, time2;
{
    return time_new(CLASS_OF(time1), NUM2INT(time2), 0);
}

static VALUE
time_plus(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    int sec, usec;

    GetTimeval(time1, tobj1);
    if (obj_is_instance_of(time2, cTime)) {
	GetTimeval(time2, tobj2);
	sec = tobj1->tv.tv_sec + tobj2->tv.tv_sec;
	usec = tobj1->tv.tv_usec + tobj2->tv.tv_usec;
    }
    else {
	sec = tobj1->tv.tv_sec + NUM2INT(time2);
	usec = tobj1->tv.tv_usec;
	if (usec >= 1000000) {
	    sec++;
	    usec -= 1000000;
	}
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
	GetTimeval(time2, tobj2);
	sec = tobj1->tv.tv_sec - tobj2->tv.tv_sec;
	usec = tobj1->tv.tv_usec - tobj2->tv.tv_usec;
	if (usec < 0) {
	    sec--;
	    usec += 1000000;
	}
    }
    else {
	sec = tobj1->tv.tv_sec - NUM2INT(time2);
	usec = tobj1->tv.tv_usec;
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

    if (times(&buf) == -1) rb_sys_fail(Qnil);
    return struct_new(S_Tms,
		      float_new((double)buf.tms_utime / HZ),
		      float_new((double)buf.tms_stime / HZ),
		      float_new((double)buf.tms_cutime / HZ),
		      float_new((double)buf.tms_cstime / HZ),
		      Qnil);
#else
#ifdef NT
    FILETIME create, exit, kernel, user;
    HANDLE hProc;

    hProc = GetCurrentProcess();
    GetProcessTimes(hProc,&create, &exit, &kernel, &user);
    return struct_new(S_Tms,
      float_new((double)(kernel.dwHighDateTime*2E32+kernel.dwLowDateTime)/2E6),
      float_new((double)(user.dwHighDateTime*2E32+user.dwLowDateTime)/2E6),
      float_new((double)0),
      float_new((double)0),
      Qnil);
#else
    Fail("can't call times");
    return Qnil;
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

    rb_define_singleton_method(cTime, "times", time_s_times, 0);

    rb_define_method(cTime, "to_i", time_to_i, 0);
    rb_define_method(cTime, "to_f", time_to_f, 0);
    rb_define_method(cTime, "<=>", time_cmp, 1);
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
    S_Tms = struct_define("Tms", "utime", "stime", "cutime", "cstime", Qnil);
#endif
}
