/************************************************

  process.c -

  $Author: matz $
  $Date: 1996/12/25 10:42:47 $
  created at: Tue Aug 10 14:30:50 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "sig.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <signal.h>
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif

#ifdef HAVE_SYS_WAIT_H
# include <sys/wait.h>
#endif
#ifdef HAVE_GETPRIORITY
# include <sys/resource.h>
#endif
#ifdef HAVE_VFORK_H
#include <vfork.h>
#endif
#include "st.h"

static VALUE
get_pid()
{
    return INT2FIX(getpid());
}

static VALUE
get_ppid()
{
#ifdef NT
    return INT2FIX(0);
#else
    return INT2FIX(getppid());
#endif
}

#ifdef NT
#define HAVE_WAITPID
#endif

VALUE last_status = Qnil;

#if !defined(HAVE_WAITPID) && !defined(HAVE_WAIT4)
static st_table *pid_tbl;
#else
# define WAIT_CALL
#endif

static int
rb_waitpid(pid, flags, st)
    int pid;
    int flags;
    int *st;
{
    int result;

#ifdef HAVE_WAITPID
  retry:
    result = waitpid(pid, st, flags);
    if (result < 0) {
	if (errno == EINTR) {
#ifdef THREAD
	    thread_schedule();
#endif
	    goto retry;
	}
	return -1;
    }
#else
#ifdef HAVE_WAIT4
  retry:
    result = wait4(pid, st, flags, NULL);
    if (result < 0) {
	if (errno == EINTR) {
#ifdef THREAD
	    thread_schedule();
#endif
	    goto retry;
	}
	return -1;
    }
#else
    if (pid_tbl && st_lookup(pid_tbl, pid, st)) {
	last_status = INT2FIX(*st);
	st_delete(pid_tbl, &pid, NULL);
	return pid;
    }

    if (flags) {
	ArgError("Can't do waitpid with flags");
    }

    for (;;) {
	result = wait(st);
	if (result < 0) {
	    if (errno == EINTR) {
#ifdef THREAD
		thread_schedule();
#endif
		continue;
	    }
	    return -1;
	}
	if (result == pid) {
	    break;
	}
	if (!pid_tbl)
	    pid_tbl = st_init_numtable();
	st_insert(pid_tbl, pid, st);
    }
#endif
#endif
    last_status = INT2FIX(*st);
    return result;
}

#ifndef WAIT_CALL
struct wait_data {
    int pid;
    int status;
}

static int
wait_each(key, value, data)
    int key, value;
    struct wait_data *data;
{
    if (data->status != -1) return ST_STOP;

    data->pid = key;
    data->status = value;
    return ST_DELETE;
}
#endif

static VALUE
f_wait()
{
    int pid, state;
#ifndef WAIT_CALL
    struct wait_data data;

    data.status = -1;
    st_foreach(pid_tbl, wait_each, &data);
    if (data.status != -1) {
	status = data.status;
	return data.pid;
    }
#endif

    while ((pid = wait(&state)) < 0) {
	if (errno == EINTR) {
#ifdef THREAD
	    thread_schedule();
#endif
	    continue;
	}
	if (errno == ECHILD) return Qnil;
	rb_sys_fail(0);
    }
    last_status = INT2FIX(state);
    return INT2FIX(pid);
}

static VALUE
f_waitpid(obj, vpid, vflags)
    VALUE obj, vpid, vflags;
{
    int pid, flags, status;

    if (NIL_P(vflags)) flags = 0;
    else flags = FIX2UINT(vflags);

    if ((pid = rb_waitpid(FIX2UINT(vpid), flags, &status)) < 0)
	rb_sys_fail(0);
    return INT2FIX(pid);
}

char *strtok();

#if defined(THREAD) && defined(HAVE_SETITIMER)
static void
before_exec()
{
    {
	struct itimerval tval;

	tval.it_interval.tv_sec = 0;
	tval.it_interval.tv_usec = 0;
	tval.it_value = tval.it_interval;
	setitimer(ITIMER_VIRTUAL, &tval, NULL);
    }
}

static void
after_exec()
{
    {
	struct itimerval tval;

	tval.it_interval.tv_sec = 1;
	tval.it_interval.tv_usec = 0;
	tval.it_value = tval.it_interval;
	setitimer(ITIMER_VIRTUAL, &tval, NULL);
    }
}
#else
#define before_exec()
#define after_exec()
#endif

extern char *dln_find_exe();

static int
proc_exec_v(argv)
    char **argv;
{
    char *prog;

    prog = dln_find_exe(argv[0], 0);
    if (!prog) {
	errno = ENOENT;
	return -1;
    }
    before_exec();
    execv(prog, argv);
    after_exec();
    return -1;
}

static int
proc_exec_n(argc, argv)
    int argc;
    VALUE *argv;
{
    char **args;
    int i;

    args = ALLOCA_N(char*, argc+1);
    for (i=0; i<argc; i++) {
	Check_Type(argv[i], T_STRING);
	args[i] = RSTRING(argv[i])->ptr;
    }
    args[i] = 0;
    if (args[0]) {
	return proc_exec_v(args);
    }
    return -1;
}

int
rb_proc_exec(str)
    char *str;
{
    char *s = str, *t;
    char **argv, **a;

    for (s=str; *s; s++) {
	if (*s != ' ' && !isalpha(*s) && strchr("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
#if defined(MSDOS)
	    system(str);
#else
	    before_exec();
	    execl("/bin/sh", "sh", "-c", str, (char *)NULL);
	    after_exec();
#endif
	    return -1;
	}
    }
    a = argv = ALLOCA_N(char*, (s-str)/2+2);
    s = ALLOCA_N(char, s-str+1);
    strcpy(s, str);
    if (*a++ = strtok(s, " \t")) {
	while (t = strtok(NULL, " \t")) {
	    *a++ = t;
	}
	*a = NULL;
    }
    if (argv[0]) {
	return proc_exec_v(argv);
    }
    errno = ENOENT;
    return -1;
}

static VALUE
f_exec(argc, argv)
    int argc;
    VALUE *argv;
{
    if (argc == 1) {
	Check_Type(argv[0], T_STRING);
	rb_proc_exec(RSTRING(argv[0])->ptr);
    }
    else {
	proc_exec_n(argc, argv);
    }
    rb_sys_fail(RSTRING(argv[0])->ptr);
}

static VALUE
f_fork(obj)
    VALUE obj;
{
    int pid;

    switch (pid = fork()) {
      case 0:
	if (iterator_p()) {
	    rb_yield(Qnil);
	    _exit(0);
	}
	return Qnil;

      case -1:
	rb_sys_fail("fork(2)");
	return Qnil;

      default:
	return INT2FIX(pid);
    }
}

static VALUE
f_exit_bang(obj, status)
    VALUE obj, status;
{
    int code = -1;

    if (FIXNUM_P(status)) {
	code = INT2FIX(status);
    }

    _exit(code);

    /* not reached */
}

