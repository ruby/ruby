/*
 *	tcltklib.c
 *		Aug. 27, 1997	Y. Shigehiro
 *		Oct. 24, 1997	Y. Matsumoto
 */

#include "ruby.h"
#include "rubysig.h"
#undef EXTERN	/* avoid conflict with tcl.h of tcl8.2 or before */
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

/* for ruby_debug */

#define DUMP1(ARG1) if (ruby_debug) { fprintf(stderr, "tcltklib: %s\n", ARG1);}
#define DUMP2(ARG1, ARG2) if (ruby_debug) { fprintf(stderr, "tcltklib: ");\
fprintf(stderr, ARG1, ARG2); fprintf(stderr, "\n"); }
/*
#define DUMP1(ARG1)
#define DUMP2(ARG1, ARG2)
*/

/* for callback break & continue */
static VALUE eTkCallbackBreak;
static VALUE eTkCallbackContinue;

static VALUE ip_invoke_real _((int, VALUE*, VALUE));
static VALUE ip_invoke _((int, VALUE*, VALUE));

/* from tkAppInit.c */

#if !defined __MINGW32__
/*
 * The following variable is a special hack that is needed in order for
 * Sun shared libraries to be used for Tcl.
 */

extern int matherr();
int *tclDummyMathPtr = (int *) matherr;
#endif

/*---- module TclTkLib ----*/

struct invoke_queue {
    Tcl_Event ev;
    int argc;
    VALUE *argv;
    VALUE obj;
    int done;
    int safe_level;
    VALUE *result;
    VALUE thread;
};
 
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
static int ip_ruby _((ClientData, Tcl_Interp *, int, Tcl_Obj *CONST*));
#else
static int ip_ruby _((ClientData, Tcl_Interp *, int, char **));
#endif

