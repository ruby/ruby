/*
 *	tcltklib.c
 *		Aug. 27, 1997	Y. Shigehiro
 *		Oct. 24, 1997	Y. Matsumoto
 */

#include "ruby.h"
#include "rubysig.h"
#undef EXTERN	/* avoid conflict with tcl.h of tcl8.2 or before */
#include <stdio.h>
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
 
static VALUE main_thread;
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
static int tick_counter;
#define DEFAULT_EVENT_LOOP_MAX  800
#define DEFAULT_NO_EVENT_TICK    10
#define DEFAULT_TIMER_TICK        0
static int event_loop_max = DEFAULT_EVENT_LOOP_MAX;
static int no_event_tick  = DEFAULT_NO_EVENT_TICK;
static int timer_tick     = DEFAULT_TIMER_TICK;

#if TCL_MAJOR_VERSION >= 8
static int ip_ruby _((ClientData, Tcl_Interp *, int, Tcl_Obj *CONST*));
#else
static int ip_ruby _((ClientData, Tcl_Interp *, int, char **));
#endif

/* Tk_ThreadTimer */
static Tcl_TimerToken timer_token = (Tcl_TimerToken)NULL;

/* timer callback */
static void _timer_for_tcl _((ClientData));
static void
_timer_for_tcl(clientData)
    ClientData clientData;
{
    struct invoke_queue *q, *tmp;
    VALUE thread;

    Tk_DeleteTimerHandler(timer_token);
    if (timer_tick > 0) {
      timer_token = Tk_CreateTimerHandler(timer_tick, _timer_for_tcl, 
					  (ClientData)0);
    } else {
      timer_token = (Tcl_TimerToken)NULL;
    }

    /* rb_thread_schedule(); */
    timer_tick += event_loop_max;
}

