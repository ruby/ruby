/************************************************

  process.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:50 $
  created at: Tue Aug 10 14:30:50 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/resource.h>
#include "st.h"
VALUE rb_readonly_hook();

static VALUE
get_pid()
{
    return INT2FIX(getpid());
}

static VALUE
get_ppid()
{
    return INT2FIX(getppid());
}

static VALUE status;

#if !defined(HAVE_WAITPID) && !defined(HAVE_WAIT4)
static st_table *pid_tbl;
#else
# define WAIT_CALL
#endif

int
rb_waitpid(pid, flags)
    int pid;
    int flags;
{
    int result, st;

#ifdef HAVE_WAITPID
    result = waitpid(pid, &st, flags);
#else
#ifdef HAVE_WAIT4
    result = wait4(pid, &st, flags, NULL);
#else
    if (pid_tbl && st_lookup(pid_tbl, pid, &st)) {
	status = INT2FIX(st);
	st_delete(pid_tbl, &pid, NULL);
	return pid;
    }

    if (flags)
	Fail("Can't do waitpid with flags");

    for (;;) {
	result = wait(&st);
	if (result < 0) return -1;
	if (result == pid) {
	    break;
	}
	if (!pid_tbl)
	    pid_tbl = st_init_table(ST_NUMCMP, ST_NUMHASH);
	st_insert(pid_tbl, pid, st);
    }
#endif
#endif
    status = INT2FIX(st);
    return result;
}

#ifndef WAIT_CALL
static int wait_pid;
static int wait_status;

static wait_each(key, value)
    int key, value;
{
    wait_pid = key;
    wait_status = value;
    return ST_DELETE;
}
#endif

static VALUE
Fwait(obj)
{
    int pid, state;

#ifndef WAIT_CALL
    wait_status = -1;
    st_foreach(pid_tbl, wait_each, NULL);
    if (wait_status != -1) {
	status = wait_status;
	return wait_pid;
    }
#endif

    if ((pid = wait(&state)) < 0) {
	if (errno == ECHILD) return Qnil;
	rb_sys_fail(Qnil);
    }
    status = INT2FIX(state);
    return INT2FIX(pid);
}

static VALUE
Fwaitpid(obj, vpid, vflags)
    VALUE obj, vpid, vflags;
{
    int pid, flags;

    if (vflags == Qnil) flags = Qnil;
    else flags = FIX2UINT(vflags);

    if ((pid = rb_waitpid(FIX2UINT(vpid), flags)) < 0)
	rb_sys_fail(Qnil);
    return INT2FIX(pid);
}

char *strtok();

rb_proc_exec(str)
    char *str;
{
    char *s = str, *t;
    char **argv, **a;

    for (s=str; *s; s++) {
	if (*s != ' ' && !isalpha(*s) && index("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
	    execl("/bin/sh", "sh", "-c", str, (char *)NULL);
	    return -1;
	}
    }
    a = argv = (char**)alloca(((s - str)/2+2)*sizeof(char*));
    s = (char*)alloca(s - str + 1);
    strcpy(s, str);
    if (*a++ = strtok(s, " \t")) {
	while (t = strtok(NULL, " \t")) {
	    *a++ = t;
	}
	*a = NULL;
    }
    if (argv[0]) {
	execvp(argv[0], argv);
    }
    return -1;
}

static VALUE
Fexec(obj, str)
    VALUE obj;
    struct RString *str;
{
    Check_Type(str, T_STRING);
    rb_proc_exec(str->ptr);
    rb_sys_fail(str->ptr);
}

static VALUE
Ffork(obj)
    VALUE obj;
{
    int pid;

    switch (pid = fork()) {
      case 0:
	return Qnil;

      case -1:
	rb_sys_fail(Qnil);
	break;

      default:
	return INT2FIX(pid);
    }
}

static VALUE
F_exit(obj, status)
    VALUE obj, status;
{
    int code = -1;

    if (FIXNUM_P(status)) {
	code = INT2FIX(status);
    }

    _exit(code);

    /* not reached */
    return Qnil;
}

