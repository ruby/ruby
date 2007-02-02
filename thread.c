/**********************************************************************

  thread.c -

  $Author$
  $Date$

  Copyright (C) 2004-2006 Koichi Sasada

**********************************************************************/

/*
  YARV Thread Desgin

  model 1: Userlevel Thread
    Same as traditional ruby thread.

  model 2: Native Thread with Giant VM lock
    Using pthread (or Windows thread) and Ruby threads run concurrent.

  model 3: Native Thread with fine grain lock
    Using pthread and Ruby threads run concurrent or parallel.

------------------------------------------------------------------------

  model 2:
    A thread has mutex (GVL: Global VM Lock) can run.  When thread
    scheduling, running thread release GVL.  If running thread
    try blocking operation, this thread must release GVL and another
    thread can continue this flow.  After blocking operation, thread
    must check interrupt (YARV_CHECK_INTS).

    Every VM can run parallel.

    Ruby threads are scheduled by OS thread scheduler.

------------------------------------------------------------------------

  model 3:
    Every threads run concurrent or parallel and to access shared object
    exclusive access control is needed.  For example, to access String
    object or Array object, fine grain lock must be locked every time.
 */


/* for model 2 */

#include "eval_intern.h"
#include "vm.h"

#define THREAD_DEBUG 0

static void sleep_for_polling();
static void sleep_timeval(yarv_thread_t *th, struct timeval time);
static void sleep_wait_for_interrupt(yarv_thread_t *th, double sleepsec);
static void sleep_forever(yarv_thread_t *th);
static double timeofday();
struct timeval rb_time_interval(VALUE);
static int rb_thread_dead(yarv_thread_t *th);

void rb_signal_exec(yarv_thread_t *th, int sig);
void rb_disable_interrupt();

NOINLINE(void yarv_set_stack_end(VALUE **stack_end_p));

static VALUE eKillSignal = INT2FIX(0);
static VALUE eTerminateSignal = INT2FIX(1);
static volatile int system_working = 1;

inline static void
st_delete_wrap(st_table * table, VALUE key)
{
    st_delete(table, (st_data_t *) & key, 0);
}

/********************************************************************************/

#define THREAD_SYSTEM_DEPENDENT_IMPLEMENTATION

static void native_thread_interrupt(yarv_thread_t *th);
static void yarv_set_interrupt_function(yarv_thread_t *th, yarv_interrupt_function_t *func, int is_return);
static void yarv_clear_interrupt_function(yarv_thread_t *th);

#define GVL_UNLOCK_RANGE(exec) do { \
    yarv_thread_t *__th = GET_THREAD(); \
    int __prev_status = __th->status; \
    yarv_set_interrupt_function(__th, native_thread_interrupt, 0); \
    __th->status = THREAD_STOPPED; \
    GVL_UNLOCK_BEGIN(); {\
	    exec; \
    } \
    GVL_UNLOCK_END(); \
    yarv_remove_signal_thread_list(__th); \
    yarv_clear_interrupt_function(__th); \
    if (__th->status == THREAD_STOPPED) { \
	__th->status = __prev_status; \
    } \
    YARV_CHECK_INTS(); \
} while(0)

#if THREAD_DEBUG
void thread_debug(const char *fmt, ...);
#else
#define thread_debug if(0)printf
#endif

#if   defined(_WIN32) || defined(__CYGWIN__)
#include "thread_win32.ci"

#define DEBUG_OUT() \
  WaitForSingleObject(&debug_mutex, INFINITE); \
  printf("%8p - %s", GetCurrentThreadId(), buf); \
  ReleaseMutex(&debug_mutex);

#elif defined(HAVE_PTHREAD_H)
#include "thread_pthread.ci"

#define DEBUG_OUT() \
  pthread_mutex_lock(&debug_mutex); \
  printf("%8p - %s", pthread_self(), buf); \
  pthread_mutex_unlock(&debug_mutex);

#else
#error "unsupported thread type"
#endif

#if THREAD_DEBUG
static int debug_mutex_initialized = 1;
static yarv_thread_lock_t debug_mutex;

void
thread_debug(const char *fmt, ...)
{
    va_list args;
    char buf[BUFSIZ];

    if (debug_mutex_initialized == 1) {
	debug_mutex_initialized = 0;
	native_mutex_initialize(&debug_mutex);
    }

    va_start(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);

    DEBUG_OUT();
}
#endif


static void
yarv_set_interrupt_function(yarv_thread_t *th, yarv_interrupt_function_t *func, int is_return)
{
  check_ints:
    YARV_CHECK_INTS();
    native_mutex_lock(&th->interrupt_lock);
    if (th->interrupt_flag) {
	native_mutex_unlock(&th->interrupt_lock);
	if (is_return) {
	    return;
	}
	else {
	    goto check_ints;
	}
    }
    else {
	th->interrupt_function = func;
    }
    native_mutex_unlock(&th->interrupt_lock);
}

static void
yarv_clear_interrupt_function(yarv_thread_t *th)
{
    native_mutex_lock(&th->interrupt_lock);
    th->interrupt_function = 0;
    native_mutex_unlock(&th->interrupt_lock);
}

static void
rb_thread_interrupt(yarv_thread_t *th)
{
    native_mutex_lock(&th->interrupt_lock);
    th->interrupt_flag = 1;

    if (th->interrupt_function) {
	(th->interrupt_function)(th);
    }
    else {
	/* none */
    }
    native_mutex_unlock(&th->interrupt_lock);
}


static int
terminate_i(st_data_t key, st_data_t val, yarv_thread_t *main_thread)
{
    VALUE thval = key;
    yarv_thread_t *th;
    GetThreadPtr(thval, th);

    if (th != main_thread) {
	thread_debug("terminate_i: %p\n", th);
	rb_thread_interrupt(th);
	th->throwed_errinfo = eTerminateSignal;
	th->status = THREAD_TO_KILL;
    }
    else {
	thread_debug("terminate_i: main thread (%p)\n", th);
    }
    return ST_CONTINUE;
}

void
rb_thread_terminate_all(void)
{
    yarv_thread_t *th = GET_THREAD(); /* main thread */
    yarv_vm_t *vm = th->vm;
    if (vm->main_thread != th) {
	rb_bug("rb_thread_terminate_all: called by child thread (%p, %p)", vm->main_thread, th);
    }

    thread_debug("rb_thread_terminate_all (main thread: %p)\n", th);
    st_foreach(vm->living_threads, terminate_i, (st_data_t)th);

    while (!rb_thread_alone()) {
	rb_thread_schedule();
    }
    system_working = 0;
}


VALUE th_eval_body(yarv_thread_t *th);

static void
thread_cleanup_func(void *th_ptr)
{
    yarv_thread_t *th = th_ptr;
    th->status = THREAD_KILLED;
    th->machine_stack_start = th->machine_stack_end = 0;
}


