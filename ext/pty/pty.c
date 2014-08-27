#include	"ruby/config.h"
#ifdef RUBY_EXTCONF_H
#include RUBY_EXTCONF_H
#endif
#include	<stdlib.h>
#include	<stdio.h>
#include	<sys/types.h>
#include	<sys/stat.h>
#include	<sys/file.h>
#include	<fcntl.h>
#include	<errno.h>
#include	<pwd.h>
#ifdef HAVE_SYS_IOCTL_H
#include	<sys/ioctl.h>
#endif
#ifdef HAVE_LIBUTIL_H
#include	<libutil.h>
#endif
#ifdef HAVE_UTIL_H
#include	<util.h>
#endif
#ifdef HAVE_PTY_H
#include	<pty.h>
#endif
#if defined(HAVE_SYS_PARAM_H)
  /* for __FreeBSD_version */
# include <sys/param.h>
#endif
#ifdef HAVE_SYS_WAIT_H
#include <sys/wait.h>
#else
#define WIFSTOPPED(status)    (((status) & 0xff) == 0x7f)
#endif
#include <ctype.h>

#include "ruby/ruby.h"
#include "ruby/io.h"
#include "ruby/util.h"
#include "internal.h"

#include <signal.h>
#ifdef HAVE_SYS_STROPTS_H
#include <sys/stropts.h>
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

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
    int master, slave;
    char *slavename;
    VALUE execarg_obj;
    struct rb_execarg *eargp;
};

static int
chfunc(void *data, char *errbuf, size_t errbuf_len)
{
    struct child_info *carg = data;
    int master = carg->master;
    int slave = carg->slave;

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
    close(master);
    (void) ioctl(slave, TIOCSCTTY, (char *)0);
    /* errors ignored for sun */
#else
    close(slave);
    slave = rb_cloexec_open(carg->slavename, O_RDWR, 0);
    if (slave < 0) {
        ERROR_EXIT("open: pty slave");
    }
    rb_update_max_fd(slave);
    close(master);
#endif
    dup2(slave,0);
    dup2(slave,1);
    dup2(slave,2);
    close(slave);
#if defined(HAVE_SETEUID) || defined(HAVE_SETREUID) || defined(HAVE_SETRESUID)
    if (seteuid(getuid())) ERROR_EXIT("seteuid()");
#endif

    return rb_exec_async_signal_safe(carg->eargp, errbuf, sizeof(errbuf_len));
#undef ERROR_EXIT
}

static void
establishShell(int argc, VALUE *argv, struct pty_info *info,
	       char SlaveName[DEVICELEN])
{
    int 		master, slave, status = 0;
    rb_pid_t		pid;
    char		*p, *getenv();
    struct passwd	*pwent;
    VALUE		v;
    struct child_info   carg;
    char		errbuf[32];

    if (argc == 0) {
	const char *shellname;

	if ((p = getenv("SHELL")) != NULL) {
	    shellname = p;
	}
	else {
	    pwent = getpwuid(getuid());
	    if (pwent && pwent->pw_shell)
		shellname = pwent->pw_shell;
	    else
		shellname = "/bin/sh";
	}
	v = rb_str_new2(shellname);
	argc = 1;
	argv = &v;
    }

    carg.execarg_obj = rb_execarg_new(argc, argv, 1);
    carg.eargp = rb_execarg_get(carg.execarg_obj);
    rb_execarg_fixup(carg.execarg_obj);

    getDevice(&master, &slave, SlaveName, 0);

    carg.master = master;
    carg.slave = slave;
    carg.slavename = SlaveName;
    errbuf[0] = '\0';
    pid = rb_fork_async_signal_safe(&status, chfunc, &carg, Qnil, errbuf, sizeof(errbuf));

    if (pid < 0) {
	int e = errno;
	close(master);
	close(slave);
	errno = e;
	if (status) rb_jump_tag(status);
	rb_sys_fail(errbuf[0] ? errbuf : "fork failed");
    }

    close(slave);

    info->child_pid = pid;
    info->fd = master;

    RB_GC_GUARD(carg.execarg_obj);
}

static int
no_mesg(char *slavedevice, int nomesg)
{
    if (nomesg)
        return chmod(slavedevice, 0600);
    else
        return 0;
}

