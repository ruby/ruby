#include <ruby.h>
#include "ruby/internal/intern/load.h"

typedef VALUE(*target_func)(VALUE);

static target_func rst_any_method;

VALUE
rsr_any_method(VALUE klass)
{
    return rst_any_method((VALUE)NULL);
}

VALUE
rsr_try_resolve_fname(VALUE klass)
{
    target_func rst_something_missing =
        (target_func) rb_ext_resolve_symbol("-test-/load/resolve_symbol_missing", "rst_any_method");
    if (rst_something_missing == NULL) {
        // This should be done in Init_*, so the error is LoadError
        rb_raise(rb_eLoadError, "symbol not found: missing fname");
    }
    return Qtrue;
}

VALUE
rsr_try_resolve_sname(VALUE klass)
{
    target_func rst_something_missing =
        (target_func)rb_ext_resolve_symbol("-test-/load/resolve_symbol_target", "rst_something_missing");
    if (rst_something_missing == NULL) {
        // This should be done in Init_*, so the error is LoadError
        rb_raise(rb_eLoadError, "symbol not found: missing sname");
    }
    return Qtrue;
}

void
Init_resolve_symbol_resolver(void)
{
    /*
     * Resolving symbols at the head of Init_ because it raises LoadError (in cases).
     * If the module and methods are defined before raising LoadError, retrying `require "this.so"` will
     * cause re-defining those methods (and will be warned).
     */
    rst_any_method = (target_func)rb_ext_resolve_symbol("-test-/load/resolve_symbol_target", "rst_any_method");
    if (rst_any_method == NULL) {
        rb_raise(rb_eLoadError, "resolve_symbol_target is not loaded");
    }

    VALUE mod = rb_define_module("ResolveSymbolResolver");
    rb_define_singleton_method(mod, "any_method", rsr_any_method, 0);
    rb_define_singleton_method(mod, "try_resolve_fname", rsr_try_resolve_fname, 0);
    rb_define_singleton_method(mod, "try_resolve_sname", rsr_try_resolve_sname, 0);
}
