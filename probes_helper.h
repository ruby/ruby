#ifndef RUBY_PROBES_HELPER_H
#define RUBY_PROBES_HELPER_H

#include "ruby/ruby.h"
#include "probes.h"

VALUE rb_class_path_no_cache(VALUE _klass);

#define RUBY_DTRACE_HOOK(name, th, klazz, id) \
do { \
    if (RUBY_DTRACE_##name##_ENABLED()) { \
	VALUE _klass = (klazz); \
	ID _id = (id); \
	const char * classname; \
	const char * methodname; \
	const char * filename; \
	if (!_klass) { \
	    rb_thread_method_id_and_class((th), &_id, &_klass); \
	} \
	if (_klass) { \
	    if (RB_TYPE_P(_klass, T_ICLASS)) { \
		_klass = RBASIC(_klass)->klass; \
	    } \
	    else if (FL_TEST(_klass, FL_SINGLETON)) { \
		_klass = rb_iv_get(_klass, "__attached__"); \
	    } \
	    switch (TYPE(_klass)) { \
		case T_CLASS: \
		case T_ICLASS: \
		case T_MODULE: \
		{ \
		    VALUE _name = rb_class_path_no_cache(_klass); \
		    if (!NIL_P(_name)) { \
		        classname = StringValuePtr(_name); \
		    } \
		    else {			 \
		        classname = "<unknown>"; \
		    } \
		    methodname = rb_id2name(_id); \
		    filename   = rb_sourcefile(); \
		    if (classname && methodname && filename) { \
		        RUBY_DTRACE_##name( \
				classname, \
				methodname, \
				filename, \
				rb_sourceline()); \
		    } \
		    break; \
		} \
	    } \
	} \
    } \
} while (0)

#define RUBY_DTRACE_METHOD_ENTRY_HOOK(th, klass, id) \
    RUBY_DTRACE_HOOK(METHOD_ENTRY, th, klass, id)

#define RUBY_DTRACE_METHOD_RETURN_HOOK(th, klass, id) \
    RUBY_DTRACE_HOOK(METHOD_RETURN, th, klass, id)

#define RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, klass, id) \
    RUBY_DTRACE_HOOK(CMETHOD_ENTRY, th, klass, id)

#define RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, klass, id) \
    RUBY_DTRACE_HOOK(CMETHOD_RETURN, th, klass, id)

#endif /* RUBY_PROBES_HELPER_H */