void
rb_syswait(pid)
    int pid;
{
    RETSIGTYPE (*hfunc)(), (*ifunc)(), (*qfunc)();

    hfunc = signal(SIGHUP, SIG_IGN);
    ifunc = signal(SIGINT, SIG_IGN);
    qfunc = signal(SIGQUIT, SIG_IGN);

    if (rb_waitpid(pid, 0) < 0) rb_sys_fail("wait");

    signal(SIGHUP, hfunc);
    signal(SIGINT, ifunc);
    signal(SIGQUIT, qfunc);
}

static VALUE
Fsystem(obj, str)
    VALUE obj;
    struct RString *str;
{
    int pid, w;

    Check_Type(str, T_STRING);

    fflush(stdin);		/* is it really needed? */
    fflush(stdout);
    fflush(stderr);
    if (*str->ptr == '\0') return INT2FIX(0);

  retry:
    switch (pid = vfork()) {
      case 0:
	rb_proc_exec(str->ptr);
	_exit(127);
	break;			/* not reached */

      case -1:
	if (errno == EAGAIN) {
	    sleep(5);
	    goto retry;
	}
	rb_sys_fail(str->ptr);
	break;

      default:
	rb_syswait(pid);
    }

    return status;
}

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

static VALUE
Fkill(argc, argv)
    int argc;
    VALUE *argv;
{
    int sig;
    int i;

    if (argc < 3)
	Fail("wrong # of arguments -- kill(sig, pid...)");
    switch (TYPE(argv[1])) {
      case T_FIXNUM:
	sig = FIX2UINT(argv[1]);
	break;

      case T_STRING:
	{
	    int negative = 0;

	    char *s = RSTRING(argv[1])->ptr;
	    if (*s == '-') {
		negative++;
		s++;
	    }
	    if (strncmp("SIG", s, 3) == 0)
		s += 3;
	    if((sig = signm2signo(s)) == 0)
		Fail("Unrecognized signal name `%s'", s);

	    if (negative)
		sig = -sig;
	}
	break;

      default:
	Fail("bad signal type %s", rb_class2name(CLASS_OF(argv[1])));
	break;
    }

    if (sig < 0) {
	sig = -sig;
	for (i=2; i<argc; i++) {
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
	for (i=2; i<argc; i++) {
	    Check_Type(argv[i], T_FIXNUM);
	    if (kill(FIX2UINT(argv[i]), sig) < 0)
		rb_sys_fail(Qnil);
	}
    }
    return INT2FIX(i-2);
}

static VALUE trap_list[NSIG];
#ifdef SAFE_SIGHANDLE
static int trap_pending_list[NSIG];
int trap_pending;
static int trap_immediate;
#endif

void
mark_trap_list()
{
    int i;

    for (i=0; i<NSIG; i++) {
	if (trap_list[i])
	    mark(trap_list[i]);
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
    if (trap_immediate)
	rb_trap_eval(trap_list[sig]);
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

#if defined(SAFE_SIGHANDLE)
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

#ifdef HAVE_SYSCALL_H
#include <syscall.h>

#ifdef SYS_read
int
read(fd, buf, nbytes)
    int fd, nbytes;
    char *buf;
{
    int res;

    trap_immediate++;
    res = syscall(SYS_read, fd, buf, nbytes);
    trap_immediate = 0;
    return res;
}
#endif /* SYS_read */

#ifdef SYS_wait
int
wait(status)
    union wait *status;
{
    int res;

    trap_immediate++;
    res = syscall(SYS_wait, status);
    trap_immediate =0;
    return res;
}
#endif /* SYS_wait */

#ifdef SYS_sigpause
int
sigpause(mask)
    int mask;
{
    int res;

    trap_immediate++;
    res = syscall(SYS_sigpause, mask);
    trap_immediate =0;
    return res;
}
#endif /* SYS_sigpause */

/* linux syscall(select) doesn't work file. */
#if defined(SYS_select) && !defined(linux)
#include <sys/types.h>

int
select(nfds, readfds, writefds, exceptfds, timeout)
    int nfds;
    fd_set *readfds, *writefds, *exceptfds;
    struct timeval *timeout;
{
    int res;

    trap_immediate++;
    res = syscall(SYS_select, nfds, readfds, writefds, exceptfds, timeout);
    trap_immediate =0;
    return res;
}
#endif /* SYS_select */

#endif /* HAVE_SYSCALL_H */
#endif /* SAFE_SIGHANDLE */

static VALUE
Ftrap(argc, argv)
    int argc;
    VALUE *argv;
{
    RETSIGTYPE (*func)();
    VALUE command;
    int i, sig;
    int mask;

    if (argc < 3)
	Fail("wrong # of arguments -- kill(cmd, sig...)");

    /* disable interrupt */
    mask = sigblock(~0);

    func = sighandle;

    if (argv[1] == Qnil) {
	func = SIG_IGN;
	command = Qnil;
    }
    else {
	Check_Type(argv[1], T_STRING);
	command = argv[1];
	if (RSTRING(argv[1])->len == 0) {
	    func = SIG_IGN;
	}
	else if (RSTRING(argv[1])->len == 7) {
	    if (strncmp(RSTRING(argv[1])->ptr, "SIG_IGN", 7) == 0) {
		func = SIG_IGN;
	    }
	    else if (strncmp(RSTRING(argv[1])->ptr, "SIG_DFL", 7) == 0) {
		func = SIG_DFL;
	    }
	    else if (strncmp(RSTRING(argv[1])->ptr, "DEFAULT", 7) == 0) {
		func = SIG_DFL;
	    }
	}
	else if (RSTRING(argv[1])->len == 6) {
	    if (strncmp(RSTRING(argv[1])->ptr, "IGNORE", 6) == 0) {
		func = SIG_IGN;
	    }
	}
    }
    if (func == SIG_IGN || func == SIG_DFL)
	command = Qnil;

    for (i=2; i<argc; i++) {
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
	if (i < 0 || i > NSIG)
	    Fail("Invalid signal no %d", sig);

	signal(sig, sighandle);
	trap_list[sig] = command;
	/* enable at least specified signal. */
	mask &= ~sigmask(sig);
    }
    sigsetmask(mask);
    return Qnil;
}

Fsleep(argc, argv)
    int argc;
    VALUE *argv;
{
    int beg, end;

    beg = time(0);
    if (argc == 1) {
	sleep((32767<<16)+32767);
    }
    else if (argc == 2) {
	sleep(NUM2INT(argv[1]));
    }
    else {
	Fail("wrong # of arguments");
    }

    end = time(0) - beg;

    return int2inum(end);
}

static VALUE
Fproc_getpgrp(obj, args)
    VALUE obj, args;
{
    VALUE vpid;
    int pid, pgrp;

    rb_scan_args(args, "01", &vpid);
    if (vpid == Qnil) {
	pid = 0;
    }
    else {
	pid = NUM2INT(vpid);
    }

    pgrp = getpgrp(pid);
    return INT2FIX(pgrp);
}

static VALUE
Fproc_setpgrp(obj, pid, pgrp)
    VALUE obj, pid, pgrp;
{
    int ipid, ipgrp;

    ipid = NUM2INT(pid);
    ipgrp = NUM2INT(pgrp);

    if (getpgrp(ipid, ipgrp) == -1) rb_sys_fail(Qnil);

    return Qnil;
}

static VALUE
Fproc_getpriority(obj, which, who)
    VALUE obj, which, who;
{
    int prio, iwhich, iwho;

    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);

    prio = getpriority(iwhich, iwho);
    if (prio == -1) rb_sys_fail(Qnil);
    return INT2FIX(prio);
}

static VALUE
Fproc_setpriority(obj, which, who, prio)
    VALUE obj, which, who, prio;
{
    int iwhich, iwho, iprio;

    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);
    iprio  = NUM2INT(prio);

    if (setpriority(iwhich, iwho, iprio) == -1)
	rb_sys_fail(Qnil);
    return Qnil;
}

static VALUE
Fproc_getuid(obj)
    VALUE obj;
{
    int uid = getuid();
    return INT2FIX(uid);
}

static VALUE
Fproc_setuid(obj, id)
    VALUE obj, id;
{
    int uid;

    uid = NUM2INT(id);
#ifdef HAVE_SETRUID
    setruid(uid);
#else
#ifdef HAVE_SETREUID
    setreuid(uid, -1);
#else
    {
	if (geteuid() == uid)
	    setuid(uid);
	else
	    Fail("getruid not implemented");
    }
#endif
#endif
	return INT2FIX(uid);
}

static VALUE
Fproc_geteuid(obj)
    VALUE obj;
{
    int euid = geteuid();
    return INT2FIX(euid);
}

static VALUE
Fproc_seteuid(obj, euid)
    VALUE obj, euid;
{
    if (seteuid(NUM2INT(euid)) == -1)
	rb_sys_fail(Qnil);
    return euid;
}

VALUE M_Process;
Init_process()
{
    extern VALUE C_Kernel;

    rb_define_variable("$$", Qnil, get_pid, rb_readonly_hook);
    rb_define_variable("$?", &status, Qnil, rb_readonly_hook);
    rb_define_func(C_Kernel, "exec", Fexec, 1);
    rb_define_func(C_Kernel, "fork", Ffork, 0);
    rb_define_func(C_Kernel, "_exit", Ffork, 1);
    rb_define_func(C_Kernel, "wait", Fwait, 0);
    rb_define_func(C_Kernel, "waitpid", Fwaitpid, 2);
    rb_define_func(C_Kernel, "system", Fsystem, 1);
    rb_define_func(C_Kernel, "kill", Fkill, -1);
    rb_define_func(C_Kernel, "trap", Ftrap, -1);
    rb_define_func(C_Kernel, "sleep", Fsleep, -1);

    M_Process = rb_define_module("Process");

    rb_define_single_method(M_Process, "fork", Ffork, 0);
    rb_define_single_method(M_Process, "_exit", Ffork, 1);
    rb_define_single_method(M_Process, "wait", Fwait, 0);
    rb_define_single_method(M_Process, "waitpid", Fwaitpid, 2);
    rb_define_single_method(M_Process, "kill", Fkill, -1);

    rb_define_mfunc(M_Process, "pid", get_pid, 0);
    rb_define_mfunc(M_Process, "ppid", get_ppid, 0);

    rb_define_mfunc(M_Process, "getpgrp", Fproc_getpgrp, -2);
    rb_define_mfunc(M_Process, "setpgrp", Fproc_setpgrp, 2);

    rb_define_mfunc(M_Process, "getpriority", Fproc_getpriority, 2);
    rb_define_mfunc(M_Process, "setpriority", Fproc_setpriority, 3);
    
    rb_define_const(M_Process, "%PRIO_PROCESS", INT2FIX(PRIO_PROCESS));
    rb_define_const(M_Process, "%PRIO_PGRP", INT2FIX(PRIO_PGRP));
    rb_define_const(M_Process, "%PRIO_USER", INT2FIX(PRIO_USER));

    rb_define_single_method(M_Process, "uid", Fproc_getuid, 0);
    rb_define_method(M_Process, "uid", Fproc_getuid, 0);
    rb_define_single_method(M_Process, "uid=", Fproc_setuid, 1);
    rb_define_method(M_Process, "uid=", Fproc_setuid, 1);
    rb_define_single_method(M_Process, "euid", Fproc_geteuid, 0);
    rb_define_method(M_Process, "euid", Fproc_geteuid, 0);
    rb_define_single_method(M_Process, "euid=", Fproc_seteuid, 1);
    rb_define_method(M_Process, "euid=", Fproc_seteuid, 1);
}
