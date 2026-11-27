#include <ruby.h>
#include <exception>

static int live_exceptions;

struct counted_exception : std::exception {
    counted_exception() { live_exceptions++; }
    counted_exception(const counted_exception &) { live_exceptions++; }
    ~counted_exception() { live_exceptions--; }
};

static VALUE
raise_in_catch(VALUE self)
{
    try {
        throw counted_exception();
    }
    catch (const std::exception &) {
        rb_raise(rb_eRuntimeError, "raised in catch");
    }
    return Qnil;
}

static VALUE
throw_and_catch(VALUE self)
{
    VALUE caught = Qfalse;
    try {
        throw counted_exception();
    }
    catch (const std::exception &) {
        caught = Qtrue;
    }
    return caught;
}

static VALUE
live_exceptions_count(VALUE self)
{
    return INT2FIX(live_exceptions);
}

extern "C" void
Init_cxx_catch(void)
{
    VALUE m = rb_define_module_under(rb_define_module("Bug"), "Win32");
    rb_define_module_function(m, "raise_in_catch", raise_in_catch, 0);
    rb_define_module_function(m, "throw_and_catch", throw_and_catch, 0);
    rb_define_module_function(m, "live_exceptions", live_exceptions_count, 0);
}
