/**********************************************************************

  process.c -

  $Author$
  $Date$
  created at: Tue Aug 10 14:30:50 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "rubysig.h"
#include <stdio.h>
#include <errno.h>
#include <signal.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifdef __DJGPP__
#include <process.h>
#endif

#include <time.h>
#include <ctype.h>

#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif
#ifndef EXIT_FAILURE
#define EXIT_FAILURE 1
#endif

struct timeval rb_time_interval _((VALUE));

#ifdef HAVE_SYS_WAIT_H
# include <sys/wait.h>
#endif
#ifdef HAVE_GETPRIORITY
# include <sys/resource.h>
#endif
#include "st.h"

#ifdef __EMX__
#undef HAVE_GETPGRP
#endif

#ifdef HAVE_SYS_TIMES_H
#include <sys/times.h>
#endif

#ifdef HAVE_GRP_H
#include <grp.h>
#endif

#if defined(HAVE_TIMES) || defined(_WIN32)
static VALUE S_Tms;
#endif

#ifndef WIFEXITED
#define WIFEXITED(w)    (((w) & 0xff) == 0)
#endif
#ifndef WIFSIGNALED
#define WIFSIGNALED(w)  (((w) & 0x7f) > 0 && (((w) & 0x7f) < 0x7f))
#endif
#ifndef WIFSTOPPED
#define WIFSTOPPED(w)   (((w) & 0xff) == 0x7f)
#endif
#ifndef WEXITSTATUS
#define WEXITSTATUS(w)  (((w) >> 8) & 0xff)
#endif
#ifndef WTERMSIG
#define WTERMSIG(w)     ((w) & 0x7f)
#endif
#ifndef WSTOPSIG
#define WSTOPSIG        WEXITSTATUS
#endif

#if defined(__APPLE__) && ( defined(__MACH__) || defined(__DARWIN__) ) && !defined(__MacOS_X__)
#define __MacOS_X__ 1
#endif

#if defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__bsdi__)
#define HAVE_44BSD_SETUID 1
#define HAVE_44BSD_SETGID 1
#endif

#if defined(__MacOS_X__) || defined(__bsdi__)
#define BROKEN_SETREUID 1
#define BROKEN_SETREGID 1
#endif

#if defined(HAVE_44BSD_SETUID) || defined(__MacOS_X__)
#if !defined(USE_SETREUID) && !defined(BROKEN_SETREUID)
#define OBSOLETE_SETREUID 1
#endif
#if !defined(USE_SETREGID) && !defined(BROKEN_SETREGID)
#define OBSOLETE_SETREGID 1
#endif
#endif

static VALUE
get_pid()
{
    return INT2FIX(getpid());
}

static VALUE
get_ppid()
{
#ifdef _WIN32
    return INT2FIX(0);
#else
    return INT2FIX(getppid());
#endif
}

static VALUE rb_cProcStatus;
VALUE rb_last_status = Qnil;

static void
last_status_set(status, pid)
    int status, pid;
{
    rb_last_status = rb_obj_alloc(rb_cProcStatus);
    rb_iv_set(rb_last_status, "status", INT2FIX(status));
    rb_iv_set(rb_last_status, "pid", INT2FIX(pid));
}

static VALUE
pst_to_i(st)
    VALUE st;
{
    return rb_iv_get(st, "status");
}

static VALUE
pst_to_s(st)
    VALUE st;
{
    return rb_fix2str(pst_to_i(st), 10);
}

static VALUE
pst_pid(st)
    VALUE st;
{
    return rb_iv_get(st, "pid");
}

static VALUE
pst_inspect(st)
    VALUE st;
{
    VALUE pid;
    int status;
    VALUE str;
    char buf[256];

    pid = pst_pid(st);
    status = NUM2INT(st);

    snprintf(buf, sizeof(buf), "#<%s: pid=%ld", rb_class2name(CLASS_OF(st)), NUM2LONG(pid));
    str = rb_str_new2(buf);
    if (WIFSTOPPED(status)) {
	int stopsig = WSTOPSIG(status);
	const char *signame = ruby_signal_name(stopsig);
	if (signame) {
	    snprintf(buf, sizeof(buf), ",stopped(SIG%s=%d)", signame, stopsig);
	}
	else {
	    snprintf(buf, sizeof(buf), ",stopped(%d)", stopsig);
	}
	rb_str_cat2(str, buf);
    }
    if (WIFSIGNALED(status)) {
	int termsig = WTERMSIG(status);
	const char *signame = ruby_signal_name(termsig);
	if (signame) {
	    snprintf(buf, sizeof(buf), ",signaled(SIG%s=%d)", signame, termsig);
	}
	else {
	    snprintf(buf, sizeof(buf), ",signaled(%d)", termsig);
	}
	rb_str_cat2(str, buf);
    }
    if (WIFEXITED(status)) {
	snprintf(buf, sizeof(buf), ",exited(%d)", WEXITSTATUS(status));
	rb_str_cat2(str, buf);
    }
#ifdef WCOREDUMP
    if (WCOREDUMP(status)) {
	rb_str_cat2(str, ",coredumped");
    }
#endif
    rb_str_cat2(str, ">");
    return str;
}

static VALUE
pst_equal(st1, st2)
    VALUE st1, st2;
{
    if (st1 == st2) return Qtrue;
    return rb_equal(pst_to_i(st1), st2);
}

static VALUE
pst_bitand(st1, st2)
    VALUE st1, st2;
{
    int status = NUM2INT(st1) & NUM2INT(st2);

    return INT2NUM(status);
}

static VALUE
pst_rshift(st1, st2)
    VALUE st1, st2;
{
    int status = NUM2INT(st1) >> NUM2INT(st2);

    return INT2NUM(status);
}

static VALUE
pst_wifstopped(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFSTOPPED(status))
	return Qtrue;
    else
	return Qfalse;
}

static VALUE
pst_wstopsig(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFSTOPPED(status))
	return INT2NUM(WSTOPSIG(status));
    return Qnil;
}

static VALUE
pst_wifsignaled(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFSIGNALED(status))
	return Qtrue;
    else
	return Qfalse;
}

static VALUE
pst_wtermsig(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFSIGNALED(status))
	return INT2NUM(WTERMSIG(status));
    return Qnil;
}

static VALUE
pst_wifexited(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFEXITED(status))
	return Qtrue;
    else
	return Qfalse;
}

static VALUE
pst_wexitstatus(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFEXITED(status))
	return INT2NUM(WEXITSTATUS(status));
    return Qnil;
}

static VALUE
pst_wcoredump(st)
    VALUE st;
{
#ifdef WCOREDUMP
    int status = NUM2INT(st);

    if (WCOREDUMP(status))
	return Qtrue;
    else
	return Qfalse;
#else
    return Qfalse;
#endif
}

#if !defined(HAVE_WAITPID) && !defined(HAVE_WAIT4)
#define NO_WAITPID
static st_table *pid_tbl;
#endif

int
rb_waitpid(pid, st, flags)
    int pid;
    int *st;
    int flags;
{
    int result;
#ifndef NO_WAITPID
    int oflags = flags;
    if (!rb_thread_alone()) {	/* there're other threads to run */
	flags |= WNOHANG;
    }

  retry:
    TRAP_BEG;
#ifdef HAVE_WAITPID
    result = waitpid(pid, st, flags);
#else  /* HAVE_WAIT4 */
    result = wait4(pid, st, flags, NULL);
#endif
    TRAP_END;
    if (result < 0) {
	if (errno == EINTR) {
	    rb_thread_polling();
	    goto retry;
	}
	return -1;
    }
    if (result == 0) {
	if (oflags & WNOHANG) return 0;
	rb_thread_polling();
	if (rb_thread_alone()) flags = oflags;
	goto retry;
    }
