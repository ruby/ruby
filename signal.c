/************************************************

  signal.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:53 $
  created at: Tue Dec 20 10:13:44 JST 1994

************************************************/

#include "ruby.h"
#include <signal.h>
#include <stdio.h>

static struct signals {
    char *signm;
    int  signo;
} siglist [] = {
#ifdef SIGHUP
    "HUP", SIGHUP,
#endif
#ifdef SIGINT
    "INT", SIGINT,
#endif
#ifdef SIGQUIT
    "QUIT", SIGQUIT,
#endif
#ifdef SIGILL
    "ILL", SIGILL,
#endif
#ifdef SIGTRAP
    "TRAP", SIGTRAP,
#endif
#ifdef SIGIOT
    "IOT", SIGIOT,
#endif
#ifdef SIGABRT
    "ABRT", SIGABRT,
#endif
#ifdef SIGEMT
    "EMT", SIGEMT,
#endif
#ifdef SIGFPE
    "FPE", SIGFPE,
#endif
#ifdef SIGKILL
    "KILL", SIGKILL,
#endif
#ifdef SIGBUS
    "BUS", SIGBUS,
#endif
#ifdef SIGSEGV
    "SEGV", SIGSEGV,
#endif
#ifdef SIGSYS
    "SYS", SIGSYS,
#endif
#ifdef SIGPIPE
    "PIPE", SIGPIPE,
#endif
#ifdef SIGALRM
    "ALRM", SIGALRM,
#endif
#ifdef SIGTERM
    "TERM", SIGTERM,
#endif
#ifdef SIGURG
    "URG", SIGURG,
#endif
#ifdef SIGSTOP
    "STOP", SIGSTOP,
#endif
#ifdef SIGTSTP
    "TSTP", SIGTSTP,
#endif
#ifdef SIGCONT
    "CONT", SIGCONT,
#endif
#ifdef SIGCHLD
    "CHLD", SIGCHLD,
#endif
#ifdef SIGCLD
    "CLD", SIGCLD,
#else
# ifdef SIGCHLD
    "CLD", SIGCHLD,
# endif
#endif
#ifdef SIGTTIN
    "TTIN", SIGTTIN,
#endif
#ifdef SIGTTOU
    "TTOU", SIGTTOU,
#endif
#ifdef SIGIO
    "IO", SIGIO,
#endif
#ifdef SIGXCPU
    "XCPU", SIGXCPU,
#endif
#ifdef SIGXFSZ
    "XFSZ", SIGXFSZ,
#endif
#ifdef SIGVTALRM
    "VTALRM", SIGVTALRM,
#endif
#ifdef SIGPROF
    "PROF", SIGPROF,
#endif
#ifdef SIGWINCH
    "WINCH", SIGWINCH,
#endif
#ifdef SIGUSR1
    "USR1", SIGUSR1,
#endif
#ifdef SIGUSR2
    "USR2", SIGUSR2,
#endif
#ifdef SIGLOST
    "LOST", SIGLOST,
#endif
#ifdef SIGMSG
    "MSG", SIGMSG,
#endif
#ifdef SIGPWR
    "PWR", SIGPWR,
#endif
#ifdef SIGPOLL
    "POLL", SIGPOLL,
#endif
#ifdef SIGDANGER
    "DANGER", SIGDANGER,
#endif
#ifdef SIGMIGRATE
    "MIGRATE", SIGMIGRATE,
#endif
#ifdef SIGPRE
    "PRE", SIGPRE,
#endif
#ifdef SIGGRANT
    "GRANT", SIGGRANT,
#endif
#ifdef SIGRETRACT
    "RETRACT", SIGRETRACT,
#endif
#ifdef SIGSOUND
    "SOUND", SIGSOUND,
#endif
    NULL, 0,
};

static int
signm2signo(nm)
    char *nm;
{
    struct signals *sigs;

    for (sigs = siglist; sigs->signm; sigs++)
	if (strcmp(sigs->signm, nm) == 0)
	    return sigs->signo;
    return 0;
}

VALUE
Fkill(argc, argv)
    int argc;
    VALUE *argv;
{
    int sig;
    int i;
    char *s;

    if (argc < 2)
	Fail("wrong # of arguments -- kill(sig, pid...)");
    switch (TYPE(argv[0])) {
      case T_FIXNUM:
	sig = FIX2UINT(argv[0]);
	if (sig >= NSIG) {
	    s = rb_id2name(sig);
	    if (!s) Fail("Bad signal");
	    goto str_signal;
	}
	break;

      case T_STRING:
	{
	    int negative = 0;

	    s = RSTRING(argv[0])->ptr;
	    if (s[0] == '-') {
		negative++;
		s++;
	    }
	  str_signal:
	    if (strncmp("SIG", s, 3) == 0)
		s += 3;
	    if((sig = signm2signo(s)) == 0)
		Fail("Unrecognized signal name `%s'", s);

	    if (negative)
		sig = -sig;
	}
	break;

      default:
	Fail("bad signal type %s", rb_class2name(CLASS_OF(argv[0])));
	break;
    }

    if (sig < 0) {
	sig = -sig;
	for (i=1; i<argc; i++) {
	    int pid = NUM2INT(argv[i]);
#ifdef HAS_KILLPG
	    if (killpg(pid, sig) < 0)
#else
	    if (kill(-pid, sig) < 0)
#endif
		rb_sys_fail(Qnil);
	}
    }
    else {
	for (i=1; i<argc; i++) {
	    Check_Type(argv[i], T_FIXNUM);
	    if (kill(FIX2UINT(argv[i]), sig) < 0)
		rb_sys_fail(Qnil);
	}
    }
    return INT2FIX(i-1);
}