static VALUE
set_eventloop_tick(self, tick)
    VALUE self;
    VALUE tick;
{
    int ttick = NUM2INT(tick);

    if (ttick < 0) {
      rb_raise(rb_eArgError, "timer-tick parameter must be 0 or plus number");
    }

    /* delete old timer callback */
    Tk_DeleteTimerHandler(timer_token);

    timer_tick = ttick;
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
set_eventloop_weight(self, loop_max, no_event)
    VALUE self;
    VALUE loop_max;
    VALUE no_event;
{
    int lpmax = NUM2INT(loop_max);
    int no_ev = NUM2INT(no_event);

    if (lpmax <= 0 || no_ev <= 0) {
      rb_raise(rb_eArgError, "weight parameters must be plus number");
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

VALUE
lib_mainloop_core(check_root_widget)
    VALUE check_root_widget;
{
    VALUE current = eventloop_thread;
    int check = (check_root_widget == Qtrue);

    Tk_DeleteTimerHandler(timer_token);
    if (timer_tick > 0) {
      timer_token = Tk_CreateTimerHandler(timer_tick, _timer_for_tcl, 
					  (ClientData)0);
    } else {
      timer_token = (Tcl_TimerToken)NULL;
    }

    for(;;) {
      tick_counter = 0;
      while(tick_counter < event_loop_max) {
        if (Tcl_DoOneEvent(TCL_ALL_EVENTS | TCL_DONT_WAIT)) {
          tick_counter++;
	} else {
          tick_counter += no_event_tick;
	}
	if (watchdog_thread != 0 && eventloop_thread != current) {
	  return Qnil;
	}
      }
      if (check && Tk_GetNumMainWindows() == 0) {
	break;
      }
      rb_thread_schedule();
    }
    return Qnil;
}

VALUE
lib_mainloop_ensure(parent_evloop)
    VALUE parent_evloop;
{
    Tk_DeleteTimerHandler(timer_token);
    timer_token = (Tcl_TimerToken)NULL;
    DUMP2("mainloop-ensure: current-thread : %lx\n", rb_thread_current());
    DUMP2("mainloop-ensure: eventloop-thread : %lx\n", eventloop_thread);
    if (eventloop_thread == rb_thread_current()) {
      DUMP2("tcltklib: eventloop-thread -> %lx\n", parent_evloop);
      eventloop_thread = parent_evloop;
    }
    return Qnil;
}

static VALUE
lib_mainloop_launcher(check_rootwidget)
    VALUE check_rootwidget;
{
    VALUE parent_evloop = eventloop_thread;

    eventloop_thread = rb_thread_current();

    if (ruby_debug) { 
      fprintf(stderr, "tcltklib: eventloop-thread : %lx -> %lx\n", 
	      parent_evloop, eventloop_thread);
    }

    return rb_ensure(lib_mainloop_core, check_rootwidget, 
		     lib_mainloop_ensure, parent_evloop);
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

    return lib_mainloop_launcher(check_rootwidget);
}

VALUE
lib_watchdog_core(check_rootwidget)
    VALUE check_rootwidget;
{
    VALUE current = eventloop_thread;
    VALUE evloop;
    int   check = (check_rootwidget == Qtrue);
    ID    stop = rb_intern("stop?");

    /* check other watchdog thread */
    if (watchdog_thread != 0) {
      if (rb_funcall(watchdog_thread, stop, 0) == Qtrue) {
	rb_funcall(watchdog_thread, rb_intern("kill"), 0);
      } else {
	return Qnil;
      }
    }
    watchdog_thread = rb_thread_current();

    /* watchdog start */
    do {
      if (eventloop_thread == 0 
	  || rb_funcall(eventloop_thread, stop, 0) == Qtrue) {
	/* start new eventloop thread */
	DUMP2("eventloop thread %lx is sleeping or dead", eventloop_thread);
	evloop = rb_thread_create(lib_mainloop_launcher, 
				  (void*)&check_rootwidget);
	DUMP2("create new eventloop thread %lx", evloop);
	rb_thread_run(evloop);
      } else {
	rb_thread_schedule();
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
lib_do_one_event(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    VALUE obj, vflags;
    int flags;

    if (rb_scan_args(argc, argv, "01", &vflags) == 0) {
      flags = 0;
    } else {
      Check_Type(vflags, T_FIXNUM);
      flags = FIX2INT(vflags);
    }
    return INT2NUM(Tcl_DoOneEvent(flags));
}

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

    /* destroy the root wdiget */
    ptr->return_value = Tcl_Eval(ptr->ip, "destroy .");
    /* ignore ERROR */
    DUMP2("(TCL_Eval result) %d", ptr->return_value);

    /* execute Tk_Init */
    DUMP1("Tk_Init");
    if (Tk_Init(ptr->ip) == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }

    return Qnil;
}

#if TCL_MAJOR_VERSION >= 8
static int ip_ruby _((ClientData, Tcl_Interp *, int, Tcl_Obj *CONST []));
static int
ip_ruby(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int argc;
    Tcl_Obj *CONST argv[];
#else
static int ip_ruby _((ClientData, Tcl_Interp *, int, Tcl_Obj *[]));
static int
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
                     rb_eStandardError, rb_eScriptError, 0);
    rb_trap_immediate = old_trapflg;

    Tcl_ResetResult(interp);
    if (failed) {
        VALUE eclass = CLASS_OF(failed);
	Tcl_AppendResult(interp, STR2CSTR(failed), (char*)NULL);
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
	return TCL_OK;
    }

    /* copy result to the tcl interpreter */
    DUMP2("(rb_eval_string result) %s", STR2CSTR(res));
    DUMP1("Tcl_AppendResult");
    Tcl_AppendResult(interp, STR2CSTR(res), (char *)NULL);

    return TCL_OK;
}

/* destroy interpreter */
static void
ip_free(ptr)
    struct tcltkip *ptr;
{
    DUMP1("Tcl_DeleteInterp");
    if (ptr) {
	Tcl_DeleteInterp(ptr->ip);
	free(ptr);
    }
}

/* create and initialize interpreter */
static VALUE
ip_new(self)
    VALUE self;
{
    struct tcltkip *ptr;	/* tcltkip data struct */
    VALUE obj;			/* newly created object */

    /* create object */
    obj = Data_Make_Struct(self, struct tcltkip, 0, ip_free, ptr);
    ptr->return_value = 0;

    /* from Tk_Main() */
    DUMP1("Tcl_CreateInterp");
    ptr->ip = Tcl_CreateInterp();

    /* from Tcl_AppInit() */
    DUMP1("Tcl_Init");
    if (Tcl_Init(ptr->ip) == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }
    DUMP1("Tk_Init");
    if (Tk_Init(ptr->ip) == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }
    DUMP1("Tcl_StaticPackage(\"Tk\")");
    Tcl_StaticPackage(ptr->ip, "Tk", Tk_Init,
		      (Tcl_PackageInitProc *) NULL);

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

    return obj;
}

/* eval string in tcl by Tcl_Eval() */
static VALUE
ip_eval(self, str)
    VALUE self;
    VALUE str;
{
    char *s;
    char *buf;			/* Tcl_Eval requires re-writable string region */
    struct tcltkip *ptr = get_ip(self);

    /* call Tcl_Eval() */
    s = STR2CSTR(str);
    buf = ALLOCA_N(char, strlen(s)+1);
    strcpy(buf, s);
    DUMP2("Tcl_Eval(%s)", buf);
    ptr->return_value = Tcl_Eval(ptr->ip, buf);
    if (ptr->return_value == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }
    DUMP2("(TCL_Eval result) %d", ptr->return_value);

    /* pass back the result (as string) */
    return(rb_str_new2(ptr->ip->result));
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

    encoding = Tcl_GetEncoding(interp,STR2CSTR(encodename));
    buf = ALLOCA_N(char,strlen(STR2CSTR(str))+1);
    strcpy(buf,STR2CSTR(str));

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    Tcl_ExternalToUtfDString(encoding,buf,strlen(buf),&dstr);
    str = rb_str_new2(Tcl_DStringValue(&dstr));

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

    encoding = Tcl_GetEncoding(interp,STR2CSTR(encodename));
    buf = ALLOCA_N(char,strlen(STR2CSTR(str))+1);
    strcpy(buf,STR2CSTR(str));

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    Tcl_UtfToExternalDString(encoding,buf,strlen(buf),&dstr);
    str = rb_str_new2(Tcl_DStringValue(&dstr));

    Tcl_FreeEncoding(encoding);
    Tcl_DStringFree(&dstr);

#endif
    return str;
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

    /* get the data struct */
    ptr = get_ip(obj);

    /* get the command name string */
    v = argv[0];
    cmd = STR2CSTR(v);

    /* map from the command name to a C procedure */
    if (!Tcl_GetCommandInfo(ptr->ip, cmd, &info)) {
	rb_raise(rb_eNameError, "invalid command name `%s'", cmd);
    }

    /* memory allocation for arguments of this command */
#if TCL_MAJOR_VERSION >= 8
    if (info.isNativeObjectProc) {
	/* object interface */
	ov = (Tcl_Obj **)ALLOCA_N(Tcl_Obj *, argc+1);
	for (i = 0; i < argc; ++i) {
	    v = argv[i];
	    s = STR2CSTR(v);
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
	    s = STR2CSTR(v);
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
	ptr->return_value = (*info.proc)(info.clientData, ptr->ip, argc, av);
	TRAP_END;
    }

    if (ptr->return_value == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }

    /* pass back the result (as string) */
    return rb_str_new2(ptr->ip->result);
}

VALUE
ivq_safelevel_handler(ivq)
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
    struct invoke_queue *tmp, *q = (struct invoke_queue *)evPtr;

    DUMP1("do_invoke_queue_handler");
    DUMP2("invoke queue_thread : %lx", rb_thread_current());
    DUMP2("added by thread : %lx", q->thread);

    if (q->done) {
      /* processed by another event-loop */
      return 0;
    }

    /* process it */
    q->done = 1;

    /* check safe-level */
    if (rb_safe_level() != q->safe_level) {
      VALUE v = Data_Wrap_Struct(rb_cData,0,0,q);
      rb_define_singleton_method(v, "handler", ivq_safelevel_handler, 0);
      *(q->result) = rb_funcall(rb_funcall(v, rb_intern("method"), 1, rb_intern("handler")),
				rb_intern("call"), 0);
    } else {
      *(q->result) = ip_invoke_real(q->argc, q->argv, q->obj);
    }

    /* back to caller */
    rb_thread_run(q->thread);

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
      DUMP2("invoke from current eventloop %lx", current);
      return ip_invoke_real(argc, argv, obj);
    }

    DUMP2("invoke from thread %lx (NOT current eventloop)", current);

    /* allocate memory (protected from Tcl_ServiceEvent) */
    alloc_argv =  ALLOC_N(VALUE,argc);
    MEMCPY(alloc_argv, argv, VALUE, argc);
    alloc_result = ALLOC(VALUE);

    /* allocate memory (freed by Tcl_ServiceEvent */
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
    Tcl_QueueEvent(&tmp->ev, position);

    /* wait for the handler to be processed */
    rb_thread_stop();

    /* get result & free allocated memory */
    result = *alloc_result;
    free(alloc_argv);
    free(alloc_result);

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

    rb_define_const(ev_flag, "WINDOW",    INT2FIX(TCL_WINDOW_EVENTS));
    rb_define_const(ev_flag, "FILE",      INT2FIX(TCL_FILE_EVENTS));
    rb_define_const(ev_flag, "TIMER",     INT2FIX(TCL_TIMER_EVENTS));
    rb_define_const(ev_flag, "IDLE",      INT2FIX(TCL_IDLE_EVENTS));
    rb_define_const(ev_flag, "ALL",       INT2FIX(TCL_ALL_EVENTS));
    rb_define_const(ev_flag, "DONT_WAIT", INT2FIX(TCL_DONT_WAIT));

    eTkCallbackBreak = rb_define_class("TkCallbackBreak", rb_eStandardError);
    eTkCallbackContinue = rb_define_class("TkCallbackContinue",rb_eStandardError);

    rb_define_module_function(lib, "mainloop", lib_mainloop, -1);
    rb_define_module_function(lib, "mainloop_watchdog", 
			      lib_mainloop_watchdog, -1);
    rb_define_module_function(lib, "do_one_event", lib_do_one_event, -1);
    rb_define_module_function(lib, "set_eventloop_tick",set_eventloop_tick,1);
    rb_define_module_function(lib, "get_eventloop_tick",get_eventloop_tick,0);
    rb_define_module_function(lib, "set_eventloop_weight", 
			      set_eventloop_weight, 2);
    rb_define_module_function(lib, "get_eventloop_weight", 
			      get_eventloop_weight, 0);

    rb_define_singleton_method(ip, "new", ip_new, 0);
    rb_define_method(ip, "_eval", ip_eval, 1);
    rb_define_method(ip, "_toUTF8",ip_toUTF8,2);
    rb_define_method(ip, "_fromUTF8",ip_fromUTF8,2);
    rb_define_method(ip, "_invoke", ip_invoke, -1);
    rb_define_method(ip, "_return_value", ip_retval, 0);
    rb_define_method(ip, "mainloop", lib_mainloop, -1);
    rb_define_method(ip, "mainloop_watchdog", lib_mainloop_watchdog, -1);
    rb_define_method(ip, "do_one_event", lib_do_one_event, -1);
    rb_define_method(ip, "set_eventloop_tick", set_eventloop_tick, 1);
    rb_define_method(ip, "get_eventloop_tick", get_eventloop_tick, 0);
    rb_define_method(ip, "set_eventloop_weight", set_eventloop_weight, 2);
    rb_define_method(ip, "get_eventloop_weight", get_eventloop_weight, 0);
    rb_define_method(ip, "restart", lib_restart, 0);

    main_thread = rb_thread_current();
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
