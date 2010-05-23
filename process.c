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
#ifdef HAVE_SYS_RESOURCE_H
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

#ifdef __NetBSD__
#undef HAVE_SETRUID
#undef HAVE_SETRGID
#endif

#ifdef BROKEN_SETREUID
#define setreuid ruby_setreuid
#endif
#ifdef BROKEN_SETREGID
#define setregid ruby_setregid
#endif

#if defined(HAVE_44BSD_SETUID) || defined(__MacOS_X__)
#if !defined(USE_SETREUID) && !defined(BROKEN_SETREUID)
#define OBSOLETE_SETREUID 1
#endif
#if !defined(USE_SETREGID) && !defined(BROKEN_SETREGID)
#define OBSOLETE_SETREGID 1
#endif
#endif

#define preserving_errno(stmts) \
	do {int saved_errno = errno; stmts; errno = saved_errno;} while (0)


/*
 *  call-seq:
 *     Process.pid   => fixnum
 *
 *  Returns the process id of this process. Not available on all
 *  platforms.
 *
 *     Process.pid   #=> 27415
 */

static VALUE
get_pid()
{
    rb_secure(2);
    return INT2FIX(getpid());
}


/*
 *  call-seq:
 *     Process.ppid   => fixnum
 *
 *  Returns the process id of the parent of this process. Always
 *  returns 0 on NT. Not available on all platforms.
 *
 *     puts "I am #{Process.pid}"
 *     Process.fork { puts "Dad is #{Process.ppid}" }
 *
 *  <em>produces:</em>
 *
 *     I am 27417
 *     Dad is 27417
 */

static VALUE
get_ppid()
{
    rb_secure(2);
#ifdef _WIN32
    return INT2FIX(0);
#else
    return INT2FIX(getppid());
#endif
}


/*********************************************************************
 *
 * Document-class: Process::Status
 *
 *  <code>Process::Status</code> encapsulates the information on the
 *  status of a running or terminated system process. The built-in
 *  variable <code>$?</code> is either +nil+ or a
 *  <code>Process::Status</code> object.
 *
 *     fork { exit 99 }   #=> 26557
 *     Process.wait       #=> 26557
 *     $?.class           #=> Process::Status
 *     $?.to_i            #=> 25344
 *     $? >> 8            #=> 99
 *     $?.stopped?        #=> false
 *     $?.exited?         #=> true
 *     $?.exitstatus      #=> 99
 *
 *  Posix systems record information on processes using a 16-bit
 *  integer.  The lower bits record the process status (stopped,
 *  exited, signaled) and the upper bits possibly contain additional
 *  information (for example the program's return code in the case of
 *  exited processes). Pre Ruby 1.8, these bits were exposed directly
 *  to the Ruby program. Ruby now encapsulates these in a
 *  <code>Process::Status</code> object. To maximize compatibility,
 *  however, these objects retain a bit-oriented interface. In the
 *  descriptions that follow, when we talk about the integer value of
 *  _stat_, we're referring to this 16 bit value.
 */

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


/*
 *  call-seq:
 *     stat.to_i     => fixnum
 *     stat.to_int   => fixnum
 *
 *  Returns the bits in _stat_ as a <code>Fixnum</code>. Poking
 *  around in these bits is platform dependent.
 *
 *     fork { exit 0xab }         #=> 26566
 *     Process.wait               #=> 26566
 *     sprintf('%04x', $?.to_i)   #=> "ab00"
 */

static VALUE
pst_to_i(st)
    VALUE st;
{
    return rb_iv_get(st, "status");
}


/*
 *  call-seq:
 *     stat.to_s   => string
 *
 *  Equivalent to _stat_<code>.to_i.to_s</code>.
 */

static VALUE
pst_to_s(st)
    VALUE st;
{
    return rb_fix2str(pst_to_i(st), 10);
}


/*
 *  call-seq:
 *     stat.pid   => fixnum
 *
 *  Returns the process ID that this status object represents.
 *
 *     fork { exit }   #=> 26569
 *     Process.wait    #=> 26569
 *     $?.pid          #=> 26569
 */

static VALUE
pst_pid(st)
    VALUE st;
{
    return rb_iv_get(st, "pid");
}


/*
 *  call-seq:
 *     stat.inspect   => string
 *
 *  Override the inspection method.
 */

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


/*
 *  call-seq:
 *     stat == other   => true or false
 *
 *  Returns +true+ if the integer value of _stat_
 *  equals <em>other</em>.
 */

static VALUE
pst_equal(st1, st2)
    VALUE st1, st2;
{
    if (st1 == st2) return Qtrue;
    return rb_equal(pst_to_i(st1), st2);
}


/*
 *  call-seq:
 *     stat & num   => fixnum
 *
 *  Logical AND of the bits in _stat_ with <em>num</em>.
 *
 *     fork { exit 0x37 }
 *     Process.wait
 *     sprintf('%04x', $?.to_i)       #=> "3700"
 *     sprintf('%04x', $? & 0x1e00)   #=> "1600"
 */

static VALUE
pst_bitand(st1, st2)
    VALUE st1, st2;
{
    int status = NUM2INT(st1) & NUM2INT(st2);

    return INT2NUM(status);
}


/*
 *  call-seq:
 *     stat >> num   => fixnum
 *
 *  Shift the bits in _stat_ right <em>num</em> places.
 *
 *     fork { exit 99 }   #=> 26563
 *     Process.wait       #=> 26563
 *     $?.to_i            #=> 25344
 *     $? >> 8            #=> 99
 */

static VALUE
pst_rshift(st1, st2)
    VALUE st1, st2;
{
    int status = NUM2INT(st1) >> NUM2INT(st2);

    return INT2NUM(status);
}


/*
 *  call-seq:
 *     stat.stopped?   => true or false
 *
 *  Returns +true+ if this process is stopped. This is only
 *  returned if the corresponding <code>wait</code> call had the
 *  <code>WUNTRACED</code> flag set.
 */

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


/*
 *  call-seq:
 *     stat.stopsig   => fixnum or nil
 *
 *  Returns the number of the signal that caused _stat_ to stop
 *  (or +nil+ if self is not stopped).
 */

static VALUE
pst_wstopsig(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFSTOPPED(status))
	return INT2NUM(WSTOPSIG(status));
    return Qnil;
}


/*
 *  call-seq:
 *     stat.signaled?   => true or false
 *
 *  Returns +true+ if _stat_ terminated because of
 *  an uncaught signal.
 */

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


/*
 *  call-seq:
 *     stat.termsig   => fixnum or nil
 *
 *  Returns the number of the signal that caused _stat_ to
 *  terminate (or +nil+ if self was not terminated by an
 *  uncaught signal).
 */

static VALUE
pst_wtermsig(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFSIGNALED(status))
	return INT2NUM(WTERMSIG(status));
    return Qnil;
}


