/**********************************************************************

  signal.c -

  $Author$
  $Date$
  created at: Tue Dec 20 10:13:44 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto
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

#if defined HAVE_SIGPROCMASK || defined HAVE_SIGSETMASK
#define USE_TRAP_MASK 1
#else
#define USE_TRAP_MASK 0
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
    {"EXIT", 0},
#ifdef SIGHUP
    {"HUP", SIGHUP},
#endif
    {"INT", SIGINT},
#ifdef SIGQUIT
    {"QUIT", SIGQUIT},
#endif
#ifdef SIGILL
    {"ILL", SIGILL},
#endif
#ifdef SIGTRAP
    {"TRAP", SIGTRAP},
#endif
#ifdef SIGIOT
    {"IOT", SIGIOT},
#endif
#ifdef SIGABRT
    {"ABRT", SIGABRT},
#endif
#ifdef SIGEMT
    {"EMT", SIGEMT},
#endif
#ifdef SIGFPE
    {"FPE", SIGFPE},
#endif
#ifdef SIGKILL
    {"KILL", SIGKILL},
#endif
#ifdef SIGBUS
    {"BUS", SIGBUS},
#endif
#ifdef SIGSEGV
    {"SEGV", SIGSEGV},
#endif
#ifdef SIGSYS
    {"SYS", SIGSYS},
#endif
#ifdef SIGPIPE
    {"PIPE", SIGPIPE},
#endif
#ifdef SIGALRM
    {"ALRM", SIGALRM},
#endif
#ifdef SIGTERM
    {"TERM", SIGTERM},
#endif
#ifdef SIGURG
    {"URG", SIGURG},
#endif
#ifdef SIGSTOP
    {"STOP", SIGSTOP},
#endif
#ifdef SIGTSTP
    {"TSTP", SIGTSTP},
#endif
#ifdef SIGCONT
    {"CONT", SIGCONT},
#endif
#ifdef SIGCHLD
    {"CHLD", SIGCHLD},
#endif
#ifdef SIGCLD
    {"CLD", SIGCLD},
#else
# ifdef SIGCHLD
    {"CLD", SIGCHLD},
# endif
#endif
#ifdef SIGTTIN
    {"TTIN", SIGTTIN},
#endif
#ifdef SIGTTOU
    {"TTOU", SIGTTOU},
#endif
#ifdef SIGIO
    {"IO", SIGIO},
#endif
#ifdef SIGXCPU
    {"XCPU", SIGXCPU},
#endif
#ifdef SIGXFSZ
    {"XFSZ", SIGXFSZ},
#endif
#ifdef SIGVTALRM
    {"VTALRM", SIGVTALRM},
#endif
#ifdef SIGPROF
    {"PROF", SIGPROF},
#endif
#ifdef SIGWINCH
    {"WINCH", SIGWINCH},
#endif
#ifdef SIGUSR1
    {"USR1", SIGUSR1},
#endif
#ifdef SIGUSR2
    {"USR2", SIGUSR2},
#endif
#ifdef SIGLOST
    {"LOST", SIGLOST},
#endif
#ifdef SIGMSG
    {"MSG", SIGMSG},
#endif
#ifdef SIGPWR
    {"PWR", SIGPWR},
#endif
#ifdef SIGPOLL
    {"POLL", SIGPOLL},
#endif
#ifdef SIGDANGER
    {"DANGER", SIGDANGER},
#endif
#ifdef SIGMIGRATE
    {"MIGRATE", SIGMIGRATE},
#endif
#ifdef SIGPRE
    {"PRE", SIGPRE},
#endif
#ifdef SIGGRANT
    {"GRANT", SIGGRANT},
#endif
#ifdef SIGRETRACT
    {"RETRACT", SIGRETRACT},
#endif
#ifdef SIGSOUND
    {"SOUND", SIGSOUND},
#endif
#ifdef SIGINFO
    {"INFO", SIGINFO},
#endif
    {NULL, 0}
};

static int
signm2signo(nm)
    const char *nm;
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

const char *
ruby_signal_name(no)
    int no;
{
    return signo2signm(no);
}

/*
 * call-seq:
 *    SignalException.new(sig)   =>  signal_exception
 *
 *  Construct a new SignalException object.  +sig+ should be a known
 *  signal name, or a signal number.
 */

