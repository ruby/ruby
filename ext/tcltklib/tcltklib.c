/*
 *      tcltklib.c
 *              Aug. 27, 1997   Y. Shigehiro
 *              Oct. 24, 1997   Y. Matsumoto
 */

#define TCLTKLIB_RELEASE_DATE "2004-12-23"

#include "ruby.h"
#include "rubysig.h"
#include "version.h"
#undef EXTERN   /* avoid conflict with tcl.h of tcl8.2 or before */
#include <stdio.h>
#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif
#include <string.h>
#include <tcl.h>
#include <tk.h>

#ifdef __MACOS__
# include <tkMac.h>
# include <Quickdraw.h>
#endif

#if TCL_MAJOR_VERSION >= 8
# ifndef CONST84
#  if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION <= 4 /* Tcl8.0.x -- 8.4b1 */
#   define CONST84
#  else /* unknown (maybe TCL_VERSION >= 8.5) */
#   ifdef CONST
#    define CONST84 CONST
#   else
#    define CONST84
#   endif
#  endif
# endif
#else  /* TCL_MAJOR_VERSION < 8 */
# ifdef CONST
#  define CONST84 CONST
# else
#  define CONST
#  define CONST84
# endif
#endif

/* copied from eval.c */
#define TAG_RETURN      0x1
#define TAG_BREAK       0x2
#define TAG_NEXT        0x3
#define TAG_RETRY       0x4
#define TAG_REDO        0x5
#define TAG_RAISE       0x6
#define TAG_THROW       0x7
#define TAG_FATAL       0x8

/* for ruby_debug */
#define DUMP1(ARG1) if (ruby_debug) { fprintf(stderr, "tcltklib: %s\n", ARG1); fflush(stderr); }
#define DUMP2(ARG1, ARG2) if (ruby_debug) { fprintf(stderr, "tcltklib: ");\
fprintf(stderr, ARG1, ARG2); fprintf(stderr, "\n"); fflush(stderr); }
/*
#define DUMP1(ARG1)
#define DUMP2(ARG1, ARG2)
*/

/* release date */
const char tcltklib_release_date[] = TCLTKLIB_RELEASE_DATE;

/*finalize_proc_name */
static char *finalize_hook_name = "INTERP_FINALIZE_HOOK";

/* for callback break & continue */
static VALUE eTkCallbackReturn;
static VALUE eTkCallbackBreak;
static VALUE eTkCallbackContinue;

static VALUE eLocalJumpError;

static ID ID_at_enc;
static ID ID_at_interp;

static ID ID_stop_p;
static ID ID_kill;
static ID ID_join;

static ID ID_call;
static ID ID_backtrace;
static ID ID_message;

static ID ID_at_reason;
static ID ID_return;
static ID ID_break;
static ID ID_next;

static ID ID_to_s;
static ID ID_inspect;

static VALUE ip_invoke_real _((int, VALUE*, VALUE));
static VALUE ip_invoke _((int, VALUE*, VALUE));

/* from tkAppInit.c */

#if TCL_MAJOR_VERSION < 8 || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION < 4)
#  if !defined __MINGW32__ && !defined __BORLANDC__
/*
 * The following variable is a special hack that is needed in order for
 * Sun shared libraries to be used for Tcl.
 */

extern int matherr();
int *tclDummyMathPtr = (int *) matherr;
#  endif
#endif

/*---- module TclTkLib ----*/

struct invoke_queue {
    Tcl_Event ev;
    int argc;
#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **argv;
#else /* TCL_MAJOR_VERSION < 8 */
    char **argv;
#endif
    VALUE interp;
    int *done;
    int safe_level;
    VALUE result;
    VALUE thread;
};

struct eval_queue {
    Tcl_Event ev;
    char *str;
    int len;
    VALUE interp;
    int *done;
    int safe_level;
    VALUE result;
    VALUE thread;
};

void 
invoke_queue_mark(struct invoke_queue *q)
{
    rb_gc_mark(q->interp);
    rb_gc_mark(q->result);
    rb_gc_mark(q->thread);
}

void 
eval_queue_mark(struct eval_queue *q)
{
    rb_gc_mark(q->interp);
    rb_gc_mark(q->result);
    rb_gc_mark(q->thread);
}

 
static VALUE eventloop_thread;
static VALUE watchdog_thread;
Tcl_Interp  *current_interp;

/* 
 *  'event_loop_max' is a maximum events which the eventloop processes in one 
 *  term of thread scheduling. 'no_event_tick' is the count-up value when 
 *  there are no event for processing. 
 *  'timer_tick' is a limit of one term of thread scheduling. 
 *  If 'timer_tick' == 0, then not use the timer for thread scheduling.
 */
#define DEFAULT_EVENT_LOOP_MAX    800/*counts*/
#define DEFAULT_NO_EVENT_TICK      10/*counts*/
#define DEFAULT_NO_EVENT_WAIT      20/*milliseconds ( 1 -- 999 ) */
#define WATCHDOG_INTERVAL          10/*milliseconds ( 1 -- 999 ) */
#define DEFAULT_TIMER_TICK          0/*milliseconds ( 0 -- 999 ) */
#define NO_THREAD_INTERRUPT_TIME  100/*milliseconds ( 1 -- 999 ) */

static int event_loop_max = DEFAULT_EVENT_LOOP_MAX;
static int no_event_tick  = DEFAULT_NO_EVENT_TICK;
static int no_event_wait  = DEFAULT_NO_EVENT_WAIT;
static int timer_tick     = DEFAULT_TIMER_TICK;
static int req_timer_tick = DEFAULT_TIMER_TICK;
static int run_timer_flag = 0;

static int event_loop_wait_event   = 0;
static int event_loop_abort_on_exc = 1;
static int loop_counter = 0;

static int check_rootwidget_flag = 0;

#if TCL_MAJOR_VERSION >= 8
static int ip_ruby_eval _((ClientData, Tcl_Interp *, int, Tcl_Obj *CONST*));
static int ip_ruby_cmd _((ClientData, Tcl_Interp *, int, Tcl_Obj *CONST*));
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_ruby_eval _((ClientData, Tcl_Interp *, int, char **));
static int ip_ruby_cmd _((ClientData, Tcl_Interp *, int, char **));
#endif

/*---- class TclTkIp ----*/
struct tcltkip {
    Tcl_Interp *ip;             /* the interpreter */
    int has_orig_exit;          /* has original 'exit' command ? */
    Tcl_CmdInfo orig_exit_info; /* command info of original 'exit' command */
    int ref_count;              /* reference count of rbtk_preserve_ip call */
    int allow_ruby_exit;        /* allow exiting ruby by 'exit' function */
    int return_value;           /* return value */
};

static struct tcltkip *
get_ip(self)
    VALUE self;
{
    struct tcltkip *ptr;

    Data_Get_Struct(self, struct tcltkip, ptr);
    if (ptr == 0) {
        rb_raise(rb_eTypeError, "uninitialized TclTkIp");
    }
    return ptr;
}

/* increment/decrement reference count of tcltkip */
static int
rbtk_preserve_ip(ptr)
    struct tcltkip *ptr;
{
    ptr->ref_count++;
    Tcl_Preserve((ClientData)ptr->ip);
    return(ptr->ref_count);
}

static int
rbtk_release_ip(ptr)
    struct tcltkip *ptr;
{
    ptr->ref_count--;
    if (ptr->ref_count < 0) {
        ptr->ref_count = 0;
    } else {
        Tcl_Release((ClientData)ptr->ip);
    }
    return(ptr->ref_count);
}

/* call original 'exit' command */
static void 
call_original_exit(ptr, state)
    struct tcltkip *ptr;
    int state;
{
    int  thr_crit_bup;
    Tcl_CmdInfo *info;
#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj *state_obj;
#endif

    if (!(ptr->has_orig_exit)) return;

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    Tcl_ResetResult(ptr->ip);

    info = &(ptr->orig_exit_info);

    /* memory allocation for arguments of this command */
#if TCL_MAJOR_VERSION >= 8
    state_obj = Tcl_NewIntObj(state);
    Tcl_IncrRefCount(state_obj);

    if (info->isNativeObjectProc) {
        Tcl_Obj **argv;
        argv = (Tcl_Obj **)ALLOC_N(Tcl_Obj *, 3);
        argv[0] = Tcl_NewStringObj("exit", 4);
        argv[1] = state_obj;
        argv[2] = (Tcl_Obj *)NULL;

        ptr->return_value 
            = (*(info->objProc))(info->objClientData, ptr->ip, 2, argv);

        free(argv);

    } else {
        /* string interface */
        char **argv;
        argv = (char **)ALLOC_N(char *, 3);
        argv[0] = "exit";
        argv[1] = Tcl_GetString(state_obj);
        argv[2] = (char *)NULL;

        ptr->return_value = (*(info->proc))(info->clientData, ptr->ip, 
                                            2, (CONST84 char **)argv);

        free(argv);
    }

    Tcl_DecrRefCount(state_obj);

#else /* TCL_MAJOR_VERSION < 8 */
    {
        /* string interface */
        char **argv;
        argv = (char **)ALLOC_N(char *, 3);
        argv[0] = "exit";
        argv[1] = RSTRING(rb_fix2str(INT2NUM(state), 10))->ptr;
        argv[2] = (char *)NULL;

        ptr->return_value = (*(info->proc))(info->clientData, ptr->ip, 
                                            2, argv);

        free(argv);
    }
#endif

    rb_thread_critical = thr_crit_bup;
}

/* Tk_ThreadTimer */
static Tcl_TimerToken timer_token = (Tcl_TimerToken)NULL;

/* timer callback */
static void _timer_for_tcl _((ClientData));
static void
_timer_for_tcl(clientData)
    ClientData clientData;
{
    int thr_crit_bup;

    /* struct invoke_queue *q, *tmp; */
    /* VALUE thread; */

    DUMP1("called timer_for_tcl");

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    Tk_DeleteTimerHandler(timer_token);

    run_timer_flag = 1;

    if (timer_tick > 0) {
        timer_token = Tk_CreateTimerHandler(timer_tick, _timer_for_tcl, 
                                            (ClientData)0);
    } else {
        timer_token = (Tcl_TimerToken)NULL;
    }

    rb_thread_critical = thr_crit_bup;

    /* rb_thread_schedule(); */
    /* tick_counter += event_loop_max; */
}

static VALUE
set_eventloop_tick(self, tick)
    VALUE self;
    VALUE tick;
{
    int ttick = NUM2INT(tick);
    int thr_crit_bup;

    rb_secure(4);

    if (ttick < 0) {
        rb_raise(rb_eArgError, 
                 "timer-tick parameter must be 0 or positive number");
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* delete old timer callback */
    Tk_DeleteTimerHandler(timer_token);

    timer_tick = req_timer_tick = ttick;
    if (timer_tick > 0) {
        /* start timer callback */
        timer_token = Tk_CreateTimerHandler(timer_tick, _timer_for_tcl, 
                                            (ClientData)0);
    } else {
        timer_token = (Tcl_TimerToken)NULL;
    }

    rb_thread_critical = thr_crit_bup;

    return tick;
}

static VALUE
get_eventloop_tick(self)
    VALUE self;
{
    return INT2NUM(timer_tick);
}

static VALUE
ip_set_eventloop_tick(self, tick)
    VALUE self;
    VALUE tick;
{
    struct tcltkip *ptr = get_ip(self);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return get_eventloop_tick(self);
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return get_eventloop_tick(self);
    }
    return set_eventloop_tick(self, tick);
}

static VALUE
ip_get_eventloop_tick(self)
    VALUE self;
{
    return get_eventloop_tick(self);
}

static VALUE
set_no_event_wait(self, wait)
    VALUE self;
    VALUE wait;
{
    int t_wait = NUM2INT(wait);

    rb_secure(4);

    if (t_wait <= 0) {
        rb_raise(rb_eArgError, 
                 "no_event_wait parameter must be positive number");
    }

    no_event_wait = t_wait;

    return wait;
}

static VALUE
get_no_event_wait(self)
    VALUE self;
{
    return INT2NUM(no_event_wait);
}

static VALUE
ip_set_no_event_wait(self, wait)
    VALUE self;
    VALUE wait;
{
    struct tcltkip *ptr = get_ip(self);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return get_no_event_wait(self);
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return get_no_event_wait(self);
    }
    return set_no_event_wait(self, wait);
}

static VALUE
ip_get_no_event_wait(self)
    VALUE self;
{
    return get_no_event_wait(self);
}

static VALUE
set_eventloop_weight(self, loop_max, no_event)
    VALUE self;
    VALUE loop_max;
    VALUE no_event;
{
    int lpmax = NUM2INT(loop_max);
    int no_ev = NUM2INT(no_event);

    rb_secure(4);

    if (lpmax <= 0 || no_ev <= 0) {
        rb_raise(rb_eArgError, "weight parameters must be positive numbers");
    }

    event_loop_max = lpmax;
    no_event_tick  = no_ev;

    return rb_ary_new3(2, loop_max, no_event);
}

static VALUE
get_eventloop_weight(self)
    VALUE self;
{
    return rb_ary_new3(2, INT2NUM(event_loop_max), INT2NUM(no_event_tick));
}

static VALUE
ip_set_eventloop_weight(self, loop_max, no_event)
    VALUE self;
    VALUE loop_max;
    VALUE no_event;
{
    struct tcltkip *ptr = get_ip(self);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return get_eventloop_weight(self);
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return get_eventloop_weight(self);
    }
    return set_eventloop_weight(self, loop_max, no_event);
}

static VALUE
ip_get_eventloop_weight(self)
    VALUE self;
{
    return get_eventloop_weight(self);
}

static VALUE
set_max_block_time(self, time)
    VALUE self;
    VALUE time;
{
    struct Tcl_Time tcl_time;
    VALUE divmod;

    switch(TYPE(time)) {
    case T_FIXNUM:
    case T_BIGNUM:
        /* time is micro-second value */
        divmod = rb_funcall(time, rb_intern("divmod"), 1, LONG2NUM(1000000));
        tcl_time.sec  = NUM2LONG(RARRAY(divmod)->ptr[0]);
        tcl_time.usec = NUM2LONG(RARRAY(divmod)->ptr[1]);
        break;

    case T_FLOAT:
        /* time is second value */
        divmod = rb_funcall(time, rb_intern("divmod"), 1, INT2FIX(1));
        tcl_time.sec  = NUM2LONG(RARRAY(divmod)->ptr[0]);
        tcl_time.usec = (long)(NUM2DBL(RARRAY(divmod)->ptr[1]) * 1000000);

    default:
        rb_raise(rb_eArgError, "invalid value for time: '%s'", 
                 RSTRING(rb_funcall(time, ID_inspect, 0, 0))->ptr);
    }

    Tcl_SetMaxBlockTime(&tcl_time);

    return Qnil;
}

static VALUE
lib_evloop_abort_on_exc(self)
    VALUE self;
{
    if (event_loop_abort_on_exc > 0) {
        return Qtrue;
    } else if (event_loop_abort_on_exc == 0) {
        return Qfalse;
    } else {
        return Qnil;
    }
}

static VALUE
ip_evloop_abort_on_exc(self)
    VALUE self;
{
    return lib_evloop_abort_on_exc(self);
}

static VALUE
lib_evloop_abort_on_exc_set(self, val)
    VALUE self, val;
{
    rb_secure(4);
    if (RTEST(val)) {
        event_loop_abort_on_exc =  1;
    } else if (NIL_P(val)) {
        event_loop_abort_on_exc = -1;
    } else {
        event_loop_abort_on_exc =  0;
    }
    return lib_evloop_abort_on_exc(self);
}

static VALUE
ip_evloop_abort_on_exc_set(self, val)
    VALUE self, val;
{
    struct tcltkip *ptr = get_ip(self);

    rb_secure(4);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return lib_evloop_abort_on_exc(self);
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return lib_evloop_abort_on_exc(self);
    }
    return lib_evloop_abort_on_exc_set(self, val);
}

static VALUE
lib_num_of_mainwindows(self)
    VALUE self;
{
    return INT2FIX(Tk_GetNumMainWindows());
}

static int
lib_eventloop_core(check_root, update_flag, check_var)
    int check_root;
    int update_flag;
    int *check_var;
{
    volatile VALUE current = eventloop_thread;
    int found_event = 1;
    int event_flag;
    struct timeval t;
    int thr_crit_bup;


    if (update_flag) DUMP1("update loop start!!");

    t.tv_sec = (time_t)0;
    t.tv_usec = (time_t)(no_event_wait*1000.0);

    Tk_DeleteTimerHandler(timer_token);
    run_timer_flag = 0;
    if (timer_tick > 0) {
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;
        timer_token = Tk_CreateTimerHandler(timer_tick, _timer_for_tcl, 
                                            (ClientData)0);
        rb_thread_critical = thr_crit_bup;
    } else {
        timer_token = (Tcl_TimerToken)NULL;
    }

    for(;;) {
        if (rb_thread_alone()) {
            DUMP1("no other thread");
            event_loop_wait_event = 0;

            if (update_flag) {
                event_flag = update_flag | TCL_DONT_WAIT; /* for safety */
            } else {
                event_flag = TCL_ALL_EVENTS;
            }

            if (timer_tick == 0 && update_flag == 0) {
                timer_tick = NO_THREAD_INTERRUPT_TIME;
                timer_token = Tk_CreateTimerHandler(timer_tick, 
                                                    _timer_for_tcl, 
                                                    (ClientData)0);
            }

            if (check_var != (int *)NULL) {
                if (*check_var || !found_event) {
                    return found_event;
                }
            }

            found_event = Tcl_DoOneEvent(event_flag);

            if (update_flag != 0) {
              if (found_event) {
                DUMP1("next update loop");
                continue;
              } else {
                DUMP1("update complete");
                return 0;
              }
            }

            DUMP1("check Root Widget");
            if (check_root && Tk_GetNumMainWindows() == 0) {
                run_timer_flag = 0;
                if (!rb_prohibit_interrupt) {
                  if (rb_trap_pending) rb_trap_exec();
                }
                return 1;
            }

            if (loop_counter++ > 30000) {
                /* fprintf(stderr, "loop_counter > 30000\n"); */
                loop_counter = 0;
            }

        } else {
            int tick_counter;

            DUMP1("there are other threads");
            event_loop_wait_event = 1;

            found_event = 1;

            if (update_flag) {
                event_flag = update_flag | TCL_DONT_WAIT; /* for safety */
            } else {
                event_flag = TCL_ALL_EVENTS | TCL_DONT_WAIT;
            }

            timer_tick = req_timer_tick;
            tick_counter = 0;
            while(tick_counter < event_loop_max) {
                if (check_var != (int *)NULL) {
                    if (*check_var || !found_event) {
                        return found_event;
                    }
                }

                if (Tcl_DoOneEvent(event_flag)) {
                    tick_counter++;
                } else {
                    if (update_flag != 0) {
                        DUMP1("update complete");
                        return 0;
                    }
                    tick_counter += no_event_tick;
                    rb_thread_wait_for(t);
                }

                if (watchdog_thread != 0 && eventloop_thread != current) {
                    return 1;
                }

                DUMP1("check Root Widget");
                if (check_root && Tk_GetNumMainWindows() == 0) {
                    run_timer_flag = 0;
                    if (!rb_prohibit_interrupt) {
                      if (rb_trap_pending) rb_trap_exec();
                    }
                    return 1;
                }

                DUMP1("trap check");
                if (!rb_prohibit_interrupt) {
                  if (rb_trap_pending) rb_trap_exec();
                }

                if (loop_counter++ > 30000) {
                    /* fprintf(stderr, "loop_counter > 30000\n"); */
                    loop_counter = 0;
                }

                if (run_timer_flag) {
                    /*
                    DUMP1("timer interrupt");
                    run_timer_flag = 0;
                    */
                    break; /* switch to other thread */
                }
            }
        }

        DUMP1("trap check & thread scheduling");
        if (update_flag == 0) CHECK_INTS;

    }
    return 1;
}

VALUE
lib_eventloop_main(check_rootwidget)
    VALUE check_rootwidget;
{
    check_rootwidget_flag = RTEST(check_rootwidget);

    if (lib_eventloop_core(check_rootwidget_flag, 0, (int *)NULL)) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

VALUE
lib_eventloop_ensure(parent_evloop)
    VALUE parent_evloop;
{
    Tk_DeleteTimerHandler(timer_token);
    timer_token = (Tcl_TimerToken)NULL;
    DUMP2("eventloop-ensure: current-thread : %lx\n", rb_thread_current());
    DUMP2("eventloop-ensure: eventloop-thread : %lx\n", eventloop_thread);
    if (eventloop_thread == rb_thread_current()) {
        DUMP2("eventloop-thread -> %lx\n", parent_evloop);
        eventloop_thread = parent_evloop;
    }
    return Qnil;
}

static VALUE
lib_eventloop_launcher(check_rootwidget)
    VALUE check_rootwidget;
{
    VALUE parent_evloop = eventloop_thread;

    eventloop_thread = rb_thread_current();

    if (ruby_debug) { 
        fprintf(stderr, "tcltklib: eventloop-thread : %lx -> %lx\n", 
                parent_evloop, eventloop_thread);
    }

    return rb_ensure(lib_eventloop_main, check_rootwidget, 
                     lib_eventloop_ensure, parent_evloop);
}

/* execute Tk_MainLoop */
static VALUE
lib_mainloop(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    VALUE check_rootwidget;

    if (rb_scan_args(argc, argv, "01", &check_rootwidget) == 0) {
        check_rootwidget = Qtrue;
    } else if (RTEST(check_rootwidget)) {
        check_rootwidget = Qtrue;
    } else {
        check_rootwidget = Qfalse;
    }

    return lib_eventloop_launcher(check_rootwidget);
}

static VALUE
ip_mainloop(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return Qnil;
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return Qnil;
    }
    return lib_mainloop(argc, argv, self);
}

