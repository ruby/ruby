/**********************************************************************

  signal.c -

  $Author$
  created at: Tue Dec 20 10:13:44 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "internal.h"
#include "vm_core.h"
#include <signal.h>
#include <stdio.h>
#include <errno.h>
#include "ruby_atomic.h"
#include "eval_intern.h"
#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif
#ifdef HAVE_SYS_UIO_H
#include <sys/uio.h>
#endif
#ifdef HAVE_UCONTEXT_H
#include <ucontext.h>
#endif

#ifdef HAVE_VALGRIND_MEMCHECK_H
# include <valgrind/memcheck.h>
# ifndef VALGRIND_MAKE_MEM_DEFINED
#  define VALGRIND_MAKE_MEM_DEFINED(p, n) VALGRIND_MAKE_READABLE((p), (n))
# endif
# ifndef VALGRIND_MAKE_MEM_UNDEFINED
#  define VALGRIND_MAKE_MEM_UNDEFINED(p, n) VALGRIND_MAKE_WRITABLE((p), (n))
# endif
#else
# define VALGRIND_MAKE_MEM_DEFINED(p, n) 0
# define VALGRIND_MAKE_MEM_UNDEFINED(p, n) 0
#endif

#if defined(__native_client__) && defined(NACL_NEWLIB)
# include "nacl/signal.h"
#endif

extern ID ruby_static_id_signo;
#define id_signo ruby_static_id_signo

#ifdef NEED_RUBY_ATOMIC_OPS
rb_atomic_t
ruby_atomic_exchange(rb_atomic_t *ptr, rb_atomic_t val)
{
    rb_atomic_t old = *ptr;
    *ptr = val;
    return old;
}

rb_atomic_t
ruby_atomic_compare_and_swap(rb_atomic_t *ptr, rb_atomic_t cmp,
			     rb_atomic_t newval)
{
    rb_atomic_t old = *ptr;
    if (old == cmp) {
	*ptr = newval;
    }
    return old;
}
#endif

#ifndef NSIG
# define NSIG (_SIGMAX + 1)      /* For QNX */
#endif