/*---- class TclTkIp ----*/
struct tcltkip {
    Tcl_Interp *ip;		/* the interpreter */
    int return_value;		/* return value */
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

/* Tk_ThreadTimer */
static Tcl_TimerToken timer_token = (Tcl_TimerToken)NULL;

/* timer callback */
static void _timer_for_tcl _((ClientData));
static void
_timer_for_tcl(clientData)
    ClientData clientData;
{
    /* struct invoke_queue *q, *tmp; */
    /* VALUE thread; */

    DUMP1("called timer_for_tcl");
    Tk_DeleteTimerHandler(timer_token);

    run_timer_flag = 1;

    if (timer_tick > 0) {
	timer_token = Tk_CreateTimerHandler(timer_tick, _timer_for_tcl, 
					    (ClientData)0);
    } else {
	timer_token = (Tcl_TimerToken)NULL;
    }

    /* rb_thread_schedule(); */
    /* tick_counter += event_loop_max; */
}

static VALUE
set_eventloop_tick(self, tick)
    VALUE self;
    VALUE tick;
{
    int ttick = NUM2INT(tick);

    rb_secure(4);

    if (ttick < 0) {
	rb_raise(rb_eArgError, 
		 "timer-tick parameter must be 0 or positive number");
    }

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
    } else if (val == Qnil) {
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
lib_eventloop_core(check_root, check_var)
    int check_root;
    int *check_var;
{
    VALUE current = eventloop_thread;
    int found_event = 1;
    struct timeval t;

    t.tv_sec = (time_t)0;
    t.tv_usec = (time_t)(no_event_wait*1000.0);

    Tk_DeleteTimerHandler(timer_token);
    run_timer_flag = 0;
    if (timer_tick > 0) {
	timer_token = Tk_CreateTimerHandler(timer_tick, _timer_for_tcl, 
					    (ClientData)0);
    } else {
	timer_token = (Tcl_TimerToken)NULL;
    }

    for(;;) {
	if (rb_thread_alone()) {
	    DUMP1("no other thread");
	    event_loop_wait_event = 0;

	    if (timer_tick == 0) {
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

	    found_event = Tcl_DoOneEvent(TCL_ALL_EVENTS);

	    if (loop_counter++ > 30000) {
		loop_counter = 0;
	    }

	    if (run_timer_flag) {
		/* 
		DUMP1("timer interrupt");
		run_timer_flag = 0;
		DUMP1("call rb_trap_exec()");
		rb_trap_exec();
		*/
		DUMP1("check Root Widget");
		if (check_root && Tk_GetNumMainWindows() == 0) {
		    run_timer_flag = 0;
		    rb_trap_exec();
		    return 1;
		}
	    }

	} else {
	    int tick_counter;

	    DUMP1("there are other threads");
	    event_loop_wait_event = 1;

	    found_event = 1;

	    timer_tick = req_timer_tick;
	    tick_counter = 0;
	    while(tick_counter < event_loop_max) {
		if (check_var != (int *)NULL) {
		    if (*check_var || !found_event) {
			return found_event;
		    }
		}

		if (Tcl_DoOneEvent(TCL_ALL_EVENTS | TCL_DONT_WAIT)) {
		    tick_counter++;
		} else {
		    tick_counter += no_event_tick;

		    DUMP1("check Root Widget");
		    if (check_root && Tk_GetNumMainWindows() == 0) {
			return 1;
		    }

		    rb_thread_wait_for(t);
		}

		if (loop_counter++ > 30000) {
		    loop_counter = 0;
		}

		if (watchdog_thread != 0 && eventloop_thread != current) {
		    return 1;
		}

		if (run_timer_flag) {
		    /*
		    DUMP1("timer interrupt");
		    run_timer_flag = 0;
		    */
		    break; /* switch to other thread */
		}
	    }

	    DUMP1("check Root Widget");
	    if (check_root && Tk_GetNumMainWindows() == 0) {
		return 1;
	    }
	}

	/* rb_thread_schedule(); */
	if (run_timer_flag) {
	    run_timer_flag = 0;
	    rb_trap_exec();
	} else {
            DUMP1("thread scheduling");
	    rb_thread_schedule();
	}
    }
    return 1;
}

VALUE
lib_eventloop_main(check_rootwidget)
    VALUE check_rootwidget;
{
    check_rootwidget_flag = RTEST(check_rootwidget);

    if (lib_eventloop_core(check_rootwidget_flag, (int *)NULL)) {
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
	if (RTEST(rb_funcall(watchdog_thread, rb_intern("stop?"), 0))) {
	    rb_funcall(watchdog_thread, rb_intern("kill"), 0);
	} else {
	    return Qnil;
	}
    }
    watchdog_thread = rb_thread_current();

    /* watchdog start */
    do {
	if (eventloop_thread == 0 
	    || (loop_counter == prev_val
		&& RTEST(rb_funcall(eventloop_thread, rb_intern("stop?"), 0))
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
    VALUE vflags;
    int flags;

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
	if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
	    /* slave IP */
	    flags |= TCL_DONT_WAIT;
	}
    }

    if (Tcl_DoOneEvent(flags)) {
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


/* Tcl command `ruby' */
static VALUE
ip_eval_rescue(failed, einfo)
    VALUE *failed;
    VALUE einfo;
{
    *failed = einfo;
    return Qnil;
}

/* restart Tk */
static VALUE
lib_restart(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    rb_secure(4);

    /* destroy the root wdiget */
    ptr->return_value = Tcl_Eval(ptr->ip, "destroy .");
    /* ignore ERROR */
    DUMP2("(TCL_Eval result) %d", ptr->return_value);

    /* execute Tk_Init of Tk_SafeInit */
#if TCL_MAJOR_VERSION >= 8
    if (Tcl_IsSafe(ptr->ip)) {
	DUMP1("Tk_SafeInit");
	if (Tk_SafeInit(ptr->ip) == TCL_ERROR) {
	    rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
	}
    } else {
	DUMP1("Tk_Init");
	if (Tk_Init(ptr->ip) == TCL_ERROR) {
	    rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
	}
    }
#else
    DUMP1("Tk_Init");
    if (Tk_Init(ptr->ip) == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }
#endif

    return Qnil;
}

static VALUE
ip_restart(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    rb_secure(4);
    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
	/* slave IP */
	return Qnil;
    }
    return lib_restart(self);
}

static int
#if TCL_MAJOR_VERSION >= 8
ip_ruby(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int argc;
    Tcl_Obj *CONST argv[];
#else
ip_ruby(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    VALUE res;
    int old_trapflg;
    VALUE failed = 0;
    char *arg;
    int  dummy;

    /* ruby command has 1 arg. */
    if (argc != 2) {
	rb_raise(rb_eArgError, "wrong # of arguments (%d for 1)", argc);
    }

    /* get C string from Tcl object */
#if TCL_MAJOR_VERSION >= 8
    arg = Tcl_GetStringFromObj(argv[1], &dummy);
#else
    arg = argv[1];
#endif

    /* evaluate the argument string by ruby */
    DUMP2("rb_eval_string(%s)", arg);
    old_trapflg = rb_trap_immediate;
    rb_trap_immediate = 0;
    res = rb_rescue2(rb_eval_string, (VALUE)arg, 
                     ip_eval_rescue, (VALUE)&failed,
                     rb_eStandardError, rb_eScriptError, (VALUE)0);
    rb_trap_immediate = old_trapflg;

    /* status check */
    if (failed) {
        VALUE eclass = CLASS_OF(failed);
	DUMP1("(rb_eval_string result) failed");
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp, StringValuePtr(failed), (char*)NULL);
        if (eclass == eTkCallbackBreak) {
	    return TCL_BREAK;
	} else if (eclass == eTkCallbackContinue) {
	    return TCL_CONTINUE;
	} else {
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
    DUMP2("(rb_eval_string result) %s", StringValuePtr(res));
    DUMP1("Tcl_AppendResult");
    Tcl_ResetResult(interp);
    Tcl_AppendResult(interp, StringValuePtr(res), (char *)NULL);

    return TCL_OK;
}


/**************************/
/*  based on tclEvent.c   */
/**************************/
static char *
VwaitVarProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    CONST char *name1;          /* Name of variable. */
    CONST char *name2;          /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
{
    int *donePtr = (int *) clientData;

    *donePtr = 1;
    return (char *) NULL;
}

static int
#if TCL_MAJOR_VERSION >= 8
ip_rbVwaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else
ip_rbVwaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    int  done, foundEvent;
    char *nameString;
    int  dummy;

    DUMP1("Ruby's 'vwait' is called");
    if (objc != 2) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "name");
#else
#if TCL_MAJOR_VERSION >= 8
	/* nameString = Tcl_GetString(objv[0]); */
	nameString = Tcl_GetStringFromObj(objv[0], &dummy);
#else
	nameString = objv[0];
#endif
        Tcl_AppendResult(interp, "wrong # args: should be \"",
			 nameString, " name\"", (char *) NULL);
#endif
        return TCL_ERROR;
    }
#if TCL_MAJOR_VERSION >= 8
    /* nameString = Tcl_GetString(objv[1]); */
    nameString = Tcl_GetStringFromObj(objv[1], &dummy);
#else
    nameString = objv[1];
#endif

    if (Tcl_TraceVar(interp, nameString,
		     TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
		     VwaitVarProc, (ClientData) &done) != TCL_OK) {
        return TCL_ERROR;
    };
    done = 0;
    foundEvent = lib_eventloop_core(/* not check root-widget */0, &done);
    Tcl_UntraceVar(interp, nameString,
		   TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
		   VwaitVarProc, (ClientData) &done);

    /*
     * Clear out the interpreter's result, since it may have been set
     * by event handlers.
     */

    Tcl_ResetResult(interp);
    if (!foundEvent) {
        Tcl_AppendResult(interp, "can't wait for variable \"", nameString,
			 "\":  would wait forever", (char *) NULL);
        return TCL_ERROR;
    }
    return TCL_OK;
}


/**************************/
/*  based on tkCmd.c      */
/**************************/
static char *
WaitVariableProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    CONST char *name1;          /* Name of variable. */
    CONST char *name2;          /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
{
    int *donePtr = (int *) clientData;

    *donePtr = 1;
    return (char *) NULL;
}

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

static int
#if TCL_MAJOR_VERSION >= 8
ip_rbTkWaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else
ip_rbTkWaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    Tk_Window tkwin = (Tk_Window) clientData;
    int done, index;
    static CONST char *optionStrings[] = { "variable", "visibility", "window",
					   (char *) NULL };
    enum options { TKWAIT_VARIABLE, TKWAIT_VISIBILITY, TKWAIT_WINDOW };
    char *nameString;
    int  dummy;

    DUMP1("Ruby's 'tkwait' is called");

    if (objc != 3) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "variable|visibility|window name");
#else
#if TCL_MAJOR_VERSION >= 8
        Tcl_AppendResult(interp, "wrong # args: should be \"",
			 Tcl_GetStringFromObj(objv[0], &dummy), 
			 " variable|visibility|window name\"", 
			 (char *) NULL);
#else
        Tcl_AppendResult(interp, "wrong # args: should be \"",
			 objv[0], " variable|visibility|window name\"", 
			 (char *) NULL);
#endif
#endif
        return TCL_ERROR;
    }

#if TCL_MAJOR_VERSION >= 8
    if (Tcl_GetIndexFromObj(interp, objv[1], 
# ifdef CONST84 /* Tcl8.4.x -- ?.?.? (current latest version is 8.4.4) */
                            (CONST84 char **)optionStrings, 
# else
#  if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION <= 4 /* Tcl8.0.x -- 8.4b1 */
                            (char **)optionStrings, 
#  else /* unknown (maybe TCL_VERSION >= 8.5) */
#   ifdef CONST
                            (CONST char **)optionStrings, 
#   else
                            optionStrings, 
#   endif
#  endif
# endif
			    "option", 0, &index) != TCL_OK) {
        return TCL_ERROR;
    }
#else
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
	    return TCL_ERROR;
	}
    }
