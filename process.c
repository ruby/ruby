/************************************************

  process.c -

  $Author$
  $Date$
  created at: Tue Aug 10 14:30:50 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "sig.h"
#include <stdio.h>
#include <errno.h>
#include <ctype.h>
#include <signal.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifndef NT
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif
#endif /* NT */

struct timeval time_timeval();

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
#if defined(THREAD) && (defined(HAVE_WAITPID) || defined(HAVE_WAIT4))
    int oflags = flags;
    if (!thread_alone()) {	/* there're other threads to run */
	flags |= WNOHANG;
    }
#endif

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
#ifdef THREAD
    if (result == 0) {
	if (oflags & WNOHANG) return 0;
	thread_schedule();
	if (thread_alone()) flags = oflags;
	goto retry;
    }
#endif
#else
#ifdef HAVE_WAIT4
  retry:

    result = wait4(pid, st, flags, NULL);
    if (result < 0) {
	if (errno == EINTR) {
	    goto retry;
	}
	return -1;
    }
#ifdef THREAD
    if (result == 0) {
	if (oflags & WNOHANG) return 0;
	thread_schedule();
	if (thread_alone()) flags = oflags;
	goto retry;
    }
#endif
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
};

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
	last_status = data.status;
	return INT2FIX(data.pid);
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
    struct itimerval tval;

    tval.it_interval.tv_sec = 0;
    tval.it_interval.tv_usec = 0;
    tval.it_value = tval.it_interval;
    setitimer(ITIMER_VIRTUAL, &tval, NULL);
}

static void
after_exec()
{
    struct itimerval tval;

    tval.it_interval.tv_sec = 0;
    tval.it_interval.tv_usec = 100000;
    tval.it_value = tval.it_interval;
    setitimer(ITIMER_VIRTUAL, &tval, NULL);
}
#else
#define before_exec()
#define after_exec()
#endif

extern char *dln_find_exe();
int env_path_tainted();

static void
security(str)
    char *str;
{
    extern VALUE eSecurityError;

    if (rb_safe_level() > 0) {
	if (env_path_tainted()) {
	    Raise(eSecurityError, "Insecure PATH - %s", str);
	}
    }
}

static int
proc_exec_v(argv, prog)
    char **argv;
    char *prog;
{
    if (prog) {
	security(prog);
    }
    else {
	security(argv[0]);
	prog = dln_find_exe(argv[0], 0);
	if (!prog) {
	    errno = ENOENT;
	    return -1;
	}
    }
#if (defined(MSDOS) && !defined(DJGPP)) || defined(__human68k__)
    {
#if defined(__human68k__)
#define COMMAND "command.x"
#else
#define COMMAND "command.com"
#endif
	char *extension;

	if ((extension = strrchr(prog, '.')) != NULL && strcasecmp(extension, ".bat") == 0) {
	    char **new_argv;
	    char *p;
	    int n;

	    for (n = 0; argv[n]; n++)
		/* no-op */;
	    new_argv = ALLOCA_N(char *, n + 2);
	    for (; n > 0; n--)
		new_argv[n + 1] = argv[n];
	    new_argv[1] = strcpy(ALLOCA_N(char, strlen(argv[0]) + 1), argv[0]);
	    for (p = new_argv[1]; *p != '\0'; p++)
		if (*p == '/')
		    *p = '\\';
	    new_argv[0] = COMMAND;
	    argv = new_argv;
	    prog = dln_find_exe(argv[0], 0);
	    if (!prog) {
		errno = ENOENT;
		return -1;
	    }
	}
    }
#endif /* MSDOS or __human68k__ */
    before_exec();
    execv(prog, argv);
    after_exec();
    return -1;
}

static int
proc_exec_n(argc, argv, progv)
    int argc;
    VALUE *argv;
    VALUE progv;
{
    char *prog = 0;
    char **args;
    int i;

    if (progv) {
	Check_SafeStr(progv);
	prog = RSTRING(progv)->ptr;
    }
    args = ALLOCA_N(char*, argc+1);
    for (i=0; i<argc; i++) {
	Check_SafeStr(argv[i]);
	args[i] = RSTRING(argv[i])->ptr;
    }
    args[i] = 0;
    if (args[0]) {
	return proc_exec_v(args, prog);
    }
    return -1;
}