static const struct signals {
    const char *signm;
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
#ifdef SIGABRT
    {"ABRT", SIGABRT},
#endif
#ifdef SIGIOT
    {"IOT", SIGIOT},
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

static const char signame_prefix[3] = "SIG";

static int
signm2signo(const char *nm)
{
    const struct signals *sigs;

    for (sigs = siglist; sigs->signm; sigs++)
	if (strcmp(sigs->signm, nm) == 0)
	    return sigs->signo;
    return 0;
}

static const char*
signo2signm(int no)
{
    const struct signals *sigs;

    for (sigs = siglist; sigs->signm; sigs++)
	if (sigs->signo == no)
	    return sigs->signm;
    return 0;
}

/*
 * call-seq:
 *     Signal.signame(signo)  ->  string or nil
 *
 *  Convert signal number to signal name.
 *  Returns +nil+ if the signo is an invalid signal number.
 *
 *     Signal.trap("INT") { |signo| puts Signal.signame(signo) }
 *     Process.kill("INT", 0)
 *
 *  <em>produces:</em>
 *
 *     INT
 */
static VALUE
sig_signame(VALUE recv, VALUE signo)
{
    const char *signame = signo2signm(NUM2INT(signo));
    if (!signame) return Qnil;
    return rb_str_new_cstr(signame);
}

const char *
ruby_signal_name(int no)
{
    return signo2signm(no);
}

static VALUE
rb_signo2signm(int signo)
{
    const char *const signm = signo2signm(signo);
    if (signm) {
	return rb_sprintf("SIG%s", signm);
    }
    else {
	return rb_sprintf("SIG%u", signo);
    }
}

/*
 * call-seq:
 *    SignalException.new(sig_name)              ->  signal_exception
 *    SignalException.new(sig_number [, name])   ->  signal_exception
 *
 *  Construct a new SignalException object.  +sig_name+ should be a known
 *  signal name.
 */

static VALUE
esignal_init(int argc, VALUE *argv, VALUE self)
{
    int argnum = 1;
    VALUE sig = Qnil;
    int signo;
    const char *signm;

    if (argc > 0) {
	sig = rb_check_to_integer(argv[0], "to_int");
	if (!NIL_P(sig)) argnum = 2;
	else sig = argv[0];
    }
    rb_check_arity(argc, 1, argnum);
    if (argnum == 2) {
	signo = NUM2INT(sig);
	if (signo < 0 || signo > NSIG) {
	    rb_raise(rb_eArgError, "invalid signal number (%d)", signo);
	}
	if (argc > 1) {
	    sig = argv[1];
	}
	else {
	    sig = rb_signo2signm(signo);
	}
    }
    else {
	int len = sizeof(signame_prefix);
	if (SYMBOL_P(sig)) sig = rb_sym2str(sig); else StringValue(sig);
	signm = RSTRING_PTR(sig);
	if (strncmp(signm, signame_prefix, len) == 0) {
	    signm += len;
	    len = 0;
	}
	signo = signm2signo(signm);
	if (!signo) {
	    rb_raise(rb_eArgError, "unsupported name `%.*s%"PRIsVALUE"'",
		     len, signame_prefix, sig);
	}
	sig = rb_sprintf("SIG%s", signm);
    }
    rb_call_super(1, &sig);
    rb_ivar_set(self, id_signo, INT2NUM(signo));

    return self;
}

/*
 * call-seq:
 *    signal_exception.signo   ->  num
 *
 *  Returns a signal number.
 */

static VALUE
esignal_signo(VALUE self)
{
    return rb_ivar_get(self, id_signo);
}

/* :nodoc: */
static VALUE
interrupt_init(int argc, VALUE *argv, VALUE self)
{
    VALUE args[2];

    args[0] = INT2FIX(SIGINT);
    rb_scan_args(argc, argv, "01", &args[1]);
    return rb_call_super(2, args);
}

void
ruby_default_signal(int sig)
{
    signal(sig, SIG_DFL);
    raise(sig);
}

static RETSIGTYPE sighandler(int sig);
static int signal_ignored(int sig);
static void signal_enque(int sig);

/*
 *  call-seq:
 *     Process.kill(signal, pid, ...)    -> integer
 *
 *  Sends the given signal to the specified process id(s) if _pid_ is positive.
 *  If _pid_ is zero _signal_ is sent to all processes whose group ID is equal
 *  to the group ID of the process. _signal_ may be an integer signal number or
 *  a POSIX signal name (either with or without a +SIG+ prefix). If _signal_ is
 *  negative (or starts with a minus sign), kills process groups instead of
 *  processes. Not all signals are available on all platforms.
 *  The keys and values of +Signal.list+ are known signal names and numbers,
 *  respectively.
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
 *
 *  If _signal_ is an integer but wrong for signal,
 *  <code>Errno::EINVAL</code> or +RangeError+ will be raised.
 *  Otherwise unless _signal_ is a +String+ or a +Symbol+, and a known
 *  signal name, +ArgumentError+ will be raised.
 *
 *  Also, <code>Errno::ESRCH</code> or +RangeError+ for invalid _pid_,
 *  <code>Errno::EPERM</code> when failed because of no privilege,
 *  will be raised.  In these cases, signals may have been sent to
 *  preceding processes.
 */

VALUE
rb_f_kill(int argc, const VALUE *argv)
{
#ifndef HAVE_KILLPG
#define killpg(pg, sig) kill(-(pg), (sig))
#endif
    int negative = 0;
    int sig;
    int i;
    VALUE str;
    const char *s;

    rb_check_arity(argc, 2, UNLIMITED_ARGUMENTS);

    switch (TYPE(argv[0])) {
      case T_FIXNUM:
	sig = FIX2INT(argv[0]);
	break;

      case T_SYMBOL:
	str = rb_sym2str(argv[0]);
	goto str_signal;

      case T_STRING:
	str = argv[0];
      str_signal:
	s = RSTRING_PTR(str);
	if (s[0] == '-') {
	    negative++;
	    s++;
	}
	if (strncmp(signame_prefix, s, sizeof(signame_prefix)) == 0)
	    s += 3;
	if ((sig = signm2signo(s)) == 0) {
	    long ofs = s - RSTRING_PTR(str);
	    if (ofs) str = rb_str_subseq(str, ofs, RSTRING_LEN(str)-ofs);
	    rb_raise(rb_eArgError, "unsupported name `SIG%"PRIsVALUE"'", str);
	}

	if (negative)
	    sig = -sig;
	break;

      default:
	str = rb_check_string_type(argv[0]);
	if (!NIL_P(str)) {
	    goto str_signal;
	}
	rb_raise(rb_eArgError, "bad signal type %s",
		 rb_obj_classname(argv[0]));
	break;
    }

    if (argc <= 1) return INT2FIX(0);

    if (sig < 0) {
	sig = -sig;
	for (i=1; i<argc; i++) {
	    if (killpg(NUM2PIDT(argv[i]), sig) < 0)
		rb_sys_fail(0);
	}
    }
    else {
	const rb_pid_t self = (GET_THREAD() == GET_VM()->main_thread) ? getpid() : -1;
	int wakeup = 0;

	for (i=1; i<argc; i++) {
	    rb_pid_t pid = NUM2PIDT(argv[i]);

	    if ((sig != 0) && (self != -1) && (pid == self)) {
		int t;
		/*
		 * When target pid is self, many caller assume signal will be
		 * delivered immediately and synchronously.
		 */
		switch (sig) {
		  case SIGSEGV:
#ifdef SIGBUS
		  case SIGBUS:
#endif
#ifdef SIGKILL
		  case SIGKILL:
#endif
#ifdef SIGILL
		  case SIGILL:
#endif
#ifdef SIGFPE
		  case SIGFPE:
#endif
#ifdef SIGSTOP
		  case SIGSTOP:
#endif
		    ruby_kill(pid, sig);
		    break;
		  default:
		    t = signal_ignored(sig);
		    if (t) {
			if (t < 0 && kill(pid, sig))
			    rb_sys_fail(0);
			break;
		    }
		    signal_enque(sig);
		    wakeup = 1;
		}
	    }
	    else if (kill(pid, sig) < 0) {
		rb_sys_fail(0);
	    }
	}
	if (wakeup) {
	    rb_threadptr_check_signal(GET_VM()->main_thread);
	}
    }
    rb_thread_execute_interrupts(rb_thread_current());

    return INT2FIX(i-1);
}

static struct {
    rb_atomic_t cnt[RUBY_NSIG];
    rb_atomic_t size;
} signal_buff;

#ifdef __dietlibc__
#define sighandler_t sh_t
#else
#define sighandler_t ruby_sighandler_t
#endif

typedef RETSIGTYPE (*sighandler_t)(int);
#ifdef USE_SIGALTSTACK
typedef void ruby_sigaction_t(int, siginfo_t*, void*);
#define SIGINFO_ARG , siginfo_t *info, void *ctx
#define SIGINFO_CTX ctx
#else
typedef RETSIGTYPE ruby_sigaction_t(int);
#define SIGINFO_ARG
#define SIGINFO_CTX 0
#endif

#ifdef USE_SIGALTSTACK
int
rb_sigaltstack_size(void)
{
    /* XXX: BSD_vfprintf() uses >1500KiB stack and x86-64 need >5KiB stack. */
    int size = 16*1024;

#ifdef MINSIGSTKSZ
    if (size < MINSIGSTKSZ)
	size = MINSIGSTKSZ;
#endif
#if defined(HAVE_SYSCONF) && defined(_SC_PAGE_SIZE)
    {
	int pagesize;
	pagesize = (int)sysconf(_SC_PAGE_SIZE);
	if (size < pagesize)
	    size = pagesize;
    }
#endif

    return size;
}

/* alternate stack for SIGSEGV */
void
rb_register_sigaltstack(rb_thread_t *th)
{
    stack_t newSS, oldSS;

    if (!th->altstack)
	rb_bug("rb_register_sigaltstack: th->altstack not initialized\n");

    newSS.ss_sp = th->altstack;
    newSS.ss_size = rb_sigaltstack_size();
    newSS.ss_flags = 0;

    sigaltstack(&newSS, &oldSS); /* ignore error. */
}
#endif /* USE_SIGALTSTACK */

#ifdef POSIX_SIGNAL
static sighandler_t
ruby_signal(int signum, sighandler_t handler)
{
    struct sigaction sigact, old;

#if 0
    rb_trap_accept_nativethreads[signum] = 0;
#endif

    sigemptyset(&sigact.sa_mask);
#ifdef USE_SIGALTSTACK
    if (handler == SIG_IGN || handler == SIG_DFL) {
        sigact.sa_handler = handler;
        sigact.sa_flags = 0;
    }
    else {
        sigact.sa_sigaction = (ruby_sigaction_t*)handler;
        sigact.sa_flags = SA_SIGINFO;
    }
#else
    sigact.sa_handler = handler;
    sigact.sa_flags = 0;
#endif

    switch (signum) {
#ifdef SA_NOCLDWAIT
      case SIGCHLD:
	if (handler == SIG_IGN)
	    sigact.sa_flags |= SA_NOCLDWAIT;
	break;
#endif
#if defined(SA_ONSTACK) && defined(USE_SIGALTSTACK)
      case SIGSEGV:
#ifdef SIGBUS
      case SIGBUS:
#endif
	sigact.sa_flags |= SA_ONSTACK;
	break;
#endif
    }
    (void)VALGRIND_MAKE_MEM_DEFINED(&old, sizeof(old));
    if (sigaction(signum, &sigact, &old) < 0) {
	return SIG_ERR;
    }
    if (old.sa_flags & SA_SIGINFO)
	return (sighandler_t)old.sa_sigaction;
    else
	return old.sa_handler;
}

sighandler_t
posix_signal(int signum, sighandler_t handler)
{
    return ruby_signal(signum, handler);
}

#elif defined _WIN32
static inline sighandler_t
ruby_signal(int signum, sighandler_t handler)
{
    if (signum == SIGKILL) {
	errno = EINVAL;
	return SIG_ERR;
    }
    return signal(signum, handler);
}

#else /* !POSIX_SIGNAL */
#define ruby_signal(sig,handler) (/* rb_trap_accept_nativethreads[(sig)] = 0,*/ signal((sig),(handler)))
#if 0 /* def HAVE_NATIVETHREAD */
static sighandler_t
ruby_nativethread_signal(int signum, sighandler_t handler)
{
    sighandler_t old;

    old = signal(signum, handler);
    rb_trap_accept_nativethreads[signum] = 1;
    return old;
}
#endif
#endif

static int
signal_ignored(int sig)
{
    sighandler_t func;
#ifdef POSIX_SIGNAL
    struct sigaction old;
    (void)VALGRIND_MAKE_MEM_DEFINED(&old, sizeof(old));
    if (sigaction(sig, NULL, &old) < 0) return FALSE;
    func = old.sa_handler;
#else
    sighandler_t old = signal(sig, SIG_DFL);
    signal(sig, old);
    func = old;
#endif
    if (func == SIG_IGN) return 1;
    return func == sighandler ? 0 : -1;
}

static void
signal_enque(int sig)
{
    ATOMIC_INC(signal_buff.cnt[sig]);
    ATOMIC_INC(signal_buff.size);
}

static RETSIGTYPE
sighandler(int sig)
{
    int old_errnum = errno;

    signal_enque(sig);
    rb_thread_wakeup_timer_thread();
#if !defined(BSD_SIGNAL) && !defined(POSIX_SIGNAL)
    ruby_signal(sig, sighandler);
#endif

    errno = old_errnum;
}

int
rb_signal_buff_size(void)
{
    return signal_buff.size;
}

#if HAVE_PTHREAD_H
#include <pthread.h>
#endif

static void
rb_disable_interrupt(void)
{
#ifdef HAVE_PTHREAD_SIGMASK
    sigset_t mask;
    sigfillset(&mask);
    pthread_sigmask(SIG_SETMASK, &mask, NULL);
#endif
}

static void
rb_enable_interrupt(void)
{
#ifdef HAVE_PTHREAD_SIGMASK
    sigset_t mask;
    sigemptyset(&mask);
    pthread_sigmask(SIG_SETMASK, &mask, NULL);
#endif
}

int
rb_get_next_signal(void)
{
    int i, sig = 0;

    if (signal_buff.size != 0) {
	for (i=1; i<RUBY_NSIG; i++) {
	    if (signal_buff.cnt[i] > 0) {
		ATOMIC_DEC(signal_buff.cnt[i]);
		ATOMIC_DEC(signal_buff.size);
		sig = i;
		break;
	    }
	}
    }
    return sig;
}

#if defined SIGSEGV || defined SIGBUS || defined SIGILL || defined SIGFPE
static const char *received_signal;
# define clear_received_signal() (void)(ruby_disable_gc = 0, received_signal = 0)
#else
# define clear_received_signal() ((void)0)
#endif

#if defined(USE_SIGALTSTACK) || defined(_WIN32)
NORETURN(void ruby_thread_stack_overflow(rb_thread_t *th));
# if defined __HAIKU__
#   define USE_UCONTEXT_REG 1
# elif !(defined(HAVE_UCONTEXT_H) && (defined __i386__ || defined __x86_64__ || defined __amd64__))
# elif defined __linux__
#   define USE_UCONTEXT_REG 1
# elif defined __APPLE__
#   define USE_UCONTEXT_REG 1
# elif defined __FreeBSD__
#   define USE_UCONTEXT_REG 1
# endif
# ifdef USE_UCONTEXT_REG
static void
check_stack_overflow(const uintptr_t addr, const ucontext_t *ctx)
{
    const DEFINE_MCONTEXT_PTR(mctx, ctx);
# if defined __linux__
#   if defined REG_RSP
    const greg_t sp = mctx->gregs[REG_RSP];
    const greg_t bp = mctx->gregs[REG_RBP];
#   else
    const greg_t sp = mctx->gregs[REG_ESP];
    const greg_t bp = mctx->gregs[REG_EBP];
#   endif
# elif defined __APPLE__
#   if defined(__LP64__)
    const uintptr_t sp = mctx->__ss.__rsp;
    const uintptr_t bp = mctx->__ss.__rbp;
#   else
    const uintptr_t sp = mctx->__ss.__esp;
    const uintptr_t bp = mctx->__ss.__ebp;
#   endif
# elif defined __FreeBSD__
#   if defined(__amd64__)
    const __register_t sp = mctx->mc_rsp;
    const __register_t bp = mctx->mc_rbp;
#   else
    const __register_t sp = mctx->mc_esp;
    const __register_t bp = mctx->mc_ebp;
#   endif
# elif defined __HAIKU__
#   if defined(__amd64__)
    const unsigned long sp = mctx->rsp;
    const unsigned long bp = mctx->rbp;
#   else
    const unsigned long sp = mctx->esp;
    const unsigned long bp = mctx->ebp;
#   endif
# endif
    enum {pagesize = 4096};
    const uintptr_t sp_page = (uintptr_t)sp / pagesize;
    const uintptr_t bp_page = (uintptr_t)bp / pagesize;
    const uintptr_t fault_page = addr / pagesize;

    /* SP in ucontext is not decremented yet when `push` failed, so
     * the fault page can be the next. */
    if (sp_page == fault_page || sp_page == fault_page + 1 ||
	sp_page <= fault_page && fault_page <= bp_page) {
	rb_thread_t *th = ruby_current_thread;
	if ((uintptr_t)th->tag->buf / pagesize == sp_page) {
	    /* drop the last tag if it is close to the fault,
	     * otherwise it can cause stack overflow again at the same
	     * place. */
	    th->tag = th->tag->prev;
	}
	clear_received_signal();
	ruby_thread_stack_overflow(th);
    }
}
# else
static void
check_stack_overflow(const void *addr)
{
    int ruby_stack_overflowed_p(const rb_thread_t *, const void *);
    rb_thread_t *th = ruby_current_thread;
    if (ruby_stack_overflowed_p(th, addr)) {
	clear_received_signal();
	ruby_thread_stack_overflow(th);
    }
}
# endif
# ifdef _WIN32
#   define CHECK_STACK_OVERFLOW() check_stack_overflow(0)
# else
#   define FAULT_ADDRESS info->si_addr
#   ifdef USE_UCONTEXT_REG
#     define CHECK_STACK_OVERFLOW() check_stack_overflow((uintptr_t)FAULT_ADDRESS, ctx)
#   else
#     define CHECK_STACK_OVERFLOW() check_stack_overflow(FAULT_ADDRESS)
#   endif
#   define MESSAGE_FAULT_ADDRESS " at %p", FAULT_ADDRESS
# endif
#else
# define CHECK_STACK_OVERFLOW() (void)0
#endif
#ifndef MESSAGE_FAULT_ADDRESS
# define MESSAGE_FAULT_ADDRESS
#endif

#if defined SIGSEGV || defined SIGBUS || defined SIGILL || defined SIGFPE
NOINLINE(static void check_reserved_signal_(const char *name, size_t name_len));
/* noinine to reduce stack usage in signal handers */

#define check_reserved_signal(name) check_reserved_signal_(name, sizeof(name)-1)

#ifdef SIGBUS
static RETSIGTYPE
sigbus(int sig SIGINFO_ARG)
{
    check_reserved_signal("BUS");
/*
 * Mac OS X makes KERN_PROTECTION_FAILURE when thread touch guard page.
 * and it's delivered as SIGBUS instead of SIGSEGV to userland. It's crazy
 * wrong IMHO. but anyway we have to care it. Sigh.
 */
    /* Seems Linux also delivers SIGBUS. */
#if defined __APPLE__ || defined __linux__
    CHECK_STACK_OVERFLOW();
#endif
    rb_bug_context(SIGINFO_CTX, "Bus Error" MESSAGE_FAULT_ADDRESS);
}
#endif

static void
ruby_abort(void)
{
#ifdef __sun
    /* Solaris's abort() is async signal unsafe. Of course, it is not
     *  POSIX compliant.
     */
    raise(SIGABRT);
#else
    abort();
#endif

}

#ifdef SIGSEGV
static RETSIGTYPE
sigsegv(int sig SIGINFO_ARG)
{
    check_reserved_signal("SEGV");
    CHECK_STACK_OVERFLOW();
    rb_bug_context(SIGINFO_CTX, "Segmentation fault" MESSAGE_FAULT_ADDRESS);
}
#endif

#ifdef SIGILL
static RETSIGTYPE
sigill(int sig SIGINFO_ARG)
{
    check_reserved_signal("ILL");
#if defined __APPLE__
    CHECK_STACK_OVERFLOW();
#endif
    rb_bug_context(SIGINFO_CTX, "Illegal instruction" MESSAGE_FAULT_ADDRESS);
}
#endif

static void
check_reserved_signal_(const char *name, size_t name_len)
{
    const char *prev = ATOMIC_PTR_EXCHANGE(received_signal, name);

    if (prev) {
	ssize_t RB_UNUSED_VAR(err);
#define NOZ(name, str) name[sizeof(str)-1] = str
	static const char NOZ(msg1, " received in ");
	static const char NOZ(msg2, " handler\n");

#ifdef HAVE_WRITEV
	struct iovec iov[4];

	iov[0].iov_base = (void *)name;
	iov[0].iov_len = name_len;
	iov[1].iov_base = (void *)msg1;
	iov[1].iov_len = sizeof(msg1);
	iov[2].iov_base = (void *)prev;
	iov[2].iov_len = strlen(prev);
	iov[3].iov_base = (void *)msg2;
	iov[3].iov_len = sizeof(msg2);
	err = writev(2, iov, 4);
#else
	err = write(2, name, name_len);
	err = write(2, msg1, sizeof(msg1));
	err = write(2, prev, strlen(prev));
	err = write(2, msg2, sizeof(msg2));
#endif
	ruby_abort();
    }

    ruby_disable_gc = 1;
}
#endif

#if defined SIGPIPE || defined SIGSYS
static RETSIGTYPE
sig_do_nothing(int sig)
{
}
#endif

static void
signal_exec(VALUE cmd, int safe, int sig)
{
    rb_thread_t *cur_th = GET_THREAD();
    volatile unsigned long old_interrupt_mask = cur_th->interrupt_mask;
    int state;

    /*
     * workaround the following race:
     * 1. signal_enque queues signal for execution
     * 2. user calls trap(sig, "IGNORE"), setting SIG_IGN
     * 3. rb_signal_exec runs on queued signal
     */
    if (IMMEDIATE_P(cmd))
	return;

    cur_th->interrupt_mask |= TRAP_INTERRUPT_MASK;
    TH_PUSH_TAG(cur_th);
    if ((state = EXEC_TAG()) == 0) {
	VALUE signum = INT2NUM(sig);
	rb_eval_cmd(cmd, rb_ary_new3(1, signum), safe);
    }
    TH_POP_TAG();
    cur_th = GET_THREAD();
    cur_th->interrupt_mask = old_interrupt_mask;

    if (state) {
	/* XXX: should be replaced with rb_threadptr_pending_interrupt_enque() */
	TH_JUMP_TAG(cur_th, state);
    }
}

void
rb_trap_exit(void)
{
    rb_vm_t *vm = GET_VM();
    VALUE trap_exit = vm->trap_list[0].cmd;

    if (trap_exit) {
	vm->trap_list[0].cmd = 0;
	signal_exec(trap_exit, vm->trap_list[0].safe, 0);
    }
}

void
rb_signal_exec(rb_thread_t *th, int sig)
{
    rb_vm_t *vm = GET_VM();
    VALUE cmd = vm->trap_list[sig].cmd;
    int safe = vm->trap_list[sig].safe;

    if (cmd == 0) {
	switch (sig) {
	  case SIGINT:
	    rb_interrupt();
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
	    rb_threadptr_signal_raise(th, sig);
	    break;
	}
    }
    else if (cmd == Qundef) {
	rb_threadptr_signal_exit(th);
    }
    else {
	signal_exec(cmd, safe, sig);
    }
}

static sighandler_t
default_handler(int sig)
{
    sighandler_t func;
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
        func = (sighandler_t)sigbus;
        break;
#endif
#ifdef SIGSEGV
      case SIGSEGV:
        func = (sighandler_t)sigsegv;
        break;
#endif
#ifdef SIGPIPE
      case SIGPIPE:
        func = sig_do_nothing;
        break;
#endif
#ifdef SIGSYS
      case SIGSYS:
        func = sig_do_nothing;
        break;
#endif
      default:
        func = SIG_DFL;
        break;
    }

    return func;
}