static int
thread_start_func_2(yarv_thread_t *th, VALUE *stack_start)
{
    int state;
    VALUE args = th->first_args;
    yarv_proc_t *proc;
    yarv_thread_t *join_th;
    th->machine_stack_start = stack_start;
    th->thgroup = th->vm->thgroup_default;

    thread_debug("thread start: %p\n", th);

    native_mutex_lock(&th->vm->global_interpreter_lock);
    {
	thread_debug("thread start (get lock): %p\n", th);
	yarv_set_current_running_thread(th);

	TH_PUSH_TAG(th);
	if ((state = EXEC_TAG()) == 0) {
	    GetProcPtr(th->first_proc, proc);
	    th->errinfo = Qnil;
	    th->local_lfp = proc->block.lfp;
	    th->local_svar = Qnil;
	    th->value = th_invoke_proc(th, proc, proc->block.self,
				       RARRAY_LEN(args), RARRAY_PTR(args));
	}
	else {
	    th->value = Qnil;
	}
	TH_POP_TAG();

	th->status = THREAD_KILLED;
	thread_debug("thread end: %p\n", th);
	st_delete_wrap(th->vm->living_threads, th->self);

	/* wake up joinning threads */
	join_th = th->join_list_head;
	while (join_th) {
	    rb_thread_interrupt(join_th);
	    join_th = join_th->join_list_next;
	}
	st_delete_wrap(th->vm->living_threads, th->self);
    }
    native_mutex_unlock(&th->vm->global_interpreter_lock);
    return 0;
}

VALUE yarv_thread_alloc(VALUE klass);

static VALUE
yarv_thread_s_new(VALUE klass, VALUE args)
{
    yarv_thread_t *th;
    VALUE thval;

    /* create thread object */
    thval = yarv_thread_alloc(cYarvThread);
    GetThreadPtr(thval, th);
    
    /* setup thread environment */
    th->first_args = args;
    th->first_proc = rb_block_proc();
    
    native_mutex_initialize(&th->interrupt_lock);

    /* kick thread */
    st_insert(th->vm->living_threads, thval, (st_data_t) th->thread_id);
    native_thread_create(th);
    return thval;
}

/* +infty, for this purpose */
#define DELAY_INFTY 1E30

VALUE th_make_jump_tag_but_local_jump(int state, VALUE val);

static VALUE
yarv_thread_join(yarv_thread_t *target_th, double delay)
{
    yarv_thread_t *th = GET_THREAD();
    double now, limit = timeofday() + delay;
    
    thread_debug("yarv_thread_join (thid: %p)\n", target_th->thread_id);

    if (target_th->status != THREAD_KILLED) {
	th->join_list_next = target_th->join_list_head;
	target_th->join_list_head = th;
    }

    while (target_th->status != THREAD_KILLED) {
	if (delay == DELAY_INFTY) {
	    sleep_forever(th);
	}
	else {
	    now = timeofday();
	    if (now > limit) {
		thread_debug("yarv_thread_join: timeout (thid: %p)\n",
			     target_th->thread_id);
		return Qnil;
	    }
	    sleep_wait_for_interrupt(th, limit - now);
	}
	thread_debug("yarv_thread_join: interrupted (thid: %p)\n",
		     target_th->thread_id);
    }

    thread_debug("yarv_thread_join: success (thid: %p)\n",
		 target_th->thread_id);

    if (target_th->errinfo != Qnil) {
	VALUE err = target_th->errinfo;

	if (FIXNUM_P(err)) {
	    /* */
	}
	else if (TYPE(target_th->errinfo) == T_NODE) {
	    rb_exc_raise(th_make_jump_tag_but_local_jump(
		GET_THROWOBJ_STATE(err), GET_THROWOBJ_VAL(err)));
	}
	else {
	    rb_exc_raise(err);
	}
    }
    return target_th->self;
}

/*
 *  call-seq:
 *     thr.join          => thr
 *     thr.join(limit)   => thr
 *  
 *  The calling thread will suspend execution and run <i>thr</i>. Does not
 *  return until <i>thr</i> exits or until <i>limit</i> seconds have passed. If
 *  the time limit expires, <code>nil</code> will be returned, otherwise
 *  <i>thr</i> is returned.
 *     
 *  Any threads not joined will be killed when the main program exits.  If
 *  <i>thr</i> had previously raised an exception and the
 *  <code>abort_on_exception</code> and <code>$DEBUG</code> flags are not set
 *  (so the exception has not yet been processed) it will be processed at this
 *  time.
 *     
 *     a = Thread.new { print "a"; sleep(10); print "b"; print "c" }
 *     x = Thread.new { print "x"; Thread.pass; print "y"; print "z" }
 *     x.join # Let x thread finish, a will be killed on exit.
 *     
 *  <em>produces:</em>
 *     
 *     axyz
 *     
 *  The following example illustrates the <i>limit</i> parameter.
 *     
 *     y = Thread.new { 4.times { sleep 0.1; puts 'tick... ' }}
 *     puts "Waiting" until y.join(0.15)
 *     
 *  <em>produces:</em>
 *     
 *     tick...
 *     Waiting
 *     tick...
 *     Waitingtick...
 *     
 *     
 *     tick...
 */

static VALUE
yarv_thread_join_m(int argc, VALUE *argv, VALUE self)
{
    yarv_thread_t *target_th;
    double delay = DELAY_INFTY;
    VALUE limit;
    
    GetThreadPtr(self, target_th);

    rb_scan_args(argc, argv, "01", &limit);
    if (!NIL_P(limit)) {
	delay = rb_num2dbl(limit);
    }
    return yarv_thread_join(target_th, delay);
}

/*
 *  call-seq:
 *     thr.value   => obj
 *  
 *  Waits for <i>thr</i> to complete (via <code>Thread#join</code>) and returns
 *  its value.
 *     
 *     a = Thread.new { 2 + 2 }
 *     a.value   #=> 4
 */

static VALUE
yarv_thread_value(VALUE self)
{
    yarv_thread_t *th;
    GetThreadPtr(self, th);
    yarv_thread_join(th, DELAY_INFTY);
    return th->value;
}

/*
 * Thread Scheduling
 */

static struct timeval
double2timeval(double d)
{
    struct timeval time;

    time.tv_sec = (int)d;
    time.tv_usec = (int)((d - (int)d) * 1e6);
    if (time.tv_usec < 0) {
	time.tv_usec += (long)1e6;
	time.tv_sec -= 1;
    }
    return time;
}

static void
sleep_forever(yarv_thread_t *th)
{
    native_sleep(th, 0);
    YARV_CHECK_INTS();
}

static void
sleep_timeval(yarv_thread_t *th, struct timeval tv)
{
    native_sleep(th, &tv);
}

void
rb_thread_sleep_forever()
{
    thread_debug("rb_thread_sleep_forever\n");
    sleep_forever(GET_THREAD());
}

static double
timeofday(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec * 1e-6;
}

static void
sleep_wait_for_interrupt(yarv_thread_t *th, double sleepsec)
{
    sleep_timeval(th, double2timeval(sleepsec));
}

