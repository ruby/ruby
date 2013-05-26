#include "ruby.h"
#include "ruby/debug.h"

static void
pjob_callback(void *data)
{
    VALUE ary = (VALUE)data;
    Check_Type(ary, T_ARRAY);

    rb_ary_replace(ary, rb_funcall(Qnil, rb_intern("caller"), 0));
}

static VALUE
pjob_register(VALUE self, VALUE obj)
{
    rb_postponed_job_register(0, pjob_callback, (void *)obj);
}

static VALUE
pjob_call_direct(VALUE self, VALUE obj)
{
    pjob_callback((void *)obj);
}

void
Init_task(VALUE self)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "postponed_job_register", pjob_register, 1);
    rb_define_module_function(mBug, "postponed_job_call_direct", pjob_call_direct, 1);
}