static sighandler_t
trap_handler(VALUE *cmd, int sig)
{
    sighandler_t func = sighandler;
    VALUE command;

    if (NIL_P(*cmd)) {
	func = SIG_IGN;
    }
    else {
	command = rb_check_string_type(*cmd);
	if (NIL_P(command) && SYMBOL_P(*cmd)) {
	    command = rb_sym2str(*cmd);
	    if (!command) rb_raise(rb_eArgError, "bad handler");
	}
	if (!NIL_P(command)) {
	    const char *cptr;
	    long len;
	    SafeStringValue(command);	/* taint check */
	    *cmd = command;
	    RSTRING_GETMEM(command, cptr, len);
	    switch (len) {
	      case 0:
                goto sig_ign;
		break;
              case 14:
		if (memcmp(cptr, "SYSTEM_DEFAULT", 14) == 0) {
                    func = SIG_DFL;
                    *cmd = 0;
		}
                break;
	      case 7:
		if (memcmp(cptr, "SIG_IGN", 7) == 0) {
sig_ign:
                    func = SIG_IGN;
                    *cmd = Qtrue;
		}
		else if (memcmp(cptr, "SIG_DFL", 7) == 0) {
sig_dfl:
                    func = default_handler(sig);
                    *cmd = 0;
		}
		else if (memcmp(cptr, "DEFAULT", 7) == 0) {
                    goto sig_dfl;
		}
		break;
	      case 6:
		if (memcmp(cptr, "IGNORE", 6) == 0) {
                    goto sig_ign;
		}
		break;
	      case 4:
		if (memcmp(cptr, "EXIT", 4) == 0) {
		    *cmd = Qundef;
		}
		break;
	    }
	}
	else {
	    rb_proc_t *proc;
	    GetProcPtr(*cmd, proc);
	    (void)proc;
	}
    }

    return func;
}