static void
sleep_for_polling(yarv_thread_t *th)
{
    struct timeval time;
    time.tv_sec = 0;
    time.tv_usec = 100 * 1000;	/* 0.1 sec */
    sleep_timeval(th, time);
}

void
rb_thread_wait_for(struct timeval time)
{
    yarv_thread_t *th = GET_THREAD();
    sleep_timeval(th, time);
}

void
rb_thread_polling(void)
{
    if (!rb_thread_alone()) {
	yarv_thread_t *th = GET_THREAD();
	sleep_for_polling(th);
    }
}

struct timeval rb_time_timeval();

void
rb_thread_sleep(int sec)
{
    rb_thread_wait_for(rb_time_timeval(INT2FIX(sec)));
}

void
rb_thread_schedule()
{
    thread_debug("rb_thread_schedule\n");
    if (!rb_thread_alone()) {
	yarv_thread_t *th = GET_THREAD();

	thread_debug("rb_thread_schedule/switch start\n");

	yarv_save_machine_context(th);
	native_mutex_unlock(&th->vm->global_interpreter_lock);
	{
	    native_thread_yield();
	}
	native_mutex_lock(&th->vm->global_interpreter_lock);

	yarv_set_current_running_thread(th);
	thread_debug("rb_thread_schedule/switch done\n");

	YARV_CHECK_INTS();
    }
}


static VALUE
rb_thread_s_critical(VALUE self)
{
    rb_warn("Thread.critical is unsupported.  Use Mutex instead.");
    return Qnil;
}


VALUE
rb_thread_run_parallel(VALUE(*func)(yarv_thread_t *th, void *), void *data)
{
    VALUE val;
    yarv_thread_t *th = GET_THREAD();
    
    GVL_UNLOCK_RANGE({
	val = func(th, data);
    });
    
    return val;
}


/*
 *  call-seq:
 *     Thread.pass   => nil
 *  
 *  Invokes the thread scheduler to pass execution to another thread.
 *     
 *     a = Thread.new { print "a"; Thread.pass;
 *                      print "b"; Thread.pass;
 *                      print "c" }
 *     b = Thread.new { print "x"; Thread.pass;
 *                      print "y"; Thread.pass;
 *                      print "z" }
 *     a.join
 *     b.join
 *     
 *  <em>produces:</em>
 *     
 *     axbycz
 */

static VALUE
yarv_thread_s_pass(VALUE klass)
{
    rb_thread_schedule();
    return Qnil;
}

/*
 *
 */

void
yarv_thread_execute_interrupts(yarv_thread_t *th)
{
    while (th->interrupt_flag) {
	int status = th->status;
	th->status = THREAD_RUNNABLE;
	th->interrupt_flag = 0;

	/* signal handling */
	if (th->exec_signal) {
	    int sig = th->exec_signal;
	    th->exec_signal = 0;
	    rb_signal_exec(th, sig);
	}

	/* exception from another thread */
	if (th->throwed_errinfo) {
	    VALUE err = th->throwed_errinfo;
	    th->throwed_errinfo = 0;
	    thread_debug("yarv_thread_execute_interrupts: %p\n", err);

	    if (err == eKillSignal) {
		th->errinfo = INT2FIX(TAG_FATAL);
		TH_JUMP_TAG(th, TAG_FATAL);
	    }
	    else if (err == eTerminateSignal) {
		struct yarv_tag *tag = th->tag;

		/* rewind to toplevel stack */
		while (th->tag->prev) {
		    th->tag = th->tag->prev;
		}

		th->errinfo = INT2FIX(TAG_FATAL);
		TH_JUMP_TAG(th, TAG_FATAL);
	    }
	    else {
		rb_exc_raise(err);
	    }
	}
	th->status = status;

	/* thread pass */
	rb_thread_schedule();
    }
}


void
rb_gc_mark_threads()
{
    /* TODO: remove */
}

/*****************************************************/

static void
rb_thread_ready(yarv_thread_t *th)
{
    rb_thread_interrupt(th);
}

static VALUE
yarv_thread_raise(int argc, VALUE *argv, yarv_thread_t *th)
{
    VALUE exc;

    if (rb_thread_dead(th)) {
	return Qnil;
    }

    exc = rb_make_exception(argc, argv);
    /* TODO: need synchronization if run threads in parallel */
    th->throwed_errinfo = exc;
    rb_thread_ready(th);
    return Qnil;
}

void
rb_thread_signal_raise(void *thptr, const char *sig)
{
    VALUE argv[1];
    char buf[BUFSIZ];
    yarv_thread_t *th = thptr;
    
    if (sig == 0) {
	return;			/* should not happen */
    }
    snprintf(buf, BUFSIZ, "SIG%s", sig);
    argv[0] = rb_exc_new3(rb_eSignal, rb_str_new2(buf));
    yarv_thread_raise(1, argv, th->vm->main_thread);
}

void
rb_thread_signal_exit(void *thptr)
{
    VALUE argv[1];
    VALUE args[2];
    yarv_thread_t *th = thptr;
    
    args[0] = INT2NUM(EXIT_SUCCESS);
    args[1] = rb_str_new2("exit");
    argv[0] = rb_class_new_instance(2, args, rb_eSystemExit);
    yarv_thread_raise(1, argv, th->vm->main_thread);
}


/*
 *  call-seq:
 *     thr.raise(exception)
 *  
 *  Raises an exception (see <code>Kernel::raise</code>) from <i>thr</i>. The
 *  caller does not have to be <i>thr</i>.
 *     
 *     Thread.abort_on_exception = true
 *     a = Thread.new { sleep(200) }
 *     a.raise("Gotcha")
 *     
 *  <em>produces:</em>
 *     
 *     prog.rb:3: Gotcha (RuntimeError)
 *     	from prog.rb:2:in `initialize'
 *     	from prog.rb:2:in `new'
 *     	from prog.rb:2
 */

static VALUE
yarv_thread_raise_m(int argc, VALUE *argv, VALUE self)
{
    yarv_thread_t *th;
    GetThreadPtr(self, th);
    yarv_thread_raise(argc, argv, th);
    return Qnil;
}


/*
 *  call-seq:
 *     thr.exit        => thr or nil
 *     thr.kill        => thr or nil
 *     thr.terminate   => thr or nil
 *  
 *  Terminates <i>thr</i> and schedules another thread to be run. If this thread
 *  is already marked to be killed, <code>exit</code> returns the
 *  <code>Thread</code>. If this is the main thread, or the last thread, exits
 *  the process.
 */

VALUE
rb_thread_kill(VALUE thread)
{
    yarv_thread_t *th;

    GetThreadPtr(thread, th);

    if (th != GET_THREAD() && th->safe_level < 4) {
	rb_secure(4);
    }
    if (th->status == THREAD_TO_KILL || th->status == THREAD_KILLED) {
	return thread;
    }
    if (th == th->vm->main_thread) {
	rb_exit(EXIT_SUCCESS);
    }

    thread_debug("rb_thread_kill: %p (%p)\n", th, th->thread_id);

    rb_thread_interrupt(th);
    th->throwed_errinfo = eKillSignal;
    th->status = THREAD_TO_KILL;

    return thread;
}