void
rb_syswait(pid)
    int pid;
{
    RETSIGTYPE (*hfunc)(), (*ifunc)(), (*qfunc)();
    int status;

    hfunc = signal(SIGHUP, SIG_IGN);
    ifunc = signal(SIGINT, SIG_IGN);
    qfunc = signal(SIGQUIT, SIG_IGN);

    if (rb_waitpid(pid, 0, &status) < 0) rb_sys_fail("wait");

    signal(SIGHUP, hfunc);
    signal(SIGINT, ifunc);
    signal(SIGQUIT, qfunc);
}

static VALUE
f_system(argc, argv)
    int argc;
    VALUE *argv;
{
#ifdef NT
    VALUE cmd;
    int state;

    cmd = ary_join(ary_new4(argc, argv), str_new2(" "));

    state = do_spawn(RSTRING(cmd)->ptr);
    last_status = INT2FIX(state);

    if (state == 0) return TRUE;
    return FALSE;
#else
#if defined(DJGPP)
    VALUE cmd;
    int state;

    cmd = ary_join(ary_new4(argc, argv), str_new2(" "));

    state = system(RSTRING(cmd)->ptr);
    last_status = INT2FIX(state);

    if (state == 0) return TRUE;
    return FALSE;
#else
    int i;
    int pid;

    fflush(stdin);		/* is it really needed? */
    fflush(stdout);
    fflush(stderr);
    if (argc == 0) {
	last_status = INT2FIX(0);
	return INT2FIX(0);
    }

    for (i=0; i<argc; i++) {
	Check_Type(argv[i], T_STRING);
    }

  retry:
    switch (pid = vfork()) {
      case 0:
	if (argc == 1) {
	    rb_proc_exec(RSTRING(argv[0])->ptr);
	}
	else {
	    proc_exec_n(argc, argv);
	}
	_exit(127);
	break;			/* not reached */

      case -1:
	if (errno == EAGAIN) {
	    sleep(5);
	    goto retry;
	}
	rb_sys_fail(0);
	break;

      default:
	rb_syswait(pid);
    }

    if (last_status == INT2FIX(0)) return TRUE;
    return FALSE;
#endif
#endif
}

