#include "ruby/config.h"

#ifdef RUBY_EXTCONF_H
# include RUBY_EXTCONF_H
#endif

#include <ctype.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>

#ifdef HAVE_PWD_H
# include <pwd.h>
#endif

#ifdef HAVE_SYS_IOCTL_H
# include <sys/ioctl.h>
#endif

#ifdef HAVE_LIBUTIL_H
# include <libutil.h>
#endif

#ifdef HAVE_UTIL_H
# include <util.h>
#endif

#ifdef HAVE_PTY_H
# include <pty.h>
#endif

#if defined(HAVE_SYS_PARAM_H)
 /* for __FreeBSD_version */
# include <sys/param.h>
#endif

#ifdef HAVE_SYS_WAIT_H
# include <sys/wait.h>
#else
# define WIFSTOPPED(status) (((status) & 0xff) == 0x7f)
#endif

#ifdef HAVE_SYS_STROPTS_H
#include <sys/stropts.h>
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#include "internal.h"
#include "internal/process.h"
#include "internal/signal.h"
#include "ruby/io.h"
#include "ruby/util.h"

#define	DEVICELEN	16

#ifndef HAVE_SETEUID
# ifdef HAVE_SETREUID
#  define seteuid(e)	setreuid(-1, (e))
# else /* NOT HAVE_SETREUID */
#  ifdef HAVE_SETRESUID
#   define seteuid(e)	setresuid(-1, (e), -1)
#  else /* NOT HAVE_SETRESUID */
    /* I can't set euid. (;_;) */
#  endif /* HAVE_SETRESUID */
# endif /* HAVE_SETREUID */
#endif /* NO_SETEUID */

static VALUE eChildExited;

/* Returns the exit status of the child for which PTY#check
 * raised this exception
 */
static VALUE
echild_status(VALUE self)
{
    return rb_ivar_get(self, rb_intern("status"));
}

struct pty_info {
    int fd;
    rb_pid_t child_pid;
};

static void getDevice(int*, int*, char [DEVICELEN], int);

struct child_info {
    int controller, worker;
    char *workername;
    VALUE execarg_obj;
    struct rb_execarg *eargp;
};

static int
chfunc(void *data, char *errbuf, size_t errbuf_len)
{
    struct child_info *carg = data;
    int controller = carg->controller;
    int worker = carg->worker;

#define ERROR_EXIT(str) do { \
	strlcpy(errbuf, (str), errbuf_len); \
	return -1; \
    } while (0)

    /*
     * Set free from process group and controlling terminal
     */
#ifdef HAVE_SETSID
    (void) setsid();
#else /* HAS_SETSID */
# ifdef HAVE_SETPGRP
#  ifdef SETGRP_VOID
    if (setpgrp() == -1)
        ERROR_EXIT("setpgrp()");
#  else /* SETGRP_VOID */
    if (setpgrp(0, getpid()) == -1)
        ERROR_EXIT("setpgrp()");
    {
        int i = rb_cloexec_open("/dev/tty", O_RDONLY, 0);
        if (i < 0) ERROR_EXIT("/dev/tty");
        rb_update_max_fd(i);
        if (ioctl(i, TIOCNOTTY, (char *)0))
            ERROR_EXIT("ioctl(TIOCNOTTY)");
        close(i);
    }
#  endif /* SETGRP_VOID */
# endif /* HAVE_SETPGRP */
#endif /* HAS_SETSID */

    /*
     * obtain new controlling terminal
     */
#if defined(TIOCSCTTY)
    close(controller);
    (void) ioctl(worker, TIOCSCTTY, (char *)0);
    /* errors ignored for sun */
#else
    close(worker);
    worker = rb_cloexec_open(carg->workername, O_RDWR, 0);
    if (worker < 0) {
        ERROR_EXIT("open: pty worker");
    }
    rb_update_max_fd(worker);
    close(controller);
#endif
    dup2(worker,0);
    dup2(worker,1);
    dup2(worker,2);
    if (worker < 0 || worker > 2) (void)!close(worker);
#if defined(HAVE_SETEUID) || defined(HAVE_SETREUID) || defined(HAVE_SETRESUID)
    if (seteuid(getuid())) ERROR_EXIT("seteuid()");
#endif

    return rb_exec_async_signal_safe(carg->eargp, errbuf, sizeof(errbuf_len));
#undef ERROR_EXIT
}