/*
 *  call-seq:
 *     stat.exited?   => true or false
 *
 *  Returns +true+ if _stat_ exited normally (for
 *  example using an <code>exit()</code> call or finishing the
 *  program).
 */

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


/*
 *  call-seq:
 *     stat.exitstatus   => fixnum or nil
 *
 *  Returns the least significant eight bits of the return code of
 *  _stat_. Only available if <code>exited?</code> is
 *  +true+.
 *
 *     fork { }           #=> 26572
 *     Process.wait       #=> 26572
 *     $?.exited?         #=> true
 *     $?.exitstatus      #=> 0
 *
 *     fork { exit 99 }   #=> 26573
 *     Process.wait       #=> 26573
 *     $?.exited?         #=> true
 *     $?.exitstatus      #=> 99
 */

static VALUE
pst_wexitstatus(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (WIFEXITED(status))
	return INT2NUM(WEXITSTATUS(status));
    return Qnil;
}


/*
 *  call-seq:
 *     stat.success?   => true, false or nil
 *
 *  Returns +true+ if _stat_ is successful, +false+ if not.
 *  Returns +nil+ if <code>exited?</code> is not +true+.
 */

static VALUE
pst_success_p(st)
    VALUE st;
{
    int status = NUM2INT(st);

    if (!WIFEXITED(status))
	return Qnil;
    return WEXITSTATUS(status) == EXIT_SUCCESS ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     stat.coredump?   => true or false
 *
 *  Returns +true+ if _stat_ generated a coredump
 *  when it terminated. Not available on all platforms.
 */

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


/* [MG]:FIXME: I wasn't sure how this should be done, since ::wait()
   has historically been documented as if it didn't take any arguments
   despite the fact that it's just an alias for ::waitpid(). The way I
   have it below is more truthful, but a little confusing.

   I also took the liberty of putting in the pid values, as they're
   pretty useful, and it looked as if the original 'ri' output was
   supposed to contain them after "[...]depending on the value of
   aPid:".

   The 'ansi' and 'bs' formats of the ri output don't display the
   definition list for some reason, but the plain text one does.
 */

/*
 *  call-seq:
 *     Process.wait()                     => fixnum
 *     Process.wait(pid=-1, flags=0)      => fixnum
 *     Process.waitpid(pid=-1, flags=0)   => fixnum
 *
 *  Waits for a child process to exit, returns its process id, and
 *  sets <code>$?</code> to a <code>Process::Status</code> object
 *  containing information on that process. Which child it waits on
 *  depends on the value of _pid_:
 *
 *  > 0::   Waits for the child whose process ID equals _pid_.
 *
 *  0::     Waits for any child whose process group ID equals that of the
 *          calling process.
 *
 *  -1::    Waits for any child process (the default if no _pid_ is
 *          given).
 *
 *  < -1::  Waits for any child whose process group ID equals the absolute
 *          value of _pid_.
 *
 *  The _flags_ argument may be a logical or of the flag values
 *  <code>Process::WNOHANG</code> (do not block if no child available)
 *  or <code>Process::WUNTRACED</code> (return stopped children that
 *  haven't been reported). Not all flags are available on all
 *  platforms, but a flag value of zero will work on all platforms.
 *
 *  Calling this method raises a <code>SystemError</code> if there are
 *  no child processes. Not available on all platforms.
 *
 *     include Process
 *     fork { exit 99 }                 #=> 27429
 *     wait                             #=> 27429
 *     $?.exitstatus                    #=> 99
 *
 *     pid = fork { sleep 3 }           #=> 27440
 *     Time.now                         #=> Wed Apr 09 08:57:09 CDT 2003
 *     waitpid(pid, Process::WNOHANG)   #=> nil
 *     Time.now                         #=> Wed Apr 09 08:57:09 CDT 2003
 *     waitpid(pid, 0)                  #=> 27440
 *     Time.now                         #=> Wed Apr 09 08:57:12 CDT 2003
 */

static VALUE
proc_wait(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vpid, vflags;
    int pid, flags, status;

    rb_secure(2);
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


/*
 *  call-seq:
 *     Process.wait2(pid=-1, flags=0)      => [pid, status]
 *     Process.waitpid2(pid=-1, flags=0)   => [pid, status]
 *
 *  Waits for a child process to exit (see Process::waitpid for exact
 *  semantics) and returns an array containing the process id and the
 *  exit status (a <code>Process::Status</code> object) of that
 *  child. Raises a <code>SystemError</code> if there are no child
 *  processes.
 *
 *     Process.fork { exit 99 }   #=> 27437
 *     pid, status = Process.wait2
 *     pid                        #=> 27437
 *     status.exitstatus          #=> 99
 */

static VALUE
proc_wait2(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE pid = proc_wait(argc, argv);
    if (NIL_P(pid)) return Qnil;
    return rb_assoc_new(pid, rb_last_status);
}


/*
 *  call-seq:
 *     Process.waitall   => [ [pid1,status1], ...]
 *
 *  Waits for all children, returning an array of
 *  _pid_/_status_ pairs (where _status_ is a
 *  <code>Process::Status</code> object).
 *
 *     fork { sleep 0.2; exit 2 }   #=> 27432
 *     fork { sleep 0.1; exit 1 }   #=> 27433
 *     fork {            exit 0 }   #=> 27434
 *     p Process.waitall
 *
 *  <em>produces</em>:
 *
 *     [[27434, #<Process::Status: pid=27434,exited(0)>],
 *      [27433, #<Process::Status: pid=27433,exited(1)>],
 *      [27432, #<Process::Status: pid=27432,exited(2)>]]
 */

static VALUE
proc_waitall()
{
    VALUE result;
    int pid, status;

    rb_secure(2);
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
detach_process_watcher(arg)
    void *arg;
{
    int pid = (int)(VALUE)arg, status;

    while (rb_waitpid(pid, &status, WNOHANG) == 0) {
	rb_thread_sleep(1);
    }
    return rb_last_status;
}

VALUE
rb_detach_process(pid)
    int pid;
{
    return rb_thread_create(detach_process_watcher, (void*)(VALUE)pid);
}


/*
 *  call-seq:
 *     Process.detach(pid)   => thread
 *
 *  Some operating systems retain the status of terminated child
 *  processes until the parent collects that status (normally using
 *  some variant of <code>wait()</code>. If the parent never collects
 *  this status, the child stays around as a <em>zombie</em> process.
 *  <code>Process::detach</code> prevents this by setting up a
 *  separate Ruby thread whose sole job is to reap the status of the
 *  process _pid_ when it terminates. Use <code>detach</code>
 *  only when you do not intent to explicitly wait for the child to
 *  terminate.  <code>detach</code> only checks the status
 *  periodically (currently once each second).
 *
 *  The waiting thread returns the exit status of the detached process
 *  when it terminates, so you can use <code>Thread#join</code> to
 *  know the result.  If specified _pid_ is not a valid child process
 *  ID, the thread returns +nil+ immediately.
 *
 *  In this first example, we don't reap the first child process, so
 *  it appears as a zombie in the process status display.
 *
 *     p1 = fork { sleep 0.1 }
 *     p2 = fork { sleep 0.2 }
 *     Process.waitpid(p2)
 *     sleep 2
 *     system("ps -ho pid,state -p #{p1}")
 *
 *  <em>produces:</em>
 *
 *     27389 Z
 *
 *  In the next example, <code>Process::detach</code> is used to reap
 *  the child automatically.
 *
 *     p1 = fork { sleep 0.1 }
 *     p2 = fork { sleep 0.2 }
 *     Process.detach(p1)
 *     Process.waitpid(p2)
 *     sleep 2
 *     system("ps -ho pid,state -p #{p1}")
 *
 *  <em>(produces no output)</em>
 */

static VALUE
proc_detach(obj, pid)
    VALUE obj, pid;
{
    rb_secure(2);
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
    preserving_errno(after_exec());
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
#ifndef _WIN32
    const char *s = str;
    char *ss, *t;
    char **argv, **a;
#endif

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
	    preserving_errno(after_exec());
#endif
#endif
	    return -1;
	}
    }
    a = argv = ALLOCA_N(char*, (s-str)/2+2);
    ss = ALLOCA_N(char, s-str+1);
    strcpy(ss, str);
    if ((*a++ = strtok(ss, " \t")) != 0) {
	while ((t = strtok(NULL, " \t")) != 0) {
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
#if defined(__human68k__)
    char *extension;
#endif
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
	args[i] = StringValueCStr(argv[i]);
    }
    if (prog)
	SafeStringValue(prog);
    args[i] = (char*) 0;
    if (args[0])
	return proc_spawn_v(args, prog ? StringValueCStr(prog) : 0);
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
    str = s = StringValueCStr(sv);
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

struct rb_exec_arg {
    int argc;
    VALUE *argv;
    VALUE prog;
};

static void
proc_prepare_args(e, argc, argv, prog)
    struct rb_exec_arg *e;
    int argc;
    VALUE *argv;
    VALUE prog;
{
    int i;

    MEMZERO(e, struct rb_exec_arg, 1);
    if (prog) {
	SafeStringValue(prog);
	StringValueCStr(prog);
    }
    for (i = 0; i < argc; i++) {
	SafeStringValue(argv[i]);
	StringValueCStr(argv[i]);
    }
    security(RSTRING(prog ? prog : argv[0])->ptr);
    e->prog = prog;
    e->argc = argc;
    e->argv = argv;
}

static VALUE
proc_exec_args(earg)
    VALUE earg;
{
    struct rb_exec_arg *e = (struct rb_exec_arg *)earg;
    int argc = e->argc;
    VALUE *argv = e->argv;
    VALUE prog = e->prog;

    if (argc == 1 && prog == 0) {
	return (VALUE)rb_proc_exec(RSTRING(argv[0])->ptr);
    }
    else {
	return (VALUE)proc_exec_n(argc, argv, prog);
    }
}

/*
 *  call-seq:
 *     exec(command [, arg, ...])
 *
 *  Replaces the current process by running the given external _command_.
 *  If +exec+ is given a single argument, that argument is
 *  taken as a line that is subject to shell expansion before being
 *  executed. If multiple arguments are given, the second and subsequent
 *  arguments are passed as parameters to _command_ with no shell
 *  expansion. If the first argument is a two-element array, the first
 *  element is the command to be executed, and the second argument is
 *  used as the <code>argv[0]</code> value, which may show up in process
 *  listings. In MSDOS environments, the command is executed in a
 *  subshell; otherwise, one of the <code>exec(2)</code> system calls is
 *  used, so the running command may inherit some of the environment of
 *  the original program (including open file descriptors).
 *
 *     exec "echo *"       # echoes list of files in current directory
 *     # never get here
 *
 *
 *     exec "echo", "*"    # echoes an asterisk
 *     # never get here
 */

VALUE
rb_f_exec(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE prog = 0;
    VALUE tmp;
    struct rb_exec_arg earg;

    if (argc == 0) {
	rb_last_status = Qnil;
	rb_raise(rb_eArgError, "wrong number of arguments");
    }

    tmp = rb_check_array_type(argv[0]);
    if (!NIL_P(tmp)) {
	if (RARRAY(tmp)->len != 2) {
	    rb_raise(rb_eArgError, "wrong first argument");
	}
	prog = RARRAY(tmp)->ptr[0];
	argv[0] = RARRAY(tmp)->ptr[1];
	SafeStringValue(prog);
    }
    proc_prepare_args(&earg, argc, argv, prog);
    proc_exec_args((VALUE)&earg);
    rb_sys_fail(RSTRING(argv[0])->ptr);
    return Qnil;		/* dummy */
}


/*
 *  call-seq:
 *     Kernel.fork  [{ block }]   => fixnum or nil
 *     Process.fork [{ block }]   => fixnum or nil
 *
 *  Creates a subprocess. If a block is specified, that block is run
 *  in the subprocess, and the subprocess terminates with a status of
 *  zero. Otherwise, the +fork+ call returns twice, once in
 *  the parent, returning the process ID of the child, and once in
 *  the child, returning _nil_. The child process can exit using
 *  <code>Kernel.exit!</code> to avoid running any
 *  <code>at_exit</code> functions. The parent process should
 *  use <code>Process.wait</code> to collect the termination statuses
 *  of its children or use <code>Process.detach</code> to register
 *  disinterest in their status; otherwise, the operating system
 *  may accumulate zombie processes.
 *
 *  The thread calling fork is the only thread in the created child process.
 *  fork doesn't copy other threads.
 */

static VALUE
rb_f_fork(obj)
    VALUE obj;
{
#if !defined(__human68k__) && !defined(_WIN32) && !defined(__MACOS__) && !defined(__EMX__) && !defined(__VMS)
    int pid;

    rb_secure(2);

#ifndef __VMS
    fflush(stdout);
    fflush(stderr);
#endif

    before_exec();
    pid = fork();
    after_exec();

    switch (pid) {
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


/*
 *  call-seq:
 *     Process.exit!(fixnum=-1)
 *
 *  Exits the process immediately. No exit handlers are
 *  run. <em>fixnum</em> is returned to the underlying system as the
 *  exit status.
 *
 *     Process.exit!(0)
 */

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

#if defined(sun)
#define signal(a,b) sigset(a,b)
#endif

void
rb_syswait(pid)
    int pid;
{
    static int overriding;
#ifdef SIGHUP
    RETSIGTYPE (*hfunc)_((int)) = 0;
#endif
#ifdef SIGQUIT
    RETSIGTYPE (*qfunc)_((int)) = 0;
#endif
    RETSIGTYPE (*ifunc)_((int)) = 0;
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

/*
 *  call-seq:
 *     system(cmd [, arg, ...])    => true or false
 *
 *  Executes _cmd_ in a subshell, returning +true+ if
 *  the command was found and ran successfully, +false+
 *  otherwise. An error status is available in <code>$?</code>. The
 *  arguments are processed in the same way as for
 *  <code>Kernel::exec</code>.
 *
 *     system("echo *")
 *     system("echo", "*")
 *
 *  <em>produces:</em>
 *
 *     config.h main.rb
 *     *
 */

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
	status = do_spawn(P_WAIT, StringValueCStr(argv[0]));
#else
	status = proc_spawn(argv[0]);
#endif
    }
    else {
	status = proc_spawn_n(argc, argv, prog);
    }
#if !defined(_WIN32)
    last_status_set(status == -1 ? 127 : status, 0);
#else
    if (status == -1)
	last_status_set(0x7f << 8, 0);
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
    status = system(StringValueCStr(cmd));
    last_status_set((status & 0xff) << 8, 0);
#else
    volatile VALUE prog = 0;
    int pid;
    struct rb_exec_arg earg;
    RETSIGTYPE (*chfunc)(int);

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
    proc_prepare_args(&earg, argc, argv, prog);

    chfunc = signal(SIGCHLD, SIG_DFL);
  retry:
    before_exec();
    pid = fork();
    if (pid == 0) {
	/* child process */
	rb_thread_atfork();
	rb_protect(proc_exec_args, (VALUE)&earg, NULL);
	_exit(127);
    }
    after_exec();
    if (pid < 0) {
	if (errno == EAGAIN) {
	    rb_thread_sleep(1);
	    goto retry;
	}
    }
    else {
	rb_syswait(pid);
    }
    signal(SIGCHLD, chfunc);
    if (pid < 0) rb_sys_fail(0);
    status = NUM2INT(rb_last_status);
#endif

    if (status == EXIT_SUCCESS) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     sleep([duration])    => fixnum
 *
 *  Suspends the current thread for _duration_ seconds (which may be any number,
 *  including a +Float+ with fractional seconds). Returns the actual number of
 *  seconds slept (rounded), which may be less than that asked for if another
 *  thread calls <code>Thread#run</code>. Zero arguments causes +sleep+ to sleep
 *  forever.
 *
 *     Time.new    #=> Wed Apr 09 08:56:32 CDT 2003
 *     sleep 1.2   #=> 1
 *     Time.new    #=> Wed Apr 09 08:56:33 CDT 2003
 *     sleep 1.9   #=> 2
 *     Time.new    #=> Wed Apr 09 08:56:35 CDT 2003
 */

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


#if defined(SIGCLD) && !defined(SIGCHLD)
# define SIGCHLD SIGCLD
#endif

/*
 *  call-seq:
 *     Process.getpgrp   => integer
 *
 *  Returns the process group ID for this process. Not available on
 *  all platforms.
 *
 *     Process.getpgid(0)   #=> 25527
 *     Process.getpgrp      #=> 25527
 */

static VALUE
proc_getpgrp()
{
#if defined(HAVE_GETPGRP) && defined(GETPGRP_VOID)
    int pgrp;
#endif

    rb_secure(2);
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


/*
 *  call-seq:
 *     Process.setpgrp   => 0
 *
 *  Equivalent to <code>setpgid(0,0)</code>. Not available on all
 *  platforms.
 */

static VALUE
proc_setpgrp()
{
    rb_secure(2);
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


/*
 *  call-seq:
 *     Process.getpgid(pid)   => integer
 *
 *  Returns the process group ID for the given process id. Not
 *  available on all platforms.
 *
 *     Process.getpgid(Process.ppid())   #=> 25527
 */

static VALUE
proc_getpgid(obj, pid)
    VALUE obj, pid;
{
#if defined(HAVE_GETPGID) && !defined(__CHECKER__)
    int i;

    rb_secure(2);
    i = getpgid(NUM2INT(pid));
    if (i < 0) rb_sys_fail(0);
    return INT2NUM(i);
#else
    rb_notimplement();
#endif
}


/*
 *  call-seq:
 *     Process.setpgid(pid, integer)   => 0
 *
 *  Sets the process group ID of _pid_ (0 indicates this
 *  process) to <em>integer</em>. Not available on all platforms.
 */

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


/*
 *  call-seq:
 *     Process.setsid   => fixnum
 *
 *  Establishes this process as a new session and process group
 *  leader, with no controlling tty. Returns the session id. Not
 *  available on all platforms.
 *
 *     Process.setsid   #=> 27422
 */

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
  rb_pid_t pid;
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


/*
 *  call-seq:
 *     Process.getpriority(kind, integer)   => fixnum
 *
 *  Gets the scheduling priority for specified process, process group,
 *  or user. <em>kind</em> indicates the kind of entity to find: one
 *  of <code>Process::PRIO_PGRP</code>,
 *  <code>Process::PRIO_USER</code>, or
 *  <code>Process::PRIO_PROCESS</code>. _integer_ is an id
 *  indicating the particular process, process group, or user (an id
 *  of 0 means _current_). Lower priorities are more favorable
 *  for scheduling. Not available on all platforms.
 *
 *     Process.getpriority(Process::PRIO_USER, 0)      #=> 19
 *     Process.getpriority(Process::PRIO_PROCESS, 0)   #=> 19
 */

static VALUE
proc_getpriority(obj, which, who)
    VALUE obj, which, who;
{
#ifdef HAVE_GETPRIORITY
    int prio, iwhich, iwho;

    rb_secure(2);
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


/*
 *  call-seq:
 *     Process.setpriority(kind, integer, priority)   => 0
 *
 *  See <code>Process#getpriority</code>.
 *
 *     Process.setpriority(Process::PRIO_USER, 0, 19)      #=> 0
 *     Process.setpriority(Process::PRIO_PROCESS, 0, 19)   #=> 0
 *     Process.getpriority(Process::PRIO_USER, 0)          #=> 19
 *     Process.getpriority(Process::PRIO_PROCESS, 0)       #=> 19
 */

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

#if SIZEOF_RLIM_T == SIZEOF_INT
# define RLIM2NUM(v) UINT2NUM(v)
# define NUM2RLIM(v) NUM2UINT(v)
#elif SIZEOF_RLIM_T == SIZEOF_LONG
# define RLIM2NUM(v) ULONG2NUM(v)
# define NUM2RLIM(v) NUM2ULONG(v)
#elif SIZEOF_RLIM_T == SIZEOF_LONG_LONG
# define RLIM2NUM(v) ULL2NUM(v)
# define NUM2RLIM(v) NUM2ULL(v)
#endif

/*
 *  call-seq:
 *     Process.getrlimit(resource)   => [cur_limit, max_limit]
 *
 *  Gets the resource limit of the process.
 *  _cur_limit_ means current (soft) limit and
 *  _max_limit_ means maximum (hard) limit.
 *
 *  _resource_ indicates the kind of resource to limit:
 *  such as <code>Process::RLIMIT_CORE</code>,
 *  <code>Process::RLIMIT_CPU</code>, etc.
 *  See Process.setrlimit for details.
 *
 *  _cur_limit_ and _max_limit_ may be <code>Process::RLIM_INFINITY</code>,
 *  <code>Process::RLIM_SAVED_MAX</code> or
 *  <code>Process::RLIM_SAVED_CUR</code>.
 *  See Process.setrlimit and the system getrlimit(2) manual for details.
 */

static VALUE
proc_getrlimit(obj, resource)
    VALUE obj, resource;
{
#if defined(HAVE_GETRLIMIT) && defined(RLIM2NUM)
    struct rlimit rlim;

    rb_secure(2);

    if (getrlimit(NUM2INT(resource), &rlim) < 0) {
        rb_sys_fail("getrlimit");
    }
    return rb_assoc_new(RLIM2NUM(rlim.rlim_cur), RLIM2NUM(rlim.rlim_max));
#else
    rb_notimplement();
#endif
}

/*
 *  call-seq:
 *     Process.setrlimit(resource, cur_limit, max_limit)        => nil
 *     Process.setrlimit(resource, cur_limit)                   => nil
 *
 *  Sets the resource limit of the process.
 *  _cur_limit_ means current (soft) limit and
 *  _max_limit_ means maximum (hard) limit.
 *
 *  If _max_limit_ is not given, _cur_limit_ is used.
 *
 *  _resource_ indicates the kind of resource to limit.
 *  The list of resources are OS dependent.
 *  Ruby may support following resources.
 *
 *  [Process::RLIMIT_CORE] core size (bytes) (SUSv3)
 *  [Process::RLIMIT_CPU] CPU time (seconds) (SUSv3)
 *  [Process::RLIMIT_DATA] data segment (bytes) (SUSv3)
 *  [Process::RLIMIT_FSIZE] file size (bytes) (SUSv3)
 *  [Process::RLIMIT_NOFILE] file descriptors (number) (SUSv3)
 *  [Process::RLIMIT_STACK] stack size (bytes) (SUSv3)
 *  [Process::RLIMIT_AS] total available memory (bytes) (SUSv3, NetBSD, FreeBSD, OpenBSD but 4.4BSD-Lite)
 *  [Process::RLIMIT_MEMLOCK] total size for mlock(2) (bytes) (4.4BSD, GNU/Linux)
 *  [Process::RLIMIT_NPROC] number of processes for the user (number) (4.4BSD, GNU/Linux)
 *  [Process::RLIMIT_RSS] resident memory size (bytes) (4.2BSD, GNU/Linux)
 *  [Process::RLIMIT_SBSIZE] all socket buffers (bytes) (NetBSD, FreeBSD)
 *
 *  Other <code>Process::RLIMIT_???</code> constants may be defined.
 *
 *  _cur_limit_ and _max_limit_ may be <code>Process::RLIM_INFINITY</code>,
 *  which means that the resource is not limited.
 *  They may be <code>Process::RLIM_SAVED_MAX</code> or
 *  <code>Process::RLIM_SAVED_CUR</code> too.
 *  See system setrlimit(2) manual for details.
 *
 */

static VALUE
proc_setrlimit(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
#if defined(HAVE_SETRLIMIT) && defined(NUM2RLIM)
    VALUE resource, rlim_cur, rlim_max;
    struct rlimit rlim;

    rb_secure(2);

    rb_scan_args(argc, argv, "21", &resource, &rlim_cur, &rlim_max);
    if (rlim_max == Qnil)
        rlim_max = rlim_cur;

    rlim.rlim_cur = NUM2RLIM(rlim_cur);
    rlim.rlim_max = NUM2RLIM(rlim_max);

    if (setrlimit(NUM2INT(resource), &rlim) < 0) {
        rb_sys_fail("setrlimit");
    }
    return Qnil;
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
	rb_raise(rb_eRuntimeError, "can't handle UID while evaluating block given to Process::UID.switch method");
    }
}

static int under_gid_switch = 0;
static void
check_gid_switch()
{
    rb_secure(2);
    if (under_gid_switch) {
	rb_raise(rb_eRuntimeError, "can't handle GID while evaluating block given to Process::UID.switch method");
    }
}


/*********************************************************************
 * Document-class: Process::Sys
 *
 *  The <code>Process::Sys</code> module contains UID and GID
 *  functions which provide direct bindings to the system calls of the
 *  same names instead of the more-portable versions of the same
 *  functionality found in the <code>Process</code>,
 *  <code>Process::UID</code>, and <code>Process::GID</code> modules.
 */


/*
 *  call-seq:
 *     Process::Sys.setuid(integer)   => nil
 *
 *  Set the user ID of the current process to _integer_. Not
 *  available on all platforms.
 *
 */

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



/*
 *  call-seq:
 *     Process::Sys.setruid(integer)   => nil
 *
 *  Set the real user ID of the calling process to _integer_.
 *  Not available on all platforms.
 *
 */

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


/*
 *  call-seq:
 *     Process::Sys.seteuid(integer)   => nil
 *
 *  Set the effective user ID of the calling process to
 *  _integer_.  Not available on all platforms.
 *
 */

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


/*
 *  call-seq:
 *     Process::Sys.setreuid(rid, eid)   => nil
 *
 *  Sets the (integer) real and/or effective user IDs of the current
 *  process to _rid_ and _eid_, respectively. A value of
 *  <code>-1</code> for either means to leave that ID unchanged. Not
 *  available on all platforms.
 *
 */

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


/*
 *  call-seq:
 *     Process::Sys.setresuid(rid, eid, sid)   => nil
 *
 *  Sets the (integer) real, effective, and saved user IDs of the
 *  current process to _rid_, _eid_, and _sid_ respectively. A
 *  value of <code>-1</code> for any value means to
 *  leave that ID unchanged. Not available on all platforms.
 *
 */

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


/*
 *  call-seq:
 *     Process.uid           => fixnum
 *     Process::UID.rid      => fixnum
 *     Process::Sys.getuid   => fixnum
 *
 *  Returns the (real) user ID of this process.
 *
 *     Process.uid   #=> 501
 */

static VALUE
proc_getuid(obj)
    VALUE obj;
{
    int uid = getuid();
    return INT2FIX(uid);
}


/*
 *  call-seq:
 *     Process.uid= integer   => numeric
 *
 *  Sets the (integer) user ID for this process. Not available on all
 *  platforms.
 */

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


/********************************************************************
 *
 * Document-class: Process::UID
 *
 *  The <code>Process::UID</code> module contains a collection of
 *  module functions which can be used to portably get, set, and
 *  switch the current process's real, effective, and saved user IDs.
 *
 */

static int SAVED_USER_ID = -1;

#ifdef BROKEN_SETREUID
int
setreuid(ruid, euid)
    rb_uid_t ruid, euid;
{
    if (ruid != -1 && ruid != getuid()) {
	if (euid == -1) euid = geteuid();
	if (setuid(ruid) < 0) return -1;
    }
    if (euid != -1 && euid != geteuid()) {
	if (seteuid(euid) < 0) return -1;
    }
    return 0;
}
#endif

/*
 *  call-seq:
 *     Process::UID.change_privilege(integer)   => fixnum
 *
 *  Change the current process's real and effective user ID to that
 *  specified by _integer_. Returns the new user ID. Not
 *  available on all platforms.
 *
 *     [Process.uid, Process.euid]          #=> [0, 0]
 *     Process::UID.change_privilege(31)    #=> 31
 *     [Process.uid, Process.euid]          #=> [31, 31]
 */

static VALUE
p_uid_change_privilege(obj, id)
    VALUE obj, id;
{
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



/*
 *  call-seq:
 *     Process::Sys.setgid(integer)   => nil
 *
 *  Set the group ID of the current process to _integer_. Not
 *  available on all platforms.
 *
 */

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


/*
 *  call-seq:
 *     Process::Sys.setrgid(integer)   => nil
 *
 *  Set the real group ID of the calling process to _integer_.
 *  Not available on all platforms.
 *
 */

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



/*
 *  call-seq:
 *     Process::Sys.setegid(integer)   => nil
 *
 *  Set the effective group ID of the calling process to
 *  _integer_.  Not available on all platforms.
 *
 */

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


/*
 *  call-seq:
 *     Process::Sys.setregid(rid, eid)   => nil
 *
 *  Sets the (integer) real and/or effective group IDs of the current
 *  process to <em>rid</em> and <em>eid</em>, respectively. A value of
 *  <code>-1</code> for either means to leave that ID unchanged. Not
 *  available on all platforms.
 *
 */

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

/*
 *  call-seq:
 *     Process::Sys.setresgid(rid, eid, sid)   => nil
 *
 *  Sets the (integer) real, effective, and saved user IDs of the
 *  current process to <em>rid</em>, <em>eid</em>, and <em>sid</em>
 *  respectively. A value of <code>-1</code> for any value means to
 *  leave that ID unchanged. Not available on all platforms.
 *
 */

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


/*
 *  call-seq:
 *     Process::Sys.issetugid   => true or false
 *
 *  Returns +true+ if the process was created as a result
 *  of an execve(2) system call which had either of the setuid or
 *  setgid bits set (and extra privileges were given as a result) or
 *  if it has changed any of its real, effective or saved user or
 *  group IDs since it began execution.
 *
 */

static VALUE
p_sys_issetugid(obj)
    VALUE obj;
{
#if defined HAVE_ISSETUGID
    rb_secure(2);
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


/*
 *  call-seq:
 *     Process.gid           => fixnum
 *     Process::GID.rid      => fixnum
 *     Process::Sys.getgid   => fixnum
 *
 *  Returns the (real) group ID for this process.
 *
 *     Process.gid   #=> 500
 */

static VALUE
proc_getgid(obj)
    VALUE obj;
{
    int gid = getgid();
    return INT2FIX(gid);
}


/*
 *  call-seq:
 *     Process.gid= fixnum   => fixnum
 *
 *  Sets the group ID for this process.
 */

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
    if (setrgid(gid) < 0) rb_sys_fail(0);
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


/*
 *  call-seq:
 *     Process.groups   => array
 *
 *  Get an <code>Array</code> of the gids of groups in the
 *  supplemental group access list for this process.
 *
 *     Process.groups   #=> [27, 6, 10, 11]
 *
 */

static VALUE
proc_getgroups(obj)
    VALUE obj;
{
#ifdef HAVE_GETGROUPS
    VALUE ary;
    size_t ngroups;
    rb_gid_t *groups;
    int i;

    groups = ALLOCA_N(rb_gid_t, maxgroups);

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


/*
 *  call-seq:
 *     Process.groups= array   => array
 *
 *  Set the supplemental group access list to the given
 *  <code>Array</code> of group IDs.
 *
 *     Process.groups   #=> [0, 1, 2, 3, 4, 6, 10, 11, 20, 26, 27]
 *     Process.groups = [27, 6, 10, 11]   #=> [27, 6, 10, 11]
 *     Process.groups   #=> [27, 6, 10, 11]
 *
 */

static VALUE
proc_setgroups(obj, ary)
    VALUE obj, ary;
{
#ifdef HAVE_SETGROUPS
    size_t ngroups;
    rb_gid_t *groups;
    int i;
    struct group *gr;

    Check_Type(ary, T_ARRAY);

    ngroups = RARRAY(ary)->len;
    if (ngroups > maxgroups)
	rb_raise(rb_eArgError, "too many groups, %d max", maxgroups);

    groups = ALLOCA_N(rb_gid_t, ngroups);

    for (i = 0; i < ngroups && i < RARRAY(ary)->len; i++) {
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
		gr = getgrnam(RSTRING(tmp)->ptr);
		if (gr == NULL)
		    rb_raise(rb_eArgError,
			     "can't find group for %s", RSTRING(tmp)->ptr);
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


/*
 *  call-seq:
 *     Process.initgroups(username, gid)   => array
 *
 *  Initializes the supplemental group access list by reading the
 *  system group database and using all groups of which the given user
 *  is a member. The group with the specified <em>gid</em> is also
 *  added to the list. Returns the resulting <code>Array</code> of the
 *  gids of all the groups in the supplementary group access list. Not
 *  available on all platforms.
 *
 *     Process.groups   #=> [0, 1, 2, 3, 4, 6, 10, 11, 20, 26, 27]
 *     Process.initgroups( "mgranger", 30 )   #=> [30, 6, 10, 11]
 *     Process.groups   #=> [30, 6, 10, 11]
 *
 */

static VALUE
proc_initgroups(obj, uname, base_grp)
    VALUE obj, uname, base_grp;
{
#ifdef HAVE_INITGROUPS
    if (initgroups(StringValuePtr(uname), (rb_gid_t)NUM2INT(base_grp)) != 0) {
	rb_sys_fail(0);
    }
    return proc_getgroups(obj);
#else
    rb_notimplement();
    return Qnil;
#endif
}


/*
 *  call-seq:
 *     Process.maxgroups   => fixnum
 *
 *  Returns the maximum number of gids allowed in the supplemental
 *  group access list.
 *
 *     Process.maxgroups   #=> 32
 */

static VALUE
proc_getmaxgroups(obj)
    VALUE obj;
{
    return INT2FIX(maxgroups);
}


/*
 *  call-seq:
 *     Process.maxgroups= fixnum   => fixnum
 *
 *  Sets the maximum number of gids allowed in the supplemental group
 *  access list.
 */

static VALUE
proc_setmaxgroups(obj, val)
    VALUE obj, val;
{
    size_t  ngroups = FIX2INT(val);

    if (ngroups > 4096)
	ngroups = 4096;

    maxgroups = ngroups;

    return INT2FIX(maxgroups);
}


/********************************************************************
 *
 * Document-class: Process::GID
 *
 *  The <code>Process::GID</code> module contains a collection of
 *  module functions which can be used to portably get, set, and
 *  switch the current process's real, effective, and saved group IDs.
 *
 */

static int SAVED_GROUP_ID = -1;

#ifdef BROKEN_SETREGID
int
setregid(rgid, egid)
    rb_gid_t rgid, egid;
{
    if (rgid != -1 && rgid != getgid()) {
	if (egid == -1) egid = getegid();
	if (setgid(rgid) < 0) return -1;
    }
    if (egid != -1 && egid != getegid()) {
	if (setegid(egid) < 0) return -1;
    }
    return 0;
}
#endif

/*
 *  call-seq:
 *     Process::GID.change_privilege(integer)   => fixnum
 *
 *  Change the current process's real and effective group ID to that
 *  specified by _integer_. Returns the new group ID. Not
 *  available on all platforms.
 *
 *     [Process.gid, Process.egid]          #=> [0, 0]
 *     Process::GID.change_privilege(33)    #=> 33
 *     [Process.gid, Process.egid]          #=> [33, 33]
 */

static VALUE
p_gid_change_privilege(obj, id)
    VALUE obj, id;
{
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


/*
 *  call-seq:
 *     Process.euid           => fixnum
 *     Process::UID.eid       => fixnum
 *     Process::Sys.geteuid   => fixnum
 *
 *  Returns the effective user ID for this process.
 *
 *     Process.euid   #=> 501
 */

static VALUE
proc_geteuid(obj)
    VALUE obj;
{
    int euid = geteuid();
    return INT2FIX(euid);
}


/*
 *  call-seq:
 *     Process.euid= integer
 *
 *  Sets the effective user ID for this process. Not available on all
 *  platforms.
 */

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


/*
 *  call-seq:
 *     Process::UID.grant_privilege(integer)   => fixnum
 *     Process::UID.eid= integer               => fixnum
 *
 *  Set the effective user ID, and if possible, the saved user ID of
 *  the process to the given _integer_. Returns the new
 *  effective user ID. Not available on all platforms.
 *
 *     [Process.uid, Process.euid]          #=> [0, 0]
 *     Process::UID.grant_privilege(31)     #=> 31
 *     [Process.uid, Process.euid]          #=> [0, 31]
 */

static VALUE
p_uid_grant_privilege(obj, id)
    VALUE obj, id;
{
    return rb_seteuid_core(NUM2INT(id));
}


/*
 *  call-seq:
 *     Process.egid          => fixnum
 *     Process::GID.eid      => fixnum
 *     Process::Sys.geteid   => fixnum
 *
 *  Returns the effective group ID for this process. Not available on
 *  all platforms.
 *
 *     Process.egid   #=> 500
 */

static VALUE
proc_getegid(obj)
    VALUE obj;
{
    int egid = getegid();

    return INT2FIX(egid);
}


/*
 *  call-seq:
 *     Process.egid = fixnum   => fixnum
 *
 *  Sets the effective group ID for this process. Not available on all
 *  platforms.
 */

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


/*
 *  call-seq:
 *     Process::GID.grant_privilege(integer)    => fixnum
 *     Process::GID.eid = integer               => fixnum
 *
 *  Set the effective group ID, and if possible, the saved group ID of
 *  the process to the given _integer_. Returns the new
 *  effective group ID. Not available on all platforms.
 *
 *     [Process.gid, Process.egid]          #=> [0, 0]
 *     Process::GID.grant_privilege(31)     #=> 33
 *     [Process.gid, Process.egid]          #=> [0, 33]
 */

static VALUE
p_gid_grant_privilege(obj, id)
    VALUE obj, id;
{
    return rb_setegid_core(NUM2INT(id));
}


/*
 *  call-seq:
 *     Process::UID.re_exchangeable?   => true or false
 *
 *  Returns +true+ if the real and effective user IDs of a
 *  process may be exchanged on the current platform.
 *
 */

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


/*
 *  call-seq:
 *     Process::UID.re_exchange   => fixnum
 *
 *  Exchange real and effective user IDs and return the new effective
 *  user ID. Not available on all platforms.
 *
 *     [Process.uid, Process.euid]   #=> [0, 31]
 *     Process::UID.re_exchange      #=> 0
 *     [Process.uid, Process.euid]   #=> [31, 0]
 */

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


/*
 *  call-seq:
 *     Process::GID.re_exchangeable?   => true or false
 *
 *  Returns +true+ if the real and effective group IDs of a
 *  process may be exchanged on the current platform.
 *
 */

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


/*
 *  call-seq:
 *     Process::GID.re_exchange   => fixnum
 *
 *  Exchange real and effective group IDs and return the new effective
 *  group ID. Not available on all platforms.
 *
 *     [Process.gid, Process.egid]   #=> [0, 33]
 *     Process::GID.re_exchange      #=> 0
 *     [Process.gid, Process.egid]   #=> [33, 0]
 */

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

/* [MG] :FIXME: Is this correct? I'm not sure how to phrase this. */

/*
 *  call-seq:
 *     Process::UID.sid_available?   => true or false
 *
 *  Returns +true+ if the current platform has saved user
 *  ID functionality.
 *
 */

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


/*
 *  call-seq:
 *     Process::UID.switch              => fixnum
 *     Process::UID.switch {|| block}   => object
 *
 *  Switch the effective and real user IDs of the current process. If
 *  a <em>block</em> is given, the user IDs will be switched back
 *  after the block is executed. Returns the new effective user ID if
 *  called without a block, and the return value of the block if one
 *  is given.
 *
 */

static VALUE
p_uid_switch(obj)
    VALUE obj;
{
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


/* [MG] :FIXME: Is this correct? I'm not sure how to phrase this. */

/*
 *  call-seq:
 *     Process::GID.sid_available?   => true or false
 *
 *  Returns +true+ if the current platform has saved group
 *  ID functionality.
 *
 */

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


/*
 *  call-seq:
 *     Process::GID.switch              => fixnum
 *     Process::GID.switch {|| block}   => object
 *
 *  Switch the effective and real group IDs of the current process. If
 *  a <em>block</em> is given, the group IDs will be switched back
 *  after the block is executed. Returns the new effective group ID if
 *  called without a block, and the return value of the block if one
 *  is given.
 *
 */

static VALUE
p_gid_switch(obj)
    VALUE obj;
{
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


/*
 *  call-seq:
 *     Process.times   => aStructTms
 *
 *  Returns a <code>Tms</code> structure (see <code>Struct::Tms</code>
 *  on page 388) that contains user and system CPU times for this
 *  process.
 *
 *     t = Process.times
 *     [ t.utime, t.stime ]   #=> [0.0, 0.02]
 */

VALUE
rb_proc_times(obj)
    VALUE obj;
{
#if defined(HAVE_TIMES) && !defined(__CHECKER__)
    const double hertz =
#ifdef HAVE__SC_CLK_TCK
	(double)sysconf(_SC_CLK_TCK);
#else
#ifndef HZ
# ifdef CLK_TCK
#   define HZ CLK_TCK
# else
#   define HZ 60
# endif
#endif /* HZ */
	HZ;
#endif
    struct tms buf;
    volatile VALUE utime, stime, cutime, sctime;

    times(&buf);
    return rb_struct_new(S_Tms,
			 utime = rb_float_new(buf.tms_utime / hertz),
			 stime = rb_float_new(buf.tms_stime / hertz),
			 cutime = rb_float_new(buf.tms_cutime / hertz),
			 sctime = rb_float_new(buf.tms_cstime / hertz));
#else
    rb_notimplement();
#endif
}

VALUE rb_mProcess;
VALUE rb_mProcUID;
VALUE rb_mProcGID;
VALUE rb_mProcID_Syscall;


/*
 *  The <code>Process</code> module is a collection of methods used to
 *  manipulate processes.
 */

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

    rb_define_singleton_method(rb_mProcess, "exec", rb_f_exec, -1);
    rb_define_singleton_method(rb_mProcess, "fork", rb_f_fork, 0);
    rb_define_singleton_method(rb_mProcess, "exit!", rb_f_exit_bang, -1);
    rb_define_singleton_method(rb_mProcess, "exit", rb_f_exit, -1);   /* in eval.c */
    rb_define_singleton_method(rb_mProcess, "abort", rb_f_abort, -1); /* in eval.c */

    rb_define_module_function(rb_mProcess, "kill", rb_f_kill, -1); /* in signal.c */
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
    rb_define_method(rb_cProcStatus, "success?", pst_success_p, 0);
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

    rb_define_module_function(rb_mProcess, "getrlimit", proc_getrlimit, 1);
    rb_define_module_function(rb_mProcess, "setrlimit", proc_setrlimit, -1);
#ifdef RLIM2NUM
    {
        VALUE inf = RLIM2NUM(RLIM_INFINITY);
        rb_define_const(rb_mProcess, "RLIM_INFINITY", inf);
#ifdef RLIM_SAVED_MAX
        {
	    VALUE v = RLIM_INFINITY == RLIM_SAVED_MAX ? inf : RLIM2NUM(RLIM_SAVED_MAX);
	    rb_define_const(rb_mProcess, "RLIM_SAVED_MAX", v);
	}
#endif
#ifdef RLIM_SAVED_CUR
	{
	    VALUE v = RLIM_INFINITY == RLIM_SAVED_CUR ? inf : RLIM2NUM(RLIM_SAVED_CUR);
	    rb_define_const(rb_mProcess, "RLIM_SAVED_CUR", v);
	}
#endif
    }
#ifdef RLIMIT_CORE
    rb_define_const(rb_mProcess, "RLIMIT_CORE", INT2FIX(RLIMIT_CORE));
#endif
#ifdef RLIMIT_CPU
    rb_define_const(rb_mProcess, "RLIMIT_CPU", INT2FIX(RLIMIT_CPU));
#endif
#ifdef RLIMIT_DATA
    rb_define_const(rb_mProcess, "RLIMIT_DATA", INT2FIX(RLIMIT_DATA));
#endif
#ifdef RLIMIT_FSIZE
    rb_define_const(rb_mProcess, "RLIMIT_FSIZE", INT2FIX(RLIMIT_FSIZE));
#endif
#ifdef RLIMIT_NOFILE
    rb_define_const(rb_mProcess, "RLIMIT_NOFILE", INT2FIX(RLIMIT_NOFILE));
#endif
#ifdef RLIMIT_STACK
    rb_define_const(rb_mProcess, "RLIMIT_STACK", INT2FIX(RLIMIT_STACK));
#endif
#ifdef RLIMIT_AS
    rb_define_const(rb_mProcess, "RLIMIT_AS", INT2FIX(RLIMIT_AS));
#endif
#ifdef RLIMIT_MEMLOCK
    rb_define_const(rb_mProcess, "RLIMIT_MEMLOCK", INT2FIX(RLIMIT_MEMLOCK));
#endif
#ifdef RLIMIT_NPROC
    rb_define_const(rb_mProcess, "RLIMIT_NPROC", INT2FIX(RLIMIT_NPROC));
#endif
#ifdef RLIMIT_RSS
    rb_define_const(rb_mProcess, "RLIMIT_RSS", INT2FIX(RLIMIT_RSS));
#endif
#ifdef RLIMIT_SBSIZE
    rb_define_const(rb_mProcess, "RLIMIT_SBSIZE", INT2FIX(RLIMIT_SBSIZE));
#endif
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
    rb_define_module_function(rb_mProcUID, "change_privilege", p_uid_change_privilege, 1);
    rb_define_module_function(rb_mProcGID, "change_privilege", p_gid_change_privilege, 1);
    rb_define_module_function(rb_mProcUID, "grant_privilege", p_uid_grant_privilege, 1);
    rb_define_module_function(rb_mProcGID, "grant_privilege", p_gid_grant_privilege, 1);
    rb_define_alias(rb_singleton_class(rb_mProcUID), "eid=", "grant_privilege");
    rb_define_alias(rb_singleton_class(rb_mProcGID), "eid=", "grant_privilege");
    rb_define_module_function(rb_mProcUID, "re_exchange", p_uid_exchange, 0);
    rb_define_module_function(rb_mProcGID, "re_exchange", p_gid_exchange, 0);
    rb_define_module_function(rb_mProcUID, "re_exchangeable?", p_uid_exchangeable, 0);
    rb_define_module_function(rb_mProcGID, "re_exchangeable?", p_gid_exchangeable, 0);
    rb_define_module_function(rb_mProcUID, "sid_available?", p_uid_have_saved_id, 0);
    rb_define_module_function(rb_mProcGID, "sid_available?", p_gid_have_saved_id, 0);
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

    rb_define_module_function(rb_mProcID_Syscall, "setreuid", p_sys_setreuid, 2);
    rb_define_module_function(rb_mProcID_Syscall, "setregid", p_sys_setregid, 2);

    rb_define_module_function(rb_mProcID_Syscall, "setresuid", p_sys_setresuid, 3);
    rb_define_module_function(rb_mProcID_Syscall, "setresgid", p_sys_setresgid, 3);
    rb_define_module_function(rb_mProcID_Syscall, "issetugid", p_sys_issetugid, 0);
}
