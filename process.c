/**********************************************************************

  process.c -

  $Author$
  created at: Tue Aug 10 14:30:50 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "internal.h"
#include "ruby/io.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "vm_core.h"

#include <stdio.h>
#include <errno.h>
#include <signal.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifdef HAVE_FCNTL_H
#include <fcntl.h>
#endif
#ifdef HAVE_PROCESS_H
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

#ifdef HAVE_SYS_WAIT_H
# include <sys/wait.h>
#endif
#ifdef HAVE_SYS_RESOURCE_H
# include <sys/resource.h>
#endif
#ifdef HAVE_VFORK_H
# include <vfork.h>
#endif
#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif
#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif
#include "ruby/st.h"

#ifdef __EMX__
#undef HAVE_GETPGRP
#endif

#include <sys/stat.h>
#if defined(__native_client__) && defined(NACL_NEWLIB)
# include <sys/unistd.h>
# include "nacl/stat.h"
# include "nacl/unistd.h"
# include "nacl/resource.h"
# undef HAVE_ISSETUGID
#endif

#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#ifdef HAVE_SYS_TIMES_H
#include <sys/times.h>
#endif

#ifdef HAVE_PWD_H
#include <pwd.h>
#endif
#ifdef HAVE_GRP_H
#include <grp.h>
#endif
#ifdef HAVE_SYS_ID_H
#include <sys/id.h>
#endif

#ifdef __APPLE__
# include <mach/mach_time.h>
#endif

/* define system APIs */
#ifdef _WIN32
#undef open
#define open	rb_w32_uopen
#endif

#if defined(HAVE_TIMES) || defined(_WIN32)
static VALUE rb_cProcessTms;
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
int setreuid(rb_uid_t ruid, rb_uid_t euid);
#endif
#ifdef BROKEN_SETREGID
#define setregid ruby_setregid
int setregid(rb_gid_t rgid, rb_gid_t egid);
#endif

#if defined(HAVE_44BSD_SETUID) || defined(__APPLE__)
#if !defined(USE_SETREUID) && !defined(BROKEN_SETREUID)
#define OBSOLETE_SETREUID 1
#endif
#if !defined(USE_SETREGID) && !defined(BROKEN_SETREGID)
#define OBSOLETE_SETREGID 1
#endif
#endif

#define preserving_errno(stmts) \
	do {int saved_errno = errno; stmts; errno = saved_errno;} while (0)

static void check_uid_switch(void);
static void check_gid_switch(void);

#if 1
#define p_uid_from_name p_uid_from_name
#define p_gid_from_name p_gid_from_name
#endif

#if defined(HAVE_PWD_H)
# if defined(HAVE_GETPWNAM_R) && defined(_SC_GETPW_R_SIZE_MAX)
#  define USE_GETPWNAM_R 1
#  define GETPW_R_SIZE_INIT sysconf(_SC_GETPW_R_SIZE_MAX)
#  define GETPW_R_SIZE_DEFAULT 0x1000
#  define GETPW_R_SIZE_LIMIT  0x10000
# endif
# ifdef USE_GETPWNAM_R
#   define PREPARE_GETPWNAM \
    VALUE getpw_buf = 0
#   define FINISH_GETPWNAM \
    ALLOCV_END(getpw_buf)
#   define OBJ2UID1(id) obj2uid((id), &getpw_buf)
#   define OBJ2UID(id) obj2uid0(id)
static rb_uid_t obj2uid(VALUE id, VALUE *getpw_buf);
static inline rb_uid_t
obj2uid0(VALUE id)
{
    rb_uid_t uid;
    PREPARE_GETPWNAM;
    uid = OBJ2UID1(id);
    FINISH_GETPWNAM;
    return uid;
}
# else
#   define PREPARE_GETPWNAM	/* do nothing */
#   define FINISH_GETPWNAM	/* do nothing */
#   define OBJ2UID1(id) obj2uid((id))
#   define OBJ2UID(id) obj2uid((id))
static rb_uid_t obj2uid(VALUE id);
# endif
#else
# define PREPARE_GETPWNAM	/* do nothing */
# define FINISH_GETPWNAM	/* do nothing */
# define OBJ2UID1(id) NUM2UIDT(id)
# define OBJ2UID(id) NUM2UIDT(id)
# ifdef p_uid_from_name
#   undef p_uid_from_name
#   define p_uid_from_name rb_f_notimplement
# endif
#endif

#if defined(HAVE_GRP_H)
# if defined(HAVE_GETGRNAM_R) && defined(_SC_GETGR_R_SIZE_MAX)
#  define USE_GETGRNAM_R
#  define GETGR_R_SIZE_INIT sysconf(_SC_GETGR_R_SIZE_MAX)
#  define GETGR_R_SIZE_DEFAULT 0x1000
#  define GETGR_R_SIZE_LIMIT  0x10000
# endif
# ifdef USE_GETGRNAM_R
#   define PREPARE_GETGRNAM \
    VALUE getgr_buf = 0
#   define FINISH_GETGRNAM \
    ALLOCV_END(getgr_buf)
#   define OBJ2GID1(id) obj2gid((id), &getgr_buf)
#   define OBJ2GID(id) obj2gid0(id)
static rb_gid_t obj2gid(VALUE id, VALUE *getgr_buf);
static inline rb_gid_t
obj2gid0(VALUE id)
{
    rb_gid_t gid;
    PREPARE_GETGRNAM;
    gid = OBJ2GID1(id);
    FINISH_GETGRNAM;
    return gid;
}
static rb_gid_t obj2gid(VALUE id, VALUE *getgr_buf);
# else
#   define PREPARE_GETGRNAM	/* do nothing */
#   define FINISH_GETGRNAM	/* do nothing */
#   define OBJ2GID1(id) obj2gid((id))
#   define OBJ2GID(id) obj2gid((id))
static rb_gid_t obj2gid(VALUE id);
# endif
#else
# define PREPARE_GETGRNAM	/* do nothing */
# define FINISH_GETGRNAM	/* do nothing */
# define OBJ2GID1(id) NUM2GIDT(id)
# define OBJ2GID(id) NUM2GIDT(id)
# ifdef p_gid_from_name
#   undef p_gid_from_name
#   define p_gid_from_name rb_f_notimplement
# endif
#endif

#if SIZEOF_CLOCK_T == SIZEOF_INT
typedef unsigned int unsigned_clock_t;
#elif SIZEOF_CLOCK_T == SIZEOF_LONG
typedef unsigned long unsigned_clock_t;
#elif defined(HAVE_LONG_LONG) && SIZEOF_CLOCK_T == SIZEOF_LONG_LONG
typedef unsigned LONG_LONG unsigned_clock_t;
#endif

static ID id_in, id_out, id_err, id_pid, id_uid, id_gid;
static ID id_close, id_child, id_status;
#ifdef HAVE_SETPGID
static ID id_pgroup;
#endif
#ifdef _WIN32
static ID id_new_pgroup;
#endif
static ID id_unsetenv_others, id_chdir, id_umask, id_close_others, id_ENV;
static ID id_nanosecond, id_microsecond, id_millisecond, id_second;
static ID id_float_microsecond, id_float_millisecond, id_float_second;
static ID id_GETTIMEOFDAY_BASED_CLOCK_REALTIME, id_TIME_BASED_CLOCK_REALTIME;
#ifdef HAVE_TIMES
static ID id_TIMES_BASED_CLOCK_MONOTONIC;
static ID id_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID;
#endif
#ifdef RUSAGE_SELF
static ID id_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID;
#endif
static ID id_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID;
#ifdef __APPLE__
static ID id_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC;
#endif
static ID id_hertz;

/*
 *  call-seq:
 *     Process.pid   -> fixnum
 *
 *  Returns the process id of this process. Not available on all
 *  platforms.
 *
 *     Process.pid   #=> 27415
 */

static VALUE
get_pid(void)
{
    rb_secure(2);
    return PIDT2NUM(getpid());
}


/*
 *  call-seq:
 *     Process.ppid   -> fixnum
 *
 *  Returns the process id of the parent of this process. Returns
 *  untrustworthy value on Win32/64. Not available on all platforms.
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
get_ppid(void)
{
    rb_secure(2);
    return PIDT2NUM(getppid());
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

static VALUE rb_cProcessStatus;

VALUE
rb_last_status_get(void)
{
    return GET_THREAD()->last_status;
}

void
rb_last_status_set(int status, rb_pid_t pid)
{
    rb_thread_t *th = GET_THREAD();
    th->last_status = rb_obj_alloc(rb_cProcessStatus);
    rb_ivar_set(th->last_status, id_status, INT2FIX(status));
    rb_ivar_set(th->last_status, id_pid, PIDT2NUM(pid));
}

void
rb_last_status_clear(void)
{
    GET_THREAD()->last_status = Qnil;
}

/*
 *  call-seq:
 *     stat.to_i     -> fixnum
 *     stat.to_int   -> fixnum
 *
 *  Returns the bits in _stat_ as a <code>Fixnum</code>. Poking
 *  around in these bits is platform dependent.
 *
 *     fork { exit 0xab }         #=> 26566
 *     Process.wait               #=> 26566
 *     sprintf('%04x', $?.to_i)   #=> "ab00"
 */

static VALUE
pst_to_i(VALUE st)
{
    return rb_ivar_get(st, id_status);
}

#define PST2INT(st) NUM2INT(pst_to_i(st))

/*
 *  call-seq:
 *     stat.pid   -> fixnum
 *
 *  Returns the process ID that this status object represents.
 *
 *     fork { exit }   #=> 26569
 *     Process.wait    #=> 26569
 *     $?.pid          #=> 26569
 */

static VALUE
pst_pid(VALUE st)
{
    return rb_attr_get(st, id_pid);
}

static void
pst_message(VALUE str, rb_pid_t pid, int status)
{
    rb_str_catf(str, "pid %ld", (long)pid);
    if (WIFSTOPPED(status)) {
	int stopsig = WSTOPSIG(status);
	const char *signame = ruby_signal_name(stopsig);
	if (signame) {
	    rb_str_catf(str, " stopped SIG%s (signal %d)", signame, stopsig);
	}
	else {
	    rb_str_catf(str, " stopped signal %d", stopsig);
	}
    }
    if (WIFSIGNALED(status)) {
	int termsig = WTERMSIG(status);
	const char *signame = ruby_signal_name(termsig);
	if (signame) {
	    rb_str_catf(str, " SIG%s (signal %d)", signame, termsig);
	}
	else {
	    rb_str_catf(str, " signal %d", termsig);
	}
    }
    if (WIFEXITED(status)) {
	rb_str_catf(str, " exit %d", WEXITSTATUS(status));
    }
#ifdef WCOREDUMP
    if (WCOREDUMP(status)) {
	rb_str_cat2(str, " (core dumped)");
    }
#endif
}


/*
 *  call-seq:
 *     stat.to_s   -> string
 *
 *  Show pid and exit status as a string.
 *
 *    system("false")
 *    p $?.to_s         #=> "pid 12766 exit 1"
 *
 */

static VALUE
pst_to_s(VALUE st)
{
    rb_pid_t pid;
    int status;
    VALUE str;

    pid = NUM2PIDT(pst_pid(st));
    status = PST2INT(st);

    str = rb_str_buf_new(0);
    pst_message(str, pid, status);
    return str;
}


/*
 *  call-seq:
 *     stat.inspect   -> string
 *
 *  Override the inspection method.
 *
 *    system("false")
 *    p $?.inspect #=> "#<Process::Status: pid 12861 exit 1>"
 *
 */

static VALUE
pst_inspect(VALUE st)
{
    rb_pid_t pid;
    int status;
    VALUE vpid, str;

    vpid = pst_pid(st);
    if (NIL_P(vpid)) {
        return rb_sprintf("#<%s: uninitialized>", rb_class2name(CLASS_OF(st)));
    }
    pid = NUM2PIDT(vpid);
    status = PST2INT(st);

    str = rb_sprintf("#<%s: ", rb_class2name(CLASS_OF(st)));
    pst_message(str, pid, status);
    rb_str_cat2(str, ">");
    return str;
}


/*
 *  call-seq:
 *     stat == other   -> true or false
 *
 *  Returns +true+ if the integer value of _stat_
 *  equals <em>other</em>.
 */

static VALUE
pst_equal(VALUE st1, VALUE st2)
{
    if (st1 == st2) return Qtrue;
    return rb_equal(pst_to_i(st1), st2);
}


/*
 *  call-seq:
 *     stat & num   -> fixnum
 *
 *  Logical AND of the bits in _stat_ with <em>num</em>.
 *
 *     fork { exit 0x37 }
 *     Process.wait
 *     sprintf('%04x', $?.to_i)       #=> "3700"
 *     sprintf('%04x', $? & 0x1e00)   #=> "1600"
 */

static VALUE
pst_bitand(VALUE st1, VALUE st2)
{
    int status = PST2INT(st1) & NUM2INT(st2);

    return INT2NUM(status);
}


/*
 *  call-seq:
 *     stat >> num   -> fixnum
 *
 *  Shift the bits in _stat_ right <em>num</em> places.
 *
 *     fork { exit 99 }   #=> 26563
 *     Process.wait       #=> 26563
 *     $?.to_i            #=> 25344
 *     $? >> 8            #=> 99
 */

static VALUE
pst_rshift(VALUE st1, VALUE st2)
{
    int status = PST2INT(st1) >> NUM2INT(st2);

    return INT2NUM(status);
}


/*
 *  call-seq:
 *     stat.stopped?   -> true or false
 *
 *  Returns +true+ if this process is stopped. This is only
 *  returned if the corresponding <code>wait</code> call had the
 *  <code>WUNTRACED</code> flag set.
 */

static VALUE
pst_wifstopped(VALUE st)
{
    int status = PST2INT(st);

    if (WIFSTOPPED(status))
	return Qtrue;
    else
	return Qfalse;
}


/*
 *  call-seq:
 *     stat.stopsig   -> fixnum or nil
 *
 *  Returns the number of the signal that caused _stat_ to stop
 *  (or +nil+ if self is not stopped).
 */

static VALUE
pst_wstopsig(VALUE st)
{
    int status = PST2INT(st);

    if (WIFSTOPPED(status))
	return INT2NUM(WSTOPSIG(status));
    return Qnil;
}


/*
 *  call-seq:
 *     stat.signaled?   -> true or false
 *
 *  Returns +true+ if _stat_ terminated because of
 *  an uncaught signal.
 */

static VALUE
pst_wifsignaled(VALUE st)
{
    int status = PST2INT(st);

    if (WIFSIGNALED(status))
	return Qtrue;
    else
	return Qfalse;
}


/*
 *  call-seq:
 *     stat.termsig   -> fixnum or nil
 *
 *  Returns the number of the signal that caused _stat_ to
 *  terminate (or +nil+ if self was not terminated by an
 *  uncaught signal).
 */

static VALUE
pst_wtermsig(VALUE st)
{
    int status = PST2INT(st);

    if (WIFSIGNALED(status))
	return INT2NUM(WTERMSIG(status));
    return Qnil;
}


/*
 *  call-seq:
 *     stat.exited?   -> true or false
 *
 *  Returns +true+ if _stat_ exited normally (for
 *  example using an <code>exit()</code> call or finishing the
 *  program).
 */

static VALUE
pst_wifexited(VALUE st)
{
    int status = PST2INT(st);

    if (WIFEXITED(status))
	return Qtrue;
    else
	return Qfalse;
}


/*
 *  call-seq:
 *     stat.exitstatus   -> fixnum or nil
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
pst_wexitstatus(VALUE st)
{
    int status = PST2INT(st);

    if (WIFEXITED(status))
	return INT2NUM(WEXITSTATUS(status));
    return Qnil;
}


/*
 *  call-seq:
 *     stat.success?   -> true, false or nil
 *
 *  Returns +true+ if _stat_ is successful, +false+ if not.
 *  Returns +nil+ if <code>exited?</code> is not +true+.
 */

static VALUE
pst_success_p(VALUE st)
{
    int status = PST2INT(st);

    if (!WIFEXITED(status))
	return Qnil;
    return WEXITSTATUS(status) == EXIT_SUCCESS ? Qtrue : Qfalse;
}


/*
 *  call-seq:
 *     stat.coredump?   -> true or false
 *
 *  Returns +true+ if _stat_ generated a coredump
 *  when it terminated. Not available on all platforms.
 */

static VALUE
pst_wcoredump(VALUE st)
{
#ifdef WCOREDUMP
    int status = PST2INT(st);

    if (WCOREDUMP(status))
	return Qtrue;
    else
	return Qfalse;
#else
    return Qfalse;
#endif
}

struct waitpid_arg {
    rb_pid_t pid;
    int flags;
    int *st;
};

static void *
rb_waitpid_blocking(void *data)
{
    rb_pid_t result;
    struct waitpid_arg *arg = data;

#if defined HAVE_WAITPID
    result = waitpid(arg->pid, arg->st, arg->flags);
#elif defined HAVE_WAIT4
    result = wait4(arg->pid, arg->st, arg->flags, NULL);
#else
#  error waitpid or wait4 is required.
#endif

    return (void *)(VALUE)result;
}

rb_pid_t
rb_waitpid(rb_pid_t pid, int *st, int flags)
{
    rb_pid_t result;
    struct waitpid_arg arg;

  retry:
    arg.pid = pid;
    arg.st = st;
    arg.flags = flags;
    result = (rb_pid_t)(VALUE)rb_thread_call_without_gvl(rb_waitpid_blocking, &arg,
							 RUBY_UBF_PROCESS, 0);
    if (result < 0) {
	if (errno == EINTR) {
            RUBY_VM_CHECK_INTS(GET_THREAD());
            goto retry;
        }
	return (rb_pid_t)-1;
    }
    if (result > 0) {
	rb_last_status_set(*st, result);
    }
    return result;
}


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
 *     Process.wait()                     -> fixnum
 *     Process.wait(pid=-1, flags=0)      -> fixnum
 *     Process.waitpid(pid=-1, flags=0)   -> fixnum
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
 *  Calling this method raises a SystemCallError if there are no child
 *  processes. Not available on all platforms.
 *
 *     include Process
 *     fork { exit 99 }                 #=> 27429
 *     wait                             #=> 27429
 *     $?.exitstatus                    #=> 99
 *
 *     pid = fork { sleep 3 }           #=> 27440
 *     Time.now                         #=> 2008-03-08 19:56:16 +0900
 *     waitpid(pid, Process::WNOHANG)   #=> nil
 *     Time.now                         #=> 2008-03-08 19:56:16 +0900
 *     waitpid(pid, 0)                  #=> 27440
 *     Time.now                         #=> 2008-03-08 19:56:19 +0900
 */

static VALUE
proc_wait(int argc, VALUE *argv)
{
    VALUE vpid, vflags;
    rb_pid_t pid;
    int flags, status;

    rb_secure(2);
    flags = 0;
    if (argc == 0) {
	pid = -1;
    }
    else {
	rb_scan_args(argc, argv, "02", &vpid, &vflags);
	pid = NUM2PIDT(vpid);
	if (argc == 2 && !NIL_P(vflags)) {
	    flags = NUM2UINT(vflags);
	}
    }
    if ((pid = rb_waitpid(pid, &status, flags)) < 0)
	rb_sys_fail(0);
    if (pid == 0) {
	rb_last_status_clear();
	return Qnil;
    }
    return PIDT2NUM(pid);
}


/*
 *  call-seq:
 *     Process.wait2(pid=-1, flags=0)      -> [pid, status]
 *     Process.waitpid2(pid=-1, flags=0)   -> [pid, status]
 *
 *  Waits for a child process to exit (see Process::waitpid for exact
 *  semantics) and returns an array containing the process id and the
 *  exit status (a <code>Process::Status</code> object) of that
 *  child. Raises a SystemCallError if there are no child processes.
 *
 *     Process.fork { exit 99 }   #=> 27437
 *     pid, status = Process.wait2
 *     pid                        #=> 27437
 *     status.exitstatus          #=> 99
 */

static VALUE
proc_wait2(int argc, VALUE *argv)
{
    VALUE pid = proc_wait(argc, argv);
    if (NIL_P(pid)) return Qnil;
    return rb_assoc_new(pid, rb_last_status_get());
}


/*
 *  call-seq:
 *     Process.waitall   -> [ [pid1,status1], ...]
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
 *     [[30982, #<Process::Status: pid 30982 exit 0>],
 *      [30979, #<Process::Status: pid 30979 exit 1>],
 *      [30976, #<Process::Status: pid 30976 exit 2>]]
 */

static VALUE
proc_waitall(void)
{
    VALUE result;
    rb_pid_t pid;
    int status;

    rb_secure(2);
    result = rb_ary_new();
    rb_last_status_clear();

    for (pid = -1;;) {
	pid = rb_waitpid(-1, &status, 0);
	if (pid == -1) {
	    if (errno == ECHILD)
		break;
	    rb_sys_fail(0);
	}
	rb_ary_push(result, rb_assoc_new(PIDT2NUM(pid), rb_last_status_get()));
    }
    return result;
}

static VALUE rb_cWaiter;

static VALUE
detach_process_pid(VALUE thread)
{
    return rb_thread_local_aref(thread, id_pid);
}

static VALUE
detach_process_watcher(void *arg)
{
    rb_pid_t cpid, pid = (rb_pid_t)(VALUE)arg;
    int status;

    while ((cpid = rb_waitpid(pid, &status, 0)) == 0) {
	/* wait while alive */
    }
    return rb_last_status_get();
}

VALUE
rb_detach_process(rb_pid_t pid)
{
    VALUE watcher = rb_thread_create(detach_process_watcher, (void*)(VALUE)pid);
    rb_thread_local_aset(watcher, id_pid, PIDT2NUM(pid));
    RBASIC_SET_CLASS(watcher, rb_cWaiter);
    return watcher;
}


/*
 *  call-seq:
 *     Process.detach(pid)   -> thread
 *
 *  Some operating systems retain the status of terminated child
 *  processes until the parent collects that status (normally using
 *  some variant of <code>wait()</code>). If the parent never collects
 *  this status, the child stays around as a <em>zombie</em> process.
 *  <code>Process::detach</code> prevents this by setting up a
 *  separate Ruby thread whose sole job is to reap the status of the
 *  process _pid_ when it terminates. Use <code>detach</code>
 *  only when you do not intent to explicitly wait for the child to
 *  terminate.
 *
 *  The waiting thread returns the exit status of the detached process
 *  when it terminates, so you can use <code>Thread#join</code> to
 *  know the result.  If specified _pid_ is not a valid child process
 *  ID, the thread returns +nil+ immediately.
 *
 *  The waiting thread has <code>pid</code> method which returns the pid.
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
proc_detach(VALUE obj, VALUE pid)
{
    rb_secure(2);
    return rb_detach_process(NUM2PIDT(pid));
}

#ifdef SIGPIPE
static RETSIGTYPE (*saved_sigpipe_handler)(int) = 0;
#endif

#ifdef SIGPIPE
static RETSIGTYPE
sig_do_nothing(int sig)
{
}
#endif

/* This function should be async-signal-safe.  Actually it is. */
static void
before_exec_async_signal_safe(void)
{
#ifdef SIGPIPE
    /*
     * Some OS commands don't initialize signal handler properly. Thus we have
     * to reset signal handler before exec(). Otherwise, system() and similar
     * child process interaction might fail. (e.g. ruby -e "system 'yes | ls'")
     * [ruby-dev:12261]
     */
    saved_sigpipe_handler = signal(SIGPIPE, sig_do_nothing); /* async-signal-safe */
#endif
}

static void
before_exec_non_async_signal_safe(void)
{
    /*
     * On Mac OS X 10.5.x (Leopard) or earlier, exec() may return ENOTSUP
     * if the process have multiple threads. Therefore we have to kill
     * internal threads temporary. [ruby-core:10583]
     * This is also true on Haiku. It returns Errno::EPERM against exec()
     * in multiple threads.
     */
    rb_thread_stop_timer_thread(0);
}

static void
before_exec(void)
{
    before_exec_non_async_signal_safe();
    before_exec_async_signal_safe();
}

/* This function should be async-signal-safe.  Actually it is. */
static void
after_exec_async_signal_safe(void)
{
#ifdef SIGPIPE
    signal(SIGPIPE, saved_sigpipe_handler); /* async-signal-safe */
#endif
}

static void
after_exec_non_async_signal_safe(void)
{
    rb_thread_reset_timer_thread();
    rb_thread_start_timer_thread();
}

static void
after_exec(void)
{
    after_exec_async_signal_safe();
    after_exec_non_async_signal_safe();
}

#define before_fork_ruby() before_exec()
#define after_fork_ruby() (rb_threadptr_pending_interrupt_clear(GET_THREAD()), after_exec())

#include "dln.h"

static void
security(const char *str)
{
    if (rb_env_path_tainted()) {
	if (rb_safe_level() > 0) {
	    rb_raise(rb_eSecurityError, "Insecure PATH - %s", str);
	}
    }
}

#if defined(HAVE_WORKING_FORK) && !defined(__native_client__)

/* try_with_sh and exec_with_sh should be async-signal-safe. Actually it is.*/
#define try_with_sh(prog, argv, envp) ((saved_errno == ENOEXEC) ? exec_with_sh((prog), (argv), (envp)) : (void)0)
static void
exec_with_sh(const char *prog, char **argv, char **envp)
{
    *argv = (char *)prog;
    *--argv = (char *)"sh";
    if (envp)
        execve("/bin/sh", argv, envp); /* async-signal-safe */
    else
        execv("/bin/sh", argv); /* async-signal-safe */
}

#else
#define try_with_sh(prog, argv, envp) (void)0
#endif

/* This function should be async-signal-safe.  Actually it is. */
static int
proc_exec_cmd(const char *prog, VALUE argv_str, VALUE envp_str)
{
#ifdef __native_client__
    rb_notimplement();
    UNREACHABLE;
#else
    char **argv;
    char **envp;
# if defined(__EMX__) || defined(OS2)
    char **new_argv = NULL;
# endif

    argv = ARGVSTR2ARGV(argv_str);

    if (!prog) {
	errno = ENOENT;
	return -1;
    }

# if defined(__EMX__) || defined(OS2)
    {
#  define COMMAND "cmd.exe"
	char *extension;

	if ((extension = strrchr(prog, '.')) != NULL && STRCASECMP(extension, ".bat") == 0) {
	    char *p;
	    int n;

	    for (n = 0; argv[n]; n++)
		/* no-op */;
	    new_argv = ALLOC_N(char*, n + 2);
	    for (; n > 0; n--)
		new_argv[n + 1] = argv[n];
	    new_argv[1] = strcpy(ALLOC_N(char, strlen(argv[0]) + 1), argv[0]);
	    for (p = new_argv[1]; *p != '\0'; p++)
		if (*p == '/')
		    *p = '\\';
	    new_argv[0] = COMMAND;
	    argv = new_argv;
	    prog = dln_find_exe_r(argv[0], 0, fbuf, sizeof(fbuf));
	    if (!prog) {
		errno = ENOENT;
		return -1;
	    }
	}
    }
# endif /* __EMX__ */
    envp = envp_str ? (char **)RSTRING_PTR(envp_str) : NULL;
    if (envp_str)
        execve(prog, argv, envp); /* async-signal-safe */
    else
        execv(prog, argv); /* async-signal-safe */
    preserving_errno(try_with_sh(prog, argv, envp)); /* try_with_sh() is async-signal-safe. */
# if defined(__EMX__) || defined(OS2)
    if (new_argv) {
	xfree(new_argv[0]);
	xfree(new_argv);
    }
# endif
    return -1;
#endif
}

/* This function should be async-signal-safe.  Actually it is. */
static int
proc_exec_sh(const char *str, VALUE envp_str)
{
#ifdef __native_client__
    rb_notimplement();
    UNREACHABLE;
#else
    const char *s;

    s = str;
    while (*s == ' ' || *s == '\t' || *s == '\n')
	s++;

    if (!*s) {
        errno = ENOENT;
        return -1;
    }

#ifdef _WIN32
    rb_w32_uspawn(P_OVERLAY, (char *)str, 0);
    return -1;
#else
#if defined(__CYGWIN32__) || defined(__EMX__)
    {
        char fbuf[MAXPATHLEN];
        char *shell = dln_find_exe_r("sh", 0, fbuf, sizeof(fbuf));
        int status = -1;
        if (shell)
            execl(shell, "sh", "-c", str, (char *) NULL);
        else
            status = system(str);
        if (status != -1)
            exit(status);
    }
#else
    if (envp_str)
        execle("/bin/sh", "sh", "-c", str, (char *)NULL, (char **)RSTRING_PTR(envp_str)); /* async-signal-safe */
    else
        execl("/bin/sh", "sh", "-c", str, (char *)NULL); /* async-signal-safe */
#endif
    return -1;
#endif	/* _WIN32 */
#endif
}

int
rb_proc_exec(const char *str)
{
    int ret;
    before_exec();
    ret = proc_exec_sh(str, Qfalse);
    preserving_errno(after_exec());
    return ret;
}