static int
trap_signm(VALUE vsig)
{
    int sig = -1;
    const char *s;

    switch (TYPE(vsig)) {
      case T_FIXNUM:
	sig = FIX2INT(vsig);
	if (sig < 0 || sig >= NSIG) {
	    rb_raise(rb_eArgError, "invalid signal number (%d)", sig);
	}
	break;

      case T_SYMBOL:
	vsig = rb_sym2str(vsig);
	s = RSTRING_PTR(vsig);
	goto str_signal;

      default:
	s = StringValuePtr(vsig);

      str_signal:
	if (strncmp(signame_prefix, s, sizeof(signame_prefix)) == 0)
	    s += 3;
	sig = signm2signo(s);
	if (sig == 0 && strcmp(s, "EXIT") != 0) {
	    long ofs = s - RSTRING_PTR(vsig);
	    if (ofs) vsig = rb_str_subseq(vsig, ofs, RSTRING_LEN(vsig)-ofs);
	    rb_raise(rb_eArgError, "unsupported signal SIG%"PRIsVALUE"", vsig);
	}
    }
    return sig;
}

static VALUE
trap(int sig, sighandler_t func, VALUE command)
{
    sighandler_t oldfunc;
    VALUE oldcmd;
    rb_vm_t *vm = GET_VM();

    /*
     * Be careful. ruby_signal() and trap_list[sig].cmd must be changed
     * atomically. In current implementation, we only need to don't call
     * RUBY_VM_CHECK_INTS().
     */
    if (sig == 0) {
	oldfunc = SIG_ERR;
    }
    else {
	oldfunc = ruby_signal(sig, func);
	if (oldfunc == SIG_ERR) rb_sys_fail_str(rb_signo2signm(sig));
    }
    oldcmd = vm->trap_list[sig].cmd;
    switch (oldcmd) {
      case 0:
      case Qtrue:
	if (oldfunc == SIG_IGN) oldcmd = rb_str_new2("IGNORE");
        else if (oldfunc == SIG_DFL) oldcmd = rb_str_new2("SYSTEM_DEFAULT");
	else if (oldfunc == sighandler) oldcmd = rb_str_new2("DEFAULT");
	else oldcmd = Qnil;
	break;
      case Qnil:
	break;
      case Qundef:
	oldcmd = rb_str_new2("EXIT");
	break;
    }

    vm->trap_list[sig].cmd = command;
    vm->trap_list[sig].safe = rb_safe_level();

    return oldcmd;
}