static VALUE
esignal_init(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    int argnum = 1;
    VALUE sig = Qnil;
    int signo;
    const char *signm;
    char tmpnm[(sizeof(int)*CHAR_BIT)/3+4];

    if (argc > 0) {
	sig = argv[0];
	if (FIXNUM_P(sig)) argnum = 2;
    }
    if (argc < 1 || argnum < argc) {
	rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)",
		 argc, argnum);
    }
    if (argnum == 2) {
	signo = FIX2INT(sig);
	if (signo < 0 || signo > NSIG) {
	    rb_raise(rb_eArgError, "invalid signal number (%d)", signo);
	}
	if (argc > 1) {
	    sig = argv[1];
	}
	else {
	    signm = signo2signm(signo);
	    if (signm) {
		snprintf(tmpnm, sizeof(tmpnm), "SIG%s", signm);
	    }
	    else {
		snprintf(tmpnm, sizeof(tmpnm), "SIG%u", signo);
	    }
	    sig = rb_str_new2(signm = tmpnm);
	}
    }
    else {
	signm = SYMBOL_P(sig) ? rb_id2name(SYM2ID(sig)) : StringValuePtr(sig);
	if (strncmp(signm, "SIG", 3) == 0) signm += 3;
	signo = signm2signo(signm);
	if (!signo) {
	    rb_raise(rb_eArgError, "unsupported name `SIG%s'", signm);
	}
	if (SYMBOL_P(sig)) {
	    sig = rb_str_new2(signm);
	}
    }
    rb_call_super(1, &sig);
    rb_iv_set(self, "signo", INT2NUM(signo));

    return self;
}

static VALUE
interrupt_init(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE args[2];

    args[0] = INT2FIX(SIGINT);
    rb_scan_args(argc, argv, "01", &args[1]);

    return rb_call_super(2, args);
}

void
ruby_default_signal(sig)
    int sig;
{
#ifndef MACOS_UNUSE_SIGNAL
    extern rb_pid_t getpid _((void));

    signal(sig, SIG_DFL);
    kill(getpid(), sig);
#endif
}