static void
mark_exec_arg(void *ptr)
{
    struct rb_execarg *eargp = ptr;
    if (eargp->use_shell)
        rb_gc_mark(eargp->invoke.sh.shell_script);
    else {
        rb_gc_mark(eargp->invoke.cmd.command_name);
        rb_gc_mark(eargp->invoke.cmd.command_abspath);
        rb_gc_mark(eargp->invoke.cmd.argv_str);
        rb_gc_mark(eargp->invoke.cmd.argv_buf);
    }
    rb_gc_mark(eargp->redirect_fds);
    rb_gc_mark(eargp->envp_str);
    rb_gc_mark(eargp->envp_buf);
    rb_gc_mark(eargp->dup2_tmpbuf);
    rb_gc_mark(eargp->rlimit_limits);
    rb_gc_mark(eargp->fd_dup2);
    rb_gc_mark(eargp->fd_close);
    rb_gc_mark(eargp->fd_open);
    rb_gc_mark(eargp->fd_dup2_child);
    rb_gc_mark(eargp->env_modification);
    rb_gc_mark(eargp->chdir_dir);
}

static size_t
memsize_exec_arg(const void *ptr)
{
    return sizeof(struct rb_execarg);
}

static const rb_data_type_t exec_arg_data_type = {
    "exec_arg",
    {mark_exec_arg, RUBY_TYPED_DEFAULT_FREE, memsize_exec_arg},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#ifdef _WIN32
# define DEFAULT_PROCESS_ENCODING rb_utf8_encoding()
#endif
#ifdef DEFAULT_PROCESS_ENCODING
# define EXPORT_STR(str) rb_str_export_to_enc((str), DEFAULT_PROCESS_ENCODING)
# define EXPORT_DUP(str) export_dup(str)
static VALUE
export_dup(VALUE str)
{
    VALUE newstr = EXPORT_STR(str);
    if (newstr == str) newstr = rb_str_dup(str);
    return newstr;
}
#else
# define EXPORT_STR(str) (str)
# define EXPORT_DUP(str) rb_str_dup(str)
#endif

#if !defined(HAVE_WORKING_FORK) && defined(HAVE_SPAWNV)
# define USE_SPAWNV 1
#else
# define USE_SPAWNV 0
#endif
#ifndef P_NOWAIT
# define P_NOWAIT _P_NOWAIT
#endif

#if USE_SPAWNV
#if defined(_WIN32)
#define proc_spawn_cmd_internal(argv, prog) rb_w32_uaspawn(P_NOWAIT, (prog), (argv))
#else
static rb_pid_t
proc_spawn_cmd_internal(char **argv, char *prog)
{
    char fbuf[MAXPATHLEN];
    rb_pid_t status;

    if (!prog)
	prog = argv[0];
    security(prog);
    prog = dln_find_exe_r(prog, 0, fbuf, sizeof(fbuf));
    if (!prog)
	return -1;

    before_exec();
    status = spawnv(P_NOWAIT, prog, (const char **)argv);
    if (status == -1 && errno == ENOEXEC) {
	*argv = (char *)prog;
	*--argv = (char *)"sh";
	status = spawnv(P_NOWAIT, "/bin/sh", (const char **)argv);
	after_exec();
	if (status == -1) errno = ENOEXEC;
    }
    return status;
}
#endif

static rb_pid_t
proc_spawn_cmd(char **argv, VALUE prog, struct rb_execarg *eargp)
{
    rb_pid_t pid = -1;

    if (argv[0]) {
#if defined(_WIN32)
	DWORD flags = 0;
	if (eargp->new_pgroup_given && eargp->new_pgroup_flag) {
	    flags = CREATE_NEW_PROCESS_GROUP;
	}
	pid = rb_w32_uaspawn_flags(P_NOWAIT, prog ? RSTRING_PTR(prog) : 0, argv, flags);
#else
	pid = proc_spawn_cmd_internal(argv, prog ? RSTRING_PTR(prog) : 0);
#endif
    }
    return pid;
}

#if defined(_WIN32)
#define proc_spawn_sh(str) rb_w32_uspawn(P_NOWAIT, (str), 0)
#else
static rb_pid_t
proc_spawn_sh(char *str)
{
    char fbuf[MAXPATHLEN];
    rb_pid_t status;

    char *shell = dln_find_exe_r("sh", 0, fbuf, sizeof(fbuf));
    before_exec();
    status = spawnl(P_NOWAIT, (shell ? shell : "/bin/sh"), "sh", "-c", str, (char*)NULL);
    after_exec();
    return status;
}
#endif
#endif

static VALUE
hide_obj(VALUE obj)
{
    RBASIC_CLEAR_CLASS(obj);
    return obj;
}

static VALUE
check_exec_redirect_fd(VALUE v, int iskey)
{
    VALUE tmp;
    int fd;
    if (FIXNUM_P(v)) {
        fd = FIX2INT(v);
    }
    else if (SYMBOL_P(v)) {
        ID id = rb_check_id(&v);
        if (id == id_in)
            fd = 0;
        else if (id == id_out)
            fd = 1;
        else if (id == id_err)
            fd = 2;
        else
            goto wrong;
    }
    else if (!NIL_P(tmp = rb_check_convert_type(v, T_FILE, "IO", "to_io"))) {
        rb_io_t *fptr;
        GetOpenFile(tmp, fptr);
        if (fptr->tied_io_for_writing)
            rb_raise(rb_eArgError, "duplex IO redirection");
        fd = fptr->fd;
    }
    else {
      wrong:
        rb_raise(rb_eArgError, "wrong exec redirect");
    }
    if (fd < 0) {
        rb_raise(rb_eArgError, "negative file descriptor");
    }
#ifdef _WIN32
    else if (fd >= 3 && iskey) {
        rb_raise(rb_eArgError, "wrong file descriptor (%d)", fd);
    }
#endif
    return INT2FIX(fd);
}

static VALUE
check_exec_redirect1(VALUE ary, VALUE key, VALUE param)
{
    if (ary == Qfalse) {
        ary = hide_obj(rb_ary_new());
    }
    if (!RB_TYPE_P(key, T_ARRAY)) {
        VALUE fd = check_exec_redirect_fd(key, !NIL_P(param));
        rb_ary_push(ary, hide_obj(rb_assoc_new(fd, param)));
    }
    else {
        int i, n=0;
        for (i = 0 ; i < RARRAY_LEN(key); i++) {
            VALUE v = RARRAY_AREF(key, i);
            VALUE fd = check_exec_redirect_fd(v, !NIL_P(param));
            rb_ary_push(ary, hide_obj(rb_assoc_new(fd, param)));
            n++;
        }
    }
    return ary;
}

static void
check_exec_redirect(VALUE key, VALUE val, struct rb_execarg *eargp)
{
    VALUE param;
    VALUE path, flags, perm;
    VALUE tmp;
    ID id;

    switch (TYPE(val)) {
      case T_SYMBOL:
        if (!(id = rb_check_id(&val))) goto wrong_symbol;
        if (id == id_close) {
            param = Qnil;
            eargp->fd_close = check_exec_redirect1(eargp->fd_close, key, param);
        }
        else if (id == id_in) {
            param = INT2FIX(0);
            eargp->fd_dup2 = check_exec_redirect1(eargp->fd_dup2, key, param);
        }
        else if (id == id_out) {
            param = INT2FIX(1);
            eargp->fd_dup2 = check_exec_redirect1(eargp->fd_dup2, key, param);
        }
        else if (id == id_err) {
            param = INT2FIX(2);
            eargp->fd_dup2 = check_exec_redirect1(eargp->fd_dup2, key, param);
        }
        else {
	  wrong_symbol:
            rb_raise(rb_eArgError, "wrong exec redirect symbol: %"PRIsVALUE,
                                   val);
        }
        break;

      case T_FILE:
      io:
        val = check_exec_redirect_fd(val, 0);
        /* fall through */
      case T_FIXNUM:
        param = val;
        eargp->fd_dup2 = check_exec_redirect1(eargp->fd_dup2, key, param);
        break;

      case T_ARRAY:
        path = rb_ary_entry(val, 0);
        if (RARRAY_LEN(val) == 2 && SYMBOL_P(path) &&
            path == ID2SYM(id_child)) {
            param = check_exec_redirect_fd(rb_ary_entry(val, 1), 0);
            eargp->fd_dup2_child = check_exec_redirect1(eargp->fd_dup2_child, key, param);
        }
        else {
            FilePathValue(path);
            flags = rb_ary_entry(val, 1);
            if (NIL_P(flags))
                flags = INT2NUM(O_RDONLY);
            else if (RB_TYPE_P(flags, T_STRING))
                flags = INT2NUM(rb_io_modestr_oflags(StringValueCStr(flags)));
            else
                flags = rb_to_int(flags);
            perm = rb_ary_entry(val, 2);
            perm = NIL_P(perm) ? INT2FIX(0644) : rb_to_int(perm);
            param = hide_obj(rb_ary_new3(3, hide_obj(EXPORT_DUP(path)),
                                            flags, perm));
            eargp->fd_open = check_exec_redirect1(eargp->fd_open, key, param);
        }
        break;

      case T_STRING:
        path = val;
        FilePathValue(path);
        if (RB_TYPE_P(key, T_FILE))
            key = check_exec_redirect_fd(key, 1);
        if (FIXNUM_P(key) && (FIX2INT(key) == 1 || FIX2INT(key) == 2))
            flags = INT2NUM(O_WRONLY|O_CREAT|O_TRUNC);
        else if (RB_TYPE_P(key, T_ARRAY)) {
	    int i;
	    for (i = 0; i < RARRAY_LEN(key); i++) {
		VALUE v = RARRAY_PTR(key)[i];
		VALUE fd = check_exec_redirect_fd(v, 1);
		if (FIX2INT(fd) != 1 && FIX2INT(fd) != 2) break;
	    }
	    if (i == RARRAY_LEN(key))
		flags = INT2NUM(O_WRONLY|O_CREAT|O_TRUNC);
	    else
		flags = INT2NUM(O_RDONLY);
	}
	else
            flags = INT2NUM(O_RDONLY);
        perm = INT2FIX(0644);
        param = hide_obj(rb_ary_new3(3, hide_obj(EXPORT_DUP(path)),
                                        flags, perm));
        eargp->fd_open = check_exec_redirect1(eargp->fd_open, key, param);
        break;

      default:
	tmp = val;
	val = rb_io_check_io(tmp);
	if (!NIL_P(val)) goto io;
        rb_raise(rb_eArgError, "wrong exec redirect action");
    }

}

#if defined(HAVE_SETRLIMIT) && defined(NUM2RLIM)
static int rlimit_type_by_lname(const char *name);
#endif

int
rb_execarg_addopt(VALUE execarg_obj, VALUE key, VALUE val)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);

    ID id;
#if defined(HAVE_SETRLIMIT) && defined(NUM2RLIM)
    int rtype;
#endif

    rb_secure(2);

    switch (TYPE(key)) {
      case T_SYMBOL:
        if (!(id = rb_check_id(&key))) return ST_STOP;
#ifdef HAVE_SETPGID
        if (id == id_pgroup) {
            rb_pid_t pgroup;
            if (eargp->pgroup_given) {
                rb_raise(rb_eArgError, "pgroup option specified twice");
            }
            if (!RTEST(val))
                pgroup = -1; /* asis(-1) means "don't call setpgid()". */
            else if (val == Qtrue)
                pgroup = 0; /* new process group. */
            else {
                pgroup = NUM2PIDT(val);
                if (pgroup < 0) {
                    rb_raise(rb_eArgError, "negative process group ID : %ld", (long)pgroup);
                }
            }
            eargp->pgroup_given = 1;
            eargp->pgroup_pgid = pgroup;
        }
        else
#endif
#ifdef _WIN32
        if (id == id_new_pgroup) {
            if (eargp->new_pgroup_given) {
                rb_raise(rb_eArgError, "new_pgroup option specified twice");
            }
            eargp->new_pgroup_given = 1;
            eargp->new_pgroup_flag = RTEST(val) ? 1 : 0;
        }
        else
#endif
#if defined(HAVE_SETRLIMIT) && defined(NUM2RLIM)
        if (strncmp("rlimit_", rb_id2name(id), 7) == 0 &&
            (rtype = rlimit_type_by_lname(rb_id2name(id)+7)) != -1) {
            VALUE ary = eargp->rlimit_limits;
            VALUE tmp, softlim, hardlim;
            if (eargp->rlimit_limits == Qfalse)
                ary = eargp->rlimit_limits = hide_obj(rb_ary_new());
            else
                ary = eargp->rlimit_limits;
            tmp = rb_check_array_type(val);
            if (!NIL_P(tmp)) {
                if (RARRAY_LEN(tmp) == 1)
                    softlim = hardlim = rb_to_int(rb_ary_entry(tmp, 0));
                else if (RARRAY_LEN(tmp) == 2) {
                    softlim = rb_to_int(rb_ary_entry(tmp, 0));
                    hardlim = rb_to_int(rb_ary_entry(tmp, 1));
                }
                else {
                    rb_raise(rb_eArgError, "wrong exec rlimit option");
                }
            }
            else {
                softlim = hardlim = rb_to_int(val);
            }
            tmp = hide_obj(rb_ary_new3(3, INT2NUM(rtype), softlim, hardlim));
            rb_ary_push(ary, tmp);
        }
        else
#endif
        if (id == id_unsetenv_others) {
            if (eargp->unsetenv_others_given) {
                rb_raise(rb_eArgError, "unsetenv_others option specified twice");
            }
            eargp->unsetenv_others_given = 1;
            eargp->unsetenv_others_do = RTEST(val) ? 1 : 0;
        }
        else if (id == id_chdir) {
            if (eargp->chdir_given) {
                rb_raise(rb_eArgError, "chdir option specified twice");
            }
            FilePathValue(val);
            eargp->chdir_given = 1;
            eargp->chdir_dir = hide_obj(EXPORT_DUP(val));
        }
        else if (id == id_umask) {
	    mode_t cmask = NUM2MODET(val);
            if (eargp->umask_given) {
                rb_raise(rb_eArgError, "umask option specified twice");
            }
            eargp->umask_given = 1;
            eargp->umask_mask = cmask;
        }
        else if (id == id_close_others) {
            if (eargp->close_others_given) {
                rb_raise(rb_eArgError, "close_others option specified twice");
            }
            eargp->close_others_given = 1;
            eargp->close_others_do = RTEST(val) ? 1 : 0;
        }
        else if (id == id_in) {
            key = INT2FIX(0);
            goto redirect;
        }
        else if (id == id_out) {
            key = INT2FIX(1);
            goto redirect;
        }
        else if (id == id_err) {
            key = INT2FIX(2);
            goto redirect;
        }
	else if (id == id_uid) {
#ifdef HAVE_SETUID
	    if (eargp->uid_given) {
		rb_raise(rb_eArgError, "uid option specified twice");
	    }
	    check_uid_switch();
	    {
		eargp->uid = OBJ2UID(val);
		eargp->uid_given = 1;
	    }
#else
	    rb_raise(rb_eNotImpError,
		     "uid option is unimplemented on this machine");
#endif
	}
	else if (id == id_gid) {
#ifdef HAVE_SETGID
	    if (eargp->gid_given) {
		rb_raise(rb_eArgError, "gid option specified twice");
	    }
	    check_gid_switch();
	    {
		eargp->gid = OBJ2GID(val);
		eargp->gid_given = 1;
	    }
#else
	    rb_raise(rb_eNotImpError,
		     "gid option is unimplemented on this machine");
#endif
	}
        else {
	    return ST_STOP;
        }
        break;

      case T_FIXNUM:
      case T_FILE:
      case T_ARRAY:
redirect:
        check_exec_redirect(key, val, eargp);
        break;

      default:
	return ST_STOP;
    }

    RB_GC_GUARD(execarg_obj);
    return ST_CONTINUE;
}

static int
check_exec_options_i(st_data_t st_key, st_data_t st_val, st_data_t arg)
{
    VALUE key = (VALUE)st_key;
    VALUE val = (VALUE)st_val;
    VALUE execarg_obj = (VALUE)arg;
    if (rb_execarg_addopt(execarg_obj, key, val) != ST_CONTINUE) {
	if (SYMBOL_P(key))
	    rb_raise(rb_eArgError, "wrong exec option symbol: %"PRIsVALUE,
		     key);
	rb_raise(rb_eArgError, "wrong exec option");
    }
    return ST_CONTINUE;
}

static int
check_exec_options_i_extract(st_data_t st_key, st_data_t st_val, st_data_t arg)
{
    VALUE key = (VALUE)st_key;
    VALUE val = (VALUE)st_val;
    VALUE *args = (VALUE *)arg;
    VALUE execarg_obj = args[0];
    if (rb_execarg_addopt(execarg_obj, key, val) != ST_CONTINUE) {
	VALUE nonopts = args[1];
	if (NIL_P(nonopts)) args[1] = nonopts = rb_hash_new();
	rb_hash_aset(nonopts, key, val);
    }
    return ST_CONTINUE;
}

static int
check_exec_fds_1(struct rb_execarg *eargp, VALUE h, int maxhint, VALUE ary)
{
    long i;

    if (ary != Qfalse) {
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            VALUE elt = RARRAY_AREF(ary, i);
            int fd = FIX2INT(RARRAY_AREF(elt, 0));
            if (RTEST(rb_hash_lookup(h, INT2FIX(fd)))) {
                rb_raise(rb_eArgError, "fd %d specified twice", fd);
            }
            if (ary == eargp->fd_open || ary == eargp->fd_dup2)
                rb_hash_aset(h, INT2FIX(fd), Qtrue);
            else if (ary == eargp->fd_dup2_child)
                rb_hash_aset(h, INT2FIX(fd), RARRAY_AREF(elt, 1));
            else /* ary == eargp->fd_close */
                rb_hash_aset(h, INT2FIX(fd), INT2FIX(-1));
            if (maxhint < fd)
                maxhint = fd;
            if (ary == eargp->fd_dup2 || ary == eargp->fd_dup2_child) {
                fd = FIX2INT(RARRAY_AREF(elt, 1));
                if (maxhint < fd)
                    maxhint = fd;
            }
        }
    }
    return maxhint;
}

static VALUE
check_exec_fds(struct rb_execarg *eargp)
{
    VALUE h = rb_hash_new();
    VALUE ary;
    int maxhint = -1;
    long i;

    maxhint = check_exec_fds_1(eargp, h, maxhint, eargp->fd_dup2);
    maxhint = check_exec_fds_1(eargp, h, maxhint, eargp->fd_close);
    maxhint = check_exec_fds_1(eargp, h, maxhint, eargp->fd_open);
    maxhint = check_exec_fds_1(eargp, h, maxhint, eargp->fd_dup2_child);

    if (eargp->fd_dup2_child) {
        ary = eargp->fd_dup2_child;
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            VALUE elt = RARRAY_AREF(ary, i);
            int newfd = FIX2INT(RARRAY_AREF(elt, 0));
            int oldfd = FIX2INT(RARRAY_AREF(elt, 1));
            int lastfd = oldfd;
            VALUE val = rb_hash_lookup(h, INT2FIX(lastfd));
            long depth = 0;
            while (FIXNUM_P(val) && 0 <= FIX2INT(val)) {
                lastfd = FIX2INT(val);
                val = rb_hash_lookup(h, val);
                if (RARRAY_LEN(ary) < depth)
                    rb_raise(rb_eArgError, "cyclic child fd redirection from %d", oldfd);
                depth++;
            }
            if (val != Qtrue)
                rb_raise(rb_eArgError, "child fd %d is not redirected", oldfd);
            if (oldfd != lastfd) {
                VALUE val2;
                rb_ary_store(elt, 1, INT2FIX(lastfd));
                rb_hash_aset(h, INT2FIX(newfd), INT2FIX(lastfd));
                val = INT2FIX(oldfd);
                while (FIXNUM_P(val2 = rb_hash_lookup(h, val))) {
                    rb_hash_aset(h, val, INT2FIX(lastfd));
                    val = val2;
                }
            }
        }
    }

    eargp->close_others_maxhint = maxhint;
    return h;
}

static void
rb_check_exec_options(VALUE opthash, VALUE execarg_obj)
{
    if (RHASH_EMPTY_P(opthash))
        return;
    st_foreach(rb_hash_tbl_raw(opthash), check_exec_options_i, (st_data_t)execarg_obj);
}

VALUE
rb_execarg_extract_options(VALUE execarg_obj, VALUE opthash)
{
    VALUE args[2];
    if (RHASH_EMPTY_P(opthash))
        return Qnil;
    args[0] = execarg_obj;
    args[1] = Qnil;
    st_foreach(rb_hash_tbl_raw(opthash), check_exec_options_i_extract, (st_data_t)args);
    return args[1];
}

static int
check_exec_env_i(st_data_t st_key, st_data_t st_val, st_data_t arg)
{
    VALUE key = (VALUE)st_key;
    VALUE val = (VALUE)st_val;
    VALUE env = (VALUE)arg;
    char *k;

    k = StringValueCStr(key);
    if (strchr(k, '='))
        rb_raise(rb_eArgError, "environment name contains a equal : %s", k);

    if (!NIL_P(val))
        StringValueCStr(val);

    key = EXPORT_STR(key);
    if (!NIL_P(val)) val = EXPORT_STR(val);

    rb_ary_push(env, hide_obj(rb_assoc_new(key, val)));

    return ST_CONTINUE;
}

static VALUE
rb_check_exec_env(VALUE hash)
{
    VALUE env;

    env = hide_obj(rb_ary_new());
    st_foreach(rb_hash_tbl_raw(hash), check_exec_env_i, (st_data_t)env);

    return env;
}

static VALUE
rb_check_argv(int argc, VALUE *argv)
{
    VALUE tmp, prog;
    int i;
    const char *name = 0;

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);

    prog = 0;
    tmp = rb_check_array_type(argv[0]);
    if (!NIL_P(tmp)) {
	if (RARRAY_LEN(tmp) != 2) {
	    rb_raise(rb_eArgError, "wrong first argument");
	}
	prog = RARRAY_AREF(tmp, 0);
	argv[0] = RARRAY_AREF(tmp, 1);
	SafeStringValue(prog);
	StringValueCStr(prog);
	prog = rb_str_new_frozen(prog);
	name = RSTRING_PTR(prog);
    }
    for (i = 0; i < argc; i++) {
	SafeStringValue(argv[i]);
	argv[i] = rb_str_new_frozen(argv[i]);
	StringValueCStr(argv[i]);
    }
    security(name ? name : RSTRING_PTR(argv[0]));
    return prog;
}

static VALUE
rb_exec_getargs(int *argc_p, VALUE **argv_p, int accept_shell, VALUE *env_ret, VALUE *opthash_ret)
{
    VALUE hash, prog;

    if (0 < *argc_p) {
        hash = rb_check_hash_type((*argv_p)[*argc_p-1]);
        if (!NIL_P(hash)) {
            *opthash_ret = hash;
            (*argc_p)--;
        }
    }

    if (0 < *argc_p) {
        hash = rb_check_hash_type((*argv_p)[0]);
        if (!NIL_P(hash)) {
            *env_ret = hash;
            (*argc_p)--;
            (*argv_p)++;
        }
    }
    prog = rb_check_argv(*argc_p, *argv_p);
    if (!prog) {
        prog = (*argv_p)[0];
        if (accept_shell && *argc_p == 1) {
            *argc_p = 0;
            *argv_p = 0;
        }
    }
    return prog;
}

#ifndef _WIN32
struct string_part {
    const char *ptr;
    size_t len;
};

static int
compare_posix_sh(const void *key, const void *el)
{
    const struct string_part *word = key;
    int ret = strncmp(word->ptr, el, word->len);
    if (!ret && ((const char *)el)[word->len]) ret = -1;
    return ret;
}
#endif

static void
rb_exec_fillarg(VALUE prog, int argc, VALUE *argv, VALUE env, VALUE opthash, VALUE execarg_obj)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);
    char fbuf[MAXPATHLEN];

    MEMZERO(eargp, struct rb_execarg, 1);

    if (!NIL_P(opthash)) {
        rb_check_exec_options(opthash, execarg_obj);
    }
    if (!NIL_P(env)) {
        env = rb_check_exec_env(env);
        eargp->env_modification = env;
    }

    prog = EXPORT_STR(prog);
    eargp->use_shell = argc == 0;
    if (eargp->use_shell)
        eargp->invoke.sh.shell_script = prog;
    else
        eargp->invoke.cmd.command_name = prog;

#ifndef _WIN32
    if (eargp->use_shell) {
	static const char posix_sh_cmds[][9] = {
	    "!",		/* reserved */
	    ".",		/* special built-in */
	    ":",		/* special built-in */
	    "break",		/* special built-in */
	    "case",		/* reserved */
	    "continue",		/* special built-in */
	    "do",		/* reserved */
	    "done",		/* reserved */
	    "elif",		/* reserved */
	    "else",		/* reserved */
	    "esac",		/* reserved */
	    "eval",		/* special built-in */
	    "exec",		/* special built-in */
	    "exit",		/* special built-in */
	    "export",		/* special built-in */
	    "fi",		/* reserved */
	    "for",		/* reserved */
	    "if",		/* reserved */
	    "in",		/* reserved */
	    "readonly",		/* special built-in */
	    "return",		/* special built-in */
	    "set",		/* special built-in */
	    "shift",		/* special built-in */
	    "then",		/* reserved */
	    "times",		/* special built-in */
	    "trap",		/* special built-in */
	    "unset",		/* special built-in */
	    "until",		/* reserved */
	    "while",		/* reserved */
	};
	const char *p;
	struct string_part first = {0, 0};
        int has_meta = 0;
        /*
         * meta characters:
         *
         * *    Pathname Expansion
         * ?    Pathname Expansion
         * {}   Grouping Commands
         * []   Pathname Expansion
         * <>   Redirection
         * ()   Grouping Commands
         * ~    Tilde Expansion
         * &    AND Lists, Asynchronous Lists
         * |    OR Lists, Pipelines
         * \    Escape Character
         * $    Parameter Expansion
         * ;    Sequential Lists
         * '    Single-Quotes
         * `    Command Substitution
         * "    Double-Quotes
         * \n   Lists
         *
         * #    Comment
         * =    Assignment preceding command name
         * %    (used in Parameter Expansion)
         */
        for (p = RSTRING_PTR(prog); *p; p++) {
	    if (*p == ' ' || *p == '\t') {
		if (first.ptr && !first.len) first.len = p - first.ptr;
	    }
	    else {
		if (!first.ptr) first.ptr = p;
	    }
            if (!has_meta && strchr("*?{}[]<>()~&|\\$;'`\"\n#", *p))
                has_meta = 1;
	    if (!first.len) {
		if (*p == '=') {
		    has_meta = 1;
		}
		else if (*p == '/') {
		    first.len = 0x100; /* longer than any posix_sh_cmds */
		}
	    }
	    if (has_meta)
                break;
        }
	if (!has_meta && first.ptr) {
	    if (!first.len) first.len = p - first.ptr;
	    if (first.len > 0 && first.len <= sizeof(posix_sh_cmds[0]) &&
		bsearch(&first, posix_sh_cmds, numberof(posix_sh_cmds), sizeof(posix_sh_cmds[0]), compare_posix_sh))
		has_meta = 1;
	}
	if (!has_meta) {
            /* avoid shell since no shell meta character found. */
            eargp->use_shell = 0;
        }
        if (!eargp->use_shell) {
            VALUE argv_buf;
            argv_buf = hide_obj(rb_str_buf_new(0));
            p = RSTRING_PTR(prog);
            while (*p) {
                while (*p == ' ' || *p == '\t')
                    p++;
                if (*p) {
		    const char *w = p;
                    while (*p && *p != ' ' && *p != '\t')
                        p++;
                    rb_str_buf_cat(argv_buf, w, p-w);
                    rb_str_buf_cat(argv_buf, "", 1); /* append '\0' */
                }
            }
            eargp->invoke.cmd.argv_buf = argv_buf;
            eargp->invoke.cmd.command_name = hide_obj(rb_str_new_cstr(RSTRING_PTR(argv_buf)));
        }
    }
