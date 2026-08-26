#include <ruby.h>
#include <signal.h>

static VALUE
bug_segv(VALUE self)
{
    raise(SIGSEGV);
    return Qnil; /* never reached */
}

void
Init_segv(VALUE mBug)
{
    rb_define_singleton_method(mBug, "segv", bug_segv, 0);
}
