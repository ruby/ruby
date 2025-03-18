#include <ruby.h>

#if SIZEOF_LONG == SIZEOF_VOIDP
# define NUM2PTR(x) NUM2ULONG(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
# define NUM2PTR(x) NUM2ULL(x)
#endif

static VALUE
invalid_call(VALUE obj, VALUE address)
{
    typedef VALUE (*func_type)(VALUE);

    return (*(func_type)NUM2PTR(address))(obj);
}

static VALUE
invalid_access(VALUE obj, VALUE address)
{
    return *(VALUE *)NUM2PTR(address) == obj ? Qtrue : Qfalse;
}

void
Init_invalid(VALUE mBug)
{
    rb_define_singleton_method(mBug, "invalid_call", invalid_call, 1);
    rb_define_singleton_method(mBug, "invalid_access", invalid_access, 1);
}