/*
 *  call-seq:
 *     Thread.kill(thread)   => thread
 *  
 *  Causes the given <em>thread</em> to exit (see <code>Thread::exit</code>).
 *     
 *     count = 0
 *     a = Thread.new { loop { count += 1 } }
 *     sleep(0.1)       #=> 0
 *     Thread.kill(a)   #=> #<Thread:0x401b3d30 dead>
 *     count            #=> 93947
 *     a.alive?         #=> false
 */

static VALUE
rb_thread_s_kill(VALUE obj, VALUE th)
{
    return rb_thread_kill(th);
}


/*
 *  call-seq:
 *     Thread.exit   => thread
 *  
 *  Terminates the currently running thread and schedules another thread to be
 *  run. If this thread is already marked to be killed, <code>exit</code>
 *  returns the <code>Thread</code>. If this is the main thread, or the last
 *  thread, exit the process.
 */

static VALUE
rb_thread_exit()
{
    return rb_thread_kill(GET_THREAD()->self);
}


/*
 *  call-seq:
 *     thr.wakeup   => thr
 *  
 *  Marks <i>thr</i> as eligible for scheduling (it may still remain blocked on
 *  I/O, however). Does not invoke the scheduler (see <code>Thread#run</code>).
 *     
 *     c = Thread.new { Thread.stop; puts "hey!" }
 *     c.wakeup
 *     
 *  <em>produces:</em>
 *     
 *     hey!
 */

VALUE
rb_thread_wakeup(VALUE thread)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    if (th->status == THREAD_KILLED) {
	rb_raise(rb_eThreadError, "killed thread");
    }
    rb_thread_ready(th);
    return thread;
}


/*
 *  call-seq:
 *     thr.run   => thr
 *  
 *  Wakes up <i>thr</i>, making it eligible for scheduling. If not in a critical
 *  section, then invokes the scheduler.
 *     
 *     a = Thread.new { puts "a"; Thread.stop; puts "c" }
 *     Thread.pass
 *     puts "Got here"
 *     a.run
 *     a.join
 *     
 *  <em>produces:</em>
 *     
 *     a
 *     Got here
 *     c
 */

VALUE
rb_thread_run(thread)
    VALUE thread;
{
    rb_thread_wakeup(thread);
    rb_thread_schedule();
    return thread;
}


/*
 *  call-seq:
 *     Thread.stop   => nil
 *  
 *  Stops execution of the current thread, putting it into a ``sleep'' state,
 *  and schedules execution of another thread. Resets the ``critical'' condition
 *  to <code>false</code>.
 *     
 *     a = Thread.new { print "a"; Thread.stop; print "c" }
 *     Thread.pass
 *     print "b"
 *     a.run
 *     a.join
 *     
 *  <em>produces:</em>
 *     
 *     abc
 */

VALUE
rb_thread_stop(void)
{
    if (rb_thread_alone()) {
	rb_raise(rb_eThreadError,
		 "stopping only thread\n\tnote: use sleep to stop forever");
    }
    rb_thread_sleep_forever();
    return Qnil;
}

static int
thread_list_i(st_data_t key, st_data_t val, void *data)
{
    VALUE ary = (VALUE)data;
    yarv_thread_t *th;
    GetThreadPtr((VALUE)key, th);

    switch (th->status) {
    case THREAD_RUNNABLE:
    case THREAD_STOPPED:
    case THREAD_TO_KILL:
	rb_ary_push(ary, th->self);
    default:
	break;
    }
    return ST_CONTINUE;
}

/********************************************************************/

/*
 *  call-seq:
 *     Thread.list   => array
 *  
 *  Returns an array of <code>Thread</code> objects for all threads that are
 *  either runnable or stopped.
 *     
 *     Thread.new { sleep(200) }
 *     Thread.new { 1000000.times {|i| i*i } }
 *     Thread.new { Thread.stop }
 *     Thread.list.each {|t| p t}
 *     
 *  <em>produces:</em>
 *     
 *     #<Thread:0x401b3e84 sleep>
 *     #<Thread:0x401b3f38 run>
 *     #<Thread:0x401b3fb0 sleep>
 *     #<Thread:0x401bdf4c run>
 */

VALUE
rb_thread_list(void)
{
    VALUE ary = rb_ary_new();
    st_foreach(GET_THREAD()->vm->living_threads, thread_list_i, ary);
    return ary;
}

/*
 *  call-seq:
 *     Thread.current   => thread
 *  
 *  Returns the currently executing thread.
 *     
 *     Thread.current   #=> #<Thread:0x401bdf4c run>
 */

static VALUE
yarv_thread_s_current(VALUE klass)
{
    return GET_THREAD()->self;
}

VALUE
rb_thread_main(void)
{
    return GET_THREAD()->vm->main_thread->self;
}

static VALUE
rb_thread_s_main(VALUE klass)
{
    return rb_thread_main();
}


/*
 *  call-seq:
 *     Thread.abort_on_exception   => true or false
 *  
 *  Returns the status of the global ``abort on exception'' condition.  The
 *  default is <code>false</code>. When set to <code>true</code>, or if the
 *  global <code>$DEBUG</code> flag is <code>true</code> (perhaps because the
 *  command line option <code>-d</code> was specified) all threads will abort
 *  (the process will <code>exit(0)</code>) if an exception is raised in any
 *  thread. See also <code>Thread::abort_on_exception=</code>.
 */

