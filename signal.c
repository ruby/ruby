/**********************************************************************

  signal.c -

  $Author$
  created at: Tue Dec 20 10:13:44 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifdef HAVE_SYS_UIO_H
# include <sys/uio.h>
#endif

#ifdef HAVE_UCONTEXT_H
# include <ucontext.h>
#endif

#if HAVE_PTHREAD_H
# include <pthread.h>
#endif

#include "debug_counter.h"
#include "eval_intern.h"
#include "internal.h"
#include "internal/eval.h"
#include "internal/sanitizers.h"
#include "internal/signal.h"
#include "internal/string.h"
#include "internal/thread.h"
#include "ruby_atomic.h"
#include "vm_core.h"

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

#define FOREACH_SIGNAL(sig, offset) \
    for (sig = siglist + (offset); sig < siglist + numberof(siglist); ++sig)
enum { LONGEST_SIGNAME = 7 }; /* MIGRATE and RETRACT */
static const struct signals {
    char signm[LONGEST_SIGNAME + 1];
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
#if RUBY_SIGCHLD
    {"CHLD", RUBY_SIGCHLD },
    {"CLD", RUBY_SIGCHLD },
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
};

static const char signame_prefix[] = "SIG";
static const int signame_prefix_len = 3;

static int
signm2signo(VALUE *sig_ptr, int negative, int exit, int *prefix_ptr)
{
    const struct signals *sigs;
    VALUE vsig = *sig_ptr;
    const char *nm;
    long len, nmlen;
    int prefix = 0;

    if (RB_SYMBOL_P(vsig)) {
	*sig_ptr = vsig = rb_sym2str(vsig);
    }
    else if (!RB_TYPE_P(vsig, T_STRING)) {
	VALUE str = rb_check_string_type(vsig);
	if (NIL_P(str)) {
	    rb_raise(rb_eArgError, "bad signal type %s",
		     rb_obj_classname(vsig));
	}
	*sig_ptr = vsig = str;
    }

    rb_must_asciicompat(vsig);
    RSTRING_GETMEM(vsig, nm, len);
    if (memchr(nm, '\0', len)) {
	rb_raise(rb_eArgError, "signal name with null byte");
    }

    if (len > 0 && nm[0] == '-') {
	if (!negative)
	    rb_raise(rb_eArgError, "negative signal name: % "PRIsVALUE, vsig);
	prefix = 1;
    }
    else {
	negative = 0;
    }
    if (len >= prefix + signame_prefix_len) {
        if (memcmp(nm + prefix, signame_prefix, signame_prefix_len) == 0)
	    prefix += signame_prefix_len;
    }
    if (len <= (long)prefix) {
        goto unsupported;
    }

    if (prefix_ptr) *prefix_ptr = prefix;
    nmlen = len - prefix;
    nm += prefix;
    if (nmlen > LONGEST_SIGNAME) goto unsupported;
    FOREACH_SIGNAL(sigs, !exit) {
	if (memcmp(sigs->signm, nm, nmlen) == 0 &&
	    sigs->signm[nmlen] == '\0') {
	    return negative ? -sigs->signo : sigs->signo;
	}
    }

  unsupported:
    if (prefix == signame_prefix_len) {
        prefix = 0;
    }
    else if (prefix > signame_prefix_len) {
        prefix -= signame_prefix_len;
        len -= prefix;
        vsig = rb_str_subseq(vsig, prefix, len);
        prefix = 0;
    }
    else {
        len -= prefix;
        vsig = rb_str_subseq(vsig, prefix, len);
        prefix = signame_prefix_len;
    }
    rb_raise(rb_eArgError, "unsupported signal `%.*s%"PRIsVALUE"'",
             prefix, signame_prefix, vsig);
    UNREACHABLE_RETURN(0);
}

static const char*
signo2signm(int no)
{
    const struct signals *sigs;

    FOREACH_SIGNAL(sigs, 0) {
	if (sigs->signo == no)
	    return sigs->signm;
    }
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
	int prefix;
	signo = signm2signo(&sig, FALSE, FALSE, &prefix);
	if (prefix != signame_prefix_len) {
	    sig = rb_str_append(rb_str_new_cstr("SIG"), sig);
	}
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
    args[1] = rb_check_arity(argc, 0, 1) ? argv[0] : Qnil;
    return rb_call_super(2, args);
}

