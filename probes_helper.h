#ifndef RUBY_PROBES_HELPER_H
#define RUBY_PROBES_HELPER_H

#include "ruby/ruby.h"

struct ruby_dtrace_method_hook_args {
    const char *classname;
    const char *methodname;
    const char *filename;
    int line_no;
    volatile VALUE klass;
    volatile VALUE name;
};

NOINLINE(int rb_dtrace_setup(rb_execution_context_t *, VALUE, ID, struct ruby_dtrace_method_hook_args *));

#define RUBY_DTRACE_METHOD_HOOK(name, ec, klazz, id) \
do { \
    if (UNLIKELY(RUBY_DTRACE_##name##_ENABLED())) { \
        struct ruby_dtrace_method_hook_args args; \
        if (rb_dtrace_setup(ec, klazz, id, &args)) { \
            RUBY_DTRACE_##name(args.classname, \
                               args.methodname, \
                               args.filename, \
                               args.line_no); \
        } \
    } \
} while (0)

#define RUBY_DTRACE_METHOD_ENTRY_HOOK(ec, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(METHOD_ENTRY, ec, klass, id)

#define RUBY_DTRACE_METHOD_RETURN_HOOK(ec, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(METHOD_RETURN, ec, klass, id)

#define RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(CMETHOD_ENTRY, ec, klass, id)

#define RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(CMETHOD_RETURN, ec, klass, id)

#endif /* RUBY_PROBES_HELPER_H */