static VALUE
rb_thread_s_abort_exc()
{
    return GET_THREAD()->vm->thread_abort_on_exception ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     Thread.abort_on_exception= boolean   => true or false
 *  
 *  When set to <code>true</code>, all threads will abort if an exception is
 *  raised. Returns the new state.
 *     
 *     Thread.abort_on_exception = true
 *     t1 = Thread.new do
 *       puts  "In new thread"
 *       raise "Exception from thread"
 *     end
 *     sleep(1)
 *     puts "not reached"
 *     
 *  <em>produces:</em>
 *     
 *     In new thread
 *     prog.rb:4: Exception from thread (RuntimeError)
 *     	from prog.rb:2:in `initialize'
 *     	from prog.rb:2:in `new'
 *     	from prog.rb:2
 */

static VALUE
rb_thread_s_abort_exc_set(VALUE self, VALUE val)
{
    rb_secure(4);
    GET_THREAD()->vm->thread_abort_on_exception = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     thr.abort_on_exception   => true or false
 *  
 *  Returns the status of the thread-local ``abort on exception'' condition for
 *  <i>thr</i>. The default is <code>false</code>. See also
 *  <code>Thread::abort_on_exception=</code>.
 */

static VALUE
rb_thread_abort_exc(VALUE thread)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);
    return th->abort_on_exception ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     thr.abort_on_exception= boolean   => true or false
 *  
 *  When set to <code>true</code>, causes all threads (including the main
 *  program) to abort if an exception is raised in <i>thr</i>. The process will
 *  effectively <code>exit(0)</code>.
 */

static VALUE
rb_thread_abort_exc_set(VALUE thread, VALUE val)
{
    yarv_thread_t *th;
    rb_secure(4);

    GetThreadPtr(thread, th);
    th->abort_on_exception = RTEST(val);
    return val;
}


/*
 *  call-seq:
 *     thr.group   => thgrp or nil
 *  
 *  Returns the <code>ThreadGroup</code> which contains <i>thr</i>, or nil if
 *  the thread is not a member of any group.
 *     
 *     Thread.main.group   #=> #<ThreadGroup:0x4029d914>
 */

VALUE
rb_thread_group(VALUE thread)
{
    yarv_thread_t *th;
    VALUE group;
    GetThreadPtr(thread, th);
    group = th->thgroup;

    if (!group) {
	group = Qnil;
    }
    return group;
}

static const char *
thread_status_name(enum yarv_thread_status status)
{
    switch (status) {
    case THREAD_RUNNABLE:
	return "run";
    case THREAD_STOPPED:
	return "sleep";
    case THREAD_TO_KILL:
	return "aborting";
    case THREAD_KILLED:
	return "dead";
    default:
	return "unknown";
    }
}

static int
rb_thread_dead(yarv_thread_t *th)
{
    return th->status == THREAD_KILLED;
}


/*
 *  call-seq:
 *     thr.status   => string, false or nil
 *  
 *  Returns the status of <i>thr</i>: ``<code>sleep</code>'' if <i>thr</i> is
 *  sleeping or waiting on I/O, ``<code>run</code>'' if <i>thr</i> is executing,
 *  ``<code>aborting</code>'' if <i>thr</i> is aborting, <code>false</code> if
 *  <i>thr</i> terminated normally, and <code>nil</code> if <i>thr</i>
 *  terminated with an exception.
 *     
 *     a = Thread.new { raise("die now") }
 *     b = Thread.new { Thread.stop }
 *     c = Thread.new { Thread.exit }
 *     d = Thread.new { sleep }
 *     Thread.critical = true
 *     d.kill                  #=> #<Thread:0x401b3678 aborting>
 *     a.status                #=> nil
 *     b.status                #=> "sleep"
 *     c.status                #=> false
 *     d.status                #=> "aborting"
 *     Thread.current.status   #=> "run"
 */

static VALUE
rb_thread_status(VALUE thread)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    if (rb_thread_dead(th)) {
	if (!NIL_P(th->errinfo) && !FIXNUM_P(th->errinfo)
	    /* TODO */ ) {
	    return Qnil;
	}
	return Qfalse;
    }
    return rb_str_new2(thread_status_name(th->status));
}


/*
 *  call-seq:
 *     thr.alive?   => true or false
 *  
 *  Returns <code>true</code> if <i>thr</i> is running or sleeping.
 *     
 *     thr = Thread.new { }
 *     thr.join                #=> #<Thread:0x401b3fb0 dead>
 *     Thread.current.alive?   #=> true
 *     thr.alive?              #=> false
 */

static VALUE
rb_thread_alive_p(VALUE thread)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    if (rb_thread_dead(th))
	return Qfalse;
    return Qtrue;
}

/*
 *  call-seq:
 *     thr.stop?   => true or false
 *  
 *  Returns <code>true</code> if <i>thr</i> is dead or sleeping.
 *     
 *     a = Thread.new { Thread.stop }
 *     b = Thread.current
 *     a.stop?   #=> true
 *     b.stop?   #=> false
 */

static VALUE
rb_thread_stop_p(VALUE thread)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    if (rb_thread_dead(th))
	return Qtrue;
    if (th->status == THREAD_STOPPED)
	return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     thr.safe_level   => integer
 *  
 *  Returns the safe level in effect for <i>thr</i>. Setting thread-local safe
 *  levels can help when implementing sandboxes which run insecure code.
 *     
 *     thr = Thread.new { $SAFE = 3; sleep }
 *     Thread.current.safe_level   #=> 0
 *     thr.safe_level              #=> 3
 */

static VALUE
rb_thread_safe_level(VALUE thread)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    return INT2NUM(th->safe_level);
}

/*
 * call-seq:
 *   thr.inspect   => string
 *
 * Dump the name, id, and status of _thr_ to a string.
 */

static VALUE
rb_thread_inspect(VALUE thread)
{
    char *cname = rb_obj_classname(thread);
    yarv_thread_t *th;
    const char *status;
    VALUE str;

    GetThreadPtr(thread, th);
    status = thread_status_name(th->status);
    str = rb_sprintf("#<%s:%p %s>", cname, (void *)thread, status);
    OBJ_INFECT(str, thread);

    return str;
}

VALUE
rb_thread_local_aref(VALUE thread, ID id)
{
    yarv_thread_t *th;
    VALUE val;

    GetThreadPtr(thread, th);
    if (rb_safe_level() >= 4 && th != GET_THREAD()) {
	rb_raise(rb_eSecurityError, "Insecure: thread locals");
    }
    if (!th->local_storage) {
	return Qnil;
    }
    if (st_lookup(th->local_storage, id, &val)) {
	return val;
    }
    return Qnil;
}

/*
 *  call-seq:
 *      thr[sym]   => obj or nil
 *  
 *  Attribute Reference---Returns the value of a thread-local variable, using
 *  either a symbol or a string name. If the specified variable does not exist,
 *  returns <code>nil</code>.
 *     
 *     a = Thread.new { Thread.current["name"] = "A"; Thread.stop }
 *     b = Thread.new { Thread.current[:name]  = "B"; Thread.stop }
 *     c = Thread.new { Thread.current["name"] = "C"; Thread.stop }
 *     Thread.list.each {|x| puts "#{x.inspect}: #{x[:name]}" }
 *     
 *  <em>produces:</em>
 *     
 *     #<Thread:0x401b3b3c sleep>: C
 *     #<Thread:0x401b3bc8 sleep>: B
 *     #<Thread:0x401b3c68 sleep>: A
 *     #<Thread:0x401bdf4c run>:
 */

static VALUE
rb_thread_aref(VALUE thread, VALUE id)
{
    return rb_thread_local_aref(thread, rb_to_id(id));
}

VALUE
rb_thread_local_aset(VALUE thread, ID id, VALUE val)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    if (rb_safe_level() >= 4 && th != GET_THREAD()) {
	rb_raise(rb_eSecurityError, "Insecure: can't modify thread locals");
    }
    if (OBJ_FROZEN(thread)) {
	rb_error_frozen("thread locals");
    }
    if (!th->local_storage) {
	th->local_storage = st_init_numtable();
    }
    if (NIL_P(val)) {
	st_delete(th->local_storage, (st_data_t *) & id, 0);
	return Qnil;
    }
    st_insert(th->local_storage, id, val);
    return val;
}