void rb_malloc_info_show_results(void); /* gc.c */

void
ruby_default_signal(int sig)
{
#if USE_DEBUG_COUNTER
    rb_debug_counter_show_results("killed by signal.");
#endif
    rb_malloc_info_show_results();

    signal(sig, SIG_DFL);
    raise(sig);
}

static RETSIGTYPE sighandler(int sig);
static int signal_ignored(int sig);
static void signal_enque(int sig);

VALUE
rb_f_kill(int argc, const VALUE *argv)
{
#ifndef HAVE_KILLPG
#define killpg(pg, sig) kill(-(pg), (sig))
#endif
    int sig;
    int i;
    VALUE str;

    rb_check_arity(argc, 2, UNLIMITED_ARGUMENTS);

    if (FIXNUM_P(argv[0])) {
	sig = FIX2INT(argv[0]);
    }
    else {
	str = argv[0];
	sig = signm2signo(&str, TRUE, FALSE, NULL);
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
	const rb_pid_t self = (GET_THREAD() == GET_VM()->ractor.main_thread) ? getpid() : -1;
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
		    kill(pid, sig);
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
	    rb_threadptr_check_signal(GET_VM()->ractor.main_thread);
	}
    }
    rb_thread_execute_interrupts(rb_thread_current());

    return INT2FIX(i-1);
}

static struct {
    rb_atomic_t cnt[RUBY_NSIG];
    rb_atomic_t size;
} signal_buff;
#if RUBY_SIGCHLD
volatile unsigned int ruby_nocldwait;
#endif

#define sighandler_t ruby_sighandler_t

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
/* XXX: BSD_vfprintf() uses >1500B stack and x86-64 need >5KiB stack. */
#define RUBY_SIGALTSTACK_SIZE (16*1024)

