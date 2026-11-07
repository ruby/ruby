#include "ruby.h"
#include <signal.h>

#ifdef POSIX_SIGNAL
struct signal_state {
    int signo;
    struct sigaction action;
    sigset_t mask;
};

static void
test_handler(int signo)
{
}

static VALUE
restore_handler(VALUE arg)
{
    struct signal_state *state = (struct signal_state *)arg;
    if (sigaction(state->signo, &state->action, NULL) < 0) rb_sys_fail("sigaction");
    return Qnil;
}

static VALUE
with_handler(VALUE self, VALUE signo)
{
    struct signal_state state = {.signo = NUM2INT(signo)};
    struct sigaction action = {0};
    action.sa_handler = test_handler;
#ifdef SA_RESTART
    action.sa_flags = SA_RESTART;
#endif
    sigemptyset(&action.sa_mask);
    sigaddset(&action.sa_mask, SIGINT);
    if (sigaction(state.signo, &action, &state.action) < 0) rb_sys_fail("sigaction");
    return rb_ensure(rb_yield, Qnil, restore_handler, (VALUE)&state);
}

static VALUE
handler_state(VALUE self, VALUE signo)
{
    struct sigaction action;
    if (sigaction(NUM2INT(signo), NULL, &action) < 0) rb_sys_fail("sigaction");
    return rb_ary_new_from_args(3,
        action.sa_handler == test_handler ? Qtrue : Qfalse,
        INT2NUM(action.sa_flags),
        INT2NUM(sigismember(&action.sa_mask, SIGINT)));
}

static VALUE
restore_mask(VALUE arg)
{
    struct signal_state *state = (struct signal_state *)arg;
    if (sigprocmask(SIG_SETMASK, &state->mask, NULL) < 0) rb_sys_fail("sigprocmask");
    return Qnil;
}

static VALUE
raise_and_yield(VALUE signo)
{
    if (raise(NUM2INT(signo)) != 0) rb_sys_fail("raise");
    return rb_yield(Qnil);
}

static VALUE
with_pending_signal(VALUE self, VALUE signo)
{
    struct signal_state state;
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, NUM2INT(signo));
    if (sigprocmask(SIG_BLOCK, &mask, &state.mask) < 0) rb_sys_fail("sigprocmask");
    return rb_ensure(raise_and_yield, signo, restore_mask, (VALUE)&state);
}

static VALUE
signal_pending_p(VALUE self, VALUE signo)
{
    sigset_t pending;
    if (sigpending(&pending) < 0) rb_sys_fail("sigpending");
    return sigismember(&pending, NUM2INT(signo)) == 1 ? Qtrue : Qfalse;
}
#endif

void
Init_signal(void)
{
    VALUE mod = rb_define_module_under(rb_define_module("Bug"), "Signal");
    (void)mod;
#ifdef POSIX_SIGNAL
    rb_define_singleton_method(mod, "with_handler", with_handler, 1);
    rb_define_singleton_method(mod, "handler_state", handler_state, 1);
    rb_define_singleton_method(mod, "with_pending_signal", with_pending_signal, 1);
    rb_define_singleton_method(mod, "pending?", signal_pending_p, 1);
#endif
}