/*
 *  call-seq:
 *      thr[sym] = obj   => obj
 *  
 *  Attribute Assignment---Sets or creates the value of a thread-local variable,
 *  using either a symbol or a string. See also <code>Thread#[]</code>.
 */

static VALUE
rb_thread_aset(VALUE self, ID id, VALUE val)
{
    return rb_thread_local_aset(self, rb_to_id(id), val);
}

/*
 *  call-seq:
 *     thr.key?(sym)   => true or false
 *  
 *  Returns <code>true</code> if the given string (or symbol) exists as a
 *  thread-local variable.
 *     
 *     me = Thread.current
 *     me[:oliver] = "a"
 *     me.key?(:oliver)    #=> true
 *     me.key?(:stanley)   #=> false
 */

static VALUE
rb_thread_key_p(VALUE self, ID id)
{
    yarv_thread_t *th;
    GetThreadPtr(self, th);

    if (!th->local_storage) {
	return Qfalse;
    }
    if (st_lookup(th->local_storage, rb_to_id(id), 0)) {
	return Qtrue;
    }
    return Qfalse;
}

static int
thread_keys_i(ID key, VALUE value, VALUE ary)
{
    rb_ary_push(ary, ID2SYM(key));
    return ST_CONTINUE;
}

int
rb_thread_alone()
{
    int num = 1;
    if (GET_THREAD()->vm->living_threads) {
	num = GET_THREAD()->vm->living_threads->num_entries;
	thread_debug("rb_thread_alone: %d\n", num);
    }
    return num == 1;
}

/*
 *  call-seq:
 *     thr.keys   => array
 *  
 *  Returns an an array of the names of the thread-local variables (as Symbols).
 *     
 *     thr = Thread.new do
 *       Thread.current[:cat] = 'meow'
 *       Thread.current["dog"] = 'woof'
 *     end
 *     thr.join   #=> #<Thread:0x401b3f10 dead>
 *     thr.keys   #=> [:dog, :cat]
 */

static VALUE
rb_thread_keys(VALUE self)
{
    yarv_thread_t *th;
    VALUE ary = rb_ary_new();
    GetThreadPtr(self, th);

    if (th->local_storage) {
	st_foreach(th->local_storage, thread_keys_i, ary);
    }
    return ary;
}

/*
 *  call-seq:
 *     thr.priority   => integer
 *  
 *  Returns the priority of <i>thr</i>. Default is zero; higher-priority threads
 *  will run before lower-priority threads.
 *     
 *     Thread.current.priority   #=> 0
 */

static VALUE
rb_thread_priority(VALUE thread)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);
    return INT2NUM(th->priority);
}


/*
 *  call-seq:
 *     thr.priority= integer   => thr
 *  
 *  Sets the priority of <i>thr</i> to <i>integer</i>. Higher-priority threads
 *  will run before lower-priority threads.
 *     
 *     count1 = count2 = 0
 *     a = Thread.new do
 *           loop { count1 += 1 }
 *         end
 *     a.priority = -1
 *     
 *     b = Thread.new do
 *           loop { count2 += 1 }
 *         end
 *     b.priority = -2
 *     sleep 1   #=> 1
 *     Thread.critical = 1
 *     count1    #=> 622504
 *     count2    #=> 5832
 */

static VALUE
rb_thread_priority_set(VALUE thread, VALUE prio)
{
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    rb_secure(4);

    th->priority = NUM2INT(prio);
    native_thread_apply_priority(th);
    return prio;
}

/* for IO */

void
rb_thread_wait_fd(int fd)
{
    fd_set set;
    int result = 0;

    FD_ZERO(&set);
    FD_SET(fd, &set);
    thread_debug("rb_thread_wait_fd (%d)\n", fd);
    while (result <= 0) {
	GVL_UNLOCK_RANGE(result = select(fd + 1, &set, 0, 0, 0));
    }
    thread_debug("rb_thread_wait_fd done\n", fd);
}

int
rb_thread_fd_writable(int fd)
{
    fd_set set;
    int result = 0;

    FD_ZERO(&set);
    FD_SET(fd, &set);

    thread_debug("rb_thread_fd_writable (%d)\n", fd);
    while (result <= 0) {
	GVL_UNLOCK_RANGE(result = select(fd + 1, 0, &set, 0, 0));
    }
    thread_debug("rb_thread_fd_writable done\n");
    return Qtrue;
}

int
rb_thread_select(int max, fd_set * read, fd_set * write, fd_set * except,
		 struct timeval *timeout)
{
    struct timeval *tvp = timeout;
    int lerrno, n;
#ifndef linux
    double limit;
    struct timeval tv;
#endif

    if (!read && !write && !except) {
	if (!timeout) {
	    rb_thread_sleep_forever();
	    return 0;
	}
	rb_thread_wait_for(*timeout);
	return 0;
    }

#ifndef linux
    if (timeout) {
	limit = timeofday() +
	    (double)timeout->tv_sec + (double)timeout->tv_usec * 1e-6;
    }
#endif

#ifndef linux
    if (timeout) {
	tv = *timeout;
	tvp = &tv;
    }
#else
    tvp = timeout;
#endif

    for (;;) {
	GVL_UNLOCK_RANGE(n = select(max, read, write, except, tvp);
			 lerrno = errno;
	    );

	if (n < 0) {
	    switch (errno) {
	    case EINTR:
#ifdef ERESTART
	    case ERESTART:
#endif

#ifndef linux
		if (timeout) {
		    double d = limit - timeofday();
		    tv = double2timeval(d);
		}
#endif
		continue;
	    default:
		break;
	    }
	}
	return n;
    }
}


/*
 * for GC
 */

void
yarv_set_stack_end(VALUE **stack_end_p)
{
    VALUE stack_end;
    *stack_end_p = &stack_end;
}

void
yarv_save_machine_context(yarv_thread_t *th)
{
    yarv_set_stack_end(&th->machine_stack_end);
    setjmp(th->machine_regs);
}

/*
 *
 */

int rb_get_next_signal(yarv_vm_t *vm);

static void
timer_thread_function(void)
{
    yarv_vm_t *vm = GET_VM(); /* TODO: fix me for Multi-VM */
    vm->running_thread->interrupt_flag = 1;
    
    if (vm->bufferd_signal_size && vm->main_thread->exec_signal == 0) {
	vm->main_thread->exec_signal = rb_get_next_signal(vm);
	thread_debug("bufferd_signal_size: %d, sig: %d\n",
		     vm->bufferd_signal_size, vm->main_thread->exec_signal);
	rb_thread_interrupt(vm->main_thread);
    }
}

void
rb_thread_stop_timer_thread(void)
{
    if (timer_thread_id) {
	system_working = 0;
	native_thread_join(timer_thread_id);
    }
}

void
rb_thread_reset_timer_thread(void)
{
    timer_thread_id = 0;
}

void
rb_thread_start_timer_thread(void)
{
    rb_thread_create_timer_thread();
}

/***/

