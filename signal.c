/************************************************

  signal.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:53 $
  created at: Tue Dec 20 10:13:44 JST 1994

************************************************/

#include "ruby.h"
#include "sig.h"
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
f_kill(argc, argv)
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
    if (sig >= NSIG ||(sig != SIGINT && trap_list[sig] == Qnil))
	Fail("trap_handler: Bad signal %d", sig);

#ifndef HAVE_BSD_SIGNALS
    signal(sig, sighandle);
#endif

#ifdef SAFE_SIGHANDLE
    if (trap_immediate) {
	if (sig == SIGINT && !trap_list[sig]) Fail("Interrupt");
	rb_trap_eval(trap_list[sig], sig);
    }
    else {
	trap_pending++;
	trap_pending_list[sig]++;
    }
#else
    if (sig == SIGINT && !trap_list[sig]) Fail("Interrupt");
    rb_trap_eval(trap_list[sig], sig);
#endif
}

void
rb_trap_exit()
{
    if (trap_list[0])
	rb_trap_eval(trap_list[0], 0);
}

#ifdef SAFE_SIGHANDLE
void
rb_trap_exec()
{
    int i;

    for (i=0; i<NSIG; i++) {
	if (trap_pending_list[i]) {
	    trap_pending_list[i] = 0;
	    if (i == SIGINT && trap_list[SIGINT] == 0)
		Fail("Interrupt");
	    rb_trap_eval(trap_list[i], i);
	}
    }
    trap_pending = 0;
}
#endif

struct trap_arg {
#ifndef NT
# ifdef HAVE_SIGPROCMASK
    sigset_t mask;
# else
    int mask;
# endif
#endif
    VALUE sig, cmd;
};

static RETSIGTYPE
sigexit()
{
    rb_exit(1);
}

static VALUE
trap(arg)
    struct trap_arg *arg;
{
    RETSIGTYPE (*func)();
    VALUE command;
    int i, sig;

    func = sighandle;
    command = arg->cmd;
    if (command == Qnil) {
	func = SIG_IGN;
    }
    else if (TYPE(command) == T_STRING) {
	if (RSTRING(command)->len == 0) {
	    func = SIG_IGN;
	}
	else if (RSTRING(command)->len == 7) {
	    if (strncmp(RSTRING(command)->ptr, "SIG_IGN", 7) == 0) {
		func = SIG_IGN;
	    }
	    else if (strncmp(RSTRING(command)->ptr, "SIG_DFL", 7) == 0) {
		func = SIG_DFL;
	    }
	    else if (strncmp(RSTRING(command)->ptr, "DEFAULT", 7) == 0) {
		func = SIG_DFL;
	    }
	}
	else if (RSTRING(command)->len == 6) {
	    if (strncmp(RSTRING(command)->ptr, "IGNORE", 6) == 0) {
		func = SIG_IGN;
	    }
	}
	else if (RSTRING(command)->len == 4) {
	    if (strncmp(RSTRING(command)->ptr, "EXIT", 4) == 0) {
		func = sigexit;
	    }
	}
    }
    if (func == SIG_IGN || func == SIG_DFL) {
	command = Qnil;
    }

    if (TYPE(arg->sig) == T_STRING) {
	char *s = RSTRING(arg->sig)->ptr;

	if (strncmp("SIG", s, 3) == 0)
	    s += 3;
	sig = signm2signo(s);
	if (sig == 0 && strcmp(s, "EXIT") != 0)
	    Fail("Invalid signal SIG%s", s);
    }
    else {
	sig = NUM2INT(arg->sig);
    }
    if (sig < 0 || sig > NSIG) {
	Fail("Invalid signal no %d", sig);
    }
    signal(sig, func);
    trap_list[sig] = command;
    /* enable at least specified signal. */
#ifdef HAVE_SIGPROCMASK
    sigdelset(&arg->mask, sig);
#else
    arg->mask &= ~sigmask(sig);
#endif
    return Qnil;
}

#ifndef NT
static void
trap_ensure(arg)
    struct trap_arg *arg;
{
    /* enable interrupt */
#ifdef HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &arg->mask, NULL);
#else
    sigsetmask(arg->mask);
#endif
}
#endif

static VALUE
f_trap(argc, argv)
    int argc;
    VALUE *argv;
{
    struct trap_arg arg;

    if (argc == 0 || argc > 2) {
	Fail("wrong # of arguments -- trap(sig, cmd)/trap(sig){...}");
    }

    arg.sig = argv[0];
    if (argc == 1) {
	arg.cmd = f_lambda();
    }
    else if (argc == 2) {
	arg.cmd = argv[1];
    }

#ifndef NT
    /* disable interrupt */
# ifdef HAVE_SIGPROCMASK
    sigfillset(&arg.mask);
    sigprocmask(SIG_BLOCK, &arg.mask, &arg.mask);
# else
    arg.mask = sigblock(~0);
# endif

    return rb_ensure(trap, &arg, trap_ensure, &arg);
#else
    return trap(&arg);
#endif
}

SIGHANDLE
sig_beg()
{
    if (!trap_list[SIGINT]) {
	return signal(SIGINT, sighandle);
    }
    return 0;
}

void
sig_end(handle)
    SIGHANDLE handle;
{
    if (!trap_list[SIGINT]) {
	signal(SIGINT, handle);
    }
}

void
Init_signal()
{
    extern VALUE cKernel;

    rb_define_method(cKernel, "kill", f_kill, -1);
    rb_define_method(cKernel, "trap", f_trap, -1);
}
