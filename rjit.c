#include "internal/symbol.h"
#include "ruby.h"
#include <stdlib.h>
#include <stdio.h>

#if USE_YJIT
typedef void * (*intern_cstr_func)(const char *);

size_t rb_rjit_address_of(void * name, intern_cstr_func func);

static VALUE
address_of(VALUE m, VALUE name)
{
    size_t addr = rb_rjit_address_of((void *)name, (intern_cstr_func)rb_sym_intern_ascii_cstr);

    if (addr) {
        return SIZET2NUM(addr);
    }
    else {
        return Qfalse;
    }
}
#endif

void
rb_rjit_init(void)
{
    VALUE vm = rb_define_class("RubyVM", rb_cObject);
    VALUE internals = rb_define_class_under(vm, "Internals", rb_cObject);
#if USE_YJIT
    rb_define_singleton_method(internals, "address_of", address_of, 1);
#else
    rb_define_singleton_method(internals, "address_of", rb_f_notimplement, 1);
#endif
}
