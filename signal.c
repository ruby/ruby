/**********************************************************************

  signal.c -

  $Author$
  $Date$
  created at: Tue Dec 20 10:13:44 JST 1994

  Copyright (C) 1993-2000 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "rubysig.h"
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
#ifdef SIGINFO
    "INFO", SIGINFO,
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

static char*
signo2signm(no)
    int no;
{
    struct signals *sigs;

    for (sigs = siglist; sigs->signm; sigs++)
	if (sigs->signo == no)
	    return sigs->signm;
    return 0;
}

VALUE
rb_f_kill(argc, argv)
    int argc;
    VALUE *argv;
{
    int negative = 0;
    int sig;
    int i;
    char *s;

    rb_secure(2);
    if (argc < 2)
	rb_raise(rb_eArgError, "wrong # of arguments -- kill(sig, pid...)");
    switch (TYPE(argv[0])) {
      case T_FIXNUM:
	sig = FIX2INT(argv[0]);
	break;

      case T_SYMBOL:
	s = rb_id2name(SYM2ID(argv[0]));
	if (!s) rb_raise(rb_eArgError, "bad signal");
	goto str_signal;

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
		rb_raise(rb_eArgError, "unrecognized signal name `%s'", s);

	    if (negative)
		sig = -sig;
	}
	break;

      default:
	rb_raise(rb_eArgError, "bad signal type %s",
		 rb_class2name(CLASS_OF(argv[0])));
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
	    if (kill(FIX2INT(argv[i]), sig) < 0)
		rb_sys_fail(0);
	}
    }
    return INT2FIX(i-1);
}

static VALUE trap_list[NSIG];
static rb_atomic_t trap_pending_list[NSIG];
rb_atomic_t rb_trap_pending;
rb_atomic_t rb_trap_immediate;
int rb_prohibit_interrupt;

void
rb_gc_mark_trap_list()
{
#ifndef MACOS_UNUSE_SIGNAL
    int i;

    for (i=0; i<NSIG; i++) {
	if (trap_list[i])
	    rb_gc_mark(trap_list[i]);
    }
#endif /* MACOS_UNUSE_SIGNAL */
}

#ifdef POSIX_SIGNAL
void
posix_signal(signum, handler)
    int signum;
    RETSIGTYPE (*handler)_((int));
{
    struct sigaction sigact;

    sigact.sa_handler = handler;
    sigemptyset(&sigact.sa_mask);
    sigact.sa_flags = 0;
#ifdef SA_RESTART
    sigact.sa_flags |= SA_RESTART; /* SVR4, 4.3+BSD */
#endif
#ifdef SA_NOCLDWAIT
    if (signum == SIGCHLD && handler == SIG_IGN)
	sigact.sa_flags |= SA_NOCLDWAIT;
#endif
    sigaction(signum, &sigact, 0);
}
#define ruby_signal(sig,handle) posix_signal((sig),(handle))
#else
#define ruby_signal(sig,handle) signal((sig),(handle))
#endif

static void signal_exec _((int sig));
static void
signal_exec(sig)
    int sig;
{
    if (trap_list[sig] == 0) {
	switch (sig) {
	  case SIGINT:
	    rb_thread_interrupt();
	    break;
#ifdef SIGHUP
	  case SIGHUP:
#endif
#ifdef SIGQUIT
	  case SIGQUIT:
#endif
#ifdef SIGALRM
	  case SIGALRM:
#endif
#ifdef SIGUSR1
	  case SIGUSR1:
#endif
#ifdef SIGUSR2
	  case SIGUSR2:
#endif
	    rb_thread_signal_raise(signo2signm(sig));
	    break;
	}
    }
    else {
	rb_thread_trap_eval(trap_list[sig], sig);
    }
}

static RETSIGTYPE sighandle _((int));
static RETSIGTYPE
sighandle(sig)
    int sig;
{
#ifdef NT
#define IN_MAIN_CONTEXT(f, a) (win32_main_context(a, f) ? (void)0 : f(a))
#else
#define IN_MAIN_CONTEXT(f, a) f(a)
#endif

    if (sig >= NSIG) {
	rb_bug("trap_handler: Bad signal %d", sig);
    }

#if !defined(BSD_SIGNAL) && !defined(POSIX_SIGNAL)
    ruby_signal(sig, sighandle);
#endif

    if (ATOMIC_TEST(rb_trap_immediate)) {
	IN_MAIN_CONTEXT(signal_exec, sig);
	ATOMIC_SET(rb_trap_immediate, 1);
    }
    else {
	ATOMIC_INC(rb_trap_pending);
	ATOMIC_INC(trap_pending_list[sig]);
    }
}

#ifdef SIGBUS
static RETSIGTYPE sigbus _((int));
static RETSIGTYPE
sigbus(sig)
    int sig;
{
    rb_bug("Bus Error");
}
#endif