#endif

#if TCL_MAJOR_VERSION >= 8
    /* nameString = Tcl_GetString(objv[2]); */
    nameString = Tcl_GetStringFromObj(objv[2], &dummy);
#else
    nameString = objv[2];
#endif

    switch ((enum options) index) {
    case TKWAIT_VARIABLE: {
	if (Tcl_TraceVar(interp, nameString,
			 TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
			 WaitVariableProc, (ClientData) &done) != TCL_OK) {
	    return TCL_ERROR;
	}
	done = 0;
	lib_eventloop_core(check_rootwidget_flag, &done);
	Tcl_UntraceVar(interp, nameString,
		       TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
		       WaitVariableProc, (ClientData) &done);
	break;
    }

    case TKWAIT_VISIBILITY: {
	Tk_Window window;

	window = Tk_NameToWindow(interp, nameString, tkwin);
	if (window == NULL) {
	    return TCL_ERROR;
	}
	Tk_CreateEventHandler(window,
			      VisibilityChangeMask|StructureNotifyMask,
			      WaitVisibilityProc, (ClientData) &done);
	done = 0;
	lib_eventloop_core(check_rootwidget_flag, &done);
	if (done != 1) {
	    /*
	     * Note that we do not delete the event handler because it
	     * was deleted automatically when the window was destroyed.
	     */

	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "window \"", nameString,
			     "\" was deleted before its visibility changed",
			     (char *) NULL);
	    return TCL_ERROR;
	}
	Tk_DeleteEventHandler(window,
			      VisibilityChangeMask|StructureNotifyMask,
			      WaitVisibilityProc, (ClientData) &done);
	break;
    }

    case TKWAIT_WINDOW: {
	Tk_Window window;
            
	window = Tk_NameToWindow(interp, nameString, tkwin);
	if (window == NULL) {
	    return TCL_ERROR;
	}
	Tk_CreateEventHandler(window, StructureNotifyMask,
			      WaitWindowProc, (ClientData) &done);
	done = 0;
	lib_eventloop_core(check_rootwidget_flag, &done);
	/*
	 * Note:  there's no need to delete the event handler.  It was
	 * deleted automatically when the window was destroyed.
	 */
	break;
    }
    }

    /*
     * Clear out the interpreter's result, since it may have been set
     * by event handlers.
     */

    Tcl_ResetResult(interp);
    return TCL_OK;
}

/****************************/
/* vwait/tkwait with thread */
/****************************/
struct th_vwait_param {
    VALUE thread;
    int   done;
};

static char *
rb_threadVwaitProc(clientData, interp, name1, name2, flags)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    Tcl_Interp *interp;         /* Interpreter containing variable. */
    CONST char *name1;          /* Name of variable. */
    CONST char *name2;          /* Second part of variable name. */
    int flags;                  /* Information about what happened. */
{
    struct th_vwait_param *param = (struct th_vwait_param *) clientData;

    param->done = 1;
    rb_thread_run(param->thread);

    return (char *)NULL;
}

static void
rb_threadWaitVisibilityProc(clientData, eventPtr)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    XEvent *eventPtr;           /* Information about event (not used). */
{
    struct th_vwait_param *param = (struct th_vwait_param *) clientData;

    if (eventPtr->type == VisibilityNotify) {
        param->done = 1;
    }
    if (eventPtr->type == DestroyNotify) {
        param->done = 2;
    }
}