#endif

    if (!eargp->use_shell) {
	const char *abspath;
        abspath = dln_find_exe_r(RSTRING_PTR(eargp->invoke.cmd.command_name), 0, fbuf, sizeof(fbuf));
	if (abspath)
	    eargp->invoke.cmd.command_abspath = rb_str_new_cstr(abspath);
	else
	    eargp->invoke.cmd.command_abspath = Qnil;
    }

    if (!eargp->use_shell && !eargp->invoke.cmd.argv_buf) {
        int i;
        VALUE argv_buf;
        argv_buf = rb_str_buf_new(0);
        hide_obj(argv_buf);
        for (i = 0; i < argc; i++) {
	    VALUE arg = argv[i];
	    const char *s = StringValueCStr(arg);
#ifdef DEFAULT_PROCESS_ENCODING
	    arg = EXPORT_STR(arg);
	    s = RSTRING_PTR(arg);
#endif
	    rb_str_buf_cat(argv_buf, s, RSTRING_LEN(arg) + 1); /* include '\0' */
        }
        eargp->invoke.cmd.argv_buf = argv_buf;
    }

    if (!eargp->use_shell) {
        const char *p, *ep, *null=NULL;
        VALUE argv_str;
        argv_str = hide_obj(rb_str_buf_new(sizeof(char*) * (argc + 2)));
        rb_str_buf_cat(argv_str, (char *)&null, sizeof(null)); /* place holder for /bin/sh of try_with_sh. */
        p = RSTRING_PTR(eargp->invoke.cmd.argv_buf);
        ep = p + RSTRING_LEN(eargp->invoke.cmd.argv_buf);
        while (p < ep) {
            rb_str_buf_cat(argv_str, (char *)&p, sizeof(p));
            p += strlen(p) + 1;
        }
        rb_str_buf_cat(argv_str, (char *)&null, sizeof(null)); /* terminator for execve.  */
        eargp->invoke.cmd.argv_str = argv_str;
    }
    RB_GC_GUARD(execarg_obj);
}

VALUE
rb_execarg_new(int argc, const VALUE *argv, int accept_shell)
{
    VALUE execarg_obj;
    struct rb_execarg *eargp;
    execarg_obj = TypedData_Make_Struct(rb_cData, struct rb_execarg, &exec_arg_data_type, eargp);
    hide_obj(execarg_obj);
    rb_execarg_init(argc, argv, accept_shell, execarg_obj);
    return execarg_obj;
}

struct rb_execarg *
rb_execarg_get(VALUE execarg_obj)
{
    struct rb_execarg *eargp;
    TypedData_Get_Struct(execarg_obj, struct rb_execarg, &exec_arg_data_type, eargp);
    return eargp;
}

VALUE
rb_execarg_init(int argc, const VALUE *orig_argv, int accept_shell, VALUE execarg_obj)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);
    VALUE prog, ret;
    VALUE env = Qnil, opthash = Qnil;
    VALUE argv_buf;
    VALUE *argv = ALLOCV_N(VALUE, argv_buf, argc);
    MEMCPY(argv, orig_argv, VALUE, argc);
    prog = rb_exec_getargs(&argc, &argv, accept_shell, &env, &opthash);
    rb_exec_fillarg(prog, argc, argv, env, opthash, execarg_obj);
    ALLOCV_END(argv_buf);
    ret = eargp->use_shell ? eargp->invoke.sh.shell_script : eargp->invoke.cmd.command_name;
    RB_GC_GUARD(execarg_obj);
    return ret;
}

void
rb_execarg_setenv(VALUE execarg_obj, VALUE env)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);
    env = !NIL_P(env) ? rb_check_exec_env(env) : Qfalse;
    eargp->env_modification = env;
}

static int
fill_envp_buf_i(st_data_t st_key, st_data_t st_val, st_data_t arg)
{
    VALUE key = (VALUE)st_key;
    VALUE val = (VALUE)st_val;
    VALUE envp_buf = (VALUE)arg;

    rb_str_buf_cat2(envp_buf, StringValueCStr(key));
    rb_str_buf_cat2(envp_buf, "=");
    rb_str_buf_cat2(envp_buf, StringValueCStr(val));
    rb_str_buf_cat(envp_buf, "", 1); /* append '\0' */

    return ST_CONTINUE;
}


static long run_exec_dup2_tmpbuf_size(long n);

void
rb_execarg_fixup(VALUE execarg_obj)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);
    int unsetenv_others;
    VALUE envopts;
    VALUE ary;

    eargp->redirect_fds = check_exec_fds(eargp);

    ary = eargp->fd_dup2;
    if (ary != Qfalse) {
        size_t len = run_exec_dup2_tmpbuf_size(RARRAY_LEN(ary));
        VALUE tmpbuf = hide_obj(rb_str_new(0, len));
        rb_str_set_len(tmpbuf, len);
        eargp->dup2_tmpbuf = tmpbuf;
    }

    unsetenv_others = eargp->unsetenv_others_given && eargp->unsetenv_others_do;
    envopts = eargp->env_modification;
    if (unsetenv_others || envopts != Qfalse) {
        VALUE envtbl, envp_str, envp_buf;
        char *p, *ep;
        if (unsetenv_others) {
            envtbl = rb_hash_new();
        }
        else {
            envtbl = rb_const_get(rb_cObject, id_ENV);
            envtbl = rb_convert_type(envtbl, T_HASH, "Hash", "to_hash");
        }
        hide_obj(envtbl);
        if (envopts != Qfalse) {
	    st_table *stenv = RHASH_TBL_RAW(envtbl);
            long i;
            for (i = 0; i < RARRAY_LEN(envopts); i++) {
                VALUE pair = RARRAY_AREF(envopts, i);
                VALUE key = RARRAY_AREF(pair, 0);
                VALUE val = RARRAY_AREF(pair, 1);
                if (NIL_P(val)) {
		    st_data_t stkey = (st_data_t)key;
		    st_delete(stenv, &stkey, NULL);
                }
                else {
		    st_insert(stenv, (st_data_t)key, (st_data_t)val);
		    RB_OBJ_WRITTEN(envtbl, Qundef, key);
		    RB_OBJ_WRITTEN(envtbl, Qundef, val);
                }
            }
        }
        envp_buf = rb_str_buf_new(0);
        hide_obj(envp_buf);
        st_foreach(RHASH_TBL_RAW(envtbl), fill_envp_buf_i, (st_data_t)envp_buf);
        envp_str = rb_str_buf_new(sizeof(char*) * (RHASH_SIZE(envtbl) + 1));
        hide_obj(envp_str);
        p = RSTRING_PTR(envp_buf);
        ep = p + RSTRING_LEN(envp_buf);
        while (p < ep) {
            rb_str_buf_cat(envp_str, (char *)&p, sizeof(p));
            p += strlen(p) + 1;
        }
        p = NULL;
        rb_str_buf_cat(envp_str, (char *)&p, sizeof(p));
        eargp->envp_str = envp_str;
        eargp->envp_buf = envp_buf;

        /*
        char **tmp_envp = (char **)RSTRING_PTR(envp_str);
        while (*tmp_envp) {
            printf("%s\n", *tmp_envp);
            tmp_envp++;
        }
        */
    }
    RB_GC_GUARD(execarg_obj);
}

#if defined(__APPLE__) || defined(__HAIKU__)
static int rb_exec_without_timer_thread(const struct rb_execarg *eargp, char *errmsg, size_t errmsg_buflen);
#endif

/*
 *  call-seq:
 *     exec([env,] command... [,options])
 *
 *  Replaces the current process by running the given external _command_, which
 *  can take one of the following forms:
 *
 *  [<code>exec(commandline)</code>]
 *	command line string which is passed to the standard shell
 *  [<code>exec(cmdname, arg1, ...)</code>]
 *	command name and one or more arguments (no shell)
 *  [<code>exec([cmdname, argv0], arg1, ...)</code>]
 *	command name, argv[0] and zero or more arguments (no shell)
 *
 *  In the first form, the string is taken as a command line that is subject to
 *  shell expansion before being executed.
 *
 *  The standard shell always means <code>"/bin/sh"</code> on Unix-like systems,
 *  same as <code>ENV["RUBYSHELL"]</code>
 *  (or <code>ENV["COMSPEC"]</code> on Windows NT series), and similar.
 *
 *  If the string from the first form (<code>exec("command")</code>) follows
 *  these simple rules:
 *
 *  * no meta characters
 *  * no shell reserved word and no special built-in
 *  * Ruby invokes the command directly without shell
 *
 *  You can force shell invocation by adding ";" to the string (because ";" is
 *  a meta character).
 *
 *  Note that this behavior is observable by pid obtained
 *  (return value of spawn() and IO#pid for IO.popen) is the pid of the invoked
 *  command, not shell.
 *
 *  In the second form (<code>exec("command1", "arg1", ...)</code>), the first
 *  is taken as a command name and the rest are passed as parameters to command
 *  with no shell expansion.
 *
 *  In the third form (<code>exec(["command", "argv0"], "arg1", ...)</code>),
 *  starting a two-element array at the beginning of the command, the first
 *  element is the command to be executed, and the second argument is used as
 *  the <code>argv[0]</code> value, which may show up in process listings.
 *
 *  In order to execute the command, one of the <code>exec(2)</code> system
 *  calls are used, so the running command may inherit some of the environment
 *  of the original program (including open file descriptors).
 *
 *  This behavior is modified by the given +env+ and +options+ parameters. See
 *  ::spawn for details.
 *
 *  If the command fails to execute (typically <code>Errno::ENOENT</code> when
 *  it was not found) a SystemCallError exception is raised.
 *
 *  This method modifies process attributes according to given +options+ before
 *  <code>exec(2)</code> system call. See ::spawn for more details about the
 *  given +options+.
 *
 *  The modified attributes may be retained when <code>exec(2)</code> system
 *  call fails.
 *
 *  For example, hard resource limits are not restorable.
 *
 *  Consider to create a child process using ::spawn or Kernel#system if this
 *  is not acceptable.
 *
 *     exec "echo *"       # echoes list of files in current directory
 *     # never get here
 *
 *     exec "echo", "*"    # echoes an asterisk
 *     # never get here
 */

VALUE
rb_f_exec(int argc, const VALUE *argv)
{
    VALUE execarg_obj, fail_str;
    struct rb_execarg *eargp;
#define CHILD_ERRMSG_BUFLEN 80
    char errmsg[CHILD_ERRMSG_BUFLEN] = { '\0' };

    execarg_obj = rb_execarg_new(argc, argv, TRUE);
    eargp = rb_execarg_get(execarg_obj);
    rb_execarg_fixup(execarg_obj);
    fail_str = eargp->use_shell ? eargp->invoke.sh.shell_script : eargp->invoke.cmd.command_name;

#if defined(__APPLE__) || defined(__HAIKU__)
    rb_exec_without_timer_thread(eargp, errmsg, sizeof(errmsg));
#else
    before_exec_async_signal_safe(); /* async-signal-safe */
    rb_exec_async_signal_safe(eargp, errmsg, sizeof(errmsg));
    preserving_errno(after_exec_async_signal_safe()); /* async-signal-safe */
#endif
    RB_GC_GUARD(execarg_obj);
    if (errmsg[0])
        rb_sys_fail(errmsg);
    rb_sys_fail_str(fail_str);
    return Qnil;		/* dummy */
}

#define ERRMSG(str) do { if (errmsg && 0 < errmsg_buflen) strlcpy(errmsg, (str), errmsg_buflen); } while (0)

/*#define DEBUG_REDIRECT*/
#if defined(DEBUG_REDIRECT)

#include <stdarg.h>

static void
ttyprintf(const char *fmt, ...)
{
    va_list ap;
    FILE *tty;
    int save = errno;
#ifdef _WIN32
    tty = fopen("con", "w");
#else
    tty = fopen("/dev/tty", "w");
#endif
    if (!tty)
        return;

    va_start(ap, fmt);
    vfprintf(tty, fmt, ap);
    va_end(ap);
    fclose(tty);
    errno = save;
}

static int
redirect_dup(int oldfd)
{
    int ret;
    ret = dup(oldfd);
    ttyprintf("dup(%d) => %d\n", oldfd, ret);
    return ret;
}

static int
redirect_dup2(int oldfd, int newfd)
{
    int ret;
    ret = dup2(oldfd, newfd);
    ttyprintf("dup2(%d, %d)\n", oldfd, newfd);
    return ret;
}

static int
redirect_close(int fd)
{
    int ret;
    ret = close(fd);
    ttyprintf("close(%d)\n", fd);
    return ret;
}

static int
redirect_open(const char *pathname, int flags, mode_t perm)
{
    int ret;
    ret = open(pathname, flags, perm);
    ttyprintf("open(\"%s\", 0x%x, 0%o) => %d\n", pathname, flags, perm, ret);
    return ret;
}

#else
#define redirect_dup(oldfd) dup(oldfd)
#define redirect_dup2(oldfd, newfd) dup2((oldfd), (newfd))
#define redirect_close(fd) close(fd)
#define redirect_open(pathname, flags, perm) open((pathname), (flags), (perm))
#endif

static int
save_redirect_fd(int fd, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    if (sargp) {
        VALUE newary;
        int save_fd = redirect_dup(fd);
        if (save_fd == -1) {
            if (errno == EBADF)
                return 0;
            ERRMSG("dup");
            return -1;
        }
        rb_update_max_fd(save_fd);
        newary = sargp->fd_dup2;
        if (newary == Qfalse) {
            newary = hide_obj(rb_ary_new());
            sargp->fd_dup2 = newary;
        }
        rb_ary_push(newary,
                    hide_obj(rb_assoc_new(INT2FIX(fd), INT2FIX(save_fd))));

        newary = sargp->fd_close;
        if (newary == Qfalse) {
            newary = hide_obj(rb_ary_new());
            sargp->fd_close = newary;
        }
        rb_ary_push(newary, hide_obj(rb_assoc_new(INT2FIX(save_fd), Qnil)));
    }

    return 0;
}

static int
intcmp(const void *a, const void *b)
{
    return *(int*)a - *(int*)b;
}

static int
intrcmp(const void *a, const void *b)
{
    return *(int*)b - *(int*)a;
}

struct run_exec_dup2_fd_pair {
    int oldfd;
    int newfd;
    long older_index;
    long num_newer;
};

static long
run_exec_dup2_tmpbuf_size(long n)
{
    return sizeof(struct run_exec_dup2_fd_pair) * n;
}

/* This function should be async-signal-safe when sargp is NULL.  Hopefully it is. */
static int
run_exec_dup2(VALUE ary, VALUE tmpbuf, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    long n, i;
    int ret;
    int extra_fd = -1;
    struct run_exec_dup2_fd_pair *pairs = 0;

    n = RARRAY_LEN(ary);
    pairs = (struct run_exec_dup2_fd_pair *)RSTRING_PTR(tmpbuf);

    /* initialize oldfd and newfd: O(n) */
    for (i = 0; i < n; i++) {
        VALUE elt = RARRAY_AREF(ary, i);
        pairs[i].oldfd = FIX2INT(RARRAY_AREF(elt, 1));
        pairs[i].newfd = FIX2INT(RARRAY_AREF(elt, 0)); /* unique */
        pairs[i].older_index = -1;
    }

    /* sort the table by oldfd: O(n log n) */
    if (!sargp)
        qsort(pairs, n, sizeof(struct run_exec_dup2_fd_pair), intcmp); /* hopefully async-signal-safe */
    else
        qsort(pairs, n, sizeof(struct run_exec_dup2_fd_pair), intrcmp);

    /* initialize older_index and num_newer: O(n log n) */
    for (i = 0; i < n; i++) {
        int newfd = pairs[i].newfd;
        struct run_exec_dup2_fd_pair key, *found;
        key.oldfd = newfd;
        found = bsearch(&key, pairs, n, sizeof(struct run_exec_dup2_fd_pair), intcmp); /* hopefully async-signal-safe */
        pairs[i].num_newer = 0;
        if (found) {
            while (pairs < found && (found-1)->oldfd == newfd)
                found--;
            while (found < pairs+n && found->oldfd == newfd) {
                pairs[i].num_newer++;
                found->older_index = i;
                found++;
            }
        }
    }

    /* non-cyclic redirection: O(n) */
    for (i = 0; i < n; i++) {
        long j = i;
        while (j != -1 && pairs[j].oldfd != -1 && pairs[j].num_newer == 0) {
            if (save_redirect_fd(pairs[j].newfd, sargp, errmsg, errmsg_buflen) < 0) /* async-signal-safe */
                goto fail;
            ret = redirect_dup2(pairs[j].oldfd, pairs[j].newfd); /* async-signal-safe */
            if (ret == -1) {
                ERRMSG("dup2");
                goto fail;
            }
            rb_update_max_fd(pairs[j].newfd); /* async-signal-safe but don't need to call it in a child process. */
            pairs[j].oldfd = -1;
            j = pairs[j].older_index;
            if (j != -1)
                pairs[j].num_newer--;
        }
    }

    /* cyclic redirection: O(n) */
    for (i = 0; i < n; i++) {
        long j;
        if (pairs[i].oldfd == -1)
            continue;
        if (pairs[i].oldfd == pairs[i].newfd) { /* self cycle */
#ifdef F_GETFD
            int fd = pairs[i].oldfd;
            ret = fcntl(fd, F_GETFD); /* async-signal-safe */
            if (ret == -1) {
                ERRMSG("fcntl(F_GETFD)");
                goto fail;
            }
            if (ret & FD_CLOEXEC) {
                ret &= ~FD_CLOEXEC;
                ret = fcntl(fd, F_SETFD, ret); /* async-signal-safe */
                if (ret == -1) {
                    ERRMSG("fcntl(F_SETFD)");
                    goto fail;
                }
            }
#endif
            pairs[i].oldfd = -1;
            continue;
        }
        if (extra_fd == -1) {
            extra_fd = redirect_dup(pairs[i].oldfd); /* async-signal-safe */
            if (extra_fd == -1) {
                ERRMSG("dup");
                goto fail;
            }
            rb_update_max_fd(extra_fd);
        }
        else {
            ret = redirect_dup2(pairs[i].oldfd, extra_fd); /* async-signal-safe */
            if (ret == -1) {
                ERRMSG("dup2");
                goto fail;
            }
            rb_update_max_fd(extra_fd);
        }
        pairs[i].oldfd = extra_fd;
        j = pairs[i].older_index;
        pairs[i].older_index = -1;
        while (j != -1) {
            ret = redirect_dup2(pairs[j].oldfd, pairs[j].newfd); /* async-signal-safe */
            if (ret == -1) {
                ERRMSG("dup2");
                goto fail;
            }
            rb_update_max_fd(ret);
            pairs[j].oldfd = -1;
            j = pairs[j].older_index;
        }
    }
    if (extra_fd != -1) {
        ret = redirect_close(extra_fd); /* async-signal-safe */
        if (ret == -1) {
            ERRMSG("close");
            goto fail;
        }
    }

    return 0;

  fail:
    return -1;
}

/* This function should be async-signal-safe.  Actually it is. */
static int
run_exec_close(VALUE ary, char *errmsg, size_t errmsg_buflen)
{
    long i;
    int ret;

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        VALUE elt = RARRAY_AREF(ary, i);
        int fd = FIX2INT(RARRAY_AREF(elt, 0));
        ret = redirect_close(fd); /* async-signal-safe */
        if (ret == -1) {
            ERRMSG("close");
            return -1;
        }
    }
    return 0;
}

/* This function should be async-signal-safe when sargp is NULL.  Actually it is. */
static int
run_exec_open(VALUE ary, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    long i;
    int ret;

    for (i = 0; i < RARRAY_LEN(ary);) {
        VALUE elt = RARRAY_AREF(ary, i);
        int fd = FIX2INT(RARRAY_AREF(elt, 0));
        VALUE param = RARRAY_AREF(elt, 1);
        const VALUE vpath = RARRAY_AREF(param, 0);
        const char *path = RSTRING_PTR(vpath);
        int flags = NUM2INT(RARRAY_AREF(param, 1));
        int perm = NUM2INT(RARRAY_AREF(param, 2));
        int need_close = 1;
        int fd2 = redirect_open(path, flags, perm); /* async-signal-safe */
        if (fd2 == -1) {
            ERRMSG("open");
            return -1;
        }
        rb_update_max_fd(fd2);
        while (i < RARRAY_LEN(ary) &&
               (elt = RARRAY_AREF(ary, i), RARRAY_AREF(elt, 1) == param)) {
            fd = FIX2INT(RARRAY_AREF(elt, 0));
            if (fd == fd2) {
                need_close = 0;
            }
            else {
                if (save_redirect_fd(fd, sargp, errmsg, errmsg_buflen) < 0) /* async-signal-safe */
                    return -1;
                ret = redirect_dup2(fd2, fd); /* async-signal-safe */
                if (ret == -1) {
                    ERRMSG("dup2");
                    return -1;
                }
                rb_update_max_fd(fd);
            }
            i++;
        }
        if (need_close) {
            ret = redirect_close(fd2); /* async-signal-safe */
            if (ret == -1) {
                ERRMSG("close");
                return -1;
            }
        }
    }
    return 0;
}

/* This function should be async-signal-safe when sargp is NULL.  Actually it is. */
static int
run_exec_dup2_child(VALUE ary, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    long i;
    int ret;

    for (i = 0; i < RARRAY_LEN(ary); i++) {
        VALUE elt = RARRAY_AREF(ary, i);
        int newfd = FIX2INT(RARRAY_AREF(elt, 0));
        int oldfd = FIX2INT(RARRAY_AREF(elt, 1));

        if (save_redirect_fd(newfd, sargp, errmsg, errmsg_buflen) < 0) /* async-signal-safe */
            return -1;
        ret = redirect_dup2(oldfd, newfd); /* async-signal-safe */
        if (ret == -1) {
            ERRMSG("dup2");
            return -1;
        }
        rb_update_max_fd(newfd);
    }
    return 0;
}

#ifdef HAVE_SETPGID
/* This function should be async-signal-safe when sargp is NULL.  Actually it is. */
static int
run_exec_pgroup(const struct rb_execarg *eargp, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    /*
     * If FD_CLOEXEC is available, rb_fork_async_signal_safe waits the child's execve.
     * So setpgid is done in the child when rb_fork_async_signal_safe is returned in
     * the parent.
     * No race condition, even without setpgid from the parent.
     * (Is there an environment which has setpgid but no FD_CLOEXEC?)
     */
    int ret;
    rb_pid_t pgroup;

    pgroup = eargp->pgroup_pgid;
    if (pgroup == -1)
        return 0;

    if (sargp) {
        /* maybe meaningless with no fork environment... */
        sargp->pgroup_given = 1;
        sargp->pgroup_pgid = getpgrp();
    }

    if (pgroup == 0) {
        pgroup = getpid(); /* async-signal-safe */
    }
    ret = setpgid(getpid(), pgroup); /* async-signal-safe */
    if (ret == -1) ERRMSG("setpgid");
    return ret;
}
#endif

#if defined(HAVE_SETRLIMIT) && defined(RLIM2NUM)
/* This function should be async-signal-safe when sargp is NULL.  Hopefully it is. */
static int
run_exec_rlimit(VALUE ary, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    long i;
    for (i = 0; i < RARRAY_LEN(ary); i++) {
        VALUE elt = RARRAY_AREF(ary, i);
        int rtype = NUM2INT(RARRAY_AREF(elt, 0));
        struct rlimit rlim;
        if (sargp) {
            VALUE tmp, newary;
            if (getrlimit(rtype, &rlim) == -1) {
                ERRMSG("getrlimit");
                return -1;
            }
            tmp = hide_obj(rb_ary_new3(3, RARRAY_AREF(elt, 0),
                                       RLIM2NUM(rlim.rlim_cur),
                                       RLIM2NUM(rlim.rlim_max)));
            if (sargp->rlimit_limits == Qfalse)
                newary = sargp->rlimit_limits = hide_obj(rb_ary_new());
            else
                newary = sargp->rlimit_limits;
            rb_ary_push(newary, tmp);
        }
        rlim.rlim_cur = NUM2RLIM(RARRAY_AREF(elt, 1));
        rlim.rlim_max = NUM2RLIM(RARRAY_AREF(elt, 2));
        if (setrlimit(rtype, &rlim) == -1) { /* hopefully async-signal-safe */
            ERRMSG("setrlimit");
            return -1;
        }
    }
    return 0;
}
#endif

#if !defined(HAVE_WORKING_FORK)
static VALUE
save_env_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, ary))
{
    rb_ary_push(ary, hide_obj(rb_ary_dup(argv[0])));
    return Qnil;
}

static void
save_env(struct rb_execarg *sargp)
{
    if (!sargp)
        return;
    if (sargp->env_modification == Qfalse) {
        VALUE env = rb_const_get(rb_cObject, id_ENV);
        if (RTEST(env)) {
            VALUE ary = hide_obj(rb_ary_new());
            rb_block_call(env, idEach, 0, 0, save_env_i,
                          (VALUE)ary);
            sargp->env_modification = ary;
        }
        sargp->unsetenv_others_given = 1;
        sargp->unsetenv_others_do = 1;
    }
}
#endif

/* This function should be async-signal-safe when sargp is NULL.  Hopefully it is. */
int
rb_execarg_run_options(const struct rb_execarg *eargp, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    VALUE obj;

    if (sargp) {
        /* assume that sargp is always NULL on fork-able environments */
        MEMZERO(sargp, struct rb_execarg, 1);
        sargp->redirect_fds = Qnil;
    }

#ifdef HAVE_SETPGID
    if (eargp->pgroup_given) {
        if (run_exec_pgroup(eargp, sargp, errmsg, errmsg_buflen) == -1) /* async-signal-safe */
            return -1;
    }
#endif

#if defined(HAVE_SETRLIMIT) && defined(RLIM2NUM)
    obj = eargp->rlimit_limits;
    if (obj != Qfalse) {
        if (run_exec_rlimit(obj, sargp, errmsg, errmsg_buflen) == -1) /* hopefully async-signal-safe */
            return -1;
    }
#endif

#if !defined(HAVE_WORKING_FORK)
    if (eargp->unsetenv_others_given && eargp->unsetenv_others_do) {
        save_env(sargp);
        rb_env_clear();
    }

    obj = eargp->env_modification;
    if (obj != Qfalse) {
        long i;
        save_env(sargp);
        for (i = 0; i < RARRAY_LEN(obj); i++) {
            VALUE pair = RARRAY_AREF(obj, i);
            VALUE key = RARRAY_AREF(pair, 0);
            VALUE val = RARRAY_AREF(pair, 1);
            if (NIL_P(val))
                ruby_setenv(StringValueCStr(key), 0);
            else
                ruby_setenv(StringValueCStr(key), StringValueCStr(val));
        }
    }
#endif

    if (eargp->umask_given) {
        mode_t mask = eargp->umask_mask;
        mode_t oldmask = umask(mask); /* never fail */ /* async-signal-safe */
        if (sargp) {
            sargp->umask_given = 1;
            sargp->umask_mask = oldmask;
        }
    }

    obj = eargp->fd_dup2;
    if (obj != Qfalse) {
        if (run_exec_dup2(obj, eargp->dup2_tmpbuf, sargp, errmsg, errmsg_buflen) == -1) /* hopefully async-signal-safe */
            return -1;
    }

    obj = eargp->fd_close;
    if (obj != Qfalse) {
        if (sargp)
            rb_warn("cannot close fd before spawn");
        else {
            if (run_exec_close(obj, errmsg, errmsg_buflen) == -1) /* async-signal-safe */
                return -1;
        }
    }

#ifdef HAVE_WORKING_FORK
    if (!eargp->close_others_given || eargp->close_others_do) {
        rb_close_before_exec(3, eargp->close_others_maxhint, eargp->redirect_fds); /* async-signal-safe */
    }
#endif

    obj = eargp->fd_open;
    if (obj != Qfalse) {
        if (run_exec_open(obj, sargp, errmsg, errmsg_buflen) == -1) /* async-signal-safe */
            return -1;
    }

    obj = eargp->fd_dup2_child;
    if (obj != Qfalse) {
        if (run_exec_dup2_child(obj, sargp, errmsg, errmsg_buflen) == -1) /* async-signal-safe */
            return -1;
    }

    if (eargp->chdir_given) {
        if (sargp) {
            char *cwd = my_getcwd();
            sargp->chdir_given = 1;
            sargp->chdir_dir = hide_obj(rb_str_new2(cwd));
            xfree(cwd);
        }
        if (chdir(RSTRING_PTR(eargp->chdir_dir)) == -1) { /* async-signal-safe */
            ERRMSG("chdir");
            return -1;
        }
    }

#ifdef HAVE_SETGID
    if (eargp->gid_given) {
	if (setgid(eargp->gid) < 0) {
	    ERRMSG("setgid");
	    return -1;
	}
    }
#endif
#ifdef HAVE_SETUID
    if (eargp->uid_given) {
	if (setuid(eargp->uid) < 0) {
	    ERRMSG("setuid");
	    return -1;
	}
    }
#endif

    if (sargp) {
        VALUE ary = sargp->fd_dup2;
        if (ary != Qfalse) {
            size_t len = run_exec_dup2_tmpbuf_size(RARRAY_LEN(ary));
            VALUE tmpbuf = hide_obj(rb_str_new(0, len));
            rb_str_set_len(tmpbuf, len);
            sargp->dup2_tmpbuf = tmpbuf;
        }
    }

    return 0;
}