struct timeval time_timeval();

VALUE
f_sleep(argc, argv)
    int argc;
    VALUE *argv;
{
    int beg, end;
    int n;

    beg = time(0);
#ifdef THREAD
    if (argc == 0) {
	thread_sleep();
    }
    else if (argc == 1) {
	thread_wait_for(time_timeval(argv[0]));
    }
#else
    if (argc == 0) {
	TRAP_BEG;
	sleep((32767<<16)+32767);
	TRAP_END;
    }
    else if (argc == 1) {
	struct timeval tv;

	tv = time_timeval(argv[0]);
	TRAP_BEG;
	sleep(tv.tv_sec);
	TRAP_END;
	if (n<0) rb_sys_fail(0);
    }
#endif
    else {
	ArgError("wrong # of arguments");
    }

    end = time(0) - beg;

    return INT2FIX(end);
}

#if !defined(NT) && !defined(DJGPP)
#ifdef _POSIX_SOURCE
static VALUE
proc_getpgrp()
{
    int pgrp;

    pgrp = getpgrp();
    if (pgrp < 0) rb_sys_fail(0);
    return INT2FIX(pgrp);
}

static VALUE
proc_setpgrp(obj)
    VALUE obj;
{
    int pgrp;

    if (setpgrp() < 0) rb_sys_fail(0);
    return Qnil;
}

#else

static VALUE
proc_getpgrp(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vpid;
    int pgrp, pid;

    rb_scan_args(argc, argv, "01", &vpid);
    if (NIL_P(vpid)) pid = 0;
    else             pid = NUM2INT(vpid);
    pgrp = getpgrp(pid);
    if (pgrp < 0) rb_sys_fail(0);
    return INT2FIX(pgrp);
}

static VALUE
proc_setpgrp(obj, pid, pgrp)
    VALUE obj, pid, pgrp;
{
    int ipid, ipgrp;

    ipid = NUM2INT(pid);
    ipgrp = NUM2INT(pgrp);
    if (setpgrp(ipid, ipgrp) < 0) rb_sys_fail(0);
    return Qnil;
}
#endif

#ifdef HAVE_SETPGID
static VALUE
proc_setpgid(obj, pid, pgrp)
    VALUE obj, pid, pgrp;
{
    int ipid, ipgrp;

    ipid = NUM2INT(pid);
    ipgrp = NUM2INT(pgrp);

    if (setpgid(ipid, ipgrp) < 0) rb_sys_fail(0);
    return Qnil;
}
#endif

static VALUE
proc_getpriority(obj, which, who)
    VALUE obj, which, who;
{
#ifdef HAVE_GETPRIORITY
    int prio, iwhich, iwho;

    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);

    prio = getpriority(iwhich, iwho);
    if (prio < 0) rb_sys_fail(0);
    return INT2FIX(prio);
#else
    rb_notimplement();
#endif
}

static VALUE
proc_setpriority(obj, which, who, prio)
    VALUE obj, which, who, prio;
{
#ifdef HAVE_GETPRIORITY
    int iwhich, iwho, iprio;

    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);
    iprio  = NUM2INT(prio);

    if (setpriority(iwhich, iwho, iprio) < 0)
	rb_sys_fail(0);
    return INT2FIX(0);
#else
    rb_notimplement();
#endif
}
#endif

static VALUE
proc_getuid(obj)
    VALUE obj;
{
    int uid = getuid();
    return INT2FIX(uid);
}

static VALUE
proc_setuid(obj, id)
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
	    rb_notimplement();
    }
#endif
#endif
	return INT2FIX(uid);
}

static VALUE
proc_getgid(obj)
    VALUE obj;
{
    int gid = getgid();
    return INT2FIX(gid);
}

static VALUE
proc_setgid(obj, id)
    VALUE obj, id;
{
    int gid;

    gid = NUM2INT(id);
#ifdef HAS_SETRGID
	setrgid((GIDTYPE)gid);
#else
#ifdef HAVE_SETREGID
    setregid(gid, -1);
#else
    {
	if (getegid() == gid)
	    setgid(gid);
	else
	    rb_notimplement();
    }
#endif
#endif
	return INT2FIX(gid);
}

static VALUE
proc_geteuid(obj)
    VALUE obj;
{
    int euid = geteuid();
    return INT2FIX(euid);
}

