/**********************************************************************

  process.c -

  $Author$
  created at: Tue Aug 10 14:30:50 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#include "ruby/fiber/scheduler.h"

#include <ctype.h>
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <time.h>

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifdef HAVE_FCNTL_H
# include <fcntl.h>
#endif

#ifdef HAVE_PROCESS_H
# include <process.h>
#endif

#ifndef EXIT_SUCCESS
# define EXIT_SUCCESS 0
#endif

#ifndef EXIT_FAILURE
# define EXIT_FAILURE 1
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

#include <sys/stat.h>

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#endif

#ifdef HAVE_SYS_TIMES_H
# include <sys/times.h>
#endif

#ifdef HAVE_PWD_H
# include <pwd.h>
#endif

#ifdef HAVE_GRP_H
# include <grp.h>
# ifdef __CYGWIN__
int initgroups(const char *, rb_gid_t);
# endif
#endif

#ifdef HAVE_SYS_ID_H
# include <sys/id.h>
#endif

#ifdef __APPLE__
# include <mach/mach_time.h>
#endif

#include "dln.h"
#include "hrtime.h"
#include "internal.h"
#include "internal/bits.h"
#include "internal/dir.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/hash.h"
#include "internal/io.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/process.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "internal/warnings.h"
#include "rjit.h"
#include "ruby/io.h"
#include "ruby/st.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "vm_core.h"
#include "vm_sync.h"
#include "ruby/ractor.h"

/* define system APIs */
#ifdef _WIN32
#undef open
#define open	rb_w32_uopen
#endif

#if defined(HAVE_TIMES) || defined(_WIN32)
/*********************************************************************
 *
 * Document-class: Process::Tms
 *
 * Placeholder for rusage
 */
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

static void check_uid_switch(void);
static void check_gid_switch(void);
static int exec_async_signal_safe(const struct rb_execarg *, char *, size_t);

VALUE rb_envtbl(void);
VALUE rb_env_to_hash(void);

#if 1
#define p_uid_from_name p_uid_from_name
#define p_gid_from_name p_gid_from_name
#endif

#if defined(HAVE_UNISTD_H)
# if defined(HAVE_GETLOGIN_R)
#  define USE_GETLOGIN_R 1
#  define GETLOGIN_R_SIZE_DEFAULT   0x100
#  define GETLOGIN_R_SIZE_LIMIT    0x1000
#  if defined(_SC_LOGIN_NAME_MAX)
#    define GETLOGIN_R_SIZE_INIT sysconf(_SC_LOGIN_NAME_MAX)
#  else
#    define GETLOGIN_R_SIZE_INIT GETLOGIN_R_SIZE_DEFAULT
#  endif
# elif defined(HAVE_GETLOGIN)
#  define USE_GETLOGIN 1
# endif
#endif

#if defined(HAVE_PWD_H)
# if defined(HAVE_GETPWUID_R)
#  define USE_GETPWUID_R 1
# elif defined(HAVE_GETPWUID)
#  define USE_GETPWUID 1
# endif
# if defined(HAVE_GETPWNAM_R)
#  define USE_GETPWNAM_R 1
# elif defined(HAVE_GETPWNAM)
#  define USE_GETPWNAM 1
# endif
# if defined(HAVE_GETPWNAM_R) || defined(HAVE_GETPWUID_R)
#  define GETPW_R_SIZE_DEFAULT 0x1000
#  define GETPW_R_SIZE_LIMIT  0x10000
#  if defined(_SC_GETPW_R_SIZE_MAX)
#   define GETPW_R_SIZE_INIT sysconf(_SC_GETPW_R_SIZE_MAX)
#  else
#   define GETPW_R_SIZE_INIT GETPW_R_SIZE_DEFAULT
#  endif
# endif
# ifdef USE_GETPWNAM_R
#   define PREPARE_GETPWNAM \
    VALUE getpw_buf = 0
#   define FINISH_GETPWNAM \
    (getpw_buf ? (void)rb_str_resize(getpw_buf, 0) : (void)0)
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
    (getgr_buf ? (void)rb_str_resize(getgr_buf, 0) : (void)0)
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
#ifndef HAVE_SIG_T
typedef void (*sig_t) (int);
#endif

#define id_exception idException
static ID id_in, id_out, id_err, id_pid, id_uid, id_gid;
static ID id_close, id_child;
#ifdef HAVE_SETPGID
static ID id_pgroup;
#endif
#ifdef _WIN32
static ID id_new_pgroup;
#endif
static ID id_unsetenv_others, id_chdir, id_umask, id_close_others;
static ID id_nanosecond, id_microsecond, id_millisecond, id_second;
static ID id_float_microsecond, id_float_millisecond, id_float_second;
static ID id_GETTIMEOFDAY_BASED_CLOCK_REALTIME, id_TIME_BASED_CLOCK_REALTIME;
#ifdef CLOCK_REALTIME
static ID id_CLOCK_REALTIME;
# define RUBY_CLOCK_REALTIME ID2SYM(id_CLOCK_REALTIME)
#endif
#ifdef CLOCK_MONOTONIC
static ID id_CLOCK_MONOTONIC;
# define RUBY_CLOCK_MONOTONIC ID2SYM(id_CLOCK_MONOTONIC)
#endif
#ifdef CLOCK_PROCESS_CPUTIME_ID
static ID id_CLOCK_PROCESS_CPUTIME_ID;
# define RUBY_CLOCK_PROCESS_CPUTIME_ID ID2SYM(id_CLOCK_PROCESS_CPUTIME_ID)
#endif
#ifdef CLOCK_THREAD_CPUTIME_ID
static ID id_CLOCK_THREAD_CPUTIME_ID;
# define RUBY_CLOCK_THREAD_CPUTIME_ID ID2SYM(id_CLOCK_THREAD_CPUTIME_ID)
#endif
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
# define RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC ID2SYM(id_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC)
#endif
static ID id_hertz;

static rb_pid_t cached_pid;

/* execv and execl are async-signal-safe since SUSv4 (POSIX.1-2008, XPG7) */
#if defined(__sun) && !defined(_XPG7) /* Solaris 10, 9, ... */
#define execv(path, argv) (rb_async_bug_errno("unreachable: async-signal-unsafe execv() is called", 0))
#define execl(path, arg0, arg1, arg2, term) do { extern char **environ; execle((path), (arg0), (arg1), (arg2), (term), (environ)); } while (0)
#define ALWAYS_NEED_ENVP 1
#else
#define ALWAYS_NEED_ENVP 0
#endif

static void
assert_close_on_exec(int fd)
{
#if VM_CHECK_MODE > 0
#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(FD_CLOEXEC)
    int flags = fcntl(fd, F_GETFD);
    if (flags == -1) {
        static const char m[] = "reserved FD closed unexpectedly?\n";
        (void)!write(2, m, sizeof(m) - 1);
        return;
    }
    if (flags & FD_CLOEXEC) return;
    rb_bug("reserved FD did not have close-on-exec set");
#else
    rb_bug("reserved FD without close-on-exec support");
#endif /* FD_CLOEXEC */
#endif /* VM_CHECK_MODE */
}

static inline int
close_unless_reserved(int fd)
{
    if (rb_reserved_fd_p(fd)) { /* async-signal-safe */
        assert_close_on_exec(fd);
        return 0;
    }
    return close(fd); /* async-signal-safe */
}

/*#define DEBUG_REDIRECT*/
#if defined(DEBUG_REDIRECT)

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
    ttyprintf("dup2(%d, %d) => %d\n", oldfd, newfd, ret);
    return ret;
}

static int
redirect_cloexec_dup(int oldfd)
{
    int ret;
    ret = rb_cloexec_dup(oldfd);
    ttyprintf("cloexec_dup(%d) => %d\n", oldfd, ret);
    return ret;
}

static int
redirect_cloexec_dup2(int oldfd, int newfd)
{
    int ret;
    ret = rb_cloexec_dup2(oldfd, newfd);
    ttyprintf("cloexec_dup2(%d, %d) => %d\n", oldfd, newfd, ret);
    return ret;
}

static int
redirect_close(int fd)
{
    int ret;
    ret = close_unless_reserved(fd);
    ttyprintf("close(%d) => %d\n", fd, ret);
    return ret;
}

static int
parent_redirect_open(const char *pathname, int flags, mode_t perm)
{
    int ret;
    ret = rb_cloexec_open(pathname, flags, perm);
    ttyprintf("parent_open(\"%s\", 0x%x, 0%o) => %d\n", pathname, flags, perm, ret);
    return ret;
}

static int
parent_redirect_close(int fd)
{
    int ret;
    ret = close_unless_reserved(fd);
    ttyprintf("parent_close(%d) => %d\n", fd, ret);
    return ret;
}

#else
#define redirect_dup(oldfd) dup(oldfd)
#define redirect_dup2(oldfd, newfd) dup2((oldfd), (newfd))
#define redirect_cloexec_dup(oldfd) rb_cloexec_dup(oldfd)
#define redirect_cloexec_dup2(oldfd, newfd) rb_cloexec_dup2((oldfd), (newfd))
#define redirect_close(fd) close_unless_reserved(fd)
#define parent_redirect_open(pathname, flags, perm) rb_cloexec_open((pathname), (flags), (perm))
#define parent_redirect_close(fd) close_unless_reserved(fd)
#endif

static VALUE
get_pid(void)
{
    if (UNLIKELY(!cached_pid)) { /* 0 is not a valid pid */
        cached_pid = getpid();
    }
    /* pid should be likely POSFIXABLE() */
    return PIDT2NUM(cached_pid);
}

#if defined HAVE_WORKING_FORK || defined HAVE_DAEMON
static void
clear_pid_cache(void)
{
    cached_pid = 0;
}
#endif

/*
 *  call-seq:
 *    Process.pid -> integer
 *
 *  Returns the process ID of the current process:
 *
 *    Process.pid # => 15668
 *
 */

static VALUE
proc_get_pid(VALUE _)
{
    return get_pid();
}

static VALUE
get_ppid(void)
{
    return PIDT2NUM(getppid());
}

/*
 *  call-seq:
 *    Process.ppid -> integer
 *
 *  Returns the process ID of the parent of the current process:
 *
 *    puts "Pid is #{Process.pid}."
 *    fork { puts "Parent pid is #{Process.ppid}." }
 *
 *  Output:
 *
 *    Pid is 271290.
 *    Parent pid is 271290.
 *
 *  May not return a trustworthy value on certain platforms.
 */

static VALUE
proc_get_ppid(VALUE _)
{
    return get_ppid();
}


/*********************************************************************
 *
 * Document-class: Process::Status
 *
 *  A Process::Status contains information about a system process.
 *
 *  Thread-local variable <tt>$?</tt> is initially +nil+.
 *  Some methods assign to it a Process::Status object
 *  that represents a system process (either running or terminated):
 *
 *    `ruby -e "exit 99"`
 *    stat = $?       # => #<Process::Status: pid 1262862 exit 99>
 *    stat.class      # => Process::Status
 *    stat.to_i       # => 25344
 *    stat.stopped?   # => false
 *    stat.exited?    # => true
 *    stat.exitstatus # => 99
 *
 */

static VALUE rb_cProcessStatus;

struct rb_process_status {
    rb_pid_t pid;
    int status;
    int error;
};