/*
 *  call-seq:
 *     Process.kill(signal, pid, ...)    => fixnum
 *  
 *  Sends the given signal to the specified process id(s), or to the
 *  current process if _pid_ is zero. _signal_ may be an
 *  integer signal number or a POSIX signal name (either with or without
 *  a +SIG+ prefix). If _signal_ is negative (or starts
 *  with a minus sign), kills process groups instead of
 *  processes. Not all signals are available on all platforms.
 *     
 *     pid = fork do
 *        Signal.trap("HUP") { puts "Ouch!"; exit }
 *        # ... do some work ...
 *     end
 *     # ...
 *     Process.kill("HUP", pid)
 *     Process.wait
 *     
 *  <em>produces:</em>
 *     
 *     Ouch!
 */

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
	rb_raise(rb_eArgError, "wrong number of arguments -- kill(sig, pid...)");
    switch (TYPE(argv[0])) {
      case T_FIXNUM:
	sig = FIX2INT(argv[0]);
	break;

      case T_SYMBOL:
	s = rb_id2name(SYM2ID(argv[0]));
	if (!s) rb_raise(rb_eArgError, "bad signal");
	goto str_signal;

      case T_STRING:
	s = RSTRING(argv[0])->ptr;
	if (s[0] == '-') {
	    negative++;
	    s++;
	}
      str_signal:
	if (strncmp("SIG", s, 3) == 0)
	    s += 3;
	if((sig = signm2signo(s)) == 0)
	    rb_raise(rb_eArgError, "unsupported name `SIG%s'", s);

	if (negative)
	    sig = -sig;
	break;

      default:
        {
	    VALUE str;

	    str = rb_check_string_type(argv[0]);
	    if (!NIL_P(str)) {
		s = RSTRING(str)->ptr;
		goto str_signal;
	    }
	    rb_raise(rb_eArgError, "bad signal type %s",
		     rb_obj_classname(argv[0]));
	}
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

static struct {
    VALUE cmd;
    int safe;
} trap_list[NSIG];
static rb_atomic_t trap_pending_list[NSIG];
static char rb_trap_accept_nativethreads[NSIG];
rb_atomic_t rb_trap_pending;
rb_atomic_t rb_trap_immediate;
int rb_prohibit_interrupt = 1;

void
rb_gc_mark_trap_list()
{
#ifndef MACOS_UNUSE_SIGNAL
    int i;

    for (i=0; i<NSIG; i++) {
	if (trap_list[i].cmd)
	    rb_gc_mark(trap_list[i].cmd);
    }
#endif /* MACOS_UNUSE_SIGNAL */
}

#ifdef __dietlibc__
#define sighandler_t sh_t
#endif

typedef RETSIGTYPE (*sighandler_t)_((int));

#ifdef POSIX_SIGNAL
static sighandler_t
ruby_signal(signum, handler)
    int signum;
    sighandler_t handler;
{
    struct sigaction sigact, old;

    rb_trap_accept_nativethreads[signum] = 0;

    sigact.sa_handler = handler;
    sigemptyset(&sigact.sa_mask);
    sigact.sa_flags = 0;
# ifdef SA_NOCLDWAIT
    if (signum == SIGCHLD && handler == SIG_IGN)
	sigact.sa_flags |= SA_NOCLDWAIT;
# endif
    sigaction(signum, &sigact, &old);
    return old.sa_handler;
}

void
posix_signal(signum, handler)
    int signum;
    sighandler_t handler;
{
    ruby_signal(signum, handler);
}

# ifdef HAVE_NATIVETHREAD
static sighandler_t
ruby_nativethread_signal(signum, handler)
    int signum;
    sighandler_t handler;
{
    sighandler_t old;

    old = ruby_signal(signum, handler);
    rb_trap_accept_nativethreads[signum] = 1;
    return old;
}

void
posix_nativethread_signal(signum, handler)
    int signum;
    sighandler_t handler;
{
    ruby_nativethread_signal(signum, handler);
}
# endif

#else /* !POSIX_SIGNAL */
#define ruby_signal(sig,handler) (rb_trap_accept_nativethreads[sig] = 0, signal((sig),(handler)))

# ifdef HAVE_NATIVETHREAD
static sighandler_t
ruby_nativethread_signal(signum, handler)
    int signum;
    sighandler_t handler;
{
    sighandler_t old;

    old = signal(signum, handler);
    rb_trap_accept_nativethreads[signum] = 1;
    return old;
}
# endif
#endif /* POSIX_SIGNAL */

static void signal_exec _((int sig));
static void
signal_exec(sig)
    int sig;
{
    if (trap_list[sig].cmd == 0) {
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
#ifdef SIGTERM
	  case SIGTERM:
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
	    rb_thread_signal_raise(sig);
	    break;
	}
    }
    else if (trap_list[sig].cmd == Qundef) {
	rb_thread_signal_exit();
    }
    else {
	rb_thread_trap_eval(trap_list[sig].cmd, sig, trap_list[sig].safe);
    }
}

#if defined(HAVE_NATIVETHREAD) && defined(HAVE_NATIVETHREAD_KILL)
static void
sigsend_to_ruby_thread(int sig)
{
# ifdef HAVE_SIGPROCMASK
    sigset_t mask, old_mask;
# else
    int mask, old_mask;
# endif

# ifdef HAVE_SIGPROCMASK
    sigfillset(&mask);
    sigprocmask(SIG_BLOCK, &mask, &old_mask);
# else
    mask = sigblock(~0);
    sigsetmask(mask);
# endif

    ruby_native_thread_kill(sig);
}
#endif

