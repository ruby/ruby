/************************************************

  process.c -

  $Author: matz $
  $Date: 1994/12/20 05:07:11 $
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
    if (wait_status != -1) return ST_STOP;

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
	if (*s != ' ' && !isalpha(*s) && strchr("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
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
	return INT2FIX(0);

      case -1:
	rb_sys_fail("fork(2)");
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

Fsleep(argc, argv)
    int argc;
    VALUE *argv;
{
    int beg, end;

    beg = time(0);
    if (argc == 0) {
	sleep((32767<<16)+32767);
    }
    else if (argc == 1) {
	sleep(NUM2INT(argv[0]));
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

    return INT2FIX(0);
}

static VALUE
Fproc_getpriority(obj, which, who)
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
Fproc_setpriority(obj, which, who, prio)
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
Fproc_getgid(obj)
    VALUE obj;
{
    int gid = getgid();
    return INT2FIX(gid);
}

static VALUE
Fproc_setgid(obj, id)
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
Fproc_getegid(obj)
    VALUE obj;
{
    int egid = getegid();
    return INT2FIX(egid);
}

static VALUE
Fproc_setegid(obj, egid)
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

VALUE rb_readonly_hook();
VALUE M_Process;

extern VALUE Fkill();

Init_process()
{
    extern VALUE C_Kernel;

    rb_define_variable("$$", Qnil, get_pid, Qnil, 0);
    rb_define_variable("$?", &status, Qnil, rb_readonly_hook, 0);
    rb_define_private_method(C_Kernel, "exec", Fexec, 1);
    rb_define_private_method(C_Kernel, "fork", Ffork, 0);
    rb_define_private_method(C_Kernel, "_exit", Ffork, 1);
    rb_define_private_method(C_Kernel, "wait", Fwait, 0);
    rb_define_private_method(C_Kernel, "waitpid", Fwaitpid, 2);
    rb_define_private_method(C_Kernel, "system", Fsystem, 1);
    rb_define_private_method(C_Kernel, "sleep", Fsleep, -1);

    M_Process = rb_define_module("Process");

    rb_define_single_method(M_Process, "fork", Ffork, 0);
    rb_define_single_method(M_Process, "_exit", Ffork, 1);
    rb_define_single_method(M_Process, "wait", Fwait, 0);
    rb_define_single_method(M_Process, "waitpid", Fwaitpid, 2);
    rb_define_single_method(M_Process, "kill", Fkill, -1);

    rb_define_module_function(M_Process, "pid", get_pid, 0);
    rb_define_module_function(M_Process, "ppid", get_ppid, 0);

    rb_define_module_function(M_Process, "getpgrp", Fproc_getpgrp, -2);
    rb_define_module_function(M_Process, "setpgrp", Fproc_setpgrp, 2);

    rb_define_module_function(M_Process, "getpriority", Fproc_getpriority, 2);
    rb_define_module_function(M_Process, "setpriority", Fproc_setpriority, 3);
    
    rb_define_const(M_Process, "%PRIO_PROCESS", INT2FIX(PRIO_PROCESS));
    rb_define_const(M_Process, "%PRIO_PGRP", INT2FIX(PRIO_PGRP));
    rb_define_const(M_Process, "%PRIO_USER", INT2FIX(PRIO_USER));

    rb_define_module_function(M_Process, "uid", Fproc_getuid, 0);
    rb_define_module_function(M_Process, "uid=", Fproc_setuid, 1);
    rb_define_module_function(M_Process, "gid", Fproc_getgid, 0);
    rb_define_module_function(M_Process, "gid=", Fproc_setgid, 1);
    rb_define_module_function(M_Process, "euid", Fproc_geteuid, 0);
    rb_define_module_function(M_Process, "euid=", Fproc_seteuid, 1);
    rb_define_module_function(M_Process, "egid", Fproc_getegid, 0);
    rb_define_module_function(M_Process, "egid=", Fproc_setegid, 1);
}