static void
establishShell(int argc, VALUE *argv, struct pty_info *info,
	       char WorkerName[DEVICELEN])
{
    int 		controller, worker, status = 0;
    rb_pid_t		pid;
    char		*p, *getenv();
    VALUE		v;
    struct child_info   carg;
    char		errbuf[32];

    if (argc == 0) {
	const char *shellname = "/bin/sh";

	if ((p = getenv("SHELL")) != NULL) {
	    shellname = p;
	}
	else {
#if defined HAVE_PWD_H
	    const char *username = getenv("USER");
	    struct passwd *pwent = getpwnam(username ? username : getlogin());
	    if (pwent && pwent->pw_shell)
		shellname = pwent->pw_shell;
#endif
	}
	v = rb_str_new2(shellname);
	argc = 1;
	argv = &v;
    }

    carg.execarg_obj = rb_execarg_new(argc, argv, 1, 0);
    carg.eargp = rb_execarg_get(carg.execarg_obj);
    rb_execarg_parent_start(carg.execarg_obj);

    getDevice(&controller, &worker, WorkerName, 0);

    carg.controller = controller;
    carg.worker = worker;
    carg.workername = WorkerName;
    errbuf[0] = '\0';
    pid = rb_fork_async_signal_safe(&status, chfunc, &carg, Qnil, errbuf, sizeof(errbuf));

    if (pid < 0) {
	int e = errno;
	close(controller);
	close(worker);
        rb_execarg_parent_end(carg.execarg_obj);
	errno = e;
	if (status) rb_jump_tag(status);
	rb_sys_fail(errbuf[0] ? errbuf : "fork failed");
    }

    close(worker);
    rb_execarg_parent_end(carg.execarg_obj);

    info->child_pid = pid;
    info->fd = controller;

    RB_GC_GUARD(carg.execarg_obj);
}

#if defined(HAVE_POSIX_OPENPT) || defined(HAVE_OPENPTY) || defined(HAVE_PTSNAME)
static int
no_mesg(char *workerdevice, int nomesg)
{
    if (nomesg)
        return chmod(workerdevice, 0600);
    else
        return 0;
}
#endif

#if defined(I_PUSH) && !defined(__linux__) && !defined(_AIX)
static inline int
ioctl_I_PUSH(int fd, const char *const name)
{
    int ret = 0;
# if defined(I_FIND)
    ret = ioctl(fd, I_FIND, name);
# endif
    if (ret == 0) {
        ret = ioctl(fd, I_PUSH, name);
    }
    return ret;
}
#endif