/* This function should be async-signal-safe.  Hopefully it is. */
int
rb_exec_async_signal_safe(const struct rb_execarg *eargp, char *errmsg, size_t errmsg_buflen)
{
#if !defined(HAVE_WORKING_FORK)
    struct rb_execarg sarg, *const sargp = &sarg;
#else
    struct rb_execarg *const sargp = NULL;
#endif

    if (rb_execarg_run_options(eargp, sargp, errmsg, errmsg_buflen) < 0) { /* hopefully async-signal-safe */
        goto failure;
    }

    if (eargp->use_shell) {
	proc_exec_sh(RSTRING_PTR(eargp->invoke.sh.shell_script), eargp->envp_str); /* async-signal-safe */
    }
    else {
	char *abspath = NULL;
	if (!NIL_P(eargp->invoke.cmd.command_abspath))
	    abspath = RSTRING_PTR(eargp->invoke.cmd.command_abspath);
	proc_exec_cmd(abspath, eargp->invoke.cmd.argv_str, eargp->envp_str); /* async-signal-safe */
    }
#if !defined(HAVE_WORKING_FORK)
    preserving_errno(rb_execarg_run_options(sargp, NULL, errmsg, errmsg_buflen));
#endif

failure:
    return -1;
}

#if defined(__APPLE__) || defined(__HAIKU__)
static int
rb_exec_without_timer_thread(const struct rb_execarg *eargp, char *errmsg, size_t errmsg_buflen)
{
    int ret;
    before_exec();
    ret = rb_exec_async_signal_safe(eargp, errmsg, errmsg_buflen); /* hopefully async-signal-safe */
    preserving_errno(after_exec()); /* not async-signal-safe because it calls rb_thread_start_timer_thread.  */
    return ret;
}
#endif

#ifdef HAVE_WORKING_FORK
/* This function should be async-signal-safe.  Hopefully it is. */
static int
rb_exec_atfork(void* arg, char *errmsg, size_t errmsg_buflen)
{
    return rb_exec_async_signal_safe(arg, errmsg, errmsg_buflen); /* hopefully async-signal-safe */
}
#endif

#ifdef HAVE_WORKING_FORK
#if SIZEOF_INT == SIZEOF_LONG
#define proc_syswait (VALUE (*)(VALUE))rb_syswait
#else
static VALUE
proc_syswait(VALUE pid)
{
    rb_syswait((int)pid);
    return Qnil;
}
#endif

static int
move_fds_to_avoid_crash(int *fdp, int n, VALUE fds)
{
    int min = 0;
    int i;
    for (i = 0; i < n; i++) {
        int ret;
        while (RTEST(rb_hash_lookup(fds, INT2FIX(fdp[i])))) {
            if (min <= fdp[i])
                min = fdp[i]+1;
            while (RTEST(rb_hash_lookup(fds, INT2FIX(min))))
                min++;
            ret = rb_cloexec_fcntl_dupfd(fdp[i], min);
            if (ret == -1)
                return -1;
            rb_update_max_fd(ret);
            close(fdp[i]);
            fdp[i] = ret;
        }
    }
    return 0;
}

static int
pipe_nocrash(int filedes[2], VALUE fds)
{
    int ret;
    ret = rb_pipe(filedes);
    if (ret == -1)
        return -1;
    if (RTEST(fds)) {
        int save = errno;
        if (move_fds_to_avoid_crash(filedes, 2, fds) == -1) {
            close(filedes[0]);
            close(filedes[1]);
            return -1;
        }
        errno = save;
    }
    return ret;
}

#ifndef O_BINARY
#define O_BINARY 0
#endif

static int
handle_fork_error(int *status, int *ep, volatile int *try_gc_p)
{
    int state = 0;

    switch (errno) {
      case ENOMEM:
        if ((*try_gc_p)-- > 0 && !rb_during_gc()) {
            rb_gc();
            return 0;
        }
        break;
      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
        if (!status && !ep) {
            rb_thread_sleep(1);
            return 0;
        }
        else {
            rb_protect((VALUE (*)())rb_thread_sleep, 1, &state);
            if (status) *status = state;
            if (!state) return 0;
        }
        break;
    }
    if (ep) {
        preserving_errno((close(ep[0]), close(ep[1])));
    }
    if (state && !status) rb_jump_tag(state);
    return -1;
}

#define prefork() (		\
	rb_io_flush(rb_stdout), \
	rb_io_flush(rb_stderr)	\
	)

/*
 * Forks child process, and returns the process ID in the parent
 * process.
 *
 * If +status+ is given, protects from any exceptions and sets the
 * jump status to it, and returns -1.  If failed to fork new process
 * but no exceptions occurred, sets 0 to it.  Otherwise, if forked
 * successfully, the value of +status+ is undetermined.
 *
 * In the child process, just returns 0 if +chfunc+ is +NULL+.
 * Otherwise +chfunc+ will be called with +charg+, and then the child
 * process exits with +EXIT_SUCCESS+ when it returned zero.
 *
 * In the case of the function is called and returns non-zero value,
 * the child process exits with non-+EXIT_SUCCESS+ value (normally
 * 127).  And, on the platforms where +FD_CLOEXEC+ is available,
 * +errno+ is propagated to the parent process, and this function
 * returns -1 in the parent process.  On the other platforms, just
 * returns pid.
 *
 * If fds is not Qnil, internal pipe for the errno propagation is
 * arranged to avoid conflicts of the hash keys in +fds+.
 *
 * +chfunc+ must not raise any exceptions.
 */

static ssize_t
write_retry(int fd, const void *buf, size_t len)
{
    ssize_t w;

    do {
	w = write(fd, buf, len);
    } while (w < 0 && errno == EINTR);

    return w;
}

static ssize_t
read_retry(int fd, void *buf, size_t len)
{
    ssize_t r;

    do {
	r = read(fd, buf, len);
    } while (r < 0 && errno == EINTR);

    return r;
}

static void
send_child_error(int fd, char *errmsg, size_t errmsg_buflen)
{
    int err;

    err = errno;
    if (write_retry(fd, &err, sizeof(err)) < 0) err = errno;
    if (errmsg && 0 < errmsg_buflen) {
        errmsg[errmsg_buflen-1] = '\0';
        errmsg_buflen = strlen(errmsg);
        if (errmsg_buflen > 0 && write_retry(fd, errmsg, errmsg_buflen) < 0)
            err = errno;
    }
}

static int
recv_child_error(int fd, int *errp, char *errmsg, size_t errmsg_buflen)
{
    int err;
    ssize_t size;
    if ((size = read_retry(fd, &err, sizeof(err))) < 0) {
        err = errno;
    }
    *errp = err;
    if (size == sizeof(err) &&
        errmsg && 0 < errmsg_buflen) {
        ssize_t ret = read_retry(fd, errmsg, errmsg_buflen-1);
        if (0 <= ret) {
            errmsg[ret] = '\0';
        }
    }
    close(fd);
    return size != 0;
}

#ifdef HAVE_WORKING_VFORK
#if !defined(HAVE_GETRESUID) && defined(HAVE_GETUIDX)
/* AIX 7.1 */
static int
getresuid(rb_uid_t *ruid, rb_uid_t *euid, rb_uid_t *suid)
{
    rb_uid_t ret;

    *ruid = getuid();
    *euid = geteuid();
    ret = getuidx(ID_SAVED);
    if (ret == (rb_uid_t)-1)
	return -1;
    *suid = ret;
    return 0;
}
#define HAVE_GETRESUID
#endif

#if !defined(HAVE_GETRESGID) && defined(HAVE_GETGIDX)
/* AIX 7.1 */
static int
getresgid(rb_gid_t *rgid, rb_gid_t *egid, rb_gid_t *sgid)
{
    rb_gid_t ret;

    *rgid = getgid();
    *egid = getegid();
    ret = getgidx(ID_SAVED);
    if (ret == (rb_gid_t)-1)
	return -1;
    *sgid = ret;
    return 0;
}
#define HAVE_GETRESGID
#endif

static int
has_privilege(void)
{
    /*
     * has_privilege() is used to choose vfork() or fork().
     *
     * If the process has privilege, the parent process or
     * the child process can change UID/GID.
     * If vfork() is used to create the child process and
     * the parent or child process change effective UID/GID,
     * different privileged processes shares memory.
     * It is a bad situation.
     * So, fork() should be used.
     */

    rb_uid_t ruid, euid;
    rb_gid_t rgid, egid;

#if defined HAVE_ISSETUGID
    if (issetugid())
	return 1;
#endif

#ifdef HAVE_GETRESUID
    {
        int ret;
        rb_uid_t suid;
        ret = getresuid(&ruid, &euid, &suid);
        if (ret == -1)
            rb_sys_fail("getresuid(2)");
        if (euid != suid)
            return 1;
    }
#else
    ruid = getuid();
    euid = geteuid();
#endif

    if (euid == 0 || euid != ruid)
        return 1;

#ifdef HAVE_GETRESGID
    {
        int ret;
        rb_gid_t sgid;
        ret = getresgid(&rgid, &egid, &sgid);
        if (ret == -1)
            rb_sys_fail("getresgid(2)");
        if (egid != sgid)
            return 1;
    }
#else
    rgid = getgid();
    egid = getegid();
#endif

    if (egid != rgid)
        return 1;

    return 0;
}
#endif

struct child_handler_disabler_state
{
    sigset_t sigmask;
    int cancelstate;
};

static void
disable_child_handler_before_fork(struct child_handler_disabler_state *old)
{
    int ret;
    sigset_t all;

#ifdef HAVE_PTHREAD_SIGMASK
    ret = sigfillset(&all);
    if (ret == -1)
        rb_sys_fail("sigfillset");

    ret = pthread_sigmask(SIG_SETMASK, &all, &old->sigmask); /* not async-signal-safe */
    if (ret != 0) {
        errno = ret;
        rb_sys_fail("pthread_sigmask");
    }
#else
# pragma GCC warning "pthread_sigmask on fork is not available. potentially dangerous"
#endif

#ifdef PTHREAD_CANCEL_DISABLE
    ret = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old->cancelstate);
    if (ret != 0) {
        errno = ret;
        rb_sys_fail("pthread_setcancelstate");
    }
#endif
}

static void
disable_child_handler_fork_parent(struct child_handler_disabler_state *old)
{
    int ret;

#ifdef PTHREAD_CANCEL_DISABLE
    ret = pthread_setcancelstate(old->cancelstate, NULL);
    if (ret != 0) {
        errno = ret;
        rb_sys_fail("pthread_setcancelstate");
    }
#endif

#ifdef HAVE_PTHREAD_SIGMASK
    ret = pthread_sigmask(SIG_SETMASK, &old->sigmask, NULL); /* not async-signal-safe */
    if (ret != 0) {
        errno = ret;
        rb_sys_fail("pthread_sigmask");
    }
#else
# pragma GCC warning "pthread_sigmask on fork is not available. potentially dangerous"
#endif
}

/* This function should be async-signal-safe.  Actually it is. */
static int
disable_child_handler_fork_child(struct child_handler_disabler_state *old, char *errmsg, size_t errmsg_buflen)
{
    int sig;
    int ret;
#ifdef POSIX_SIGNAL
    struct sigaction act, oact;

    act.sa_handler = SIG_DFL;
    act.sa_flags = 0;
    ret = sigemptyset(&act.sa_mask); /* async-signal-safe */
    if (ret == -1) {
        ERRMSG("sigemptyset");
        return -1;
    }
#else
    sig_t handler;
#endif

    for (sig = 1; sig < NSIG; sig++) {
        int reset = 0;
#ifdef SIGPIPE
        if (sig == SIGPIPE)
            reset = 1;
#endif
        if (!reset) {
#ifdef POSIX_SIGNAL
            ret = sigaction(sig, NULL, &oact); /* async-signal-safe */
            if (ret == -1 && errno == EINVAL) {
                continue; /* Ignore invalid signal number. */
            }
            if (ret == -1) {
                ERRMSG("sigaction to obtain old action");
                return -1;
            }
            reset = (oact.sa_flags & SA_SIGINFO) ||
                    (oact.sa_handler != SIG_IGN && oact.sa_handler != SIG_DFL);
#else
            handler = signal(sig, SIG_DFL);
            if (handler == SIG_ERR && errno == EINVAL) {
                continue; /* Ignore invalid signal number */
            }
            if (handler == SIG_ERR) {
                ERRMSG("signal to obtain old action");
                return -1;
            }
            reset = (handler != SIG_IGN && handler != SIG_DFL);
#endif
        }
        if (reset) {
#ifdef POSIX_SIGNAL
            ret = sigaction(sig, &act, NULL); /* async-signal-safe */
            if (ret == -1) {
                ERRMSG("sigaction to set default action");
                return -1;
            }
#else
           handler = signal(sig, handler);
           if (handler == SIG_ERR) {
                ERRMSG("signal to set default action");
                return -1;
           }
#endif
        }
    }

    ret = sigprocmask(SIG_SETMASK, &old->sigmask, NULL); /* async-signal-safe */
    if (ret != 0) {
        ERRMSG("sigprocmask");
        return -1;
    }
    return 0;
}

static rb_pid_t
retry_fork_async_signal_safe(int *status, int *ep,
        int (*chfunc)(void*, char *, size_t), void *charg,
        char *errmsg, size_t errmsg_buflen)
{
    rb_pid_t pid;
    volatile int try_gc = 1;
    struct child_handler_disabler_state old;

    while (1) {
        prefork();
        disable_child_handler_before_fork(&old);
#ifdef HAVE_WORKING_VFORK
        if (!has_privilege())
            pid = vfork();
        else
            pid = fork();
#else
        pid = fork();
#endif
        if (pid == 0) {/* fork succeed, child process */
            int ret;
            close(ep[0]);
            ret = disable_child_handler_fork_child(&old, errmsg, errmsg_buflen); /* async-signal-safe */
            if (ret == 0) {
                ret = chfunc(charg, errmsg, errmsg_buflen);
                if (!ret) _exit(EXIT_SUCCESS);
            }
            send_child_error(ep[1], errmsg, errmsg_buflen);
#if EXIT_SUCCESS == 127
            _exit(EXIT_FAILURE);
#else
            _exit(127);
#endif
        }
        preserving_errno(disable_child_handler_fork_parent(&old));
        if (0 < pid) /* fork succeed, parent process */
            return pid;
        /* fork failed */
        if (handle_fork_error(status, ep, &try_gc))
            return -1;
    }
}

rb_pid_t
rb_fork_async_signal_safe(int *status, int (*chfunc)(void*, char *, size_t), void *charg, VALUE fds,
        char *errmsg, size_t errmsg_buflen)
{
    rb_pid_t pid;
    int err;
    int ep[2];
    int error_occurred;

    if (status) *status = 0;

    if (pipe_nocrash(ep, fds)) return -1;
    pid = retry_fork_async_signal_safe(status, ep, chfunc, charg, errmsg, errmsg_buflen);
    if (pid < 0)
        return pid;
    close(ep[1]);
    error_occurred = recv_child_error(ep[0], &err, errmsg, errmsg_buflen);
    if (error_occurred) {
        if (status) {
            rb_protect(proc_syswait, (VALUE)pid, status);
        }
        else {
            rb_syswait(pid);
        }
        errno = err;
        return -1;
    }
    return pid;
}

static rb_pid_t
retry_fork_ruby(int *status)
{
    rb_pid_t pid;
    int try_gc = 1;

    while (1) {
        prefork();
        before_fork_ruby();
        pid = fork();
        if (pid == 0) /* fork succeed, child process */
            return pid;
        preserving_errno(after_fork_ruby());
        if (0 < pid) /* fork succeed, parent process */
            return pid;
        /* fork failed */
        if (handle_fork_error(status, NULL, &try_gc))
            return -1;
    }
}

rb_pid_t
rb_fork_ruby(int *status)
{
    rb_pid_t pid;

    if (status) *status = 0;

    pid = retry_fork_ruby(status);
    if (pid < 0)
        return pid;
    if (!pid) {
        after_fork_ruby();
    }
    return pid;
}

#endif

#if defined(HAVE_WORKING_FORK) && !defined(CANNOT_FORK_WITH_PTHREAD)
/*
 *  call-seq:
 *     Kernel.fork  [{ block }]   -> fixnum or nil
 *     Process.fork [{ block }]   -> fixnum or nil
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
 *
 *  If fork is not usable, Process.respond_to?(:fork) returns false.
 *
 *  Note that fork(2) is not available on some platforms like Windows and NetBSD 4.
 *  Therefore you should use spawn() instead of fork().
 */

static VALUE
rb_f_fork(VALUE obj)
{
    rb_pid_t pid;

    rb_secure(2);

    switch (pid = rb_fork_ruby(NULL)) {
      case 0:
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
	return PIDT2NUM(pid);
    }
}
#else
#define rb_f_fork rb_f_notimplement
#endif

static int
exit_status_code(VALUE status)
{
    int istatus;

    switch (status) {
      case Qtrue:
	istatus = EXIT_SUCCESS;
	break;
      case Qfalse:
	istatus = EXIT_FAILURE;
	break;
      default:
	istatus = NUM2INT(status);
#if EXIT_SUCCESS != 0
	if (istatus == 0)
	    istatus = EXIT_SUCCESS;
#endif
	break;
    }
    return istatus;
}

/*
 *  call-seq:
 *     Process.exit!(status=false)
 *
 *  Exits the process immediately. No exit handlers are
 *  run. <em>status</em> is returned to the underlying system as the
 *  exit status.
 *
 *     Process.exit!(true)
 */

static VALUE
rb_f_exit_bang(int argc, VALUE *argv, VALUE obj)
{
    VALUE status;
    int istatus;

    if (argc > 0 && rb_scan_args(argc, argv, "01", &status) == 1) {
	istatus = exit_status_code(status);
    }
    else {
	istatus = EXIT_FAILURE;
    }
    _exit(istatus);

    UNREACHABLE;
}

void
rb_exit(int status)
{
    if (GET_THREAD()->tag) {
	VALUE args[2];

	args[0] = INT2NUM(status);
	args[1] = rb_str_new2("exit");
	rb_exc_raise(rb_class_new_instance(2, args, rb_eSystemExit));
    }
    ruby_stop(status);
}


/*
 *  call-seq:
 *     exit(status=true)
 *     Kernel::exit(status=true)
 *     Process::exit(status=true)
 *
 *  Initiates the termination of the Ruby script by raising the
 *  <code>SystemExit</code> exception. This exception may be caught. The
 *  optional parameter is used to return a status code to the invoking
 *  environment.
 *  +true+ and +FALSE+ of _status_ means success and failure
 *  respectively.  The interpretation of other integer values are
 *  system dependent.
 *
 *     begin
 *       exit
 *       puts "never get here"
 *     rescue SystemExit
 *       puts "rescued a SystemExit exception"
 *     end
 *     puts "after begin block"
 *
 *  <em>produces:</em>
 *
 *     rescued a SystemExit exception
 *     after begin block
 *
 *  Just prior to termination, Ruby executes any <code>at_exit</code> functions
 *  (see Kernel::at_exit) and runs any object finalizers (see
 *  ObjectSpace::define_finalizer).
 *
 *     at_exit { puts "at_exit function" }
 *     ObjectSpace.define_finalizer("string",  proc { puts "in finalizer" })
 *     exit
 *
 *  <em>produces:</em>
 *
 *     at_exit function
 *     in finalizer
 */

VALUE
rb_f_exit(int argc, const VALUE *argv)
{
    VALUE status;
    int istatus;

    if (argc > 0 && rb_scan_args(argc, argv, "01", &status) == 1) {
	istatus = exit_status_code(status);
    }
    else {
	istatus = EXIT_SUCCESS;
    }
    rb_exit(istatus);

    UNREACHABLE;
}


/*
 *  call-seq:
 *     abort
 *     Kernel::abort([msg])
 *     Process::abort([msg])
 *
 *  Terminate execution immediately, effectively by calling
 *  <code>Kernel.exit(false)</code>. If _msg_ is given, it is written
 *  to STDERR prior to terminating.
 */

VALUE
rb_f_abort(int argc, const VALUE *argv)
{
    rb_check_arity(argc, 0, 1);
    if (argc == 0) {
	if (!NIL_P(GET_THREAD()->errinfo)) {
	    ruby_error_print();
	}
	rb_exit(EXIT_FAILURE);
    }
    else {
	VALUE args[2];

	args[1] = args[0] = argv[0];
	StringValue(args[0]);
	rb_io_puts(1, args, rb_stderr);
	args[0] = INT2NUM(EXIT_FAILURE);
	rb_exc_raise(rb_class_new_instance(2, args, rb_eSystemExit));
    }

    UNREACHABLE;
}

void
rb_syswait(rb_pid_t pid)
{
    int status;

    rb_waitpid(pid, &status, 0);
}

static rb_pid_t
rb_spawn_process(struct rb_execarg *eargp, char *errmsg, size_t errmsg_buflen)
{
    rb_pid_t pid;
#if !USE_SPAWNV
    int status;
#endif
#if !defined HAVE_WORKING_FORK || USE_SPAWNV
    VALUE prog;
    struct rb_execarg sarg;
#endif

#if defined HAVE_WORKING_FORK && !USE_SPAWNV
    pid = rb_fork_async_signal_safe(&status, rb_exec_atfork, eargp, eargp->redirect_fds, errmsg, errmsg_buflen);
#else
    prog = eargp->use_shell ? eargp->invoke.sh.shell_script : eargp->invoke.cmd.command_name;

    if (rb_execarg_run_options(eargp, &sarg, errmsg, errmsg_buflen) < 0) {
        return -1;
    }

    if (prog && !eargp->use_shell) {
        char **argv = ARGVSTR2ARGV(eargp->invoke.cmd.argv_str);
        argv[0] = RSTRING_PTR(prog);
    }
# if defined HAVE_SPAWNV
    if (eargp->use_shell) {
	pid = proc_spawn_sh(RSTRING_PTR(prog));
    }
    else {
        char **argv = ARGVSTR2ARGV(eargp->invoke.cmd.argv_str);
	pid = proc_spawn_cmd(argv, prog, eargp);
    }
    if (pid == -1)
	rb_last_status_set(0x7f << 8, 0);
# else
    if (!eargp->use_shell) {
        char **argv = ARGVSTR2ARGV(eargp->invoke.cmd.argv_str);
        int argc = ARGVSTR2ARGC(eargp->invoke.cmd.argv_str);
        prog = rb_ary_join(rb_ary_new4(argc, argv), rb_str_new2(" "));
    }
    status = system(StringValuePtr(prog));
    rb_last_status_set((status & 0xff) << 8, 0);
    pid = 1;			/* dummy */
# endif

    rb_execarg_run_options(&sarg, NULL, errmsg, errmsg_buflen);
#endif
    return pid;
}

static rb_pid_t
rb_spawn_internal(int argc, const VALUE *argv, char *errmsg, size_t errmsg_buflen)
{
    VALUE execarg_obj;
    struct rb_execarg *eargp;
    rb_pid_t ret;

    execarg_obj = rb_execarg_new(argc, argv, TRUE);
    eargp = rb_execarg_get(execarg_obj);
    rb_execarg_fixup(execarg_obj);
    ret = rb_spawn_process(eargp, errmsg, errmsg_buflen);
    RB_GC_GUARD(execarg_obj);
    return ret;
}

rb_pid_t
rb_spawn_err(int argc, const VALUE *argv, char *errmsg, size_t errmsg_buflen)
{
    return rb_spawn_internal(argc, argv, errmsg, errmsg_buflen);
}

rb_pid_t
rb_spawn(int argc, const VALUE *argv)
{
    return rb_spawn_internal(argc, argv, NULL, 0);
}

/*
 *  call-seq:
 *     system([env,] command... [,options])    -> true, false or nil
 *
 *  Executes _command..._ in a subshell.
 *  _command..._ is one of following forms.
 *
 *    commandline                 : command line string which is passed to the standard shell
 *    cmdname, arg1, ...          : command name and one or more arguments (no shell)
 *    [cmdname, argv0], arg1, ... : command name, argv[0] and zero or more arguments (no shell)
 *
 *  system returns +true+ if the command gives zero exit status,
 *  +false+ for non zero exit status.
 *  Returns +nil+ if command execution fails.
 *  An error status is available in <code>$?</code>.
 *  The arguments are processed in the same way as
 *  for <code>Kernel.spawn</code>.
 *
 *  The hash arguments, env and options, are same as
 *  <code>exec</code> and <code>spawn</code>.
 *  See <code>Kernel.spawn</code> for details.
 *
 *     system("echo *")
 *     system("echo", "*")
 *
 *  <em>produces:</em>
 *
 *     config.h main.rb
 *     *
 *
 *  See <code>Kernel.exec</code> for the standard shell.
 */