#ifdef SIGSEGV
static RETSIGTYPE sigsegv _((int));
static RETSIGTYPE
sigsegv(sig)
    int sig;
{
    rb_bug("Segmentation fault");
}
#endif

#ifdef SIGPIPE
static RETSIGTYPE sigpipe _((int));
static RETSIGTYPE
sigpipe(sig)
    int sig;
{
    /* do nothing */
}
#endif

void
rb_trap_exit()
{
#ifndef MACOS_UNUSE_SIGNAL
    if (trap_list[0]) {
	VALUE trap_exit = trap_list[0];

	trap_list[0] = 0;
	rb_eval_cmd(trap_exit, rb_ary_new3(1, INT2FIX(0)));
    }
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
	    signal_exec(i);
	}
    }
#endif /* MACOS_UNUSE_SIGNAL */
    rb_trap_pending = 0;
}

struct trap_arg {
#if !defined(NT)
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

static RETSIGTYPE sigexit _((int));
static RETSIGTYPE
sigexit(sig)
    int sig;
{
    rb_exit(0);
}

static VALUE
trap(arg)
    struct trap_arg *arg;
{
    RETSIGTYPE (*func)_((int));
    VALUE command, old;
    int sig;
    char *s;

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

    switch (TYPE(arg->sig)) {
      case T_FIXNUM:
	sig = NUM2INT(arg->sig);
	break;

      case T_SYMBOL:
	s = rb_id2name(SYM2ID(arg->sig));
	if (!s) rb_raise(rb_eArgError, "bad signal");
	goto str_signal;

      case T_STRING:
	s = RSTRING(arg->sig)->ptr;

      str_signal:
	if (strncmp("SIG", s, 3) == 0)
	    s += 3;
	sig = signm2signo(s);
	if (sig == 0 && strcmp(s, "EXIT") != 0)
	    rb_raise(rb_eArgError, "invalid signal SIG%s", s);
    }

    if (sig < 0 || sig > NSIG) {
	rb_raise(rb_eArgError, "invalid signal number (%d)", sig);
    }
#if defined(HAVE_SETITIMER) && !defined(__BOW__)
    if (sig == SIGVTALRM) {
	rb_raise(rb_eArgError, "SIGVTALRM reserved for Thread; cannot set handler");
    }
#endif
    if (func == SIG_DFL) {
	switch (sig) {
	  case SIGINT:
#ifdef SIGHUP
	  case SIGHUP:
#endif
#ifdef SIGQUIT
	  case SIGQUIT:
#endif
#ifdef SIGALRM
	  case SIGALRM:
#endif
#ifdef SIGUSR1
	  case SIGUSR1:
#endif
#ifdef SIGUSR2
	  case SIGUSR2:
#endif
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
#ifdef SIGPIPE
	  case SIGPIPE:
	    func = sigpipe;
	    break;
#endif
	}
    }
    ruby_signal(sig, func);
    old = trap_list[sig];
    if (!old) old = Qnil;

    trap_list[sig] = command;
    /* enable at least specified signal. */
#if !defined(NT)
#ifdef HAVE_SIGPROCMASK
    sigdelset(&arg->mask, sig);
#else
    arg->mask &= ~sigmask(sig);
#endif
#endif
    return old;
}

#if !defined(NT)
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
rb_trap_restore_mask()
{
#if !defined(NT)
# ifdef HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &trap_last_mask, NULL);
# else
    sigsetmask(trap_last_mask);
# endif
#endif
}

static VALUE
rb_f_trap(argc, argv)
    int argc;
    VALUE *argv;
{
    struct trap_arg arg;

    rb_secure(2);
    if (argc == 0 || argc > 2) {
	rb_raise(rb_eArgError, "wrong # of arguments -- trap(sig, cmd)/trap(sig){...}");
    }

    arg.sig = argv[0];
    if (argc == 1) {
	arg.cmd = rb_f_lambda();
    }
    else if (argc == 2) {
	arg.cmd = argv[1];
    }

#if !defined(NT)
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
    rb_define_global_function("trap", rb_f_trap, -1);
    ruby_signal(SIGINT, sighandle);
#ifdef SIGHUP
    ruby_signal(SIGHUP, sighandle);
#endif
#ifdef SIGQUIT
    ruby_signal(SIGQUIT, sighandle);
#endif
#ifdef SIGALRM
    ruby_signal(SIGALRM, sighandle);
#endif
#ifdef SIGUSR1
    ruby_signal(SIGUSR1, sighandle);
#endif
#ifdef SIGUSR2
    ruby_signal(SIGUSR2, sighandle);
#endif

#ifdef SIGBUS
    ruby_signal(SIGBUS, sigbus);
#endif
#ifdef SIGSEGV
    ruby_signal(SIGSEGV, sigsegv);
#endif
#ifdef SIGPIPE
    ruby_signal(SIGPIPE, sigpipe);
#endif
#endif /* MACOS_UNUSE_SIGNAL */
}
