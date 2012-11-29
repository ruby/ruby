#ifndef RUBY_PROBES_HELPER_H
#define RUBY_PROBES_HELPER_H

#include "ruby/ruby.h"
#include "probes.h"

#define RUBY_DTRACE_METHOD_ENTRY_HOOK(klass, id) \
    if (RUBY_DTRACE_METHOD_ENTRY_ENABLED()) { \
	const char * classname  = rb_class2name((klass)); \
	const char * methodname = rb_id2name((id)); \
	const char * filename   = rb_sourcefile(); \
	if (classname && methodname && filename) { \
	    RUBY_DTRACE_METHOD_ENTRY( \
		    classname, \
		    methodname, \
		    filename, \
		    rb_sourceline()); \
	} \
    } \

#define RUBY_DTRACE_METHOD_RETURN_HOOK(th, klass, id) \
    if (RUBY_DTRACE_METHOD_RETURN_ENABLED()) { \
	VALUE _klass = (klass); \
	VALUE _id = (id); \
	const char * classname; \
	const char * methodname; \
	const char * filename; \
	if (!_klass) { \
	    rb_thread_method_id_and_class((th), &_id, &_klass); \
	} \
	classname  = rb_class2name(_klass); \
	methodname = rb_id2name(_id); \
	filename   = rb_sourcefile(); \
	if (classname && methodname && filename) { \
	    RUBY_DTRACE_METHOD_RETURN( \
		    classname, \
		    methodname, \
		    filename, \
		    rb_sourceline()); \
	} \
    } \

#endif /* RUBY_PROBES_HELPER_H */
