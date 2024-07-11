#include <ruby/ruby.h>
#include <ruby/debug.h>

#ifndef MAYBE_UNUSED
# define MAYBE_UNUSED(x) x
#endif

static NOINLINE(VALUE f(VALUE));
static NOINLINE(void g(VALUE, void*));
extern NOINLINE(void Init_bug_14834(void));

void
Init_bug_14834(void)
{
    VALUE q = rb_define_module("Bug");
    rb_define_module_function(q, "bug_14834", f, 0);
}

VALUE
f(VALUE q)
{
    int   w[] = { 0, 1024 };
    VALUE e   = rb_tracepoint_new(Qnil, RUBY_INTERNAL_EVENT_NEWOBJ, g, w);

    rb_tracepoint_enable(e);
    return rb_ensure(rb_yield, q, rb_tracepoint_disable, e);
}

void
g(MAYBE_UNUSED(VALUE q), void* w)
{
    const int *e = (const int *)w;
    const int  r = *e++;
    const int  t = *e++;
    VALUE     *y = ALLOCA_N(VALUE, t);
    int       *u = ALLOCA_N(int, t);

    rb_profile_frames(r, t, y, u);
}
