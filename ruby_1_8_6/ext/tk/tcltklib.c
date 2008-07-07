/*
 *      tcltklib.c
 *              Aug. 27, 1997   Y. Shigehiro
 *              Oct. 24, 1997   Y. Matsumoto
 */

#define TCLTKLIB_RELEASE_DATE "2006-12-01"

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

#include "stubs.h"

#ifndef TCL_ALPHA_RELEASE
#define TCL_ALPHA_RELEASE       0
#define TCL_BETA_RELEASE        1
#define TCL_FINAL_RELEASE       2
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
#define DUMP3(ARG1, ARG2, ARG3) if (ruby_debug) { fprintf(stderr, "tcltklib: ");\
fprintf(stderr, ARG1, ARG2, ARG3); fprintf(stderr, "\n"); fflush(stderr); }
/*
#define DUMP1(ARG1)
#define DUMP2(ARG1, ARG2)
#define DUMP3(ARG1, ARG2, ARG3)
*/

/* release date */
const char tcltklib_release_date[] = TCLTKLIB_RELEASE_DATE;

/* finalize_proc_name */
static char *finalize_hook_name = "INTERP_FINALIZE_HOOK";

static void ip_finalize _((Tcl_Interp*));

static int at_exit = 0;


/* for callback break & continue */
static VALUE eTkCallbackReturn;
static VALUE eTkCallbackBreak;
static VALUE eTkCallbackContinue;

static VALUE eLocalJumpError;

static VALUE eTkLocalJumpError;
static VALUE eTkCallbackRetry;
static VALUE eTkCallbackRedo;
static VALUE eTkCallbackThrow;

static VALUE tcltkip_class;

static ID ID_at_enc;
static ID ID_at_interp;

static ID ID_stop_p;
static ID ID_alive_p;
static ID ID_kill;
static ID ID_join;
static ID ID_value;

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

static VALUE tk_funcall _((VALUE(), int, VALUE*, VALUE));

/* safe Tcl_Eval and Tcl_GlobalEval */
static int
tcl_eval(interp, cmd)
    Tcl_Interp *interp;
    const char *cmd; /* don't have to be writable */
{
    char *buf = strdup(cmd);
    int ret;

    Tcl_AllowExceptions(interp);
    ret = Tcl_Eval(interp, buf);
    free(buf);
    return ret;
}

#undef Tcl_Eval
#define Tcl_Eval tcl_eval

static int
tcl_global_eval(interp, cmd)
    Tcl_Interp *interp;
    const char *cmd; /* don't have to be writable */
{
    char *buf = strdup(cmd);
    int ret;

    Tcl_AllowExceptions(interp);
    ret = Tcl_GlobalEval(interp, buf);
    free(buf);
    return ret;
}

#undef Tcl_GlobalEval
#define Tcl_GlobalEval tcl_global_eval

/* Tcl_{Incr|Decr}RefCount for tcl7.x or earlier */
#if TCL_MAJOR_VERSION < 8
#define Tcl_IncrRefCount(obj) (1)
#define Tcl_DecrRefCount(obj) (1)
#endif

/* Tcl_GetStringResult for tcl7.x or earlier */
#if TCL_MAJOR_VERSION < 8
#define Tcl_GetStringResult(interp) ((interp)->result)
#endif

/* Tcl_[GS]etVar2Ex for tcl8.0 */
#if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
static Tcl_Obj *
Tcl_GetVar2Ex(interp, name1, name2, flags)
    Tcl_Interp *interp;
    CONST char *name1;
    CONST char *name2;
    int flags;
{
    Tcl_Obj *nameObj1, *nameObj2 = NULL, *retObj;

    nameObj1 = Tcl_NewStringObj((char*)name1, -1);
    Tcl_IncrRefCount(nameObj1);

    if (name2) {
        nameObj2 = Tcl_NewStringObj((char*)name2, -1);
        Tcl_IncrRefCount(nameObj2);
    }

    retObj = Tcl_ObjGetVar2(interp, nameObj1, nameObj2, flags);

    if (name2) {
        Tcl_DecrRefCount(nameObj2);
    }

    Tcl_DecrRefCount(nameObj1);

    return retObj;
}

static Tcl_Obj *
Tcl_SetVar2Ex(interp, name1, name2, newValObj, flags)
    Tcl_Interp *interp;
    CONST char *name1;
    CONST char *name2;
    Tcl_Obj *newValObj;
    int flags;
{
    Tcl_Obj *nameObj1, *nameObj2 = NULL, *retObj;

    nameObj1 = Tcl_NewStringObj((char*)name1, -1);
    Tcl_IncrRefCount(nameObj1);

    if (name2) {
        nameObj2 = Tcl_NewStringObj((char*)name2, -1);
        Tcl_IncrRefCount(nameObj2);
    }

    retObj = Tcl_ObjSetVar2(interp, nameObj1, nameObj2, newValObj, flags);

    if (name2) {
        Tcl_DecrRefCount(nameObj2);
    }

    Tcl_DecrRefCount(nameObj1);

    return retObj;
}
#endif

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

struct call_queue {
    Tcl_Event ev;
    VALUE (*func)();
    int argc;
    VALUE *argv;
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

void 
call_queue_mark(struct call_queue *q)
{
    int i;

    for(i = 0; i < q->argc; i++) {
        rb_gc_mark(q->argv[i]);
    }

    rb_gc_mark(q->interp);
    rb_gc_mark(q->result);
    rb_gc_mark(q->thread);
}


static VALUE eventloop_thread;
static VALUE eventloop_stack;

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


/* call ruby interpreter */
#if TCL_MAJOR_VERSION >= 8
static int ip_ruby_eval _((ClientData, Tcl_Interp *, int, Tcl_Obj *CONST*));
static int ip_ruby_cmd _((ClientData, Tcl_Interp *, int, Tcl_Obj *CONST*));
#else /* TCL_MAJOR_VERSION < 8 */
static int ip_ruby_eval _((ClientData, Tcl_Interp *, int, char **));
static int ip_ruby_cmd _((ClientData, Tcl_Interp *, int, char **));
#endif

struct cmd_body_arg {
    VALUE receiver;
    ID    method;
    VALUE args;
};


/*----------------------------*/
/* use Tcl internal functions */
/*----------------------------*/
#ifndef TCL_NAMESPACE_DEBUG
#define TCL_NAMESPACE_DEBUG 0
#endif

#if TCL_NAMESPACE_DEBUG

#if TCL_MAJOR_VERSION >= 8
EXTERN struct TclIntStubs *tclIntStubsPtr;
#endif

/*-- Tcl_GetCurrentNamespace --*/
#if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION < 5
/* Tcl7.x doesn't have namespace support.                            */
/* Tcl8.5+ has definition of Tcl_GetCurrentNamespace() in tclDecls.h */
#  ifndef Tcl_GetCurrentNamespace
EXTERN Tcl_Namespace *  Tcl_GetCurrentNamespace _((Tcl_Interp *));
#  endif
#  if defined(USE_TCL_STUBS) && !defined(USE_TCL_STUB_PROCS)
#    ifndef Tcl_GetCurrentNamespace
#      ifndef FunctionNum_of_GetCurrentNamespace
#define FunctionNum_of_GetCurrentNamespace 124
#      endif
struct DummyTclIntStubs_for_GetCurrentNamespace {
    int magic;
    struct TclIntStubHooks *hooks;
    void (*func[FunctionNum_of_GetCurrentNamespace])();
    Tcl_Namespace * (*tcl_GetCurrentNamespace) _((Tcl_Interp *));
};

#define Tcl_GetCurrentNamespace \
   (((struct DummyTclIntStubs_for_GetCurrentNamespace *)tclIntStubsPtr)->tcl_GetCurrentNamespace)
#    endif
#  endif
#endif

/* namespace check */
/* ip_null_namespace(Tcl_Interp *interp) */
#if TCL_MAJOR_VERSION < 8
#define ip_null_namespace(interp) (0)
#else /* support namespace */
#define ip_null_namespace(interp) \
    (Tcl_GetCurrentNamespace(interp) == (Tcl_Namespace *)NULL)
#endif

/* rbtk_invalid_namespace(tcltkip *ptr) */
#if TCL_MAJOR_VERSION < 8
#define rbtk_invalid_namespace(ptr) (0)
#else /* support namespace */
#define rbtk_invalid_namespace(ptr) \
    ((ptr)->default_ns == (Tcl_Namespace*)NULL || Tcl_GetCurrentNamespace((ptr)->ip) != (ptr)->default_ns)
#endif

/*-- Tcl_PopCallFrame & Tcl_PushCallFrame --*/
#if TCL_MAJOR_VERSION >= 8
#  ifndef CallFrame
typedef struct CallFrame {
    Tcl_Namespace *nsPtr;
    int dummy1;
    int dummy2;
    char *dummy3;
    struct CallFrame *callerPtr;
    struct CallFrame *callerVarPtr;
    int level;
    char *dummy7;
    char *dummy8;
    int dummy9;
    char* dummy10;
} CallFrame;
#  endif

#  if !defined(TclGetFrame) && !defined(TclGetFrame_TCL_DECLARED)
EXTERN int  TclGetFrame _((Tcl_Interp *, CONST char *, CallFrame **));
#  endif
#  if defined(USE_TCL_STUBS) && !defined(USE_TCL_STUB_PROCS)
#    ifndef TclGetFrame
#      ifndef FunctionNum_of_GetFrame
#define FunctionNum_of_GetFrame 32
#      endif
struct DummyTclIntStubs_for_GetFrame {
    int magic;
    struct TclIntStubHooks *hooks;
    void (*func[FunctionNum_of_GetFrame])();
    int (*tclGetFrame) _((Tcl_Interp *, CONST char *, CallFrame **));
};
#define TclGetFrame \
   (((struct DummyTclIntStubs_for_GetFrame *)tclIntStubsPtr)->tclGetFrame)
#    endif
#  endif

#  if !defined(Tcl_PopCallFrame) && !defined(Tcl_PopCallFrame_TCL_DECLARED)
EXTERN void Tcl_PopCallFrame _((Tcl_Interp *));
EXTERN int  Tcl_PushCallFrame _((Tcl_Interp *, Tcl_CallFrame *, Tcl_Namespace *, int));
#  endif
#  if defined(USE_TCL_STUBS) && !defined(USE_TCL_STUB_PROCS)
#    ifndef Tcl_PopCallFrame
#      ifndef FunctionNum_of_PopCallFrame
#define FunctionNum_of_PopCallFrame 128
#      endif
struct DummyTclIntStubs_for_PopCallFrame {
    int magic;
    struct TclIntStubHooks *hooks;
    void (*func[FunctionNum_of_PopCallFrame])();
    void (*tcl_PopCallFrame) _((Tcl_Interp *));
    int  (*tcl_PushCallFrame) _((Tcl_Interp *, Tcl_CallFrame *, Tcl_Namespace *, int));
};

#define Tcl_PopCallFrame \
   (((struct DummyTclIntStubs_for_PopCallFrame *)tclIntStubsPtr)->tcl_PopCallFrame)
#define Tcl_PushCallFrame \
   (((struct DummyTclIntStubs_for_PopCallFrame *)tclIntStubsPtr)->tcl_PushCallFrame)
#    endif
#  endif

#else /* Tcl7.x */
#  ifndef CallFrame
typedef struct CallFrame {
    Tcl_HashTable varTable;
    int level;
    int argc;
    char **argv;
    struct CallFrame *callerPtr;
    struct CallFrame *callerVarPtr;
} CallFrame;
#  endif
#  ifndef Tcl_CallFrame
#define Tcl_CallFrame CallFrame
#  endif

#  if !defined(TclGetFrame) && !defined(TclGetFrame_TCL_DECLARED)
EXTERN int  TclGetFrame _((Tcl_Interp *, CONST char *, CallFrame **));
#  endif

#  if !defined(Tcl_PopCallFrame) && !defined(Tcl_PopCallFrame_TCL_DECLARED)
typedef struct DummyInterp {
    char *dummy1;
    char *dummy2;
    int  dummy3;
    Tcl_HashTable dummy4;
    Tcl_HashTable dummy5;
    Tcl_HashTable dummy6;
    int numLevels;
    int maxNestingDepth;
    CallFrame *framePtr;
    CallFrame *varFramePtr;
} DummyInterp;

static void
Tcl_PopCallFrame(interp)
    Tcl_Interp *interp;
{
    DummyInterp *iPtr = (DummyInterp*)interp;
    CallFrame *frame = iPtr->varFramePtr;

    /* **** DUMMY **** */
    iPtr->framePtr = frame.callerPtr;
    iPtr->varFramePtr = frame.callerVarPtr;

    return TCL_OK;
}

/* dummy */
#define Tcl_Namespace char

static int
Tcl_PushCallFrame(interp, framePtr, nsPtr, isProcCallFrame)
    Tcl_Interp *interp;
    Tcl_CallFrame *framePtr;
    Tcl_Namespace *nsPtr;
    int isProcCallFrame;
{
    DummyInterp *iPtr = (DummyInterp*)interp;
    CallFrame *frame = (CallFrame *)framePtr;

    /* **** DUMMY **** */
    Tcl_InitHashTable(&frame.varTable, TCL_STRING_KEYS);
    if (iPtr->varFramePtr != NULL) {
        frame.level = iPtr->varFramePtr->level + 1;
    } else {
        frame.level = 1;
    }
    frame.callerPtr = iPtr->framePtr;
    frame.callerVarPtr = iPtr->varFramePtr;
    iPtr->framePtr = &frame;
    iPtr->varFramePtr = &frame;

    return TCL_OK;
}
#  endif

#endif

#endif /* TCL_NAMESPACE_DEBUG */


/*---- class TclTkIp ----*/
struct tcltkip {
    Tcl_Interp *ip;              /* the interpreter */
#if TCL_NAMESPACE_DEBUG
    Tcl_Namespace *default_ns;   /* default namespace */
#endif
    int has_orig_exit;           /* has original 'exit' command ? */
    Tcl_CmdInfo orig_exit_info;  /* command info of original 'exit' command */
    int ref_count;               /* reference count of rbtk_preserve_ip call */
    int allow_ruby_exit;         /* allow exiting ruby by 'exit' function */
    int return_value;            /* return value */
};

static struct tcltkip *
get_ip(self)
    VALUE self;
{
    struct tcltkip *ptr;

    Data_Get_Struct(self, struct tcltkip, ptr);
    if (ptr == 0) {
        /* rb_raise(rb_eTypeError, "uninitialized TclTkIp"); */
        return((struct tcltkip *)NULL);
    }
    if (ptr->ip == (Tcl_Interp*)NULL) {
        /* rb_raise(rb_eRuntimeError, "deleted IP"); */
        return((struct tcltkip *)NULL);
    }
    return ptr;
}

static int
deleted_ip(ptr)
    struct tcltkip *ptr;
{
    if (!ptr || !ptr->ip || Tcl_InterpDeleted(ptr->ip)
#if TCL_NAMESPACE_DEBUG
          || rbtk_invalid_namespace(ptr)
#endif
    ) {
        DUMP1("ip is deleted");
        return Qtrue;
    }
    return Qfalse;
}

/* increment/decrement reference count of tcltkip */
static int
rbtk_preserve_ip(ptr)
    struct tcltkip *ptr;
{
    ptr->ref_count++;
    if (ptr->ip == (Tcl_Interp*)NULL) {
        /* deleted IP */
        ptr->ref_count = 0;
    } else {
        Tcl_Preserve((ClientData)ptr->ip);
    }
    return(ptr->ref_count);
}

static int
rbtk_release_ip(ptr)
    struct tcltkip *ptr;
{
    ptr->ref_count--;
    if (ptr->ref_count < 0) {
        ptr->ref_count = 0;
    } else if (ptr->ip == (Tcl_Interp*)NULL) {
        /* deleted IP */
        ptr->ref_count = 0;
    } else {
        Tcl_Release((ClientData)ptr->ip);
    }
    return(ptr->ref_count);
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
    struct tcltkip *ptr = get_ip(interp);