static int
reserved_signal_p(int signo)
{
/* Synchronous signal can't deliver to main thread */
#ifdef SIGSEGV
    if (signo == SIGSEGV)
	return 1;
#endif
#ifdef SIGBUS
    if (signo == SIGBUS)
	return 1;
#endif
#ifdef SIGILL
    if (signo == SIGILL)
	return 1;
#endif
#ifdef SIGFPE
    if (signo == SIGFPE)
	return 1;
#endif

/* used ubf internal see thread_pthread.c. */
#ifdef SIGVTALRM
    if (signo == SIGVTALRM)
	return 1;
#endif

    return 0;
}

/*
 * call-seq:
 *   Signal.trap( signal, command ) -> obj
 *   Signal.trap( signal ) {| | block } -> obj
 *
 * Specifies the handling of signals. The first parameter is a signal
 * name (a string such as ``SIGALRM'', ``SIGUSR1'', and so on) or a
 * signal number. The characters ``SIG'' may be omitted from the
 * signal name. The command or block specifies code to be run when the
 * signal is raised.
 * If the command is the string ``IGNORE'' or ``SIG_IGN'', the signal
 * will be ignored.
 * If the command is ``DEFAULT'' or ``SIG_DFL'', the Ruby's default handler
 * will be invoked.
 * If the command is ``EXIT'', the script will be terminated by the signal.
 * If the command is ``SYSTEM_DEFAULT'', the operating system's default
 * handler will be invoked.
 * Otherwise, the given command or block will be run.
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
sig_trap(int argc, VALUE *argv)
{
    int sig;
    sighandler_t func;
    VALUE cmd;

    rb_check_arity(argc, 1, 2);

    sig = trap_signm(argv[0]);
    if (reserved_signal_p(sig)) {
        const char *name = signo2signm(sig);
        if (name)
            rb_raise(rb_eArgError, "can't trap reserved signal: SIG%s", name);
        else
            rb_raise(rb_eArgError, "can't trap reserved signal: %d", sig);
    }

    if (argc == 1) {
	cmd = rb_block_proc();
	func = sighandler;
    }
    else {
	cmd = argv[1];
	func = trap_handler(&cmd, sig);
    }

    if (OBJ_TAINTED(cmd)) {
	rb_raise(rb_eSecurityError, "Insecure: tainted signal trap");
    }

    return trap(sig, func, cmd);
}

/*
 * call-seq:
 *   Signal.list -> a_hash
 *
 * Returns a list of signal names mapped to the corresponding
 * underlying signal numbers.
 *
 *   Signal.list   #=> {"EXIT"=>0, "HUP"=>1, "INT"=>2, "QUIT"=>3, "ILL"=>4, "TRAP"=>5, "IOT"=>6, "ABRT"=>6, "FPE"=>8, "KILL"=>9, "BUS"=>7, "SEGV"=>11, "SYS"=>31, "PIPE"=>13, "ALRM"=>14, "TERM"=>15, "URG"=>23, "STOP"=>19, "TSTP"=>20, "CONT"=>18, "CHLD"=>17, "CLD"=>17, "TTIN"=>21, "TTOU"=>22, "IO"=>29, "XCPU"=>24, "XFSZ"=>25, "VTALRM"=>26, "PROF"=>27, "WINCH"=>28, "USR1"=>10, "USR2"=>12, "PWR"=>30, "POLL"=>29}
 */
