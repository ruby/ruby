#include "ruby.h"

static VALUE
bug_time_s_nano_new(VALUE klass, VALUE sec, VALUE nsec)
{
    return rb_time_nano_new(NUM2TIMET(sec), NUM2LONG(nsec));
}

static VALUE
bug_time_s_timespec_new(VALUE klass, VALUE sec, VALUE nsec, VALUE gmtoff)
{
    struct timespec ts;
    ts.tv_sec = NUM2TIMET(sec);
    ts.tv_nsec = NUM2LONG(nsec);
    return rb_time_timespec_new(&ts, NUM2INT(gmtoff));
}

static VALUE
bug_time_s_timespec_now(VALUE klass)
{
    struct timespec ts;
    VALUE v;
    rb_timespec_now(&ts);
    v = rb_Rational(LONG2NUM(ts.tv_nsec), LONG2NUM(1000000000L));
    return rb_num_coerce_bin(TIMET2NUM(ts.tv_sec), v, '+');
}

void
Init_time_new(VALUE klass)
{
    rb_define_singleton_method(klass, "nano_new", bug_time_s_nano_new, 2);
    rb_define_singleton_method(klass, "timespec_new", bug_time_s_timespec_new, 3);
    rb_define_singleton_method(klass, "timespec_now", bug_time_s_timespec_now, 0);
}