static void
rb_threadWaitWindowProc(clientData, eventPtr)
    ClientData clientData;      /* Pointer to integer to set to 1. */
    XEvent *eventPtr;           /* Information about event. */
{
    struct th_vwait_param *param = (struct th_vwait_param *) clientData;

    if (eventPtr->type == DestroyNotify) {
        param->done = 1;
    }
}

static int
#if TCL_MAJOR_VERSION >= 8
ip_rb_threadVwaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else
ip_rb_threadVwaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    struct th_vwait_param *param;
    char *nameString;
    int  dummy;

    DUMP1("Ruby's 'thread_vwait' is called");

    if (eventloop_thread == rb_thread_current()) {
#if TCL_MAJOR_VERSION >= 8
	DUMP1("call ip_rbVwaitObjCmd");
	return ip_rbVwaitObjCmd(clientData, interp, objc, objv);
#else
	DUMP1("call ip_rbVwaitCommand");
	return ip_rbVwaitCommand(clientData, interp, objc, objv);
#endif
    }

    if (objc != 2) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "name");
#else
#if TCL_MAJOR_VERSION >= 8
	/* nameString = Tcl_GetString(objv[0]); */
	nameString = Tcl_GetStringFromObj(objv[0], &dummy);
#else
	nameString = objv[0];
#endif
        Tcl_AppendResult(interp, "wrong # args: should be \"",
			 nameString, " name\"", (char *) NULL);
#endif
        return TCL_ERROR;
    }
#if TCL_MAJOR_VERSION >= 8
    /* nameString = Tcl_GetString(objv[1]); */
    nameString = Tcl_GetStringFromObj(objv[1], &dummy);
#else
    nameString = objv[1];
#endif

    param = (struct th_vwait_param *)Tcl_Alloc(sizeof(struct th_vwait_param));
    param->thread = rb_thread_current();
    param->done = 0;

    if (Tcl_TraceVar(interp, nameString,
		     TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
		     rb_threadVwaitProc, (ClientData) param) != TCL_OK) {
        return TCL_ERROR;
    };

    if (!param->done) {
	rb_thread_stop();
    }

    Tcl_UntraceVar(interp, nameString,
		   TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
		   rb_threadVwaitProc, (ClientData) param);

    Tcl_Free((char *)param);

    return TCL_OK;
}

static int
#if TCL_MAJOR_VERSION >= 8
ip_rb_threadTkWaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else
ip_rb_threadTkWaitCommand(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp;
    int objc;
    char *objv[];
#endif
{
    struct th_vwait_param *param;
    Tk_Window tkwin = (Tk_Window) clientData;
    int index;
    static CONST char *optionStrings[] = { "variable", "visibility", "window",
					   (char *) NULL };
    enum options { TKWAIT_VARIABLE, TKWAIT_VISIBILITY, TKWAIT_WINDOW };
    char *nameString;
    int  dummy;

    DUMP1("Ruby's 'thread_tkwait' is called");

    if (eventloop_thread == rb_thread_current()) {
#if TCL_MAJOR_VERSION >= 8
	DUMP1("call ip_rbTkWaitObjCmd");
	return ip_rbTkWaitObjCmd(clientData, interp, objc, objv);
#else
	DUMP1("call rb_VwaitCommand");
	return ip_rbTkWaitCommand(clientData, interp, objc, objv);
#endif
    }

    if (objc != 3) {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "variable|visibility|window name");
#else
#if TCL_MAJOR_VERSION >= 8
        Tcl_AppendResult(interp, "wrong # args: should be \"",
			 Tcl_GetStringFromObj(objv[0], &dummy), 
			 " variable|visibility|window name\"", 
			 (char *) NULL);
#else
        Tcl_AppendResult(interp, "wrong # args: should be \"",
			 objv[0], " variable|visibility|window name\"", 
			 (char *) NULL);
#endif
#endif
        return TCL_ERROR;
    }

#if TCL_MAJOR_VERSION >= 8
    if (Tcl_GetIndexFromObj(interp, objv[1], 
# ifdef CONST84 /* Tcl8.4.x -- ?.?.? (current latest version is 8.4.4) */
                            (CONST84 char **)optionStrings, 
# else
#  if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION <= 4 /* Tcl8.0.x -- 8.4b1 */
                            (char **)optionStrings, 
#  else /* unknown (maybe TCL_VERSION >= 8.5) */
#   ifdef CONST
                            (CONST char **)optionStrings, 
#   else
                            optionStrings, 
#   endif
#  endif
# endif
			    "option", 0, &index) != TCL_OK) {
        return TCL_ERROR;
    }
#else
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
	    return TCL_ERROR;
	}
    }
#endif

#if TCL_MAJOR_VERSION >= 8
    /* nameString = Tcl_GetString(objv[2]); */
    nameString = Tcl_GetStringFromObj(objv[2], &dummy);
#else
    nameString = objv[2];
