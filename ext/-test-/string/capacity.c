#include "ruby.h"
#include "internal/string.h"

static VALUE
bug_str_capacity(VALUE klass, VALUE str)
{
    return
	STR_EMBED_P(str) ? INT2FIX(RSTRING_EMBED_LEN_MAX) : \
	STR_SHARED_P(str) ? INT2FIX(0) : \
	LONG2FIX(RSTRING(str)->as.heap.aux.capa);
}

void
Init_string_capacity(VALUE klass)
{
    rb_define_singleton_method(klass, "capacity", bug_str_capacity, 1);
}
