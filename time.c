/************************************************

  time.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:51 $
  created at: Tue Dec 28 14:31:59 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <sys/types.h>
#include <sys/time.h>
#include <sys/times.h>

static VALUE C_Time;
extern VALUE M_Comparable;

struct time_object {
    struct timeval tv;
    struct tm tm;
#ifndef HAVE_TM_ZONE
    int gmt;
#endif
    int tm_got;
};

#define GetTimeval(obj, tobj) \
    Get_Data_Struct(obj, "tv", struct time_object, tobj)
#define MakeTimeval(obj,tobj) {\
    Make_Data_Struct(obj, "tv", struct time_object, Qnil, Qnil, tobj);\
    tobj->tm_got=0;\
}

static VALUE
Ftime_now(class)
    VALUE class;
{
    VALUE obj = obj_alloc(class);
    struct time_object *tobj;

    GC_LINK;
    GC_PRO(obj);
    MakeTimeval(obj, tobj);

    if (gettimeofday(&(tobj->tv), 0) == -1) {
	rb_sys_fail("gettimeofday");
    }
    GC_UNLINK;

    return obj;
}

static VALUE
time_new_internal(class, sec, usec)
    int sec, usec;
{
    VALUE obj = obj_alloc(class);
    struct time_object *tobj;

    GC_LINK;
    GC_PRO(obj);
    MakeTimeval(obj, tobj);
    tobj->tv.tv_sec = sec;
    tobj->tv.tv_usec =usec;
    GC_UNLINK;

    return obj;
}

VALUE
time_new(sec, usec)
    int sec, usec;
{
    return time_new_internal(C_Time, sec, usec);
}

struct timeval*
time_timeval(time)
    VALUE time;
{
    struct time_object *tobj;
    static struct timeval t, *tp;

    switch (TYPE(time)) {
      case T_FIXNUM:
	t.tv_sec = FIX2UINT(time);
	if (t.tv_sec < 0)
	    Fail("time must be positive");
	t.tv_usec = 0;
	tp = &t;
	break;

      case T_FLOAT:
	{
	    double floor();
	    double seconds, microseconds;

	    if (RFLOAT(time)->value < 0.0)
		Fail("time must be positive");
	    seconds = floor(RFLOAT(time)->value);
	    microseconds = (RFLOAT(time)->value - seconds) * 1000000.0;
	    t.tv_sec = seconds;
	    t.tv_usec = microseconds;
	    tp = &t;
	}
	break;

      default:
	if (!obj_is_kind_of(time, C_Time)) {
	    Fail("Can't convert %s into Time", rb_class2name(CLASS_OF(time)));
	}
	GetTimeval(time, tobj);
	tp = &(tobj->tv);
	break;
    }
    return tp;
}

static VALUE
Ftime_at(class, time)
    VALUE class, time;
{ 
   VALUE obj;
    int sec, usec;
    struct time_object *tobj;
    struct timeval *tp;

    tp = time_timeval(time);
    return time_new_internal(class, tp->tv_sec, tp->tv_usec);

}
static VALUE
Ftime_to_i(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return int2inum(tobj->tv.tv_sec);
}

static VALUE
Ftime_usec(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    return INT2FIX(tobj->tv.tv_usec);
}

static VALUE
Ftime_cmp(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    int i;

    GetTimeval(time1, tobj1);
    if (obj_is_member_of(time2, C_Time)) {
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
Ftime_hash(time)
    VALUE time;
{
    struct time_object *tobj;
    int hash;

    GetTimeval(time, tobj);
    hash = tobj->tv.tv_sec ^ tobj->tv.tv_usec;
    return INT2FIX(hash);
}

static VALUE
Ftime_localtime(time)
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
Ftime_gmtime(time)
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
Ftime_asctime(time)
    VALUE time;
{
    struct time_object *tobj;
    char *ct;
    char buf[32];
    int len;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
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
Ftime_coerce(time1, time2)
    VALUE time1, time2;
{
    return time_new(CLASS_OF(time1), NUM2INT(time2), 0);
}

static VALUE
Ftime_plus(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    int sec, usec;

    GetTimeval(time1, tobj1);
    if (obj_is_member_of(time2, C_Time)) {
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
Ftime_minus(time1, time2)
    VALUE time1, time2;
{
    struct time_object *tobj1, *tobj2;
    int sec, usec;

    GetTimeval(time1, tobj1);
    if (obj_is_member_of(time2, C_Time)) {
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
Ftime_sec(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_sec);
}

static VALUE
Ftime_min(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_min);
}

static VALUE
Ftime_hour(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_hour);
}

static VALUE
Ftime_mday(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_mday);
}

static VALUE
Ftime_mon(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_mon);
}

static VALUE
Ftime_year(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_year);
}

static VALUE
Ftime_wday(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_wday);
}

static VALUE
Ftime_yday(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_yday);
}

static VALUE
Ftime_isdst(time)
    VALUE time;
{
    struct time_object *tobj;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    return INT2FIX(tobj->tm.tm_isdst);
}

static VALUE
Ftime_zone(time)
    VALUE time;
{
    struct time_object *tobj;
    char buf[10];
    int len;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }

    len = strftime(buf, 10, "%Z", &(tobj->tm));
    return str_new(buf, len);
}

static VALUE
Ftime_to_a(time)
    VALUE time;
{
    struct time_object *tobj;
    struct tm *tm;
    char buf[10];
    VALUE ary;

    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
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
Ftime_strftime(time, format)
    VALUE time, format;
{
    struct time_object *tobj;
    char buf[100];
    int len;

    Check_Type(format, T_STRING);
    GetTimeval(time, tobj);
    if (tobj->tm_got == 0) {
	Ftime_localtime(time);
    }
    if (strlen(RSTRING(format)->ptr) < RSTRING(format)->len) {
	/* Ruby string contains \0. */
	VALUE str;
	int l, total = 0;
	char *p = RSTRING(format)->ptr, *pe = p + RSTRING(format)->len;

	GC_LINK;
	GC_PRO3(str, str_new(0, 0));
	while (p < pe) {
	    len = strftime(buf, 100, p, &(tobj->tm));
	    str_cat(str, buf, len);
	    l = strlen(p);
	    p += l + 1;
	}
	GC_UNLINK;
	return str;
    }
    len = strftime(buf, 100, RSTRING(format)->ptr, &(tobj->tm));
    return str_new(buf, len);
}

