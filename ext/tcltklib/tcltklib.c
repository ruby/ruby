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
    int argc;
    VALUE *argv;
    VALUE obj;
    int done;
    VALUE result;
    VALUE thread;
    struct invoke_queue *next;
};
 
static struct invoke_queue *iqueue;
static VALUE main_thread;

/* Tk_ThreadTimer */
static Tcl_TimerToken timer_token;

/* timer callback */
static void
_timer_for_tcl(clientData)
    ClientData clientData;
{
    struct invoke_queue *q, *tmp;
    VALUE thread;

    Tk_DeleteTimerHandler(timer_token);
    timer_token = Tk_CreateTimerHandler(100, _timer_for_tcl, (ClientData)0);

    CHECK_INTS;
    q = iqueue;
    while (q) {
	tmp = q;
	q = q->next;
	if (!tmp->done) {
	    tmp->done = 1;
	    tmp->result = ip_invoke_real(tmp->argc, tmp->argv, tmp->obj);
	    thread = tmp->thread;
	    tmp = tmp->next;
	    rb_thread_run(thread);
	}
    }
    rb_thread_schedule();
}

/* execute Tk_MainLoop */
static VALUE
lib_mainloop(self)
    VALUE self;
{
    timer_token = Tk_CreateTimerHandler(100, _timer_for_tcl, (ClientData)0);
    DUMP1("start Tk_Mainloop");
    Tk_MainLoop();
    DUMP1("stop Tk_Mainloop");
    Tk_DeleteTimerHandler(timer_token);

    return Qnil;
}

/*---- class TclTkIp ----*/
struct tcltkip {
    Tcl_Interp *ip;		/* the interpreter */
    int return_value;		/* return value */
};

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
    struct tcltkip *ptr;	/* tcltkip data struct */

    /* get the data struct */
    Data_Get_Struct(self, struct tcltkip, ptr);

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
    res = rb_rescue(rb_eval_string, (VALUE)arg, ip_eval_rescue, (VALUE)&failed);
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
    Tcl_DeleteInterp(ptr->ip);
    free(ptr);
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
    struct tcltkip *ptr;	/* tcltkip data struct */

    /* get the data struct */
    Data_Get_Struct(self, struct tcltkip, ptr);

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

    Data_Get_Struct(self,struct tcltkip, ptr);
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

    Data_Get_Struct(self,struct tcltkip, ptr);
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
    struct tcltkip *ptr;	/* tcltkip data struct */
    int i;
    Tcl_CmdInfo info;
    char *cmd;
    char **av = (char **)NULL;
#if TCL_MAJOR_VERSION >= 8
    Tcl_Obj **ov = (Tcl_Obj **)NULL;
    Tcl_Obj *resultPtr;
#endif

    /* get the data struct */
    Data_Get_Struct(obj, struct tcltkip, ptr);

    /* get the command name string */
    cmd = STR2CSTR(argv[0]);

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
	    char *s = STR2CSTR(argv[i]);
	    ov[i] = Tcl_NewStringObj(s, strlen(s));
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
	    char *s = STR2CSTR(argv[i]);

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
	ptr->return_value = (*info.proc)(info.clientData,
					 ptr->ip, argc, av);
    }

    if (ptr->return_value == TCL_ERROR) {
	rb_raise(rb_eRuntimeError, "%s", ptr->ip->result);
    }

    /* pass back the result (as string) */
    return rb_str_new2(ptr->ip->result);
}

static VALUE
ip_invoke(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    struct invoke_queue *tmp, *p;
    VALUE result = rb_thread_current();

    if (result == main_thread) {
	return ip_invoke_real(argc, argv, obj);
    }
    tmp = ALLOC(struct invoke_queue);
    tmp->obj = obj;
    tmp->argc = argc;
    tmp->argv = ALLOC_N(VALUE, argc);
    MEMCPY(tmp->argv, argv, VALUE, argc);
    tmp->thread = result;
    tmp->done = 0;

    tmp->next = iqueue;
    iqueue = tmp;

    rb_thread_stop();
    result = tmp->result;
    if (iqueue == tmp) {
	iqueue = tmp->next;
	free(tmp->argv);
	free(tmp);
	return result;
    }

    p = iqueue;
    while (p->next) {
	if (p->next == tmp) {
	    p->next = tmp->next;
	    free(tmp->argv);
	    free(tmp);
	    break;
	}
	p = p->next;
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
    Data_Get_Struct(self, struct tcltkip, ptr);

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

#if defined USE_TCL_STUBS && defined USE_TK_STUBS
    extern int ruby_tcltk_stubs();
    int ret = ruby_tcltk_stubs();
    if (ret)
	rb_raise(rb_eLoadError, "tcltklib: tcltk_stubs init error(%d)", ret);
#endif

    eTkCallbackBreak = rb_define_class("TkCallbackBreak", rb_eStandardError);
    eTkCallbackContinue = rb_define_class("TkCallbackContinue",rb_eStandardError);

    rb_define_module_function(lib, "mainloop", lib_mainloop, 0);

    rb_define_singleton_method(ip, "new", ip_new, 0);
    rb_define_method(ip, "_eval", ip_eval, 1);
    rb_define_method(ip, "_toUTF8",ip_toUTF8,2);
    rb_define_method(ip, "_fromUTF8",ip_fromUTF8,2);
    rb_define_method(ip, "_invoke", ip_invoke, -1);
    rb_define_method(ip, "_return_value", ip_retval, 0);
    rb_define_method(ip, "mainloop", lib_mainloop, 0);
    rb_define_method(ip, "restart", lib_restart, 0);

    main_thread = rb_thread_current();
#ifdef __MACOS__
    _macinit();
#endif

    /*---- initialize tcl/tk libraries ----*/
    /* from Tk_Main() */
    DUMP1("Tcl_FindExecutable");
    Tcl_FindExecutable(RSTRING(rb_argv0)->ptr);
}

/* eof */