    va_init_list(args,fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    buf[BUFSIZ - 1] = '\0';
    va_end(args);
    einfo = rb_exc_new2(exc, buf);
    rb_ivar_set(einfo, ID_at_interp, interp);
    if (ptr) {
        Tcl_ResetResult(ptr->ip);
    }

    return einfo;
}


/* stub status */
static void
tcl_stubs_check()
{
    if (!tcl_stubs_init_p()) {
        int st = ruby_tcl_stubs_init();
        switch(st) {
        case TCLTK_STUBS_OK:
            break;
        case NO_TCL_DLL:
            rb_raise(rb_eLoadError, "tcltklib: fail to open tcl_dll");
        case NO_FindExecutable:
            rb_raise(rb_eLoadError, "tcltklib: can't find Tcl_FindExecutable");
        case NO_CreateInterp:
            rb_raise(rb_eLoadError, "tcltklib: can't find Tcl_CreateInterp()");
        case NO_DeleteInterp:
            rb_raise(rb_eLoadError, "tcltklib: can't find Tcl_DeleteInterp()");
        case FAIL_CreateInterp:
            rb_raise(rb_eRuntimeError, "tcltklib: fail to create a new IP to call Tcl_InitStubs()");
        case FAIL_Tcl_InitStubs:
            rb_raise(rb_eRuntimeError, "tcltklib: fail to Tcl_InitStubs()");
        default:
            rb_raise(rb_eRuntimeError, "tcltklib: unknown error(%d) on ruby_tcl_stubs_init()", st);
        }
    }
}


static VALUE
tcltkip_init_tk(interp)
    VALUE interp;
{
    struct tcltkip *ptr = get_ip(interp);

#if TCL_MAJOR_VERSION >= 8
    int  st;

    if (Tcl_IsSafe(ptr->ip)) {
        DUMP1("Tk_SafeInit");
        st = ruby_tk_stubs_safeinit(ptr->ip);
        switch(st) {
        case TCLTK_STUBS_OK:
            break;
        case NO_Tk_Init:
            return rb_exc_new2(rb_eLoadError, 
                               "tcltklib: can't find Tk_SafeInit()");
        case FAIL_Tk_Init:
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "tcltklib: fail to Tk_SafeInit(). %s", 
                                 Tcl_GetStringResult(ptr->ip));
        case FAIL_Tk_InitStubs:
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "tcltklib: fail to Tk_InitStubs(). %s", 
                                 Tcl_GetStringResult(ptr->ip));
        default:
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "tcltklib: unknown error(%d) on ruby_tk_stubs_safeinit", st);
        }
    } else {
        DUMP1("Tk_Init");
        st = ruby_tk_stubs_init(ptr->ip);
        switch(st) {
        case TCLTK_STUBS_OK:
            break;
        case NO_Tk_Init:
            return rb_exc_new2(rb_eLoadError, 
                               "tcltklib: can't find Tk_Init()");
        case FAIL_Tk_Init:
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "tcltklib: fail to Tk_Init(). %s", 
                                 Tcl_GetStringResult(ptr->ip));
        case FAIL_Tk_InitStubs:
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "tcltklib: fail to Tk_InitStubs(). %s", 
                                 Tcl_GetStringResult(ptr->ip));
        default:
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "tcltklib: unknown error(%d) on ruby_tk_stubs_init", st);
        }
    }

#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tk_Init");
    if (ruby_tk_stubs_init(ptr->ip) != TCLTK_STUBS_OK) {
        return rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
    }
#endif

    return Qnil;
}


/* treat excetiopn on Tcl side */
static VALUE rbtk_pending_exception;
static int rbtk_eventloop_depth = 0;


static int
pending_exception_check0()
{
    volatile VALUE exc = rbtk_pending_exception;

    if (!NIL_P(exc) && rb_obj_is_kind_of(exc, rb_eException)) {
        DUMP1("find a pending exception");
        if (rbtk_eventloop_depth > 0) {
            return 1; /* pending */
        } else {
            rbtk_pending_exception = Qnil;

            if (rb_obj_is_kind_of(exc, eTkCallbackRetry)) {
                DUMP1("pending_exception_check0: call rb_jump_tag(retry)");
                rb_jump_tag(TAG_RETRY);
            } else if (rb_obj_is_kind_of(exc, eTkCallbackRedo)) {
                DUMP1("pending_exception_check0: call rb_jump_tag(redo)");
                rb_jump_tag(TAG_REDO);
            } else if (rb_obj_is_kind_of(exc, eTkCallbackThrow)) {
                DUMP1("pending_exception_check0: call rb_jump_tag(throw)");
                rb_jump_tag(TAG_THROW);
            }

            rb_exc_raise(exc);
        }
    } else {
        return 0;
    }
}

static int
pending_exception_check1(thr_crit_bup, ptr)
    int thr_crit_bup;
    struct tcltkip *ptr;
{
    volatile VALUE exc = rbtk_pending_exception;

    if (!NIL_P(exc) && rb_obj_is_kind_of(exc, rb_eException)) {
        DUMP1("find a pending exception");

        if (rbtk_eventloop_depth > 0) {
            return 1; /* pending */
        } else {
            rbtk_pending_exception = Qnil;

            if (ptr != (struct tcltkip *)NULL) {
                /* Tcl_Release(ptr->ip); */
                rbtk_release_ip(ptr);
            }

            rb_thread_critical = thr_crit_bup;

            if (rb_obj_is_kind_of(exc, eTkCallbackRetry)) {
                DUMP1("pending_exception_check1: call rb_jump_tag(retry)");
                rb_jump_tag(TAG_RETRY);
            } else if (rb_obj_is_kind_of(exc, eTkCallbackRedo)) {
                DUMP1("pending_exception_check1: call rb_jump_tag(redo)");
                rb_jump_tag(TAG_REDO);
            } else if (rb_obj_is_kind_of(exc, eTkCallbackThrow)) {
                DUMP1("pending_exception_check1: call rb_jump_tag(throw)");
                rb_jump_tag(TAG_THROW);
            }
            rb_exc_raise(exc);
        }
    } else {
        return 0;
    }
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
        /* argv[1] = Tcl_GetString(state_obj); */
        argv[1] = Tcl_GetStringFromObj(state_obj, (int*)NULL);
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

    DUMP1("call _timer_for_tcl");

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    Tcl_DeleteTimerHandler(timer_token);

    run_timer_flag = 1;