VALUE
lib_watchdog_core(check_rootwidget)
    VALUE check_rootwidget;
{
    VALUE evloop;
    int   prev_val = -1;
    int   chance = 0;
    int   check = RTEST(check_rootwidget);
    struct timeval t0, t1;

    t0.tv_sec  = (time_t)0;
    t0.tv_usec = (time_t)((NO_THREAD_INTERRUPT_TIME)*1000.0);
    t1.tv_sec  = (time_t)0;
    t1.tv_usec = (time_t)((WATCHDOG_INTERVAL)*1000.0);

    /* check other watchdog thread */
    if (watchdog_thread != 0) {
        if (RTEST(rb_funcall(watchdog_thread, ID_stop_p, 0))) {
            rb_funcall(watchdog_thread, ID_kill, 0);
        } else {
            return Qnil;
        }
    }
    watchdog_thread = rb_thread_current();

    /* watchdog start */
    do {
        if (eventloop_thread == 0 
            || (loop_counter == prev_val
                && RTEST(rb_funcall(eventloop_thread, ID_stop_p, 0))
                && ++chance >= 3 )
            ) {
            /* start new eventloop thread */
            DUMP2("eventloop thread %lx is sleeping or dead", 
                  eventloop_thread);
            evloop = rb_thread_create(lib_eventloop_launcher, 
                                      (void*)&check_rootwidget);
            DUMP2("create new eventloop thread %lx", evloop);
            loop_counter = -1;
            chance = 0;
            rb_thread_run(evloop);
        } else {
            loop_counter = prev_val;
            chance = 0;
            if (event_loop_wait_event) {
                rb_thread_wait_for(t0);
            } else {
                rb_thread_wait_for(t1);
            }
            /* rb_thread_schedule(); */
        }
    } while(!check || Tk_GetNumMainWindows() != 0);

    return Qnil;
}

VALUE
lib_watchdog_ensure(arg)
    VALUE arg;
{
    eventloop_thread = 0; /* stop eventloops */
    return Qnil;
}

static VALUE
lib_mainloop_watchdog(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    VALUE check_rootwidget;

    if (rb_scan_args(argc, argv, "01", &check_rootwidget) == 0) {
        check_rootwidget = Qtrue;
    } else if (RTEST(check_rootwidget)) {
        check_rootwidget = Qtrue;
    } else {
        check_rootwidget = Qfalse;
    }

    return rb_ensure(lib_watchdog_core, check_rootwidget, 
                     lib_watchdog_ensure, Qnil);
}

static VALUE
ip_mainloop_watchdog(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return Qnil;
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return Qnil;
    }
    return lib_mainloop_watchdog(argc, argv, self);
}

static VALUE
lib_do_one_event_core(argc, argv, self, is_ip)
    int   argc;
    VALUE *argv;
    VALUE self;
    int   is_ip;
{
    volatile VALUE vflags;
    int flags;
    int found_event;

    if (rb_scan_args(argc, argv, "01", &vflags) == 0) {
        flags = TCL_ALL_EVENTS | TCL_DONT_WAIT;
    } else {
        Check_Type(vflags, T_FIXNUM);
        flags = FIX2INT(vflags);
    }

    if (rb_safe_level() >= 4 || (rb_safe_level() >=1 && OBJ_TAINTED(vflags))) {
      flags |= TCL_DONT_WAIT;
    }

    if (is_ip) {
        /* check IP */
        struct tcltkip *ptr = get_ip(self);

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            return Qfalse;
        }

        if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
            /* slave IP */
            flags |= TCL_DONT_WAIT;
        }
    }

    /* found_event = Tcl_DoOneEvent(TCL_ALL_EVENTS | TCL_DONT_WAIT); */
    found_event = Tcl_DoOneEvent(flags);

    if (found_event) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

static VALUE
lib_do_one_event(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    return lib_do_one_event_core(argc, argv, self, 0);
}

static VALUE
ip_do_one_event(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    return lib_do_one_event_core(argc, argv, self, 0);
}


static void
ip_set_exc_message(interp, exc)
    Tcl_Interp *interp;
    VALUE exc;
{
    char *buf;
    Tcl_DString dstr;
    volatile VALUE msg;
    int thr_crit_bup;

#if TCL_MAJOR_VERSION > 8 || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION > 0)
    volatile VALUE enc;
    Tcl_Encoding encoding;
#endif

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    msg = rb_funcall(exc, ID_message, 0, 0);

#if TCL_MAJOR_VERSION > 8 || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION > 0)
    enc = Qnil;
    if (RTEST(rb_ivar_defined(exc, ID_at_enc))) {
        enc = rb_ivar_get(exc, ID_at_enc);
    }
    if (NIL_P(enc) && RTEST(rb_ivar_defined(msg, ID_at_enc))) {
        enc = rb_ivar_get(msg, ID_at_enc);
    }
    if (NIL_P(enc)) {
        encoding = (Tcl_Encoding)NULL;
    } else if (TYPE(enc) == T_STRING) {
        encoding = Tcl_GetEncoding(interp, RSTRING(enc)->ptr);
    } else {
        enc = rb_funcall(enc, ID_to_s, 0, 0);
        encoding = Tcl_GetEncoding(interp, RSTRING(enc)->ptr);
    }

    /* to avoid a garbled error message dialog */
    buf = ALLOC_N(char, (RSTRING(msg)->len)+1);
    strncpy(buf, RSTRING(msg)->ptr, RSTRING(msg)->len);
    buf[RSTRING(msg)->len] = 0;

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    Tcl_ExternalToUtfDString(encoding, buf, RSTRING(msg)->len, &dstr);

    Tcl_AppendResult(interp, Tcl_DStringValue(&dstr), (char*)NULL);
    DUMP2("error message:%s", Tcl_DStringValue(&dstr));
    free(buf);

#else /* TCL_VERSION <= 8.0 */
    Tcl_AppendResult(interp, RSTRING(msg)->ptr, (char*)NULL);
#endif

    rb_thread_critical = thr_crit_bup;
}

static VALUE
TkStringValue(obj)
    VALUE obj;
{
    switch(TYPE(obj)) {
    case T_STRING:
        return obj;

    case T_NIL:
        return rb_str_new2("");

    case T_TRUE:
        return rb_str_new2("1");

    case T_FALSE:
        return rb_str_new2("0");

    case T_ARRAY:
        return rb_funcall(obj, ID_join, 1, rb_str_new2(" "));

    default:
        if (rb_respond_to(obj, ID_to_s)) {
            return rb_funcall(obj, ID_to_s, 0, 0);
        }
    }

    return rb_funcall(obj, ID_inspect, 0, 0);
}

/* Tcl command `ruby'|`ruby_eval' */
static VALUE
ip_ruby_eval_rescue(failed, einfo)
    VALUE failed;
    VALUE einfo;
{
    DUMP1("call ip_ruby_eval_rescue");
    RARRAY(failed)->ptr[0] = einfo;
    return Qnil;
}

struct eval_body_arg {
    char  *string;
    VALUE failed;
};

static VALUE
ip_ruby_eval_body(arg)
    struct eval_body_arg *arg;
{
    volatile VALUE ret;
    int status = 0;
    int thr_crit_bup;

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    DUMP1("call ip_ruby_eval_body");
    rb_trap_immediate = 0;

#if 0
    ret = rb_rescue2(rb_eval_string, (VALUE)arg->string, 
                      ip_ruby_eval_rescue, arg->failed,
                      rb_eStandardError, rb_eScriptError, rb_eSystemExit, 
                      (VALUE)0);
#else

    rb_thread_critical = Qfalse;
    ret = rb_eval_string_protect(arg->string, &status);
    rb_thread_critical = Qtrue;
    if (status) {
        char *errtype, *buf;
        int  errtype_len, len;
        VALUE old_gc;

        old_gc = rb_gc_disable();

        switch(status) {
        case TAG_RETURN:
            errtype = "LocalJumpError: ";
            errtype_len = strlen(errtype);
            len = errtype_len + RSTRING(rb_obj_as_string(ruby_errinfo))->len;
            buf = ALLOC_N(char, len + 1);
            strncpy(buf, errtype, errtype_len);
            strncpy(buf + errtype_len, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->ptr, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->len);
            *(buf + len) = 0;

            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(eTkCallbackReturn, buf);
            free(buf);
            break;

        case TAG_BREAK:
            errtype = "LocalJumpError: ";
            errtype_len = strlen(errtype);
            len = errtype_len + RSTRING(rb_obj_as_string(ruby_errinfo))->len;
            buf = ALLOC_N(char, len + 1);
            strncpy(buf, errtype, errtype_len);
            strncpy(buf + errtype_len, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->ptr, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->len);
            *(buf + len) = 0;

            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(eTkCallbackBreak, buf);
            free(buf);
            break;

        case TAG_NEXT:
            errtype = "LocalJumpError: ";
            errtype_len = strlen(errtype);
            len = errtype_len + RSTRING(rb_obj_as_string(ruby_errinfo))->len;
            buf = ALLOC_N(char, len + 1);
            strncpy(buf, errtype, errtype_len);
            strncpy(buf + errtype_len, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->ptr, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->len);
            *(buf + len) = 0;

            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(eTkCallbackContinue,buf);
            free(buf);
            break;

        case TAG_RETRY:
        case TAG_REDO:
            if (NIL_P(ruby_errinfo)) {
                rb_jump_tag(status);
            } else {
                RARRAY(arg->failed)->ptr[0] = ruby_errinfo;
            }
            break;

        case TAG_RAISE:
        case TAG_FATAL:
            if (NIL_P(ruby_errinfo)) {
                RARRAY(arg->failed)->ptr[0] 
                    = rb_exc_new2(rb_eException, "unknown exception");
            } else {
                RARRAY(arg->failed)->ptr[0] = ruby_errinfo;
            }
            break;

        case TAG_THROW:
            if (NIL_P(ruby_errinfo)) {
                rb_jump_tag(TAG_THROW);
            } else {
                RARRAY(arg->failed)->ptr[0] = ruby_errinfo;
            }
            break;

        default:
            buf = ALLOC_N(char, 256);
            sprintf(buf, "unknown loncaljmp status %d", status);
            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(rb_eException, buf);
            free(buf);
            break;
        }

        if (old_gc == Qfalse) rb_gc_enable();

        ret = Qnil;
    }
#endif

    rb_thread_critical = thr_crit_bup;

    return ret;
}

static VALUE
ip_ruby_eval_ensure(trapflag)
    VALUE trapflag;
{
    rb_trap_immediate = NUM2INT(trapflag);
    return Qnil;
}


static int
#if TCL_MAJOR_VERSION >= 8
ip_ruby_eval(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int argc;
    Tcl_Obj *CONST argv[];
#else /* TCL_MAJOR_VERSION < 8 */
ip_ruby_eval(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    volatile VALUE res;
    volatile VALUE exception = rb_ary_new2(1);
    int old_trapflag;
    struct eval_body_arg *arg;
    int thr_crit_bup;

    /* ruby command has 1 arg. */
    if (argc != 2) {
        rb_raise(rb_eArgError, "wrong number of arguments (%d for 1)", 
                 argc - 1);
    }

    /* allocate */
    arg = ALLOC(struct eval_body_arg);

    /* get C string from Tcl object */
#if TCL_MAJOR_VERSION >= 8
    {
      char *str;
      int  len;

      thr_crit_bup = rb_thread_critical;
      rb_thread_critical = Qtrue;

      str = Tcl_GetStringFromObj(argv[1], &len);
      arg->string = ALLOC_N(char, len + 1);
      strncpy(arg->string, str, len);
      arg->string[len] = 0;

      rb_thread_critical = thr_crit_bup;

    }
#else /* TCL_MAJOR_VERSION < 8 */
    arg->string = argv[1];
#endif
    /* arg.failed = 0; */
    RARRAY(exception)->ptr[0] = Qnil;
    RARRAY(exception)->len = 1;
    arg->failed = exception;

    /* evaluate the argument string by ruby */
    DUMP2("rb_eval_string(%s)", arg->string);
    old_trapflag = rb_trap_immediate;
#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on ip_ruby_eval()");
    }
#endif
    res = rb_ensure(ip_ruby_eval_body, (VALUE)arg, 
                    ip_ruby_eval_ensure, INT2FIX(old_trapflag));

#if TCL_MAJOR_VERSION >= 8
    free(arg->string);
#endif

    free(arg);

    /* status check */
    /* if (arg.failed) { */
    if (!NIL_P(RARRAY(exception)->ptr[0])) {
        VALUE eclass;
        volatile VALUE bt_ary;
        volatile VALUE backtrace;

        DUMP1("(rb_eval_string result) failed");

        Tcl_ResetResult(interp);

        res = RARRAY(exception)->ptr[0];
        eclass = rb_obj_class(res);

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        DUMP1("set backtrace");
        if (!NIL_P(bt_ary = rb_funcall(res, ID_backtrace, 0, 0))) {
          backtrace = rb_ary_join(bt_ary, rb_str_new2("\n"));
          StringValue(backtrace);
          Tcl_AddErrorInfo(interp, RSTRING(backtrace)->ptr);
        }

        rb_thread_critical = thr_crit_bup;

        if (eclass == eTkCallbackReturn) {
            ip_set_exc_message(interp, res);
            return TCL_RETURN;

        } else if (eclass == eTkCallbackBreak) {
            ip_set_exc_message(interp, res);
            return TCL_BREAK;

        } else if (eclass == eTkCallbackContinue) {
            ip_set_exc_message(interp, res);
            return TCL_CONTINUE;

        } else if (eclass == rb_eSystemExit) {
            thr_crit_bup = rb_thread_critical;
            rb_thread_critical = Qtrue;

            /* Tcl_Eval(interp, "destroy ."); */
            if (Tk_GetNumMainWindows() > 0) {
                Tk_Window main_win = Tk_MainWindow(interp);
                if (main_win != (Tk_Window)NULL) {
                    Tk_DestroyWindow(main_win);
                }
            }

            /* StringValue(res); */
            res = rb_funcall(res, ID_message, 0, 0);

            Tcl_AppendResult(interp, RSTRING(res)->ptr, (char*)NULL);

            rb_thread_critical = thr_crit_bup;

            rb_raise(rb_eSystemExit, RSTRING(res)->ptr);

        } else if (rb_obj_is_kind_of(res, eLocalJumpError)) {
            VALUE reason = rb_ivar_get(res, ID_at_reason);

            if (TYPE(reason) != T_SYMBOL) {
                ip_set_exc_message(interp, res);
                return TCL_ERROR;
            }

            if (SYM2ID(reason) == ID_return) {
                ip_set_exc_message(interp, res);
                return TCL_RETURN;

            } else if (SYM2ID(reason) == ID_break) {
                ip_set_exc_message(interp, res);
                return TCL_BREAK;

            } else if (SYM2ID(reason) == ID_next) {
                ip_set_exc_message(interp, res);
                return TCL_CONTINUE;

            } else {
                ip_set_exc_message(interp, res);
                return TCL_ERROR;
            }
        } else {
            ip_set_exc_message(interp, res);
            return TCL_ERROR;
        }
    }

    /* result must be string or nil */
    if (NIL_P(res)) {
        DUMP1("(rb_eval_string result) nil");
        Tcl_ResetResult(interp);
        return TCL_OK;
    }

    /* copy result to the tcl interpreter */
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    res = TkStringValue(res);
    DUMP2("(rb_eval_string result) %s", RSTRING(res)->ptr);
    DUMP1("Tcl_AppendResult");
    Tcl_ResetResult(interp);
    Tcl_AppendResult(interp, RSTRING(res)->ptr, (char *)NULL);

    rb_thread_critical = thr_crit_bup;

    return TCL_OK;
}


/* Tcl command `ruby_cmd' */
struct cmd_body_arg {
    VALUE receiver;
    ID    method;
    VALUE args;
    VALUE failed;
};

static VALUE
ip_ruby_cmd_core(arg)
    struct cmd_body_arg *arg;
{
    volatile VALUE ret;
    int thr_crit_bup;

    DUMP1("call ip_ruby_cmd_core");
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qfalse;
    ret = rb_apply(arg->receiver, arg->method, arg->args);
    rb_thread_critical = thr_crit_bup;
    DUMP1("finish ip_ruby_cmd_core");

    return ret;
}

static VALUE
ip_ruby_cmd_rescue(failed, einfo)
    VALUE failed;
    VALUE einfo;
{
    DUMP1("call ip_ruby_cmd_rescue");
    RARRAY(failed)->ptr[0] = einfo;
    return Qnil;
}

static VALUE
ip_ruby_cmd_body(arg)
    struct cmd_body_arg *arg;
{
    volatile VALUE ret;
    int status = 0;
    int thr_crit_bup;
    VALUE old_gc;

    volatile VALUE receiver = arg->receiver;
    volatile VALUE args     = arg->args;
    volatile VALUE failed   = arg->failed;

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    DUMP1("call ip_ruby_cmd_body");
    rb_trap_immediate = 0;

#if 0
    ret = rb_rescue2(ip_ruby_cmd_core, (VALUE)arg, 
                     ip_ruby_cmd_rescue, arg->failed,
                     rb_eStandardError, rb_eScriptError, rb_eSystemExit, 
                     (VALUE)0);
#else
    ret = rb_protect(ip_ruby_cmd_core, (VALUE)arg, &status);

    if (status) {
        char *errtype, *buf;
        int  errtype_len, len;

        old_gc = rb_gc_disable();

        switch(status) {
        case TAG_RETURN:
            errtype = "LocalJumpError: ";
            errtype_len = strlen(errtype);
            len = errtype_len + RSTRING(rb_obj_as_string(ruby_errinfo))->len;
            buf = ALLOC_N(char, len + 1);
            strncpy(buf, errtype, errtype_len);
            strncpy(buf + errtype_len, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->ptr, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->len);
            *(buf + len) = 0;

            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(eTkCallbackReturn, buf);
            free(buf);
            break;

        case TAG_BREAK:
            errtype = "LocalJumpError: ";
            errtype_len = strlen(errtype);
            len = errtype_len + RSTRING(rb_obj_as_string(ruby_errinfo))->len;
            buf = ALLOC_N(char, len + 1);
            strncpy(buf, errtype, errtype_len);
            strncpy(buf + errtype_len, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->ptr, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->len);
            *(buf + len) = 0;

            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(eTkCallbackBreak, buf);
            free(buf);
            break;

        case TAG_NEXT:
            errtype = "LocalJumpError: ";
            errtype_len = strlen(errtype);
            len = errtype_len + RSTRING(rb_obj_as_string(ruby_errinfo))->len;
            buf = ALLOC_N(char, len + 1);
            strncpy(buf, errtype, errtype_len);
            strncpy(buf + errtype_len, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->ptr, 
                    RSTRING(rb_obj_as_string(ruby_errinfo))->len);
            *(buf + len) = 0;

            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(eTkCallbackContinue,buf);
            free(buf);
            break;

        case TAG_RETRY:
        case TAG_REDO:
            if (NIL_P(ruby_errinfo)) {
                rb_jump_tag(status);
            } else {
                RARRAY(arg->failed)->ptr[0] = ruby_errinfo;
            }
            break;

        case TAG_RAISE:
        case TAG_FATAL:
            if (NIL_P(ruby_errinfo)) {
                RARRAY(arg->failed)->ptr[0] 
                    = rb_exc_new2(rb_eException, "unknown exception");
            } else {
                RARRAY(arg->failed)->ptr[0] = ruby_errinfo;
            }
            break;

        case TAG_THROW:
            if (NIL_P(ruby_errinfo)) {
                rb_jump_tag(TAG_THROW);
            } else {
                RARRAY(arg->failed)->ptr[0] = ruby_errinfo;
            }
            break;

        default:
            buf = ALLOC_N(char, 256);
            rb_warn(buf, "unknown loncaljmp status %d", status);
            RARRAY(arg->failed)->ptr[0] = rb_exc_new2(rb_eException, buf);
            free(buf);
            break;
        }

        if (old_gc == Qfalse) rb_gc_enable();

        ret = Qnil;
    }
#endif

    rb_thread_critical = thr_crit_bup;
    DUMP1("finish ip_ruby_cmd_body");

    return ret;
}

static VALUE
ip_ruby_cmd_ensure(trapflag)
    VALUE trapflag;
{
    rb_trap_immediate = NUM2INT(trapflag);
    return Qnil;
}