#endif

    param = (struct th_vwait_param *)Tcl_Alloc(sizeof(struct th_vwait_param));
    param->thread = rb_thread_current();
    param->done = 0;

    switch ((enum options) index) {
    case TKWAIT_VARIABLE: {
	if (Tcl_TraceVar(interp, nameString,
			 TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
			 rb_threadVwaitProc, (ClientData) param) != TCL_OK) {
	    return TCL_ERROR;
	};

	if (!param->done) {
	    rb_thread_stop();
	}

	Tcl_UntraceVar(interp, nameString,
		       TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
		       rb_threadVwaitProc, (ClientData) param);
	break;
    }

    case TKWAIT_VISIBILITY: {
	Tk_Window window;

	window = Tk_NameToWindow(interp, nameString, tkwin);
	if (window == NULL) {
	    return TCL_ERROR;
	}
	Tk_CreateEventHandler(window,
			      VisibilityChangeMask|StructureNotifyMask,
			      rb_threadWaitVisibilityProc, (ClientData) param);
	if (!param->done) {
	    rb_thread_stop();
	}
	if (param->done != 1) {
	    /*
	     * Note that we do not delete the event handler because it
	     * was deleted automatically when the window was destroyed.
	     */

	    Tcl_ResetResult(interp);
	    Tcl_AppendResult(interp, "window \"", nameString,
			     "\" was deleted before its visibility changed",
			     (char *) NULL);
	    return TCL_ERROR;
	}
	Tk_DeleteEventHandler(window,
			      VisibilityChangeMask|StructureNotifyMask,
			      rb_threadWaitVisibilityProc, (ClientData) param);
	break;
    }

    case TKWAIT_WINDOW: {
	Tk_Window window;
            
	window = Tk_NameToWindow(interp, nameString, tkwin);
	if (window == NULL) {
	    return TCL_ERROR;
	}
	Tk_CreateEventHandler(window, StructureNotifyMask,
			      rb_threadWaitWindowProc, (ClientData) param);
	if (!param->done) {
	    rb_thread_stop();
	}
	/*
	 * Note:  there's no need to delete the event handler.  It was
	 * deleted automatically when the window was destroyed.
	 */
	break;
    }
    }

    Tcl_Free((char *)param);

    /*
     * Clear out the interpreter's result, since it may have been set
     * by event handlers.
     */

    Tcl_ResetResult(interp);
    return TCL_OK;
}

static VALUE
ip_thread_vwait(self, var)
    VALUE self;
    VALUE var;
{
    VALUE argv[2];

    argv[0] = rb_str_new2("thread_vwait");
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

    argv[0] = rb_str_new2("thread_tkwait");
    argv[1] = mode;
    argv[2] = target;
    return ip_invoke_real(3, argv, self);
}


/* destroy interpreter */
static void
ip_free(ptr)
    struct tcltkip *ptr;
{
    DUMP1("Tcl_DeleteInterp");
    if (ptr) {
	Tcl_Release((ClientData)ptr->ip);
	Tcl_DeleteInterp(ptr->ip);
	free(ptr);
    }
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
    struct tcltkip *ptr;	/* tcltkip data struct */
    VALUE argv0, opts;
    int cnt;
    int with_tk = 1;

    /* create object */
    Data_Get_Struct(self, struct tcltkip, ptr);
    ptr = ALLOC(struct tcltkip);
    DATA_PTR(self) = ptr;
    ptr->return_value = 0;

    /* from Tk_Main() */
    DUMP1("Tcl_CreateInterp");
    ptr->ip = Tcl_CreateInterp();
    Tcl_Preserve((ClientData)ptr->ip);
    current_interp = ptr->ip;

    /* from Tcl_AppInit() */
    DUMP1("Tcl_Init");
    if (Tcl_Init(ptr->ip) == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }

    /* set variables */
    cnt = rb_scan_args(argc, argv, "02", &argv0, &opts);
    switch(cnt) {
    case 2:
	/* options */
	if (opts == Qnil || opts == Qfalse) {
	    /* without Tk */
	    with_tk = 0;
	} else {
	    Tcl_SetVar(ptr->ip, "argv", StringValuePtr(opts), 0);
	}
    case 1:
	/* argv0 */
	if (argv0 != Qnil) {
	    Tcl_SetVar(ptr->ip, "argv0", StringValuePtr(argv0), 0);
	}
    case 0:
	/* no args */
	;
    }

    /* from Tcl_AppInit() */
    if (with_tk) {
	DUMP1("Tk_Init");
	if (Tk_Init(ptr->ip) == TCL_ERROR) {
	    rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
	}
	DUMP1("Tcl_StaticPackage(\"Tk\")");
#if TCL_MAJOR_VERSION >= 8
	Tcl_StaticPackage(ptr->ip, "Tk", Tk_Init, Tk_SafeInit);
#else
	Tcl_StaticPackage(ptr->ip, "Tk", Tk_Init,
			  (Tcl_PackageInitProc *) NULL);
#endif
    }

    /* add ruby command to the interpreter */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"ruby\")");
    Tcl_CreateObjCommand(ptr->ip, "ruby", ip_ruby, (ClientData)NULL,
			 (Tcl_CmdDeleteProc *)NULL);
#else
    DUMP1("Tcl_CreateCommand(\"ruby\")");
    Tcl_CreateCommand(ptr->ip, "ruby", ip_ruby, (ClientData)NULL,
		      (Tcl_CmdDeleteProc *)NULL);