    if (timer_tick > 0) {
        timer_token = Tcl_CreateTimerHandler(timer_tick, _timer_for_tcl, 
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
    Tcl_DeleteTimerHandler(timer_token);

    timer_tick = req_timer_tick = ttick;
    if (timer_tick > 0) {
        /* start timer callback */
        timer_token = Tcl_CreateTimerHandler(timer_tick, _timer_for_tcl, 
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
    if (deleted_ip(ptr)) {
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
    if (deleted_ip(ptr)) {
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
    if (deleted_ip(ptr)) {
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
        {
	    VALUE tmp = rb_funcall(time, ID_inspect, 0, 0);
	    rb_raise(rb_eArgError, "invalid value for time: '%s'", 
		     StringValuePtr(tmp));
	}
    }

    Tcl_SetMaxBlockTime(&tcl_time);

    return Qnil;
}

static VALUE
lib_evloop_thread_p(self)
    VALUE self;
{
    if (NIL_P(eventloop_thread)) {
        return Qnil;    /* no eventloop */
    } else if (rb_thread_current() == eventloop_thread) {
        return Qtrue;   /* is eventloop */
    } else {
        return Qfalse;  /* not eventloop */
    }
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
    if (deleted_ip(ptr)) {
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
    if (tk_stubs_init_p()) {
        return INT2FIX(Tk_GetNumMainWindows());
    } else {
        return INT2FIX(0);
    }
}


static VALUE
call_DoOneEvent(flag_val)
    VALUE flag_val;
{
    int flag;

    flag = FIX2INT(flag_val);
    if (Tcl_DoOneEvent(flag)) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

static VALUE
eventloop_sleep(dummy)
    VALUE dummy;
{
    struct timeval t;

    t.tv_sec = (time_t)0;
    t.tv_usec = (time_t)(no_event_wait*1000.0);

#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on eventloop_sleep()");
    }
#endif

    rb_thread_wait_for(t);

#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on eventloop_sleep()");
    }
#endif

    return Qnil;
}


static int
lib_eventloop_core(check_root, update_flag, check_var, interp)
    int check_root;
    int update_flag;
    int *check_var;
    Tcl_Interp *interp;
{
    volatile VALUE current = eventloop_thread;
    int found_event = 1;
    int event_flag;
    struct timeval t;
    int thr_crit_bup;
    int status;
    int depth = rbtk_eventloop_depth;


    if (update_flag) DUMP1("update loop start!!");

    t.tv_sec = (time_t)0;
    t.tv_usec = (time_t)(no_event_wait*1000.0);

    Tcl_DeleteTimerHandler(timer_token);
    run_timer_flag = 0;
    if (timer_tick > 0) {
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;
        timer_token = Tcl_CreateTimerHandler(timer_tick, _timer_for_tcl, 
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
                timer_token = Tcl_CreateTimerHandler(timer_tick, 
                                                     _timer_for_tcl, 
                                                     (ClientData)0);
            }

            if (check_var != (int *)NULL) {
                if (*check_var || !found_event) {
                    return found_event;
                }
                if (interp != (Tcl_Interp*)NULL 
                    && Tcl_InterpDeleted(interp)) {
                    /* IP for check_var is deleted */
                    return 0;
                }
            }

            /* found_event = Tcl_DoOneEvent(event_flag); */
            found_event = RTEST(rb_protect(call_DoOneEvent, 
                                           INT2FIX(event_flag), &status)); 
            if (status) {
                switch (status) {
                case TAG_RAISE:
                    if (NIL_P(ruby_errinfo)) {
                        rbtk_pending_exception 
                            = rb_exc_new2(rb_eException, "unknown exception");
                    } else {
                        rbtk_pending_exception = ruby_errinfo;

                        if (!NIL_P(rbtk_pending_exception)) {
                            if (rbtk_eventloop_depth == 0) {
                                VALUE exc = rbtk_pending_exception;
                                rbtk_pending_exception = Qnil;
                                rb_exc_raise(exc);
                            } else {
                                return 0;
                            }
                        }
                    }
                    break;

                case TAG_FATAL:
                    if (NIL_P(ruby_errinfo)) {
                        rb_exc_raise(rb_exc_new2(rb_eFatal, "FATAL"));
                    } else {
                        rb_exc_raise(ruby_errinfo);
                    }
                }
            }

            if (depth != rbtk_eventloop_depth) {
                DUMP2("DoOneEvent(1) abnormal exit!! %d", 
                      rbtk_eventloop_depth);
            }

            if (check_var != (int*)NULL && !NIL_P(rbtk_pending_exception)) {
                DUMP1("exception on wait");
                return 0;
            }

            if (pending_exception_check0()) {
                /* pending -> upper level */
                return 0;
            }

            if (update_flag != 0) {
              if (found_event) {
                DUMP1("next update loop");
                continue;
              } else {
                DUMP1("update complete");
                return 0;
              }
            }

            DUMP1("trap check");
            if (rb_trap_pending) {
                run_timer_flag = 0;
                if (rb_prohibit_interrupt || check_var != (int*)NULL) {
                    /* pending or on wait command */
                    return 0;
                } else {
                    rb_trap_exec();
                }
            }

            DUMP1("check Root Widget");
            if (check_root && tk_stubs_init_p() && Tk_GetNumMainWindows() == 0) {
                run_timer_flag = 0;
                if (rb_trap_pending) {
                    if (rb_prohibit_interrupt || check_var != (int*)NULL) {
                        /* pending or on wait command */
                        return 0;
                    } else {
                        rb_trap_exec();
                    }
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
                    if (interp != (Tcl_Interp*)NULL 
                        && Tcl_InterpDeleted(interp)) {
                        /* IP for check_var is deleted */
                        return 0;
                    }
                }

                if (NIL_P(eventloop_thread) || current == eventloop_thread) {
                    int st;
                    int status;

                    /* st = Tcl_DoOneEvent(event_flag); */
                    st = RTEST(rb_protect(call_DoOneEvent, 
                                          INT2FIX(event_flag), &status)); 
                    if (status) {
                        switch (status) {
                        case TAG_RAISE:
                            if (NIL_P(ruby_errinfo)) {
                                rbtk_pending_exception 
                                    = rb_exc_new2(rb_eException, 
                                                  "unknown exception");
                            } else {
                                rbtk_pending_exception = ruby_errinfo;

                                if (!NIL_P(rbtk_pending_exception)) {
                                    if (rbtk_eventloop_depth == 0) {
                                        VALUE exc = rbtk_pending_exception;
                                        rbtk_pending_exception = Qnil;
                                        rb_exc_raise(exc);
                                    } else {
                                        return 0;
                                    }
                                }
                            }
                            break;

                        case TAG_FATAL:
                            if (NIL_P(ruby_errinfo)) {
                                rb_exc_raise(rb_exc_new2(rb_eFatal, "FATAL"));
                            } else {
                                rb_exc_raise(ruby_errinfo);
                            }
                        }
                    }

                    if (depth != rbtk_eventloop_depth) {
                        DUMP2("DoOneEvent(2) abnormal exit!! %d", 
                              rbtk_eventloop_depth);
                        return 0;
                    }

                    DUMP1("trap check");
                    if (rb_trap_pending) {
                        run_timer_flag = 0;
                        if (rb_prohibit_interrupt || check_var != (int*)NULL) {
                            /* pending or on wait command */
                            return 0;
                        } else {
                            rb_trap_exec();
                        }
                    }

                    if (check_var != (int*)NULL 
                        && !NIL_P(rbtk_pending_exception)) {
                        DUMP1("exception on wait");
                        return 0;
                    }

                    if (pending_exception_check0()) {
                        /* pending -> upper level */
                        return 0;
                    }

                    if (st) {
                        tick_counter++;
                    } else {
                        if (update_flag != 0) {
                            DUMP1("update complete");
                            return 0;
                        }

                        tick_counter += no_event_tick;

                        /* rb_thread_wait_for(t); */
                        rb_protect(eventloop_sleep, Qnil, &status);

                        if (status) {
                            switch (status) {
                            case TAG_RAISE:
                                if (NIL_P(ruby_errinfo)) {
                                    rbtk_pending_exception 
                                        = rb_exc_new2(rb_eException, 
                                                      "unknown exception");
                                } else {
                                    rbtk_pending_exception = ruby_errinfo;

                                    if (!NIL_P(rbtk_pending_exception)) {
                                        if (rbtk_eventloop_depth == 0) {
                                            VALUE exc = rbtk_pending_exception;
                                            rbtk_pending_exception = Qnil;
                                            rb_exc_raise(exc);
                                        } else {
                                            return 0;
                                        }
                                    }
                                }
                                break;

                            case TAG_FATAL:
                                if (NIL_P(ruby_errinfo)) {
                                    rb_exc_raise(rb_exc_new2(rb_eFatal, 
                                                             "FATAL"));
                                } else {
                                    rb_exc_raise(ruby_errinfo);
                                }
                            }
                        }
                    }

                } else {
                    DUMP2("sleep eventloop %lx", current);
                    DUMP2("eventloop thread is %lx", eventloop_thread);
                    rb_thread_stop();
                }

                if (!NIL_P(watchdog_thread) && eventloop_thread != current) {
                    return 1;
                }

                DUMP1("trap check");
                if (rb_trap_pending) {
                    run_timer_flag = 0;
                    if (rb_prohibit_interrupt || check_var != (int*)NULL) {
                        /* pending or on wait command */
                        return 0;
                    } else {
                        rb_trap_exec();
                    }
                }

                DUMP1("check Root Widget");
                if (check_root && tk_stubs_init_p() && Tk_GetNumMainWindows() == 0) {
                    run_timer_flag = 0;
                    if (rb_trap_pending) {
                        if (rb_prohibit_interrupt || check_var != (int*)NULL) {
                            /* pending or on wait command */
                            return 0;
                        } else {
                            rb_trap_exec();
                        }
                    }
                    return 1;
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


struct evloop_params {
    int check_root;
    int update_flag;
    int *check_var;
    Tcl_Interp *interp;
    int thr_crit_bup;
};

VALUE
lib_eventloop_main_core(args)
    VALUE args;
{
    struct evloop_params *params = (struct evloop_params *)args;

    check_rootwidget_flag = params->check_root;

    if (lib_eventloop_core(params->check_root, 
                           params->update_flag, 
                           params->check_var, 
                           params->interp)) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

VALUE
lib_eventloop_main(args)
    VALUE args;
{
    return lib_eventloop_main_core(args);

#if 0
    volatile VALUE ret;
    int status = 0;

    ret = rb_protect(lib_eventloop_main_core, args, &status);

    switch (status) {
    case TAG_RAISE:
        if (NIL_P(ruby_errinfo)) {
            rbtk_pending_exception 
                = rb_exc_new2(rb_eException, "unknown exception");
        } else {
            rbtk_pending_exception = ruby_errinfo;
        }
        return Qnil;

    case TAG_FATAL:
        if (NIL_P(ruby_errinfo)) {
            rbtk_pending_exception = rb_exc_new2(rb_eFatal, "FATAL");
        } else {
            rbtk_pending_exception = ruby_errinfo;
        }
        return Qnil;
    }

    return ret;
#endif
}

VALUE
lib_eventloop_ensure(args)
    VALUE args;
{
    struct evloop_params *ptr = (struct evloop_params *)args;
    volatile VALUE current_evloop = rb_thread_current();

    DUMP2("eventloop_ensure: current-thread : %lx", current_evloop);
    DUMP2("eventloop_ensure: eventloop-thread : %lx", eventloop_thread);
    if (eventloop_thread != current_evloop) {
        DUMP2("finish eventloop %lx (NOT current eventloop)", current_evloop);

	rb_thread_critical = ptr->thr_crit_bup;

        free(ptr);

        return Qnil;
    }

    while((eventloop_thread = rb_ary_pop(eventloop_stack))) {
        DUMP2("eventloop-ensure: new eventloop-thread -> %lx", 
              eventloop_thread);

        if (eventloop_thread == current_evloop) {
            rbtk_eventloop_depth--;
            DUMP2("eventloop %lx : back from recursive call", current_evloop);
            break;
        }

        if (NIL_P(eventloop_thread)) {
          Tcl_DeleteTimerHandler(timer_token);
          timer_token = (Tcl_TimerToken)NULL;

          break; 
        }

        if (RTEST(rb_funcall(eventloop_thread, ID_alive_p, 0, 0))) {
            DUMP2("eventloop-enshure: wake up parent %lx", eventloop_thread);
            rb_thread_wakeup(eventloop_thread);

            break;
        }
    }

    rb_thread_critical = ptr->thr_crit_bup;

    free(ptr);

    DUMP2("finish current eventloop %lx", current_evloop);
    return Qnil;
}

static VALUE
lib_eventloop_launcher(check_root, update_flag, check_var, interp)
    int check_root;
    int update_flag;
    int *check_var;
    Tcl_Interp *interp;
{
    volatile VALUE parent_evloop = eventloop_thread;
    struct evloop_params *args = ALLOC(struct evloop_params);

    tcl_stubs_check();

    eventloop_thread = rb_thread_current();

    if (parent_evloop == eventloop_thread) {
        DUMP2("eventloop: recursive call on %lx", parent_evloop);
        rbtk_eventloop_depth++;
    }

    if (!NIL_P(parent_evloop) && parent_evloop != eventloop_thread) {
        DUMP2("wait for stop of parent_evloop %lx", parent_evloop);
        while(!RTEST(rb_funcall(parent_evloop, ID_stop_p, 0))) {
            DUMP2("parent_evloop %lx doesn't stop", parent_evloop);
            rb_thread_run(parent_evloop);
        }
        DUMP1("succeed to stop parent");
    }

    rb_ary_push(eventloop_stack, parent_evloop);

    DUMP3("tcltklib: eventloop-thread : %lx -> %lx\n", 
                parent_evloop, eventloop_thread);

    args->check_root   = check_root;
    args->update_flag  = update_flag;
    args->check_var    = check_var;
    args->interp       = interp;
    args->thr_crit_bup = rb_thread_critical;

    rb_thread_critical = Qfalse;

#if 0
    return rb_ensure(lib_eventloop_main, (VALUE)args, 
                     lib_eventloop_ensure, (VALUE)args);
#endif
    return rb_ensure(lib_eventloop_main_core, (VALUE)args, 
                     lib_eventloop_ensure, (VALUE)args);
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

    return lib_eventloop_launcher(RTEST(check_rootwidget), 0, 
                                  (int*)NULL, (Tcl_Interp*)NULL);
}

static VALUE
ip_mainloop(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        return Qnil;
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return Qnil;
    }
    return lib_mainloop(argc, argv, self);
}


static VALUE
watchdog_evloop_launcher(check_rootwidget)
    VALUE check_rootwidget;
{
    return lib_eventloop_launcher(RTEST(check_rootwidget), 0, 
                                  (int*)NULL, (Tcl_Interp*)NULL);
}

#define EVLOOP_WAKEUP_CHANCE 3

static VALUE
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
    if (!NIL_P(watchdog_thread)) {
        if (RTEST(rb_funcall(watchdog_thread, ID_stop_p, 0))) {
            rb_funcall(watchdog_thread, ID_kill, 0);
        } else {
            return Qnil;
        }
    }
    watchdog_thread = rb_thread_current();

    /* watchdog start */
    do {
        if (NIL_P(eventloop_thread)
            || (loop_counter == prev_val && chance >= EVLOOP_WAKEUP_CHANCE)) {
            /* start new eventloop thread */
            DUMP2("eventloop thread %lx is sleeping or dead", 
                  eventloop_thread);
            evloop = rb_thread_create(watchdog_evloop_launcher, 
                                      (void*)&check_rootwidget);
            DUMP2("create new eventloop thread %lx", evloop);
            loop_counter = -1;
            chance = 0;
            rb_thread_run(evloop);
        } else {
            prev_val = loop_counter;
            if (RTEST(rb_funcall(eventloop_thread, ID_stop_p, 0))) {
                ++chance;
            } else {
                chance = 0;
            }
            if (event_loop_wait_event) {
                rb_thread_wait_for(t0);
            } else {
                rb_thread_wait_for(t1);
            }
            /* rb_thread_schedule(); */
        }
    } while(!check || !tk_stubs_init_p() || Tk_GetNumMainWindows() != 0);

    return Qnil;
}

VALUE
lib_watchdog_ensure(arg)
    VALUE arg;
{
    eventloop_thread = Qnil; /* stop eventloops */
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
    if (deleted_ip(ptr)) {
        return Qnil;
    }

    if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
        /* slave IP */
        return Qnil;
    }
    return lib_mainloop_watchdog(argc, argv, self);
}


/* thread-safe(?) interaction between Ruby and Tk */
struct thread_call_proc_arg {
    VALUE proc;
    int *done;
};

void 
_thread_call_proc_arg_mark(struct thread_call_proc_arg *q)
{
    rb_gc_mark(q->proc);
}

static VALUE
_thread_call_proc_core(arg)
    VALUE arg;
{
    struct thread_call_proc_arg *q = (struct thread_call_proc_arg*)arg;
    return rb_funcall(q->proc, ID_call, 0);
}

static VALUE
_thread_call_proc_ensure(arg)
    VALUE arg;
{
    struct thread_call_proc_arg *q = (struct thread_call_proc_arg*)arg;
    *(q->done) = 1;
    return Qnil;
}

static VALUE
_thread_call_proc(arg)
    VALUE arg;
{
    struct thread_call_proc_arg *q = (struct thread_call_proc_arg*)arg;

    return rb_ensure(_thread_call_proc_core, (VALUE)q, 
                     _thread_call_proc_ensure, (VALUE)q);
}

static VALUE
_thread_call_proc_value(th)
    VALUE th;
{
    return rb_funcall(th, ID_value, 0);
}

static VALUE
lib_thread_callback(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    struct thread_call_proc_arg *q;
    VALUE proc, th, ret;
    int status, foundEvent;

    if (rb_scan_args(argc, argv, "01", &proc) == 0) {
        proc = rb_block_proc();
    }

    q = (struct thread_call_proc_arg *)ALLOC(struct thread_call_proc_arg);
    q->proc = proc;
    q->done = (int*)ALLOC(int);
    *(q->done) = 0;

    /* create call-proc thread */
    th = rb_thread_create(_thread_call_proc, (void*)q);

    rb_thread_schedule();

    /* start sub-eventloop */
    foundEvent = RTEST(lib_eventloop_launcher(/* not check root-widget */0, 0, 
                                              q->done, (Tcl_Interp*)NULL));

    if (RTEST(rb_funcall(th, ID_alive_p, 0))) {
        rb_funcall(th, ID_kill, 0);
        ret = Qnil;
    } else {
        ret = rb_protect(_thread_call_proc_value, th, &status);
    }

    free(q->done);
    free(q);

    if (NIL_P(rbtk_pending_exception)) {
        /* return ruby_errinfo; */
        if (status) {
            rb_exc_raise(ruby_errinfo);
        }
    } else {
        VALUE exc = rbtk_pending_exception;
        rbtk_pending_exception = Qnil;
        /* return exc; */
        rb_exc_raise(exc);
    }

    return ret;
}


/* do_one_event */
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

    if (!NIL_P(eventloop_thread)) {
        rb_raise(rb_eRuntimeError, "eventloop is already running");
    }

    tcl_stubs_check();

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
        if (deleted_ip(ptr)) {
            return Qfalse;
        }

        if (Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL) {
            /* slave IP */
            flags |= TCL_DONT_WAIT;
        }
    }

    /* found_event = Tcl_DoOneEvent(TCL_ALL_EVENTS | TCL_DONT_WAIT); */
    found_event = Tcl_DoOneEvent(flags);

    if (pending_exception_check0()) {
        return Qfalse;
    }

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
    StringValue(msg);

#if TCL_MAJOR_VERSION > 8 || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION > 0)
    enc = rb_attr_get(exc, ID_at_enc);
    if (NIL_P(enc)) {
        enc = rb_attr_get(msg, ID_at_enc);
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
    memcpy(buf, RSTRING(msg)->ptr, RSTRING(msg)->len);
    buf[RSTRING(msg)->len] = 0;

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    Tcl_ExternalToUtfDString(encoding, buf, RSTRING(msg)->len, &dstr);

    Tcl_AppendResult(interp, Tcl_DStringValue(&dstr), (char*)NULL);
    DUMP2("error message:%s", Tcl_DStringValue(&dstr));
    Tcl_DStringFree(&dstr);
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

static int
tcl_protect_core(interp, proc, data) /* should not raise exception */
    Tcl_Interp *interp;
    VALUE (*proc)();
    VALUE data;
{
    volatile VALUE ret, exc = Qnil;
    int status = 0;
    int thr_crit_bup = rb_thread_critical;

    rb_thread_critical = Qfalse;
    ret = rb_protect(proc, data, &status);
    rb_thread_critical = Qtrue;
    if (status) {
        char *buf;
        VALUE old_gc, type, str;

        old_gc = rb_gc_disable();

        switch(status) {
        case TAG_RETURN:
            type = eTkCallbackReturn;
            goto error;
        case TAG_BREAK:
            type = eTkCallbackBreak;
            goto error;
        case TAG_NEXT:
            type = eTkCallbackContinue;
            goto error;
        error:
            str = rb_str_new2("LocalJumpError: ");
            rb_str_append(str, rb_obj_as_string(ruby_errinfo));
            exc = rb_exc_new3(type, str);
            break;

        case TAG_RETRY:
            if (NIL_P(ruby_errinfo)) {
                DUMP1("rb_protect: retry");
                exc = rb_exc_new2(eTkCallbackRetry, "retry jump error");
            } else {
                exc = ruby_errinfo;
            }
            break;

        case TAG_REDO:
            if (NIL_P(ruby_errinfo)) {
                DUMP1("rb_protect: redo");
                exc = rb_exc_new2(eTkCallbackRedo,  "redo jump error");
            } else {
                exc = ruby_errinfo;
            }
            break;

        case TAG_RAISE:
            if (NIL_P(ruby_errinfo)) {
                exc = rb_exc_new2(rb_eException, "unknown exception");
            } else {
                exc = ruby_errinfo;
            }
            break;

        case TAG_FATAL:
            if (NIL_P(ruby_errinfo)) {
                exc = rb_exc_new2(rb_eFatal, "FATAL");
            } else {
                exc = ruby_errinfo;
            }
            break;

        case TAG_THROW:
            if (NIL_P(ruby_errinfo)) {
                DUMP1("rb_protect: throw");
                exc = rb_exc_new2(eTkCallbackThrow,  "throw jump error");
            } else {
                exc = ruby_errinfo;
            }
            break;

        default:
            buf = ALLOC_N(char, 256);
            sprintf(buf, "unknown loncaljmp status %d", status);
            exc = rb_exc_new2(rb_eException, buf);
            free(buf);
            break;
        }

        if (old_gc == Qfalse) rb_gc_enable();

        ret = Qnil;
    }

    rb_thread_critical = thr_crit_bup;

    Tcl_ResetResult(interp);

    /* status check */
    if (!NIL_P(exc)) {
        volatile VALUE eclass = rb_obj_class(exc);
        volatile VALUE backtrace;

        DUMP1("(failed)");

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        DUMP1("set backtrace");
        if (!NIL_P(backtrace = rb_funcall(exc, ID_backtrace, 0, 0))) {
            backtrace = rb_ary_join(backtrace, rb_str_new2("\n"));
            Tcl_AddErrorInfo(interp, StringValuePtr(backtrace));
        }

        rb_thread_critical = thr_crit_bup;

        ip_set_exc_message(interp, exc);

        if (eclass == eTkCallbackReturn)
            return TCL_RETURN;

        if (eclass == eTkCallbackBreak)
            return TCL_BREAK;

        if (eclass == eTkCallbackContinue)
            return TCL_CONTINUE;

        if (eclass == rb_eSystemExit || eclass == rb_eInterrupt) {
            rbtk_pending_exception = exc;
            return TCL_RETURN;
        }

        if (rb_obj_is_kind_of(exc, eTkLocalJumpError)) {
            rbtk_pending_exception = exc;
            return TCL_ERROR;
        }

        if (rb_obj_is_kind_of(exc, eLocalJumpError)) {
            VALUE reason = rb_ivar_get(exc, ID_at_reason);

            if (TYPE(reason) == T_SYMBOL) {
                if (SYM2ID(reason) == ID_return)
                    return TCL_RETURN;

                if (SYM2ID(reason) == ID_break)
                    return TCL_BREAK;

                if (SYM2ID(reason) == ID_next)
                    return TCL_CONTINUE;
            }
        }

        return TCL_ERROR;
    }

    /* result must be string or nil */
    if (!NIL_P(ret)) {
        /* copy result to the tcl interpreter */
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        ret = TkStringValue(ret);
        DUMP1("Tcl_AppendResult");
        Tcl_AppendResult(interp, RSTRING(ret)->ptr, (char *)NULL);

        rb_thread_critical = thr_crit_bup;
    }

    DUMP2("(result) %s", NIL_P(ret) ? "nil" : RSTRING(ret)->ptr);

    return TCL_OK;
}

static int
tcl_protect(interp, proc, data)
    Tcl_Interp *interp;
    VALUE (*proc)();
    VALUE data;
{
    int old_trapflag = rb_trap_immediate;
    int code;

#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on tcl_protect()");
    }
#endif

    rb_trap_immediate = 0;
    code = tcl_protect_core(interp, proc, data);
    rb_trap_immediate = old_trapflag;

    return code;
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
    char *arg;
    int thr_crit_bup;
    int code;

    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }

    /* ruby command has 1 arg. */
    if (argc != 2) {
#if 0
        rb_raise(rb_eArgError, 
                 "wrong number of arguments (%d for 1)", argc - 1);
#else
        char buf[sizeof(int)*8 + 1];
        Tcl_ResetResult(interp);
        sprintf(buf, "%d", argc-1);
        Tcl_AppendResult(interp, "wrong number of arguments (", 
                         buf, " for 1)", (char *)NULL);
        rbtk_pending_exception = rb_exc_new2(rb_eArgError, 
                                             Tcl_GetStringResult(interp));
        return TCL_ERROR;
#endif
    }

    /* get C string from Tcl object */
#if TCL_MAJOR_VERSION >= 8
    {
      char *str;
      int  len;

      thr_crit_bup = rb_thread_critical;
      rb_thread_critical = Qtrue;

      str = Tcl_GetStringFromObj(argv[1], &len);
      arg = ALLOC_N(char, len + 1);
      memcpy(arg, str, len);
      arg[len] = 0;

      rb_thread_critical = thr_crit_bup;

    }
#else /* TCL_MAJOR_VERSION < 8 */
    arg = argv[1];
#endif

    /* evaluate the argument string by ruby */
    DUMP2("rb_eval_string(%s)", arg);

    code = tcl_protect(interp, rb_eval_string, (VALUE)arg);

#if TCL_MAJOR_VERSION >= 8
    free(arg);
#endif

    return code;
}


/* Tcl command `ruby_cmd' */
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
    volatile VALUE receiver;
    volatile ID method;
    volatile VALUE args;
    char *str;
    int i;
    int  len;
    struct cmd_body_arg *arg;
    int thr_crit_bup;
    VALUE old_gc;
    int code;

    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }

    if (argc < 3) {
#if 0
        rb_raise(rb_eArgError, "too few arguments");
#else
        Tcl_ResetResult(interp);
        Tcl_AppendResult(interp, "too few arguments", (char *)NULL);
        rbtk_pending_exception = rb_exc_new2(rb_eArgError, 
                                             Tcl_GetStringResult(interp));
        return TCL_ERROR;
#endif
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
        memcpy(buf + 1, str, len);
        buf[len + 1] = 0;
        receiver = rb_gv_get(buf);
        free(buf);
    }
    if (NIL_P(receiver)) {
#if 0
        rb_raise(rb_eArgError, 
                 "unknown class/module/global-variable '%s'", str);
#else
        Tcl_ResetResult(interp);
        Tcl_AppendResult(interp, "unknown class/module/global-variable '", 
                         str, "'", (char *)NULL);
        rbtk_pending_exception = rb_exc_new2(rb_eArgError, 
                                             Tcl_GetStringResult(interp));
        return TCL_ERROR;
#endif
    }

    /* get metrhod */
#if TCL_MAJOR_VERSION >= 8
    str = Tcl_GetStringFromObj(argv[2], &len);
#else /* TCL_MAJOR_VERSION < 8 */
    str = argv[2];
#endif
    method = rb_intern(str);

    /* get args */
    args = rb_ary_new2(argc - 2);
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

    arg->receiver = receiver;
    arg->method = method;
    arg->args = args;

    /* evaluate the argument string by ruby */
    code = tcl_protect(interp, ip_ruby_cmd_core, (VALUE)arg);

    free(arg);

    return code;
}


/*****************************/
/* relpace of 'exit' command */
/*****************************/
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
    DUMP1("start ip_InterpExitCommand");
    if (interp != (Tcl_Interp*)NULL 
        && !Tcl_InterpDeleted(interp)
#if TCL_NAMESPACE_DEBUG
        && !ip_null_namespace(interp)
#endif
        ) {
        Tcl_ResetResult(interp);
        /* Tcl_Preserve(interp); */
        /* Tcl_Eval(interp, "interp eval {} {destroy .}; interp delete {}"); */
        ip_finalize(interp);
        Tcl_DeleteInterp(interp);
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
#if TCL_MAJOR_VERSION < 8
    char *endptr;
    cmd = argv[0];
#endif

    DUMP1("start ip_RubyExitCommand");

#if TCL_MAJOR_VERSION >= 8
    /* cmd = Tcl_GetString(argv[0]); */
    cmd = Tcl_GetStringFromObj(argv[0], (int*)NULL);
#endif

    if (argc < 1 || argc > 2) {
        /* arguemnt error */
        Tcl_AppendResult(interp, 
                         "wrong number of arguments: should be \"", 
                         cmd, " ?returnCode?\"", (char *)NULL);
        return TCL_ERROR;
    }

    if (interp == (Tcl_Interp*)NULL) return TCL_OK;

    Tcl_ResetResult(interp);

    if (rb_safe_level() >= 4 || Tcl_IsSafe(interp)) {
        ip_finalize(interp);
        Tcl_DeleteInterp(interp);
        Tcl_Release(interp);
        return TCL_OK;
    }

    switch(argc) {
    case 1:
        /* rb_exit(0); */ /* not return if succeed */
        Tcl_AppendResult(interp, 
                         "fail to call \"", cmd, "\"", (char *)NULL);

        rbtk_pending_exception = rb_exc_new2(rb_eSystemExit, 
                                             Tcl_GetStringResult(interp));
        rb_iv_set(rbtk_pending_exception, "status", INT2FIX(0));

        return TCL_RETURN;

    case 2:
#if TCL_MAJOR_VERSION >= 8
        if (Tcl_GetIntFromObj(interp, argv[1], &state) == TCL_ERROR) {
            return TCL_ERROR;
        }
        /* param = Tcl_GetString(argv[1]); */
        param = Tcl_GetStringFromObj(argv[1], (int*)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
        state = (int)strtol(argv[1], &endptr, 0);
        if (*endptr) {
            Tcl_AppendResult(interp, 
                             "expected integer but got \"", 
                             argv[1], "\"", (char *)NULL);
            return TCL_ERROR;
        }
        param = argv[1];
#endif
        /* rb_exit(state); */ /* not return if succeed */

        Tcl_AppendResult(interp, "fail to call \"", cmd, " ", 
                         param, "\"", (char *)NULL);

        rbtk_pending_exception = rb_exc_new2(rb_eSystemExit, 
                                             Tcl_GetStringResult(interp));
        rb_iv_set(rbtk_pending_exception, "status", INT2FIX(state));

        return TCL_RETURN;

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
    int  ret;
    int  flags = 0;
    static CONST char *updateOptions[] = {"idletasks", (char *) NULL};
    enum updateOptions {REGEXP_IDLETASKS};

    DUMP1("Ruby's 'update' is called");
    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }
#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on ip_ruby_eval()");
    }
#endif

    if (objc == 1) {
        flags = TCL_DONT_WAIT;

    } else if (objc == 2) {
#if TCL_MAJOR_VERSION >= 8
        if (Tcl_GetIndexFromObj(interp, objv[1], (CONST84 char **)updateOptions,
                "option", 0, &optionIndex) != TCL_OK) {
            return TCL_ERROR;
        }
        switch ((enum updateOptions) optionIndex) {
            case REGEXP_IDLETASKS: {
                flags = TCL_IDLE_EVENTS;
                break;
            }
            default: {
                rb_bug("ip_rbUpdateObjCmd: bad option index to UpdateOptions");
            }
        }
#else
        if (strncmp(objv[1], "idletasks", strlen(objv[1])) != 0) {
            Tcl_AppendResult(interp, "bad option \"", objv[1],
                    "\": must be idletasks", (char *) NULL);
            return TCL_ERROR;
        }
        flags = TCL_IDLE_EVENTS;
#endif
    } else {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "[ idletasks ]");
#else
# if TCL_MAJOR_VERSION >= 8
        int  dummy;
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

    Tcl_Preserve(interp);

    /* call eventloop */
    /* ret = lib_eventloop_core(0, flags, (int *)NULL);*/ /* ignore result */
    ret = RTEST(lib_eventloop_launcher(0, flags, (int *)NULL, interp)); /* ignore result */

    /* exception check */
    if (!NIL_P(rbtk_pending_exception)) {
        Tcl_Release(interp);

        /*
        if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)) {
        */
        if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)
            || rb_obj_is_kind_of(rbtk_pending_exception, rb_eInterrupt)) {
            return TCL_RETURN;
        } else{
            return TCL_ERROR;
        }
    }

    /* trap check */
    if (rb_trap_pending) {
        Tcl_Release(interp);

        return TCL_RETURN;
    }

    /*
     * Must clear the interpreter's result because event handlers could
     * have executed commands.
     */

    DUMP2("last result '%s'", Tcl_GetStringResult(interp));
    Tcl_ResetResult(interp);
    Tcl_Release(interp);

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
    int  flags = 0;
    struct th_update_param *param;
    static CONST char *updateOptions[] = {"idletasks", (char *) NULL};
    enum updateOptions {REGEXP_IDLETASKS};
    volatile VALUE current_thread = rb_thread_current();

    DUMP1("Ruby's 'thread_update' is called");
    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }
#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on ip_ruby_eval()");
    }
#endif