static RETSIGTYPE sighandler _((int));
static RETSIGTYPE
sighandler(sig)
    int sig;
{
#ifdef _WIN32
#define IN_MAIN_CONTEXT(f, a) (rb_w32_main_context(a, f) ? (void)0 : f(a))
#else
#define IN_MAIN_CONTEXT(f, a) f(a)
#endif

    if (sig >= NSIG) {
	rb_bug("trap_handler: Bad signal %d", sig);
    }

#if defined(HAVE_NATIVETHREAD) && defined(HAVE_NATIVETHREAD_KILL)
    if (!is_ruby_native_thread() && !rb_trap_accept_nativethreads[sig]) {
	sigsend_to_ruby_thread(sig);
	return;
    }
#endif

#if !defined(BSD_SIGNAL) && !defined(POSIX_SIGNAL)
    if (rb_trap_accept_nativethreads[sig]) {
	ruby_nativethread_signal(sig, sighandler);
    }
    else {
	ruby_signal(sig, sighandler);
    }
#endif

    if (trap_list[sig].cmd == 0 && ATOMIC_TEST(rb_trap_immediate)) {
	IN_MAIN_CONTEXT(signal_exec, sig);
	ATOMIC_SET(rb_trap_immediate, 1);
    }
    else {
	ATOMIC_INC(rb_trap_pending);
	ATOMIC_INC(trap_pending_list[sig]);
#ifdef _WIN32
	rb_w32_interrupted();
#endif
    }
}

#ifdef SIGBUS
static RETSIGTYPE sigbus _((int));
static RETSIGTYPE
sigbus(sig)
    int sig;
{
#if defined(HAVE_NATIVETHREAD) && defined(HAVE_NATIVETHREAD_KILL)
    if (!is_ruby_native_thread() && !rb_trap_accept_nativethreads[sig]) {
        sigsend_to_ruby_thread(sig);
        return;
    }
#endif

    rb_bug("Bus Error");
}
#endif