static VALUE
sig_list(void)
{
    VALUE h = rb_hash_new();
    const struct signals *sigs;

    for (sigs = siglist; sigs->signm; sigs++) {
	rb_hash_aset(h, rb_fstring_cstr(sigs->signm), INT2FIX(sigs->signo));
    }
    return h;
}

static int
install_sighandler(int signum, sighandler_t handler)
{
    sighandler_t old;

    old = ruby_signal(signum, handler);
    if (old == SIG_ERR) return -1;
    /* signal handler should be inherited during exec. */
    if (old != SIG_DFL) {
	ruby_signal(signum, old);
    }
    return 0;
}
#ifndef __native_client__
#  define install_sighandler(signum, handler) (install_sighandler(signum, handler) ? rb_bug(#signum) : (void)0)
#endif

#if defined(SIGCLD) || defined(SIGCHLD)
static int
init_sigchld(int sig)
{
    sighandler_t oldfunc;

    oldfunc = ruby_signal(sig, SIG_DFL);
    if (oldfunc == SIG_ERR) return -1;
    if (oldfunc != SIG_DFL && oldfunc != SIG_IGN) {
	ruby_signal(sig, oldfunc);
    }
    else {
	GET_VM()->trap_list[sig].cmd = 0;
    }
    return 0;
}
#  ifndef __native_client__
#    define init_sigchld(signum) (init_sigchld(signum) ? rb_bug(#signum) : (void)0)
#  endif
#endif

