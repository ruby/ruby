/************************************************

  signal.c -

  $Author$
  $Date$
  created at: Tue Dec 20 10:13:44 JST 1994

************************************************/

#include "ruby.h"
#include "sig.h"
#include <signal.h>
#include <stdio.h>

#ifdef __BEOS__
#undef SIGBUS
#endif

#ifndef NSIG
# ifdef DJGPP
#  define NSIG SIGMAX
# else
#  define NSIG (_SIGMAX + 1)      /* For QNX */
# endif
#endif

#ifdef USE_CWGUSI
# undef NSIG
# define NSIG __signal_max
#endif

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
#ifdef USE_CWGUSI
    rb_notimplement();
#else
    int negative = 0;
    int sig;
    int i;
    char *s;

    rb_secure(2);
    if (argc < 2)
	ArgError("wrong # of arguments -- kill(sig, pid...)");
    switch (TYPE(argv[0])) {
      case T_FIXNUM:
	sig = FIX2UINT(argv[0]);
	if (sig >= NSIG) {
	    s = rb_id2name(sig);
	    if (!s) ArgError("Bad signal");
	    goto str_signal;
	}
	break;

      case T_STRING:
        {
	    s = RSTRING(argv[0])->ptr;
	    if (s[0] == '-') {
		negative++;
		s++;
	    }
	  str_signal:
	    if (strncmp("SIG", s, 3) == 0)
		s += 3;
	    if((sig = signm2signo(s)) == 0)
		ArgError("Unrecognized signal name `%s'", s);

	    if (negative)
		sig = -sig;
	}
	break;

      default:
	ArgError("bad signal type %s", rb_class2name(CLASS_OF(argv[0])));
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
		rb_sys_fail(0);
	}
    }
    else {
	for (i=1; i<argc; i++) {
	    Check_Type(argv[i], T_FIXNUM);
	    if (kill(FIX2UINT(argv[i]), sig) < 0)
		rb_sys_fail(0);
	}
    }
    return INT2FIX(i-1);
#endif /* USE_CWGUSI */
}

static VALUE trap_list[NSIG];
static int trap_pending_list[NSIG];
int trap_pending;
int trap_immediate;
int prohibit_interrupt;

void
gc_mark_trap_list()
{
#ifndef MACOS_UNUSE_SIGNAL
    int i;

    for (i=0; i<NSIG; i++) {
	if (trap_list[i])
	    gc_mark(trap_list[i]);
    }
#endif /* MACOS_UNUSE_SIGNAL */
}

#ifdef POSIX_SIGNAL
void
posix_signal(signum, handler)
    int signum;
    RETSIGTYPE (*handler)();
{
    struct sigaction sigact;

    sigact.sa_handler = handler;
    sigemptyset(&sigact.sa_mask);
    sigact.sa_flags = 0;
    sigaction(signum, &sigact, 0);
}
#endif

#ifdef THREAD
# define rb_interrupt thread_interrupt
# define rb_trap_eval thread_trap_eval
#endif

static RETSIGTYPE
sighandle(sig)
    int sig;
{
    if (sig >= NSIG ||(sig != SIGINT && !trap_list[sig]))
	Bug("trap_handler: Bad signal %d", sig);

#if !defined(POSIX_SIGNAL) && !defined(BSD_SIGNAL)
    signal(sig, sighandle);
#endif

    if (trap_immediate) {
	trap_immediate = 0;
	if (sig == SIGINT && !trap_list[SIGINT]) {
	    rb_interrupt();
	}
	rb_trap_eval(trap_list[sig], sig);
	trap_immediate = 1;
    }
    else {
	trap_pending++;
	trap_pending_list[sig]++;
    }
}

#ifdef SIGBUS
static RETSIGTYPE
sigbus(sig)
    int sig;
{
    Bug("Bus Error");
}
#endif

#ifdef SIGSEGV
static RETSIGTYPE
sigsegv(sig)
    int sig;
{
    Bug("Segmentation fault");
}
#endif

void
rb_trap_exit()
{
#ifndef MACOS_UNUSE_SIGNAL
    if (trap_list[0])
	rb_eval_cmd(trap_list[0], ary_new3(1, INT2FIX(0)));
#endif
}

void
rb_trap_exec()
{
#ifndef MACOS_UNUSE_SIGNAL
    int i;

    for (i=0; i<NSIG; i++) {
	if (trap_pending_list[i]) {
	    trap_pending_list[i] = 0;
	    if (i == SIGINT && trap_list[SIGINT] == 0) {
		rb_interrupt();
		return;
	    }
	    rb_trap_eval(trap_list[i], i);
	}
    }
#endif /* MACOS_UNUSE_SIGNAL */
    trap_pending = 0;
}

