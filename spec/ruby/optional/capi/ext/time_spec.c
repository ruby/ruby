#include "ruby.h"
#include "rubyspec.h"

#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

static VALUE time_spec_rb_time_new(VALUE self, VALUE sec, VALUE usec) {
  return rb_time_new(NUM2TIMET(sec), NUM2LONG(usec));
}

static VALUE time_spec_rb_time_nano_new(VALUE self, VALUE sec, VALUE nsec) {
  return rb_time_nano_new(NUM2TIMET(sec), NUM2LONG(nsec));
}

static VALUE time_spec_rb_time_num_new(VALUE self, VALUE ts, VALUE offset) {
  return rb_time_num_new(ts, offset);
}

static VALUE time_spec_rb_time_interval(VALUE self, VALUE ts) {
  struct timeval interval = rb_time_interval(ts);
  VALUE ary = rb_ary_new();
  rb_ary_push(ary, TIMET2NUM(interval.tv_sec));
  rb_ary_push(ary, TIMET2NUM(interval.tv_usec));
  return ary;
}

static VALUE time_spec_rb_time_timeval(VALUE self, VALUE ts) {
  struct timeval tv = rb_time_timeval(ts);
  VALUE ary = rb_ary_new();
  rb_ary_push(ary, TIMET2NUM(tv.tv_sec));
  rb_ary_push(ary, TIMET2NUM(tv.tv_usec));
  return ary;
}

static VALUE time_spec_rb_time_timespec(VALUE self, VALUE time) {
  struct timespec ts = rb_time_timespec(time);
  VALUE ary = rb_ary_new();
  rb_ary_push(ary, TIMET2NUM(ts.tv_sec));
  rb_ary_push(ary, TIMET2NUM(ts.tv_nsec));
  return ary;
}

static VALUE time_spec_rb_time_timespec_new(VALUE self, VALUE sec, VALUE nsec, VALUE offset) {
  struct timespec ts;
  ts.tv_sec = NUM2TIMET(sec);
  ts.tv_nsec = NUM2LONG(nsec);

  return rb_time_timespec_new(&ts, NUM2INT(offset));
}

static VALUE time_spec_rb_time_from_timspec_now(VALUE self, VALUE offset) {
  struct timespec ts;
  rb_timespec_now(&ts);

  return rb_time_timespec_new(&ts, NUM2INT(offset));
}

static VALUE time_spec_TIMET2NUM(VALUE self) {
  time_t t = 10;
  return TIMET2NUM(t);
}

void Init_time_spec(void) {
  VALUE cls = rb_define_class("CApiTimeSpecs", rb_cObject);
  rb_define_method(cls, "rb_time_new", time_spec_rb_time_new, 2);
  rb_define_method(cls, "TIMET2NUM", time_spec_TIMET2NUM, 0);
  rb_define_method(cls, "rb_time_nano_new", time_spec_rb_time_nano_new, 2);
  rb_define_method(cls, "rb_time_num_new", time_spec_rb_time_num_new, 2);
  rb_define_method(cls, "rb_time_interval", time_spec_rb_time_interval, 1);
  rb_define_method(cls, "rb_time_timeval", time_spec_rb_time_timeval, 1);
  rb_define_method(cls, "rb_time_timespec", time_spec_rb_time_timespec, 1);
  rb_define_method(cls, "rb_time_timespec_new", time_spec_rb_time_timespec_new, 3);
  rb_define_method(cls, "rb_time_from_timespec", time_spec_rb_time_from_timspec_now, 1);
}

#ifdef __cplusplus
}
#endif