/* ruby_cmd receiver method arg ... */
static int
#if TCL_MAJOR_VERSION >= 8
ip_ruby_cmd(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int argc;
    Tcl_Obj *CONST argv[];
#else /* TCL_MAJOR_VERSION < 8 */
ip_ruby_cmd(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    volatile VALUE res;
    volatile VALUE receiver;
    volatile ID method;
    volatile VALUE args = rb_ary_new2(argc - 2);
    volatile VALUE exception = rb_ary_new2(1);
    char *str;
    int i;
    int  len;
    int old_trapflag;
    struct cmd_body_arg *arg;
    int thr_crit_bup;
    VALUE old_gc;

    if (argc < 3) {
        rb_raise(rb_eArgError, "too few arguments");
    }

    /* allocate */
    arg = ALLOC(struct cmd_body_arg);

    /* get arguments from Tcl objects */
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;
    old_gc = rb_gc_disable();

    /* get receiver */
#if TCL_MAJOR_VERSION >= 8
    str = Tcl_GetStringFromObj(argv[1], &len);
#else /* TCL_MAJOR_VERSION < 8 */
    str = argv[1];
#endif
    DUMP2("receiver:%s",str);
    if (str[0] == ':' || ('A' <= str[0] && str[0] <= 'Z')) {
        /* class | module | constant */
        receiver = rb_const_get(rb_cObject, rb_intern(str));
    } else if (str[0] == '$') {
        /* global variable */
        receiver = rb_gv_get(str);
    } else {
        /* global variable omitted '$' */
        char *buf;

        len = strlen(str);
        buf = ALLOC_N(char, len + 2);
        buf[0] = '$';
        strncpy(buf + 1, str, len);
        buf[len + 1] = 0;
        receiver = rb_gv_get(buf);
        free(buf);
    }
    if (NIL_P(receiver)) {
        rb_raise(rb_eArgError, "unknown class/module/global-variable '%s'", 
                 str);
    }

    /* get metrhod */
#if TCL_MAJOR_VERSION >= 8
    str = Tcl_GetStringFromObj(argv[2], &len);
#else /* TCL_MAJOR_VERSION < 8 */
    str = argv[2];
#endif
    method = rb_intern(str);

    /* get args */
    RARRAY(args)->len = 0;
    for(i = 3; i < argc; i++) {
#if TCL_MAJOR_VERSION >= 8
        str = Tcl_GetStringFromObj(argv[i], &len);
        DUMP2("arg:%s",str);
        RARRAY(args)->ptr[RARRAY(args)->len++] = rb_tainted_str_new(str, len);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP2("arg:%s",argv[i]);
        RARRAY(args)->ptr[RARRAY(args)->len++] = rb_tainted_str_new2(argv[i]);
#endif
    }

    if (old_gc == Qfalse) rb_gc_enable();
    rb_thread_critical = thr_crit_bup;

    RARRAY(exception)->ptr[0] = Qnil;
    RARRAY(exception)->len = 1;

    arg->receiver = receiver;
    arg->method = method;
    arg->args = args;
    arg->failed = exception;

    /* evaluate the argument string by ruby */
    old_trapflag = rb_trap_immediate;
#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on ip_ruby_cmd()");
    }
#endif

    res = rb_ensure(ip_ruby_cmd_body, (VALUE)arg, 
                    ip_ruby_cmd_ensure, INT2FIX(old_trapflag));

    free(arg);

    /* status check */
    /* if (arg.failed) { */
    if (!NIL_P(RARRAY(exception)->ptr[0])) {
        VALUE eclass;
        volatile VALUE bt_ary;
        volatile VALUE backtrace;

        DUMP1("(rb_eval_cmd result) failed");

        Tcl_ResetResult(interp);

        res = RARRAY(exception)->ptr[0];
        eclass = rb_obj_class(res);

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        DUMP1("set backtrace");
        if (!NIL_P(bt_ary = rb_funcall(res, ID_backtrace, 0, 0))) {
          backtrace = rb_ary_join(bt_ary, rb_str_new2("\n"));
          StringValue(backtrace);
          Tcl_AddErrorInfo(interp, RSTRING(backtrace)->ptr);
        }

        rb_thread_critical = thr_crit_bup;

        if (eclass == eTkCallbackReturn) {
            ip_set_exc_message(interp, res);
            return TCL_RETURN;

        } else if (eclass == eTkCallbackBreak) {
            ip_set_exc_message(interp, res);
            return TCL_BREAK;

        } else if (eclass == eTkCallbackContinue) {
            ip_set_exc_message(interp, res);
            return TCL_CONTINUE;

        } else if (eclass == rb_eSystemExit) {
            thr_crit_bup = rb_thread_critical;
            rb_thread_critical = Qtrue;

            /* Tcl_Eval(interp, "destroy ."); */
            if (Tk_GetNumMainWindows() > 0) {
                Tk_Window main_win = Tk_MainWindow(interp);
                if (main_win != (Tk_Window)NULL) {
                    Tk_DestroyWindow(main_win);
                }
            }

            /* StringValue(res); */
            res = rb_funcall(res, ID_message, 0, 0);

            Tcl_AppendResult(interp, RSTRING(res)->ptr, (char*)NULL);

            rb_thread_critical = thr_crit_bup;

            rb_raise(rb_eSystemExit, RSTRING(res)->ptr);

        } else if (rb_obj_is_kind_of(res, eLocalJumpError)) {
            VALUE reason = rb_ivar_get(res, ID_at_reason);

            if (TYPE(reason) != T_SYMBOL) {
                ip_set_exc_message(interp, res);
                return TCL_ERROR;
            }

            if (SYM2ID(reason) == ID_return) {
                ip_set_exc_message(interp, res);
                return TCL_RETURN;

            } else if (SYM2ID(reason) == ID_break) {
                ip_set_exc_message(interp, res);
                return TCL_BREAK;

            } else if (SYM2ID(reason) == ID_next) {
                ip_set_exc_message(interp, res);
                return TCL_CONTINUE;

            } else {
                ip_set_exc_message(interp, res);
                return TCL_ERROR;
            }
        } else {
            ip_set_exc_message(interp, res);
            return TCL_ERROR;
        }
    }

    /* result must be string or nil */
    if (NIL_P(res)) {
        DUMP1("(rb_eval_cmd result) nil");
        Tcl_ResetResult(interp);
        return TCL_OK;
    }


    /* copy result to the tcl interpreter */
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    old_gc = rb_gc_disable();

    res = TkStringValue(res);

    if (old_gc == Qfalse) rb_gc_enable();
    DUMP2("(rb_eval_cmd result) '%s'", RSTRING(res)->ptr);
    DUMP1("Tcl_AppendResult");
    Tcl_ResetResult(interp);
    Tcl_AppendResult(interp, RSTRING(res)->ptr, (char *)NULL);

    rb_thread_critical = thr_crit_bup;

    DUMP1("end of ip_ruby_cmd");
    return TCL_OK;
}


static int
#if TCL_MAJOR_VERSION >= 8
ip_InterpExitObjCmd(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int argc;
    Tcl_Obj *CONST argv[];
#else /* TCL_MAJOR_VERSION < 8 */
ip_InterpExitCommand(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    if (!Tcl_InterpDeleted(interp)) {
        Tcl_Preserve(interp);
        Tcl_Eval(interp, "interp eval {} {destroy .}; interp delete {}");
        Tcl_Release(interp);
    }
    return TCL_OK;
}

static int
#if TCL_MAJOR_VERSION >= 8
ip_RubyExitObjCmd(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int argc;
    Tcl_Obj *CONST argv[];
#else /* TCL_MAJOR_VERSION < 8 */
ip_RubyExitCommand(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    int state;
    char *cmd, *param;

#if TCL_MAJOR_VERSION >= 8
    cmd = Tcl_GetString(argv[0]);

#else /* TCL_MAJOR_VERSION < 8 */
    char *endptr;
    cmd = argv[0];
#endif

    if (rb_safe_level() >= 4) {
        rb_raise(rb_eSecurityError, 
                 "Insecure operation `exit' at level %d", 
                 rb_safe_level());
    } else if (Tcl_IsSafe(interp)) {
        rb_raise(rb_eSecurityError, 
                 "Insecure operation `exit' on a safe interpreter");
#if 0
    } else if (Tcl_GetMaster(interp) != (Tcl_Interp *)NULL) {
        Tcl_Preserve(interp);
        Tcl_Eval(interp, "interp eval {} {destroy .}");
        Tcl_Eval(interp, "interp delete {}");
        Tcl_Release(interp);
        return TCL_OK;
#endif
    }

    Tcl_ResetResult(interp);

    switch(argc) {
    case 1:
        rb_exit(0); /* not return if succeed */

        Tcl_AppendResult(interp, 
                         "fail to call \"", cmd, "\"", (char *)NULL);
        return TCL_ERROR;

    case 2:
#if TCL_MAJOR_VERSION >= 8
        if (!Tcl_GetIntFromObj(interp, argv[1], &state)) {
            return TCL_ERROR;
        }
        param = Tcl_GetString(argv[1]);
#else /* TCL_MAJOR_VERSION < 8 */
        state = (int)strtol(argv[1], &endptr, 0);
        if (endptr) {
            Tcl_AppendResult(interp, 
                             "expected integer but got \"", 
                             argv[1], "\"", (char *)NULL);
        }
        param = argv[1];
#endif
        rb_exit(state); /* not return if succeed */

        Tcl_AppendResult(interp, "fail to call \"", cmd, " ", 
                         param, "\"", (char *)NULL);
        return TCL_ERROR;
    default:
        /* arguemnt error */
        Tcl_AppendResult(interp, 
                         "wrong number of arguments: should be \"", 
                         cmd, " ?returnCode?\"", (char *)NULL);
        return TCL_ERROR;
    }
}


/**************************/
/*  based on tclEvent.c   */
/**************************/

#if 0  /* 
          Disable the following "update" and "thread_update". Bcause, 
          they don't work in a callback-proc. After calling update in 
          a callback-proc, the callback proc never be worked. 
          If the problem will be fixed in the future, may enable the 
          functions. 
       */
/*********************/
/* replace of update */
/*********************/
#if TCL_MAJOR_VERSION >= 8
static int ip_rbUpdateObjCmd _((ClientData, Tcl_Interp *, int,
                               Tcl_Obj *CONST []));
static int
ip_rbUpdateObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_rbUpdateCommand _((ClientData, Tcl_Interp *, int, char *[]));
static int
ip_rbUpdateCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    int  optionIndex;
    int  ret, done;
    int  flags = 0;
    static CONST char *updateOptions[] = {"idletasks", (char *) NULL};
    enum updateOptions {REGEXP_IDLETASKS};
    char *nameString;
    int  dummy;

    DUMP1("Ruby's 'update' is called");
    if (objc == 1) {
        flags = TCL_ALL_EVENTS|TCL_DONT_WAIT;

    } else if (objc == 2) {
        if (Tcl_GetIndexFromObj(interp, objv[1], updateOptions,
                "option", 0, &optionIndex) != TCL_OK) {
            return TCL_ERROR;
        }
        switch ((enum updateOptions) optionIndex) {
            case REGEXP_IDLETASKS: {
                flags = TCL_WINDOW_EVENTS|TCL_IDLE_EVENTS|TCL_DONT_WAIT;
                break;
            }
            default: {
                Tcl_Panic("ip_rbUpdateObjCmd: bad option index to UpdateOptions");
            }
        }
    } else {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "[ idletasks ]");
#else
# if TCL_MAJOR_VERSION >= 8
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         Tcl_GetStringFromObj(objv[0], &dummy), 
                         " [ idletasks ]\"", 
                         (char *) NULL);
# else /* TCL_MAJOR_VERSION < 8 */
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         objv[0], " [ idletasks ]\"", (char *) NULL);
# endif
#endif
        return TCL_ERROR;
    }

    /* call eventloop */
#if 1
    ret = lib_eventloop_core(0, flags, (int *)NULL); /* ignore result */
#else
    Tcl_UpdateObjCmd(clientData, interp, objc, objv);
#endif

    /*
     * Must clear the interpreter's result because event handlers could
     * have executed commands.
     */

    DUMP2("last result '%s'", Tcl_GetStringResult(interp));
    Tcl_ResetResult(interp);
    DUMP1("finish Ruby's 'update'");
    return TCL_OK;
}


/**********************/
/* update with thread */
/**********************/
struct th_update_param {
    VALUE thread;
    int   done;
};

static void rb_threadUpdateProc _((ClientData));
static void 
rb_threadUpdateProc(clientData)
    ClientData clientData;      /* Pointer to integer to set to 1. */
{
    struct th_update_param *param = (struct th_update_param *) clientData;

    DUMP1("threadUpdateProc is called");
    param->done = 1;
    rb_thread_wakeup(param->thread);

    return;
}

#if TCL_MAJOR_VERSION >= 8
static int ip_rb_threadUpdateObjCmd _((ClientData, Tcl_Interp *, int,
                                       Tcl_Obj *CONST []));
static int
ip_rb_threadUpdateObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_rb_threadUpdateCommand _((ClientData, Tcl_Interp *, int,
                                       char *[]));
static int
ip_rb_threadUpdateCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    int  optionIndex;
    int  ret, done;
    int  flags = 0;
    int  dummy;
    struct th_update_param *param;
    static CONST char *updateOptions[] = {"idletasks", (char *) NULL};
    enum updateOptions {REGEXP_IDLETASKS};
    volatile VALUE current_thread = rb_thread_current();

    DUMP1("Ruby's 'thread_update' is called");

    if (rb_thread_alone() || eventloop_thread == current_thread) {
#define USE_TCL_UPDATE 0
#if TCL_MAJOR_VERSION >= 8
# if USE_TCL_UPDATE
        DUMP1("call Tcl_UpdateObjCmd");
        return Tcl_UpdateObjCmd(clientData, interp, objc, objv);
# else
        DUMP1("call ip_rbUpdateObjCmd");
        return ip_rbUpdateObjCmd(clientData, interp, objc, objv);
# endif
#else /* TCL_MAJOR_VERSION < 8 */
# if USE_TCL_UPDATE
        DUMP1("call ip_rbUpdateCommand");
        return Tcl_UpdateCommand(clientData, interp, objc, objv);
# else
        DUMP1("call ip_rbUpdateCommand");
        return ip_rbUpdateCommand(clientData, interp, objc, objv);
# endif 
#endif
    }

    DUMP1("start Ruby's 'thread_update' body");

    if (objc == 1) {
        flags = TCL_ALL_EVENTS|TCL_DONT_WAIT;

    } else if (objc == 2) {
        if (Tcl_GetIndexFromObj(interp, objv[1], updateOptions,
                "option", 0, &optionIndex) != TCL_OK) {
            return TCL_ERROR;
        }
        switch ((enum updateOptions) optionIndex) {
            case REGEXP_IDLETASKS: {
                flags = TCL_WINDOW_EVENTS|TCL_IDLE_EVENTS|TCL_DONT_WAIT;
                break;
            }
            default: {
                Tcl_Panic("ip_rb_threadUpdateObjCmd: bad option index to UpdateOptions");
            }
        }
    } else {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "[ idletasks ]");
#else
# if TCL_MAJOR_VERSION >= 8
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         Tcl_GetStringFromObj(objv[0], &dummy), 
                         " [ idletasks ]\"", 
                         (char *) NULL);
# else /* TCL_MAJOR_VERSION < 8 */
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         objv[0], " [ idletasks ]\"", (char *) NULL);
# endif
#endif
        return TCL_ERROR;
    }

    DUMP1("pass argument check");

    param = (struct th_update_param *)Tcl_Alloc(sizeof(struct th_update_param));
    Tcl_Preserve(param);
    param->thread = current_thread;
    param->done = 0;

    DUMP1("set idle proc");
    Tcl_DoWhenIdle(rb_threadUpdateProc, (ClientData) param);

    while(!param->done) {
        DUMP1("wait for complete idle proc");
        rb_thread_stop();
    }

    Tcl_Release(param);
    Tcl_Free((char *)param);

    DUMP1("finish Ruby's 'thread_update'");
    return TCL_OK;
}
#endif  /* update and thread_update don't work */


/***************************/
/* replace of vwait/tkwait */
/***************************/
#if TCL_MAJOR_VERSION >= 8
static char *VwaitVarProc _((ClientData, Tcl_Interp *, 
                             CONST84 char *,CONST84 char *, int));
static char *
VwaitVarProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    CONST84 char *name1;        /* Name of variable. */
    CONST84 char *name2;        /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
#else /* TCL_MAJOR_VERSION < 8 */
static char *VwaitVarProc _((ClientData, Tcl_Interp *, char *, char *, int));
static char *
VwaitVarProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    char *name1;                /* Name of variable. */
    char *name2;                /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
#endif
{
    int *donePtr = (int *) clientData;

    *donePtr = 1;
    return (char *) NULL;
}

#if TCL_MAJOR_VERSION >= 8
static int ip_rbVwaitObjCmd _((ClientData, Tcl_Interp *, int,
                               Tcl_Obj *CONST []));
static int
ip_rbVwaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_rbVwaitCommand _((ClientData, Tcl_Interp *, int, char *[]));
static int
ip_rbVwaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    int  ret, done, foundEvent;
    char *nameString;
    int  dummy;
    int thr_crit_bup;

    DUMP1("Ruby's 'vwait' is called");
    Tcl_Preserve(interp);

    if (objc != 2) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "name");
#else
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
        /* nameString = Tcl_GetString(objv[0]); */
        nameString = Tcl_GetStringFromObj(objv[0], &dummy);
#else /* TCL_MAJOR_VERSION < 8 */
        nameString = objv[0];
#endif
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         nameString, " name\"", (char *) NULL);

        rb_thread_critical = thr_crit_bup;
#endif

        Tcl_Release(interp);
        return TCL_ERROR;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
    Tcl_IncrRefCount(objv[1]);
    /* nameString = Tcl_GetString(objv[1]); */
    nameString = Tcl_GetStringFromObj(objv[1], &dummy);
#else /* TCL_MAJOR_VERSION < 8 */
    nameString = objv[1];
#endif

    /* 
    if (Tcl_TraceVar(interp, nameString,
                     TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                     VwaitVarProc, (ClientData) &done) != TCL_OK) {
        return TCL_ERROR;
    }
    */
    ret = Tcl_TraceVar(interp, nameString,
                       TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                       VwaitVarProc, (ClientData) &done);

    rb_thread_critical = thr_crit_bup;

    if (ret != TCL_OK) {
#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[1]);
#endif
        Tcl_Release(interp);
        return TCL_ERROR;
    }
    done = 0;
    foundEvent = lib_eventloop_core(/* not check root-widget */0, 0, &done);

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    Tcl_UntraceVar(interp, nameString,
                   TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                   VwaitVarProc, (ClientData) &done);

    rb_thread_critical = thr_crit_bup;

    /*
     * Clear out the interpreter's result, since it may have been set
     * by event handlers.
     */

    Tcl_ResetResult(interp);
    if (!foundEvent) {
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        Tcl_AppendResult(interp, "can't wait for variable \"", nameString,
                         "\":  would wait forever", (char *) NULL);

        rb_thread_critical = thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[1]);
#endif
        Tcl_Release(interp);
        return TCL_ERROR;
    }

#if TCL_MAJOR_VERSION >= 8
    Tcl_DecrRefCount(objv[1]);
#endif
    Tcl_Release(interp);
    return TCL_OK;
}


/**************************/
/*  based on tkCmd.c      */
/**************************/
#if TCL_MAJOR_VERSION >= 8
static char *WaitVariableProc _((ClientData, Tcl_Interp *, 
                                 CONST84 char *,CONST84 char *, int));
static char *
WaitVariableProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    CONST84 char *name1;        /* Name of variable. */
    CONST84 char *name2;        /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
#else /* TCL_MAJOR_VERSION < 8 */
static char *WaitVariableProc _((ClientData, Tcl_Interp *, 
                                 char *, char *, int));
static char *
WaitVariableProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    char *name1;                /* Name of variable. */
    char *name2;                /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
#endif
{
    int *donePtr = (int *) clientData;

    *donePtr = 1;
    return (char *) NULL;
}

static void WaitVisibilityProc _((ClientData, XEvent *));
static void
WaitVisibilityProc(clientData, eventPtr)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    XEvent *eventPtr;           /* Information about event (not used). */
{
    int *donePtr = (int *) clientData;

    if (eventPtr->type == VisibilityNotify) {
        *donePtr = 1;
    }
    if (eventPtr->type == DestroyNotify) {
        *donePtr = 2;
    }
}

static void WaitWindowProc _((ClientData, XEvent *));
static void
WaitWindowProc(clientData, eventPtr)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    XEvent *eventPtr;           /* Information about event. */
{
    int *donePtr = (int *) clientData;

    if (eventPtr->type == DestroyNotify) {
        *donePtr = 1;
    }
}

#if TCL_MAJOR_VERSION >= 8
static int ip_rbTkWaitObjCmd _((ClientData, Tcl_Interp *, int,
                                Tcl_Obj *CONST []));
static int
ip_rbTkWaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_rbTkWaitCommand _((ClientData, Tcl_Interp *, int, char *[]));
static int
ip_rbTkWaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    Tk_Window tkwin = (Tk_Window) clientData;
    Tk_Window window;
    int done, index;
    static CONST char *optionStrings[] = { "variable", "visibility", "window",
                                           (char *) NULL };
    enum options { TKWAIT_VARIABLE, TKWAIT_VISIBILITY, TKWAIT_WINDOW };
    char *nameString;
    int ret, dummy;
    int thr_crit_bup;

    DUMP1("Ruby's 'tkwait' is called");

    Tcl_Preserve(interp);

    if (objc != 3) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "variable|visibility|window name");
#else
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         Tcl_GetStringFromObj(objv[0], &dummy), 
                         " variable|visibility|window name\"", 
                         (char *) NULL);
#else /* TCL_MAJOR_VERSION < 8 */
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         objv[0], " variable|visibility|window name\"", 
                         (char *) NULL);
#endif

        rb_thread_critical = thr_crit_bup;
#endif

        Tcl_Release(interp);
        return TCL_ERROR;
    }