#ifdef SIGSEGV
static RETSIGTYPE sigsegv _((int));
static RETSIGTYPE
sigsegv(sig)
    int sig;
{
#if defined(HAVE_NATIVETHREAD) && defined(HAVE_NATIVETHREAD_KILL)
    if (!is_ruby_native_thread() && !rb_trap_accept_nativethreads[sig]) {
        sigsend_to_ruby_thread(sig);
        return;
    }
#endif

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
    if (trap_list[0].cmd) {
	VALUE trap_exit = trap_list[0].cmd;

	trap_list[0].cmd = 0;
	rb_eval_cmd(trap_exit, rb_ary_new3(1, INT2FIX(0)), trap_list[0].safe);
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
#if USE_TRAP_MASK
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
    rb_thread_signal_exit();
}

static VALUE
trap(arg)
    struct trap_arg *arg;
{
    sighandler_t func, oldfunc;
    VALUE command, oldcmd;
    int sig = -1;
    char *s;

    func = sighandler;
    command = arg->cmd;
    if (NIL_P(command)) {
	func = SIG_IGN;
    }
    else if (TYPE(command) == T_STRING) {
	SafeStringValue(command);	/* taint check */
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
	sig = FIX2INT(arg->sig);
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
	    rb_raise(rb_eArgError, "unsupported signal SIG%s", s);
    }

    if (sig < 0 || sig >= NSIG) {
	rb_raise(rb_eArgError, "invalid signal number (%d)", sig);
    }
#if defined(HAVE_SETITIMER)
    if (sig == SIGVTALRM) {
	rb_raise(rb_eArgError, "SIGVTALRM reserved for Thread; can't set handler");
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
#ifdef SIGTERM
	  case SIGTERM:
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
	    func = sighandler;
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
    oldfunc = ruby_signal(sig, func);
    oldcmd = trap_list[sig].cmd;
    if (!oldcmd) {
	if (oldfunc == SIG_IGN) oldcmd = rb_str_new2("IGNORE");
	else if (oldfunc == sighandler) oldcmd = rb_str_new2("DEFAULT");
	else oldcmd = Qnil;
    }

    trap_list[sig].cmd = command;
    trap_list[sig].safe = ruby_safe_level;
    /* enable at least specified signal. */
#if USE_TRAP_MASK
#ifdef HAVE_SIGPROCMASK
    sigdelset(&arg->mask, sig);
#else
    arg->mask &= ~sigmask(sig);
#endif
#endif
    return oldcmd;
}

#if USE_TRAP_MASK
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
#if USE_TRAP_MASK
# ifdef HAVE_SIGPROCMASK
    sigprocmask(SIG_SETMASK, &trap_last_mask, NULL);
# else
    sigsetmask(trap_last_mask);
# endif
#endif
}

/*
 * call-seq:
 *   Signal.trap( signal, proc ) => obj
 *   Signal.trap( signal ) {| | block } => obj
 *
 * Specifies the handling of signals. The first parameter is a signal
 * name (a string such as ``SIGALRM'', ``SIGUSR1'', and so on) or a
 * signal number. The characters ``SIG'' may be omitted from the
 * signal name. The command or block specifies code to be run when the
 * signal is raised. If the command is the string ``IGNORE'' or
 * ``SIG_IGN'', the signal will be ignored. If the command is
 * ``DEFAULT'' or ``SIG_DFL'', the operating system's default handler
 * will be invoked. If the command is ``EXIT'', the script will be
 * terminated by the signal. Otherwise, the given command or block
 * will be run.
 * The special signal name ``EXIT'' or signal number zero will be
 * invoked just prior to program termination.
 * trap returns the previous handler for the given signal.
 *
 *     Signal.trap(0, proc { puts "Terminating: #{$$}" })
 *     Signal.trap("CLD")  { puts "Child died" }
 *     fork && Process.wait
 *
 * produces:
 *     Terminating: 27461
 *     Child died
 *     Terminating: 27460
 */
static VALUE
sig_trap(argc, argv)
    int argc;
    VALUE *argv;
{
    struct trap_arg arg;

    rb_secure(2);
    if (argc == 0 || argc > 2) {
	rb_raise(rb_eArgError, "wrong number of arguments -- trap(sig, cmd)/trap(sig){...}");
    }

    arg.sig = argv[0];
    if (argc == 1) {
	arg.cmd = rb_block_proc();
    }
    else if (argc == 2) {
	arg.cmd = argv[1];
    }

    if (OBJ_TAINTED(arg.cmd)) {
	rb_raise(rb_eSecurityError, "Insecure: tainted signal trap");
    }
#if USE_TRAP_MASK
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

/*
 * call-seq:
 *   Signal.list => a_hash
 *
 * Returns a list of signal names mapped to the corresponding
 * underlying signal numbers.
 *
 * Signal.list   #=> {"ABRT"=>6, "ALRM"=>14, "BUS"=>7, "CHLD"=>17, "CLD"=>17, "CONT"=>18, "FPE"=>8, "HUP"=>1, "ILL"=>4, "INT"=>2, "IO"=>29, "IOT"=>6, "KILL"=>9, "PIPE"=>13, "POLL"=>29, "PROF"=>27, "PWR"=>30, "QUIT"=>3, "SEGV"=>11, "STOP"=>19, "SYS"=>31, "TERM"=>15, "TRAP"=>5, "TSTP"=>20, "TTIN"=>21, "TTOU"=>22, "URG"=>23, "USR1"=>10, "USR2"=>12, "VTALRM"=>26, "WINCH"=>28, "XCPU"=>24, "XFSZ"=>25}
 */
static VALUE
sig_list()
{
    VALUE h = rb_hash_new();
    struct signals *sigs;

    for (sigs = siglist; sigs->signm; sigs++) {
	rb_hash_aset(h, rb_str_new2(sigs->signm), INT2FIX(sigs->signo));
    }
    return h;
}

static void
install_sighandler(signum, handler)
    int signum;
    sighandler_t handler;
{
    sighandler_t old;

    old = ruby_signal(signum, handler);
    if (old != SIG_DFL) {
	ruby_signal(signum, old);
    }
}

#if 0
/* 
 *   If you write a handler which works on any native thread
 *   (even if the thread is NOT a ruby's one), please enable
 *   this function and use it to install the handler, instead
 *   of `install_sighandler()'.
 */
#ifdef HAVE_NATIVETHREAD
static void
install_nativethread_sighandler(signum, handler)
    int signum;
    sighandler_t handler;
{
    sighandler_t old;
    int old_st;

    old_st = rb_trap_accept_nativethreads[signum];
    old = ruby_nativethread_signal(signum, handler);
    if (old != SIG_DFL) {
        if (old_st) {
            ruby_nativethread_signal(signum, old);
        } else {
            ruby_signal(signum, old);
        }
    }
}
#endif
#endif

static void
init_sigchld(sig)
    int sig;
{
    sighandler_t oldfunc;
#if USE_TRAP_MASK
# ifdef HAVE_SIGPROCMASK
    sigset_t mask;
# else
    int mask;
# endif
#endif

#if USE_TRAP_MASK
    /* disable interrupt */
# ifdef HAVE_SIGPROCMASK
    sigfillset(&mask);
    sigprocmask(SIG_BLOCK, &mask, &mask);
# else
    mask = sigblock(~0);
# endif
#endif

    oldfunc = ruby_signal(sig, SIG_DFL);
    if (oldfunc != SIG_DFL && oldfunc != SIG_IGN) {
	ruby_signal(sig, oldfunc);
    } else {
	trap_list[sig].cmd = 0;
    }

#if USE_TRAP_MASK
#ifdef HAVE_SIGPROCMASK
    sigdelset(&mask, sig);
    sigprocmask(SIG_SETMASK, &mask, NULL);
#else
    mask &= ~sigmask(sig);
    sigsetmask(mask);
#endif
    trap_last_mask = mask;
#endif
}

/*
 * Many operating systems allow signals to be sent to running
 * processes. Some signals have a defined effect on the process, while
 * others may be trapped at the code level and acted upon. For
 * example, your process may trap the USR1 signal and use it to toggle
 * debugging, and may use TERM to initiate a controlled shutdown.
 *
 *     pid = fork do
 *       Signal.trap("USR1") do
 *         $debug = !$debug
 *         puts "Debug now: #$debug"
 *       end
 *       Signal.trap("TERM") do
 *         puts "Terminating..."
 *         shutdown()
 *       end
 *       # . . . do some work . . .
 *     end
 *
 *     Process.detach(pid)
 *
 *     # Controlling program:
 *     Process.kill("USR1", pid)
 *     # ...
 *     Process.kill("USR1", pid)
 *     # ...
 *     Process.kill("TERM", pid)
 *
 * produces:
 *     Debug now: true
 *     Debug now: false
 *    Terminating...
 *
 * The list of available signal names and their interpretation is
 * system dependent. Signal delivery semantics may also vary between
 * systems; in particular signal delivery may not always be reliable.
 */
void
Init_signal()
{
#ifndef MACOS_UNUSE_SIGNAL
    VALUE mSignal = rb_define_module("Signal");

    rb_define_global_function("trap", sig_trap, -1);
    rb_define_module_function(mSignal, "trap", sig_trap, -1);
    rb_define_module_function(mSignal, "list", sig_list, 0);

    rb_define_method(rb_eSignal, "initialize", esignal_init, -1);
    rb_attr(rb_eSignal, rb_intern("signo"), 1, 0, 0);
    rb_alias(rb_eSignal, rb_intern("signm"), rb_intern("message"));
    rb_define_method(rb_eInterrupt, "initialize", interrupt_init, -1);

    install_sighandler(SIGINT, sighandler);
#ifdef SIGHUP
    install_sighandler(SIGHUP, sighandler);
#endif
#ifdef SIGQUIT
    install_sighandler(SIGQUIT, sighandler);
#endif
#ifdef SIGTERM
    install_sighandler(SIGTERM, sighandler);
#endif
#ifdef SIGALRM
    install_sighandler(SIGALRM, sighandler);
#endif
#ifdef SIGUSR1
    install_sighandler(SIGUSR1, sighandler);
#endif
#ifdef SIGUSR2
    install_sighandler(SIGUSR2, sighandler);
#endif

#ifdef SIGBUS
    install_sighandler(SIGBUS, sigbus);
#endif
#ifdef SIGSEGV
    install_sighandler(SIGSEGV, sigsegv);
#endif
#ifdef SIGPIPE
    install_sighandler(SIGPIPE, sigpipe);
#endif

#if defined(SIGCLD)
    init_sigchld(SIGCLD);
#elif defined(SIGCHLD)
    init_sigchld(SIGCHLD);
#endif

#endif /* MACOS_UNUSE_SIGNAL */
}