static int
rb_sigaltstack_size(void)
{
    int size = RUBY_SIGALTSTACK_SIZE;

#ifdef MINSIGSTKSZ
    {
        int minsigstksz = (int)MINSIGSTKSZ;
        if (size < minsigstksz)
            size = minsigstksz;
    }
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

static int rb_sigaltstack_size_value = 0;

void *
rb_allocate_sigaltstack(void)
{
    if (!rb_sigaltstack_size_value) {
	rb_sigaltstack_size_value = rb_sigaltstack_size();
    }
    return xmalloc(rb_sigaltstack_size_value);
}

/* alternate stack for SIGSEGV */
void *
rb_register_sigaltstack(void *altstack)
{
    stack_t newSS, oldSS;

    newSS.ss_size = rb_sigaltstack_size_value;
    newSS.ss_sp = altstack;
    newSS.ss_flags = 0;

    sigaltstack(&newSS, &oldSS); /* ignore error. */

    return newSS.ss_sp;
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
#if RUBY_SIGCHLD
      case RUBY_SIGCHLD:
	if (handler == SIG_IGN) {
	    ruby_nocldwait = 1;
# ifdef USE_SIGALTSTACK
	    if (sigact.sa_flags & SA_SIGINFO) {
		sigact.sa_sigaction = (ruby_sigaction_t*)sighandler;
	    }
	    else {
		sigact.sa_handler = sighandler;
	    }
# else
	    sigact.sa_handler = handler;
	    sigact.sa_flags = 0;
# endif
	}
	else {
	    ruby_nocldwait = 0;
	}
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
	handler = (sighandler_t)old.sa_sigaction;
    else
	handler = old.sa_handler;
    ASSUME(handler != SIG_ERR);
    return handler;
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

#if RUBY_SIGCHLD
static rb_atomic_t sigchld_hit;
/* destructive getter than simple predicate */
# define GET_SIGCHLD_HIT() ATOMIC_EXCHANGE(sigchld_hit, 0)
#else
# define GET_SIGCHLD_HIT() 0
#endif

static RETSIGTYPE
sighandler(int sig)
{
    int old_errnum = errno;

    /* the VM always needs to handle SIGCHLD for rb_waitpid */
    if (sig == RUBY_SIGCHLD) {
#if RUBY_SIGCHLD
        rb_vm_t *vm = GET_VM();
        ATOMIC_EXCHANGE(sigchld_hit, 1);

        /* avoid spurious wakeup in main thread iff nobody uses trap(:CHLD) */
        if (vm && ACCESS_ONCE(VALUE, vm->trap_list.cmd[sig])) {
            signal_enque(sig);
        }
#endif
    }
    else {
        signal_enque(sig);
    }
    rb_thread_wakeup_timer_thread(sig);
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
NORETURN(void rb_ec_stack_overflow(rb_execution_context_t *ec, int crit));
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
#if defined(HAVE_PTHREAD_SIGMASK)
# define ruby_sigunmask pthread_sigmask
#elif defined(HAVE_SIGPROCMASK)
# define ruby_sigunmask sigprocmask
#endif
static void
reset_sigmask(int sig)
{
#if defined(ruby_sigunmask)
    sigset_t mask;
#endif
    clear_received_signal();
#if defined(ruby_sigunmask)
    sigemptyset(&mask);
    sigaddset(&mask, sig);
    if (ruby_sigunmask(SIG_UNBLOCK, &mask, NULL)) {
	rb_bug_errno(STRINGIZE(ruby_sigunmask)":unblock", errno);
    }
#endif
}

# ifdef USE_UCONTEXT_REG
static void
check_stack_overflow(int sig, const uintptr_t addr, const ucontext_t *ctx)
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
#   if __DARWIN_UNIX03
#     define MCTX_SS_REG(reg) __ss.__##reg
#   else
#     define MCTX_SS_REG(reg) ss.reg
#   endif
#   if defined(__LP64__)
    const uintptr_t sp = mctx->MCTX_SS_REG(rsp);
    const uintptr_t bp = mctx->MCTX_SS_REG(rbp);
#   else
    const uintptr_t sp = mctx->MCTX_SS_REG(esp);
    const uintptr_t bp = mctx->MCTX_SS_REG(ebp);
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
        (sp_page <= fault_page && fault_page <= bp_page)) {
	rb_execution_context_t *ec = GET_EC();
	int crit = FALSE;
	if ((uintptr_t)ec->tag->buf / pagesize <= fault_page + 1) {
	    /* drop the last tag if it is close to the fault,
	     * otherwise it can cause stack overflow again at the same
	     * place. */
	    ec->tag = ec->tag->prev;
	    crit = TRUE;
	}
	reset_sigmask(sig);
	rb_ec_stack_overflow(ec, crit);
    }
}
# else
static void
check_stack_overflow(int sig, const void *addr)
{
    int ruby_stack_overflowed_p(const rb_thread_t *, const void *);
    rb_thread_t *th = GET_THREAD();
    if (ruby_stack_overflowed_p(th, addr)) {
	reset_sigmask(sig);
	rb_ec_stack_overflow(th->ec, FALSE);
    }
}
# endif
# ifdef _WIN32
#   define CHECK_STACK_OVERFLOW() check_stack_overflow(sig, 0)
# else
#   define FAULT_ADDRESS info->si_addr
#   ifdef USE_UCONTEXT_REG
#     define CHECK_STACK_OVERFLOW() check_stack_overflow(sig, (uintptr_t)FAULT_ADDRESS, ctx)
#   else
#     define CHECK_STACK_OVERFLOW() check_stack_overflow(sig, FAULT_ADDRESS)
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

static sighandler_t default_sigbus_handler;
NORETURN(static ruby_sigaction_t sigbus);

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
    rb_bug_for_fatal_signal(default_sigbus_handler, sig, SIGINFO_CTX, "Bus Error" MESSAGE_FAULT_ADDRESS);
}
#endif

#ifdef SIGSEGV

static sighandler_t default_sigsegv_handler;
NORETURN(static ruby_sigaction_t sigsegv);

static RETSIGTYPE
sigsegv(int sig SIGINFO_ARG)
{
    check_reserved_signal("SEGV");
    CHECK_STACK_OVERFLOW();
    rb_bug_for_fatal_signal(default_sigsegv_handler, sig, SIGINFO_CTX, "Segmentation fault" MESSAGE_FAULT_ADDRESS);
}
#endif