#if TCL_MAJOR_VERSION >= 8
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /*
    if (Tcl_GetIndexFromObj(interp, objv[1], 
                            (CONST84 char **)optionStrings, 
                            "option", 0, &index) != TCL_OK) {
        return TCL_ERROR;
    }
    */
    ret = Tcl_GetIndexFromObj(interp, objv[1], 
                              (CONST84 char **)optionStrings, 
                              "option", 0, &index);

    rb_thread_critical = thr_crit_bup;

    if (ret != TCL_OK) {
        Tcl_Release(interp);
        return TCL_ERROR;
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        int c = objv[1][0];
        size_t length = strlen(objv[1]);

        if ((c == 'v') && (strncmp(objv[1], "variable", length) == 0)
            && (length >= 2)) {
            index = TKWAIT_VARIABLE;
        } else if ((c == 'v') && (strncmp(objv[1], "visibility", length) == 0)
                   && (length >= 2)) {
            index = TKWAIT_VISIBILITY;
        } else if ((c == 'w') && (strncmp(objv[1], "window", length) == 0)) {
            index = TKWAIT_WINDOW;
        } else {
            Tcl_AppendResult(interp, "bad option \"", objv[1],
                             "\": must be variable, visibility, or window", 
                             (char *) NULL);
            Tcl_Release(interp);
            return TCL_ERROR;
        }
    }
#endif

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
    Tcl_IncrRefCount(objv[2]);
    /* nameString = Tcl_GetString(objv[2]); */
    nameString = Tcl_GetStringFromObj(objv[2], &dummy);
#else /* TCL_MAJOR_VERSION < 8 */
    nameString = objv[2];
#endif

    rb_thread_critical = thr_crit_bup;

    switch ((enum options) index) {
    case TKWAIT_VARIABLE:
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;
        /*
        if (Tcl_TraceVar(interp, nameString,
                         TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                         WaitVariableProc, (ClientData) &done) != TCL_OK) {
            return TCL_ERROR;
        }
        */
        ret = Tcl_TraceVar(interp, nameString,
                           TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                           WaitVariableProc, (ClientData) &done);

        rb_thread_critical = thr_crit_bup;

        if (ret != TCL_OK) {
#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif
            Tcl_Release(interp);
            return TCL_ERROR;
        }
        done = 0;
        lib_eventloop_core(check_rootwidget_flag, 0, &done);

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        Tcl_UntraceVar(interp, nameString,
                       TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                       WaitVariableProc, (ClientData) &done);

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        rb_thread_critical = thr_crit_bup;

        break;

    case TKWAIT_VISIBILITY:
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        if (Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

        if (window == NULL) {
            rb_thread_critical = thr_crit_bup;
#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif
            Tcl_Release(interp);
            return TCL_ERROR;
        }

        Tk_CreateEventHandler(window,
                              VisibilityChangeMask|StructureNotifyMask,
                              WaitVisibilityProc, (ClientData) &done);

        rb_thread_critical = thr_crit_bup;

        done = 0;
        lib_eventloop_core(check_rootwidget_flag, 0, &done);
        if (done != 1) {
            /*
             * Note that we do not delete the event handler because it
             * was deleted automatically when the window was destroyed.
             */
            thr_crit_bup = rb_thread_critical;
            rb_thread_critical = Qtrue;

            Tcl_ResetResult(interp);
            Tcl_AppendResult(interp, "window \"", nameString,
                             "\" was deleted before its visibility changed",
                             (char *) NULL);

            rb_thread_critical = thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif
            Tcl_Release(interp);
            return TCL_ERROR;
        }

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        Tk_DeleteEventHandler(window,
                              VisibilityChangeMask|StructureNotifyMask,
                              WaitVisibilityProc, (ClientData) &done);

        rb_thread_critical = thr_crit_bup;

        break;

    case TKWAIT_WINDOW:
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;
            
        if (Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        if (window == NULL) {
            rb_thread_critical = thr_crit_bup;
            Tcl_Release(interp);
            return TCL_ERROR;
        }

        Tk_CreateEventHandler(window, StructureNotifyMask,
                              WaitWindowProc, (ClientData) &done);

        rb_thread_critical = thr_crit_bup;

        done = 0;
        lib_eventloop_core(check_rootwidget_flag, 0, &done);
        /*
         * Note:  there's no need to delete the event handler.  It was
         * deleted automatically when the window was destroyed.
         */
        break;
    }

    /*
     * Clear out the interpreter's result, since it may have been set
     * by event handlers.
     */

    Tcl_ResetResult(interp);
    Tcl_Release(interp);
    return TCL_OK;
}

/****************************/
/* vwait/tkwait with thread */
/****************************/
struct th_vwait_param {
    VALUE thread;
    int   done;
};

#if TCL_MAJOR_VERSION >= 8
static char *rb_threadVwaitProc _((ClientData, Tcl_Interp *, 
                                   CONST84 char *,CONST84 char *, int));
static char *
rb_threadVwaitProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    CONST84 char *name1;        /* Name of variable. */
    CONST84 char *name2;        /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
#else /* TCL_MAJOR_VERSION < 8 */
static char *rb_threadVwaitProc _((ClientData, Tcl_Interp *, 
                                   char *, char *, int));
static char *
rb_threadVwaitProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    char *name1;                /* Name of variable. */
    char *name2;                /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
#endif
{
    struct th_vwait_param *param = (struct th_vwait_param *) clientData;

    if (flags & (TCL_INTERP_DESTROYED | TCL_TRACE_DESTROYED)) {
        param->done = -1;
    } else {
        param->done = 1;
    }
    rb_thread_wakeup(param->thread);

    return (char *)NULL;
}

#define TKWAIT_MODE_VISIBILITY 1
#define TKWAIT_MODE_DESTROY    2

static void rb_threadWaitVisibilityProc _((ClientData, XEvent *));
static void
rb_threadWaitVisibilityProc(clientData, eventPtr)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    XEvent *eventPtr;           /* Information about event (not used). */
{
    struct th_vwait_param *param = (struct th_vwait_param *) clientData;

    if (eventPtr->type == VisibilityNotify) {
        param->done = TKWAIT_MODE_VISIBILITY;
    }
    if (eventPtr->type == DestroyNotify) {
        param->done = TKWAIT_MODE_DESTROY;
    }
    rb_thread_wakeup(param->thread);
}

static void rb_threadWaitWindowProc _((ClientData, XEvent *));
static void
rb_threadWaitWindowProc(clientData, eventPtr)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    XEvent *eventPtr;           /* Information about event. */
{
    struct th_vwait_param *param = (struct th_vwait_param *) clientData;

    if (eventPtr->type == DestroyNotify) {
        param->done = TKWAIT_MODE_DESTROY;
    }
    rb_thread_wakeup(param->thread);
}

#if TCL_MAJOR_VERSION >= 8
static int ip_rb_threadVwaitObjCmd _((ClientData, Tcl_Interp *, int,
                                      Tcl_Obj *CONST []));
static int
ip_rb_threadVwaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_rb_threadVwaitCommand _((ClientData, Tcl_Interp *, int,
                                       char *[]));
static int
ip_rb_threadVwaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    struct th_vwait_param *param;
    char *nameString;
    int ret, dummy;
    int thr_crit_bup;
    volatile VALUE current_thread = rb_thread_current();

    DUMP1("Ruby's 'thread_vwait' is called");

    if (rb_thread_alone() || eventloop_thread == current_thread) {
#if TCL_MAJOR_VERSION >= 8
        DUMP1("call ip_rbVwaitObjCmd");
        return ip_rbVwaitObjCmd(clientData, interp, objc, objv);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP1("call ip_rbVwaitCommand");
        return ip_rbVwaitCommand(clientData, interp, objc, objv);
#endif
    }

    Tcl_Preserve(interp);

    if (objc != 2) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "name");
#else
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
        /* nameString = Tcl_GetString(objv[0]); */
        nameString = Tcl_GetStringFromObj(objv[0], &dummy);
#else /* TCL_MAJOR_VERSION < 8 */
        nameString = objv[0];
#endif
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         nameString, " name\"", (char *) NULL);

        rb_thread_critical = thr_crit_bup;
#endif

        Tcl_Release(interp);
        return TCL_ERROR;
    }

#if TCL_MAJOR_VERSION >= 8
    Tcl_IncrRefCount(objv[1]);
    /* nameString = Tcl_GetString(objv[1]); */
    nameString = Tcl_GetStringFromObj(objv[1], &dummy);
#else /* TCL_MAJOR_VERSION < 8 */
    nameString = objv[1];
#endif
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    param = (struct th_vwait_param *)Tcl_Alloc(sizeof(struct th_vwait_param));
    Tcl_Preserve(param);
    param->thread = current_thread;
    param->done = 0;

    /*
    if (Tcl_TraceVar(interp, nameString,
                     TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                     rb_threadVwaitProc, (ClientData) param) != TCL_OK) {
        return TCL_ERROR;
    }
    */
    ret = Tcl_TraceVar(interp, nameString,
                       TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                       rb_threadVwaitProc, (ClientData) param);

    rb_thread_critical = thr_crit_bup;

    if (ret != TCL_OK) {
#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[1]);
#endif
        Tcl_Release(interp);
        return TCL_ERROR;
    }

    /* if (!param->done) { */
    while(!param->done) {
        rb_thread_stop();
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (param->done > 0) {
        Tcl_UntraceVar(interp, nameString,
                       TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                       rb_threadVwaitProc, (ClientData) param);
    }

    Tcl_Release(param);
    Tcl_Free((char *)param);

    rb_thread_critical = thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
    Tcl_DecrRefCount(objv[1]);
#endif
    Tcl_Release(interp);
    return TCL_OK;
}

#if TCL_MAJOR_VERSION >= 8
static int ip_rb_threadTkWaitObjCmd _((ClientData, Tcl_Interp *, int,
                                       Tcl_Obj *CONST []));
static int
ip_rb_threadTkWaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_rb_threadTkWaitCommand _((ClientData, Tcl_Interp *, int,
                                        char *[]));
static int
ip_rb_threadTkWaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    struct th_vwait_param *param;
    Tk_Window tkwin = (Tk_Window) clientData;
    Tk_Window window;
    int index;
    static CONST char *optionStrings[] = { "variable", "visibility", "window",
                                           (char *) NULL };
    enum options { TKWAIT_VARIABLE, TKWAIT_VISIBILITY, TKWAIT_WINDOW };
    char *nameString;
    int ret, dummy;
    int thr_crit_bup;
    volatile VALUE current_thread = rb_thread_current();

    DUMP1("Ruby's 'thread_tkwait' is called");

    if (rb_thread_alone() || eventloop_thread == current_thread) {
#if TCL_MAJOR_VERSION >= 8
        DUMP1("call ip_rbTkWaitObjCmd");
        return ip_rbTkWaitObjCmd(clientData, interp, objc, objv);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP1("call rb_VwaitCommand");
        return ip_rbTkWaitCommand(clientData, interp, objc, objv);
#endif
    }

    Tcl_Preserve(interp);
    Tcl_Preserve(tkwin);

    if (objc != 3) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "variable|visibility|window name");
#else
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         Tcl_GetStringFromObj(objv[0], &dummy), 
                         " variable|visibility|window name\"", 
                         (char *) NULL);
#else /* TCL_MAJOR_VERSION < 8 */
        Tcl_AppendResult(interp, "wrong number of arguments: should be \"",
                         objv[0], " variable|visibility|window name\"", 
                         (char *) NULL);
#endif

        rb_thread_critical = thr_crit_bup;
#endif

        Tcl_Release(tkwin);
        Tcl_Release(interp);
        return TCL_ERROR;
    }

#if TCL_MAJOR_VERSION >= 8
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;
    /*
    if (Tcl_GetIndexFromObj(interp, objv[1], 
                            (CONST84 char **)optionStrings, 
                            "option", 0, &index) != TCL_OK) {
        return TCL_ERROR;
    }
    */
    ret = Tcl_GetIndexFromObj(interp, objv[1], 
                              (CONST84 char **)optionStrings, 
                              "option", 0, &index);

    rb_thread_critical = thr_crit_bup;

    if (ret != TCL_OK) {
        Tcl_Release(tkwin);
        Tcl_Release(interp);
        return TCL_ERROR;
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        int c = objv[1][0];
        size_t length = strlen(objv[1]);

        if ((c == 'v') && (strncmp(objv[1], "variable", length) == 0)
            && (length >= 2)) {
            index = TKWAIT_VARIABLE;
        } else if ((c == 'v') && (strncmp(objv[1], "visibility", length) == 0)
                   && (length >= 2)) {
            index = TKWAIT_VISIBILITY;
        } else if ((c == 'w') && (strncmp(objv[1], "window", length) == 0)) {
            index = TKWAIT_WINDOW;
        } else {
            Tcl_AppendResult(interp, "bad option \"", objv[1],
                             "\": must be variable, visibility, or window", 
                             (char *) NULL);
            Tcl_Release(tkwin);
            Tcl_Release(interp);
            return TCL_ERROR;
        }
    }
#endif

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

#if TCL_MAJOR_VERSION >= 8
    Tcl_IncrRefCount(objv[2]);
    /* nameString = Tcl_GetString(objv[2]); */
    nameString = Tcl_GetStringFromObj(objv[2], &dummy);
#else /* TCL_MAJOR_VERSION < 8 */
    nameString = objv[2];
#endif

    param = (struct th_vwait_param *)Tcl_Alloc(sizeof(struct th_vwait_param));
    Tcl_Preserve(param);
    param->thread = current_thread;
    param->done = 0;

    rb_thread_critical = thr_crit_bup;

    switch ((enum options) index) {
    case TKWAIT_VARIABLE:
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;
        /* 
        if (Tcl_TraceVar(interp, nameString,
                         TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                         rb_threadVwaitProc, (ClientData) param) != TCL_OK) {
            return TCL_ERROR;
        }
        */
        ret = Tcl_TraceVar(interp, nameString,
                         TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                         rb_threadVwaitProc, (ClientData) param);

        rb_thread_critical = thr_crit_bup;

        if (ret != TCL_OK) {
            Tcl_Release(param);
            Tcl_Free((char *)param);

#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif

            Tcl_Release(tkwin);
            Tcl_Release(interp);
            return TCL_ERROR;
        }

        /* if (!param->done) { */
        while(!param->done) {
            rb_thread_stop();
        }

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        if (param->done > 0) {
            Tcl_UntraceVar(interp, nameString,
                           TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                           rb_threadVwaitProc, (ClientData) param);
        }

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        rb_thread_critical = thr_crit_bup;

        break;

    case TKWAIT_VISIBILITY:
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        if (Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

        if (window == NULL) {
            rb_thread_critical = thr_crit_bup;

            Tcl_Release(param);
            Tcl_Free((char *)param);

#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif
            Tcl_Release(tkwin);
            Tcl_Release(interp);
            return TCL_ERROR;
        }
        Tcl_Preserve(window);

        Tk_CreateEventHandler(window,
                              VisibilityChangeMask|StructureNotifyMask,
                              rb_threadWaitVisibilityProc, (ClientData) param);

        rb_thread_critical = thr_crit_bup;

        /* if (!param->done) { */
        /*
        while(!param->done) {
            rb_thread_stop();
        }
        */
        while(param->done != TKWAIT_MODE_VISIBILITY) {
            if (param->done == TKWAIT_MODE_DESTROY) break;
            rb_thread_stop();
        }

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        /* when a window is destroyed, no need to call Tk_DeleteEventHandler */
        if (param->done != TKWAIT_MODE_DESTROY) {
            Tk_DeleteEventHandler(window,
                                  VisibilityChangeMask|StructureNotifyMask,
                                  rb_threadWaitVisibilityProc, 
                                  (ClientData) param);
        }

        if (param->done != 1) {
            Tcl_ResetResult(interp);
            Tcl_AppendResult(interp, "window \"", nameString,
                             "\" was deleted before its visibility changed",
                             (char *) NULL);

            rb_thread_critical = thr_crit_bup;

            Tcl_Release(window);

            Tcl_Release(param);
            Tcl_Free((char *)param);

#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif

            Tcl_Release(tkwin);
            Tcl_Release(interp);
            return TCL_ERROR;
        }

        Tcl_Release(window);

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        rb_thread_critical = thr_crit_bup;

        break;

    case TKWAIT_WINDOW:
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        if (Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        if (window == NULL) {
            rb_thread_critical = thr_crit_bup;

            Tcl_Release(param);
            Tcl_Free((char *)param);

            Tcl_Release(tkwin);
            Tcl_Release(interp);
            return TCL_ERROR;
        }

        Tcl_Preserve(window);

        Tk_CreateEventHandler(window, StructureNotifyMask,
                              rb_threadWaitWindowProc, (ClientData) param);

        rb_thread_critical = thr_crit_bup;

        /* if (!param->done) { */
        /* 
        while(!param->done) {
            rb_thread_stop();
        }
        */
        while(param->done != TKWAIT_MODE_DESTROY) {
            rb_thread_stop();
        }

        Tcl_Release(window);

        /* when a window is destroyed, no need to call Tk_DeleteEventHandler
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        Tk_DeleteEventHandler(window, StructureNotifyMask,
                              rb_threadWaitWindowProc, (ClientData) param);

        rb_thread_critical = thr_crit_bup;
        */

        break;
    } /* end of 'switch' statement */

    Tcl_Release(param);
    Tcl_Free((char *)param);

    /*
     * Clear out the interpreter's result, since it may have been set
     * by event handlers.
     */

    Tcl_ResetResult(interp);

    Tcl_Release(tkwin);
    Tcl_Release(interp);
    return TCL_OK;
}

static VALUE
ip_thread_vwait(self, var)
    VALUE self;
    VALUE var;
{
    VALUE argv[2];
    volatile VALUE cmd_str = rb_str_new2("thread_vwait");

    argv[0] = cmd_str;
    argv[1] = var;
    return ip_invoke_real(2, argv, self);
}

static VALUE
ip_thread_tkwait(self, mode, target)
    VALUE self;
    VALUE mode;
    VALUE target;
{
    VALUE argv[3];
    volatile VALUE cmd_str = rb_str_new2("thread_tkwait");

    argv[0] = cmd_str;
    argv[1] = mode;
    argv[2] = target;
    return ip_invoke_real(3, argv, self);
}

/* destroy interpreter */
VALUE del_root(ip)
    Tcl_Interp *ip;
{
    Tk_Window main_win;

    if (!Tcl_InterpDeleted(ip)) {
        Tcl_Preserve(ip);
        while((main_win = Tk_MainWindow(ip)) != (Tk_Window)NULL) {
          DUMP1("wait main_win is destroyed");
          Tk_DestroyWindow(main_win);
        }
        Tcl_Release(ip);
    }
    return Qnil;
}


static void
delete_slaves(ip)
    Tcl_Interp *ip;
{
    Tcl_Interp *slave;
    Tcl_Obj *slave_list, *elem;
    char *slave_name;
    int i, len;

    DUMP2("delete slaves of ip(%lx)", ip);

    Tcl_Preserve(ip);

    if (Tcl_Eval(ip, "info slaves") == TCL_ERROR) {
        DUMP2("ip(%lx) cannot get a list of slave IPs", ip);
        return;
    }

    slave_list = Tcl_GetObjResult(ip);
    Tcl_IncrRefCount(slave_list);

    if (Tcl_ListObjLength((Tcl_Interp*)NULL, slave_list, &len) == TCL_ERROR) {
        DUMP1("slave_list is not a list object");
        Tcl_DecrRefCount(slave_list);
        return;
    }

    for(i = 0; i < len; i++) {
        Tcl_ListObjIndex((Tcl_Interp*)NULL, slave_list, i, &elem);
        Tcl_IncrRefCount(elem);

        if (elem == (Tcl_Obj*)NULL) continue;

        /* get slave */
        slave_name = Tcl_GetString(elem);
        slave = Tcl_GetSlave(ip, slave_name);
        if (slave == (Tcl_Interp*)NULL) {
            DUMP2("slave \"%s\" does not exist", slave_name);
            continue;
        }

        Tcl_DecrRefCount(elem);

        Tcl_Preserve(slave);

#if TCL_MAJOR_VERSION < 8 || ( TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION < 4)
#else
        if (!Tcl_InterpDeleted(slave)) {
            Tcl_Eval(slave, "foreach i [after info] { after cancel $i }");
        }
#endif

        /* delete slaves of slave */
        delete_slaves(slave);

        /* delete slave */
        del_root(slave);
        while(!Tcl_InterpDeleted(slave)) {
            DUMP1("wait ip is deleted");
            Tcl_DeleteInterp(slave);
        }

        Tcl_Release(slave);
    }

    Tcl_DecrRefCount(slave_list);

    Tcl_Release(ip);
}

static void
ip_free(ptr)
    struct tcltkip *ptr;
{
    Tcl_CmdInfo info;
    int thr_crit_bup;

    DUMP2("free Tcl Interp %lx", ptr->ip);
    if (ptr) {
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        DUMP2("IP ref_count = %d", ptr->ref_count);

        if (!Tcl_InterpDeleted(ptr->ip)) {
            DUMP2("IP(%lx) is not deleted", ptr->ip);
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);

            delete_slaves(ptr->ip);

            Tcl_ResetResult(ptr->ip);

            if (Tcl_GetCommandInfo(ptr->ip, finalize_hook_name, &info)) {
                DUMP2("call finalize hook proc '%s'", finalize_hook_name);
                Tcl_Eval(ptr->ip, finalize_hook_name);
            }

#if TCL_MAJOR_VERSION < 8 || ( TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION < 4)
#else
            if (!Tcl_InterpDeleted(ptr->ip)) {
                Tcl_Eval(ptr->ip, "foreach i [after info] {after cancel $i}");
            }
#endif

            del_root(ptr->ip);

            DUMP1("delete interp");
            while(!Tcl_InterpDeleted(ptr->ip)) {
                DUMP1("wait ip is deleted");
                Tcl_DeleteInterp(ptr->ip);
            }

            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
        }

        rbtk_release_ip(ptr);
        DUMP2("IP ref_count = %d", ptr->ref_count);

        free(ptr);

        rb_thread_critical = thr_crit_bup;
    }
    DUMP1("complete freeing Tcl Interp");
}