static VALUE
Ftime_times(obj)
    VALUE obj;
{
    struct tms buf;
    VALUE t1, t2, t3, t4, tm;

    if (times(&buf) == -1) rb_sys_fail(Qnil);
    GC_LINK;
    GC_PRO3(t1, float_new((double)buf.tms_utime / 60.0));
    GC_PRO3(t2, float_new((double)buf.tms_stime / 60.0));
    GC_PRO3(t3, float_new((double)buf.tms_cutime / 60.0));
    GC_PRO3(t4, float_new((double)buf.tms_cstime / 60.0));

    tm = struct_new("tms",
		    "utime", t1, "stime", t2,
		    "cutime", t3, "cstime", t4,
		    Qnil);
    GC_UNLINK;

    return tm;
}

Init_Time()
{
    C_Time = rb_define_class("Time", C_Object);
    rb_include_module(C_Time, M_Comparable);

    rb_define_single_method(C_Time, "now", Ftime_now, 0);
    rb_define_single_method(C_Time, "new", Ftime_now, 0);
    rb_define_single_method(C_Time, "at", Ftime_at, 1);

    rb_define_single_method(C_Time, "times", Ftime_times, 0);

    rb_define_method(C_Time, "to_i", Ftime_to_i, 0);
    rb_define_method(C_Time, "<=>", Ftime_cmp, 1);
    rb_define_method(C_Time, "hash", Ftime_hash, 0);

    rb_define_method(C_Time, "localtime", Ftime_localtime, 0);
    rb_define_method(C_Time, "gmtime", Ftime_gmtime, 0);
    rb_define_method(C_Time, "ctime", Ftime_asctime, 0);
    rb_define_method(C_Time, "asctime", Ftime_asctime, 0);
    rb_define_method(C_Time, "to_s", Ftime_asctime, 0);
    rb_define_method(C_Time, "_inspect", Ftime_asctime, 0);
    rb_define_method(C_Time, "to_a", Ftime_to_a, 0);
    rb_define_method(C_Time, "coerce", Ftime_coerce, 1);

    rb_define_method(C_Time, "+", Ftime_plus, 1);
    rb_define_method(C_Time, "-", Ftime_minus, 1);

    rb_define_method(C_Time, "sec", Ftime_sec, 0);
    rb_define_method(C_Time, "min", Ftime_min, 0);
    rb_define_method(C_Time, "hour", Ftime_hour, 0);
    rb_define_method(C_Time, "mday", Ftime_mday, 0);
    rb_define_method(C_Time, "year", Ftime_year, 0);
    rb_define_method(C_Time, "wday", Ftime_wday, 0);
    rb_define_method(C_Time, "yday", Ftime_yday, 0);
    rb_define_method(C_Time, "isdst", Ftime_isdst, 0);

    rb_define_method(C_Time, "tv_sec", Ftime_to_i, 0);
    rb_define_method(C_Time, "tv_usec", Ftime_usec, 0);
    rb_define_method(C_Time, "usec", Ftime_usec, 0);

    rb_define_method(C_Time, "strftime", Ftime_strftime, 1);
}