static int
get_device_once(int *master, int *slave, char SlaveName[DEVICELEN], int nomesg, int fail)
{
#if defined(HAVE_POSIX_OPENPT)
    /* Unix98 PTY */
    int masterfd = -1, slavefd = -1;
    char *slavedevice;
    struct sigaction dfl, old;

    dfl.sa_handler = SIG_DFL;
    dfl.sa_flags = 0;
    sigemptyset(&dfl.sa_mask);

#if defined(__sun) || (defined(__FreeBSD__) && __FreeBSD_version < 902000)
    /* workaround for Solaris 10: grantpt() doesn't work if FD_CLOEXEC is set.  [ruby-dev:44688] */
    /* FreeBSD 9.2 or later supports O_CLOEXEC
     * http://www.freebsd.org/cgi/query-pr.cgi?pr=162374 */
    if ((masterfd = posix_openpt(O_RDWR|O_NOCTTY)) == -1) goto error;
    if (sigaction(SIGCHLD, &dfl, &old) == -1) goto error;
    if (grantpt(masterfd) == -1) goto grantpt_error;
    rb_fd_fix_cloexec(masterfd);
#else
    {
	int flags = O_RDWR|O_NOCTTY;
# if defined(O_CLOEXEC)
	/* glibc posix_openpt() in GNU/Linux calls open("/dev/ptmx", flags) internally.
	 * So version dependency on GNU/Linux is same as O_CLOEXEC with open().
	 * O_CLOEXEC is available since Linux 2.6.23.  Linux 2.6.18 silently ignore it. */
	flags |= O_CLOEXEC;
# endif
	if ((masterfd = posix_openpt(flags)) == -1) goto error;
    }
    rb_fd_fix_cloexec(masterfd);
    if (sigaction(SIGCHLD, &dfl, &old) == -1) goto error;
    if (grantpt(masterfd) == -1) goto grantpt_error;
#endif
    if (sigaction(SIGCHLD, &old, NULL) == -1) goto error;
    if (unlockpt(masterfd) == -1) goto error;
    if ((slavedevice = ptsname(masterfd)) == NULL) goto error;
    if (no_mesg(slavedevice, nomesg) == -1) goto error;
    if ((slavefd = rb_cloexec_open(slavedevice, O_RDWR|O_NOCTTY, 0)) == -1) goto error;
    rb_update_max_fd(slavefd);

#if defined(I_PUSH) && !defined(__linux__)
    if (ioctl(slavefd, I_PUSH, "ptem") == -1) goto error;
    if (ioctl(slavefd, I_PUSH, "ldterm") == -1) goto error;
    if (ioctl(slavefd, I_PUSH, "ttcompat") == -1) goto error;
#endif

    *master = masterfd;
    *slave = slavefd;
    strlcpy(SlaveName, slavedevice, DEVICELEN);
    return 0;

  grantpt_error:
    sigaction(SIGCHLD, &old, NULL);
  error:
    if (slavefd != -1) close(slavefd);
    if (masterfd != -1) close(masterfd);
    if (fail) {
        rb_raise(rb_eRuntimeError, "can't get Master/Slave device");
    }
    return -1;
#elif defined HAVE_OPENPTY
/*
 * Use openpty(3) of 4.3BSD Reno and later,
 * or the same interface function.
 */
    if (openpty(master, slave, SlaveName,
		(struct termios *)0, (struct winsize *)0) == -1) {
	if (!fail) return -1;
	rb_raise(rb_eRuntimeError, "openpty() failed");
    }
    rb_fd_fix_cloexec(*master);
    rb_fd_fix_cloexec(*slave);
    if (no_mesg(SlaveName, nomesg) == -1) {
	if (!fail) return -1;
	rb_raise(rb_eRuntimeError, "can't chmod slave pty");
    }

    return 0;

#elif defined HAVE__GETPTY
    /* SGI IRIX */
    char *name;
    mode_t mode = nomesg ? 0600 : 0622;

    if (!(name = _getpty(master, O_RDWR, mode, 0))) {
	if (!fail) return -1;
	rb_raise(rb_eRuntimeError, "_getpty() failed");
    }
    rb_fd_fix_cloexec(*master);

    *slave = rb_cloexec_open(name, O_RDWR, 0);
    /* error check? */
    rb_update_max_fd(*slave);
    strlcpy(SlaveName, name, DEVICELEN);

    return 0;
#elif defined(HAVE_PTSNAME)
    /* System V */
    int	 masterfd = -1, slavefd = -1;
    char *slavedevice;
    void (*s)();

    extern char *ptsname(int);
    extern int unlockpt(int);
    extern int grantpt(int);

#if defined(__sun)
    /* workaround for Solaris 10: grantpt() doesn't work if FD_CLOEXEC is set.  [ruby-dev:44688] */
    if((masterfd = open("/dev/ptmx", O_RDWR, 0)) == -1) goto error;
    s = signal(SIGCHLD, SIG_DFL);
    if(grantpt(masterfd) == -1) goto error;
    rb_fd_fix_cloexec(masterfd);
#else
    if((masterfd = rb_cloexec_open("/dev/ptmx", O_RDWR, 0)) == -1) goto error;
    rb_update_max_fd(masterfd);
    s = signal(SIGCHLD, SIG_DFL);
    if(grantpt(masterfd) == -1) goto error;
#endif
    signal(SIGCHLD, s);
    if(unlockpt(masterfd) == -1) goto error;
    if((slavedevice = ptsname(masterfd)) == NULL) goto error;
    if (no_mesg(slavedevice, nomesg) == -1) goto error;
    if((slavefd = rb_cloexec_open(slavedevice, O_RDWR, 0)) == -1) goto error;
    rb_update_max_fd(slavefd);
#if defined(I_PUSH) && !defined(__linux__)
    if(ioctl(slavefd, I_PUSH, "ptem") == -1) goto error;
    if(ioctl(slavefd, I_PUSH, "ldterm") == -1) goto error;
    ioctl(slavefd, I_PUSH, "ttcompat");
#endif
    *master = masterfd;
    *slave = slavefd;
    strlcpy(SlaveName, slavedevice, DEVICELEN);
    return 0;

  error:
    if (slavefd != -1) close(slavefd);
    if (masterfd != -1) close(masterfd);
    if (fail) rb_raise(rb_eRuntimeError, "can't get Master/Slave device");
    return -1;
#else
    /* BSD */
    int	 masterfd = -1, slavefd = -1;
    const char *const *p;
    char MasterName[DEVICELEN];

#if defined(__hpux)
    static const char MasterDevice[] = "/dev/ptym/pty%s";
    static const char SlaveDevice[] =  "/dev/pty/tty%s";
    static const char *const deviceNo[] = {
    "p0","p1","p2","p3","p4","p5","p6","p7",
    "p8","p9","pa","pb","pc","pd","pe","pf",
    "q0","q1","q2","q3","q4","q5","q6","q7",
    "q8","q9","qa","qb","qc","qd","qe","qf",
    "r0","r1","r2","r3","r4","r5","r6","r7",
    "r8","r9","ra","rb","rc","rd","re","rf",
    "s0","s1","s2","s3","s4","s5","s6","s7",
    "s8","s9","sa","sb","sc","sd","se","sf",
    "t0","t1","t2","t3","t4","t5","t6","t7",
    "t8","t9","ta","tb","tc","td","te","tf",
    "u0","u1","u2","u3","u4","u5","u6","u7",
    "u8","u9","ua","ub","uc","ud","ue","uf",
    "v0","v1","v2","v3","v4","v5","v6","v7",
    "v8","v9","va","vb","vc","vd","ve","vf",
    "w0","w1","w2","w3","w4","w5","w6","w7",
    "w8","w9","wa","wb","wc","wd","we","wf",
    0
    };
#elif defined(_IBMESA)  /* AIX/ESA */
    static const char MasterDevice[] = "/dev/ptyp%s";
    static const char SlaveDevice[] = "/dev/ttyp%s";
    static const char *const deviceNo[] = {
    "00","01","02","03","04","05","06","07","08","09","0a","0b","0c","0d","0e","0f",
    "10","11","12","13","14","15","16","17","18","19","1a","1b","1c","1d","1e","1f",
    "20","21","22","23","24","25","26","27","28","29","2a","2b","2c","2d","2e","2f",
    "30","31","32","33","34","35","36","37","38","39","3a","3b","3c","3d","3e","3f",
    "40","41","42","43","44","45","46","47","48","49","4a","4b","4c","4d","4e","4f",
    "50","51","52","53","54","55","56","57","58","59","5a","5b","5c","5d","5e","5f",
    "60","61","62","63","64","65","66","67","68","69","6a","6b","6c","6d","6e","6f",
    "70","71","72","73","74","75","76","77","78","79","7a","7b","7c","7d","7e","7f",
    "80","81","82","83","84","85","86","87","88","89","8a","8b","8c","8d","8e","8f",
    "90","91","92","93","94","95","96","97","98","99","9a","9b","9c","9d","9e","9f",
    "a0","a1","a2","a3","a4","a5","a6","a7","a8","a9","aa","ab","ac","ad","ae","af",
    "b0","b1","b2","b3","b4","b5","b6","b7","b8","b9","ba","bb","bc","bd","be","bf",
    "c0","c1","c2","c3","c4","c5","c6","c7","c8","c9","ca","cb","cc","cd","ce","cf",
    "d0","d1","d2","d3","d4","d5","d6","d7","d8","d9","da","db","dc","dd","de","df",
    "e0","e1","e2","e3","e4","e5","e6","e7","e8","e9","ea","eb","ec","ed","ee","ef",
    "f0","f1","f2","f3","f4","f5","f6","f7","f8","f9","fa","fb","fc","fd","fe","ff",
    0
    };
#else /* 4.2BSD */
    static const char MasterDevice[] = "/dev/pty%s";
    static const char SlaveDevice[] = "/dev/tty%s";
    static const char *const deviceNo[] = {
    "p0","p1","p2","p3","p4","p5","p6","p7",
    "p8","p9","pa","pb","pc","pd","pe","pf",
    "q0","q1","q2","q3","q4","q5","q6","q7",
    "q8","q9","qa","qb","qc","qd","qe","qf",
    "r0","r1","r2","r3","r4","r5","r6","r7",
    "r8","r9","ra","rb","rc","rd","re","rf",
    "s0","s1","s2","s3","s4","s5","s6","s7",
    "s8","s9","sa","sb","sc","sd","se","sf",
    0
    };
#endif
    for (p = deviceNo; *p != NULL; p++) {
	snprintf(MasterName, sizeof MasterName, MasterDevice, *p);
	if ((masterfd = rb_cloexec_open(MasterName,O_RDWR,0)) >= 0) {
            rb_update_max_fd(masterfd);
	    *master = masterfd;
	    snprintf(SlaveName, DEVICELEN, SlaveDevice, *p);
	    if ((slavefd = rb_cloexec_open(SlaveName,O_RDWR,0)) >= 0) {
                rb_update_max_fd(slavefd);
		*slave = slavefd;
		if (chown(SlaveName, getuid(), getgid()) != 0) goto error;
		if (chmod(SlaveName, nomesg ? 0600 : 0622) != 0) goto error;
		return 0;
	    }
	    close(masterfd);
	}
    }
  error:
    if (slavefd != -1) close(slavefd);
    if (masterfd != -1) close(masterfd);
    if (fail) rb_raise(rb_eRuntimeError, "can't get %s", SlaveName);
    return -1;
#endif
}