int
rb_proc_exec(str)
    char *str;
{
    char *s = str, *t;
    char **argv, **a;

    security(str);
    for (s=str; *s; s++) {
	if (*s != ' ' && !isalpha(*s) && strchr("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
#if defined(MSDOS)
	    int state;
	    before_exec();
	    state = system(str);
	    after_exec();
	    if (state != -1)
		exit(state);
#else
#if defined(__human68k__)
	    char *shell = dln_find_exe("sh", 0);
	    int state = -1;
	    before_exec();
	    if (shell)
		execl(shell, "sh", "-c", str, (char *) NULL);
	    else
		state = system(str);
	    after_exec();
	    if (state != -1)
		exit(state);
#else
	    before_exec();
	    execl("/bin/sh", "sh", "-c", str, (char *)NULL);
	    after_exec();
#endif
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
	return proc_exec_v(argv, 0);
    }
    errno = ENOENT;
    return -1;
}

#if defined(__human68k__)
static int
proc_spawn_v(argv, prog)
    char **argv;
    char *prog;
{
    char *extension;
    int state;

    if (prog) {
	security(prog);
    }
    else {
	security(argv[0]);
	prog = dln_find_exe(argv[0], 0);
	if (!prog)
	    return -1;
    }

    if ((extension = strrchr(prog, '.')) != NULL && strcasecmp(extension, ".bat") == 0) {
	char **new_argv;
	char *p;
	int n;

	for (n = 0; argv[n]; n++)
	    /* no-op */;
	new_argv = ALLOCA_N(char *, n + 2);
	for (; n > 0; n--)
	    new_argv[n + 1] = argv[n];
	new_argv[1] = strcpy(ALLOCA_N(char, strlen(argv[0]) + 1), argv[0]);
	for (p = new_argv[1]; *p != '\0'; p++)
	    if (*p == '/')
		*p = '\\';
	new_argv[0] = COMMAND;
	argv = new_argv;
	prog = dln_find_exe(argv[0], 0);
	if (!prog) {
	    errno = ENOENT;
	    return -1;
	}
    }
    before_exec();
    state = spawnv(P_WAIT, prog, argv);
    after_exec();    
    return state;
}

static int
proc_spawn_n(argc, argv, prog)
    int argc;
    VALUE *argv;
    VALUE prog;
{
    char **args;
    int i;

    args = ALLOCA_N(char *, argc + 1);
    for (i = 0; i < argc; i++) {
	Check_SafeStr(argv[i]);
	args[i] = RSTRING(argv[i])->ptr;
    }
    Check_SafeStr(prog);
    args[i] = (char *) 0;
    if (args[0])
	return proc_spawn_v(args, RSTRING(prog)->ptr);
    return -1;
}

static int
proc_spawn(str)
    char *str;
{
    char *s = str, *t;
    char **argv, **a;
    int state;

    for (s = str; *s; s++) {
	if (*s != ' ' && !isalpha(*s) && strchr("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
	    char *shell = dln_find_exe("sh", 0);
	    before_exec();
	    state = shell ? spawnl(P_WAIT, shell, "sh", "-c", str, (char *) NULL) : system(str) ;
	    after_exec();
	    return state;
	}
    }
    a = argv = ALLOCA_N(char *, (s - str) / 2 + 2);
    s = ALLOCA_N(char, s - str + 1);
    strcpy(s, str);
    if (*a++ = strtok(s, " \t")) {
	while (t = strtok(NULL, " \t"))
	    *a++ = t;
	*a = NULL;
    }
    return argv[0] ? proc_spawn_v(argv, 0) : -1 ;
}
#endif /* __human68k__ */

static VALUE
f_exec(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE prog = 0;

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    ArgError("wrong first argument");
	}
	prog = RARRAY(argv[0])->ptr[0];
	argv[0] = RARRAY(argv[0])->ptr[1];
    }

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    ArgError("wrong first argument");
	}
	prog = RARRAY(argv[0])->ptr[0];
	argv[0] = RARRAY(argv[0])->ptr[1];
    }
    if (argc == 1 && prog == 0) {
	Check_SafeStr(argv[0]);
	rb_proc_exec(RSTRING(argv[0])->ptr);
    }
    else {
	proc_exec_n(argc, argv, prog);
    }
    rb_sys_fail(RSTRING(argv[0])->ptr);
}

static VALUE
f_fork(obj)
    VALUE obj;
{
#if !defined(__human68k__)
    int pid;

    rb_secure(2);
    switch (pid = fork()) {
      case 0:
#ifdef linux
	after_exec();
#endif
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
#else
    rb_notimplement();
#endif
}

static VALUE
f_exit_bang(obj, status)
    VALUE obj, status;
{
    int code = -1;

    rb_secure(2);
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
    RETSIGTYPE (*hfunc)(), (*qfunc)(), (*ifunc)();
    int status;

#ifdef SIGHUP
    hfunc = signal(SIGHUP, SIG_IGN);
#endif
#ifdef SIGQUIT
    qfunc = signal(SIGQUIT, SIG_IGN);
#endif
    ifunc = signal(SIGINT, SIG_IGN);

    if (rb_waitpid(pid, 0, &status) < 0) rb_sys_fail("wait");

#ifdef SIGHUP
    signal(SIGHUP, hfunc);
#endif
#ifdef SIGQUIT
    signal(SIGQUIT, qfunc);
#endif
    signal(SIGINT, ifunc);
}

static VALUE
f_system(argc, argv)
    int argc;
    VALUE *argv;
{
#ifdef NT
    VALUE cmd;
    int state;

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    ArgError("wrong first argument");
	}
	argv[0] = RARRAY(argv[0])->ptr[0];
    }
    cmd = ary_join(ary_new4(argc, argv), str_new2(" "));

    Check_SafeStr(cmd);
    state = do_spawn(RSTRING(cmd)->ptr);
    last_status = INT2FIX(state);

    if (state == 0) return TRUE;
    return FALSE;
