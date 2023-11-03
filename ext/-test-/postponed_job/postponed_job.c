#include "ruby.h"
#include "ruby/debug.h"

static int counter;

static void
pjob_callback(void *data)
{
    VALUE ary = (VALUE)data;
    Check_Type(ary, T_ARRAY);

    rb_ary_push(ary, INT2FIX(counter));
}

static VALUE
pjob_register(VALUE self, VALUE obj)
{
    counter = 0;
    rb_postponed_job_register(0, pjob_callback, (void *)obj);
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    return self;
}

static void
pjob_one_callback(void *data)
{
    VALUE ary = (VALUE)data;
    Check_Type(ary, T_ARRAY);

    rb_ary_push(ary, INT2FIX(1));
}

static VALUE
pjob_register_one(VALUE self, VALUE obj)
{
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    return self;
}

static VALUE
pjob_call_direct(VALUE self, VALUE obj)
{
    counter = 0;
    pjob_callback((void *)obj);
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    rb_gc_start();
    counter++;
    return self;
}

#ifdef HAVE_PTHREAD_H
#include <pthread.h>

static void *
pjob_register_in_c_thread_i(void *obj)
{
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    rb_postponed_job_register_one(0, pjob_one_callback, (void *)obj);
    return NULL;
}

static VALUE
pjob_register_in_c_thread(VALUE self, VALUE obj)
{
    pthread_t thread;
    if (pthread_create(&thread, NULL, pjob_register_in_c_thread_i, (void *)obj)) {
        return Qfalse;
    }

    if (pthread_join(thread, NULL)) {
        return Qfalse;
    }

    return Qtrue;
}
#endif

#if defined(HAVE_PTHREAD_H) && defined(HAVE_CLOCK_GETTIME) && defined(CLOCK_MONOTONIC) && defined(HAVE_SIGACTION)
#include <sched.h>
#include <signal.h>

#define RACE_NUM_COUNTERS 500
#define RACE_NUM_ITERATIONS 1000
static int job_counters[RACE_NUM_COUNTERS];
static int signal_job_counter;
static sig_atomic_t signal_jobs_enqueued;
static pthread_t test_main_thread;

static void
pobj_register_race_callback(void *data)
{
    intptr_t index = (intptr_t)data;
    if (index == -1) {
        signal_job_counter += 1;
    } else {
        job_counters[index] += 1;
    }
}

static void *
pjob_register_thread_race_i(void *_data)
{
    for (size_t i = 0; i < RACE_NUM_ITERATIONS; i++) {
        for (intptr_t j = 0; j < RACE_NUM_COUNTERS; j++) {
            while (rb_postponed_job_register(0, pobj_register_race_callback, (void *)j) == 0) {
                sched_yield();
                pthread_testcancel();
            }
        }
        pthread_kill(test_main_thread, SIGUSR2);
    }
    return NULL;
}

static VALUE
pjob_register_thread_race_sleep_protected(VALUE arg)
{
    rb_thread_sleep(0);
    return Qnil;
}

static void
pjob_register_thread_race_signal_handler(int sig)
{
    if (rb_postponed_job_register(0, pobj_register_race_callback, (void *)-1)) {
        signal_jobs_enqueued++;
    }
}

static VALUE
pjob_register_thread_race(VALUE self)
{

    pthread_t thread;
    test_main_thread = pthread_self();
    VALUE ret = Qnil;
    int tag = 0;
    struct sigaction old_handler;
    struct sigaction usr2_handler = {0};
    signal_job_counter = 0;
    signal_jobs_enqueued = 0;
    int handler_registered = 0;
    int thread_created = 0;
    for (size_t i = 0; i < RACE_NUM_COUNTERS; i++) {
        job_counters[i] = 0;
    }


    usr2_handler.sa_flags = SA_NODEFER | SA_RESTART;
    usr2_handler.sa_handler = pjob_register_thread_race_signal_handler;
    if (sigaction(SIGUSR2, &usr2_handler, &old_handler) == -1) {
        ret = rb_id2sym(rb_intern("pthread_create_failed"));
        goto test_done;
    }
    handler_registered = 1;


    if (pthread_create(&thread, NULL, pjob_register_thread_race_i, NULL)) {
        ret = rb_id2sym(rb_intern("pthread_create_failed"));
        goto test_done;
    }
    thread_created = 1;


    struct timespec t1;
    clock_gettime(CLOCK_MONOTONIC, &t1);

    /* Spin waiting for the jobs, yielding to ruby, so that the jobs can actually happen */
    while (true) {
        struct timespec t2;
        clock_gettime(CLOCK_MONOTONIC, &t2);
        /* time out after... well, about 5 seconds */
        if (t2.tv_sec > t1.tv_sec + 60) {
            ret = rb_id2sym(rb_intern("timed_out"));
            goto test_done;
        }
        rb_protect(pjob_register_thread_race_sleep_protected, Qnil, &tag);
        if (tag) {
            goto test_done;
        }

        int done = 1;
        for (size_t i = 0; i < RACE_NUM_COUNTERS; i++) {
            /* this is safe - the jobs are running _on this thread_, so accessing them
               without atomics is OK (and atomics would add additional synchronization
               to the test we don't actually want) */
            if (job_counters[i] > RACE_NUM_ITERATIONS) {
                /* this job ran twice somehow. */
                ret = rb_id2sym(rb_intern("job_counter_too_high"));
                goto test_done;
            } else if (job_counters[i] < RACE_NUM_ITERATIONS) {
                /* not ready yet */
                done = 0;
            }
        }
        if (signal_jobs_enqueued < signal_job_counter) {
            done = 0;
        }
        if (done) {
            ret =  rb_id2sym(rb_intern("ok"));
            goto test_done;
        }
    }

test_done:
    if (thread_created) {
        pthread_cancel(thread);
        pthread_join(thread, NULL);
    }
    if (handler_registered) {
        sigaction(SIGUSR2, &old_handler, NULL);
    }
    if (tag) {
        rb_jump_tag(tag);
    }
    return ret;
}

#else
# define pjob_register_thread_race rb_f_notimplement
#endif


void
Init_postponed_job(VALUE self)
{
    VALUE mBug = rb_define_module("Bug");
    rb_define_module_function(mBug, "postponed_job_register", pjob_register, 1);
    rb_define_module_function(mBug, "postponed_job_register_one", pjob_register_one, 1);
    rb_define_module_function(mBug, "postponed_job_call_direct", pjob_call_direct, 1);
#ifdef HAVE_PTHREAD_H
    rb_define_module_function(mBug, "postponed_job_register_in_c_thread", pjob_register_in_c_thread, 1);
#endif
    rb_define_module_function(mBug, "postponed_job_register_race", pjob_register_thread_race, 0);
}