static VALUE
rb_f_system(int argc, VALUE *argv)
{
    rb_pid_t pid;
    int status;

#if defined(SIGCLD) && !defined(SIGCHLD)
# define SIGCHLD SIGCLD
#endif

#ifdef SIGCHLD
    RETSIGTYPE (*chfunc)(int);

    rb_last_status_clear();
    chfunc = signal(SIGCHLD, SIG_DFL);
#endif
    pid = rb_spawn_internal(argc, argv, NULL, 0);
#if defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)
    if (pid > 0) {
        int ret, status;
        ret = rb_waitpid(pid, &status, 0);
        if (ret == (rb_pid_t)-1)
            rb_sys_fail("Another thread waited the process started by system().");
    }
#endif
#ifdef SIGCHLD
    signal(SIGCHLD, chfunc);
#endif
    if (pid < 0) {
	return Qnil;
    }
    status = PST2INT(rb_last_status_get());
    if (status == EXIT_SUCCESS) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     spawn([env,] command... [,options])     -> pid
 *     Process.spawn([env,] command... [,options])     -> pid
 *
 *  spawn executes specified command and return its pid.
 *
 *    pid = spawn("tar xf ruby-2.0.0-p195.tar.bz2")
 *    Process.wait pid
 *
 *    pid = spawn(RbConfig.ruby, "-eputs'Hello, world!'")
 *    Process.wait pid
 *
 *  This method is similar to Kernel#system but it doesn't wait for the command
 *  to finish.
 *
 *  The parent process should
 *  use <code>Process.wait</code> to collect
 *  the termination status of its child or
 *  use <code>Process.detach</code> to register
 *  disinterest in their status;
 *  otherwise, the operating system may accumulate zombie processes.
 *
 *  spawn has bunch of options to specify process attributes:
 *
 *    env: hash
 *      name => val : set the environment variable
 *      name => nil : unset the environment variable
 *    command...:
 *      commandline                 : command line string which is passed to the standard shell
 *      cmdname, arg1, ...          : command name and one or more arguments (This form does not use the shell. See below for caveats.)
 *      [cmdname, argv0], arg1, ... : command name, argv[0] and zero or more arguments (no shell)
 *    options: hash
 *      clearing environment variables:
 *        :unsetenv_others => true   : clear environment variables except specified by env
 *        :unsetenv_others => false  : don't clear (default)
 *      process group:
 *        :pgroup => true or 0 : make a new process group
 *        :pgroup => pgid      : join to specified process group
 *        :pgroup => nil       : don't change the process group (default)
 *      create new process group: Windows only
 *        :new_pgroup => true  : the new process is the root process of a new process group
 *        :new_pgroup => false : don't create a new process group (default)
 *      resource limit: resourcename is core, cpu, data, etc.  See Process.setrlimit.
 *        :rlimit_resourcename => limit
 *        :rlimit_resourcename => [cur_limit, max_limit]
 *      umask:
 *        :umask => int
 *      redirection:
 *        key:
 *          FD              : single file descriptor in child process
 *          [FD, FD, ...]   : multiple file descriptor in child process
 *        value:
 *          FD                        : redirect to the file descriptor in parent process
 *          string                    : redirect to file with open(string, "r" or "w")
 *          [string]                  : redirect to file with open(string, File::RDONLY)
 *          [string, open_mode]       : redirect to file with open(string, open_mode, 0644)
 *          [string, open_mode, perm] : redirect to file with open(string, open_mode, perm)
 *          [:child, FD]              : redirect to the redirected file descriptor
 *          :close                    : close the file descriptor in child process
 *        FD is one of follows
 *          :in     : the file descriptor 0 which is the standard input
 *          :out    : the file descriptor 1 which is the standard output
 *          :err    : the file descriptor 2 which is the standard error
 *          integer : the file descriptor of specified the integer
 *          io      : the file descriptor specified as io.fileno
 *      file descriptor inheritance: close non-redirected non-standard fds (3, 4, 5, ...) or not
 *        :close_others => true  : don't inherit
 *      current directory:
 *        :chdir => str
 *
 *      The 'cmdname, arg1, ...' form does not use the shell. However,
 *      on different OSes, different things are provided as built-in
 *      commands. An example of this is 'echo', which is a built-in
 *      on Windows, but is a normal program on Linux and Mac OS X.
 *      This means that `Process.spawn 'echo', '%Path%'` will display
 *      the contents of the `%Path%` environment variable on Windows,
 *      but `Process.spawn 'echo', '$PATH'` prints the literal '$PATH'.
 *
 *  If a hash is given as +env+, the environment is
 *  updated by +env+ before <code>exec(2)</code> in the child process.
 *  If a pair in +env+ has nil as the value, the variable is deleted.
 *
 *    # set FOO as BAR and unset BAZ.
 *    pid = spawn({"FOO"=>"BAR", "BAZ"=>nil}, command)
 *
 *  If a hash is given as +options+,
 *  it specifies
 *  process group,
 *  create new process group,
 *  resource limit,
 *  current directory,
 *  umask and
 *  redirects for the child process.
 *  Also, it can be specified to clear environment variables.
 *
 *  The <code>:unsetenv_others</code> key in +options+ specifies
 *  to clear environment variables, other than specified by +env+.
 *
 *    pid = spawn(command, :unsetenv_others=>true) # no environment variable
 *    pid = spawn({"FOO"=>"BAR"}, command, :unsetenv_others=>true) # FOO only
 *
 *  The <code>:pgroup</code> key in +options+ specifies a process group.
 *  The corresponding value should be true, zero or positive integer.
 *  true and zero means the process should be a process leader of a new
 *  process group.
 *  Other values specifies a process group to be belongs.
 *
 *    pid = spawn(command, :pgroup=>true) # process leader
 *    pid = spawn(command, :pgroup=>10) # belongs to the process group 10
 *
 *  The <code>:new_pgroup</code> key in +options+ specifies to pass
 *  +CREATE_NEW_PROCESS_GROUP+ flag to <code>CreateProcessW()</code> that is
 *  Windows API. This option is only for Windows.
 *  true means the new process is the root process of the new process group.
 *  The new process has CTRL+C disabled. This flag is necessary for
 *  <code>Process.kill(:SIGINT, pid)</code> on the subprocess.
 *  :new_pgroup is false by default.
 *
 *    pid = spawn(command, :new_pgroup=>true)  # new process group
 *    pid = spawn(command, :new_pgroup=>false) # same process group
 *
 *  The <code>:rlimit_</code><em>foo</em> key specifies a resource limit.
 *  <em>foo</em> should be one of resource types such as <code>core</code>.
 *  The corresponding value should be an integer or an array which have one or
 *  two integers: same as cur_limit and max_limit arguments for
 *  Process.setrlimit.
 *
 *    cur, max = Process.getrlimit(:CORE)
 *    pid = spawn(command, :rlimit_core=>[0,max]) # disable core temporary.
 *    pid = spawn(command, :rlimit_core=>max) # enable core dump
 *    pid = spawn(command, :rlimit_core=>0) # never dump core.
 *
 *  The <code>:umask</code> key in +options+ specifies the umask.
 *
 *    pid = spawn(command, :umask=>077)
 *
 *  The :in, :out, :err, a fixnum, an IO and an array key specifies a redirection.
 *  The redirection maps a file descriptor in the child process.
 *
 *  For example, stderr can be merged into stdout as follows:
 *
 *    pid = spawn(command, :err=>:out)
 *    pid = spawn(command, 2=>1)
 *    pid = spawn(command, STDERR=>:out)
 *    pid = spawn(command, STDERR=>STDOUT)
 *
 *  The hash keys specifies a file descriptor
 *  in the child process started by <code>spawn</code>.
 *  :err, 2 and STDERR specifies the standard error stream (stderr).
 *
 *  The hash values specifies a file descriptor
 *  in the parent process which invokes <code>spawn</code>.
 *  :out, 1 and STDOUT specifies the standard output stream (stdout).
 *
 *  In the above example,
 *  the standard output in the child process is not specified.
 *  So it is inherited from the parent process.
 *
 *  The standard input stream (stdin) can be specified by :in, 0 and STDIN.
 *
 *  A filename can be specified as a hash value.
 *
 *    pid = spawn(command, :in=>"/dev/null") # read mode
 *    pid = spawn(command, :out=>"/dev/null") # write mode
 *    pid = spawn(command, :err=>"log") # write mode
 *    pid = spawn(command, [:out, :err]=>"/dev/null") # write mode
 *    pid = spawn(command, 3=>"/dev/null") # read mode
 *
 *  For stdout and stderr (and combination of them),
 *  it is opened in write mode.
 *  Otherwise read mode is used.
 *
 *  For specifying flags and permission of file creation explicitly,
 *  an array is used instead.
 *
 *    pid = spawn(command, :in=>["file"]) # read mode is assumed
 *    pid = spawn(command, :in=>["file", "r"])
 *    pid = spawn(command, :out=>["log", "w"]) # 0644 assumed
 *    pid = spawn(command, :out=>["log", "w", 0600])
 *    pid = spawn(command, :out=>["log", File::WRONLY|File::EXCL|File::CREAT, 0600])
 *
 *  The array specifies a filename, flags and permission.
 *  The flags can be a string or an integer.
 *  If the flags is omitted or nil, File::RDONLY is assumed.
 *  The permission should be an integer.
 *  If the permission is omitted or nil, 0644 is assumed.
 *
 *  If an array of IOs and integers are specified as a hash key,
 *  all the elements are redirected.
 *
 *    # stdout and stderr is redirected to log file.
 *    # The file "log" is opened just once.
 *    pid = spawn(command, [:out, :err]=>["log", "w"])
 *
 *  Another way to merge multiple file descriptors is [:child, fd].
 *  \[:child, fd] means the file descriptor in the child process.
 *  This is different from fd.
 *  For example, :err=>:out means redirecting child stderr to parent stdout.
 *  But :err=>[:child, :out] means redirecting child stderr to child stdout.
 *  They differ if stdout is redirected in the child process as follows.
 *
 *    # stdout and stderr is redirected to log file.
 *    # The file "log" is opened just once.
 *    pid = spawn(command, :out=>["log", "w"], :err=>[:child, :out])
 *
 *  \[:child, :out] can be used to merge stderr into stdout in IO.popen.
 *  In this case, IO.popen redirects stdout to a pipe in the child process
 *  and [:child, :out] refers the redirected stdout.
 *
 *    io = IO.popen(["sh", "-c", "echo out; echo err >&2", :err=>[:child, :out]])
 *    p io.read #=> "out\nerr\n"
 *
 *  The <code>:chdir</code> key in +options+ specifies the current directory.
 *
 *    pid = spawn(command, :chdir=>"/var/tmp")
 *
 *  spawn closes all non-standard unspecified descriptors by default.
 *  The "standard" descriptors are 0, 1 and 2.
 *  This behavior is specified by :close_others option.
 *  :close_others doesn't affect the standard descriptors which are
 *  closed only if :close is specified explicitly.
 *
 *    pid = spawn(command, :close_others=>true)  # close 3,4,5,... (default)
 *    pid = spawn(command, :close_others=>false) # don't close 3,4,5,...
 *
 *  :close_others is true by default for spawn and IO.popen.
 *
 *  Note that fds which close-on-exec flag is already set are closed
 *  regardless of :close_others option.
 *
 *  So IO.pipe and spawn can be used as IO.popen.
 *
 *    # similar to r = IO.popen(command)
 *    r, w = IO.pipe
 *    pid = spawn(command, :out=>w)   # r, w is closed in the child process.
 *    w.close
 *
 *  :close is specified as a hash value to close a fd individually.
 *
 *    f = open(foo)
 *    system(command, f=>:close)        # don't inherit f.
 *
 *  If a file descriptor need to be inherited,
 *  io=>io can be used.
 *
 *    # valgrind has --log-fd option for log destination.
 *    # log_w=>log_w indicates log_w.fileno inherits to child process.
 *    log_r, log_w = IO.pipe
 *    pid = spawn("valgrind", "--log-fd=#{log_w.fileno}", "echo", "a", log_w=>log_w)
 *    log_w.close
 *    p log_r.read
 *
 *  It is also possible to exchange file descriptors.
 *
 *    pid = spawn(command, :out=>:err, :err=>:out)
 *
 *  The hash keys specify file descriptors in the child process.
 *  The hash values specifies file descriptors in the parent process.
 *  So the above specifies exchanging stdout and stderr.
 *  Internally, +spawn+ uses an extra file descriptor to resolve such cyclic
 *  file descriptor mapping.
 *
 *  See <code>Kernel.exec</code> for the standard shell.
 */

static VALUE
rb_f_spawn(int argc, VALUE *argv)
{
    rb_pid_t pid;
    char errmsg[CHILD_ERRMSG_BUFLEN] = { '\0' };
    VALUE execarg_obj, fail_str;
    struct rb_execarg *eargp;

    execarg_obj = rb_execarg_new(argc, argv, TRUE);
    eargp = rb_execarg_get(execarg_obj);
    rb_execarg_fixup(execarg_obj);
    fail_str = eargp->use_shell ? eargp->invoke.sh.shell_script : eargp->invoke.cmd.command_name;

    pid = rb_spawn_process(eargp, errmsg, sizeof(errmsg));
    RB_GC_GUARD(execarg_obj);

    if (pid == -1) {
	const char *prog = errmsg;
	if (!prog[0]) {
	    rb_sys_fail_str(fail_str);
	}
	rb_sys_fail(prog);
    }
#if defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)
    return PIDT2NUM(pid);
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     sleep([duration])    -> fixnum
 *
 *  Suspends the current thread for _duration_ seconds (which may be any number,
 *  including a +Float+ with fractional seconds). Returns the actual number of
 *  seconds slept (rounded), which may be less than that asked for if another
 *  thread calls <code>Thread#run</code>. Called without an argument, sleep()
 *  will sleep forever.
 *
 *     Time.new    #=> 2008-03-08 19:56:19 +0900
 *     sleep 1.2   #=> 1
 *     Time.new    #=> 2008-03-08 19:56:20 +0900
 *     sleep 1.9   #=> 2
 *     Time.new    #=> 2008-03-08 19:56:22 +0900
 */

static VALUE
rb_f_sleep(int argc, VALUE *argv)
{
    time_t beg, end;

    beg = time(0);
    if (argc == 0) {
	rb_thread_sleep_forever();
    }
    else {
	rb_check_arity(argc, 0, 1);
	rb_thread_wait_for(rb_time_interval(argv[0]));
    }

    end = time(0) - beg;

    return INT2FIX(end);
}


#if (defined(HAVE_GETPGRP) && defined(GETPGRP_VOID)) || defined(HAVE_GETPGID)
/*
 *  call-seq:
 *     Process.getpgrp   -> integer
 *
 *  Returns the process group ID for this process. Not available on
 *  all platforms.
 *
 *     Process.getpgid(0)   #=> 25527
 *     Process.getpgrp      #=> 25527
 */

static VALUE
proc_getpgrp(void)
{
    rb_pid_t pgrp;

    rb_secure(2);
#if defined(HAVE_GETPGRP) && defined(GETPGRP_VOID)
    pgrp = getpgrp();
    if (pgrp < 0) rb_sys_fail(0);
    return PIDT2NUM(pgrp);
#else /* defined(HAVE_GETPGID) */
    pgrp = getpgid(0);
    if (pgrp < 0) rb_sys_fail(0);
    return PIDT2NUM(pgrp);
#endif
}
#else
#define proc_getpgrp rb_f_notimplement
#endif


#if defined(HAVE_SETPGID) || (defined(HAVE_SETPGRP) && defined(SETPGRP_VOID))
/*
 *  call-seq:
 *     Process.setpgrp   -> 0
 *
 *  Equivalent to <code>setpgid(0,0)</code>. Not available on all
 *  platforms.
 */

static VALUE
proc_setpgrp(void)
{
    rb_secure(2);
  /* check for posix setpgid() first; this matches the posix */
  /* getpgrp() above.  It appears that configure will set SETPGRP_VOID */
  /* even though setpgrp(0,0) would be preferred. The posix call avoids */
  /* this confusion. */
#ifdef HAVE_SETPGID
    if (setpgid(0,0) < 0) rb_sys_fail(0);
#elif defined(HAVE_SETPGRP) && defined(SETPGRP_VOID)
    if (setpgrp() < 0) rb_sys_fail(0);
#endif
    return INT2FIX(0);
}
#else
#define proc_setpgrp rb_f_notimplement
#endif


#if defined(HAVE_GETPGID)
/*
 *  call-seq:
 *     Process.getpgid(pid)   -> integer
 *
 *  Returns the process group ID for the given process id. Not
 *  available on all platforms.
 *
 *     Process.getpgid(Process.ppid())   #=> 25527
 */

static VALUE
proc_getpgid(VALUE obj, VALUE pid)
{
    rb_pid_t i;

    rb_secure(2);
    i = getpgid(NUM2PIDT(pid));
    if (i < 0) rb_sys_fail(0);
    return PIDT2NUM(i);
}
#else
#define proc_getpgid rb_f_notimplement
#endif


#ifdef HAVE_SETPGID
/*
 *  call-seq:
 *     Process.setpgid(pid, integer)   -> 0
 *
 *  Sets the process group ID of _pid_ (0 indicates this
 *  process) to <em>integer</em>. Not available on all platforms.
 */

static VALUE
proc_setpgid(VALUE obj, VALUE pid, VALUE pgrp)
{
    rb_pid_t ipid, ipgrp;

    rb_secure(2);
    ipid = NUM2PIDT(pid);
    ipgrp = NUM2PIDT(pgrp);

    if (setpgid(ipid, ipgrp) < 0) rb_sys_fail(0);
    return INT2FIX(0);
}
#else
#define proc_setpgid rb_f_notimplement
#endif


#ifdef HAVE_GETSID
/*
 *  call-seq:
 *     Process.getsid()      -> integer
 *     Process.getsid(pid)   -> integer
 *
 *  Returns the session ID for for the given process id. If not give,
 *  return current process sid. Not available on all platforms.
 *
 *     Process.getsid()                #=> 27422
 *     Process.getsid(0)               #=> 27422
 *     Process.getsid(Process.pid())   #=> 27422
 */
static VALUE
proc_getsid(int argc, VALUE *argv)
{
    rb_pid_t sid;
    VALUE pid;

    rb_secure(2);
    rb_scan_args(argc, argv, "01", &pid);

    if (NIL_P(pid))
	pid = INT2FIX(0);

    sid = getsid(NUM2PIDT(pid));
    if (sid < 0) rb_sys_fail(0);
    return PIDT2NUM(sid);
}
#else
#define proc_getsid rb_f_notimplement
#endif


#if defined(HAVE_SETSID) || (defined(HAVE_SETPGRP) && defined(TIOCNOTTY))
#if !defined(HAVE_SETSID)
static rb_pid_t ruby_setsid(void);
#define setsid() ruby_setsid()
#endif
/*
 *  call-seq:
 *     Process.setsid   -> fixnum
 *
 *  Establishes this process as a new session and process group
 *  leader, with no controlling tty. Returns the session id. Not
 *  available on all platforms.
 *
 *     Process.setsid   #=> 27422
 */

static VALUE
proc_setsid(void)
{
    rb_pid_t pid;

    rb_secure(2);
    pid = setsid();
    if (pid < 0) rb_sys_fail(0);
    return PIDT2NUM(pid);
}

#if !defined(HAVE_SETSID)
#define HAVE_SETSID 1
static rb_pid_t
ruby_setsid(void)
{
    rb_pid_t pid;
    int ret;

    pid = getpid();
#if defined(SETPGRP_VOID)
    ret = setpgrp();
    /* If `pid_t setpgrp(void)' is equivalent to setsid(),
       `ret' will be the same value as `pid', and following open() will fail.
       In Linux, `int setpgrp(void)' is equivalent to setpgid(0, 0). */
#else
    ret = setpgrp(0, pid);
#endif
    if (ret == -1) return -1;

    if ((fd = rb_cloexec_open("/dev/tty", O_RDWR, 0)) >= 0) {
        rb_update_max_fd(fd);
	ioctl(fd, TIOCNOTTY, NULL);
	close(fd);
    }
    return pid;
}
#endif
#else
#define proc_setsid rb_f_notimplement
#endif


#ifdef HAVE_GETPRIORITY
/*
 *  call-seq:
 *     Process.getpriority(kind, integer)   -> fixnum
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
proc_getpriority(VALUE obj, VALUE which, VALUE who)
{
    int prio, iwhich, iwho;

    rb_secure(2);
    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);

    errno = 0;
    prio = getpriority(iwhich, iwho);
    if (errno) rb_sys_fail(0);
    return INT2FIX(prio);
}
#else
#define proc_getpriority rb_f_notimplement
#endif


#ifdef HAVE_GETPRIORITY
/*
 *  call-seq:
 *     Process.setpriority(kind, integer, priority)   -> 0
 *
 *  See <code>Process#getpriority</code>.
 *
 *     Process.setpriority(Process::PRIO_USER, 0, 19)      #=> 0
 *     Process.setpriority(Process::PRIO_PROCESS, 0, 19)   #=> 0
 *     Process.getpriority(Process::PRIO_USER, 0)          #=> 19
 *     Process.getpriority(Process::PRIO_PROCESS, 0)       #=> 19
 */

static VALUE
proc_setpriority(VALUE obj, VALUE which, VALUE who, VALUE prio)
{
    int iwhich, iwho, iprio;

    rb_secure(2);
    iwhich = NUM2INT(which);
    iwho   = NUM2INT(who);
    iprio  = NUM2INT(prio);

    if (setpriority(iwhich, iwho, iprio) < 0)
	rb_sys_fail(0);
    return INT2FIX(0);
}
#else
#define proc_setpriority rb_f_notimplement
#endif

#if defined(HAVE_SETRLIMIT) && defined(NUM2RLIM)
static int
rlimit_resource_name2int(const char *name, int casetype)
{
    int resource;
    const char *p;
#define RESCHECK(r) \
    do { \
        if (STRCASECMP(name, #r) == 0) { \
            resource = RLIMIT_##r; \
            goto found; \
        } \
    } while (0)

    switch (TOUPPER(*name)) {
      case 'A':
#ifdef RLIMIT_AS
        RESCHECK(AS);
#endif
        break;

      case 'C':
#ifdef RLIMIT_CORE
        RESCHECK(CORE);
#endif
#ifdef RLIMIT_CPU
        RESCHECK(CPU);
#endif
        break;

      case 'D':
#ifdef RLIMIT_DATA
        RESCHECK(DATA);
#endif
        break;

      case 'F':
#ifdef RLIMIT_FSIZE
        RESCHECK(FSIZE);
#endif
        break;

      case 'M':
#ifdef RLIMIT_MEMLOCK
        RESCHECK(MEMLOCK);
#endif
#ifdef RLIMIT_MSGQUEUE
        RESCHECK(MSGQUEUE);
#endif
        break;

      case 'N':
#ifdef RLIMIT_NOFILE
        RESCHECK(NOFILE);
#endif
#ifdef RLIMIT_NPROC
        RESCHECK(NPROC);
#endif
#ifdef RLIMIT_NICE
        RESCHECK(NICE);
#endif
        break;

      case 'R':
#ifdef RLIMIT_RSS
        RESCHECK(RSS);
#endif
#ifdef RLIMIT_RTPRIO
        RESCHECK(RTPRIO);
#endif
#ifdef RLIMIT_RTTIME
        RESCHECK(RTTIME);
#endif
        break;

      case 'S':
#ifdef RLIMIT_STACK
        RESCHECK(STACK);
#endif
#ifdef RLIMIT_SBSIZE
        RESCHECK(SBSIZE);
#endif
#ifdef RLIMIT_SIGPENDING
        RESCHECK(SIGPENDING);
#endif
        break;
    }
    return -1;

  found:
    switch (casetype) {
      case 0:
        for (p = name; *p; p++)
            if (!ISUPPER(*p))
                return -1;
        break;

      case 1:
        for (p = name; *p; p++)
            if (!ISLOWER(*p))
                return -1;
        break;

      default:
        rb_bug("unexpected casetype");
    }
    return resource;
#undef RESCHECK
}

static int
rlimit_type_by_hname(const char *name)
{
    return rlimit_resource_name2int(name, 0);
}

static int
rlimit_type_by_lname(const char *name)
{
    return rlimit_resource_name2int(name, 1);
}

static int
rlimit_resource_type(VALUE rtype)
{
    const char *name;
    VALUE v;
    int r;

    switch (TYPE(rtype)) {
      case T_SYMBOL:
	v = rb_sym2str(rtype);
	name = RSTRING_PTR(v);
        break;

      default:
        v = rb_check_string_type(rtype);
        if (!NIL_P(v)) {
            rtype = v;
      case T_STRING:
            name = StringValueCStr(rtype);
            break;
        }
        /* fall through */

      case T_FIXNUM:
      case T_BIGNUM:
        return NUM2INT(rtype);
    }

    r = rlimit_type_by_hname(name);
    if (r != -1)
        return r;

    rb_raise(rb_eArgError, "invalid resource name: %"PRIsVALUE, rtype);

    UNREACHABLE;
}

static rlim_t
rlimit_resource_value(VALUE rval)
{
    const char *name;
    VALUE v;

    switch (TYPE(rval)) {
      case T_SYMBOL:
	v = rb_sym2str(rval);
	name = RSTRING_PTR(v);
        break;

      default:
        v = rb_check_string_type(rval);
        if (!NIL_P(v)) {
            rval = v;
      case T_STRING:
            name = StringValueCStr(rval);
            break;
        }
        /* fall through */

      case T_FIXNUM:
      case T_BIGNUM:
        return NUM2RLIM(rval);
    }

#ifdef RLIM_INFINITY
    if (strcmp(name, "INFINITY") == 0) return RLIM_INFINITY;
#endif
#ifdef RLIM_SAVED_MAX
    if (strcmp(name, "SAVED_MAX") == 0) return RLIM_SAVED_MAX;
#endif
#ifdef RLIM_SAVED_CUR
    if (strcmp(name, "SAVED_CUR") == 0) return RLIM_SAVED_CUR;
#endif
    rb_raise(rb_eArgError, "invalid resource value: %"PRIsVALUE, rval);

    UNREACHABLE;
}
#endif

#if defined(HAVE_GETRLIMIT) && defined(RLIM2NUM)
/*
 *  call-seq:
 *     Process.getrlimit(resource)   -> [cur_limit, max_limit]
 *
 *  Gets the resource limit of the process.
 *  _cur_limit_ means current (soft) limit and
 *  _max_limit_ means maximum (hard) limit.
 *
 *  _resource_ indicates the kind of resource to limit.
 *  It is specified as a symbol such as <code>:CORE</code>,
 *  a string such as <code>"CORE"</code> or
 *  a constant such as <code>Process::RLIMIT_CORE</code>.
 *  See Process.setrlimit for details.
 *
 *  _cur_limit_ and _max_limit_ may be <code>Process::RLIM_INFINITY</code>,
 *  <code>Process::RLIM_SAVED_MAX</code> or
 *  <code>Process::RLIM_SAVED_CUR</code>.
 *  See Process.setrlimit and the system getrlimit(2) manual for details.
 */

static VALUE
proc_getrlimit(VALUE obj, VALUE resource)
{
    struct rlimit rlim;

    rb_secure(2);

    if (getrlimit(rlimit_resource_type(resource), &rlim) < 0) {
	rb_sys_fail("getrlimit");
    }
    return rb_assoc_new(RLIM2NUM(rlim.rlim_cur), RLIM2NUM(rlim.rlim_max));
}
#else
#define proc_getrlimit rb_f_notimplement
#endif

#if defined(HAVE_SETRLIMIT) && defined(NUM2RLIM)
/*
 *  call-seq:
 *     Process.setrlimit(resource, cur_limit, max_limit)        -> nil
 *     Process.setrlimit(resource, cur_limit)                   -> nil
 *
 *  Sets the resource limit of the process.
 *  _cur_limit_ means current (soft) limit and
 *  _max_limit_ means maximum (hard) limit.
 *
 *  If _max_limit_ is not given, _cur_limit_ is used.
 *
 *  _resource_ indicates the kind of resource to limit.
 *  It should be a symbol such as <code>:CORE</code>,
 *  a string such as <code>"CORE"</code> or
 *  a constant such as <code>Process::RLIMIT_CORE</code>.
 *  The available resources are OS dependent.
 *  Ruby may support following resources.
 *
 *  [AS] total available memory (bytes) (SUSv3, NetBSD, FreeBSD, OpenBSD but 4.4BSD-Lite)
 *  [CORE] core size (bytes) (SUSv3)
 *  [CPU] CPU time (seconds) (SUSv3)
 *  [DATA] data segment (bytes) (SUSv3)
 *  [FSIZE] file size (bytes) (SUSv3)
 *  [MEMLOCK] total size for mlock(2) (bytes) (4.4BSD, GNU/Linux)
 *  [MSGQUEUE] allocation for POSIX message queues (bytes) (GNU/Linux)
 *  [NICE] ceiling on process's nice(2) value (number) (GNU/Linux)
 *  [NOFILE] file descriptors (number) (SUSv3)
 *  [NPROC] number of processes for the user (number) (4.4BSD, GNU/Linux)
 *  [RSS] resident memory size (bytes) (4.2BSD, GNU/Linux)
 *  [RTPRIO] ceiling on the process's real-time priority (number) (GNU/Linux)
 *  [RTTIME] CPU time for real-time process (us) (GNU/Linux)
 *  [SBSIZE] all socket buffers (bytes) (NetBSD, FreeBSD)
 *  [SIGPENDING] number of queued signals allowed (signals) (GNU/Linux)
 *  [STACK] stack size (bytes) (SUSv3)
 *
 *  _cur_limit_ and _max_limit_ may be
 *  <code>:INFINITY</code>, <code>"INFINITY"</code> or
 *  <code>Process::RLIM_INFINITY</code>,
 *  which means that the resource is not limited.
 *  They may be <code>Process::RLIM_SAVED_MAX</code>,
 *  <code>Process::RLIM_SAVED_CUR</code> and
 *  corresponding symbols and strings too.
 *  See system setrlimit(2) manual for details.
 *
 *  The following example raises the soft limit of core size to
 *  the hard limit to try to make core dump possible.
 *
 *    Process.setrlimit(:CORE, Process.getrlimit(:CORE)[1])
 *
 */

static VALUE
proc_setrlimit(int argc, VALUE *argv, VALUE obj)
{
    VALUE resource, rlim_cur, rlim_max;
    struct rlimit rlim;

    rb_secure(2);

    rb_scan_args(argc, argv, "21", &resource, &rlim_cur, &rlim_max);
    if (rlim_max == Qnil)
        rlim_max = rlim_cur;

    rlim.rlim_cur = rlimit_resource_value(rlim_cur);
    rlim.rlim_max = rlimit_resource_value(rlim_max);

    if (setrlimit(rlimit_resource_type(resource), &rlim) < 0) {
	rb_sys_fail("setrlimit");
    }
    return Qnil;
}
#else
#define proc_setrlimit rb_f_notimplement
#endif

static int under_uid_switch = 0;
static void
check_uid_switch(void)
{
    rb_secure(2);
    if (under_uid_switch) {
	rb_raise(rb_eRuntimeError, "can't handle UID while evaluating block given to Process::UID.switch method");
    }
}

static int under_gid_switch = 0;
static void
check_gid_switch(void)
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

#if defined(HAVE_PWD_H)
static rb_uid_t
obj2uid(VALUE id
# ifdef USE_GETPWNAM_R
	, VALUE *getpw_tmp
# endif
    )
{
    rb_uid_t uid;
    VALUE tmp;

    if (FIXNUM_P(id) || NIL_P(tmp = rb_check_string_type(id))) {
	uid = NUM2UIDT(id);
    }
    else {
	const char *usrname = StringValueCStr(id);
	struct passwd *pwptr;
#ifdef USE_GETPWNAM_R
	struct passwd pwbuf;
	char *getpw_buf;
	long getpw_buf_len;
	if (!*getpw_tmp) {
	    getpw_buf_len = GETPW_R_SIZE_INIT;
	    if (getpw_buf_len < 0) getpw_buf_len = GETPW_R_SIZE_DEFAULT;
	    getpw_buf = rb_alloc_tmp_buffer(getpw_tmp, getpw_buf_len);
	}
	else {
	    getpw_buf = RSTRING_PTR(*getpw_tmp);
	    getpw_buf_len = rb_str_capacity(*getpw_tmp);
	}
	errno = ERANGE;
	/* gepwnam_r() on MacOS X doesn't set errno if buffer size is insufficient */
	while (getpwnam_r(usrname, &pwbuf, getpw_buf, getpw_buf_len, &pwptr)) {
	    if (errno != ERANGE || getpw_buf_len >= GETPW_R_SIZE_LIMIT) {
		rb_free_tmp_buffer(getpw_tmp);
		rb_sys_fail("getpwnam_r");
	    }
	    rb_str_modify_expand(*getpw_tmp, getpw_buf_len);
	    getpw_buf = RSTRING_PTR(*getpw_tmp);
	    getpw_buf_len = rb_str_capacity(*getpw_tmp);
	}
#else
	pwptr = getpwnam(usrname);
#endif
	if (!pwptr) {
#ifndef USE_GETPWNAM_R
	    endpwent();
#endif
	    rb_raise(rb_eArgError, "can't find user for %s", usrname);
	}
	uid = pwptr->pw_uid;
#ifndef USE_GETPWNAM_R
	endpwent();
#endif
    }
    return uid;
}

# ifdef p_uid_from_name
/*
 *  call-seq:
 *     Process::UID.from_name(name)   -> uid
 *
 *  Get the user ID by the _name_.
 *  If the user is not found, +ArgumentError+ will be raised.
 *
 *     Process::UID.from_name("root") #=> 0
 *     Process::UID.from_name("nosuchuser") #=> can't find user for nosuchuser (ArgumentError)
 */

static VALUE
p_uid_from_name(VALUE self, VALUE id)
{
    return UIDT2NUM(OBJ2UID(id));
}
# endif
#endif

#if defined(HAVE_GRP_H)
static rb_gid_t
obj2gid(VALUE id
# ifdef USE_GETGRNAM_R
	, VALUE *getgr_tmp
# endif
    )
{
    rb_gid_t gid;
    VALUE tmp;

    if (FIXNUM_P(id) || NIL_P(tmp = rb_check_string_type(id))) {
	gid = NUM2GIDT(id);
    }
    else {
	const char *grpname = StringValueCStr(id);
	struct group *grptr;
#ifdef USE_GETGRNAM_R
	struct group grbuf;
	char *getgr_buf;
	long getgr_buf_len;
	if (!*getgr_tmp) {
	    getgr_buf_len = GETGR_R_SIZE_INIT;
	    if (getgr_buf_len < 0) getgr_buf_len = GETGR_R_SIZE_DEFAULT;
	    getgr_buf = rb_alloc_tmp_buffer(getgr_tmp, getgr_buf_len);
	}
	else {
	    getgr_buf = RSTRING_PTR(*getgr_tmp);
	    getgr_buf_len = rb_str_capacity(*getgr_tmp);
	}
	errno = ERANGE;
	/* gegrnam_r() on MacOS X doesn't set errno if buffer size is insufficient */
	while (getgrnam_r(grpname, &grbuf, getgr_buf, getgr_buf_len, &grptr)) {
	    if (errno != ERANGE || getgr_buf_len >= GETGR_R_SIZE_LIMIT) {
		rb_free_tmp_buffer(getgr_tmp);
		rb_sys_fail("getgrnam_r");
	    }
	    rb_str_modify_expand(*getgr_tmp, getgr_buf_len);
	    getgr_buf = RSTRING_PTR(*getgr_tmp);
	    getgr_buf_len = rb_str_capacity(*getgr_tmp);
	}
#elif defined(HAVE_GETGRNAM)
	grptr = getgrnam(grpname);
#else
	grptr = NULL;
#endif
	if (!grptr) {
#if !defined(USE_GETGRNAM_R) && defined(HAVE_ENDGRENT)
	    endgrent();
#endif
	    rb_raise(rb_eArgError, "can't find group for %s", grpname);
	}
	gid = grptr->gr_gid;
#if !defined(USE_GETGRNAM_R) && defined(HAVE_ENDGRENT)
	endgrent();
#endif
    }
    return gid;
}

# ifdef p_gid_from_name
/*
 *  call-seq:
 *     Process::GID.from_name(name)   -> gid
 *
 *  Get the group ID by the _name_.
 *  If the group is not found, +ArgumentError+ will be raised.
 *
 *     Process::GID.from_name("wheel") #=> 0
 *     Process::GID.from_name("nosuchgroup") #=> can't find group for nosuchgroup (ArgumentError)
 */

static VALUE
p_gid_from_name(VALUE self, VALUE id)
{
    return GIDT2NUM(OBJ2GID(id));
}
# endif
#endif

#if defined HAVE_SETUID
/*
 *  call-seq:
 *     Process::Sys.setuid(user)   -> nil
 *
 *  Set the user ID of the current process to _user_. Not
 *  available on all platforms.
 *
 */

static VALUE
p_sys_setuid(VALUE obj, VALUE id)
{
    check_uid_switch();
    if (setuid(OBJ2UID(id)) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setuid rb_f_notimplement
#endif


#if defined HAVE_SETRUID
/*
 *  call-seq:
 *     Process::Sys.setruid(user)   -> nil
 *
 *  Set the real user ID of the calling process to _user_.
 *  Not available on all platforms.
 *
 */

static VALUE
p_sys_setruid(VALUE obj, VALUE id)
{
    check_uid_switch();
    if (setruid(OBJ2UID(id)) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setruid rb_f_notimplement
#endif


#if defined HAVE_SETEUID
/*
 *  call-seq:
 *     Process::Sys.seteuid(user)   -> nil
 *
 *  Set the effective user ID of the calling process to
 *  _user_.  Not available on all platforms.
 *
 */

static VALUE
p_sys_seteuid(VALUE obj, VALUE id)
{
    check_uid_switch();
    if (seteuid(OBJ2UID(id)) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_seteuid rb_f_notimplement
#endif


#if defined HAVE_SETREUID
/*
 *  call-seq:
 *     Process::Sys.setreuid(rid, eid)   -> nil
 *
 *  Sets the (user) real and/or effective user IDs of the current
 *  process to _rid_ and _eid_, respectively. A value of
 *  <code>-1</code> for either means to leave that ID unchanged. Not
 *  available on all platforms.
 *
 */

static VALUE
p_sys_setreuid(VALUE obj, VALUE rid, VALUE eid)
{
    rb_uid_t ruid, euid;
    PREPARE_GETPWNAM;
    check_uid_switch();
    ruid = OBJ2UID1(rid);
    euid = OBJ2UID1(eid);
    FINISH_GETPWNAM;
    if (setreuid(ruid, euid) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setreuid rb_f_notimplement
#endif


#if defined HAVE_SETRESUID
/*
 *  call-seq:
 *     Process::Sys.setresuid(rid, eid, sid)   -> nil
 *
 *  Sets the (user) real, effective, and saved user IDs of the
 *  current process to _rid_, _eid_, and _sid_ respectively. A
 *  value of <code>-1</code> for any value means to
 *  leave that ID unchanged. Not available on all platforms.
 *
 */

static VALUE
p_sys_setresuid(VALUE obj, VALUE rid, VALUE eid, VALUE sid)
{
    rb_uid_t ruid, euid, suid;
    PREPARE_GETPWNAM;
    check_uid_switch();
    ruid = OBJ2UID1(rid);
    euid = OBJ2UID1(eid);
    suid = OBJ2UID1(sid);
    FINISH_GETPWNAM;
    if (setresuid(ruid, euid, suid) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setresuid rb_f_notimplement
#endif


/*
 *  call-seq:
 *     Process.uid           -> fixnum
 *     Process::UID.rid      -> fixnum
 *     Process::Sys.getuid   -> fixnum
 *
 *  Returns the (real) user ID of this process.
 *
 *     Process.uid   #=> 501
 */

static VALUE
proc_getuid(VALUE obj)
{
    rb_uid_t uid = getuid();
    return UIDT2NUM(uid);
}


#if defined(HAVE_SETRESUID) || defined(HAVE_SETREUID) || defined(HAVE_SETRUID) || defined(HAVE_SETUID)
/*
 *  call-seq:
 *     Process.uid= user   -> numeric
 *
 *  Sets the (user) user ID for this process. Not available on all
 *  platforms.
 */

static VALUE
proc_setuid(VALUE obj, VALUE id)
{
    rb_uid_t uid;

    check_uid_switch();

    uid = OBJ2UID(id);
#if defined(HAVE_SETRESUID)
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
#endif
    return id;
}
#else
#define proc_setuid rb_f_notimplement
#endif


/********************************************************************
 *
 * Document-class: Process::UID
 *
 *  The <code>Process::UID</code> module contains a collection of
 *  module functions which can be used to portably get, set, and
 *  switch the current process's real, effective, and saved user IDs.
 *
 */

static rb_uid_t SAVED_USER_ID = -1;

#ifdef BROKEN_SETREUID
int
setreuid(rb_uid_t ruid, rb_uid_t euid)
{
    if (ruid != (rb_uid_t)-1 && ruid != getuid()) {
	if (euid == (rb_uid_t)-1) euid = geteuid();
	if (setuid(ruid) < 0) return -1;
    }
    if (euid != (rb_uid_t)-1 && euid != geteuid()) {
	if (seteuid(euid) < 0) return -1;
    }
    return 0;
}
#endif

/*
 *  call-seq:
 *     Process::UID.change_privilege(user)   -> fixnum
 *
 *  Change the current process's real and effective user ID to that
 *  specified by _user_. Returns the new user ID. Not
 *  available on all platforms.
 *
 *     [Process.uid, Process.euid]          #=> [0, 0]
 *     Process::UID.change_privilege(31)    #=> 31
 *     [Process.uid, Process.euid]          #=> [31, 31]
 */

static VALUE
p_uid_change_privilege(VALUE obj, VALUE id)
{
    rb_uid_t uid;

    check_uid_switch();

    uid = OBJ2UID(id);

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
	    }
	    else {
		if (uid == 0) { /* (r,e,s) == (root, root, x) */
		    if (setreuid(-1, SAVED_USER_ID) < 0) rb_sys_fail(0);
		    if (setreuid(SAVED_USER_ID, 0) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0; /* (r,e,s) == (x, root, root) */
		    if (setreuid(uid, uid) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = uid;
		}
		else {
		    if (setreuid(0, -1) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0;
		    if (setreuid(uid, uid) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = uid;
		}
	    }
	}
	else {
	    if (setreuid(uid, uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	}
#elif defined(HAVE_SETRUID) && defined(HAVE_SETEUID)
	if (getuid() == uid) {
	    if (SAVED_USER_ID == uid) {
		if (seteuid(uid) < 0) rb_sys_fail(0);
	    }
	    else {
		if (uid == 0) {
		    if (setruid(SAVED_USER_ID) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0;
		    if (setruid(0) < 0) rb_sys_fail(0);
		}
		else {
		    if (setruid(0) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = 0;
		    if (seteuid(uid) < 0) rb_sys_fail(0);
		    if (setruid(uid) < 0) rb_sys_fail(0);
		    SAVED_USER_ID = uid;
		}
	    }
	}
	else {
	    if (seteuid(uid) < 0) rb_sys_fail(0);
	    if (setruid(uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	}
#else
	(void)uid;
	rb_notimplement();
#endif
    }
    else { /* unprivileged user */
#if defined(HAVE_SETRESUID)
	if (setresuid((getuid() == uid)? (rb_uid_t)-1: uid,
		      (geteuid() == uid)? (rb_uid_t)-1: uid,
		      (SAVED_USER_ID == uid)? (rb_uid_t)-1: uid) < 0) rb_sys_fail(0);
	SAVED_USER_ID = uid;
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
	if (SAVED_USER_ID == uid) {
	    if (setreuid((getuid() == uid)? (rb_uid_t)-1: uid,
			 (geteuid() == uid)? (rb_uid_t)-1: uid) < 0)
		rb_sys_fail(0);
	}
	else if (getuid() != uid) {
	    if (setreuid(uid, (geteuid() == uid)? (rb_uid_t)-1: uid) < 0)
		rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	}
	else if (/* getuid() == uid && */ geteuid() != uid) {
	    if (setreuid(geteuid(), uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	    if (setreuid(uid, -1) < 0) rb_sys_fail(0);
	}
	else { /* getuid() == uid && geteuid() == uid */
	    if (setreuid(-1, SAVED_USER_ID) < 0) rb_sys_fail(0);
	    if (setreuid(SAVED_USER_ID, uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	    if (setreuid(uid, -1) < 0) rb_sys_fail(0);
	}
#elif defined(HAVE_SETRUID) && defined(HAVE_SETEUID)
	if (SAVED_USER_ID == uid) {
	    if (geteuid() != uid && seteuid(uid) < 0) rb_sys_fail(0);
	    if (getuid() != uid && setruid(uid) < 0) rb_sys_fail(0);
	}
	else if (/* SAVED_USER_ID != uid && */ geteuid() == uid) {
	    if (getuid() != uid) {
		if (setruid(uid) < 0) rb_sys_fail(0);
		SAVED_USER_ID = uid;
	    }
	    else {
		if (setruid(SAVED_USER_ID) < 0) rb_sys_fail(0);
		SAVED_USER_ID = uid;
		if (setruid(uid) < 0) rb_sys_fail(0);
	    }
	}
	else if (/* geteuid() != uid && */ getuid() == uid) {
	    if (seteuid(uid) < 0) rb_sys_fail(0);
	    if (setruid(SAVED_USER_ID) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	    if (setruid(uid) < 0) rb_sys_fail(0);
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_44BSD_SETUID
	if (getuid() == uid) {
	    /* (r,e,s)==(uid,?,?) ==> (uid,uid,uid) */
	    if (setuid(uid) < 0) rb_sys_fail(0);
	    SAVED_USER_ID = uid;
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETEUID
	if (getuid() == uid && SAVED_USER_ID == uid) {
	    if (seteuid(uid) < 0) rb_sys_fail(0);
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETUID
	if (getuid() == uid && SAVED_USER_ID == uid) {
	    if (setuid(uid) < 0) rb_sys_fail(0);
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#else
	rb_notimplement();
#endif
    }
    return id;
}



#if defined HAVE_SETGID
/*
 *  call-seq:
 *     Process::Sys.setgid(group)   -> nil
 *
 *  Set the group ID of the current process to _group_. Not
 *  available on all platforms.
 *
 */

static VALUE
p_sys_setgid(VALUE obj, VALUE id)
{
    check_gid_switch();
    if (setgid(OBJ2GID(id)) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setgid rb_f_notimplement
#endif


#if defined HAVE_SETRGID
/*
 *  call-seq:
 *     Process::Sys.setrgid(group)   -> nil
 *
 *  Set the real group ID of the calling process to _group_.
 *  Not available on all platforms.
 *
 */

static VALUE
p_sys_setrgid(VALUE obj, VALUE id)
{
    check_gid_switch();
    if (setrgid(OBJ2GID(id)) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setrgid rb_f_notimplement
#endif


#if defined HAVE_SETEGID
/*
 *  call-seq:
 *     Process::Sys.setegid(group)   -> nil
 *
 *  Set the effective group ID of the calling process to
 *  _group_.  Not available on all platforms.
 *
 */

static VALUE
p_sys_setegid(VALUE obj, VALUE id)
{
    check_gid_switch();
    if (setegid(OBJ2GID(id)) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setegid rb_f_notimplement
#endif


#if defined HAVE_SETREGID
/*
 *  call-seq:
 *     Process::Sys.setregid(rid, eid)   -> nil
 *
 *  Sets the (group) real and/or effective group IDs of the current
 *  process to <em>rid</em> and <em>eid</em>, respectively. A value of
 *  <code>-1</code> for either means to leave that ID unchanged. Not
 *  available on all platforms.
 *
 */

static VALUE
p_sys_setregid(VALUE obj, VALUE rid, VALUE eid)
{
    rb_gid_t rgid, egid;
    PREPARE_GETGRNAM;
    check_gid_switch();
    rgid = OBJ2GID(rid);
    egid = OBJ2GID(eid);
    FINISH_GETGRNAM;
    if (setregid(rgid, egid) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setregid rb_f_notimplement
#endif

#if defined HAVE_SETRESGID
/*
 *  call-seq:
 *     Process::Sys.setresgid(rid, eid, sid)   -> nil
 *
 *  Sets the (group) real, effective, and saved user IDs of the
 *  current process to <em>rid</em>, <em>eid</em>, and <em>sid</em>
 *  respectively. A value of <code>-1</code> for any value means to
 *  leave that ID unchanged. Not available on all platforms.
 *
 */

static VALUE
p_sys_setresgid(VALUE obj, VALUE rid, VALUE eid, VALUE sid)
{
    rb_gid_t rgid, egid, sgid;
    PREPARE_GETGRNAM;
    check_gid_switch();
    rgid = OBJ2GID(rid);
    egid = OBJ2GID(eid);
    sgid = OBJ2GID(sid);
    FINISH_GETGRNAM;
    if (setresgid(rgid, egid, sgid) != 0) rb_sys_fail(0);
    return Qnil;
}
#else
#define p_sys_setresgid rb_f_notimplement
#endif


#if defined HAVE_ISSETUGID
/*
 *  call-seq:
 *     Process::Sys.issetugid   -> true or false
 *
 *  Returns +true+ if the process was created as a result
 *  of an execve(2) system call which had either of the setuid or
 *  setgid bits set (and extra privileges were given as a result) or
 *  if it has changed any of its real, effective or saved user or
 *  group IDs since it began execution.
 *
 */

static VALUE
p_sys_issetugid(VALUE obj)
{
    rb_secure(2);
    if (issetugid()) {
	return Qtrue;
    }
    else {
	return Qfalse;
    }
}
#else
#define p_sys_issetugid rb_f_notimplement
#endif


/*
 *  call-seq:
 *     Process.gid           -> fixnum
 *     Process::GID.rid      -> fixnum
 *     Process::Sys.getgid   -> fixnum
 *
 *  Returns the (real) group ID for this process.
 *
 *     Process.gid   #=> 500
 */

static VALUE
proc_getgid(VALUE obj)
{
    rb_gid_t gid = getgid();
    return GIDT2NUM(gid);
}


#if defined(HAVE_SETRESGID) || defined(HAVE_SETREGID) || defined(HAVE_SETRGID) || defined(HAVE_SETGID)
/*
 *  call-seq:
 *     Process.gid= fixnum   -> fixnum
 *
 *  Sets the group ID for this process.
 */

static VALUE
proc_setgid(VALUE obj, VALUE id)
{
    rb_gid_t gid;

    check_gid_switch();

    gid = OBJ2GID(id);
#if defined(HAVE_SETRESGID)
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
#endif
    return GIDT2NUM(gid);
}
#else
#define proc_setgid rb_f_notimplement
#endif


#if defined(_SC_NGROUPS_MAX) || defined(NGROUPS_MAX)
/*
 * Maximum supplementary groups are platform dependent.
 * FWIW, 65536 is enough big for our supported OSs.
 *
 * OS Name			max groups
 * -----------------------------------------------
 * Linux Kernel >= 2.6.3	65536
 * Linux Kernel < 2.6.3		   32
 * IBM AIX 5.2			   64
 * IBM AIX 5.3 ... 6.1		  128
 * IBM AIX 7.1			  128 (can be configured to be up to 2048)
 * OpenBSD, NetBSD		   16
 * FreeBSD < 8.0		   16
 * FreeBSD >=8.0		 1023
 * Darwin (Mac OS X)		   16
 * Sun Solaris 7,8,9,10		   16
 * Sun Solaris 11 / OpenSolaris	 1024
 * HP-UX			   20
 * Windows			 1015
 */
static int _maxgroups = -1;
static int
get_sc_ngroups_max(void)
{
#ifdef _SC_NGROUPS_MAX
    return (int)sysconf(_SC_NGROUPS_MAX);
#elif defined(NGROUPS_MAX)
    return (int)NGROUPS_MAX;
#else
    return -1;
#endif
}
static int
maxgroups(void)
{
    if (_maxgroups < 0) {
	_maxgroups = get_sc_ngroups_max();
	if (_maxgroups < 0)
	    _maxgroups = RB_MAX_GROUPS;
    }

    return _maxgroups;
}
#endif



#ifdef HAVE_GETGROUPS
/*
 *  call-seq:
 *     Process.groups   -> array
 *
 *  Get an <code>Array</code> of the gids of groups in the
 *  supplemental group access list for this process.
 *
 *     Process.groups   #=> [27, 6, 10, 11]
 *
 */

static VALUE
proc_getgroups(VALUE obj)
{
    VALUE ary, tmp;
    int i, ngroups;
    rb_gid_t *groups;

    ngroups = getgroups(0, NULL);
    if (ngroups == -1)
	rb_sys_fail(0);

    groups = ALLOCV_N(rb_gid_t, tmp, ngroups);

    ngroups = getgroups(ngroups, groups);
    if (ngroups == -1)
	rb_sys_fail(0);

    ary = rb_ary_new();
    for (i = 0; i < ngroups; i++)
	rb_ary_push(ary, GIDT2NUM(groups[i]));

    ALLOCV_END(tmp);

    return ary;
}
#else
#define proc_getgroups rb_f_notimplement
#endif


#ifdef HAVE_SETGROUPS
/*
 *  call-seq:
 *     Process.groups= array   -> array
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
proc_setgroups(VALUE obj, VALUE ary)
{
    int ngroups, i;
    rb_gid_t *groups;
    VALUE tmp;
    PREPARE_GETGRNAM;

    Check_Type(ary, T_ARRAY);

    ngroups = RARRAY_LENINT(ary);
    if (ngroups > maxgroups())
	rb_raise(rb_eArgError, "too many groups, %d max", maxgroups());

    groups = ALLOCV_N(rb_gid_t, tmp, ngroups);

    for (i = 0; i < ngroups; i++) {
	VALUE g = RARRAY_AREF(ary, i);

	groups[i] = OBJ2GID1(g);
    }
    FINISH_GETGRNAM;

    if (setgroups(ngroups, groups) == -1) /* ngroups <= maxgroups */
	rb_sys_fail(0);

    ALLOCV_END(tmp);

    return proc_getgroups(obj);
}
#else
#define proc_setgroups rb_f_notimplement
#endif


#ifdef HAVE_INITGROUPS
/*
 *  call-seq:
 *     Process.initgroups(username, gid)   -> array
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
proc_initgroups(VALUE obj, VALUE uname, VALUE base_grp)
{
    if (initgroups(StringValuePtr(uname), OBJ2GID(base_grp)) != 0) {
	rb_sys_fail(0);
    }
    return proc_getgroups(obj);
}
#else
#define proc_initgroups rb_f_notimplement
#endif

#if defined(_SC_NGROUPS_MAX) || defined(NGROUPS_MAX)
/*
 *  call-seq:
 *     Process.maxgroups   -> fixnum
 *
 *  Returns the maximum number of gids allowed in the supplemental
 *  group access list.
 *
 *     Process.maxgroups   #=> 32
 */

static VALUE
proc_getmaxgroups(VALUE obj)
{
    return INT2FIX(maxgroups());
}
#else
#define proc_getmaxgroups rb_f_notimplement
#endif

#ifdef HAVE_SETGROUPS
/*
 *  call-seq:
 *     Process.maxgroups= fixnum   -> fixnum
 *
 *  Sets the maximum number of gids allowed in the supplemental group
 *  access list.
 */

static VALUE
proc_setmaxgroups(VALUE obj, VALUE val)
{
    int ngroups = FIX2INT(val);
    int ngroups_max = get_sc_ngroups_max();

    if (ngroups <= 0)
	rb_raise(rb_eArgError, "maxgroups %d shold be positive", ngroups);

    if (ngroups > RB_MAX_GROUPS)
	ngroups = RB_MAX_GROUPS;

    if (ngroups_max > 0 && ngroups > ngroups_max)
	ngroups = ngroups_max;

    _maxgroups = ngroups;

    return INT2FIX(_maxgroups);
}
#else
#define proc_setmaxgroups rb_f_notimplement
#endif

#if defined(HAVE_DAEMON) || (defined(HAVE_WORKING_FORK) && defined(HAVE_SETSID))
static int rb_daemon(int nochdir, int noclose);

/*
 *  call-seq:
 *     Process.daemon()                        -> 0
 *     Process.daemon(nochdir=nil,noclose=nil) -> 0
 *
 *  Detach the process from controlling terminal and run in
 *  the background as system daemon.  Unless the argument
 *  nochdir is true (i.e. non false), it changes the current
 *  working directory to the root ("/"). Unless the argument
 *  noclose is true, daemon() will redirect standard input,
 *  standard output and standard error to /dev/null.
 *  Return zero on success, or raise one of Errno::*.
 */

static VALUE
proc_daemon(int argc, VALUE *argv)
{
    VALUE nochdir, noclose;
    int n;

    rb_secure(2);
    rb_scan_args(argc, argv, "02", &nochdir, &noclose);

    prefork();
    n = rb_daemon(RTEST(nochdir), RTEST(noclose));
    if (n < 0) rb_sys_fail("daemon");
    return INT2FIX(n);
}

static int
rb_daemon(int nochdir, int noclose)
{
    int err = 0;
#ifdef HAVE_DAEMON
    before_fork_ruby();
    err = daemon(nochdir, noclose);
    after_fork_ruby();
    rb_thread_atfork();
#else
    int n;

#define fork_daemon() \
    switch (rb_fork_ruby(NULL)) { \
      case -1: return -1; \
      case 0:  rb_thread_atfork(); break; \
      default: _exit(EXIT_SUCCESS); \
    }

    fork_daemon();

    if (setsid() < 0) return -1;

    /* must not be process-leader */
    fork_daemon();

    if (!nochdir)
	err = chdir("/");

    if (!noclose && (n = rb_cloexec_open("/dev/null", O_RDWR, 0)) != -1) {
        rb_update_max_fd(n);
	(void)dup2(n, 0);
	(void)dup2(n, 1);
	(void)dup2(n, 2);
	if (n > 2)
	    (void)close (n);
    }
#endif
    return err;
}
#else
#define proc_daemon rb_f_notimplement
#endif

/********************************************************************
 *
 * Document-class: Process::GID
 *
 *  The <code>Process::GID</code> module contains a collection of
 *  module functions which can be used to portably get, set, and
 *  switch the current process's real, effective, and saved group IDs.
 *
 */

static rb_gid_t SAVED_GROUP_ID = -1;

#ifdef BROKEN_SETREGID
int
setregid(rb_gid_t rgid, rb_gid_t egid)
{
    if (rgid != (rb_gid_t)-1 && rgid != getgid()) {
	if (egid == (rb_gid_t)-1) egid = getegid();
	if (setgid(rgid) < 0) return -1;
    }
    if (egid != (rb_gid_t)-1 && egid != getegid()) {
	if (setegid(egid) < 0) return -1;
    }
    return 0;
}
#endif

/*
 *  call-seq:
 *     Process::GID.change_privilege(group)   -> fixnum
 *
 *  Change the current process's real and effective group ID to that
 *  specified by _group_. Returns the new group ID. Not
 *  available on all platforms.
 *
 *     [Process.gid, Process.egid]          #=> [0, 0]
 *     Process::GID.change_privilege(33)    #=> 33
 *     [Process.gid, Process.egid]          #=> [33, 33]
 */

static VALUE
p_gid_change_privilege(VALUE obj, VALUE id)
{
    rb_gid_t gid;

    check_gid_switch();

    gid = OBJ2GID(id);

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
	    }
	    else {
		if (gid == 0) { /* (r,e,s) == (root, y, x) */
		    if (setregid(-1, SAVED_GROUP_ID) < 0) rb_sys_fail(0);
		    if (setregid(SAVED_GROUP_ID, 0) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0; /* (r,e,s) == (x, root, root) */
		    if (setregid(gid, gid) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = gid;
		}
		else { /* (r,e,s) == (z, y, x) */
		    if (setregid(0, 0) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0;
		    if (setregid(gid, gid) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = gid;
		}
	    }
	}
	else {
	    if (setregid(gid, gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	}
#elif defined(HAVE_SETRGID) && defined (HAVE_SETEGID)
	if (getgid() == gid) {
	    if (SAVED_GROUP_ID == gid) {
		if (setegid(gid) < 0) rb_sys_fail(0);
	    }
	    else {
		if (gid == 0) {
		    if (setegid(gid) < 0) rb_sys_fail(0);
		    if (setrgid(SAVED_GROUP_ID) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0;
		    if (setrgid(0) < 0) rb_sys_fail(0);
		}
		else {
		    if (setrgid(0) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = 0;
		    if (setegid(gid) < 0) rb_sys_fail(0);
		    if (setrgid(gid) < 0) rb_sys_fail(0);
		    SAVED_GROUP_ID = gid;
		}
	    }
	}
	else {
	    if (setegid(gid) < 0) rb_sys_fail(0);
	    if (setrgid(gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	}
#else
	rb_notimplement();
#endif
    }
    else { /* unprivileged user */
#if defined(HAVE_SETRESGID)
	if (setresgid((getgid() == gid)? (rb_gid_t)-1: gid,
		      (getegid() == gid)? (rb_gid_t)-1: gid,
		      (SAVED_GROUP_ID == gid)? (rb_gid_t)-1: gid) < 0) rb_sys_fail(0);
	SAVED_GROUP_ID = gid;
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
	if (SAVED_GROUP_ID == gid) {
	    if (setregid((getgid() == gid)? (rb_uid_t)-1: gid,
			 (getegid() == gid)? (rb_uid_t)-1: gid) < 0)
		rb_sys_fail(0);
	}
	else if (getgid() != gid) {
	    if (setregid(gid, (getegid() == gid)? (rb_uid_t)-1: gid) < 0)
		rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	}
	else if (/* getgid() == gid && */ getegid() != gid) {
	    if (setregid(getegid(), gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	    if (setregid(gid, -1) < 0) rb_sys_fail(0);
	}
	else { /* getgid() == gid && getegid() == gid */
	    if (setregid(-1, SAVED_GROUP_ID) < 0) rb_sys_fail(0);
	    if (setregid(SAVED_GROUP_ID, gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	    if (setregid(gid, -1) < 0) rb_sys_fail(0);
	}
#elif defined(HAVE_SETRGID) && defined(HAVE_SETEGID)
	if (SAVED_GROUP_ID == gid) {
	    if (getegid() != gid && setegid(gid) < 0) rb_sys_fail(0);
	    if (getgid() != gid && setrgid(gid) < 0) rb_sys_fail(0);
	}
	else if (/* SAVED_GROUP_ID != gid && */ getegid() == gid) {
	    if (getgid() != gid) {
		if (setrgid(gid) < 0) rb_sys_fail(0);
		SAVED_GROUP_ID = gid;
	    }
	    else {
		if (setrgid(SAVED_GROUP_ID) < 0) rb_sys_fail(0);
		SAVED_GROUP_ID = gid;
		if (setrgid(gid) < 0) rb_sys_fail(0);
	    }
	}
	else if (/* getegid() != gid && */ getgid() == gid) {
	    if (setegid(gid) < 0) rb_sys_fail(0);
	    if (setrgid(SAVED_GROUP_ID) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	    if (setrgid(gid) < 0) rb_sys_fail(0);
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_44BSD_SETGID
	if (getgid() == gid) {
	    /* (r,e,s)==(gid,?,?) ==> (gid,gid,gid) */
	    if (setgid(gid) < 0) rb_sys_fail(0);
	    SAVED_GROUP_ID = gid;
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETEGID
	if (getgid() == gid && SAVED_GROUP_ID == gid) {
	    if (setegid(gid) < 0) rb_sys_fail(0);
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#elif defined HAVE_SETGID
	if (getgid() == gid && SAVED_GROUP_ID == gid) {
	    if (setgid(gid) < 0) rb_sys_fail(0);
	}
	else {
	    errno = EPERM;
	    rb_sys_fail(0);
	}
#else
	(void)gid;
	rb_notimplement();
#endif
    }
    return id;
}


/*
 *  call-seq:
 *     Process.euid           -> fixnum
 *     Process::UID.eid       -> fixnum
 *     Process::Sys.geteuid   -> fixnum
 *
 *  Returns the effective user ID for this process.
 *
 *     Process.euid   #=> 501
 */

static VALUE
proc_geteuid(VALUE obj)
{
    rb_uid_t euid = geteuid();
    return UIDT2NUM(euid);
}

#if defined(HAVE_SETRESUID) || defined(HAVE_SETREUID) || defined(HAVE_SETEUID) || defined(HAVE_SETUID) || defined(_POSIX_SAVED_IDS)
static void
proc_seteuid(rb_uid_t uid)
{
#if defined(HAVE_SETRESUID)
    if (setresuid(-1, uid, -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETREUID
    if (setreuid(-1, uid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETEUID
    if (seteuid(uid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETUID
    if (uid == getuid()) {
	if (setuid(uid) < 0) rb_sys_fail(0);
    }
    else {
	rb_notimplement();
    }
#else
    rb_notimplement();
#endif
}
#endif

#if defined(HAVE_SETRESUID) || defined(HAVE_SETREUID) || defined(HAVE_SETEUID) || defined(HAVE_SETUID)
/*
 *  call-seq:
 *     Process.euid= user
 *
 *  Sets the effective user ID for this process. Not available on all
 *  platforms.
 */

static VALUE
proc_seteuid_m(VALUE mod, VALUE euid)
{
    check_uid_switch();
    proc_seteuid(OBJ2UID(euid));
    return euid;
}
#else
#define proc_seteuid_m rb_f_notimplement
#endif

static rb_uid_t
rb_seteuid_core(rb_uid_t euid)
{
#if defined(HAVE_SETRESUID) || (defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID))
    rb_uid_t uid;
#endif

    check_uid_switch();

#if defined(HAVE_SETRESUID) || (defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID))
    uid = getuid();
#endif

#if defined(HAVE_SETRESUID)
    if (uid != euid) {
	if (setresuid(-1,euid,euid) < 0) rb_sys_fail(0);
	SAVED_USER_ID = euid;
    }
    else {
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
    return euid;
}


/*
 *  call-seq:
 *     Process::UID.grant_privilege(user)   -> fixnum
 *     Process::UID.eid= user               -> fixnum
 *
 *  Set the effective user ID, and if possible, the saved user ID of
 *  the process to the given _user_. Returns the new
 *  effective user ID. Not available on all platforms.
 *
 *     [Process.uid, Process.euid]          #=> [0, 0]
 *     Process::UID.grant_privilege(31)     #=> 31
 *     [Process.uid, Process.euid]          #=> [0, 31]
 */

static VALUE
p_uid_grant_privilege(VALUE obj, VALUE id)
{
    rb_seteuid_core(OBJ2UID(id));
    return id;
}


/*
 *  call-seq:
 *     Process.egid          -> fixnum
 *     Process::GID.eid      -> fixnum
 *     Process::Sys.geteid   -> fixnum
 *
 *  Returns the effective group ID for this process. Not available on
 *  all platforms.
 *
 *     Process.egid   #=> 500
 */

static VALUE
proc_getegid(VALUE obj)
{
    rb_gid_t egid = getegid();

    return GIDT2NUM(egid);
}

#if defined(HAVE_SETRESGID) || defined(HAVE_SETREGID) || defined(HAVE_SETEGID) || defined(HAVE_SETGID) || defined(_POSIX_SAVED_IDS)
/*
 *  call-seq:
 *     Process.egid = fixnum   -> fixnum
 *
 *  Sets the effective group ID for this process. Not available on all
 *  platforms.
 */

static VALUE
proc_setegid(VALUE obj, VALUE egid)
{
#if defined(HAVE_SETRESGID) || defined(HAVE_SETREGID) || defined(HAVE_SETEGID) || defined(HAVE_SETGID)
    rb_gid_t gid;
#endif

    check_gid_switch();

#if defined(HAVE_SETRESGID) || defined(HAVE_SETREGID) || defined(HAVE_SETEGID) || defined(HAVE_SETGID)
    gid = OBJ2GID(egid);
#endif

#if defined(HAVE_SETRESGID)
    if (setresgid(-1, gid, -1) < 0) rb_sys_fail(0);
#elif defined HAVE_SETREGID
    if (setregid(-1, gid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETEGID
    if (setegid(gid) < 0) rb_sys_fail(0);
#elif defined HAVE_SETGID
    if (gid == getgid()) {
	if (setgid(gid) < 0) rb_sys_fail(0);
    }
    else {
	rb_notimplement();
    }
#else
    rb_notimplement();
#endif
    return egid;
}
#endif

#if defined(HAVE_SETRESGID) || defined(HAVE_SETREGID) || defined(HAVE_SETEGID) || defined(HAVE_SETGID)
#define proc_setegid_m proc_setegid
#else
#define proc_setegid_m rb_f_notimplement
#endif

static rb_gid_t
rb_setegid_core(rb_gid_t egid)
{
#if defined(HAVE_SETRESGID) || (defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID))
    rb_gid_t gid;
#endif

    check_gid_switch();

#if defined(HAVE_SETRESGID) || (defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID))
    gid = getgid();
#endif

#if defined(HAVE_SETRESGID)
    if (gid != egid) {
	if (setresgid(-1,egid,egid) < 0) rb_sys_fail(0);
	SAVED_GROUP_ID = egid;
    }
    else {
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
    return egid;
}


/*
 *  call-seq:
 *     Process::GID.grant_privilege(group)    -> fixnum
 *     Process::GID.eid = group               -> fixnum
 *
 *  Set the effective group ID, and if possible, the saved group ID of
 *  the process to the given _group_. Returns the new
 *  effective group ID. Not available on all platforms.
 *
 *     [Process.gid, Process.egid]          #=> [0, 0]
 *     Process::GID.grant_privilege(31)     #=> 33
 *     [Process.gid, Process.egid]          #=> [0, 33]
 */

static VALUE
p_gid_grant_privilege(VALUE obj, VALUE id)
{
    rb_setegid_core(OBJ2GID(id));
    return id;
}


/*
 *  call-seq:
 *     Process::UID.re_exchangeable?   -> true or false
 *
 *  Returns +true+ if the real and effective user IDs of a
 *  process may be exchanged on the current platform.
 *
 */

static VALUE
p_uid_exchangeable(void)
{
#if defined(HAVE_SETRESUID)
    return Qtrue;
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
    return Qtrue;
#else
    return Qfalse;
#endif
}


/*
 *  call-seq:
 *     Process::UID.re_exchange   -> fixnum
 *
 *  Exchange real and effective user IDs and return the new effective
 *  user ID. Not available on all platforms.
 *
 *     [Process.uid, Process.euid]   #=> [0, 31]
 *     Process::UID.re_exchange      #=> 0
 *     [Process.uid, Process.euid]   #=> [31, 0]
 */

static VALUE
p_uid_exchange(VALUE obj)
{
    rb_uid_t uid;
#if defined(HAVE_SETRESUID) || (defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID))
    rb_uid_t euid;
#endif

    check_uid_switch();

    uid = getuid();
#if defined(HAVE_SETRESUID) || (defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID))
    euid = geteuid();
#endif

#if defined(HAVE_SETRESUID)
    if (setresuid(euid, uid, uid) < 0) rb_sys_fail(0);
    SAVED_USER_ID = uid;
#elif defined(HAVE_SETREUID) && !defined(OBSOLETE_SETREUID)
    if (setreuid(euid,uid) < 0) rb_sys_fail(0);
    SAVED_USER_ID = uid;
#else
    rb_notimplement();
#endif
    return UIDT2NUM(uid);
}


/*
 *  call-seq:
 *     Process::GID.re_exchangeable?   -> true or false
 *
 *  Returns +true+ if the real and effective group IDs of a
 *  process may be exchanged on the current platform.
 *
 */

static VALUE
p_gid_exchangeable(void)
{
#if defined(HAVE_SETRESGID)
    return Qtrue;
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
    return Qtrue;
#else
    return Qfalse;
#endif
}


/*
 *  call-seq:
 *     Process::GID.re_exchange   -> fixnum
 *
 *  Exchange real and effective group IDs and return the new effective
 *  group ID. Not available on all platforms.
 *
 *     [Process.gid, Process.egid]   #=> [0, 33]
 *     Process::GID.re_exchange      #=> 0
 *     [Process.gid, Process.egid]   #=> [33, 0]
 */

static VALUE
p_gid_exchange(VALUE obj)
{
    rb_gid_t gid;
#if defined(HAVE_SETRESGID) || (defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID))
    rb_gid_t egid;
#endif

    check_gid_switch();

    gid = getgid();
#if defined(HAVE_SETRESGID) || (defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID))
    egid = getegid();
#endif

#if defined(HAVE_SETRESGID)
    if (setresgid(egid, gid, gid) < 0) rb_sys_fail(0);
    SAVED_GROUP_ID = gid;
#elif defined(HAVE_SETREGID) && !defined(OBSOLETE_SETREGID)
    if (setregid(egid,gid) < 0) rb_sys_fail(0);
    SAVED_GROUP_ID = gid;
#else
    rb_notimplement();
#endif
    return GIDT2NUM(gid);
}

/* [MG] :FIXME: Is this correct? I'm not sure how to phrase this. */

/*
 *  call-seq:
 *     Process::UID.sid_available?   -> true or false
 *
 *  Returns +true+ if the current platform has saved user
 *  ID functionality.
 *
 */

static VALUE
p_uid_have_saved_id(void)
{
#if defined(HAVE_SETRESUID) || defined(HAVE_SETEUID) || defined(_POSIX_SAVED_IDS)
    return Qtrue;
#else
    return Qfalse;
#endif
}


#if defined(HAVE_SETRESUID) || defined(HAVE_SETEUID) || defined(_POSIX_SAVED_IDS)
static VALUE
p_uid_sw_ensure(rb_uid_t id)
{
    under_uid_switch = 0;
    id = rb_seteuid_core(id);
    return UIDT2NUM(id);
}


/*
 *  call-seq:
 *     Process::UID.switch              -> fixnum
 *     Process::UID.switch {|| block}   -> object
 *
 *  Switch the effective and real user IDs of the current process. If
 *  a <em>block</em> is given, the user IDs will be switched back
 *  after the block is executed. Returns the new effective user ID if
 *  called without a block, and the return value of the block if one
 *  is given.
 *
 */

static VALUE
p_uid_switch(VALUE obj)
{
    rb_uid_t uid, euid;

    check_uid_switch();

    uid = getuid();
    euid = geteuid();

    if (uid != euid) {
	proc_seteuid(uid);
	if (rb_block_given_p()) {
	    under_uid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_uid_sw_ensure, SAVED_USER_ID);
	}
	else {
	    return UIDT2NUM(euid);
	}
    }
    else if (euid != SAVED_USER_ID) {
	proc_seteuid(SAVED_USER_ID);
	if (rb_block_given_p()) {
	    under_uid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_uid_sw_ensure, euid);
	}
	else {
	    return UIDT2NUM(uid);
	}
    }
    else {
	errno = EPERM;
	rb_sys_fail(0);
    }

    UNREACHABLE;
}
#else
static VALUE
p_uid_sw_ensure(VALUE obj)
{
    under_uid_switch = 0;
    return p_uid_exchange(obj);
}

static VALUE
p_uid_switch(VALUE obj)
{
    rb_uid_t uid, euid;

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
    }
    else {
	return UIDT2NUM(euid);
    }
}
#endif


/* [MG] :FIXME: Is this correct? I'm not sure how to phrase this. */

/*
 *  call-seq:
 *     Process::GID.sid_available?   -> true or false
 *
 *  Returns +true+ if the current platform has saved group
 *  ID functionality.
 *
 */

static VALUE
p_gid_have_saved_id(void)
{
#if defined(HAVE_SETRESGID) || defined(HAVE_SETEGID) || defined(_POSIX_SAVED_IDS)
    return Qtrue;
#else
    return Qfalse;
#endif
}

#if defined(HAVE_SETRESGID) || defined(HAVE_SETEGID) || defined(_POSIX_SAVED_IDS)
static VALUE
p_gid_sw_ensure(rb_gid_t id)
{
    under_gid_switch = 0;
    id = rb_setegid_core(id);
    return GIDT2NUM(id);
}


/*
 *  call-seq:
 *     Process::GID.switch              -> fixnum
 *     Process::GID.switch {|| block}   -> object
 *
 *  Switch the effective and real group IDs of the current process. If
 *  a <em>block</em> is given, the group IDs will be switched back
 *  after the block is executed. Returns the new effective group ID if
 *  called without a block, and the return value of the block if one
 *  is given.
 *
 */

static VALUE
p_gid_switch(VALUE obj)
{
    rb_gid_t gid, egid;

    check_gid_switch();

    gid = getgid();
    egid = getegid();

    if (gid != egid) {
	proc_setegid(obj, GIDT2NUM(gid));
	if (rb_block_given_p()) {
	    under_gid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_gid_sw_ensure, SAVED_GROUP_ID);
	}
	else {
	    return GIDT2NUM(egid);
	}
    }
    else if (egid != SAVED_GROUP_ID) {
	proc_setegid(obj, GIDT2NUM(SAVED_GROUP_ID));
	if (rb_block_given_p()) {
	    under_gid_switch = 1;
	    return rb_ensure(rb_yield, Qnil, p_gid_sw_ensure, egid);
	}
	else {
	    return GIDT2NUM(gid);
	}
    }
    else {
	errno = EPERM;
	rb_sys_fail(0);
    }

    UNREACHABLE;
}
#else
static VALUE
p_gid_sw_ensure(VALUE obj)
{
    under_gid_switch = 0;
    return p_gid_exchange(obj);
}

static VALUE
p_gid_switch(VALUE obj)
{
    rb_gid_t gid, egid;

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
    }
    else {
	return GIDT2NUM(egid);
    }
}
#endif


#if defined(HAVE_TIMES)
static long
get_clk_tck(void)
{
    long hertz =
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
    return hertz;
}

/*
 *  call-seq:
 *     Process.times   -> aProcessTms
 *
 *  Returns a <code>Tms</code> structure (see <code>Process::Tms</code>)
 *  that contains user and system CPU times for this process,
 *  and also for children processes.
 *
 *     t = Process.times
 *     [ t.utime, t.stime, t.cutime, t.cstime ]   #=> [0.0, 0.02, 0.00, 0.00]
 */

VALUE
rb_proc_times(VALUE obj)
{
    const double hertz = get_clk_tck();
    struct tms buf;
    VALUE utime, stime, cutime, cstime, ret;

    times(&buf);
    utime = DBL2NUM(buf.tms_utime / hertz);
    stime = DBL2NUM(buf.tms_stime / hertz);
    cutime = DBL2NUM(buf.tms_cutime / hertz);
    cstime = DBL2NUM(buf.tms_cstime / hertz);
    ret = rb_struct_new(rb_cProcessTms, utime, stime, cutime, cstime);
    RB_GC_GUARD(utime);
    RB_GC_GUARD(stime);
    RB_GC_GUARD(cutime);
    RB_GC_GUARD(cstime);
    return ret;
}
#else
#define rb_proc_times rb_f_notimplement
#endif

#ifdef HAVE_LONG_LONG
typedef LONG_LONG timetick_int_t;
#define TIMETICK_INT_MIN LLONG_MIN
#define TIMETICK_INT_MAX LLONG_MAX
#define TIMETICK_INT2NUM(v) LL2NUM(v)
#else
typedef long timetick_int_t;
#define TIMETICK_INT_MIN LONG_MIN
#define TIMETICK_INT_MAX LONG_MAX
#define TIMETICK_INT2NUM(v) LONG2NUM(v)
#endif

static timetick_int_t
gcd_timetick_int(timetick_int_t a, timetick_int_t b)
{
    timetick_int_t t;

    if (a < b) {
        t = a;
        a = b;
        b = t;
    }

    while (1) {
        t = a % b;
        if (t == 0)
            return b;
        a = b;
        b = t;
    }
}

static void
reduce_fraction(timetick_int_t *np, timetick_int_t *dp)
{
    timetick_int_t gcd = gcd_timetick_int(*np, *dp);
    if (gcd != 1) {
        *np /= gcd;
        *dp /= gcd;
    }
}

static void
reduce_factors(timetick_int_t *numerators, int num_numerators,
               timetick_int_t *denominators, int num_denominators)
{
    int i, j;
    for (i = 0; i < num_numerators; i++) {
        if (numerators[i] == 1)
            continue;
        for (j = 0; j < num_denominators; j++) {
            if (denominators[j] == 1)
                continue;
            reduce_fraction(&numerators[i], &denominators[j]);
        }
    }
}

struct timetick {
    timetick_int_t giga_count;
    int32_t count; /* 0 .. 999999999 */
};

static VALUE
timetick2dblnum(struct timetick *ttp,
    timetick_int_t *numerators, int num_numerators,
    timetick_int_t *denominators, int num_denominators)
{
    double d;
    int i;

    reduce_factors(numerators, num_numerators,
                   denominators, num_denominators);

    d = ttp->giga_count * 1e9 + ttp->count;

    for (i = 0; i < num_numerators; i++)
        d *= numerators[i];
    for (i = 0; i < num_denominators; i++)
        d /= denominators[i];

    return DBL2NUM(d);
}

static VALUE
timetick2dblnum_reciprocal(struct timetick *ttp,
    timetick_int_t *numerators, int num_numerators,
    timetick_int_t *denominators, int num_denominators)
{
    double d;
    int i;

    reduce_factors(numerators, num_numerators,
                   denominators, num_denominators);

    d = 1.0;
    for (i = 0; i < num_denominators; i++)
        d *= denominators[i];
    for (i = 0; i < num_numerators; i++)
        d /= numerators[i];
    d /= ttp->giga_count * 1e9 + ttp->count;

    return DBL2NUM(d);
}

#define NDIV(x,y) (-(-((x)+1)/(y))-1)
#define DIV(n,d) ((n)<0 ? NDIV((n),(d)) : (n)/(d))

static VALUE
timetick2integer(struct timetick *ttp,
        timetick_int_t *numerators, int num_numerators,
        timetick_int_t *denominators, int num_denominators)
{
    VALUE v;
    int i;

    reduce_factors(numerators, num_numerators,
                   denominators, num_denominators);

    if (!MUL_OVERFLOW_SIGNED_INTEGER_P(1000000000, ttp->giga_count,
                TIMETICK_INT_MIN, TIMETICK_INT_MAX-ttp->count)) {
        timetick_int_t t = ttp->giga_count * 1000000000 + ttp->count;
        for (i = 0; i < num_numerators; i++) {
            timetick_int_t factor = numerators[i];
            if (MUL_OVERFLOW_SIGNED_INTEGER_P(factor, t,
                        TIMETICK_INT_MIN, TIMETICK_INT_MAX))
                goto generic;
            t *= factor;
        }
        for (i = 0; i < num_denominators; i++) {
            t = DIV(t, denominators[i]);
        }
        return TIMETICK_INT2NUM(t);
    }

  generic:
    v = TIMETICK_INT2NUM(ttp->giga_count);
    v = rb_funcall(v, '*', 1, LONG2FIX(1000000000));
    v = rb_funcall(v, '+', 1, LONG2FIX(ttp->count));
    for (i = 0; i < num_numerators; i++) {
        timetick_int_t factor = numerators[i];
        if (factor == 1)
            continue;
        v = rb_funcall(v, '*', 1, TIMETICK_INT2NUM(factor));
    }
    for (i = 0; i < num_denominators; i++) {
        v = rb_funcall(v, '/', 1, TIMETICK_INT2NUM(denominators[i])); /* Ruby's '/' is div. */
    }
    return v;
}

static VALUE
make_clock_result(struct timetick *ttp,
        timetick_int_t *numerators, int num_numerators,
        timetick_int_t *denominators, int num_denominators,
        VALUE unit)
{
    if (unit == ID2SYM(id_nanosecond)) {
        numerators[num_numerators++] = 1000000000;
        return timetick2integer(ttp, numerators, num_numerators, denominators, num_denominators);
    }
    else if (unit == ID2SYM(id_microsecond)) {
        numerators[num_numerators++] = 1000000;
        return timetick2integer(ttp, numerators, num_numerators, denominators, num_denominators);
    }
    else if (unit == ID2SYM(id_millisecond)) {
        numerators[num_numerators++] = 1000;
        return timetick2integer(ttp, numerators, num_numerators, denominators, num_denominators);
    }
    else if (unit == ID2SYM(id_second)) {
        return timetick2integer(ttp, numerators, num_numerators, denominators, num_denominators);
    }
    else if (unit == ID2SYM(id_float_microsecond)) {
        numerators[num_numerators++] = 1000000;
        return timetick2dblnum(ttp, numerators, num_numerators, denominators, num_denominators);
    }
    else if (unit == ID2SYM(id_float_millisecond)) {
        numerators[num_numerators++] = 1000;
        return timetick2dblnum(ttp, numerators, num_numerators, denominators, num_denominators);
    }
    else if (NIL_P(unit) || unit == ID2SYM(id_float_second)) {
        return timetick2dblnum(ttp, numerators, num_numerators, denominators, num_denominators);
    }
    else
        rb_raise(rb_eArgError, "unexpected unit: %"PRIsVALUE, unit);
}

#ifdef __APPLE__
static mach_timebase_info_data_t *
get_mach_timebase_info(void)
{
    static mach_timebase_info_data_t sTimebaseInfo;

    if ( sTimebaseInfo.denom == 0 ) {
        (void) mach_timebase_info(&sTimebaseInfo);
    }

    return &sTimebaseInfo;
}
#endif

/*
 *  call-seq:
 *     Process.clock_gettime(clock_id [, unit])   -> number
 *
 *  Returns a time returned by POSIX clock_gettime() function.
 *
 *    p Process.clock_gettime(Process::CLOCK_MONOTONIC)
 *    #=> 896053.968060096
 *
 *  +clock_id+ specifies a kind of clock.
 *  It is specifed as a constant which begins with <code>Process::CLOCK_</code>
 *  such as Process::CLOCK_REALTIME and Process::CLOCK_MONOTONIC.
 *
 *  The supported constants depends on OS and version.
 *  Ruby provides following types of +clock_id+ if available.
 *
 *  [CLOCK_REALTIME] SUSv2 to 4, Linux 2.5.63, FreeBSD 3.0, NetBSD 2.0, OpenBSD 2.1
 *  [CLOCK_MONOTONIC] SUSv3 to 4, Linux 2.5.63, FreeBSD 3.0, NetBSD 2.0, OpenBSD 3.4
 *  [CLOCK_PROCESS_CPUTIME_ID] SUSv3 to 4, Linux 2.5.63, OpenBSD 5.4
 *  [CLOCK_THREAD_CPUTIME_ID] SUSv3 to 4, Linux 2.5.63, FreeBSD 7.1, OpenBSD 5.4
 *  [CLOCK_VIRTUAL] FreeBSD 3.0, OpenBSD 2.1
 *  [CLOCK_PROF] FreeBSD 3.0, OpenBSD 2.1
 *  [CLOCK_REALTIME_FAST] FreeBSD 8.1
 *  [CLOCK_REALTIME_PRECISE] FreeBSD 8.1
 *  [CLOCK_REALTIME_COARSE] Linux 2.6.32
 *  [CLOCK_REALTIME_ALARM] Linux 3.0
 *  [CLOCK_MONOTONIC_FAST] FreeBSD 8.1
 *  [CLOCK_MONOTONIC_PRECISE] FreeBSD 8.1
 *  [CLOCK_MONOTONIC_COARSE] Linux 2.6.32
 *  [CLOCK_MONOTONIC_RAW] Linux 2.6.28
 *  [CLOCK_BOOTTIME] Linux 2.6.39
 *  [CLOCK_BOOTTIME_ALARM] Linux 3.0
 *  [CLOCK_UPTIME] FreeBSD 7.0, OpenBSD 5.5
 *  [CLOCK_UPTIME_FAST] FreeBSD 8.1
 *  [CLOCK_UPTIME_PRECISE] FreeBSD 8.1
 *  [CLOCK_SECOND] FreeBSD 8.1
 *
 *  Note that SUS stands for Single Unix Specification.
 *  SUS contains POSIX and clock_gettime is defined in the POSIX part.
 *  SUS defines CLOCK_REALTIME mandatory but
 *  CLOCK_MONOTONIC, CLOCK_PROCESS_CPUTIME_ID and CLOCK_THREAD_CPUTIME_ID are optional.
 *
 *  Also, several symbols are accepted as +clock_id+.
 *  There are emulations for clock_gettime().
 *
 *  For example, Process::CLOCK_REALTIME is defined as
 *  +:GETTIMEOFDAY_BASED_CLOCK_REALTIME+ when clock_gettime() is not available.
 *
 *  Emulations for +CLOCK_REALTIME+:
 *  [:GETTIMEOFDAY_BASED_CLOCK_REALTIME]
 *    Use gettimeofday() defined by SUS.
 *    (SUSv4 obsoleted it, though.)
 *    The resolution is 1 microsecond.
 *  [:TIME_BASED_CLOCK_REALTIME]
 *    Use time() defined by ISO C.
 *    The resolution is 1 second.
 *
 *  Emulations for +CLOCK_MONOTONIC+:
 *  [:MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC]
 *    Use mach_absolute_time(), available on Darwin.
 *    The resolution is CPU dependent.
 *  [:TIMES_BASED_CLOCK_MONOTONIC]
 *    Use the result value of times() defined by POSIX.
 *    POSIX defines it as "times() shall return the elapsed real time, in clock ticks, since an arbitrary point in the past (for example, system start-up time)".
 *    For example, GNU/Linux returns a value based on jiffies and it is monotonic.
 *    However, 4.4BSD uses gettimeofday() and it is not monotonic.
 *    (FreeBSD uses clock_gettime(CLOCK_MONOTONIC) instead, though.)
 *    The resolution is the clock tick.
 *    "getconf CLK_TCK" command shows the clock ticks per second.
 *    (The clock ticks per second is defined by HZ macro in older systems.)
 *    If it is 100 and clock_t is 32 bits integer type, the resolution is 10 millisecond and
 *    cannot represent over 497 days.
 *
 *  Emulations for +CLOCK_PROCESS_CPUTIME_ID+:
 *  [:GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID]
 *    Use getrusage() defined by SUS.
 *    getrusage() is used with RUSAGE_SELF to obtain the time only for
 *    the calling process (excluding the time for child processes).
 *    The result is addition of user time (ru_utime) and system time (ru_stime).
 *    The resolution is 1 microsecond.
 *  [:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID]
 *    Use times() defined by POSIX.
 *    The result is addition of user time (tms_utime) and system time (tms_stime).
 *    tms_cutime and tms_cstime are ignored to exclude the time for child processes.
 *    The resolution is the clock tick.
 *    "getconf CLK_TCK" command shows the clock ticks per second.
 *    (The clock ticks per second is defined by HZ macro in older systems.)
 *    If it is 100, the resolution is 10 millisecond.
 *  [:CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID]
 *    Use clock() defined by ISO C.
 *    The resolution is 1/CLOCKS_PER_SEC.
 *    CLOCKS_PER_SEC is the C-level macro defined by time.h.
 *    SUS defines CLOCKS_PER_SEC is 1000000.
 *    Non-Unix systems may define it a different value, though.
 *    If CLOCKS_PER_SEC is 1000000 as SUS, the resolution is 1 microsecond.
 *    If CLOCKS_PER_SEC is 1000000 and clock_t is 32 bits integer type, it cannot represent over 72 minutes.
 *
 *  If the given +clock_id+ is not supported, Errno::EINVAL is raised.
 *
 *  +unit+ specifies a type of the return value.
 *
 *  [:float_second] number of seconds as a float (default)
 *  [:float_millisecond] number of milliseconds as a float
 *  [:float_microsecond] number of microseconds as a float
 *  [:second] number of seconds as an integer
 *  [:millisecond] number of milliseconds as an integer
 *  [:microsecond] number of microseconds as an integer
 *  [:nanosecond] number of nanoseconds as an integer
 *
 *  The underlying function, clock_gettime(), returns a number of nanoseconds.
 *  Float object (IEEE 754 double) is not enough to represent
 *  the return value for CLOCK_REALTIME.
 *  If the exact nanoseconds value is required, use +:nanoseconds+ as the +unit+.
 *
 *  The origin (zero) of the returned value varies.
 *  For example, system start up time, process start up time, the Epoch, etc.
 *
 *  The origin in CLOCK_REALTIME is defined as the Epoch
 *  (1970-01-01 00:00:00 UTC).
 *  But some systems count leap seconds and others doesn't.
 *  So the result can be interpreted differently across systems.
 *  Time.now is recommended over CLOCK_REALTIME.
 */
VALUE
rb_clock_gettime(int argc, VALUE *argv)
{
    VALUE clk_id, unit;
    int ret;

    struct timetick tt;
    timetick_int_t numerators[2];
    timetick_int_t denominators[2];
    int num_numerators = 0;
    int num_denominators = 0;

    rb_scan_args(argc, argv, "11", &clk_id, &unit);

    if (SYMBOL_P(clk_id)) {
        /*
         * Non-clock_gettime clocks are provided by symbol clk_id.
         *
         * gettimeofday is always available on platforms supported by Ruby.
         * GETTIMEOFDAY_BASED_CLOCK_REALTIME is used for
         * CLOCK_REALTIME if clock_gettime is not available.
         */
#define RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME ID2SYM(id_GETTIMEOFDAY_BASED_CLOCK_REALTIME)
        if (clk_id == RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME) {
            struct timeval tv;
            ret = gettimeofday(&tv, 0);
            if (ret != 0)
                rb_sys_fail("gettimeofday");
            tt.giga_count = tv.tv_sec;
            tt.count = (int32_t)tv.tv_usec * 1000;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }

#define RUBY_TIME_BASED_CLOCK_REALTIME ID2SYM(id_TIME_BASED_CLOCK_REALTIME)
        if (clk_id == RUBY_TIME_BASED_CLOCK_REALTIME) {
            time_t t;
            t = time(NULL);
            if (t == (time_t)-1)
                rb_sys_fail("time");
            tt.giga_count = t;
            tt.count = 0;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }

#ifdef HAVE_TIMES
#define RUBY_TIMES_BASED_CLOCK_MONOTONIC \
        ID2SYM(id_TIMES_BASED_CLOCK_MONOTONIC)
        if (clk_id == RUBY_TIMES_BASED_CLOCK_MONOTONIC) {
            struct tms buf;
            clock_t c;
            unsigned_clock_t uc;
            c = times(&buf);
            if (c ==  (clock_t)-1)
                rb_sys_fail("times");
            uc = (unsigned_clock_t)c;
            tt.count = (int32_t)(uc % 1000000000);
            tt.giga_count = (uc / 1000000000);
            denominators[num_denominators++] = get_clk_tck();
            goto success;
        }
#endif

#ifdef RUSAGE_SELF
#define RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID \
        ID2SYM(id_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID)
        if (clk_id == RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID) {
            struct rusage usage;
            int32_t usec;
            ret = getrusage(RUSAGE_SELF, &usage);
            if (ret != 0)
                rb_sys_fail("getrusage");
            tt.giga_count = usage.ru_utime.tv_sec + usage.ru_stime.tv_sec;
            usec = (int32_t)(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec);
            if (1000000 <= usec) {
                tt.giga_count++;
                usec -= 1000000;
            }
            tt.count = usec * 1000;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }
#endif

#ifdef HAVE_TIMES
#define RUBY_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID \
        ID2SYM(id_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID)
        if (clk_id == RUBY_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID) {
            struct tms buf;
            unsigned_clock_t utime, stime;
            if (times(&buf) ==  (clock_t)-1)
                rb_sys_fail("times");
            utime = (unsigned_clock_t)buf.tms_utime;
            stime = (unsigned_clock_t)buf.tms_stime;
            tt.count = (int32_t)((utime % 1000000000) + (stime % 1000000000));
            tt.giga_count = (utime / 1000000000) + (stime / 1000000000);
            if (1000000000 <= tt.count) {
                tt.count -= 1000000000;
                tt.giga_count++;
            }
            denominators[num_denominators++] = get_clk_tck();
            goto success;
        }
#endif

#define RUBY_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID \
        ID2SYM(id_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID)
        if (clk_id == RUBY_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID) {
            clock_t c;
            unsigned_clock_t uc;
            errno = 0;
            c = clock();
            if (c == (clock_t)-1)
                rb_sys_fail("clock");
            uc = (unsigned_clock_t)c;
            tt.count = (int32_t)(uc % 1000000000);
            tt.giga_count = uc / 1000000000;
            denominators[num_denominators++] = CLOCKS_PER_SEC;
            goto success;
        }

#ifdef __APPLE__
#define RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC ID2SYM(id_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC)
        if (clk_id == RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC) {
	    mach_timebase_info_data_t *info = get_mach_timebase_info();
            uint64_t t = mach_absolute_time();
            tt.count = (int32_t)(t % 1000000000);
            tt.giga_count = t / 1000000000;
            numerators[num_numerators++] = info->numer;
            denominators[num_denominators++] = info->denom;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }
#endif
    }
    else {
#if defined(HAVE_CLOCK_GETTIME)
        struct timespec ts;
        clockid_t c;
        c = NUM2CLOCKID(clk_id);
        ret = clock_gettime(c, &ts);
        if (ret == -1)
            rb_sys_fail("clock_gettime");
        tt.count = (int32_t)ts.tv_nsec;
        tt.giga_count = ts.tv_sec;
        denominators[num_denominators++] = 1000000000;
        goto success;
#endif
    }
    /* EINVAL emulates clock_gettime behavior when clock_id is invalid. */
    errno = EINVAL;
    rb_sys_fail(0);

  success:
    return make_clock_result(&tt, numerators, num_numerators, denominators, num_denominators, unit);
}

/*
 *  call-seq:
 *     Process.clock_getres(clock_id [, unit])   -> number
 *
 *  Returns the time resolution returned by POSIX clock_getres() function.
 *
 *  +clock_id+ specifies a kind of clock.
 *  See the document of +Process.clock_gettime+ for details.
 *
 *  +clock_id+ can be a symbol as +Process.clock_gettime+.
 *  However the result may not be accurate.
 *  For example, +Process.clock_getres(:GETTIMEOFDAY_BASED_CLOCK_REALTIME)+
 *  returns 1.0e-06 which means 1 microsecond, but actual resolution can be more coarse.
 *
 *  If the given +clock_id+ is not supported, Errno::EINVAL is raised.
 *
 *  +unit+ specifies a type of the return value.
 *  +Process.clock_getres+ accepts +unit+ as +Process.clock_gettime+.
 *  The default value, +:float_second+, is also same as
 *  +Process.clock_gettime+.
 *
 *  +Process.clock_getres+ also accepts +:hertz+ as +unit+.
 *  +:hertz+ means a the reciprocal of +:float_second+.
 *
 *  +:hertz+ can be used to obtain the exact value of
 *  the clock ticks per second for times() function and
 *  CLOCKS_PER_SEC for clock() function.
 *
 *  +Process.clock_getres(:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID, :hertz)+
 *  returns the clock ticks per second.
 *
 *  +Process.clock_getres(:CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID, :hertz)+
 *  returns CLOCKS_PER_SEC.
 *
 *    p Process.clock_getres(Process::CLOCK_MONOTONIC)
 *    #=> 1.0e-09
 *
 */
VALUE
rb_clock_getres(int argc, VALUE *argv)
{
    VALUE clk_id, unit;

    struct timetick tt;
    timetick_int_t numerators[2];
    timetick_int_t denominators[2];
    int num_numerators = 0;
    int num_denominators = 0;

    rb_scan_args(argc, argv, "11", &clk_id, &unit);

    if (SYMBOL_P(clk_id)) {
#ifdef RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME
        if (clk_id == RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME) {
            tt.giga_count = 0;
            tt.count = 1000;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }
#endif

#ifdef RUBY_TIME_BASED_CLOCK_REALTIME
        if (clk_id == RUBY_TIME_BASED_CLOCK_REALTIME) {
            tt.giga_count = 1;
            tt.count = 0;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }
#endif

#ifdef RUBY_TIMES_BASED_CLOCK_MONOTONIC
        if (clk_id == RUBY_TIMES_BASED_CLOCK_MONOTONIC) {
            tt.count = 1;
            tt.giga_count = 0;
            denominators[num_denominators++] = get_clk_tck();
            goto success;
        }
#endif

#ifdef RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID
        if (clk_id == RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID) {
            tt.giga_count = 0;
            tt.count = 1000;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }
#endif

#ifdef RUBY_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID
        if (clk_id == RUBY_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID) {
            tt.count = 1;
            tt.giga_count = 0;
            denominators[num_denominators++] = get_clk_tck();
            goto success;
        }
#endif

#ifdef RUBY_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID
        if (clk_id == RUBY_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID) {
            tt.count = 1;
            tt.giga_count = 0;
            denominators[num_denominators++] = CLOCKS_PER_SEC;
            goto success;
        }
#endif

#ifdef RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC
        if (clk_id == RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC) {
	    mach_timebase_info_data_t *info = get_mach_timebase_info();
            tt.count = 1;
            tt.giga_count = 0;
            numerators[num_numerators++] = info->numer;
            denominators[num_denominators++] = info->denom;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }
#endif
    }
    else {
#if defined(HAVE_CLOCK_GETRES)
        struct timespec ts;
        clockid_t c = NUM2CLOCKID(clk_id);
        int ret = clock_getres(c, &ts);
        if (ret == -1)
            rb_sys_fail("clock_getres");
        tt.count = (int32_t)ts.tv_nsec;
        tt.giga_count = ts.tv_sec;
        denominators[num_denominators++] = 1000000000;
        goto success;
#endif
    }
    /* EINVAL emulates clock_getres behavior when clock_id is invalid. */
    errno = EINVAL;
    rb_sys_fail(0);

  success:
    if (unit == ID2SYM(id_hertz)) {
        return timetick2dblnum_reciprocal(&tt, numerators, num_numerators, denominators, num_denominators);
    }
    else {
        return make_clock_result(&tt, numerators, num_numerators, denominators, num_denominators, unit);
    }
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
InitVM_process(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)
    rb_define_virtual_variable("$?", rb_last_status_get, 0);
    rb_define_virtual_variable("$$", get_pid, 0);
    rb_define_global_function("exec", rb_f_exec, -1);
    rb_define_global_function("fork", rb_f_fork, 0);
    rb_define_global_function("exit!", rb_f_exit_bang, -1);
    rb_define_global_function("system", rb_f_system, -1);
    rb_define_global_function("spawn", rb_f_spawn, -1);
    rb_define_global_function("sleep", rb_f_sleep, -1);
    rb_define_global_function("exit", rb_f_exit, -1);
    rb_define_global_function("abort", rb_f_abort, -1);

    rb_mProcess = rb_define_module("Process");

#ifdef WNOHANG
    /* see Process.wait */
    rb_define_const(rb_mProcess, "WNOHANG", INT2FIX(WNOHANG));
#else
    /* see Process.wait */
    rb_define_const(rb_mProcess, "WNOHANG", INT2FIX(0));
#endif
#ifdef WUNTRACED
    /* see Process.wait */
    rb_define_const(rb_mProcess, "WUNTRACED", INT2FIX(WUNTRACED));
#else
    /* see Process.wait */
    rb_define_const(rb_mProcess, "WUNTRACED", INT2FIX(0));
#endif

    rb_define_singleton_method(rb_mProcess, "exec", rb_f_exec, -1);
    rb_define_singleton_method(rb_mProcess, "fork", rb_f_fork, 0);
    rb_define_singleton_method(rb_mProcess, "spawn", rb_f_spawn, -1);
    rb_define_singleton_method(rb_mProcess, "exit!", rb_f_exit_bang, -1);
    rb_define_singleton_method(rb_mProcess, "exit", rb_f_exit, -1);
    rb_define_singleton_method(rb_mProcess, "abort", rb_f_abort, -1);

    rb_define_module_function(rb_mProcess, "kill", rb_f_kill, -1); /* in signal.c */
    rb_define_module_function(rb_mProcess, "wait", proc_wait, -1);
    rb_define_module_function(rb_mProcess, "wait2", proc_wait2, -1);
    rb_define_module_function(rb_mProcess, "waitpid", proc_wait, -1);
    rb_define_module_function(rb_mProcess, "waitpid2", proc_wait2, -1);
    rb_define_module_function(rb_mProcess, "waitall", proc_waitall, 0);
    rb_define_module_function(rb_mProcess, "detach", proc_detach, 1);

    rb_cWaiter = rb_define_class_under(rb_mProcess, "Waiter", rb_cThread);
    rb_undef_alloc_func(rb_cWaiter);
    rb_undef_method(CLASS_OF(rb_cWaiter), "new");
    rb_define_method(rb_cWaiter, "pid", detach_process_pid, 0);

    rb_cProcessStatus = rb_define_class_under(rb_mProcess, "Status", rb_cObject);
    rb_undef_method(CLASS_OF(rb_cProcessStatus), "new");

    rb_define_method(rb_cProcessStatus, "==", pst_equal, 1);
    rb_define_method(rb_cProcessStatus, "&", pst_bitand, 1);
    rb_define_method(rb_cProcessStatus, ">>", pst_rshift, 1);
    rb_define_method(rb_cProcessStatus, "to_i", pst_to_i, 0);
    rb_define_method(rb_cProcessStatus, "to_s", pst_to_s, 0);
    rb_define_method(rb_cProcessStatus, "inspect", pst_inspect, 0);

    rb_define_method(rb_cProcessStatus, "pid", pst_pid, 0);

    rb_define_method(rb_cProcessStatus, "stopped?", pst_wifstopped, 0);
    rb_define_method(rb_cProcessStatus, "stopsig", pst_wstopsig, 0);
    rb_define_method(rb_cProcessStatus, "signaled?", pst_wifsignaled, 0);
    rb_define_method(rb_cProcessStatus, "termsig", pst_wtermsig, 0);
    rb_define_method(rb_cProcessStatus, "exited?", pst_wifexited, 0);
    rb_define_method(rb_cProcessStatus, "exitstatus", pst_wexitstatus, 0);
    rb_define_method(rb_cProcessStatus, "success?", pst_success_p, 0);
    rb_define_method(rb_cProcessStatus, "coredump?", pst_wcoredump, 0);

    rb_define_module_function(rb_mProcess, "pid", get_pid, 0);
    rb_define_module_function(rb_mProcess, "ppid", get_ppid, 0);

    rb_define_module_function(rb_mProcess, "getpgrp", proc_getpgrp, 0);
    rb_define_module_function(rb_mProcess, "setpgrp", proc_setpgrp, 0);
    rb_define_module_function(rb_mProcess, "getpgid", proc_getpgid, 1);
    rb_define_module_function(rb_mProcess, "setpgid", proc_setpgid, 2);

    rb_define_module_function(rb_mProcess, "getsid", proc_getsid, -1);
    rb_define_module_function(rb_mProcess, "setsid", proc_setsid, 0);

    rb_define_module_function(rb_mProcess, "getpriority", proc_getpriority, 2);
    rb_define_module_function(rb_mProcess, "setpriority", proc_setpriority, 3);

#ifdef HAVE_GETPRIORITY
    /* see Process.setpriority */
    rb_define_const(rb_mProcess, "PRIO_PROCESS", INT2FIX(PRIO_PROCESS));
    /* see Process.setpriority */
    rb_define_const(rb_mProcess, "PRIO_PGRP", INT2FIX(PRIO_PGRP));
    /* see Process.setpriority */
    rb_define_const(rb_mProcess, "PRIO_USER", INT2FIX(PRIO_USER));
#endif

    rb_define_module_function(rb_mProcess, "getrlimit", proc_getrlimit, 1);
    rb_define_module_function(rb_mProcess, "setrlimit", proc_setrlimit, -1);
#if defined(RLIM2NUM) && defined(RLIM_INFINITY)
    {
        VALUE inf = RLIM2NUM(RLIM_INFINITY);
#ifdef RLIM_SAVED_MAX
	{
	    VALUE v = RLIM_INFINITY == RLIM_SAVED_MAX ? inf : RLIM2NUM(RLIM_SAVED_MAX);
	    /* see Process.setrlimit */
	    rb_define_const(rb_mProcess, "RLIM_SAVED_MAX", v);
	}
#endif
	/* see Process.setrlimit */
        rb_define_const(rb_mProcess, "RLIM_INFINITY", inf);
#ifdef RLIM_SAVED_CUR
	{
	    VALUE v = RLIM_INFINITY == RLIM_SAVED_CUR ? inf : RLIM2NUM(RLIM_SAVED_CUR);
	    /* see Process.setrlimit */
	    rb_define_const(rb_mProcess, "RLIM_SAVED_CUR", v);
	}
#endif
    }
#ifdef RLIMIT_AS
    /* Maximum size of the process's virtual memory (address space) in bytes.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_AS", INT2FIX(RLIMIT_AS));
#endif
#ifdef RLIMIT_CORE
    /* Maximum size of the core file.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_CORE", INT2FIX(RLIMIT_CORE));
#endif
#ifdef RLIMIT_CPU
    /* CPU time limit in seconds.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_CPU", INT2FIX(RLIMIT_CPU));
#endif
#ifdef RLIMIT_DATA
    /* Maximum size of the process's data segment.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_DATA", INT2FIX(RLIMIT_DATA));
#endif
#ifdef RLIMIT_FSIZE
    /* Maximum size of files that the process may create.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_FSIZE", INT2FIX(RLIMIT_FSIZE));
#endif
#ifdef RLIMIT_MEMLOCK
    /* Maximum number of bytes of memory that may be locked into RAM.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_MEMLOCK", INT2FIX(RLIMIT_MEMLOCK));
#endif
#ifdef RLIMIT_MSGQUEUE
    /* Specifies the limit on the number of bytes that can be allocated
     * for POSIX message queues for the real user ID of the calling process.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_MSGQUEUE", INT2FIX(RLIMIT_MSGQUEUE));
#endif
#ifdef RLIMIT_NICE
    /* Specifies a ceiling to which the process's nice value can be raised.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_NICE", INT2FIX(RLIMIT_NICE));
#endif
#ifdef RLIMIT_NOFILE
    /* Specifies a value one greater than the maximum file descriptor
     * number that can be opened by this process.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_NOFILE", INT2FIX(RLIMIT_NOFILE));
#endif
#ifdef RLIMIT_NPROC
    /* The maximum number of processes that can be created for the
     * real user ID of the calling process.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_NPROC", INT2FIX(RLIMIT_NPROC));
#endif
#ifdef RLIMIT_RSS
    /* Specifies the limit (in pages) of the process's resident set.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_RSS", INT2FIX(RLIMIT_RSS));
#endif
#ifdef RLIMIT_RTPRIO
    /* Specifies a ceiling on the real-time priority that may be set for this process.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_RTPRIO", INT2FIX(RLIMIT_RTPRIO));
#endif
#ifdef RLIMIT_RTTIME
    /* Specifies limit on CPU time this process scheduled under a real-time
     * scheduling policy can consume.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_RTTIME", INT2FIX(RLIMIT_RTTIME));
#endif
#ifdef RLIMIT_SBSIZE
    /* Maximum size of the socket buffer.
     */
    rb_define_const(rb_mProcess, "RLIMIT_SBSIZE", INT2FIX(RLIMIT_SBSIZE));
#endif
#ifdef RLIMIT_SIGPENDING
    /* Specifies a limit on the number of signals that may be queued for
     * the real user ID of the calling process.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_SIGPENDING", INT2FIX(RLIMIT_SIGPENDING));
#endif
#ifdef RLIMIT_STACK
    /* Maximum size of the stack, in bytes.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_STACK", INT2FIX(RLIMIT_STACK));
#endif
#endif

    rb_define_module_function(rb_mProcess, "uid", proc_getuid, 0);
    rb_define_module_function(rb_mProcess, "uid=", proc_setuid, 1);
    rb_define_module_function(rb_mProcess, "gid", proc_getgid, 0);
    rb_define_module_function(rb_mProcess, "gid=", proc_setgid, 1);
    rb_define_module_function(rb_mProcess, "euid", proc_geteuid, 0);
    rb_define_module_function(rb_mProcess, "euid=", proc_seteuid_m, 1);
    rb_define_module_function(rb_mProcess, "egid", proc_getegid, 0);
    rb_define_module_function(rb_mProcess, "egid=", proc_setegid_m, 1);
    rb_define_module_function(rb_mProcess, "initgroups", proc_initgroups, 2);
    rb_define_module_function(rb_mProcess, "groups", proc_getgroups, 0);
    rb_define_module_function(rb_mProcess, "groups=", proc_setgroups, 1);
    rb_define_module_function(rb_mProcess, "maxgroups", proc_getmaxgroups, 0);
    rb_define_module_function(rb_mProcess, "maxgroups=", proc_setmaxgroups, 1);

    rb_define_module_function(rb_mProcess, "daemon", proc_daemon, -1);

    rb_define_module_function(rb_mProcess, "times", rb_proc_times, 0);

#ifdef CLOCK_REALTIME
    rb_define_const(rb_mProcess, "CLOCK_REALTIME", CLOCKID2NUM(CLOCK_REALTIME));
#elif defined(RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME)
    rb_define_const(rb_mProcess, "CLOCK_REALTIME", RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME);
#endif
#ifdef CLOCK_MONOTONIC
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC", CLOCKID2NUM(CLOCK_MONOTONIC));
#elif defined(RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC)
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC", RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC);
#endif
#ifdef CLOCK_PROCESS_CPUTIME_ID
    rb_define_const(rb_mProcess, "CLOCK_PROCESS_CPUTIME_ID", CLOCKID2NUM(CLOCK_PROCESS_CPUTIME_ID));
#elif defined(RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID)
    rb_define_const(rb_mProcess, "CLOCK_PROCESS_CPUTIME_ID", RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID);
#endif
#ifdef CLOCK_THREAD_CPUTIME_ID
    rb_define_const(rb_mProcess, "CLOCK_THREAD_CPUTIME_ID", CLOCKID2NUM(CLOCK_THREAD_CPUTIME_ID));
#endif
#ifdef CLOCK_VIRTUAL
    rb_define_const(rb_mProcess, "CLOCK_VIRTUAL", CLOCKID2NUM(CLOCK_VIRTUAL));
#endif
#ifdef CLOCK_PROF
    rb_define_const(rb_mProcess, "CLOCK_PROF", CLOCKID2NUM(CLOCK_PROF));
#endif
#ifdef CLOCK_REALTIME_FAST
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_FAST", CLOCKID2NUM(CLOCK_REALTIME_FAST));
#endif
#ifdef CLOCK_REALTIME_PRECISE
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_PRECISE", CLOCKID2NUM(CLOCK_REALTIME_PRECISE));
#endif
#ifdef CLOCK_REALTIME_COARSE
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_COARSE", CLOCKID2NUM(CLOCK_REALTIME_COARSE));
#endif
#ifdef CLOCK_REALTIME_ALARM
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_ALARM", CLOCKID2NUM(CLOCK_REALTIME_ALARM));
#endif
#ifdef CLOCK_MONOTONIC_FAST
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_FAST", CLOCKID2NUM(CLOCK_MONOTONIC_FAST));
#endif
#ifdef CLOCK_MONOTONIC_PRECISE
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_PRECISE", CLOCKID2NUM(CLOCK_MONOTONIC_PRECISE));
#endif
#ifdef CLOCK_MONOTONIC_RAW
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_RAW", CLOCKID2NUM(CLOCK_MONOTONIC_RAW));
#endif
#ifdef CLOCK_MONOTONIC_COARSE
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_COARSE", CLOCKID2NUM(CLOCK_MONOTONIC_COARSE));
#endif
#ifdef CLOCK_BOOTTIME
    rb_define_const(rb_mProcess, "CLOCK_BOOTTIME", CLOCKID2NUM(CLOCK_BOOTTIME));
#endif
#ifdef CLOCK_BOOTTIME_ALARM
    rb_define_const(rb_mProcess, "CLOCK_BOOTTIME_ALARM", CLOCKID2NUM(CLOCK_BOOTTIME_ALARM));
#endif
#ifdef CLOCK_UPTIME
    rb_define_const(rb_mProcess, "CLOCK_UPTIME", CLOCKID2NUM(CLOCK_UPTIME));
#endif
#ifdef CLOCK_UPTIME_FAST
    rb_define_const(rb_mProcess, "CLOCK_UPTIME_FAST", CLOCKID2NUM(CLOCK_UPTIME_FAST));
#endif
#ifdef CLOCK_UPTIME_PRECISE
    rb_define_const(rb_mProcess, "CLOCK_UPTIME_PRECISE", CLOCKID2NUM(CLOCK_UPTIME_PRECISE));
#endif
#ifdef CLOCK_SECOND
    rb_define_const(rb_mProcess, "CLOCK_SECOND", CLOCKID2NUM(CLOCK_SECOND));
#endif
    rb_define_module_function(rb_mProcess, "clock_gettime", rb_clock_gettime, -1);
    rb_define_module_function(rb_mProcess, "clock_getres", rb_clock_getres, -1);

#if defined(HAVE_TIMES) || defined(_WIN32)
    rb_cProcessTms = rb_struct_define_under(rb_mProcess, "Tms", "utime", "stime", "cutime", "cstime", NULL);
    rb_define_const(rb_cStruct, "Tms", rb_cProcessTms); /* for the backward compatibility */
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
#ifdef p_uid_from_name
    rb_define_module_function(rb_mProcUID, "from_name", p_uid_from_name, 1);
#endif
#ifdef p_gid_from_name
    rb_define_module_function(rb_mProcGID, "from_name", p_gid_from_name, 1);
#endif

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

void
Init_process(void)
{
    id_in = rb_intern("in");
    id_out = rb_intern("out");
    id_err = rb_intern("err");
    id_pid = rb_intern("pid");
    id_uid = rb_intern("uid");
    id_gid = rb_intern("gid");
    id_close = rb_intern("close");
    id_child = rb_intern("child");
    id_status = rb_intern("status");
#ifdef HAVE_SETPGID
    id_pgroup = rb_intern("pgroup");
#endif
#ifdef _WIN32
    id_new_pgroup = rb_intern("new_pgroup");
#endif
    id_unsetenv_others = rb_intern("unsetenv_others");
    id_chdir = rb_intern("chdir");
    id_umask = rb_intern("umask");
    id_close_others = rb_intern("close_others");
    id_ENV = rb_intern("ENV");
    id_nanosecond = rb_intern("nanosecond");
    id_microsecond = rb_intern("microsecond");
    id_millisecond = rb_intern("millisecond");
    id_second = rb_intern("second");
    id_float_microsecond = rb_intern("float_microsecond");
    id_float_millisecond = rb_intern("float_millisecond");
    id_float_second = rb_intern("float_second");
    id_GETTIMEOFDAY_BASED_CLOCK_REALTIME = rb_intern("GETTIMEOFDAY_BASED_CLOCK_REALTIME");
    id_TIME_BASED_CLOCK_REALTIME = rb_intern("TIME_BASED_CLOCK_REALTIME");
#ifdef HAVE_TIMES
    id_TIMES_BASED_CLOCK_MONOTONIC = rb_intern("TIMES_BASED_CLOCK_MONOTONIC");
    id_TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID = rb_intern("TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID");
#endif
#ifdef RUSAGE_SELF
    id_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID = rb_intern("GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID");
#endif
    id_CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID = rb_intern("CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID");
#ifdef __APPLE__
    id_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC = rb_intern("MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC");
#endif
    id_hertz = rb_intern("hertz");

    InitVM(process);
}