#ifdef SIGILL

static sighandler_t default_sigill_handler;
NORETURN(static ruby_sigaction_t sigill);

static RETSIGTYPE
sigill(int sig SIGINFO_ARG)
{
    check_reserved_signal("ILL");
#if defined __APPLE__
    CHECK_STACK_OVERFLOW();
#endif
    rb_bug_for_fatal_signal(default_sigill_handler, sig, SIGINFO_CTX, "Illegal instruction" MESSAGE_FAULT_ADDRESS);
}
#endif

#ifndef __sun
NORETURN(static void ruby_abort(void));
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

static int
signal_exec(VALUE cmd, int sig)
{
    rb_execution_context_t *ec = GET_EC();
    volatile rb_atomic_t old_interrupt_mask = ec->interrupt_mask;
    enum ruby_tag_type state;

    /*
     * workaround the following race:
     * 1. signal_enque queues signal for execution
     * 2. user calls trap(sig, "IGNORE"), setting SIG_IGN
     * 3. rb_signal_exec runs on queued signal
     */
    if (IMMEDIATE_P(cmd))
	return FALSE;

    ec->interrupt_mask |= TRAP_INTERRUPT_MASK;
    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
	VALUE signum = INT2NUM(sig);
        rb_eval_cmd_kw(cmd, rb_ary_new3(1, signum), RB_NO_KEYWORDS);
    }
    EC_POP_TAG();
    ec = GET_EC();
    ec->interrupt_mask = old_interrupt_mask;

    if (state) {
	/* XXX: should be replaced with rb_threadptr_pending_interrupt_enque() */
	EC_JUMP_TAG(ec, state);
    }
    return TRUE;
}

void
rb_vm_trap_exit(rb_vm_t *vm)
{
    VALUE trap_exit = vm->trap_list.cmd[0];

    if (trap_exit) {
	vm->trap_list.cmd[0] = 0;
        signal_exec(trap_exit, 0);
    }
}

void ruby_waitpid_all(rb_vm_t *); /* process.c */

void
ruby_sigchld_handler(rb_vm_t *vm)
{
    if (SIGCHLD_LOSSY || GET_SIGCHLD_HIT()) {
        ruby_waitpid_all(vm);
    }
}

