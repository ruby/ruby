#ifndef RUBY_RUBY_BACKWARD_H                         /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_RUBY_BACKWARD_H 1
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#include "ruby/internal/value.h"
#include "ruby/internal/interpreter.h"
#include "ruby/backward/2/attributes.h"

#define DECLARE_DEPRECATED_FEATURE(ver, func) \
    NORETURN(ERRORFUNC(("deprecated since "#ver), DEPRECATED(void func(void))))

/* eval.c */
DECLARE_DEPRECATED_FEATURE(2.2, rb_disable_super);
DECLARE_DEPRECATED_FEATURE(2.2, rb_enable_super);

/* hash.c */
DECLARE_DEPRECATED_FEATURE(2.2, rb_hash_iter_lev);
DECLARE_DEPRECATED_FEATURE(2.2, rb_hash_ifnone);

/* string.c */
DECLARE_DEPRECATED_FEATURE(2.2, rb_str_associate);
DECLARE_DEPRECATED_FEATURE(2.2, rb_str_associated);

/* variable.c */
DEPRECATED(void rb_autoload(VALUE, ID, const char*));

/* vm.c */
DECLARE_DEPRECATED_FEATURE(2.2, rb_clear_cache);
DECLARE_DEPRECATED_FEATURE(2.2, rb_frame_pop);

#define DECLARE_DEPRECATED_INTERNAL_FEATURE(func) \
    NORETURN(ERRORFUNC(("deprecated internal function"), DEPRECATED(void func(void))))

/* eval.c */
NORETURN(ERRORFUNC(("internal function"), void rb_frozen_class_p(VALUE)));
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_exec_end_proc);

/* error.c */
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_compile_error);
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_compile_error_with_enc);
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_compile_error_append);

/* gc.c */
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_gc_call_finalizer_at_exit);

/* signal.c */
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_trap_exit);

/* struct.c */
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_struct_ptr);

/* thread.c */
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_clear_trace_func);

/* variable.c */
DECLARE_DEPRECATED_INTERNAL_FEATURE(rb_generic_ivar_table);
NORETURN(ERRORFUNC(("internal function"), VALUE rb_mod_const_missing(VALUE, VALUE)));

/* from version.c */
#if defined(RUBY_SHOW_COPYRIGHT_TO_DIE) && !!(RUBY_SHOW_COPYRIGHT_TO_DIE+0)
/* for source code backward compatibility */
RBIMPL_ATTR_DEPRECATED(("since 2.4"))
static inline int
ruby_show_copyright_to_die(int exitcode)
{
    ruby_show_copyright();
    return exitcode;
}
#define ruby_show_copyright() /* defer EXIT_SUCCESS */ \
    (exit(ruby_show_copyright_to_die(EXIT_SUCCESS)))
#endif

#endif /* RUBY_RUBY_BACKWARD_H */
