/**
 * probe.c - 
 *
 * $Author$
 *
 * Based on the patch for Ruby 1.8.6 by Joyent Inc.
 *
 * Copyright 2007 Joyent Inc.
 * Copyright 2009 Yuki Sonoda (Yugui).
 */
#include "ruby/ruby.h"

#define FIRE_WITH_SUFFIXED_MSG(probe_name, probe_data, suffix) \
    if (TRACE_RUBY_PROBE_ENABLED()) { \
        char *msg = ALLOCA_N(char, strlen(probe_name) + strlen("-" #suffix) ); \
        sprintf(msg, "%s%s", probe_name, "-" #suffix); \
        FIRE_RUBY_PROBE(msg, (char*)probe_data); \
    }

static VALUE
probe_fire(int argc, VALUE *argv, VALUE klass)
{
    int args;
    VALUE name, data, ret;
    const char *probe_data;
    char *probe_name;

    args = rb_scan_args(argc, argv, "11", &name, &data);
    probe_data = args == 2 ? StringValuePtr(data) : "";
    probe_name = StringValuePtr(name);

    if (rb_block_given_p()) {
        FIRE_WITH_SUFFIXED_MSG(probe_name, probe_data, start);
	ret = rb_yield(Qnil);
        FIRE_WITH_SUFFIXED_MSG(probe_name, probe_data, end);
    } else {
	if (TRACE_RUBY_PROBE_ENABLED())
	    FIRE_RUBY_PROBE(probe_name, (char*)probe_data);
	ret = Qnil;
    }
    return ret;
}

void Init_probe()
{
    rb_define_global_function("fire_probe", probe_fire, -1);
}