void
rb_thread_atfork(void)
{
    yarv_thread_t *th = GET_THREAD();
    yarv_vm_t *vm = th->vm;
    vm->main_thread = th;

    st_free_table(vm->living_threads);
    vm->living_threads = st_init_numtable();
    st_insert(vm->living_threads, th->self, (st_data_t) th->thread_id);
}

/*
 * for tests
 */

static VALUE
raw_gets(VALUE klass)
{
    char buff[100];
    GVL_UNLOCK_BEGIN();
    {
	fgets(buff, 100, stdin);
    }
    GVL_UNLOCK_END();
    return rb_str_new2(buff);
}


struct thgroup {
    int enclosed;
    VALUE group;
};

/*
 * Document-class: ThreadGroup
 *
 *  <code>ThreadGroup</code> provides a means of keeping track of a number of
 *  threads as a group. A <code>Thread</code> can belong to only one
 *  <code>ThreadGroup</code> at a time; adding a thread to a new group will
 *  remove it from any previous group.
 *     
 *  Newly created threads belong to the same group as the thread from which they
 *  were created.
 */

static VALUE thgroup_s_alloc _((VALUE));
static VALUE
thgroup_s_alloc(VALUE klass)
{
    VALUE group;
    struct thgroup *data;

    group = Data_Make_Struct(klass, struct thgroup, 0, free, data);
    data->enclosed = 0;
    data->group = group;

    return group;
}

struct thgroup_list_params {
    VALUE ary;
    VALUE group;
};

static int
thgroup_list_i(st_data_t key, st_data_t val, st_data_t data)
{
    VALUE thread = (VALUE)key;
    VALUE ary = ((struct thgroup_list_params *)data)->ary;
    VALUE group = ((struct thgroup_list_params *)data)->group;
    yarv_thread_t *th;
    GetThreadPtr(thread, th);

    if (th->thgroup == group) {
	rb_ary_push(ary, thread);
    }
    return ST_CONTINUE;
}

/*
 *  call-seq:
 *     thgrp.list   => array
 *  
 *  Returns an array of all existing <code>Thread</code> objects that belong to
 *  this group.
 *     
 *     ThreadGroup::Default.list   #=> [#<Thread:0x401bdf4c run>]
 */

static VALUE
thgroup_list(VALUE group)
{
    VALUE ary = rb_ary_new();
    struct thgroup_list_params param = {
	ary, group,
    };
    st_foreach(GET_THREAD()->vm->living_threads, thgroup_list_i, (st_data_t) & param);
    return ary;
}


/*
 *  call-seq:
 *     thgrp.enclose   => thgrp
 *  
 *  Prevents threads from being added to or removed from the receiving
 *  <code>ThreadGroup</code>. New threads can still be started in an enclosed
 *  <code>ThreadGroup</code>.
 *     
 *     ThreadGroup::Default.enclose        #=> #<ThreadGroup:0x4029d914>
 *     thr = Thread::new { Thread.stop }   #=> #<Thread:0x402a7210 sleep>
 *     tg = ThreadGroup::new               #=> #<ThreadGroup:0x402752d4>
 *     tg.add thr
 *
 *  <em>produces:</em>
 *
 *     ThreadError: can't move from the enclosed thread group
 */

VALUE
thgroup_enclose(group)
    VALUE group;
{
    struct thgroup *data;

    Data_Get_Struct(group, struct thgroup, data);
    data->enclosed = 1;

    return group;
}


/*
 *  call-seq:
 *     thgrp.enclosed?   => true or false
 *  
 *  Returns <code>true</code> if <em>thgrp</em> is enclosed. See also
 *  ThreadGroup#enclose.
 */

static VALUE
thgroup_enclosed_p(VALUE group)
{
    struct thgroup *data;

    Data_Get_Struct(group, struct thgroup, data);
    if (data->enclosed)
	return Qtrue;
    return Qfalse;
}


/*
 *  call-seq:
 *     thgrp.add(thread)   => thgrp
 *  
 *  Adds the given <em>thread</em> to this group, removing it from any other
 *  group to which it may have previously belonged.
 *     
 *     puts "Initial group is #{ThreadGroup::Default.list}"
 *     tg = ThreadGroup.new
 *     t1 = Thread.new { sleep }
 *     t2 = Thread.new { sleep }
 *     puts "t1 is #{t1}"
 *     puts "t2 is #{t2}"
 *     tg.add(t1)
 *     puts "Initial group now #{ThreadGroup::Default.list}"
 *     puts "tg group now #{tg.list}"
 *     
 *  <em>produces:</em>
 *     
 *     Initial group is #<Thread:0x401bdf4c>
 *     t1 is #<Thread:0x401b3c90>
 *     t2 is #<Thread:0x401b3c18>
 *     Initial group now #<Thread:0x401b3c18>#<Thread:0x401bdf4c>
 *     tg group now #<Thread:0x401b3c90>
 */

static VALUE
thgroup_add(VALUE group, VALUE thread)
{
    yarv_thread_t *th;
    struct thgroup *data;

    rb_secure(4);
    GetThreadPtr(thread, th);

    if (OBJ_FROZEN(group)) {
	rb_raise(rb_eThreadError, "can't move to the frozen thread group");
    }
    Data_Get_Struct(group, struct thgroup, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError, "can't move to the enclosed thread group");
    }

    if (!th->thgroup) {
	return Qnil;
    }

    if (OBJ_FROZEN(th->thgroup)) {
	rb_raise(rb_eThreadError, "can't move from the frozen thread group");
    }
    Data_Get_Struct(th->thgroup, struct thgroup, data);
    if (data->enclosed) {
	rb_raise(rb_eThreadError,
		 "can't move from the enclosed thread group");
    }

    th->thgroup = group;
    return group;
}

/*
  Mutex
 */

typedef struct mutex_struct {
    yarv_thread_t *th;
    yarv_thread_lock_t lock;
} mutex_t;

#define GetMutexVal(obj, tobj) \
  Data_Get_Struct(obj, mutex_t, tobj)

static void
mutex_mark(void *ptr)
{
    if (ptr) {
	mutex_t *mutex = ptr;
	if (mutex->th) {
	    rb_gc_mark(mutex->th->self);
	}
    }
}

static void
mutex_free(void *ptr)
{
    if (ptr) {
	mutex_t *mutex = ptr;
	if (mutex->th) {
	    native_mutex_unlock(&mutex->lock);
	}
    }
    ruby_xfree(ptr);
}

static VALUE
mutex_alloc(VALUE klass)
{
    VALUE volatile obj;
    mutex_t *mutex;

    obj = Data_Make_Struct(klass, mutex_t, mutex_mark, mutex_free, mutex);
    mutex->th = 0;
    native_mutex_initialize(&mutex->lock);
    return obj;
}

static VALUE
mutex_initialize(VALUE self)
{
    return self;
}

static VALUE
mutex_locked_p(VALUE self)
{
    mutex_t *mutex;
    GetMutexVal(self, mutex);
    return mutex->th ? Qtrue : Qfalse;
}