#endif

    /* replace 'vwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"vwait\")");
    Tcl_CreateObjCommand(ptr->ip, "vwait", ip_rbVwaitObjCmd, 
			 (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#else
    DUMP1("Tcl_CreateCommand(\"vwait\")");
    Tcl_CreateCommand(ptr->ip, "vwait", ip_rbVwaitCommand, 
		      (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* replace 'tkwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"tkwait\")");
    Tcl_CreateObjCommand(ptr->ip, "tkwait", ip_rbTkWaitObjCmd, 
			 (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#else
    DUMP1("Tcl_CreateCommand(\"tkwait\")");
    Tcl_CreateCommand(ptr->ip, "tkwait", ip_rbTkWaitCommand, 
		      (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'thread_vwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_vwait\")");
    Tcl_CreateObjCommand(ptr->ip, "thread_vwait", ip_rb_threadVwaitObjCmd, 
			 (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#else
    DUMP1("Tcl_CreateCommand(\"thread_vwait\")");
    Tcl_CreateCommand(ptr->ip, "thread_vwait", ip_rb_threadVwaitCommand, 
		      (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'thread_tkwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_tkwait\")");
    Tcl_CreateObjCommand(ptr->ip, "thread_tkwait", ip_rb_threadTkWaitObjCmd, 
			 (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#else
    DUMP1("Tcl_CreateCommand(\"thread_tkwait\")");
    Tcl_CreateCommand(ptr->ip, "thread_tkwait", ip_rb_threadTkWaitCommand, 
		      (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#endif

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
    VALUE name;
    VALUE safemode;
    int safe;

    /* safe-mode check */
    if (rb_scan_args(argc, argv, "11", &name, &safemode) == 1) {
	safemode = Qfalse;
    }
    if (Tcl_IsSafe(master->ip) == 1) {
	safe = 1;
    } else if (safemode == Qfalse || safemode == Qnil) {
	safe = 0;
	rb_secure(4);
    } else {
	safe = 1;
    }

    /* create slave-ip */
    if ((slave->ip = Tcl_CreateSlave(master->ip, StringValuePtr(name), safe)) 
	== NULL) {
	rb_raise(rb_eRuntimeError, "fail to create the new slave interpreter");
    }
    Tcl_Preserve((ClientData)slave->ip);
    slave->return_value = 0;

    return Data_Wrap_Struct(CLASS_OF(self), 0, ip_free, slave);
}

/* make ip "safe" */
static VALUE
ip_make_safe(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    
    if (Tcl_MakeSafe(ptr->ip) == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }

    return self;
}

/* is safe? */
static VALUE
ip_is_safe_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    
    if (Tcl_IsSafe(ptr->ip)) {
	return Qtrue;
    } else {
	return Qfalse;
    }
}