static int
get_device_once(int *controller, int *worker, char WorkerName[DEVICELEN], int nomesg, int fail)
{
#if defined(HAVE_POSIX_OPENPT)
    /* Unix98 PTY */
    int controllerfd = -1, workerfd = -1;
    char *workerdevice;

#if defined(__sun) || defined(__OpenBSD__) || (defined(__FreeBSD__) && __FreeBSD_version < 902000)
    /* workaround for Solaris 10: grantpt() doesn't work if FD_CLOEXEC is set.  [ruby-dev:44688] */
    /* FreeBSD 9.2 or later supports O_CLOEXEC
     * http://www.freebsd.org/cgi/query-pr.cgi?pr=162374 */
    if ((controllerfd = posix_openpt(O_RDWR|O_NOCTTY)) == -1) goto error;
    if (rb_grantpt(controllerfd) == -1) goto error;
    rb_fd_fix_cloexec(controllerfd);
#else
    {
	int flags = O_RDWR|O_NOCTTY;
# if defined(O_CLOEXEC)
	/* glibc posix_openpt() in GNU/Linux calls open("/dev/ptmx", flags) internally.
	 * So version dependency on GNU/Linux is the same as O_CLOEXEC with open().
	 * O_CLOEXEC is available since Linux 2.6.23.  Linux 2.6.18 silently ignore it. */
	flags |= O_CLOEXEC;
# endif
	if ((controllerfd = posix_openpt(flags)) == -1) goto error;
    }
    rb_fd_fix_cloexec(controllerfd);
    if (rb_grantpt(controllerfd) == -1) goto error;
#endif
    if (unlockpt(controllerfd) == -1) goto error;
    if ((workerdevice = ptsname(controllerfd)) == NULL) goto error;
    if (no_mesg(workerdevice, nomesg) == -1) goto error;
    if ((workerfd = rb_cloexec_open(workerdevice, O_RDWR|O_NOCTTY, 0)) == -1) goto error;
    rb_update_max_fd(workerfd);

#if defined(I_PUSH) && !defined(__linux__) && !defined(_AIX)
    if (ioctl_I_PUSH(workerfd, "ptem") == -1) goto error;
    if (ioctl_I_PUSH(workerfd, "ldterm") == -1) goto error;
    if (ioctl_I_PUSH(workerfd, "ttcompat") == -1) goto error;
#endif

    *controller = controllerfd;
    *worker = workerfd;
    strlcpy(WorkerName, workerdevice, DEVICELEN);
    return 0;

  error:
    if (workerfd != -1) close(workerfd);
    if (controllerfd != -1) close(controllerfd);
    if (fail) {
        rb_raise(rb_eRuntimeError, "can't get Controller/Worker device");
    }
    return -1;
#elif defined HAVE_OPENPTY
/*
 * Use openpty(3) of 4.3BSD Reno and later,
 * or the same interface function.
 */
    if (openpty(controller, worker, WorkerName,
		(struct termios *)0, (struct winsize *)0) == -1) {
	if (!fail) return -1;
	rb_raise(rb_eRuntimeError, "openpty() failed");
    }
    rb_fd_fix_cloexec(*controller);
    rb_fd_fix_cloexec(*worker);
    if (no_mesg(WorkerName, nomesg) == -1) {
	if (!fail) return -1;
	rb_raise(rb_eRuntimeError, "can't chmod worker pty");
    }

    return 0;

#elif defined HAVE__GETPTY
    /* SGI IRIX */
    char *name;
    mode_t mode = nomesg ? 0600 : 0622;

    if (!(name = _getpty(controller, O_RDWR, mode, 0))) {
	if (!fail) return -1;
	rb_raise(rb_eRuntimeError, "_getpty() failed");
    }
    rb_fd_fix_cloexec(*controller);

    *worker = rb_cloexec_open(name, O_RDWR, 0);
    /* error check? */
    rb_update_max_fd(*worker);
    strlcpy(WorkerName, name, DEVICELEN);

    return 0;
#elif defined(HAVE_PTSNAME)
    /* System V */
    int  controllerfd = -1, workerfd = -1;
    char *workerdevice;
    void (*s)();

    extern char *ptsname(int);
    extern int unlockpt(int);

#if defined(__sun)
    /* workaround for Solaris 10: grantpt() doesn't work if FD_CLOEXEC is set.  [ruby-dev:44688] */
    if((controllerfd = open("/dev/ptmx", O_RDWR, 0)) == -1) goto error;
    if(rb_grantpt(controllerfd) == -1) goto error;
    rb_fd_fix_cloexec(controllerfd);
#else
    if((controllerfd = rb_cloexec_open("/dev/ptmx", O_RDWR, 0)) == -1) goto error;
    rb_update_max_fd(controllerfd);
    if(rb_grantpt(controllerfd) == -1) goto error;
#endif
    if(unlockpt(controllerfd) == -1) goto error;
    if((workerdevice = ptsname(controllerfd)) == NULL) goto error;
    if (no_mesg(workerdevice, nomesg) == -1) goto error;
    if((workerfd = rb_cloexec_open(workerdevice, O_RDWR, 0)) == -1) goto error;
    rb_update_max_fd(workerfd);
#if defined(I_PUSH) && !defined(__linux__) && !defined(_AIX)
    if(ioctl_I_PUSH(workerfd, "ptem") == -1) goto error;
    if(ioctl_I_PUSH(workerfd, "ldterm") == -1) goto error;
    ioctl_I_PUSH(workerfd, "ttcompat");
#endif
    *controller = controllerfd;
    *worker = workerfd;
    strlcpy(WorkerName, workerdevice, DEVICELEN);
    return 0;

  error:
    if (workerfd != -1) close(workerfd);
    if (controllerfd != -1) close(controllerfd);
    if (fail) rb_raise(rb_eRuntimeError, "can't get Controller/Worker device");
    return -1;
#else
    /* BSD */
    int  controllerfd = -1, workerfd = -1;
    int  i;
    char ControllerName[DEVICELEN];

#define HEX1(c) \
	c"0",c"1",c"2",c"3",c"4",c"5",c"6",c"7", \
	c"8",c"9",c"a",c"b",c"c",c"d",c"e",c"f"

#if defined(__hpux)
    static const char ControllerDevice[] = "/dev/ptym/pty%s";
    static const char WorkerDevice[] =  "/dev/pty/tty%s";
    static const char deviceNo[][3] = {
	HEX1("p"), HEX1("q"), HEX1("r"), HEX1("s"),
	HEX1("t"), HEX1("u"), HEX1("v"), HEX1("w"),
    };
#elif defined(_IBMESA)  /* AIX/ESA */
    static const char ControllerDevice[] = "/dev/ptyp%s";
    static const char WorkerDevice[] = "/dev/ttyp%s";
    static const char deviceNo[][3] = {
	HEX1("0"), HEX1("1"), HEX1("2"), HEX1("3"),
	HEX1("4"), HEX1("5"), HEX1("6"), HEX1("7"),
	HEX1("8"), HEX1("9"), HEX1("a"), HEX1("b"),
	HEX1("c"), HEX1("d"), HEX1("e"), HEX1("f"),
    };
#else /* 4.2BSD */
    static const char ControllerDevice[] = "/dev/pty%s";
    static const char WorkerDevice[] = "/dev/tty%s";
    static const char deviceNo[][3] = {
	HEX1("p"), HEX1("q"), HEX1("r"), HEX1("s"),
    };
#endif
#undef HEX1
    for (i = 0; i < numberof(deviceNo); i++) {
	const char *const devno = deviceNo[i];
	snprintf(ControllerName, sizeof ControllerName, ControllerDevice, devno);
	if ((controllerfd = rb_cloexec_open(ControllerName,O_RDWR,0)) >= 0) {
            rb_update_max_fd(controllerfd);
	    *controller = controllerfd;
	    snprintf(WorkerName, DEVICELEN, WorkerDevice, devno);
	    if ((workerfd = rb_cloexec_open(WorkerName,O_RDWR,0)) >= 0) {
                rb_update_max_fd(workerfd);
		*worker = workerfd;
		if (chown(WorkerName, getuid(), getgid()) != 0) goto error;
		if (chmod(WorkerName, nomesg ? 0600 : 0622) != 0) goto error;
		return 0;
	    }
	    close(controllerfd);
	}
    }
  error:
    if (workerfd != -1) close(workerfd);
    if (controllerfd != -1) close(controllerfd);
    if (fail) rb_raise(rb_eRuntimeError, "can't get %s", WorkerName);
    return -1;
#endif
}