#else
#if defined(DJGPP)
    VALUE cmd;
    int state;

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    ArgError("wrong first argument");
	}
	argv[0] = RARRAY(argv[0])->ptr[0];
    }
    cmd = ary_join(ary_new4(argc, argv), str_new2(" "));

    Check_SafeStr(cmd);
    state = system(RSTRING(cmd)->ptr);
    last_status = INT2FIX(state);

    if (state == 0) return TRUE;
    return FALSE;
#else
#if defined(__human68k__)
    VALUE prog = 0;
    int i;
    int state;

    fflush(stdin);
    fflush(stdout);
    fflush(stderr);
    if (argc == 0) {
	last_status = INT2FIX(0);
	return INT2FIX(0);
    }

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    ArgError("wrong first argument");
	}
	prog = RARRAY(argv[0])->ptr[0];
	argv[0] = RARRAY(argv[0])->ptr[1];
    }

    if (argc == 1 && prog == 0) {
	state = proc_spawn(RSTRING(argv[0])->ptr);
    }
    else {
	state = proc_spawn_n(argc, argv, prog);
    }
    last_status = state == -1 ? INT2FIX(127) : INT2FIX(state);

    return state == 0 ? TRUE : FALSE ;
#else
    VALUE prog = 0;
    int i;
    int pid;

    fflush(stdin);		/* is it really needed? */
    fflush(stdout);
    fflush(stderr);
    if (argc == 0) {
	last_status = INT2FIX(0);
	return INT2FIX(0);
    }

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    ArgError("wrong first argument");
	}
	prog = RARRAY(argv[0])->ptr[0];
	argv[0] = RARRAY(argv[0])->ptr[1];
    }

  retry:
    switch (pid = vfork()) {
      case 0:
	if (argc == 1 && prog == 0) {
	    rb_proc_exec(RSTRING(argv[0])->ptr);
	}
	else {
	    proc_exec_n(argc, argv, prog);
	}
	_exit(127);
	break;			/* not reached */

      case -1:
	if (errno == EAGAIN) {
#ifdef THREAD
	    thread_sleep(1);
#else
	    sleep(1);
#endif
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
#endif
}

static VALUE
f_sleep(argc, argv)
    int argc;
    VALUE *argv;
{
    int beg, end;

    beg = time(0);
#ifdef THREAD
    if (argc == 0) {
	thread_sleep_forever();
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
	int n;

	tv = time_timeval(argv[0]);
	TRAP_BEG;
	n = select(0, 0, 0, 0, &tv);
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

#if !defined(NT) && !defined(DJGPP) && !defined(__human68k__)
static VALUE
proc_getpgrp(argc, argv)
    int argc;
    VALUE *argv;
{
    int pgrp;
#ifdef BSD_GETPGRP
    VALUE vpid;
    int pid;

    rb_scan_args(argc, argv, "01", &vpid);
    pid = NUM2INT(vpid);
    pgrp = BSD_GETPGRP(pid);
#else
    rb_scan_args(argc, argv, "0");
    pgrp = getpgrp();
#endif
    if (pgrp < 0) rb_sys_fail(0);
    return INT2FIX(pgrp);
}

static VALUE
proc_setpgrp(argc, argv)
    int argc;
    VALUE *argv;
{
#ifdef BSD_SETPGRP
    VALUE pid, pgrp;
    int ipid, ipgrp;

    rb_scan_args(argc, argv, "02", &pid, &pgrp);

    ipid = NUM2INT(pid);
    ipgrp = NUM2INT(pgrp);
    if (BSD_SETPGRP(ipid, ipgrp) < 0) rb_sys_fail(0);
#else
    rb_scan_args(argc, argv, "0");
    if (setpgrp() < 0) rb_sys_fail(0);
#endif
    return Qnil;
}

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
    rb_define_virtual_variable("$$", get_pid, 0);
    rb_define_readonly_variable("$?", &last_status);
    rb_define_global_function("exec", f_exec, -1);
#ifndef NT
    rb_define_global_function("fork", f_fork, 0);
#endif
    rb_define_global_function("exit!", f_exit_bang, 1);
    rb_define_global_function("system", f_system, -1);
    rb_define_global_function("sleep", f_sleep, -1);

    mProcess = rb_define_module("Process");

#if !defined(NT) && !defined(DJGPP)
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
#endif
    rb_define_singleton_method(mProcess, "exit!", f_exit_bang, 1);
    rb_define_module_function(mProcess, "kill", f_kill, -1);
#ifndef NT
    rb_define_module_function(mProcess, "wait", f_wait, 0);
    rb_define_module_function(mProcess, "waitpid", f_waitpid, 2);

    rb_define_module_function(mProcess, "pid", get_pid, 0);
    rb_define_module_function(mProcess, "ppid", get_ppid, 0);
#endif

#if !defined(NT) && !defined(DJGPP) && !defined(__human68k__)
    rb_define_module_function(mProcess, "getpgrp", proc_getpgrp, -1);
    rb_define_module_function(mProcess, "setpgrp", proc_setpgrp, -1);
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
