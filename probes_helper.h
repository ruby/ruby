#ifndef RUBY_PROBES_HELPER_H
#define RUBY_PROBES_HELPER_H

#include "ruby/ruby.h"
#include "probes.h"

#define RUBY_DTRACE_FUNC_ENTRY_HOOK(klass, id) \
    if (RUBY_DTRACE_FUNCTION_ENTRY_ENABLED()) { \
	const char * classname  = rb_class2name((klass)); \
	const char * methodname = rb_id2name((id)); \
	const char * filename   = rb_sourcefile(); \
	if (classname && methodname && filename) { \
	    RUBY_DTRACE_FUNCTION_ENTRY( \
		    classname, \
		    methodname, \
		    filename, \
		    rb_sourceline()); \
	} \
    } \

#define RUBY_DTRACE_FUNC_RETURN_HOOK(klass, id) \
    if (RUBY_DTRACE_FUNCTION_RETURN_ENABLED()) { \
	const char * classname  = rb_class2name((klass)); \
	const char * methodname = rb_id2name((id)); \
	const char * filename   = rb_sourcefile(); \
	if (classname && methodname && filename) { \
	    RUBY_DTRACE_FUNCTION_RETURN( \
		    classname, \
		    methodname, \
		    filename, \
		    rb_sourceline()); \
	} \
    } \

#endif /* RUBY_PROBES_HELPER_H */
