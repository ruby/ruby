#include <ruby.h>

static VALUE
exc_unreachable_return(VALUE self)
{
    rb_raise(rb_eRuntimeError, "unreachable_return");

    /* UNREACHABLE_RETURN must accept an empty argument on compilers with
     * unreachability support; gcc, clang and MSVC all discard it. */
#if RBIMPL_HAS_BUILTIN(__builtin_unreachable) || defined(HAVE___ASSUME)
    UNREACHABLE_RETURN();
#else
    UNREACHABLE_RETURN(Qnil);
#endif
}

void
Init_unreachable_return(VALUE klass)
{
    rb_define_module_function(klass, "unreachable_return", exc_unreachable_return, 0);
}
