#include <ruby.h>
#include "ruby/internal/intern/load.h"
#include "ruby/util.h"

#if SIZEOF_INTPTR_T == SIZEOF_LONG_LONG
#   define UINTPTR2NUM ULL2NUM
#elif SIZEOF_INTPTR_T == SIZEOF_LONG
#   define UINTPTR2NUM ULONG2NUM
#else
#   define UINTPTR2NUM UINT2NUM
#endif

static VALUE
stringify_symbol(VALUE klass, VALUE fname, VALUE sname)
{
    void *ptr = rb_ext_resolve_symbol(StringValueCStr(fname), StringValueCStr(sname));
    if (ptr == NULL) {
        return Qnil;
    }
    uintptr_t uintptr = (uintptr_t)ptr;
    return UINTPTR2NUM(uintptr);
}

void
Init_stringify_symbols(void)
{
    VALUE mod = rb_define_module("StringifySymbols");
    rb_define_singleton_method(mod, "stringify_symbol", stringify_symbol, 2);
}