    if (rb_thread_alone() 
        || NIL_P(eventloop_thread) || eventloop_thread == current_thread) {
#if TCL_MAJOR_VERSION >= 8
        DUMP1("call ip_rbUpdateObjCmd");
        return ip_rbUpdateObjCmd(clientData, interp, objc, objv);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP1("call ip_rbUpdateCommand");
        return ip_rbUpdateCommand(clientData, interp, objc, objv);
#endif
    }

    DUMP1("start Ruby's 'thread_update' body");

    if (objc == 1) {
        flags = TCL_DONT_WAIT;

    } else if (objc == 2) {
#if TCL_MAJOR_VERSION >= 8
        if (Tcl_GetIndexFromObj(interp, objv[1], (CONST84 char **)updateOptions,
                "option", 0, &optionIndex) != TCL_OK) {
            return TCL_ERROR;
        }
        switch ((enum updateOptions) optionIndex) {
            case REGEXP_IDLETASKS: {
                flags = TCL_IDLE_EVENTS;
                break;
            }
            default: {
                rb_bug("ip_rb_threadUpdateObjCmd: bad option index to UpdateOptions");
            }
        }
#else
        if (strncmp(objv[1], "idletasks", strlen(objv[1])) != 0) {
            Tcl_AppendResult(interp, "bad option \"", objv[1],
                    "\": must be idletasks", (char *) NULL);
            return TCL_ERROR;
        }
        flags = TCL_IDLE_EVENTS;
#endif
    } else {
#ifdef Tcl_WrongNumArgs
        Tcl_WrongNumArgs(interp, 1, objv, "[ idletasks ]");
#else
# if TCL_MAJOR_VERSION >= 8
        int  dummy;
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


/***************************/
/* replace of vwait/tkwait */
/***************************/
#if TCL_MAJOR_VERSION >= 8
static int ip_rbVwaitObjCmd _((ClientData, Tcl_Interp *, int,
                               Tcl_Obj *CONST []));
static int ip_rb_threadVwaitObjCmd _((ClientData, Tcl_Interp *, int,
                                      Tcl_Obj *CONST []));
static int ip_rbTkWaitObjCmd _((ClientData, Tcl_Interp *, int,
                                Tcl_Obj *CONST []));
static int ip_rb_threadTkWaitObjCmd _((ClientData, Tcl_Interp *, int,
                                       Tcl_Obj *CONST []));
#else
static int ip_rbVwaitCommand _((ClientData, Tcl_Interp *, int, char *[]));
static int ip_rb_threadVwaitCommand _((ClientData, Tcl_Interp *, int,
                                       char *[]));
static int ip_rbTkWaitCommand _((ClientData, Tcl_Interp *, int, char *[]));
static int ip_rb_threadTkWaitCommand _((ClientData, Tcl_Interp *, int,
                                        char *[]));
#endif

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
static int
ip_rbVwaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
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
    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }

#if 0
    if (!rb_thread_alone() 
	&& eventloop_thread != Qnil
	&& eventloop_thread != rb_thread_current()) {
#if TCL_MAJOR_VERSION >= 8
        DUMP1("call ip_rb_threadVwaitObjCmd");
        return ip_rb_threadVwaitObjCmd(clientData, interp, objc, objv);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP1("call ip_rb_threadVwaitCommand");
        return ip_rb_threadVwaitCommand(clientData, interp, objc, objv);
#endif
    }
#endif

    Tcl_Preserve(interp);
#ifdef HAVE_NATIVETHREAD
    if (!is_ruby_native_thread()) {
        rb_bug("cross-thread violation on ip_ruby_eval()");
    }
#endif

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

    foundEvent = RTEST(lib_eventloop_launcher(/* not check root-widget */0, 
                                              0, &done, interp));

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    Tcl_UntraceVar(interp, nameString,
                   TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                   VwaitVarProc, (ClientData) &done);

    rb_thread_critical = thr_crit_bup;

    /* exception check */
    if (!NIL_P(rbtk_pending_exception)) {
#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[1]);
#endif
        Tcl_Release(interp);

/*
        if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)) {
*/
        if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)
            || rb_obj_is_kind_of(rbtk_pending_exception, rb_eInterrupt)) {
            return TCL_RETURN;
        } else{
            return TCL_ERROR;
        }
    }

    /* trap check */
    if (rb_trap_pending) {
#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[1]);
#endif
        Tcl_Release(interp);

        return TCL_RETURN;
    }

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
static int
ip_rbTkWaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
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
    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }

#if 0
    if (!rb_thread_alone() 
	&& eventloop_thread != Qnil
	&& eventloop_thread != rb_thread_current()) {
#if TCL_MAJOR_VERSION >= 8
        DUMP1("call ip_rb_threadTkWaitObjCmd");
        return ip_rb_threadTkWaitObjCmd(clientData, interp, objc, objv);
#else /* TCL_MAJOR_VERSION < 8 */
        DUMP1("call ip_rb_threadTkWaitCommand");
        return ip_rb_threadTkWwaitCommand(clientData, interp, objc, objv);
#endif
    }
