#include <ruby.h>
#include <yarvcore.h>

static void
hash_inc(VALUE data, VALUE key)
{
    VALUE num = INT2FIX(0);

    if (num = rb_hash_aref(data, key)) {
	num = INT2FIX(FIX2INT(num) + 1);
    }

    rb_hash_aset(data, key, num);
}

static void
pprof_hook(rb_event_flag_t flag, VALUE data,
	   VALUE dmyid, VALUE dmyklass)
{
    rb_thread_t *th = GET_THREAD();
    VALUE sig = rb_thread_current_sig(th);
    hash_inc(data, sig);
}

static VALUE
pprof_data(VALUE mod)
{
    rb_const_get_at(mod, rb_intern("#pprof_data"));
}

static VALUE
pprof_start(VALUE self)
{
    VALUE data = pprof_data(self);
    rb_add_event_hook(pprof_hook, RUBY_EVENT_SWITCH, data);
    return Qnil;
}

static VALUE
pprof_stop(VALUE self)
{
    rb_remove_event_hook(pprof_hook);
    return Qnil;
}

static int
hash_to_ary_i(VALUE key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, rb_ary_new3(2, value, key));
    return ST_CONTINUE;
}

Init_probeprofiler(void)
{
    VALUE mPProf;

    mPProf = rb_define_module("ProbeProfiler");
    rb_const_set(mPProf, rb_intern("#pprof_data"), rb_hash_new());
    rb_define_module_function(mPProf, "start_profile", pprof_start, 0);
    rb_define_module_function(mPProf, "stop_profile", pprof_stop, 0);
    rb_define_module_function(mPProf, "profile_data", pprof_data, 0);
}

