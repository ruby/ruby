#include "ruby.h"

#ifdef HAVE_RB_IS_CONST_NAME
# define get_symbol_type(type, t, name) do { \
        ID id = rb_check_id(&name); \
        t = (id ? rb_is_##type##_id(id) : rb_is_##type##_name(name)); \
    } while (0)
#else
# define get_symbol_type(type, t, name) do { \
        t = rb_is_##type##_id(rb_to_id(name)); \
    } while (0)
#endif

#define define_symbol_type_p(type) \
static VALUE \
bug_sym_##type##_p(VALUE self, VALUE name) \
{ \
    int t; \
    get_symbol_type(type, t, name); \
    return (t ? Qtrue : Qfalse); \
}

#define declare_symbol_type_p(type) \
    rb_define_singleton_method(klass, #type"?", bug_sym_##type##_p, 1);

#define FOREACH_ID_TYPES(x) x(const) x(class) x(global) x(instance) x(attrset) x(local) x(junk)

FOREACH_ID_TYPES(define_symbol_type_p)

static VALUE
bug_sym_attrset(VALUE self, VALUE name)
{
    ID id = rb_to_id(name);
    id = rb_id_attrset(id);
    return ID2SYM(id);
}

static VALUE
bug_id2str(VALUE self, VALUE sym)
{
    return rb_sym2str(sym);
}

static VALUE
bug_static_p(VALUE self, VALUE sym)
{
    return STATIC_SYM_P(sym) ? Qtrue : Qfalse;
}

static VALUE
bug_dynamic_p(VALUE self, VALUE sym)
{
    return DYNAMIC_SYM_P(sym) ? Qtrue : Qfalse;
}

#ifdef HAVE_RB_PIN_DYNAMIC_SYMBOL
ID rb_pin_dynamic_symbol(VALUE);

static VALUE
bug_pindown(VALUE self, VALUE sym)
{
    rb_pin_dynamic_symbol(sym);
    return sym;
}
#endif

void
Init_type(VALUE klass)
{
    FOREACH_ID_TYPES(declare_symbol_type_p);
    rb_define_singleton_method(klass, "attrset", bug_sym_attrset, 1);
    rb_define_singleton_method(klass, "id2str", bug_id2str, 1);
    rb_define_singleton_method(klass, "static?", bug_static_p, 1);
    rb_define_singleton_method(klass, "dynamic?", bug_dynamic_p, 1);
#ifdef HAVE_RB_PIN_DYNAMIC_SYMBOL
    rb_define_singleton_method(klass, "pindown", bug_pindown, 1);
#endif
}