#endif

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
        /* lib_eventloop_core(check_rootwidget_flag, 0, &done); */
        lib_eventloop_launcher(check_rootwidget_flag, 0, &done, interp);

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        Tcl_UntraceVar(interp, nameString,
                       TCL_GLOBAL_ONLY|TCL_TRACE_WRITES|TCL_TRACE_UNSETS,
                       WaitVariableProc, (ClientData) &done);

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        rb_thread_critical = thr_crit_bup;

        /* exception check */
        if (!NIL_P(rbtk_pending_exception)) {
            Tcl_Release(interp);

            /*
            if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)) {
            */
            if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)
                || rb_obj_is_kind_of(rbtk_pending_exception, rb_eInterrupt)) {
                return TCL_RETURN;
            } else{
                return TCL_ERROR;
            }
        }

        /* trap check */
        if (rb_trap_pending) {
            Tcl_Release(interp);

            return TCL_RETURN;
        }

        break;

    case TKWAIT_VISIBILITY:
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        if (!tk_stubs_init_p() || Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

        if (window == NULL) {
            Tcl_AppendResult(interp, "tkwait: ", 
                             "no main-window (not Tk application?)", 
                             (char*)NULL);
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
        /* lib_eventloop_core(check_rootwidget_flag, 0, &done); */
        lib_eventloop_launcher(check_rootwidget_flag, 0, &done, interp);

        /* exception check */
        if (!NIL_P(rbtk_pending_exception)) {
#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif
            Tcl_Release(interp);

            /*
            if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)) {
            */
            if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)
                || rb_obj_is_kind_of(rbtk_pending_exception, rb_eInterrupt)) {
                return TCL_RETURN;
            } else{
                return TCL_ERROR;
            }
        }

        /* trap check */
        if (rb_trap_pending) {
#if TCL_MAJOR_VERSION >= 8
            Tcl_DecrRefCount(objv[2]);
#endif
            Tcl_Release(interp);

            return TCL_RETURN;
        }

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
            
        if (!tk_stubs_init_p() || Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        if (window == NULL) {
            Tcl_AppendResult(interp, "tkwait: ", 
                             "no main-window (not Tk application?)", 
                             (char*)NULL);
            rb_thread_critical = thr_crit_bup;
            Tcl_Release(interp);
            return TCL_ERROR;
        }

        Tk_CreateEventHandler(window, StructureNotifyMask,
                              WaitWindowProc, (ClientData) &done);

        rb_thread_critical = thr_crit_bup;

        done = 0;
        /* lib_eventloop_core(check_rootwidget_flag, 0, &done); */
        lib_eventloop_launcher(check_rootwidget_flag, 0, &done, interp);

        /* exception check */
        if (!NIL_P(rbtk_pending_exception)) {
            Tcl_Release(interp);

            /*
            if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)) {
            */
            if (rb_obj_is_kind_of(rbtk_pending_exception, rb_eSystemExit)
                || rb_obj_is_kind_of(rbtk_pending_exception, rb_eInterrupt)) {
                return TCL_RETURN;
            } else{
                return TCL_ERROR;
            }
        }

        /* trap check */
        if (rb_trap_pending) {
            Tcl_Release(interp);

            return TCL_RETURN;
        }

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
static int
ip_rb_threadVwaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
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
    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }

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
        Tcl_Release(param);
        Tcl_Free((char *)param);

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
static int
ip_rb_threadTkWaitObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
#else /* TCL_MAJOR_VERSION < 8 */
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
    if (interp == (Tcl_Interp*)NULL) {
        rbtk_pending_exception = rb_exc_new2(rb_eRuntimeError, 
                                             "IP is deleted");
        return TCL_ERROR;
    }

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

        if (!tk_stubs_init_p() || Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

        if (window == NULL) {
            Tcl_AppendResult(interp, "thread_tkwait: ", 
                             "no main-window (not Tk application?)", 
                             (char*)NULL);

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

        if (!tk_stubs_init_p() || Tk_MainWindow(interp) == (Tk_Window)NULL) {
            window = NULL;
        } else {
            window = Tk_NameToWindow(interp, nameString, tkwin);
        }

#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[2]);
#endif

        if (window == NULL) {
            Tcl_AppendResult(interp, "thread_tkwait: ", 
                             "no main-window (not Tk application?)", 
                             (char*)NULL);

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


/* delete slave interpreters */
#if TCL_MAJOR_VERSION >= 8
static void
delete_slaves(ip)
    Tcl_Interp *ip;
{
    int  thr_crit_bup;
    Tcl_Interp *slave;
    Tcl_Obj *slave_list, *elem;
    char *slave_name;
    int i, len;

    DUMP1("delete slaves");
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (!Tcl_InterpDeleted(ip) && Tcl_Eval(ip, "interp slaves") == TCL_OK) {
        slave_list = Tcl_GetObjResult(ip);
        Tcl_IncrRefCount(slave_list);

        if (Tcl_ListObjLength((Tcl_Interp*)NULL, slave_list, &len) == TCL_OK) {
            for(i = 0; i < len; i++) {
                Tcl_ListObjIndex((Tcl_Interp*)NULL, slave_list, i, &elem);

                if (elem == (Tcl_Obj*)NULL) continue;

                Tcl_IncrRefCount(elem);

                /* get slave */
                /* slave_name = Tcl_GetString(elem); */
                slave_name = Tcl_GetStringFromObj(elem, (int*)NULL);
                DUMP2("delete slave:'%s'", slave_name);

                Tcl_DecrRefCount(elem);

                slave = Tcl_GetSlave(ip, slave_name);
                if (slave == (Tcl_Interp*)NULL) continue;

                /* call ip_finalize */
                ip_finalize(slave);

                Tcl_DeleteInterp(slave);
                /* Tcl_Release(slave); */
            }
        }

        Tcl_DecrRefCount(slave_list);
    }

    rb_thread_critical = thr_crit_bup;
}
#else /* TCL_MAJOR_VERSION < 8 */
static void
delete_slaves(ip)
    Tcl_Interp *ip;
{
    int  thr_crit_bup;
    Tcl_Interp *slave;
    int argc;
    char **argv;
    char *slave_list;
    char *slave_name;
    int i, len;

    DUMP1("delete slaves");
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (!Tcl_InterpDeleted(ip) && Tcl_Eval(ip, "interp slaves") == TCL_OK) {
        slave_list = ip->result;
        if (Tcl_SplitList((Tcl_Interp*)NULL, 
                          slave_list, &argc, &argv) == TCL_OK) {
            for(i = 0; i < argc; i++) {
                slave_name = argv[i];

                DUMP2("delete slave:'%s'", slave_name);

                slave = Tcl_GetSlave(ip, slave_name);
                if (slave == (Tcl_Interp*)NULL) continue;

                /* call ip_finalize */
                ip_finalize(slave);

                Tcl_DeleteInterp(slave);
            }
        }
    }

    rb_thread_critical = thr_crit_bup;
}
#endif


/* finalize operation */
static void
lib_mark_at_exit(self)
    VALUE self;
{
    at_exit = 1;
}

static int
#if TCL_MAJOR_VERSION >= 8
ip_null_proc(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int argc;
    Tcl_Obj *CONST argv[];
#else /* TCL_MAJOR_VERSION < 8 */
ip_null_proc(clientData, interp, argc, argv)
    ClientData clientData;
    Tcl_Interp *interp;
    int argc;
    char *argv[];
#endif
{
    Tcl_ResetResult(interp);
    return TCL_OK;
}

static void
ip_finalize(ip)
    Tcl_Interp *ip;
{
    Tcl_CmdInfo info;
    int  thr_crit_bup;

    VALUE rb_debug_bup, rb_verbose_bup;
          /* When ruby is exiting, printing debug messages in some callback 
             operations from Tcl-IP sometimes cause SEGV. I don't know the 
             reason. But I got SEGV when calling "rb_io_write(rb_stdout, ...)".
             So, in some part of this function, debug mode and verbose mode 
             are disabled. If you know the reason, please fix it.
                           --  Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)  */

    DUMP1("start ip_finalize");

    if (ip == (Tcl_Interp*)NULL) {
        DUMP1("ip is NULL");
        return;
    }

    if (Tcl_InterpDeleted(ip)) {
        DUMP2("ip(%p) is already deleted", ip);
        return;
    }

#if TCL_NAMESPACE_DEBUG
    if (ip_null_namespace(ip)) {
        DUMP2("ip(%p) has null namespace", ip);
        return;
    }
#endif

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    rb_debug_bup   = ruby_debug;
    rb_verbose_bup = ruby_verbose;

    Tcl_Preserve(ip);

    /* delete slaves */
    delete_slaves(ip);

    /* shut off some connections from Tcl-proc to Ruby */
    if (at_exit) {
	/* NOTE: Only when at exit. 
	   Because, ruby removes objects, which depends on the deleted 
	   interpreter, on some callback operations. 
	   It is important for GC. */
#if TCL_MAJOR_VERSION >= 8
	Tcl_CreateObjCommand(ip, "ruby", ip_null_proc, 
			     (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
	Tcl_CreateObjCommand(ip, "ruby_eval", ip_null_proc, 
			     (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
	Tcl_CreateObjCommand(ip, "ruby_cmd", ip_null_proc, 
			     (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
	Tcl_CreateCommand(ip, "ruby", ip_null_proc, 
			  (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
	Tcl_CreateCommand(ip, "ruby_eval", ip_null_proc, 
			  (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
	Tcl_CreateCommand(ip, "ruby_cmd", ip_null_proc, 
			  (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);
#endif
    }

    /* delete root widget */
#if 0
    DUMP1("check `destroy'");
    if (Tcl_GetCommandInfo(ip, "destroy", &info)) {
        DUMP1("call `destroy'");
        Tcl_GlobalEval(ip, "destroy .");
    }
#endif
#if 1
    DUMP1("destroy root widget");
    if (tk_stubs_init_p() && Tk_MainWindow(ip) != (Tk_Window)NULL) {
        DUMP1("call Tk_DestroyWindow");
        ruby_debug   = Qfalse;
        ruby_verbose = Qnil;
        Tk_DestroyWindow(Tk_MainWindow(ip));
        ruby_debug   = rb_debug_bup;
        ruby_verbose = rb_verbose_bup;
    }
#endif

    /* call finalize-hook-proc */
    DUMP1("check `finalize-hook-proc'");
    if ( Tcl_GetCommandInfo(ip, finalize_hook_name, &info)) {
        DUMP2("call finalize hook proc '%s'", finalize_hook_name);
        ruby_debug   = Qfalse;
        ruby_verbose = Qnil;
        Tcl_GlobalEval(ip, finalize_hook_name);
        ruby_debug   = rb_debug_bup;
        ruby_verbose = rb_verbose_bup;
    }

    DUMP1("check `foreach' & `after'");
    if ( Tcl_GetCommandInfo(ip, "foreach", &info)
         && Tcl_GetCommandInfo(ip, "after", &info) ) {
        DUMP1("cancel after callbacks");
        ruby_debug   = Qfalse;
        ruby_verbose = Qnil;
        Tcl_GlobalEval(ip, "foreach id [after info] {after cancel $id}");
        ruby_debug   = rb_debug_bup;
        ruby_verbose = rb_verbose_bup;
    }

    Tcl_Release(ip);

    DUMP1("finish ip_finalize");
    ruby_debug   = rb_debug_bup;
    ruby_verbose = rb_verbose_bup;
    rb_thread_critical = thr_crit_bup;
}


/* destroy interpreter */
static void
ip_free(ptr)
    struct tcltkip *ptr;
{
    int  thr_crit_bup;

    DUMP2("free Tcl Interp %lx", (unsigned long)ptr->ip);
    if (ptr) {
        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        if ( ptr->ip != (Tcl_Interp*)NULL 
             && !Tcl_InterpDeleted(ptr->ip)
             && Tcl_GetMaster(ptr->ip) != (Tcl_Interp*)NULL 
             && !Tcl_InterpDeleted(Tcl_GetMaster(ptr->ip)) ) {
            DUMP2("parent IP(%lx) is not deleted", 
                  (unsigned long)Tcl_GetMaster(ptr->ip));
            DUMP2("slave IP(%lx) should not be deleted", 
                  (unsigned long)ptr->ip);
            free(ptr);
            rb_thread_critical = thr_crit_bup;
            return;
        }

        if (ptr->ip == (Tcl_Interp*)NULL) {
            DUMP1("ip_free is called for deleted IP");
            free(ptr);
            rb_thread_critical = thr_crit_bup;
            return;
        }

        ip_finalize(ptr->ip);
        Tcl_DeleteInterp(ptr->ip); 
        Tcl_Release(ptr->ip); 

        ptr->ip = (Tcl_Interp*)NULL;
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

static void
ip_replace_wait_commands(interp, mainWin)
    Tcl_Interp *interp;
    Tk_Window mainWin;
{
    /* replace 'vwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"vwait\")");
    Tcl_CreateObjCommand(interp, "vwait", ip_rbVwaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"vwait\")");
    Tcl_CreateCommand(interp, "vwait", ip_rbVwaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* replace 'tkwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"tkwait\")");
    Tcl_CreateObjCommand(interp, "tkwait", ip_rbTkWaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"tkwait\")");
    Tcl_CreateCommand(interp, "tkwait", ip_rbTkWaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'thread_vwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_vwait\")");
    Tcl_CreateObjCommand(interp, "thread_vwait", ip_rb_threadVwaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"thread_vwait\")");
    Tcl_CreateCommand(interp, "thread_vwait", ip_rb_threadVwaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'thread_tkwait' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_tkwait\")");
    Tcl_CreateObjCommand(interp, "thread_tkwait", ip_rb_threadTkWaitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"thread_tkwait\")");
    Tcl_CreateCommand(interp, "thread_tkwait", ip_rb_threadTkWaitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* replace 'update' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"update\")");
    Tcl_CreateObjCommand(interp, "update", ip_rbUpdateObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"update\")");
    Tcl_CreateCommand(interp, "update", ip_rbUpdateCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* add 'thread_update' command */
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"thread_update\")");
    Tcl_CreateObjCommand(interp, "thread_update", ip_rb_threadUpdateObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"thread_update\")");
    Tcl_CreateCommand(interp, "thread_update", ip_rb_threadUpdateCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif
}



#if TCL_MAJOR_VERSION >= 8
static int ip_rbNamespaceObjCmd _((ClientData, Tcl_Interp *, int,
                                   Tcl_Obj *CONST []));
static int
ip_rbNamespaceObjCmd(clientData, interp, objc, objv)
    ClientData clientData;
    Tcl_Interp *interp; 
    int objc;
    Tcl_Obj *CONST objv[];
{
    Tcl_CmdInfo info;
    int ret;

    if (!Tcl_GetCommandInfo(interp, "__orig_namespace_command__", &(info))) {
        Tcl_ResetResult(interp);
        Tcl_AppendResult(interp, 
                         "invalid command name \"namespace\"", (char*)NULL);
        return TCL_ERROR;
    }

    rbtk_eventloop_depth++;
    DUMP2("namespace wrapper enter depth == %d", rbtk_eventloop_depth);

    if (info.isNativeObjectProc) {
        ret = (*(info.objProc))(info.objClientData, interp, objc, objv);
    } else {
        /* string interface */
        int i;
        char **argv;

        argv = (char **)Tcl_Alloc(sizeof(char *) * (objc + 1));

        for(i = 0; i < objc; i++) {
            /* argv[i] = Tcl_GetString(objv[i]); */
            argv[i] = Tcl_GetStringFromObj(objv[i], (int*)NULL);
        }
        argv[objc] = (char *)NULL;

        ret = (*(info.proc))(info.clientData, interp, 
                              objc, (CONST84 char **)argv);

        Tcl_Free((char*)argv);
    }

    DUMP2("namespace wrapper exit depth == %d", rbtk_eventloop_depth);
    rbtk_eventloop_depth--;

    return ret;
}
#endif

static void
ip_wrap_namespace_command(interp)
    Tcl_Interp *interp; 
{
#if TCL_MAJOR_VERSION >= 8
    Tcl_CmdInfo orig_info;

    if (!Tcl_GetCommandInfo(interp, "namespace", &(orig_info))) {
        return;
    }

    if (orig_info.isNativeObjectProc) {
        Tcl_CreateObjCommand(interp, "__orig_namespace_command__", 
                             orig_info.objProc, orig_info.objClientData, 
                             orig_info.deleteProc);
    } else {
        Tcl_CreateCommand(interp, "__orig_namespace_command__", 
                          orig_info.proc, orig_info.clientData, 
                          orig_info.deleteProc);
    }

    Tcl_CreateObjCommand(interp, "namespace", ip_rbNamespaceObjCmd, 
                         (ClientData) 0, (Tcl_CmdDeleteProc *)NULL);
#endif
}


/* call when interpreter is deleted */
static void
ip_CallWhenDeleted(clientData, ip)
    ClientData clientData;
    Tcl_Interp *ip;
{
    int  thr_crit_bup;
    /* Tk_Window main_win = (Tk_Window) clientData; */

    DUMP1("start ip_CallWhenDeleted");
    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    ip_finalize(ip);

    DUMP1("finish ip_CallWhenDeleted");
    rb_thread_critical = thr_crit_bup;
}

/* initialize interpreter */
static VALUE
ip_init(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct tcltkip *ptr;        /* tcltkip data struct */
    VALUE argv0, opts;
    int cnt;
    int st;
    int with_tk = 1;
    Tk_Window mainWin = (Tk_Window)NULL;

    /* security check */
    if (ruby_safe_level >= 4) {
        rb_raise(rb_eSecurityError, 
                 "Cannot create a TclTkIp object at level %d", 
                 ruby_safe_level);
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
    ptr->ip = ruby_tcl_create_ip_and_stubs_init(&st);
    if (ptr->ip == NULL) {
        switch(st) {
        case TCLTK_STUBS_OK:
            break;
        case NO_TCL_DLL:
            rb_raise(rb_eLoadError, "tcltklib: fail to open tcl_dll");
        case NO_FindExecutable:
            rb_raise(rb_eLoadError, "tcltklib: can't find Tcl_FindExecutable");
        case NO_CreateInterp:
            rb_raise(rb_eLoadError, "tcltklib: can't find Tcl_CreateInterp()");
        case NO_DeleteInterp:
            rb_raise(rb_eLoadError, "tcltklib: can't find Tcl_DeleteInterp()");
        case FAIL_CreateInterp:
            rb_raise(rb_eRuntimeError, "tcltklib: fail to create a new IP");
        case FAIL_Tcl_InitStubs:
            rb_raise(rb_eRuntimeError, "tcltklib: fail to Tcl_InitStubs()");
        default:
            rb_raise(rb_eRuntimeError, "tcltklib: unknown error(%d) on ruby_tcl_create_ip_and_stubs_init", st);
        }
    }

#if TCL_MAJOR_VERSION >= 8
#if TCL_NAMESPACE_DEBUG
    DUMP1("get current namespace");
    if ((ptr->default_ns = Tcl_GetCurrentNamespace(ptr->ip)) 
        == (Tcl_Namespace*)NULL) {
      rb_raise(rb_eRuntimeError, "a new Tk interpreter has a NULL namespace");
    }
#endif
#endif

    rbtk_preserve_ip(ptr);
    DUMP2("IP ref_count = %d", ptr->ref_count);
    current_interp = ptr->ip;

    ptr->has_orig_exit 
        = Tcl_GetCommandInfo(ptr->ip, "exit", &(ptr->orig_exit_info));

    /* from Tcl_AppInit() */
    DUMP1("Tcl_Init");
    if (Tcl_Init(ptr->ip) == TCL_ERROR) {
        rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(ptr->ip));
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
        st = ruby_tk_stubs_init(ptr->ip);
        switch(st) {
        case TCLTK_STUBS_OK:
            break;
        case NO_Tk_Init:
            rb_raise(rb_eLoadError, "tcltklib: can't find Tk_Init()");
        case FAIL_Tk_Init:
            rb_raise(rb_eRuntimeError, "tcltklib: fail to Tk_Init(). %s", 
                     Tcl_GetStringResult(ptr->ip));
        case FAIL_Tk_InitStubs:
            rb_raise(rb_eRuntimeError, "tcltklib: fail to Tk_InitStubs(). %s", 
                     Tcl_GetStringResult(ptr->ip));
        default:
            rb_raise(rb_eRuntimeError, "tcltklib: unknown error(%d) on ruby_tk_stubs_init", st);
        }

        DUMP1("Tcl_StaticPackage(\"Tk\")");
#if TCL_MAJOR_VERSION >= 8
        Tcl_StaticPackage(ptr->ip, "Tk", Tk_Init, Tk_SafeInit);
#else /* TCL_MAJOR_VERSION < 8 */
        Tcl_StaticPackage(ptr->ip, "Tk", Tk_Init,
                          (Tcl_PackageInitProc *) NULL);
#endif

        /* get main window */
        mainWin = Tk_MainWindow(ptr->ip);
        Tk_Preserve((ClientData)mainWin);
    }

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

    /* replace vwait and tkwait */
    ip_replace_wait_commands(ptr->ip, mainWin);

    /* wrap namespace command */
    ip_wrap_namespace_command(ptr->ip);

    /* set finalizer */
    Tcl_CallWhenDeleted(ptr->ip, ip_CallWhenDeleted, (ClientData)mainWin);

    if (mainWin != (Tk_Window)NULL) {
        Tk_Release((ClientData)mainWin);
    }

    return self;
}

static VALUE
ip_create_slave_core(interp, argc, argv)
    VALUE interp;
    int   argc;
    VALUE *argv;
{
    struct tcltkip *master = get_ip(interp);
    struct tcltkip *slave = ALLOC(struct tcltkip);
    VALUE safemode;
    VALUE name;
    int safe;
    int thr_crit_bup;
    Tk_Window mainWin;

    /* ip is deleted? */
    if (deleted_ip(master)) {
        return rb_exc_new2(rb_eRuntimeError, 
                           "deleted master cannot create a new slave");
    }

    name     = argv[0];
    safemode = argv[1];

    if (Tcl_IsSafe(master->ip) == 1) {
        safe = 1;
    } else if (safemode == Qfalse || NIL_P(safemode)) {
        safe = 0;
        /* rb_secure(4); */ /* already checked */
    } else {
        safe = 1;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

#if 0
    /* init Tk */
    if (RTEST(with_tk)) {
        volatile VALUE exc;
        if (!tk_stubs_init_p()) {
            exc = tcltkip_init_tk(interp);
            if (!NIL_P(exc)) {
                rb_thread_critical = thr_crit_bup;
                return exc;
            }
        }
    }
#endif

    /* create slave-ip */
    slave->ref_count = 0;
    slave->allow_ruby_exit = 0;
    slave->return_value = 0;

    slave->ip = Tcl_CreateSlave(master->ip, StringValuePtr(name), safe);
    if (slave->ip == NULL) {
        rb_thread_critical = thr_crit_bup;
        return rb_exc_new2(rb_eRuntimeError, 
                           "fail to create the new slave interpreter");
    }
#if TCL_MAJOR_VERSION >= 8
#if TCL_NAMESPACE_DEBUG
    slave->default_ns = Tcl_GetCurrentNamespace(slave->ip);
#endif
#endif
    rbtk_preserve_ip(slave);

    slave->has_orig_exit 
        = Tcl_GetCommandInfo(slave->ip, "exit", &(slave->orig_exit_info));

    /* replace 'exit' command --> 'interp_exit' command */
    mainWin = (tk_stubs_init_p())? Tk_MainWindow(slave->ip): (Tk_Window)NULL;
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateObjCommand(slave->ip, "exit", ip_InterpExitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateCommand(slave->ip, "exit", ip_InterpExitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    /* replace vwait and tkwait */
    ip_replace_wait_commands(slave->ip, mainWin);

    /* wrap namespace command */
    ip_wrap_namespace_command(slave->ip);

    /* set finalizer */
    Tcl_CallWhenDeleted(slave->ip, ip_CallWhenDeleted, (ClientData)mainWin);

    rb_thread_critical = thr_crit_bup;

    return Data_Wrap_Struct(CLASS_OF(interp), 0, ip_free, slave);
}

static VALUE
ip_create_slave(argc, argv, self)
    int   argc;
    VALUE *argv;
    VALUE self;
{
    struct tcltkip *master = get_ip(self);
    VALUE safemode;
    VALUE name;
    VALUE callargv[2];

    /* ip is deleted? */
    if (deleted_ip(master)) {
        rb_raise(rb_eRuntimeError, 
                 "deleted master cannot create a new slave interpreter");
    }

    /* argument check */
    if (rb_scan_args(argc, argv, "11", &name, &safemode) == 1) {
        safemode = Qfalse;
    }
    if (Tcl_IsSafe(master->ip) != 1
        && (safemode == Qfalse || NIL_P(safemode))) {
        rb_secure(4);
    }

    StringValue(name);
    callargv[0] = name;
    callargv[1] = safemode;

    return tk_funcall(ip_create_slave_core, 2, callargv, self);
}


/* self is slave of master? */
static VALUE
ip_is_slave_of_p(self, master)
    VALUE self, master;
{
    if (!rb_obj_is_kind_of(master, tcltkip_class)) {
        rb_raise(rb_eArgError, "expected TclTkIp object");
    }

    if (Tcl_GetMaster(get_ip(self)->ip) == get_ip(master)->ip) {
      return Qtrue;
    } else {
      return Qfalse;
    }
}


/* create console (if supported) */
#if defined(MAC_TCL) || defined(__WIN32__)
#if TCL_MAJOR_VERSION < 8 \
    || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0) \
    || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 1 \
        && (TCL_RELEASE_LEVEL == TCL_ALPHA_RELEASE \
           || (TCL_RELEASE_LEVEL == TCL_BETA_RELEASE \
               && TCL_RELEASE_SERIAL < 2) ) )
EXTERN void TkConsoleCreate _((void));
#endif
#if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 1 \
    && ( (TCL_RELEASE_LEVEL == TCL_FINAL_RELEASE \
          && TCL_RELEASE_SERIAL == 0) \
       || (TCL_RELEASE_LEVEL == TCL_BETA_RELEASE \
           && TCL_RELEASE_SERIAL >= 2) )
EXTERN void TkConsoleCreate_ _((void));
#endif
#endif
static VALUE
ip_create_console_core(interp, argc, argv)
    VALUE interp;
    int   argc;   /* dummy */
    VALUE *argv;  /* dummy */
{
    struct tcltkip *ptr = get_ip(interp);

    if (!tk_stubs_init_p()) {
        tcltkip_init_tk(interp);
    }

    if (Tcl_GetVar(ptr->ip,"tcl_interactive",TCL_GLOBAL_ONLY) == (char*)NULL) {
        Tcl_SetVar(ptr->ip, "tcl_interactive", "0", TCL_GLOBAL_ONLY);
    }

#if TCL_MAJOR_VERSION > 8 \
    || (TCL_MAJOR_VERSION == 8 \
        && (TCL_MINOR_VERSION > 1 \
            || (TCL_MINOR_VERSION == 1 \
                 && TCL_RELEASE_LEVEL == TCL_FINAL_RELEASE \
                 && TCL_RELEASE_SERIAL >= 1) ) )
    Tk_InitConsoleChannels(ptr->ip);

    if (Tk_CreateConsoleWindow(ptr->ip) != TCL_OK) {
        rb_raise(rb_eRuntimeError, "fail to create console-window");
    }
#else
#if defined(MAC_TCL) || defined(__WIN32__)
#if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 1 \
    && ( (TCL_RELEASE_LEVEL == TCL_FINAL_RELEASE && TCL_RELEASE_SERIAL == 0) \
        || (TCL_RELEASE_LEVEL == TCL_BETA_RELEASE && TCL_RELEASE_SERIAL >= 2) )
    TkConsoleCreate_();
#else
    TkConsoleCreate();
#endif

    if (TkConsoleInit(ptr->ip) != TCL_OK) {
        rb_raise(rb_eRuntimeError, "fail to create console-window");
    }
#else
    rb_notimplement();
#endif
#endif

    return interp;
}

static VALUE
ip_create_console(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    
    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    return tk_funcall(ip_create_console_core, 0, (VALUE*)NULL, self);
}

/* make ip "safe" */
static VALUE
ip_make_safe_core(interp, argc, argv)
    VALUE interp;
    int   argc;   /* dummy */
    VALUE *argv;  /* dummy */
{
    struct tcltkip *ptr = get_ip(interp);
    Tk_Window mainWin;
    
    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        return rb_exc_new2(rb_eRuntimeError, "interpreter is deleted");
    }

    if (Tcl_MakeSafe(ptr->ip) == TCL_ERROR) {
        /* return rb_exc_new2(rb_eRuntimeError, 
                              Tcl_GetStringResult(ptr->ip)); */
        return create_ip_exc(interp, rb_eRuntimeError, 
                             Tcl_GetStringResult(ptr->ip));
    }

    ptr->allow_ruby_exit = 0;

    /* replace 'exit' command --> 'interp_exit' command */
    mainWin = (tk_stubs_init_p())? Tk_MainWindow(ptr->ip): (Tk_Window)NULL;
#if TCL_MAJOR_VERSION >= 8
    DUMP1("Tcl_CreateObjCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateObjCommand(ptr->ip, "exit", ip_InterpExitObjCmd, 
                         (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#else /* TCL_MAJOR_VERSION < 8 */
    DUMP1("Tcl_CreateCommand(\"exit\") --> \"interp_exit\"");
    Tcl_CreateCommand(ptr->ip, "exit", ip_InterpExitCommand, 
                      (ClientData)mainWin, (Tcl_CmdDeleteProc *)NULL);
#endif

    return interp;
}

static VALUE
ip_make_safe(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    
    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    return tk_funcall(ip_make_safe_core, 0, (VALUE*)NULL, self);
}

/* is safe? */
static VALUE
ip_is_safe_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);
    
    /* ip is deleted? */
    if (deleted_ip(ptr)) {
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
    if (deleted_ip(ptr)) {
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
    if (deleted_ip(ptr)) {
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    if (Tcl_IsSafe(ptr->ip)) {
        rb_raise(rb_eSecurityError, 
                 "insecure operation on a safe interpreter");
    }

    mainWin = (tk_stubs_init_p())? Tk_MainWindow(ptr->ip): (Tk_Window)NULL;

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
    int  thr_crit_bup;
    struct tcltkip *ptr = get_ip(self);

    if (ptr == (struct tcltkip *)NULL || ptr->ip == (Tcl_Interp*)NULL) {
        DUMP1("delete deleted IP");
        return Qnil;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    DUMP1("call ip_finalize");
    ip_finalize(ptr->ip);

    DUMP1("delete interp");
    Tcl_DeleteInterp(ptr->ip);
    Tcl_Release(ptr->ip);

    rb_thread_critical = thr_crit_bup;

    return Qnil;
}


/* is deleted? */
static VALUE
ip_has_invalid_namespace_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    if (ptr == (struct tcltkip *)NULL || ptr->ip == (Tcl_Interp *)NULL) {
        /* deleted IP */
        return Qtrue;
    }

#if TCL_NAMESPACE_DEBUG
    if (rbtk_invalid_namespace(ptr)) {
        return Qtrue;
    } else {
        return Qfalse;
    }
#else
    return Qfalse;
#endif
}

static VALUE
ip_is_deleted_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    if (deleted_ip(ptr)) {
        return Qtrue;
    } else {
        return Qfalse;
    }
}

static VALUE
ip_has_mainwindow_p(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    if (deleted_ip(ptr) || !tk_stubs_init_p()) {
        return Qnil;
    } else if (Tk_MainWindow(ptr->ip) == (Tk_Window)NULL) {
        return Qfalse;
    } else {
        return Qtrue;
    }
}

/*** ruby string <=> tcl object ***/
#if TCL_MAJOR_VERSION >= 8
static VALUE
get_str_from_obj(obj)
    Tcl_Obj *obj;
{
    int len, binary = 0;
    const char *s;
    volatile VALUE str;

#if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
    s = Tcl_GetStringFromObj(obj, &len);
#else /* TCL_VERSION >= 8.1 */
    if (Tcl_GetCharLength(obj) != Tcl_UniCharLen(Tcl_GetUnicode(obj))) {
        /* possibly binary string */
        s = Tcl_GetByteArrayFromObj(obj, &len);
        binary = 1;
    } else {
        /* possibly text string */
        s = Tcl_GetStringFromObj(obj, &len);
    }
#endif
    str = s ? rb_str_new(s, len) : rb_str_new2("");
    if (binary) rb_ivar_set(str, ID_at_enc, rb_str_new2("binary"));
    return str;
}

static Tcl_Obj *
get_obj_from_str(str)
    VALUE str;
{
    const char *s = StringValuePtr(str);

#if TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION == 0
    return Tcl_NewStringObj((char*)s, RSTRING(str)->len);
#else /* TCL_VERSION >= 8.1 */
    VALUE enc = rb_attr_get(str, ID_at_enc);

    if (!NIL_P(enc)) {
        StringValue(enc);
        if (strcmp(RSTRING(enc)->ptr, "binary") == 0) {
            /* binary string */
            return Tcl_NewByteArrayObj(s, RSTRING(str)->len);
        } else {
            /* text string */
            return Tcl_NewStringObj(s, RSTRING(str)->len);
        }
    } else if (strlen(s) != RSTRING(str)->len) {
        /* probably binary string */
        return Tcl_NewByteArrayObj(s, RSTRING(str)->len);
    } else {
        /* probably text string */
        return Tcl_NewStringObj(s, RSTRING(str)->len);
    }
#endif
}
#endif /* ruby string <=> tcl object */

static VALUE
ip_get_result_string_obj(interp)
    Tcl_Interp *interp;
{
#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj *retObj;
    volatile VALUE strval;

    retObj = Tcl_GetObjResult(interp);
    Tcl_IncrRefCount(retObj);
    strval = get_str_from_obj(retObj);
    OBJ_TAINT(strval);
    Tcl_DecrRefCount(retObj);
    return strval;
#else
    return rb_tainted_str_new2(interp->result);
#endif
}

/* call Tcl/Tk functions on the eventloop thread */
static VALUE
callq_safelevel_handler(arg, callq)
    VALUE arg;
    VALUE callq;
{
    struct call_queue *q;

    Data_Get_Struct(callq, struct call_queue, q);
    DUMP2("(safe-level handler) $SAFE = %d", q->safe_level);
    rb_set_safe_level(q->safe_level);
    return((q->func)(q->interp, q->argc, q->argv));
}

static int call_queue_handler _((Tcl_Event *, int));
static int
call_queue_handler(evPtr, flags)
    Tcl_Event *evPtr;
    int flags;
{
    struct call_queue *q = (struct call_queue *)evPtr;
    volatile VALUE ret;
    volatile VALUE q_dat;
    struct tcltkip *ptr;

    DUMP2("do_call_queue_handler : evPtr = %p", evPtr);
    DUMP2("queue_handler thread : %lx", rb_thread_current());
    DUMP2("added by thread : %lx", q->thread);

    if (*(q->done)) {
        DUMP1("processed by another event-loop");
        return 0;
    } else {
        DUMP1("process it on current event-loop");
    }

    /* process it */
    *(q->done) = 1;

    /* deleted ipterp ? */
    ptr = get_ip(q->interp);
    if (deleted_ip(ptr)) {
        /* deleted IP --> ignore */
        return 1;
    }

    /* check safe-level */
    if (rb_safe_level() != q->safe_level) {
        /* q_dat = Data_Wrap_Struct(rb_cData,0,0,q); */
        q_dat = Data_Wrap_Struct(rb_cData,call_queue_mark,0,q);
        ret = rb_funcall(rb_proc_new(callq_safelevel_handler, q_dat), 
                         ID_call, 0);
        rb_gc_force_recycle(q_dat);
    } else {
        DUMP2("call function (for caller thread:%lx)", q->thread);
        DUMP2("call function (current thread:%lx)", rb_thread_current());
        ret = (q->func)(q->interp, q->argc, q->argv);
    }

    /* set result */
    RARRAY(q->result)->ptr[0] = ret;

    /* complete */
    *(q->done) = -1;

    /* back to caller */
    if (RTEST(rb_funcall(q->thread, ID_alive_p, 0, 0))) {
      DUMP2("back to caller (caller thread:%lx)", q->thread);
      DUMP2("               (current thread:%lx)", rb_thread_current());
      rb_thread_run(q->thread);
      DUMP1("finish back to caller");
    } else {
      DUMP2("caller is dead (caller thread:%lx)", q->thread);
      DUMP2("               (current thread:%lx)", rb_thread_current());
    }

    /* end of handler : remove it */
    return 1;
}

static VALUE
tk_funcall(func, argc, argv, obj)
    VALUE (*func)();
    int argc;
    VALUE *argv;
    VALUE obj;
{
    struct call_queue *callq;
    int  *alloc_done;
    int  thr_crit_bup;
    volatile VALUE current = rb_thread_current();
    volatile VALUE ip_obj = obj;
    volatile VALUE result;
    volatile VALUE ret;


    if (!NIL_P(ip_obj) && deleted_ip(get_ip(ip_obj))) {
        return Qnil;
    }

    if (NIL_P(eventloop_thread) || current == eventloop_thread) {
        if (NIL_P(eventloop_thread)) {
            DUMP2("tk_funcall from thread:%lx but no eventloop", current);
        } else {
            DUMP2("tk_funcall from current eventloop %lx", current);
        }
        result = (func)(ip_obj, argc, argv);
        if (rb_obj_is_kind_of(result, rb_eException)) {
            rb_exc_raise(result);
        }
        return result;
    }

    DUMP2("tk_funcall from thread %lx (NOT current eventloop)", current);

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* allocate memory (argv cross over thread : must be in heap) */
    if (argv) {
        VALUE *temp = ALLOC_N(VALUE, argc);
        MEMCPY(temp, argv, VALUE, argc);
        argv = temp;
    }

    /* allocate memory (keep result) */
    alloc_done = (int*)ALLOC(int);
    *alloc_done = 0;

    /* allocate memory (freed by Tcl_ServiceEvent) */
    callq = (struct call_queue *)Tcl_Alloc(sizeof(struct call_queue));
    Tcl_Preserve(callq);

    /* allocate result obj */
    result = rb_ary_new2(1);
    RARRAY(result)->ptr[0] = Qnil;
    RARRAY(result)->len = 1;

    /* construct event data */
    callq->done = alloc_done;
    callq->func = func;
    callq->argc = argc;
    callq->argv = argv;
    callq->interp = ip_obj;
    callq->result = result;
    callq->thread = current;
    callq->safe_level = rb_safe_level();
    callq->ev.proc = call_queue_handler;

    /* add the handler to Tcl event queue */
    DUMP1("add handler");
    Tcl_QueueEvent(&(callq->ev), TCL_QUEUE_HEAD);

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
    if (argv) free(argv);

    Tcl_Release(callq);

    /* exception? */
    if (rb_obj_is_kind_of(ret, rb_eException)) {
        DUMP1("raise exception");
        rb_exc_raise(ret);
    }

    DUMP1("exit tk_funcall");
    return ret;
}


/* eval string in tcl by Tcl_Eval() */
#if TCL_MAJOR_VERSION >= 8
struct call_eval_info {
    struct tcltkip *ptr;
    Tcl_Obj *cmd;
};

static VALUE
call_tcl_eval(arg)
    VALUE arg;
{
    struct call_eval_info *inf = (struct call_eval_info *)arg;

    Tcl_AllowExceptions(inf->ptr->ip);
    inf->ptr->return_value = Tcl_EvalObj(inf->ptr->ip, inf->cmd);

    return Qnil;
}
#endif

static VALUE
ip_eval_real(self, cmd_str, cmd_len)
    VALUE self;
    char *cmd_str;
    int  cmd_len;
{
    volatile VALUE ret;
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
      if (deleted_ip(ptr)) {
          Tcl_DecrRefCount(cmd);
          rb_thread_critical = thr_crit_bup;
          ptr->return_value = TCL_OK;
          return rb_tainted_str_new2("");
      } else {
          int status;
          struct call_eval_info inf;

          /* Tcl_Preserve(ptr->ip); */
          rbtk_preserve_ip(ptr);

#if 0
          ptr->return_value = Tcl_EvalObj(ptr->ip, cmd);
          /* ptr->return_value = Tcl_GlobalEvalObj(ptr->ip, cmd); */
#else
          inf.ptr = ptr;
          inf.cmd = cmd;
          ret = rb_protect(call_tcl_eval, (VALUE)&inf, &status);
          switch(status) {
          case TAG_RAISE:
              if (NIL_P(ruby_errinfo)) {
                  rbtk_pending_exception = rb_exc_new2(rb_eException, 
                                                       "unknown exception");
              } else {
                  rbtk_pending_exception = ruby_errinfo;
              }
              break;

          case TAG_FATAL:
              if (NIL_P(ruby_errinfo)) {
                  rbtk_pending_exception = rb_exc_new2(rb_eFatal, "FATAL");
              } else {
                  rbtk_pending_exception = ruby_errinfo;
              }
          }
#endif
      }

      Tcl_DecrRefCount(cmd);

    }

    if (pending_exception_check1(thr_crit_bup, ptr)) {
        rbtk_release_ip(ptr);
        return rbtk_pending_exception;
    }

    if (ptr->return_value == TCL_ERROR) {
        if (event_loop_abort_on_exc > 0 && !Tcl_InterpDeleted(ptr->ip)) {
            volatile VALUE exc;
            exc = create_ip_exc(self, rb_eRuntimeError, 
                                "%s", Tcl_GetStringResult(ptr->ip));
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            return exc;
        } else {
            if (event_loop_abort_on_exc < 0) {
                rb_warning("%s (ignore)", Tcl_GetStringResult(ptr->ip));
            } else {
                rb_warn("%s (ignore)", Tcl_GetStringResult(ptr->ip));
            }
            Tcl_ResetResult(ptr->ip);
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            return rb_tainted_str_new2("");
        }
    }

    /* pass back the result (as string) */
    ret =  ip_get_result_string_obj(ptr->ip);
    rbtk_release_ip(ptr);
    rb_thread_critical = thr_crit_bup;
    return ret;

#else /* TCL_MAJOR_VERSION < 8 */
    DUMP2("Tcl_Eval(%s)", cmd_str);

    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        ptr->return_value = TCL_OK;
        return rb_tainted_str_new2("");
    } else {
        /* Tcl_Preserve(ptr->ip); */
        rbtk_preserve_ip(ptr);
        ptr->return_value = Tcl_Eval(ptr->ip, cmd_str);
        /* ptr->return_value = Tcl_GlobalEval(ptr->ip, cmd_str); */
    }

    if (pending_exception_check1(thr_crit_bup, ptr)) {
        rbtk_release_ip(ptr);
        return rbtk_pending_exception;
    }

    if (ptr->return_value == TCL_ERROR) {
        volatile VALUE exc;

        exc = create_ip_exc(self, rb_eRuntimeError, "%s", ptr->ip->result);

        rbtk_release_ip(ptr);
        return exc;
    }
    DUMP2("(TCL_Eval result) %d", ptr->return_value);

    /* pass back the result (as string) */
    ret =  ip_get_result_string_obj(ptr->ip);
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
        ret = ip_eval_real(q->interp, q->str, q->len);
    }

    /* set result */
    RARRAY(q->result)->ptr[0] = ret;

    /* complete */
    *(q->done) = -1;

    /* back to caller */
    if (RTEST(rb_funcall(q->thread, ID_alive_p, 0, 0))) {
      DUMP2("back to caller (caller thread:%lx)", q->thread);
      DUMP2("               (current thread:%lx)", rb_thread_current());
      rb_thread_run(q->thread);
      DUMP1("finish back to caller");
    } else {
      DUMP2("caller is dead (caller thread:%lx)", q->thread);
      DUMP2("               (current thread:%lx)", rb_thread_current());
    }

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

    if (NIL_P(eventloop_thread) || current == eventloop_thread) {
        if (NIL_P(eventloop_thread)) {
            DUMP2("eval from thread:%lx but no eventloop", current);
        } else {
            DUMP2("eval from current eventloop %lx", current);
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
    memcpy(eval_str, RSTRING(str)->ptr, RSTRING(str)->len);
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
lib_restart_core(interp, argc, argv)
    VALUE interp;
    int   argc;   /* dummy */
    VALUE *argv;  /* dummy */
{
    volatile VALUE exc;
    struct tcltkip *ptr = get_ip(interp);
    int  thr_crit_bup;

    /* rb_secure(4); */ /* already checked */

    /* tcl_stubs_check(); */ /* already checked */

    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        return rb_exc_new2(rb_eRuntimeError, "interpreter is deleted");
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

#if TCL_MAJOR_VERSION >= 8
    /* delete namespace ( tested on tk8.4.5 ) */
    ptr->return_value = Tcl_Eval(ptr->ip, "namespace delete ::tk::msgcat");
    /* ignore ERROR */
    DUMP2("(TCL_Eval result) %d", ptr->return_value);
    Tcl_ResetResult(ptr->ip);
#endif

    /* delete trace proc ( tested on tk8.4.5 ) */
    ptr->return_value = Tcl_Eval(ptr->ip, "trace vdelete ::tk_strictMotif w ::tk::EventMotifBindings");
    /* ignore ERROR */
    DUMP2("(TCL_Eval result) %d", ptr->return_value);
    Tcl_ResetResult(ptr->ip);

    /* execute Tk_Init or Tk_SafeInit */
    exc = tcltkip_init_tk(interp);
    if (!NIL_P(exc)) {
        rb_thread_critical = thr_crit_bup;
        rbtk_release_ip(ptr);
        return exc;
    }

    /* Tcl_Release(ptr->ip); */
    rbtk_release_ip(ptr);

    rb_thread_critical = thr_crit_bup;

    /* return Qnil; */
    return interp;
}

static VALUE
lib_restart(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    rb_secure(4);

    tcl_stubs_check();

    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        rb_raise(rb_eRuntimeError, "interpreter is deleted");
    }

    return tk_funcall(lib_restart_core, 0, (VALUE*)NULL, self);
}


static VALUE
ip_restart(self)
    VALUE self;
{
    struct tcltkip *ptr = get_ip(self);

    rb_secure(4);

    tcl_stubs_check();

    /* ip is deleted? */
    if (deleted_ip(ptr)) {
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
#endif

    tcl_stubs_check();

    if (NIL_P(src)) {
      return rb_str_new2("");
    }

#ifdef TCL_UTF_MAX
    if (NIL_P(ip_obj)) {
        interp = (Tcl_Interp *)NULL;
    } else {
        ptr = get_ip(ip_obj);

        /* ip is deleted? */
        if (deleted_ip(ptr)) {
            interp = (Tcl_Interp *)NULL;
        } else {
            interp = ptr->ip;
        }
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (NIL_P(encodename)) {
        if (TYPE(str) == T_STRING) {
            volatile VALUE enc;
            enc = rb_attr_get(str, ID_at_enc);
            if (NIL_P(enc)) {
                if (NIL_P(ip_obj)) {
                    encoding = (Tcl_Encoding)NULL;
                } else {
                    enc = rb_attr_get(ip_obj, ID_at_enc);
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
    memcpy(buf, RSTRING(str)->ptr, RSTRING(str)->len);
    buf[RSTRING(str)->len] = 0;

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    /* Tcl_ExternalToUtfDString(encoding,buf,strlen(buf),&dstr); */
    Tcl_ExternalToUtfDString(encoding, buf, RSTRING(str)->len, &dstr);

    /* str = rb_tainted_str_new2(Tcl_DStringValue(&dstr)); */
    /* str = rb_str_new2(Tcl_DStringValue(&dstr)); */
    str = rb_str_new(Tcl_DStringValue(&dstr), Tcl_DStringLength(&dstr));
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
#endif

    tcl_stubs_check();

    if (NIL_P(src)) {
      return rb_str_new2("");
    }

#ifdef TCL_UTF_MAX
    if (NIL_P(ip_obj)) {
        interp = (Tcl_Interp *)NULL;
    } else if (get_ip(ip_obj) == (struct tcltkip *)NULL) {
        interp = (Tcl_Interp *)NULL;
    } else {
        interp = get_ip(ip_obj)->ip;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    if (NIL_P(encodename)) {
        volatile VALUE enc;

        if (TYPE(str) == T_STRING) {
            enc = rb_attr_get(str, ID_at_enc);
            if (!NIL_P(enc)) {
                StringValue(enc);
                if (strcmp(RSTRING(enc)->ptr, "binary") == 0) {
                    rb_thread_critical = thr_crit_bup;
                    return str;
                }
            }
        }

        if (NIL_P(ip_obj)) {
            encoding = (Tcl_Encoding)NULL;
        } else {
            enc = rb_attr_get(ip_obj, ID_at_enc);
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

            StringValue(str);
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
    memcpy(buf, RSTRING(str)->ptr, RSTRING(str)->len);
    buf[RSTRING(str)->len] = 0;

    Tcl_DStringInit(&dstr);
    Tcl_DStringFree(&dstr);
    /* Tcl_UtfToExternalDString(encoding,buf,strlen(buf),&dstr); */
    Tcl_UtfToExternalDString(encoding,buf,RSTRING(str)->len,&dstr);

    /* str = rb_tainted_str_new2(Tcl_DStringValue(&dstr)); */
    /* str = rb_str_new2(Tcl_DStringValue(&dstr)); */
    str = rb_str_new(Tcl_DStringValue(&dstr), Tcl_DStringLength(&dstr));
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

    tcl_stubs_check();

    StringValue(str);
    if (!RSTRING(str)->len) {
        return str;
    }

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    src_buf = ALLOC_N(char,(RSTRING(str)->len)+1);
    memcpy(src_buf, RSTRING(str)->ptr, RSTRING(str)->len);
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

static VALUE
lib_get_system_encoding(self)
    VALUE self;
{
#if TCL_MAJOR_VERSION > 8 || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION > 0)
    tcl_stubs_check();
    return rb_str_new2(Tcl_GetEncodingName((Tcl_Encoding)NULL));
#else
    return Qnil;
#endif
}

static VALUE
lib_set_system_encoding(self, enc_name)
    VALUE self;
    VALUE enc_name;
{
#if TCL_MAJOR_VERSION > 8 || (TCL_MAJOR_VERSION == 8 && TCL_MINOR_VERSION > 0)
    tcl_stubs_check();

    if (NIL_P(enc_name)) {
        Tcl_SetSystemEncoding((Tcl_Interp *)NULL, (CONST char *)NULL);
        return lib_get_system_encoding(self);
    }

    enc_name = rb_funcall(enc_name, ID_to_s, 0, 0);
    if (Tcl_SetSystemEncoding((Tcl_Interp *)NULL, 
                              StringValuePtr(enc_name)) != TCL_OK) {
        rb_raise(rb_eArgError, "unknown encoding name '%s'", 
                 RSTRING(enc_name)->ptr);
    }

    return enc_name;
#else
    return Qnil;
#endif
}


/* invoke Tcl proc */
struct invoke_info {
    struct tcltkip *ptr;
    Tcl_CmdInfo cmdinfo;
#if TCL_MAJOR_VERSION >= 8
    int objc;
    Tcl_Obj **objv;
#else
    int argc;
    char **argv;
#endif
};

static VALUE
invoke_tcl_proc(arg)
    VALUE arg;
{
    struct invoke_info *inf = (struct invoke_info *)arg;
    int i, len;
#if TCL_MAJOR_VERSION >= 8
    int argc = inf->objc;
    char **argv = (char **)NULL;
#endif

    /* memory allocation for arguments of this command */
#if TCL_MAJOR_VERSION >= 8
    if (!inf->cmdinfo.isNativeObjectProc) {
        /* string interface */
        argv = (char **)ALLOC_N(char *, argc+1);
        for (i = 0; i < argc; ++i) {
            argv[i] = Tcl_GetStringFromObj(inf->objv[i], &len);
        }
        argv[argc] = (char *)NULL;
    }
#endif

    Tcl_ResetResult(inf->ptr->ip);

    /* Invoke the C procedure */
#if TCL_MAJOR_VERSION >= 8
    if (inf->cmdinfo.isNativeObjectProc) {
        inf->ptr->return_value 
            = (*(inf->cmdinfo.objProc))(inf->cmdinfo.objClientData, 
                                        inf->ptr->ip, inf->objc, inf->objv);
    }
    else
#endif
    {
#if TCL_MAJOR_VERSION >= 8
        inf->ptr->return_value 
            = (*(inf->cmdinfo.proc))(inf->cmdinfo.clientData, inf->ptr->ip, 
                                     argc, (CONST84 char **)argv);

        free(argv);

#else /* TCL_MAJOR_VERSION < 8 */
        inf->ptr->return_value 
            = (*(inf->cmdinfo.proc))(inf->cmdinfo.clientData, inf->ptr->ip, 
                                     inf->argc, inf->argv);
#endif
    }

    return Qnil;
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
    Tcl_CmdInfo info;
    char *cmd;
    int  len;
    int  thr_crit_bup;
    int unknown_flag = 0;

#if 1 /* wrap tcl-proc call */
    struct invoke_info inf;
    int status;
    VALUE ret;
#else
#if TCL_MAJOR_VERSION >= 8
    int argc = objc;
    char **argv = (char **)NULL;
    /* Tcl_Obj *resultPtr; */
#endif
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
    if (deleted_ip(ptr)) {
        return rb_tainted_str_new2("");
    }

    /* Tcl_Preserve(ptr->ip); */
    rbtk_preserve_ip(ptr);

    /* map from the command name to a C procedure */
    DUMP2("call Tcl_GetCommandInfo, %s", cmd);
    if (!Tcl_GetCommandInfo(ptr->ip, cmd, &info)) {
        DUMP1("error Tcl_GetCommandInfo");
        DUMP1("try auto_load (call 'unknown' command)");
        if (!Tcl_GetCommandInfo(ptr->ip, 
#if TCL_MAJOR_VERSION >= 8
                                "::unknown", 
#else
                                "unknown", 
#endif
                                &info)) {
            DUMP1("fail to get 'unknown' command");
            /* if (event_loop_abort_on_exc || cmd[0] != '.') { */
            if (event_loop_abort_on_exc > 0) {
                /* Tcl_Release(ptr->ip); */
                rbtk_release_ip(ptr);
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
                /* Tcl_Release(ptr->ip); */
                rbtk_release_ip(ptr);
                return rb_tainted_str_new2("");
            }
        } else {
#if TCL_MAJOR_VERSION >= 8
            Tcl_Obj **unknown_objv;
#else
            char **unknown_argv;
#endif
            DUMP1("find 'unknown' command -> set arguemnts");
            unknown_flag = 1;

#if TCL_MAJOR_VERSION >= 8
            unknown_objv = (Tcl_Obj **)ALLOC_N(Tcl_Obj *, objc+2);
            unknown_objv[0] = Tcl_NewStringObj("::unknown", 9);
            Tcl_IncrRefCount(unknown_objv[0]);
            memcpy(unknown_objv + 1, objv, sizeof(Tcl_Obj *)*objc);
            unknown_objv[++objc] = (Tcl_Obj*)NULL;
            objv = unknown_objv;
#else
            unknown_argv = (char **)ALLOC_N(char *, argc+2);
            unknown_argv[0] = strdup("unknown");
            memcpy(unknown_argv + 1, argv, sizeof(char *)*argc);
            unknown_argv[++argc] = (char *)NULL;
            argv = unknown_argv;
#endif
        }
    }
    DUMP1("end Tcl_GetCommandInfo");

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;


#if 1 /* wrap tcl-proc call */
    /* setup params */
    inf.ptr = ptr;
    inf.cmdinfo = info;
#if TCL_MAJOR_VERSION >= 8
    inf.objc = objc;
    inf.objv = objv;
#else
    inf.argc = argc;
    inf.argv = argv;
#endif

    /* invoke tcl-proc */
    ret = rb_protect(invoke_tcl_proc, (VALUE)&inf, &status);
    switch(status) {
    case TAG_RAISE:
        if (NIL_P(ruby_errinfo)) {
            rbtk_pending_exception = rb_exc_new2(rb_eException, 
                                                 "unknown exception");
        } else {
            rbtk_pending_exception = ruby_errinfo;
        }
        break;
        
    case TAG_FATAL:
        if (NIL_P(ruby_errinfo)) {
            rbtk_pending_exception = rb_exc_new2(rb_eFatal, "FATAL");
        } else {
            rbtk_pending_exception = ruby_errinfo;
        }
    }

#else /* !wrap tcl-proc call */

    /* memory allocation for arguments of this command */
#if TCL_MAJOR_VERSION >= 8
    if (!info.isNativeObjectProc) {
        int i;

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
#endif /* ! wrap tcl-proc call */

    /* free allocated memory for calling 'unknown' command */
    if (unknown_flag) {
#if TCL_MAJOR_VERSION >= 8
        Tcl_DecrRefCount(objv[0]);
        free(objv);
#else
        free(argv[0]);
        free(argv);
#endif
    }

    /* exception on mainloop */
    if (pending_exception_check1(thr_crit_bup, ptr)) {
        return rbtk_pending_exception;
    }

    rb_thread_critical = thr_crit_bup;

    if (ptr->return_value == TCL_ERROR) {
        if (event_loop_abort_on_exc > 0 && !Tcl_InterpDeleted(ptr->ip)) {

            return create_ip_exc(interp, rb_eRuntimeError, 
                                 "%s", Tcl_GetStringResult(ptr->ip));
        } else {
            if (event_loop_abort_on_exc < 0) {
                rb_warning("%s (ignore)", Tcl_GetStringResult(ptr->ip));
            } else {
                rb_warn("%s (ignore)", Tcl_GetStringResult(ptr->ip));
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
    int thr_crit_bup;

#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **av;
#else /* TCL_MAJOR_VERSION < 8 */
    char **av;
#endif

    thr_crit_bup = rb_thread_critical;
    rb_thread_critical = Qtrue;

    /* memory allocation */
#if TCL_MAJOR_VERSION >= 8
    av = ALLOC_N(Tcl_Obj *, argc+1);
    for (i = 0; i < argc; ++i) {
        av[i] = get_obj_from_str(argv[i]);
        Tcl_IncrRefCount(av[i]);
    }
    av[argc] = NULL;

#else /* TCL_MAJOR_VERSION < 8 */
    /* string interface */
    av = ALLOC_N(char *, argc+1);
    for (i = 0; i < argc; ++i) {
        av[i] = strdup(StringValuePtr(argv[i]));
    }
    av[argc] = NULL;
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

#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **av = (Tcl_Obj **)NULL;
#else /* TCL_MAJOR_VERSION < 8 */
    char **av = (char **)NULL;
#endif

    DUMP2("invoke_real called by thread:%lx", rb_thread_current());

    /* get the data struct */
    ptr = get_ip(interp);

    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        return rb_tainted_str_new2("");
    }

    /* allocate memory for arguments */
    av = alloc_invoke_arguments(argc, argv);

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
    if (RTEST(rb_funcall(q->thread, ID_alive_p, 0, 0))) {
      DUMP2("back to caller (caller thread:%lx)", q->thread);
      DUMP2("               (current thread:%lx)", rb_thread_current());
      rb_thread_run(q->thread);
      DUMP1("finish back to caller");
    } else {
      DUMP2("caller is dead (caller thread:%lx)", q->thread);
      DUMP2("               (current thread:%lx)", rb_thread_current());
    }

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
    if (NIL_P(eventloop_thread) || current == eventloop_thread) {
        if (NIL_P(eventloop_thread)) {
            DUMP2("invoke from thread:%lx but no eventloop", current);
        } else {
            DUMP2("invoke from current eventloop %lx", current);
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
    if (deleted_ip(ptr)) {
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
    /* POTENTIALY INSECURE : can create infinite loop */
    rb_secure(4);
    return ip_invoke_with_position(argc, argv, obj, TCL_QUEUE_HEAD);
}


/* access Tcl variables */
static VALUE
ip_get_variable2_core(interp, argc, argv)
    VALUE interp;
    int   argc;
    VALUE *argv;
{
    struct tcltkip *ptr = get_ip(interp);
    int thr_crit_bup;
    volatile VALUE varname, index, flag;

    varname = argv[0];
    index   = argv[1];
    flag    = argv[2];

    /* 
    StringValue(varname);
    if (!NIL_P(index)) StringValue(index);
    */

#if TCL_MAJOR_VERSION >= 8
    {
        Tcl_Obj *ret;
        volatile VALUE strval;

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        /* ip is deleted? */
        if (deleted_ip(ptr)) {
            rb_thread_critical = thr_crit_bup;
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_GetVar2Ex(ptr->ip, RSTRING(varname)->ptr,
                                NIL_P(index) ? NULL : RSTRING(index)->ptr,
                                FIX2INT(flag));
        }

        if (ret == (Tcl_Obj*)NULL) {
            volatile VALUE exc;
            /* exc = rb_exc_new2(rb_eRuntimeError, 
                                 Tcl_GetStringResult(ptr->ip)); */
            exc = create_ip_exc(interp, rb_eRuntimeError, 
                                Tcl_GetStringResult(ptr->ip));
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            return exc;
        }

        Tcl_IncrRefCount(ret);
        strval = get_str_from_obj(ret);
        OBJ_TAINT(strval);
        Tcl_DecrRefCount(ret);

        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;
        return(strval);
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        char *ret;
        volatile VALUE strval;

        /* ip is deleted? */
        if (deleted_ip(ptr)) {
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_GetVar2(ptr->ip, RSTRING(varname)->ptr, 
                              NIL_P(index) ? NULL : RSTRING(index)->ptr,
                              FIX2INT(flag));
        }

        if (ret == (char*)NULL) {
            volatile VALUE exc;
            exc = rb_exc_new2(rb_eRuntimeError, Tcl_GetStringResult(ptr->ip));
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            return exc;
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
ip_get_variable2(self, varname, index, flag)
    VALUE self;
    VALUE varname;
    VALUE index;
    VALUE flag;
{
    VALUE argv[3];
    VALUE retval;

    StringValue(varname);
    if (!NIL_P(index)) StringValue(index);

    argv[0] = varname;
    argv[1] = index;
    argv[2] = flag;

    retval = tk_funcall(ip_get_variable2_core, 3, argv, self);

    if (NIL_P(retval)) {
        return rb_tainted_str_new2("");
    } else {
        return retval;
    }
}

static VALUE
ip_get_variable(self, varname, flag)
    VALUE self;
    VALUE varname;
    VALUE flag;
{
    return ip_get_variable2(self, varname, Qnil, flag);
}

static VALUE
ip_set_variable2_core(interp, argc, argv)
    VALUE interp;
    int   argc;
    VALUE *argv;
{
    struct tcltkip *ptr = get_ip(interp);
    int thr_crit_bup;
    volatile VALUE varname, index, value, flag;

    varname = argv[0];
    index   = argv[1];
    value   = argv[2];
    flag    = argv[3];

    /*
    StringValue(varname);
    if (!NIL_P(index)) StringValue(index);
    StringValue(value);
    */

#if TCL_MAJOR_VERSION >= 8
    {
        Tcl_Obj *valobj, *ret;
        volatile VALUE strval;

        thr_crit_bup = rb_thread_critical;
        rb_thread_critical = Qtrue;

        valobj = get_obj_from_str(value);
        Tcl_IncrRefCount(valobj);

        /* ip is deleted? */
        if (deleted_ip(ptr)) {
            Tcl_DecrRefCount(valobj);
            rb_thread_critical = thr_crit_bup;
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_SetVar2Ex(ptr->ip, RSTRING(varname)->ptr,
                                NIL_P(index) ? NULL : RSTRING(index)->ptr,
                                valobj, FIX2INT(flag));
        }

        Tcl_DecrRefCount(valobj);

        if (ret == (Tcl_Obj*)NULL) {
            volatile VALUE exc;
            /* exc = rb_exc_new2(rb_eRuntimeError, 
                                 Tcl_GetStringResult(ptr->ip)); */
            exc = create_ip_exc(interp, rb_eRuntimeError, 
                                Tcl_GetStringResult(ptr->ip));
            /* Tcl_Release(ptr->ip); */
            rbtk_release_ip(ptr);
            rb_thread_critical = thr_crit_bup;
            return exc;
        }

        Tcl_IncrRefCount(ret);
        strval = get_str_from_obj(ret);
        OBJ_TAINT(strval);
        Tcl_DecrRefCount(ret);

        /* Tcl_Release(ptr->ip); */
        rbtk_release_ip(ptr);
        rb_thread_critical = thr_crit_bup;

        return(strval);
    }
#else /* TCL_MAJOR_VERSION < 8 */
    {
        CONST char *ret;
        volatile VALUE strval;

        /* ip is deleted? */
        if (deleted_ip(ptr)) {
            return rb_tainted_str_new2("");
        } else {
            /* Tcl_Preserve(ptr->ip); */
            rbtk_preserve_ip(ptr);
            ret = Tcl_SetVar2(ptr->ip, RSTRING(varname)->ptr, 
                              NIL_P(index) ? NULL : RSTRING(index)->ptr, 
                              RSTRING(value)->ptr, FIX2INT(flag));
        }

        if (ret == (char*)NULL) {
            return rb_exc_new2(rb_eRuntimeError, ptr->ip->result);
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
ip_set_variable2(self, varname, index, value, flag)
    VALUE self;
    VALUE varname;
    VALUE index;
    VALUE value;
    VALUE flag;
{
    VALUE argv[4];
    VALUE retval;

    StringValue(varname);
    if (!NIL_P(index)) StringValue(index);
    StringValue(value);

    argv[0] = varname;
    argv[1] = index;
    argv[2] = value;
    argv[3] = flag;

    retval = tk_funcall(ip_set_variable2_core, 4, argv, self);

    if (NIL_P(retval)) {
        return rb_tainted_str_new2("");
    } else {
        return retval;
    }
}

static VALUE
ip_set_variable(self, varname, value, flag)
    VALUE self;
    VALUE varname;
    VALUE value;
    VALUE flag;
{
    return ip_set_variable2(self, varname, Qnil, value, flag);
}

static VALUE
ip_unset_variable2_core(interp, argc, argv)
    VALUE interp;
    int   argc;
    VALUE *argv;
{
    struct tcltkip *ptr = get_ip(interp);
    volatile VALUE varname, index, flag;

    varname = argv[0];
    index   = argv[1];
    flag    = argv[2];

    /* 
    StringValue(varname);
    if (!NIL_P(index)) StringValue(index);
    */

    /* ip is deleted? */
    if (deleted_ip(ptr)) {
        return Qtrue;
    }

    ptr->return_value = Tcl_UnsetVar2(ptr->ip, RSTRING(varname)->ptr, 
                                      NIL_P(index) ? NULL : RSTRING(index)->ptr,
                                      FIX2INT(flag));

    if (ptr->return_value == TCL_ERROR) {
        if (FIX2INT(flag) & TCL_LEAVE_ERR_MSG) {
            /* return rb_exc_new2(rb_eRuntimeError, 
                                  Tcl_GetStringResult(ptr->ip)); */
            return create_ip_exc(interp, rb_eRuntimeError, 
                                 Tcl_GetStringResult(ptr->ip));
        }
        return Qfalse;
    }
    return Qtrue;
}

static VALUE
ip_unset_variable2(self, varname, index, flag)
    VALUE self;
    VALUE varname;
    VALUE index;
    VALUE flag;
{
    VALUE argv[3];
    VALUE retval;

    StringValue(varname);
    if (!NIL_P(index)) StringValue(index);

    argv[0] = varname;
    argv[1] = index;
    argv[2] = flag;

    retval = tk_funcall(ip_unset_variable2_core, 3, argv, self);

    if (NIL_P(retval)) {
        return rb_tainted_str_new2("");
    } else {
        return retval;
    }
}

static VALUE
ip_unset_variable(self, varname, flag)
    VALUE self;
    VALUE varname;
    VALUE flag;
{
    return ip_unset_variable2(self, varname, Qnil, flag);
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

    tcl_stubs_check();

    if (NIL_P(ip_obj)) {
        interp = (Tcl_Interp *)NULL;
    } else if (get_ip(ip_obj) == (struct tcltkip *)NULL) {
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

        listobj = get_obj_from_str(list_str);

        Tcl_IncrRefCount(listobj);

        result = Tcl_ListObjGetElements(interp, listobj, &objc, &objv);

        if (result == TCL_ERROR) {
            Tcl_DecrRefCount(listobj);
            if (interp == (Tcl_Interp*)NULL) {
                rb_raise(rb_eRuntimeError, "can't get elements from list");
            } else {
                rb_raise(rb_eRuntimeError, "%s", Tcl_GetStringResult(interp));
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
            elem = get_str_from_obj(objv[idx]);
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
                rb_raise(rb_eRuntimeError, "can't get elements from list");
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

    tcl_stubs_check();

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

    tcl_stubs_check();

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

/*###############################################*/

/*
 *   The following is based on tkMenu.[ch] 
 *   of Tcl/Tk (>=8.0) source code.
 */
#if TCL_MAJOR_VERSION >= 8

#define MASTER_MENU             0
#define TEAROFF_MENU            1
#define MENUBAR                 2

struct dummy_TkMenuEntry {
    int type;
    struct dummy_TkMenu *menuPtr;
    /* , and etc.   */
};

struct dummy_TkMenu {
    Tk_Window tkwin;
    Display *display;
    Tcl_Interp *interp;
    Tcl_Command widgetCmd;
    struct dummy_TkMenuEntry **entries;
    int numEntries;
    int active;
    int menuType;     /* MASTER_MENU, TEAROFF_MENU, or MENUBAR */
    Tcl_Obj *menuTypePtr;
    /* , and etc.   */
};

struct dummy_TkMenuRef {
    struct dummy_TkMenu *menuPtr;
    char *dummy1;
    char *dummy2;
    char *dummy3;
};

EXTERN struct dummy_TkMenuRef *TkFindMenuReferences(Tcl_Interp*, char*);

#endif

static VALUE
ip_make_menu_embeddable(interp, menu_path)
    VALUE interp;
    VALUE menu_path;
{
#if TCL_MAJOR_VERSION >= 8
    struct tcltkip *ptr = get_ip(interp);
    struct dummy_TkMenuRef *menuRefPtr;

    StringValue(menu_path);

    menuRefPtr = TkFindMenuReferences(ptr->ip, RSTRING(menu_path)->ptr);
    if (menuRefPtr == (struct dummy_TkMenuRef *) NULL) {
        rb_raise(rb_eArgError, "not a menu widget, or invalid widget path");
    }

    if (menuRefPtr->menuPtr == (struct dummy_TkMenu *) NULL) {
        rb_raise(rb_eRuntimeError, 
		 "invalid menu widget (maybe already destroyed)");
    }

    if ((menuRefPtr->menuPtr)->menuType != MENUBAR) {
        rb_raise(rb_eRuntimeError, 
		 "target menu widget must be a MENUBAR type");
    }

    (menuRefPtr->menuPtr)->menuType = TEAROFF_MENU;
#if 0  /* cause SEGV */
    {
       /* char *s = "tearoff"; */
       char *s = "normal";
       /* Tcl_SetStringObj((menuRefPtr->menuPtr)->menuTypePtr, s, strlen(s));*/
       (menuRefPtr->menuPtr)->menuTypePtr = Tcl_NewStringObj(s, strlen(s));
       /* (menuRefPtr->menuPtr)->menuType = TEAROFF_MENU; */
       (menuRefPtr->menuPtr)->menuType = MASTER_MENU;
    }
#endif

    TkEventuallyRecomputeMenu(menuRefPtr->menuPtr);
    TkEventuallyRedrawMenu(menuRefPtr->menuPtr, 
			   (struct dummy_TkMenuEntry *)NULL);

#else /* TCL_MAJOR_VERSION <= 7 */
    rb_notimplement();
#endif

    return interp;
}

/*###############################################*/

/*---- initialization ----*/
void
Init_tcltklib()
{
    int  ret;

    VALUE lib = rb_define_module("TclTkLib");
    VALUE ip = rb_define_class("TclTkIp", rb_cObject);

    VALUE ev_flag = rb_define_module_under(lib, "EventFlag");
    VALUE var_flag = rb_define_module_under(lib, "VarAccessFlag");

    /* --------------------------------------------------------------- */

    tcltkip_class = ip;

    /* --------------------------------------------------------------- */

    rb_global_variable(&eTkCallbackReturn);
    rb_global_variable(&eTkCallbackBreak);
    rb_global_variable(&eTkCallbackContinue);

    rb_global_variable(&eventloop_thread);
    rb_global_variable(&eventloop_stack);
    rb_global_variable(&watchdog_thread);

    rb_global_variable(&rbtk_pending_exception);

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

    eTkCallbackReturn = rb_define_class("TkCallbackReturn", rb_eStandardError);
    eTkCallbackBreak = rb_define_class("TkCallbackBreak", rb_eStandardError);
    eTkCallbackContinue = rb_define_class("TkCallbackContinue",
                                          rb_eStandardError);

    /* --------------------------------------------------------------- */

    eLocalJumpError = rb_const_get(rb_cObject, rb_intern("LocalJumpError"));

    eTkLocalJumpError = rb_define_class("TkLocalJumpError", eLocalJumpError);

    eTkCallbackRetry  = rb_define_class("TkCallbackRetry", eTkLocalJumpError);
    eTkCallbackRedo   = rb_define_class("TkCallbackRedo",  eTkLocalJumpError);
    eTkCallbackThrow  = rb_define_class("TkCallbackThrow", eTkLocalJumpError);

    /* --------------------------------------------------------------- */

    ID_at_enc = rb_intern("@encoding");
    ID_at_interp = rb_intern("@interp");

    ID_stop_p = rb_intern("stop?");
    ID_alive_p = rb_intern("alive?");
    ID_kill = rb_intern("kill");
    ID_join = rb_intern("join");
    ID_value = rb_intern("value");

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
    rb_define_module_function(lib, "mainloop_thread?", 
                              lib_evloop_thread_p, 0);
    rb_define_module_function(lib, "mainloop_watchdog", 
                              lib_mainloop_watchdog, -1);
    rb_define_module_function(lib, "do_thread_callback", 
                              lib_thread_callback, -1);
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

    rb_define_module_function(lib, "encoding_system", 
                              lib_get_system_encoding, 0);
    rb_define_module_function(lib, "encoding_system=", 
                              lib_set_system_encoding, 1);
    rb_define_module_function(lib, "encoding", 
                              lib_get_system_encoding, 0);
    rb_define_module_function(lib, "encoding=", 
                              lib_set_system_encoding, 1);

    /* --------------------------------------------------------------- */

    rb_define_alloc_func(ip, ip_alloc);
    rb_define_method(ip, "initialize", ip_init, -1);
    rb_define_method(ip, "create_slave", ip_create_slave, -1);
    rb_define_method(ip, "slave_of?", ip_is_slave_of_p, 1);
    rb_define_method(ip, "make_safe", ip_make_safe, 0);
    rb_define_method(ip, "safe?", ip_is_safe_p, 0);
    rb_define_method(ip, "allow_ruby_exit?", ip_allow_ruby_exit_p, 0);
    rb_define_method(ip, "allow_ruby_exit=", ip_allow_ruby_exit_set, 1);
    rb_define_method(ip, "delete", ip_delete, 0);
    rb_define_method(ip, "deleted?", ip_is_deleted_p, 0);
    rb_define_method(ip, "has_mainwindow?", ip_has_mainwindow_p, 0);
    rb_define_method(ip, "invalid_namespace?", ip_has_invalid_namespace_p, 0);
    rb_define_method(ip, "_eval", ip_eval, 1);
    rb_define_method(ip, "_toUTF8", ip_toUTF8, -1);
    rb_define_method(ip, "_fromUTF8", ip_fromUTF8, -1);
    rb_define_method(ip, "_thread_vwait", ip_thread_vwait, 1);
    rb_define_method(ip, "_thread_tkwait", ip_thread_tkwait, 2);
    rb_define_method(ip, "_invoke", ip_invoke, -1);
    rb_define_method(ip, "_immediate_invoke", ip_invoke_immediate, -1);
    rb_define_method(ip, "_return_value", ip_retval, 0);

    rb_define_method(ip, "_create_console", ip_create_console, 0);

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

    rb_define_method(ip, "_make_menu_embeddable", ip_make_menu_embeddable, 1);

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

    eventloop_thread = Qnil;

#ifndef DEFAULT_EVENTLOOP_DEPTH
#define DEFAULT_EVENTLOOP_DEPTH 7
#endif 
    eventloop_stack = rb_ary_new2(DEFAULT_EVENTLOOP_DEPTH);
    OBJ_TAINT(eventloop_stack);

    watchdog_thread  = Qnil;

    rbtk_pending_exception = Qnil;

    /* --------------------------------------------------------------- */

    /* if ruby->nativethread-supprt and tcltklib->doen't, 
       the following will cause link-error. */
    is_ruby_native_thread();

    /* --------------------------------------------------------------- */

    rb_set_end_proc(lib_mark_at_exit, 0);

    /* --------------------------------------------------------------- */

    ret = ruby_open_tcl_dll(rb_argv0 ? RSTRING(rb_argv0)->ptr : 0);
    switch(ret) {
    case TCLTK_STUBS_OK:
        break;
    case NO_TCL_DLL:
        rb_raise(rb_eLoadError, "tcltklib: fail to open tcl_dll");
    case NO_FindExecutable:
        rb_raise(rb_eLoadError, "tcltklib: can't find Tcl_FindExecutable");
    default:
        rb_raise(rb_eLoadError, "tcltklib: unknown error(%d) on ruby_open_tcl_dll", ret);
    }

    /* --------------------------------------------------------------- */
}

/* eof */