/* delete interpreter */
static VALUE
ip_delete(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    Tcl_DeleteInterp(ptr->ip);

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

/* eval string in tcl by Tcl_Eval() */
static VALUE
ip_eval(self, str)
    VALUE self;
    VALUE str;
{
    char *s;
    char *buf;	/* Tcl_Eval requires re-writable string region */
    struct tcltkip *ptr = get_ip(self);

    /* call Tcl_Eval() */
    s = StringValuePtr(str);
    buf = ALLOCA_N(char, strlen(s)+1);
    strcpy(buf, s);
    DUMP2("Tcl_Eval(%s)", buf);
    ptr->return_value = Tcl_Eval(ptr->ip, buf);
    if (ptr->return_value == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }
    DUMP2("(TCL_Eval result) %d", ptr->return_value);

    /* pass back the result (as string) */
    /* return(rb_str_new2(ptr->ip->result)); */
    return(rb_tainted_str_new2(ptr->ip->result));
}

static VALUE
ip_toUTF8(self, str, encodename)
    VALUE self;
    VALUE str;
    VALUE encodename;
{
#ifdef TCL_UTF_MAX
    Tcl_Interp *interp;
    Tcl_Encoding encoding;
    Tcl_DString dstr;
    struct tcltkip *ptr;
    char *buf;

    ptr = get_ip(self);
    interp = ptr->ip;

    StringValue(encodename);
    StringValue(str);
    encoding = Tcl_GetEncoding(interp, RSTRING(encodename)->ptr);
    if (!RSTRING(str)->len) return str;
    buf = ALLOCA_N(char,strlen(RSTRING(str)->ptr)+1);
    strcpy(buf, RSTRING(str)->ptr);

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    Tcl_ExternalToUtfDString(encoding,buf,strlen(buf),&dstr);
    /* str = rb_str_new2(Tcl_DStringValue(&dstr)); */
    str = rb_tainted_str_new2(Tcl_DStringValue(&dstr));

    Tcl_FreeEncoding(encoding);
    Tcl_DStringFree(&dstr);
#endif
    return str;
}

static VALUE
ip_fromUTF8(self, str, encodename)
    VALUE self;
    VALUE str;
    VALUE encodename;
{
#ifdef TCL_UTF_MAX
    Tcl_Interp *interp;
    Tcl_Encoding encoding;
    Tcl_DString dstr;
    struct tcltkip *ptr;
    char *buf;

    ptr = get_ip(self);
    interp = ptr->ip;

    StringValue(encodename);
    StringValue(str);
    encoding = Tcl_GetEncoding(interp,RSTRING(encodename)->ptr);
    if (!RSTRING(str)->len) return str;
    buf = ALLOCA_N(char,strlen(RSTRING(str)->ptr)+1);
    strcpy(buf,RSTRING(str)->ptr);

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    Tcl_UtfToExternalDString(encoding,buf,strlen(buf),&dstr);
    /* str = rb_str_new2(Tcl_DStringValue(&dstr)); */
    str = rb_tainted_str_new2(Tcl_DStringValue(&dstr));

    Tcl_FreeEncoding(encoding);
    Tcl_DStringFree(&dstr);

#endif
    return str;
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
    rb_iv_set(einfo, "interp", interp);
    Tcl_ResetResult(get_ip(interp)->ip);
    return einfo;
}


static VALUE
ip_invoke_real(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE v;
    struct tcltkip *ptr;	/* tcltkip data struct */
    int i;
    Tcl_CmdInfo info;
    char *cmd, *s;
    char **av = (char **)NULL;
#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **ov = (Tcl_Obj **)NULL;
    Tcl_Obj *resultPtr;
#endif

    DUMP2("invoke_real called by thread:%lx", rb_thread_current());
    /* get the command name string */
    v = argv[0];
    cmd = StringValuePtr(v);

    /* get the data struct */
    ptr = get_ip(obj);

    /* ip is deleted? */
    if (Tcl_InterpDeleted(ptr->ip)) {
	return rb_tainted_str_new2("");
    }

    /* map from the command name to a C procedure */
    DUMP2("call Tcl_GetCommandInfo, %s", cmd);
    if (!Tcl_GetCommandInfo(ptr->ip, cmd, &info)) {
    DUMP1("error Tcl_GetCommandInfo");
	/* if (event_loop_abort_on_exc || cmd[0] != '.') { */
	if (event_loop_abort_on_exc > 0) {
	    /*rb_ip_raise(obj,rb_eNameError,"invalid command name `%s'",cmd);*/
	    return create_ip_exc(obj, rb_eNameError, 
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

    /* memory allocation for arguments of this command */
#if TCL_MAJOR_VERSION >= 8
    if (info.isNativeObjectProc) {
	/* object interface */
	ov = (Tcl_Obj **)ALLOCA_N(Tcl_Obj *, argc+1);
	for (i = 0; i < argc; ++i) {
	    v = argv[i];
	    s = StringValuePtr(v);
	    ov[i] = Tcl_NewStringObj(s, RSTRING(v)->len);
	    Tcl_IncrRefCount(ov[i]);
	}
	ov[argc] = (Tcl_Obj *)NULL;
    } 
    else
#endif
    {
	/* string interface */
	av = (char **)ALLOCA_N(char *, argc+1);
	for (i = 0; i < argc; ++i) {
	    v = argv[i];
	    s = StringValuePtr(v);
	    av[i] = ALLOCA_N(char, strlen(s)+1);
	    strcpy(av[i], s);
	}
	av[argc] = (char *)NULL;
    }

    Tcl_ResetResult(ptr->ip);

    /* Invoke the C procedure */
#if TCL_MAJOR_VERSION >= 8
    if (info.isNativeObjectProc) {
	int dummy;
	ptr->return_value = (*info.objProc)(info.objClientData,
					    ptr->ip, argc, ov);

	/* get the string value from the result object */
	resultPtr = Tcl_GetObjResult(ptr->ip);
	Tcl_SetResult(ptr->ip, Tcl_GetStringFromObj(resultPtr, &dummy),
		      TCL_VOLATILE);

	for (i=0; i<argc; i++) {
	    Tcl_DecrRefCount(ov[i]);
	}
    }
    else
#endif
    {
	TRAP_BEG;
#if TCL_MAJOR_VERSION >= 8
# ifdef CONST84 /* Tcl8.4.x -- ?.?.? (current latest version is 8.4.4) */
	ptr->return_value = (*info.proc)(info.clientData, ptr->ip, 
					 argc, (CONST84 char **)av);
# else
#  if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION <= 4 /* Tcl8.0.x -- 8.4b1 */
	ptr->return_value = (*info.proc)(info.clientData, ptr->ip, argc, av);

#  else /* unknown (maybe TCL_VERSION >= 8.5) */
#   ifdef CONST
	ptr->return_value = (*info.proc)(info.clientData, ptr->ip, 
					 argc, (CONST char **)av);
#   else
	ptr->return_value = (*info.proc)(info.clientData, ptr->ip, argc, av);
#   endif
#  endif
# endif
#else /* TCL_MAJOR_VERSION < 8 */
	ptr->return_value = (*info.proc)(info.clientData, ptr->ip, argc, av);
#endif
	TRAP_END;
    }

    /* exception on mainloop */
    if (ptr->return_value == TCL_ERROR) {
	if (event_loop_abort_on_exc > 0 && !Tcl_InterpDeleted(ptr->ip)) {
	    /*rb_ip_raise(obj, rb_eRuntimeError, "%s", ptr->ip->result);*/
	    return create_ip_exc(obj, rb_eRuntimeError, "%s", ptr->ip->result);
	} else {
	    if (event_loop_abort_on_exc < 0) {
		rb_warning("%s (ignore)", ptr->ip->result);
	    } else {
		rb_warn("%s (ignore)", ptr->ip->result);
	    }
	    Tcl_ResetResult(ptr->ip);
	    return rb_tainted_str_new2("");
	}
    }

    /* pass back the result (as string) */
    /* return rb_str_new2(ptr->ip->result); */
    return rb_tainted_str_new2(ptr->ip->result);
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
    return ip_invoke_real(q->argc, q->argv, q->obj);
}

int invoke_queue_handler _((Tcl_Event *, int));
int
invoke_queue_handler(evPtr, flags)
    Tcl_Event *evPtr;
    int flags;
{
    struct invoke_queue *q = (struct invoke_queue *)evPtr;

    DUMP2("do_invoke_queue_handler : evPtr = %lx", evPtr);
    DUMP2("invoke queue_thread : %lx", rb_thread_current());
    DUMP2("added by thread : %lx", q->thread);

    if (q->done) {
	DUMP1("processed by another event-loop");
	return 0;
    } else {
	DUMP1("process it on current event-loop");
    }

    /* process it */
    q->done = 1;

    /* check safe-level */
    if (rb_safe_level() != q->safe_level) {
	*(q->result) 
	    = rb_funcall(rb_proc_new(ivq_safelevel_handler, 
				     Data_Wrap_Struct(rb_cData,0,0,q)), 
			 rb_intern("call"), 0);
    } else {
    DUMP2("call invoke_real (for caller thread:%lx)", q->thread);
    DUMP2("call invoke_real (current thread:%lx)", rb_thread_current());
	*(q->result) = ip_invoke_real(q->argc, q->argv, q->obj);
    }

    /* back to caller */
    DUMP2("back to caller (caller thread:%lx)", q->thread);
    DUMP2("               (current thread:%lx)", rb_thread_current());
    rb_thread_run(q->thread);
    DUMP1("finish back to caller");

    /* end of handler : remove it */
    return 1;
}

static VALUE
ip_invoke(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    struct invoke_queue *tmp;
    VALUE current = rb_thread_current();
    VALUE result;
    VALUE *alloc_argv, *alloc_result;
    Tcl_QueuePosition position;

    if (argc < 1) {
	rb_raise(rb_eArgError, "command name missing");
    }
    if (eventloop_thread == 0 || current == eventloop_thread) {
	if (eventloop_thread) {
	    DUMP2("invoke from current eventloop %lx", current);
	} else {
	    DUMP2("invoke from thread:%lx but no eventloop", current);
	}
	result = ip_invoke_real(argc, argv, obj);
	if (rb_obj_is_kind_of(result, rb_eException)) {
	    rb_exc_raise(result);
	}
	return result;
    }

    DUMP2("invoke from thread %lx (NOT current eventloop)", current);

    /* allocate memory (protected from Tcl_ServiceEvent) */
    alloc_argv =  ALLOC_N(VALUE,argc);
    MEMCPY(alloc_argv, argv, VALUE, argc);
    alloc_result = ALLOC(VALUE);

    /* allocate memory (freed by Tcl_ServiceEvent) */
    tmp = (struct invoke_queue *)Tcl_Alloc(sizeof(struct invoke_queue));

    /* construct event data */
    tmp->done = 0;
    tmp->obj = obj;
    tmp->argc = argc;
    tmp->argv = alloc_argv;
    tmp->result = alloc_result;
    tmp->thread = current;
    tmp->safe_level = rb_safe_level();
    tmp->ev.proc = invoke_queue_handler;
    position = TCL_QUEUE_TAIL;

    /* add the handler to Tcl event queue */
    DUMP1("add handler");
    Tcl_QueueEvent(&(tmp->ev), position);

    /* wait for the handler to be processed */
    DUMP2("wait for handler (current thread:%lx)", current);
    rb_thread_stop();
    DUMP2("back from handler (current thread:%lx)", current);

    /* get result & free allocated memory */
    result = *alloc_result;
    free(alloc_argv);
    free(alloc_result);
    if (rb_obj_is_kind_of(result, rb_eException)) {
	rb_exc_raise(result);
    }

    return result;
}

/* get return code from Tcl_Eval() */
static VALUE
ip_retval(self)
    VALUE self;
{
    struct tcltkip *ptr;	/* tcltkip data struct */

    /* get the data strcut */
    ptr = get_ip(self);

    return (INT2FIX(ptr->return_value));
}

#ifdef __MACOS__
static void
_macinit()
{
    tcl_macQdPtr = &qd; /* setup QuickDraw globals */
    Tcl_MacSetEventProc(TkMacConvertEvent); /* setup event handler */
}
#endif

/*---- initialization ----*/
void
Init_tcltklib()
{
    VALUE lib = rb_define_module("TclTkLib");
    VALUE ip = rb_define_class("TclTkIp", rb_cObject);

    VALUE ev_flag = rb_define_module_under(lib, "EventFlag");

#if defined USE_TCL_STUBS && defined USE_TK_STUBS
    extern int ruby_tcltk_stubs();
    int ret = ruby_tcltk_stubs();
    if (ret)
	rb_raise(rb_eLoadError, "tcltklib: tcltk_stubs init error(%d)", ret);
#endif

    rb_define_const(ev_flag, "NONE",      INT2FIX(0));
    rb_define_const(ev_flag, "WINDOW",    INT2FIX(TCL_WINDOW_EVENTS));
    rb_define_const(ev_flag, "FILE",      INT2FIX(TCL_FILE_EVENTS));
    rb_define_const(ev_flag, "TIMER",     INT2FIX(TCL_TIMER_EVENTS));
    rb_define_const(ev_flag, "IDLE",      INT2FIX(TCL_IDLE_EVENTS));
    rb_define_const(ev_flag, "ALL",       INT2FIX(TCL_ALL_EVENTS));
    rb_define_const(ev_flag, "DONT_WAIT", INT2FIX(TCL_DONT_WAIT));

    eTkCallbackBreak = rb_define_class("TkCallbackBreak", rb_eStandardError);
    eTkCallbackContinue = rb_define_class("TkCallbackContinue",
                                          rb_eStandardError);

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
    rb_define_module_function(lib, "get_eventloop_weight", 
			      get_eventloop_weight, 0);
    rb_define_module_function(lib, "num_of_mainwindows", 
			      lib_num_of_mainwindows, 0);

    rb_define_alloc_func(ip, ip_alloc);
    rb_define_method(ip, "initialize", ip_init, -1);
    rb_define_method(ip, "create_slave", ip_create_slave, -1);
    rb_define_method(ip, "make_safe", ip_make_safe, 0);
    rb_define_method(ip, "safe?", ip_is_safe_p, 0);
    rb_define_method(ip, "delete", ip_delete, 0);
    rb_define_method(ip, "deleted?", ip_is_deleted_p, 0);
    rb_define_method(ip, "_eval", ip_eval, 1);
    rb_define_method(ip, "_toUTF8",ip_toUTF8, 2);
    rb_define_method(ip, "_fromUTF8",ip_fromUTF8, 2);
    rb_define_method(ip, "_thread_vwait", ip_thread_vwait, 1);
    rb_define_method(ip, "_thread_tkwait", ip_thread_tkwait, 2);
    rb_define_method(ip, "_invoke", ip_invoke, -1);
    rb_define_method(ip, "_return_value", ip_retval, 0);

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
    rb_define_method(ip, "restart", ip_restart, 0);

    eventloop_thread = 0;
    watchdog_thread  = 0;

#ifdef __MACOS__
    _macinit();
#endif

    /*---- initialize tcl/tk libraries ----*/
    /* from Tk_Main() */
    DUMP1("Tcl_FindExecutable");
    Tcl_FindExecutable(RSTRING(rb_argv0)->ptr);
}

/* eof */