static void
getDevice(int *controller, int *worker, char WorkerName[DEVICELEN], int nomesg)
{
    if (get_device_once(controller, worker, WorkerName, nomesg, 0)) {
	rb_gc();
	get_device_once(controller, worker, WorkerName, nomesg, 1);
    }
}

static VALUE
pty_close_pty(VALUE assoc)
{
    VALUE io;
    int i;

    for (i = 0; i < 2; i++) {
        io = rb_ary_entry(assoc, i);
        if (RB_TYPE_P(io, T_FILE) && 0 <= RFILE(io)->fptr->fd)
            rb_io_close(io);
    }
    return Qnil;
}

/*
 * call-seq:
 *   PTY.open => [controller_io, worker_file]
 *   PTY.open {|(controller_io, worker_file)| ... } => block value
 *
 * Allocates a pty (pseudo-terminal).
 *
 * In the block form, yields an array of two elements (<tt>controller_io, worker_file</tt>)
 * and the value of the block is returned from +open+.
 *
 * The IO and File are both closed after the block completes if they haven't
 * been already closed.
 *
 *   PTY.open {|controller, worker|
 *     p controller  #=> #<IO:controllerpty:/dev/pts/1>
 *     p worker      #=> #<File:/dev/pts/1>
 *     p worker.path #=> "/dev/pts/1"
 *   }
 *
 * In the non-block form, returns a two element array, <tt>[controller_io,
 * worker_file]</tt>.
 *
 *   controller, worker = PTY.open
 *   # do something with controller for IO, or the worker file
 *
 * The arguments in both forms are:
 *
 * +controller_io+:: the controller of the pty, as an IO.
 * +worker_file+::   the worker of the pty, as a File. The path to the
 *                   terminal device is available via +worker_file.path+
 *
 * IO#raw! is usable to disable newline conversions:
 *
 *   require 'io/console'
 *   PTY.open {|c, w|
 *     w.raw!
 *     # ...
 *   }
 *
 */