static void
getDevice(int *master, int *slave, char SlaveName[DEVICELEN], int nomesg)
{
    if (get_device_once(master, slave, SlaveName, nomesg, 0)) {
	rb_gc();
	get_device_once(master, slave, SlaveName, nomesg, 1);
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
 *   PTY.open => [master_io, slave_file]
 *   PTY.open {|master_io, slave_file| ... } => block value
 *
 * Allocates a pty (pseudo-terminal).
 *
 * In the block form, yields two arguments <tt>master_io, slave_file</tt>
 * and the value of the block is returned from +open+.
 *
 * The IO and File are both closed after the block completes if they haven't
 * been already closed.
 *
 *   PTY.open {|master, slave|
 *     p master      #=> #<IO:masterpty:/dev/pts/1>
 *     p slave      #=> #<File:/dev/pts/1>
 *     p slave.path #=> "/dev/pts/1"
 *   }
 *
 * In the non-block form, returns a two element array, <tt>[master_io,
 * slave_file]</tt>.
 *
 *   master, slave = PTY.open
 *   # do something with master for IO, or the slave file
 *
 * The arguments in both forms are:
 *
 * +master_io+::    the master of the pty, as an IO.
 * +slave_file+::   the slave of the pty, as a File.  The path to the
 *		    terminal device is available via +slave_file.path+
 *
 */
static VALUE
pty_open(VALUE klass)
{
    int master_fd, slave_fd;
    char slavename[DEVICELEN];
    VALUE master_io, slave_file;
    rb_io_t *master_fptr, *slave_fptr;
    VALUE assoc;

    getDevice(&master_fd, &slave_fd, slavename, 1);

    master_io = rb_obj_alloc(rb_cIO);
    MakeOpenFile(master_io, master_fptr);
    master_fptr->mode = FMODE_READWRITE | FMODE_SYNC | FMODE_DUPLEX;
    master_fptr->fd = master_fd;
    master_fptr->pathv = rb_obj_freeze(rb_sprintf("masterpty:%s", slavename));

    slave_file = rb_obj_alloc(rb_cFile);
    MakeOpenFile(slave_file, slave_fptr);
    slave_fptr->mode = FMODE_READWRITE | FMODE_SYNC | FMODE_DUPLEX | FMODE_TTY;
    slave_fptr->fd = slave_fd;
    slave_fptr->pathv = rb_obj_freeze(rb_str_new_cstr(slavename));

    assoc = rb_assoc_new(master_io, slave_file);
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, assoc, pty_close_pty, assoc);
    }
    return assoc;
}

