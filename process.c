/************************************************

  process.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:47 $
  created at: Tue Aug 10 14:30:50 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

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

#include <sys/resource.h>
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
    if (wait_status != -1) return ST_STOP;

    wait_pid = key;
    wait_status = value;
    return ST_DELETE;
}
#endif

static VALUE
f_wait()
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
f_waitpid(obj, vpid, vflags)
    VALUE obj, vpid, vflags;
{
    int pid, flags;

    if (vflags == Qnil) flags = 0;
    else flags = FIX2UINT(vflags);

    if ((pid = rb_waitpid(FIX2UINT(vpid), flags)) < 0)
	rb_sys_fail(Qnil);
    return INT2FIX(pid);
}

char *strtok();

int
rb_proc_exec(str)
    char *str;
{
    char *s = str, *t;
    char **argv, **a;

    for (s=str; *s; s++) {
	if (*s != ' ' && !isalpha(*s) && strchr("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
	    execl("/bin/sh", "sh", "-c", str, (char *)NULL);
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
	execvp(argv[0], argv);
    }
    return -1;
}

static VALUE
f_exec(obj, str)
    VALUE obj;
    struct RString *str;
{
    Check_Type(str, T_STRING);
    rb_proc_exec(str->ptr);
    rb_sys_fail(str->ptr);
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
f_system(obj, str)
    VALUE obj;
    struct RString *str;
{
#ifdef NT
    int state;

    Check_Type(str, T_STRING);
    state = do_spawn(str->ptr);
    status = INT2FIX(state);

    if (state == 0) return TRUE;
    return FALSE;
#else
    int pid;

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

    if (status == INT2FIX(0)) return TRUE;
    return FALSE;
#endif
}

VALUE
f_sleep(argc, argv)
    int argc;
    VALUE *argv;
{
    int beg, end;

    beg = time(0);
    if (argc == 0) {
	sleep((32767<<16)+32767);
    }
    else if (argc == 1) {
	TRAP_BEG;
	sleep(NUM2INT(argv[0]));
	TRAP_END;
    }
    else {
	Fail("wrong # of arguments");
    }

    end = time(0) - beg;

    return int2inum(end);
}

#ifndef NT
static VALUE
proc_getpgrp(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE vpid;
    int pid, pgrp;

    rb_scan_args(argc, argv, "01", &vpid);
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
proc_setpgrp(obj, pid, pgrp)
    VALUE obj, pid, pgrp;
{
    int ipid, ipgrp;

    ipid = NUM2INT(pid);
    ipgrp = NUM2INT(pgrp);

    if (getpgrp(ipid, ipgrp) == -1) rb_sys_fail(Qnil);

    return INT2FIX(0);
}

static VALUE
proc_getpriority(obj, which, who)
    VALUE obj, which, who;
{
#ifdef HAVE_GETPRIORITY
    int prio, iwhich, iwho;

    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);

    prio = getpriority(iwhich, iwho);
    if (prio == -1) rb_sys_fail(Qnil);
    return INT2FIX(prio);
#else
    Fail("The getpriority() function is unimplemented on this machine");
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

    if (setpriority(iwhich, iwho, iprio) == -1)
	rb_sys_fail(Qnil);
    return INT2FIX(0);
#else
    Fail("The setpriority() function is unimplemented on this machine");
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
	    Fail("getruid not implemented");
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
	    Fail("getrgid not implemented");
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
    if (seteuid(NUM2INT(euid)) == -1) rb_sys_fail(Qnil);
#else
#ifdef HAVE_SETREUID
    if (setreuid(-1, NUM2INT(euid)) == -1) rb_sys_fail(Qnil);
#else
    euid = NUM2INT(euid);
    if (euid == getuid())
	setuid(euid);
    else
	Fail("seteuid() not implemented");
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
    if (setegid(NUM2INT(egid)) == -1) rb_sys_fail(Qnil);
#else
#ifdef HAVE_SETREGID
    if (setregid(-1, NUM2INT(egid)) == -1) rb_sys_fail(Qnil);
#else
    egid = NUM2INT(egid);
    if (egid == getgid())
	setgid(egid);
    else
	Fail("setegid() not implemented");
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

    rb_define_virtual_variable("$$", get_pid, Qnil);
    rb_define_readonly_variable("$?", &status);
#ifndef NT
    rb_define_private_method(cKernel, "exec", f_exec, 1);
    rb_define_private_method(cKernel, "fork", f_fork, 0);
    rb_define_private_method(cKernel, "exit!", f_exit_bang, 1);
    rb_define_private_method(cKernel, "wait", f_wait, 0);
    rb_define_private_method(cKernel, "waitpid", f_waitpid, 2);
#endif
    rb_define_private_method(cKernel, "system", f_system, 1);
    rb_define_private_method(cKernel, "sleep", f_sleep, -1);

    mProcess = rb_define_module("Process");

#ifndef NT
    rb_define_singleton_method(mProcess, "fork", f_fork, 0);
    rb_define_singleton_method(mProcess, "exit!", f_exit_bang, 1);
    rb_define_singleton_method(mProcess, "wait", f_wait, 0);
    rb_define_singleton_method(mProcess, "waitpid", f_waitpid, 2);
    rb_define_singleton_method(mProcess, "kill", f_kill, -1);
#endif

    rb_define_module_function(mProcess, "pid", get_pid, 0);
    rb_define_module_function(mProcess, "ppid", get_ppid, 0);

#ifndef NT
    rb_define_module_function(mProcess, "getpgrp", proc_getpgrp, -1);
    rb_define_module_function(mProcess, "setpgrp", proc_setpgrp, 2);

    rb_define_module_function(mProcess, "getpriority", proc_getpriority, 2);
    rb_define_module_function(mProcess, "setpriority", proc_setpriority, 3);

    rb_define_const(mProcess, "PRIO_PROCESS", INT2FIX(PRIO_PROCESS));
    rb_define_const(mProcess, "PRIO_PGRP", INT2FIX(PRIO_PGRP));
    rb_define_const(mProcess, "PRIO_USER", INT2FIX(PRIO_USER));

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