void
ruby_sig_finalize(void)
{
    sighandler_t oldfunc;

    oldfunc = ruby_signal(SIGINT, SIG_IGN);
    if (oldfunc == sighandler) {
	ruby_signal(SIGINT, SIG_DFL);
    }
}


int ruby_enable_coredump = 0;
#ifndef RUBY_DEBUG_ENV
#define ruby_enable_coredump 0
#endif

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
Init_signal(void)
{
    VALUE mSignal = rb_define_module("Signal");

    rb_define_global_function("trap", sig_trap, -1);
    rb_define_module_function(mSignal, "trap", sig_trap, -1);
    rb_define_module_function(mSignal, "list", sig_list, 0);
    rb_define_module_function(mSignal, "signame", sig_signame, 1);

    rb_define_method(rb_eSignal, "initialize", esignal_init, -1);
    rb_define_method(rb_eSignal, "signo", esignal_signo, 0);
    rb_alias(rb_eSignal, rb_intern_const("signm"), rb_intern_const("message"));
    rb_define_method(rb_eInterrupt, "initialize", interrupt_init, -1);

    /* At this time, there is no subthread. Then sigmask guarantee atomics. */
    rb_disable_interrupt();

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

    if (!ruby_enable_coredump) {
#ifdef SIGBUS
	install_sighandler(SIGBUS, (sighandler_t)sigbus);
#endif
#ifdef SIGILL
	install_sighandler(SIGILL, (sighandler_t)sigill);
#endif
#ifdef SIGSEGV
# ifdef USE_SIGALTSTACK
	rb_register_sigaltstack(GET_THREAD());
# endif
	install_sighandler(SIGSEGV, (sighandler_t)sigsegv);
#endif
    }
#ifdef SIGPIPE
    install_sighandler(SIGPIPE, sig_do_nothing);
#endif
#ifdef SIGSYS
    install_sighandler(SIGSYS, sig_do_nothing);
#endif

#if defined(SIGCLD)
    init_sigchld(SIGCLD);
#elif defined(SIGCHLD)
    init_sigchld(SIGCHLD);
#endif

    rb_enable_interrupt();
}