static VALUE
pty_detach_process(struct pty_info *info)
{
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
 * The command's controlling tty is set to the slave device of the pty
 * and its standard input/output/error is redirected to the slave device.
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
 * +r+:: A readable IO that that contains the command's
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
    char SlaveName[DEVICELEN];

    MakeOpenFile(rport, rfptr);
    MakeOpenFile(wport, wfptr);

    establishShell(argc, argv, &info, SlaveName);

    rfptr->mode = rb_io_mode_flags("r");
    rfptr->fd = info.fd;
    rfptr->pathv = rb_obj_freeze(rb_str_new_cstr(SlaveName));

    wfptr->mode = rb_io_mode_flags("w") | FMODE_SYNC;
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

    rb_scan_args(argc, argv, "11", &pid, &exc);
    cpid = rb_waitpid(NUM2PIDT(pid), &status, WNOHANG|WUNTRACED);
    if (cpid == -1 || cpid == 0) return Qnil;

    if (!RTEST(exc)) return rb_last_status_get();
    raise_from_check(cpid, status);

    UNREACHABLE;
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
 * Creates and managed pseudo terminals (PTYs).  See also
 * http://en.wikipedia.org/wiki/Pseudo_terminal
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
 *   master, slave = PTY.open
 *   read, write = IO.pipe
 *   pid = spawn("factor", :in=>read, :out=>slave)
 *   read.close	    # we dont need the read
 *   slave.close    # or the slave
 *
 *   # pipe "42" to the factor command
 *   write.puts "42"
 *   # output the response from factor
 *   p master.gets #=> "42: 2 3 7\n"
 *
 *   # pipe "144" to factor and print out the response
 *   write.puts "144"
 *   p master.gets #=> "144: 2 2 2 2 3 3\n"
 *   write.close # close the pipe
 *
 *   # The result of read operation when pty slave is closed is platform
 *   # dependent.
 *   ret = begin
 *           m.gets          # FreeBSD returns nil.
 *         rescue Errno::EIO # GNU/Linux raises EIO.
 *           nil
 *         end
 *   p ret #=> nil
 *
 * == License
 *
 *  C) Copyright 1998 by Akinori Ito.
 *
 *  This software may be redistributed freely for this purpose, in full
 *  or in part, provided that this entire copyright notice is included
 *  on any copies of this software and applications and derivations thereof.
 *
 *  This software is provided on an "as is" basis, without warranty of any
 *  kind, either expressed or implied, as to any matter including, but not
 *  limited to warranty of fitness of purpose, or merchantability, or
 *  results obtained from use of this software.
 */

void
Init_pty()
{
    cPTY = rb_define_module("PTY");
    /* :nodoc */
    rb_define_module_function(cPTY,"getpty",pty_getpty,-1);
    rb_define_module_function(cPTY,"spawn",pty_getpty,-1);
    rb_define_singleton_method(cPTY,"check",pty_check,-1);
    rb_define_singleton_method(cPTY,"open",pty_open,0);

    eChildExited = rb_define_class_under(cPTY,"ChildExited",rb_eRuntimeError);
    rb_define_method(eChildExited,"status",echild_status,0);
}