static VALUE trap_list[NSIG];
#ifdef SAFE_SIGHANDLE
static int trap_pending_list[NSIG];
int trap_pending;
int trap_immediate;
#endif

void
gc_mark_trap_list()
{
    int i;

    for (i=0; i<NSIG; i++) {
	if (trap_list[i])
	    gc_mark(trap_list[i]);
    }
}

static RETSIGTYPE
sighandle(sig)
    int sig;
{
    if (sig >= NSIG || trap_list[sig] == Qnil)
	Fail("trap_handler: Bad signal %d", sig);

#ifndef HAVE_BSD_SIGNALS
    signal(sig, sighandle);
#endif

#ifdef SAFE_SIGHANDLE
    if (trap_immediate) {
	rb_trap_eval(trap_list[sig]);
    }
    else {
	trap_pending++;
	trap_pending_list[sig]++;
    }
#else
    rb_trap_eval(trap_list[sig]);
#endif
}

void
rb_trap_exit()
{
    if (trap_list[0])
	rb_trap_eval(trap_list[0]);
}

#ifdef SAFE_SIGHANDLE
rb_trap_exec()
{
    int i;

    trap_pending = 0;
    for (i=0; i<NSIG; i++) {
	if (trap_pending_list[i]) {
	    trap_pending_list[i] = 0;
	    rb_trap_eval(trap_list[i]);
	}
    }
}
#endif

static VALUE
Ftrap(argc, argv)
    int argc;
    VALUE *argv;
{
    RETSIGTYPE (*func)();
    VALUE command;
    int i, sig;
#ifdef HAVE_SIGPROCMASK
    sigset_t mask;
#else
    int mask;
#endif

    if (argc < 2)
	Fail("wrong # of arguments -- kill(cmd, sig...)");

    /* disable interrupt */
#ifdef HAVE_SIGPROCMASK
    sigfillset(&mask);
    sigprocmask(SIG_BLOCK, &mask, &mask);
#else
    mask = sigblock(~0);
#endif

    func = sighandle;

    if (argv[0] == Qnil) {
	func = SIG_IGN;
	command = Qnil;
    }
    else {
	Check_Type(argv[0], T_STRING);
	command = argv[0];
	if (RSTRING(argv[0])->len == 0) {
	    func = SIG_IGN;
	}
	else if (RSTRING(argv[0])->len == 7) {
	    if (strncmp(RSTRING(argv[0])->ptr, "SIG_IGN", 7) == 0) {
		func = SIG_IGN;
	    }
	    else if (strncmp(RSTRING(argv[0])->ptr, "SIG_DFL", 7) == 0) {
		func = SIG_DFL;
	    }
	    else if (strncmp(RSTRING(argv[0])->ptr, "DEFAULT", 7) == 0) {
		func = SIG_DFL;
	    }
	}
	else if (RSTRING(argv[0])->len == 6) {
	    if (strncmp(RSTRING(argv[0])->ptr, "IGNORE", 6) == 0) {
		func = SIG_IGN;
	    }
	}
    }
    if (func == SIG_IGN || func == SIG_DFL)
	command = Qnil;

    for (i=1; i<argc; i++) {
	if (TYPE(argv[i]) == T_STRING) {
	    char *s = RSTRING(argv[i])->ptr;

	    if (strncmp("SIG", s, 3) == 0)
		s += 3;
	    sig = signm2signo(s);
	    if (sig == 0 && strcmp(s, "EXIT") != 0)
		Fail("Invalid signal SIG%s", s);
	}
	else {
	    sig = NUM2INT(argv[i]);
	}
	if (sig < 0 || sig > NSIG)
	    Fail("Invalid signal no %d", sig);

	signal(sig, sighandle);
	trap_list[sig] = command;
	/* enable at least specified signal. */
#ifdef HAVE_SIGPROCMASK
	sigdelset(&mask, sig);
#else
	mask &= ~sigmask(sig);
#endif
    }
    /* disable interrupt */
#ifdef HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &mask, NULL);
#else
    sigsetmask(mask);
#endif
    return Qnil;
}

Init_signal()
{
    extern VALUE C_Kernel;

    rb_define_method(C_Kernel, "kill", Fkill, -1);
    rb_define_method(C_Kernel, "trap", Ftrap, -1);
}