struct trap_arg {
#if !defined(NT) && !defined(USE_CWGUSI)
# ifdef HAVE_SIGPROCMASK
    sigset_t mask;
# else
    int mask;
# endif
#endif
    VALUE sig, cmd;
};

# ifdef HAVE_SIGPROCMASK
static sigset_t trap_last_mask;
# else
static int trap_last_mask;
# endif

static RETSIGTYPE
sigexit()
{
    rb_exit(0);
}

static VALUE
trap(arg)
    struct trap_arg *arg;
{
    RETSIGTYPE (*func)();
    VALUE command, old;
    int sig;

    func = sighandle;
    command = arg->cmd;
    if (NIL_P(command)) {
	func = SIG_IGN;
    }
    else if (TYPE(command) == T_STRING) {
	Check_SafeStr(command);	/* taint check */
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
	command = 0;
    }

    if (TYPE(arg->sig) == T_STRING) {
	char *s = RSTRING(arg->sig)->ptr;

	if (strncmp("SIG", s, 3) == 0)
	    s += 3;
	sig = signm2signo(s);
	if (sig == 0 && strcmp(s, "EXIT") != 0)
	    ArgError("Invalid signal SIG%s", s);
    }
    else {
	sig = NUM2INT(arg->sig);
    }
    if (sig < 0 || sig > NSIG) {
	ArgError("Invalid signal no %d", sig);
    }
#if defined(THREAD) && defined(HAVE_SETITIMER) && !defined(__BOW__)
    if (sig == SIGVTALRM) {
	ArgError("SIGVTALRM reserved for Thread; cannot set handler");
    }
    if (sig == SIGALRM) {
	ArgError("SIGALRM reserved for Thread; cannot set handler");
    }
#endif
    if (func == SIG_DFL) {
	switch (sig) {
	  case SIGINT:
	    func = sighandle;
	    break;
#ifdef SIGBUS
	  case SIGBUS:
	    func = sigbus;
	    break;
#endif
#ifdef SIGSEGV
	  case SIGSEGV:
	    func = sigsegv;
	    break;
#endif
	}
    }
#ifdef POSIX_SIGNAL
    posix_signal(sig, func);
#else
    signal(sig, func);
#endif
    old = trap_list[sig];
    if (!old) old = Qnil;

    trap_list[sig] = command;
    /* enable at least specified signal. */
#if !defined(NT) && !defined(USE_CWGUSI)
#ifdef HAVE_SIGPROCMASK
    sigdelset(&arg->mask, sig);
#else
    arg->mask &= ~sigmask(sig);
#endif
#endif
    return old;
}

#if !defined(NT) && !defined(USE_CWGUSI)
static VALUE
trap_ensure(arg)
    struct trap_arg *arg;
{
    /* enable interrupt */
#ifdef HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &arg->mask, NULL);
#else
    sigsetmask(arg->mask);
#endif
    trap_last_mask = arg->mask;
    return 0;
}
#endif

void
trap_restore_mask()
{
#ifndef NT
# ifdef HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &trap_last_mask, NULL);
# else
    sigsetmask(trap_last_mask);
# endif
#endif
}

static VALUE
f_trap(argc, argv)
    int argc;
    VALUE *argv;
{
    struct trap_arg arg;

    rb_secure(2);
    if (argc == 0 || argc > 2) {
	ArgError("wrong # of arguments -- trap(sig, cmd)/trap(sig){...}");
    }

    arg.sig = argv[0];
    if (argc == 1) {
	arg.cmd = f_lambda();
    }
    else if (argc == 2) {
	arg.cmd = argv[1];
    }

#if !defined(NT) && !defined(USE_CWGUSI)
    /* disable interrupt */
# ifdef HAVE_SIGPROCMASK
    sigfillset(&arg.mask);
    sigprocmask(SIG_BLOCK, &arg.mask, &arg.mask);
# else
    arg.mask = sigblock(~0);
# endif

    return rb_ensure(trap, (VALUE)&arg, trap_ensure, (VALUE)&arg);
#else
    return trap(&arg);
#endif
}

void
Init_signal()
{
#ifndef MACOS_UNUSE_SIGNAL
    rb_define_global_function("trap", f_trap, -1);
#ifdef POSIX_SIGNAL
    posix_signal(SIGINT, sighandle);
#else
    signal(SIGINT, sighandle);
#endif
#ifdef SIGBUS
    signal(SIGBUS, sigbus);
#endif
#ifdef SIGSEGV
    signal(SIGSEGV, sigsegv);
#endif
#endif /* MACOS_UNUSE_SIGNAL */
}