/* create and initialize interpreter */
static VALUE ip_alloc _((VALUE));
static VALUE
ip_alloc(self)
    VALUE self;
{
    return Data_Wrap_Struct(self, 0, ip_free, 0);
}

static VALUE
ip_init(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct tcltkip *ptr;        /* tcltkip data struct */
    VALUE argv0, opts;
    int cnt;
    int with_tk = 1;
    Tk_Window mainWin;

    /* security check */
    if (ruby_safe_level >= 4) {
        rb_raise(rb_eSecurityError, "Cannot create a TclTkIp object at level %d", ruby_safe_level);
    }

    /* create object */
    Data_Get_Struct(self, struct tcltkip, ptr);
    ptr = ALLOC(struct tcltkip);
    DATA_PTR(self) = ptr;
    ptr->ref_count = 0;
    ptr->allow_ruby_exit = 1;
    ptr->return_value = 0;

    /* from Tk_Main() */
    DUMP1("Tcl_CreateInterp");
    ptr->ip = Tcl_CreateInterp();
    if (ptr->ip == NULL) {
        rb_raise(rb_eRuntimeError, "fail to create a new Tk interpreter");
    }

    rbtk_preserve_ip(ptr);
    DUMP2("IP ref_count = %d", ptr->ref_count);
    current_interp = ptr->ip;

    ptr->has_orig_exit 
        = Tcl_GetCommandInfo(ptr->ip, "exit", &(ptr->orig_exit_info));

    /* from Tcl_AppInit() */
    DUMP1("Tcl_Init");
    if (Tcl_Init(ptr->ip) == TCL_ERROR) {
#if TCL_MAJOR_VERSION >= 8
        rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
        rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
#endif
    }

    /* set variables */
    cnt = rb_scan_args(argc, argv, "02", &argv0, &opts);
    switch(cnt) {
    case 2:
        /* options */
        if (NIL_P(opts) || opts == Qfalse) {
            /* without Tk */
            with_tk = 0;
        } else {
            /* Tcl_SetVar(ptr->ip, "argv", StringValuePtr(opts), 0); */
            Tcl_SetVar(ptr->ip, "argv", StringValuePtr(opts), TCL_GLOBAL_ONLY);
        }
    case 1:
        /* argv0 */
        if (!NIL_P(argv0)) {
            if (strncmp(StringValuePtr(argv0), "-e", 3) == 0
                || strncmp(StringValuePtr(argv0), "-", 2) == 0) {
                Tcl_SetVar(ptr->ip, "argv0", "ruby", TCL_GLOBAL_ONLY);
            } else {
                /* Tcl_SetVar(ptr->ip, "argv0", StringValuePtr(argv0), 0); */
                Tcl_SetVar(ptr->ip, "argv0", StringValuePtr(argv0), 
                           TCL_GLOBAL_ONLY);
            }
        }
    case 0:
        /* no args */
        ;
    }

    /* from Tcl_AppInit() */
    if (with_tk) {
        DUMP1("Tk_Init");
        if (Tk_Init(ptr->ip) == TCL_ERROR) {
#if TCL_MAJOR_VERSION >= 8
            rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
#endif
        }
        DUMP1("Tcl_StaticPackage(\"Tk\")");
#if TCL_MAJOR_VERSION >= 8
        Tcl_StaticPackage(ptr->ip, "Tk", Tk_Init, Tk_SafeInit);
#else /* TCL_MAJOR_VERSION < 8 */
        Tcl_StaticPackage(ptr->ip, "Tk", Tk_Init,
                          (Tcl_PackageInitProc *) NULL);
#endif
    }

    /* get main window */
    mainWin = Tk_MainWindow(ptr->ip);
    Tk_Preserve((ClientData)mainWin);

    /* add ruby command to the interpreter */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"ruby\")");
    Tcl_CreateObjCommand(ptr->ip, "ruby", ip_ruby_eval, (ClientData)NULL,
                         (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateObjCommand(\"ruby_eval\")");
    Tcl_CreateObjCommand(ptr->ip, "ruby_eval", ip_ruby_eval, (ClientData)NULL,
                         (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateObjCommand(\"ruby_cmd\")");
    Tcl_CreateObjCommand(ptr->ip, "ruby_cmd", ip_ruby_cmd, (ClientData)NULL,
                         (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"ruby\")");
    Tcl_CreateCommand(ptr->ip, "ruby", ip_ruby_eval, (ClientData)NULL,
                      (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateCommand(\"ruby_eval\")");
    Tcl_CreateCommand(ptr->ip, "ruby_eval", ip_ruby_eval, (ClientData)NULL,
                      (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateCommand(\"ruby_cmd\")");
    Tcl_CreateCommand(ptr->ip, "ruby_cmd", ip_ruby_cmd, (ClientData)NULL,
                      (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'interp_exit', 'ruby_exit' and replace 'exit' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"interp_exit\")");
    Tcl_CreateObjCommand(ptr->ip, "interp_exit", ip_InterpExitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateObjCommand(\"ruby_exit\")");
    Tcl_CreateObjCommand(ptr->ip, "ruby_exit", ip_RubyExitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateObjCommand(\"exit\") --> \"ruby_exit\"");
    Tcl_CreateObjCommand(ptr->ip, "exit", ip_RubyExitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"interp_exit\")");
    Tcl_CreateCommand(ptr->ip, "interp_exit", ip_InterpExitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateCommand(\"ruby_exit\")");
    Tcl_CreateCommand(ptr->ip, "ruby_exit", ip_RubyExitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
    DUMP1("Tcl_CreateCommand(\"exit\") --> \"ruby_exit\"");
    Tcl_CreateCommand(ptr->ip, "exit", ip_RubyExitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

#if 0  /* 
          Disable the following "update" and "thread_update". Bcause, 
          they don't work in a callback-proc. After calling update in 
          a callback-proc, the callback proc never be worked. 
          If the problem will be fixed in the future, may enable the 
          functions. 
       */
    /* replace 'update' command */
# if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"update\")");
    Tcl_CreateObjCommand(ptr->ip, "update", ip_rbUpdateObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
# else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"update\")");
    Tcl_CreateCommand(ptr->ip, "update", ip_rbUpdateCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
# endif

    /* add 'thread_update' command */
# if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_update\")");
    Tcl_CreateObjCommand(ptr->ip, "thread_update", ip_rb_threadUpdateObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
# else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"thread_update\")");
    Tcl_CreateCommand(ptr->ip, "thread_update", ip_rb_threadUpdateCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
# endif
#endif

    /* replace 'vwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"vwait\")");
    Tcl_CreateObjCommand(ptr->ip, "vwait", ip_rbVwaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"vwait\")");
    Tcl_CreateCommand(ptr->ip, "vwait", ip_rbVwaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* replace 'tkwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"tkwait\")");
    Tcl_CreateObjCommand(ptr->ip, "tkwait", ip_rbTkWaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"tkwait\")");
    Tcl_CreateCommand(ptr->ip, "tkwait", ip_rbTkWaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'thread_vwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_vwait\")");
    Tcl_CreateObjCommand(ptr->ip, "thread_vwait", ip_rb_threadVwaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"thread_vwait\")");
    Tcl_CreateCommand(ptr->ip, "thread_vwait", ip_rb_threadVwaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'thread_tkwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_tkwait\")");
    Tcl_CreateObjCommand(ptr->ip, "thread_tkwait", ip_rb_threadTkWaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"thread_tkwait\")");
    Tcl_CreateCommand(ptr->ip, "thread_tkwait", ip_rb_threadTkWaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    Tk_Release((ClientData)mainWin);

    return self;
}

static VALUE
ip_create_slave(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct tcltkip *master = get_ip(self);
    struct tcltkip *slave = ALLOC(struct tcltkip);
    VALUE safemode;
    VALUE name;
    int safe;
    int thr_crit_bup;
    Tk_Window mainWin;

    /* safe-mode check */
    if (rb_scan_args(argc, argv, "11", &name, &safemode) == 1) {
        safemode = Qfalse;
    }
    if (Tcl_IsSafe(master->ip) == 1) {
        safe = 1;
    } else if (safemode == Qfalse || NIL_P(safemode)) {
        safe = 0;
        rb_secure(4);
    } else {
        safe = 1;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* ip is deleted? */
    if (Tcl_InterpDeleted(master->ip)) {
        DUMP1("master-ip is deleted");
        rb_thread_critical = thr_crit_bup;
        rb_raise(rb_eRuntimeError, "deleted master cannot create a new slave interpreter");
    }

    /* create slave-ip */
    slave->ref_count = 0;
    slave->allow_ruby_exit = 0;
    slave->return_value = 0;

    slave->ip = Tcl_CreateSlave(master->ip, StringValuePtr(name), safe);
    if (slave->ip == NULL) {
        rb_thread_critical = thr_crit_bup;
        rb_raise(rb_eRuntimeError, "fail to create the new slave interpreter");
    }
    rbtk_preserve_ip(slave);

    slave->has_orig_exit 
        = Tcl_GetCommandInfo(slave->ip, "exit", &(slave->orig_exit_info));

    /* replace 'exit' command --> 'interp_exit' command */
    mainWin = Tk_MainWindow(slave->ip);
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateObjCommand(slave->ip, "exit", ip_InterpExitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateCommand(slave->ip, "exit", ip_InterpExitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    rb_thread_critical = thr_crit_bup;

    return Data_Wrap_Struct(CLASS_OF(self), 0, ip_free, slave);
}

/* make ip "safe" */
static VALUE
ip_make_safe(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    Tk_Window mainWin;
    
    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    if (Tcl_MakeSafe(ptr->ip) == TCL_ERROR) {
#if TCL_MAJOR_VERSION >= 8
        rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
        rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
#endif
    }

    ptr->allow_ruby_exit = 0;

    /* replace 'exit' command --> 'interp_exit' command */
    mainWin = Tk_MainWindow(ptr->ip);
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateObjCommand(ptr->ip, "exit", ip_InterpExitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateCommand(ptr->ip, "exit", ip_InterpExitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    return self;
}

/* is safe? */
static VALUE
ip_is_safe_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    
    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    if (Tcl_IsSafe(ptr->ip)) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/* allow_ruby_exit? */
static VALUE
ip_allow_ruby_exit_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    
    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    if (ptr->allow_ruby_exit) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

/* allow_ruby_exit = mode */
static VALUE
ip_allow_ruby_exit_set(self, val)
    VALUE self, val;
{
    struct tcltkip *ptr = get_ip(self);
    Tk_Window mainWin;

    rb_secure(4);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    if (Tcl_IsSafe(ptr->ip)) {
        rb_raise(rb_eSecurityError, 
                 "insecure operation on a safe interpreter");
    }

    mainWin = Tk_MainWindow(ptr->ip);

    if (RTEST(val)) {
        ptr->allow_ruby_exit = 1;
#if TCL_MAJOR_VERSION >= 8
        DUMP1("Tcl_CreateObjCommand(\"exit\") --> \"ruby_exit\"");
        Tcl_CreateObjCommand(ptr->ip, "exit", ip_RubyExitObjCmd, 
                             (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP1("Tcl_CreateCommand(\"exit\") --> \"ruby_exit\"");
        Tcl_CreateCommand(ptr->ip, "exit", ip_RubyExitCommand, 
                          (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif
        return Qtrue;

    } else {
        ptr->allow_ruby_exit = 0;
#if TCL_MAJOR_VERSION >= 8
        DUMP1("Tcl_CreateObjCommand(\"exit\") --> \"interp_exit\"");
        Tcl_CreateObjCommand(ptr->ip, "exit", ip_InterpExitObjCmd, 
                             (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP1("Tcl_CreateCommand(\"exit\") --> \"interp_exit\"");
        Tcl_CreateCommand(ptr->ip, "exit", ip_InterpExitCommand, 
                          (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif
        return Qfalse;
    }
}

/* delete interpreter */
static VALUE
ip_delete(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    /* Tcl_Preserve(ptr->ip); */
    rbtk_preserve_ip(ptr);

#if TCL_MAJOR_VERSION < 8 || ( TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION < 4)
#else
    if (!Tcl_InterpDeleted(ptr->ip)) {
        Tcl_Eval(ptr->ip, "foreach i [after info] { after cancel $i }");
    }
#endif

    del_root(ptr->ip);

    DUMP1("delete interp");
    while(!Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("wait ip is deleted");
        Tcl_DeleteInterp(ptr->ip);
    }

    /* Tcl_Release(ptr->ip); */
    rbtk_release_ip(ptr);

    return Qnil;
}

/* is deleted? */
static VALUE
ip_is_deleted_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    if (Tcl_InterpDeleted(ptr->ip)) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}


static VALUE
#ifdef HAVE_STDARG_PROTOTYPES
create_ip_exc(VALUE interp, VALUE exc, const char *fmt, ...)
#else
create_ip_exc(interp, exc, fmt, va_alist)
    VALUE interp:
    VALUE exc;
    const char *fmt;
    va_dcl
#endif
{
    va_list args;
    char buf[BUFSIZ];
    VALUE einfo;

    va_init_list(args,fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    buf[BUFSIZ - 1] = '\0';
    va_end(args);
    einfo = rb_exc_new2(exc, buf);
    rb_ivar_set(einfo, ID_at_interp, interp);
    Tcl_ResetResult(get_ip(interp)->ip);

    return einfo;
}

static VALUE
ip_get_result_string_obj(interp)
    Tcl_Interp *interp;
{
#if TCL_MAJOR_VERSION >= 8
    int len;
    char *s;

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
    s = Tcl_GetStringFromObj(Tcl_GetObjResult(interp), &len);
    return(rb_tainted_str_new(s, len));

# else /* TCL_VERSION >= 8.1 */
    volatile VALUE strval;
    Tcl_Obj *retobj = Tcl_GetObjResult(interp);
    int thr_crit_bup;

    Tcl_IncrRefCount(retobj);

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (Tcl_GetCharLength(retobj) != Tcl_UniCharLen(Tcl_GetUnicode(retobj))) {
        /* possibly binary string */
        s = Tcl_GetByteArrayFromObj(retobj, &len);
        strval = rb_tainted_str_new(s, len);
        rb_ivar_set(strval, ID_at_enc, rb_str_new2("binary"));
    } else {
        /* possibly text string */
        s = Tcl_GetStringFromObj(retobj, &len);
        strval = rb_tainted_str_new(s, len);
    }

    rb_thread_critical = thr_crit_bup;

    Tcl_DecrRefCount(retobj);

    return(strval);

# endif
#else /* TCL_MAJOR_VERSION < 8 */
    return(rb_tainted_str_new2(interp->result));
#endif
}

/* eval string in tcl by Tcl_Eval() */
static VALUE
ip_eval_real(self, cmd_str, cmd_len)
    VALUE self;
    char *cmd_str;
    int  cmd_len;
{
    volatile VALUE ret;
    char *s;
    int  len;
    struct tcltkip *ptr = get_ip(self);
    int thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
    /* call Tcl_EvalObj() */
    {
      Tcl_Obj *cmd;

      thr_crit_bup = rb_thread_critical;
      rb_thread_critical = Qtrue;

      cmd = Tcl_NewStringObj(cmd_str, cmd_len);
      Tcl_IncrRefCount(cmd);

      /* ip is deleted? */
      if (Tcl_InterpDeleted(ptr->ip)) {
          DUMP1("ip is deleted");
          Tcl_DecrRefCount(cmd);
          rb_thread_critical = thr_crit_bup;
          ptr->return_value = TCL_OK;
          return rb_tainted_str_new2("");
      } else {
          /* Tcl_Preserve(ptr->ip); */
          rbtk_preserve_ip(ptr);
          
          ptr->return_value = Tcl_EvalObj(ptr->ip, cmd);
          /* ptr->return_value = Tcl_GlobalEvalObj(ptr->ip, cmd); */
      }

      Tcl_DecrRefCount(cmd);

    }

    if (ptr->return_value == TCL_ERROR) {
        volatile VALUE exc;
        exc = create_ip_exc(self, rb_eRuntimeError, 
                            "%s", Tcl_GetStringResult(ptr->ip));
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);

        rb_thread_critical = thr_crit_bup;
        rb_exc_raise(exc);
    }
    DUMP2("(TCL_Eval result) %d", ptr->return_value);

    /* pass back the result (as string) */
    ret =  ip_get_result_string_obj(ptr->ip);
    /* Tcl_Release(ptr->ip); */
    rbtk_release_ip(ptr);
    rb_thread_critical = thr_crit_bup;
    return ret;

#else /* TCL_MAJOR_VERSION < 8 */
    DUMP2("Tcl_Eval(%s)", cmd_str);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        ptr->return_value = TCL_OK;
        return rb_tainted_str_new2("");
    } else {
        /* Tcl_Preserve(ptr->ip); */
        rbtk_preserve_ip(ptr);
        ptr->return_value = Tcl_Eval(ptr->ip, cmd_str);
        /* ptr->return_value = Tcl_GlobalEval(ptr->ip, cmd_str); */
    }

    if (ptr->return_value == TCL_ERROR) {
        volatile VALUE exc;
        exc = create_ip_exc(self, rb_eRuntimeError, "%s", ptr->ip->result);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_exc_raise(exc);
    }
    DUMP2("(TCL_Eval result) %d", ptr->return_value);

    /* pass back the result (as string) */
    ret =  ip_get_result_string_obj(ptr->ip);
    /* Tcl_Release(ptr->ip); */
    rbtk_release_ip(ptr);
    return ret;
#endif
}

static VALUE
evq_safelevel_handler(arg, evq)
    VALUE arg;
    VALUE evq;
{
    struct eval_queue *q;

    Data_Get_Struct(evq, struct eval_queue, q);
    DUMP2("(safe-level handler) $SAFE = %d", q->safe_level);
    rb_set_safe_level(q->safe_level);
    return ip_eval_real(q->interp, q->str, q->len);
}

int eval_queue_handler _((Tcl_Event *, int));
int
eval_queue_handler(evPtr, flags)
    Tcl_Event *evPtr;
    int flags;
{
    struct eval_queue *q = (struct eval_queue *)evPtr;
    volatile VALUE ret;
    volatile VALUE q_dat;

    DUMP2("do_eval_queue_handler : evPtr = %p", evPtr);
    DUMP2("eval queue_thread : %lx", rb_thread_current());
    DUMP2("added by thread : %lx", q->thread);

    if (*(q->done)) {
        DUMP1("processed by another event-loop");
        return 0;
    } else {
        DUMP1("process it on current event-loop");
    }

    /* process it */
    *(q->done) = 1;

    /* check safe-level */
    if (rb_safe_level() != q->safe_level) {
#ifdef HAVE_NATIVETHREAD
        if (!is_ruby_native_thread()) {
            rb_bug("cross-thread violation on eval_queue_handler()");
        }
#endif
        /* q_dat = Data_Wrap_Struct(rb_cData,0,0,q); */
        q_dat = Data_Wrap_Struct(rb_cData,eval_queue_mark,0,q);
        ret = rb_funcall(rb_proc_new(evq_safelevel_handler, q_dat), 
                         ID_call, 0);
        rb_gc_force_recycle(q_dat);
    } else {
        DUMP2("call eval_real (for caller thread:%lx)", q->thread);
        DUMP2("call eval_real (current thread:%lx)", rb_thread_current());
        ret = ip_eval_real(q->interp, q->str, q->len);
    }

    /* set result */
    RARRAY(q->result)->ptr[0] = ret;

    /* complete */
    *(q->done) = -1;

    /* back to caller */
    DUMP2("back to caller (caller thread:%lx)", q->thread);
    DUMP2("               (current thread:%lx)", rb_thread_current());
    rb_thread_run(q->thread);
    DUMP1("finish back to caller");

    /* end of handler : remove it */
    return 1;
}

static VALUE
ip_eval(self, str)
    VALUE self;
    VALUE str;
{
    struct eval_queue *evq;
    char *eval_str;
    int  *alloc_done;
    int  thr_crit_bup;
    volatile VALUE current = rb_thread_current();
    volatile VALUE ip_obj = self;
    volatile VALUE result;
    volatile VALUE ret;
    Tcl_QueuePosition position;

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;
    StringValue(str);
    rb_thread_critical = thr_crit_bup;

    if (eventloop_thread == 0 || current == eventloop_thread) {
        if (eventloop_thread) {
            DUMP2("eval from current eventloop %lx", current);
        } else {
            DUMP2("eval from thread:%lx but no eventloop", current);
        }
        result = ip_eval_real(self, RSTRING(str)->ptr, RSTRING(str)->len);
        if (rb_obj_is_kind_of(result, rb_eException)) {
            rb_exc_raise(result);
        }
        return result;
    }

    DUMP2("eval from thread %lx (NOT current eventloop)", current);

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* allocate memory (protected from Tcl_ServiceEvent) */
    alloc_done = (int*)ALLOC(int);
    *alloc_done = 0;

    eval_str = ALLOC_N(char, RSTRING(str)->len + 1);
    strncpy(eval_str, RSTRING(str)->ptr, RSTRING(str)->len);
    eval_str[RSTRING(str)->len] = 0;

    /* allocate memory (freed by Tcl_ServiceEvent) */
    evq = (struct eval_queue *)Tcl_Alloc(sizeof(struct eval_queue));
    Tcl_Preserve(evq);

    /* allocate result obj */
    result = rb_ary_new2(1);
    RARRAY(result)->ptr[0] = Qnil;
    RARRAY(result)->len = 1;

    /* construct event data */
    evq->done = alloc_done;
    evq->str = eval_str;
    evq->len = RSTRING(str)->len;
    evq->interp = ip_obj;
    evq->result = result;
    evq->thread = current;
    evq->safe_level = rb_safe_level();
    evq->ev.proc = eval_queue_handler;
    position = TCL_QUEUE_TAIL;

    /* add the handler to Tcl event queue */
    DUMP1("add handler");
    Tcl_QueueEvent(&(evq->ev), position);

    rb_thread_critical = thr_crit_bup;

    /* wait for the handler to be processed */
    DUMP2("wait for handler (current thread:%lx)", current);
    while(*alloc_done >= 0) {
        rb_thread_stop();
    }
    DUMP2("back from handler (current thread:%lx)", current);

    /* get result & free allocated memory */
    ret = RARRAY(result)->ptr[0];

    free(alloc_done);
    free(eval_str);
    Tcl_Release(evq);

    if (rb_obj_is_kind_of(ret, rb_eException)) {
        rb_exc_raise(ret);
    }

    return ret;
}


/* restart Tk */
static VALUE
lib_restart(self)
    VALUE self;
{
    volatile VALUE exc;
    struct tcltkip *ptr = get_ip(self);
    int  thr_crit_bup;

    rb_secure(4);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* Tcl_Preserve(ptr->ip); */
    rbtk_preserve_ip(ptr);

    /* destroy the root wdiget */
    ptr->return_value = Tcl_Eval(ptr->ip, "destroy .");
    /* ignore ERROR */
    DUMP2("(TCL_Eval result) %d", ptr->return_value);
    Tcl_ResetResult(ptr->ip);

    /* delete namespace ( tested on tk8.4.5 ) */
    ptr->return_value = Tcl_Eval(ptr->ip, "namespace delete ::tk::msgcat");
    /* ignore ERROR */
    DUMP2("(TCL_Eval result) %d", ptr->return_value);
    Tcl_ResetResult(ptr->ip);

    /* delete trace proc ( tested on tk8.4.5 ) */
    ptr->return_value = Tcl_Eval(ptr->ip, "trace vdelete ::tk_strictMotif w ::tk::EventMotifBindings");
    /* ignore ERROR */
    DUMP2("(TCL_Eval result) %d", ptr->return_value);
    Tcl_ResetResult(ptr->ip);

    /* execute Tk_Init of Tk_SafeInit */
#if TCL_MAJOR_VERSION >= 8
    if (Tcl_IsSafe(ptr->ip)) {
        DUMP1("Tk_SafeInit");
        if (Tk_SafeInit(ptr->ip) == TCL_ERROR) {
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }
    } else {
        DUMP1("Tk_Init");
        if (Tk_Init(ptr->ip) == TCL_ERROR) {
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }
    }
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tk_Init");
    if (Tk_Init(ptr->ip) == TCL_ERROR) {
        exc = rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_exc_raise(exc);
    }
#endif

    /* Tcl_Release(ptr->ip); */
    rbtk_release_ip(ptr);

    rb_thread_critical = thr_crit_bup;

    return Qnil;
}


static VALUE
ip_restart(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    rb_secure(4);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return Qnil;
    }
    return lib_restart(self);
}

static VALUE
lib_toUTF8_core(ip_obj, src, encodename)
    VALUE ip_obj;
    VALUE src;
    VALUE encodename;
{
    volatile VALUE str = src;

#ifdef TCL_UTF_MAX
    Tcl_Interp *interp;
    Tcl_Encoding encoding;
    Tcl_DString dstr;
    int taint_flag = OBJ_TAINTED(str);
    struct tcltkip *ptr;
    char *buf;
    int thr_crit_bup;

    if (NIL_P(ip_obj)) {
        interp = (Tcl_Interp *)NULL;
    } else {
        interp = get_ip(ip_obj)->ip;

        /* ip is deleted? */
        if (Tcl_InterpDeleted(interp)) {
            DUMP1("ip is deleted");
            interp = (Tcl_Interp *)NULL;
        }
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (NIL_P(encodename)) {
        if (TYPE(str) == T_STRING) {
            volatile VALUE enc;

            enc = Qnil;
            if (RTEST(rb_ivar_defined(str, ID_at_enc))) {
                enc = rb_ivar_get(str, ID_at_enc);
            }
            if (NIL_P(enc)) {
                if (NIL_P(ip_obj)) {
                    encoding = (Tcl_Encoding)NULL;
                } else {
                    if (RTEST(rb_ivar_defined(ip_obj, ID_at_enc))) {
                        enc = rb_ivar_get(ip_obj, ID_at_enc);
                    }
                    if (NIL_P(enc)) {
                        encoding = (Tcl_Encoding)NULL;
                    } else {
                        StringValue(enc);
                        encoding = Tcl_GetEncoding(interp, RSTRING(enc)->ptr);
                        if (encoding == (Tcl_Encoding)NULL) {
                            rb_warning("Tk-interp has unknown encoding information (@encoding:'%s')", RSTRING(enc)->ptr);
                        }
                    }
                }
            } else {
                StringValue(enc);
                if (strcmp(RSTRING(enc)->ptr, "binary") == 0) {
                    rb_thread_critical = thr_crit_bup;
                    return str;
                }
                encoding = Tcl_GetEncoding(interp, RSTRING(enc)->ptr);
                if (encoding == (Tcl_Encoding)NULL) {
                    rb_warning("string has unknown encoding information (@encoding:'%s')", RSTRING(enc)->ptr);
                }
            }
        } else {
            encoding = (Tcl_Encoding)NULL;
        }
    } else {
        StringValue(encodename);
        encoding = Tcl_GetEncoding(interp, RSTRING(encodename)->ptr);
        if (encoding == (Tcl_Encoding)NULL) {
            /*
            rb_warning("unknown encoding name '%s'", 
                       RSTRING(encodename)->ptr);
            */
            rb_raise(rb_eArgError, "unknown encoding name '%s'", 
                     RSTRING(encodename)->ptr);
        }
    }

    StringValue(str);
    if (!RSTRING(str)->len) {
        rb_thread_critical = thr_crit_bup;
        return str;
    }

    buf = ALLOC_N(char,(RSTRING(str)->len)+1);
    strncpy(buf, RSTRING(str)->ptr, RSTRING(str)->len);
    buf[RSTRING(str)->len] = 0;

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    /* Tcl_ExternalToUtfDString(encoding,buf,strlen(buf),&dstr); */
    Tcl_ExternalToUtfDString(encoding, buf, RSTRING(str)->len, &dstr);

    /* str = rb_tainted_str_new2(Tcl_DStringValue(&dstr)); */
    str = rb_str_new2(Tcl_DStringValue(&dstr));
    rb_ivar_set(str, ID_at_enc, rb_tainted_str_new2("utf-8"));
    if (taint_flag) OBJ_TAINT(str);

    if (encoding != (Tcl_Encoding)NULL) {
        Tcl_FreeEncoding(encoding);
    }
    Tcl_DStringFree(&dstr);

    free(buf);

    rb_thread_critical = thr_crit_bup;
#endif

    return str;
}

static VALUE
lib_toUTF8(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    VALUE str, encodename;

    if (rb_scan_args(argc, argv, "11", &str, &encodename) == 1) {
        encodename = Qnil;
    }
    return lib_toUTF8_core(Qnil, str, encodename);
}

static VALUE
ip_toUTF8(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    VALUE str, encodename;

    if (rb_scan_args(argc, argv, "11", &str, &encodename) == 1) {
        encodename = Qnil;
    }
    return lib_toUTF8_core(self, str, encodename);
}

static VALUE
lib_fromUTF8_core(ip_obj, src, encodename)
    VALUE ip_obj;
    VALUE src;
    VALUE encodename;
{
    volatile VALUE str = src;

#ifdef TCL_UTF_MAX
    Tcl_Interp *interp;
    Tcl_Encoding encoding;
    Tcl_DString dstr;
    int taint_flag = OBJ_TAINTED(str);
    char *buf;
    int thr_crit_bup;

    if (NIL_P(ip_obj)) {
        interp = (Tcl_Interp *)NULL;
    } else {
        interp = get_ip(ip_obj)->ip;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (NIL_P(encodename)) {
        volatile VALUE enc;

        if (TYPE(str) == T_STRING) {
            enc = Qnil;
            if (RTEST(rb_ivar_defined(str, ID_at_enc))) {
                enc = rb_ivar_get(str, ID_at_enc);
            }
            if (!NIL_P(enc) && strcmp(StringValuePtr(enc), "binary") == 0) {
                rb_thread_critical = thr_crit_bup;
                return str;
            }
        }

        if (NIL_P(ip_obj)) {
            encoding = (Tcl_Encoding)NULL;
        } else {
            enc = Qnil;
            if (RTEST(rb_ivar_defined(ip_obj, ID_at_enc))) {
                enc = rb_ivar_get(ip_obj, ID_at_enc);
            }
            if (NIL_P(enc)) {
                encoding = (Tcl_Encoding)NULL;
            } else {
                StringValue(enc);
                encoding = Tcl_GetEncoding(interp, RSTRING(enc)->ptr);
                if (encoding == (Tcl_Encoding)NULL) {
                    rb_warning("Tk-interp has unknown encoding information (@encoding:'%s')", RSTRING(enc)->ptr);
                } else {
                  encodename = rb_obj_dup(enc);
                }
            }
        }

    } else {
        StringValue(encodename);

        if (strcmp(RSTRING(encodename)->ptr, "binary") == 0) {
            char *s;
            int  len;

            s = Tcl_GetByteArrayFromObj(Tcl_NewStringObj(RSTRING(str)->ptr, 
                                                         RSTRING(str)->len), 
                                        &len);
            str = rb_tainted_str_new(s, len);
            rb_ivar_set(str, ID_at_enc, rb_tainted_str_new2("binary"));

            rb_thread_critical = thr_crit_bup;
            return str;
        }

        encoding = Tcl_GetEncoding(interp, RSTRING(encodename)->ptr);
        if (encoding == (Tcl_Encoding)NULL) {
            /* 
            rb_warning("unknown encoding name '%s'", 
                       RSTRING(encodename)->ptr);
            encodename = Qnil;
            */
            rb_raise(rb_eArgError, "unknown encoding name '%s'", 
                     RSTRING(encodename)->ptr);
        }
    }

    StringValue(str);

    if (RSTRING(str)->len == 0) {
        rb_thread_critical = thr_crit_bup;
        return rb_tainted_str_new2("");
    }

    buf = ALLOC_N(char,strlen(RSTRING(str)->ptr)+1);
    strncpy(buf, RSTRING(str)->ptr, RSTRING(str)->len);
    buf[RSTRING(str)->len] = 0;

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    /* Tcl_UtfToExternalDString(encoding,buf,strlen(buf),&dstr); */
    Tcl_UtfToExternalDString(encoding,buf,RSTRING(str)->len,&dstr);

    /* str = rb_tainted_str_new2(Tcl_DStringValue(&dstr)); */
    str = rb_str_new2(Tcl_DStringValue(&dstr));
    rb_ivar_set(str, ID_at_enc, encodename);

    if (taint_flag) OBJ_TAINT(str);

    if (encoding != (Tcl_Encoding)NULL) {
        Tcl_FreeEncoding(encoding);
    }
    Tcl_DStringFree(&dstr);

    free(buf);

    rb_thread_critical = thr_crit_bup;
#endif

    return str;
}

static VALUE
lib_fromUTF8(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    VALUE str, encodename;

    if (rb_scan_args(argc, argv, "11", &str, &encodename) == 1) {
        encodename = Qnil;
    }
    return lib_fromUTF8_core(Qnil, str, encodename);
}

static VALUE
ip_fromUTF8(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    VALUE str, encodename;

    if (rb_scan_args(argc, argv, "11", &str, &encodename) == 1) {
        encodename = Qnil;
    }
    return lib_fromUTF8_core(self, str, encodename);
}

static VALUE
lib_UTF_backslash_core(self, str, all_bs)
    VALUE self;
    VALUE str;
    int all_bs;
{
#ifdef TCL_UTF_MAX
    char *src_buf, *dst_buf, *ptr;
    int read_len = 0, dst_len = 0;
    int taint_flag = OBJ_TAINTED(str);
    int thr_crit_bup;

    StringValue(str);
    if (!RSTRING(str)->len) {
        return str;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    src_buf = ALLOC_N(char,(RSTRING(str)->len)+1);
    strncpy(src_buf, RSTRING(str)->ptr, RSTRING(str)->len);
    src_buf[RSTRING(str)->len] = 0;

    dst_buf = ALLOC_N(char,(RSTRING(str)->len)+1);

    ptr = src_buf;
    while(RSTRING(str)->len > ptr - src_buf) {
        if (*ptr == '\\' && (all_bs || *(ptr + 1) == 'u')) {
            dst_len += Tcl_UtfBackslash(ptr, &read_len, (dst_buf + dst_len));
            ptr += read_len;
        } else {
            *(dst_buf + (dst_len++)) = *(ptr++);
        }
    }

    str = rb_str_new(dst_buf, dst_len);
    if (taint_flag) OBJ_TAINT(str);

    free(src_buf);
    free(dst_buf);

    rb_thread_critical = thr_crit_bup;
#endif

    return str;
}

static VALUE
lib_UTF_backslash(self, str)
    VALUE self;
    VALUE str;
{
    return lib_UTF_backslash_core(self, str, 0);
}

static VALUE
lib_Tcl_backslash(self, str)
    VALUE self;
    VALUE str;
{
    return lib_UTF_backslash_core(self, str, 1);
}

#if TCL_MAJOR_VERSION >= 8
static VALUE
ip_invoke_core(interp, objc, objv)
    VALUE interp;
    int objc;
    Tcl_Obj **objv;
#else
static VALUE
ip_invoke_core(interp, argc, argv)
    VALUE interp;
    int argc;
    char **argv;
#endif
{
    struct tcltkip *ptr;
    int i;
    Tcl_CmdInfo info;
    char *cmd;
    char *s;
    int  len;
    int  thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
    int argc = objc;
    char **argv = (char **)NULL;
    Tcl_Obj *resultPtr;
#endif

    /* get the command name string */
#if TCL_MAJOR_VERSION >= 8
    cmd = Tcl_GetStringFromObj(objv[0], &len);
#else /* TCL_MAJOR_VERSION < 8 */
    cmd = argv[0];
#endif

    /* get the data struct */
    ptr = get_ip(interp);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return rb_tainted_str_new2("");
    }

    /* map from the command name to a C procedure */
    DUMP2("call Tcl_GetCommandInfo, %s", cmd);
    if (!Tcl_GetCommandInfo(ptr->ip, cmd, &info)) {
        DUMP1("error Tcl_GetCommandInfo");
        /* if (event_loop_abort_on_exc || cmd[0] != '.') { */
        if (event_loop_abort_on_exc > 0) {
            /*rb_ip_raise(obj,rb_eNameError,"invalid command name `%s'",cmd);*/
            return create_ip_exc(interp, rb_eNameError, 
                                 "invalid command name `%s'", cmd);
        } else {
            if (event_loop_abort_on_exc < 0) {
                rb_warning("invalid command name `%s' (ignore)", cmd);
            } else {
                rb_warn("invalid command name `%s' (ignore)", cmd);
            }
            Tcl_ResetResult(ptr->ip);
            return rb_tainted_str_new2("");
        }
    }
    DUMP1("end Tcl_GetCommandInfo");

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* memory allocation for arguments of this command */
#if TCL_MAJOR_VERSION >= 8
    if (!info.isNativeObjectProc) {
        /* string interface */
        argv = (char **)ALLOC_N(char *, argc+1);
        for (i = 0; i < argc; ++i) {
            argv[i] = Tcl_GetStringFromObj(objv[i], &len);
        }
        argv[argc] = (char *)NULL;
    }
#endif

    Tcl_ResetResult(ptr->ip);

    /* Invoke the C procedure */
#if TCL_MAJOR_VERSION >= 8
    if (info.isNativeObjectProc) {
        ptr->return_value = (*info.objProc)(info.objClientData, ptr->ip, 
                                            objc, objv);
#if 0
        /* get the string value from the result object */
        resultPtr = Tcl_GetObjResult(ptr->ip);
        Tcl_SetResult(ptr->ip, Tcl_GetStringFromObj(resultPtr, &len),
                      TCL_VOLATILE);
#endif
    }
    else
#endif
    {
#if TCL_MAJOR_VERSION >= 8
        ptr->return_value = (*info.proc)(info.clientData, ptr->ip, 
                                         argc, (CONST84 char **)argv);

        free(argv);

#else /* TCL_MAJOR_VERSION < 8 */
        ptr->return_value = (*info.proc)(info.clientData, ptr->ip, 
                                         argc, argv);
#endif
    }

    rb_thread_critical = thr_crit_bup;

    /* exception on mainloop */
    if (ptr->return_value == TCL_ERROR) {
        if (event_loop_abort_on_exc > 0 && !Tcl_InterpDeleted(ptr->ip)) {
#if TCL_MAJOR_VERSION >= 8
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "%s", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "%s", ptr->ip->result);
#endif
        } else {
            if (event_loop_abort_on_exc < 0) {
#if TCL_MAJOR_VERSION >= 8
                rb_warning("%s (ignore)", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
                rb_warning("%s (ignore)", ptr->ip->result);
#endif
            } else {
#if TCL_MAJOR_VERSION >= 8
                rb_warn("%s (ignore)", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
                rb_warn("%s (ignore)", ptr->ip->result);
#endif
            }
            Tcl_ResetResult(ptr->ip);
            return rb_tainted_str_new2("");
        }
    }

    /* pass back the result (as string) */
    return ip_get_result_string_obj(ptr->ip);
}


#if TCL_MAJOR_VERSION >= 8
static Tcl_Obj **
#else /* TCL_MAJOR_VERSION < 8 */
static char **
#endif
alloc_invoke_arguments(argc, argv)
    int argc;
    VALUE *argv;
{
    int i;
    VALUE v;
    char *s;
    int thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **av = (Tcl_Obj **)NULL;
    Tcl_Obj *resultPtr;
#else /* TCL_MAJOR_VERSION < 8 */
    char **av = (char **)NULL;
#endif

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* memory allocation */
#if TCL_MAJOR_VERSION >= 8
    av = (Tcl_Obj **)ALLOC_N(Tcl_Obj *, argc+1);
    for (i = 0; i < argc; ++i) {
        VALUE enc;

        v = argv[i];
        s = StringValuePtr(v);

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        av[i] = Tcl_NewStringObj(s, RSTRING(v)->len);
# else /* TCL_VERSION >= 8.1 */
        enc = Qnil;
        if (RTEST(rb_ivar_defined(v, ID_at_enc))) {
            enc = rb_ivar_get(v, ID_at_enc);
        }
        if (!NIL_P(enc) && strcmp(StringValuePtr(enc), "binary") == 0) {
            /* binary string */
            av[i] = Tcl_NewByteArrayObj(s, RSTRING(v)->len);
        } else if (strlen(s) != RSTRING(v)->len) {
            /* probably binary string */
            av[i] = Tcl_NewByteArrayObj(s, RSTRING(v)->len);
        } else {
            /* probably text string */
            av[i] = Tcl_NewStringObj(s, RSTRING(v)->len);
        }
# endif
        Tcl_IncrRefCount(av[i]);
    }
    av[argc] = (Tcl_Obj *)NULL;

#else /* TCL_MAJOR_VERSION < 8 */
    /* string interface */
    av = (char **)ALLOC_N(char *, argc+1);
    for (i = 0; i < argc; ++i) {
        v = argv[i];
        s = StringValuePtr(v);
        av[i] = ALLOC_N(char, strlen(s)+1);
        strcpy(av[i], s);
    }
    av[argc] = (char *)NULL;
#endif

    rb_thread_critical = thr_crit_bup;

    return av;
}

static void
free_invoke_arguments(argc, av)
    int argc;
#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **av;
#else /* TCL_MAJOR_VERSION < 8 */
    char **av;
#endif
{
    int i;

    for (i = 0; i < argc; ++i) {
#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(av[i]);
#else /* TCL_MAJOR_VERSION < 8 */
        free(av[i]);
#endif
    }
    free(av);
}

static VALUE
ip_invoke_real(argc, argv, interp)
    int argc;
    VALUE *argv;
    VALUE interp;
{
    VALUE v;
    struct tcltkip *ptr;        /* tcltkip data struct */
    int i;
    Tcl_CmdInfo info;
    char *s;
    int  len;
    int thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **av = (Tcl_Obj **)NULL;
    Tcl_Obj *resultPtr;
#else /* TCL_MAJOR_VERSION < 8 */
    char **av = (char **)NULL;
#endif

    DUMP2("invoke_real called by thread:%lx", rb_thread_current());

    /* allocate memory for arguments */
    av = alloc_invoke_arguments(argc, argv);

    /* get the data struct */
    ptr = get_ip(interp);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return rb_tainted_str_new2("");
    }

    /* Invoke the C procedure */
    Tcl_ResetResult(ptr->ip);
    v = ip_invoke_core(interp, argc, av);

    /* free allocated memory */
    free_invoke_arguments(argc, av);

    return v;
}

VALUE
ivq_safelevel_handler(arg, ivq)
    VALUE arg;
    VALUE ivq;
{
    struct invoke_queue *q;

    Data_Get_Struct(ivq, struct invoke_queue, q);
    DUMP2("(safe-level handler) $SAFE = %d", q->safe_level);
    rb_set_safe_level(q->safe_level);
    return ip_invoke_core(q->interp, q->argc, q->argv);
}

int invoke_queue_handler _((Tcl_Event *, int));
int
invoke_queue_handler(evPtr, flags)
    Tcl_Event *evPtr;
    int flags;
{
    struct invoke_queue *q = (struct invoke_queue *)evPtr;
    volatile VALUE ret;
    volatile VALUE q_dat;

    DUMP2("do_invoke_queue_handler : evPtr = %p", evPtr);
    DUMP2("invoke queue_thread : %lx", rb_thread_current());
    DUMP2("added by thread : %lx", q->thread);

    if (*(q->done)) {
        DUMP1("processed by another event-loop");
        return 0;
    } else {
        DUMP1("process it on current event-loop");
    }

    /* process it */
    *(q->done) = 1;

    /* check safe-level */
    if (rb_safe_level() != q->safe_level) {
        /* q_dat = Data_Wrap_Struct(rb_cData,0,0,q); */
        q_dat = Data_Wrap_Struct(rb_cData,invoke_queue_mark,0,q);
        ret = rb_funcall(rb_proc_new(ivq_safelevel_handler, q_dat), 
                         ID_call, 0);
        rb_gc_force_recycle(q_dat);
    } else {
        DUMP2("call invoke_real (for caller thread:%lx)", q->thread);
        DUMP2("call invoke_real (current thread:%lx)", rb_thread_current());
        ret = ip_invoke_core(q->interp, q->argc, q->argv);
    }

    /* set result */
    RARRAY(q->result)->ptr[0] = ret;

    /* complete */
    *(q->done) = -1;

    /* back to caller */
    DUMP2("back to caller (caller thread:%lx)", q->thread);
    DUMP2("               (current thread:%lx)", rb_thread_current());
    rb_thread_run(q->thread);
    DUMP1("finish back to caller");

    /* end of handler : remove it */
    return 1;
}

static VALUE
ip_invoke_with_position(argc, argv, obj, position)
    int argc;
    VALUE *argv;
    VALUE obj;
    Tcl_QueuePosition position;
{
    struct invoke_queue *ivq;
    char *s;
    int  len;
    int  i;
    int  *alloc_done;
    int  thr_crit_bup;
    volatile VALUE current = rb_thread_current();
    volatile VALUE ip_obj = obj;
    volatile VALUE result;
    volatile VALUE ret;

#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **av = (Tcl_Obj **)NULL;
#else /* TCL_MAJOR_VERSION < 8 */
    char **av = (char **)NULL;
#endif

    if (argc < 1) {
        rb_raise(rb_eArgError, "command name missing");
    }
    if (eventloop_thread == 0 || current == eventloop_thread) {
        if (eventloop_thread) {
            DUMP2("invoke from current eventloop %lx", current);
        } else {
            DUMP2("invoke from thread:%lx but no eventloop", current);
        }
        result = ip_invoke_real(argc, argv, ip_obj);
        if (rb_obj_is_kind_of(result, rb_eException)) {
            rb_exc_raise(result);
        }
        return result;
    }

    DUMP2("invoke from thread %lx (NOT current eventloop)", current);

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* allocate memory (for arguments) */
    av = alloc_invoke_arguments(argc, argv);

    /* allocate memory (keep result) */
    alloc_done = (int*)ALLOC(int);
    *alloc_done = 0;

    /* allocate memory (freed by Tcl_ServiceEvent) */
    ivq = (struct invoke_queue *)Tcl_Alloc(sizeof(struct invoke_queue));
    Tcl_Preserve(ivq);

    /* allocate result obj */
    result = rb_ary_new2(1);
    RARRAY(result)->ptr[0] = Qnil;
    RARRAY(result)->len = 1;

    /* construct event data */
    ivq->done = alloc_done;
    ivq->argc = argc;
    ivq->argv = av;
    ivq->interp = ip_obj;
    ivq->result = result;
    ivq->thread = current;
    ivq->safe_level = rb_safe_level();
    ivq->ev.proc = invoke_queue_handler;

    /* add the handler to Tcl event queue */
    DUMP1("add handler");
    Tcl_QueueEvent(&(ivq->ev), position);

    rb_thread_critical = thr_crit_bup;

    /* wait for the handler to be processed */
    DUMP2("wait for handler (current thread:%lx)", current);
    while(*alloc_done >= 0) {
        rb_thread_stop();
    }
    DUMP2("back from handler (current thread:%lx)", current);

    /* get result & free allocated memory */
    ret = RARRAY(result)->ptr[0];
    free(alloc_done);

    Tcl_Release(ivq);

    /* free allocated memory */
    free_invoke_arguments(argc, av);

    /* exception? */
    if (rb_obj_is_kind_of(ret, rb_eException)) {
        DUMP1("raise exception");
        rb_exc_raise(ret);
    }

    DUMP1("exit ip_invoke");
    return ret;
}


/* get return code from Tcl_Eval() */
static VALUE
ip_retval(self)
    VALUE self;
{
    struct tcltkip *ptr;        /* tcltkip data struct */

    /* get the data strcut */
    ptr = get_ip(self);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return rb_tainted_str_new2("");
    }

    return (INT2FIX(ptr->return_value));
}

static VALUE
ip_invoke(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    return ip_invoke_with_position(argc, argv, obj, TCL_QUEUE_TAIL);
}

static VALUE
ip_invoke_immediate(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    return ip_invoke_with_position(argc, argv, obj, TCL_QUEUE_HEAD);
}

/* access Tcl variables */
static VALUE
ip_get_variable(self, varname_arg, flag_arg)
    VALUE self;
    VALUE varname_arg;
    VALUE flag_arg;
{
    struct tcltkip *ptr = get_ip(self);
    int thr_crit_bup;
    volatile VALUE varname, flag;

    varname = varname_arg;
    flag    = flag_arg;

    StringValue(varname);

#if TCL_MAJOR_VERSION >= 8
    {
        Tcl_Obj *nameobj, *ret;
        char *s;
        int  len;
        volatile VALUE strval;

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        nameobj = Tcl_NewStringObj(RSTRING(varname)->ptr, 
                                   RSTRING(varname)->len);
        Tcl_IncrRefCount(nameobj);

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            Tcl_DecrRefCount(nameobj);
            rb_thread_critical = thr_crit_bup;
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_ObjGetVar2(ptr->ip, nameobj, (Tcl_Obj*)NULL, 
                                 FIX2INT(flag));
        }

        Tcl_DecrRefCount(nameobj);

        if (ret == (Tcl_Obj*)NULL) {
            volatile VALUE exc;
#if TCL_MAJOR_VERSION >= 8
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            exc = rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
#endif
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }

        Tcl_IncrRefCount(ret);

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        s = Tcl_GetStringFromObj(ret, &len);
        strval = rb_tainted_str_new(s, len);
        Tcl_DecrRefCount(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;
        return(strval);

# else /* TCL_VERSION >= 8.1 */
        if (Tcl_GetCharLength(ret) 
            != Tcl_UniCharLen(Tcl_GetUnicode(ret))) {
            /* possibly binary string */
            s = Tcl_GetByteArrayFromObj(ret, &len);
            strval = rb_tainted_str_new(s, len);
            rb_ivar_set(strval, ID_at_enc, rb_tainted_str_new2("binary"));
        } else {
            /* possibly text string */
            s = Tcl_GetStringFromObj(ret, &len);
            strval = rb_tainted_str_new(s, len);
        }

        Tcl_DecrRefCount(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
# endif
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        char *ret;

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_GetVar2(ptr->ip, RSTRING(varname)->ptr, 
                              (char*)NULL, FIX2INT(flag));
        }

        if (ret == (char*)NULL) {
            volatile VALUE exc;
#if TCL_MAJOR_VERSION >= 8
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            exc = rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
#endif
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }

        strval = rb_tainted_str_new2(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
    }
#endif
}

static VALUE
ip_get_variable2(self, varname_arg, index_arg, flag_arg)
    VALUE self;
    VALUE varname_arg;
    VALUE index_arg;
    VALUE flag_arg;
{
    struct tcltkip *ptr = get_ip(self);
    int thr_crit_bup;
    volatile VALUE varname, index, flag;

    if (NIL_P(index_arg)) {
      return ip_get_variable(self, varname_arg, flag_arg);
    }

    varname = varname_arg;
    index   = index_arg;
    flag    = flag_arg;

    StringValue(varname);
    StringValue(index);

#if TCL_MAJOR_VERSION >= 8
    {
        Tcl_Obj *nameobj, *idxobj, *ret;
        char *s;
        int  len;
        volatile VALUE strval;

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        nameobj = Tcl_NewStringObj(RSTRING(varname)->ptr, 
                                   RSTRING(varname)->len);
        Tcl_IncrRefCount(nameobj);
        idxobj  = Tcl_NewStringObj(RSTRING(index)->ptr, RSTRING(index)->len);
        Tcl_IncrRefCount(idxobj);

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            Tcl_DecrRefCount(nameobj);
            Tcl_DecrRefCount(idxobj);
            rb_thread_critical = thr_crit_bup;
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_ObjGetVar2(ptr->ip, nameobj, idxobj, FIX2INT(flag));
        }

        Tcl_DecrRefCount(nameobj);
        Tcl_DecrRefCount(idxobj);

        if (ret == (Tcl_Obj*)NULL) {
            volatile VALUE exc;
#if TCL_MAJOR_VERSION >= 8
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            exc = rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
#endif
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }

        Tcl_IncrRefCount(ret);

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        s = Tcl_GetStringFromObj(ret, &len);
        strval = rb_tainted_str_new(s, len);
        Tcl_DecrRefCount(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;
        return(strval);

# else /* TCL_VERSION >= 8.1 */
        if (Tcl_GetCharLength(ret) 
            != Tcl_UniCharLen(Tcl_GetUnicode(ret))) {
            /* possibly binary string */
            s = Tcl_GetByteArrayFromObj(ret, &len);
            strval = rb_tainted_str_new(s, len);
            rb_ivar_set(strval, ID_at_enc, rb_tainted_str_new2("binary"));
        } else {
            /* possibly text string */
            s = Tcl_GetStringFromObj(ret, &len);
            strval = rb_tainted_str_new(s, len);
        }

        Tcl_DecrRefCount(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
# endif
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        char *ret;

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_GetVar2(ptr->ip, RSTRING(varname)->ptr, 
                              RSTRING(index)->ptr, FIX2INT(flag));
        }

        if (ret == (char*)NULL) {
            volatile VALUE exc;
#if TCL_MAJOR_VERSION >= 8
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            exc = rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
#endif
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }

        strval = rb_tainted_str_new2(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
    }
#endif
}

static VALUE
ip_set_variable(self, varname_arg, value_arg, flag_arg)
    VALUE self;
    VALUE varname_arg;
    VALUE value_arg;
    VALUE flag_arg;
{
    struct tcltkip *ptr = get_ip(self);
    int thr_crit_bup;
    volatile VALUE varname, value, flag;

    varname = varname_arg;
    value   = value_arg;
    flag    = flag_arg;
 
    StringValue(varname);
    StringValue(value);

#if TCL_MAJOR_VERSION >= 8
    {
        Tcl_Obj *nameobj, *valobj, *ret;
        char *s;
        int  len;
        volatile VALUE strval;

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        nameobj = Tcl_NewStringObj(RSTRING(varname)->ptr, 
                                   RSTRING(varname)->len);

        Tcl_IncrRefCount(nameobj);

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        valobj  = Tcl_NewStringObj(RSTRING(value)->ptr, 
                                   RSTRING(value)->len); 
        Tcl_IncrRefCount(valobj);
# else /* TCL_VERSION >= 8.1 */
        {
            volatile VALUE enc = Qnil;

            if (RTEST(rb_ivar_defined(value, ID_at_enc))) {
                enc = rb_ivar_get(value, ID_at_enc);
            }

            if (!NIL_P(enc) && strcmp(StringValuePtr(enc), "binary") == 0) {
                /* binary string */
                valobj = Tcl_NewByteArrayObj(RSTRING(value)->ptr, 
                                             RSTRING(value)->len);
            } else if (strlen(RSTRING(value)->ptr) != RSTRING(value)->len) {
                /* probably binary string */
                valobj = Tcl_NewByteArrayObj(RSTRING(value)->ptr, 
                                             RSTRING(value)->len);
            } else {
                /* probably text string */
                valobj = Tcl_NewStringObj(RSTRING(value)->ptr, 
                                          RSTRING(value)->len); 
            }

            Tcl_IncrRefCount(valobj);
        }
# endif

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            Tcl_DecrRefCount(nameobj);
            Tcl_DecrRefCount(valobj);
            rb_thread_critical = thr_crit_bup;
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_ObjSetVar2(ptr->ip, nameobj, (Tcl_Obj*)NULL, valobj, 
                                 FIX2INT(flag));
        }

        Tcl_DecrRefCount(nameobj);
        Tcl_DecrRefCount(valobj);

        if (ret == (Tcl_Obj*)NULL) {
            volatile VALUE exc;
#if TCL_MAJOR_VERSION >= 8
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            exc = rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
#endif
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }

        Tcl_IncrRefCount(ret);

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        s = Tcl_GetStringFromObj(ret, &len); 
        strval = rb_tainted_str_new(s, len);
# else /* TCL_VERSION >= 8.1 */
        {
            VALUE old_gc;

            old_gc = rb_gc_disable();

            if (Tcl_GetCharLength(ret) != Tcl_UniCharLen(Tcl_GetUnicode(ret))) {
                /* possibly binary string */
                s = Tcl_GetByteArrayFromObj(ret, &len);
                strval = rb_tainted_str_new(s, len);
                rb_ivar_set(strval, ID_at_enc, rb_str_new2("binary"));
            } else {
                /* possibly text string */
                s = Tcl_GetStringFromObj(ret, &len);
                strval = rb_tainted_str_new(s, len);
            }
            if (old_gc == Qfalse) rb_gc_enable();
        }
# endif

        Tcl_DecrRefCount(ret);

        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        CONST char *ret;

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_SetVar2(ptr->ip, RSTRING(varname)->ptr, (char*)NULL, 
                              RSTRING(value)->ptr, (int)FIX2INT(flag));
        }

        if (ret == NULL) {
            rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
        }

        strval = rb_tainted_str_new2(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
    }
#endif
}

static VALUE
ip_set_variable2(self, varname_arg, index_arg, value_arg, flag_arg)
    VALUE self;
    VALUE varname_arg;
    VALUE index_arg;
    VALUE value_arg;
    VALUE flag_arg;
{
    struct tcltkip *ptr = get_ip(self);
    int thr_crit_bup;
    volatile VALUE varname, index, value, flag;

    if (NIL_P(index_arg)) {
      return ip_set_variable(self, varname_arg, value_arg, flag_arg);
    }

    varname = varname_arg;
    index   = index_arg;
    value   = value_arg;
    flag    = flag_arg;

    StringValue(varname);
    StringValue(index);
    StringValue(value);

#if TCL_MAJOR_VERSION >= 8
    {
        Tcl_Obj *nameobj, *idxobj, *valobj, *ret;
        char *s;
        int  len;
        volatile VALUE strval;

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        nameobj = Tcl_NewStringObj(RSTRING(varname)->ptr, 
                                   RSTRING(varname)->len);
        Tcl_IncrRefCount(nameobj);

        idxobj  = Tcl_NewStringObj(RSTRING(index)->ptr, 
                                   RSTRING(index)->len);
        Tcl_IncrRefCount(idxobj);

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        valobj  = Tcl_NewStringObj(RSTRING(value)->ptr, 
                                   RSTRING(value)->len); 
# else /* TCL_VERSION >= 8.1 */
        {
            VALUE enc = Qnil;

            if (RTEST(rb_ivar_defined(value, ID_at_enc))) {
                enc = rb_ivar_get(value, ID_at_enc);
            }

            if (!NIL_P(enc) && strcmp(StringValuePtr(enc), "binary") == 0) {
                /* binary string */
                valobj = Tcl_NewByteArrayObj(RSTRING(value)->ptr, 
                                             RSTRING(value)->len);
            } else if (strlen(RSTRING(value)->ptr) != RSTRING(value)->len) {
                /* probably binary string */
                valobj = Tcl_NewByteArrayObj(RSTRING(value)->ptr, 
                                             RSTRING(value)->len);
            } else {
                /* probably text string */
                valobj = Tcl_NewStringObj(RSTRING(value)->ptr, 
                                          RSTRING(value)->len); 
            }
        }

# endif
        Tcl_IncrRefCount(valobj);

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            Tcl_DecrRefCount(nameobj);
            Tcl_DecrRefCount(idxobj);
            Tcl_DecrRefCount(valobj);
            rb_thread_critical = thr_crit_bup;
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_ObjSetVar2(ptr->ip, nameobj, idxobj, valobj, 
                                 FIX2INT(flag));
        }

        Tcl_DecrRefCount(nameobj);
        Tcl_DecrRefCount(idxobj);
        Tcl_DecrRefCount(valobj);

        if (ret == (Tcl_Obj*)NULL) {
            volatile VALUE exc;
#if TCL_MAJOR_VERSION >= 8
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            exc = rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
#endif
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            rb_exc_raise(exc);
        }

        Tcl_IncrRefCount(ret);

# if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        s = Tcl_GetStringFromObj(ret, &len); 
        strval = rb_tainted_str_new(s, len);
# else /* TCL_VERSION >= 8.1 */
        if (Tcl_GetCharLength(ret) != Tcl_UniCharLen(Tcl_GetUnicode(ret))) {
            /* possibly binary string */
            s = Tcl_GetByteArrayFromObj(ret, &len);
            strval = rb_tainted_str_new(s, len);
            rb_ivar_set(strval, ID_at_enc, rb_str_new2("binary"));
        } else {
            /* possibly text string */
            s = Tcl_GetStringFromObj(ret, &len);
            strval = rb_tainted_str_new(s, len);
        }
# endif

        Tcl_DecrRefCount(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        CONST char *ret;

        /* ip is deleted? */
        if (Tcl_InterpDeleted(ptr->ip)) {
            DUMP1("ip is deleted");
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_SetVar2(ptr->ip, RSTRING(varname)->ptr, 
                              RSTRING(index)->ptr, 
                              RSTRING(value)->ptr, FIX2INT(flag));
        }

        if (ret == (char*)NULL) {
            rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
        }

        Tcl_IncrRefCount(ret);

        strval = rb_tainted_str_new2(ret);

        Tcl_DecrRefCount(ret);
        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
    }
#endif
}

static VALUE
ip_unset_variable(self, varname_arg, flag_arg)
    VALUE self;
    VALUE varname_arg;
    VALUE flag_arg;
{
    struct tcltkip *ptr = get_ip(self);
    volatile VALUE varname, value, flag;

    varname = varname_arg;
    flag    = flag_arg;

    StringValue(varname);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return Qtrue;
    }

    ptr->return_value = Tcl_UnsetVar(ptr->ip, RSTRING(varname)->ptr, 
                                     FIX2INT(flag));
    if (ptr->return_value == TCL_ERROR) {
        if (FIX2INT(flag) & TCL_LEAVE_ERR_MSG) {
#if TCL_MAJOR_VERSION >= 8
            rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
#endif
        }
        return Qfalse;
    }
    return Qtrue;
}

static VALUE
ip_unset_variable2(self, varname_arg, index_arg, flag_arg)
    VALUE self;
    VALUE varname_arg;
    VALUE index_arg;
    VALUE flag_arg;
{
    struct tcltkip *ptr = get_ip(self);
    volatile VALUE varname, index, value, flag;

    if (NIL_P(index_arg)) {
      return ip_unset_variable(self, varname_arg, flag_arg);
    }

    varname = varname_arg;
    index   = index_arg;
    flag    = flag_arg;

    StringValue(varname);
    StringValue(index);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
        DUMP1("ip is deleted");
        return Qtrue;
    }

    ptr->return_value = Tcl_UnsetVar2(ptr->ip, RSTRING(varname)->ptr, 
                                      RSTRING(index)->ptr, FIX2INT(flag));
    if (ptr->return_value == TCL_ERROR) {
        if (FIX2INT(flag) & TCL_LEAVE_ERR_MSG) {
#if TCL_MAJOR_VERSION >= 8
            rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(ptr->ip));
#else /* TCL_MAJOR_VERSION < 8 */
            rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
#endif
        }
        return Qfalse;
    }
    return Qtrue;
}

static VALUE
ip_get_global_var(self, varname)
    VALUE self;
    VALUE varname;
{
    return ip_get_variable(self, varname, 
                           INT2FIX(TCL_GLOBAL_ONLY | TCL_LEAVE_ERR_MSG));
}

static VALUE
ip_get_global_var2(self, varname, index)
    VALUE self;
    VALUE varname;
    VALUE index;
{
    return ip_get_variable2(self, varname, index, 
                            INT2FIX(TCL_GLOBAL_ONLY | TCL_LEAVE_ERR_MSG));
}

static VALUE
ip_set_global_var(self, varname, value)
    VALUE self;
    VALUE varname;
    VALUE value;
{
    return ip_set_variable(self, varname, value, 
                           INT2FIX(TCL_GLOBAL_ONLY | TCL_LEAVE_ERR_MSG));
}

static VALUE
ip_set_global_var2(self, varname, index, value)
    VALUE self;
    VALUE varname;
    VALUE index;
    VALUE value;
{
    return ip_set_variable2(self, varname, index, value, 
                            INT2FIX(TCL_GLOBAL_ONLY | TCL_LEAVE_ERR_MSG));
}

static VALUE
ip_unset_global_var(self, varname)
    VALUE self;
    VALUE varname;
{
    return ip_unset_variable(self, varname, 
                             INT2FIX(TCL_GLOBAL_ONLY | TCL_LEAVE_ERR_MSG));
}

static VALUE
ip_unset_global_var2(self, varname, index)
    VALUE self;
    VALUE varname;
    VALUE index;
{
    return ip_unset_variable2(self, varname, index, 
                              INT2FIX(TCL_GLOBAL_ONLY | TCL_LEAVE_ERR_MSG));
}


/* treat Tcl_List */
static VALUE
lib_split_tklist_core(ip_obj, list_str)
    VALUE ip_obj;
    VALUE list_str;
{
    Tcl_Interp *interp;
    volatile VALUE ary, elem;
    int idx;
    int taint_flag = OBJ_TAINTED(list_str);
    int result;
    VALUE old_gc;

    if (NIL_P(ip_obj)) {
        interp = (Tcl_Interp *)NULL;
    } else {
        interp = get_ip(ip_obj)->ip;
    }

    StringValue(list_str);

    {
#if TCL_MAJOR_VERSION >= 8
        /* object style interface */
        Tcl_Obj *listobj;
        int     objc;
        Tcl_Obj **objv;
        int thr_crit_bup;

# if 1
#  if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
        listobj = Tcl_NewStringObj(RSTRING(list_str)->ptr, 
                                   RSTRING(list_str)->len); 
#  else /* TCL_VERSION >= 8.1 */
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        {
            VALUE enc = Qnil;

            if (RTEST(rb_ivar_defined(list_str, ID_at_enc))) {
                enc = rb_ivar_get(list_str, ID_at_enc);
            }

            if (!NIL_P(enc) && strcmp(StringValuePtr(enc), "binary") == 0) {
                /* binary string */
                listobj = Tcl_NewByteArrayObj(RSTRING(list_str)->ptr, 
                                              RSTRING(list_str)->len);
            } else if (strlen(RSTRING(list_str)->ptr)
                                    != RSTRING(list_str)->len) {
                /* probably binary string */
                listobj = Tcl_NewByteArrayObj(RSTRING(list_str)->ptr, 
                                              RSTRING(list_str)->len);
            } else {
                /* probably text string */
                listobj = Tcl_NewStringObj(RSTRING(list_str)->ptr, 
                                           RSTRING(list_str)->len); 
            }
        }

        rb_thread_critical = thr_crit_bup;
#  endif
# else
        listobj = Tcl_NewStringObj(RSTRING(list_str)->ptr, 
                                   RSTRING(list_str)->len); 
# endif

        Tcl_IncrRefCount(listobj);

        result = Tcl_ListObjGetElements(interp, listobj, &objc, &objv);

        if (result == TCL_ERROR) {
            Tcl_DecrRefCount(listobj);
            if (interp == (Tcl_Interp*)NULL) {
                rb_raise(rb_eRuntimeError, "cannot get elements from list");
            } else {
#if TCL_MAJOR_VERSION >= 8
                rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(interp));
#else /* TCL_MAJOR_VERSION < 8 */
                rb_raise(rb_eRuntimeError, "%s", interp->result);
#endif
            }
        }

        for(idx = 0; idx < objc; idx++) {
            Tcl_IncrRefCount(objv[idx]);
        }

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        ary = rb_ary_new2(objc);
        if (taint_flag) OBJ_TAINT(ary);

        old_gc = rb_gc_disable();

        for(idx = 0; idx < objc; idx++) {
            char *str;
            int  len;

# if 1
#  if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
            str = Tcl_GetStringFromObj(objv[idx], &len);
            elem = rb_str_new(str, len);
#  else /* TCL_VERSION >= 8.1 */
            if (Tcl_GetCharLength(objv[idx]) 
                != Tcl_UniCharLen(Tcl_GetUnicode(objv[idx]))) {
                /* possibly binary string */
                str = Tcl_GetByteArrayFromObj(objv[idx], &len);
                elem = rb_str_new(str, len);
                rb_ivar_set(elem, ID_at_enc, rb_tainted_str_new2("binary"));
            } else {
                /* possibly text string */
                str = Tcl_GetStringFromObj(objv[idx], &len);
                elem = rb_str_new(str, len);
            }
#  endif
# else
            str = Tcl_GetStringFromObj(objv[idx], &len);
            elem = rb_str_new(str, len);
# endif

            if (taint_flag) OBJ_TAINT(elem);
            RARRAY(ary)->ptr[idx] = elem;
        }

        RARRAY(ary)->len = objc;

        if (old_gc == Qfalse) rb_gc_enable();

        rb_thread_critical = thr_crit_bup;

        for(idx = 0; idx < objc; idx++) {
            Tcl_DecrRefCount(objv[idx]);
        }

        Tcl_DecrRefCount(listobj);

#else /* TCL_MAJOR_VERSION < 8 */
        /* string style interface */
        int  argc;
        char **argv;

        if (Tcl_SplitList(interp, RSTRING(list_str)->ptr, 
                          &argc, &argv) == TCL_ERROR) {
            if (interp == (Tcl_Interp*)NULL) {
                rb_raise(rb_eRuntimeError, "cannot get elements from list");
            } else {
                rb_raise(rb_eRuntimeError, "%s", interp->result);
            }
        }

        ary = rb_ary_new2(argc);
        if (taint_flag) OBJ_TAINT(ary);

        old_gc = rb_gc_disable();

        for(idx = 0; idx < argc; idx++) {
            if (taint_flag) {
                elem = rb_tainted_str_new2(argv[idx]);
            } else {
                elem = rb_str_new2(argv[idx]);
            }
            /* rb_ivar_set(elem, ID_at_enc, rb_str_new2("binary")); */
            RARRAY(ary)->ptr[idx] = elem;
        }
        RARRAY(ary)->len = argc;

        if (old_gc == Qfalse) rb_gc_enable();
#endif
    }

    return ary;
}

static VALUE
lib_split_tklist(self, list_str)
    VALUE self;
    VALUE list_str;
{
    return lib_split_tklist_core(Qnil, list_str);
}


static VALUE
ip_split_tklist(self, list_str)
    VALUE self;
    VALUE list_str;
{
    return lib_split_tklist_core(self, list_str);
}

static VALUE
lib_merge_tklist(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    int  num, len;
    int  *flagPtr;
    char *dst, *result;
    volatile VALUE str;
    int taint_flag = 0;
    int thr_crit_bup;
    VALUE old_gc;

    if (argc == 0) return rb_str_new2("");

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;
    old_gc = rb_gc_disable();

    /* based on Tcl/Tk's Tcl_Merge() */
    flagPtr = ALLOC_N(int, argc);

    /* pass 1 */
    len = 1;
    for(num = 0; num < argc; num++) {
        if (OBJ_TAINTED(argv[num])) taint_flag = 1;
        dst = StringValuePtr(argv[num]);
#if TCL_MAJOR_VERSION >= 8
        len += Tcl_ScanCountedElement(dst, RSTRING(argv[num])->len, 
                                      &flagPtr[num]) + 1;
#else /* TCL_MAJOR_VERSION < 8 */
        len += Tcl_ScanElement(dst, &flagPtr[num]) + 1;
#endif
    }

    /* pass 2 */
    result = (char *)Tcl_Alloc(len);
    dst = result;
    for(num = 0; num < argc; num++) {
#if TCL_MAJOR_VERSION >= 8
        len = Tcl_ConvertCountedElement(RSTRING(argv[num])->ptr, 
                                        RSTRING(argv[num])->len, 
                                        dst, flagPtr[num]);
#else /* TCL_MAJOR_VERSION < 8 */
        len = Tcl_ConvertElement(RSTRING(argv[num])->ptr, dst, flagPtr[num]);
#endif
        dst += len;
        *dst = ' ';
        dst++;
    }
    if (dst == result) {
        *dst = 0;
    } else {
        dst[-1] = 0;
    }

    free(flagPtr);

    /* create object */
    str = rb_str_new(result, dst - result - 1);
    if (taint_flag) OBJ_TAINT(str);
    Tcl_Free(result);

    if (old_gc == Qfalse) rb_gc_enable();
    rb_thread_critical = thr_crit_bup;

    return str;
}

static VALUE
lib_conv_listelement(self, src)
    VALUE self;
    VALUE src;
{
    int   len, scan_flag;
    volatile VALUE dst;
    int   taint_flag = OBJ_TAINTED(src);
    int thr_crit_bup;

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    StringValue(src);

#if TCL_MAJOR_VERSION >= 8
    len = Tcl_ScanCountedElement(RSTRING(src)->ptr, RSTRING(src)->len, 
                                 &scan_flag);
    dst = rb_str_new(0, len + 1);
    len = Tcl_ConvertCountedElement(RSTRING(src)->ptr, RSTRING(src)->len, 
                                    RSTRING(dst)->ptr, scan_flag);
#else /* TCL_MAJOR_VERSION < 8 */
    len = Tcl_ScanElement(RSTRING(src)->ptr, &scan_flag);
    dst = rb_str_new(0, len + 1);
    len = Tcl_ConvertElement(RSTRING(src)->ptr, RSTRING(dst)->ptr, scan_flag);
#endif

    RSTRING(dst)->len = len;
    RSTRING(dst)->ptr[len] = '\0';
    if (taint_flag) OBJ_TAINT(dst);

    rb_thread_critical = thr_crit_bup;

    return dst;
}


#ifdef __MACOS__
static void
_macinit()
{
    tcl_macQdPtr = &qd; /* setup QuickDraw globals */
    Tcl_MacSetEventProc(TkMacConvertEvent); /* setup event handler */
}
#endif

static VALUE
tcltklib_compile_info()
{
    volatile VALUE ret;
    int size;
    char form[] 
      = "tcltklib %s :: Ruby%s (%s) %s pthread :: Tcl%s(%s)/Tk%s(%s) %s";
    char *info;

    size = strlen(form)
        + strlen(TCLTKLIB_RELEASE_DATE)
        + strlen(RUBY_VERSION)
        + strlen(RUBY_RELEASE_DATE)
        + strlen("without") 
        + strlen(TCL_PATCH_LEVEL)
        + strlen("without stub")
        + strlen(TK_PATCH_LEVEL)
        + strlen("without stub") 
        + strlen("unknown tcl_threads");

    info = ALLOC_N(char, size);

    sprintf(info, form,
            TCLTKLIB_RELEASE_DATE, 
            RUBY_VERSION, RUBY_RELEASE_DATE, 
#ifdef HAVE_NATIVETHREAD
            "with",
#else
            "without",
#endif
            TCL_PATCH_LEVEL, 
#ifdef USE_TCL_STUBS
            "with stub",
#else
            "without stub",
#endif
            TK_PATCH_LEVEL, 
#ifdef USE_TK_STUBS
            "with stub",
#else
            "without stub",
#endif
#ifdef WITH_TCL_ENABLE_THREAD
# if WITH_TCL_ENABLE_THREAD
            "with tcl_threads"
# else
            "without tcl_threads"
# endif
#else
            "unknown tcl_threads"
#endif
        );

    ret = rb_obj_freeze(rb_str_new2(info));

    free(info);

    return ret;
}

/*---- initialization ----*/
void
Init_tcltklib()
{
    int  thr_crit_bup;

    VALUE lib = rb_define_module("TclTkLib");
    VALUE ip = rb_define_class("TclTkIp", rb_cObject);

    VALUE ev_flag = rb_define_module_under(lib, "EventFlag");
    VALUE var_flag = rb_define_module_under(lib, "VarAccessFlag");

    /* --------------------------------------------------------------- */

#if defined USE_TCL_STUBS && defined USE_TK_STUBS
    extern int ruby_tcltk_stubs();
    int ret = ruby_tcltk_stubs();

    if (ret)
        rb_raise(rb_eLoadError, "tcltklib: tcltk_stubs init error(%d)", ret);
#endif

    /* --------------------------------------------------------------- */

    rb_global_variable(&eTkCallbackReturn);
    rb_global_variable(&eTkCallbackBreak);
    rb_global_variable(&eTkCallbackContinue);

    rb_global_variable(&eventloop_thread);
    rb_global_variable(&watchdog_thread);

   /* --------------------------------------------------------------- */

    rb_define_const(lib, "COMPILE_INFO", tcltklib_compile_info());

    rb_define_const(lib, "RELEASE_DATE", 
                    rb_obj_freeze(rb_str_new2(tcltklib_release_date)));

    rb_define_const(lib, "FINALIZE_PROC_NAME", 
                    rb_str_new2(finalize_hook_name));

   /* --------------------------------------------------------------- */

    rb_define_const(ev_flag, "NONE",      INT2FIX(0));
    rb_define_const(ev_flag, "WINDOW",    INT2FIX(TCL_WINDOW_EVENTS));
    rb_define_const(ev_flag, "FILE",      INT2FIX(TCL_FILE_EVENTS));
    rb_define_const(ev_flag, "TIMER",     INT2FIX(TCL_TIMER_EVENTS));
    rb_define_const(ev_flag, "IDLE",      INT2FIX(TCL_IDLE_EVENTS));
    rb_define_const(ev_flag, "ALL",       INT2FIX(TCL_ALL_EVENTS));
    rb_define_const(ev_flag, "DONT_WAIT", INT2FIX(TCL_DONT_WAIT));

    /* --------------------------------------------------------------- */

    rb_define_const(var_flag, "NONE",           INT2FIX(0));
    rb_define_const(var_flag, "GLOBAL_ONLY",    INT2FIX(TCL_GLOBAL_ONLY));
#ifdef TCL_NAMESPACE_ONLY
    rb_define_const(var_flag, "NAMESPACE_ONLY", INT2FIX(TCL_NAMESPACE_ONLY));
#else /* probably Tcl7.6 */
    rb_define_const(var_flag, "NAMESPACE_ONLY", INT2FIX(0));
#endif
    rb_define_const(var_flag, "LEAVE_ERR_MSG",  INT2FIX(TCL_LEAVE_ERR_MSG));
    rb_define_const(var_flag, "APPEND_VALUE",   INT2FIX(TCL_APPEND_VALUE));
    rb_define_const(var_flag, "LIST_ELEMENT",   INT2FIX(TCL_LIST_ELEMENT));
#ifdef TCL_PARSE_PART1
    rb_define_const(var_flag, "PARSE_VARNAME",  INT2FIX(TCL_PARSE_PART1));
#else /* probably Tcl7.6 */
    rb_define_const(var_flag, "PARSE_VARNAME",  INT2FIX(0));
#endif

    /* --------------------------------------------------------------- */

    eTkCallbackBreak = rb_define_class("TkCallbackReturn", rb_eStandardError);
    eTkCallbackBreak = rb_define_class("TkCallbackBreak", rb_eStandardError);
    eTkCallbackContinue = rb_define_class("TkCallbackContinue",
                                          rb_eStandardError);

    /* --------------------------------------------------------------- */

    eLocalJumpError = rb_const_get(rb_cObject, rb_intern("LocalJumpError"));

    ID_at_enc = rb_intern("@encoding");
    ID_at_interp = rb_intern("@interp");

    ID_stop_p = rb_intern("stop?");
    ID_kill = rb_intern("kill");
    ID_join = rb_intern("join");

    ID_call = rb_intern("call");
    ID_backtrace = rb_intern("backtrace");
    ID_message = rb_intern("message");

    ID_at_reason = rb_intern("@reason");
    ID_return = rb_intern("return");
    ID_break = rb_intern("break");
    ID_next = rb_intern("next");

    ID_to_s = rb_intern("to_s");
    ID_inspect = rb_intern("inspect");

    /* --------------------------------------------------------------- */

    rb_define_module_function(lib, "mainloop", lib_mainloop, -1);
    rb_define_module_function(lib, "mainloop_watchdog", 
                              lib_mainloop_watchdog, -1);
    rb_define_module_function(lib, "do_one_event", lib_do_one_event, -1);
    rb_define_module_function(lib, "mainloop_abort_on_exception", 
                             lib_evloop_abort_on_exc, 0);
    rb_define_module_function(lib, "mainloop_abort_on_exception=",  
                             lib_evloop_abort_on_exc_set, 1);
    rb_define_module_function(lib, "set_eventloop_tick",set_eventloop_tick,1);
    rb_define_module_function(lib, "get_eventloop_tick",get_eventloop_tick,0);
    rb_define_module_function(lib, "set_no_event_wait", set_no_event_wait, 1);
    rb_define_module_function(lib, "get_no_event_wait", get_no_event_wait, 0);
    rb_define_module_function(lib, "set_eventloop_weight", 
                              set_eventloop_weight, 2);
    rb_define_module_function(lib, "set_max_block_time", set_max_block_time,1);
    rb_define_module_function(lib, "get_eventloop_weight", 
                              get_eventloop_weight, 0);
    rb_define_module_function(lib, "num_of_mainwindows", 
                              lib_num_of_mainwindows, 0);

    /* --------------------------------------------------------------- */

    rb_define_module_function(lib, "_split_tklist", lib_split_tklist, 1);
    rb_define_module_function(lib, "_merge_tklist", lib_merge_tklist, -1);
    rb_define_module_function(lib, "_conv_listelement", 
                              lib_conv_listelement, 1);
    rb_define_module_function(lib, "_toUTF8", lib_toUTF8, -1);
    rb_define_module_function(lib, "_fromUTF8", lib_fromUTF8, -1);
    rb_define_module_function(lib, "_subst_UTF_backslash", 
                              lib_UTF_backslash, 1);
    rb_define_module_function(lib, "_subst_Tcl_backslash", 
                              lib_Tcl_backslash, 1);

    /* --------------------------------------------------------------- */

    rb_define_alloc_func(ip, ip_alloc);
    rb_define_method(ip, "initialize", ip_init, -1);
    rb_define_method(ip, "create_slave", ip_create_slave, -1);
    rb_define_method(ip, "make_safe", ip_make_safe, 0);
    rb_define_method(ip, "safe?", ip_is_safe_p, 0);
    rb_define_method(ip, "allow_ruby_exit?", ip_allow_ruby_exit_p, 0);
    rb_define_method(ip, "allow_ruby_exit=", ip_allow_ruby_exit_set, 1);
    rb_define_method(ip, "delete", ip_delete, 0);
    rb_define_method(ip, "deleted?", ip_is_deleted_p, 0);
    rb_define_method(ip, "_eval", ip_eval, 1);
    rb_define_method(ip, "_toUTF8", ip_toUTF8, -1);
    rb_define_method(ip, "_fromUTF8", ip_fromUTF8, -1);
    rb_define_method(ip, "_thread_vwait", ip_thread_vwait, 1);
    rb_define_method(ip, "_thread_tkwait", ip_thread_tkwait, 2);
    rb_define_method(ip, "_invoke", ip_invoke, -1);
    rb_define_method(ip, "_return_value", ip_retval, 0);

    /* --------------------------------------------------------------- */

    rb_define_method(ip, "_get_variable", ip_get_variable, 2);
    rb_define_method(ip, "_get_variable2", ip_get_variable2, 3);
    rb_define_method(ip, "_set_variable", ip_set_variable, 3);
    rb_define_method(ip, "_set_variable2", ip_set_variable2, 4);
    rb_define_method(ip, "_unset_variable", ip_unset_variable, 2);
    rb_define_method(ip, "_unset_variable2", ip_unset_variable2, 3);
    rb_define_method(ip, "_get_global_var", ip_get_global_var, 1);
    rb_define_method(ip, "_get_global_var2", ip_get_global_var2, 2);
    rb_define_method(ip, "_set_global_var", ip_set_global_var, 2);
    rb_define_method(ip, "_set_global_var2", ip_set_global_var2, 3);
    rb_define_method(ip, "_unset_global_var", ip_unset_global_var, 1);
    rb_define_method(ip, "_unset_global_var2", ip_unset_global_var2, 2);

    /* --------------------------------------------------------------- */

    rb_define_method(ip, "_split_tklist", ip_split_tklist, 1);
    rb_define_method(ip, "_merge_tklist", lib_merge_tklist, -1);
    rb_define_method(ip, "_conv_listelement", lib_conv_listelement, 1);

    /* --------------------------------------------------------------- */

    rb_define_method(ip, "mainloop", ip_mainloop, -1);
    rb_define_method(ip, "mainloop_watchdog", ip_mainloop_watchdog, -1);
    rb_define_method(ip, "do_one_event", ip_do_one_event, -1);
    rb_define_method(ip, "mainloop_abort_on_exception", 
                    ip_evloop_abort_on_exc, 0);
    rb_define_method(ip, "mainloop_abort_on_exception=", 
                    ip_evloop_abort_on_exc_set, 1);
    rb_define_method(ip, "set_eventloop_tick", ip_set_eventloop_tick, 1);
    rb_define_method(ip, "get_eventloop_tick", ip_get_eventloop_tick, 0);
    rb_define_method(ip, "set_no_event_wait", ip_set_no_event_wait, 1);
    rb_define_method(ip, "get_no_event_wait", ip_get_no_event_wait, 0);
    rb_define_method(ip, "set_eventloop_weight", ip_set_eventloop_weight, 2);
    rb_define_method(ip, "get_eventloop_weight", ip_get_eventloop_weight, 0);
    rb_define_method(ip, "set_max_block_time", set_max_block_time, 1);
    rb_define_method(ip, "restart", ip_restart, 0);

    /* --------------------------------------------------------------- */

    eventloop_thread = 0;
    watchdog_thread  = 0;

    /* --------------------------------------------------------------- */

#ifdef __MACOS__
    _macinit();
#endif

    /* from Tk_Main() */
    DUMP1("Tcl_FindExecutable");
    Tcl_FindExecutable(RSTRING(rb_argv0)->ptr);

    /* --------------------------------------------------------------- */
}

/* eof */