static VALUE
pty_open(VALUE klass)
{
    int controller_fd, worker_fd;
    char workername[DEVICELEN];
    VALUE controller_io, worker_file;
    rb_io_t *controller_fptr, *worker_fptr;
    VALUE assoc;

    getDevice(&controller_fd, &worker_fd, workername, 1);

    controller_io = rb_obj_alloc(rb_cIO);
    MakeOpenFile(controller_io, controller_fptr);
    controller_fptr->mode = FMODE_READWRITE | FMODE_SYNC | FMODE_DUPLEX;
    controller_fptr->fd = controller_fd;
    controller_fptr->pathv = rb_obj_freeze(rb_sprintf("controllerpty:%s", workername));

    worker_file = rb_obj_alloc(rb_cFile);
    MakeOpenFile(worker_file, worker_fptr);
    worker_fptr->mode = FMODE_READWRITE | FMODE_SYNC | FMODE_DUPLEX | FMODE_TTY;
    worker_fptr->fd = worker_fd;
    worker_fptr->pathv = rb_obj_freeze(rb_str_new_cstr(workername));

    assoc = rb_assoc_new(controller_io, worker_file);
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, assoc, pty_close_pty, assoc);
    }
    return assoc;
}

static VALUE
pty_detach_process(VALUE v)
{
    struct pty_info *info = (void *)v;
#ifdef WNOHANG
    int st;
    if (rb_waitpid(info->child_pid, &st, WNOHANG) <= 0)
	return Qnil;
#endif
    rb_detach_process(info->child_pid);
    return Qnil;
}

/*
 * call-seq:
 *   PTY.spawn(command_line)  { |r, w, pid| ... }
 *   PTY.spawn(command_line)  => [r, w, pid]
 *   PTY.spawn(command, arguments, ...)  { |r, w, pid| ... }
 *   PTY.spawn(command, arguments, ...)  => [r, w, pid]
 *
 * Spawns the specified command on a newly allocated pty. You can also use the
 * alias ::getpty.
 *
 * The command's controlling tty is set to the worker device of the pty
 * and its standard input/output/error is redirected to the worker device.
 *
 * +command+ and +command_line+ are the full commands to run, given a String.
 * Any additional +arguments+ will be passed to the command.
 *
 * === Return values
 *
 * In the non-block form this returns an array of size three,
 * <tt>[r, w, pid]</tt>.
 *
 * In the block form these same values will be yielded to the block:
 *
 * +r+:: A readable IO that contains the command's
 *       standard output and standard error
 * +w+:: A writable IO that is the command's standard input
 * +pid+:: The process identifier for the command.
 */
static VALUE
pty_getpty(int argc, VALUE *argv, VALUE self)
{
    VALUE res;
    struct pty_info info;
    rb_io_t *wfptr,*rfptr;
    VALUE rport = rb_obj_alloc(rb_cFile);
    VALUE wport = rb_obj_alloc(rb_cFile);
    char WorkerName[DEVICELEN];

    MakeOpenFile(rport, rfptr);
    MakeOpenFile(wport, wfptr);

    establishShell(argc, argv, &info, WorkerName);

    rfptr->mode = rb_io_modestr_fmode("r");
    rfptr->fd = info.fd;
    rfptr->pathv = rb_obj_freeze(rb_str_new_cstr(WorkerName));

    wfptr->mode = rb_io_modestr_fmode("w") | FMODE_SYNC;
    wfptr->fd = rb_cloexec_dup(info.fd);
    if (wfptr->fd == -1)
        rb_sys_fail("dup()");
    rb_update_max_fd(wfptr->fd);
    wfptr->pathv = rfptr->pathv;

    res = rb_ary_new2(3);
    rb_ary_store(res,0,(VALUE)rport);
    rb_ary_store(res,1,(VALUE)wport);
    rb_ary_store(res,2,PIDT2NUM(info.child_pid));

    if (rb_block_given_p()) {
	rb_ensure(rb_yield, res, pty_detach_process, (VALUE)&info);
	return Qnil;
    }
    return res;
}

NORETURN(static void raise_from_check(rb_pid_t pid, int status));
static void
raise_from_check(rb_pid_t pid, int status)
{
    const char *state;
    VALUE msg;
    VALUE exc;

#if defined(WIFSTOPPED)
#elif defined(IF_STOPPED)
#define WIFSTOPPED(status) IF_STOPPED(status)
#else
---->> Either IF_STOPPED or WIFSTOPPED is needed <<----
#endif /* WIFSTOPPED | IF_STOPPED */
    if (WIFSTOPPED(status)) { /* suspend */
	state = "stopped";
    }
    else if (kill(pid, 0) == 0) {
	state = "changed";
    }
    else {
	state = "exited";
    }
    msg = rb_sprintf("pty - %s: %ld", state, (long)pid);
    exc = rb_exc_new_str(eChildExited, msg);
    rb_iv_set(exc, "status", rb_last_status_get());
    rb_exc_raise(exc);
}

