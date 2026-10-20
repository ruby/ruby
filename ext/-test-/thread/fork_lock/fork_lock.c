#include "ruby/ruby.h"
#include "ruby/atomic.h"
#include "internal/compilers.h"
#include "internal/thread.h"
#include "internal/warnings.h"

#ifdef HAVE_WORKING_FORK
#include <pthread.h>
#include <time.h>
#include <unistd.h>

static rb_atomic_t contending;

static void *
do_nothing(void *arg)
{
    return arg;
}

static void *
contend_loop(void *arg)
{
    const struct timespec ts = {0, 10 * 1000};
    while (RUBY_ATOMIC_LOAD(contending)) {
        rb_thread_prevent_fork(do_nothing, NULL);
        nanosleep(&ts, NULL); // give a waiting fork a turn
    }
    return NULL;
}

static VALUE
stop_contending(VALUE thread)
{
    RUBY_ATOMIC_SET(contending, 0);
    pthread_join(*(pthread_t *)thread, NULL);
    return Qnil;
}

static VALUE
contend(VALUE self)
{
    pthread_t thread;
    int err;
    RUBY_ATOMIC_SET(contending, 1);
    if ((err = pthread_create(&thread, NULL, contend_loop, NULL)) != 0) {
        rb_syserr_fail(err, "pthread_create");
    }
    return rb_ensure(rb_yield, Qnil, stop_contending, (VALUE)&thread);
}
#endif

void
Init_fork_lock(void)
{
#ifdef HAVE_WORKING_FORK
    VALUE mBug = rb_define_module("Bug");
    VALUE klass = rb_define_module_under(mBug, "ThreadForkLock");
    rb_define_module_function(klass, "contend", contend, 0);
#endif
}