#else  /* NO_WAITPID */
    if (pid_tbl && st_lookup(pid_tbl, pid, st)) {
	last_status_set(*st, pid);
	st_delete(pid_tbl, (st_data_t*)&pid, NULL);
	return pid;
    }

    if (flags) {
	rb_raise(rb_eArgError, "can't do waitpid with flags");
    }

    for (;;) {
	TRAP_BEG;
	result = wait(st);
	TRAP_END;
	if (result < 0) {
	    if (errno == EINTR) {
		rb_thread_schedule();
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
	if (!rb_thread_alone()) rb_thread_schedule();
    }
#endif
    if (result > 0) {
	last_status_set(*st, result);
    }
    return result;
}

#ifdef NO_WAITPID
struct wait_data {
    int pid;
    int status;
};

static int
wait_each(pid, status, data)
    int pid, status;
    struct wait_data *data;
{
    if (data->status != -1) return ST_STOP;

    data->pid = pid;
    data->status = status;
    return ST_DELETE;
}

static int
waitall_each(pid, status, ary)
    int pid, status;
    VALUE ary;
{
    last_status_set(status, pid);
    rb_ary_push(ary, rb_assoc_new(INT2NUM(pid), rb_last_status));
    return ST_DELETE;
}
#endif

static VALUE
proc_wait(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vpid, vflags;
    int pid, flags, status;

    flags = 0;
    rb_scan_args(argc, argv, "02", &vpid, &vflags);
    if (argc == 0) {
	pid = -1;
    }
    else {
	pid = NUM2INT(vpid);
	if (argc == 2 && !NIL_P(vflags)) {
	    flags = NUM2UINT(vflags);
	}
    }
    if ((pid = rb_waitpid(pid, &status, flags)) < 0)
	rb_sys_fail(0);
    if (pid == 0) {
	return rb_last_status = Qnil;
    }
    return INT2FIX(pid);
}

static VALUE
proc_wait2(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE pid = proc_wait(argc, argv);
    if (NIL_P(pid)) return Qnil;
    return rb_assoc_new(pid, rb_last_status);
}

static VALUE
proc_waitall()
{
    VALUE result;
    int pid, status;

    result = rb_ary_new();
#ifdef NO_WAITPID
    if (pid_tbl) {
	st_foreach(pid_tbl, waitall_each, result);
    }

    for (pid = -1;;) {
	pid = wait(&status);
	if (pid == -1) {
	    if (errno == ECHILD)
		break;
            if (errno == EINTR) {
		rb_thread_schedule();
		continue;
	    }
	    rb_sys_fail(0);
	}
	last_status_set(status, pid);
	rb_ary_push(result, rb_assoc_new(INT2NUM(pid), rb_last_status));
    }
#else
    rb_last_status = Qnil;
    for (pid = -1;;) {
	pid = rb_waitpid(-1, &status, 0);
	if (pid == -1) {
	    if (errno == ECHILD)
		break;
	    rb_sys_fail(0);
	}
	rb_ary_push(result, rb_assoc_new(INT2NUM(pid), rb_last_status));
    }
#endif
    return result;
}

static VALUE
detach_process_watcer(pid_p)
    int *pid_p;
{
    int cpid, status;

    for (;;) {
	cpid = rb_waitpid(*pid_p, &status, WNOHANG);
	if (cpid == -1) return Qnil;
	rb_thread_sleep(1);
    }
}

VALUE
rb_detach_process(pid)
    int pid;
{
    return rb_thread_create(detach_process_watcer, (void*)&pid);
}

static VALUE
proc_detach(obj, pid)
    VALUE pid;
{
    return rb_detach_process(NUM2INT(pid));
}

#ifndef HAVE_STRING_H
char *strtok();
#endif

#ifdef HAVE_SETITIMER
#define before_exec() rb_thread_stop_timer()
#define after_exec() rb_thread_start_timer()
#else
#define before_exec()
#define after_exec()
#endif

extern char *dln_find_exe();

static void
security(str)
    char *str;
{
    if (rb_env_path_tainted()) {
	if (rb_safe_level() > 0) {
	    rb_raise(rb_eSecurityError, "Insecure PATH - %s", str);
	}
    }
}

static int
proc_exec_v(argv, prog)
    char **argv;
    char *prog;
{
    if (!prog)
	prog = argv[0];
    security(prog);
    prog = dln_find_exe(prog, 0);
    if (!prog)
	return -1;

#if (defined(MSDOS) && !defined(DJGPP)) || defined(__human68k__) || defined(__EMX__) || defined(OS2)
    {
#if defined(__human68k__)
#define COMMAND "command.x"
#endif
#if defined(__EMX__) || defined(OS2) /* OS/2 emx */
#define COMMAND "cmd.exe"
#endif
#if (defined(MSDOS) && !defined(DJGPP))
#define COMMAND "command.com"
#endif
	char *extension;

	if ((extension = strrchr(prog, '.')) != NULL && strcasecmp(extension, ".bat") == 0) {
	    char **new_argv;
	    char *p;
	    int n;

	    for (n = 0; argv[n]; n++)
		/* no-op */;
	    new_argv = ALLOCA_N(char*, n + 2);
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
#endif /* MSDOS or __human68k__ or __EMX__ */
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
	prog = RSTRING(progv)->ptr;
    }
    args = ALLOCA_N(char*, argc+1);
    for (i=0; i<argc; i++) {
	SafeStringValue(argv[i]);
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
    const char *str;
{
    const char *s = str;
    char *ss, *t;
    char **argv, **a;

    while (*str && ISSPACE(*str))
	str++;

#ifdef _WIN32
    before_exec();
    do_spawn(P_OVERLAY, (char *)str);
    after_exec();
#else
    for (s=str; *s; s++) {
	if (*s != ' ' && !ISALPHA(*s) && strchr("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
#if defined(MSDOS)
	    int status;
	    before_exec();
	    status = system(str);
	    after_exec();
	    if (status != -1)
		exit(status);
#else
#if defined(__human68k__) || defined(__CYGWIN32__) || defined(__EMX__)
	    char *shell = dln_find_exe("sh", 0);
	    int status = -1;
	    before_exec();
	    if (shell)
		execl(shell, "sh", "-c", str, (char *) NULL);
	    else
		status = system(str);
	    after_exec();
	    if (status != -1)
		exit(status);
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
    ss = ALLOCA_N(char, s-str+1);
    strcpy(ss, str);
    if (*a++ = strtok(ss, " \t")) {
	while (t = strtok(NULL, " \t")) {
	    *a++ = t;
	}
	*a = NULL;
    }
    if (argv[0]) {
	return proc_exec_v(argv, 0);
    }
    errno = ENOENT;
#endif	/* _WIN32 */
    return -1;
}

#if defined(__human68k__) || defined(__DJGPP__) || defined(_WIN32)
static int
proc_spawn_v(argv, prog)
    char **argv;
    char *prog;
{
    char *extension;
    int status;

    if (!prog)
	prog = argv[0];
    security(prog);
    prog = dln_find_exe(prog, 0);
    if (!prog)
	return -1;

#if defined(__human68k__)
    if ((extension = strrchr(prog, '.')) != NULL && strcasecmp(extension, ".bat") == 0) {
	char **new_argv;
	char *p;
	int n;

	for (n = 0; argv[n]; n++)
	    /* no-op */;
	new_argv = ALLOCA_N(char*, n + 2);
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
#endif
    before_exec();
#if defined(_WIN32)
    status = do_aspawn(P_WAIT, prog, argv);
#else
    status = spawnv(P_WAIT, prog, argv);
#endif
    after_exec();
    return status;
}

static int
proc_spawn_n(argc, argv, prog)
    int argc;
    VALUE *argv;
    VALUE prog;
{
    char **args;
    int i;

    args = ALLOCA_N(char*, argc + 1);
    for (i = 0; i < argc; i++) {
	SafeStringValue(argv[i]);
	args[i] = RSTRING(argv[i])->ptr;
    }
    if (prog)
	SafeStringValue(prog);
    args[i] = (char*) 0;
    if (args[0])
	return proc_spawn_v(args, prog ? RSTRING(prog)->ptr : 0);
    return -1;
}

#if !defined(_WIN32)
static int
proc_spawn(sv)
    VALUE sv;
{
    char *str;
    char *s, *t;
    char **argv, **a;
    int status;

    SafeStringValue(sv);
    str = s = RSTRING(sv)->ptr;
    for (s = str; *s; s++) {
	if (*s != ' ' && !ISALPHA(*s) && strchr("*?{}[]<>()~&|\\$;'`\"\n",*s)) {
	    char *shell = dln_find_exe("sh", 0);
	    before_exec();
	    status = shell?spawnl(P_WAIT,shell,"sh","-c",str,(char*)NULL):system(str);
	    after_exec();
	    return status;
	}
    }
    a = argv = ALLOCA_N(char*, (s - str) / 2 + 2);
    s = ALLOCA_N(char, s - str + 1);
    strcpy(s, str);
    if (*a++ = strtok(s, " \t")) {
	while (t = strtok(NULL, " \t"))
	    *a++ = t;
	*a = NULL;
    }
    return argv[0] ? proc_spawn_v(argv, 0) : -1;
}
#endif
#endif

VALUE
rb_f_exec(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE prog = 0;
    VALUE tmp;

    if (argc == 0) {
	rb_raise(rb_eArgError, "wrong number of arguments");
    }

    tmp = rb_check_array_type(argv[0]);
    if (!NIL_P(tmp)) {
	if (RARRAY(tmp)->len != 2) {
	    rb_raise(rb_eArgError, "wrong first argument");
	}
	prog = RARRAY(tmp)->ptr[0];
	SafeStringValue(prog);
	argv[0] = RARRAY(tmp)->ptr[1];
    }
    if (argc == 1 && prog == 0) {
	VALUE cmd = argv[0];

	SafeStringValue(cmd);
	rb_proc_exec(RSTRING(cmd)->ptr);
    }
    else {
	proc_exec_n(argc, argv, prog);
    }
    rb_sys_fail(RSTRING(argv[0])->ptr);
    return Qnil;		/* dummy */
}

static VALUE
rb_f_fork(obj)
    VALUE obj;
{
#if !defined(__human68k__) && !defined(_WIN32) && !defined(__MACOS__) && !defined(__EMX__) && !defined(__VMS)
    int pid;

    rb_secure(2);
    switch (pid = fork()) {
      case 0:
#ifdef linux
	after_exec();
#endif
	rb_thread_atfork();
	if (rb_block_given_p()) {
	    int status;

	    rb_protect(rb_yield, Qundef, &status);
	    ruby_stop(status);
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
rb_f_exit_bang(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE status;
    int istatus;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "01", &status) == 1) {
	switch (status) {
	  case Qtrue:
	    istatus = EXIT_SUCCESS;
	    break;
	  case Qfalse:
	    istatus = EXIT_FAILURE;
	    break;
	  default:
	    istatus = NUM2INT(status);
	    break;
	}
    }
    else {
	istatus = EXIT_FAILURE;
    }
    _exit(istatus);

    return Qnil;		/* not reached */
}

void
rb_syswait(pid)
    int pid;
{
    static int overriding;
    RETSIGTYPE (*hfunc)_((int)), (*qfunc)_((int)), (*ifunc)_((int));
    int status;
    int i, hooked = Qfalse;

    if (!overriding) {
#ifdef SIGHUP
	hfunc = signal(SIGHUP, SIG_IGN);
#endif
#ifdef SIGQUIT
	qfunc = signal(SIGQUIT, SIG_IGN);
#endif
	ifunc = signal(SIGINT, SIG_IGN);
	overriding = Qtrue;
	hooked = Qtrue;
    }

    do {
	i = rb_waitpid(pid, &status, 0);
    } while (i == -1 && errno == EINTR);

    if (hooked) {
#ifdef SIGHUP
	signal(SIGHUP, hfunc);
#endif
#ifdef SIGQUIT
	signal(SIGQUIT, qfunc);
#endif
	signal(SIGINT, ifunc);
	overriding = Qfalse;
    }
}

static VALUE
rb_f_system(argc, argv)
    int argc;
    VALUE *argv;
{
    int status;
#if defined(__EMX__)
    VALUE cmd;

    fflush(stdout);
    fflush(stderr);
    if (argc == 0) {
	rb_last_status = Qnil;
	rb_raise(rb_eArgError, "wrong number of arguments");
    }

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    rb_raise(rb_eArgError, "wrong first argument");
	}
	argv[0] = RARRAY(argv[0])->ptr[0];
    }
    cmd = rb_ary_join(rb_ary_new4(argc, argv), rb_str_new2(" "));

    SafeStringValue(cmd);
    status = do_spawn(RSTRING(cmd)->ptr);
    last_status_set(status, 0);
#elif defined(__human68k__) || defined(__DJGPP__) || defined(_WIN32)
    volatile VALUE prog = 0;

    fflush(stdout);
    fflush(stderr);
    if (argc == 0) {
	rb_last_status = Qnil;
	rb_raise(rb_eArgError, "wrong number of arguments");
    }

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    rb_raise(rb_eArgError, "wrong first argument");
	}
	prog = RARRAY(argv[0])->ptr[0];
	argv[0] = RARRAY(argv[0])->ptr[1];
    }

    if (argc == 1 && prog == 0) {
#if defined(_WIN32)
	SafeStringValue(argv[0]);
	status = do_spawn(P_WAIT, RSTRING(argv[0])->ptr);
#else
	status = proc_spawn(argv[0]);
#endif
    }
    else {
	status = proc_spawn_n(argc, argv, prog);
    }
#if defined(_WIN32)
    last_status_set(status, 0);
#else
    last_status_set(status == -1 ? 127 : status, 0);
#endif
#elif defined(__VMS)
    VALUE cmd;

    if (argc == 0) {
	rb_last_status = Qnil;
	rb_raise(rb_eArgError, "wrong number of arguments");
    }

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    rb_raise(rb_eArgError, "wrong first argument");
	}
	argv[0] = RARRAY(argv[0])->ptr[0];
    }
    cmd = rb_ary_join(rb_ary_new4(argc, argv), rb_str_new2(" "));

    SafeStringValue(cmd);
    status = system(RSTRING(cmd)->ptr);
    last_status_set((status & 0xff) << 8, 0);
#else
    volatile VALUE prog = 0;
    int pid;
    int i;

    fflush(stdout);
    fflush(stderr);
    if (argc == 0) {
	rb_last_status = Qnil;
	rb_raise(rb_eArgError, "wrong number of arguments");
    }

    if (TYPE(argv[0]) == T_ARRAY) {
	if (RARRAY(argv[0])->len != 2) {
	    rb_raise(rb_eArgError, "wrong first argument");
	}
	prog = RARRAY(argv[0])->ptr[0];
	argv[0] = RARRAY(argv[0])->ptr[1];
    }

    if (prog) {
	SafeStringValue(prog);
    }
    for (i = 0; i < argc; i++) {
	SafeStringValue(argv[i]);
    }
  retry:
    switch (pid = fork()) {
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
	    rb_thread_sleep(1);
	    goto retry;
	}
	rb_sys_fail(0);
	break;

      default:
	rb_syswait(pid);
    }

    status = NUM2INT(rb_last_status);
#endif

    if (status == EXIT_SUCCESS) return Qtrue;
    return Qfalse;
}

static VALUE
rb_f_sleep(argc, argv)
    int argc;
    VALUE *argv;
{
    int beg, end;

    beg = time(0);
    if (argc == 0) {
	rb_thread_sleep_forever();
    }
    else if (argc == 1) {
	rb_thread_wait_for(rb_time_interval(argv[0]));
    }
    else {
	rb_raise(rb_eArgError, "wrong number of arguments");
    }

    end = time(0) - beg;

    return INT2FIX(end);
}

static VALUE
proc_getpgrp()
{
    int pgrp;

#if defined(HAVE_GETPGRP) && defined(GETPGRP_VOID)
    pgrp = getpgrp();
    if (pgrp < 0) rb_sys_fail(0);
    return INT2FIX(pgrp);
#else
# ifdef HAVE_GETPGID
    pgrp = getpgid(0);
    if (pgrp < 0) rb_sys_fail(0);
    return INT2FIX(pgrp);
# else
    rb_notimplement();
# endif
#endif
}

static VALUE
proc_setpgrp()
{
  /* check for posix setpgid() first; this matches the posix */
  /* getpgrp() above.  It appears that configure will set SETPGRP_VOID */
  /* even though setpgrp(0,0) would be prefered. The posix call avoids */
  /* this confusion. */
#ifdef HAVE_SETPGID
  if (setpgid(0,0) < 0) rb_sys_fail(0);
#elif defined(HAVE_SETPGRP) && defined(SETPGRP_VOID)
    if (setpgrp() < 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return INT2FIX(0);
}

static VALUE
proc_getpgid(obj, pid)
    VALUE obj, pid;
{
#if defined(HAVE_GETPGID) && !defined(__CHECKER__)
    int i = getpgid(NUM2INT(pid));

    if (i < 0) rb_sys_fail(0);
    return INT2NUM(i);
#else
    rb_notimplement();
#endif
}

static VALUE
proc_setpgid(obj, pid, pgrp)
    VALUE obj, pid, pgrp;
{
#ifdef HAVE_SETPGID
    int ipid, ipgrp;

    rb_secure(2);
    ipid = NUM2INT(pid);
    ipgrp = NUM2INT(pgrp);

    if (setpgid(ipid, ipgrp) < 0) rb_sys_fail(0);
    return INT2FIX(0);
#else
    rb_notimplement();
#endif
}

static VALUE
proc_setsid()
{
#if defined(HAVE_SETSID)
    int pid;

    rb_secure(2);
    pid = setsid();
    if (pid < 0) rb_sys_fail(0);
    return INT2FIX(pid);
#elif defined(HAVE_SETPGRP) && defined(TIOCNOTTY)
  pid_t pid;
  int ret;

  rb_secure(2);
  pid = getpid();
#if defined(SETPGRP_VOID)
  ret = setpgrp();
  /* If `pid_t setpgrp(void)' is equivalent to setsid(),
     `ret' will be the same value as `pid', and following open() will fail.
     In Linux, `int setpgrp(void)' is equivalent to setpgid(0, 0). */
#else
  ret = setpgrp(0, pid);
#endif
  if (ret == -1) rb_sys_fail(0);

  if ((fd = open("/dev/tty", O_RDWR)) >= 0) {
    ioctl(fd, TIOCNOTTY, NULL);
    close(fd);
  }
  return INT2FIX(pid);
#else
    rb_notimplement();
#endif
}

static VALUE
proc_getpriority(obj, which, who)
    VALUE obj, which, who;
{
#ifdef HAVE_GETPRIORITY
    int prio, iwhich, iwho;

    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);

    errno = 0;
    prio = getpriority(iwhich, iwho);
    if (errno) rb_sys_fail(0);
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

    rb_secure(2);
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

static int under_uid_switch = 0;
static void
check_uid_switch()
{
    rb_secure(2);
    if (under_uid_switch) {
	rb_raise(rb_eRuntimeError, "can't handle UID during evaluating the block given to the Process::UID.switch method");
    }
}

static int under_gid_switch = 0;
static void
check_gid_switch()
{
    rb_secure(2);
    if (under_gid_switch) {
	rb_raise(rb_eRuntimeError, "can't handle GID during evaluating the block given to the Process::UID.switch method");
    }
}

static VALUE
p_sys_setuid(obj, id)
    VALUE obj, id;
{
#if defined HAVE_SETUID
    check_uid_switch();
    if (setuid(NUM2INT(id)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_setruid(obj, id)
    VALUE obj, id;
{
#if defined HAVE_SETRUID
    check_uid_switch();
    if (setruid(NUM2INT(id)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_seteuid(obj, id)
    VALUE obj, id;
{
#if defined HAVE_SETEUID
    check_uid_switch();
    if (seteuid(NUM2INT(id)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_setreuid(obj, rid, eid)
    VALUE obj, rid, eid;
{
#if defined HAVE_SETREUID
    check_uid_switch();
    if (setreuid(NUM2INT(rid),NUM2INT(eid)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_setresuid(obj, rid, eid, sid)
    VALUE obj, rid, eid, sid;
{
#if defined HAVE_SETRESUID
    check_uid_switch();
    if (setresuid(NUM2INT(rid),NUM2INT(eid),NUM2INT(sid)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

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
    int uid = NUM2INT(id);

    check_uid_switch();
#if defined(HAVE_SETRESUID) &&  !defined(__CHECKER__)
    if (setresuid(uid, -1, -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETREUID
    if (setreuid(uid, -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETRUID
    if (setruid(uid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETUID
    {
	if (geteuid() == uid) {
	    if (setuid(uid) < 0) rb_sys_fail(0);
	}
	else {
	    rb_notimplement();
	}
    }
#else
    rb_notimplement();
#endif
    return INT2FIX(uid);
}

static int SAVED_USER_ID;

static VALUE
p_uid_change_privilege(obj, id)
    VALUE obj, id;
{
    extern int errno;
    int uid;

    check_uid_switch();

    uid = NUM2INT(id);

    if (geteuid() == 0) { /* root-user */
#if defined(HAVE_SETRESUID)
	if (setresuid(uid, uid, uid) < 0) rb_sys_fail(0);
	SAVED_USER_ID = uid;
#elif defined(HAVE_SETUID)
	if (setuid(uid) < 0) rb_sys_fail(0);
	SAVED_USER_ID = uid;
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
	if (getuid() == uid) {
	    if (SAVED_USER_ID == uid) {
		if (setreuid(-1, uid) < 0) rb_sys_fail(0);
	    } else {
		if (uid == 0) { /* (r,e,s) == (root, root, x) */
		    if (setreuid(-1, SAVED_USER_ID) < 0) rb_sys_fail(0);
		    if (setreuid(SAVED_USER_ID, 0) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0; /* (r,e,s) == (x, root, root) */
		    if (setreuid(uid, uid) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = uid;
		} else {
		    if (setreuid(0, -1) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0;
		    if (setreuid(uid, uid) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = uid;
		}
	    }
	} else {
	    if (setreuid(uid, uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	}
#elif defined(HAVE_SETRUID) && defined(HAVE_SETEUID)
	if (getuid() == uid) {
	    if (SAVED_USER_ID == uid) {
		if (seteuid(uid) < 0) rb_sys_fail(0);
	    } else {
		if (uid == 0) {
		    if (setruid(SAVED_USER_ID) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0;
		    if (setruid(0) < 0) rb_sys_fail(0);
		} else {
		    if (setruid(0) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0;
		    if (seteuid(uid) < 0) rb_sys_fail(0);
		    if (setruid(uid) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = uid;
		}
	    }
	} else {
	    if (seteuid(uid) < 0) rb_sys_fail(0);
	    if (setruid(uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	}
#else
	rb_notimplement();
#endif
    } else { /* unprivileged user */
#if defined(HAVE_SETRESUID)
	if (setresuid((getuid() == uid)? -1: uid, 
		      (geteuid() == uid)? -1: uid, 
		      (SAVED_USER_ID == uid)? -1: uid) < 0) rb_sys_fail(0);
	SAVED_USER_ID = uid;
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
	if (SAVED_USER_ID == uid) {
	    if (setreuid((getuid() == uid)? -1: uid, 
			 (geteuid() == uid)? -1: uid) < 0) rb_sys_fail(0);
	} else if (getuid() != uid) {
	    if (setreuid(uid, (geteuid() == uid)? -1: uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	} else if (/* getuid() == uid && */ geteuid() != uid) {
	    if (setreuid(geteuid(), uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	    if (setreuid(uid, -1) < 0) rb_sys_fail(0);
	} else { /* getuid() == uid && geteuid() == uid */
	    if (setreuid(-1, SAVED_USER_ID) < 0) rb_sys_fail(0);
	    if (setreuid(SAVED_USER_ID, uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	    if (setreuid(uid, -1) < 0) rb_sys_fail(0);
	}
#elif defined(HAVE_SETRUID) && defined(HAVE_SETEUID)
	if (SAVED_USER_ID == uid) {
	    if (geteuid() != uid && seteuid(uid) < 0) rb_sys_fail(0);
	    if (getuid() != uid && setruid(uid) < 0) rb_sys_fail(0);
	} else if (/* SAVED_USER_ID != uid && */ geteuid() == uid) {
	    if (getuid() != uid) {
		if (setruid(uid) < 0) rb_sys_fail(0);
		SAVED_USER_ID = uid;
	    } else {
		if (setruid(SAVED_USER_ID) < 0) rb_sys_fail(0);
		SAVED_USER_ID = uid;
		if (setruid(uid) < 0) rb_sys_fail(0);
	    }
	} else if (/* geteuid() != uid && */ getuid() == uid) {
	    if (seteuid(uid) < 0) rb_sys_fail(0);
	    if (setruid(SAVED_USER_ID) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	    if (setruid(uid) < 0) rb_sys_fail(0);
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_44BSD_SETUID
	if (getuid() == uid) {
	    /* (r,e,s)==(uid,?,?) ==> (uid,uid,uid) */
	    if (setuid(uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETEUID
	if (getuid() == uid && SAVED_USER_ID == uid) {
	    if (seteuid(uid) < 0) rb_sys_fail(0);
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETUID
	if (getuid() == uid && SAVED_USER_ID == uid) {
	    if (setuid(uid) < 0) rb_sys_fail(0);
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#else
	rb_notimplement();
#endif
    }
    return INT2FIX(uid);
}

static VALUE
p_sys_setgid(obj, id)
    VALUE obj, id;
{
#if defined HAVE_SETGID
    check_gid_switch();
    if (setgid(NUM2INT(id)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_setrgid(obj, id)
    VALUE obj, id;
{
#if defined HAVE_SETRGID
    check_gid_switch();
    if (setrgid(NUM2INT(id)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_setegid(obj, id)
    VALUE obj, id;
{
#if defined HAVE_SETEGID
    check_gid_switch();
    if (setegid(NUM2INT(id)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_setregid(obj, rid, eid)
    VALUE obj, rid, eid;
{
#if defined HAVE_SETREGID
    check_gid_switch();
    if (setregid(NUM2INT(rid),NUM2INT(eid)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_setresgid(obj, rid, eid, sid)
    VALUE obj, rid, eid, sid;
{
#if defined HAVE_SETRESGID
    check_gid_switch();
    if (setresgid(NUM2INT(rid),NUM2INT(eid),NUM2INT(sid)) != 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return Qnil;
}

static VALUE
p_sys_issetugid(obj)
    VALUE obj;
{
#if defined HAVE_ISSETUGID
    if (issetugid()) {
	return Qtrue;
    } else {
	return Qfalse;
    }
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
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
    int gid = NUM2INT(id);

    check_gid_switch();
#if defined(HAVE_SETRESGID) && !defined(__CHECKER__)
    if (setresgid(gid, -1, -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETREGID
    if (setregid(gid, -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETRGID
    if (setrgid((GIDTYPE)gid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETGID
    {
	if (getegid() == gid) {
	    if (setgid(gid) < 0) rb_sys_fail(0);
	}
	else {
	    rb_notimplement();
	}
    }
#else
    rb_notimplement();
#endif
    return INT2FIX(gid);
}


static size_t maxgroups = 32;

static VALUE
proc_getgroups(VALUE obj)
{
#ifdef HAVE_GETGROUPS
    VALUE ary;
    size_t ngroups;
    gid_t *groups;
    int i;

    groups = ALLOCA_N(gid_t, maxgroups);

    ngroups = getgroups(maxgroups, groups);
    if (ngroups == -1)
        rb_sys_fail(0);

    ary = rb_ary_new();
    for (i = 0; i < ngroups; i++)
        rb_ary_push(ary, INT2NUM(groups[i]));

    return ary;
#else
    rb_notimplement();
    return Qnil;
#endif
}

static VALUE
proc_setgroups(VALUE obj, VALUE ary)
{
#ifdef HAVE_SETGROUPS
    size_t ngroups;
    gid_t *groups;
    int i;
    struct group *gr;

    Check_Type(ary, T_ARRAY);

    ngroups = RARRAY(ary)->len;
    if (ngroups > maxgroups)
        rb_raise(rb_eArgError, "too many groups, %d max", maxgroups);

    groups = ALLOCA_N(gid_t, ngroups);

    for (i = 0; i < ngroups; i++) {
        VALUE g = RARRAY(ary)->ptr[i];

	if (FIXNUM_P(g)) {
            groups[i] = FIX2INT(g);
	}
	else {
	    VALUE tmp = rb_check_string_type(g);

	    if (NIL_P(tmp)) {
		groups[i] = NUM2INT(g);
	    }
	    else {
		gr = getgrnam(RSTRING(g)->ptr);
		if (gr == NULL)
		    rb_raise(rb_eArgError, 
			     "can't find group for %s", RSTRING(g)->ptr);
		groups[i] = gr->gr_gid;
	    }
	}
    }

    i = setgroups(ngroups, groups);
    if (i == -1)
        rb_sys_fail(0);

    return proc_getgroups(obj);
#else
    rb_notimplement();
    return Qnil;
#endif
}

static VALUE
proc_initgroups(obj, uname, base_grp)
    VALUE obj, uname, base_grp;
{
#ifdef HAVE_INITGROUPS
    if (initgroups(StringValuePtr(uname), (gid_t)NUM2INT(base_grp)) != 0) {
	rb_sys_fail(0);
    }
    return proc_getgroups(obj);
#else
    rb_notimplement();
    return Qnil;
#endif
}

static VALUE
proc_getmaxgroups(obj)
    VALUE obj;
{
    return INT2FIX(maxgroups);
}

static VALUE
proc_setmaxgroups(obj, val)
    VALUE obj;
{
    size_t  ngroups = FIX2INT(val);

    if (ngroups > 4096)
	ngroups = 4096;

    maxgroups = ngroups;

    return INT2FIX(maxgroups);
}

static int SAVED_GROUP_ID;

static VALUE
p_gid_change_privilege(obj, id)
    VALUE obj, id;
{
    extern int errno;
    int gid;

    check_gid_switch();

    gid = NUM2INT(id);

    if (geteuid() == 0) { /* root-user */
#if defined(HAVE_SETRESGID)
	if (setresgid(gid, gid, gid) < 0) rb_sys_fail(0);
	SAVED_GROUP_ID = gid;
#elif defined HAVE_SETGID
	if (setgid(gid) < 0) rb_sys_fail(0);
	SAVED_GROUP_ID = gid;
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
	if (getgid() == gid) {
	    if (SAVED_GROUP_ID == gid) {
		if (setregid(-1, gid) < 0) rb_sys_fail(0);
	    } else {
		if (gid == 0) { /* (r,e,s) == (root, y, x) */
		    if (setregid(-1, SAVED_GROUP_ID) < 0) rb_sys_fail(0);
		    if (setregid(SAVED_GROUP_ID, 0) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0; /* (r,e,s) == (x, root, root) */
		    if (setregid(gid, gid) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = gid;
		} else { /* (r,e,s) == (z, y, x) */
		    if (setregid(0, 0) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0;
		    if (setregid(gid, gid) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = gid;
		}
	    }
	} else {
	    if (setregid(gid, gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	}
#elif defined(HAVE_SETRGID) && defined (HAVE_SETEGID)
	if (getgid() == gid) {
	    if (SAVED_GROUP_ID == gid) {
		if (setegid(gid) < 0) rb_sys_fail(0);
	    } else {
		if (gid == 0) {
		    if (setegid(gid) < 0) rb_sys_fail(0);
		    if (setrgid(SAVED_GROUP_ID) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0;
		    if (setrgid(0) < 0) rb_sys_fail(0);
		} else {
		    if (setrgid(0) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0;
		    if (setegid(gid) < 0) rb_sys_fail(0);
		    if (setrgid(gid) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = gid;
		}
	    }
	} else {
	    if (setegid(gid) < 0) rb_sys_fail(0);
	    if (setrgid(gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	}
#else
	rb_notimplement();
#endif
    } else { /* unprivileged user */
#if defined(HAVE_SETRESGID)
	if (setresgid((getgid() == gid)? -1: gid, 
		      (getegid() == gid)? -1: gid, 
		      (SAVED_GROUP_ID == gid)? -1: gid) < 0) rb_sys_fail(0);
	SAVED_GROUP_ID = gid;
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
	if (SAVED_GROUP_ID == gid) {
	    if (setregid((getgid() == gid)? -1: gid, 
			 (getegid() == gid)? -1: gid) < 0) rb_sys_fail(0);
	} else if (getgid() != gid) {
	    if (setregid(gid, (getegid() == gid)? -1: gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	} else if (/* getgid() == gid && */ getegid() != gid) {
	    if (setregid(getegid(), gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	    if (setregid(gid, -1) < 0) rb_sys_fail(0);
	} else { /* getgid() == gid && getegid() == gid */
	    if (setregid(-1, SAVED_GROUP_ID) < 0) rb_sys_fail(0);
	    if (setregid(SAVED_GROUP_ID, gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	    if (setregid(gid, -1) < 0) rb_sys_fail(0);
	}
#elif defined(HAVE_SETRGID) && defined(HAVE_SETEGID)
	if (SAVED_GROUP_ID == gid) {
	    if (getegid() != gid && setegid(gid) < 0) rb_sys_fail(0);
	    if (getgid() != gid && setrgid(gid) < 0) rb_sys_fail(0);
	} else if (/* SAVED_GROUP_ID != gid && */ getegid() == gid) {
	    if (getgid() != gid) {
		if (setrgid(gid) < 0) rb_sys_fail(0);
		SAVED_GROUP_ID = gid;
	    } else {
		if (setrgid(SAVED_GROUP_ID) < 0) rb_sys_fail(0);
		SAVED_GROUP_ID = gid;
		if (setrgid(gid) < 0) rb_sys_fail(0);
	    }
	} else if (/* getegid() != gid && */ getgid() == gid) {
	    if (setegid(gid) < 0) rb_sys_fail(0);
	    if (setrgid(SAVED_GROUP_ID) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	    if (setrgid(gid) < 0) rb_sys_fail(0);
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_44BSD_SETGID
	if (getgid() == gid) {
	    /* (r,e,s)==(gid,?,?) ==> (gid,gid,gid) */
	    if (setgid(gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETEGID
	if (getgid() == gid && SAVED_GROUP_ID == gid) {
	    if (setegid(gid) < 0) rb_sys_fail(0);
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETGID
	if (getgid() == gid && SAVED_GROUP_ID == gid) {
	    if (setgid(gid) < 0) rb_sys_fail(0);
	} else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#else
	rb_notimplement();
#endif
    }
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
    check_uid_switch();
#if defined(HAVE_SETRESUID) && !defined(__CHECKER__)
    if (setresuid(-1, NUM2INT(euid), -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETREUID
    if (setreuid(-1, NUM2INT(euid)) < 0) rb_sys_fail(0);
#elif defined HAVE_SETEUID
    if (seteuid(NUM2INT(euid)) < 0) rb_sys_fail(0);
#elif defined HAVE_SETUID
    euid = NUM2INT(euid);
    if (euid == getuid()) {
	if (setuid(euid) < 0) rb_sys_fail(0);
    }
    else {
	rb_notimplement();
    }
#else
    rb_notimplement();
#endif
    return euid;
}

static VALUE
rb_seteuid_core(euid)
    int euid;
{
    int uid;

    check_uid_switch();

    uid = getuid();

#if defined(HAVE_SETRESUID) && !defined(__CHECKER__)
    if (uid != euid) {
	if (setresuid(-1,euid,euid) < 0) rb_sys_fail(0);
	SAVED_USER_ID = euid;
    } else {
	if (setresuid(-1,euid,-1) < 0) rb_sys_fail(0);
    }
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
    if (setreuid(-1, euid) < 0) rb_sys_fail(0);
    if (uid != euid) {
	if (setreuid(euid,uid) < 0) rb_sys_fail(0);
	if (setreuid(uid,euid) < 0) rb_sys_fail(0);
	SAVED_USER_ID = euid;
    }
#elif defined HAVE_SETEUID
    if (seteuid(euid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETUID
    if (geteuid() == 0) rb_sys_fail(0);
    if (setuid(euid) < 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return INT2FIX(euid);
}

static VALUE
p_uid_grant_privilege(obj, id)
    VALUE obj, id;
{
    return rb_seteuid_core(NUM2INT(id));
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
    check_gid_switch();

#if defined(HAVE_SETRESGID) && !defined(__CHECKER__)
    if (setresgid(-1, NUM2INT(egid), -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETREGID
    if (setregid(-1, NUM2INT(egid)) < 0) rb_sys_fail(0);
#elif defined HAVE_SETEGID
    if (setegid(NUM2INT(egid)) < 0) rb_sys_fail(0);
#elif defined HAVE_SETGID
    egid = NUM2INT(egid);
    if (egid == getgid()) {
	if (setgid(egid) < 0) rb_sys_fail(0);
    }
    else {
	rb_notimplement();
    }
#else
    rb_notimplement();
#endif
    return egid;
}

static VALUE
rb_setegid_core(egid)
    int egid;
{
    int gid;

    check_gid_switch();

    gid = getgid();

#if defined(HAVE_SETRESGID) && !defined(__CHECKER__)
    if (gid != egid) {
	if (setresgid(-1,egid,egid) < 0) rb_sys_fail(0);
	SAVED_GROUP_ID = egid;
    } else {
	if (setresgid(-1,egid,-1) < 0) rb_sys_fail(0);
    }
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
    if (setregid(-1, egid) < 0) rb_sys_fail(0);
    if (gid != egid) {
	if (setregid(egid,gid) < 0) rb_sys_fail(0);
	if (setregid(gid,egid) < 0) rb_sys_fail(0);
	SAVED_GROUP_ID = egid;
    }
#elif defined HAVE_SETEGID
    if (setegid(egid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETGID
    if (geteuid() == 0 /* root user */) rb_sys_fail(0);
    if (setgid(egid) < 0) rb_sys_fail(0);
#else
    rb_notimplement();
#endif
    return INT2FIX(egid);
}

static VALUE
p_gid_grant_privilege(obj, id)
    VALUE obj, id;
{
    return rb_setegid_core(NUM2INT(id));
}

static VALUE
p_uid_exchangeable()
{
#if defined(HAVE_SETRESUID) &&  !defined(__CHECKER__)
    return Qtrue;
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
    return Qtrue;
#else
    return Qfalse;
#endif
}

static VALUE
p_uid_exchange(obj)
    VALUE obj;
{
    int uid, euid;

    check_uid_switch();

    uid = getuid();
    euid = geteuid();

#if defined(HAVE_SETRESUID) &&  !defined(__CHECKER__)
    if (setresuid(euid, uid, uid) < 0) rb_sys_fail(0);
    SAVED_USER_ID = uid;
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
    if (setreuid(euid,uid) < 0) rb_sys_fail(0);
    SAVED_USER_ID = uid;
#else
    rb_notimplement();
#endif
    return INT2FIX(uid);
}

static VALUE
p_gid_exchangeable()
{
#if defined(HAVE_SETRESGID) &&  !defined(__CHECKER__)
    return Qtrue;
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
    return Qtrue;
#else
    return Qfalse;
#endif
}

static VALUE
p_gid_exchange(obj)
    VALUE obj;
{
    int gid, egid;

    check_gid_switch();

    gid = getgid();
    egid = getegid();

#if defined(HAVE_SETRESGID) &&  !defined(__CHECKER__)
    if (setresgid(egid, gid, gid) < 0) rb_sys_fail(0);
    SAVED_GROUP_ID = gid;
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
    if (setregid(egid,gid) < 0) rb_sys_fail(0);
    SAVED_GROUP_ID = gid;
#else
    rb_notimplement();
#endif
    return INT2FIX(gid);
}

static VALUE
p_uid_have_saved_id()
{
#if defined(HAVE_SETRESUID) || defined(HAVE_SETEUID) || defined(_POSIX_SAVED_IDS)
    return Qtrue;
#else
    return Qfalse;
#endif
}


#if defined(HAVE_SETRESUID) || defined(HAVE_SETEUID) || defined(_POSIX_SAVED_IDS)
static VALUE
p_uid_sw_ensure(id)
    int id;
{
    under_uid_switch = 0;
    return rb_seteuid_core(id);
}

static VALUE
p_uid_switch(obj)
    VALUE obj;
{
    extern int errno;
    int uid, euid;

    check_uid_switch();

    uid = getuid();
    euid = geteuid();

    if (uid != euid) {
	proc_seteuid(obj, INT2FIX(uid));
	if (rb_block_given_p()) {
	    under_uid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_uid_sw_ensure, SAVED_USER_ID);
	} else {
	    return INT2FIX(euid);
	}
    } else if (euid != SAVED_USER_ID) {
	proc_seteuid(obj, INT2FIX(SAVED_USER_ID));
	if (rb_block_given_p()) {
	    under_uid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_uid_sw_ensure, euid);
	} else {
	    return INT2FIX(uid);
	}
    } else {
	errno = EPERM;
	rb_sys_fail(0);
    }

#else
static VALUE
p_uid_sw_ensure(obj)
    VALUE obj;
{
    under_uid_switch = 0;
    return p_uid_exchange(obj);
}

static VALUE
p_uid_switch(obj)
    VALUE obj;
{
    extern int errno;
    int uid, euid;

    check_uid_switch();

    uid = getuid();
    euid = geteuid();

    if (uid == euid) {
	errno = EPERM;
	rb_sys_fail(0);
    }
    p_uid_exchange(obj);
    if (rb_block_given_p()) {
	under_uid_switch = 1;
	return rb_ensure(rb_yield, Qnil, p_uid_sw_ensure, obj);
    } else {
	return INT2FIX(euid);
    }
#endif
}

static VALUE
p_gid_have_saved_id()
{
#if defined(HAVE_SETRESGID) || defined(HAVE_SETEGID) || defined(_POSIX_SAVED_IDS)
    return Qtrue;
#else
    return Qfalse;
#endif
}

#if defined(HAVE_SETRESGID) || defined(HAVE_SETEGID) || defined(_POSIX_SAVED_IDS)
static VALUE
p_gid_sw_ensure(id)
    int id;
{
    under_gid_switch = 0;
    return rb_setegid_core(id);
}

static VALUE
p_gid_switch(obj)
    VALUE obj;
{
    extern int errno;
    int gid, egid;

    check_gid_switch();

    gid = getgid();
    egid = getegid();

    if (gid != egid) {
	proc_setegid(obj, INT2FIX(gid));
	if (rb_block_given_p()) {
	    under_gid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_gid_sw_ensure, SAVED_GROUP_ID);
	} else {
	    return INT2FIX(egid);
	}
    } else if (egid != SAVED_GROUP_ID) {
	proc_setegid(obj, INT2FIX(SAVED_GROUP_ID));
	if (rb_block_given_p()) {
	    under_gid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_gid_sw_ensure, egid);
	} else {
	    return INT2FIX(gid);
	}
    } else {
	errno = EPERM;
	rb_sys_fail(0);
    }
#else
static VALUE
p_gid_sw_ensure(obj)
    VALUE obj;
{
    under_gid_switch = 0;
    return p_gid_exchange(obj);
}

static VALUE
p_gid_switch(obj)
    VALUE obj;
{
    extern int errno;
    int gid, egid;

    check_gid_switch();

    gid = getgid();
    egid = getegid();

    if (gid == egid) {
	errno = EPERM;
	rb_sys_fail(0);
    }
    p_gid_exchange(obj);
    if (rb_block_given_p()) {
	under_gid_switch = 1;
	return rb_ensure(rb_yield, Qnil, p_gid_sw_ensure, obj);
    } else {
	return INT2FIX(egid);
    }
#endif
}

VALUE
rb_proc_times(obj)
    VALUE obj;
{
#if defined(HAVE_TIMES) && !defined(__CHECKER__)
#ifndef HZ
# ifdef CLK_TCK
#   define HZ CLK_TCK
# else
#   define HZ 60
# endif
#endif /* HZ */
    struct tms buf;
    volatile VALUE utime, stime, cutime, sctime;

    times(&buf);
    return rb_struct_new(S_Tms,
			 utime = rb_float_new((double)buf.tms_utime / HZ),
			 stime = rb_float_new((double)buf.tms_stime / HZ),
			 cutime = rb_float_new((double)buf.tms_cutime / HZ),
			 sctime = rb_float_new((double)buf.tms_cstime / HZ));
#else
    rb_notimplement();
#endif
}

VALUE rb_mProcess;
VALUE rb_mProcUID;
VALUE rb_mProcGID;
VALUE rb_mProcID_Syscall;

void
Init_process()
{
    rb_define_virtual_variable("$$", get_pid, 0);
    rb_define_readonly_variable("$?", &rb_last_status);
    rb_define_global_function("exec", rb_f_exec, -1);
    rb_define_global_function("fork", rb_f_fork, 0);
    rb_define_global_function("exit!", rb_f_exit_bang, -1);
    rb_define_global_function("system", rb_f_system, -1);
    rb_define_global_function("sleep", rb_f_sleep, -1);

    rb_mProcess = rb_define_module("Process");

#if !defined(_WIN32) && !defined(DJGPP)
#ifdef WNOHANG
    rb_define_const(rb_mProcess, "WNOHANG", INT2FIX(WNOHANG));
#else
    rb_define_const(rb_mProcess, "WNOHANG", INT2FIX(0));
#endif
#ifdef WUNTRACED
    rb_define_const(rb_mProcess, "WUNTRACED", INT2FIX(WUNTRACED));
#else
    rb_define_const(rb_mProcess, "WUNTRACED", INT2FIX(0));
#endif
#endif

    rb_define_singleton_method(rb_mProcess, "fork", rb_f_fork, 0);
    rb_define_singleton_method(rb_mProcess, "exit!", rb_f_exit_bang, -1);
    rb_define_singleton_method(rb_mProcess, "exit", rb_f_exit, -1);
    rb_define_singleton_method(rb_mProcess, "abort", rb_f_abort, -1);

    rb_define_module_function(rb_mProcess, "kill", rb_f_kill, -1);
    rb_define_module_function(rb_mProcess, "wait", proc_wait, -1);
    rb_define_module_function(rb_mProcess, "wait2", proc_wait2, -1);
    rb_define_module_function(rb_mProcess, "waitpid", proc_wait, -1);
    rb_define_module_function(rb_mProcess, "waitpid2", proc_wait2, -1);
    rb_define_module_function(rb_mProcess, "waitall", proc_waitall, 0);
    rb_define_module_function(rb_mProcess, "detach", proc_detach, 1);

    rb_cProcStatus = rb_define_class_under(rb_mProcess, "Status", rb_cObject);
    rb_undef_method(CLASS_OF(rb_cProcStatus), "new");

    rb_define_method(rb_cProcStatus, "==", pst_equal, 1);
    rb_define_method(rb_cProcStatus, "&", pst_bitand, 1);
    rb_define_method(rb_cProcStatus, ">>", pst_rshift, 1);
    rb_define_method(rb_cProcStatus, "to_i", pst_to_i, 0);
    rb_define_method(rb_cProcStatus, "to_int", pst_to_i, 0);
    rb_define_method(rb_cProcStatus, "to_s", pst_to_s, 0);
    rb_define_method(rb_cProcStatus, "inspect", pst_inspect, 0);

    rb_define_method(rb_cProcStatus, "pid", pst_pid, 0);

    rb_define_method(rb_cProcStatus, "stopped?", pst_wifstopped, 0);
    rb_define_method(rb_cProcStatus, "stopsig", pst_wstopsig, 0);
    rb_define_method(rb_cProcStatus, "signaled?", pst_wifsignaled, 0);
    rb_define_method(rb_cProcStatus, "termsig", pst_wtermsig, 0);
    rb_define_method(rb_cProcStatus, "exited?", pst_wifexited, 0);
    rb_define_method(rb_cProcStatus, "exitstatus", pst_wexitstatus, 0);
    rb_define_method(rb_cProcStatus, "coredump?", pst_wcoredump, 0);

    rb_define_module_function(rb_mProcess, "pid", get_pid, 0);
    rb_define_module_function(rb_mProcess, "ppid", get_ppid, 0);

    rb_define_module_function(rb_mProcess, "getpgrp", proc_getpgrp, 0);
    rb_define_module_function(rb_mProcess, "setpgrp", proc_setpgrp, 0);
    rb_define_module_function(rb_mProcess, "getpgid", proc_getpgid, 1);
    rb_define_module_function(rb_mProcess, "setpgid", proc_setpgid, 2);

    rb_define_module_function(rb_mProcess, "setsid", proc_setsid, 0);

    rb_define_module_function(rb_mProcess, "getpriority", proc_getpriority, 2);
    rb_define_module_function(rb_mProcess, "setpriority", proc_setpriority, 3);

#ifdef HAVE_GETPRIORITY
    rb_define_const(rb_mProcess, "PRIO_PROCESS", INT2FIX(PRIO_PROCESS));
    rb_define_const(rb_mProcess, "PRIO_PGRP", INT2FIX(PRIO_PGRP));
    rb_define_const(rb_mProcess, "PRIO_USER", INT2FIX(PRIO_USER));
#endif

    rb_define_module_function(rb_mProcess, "uid", proc_getuid, 0);
    rb_define_module_function(rb_mProcess, "uid=", proc_setuid, 1);
    rb_define_module_function(rb_mProcess, "gid", proc_getgid, 0);
    rb_define_module_function(rb_mProcess, "gid=", proc_setgid, 1);
    rb_define_module_function(rb_mProcess, "euid", proc_geteuid, 0);
    rb_define_module_function(rb_mProcess, "euid=", proc_seteuid, 1);
    rb_define_module_function(rb_mProcess, "egid", proc_getegid, 0);
    rb_define_module_function(rb_mProcess, "egid=", proc_setegid, 1);
    rb_define_module_function(rb_mProcess, "initgroups", proc_initgroups, 2);
    rb_define_module_function(rb_mProcess, "groups", proc_getgroups, 0);
    rb_define_module_function(rb_mProcess, "groups=", proc_setgroups, 1);
    rb_define_module_function(rb_mProcess, "maxgroups", proc_getmaxgroups, 0);
    rb_define_module_function(rb_mProcess, "maxgroups=", proc_setmaxgroups, 1);

    rb_define_module_function(rb_mProcess, "times", rb_proc_times, 0);

#if defined(HAVE_TIMES) || defined(_WIN32)
    S_Tms = rb_struct_define("Tms", "utime", "stime", "cutime", "cstime", NULL);
#endif

    SAVED_USER_ID = geteuid();
    SAVED_GROUP_ID = getegid();

    rb_mProcUID = rb_define_module_under(rb_mProcess, "UID");
    rb_mProcGID = rb_define_module_under(rb_mProcess, "GID");

    rb_define_module_function(rb_mProcUID, "rid", proc_getuid, 0);
    rb_define_module_function(rb_mProcGID, "rid", proc_getgid, 0);
    rb_define_module_function(rb_mProcUID, "eid", proc_geteuid, 0);
    rb_define_module_function(rb_mProcGID, "eid", proc_getegid, 0);
    rb_define_module_function(rb_mProcUID, "change_privilege", 
			      p_uid_change_privilege, 1);
    rb_define_module_function(rb_mProcGID, "change_privilege", 
			      p_gid_change_privilege, 1);
    rb_define_module_function(rb_mProcUID, "grant_privilege", 
			      p_uid_grant_privilege, 1);
    rb_define_module_function(rb_mProcGID, "grant_privilege", 
			      p_gid_grant_privilege, 1);
    rb_define_alias(rb_mProcUID, "eid=", "grant_privilege");
    rb_define_alias(rb_mProcGID, "eid=", "grant_privilege");
    rb_define_module_function(rb_mProcUID, "re_exchange", p_uid_exchange, 0);
    rb_define_module_function(rb_mProcGID, "re_exchange", p_gid_exchange, 0);
    rb_define_module_function(rb_mProcUID, "re_exchangeable?", 
			      p_uid_exchangeable, 0);
    rb_define_module_function(rb_mProcGID, "re_exchangeable?", 
			      p_gid_exchangeable, 0);
    rb_define_module_function(rb_mProcUID, "sid_available?", 
			      p_uid_have_saved_id, 0);
    rb_define_module_function(rb_mProcGID, "sid_available?", 
			      p_gid_have_saved_id, 0);
    rb_define_module_function(rb_mProcUID, "switch", p_uid_switch, 0);
    rb_define_module_function(rb_mProcGID, "switch", p_gid_switch, 0);

    rb_mProcID_Syscall = rb_define_module_under(rb_mProcess, "Sys");

    rb_define_module_function(rb_mProcID_Syscall, "getuid", proc_getuid, 0);
    rb_define_module_function(rb_mProcID_Syscall, "geteuid", proc_geteuid, 0);
    rb_define_module_function(rb_mProcID_Syscall, "getgid", proc_getgid, 0);
    rb_define_module_function(rb_mProcID_Syscall, "getegid", proc_getegid, 0);

    rb_define_module_function(rb_mProcID_Syscall, "setuid", p_sys_setuid, 1);
    rb_define_module_function(rb_mProcID_Syscall, "setgid", p_sys_setgid, 1);

    rb_define_module_function(rb_mProcID_Syscall, "setruid", p_sys_setruid, 1);
    rb_define_module_function(rb_mProcID_Syscall, "setrgid", p_sys_setrgid, 1);

    rb_define_module_function(rb_mProcID_Syscall, "seteuid", p_sys_seteuid, 1);
    rb_define_module_function(rb_mProcID_Syscall, "setegid", p_sys_setegid, 1);

    rb_define_module_function(rb_mProcID_Syscall, "setreuid", 
			      p_sys_setreuid, 2);
    rb_define_module_function(rb_mProcID_Syscall, "setregid", 
			      p_sys_setregid, 2);

    rb_define_module_function(rb_mProcID_Syscall, "setresuid", 
			      p_sys_setresuid, 3);
    rb_define_module_function(rb_mProcID_Syscall, "setresgid", 
			      p_sys_setresgid, 3);
    rb_define_module_function(rb_mProcID_Syscall, "issetugid", 
			      p_sys_issetugid, 0);
}