static VALUE
proc_seteuid(obj, euid)
    VALUE obj, euid;
{
#ifdef HAVE_SETEUID
    if (seteuid(NUM2INT(euid)) < 0) rb_sys_fail(0);
#else
#ifdef HAVE_SETREUID
    if (setreuid(-1, NUM2INT(euid)) < 0) rb_sys_fail(0);
#else
    euid = NUM2INT(euid);
    if (euid == getuid())
	setuid(euid);
    else
	rb_notimplement();
#endif
#endif
    return euid;
}

static VALUE
proc_getegid(obj)
    VALUE obj;
{
    int egid = getegid();
    return INT2FIX(egid);
}

static VALUE
proc_setegid(obj, egid)
    VALUE obj, egid;
{
#ifdef HAVE_SETEGID
    if (setegid(NUM2INT(egid)) < 0) rb_sys_fail(0);
#else
#ifdef HAVE_SETREGID
    if (setregid(-1, NUM2INT(egid)) < 0) rb_sys_fail(0);
#else
    egid = NUM2INT(egid);
    if (egid == getgid())
	setgid(egid);
    else
	rb_notimplement();
#endif
#endif
    return egid;
}

VALUE mProcess;

extern VALUE f_kill();

void
Init_process()
{
    extern VALUE cKernel;

    rb_define_virtual_variable("$$", get_pid, 0);
    rb_define_readonly_variable("$?", &last_status);
#ifndef NT
    rb_define_private_method(cKernel, "exec", f_exec, -1);
    rb_define_private_method(cKernel, "fork", f_fork, 0);
    rb_define_private_method(cKernel, "exit!", f_exit_bang, 1);
    rb_define_private_method(cKernel, "system", f_system, -1);
    rb_define_private_method(cKernel, "sleep", f_sleep, -1);

    mProcess = rb_define_module("Process");

#ifdef WNOHANG
    rb_define_const(mProcess, "WNOHANG", INT2FIX(WNOHANG));
#else
    rb_define_const(mProcess, "WNOHANG", INT2FIX(0));
#endif
#ifdef WUNTRACED
    rb_define_const(mProcess, "WUNTRACED", INT2FIX(WUNTRACED));
#else
    rb_define_const(mProcess, "WUNTRACED", INT2FIX(0));
#endif
#endif

#ifndef NT
    rb_define_singleton_method(mProcess, "fork", f_fork, 0);
    rb_define_singleton_method(mProcess, "exit!", f_exit_bang, 1);
#endif
    rb_define_module_function(mProcess, "kill", f_kill, -1);
    rb_define_module_function(mProcess, "wait", f_wait, 0);
    rb_define_module_function(mProcess, "waitpid", f_waitpid, 2);

    rb_define_module_function(mProcess, "pid", get_pid, 0);
    rb_define_module_function(mProcess, "ppid", get_ppid, 0);

#if !defined(NT) && !defined(DJGPP)
#ifdef _POSIX_SOURCE
    rb_define_module_function(mProcess, "getpgrp", proc_getpgrp, 0);
    rb_define_module_function(mProcess, "setpgrp", proc_setpgrp, 0);
#else
    rb_define_module_function(mProcess, "getpgrp", proc_getpgrp, -1);
    rb_define_module_function(mProcess, "setpgrp", proc_setpgrp, 2);
#endif
#ifdef HAVE_SETPGID
    rb_define_module_function(mProcess, "setpgid", proc_setpgid, 2);
#endif

#ifdef HAVE_GETPRIORITY
    rb_define_module_function(mProcess, "getpriority", proc_getpriority, 2);
    rb_define_module_function(mProcess, "setpriority", proc_setpriority, 3);

    rb_define_const(mProcess, "PRIO_PROCESS", INT2FIX(PRIO_PROCESS));
    rb_define_const(mProcess, "PRIO_PGRP", INT2FIX(PRIO_PGRP));
    rb_define_const(mProcess, "PRIO_USER", INT2FIX(PRIO_USER));
#endif

    rb_define_module_function(mProcess, "uid", proc_getuid, 0);
    rb_define_module_function(mProcess, "uid=", proc_setuid, 1);
    rb_define_module_function(mProcess, "gid", proc_getgid, 0);
    rb_define_module_function(mProcess, "gid=", proc_setgid, 1);
    rb_define_module_function(mProcess, "euid", proc_geteuid, 0);
    rb_define_module_function(mProcess, "euid=", proc_seteuid, 1);
    rb_define_module_function(mProcess, "egid", proc_getegid, 0);
    rb_define_module_function(mProcess, "egid=", proc_setegid, 1);
#endif
}