static VALUE
mutex_try_lock(VALUE self)
{
    mutex_t *mutex;
    GetMutexVal(self, mutex);

    if (native_mutex_trylock(&mutex->lock) != EBUSY) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}

static VALUE
mutex_lock(VALUE self)
{
    mutex_t *mutex;
    GetMutexVal(self, mutex);

    if (mutex->th == GET_THREAD()) {
	rb_raise(rb_eThreadError, "deadlock; recursive locking");
    }

    if (native_mutex_trylock(&mutex->lock) != 0) {
	/* can't cancel */
	GVL_UNLOCK_BEGIN();
	native_mutex_lock(&mutex->lock);
	GVL_UNLOCK_END();
    }

    mutex->th = GET_THREAD();
    return self;
}

static VALUE
mutex_unlock(VALUE self)
{
    mutex_t *mutex;
    GetMutexVal(self, mutex);

    if (mutex->th != GET_THREAD()) {
	rb_raise(rb_eThreadError,
		 "Attempt to unlock a mutex which is locked by another thread");
    }
    mutex->th = 0;
    native_mutex_unlock(&mutex->lock);
    return self;
}

static VALUE
mutex_sleep(int argc, VALUE *argv, VALUE self)
{
    int beg, end;
    mutex_unlock(self);

    beg = time(0);
    if (argc == 0) {
	rb_thread_sleep_forever();
    }
    else if (argc == 1) {
	rb_thread_wait_for(rb_time_interval(argv[0]));
    }
    else {
	rb_raise(rb_eArgError, "wrong number of arguments");
    }
    mutex_lock(self);
    end = time(0) - beg;
    return INT2FIX(end);
}


void
Init_yarvthread()
{
    VALUE cThGroup;
    VALUE thgroup_default;
    VALUE cMutex;

    rb_define_global_function("raw_gets", raw_gets, 0);

    rb_define_singleton_method(cYarvThread, "new", yarv_thread_s_new, -2);
    rb_define_singleton_method(cYarvThread, "start", yarv_thread_s_new, -2);
    rb_define_singleton_method(cYarvThread, "fork", yarv_thread_s_new, -2);
    rb_define_singleton_method(cYarvThread, "main", rb_thread_s_main, 0);
    rb_define_singleton_method(cYarvThread, "current", yarv_thread_s_current, 0);
    rb_define_singleton_method(cYarvThread, "stop", rb_thread_stop, 0);
    rb_define_singleton_method(cYarvThread, "kill", rb_thread_s_kill, 1);
    rb_define_singleton_method(cYarvThread, "exit", rb_thread_exit, 0);
    rb_define_singleton_method(cYarvThread, "pass", yarv_thread_s_pass, 0);
    rb_define_singleton_method(cYarvThread, "list", rb_thread_list, 0);
    rb_define_singleton_method(cYarvThread, "critical", rb_thread_s_critical, 0);
    rb_define_singleton_method(cYarvThread, "critical=", rb_thread_s_critical, 1);
    rb_define_singleton_method(cYarvThread, "abort_on_exception", rb_thread_s_abort_exc, 0);
    rb_define_singleton_method(cYarvThread, "abort_on_exception=", rb_thread_s_abort_exc_set, 1);

    rb_define_method(cYarvThread, "raise", yarv_thread_raise_m, -1);
    rb_define_method(cYarvThread, "join", yarv_thread_join_m, -1);
    rb_define_method(cYarvThread, "value", yarv_thread_value, 0);
    rb_define_method(cYarvThread, "kill", rb_thread_kill, 0);
    rb_define_method(cYarvThread, "terminate", rb_thread_kill, 0);
    rb_define_method(cYarvThread, "exit", rb_thread_kill, 0);
    rb_define_method(cYarvThread, "run", rb_thread_run, 0);
    rb_define_method(cYarvThread, "wakeup", rb_thread_wakeup, 0);
    rb_define_method(cYarvThread, "[]", rb_thread_aref, 1);
    rb_define_method(cYarvThread, "[]=", rb_thread_aset, 2);
    rb_define_method(cYarvThread, "key?", rb_thread_key_p, 1);
    rb_define_method(cYarvThread, "keys", rb_thread_keys, 0);
    rb_define_method(cYarvThread, "priority", rb_thread_priority, 0);
    rb_define_method(cYarvThread, "priority=", rb_thread_priority_set, 1);
    rb_define_method(cYarvThread, "status", rb_thread_status, 0);
    rb_define_method(cYarvThread, "alive?", rb_thread_alive_p, 0);
    rb_define_method(cYarvThread, "stop?", rb_thread_stop_p, 0);
    rb_define_method(cYarvThread, "abort_on_exception", rb_thread_abort_exc, 0);
    rb_define_method(cYarvThread, "abort_on_exception=", rb_thread_abort_exc_set, 1);
    rb_define_method(cYarvThread, "safe_level", rb_thread_safe_level, 0);
    rb_define_method(cYarvThread, "group", rb_thread_group, 0);

    rb_define_method(cYarvThread, "inspect", rb_thread_inspect, 0);

    cThGroup = rb_define_class("ThreadGroup", rb_cObject);
    rb_define_alloc_func(cThGroup, thgroup_s_alloc);
    rb_define_method(cThGroup, "list", thgroup_list, 0);
    rb_define_method(cThGroup, "enclose", thgroup_enclose, 0);
    rb_define_method(cThGroup, "enclosed?", thgroup_enclosed_p, 0);
    rb_define_method(cThGroup, "add", thgroup_add, 1);
    GET_THREAD()->vm->thgroup_default = thgroup_default = rb_obj_alloc(cThGroup);
    rb_define_const(cThGroup, "Default", thgroup_default);

    cMutex = rb_define_class("Mutex", rb_cObject);
    rb_define_alloc_func(cMutex, mutex_alloc);
    rb_define_method(cMutex, "initialize", mutex_initialize, 0);
    rb_define_method(cMutex, "locked?", mutex_locked_p, 0);
    rb_define_method(cMutex, "try_lock", mutex_try_lock, 0);
    rb_define_method(cMutex, "lock", mutex_lock, 0);
    rb_define_method(cMutex, "unlock", mutex_unlock, 0);
    rb_define_method(cMutex, "sleep", mutex_sleep, -1);
    yarvcore_eval(Qnil, rb_str_new2(
	"class Mutex;"
	"  def synchronize; self.lock; yield; ensure; self.unlock; end;"
	"end;") , rb_str_new2("<preload>"), INT2FIX(1));
    Init_native_thread();
    {
	/* main thread setting */
	{
	    /* acquire global interpreter lock */
	    yarv_thread_lock_t *lp = &GET_THREAD()->vm->global_interpreter_lock;
	    native_mutex_initialize(lp);
	    native_mutex_lock(lp);
	    native_mutex_initialize(&GET_THREAD()->interrupt_lock);
	}
    }

    rb_thread_create_timer_thread();
}

