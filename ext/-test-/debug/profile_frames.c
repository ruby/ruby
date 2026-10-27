#include "ruby/ruby.h"
#include "ruby/atomic.h"
#include "ruby/debug.h"
#include <errno.h>
#include <signal.h>

#define MAX_BUF_SIZE 0x100

static VALUE
profile_frames(VALUE self, VALUE start_v, VALUE num_v)
{
    int i, collected_size;
    int start = NUM2INT(start_v);
    int buff_size = NUM2INT(num_v);
    VALUE buff[MAX_BUF_SIZE];
    int lines[MAX_BUF_SIZE];
    VALUE result = rb_ary_new();

    if (buff_size > MAX_BUF_SIZE) rb_raise(rb_eRuntimeError, "too long buff_size");

    collected_size = rb_profile_frames(start, buff_size, buff, lines);

    for (i=0; i<collected_size; i++) {
        VALUE ary = rb_ary_new();
        rb_ary_push(ary, rb_profile_frame_path(buff[i]));
        rb_ary_push(ary, rb_profile_frame_absolute_path(buff[i]));
        rb_ary_push(ary, rb_profile_frame_label(buff[i]));
        rb_ary_push(ary, rb_profile_frame_base_label(buff[i]));
        rb_ary_push(ary, rb_profile_frame_full_label(buff[i]));
        rb_ary_push(ary, rb_profile_frame_first_lineno(buff[i]));
        rb_ary_push(ary, rb_profile_frame_classpath(buff[i]));
        rb_ary_push(ary, rb_profile_frame_singleton_method_p(buff[i]));
        rb_ary_push(ary, rb_profile_frame_method_name(buff[i]));
        rb_ary_push(ary, rb_profile_frame_qualified_method_name(buff[i]));
        rb_ary_push(ary, INT2NUM(lines[i]));

        rb_ary_push(result, ary);
    }

    return result;
}

static VALUE
profile_thread_frames(VALUE self, VALUE thread, VALUE start_v, VALUE num_v)
{
    int i, collected_size;
    int start = NUM2INT(start_v);
    int buff_size = NUM2INT(num_v);
    VALUE buff[MAX_BUF_SIZE];
    int lines[MAX_BUF_SIZE];
    VALUE result = rb_ary_new();

    if (buff_size > MAX_BUF_SIZE) rb_raise(rb_eRuntimeError, "too long buff_size");

    collected_size = rb_profile_thread_frames(thread, start, buff_size, buff, lines);
    for (i=0; i<collected_size; i++) {
        rb_ary_push(result, rb_profile_frame_full_label(buff[i]));
    }

    return result;
}

#if defined(HAVE_PTHREAD_H) && defined(HAVE_SIGACTION) && defined(SIGPROF)
#include <pthread.h>
#include <time.h>

static pthread_t sampler_target_thread;
static pthread_t sampler_thread;
static rb_atomic_t sampler_running;
static rb_atomic_t sampler_samples;

/* Like sampling profilers, call rb_profile_frames() directly in the signal handler */
static void
sampler_signal_handler(int sig)
{
    int saved_errno = errno;
    VALUE buff[MAX_BUF_SIZE];
    int lines[MAX_BUF_SIZE];

    rb_profile_frames(0, MAX_BUF_SIZE, buff, lines);
    RUBY_ATOMIC_INC(sampler_samples);
    errno = saved_errno;
}

static void *
sampler_loop(void *arg)
{
    const struct timespec ts = {0, 10 * 1000};
    while (RUBY_ATOMIC_LOAD(sampler_running)) {
        pthread_kill(sampler_target_thread, SIGPROF);
        nanosleep(&ts, NULL);
    }
    return NULL;
}

/* Send SIGPROF to the calling thread every ~10us from another native thread */
static VALUE
start_profile_frames_sampler(VALUE self)
{
    struct sigaction sa = {0};
    int err;

    if (RUBY_ATOMIC_LOAD(sampler_running)) rb_raise(rb_eRuntimeError, "sampler already running");

    /* The handler stays installed after stop, as a SIGPROF might still be pending */
    sa.sa_handler = sampler_signal_handler;
    sa.sa_flags = SA_RESTART;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGPROF, &sa, NULL) != 0) rb_sys_fail("sigaction");

    sampler_target_thread = pthread_self();
    RUBY_ATOMIC_SET(sampler_samples, 0);
    RUBY_ATOMIC_SET(sampler_running, 1);
    if ((err = pthread_create(&sampler_thread, NULL, sampler_loop, NULL)) != 0) {
        RUBY_ATOMIC_SET(sampler_running, 0);
        rb_syserr_fail(err, "pthread_create");
    }
    return Qnil;
}

/* Returns the number of samples taken */
static VALUE
stop_profile_frames_sampler(VALUE self)
{
    if (!RUBY_ATOMIC_LOAD(sampler_running)) rb_raise(rb_eRuntimeError, "sampler not running");

    RUBY_ATOMIC_SET(sampler_running, 0);
    pthread_join(sampler_thread, NULL);
    return UINT2NUM(RUBY_ATOMIC_LOAD(sampler_samples));
}
#endif

void
Init_profile_frames(VALUE klass)
{
    rb_define_module_function(klass, "profile_frames", profile_frames, 2);
    rb_define_module_function(klass, "profile_thread_frames", profile_thread_frames, 3);
#if defined(HAVE_PTHREAD_H) && defined(HAVE_SIGACTION) && defined(SIGPROF)
    rb_define_module_function(klass, "start_profile_frames_sampler", start_profile_frames_sampler, 0);
    rb_define_module_function(klass, "stop_profile_frames_sampler", stop_profile_frames_sampler, 0);
#endif
}