/*
 * call-seq:
 *   PTY.check(pid, raise = false) => Process::Status or nil
 *   PTY.check(pid, true)          => nil or raises PTY::ChildExited
 *
 * Checks the status of the child process specified by +pid+.
 * Returns +nil+ if the process is still alive.
 *
 * If the process is not alive, and +raise+ was true, a PTY::ChildExited
 * exception will be raised. Otherwise it will return a Process::Status
 * instance.
 *
 * +pid+:: The process id of the process to check
 * +raise+:: If +true+ and the process identified by +pid+ is no longer
 *           alive a PTY::ChildExited is raised.
 *
 */
static VALUE
pty_check(int argc, VALUE *argv, VALUE self)
{
    VALUE pid, exc;
    rb_pid_t cpid;
    int status;
    const int flag =
#ifdef WNOHANG
	WNOHANG|
#endif
#ifdef WUNTRACED
	WUNTRACED|
#endif
	0;

    rb_scan_args(argc, argv, "11", &pid, &exc);
    cpid = rb_waitpid(NUM2PIDT(pid), &status, flag);
    if (cpid == -1 || cpid == 0) return Qnil;

    if (!RTEST(exc)) return rb_last_status_get();
    raise_from_check(cpid, status);

    UNREACHABLE_RETURN(Qnil);
}

static VALUE cPTY;

/*
 * Document-class: PTY::ChildExited
 *
 * Thrown when PTY::check is called for a pid that represents a process that
 * has exited.
 */

/*
 * Document-class: PTY
 *
 * Creates and manages pseudo terminals (PTYs).  See also
 * https://en.wikipedia.org/wiki/Pseudo_terminal
 *
 * PTY allows you to allocate new terminals using ::open or ::spawn a new
 * terminal with a specific command.
 *
 * == Example
 *
 * In this example we will change the buffering type in the +factor+ command,
 * assuming that factor uses stdio for stdout buffering.
 *
 * If IO.pipe is used instead of PTY.open, this code deadlocks because factor's
 * stdout is fully buffered.
 *
 *   # start by requiring the standard library PTY
 *   require 'pty'
 *
 *   controller, worker = PTY.open
 *   read, write = IO.pipe
 *   pid = spawn("factor", :in=>read, :out=>worker)
 *   read.close	   # we dont need the read
 *   worker.close  # or the worker
 *
 *   # pipe "42" to the factor command
 *   write.puts "42"
 *   # output the response from factor
 *   p controller.gets #=> "42: 2 3 7\n"
 *
 *   # pipe "144" to factor and print out the response
 *   write.puts "144"
 *   p controller.gets #=> "144: 2 2 2 2 3 3\n"
 *   write.close # close the pipe
 *
 *   # The result of read operation when pty worker is closed is platform
 *   # dependent.
 *   ret = begin
 *           controller.gets # FreeBSD returns nil.
 *         rescue Errno::EIO # GNU/Linux raises EIO.
 *           nil
 *         end
 *   p ret #=> nil
 *
 * == License
 *
 * (c) Copyright 1998 by Akinori Ito.
 *
 * This software may be redistributed freely for this purpose, in full
 * or in part, provided that this entire copyright notice is included
 * on any copies of this software and applications and derivations thereof.
 *
 * This software is provided on an "as is" basis, without warranty of any
 * kind, either expressed or implied, as to any matter including, but not
 * limited to warranty of fitness of purpose, or merchantability, or
 * results obtained from use of this software.
 */

void
Init_pty(void)
{
    cPTY = rb_define_module("PTY");
    /* :nodoc: */
    rb_define_module_function(cPTY,"getpty",pty_getpty,-1);
    rb_define_module_function(cPTY,"spawn",pty_getpty,-1);
    rb_define_singleton_method(cPTY,"check",pty_check,-1);
    rb_define_singleton_method(cPTY,"open",pty_open,0);

    eChildExited = rb_define_class_under(cPTY,"ChildExited",rb_eRuntimeError);
    rb_define_method(eChildExited,"status",echild_status,0);
}