/* returns true if a trap handler was run, false otherwise */
int
rb_signal_exec(rb_thread_t *th, int sig)
{
    rb_vm_t *vm = GET_VM();
    VALUE cmd = vm->trap_list.cmd[sig];

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
        return signal_exec(cmd, sig);
    }
    return FALSE;
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
#if RUBY_SIGCHLD
      case RUBY_SIGCHLD:
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
            StringValue(command);
	    *cmd = command;
	    RSTRING_GETMEM(command, cptr, len);
	    switch (len) {
              sig_ign:
                func = SIG_IGN;
                *cmd = Qtrue;
                break;
              sig_dfl:
                func = default_handler(sig);
                *cmd = 0;
                break;
	      case 0:
                goto sig_ign;
		break;
              case 14:
		if (memcmp(cptr, "SYSTEM_DEFAULT", 14) == 0) {
                    if (sig == RUBY_SIGCHLD) {
                        goto sig_dfl;
                    }
                    func = SIG_DFL;
                    *cmd = 0;
		}
                break;
	      case 7:
		if (memcmp(cptr, "SIG_IGN", 7) == 0) {
                    goto sig_ign;
		}
		else if (memcmp(cptr, "SIG_DFL", 7) == 0) {
                    goto sig_dfl;
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

    if (FIXNUM_P(vsig)) {
	sig = FIX2INT(vsig);
	if (sig < 0 || sig >= NSIG) {
	    rb_raise(rb_eArgError, "invalid signal number (%d)", sig);
	}
    }
    else {
	sig = signm2signo(&vsig, FALSE, TRUE, NULL);
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
     * Be careful. ruby_signal() and trap_list.cmd[sig] must be changed
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
    oldcmd = vm->trap_list.cmd[sig];
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

    ACCESS_ONCE(VALUE, vm->trap_list.cmd[sig]) = command;

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
sig_trap(int argc, VALUE *argv, VALUE _)
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
sig_list(VALUE _)
{
    VALUE h = rb_hash_new();
    const struct signals *sigs;

    FOREACH_SIGNAL(sigs, 0) {
	rb_hash_aset(h, rb_fstring_cstr(sigs->signm), INT2FIX(sigs->signo));
    }
    return h;
}

#define INSTALL_SIGHANDLER(cond, signame, signum) do {	\
	static const char failed[] = "failed to install "signame" handler"; \
	if (!(cond)) break; \
	if (reserved_signal_p(signum)) rb_bug(failed); \
	perror(failed); \
    } while (0)
static int
install_sighandler_core(int signum, sighandler_t handler, sighandler_t *old_handler)
{
    sighandler_t old;

    old = ruby_signal(signum, handler);
    if (old == SIG_ERR) return -1;
    if (old_handler) {
        *old_handler = (old == SIG_DFL || old == SIG_IGN) ? 0 : old;
    }
    else {
        /* signal handler should be inherited during exec. */
        if (old != SIG_DFL) {
            ruby_signal(signum, old);
        }
    }
    return 0;
}

#  define install_sighandler(signum, handler) \
    INSTALL_SIGHANDLER(install_sighandler_core(signum, handler, NULL), #signum, signum)
#  define force_install_sighandler(signum, handler, old_handler) \
    INSTALL_SIGHANDLER(install_sighandler_core(signum, handler, old_handler), #signum, signum)

#if RUBY_SIGCHLD
static int
init_sigchld(int sig)
{
    sighandler_t oldfunc;
    sighandler_t func = sighandler;

    oldfunc = ruby_signal(sig, SIG_DFL);
    if (oldfunc == SIG_ERR) return -1;
    ruby_signal(sig, func);
    ACCESS_ONCE(VALUE, GET_VM()->trap_list.cmd[sig]) = 0;

    return 0;
}

#    define init_sigchld(signum) \
    INSTALL_SIGHANDLER(init_sigchld(signum), #signum, signum)
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
	force_install_sighandler(SIGBUS, (sighandler_t)sigbus, &default_sigbus_handler);
#endif
#ifdef SIGILL
	force_install_sighandler(SIGILL, (sighandler_t)sigill, &default_sigill_handler);
#endif
#ifdef SIGSEGV
	RB_ALTSTACK_INIT(GET_VM()->main_altstack, rb_allocate_sigaltstack());
	force_install_sighandler(SIGSEGV, (sighandler_t)sigsegv, &default_sigsegv_handler);
#endif
    }
#ifdef SIGPIPE
    install_sighandler(SIGPIPE, sig_do_nothing);
#endif
#ifdef SIGSYS
    install_sighandler(SIGSYS, sig_do_nothing);
#endif

#if RUBY_SIGCHLD
    init_sigchld(RUBY_SIGCHLD);
#endif

    rb_enable_interrupt();
}

#if defined(HAVE_GRANTPT)
extern int grantpt(int);
#else
static int
fake_grantfd(int masterfd)
{
    errno = ENOSYS;
    return -1;
}
#define grantpt(fd) fake_grantfd(fd)
#endif

int
rb_grantpt(int masterfd)
{
    if (RUBY_SIGCHLD) {
        rb_vm_t *vm = GET_VM();
        int ret, e;

        /*
         * Prevent waitpid calls from Ruby by taking waitpid_lock.
         * Pedantically, grantpt(3) is undefined if a non-default
         * SIGCHLD handler is defined, but preventing conflicting
         * waitpid calls ought to be sufficient.
         *
         * We could install the default sighandler temporarily, but that
         * could cause SIGCHLD to be missed by other threads.  Blocking
         * SIGCHLD won't work here, either, unless we stop and restart
         * timer-thread (as only timer-thread sees SIGCHLD), but that
         * seems like overkill.
         */
        rb_nativethread_lock_lock(&vm->waitpid_lock);
        {
            ret = grantpt(masterfd); /* may spawn `pt_chown' and wait on it */
            if (ret < 0) e = errno;
        }
        rb_nativethread_lock_unlock(&vm->waitpid_lock);

        if (ret < 0) errno = e;
        return ret;
    }
    else {
        return grantpt(masterfd);
    }
}