static const rb_data_type_t rb_process_status_type = {
    .wrap_struct_name = "Process::Status",
    .function = {
        .dmark = NULL,
        .dfree = RUBY_DEFAULT_FREE,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE,
};

static VALUE
rb_process_status_allocate(VALUE klass)
{
    struct rb_process_status *data;
    return TypedData_Make_Struct(klass, struct rb_process_status, &rb_process_status_type, data);
}

VALUE
rb_last_status_get(void)
{
    return GET_THREAD()->last_status;
}

/*
 *  call-seq:
 *    Process.last_status -> Process::Status or nil
 *
 *  Returns a Process::Status object representing the most recently exited
 *  child process in the current thread, or +nil+ if none:
 *
 *    Process.spawn('ruby', '-e', 'exit 13')
 *    Process.wait
 *    Process.last_status # => #<Process::Status: pid 14396 exit 13>
 *
 *    Process.spawn('ruby', '-e', 'exit 14')
 *    Process.wait
 *    Process.last_status # => #<Process::Status: pid 4692 exit 14>
 *
 *    Process.spawn('ruby', '-e', 'exit 15')
 *    # 'exit 15' has not been reaped by #wait.
 *    Process.last_status # => #<Process::Status: pid 4692 exit 14>
 *    Process.wait
 *    Process.last_status # => #<Process::Status: pid 1380 exit 15>
 *
 */
static VALUE
proc_s_last_status(VALUE mod)
{
    return rb_last_status_get();
}

VALUE
rb_process_status_new(rb_pid_t pid, int status, int error)
{
    VALUE last_status = rb_process_status_allocate(rb_cProcessStatus);
    struct rb_process_status *data = RTYPEDDATA_GET_DATA(last_status);
    data->pid = pid;
    data->status = status;
    data->error = error;

    rb_obj_freeze(last_status);
    return last_status;
}

static VALUE
process_status_dump(VALUE status)
{
    VALUE dump = rb_class_new_instance(0, 0, rb_cObject);
    struct rb_process_status *data;
    TypedData_Get_Struct(status, struct rb_process_status, &rb_process_status_type, data);
    if (data->pid) {
        rb_ivar_set(dump, id_status, INT2NUM(data->status));
        rb_ivar_set(dump, id_pid, PIDT2NUM(data->pid));
    }
    return dump;
}

static VALUE
process_status_load(VALUE real_obj, VALUE load_obj)
{
    struct rb_process_status *data = rb_check_typeddata(real_obj, &rb_process_status_type);
    VALUE status = rb_attr_get(load_obj, id_status);
    VALUE pid = rb_attr_get(load_obj, id_pid);
    data->pid = NIL_P(pid) ? 0 : NUM2PIDT(pid);
    data->status = NIL_P(status) ? 0 : NUM2INT(status);
    return real_obj;
}

void
rb_last_status_set(int status, rb_pid_t pid)
{
    GET_THREAD()->last_status = rb_process_status_new(pid, status, 0);
}

static void
last_status_clear(rb_thread_t *th)
{
    th->last_status = Qnil;
}

void
rb_last_status_clear(void)
{
    last_status_clear(GET_THREAD());
}

static rb_pid_t
pst_pid(VALUE status)
{
    struct rb_process_status *data;
    TypedData_Get_Struct(status, struct rb_process_status, &rb_process_status_type, data);
    return data->pid;
}

static int
pst_status(VALUE status)
{
    struct rb_process_status *data;
    TypedData_Get_Struct(status, struct rb_process_status, &rb_process_status_type, data);
    return data->status;
}

/*
 *  call-seq:
 *    to_i     -> integer
 *
 *  Returns the system-dependent integer status of +self+:
 *
 *    `cat /nop`
 *    $?.to_i # => 256
 */

static VALUE
pst_to_i(VALUE self)
{
    int status = pst_status(self);
    return RB_INT2NUM(status);
}

#define PST2INT(st) pst_status(st)

/*
 *  call-seq:
 *    pid -> integer
 *
 *  Returns the process ID of the process:
 *
 *    system("false")
 *    $?.pid # => 1247002
 *
 */

static VALUE
pst_pid_m(VALUE self)
{
    rb_pid_t pid = pst_pid(self);
    return PIDT2NUM(pid);
}

static VALUE pst_message_status(VALUE str, int status);

static void
pst_message(VALUE str, rb_pid_t pid, int status)
{
    rb_str_catf(str, "pid %ld", (long)pid);
    pst_message_status(str, status);
}

static VALUE
pst_message_status(VALUE str, int status)
{
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
    return str;
}


/*
 *  call-seq:
 *    to_s -> string
 *
 *  Returns a string representation of +self+:
 *
 *    `cat /nop`
 *    $?.to_s # => "pid 1262141 exit 1"
 *
 *
 */

static VALUE
pst_to_s(VALUE st)
{
    rb_pid_t pid;
    int status;
    VALUE str;

    pid = pst_pid(st);
    status = PST2INT(st);

    str = rb_str_buf_new(0);
    pst_message(str, pid, status);
    return str;
}


/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a string representation of +self+:
 *
 *    system("false")
 *    $?.inspect # => "#<Process::Status: pid 1303494 exit 1>"
 *
 */

static VALUE
pst_inspect(VALUE st)
{
    rb_pid_t pid;
    int status;
    VALUE str;

    pid = pst_pid(st);
    if (!pid) {
        return rb_sprintf("#<%s: uninitialized>", rb_class2name(CLASS_OF(st)));
    }
    status = PST2INT(st);

    str = rb_sprintf("#<%s: ", rb_class2name(CLASS_OF(st)));
    pst_message(str, pid, status);
    rb_str_cat2(str, ">");
    return str;
}


/*
 *  call-seq:
 *    stat == other -> true or false
 *
 *  Returns whether the value of #to_i == +other+:
 *
 *    `cat /nop`
 *    stat = $?                # => #<Process::Status: pid 1170366 exit 1>
 *    sprintf('%x', stat.to_i) # => "100"
 *    stat == 0x100            # => true
 *
 */

static VALUE
pst_equal(VALUE st1, VALUE st2)
{
    if (st1 == st2) return Qtrue;
    return rb_equal(pst_to_i(st1), st2);
}


/*
 *  call-seq:
 *    stat & mask -> integer
 *
 *  This method is deprecated as #to_i value is system-specific; use
 *  predicate methods like #exited? or #stopped?, or getters like #exitstatus
 *  or #stopsig.
 *
 *  Returns the logical AND of the value of #to_i with +mask+:
 *
 *    `cat /nop`
 *    stat = $?                 # => #<Process::Status: pid 1155508 exit 1>
 *    sprintf('%x', stat.to_i)  # => "100"
 *    stat & 0x00               # => 0
 *
 *  ArgumentError is raised if +mask+ is negative.
 */

static VALUE
pst_bitand(VALUE st1, VALUE st2)
{
    int status = PST2INT(st1);
    int mask = NUM2INT(st2);

    if (mask < 0) {
        rb_raise(rb_eArgError, "negative mask value: %d", mask);
    }
#define WARN_SUGGEST(suggest) \
    rb_warn_deprecated_to_remove_at(3.5, "Process::Status#&", suggest)

    switch (mask) {
      case 0x80:
        WARN_SUGGEST("Process::Status#coredump?");
        break;
      case 0x7f:
        WARN_SUGGEST("Process::Status#signaled? or Process::Status#termsig");
        break;
      case 0xff:
        WARN_SUGGEST("Process::Status#exited?, Process::Status#stopped? or Process::Status#coredump?");
        break;
      case 0xff00:
        WARN_SUGGEST("Process::Status#exitstatus or Process::Status#stopsig");
        break;
      default:
        WARN_SUGGEST("other Process::Status predicates");
        break;
    }
#undef WARN_SUGGEST
    status &= mask;

    return INT2NUM(status);
}


/*
 *  call-seq:
 *    stat >> places -> integer
 *
 *  This method is deprecated as #to_i value is system-specific; use
 *  predicate methods like #exited? or #stopped?, or getters like #exitstatus
 *  or #stopsig.
 *
 *  Returns the value of #to_i, shifted +places+ to the right:
 *
 *     `cat /nop`
 *     stat = $?                 # => #<Process::Status: pid 1155508 exit 1>
 *     stat.to_i                 # => 256
 *     stat >> 1                 # => 128
 *     stat >> 2                 # => 64
 *
 *  ArgumentError is raised if +places+ is negative.
 */

static VALUE
pst_rshift(VALUE st1, VALUE st2)
{
    int status = PST2INT(st1);
    int places = NUM2INT(st2);

    if (places < 0) {
        rb_raise(rb_eArgError, "negative shift value: %d", places);
    }
#define WARN_SUGGEST(suggest) \
    rb_warn_deprecated_to_remove_at(3.5, "Process::Status#>>", suggest)

    switch (places) {
      case 7:
        WARN_SUGGEST("Process::Status#coredump?");
        break;
      case 8:
        WARN_SUGGEST("Process::Status#exitstatus or Process::Status#stopsig");
        break;
      default:
        WARN_SUGGEST("other Process::Status attributes");
        break;
    }
#undef WARN_SUGGEST
    status >>= places;

    return INT2NUM(status);
}


/*
 *  call-seq:
 *    stopped? -> true or false
 *
 *  Returns +true+ if this process is stopped,
 *  and if the corresponding #wait call had the Process::WUNTRACED flag set,
 *  +false+ otherwise.
 */

static VALUE
pst_wifstopped(VALUE st)
{
    int status = PST2INT(st);

    return RBOOL(WIFSTOPPED(status));
}


/*
 *  call-seq:
 *    stopsig -> integer or nil
 *
 *  Returns the number of the signal that caused the process to stop,
 *  or +nil+ if the process is not stopped.
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
 *    signaled? -> true or false
 *
 *  Returns +true+ if the process terminated because of an uncaught signal,
 *  +false+ otherwise.
 */

static VALUE
pst_wifsignaled(VALUE st)
{
    int status = PST2INT(st);

    return RBOOL(WIFSIGNALED(status));
}


/*
 *  call-seq:
 *    termsig -> integer or nil
 *
 *  Returns the number of the signal that caused the process to terminate
 *  or +nil+ if the process was not terminated by an uncaught signal.
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
 *    exited? -> true or false
 *
 *  Returns +true+ if the process exited normally
 *  (for example using an <code>exit()</code> call or finishing the
 *  program), +false+ if not.
 */

static VALUE
pst_wifexited(VALUE st)
{
    int status = PST2INT(st);

    return RBOOL(WIFEXITED(status));
}


/*
 *  call-seq:
 *    exitstatus -> integer or nil
 *
 *  Returns the least significant eight bits of the return code
 *  of the process if it has exited;
 *  +nil+ otherwise:
 *
 *    `exit 99`
 *    $?.exitstatus # => 99
 *
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
 *    success? -> true, false, or nil
 *
 *  Returns:
 *
 *  - +true+ if the process has completed successfully and exited.
 *  - +false+ if the process has completed unsuccessfully and exited.
 *  - +nil+ if the process has not exited.
 *
 */

static VALUE
pst_success_p(VALUE st)
{
    int status = PST2INT(st);

    if (!WIFEXITED(status))
        return Qnil;
    return RBOOL(WEXITSTATUS(status) == EXIT_SUCCESS);
}


/*
 *  call-seq:
 *    coredump? -> true or false
 *
 *  Returns +true+ if the process generated a coredump
 *  when it terminated, +false+ if not.
 *
 *  Not available on all platforms.
 */

static VALUE
pst_wcoredump(VALUE st)
{
#ifdef WCOREDUMP
    int status = PST2INT(st);

    return RBOOL(WCOREDUMP(status));
#else
    return Qfalse;
#endif
}

static rb_pid_t
do_waitpid(rb_pid_t pid, int *st, int flags)
{
#if defined HAVE_WAITPID
    return waitpid(pid, st, flags);
#elif defined HAVE_WAIT4
    return wait4(pid, st, flags, NULL);
#else
#  error waitpid or wait4 is required.
#endif
}

struct waitpid_state {
    struct ccan_list_node wnode;
    rb_execution_context_t *ec;
    rb_nativethread_cond_t *cond;
    rb_pid_t ret;
    rb_pid_t pid;
    int status;
    int options;
    int errnum;
};

static void
waitpid_state_init(struct waitpid_state *w, rb_pid_t pid, int options)
{
    w->ret = 0;
    w->pid = pid;
    w->options = options;
    w->errnum = 0;
    w->status = 0;
}

static void *
waitpid_blocking_no_SIGCHLD(void *x)
{
    struct waitpid_state *w = x;

    w->ret = do_waitpid(w->pid, &w->status, w->options);

    return 0;
}

static void
waitpid_no_SIGCHLD(struct waitpid_state *w)
{
    if (w->options & WNOHANG) {
        w->ret = do_waitpid(w->pid, &w->status, w->options);
    }
    else {
        do {
            rb_thread_call_without_gvl(waitpid_blocking_no_SIGCHLD, w, RUBY_UBF_PROCESS, 0);
        } while (w->ret < 0 && errno == EINTR && (RUBY_VM_CHECK_INTS(w->ec),1));
    }
    if (w->ret == -1)
        w->errnum = errno;
}

VALUE
rb_process_status_wait(rb_pid_t pid, int flags)
{
    // We only enter the scheduler if we are "blocking":
    if (!(flags & WNOHANG)) {
        VALUE scheduler = rb_fiber_scheduler_current();
        VALUE result = rb_fiber_scheduler_process_wait(scheduler, pid, flags);
        if (!UNDEF_P(result)) return result;
    }

    struct waitpid_state waitpid_state;

    waitpid_state_init(&waitpid_state, pid, flags);
    waitpid_state.ec = GET_EC();

    waitpid_no_SIGCHLD(&waitpid_state);

    if (waitpid_state.ret == 0) return Qnil;

    return rb_process_status_new(waitpid_state.ret, waitpid_state.status, waitpid_state.errnum);
}

/*
 *  call-seq:
 *     Process::Status.wait(pid = -1, flags = 0) -> Process::Status
 *
 *  Like Process.wait, but returns a Process::Status object
 *  (instead of an integer pid or nil);
 *  see Process.wait for the values of +pid+ and +flags+.
 *
 *  If there are child processes,
 *  waits for a child process to exit and returns a Process::Status object
 *  containing information on that process;
 *  sets thread-local variable <tt>$?</tt>:
 *
 *    Process.spawn('cat /nop') # => 1155880
 *    Process::Status.wait      # => #<Process::Status: pid 1155880 exit 1>
 *    $?                        # => #<Process::Status: pid 1155508 exit 1>
 *
 *  If there is no child process,
 *  returns an "empty" Process::Status object
 *  that does not represent an actual process;
 *  does not set thread-local variable <tt>$?</tt>:
 *
 *    Process::Status.wait # => #<Process::Status: pid -1 exit 0>
 *    $?                   # => #<Process::Status: pid 1155508 exit 1> # Unchanged.
 *
 *  May invoke the scheduler hook Fiber::Scheduler#process_wait.
 *
 *  Not available on all platforms.
 */

static VALUE
rb_process_status_waitv(int argc, VALUE *argv, VALUE _)
{
    rb_check_arity(argc, 0, 2);

    rb_pid_t pid = -1;
    int flags = 0;

    if (argc >= 1) {
        pid = NUM2PIDT(argv[0]);
    }

    if (argc >= 2) {
        flags = RB_NUM2INT(argv[1]);
    }

    return rb_process_status_wait(pid, flags);
}

rb_pid_t
rb_waitpid(rb_pid_t pid, int *st, int flags)
{
    VALUE status = rb_process_status_wait(pid, flags);
    if (NIL_P(status)) return 0;

    struct rb_process_status *data = rb_check_typeddata(status, &rb_process_status_type);
    pid = data->pid;

    if (st) *st = data->status;

    if (pid == -1) {
        errno = data->error;
    }
    else {
        GET_THREAD()->last_status = status;
    }

    return pid;
}

static VALUE
proc_wait(int argc, VALUE *argv)
{
    rb_pid_t pid;
    int flags, status;

    flags = 0;
    if (rb_check_arity(argc, 0, 2) == 0) {
        pid = -1;
    }
    else {
        VALUE vflags;
        pid = NUM2PIDT(argv[0]);
        if (argc == 2 && !NIL_P(vflags = argv[1])) {
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
 *    Process.wait(pid = -1, flags = 0) -> integer
 *
 *  Waits for a suitable child process to exit, returns its process ID,
 *  and sets <tt>$?</tt> to a Process::Status object
 *  containing information on that process.
 *  Which child it waits for depends on the value of the given +pid+:
 *
 *  - Positive integer: Waits for the child process whose process ID is +pid+:
 *
 *      pid0 = Process.spawn('ruby', '-e', 'exit 13') # => 230866
 *      pid1 = Process.spawn('ruby', '-e', 'exit 14') # => 230891
 *      Process.wait(pid0)                            # => 230866
 *      $?                                            # => #<Process::Status: pid 230866 exit 13>
 *      Process.wait(pid1)                            # => 230891
 *      $?                                            # => #<Process::Status: pid 230891 exit 14>
 *      Process.wait(pid0)                            # Raises Errno::ECHILD
 *
 *  - <tt>0</tt>: Waits for any child process whose group ID
 *    is the same as that of the current process:
 *
 *      parent_pgpid = Process.getpgid(Process.pid)
 *      puts "Parent process group ID is #{parent_pgpid}."
 *      child0_pid = fork do
 *        puts "Child 0 pid is #{Process.pid}"
 *        child0_pgid = Process.getpgid(Process.pid)
 *        puts "Child 0 process group ID is #{child0_pgid} (same as parent's)."
 *      end
 *      child1_pid = fork do
 *        puts "Child 1 pid is #{Process.pid}"
 *        Process.setpgid(0, Process.pid)
 *        child1_pgid = Process.getpgid(Process.pid)
 *        puts "Child 1 process group ID is #{child1_pgid} (different from parent's)."
 *      end
 *      retrieved_pid = Process.wait(0)
 *      puts "Process.wait(0) returned pid #{retrieved_pid}, which is child 0 pid."
 *      begin
 *        Process.wait(0)
 *      rescue Errno::ECHILD => x
 *        puts "Raised #{x.class}, because child 1 process group ID differs from parent process group ID."
 *      end
 *
 *    Output:
 *
 *      Parent process group ID is 225764.
 *      Child 0 pid is 225788
 *      Child 0 process group ID is 225764 (same as parent's).
 *      Child 1 pid is 225789
 *      Child 1 process group ID is 225789 (different from parent's).
 *      Process.wait(0) returned pid 225788, which is child 0 pid.
 *      Raised Errno::ECHILD, because child 1 process group ID differs from parent process group ID.
 *
 *  - <tt>-1</tt> (default): Waits for any child process:
 *
 *      parent_pgpid = Process.getpgid(Process.pid)
 *      puts "Parent process group ID is #{parent_pgpid}."
 *      child0_pid = fork do
 *        puts "Child 0 pid is #{Process.pid}"
 *        child0_pgid = Process.getpgid(Process.pid)
 *        puts "Child 0 process group ID is #{child0_pgid} (same as parent's)."
 *      end
 *      child1_pid = fork do
 *        puts "Child 1 pid is #{Process.pid}"
 *        Process.setpgid(0, Process.pid)
 *        child1_pgid = Process.getpgid(Process.pid)
 *        puts "Child 1 process group ID is #{child1_pgid} (different from parent's)."
 *        sleep 3 # To force child 1 to exit later than child 0 exit.
 *      end
 *      child_pids = [child0_pid, child1_pid]
 *      retrieved_pid = Process.wait(-1)
 *      puts child_pids.include?(retrieved_pid)
 *      retrieved_pid = Process.wait(-1)
 *      puts child_pids.include?(retrieved_pid)
 *
 *    Output:
 *
 *      Parent process group ID is 228736.
 *      Child 0 pid is 228758
 *      Child 0 process group ID is 228736 (same as parent's).
 *      Child 1 pid is 228759
 *      Child 1 process group ID is 228759 (different from parent's).
 *      true
 *      true
 *
 *  - Less than <tt>-1</tt>: Waits for any child whose process group ID is <tt>-pid</tt>:
 *
 *      parent_pgpid = Process.getpgid(Process.pid)
 *      puts "Parent process group ID is #{parent_pgpid}."
 *      child0_pid = fork do
 *        puts "Child 0 pid is #{Process.pid}"
 *        child0_pgid = Process.getpgid(Process.pid)
 *        puts "Child 0 process group ID is #{child0_pgid} (same as parent's)."
 *      end
 *      child1_pid = fork do
 *        puts "Child 1 pid is #{Process.pid}"
 *        Process.setpgid(0, Process.pid)
 *        child1_pgid = Process.getpgid(Process.pid)
 *        puts "Child 1 process group ID is #{child1_pgid} (different from parent's)."
 *      end
 *      sleep 1
 *      retrieved_pid = Process.wait(-child1_pid)
 *      puts "Process.wait(-child1_pid) returned pid #{retrieved_pid}, which is child 1 pid."
 *      begin
 *        Process.wait(-child1_pid)
 *      rescue Errno::ECHILD => x
 *        puts "Raised #{x.class}, because there's no longer a child with process group id #{child1_pid}."
 *      end
 *
 *    Output:
 *
 *      Parent process group ID is 230083.
 *      Child 0 pid is 230108
 *      Child 0 process group ID is 230083 (same as parent's).
 *      Child 1 pid is 230109
 *      Child 1 process group ID is 230109 (different from parent's).
 *      Process.wait(-child1_pid) returned pid 230109, which is child 1 pid.
 *      Raised Errno::ECHILD, because there's no longer a child with process group id 230109.
 *
 *  Argument +flags+ should be given as one of the following constants,
 *  or as the logical OR of both:
 *
 *  - Process::WNOHANG: Does not block if no child process is available.
 *  - Process::WUNTRACED: May return a stopped child process, even if not yet reported.
 *
 *  Not all flags are available on all platforms.
 *
 *  Raises Errno::ECHILD if there is no suitable child process.
 *
 *  Not available on all platforms.
 *
 *  Process.waitpid is an alias for Process.wait.
 */
static VALUE
proc_m_wait(int c, VALUE *v, VALUE _)
{
    return proc_wait(c, v);
}

/*
 *  call-seq:
 *    Process.wait2(pid = -1, flags = 0) -> [pid, status]
 *
 *  Like Process.waitpid, but returns an array
 *  containing the child process +pid+ and Process::Status +status+:
 *
 *    pid = Process.spawn('ruby', '-e', 'exit 13') # => 309581
 *    Process.wait2(pid)
 *    # => [309581, #<Process::Status: pid 309581 exit 13>]
 *
 *  Process.waitpid2 is an alias for Process.wait2.
 */

static VALUE
proc_wait2(int argc, VALUE *argv, VALUE _)
{
    VALUE pid = proc_wait(argc, argv);
    if (NIL_P(pid)) return Qnil;
    return rb_assoc_new(pid, rb_last_status_get());
}


/*
 *  call-seq:
 *    Process.waitall -> array
 *
 *  Waits for all children, returns an array of 2-element arrays;
 *  each subarray contains the integer pid and Process::Status status
 *  for one of the reaped child processes:
 *
 *    pid0 = Process.spawn('ruby', '-e', 'exit 13') # => 325470
 *    pid1 = Process.spawn('ruby', '-e', 'exit 14') # => 325495
 *    Process.waitall
 *    # => [[325470, #<Process::Status: pid 325470 exit 13>], [325495, #<Process::Status: pid 325495 exit 14>]]
 *
 */

static VALUE
proc_waitall(VALUE _)
{
    VALUE result;
    rb_pid_t pid;
    int status;

    result = rb_ary_new();
    rb_last_status_clear();

    for (pid = -1;;) {
        pid = rb_waitpid(-1, &status, 0);
        if (pid == -1) {
            int e = errno;
            if (e == ECHILD)
                break;
            rb_syserr_fail(e, 0);
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
 *    Process.detach(pid) -> thread
 *
 *  Avoids the potential for a child process to become a
 *  {zombie process}[https://en.wikipedia.org/wiki/Zombie_process].
 *  Process.detach prevents this by setting up a separate Ruby thread
 *  whose sole job is to reap the status of the process _pid_ when it terminates.
 *
 *  This method is needed only when the parent process will never wait
 *  for the child process.
 *
 *  This example does not reap the second child process;
 *  that process appears as a zombie in the process status (+ps+) output:
 *
 *    pid = Process.spawn('ruby', '-e', 'exit 13') # => 312691
 *    sleep(1)
 *    # Find zombies.
 *    system("ps -ho pid,state -p #{pid}")
 *
 *  Output:
 *
 *     312716 Z
 *
 *  This example also does not reap the second child process,
 *  but it does detach the process so that it does not become a zombie:
 *
 *    pid = Process.spawn('ruby', '-e', 'exit 13') # => 313213
 *    thread = Process.detach(pid)
 *    sleep(1)
 *    # => #<Process::Waiter:0x00007f038f48b838 run>
 *    system("ps -ho pid,state -p #{pid}")        # Finds no zombies.
 *
 *  The waiting thread can return the pid of the detached child process:
 *
 *    thread.join.pid                       # => 313262
 *
 */

static VALUE
proc_detach(VALUE obj, VALUE pid)
{
    return rb_detach_process(NUM2PIDT(pid));
}

/* This function should be async-signal-safe.  Actually it is. */
static void
before_exec_async_signal_safe(void)
{
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
     *
     * Nowadays, we always stop the timer thread completely to allow redirects.
     */
    rb_thread_stop_timer_thread();
}

#define WRITE_CONST(fd, str) (void)(write((fd),(str),sizeof(str)-1)<0)
#ifdef _WIN32
int rb_w32_set_nonblock2(int fd, int nonblock);
#endif

static int
set_blocking(int fd)
{
#ifdef _WIN32
    return rb_w32_set_nonblock2(fd, 0);
#elif defined(F_GETFL) && defined(F_SETFL)
    int fl = fcntl(fd, F_GETFL); /* async-signal-safe */

    /* EBADF ought to be possible */
    if (fl == -1) return fl;
    if (fl & O_NONBLOCK) {
        fl &= ~O_NONBLOCK;
        return fcntl(fd, F_SETFL, fl);
    }
    return 0;
#endif
}

static void
stdfd_clear_nonblock(void)
{
    /* many programs cannot deal with non-blocking stdin/stdout/stderr */
    int fd;
    for (fd = 0; fd < 3; fd++) {
        (void)set_blocking(fd); /* can't do much about errors anyhow */
    }
}

static void
before_exec(void)
{
    before_exec_non_async_signal_safe();
    before_exec_async_signal_safe();
}

static void
after_exec(void)
{
    rb_thread_reset_timer_thread();
    rb_thread_start_timer_thread();
}

#if defined HAVE_WORKING_FORK || defined HAVE_DAEMON
static void
before_fork_ruby(void)
{
    before_exec();
}

static void
after_fork_ruby(rb_pid_t pid)
{
    if (pid == 0) {
        // child
        clear_pid_cache();
        rb_thread_atfork();
    }
    else {
        // parent
        after_exec();
    }
}
#endif

#if defined(HAVE_WORKING_FORK)

COMPILER_WARNING_PUSH
#if __has_warning("-Wdeprecated-declarations") || RBIMPL_COMPILER_IS(GCC)
COMPILER_WARNING_IGNORED(-Wdeprecated-declarations)
#endif
static inline rb_pid_t
rb_fork(void)
{
    return fork();
}
COMPILER_WARNING_POP

/* try_with_sh and exec_with_sh should be async-signal-safe. Actually it is.*/
#define try_with_sh(err, prog, argv, envp) ((err == ENOEXEC) ? exec_with_sh((prog), (argv), (envp)) : (void)0)
static void
exec_with_sh(const char *prog, char **argv, char **envp)
{
    *argv = (char *)prog;
    *--argv = (char *)"sh";
    if (envp)
        execve("/bin/sh", argv, envp); /* async-signal-safe */
    else
        execv("/bin/sh", argv); /* async-signal-safe (since SUSv4) */
}

#else
#define try_with_sh(err, prog, argv, envp) (void)0
#endif

/* This function should be async-signal-safe.  Actually it is. */
static int
proc_exec_cmd(const char *prog, VALUE argv_str, VALUE envp_str)
{
    char **argv;
#ifndef _WIN32
    char **envp;
    int err;
#endif

    argv = ARGVSTR2ARGV(argv_str);

    if (!prog) {
        return ENOENT;
    }

#ifdef _WIN32
    rb_w32_uaspawn(P_OVERLAY, prog, argv);
    return errno;
#else
    envp = envp_str ? RB_IMEMO_TMPBUF_PTR(envp_str) : NULL;
    if (envp_str)
        execve(prog, argv, envp); /* async-signal-safe */
    else
        execv(prog, argv); /* async-signal-safe (since SUSv4) */
    err = errno;
    try_with_sh(err, prog, argv, envp); /* try_with_sh() is async-signal-safe. */
    return err;
#endif
}

/* This function should be async-signal-safe.  Actually it is. */
static int
proc_exec_sh(const char *str, VALUE envp_str)
{
    const char *s;

    s = str;
    while (*s == ' ' || *s == '\t' || *s == '\n')
        s++;

    if (!*s) {
        return ENOENT;
    }

#ifdef _WIN32
    rb_w32_uspawn(P_OVERLAY, (char *)str, 0);
#elif defined(__CYGWIN32__)
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
        execle("/bin/sh", "sh", "-c", str, (char *)NULL, RB_IMEMO_TMPBUF_PTR(envp_str)); /* async-signal-safe */
    else
        execl("/bin/sh", "sh", "-c", str, (char *)NULL); /* async-signal-safe (since SUSv4) */
#endif	/* _WIN32 */
    return errno;
}

int
rb_proc_exec(const char *str)
{
    int ret;
    before_exec();
    ret = proc_exec_sh(str, Qfalse);
    after_exec();
    errno = ret;
    return -1;
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
    rb_gc_mark(eargp->path_env);
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
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_EMBEDDABLE
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
    else if (!NIL_P(tmp = rb_io_check_io(v))) {
        rb_io_t *fptr;
        GetOpenFile(tmp, fptr);
        if (fptr->tied_io_for_writing)
            rb_raise(rb_eArgError, "duplex IO redirection");
        fd = fptr->fd;
    }
    else {
        goto wrong;
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

  wrong:
    rb_raise(rb_eArgError, "wrong exec redirect");
    UNREACHABLE_RETURN(Qundef);
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
        int i;
        for (i = 0 ; i < RARRAY_LEN(key); i++) {
            VALUE v = RARRAY_AREF(key, i);
            VALUE fd = check_exec_redirect_fd(v, !NIL_P(param));
            rb_ary_push(ary, hide_obj(rb_assoc_new(fd, param)));
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
        id = rb_check_id(&val);
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
            param = hide_obj(rb_ary_new3(4, hide_obj(EXPORT_DUP(path)),
                                            flags, perm, Qnil));
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
                VALUE v = RARRAY_AREF(key, i);
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
        param = hide_obj(rb_ary_new3(4, hide_obj(EXPORT_DUP(path)),
                                        flags, perm, Qnil));
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
static int rlimit_type_by_sym(VALUE key);

static void
rb_execarg_addopt_rlimit(struct rb_execarg *eargp, int rtype, VALUE val)
{
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
#endif

#define TO_BOOL(val, name) (NIL_P(val) ? 0 : rb_bool_expected((val), name, TRUE))
int
rb_execarg_addopt(VALUE execarg_obj, VALUE key, VALUE val)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);

    ID id;

    switch (TYPE(key)) {
      case T_SYMBOL:
#if defined(HAVE_SETRLIMIT) && defined(NUM2RLIM)
        {
            int rtype = rlimit_type_by_sym(key);
            if (rtype != -1) {
                rb_execarg_addopt_rlimit(eargp, rtype, val);
                RB_GC_GUARD(execarg_obj);
                return ST_CONTINUE;
            }
        }
#endif
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
            eargp->new_pgroup_flag = TO_BOOL(val, "new_pgroup");
        }
        else
#endif
        if (id == id_unsetenv_others) {
            if (eargp->unsetenv_others_given) {
                rb_raise(rb_eArgError, "unsetenv_others option specified twice");
            }
            eargp->unsetenv_others_given = 1;
            eargp->unsetenv_others_do = TO_BOOL(val, "unsetenv_others");
        }
        else if (id == id_chdir) {
            if (eargp->chdir_given) {
                rb_raise(rb_eArgError, "chdir option specified twice");
            }
            FilePathValue(val);
            val = rb_str_encode_ospath(val);
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
            eargp->close_others_do = TO_BOOL(val, "close_others");
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
        else if (id == id_exception) {
            if (eargp->exception_given) {
                rb_raise(rb_eArgError, "exception option specified twice");
            }
            eargp->exception_given = 1;
            eargp->exception = TO_BOOL(val, "exception");
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
            rb_raise(rb_eArgError, "wrong exec option symbol: % "PRIsVALUE,
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
            if (ary == eargp->fd_dup2)
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
    rb_hash_stlike_foreach(opthash, check_exec_options_i, (st_data_t)execarg_obj);
}

VALUE
rb_execarg_extract_options(VALUE execarg_obj, VALUE opthash)
{
    VALUE args[2];
    if (RHASH_EMPTY_P(opthash))
        return Qnil;
    args[0] = execarg_obj;
    args[1] = Qnil;
    rb_hash_stlike_foreach(opthash, check_exec_options_i_extract, (st_data_t)args);
    return args[1];
}

#ifdef ENV_IGNORECASE
#define ENVMATCH(s1, s2) (STRCASECMP((s1), (s2)) == 0)
#else
#define ENVMATCH(n1, n2) (strcmp((n1), (n2)) == 0)
#endif

static int
check_exec_env_i(st_data_t st_key, st_data_t st_val, st_data_t arg)
{
    VALUE key = (VALUE)st_key;
    VALUE val = (VALUE)st_val;
    VALUE env = ((VALUE *)arg)[0];
    VALUE *path = &((VALUE *)arg)[1];
    char *k;

    k = StringValueCStr(key);
    if (strchr(k, '='))
        rb_raise(rb_eArgError, "environment name contains a equal : %"PRIsVALUE, key);

    if (!NIL_P(val))
        StringValueCStr(val);

    key = EXPORT_STR(key);
    if (!NIL_P(val)) val = EXPORT_STR(val);

    if (ENVMATCH(k, PATH_ENV)) {
        *path = val;
    }
    rb_ary_push(env, hide_obj(rb_assoc_new(key, val)));

    return ST_CONTINUE;
}

static VALUE
rb_check_exec_env(VALUE hash, VALUE *path)
{
    VALUE env[2];

    env[0] = hide_obj(rb_ary_new());
    env[1] = Qfalse;
    rb_hash_stlike_foreach(hash, check_exec_env_i, (st_data_t)env);
    *path = env[1];

    return env[0];
}

static VALUE
rb_check_argv(int argc, VALUE *argv)
{
    VALUE tmp, prog;
    int i;

    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);

    prog = 0;
    tmp = rb_check_array_type(argv[0]);
    if (!NIL_P(tmp)) {
        if (RARRAY_LEN(tmp) != 2) {
            rb_raise(rb_eArgError, "wrong first argument");
        }
        prog = RARRAY_AREF(tmp, 0);
        argv[0] = RARRAY_AREF(tmp, 1);
        StringValue(prog);
        StringValueCStr(prog);
        prog = rb_str_new_frozen(prog);
    }
    for (i = 0; i < argc; i++) {
        StringValue(argv[i]);
        argv[i] = rb_str_new_frozen(argv[i]);
        StringValueCStr(argv[i]);
    }
    return prog;
}

static VALUE
check_hash(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return Qnil;
    switch (RB_BUILTIN_TYPE(obj)) {
      case T_STRING:
      case T_ARRAY:
        return Qnil;
      default:
        break;
    }
    return rb_check_hash_type(obj);
}

static VALUE
rb_exec_getargs(int *argc_p, VALUE **argv_p, int accept_shell, VALUE *env_ret, VALUE *opthash_ret)
{
    VALUE hash, prog;

    if (0 < *argc_p) {
        hash = check_hash((*argv_p)[*argc_p-1]);
        if (!NIL_P(hash)) {
            *opthash_ret = hash;
            (*argc_p)--;
        }
    }

    if (0 < *argc_p) {
        hash = check_hash((*argv_p)[0]);
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
        env = rb_check_exec_env(env, &eargp->path_env);
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
            eargp->invoke.cmd.command_name =
                hide_obj(rb_str_subseq(argv_buf, 0, strlen(RSTRING_PTR(argv_buf))));
            rb_enc_copy(eargp->invoke.cmd.command_name, prog);
        }
    }
#endif

    if (!eargp->use_shell) {
        const char *abspath;
        const char *path_env = 0;
        if (RTEST(eargp->path_env)) path_env = RSTRING_PTR(eargp->path_env);
        abspath = dln_find_exe_r(RSTRING_PTR(eargp->invoke.cmd.command_name),
                                 path_env, fbuf, sizeof(fbuf));
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
        eargp->invoke.cmd.argv_str =
            rb_imemo_tmpbuf_auto_free_pointer_new_from_an_RString(argv_str);
    }
    RB_GC_GUARD(execarg_obj);
}

struct rb_execarg *
rb_execarg_get(VALUE execarg_obj)
{
    struct rb_execarg *eargp;
    TypedData_Get_Struct(execarg_obj, struct rb_execarg, &exec_arg_data_type, eargp);
    return eargp;
}

static VALUE
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

VALUE
rb_execarg_new(int argc, const VALUE *argv, int accept_shell, int allow_exc_opt)
{
    VALUE execarg_obj;
    struct rb_execarg *eargp;
    execarg_obj = TypedData_Make_Struct(0, struct rb_execarg, &exec_arg_data_type, eargp);
    rb_execarg_init(argc, argv, accept_shell, execarg_obj);
    if (!allow_exc_opt && eargp->exception_given) {
        rb_raise(rb_eArgError, "exception option is not allowed");
    }
    return execarg_obj;
}

void
rb_execarg_setenv(VALUE execarg_obj, VALUE env)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);
    env = !NIL_P(env) ? rb_check_exec_env(env, &eargp->path_env) : Qfalse;
    eargp->env_modification = env;
    RB_GC_GUARD(execarg_obj);
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

struct open_struct {
    VALUE fname;
    int oflags;
    mode_t perm;
    int ret;
    int err;
};

static void *
open_func(void *ptr)
{
    struct open_struct *data = ptr;
    const char *fname = RSTRING_PTR(data->fname);
    data->ret = parent_redirect_open(fname, data->oflags, data->perm);
    data->err = errno;
    return NULL;
}

static void
rb_execarg_allocate_dup2_tmpbuf(struct rb_execarg *eargp, long len)
{
    VALUE tmpbuf = rb_imemo_tmpbuf_auto_free_pointer();
    rb_imemo_tmpbuf_set_ptr(tmpbuf, ruby_xmalloc(run_exec_dup2_tmpbuf_size(len)));
    eargp->dup2_tmpbuf = tmpbuf;
}

static VALUE
rb_execarg_parent_start1(VALUE execarg_obj)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);
    int unsetenv_others;
    VALUE envopts;
    VALUE ary;

    ary = eargp->fd_open;
    if (ary != Qfalse) {
        long i;
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            VALUE elt = RARRAY_AREF(ary, i);
            int fd = FIX2INT(RARRAY_AREF(elt, 0));
            VALUE param = RARRAY_AREF(elt, 1);
            VALUE vpath = RARRAY_AREF(param, 0);
            int flags = NUM2INT(RARRAY_AREF(param, 1));
            mode_t perm = NUM2MODET(RARRAY_AREF(param, 2));
            VALUE fd2v = RARRAY_AREF(param, 3);
            int fd2;
            if (NIL_P(fd2v)) {
                struct open_struct open_data;
              again:
                open_data.fname = vpath;
                open_data.oflags = flags;
                open_data.perm = perm;
                open_data.ret = -1;
                open_data.err = EINTR;
                rb_thread_call_without_gvl2(open_func, (void *)&open_data, RUBY_UBF_IO, 0);
                if (open_data.ret == -1) {
                    if (open_data.err == EINTR) {
                        rb_thread_check_ints();
                        goto again;
                    }
                    rb_syserr_fail_str(open_data.err, vpath);
                }
                fd2 = open_data.ret;
                rb_update_max_fd(fd2);
                RARRAY_ASET(param, 3, INT2FIX(fd2));
                rb_thread_check_ints();
            }
            else {
                fd2 = NUM2INT(fd2v);
            }
            rb_execarg_addopt(execarg_obj, INT2FIX(fd), INT2FIX(fd2));
        }
    }

    eargp->redirect_fds = check_exec_fds(eargp);

    ary = eargp->fd_dup2;
    if (ary != Qfalse) {
        rb_execarg_allocate_dup2_tmpbuf(eargp, RARRAY_LEN(ary));
    }

    unsetenv_others = eargp->unsetenv_others_given && eargp->unsetenv_others_do;
    envopts = eargp->env_modification;
    if (ALWAYS_NEED_ENVP || unsetenv_others || envopts != Qfalse) {
        VALUE envtbl, envp_str, envp_buf;
        char *p, *ep;
        if (unsetenv_others) {
            envtbl = rb_hash_new();
        }
        else {
            envtbl = rb_env_to_hash();
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
        rb_hash_stlike_foreach(envtbl, fill_envp_buf_i, (st_data_t)envp_buf);
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
        eargp->envp_str =
            rb_imemo_tmpbuf_auto_free_pointer_new_from_an_RString(envp_str);
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
    return Qnil;
}

void
rb_execarg_parent_start(VALUE execarg_obj)
{
    int state;
    rb_protect(rb_execarg_parent_start1, execarg_obj, &state);
    if (state) {
        rb_execarg_parent_end(execarg_obj);
        rb_jump_tag(state);
    }
}

static VALUE
execarg_parent_end(VALUE execarg_obj)
{
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);
    int err = errno;
    VALUE ary;

    ary = eargp->fd_open;
    if (ary != Qfalse) {
        long i;
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            VALUE elt = RARRAY_AREF(ary, i);
            VALUE param = RARRAY_AREF(elt, 1);
            VALUE fd2v;
            int fd2;
            fd2v = RARRAY_AREF(param, 3);
            if (!NIL_P(fd2v)) {
                fd2 = FIX2INT(fd2v);
                parent_redirect_close(fd2);
                RARRAY_ASET(param, 3, Qnil);
            }
        }
    }

    errno = err;
    RB_GC_GUARD(execarg_obj);
    return execarg_obj;
}

void
rb_execarg_parent_end(VALUE execarg_obj)
{
    execarg_parent_end(execarg_obj);
    RB_GC_GUARD(execarg_obj);
}

static void
rb_exec_fail(struct rb_execarg *eargp, int err, const char *errmsg)
{
    if (!errmsg || !*errmsg) return;
    if (strcmp(errmsg, "chdir") == 0) {
        rb_sys_fail_str(eargp->chdir_dir);
    }
    rb_sys_fail(errmsg);
}

#if 0
void
rb_execarg_fail(VALUE execarg_obj, int err, const char *errmsg)
{
    if (!errmsg || !*errmsg) return;
    rb_exec_fail(rb_execarg_get(execarg_obj), err, errmsg);
    RB_GC_GUARD(execarg_obj);
}
#endif

VALUE
rb_f_exec(int argc, const VALUE *argv)
{
    VALUE execarg_obj, fail_str;
    struct rb_execarg *eargp;
#define CHILD_ERRMSG_BUFLEN 80
    char errmsg[CHILD_ERRMSG_BUFLEN] = { '\0' };
    int err, state;

    execarg_obj = rb_execarg_new(argc, argv, TRUE, FALSE);
    eargp = rb_execarg_get(execarg_obj);
    before_exec(); /* stop timer thread before redirects */

    rb_protect(rb_execarg_parent_start1, execarg_obj, &state);
    if (state) {
        execarg_parent_end(execarg_obj);
        after_exec(); /* restart timer thread */
        rb_jump_tag(state);
    }

    fail_str = eargp->use_shell ? eargp->invoke.sh.shell_script : eargp->invoke.cmd.command_name;

    err = exec_async_signal_safe(eargp, errmsg, sizeof(errmsg));
    after_exec(); /* restart timer thread */

    rb_exec_fail(eargp, err, errmsg);
    RB_GC_GUARD(execarg_obj);
    rb_syserr_fail_str(err, fail_str);
    UNREACHABLE_RETURN(Qnil);
}

NORETURN(static VALUE f_exec(int c, const VALUE *a, VALUE _));

/*
 *  call-seq:
 *    exec([env, ] command_line, options = {})
 *    exec([env, ] exe_path, *args, options  = {})
 *
 *  Replaces the current process by doing one of the following:
 *
 *  - Passing string +command_line+ to the shell.
 *  - Invoking the executable at +exe_path+.
 *
 *  This method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  The new process is created using the
 *  {exec system call}[https://pubs.opengroup.org/onlinepubs/9699919799.2018edition/functions/execve.html];
 *  it may inherit some of its environment from the calling program
 *  (possibly including open file descriptors).
 *
 *  Argument +env+, if given, is a hash that affects +ENV+ for the new process;
 *  see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
 *
 *  Argument +options+ is a hash of options for the new process;
 *  see {Execution Options}[rdoc-ref:Process@Execution+Options].
 *
 *  The first required argument is one of the following:
 *
 *  - +command_line+ if it is a string,
 *    and if it begins with a shell reserved word or special built-in,
 *    or if it contains one or more meta characters.
 *  - +exe_path+ otherwise.
 *
 *  <b>Argument +command_line+</b>
 *
 *  \String argument +command_line+ is a command line to be passed to a shell;
 *  it must begin with a shell reserved word, begin with a special built-in,
 *  or contain meta characters:
 *
 *    exec('if true; then echo "Foo"; fi') # Shell reserved word.
 *    exec('exit')                         # Built-in.
 *    exec('date > date.tmp')              # Contains meta character.
 *
 *  The command line may also contain arguments and options for the command:
 *
 *    exec('echo "Foo"')
 *
 *  Output:
 *
 *    Foo
 *
 *  See {Execution Shell}[rdoc-ref:Process@Execution+Shell] for details about the shell.
 *
 *  Raises an exception if the new process could not execute.
 *
 *  <b>Argument +exe_path+</b>
 *
 *  Argument +exe_path+ is one of the following:
 *
 *  - The string path to an executable to be called.
 *  - A 2-element array containing the path to an executable
 *    and the string to be used as the name of the executing process.
 *
 *  Example:
 *
 *    exec('/usr/bin/date')
 *
 *  Output:
 *
 *    Sat Aug 26 09:38:00 AM CDT 2023
 *
 *  Ruby invokes the executable directly.
 *  This form does not use the shell;
 *  see {Arguments args}[rdoc-ref:Process@Arguments+args] for caveats.
 *
 *    exec('doesnt_exist') # Raises Errno::ENOENT
 *
 *  If one or more +args+ is given, each is an argument or option
 *  to be passed to the executable:
 *
 *    exec('echo', 'C*')
 *    exec('echo', 'hello', 'world')
 *
 *  Output:
 *
 *    C*
 *    hello world
 *
 *  Raises an exception if the new process could not execute.
 */

static VALUE
f_exec(int c, const VALUE *a, VALUE _)
{
    rb_f_exec(c, a);
    UNREACHABLE_RETURN(Qnil);
}

#define ERRMSG(str) \
    ((errmsg && 0 < errmsg_buflen) ? \
     (void)strlcpy(errmsg, (str), errmsg_buflen) : (void)0)

#define ERRMSG_FMT(...) \
    ((errmsg && 0 < errmsg_buflen) ? \
     (void)snprintf(errmsg, errmsg_buflen, __VA_ARGS__) : (void)0)

static int fd_get_cloexec(int fd, char *errmsg, size_t errmsg_buflen);
static int fd_set_cloexec(int fd, char *errmsg, size_t errmsg_buflen);
static int fd_clear_cloexec(int fd, char *errmsg, size_t errmsg_buflen);

static int
save_redirect_fd(int fd, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    if (sargp) {
        VALUE newary, redirection;
        int save_fd = redirect_cloexec_dup(fd), cloexec;
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
        cloexec = fd_get_cloexec(fd, errmsg, errmsg_buflen);
        redirection = hide_obj(rb_assoc_new(INT2FIX(fd), INT2FIX(save_fd)));
        if (cloexec) rb_ary_push(redirection, Qtrue);
        rb_ary_push(newary, redirection);

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
    int cloexec;
};

static long
run_exec_dup2_tmpbuf_size(long n)
{
    return sizeof(struct run_exec_dup2_fd_pair) * n;
}

/* This function should be async-signal-safe.  Actually it is. */
static int
fd_get_cloexec(int fd, char *errmsg, size_t errmsg_buflen)
{
#ifdef F_GETFD
    int ret = 0;
    ret = fcntl(fd, F_GETFD); /* async-signal-safe */
    if (ret == -1) {
        ERRMSG("fcntl(F_GETFD)");
        return -1;
    }
    if (ret & FD_CLOEXEC) return 1;
#endif
    return 0;
}

/* This function should be async-signal-safe.  Actually it is. */
static int
fd_set_cloexec(int fd, char *errmsg, size_t errmsg_buflen)
{
#ifdef F_GETFD
    int ret = 0;
    ret = fcntl(fd, F_GETFD); /* async-signal-safe */
    if (ret == -1) {
        ERRMSG("fcntl(F_GETFD)");
        return -1;
    }
    if (!(ret & FD_CLOEXEC)) {
        ret |= FD_CLOEXEC;
        ret = fcntl(fd, F_SETFD, ret); /* async-signal-safe */
        if (ret == -1) {
            ERRMSG("fcntl(F_SETFD)");
            return -1;
        }
    }
#endif
    return 0;
}

/* This function should be async-signal-safe.  Actually it is. */
static int
fd_clear_cloexec(int fd, char *errmsg, size_t errmsg_buflen)
{
#ifdef F_GETFD
    int ret;
    ret = fcntl(fd, F_GETFD); /* async-signal-safe */
    if (ret == -1) {
        ERRMSG("fcntl(F_GETFD)");
        return -1;
    }
    if (ret & FD_CLOEXEC) {
        ret &= ~FD_CLOEXEC;
        ret = fcntl(fd, F_SETFD, ret); /* async-signal-safe */
        if (ret == -1) {
            ERRMSG("fcntl(F_SETFD)");
            return -1;
        }
    }
#endif
    return 0;
}

/* This function should be async-signal-safe when sargp is NULL.  Hopefully it is. */
static int
run_exec_dup2(VALUE ary, VALUE tmpbuf, struct rb_execarg *sargp, char *errmsg, size_t errmsg_buflen)
{
    long n, i;
    int ret;
    int extra_fd = -1;
    struct rb_imemo_tmpbuf_struct *buf = (void *)tmpbuf;
    struct run_exec_dup2_fd_pair *pairs = (void *)buf->ptr;

    n = RARRAY_LEN(ary);

    /* initialize oldfd and newfd: O(n) */
    for (i = 0; i < n; i++) {
        VALUE elt = RARRAY_AREF(ary, i);
        pairs[i].oldfd = FIX2INT(RARRAY_AREF(elt, 1));
        pairs[i].newfd = FIX2INT(RARRAY_AREF(elt, 0)); /* unique */
        pairs[i].cloexec = RARRAY_LEN(elt) > 2 && RTEST(RARRAY_AREF(elt, 2));
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
            if (pairs[j].cloexec &&
                fd_set_cloexec(pairs[j].newfd, errmsg, errmsg_buflen)) {
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
            if (fd_clear_cloexec(pairs[i].oldfd, errmsg, errmsg_buflen) == -1) /* async-signal-safe */
                goto fail;
            pairs[i].oldfd = -1;
            continue;
        }
        if (extra_fd == -1) {
            extra_fd = redirect_dup(pairs[i].oldfd); /* async-signal-safe */
            if (extra_fd == -1) {
                ERRMSG("dup");
                goto fail;
            }
            // without this, kqueue timer_th.event_fd fails with a reserved FD did not have close-on-exec
            //   in #assert_close_on_exec because the FD_CLOEXEC is not dup'd by default
            if (fd_get_cloexec(pairs[i].oldfd, errmsg, errmsg_buflen)) {
                if (fd_set_cloexec(extra_fd, errmsg, errmsg_buflen)) {
                    goto fail;
                }
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
        VALUE env = rb_envtbl();
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

#ifdef _WIN32
#undef chdir
#define chdir(p) rb_w32_uchdir(p)
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
    if (eargp->close_others_do) {
        rb_close_before_exec(3, eargp->close_others_maxhint, eargp->redirect_fds); /* async-signal-safe */
    }
#endif

    obj = eargp->fd_dup2_child;
    if (obj != Qfalse) {
        if (run_exec_dup2_child(obj, sargp, errmsg, errmsg_buflen) == -1) /* async-signal-safe */
            return -1;
    }

    if (eargp->chdir_given) {
        if (sargp) {
            sargp->chdir_given = 1;
            sargp->chdir_dir = hide_obj(rb_dir_getwd_ospath());
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
            rb_execarg_allocate_dup2_tmpbuf(sargp, RARRAY_LEN(ary));
        }
    }
    {
        int preserve = errno;
        stdfd_clear_nonblock();
        errno = preserve;
    }

    return 0;
}

/* This function should be async-signal-safe.  Hopefully it is. */
int
rb_exec_async_signal_safe(const struct rb_execarg *eargp, char *errmsg, size_t errmsg_buflen)
{
    errno = exec_async_signal_safe(eargp, errmsg, errmsg_buflen);
    return -1;
}

static int
exec_async_signal_safe(const struct rb_execarg *eargp, char *errmsg, size_t errmsg_buflen)
{
#if !defined(HAVE_WORKING_FORK)
    struct rb_execarg sarg, *const sargp = &sarg;
#else
    struct rb_execarg *const sargp = NULL;
#endif
    int err;

    if (rb_execarg_run_options(eargp, sargp, errmsg, errmsg_buflen) < 0) { /* hopefully async-signal-safe */
        return errno;
    }

    if (eargp->use_shell) {
        err = proc_exec_sh(RSTRING_PTR(eargp->invoke.sh.shell_script), eargp->envp_str); /* async-signal-safe */
    }
    else {
        char *abspath = NULL;
        if (!NIL_P(eargp->invoke.cmd.command_abspath))
            abspath = RSTRING_PTR(eargp->invoke.cmd.command_abspath);
        err = proc_exec_cmd(abspath, eargp->invoke.cmd.argv_str, eargp->envp_str); /* async-signal-safe */
    }
#if !defined(HAVE_WORKING_FORK)
    rb_execarg_run_options(sargp, NULL, errmsg, errmsg_buflen);
#endif

    return err;
}

#ifdef HAVE_WORKING_FORK
/* This function should be async-signal-safe.  Hopefully it is. */
static int
rb_exec_atfork(void* arg, char *errmsg, size_t errmsg_buflen)
{
    return rb_exec_async_signal_safe(arg, errmsg, errmsg_buflen); /* hopefully async-signal-safe */
}

static VALUE
proc_syswait(VALUE pid)
{
    rb_syswait((rb_pid_t)pid);
    return Qnil;
}

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

static VALUE
rb_thread_sleep_that_takes_VALUE_as_sole_argument(VALUE n)
{
    rb_thread_sleep(NUM2INT(n));
    return Qundef;
}

static int
handle_fork_error(int err, struct rb_process_status *status, int *ep, volatile int *try_gc_p)
{
    int state = 0;

    switch (err) {
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
            rb_protect(rb_thread_sleep_that_takes_VALUE_as_sole_argument, INT2FIX(1), &state);
            if (status) status->status = state;
            if (!state) return 0;
        }
        break;
    }
    if (ep) {
        close(ep[0]);
        close(ep[1]);
        errno = err;
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

    if (set_blocking(fd) != 0) {
#ifndef _WIN32
        rb_async_bug_errno("set_blocking failed reading child error", errno);
#endif
    }

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
};

static void
disable_child_handler_before_fork(struct child_handler_disabler_state *old)
{
#ifdef HAVE_PTHREAD_SIGMASK
    int ret;
    sigset_t all;

    ret = sigfillset(&all);
    if (ret == -1)
        rb_sys_fail("sigfillset");

    ret = pthread_sigmask(SIG_SETMASK, &all, &old->sigmask); /* not async-signal-safe */
    if (ret != 0) {
        rb_syserr_fail(ret, "pthread_sigmask");
    }
#else
# pragma GCC warning "pthread_sigmask on fork is not available. potentially dangerous"
#endif
}

static void
disable_child_handler_fork_parent(struct child_handler_disabler_state *old)
{
#ifdef HAVE_PTHREAD_SIGMASK
    int ret;

    ret = pthread_sigmask(SIG_SETMASK, &old->sigmask, NULL); /* not async-signal-safe */
    if (ret != 0) {
        rb_syserr_fail(ret, "pthread_sigmask");
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

    for (sig = 1; sig < NSIG; sig++) {
        sig_t handler = signal(sig, SIG_DFL);

        if (handler == SIG_ERR && errno == EINVAL) {
            continue; /* Ignore invalid signal number */
        }
        if (handler == SIG_ERR) {
            ERRMSG("signal to obtain old action");
            return -1;
        }
#ifdef SIGPIPE
        if (sig == SIGPIPE) {
            continue;
        }
#endif
        /* it will be reset to SIG_DFL at execve time, instead */
        if (handler == SIG_IGN) {
            signal(sig, SIG_IGN);
        }
    }

    /* non-Ruby child process, ensure cmake can see SIGCHLD */
    sigemptyset(&old->sigmask);
    ret = sigprocmask(SIG_SETMASK, &old->sigmask, NULL); /* async-signal-safe */
    if (ret != 0) {
        ERRMSG("sigprocmask");
        return -1;
    }
    return 0;
}

static rb_pid_t
retry_fork_async_signal_safe(struct rb_process_status *status, int *ep,
        int (*chfunc)(void*, char *, size_t), void *charg,
        char *errmsg, size_t errmsg_buflen,
        struct waitpid_state *w)
{
    rb_pid_t pid;
    volatile int try_gc = 1;
    struct child_handler_disabler_state old;
    int err;

    while (1) {
        prefork();
        disable_child_handler_before_fork(&old);
#ifdef HAVE_WORKING_VFORK
        if (!has_privilege())
            pid = vfork();
        else
            pid = rb_fork();
#else
        pid = rb_fork();
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
        err = errno;
        disable_child_handler_fork_parent(&old);
        if (0 < pid) /* fork succeed, parent process */
            return pid;
        /* fork failed */
        if (handle_fork_error(err, status, ep, &try_gc))
            return -1;
    }
}

static rb_pid_t
fork_check_err(struct rb_process_status *status, int (*chfunc)(void*, char *, size_t), void *charg,
        VALUE fds, char *errmsg, size_t errmsg_buflen,
        struct rb_execarg *eargp)
{
    rb_pid_t pid;
    int err;
    int ep[2];
    int error_occurred;

    struct waitpid_state *w = eargp && eargp->waitpid_state ? eargp->waitpid_state : 0;

    if (status) status->status = 0;

    if (pipe_nocrash(ep, fds)) return -1;

    pid = retry_fork_async_signal_safe(status, ep, chfunc, charg, errmsg, errmsg_buflen, w);

    if (status) status->pid = pid;

    if (pid < 0) {
        if (status) status->error = errno;

        return pid;
    }

    close(ep[1]);

    error_occurred = recv_child_error(ep[0], &err, errmsg, errmsg_buflen);

    if (error_occurred) {
        if (status) {
            int state = 0;
            status->error = err;

            VM_ASSERT((w == 0) && "only used by extensions");
            rb_protect(proc_syswait, (VALUE)pid, &state);

            status->status = state;
        }
        else if (!w) {
            rb_syswait(pid);
        }

        errno = err;
        return -1;
    }

    return pid;
}

/*
 * The "async_signal_safe" name is a lie, but it is used by pty.c and
 * maybe other exts.  fork() is not async-signal-safe due to pthread_atfork
 * and future POSIX revisions will remove it from a list of signal-safe
 * functions.  rb_waitpid is not async-signal-safe since RJIT, either.
 * For our purposes, we do not need async-signal-safety, here
 */
rb_pid_t
rb_fork_async_signal_safe(int *status,
                          int (*chfunc)(void*, char *, size_t), void *charg,
                          VALUE fds, char *errmsg, size_t errmsg_buflen)
{
    struct rb_process_status process_status;

    rb_pid_t result = fork_check_err(&process_status, chfunc, charg, fds, errmsg, errmsg_buflen, 0);

    if (status) {
        *status = process_status.status;
    }

    return result;
}

static rb_pid_t
rb_fork_ruby2(struct rb_process_status *status)
{
    rb_pid_t pid;
    int try_gc = 1, err;
    struct child_handler_disabler_state old;

    if (status) status->status = 0;

    while (1) {
        prefork();

        before_fork_ruby();
        disable_child_handler_before_fork(&old);
        {
            pid = rb_fork();
            err = errno;
            if (status) {
                status->pid = pid;
                status->error = err;
            }
        }
        disable_child_handler_fork_parent(&old); /* yes, bad name */
        after_fork_ruby(pid);

        if (pid >= 0) { /* fork succeed */
            return pid;
        }

        /* fork failed */
        if (handle_fork_error(err, status, NULL, &try_gc)) {
            return -1;
        }
    }
}

rb_pid_t
rb_fork_ruby(int *status)
{
    struct rb_process_status process_status = {0};

    rb_pid_t pid = rb_fork_ruby2(&process_status);

    if (status) *status = process_status.status;

    return pid;
}

static rb_pid_t
proc_fork_pid(void)
{
    rb_pid_t pid = rb_fork_ruby(NULL);

    if (pid == -1) {
        rb_sys_fail("fork(2)");
    }

    return pid;
}

rb_pid_t
rb_call_proc__fork(void)
{
    ID id__fork;
    CONST_ID(id__fork, "_fork");
    if (rb_method_basic_definition_p(CLASS_OF(rb_mProcess), id__fork)) {
        return proc_fork_pid();
    }
    else {
        VALUE pid = rb_funcall(rb_mProcess, id__fork, 0);
        return NUM2PIDT(pid);
    }
}
#endif

#if defined(HAVE_WORKING_FORK) && !defined(CANNOT_FORK_WITH_PTHREAD)
/*
 *  call-seq:
 *     Process._fork   -> integer
 *
 *  An internal API for fork. Do not call this method directly.
 *  Currently, this is called via Kernel#fork, Process.fork, and
 *  IO.popen with <tt>"-"</tt>.
 *
 *  This method is not for casual code but for application monitoring
 *  libraries. You can add custom code before and after fork events
 *  by overriding this method.
 *
 *  Note: Process.daemon may be implemented using fork(2) BUT does not go
 *  through this method.
 *  Thus, depending on your reason to hook into this method, you
 *  may also want to hook into that one.
 *  See {this issue}[https://bugs.ruby-lang.org/issues/18911] for a
 *  more detailed discussion of this.
 */
VALUE
rb_proc__fork(VALUE _obj)
{
    rb_pid_t pid = proc_fork_pid();
    return PIDT2NUM(pid);
}

/*
 *  call-seq:
 *    Process.fork { ... } -> integer or nil
 *    Process.fork -> integer or nil
 *
 *  Creates a child process.
 *
 *  With a block given, runs the block in the child process;
 *  on block exit, the child terminates with a status of zero:
 *
 *    puts "Before the fork: #{Process.pid}"
 *    fork do
 *      puts "In the child process: #{Process.pid}"
 *    end                   # => 382141
 *    puts "After the fork: #{Process.pid}"
 *
 *  Output:
 *
 *    Before the fork: 420496
 *    After the fork: 420496
 *    In the child process: 420520
 *
 *  With no block given, the +fork+ call returns twice:
 *
 *  - Once in the parent process, returning the pid of the child process.
 *  - Once in the child process, returning +nil+.
 *
 *  Example:
 *
 *    puts "This is the first line before the fork (pid #{Process.pid})"
 *    puts fork
 *    puts "This is the second line after the fork (pid #{Process.pid})"
 *
 *  Output:
 *
 *    This is the first line before the fork (pid 420199)
 *    420223
 *    This is the second line after the fork (pid 420199)
 *
 *    This is the second line after the fork (pid 420223)
 *
 *  In either case, the child process may exit using
 *  Kernel.exit! to avoid the call to Kernel#at_exit.
 *
 *  To avoid zombie processes, the parent process should call either:
 *
 *  - Process.wait, to collect the termination statuses of its children.
 *  - Process.detach, to register disinterest in their status.
 *
 *  The thread calling +fork+ is the only thread in the created child process;
 *  +fork+ doesn't copy other threads.
 *
 *  Note that method +fork+ is available on some platforms,
 *  but not on others:
 *
 *    Process.respond_to?(:fork) # => true # Would be false on some.
 *
 *  If not, you may use ::spawn instead of +fork+.
 */

static VALUE
rb_f_fork(VALUE obj)
{
    rb_pid_t pid;

    pid = rb_call_proc__fork();

    if (pid == 0) {
        if (rb_block_given_p()) {
            int status;
            rb_protect(rb_yield, Qundef, &status);
            ruby_stop(status);
        }
        return Qnil;
    }

    return PIDT2NUM(pid);
}
#else
#define rb_proc__fork rb_f_notimplement
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

NORETURN(static VALUE rb_f_exit_bang(int argc, VALUE *argv, VALUE obj));
/*
 *  call-seq:
 *    exit!(status = false)
 *    Process.exit!(status = false)
 *
 *  Exits the process immediately; no exit handlers are called.
 *  Returns exit status +status+ to the underlying operating system.
 *
 *     Process.exit!(true)
 *
 *  Values +true+ and +false+ for argument +status+
 *  indicate, respectively, success and failure;
 *  The meanings of integer values are system-dependent.
 *
 */

static VALUE
rb_f_exit_bang(int argc, VALUE *argv, VALUE obj)
{
    int istatus;

    if (rb_check_arity(argc, 0, 1) == 1) {
        istatus = exit_status_code(argv[0]);
    }
    else {
        istatus = EXIT_FAILURE;
    }
    _exit(istatus);

    UNREACHABLE_RETURN(Qnil);
}

void
rb_exit(int status)
{
    if (GET_EC()->tag) {
        VALUE args[2];

        args[0] = INT2NUM(status);
        args[1] = rb_str_new2("exit");
        rb_exc_raise(rb_class_new_instance(2, args, rb_eSystemExit));
    }
    ruby_stop(status);
}

VALUE
rb_f_exit(int argc, const VALUE *argv)
{
    int istatus;

    if (rb_check_arity(argc, 0, 1) == 1) {
        istatus = exit_status_code(argv[0]);
    }
    else {
        istatus = EXIT_SUCCESS;
    }
    rb_exit(istatus);

    UNREACHABLE_RETURN(Qnil);
}

NORETURN(static VALUE f_exit(int c, const VALUE *a, VALUE _));
/*
 *  call-seq:
 *    exit(status = true)
 *    Process.exit(status = true)
 *
 *  Initiates termination of the Ruby script by raising SystemExit;
 *  the exception may be caught.
 *  Returns exit status +status+ to the underlying operating system.
 *
 *  Values +true+ and +false+ for argument +status+
 *  indicate, respectively, success and failure;
 *  The meanings of integer values are system-dependent.
 *
 *  Example:
 *
 *    begin
 *      exit
 *      puts 'Never get here.'
 *    rescue SystemExit
 *      puts 'Rescued a SystemExit exception.'
 *    end
 *    puts 'After begin block.'
 *
 *  Output:
 *
 *    Rescued a SystemExit exception.
 *    After begin block.
 *
 *  Just prior to final termination,
 *  Ruby executes any at-exit procedures (see Kernel::at_exit)
 *  and any object finalizers (see ObjectSpace::define_finalizer).
 *
 *  Example:
 *
 *    at_exit { puts 'In at_exit function.' }
 *    ObjectSpace.define_finalizer('string', proc { puts 'In finalizer.' })
 *    exit
 *
 *  Output:
 *
 *     In at_exit function.
 *     In finalizer.
 *
 */

static VALUE
f_exit(int c, const VALUE *a, VALUE _)
{
    rb_f_exit(c, a);
    UNREACHABLE_RETURN(Qnil);
}

VALUE
rb_f_abort(int argc, const VALUE *argv)
{
    rb_check_arity(argc, 0, 1);
    if (argc == 0) {
        rb_execution_context_t *ec = GET_EC();
        VALUE errinfo = rb_ec_get_errinfo(ec);
        if (!NIL_P(errinfo)) {
            rb_ec_error_print(ec, errinfo);
        }
        rb_exit(EXIT_FAILURE);
    }
    else {
        VALUE args[2];

        args[1] = args[0] = argv[0];
        StringValue(args[0]);
        rb_io_puts(1, args, rb_ractor_stderr());
        args[0] = INT2NUM(EXIT_FAILURE);
        rb_exc_raise(rb_class_new_instance(2, args, rb_eSystemExit));
    }

    UNREACHABLE_RETURN(Qnil);
}

NORETURN(static VALUE f_abort(int c, const VALUE *a, VALUE _));

/*
 *  call-seq:
 *    abort
 *    Process.abort(msg = nil)
 *
 *  Terminates execution immediately, effectively by calling
 *  <tt>Kernel.exit(false)</tt>.
 *
 *  If string argument +msg+ is given,
 *  it is written to STDERR prior to termination;
 *  otherwise, if an exception was raised,
 *  prints its message and backtrace.
 */

static VALUE
f_abort(int c, const VALUE *a, VALUE _)
{
    rb_f_abort(c, a);
    UNREACHABLE_RETURN(Qnil);
}

void
rb_syswait(rb_pid_t pid)
{
    int status;

    rb_waitpid(pid, &status, 0);
}

#if !defined HAVE_WORKING_FORK && !defined HAVE_SPAWNV && !defined __EMSCRIPTEN__
char *
rb_execarg_commandline(const struct rb_execarg *eargp, VALUE *prog)
{
    VALUE cmd = *prog;
    if (eargp && !eargp->use_shell) {
        VALUE str = eargp->invoke.cmd.argv_str;
        VALUE buf = eargp->invoke.cmd.argv_buf;
        char *p, **argv = ARGVSTR2ARGV(str);
        long i, argc = ARGVSTR2ARGC(str);
        const char *start = RSTRING_PTR(buf);
        cmd = rb_str_new(start, RSTRING_LEN(buf));
        p = RSTRING_PTR(cmd);
        for (i = 1; i < argc; ++i) {
            p[argv[i] - start - 1] = ' ';
        }
        *prog = cmd;
        return p;
    }
    return StringValueCStr(*prog);
}
#endif

static rb_pid_t
rb_spawn_process(struct rb_execarg *eargp, char *errmsg, size_t errmsg_buflen)
{
    rb_pid_t pid;
#if !defined HAVE_WORKING_FORK || USE_SPAWNV
    VALUE prog;
    struct rb_execarg sarg;
# if !defined HAVE_SPAWNV
    int status;
# endif
#endif

#if defined HAVE_WORKING_FORK && !USE_SPAWNV
    pid = fork_check_err(eargp->status, rb_exec_atfork, eargp, eargp->redirect_fds, errmsg, errmsg_buflen, eargp);
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

    if (pid == -1) {
        rb_last_status_set(0x7f << 8, pid);
    }
# else
    status = system(rb_execarg_commandline(eargp, &prog));
    pid = 1;			/* dummy */
    rb_last_status_set((status & 0xff) << 8, pid);
# endif

    if (eargp->waitpid_state) {
        eargp->waitpid_state->pid = pid;
    }

    rb_execarg_run_options(&sarg, NULL, errmsg, errmsg_buflen);
#endif

    return pid;
}

struct spawn_args {
    VALUE execarg;
    struct {
        char *ptr;
        size_t buflen;
    } errmsg;
};

static VALUE
do_spawn_process(VALUE arg)
{
    struct spawn_args *argp = (struct spawn_args *)arg;

    rb_execarg_parent_start1(argp->execarg);

    return (VALUE)rb_spawn_process(rb_execarg_get(argp->execarg),
                                   argp->errmsg.ptr, argp->errmsg.buflen);
}

NOINLINE(static rb_pid_t
         rb_execarg_spawn(VALUE execarg_obj, char *errmsg, size_t errmsg_buflen));

static rb_pid_t
rb_execarg_spawn(VALUE execarg_obj, char *errmsg, size_t errmsg_buflen)
{
    struct spawn_args args;

    args.execarg = execarg_obj;
    args.errmsg.ptr = errmsg;
    args.errmsg.buflen = errmsg_buflen;

    rb_pid_t r = (rb_pid_t)rb_ensure(do_spawn_process, (VALUE)&args,
                                     execarg_parent_end, execarg_obj);
    return r;
}

static rb_pid_t
rb_spawn_internal(int argc, const VALUE *argv, char *errmsg, size_t errmsg_buflen)
{
    VALUE execarg_obj;

    execarg_obj = rb_execarg_new(argc, argv, TRUE, FALSE);
    return rb_execarg_spawn(execarg_obj, errmsg, errmsg_buflen);
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
 *    system([env, ] command_line, options = {}, exception: false) -> true, false, or nil
 *    system([env, ] exe_path, *args, options  = {}, exception: false) -> true, false, or nil
 *
 *  Creates a new child process by doing one of the following
 *  in that process:
 *
 *  - Passing string +command_line+ to the shell.
 *  - Invoking the executable at +exe_path+.
 *
 *  This method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  Returns:
 *
 *  - +true+ if the command exits with status zero.
 *  - +false+ if the exit status is a non-zero integer.
 *  - +nil+ if the command could not execute.
 *
 *  Raises an exception (instead of returning +false+ or +nil+)
 *  if keyword argument +exception+ is set to +true+.
 *
 *  Assigns the command's error status to <tt>$?</tt>.
 *
 *  The new process is created using the
 *  {system system call}[https://pubs.opengroup.org/onlinepubs/9699919799.2018edition/functions/system.html];
 *  it may inherit some of its environment from the calling program
 *  (possibly including open file descriptors).
 *
 *  Argument +env+, if given, is a hash that affects +ENV+ for the new process;
 *  see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
 *
 *  Argument +options+ is a hash of options for the new process;
 *  see {Execution Options}[rdoc-ref:Process@Execution+Options].
 *
 *  The first required argument is one of the following:
 *
 *  - +command_line+ if it is a string,
 *    and if it begins with a shell reserved word or special built-in,
 *    or if it contains one or more meta characters.
 *  - +exe_path+ otherwise.
 *
 *  <b>Argument +command_line+</b>
 *
 *  \String argument +command_line+ is a command line to be passed to a shell;
 *  it must begin with a shell reserved word, begin with a special built-in,
 *  or contain meta characters:
 *
 *    system('if true; then echo "Foo"; fi')          # => true  # Shell reserved word.
 *    system('exit')                                  # => true  # Built-in.
 *    system('date > /tmp/date.tmp')                  # => true  # Contains meta character.
 *    system('date > /nop/date.tmp')                  # => false
 *    system('date > /nop/date.tmp', exception: true) # Raises RuntimeError.
 *
 *  Assigns the command's error status to <tt>$?</tt>:
 *
 *    system('exit')                             # => true  # Built-in.
 *    $?                                         # => #<Process::Status: pid 640610 exit 0>
 *    system('date > /nop/date.tmp')             # => false
 *    $?                                         # => #<Process::Status: pid 640742 exit 2>
 *
 *  The command line may also contain arguments and options for the command:
 *
 *    system('echo "Foo"') # => true
 *
 *  Output:
 *
 *    Foo
 *
 *  See {Execution Shell}[rdoc-ref:Process@Execution+Shell] for details about the shell.
 *
 *  Raises an exception if the new process could not execute.
 *
 *  <b>Argument +exe_path+</b>
 *
 *  Argument +exe_path+ is one of the following:
 *
 *  - The string path to an executable to be called.
 *  - A 2-element array containing the path to an executable
 *    and the string to be used as the name of the executing process.
 *
 *  Example:
 *
 *    system('/usr/bin/date') # => true # Path to date on Unix-style system.
 *    system('foo')           # => nil  # Command failed.
 *
 *  Output:
 *
 *    Mon Aug 28 11:43:10 AM CDT 2023
 *
 *  Assigns the command's error status to <tt>$?</tt>:
 *
 *    system('/usr/bin/date') # => true
 *    $?                      # => #<Process::Status: pid 645605 exit 0>
 *    system('foo')           # => nil
 *    $?                      # => #<Process::Status: pid 645608 exit 127>
 *
 *  Ruby invokes the executable directly.
 *  This form does not use the shell;
 *  see {Arguments args}[rdoc-ref:Process@Arguments+args] for caveats.
 *
 *    system('doesnt_exist') # => nil
 *
 *  If one or more +args+ is given, each is an argument or option
 *  to be passed to the executable:
 *
 *    system('echo', 'C*')             # => true
 *    system('echo', 'hello', 'world') # => true
 *
 *  Output:
 *
 *    C*
 *    hello world
 *
 *  Raises an exception if the new process could not execute.
 */

static VALUE
rb_f_system(int argc, VALUE *argv, VALUE _)
{
    rb_thread_t *th = GET_THREAD();
    VALUE execarg_obj = rb_execarg_new(argc, argv, TRUE, TRUE);
    struct rb_execarg *eargp = rb_execarg_get(execarg_obj);

    struct rb_process_status status = {0};
    eargp->status = &status;

    last_status_clear(th);

    // This function can set the thread's last status.
    // May be different from waitpid_state.pid on exec failure.
    rb_pid_t pid = rb_execarg_spawn(execarg_obj, 0, 0);

    if (pid > 0) {
        VALUE status = rb_process_status_wait(pid, 0);
        struct rb_process_status *data = rb_check_typeddata(status, &rb_process_status_type);
        // Set the last status:
        rb_obj_freeze(status);
        th->last_status = status;

        if (data->status == EXIT_SUCCESS) {
            return Qtrue;
        }

        if (data->error != 0) {
            if (eargp->exception) {
                VALUE command = eargp->invoke.sh.shell_script;
                RB_GC_GUARD(execarg_obj);
                rb_syserr_fail_str(data->error, command);
            }
            else {
                return Qnil;
            }
        }
        else if (eargp->exception) {
            VALUE command = eargp->invoke.sh.shell_script;
            VALUE str = rb_str_new_cstr("Command failed with");
            rb_str_cat_cstr(pst_message_status(str, data->status), ": ");
            rb_str_append(str, command);
            RB_GC_GUARD(execarg_obj);
            rb_exc_raise(rb_exc_new_str(rb_eRuntimeError, str));
        }
        else {
            return Qfalse;
        }

        RB_GC_GUARD(status);
    }

    if (eargp->exception) {
        VALUE command = eargp->invoke.sh.shell_script;
        RB_GC_GUARD(execarg_obj);
        rb_syserr_fail_str(errno, command);
    }
    else {
        return Qnil;
    }
}

/*
 *  call-seq:
 *    spawn([env, ] command_line, options = {}) -> pid
 *    spawn([env, ] exe_path, *args, options  = {}) -> pid
 *
 *  Creates a new child process by doing one of the following
 *  in that process:
 *
 *  - Passing string +command_line+ to the shell.
 *  - Invoking the executable at +exe_path+.
 *
 *  This method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  Returns the process ID (pid) of the new process,
 *  without waiting for it to complete.
 *
 *  To avoid zombie processes, the parent process should call either:
 *
 *  - Process.wait, to collect the termination statuses of its children.
 *  - Process.detach, to register disinterest in their status.
 *
 *  The new process is created using the
 *  {exec system call}[https://pubs.opengroup.org/onlinepubs/9699919799.2018edition/functions/execve.html];
 *  it may inherit some of its environment from the calling program
 *  (possibly including open file descriptors).
 *
 *  Argument +env+, if given, is a hash that affects +ENV+ for the new process;
 *  see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
 *
 *  Argument +options+ is a hash of options for the new process;
 *  see {Execution Options}[rdoc-ref:Process@Execution+Options].
 *
 *  The first required argument is one of the following:
 *
 *  - +command_line+ if it is a string,
 *    and if it begins with a shell reserved word or special built-in,
 *    or if it contains one or more meta characters.
 *  - +exe_path+ otherwise.
 *
 *  <b>Argument +command_line+</b>
 *
 *  \String argument +command_line+ is a command line to be passed to a shell;
 *  it must begin with a shell reserved word, begin with a special built-in,
 *  or contain meta characters:
 *
 *    spawn('if true; then echo "Foo"; fi') # => 798847 # Shell reserved word.
 *    Process.wait                          # => 798847
 *    spawn('exit')                         # => 798848 # Built-in.
 *    Process.wait                          # => 798848
 *    spawn('date > /tmp/date.tmp')         # => 798879 # Contains meta character.
 *    Process.wait                          # => 798849
 *    spawn('date > /nop/date.tmp')         # => 798882 # Issues error message.
 *    Process.wait                          # => 798882
 *
 *  The command line may also contain arguments and options for the command:
 *
 *    spawn('echo "Foo"') # => 799031
 *    Process.wait        # => 799031
 *
 *  Output:
 *
 *    Foo
 *
 *  See {Execution Shell}[rdoc-ref:Process@Execution+Shell] for details about the shell.
 *
 *  Raises an exception if the new process could not execute.
 *
 *  <b>Argument +exe_path+</b>
 *
 *  Argument +exe_path+ is one of the following:
 *
 *  - The string path to an executable to be called.
 *  - A 2-element array containing the path to an executable to be called,
 *    and the string to be used as the name of the executing process.
 *
 *      spawn('/usr/bin/date') # Path to date on Unix-style system.
 *      Process.wait
 *
 *    Output:
 *
 *      Mon Aug 28 11:43:10 AM CDT 2023
 *
 *  Ruby invokes the executable directly.
 *  This form does not use the shell;
 *  see {Arguments args}[rdoc-ref:Process@Arguments+args] for caveats.
 *
 *  If one or more +args+ is given, each is an argument or option
 *  to be passed to the executable:
 *
 *    spawn('echo', 'C*')             # => 799392
 *    Process.wait                    # => 799392
 *    spawn('echo', 'hello', 'world') # => 799393
 *    Process.wait                    # => 799393
 *
 *  Output:
 *
 *    C*
 *    hello world
 *
 *  Raises an exception if the new process could not execute.
 */

static VALUE
rb_f_spawn(int argc, VALUE *argv, VALUE _)
{
    rb_pid_t pid;
    char errmsg[CHILD_ERRMSG_BUFLEN] = { '\0' };
    VALUE execarg_obj, fail_str;
    struct rb_execarg *eargp;

    execarg_obj = rb_execarg_new(argc, argv, TRUE, FALSE);
    eargp = rb_execarg_get(execarg_obj);
    fail_str = eargp->use_shell ? eargp->invoke.sh.shell_script : eargp->invoke.cmd.command_name;

    pid = rb_execarg_spawn(execarg_obj, errmsg, sizeof(errmsg));

    if (pid == -1) {
        int err = errno;
        rb_exec_fail(eargp, err, errmsg);
        RB_GC_GUARD(execarg_obj);
        rb_syserr_fail_str(err, fail_str);
    }
#if defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)
    return PIDT2NUM(pid);
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *    sleep(secs = nil) -> slept_secs
 *
 *  Suspends execution of the current thread for the number of seconds
 *  specified by numeric argument +secs+, or forever if +secs+ is +nil+;
 *  returns the integer number of seconds suspended (rounded).
 *
 *    Time.new  # => 2008-03-08 19:56:19 +0900
 *    sleep 1.2 # => 1
 *    Time.new  # => 2008-03-08 19:56:20 +0900
 *    sleep 1.9 # => 2
 *    Time.new  # => 2008-03-08 19:56:22 +0900
 *
 */

static VALUE
rb_f_sleep(int argc, VALUE *argv, VALUE _)
{
    time_t beg = time(0);
    VALUE scheduler = rb_fiber_scheduler_current();

    if (scheduler != Qnil) {
        rb_fiber_scheduler_kernel_sleepv(scheduler, argc, argv);
    }
    else {
        if (argc == 0 || (argc == 1 && NIL_P(argv[0]))) {
            rb_thread_sleep_forever();
        }
        else {
            rb_check_arity(argc, 0, 1);
            rb_thread_wait_for(rb_time_interval(argv[0]));
        }
    }

    time_t end = time(0) - beg;

    return TIMET2NUM(end);
}


#if (defined(HAVE_GETPGRP) && defined(GETPGRP_VOID)) || defined(HAVE_GETPGID)
/*
 *  call-seq:
 *    Process.getpgrp -> integer
 *
 *  Returns the process group ID for the current process:
 *
 *    Process.getpgid(0) # => 25527
 *    Process.getpgrp    # => 25527
 *
 */

static VALUE
proc_getpgrp(VALUE _)
{
    rb_pid_t pgrp;

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
 *    Process.setpgrp -> 0
 *
 *  Equivalent to <tt>setpgid(0, 0)</tt>.
 *
 *  Not available on all platforms.
 */

static VALUE
proc_setpgrp(VALUE _)
{
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
 *    Process.getpgid(pid) -> integer
 *
 *  Returns the process group ID for the given process ID +pid+:
 *
 *    Process.getpgid(Process.ppid) # => 25527
 *
 * Not available on all platforms.
 */

static VALUE
proc_getpgid(VALUE obj, VALUE pid)
{
    rb_pid_t i;

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
 *    Process.setpgid(pid, pgid) -> 0
 *
 *  Sets the process group ID for the process given by process ID +pid+
 *  to +pgid+.
 *
 *  Not available on all platforms.
 */

static VALUE
proc_setpgid(VALUE obj, VALUE pid, VALUE pgrp)
{
    rb_pid_t ipid, ipgrp;

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
 *    Process.getsid(pid = nil) -> integer
 *
 *  Returns the session ID of the given process ID +pid+,
 *  or of the current process if not given:
 *
 *    Process.getsid                # => 27422
 *    Process.getsid(0)             # => 27422
 *    Process.getsid(Process.pid()) # => 27422
 *
 *  Not available on all platforms.
 */
static VALUE
proc_getsid(int argc, VALUE *argv, VALUE _)
{
    rb_pid_t sid;
    rb_pid_t pid = 0;

    if (rb_check_arity(argc, 0, 1) == 1 && !NIL_P(argv[0]))
        pid = NUM2PIDT(argv[0]);

    sid = getsid(pid);
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
 *    Process.setsid -> integer
 *
 *  Establishes the current process as a new session and process group leader,
 *  with no controlling tty;
 *  returns the session ID:
 *
 *    Process.setsid # => 27422
 *
 *  Not available on all platforms.
 */

static VALUE
proc_setsid(VALUE _)
{
    rb_pid_t pid;

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
 *    Process.getpriority(kind, id)   -> integer
 *
 *  Returns the scheduling priority for specified process, process group,
 *  or user.
 *
 *  Argument +kind+ is one of:
 *
 *  - Process::PRIO_PROCESS: return priority for process.
 *  - Process::PRIO_PGRP: return priority for process group.
 *  - Process::PRIO_USER: return priority for user.
 *
 *  Argument +id+ is the ID for the process, process group, or user;
 *  zero specified the current ID for +kind+.
 *
 *  Examples:
 *
 *    Process.getpriority(Process::PRIO_USER, 0)    # => 19
 *    Process.getpriority(Process::PRIO_PROCESS, 0) # => 19
 *
 *  Not available on all platforms.
 */

static VALUE
proc_getpriority(VALUE obj, VALUE which, VALUE who)
{
    int prio, iwhich, iwho;

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
 *    Process.setpriority(kind, integer, priority) -> 0
 *
 *  See Process.getpriority.
 *
 *  Examples:
 *
 *    Process.setpriority(Process::PRIO_USER, 0, 19)    # => 0
 *    Process.setpriority(Process::PRIO_PROCESS, 0, 19) # => 0
 *    Process.getpriority(Process::PRIO_USER, 0)        # => 19
 *    Process.getpriority(Process::PRIO_PROCESS, 0)     # => 19
 *
 *  Not available on all platforms.
 */

static VALUE
proc_setpriority(VALUE obj, VALUE which, VALUE who, VALUE prio)
{
    int iwhich, iwho, iprio;

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
rlimit_resource_name2int(const char *name, long len, int casetype)
{
    int resource;
    const char *p;
#define RESCHECK(r) \
    do { \
        if (len == rb_strlen_lit(#r) && STRCASECMP(name, #r) == 0) { \
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
#ifdef RLIMIT_NPTS
        RESCHECK(NPTS);
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
rlimit_type_by_hname(const char *name, long len)
{
    return rlimit_resource_name2int(name, len, 0);
}

static int
rlimit_type_by_lname(const char *name, long len)
{
    return rlimit_resource_name2int(name, len, 1);
}

static int
rlimit_type_by_sym(VALUE key)
{
    VALUE name = rb_sym2str(key);
    const char *rname = RSTRING_PTR(name);
    long len = RSTRING_LEN(name);
    int rtype = -1;
    static const char prefix[] = "rlimit_";
    enum {prefix_len = sizeof(prefix)-1};

    if (len > prefix_len && strncmp(prefix, rname, prefix_len) == 0) {
        rtype = rlimit_type_by_lname(rname + prefix_len, len - prefix_len);
    }

    RB_GC_GUARD(key);
    return rtype;
}

static int
rlimit_resource_type(VALUE rtype)
{
    const char *name;
    long len;
    VALUE v;
    int r;

    switch (TYPE(rtype)) {
      case T_SYMBOL:
        v = rb_sym2str(rtype);
        name = RSTRING_PTR(v);
        len = RSTRING_LEN(v);
        break;

      default:
        v = rb_check_string_type(rtype);
        if (!NIL_P(v)) {
            rtype = v;
      case T_STRING:
            name = StringValueCStr(rtype);
            len = RSTRING_LEN(rtype);
            break;
        }
        /* fall through */

      case T_FIXNUM:
      case T_BIGNUM:
        return NUM2INT(rtype);
    }

    r = rlimit_type_by_hname(name, len);
    if (r != -1)
        return r;

    rb_raise(rb_eArgError, "invalid resource name: % "PRIsVALUE, rtype);

    UNREACHABLE_RETURN(-1);
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

    UNREACHABLE_RETURN((rlim_t)-1);
}
#endif

#if defined(HAVE_GETRLIMIT) && defined(RLIM2NUM)
/*
 *  call-seq:
 *    Process.getrlimit(resource) -> [cur_limit, max_limit]
 *
 *  Returns a 2-element array of the current (soft) limit
 *  and maximum (hard) limit for the given +resource+.
 *
 *  Argument +resource+ specifies the resource whose limits are to be returned;
 *  see Process.setrlimit.
 *
 *  Each of the returned values +cur_limit+ and +max_limit+ is an integer;
 *  see Process.setrlimit.
 *
 *  Example:
 *
 *    Process.getrlimit(:CORE) # => [0, 18446744073709551615]
 *
 *  See Process.setrlimit.
 *
 *  Not available on all platforms.
 */

static VALUE
proc_getrlimit(VALUE obj, VALUE resource)
{
    struct rlimit rlim;

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
 *    Process.setrlimit(resource, cur_limit, max_limit = cur_limit) -> nil
 *
 *  Sets limits for the current process for the given +resource+
 *  to +cur_limit+ (soft limit) and +max_limit+ (hard limit);
 *  returns +nil+.
 *
 *  Argument +resource+ specifies the resource whose limits are to be set;
 *  the argument may be given as a symbol, as a string, or as a constant
 *  beginning with <tt>Process::RLIMIT_</tt>
 *  (e.g., +:CORE+, <tt>'CORE'</tt>, or <tt>Process::RLIMIT_CORE</tt>.
 *
 *  The resources available and supported are system-dependent,
 *  and may include (here expressed as symbols):
 *
 *  - +:AS+: Total available memory (bytes) (SUSv3, NetBSD, FreeBSD, OpenBSD except 4.4BSD-Lite).
 *  - +:CORE+: Core size (bytes) (SUSv3).
 *  - +:CPU+: CPU time (seconds) (SUSv3).
 *  - +:DATA+: Data segment (bytes) (SUSv3).
 *  - +:FSIZE+: File size (bytes) (SUSv3).
 *  - +:MEMLOCK+: Total size for mlock(2) (bytes) (4.4BSD, GNU/Linux).
 *  - +:MSGQUEUE+: Allocation for POSIX message queues (bytes) (GNU/Linux).
 *  - +:NICE+: Ceiling on process's nice(2) value (number) (GNU/Linux).
 *  - +:NOFILE+: File descriptors (number) (SUSv3).
 *  - +:NPROC+: Number of processes for the user (number) (4.4BSD, GNU/Linux).
 *  - +:NPTS+: Number of pseudo terminals (number) (FreeBSD).
 *  - +:RSS+: Resident memory size (bytes) (4.2BSD, GNU/Linux).
 *  - +:RTPRIO+: Ceiling on the process's real-time priority (number) (GNU/Linux).
 *  - +:RTTIME+: CPU time for real-time process (us) (GNU/Linux).
 *  - +:SBSIZE+: All socket buffers (bytes) (NetBSD, FreeBSD).
 *  - +:SIGPENDING+: Number of queued signals allowed (signals) (GNU/Linux).
 *  - +:STACK+: Stack size (bytes) (SUSv3).
 *
 *  Arguments +cur_limit+ and +max_limit+ may be:
 *
 *  - Integers (+max_limit+ should not be smaller than +cur_limit+).
 *  - Symbol +:SAVED_MAX+, string <tt>'SAVED_MAX'</tt>,
 *    or constant <tt>Process::RLIM_SAVED_MAX</tt>: saved maximum limit.
 *  - Symbol +:SAVED_CUR+, string <tt>'SAVED_CUR'</tt>,
 *    or constant <tt>Process::RLIM_SAVED_CUR</tt>: saved current limit.
 *  - Symbol +:INFINITY+, string <tt>'INFINITY'</tt>,
 *    or constant <tt>Process::RLIM_INFINITY</tt>: no limit on resource.
 *
 *  This example raises the soft limit of core size to
 *  the hard limit to try to make core dump possible:
 *
 *    Process.setrlimit(:CORE, Process.getrlimit(:CORE)[1])
 *
 *  Not available on all platforms.
 */

static VALUE
proc_setrlimit(int argc, VALUE *argv, VALUE obj)
{
    VALUE resource, rlim_cur, rlim_max;
    struct rlimit rlim;

    rb_check_arity(argc, 2, 3);
    resource = argv[0];
    rlim_cur = argv[1];
    if (argc < 3 || NIL_P(rlim_max = argv[2]))
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
    if (under_uid_switch) {
        rb_raise(rb_eRuntimeError, "can't handle UID while evaluating block given to Process::UID.switch method");
    }
}

static int under_gid_switch = 0;
static void
check_gid_switch(void)
{
    if (under_gid_switch) {
        rb_raise(rb_eRuntimeError, "can't handle GID while evaluating block given to Process::UID.switch method");
    }
}


#if defined(HAVE_PWD_H)
/**
 * Best-effort attempt to obtain the name of the login user, if any,
 * associated with the process. Processes not descended from login(1) (or
 * similar) may not have a logged-in user; returns Qnil in that case.
 */
VALUE
rb_getlogin(void)
{
#if ( !defined(USE_GETLOGIN_R) && !defined(USE_GETLOGIN) )
    return Qnil;
#else
    char MAYBE_UNUSED(*login) = NULL;

# ifdef USE_GETLOGIN_R

#if defined(__FreeBSD__)
    typedef int getlogin_r_size_t;
#else
    typedef size_t getlogin_r_size_t;
#endif

    long loginsize = GETLOGIN_R_SIZE_INIT;  /* maybe -1 */

    if (loginsize < 0)
        loginsize = GETLOGIN_R_SIZE_DEFAULT;

    VALUE maybe_result = rb_str_buf_new(loginsize);

    login = RSTRING_PTR(maybe_result);
    loginsize = rb_str_capacity(maybe_result);
    rb_str_set_len(maybe_result, loginsize);

    int gle;
    errno = 0;
    while ((gle = getlogin_r(login, (getlogin_r_size_t)loginsize)) != 0) {

        if (gle == ENOTTY || gle == ENXIO || gle == ENOENT) {
            rb_str_resize(maybe_result, 0);
            return Qnil;
        }

        if (gle != ERANGE || loginsize >= GETLOGIN_R_SIZE_LIMIT) {
            rb_str_resize(maybe_result, 0);
            rb_syserr_fail(gle, "getlogin_r");
        }

        rb_str_modify_expand(maybe_result, loginsize);
        login = RSTRING_PTR(maybe_result);
        loginsize = rb_str_capacity(maybe_result);
    }

    if (login == NULL) {
        rb_str_resize(maybe_result, 0);
        return Qnil;
    }

    return maybe_result;

# elif USE_GETLOGIN

    errno = 0;
    login = getlogin();
    if (errno) {
        if (errno == ENOTTY || errno == ENXIO || errno == ENOENT) {
            return Qnil;
        }
        rb_syserr_fail(errno, "getlogin");
    }

    return login ? rb_str_new_cstr(login) : Qnil;
# endif

#endif
}

VALUE
rb_getpwdirnam_for_login(VALUE login_name)
{
#if ( !defined(USE_GETPWNAM_R) && !defined(USE_GETPWNAM) )
    return Qnil;
#else

    if (NIL_P(login_name)) {
        /* nothing to do; no name with which to query the password database */
        return Qnil;
    }

    char *login = RSTRING_PTR(login_name);

    struct passwd *pwptr;

# ifdef USE_GETPWNAM_R

    struct passwd pwdnm;
    char *bufnm;
    long bufsizenm = GETPW_R_SIZE_INIT;  /* maybe -1 */

    if (bufsizenm < 0)
        bufsizenm = GETPW_R_SIZE_DEFAULT;

    VALUE getpwnm_tmp = rb_str_tmp_new(bufsizenm);

    bufnm = RSTRING_PTR(getpwnm_tmp);
    bufsizenm = rb_str_capacity(getpwnm_tmp);
    rb_str_set_len(getpwnm_tmp, bufsizenm);

    int enm;
    errno = 0;
    while ((enm = getpwnam_r(login, &pwdnm, bufnm, bufsizenm, &pwptr)) != 0) {

        if (enm == ENOENT || enm== ESRCH || enm == EBADF || enm == EPERM) {
            /* not found; non-errors */
            rb_str_resize(getpwnm_tmp, 0);
            return Qnil;
        }

        if (enm != ERANGE || bufsizenm >= GETPW_R_SIZE_LIMIT) {
            rb_str_resize(getpwnm_tmp, 0);
            rb_syserr_fail(enm, "getpwnam_r");
        }

        rb_str_modify_expand(getpwnm_tmp, bufsizenm);
        bufnm = RSTRING_PTR(getpwnm_tmp);
        bufsizenm = rb_str_capacity(getpwnm_tmp);
    }

    if (pwptr == NULL) {
        /* no record in the password database for the login name */
        rb_str_resize(getpwnm_tmp, 0);
        return Qnil;
    }

    /* found it */
    VALUE result = rb_str_new_cstr(pwptr->pw_dir);
    rb_str_resize(getpwnm_tmp, 0);
    return result;

# elif USE_GETPWNAM

    errno = 0;
    pwptr = getpwnam(login);
    if (pwptr) {
        /* found it */
        return rb_str_new_cstr(pwptr->pw_dir);
    }
    if (errno
        /*   avoid treating as errors errno values that indicate "not found" */
        && ( errno != ENOENT && errno != ESRCH && errno != EBADF && errno != EPERM)) {
        rb_syserr_fail(errno, "getpwnam");
    }

    return Qnil;  /* not found */
# endif

#endif
}

/**
 * Look up the user's dflt home dir in the password db, by uid.
 */
VALUE
rb_getpwdiruid(void)
{
# if !defined(USE_GETPWUID_R) && !defined(USE_GETPWUID)
    /* Should never happen... </famous-last-words> */
    return Qnil;
# else
    uid_t ruid = getuid();

    struct passwd *pwptr;

# ifdef USE_GETPWUID_R

    struct passwd pwdid;
    char *bufid;
    long bufsizeid = GETPW_R_SIZE_INIT;  /* maybe -1 */

    if (bufsizeid < 0)
        bufsizeid = GETPW_R_SIZE_DEFAULT;

    VALUE getpwid_tmp = rb_str_tmp_new(bufsizeid);

    bufid = RSTRING_PTR(getpwid_tmp);
    bufsizeid = rb_str_capacity(getpwid_tmp);
    rb_str_set_len(getpwid_tmp, bufsizeid);

    int eid;
    errno = 0;
    while ((eid = getpwuid_r(ruid, &pwdid, bufid, bufsizeid, &pwptr)) != 0) {

        if (eid == ENOENT || eid== ESRCH || eid == EBADF || eid == EPERM) {
            /* not found; non-errors */
            rb_str_resize(getpwid_tmp, 0);
            return Qnil;
        }

        if (eid != ERANGE || bufsizeid >= GETPW_R_SIZE_LIMIT) {
            rb_str_resize(getpwid_tmp, 0);
            rb_syserr_fail(eid, "getpwuid_r");
        }

        rb_str_modify_expand(getpwid_tmp, bufsizeid);
        bufid = RSTRING_PTR(getpwid_tmp);
        bufsizeid = rb_str_capacity(getpwid_tmp);
    }

    if (pwptr == NULL) {
        /* no record in the password database for the uid */
        rb_str_resize(getpwid_tmp, 0);
        return Qnil;
    }

    /* found it */
    VALUE result = rb_str_new_cstr(pwptr->pw_dir);
    rb_str_resize(getpwid_tmp, 0);
    return result;

# elif defined(USE_GETPWUID)

    errno = 0;
    pwptr = getpwuid(ruid);
    if (pwptr) {
        /* found it */
        return rb_str_new_cstr(pwptr->pw_dir);
    }
    if (errno
        /*   avoid treating as errors errno values that indicate "not found" */
        && ( errno == ENOENT || errno == ESRCH || errno == EBADF || errno == EPERM)) {
        rb_syserr_fail(errno, "getpwuid");
    }

    return Qnil;  /* not found */
# endif

#endif /* !defined(USE_GETPWUID_R) && !defined(USE_GETPWUID) */
}
#endif /* HAVE_PWD_H */


/*********************************************************************
 * Document-class: Process::Sys
 *
 *  The Process::Sys module contains UID and GID
 *  functions which provide direct bindings to the system calls of the
 *  same names instead of the more-portable versions of the same
 *  functionality found in the Process,
 *  Process::UID, and Process::GID modules.
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
        int e;
        if (!*getpw_tmp) {
            getpw_buf_len = GETPW_R_SIZE_INIT;
            if (getpw_buf_len < 0) getpw_buf_len = GETPW_R_SIZE_DEFAULT;
            *getpw_tmp = rb_str_tmp_new(getpw_buf_len);
        }
        getpw_buf = RSTRING_PTR(*getpw_tmp);
        getpw_buf_len = rb_str_capacity(*getpw_tmp);
        rb_str_set_len(*getpw_tmp, getpw_buf_len);
        errno = 0;
        while ((e = getpwnam_r(usrname, &pwbuf, getpw_buf, getpw_buf_len, &pwptr)) != 0) {
            if (e != ERANGE || getpw_buf_len >= GETPW_R_SIZE_LIMIT) {
                rb_str_resize(*getpw_tmp, 0);
                rb_syserr_fail(e, "getpwnam_r");
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
            rb_raise(rb_eArgError, "can't find user for %"PRIsVALUE, id);
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
        int e;
        if (!*getgr_tmp) {
            getgr_buf_len = GETGR_R_SIZE_INIT;
            if (getgr_buf_len < 0) getgr_buf_len = GETGR_R_SIZE_DEFAULT;
            *getgr_tmp = rb_str_tmp_new(getgr_buf_len);
        }
        getgr_buf = RSTRING_PTR(*getgr_tmp);
        getgr_buf_len = rb_str_capacity(*getgr_tmp);
        rb_str_set_len(*getgr_tmp, getgr_buf_len);
        errno = 0;
        while ((e = getgrnam_r(grpname, &grbuf, getgr_buf, getgr_buf_len, &grptr)) != 0) {
            if (e != ERANGE || getgr_buf_len >= GETGR_R_SIZE_LIMIT) {
                rb_str_resize(*getgr_tmp, 0);
                rb_syserr_fail(e, "getgrnam_r");
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
            rb_raise(rb_eArgError, "can't find group for %"PRIsVALUE, id);
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
 *    Process.uid         -> integer
 *    Process::UID.rid    -> integer
 *    Process::Sys.getuid -> integer
 *
 *  Returns the (real) user ID of the current process.
 *
 *    Process.uid # => 1000
 *
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
 *    Process.uid = new_uid -> new_uid
 *
 *  Sets the (user) user ID for the current process to +new_uid+:
 *
 *    Process.uid = 1000 # => 1000
 *
 *  Not available on all platforms.
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
 *  The Process::UID module contains a collection of
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
 *     Process::UID.change_privilege(user)   -> integer
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
            rb_syserr_fail(EPERM, 0);
        }
#elif defined HAVE_44BSD_SETUID
        if (getuid() == uid) {
            /* (r,e,s)==(uid,?,?) ==> (uid,uid,uid) */
            if (setuid(uid) < 0) rb_sys_fail(0);
            SAVED_USER_ID = uid;
        }
        else {
            rb_syserr_fail(EPERM, 0);
        }
#elif defined HAVE_SETEUID
        if (getuid() == uid && SAVED_USER_ID == uid) {
            if (seteuid(uid) < 0) rb_sys_fail(0);
        }
        else {
            rb_syserr_fail(EPERM, 0);
        }
#elif defined HAVE_SETUID
        if (getuid() == uid && SAVED_USER_ID == uid) {
            if (setuid(uid) < 0) rb_sys_fail(0);
        }
        else {
            rb_syserr_fail(EPERM, 0);
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
    check_gid_switch();
    rgid = OBJ2GID(rid);
    egid = OBJ2GID(eid);
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
    check_gid_switch();
    rgid = OBJ2GID(rid);
    egid = OBJ2GID(eid);
    sgid = OBJ2GID(sid);
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
    return RBOOL(issetugid());
}
#else
#define p_sys_issetugid rb_f_notimplement
#endif


/*
 *  call-seq:
 *    Process.gid         -> integer
 *    Process::GID.rid    -> integer
 *    Process::Sys.getgid -> integer
 *
 *  Returns the (real) group ID for the current process:
 *
 *    Process.gid # => 1000
 *
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
 *    Process.gid = new_gid -> new_gid
 *
 *  Sets the group ID for the current process to +new_gid+:
 *
 *    Process.gid = 1000 # => 1000
 *
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
 *    Process.groups -> array
 *
 *  Returns an array of the group IDs
 *  in the supplemental group access list for the current process:
 *
 *    Process.groups # => [4, 24, 27, 30, 46, 122, 135, 136, 1000]
 *
 *  These properties of the returned array are system-dependent:
 *
 *  - Whether (and how) the array is sorted.
 *  - Whether the array includes effective group IDs.
 *  - Whether the array includes duplicate group IDs.
 *  - Whether the array size exceeds the value of Process.maxgroups.
 *
 *  Use this call to get a sorted and unique array:
 *
 *    Process.groups.uniq.sort
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
 *    Process.groups = new_groups -> new_groups
 *
 *  Sets the supplemental group access list to the given
 *  array of group IDs.
 *
 *    Process.groups                     # => [0, 1, 2, 3, 4, 6, 10, 11, 20, 26, 27]
 *    Process.groups = [27, 6, 10, 11]   # => [27, 6, 10, 11]
 *    Process.groups                     # => [27, 6, 10, 11]
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
 *     Process.initgroups(username, gid) -> array
 *
 *  Sets the supplemental group access list;
 *  the new list includes:
 *
 *  - The group IDs of those groups to which the user given by +username+ belongs.
 *  - The group ID +gid+.
 *
 *  Example:
 *
 *     Process.groups                # => [0, 1, 2, 3, 4, 6, 10, 11, 20, 26, 27]
 *     Process.initgroups('me', 30)  # => [30, 6, 10, 11]
 *     Process.groups                # => [30, 6, 10, 11]
 *
 *  Not available on all platforms.
 */

static VALUE
proc_initgroups(VALUE obj, VALUE uname, VALUE base_grp)
{
    if (initgroups(StringValueCStr(uname), OBJ2GID(base_grp)) != 0) {
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
 *    Process.maxgroups -> integer
 *
 *  Returns the maximum number of group IDs allowed
 *  in the supplemental group access list:
 *
 *    Process.maxgroups # => 32
 *
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
 *    Process.maxgroups = new_max -> new_max
 *
 *  Sets the maximum number of group IDs allowed
 *  in the supplemental group access list.
 */

static VALUE
proc_setmaxgroups(VALUE obj, VALUE val)
{
    int ngroups = FIX2INT(val);
    int ngroups_max = get_sc_ngroups_max();

    if (ngroups <= 0)
        rb_raise(rb_eArgError, "maxgroups %d should be positive", ngroups);

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
 *    Process.daemon(nochdir = nil, noclose = nil) -> 0
 *
 *  Detaches the current process from its controlling terminal
 *  and runs it in the background as system daemon;
 *  returns zero.
 *
 *  By default:
 *
 *  - Changes the current working directory to the root directory.
 *  - Redirects $stdin, $stdout, and $stderr to the null device.
 *
 *  If optional argument +nochdir+ is +true+,
 *  does not change the current working directory.
 *
 *  If optional argument +noclose+ is +true+,
 *  does not redirect $stdin, $stdout, or $stderr.
 */

static VALUE
proc_daemon(int argc, VALUE *argv, VALUE _)
{
    int n, nochdir = FALSE, noclose = FALSE;

    switch (rb_check_arity(argc, 0, 2)) {
      case 2: noclose = TO_BOOL(argv[1], "noclose");
      case 1: nochdir = TO_BOOL(argv[0], "nochdir");
    }

    prefork();
    n = rb_daemon(nochdir, noclose);
    if (n < 0) rb_sys_fail("daemon");
    return INT2FIX(n);
}

extern const char ruby_null_device[];

static int
rb_daemon(int nochdir, int noclose)
{
    int err = 0;
#ifdef HAVE_DAEMON
    before_fork_ruby();
    err = daemon(nochdir, noclose);
    after_fork_ruby(0);
#else
    int n;

    switch (rb_fork_ruby(NULL)) {
      case -1: return -1;
      case 0:  break;
      default: _exit(EXIT_SUCCESS);
    }

    /* ignore EPERM which means already being process-leader */
    if (setsid() < 0) (void)0;

    if (!nochdir)
        err = chdir("/");

    if (!noclose && (n = rb_cloexec_open(ruby_null_device, O_RDWR, 0)) != -1) {
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
 *  The Process::GID module contains a collection of
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
 *     Process::GID.change_privilege(group)   -> integer
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
            rb_syserr_fail(EPERM, 0);
        }
#elif defined HAVE_44BSD_SETGID
        if (getgid() == gid) {
            /* (r,e,s)==(gid,?,?) ==> (gid,gid,gid) */
            if (setgid(gid) < 0) rb_sys_fail(0);
            SAVED_GROUP_ID = gid;
        }
        else {
            rb_syserr_fail(EPERM, 0);
        }
#elif defined HAVE_SETEGID
        if (getgid() == gid && SAVED_GROUP_ID == gid) {
            if (setegid(gid) < 0) rb_sys_fail(0);
        }
        else {
            rb_syserr_fail(EPERM, 0);
        }
#elif defined HAVE_SETGID
        if (getgid() == gid && SAVED_GROUP_ID == gid) {
            if (setgid(gid) < 0) rb_sys_fail(0);
        }
        else {
            rb_syserr_fail(EPERM, 0);
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
 *    Process.euid         -> integer
 *    Process::UID.eid     -> integer
 *    Process::Sys.geteuid -> integer
 *
 *  Returns the effective user ID for the current process.
 *
 *    Process.euid # => 501
 *
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
 *    Process.euid = new_euid -> new_euid
 *
 *  Sets the effective user ID for the current process.
 *
 *  Not available on all platforms.
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
 *     Process::UID.grant_privilege(user)   -> integer
 *     Process::UID.eid= user               -> integer
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
 *    Process.egid        -> integer
 *    Process::GID.eid    -> integer
 *    Process::Sys.geteid -> integer
 *
 *  Returns the effective group ID for the current process:
 *
 *    Process.egid # => 500
 *
 *  Not available on all platforms.
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
 *    Process.egid = new_egid -> new_egid
 *
 *  Sets the effective group ID for the current process.
 *
 *  Not available on all platforms.
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
 *     Process::GID.grant_privilege(group)    -> integer
 *     Process::GID.eid = group               -> integer
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
p_uid_exchangeable(VALUE _)
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
 *     Process::UID.re_exchange   -> integer
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
p_gid_exchangeable(VALUE _)
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
 *     Process::GID.re_exchange   -> integer
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
p_uid_have_saved_id(VALUE _)
{
#if defined(HAVE_SETRESUID) || defined(HAVE_SETEUID) || defined(_POSIX_SAVED_IDS)
    return Qtrue;
#else
    return Qfalse;
#endif
}


#if defined(HAVE_SETRESUID) || defined(HAVE_SETEUID) || defined(_POSIX_SAVED_IDS)
static VALUE
p_uid_sw_ensure(VALUE i)
{
    rb_uid_t id = (rb_uid_t/* narrowing */)i;
    under_uid_switch = 0;
    id = rb_seteuid_core(id);
    return UIDT2NUM(id);
}


/*
 *  call-seq:
 *     Process::UID.switch              -> integer
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
        rb_syserr_fail(EPERM, 0);
    }

    UNREACHABLE_RETURN(Qnil);
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
        rb_syserr_fail(EPERM, 0);
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
p_gid_have_saved_id(VALUE _)
{
#if defined(HAVE_SETRESGID) || defined(HAVE_SETEGID) || defined(_POSIX_SAVED_IDS)
    return Qtrue;
#else
    return Qfalse;
#endif
}

#if defined(HAVE_SETRESGID) || defined(HAVE_SETEGID) || defined(_POSIX_SAVED_IDS)
static VALUE
p_gid_sw_ensure(VALUE i)
{
    rb_gid_t id = (rb_gid_t/* narrowing */)i;
    under_gid_switch = 0;
    id = rb_setegid_core(id);
    return GIDT2NUM(id);
}


/*
 *  call-seq:
 *     Process::GID.switch              -> integer
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
        rb_syserr_fail(EPERM, 0);
    }

    UNREACHABLE_RETURN(Qnil);
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
        rb_syserr_fail(EPERM, 0);
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
#ifdef HAVE__SC_CLK_TCK
    return sysconf(_SC_CLK_TCK);
#elif defined CLK_TCK
    return CLK_TCK;
#elif defined HZ
    return HZ;
#else
    return 60;
#endif
}

/*
 *  call-seq:
 *    Process.times -> process_tms
 *
 *  Returns a Process::Tms structure that contains user and system CPU times
 *  for the current process, and for its children processes:
 *
 *    Process.times
 *    # => #<struct Process::Tms utime=55.122118, stime=35.533068, cutime=0.0, cstime=0.002846>
 *
 *  The precision is platform-defined.
 */

VALUE
rb_proc_times(VALUE obj)
{
    VALUE utime, stime, cutime, cstime, ret;
#if defined(RUSAGE_SELF) && defined(RUSAGE_CHILDREN)
    struct rusage usage_s, usage_c;

    if (getrusage(RUSAGE_SELF, &usage_s) != 0 || getrusage(RUSAGE_CHILDREN, &usage_c) != 0)
        rb_sys_fail("getrusage");
    utime = DBL2NUM((double)usage_s.ru_utime.tv_sec + (double)usage_s.ru_utime.tv_usec/1e6);
    stime = DBL2NUM((double)usage_s.ru_stime.tv_sec + (double)usage_s.ru_stime.tv_usec/1e6);
    cutime = DBL2NUM((double)usage_c.ru_utime.tv_sec + (double)usage_c.ru_utime.tv_usec/1e6);
    cstime = DBL2NUM((double)usage_c.ru_stime.tv_sec + (double)usage_c.ru_stime.tv_usec/1e6);
#else
    const double hertz = (double)get_clk_tck();
    struct tms buf;

    times(&buf);
    utime = DBL2NUM(buf.tms_utime / hertz);
    stime = DBL2NUM(buf.tms_stime / hertz);
    cutime = DBL2NUM(buf.tms_cutime / hertz);
    cstime = DBL2NUM(buf.tms_cstime / hertz);
#endif
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
#define MUL_OVERFLOW_TIMETICK_P(a, b) MUL_OVERFLOW_LONG_LONG_P(a, b)
#else
typedef long timetick_int_t;
#define TIMETICK_INT_MIN LONG_MIN
#define TIMETICK_INT_MAX LONG_MAX
#define TIMETICK_INT2NUM(v) LONG2NUM(v)
#define MUL_OVERFLOW_TIMETICK_P(a, b) MUL_OVERFLOW_LONG_P(a, b)
#endif

CONSTFUNC(static timetick_int_t gcd_timetick_int(timetick_int_t, timetick_int_t));
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
            if (MUL_OVERFLOW_TIMETICK_P(factor, t))
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
static const mach_timebase_info_data_t *
get_mach_timebase_info(void)
{
    static mach_timebase_info_data_t sTimebaseInfo;

    if ( sTimebaseInfo.denom == 0 ) {
        (void) mach_timebase_info(&sTimebaseInfo);
    }

    return &sTimebaseInfo;
}

double
ruby_real_ms_time(void)
{
    const mach_timebase_info_data_t *info = get_mach_timebase_info();
    uint64_t t = mach_absolute_time();
    return (double)t * info->numer / info->denom / 1e6;
}
#endif

#if defined(NUM2CLOCKID)
# define NUMERIC_CLOCKID 1
#else
# define NUMERIC_CLOCKID 0
# define NUM2CLOCKID(x) 0
#endif

#define clock_failed(name, err, arg) do { \
        int clock_error = (err); \
        rb_syserr_fail_str(clock_error, rb_sprintf("clock_" name "(%+"PRIsVALUE")", (arg))); \
    } while (0)

/*
 *  call-seq:
 *    Process.clock_gettime(clock_id, unit = :float_second) -> number
 *
 *  Returns a clock time as determined by POSIX function
 *  {clock_gettime()}[https://man7.org/linux/man-pages/man3/clock_gettime.3.html]:
 *
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID) # => 198.650379677
 *
 *  Argument +clock_id+ should be a symbol or a constant that specifies
 *  the clock whose time is to be returned;
 *  see below.
 *
 *  Optional argument +unit+ should be a symbol that specifies
 *  the unit to be used in the returned clock time;
 *  see below.
 *
 *  <b>Argument +clock_id+</b>
 *
 *  Argument +clock_id+ specifies the clock whose time is to be returned;
 *  it may be a constant such as <tt>Process::CLOCK_REALTIME</tt>,
 *  or a symbol shorthand such as +:CLOCK_REALTIME+.
 *
 *  The supported clocks depend on the underlying operating system;
 *  this method supports the following clocks on the indicated platforms
 *  (raises Errno::EINVAL if called with an unsupported clock):
 *
 *  - +:CLOCK_BOOTTIME+: Linux 2.6.39.
 *  - +:CLOCK_BOOTTIME_ALARM+: Linux 3.0.
 *  - +:CLOCK_MONOTONIC+: SUSv3 to 4, Linux 2.5.63, FreeBSD 3.0, NetBSD 2.0, OpenBSD 3.4, macOS 10.12, Windows-2000.
 *  - +:CLOCK_MONOTONIC_COARSE+: Linux 2.6.32.
 *  - +:CLOCK_MONOTONIC_FAST+: FreeBSD 8.1.
 *  - +:CLOCK_MONOTONIC_PRECISE+: FreeBSD 8.1.
 *  - +:CLOCK_MONOTONIC_RAW+: Linux 2.6.28, macOS 10.12.
 *  - +:CLOCK_MONOTONIC_RAW_APPROX+: macOS 10.12.
 *  - +:CLOCK_PROCESS_CPUTIME_ID+: SUSv3 to 4, Linux 2.5.63, FreeBSD 9.3, OpenBSD 5.4, macOS 10.12.
 *  - +:CLOCK_PROF+: FreeBSD 3.0, OpenBSD 2.1.
 *  - +:CLOCK_REALTIME+: SUSv2 to 4, Linux 2.5.63, FreeBSD 3.0, NetBSD 2.0, OpenBSD 2.1, macOS 10.12, Windows-8/Server-2012.
 *    Time.now is recommended over +:CLOCK_REALTIME:.
 *  - +:CLOCK_REALTIME_ALARM+: Linux 3.0.
 *  - +:CLOCK_REALTIME_COARSE+: Linux 2.6.32.
 *  - +:CLOCK_REALTIME_FAST+: FreeBSD 8.1.
 *  - +:CLOCK_REALTIME_PRECISE+: FreeBSD 8.1.
 *  - +:CLOCK_SECOND+: FreeBSD 8.1.
 *  - +:CLOCK_TAI+: Linux 3.10.
 *  - +:CLOCK_THREAD_CPUTIME_ID+: SUSv3 to 4, Linux 2.5.63, FreeBSD 7.1, OpenBSD 5.4, macOS 10.12.
 *  - +:CLOCK_UPTIME+: FreeBSD 7.0, OpenBSD 5.5.
 *  - +:CLOCK_UPTIME_FAST+: FreeBSD 8.1.
 *  - +:CLOCK_UPTIME_PRECISE+: FreeBSD 8.1.
 *  - +:CLOCK_UPTIME_RAW+: macOS 10.12.
 *  - +:CLOCK_UPTIME_RAW_APPROX+: macOS 10.12.
 *  - +:CLOCK_VIRTUAL+: FreeBSD 3.0, OpenBSD 2.1.
 *
 *  Note that SUS stands for Single Unix Specification.
 *  SUS contains POSIX and clock_gettime is defined in the POSIX part.
 *  SUS defines +:CLOCK_REALTIME+ as mandatory but
 *  +:CLOCK_MONOTONIC+, +:CLOCK_PROCESS_CPUTIME_ID+,
 *  and +:CLOCK_THREAD_CPUTIME_ID+ are optional.
 *
 *  Certain emulations are used when the given +clock_id+
 *  is not supported directly:
 *
 *  - Emulations for +:CLOCK_REALTIME+:
 *
 *    - +:GETTIMEOFDAY_BASED_CLOCK_REALTIME+:
 *      Use gettimeofday() defined by SUS (deprecated in SUSv4).
 *      The resolution is 1 microsecond.
 *    - +:TIME_BASED_CLOCK_REALTIME+:
 *      Use time() defined by ISO C.
 *      The resolution is 1 second.
 *
 *  - Emulations for +:CLOCK_MONOTONIC+:
 *
 *    - +:MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC+:
 *      Use mach_absolute_time(), available on Darwin.
 *      The resolution is CPU dependent.
 *    - +:TIMES_BASED_CLOCK_MONOTONIC+:
 *      Use the result value of times() defined by POSIX, thus:
 *      >>>
 *        Upon successful completion, times() shall return the elapsed real time,
 *        in clock ticks, since an arbitrary point in the past
 *        (for example, system start-up time).
 *
 *      For example, GNU/Linux returns a value based on jiffies and it is monotonic.
 *      However, 4.4BSD uses gettimeofday() and it is not monotonic.
 *      (FreeBSD uses +:CLOCK_MONOTONIC+ instead, though.)
 *
 *      The resolution is the clock tick.
 *      "getconf CLK_TCK" command shows the clock ticks per second.
 *      (The clock ticks-per-second is defined by HZ macro in older systems.)
 *      If it is 100 and clock_t is 32 bits integer type,
 *      the resolution is 10 millisecond and cannot represent over 497 days.
 *
 *  - Emulations for +:CLOCK_PROCESS_CPUTIME_ID+:
 *
 *    - +:GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID+:
 *      Use getrusage() defined by SUS.
 *      getrusage() is used with RUSAGE_SELF to obtain the time only for
 *      the calling process (excluding the time for child processes).
 *      The result is addition of user time (ru_utime) and system time (ru_stime).
 *      The resolution is 1 microsecond.
 *    - +:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID+:
 *      Use times() defined by POSIX.
 *      The result is addition of user time (tms_utime) and system time (tms_stime).
 *      tms_cutime and tms_cstime are ignored to exclude the time for child processes.
 *      The resolution is the clock tick.
 *      "getconf CLK_TCK" command shows the clock ticks per second.
 *      (The clock ticks per second is defined by HZ macro in older systems.)
 *      If it is 100, the resolution is 10 millisecond.
 *    - +:CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID+:
 *      Use clock() defined by ISO C.
 *      The resolution is <tt>1/CLOCKS_PER_SEC</tt>.
 *      +CLOCKS_PER_SEC+ is the C-level macro defined by time.h.
 *      SUS defines +CLOCKS_PER_SEC+ as 1000000;
 *      other systems may define it differently.
 *      If +CLOCKS_PER_SEC+ is 1000000 (as in SUS),
 *      the resolution is 1 microsecond.
 *      If +CLOCKS_PER_SEC+ is 1000000 and clock_t is a 32-bit integer type,
 *      it cannot represent over 72 minutes.
 *
 *  <b>Argument +unit+</b>
 *
 *  Optional argument +unit+ (default +:float_second+)
 *  specifies the unit for the returned value.
 *
 *  - +:float_microsecond+: Number of microseconds as a float.
 *  - +:float_millisecond+: Number of milliseconds as a float.
 *  - +:float_second+: Number of seconds as a float.
 *  - +:microsecond+: Number of microseconds as an integer.
 *  - +:millisecond+: Number of milliseconds as an integer.
 *  - +:nanosecond+: Number of nanoseconds as an integer.
 *  - +::second+: Number of seconds as an integer.
 *
 *  Examples:
 *
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID, :float_microsecond)
 *    # => 203605054.825
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID, :float_millisecond)
 *    # => 203643.696848
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID, :float_second)
 *    # => 203.762181929
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID, :microsecond)
 *    # => 204123212
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID, :millisecond)
 *    # => 204298
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID, :nanosecond)
 *    # => 204602286036
 *    Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID, :second)
 *    # => 204
 *
 *  The underlying function, clock_gettime(), returns a number of nanoseconds.
 *  Float object (IEEE 754 double) is not enough to represent
 *  the return value for +:CLOCK_REALTIME+.
 *  If the exact nanoseconds value is required, use +:nanosecond+ as the +unit+.
 *
 *  The origin (time zero) of the returned value is system-dependent,
 *  and may be, for example, system start up time,
 *  process start up time, the Epoch, etc.
 *
 *  The origin in +:CLOCK_REALTIME+ is defined as the Epoch:
 *  <tt>1970-01-01 00:00:00 UTC</tt>;
 *  some systems count leap seconds and others don't,
 *  so the result may vary across systems.
 */
static VALUE
rb_clock_gettime(int argc, VALUE *argv, VALUE _)
{
    int ret;

    struct timetick tt;
    timetick_int_t numerators[2];
    timetick_int_t denominators[2];
    int num_numerators = 0;
    int num_denominators = 0;

    VALUE unit = (rb_check_arity(argc, 1, 2) == 2) ? argv[1] : Qnil;
    VALUE clk_id = argv[0];
#ifdef HAVE_CLOCK_GETTIME
    clockid_t c;
#endif

    if (SYMBOL_P(clk_id)) {
#ifdef CLOCK_REALTIME
        if (clk_id == RUBY_CLOCK_REALTIME) {
            c = CLOCK_REALTIME;
            goto gettime;
        }
#endif

#ifdef CLOCK_MONOTONIC
        if (clk_id == RUBY_CLOCK_MONOTONIC) {
            c = CLOCK_MONOTONIC;
            goto gettime;
        }
#endif

#ifdef CLOCK_PROCESS_CPUTIME_ID
        if (clk_id == RUBY_CLOCK_PROCESS_CPUTIME_ID) {
            c = CLOCK_PROCESS_CPUTIME_ID;
            goto gettime;
        }
#endif

#ifdef CLOCK_THREAD_CPUTIME_ID
        if (clk_id == RUBY_CLOCK_THREAD_CPUTIME_ID) {
            c = CLOCK_THREAD_CPUTIME_ID;
            goto gettime;
        }
#endif

        /*
         * Non-clock_gettime clocks are provided by symbol clk_id.
         */
#ifdef HAVE_GETTIMEOFDAY
        /*
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
#endif

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
        if (clk_id == RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC) {
            const mach_timebase_info_data_t *info = get_mach_timebase_info();
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
    else if (NUMERIC_CLOCKID) {
#if defined(HAVE_CLOCK_GETTIME)
        struct timespec ts;
        c = NUM2CLOCKID(clk_id);
      gettime:
        ret = clock_gettime(c, &ts);
        if (ret == -1)
            clock_failed("gettime", errno, clk_id);
        tt.count = (int32_t)ts.tv_nsec;
        tt.giga_count = ts.tv_sec;
        denominators[num_denominators++] = 1000000000;
        goto success;
#endif
    }
    else {
        rb_unexpected_type(clk_id, T_SYMBOL);
    }
    clock_failed("gettime", EINVAL, clk_id);

  success:
    return make_clock_result(&tt, numerators, num_numerators, denominators, num_denominators, unit);
}

/*
 *  call-seq:
 *    Process.clock_getres(clock_id, unit = :float_second)  -> number
 *
 *  Returns a clock resolution as determined by POSIX function
 *  {clock_getres()}[https://man7.org/linux/man-pages/man3/clock_getres.3.html]:
 *
 *    Process.clock_getres(:CLOCK_REALTIME) # => 1.0e-09
 *
 *  See Process.clock_gettime for the values of +clock_id+ and +unit+.
 *
 *  Examples:
 *
 *    Process.clock_getres(:CLOCK_PROCESS_CPUTIME_ID, :float_microsecond) # => 0.001
 *    Process.clock_getres(:CLOCK_PROCESS_CPUTIME_ID, :float_millisecond) # => 1.0e-06
 *    Process.clock_getres(:CLOCK_PROCESS_CPUTIME_ID, :float_second)      # => 1.0e-09
 *    Process.clock_getres(:CLOCK_PROCESS_CPUTIME_ID, :microsecond)       # => 0
 *    Process.clock_getres(:CLOCK_PROCESS_CPUTIME_ID, :millisecond)       # => 0
 *    Process.clock_getres(:CLOCK_PROCESS_CPUTIME_ID, :nanosecond)        # => 1
 *    Process.clock_getres(:CLOCK_PROCESS_CPUTIME_ID, :second)            # => 0
 *
 *  In addition to the values for +unit+ supported in Process.clock_gettime,
 *  this method supports +:hertz+, the integer number of clock ticks per second
 *  (which is the reciprocal of +:float_second+):
 *
 *    Process.clock_getres(:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID, :hertz)        # => 100.0
 *    Process.clock_getres(:TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID, :float_second) # => 0.01
 *
 *  <b>Accuracy</b>:
 *  Note that the returned resolution may be inaccurate on some platforms
 *  due to underlying bugs.
 *  Inaccurate resolutions have been reported for various clocks including
 *  +:CLOCK_MONOTONIC+ and +:CLOCK_MONOTONIC_RAW+
 *  on Linux, macOS, BSD or AIX platforms, when using ARM processors,
 *  or when using virtualization.
 */
static VALUE
rb_clock_getres(int argc, VALUE *argv, VALUE _)
{
    int ret;

    struct timetick tt;
    timetick_int_t numerators[2];
    timetick_int_t denominators[2];
    int num_numerators = 0;
    int num_denominators = 0;
#ifdef HAVE_CLOCK_GETRES
    clockid_t c;
#endif

    VALUE unit = (rb_check_arity(argc, 1, 2) == 2) ? argv[1] : Qnil;
    VALUE clk_id = argv[0];

    if (SYMBOL_P(clk_id)) {
#ifdef CLOCK_REALTIME
        if (clk_id == RUBY_CLOCK_REALTIME) {
            c = CLOCK_REALTIME;
            goto getres;
        }
#endif

#ifdef CLOCK_MONOTONIC
        if (clk_id == RUBY_CLOCK_MONOTONIC) {
            c = CLOCK_MONOTONIC;
            goto getres;
        }
#endif

#ifdef CLOCK_PROCESS_CPUTIME_ID
        if (clk_id == RUBY_CLOCK_PROCESS_CPUTIME_ID) {
            c = CLOCK_PROCESS_CPUTIME_ID;
            goto getres;
        }
#endif

#ifdef CLOCK_THREAD_CPUTIME_ID
        if (clk_id == RUBY_CLOCK_THREAD_CPUTIME_ID) {
            c = CLOCK_THREAD_CPUTIME_ID;
            goto getres;
        }
#endif

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
            const mach_timebase_info_data_t *info = get_mach_timebase_info();
            tt.count = 1;
            tt.giga_count = 0;
            numerators[num_numerators++] = info->numer;
            denominators[num_denominators++] = info->denom;
            denominators[num_denominators++] = 1000000000;
            goto success;
        }
#endif
    }
    else if (NUMERIC_CLOCKID) {
#if defined(HAVE_CLOCK_GETRES)
        struct timespec ts;
        c = NUM2CLOCKID(clk_id);
      getres:
        ret = clock_getres(c, &ts);
        if (ret == -1)
            clock_failed("getres", errno, clk_id);
        tt.count = (int32_t)ts.tv_nsec;
        tt.giga_count = ts.tv_sec;
        denominators[num_denominators++] = 1000000000;
        goto success;
#endif
    }
    else {
        rb_unexpected_type(clk_id, T_SYMBOL);
    }
    clock_failed("getres", EINVAL, clk_id);

  success:
    if (unit == ID2SYM(id_hertz)) {
        return timetick2dblnum_reciprocal(&tt, numerators, num_numerators, denominators, num_denominators);
    }
    else {
        return make_clock_result(&tt, numerators, num_numerators, denominators, num_denominators, unit);
    }
}

static VALUE
get_CHILD_STATUS(ID _x, VALUE *_y)
{
    return rb_last_status_get();
}

static VALUE
get_PROCESS_ID(ID _x, VALUE *_y)
{
    return get_pid();
}

/*
 *  call-seq:
 *    Process.kill(signal, *ids) -> count
 *
 *  Sends a signal to each process specified by +ids+
 *  (which must specify at least one ID);
 *  returns the count of signals sent.
 *
 *  For each given +id+, if +id+ is:
 *
 *  - Positive, sends the signal to the process whose process ID is +id+.
 *  - Zero, send the signal to all processes in the current process group.
 *  - Negative, sends the signal to a system-dependent collection of processes.
 *
 *  Argument +signal+ specifies the signal to be sent;
 *  the argument may be:
 *
 *  - An integer signal number: e.g., +-29+, +0+, +29+.
 *  - A signal name (string), with or without leading <tt>'SIG'</tt>,
 *    and with or without a further prefixed minus sign (<tt>'-'</tt>):
 *    e.g.:
 *
 *    - <tt>'SIGPOLL'</tt>.
 *    - <tt>'POLL'</tt>,
 *    - <tt>'-SIGPOLL'</tt>.
 *    - <tt>'-POLL'</tt>.
 *
 *  - A signal symbol, with or without leading <tt>'SIG'</tt>,
 *    and with or without a further prefixed minus sign (<tt>'-'</tt>):
 *    e.g.:
 *
 *    - +:SIGPOLL+.
 *    - +:POLL+.
 *    - <tt>:'-SIGPOLL'</tt>.
 *    - <tt>:'-POLL'</tt>.
 *
 *  If +signal+ is:
 *
 *  - A non-negative integer, or a signal name or symbol
 *    without prefixed <tt>'-'</tt>,
 *    each process with process ID +id+ is signalled.
 *  - A negative integer, or a signal name or symbol
 *    with prefixed <tt>'-'</tt>,
 *    each process group with group ID +id+ is signalled.
 *
 *  Use method Signal.list to see which signals are supported
 *  by Ruby on the underlying platform;
 *  the method returns a hash of the string names
 *  and non-negative integer values of the supported signals.
 *  The size and content of the returned hash varies widely
 *  among platforms.
 *
 *  Additionally, signal +0+ is useful to determine if the process exists.
 *
 *  Example:
 *
 *    pid = fork do
 *      Signal.trap('HUP') { puts 'Ouch!'; exit }
 *      # ... do some work ...
 *    end
 *    # ...
 *    Process.kill('HUP', pid)
 *    Process.wait
 *
 *  Output:
 *
 *     Ouch!
 *
 *  Exceptions:
 *
 *  - Raises Errno::EINVAL or RangeError if +signal+ is an integer
 *    but invalid.
 *  - Raises ArgumentError if +signal+ is a string or symbol
 *    but invalid.
 *  - Raises Errno::ESRCH or RangeError if one of +ids+ is invalid.
 *  - Raises Errno::EPERM if needed permissions are not in force.
 *
 *  In the last two cases, signals may have been sent to some processes.
 */

static VALUE
proc_rb_f_kill(int c, const VALUE *v, VALUE _)
{
    return rb_f_kill(c, v);
}

VALUE rb_mProcess;
static VALUE rb_mProcUID;
static VALUE rb_mProcGID;
static VALUE rb_mProcID_Syscall;

/*
 *  call-seq:
 *     Process.warmup    -> true
 *
 *  Notify the Ruby virtual machine that the boot sequence is finished,
 *  and that now is a good time to optimize the application. This is useful
 *  for long running applications.
 *
 *  This method is expected to be called at the end of the application boot.
 *  If the application is deployed using a pre-forking model, +Process.warmup+
 *  should be called in the original process before the first fork.
 *
 *  The actual optimizations performed are entirely implementation specific
 *  and may change in the future without notice.
 *
 *  On CRuby, +Process.warmup+:
 *
 *  * Performs a major GC.
 *  * Compacts the heap.
 *  * Promotes all surviving objects to the old generation.
 *  * Precomputes the coderange of all strings.
 *  * Frees all empty heap pages and increments the allocatable pages counter
 *    by the number of pages freed.
 *  * Invoke +malloc_trim+ if available to free empty malloc pages.
 */

static VALUE
proc_warmup(VALUE _)
{
    RB_VM_LOCK_ENTER();
    rb_gc_prepare_heap();
    RB_VM_LOCK_LEAVE();
    return Qtrue;
}

/*
 * Document-module: Process
 *
 * \Module +Process+ represents a process in the underlying operating system.
 * Its methods support management of the current process and its child processes.
 *
 * == \Process Creation
 *
 * Each of the following methods executes a given command in a new process or subshell,
 * or multiple commands in new processes and/or subshells.
 * The choice of process or subshell depends on the form of the command;
 * see {Argument command_line or exe_path}[rdoc-ref:Process@Argument+command_line+or+exe_path].
 *
 * - Process.spawn, Kernel#spawn: Executes the command;
 *   returns the new pid without waiting for completion.
 * - Process.exec: Replaces the current process by executing the command.
 *
 * In addition:
 *
 * - \Method Kernel#system executes a given command-line (string) in a subshell;
 *   returns +true+, +false+, or +nil+.
 * - \Method Kernel#` executes a given command-line (string) in a subshell;
 *   returns its $stdout string.
 * - \Module Open3 supports creating child processes
 *   with access to their $stdin, $stdout, and $stderr streams.
 *
 * === Execution Environment
 *
 * Optional leading argument +env+ is a hash of name/value pairs,
 * where each name is a string and each value is a string or +nil+;
 * each name/value pair is added to ENV in the new process.
 *
 *   Process.spawn(                'ruby -e "p ENV[\"Foo\"]"')
 *   Process.spawn({'Foo' => '0'}, 'ruby -e "p ENV[\"Foo\"]"')
 *
 * Output:
 *
 *   "0"
 *
 * The effect is usually similar to that of calling ENV#update with argument +env+,
 * where each named environment variable is created or updated
 * (if the value is non-+nil+),
 * or deleted (if the value is +nil+).
 *
 * However, some modifications to the calling process may remain
 * if the new process fails.
 * For example, hard resource limits are not restored.
 *
 * === Argument +command_line+ or +exe_path+
 *
 * The required string argument is one of the following:
 *
 * - +command_line+ if it begins with a shell reserved word or special built-in,
 *   or if it contains one or more meta characters.
 * - +exe_path+ otherwise.
 *
 * ==== Argument +command_line+
 *
 * \String argument +command_line+ is a command line to be passed to a shell;
 * it must begin with a shell reserved word, begin with a special built-in,
 * or contain meta characters:
 *
 *   system('if true; then echo "Foo"; fi')          # => true  # Shell reserved word.
 *   system('exit')                                  # => true  # Built-in.
 *   system('date > /tmp/date.tmp')                  # => true  # Contains meta character.
 *   system('date > /nop/date.tmp')                  # => false
 *   system('date > /nop/date.tmp', exception: true) # Raises RuntimeError.
 *
 * The command line may also contain arguments and options for the command:
 *
 *   system('echo "Foo"') # => true
 *
 * Output:
 *
 *   Foo
 *
 * See {Execution Shell}[rdoc-ref:Process@Execution+Shell] for details about the shell.
 *
 * ==== Argument +exe_path+
 *
 * Argument +exe_path+ is one of the following:
 *
 * - The string path to an executable file to be called:
 *
 *   Example:
 *
 *     system('/usr/bin/date') # => true # Path to date on Unix-style system.
 *     system('foo')           # => nil  # Command execlution failed.
 *
 *   Output:
 *
 *     Thu Aug 31 10:06:48 AM CDT 2023
 *
 *   A path or command name containing spaces without arguments cannot
 *   be distinguished from +command_line+ above, so you must quote or
 *   escape the entire command name using a shell in platform
 *   dependent manner, or use the array form below.
 *
 *   If +exe_path+ does not contain any path separator, an executable
 *   file is searched from directories specified with the +PATH+
 *   environment variable.  What the word "executable" means here is
 *   depending on platforms.
 *
 *   Even if the file considered "executable", its content may not be
 *   in proper executable format.  In that case, Ruby tries to run it
 *   by using <tt>/bin/sh</tt> on a Unix-like system, like system(3)
 *   does.
 *
 *     File.write('shell_command', 'echo $SHELL', perm: 0o755)
 *     system('./shell_command')        # prints "/bin/sh" or something.
 *
 * - A 2-element array containing the path to an executable
 *   and the string to be used as the name of the executing process:
 *
 *   Example:
 *
 *     pid = spawn(['sleep', 'Hello!'], '1') # 2-element array.
 *     p `ps -p #{pid} -o command=`
 *
 *   Output:
 *
 *     "Hello! 1\n"
 *
 * === Arguments +args+
 *
 * If +command_line+ does not contain shell meta characters except for
 * spaces and tabs, or +exe_path+ is given, Ruby invokes the
 * executable directly.  This form does not use the shell:
 *
 *   spawn("doesnt_exist")       # Raises Errno::ENOENT
 *   spawn("doesnt_exist", "\n") # Raises Errno::ENOENT
 *
 *   spawn("doesnt_exist\n")     # => false
 *   # sh: 1: doesnot_exist: not found
 *
 * The error message is from a shell and would vary depending on your
 * system.
 *
 * If one or more +args+ is given after +exe_path+, each is an
 * argument or option to be passed to the executable:
 *
 * Example:
 *
 *   system('echo', '<', 'C*', '|', '$SHELL', '>')   # => true
 *
 * Output:
 *
 *   < C* | $SHELL >
 *
 * However, there are exceptions on Windows.  See {Execution Shell on
 * Windows}[rdoc-ref:Process@Execution+Shell+on+Windows].
 *
 * If you want to invoke a path containing spaces with no arguments
 * without shell, you will need to use a 2-element array +exe_path+.
 *
 * Example:
 *
 *   path = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
 *   spawn(path) # Raises Errno::ENOENT; No such file or directory - /Applications/Google
 *   spawn([path] * 2)
 *
 * === Execution Options
 *
 * Optional trailing argument +options+ is a hash of execution options.
 *
 * ==== Working Directory (+:chdir+)
 *
 * By default, the working directory for the new process is the same as
 * that of the current process:
 *
 *   Dir.chdir('/var')
 *   Process.spawn('ruby -e "puts Dir.pwd"')
 *
 * Output:
 *
 *   /var
 *
 * Use option +:chdir+ to set the working directory for the new process:
 *
 *   Process.spawn('ruby -e "puts Dir.pwd"', {chdir: '/tmp'})
 *
 * Output:
 *
 *   /tmp
 *
 * The working directory of the current process is not changed:
 *
 *   Dir.pwd # => "/var"
 *
 * ==== \File Redirection (\File Descriptor)
 *
 * Use execution options for file redirection in the new process.
 *
 * The key for such an option may be an integer file descriptor (fd),
 * specifying a source,
 * or an array of fds, specifying multiple sources.
 *
 * An integer source fd may be specified as:
 *
 * - _n_: Specifies file descriptor _n_.
 *
 * There are these shorthand symbols for fds:
 *
 * - +:in+: Specifies file descriptor 0 (STDIN).
 * - +:out+: Specifies file descriptor 1 (STDOUT).
 * - +:err+: Specifies file descriptor 2 (STDERR).
 *
 * The value given with a source is one of:
 *
 * - _n_:
 *   Redirects to fd _n_ in the parent process.
 * - +filepath+:
 *   Redirects from or to the file at +filepath+ via <tt>open(filepath, mode, 0644)</tt>,
 *   where +mode+ is <tt>'r'</tt> for source +:in+,
 *   or <tt>'w'</tt> for source +:out+ or +:err+.
 * - <tt>[filepath]</tt>:
 *   Redirects from the file at +filepath+ via <tt>open(filepath, 'r', 0644)</tt>.
 * - <tt>[filepath, mode]</tt>:
 *   Redirects from or to the file at +filepath+ via <tt>open(filepath, mode, 0644)</tt>.
 * - <tt>[filepath, mode, perm]</tt>:
 *   Redirects from or to the file at +filepath+ via <tt>open(filepath, mode, perm)</tt>.
 * - <tt>[:child, fd]</tt>:
 *   Redirects to the redirected +fd+.
 * - +:close+: Closes the file descriptor in child process.
 *
 * See {Access Modes}[rdoc-ref:File@Access+Modes]
 * and {File Permissions}[rdoc-ref:File@File+Permissions].
 *
 * ==== Environment Variables (+:unsetenv_others+)
 *
 * By default, the new process inherits environment variables
 * from the parent process;
 * use execution option key +:unsetenv_others+ with value +true+
 * to clear environment variables in the new process.
 *
 * Any changes specified by execution option +env+ are made after the new process
 * inherits or clears its environment variables;
 * see {Execution Environment}[rdoc-ref:Process@Execution+Environment].
 *
 * ==== \File-Creation Access (+:umask+)
 *
 * Use execution option +:umask+ to set the file-creation access
 * for the new process;
 * see {Access Modes}[rdoc-ref:File@Access+Modes]:
 *
 *   command = 'ruby -e "puts sprintf(\"0%o\", File.umask)"'
 *   options = {:umask => 0644}
 *   Process.spawn(command, options)
 *
 * Output:
 *
 *   0644
 *
 * ==== \Process Groups (+:pgroup+ and +:new_pgroup+)
 *
 * By default, the new process belongs to the same
 * {process group}[https://en.wikipedia.org/wiki/Process_group]
 * as the parent process.
 *
 * To specify a different process group.
 * use execution option +:pgroup+ with one of the following values:
 *
 * - +true+: Create a new process group for the new process.
 * - _pgid_: Create the new process in the process group
 *   whose id is _pgid_.
 *
 * On Windows only, use execution option +:new_pgroup+ with value +true+
 * to create a new process group for the new process.
 *
 * ==== Resource Limits
 *
 * Use execution options to set resource limits.
 *
 * The keys for these options are symbols of the form
 * <tt>:rlimit_<i>resource_name</i></tt>,
 * where _resource_name_ is the downcased form of one of the string
 * resource names described at method Process.setrlimit.
 * For example, key +:rlimit_cpu+ corresponds to resource limit <tt>'CPU'</tt>.
 *
 * The value for such as key is one of:
 *
 * - An integer, specifying both the current and maximum limits.
 * - A 2-element array of integers, specifying the current and maximum limits.
 *
 * ==== \File Descriptor Inheritance
 *
 * By default, the new process inherits file descriptors from the parent process.
 *
 * Use execution option <tt>:close_others => true</tt> to modify that inheritance
 * by closing non-standard fds (3 and greater) that are not otherwise redirected.
 *
 * === Execution Shell
 *
 * On a Unix-like system, the shell invoked is <tt>/bin/sh</tt>;
 * the entire string +command_line+ is passed as an argument
 * to {shell option -c}[https://pubs.opengroup.org/onlinepubs/9699919799.2018edition/utilities/sh.html].
 *
 * The shell performs normal shell expansion on the command line:
 *
 * Example:
 *
 *   system('echo $SHELL: C*') # => true
 *
 * Output:
 *
 *   /bin/bash: CONTRIBUTING.md COPYING COPYING.ja
 *
 * ==== Execution Shell on Windows
 *
 * On Windows, the shell invoked is determined by environment variable
 * +RUBYSHELL+, if defined, or +COMSPEC+ otherwise; the entire string
 * +command_line+ is passed as an argument to <tt>-c</tt> option for
 * +RUBYSHELL+, as well as <tt>/bin/sh</tt>, and {/c
 * option}[https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cmd]
 * for +COMSPEC+.  The shell is invoked automatically in the following
 * cases:
 *
 * - The command is a built-in of +cmd.exe+, such as +echo+.
 * - The executable file is a batch file; its name ends with +.bat+ or
 *   +.cmd+.
 *
 * Note that the command will still be invoked as +command_line+ form
 * even when called in +exe_path+ form, because +cmd.exe+ does not
 * accept a script name like <tt>/bin/sh</tt> does but only works with
 * <tt>/c</tt> option.
 *
 * The standard shell +cmd.exe+ performs environment variable
 * expansion but does not have globbing functionality:
 *
 * Example:
 *
 *   system("echo %COMSPEC%: C*")' # => true
 *
 * Output:
 *
 *   C:\WINDOWS\system32\cmd.exe: C*
 *
 * == What's Here
 *
 * === Current-Process Getters
 *
 * - ::argv0: Returns the process name as a frozen string.
 * - ::egid: Returns the effective group ID.
 * - ::euid: Returns the effective user ID.
 * - ::getpgrp: Return the process group ID.
 * - ::getrlimit: Returns the resource limit.
 * - ::gid: Returns the (real) group ID.
 * - ::pid: Returns the process ID.
 * - ::ppid: Returns the process ID of the parent process.
 * - ::uid: Returns the (real) user ID.
 *
 * === Current-Process Setters
 *
 * - ::egid=: Sets the effective group ID.
 * - ::euid=: Sets the effective user ID.
 * - ::gid=: Sets the (real) group ID.
 * - ::setproctitle: Sets the process title.
 * - ::setpgrp: Sets the process group ID of the process to zero.
 * - ::setrlimit: Sets a resource limit.
 * - ::setsid: Establishes the process as a new session and process group leader,
 *   with no controlling tty.
 * - ::uid=: Sets the user ID.
 *
 * === Current-Process Execution
 *
 * - ::abort: Immediately terminates the process.
 * - ::daemon: Detaches the process from its controlling terminal
 *   and continues running it in the background as system daemon.
 * - ::exec: Replaces the process by running a given external command.
 * - ::exit: Initiates process termination by raising exception SystemExit
 *   (which may be caught).
 * - ::exit!: Immediately exits the process.
 * - ::warmup: Notifies the Ruby virtual machine that the boot sequence
 *   for the application is completed,
 *   and that the VM may begin optimizing the application.
 *
 * === Child Processes
 *
 * - ::detach: Guards against a child process becoming a zombie.
 * - ::fork: Creates a child process.
 * - ::kill: Sends a given signal to processes.
 * - ::spawn: Creates a child process.
 * - ::wait, ::waitpid: Waits for a child process to exit; returns its process ID.
 * - ::wait2, ::waitpid2: Waits for a child process to exit; returns its process ID and status.
 * - ::waitall: Waits for all child processes to exit;
 *   returns their process IDs and statuses.
 *
 * === \Process Groups
 *
 * - ::getpgid: Returns the process group ID for a process.
 * - ::getpriority: Returns the scheduling priority
 *   for a process, process group, or user.
 * - ::getsid: Returns the session ID for a process.
 * - ::groups: Returns an array of the group IDs
 *   in the supplemental group access list for this process.
 * - ::groups=: Sets the supplemental group access list
 *   to the given array of group IDs.
 * - ::initgroups: Initializes the supplemental group access list.
 * - ::last_status: Returns the status of the last executed child process
 *   in the current thread.
 * - ::maxgroups: Returns the maximum number of group IDs allowed
 *   in the supplemental group access list.
 * - ::maxgroups=: Sets the maximum number of group IDs allowed
 *   in the supplemental group access list.
 * - ::setpgid: Sets the process group ID of a process.
 * - ::setpriority: Sets the scheduling priority
 *   for a process, process group, or user.
 *
 * === Timing
 *
 * - ::clock_getres: Returns the resolution of a system clock.
 * - ::clock_gettime: Returns the time from a system clock.
 * - ::times: Returns a Process::Tms object containing times
 *   for the current process and its child processes.
 *
 */

void
InitVM_process(void)
{
    rb_define_virtual_variable("$?", get_CHILD_STATUS, 0);
    rb_define_virtual_variable("$$", get_PROCESS_ID, 0);

    rb_gvar_ractor_local("$$");
    rb_gvar_ractor_local("$?");

    rb_define_global_function("exec", f_exec, -1);
    rb_define_global_function("fork", rb_f_fork, 0);
    rb_define_global_function("exit!", rb_f_exit_bang, -1);
    rb_define_global_function("system", rb_f_system, -1);
    rb_define_global_function("spawn", rb_f_spawn, -1);
    rb_define_global_function("sleep", rb_f_sleep, -1);
    rb_define_global_function("exit", f_exit, -1);
    rb_define_global_function("abort", f_abort, -1);

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

    rb_define_singleton_method(rb_mProcess, "exec", f_exec, -1);
    rb_define_singleton_method(rb_mProcess, "fork", rb_f_fork, 0);
    rb_define_singleton_method(rb_mProcess, "spawn", rb_f_spawn, -1);
    rb_define_singleton_method(rb_mProcess, "exit!", rb_f_exit_bang, -1);
    rb_define_singleton_method(rb_mProcess, "exit", f_exit, -1);
    rb_define_singleton_method(rb_mProcess, "abort", f_abort, -1);
    rb_define_singleton_method(rb_mProcess, "last_status", proc_s_last_status, 0);
    rb_define_singleton_method(rb_mProcess, "_fork", rb_proc__fork, 0);

    rb_define_module_function(rb_mProcess, "kill", proc_rb_f_kill, -1);
    rb_define_module_function(rb_mProcess, "wait", proc_m_wait, -1);
    rb_define_module_function(rb_mProcess, "wait2", proc_wait2, -1);
    rb_define_module_function(rb_mProcess, "waitpid", proc_m_wait, -1);
    rb_define_module_function(rb_mProcess, "waitpid2", proc_wait2, -1);
    rb_define_module_function(rb_mProcess, "waitall", proc_waitall, 0);
    rb_define_module_function(rb_mProcess, "detach", proc_detach, 1);

    /* :nodoc: */
    rb_cWaiter = rb_define_class_under(rb_mProcess, "Waiter", rb_cThread);
    rb_undef_alloc_func(rb_cWaiter);
    rb_undef_method(CLASS_OF(rb_cWaiter), "new");
    rb_define_method(rb_cWaiter, "pid", detach_process_pid, 0);

    rb_cProcessStatus = rb_define_class_under(rb_mProcess, "Status", rb_cObject);
    rb_define_alloc_func(rb_cProcessStatus, rb_process_status_allocate);
    rb_undef_method(CLASS_OF(rb_cProcessStatus), "new");
    rb_marshal_define_compat(rb_cProcessStatus, rb_cObject,
                             process_status_dump, process_status_load);

    rb_define_singleton_method(rb_cProcessStatus, "wait", rb_process_status_waitv, -1);

    rb_define_method(rb_cProcessStatus, "==", pst_equal, 1);
    rb_define_method(rb_cProcessStatus, "&", pst_bitand, 1);
    rb_define_method(rb_cProcessStatus, ">>", pst_rshift, 1);
    rb_define_method(rb_cProcessStatus, "to_i", pst_to_i, 0);
    rb_define_method(rb_cProcessStatus, "to_s", pst_to_s, 0);
    rb_define_method(rb_cProcessStatus, "inspect", pst_inspect, 0);

    rb_define_method(rb_cProcessStatus, "pid", pst_pid_m, 0);

    rb_define_method(rb_cProcessStatus, "stopped?", pst_wifstopped, 0);
    rb_define_method(rb_cProcessStatus, "stopsig", pst_wstopsig, 0);
    rb_define_method(rb_cProcessStatus, "signaled?", pst_wifsignaled, 0);
    rb_define_method(rb_cProcessStatus, "termsig", pst_wtermsig, 0);
    rb_define_method(rb_cProcessStatus, "exited?", pst_wifexited, 0);
    rb_define_method(rb_cProcessStatus, "exitstatus", pst_wexitstatus, 0);
    rb_define_method(rb_cProcessStatus, "success?", pst_success_p, 0);
    rb_define_method(rb_cProcessStatus, "coredump?", pst_wcoredump, 0);

    rb_define_module_function(rb_mProcess, "pid", proc_get_pid, 0);
    rb_define_module_function(rb_mProcess, "ppid", proc_get_ppid, 0);

    rb_define_module_function(rb_mProcess, "getpgrp", proc_getpgrp, 0);
    rb_define_module_function(rb_mProcess, "setpgrp", proc_setpgrp, 0);
    rb_define_module_function(rb_mProcess, "getpgid", proc_getpgid, 1);
    rb_define_module_function(rb_mProcess, "setpgid", proc_setpgid, 2);

    rb_define_module_function(rb_mProcess, "getsid", proc_getsid, -1);
    rb_define_module_function(rb_mProcess, "setsid", proc_setsid, 0);

    rb_define_module_function(rb_mProcess, "getpriority", proc_getpriority, 2);
    rb_define_module_function(rb_mProcess, "setpriority", proc_setpriority, 3);

    rb_define_module_function(rb_mProcess, "warmup", proc_warmup, 0);

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
#ifdef RLIMIT_NPTS
    /* The maximum number of pseudo-terminals that can be created for the
     * real user ID of the calling process.
     *
     * see the system getrlimit(2) manual for details.
     */
    rb_define_const(rb_mProcess, "RLIMIT_NPTS", INT2FIX(RLIMIT_NPTS));
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

#if defined(RUBY_CLOCK_REALTIME)
#elif defined(RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME)
# define RUBY_CLOCK_REALTIME RUBY_GETTIMEOFDAY_BASED_CLOCK_REALTIME
#elif defined(RUBY_TIME_BASED_CLOCK_REALTIME)
# define RUBY_CLOCK_REALTIME RUBY_TIME_BASED_CLOCK_REALTIME
#endif
#if defined(CLOCK_REALTIME) && defined(CLOCKID2NUM)
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_REALTIME", CLOCKID2NUM(CLOCK_REALTIME));
#elif defined(RUBY_CLOCK_REALTIME)
    rb_define_const(rb_mProcess, "CLOCK_REALTIME", RUBY_CLOCK_REALTIME);
#endif

#if defined(RUBY_CLOCK_MONOTONIC)
#elif defined(RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC)
# define RUBY_CLOCK_MONOTONIC RUBY_MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC
#endif
#if defined(CLOCK_MONOTONIC) && defined(CLOCKID2NUM)
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC", CLOCKID2NUM(CLOCK_MONOTONIC));
#elif defined(RUBY_CLOCK_MONOTONIC)
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC", RUBY_CLOCK_MONOTONIC);
#endif

#if defined(RUBY_CLOCK_PROCESS_CPUTIME_ID)
#elif defined(RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID)
# define RUBY_CLOCK_PROCESS_CPUTIME_ID RUBY_GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID
#endif
#if defined(CLOCK_PROCESS_CPUTIME_ID) && defined(CLOCKID2NUM)
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_PROCESS_CPUTIME_ID", CLOCKID2NUM(CLOCK_PROCESS_CPUTIME_ID));
#elif defined(RUBY_CLOCK_PROCESS_CPUTIME_ID)
    rb_define_const(rb_mProcess, "CLOCK_PROCESS_CPUTIME_ID", RUBY_CLOCK_PROCESS_CPUTIME_ID);
#endif

#if defined(CLOCK_THREAD_CPUTIME_ID) && defined(CLOCKID2NUM)
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_THREAD_CPUTIME_ID", CLOCKID2NUM(CLOCK_THREAD_CPUTIME_ID));
#elif defined(RUBY_CLOCK_THREAD_CPUTIME_ID)
    rb_define_const(rb_mProcess, "CLOCK_THREAD_CPUTIME_ID", RUBY_CLOCK_THREAD_CPUTIME_ID);
#endif

#ifdef CLOCKID2NUM
#ifdef CLOCK_VIRTUAL
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_VIRTUAL", CLOCKID2NUM(CLOCK_VIRTUAL));
#endif
#ifdef CLOCK_PROF
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_PROF", CLOCKID2NUM(CLOCK_PROF));
#endif
#ifdef CLOCK_REALTIME_FAST
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_FAST", CLOCKID2NUM(CLOCK_REALTIME_FAST));
#endif
#ifdef CLOCK_REALTIME_PRECISE
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_PRECISE", CLOCKID2NUM(CLOCK_REALTIME_PRECISE));
#endif
#ifdef CLOCK_REALTIME_COARSE
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_COARSE", CLOCKID2NUM(CLOCK_REALTIME_COARSE));
#endif
#ifdef CLOCK_REALTIME_ALARM
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_REALTIME_ALARM", CLOCKID2NUM(CLOCK_REALTIME_ALARM));
#endif
#ifdef CLOCK_MONOTONIC_FAST
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_FAST", CLOCKID2NUM(CLOCK_MONOTONIC_FAST));
#endif
#ifdef CLOCK_MONOTONIC_PRECISE
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_PRECISE", CLOCKID2NUM(CLOCK_MONOTONIC_PRECISE));
#endif
#ifdef CLOCK_MONOTONIC_RAW
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_RAW", CLOCKID2NUM(CLOCK_MONOTONIC_RAW));
#endif
#ifdef CLOCK_MONOTONIC_RAW_APPROX
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_RAW_APPROX", CLOCKID2NUM(CLOCK_MONOTONIC_RAW_APPROX));
#endif
#ifdef CLOCK_MONOTONIC_COARSE
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_MONOTONIC_COARSE", CLOCKID2NUM(CLOCK_MONOTONIC_COARSE));
#endif
#ifdef CLOCK_BOOTTIME
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_BOOTTIME", CLOCKID2NUM(CLOCK_BOOTTIME));
#endif
#ifdef CLOCK_BOOTTIME_ALARM
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_BOOTTIME_ALARM", CLOCKID2NUM(CLOCK_BOOTTIME_ALARM));
#endif
#ifdef CLOCK_UPTIME
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_UPTIME", CLOCKID2NUM(CLOCK_UPTIME));
#endif
#ifdef CLOCK_UPTIME_FAST
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_UPTIME_FAST", CLOCKID2NUM(CLOCK_UPTIME_FAST));
#endif
#ifdef CLOCK_UPTIME_PRECISE
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_UPTIME_PRECISE", CLOCKID2NUM(CLOCK_UPTIME_PRECISE));
#endif
#ifdef CLOCK_UPTIME_RAW
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_UPTIME_RAW", CLOCKID2NUM(CLOCK_UPTIME_RAW));
#endif
#ifdef CLOCK_UPTIME_RAW_APPROX
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_UPTIME_RAW_APPROX", CLOCKID2NUM(CLOCK_UPTIME_RAW_APPROX));
#endif
#ifdef CLOCK_SECOND
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_SECOND", CLOCKID2NUM(CLOCK_SECOND));
#endif
#ifdef CLOCK_TAI
    /* see Process.clock_gettime */
    rb_define_const(rb_mProcess, "CLOCK_TAI", CLOCKID2NUM(CLOCK_TAI));
#endif
#endif
    rb_define_module_function(rb_mProcess, "clock_gettime", rb_clock_gettime, -1);
    rb_define_module_function(rb_mProcess, "clock_getres", rb_clock_getres, -1);

#if defined(HAVE_TIMES) || defined(_WIN32)
    rb_cProcessTms = rb_struct_define_under(rb_mProcess, "Tms", "utime", "stime", "cutime", "cstime", NULL);
#if 0 /* for RDoc */
    /* user time used in this process */
    rb_define_attr(rb_cProcessTms, "utime", TRUE, TRUE);
    /* system time used in this process */
    rb_define_attr(rb_cProcessTms, "stime", TRUE, TRUE);
    /* user time used in the child processes */
    rb_define_attr(rb_cProcessTms, "cutime", TRUE, TRUE);
    /* system time used in the child processes */
    rb_define_attr(rb_cProcessTms, "cstime", TRUE, TRUE);
#endif
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
#define define_id(name) id_##name = rb_intern_const(#name)
    define_id(in);
    define_id(out);
    define_id(err);
    define_id(pid);
    define_id(uid);
    define_id(gid);
    define_id(close);
    define_id(child);
#ifdef HAVE_SETPGID
    define_id(pgroup);
#endif
#ifdef _WIN32
    define_id(new_pgroup);
#endif
    define_id(unsetenv_others);
    define_id(chdir);
    define_id(umask);
    define_id(close_others);
    define_id(nanosecond);
    define_id(microsecond);
    define_id(millisecond);
    define_id(second);
    define_id(float_microsecond);
    define_id(float_millisecond);
    define_id(float_second);
    define_id(GETTIMEOFDAY_BASED_CLOCK_REALTIME);
    define_id(TIME_BASED_CLOCK_REALTIME);
#ifdef CLOCK_REALTIME
    define_id(CLOCK_REALTIME);
#endif
#ifdef CLOCK_MONOTONIC
    define_id(CLOCK_MONOTONIC);
#endif
#ifdef CLOCK_PROCESS_CPUTIME_ID
    define_id(CLOCK_PROCESS_CPUTIME_ID);
#endif
#ifdef CLOCK_THREAD_CPUTIME_ID
    define_id(CLOCK_THREAD_CPUTIME_ID);
#endif
#ifdef HAVE_TIMES
    define_id(TIMES_BASED_CLOCK_MONOTONIC);
    define_id(TIMES_BASED_CLOCK_PROCESS_CPUTIME_ID);
#endif
#ifdef RUSAGE_SELF
    define_id(GETRUSAGE_BASED_CLOCK_PROCESS_CPUTIME_ID);
#endif
    define_id(CLOCK_BASED_CLOCK_PROCESS_CPUTIME_ID);
#ifdef __APPLE__
    define_id(MACH_ABSOLUTE_TIME_BASED_CLOCK_MONOTONIC);
#endif
    define_id(hertz);

    InitVM(process);
}
