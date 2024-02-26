
#include "ruby/ruby.h"
#include "ruby/thread.h"

#ifdef HAVE_PTHREAD_H
#include <pthread.h>

static pthread_key_t tls_key;

static VALUE
get_tls(VALUE self)
{
    return (VALUE)pthread_getspecific(tls_key);
}

static VALUE
set_tls(VALUE self, VALUE vn)
{
    pthread_setspecific(tls_key, (void *)vn);
    return Qnil;
}

static VALUE
lock_native_thread(VALUE self)
{
    return rb_thread_lock_native_thread() ? Qtrue : Qfalse;
}

void
Init_lock_native_thread(void)
{
    int r;

    if ((r = pthread_key_create(&tls_key, NULL)) != 0) {
        rb_bug("pthread_key_create() returns %d", r);
    }
    pthread_setspecific(tls_key, NULL);

    rb_define_method(rb_cThread, "lock_native_thread", lock_native_thread, 0);
    rb_define_method(rb_cThread, "get_tls", get_tls, 0);
    rb_define_method(rb_cThread, "set_tls", set_tls, 1);
}

#else // HAVE_PTHREAD_H
void
Init_lock_native_thread(void)
{
    // do nothing
}
#endif // HAVE_PTHREAD_H
