/**********************************************************************

  io.c -

  $Author$
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#include "ruby/fiber/scheduler.h"
#include "ruby/io/buffer.h"

#include <ctype.h>
#include <errno.h>
#include <stddef.h>

/* non-Linux poll may not work on all FDs */
#if defined(HAVE_POLL)
# if defined(__linux__)
#   define USE_POLL 1
# endif
# if defined(__FreeBSD_version) && __FreeBSD_version >= 1100000
#  define USE_POLL 1
# endif
#endif

#ifndef USE_POLL
# define USE_POLL 0
#endif

#undef free
#define free(x) xfree(x)

#if defined(DOSISH) || defined(__CYGWIN__)
#include <io.h>
#endif

#include <sys/types.h>
#if defined HAVE_NET_SOCKET_H
# include <net/socket.h>
#elif defined HAVE_SYS_SOCKET_H
# include <sys/socket.h>
#endif

#if defined(__BOW__) || defined(__CYGWIN__) || defined(_WIN32)
# define NO_SAFE_RENAME
#endif

#if defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__DragonFly__) || defined(__sun) || defined(_nec_ews)
# define USE_SETVBUF
#endif

#ifdef __QNXNTO__
#include <unix.h>
#endif

#include <sys/types.h>
#if defined(HAVE_SYS_IOCTL_H) && !defined(_WIN32)
#include <sys/ioctl.h>
#endif
#if defined(HAVE_FCNTL_H) || defined(_WIN32)
#include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
#include <sys/fcntl.h>
#endif

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#endif

#include <sys/stat.h>

#if defined(HAVE_SYS_PARAM_H) || defined(__HIUX_MPP__)
# include <sys/param.h>
#endif

#if !defined NOFILE
# define NOFILE 64
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_SYSCALL_H
#include <syscall.h>
#elif defined HAVE_SYS_SYSCALL_H
#include <sys/syscall.h>
#endif

#ifdef HAVE_SYS_UIO_H
#include <sys/uio.h>
#endif

#ifdef HAVE_SYS_WAIT_H
# include <sys/wait.h>		/* for WNOHANG on BSD */
#endif

#ifdef HAVE_COPYFILE_H
# include <copyfile.h>

# ifndef COPYFILE_STATE_COPIED
/*
 * Some OSes (e.g., OSX < 10.6) implement fcopyfile() but not
 * COPYFILE_STATE_COPIED.  Since the only use of the former here
 * requires the latter, we disable the former when the latter is undefined.
 */
#   undef HAVE_FCOPYFILE
# endif

#endif

#include "ruby/internal/stdbool.h"
#include "ccan/list/list.h"
#include "dln.h"
#include "encindex.h"
#include "id.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/encoding.h"
#include "internal/error.h"
#include "internal/inits.h"
#include "internal/io.h"
#include "internal/numeric.h"
#include "internal/object.h"
#include "internal/process.h"
#include "internal/thread.h"
#include "internal/transcode.h"
#include "internal/variable.h"
#include "ruby/io.h"
#include "ruby/io/buffer.h"
#include "ruby/missing.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "ruby_atomic.h"
#include "ruby/ractor.h"

#if !USE_POLL
#  include "vm_core.h"
#endif

#include "builtin.h"

#ifndef O_ACCMODE
#define O_ACCMODE (O_RDONLY | O_WRONLY | O_RDWR)
#endif

#ifndef PIPE_BUF
# ifdef _POSIX_PIPE_BUF
#  define PIPE_BUF _POSIX_PIPE_BUF
# else
#  define PIPE_BUF 512 /* is this ok? */
# endif
#endif

#ifndef EWOULDBLOCK
# define EWOULDBLOCK EAGAIN
#endif

#if defined(HAVE___SYSCALL) && (defined(__APPLE__) || defined(__OpenBSD__))
/* Mac OS X and OpenBSD have __syscall but don't define it in headers */
off_t __syscall(quad_t number, ...);
#endif

#define IO_RBUF_CAPA_MIN  8192
#define IO_CBUF_CAPA_MIN  (128*1024)
#define IO_RBUF_CAPA_FOR(fptr) (NEED_READCONV(fptr) ? IO_CBUF_CAPA_MIN : IO_RBUF_CAPA_MIN)
#define IO_WBUF_CAPA_MIN  8192

#define IO_MAX_BUFFER_GROWTH 8 * 1024 * 1024 // 8MB

/* define system APIs */
#ifdef _WIN32
#undef open
#define open	rb_w32_uopen
#undef rename
#define rename(f, t)	rb_w32_urename((f), (t))
#include "win32/file.h"
#endif

VALUE rb_cIO;
VALUE rb_eEOFError;
VALUE rb_eIOError;
VALUE rb_eIOTimeoutError;
VALUE rb_mWaitReadable;
VALUE rb_mWaitWritable;

static VALUE rb_eEAGAINWaitReadable;
static VALUE rb_eEAGAINWaitWritable;
static VALUE rb_eEWOULDBLOCKWaitReadable;
static VALUE rb_eEWOULDBLOCKWaitWritable;
static VALUE rb_eEINPROGRESSWaitWritable;
static VALUE rb_eEINPROGRESSWaitReadable;

VALUE rb_stdin, rb_stdout, rb_stderr;
static VALUE orig_stdout, orig_stderr;

VALUE rb_output_fs;
VALUE rb_rs;
VALUE rb_output_rs;
VALUE rb_default_rs;

static VALUE argf;

static ID id_write, id_read, id_getc, id_flush, id_readpartial, id_set_encoding, id_fileno;
static VALUE sym_mode, sym_perm, sym_flags, sym_extenc, sym_intenc, sym_encoding, sym_open_args;
static VALUE sym_textmode, sym_binmode, sym_autoclose;
static VALUE sym_SET, sym_CUR, sym_END;
static VALUE sym_wait_readable, sym_wait_writable;
#ifdef SEEK_DATA
static VALUE sym_DATA;
#endif
#ifdef SEEK_HOLE
static VALUE sym_HOLE;
#endif

static VALUE prep_io(int fd, enum rb_io_mode fmode, VALUE klass, const char *path);

VALUE
rb_io_blocking_region_wait(struct rb_io *io, rb_blocking_function_t *function, void *argument, enum rb_io_event events)
{
    return rb_thread_io_blocking_call(io, function, argument, events);
}

VALUE rb_io_blocking_region(struct rb_io *io, rb_blocking_function_t *function, void *argument)
{
    return rb_io_blocking_region_wait(io, function, argument, 0);
}

struct argf {
    VALUE filename, current_file;
    long last_lineno;		/* $. */
    long lineno;
    VALUE argv;
    VALUE inplace;
    struct rb_io_encoding encs;
    int8_t init_p, next_p, binmode;
};

static rb_atomic_t max_file_descriptor = NOFILE;
void
rb_update_max_fd(int fd)
{
    rb_atomic_t afd = (rb_atomic_t)fd;
    rb_atomic_t max_fd = max_file_descriptor;
    int err;

    if (fd < 0 || afd <= max_fd)
        return;

#if defined(HAVE_FCNTL) && defined(F_GETFL)
    err = fcntl(fd, F_GETFL) == -1;
#else
    {
        struct stat buf;
        err = fstat(fd, &buf) != 0;
    }
#endif
    if (err && errno == EBADF) {
        rb_bug("rb_update_max_fd: invalid fd (%d) given.", fd);
    }

    while (max_fd < afd) {
        max_fd = ATOMIC_CAS(max_file_descriptor, max_fd, afd);
    }
}

void
rb_maygvl_fd_fix_cloexec(int fd)
{
  /* MinGW don't have F_GETFD and FD_CLOEXEC.  [ruby-core:40281] */
#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(F_SETFD) && defined(FD_CLOEXEC)
    int flags, flags2, ret;
    flags = fcntl(fd, F_GETFD); /* should not fail except EBADF. */
    if (flags == -1) {
        rb_bug("rb_maygvl_fd_fix_cloexec: fcntl(%d, F_GETFD) failed: %s", fd, strerror(errno));
    }
    if (fd <= 2)
        flags2 = flags & ~FD_CLOEXEC; /* Clear CLOEXEC for standard file descriptors: 0, 1, 2. */
    else
        flags2 = flags | FD_CLOEXEC; /* Set CLOEXEC for non-standard file descriptors: 3, 4, 5, ... */
    if (flags != flags2) {
        ret = fcntl(fd, F_SETFD, flags2);
        if (ret != 0) {
            rb_bug("rb_maygvl_fd_fix_cloexec: fcntl(%d, F_SETFD, %d) failed: %s", fd, flags2, strerror(errno));
        }
    }
#endif
}

void
rb_fd_fix_cloexec(int fd)
{
    rb_maygvl_fd_fix_cloexec(fd);
    rb_update_max_fd(fd);
}

/* this is only called once */
static int
rb_fix_detect_o_cloexec(int fd)
{
#if defined(O_CLOEXEC) && defined(F_GETFD)
    int flags = fcntl(fd, F_GETFD);

    if (flags == -1)
        rb_bug("rb_fix_detect_o_cloexec: fcntl(%d, F_GETFD) failed: %s", fd, strerror(errno));

    if (flags & FD_CLOEXEC)
        return 1;
#endif /* fall through if O_CLOEXEC does not work: */
    rb_maygvl_fd_fix_cloexec(fd);
    return 0;
}

static inline bool
io_again_p(int e)
{
    return (e == EWOULDBLOCK) || (e == EAGAIN);
}

int
rb_cloexec_open(const char *pathname, int flags, mode_t mode)
{
    int ret;
    static int o_cloexec_state = -1; /* <0: unknown, 0: ignored, >0: working */

    static const int retry_interval = 0;
    static const int retry_max_count = 10000;

    int retry_count = 0;

#ifdef O_CLOEXEC
    /* O_CLOEXEC is available since Linux 2.6.23.  Linux 2.6.18 silently ignore it. */
    flags |= O_CLOEXEC;
#elif defined O_NOINHERIT
    flags |= O_NOINHERIT;
#endif

    while ((ret = open(pathname, flags, mode)) == -1) {
        int e = errno;
        if (!io_again_p(e)) break;
        if (retry_count++ >= retry_max_count) break;

        sleep(retry_interval);
    }

    if (ret < 0) return ret;
    if (ret <= 2 || o_cloexec_state == 0) {
        rb_maygvl_fd_fix_cloexec(ret);
    }
    else if (o_cloexec_state > 0) {
        return ret;
    }
    else {
        o_cloexec_state = rb_fix_detect_o_cloexec(ret);
    }
    return ret;
}

int
rb_cloexec_dup(int oldfd)
{
    /* Don't allocate standard file descriptors: 0, 1, 2 */
    return rb_cloexec_fcntl_dupfd(oldfd, 3);
}

int
rb_cloexec_dup2(int oldfd, int newfd)
{
    int ret;

    /* When oldfd == newfd, dup2 succeeds but dup3 fails with EINVAL.
     * rb_cloexec_dup2 succeeds as dup2.  */
    if (oldfd == newfd) {
        ret = newfd;
    }
    else {
#if defined(HAVE_DUP3) && defined(O_CLOEXEC)
        static int try_dup3 = 1;
        if (2 < newfd && try_dup3) {
            ret = dup3(oldfd, newfd, O_CLOEXEC);
            if (ret != -1)
                return ret;
            /* dup3 is available since Linux 2.6.27, glibc 2.9. */
            if (errno == ENOSYS) {
                try_dup3 = 0;
                ret = dup2(oldfd, newfd);
            }
        }
        else {
            ret = dup2(oldfd, newfd);
        }
#else
        ret = dup2(oldfd, newfd);
#endif
        if (ret < 0) return ret;
    }
    rb_maygvl_fd_fix_cloexec(ret);
    return ret;
}

static int
rb_fd_set_nonblock(int fd)
{
#ifdef _WIN32
    return rb_w32_set_nonblock(fd);
#elif defined(F_GETFL)
    int oflags = fcntl(fd, F_GETFL);

    if (oflags == -1)
        return -1;
    if (oflags & O_NONBLOCK)
        return 0;
    oflags |= O_NONBLOCK;
    return fcntl(fd, F_SETFL, oflags);
#endif
    return 0;
}

int
rb_cloexec_pipe(int descriptors[2])
{
#ifdef HAVE_PIPE2
    int result = pipe2(descriptors, O_CLOEXEC | O_NONBLOCK);
#else
    int result = pipe(descriptors);
#endif

    if (result < 0)
        return result;

#ifdef __CYGWIN__
    if (result == 0 && descriptors[1] == -1) {
        close(descriptors[0]);
        descriptors[0] = -1;
        errno = ENFILE;
        return -1;
    }
#endif

#ifndef HAVE_PIPE2
    rb_maygvl_fd_fix_cloexec(descriptors[0]);
    rb_maygvl_fd_fix_cloexec(descriptors[1]);

#ifndef _WIN32
    rb_fd_set_nonblock(descriptors[0]);
    rb_fd_set_nonblock(descriptors[1]);
#endif
#endif

    return result;
}

int
rb_cloexec_fcntl_dupfd(int fd, int minfd)
{
    int ret;

#if defined(HAVE_FCNTL) && defined(F_DUPFD_CLOEXEC) && defined(F_DUPFD)
    static int try_dupfd_cloexec = 1;
    if (try_dupfd_cloexec) {
        ret = fcntl(fd, F_DUPFD_CLOEXEC, minfd);
        if (ret != -1) {
            if (ret <= 2)
                rb_maygvl_fd_fix_cloexec(ret);
            return ret;
        }
        /* F_DUPFD_CLOEXEC is available since Linux 2.6.24.  Linux 2.6.18 fails with EINVAL */
        if (errno == EINVAL) {
            ret = fcntl(fd, F_DUPFD, minfd);
            if (ret != -1) {
                try_dupfd_cloexec = 0;
            }
        }
    }
    else {
        ret = fcntl(fd, F_DUPFD, minfd);
    }
#elif defined(HAVE_FCNTL) && defined(F_DUPFD)
    ret = fcntl(fd, F_DUPFD, minfd);
#else
    ret = dup(fd);
    if (ret >= 0 && ret < minfd) {
        const int prev_fd = ret;
        ret = rb_cloexec_fcntl_dupfd(fd, minfd);
        close(prev_fd);
    }
    return ret;
#endif
    if (ret < 0) return ret;
    rb_maygvl_fd_fix_cloexec(ret);
    return ret;
}

#define argf_of(obj) (*(struct argf *)DATA_PTR(obj))
#define ARGF argf_of(argf)

#define GetWriteIO(io) rb_io_get_write_io(io)

#define READ_DATA_PENDING(fptr) ((fptr)->rbuf.len)
#define READ_DATA_PENDING_COUNT(fptr) ((fptr)->rbuf.len)
#define READ_DATA_PENDING_PTR(fptr) ((fptr)->rbuf.ptr+(fptr)->rbuf.off)
#define READ_DATA_BUFFERED(fptr) READ_DATA_PENDING(fptr)

#define READ_CHAR_PENDING(fptr) ((fptr)->cbuf.len)
#define READ_CHAR_PENDING_COUNT(fptr) ((fptr)->cbuf.len)
#define READ_CHAR_PENDING_PTR(fptr) ((fptr)->cbuf.ptr+(fptr)->cbuf.off)

#if defined(_WIN32)
#define WAIT_FD_IN_WIN32(fptr) \
    (rb_w32_io_cancelable_p((fptr)->fd) ? Qnil : rb_io_wait(fptr->self, RB_INT2NUM(RUBY_IO_READABLE), RUBY_IO_TIMEOUT_DEFAULT))
#else
#define WAIT_FD_IN_WIN32(fptr)
#endif

#define READ_CHECK(fptr) do {\
    if (!READ_DATA_PENDING(fptr)) {\
        WAIT_FD_IN_WIN32(fptr);\
        rb_io_check_closed(fptr);\
    }\
} while(0)

#ifndef S_ISSOCK
#  ifdef _S_ISSOCK
#    define S_ISSOCK(m) _S_ISSOCK(m)
#  else
#    ifdef _S_IFSOCK
#      define S_ISSOCK(m) (((m) & S_IFMT) == _S_IFSOCK)
#    else
#      ifdef S_IFSOCK
#	 define S_ISSOCK(m) (((m) & S_IFMT) == S_IFSOCK)
#      endif
#    endif
#  endif
#endif

static int io_fflush(rb_io_t *);
static rb_io_t *flush_before_seek(rb_io_t *fptr, bool discard_rbuf);
static void clear_codeconv(rb_io_t *fptr);

#define FMODE_SIGNAL_ON_EPIPE (1<<17)

#define fptr_signal_on_epipe(fptr) \
    (((fptr)->mode & FMODE_SIGNAL_ON_EPIPE) != 0)

#define fptr_set_signal_on_epipe(fptr, flag) \
    ((flag) ? \
     (fptr)->mode |= FMODE_SIGNAL_ON_EPIPE : \
     (fptr)->mode &= ~FMODE_SIGNAL_ON_EPIPE)

extern ID ruby_static_id_signo;

NORETURN(static void rb_sys_fail_on_write(rb_io_t *fptr));
static void
rb_sys_fail_on_write(rb_io_t *fptr)
{
    int e = errno;
    VALUE errinfo = rb_syserr_new_path(e, (fptr)->pathv);
#if defined EPIPE
    if (fptr_signal_on_epipe(fptr) && (e == EPIPE)) {
        const VALUE sig =
# if defined SIGPIPE
            INT2FIX(SIGPIPE) - INT2FIX(0) +
# endif
            INT2FIX(0);
        rb_ivar_set(errinfo, ruby_static_id_signo, sig);
    }
#endif
    rb_exc_raise(errinfo);
}

#define NEED_NEWLINE_DECORATOR_ON_READ(fptr) ((fptr)->mode & FMODE_TEXTMODE)
#define NEED_NEWLINE_DECORATOR_ON_WRITE(fptr) ((fptr)->mode & FMODE_TEXTMODE)
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
# define RUBY_CRLF_ENVIRONMENT 1
#else
# define RUBY_CRLF_ENVIRONMENT 0
#endif

#if RUBY_CRLF_ENVIRONMENT
/* Windows */
# define DEFAULT_TEXTMODE FMODE_TEXTMODE
# define TEXTMODE_NEWLINE_DECORATOR_ON_WRITE ECONV_CRLF_NEWLINE_DECORATOR
/*
 * CRLF newline is set as default newline decorator.
 * If only CRLF newline conversion is needed, we use binary IO process
 * with OS's text mode for IO performance improvement.
 * If encoding conversion is needed or a user sets text mode, we use encoding
 * conversion IO process and universal newline decorator by default.
 */
#define NEED_READCONV(fptr) ((fptr)->encs.enc2 != NULL || (fptr)->encs.ecflags & ~ECONV_CRLF_NEWLINE_DECORATOR)
#define WRITECONV_MASK ( \
    (ECONV_DECORATOR_MASK & ~ECONV_CRLF_NEWLINE_DECORATOR)|\
    ECONV_STATEFUL_DECORATOR_MASK|\
    0)
#define NEED_WRITECONV(fptr) ( \
  ((fptr)->encs.enc != NULL && (fptr)->encs.enc != rb_ascii8bit_encoding()) || \
  ((fptr)->encs.ecflags & WRITECONV_MASK) || \
  0)
#define SET_BINARY_MODE(fptr) setmode((fptr)->fd, O_BINARY)

#define NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr) do {\
    if (NEED_NEWLINE_DECORATOR_ON_READ(fptr)) {\
        if (((fptr)->mode & FMODE_READABLE) &&\
            !((fptr)->encs.ecflags & ECONV_NEWLINE_DECORATOR_MASK)) {\
            setmode((fptr)->fd, O_BINARY);\
        }\
        else {\
            setmode((fptr)->fd, O_TEXT);\
        }\
    }\
} while(0)

#define SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags) do {\
    if ((enc2) && ((ecflags) & ECONV_DEFAULT_NEWLINE_DECORATOR)) {\
        (ecflags) |= ECONV_UNIVERSAL_NEWLINE_DECORATOR;\
    }\
} while(0)

/*
 * IO unread with taking care of removed '\r' in text mode.
 */
static void
io_unread(rb_io_t *fptr, bool discard_rbuf)
{
    rb_off_t r, pos;
    ssize_t read_size;
    long i;
    long newlines = 0;
    long extra_max;
    char *p;
    char *buf;

    rb_io_check_closed(fptr);
    if (fptr->rbuf.len == 0 || fptr->mode & FMODE_DUPLEX) {
        return;
    }

    errno = 0;
    if (!rb_w32_fd_is_text(fptr->fd)) {
        r = lseek(fptr->fd, -fptr->rbuf.len, SEEK_CUR);
        if (r < 0 && errno) {
            if (errno == ESPIPE)
                fptr->mode |= FMODE_DUPLEX;
            if (!discard_rbuf) return;
        }

        goto end;
    }

    pos = lseek(fptr->fd, 0, SEEK_CUR);
    if (pos < 0 && errno) {
        if (errno == ESPIPE)
            fptr->mode |= FMODE_DUPLEX;
        if (!discard_rbuf) goto end;
    }

    /* add extra offset for removed '\r' in rbuf */
    extra_max = (long)(pos - fptr->rbuf.len);
    p = fptr->rbuf.ptr + fptr->rbuf.off;

    /* if the end of rbuf is '\r', rbuf doesn't have '\r' within rbuf.len */
    if (*(fptr->rbuf.ptr + fptr->rbuf.capa - 1) == '\r') {
        newlines++;
    }

    for (i = 0; i < fptr->rbuf.len; i++) {
        if (*p == '\n') newlines++;
        if (extra_max == newlines) break;
        p++;
    }

    buf = ALLOC_N(char, fptr->rbuf.len + newlines);
    while (newlines >= 0) {
        r = lseek(fptr->fd, pos - fptr->rbuf.len - newlines, SEEK_SET);
        if (newlines == 0) break;
        if (r < 0) {
            newlines--;
            continue;
        }
        read_size = _read(fptr->fd, buf, fptr->rbuf.len + newlines);
        if (read_size < 0) {
            int e = errno;
            free(buf);
            rb_syserr_fail_path(e, fptr->pathv);
        }
        if (read_size == fptr->rbuf.len) {
            lseek(fptr->fd, r, SEEK_SET);
            break;
        }
        else {
            newlines--;
        }
    }
    free(buf);
  end:
    fptr->rbuf.off = 0;
    fptr->rbuf.len = 0;
    clear_codeconv(fptr);
    return;
}

/*
 * We use io_seek to back cursor position when changing mode from text to binary,
 * but stdin and pipe cannot seek back. Stdin and pipe read should use encoding
 * conversion for working properly with mode change.
 *
 * Return previous translation mode.
 */
static inline int
set_binary_mode_with_seek_cur(rb_io_t *fptr)
{
    if (!rb_w32_fd_is_text(fptr->fd)) return O_BINARY;

    if (fptr->rbuf.len == 0 || fptr->mode & FMODE_DUPLEX) {
        return setmode(fptr->fd, O_BINARY);
    }
    flush_before_seek(fptr, false);
    return setmode(fptr->fd, O_BINARY);
}
#define SET_BINARY_MODE_WITH_SEEK_CUR(fptr) set_binary_mode_with_seek_cur(fptr)

#else
/* Unix */
# define DEFAULT_TEXTMODE 0
#define NEED_READCONV(fptr) ((fptr)->encs.enc2 != NULL || NEED_NEWLINE_DECORATOR_ON_READ(fptr))
#define NEED_WRITECONV(fptr) ( \
  ((fptr)->encs.enc != NULL && (fptr)->encs.enc != rb_ascii8bit_encoding()) || \
  NEED_NEWLINE_DECORATOR_ON_WRITE(fptr) ||                        \
  ((fptr)->encs.ecflags & (ECONV_DECORATOR_MASK|ECONV_STATEFUL_DECORATOR_MASK)) || \
  0)
#define SET_BINARY_MODE(fptr) (void)(fptr)
#define NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr) (void)(fptr)
#define SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags) ((void)(enc2), (void)(ecflags))
#define SET_BINARY_MODE_WITH_SEEK_CUR(fptr) (void)(fptr)
#endif

#if !defined HAVE_SHUTDOWN && !defined shutdown
#define shutdown(a,b)	0
#endif

#if defined(_WIN32)
#define is_socket(fd, path)	rb_w32_is_socket(fd)
#elif !defined(S_ISSOCK)
#define is_socket(fd, path)	0
#else
static int
is_socket(int fd, VALUE path)
{
    struct stat sbuf;
    if (fstat(fd, &sbuf) < 0)
        rb_sys_fail_path(path);
    return S_ISSOCK(sbuf.st_mode);
}
#endif

static const char closed_stream[] = "closed stream";

static void
io_fd_check_closed(int fd)
{
    if (fd < 0) {
        rb_thread_check_ints(); /* check for ruby_error_stream_closed */
        rb_raise(rb_eIOError, closed_stream);
    }
}

void
rb_eof_error(void)
{
    rb_raise(rb_eEOFError, "end of file reached");
}

VALUE
rb_io_taint_check(VALUE io)
{
    rb_check_frozen(io);
    return io;
}

void
rb_io_check_initialized(rb_io_t *fptr)
{
    if (!fptr) {
        rb_raise(rb_eIOError, "uninitialized stream");
    }
}

void
rb_io_check_closed(rb_io_t *fptr)
{
    rb_io_check_initialized(fptr);
    io_fd_check_closed(fptr->fd);
}

static rb_io_t *
rb_io_get_fptr(VALUE io)
{
    rb_io_t *fptr = RFILE(io)->fptr;
    rb_io_check_initialized(fptr);
    return fptr;
}

VALUE
rb_io_get_io(VALUE io)
{
    return rb_convert_type_with_id(io, T_FILE, "IO", idTo_io);
}

VALUE
rb_io_check_io(VALUE io)
{
    return rb_check_convert_type_with_id(io, T_FILE, "IO", idTo_io);
}

VALUE
rb_io_get_write_io(VALUE io)
{
    VALUE write_io;
    write_io = rb_io_get_fptr(io)->tied_io_for_writing;
    if (write_io) {
        return write_io;
    }
    return io;
}

VALUE
rb_io_set_write_io(VALUE io, VALUE w)
{
    VALUE write_io;
    rb_io_t *fptr = rb_io_get_fptr(io);
    if (!RTEST(w)) {
        w = 0;
    }
    else {
        GetWriteIO(w);
    }
    write_io = fptr->tied_io_for_writing;
    fptr->tied_io_for_writing = w;
    return write_io ? write_io : Qnil;
}

/*
 *  call-seq:
 *    timeout -> duration or nil
 *
 *  Get the internal timeout duration or nil if it was not set.
 *
 */
VALUE
rb_io_timeout(VALUE self)
{
    rb_io_t *fptr = rb_io_get_fptr(self);

    return fptr->timeout;
}

/*
 *  call-seq:
 *    timeout = duration -> duration
 *    timeout = nil -> nil
 *
 *  Sets the internal timeout to the specified duration or nil. The timeout
 *  applies to all blocking operations where possible.
 *
 *  When the operation performs longer than the timeout set, IO::TimeoutError
 *  is raised.
 *
 *  This affects the following methods (but is not limited to): #gets, #puts,
 *  #read, #write, #wait_readable and #wait_writable. This also affects
 *  blocking socket operations like Socket#accept and Socket#connect.
 *
 *  Some operations like File#open and IO#close are not affected by the
 *  timeout. A timeout during a write operation may leave the IO in an
 *  inconsistent state, e.g. data was partially written. Generally speaking, a
 *  timeout is a last ditch effort to prevent an application from hanging on
 *  slow I/O operations, such as those that occur during a slowloris attack.
 */
VALUE
rb_io_set_timeout(VALUE self, VALUE timeout)
{
    // Validate it:
    if (RTEST(timeout)) {
        rb_time_interval(timeout);
    }

    rb_io_t *fptr = rb_io_get_fptr(self);

    fptr->timeout = timeout;

    return self;
}

/*
 *  call-seq:
 *    IO.try_convert(object) -> new_io or nil
 *
 *  Attempts to convert +object+ into an \IO object via method +to_io+;
 *  returns the new \IO object if successful, or +nil+ otherwise:
 *
 *    IO.try_convert(STDOUT)   # => #<IO:<STDOUT>>
 *    IO.try_convert(ARGF)     # => #<IO:<STDIN>>
 *    IO.try_convert('STDOUT') # => nil
 *
 */
static VALUE
rb_io_s_try_convert(VALUE dummy, VALUE io)
{
    return rb_io_check_io(io);
}

#if !RUBY_CRLF_ENVIRONMENT
static void
io_unread(rb_io_t *fptr, bool discard_rbuf)
{
    rb_off_t r;
    rb_io_check_closed(fptr);
    if (fptr->rbuf.len == 0 || fptr->mode & FMODE_DUPLEX)
        return;
    /* xxx: target position may be negative if buffer is filled by ungetc */
    errno = 0;
    r = lseek(fptr->fd, -fptr->rbuf.len, SEEK_CUR);
    if (r < 0 && errno) {
        if (errno == ESPIPE)
            fptr->mode |= FMODE_DUPLEX;
        if (!discard_rbuf) return;
    }
    fptr->rbuf.off = 0;
    fptr->rbuf.len = 0;
    clear_codeconv(fptr);
    return;
}
#endif

static rb_encoding *io_input_encoding(rb_io_t *fptr);

static void
io_ungetbyte(VALUE str, rb_io_t *fptr)
{
    long len = RSTRING_LEN(str);

    if (fptr->rbuf.ptr == NULL) {
        const int min_capa = IO_RBUF_CAPA_FOR(fptr);
        fptr->rbuf.off = 0;
        fptr->rbuf.len = 0;
#if SIZEOF_LONG > SIZEOF_INT
        if (len > INT_MAX)
            rb_raise(rb_eIOError, "ungetbyte failed");
#endif
        if (len > min_capa)
            fptr->rbuf.capa = (int)len;
        else
            fptr->rbuf.capa = min_capa;
        fptr->rbuf.ptr = ALLOC_N(char, fptr->rbuf.capa);
    }
    if (fptr->rbuf.capa < len + fptr->rbuf.len) {
        rb_raise(rb_eIOError, "ungetbyte failed");
    }
    if (fptr->rbuf.off < len) {
        MEMMOVE(fptr->rbuf.ptr+fptr->rbuf.capa-fptr->rbuf.len,
                fptr->rbuf.ptr+fptr->rbuf.off,
                char, fptr->rbuf.len);
        fptr->rbuf.off = fptr->rbuf.capa-fptr->rbuf.len;
    }
    fptr->rbuf.off-=(int)len;
    fptr->rbuf.len+=(int)len;
    MEMMOVE(fptr->rbuf.ptr+fptr->rbuf.off, RSTRING_PTR(str), char, len);
}

static rb_io_t *
flush_before_seek(rb_io_t *fptr, bool discard_rbuf)
{
    if (io_fflush(fptr) < 0)
        rb_sys_fail_on_write(fptr);
    io_unread(fptr, discard_rbuf);
    errno = 0;
    return fptr;
}

#define io_seek(fptr, ofs, whence) (errno = 0, lseek(flush_before_seek(fptr, true)->fd, (ofs), (whence)))
#define io_tell(fptr) lseek(flush_before_seek(fptr, false)->fd, 0, SEEK_CUR)

#ifndef SEEK_CUR
# define SEEK_SET 0
# define SEEK_CUR 1
# define SEEK_END 2
#endif

void
rb_io_check_char_readable(rb_io_t *fptr)
{
    rb_io_check_closed(fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
        rb_raise(rb_eIOError, "not opened for reading");
    }
    if (fptr->wbuf.len) {
        if (io_fflush(fptr) < 0)
            rb_sys_fail_on_write(fptr);
    }
    if (fptr->tied_io_for_writing) {
        rb_io_t *wfptr;
        GetOpenFile(fptr->tied_io_for_writing, wfptr);
        if (io_fflush(wfptr) < 0)
            rb_sys_fail_on_write(wfptr);
    }
}

void
rb_io_check_byte_readable(rb_io_t *fptr)
{
    rb_io_check_char_readable(fptr);
    if (READ_CHAR_PENDING(fptr)) {
        rb_raise(rb_eIOError, "byte oriented read for character buffered IO");
    }
}

void
rb_io_check_readable(rb_io_t *fptr)
{
    rb_io_check_byte_readable(fptr);
}

static rb_encoding*
io_read_encoding(rb_io_t *fptr)
{
    if (fptr->encs.enc) {
        return fptr->encs.enc;
    }
    return rb_default_external_encoding();
}

static rb_encoding*
io_input_encoding(rb_io_t *fptr)
{
    if (fptr->encs.enc2) {
        return fptr->encs.enc2;
    }
    return io_read_encoding(fptr);
}

void
rb_io_check_writable(rb_io_t *fptr)
{
    rb_io_check_closed(fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
        rb_raise(rb_eIOError, "not opened for writing");
    }
    if (fptr->rbuf.len) {
        io_unread(fptr, true);
    }
}

int
rb_io_read_pending(rb_io_t *fptr)
{
    /* This function is used for bytes and chars.  Confusing. */
    if (READ_CHAR_PENDING(fptr))
        return 1; /* should raise? */
    return READ_DATA_PENDING(fptr);
}

void
rb_io_read_check(rb_io_t *fptr)
{
    if (!READ_DATA_PENDING(fptr)) {
        rb_io_wait(fptr->self, RB_INT2NUM(RUBY_IO_READABLE), RUBY_IO_TIMEOUT_DEFAULT);
    }
    return;
}

int
rb_gc_for_fd(int err)
{
    if (err == EMFILE || err == ENFILE || err == ENOMEM) {
        rb_gc();
        return 1;
    }
    return 0;
}

/* try `expr` upto twice while it returns false and `errno`
 * is to GC.  Each `errno`s are available as `first_errno` and
 * `retried_errno` respectively */
#define TRY_WITH_GC(expr) \
    for (int first_errno, retried_errno = 0, retried = 0; \
         (!retried && \
          !(expr) && \
          (!rb_gc_for_fd(first_errno = errno) || !(expr)) &&   \
          (retried_errno = errno, 1)); \
         (void)retried_errno, retried = 1)

static int
ruby_dup(int orig)
{
    int fd = -1;

    TRY_WITH_GC((fd = rb_cloexec_dup(orig)) >= 0) {
        rb_syserr_fail(first_errno, 0);
    }
    rb_update_max_fd(fd);
    return fd;
}

static VALUE
io_alloc(VALUE klass)
{
    NEWOBJ_OF(io, struct RFile, klass, T_FILE, sizeof(struct RFile), 0);

    io->fptr = 0;

    return (VALUE)io;
}

#ifndef S_ISREG
#   define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#endif

struct io_internal_read_struct {
    VALUE th;
    rb_io_t *fptr;
    int nonblock;
    int fd;

    void *buf;
    size_t capa;
    struct timeval *timeout;
};

struct io_internal_write_struct {
    VALUE th;
    rb_io_t *fptr;
    int nonblock;
    int fd;

    const void *buf;
    size_t capa;
    struct timeval *timeout;
};

#ifdef HAVE_WRITEV
struct io_internal_writev_struct {
    VALUE th;
    rb_io_t *fptr;
    int nonblock;
    int fd;

    int iovcnt;
    const struct iovec *iov;
    struct timeval *timeout;
};
#endif

static int nogvl_wait_for(VALUE th, rb_io_t *fptr, short events, struct timeval *timeout);

/**
 * Wait for the given events on the given file descriptor.
 * Returns -1 if an error or timeout occurred. +errno+ will be set.
 * Returns the event mask if an event occurred.
 */
static inline int
io_internal_wait(VALUE thread, rb_io_t *fptr, int error, int events, struct timeval *timeout)
{
    if (!timeout && rb_thread_mn_schedulable(thread)) {
        RUBY_ASSERT(errno == EWOULDBLOCK || errno == EAGAIN);
        return -1;
    }

    int ready = nogvl_wait_for(thread, fptr, events, timeout);

    if (ready > 0) {
        return ready;
    }
    else if (ready == 0) {
        errno = ETIMEDOUT;
        return -1;
    }

    // If there was an error BEFORE we started waiting, return it:
    if (error) {
        errno = error;
        return -1;
    }
    else {
        // Otherwise, whatever error was generated by `nogvl_wait_for` is the one we want:
        return ready;
    }
}

static VALUE
internal_read_func(void *ptr)
{
    struct io_internal_read_struct *iis = ptr;
    ssize_t result;

    if (iis->timeout && !iis->nonblock) {
        if (io_internal_wait(iis->th, iis->fptr, 0, RB_WAITFD_IN, iis->timeout) == -1) {
            return -1;
        }
    }

  retry:
    result = read(iis->fd, iis->buf, iis->capa);

    if (result < 0 && !iis->nonblock) {
        if (io_again_p(errno)) {
            if (io_internal_wait(iis->th, iis->fptr, errno, RB_WAITFD_IN, iis->timeout) == -1) {
                return -1;
            }
            else {
                goto retry;
            }
        }
    }

    return result;
}

#if defined __APPLE__
# define do_write_retry(code) do {result = code;} while (result == -1 && errno == EPROTOTYPE)
#else
# define do_write_retry(code) result = code
#endif

static VALUE
internal_write_func(void *ptr)
{
    struct io_internal_write_struct *iis = ptr;
    ssize_t result;

    if (iis->timeout && !iis->nonblock) {
        if (io_internal_wait(iis->th, iis->fptr, 0, RB_WAITFD_OUT, iis->timeout) == -1) {
            return -1;
        }
    }

  retry:
    do_write_retry(write(iis->fd, iis->buf, iis->capa));

    if (result < 0 && !iis->nonblock) {
        int e = errno;
        if (io_again_p(e)) {
            if (io_internal_wait(iis->th, iis->fptr, errno, RB_WAITFD_OUT, iis->timeout) == -1) {
                return -1;
            }
            else {
                goto retry;
            }
        }
    }

    return result;
}

#ifdef HAVE_WRITEV
static VALUE
internal_writev_func(void *ptr)
{
    struct io_internal_writev_struct *iis = ptr;
    ssize_t result;

    if (iis->timeout && !iis->nonblock) {
        if (io_internal_wait(iis->th, iis->fptr, 0, RB_WAITFD_OUT, iis->timeout) == -1) {
            return -1;
        }
    }

  retry:
    do_write_retry(writev(iis->fd, iis->iov, iis->iovcnt));

    if (result < 0 && !iis->nonblock) {
        if (io_again_p(errno)) {
            if (io_internal_wait(iis->th, iis->fptr, errno, RB_WAITFD_OUT, iis->timeout) == -1) {
                return -1;
            }
            else {
                goto retry;
            }
        }
    }

    return result;
}
#endif

static ssize_t
rb_io_read_memory(rb_io_t *fptr, void *buf, size_t count)
{
    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_read_memory(scheduler, fptr->self, buf, count, 0);

        if (!UNDEF_P(result)) {
            return rb_fiber_scheduler_io_result_apply(result);
        }
    }

    struct io_internal_read_struct iis = {
        .th = rb_thread_current(),
        .fptr = fptr,
        .nonblock = 0,
        .fd = fptr->fd,

        .buf = buf,
        .capa = count,
        .timeout = NULL,
    };

    struct timeval timeout_storage;

    if (fptr->timeout != Qnil) {
        timeout_storage = rb_time_interval(fptr->timeout);
        iis.timeout = &timeout_storage;
    }

    return (ssize_t)rb_io_blocking_region_wait(fptr, internal_read_func, &iis, RUBY_IO_READABLE);
}

static ssize_t
rb_io_write_memory(rb_io_t *fptr, const void *buf, size_t count)
{
    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_write_memory(scheduler, fptr->self, buf, count, 0);

        if (!UNDEF_P(result)) {
            return rb_fiber_scheduler_io_result_apply(result);
        }
    }

    struct io_internal_write_struct iis = {
        .th = rb_thread_current(),
        .fptr = fptr,
        .nonblock = 0,
        .fd = fptr->fd,

        .buf = buf,
        .capa = count,
        .timeout = NULL
    };

    struct timeval timeout_storage;

    if (fptr->timeout != Qnil) {
        timeout_storage = rb_time_interval(fptr->timeout);
        iis.timeout = &timeout_storage;
    }

    return (ssize_t)rb_io_blocking_region_wait(fptr, internal_write_func, &iis, RUBY_IO_WRITABLE);
}

#ifdef HAVE_WRITEV
static ssize_t
rb_writev_internal(rb_io_t *fptr, const struct iovec *iov, int iovcnt)
{
    if (!iovcnt) return 0;

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        // This path assumes at least one `iov`:
        VALUE result = rb_fiber_scheduler_io_write_memory(scheduler, fptr->self, iov[0].iov_base, iov[0].iov_len, 0);

        if (!UNDEF_P(result)) {
            return rb_fiber_scheduler_io_result_apply(result);
        }
    }

    struct io_internal_writev_struct iis = {
        .th = rb_thread_current(),
        .fptr = fptr,
        .nonblock = 0,
        .fd = fptr->fd,

        .iov = iov,
        .iovcnt = iovcnt,
        .timeout = NULL
    };

    struct timeval timeout_storage;

    if (fptr->timeout != Qnil) {
        timeout_storage = rb_time_interval(fptr->timeout);
        iis.timeout = &timeout_storage;
    }

    return (ssize_t)rb_io_blocking_region_wait(fptr, internal_writev_func, &iis, RUBY_IO_WRITABLE);
}
#endif

static VALUE
io_flush_buffer_sync(void *arg)
{
    rb_io_t *fptr = arg;
    long l = fptr->wbuf.len;
    ssize_t r = write(fptr->fd, fptr->wbuf.ptr+fptr->wbuf.off, (size_t)l);

    if (fptr->wbuf.len <= r) {
        fptr->wbuf.off = 0;
        fptr->wbuf.len = 0;
        return 0;
    }

    if (0 <= r) {
        fptr->wbuf.off += (int)r;
        fptr->wbuf.len -= (int)r;
        errno = EAGAIN;
    }

    return (VALUE)-1;
}

static VALUE
io_flush_buffer_async(VALUE arg)
{
    rb_io_t *fptr = (rb_io_t *)arg;
    return rb_io_blocking_region_wait(fptr, io_flush_buffer_sync, fptr, RUBY_IO_WRITABLE);
}

static inline int
io_flush_buffer(rb_io_t *fptr)
{
    if (!NIL_P(fptr->write_lock) && rb_mutex_owned_p(fptr->write_lock)) {
        return (int)io_flush_buffer_async((VALUE)fptr);
    }
    else {
        return (int)rb_mutex_synchronize(fptr->write_lock, io_flush_buffer_async, (VALUE)fptr);
    }
}

static int
io_fflush(rb_io_t *fptr)
{
    rb_io_check_closed(fptr);

    if (fptr->wbuf.len == 0)
        return 0;

    while (fptr->wbuf.len > 0 && io_flush_buffer(fptr) != 0) {
        if (!rb_io_maybe_wait_writable(errno, fptr->self, RUBY_IO_TIMEOUT_DEFAULT))
            return -1;

        rb_io_check_closed(fptr);
    }

    return 0;
}

VALUE
rb_io_wait(VALUE io, VALUE events, VALUE timeout)
{
    VALUE scheduler = rb_fiber_scheduler_current();

    if (scheduler != Qnil) {
        return rb_fiber_scheduler_io_wait(scheduler, io, events, timeout);
    }

    rb_io_t * fptr = NULL;
    RB_IO_POINTER(io, fptr);

    struct timeval tv_storage;
    struct timeval *tv = NULL;

    if (NIL_OR_UNDEF_P(timeout)) {
        timeout = fptr->timeout;
    }

    if (timeout != Qnil) {
        tv_storage = rb_time_interval(timeout);
        tv = &tv_storage;
    }

    int ready = rb_thread_io_wait(fptr, RB_NUM2INT(events), tv);

    if (ready < 0) {
        rb_sys_fail(0);
    }

    // Not sure if this is necessary:
    rb_io_check_closed(fptr);

    if (ready) {
        return RB_INT2NUM(ready);
    }
    else {
        return Qfalse;
    }
}

static VALUE
io_from_fd(int fd)
{
    return prep_io(fd, FMODE_EXTERNAL, rb_cIO, NULL);
}

static int
io_wait_for_single_fd(int fd, int events, struct timeval *timeout)
{
    VALUE scheduler = rb_fiber_scheduler_current();

    if (scheduler != Qnil) {
        return RTEST(
            rb_fiber_scheduler_io_wait(scheduler, io_from_fd(fd), RB_INT2NUM(events), rb_fiber_scheduler_make_timeout(timeout))
        );
    }

    return rb_thread_wait_for_single_fd(fd, events, timeout);
}

int
rb_io_wait_readable(int f)
{
    io_fd_check_closed(f);

    VALUE scheduler = rb_fiber_scheduler_current();

    switch (errno) {
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
        rb_thread_check_ints();
        return TRUE;

      case EAGAIN:
#if EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
        if (scheduler != Qnil) {
            return RTEST(
                rb_fiber_scheduler_io_wait_readable(scheduler, io_from_fd(f))
            );
        }
        else {
            io_wait_for_single_fd(f, RUBY_IO_READABLE, NULL);
        }
        return TRUE;

      default:
        return FALSE;
    }
}

int
rb_io_wait_writable(int f)
{
    io_fd_check_closed(f);

    VALUE scheduler = rb_fiber_scheduler_current();

    switch (errno) {
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
        /*
         * In old Linux, several special files under /proc and /sys don't handle
         * select properly. Thus we need avoid to call if don't use O_NONBLOCK.
         * Otherwise, we face nasty hang up. Sigh.
         * e.g. https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=31b07093c44a7a442394d44423e21d783f5523b8
         * https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=31b07093c44a7a442394d44423e21d783f5523b8
         * In EINTR case, we only need to call RUBY_VM_CHECK_INTS_BLOCKING().
         * Then rb_thread_check_ints() is enough.
         */
        rb_thread_check_ints();
        return TRUE;

      case EAGAIN:
#if EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
        if (scheduler != Qnil) {
            return RTEST(
                rb_fiber_scheduler_io_wait_writable(scheduler, io_from_fd(f))
            );
        }
        else {
            io_wait_for_single_fd(f, RUBY_IO_WRITABLE, NULL);
        }
        return TRUE;

      default:
        return FALSE;
    }
}

int
rb_wait_for_single_fd(int fd, int events, struct timeval *timeout)
{
    return io_wait_for_single_fd(fd, events, timeout);
}

int
rb_thread_wait_fd(int fd)
{
    return rb_wait_for_single_fd(fd, RUBY_IO_READABLE, NULL);
}

int
rb_thread_fd_writable(int fd)
{
    return rb_wait_for_single_fd(fd, RUBY_IO_WRITABLE, NULL);
}

VALUE
rb_io_maybe_wait(int error, VALUE io, VALUE events, VALUE timeout)
{
    // fptr->fd can be set to -1 at any time by another thread when the GVL is
    // released. Many code, e.g. `io_bufread` didn't check this correctly and
    // instead relies on `read(-1) -> -1` which causes this code path. We then
    // check here whether the IO was in fact closed. Probably it's better to
    // check that `fptr->fd != -1` before using it in syscall.
    rb_io_check_closed(RFILE(io)->fptr);

    switch (error) {
      // In old Linux, several special files under /proc and /sys don't handle
      // select properly. Thus we need avoid to call if don't use O_NONBLOCK.
      // Otherwise, we face nasty hang up. Sigh.
      // e.g. https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=31b07093c44a7a442394d44423e21d783f5523b8
      // https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=31b07093c44a7a442394d44423e21d783f5523b8
      // In EINTR case, we only need to call RUBY_VM_CHECK_INTS_BLOCKING().
      // Then rb_thread_check_ints() is enough.
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
        // We might have pending interrupts since the previous syscall was interrupted:
        rb_thread_check_ints();

        // The operation was interrupted, so retry it immediately:
        return events;

      case EAGAIN:
#if EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
        // The operation would block, so wait for the specified events:
        return rb_io_wait(io, events, timeout);

      default:
        // Non-specific error, no event is ready:
        return Qnil;
    }
}

int
rb_io_maybe_wait_readable(int error, VALUE io, VALUE timeout)
{
    VALUE result = rb_io_maybe_wait(error, io, RB_INT2NUM(RUBY_IO_READABLE), timeout);

    if (RTEST(result)) {
        return RB_NUM2INT(result);
    }
    else if (result == RUBY_Qfalse) {
        rb_raise(rb_eIOTimeoutError, "Timed out waiting for IO to become readable!");
    }

    return 0;
}

int
rb_io_maybe_wait_writable(int error, VALUE io, VALUE timeout)
{
    VALUE result = rb_io_maybe_wait(error, io, RB_INT2NUM(RUBY_IO_WRITABLE), timeout);

    if (RTEST(result)) {
        return RB_NUM2INT(result);
    }
    else if (result == RUBY_Qfalse) {
        rb_raise(rb_eIOTimeoutError, "Timed out waiting for IO to become writable!");
    }

    return 0;
}

static void
make_writeconv(rb_io_t *fptr)
{
    if (!fptr->writeconv_initialized) {
        const char *senc, *denc;
        rb_encoding *enc;
        int ecflags;
        VALUE ecopts;

        fptr->writeconv_initialized = 1;

        ecflags = fptr->encs.ecflags & ~ECONV_NEWLINE_DECORATOR_READ_MASK;
        ecopts = fptr->encs.ecopts;

        if (!fptr->encs.enc || (rb_is_ascii8bit_enc(fptr->encs.enc) && !fptr->encs.enc2)) {
            /* no encoding conversion */
            fptr->writeconv_pre_ecflags = 0;
            fptr->writeconv_pre_ecopts = Qnil;
            fptr->writeconv = rb_econv_open_opts("", "", ecflags, ecopts);
            if (!fptr->writeconv)
                rb_exc_raise(rb_econv_open_exc("", "", ecflags));
            fptr->writeconv_asciicompat = Qnil;
        }
        else {
            enc = fptr->encs.enc2 ? fptr->encs.enc2 : fptr->encs.enc;
            senc = rb_econv_asciicompat_encoding(rb_enc_name(enc));
            if (!senc && !(fptr->encs.ecflags & ECONV_STATEFUL_DECORATOR_MASK)) {
                /* single conversion */
                fptr->writeconv_pre_ecflags = ecflags;
                fptr->writeconv_pre_ecopts = ecopts;
                fptr->writeconv = NULL;
                fptr->writeconv_asciicompat = Qnil;
            }
            else {
                /* double conversion */
                fptr->writeconv_pre_ecflags = ecflags & ~ECONV_STATEFUL_DECORATOR_MASK;
                fptr->writeconv_pre_ecopts = ecopts;
                if (senc) {
                    denc = rb_enc_name(enc);
                    fptr->writeconv_asciicompat = rb_str_new2(senc);
                }
                else {
                    senc = denc = "";
                    fptr->writeconv_asciicompat = rb_str_new2(rb_enc_name(enc));
                }
                ecflags = fptr->encs.ecflags & (ECONV_ERROR_HANDLER_MASK|ECONV_STATEFUL_DECORATOR_MASK);
                ecopts = fptr->encs.ecopts;
                fptr->writeconv = rb_econv_open_opts(senc, denc, ecflags, ecopts);
                if (!fptr->writeconv)
                    rb_exc_raise(rb_econv_open_exc(senc, denc, ecflags));
            }
        }
    }
}

/* writing functions */
struct binwrite_arg {
    rb_io_t *fptr;
    const char *ptr;
    long length;
};

struct write_arg {
    VALUE io;
    VALUE str;
    int nosync;
};

#ifdef HAVE_WRITEV
static ssize_t
io_binwrite_string_internal(rb_io_t *fptr, const char *ptr, long length)
{
    if (fptr->wbuf.len) {
        struct iovec iov[2];

        iov[0].iov_base = fptr->wbuf.ptr+fptr->wbuf.off;
        iov[0].iov_len = fptr->wbuf.len;
        iov[1].iov_base = (void*)ptr;
        iov[1].iov_len = length;

        ssize_t result = rb_writev_internal(fptr, iov, 2);

        if (result < 0)
            return result;

        if (result >= fptr->wbuf.len) {
            // We wrote more than the internal buffer:
            result -= fptr->wbuf.len;
            fptr->wbuf.off = 0;
            fptr->wbuf.len = 0;
        }
        else {
            // We only wrote less data than the internal buffer:
            fptr->wbuf.off += (int)result;
            fptr->wbuf.len -= (int)result;

            result = 0;
        }

        return result;
    }
    else {
        return rb_io_write_memory(fptr, ptr, length);
    }
}
#else
static ssize_t
io_binwrite_string_internal(rb_io_t *fptr, const char *ptr, long length)
{
    long remaining = length;

    if (fptr->wbuf.len) {
        if (fptr->wbuf.len+length <= fptr->wbuf.capa) {
            if (fptr->wbuf.capa < fptr->wbuf.off+fptr->wbuf.len+length) {
                MEMMOVE(fptr->wbuf.ptr, fptr->wbuf.ptr+fptr->wbuf.off, char, fptr->wbuf.len);
                fptr->wbuf.off = 0;
            }

            MEMMOVE(fptr->wbuf.ptr+fptr->wbuf.off+fptr->wbuf.len, ptr, char, length);
            fptr->wbuf.len += (int)length;

            // We copied the entire incoming data to the internal buffer:
            remaining = 0;
        }

        // Flush the internal buffer:
        if (io_fflush(fptr) < 0) {
            return -1;
        }

        // If all the data was buffered, we are done:
        if (remaining == 0) {
            return length;
        }
    }

    // Otherwise, we should write the data directly:
    return rb_io_write_memory(fptr, ptr, length);
}
#endif

static VALUE
io_binwrite_string(VALUE arg)
{
    struct binwrite_arg *p = (struct binwrite_arg *)arg;

    const char *ptr = p->ptr;
    size_t remaining = p->length;

    while (remaining) {
        // Write as much as possible:
        ssize_t result = io_binwrite_string_internal(p->fptr, ptr, remaining);

        if (result == 0) {
            // If only the internal buffer is written, result will be zero [bytes of given data written]. This means we
            // should try again immediately.
        }
        else if (result > 0) {
            if ((size_t)result == remaining) break;
            ptr += result;
            remaining -= result;
        }
        // Wait for it to become writable:
        else if (rb_io_maybe_wait_writable(errno, p->fptr->self, RUBY_IO_TIMEOUT_DEFAULT)) {
            rb_io_check_closed(p->fptr);
        }
        else {
            // The error was unrelated to waiting for it to become writable, so we fail:
            return -1;
        }
    }

    return p->length;
}

inline static void
io_allocate_write_buffer(rb_io_t *fptr, int sync)
{
    if (fptr->wbuf.ptr == NULL && !(sync && (fptr->mode & FMODE_SYNC))) {
        fptr->wbuf.off = 0;
        fptr->wbuf.len = 0;
        fptr->wbuf.capa = IO_WBUF_CAPA_MIN;
        fptr->wbuf.ptr = ALLOC_N(char, fptr->wbuf.capa);
    }

    if (NIL_P(fptr->write_lock)) {
        fptr->write_lock = rb_mutex_new();
        rb_mutex_allow_trap(fptr->write_lock, 1);
    }
}

static inline int
io_binwrite_requires_flush_write(rb_io_t *fptr, long len, int nosync)
{
    // If the requested operation was synchronous and the output mode is synchronous or a TTY:
    if (!nosync && (fptr->mode & (FMODE_SYNC|FMODE_TTY)))
        return 1;

    // If the amount of data we want to write exceeds the internal buffer:
    if (fptr->wbuf.ptr && fptr->wbuf.capa <= fptr->wbuf.len + len)
        return 1;

    // Otherwise, we can append to the internal buffer:
    return 0;
}

static long
io_binwrite(const char *ptr, long len, rb_io_t *fptr, int nosync)
{
    if (len <= 0) return len;

    // Don't write anything if current thread has a pending interrupt:
    rb_thread_check_ints();

    io_allocate_write_buffer(fptr, !nosync);

    if (io_binwrite_requires_flush_write(fptr, len, nosync)) {
        struct binwrite_arg arg;

        arg.fptr = fptr;
        arg.ptr = ptr;
        arg.length = len;

        if (!NIL_P(fptr->write_lock)) {
            return rb_mutex_synchronize(fptr->write_lock, io_binwrite_string, (VALUE)&arg);
        }
        else {
            return io_binwrite_string((VALUE)&arg);
        }
    }
    else {
        if (fptr->wbuf.off) {
            if (fptr->wbuf.len)
                MEMMOVE(fptr->wbuf.ptr, fptr->wbuf.ptr+fptr->wbuf.off, char, fptr->wbuf.len);
            fptr->wbuf.off = 0;
        }

        MEMMOVE(fptr->wbuf.ptr+fptr->wbuf.off+fptr->wbuf.len, ptr, char, len);
        fptr->wbuf.len += (int)len;

        return len;
    }
}

# define MODE_BTMODE(a,b,c) ((fmode & FMODE_BINMODE) ? (b) : \
                             (fmode & FMODE_TEXTMODE) ? (c) : (a))

#define MODE_BTXMODE(a, b, c, d, e, f) ((fmode & FMODE_EXCL) ? \
                                        MODE_BTMODE(d, e, f) : \
                                        MODE_BTMODE(a, b, c))

static VALUE
do_writeconv(VALUE str, rb_io_t *fptr, int *converted)
{
    if (NEED_WRITECONV(fptr)) {
        VALUE common_encoding = Qnil;
        SET_BINARY_MODE(fptr);

        make_writeconv(fptr);

        if (fptr->writeconv) {
#define fmode (fptr->mode)
            if (!NIL_P(fptr->writeconv_asciicompat))
                common_encoding = fptr->writeconv_asciicompat;
            else if (MODE_BTMODE(DEFAULT_TEXTMODE,0,1) && !rb_enc_asciicompat(rb_enc_get(str))) {
                rb_raise(rb_eArgError, "ASCII incompatible string written for text mode IO without encoding conversion: %s",
                         rb_enc_name(rb_enc_get(str)));
            }
#undef fmode
        }
        else {
            if (fptr->encs.enc2)
                common_encoding = rb_enc_from_encoding(fptr->encs.enc2);
            else if (fptr->encs.enc != rb_ascii8bit_encoding())
                common_encoding = rb_enc_from_encoding(fptr->encs.enc);
        }

        if (!NIL_P(common_encoding)) {
            str = rb_str_encode(str, common_encoding,
                fptr->writeconv_pre_ecflags, fptr->writeconv_pre_ecopts);
            *converted = 1;
        }

        if (fptr->writeconv) {
            str = rb_econv_str_convert(fptr->writeconv, str, ECONV_PARTIAL_INPUT);
            *converted = 1;
        }
    }
#if RUBY_CRLF_ENVIRONMENT
#define fmode (fptr->mode)
    else if (MODE_BTMODE(DEFAULT_TEXTMODE,0,1)) {
        if ((fptr->mode & FMODE_READABLE) &&
            !(fptr->encs.ecflags & ECONV_NEWLINE_DECORATOR_MASK)) {
            setmode(fptr->fd, O_BINARY);
        }
        else {
            setmode(fptr->fd, O_TEXT);
        }
        if (!rb_enc_asciicompat(rb_enc_get(str))) {
            rb_raise(rb_eArgError, "ASCII incompatible string written for text mode IO without encoding conversion: %s",
            rb_enc_name(rb_enc_get(str)));
        }
    }
#undef fmode
#endif
    return str;
}

static long
io_fwrite(VALUE str, rb_io_t *fptr, int nosync)
{
    int converted = 0;
    VALUE tmp;
    long n, len;
    const char *ptr;

#ifdef _WIN32
    if (fptr->mode & FMODE_TTY) {
        long len = rb_w32_write_console(str, fptr->fd);
        if (len > 0) return len;
    }
#endif

    str = do_writeconv(str, fptr, &converted);
    if (converted)
        OBJ_FREEZE(str);

    tmp = rb_str_tmp_frozen_no_embed_acquire(str);
    RSTRING_GETMEM(tmp, ptr, len);
    n = io_binwrite(ptr, len, fptr, nosync);
    rb_str_tmp_frozen_release(str, tmp);

    return n;
}

ssize_t
rb_io_bufwrite(VALUE io, const void *buf, size_t size)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);
    return (ssize_t)io_binwrite(buf, (long)size, fptr, 0);
}

static VALUE
io_write(VALUE io, VALUE str, int nosync)
{
    rb_io_t *fptr;
    long n;
    VALUE tmp;

    io = GetWriteIO(io);
    str = rb_obj_as_string(str);
    tmp = rb_io_check_io(io);

    if (NIL_P(tmp)) {
        /* port is not IO, call write method for it. */
        return rb_funcall(io, id_write, 1, str);
    }

    io = tmp;
    if (RSTRING_LEN(str) == 0) return INT2FIX(0);

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    n = io_fwrite(str, fptr, nosync);
    if (n < 0L) rb_sys_fail_on_write(fptr);

    return LONG2FIX(n);
}

#ifdef HAVE_WRITEV
struct binwritev_arg {
    rb_io_t *fptr;
    struct iovec *iov;
    int iovcnt;
    size_t total;
};

static VALUE
io_binwritev_internal(VALUE arg)
{
    struct binwritev_arg *p = (struct binwritev_arg *)arg;

    size_t remaining = p->total;
    size_t offset = 0;

    rb_io_t *fptr = p->fptr;
    struct iovec *iov = p->iov;
    int iovcnt = p->iovcnt;

    while (remaining) {
        long result = rb_writev_internal(fptr, iov, iovcnt);

        if (result >= 0) {
            offset += result;
            if (fptr->wbuf.ptr && fptr->wbuf.len) {
                if (offset < (size_t)fptr->wbuf.len) {
                    fptr->wbuf.off += result;
                    fptr->wbuf.len -= result;
                }
                else {
                    offset -= (size_t)fptr->wbuf.len;
                    fptr->wbuf.off = 0;
                    fptr->wbuf.len = 0;
                }
            }

            if (offset == p->total) {
                return p->total;
            }

            while (result >= (ssize_t)iov->iov_len) {
                /* iovcnt > 0 */
                result -= iov->iov_len;
                iov->iov_len = 0;
                iov++;

                if (!--iovcnt) {
                    // I don't believe this code path can ever occur.
                    return offset;
                }
            }

            iov->iov_base = (char *)iov->iov_base + result;
            iov->iov_len -= result;
        }
        else if (rb_io_maybe_wait_writable(errno, fptr->self, RUBY_IO_TIMEOUT_DEFAULT)) {
            rb_io_check_closed(fptr);
        }
        else {
            return -1;
        }
    }

    return offset;
}

static long
io_binwritev(struct iovec *iov, int iovcnt, rb_io_t *fptr)
{
    // Don't write anything if current thread has a pending interrupt:
    rb_thread_check_ints();

    if (iovcnt == 0) return 0;

    size_t total = 0;
    for (int i = 1; i < iovcnt; i++) total += iov[i].iov_len;

    io_allocate_write_buffer(fptr, 1);

    if (fptr->wbuf.ptr && fptr->wbuf.len) {
        // The end of the buffered data:
        size_t offset = fptr->wbuf.off + fptr->wbuf.len;

        if (offset + total <= (size_t)fptr->wbuf.capa) {
            for (int i = 1; i < iovcnt; i++) {
                memcpy(fptr->wbuf.ptr+offset, iov[i].iov_base, iov[i].iov_len);
                offset += iov[i].iov_len;
            }

            fptr->wbuf.len += total;

            return total;
        }
        else {
            iov[0].iov_base = fptr->wbuf.ptr + fptr->wbuf.off;
            iov[0].iov_len = fptr->wbuf.len;
        }
    }
    else {
        // The first iov is reserved for the internal buffer, and it's empty.
        iov++;

        if (!--iovcnt) {
            // If there are no other io vectors we are done.
            return 0;
        }
    }

    struct binwritev_arg arg;
    arg.fptr = fptr;
    arg.iov = iov;
    arg.iovcnt = iovcnt;
    arg.total = total;

    if (!NIL_P(fptr->write_lock)) {
        return rb_mutex_synchronize(fptr->write_lock, io_binwritev_internal, (VALUE)&arg);
    }
    else {
        return io_binwritev_internal((VALUE)&arg);
    }
}

static long
io_fwritev(int argc, const VALUE *argv, rb_io_t *fptr)
{
    int i, converted, iovcnt = argc + 1;
    long n;
    VALUE v1, v2, str, tmp, *tmp_array;
    struct iovec *iov;

    iov = ALLOCV_N(struct iovec, v1, iovcnt);
    tmp_array = ALLOCV_N(VALUE, v2, argc);

    for (i = 0; i < argc; i++) {
        str = rb_obj_as_string(argv[i]);
        converted = 0;
        str = do_writeconv(str, fptr, &converted);

        if (converted)
            OBJ_FREEZE(str);

        tmp = rb_str_tmp_frozen_acquire(str);
        tmp_array[i] = tmp;

        /* iov[0] is reserved for buffer of fptr */
        iov[i+1].iov_base = RSTRING_PTR(tmp);
        iov[i+1].iov_len = RSTRING_LEN(tmp);
    }

    n = io_binwritev(iov, iovcnt, fptr);
    if (v1) ALLOCV_END(v1);

    for (i = 0; i < argc; i++) {
        rb_str_tmp_frozen_release(argv[i], tmp_array[i]);
    }

    if (v2) ALLOCV_END(v2);

    return n;
}

static int
iovcnt_ok(int iovcnt)
{
#ifdef IOV_MAX
    return iovcnt < IOV_MAX;
#else /* GNU/Hurd has writev, but no IOV_MAX */
    return 1;
#endif
}
#endif /* HAVE_WRITEV */

static VALUE
io_writev(int argc, const VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    long n;
    VALUE tmp, total = INT2FIX(0);
    int i, cnt = 1;

    io = GetWriteIO(io);
    tmp = rb_io_check_io(io);

    if (NIL_P(tmp)) {
        /* port is not IO, call write method for it. */
        return rb_funcallv(io, id_write, argc, argv);
    }

    io = tmp;

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    for (i = 0; i < argc; i += cnt) {
#ifdef HAVE_WRITEV
        if ((fptr->mode & (FMODE_SYNC|FMODE_TTY)) && iovcnt_ok(cnt = argc - i)) {
            n = io_fwritev(cnt, &argv[i], fptr);
        }
        else
#endif
        {
            cnt = 1;
            /* sync at last item */
            n = io_fwrite(rb_obj_as_string(argv[i]), fptr, (i < argc-1));
        }

        if (n < 0L)
            rb_sys_fail_on_write(fptr);

        total = rb_fix_plus(LONG2FIX(n), total);
    }

    return total;
}

/*
 *  call-seq:
 *    write(*objects) -> integer
 *
 *  Writes each of the given +objects+ to +self+,
 *  which must be opened for writing
 *  (see {Access Modes}[rdoc-ref:File@Access+Modes]);
 *  returns the total number bytes written;
 *  each of +objects+ that is not a string is converted via method +to_s+:
 *
 *    $stdout.write('Hello', ', ', 'World!', "\n") # => 14
 *    $stdout.write('foo', :bar, 2, "\n")          # => 8
 *
 *  Output:
 *
 *    Hello, World!
 *    foobar2
 *
 *  Related: IO#read.
 */

static VALUE
io_write_m(int argc, VALUE *argv, VALUE io)
{
    if (argc != 1) {
        return io_writev(argc, argv, io);
    }
    else {
        VALUE str = argv[0];
        return io_write(io, str, 0);
    }
}

VALUE
rb_io_write(VALUE io, VALUE str)
{
    return rb_funcallv(io, id_write, 1, &str);
}

static VALUE
rb_io_writev(VALUE io, int argc, const VALUE *argv)
{
    if (argc > 1 && rb_obj_method_arity(io, id_write) == 1) {
        if (io != rb_ractor_stderr() && RTEST(ruby_verbose)) {
            VALUE klass = CLASS_OF(io);
            char sep = RCLASS_SINGLETON_P(klass) ? (klass = io, '.') : '#';
            rb_category_warning(
                RB_WARN_CATEGORY_DEPRECATED, "%+"PRIsVALUE"%c""write is outdated interface"
                " which accepts just one argument",
                klass, sep
            );
        }

        do rb_io_write(io, *argv++); while (--argc);

        return Qnil;
    }

    return rb_funcallv(io, id_write, argc, argv);
}

/*
 *  call-seq:
 *    self << object -> self
 *
 *  Writes the given +object+ to +self+,
 *  which must be opened for writing (see {Access Modes}[rdoc-ref:File@Access+Modes]);
 *  returns +self+;
 *  if +object+ is not a string, it is converted via method +to_s+:
 *
 *    $stdout << 'Hello' << ', ' << 'World!' << "\n"
 *    $stdout << 'foo' << :bar << 2 << "\n"
 *
 *  Output:
 *
 *    Hello, World!
 *    foobar2
 *
 */


VALUE
rb_io_addstr(VALUE io, VALUE str)
{
    rb_io_write(io, str);
    return io;
}

#ifdef HAVE_FSYNC
static VALUE
nogvl_fsync(void *ptr)
{
    rb_io_t *fptr = ptr;

#ifdef _WIN32
    if (GetFileType((HANDLE)rb_w32_get_osfhandle(fptr->fd)) != FILE_TYPE_DISK)
        return 0;
#endif
    return (VALUE)fsync(fptr->fd);
}
#endif

VALUE
rb_io_flush_raw(VALUE io, int sync)
{
    rb_io_t *fptr;

    if (!RB_TYPE_P(io, T_FILE)) {
        return rb_funcall(io, id_flush, 0);
    }

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    if (fptr->mode & FMODE_WRITABLE) {
        if (io_fflush(fptr) < 0)
            rb_sys_fail_on_write(fptr);
    }
    if (fptr->mode & FMODE_READABLE) {
        io_unread(fptr, true);
    }

    return io;
}

/*
 *  call-seq:
 *    flush -> self
 *
 *  Flushes data buffered in +self+ to the operating system
 *  (but does not necessarily flush data buffered in the operating system):
 *
 *    $stdout.print 'no newline' # Not necessarily flushed.
 *    $stdout.flush              # Flushed.
 *
 */

VALUE
rb_io_flush(VALUE io)
{
    return rb_io_flush_raw(io, 1);
}

/*
 *  call-seq:
 *    tell -> integer
 *
 *  Returns the current position (in bytes) in +self+
 *  (see {Position}[rdoc-ref:IO@Position]):
 *
 *    f = File.open('t.txt')
 *    f.tell # => 0
 *    f.gets # => "First line\n"
 *    f.tell # => 12
 *    f.close
 *
 *  Related: IO#pos=, IO#seek.
 */

static VALUE
rb_io_tell(VALUE io)
{
    rb_io_t *fptr;
    rb_off_t pos;

    GetOpenFile(io, fptr);
    pos = io_tell(fptr);
    if (pos < 0 && errno) rb_sys_fail_path(fptr->pathv);
    pos -= fptr->rbuf.len;
    return OFFT2NUM(pos);
}

static VALUE
rb_io_seek(VALUE io, VALUE offset, int whence)
{
    rb_io_t *fptr;
    rb_off_t pos;

    pos = NUM2OFFT(offset);
    GetOpenFile(io, fptr);
    pos = io_seek(fptr, pos, whence);
    if (pos < 0 && errno) rb_sys_fail_path(fptr->pathv);

    return INT2FIX(0);
}

static int
interpret_seek_whence(VALUE vwhence)
{
    if (vwhence == sym_SET)
        return SEEK_SET;
    if (vwhence == sym_CUR)
        return SEEK_CUR;
    if (vwhence == sym_END)
        return SEEK_END;
#ifdef SEEK_DATA
    if (vwhence == sym_DATA)
        return SEEK_DATA;
#endif
#ifdef SEEK_HOLE
    if (vwhence == sym_HOLE)
        return SEEK_HOLE;
#endif
    return NUM2INT(vwhence);
}

/*
 *  call-seq:
 *    seek(offset, whence = IO::SEEK_SET) -> 0
 *
 *  Seeks to the position given by integer +offset+
 *  (see {Position}[rdoc-ref:IO@Position])
 *  and constant +whence+, which is one of:
 *
 *  - +:CUR+ or <tt>IO::SEEK_CUR</tt>:
 *    Repositions the stream to its current position plus the given +offset+:
 *
 *      f = File.open('t.txt')
 *      f.tell            # => 0
 *      f.seek(20, :CUR)  # => 0
 *      f.tell            # => 20
 *      f.seek(-10, :CUR) # => 0
 *      f.tell            # => 10
 *      f.close
 *
 *  - +:END+ or <tt>IO::SEEK_END</tt>:
 *    Repositions the stream to its end plus the given +offset+:
 *
 *      f = File.open('t.txt')
 *      f.tell            # => 0
 *      f.seek(0, :END)   # => 0  # Repositions to stream end.
 *      f.tell            # => 52
 *      f.seek(-20, :END) # => 0
 *      f.tell            # => 32
 *      f.seek(-40, :END) # => 0
 *      f.tell            # => 12
 *      f.close
 *
 *  - +:SET+ or <tt>IO:SEEK_SET</tt>:
 *    Repositions the stream to the given +offset+:
 *
 *      f = File.open('t.txt')
 *      f.tell            # => 0
 *      f.seek(20, :SET) # => 0
 *      f.tell           # => 20
 *      f.seek(40, :SET) # => 0
 *      f.tell           # => 40
 *      f.close
 *
 *  Related: IO#pos=, IO#tell.
 *
 */

static VALUE
rb_io_seek_m(int argc, VALUE *argv, VALUE io)
{
    VALUE offset, ptrname;
    int whence = SEEK_SET;

    if (rb_scan_args(argc, argv, "11", &offset, &ptrname) == 2) {
        whence = interpret_seek_whence(ptrname);
    }

    return rb_io_seek(io, offset, whence);
}

/*
 *  call-seq:
 *    pos = new_position -> new_position
 *
 *  Seeks to the given +new_position+ (in bytes);
 *  see {Position}[rdoc-ref:IO@Position]:
 *
 *    f = File.open('t.txt')
 *    f.tell     # => 0
 *    f.pos = 20 # => 20
 *    f.tell     # => 20
 *    f.close
 *
 *  Related: IO#seek, IO#tell.
 *
 */

static VALUE
rb_io_set_pos(VALUE io, VALUE offset)
{
    rb_io_t *fptr;
    rb_off_t pos;

    pos = NUM2OFFT(offset);
    GetOpenFile(io, fptr);
    pos = io_seek(fptr, pos, SEEK_SET);
    if (pos < 0 && errno) rb_sys_fail_path(fptr->pathv);

    return OFFT2NUM(pos);
}

static void clear_readconv(rb_io_t *fptr);

/*
 *  call-seq:
 *    rewind -> 0
 *
 *  Repositions the stream to its beginning,
 *  setting both the position and the line number to zero;
 *  see {Position}[rdoc-ref:IO@Position]
 *  and {Line Number}[rdoc-ref:IO@Line+Number]:
 *
 *    f = File.open('t.txt')
 *    f.tell     # => 0
 *    f.lineno   # => 0
 *    f.gets     # => "First line\n"
 *    f.tell     # => 12
 *    f.lineno   # => 1
 *    f.rewind   # => 0
 *    f.tell     # => 0
 *    f.lineno   # => 0
 *    f.close
 *
 *  Note that this method cannot be used with streams such as pipes, ttys, and sockets.
 *
 */

static VALUE
rb_io_rewind(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (io_seek(fptr, 0L, 0) < 0 && errno) rb_sys_fail_path(fptr->pathv);
    if (io == ARGF.current_file) {
        ARGF.lineno -= fptr->lineno;
    }
    fptr->lineno = 0;
    if (fptr->readconv) {
        clear_readconv(fptr);
    }

    return INT2FIX(0);
}

static int
fptr_wait_readable(rb_io_t *fptr)
{
    int result = rb_io_maybe_wait_readable(errno, fptr->self, RUBY_IO_TIMEOUT_DEFAULT);

    if (result)
        rb_io_check_closed(fptr);

    return result;
}

static int
io_fillbuf(rb_io_t *fptr)
{
    ssize_t r;

    if (fptr->rbuf.ptr == NULL) {
        fptr->rbuf.off = 0;
        fptr->rbuf.len = 0;
        fptr->rbuf.capa = IO_RBUF_CAPA_FOR(fptr);
        fptr->rbuf.ptr = ALLOC_N(char, fptr->rbuf.capa);
#ifdef _WIN32
        fptr->rbuf.capa--;
#endif
    }
    if (fptr->rbuf.len == 0) {
      retry:
        r = rb_io_read_memory(fptr, fptr->rbuf.ptr, fptr->rbuf.capa);

        if (r < 0) {
            if (fptr_wait_readable(fptr))
                goto retry;

            int e = errno;
            VALUE path = rb_sprintf("fd:%d ", fptr->fd);
            if (!NIL_P(fptr->pathv)) {
                rb_str_append(path, fptr->pathv);
            }

            rb_syserr_fail_path(e, path);
        }
        if (r > 0) rb_io_check_closed(fptr);
        fptr->rbuf.off = 0;
        fptr->rbuf.len = (int)r; /* r should be <= rbuf_capa */
        if (r == 0)
            return -1; /* EOF */
    }
    return 0;
}

/*
 *  call-seq:
 *    eof -> true or false
 *
 *  Returns +true+ if the stream is positioned at its end, +false+ otherwise;
 *  see {Position}[rdoc-ref:IO@Position]:
 *
 *    f = File.open('t.txt')
 *    f.eof           # => false
 *    f.seek(0, :END) # => 0
 *    f.eof           # => true
 *    f.close
 *
 *  Raises an exception unless the stream is opened for reading;
 *  see {Mode}[rdoc-ref:File@Access+Modes].
 *
 *  If +self+ is a stream such as pipe or socket, this method
 *  blocks until the other end sends some data or closes it:
 *
 *    r, w = IO.pipe
 *    Thread.new { sleep 1; w.close }
 *    r.eof? # => true # After 1-second wait.
 *
 *    r, w = IO.pipe
 *    Thread.new { sleep 1; w.puts "a" }
 *    r.eof?  # => false # After 1-second wait.
 *
 *    r, w = IO.pipe
 *    r.eof?  # blocks forever
 *
 *  Note that this method reads data to the input byte buffer.  So
 *  IO#sysread may not behave as you intend with IO#eof?, unless you
 *  call IO#rewind first (which is not available for some streams).
 */

VALUE
rb_io_eof(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);

    if (READ_CHAR_PENDING(fptr)) return Qfalse;
    if (READ_DATA_PENDING(fptr)) return Qfalse;
    READ_CHECK(fptr);
#if RUBY_CRLF_ENVIRONMENT
    if (!NEED_READCONV(fptr) && NEED_NEWLINE_DECORATOR_ON_READ(fptr)) {
        return RBOOL(eof(fptr->fd));
    }
#endif
    return RBOOL(io_fillbuf(fptr) < 0);
}

/*
 *  call-seq:
 *    sync -> true or false
 *
 *  Returns the current sync mode of the stream.
 *  When sync mode is true, all output is immediately flushed to the underlying
 *  operating system and is not buffered by Ruby internally. See also #fsync.
 *
 *    f = File.open('t.tmp', 'w')
 *    f.sync # => false
 *    f.sync = true
 *    f.sync # => true
 *    f.close
 *
 */

static VALUE
rb_io_sync(VALUE io)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    return RBOOL(fptr->mode & FMODE_SYNC);
}

#ifdef HAVE_FSYNC

/*
 *  call-seq:
 *    sync = boolean -> boolean
 *
 *  Sets the _sync_ _mode_ for the stream to the given value;
 *  returns the given value.
 *
 *  Values for the sync mode:
 *
 *  - +true+: All output is immediately flushed to the
 *    underlying operating system and is not buffered internally.
 *  - +false+: Output may be buffered internally.
 *
 *  Example;
 *
 *    f = File.open('t.tmp', 'w')
 *    f.sync # => false
 *    f.sync = true
 *    f.sync # => true
 *    f.close
 *
 *  Related: IO#fsync.
 *
 */

static VALUE
rb_io_set_sync(VALUE io, VALUE sync)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    if (RTEST(sync)) {
        fptr->mode |= FMODE_SYNC;
    }
    else {
        fptr->mode &= ~FMODE_SYNC;
    }
    return sync;
}

/*
 *  call-seq:
 *    fsync -> 0
 *
 *  Immediately writes to disk all data buffered in the stream,
 *  via the operating system's <tt>fsync(2)</tt>.

 *  Note this difference:
 *
 *  - IO#sync=: Ensures that data is flushed from the stream's internal buffers,
 *    but does not guarantee that the operating system actually writes the data to disk.
 *  - IO#fsync: Ensures both that data is flushed from internal buffers,
 *    and that data is written to disk.
 *
 *  Raises an exception if the operating system does not support <tt>fsync(2)</tt>.
 *
 */

static VALUE
rb_io_fsync(VALUE io)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    if (io_fflush(fptr) < 0)
        rb_sys_fail_on_write(fptr);

    if ((int)rb_io_blocking_region(fptr, nogvl_fsync, fptr))
        rb_sys_fail_path(fptr->pathv);

    return INT2FIX(0);
}
#else
# define rb_io_fsync rb_f_notimplement
# define rb_io_sync rb_f_notimplement
static VALUE
rb_io_set_sync(VALUE io, VALUE sync)
{
    rb_notimplement();
    UNREACHABLE;
}
#endif

#ifdef HAVE_FDATASYNC
static VALUE
nogvl_fdatasync(void *ptr)
{
    rb_io_t *fptr = ptr;

#ifdef _WIN32
    if (GetFileType((HANDLE)rb_w32_get_osfhandle(fptr->fd)) != FILE_TYPE_DISK)
        return 0;
#endif
    return (VALUE)fdatasync(fptr->fd);
}

/*
 *  call-seq:
 *    fdatasync -> 0
 *
 *  Immediately writes to disk all data buffered in the stream,
 *  via the operating system's: <tt>fdatasync(2)</tt>, if supported,
 *  otherwise via <tt>fsync(2)</tt>, if supported;
 *  otherwise raises an exception.
 *
 */

static VALUE
rb_io_fdatasync(VALUE io)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    if (io_fflush(fptr) < 0)
        rb_sys_fail_on_write(fptr);

    if ((int)rb_io_blocking_region(fptr, nogvl_fdatasync, fptr) == 0)
        return INT2FIX(0);

    /* fall back */
    return rb_io_fsync(io);
}
#else
#define rb_io_fdatasync rb_io_fsync
#endif

/*
 *  call-seq:
 *    fileno -> integer
 *
 *  Returns the integer file descriptor for the stream:
 *
 *    $stdin.fileno             # => 0
 *    $stdout.fileno            # => 1
 *    $stderr.fileno            # => 2
 *    File.open('t.txt').fileno # => 10
 *    f.close
 *
 */

static VALUE
rb_io_fileno(VALUE io)
{
    rb_io_t *fptr = RFILE(io)->fptr;
    int fd;

    rb_io_check_closed(fptr);
    fd = fptr->fd;
    return INT2FIX(fd);
}

int
rb_io_descriptor(VALUE io)
{
    if (RB_TYPE_P(io, T_FILE)) {
        rb_io_t *fptr = RFILE(io)->fptr;
        rb_io_check_closed(fptr);
        return fptr->fd;
    }
    else {
        VALUE fileno = rb_check_funcall(io, id_fileno, 0, NULL);
        if (!UNDEF_P(fileno)) {
            return RB_NUM2INT(fileno);
        }
    }

    rb_raise(rb_eTypeError, "expected IO or #fileno, %"PRIsVALUE" given", rb_obj_class(io));

    UNREACHABLE_RETURN(-1);
}

int
rb_io_mode(VALUE io)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    return fptr->mode;
}

/*
 *  call-seq:
 *    pid -> integer or nil
 *
 *  Returns the process ID of a child process associated with the stream,
 *  which will have been set by IO#popen, or +nil+ if the stream was not
 *  created by IO#popen:
 *
 *    pipe = IO.popen("-")
 *    if pipe
 *      $stderr.puts "In parent, child pid is #{pipe.pid}"
 *    else
 *      $stderr.puts "In child, pid is #{$$}"
 *    end
 *
 *  Output:
 *
 *    In child, pid is 26209
 *    In parent, child pid is 26209
 *
 */

static VALUE
rb_io_pid(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (!fptr->pid)
        return Qnil;
    return PIDT2NUM(fptr->pid);
}

/*
 *  call-seq:
 *    path -> string or nil
 *
 *  Returns the path associated with the IO, or +nil+ if there is no path
 *  associated with the IO. It is not guaranteed that the path exists on
 *  the filesystem.
 *
 *    $stdin.path # => "<STDIN>"
 *
 *    File.open("testfile") {|f| f.path} # => "testfile"
 */

VALUE
rb_io_path(VALUE io)
{
    rb_io_t *fptr = RFILE(io)->fptr;

    if (!fptr)
        return Qnil;

    return rb_obj_dup(fptr->pathv);
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a string representation of +self+:
 *
 *    f = File.open('t.txt')
 *    f.inspect # => "#<File:t.txt>"
 *    f.close
 *
 */

static VALUE
rb_io_inspect(VALUE obj)
{
    rb_io_t *fptr;
    VALUE result;
    static const char closed[] = " (closed)";

    fptr = RFILE(obj)->fptr;
    if (!fptr) return rb_any_to_s(obj);
    result = rb_str_new_cstr("#<");
    rb_str_append(result, rb_class_name(CLASS_OF(obj)));
    rb_str_cat2(result, ":");
    if (NIL_P(fptr->pathv)) {
        if (fptr->fd < 0) {
            rb_str_cat(result, closed+1, strlen(closed)-1);
        }
        else {
            rb_str_catf(result, "fd %d", fptr->fd);
        }
    }
    else {
        rb_str_append(result, fptr->pathv);
        if (fptr->fd < 0) {
            rb_str_cat(result, closed, strlen(closed));
        }
    }
    return rb_str_cat2(result, ">");
}

/*
 *  call-seq:
 *    to_io -> self
 *
 *  Returns +self+.
 *
 */

static VALUE
rb_io_to_io(VALUE io)
{
    return io;
}

/* reading functions */
static long
read_buffered_data(char *ptr, long len, rb_io_t *fptr)
{
    int n;

    n = READ_DATA_PENDING_COUNT(fptr);
    if (n <= 0) return 0;
    if (n > len) n = (int)len;
    MEMMOVE(ptr, fptr->rbuf.ptr+fptr->rbuf.off, char, n);
    fptr->rbuf.off += n;
    fptr->rbuf.len -= n;
    return n;
}

static long
io_bufread(char *ptr, long len, rb_io_t *fptr)
{
    long offset = 0;
    long n = len;
    long c;

    if (READ_DATA_PENDING(fptr) == 0) {
        while (n > 0) {
          again:
            rb_io_check_closed(fptr);
            c = rb_io_read_memory(fptr, ptr+offset, n);
            if (c == 0) break;
            if (c < 0) {
                if (fptr_wait_readable(fptr))
                    goto again;
                return -1;
            }
            offset += c;
            if ((n -= c) <= 0) break;
        }
        return len - n;
    }

    while (n > 0) {
        c = read_buffered_data(ptr+offset, n, fptr);
        if (c > 0) {
            offset += c;
            if ((n -= c) <= 0) break;
        }
        rb_io_check_closed(fptr);
        if (io_fillbuf(fptr) < 0) {
            break;
        }
    }
    return len - n;
}

static int io_setstrbuf(VALUE *str, long len);

struct bufread_arg {
    char *str_ptr;
    long len;
    rb_io_t *fptr;
};

static VALUE
bufread_call(VALUE arg)
{
    struct bufread_arg *p = (struct bufread_arg *)arg;
    p->len = io_bufread(p->str_ptr, p->len, p->fptr);
    return Qundef;
}

static long
io_fread(VALUE str, long offset, long size, rb_io_t *fptr)
{
    long len;
    struct bufread_arg arg;

    io_setstrbuf(&str, offset + size);
    arg.str_ptr = RSTRING_PTR(str) + offset;
    arg.len = size;
    arg.fptr = fptr;
    rb_str_locktmp_ensure(str, bufread_call, (VALUE)&arg);
    len = arg.len;
    if (len < 0) rb_sys_fail_path(fptr->pathv);
    return len;
}

static long
remain_size(rb_io_t *fptr)
{
    struct stat st;
    rb_off_t siz = READ_DATA_PENDING_COUNT(fptr);
    rb_off_t pos;

    if (fstat(fptr->fd, &st) == 0  && S_ISREG(st.st_mode)
#if defined(__HAIKU__)
        && (st.st_dev > 3)
#endif
        )
    {
        if (io_fflush(fptr) < 0)
            rb_sys_fail_on_write(fptr);
        pos = lseek(fptr->fd, 0, SEEK_CUR);
        if (st.st_size >= pos && pos >= 0) {
            siz += st.st_size - pos;
            if (siz > LONG_MAX) {
                rb_raise(rb_eIOError, "file too big for single read");
            }
        }
    }
    else {
        siz += BUFSIZ;
    }
    return (long)siz;
}

static VALUE
io_enc_str(VALUE str, rb_io_t *fptr)
{
    rb_enc_associate(str, io_read_encoding(fptr));
    return str;
}

static rb_encoding *io_read_encoding(rb_io_t *fptr);

static void
make_readconv(rb_io_t *fptr, int size)
{
    if (!fptr->readconv) {
        int ecflags;
        VALUE ecopts;
        const char *sname, *dname;
        ecflags = fptr->encs.ecflags & ~ECONV_NEWLINE_DECORATOR_WRITE_MASK;
        ecopts = fptr->encs.ecopts;
        if (fptr->encs.enc2) {
            sname = rb_enc_name(fptr->encs.enc2);
            dname = rb_enc_name(io_read_encoding(fptr));
        }
        else {
            sname = dname = "";
        }
        fptr->readconv = rb_econv_open_opts(sname, dname, ecflags, ecopts);
        if (!fptr->readconv)
            rb_exc_raise(rb_econv_open_exc(sname, dname, ecflags));
        fptr->cbuf.off = 0;
        fptr->cbuf.len = 0;
        if (size < IO_CBUF_CAPA_MIN) size = IO_CBUF_CAPA_MIN;
        fptr->cbuf.capa = size;
        fptr->cbuf.ptr = ALLOC_N(char, fptr->cbuf.capa);
    }
}

#define MORE_CHAR_SUSPENDED Qtrue
#define MORE_CHAR_FINISHED Qnil
static VALUE
fill_cbuf(rb_io_t *fptr, int ec_flags)
{
    const unsigned char *ss, *sp, *se;
    unsigned char *ds, *dp, *de;
    rb_econv_result_t res;
    int putbackable;
    int cbuf_len0;
    VALUE exc;

    ec_flags |= ECONV_PARTIAL_INPUT;

    if (fptr->cbuf.len == fptr->cbuf.capa)
        return MORE_CHAR_SUSPENDED; /* cbuf full */
    if (fptr->cbuf.len == 0)
        fptr->cbuf.off = 0;
    else if (fptr->cbuf.off + fptr->cbuf.len == fptr->cbuf.capa) {
        memmove(fptr->cbuf.ptr, fptr->cbuf.ptr+fptr->cbuf.off, fptr->cbuf.len);
        fptr->cbuf.off = 0;
    }

    cbuf_len0 = fptr->cbuf.len;

    while (1) {
        ss = sp = (const unsigned char *)fptr->rbuf.ptr + fptr->rbuf.off;
        se = sp + fptr->rbuf.len;
        ds = dp = (unsigned char *)fptr->cbuf.ptr + fptr->cbuf.off + fptr->cbuf.len;
        de = (unsigned char *)fptr->cbuf.ptr + fptr->cbuf.capa;
        res = rb_econv_convert(fptr->readconv, &sp, se, &dp, de, ec_flags);
        fptr->rbuf.off += (int)(sp - ss);
        fptr->rbuf.len -= (int)(sp - ss);
        fptr->cbuf.len += (int)(dp - ds);

        putbackable = rb_econv_putbackable(fptr->readconv);
        if (putbackable) {
            rb_econv_putback(fptr->readconv, (unsigned char *)fptr->rbuf.ptr + fptr->rbuf.off - putbackable, putbackable);
            fptr->rbuf.off -= putbackable;
            fptr->rbuf.len += putbackable;
        }

        exc = rb_econv_make_exception(fptr->readconv);
        if (!NIL_P(exc))
            return exc;

        if (cbuf_len0 != fptr->cbuf.len)
            return MORE_CHAR_SUSPENDED;

        if (res == econv_finished) {
            return MORE_CHAR_FINISHED;
        }

        if (res == econv_source_buffer_empty) {
            if (fptr->rbuf.len == 0) {
                READ_CHECK(fptr);
                if (io_fillbuf(fptr) < 0) {
                    if (!fptr->readconv) {
                        return MORE_CHAR_FINISHED;
                    }
                    ds = dp = (unsigned char *)fptr->cbuf.ptr + fptr->cbuf.off + fptr->cbuf.len;
                    de = (unsigned char *)fptr->cbuf.ptr + fptr->cbuf.capa;
                    res = rb_econv_convert(fptr->readconv, NULL, NULL, &dp, de, 0);
                    fptr->cbuf.len += (int)(dp - ds);
                    rb_econv_check_error(fptr->readconv);
                    break;
                }
            }
        }
    }
    if (cbuf_len0 != fptr->cbuf.len)
        return MORE_CHAR_SUSPENDED;

    return MORE_CHAR_FINISHED;
}

static VALUE
more_char(rb_io_t *fptr)
{
    VALUE v;
    v = fill_cbuf(fptr, ECONV_AFTER_OUTPUT);
    if (v != MORE_CHAR_SUSPENDED && v != MORE_CHAR_FINISHED)
        rb_exc_raise(v);
    return v;
}

static VALUE
io_shift_cbuf(rb_io_t *fptr, int len, VALUE *strp)
{
    VALUE str = Qnil;
    if (strp) {
        str = *strp;
        if (NIL_P(str)) {
            *strp = str = rb_str_new(fptr->cbuf.ptr+fptr->cbuf.off, len);
        }
        else {
            rb_str_cat(str, fptr->cbuf.ptr+fptr->cbuf.off, len);
        }
        rb_enc_associate(str, fptr->encs.enc);
    }
    fptr->cbuf.off += len;
    fptr->cbuf.len -= len;
    /* xxx: set coderange */
    if (fptr->cbuf.len == 0)
        fptr->cbuf.off = 0;
    else if (fptr->cbuf.capa/2 < fptr->cbuf.off) {
        memmove(fptr->cbuf.ptr, fptr->cbuf.ptr+fptr->cbuf.off, fptr->cbuf.len);
        fptr->cbuf.off = 0;
    }
    return str;
}

static int
io_setstrbuf(VALUE *str, long len)
{
#ifdef _WIN32
    if (len > 0)
        len = (len + 1) & ~1L;	/* round up for wide char */
#endif
    if (NIL_P(*str)) {
        *str = rb_str_new(0, len);
        return TRUE;
    }
    else {
        VALUE s = StringValue(*str);
        rb_str_modify(s);

        long clen = RSTRING_LEN(s);
        if (clen >= len) {
            return FALSE;
        }
        len -= clen;
    }
    if ((rb_str_capacity(*str) - (size_t)RSTRING_LEN(*str)) < (size_t)len) {
        rb_str_modify_expand(*str, len);
    }
    return FALSE;
}

#define MAX_REALLOC_GAP 4096
static void
io_shrink_read_string(VALUE str, long n)
{
    if (rb_str_capacity(str) - n > MAX_REALLOC_GAP) {
        rb_str_resize(str, n);
    }
}

static void
io_set_read_length(VALUE str, long n, int shrinkable)
{
    if (RSTRING_LEN(str) != n) {
        rb_str_modify(str);
        rb_str_set_len(str, n);
        if (shrinkable) io_shrink_read_string(str, n);
    }
}

static VALUE
read_all(rb_io_t *fptr, long siz, VALUE str)
{
    long bytes;
    long n;
    long pos;
    rb_encoding *enc;
    int cr;
    int shrinkable;

    if (NEED_READCONV(fptr)) {
        int first = !NIL_P(str);
        SET_BINARY_MODE(fptr);
        shrinkable = io_setstrbuf(&str,0);
        make_readconv(fptr, 0);
        while (1) {
            VALUE v;
            if (fptr->cbuf.len) {
                if (first) rb_str_set_len(str, first = 0);
                io_shift_cbuf(fptr, fptr->cbuf.len, &str);
            }
            v = fill_cbuf(fptr, 0);
            if (v != MORE_CHAR_SUSPENDED && v != MORE_CHAR_FINISHED) {
                if (fptr->cbuf.len) {
                    if (first) rb_str_set_len(str, first = 0);
                    io_shift_cbuf(fptr, fptr->cbuf.len, &str);
                }
                rb_exc_raise(v);
            }
            if (v == MORE_CHAR_FINISHED) {
                clear_readconv(fptr);
                if (first) rb_str_set_len(str, first = 0);
                if (shrinkable) io_shrink_read_string(str, RSTRING_LEN(str));
                return io_enc_str(str, fptr);
            }
        }
    }

    NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr);
    bytes = 0;
    pos = 0;

    enc = io_read_encoding(fptr);
    cr = 0;

    if (siz == 0) siz = BUFSIZ;
    shrinkable = io_setstrbuf(&str, siz);
    for (;;) {
        READ_CHECK(fptr);
        n = io_fread(str, bytes, siz - bytes, fptr);
        if (n == 0 && bytes == 0) {
            rb_str_set_len(str, 0);
            break;
        }
        bytes += n;
        rb_str_set_len(str, bytes);
        if (cr != ENC_CODERANGE_BROKEN)
            pos += rb_str_coderange_scan_restartable(RSTRING_PTR(str) + pos, RSTRING_PTR(str) + bytes, enc, &cr);
        if (bytes < siz) break;
        siz += BUFSIZ;

        size_t capa = rb_str_capacity(str);
        if (capa < (size_t)RSTRING_LEN(str) + BUFSIZ) {
            if (capa < BUFSIZ) {
                capa = BUFSIZ;
            }
            else if (capa > IO_MAX_BUFFER_GROWTH) {
                capa = IO_MAX_BUFFER_GROWTH;
            }
            rb_str_modify_expand(str, capa);
        }
    }
    if (shrinkable) io_shrink_read_string(str, RSTRING_LEN(str));
    str = io_enc_str(str, fptr);
    ENC_CODERANGE_SET(str, cr);
    return str;
}

void
rb_io_set_nonblock(rb_io_t *fptr)
{
    if (rb_fd_set_nonblock(fptr->fd) != 0) {
        rb_sys_fail_path(fptr->pathv);
    }
}

static VALUE
io_read_memory_call(VALUE arg)
{
    struct io_internal_read_struct *iis = (struct io_internal_read_struct *)arg;

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_read_memory(scheduler, iis->fptr->self, iis->buf, iis->capa, 0);

        if (!UNDEF_P(result)) {
            // This is actually returned as a pseudo-VALUE and later cast to a long:
            return (VALUE)rb_fiber_scheduler_io_result_apply(result);
        }
    }

    if (iis->nonblock) {
        return rb_io_blocking_region(iis->fptr, internal_read_func, iis);
    }
    else {
        return rb_io_blocking_region_wait(iis->fptr, internal_read_func, iis, RUBY_IO_READABLE);
    }
}

static long
io_read_memory_locktmp(VALUE str, struct io_internal_read_struct *iis)
{
    return (long)rb_str_locktmp_ensure(str, io_read_memory_call, (VALUE)iis);
}

#define no_exception_p(opts) !rb_opts_exception_p((opts), TRUE)

static VALUE
io_getpartial(int argc, VALUE *argv, VALUE io, int no_exception, int nonblock)
{
    rb_io_t *fptr;
    VALUE length, str;
    long n, len;
    struct io_internal_read_struct iis;
    int shrinkable;

    rb_scan_args(argc, argv, "11", &length, &str);

    if ((len = NUM2LONG(length)) < 0) {
        rb_raise(rb_eArgError, "negative length %ld given", len);
    }

    shrinkable = io_setstrbuf(&str, len);

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);

    if (len == 0) {
        io_set_read_length(str, 0, shrinkable);
        return str;
    }

    if (!nonblock)
        READ_CHECK(fptr);
    n = read_buffered_data(RSTRING_PTR(str), len, fptr);
    if (n <= 0) {
      again:
        if (nonblock) {
            rb_io_set_nonblock(fptr);
        }
        io_setstrbuf(&str, len);
        iis.th = rb_thread_current();
        iis.fptr = fptr;
        iis.nonblock = nonblock;
        iis.fd = fptr->fd;
        iis.buf = RSTRING_PTR(str);
        iis.capa = len;
        iis.timeout = NULL;
        n = io_read_memory_locktmp(str, &iis);
        if (n < 0) {
            int e = errno;
            if (!nonblock && fptr_wait_readable(fptr))
                goto again;
            if (nonblock && (io_again_p(e))) {
                if (no_exception)
                    return sym_wait_readable;
                else
                    rb_readwrite_syserr_fail(RB_IO_WAIT_READABLE,
                                             e, "read would block");
            }
            rb_syserr_fail_path(e, fptr->pathv);
        }
    }
    io_set_read_length(str, n, shrinkable);

    if (n == 0)
        return Qnil;
    else
        return str;
}

/*
 *  call-seq:
 *    readpartial(maxlen)             -> string
 *    readpartial(maxlen, out_string) -> out_string
 *
 *  Reads up to +maxlen+ bytes from the stream;
 *  returns a string (either a new string or the given +out_string+).
 *  Its encoding is:
 *
 *  - The unchanged encoding of +out_string+, if +out_string+ is given.
 *  - ASCII-8BIT, otherwise.
 *
 *  - Contains +maxlen+ bytes from the stream, if available.
 *  - Otherwise contains all available bytes, if any available.
 *  - Otherwise is an empty string.
 *
 *  With the single non-negative integer argument +maxlen+ given,
 *  returns a new string:
 *
 *    f = File.new('t.txt')
 *    f.readpartial(20) # => "First line\nSecond l"
 *    f.readpartial(20) # => "ine\n\nFourth line\n"
 *    f.readpartial(20) # => "Fifth line\n"
 *    f.readpartial(20) # Raises EOFError.
 *    f.close
 *
 *  With both argument +maxlen+ and string argument +out_string+ given,
 *  returns modified +out_string+:
 *
 *    f = File.new('t.txt')
 *    s = 'foo'
 *    f.readpartial(20, s) # => "First line\nSecond l"
 *    s = 'bar'
 *    f.readpartial(0, s)  # => ""
 *    f.close
 *
 *  This method is useful for a stream such as a pipe, a socket, or a tty.
 *  It blocks only when no data is immediately available.
 *  This means that it blocks only when _all_ of the following are true:
 *
 *  - The byte buffer in the stream is empty.
 *  - The content of the stream is empty.
 *  - The stream is not at EOF.
 *
 *  When blocked, the method waits for either more data or EOF on the stream:
 *
 *  - If more data is read, the method returns the data.
 *  - If EOF is reached, the method raises EOFError.
 *
 *  When not blocked, the method responds immediately:
 *
 *  - Returns data from the buffer if there is any.
 *  - Otherwise returns data from the stream if there is any.
 *  - Otherwise raises EOFError if the stream has reached EOF.
 *
 *  Note that this method is similar to sysread. The differences are:
 *
 *  - If the byte buffer is not empty, read from the byte buffer
 *    instead of "sysread for buffered IO (IOError)".
 *  - It doesn't cause Errno::EWOULDBLOCK and Errno::EINTR.  When
 *    readpartial meets EWOULDBLOCK and EINTR by read system call,
 *    readpartial retries the system call.
 *
 *  The latter means that readpartial is non-blocking-flag insensitive.
 *  It blocks on the situation IO#sysread causes Errno::EWOULDBLOCK as
 *  if the fd is blocking mode.
 *
 *  Examples:
 *
 *     #                        # Returned      Buffer Content    Pipe Content
 *     r, w = IO.pipe           #
 *     w << 'abc'               #               ""                "abc".
 *     r.readpartial(4096)      # => "abc"      ""                ""
 *     r.readpartial(4096)      # (Blocks because buffer and pipe are empty.)
 *
 *     #                        # Returned      Buffer Content    Pipe Content
 *     r, w = IO.pipe           #
 *     w << 'abc'               #               ""                "abc"
 *     w.close                  #               ""                "abc" EOF
 *     r.readpartial(4096)      # => "abc"      ""                 EOF
 *     r.readpartial(4096)      # raises EOFError
 *
 *     #                        # Returned      Buffer Content    Pipe Content
 *     r, w = IO.pipe           #
 *     w << "abc\ndef\n"        #               ""                "abc\ndef\n"
 *     r.gets                   # => "abc\n"    "def\n"           ""
 *     w << "ghi\n"             #               "def\n"           "ghi\n"
 *     r.readpartial(4096)      # => "def\n"    ""                "ghi\n"
 *     r.readpartial(4096)      # => "ghi\n"    ""                ""
 *
 */

static VALUE
io_readpartial(int argc, VALUE *argv, VALUE io)
{
    VALUE ret;

    ret = io_getpartial(argc, argv, io, Qnil, 0);
    if (NIL_P(ret))
        rb_eof_error();
    return ret;
}

static VALUE
io_nonblock_eof(int no_exception)
{
    if (!no_exception) {
        rb_eof_error();
    }
    return Qnil;
}

/* :nodoc: */
static VALUE
io_read_nonblock(rb_execution_context_t *ec, VALUE io, VALUE length, VALUE str, VALUE ex)
{
    rb_io_t *fptr;
    long n, len;
    struct io_internal_read_struct iis;
    int shrinkable;

    if ((len = NUM2LONG(length)) < 0) {
        rb_raise(rb_eArgError, "negative length %ld given", len);
    }

    shrinkable = io_setstrbuf(&str, len);
    rb_bool_expected(ex, "exception", TRUE);

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);

    if (len == 0) {
        io_set_read_length(str, 0, shrinkable);
        return str;
    }

    n = read_buffered_data(RSTRING_PTR(str), len, fptr);
    if (n <= 0) {
        rb_fd_set_nonblock(fptr->fd);
        shrinkable |= io_setstrbuf(&str, len);
        iis.fptr = fptr;
        iis.nonblock = 1;
        iis.fd = fptr->fd;
        iis.buf = RSTRING_PTR(str);
        iis.capa = len;
        iis.timeout = NULL;
        n = io_read_memory_locktmp(str, &iis);
        if (n < 0) {
            int e = errno;
            if (io_again_p(e)) {
                if (!ex) return sym_wait_readable;
                rb_readwrite_syserr_fail(RB_IO_WAIT_READABLE,
                                         e, "read would block");
            }
            rb_syserr_fail_path(e, fptr->pathv);
        }
    }
    io_set_read_length(str, n, shrinkable);

    if (n == 0) {
        if (!ex) return Qnil;
        rb_eof_error();
    }

    return str;
}

/* :nodoc: */
static VALUE
io_write_nonblock(rb_execution_context_t *ec, VALUE io, VALUE str, VALUE ex)
{
    rb_io_t *fptr;
    long n;

    if (!RB_TYPE_P(str, T_STRING))
        str = rb_obj_as_string(str);
    rb_bool_expected(ex, "exception", TRUE);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    if (io_fflush(fptr) < 0)
        rb_sys_fail_on_write(fptr);

    rb_fd_set_nonblock(fptr->fd);
    n = write(fptr->fd, RSTRING_PTR(str), RSTRING_LEN(str));
    RB_GC_GUARD(str);

    if (n < 0) {
        int e = errno;
        if (io_again_p(e)) {
            if (!ex) {
                return sym_wait_writable;
            }
            else {
                rb_readwrite_syserr_fail(RB_IO_WAIT_WRITABLE, e, "write would block");
            }
        }
        rb_syserr_fail_path(e, fptr->pathv);
    }

    return LONG2FIX(n);
}

/*
 *  call-seq:
 *    read(maxlen = nil, out_string = nil) -> new_string, out_string, or nil
 *
 *  Reads bytes from the stream; the stream must be opened for reading
 *  (see {Access Modes}[rdoc-ref:File@Access+Modes]):
 *
 *  - If +maxlen+ is +nil+, reads all bytes using the stream's data mode.
 *  - Otherwise reads up to +maxlen+ bytes in binary mode.
 *
 *  Returns a string (either a new string or the given +out_string+)
 *  containing the bytes read.
 *  The encoding of the string depends on both +maxLen+ and +out_string+:
 *
 *  - +maxlen+ is +nil+: uses internal encoding of +self+
 *    (regardless of whether +out_string+ was given).
 *  - +maxlen+ not +nil+:
 *
 *    - +out_string+ given: encoding of +out_string+ not modified.
 *    - +out_string+ not given: ASCII-8BIT is used.
 *
 *  <b>Without Argument +out_string+</b>
 *
 *  When argument +out_string+ is omitted,
 *  the returned value is a new string:
 *
 *    f = File.new('t.txt')
 *    f.read
 *    # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *    f.rewind
 *    f.read(30) # => "First line\r\nSecond line\r\n\r\nFou"
 *    f.read(30) # => "rth line\r\nFifth line\r\n"
 *    f.read(30) # => nil
 *    f.close
 *
 *  If +maxlen+ is zero, returns an empty string.
 *
 *  <b> With Argument +out_string+</b>
 *
 *  When argument +out_string+ is given,
 *  the returned value is +out_string+, whose content is replaced:
 *
 *    f = File.new('t.txt')
 *    s = 'foo'      # => "foo"
 *    f.read(nil, s) # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *    s              # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *    f.rewind
 *    s = 'bar'
 *    f.read(30, s)  # => "First line\r\nSecond line\r\n\r\nFou"
 *    s              # => "First line\r\nSecond line\r\n\r\nFou"
 *    s = 'baz'
 *    f.read(30, s)  # => "rth line\r\nFifth line\r\n"
 *    s              # => "rth line\r\nFifth line\r\n"
 *    s = 'bat'
 *    f.read(30, s)  # => nil
 *    s              # => ""
 *    f.close
 *
 *  Note that this method behaves like the fread() function in C.
 *  This means it retries to invoke read(2) system calls to read data
 *  with the specified maxlen (or until EOF).
 *
 *  This behavior is preserved even if the stream is in non-blocking mode.
 *  (This method is non-blocking-flag insensitive as other methods.)
 *
 *  If you need the behavior like a single read(2) system call,
 *  consider #readpartial, #read_nonblock, and #sysread.
 *
 *  Related: IO#write.
 */

static VALUE
io_read(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    long n, len;
    VALUE length, str;
    int shrinkable;
#if RUBY_CRLF_ENVIRONMENT
    int previous_mode;
#endif

    rb_scan_args(argc, argv, "02", &length, &str);

    if (NIL_P(length)) {
        GetOpenFile(io, fptr);
        rb_io_check_char_readable(fptr);
        return read_all(fptr, remain_size(fptr), str);
    }
    len = NUM2LONG(length);
    if (len < 0) {
        rb_raise(rb_eArgError, "negative length %ld given", len);
    }

    shrinkable = io_setstrbuf(&str,len);

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);
    if (len == 0) {
        io_set_read_length(str, 0, shrinkable);
        return str;
    }

    READ_CHECK(fptr);
#if RUBY_CRLF_ENVIRONMENT
    previous_mode = set_binary_mode_with_seek_cur(fptr);
#endif
    n = io_fread(str, 0, len, fptr);
    io_set_read_length(str, n, shrinkable);
#if RUBY_CRLF_ENVIRONMENT
    if (previous_mode == O_TEXT) {
        setmode(fptr->fd, O_TEXT);
    }
#endif
    if (n == 0) return Qnil;

    return str;
}

static void
rscheck(const char *rsptr, long rslen, VALUE rs)
{
    if (!rs) return;
    if (RSTRING_PTR(rs) != rsptr && RSTRING_LEN(rs) != rslen)
        rb_raise(rb_eRuntimeError, "rs modified");
}

static const char *
search_delim(const char *p, long len, int delim, rb_encoding *enc)
{
    if (rb_enc_mbminlen(enc) == 1) {
        p = memchr(p, delim, len);
        if (p) return p + 1;
    }
    else {
        const char *end = p + len;
        while (p < end) {
            int r = rb_enc_precise_mbclen(p, end, enc);
            if (!MBCLEN_CHARFOUND_P(r)) {
                p += rb_enc_mbminlen(enc);
                continue;
            }
            int n = MBCLEN_CHARFOUND_LEN(r);
            if (rb_enc_mbc_to_codepoint(p, end, enc) == (unsigned int)delim) {
                return p + n;
            }
            p += n;
        }
    }
    return NULL;
}

static int
appendline(rb_io_t *fptr, int delim, VALUE *strp, long *lp, rb_encoding *enc)
{
    VALUE str = *strp;
    long limit = *lp;

    if (NEED_READCONV(fptr)) {
        SET_BINARY_MODE(fptr);
        make_readconv(fptr, 0);
        do {
            const char *p, *e;
            int searchlen = READ_CHAR_PENDING_COUNT(fptr);
            if (searchlen) {
                p = READ_CHAR_PENDING_PTR(fptr);
                if (0 < limit && limit < searchlen)
                    searchlen = (int)limit;
                e = search_delim(p, searchlen, delim, enc);
                if (e) {
                    int len = (int)(e-p);
                    if (NIL_P(str))
                        *strp = str = rb_str_new(p, len);
                    else
                        rb_str_buf_cat(str, p, len);
                    fptr->cbuf.off += len;
                    fptr->cbuf.len -= len;
                    limit -= len;
                    *lp = limit;
                    return delim;
                }

                if (NIL_P(str))
                    *strp = str = rb_str_new(p, searchlen);
                else
                    rb_str_buf_cat(str, p, searchlen);
                fptr->cbuf.off += searchlen;
                fptr->cbuf.len -= searchlen;
                limit -= searchlen;

                if (limit == 0) {
                    *lp = limit;
                    return (unsigned char)RSTRING_PTR(str)[RSTRING_LEN(str)-1];
                }
            }
        } while (more_char(fptr) != MORE_CHAR_FINISHED);
        clear_readconv(fptr);
        *lp = limit;
        return EOF;
    }

    NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr);
    do {
        long pending = READ_DATA_PENDING_COUNT(fptr);
        if (pending > 0) {
            const char *p = READ_DATA_PENDING_PTR(fptr);
            const char *e;
            long last;

            if (limit > 0 && pending > limit) pending = limit;
            e = search_delim(p, pending, delim, enc);
            if (e) pending = e - p;
            if (!NIL_P(str)) {
                last = RSTRING_LEN(str);
                rb_str_resize(str, last + pending);
            }
            else {
                last = 0;
                *strp = str = rb_str_buf_new(pending);
                rb_str_set_len(str, pending);
            }
            read_buffered_data(RSTRING_PTR(str) + last, pending, fptr); /* must not fail */
            limit -= pending;
            *lp = limit;
            if (e) return delim;
            if (limit == 0)
                return (unsigned char)RSTRING_PTR(str)[RSTRING_LEN(str)-1];
        }
        READ_CHECK(fptr);
    } while (io_fillbuf(fptr) >= 0);
    *lp = limit;
    return EOF;
}

static inline int
swallow(rb_io_t *fptr, int term)
{
    if (NEED_READCONV(fptr)) {
        rb_encoding *enc = io_read_encoding(fptr);
        int needconv = rb_enc_mbminlen(enc) != 1;
        SET_BINARY_MODE(fptr);
        make_readconv(fptr, 0);
        do {
            size_t cnt;
            while ((cnt = READ_CHAR_PENDING_COUNT(fptr)) > 0) {
                const char *p = READ_CHAR_PENDING_PTR(fptr);
                int i;
                if (!needconv) {
                    if (*p != term) return TRUE;
                    i = (int)cnt;
                    while (--i && *++p == term);
                }
                else {
                    const char *e = p + cnt;
                    if (rb_enc_ascget(p, e, &i, enc) != term) return TRUE;
                    while ((p += i) < e && rb_enc_ascget(p, e, &i, enc) == term);
                    i = (int)(e - p);
                }
                io_shift_cbuf(fptr, (int)cnt - i, NULL);
            }
        } while (more_char(fptr) != MORE_CHAR_FINISHED);
        return FALSE;
    }

    NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr);
    do {
        size_t cnt;
        while ((cnt = READ_DATA_PENDING_COUNT(fptr)) > 0) {
            char buf[1024];
            const char *p = READ_DATA_PENDING_PTR(fptr);
            int i;
            if (cnt > sizeof buf) cnt = sizeof buf;
            if (*p != term) return TRUE;
            i = (int)cnt;
            while (--i && *++p == term);
            if (!read_buffered_data(buf, cnt - i, fptr)) /* must not fail */
                rb_sys_fail_path(fptr->pathv);
        }
        READ_CHECK(fptr);
    } while (io_fillbuf(fptr) == 0);
    return FALSE;
}

static VALUE
rb_io_getline_fast(rb_io_t *fptr, rb_encoding *enc, int chomp)
{
    VALUE str = Qnil;
    int len = 0;
    long pos = 0;
    int cr = 0;

    do {
        int pending = READ_DATA_PENDING_COUNT(fptr);

        if (pending > 0) {
            const char *p = READ_DATA_PENDING_PTR(fptr);
            const char *e;
            int chomplen = 0;

            e = memchr(p, '\n', pending);
            if (e) {
                pending = (int)(e - p + 1);
                if (chomp) {
                    chomplen = (pending > 1 && *(e-1) == '\r') + 1;
                }
            }
            if (NIL_P(str)) {
                str = rb_str_new(p, pending - chomplen);
                fptr->rbuf.off += pending;
                fptr->rbuf.len -= pending;
            }
            else {
                rb_str_resize(str, len + pending - chomplen);
                read_buffered_data(RSTRING_PTR(str)+len, pending - chomplen, fptr);
                fptr->rbuf.off += chomplen;
                fptr->rbuf.len -= chomplen;
                if (pending == 1 && chomplen == 1 && len > 0) {
                    if (RSTRING_PTR(str)[len-1] == '\r') {
                        rb_str_resize(str, --len);
                        break;
                    }
                }
            }
            len += pending - chomplen;
            if (cr != ENC_CODERANGE_BROKEN)
                pos += rb_str_coderange_scan_restartable(RSTRING_PTR(str) + pos, RSTRING_PTR(str) + len, enc, &cr);
            if (e) break;
        }
        READ_CHECK(fptr);
    } while (io_fillbuf(fptr) >= 0);
    if (NIL_P(str)) return Qnil;

    str = io_enc_str(str, fptr);
    ENC_CODERANGE_SET(str, cr);
    fptr->lineno++;

    return str;
}

struct getline_arg {
    VALUE io;
    VALUE rs;
    long limit;
    unsigned int chomp: 1;
};

static void
extract_getline_opts(VALUE opts, struct getline_arg *args)
{
    int chomp = FALSE;
    if (!NIL_P(opts)) {
        static ID kwds[1];
        VALUE vchomp;
        if (!kwds[0]) {
            kwds[0] = rb_intern_const("chomp");
        }
        rb_get_kwargs(opts, kwds, 0, -2, &vchomp);
        chomp = (!UNDEF_P(vchomp)) && RTEST(vchomp);
    }
    args->chomp = chomp;
}

static void
extract_getline_args(int argc, VALUE *argv, struct getline_arg *args)
{
    VALUE rs = rb_rs, lim = Qnil;

    if (argc == 1) {
        VALUE tmp = Qnil;

        if (NIL_P(argv[0]) || !NIL_P(tmp = rb_check_string_type(argv[0]))) {
            rs = tmp;
        }
        else {
            lim = argv[0];
        }
    }
    else if (2 <= argc) {
        rs = argv[0], lim = argv[1];
        if (!NIL_P(rs))
            StringValue(rs);
    }
    args->rs = rs;
    args->limit = NIL_P(lim) ? -1L : NUM2LONG(lim);
}

static void
check_getline_args(VALUE *rsp, long *limit, VALUE io)
{
    rb_io_t *fptr;
    VALUE rs = *rsp;

    if (!NIL_P(rs)) {
        rb_encoding *enc_rs, *enc_io;

        GetOpenFile(io, fptr);
        enc_rs = rb_enc_get(rs);
        enc_io = io_read_encoding(fptr);
        if (enc_io != enc_rs &&
            (!is_ascii_string(rs) ||
             (RSTRING_LEN(rs) > 0 && !rb_enc_asciicompat(enc_io)))) {
            if (rs == rb_default_rs) {
                rs = rb_enc_str_new(0, 0, enc_io);
                rb_str_buf_cat_ascii(rs, "\n");
                *rsp = rs;
            }
            else {
                rb_raise(rb_eArgError, "encoding mismatch: %s IO with %s RS",
                         rb_enc_name(enc_io),
                         rb_enc_name(enc_rs));
            }
        }
    }
}

static void
prepare_getline_args(int argc, VALUE *argv, struct getline_arg *args, VALUE io)
{
    VALUE opts;
    argc = rb_scan_args(argc, argv, "02:", NULL, NULL, &opts);
    extract_getline_args(argc, argv, args);
    extract_getline_opts(opts, args);
    check_getline_args(&args->rs, &args->limit, io);
}

static VALUE
rb_io_getline_0(VALUE rs, long limit, int chomp, rb_io_t *fptr)
{
    VALUE str = Qnil;
    int nolimit = 0;
    rb_encoding *enc;

    rb_io_check_char_readable(fptr);
    if (NIL_P(rs) && limit < 0) {
        str = read_all(fptr, 0, Qnil);
        if (RSTRING_LEN(str) == 0) return Qnil;
    }
    else if (limit == 0) {
        return rb_enc_str_new(0, 0, io_read_encoding(fptr));
    }
    else if (rs == rb_default_rs && limit < 0 && !NEED_READCONV(fptr) &&
             rb_enc_asciicompat(enc = io_read_encoding(fptr))) {
        NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr);
        return rb_io_getline_fast(fptr, enc, chomp);
    }
    else {
        int c, newline = -1;
        const char *rsptr = 0;
        long rslen = 0;
        int rspara = 0;
        int extra_limit = 16;
        int chomp_cr = chomp;

        SET_BINARY_MODE(fptr);
        enc = io_read_encoding(fptr);

        if (!NIL_P(rs)) {
            rslen = RSTRING_LEN(rs);
            if (rslen == 0) {
                rsptr = "\n\n";
                rslen = 2;
                rspara = 1;
                swallow(fptr, '\n');
                rs = 0;
                if (!rb_enc_asciicompat(enc)) {
                    rs = rb_usascii_str_new(rsptr, rslen);
                    rs = rb_str_conv_enc(rs, 0, enc);
                    OBJ_FREEZE(rs);
                    rsptr = RSTRING_PTR(rs);
                    rslen = RSTRING_LEN(rs);
                }
                newline = '\n';
            }
            else if (rb_enc_mbminlen(enc) == 1) {
                 rsptr = RSTRING_PTR(rs);
                 newline = (unsigned char)rsptr[rslen - 1];
            }
            else {
                rs = rb_str_conv_enc(rs, 0, enc);
                rsptr = RSTRING_PTR(rs);
                const char *e = rsptr + rslen;
                const char *last = rb_enc_prev_char(rsptr, e, e, enc);
                int n;
                newline = rb_enc_codepoint_len(last, e, &n, enc);
                if (last + n != e) rb_raise(rb_eArgError, "broken separator");
            }
            chomp_cr = chomp && newline == '\n' && rslen == rb_enc_mbminlen(enc);
        }

        /* MS - Optimization */
        while ((c = appendline(fptr, newline, &str, &limit, enc)) != EOF) {
            const char *s, *p, *pp, *e;

            if (c == newline) {
                if (RSTRING_LEN(str) < rslen) continue;
                s = RSTRING_PTR(str);
                e = RSTRING_END(str);
                p = e - rslen;
                if (!at_char_boundary(s, p, e, enc)) continue;
                if (!rspara) rscheck(rsptr, rslen, rs);
                if (memcmp(p, rsptr, rslen) == 0) {
                    if (chomp) {
                        if (chomp_cr && p > s && *(p-1) == '\r') --p;
                        rb_str_set_len(str, p - s);
                    }
                    break;
                }
            }
            if (limit == 0) {
                s = RSTRING_PTR(str);
                p = RSTRING_END(str);
                pp = rb_enc_prev_char(s, p, p, enc);
                if (extra_limit && pp &&
                    MBCLEN_NEEDMORE_P(rb_enc_precise_mbclen(pp, p, enc))) {
                    /* relax the limit while incomplete character.
                     * extra_limit limits the relax length */
                    limit = 1;
                    extra_limit--;
                }
                else {
                    nolimit = 1;
                    break;
                }
            }
        }

        if (rspara && c != EOF)
            swallow(fptr, '\n');
        if (!NIL_P(str))
            str = io_enc_str(str, fptr);
    }

    if (!NIL_P(str) && !nolimit) {
        fptr->lineno++;
    }

    return str;
}

static VALUE
rb_io_getline_1(VALUE rs, long limit, int chomp, VALUE io)
{
    rb_io_t *fptr;
    int old_lineno, new_lineno;
    VALUE str;

    GetOpenFile(io, fptr);
    old_lineno = fptr->lineno;
    str = rb_io_getline_0(rs, limit, chomp, fptr);
    if (!NIL_P(str) && (new_lineno = fptr->lineno) != old_lineno) {
        if (io == ARGF.current_file) {
            ARGF.lineno += new_lineno - old_lineno;
            ARGF.last_lineno = ARGF.lineno;
        }
        else {
            ARGF.last_lineno = new_lineno;
        }
    }

    return str;
}

static VALUE
rb_io_getline(int argc, VALUE *argv, VALUE io)
{
    struct getline_arg args;

    prepare_getline_args(argc, argv, &args, io);
    return rb_io_getline_1(args.rs, args.limit, args.chomp, io);
}

VALUE
rb_io_gets(VALUE io)
{
    return rb_io_getline_1(rb_default_rs, -1, FALSE, io);
}

VALUE
rb_io_gets_internal(VALUE io)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    return rb_io_getline_0(rb_default_rs, -1, FALSE, fptr);
}

/*
 *  call-seq:
 *    gets(sep = $/, chomp: false)   -> string or nil
 *    gets(limit, chomp: false)      -> string or nil
 *    gets(sep, limit, chomp: false) -> string or nil
 *
 *  Reads and returns a line from the stream;
 *  assigns the return value to <tt>$_</tt>.
 *  See {Line IO}[rdoc-ref:IO@Line+IO].
 *
 *  With no arguments given, returns the next line
 *  as determined by line separator <tt>$/</tt>, or +nil+ if none:
 *
 *    f = File.open('t.txt')
 *    f.gets # => "First line\n"
 *    $_     # => "First line\n"
 *    f.gets # => "\n"
 *    f.gets # => "Fourth line\n"
 *    f.gets # => "Fifth line\n"
 *    f.gets # => nil
 *    f.close
 *
 *  With only string argument +sep+ given,
 *  returns the next line as determined by line separator +sep+,
 *  or +nil+ if none;
 *  see {Line Separator}[rdoc-ref:IO@Line+Separator]:
 *
 *    f = File.new('t.txt')
 *    f.gets('l')   # => "First l"
 *    f.gets('li')  # => "ine\nSecond li"
 *    f.gets('lin') # => "ne\n\nFourth lin"
 *    f.gets        # => "e\n"
 *    f.close
 *
 *  The two special values for +sep+ are honored:
 *
 *    f = File.new('t.txt')
 *    # Get all.
 *    f.gets(nil) # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *    f.rewind
 *    # Get paragraph (up to two line separators).
 *    f.gets('')  # => "First line\nSecond line\n\n"
 *    f.close
 *
 *  With only integer argument +limit+ given,
 *  limits the number of bytes in the line;
 *  see {Line Limit}[rdoc-ref:IO@Line+Limit]:
 *
 *    # No more than one line.
 *    File.open('t.txt') {|f| f.gets(10) } # => "First line"
 *    File.open('t.txt') {|f| f.gets(11) } # => "First line\n"
 *    File.open('t.txt') {|f| f.gets(12) } # => "First line\n"
 *
 *  With arguments +sep+ and +limit+ given,
 *  combines the two behaviors
 *  (see {Line Separator and Line Limit}[rdoc-ref:IO@Line+Separator+and+Line+Limit]).
 *
 *  Optional keyword argument +chomp+ specifies whether line separators
 *  are to be omitted:
 *
 *    f = File.open('t.txt')
 *    # Chomp the lines.
 *    f.gets(chomp: true) # => "First line"
 *    f.gets(chomp: true) # => "Second line"
 *    f.gets(chomp: true) # => ""
 *    f.gets(chomp: true) # => "Fourth line"
 *    f.gets(chomp: true) # => "Fifth line"
 *    f.gets(chomp: true) # => nil
 *    f.close
 *
 */

static VALUE
rb_io_gets_m(int argc, VALUE *argv, VALUE io)
{
    VALUE str;

    str = rb_io_getline(argc, argv, io);
    rb_lastline_set(str);

    return str;
}

/*
 *  call-seq:
 *    lineno -> integer
 *
 *  Returns the current line number for the stream;
 *  see {Line Number}[rdoc-ref:IO@Line+Number].
 *
 */

static VALUE
rb_io_lineno(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);
    return INT2NUM(fptr->lineno);
}

/*
 *  call-seq:
 *    lineno = integer -> integer
 *
 *  Sets and returns the line number for the stream;
 *  see {Line Number}[rdoc-ref:IO@Line+Number].
 *
 */

static VALUE
rb_io_set_lineno(VALUE io, VALUE lineno)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);
    fptr->lineno = NUM2INT(lineno);
    return lineno;
}

/* :nodoc: */
static VALUE
io_readline(rb_execution_context_t *ec, VALUE io, VALUE sep, VALUE lim, VALUE chomp)
{
    long limit = -1;
    if (NIL_P(lim)) {
        VALUE tmp = Qnil;
        // If sep is specified, but it's not a string and not nil, then assume
        // it's the limit (it should be an integer)
        if (!NIL_P(sep) && NIL_P(tmp = rb_check_string_type(sep))) {
            // If the user has specified a non-nil / non-string value
            // for the separator, we assume it's the limit and set the
            // separator to default: rb_rs.
            lim = sep;
            limit = NUM2LONG(lim);
            sep = rb_rs;
        }
        else {
            sep = tmp;
        }
    }
    else {
        if (!NIL_P(sep)) StringValue(sep);
        limit = NUM2LONG(lim);
    }

    check_getline_args(&sep, &limit, io);

    VALUE line = rb_io_getline_1(sep, limit, RTEST(chomp), io);
    rb_lastline_set_up(line, 1);

    if (NIL_P(line)) {
        rb_eof_error();
    }
    return line;
}

static VALUE io_readlines(const struct getline_arg *arg, VALUE io);

/*
 *  call-seq:
 *    readlines(sep = $/, chomp: false)   -> array
 *    readlines(limit, chomp: false)       -> array
 *    readlines(sep, limit, chomp: false) -> array
 *
 *  Reads and returns all remaining line from the stream;
 *  does not modify <tt>$_</tt>.
 *  See {Line IO}[rdoc-ref:IO@Line+IO].
 *
 *  With no arguments given, returns lines
 *  as determined by line separator <tt>$/</tt>, or +nil+ if none:
 *
 *    f = File.new('t.txt')
 *    f.readlines
 *    # => ["First line\n", "Second line\n", "\n", "Fourth line\n", "Fifth line\n"]
 *    f.readlines # => []
 *    f.close
 *
 *  With only string argument +sep+ given,
 *  returns lines as determined by line separator +sep+,
 *  or +nil+ if none;
 *  see {Line Separator}[rdoc-ref:IO@Line+Separator]:
 *
 *    f = File.new('t.txt')
 *    f.readlines('li')
 *    # => ["First li", "ne\nSecond li", "ne\n\nFourth li", "ne\nFifth li", "ne\n"]
 *    f.close
 *
 *  The two special values for +sep+ are honored:
 *
 *    f = File.new('t.txt')
 *    # Get all into one string.
 *    f.readlines(nil)
 *    # => ["First line\nSecond line\n\nFourth line\nFifth line\n"]
 *    # Get paragraphs (up to two line separators).
 *    f.rewind
 *    f.readlines('')
 *    # => ["First line\nSecond line\n\n", "Fourth line\nFifth line\n"]
 *    f.close
 *
 *  With only integer argument +limit+ given,
 *  limits the number of bytes in each line;
 *  see {Line Limit}[rdoc-ref:IO@Line+Limit]:
 *
 *    f = File.new('t.txt')
 *    f.readlines(8)
 *    # => ["First li", "ne\n", "Second l", "ine\n", "\n", "Fourth l", "ine\n", "Fifth li", "ne\n"]
 *    f.close
 *
 *  With arguments +sep+ and +limit+ given,
 *  combines the two behaviors
 *  (see {Line Separator and Line Limit}[rdoc-ref:IO@Line+Separator+and+Line+Limit]).
 *
 *  Optional keyword argument +chomp+ specifies whether line separators
 *  are to be omitted:
 *
 *    f = File.new('t.txt')
 *    f.readlines(chomp: true)
 *    # => ["First line", "Second line", "", "Fourth line", "Fifth line"]
 *    f.close
 *
 */

static VALUE
rb_io_readlines(int argc, VALUE *argv, VALUE io)
{
    struct getline_arg args;

    prepare_getline_args(argc, argv, &args, io);
    return io_readlines(&args, io);
}

static VALUE
io_readlines(const struct getline_arg *arg, VALUE io)
{
    VALUE line, ary;

    if (arg->limit == 0)
        rb_raise(rb_eArgError, "invalid limit: 0 for readlines");
    ary = rb_ary_new();
    while (!NIL_P(line = rb_io_getline_1(arg->rs, arg->limit, arg->chomp, io))) {
        rb_ary_push(ary, line);
    }
    return ary;
}

/*
 *  call-seq:
 *    each_line(sep = $/, chomp: false) {|line| ... }   -> self
 *    each_line(limit, chomp: false) {|line| ... }      -> self
 *    each_line(sep, limit, chomp: false) {|line| ... } -> self
 *    each_line                                   -> enumerator
 *
 *  Calls the block with each remaining line read from the stream;
 *  returns +self+.
 *  Does nothing if already at end-of-stream;
 *  See {Line IO}[rdoc-ref:IO@Line+IO].
 *
 *  With no arguments given, reads lines
 *  as determined by line separator <tt>$/</tt>:
 *
 *    f = File.new('t.txt')
 *    f.each_line {|line| p line }
 *    f.each_line {|line| fail 'Cannot happen' }
 *    f.close
 *
 *  Output:
 *
 *    "First line\n"
 *    "Second line\n"
 *    "\n"
 *    "Fourth line\n"
 *    "Fifth line\n"
 *
 *  With only string argument +sep+ given,
 *  reads lines as determined by line separator +sep+;
 *  see {Line Separator}[rdoc-ref:IO@Line+Separator]:
 *
 *    f = File.new('t.txt')
 *    f.each_line('li') {|line| p line }
 *    f.close
 *
 *  Output:
 *
 *    "First li"
 *    "ne\nSecond li"
 *    "ne\n\nFourth li"
 *    "ne\nFifth li"
 *    "ne\n"
 *
 *  The two special values for +sep+ are honored:
 *
 *    f = File.new('t.txt')
 *    # Get all into one string.
 *    f.each_line(nil) {|line| p line }
 *    f.close
 *
 *  Output:
 *
 *    "First line\nSecond line\n\nFourth line\nFifth line\n"
 *
 *    f.rewind
 *    # Get paragraphs (up to two line separators).
 *    f.each_line('') {|line| p line }
 *
 *  Output:
 *
 *    "First line\nSecond line\n\n"
 *    "Fourth line\nFifth line\n"
 *
 *  With only integer argument +limit+ given,
 *  limits the number of bytes in each line;
 *  see {Line Limit}[rdoc-ref:IO@Line+Limit]:
 *
 *    f = File.new('t.txt')
 *    f.each_line(8) {|line| p line }
 *    f.close
 *
 *  Output:
 *
 *    "First li"
 *    "ne\n"
 *    "Second l"
 *    "ine\n"
 *    "\n"
 *    "Fourth l"
 *    "ine\n"
 *    "Fifth li"
 *    "ne\n"
 *
 *  With arguments +sep+ and +limit+ given,
 *  combines the two behaviors
 *  (see {Line Separator and Line Limit}[rdoc-ref:IO@Line+Separator+and+Line+Limit]).
 *
 *  Optional keyword argument +chomp+ specifies whether line separators
 *  are to be omitted:
 *
 *    f = File.new('t.txt')
 *    f.each_line(chomp: true) {|line| p line }
 *    f.close
 *
 *  Output:
 *
 *    "First line"
 *    "Second line"
 *    ""
 *    "Fourth line"
 *    "Fifth line"
 *
 *  Returns an Enumerator if no block is given.
 */

static VALUE
rb_io_each_line(int argc, VALUE *argv, VALUE io)
{
    VALUE str;
    struct getline_arg args;

    RETURN_ENUMERATOR(io, argc, argv);
    prepare_getline_args(argc, argv, &args, io);
    if (args.limit == 0)
        rb_raise(rb_eArgError, "invalid limit: 0 for each_line");
    while (!NIL_P(str = rb_io_getline_1(args.rs, args.limit, args.chomp, io))) {
        rb_yield(str);
    }
    return io;
}

/*
 *  call-seq:
 *    each_byte {|byte| ... } -> self
 *    each_byte               -> enumerator
 *
 *  Calls the given block with each byte (0..255) in the stream; returns +self+.
 *  See {Byte IO}[rdoc-ref:IO@Byte+IO].
 *
 *    f = File.new('t.rus')
 *    a = []
 *    f.each_byte {|b| a << b }
 *    a # => [209, 130, 208, 181, 209, 129, 209, 130]
 *    f.close
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: IO#each_char, IO#each_codepoint.
 *
 */

static VALUE
rb_io_each_byte(VALUE io)
{
    rb_io_t *fptr;

    RETURN_ENUMERATOR(io, 0, 0);
    GetOpenFile(io, fptr);

    do {
        while (fptr->rbuf.len > 0) {
            char *p = fptr->rbuf.ptr + fptr->rbuf.off++;
            fptr->rbuf.len--;
            rb_yield(INT2FIX(*p & 0xff));
            rb_io_check_byte_readable(fptr);
            errno = 0;
        }
        READ_CHECK(fptr);
    } while (io_fillbuf(fptr) >= 0);
    return io;
}

static VALUE
io_getc(rb_io_t *fptr, rb_encoding *enc)
{
    int r, n, cr = 0;
    VALUE str;

    if (NEED_READCONV(fptr)) {
        rb_encoding *read_enc = io_read_encoding(fptr);

        str = Qnil;
        SET_BINARY_MODE(fptr);
        make_readconv(fptr, 0);

        while (1) {
            if (fptr->cbuf.len) {
                r = rb_enc_precise_mbclen(fptr->cbuf.ptr+fptr->cbuf.off,
                        fptr->cbuf.ptr+fptr->cbuf.off+fptr->cbuf.len,
                        read_enc);
                if (!MBCLEN_NEEDMORE_P(r))
                    break;
                if (fptr->cbuf.len == fptr->cbuf.capa) {
                    rb_raise(rb_eIOError, "too long character");
                }
            }

            if (more_char(fptr) == MORE_CHAR_FINISHED) {
                if (fptr->cbuf.len == 0) {
                    clear_readconv(fptr);
                    return Qnil;
                }
                /* return an unit of an incomplete character just before EOF */
                str = rb_enc_str_new(fptr->cbuf.ptr+fptr->cbuf.off, 1, read_enc);
                fptr->cbuf.off += 1;
                fptr->cbuf.len -= 1;
                if (fptr->cbuf.len == 0) clear_readconv(fptr);
                ENC_CODERANGE_SET(str, ENC_CODERANGE_BROKEN);
                return str;
            }
        }
        if (MBCLEN_INVALID_P(r)) {
            r = rb_enc_mbclen(fptr->cbuf.ptr+fptr->cbuf.off,
                              fptr->cbuf.ptr+fptr->cbuf.off+fptr->cbuf.len,
                              read_enc);
            io_shift_cbuf(fptr, r, &str);
            cr = ENC_CODERANGE_BROKEN;
        }
        else {
            io_shift_cbuf(fptr, MBCLEN_CHARFOUND_LEN(r), &str);
            cr = ENC_CODERANGE_VALID;
            if (MBCLEN_CHARFOUND_LEN(r) == 1 && rb_enc_asciicompat(read_enc) &&
                ISASCII(RSTRING_PTR(str)[0])) {
                cr = ENC_CODERANGE_7BIT;
            }
        }
        str = io_enc_str(str, fptr);
        ENC_CODERANGE_SET(str, cr);
        return str;
    }

    NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr);
    if (io_fillbuf(fptr) < 0) {
        return Qnil;
    }
    if (rb_enc_asciicompat(enc) && ISASCII(fptr->rbuf.ptr[fptr->rbuf.off])) {
        str = rb_str_new(fptr->rbuf.ptr+fptr->rbuf.off, 1);
        fptr->rbuf.off += 1;
        fptr->rbuf.len -= 1;
        cr = ENC_CODERANGE_7BIT;
    }
    else {
        r = rb_enc_precise_mbclen(fptr->rbuf.ptr+fptr->rbuf.off, fptr->rbuf.ptr+fptr->rbuf.off+fptr->rbuf.len, enc);
        if (MBCLEN_CHARFOUND_P(r) &&
            (n = MBCLEN_CHARFOUND_LEN(r)) <= fptr->rbuf.len) {
            str = rb_str_new(fptr->rbuf.ptr+fptr->rbuf.off, n);
            fptr->rbuf.off += n;
            fptr->rbuf.len -= n;
            cr = ENC_CODERANGE_VALID;
        }
        else if (MBCLEN_NEEDMORE_P(r)) {
            str = rb_str_new(fptr->rbuf.ptr+fptr->rbuf.off, fptr->rbuf.len);
            fptr->rbuf.len = 0;
          getc_needmore:
            if (io_fillbuf(fptr) != -1) {
                rb_str_cat(str, fptr->rbuf.ptr+fptr->rbuf.off, 1);
                fptr->rbuf.off++;
                fptr->rbuf.len--;
                r = rb_enc_precise_mbclen(RSTRING_PTR(str), RSTRING_PTR(str)+RSTRING_LEN(str), enc);
                if (MBCLEN_NEEDMORE_P(r)) {
                    goto getc_needmore;
                }
                else if (MBCLEN_CHARFOUND_P(r)) {
                    cr = ENC_CODERANGE_VALID;
                }
            }
        }
        else {
            str = rb_str_new(fptr->rbuf.ptr+fptr->rbuf.off, 1);
            fptr->rbuf.off++;
            fptr->rbuf.len--;
        }
    }
    if (!cr) cr = ENC_CODERANGE_BROKEN;
    str = io_enc_str(str, fptr);
    ENC_CODERANGE_SET(str, cr);
    return str;
}

/*
 *  call-seq:
 *    each_char {|c| ... } -> self
 *    each_char            -> enumerator
 *
 *  Calls the given block with each character in the stream; returns +self+.
 *  See {Character IO}[rdoc-ref:IO@Character+IO].
 *
 *    f = File.new('t.rus')
 *    a = []
 *    f.each_char {|c| a << c.ord }
 *    a # => [1090, 1077, 1089, 1090]
 *    f.close
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: IO#each_byte, IO#each_codepoint.
 *
 */

static VALUE
rb_io_each_char(VALUE io)
{
    rb_io_t *fptr;
    rb_encoding *enc;
    VALUE c;

    RETURN_ENUMERATOR(io, 0, 0);
    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);

    enc = io_input_encoding(fptr);
    READ_CHECK(fptr);
    while (!NIL_P(c = io_getc(fptr, enc))) {
        rb_yield(c);
    }
    return io;
}

/*
 *  call-seq:
 *    each_codepoint {|c| ... } -> self
 *    each_codepoint            -> enumerator
 *
 *  Calls the given block with each codepoint in the stream; returns +self+:
 *
 *    f = File.new('t.rus')
 *    a = []
 *    f.each_codepoint {|c| a << c }
 *    a # => [1090, 1077, 1089, 1090]
 *    f.close
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: IO#each_byte, IO#each_char.
 *
 */

static VALUE
rb_io_each_codepoint(VALUE io)
{
    rb_io_t *fptr;
    rb_encoding *enc;
    unsigned int c;
    int r, n;

    RETURN_ENUMERATOR(io, 0, 0);
    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);

    READ_CHECK(fptr);
    if (NEED_READCONV(fptr)) {
        SET_BINARY_MODE(fptr);
        r = 1;		/* no invalid char yet */
        for (;;) {
            make_readconv(fptr, 0);
            for (;;) {
                if (fptr->cbuf.len) {
                    if (fptr->encs.enc)
                        r = rb_enc_precise_mbclen(fptr->cbuf.ptr+fptr->cbuf.off,
                                                  fptr->cbuf.ptr+fptr->cbuf.off+fptr->cbuf.len,
                                                  fptr->encs.enc);
                    else
                        r = ONIGENC_CONSTRUCT_MBCLEN_CHARFOUND(1);
                    if (!MBCLEN_NEEDMORE_P(r))
                        break;
                    if (fptr->cbuf.len == fptr->cbuf.capa) {
                        rb_raise(rb_eIOError, "too long character");
                    }
                }
                if (more_char(fptr) == MORE_CHAR_FINISHED) {
                    clear_readconv(fptr);
                    if (!MBCLEN_CHARFOUND_P(r)) {
                        enc = fptr->encs.enc;
                        goto invalid;
                    }
                    return io;
                }
            }
            if (MBCLEN_INVALID_P(r)) {
                enc = fptr->encs.enc;
                goto invalid;
            }
            n = MBCLEN_CHARFOUND_LEN(r);
            if (fptr->encs.enc) {
                c = rb_enc_codepoint(fptr->cbuf.ptr+fptr->cbuf.off,
                                     fptr->cbuf.ptr+fptr->cbuf.off+fptr->cbuf.len,
                                     fptr->encs.enc);
            }
            else {
                c = (unsigned char)fptr->cbuf.ptr[fptr->cbuf.off];
            }
            fptr->cbuf.off += n;
            fptr->cbuf.len -= n;
            rb_yield(UINT2NUM(c));
            rb_io_check_byte_readable(fptr);
        }
    }
    NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr);
    enc = io_input_encoding(fptr);
    while (io_fillbuf(fptr) >= 0) {
        r = rb_enc_precise_mbclen(fptr->rbuf.ptr+fptr->rbuf.off,
                                  fptr->rbuf.ptr+fptr->rbuf.off+fptr->rbuf.len, enc);
        if (MBCLEN_CHARFOUND_P(r) &&
            (n = MBCLEN_CHARFOUND_LEN(r)) <= fptr->rbuf.len) {
            c = rb_enc_codepoint(fptr->rbuf.ptr+fptr->rbuf.off,
                                 fptr->rbuf.ptr+fptr->rbuf.off+fptr->rbuf.len, enc);
            fptr->rbuf.off += n;
            fptr->rbuf.len -= n;
            rb_yield(UINT2NUM(c));
        }
        else if (MBCLEN_INVALID_P(r)) {
            goto invalid;
        }
        else if (MBCLEN_NEEDMORE_P(r)) {
            char cbuf[8], *p = cbuf;
            int more = MBCLEN_NEEDMORE_LEN(r);
            if (more > numberof(cbuf)) goto invalid;
            more += n = fptr->rbuf.len;
            if (more > numberof(cbuf)) goto invalid;
            while ((n = (int)read_buffered_data(p, more, fptr)) > 0 &&
                   (p += n, (more -= n) > 0)) {
                if (io_fillbuf(fptr) < 0) goto invalid;
                if ((n = fptr->rbuf.len) > more) n = more;
            }
            r = rb_enc_precise_mbclen(cbuf, p, enc);
            if (!MBCLEN_CHARFOUND_P(r)) goto invalid;
            c = rb_enc_codepoint(cbuf, p, enc);
            rb_yield(UINT2NUM(c));
        }
        else {
            continue;
        }
        rb_io_check_byte_readable(fptr);
    }
    return io;

  invalid:
    rb_raise(rb_eArgError, "invalid byte sequence in %s", rb_enc_name(enc));
    UNREACHABLE_RETURN(Qundef);
}

/*
 *  call-seq:
 *    getc -> character or nil
 *
 *  Reads and returns the next 1-character string from the stream;
 *  returns +nil+ if already at end-of-stream.
 *  See {Character IO}[rdoc-ref:IO@Character+IO].
 *
 *    f = File.open('t.txt')
 *    f.getc     # => "F"
 *    f.close
 *    f = File.open('t.rus')
 *    f.getc.ord # => 1090
 *    f.close
 *
 *  Related:  IO#readchar (may raise EOFError).
 *
 */

static VALUE
rb_io_getc(VALUE io)
{
    rb_io_t *fptr;
    rb_encoding *enc;

    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);

    enc = io_input_encoding(fptr);
    READ_CHECK(fptr);
    return io_getc(fptr, enc);
}

/*
 *  call-seq:
 *    readchar -> string
 *
 *  Reads and returns the next 1-character string from the stream;
 *  raises EOFError if already at end-of-stream.
 *  See {Character IO}[rdoc-ref:IO@Character+IO].
 *
 *    f = File.open('t.txt')
 *    f.readchar     # => "F"
 *    f.close
 *    f = File.open('t.rus')
 *    f.readchar.ord # => 1090
 *    f.close
 *
 *  Related:  IO#getc (will not raise EOFError).
 *
 */

static VALUE
rb_io_readchar(VALUE io)
{
    VALUE c = rb_io_getc(io);

    if (NIL_P(c)) {
        rb_eof_error();
    }
    return c;
}

/*
 *  call-seq:
 *    getbyte -> integer or nil
 *
 *  Reads and returns the next byte (in range 0..255) from the stream;
 *  returns +nil+ if already at end-of-stream.
 *  See {Byte IO}[rdoc-ref:IO@Byte+IO].
 *
 *    f = File.open('t.txt')
 *    f.getbyte # => 70
 *    f.close
 *    f = File.open('t.rus')
 *    f.getbyte # => 209
 *    f.close
 *
 *  Related: IO#readbyte (may raise EOFError).
 */

VALUE
rb_io_getbyte(VALUE io)
{
    rb_io_t *fptr;
    int c;

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);
    READ_CHECK(fptr);
    VALUE r_stdout = rb_ractor_stdout();
    if (fptr->fd == 0 && (fptr->mode & FMODE_TTY) && RB_TYPE_P(r_stdout, T_FILE)) {
        rb_io_t *ofp;
        GetOpenFile(r_stdout, ofp);
        if (ofp->mode & FMODE_TTY) {
            rb_io_flush(r_stdout);
        }
    }
    if (io_fillbuf(fptr) < 0) {
        return Qnil;
    }
    fptr->rbuf.off++;
    fptr->rbuf.len--;
    c = (unsigned char)fptr->rbuf.ptr[fptr->rbuf.off-1];
    return INT2FIX(c & 0xff);
}

/*
 *  call-seq:
 *    readbyte -> integer
 *
 *  Reads and returns the next byte (in range 0..255) from the stream;
 *  raises EOFError if already at end-of-stream.
 *  See {Byte IO}[rdoc-ref:IO@Byte+IO].
 *
 *    f = File.open('t.txt')
 *    f.readbyte # => 70
 *    f.close
 *    f = File.open('t.rus')
 *    f.readbyte # => 209
 *    f.close
 *
 *  Related: IO#getbyte (will not raise EOFError).
 *
 */

static VALUE
rb_io_readbyte(VALUE io)
{
    VALUE c = rb_io_getbyte(io);

    if (NIL_P(c)) {
        rb_eof_error();
    }
    return c;
}

/*
 *  call-seq:
 *    ungetbyte(integer) -> nil
 *    ungetbyte(string)  -> nil
 *
 *  Pushes back ("unshifts") the given data onto the stream's buffer,
 *  placing the data so that it is next to be read; returns +nil+.
 *  See {Byte IO}[rdoc-ref:IO@Byte+IO].
 *
 *  Note that:
 *
 *  - Calling the method has no effect with unbuffered reads (such as IO#sysread).
 *  - Calling #rewind on the stream discards the pushed-back data.
 *
 *  When argument +integer+ is given, uses only its low-order byte:
 *
 *    File.write('t.tmp', '012')
 *    f = File.open('t.tmp')
 *    f.ungetbyte(0x41)   # => nil
 *    f.read              # => "A012"
 *    f.rewind
 *    f.ungetbyte(0x4243) # => nil
 *    f.read              # => "C012"
 *    f.close
 *
 *  When argument +string+ is given, uses all bytes:
 *
 *    File.write('t.tmp', '012')
 *    f = File.open('t.tmp')
 *    f.ungetbyte('A')    # => nil
 *    f.read              # => "A012"
 *    f.rewind
 *    f.ungetbyte('BCDE') # => nil
 *    f.read              # => "BCDE012"
 *    f.close
 *
 */

VALUE
rb_io_ungetbyte(VALUE io, VALUE b)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);
    switch (TYPE(b)) {
      case T_NIL:
        return Qnil;
      case T_FIXNUM:
      case T_BIGNUM: ;
        VALUE v = rb_int_modulo(b, INT2FIX(256));
        unsigned char c = NUM2INT(v) & 0xFF;
        b = rb_str_new((const char *)&c, 1);
        break;
      default:
        StringValue(b);
    }
    io_ungetbyte(b, fptr);
    return Qnil;
}

/*
 *  call-seq:
 *    ungetc(integer) -> nil
 *    ungetc(string)  -> nil
 *
 *  Pushes back ("unshifts") the given data onto the stream's buffer,
 *  placing the data so that it is next to be read; returns +nil+.
 *  See {Character IO}[rdoc-ref:IO@Character+IO].
 *
 *  Note that:
 *
 *  - Calling the method has no effect with unbuffered reads (such as IO#sysread).
 *  - Calling #rewind on the stream discards the pushed-back data.
 *
 *  When argument +integer+ is given, interprets the integer as a character:
 *
 *    File.write('t.tmp', '012')
 *    f = File.open('t.tmp')
 *    f.ungetc(0x41)     # => nil
 *    f.read             # => "A012"
 *    f.rewind
 *    f.ungetc(0x0442)   # => nil
 *    f.getc.ord         # => 1090
 *    f.close
 *
 *  When argument +string+ is given, uses all characters:
 *
 *    File.write('t.tmp', '012')
 *    f = File.open('t.tmp')
 *    f.ungetc('A')      # => nil
 *    f.read      # => "A012"
 *    f.rewind
 *    f.ungetc("\u0442\u0435\u0441\u0442") # => nil
 *    f.getc.ord      # => 1090
 *    f.getc.ord      # => 1077
 *    f.getc.ord      # => 1089
 *    f.getc.ord      # => 1090
 *    f.close
 *
 */

VALUE
rb_io_ungetc(VALUE io, VALUE c)
{
    rb_io_t *fptr;
    long len;

    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);
    if (FIXNUM_P(c)) {
        c = rb_enc_uint_chr(FIX2UINT(c), io_read_encoding(fptr));
    }
    else if (RB_BIGNUM_TYPE_P(c)) {
        c = rb_enc_uint_chr(NUM2UINT(c), io_read_encoding(fptr));
    }
    else {
        StringValue(c);
    }
    if (NEED_READCONV(fptr)) {
        SET_BINARY_MODE(fptr);
        len = RSTRING_LEN(c);
#if SIZEOF_LONG > SIZEOF_INT
        if (len > INT_MAX)
            rb_raise(rb_eIOError, "ungetc failed");
#endif
        make_readconv(fptr, (int)len);
        if (fptr->cbuf.capa - fptr->cbuf.len < len)
            rb_raise(rb_eIOError, "ungetc failed");
        if (fptr->cbuf.off < len) {
            MEMMOVE(fptr->cbuf.ptr+fptr->cbuf.capa-fptr->cbuf.len,
                    fptr->cbuf.ptr+fptr->cbuf.off,
                    char, fptr->cbuf.len);
            fptr->cbuf.off = fptr->cbuf.capa-fptr->cbuf.len;
        }
        fptr->cbuf.off -= (int)len;
        fptr->cbuf.len += (int)len;
        MEMMOVE(fptr->cbuf.ptr+fptr->cbuf.off, RSTRING_PTR(c), char, len);
    }
    else {
        NEED_NEWLINE_DECORATOR_ON_READ_CHECK(fptr);
        io_ungetbyte(c, fptr);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    isatty -> true or false
 *
 *  Returns +true+ if the stream is associated with a terminal device (tty),
 *  +false+ otherwise:
 *
 *    f = File.new('t.txt').isatty    #=> false
 *    f.close
 *    f = File.new('/dev/tty').isatty #=> true
 *    f.close
 *
 */

static VALUE
rb_io_isatty(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    return RBOOL(isatty(fptr->fd) != 0);
}

#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(F_SETFD) && defined(FD_CLOEXEC)
/*
 *  call-seq:
 *    close_on_exec? -> true or false
 *
 *  Returns +true+ if the stream will be closed on exec, +false+ otherwise:
 *
 *    f = File.open('t.txt')
 *    f.close_on_exec? # => true
 *    f.close_on_exec = false
 *    f.close_on_exec? # => false
 *    f.close
 *
 */

static VALUE
rb_io_close_on_exec_p(VALUE io)
{
    rb_io_t *fptr;
    VALUE write_io;
    int fd, ret;

    write_io = GetWriteIO(io);
    if (io != write_io) {
        GetOpenFile(write_io, fptr);
        if (fptr && 0 <= (fd = fptr->fd)) {
            if ((ret = fcntl(fd, F_GETFD)) == -1) rb_sys_fail_path(fptr->pathv);
            if (!(ret & FD_CLOEXEC)) return Qfalse;
        }
    }

    GetOpenFile(io, fptr);
    if (fptr && 0 <= (fd = fptr->fd)) {
        if ((ret = fcntl(fd, F_GETFD)) == -1) rb_sys_fail_path(fptr->pathv);
        if (!(ret & FD_CLOEXEC)) return Qfalse;
    }
    return Qtrue;
}
#else
#define rb_io_close_on_exec_p rb_f_notimplement
#endif

#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(F_SETFD) && defined(FD_CLOEXEC)
/*
 *  call-seq:
 *    self.close_on_exec = bool -> true or false
 *
 *  Sets a close-on-exec flag.
 *
 *     f = File.open(File::NULL)
 *     f.close_on_exec = true
 *     system("cat", "/proc/self/fd/#{f.fileno}") # cat: /proc/self/fd/3: No such file or directory
 *     f.closed?                #=> false
 *
 *  Ruby sets close-on-exec flags of all file descriptors by default
 *  since Ruby 2.0.0.
 *  So you don't need to set by yourself.
 *  Also, unsetting a close-on-exec flag can cause file descriptor leak
 *  if another thread use fork() and exec() (via system() method for example).
 *  If you really needs file descriptor inheritance to child process,
 *  use spawn()'s argument such as fd=>fd.
 */

static VALUE
rb_io_set_close_on_exec(VALUE io, VALUE arg)
{
    int flag = RTEST(arg) ? FD_CLOEXEC : 0;
    rb_io_t *fptr;
    VALUE write_io;
    int fd, ret;

    write_io = GetWriteIO(io);
    if (io != write_io) {
        GetOpenFile(write_io, fptr);
        if (fptr && 0 <= (fd = fptr->fd)) {
            if ((ret = fcntl(fptr->fd, F_GETFD)) == -1) rb_sys_fail_path(fptr->pathv);
            if ((ret & FD_CLOEXEC) != flag) {
                ret = (ret & ~FD_CLOEXEC) | flag;
                ret = fcntl(fd, F_SETFD, ret);
                if (ret != 0) rb_sys_fail_path(fptr->pathv);
            }
        }

    }

    GetOpenFile(io, fptr);
    if (fptr && 0 <= (fd = fptr->fd)) {
        if ((ret = fcntl(fd, F_GETFD)) == -1) rb_sys_fail_path(fptr->pathv);
        if ((ret & FD_CLOEXEC) != flag) {
            ret = (ret & ~FD_CLOEXEC) | flag;
            ret = fcntl(fd, F_SETFD, ret);
            if (ret != 0) rb_sys_fail_path(fptr->pathv);
        }
    }
    return Qnil;
}
#else
#define rb_io_set_close_on_exec rb_f_notimplement
#endif

#define RUBY_IO_EXTERNAL_P(f) ((f)->mode & FMODE_EXTERNAL)
#define PREP_STDIO_NAME(f) (RSTRING_PTR((f)->pathv))

static VALUE
finish_writeconv(rb_io_t *fptr, int noalloc)
{
    unsigned char *ds, *dp, *de;
    rb_econv_result_t res;

    if (!fptr->wbuf.ptr) {
        unsigned char buf[1024];

        res = econv_destination_buffer_full;
        while (res == econv_destination_buffer_full) {
            ds = dp = buf;
            de = buf + sizeof(buf);
            res = rb_econv_convert(fptr->writeconv, NULL, NULL, &dp, de, 0);
            while (dp-ds) {
                size_t remaining = dp-ds;
                long result = rb_io_write_memory(fptr, ds, remaining);

                if (result > 0) {
                    ds += result;
                    if ((size_t)result == remaining) break;
                }
                else if (rb_io_maybe_wait_writable(errno, fptr->self, RUBY_IO_TIMEOUT_DEFAULT)) {
                    if (fptr->fd < 0)
                        return noalloc ? Qtrue : rb_exc_new3(rb_eIOError, rb_str_new_cstr(closed_stream));
                }
                else {
                    return noalloc ? Qtrue : INT2NUM(errno);
                }
            }
            if (res == econv_invalid_byte_sequence ||
                res == econv_incomplete_input ||
                res == econv_undefined_conversion) {
                return noalloc ? Qtrue : rb_econv_make_exception(fptr->writeconv);
            }
        }

        return Qnil;
    }

    res = econv_destination_buffer_full;
    while (res == econv_destination_buffer_full) {
        if (fptr->wbuf.len == fptr->wbuf.capa) {
            if (io_fflush(fptr) < 0) {
                return noalloc ? Qtrue : INT2NUM(errno);
            }
        }

        ds = dp = (unsigned char *)fptr->wbuf.ptr + fptr->wbuf.off + fptr->wbuf.len;
        de = (unsigned char *)fptr->wbuf.ptr + fptr->wbuf.capa;
        res = rb_econv_convert(fptr->writeconv, NULL, NULL, &dp, de, 0);
        fptr->wbuf.len += (int)(dp - ds);
        if (res == econv_invalid_byte_sequence ||
            res == econv_incomplete_input ||
            res == econv_undefined_conversion) {
            return noalloc ? Qtrue : rb_econv_make_exception(fptr->writeconv);
        }
    }
    return Qnil;
}

struct finish_writeconv_arg {
    rb_io_t *fptr;
    int noalloc;
};

static VALUE
finish_writeconv_sync(VALUE arg)
{
    struct finish_writeconv_arg *p = (struct finish_writeconv_arg *)arg;
    return finish_writeconv(p->fptr, p->noalloc);
}

static void*
nogvl_close(void *ptr)
{
    int *fd = ptr;

    return (void*)(intptr_t)close(*fd);
}

static int
maygvl_close(int fd, int keepgvl)
{
    if (keepgvl)
        return close(fd);

    /*
     * close() may block for certain file types (NFS, SO_LINGER sockets,
     * inotify), so let other threads run.
     */
    return IO_WITHOUT_GVL_INT(nogvl_close, &fd);
}

static void*
nogvl_fclose(void *ptr)
{
    FILE *file = ptr;

    return (void*)(intptr_t)fclose(file);
}

static int
maygvl_fclose(FILE *file, int keepgvl)
{
    if (keepgvl)
        return fclose(file);

    return IO_WITHOUT_GVL_INT(nogvl_fclose, file);
}

static void free_io_buffer(rb_io_buffer_t *buf);

static void
fptr_finalize_flush(rb_io_t *fptr, int noraise, int keepgvl)
{
    VALUE error = Qnil;
    int fd = fptr->fd;
    FILE *stdio_file = fptr->stdio_file;
    int mode = fptr->mode;

    if (fptr->writeconv) {
        if (!NIL_P(fptr->write_lock) && !noraise) {
            struct finish_writeconv_arg arg;
            arg.fptr = fptr;
            arg.noalloc = noraise;
            error = rb_mutex_synchronize(fptr->write_lock, finish_writeconv_sync, (VALUE)&arg);
        }
        else {
            error = finish_writeconv(fptr, noraise);
        }
    }
    if (fptr->wbuf.len) {
        if (noraise) {
            io_flush_buffer_sync(fptr);
        }
        else {
            if (io_fflush(fptr) < 0 && NIL_P(error)) {
                error = INT2NUM(errno);
            }
        }
    }

    int done = 0;

    if (RUBY_IO_EXTERNAL_P(fptr) || fd <= 2) {
        // Need to keep FILE objects of stdin, stdout and stderr, so we are done:
        done = 1;
    }

    fptr->fd = -1;
    fptr->stdio_file = 0;
    fptr->mode &= ~(FMODE_READABLE|FMODE_WRITABLE);

    // wait for blocking operations to ensure they do not hit EBADF:
    rb_thread_io_close_wait(fptr);

    // Disable for now.
    // if (!done && fd >= 0) {
    //     VALUE scheduler = rb_fiber_scheduler_current();
    //     if (scheduler != Qnil) {
    //         VALUE result = rb_fiber_scheduler_io_close(scheduler, fptr->self);
    //         if (!UNDEF_P(result)) done = 1;
    //     }
    // }

    if (!done && stdio_file) {
        // stdio_file is deallocated anyway even if fclose failed.
        if ((maygvl_fclose(stdio_file, noraise) < 0) && NIL_P(error)) {
            if (!noraise) {
                error = INT2NUM(errno);
            }
        }

        done = 1;
    }

    if (!done && fd >= 0) {
        // fptr->fd may be closed even if close fails. POSIX doesn't specify it.
        // We assumes it is closed.

        keepgvl |= !(mode & FMODE_WRITABLE);
        keepgvl |= noraise;
        if ((maygvl_close(fd, keepgvl) < 0) && NIL_P(error)) {
            if (!noraise) {
                error = INT2NUM(errno);
            }
        }

        done = 1;
    }

    if (!NIL_P(error) && !noraise) {
        if (RB_INTEGER_TYPE_P(error))
            rb_syserr_fail_path(NUM2INT(error), fptr->pathv);
        else
            rb_exc_raise(error);
    }
}

static void
fptr_finalize(rb_io_t *fptr, int noraise)
{
    fptr_finalize_flush(fptr, noraise, FALSE);
    free_io_buffer(&fptr->rbuf);
    free_io_buffer(&fptr->wbuf);
    clear_codeconv(fptr);
}

static void
rb_io_fptr_cleanup(rb_io_t *fptr, int noraise)
{
    if (fptr->finalize) {
        (*fptr->finalize)(fptr, noraise);
    }
    else {
        fptr_finalize(fptr, noraise);
    }
}

static void
free_io_buffer(rb_io_buffer_t *buf)
{
    if (buf->ptr) {
        ruby_sized_xfree(buf->ptr, (size_t)buf->capa);
        buf->ptr = NULL;
    }
}

static void
clear_readconv(rb_io_t *fptr)
{
    if (fptr->readconv) {
        rb_econv_close(fptr->readconv);
        fptr->readconv = NULL;
    }
    free_io_buffer(&fptr->cbuf);
}

static void
clear_writeconv(rb_io_t *fptr)
{
    if (fptr->writeconv) {
        rb_econv_close(fptr->writeconv);
        fptr->writeconv = NULL;
    }
    fptr->writeconv_initialized = 0;
}

static void
clear_codeconv(rb_io_t *fptr)
{
    clear_readconv(fptr);
    clear_writeconv(fptr);
}

static void
rb_io_fptr_cleanup_all(rb_io_t *fptr)
{
    fptr->pathv = Qnil;
    if (0 <= fptr->fd)
        rb_io_fptr_cleanup(fptr, TRUE);
    fptr->write_lock = Qnil;
    free_io_buffer(&fptr->rbuf);
    free_io_buffer(&fptr->wbuf);
    clear_codeconv(fptr);
}

int
rb_io_fptr_finalize(struct rb_io *io)
{
    if (!io) return 0;
    rb_io_fptr_cleanup_all(io);
    free(io);

    return 1;
}

size_t
rb_io_memsize(const rb_io_t *io)
{
    size_t size = sizeof(rb_io_t);
    size += io->rbuf.capa;
    size += io->wbuf.capa;
    size += io->cbuf.capa;
    if (io->readconv) size += rb_econv_memsize(io->readconv);
    if (io->writeconv) size += rb_econv_memsize(io->writeconv);

    struct rb_io_blocking_operation *blocking_operation = 0;

    // Validate the fork generation of the IO object. If the IO object fork generation is different, the list of blocking operations is not valid memory. See `rb_io_blocking_operations` for the exact semantics.
    rb_serial_t fork_generation = GET_VM()->fork_gen;
    if (io->fork_generation == fork_generation) {
        ccan_list_for_each(&io->blocking_operations, blocking_operation, list) {
            size += sizeof(struct rb_io_blocking_operation);
        }
    }

    return size;
}

#ifdef _WIN32
/* keep GVL while closing to prevent crash on Windows */
# define KEEPGVL TRUE
#else
# define KEEPGVL FALSE
#endif

static rb_io_t *
io_close_fptr(VALUE io)
{
    rb_io_t *fptr;
    VALUE write_io;
    rb_io_t *write_fptr;

    write_io = GetWriteIO(io);
    if (io != write_io) {
        write_fptr = RFILE(write_io)->fptr;
        if (write_fptr && 0 <= write_fptr->fd) {
            rb_io_fptr_cleanup(write_fptr, TRUE);
        }
    }

    fptr = RFILE(io)->fptr;
    if (!fptr) return 0;
    if (fptr->fd < 0) return 0;

    if (rb_thread_io_close_interrupt(fptr)) {
        /* calls close(fptr->fd): */
        fptr_finalize_flush(fptr, FALSE, KEEPGVL);
    }
    rb_io_fptr_cleanup(fptr, FALSE);
    return fptr;
}

static void
fptr_waitpid(rb_io_t *fptr, int nohang)
{
    int status;
    if (fptr->pid) {
        rb_last_status_clear();
        rb_waitpid(fptr->pid, &status, nohang ? WNOHANG : 0);
        fptr->pid = 0;
    }
}

VALUE
rb_io_close(VALUE io)
{
    rb_io_t *fptr = io_close_fptr(io);
    if (fptr) fptr_waitpid(fptr, 0);
    return Qnil;
}

/*
 *  call-seq:
 *    close -> nil
 *
 *  Closes the stream for both reading and writing
 *  if open for either or both; returns +nil+.
 *  See {Open and Closed Streams}[rdoc-ref:IO@Open+and+Closed+Streams].
 *
 *  If the stream is open for writing, flushes any buffered writes
 *  to the operating system before closing.
 *
 *  If the stream was opened by IO.popen, sets global variable <tt>$?</tt>
 *  (child exit status).
 *
 *  It is not an error to close an IO object that has already been closed.
 *  It just returns nil.
 *
 *  Example:
 *
 *    IO.popen('ruby', 'r+') do |pipe|
 *      puts pipe.closed?
 *      pipe.close
 *      puts $?
 *      puts pipe.closed?
 *    end
 *
 *  Output:
 *
 *    false
 *    pid 13760 exit 0
 *    true
 *
 *  Related: IO#close_read, IO#close_write, IO#closed?.
 */

static VALUE
rb_io_close_m(VALUE io)
{
    rb_io_t *fptr = rb_io_get_fptr(io);
    if (fptr->fd < 0) {
        return Qnil;
    }
    rb_io_close(io);
    return Qnil;
}

static VALUE
io_call_close(VALUE io)
{
    rb_check_funcall(io, rb_intern("close"), 0, 0);
    return io;
}

static VALUE
ignore_closed_stream(VALUE io, VALUE exc)
{
    enum {mesg_len = sizeof(closed_stream)-1};
    VALUE mesg = rb_attr_get(exc, idMesg);
    if (!RB_TYPE_P(mesg, T_STRING) ||
        RSTRING_LEN(mesg) != mesg_len ||
        memcmp(RSTRING_PTR(mesg), closed_stream, mesg_len)) {
        rb_exc_raise(exc);
    }
    return io;
}

static VALUE
io_close(VALUE io)
{
    VALUE closed = rb_check_funcall(io, rb_intern("closed?"), 0, 0);
    if (!UNDEF_P(closed) && RTEST(closed)) return io;
    rb_rescue2(io_call_close, io, ignore_closed_stream, io,
               rb_eIOError, (VALUE)0);
    return io;
}

/*
 *  call-seq:
 *    closed? -> true or false
 *
 *  Returns +true+ if the stream is closed for both reading and writing,
 *  +false+ otherwise.
 *  See {Open and Closed Streams}[rdoc-ref:IO@Open+and+Closed+Streams].
 *
 *    IO.popen('ruby', 'r+') do |pipe|
 *      puts pipe.closed?
 *      pipe.close_read
 *      puts pipe.closed?
 *      pipe.close_write
 *      puts pipe.closed?
 *    end
 *
 *  Output:
 *
 *    false
 *    false
 *    true
 *
 *  Related: IO#close_read, IO#close_write, IO#close.
 */
VALUE
rb_io_closed_p(VALUE io)
{
    rb_io_t *fptr;
    VALUE write_io;
    rb_io_t *write_fptr;

    write_io = GetWriteIO(io);
    if (io != write_io) {
        write_fptr = RFILE(write_io)->fptr;
        if (write_fptr && 0 <= write_fptr->fd) {
            return Qfalse;
        }
    }

    fptr = rb_io_get_fptr(io);
    return RBOOL(0 > fptr->fd);
}

/*
 *  call-seq:
 *    close_read -> nil
 *
 *  Closes the stream for reading if open for reading;
 *  returns +nil+.
 *  See {Open and Closed Streams}[rdoc-ref:IO@Open+and+Closed+Streams].
 *
 *  If the stream was opened by IO.popen and is also closed for writing,
 *  sets global variable <tt>$?</tt> (child exit status).
 *
 *  Example:
 *
 *    IO.popen('ruby', 'r+') do |pipe|
 *      puts pipe.closed?
 *      pipe.close_write
 *      puts pipe.closed?
 *      pipe.close_read
 *      puts $?
 *      puts pipe.closed?
 *    end
 *
 *  Output:
 *
 *    false
 *    false
 *    pid 14748 exit 0
 *    true
 *
 *  Related: IO#close, IO#close_write, IO#closed?.
 */

static VALUE
rb_io_close_read(VALUE io)
{
    rb_io_t *fptr;
    VALUE write_io;

    fptr = rb_io_get_fptr(rb_io_taint_check(io));
    if (fptr->fd < 0) return Qnil;
    if (is_socket(fptr->fd, fptr->pathv)) {
#ifndef SHUT_RD
# define SHUT_RD 0
#endif
        if (shutdown(fptr->fd, SHUT_RD) < 0)
            rb_sys_fail_path(fptr->pathv);
        fptr->mode &= ~FMODE_READABLE;
        if (!(fptr->mode & FMODE_WRITABLE))
            return rb_io_close(io);
        return Qnil;
    }

    write_io = GetWriteIO(io);
    if (io != write_io) {
        rb_io_t *wfptr;
        wfptr = rb_io_get_fptr(rb_io_taint_check(write_io));
        wfptr->pid = fptr->pid;
        fptr->pid = 0;
        RFILE(io)->fptr = wfptr;
        /* bind to write_io temporarily to get rid of memory/fd leak */
        fptr->tied_io_for_writing = 0;
        RFILE(write_io)->fptr = fptr;
        rb_io_fptr_cleanup(fptr, FALSE);
        /* should not finalize fptr because another thread may be reading it */
        return Qnil;
    }

    if ((fptr->mode & (FMODE_DUPLEX|FMODE_WRITABLE)) == FMODE_WRITABLE) {
        rb_raise(rb_eIOError, "closing non-duplex IO for reading");
    }
    return rb_io_close(io);
}

/*
 *  call-seq:
 *    close_write -> nil
 *
 *  Closes the stream for writing if open for writing;
 *  returns +nil+.
 *  See {Open and Closed Streams}[rdoc-ref:IO@Open+and+Closed+Streams].
 *
 *  Flushes any buffered writes to the operating system before closing.
 *
 *  If the stream was opened by IO.popen and is also closed for reading,
 *  sets global variable <tt>$?</tt> (child exit status).
 *
 *    IO.popen('ruby', 'r+') do |pipe|
 *      puts pipe.closed?
 *      pipe.close_read
 *      puts pipe.closed?
 *      pipe.close_write
 *      puts $?
 *      puts pipe.closed?
 *    end
 *
 *  Output:
 *
 *    false
 *    false
 *    pid 15044 exit 0
 *    true
 *
 *  Related: IO#close, IO#close_read, IO#closed?.
 */

static VALUE
rb_io_close_write(VALUE io)
{
    rb_io_t *fptr;
    VALUE write_io;

    write_io = GetWriteIO(io);
    fptr = rb_io_get_fptr(rb_io_taint_check(write_io));
    if (fptr->fd < 0) return Qnil;
    if (is_socket(fptr->fd, fptr->pathv)) {
#ifndef SHUT_WR
# define SHUT_WR 1
#endif
        if (shutdown(fptr->fd, SHUT_WR) < 0)
            rb_sys_fail_path(fptr->pathv);
        fptr->mode &= ~FMODE_WRITABLE;
        if (!(fptr->mode & FMODE_READABLE))
            return rb_io_close(write_io);
        return Qnil;
    }

    if ((fptr->mode & (FMODE_DUPLEX|FMODE_READABLE)) == FMODE_READABLE) {
        rb_raise(rb_eIOError, "closing non-duplex IO for writing");
    }

    if (io != write_io) {
        fptr = rb_io_get_fptr(rb_io_taint_check(io));
        fptr->tied_io_for_writing = 0;
    }
    rb_io_close(write_io);
    return Qnil;
}

/*
 *  call-seq:
 *    sysseek(offset, whence = IO::SEEK_SET) -> integer
 *
 *  Behaves like IO#seek, except that it:
 *
 *  - Uses low-level system functions.
 *  - Returns the new position.
 *
 */

static VALUE
rb_io_sysseek(int argc, VALUE *argv, VALUE io)
{
    VALUE offset, ptrname;
    int whence = SEEK_SET;
    rb_io_t *fptr;
    rb_off_t pos;

    if (rb_scan_args(argc, argv, "11", &offset, &ptrname) == 2) {
        whence = interpret_seek_whence(ptrname);
    }
    pos = NUM2OFFT(offset);
    GetOpenFile(io, fptr);
    if ((fptr->mode & FMODE_READABLE) &&
        (READ_DATA_BUFFERED(fptr) || READ_CHAR_PENDING(fptr))) {
        rb_raise(rb_eIOError, "sysseek for buffered IO");
    }
    if ((fptr->mode & FMODE_WRITABLE) && fptr->wbuf.len) {
        rb_warn("sysseek for buffered IO");
    }
    errno = 0;
    pos = lseek(fptr->fd, pos, whence);
    if (pos < 0 && errno) rb_sys_fail_path(fptr->pathv);

    return OFFT2NUM(pos);
}

/*
 *  call-seq:
 *    syswrite(object) -> integer
 *
 *  Writes the given +object+ to self, which must be opened for writing (see Modes);
 *  returns the number bytes written.
 *  If +object+ is not a string is converted via method to_s:
 *
 *    f = File.new('t.tmp', 'w')
 *    f.syswrite('foo') # => 3
 *    f.syswrite(30)    # => 2
 *    f.syswrite(:foo)  # => 3
 *    f.close
 *
 *  This methods should not be used with other stream-writer methods.
 *
 */

static VALUE
rb_io_syswrite(VALUE io, VALUE str)
{
    VALUE tmp;
    rb_io_t *fptr;
    long n, len;
    const char *ptr;

    if (!RB_TYPE_P(str, T_STRING))
        str = rb_obj_as_string(str);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    if (fptr->wbuf.len) {
        rb_warn("syswrite for buffered IO");
    }

    tmp = rb_str_tmp_frozen_acquire(str);
    RSTRING_GETMEM(tmp, ptr, len);
    n = rb_io_write_memory(fptr, ptr, len);
    if (n < 0) rb_sys_fail_path(fptr->pathv);
    rb_str_tmp_frozen_release(str, tmp);

    return LONG2FIX(n);
}

/*
 *  call-seq:
 *    sysread(maxlen)             -> string
 *    sysread(maxlen, out_string) -> string
 *
 *  Behaves like IO#readpartial, except that it uses low-level system functions.
 *
 *  This method should not be used with other stream-reader methods.
 *
 */

static VALUE
rb_io_sysread(int argc, VALUE *argv, VALUE io)
{
    VALUE len, str;
    rb_io_t *fptr;
    long n, ilen;
    struct io_internal_read_struct iis;
    int shrinkable;

    rb_scan_args(argc, argv, "11", &len, &str);
    ilen = NUM2LONG(len);

    shrinkable = io_setstrbuf(&str, ilen);
    if (ilen == 0) return str;

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);

    if (READ_DATA_BUFFERED(fptr)) {
        rb_raise(rb_eIOError, "sysread for buffered IO");
    }

    rb_io_check_closed(fptr);

    io_setstrbuf(&str, ilen);
    iis.th = rb_thread_current();
    iis.fptr = fptr;
    iis.nonblock = 0;
    iis.fd = fptr->fd;
    iis.buf = RSTRING_PTR(str);
    iis.capa = ilen;
    iis.timeout = NULL;
    n = io_read_memory_locktmp(str, &iis);

    if (n < 0) {
        rb_sys_fail_path(fptr->pathv);
    }

    io_set_read_length(str, n, shrinkable);

    if (n == 0 && ilen > 0) {
        rb_eof_error();
    }

    return str;
}

struct prdwr_internal_arg {
    struct rb_io *io;
    int fd;
    void *buf;
    size_t count;
    rb_off_t offset;
};

static VALUE
internal_pread_func(void *_arg)
{
    struct prdwr_internal_arg *arg = _arg;

    return (VALUE)pread(arg->fd, arg->buf, arg->count, arg->offset);
}

static VALUE
pread_internal_call(VALUE _arg)
{
    struct prdwr_internal_arg *arg = (struct prdwr_internal_arg *)_arg;

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_pread_memory(scheduler, arg->io->self, arg->offset, arg->buf, arg->count, 0);

        if (!UNDEF_P(result)) {
            return rb_fiber_scheduler_io_result_apply(result);
        }
    }

    return rb_io_blocking_region_wait(arg->io, internal_pread_func, arg, RUBY_IO_READABLE);
}

/*
 *  call-seq:
 *    pread(maxlen, offset)             -> string
 *    pread(maxlen, offset, out_string) -> string
 *
 *  Behaves like IO#readpartial, except that it:
 *
 *  - Reads at the given +offset+ (in bytes).
 *  - Disregards, and does not modify, the stream's position
 *    (see {Position}[rdoc-ref:IO@Position]).
 *  - Bypasses any user space buffering in the stream.
 *
 *  Because this method does not disturb the stream's state
 *  (its position, in particular), +pread+ allows multiple threads and processes
 *  to use the same \IO object for reading at various offsets.
 *
 *    f = File.open('t.txt')
 *    f.read # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *    f.pos  # => 52
 *    # Read 12 bytes at offset 0.
 *    f.pread(12, 0) # => "First line\n"
 *    # Read 9 bytes at offset 8.
 *    f.pread(9, 8)  # => "ne\nSecon"
 *    f.close
 *
 *  Not available on some platforms.
 *
 */
static VALUE
rb_io_pread(int argc, VALUE *argv, VALUE io)
{
    VALUE len, offset, str;
    rb_io_t *fptr;
    ssize_t n;
    struct prdwr_internal_arg arg;
    int shrinkable;

    rb_scan_args(argc, argv, "21", &len, &offset, &str);
    arg.count = NUM2SIZET(len);
    arg.offset = NUM2OFFT(offset);

    shrinkable = io_setstrbuf(&str, (long)arg.count);
    if (arg.count == 0) return str;
    arg.buf = RSTRING_PTR(str);

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);

    arg.io = fptr;
    arg.fd = fptr->fd;
    rb_io_check_closed(fptr);

    rb_str_locktmp(str);
    n = (ssize_t)rb_ensure(pread_internal_call, (VALUE)&arg, rb_str_unlocktmp, str);

    if (n < 0) {
        rb_sys_fail_path(fptr->pathv);
    }
    io_set_read_length(str, n, shrinkable);
    if (n == 0 && arg.count > 0) {
        rb_eof_error();
    }

    return str;
}

static VALUE
internal_pwrite_func(void *_arg)
{
    struct prdwr_internal_arg *arg = _arg;

    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        VALUE result = rb_fiber_scheduler_io_pwrite_memory(scheduler, arg->io->self, arg->offset, arg->buf, arg->count, 0);

        if (!UNDEF_P(result)) {
            return rb_fiber_scheduler_io_result_apply(result);
        }
    }


    return (VALUE)pwrite(arg->fd, arg->buf, arg->count, arg->offset);
}

/*
 *  call-seq:
 *    pwrite(object, offset) -> integer
 *
 *  Behaves like IO#write, except that it:
 *
 *  - Writes at the given +offset+ (in bytes).
 *  - Disregards, and does not modify, the stream's position
 *    (see {Position}[rdoc-ref:IO@Position]).
 *  - Bypasses any user space buffering in the stream.
 *
 *  Because this method does not disturb the stream's state
 *  (its position, in particular), +pwrite+ allows multiple threads and processes
 *  to use the same \IO object for writing at various offsets.
 *
 *    f = File.open('t.tmp', 'w+')
 *    # Write 6 bytes at offset 3.
 *    f.pwrite('ABCDEF', 3) # => 6
 *    f.rewind
 *    f.read # => "\u0000\u0000\u0000ABCDEF"
 *    f.close
 *
 *  Not available on some platforms.
 *
 */
static VALUE
rb_io_pwrite(VALUE io, VALUE str, VALUE offset)
{
    rb_io_t *fptr;
    ssize_t n;
    struct prdwr_internal_arg arg;
    VALUE tmp;

    if (!RB_TYPE_P(str, T_STRING))
        str = rb_obj_as_string(str);

    arg.offset = NUM2OFFT(offset);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    arg.io = fptr;
    arg.fd = fptr->fd;

    tmp = rb_str_tmp_frozen_acquire(str);
    arg.buf = RSTRING_PTR(tmp);
    arg.count = (size_t)RSTRING_LEN(tmp);

    n = (ssize_t)rb_io_blocking_region_wait(fptr, internal_pwrite_func, &arg, RUBY_IO_WRITABLE);
    if (n < 0) rb_sys_fail_path(fptr->pathv);
    rb_str_tmp_frozen_release(str, tmp);

    return SSIZET2NUM(n);
}

VALUE
rb_io_binmode(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (fptr->readconv)
        rb_econv_binmode(fptr->readconv);
    if (fptr->writeconv)
        rb_econv_binmode(fptr->writeconv);
    fptr->mode |= FMODE_BINMODE;
    fptr->mode &= ~FMODE_TEXTMODE;
    fptr->writeconv_pre_ecflags &= ~ECONV_NEWLINE_DECORATOR_MASK;
#ifdef O_BINARY
    if (!fptr->readconv) {
        SET_BINARY_MODE_WITH_SEEK_CUR(fptr);
    }
    else {
        setmode(fptr->fd, O_BINARY);
    }
#endif
    return io;
}

static void
io_ascii8bit_binmode(rb_io_t *fptr)
{
    if (fptr->readconv) {
        rb_econv_close(fptr->readconv);
        fptr->readconv = NULL;
    }
    if (fptr->writeconv) {
        rb_econv_close(fptr->writeconv);
        fptr->writeconv = NULL;
    }
    fptr->mode |= FMODE_BINMODE;
    fptr->mode &= ~FMODE_TEXTMODE;
    SET_BINARY_MODE_WITH_SEEK_CUR(fptr);

    fptr->encs.enc = rb_ascii8bit_encoding();
    fptr->encs.enc2 = NULL;
    fptr->encs.ecflags = 0;
    fptr->encs.ecopts = Qnil;
    clear_codeconv(fptr);
}

VALUE
rb_io_ascii8bit_binmode(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    io_ascii8bit_binmode(fptr);

    return io;
}

/*
 *  call-seq:
 *    binmode -> self
 *
 *  Sets the stream's data mode as binary
 *  (see {Data Mode}[rdoc-ref:File@Data+Mode]).
 *
 *  A stream's data mode may not be changed from binary to text.
 *
 */

static VALUE
rb_io_binmode_m(VALUE io)
{
    VALUE write_io;

    rb_io_ascii8bit_binmode(io);

    write_io = GetWriteIO(io);
    if (write_io != io)
        rb_io_ascii8bit_binmode(write_io);
    return io;
}

/*
 *  call-seq:
 *    binmode? -> true or false
 *
 *  Returns +true+ if the stream is on binary mode, +false+ otherwise.
 *  See {Data Mode}[rdoc-ref:File@Data+Mode].
 *
 */
static VALUE
rb_io_binmode_p(VALUE io)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    return RBOOL(fptr->mode & FMODE_BINMODE);
}

static const char*
rb_io_fmode_modestr(enum rb_io_mode fmode)
{
    if (fmode & FMODE_APPEND) {
        if ((fmode & FMODE_READWRITE) == FMODE_READWRITE) {
            return MODE_BTMODE("a+", "ab+", "at+");
        }
        return MODE_BTMODE("a", "ab", "at");
    }
    switch (fmode & FMODE_READWRITE) {
      default:
        rb_raise(rb_eArgError, "invalid access fmode 0x%x", fmode);
      case FMODE_READABLE:
        return MODE_BTMODE("r", "rb", "rt");
      case FMODE_WRITABLE:
        return MODE_BTXMODE("w", "wb", "wt", "wx", "wbx", "wtx");
      case FMODE_READWRITE:
        if (fmode & FMODE_CREATE) {
            return MODE_BTXMODE("w+", "wb+", "wt+", "w+x", "wb+x", "wt+x");
        }
        return MODE_BTMODE("r+", "rb+", "rt+");
    }
}

static const char bom_prefix[] = "bom|";
static const char utf_prefix[] = "utf-";
enum {bom_prefix_len = (int)sizeof(bom_prefix) - 1};
enum {utf_prefix_len = (int)sizeof(utf_prefix) - 1};

static int
io_encname_bom_p(const char *name, long len)
{
    return len > bom_prefix_len && STRNCASECMP(name, bom_prefix, bom_prefix_len) == 0;
}

enum rb_io_mode
rb_io_modestr_fmode(const char *modestr)
{
    enum rb_io_mode fmode = 0;
    const char *m = modestr, *p = NULL;

    switch (*m++) {
      case 'r':
        fmode |= FMODE_READABLE;
        break;
      case 'w':
        fmode |= FMODE_WRITABLE | FMODE_TRUNC | FMODE_CREATE;
        break;
      case 'a':
        fmode |= FMODE_WRITABLE | FMODE_APPEND | FMODE_CREATE;
        break;
      default:
        goto error;
    }

    while (*m) {
        switch (*m++) {
          case 'b':
            fmode |= FMODE_BINMODE;
            break;
          case 't':
            fmode |= FMODE_TEXTMODE;
            break;
          case '+':
            fmode |= FMODE_READWRITE;
            break;
          case 'x':
            if (modestr[0] != 'w')
                goto error;
            fmode |= FMODE_EXCL;
            break;
          default:
            goto error;
          case ':':
            p = strchr(m, ':');
            if (io_encname_bom_p(m, p ? (long)(p - m) : (long)strlen(m)))
                fmode |= FMODE_SETENC_BY_BOM;
            goto finished;
        }
    }

  finished:
    if ((fmode & FMODE_BINMODE) && (fmode & FMODE_TEXTMODE))
        goto error;

    return fmode;

  error:
    rb_raise(rb_eArgError, "invalid access mode %s", modestr);
    UNREACHABLE_RETURN(Qundef);
}

int
rb_io_oflags_fmode(int oflags)
{
    enum rb_io_mode fmode = 0;

    switch (oflags & O_ACCMODE) {
      case O_RDONLY:
        fmode = FMODE_READABLE;
        break;
      case O_WRONLY:
        fmode = FMODE_WRITABLE;
        break;
      case O_RDWR:
        fmode = FMODE_READWRITE;
        break;
    }

    if (oflags & O_APPEND) {
        fmode |= FMODE_APPEND;
    }
    if (oflags & O_TRUNC) {
        fmode |= FMODE_TRUNC;
    }
    if (oflags & O_CREAT) {
        fmode |= FMODE_CREATE;
    }
    if (oflags & O_EXCL) {
        fmode |= FMODE_EXCL;
    }
#ifdef O_BINARY
    if (oflags & O_BINARY) {
        fmode |= FMODE_BINMODE;
    }
#endif

    return fmode;
}

static int
rb_io_fmode_oflags(enum rb_io_mode fmode)
{
    int oflags = 0;

    switch (fmode & FMODE_READWRITE) {
      case FMODE_READABLE:
        oflags |= O_RDONLY;
        break;
      case FMODE_WRITABLE:
        oflags |= O_WRONLY;
        break;
      case FMODE_READWRITE:
        oflags |= O_RDWR;
        break;
    }

    if (fmode & FMODE_APPEND) {
        oflags |= O_APPEND;
    }
    if (fmode & FMODE_TRUNC) {
        oflags |= O_TRUNC;
    }
    if (fmode & FMODE_CREATE) {
        oflags |= O_CREAT;
    }
    if (fmode & FMODE_EXCL) {
        oflags |= O_EXCL;
    }
#ifdef O_BINARY
    if (fmode & FMODE_BINMODE) {
        oflags |= O_BINARY;
    }
#endif

    return oflags;
}

int
rb_io_modestr_oflags(const char *modestr)
{
    return rb_io_fmode_oflags(rb_io_modestr_fmode(modestr));
}

static const char*
rb_io_oflags_modestr(int oflags)
{
#ifdef O_BINARY
# define MODE_BINARY(a,b) ((oflags & O_BINARY) ? (b) : (a))
#else
# define MODE_BINARY(a,b) (a)
#endif
    int accmode;
    if (oflags & O_EXCL) {
        rb_raise(rb_eArgError, "exclusive access mode is not supported");
    }
    accmode = oflags & (O_RDONLY|O_WRONLY|O_RDWR);
    if (oflags & O_APPEND) {
        if (accmode == O_WRONLY) {
            return MODE_BINARY("a", "ab");
        }
        if (accmode == O_RDWR) {
            return MODE_BINARY("a+", "ab+");
        }
    }
    switch (accmode) {
      default:
        rb_raise(rb_eArgError, "invalid access oflags 0x%x", oflags);
      case O_RDONLY:
        return MODE_BINARY("r", "rb");
      case O_WRONLY:
        return MODE_BINARY("w", "wb");
      case O_RDWR:
        if (oflags & O_TRUNC) {
            return MODE_BINARY("w+", "wb+");
        }
        return MODE_BINARY("r+", "rb+");
    }
}

/*
 * Convert external/internal encodings to enc/enc2
 * NULL => use default encoding
 * Qnil => no encoding specified (internal only)
 */
static void
rb_io_ext_int_to_encs(rb_encoding *ext, rb_encoding *intern, rb_encoding **enc, rb_encoding **enc2, enum rb_io_mode fmode)
{
    int default_ext = 0;

    if (ext == NULL) {
        ext = rb_default_external_encoding();
        default_ext = 1;
    }
    if (rb_is_ascii8bit_enc(ext)) {
        /* If external is ASCII-8BIT, no transcoding */
        intern = NULL;
    }
    else if (intern == NULL) {
        intern = rb_default_internal_encoding();
    }
    if (intern == NULL || intern == (rb_encoding *)Qnil ||
        (!(fmode & FMODE_SETENC_BY_BOM) && (intern == ext))) {
        /* No internal encoding => use external + no transcoding */
        *enc = (default_ext && intern != ext) ? NULL : ext;
        *enc2 = NULL;
    }
    else {
        *enc = intern;
        *enc2 = ext;
    }
}

static void
unsupported_encoding(const char *name, rb_encoding *enc)
{
    rb_enc_warn(enc, "Unsupported encoding %s ignored", name);
}

static void
parse_mode_enc(const char *estr, rb_encoding *estr_enc,
               rb_encoding **enc_p, rb_encoding **enc2_p, enum rb_io_mode *fmode_p)
{
    const char *p;
    char encname[ENCODING_MAXNAMELEN+1];
    int idx, idx2;
    enum rb_io_mode fmode = fmode_p ? *fmode_p : 0;
    rb_encoding *ext_enc, *int_enc;
    long len;

    /* parse estr as "enc" or "enc2:enc" or "enc:-" */

    p = strrchr(estr, ':');
    len = p ? (p++ - estr) : (long)strlen(estr);
    if ((fmode & FMODE_SETENC_BY_BOM) || io_encname_bom_p(estr, len)) {
        estr += bom_prefix_len;
        len -= bom_prefix_len;
        if (!STRNCASECMP(estr, utf_prefix, utf_prefix_len)) {
            fmode |= FMODE_SETENC_BY_BOM;
        }
        else {
            rb_enc_warn(estr_enc, "BOM with non-UTF encoding %s is nonsense", estr);
            fmode &= ~FMODE_SETENC_BY_BOM;
        }
    }
    if (len == 0 || len > ENCODING_MAXNAMELEN) {
        idx = -1;
    }
    else {
        if (p) {
            memcpy(encname, estr, len);
            encname[len] = '\0';
            estr = encname;
        }
        idx = rb_enc_find_index(estr);
    }
    if (fmode_p) *fmode_p = fmode;

    if (idx >= 0)
        ext_enc = rb_enc_from_index(idx);
    else {
        if (idx != -2)
            unsupported_encoding(estr, estr_enc);
        ext_enc = NULL;
    }

    int_enc = NULL;
    if (p) {
        if (*p == '-' && *(p+1) == '\0') {
            /* Special case - "-" => no transcoding */
            int_enc = (rb_encoding *)Qnil;
        }
        else {
            idx2 = rb_enc_find_index(p);
            if (idx2 < 0)
                unsupported_encoding(p, estr_enc);
            else if (!(fmode & FMODE_SETENC_BY_BOM) && (idx2 == idx)) {
                int_enc = (rb_encoding *)Qnil;
            }
            else
                int_enc = rb_enc_from_index(idx2);
        }
    }

    rb_io_ext_int_to_encs(ext_enc, int_enc, enc_p, enc2_p, fmode);
}

int
rb_io_extract_encoding_option(VALUE opt, rb_encoding **enc_p, rb_encoding **enc2_p, enum rb_io_mode *fmode_p)
{
    VALUE encoding=Qnil, extenc=Qundef, intenc=Qundef, tmp;
    int extracted = 0;
    rb_encoding *extencoding = NULL;
    rb_encoding *intencoding = NULL;

    if (!NIL_P(opt)) {
        VALUE v;
        v = rb_hash_lookup2(opt, sym_encoding, Qnil);
        if (v != Qnil) encoding = v;
        v = rb_hash_lookup2(opt, sym_extenc, Qundef);
        if (v != Qnil) extenc = v;
        v = rb_hash_lookup2(opt, sym_intenc, Qundef);
        if (!UNDEF_P(v)) intenc = v;
    }
    if ((!UNDEF_P(extenc) || !UNDEF_P(intenc)) && !NIL_P(encoding)) {
        if (!NIL_P(ruby_verbose)) {
            int idx = rb_to_encoding_index(encoding);
            if (idx >= 0) encoding = rb_enc_from_encoding(rb_enc_from_index(idx));
            rb_warn("Ignoring encoding parameter '%"PRIsVALUE"': %s_encoding is used",
                    encoding, UNDEF_P(extenc) ? "internal" : "external");
        }
        encoding = Qnil;
    }
    if (!UNDEF_P(extenc) && !NIL_P(extenc)) {
        extencoding = rb_to_encoding(extenc);
    }
    if (!UNDEF_P(intenc)) {
        if (NIL_P(intenc)) {
            /* internal_encoding: nil => no transcoding */
            intencoding = (rb_encoding *)Qnil;
        }
        else if (!NIL_P(tmp = rb_check_string_type(intenc))) {
            char *p = StringValueCStr(tmp);

            if (*p == '-' && *(p+1) == '\0') {
                /* Special case - "-" => no transcoding */
                intencoding = (rb_encoding *)Qnil;
            }
            else {
                intencoding = rb_to_encoding(intenc);
            }
        }
        else {
            intencoding = rb_to_encoding(intenc);
        }
        if (extencoding == intencoding) {
            intencoding = (rb_encoding *)Qnil;
        }
    }
    if (!NIL_P(encoding)) {
        extracted = 1;
        if (!NIL_P(tmp = rb_check_string_type(encoding))) {
            parse_mode_enc(StringValueCStr(tmp), rb_enc_get(tmp),
                           enc_p, enc2_p, fmode_p);
        }
        else {
            rb_io_ext_int_to_encs(rb_to_encoding(encoding), NULL, enc_p, enc2_p, 0);
        }
    }
    else if (!UNDEF_P(extenc) || !UNDEF_P(intenc)) {
        extracted = 1;
        rb_io_ext_int_to_encs(extencoding, intencoding, enc_p, enc2_p, 0);
    }
    return extracted;
}

static void
validate_enc_binmode(enum rb_io_mode *fmode_p, int ecflags, rb_encoding *enc, rb_encoding *enc2)
{
    enum rb_io_mode fmode = *fmode_p;

    if ((fmode & FMODE_READABLE) &&
        !enc2 &&
        !(fmode & FMODE_BINMODE) &&
        !rb_enc_asciicompat(enc ? enc : rb_default_external_encoding()))
        rb_raise(rb_eArgError, "ASCII incompatible encoding needs binmode");

    if ((fmode & FMODE_BINMODE) && (ecflags & ECONV_NEWLINE_DECORATOR_MASK)) {
        rb_raise(rb_eArgError, "newline decorator with binary mode");
    }
    if (!(fmode & FMODE_BINMODE) &&
        (DEFAULT_TEXTMODE || (ecflags & ECONV_NEWLINE_DECORATOR_MASK))) {
        fmode |= FMODE_TEXTMODE;
        *fmode_p = fmode;
    }
#if !DEFAULT_TEXTMODE
    else if (!(ecflags & ECONV_NEWLINE_DECORATOR_MASK)) {
        fmode &= ~FMODE_TEXTMODE;
        *fmode_p = fmode;
    }
#endif
}

static void
extract_binmode(VALUE opthash, enum rb_io_mode *fmode)
{
    if (!NIL_P(opthash)) {
        VALUE v;
        v = rb_hash_aref(opthash, sym_textmode);
        if (!NIL_P(v)) {
            if (*fmode & FMODE_TEXTMODE)
                rb_raise(rb_eArgError, "textmode specified twice");
            if (*fmode & FMODE_BINMODE)
                rb_raise(rb_eArgError, "both textmode and binmode specified");
            if (RTEST(v))
                *fmode |= FMODE_TEXTMODE;
        }
        v = rb_hash_aref(opthash, sym_binmode);
        if (!NIL_P(v)) {
            if (*fmode & FMODE_BINMODE)
                rb_raise(rb_eArgError, "binmode specified twice");
            if (*fmode & FMODE_TEXTMODE)
                rb_raise(rb_eArgError, "both textmode and binmode specified");
            if (RTEST(v))
                *fmode |= FMODE_BINMODE;
        }

        if ((*fmode & FMODE_BINMODE) && (*fmode & FMODE_TEXTMODE))
            rb_raise(rb_eArgError, "both textmode and binmode specified");
    }
}

void
rb_io_extract_modeenc(VALUE *vmode_p, VALUE *vperm_p, VALUE opthash,
        int *oflags_p, enum rb_io_mode *fmode_p, struct rb_io_encoding *convconfig_p)
{
    VALUE vmode;
    int oflags;
    enum rb_io_mode fmode;
    rb_encoding *enc, *enc2;
    int ecflags;
    VALUE ecopts;
    int has_enc = 0, has_vmode = 0;
    VALUE intmode;

    vmode = *vmode_p;

    /* Set to defaults */
    rb_io_ext_int_to_encs(NULL, NULL, &enc, &enc2, 0);

  vmode_handle:
    if (NIL_P(vmode)) {
        fmode = FMODE_READABLE;
        oflags = O_RDONLY;
    }
    else if (!NIL_P(intmode = rb_check_to_integer(vmode, "to_int"))) {
        vmode = intmode;
        oflags = NUM2INT(intmode);
        fmode = rb_io_oflags_fmode(oflags);
    }
    else {
        const char *p;

        StringValue(vmode);
        p = StringValueCStr(vmode);
        fmode = rb_io_modestr_fmode(p);
        oflags = rb_io_fmode_oflags(fmode);
        p = strchr(p, ':');
        if (p) {
            has_enc = 1;
            parse_mode_enc(p+1, rb_enc_get(vmode), &enc, &enc2, &fmode);
        }
        else {
            rb_encoding *e;

            e = (fmode & FMODE_BINMODE) ? rb_ascii8bit_encoding() : NULL;
            rb_io_ext_int_to_encs(e, NULL, &enc, &enc2, fmode);
        }
    }

    if (NIL_P(opthash)) {
        ecflags = (fmode & FMODE_READABLE) ?
            MODE_BTMODE(ECONV_DEFAULT_NEWLINE_DECORATOR,
                        0, ECONV_UNIVERSAL_NEWLINE_DECORATOR) : 0;
#ifdef TEXTMODE_NEWLINE_DECORATOR_ON_WRITE
        ecflags |= (fmode & FMODE_WRITABLE) ?
            MODE_BTMODE(TEXTMODE_NEWLINE_DECORATOR_ON_WRITE,
                        0, TEXTMODE_NEWLINE_DECORATOR_ON_WRITE) : 0;
#endif
        SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags);
        ecopts = Qnil;
        if (fmode & FMODE_BINMODE) {
#ifdef O_BINARY
            oflags |= O_BINARY;
#endif
            if (!has_enc)
                rb_io_ext_int_to_encs(rb_ascii8bit_encoding(), NULL, &enc, &enc2, fmode);
        }
#if DEFAULT_TEXTMODE
        else if (NIL_P(vmode)) {
            fmode |= DEFAULT_TEXTMODE;
        }
#endif
    }
    else {
        VALUE v;
        if (!has_vmode) {
            v = rb_hash_aref(opthash, sym_mode);
            if (!NIL_P(v)) {
                if (!NIL_P(vmode)) {
                    rb_raise(rb_eArgError, "mode specified twice");
                }
                has_vmode = 1;
                vmode = v;
                goto vmode_handle;
            }
        }
        v = rb_hash_aref(opthash, sym_flags);
        if (!NIL_P(v)) {
            v = rb_to_int(v);
            oflags |= NUM2INT(v);
            vmode = INT2NUM(oflags);
            fmode = rb_io_oflags_fmode(oflags);
        }
        extract_binmode(opthash, &fmode);
        if (fmode & FMODE_BINMODE) {
#ifdef O_BINARY
            oflags |= O_BINARY;
#endif
            if (!has_enc)
                rb_io_ext_int_to_encs(rb_ascii8bit_encoding(), NULL, &enc, &enc2, fmode);
        }
#if DEFAULT_TEXTMODE
        else if (NIL_P(vmode)) {
            fmode |= DEFAULT_TEXTMODE;
        }
#endif
        v = rb_hash_aref(opthash, sym_perm);
        if (!NIL_P(v)) {
            if (vperm_p) {
                if (!NIL_P(*vperm_p)) {
                    rb_raise(rb_eArgError, "perm specified twice");
                }
                *vperm_p = v;
            }
            else {
                /* perm no use, just ignore */
            }
        }
        ecflags = (fmode & FMODE_READABLE) ?
            MODE_BTMODE(ECONV_DEFAULT_NEWLINE_DECORATOR,
                        0, ECONV_UNIVERSAL_NEWLINE_DECORATOR) : 0;
#ifdef TEXTMODE_NEWLINE_DECORATOR_ON_WRITE
        ecflags |= (fmode & FMODE_WRITABLE) ?
            MODE_BTMODE(TEXTMODE_NEWLINE_DECORATOR_ON_WRITE,
                        0, TEXTMODE_NEWLINE_DECORATOR_ON_WRITE) : 0;
#endif

        if (rb_io_extract_encoding_option(opthash, &enc, &enc2, &fmode)) {
            if (has_enc) {
                rb_raise(rb_eArgError, "encoding specified twice");
            }
        }
        SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags);
        ecflags = rb_econv_prepare_options(opthash, &ecopts, ecflags);
    }

    validate_enc_binmode(&fmode, ecflags, enc, enc2);

    *vmode_p = vmode;

    *oflags_p = oflags;
    *fmode_p = fmode;
    convconfig_p->enc = enc;
    convconfig_p->enc2 = enc2;
    convconfig_p->ecflags = ecflags;
    convconfig_p->ecopts = ecopts;
}

struct sysopen_struct {
    VALUE fname;
    int oflags;
    mode_t perm;
};

static void *
sysopen_func(void *ptr)
{
    const struct sysopen_struct *data = ptr;
    const char *fname = RSTRING_PTR(data->fname);
    return (void *)(VALUE)rb_cloexec_open(fname, data->oflags, data->perm);
}

static inline int
rb_sysopen_internal(struct sysopen_struct *data)
{
    int fd;
    do {
        fd = IO_WITHOUT_GVL_INT(sysopen_func, data);
    } while (fd < 0 && errno == EINTR);
    if (0 <= fd)
        rb_update_max_fd(fd);
    return fd;
}

static int
rb_sysopen(VALUE fname, int oflags, mode_t perm)
{
    int fd = -1;
    struct sysopen_struct data;

    data.fname = rb_str_encode_ospath(fname);
    StringValueCStr(data.fname);
    data.oflags = oflags;
    data.perm = perm;

    TRY_WITH_GC((fd = rb_sysopen_internal(&data)) >= 0) {
        rb_syserr_fail_path(first_errno, fname);
    }
    return fd;
}

static inline FILE *
fdopen_internal(int fd, const char *modestr)
{
    FILE *file;

#if defined(__sun)
    errno = 0;
#endif
    file = fdopen(fd, modestr);
    if (!file) {
#ifdef _WIN32
        if (errno == 0) errno = EINVAL;
#elif defined(__sun)
        if (errno == 0) errno = EMFILE;
#endif
    }
    return file;
}

FILE *
rb_fdopen(int fd, const char *modestr)
{
    FILE *file = 0;

    TRY_WITH_GC((file = fdopen_internal(fd, modestr)) != 0) {
        rb_syserr_fail(first_errno, 0);
    }

    /* xxx: should be _IONBF?  A buffer in FILE may have trouble. */
#ifdef USE_SETVBUF
    if (setvbuf(file, NULL, _IOFBF, 0) != 0)
        rb_warn("setvbuf() can't be honoured (fd=%d)", fd);
#endif
    return file;
}

static int
io_check_tty(rb_io_t *fptr)
{
    int t = isatty(fptr->fd);
    if (t)
        fptr->mode |= FMODE_TTY|FMODE_DUPLEX;
    return t;
}

static VALUE rb_io_internal_encoding(VALUE);
static void io_encoding_set(rb_io_t *, VALUE, VALUE, VALUE);

static int
io_strip_bom(VALUE io)
{
    VALUE b1, b2, b3, b4;
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (!(fptr->mode & FMODE_READABLE)) return 0;
    if (NIL_P(b1 = rb_io_getbyte(io))) return 0;
    switch (b1) {
      case INT2FIX(0xEF):
        if (NIL_P(b2 = rb_io_getbyte(io))) break;
        if (b2 == INT2FIX(0xBB) && !NIL_P(b3 = rb_io_getbyte(io))) {
            if (b3 == INT2FIX(0xBF)) {
                return rb_utf8_encindex();
            }
            rb_io_ungetbyte(io, b3);
        }
        rb_io_ungetbyte(io, b2);
        break;

      case INT2FIX(0xFE):
        if (NIL_P(b2 = rb_io_getbyte(io))) break;
        if (b2 == INT2FIX(0xFF)) {
            return ENCINDEX_UTF_16BE;
        }
        rb_io_ungetbyte(io, b2);
        break;

      case INT2FIX(0xFF):
        if (NIL_P(b2 = rb_io_getbyte(io))) break;
        if (b2 == INT2FIX(0xFE)) {
            b3 = rb_io_getbyte(io);
            if (b3 == INT2FIX(0) && !NIL_P(b4 = rb_io_getbyte(io))) {
                if (b4 == INT2FIX(0)) {
                    return ENCINDEX_UTF_32LE;
                }
                rb_io_ungetbyte(io, b4);
            }
            rb_io_ungetbyte(io, b3);
            return ENCINDEX_UTF_16LE;
        }
        rb_io_ungetbyte(io, b2);
        break;

      case INT2FIX(0):
        if (NIL_P(b2 = rb_io_getbyte(io))) break;
        if (b2 == INT2FIX(0) && !NIL_P(b3 = rb_io_getbyte(io))) {
            if (b3 == INT2FIX(0xFE) && !NIL_P(b4 = rb_io_getbyte(io))) {
                if (b4 == INT2FIX(0xFF)) {
                    return ENCINDEX_UTF_32BE;
                }
                rb_io_ungetbyte(io, b4);
            }
            rb_io_ungetbyte(io, b3);
        }
        rb_io_ungetbyte(io, b2);
        break;
    }
    rb_io_ungetbyte(io, b1);
    return 0;
}

static rb_encoding *
io_set_encoding_by_bom(VALUE io)
{
    int idx = io_strip_bom(io);
    rb_io_t *fptr;
    rb_encoding *extenc = NULL;

    GetOpenFile(io, fptr);
    if (idx) {
        extenc = rb_enc_from_index(idx);
        io_encoding_set(fptr, rb_enc_from_encoding(extenc),
                        rb_io_internal_encoding(io), Qnil);
    }
    else {
        fptr->encs.enc2 = NULL;
    }
    return extenc;
}

static VALUE
rb_file_open_generic(VALUE io, VALUE filename, int oflags, enum rb_io_mode fmode,
                     const struct rb_io_encoding *convconfig, mode_t perm)
{
    VALUE pathv;
    rb_io_t *fptr;
    struct rb_io_encoding cc;
    if (!convconfig) {
        /* Set to default encodings */
        rb_io_ext_int_to_encs(NULL, NULL, &cc.enc, &cc.enc2, fmode);
        cc.ecflags = 0;
        cc.ecopts = Qnil;
        convconfig = &cc;
    }
    validate_enc_binmode(&fmode, convconfig->ecflags,
                         convconfig->enc, convconfig->enc2);

    MakeOpenFile(io, fptr);
    fptr->mode = fmode;
    fptr->encs = *convconfig;
    pathv = rb_str_new_frozen(filename);
#ifdef O_TMPFILE
    if (!(oflags & O_TMPFILE)) {
        fptr->pathv = pathv;
    }
#else
    fptr->pathv = pathv;
#endif
    fptr->fd = rb_sysopen(pathv, oflags, perm);
    io_check_tty(fptr);
    if (fmode & FMODE_SETENC_BY_BOM) io_set_encoding_by_bom(io);

    return io;
}

static VALUE
rb_file_open_internal(VALUE io, VALUE filename, const char *modestr)
{
    enum rb_io_mode fmode = rb_io_modestr_fmode(modestr);
    const char *p = strchr(modestr, ':');
    struct rb_io_encoding convconfig;

    if (p) {
        parse_mode_enc(p+1, rb_usascii_encoding(),
                       &convconfig.enc, &convconfig.enc2, &fmode);
    }
    else {
        rb_encoding *e;
        /* Set to default encodings */

        e = (fmode & FMODE_BINMODE) ? rb_ascii8bit_encoding() : NULL;
        rb_io_ext_int_to_encs(e, NULL, &convconfig.enc, &convconfig.enc2, fmode);
    }

    convconfig.ecflags = (fmode & FMODE_READABLE) ?
        MODE_BTMODE(ECONV_DEFAULT_NEWLINE_DECORATOR,
            0, ECONV_UNIVERSAL_NEWLINE_DECORATOR) : 0;
#ifdef TEXTMODE_NEWLINE_DECORATOR_ON_WRITE
    convconfig.ecflags |= (fmode & FMODE_WRITABLE) ?
        MODE_BTMODE(TEXTMODE_NEWLINE_DECORATOR_ON_WRITE,
            0, TEXTMODE_NEWLINE_DECORATOR_ON_WRITE) : 0;
#endif
    SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(convconfig.enc2, convconfig.ecflags);
    convconfig.ecopts = Qnil;

    return rb_file_open_generic(io, filename,
            rb_io_fmode_oflags(fmode),
            fmode,
            &convconfig,
            0666);
}

VALUE
rb_file_open_str(VALUE fname, const char *modestr)
{
    FilePathValue(fname);
    return rb_file_open_internal(io_alloc(rb_cFile), fname, modestr);
}

VALUE
rb_file_open(const char *fname, const char *modestr)
{
    return rb_file_open_internal(io_alloc(rb_cFile), rb_str_new_cstr(fname), modestr);
}

#if defined(__CYGWIN__) || !defined(HAVE_WORKING_FORK)
static struct pipe_list {
    rb_io_t *fptr;
    struct pipe_list *next;
} *pipe_list;

static void
pipe_add_fptr(rb_io_t *fptr)
{
    struct pipe_list *list;

    list = ALLOC(struct pipe_list);
    list->fptr = fptr;
    list->next = pipe_list;
    pipe_list = list;
}

static void
pipe_del_fptr(rb_io_t *fptr)
{
    struct pipe_list **prev = &pipe_list;
    struct pipe_list *tmp;

    while ((tmp = *prev) != 0) {
        if (tmp->fptr == fptr) {
            *prev = tmp->next;
            free(tmp);
            return;
        }
        prev = &tmp->next;
    }
}

#if defined (_WIN32) || defined(__CYGWIN__)
static void
pipe_atexit(void)
{
    struct pipe_list *list = pipe_list;
    struct pipe_list *tmp;

    while (list) {
        tmp = list->next;
        rb_io_fptr_finalize(list->fptr);
        list = tmp;
    }
}
#endif

static void
pipe_finalize(rb_io_t *fptr, int noraise)
{
#if !defined(HAVE_WORKING_FORK) && !defined(_WIN32)
    int status = 0;
    if (fptr->stdio_file) {
        status = pclose(fptr->stdio_file);
    }
    fptr->fd = -1;
    fptr->stdio_file = 0;
    rb_last_status_set(status, fptr->pid);
#else
    fptr_finalize(fptr, noraise);
#endif
    pipe_del_fptr(fptr);
}
#endif

static void
fptr_copy_finalizer(rb_io_t *fptr, const rb_io_t *orig)
{
#if defined(__CYGWIN__) || !defined(HAVE_WORKING_FORK)
    void (*const old_finalize)(struct rb_io*,int) = fptr->finalize;

    if (old_finalize == orig->finalize) return;
#endif

    fptr->finalize = orig->finalize;

#if defined(__CYGWIN__) || !defined(HAVE_WORKING_FORK)
    if (old_finalize != pipe_finalize) {
        struct pipe_list *list;
        for (list = pipe_list; list; list = list->next) {
            if (list->fptr == fptr) break;
        }
        if (!list) pipe_add_fptr(fptr);
    }
    else {
        pipe_del_fptr(fptr);
    }
#endif
}

void
rb_io_synchronized(rb_io_t *fptr)
{
    rb_io_check_initialized(fptr);
    fptr->mode |= FMODE_SYNC;
}

void
rb_io_unbuffered(rb_io_t *fptr)
{
    rb_io_synchronized(fptr);
}

int
rb_pipe(int *pipes)
{
    int ret;
    TRY_WITH_GC((ret = rb_cloexec_pipe(pipes)) >= 0);
    if (ret == 0) {
        rb_update_max_fd(pipes[0]);
        rb_update_max_fd(pipes[1]);
    }
    return ret;
}

#ifdef _WIN32
#define HAVE_SPAWNV 1
#define spawnv(mode, cmd, args) rb_w32_uaspawn((mode), (cmd), (args))
#define spawn(mode, cmd) rb_w32_uspawn((mode), (cmd), 0)
#endif

#if defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)
struct popen_arg {
    VALUE execarg_obj;
    struct rb_execarg *eargp;
    int modef;
    int pair[2];
    int write_pair[2];
};
#endif

#ifdef HAVE_WORKING_FORK
# ifndef __EMSCRIPTEN__
static void
popen_redirect(struct popen_arg *p)
{
    if ((p->modef & FMODE_READABLE) && (p->modef & FMODE_WRITABLE)) {
        close(p->write_pair[1]);
        if (p->write_pair[0] != 0) {
            dup2(p->write_pair[0], 0);
            close(p->write_pair[0]);
        }
        close(p->pair[0]);
        if (p->pair[1] != 1) {
            dup2(p->pair[1], 1);
            close(p->pair[1]);
        }
    }
    else if (p->modef & FMODE_READABLE) {
        close(p->pair[0]);
        if (p->pair[1] != 1) {
            dup2(p->pair[1], 1);
            close(p->pair[1]);
        }
    }
    else {
        close(p->pair[1]);
        if (p->pair[0] != 0) {
            dup2(p->pair[0], 0);
            close(p->pair[0]);
        }
    }
}
# endif

#if defined(__linux__)
/* Linux /proc/self/status contains a line: "FDSize:\t<nnn>\n"
 * Since /proc may not be available, linux_get_maxfd is just a hint.
 * This function, linux_get_maxfd, must be async-signal-safe.
 * I.e. opendir() is not usable.
 *
 * Note that memchr() and memcmp is *not* async-signal-safe in POSIX.
 * However they are easy to re-implement in async-signal-safe manner.
 * (Also note that there is missing/memcmp.c.)
 */
static int
linux_get_maxfd(void)
{
    int fd;
    char buf[4096], *p, *np, *e;
    ssize_t ss;
    fd = rb_cloexec_open("/proc/self/status", O_RDONLY|O_NOCTTY, 0);
    if (fd < 0) return fd;
    ss = read(fd, buf, sizeof(buf));
    if (ss < 0) goto err;
    p = buf;
    e = buf + ss;
    while ((int)sizeof("FDSize:\t0\n")-1 <= e-p &&
           (np = memchr(p, '\n', e-p)) != NULL) {
        if (memcmp(p, "FDSize:", sizeof("FDSize:")-1) == 0) {
            int fdsize;
            p += sizeof("FDSize:")-1;
            *np = '\0';
            fdsize = (int)ruby_strtoul(p, (char **)NULL, 10);
            close(fd);
            return fdsize;
        }
        p = np+1;
    }
    /* fall through */

  err:
    close(fd);
    return (int)ss;
}
#endif

/* This function should be async-signal-safe. */
void
rb_close_before_exec(int lowfd, int maxhint, VALUE noclose_fds)
{
#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(F_SETFD) && defined(FD_CLOEXEC)
    int fd, ret;
    int max = (int)max_file_descriptor;
# ifdef F_MAXFD
    /* F_MAXFD is available since NetBSD 2.0. */
    ret = fcntl(0, F_MAXFD); /* async-signal-safe */
    if (ret != -1)
        maxhint = max = ret;
# elif defined(__linux__)
    ret = linux_get_maxfd();
    if (maxhint < ret)
        maxhint = ret;
    /* maxhint = max = ret; if (ret == -1) abort(); // test */
# endif
    if (max < maxhint)
        max = maxhint;
    for (fd = lowfd; fd <= max; fd++) {
        if (!NIL_P(noclose_fds) &&
            RTEST(rb_hash_lookup(noclose_fds, INT2FIX(fd)))) /* async-signal-safe */
            continue;
        ret = fcntl(fd, F_GETFD); /* async-signal-safe */
        if (ret != -1 && !(ret & FD_CLOEXEC)) {
            fcntl(fd, F_SETFD, ret|FD_CLOEXEC); /* async-signal-safe */
        }
# define CONTIGUOUS_CLOSED_FDS 20
        if (ret != -1) {
            if (max < fd + CONTIGUOUS_CLOSED_FDS)
                max = fd + CONTIGUOUS_CLOSED_FDS;
        }
    }
#endif
}

# ifndef __EMSCRIPTEN__
static int
popen_exec(void *pp, char *errmsg, size_t errmsg_len)
{
    struct popen_arg *p = (struct popen_arg*)pp;

    return rb_exec_async_signal_safe(p->eargp, errmsg, errmsg_len);
}
# endif
#endif

#if (defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)) && !defined __EMSCRIPTEN__
static VALUE
rb_execarg_fixup_v(VALUE execarg_obj)
{
    rb_execarg_parent_start(execarg_obj);
    return Qnil;
}
#else
char *rb_execarg_commandline(const struct rb_execarg *eargp, VALUE *prog);
#endif

#ifndef __EMSCRIPTEN__
static VALUE
pipe_open(VALUE execarg_obj, const char *modestr, enum rb_io_mode fmode,
          const struct rb_io_encoding *convconfig)
{
    struct rb_execarg *eargp = NIL_P(execarg_obj) ? NULL : rb_execarg_get(execarg_obj);
    VALUE prog = eargp ? (eargp->use_shell ? eargp->invoke.sh.shell_script : eargp->invoke.cmd.command_name) : Qfalse ;
    rb_pid_t pid = 0;
    rb_io_t *fptr;
    VALUE port;
    rb_io_t *write_fptr;
    VALUE write_port;
#if defined(HAVE_WORKING_FORK)
    int status;
    char errmsg[80] = { '\0' };
#endif
#if defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)
    int state;
    struct popen_arg arg;
#endif
    int e = 0;
#if defined(HAVE_SPAWNV)
# if defined(HAVE_SPAWNVE)
#   define DO_SPAWN(cmd, args, envp) ((args) ? \
                                      spawnve(P_NOWAIT, (cmd), (args), (envp)) : \
                                      spawne(P_NOWAIT, (cmd), (envp)))
# else
#   define DO_SPAWN(cmd, args, envp) ((args) ? \
                                      spawnv(P_NOWAIT, (cmd), (args)) : \
                                      spawn(P_NOWAIT, (cmd)))
# endif
# if !defined(HAVE_WORKING_FORK)
    char **args = NULL;
#   if defined(HAVE_SPAWNVE)
    char **envp = NULL;
#   endif
# endif
#endif
#if !defined(HAVE_WORKING_FORK)
    struct rb_execarg sarg, *sargp = &sarg;
#endif
    FILE *fp = 0;
    int fd = -1;
    int write_fd = -1;
#if !defined(HAVE_WORKING_FORK)
    const char *cmd = 0;

    if (prog)
        cmd = StringValueCStr(prog);
#endif

#if defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)
    arg.execarg_obj = execarg_obj;
    arg.eargp = eargp;
    arg.modef = fmode;
    arg.pair[0] = arg.pair[1] = -1;
    arg.write_pair[0] = arg.write_pair[1] = -1;
# if !defined(HAVE_WORKING_FORK)
    if (eargp && !eargp->use_shell) {
        args = ARGVSTR2ARGV(eargp->invoke.cmd.argv_str);
    }
# endif
    switch (fmode & (FMODE_READABLE|FMODE_WRITABLE)) {
      case FMODE_READABLE|FMODE_WRITABLE:
        if (rb_pipe(arg.write_pair) < 0)
            rb_sys_fail_str(prog);
        if (rb_pipe(arg.pair) < 0) {
            e = errno;
            close(arg.write_pair[0]);
            close(arg.write_pair[1]);
            rb_syserr_fail_str(e, prog);
        }
        if (eargp) {
            rb_execarg_addopt(execarg_obj, INT2FIX(0), INT2FIX(arg.write_pair[0]));
            rb_execarg_addopt(execarg_obj, INT2FIX(1), INT2FIX(arg.pair[1]));
        }
        break;
      case FMODE_READABLE:
        if (rb_pipe(arg.pair) < 0)
            rb_sys_fail_str(prog);
        if (eargp)
            rb_execarg_addopt(execarg_obj, INT2FIX(1), INT2FIX(arg.pair[1]));
        break;
      case FMODE_WRITABLE:
        if (rb_pipe(arg.pair) < 0)
            rb_sys_fail_str(prog);
        if (eargp)
            rb_execarg_addopt(execarg_obj, INT2FIX(0), INT2FIX(arg.pair[0]));
        break;
      default:
        rb_sys_fail_str(prog);
    }
    if (!NIL_P(execarg_obj)) {
        rb_protect(rb_execarg_fixup_v, execarg_obj, &state);
        if (state) {
            if (0 <= arg.write_pair[0]) close(arg.write_pair[0]);
            if (0 <= arg.write_pair[1]) close(arg.write_pair[1]);
            if (0 <= arg.pair[0]) close(arg.pair[0]);
            if (0 <= arg.pair[1]) close(arg.pair[1]);
            rb_execarg_parent_end(execarg_obj);
            rb_jump_tag(state);
        }

# if defined(HAVE_WORKING_FORK)
        pid = rb_fork_async_signal_safe(&status, popen_exec, &arg, arg.eargp->redirect_fds, errmsg, sizeof(errmsg));
# else
        rb_execarg_run_options(eargp, sargp, NULL, 0);
#   if defined(HAVE_SPAWNVE)
        if (eargp->envp_str) envp = (char **)RSTRING_PTR(eargp->envp_str);
#   endif
        while ((pid = DO_SPAWN(cmd, args, envp)) < 0) {
            /* exec failed */
            switch (e = errno) {
              case EAGAIN:
#   if EWOULDBLOCK != EAGAIN
              case EWOULDBLOCK:
#   endif
                rb_thread_sleep(1);
                continue;
            }
            break;
        }
        if (eargp)
            rb_execarg_run_options(sargp, NULL, NULL, 0);
# endif
        rb_execarg_parent_end(execarg_obj);
    }
    else {
# if defined(HAVE_WORKING_FORK)
        pid = rb_call_proc__fork();
        if (pid == 0) {		/* child */
            popen_redirect(&arg);
            rb_io_synchronized(RFILE(orig_stdout)->fptr);
            rb_io_synchronized(RFILE(orig_stderr)->fptr);
            return Qnil;
        }
# else
        rb_notimplement();
# endif
    }

    /* parent */
    if (pid < 0) {
# if defined(HAVE_WORKING_FORK)
        e = errno;
# endif
        close(arg.pair[0]);
        close(arg.pair[1]);
        if ((fmode & (FMODE_READABLE|FMODE_WRITABLE)) == (FMODE_READABLE|FMODE_WRITABLE)) {
            close(arg.write_pair[0]);
            close(arg.write_pair[1]);
        }
# if defined(HAVE_WORKING_FORK)
        if (errmsg[0])
            rb_syserr_fail(e, errmsg);
# endif
        rb_syserr_fail_str(e, prog);
    }
    if ((fmode & FMODE_READABLE) && (fmode & FMODE_WRITABLE)) {
        close(arg.pair[1]);
        fd = arg.pair[0];
        close(arg.write_pair[0]);
        write_fd = arg.write_pair[1];
    }
    else if (fmode & FMODE_READABLE) {
        close(arg.pair[1]);
        fd = arg.pair[0];
    }
    else {
        close(arg.pair[0]);
        fd = arg.pair[1];
    }
#else
    cmd = rb_execarg_commandline(eargp, &prog);
    if (!NIL_P(execarg_obj)) {
        rb_execarg_parent_start(execarg_obj);
        rb_execarg_run_options(eargp, sargp, NULL, 0);
    }
    fp = popen(cmd, modestr);
    e = errno;
    if (eargp) {
        rb_execarg_parent_end(execarg_obj);
        rb_execarg_run_options(sargp, NULL, NULL, 0);
    }
    if (!fp) rb_syserr_fail_path(e, prog);
    fd = fileno(fp);
#endif

    port = io_alloc(rb_cIO);
    MakeOpenFile(port, fptr);
    fptr->fd = fd;
    fptr->stdio_file = fp;
    fptr->mode = fmode | FMODE_SYNC|FMODE_DUPLEX;
    if (convconfig) {
        fptr->encs = *convconfig;
#if RUBY_CRLF_ENVIRONMENT
        if (fptr->encs.ecflags & ECONV_DEFAULT_NEWLINE_DECORATOR) {
            fptr->encs.ecflags |= ECONV_UNIVERSAL_NEWLINE_DECORATOR;
        }
#endif
    }
    else {
        if (NEED_NEWLINE_DECORATOR_ON_READ(fptr)) {
            fptr->encs.ecflags |= ECONV_UNIVERSAL_NEWLINE_DECORATOR;
        }
#ifdef TEXTMODE_NEWLINE_DECORATOR_ON_WRITE
        if (NEED_NEWLINE_DECORATOR_ON_WRITE(fptr)) {
            fptr->encs.ecflags |= TEXTMODE_NEWLINE_DECORATOR_ON_WRITE;
        }
#endif
    }
    fptr->pid = pid;

    if (0 <= write_fd) {
        write_port = io_alloc(rb_cIO);
        MakeOpenFile(write_port, write_fptr);
        write_fptr->fd = write_fd;
        write_fptr->mode = (fmode & ~FMODE_READABLE)| FMODE_SYNC|FMODE_DUPLEX;
        fptr->mode &= ~FMODE_WRITABLE;
        fptr->tied_io_for_writing = write_port;
        rb_ivar_set(port, rb_intern("@tied_io_for_writing"), write_port);
    }

#if defined (__CYGWIN__) || !defined(HAVE_WORKING_FORK)
    fptr->finalize = pipe_finalize;
    pipe_add_fptr(fptr);
#endif
    return port;
}
#else
static VALUE
pipe_open(VALUE execarg_obj, const char *modestr, enum rb_io_mode fmode,
          const struct rb_io_encoding *convconfig)
{
    rb_raise(rb_eNotImpError, "popen() is not available");
}
#endif

static int
is_popen_fork(VALUE prog)
{
    if (RSTRING_LEN(prog) == 1 && RSTRING_PTR(prog)[0] == '-') {
#if !defined(HAVE_WORKING_FORK)
        rb_raise(rb_eNotImpError,
                 "fork() function is unimplemented on this machine");
#else
        return TRUE;
#endif
    }
    return FALSE;
}

static VALUE
pipe_open_s(VALUE prog, const char *modestr, enum rb_io_mode fmode,
            const struct rb_io_encoding *convconfig)
{
    int argc = 1;
    VALUE *argv = &prog;
    VALUE execarg_obj = Qnil;

    if (!is_popen_fork(prog))
        execarg_obj = rb_execarg_new(argc, argv, TRUE, FALSE);
    return pipe_open(execarg_obj, modestr, fmode, convconfig);
}

static VALUE
pipe_close(VALUE io)
{
    rb_io_t *fptr = io_close_fptr(io);
    if (fptr) {
        fptr_waitpid(fptr, rb_thread_to_be_killed(rb_thread_current()));
    }
    return Qnil;
}

static VALUE popen_finish(VALUE port, VALUE klass);

/*
 *  call-seq:
 *    IO.popen(env = {}, cmd, mode = 'r', **opts) -> io
 *    IO.popen(env = {}, cmd, mode = 'r', **opts) {|io| ... } -> object
 *
 *  Executes the given command +cmd+ as a subprocess
 *  whose $stdin and $stdout are connected to a new stream +io+.
 *
 *  This method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  If no block is given, returns the new stream,
 *  which depending on given +mode+ may be open for reading, writing, or both.
 *  The stream should be explicitly closed (eventually) to avoid resource leaks.
 *
 *  If a block is given, the stream is passed to the block
 *  (again, open for reading, writing, or both);
 *  when the block exits, the stream is closed,
 *  and the block's value is assigned to global variable <tt>$?</tt> and returned.
 *
 *  Optional argument +mode+ may be any valid \IO mode.
 *  See {Access Modes}[rdoc-ref:File@Access+Modes].
 *
 *  Required argument +cmd+ determines which of the following occurs:
 *
 *  - The process forks.
 *  - A specified program runs in a shell.
 *  - A specified program runs with specified arguments.
 *  - A specified program runs with specified arguments and a specified +argv0+.
 *
 *  Each of these is detailed below.
 *
 *  The optional hash argument +env+ specifies name/value pairs that are to be added
 *  to the environment variables for the subprocess:
 *
 *    IO.popen({'FOO' => 'bar'}, 'ruby', 'r+') do |pipe|
 *      pipe.puts 'puts ENV["FOO"]'
 *      pipe.close_write
 *      pipe.gets
 *    end => "bar\n"
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *  - Options for Kernel#spawn.
 *
 *  <b>Forked Process</b>
 *
 *  When argument +cmd+ is the 1-character string <tt>'-'</tt>, causes the process to fork:
 *    IO.popen('-') do |pipe|
 *      if pipe
 *        $stderr.puts "In parent, child pid is #{pipe.pid}\n"
 *      else
 *        $stderr.puts "In child, pid is #{$$}\n"
 *      end
 *    end
 *
 *  Output:
 *
 *    In parent, child pid is 26253
 *    In child, pid is 26253
 *
 *  Note that this is not supported on all platforms.
 *
 *  <b>Shell Subprocess</b>
 *
 *  When argument +cmd+ is a single string (but not <tt>'-'</tt>),
 *  the program named +cmd+ is run as a shell command:
 *
 *    IO.popen('uname') do |pipe|
 *      pipe.readlines
 *    end
 *
 *  Output:
 *
 *    ["Linux\n"]
 *
 *  Another example:
 *
 *    IO.popen('/bin/sh', 'r+') do |pipe|
 *      pipe.puts('ls')
 *      pipe.close_write
 *      $stderr.puts pipe.readlines.size
 *    end
 *
 *  Output:
 *
 *    213
 *
 *  <b>Program Subprocess</b>
 *
 *  When argument +cmd+ is an array of strings,
 *  the program named <tt>cmd[0]</tt> is run with all elements of +cmd+ as its arguments:
 *
 *    IO.popen(['du', '..', '.']) do |pipe|
 *      $stderr.puts pipe.readlines.size
 *    end
 *
 *  Output:
 *
 *    1111
 *
 *  <b>Program Subprocess with <tt>argv0</tt></b>
 *
 *  When argument +cmd+ is an array whose first element is a 2-element string array
 *  and whose remaining elements (if any) are strings:
 *
 *  - <tt>cmd[0][0]</tt> (the first string in the nested array) is the name of a program that is run.
 *  - <tt>cmd[0][1]</tt> (the second string in the nested array) is set as the program's <tt>argv[0]</tt>.
 *  - <tt>cmd[1..-1]</tt> (the strings in the outer array) are the program's arguments.
 *
 *  Example (sets <tt>$0</tt> to 'foo'):
 *
 *    IO.popen([['/bin/sh', 'foo'], '-c', 'echo $0']).read # => "foo\n"
 *
 *  <b>Some Special Examples</b>
 *
 *    # Set IO encoding.
 *    IO.popen("nkf -e filename", :external_encoding=>"EUC-JP") {|nkf_io|
 *      euc_jp_string = nkf_io.read
 *    }
 *
 *    # Merge standard output and standard error using Kernel#spawn option. See Kernel#spawn.
 *    IO.popen(["ls", "/", :err=>[:child, :out]]) do |io|
 *      ls_result_with_error = io.read
 *    end
 *
 *    # Use mixture of spawn options and IO options.
 *    IO.popen(["ls", "/"], :err=>[:child, :out]) do |io|
 *      ls_result_with_error = io.read
 *    end
 *
 *     f = IO.popen("uname")
 *     p f.readlines
 *     f.close
 *     puts "Parent is #{Process.pid}"
 *     IO.popen("date") {|f| puts f.gets }
 *     IO.popen("-") {|f| $stderr.puts "#{Process.pid} is here, f is #{f.inspect}"}
 *     p $?
 *     IO.popen(%w"sed -e s|^|<foo>| -e s&$&;zot;&", "r+") {|f|
 *       f.puts "bar"; f.close_write; puts f.gets
 *     }
 *
 *  Output (from last section):
 *
 *     ["Linux\n"]
 *     Parent is 21346
 *     Thu Jan 15 22:41:19 JST 2009
 *     21346 is here, f is #<IO:fd 3>
 *     21352 is here, f is nil
 *     #<Process::Status: pid 21352 exit 0>
 *     <foo>bar;zot;
 *
 *  Raises exceptions that IO.pipe and Kernel.spawn raise.
 *
 */

static VALUE
rb_io_s_popen(int argc, VALUE *argv, VALUE klass)
{
    VALUE pname, pmode = Qnil, opt = Qnil, env = Qnil;

    if (argc > 1 && !NIL_P(opt = rb_check_hash_type(argv[argc-1]))) --argc;
    if (argc > 1 && !NIL_P(env = rb_check_hash_type(argv[0]))) --argc, ++argv;
    switch (argc) {
      case 2:
        pmode = argv[1];
      case 1:
        pname = argv[0];
        break;
      default:
        {
            int ex = !NIL_P(opt);
            rb_error_arity(argc + ex, 1 + ex, 2 + ex);
        }
    }
    return popen_finish(rb_io_popen(pname, pmode, env, opt), klass);
}

VALUE
rb_io_popen(VALUE pname, VALUE pmode, VALUE env, VALUE opt)
{
    const char *modestr;
    VALUE tmp, execarg_obj = Qnil;
    int oflags;
    enum rb_io_mode fmode;
    struct rb_io_encoding convconfig;

    tmp = rb_check_array_type(pname);
    if (!NIL_P(tmp)) {
        long len = RARRAY_LEN(tmp);
#if SIZEOF_LONG > SIZEOF_INT
        if (len > INT_MAX) {
            rb_raise(rb_eArgError, "too many arguments");
        }
#endif
        execarg_obj = rb_execarg_new((int)len, RARRAY_CONST_PTR(tmp), FALSE, FALSE);
        RB_GC_GUARD(tmp);
    }
    else {
        StringValue(pname);
        execarg_obj = Qnil;
        if (!is_popen_fork(pname))
            execarg_obj = rb_execarg_new(1, &pname, TRUE, FALSE);
    }
    if (!NIL_P(execarg_obj)) {
        if (!NIL_P(opt))
            opt = rb_execarg_extract_options(execarg_obj, opt);
        if (!NIL_P(env))
            rb_execarg_setenv(execarg_obj, env);
    }
    rb_io_extract_modeenc(&pmode, 0, opt, &oflags, &fmode, &convconfig);
    modestr = rb_io_oflags_modestr(oflags);

    return pipe_open(execarg_obj, modestr, fmode, &convconfig);
}

static VALUE
popen_finish(VALUE port, VALUE klass)
{
    if (NIL_P(port)) {
        /* child */
        if (rb_block_given_p()) {
            rb_protect(rb_yield, Qnil, NULL);
            rb_io_flush(rb_ractor_stdout());
            rb_io_flush(rb_ractor_stderr());
            _exit(0);
        }
        return Qnil;
    }
    RBASIC_SET_CLASS(port, klass);
    if (rb_block_given_p()) {
        return rb_ensure(rb_yield, port, pipe_close, port);
    }
    return port;
}

#if defined(HAVE_WORKING_FORK) && !defined(__EMSCRIPTEN__)
struct popen_writer_arg {
    char *const *argv;
    struct popen_arg popen;
};

static int
exec_popen_writer(void *arg, char *errmsg, size_t buflen)
{
    struct popen_writer_arg *pw = arg;
    pw->popen.modef = FMODE_WRITABLE;
    popen_redirect(&pw->popen);
    execv(pw->argv[0], pw->argv);
    strlcpy(errmsg, strerror(errno), buflen);
    return -1;
}
#endif

FILE *
ruby_popen_writer(char *const *argv, rb_pid_t *pid)
{
#if (defined(HAVE_WORKING_FORK) && !defined(__EMSCRIPTEN__)) || defined(_WIN32)
# ifdef HAVE_WORKING_FORK
    struct popen_writer_arg pw;
    int *const write_pair = pw.popen.pair;
# else
    int write_pair[2];
# endif

    int result = rb_cloexec_pipe(write_pair);
    *pid = -1;
    if (result == 0) {
# ifdef HAVE_WORKING_FORK
        pw.argv = argv;
        int status;
        char errmsg[80] = {'\0'};
        *pid = rb_fork_async_signal_safe(&status, exec_popen_writer, &pw, Qnil, errmsg, sizeof(errmsg));
# else
        *pid = rb_w32_uspawn_process(P_NOWAIT, argv[0], argv, write_pair[0], -1, -1, 0);
        const char *errmsg = (*pid < 0) ? strerror(errno) : NULL;
# endif
        close(write_pair[0]);
        if (*pid < 0) {
            close(write_pair[1]);
            fprintf(stderr, "ruby_popen_writer(%s): %s\n", argv[0], errmsg);
        }
        else {
            return fdopen(write_pair[1], "w");
        }
    }
#endif
    return NULL;
}

static VALUE
rb_open_file(VALUE io, VALUE fname, VALUE vmode, VALUE vperm, VALUE opt)
{
    int oflags;
    enum rb_io_mode fmode;
    struct rb_io_encoding convconfig;
    mode_t perm;

    FilePathValue(fname);

    rb_io_extract_modeenc(&vmode, &vperm, opt, &oflags, &fmode, &convconfig);
    perm = NIL_P(vperm) ? 0666 : NUM2MODET(vperm);

    rb_file_open_generic(io, fname, oflags, fmode, &convconfig, perm);

    return io;
}

/*
 *  Document-method: File::open
 *
 *  call-seq:
 *    File.open(path, mode = 'r', perm = 0666, **opts) -> file
 *    File.open(path, mode = 'r', perm = 0666, **opts) {|f| ... } -> object
 *
 *  Creates a new File object, via File.new with the given arguments.
 *
 *  With no block given, returns the File object.
 *
 *  With a block given, calls the block with the File object
 *  and returns the block's value.
 *
 */

/*
 *  Document-method: IO::open
 *
 *  call-seq:
 *    IO.open(fd, mode = 'r', **opts)             -> io
 *    IO.open(fd, mode = 'r', **opts) {|io| ... } -> object
 *
 *  Creates a new \IO object, via IO.new with the given arguments.
 *
 *  With no block given, returns the \IO object.
 *
 *  With a block given, calls the block with the \IO object
 *  and returns the block's value.
 *
 */

static VALUE
rb_io_s_open(int argc, VALUE *argv, VALUE klass)
{
    VALUE io = rb_class_new_instance_kw(argc, argv, klass, RB_PASS_CALLED_KEYWORDS);

    if (rb_block_given_p()) {
        return rb_ensure(rb_yield, io, io_close, io);
    }

    return io;
}

/*
 *  call-seq:
 *    IO.sysopen(path, mode = 'r', perm = 0666) -> integer
 *
 *  Opens the file at the given path with the given mode and permissions;
 *  returns the integer file descriptor.
 *
 *  If the file is to be readable, it must exist;
 *  if the file is to be writable and does not exist,
 *  it is created with the given permissions:
 *
 *    File.write('t.tmp', '')  # => 0
 *    IO.sysopen('t.tmp')      # => 8
 *    IO.sysopen('t.tmp', 'w') # => 9
 *
 *
 */

static VALUE
rb_io_s_sysopen(int argc, VALUE *argv, VALUE _)
{
    VALUE fname, vmode, vperm;
    VALUE intmode;
    int oflags, fd;
    mode_t perm;

    rb_scan_args(argc, argv, "12", &fname, &vmode, &vperm);
    FilePathValue(fname);

    if (NIL_P(vmode))
        oflags = O_RDONLY;
    else if (!NIL_P(intmode = rb_check_to_integer(vmode, "to_int")))
        oflags = NUM2INT(intmode);
    else {
        StringValue(vmode);
        oflags = rb_io_modestr_oflags(StringValueCStr(vmode));
    }
    if (NIL_P(vperm)) perm = 0666;
    else              perm = NUM2MODET(vperm);

    RB_GC_GUARD(fname) = rb_str_new4(fname);
    fd = rb_sysopen(fname, oflags, perm);
    return INT2NUM(fd);
}

static VALUE
check_pipe_command(VALUE filename_or_command)
{
    char *s = RSTRING_PTR(filename_or_command);
    long l = RSTRING_LEN(filename_or_command);
    char *e = s + l;
    int chlen;

    if (rb_enc_ascget(s, e, &chlen, rb_enc_get(filename_or_command)) == '|') {
        VALUE cmd = rb_str_new(s+chlen, l-chlen);
        return cmd;
    }
    return Qnil;
}

/*
 *  call-seq:
 *    open(path, mode = 'r', perm = 0666, **opts)             -> io or nil
 *    open(path, mode = 'r', perm = 0666, **opts) {|io| ... } -> obj
 *
 *  Creates an IO object connected to the given file.
 *
 *  This method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  With no block given, file stream is returned:
 *
 *    open('t.txt') # => #<File:t.txt>
 *
 *  With a block given, calls the block with the open file stream,
 *  then closes the stream:
 *
 *    open('t.txt') {|f| p f } # => #<File:t.txt (closed)>
 *
 *  Output:
 *
 *    #<File:t.txt>
 *
 *  See File.open for details.
 *
 */

static VALUE
rb_f_open(int argc, VALUE *argv, VALUE _)
{
    ID to_open = 0;
    int redirect = FALSE;

    if (argc >= 1) {
        CONST_ID(to_open, "to_open");
        if (rb_respond_to(argv[0], to_open)) {
            redirect = TRUE;
        }
        else {
            VALUE tmp = argv[0];
            FilePathValue(tmp);
            if (NIL_P(tmp)) {
                redirect = TRUE;
            }
            else {
                VALUE cmd = check_pipe_command(tmp);
                if (!NIL_P(cmd)) {
                    // TODO: when removed in 4.0, update command_injection.rdoc
                    rb_warn_deprecated_to_remove_at(4.0, "Calling Kernel#open with a leading '|'", "IO.popen");
                    argv[0] = cmd;
                    return rb_io_s_popen(argc, argv, rb_cIO);
                }
            }
        }
    }
    if (redirect) {
        VALUE io = rb_funcallv_kw(argv[0], to_open, argc-1, argv+1, RB_PASS_CALLED_KEYWORDS);

        if (rb_block_given_p()) {
            return rb_ensure(rb_yield, io, io_close, io);
        }
        return io;
    }
    return rb_io_s_open(argc, argv, rb_cFile);
}

static VALUE
rb_io_open_generic(VALUE klass, VALUE filename, int oflags, enum rb_io_mode fmode,
                   const struct rb_io_encoding *convconfig, mode_t perm)
{
    VALUE cmd;
    if (klass == rb_cIO && !NIL_P(cmd = check_pipe_command(filename))) {
        // TODO: when removed in 4.0, update command_injection.rdoc
        rb_warn_deprecated_to_remove_at(4.0, "IO process creation with a leading '|'", "IO.popen");
        return pipe_open_s(cmd, rb_io_oflags_modestr(oflags), fmode, convconfig);
    }
    else {
        return rb_file_open_generic(io_alloc(klass), filename,
                                    oflags, fmode, convconfig, perm);
    }
}

static VALUE
rb_io_open(VALUE io, VALUE filename, VALUE vmode, VALUE vperm, VALUE opt)
{
    int oflags;
    enum rb_io_mode fmode;
    struct rb_io_encoding convconfig;
    mode_t perm;

    rb_io_extract_modeenc(&vmode, &vperm, opt, &oflags, &fmode, &convconfig);
    perm = NIL_P(vperm) ? 0666 :  NUM2MODET(vperm);
    return rb_io_open_generic(io, filename, oflags, fmode, &convconfig, perm);
}

static VALUE
io_reopen(VALUE io, VALUE nfile)
{
    rb_io_t *fptr, *orig;
    int fd, fd2;
    rb_off_t pos = 0;

    nfile = rb_io_get_io(nfile);
    GetOpenFile(io, fptr);
    GetOpenFile(nfile, orig);

    if (fptr == orig) return io;
    if (RUBY_IO_EXTERNAL_P(fptr)) {
        if ((fptr->stdio_file == stdin && !(orig->mode & FMODE_READABLE)) ||
            (fptr->stdio_file == stdout && !(orig->mode & FMODE_WRITABLE)) ||
            (fptr->stdio_file == stderr && !(orig->mode & FMODE_WRITABLE))) {
            rb_raise(rb_eArgError,
                     "%s can't change access mode from \"%s\" to \"%s\"",
                     PREP_STDIO_NAME(fptr), rb_io_fmode_modestr(fptr->mode),
                     rb_io_fmode_modestr(orig->mode));
        }
    }
    if (fptr->mode & FMODE_WRITABLE) {
        if (io_fflush(fptr) < 0)
            rb_sys_fail_on_write(fptr);
    }
    else {
        flush_before_seek(fptr, true);
    }
    if (orig->mode & FMODE_READABLE) {
        pos = io_tell(orig);
    }
    if (orig->mode & FMODE_WRITABLE) {
        if (io_fflush(orig) < 0)
            rb_sys_fail_on_write(fptr);
    }

    /* copy rb_io_t structure */
    fptr->mode = orig->mode | (fptr->mode & FMODE_EXTERNAL);
    fptr->encs = orig->encs;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (RTEST(orig->pathv)) fptr->pathv = orig->pathv;
    else if (!RUBY_IO_EXTERNAL_P(fptr)) fptr->pathv = Qnil;
    fptr_copy_finalizer(fptr, orig);

    fd = fptr->fd;
    fd2 = orig->fd;
    if (fd != fd2) {
        // Interrupt all usage of the old file descriptor:
        rb_thread_io_close_interrupt(fptr);
        rb_thread_io_close_wait(fptr);

        if (RUBY_IO_EXTERNAL_P(fptr) || fd <= 2 || !fptr->stdio_file) {
            /* need to keep FILE objects of stdin, stdout and stderr */
            if (rb_cloexec_dup2(fd2, fd) < 0)
                rb_sys_fail_path(orig->pathv);
            rb_update_max_fd(fd);
        }
        else {
            fclose(fptr->stdio_file);
            fptr->stdio_file = 0;
            fptr->fd = -1;
            if (rb_cloexec_dup2(fd2, fd) < 0)
                rb_sys_fail_path(orig->pathv);
            rb_update_max_fd(fd);
            fptr->fd = fd;
        }

        if ((orig->mode & FMODE_READABLE) && pos >= 0) {
            if (io_seek(fptr, pos, SEEK_SET) < 0 && errno) {
                rb_sys_fail_path(fptr->pathv);
            }
            if (io_seek(orig, pos, SEEK_SET) < 0 && errno) {
                rb_sys_fail_path(orig->pathv);
            }
        }
    }

    if (fptr->mode & FMODE_BINMODE) {
        rb_io_binmode(io);
    }

    RBASIC_SET_CLASS(io, rb_obj_class(nfile));
    return io;
}

#ifdef _WIN32
int rb_freopen(VALUE fname, const char *mode, FILE *fp);
#else
static int
rb_freopen(VALUE fname, const char *mode, FILE *fp)
{
    if (!freopen(RSTRING_PTR(fname), mode, fp)) {
        RB_GC_GUARD(fname);
        return errno;
    }
    return 0;
}
#endif

/*
 *  call-seq:
 *    reopen(other_io)                 -> self
 *    reopen(path, mode = 'r', **opts) -> self
 *
 *  Reassociates the stream with another stream,
 *  which may be of a different class.
 *  This method may be used to redirect an existing stream
 *  to a new destination.
 *
 *  With argument +other_io+ given, reassociates with that stream:
 *
 *    # Redirect $stdin from a file.
 *    f = File.open('t.txt')
 *    $stdin.reopen(f)
 *    f.close
 *
 *    # Redirect $stdout to a file.
 *    f = File.open('t.tmp', 'w')
 *    $stdout.reopen(f)
 *    f.close
 *
 *  With argument +path+ given, reassociates with a new stream to that file path:
 *
 *    $stdin.reopen('t.txt')
 *    $stdout.reopen('t.tmp', 'w')
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 */

static VALUE
rb_io_reopen(int argc, VALUE *argv, VALUE file)
{
    VALUE fname, nmode, opt;
    int oflags;
    rb_io_t *fptr;

    if (rb_scan_args(argc, argv, "11:", &fname, &nmode, &opt) == 1) {
        VALUE tmp = rb_io_check_io(fname);
        if (!NIL_P(tmp)) {
            return io_reopen(file, tmp);
        }
    }

    FilePathValue(fname);
    rb_io_taint_check(file);
    fptr = RFILE(file)->fptr;
    if (!fptr) {
        fptr = RFILE(file)->fptr = ZALLOC(rb_io_t);
    }

    if (!NIL_P(nmode) || !NIL_P(opt)) {
        enum rb_io_mode fmode;
        struct rb_io_encoding convconfig;

        rb_io_extract_modeenc(&nmode, 0, opt, &oflags, &fmode, &convconfig);
        if (RUBY_IO_EXTERNAL_P(fptr) &&
            ((fptr->mode & FMODE_READWRITE) & (fmode & FMODE_READWRITE)) !=
            (fptr->mode & FMODE_READWRITE)) {
            rb_raise(rb_eArgError,
                     "%s can't change access mode from \"%s\" to \"%s\"",
                     PREP_STDIO_NAME(fptr), rb_io_fmode_modestr(fptr->mode),
                     rb_io_fmode_modestr(fmode));
        }
        fptr->mode = fmode;
        fptr->encs = convconfig;
    }
    else {
        oflags = rb_io_fmode_oflags(fptr->mode);
    }

    fptr->pathv = fname;
    if (fptr->fd < 0) {
        fptr->fd = rb_sysopen(fptr->pathv, oflags, 0666);
        fptr->stdio_file = 0;
        return file;
    }

    if (fptr->mode & FMODE_WRITABLE) {
        if (io_fflush(fptr) < 0)
            rb_sys_fail_on_write(fptr);
    }
    fptr->rbuf.off = fptr->rbuf.len = 0;

    if (fptr->stdio_file) {
        int e = rb_freopen(rb_str_encode_ospath(fptr->pathv),
                           rb_io_oflags_modestr(oflags),
                           fptr->stdio_file);
        if (e) rb_syserr_fail_path(e, fptr->pathv);
        fptr->fd = fileno(fptr->stdio_file);
        rb_fd_fix_cloexec(fptr->fd);
#ifdef USE_SETVBUF
        if (setvbuf(fptr->stdio_file, NULL, _IOFBF, 0) != 0)
            rb_warn("setvbuf() can't be honoured for %"PRIsVALUE, fptr->pathv);
#endif
        if (fptr->stdio_file == stderr) {
            if (setvbuf(fptr->stdio_file, NULL, _IONBF, BUFSIZ) != 0)
                rb_warn("setvbuf() can't be honoured for %"PRIsVALUE, fptr->pathv);
        }
        else if (fptr->stdio_file == stdout && isatty(fptr->fd)) {
            if (setvbuf(fptr->stdio_file, NULL, _IOLBF, BUFSIZ) != 0)
                rb_warn("setvbuf() can't be honoured for %"PRIsVALUE, fptr->pathv);
        }
    }
    else {
        int tmpfd = rb_sysopen(fptr->pathv, oflags, 0666);
        int err = 0;
        if (rb_cloexec_dup2(tmpfd, fptr->fd) < 0)
            err = errno;
        (void)close(tmpfd);
        if (err) {
            rb_syserr_fail_path(err, fptr->pathv);
        }
    }

    return file;
}

/* :nodoc: */
static VALUE
rb_io_init_copy(VALUE dest, VALUE io)
{
    rb_io_t *fptr, *orig;
    int fd;
    VALUE write_io;
    rb_off_t pos;

    io = rb_io_get_io(io);
    if (!OBJ_INIT_COPY(dest, io)) return dest;
    GetOpenFile(io, orig);
    MakeOpenFile(dest, fptr);

    rb_io_flush(io);

    /* copy rb_io_t structure */
    fptr->mode = orig->mode & ~FMODE_EXTERNAL;
    fptr->encs = orig->encs;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    fptr->timeout = orig->timeout;

    ccan_list_head_init(&fptr->blocking_operations);
    fptr->closing_ec = NULL;
    fptr->wakeup_mutex = Qnil;
    fptr->fork_generation = GET_VM()->fork_gen;

    if (!NIL_P(orig->pathv)) fptr->pathv = orig->pathv;
    fptr_copy_finalizer(fptr, orig);

    fd = ruby_dup(orig->fd);
    fptr->fd = fd;
    pos = io_tell(orig);
    if (0 <= pos)
        io_seek(fptr, pos, SEEK_SET);
    if (fptr->mode & FMODE_BINMODE) {
        rb_io_binmode(dest);
    }

    write_io = GetWriteIO(io);
    if (io != write_io) {
        write_io = rb_obj_dup(write_io);
        fptr->tied_io_for_writing = write_io;
        rb_ivar_set(dest, rb_intern("@tied_io_for_writing"), write_io);
    }

    return dest;
}

/*
 *  call-seq:
 *    printf(format_string, *objects) -> nil
 *
 *  Formats and writes +objects+ to the stream.
 *
 *  For details on +format_string+, see
 *  {Format Specifications}[rdoc-ref:format_specifications.rdoc].
 *
 */

VALUE
rb_io_printf(int argc, const VALUE *argv, VALUE out)
{
    rb_io_write(out, rb_f_sprintf(argc, argv));
    return Qnil;
}

/*
 *  call-seq:
 *    printf(format_string, *objects)               -> nil
 *    printf(io, format_string, *objects) -> nil
 *
 *  Equivalent to:
 *
 *    io.write(sprintf(format_string, *objects))
 *
 *  For details on +format_string+, see
 *  {Format Specifications}[rdoc-ref:format_specifications.rdoc].
 *
 *  With the single argument +format_string+, formats +objects+ into the string,
 *  then writes the formatted string to $stdout:
 *
 *    printf('%4.4d %10s %2.2f', 24, 24, 24.0)
 *
 *  Output (on $stdout):
 *
 *    0024         24 24.00#
 *
 *  With arguments +io+ and +format_string+, formats +objects+ into the string,
 *  then writes the formatted string to +io+:
 *
 *    printf($stderr, '%4.4d %10s %2.2f', 24, 24, 24.0)
 *
 *  Output (on $stderr):
 *
 *    0024         24 24.00# => nil
 *
 *  With no arguments, does nothing.
 *
 */

static VALUE
rb_f_printf(int argc, VALUE *argv, VALUE _)
{
    VALUE out;

    if (argc == 0) return Qnil;
    if (RB_TYPE_P(argv[0], T_STRING)) {
        out = rb_ractor_stdout();
    }
    else {
        out = argv[0];
        argv++;
        argc--;
    }
    rb_io_write(out, rb_f_sprintf(argc, argv));

    return Qnil;
}

static void
deprecated_str_setter(VALUE val, ID id, VALUE *var)
{
    rb_str_setter(val, id, &val);
    if (!NIL_P(val)) {
        rb_warn_deprecated("'%s'", NULL, rb_id2name(id));
    }
    *var = val;
}

static void
deprecated_rs_setter(VALUE val, ID id, VALUE *var)
{
    if (!NIL_P(val)) {
        if (!RB_TYPE_P(val, T_STRING)) {
            rb_raise(rb_eTypeError, "value of %"PRIsVALUE" must be String", rb_id2str(id));
        }
        if (rb_str_equal(val, rb_default_rs)) {
            val = rb_default_rs;
        }
        else {
            val = rb_str_frozen_bare_string(val);
        }
        rb_enc_str_coderange(val);
        rb_warn_deprecated("'%s'", NULL, rb_id2name(id));
    }
    *var = val;
}

/*
 *  call-seq:
 *    print(*objects) -> nil
 *
 *  Writes the given objects to the stream; returns +nil+.
 *  Appends the output record separator <tt>$OUTPUT_RECORD_SEPARATOR</tt>
 *  (<tt>$\\</tt>), if it is not +nil+.
 *  See {Line IO}[rdoc-ref:IO@Line+IO].
 *
 *  With argument +objects+ given, for each object:
 *
 *  - Converts via its method +to_s+ if not a string.
 *  - Writes to the stream.
 *  - If not the last object, writes the output field separator
 *    <tt>$OUTPUT_FIELD_SEPARATOR</tt> (<tt>$,</tt>) if it is not +nil+.
 *
 *  With default separators:
 *
 *    f = File.open('t.tmp', 'w+')
 *    objects = [0, 0.0, Rational(0, 1), Complex(0, 0), :zero, 'zero']
 *    p $OUTPUT_RECORD_SEPARATOR
 *    p $OUTPUT_FIELD_SEPARATOR
 *    f.print(*objects)
 *    f.rewind
 *    p f.read
 *    f.close
 *
 *  Output:
 *
 *    nil
 *    nil
 *    "00.00/10+0izerozero"
 *
 *  With specified separators:
 *
 *    $\ = "\n"
 *    $, = ','
 *    f.rewind
 *    f.print(*objects)
 *    f.rewind
 *    p f.read
 *
 *  Output:
 *
 *    "0,0.0,0/1,0+0i,zero,zero\n"
 *
 *  With no argument given, writes the content of <tt>$_</tt>
 *  (which is usually the most recent user input):
 *
 *    f = File.open('t.tmp', 'w+')
 *    gets # Sets $_ to the most recent user input.
 *    f.print
 *    f.close
 *
 */

VALUE
rb_io_print(int argc, const VALUE *argv, VALUE out)
{
    int i;
    VALUE line;

    /* if no argument given, print `$_' */
    if (argc == 0) {
        argc = 1;
        line = rb_lastline_get();
        argv = &line;
    }
    if (argc > 1 && !NIL_P(rb_output_fs)) {
        rb_category_warn(RB_WARN_CATEGORY_DEPRECATED, "$, is set to non-nil value");
    }
    for (i=0; i<argc; i++) {
        if (!NIL_P(rb_output_fs) && i>0) {
            rb_io_write(out, rb_output_fs);
        }
        rb_io_write(out, argv[i]);
    }
    if (argc > 0 && !NIL_P(rb_output_rs)) {
        rb_io_write(out, rb_output_rs);
    }

    return Qnil;
}

/*
 *  call-seq:
 *    print(*objects) -> nil
 *
 *  Equivalent to <tt>$stdout.print(*objects)</tt>,
 *  this method is the straightforward way to write to <tt>$stdout</tt>.
 *
 *  Writes the given objects to <tt>$stdout</tt>; returns +nil+.
 *  Appends the output record separator <tt>$OUTPUT_RECORD_SEPARATOR</tt>
 *  <tt>$\\</tt>), if it is not +nil+.
 *
 *  With argument +objects+ given, for each object:
 *
 *  - Converts via its method +to_s+ if not a string.
 *  - Writes to <tt>stdout</tt>.
 *  - If not the last object, writes the output field separator
 *    <tt>$OUTPUT_FIELD_SEPARATOR</tt> (<tt>$,</tt> if it is not +nil+.
 *
 *  With default separators:
 *
 *    objects = [0, 0.0, Rational(0, 1), Complex(0, 0), :zero, 'zero']
 *    $OUTPUT_RECORD_SEPARATOR
 *    $OUTPUT_FIELD_SEPARATOR
 *    print(*objects)
 *
 *  Output:
 *
 *    nil
 *    nil
 *    00.00/10+0izerozero
 *
 *  With specified separators:
 *
 *    $OUTPUT_RECORD_SEPARATOR = "\n"
 *    $OUTPUT_FIELD_SEPARATOR = ','
 *    print(*objects)
 *
 *  Output:
 *
 *    0,0.0,0/1,0+0i,zero,zero
 *
 *  With no argument given, writes the content of <tt>$_</tt>
 *  (which is usually the most recent user input):
 *
 *    gets  # Sets $_ to the most recent user input.
 *    print # Prints $_.
 *
 */

static VALUE
rb_f_print(int argc, const VALUE *argv, VALUE _)
{
    rb_io_print(argc, argv, rb_ractor_stdout());
    return Qnil;
}

/*
 *  call-seq:
 *    putc(object) -> object
 *
 *  Writes a character to the stream.
 *  See {Character IO}[rdoc-ref:IO@Character+IO].
 *
 *  If +object+ is numeric, converts to integer if necessary,
 *  then writes the character whose code is the
 *  least significant byte;
 *  if +object+ is a string, writes the first character:
 *
 *    $stdout.putc "A"
 *    $stdout.putc 65
 *
 *  Output:
 *
 *     AA
 *
 */

static VALUE
rb_io_putc(VALUE io, VALUE ch)
{
    VALUE str;
    if (RB_TYPE_P(ch, T_STRING)) {
        str = rb_str_substr(ch, 0, 1);
    }
    else {
        char c = NUM2CHR(ch);
        str = rb_str_new(&c, 1);
    }
    rb_io_write(io, str);
    return ch;
}

#define forward(obj, id, argc, argv) \
    rb_funcallv_kw(obj, id, argc, argv, RB_PASS_CALLED_KEYWORDS)
#define forward_public(obj, id, argc, argv) \
    rb_funcallv_public_kw(obj, id, argc, argv, RB_PASS_CALLED_KEYWORDS)
#define forward_current(id, argc, argv) \
    forward_public(ARGF.current_file, id, argc, argv)

/*
 *  call-seq:
 *    putc(int) -> int
 *
 *  Equivalent to:
 *
 *    $stdout.putc(int)
 *
 *  See IO#putc for important information regarding multi-byte characters.
 *
 */

static VALUE
rb_f_putc(VALUE recv, VALUE ch)
{
    VALUE r_stdout = rb_ractor_stdout();
    if (recv == r_stdout) {
        return rb_io_putc(recv, ch);
    }
    return forward(r_stdout, rb_intern("putc"), 1, &ch);
}


int
rb_str_end_with_asciichar(VALUE str, int c)
{
    long len = RSTRING_LEN(str);
    const char *ptr = RSTRING_PTR(str);
    rb_encoding *enc = rb_enc_from_index(ENCODING_GET(str));
    int n;

    if (len == 0) return 0;
    if ((n = rb_enc_mbminlen(enc)) == 1) {
        return ptr[len - 1] == c;
    }
    return rb_enc_ascget(ptr + ((len - 1) / n) * n, ptr + len, &n, enc) == c;
}

static VALUE
io_puts_ary(VALUE ary, VALUE out, int recur)
{
    VALUE tmp;
    long i;

    if (recur) {
        tmp = rb_str_new2("[...]");
        rb_io_puts(1, &tmp, out);
        return Qtrue;
    }
    ary = rb_check_array_type(ary);
    if (NIL_P(ary)) return Qfalse;
    for (i=0; i<RARRAY_LEN(ary); i++) {
        tmp = RARRAY_AREF(ary, i);
        rb_io_puts(1, &tmp, out);
    }
    return Qtrue;
}

/*
 *  call-seq:
 *    puts(*objects) -> nil
 *
 *  Writes the given +objects+ to the stream, which must be open for writing;
 *  returns +nil+.\
 *  Writes a newline after each that does not already end with a newline sequence.
 *  If called without arguments, writes a newline.
 *  See {Line IO}[rdoc-ref:IO@Line+IO].
 *
 *  Note that each added newline is the character <tt>"\n"<//tt>,
 *  not the output record separator (<tt>$\\</tt>).
 *
 *  Treatment for each object:
 *
 *  - String: writes the string.
 *  - Neither string nor array: writes <tt>object.to_s</tt>.
 *  - Array: writes each element of the array; arrays may be nested.
 *
 *  To keep these examples brief, we define this helper method:
 *
 *    def show(*objects)
 *      # Puts objects to file.
 *      f = File.new('t.tmp', 'w+')
 *      f.puts(objects)
 *      # Return file content.
 *      f.rewind
 *      p f.read
 *      f.close
 *    end
 *
 *    # Strings without newlines.
 *    show('foo', 'bar', 'baz')     # => "foo\nbar\nbaz\n"
 *    # Strings, some with newlines.
 *    show("foo\n", 'bar', "baz\n") # => "foo\nbar\nbaz\n"
 *
 *    # Neither strings nor arrays:
 *    show(0, 0.0, Rational(0, 1), Complex(9, 0), :zero)
 *    # => "0\n0.0\n0/1\n9+0i\nzero\n"
 *
 *    # Array of strings.
 *    show(['foo', "bar\n", 'baz']) # => "foo\nbar\nbaz\n"
 *    # Nested arrays.
 *    show([[[0, 1], 2, 3], 4, 5])  # => "0\n1\n2\n3\n4\n5\n"
 *
 */

VALUE
rb_io_puts(int argc, const VALUE *argv, VALUE out)
{
    VALUE line, args[2];

    /* if no argument given, print newline. */
    if (argc == 0) {
        rb_io_write(out, rb_default_rs);
        return Qnil;
    }
    for (int i = 0; i < argc; i++) {
        // Convert the argument to a string:
        if (RB_TYPE_P(argv[i], T_STRING)) {
            line = argv[i];
        }
        else if (rb_exec_recursive(io_puts_ary, argv[i], out)) {
            continue;
        }
        else {
            line = rb_obj_as_string(argv[i]);
        }

        // Write the line:
        int n = 0;
        if (RSTRING_LEN(line) == 0) {
            args[n++] = rb_default_rs;
        }
        else {
            args[n++] = line;
            if (!rb_str_end_with_asciichar(line, '\n')) {
                args[n++] = rb_default_rs;
            }
        }

        rb_io_writev(out, n, args);
    }

    return Qnil;
}

/*
 *  call-seq:
 *    puts(*objects)    -> nil
 *
 *  Equivalent to
 *
 *     $stdout.puts(objects)
 */

static VALUE
rb_f_puts(int argc, VALUE *argv, VALUE recv)
{
    VALUE r_stdout = rb_ractor_stdout();
    if (recv == r_stdout) {
        return rb_io_puts(argc, argv, recv);
    }
    return forward(r_stdout, rb_intern("puts"), argc, argv);
}

static VALUE
rb_p_write(VALUE str)
{
    VALUE args[2];
    args[0] = str;
    args[1] = rb_default_rs;
    VALUE r_stdout = rb_ractor_stdout();
    if (RB_TYPE_P(r_stdout, T_FILE) &&
        rb_method_basic_definition_p(CLASS_OF(r_stdout), id_write)) {
        io_writev(2, args, r_stdout);
    }
    else {
        rb_io_writev(r_stdout, 2, args);
    }
    return Qnil;
}

void
rb_p(VALUE obj) /* for debug print within C code */
{
    rb_p_write(rb_obj_as_string(rb_inspect(obj)));
}

static VALUE
rb_p_result(int argc, const VALUE *argv)
{
    VALUE ret = Qnil;

    if (argc == 1) {
        ret = argv[0];
    }
    else if (argc > 1) {
        ret = rb_ary_new4(argc, argv);
    }
    VALUE r_stdout = rb_ractor_stdout();
    if (RB_TYPE_P(r_stdout, T_FILE)) {
        rb_uninterruptible(rb_io_flush, r_stdout);
    }
    return ret;
}

/*
 *  call-seq:
 *    p(object)   -> obj
 *    p(*objects) -> array of objects
 *    p           -> nil
 *
 *  For each object +obj+, executes:
 *
 *    $stdout.write(obj.inspect, "\n")
 *
 *  With one object given, returns the object;
 *  with multiple objects given, returns an array containing the objects;
 *  with no object given, returns +nil+.
 *
 *  Examples:
 *
 *    r = Range.new(0, 4)
 *    p r                 # => 0..4
 *    p [r, r, r]         # => [0..4, 0..4, 0..4]
 *    p                   # => nil
 *
 *  Output:
 *
 *     0..4
 *     [0..4, 0..4, 0..4]
 *
 *  Kernel#p is designed for debugging purposes.
 *  Ruby implementations may define Kernel#p to be uninterruptible
 *  in whole or in part.
 *  On CRuby, Kernel#p's writing of data is uninterruptible.
 */

static VALUE
rb_f_p(int argc, VALUE *argv, VALUE self)
{
    int i;
    for (i=0; i<argc; i++) {
        VALUE inspected = rb_obj_as_string(rb_inspect(argv[i]));
        rb_uninterruptible(rb_p_write, inspected);
    }
    return rb_p_result(argc, argv);
}

/*
 *  call-seq:
 *    display(port = $>) -> nil
 *
 *  Writes +self+ on the given port:
 *
 *     1.display
 *     "cat".display
 *     [ 4, 5, 6 ].display
 *     puts
 *
 *  Output:
 *
 *     1cat[4, 5, 6]
 *
 */

static VALUE
rb_obj_display(int argc, VALUE *argv, VALUE self)
{
    VALUE out;

    out = (!rb_check_arity(argc, 0, 1) ? rb_ractor_stdout() : argv[0]);
    rb_io_write(out, self);

    return Qnil;
}

static int
rb_stderr_to_original_p(VALUE err)
{
    return (err == orig_stderr || RFILE(orig_stderr)->fptr->fd < 0);
}

void
rb_write_error2(const char *mesg, long len)
{
    VALUE out = rb_ractor_stderr();
    if (rb_stderr_to_original_p(out)) {
#ifdef _WIN32
        if (isatty(fileno(stderr))) {
            if (rb_w32_write_console(rb_str_new(mesg, len), fileno(stderr)) > 0) return;
        }
#endif
        if (fwrite(mesg, sizeof(char), (size_t)len, stderr) < (size_t)len) {
            /* failed to write to stderr, what can we do? */
            return;
        }
    }
    else {
        rb_io_write(out, rb_str_new(mesg, len));
    }
}

void
rb_write_error(const char *mesg)
{
    rb_write_error2(mesg, strlen(mesg));
}

void
rb_write_error_str(VALUE mesg)
{
    VALUE out = rb_ractor_stderr();
    /* a stopgap measure for the time being */
    if (rb_stderr_to_original_p(out)) {
        size_t len = (size_t)RSTRING_LEN(mesg);
#ifdef _WIN32
        if (isatty(fileno(stderr))) {
            if (rb_w32_write_console(mesg, fileno(stderr)) > 0) return;
        }
#endif
        if (fwrite(RSTRING_PTR(mesg), sizeof(char), len, stderr) < len) {
            RB_GC_GUARD(mesg);
            return;
        }
    }
    else {
        /* may unlock GVL, and  */
        rb_io_write(out, mesg);
    }
}

int
rb_stderr_tty_p(void)
{
    if (rb_stderr_to_original_p(rb_ractor_stderr()))
        return isatty(fileno(stderr));
    return 0;
}

static void
must_respond_to(ID mid, VALUE val, ID id)
{
    if (!rb_respond_to(val, mid)) {
        rb_raise(rb_eTypeError, "%"PRIsVALUE" must have %"PRIsVALUE" method, %"PRIsVALUE" given",
                 rb_id2str(id), rb_id2str(mid),
                 rb_obj_class(val));
    }
}

static void
stdin_setter(VALUE val, ID id, VALUE *ptr)
{
    rb_ractor_stdin_set(val);
}

static VALUE
stdin_getter(ID id, VALUE *ptr)
{
    return rb_ractor_stdin();
}

static void
stdout_setter(VALUE val, ID id, VALUE *ptr)
{
    must_respond_to(id_write, val, id);
    rb_ractor_stdout_set(val);
}

static VALUE
stdout_getter(ID id, VALUE *ptr)
{
    return rb_ractor_stdout();
}

static void
stderr_setter(VALUE val, ID id, VALUE *ptr)
{
    must_respond_to(id_write, val, id);
    rb_ractor_stderr_set(val);
}

static VALUE
stderr_getter(ID id, VALUE *ptr)
{
    return rb_ractor_stderr();
}

static VALUE
allocate_and_open_new_file(VALUE klass)
{
    VALUE self = io_alloc(klass);
    rb_io_make_open_file(self);
    return self;
}

VALUE
rb_io_open_descriptor(VALUE klass, int descriptor, int mode, VALUE path, VALUE timeout, struct rb_io_encoding *encoding)
{
    int state;
    VALUE self = rb_protect(allocate_and_open_new_file, klass, &state);
    if (state) {
        /* if we raised an exception allocating an IO object, but the caller
           intended to transfer ownership of this FD to us, close the fd before
           raising the exception. Otherwise, we would leak a FD - the caller
           expects GC to close the file, but we never got around to assigning
           it to a rb_io. */
        if (!(mode & FMODE_EXTERNAL)) {
            maygvl_close(descriptor, 0);
        }
        rb_jump_tag(state);
    }


    rb_io_t *io = RFILE(self)->fptr;
    io->self = self;
    io->fd = descriptor;
    io->mode = mode;

    /* At this point, Ruby fully owns the descriptor, and will close it when
       the IO gets GC'd (unless FMODE_EXTERNAL was set), no matter what happens
       in the rest of this method. */

    if (NIL_P(path)) {
        io->pathv = Qnil;
    }
    else {
        StringValue(path);
        io->pathv = rb_str_new_frozen(path);
    }

    io->timeout = timeout;

    ccan_list_head_init(&io->blocking_operations);
    io->closing_ec = NULL;
    io->wakeup_mutex = Qnil;
    io->fork_generation = GET_VM()->fork_gen;

    if (encoding) {
        io->encs = *encoding;
    }

    rb_update_max_fd(descriptor);

    return self;
}

static VALUE
prep_io(int fd, enum rb_io_mode fmode, VALUE klass, const char *path)
{
    VALUE path_value = Qnil;
    rb_encoding *e;
    struct rb_io_encoding convconfig;

    if (path) {
        path_value = rb_obj_freeze(rb_str_new_cstr(path));
    }

    e = (fmode & FMODE_BINMODE) ? rb_ascii8bit_encoding() : NULL;
    rb_io_ext_int_to_encs(e, NULL, &convconfig.enc, &convconfig.enc2, fmode);
    convconfig.ecflags = (fmode & FMODE_READABLE) ?
        MODE_BTMODE(ECONV_DEFAULT_NEWLINE_DECORATOR,
            0, ECONV_UNIVERSAL_NEWLINE_DECORATOR) : 0;
#ifdef TEXTMODE_NEWLINE_DECORATOR_ON_WRITE
    convconfig.ecflags |= (fmode & FMODE_WRITABLE) ?
        MODE_BTMODE(TEXTMODE_NEWLINE_DECORATOR_ON_WRITE,
            0, TEXTMODE_NEWLINE_DECORATOR_ON_WRITE) : 0;
#endif
    SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(convconfig.enc2, convconfig.ecflags);
    convconfig.ecopts = Qnil;

    VALUE self = rb_io_open_descriptor(klass, fd, fmode, path_value, Qnil, &convconfig);
    rb_io_t*io = RFILE(self)->fptr;

    if (!io_check_tty(io)) {
#ifdef __CYGWIN__
        io->mode |= FMODE_BINMODE;
        setmode(fd, O_BINARY);
#endif
    }

    return self;
}

VALUE
rb_io_fdopen(int fd, int oflags, const char *path)
{
    VALUE klass = rb_cIO;

    if (path && strcmp(path, "-")) klass = rb_cFile;
    return prep_io(fd, rb_io_oflags_fmode(oflags), klass, path);
}

static VALUE
prep_stdio(FILE *f, enum rb_io_mode fmode, VALUE klass, const char *path)
{
    rb_io_t *fptr;
    VALUE io = prep_io(fileno(f), fmode|FMODE_EXTERNAL|DEFAULT_TEXTMODE, klass, path);

    GetOpenFile(io, fptr);
    fptr->encs.ecflags |= ECONV_DEFAULT_NEWLINE_DECORATOR;
#ifdef TEXTMODE_NEWLINE_DECORATOR_ON_WRITE
    fptr->encs.ecflags |= TEXTMODE_NEWLINE_DECORATOR_ON_WRITE;
    if (fmode & FMODE_READABLE) {
        fptr->encs.ecflags |= ECONV_UNIVERSAL_NEWLINE_DECORATOR;
    }
#endif
    fptr->stdio_file = f;

    return io;
}

VALUE
rb_io_prep_stdin(void)
{
    return prep_stdio(stdin,  FMODE_READABLE, rb_cIO, "<STDIN>");
}

VALUE
rb_io_prep_stdout(void)
{
    return prep_stdio(stdout, FMODE_WRITABLE|FMODE_SIGNAL_ON_EPIPE, rb_cIO, "<STDOUT>");
}

VALUE
rb_io_prep_stderr(void)
{
    return prep_stdio(stderr, FMODE_WRITABLE|FMODE_SYNC, rb_cIO, "<STDERR>");
}

FILE *
rb_io_stdio_file(rb_io_t *fptr)
{
    if (!fptr->stdio_file) {
        int oflags = rb_io_fmode_oflags(fptr->mode) & ~O_EXCL;
        fptr->stdio_file = rb_fdopen(fptr->fd, rb_io_oflags_modestr(oflags));
    }
    return fptr->stdio_file;
}

static inline void
rb_io_buffer_init(struct rb_io_internal_buffer *buf)
{
    buf->ptr = NULL;
    buf->off = 0;
    buf->len = 0;
    buf->capa = 0;
}

static inline rb_io_t *
rb_io_fptr_new(void)
{
    rb_io_t *fp = ALLOC(rb_io_t);
    fp->self = Qnil;
    fp->fd = -1;
    fp->stdio_file = NULL;
    fp->mode = 0;
    fp->pid = 0;
    fp->lineno = 0;
    fp->pathv = Qnil;
    fp->finalize = 0;
    rb_io_buffer_init(&fp->wbuf);
    rb_io_buffer_init(&fp->rbuf);
    rb_io_buffer_init(&fp->cbuf);
    fp->readconv = NULL;
    fp->writeconv = NULL;
    fp->writeconv_asciicompat = Qnil;
    fp->writeconv_pre_ecflags = 0;
    fp->writeconv_pre_ecopts = Qnil;
    fp->writeconv_initialized = 0;
    fp->tied_io_for_writing = 0;
    fp->encs.enc = NULL;
    fp->encs.enc2 = NULL;
    fp->encs.ecflags = 0;
    fp->encs.ecopts = Qnil;
    fp->write_lock = Qnil;
    fp->timeout = Qnil;
    ccan_list_head_init(&fp->blocking_operations);
    fp->closing_ec = NULL;
    fp->wakeup_mutex = Qnil;
    fp->fork_generation = GET_VM()->fork_gen;
    return fp;
}

rb_io_t *
rb_io_make_open_file(VALUE obj)
{
    rb_io_t *fp = 0;

    Check_Type(obj, T_FILE);
    if (RFILE(obj)->fptr) {
        rb_io_close(obj);
        rb_io_fptr_finalize(RFILE(obj)->fptr);
        RFILE(obj)->fptr = 0;
    }
    fp = rb_io_fptr_new();
    fp->self = obj;
    RFILE(obj)->fptr = fp;
    return fp;
}

static VALUE io_initialize(VALUE io, VALUE fnum, VALUE vmode, VALUE opt);

/*
 *  call-seq:
 *    IO.new(fd, mode = 'r', **opts) -> io
 *
 *  Creates and returns a new \IO object (file stream) from a file descriptor.
 *
 *  \IO.new may be useful for interaction with low-level libraries.
 *  For higher-level interactions, it may be simpler to create
 *  the file stream using File.open.
 *
 *  Argument +fd+ must be a valid file descriptor (integer):
 *
 *    path = 't.tmp'
 *    fd = IO.sysopen(path) # => 3
 *    IO.new(fd)            # => #<IO:fd 3>
 *
 *  The new \IO object does not inherit encoding
 *  (because the integer file descriptor does not have an encoding):
 *
 *    fd = IO.sysopen('t.rus', 'rb')
 *    io = IO.new(fd)
 *    io.external_encoding # => #<Encoding:UTF-8> # Not ASCII-8BIT.
 *
 *  Optional argument +mode+ (defaults to 'r') must specify a valid mode;
 *  see {Access Modes}[rdoc-ref:File@Access+Modes]:
 *
 *    IO.new(fd, 'w')         # => #<IO:fd 3>
 *    IO.new(fd, File::WRONLY) # => #<IO:fd 3>
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 *  Examples:
 *
 *    IO.new(fd, internal_encoding: nil) # => #<IO:fd 3>
 *    IO.new(fd, autoclose: true)        # => #<IO:fd 3>
 *
 */

static VALUE
rb_io_initialize(int argc, VALUE *argv, VALUE io)
{
    VALUE fnum, vmode;
    VALUE opt;

    rb_scan_args(argc, argv, "11:", &fnum, &vmode, &opt);
    return io_initialize(io, fnum, vmode, opt);
}

static VALUE
io_initialize(VALUE io, VALUE fnum, VALUE vmode, VALUE opt)
{
    rb_io_t *fp;
    int fd, oflags = O_RDONLY;
    enum rb_io_mode fmode;
    struct rb_io_encoding convconfig;
#if defined(HAVE_FCNTL) && defined(F_GETFL)
    int ofmode;
#else
    struct stat st;
#endif

    rb_io_extract_modeenc(&vmode, 0, opt, &oflags, &fmode, &convconfig);

    fd = NUM2INT(fnum);
    if (rb_reserved_fd_p(fd)) {
        rb_raise(rb_eArgError, "The given fd is not accessible because RubyVM reserves it");
    }
#if defined(HAVE_FCNTL) && defined(F_GETFL)
    oflags = fcntl(fd, F_GETFL);
    if (oflags == -1) rb_sys_fail(0);
#else
    if (fstat(fd, &st) < 0) rb_sys_fail(0);
#endif
    rb_update_max_fd(fd);
#if defined(HAVE_FCNTL) && defined(F_GETFL)
    ofmode = rb_io_oflags_fmode(oflags);
    if (NIL_P(vmode)) {
        fmode = ofmode;
    }
    else if ((~ofmode & fmode) & FMODE_READWRITE) {
        VALUE error = INT2FIX(EINVAL);
        rb_exc_raise(rb_class_new_instance(1, &error, rb_eSystemCallError));
    }
#endif
    VALUE path = Qnil;

    if (!NIL_P(opt)) {
        if (rb_hash_aref(opt, sym_autoclose) == Qfalse) {
            fmode |= FMODE_EXTERNAL;
        }

        path = rb_hash_aref(opt, RB_ID2SYM(idPath));
        if (!NIL_P(path)) {
            StringValue(path);
            path = rb_str_new_frozen(path);
        }
    }

    MakeOpenFile(io, fp);
    fp->self = io;
    fp->fd = fd;
    fp->mode = fmode;
    fp->encs = convconfig;
    fp->pathv = path;
    fp->timeout = Qnil;
    ccan_list_head_init(&fp->blocking_operations);
    fp->closing_ec = NULL;
    fp->wakeup_mutex = Qnil;
    fp->fork_generation = GET_VM()->fork_gen;
    clear_codeconv(fp);
    io_check_tty(fp);
    if (fileno(stdin) == fd)
        fp->stdio_file = stdin;
    else if (fileno(stdout) == fd)
        fp->stdio_file = stdout;
    else if (fileno(stderr) == fd)
        fp->stdio_file = stderr;

    if (fmode & FMODE_SETENC_BY_BOM) io_set_encoding_by_bom(io);
    return io;
}

/*
 *  call-seq:
 *    set_encoding_by_bom -> encoding or nil
 *
 *  If the stream begins with a BOM
 *  ({byte order marker}[https://en.wikipedia.org/wiki/Byte_order_mark]),
 *  consumes the BOM and sets the external encoding accordingly;
 *  returns the result encoding if found, or +nil+ otherwise:
 *
 *   File.write('t.tmp', "\u{FEFF}abc")
 *   io = File.open('t.tmp', 'rb')
 *   io.set_encoding_by_bom # => #<Encoding:UTF-8>
 *   io.close
 *
 *   File.write('t.tmp', 'abc')
 *   io = File.open('t.tmp', 'rb')
 *   io.set_encoding_by_bom # => nil
 *   io.close
 *
 *  Raises an exception if the stream is not binmode
 *  or its encoding has already been set.
 *
 */

static VALUE
rb_io_set_encoding_by_bom(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (!(fptr->mode & FMODE_BINMODE)) {
        rb_raise(rb_eArgError, "ASCII incompatible encoding needs binmode");
    }
    if (fptr->encs.enc2) {
        rb_raise(rb_eArgError, "encoding conversion is set");
    }
    else if (fptr->encs.enc && fptr->encs.enc != rb_ascii8bit_encoding()) {
        rb_raise(rb_eArgError, "encoding is set to %s already",
                 rb_enc_name(fptr->encs.enc));
    }
    if (!io_set_encoding_by_bom(io)) return Qnil;
    return rb_enc_from_encoding(fptr->encs.enc);
}

/*
 *  call-seq:
 *    File.new(path, mode = 'r', perm = 0666, **opts) -> file
 *
 *  Opens the file at the given +path+ according to the given +mode+;
 *  creates and returns a new File object for that file.
 *
 *  The new File object is buffered mode (or non-sync mode), unless
 *  +filename+ is a tty.
 *  See IO#flush, IO#fsync, IO#fdatasync, and IO#sync=.
 *
 *  Argument +path+ must be a valid file path:
 *
 *    f = File.new('/etc/fstab')
 *    f.close
 *    f = File.new('t.txt')
 *    f.close
 *
 *  Optional argument +mode+ (defaults to 'r') must specify a valid mode;
 *  see {Access Modes}[rdoc-ref:File@Access+Modes]:
 *
 *    f = File.new('t.tmp', 'w')
 *    f.close
 *    f = File.new('t.tmp', File::RDONLY)
 *    f.close
 *
 *  Optional argument +perm+ (defaults to 0666) must specify valid permissions
 *  see {File Permissions}[rdoc-ref:File@File+Permissions]:
 *
 *    f = File.new('t.tmp', File::CREAT, 0644)
 *    f.close
 *    f = File.new('t.tmp', File::CREAT, 0444)
 *    f.close
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 */

static VALUE
rb_file_initialize(int argc, VALUE *argv, VALUE io)
{
    if (RFILE(io)->fptr) {
        rb_raise(rb_eRuntimeError, "reinitializing File");
    }
    VALUE fname, vmode, vperm, opt;
    int posargc = rb_scan_args(argc, argv, "12:", &fname, &vmode, &vperm, &opt);
    if (posargc < 3) {          /* perm is File only */
        VALUE fd = rb_check_to_int(fname);

        if (!NIL_P(fd)) {
            return io_initialize(io, fd, vmode, opt);
        }
    }
    return rb_open_file(io, fname, vmode, vperm, opt);
}

/* :nodoc: */
static VALUE
rb_io_s_new(int argc, VALUE *argv, VALUE klass)
{
    if (rb_block_given_p()) {
        VALUE cname = rb_obj_as_string(klass);

        rb_warn("%"PRIsVALUE"::new() does not take block; use %"PRIsVALUE"::open() instead",
                cname, cname);
    }
    return rb_class_new_instance_kw(argc, argv, klass, RB_PASS_CALLED_KEYWORDS);
}


/*
 *  call-seq:
 *    IO.for_fd(fd, mode = 'r', **opts) -> io
 *
 *  Synonym for IO.new.
 *
 */

static VALUE
rb_io_s_for_fd(int argc, VALUE *argv, VALUE klass)
{
    VALUE io = rb_obj_alloc(klass);
    rb_io_initialize(argc, argv, io);
    return io;
}

/*
 *  call-seq:
 *     ios.autoclose?   -> true or false
 *
 *  Returns +true+ if the underlying file descriptor of _ios_ will be
 *  closed at its finalization or at calling #close, otherwise +false+.
 */

static VALUE
rb_io_autoclose_p(VALUE io)
{
    rb_io_t *fptr = RFILE(io)->fptr;
    rb_io_check_closed(fptr);
    return RBOOL(!(fptr->mode & FMODE_EXTERNAL));
}

/*
 *  call-seq:
 *     io.autoclose = bool    -> true or false
 *
 *  Sets auto-close flag.
 *
 *     f = File.open(File::NULL)
 *     IO.for_fd(f.fileno).close
 *     f.gets # raises Errno::EBADF
 *
 *     f = File.open(File::NULL)
 *     g = IO.for_fd(f.fileno)
 *     g.autoclose = false
 *     g.close
 *     f.gets # won't cause Errno::EBADF
 */

static VALUE
rb_io_set_autoclose(VALUE io, VALUE autoclose)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    if (!RTEST(autoclose))
        fptr->mode |= FMODE_EXTERNAL;
    else
        fptr->mode &= ~FMODE_EXTERNAL;
    return autoclose;
}

static VALUE
io_wait_event(VALUE io, int event, VALUE timeout, int return_io)
{
    VALUE result = rb_io_wait(io, RB_INT2NUM(event), timeout);

    if (!RB_TEST(result)) {
        return Qnil;
    }

    int mask = RB_NUM2INT(result);

    if (mask & event) {
        if (return_io)
            return io;
        else
            return result;
    }
    else {
        return Qfalse;
    }
}

/*
 * call-seq:
 *   io.wait_readable          -> truthy or falsy
 *   io.wait_readable(timeout) -> truthy or falsy
 *
 * Waits until IO is readable and returns a truthy value, or a falsy
 * value when times out.  Returns a truthy value immediately when
 * buffered data is available.
 */

static VALUE
io_wait_readable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;

    RB_IO_POINTER(io, fptr);
    rb_io_check_readable(fptr);

    if (rb_io_read_pending(fptr)) return Qtrue;

    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_READABLE, timeout, 1);
}

/*
 * call-seq:
 *   io.wait_writable          -> truthy or falsy
 *   io.wait_writable(timeout) -> truthy or falsy
 *
 * Waits until IO is writable and returns a truthy value or a falsy
 * value when times out.
 */
static VALUE
io_wait_writable(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;

    RB_IO_POINTER(io, fptr);
    rb_io_check_writable(fptr);

    rb_check_arity(argc, 0, 1);
    VALUE timeout = (argc == 1 ? argv[0] : Qnil);

    return io_wait_event(io, RUBY_IO_WRITABLE, timeout, 1);
}

/*
 * call-seq:
 *   io.wait_priority          -> truthy or falsy
 *   io.wait_priority(timeout) -> truthy or falsy
 *
 * Waits until IO is priority and returns a truthy value or a falsy
 * value when times out. Priority data is sent and received using
 * the Socket::MSG_OOB flag and is typically limited to streams.
 */
static VALUE
io_wait_priority(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr = NULL;

    RB_IO_POINTER(io, fptr);
    rb_io_check_readable(fptr);

    if (rb_io_read_pending(fptr)) return Qtrue;

    rb_check_arity(argc, 0, 1);
    VALUE timeout = argc == 1 ? argv[0] : Qnil;

    return io_wait_event(io, RUBY_IO_PRIORITY, timeout, 1);
}

static int
wait_mode_sym(VALUE mode)
{
    if (mode == ID2SYM(rb_intern("r"))) {
        return RB_WAITFD_IN;
    }
    if (mode == ID2SYM(rb_intern("read"))) {
        return RB_WAITFD_IN;
    }
    if (mode == ID2SYM(rb_intern("readable"))) {
        return RB_WAITFD_IN;
    }
    if (mode == ID2SYM(rb_intern("w"))) {
        return RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("write"))) {
        return RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("writable"))) {
        return RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("rw"))) {
        return RB_WAITFD_IN|RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("read_write"))) {
        return RB_WAITFD_IN|RB_WAITFD_OUT;
    }
    if (mode == ID2SYM(rb_intern("readable_writable"))) {
        return RB_WAITFD_IN|RB_WAITFD_OUT;
    }

    rb_raise(rb_eArgError, "unsupported mode: %"PRIsVALUE, mode);
}

static inline enum rb_io_event
io_event_from_value(VALUE value)
{
    int events = RB_NUM2INT(value);

    if (events <= 0) rb_raise(rb_eArgError, "Events must be positive integer!");

    return events;
}

/*
 * call-seq:
 *   io.wait(events, timeout) -> event mask, false or nil
 *   io.wait(timeout = nil, mode = :read) -> self, true, or false
 *
 * Waits until the IO becomes ready for the specified events and returns the
 * subset of events that become ready, or a falsy value when times out.
 *
 * The events can be a bit mask of +IO::READABLE+, +IO::WRITABLE+ or
 * +IO::PRIORITY+.
 *
 * Returns an event mask (truthy value) immediately when buffered data is available.
 *
 * Optional parameter +mode+ is one of +:read+, +:write+, or
 * +:read_write+.
 */

static VALUE
io_wait(int argc, VALUE *argv, VALUE io)
{
    VALUE timeout = Qundef;
    enum rb_io_event events = 0;
    int return_io = 0;

    // The documented signature for this method is actually incorrect.
    // A single timeout is allowed in any position, and multiple symbols can be given.
    // Whether this is intentional or not, I don't know, and as such I consider this to
    // be a legacy/slow path.
    if (argc != 2 || (RB_SYMBOL_P(argv[0]) || RB_SYMBOL_P(argv[1]))) {
        // We'd prefer to return the actual mask, but this form would return the io itself:
        return_io = 1;

        // Slow/messy path:
        for (int i = 0; i < argc; i += 1) {
            if (RB_SYMBOL_P(argv[i])) {
                events |= wait_mode_sym(argv[i]);
            }
            else if (UNDEF_P(timeout)) {
                rb_time_interval(timeout = argv[i]);
            }
            else {
                rb_raise(rb_eArgError, "timeout given more than once");
            }
        }

        if (UNDEF_P(timeout)) timeout = Qnil;

        if (events == 0) {
            events = RUBY_IO_READABLE;
        }
    }
    else /* argc == 2 and neither are symbols */ {
        // This is the fast path:
        events = io_event_from_value(argv[0]);
        timeout = argv[1];
    }

    if (events & RUBY_IO_READABLE) {
        rb_io_t *fptr = NULL;
        RB_IO_POINTER(io, fptr);

        if (rb_io_read_pending(fptr)) {
            // This was the original behaviour:
            if (return_io) return Qtrue;
            // New behaviour always returns an event mask:
            else return RB_INT2NUM(RUBY_IO_READABLE);
        }
    }

    return io_wait_event(io, events, timeout, return_io);
}

static void
argf_mark(void *ptr)
{
    struct argf *p = ptr;
    rb_gc_mark(p->filename);
    rb_gc_mark(p->current_file);
    rb_gc_mark(p->argv);
    rb_gc_mark(p->inplace);
    rb_gc_mark(p->encs.ecopts);
}

static size_t
argf_memsize(const void *ptr)
{
    const struct argf *p = ptr;
    size_t size = sizeof(*p);
    return size;
}

static void
argf_compact(void *ptr)
{
    struct argf *p = ptr;
    p->filename = rb_gc_location(p->filename);
    p->current_file = rb_gc_location(p->current_file);
    p->argv = rb_gc_location(p->argv);
    p->inplace = rb_gc_location(p->inplace);
    p->encs.ecopts = rb_gc_location(p->encs.ecopts);
}

static const rb_data_type_t argf_type = {
    "ARGF",
    {argf_mark, RUBY_TYPED_DEFAULT_FREE, argf_memsize, argf_compact},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static inline void
argf_init(struct argf *p, VALUE v)
{
    p->filename = Qnil;
    p->current_file = Qnil;
    p->lineno = 0;
    p->argv = v;
}

static VALUE
argf_alloc(VALUE klass)
{
    struct argf *p;
    VALUE argf = TypedData_Make_Struct(klass, struct argf, &argf_type, p);

    argf_init(p, Qnil);
    return argf;
}

#undef rb_argv

/* :nodoc: */
static VALUE
argf_initialize(VALUE argf, VALUE argv)
{
    memset(&ARGF, 0, sizeof(ARGF));
    argf_init(&ARGF, argv);

    return argf;
}

/* :nodoc: */
static VALUE
argf_initialize_copy(VALUE argf, VALUE orig)
{
    if (!OBJ_INIT_COPY(argf, orig)) return argf;
    ARGF = argf_of(orig);
    ARGF.argv = rb_obj_dup(ARGF.argv);
    return argf;
}

/*
 *  call-seq:
 *     ARGF.lineno = integer  -> integer
 *
 *  Sets the line number of ARGF as a whole to the given Integer.
 *
 *  ARGF sets the line number automatically as you read data, so normally
 *  you will not need to set it explicitly. To access the current line number
 *  use ARGF.lineno.
 *
 *  For example:
 *
 *      ARGF.lineno      #=> 0
 *      ARGF.readline    #=> "This is line 1\n"
 *      ARGF.lineno      #=> 1
 *      ARGF.lineno = 0  #=> 0
 *      ARGF.lineno      #=> 0
 */
static VALUE
argf_set_lineno(VALUE argf, VALUE val)
{
    ARGF.lineno = NUM2INT(val);
    ARGF.last_lineno = ARGF.lineno;
    return val;
}

/*
 *  call-seq:
 *     ARGF.lineno  -> integer
 *
 *  Returns the current line number of ARGF as a whole. This value
 *  can be set manually with ARGF.lineno=.
 *
 *  For example:
 *
 *      ARGF.lineno   #=> 0
 *      ARGF.readline #=> "This is line 1\n"
 *      ARGF.lineno   #=> 1
 */
static VALUE
argf_lineno(VALUE argf)
{
    return INT2FIX(ARGF.lineno);
}

static VALUE
argf_forward(int argc, VALUE *argv, VALUE argf)
{
    return forward_current(rb_frame_this_func(), argc, argv);
}

#define next_argv() argf_next_argv(argf)
#define ARGF_GENERIC_INPUT_P() \
    (ARGF.current_file == rb_stdin && !RB_TYPE_P(ARGF.current_file, T_FILE))
#define ARGF_FORWARD(argc, argv) do {\
    if (ARGF_GENERIC_INPUT_P())\
        return argf_forward((argc), (argv), argf);\
} while (0)
#define NEXT_ARGF_FORWARD(argc, argv) do {\
    if (!next_argv()) return Qnil;\
    ARGF_FORWARD((argc), (argv));\
} while (0)

static void
argf_close(VALUE argf)
{
    VALUE file = ARGF.current_file;
    if (file == rb_stdin) return;
    if (RB_TYPE_P(file, T_FILE)) {
        rb_io_set_write_io(file, Qnil);
    }
    io_close(file);
    ARGF.init_p = -1;
}

static int
argf_next_argv(VALUE argf)
{
    char *fn;
    rb_io_t *fptr;
    int stdout_binmode = 0;
    enum rb_io_mode fmode;

    VALUE r_stdout = rb_ractor_stdout();

    if (RB_TYPE_P(r_stdout, T_FILE)) {
        GetOpenFile(r_stdout, fptr);
        if (fptr->mode & FMODE_BINMODE)
            stdout_binmode = 1;
    }

    if (ARGF.init_p == 0) {
        if (!NIL_P(ARGF.argv) && RARRAY_LEN(ARGF.argv) > 0) {
            ARGF.next_p = 1;
        }
        else {
            ARGF.next_p = -1;
        }
        ARGF.init_p = 1;
    }
    else {
        if (NIL_P(ARGF.argv)) {
            ARGF.next_p = -1;
        }
        else if (ARGF.next_p == -1 && RARRAY_LEN(ARGF.argv) > 0) {
            ARGF.next_p = 1;
        }
    }

    if (ARGF.next_p == 1) {
        if (ARGF.init_p == 1) argf_close(argf);
      retry:
        if (RARRAY_LEN(ARGF.argv) > 0) {
            VALUE filename = rb_ary_shift(ARGF.argv);
            FilePathValue(filename);
            ARGF.filename = filename;
            filename = rb_str_encode_ospath(filename);
            fn = StringValueCStr(filename);
            if (RSTRING_LEN(filename) == 1 && fn[0] == '-') {
                ARGF.current_file = rb_stdin;
                if (ARGF.inplace) {
                    rb_warn("Can't do inplace edit for stdio; skipping");
                    goto retry;
                }
            }
            else {
                VALUE write_io = Qnil;
                int fr = rb_sysopen(filename, O_RDONLY, 0);

                if (ARGF.inplace) {
                    struct stat st;
#ifndef NO_SAFE_RENAME
                    struct stat st2;
#endif
                    VALUE str;
                    int fw;

                    if (RB_TYPE_P(r_stdout, T_FILE) && r_stdout != orig_stdout) {
                        rb_io_close(r_stdout);
                    }
                    fstat(fr, &st);
                    str = filename;
                    if (!NIL_P(ARGF.inplace)) {
                        VALUE suffix = ARGF.inplace;
                        str = rb_str_dup(str);
                        if (NIL_P(rb_str_cat_conv_enc_opts(str, RSTRING_LEN(str),
                                                           RSTRING_PTR(suffix), RSTRING_LEN(suffix),
                                                           rb_enc_get(suffix), 0, Qnil))) {
                            rb_str_append(str, suffix);
                        }
#ifdef NO_SAFE_RENAME
                        (void)close(fr);
                        (void)unlink(RSTRING_PTR(str));
                        if (rename(fn, RSTRING_PTR(str)) < 0) {
                            rb_warn("Can't rename %"PRIsVALUE" to %"PRIsVALUE": %s, skipping file",
                                    filename, str, strerror(errno));
                            goto retry;
                        }
                        fr = rb_sysopen(str, O_RDONLY, 0);
#else
                        if (rename(fn, RSTRING_PTR(str)) < 0) {
                            rb_warn("Can't rename %"PRIsVALUE" to %"PRIsVALUE": %s, skipping file",
                                    filename, str, strerror(errno));
                            close(fr);
                            goto retry;
                        }
#endif
                    }
                    else {
#ifdef NO_SAFE_RENAME
                        rb_fatal("Can't do inplace edit without backup");
#else
                        if (unlink(fn) < 0) {
                            rb_warn("Can't remove %"PRIsVALUE": %s, skipping file",
                                    filename, strerror(errno));
                            close(fr);
                            goto retry;
                        }
#endif
                    }
                    fw = rb_sysopen(filename, O_WRONLY|O_CREAT|O_TRUNC, 0666);
#ifndef NO_SAFE_RENAME
                    fstat(fw, &st2);
#ifdef HAVE_FCHMOD
                    fchmod(fw, st.st_mode);
#else
                    chmod(fn, st.st_mode);
#endif
                    if (st.st_uid!=st2.st_uid || st.st_gid!=st2.st_gid) {
                        int err;
#ifdef HAVE_FCHOWN
                        err = fchown(fw, st.st_uid, st.st_gid);
#else
                        err = chown(fn, st.st_uid, st.st_gid);
#endif
                        if (err && getuid() == 0 && st2.st_uid == 0) {
                            const char *wkfn = RSTRING_PTR(filename);
                            rb_warn("Can't set owner/group of %"PRIsVALUE" to same as %"PRIsVALUE": %s, skipping file",
                                    filename, str, strerror(errno));
                            (void)close(fr);
                            (void)close(fw);
                            (void)unlink(wkfn);
                            goto retry;
                        }
                    }
#endif
                    write_io = prep_io(fw, FMODE_WRITABLE, rb_cFile, fn);
                    rb_ractor_stdout_set(write_io);
                    if (stdout_binmode) rb_io_binmode(rb_stdout);
                }
                fmode = FMODE_READABLE;
                if (!ARGF.binmode) {
                    fmode |= DEFAULT_TEXTMODE;
                }
                ARGF.current_file = prep_io(fr, fmode, rb_cFile, fn);
                if (!NIL_P(write_io)) {
                    rb_io_set_write_io(ARGF.current_file, write_io);
                }
                RB_GC_GUARD(filename);
            }
            if (ARGF.binmode) rb_io_ascii8bit_binmode(ARGF.current_file);
            GetOpenFile(ARGF.current_file, fptr);
            if (ARGF.encs.enc) {
                fptr->encs = ARGF.encs;
                clear_codeconv(fptr);
            }
            else {
                fptr->encs.ecflags &= ~ECONV_NEWLINE_DECORATOR_MASK;
                if (!ARGF.binmode) {
                    fptr->encs.ecflags |= ECONV_DEFAULT_NEWLINE_DECORATOR;
#ifdef TEXTMODE_NEWLINE_DECORATOR_ON_WRITE
                    fptr->encs.ecflags |= TEXTMODE_NEWLINE_DECORATOR_ON_WRITE;
#endif
                }
            }
            ARGF.next_p = 0;
        }
        else {
            ARGF.next_p = 1;
            return FALSE;
        }
    }
    else if (ARGF.next_p == -1) {
        ARGF.current_file = rb_stdin;
        ARGF.filename = rb_str_new2("-");
        if (ARGF.inplace) {
            rb_warn("Can't do inplace edit for stdio");
            rb_ractor_stdout_set(orig_stdout);
        }
    }
    if (ARGF.init_p == -1) ARGF.init_p = 1;
    return TRUE;
}

static VALUE
argf_getline(int argc, VALUE *argv, VALUE argf)
{
    VALUE line;
    long lineno = ARGF.lineno;

  retry:
    if (!next_argv()) return Qnil;
    if (ARGF_GENERIC_INPUT_P()) {
        line = forward_current(idGets, argc, argv);
    }
    else {
        if (argc == 0 && rb_rs == rb_default_rs) {
            line = rb_io_gets(ARGF.current_file);
        }
        else {
            line = rb_io_getline(argc, argv, ARGF.current_file);
        }
        if (NIL_P(line) && ARGF.next_p != -1) {
            argf_close(argf);
            ARGF.next_p = 1;
            goto retry;
        }
    }
    if (!NIL_P(line)) {
        ARGF.lineno = ++lineno;
        ARGF.last_lineno = ARGF.lineno;
    }
    return line;
}

static VALUE
argf_lineno_getter(ID id, VALUE *var)
{
    VALUE argf = *var;
    return INT2FIX(ARGF.last_lineno);
}

static void
argf_lineno_setter(VALUE val, ID id, VALUE *var)
{
    VALUE argf = *var;
    int n = NUM2INT(val);
    ARGF.last_lineno = ARGF.lineno = n;
}

void
rb_reset_argf_lineno(long n)
{
    ARGF.last_lineno = ARGF.lineno = n;
}

static VALUE argf_gets(int, VALUE *, VALUE);

/*
 *  call-seq:
 *     gets(sep=$/ [, getline_args])     -> string or nil
 *     gets(limit [, getline_args])      -> string or nil
 *     gets(sep, limit [, getline_args]) -> string or nil
 *
 *  Returns (and assigns to <code>$_</code>) the next line from the list
 *  of files in +ARGV+ (or <code>$*</code>), or from standard input if
 *  no files are present on the command line. Returns +nil+ at end of
 *  file. The optional argument specifies the record separator. The
 *  separator is included with the contents of each record. A separator
 *  of +nil+ reads the entire contents, and a zero-length separator
 *  reads the input one paragraph at a time, where paragraphs are
 *  divided by two consecutive newlines.  If the first argument is an
 *  integer, or optional second argument is given, the returning string
 *  would not be longer than the given value in bytes.  If multiple
 *  filenames are present in +ARGV+, <code>gets(nil)</code> will read
 *  the contents one file at a time.
 *
 *     ARGV << "testfile"
 *     print while gets
 *
 *  <em>produces:</em>
 *
 *     This is line one
 *     This is line two
 *     This is line three
 *     And so on...
 *
 *  The style of programming using <code>$_</code> as an implicit
 *  parameter is gradually losing favor in the Ruby community.
 */

static VALUE
rb_f_gets(int argc, VALUE *argv, VALUE recv)
{
    if (recv == argf) {
        return argf_gets(argc, argv, argf);
    }
    return forward(argf, idGets, argc, argv);
}

/*
 *  call-seq:
 *     ARGF.gets(sep=$/ [, getline_args])     -> string or nil
 *     ARGF.gets(limit [, getline_args])      -> string or nil
 *     ARGF.gets(sep, limit [, getline_args]) -> string or nil
 *
 *  Returns the next line from the current file in ARGF.
 *
 *  By default lines are assumed to be separated by <code>$/</code>;
 *  to use a different character as a separator, supply it as a String
 *  for the _sep_ argument.
 *
 *  The optional _limit_ argument specifies how many characters of each line
 *  to return. By default all characters are returned.
 *
 *  See IO.readlines for details about getline_args.
 *
 */
static VALUE
argf_gets(int argc, VALUE *argv, VALUE argf)
{
    VALUE line;

    line = argf_getline(argc, argv, argf);
    rb_lastline_set(line);

    return line;
}

VALUE
rb_gets(void)
{
    VALUE line;

    if (rb_rs != rb_default_rs) {
        return rb_f_gets(0, 0, argf);
    }

  retry:
    if (!next_argv()) return Qnil;
    line = rb_io_gets(ARGF.current_file);
    if (NIL_P(line) && ARGF.next_p != -1) {
        rb_io_close(ARGF.current_file);
        ARGF.next_p = 1;
        goto retry;
    }
    rb_lastline_set(line);
    if (!NIL_P(line)) {
        ARGF.lineno++;
        ARGF.last_lineno = ARGF.lineno;
    }

    return line;
}

static VALUE argf_readline(int, VALUE *, VALUE);

/*
 *  call-seq:
 *    readline(sep = $/, chomp: false)   -> string
 *    readline(limit, chomp: false)      -> string
 *    readline(sep, limit, chomp: false) -> string
 *
 *  Equivalent to method Kernel#gets, except that it raises an exception
 *  if called at end-of-stream:
 *
 *    $ cat t.txt | ruby -e "p readlines; readline"
 *    ["First line\n", "Second line\n", "\n", "Fourth line\n", "Fifth line\n"]
 *    in `readline': end of file reached (EOFError)
 *
 *  Optional keyword argument +chomp+ specifies whether line separators
 *  are to be omitted.
 */

static VALUE
rb_f_readline(int argc, VALUE *argv, VALUE recv)
{
    if (recv == argf) {
        return argf_readline(argc, argv, argf);
    }
    return forward(argf, rb_intern("readline"), argc, argv);
}


/*
 *  call-seq:
 *     ARGF.readline(sep=$/)     -> string
 *     ARGF.readline(limit)      -> string
 *     ARGF.readline(sep, limit) -> string
 *
 *  Returns the next line from the current file in ARGF.
 *
 *  By default lines are assumed to be separated by <code>$/</code>;
 *  to use a different character as a separator, supply it as a String
 *  for the _sep_ argument.
 *
 *  The optional _limit_ argument specifies how many characters of each line
 *  to return. By default all characters are returned.
 *
 *  An EOFError is raised at the end of the file.
 */
static VALUE
argf_readline(int argc, VALUE *argv, VALUE argf)
{
    VALUE line;

    if (!next_argv()) rb_eof_error();
    ARGF_FORWARD(argc, argv);
    line = argf_gets(argc, argv, argf);
    if (NIL_P(line)) {
        rb_eof_error();
    }

    return line;
}

static VALUE argf_readlines(int, VALUE *, VALUE);

/*
 *  call-seq:
 *    readlines(sep = $/, chomp: false, **enc_opts)   -> array
 *    readlines(limit, chomp: false, **enc_opts)       -> array
 *    readlines(sep, limit, chomp: false, **enc_opts) -> array
 *
 *  Returns an array containing the lines returned by calling
 *  Kernel#gets until the end-of-stream is reached;
 *  (see {Line IO}[rdoc-ref:IO@Line+IO]).
 *
 *  With only string argument +sep+ given,
 *  returns the remaining lines as determined by line separator +sep+,
 *  or +nil+ if none;
 *  see {Line Separator}[rdoc-ref:IO@Line+Separator]:
 *
 *    # Default separator.
 *    $ cat t.txt | ruby -e "p readlines"
 *    ["First line\n", "Second line\n", "\n", "Fourth line\n", "Fifth line\n"]
 *
 *    # Specified separator.
 *    $ cat t.txt | ruby -e "p readlines 'li'"
 *    ["First li", "ne\nSecond li", "ne\n\nFourth li", "ne\nFifth li", "ne\n"]
 *
 *    # Get-all separator.
 *    $ cat t.txt | ruby -e "p readlines nil"
 *    ["First line\nSecond line\n\nFourth line\nFifth line\n"]
 *
 *    # Get-paragraph separator.
 *    $ cat t.txt | ruby -e "p readlines ''"
 *    ["First line\nSecond line\n\n", "Fourth line\nFifth line\n"]
 *
 *  With only integer argument +limit+ given,
 *  limits the number of bytes in the line;
 *  see {Line Limit}[rdoc-ref:IO@Line+Limit]:
 *
 *    $cat t.txt | ruby -e "p readlines 10"
 *    ["First line", "\n", "Second lin", "e\n", "\n", "Fourth lin", "e\n", "Fifth line", "\n"]
 *
 *    $cat t.txt | ruby -e "p readlines 11"
 *    ["First line\n", "Second line", "\n", "\n", "Fourth line", "\n", "Fifth line\n"]
 *
 *    $cat t.txt | ruby -e "p readlines 12"
 *    ["First line\n", "Second line\n", "\n", "Fourth line\n", "Fifth line\n"]
 *
 *  With arguments +sep+ and +limit+ given,
 *  combines the two behaviors
 *  (see {Line Separator and Line Limit}[rdoc-ref:IO@Line+Separator+and+Line+Limit]).
 *
 *  Optional keyword argument +chomp+ specifies whether line separators
 *  are to be omitted:
 *
 *    $ cat t.txt | ruby -e "p readlines(chomp: true)"
 *    ["First line", "Second line", "", "Fourth line", "Fifth line"]
 *
 *  Optional keyword arguments +enc_opts+ specify encoding options;
 *  see {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 */

static VALUE
rb_f_readlines(int argc, VALUE *argv, VALUE recv)
{
    if (recv == argf) {
        return argf_readlines(argc, argv, argf);
    }
    return forward(argf, rb_intern("readlines"), argc, argv);
}

/*
 *  call-seq:
 *     ARGF.readlines(sep = $/, chomp: false)   -> array
 *     ARGF.readlines(limit, chomp: false)      -> array
 *     ARGF.readlines(sep, limit, chomp: false) -> array
 *
 *     ARGF.to_a(sep = $/, chomp: false)   -> array
 *     ARGF.to_a(limit, chomp: false)      -> array
 *     ARGF.to_a(sep, limit, chomp: false) -> array
 *
 *  Reads each file in ARGF in its entirety, returning an Array containing
 *  lines from the files. Lines are assumed to be separated by _sep_.
 *
 *     lines = ARGF.readlines
 *     lines[0]                #=> "This is line one\n"
 *
 *  See +IO.readlines+ for a full description of all options.
 */
static VALUE
argf_readlines(int argc, VALUE *argv, VALUE argf)
{
    long lineno = ARGF.lineno;
    VALUE lines, ary;

    ary = rb_ary_new();
    while (next_argv()) {
        if (ARGF_GENERIC_INPUT_P()) {
            lines = forward_current(rb_intern("readlines"), argc, argv);
        }
        else {
            lines = rb_io_readlines(argc, argv, ARGF.current_file);
            argf_close(argf);
        }
        ARGF.next_p = 1;
        rb_ary_concat(ary, lines);
        ARGF.lineno = lineno + RARRAY_LEN(ary);
        ARGF.last_lineno = ARGF.lineno;
    }
    ARGF.init_p = 0;
    return ary;
}

/*
 *  call-seq:
 *    `command` -> string
 *
 *  Returns the <tt>$stdout</tt> output from running +command+ in a subshell;
 *  sets global variable <tt>$?</tt> to the process status.
 *
 *  This method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  Examples:
 *
 *    $ `date`                 # => "Wed Apr  9 08:56:30 CDT 2003\n"
 *    $ `echo oops && exit 99` # => "oops\n"
 *    $ $?                     # => #<Process::Status: pid 17088 exit 99>
 *    $ $?.exitstatus          # => 99
 *
 *  The built-in syntax <tt>%x{...}</tt> uses this method.
 *
 */

static VALUE
rb_f_backquote(VALUE obj, VALUE str)
{
    VALUE port;
    VALUE result;
    rb_io_t *fptr;

    StringValue(str);
    rb_last_status_clear();
    port = pipe_open_s(str, "r", FMODE_READABLE|DEFAULT_TEXTMODE, NULL);
    if (NIL_P(port)) return rb_str_new(0,0);

    GetOpenFile(port, fptr);
    result = read_all(fptr, remain_size(fptr), Qnil);
    rb_io_close(port);
    rb_io_fptr_cleanup_all(fptr);
    RB_GC_GUARD(port);

    return result;
}

#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif

static VALUE
select_internal(VALUE read, VALUE write, VALUE except, struct timeval *tp, rb_fdset_t *fds)
{
    VALUE res, list;
    rb_fdset_t *rp, *wp, *ep;
    rb_io_t *fptr;
    long i;
    int max = 0, n;
    int pending = 0;
    struct timeval timerec;

    if (!NIL_P(read)) {
        Check_Type(read, T_ARRAY);
        for (i=0; i<RARRAY_LEN(read); i++) {
            GetOpenFile(rb_io_get_io(RARRAY_AREF(read, i)), fptr);
            rb_fd_set(fptr->fd, &fds[0]);
            if (READ_DATA_PENDING(fptr) || READ_CHAR_PENDING(fptr)) { /* check for buffered data */
                pending++;
                rb_fd_set(fptr->fd, &fds[3]);
            }
            if (max < fptr->fd) max = fptr->fd;
        }
        if (pending) {		/* no blocking if there's buffered data */
            timerec.tv_sec = timerec.tv_usec = 0;
            tp = &timerec;
        }
        rp = &fds[0];
    }
    else
        rp = 0;

    if (!NIL_P(write)) {
        Check_Type(write, T_ARRAY);
        for (i=0; i<RARRAY_LEN(write); i++) {
            VALUE write_io = GetWriteIO(rb_io_get_io(RARRAY_AREF(write, i)));
            GetOpenFile(write_io, fptr);
            rb_fd_set(fptr->fd, &fds[1]);
            if (max < fptr->fd) max = fptr->fd;
        }
        wp = &fds[1];
    }
    else
        wp = 0;

    if (!NIL_P(except)) {
        Check_Type(except, T_ARRAY);
        for (i=0; i<RARRAY_LEN(except); i++) {
            VALUE io = rb_io_get_io(RARRAY_AREF(except, i));
            VALUE write_io = GetWriteIO(io);
            GetOpenFile(io, fptr);
            rb_fd_set(fptr->fd, &fds[2]);
            if (max < fptr->fd) max = fptr->fd;
            if (io != write_io) {
                GetOpenFile(write_io, fptr);
                rb_fd_set(fptr->fd, &fds[2]);
                if (max < fptr->fd) max = fptr->fd;
            }
        }
        ep = &fds[2];
    }
    else {
        ep = 0;
    }

    max++;

    n = rb_thread_fd_select(max, rp, wp, ep, tp);
    if (n < 0) {
        rb_sys_fail(0);
    }
    if (!pending && n == 0) return Qnil; /* returns nil on timeout */

    res = rb_ary_new2(3);
    rb_ary_push(res, rp?rb_ary_new():rb_ary_new2(0));
    rb_ary_push(res, wp?rb_ary_new():rb_ary_new2(0));
    rb_ary_push(res, ep?rb_ary_new():rb_ary_new2(0));

    if (rp) {
        list = RARRAY_AREF(res, 0);
        for (i=0; i< RARRAY_LEN(read); i++) {
            VALUE obj = rb_ary_entry(read, i);
            VALUE io = rb_io_get_io(obj);
            GetOpenFile(io, fptr);
            if (rb_fd_isset(fptr->fd, &fds[0]) ||
                rb_fd_isset(fptr->fd, &fds[3])) {
                rb_ary_push(list, obj);
            }
        }
    }

    if (wp) {
        list = RARRAY_AREF(res, 1);
        for (i=0; i< RARRAY_LEN(write); i++) {
            VALUE obj = rb_ary_entry(write, i);
            VALUE io = rb_io_get_io(obj);
            VALUE write_io = GetWriteIO(io);
            GetOpenFile(write_io, fptr);
            if (rb_fd_isset(fptr->fd, &fds[1])) {
                rb_ary_push(list, obj);
            }
        }
    }

    if (ep) {
        list = RARRAY_AREF(res, 2);
        for (i=0; i< RARRAY_LEN(except); i++) {
            VALUE obj = rb_ary_entry(except, i);
            VALUE io = rb_io_get_io(obj);
            VALUE write_io = GetWriteIO(io);
            GetOpenFile(io, fptr);
            if (rb_fd_isset(fptr->fd, &fds[2])) {
                rb_ary_push(list, obj);
            }
            else if (io != write_io) {
                GetOpenFile(write_io, fptr);
                if (rb_fd_isset(fptr->fd, &fds[2])) {
                    rb_ary_push(list, obj);
                }
            }
        }
    }

    return res;			/* returns an empty array on interrupt */
}

struct select_args {
    VALUE read, write, except;
    struct timeval *timeout;
    rb_fdset_t fdsets[4];
};

static VALUE
select_call(VALUE arg)
{
    struct select_args *p = (struct select_args *)arg;

    return select_internal(p->read, p->write, p->except, p->timeout, p->fdsets);
}

static VALUE
select_end(VALUE arg)
{
    struct select_args *p = (struct select_args *)arg;
    int i;

    for (i = 0; i < numberof(p->fdsets); ++i)
        rb_fd_term(&p->fdsets[i]);
    return Qnil;
}

static VALUE sym_normal,   sym_sequential, sym_random,
             sym_willneed, sym_dontneed, sym_noreuse;

#ifdef HAVE_POSIX_FADVISE
struct io_advise_struct {
    int fd;
    int advice;
    rb_off_t offset;
    rb_off_t len;
};

static VALUE
io_advise_internal(void *arg)
{
    struct io_advise_struct *ptr = arg;
    return posix_fadvise(ptr->fd, ptr->offset, ptr->len, ptr->advice);
}

static VALUE
io_advise_sym_to_const(VALUE sym)
{
#ifdef POSIX_FADV_NORMAL
    if (sym == sym_normal)
        return INT2NUM(POSIX_FADV_NORMAL);
#endif

#ifdef POSIX_FADV_RANDOM
    if (sym == sym_random)
        return INT2NUM(POSIX_FADV_RANDOM);
#endif

#ifdef POSIX_FADV_SEQUENTIAL
    if (sym == sym_sequential)
        return INT2NUM(POSIX_FADV_SEQUENTIAL);
#endif

#ifdef POSIX_FADV_WILLNEED
    if (sym == sym_willneed)
        return INT2NUM(POSIX_FADV_WILLNEED);
#endif

#ifdef POSIX_FADV_DONTNEED
    if (sym == sym_dontneed)
        return INT2NUM(POSIX_FADV_DONTNEED);
#endif

#ifdef POSIX_FADV_NOREUSE
    if (sym == sym_noreuse)
        return INT2NUM(POSIX_FADV_NOREUSE);
#endif

    return Qnil;
}

static VALUE
do_io_advise(rb_io_t *fptr, VALUE advice, rb_off_t offset, rb_off_t len)
{
    int rv;
    struct io_advise_struct ias;
    VALUE num_adv;

    num_adv = io_advise_sym_to_const(advice);

    /*
     * The platform doesn't support this hint. We don't raise exception, instead
     * silently ignore it. Because IO::advise is only hint.
     */
    if (NIL_P(num_adv))
        return Qnil;

    ias.fd     = fptr->fd;
    ias.advice = NUM2INT(num_adv);
    ias.offset = offset;
    ias.len    = len;

    rv = (int)rb_io_blocking_region(fptr, io_advise_internal, &ias);
    if (rv && rv != ENOSYS) {
        /* posix_fadvise(2) doesn't set errno. On success it returns 0; otherwise
           it returns the error code. */
        VALUE message = rb_sprintf("%"PRIsVALUE" "
                                   "(%"PRI_OFFT_PREFIX"d, "
                                   "%"PRI_OFFT_PREFIX"d, "
                                   "%"PRIsVALUE")",
                                   fptr->pathv, offset, len, advice);
        rb_syserr_fail_str(rv, message);
    }

    return Qnil;
}

#endif /* HAVE_POSIX_FADVISE */

static void
advice_arg_check(VALUE advice)
{
    if (!SYMBOL_P(advice))
        rb_raise(rb_eTypeError, "advice must be a Symbol");

    if (advice != sym_normal &&
        advice != sym_sequential &&
        advice != sym_random &&
        advice != sym_willneed &&
        advice != sym_dontneed &&
        advice != sym_noreuse) {
        rb_raise(rb_eNotImpError, "Unsupported advice: %+"PRIsVALUE, advice);
    }
}

/*
 *  call-seq:
 *    advise(advice, offset = 0, len = 0) -> nil
 *
 *  Invokes Posix system call
 *  {posix_fadvise(2)}[https://linux.die.net/man/2/posix_fadvise],
 *  which announces an intention to access data from the current file
 *  in a particular manner.
 *
 *  The arguments and results are platform-dependent.
 *
 *  The relevant data is specified by:
 *
 *  - +offset+: The offset of the first byte of data.
 *  - +len+: The number of bytes to be accessed;
 *    if +len+ is zero, or is larger than the number of bytes remaining,
 *    all remaining bytes will be accessed.
 *
 *  Argument +advice+ is one of the following symbols:
 *
 *  - +:normal+: The application has no advice to give
 *    about its access pattern for the specified data.
 *    If no advice is given for an open file, this is the default assumption.
 *  - +:sequential+: The application expects to access the specified data sequentially
 *    (with lower offsets read before higher ones).
 *  - +:random+: The specified data will be accessed in random order.
 *  - +:noreuse+: The specified data will be accessed only once.
 *  - +:willneed+: The specified data will be accessed in the near future.
 *  - +:dontneed+: The specified data will not be accessed in the near future.
 *
 *  Not implemented on all platforms.
 *
 */
static VALUE
rb_io_advise(int argc, VALUE *argv, VALUE io)
{
    VALUE advice, offset, len;
    rb_off_t off, l;
    rb_io_t *fptr;

    rb_scan_args(argc, argv, "12", &advice, &offset, &len);
    advice_arg_check(advice);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    off = NIL_P(offset) ? 0 : NUM2OFFT(offset);
    l   = NIL_P(len)    ? 0 : NUM2OFFT(len);

#ifdef HAVE_POSIX_FADVISE
    return do_io_advise(fptr, advice, off, l);
#else
    ((void)off, (void)l);	/* Ignore all hint */
    return Qnil;
#endif
}

static int
is_pos_inf(VALUE x)
{
    double f;
    if (!RB_FLOAT_TYPE_P(x))
        return 0;
    f = RFLOAT_VALUE(x);
    return isinf(f) && 0 < f;
}

/*
 *  call-seq:
 *    IO.select(read_ios, write_ios = [], error_ios = [], timeout = nil) -> array or nil
 *
 *  Invokes system call {select(2)}[https://linux.die.net/man/2/select],
 *  which monitors multiple file descriptors,
 *  waiting until one or more of the file descriptors
 *  becomes ready for some class of I/O operation.
 *
 *  Not implemented on all platforms.
 *
 *  Each of the arguments +read_ios+, +write_ios+, and +error_ios+
 *  is an array of IO objects.
 *
 *  Argument +timeout+ is a numeric value (such as integer or float) timeout
 *  interval in seconds.
 *  +timeout+ can also be +nil+ or +Float::INFINITY+.
 *  +nil+ and +Float::INFINITY+ means no timeout.
 *
 *  The method monitors the \IO objects given in all three arrays,
 *  waiting for some to be ready;
 *  returns a 3-element array whose elements are:
 *
 *  - An array of the objects in +read_ios+ that are ready for reading.
 *  - An array of the objects in +write_ios+ that are ready for writing.
 *  - An array of the objects in +error_ios+ have pending exceptions.
 *
 *  If no object becomes ready within the given +timeout+, +nil+ is returned.
 *
 *  \IO.select peeks the buffer of \IO objects for testing readability.
 *  If the \IO buffer is not empty, \IO.select immediately notifies
 *  readability.  This "peek" only happens for \IO objects.  It does not
 *  happen for IO-like objects such as OpenSSL::SSL::SSLSocket.
 *
 *  The best way to use \IO.select is invoking it after non-blocking
 *  methods such as #read_nonblock, #write_nonblock, etc.  The methods
 *  raise an exception which is extended by IO::WaitReadable or
 *  IO::WaitWritable.  The modules notify how the caller should wait
 *  with \IO.select.  If IO::WaitReadable is raised, the caller should
 *  wait for reading.  If IO::WaitWritable is raised, the caller should
 *  wait for writing.
 *
 *  So, blocking read (#readpartial) can be emulated using
 *  #read_nonblock and \IO.select as follows:
 *
 *    begin
 *      result = io_like.read_nonblock(maxlen)
 *    rescue IO::WaitReadable
 *      IO.select([io_like])
 *      retry
 *    rescue IO::WaitWritable
 *      IO.select(nil, [io_like])
 *      retry
 *    end
 *
 *  Especially, the combination of non-blocking methods and \IO.select is
 *  preferred for IO like objects such as OpenSSL::SSL::SSLSocket.  It
 *  has #to_io method to return underlying IO object.  IO.select calls
 *  #to_io to obtain the file descriptor to wait.
 *
 *  This means that readability notified by \IO.select doesn't mean
 *  readability from OpenSSL::SSL::SSLSocket object.
 *
 *  The most likely situation is that OpenSSL::SSL::SSLSocket buffers
 *  some data.  \IO.select doesn't see the buffer.  So \IO.select can
 *  block when OpenSSL::SSL::SSLSocket#readpartial doesn't block.
 *
 *  However, several more complicated situations exist.
 *
 *  SSL is a protocol which is sequence of records.
 *  The record consists of multiple bytes.
 *  So, the remote side of SSL sends a partial record, IO.select
 *  notifies readability but OpenSSL::SSL::SSLSocket cannot decrypt a
 *  byte and OpenSSL::SSL::SSLSocket#readpartial will block.
 *
 *  Also, the remote side can request SSL renegotiation which forces
 *  the local SSL engine to write some data.
 *  This means OpenSSL::SSL::SSLSocket#readpartial may invoke #write
 *  system call and it can block.
 *  In such a situation, OpenSSL::SSL::SSLSocket#read_nonblock raises
 *  IO::WaitWritable instead of blocking.
 *  So, the caller should wait for ready for writability as above
 *  example.
 *
 *  The combination of non-blocking methods and \IO.select is also useful
 *  for streams such as tty, pipe socket socket when multiple processes
 *  read from a stream.
 *
 *  Finally, Linux kernel developers don't guarantee that
 *  readability of select(2) means readability of following read(2) even
 *  for a single process;
 *  see {select(2)}[https://linux.die.net/man/2/select]
 *
 *  Invoking \IO.select before IO#readpartial works well as usual.
 *  However it is not the best way to use \IO.select.
 *
 *  The writability notified by select(2) doesn't show
 *  how many bytes are writable.
 *  IO#write method blocks until given whole string is written.
 *  So, <tt>IO#write(two or more bytes)</tt> can block after
 *  writability is notified by \IO.select.  IO#write_nonblock is required
 *  to avoid the blocking.
 *
 *  Blocking write (#write) can be emulated using #write_nonblock and
 *  IO.select as follows: IO::WaitReadable should also be rescued for
 *  SSL renegotiation in OpenSSL::SSL::SSLSocket.
 *
 *    while 0 < string.bytesize
 *      begin
 *        written = io_like.write_nonblock(string)
 *      rescue IO::WaitReadable
 *        IO.select([io_like])
 *        retry
 *      rescue IO::WaitWritable
 *        IO.select(nil, [io_like])
 *        retry
 *      end
 *      string = string.byteslice(written..-1)
 *    end
 *
 *  Example:
 *
 *      rp, wp = IO.pipe
 *      mesg = "ping "
 *      100.times {
 *        # IO.select follows IO#read.  Not the best way to use IO.select.
 *        rs, ws, = IO.select([rp], [wp])
 *        if r = rs[0]
 *          ret = r.read(5)
 *          print ret
 *          case ret
 *          when /ping/
 *            mesg = "pong\n"
 *          when /pong/
 *            mesg = "ping "
 *          end
 *        end
 *        if w = ws[0]
 *          w.write(mesg)
 *        end
 *      }
 *
 *  Output:
 *
 *      ping pong
 *      ping pong
 *      ping pong
 *      (snipped)
 *      ping
 *
 */

static VALUE
rb_f_select(int argc, VALUE *argv, VALUE obj)
{
    VALUE scheduler = rb_fiber_scheduler_current();
    if (scheduler != Qnil) {
        // It's optionally supported.
        VALUE result = rb_fiber_scheduler_io_selectv(scheduler, argc, argv);
        if (!UNDEF_P(result)) return result;
    }

    VALUE timeout;
    struct select_args args;
    struct timeval timerec;
    int i;

    rb_scan_args(argc, argv, "13", &args.read, &args.write, &args.except, &timeout);
    if (NIL_P(timeout) || is_pos_inf(timeout)) {
        args.timeout = 0;
    }
    else {
        timerec = rb_time_interval(timeout);
        args.timeout = &timerec;
    }

    for (i = 0; i < numberof(args.fdsets); ++i)
        rb_fd_init(&args.fdsets[i]);

    return rb_ensure(select_call, (VALUE)&args, select_end, (VALUE)&args);
}

#ifdef IOCTL_REQ_TYPE
 typedef IOCTL_REQ_TYPE ioctl_req_t;
#else
 typedef int ioctl_req_t;
# define NUM2IOCTLREQ(num) ((int)NUM2LONG(num))
#endif

#ifdef HAVE_IOCTL
struct ioctl_arg {
    int		fd;
    ioctl_req_t	cmd;
    long	narg;
};

static VALUE
nogvl_ioctl(void *ptr)
{
    struct ioctl_arg *arg = ptr;

    return (VALUE)ioctl(arg->fd, arg->cmd, arg->narg);
}

static int
do_ioctl(struct rb_io *io, ioctl_req_t cmd, long narg)
{
    int retval;
    struct ioctl_arg arg;

    arg.fd = io->fd;
    arg.cmd = cmd;
    arg.narg = narg;

    retval = (int)rb_io_blocking_region(io, nogvl_ioctl, &arg);

    return retval;
}
#endif

#define DEFAULT_IOCTL_NARG_LEN (256)

#if defined(__linux__) && defined(_IOC_SIZE)
static long
linux_iocparm_len(ioctl_req_t cmd)
{
    long len;

    if ((cmd & 0xFFFF0000) == 0) {
        /* legacy and unstructured ioctl number. */
        return DEFAULT_IOCTL_NARG_LEN;
    }

    len = _IOC_SIZE(cmd);

    /* paranoia check for silly drivers which don't keep ioctl convention */
    if (len < DEFAULT_IOCTL_NARG_LEN)
        len = DEFAULT_IOCTL_NARG_LEN;

    return len;
}
#endif

#ifdef HAVE_IOCTL
static long
ioctl_narg_len(ioctl_req_t cmd)
{
    long len;

#ifdef IOCPARM_MASK
#ifndef IOCPARM_LEN
#define IOCPARM_LEN(x)  (((x) >> 16) & IOCPARM_MASK)
#endif
#endif
#ifdef IOCPARM_LEN
    len = IOCPARM_LEN(cmd);	/* on BSDish systems we're safe */
#elif defined(__linux__) && defined(_IOC_SIZE)
    len = linux_iocparm_len(cmd);
#else
    /* otherwise guess at what's safe */
    len = DEFAULT_IOCTL_NARG_LEN;
#endif

    return len;
}
#endif

#ifdef HAVE_FCNTL
#ifdef __linux__
typedef long fcntl_arg_t;
#else
/* posix */
typedef int fcntl_arg_t;
#endif

static long
fcntl_narg_len(ioctl_req_t cmd)
{
    long len;

    switch (cmd) {
#ifdef F_DUPFD
      case F_DUPFD:
        len = sizeof(fcntl_arg_t);
        break;
#endif
#ifdef F_DUP2FD /* bsd specific */
      case F_DUP2FD:
        len = sizeof(int);
        break;
#endif
#ifdef F_DUPFD_CLOEXEC /* linux specific */
      case F_DUPFD_CLOEXEC:
        len = sizeof(fcntl_arg_t);
        break;
#endif
#ifdef F_GETFD
      case F_GETFD:
        len = 1;
        break;
#endif
#ifdef F_SETFD
      case F_SETFD:
        len = sizeof(fcntl_arg_t);
        break;
#endif
#ifdef F_GETFL
      case F_GETFL:
        len = 1;
        break;
#endif
#ifdef F_SETFL
      case F_SETFL:
        len = sizeof(fcntl_arg_t);
        break;
#endif
#ifdef F_GETOWN
      case F_GETOWN:
        len = 1;
        break;
#endif
#ifdef F_SETOWN
      case F_SETOWN:
        len = sizeof(fcntl_arg_t);
        break;
#endif
#ifdef F_GETOWN_EX /* linux specific */
      case F_GETOWN_EX:
        len = sizeof(struct f_owner_ex);
        break;
#endif
#ifdef F_SETOWN_EX /* linux specific */
      case F_SETOWN_EX:
        len = sizeof(struct f_owner_ex);
        break;
#endif
#ifdef F_GETLK
      case F_GETLK:
        len = sizeof(struct flock);
        break;
#endif
#ifdef F_SETLK
      case F_SETLK:
        len = sizeof(struct flock);
        break;
#endif
#ifdef F_SETLKW
      case F_SETLKW:
        len = sizeof(struct flock);
        break;
#endif
#ifdef F_READAHEAD /* bsd specific */
      case F_READAHEAD:
        len = sizeof(int);
        break;
#endif
#ifdef F_RDAHEAD /* Darwin specific */
      case F_RDAHEAD:
        len = sizeof(int);
        break;
#endif
#ifdef F_GETSIG /* linux specific */
      case F_GETSIG:
        len = 1;
        break;
#endif
#ifdef F_SETSIG /* linux specific */
      case F_SETSIG:
        len = sizeof(fcntl_arg_t);
        break;
#endif
#ifdef F_GETLEASE /* linux specific */
      case F_GETLEASE:
        len = 1;
        break;
#endif
#ifdef F_SETLEASE /* linux specific */
      case F_SETLEASE:
        len = sizeof(fcntl_arg_t);
        break;
#endif
#ifdef F_NOTIFY /* linux specific */
      case F_NOTIFY:
        len = sizeof(fcntl_arg_t);
        break;
#endif

      default:
        len = 256;
        break;
    }

    return len;
}
#else /* HAVE_FCNTL */
static long
fcntl_narg_len(ioctl_req_t cmd)
{
    return 0;
}
#endif /* HAVE_FCNTL */

#define NARG_SENTINEL 17

static long
setup_narg(ioctl_req_t cmd, VALUE *argp, long (*narg_len)(ioctl_req_t))
{
    long narg = 0;
    VALUE arg = *argp;

    if (!RTEST(arg)) {
        narg = 0;
    }
    else if (FIXNUM_P(arg)) {
        narg = FIX2LONG(arg);
    }
    else if (arg == Qtrue) {
        narg = 1;
    }
    else {
        VALUE tmp = rb_check_string_type(arg);

        if (NIL_P(tmp)) {
            narg = NUM2LONG(arg);
        }
        else {
            char *ptr;
            long len, slen;

            *argp = arg = tmp;
            len = narg_len(cmd);
            rb_str_modify(arg);

            slen = RSTRING_LEN(arg);
            /* expand for data + sentinel. */
            if (slen < len+1) {
                rb_str_resize(arg, len+1);
                MEMZERO(RSTRING_PTR(arg)+slen, char, len-slen);
                slen = len+1;
            }
            /* a little sanity check here */
            ptr = RSTRING_PTR(arg);
            ptr[slen - 1] = NARG_SENTINEL;
            narg = (long)(SIGNED_VALUE)ptr;
        }
    }

    return narg;
}

static VALUE
finish_narg(int retval, VALUE arg, const rb_io_t *fptr)
{
    if (retval < 0) rb_sys_fail_path(fptr->pathv);
    if (RB_TYPE_P(arg, T_STRING)) {
        char *ptr;
        long slen;
        RSTRING_GETMEM(arg, ptr, slen);
        if (ptr[slen-1] != NARG_SENTINEL)
            rb_raise(rb_eArgError, "return value overflowed string");
        ptr[slen-1] = '\0';
    }

    return INT2NUM(retval);
}

#ifdef HAVE_IOCTL
static VALUE
rb_ioctl(VALUE io, VALUE req, VALUE arg)
{
    ioctl_req_t cmd = NUM2IOCTLREQ(req);
    rb_io_t *fptr;
    long narg;
    int retval;

    narg = setup_narg(cmd, &arg, ioctl_narg_len);
    GetOpenFile(io, fptr);
    retval = do_ioctl(fptr, cmd, narg);
    return finish_narg(retval, arg, fptr);
}

/*
 *  call-seq:
 *    ioctl(integer_cmd, argument) -> integer
 *
 *  Invokes Posix system call {ioctl(2)}[https://linux.die.net/man/2/ioctl],
 *  which issues a low-level command to an I/O device.
 *
 *  Issues a low-level command to an I/O device.
 *  The arguments and returned value are platform-dependent.
 *  The effect of the call is platform-dependent.
 *
 *  If argument +argument+ is an integer, it is passed directly;
 *  if it is a string, it is interpreted as a binary sequence of bytes.
 *
 *  Not implemented on all platforms.
 *
 */

static VALUE
rb_io_ioctl(int argc, VALUE *argv, VALUE io)
{
    VALUE req, arg;

    rb_scan_args(argc, argv, "11", &req, &arg);
    return rb_ioctl(io, req, arg);
}
#else
#define rb_io_ioctl rb_f_notimplement
#endif

#ifdef HAVE_FCNTL
struct fcntl_arg {
    int		fd;
    int 	cmd;
    long	narg;
};

static VALUE
nogvl_fcntl(void *ptr)
{
    struct fcntl_arg *arg = ptr;

#if defined(F_DUPFD)
    if (arg->cmd == F_DUPFD)
        return (VALUE)rb_cloexec_fcntl_dupfd(arg->fd, (int)arg->narg);
#endif
    return (VALUE)fcntl(arg->fd, arg->cmd, arg->narg);
}

static int
do_fcntl(struct rb_io *io, int cmd, long narg)
{
    int retval;
    struct fcntl_arg arg;

    arg.fd = io->fd;
    arg.cmd = cmd;
    arg.narg = narg;

    retval = (int)rb_io_blocking_region(io, nogvl_fcntl, &arg);
    if (retval != -1) {
        switch (cmd) {
#if defined(F_DUPFD)
          case F_DUPFD:
#endif
#if defined(F_DUPFD_CLOEXEC)
          case F_DUPFD_CLOEXEC:
#endif
            rb_update_max_fd(retval);
        }
    }

    return retval;
}

static VALUE
rb_fcntl(VALUE io, VALUE req, VALUE arg)
{
    int cmd = NUM2INT(req);
    rb_io_t *fptr;
    long narg;
    int retval;

    narg = setup_narg(cmd, &arg, fcntl_narg_len);
    GetOpenFile(io, fptr);
    retval = do_fcntl(fptr, cmd, narg);
    return finish_narg(retval, arg, fptr);
}

/*
 *  call-seq:
 *    fcntl(integer_cmd, argument) -> integer
 *
 *  Invokes Posix system call {fcntl(2)}[https://linux.die.net/man/2/fcntl],
 *  which provides a mechanism for issuing low-level commands to control or query
 *  a file-oriented I/O stream. Arguments and results are platform
 *  dependent.
 *
 *  If +argument+ is a number, its value is passed directly;
 *  if it is a string, it is interpreted as a binary sequence of bytes.
 *  (Array#pack might be a useful way to build this string.)
 *
 *  Not implemented on all platforms.
 *
 */

static VALUE
rb_io_fcntl(int argc, VALUE *argv, VALUE io)
{
    VALUE req, arg;

    rb_scan_args(argc, argv, "11", &req, &arg);
    return rb_fcntl(io, req, arg);
}
#else
#define rb_io_fcntl rb_f_notimplement
#endif

#if defined(HAVE_SYSCALL) || defined(HAVE___SYSCALL)
/*
 *  call-seq:
 *    syscall(integer_callno, *arguments)   -> integer
 *
 *  Invokes Posix system call {syscall(2)}[https://linux.die.net/man/2/syscall],
 *  which calls a specified function.
 *
 *  Calls the operating system function identified by +integer_callno+;
 *  returns the result of the function or raises SystemCallError if it failed.
 *  The effect of the call is platform-dependent.
 *  The arguments and returned value are platform-dependent.
 *
 *  For each of +arguments+: if it is an integer, it is passed directly;
 *  if it is a string, it is interpreted as a binary sequence of bytes.
 *  There may be as many as nine such arguments.
 *
 *  Arguments +integer_callno+ and +argument+, as well as the returned value,
 *  are platform-dependent.
 *
 *  Note: Method +syscall+ is essentially unsafe and unportable.
 *  The DL (Fiddle) library is preferred for safer and a bit
 *  more portable programming.
 *
 *  Not implemented on all platforms.
 *
 */

static VALUE
rb_f_syscall(int argc, VALUE *argv, VALUE _)
{
    VALUE arg[8];
#if SIZEOF_VOIDP == 8 && defined(HAVE___SYSCALL) && SIZEOF_INT != 8 /* mainly *BSD */
# define SYSCALL __syscall
# define NUM2SYSCALLID(x) NUM2LONG(x)
# define RETVAL2NUM(x) LONG2NUM(x)
# if SIZEOF_LONG == 8
    long num, retval = -1;
# elif SIZEOF_LONG_LONG == 8
    long long num, retval = -1;
# else
#  error ---->> it is asserted that __syscall takes the first argument and returns retval in 64bit signed integer. <<----
# endif
#elif defined(__linux__)
# define SYSCALL syscall
# define NUM2SYSCALLID(x) NUM2LONG(x)
# define RETVAL2NUM(x) LONG2NUM(x)
    /*
     * Linux man page says, syscall(2) function prototype is below.
     *
     *     int syscall(int number, ...);
     *
     * But, it's incorrect. Actual one takes and returned long. (see unistd.h)
     */
    long num, retval = -1;
#else
# define SYSCALL syscall
# define NUM2SYSCALLID(x) NUM2INT(x)
# define RETVAL2NUM(x) INT2NUM(x)
    int num, retval = -1;
#endif
    int i;

    if (RTEST(ruby_verbose)) {
        rb_category_warning(RB_WARN_CATEGORY_DEPRECATED,
            "We plan to remove a syscall function at future release. DL(Fiddle) provides safer alternative.");
    }

    if (argc == 0)
        rb_raise(rb_eArgError, "too few arguments for syscall");
    if (argc > numberof(arg))
        rb_raise(rb_eArgError, "too many arguments for syscall");
    num = NUM2SYSCALLID(argv[0]); ++argv;
    for (i = argc - 1; i--; ) {
        VALUE v = rb_check_string_type(argv[i]);

        if (!NIL_P(v)) {
            StringValue(v);
            rb_str_modify(v);
            arg[i] = (VALUE)StringValueCStr(v);
        }
        else {
            arg[i] = (VALUE)NUM2LONG(argv[i]);
        }
    }

    switch (argc) {
      case 1:
        retval = SYSCALL(num);
        break;
      case 2:
        retval = SYSCALL(num, arg[0]);
        break;
      case 3:
        retval = SYSCALL(num, arg[0],arg[1]);
        break;
      case 4:
        retval = SYSCALL(num, arg[0],arg[1],arg[2]);
        break;
      case 5:
        retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3]);
        break;
      case 6:
        retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4]);
        break;
      case 7:
        retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5]);
        break;
      case 8:
        retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6]);
        break;
    }

    if (retval == -1)
        rb_sys_fail(0);
    return RETVAL2NUM(retval);
#undef SYSCALL
#undef NUM2SYSCALLID
#undef RETVAL2NUM
}
#else
#define rb_f_syscall rb_f_notimplement
#endif

static VALUE
io_new_instance(VALUE args)
{
    return rb_class_new_instance(2, (VALUE*)args+1, *(VALUE*)args);
}

static rb_encoding *
find_encoding(VALUE v)
{
    rb_encoding *enc = rb_find_encoding(v);
    if (!enc) rb_warn("Unsupported encoding %"PRIsVALUE" ignored", v);
    return enc;
}

static void
io_encoding_set(rb_io_t *fptr, VALUE v1, VALUE v2, VALUE opt)
{
    rb_encoding *enc, *enc2;
    int ecflags = fptr->encs.ecflags;
    VALUE ecopts, tmp;

    if (!NIL_P(v2)) {
        enc2 = find_encoding(v1);
        tmp = rb_check_string_type(v2);
        if (!NIL_P(tmp)) {
            if (RSTRING_LEN(tmp) == 1 && RSTRING_PTR(tmp)[0] == '-') {
                /* Special case - "-" => no transcoding */
                enc = enc2;
                enc2 = NULL;
            }
            else
                enc = find_encoding(v2);
            if (enc == enc2) {
                /* Special case - "-" => no transcoding */
                enc2 = NULL;
            }
        }
        else {
            enc = find_encoding(v2);
            if (enc == enc2) {
                /* Special case - "-" => no transcoding */
                enc2 = NULL;
            }
        }
        if (enc2 == rb_ascii8bit_encoding()) {
            /* If external is ASCII-8BIT, no transcoding */
            enc = enc2;
            enc2 = NULL;
        }
        SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags);
        ecflags = rb_econv_prepare_options(opt, &ecopts, ecflags);
    }
    else {
        if (NIL_P(v1)) {
            /* Set to default encodings */
            rb_io_ext_int_to_encs(NULL, NULL, &enc, &enc2, 0);
            SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags);
            ecopts = Qnil;
        }
        else {
            tmp = rb_check_string_type(v1);
            if (!NIL_P(tmp) && rb_enc_asciicompat(enc = rb_enc_get(tmp))) {
                parse_mode_enc(RSTRING_PTR(tmp), enc, &enc, &enc2, NULL);
                SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags);
                ecflags = rb_econv_prepare_options(opt, &ecopts, ecflags);
            }
            else {
                rb_io_ext_int_to_encs(find_encoding(v1), NULL, &enc, &enc2, 0);
                SET_UNIVERSAL_NEWLINE_DECORATOR_IF_ENC2(enc2, ecflags);
                ecopts = Qnil;
            }
        }
    }
    validate_enc_binmode(&fptr->mode, ecflags, enc, enc2);
    fptr->encs.enc = enc;
    fptr->encs.enc2 = enc2;
    fptr->encs.ecflags = ecflags;
    fptr->encs.ecopts = ecopts;
    clear_codeconv(fptr);

}

struct io_encoding_set_args {
    rb_io_t *fptr;
    VALUE v1;
    VALUE v2;
    VALUE opt;
};

static VALUE
io_encoding_set_v(VALUE v)
{
    struct io_encoding_set_args *arg = (struct io_encoding_set_args *)v;
    io_encoding_set(arg->fptr, arg->v1, arg->v2, arg->opt);
    return Qnil;
}

static VALUE
pipe_pair_close(VALUE rw)
{
    VALUE *rwp = (VALUE *)rw;
    return rb_ensure(io_close, rwp[0], io_close, rwp[1]);
}

/*
 *  call-seq:
 *    IO.pipe(**opts) -> [read_io, write_io]
 *    IO.pipe(enc, **opts) -> [read_io, write_io]
 *    IO.pipe(ext_enc, int_enc, **opts) -> [read_io, write_io]
 *    IO.pipe(**opts) {|read_io, write_io| ...} -> object
 *    IO.pipe(enc, **opts) {|read_io, write_io| ...} -> object
 *    IO.pipe(ext_enc, int_enc, **opts) {|read_io, write_io| ...} -> object
 *
 *  Creates a pair of pipe endpoints, +read_io+ and +write_io+,
 *  connected to each other.
 *
 *  If argument +enc_string+ is given, it must be a string containing one of:
 *
 *  - The name of the encoding to be used as the external encoding.
 *  - The colon-separated names of two encodings to be used as the external
 *    and internal encodings.
 *
 *  If argument +int_enc+ is given, it must be an Encoding object
 *  or encoding name string that specifies the internal encoding to be used;
 *  if argument +ext_enc+ is also given, it must be an Encoding object
 *  or encoding name string that specifies the external encoding to be used.
 *
 *  The string read from +read_io+ is tagged with the external encoding;
 *  if an internal encoding is also specified, the string is converted
 *  to, and tagged with, that encoding.
 *
 *  If any encoding is specified,
 *  optional hash arguments specify the conversion option.
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding Options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 *  With no block given, returns the two endpoints in an array:
 *
 *    IO.pipe # => [#<IO:fd 4>, #<IO:fd 5>]
 *
 *  With a block given, calls the block with the two endpoints;
 *  closes both endpoints and returns the value of the block:
 *
 *    IO.pipe {|read_io, write_io| p read_io; p write_io }
 *
 *  Output:
 *
 *    #<IO:fd 6>
 *    #<IO:fd 7>
 *
 *  Not available on all platforms.
 *
 *  In the example below, the two processes close the ends of the pipe
 *  that they are not using. This is not just a cosmetic nicety. The
 *  read end of a pipe will not generate an end of file condition if
 *  there are any writers with the pipe still open. In the case of the
 *  parent process, the <tt>rd.read</tt> will never return if it
 *  does not first issue a <tt>wr.close</tt>:
 *
 *    rd, wr = IO.pipe
 *
 *    if fork
 *      wr.close
 *      puts "Parent got: <#{rd.read}>"
 *      rd.close
 *      Process.wait
 *    else
 *      rd.close
 *      puts 'Sending message to parent'
 *      wr.write "Hi Dad"
 *      wr.close
 *    end
 *
 *  <em>produces:</em>
 *
 *     Sending message to parent
 *     Parent got: <Hi Dad>
 *
 */

static VALUE
rb_io_s_pipe(int argc, VALUE *argv, VALUE klass)
{
    int pipes[2], state;
    VALUE r, w, args[3], v1, v2;
    VALUE opt;
    rb_io_t *fptr, *fptr2;
    struct io_encoding_set_args ies_args;
    enum rb_io_mode fmode = 0;
    VALUE ret;

    argc = rb_scan_args(argc, argv, "02:", &v1, &v2, &opt);
    if (rb_pipe(pipes) < 0)
        rb_sys_fail(0);

    args[0] = klass;
    args[1] = INT2NUM(pipes[0]);
    args[2] = INT2FIX(O_RDONLY);
    r = rb_protect(io_new_instance, (VALUE)args, &state);
    if (state) {
        close(pipes[0]);
        close(pipes[1]);
        rb_jump_tag(state);
    }
    GetOpenFile(r, fptr);

    ies_args.fptr = fptr;
    ies_args.v1 = v1;
    ies_args.v2 = v2;
    ies_args.opt = opt;
    rb_protect(io_encoding_set_v, (VALUE)&ies_args, &state);
    if (state) {
        close(pipes[1]);
        io_close(r);
        rb_jump_tag(state);
    }

    args[1] = INT2NUM(pipes[1]);
    args[2] = INT2FIX(O_WRONLY);
    w = rb_protect(io_new_instance, (VALUE)args, &state);
    if (state) {
        close(pipes[1]);
        if (!NIL_P(r)) rb_io_close(r);
        rb_jump_tag(state);
    }
    GetOpenFile(w, fptr2);
    rb_io_synchronized(fptr2);

    extract_binmode(opt, &fmode);

    if ((fmode & FMODE_BINMODE) && NIL_P(v1)) {
        rb_io_ascii8bit_binmode(r);
        rb_io_ascii8bit_binmode(w);
    }

#if DEFAULT_TEXTMODE
    if ((fptr->mode & FMODE_TEXTMODE) && (fmode & FMODE_BINMODE)) {
        fptr->mode &= ~FMODE_TEXTMODE;
        setmode(fptr->fd, O_BINARY);
    }
#if RUBY_CRLF_ENVIRONMENT
    if (fptr->encs.ecflags & ECONV_DEFAULT_NEWLINE_DECORATOR) {
        fptr->encs.ecflags |= ECONV_UNIVERSAL_NEWLINE_DECORATOR;
    }
#endif
#endif
    fptr->mode |= fmode;
#if DEFAULT_TEXTMODE
    if ((fptr2->mode & FMODE_TEXTMODE) && (fmode & FMODE_BINMODE)) {
        fptr2->mode &= ~FMODE_TEXTMODE;
        setmode(fptr2->fd, O_BINARY);
    }
#endif
    fptr2->mode |= fmode;

    ret = rb_assoc_new(r, w);
    if (rb_block_given_p()) {
        VALUE rw[2];
        rw[0] = r;
        rw[1] = w;
        return rb_ensure(rb_yield, ret, pipe_pair_close, (VALUE)rw);
    }
    return ret;
}

struct foreach_arg {
    int argc;
    VALUE *argv;
    VALUE io;
};

static void
open_key_args(VALUE klass, int argc, VALUE *argv, VALUE opt, struct foreach_arg *arg)
{
    VALUE path, v;
    VALUE vmode = Qnil, vperm = Qnil;

    path = *argv++;
    argc--;
    FilePathValue(path);
    arg->io = 0;
    arg->argc = argc;
    arg->argv = argv;
    if (NIL_P(opt)) {
        vmode = INT2NUM(O_RDONLY);
        vperm = INT2FIX(0666);
    }
    else if (!NIL_P(v = rb_hash_aref(opt, sym_open_args))) {
        int n;

        v = rb_to_array_type(v);
        n = RARRAY_LENINT(v);
        rb_check_arity(n, 0, 3); /* rb_io_open */
        rb_scan_args_kw(RB_SCAN_ARGS_LAST_HASH_KEYWORDS, n, RARRAY_CONST_PTR(v), "02:", &vmode, &vperm, &opt);
    }
    arg->io = rb_io_open(klass, path, vmode, vperm, opt);
}

static VALUE
io_s_foreach(VALUE v)
{
    struct getline_arg *arg = (void *)v;
    VALUE str;

    if (arg->limit == 0)
        rb_raise(rb_eArgError, "invalid limit: 0 for foreach");
    while (!NIL_P(str = rb_io_getline_1(arg->rs, arg->limit, arg->chomp, arg->io))) {
        rb_lastline_set(str);
        rb_yield(str);
    }
    rb_lastline_set(Qnil);
    return Qnil;
}

/*
 *  call-seq:
 *    IO.foreach(path, sep = $/, **opts) {|line| block }       -> nil
 *    IO.foreach(path, limit, **opts) {|line| block }          -> nil
 *    IO.foreach(path, sep, limit, **opts) {|line| block }     -> nil
 *    IO.foreach(...)                                          -> an_enumerator
 *
 *  Calls the block with each successive line read from the stream.
 *
 *  When called from class \IO (but not subclasses of \IO),
 *  this method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  The first argument must be a string that is the path to a file.
 *
 *  With only argument +path+ given, parses lines from the file at the given +path+,
 *  as determined by the default line separator,
 *  and calls the block with each successive line:
 *
 *    File.foreach('t.txt') {|line| p line }
 *
 *  Output: the same as above.
 *
 *  For both forms, command and path, the remaining arguments are the same.
 *
 *  With argument +sep+ given, parses lines as determined by that line separator
 *  (see {Line Separator}[rdoc-ref:IO@Line+Separator]):
 *
 *    File.foreach('t.txt', 'li') {|line| p line }
 *
 *  Output:
 *
 *    "First li"
 *    "ne\nSecond li"
 *    "ne\n\nThird li"
 *    "ne\nFourth li"
 *    "ne\n"
 *
 *  Each paragraph:
 *
 *    File.foreach('t.txt', '') {|paragraph| p paragraph }
 *
 *  Output:
 *
 *   "First line\nSecond line\n\n"
 *   "Third line\nFourth line\n"
 *
 *  With argument +limit+ given, parses lines as determined by the default
 *  line separator and the given line-length limit
 *  (see {Line Separator}[rdoc-ref:IO@Line+Separator] and {Line Limit}[rdoc-ref:IO@Line+Limit]):
 *
 *    File.foreach('t.txt', 7) {|line| p line }
 *
 *  Output:
 *
 *    "First l"
 *    "ine\n"
 *    "Second "
 *    "line\n"
 *    "\n"
 *    "Third l"
 *    "ine\n"
 *    "Fourth l"
 *    "line\n"
 *
 *  With arguments +sep+ and +limit+ given,
 *  combines the two behaviors
 *  (see {Line Separator and Line Limit}[rdoc-ref:IO@Line+Separator+and+Line+Limit]).
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *  - {Line Options}[rdoc-ref:IO@Line+IO].
 *
 *  Returns an Enumerator if no block is given.
 *
 */

static VALUE
rb_io_s_foreach(int argc, VALUE *argv, VALUE self)
{
    VALUE opt;
    int orig_argc = argc;
    struct foreach_arg arg;
    struct getline_arg garg;

    argc = rb_scan_args(argc, argv, "12:", NULL, NULL, NULL, &opt);
    RETURN_ENUMERATOR(self, orig_argc, argv);
    extract_getline_args(argc-1, argv+1, &garg);
    open_key_args(self, argc, argv, opt, &arg);
    if (NIL_P(arg.io)) return Qnil;
    extract_getline_opts(opt, &garg);
    check_getline_args(&garg.rs, &garg.limit, garg.io = arg.io);
    return rb_ensure(io_s_foreach, (VALUE)&garg, rb_io_close, arg.io);
}

static VALUE
io_s_readlines(VALUE v)
{
    struct getline_arg *arg = (void *)v;
    return io_readlines(arg, arg->io);
}

/*
 *  call-seq:
 *     IO.readlines(path, sep = $/, **opts)     -> array
 *     IO.readlines(path, limit, **opts)      -> array
 *     IO.readlines(path, sep, limit, **opts) -> array
 *
 *  Returns an array of all lines read from the stream.
 *
 *  When called from class \IO (but not subclasses of \IO),
 *  this method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  The first argument must be a string that is the path to a file.
 *
 *  With only argument +path+ given, parses lines from the file at the given +path+,
 *  as determined by the default line separator,
 *  and returns those lines in an array:
 *
 *    IO.readlines('t.txt')
 *    # => ["First line\n", "Second line\n", "\n", "Third line\n", "Fourth line\n"]
 *
 *  With argument +sep+ given, parses lines as determined by that line separator
 *  (see {Line Separator}[rdoc-ref:IO@Line+Separator]):
 *
 *    # Ordinary separator.
 *    IO.readlines('t.txt', 'li')
 *    # =>["First li", "ne\nSecond li", "ne\n\nThird li", "ne\nFourth li", "ne\n"]
 *    # Get-paragraphs separator.
 *    IO.readlines('t.txt', '')
 *    # => ["First line\nSecond line\n\n", "Third line\nFourth line\n"]
 *    # Get-all separator.
 *    IO.readlines('t.txt', nil)
 *    # => ["First line\nSecond line\n\nThird line\nFourth line\n"]
 *
 *  With argument +limit+ given, parses lines as determined by the default
 *  line separator and the given line-length limit
 *  (see {Line Separator}[rdoc-ref:IO@Line+Separator] and {Line Limit}[rdoc-ref:IO@Line+Limit]:
 *
 *    IO.readlines('t.txt', 7)
 *    # => ["First l", "ine\n", "Second ", "line\n", "\n", "Third l", "ine\n", "Fourth ", "line\n"]
 *
 *  With arguments +sep+ and +limit+ given,
 *  combines the two behaviors
 *  (see {Line Separator and Line Limit}[rdoc-ref:IO@Line+Separator+and+Line+Limit]).
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *  - {Line Options}[rdoc-ref:IO@Line+IO].
 *
 */

static VALUE
rb_io_s_readlines(int argc, VALUE *argv, VALUE io)
{
    VALUE opt;
    struct foreach_arg arg;
    struct getline_arg garg;

    argc = rb_scan_args(argc, argv, "12:", NULL, NULL, NULL, &opt);
    extract_getline_args(argc-1, argv+1, &garg);
    open_key_args(io, argc, argv, opt, &arg);
    if (NIL_P(arg.io)) return Qnil;
    extract_getline_opts(opt, &garg);
    check_getline_args(&garg.rs, &garg.limit, garg.io = arg.io);
    return rb_ensure(io_s_readlines, (VALUE)&garg, rb_io_close, arg.io);
}

static VALUE
io_s_read(VALUE v)
{
    struct foreach_arg *arg = (void *)v;
    return io_read(arg->argc, arg->argv, arg->io);
}

struct seek_arg {
    VALUE io;
    VALUE offset;
    int mode;
};

static VALUE
seek_before_access(VALUE argp)
{
    struct seek_arg *arg = (struct seek_arg *)argp;
    rb_io_binmode(arg->io);
    return rb_io_seek(arg->io, arg->offset, arg->mode);
}

/*
 *  call-seq:
 *     IO.read(path, length = nil, offset = 0, **opts)    -> string or nil
 *
 *  Opens the stream, reads and returns some or all of its content,
 *  and closes the stream; returns +nil+ if no bytes were read.
 *
 *  When called from class \IO (but not subclasses of \IO),
 *  this method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  The first argument must be a string that is the path to a file.
 *
 *  With only argument +path+ given, reads in text mode and returns the entire content
 *  of the file at the given path:
 *
 *    IO.read('t.txt')
 *    # => "First line\nSecond line\n\nThird line\nFourth line\n"
 *
 *  On Windows, text mode can terminate reading and leave bytes in the file
 *  unread when encountering certain special bytes. Consider using
 *  IO.binread if all bytes in the file should be read.
 *
 *  With argument +length+, returns +length+ bytes if available:
 *
 *    IO.read('t.txt', 7) # => "First l"
 *    IO.read('t.txt', 700)
 *    # => "First line\r\nSecond line\r\n\r\nFourth line\r\nFifth line\r\n"
 *
 *  With arguments +length+ and +offset+, returns +length+ bytes
 *  if available, beginning at the given +offset+:
 *
 *    IO.read('t.txt', 10, 2)   # => "rst line\nS"
 *    IO.read('t.txt', 10, 200) # => nil
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 */

static VALUE
rb_io_s_read(int argc, VALUE *argv, VALUE io)
{
    VALUE opt, offset;
    long off;
    struct foreach_arg arg;

    argc = rb_scan_args(argc, argv, "13:", NULL, NULL, &offset, NULL, &opt);
    if (!NIL_P(offset) && (off = NUM2LONG(offset)) < 0) {
        rb_raise(rb_eArgError, "negative offset %ld given", off);
    }
    open_key_args(io, argc, argv, opt, &arg);
    if (NIL_P(arg.io)) return Qnil;
    if (!NIL_P(offset)) {
        struct seek_arg sarg;
        int state = 0;
        sarg.io = arg.io;
        sarg.offset = offset;
        sarg.mode = SEEK_SET;
        rb_protect(seek_before_access, (VALUE)&sarg, &state);
        if (state) {
            rb_io_close(arg.io);
            rb_jump_tag(state);
        }
        if (arg.argc == 2) arg.argc = 1;
    }
    return rb_ensure(io_s_read, (VALUE)&arg, rb_io_close, arg.io);
}

/*
 *  call-seq:
 *     IO.binread(path, length = nil, offset = 0)    -> string or nil
 *
 *  Behaves like IO.read, except that the stream is opened in binary mode
 *  with ASCII-8BIT encoding.
 *
 *  When called from class \IO (but not subclasses of \IO),
 *  this method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 */

static VALUE
rb_io_s_binread(int argc, VALUE *argv, VALUE io)
{
    VALUE offset;
    struct foreach_arg arg;
    enum rb_io_mode fmode = FMODE_READABLE|FMODE_BINMODE;
    enum {
        oflags = O_RDONLY
#ifdef O_BINARY
                |O_BINARY
#endif
    };
    struct rb_io_encoding convconfig = {NULL, NULL, 0, Qnil};

    rb_scan_args(argc, argv, "12", NULL, NULL, &offset);
    FilePathValue(argv[0]);
    convconfig.enc = rb_ascii8bit_encoding();
    arg.io = rb_io_open_generic(io, argv[0], oflags, fmode, &convconfig, 0);
    if (NIL_P(arg.io)) return Qnil;
    arg.argv = argv+1;
    arg.argc = (argc > 1) ? 1 : 0;
    if (!NIL_P(offset)) {
        struct seek_arg sarg;
        int state = 0;
        sarg.io = arg.io;
        sarg.offset = offset;
        sarg.mode = SEEK_SET;
        rb_protect(seek_before_access, (VALUE)&sarg, &state);
        if (state) {
            rb_io_close(arg.io);
            rb_jump_tag(state);
        }
    }
    return rb_ensure(io_s_read, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
io_s_write0(VALUE v)
{
    struct write_arg *arg = (void *)v;
    return io_write(arg->io,arg->str,arg->nosync);
}

static VALUE
io_s_write(int argc, VALUE *argv, VALUE klass, int binary)
{
    VALUE string, offset, opt;
    struct foreach_arg arg;
    struct write_arg warg;

    rb_scan_args(argc, argv, "21:", NULL, &string, &offset, &opt);

    if (NIL_P(opt)) opt = rb_hash_new();
    else opt = rb_hash_dup(opt);


    if (NIL_P(rb_hash_aref(opt,sym_mode))) {
       int mode = O_WRONLY|O_CREAT;
#ifdef O_BINARY
       if (binary) mode |= O_BINARY;
#endif
       if (NIL_P(offset)) mode |= O_TRUNC;
       rb_hash_aset(opt,sym_mode,INT2NUM(mode));
    }
    open_key_args(klass, argc, argv, opt, &arg);

#ifndef O_BINARY
    if (binary) rb_io_binmode_m(arg.io);
#endif

    if (NIL_P(arg.io)) return Qnil;
    if (!NIL_P(offset)) {
       struct seek_arg sarg;
       int state = 0;
       sarg.io = arg.io;
       sarg.offset = offset;
       sarg.mode = SEEK_SET;
       rb_protect(seek_before_access, (VALUE)&sarg, &state);
       if (state) {
           rb_io_close(arg.io);
           rb_jump_tag(state);
       }
    }

    warg.io = arg.io;
    warg.str = string;
    warg.nosync = 0;

    return rb_ensure(io_s_write0, (VALUE)&warg, rb_io_close, arg.io);
}

/*
 *  call-seq:
 *    IO.write(path, data, offset = 0, **opts)    -> integer
 *
 *  Opens the stream, writes the given +data+ to it,
 *  and closes the stream; returns the number of bytes written.
 *
 *  When called from class \IO (but not subclasses of \IO),
 *  this method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 *  The first argument must be a string that is the path to a file.
 *
 *  With only argument +path+ given, writes the given +data+ to the file at that path:
 *
 *    IO.write('t.tmp', 'abc')    # => 3
 *    File.read('t.tmp')          # => "abc"
 *
 *  If +offset+ is zero (the default), the file is overwritten:
 *
 *    IO.write('t.tmp', 'A')      # => 1
 *    File.read('t.tmp')          # => "A"
 *
 *  If +offset+ in within the file content, the file is partly overwritten:
 *
 *    IO.write('t.tmp', 'abcdef') # => 3
 *    File.read('t.tmp')          # => "abcdef"
 *    # Offset within content.
 *    IO.write('t.tmp', '012', 2) # => 3
 *    File.read('t.tmp')          # => "ab012f"
 *
 *  If +offset+ is outside the file content,
 *  the file is padded with null characters <tt>"\u0000"</tt>:
 *
 *    IO.write('t.tmp', 'xyz', 10) # => 3
 *    File.read('t.tmp')           # => "ab012f\u0000\u0000\u0000\u0000xyz"
 *
 *  Optional keyword arguments +opts+ specify:
 *
 *  - {Open Options}[rdoc-ref:IO@Open+Options].
 *  - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 */

static VALUE
rb_io_s_write(int argc, VALUE *argv, VALUE io)
{
    return io_s_write(argc, argv, io, 0);
}

/*
 *  call-seq:
 *    IO.binwrite(path, string, offset = 0)    -> integer
 *
 *  Behaves like IO.write, except that the stream is opened in binary mode
 *  with ASCII-8BIT encoding.
 *
 *  When called from class \IO (but not subclasses of \IO),
 *  this method has potential security vulnerabilities if called with untrusted input;
 *  see {Command Injection}[rdoc-ref:command_injection.rdoc].
 *
 */

static VALUE
rb_io_s_binwrite(int argc, VALUE *argv, VALUE io)
{
    return io_s_write(argc, argv, io, 1);
}

struct copy_stream_struct {
    VALUE src;
    VALUE dst;
    rb_off_t copy_length; /* (rb_off_t)-1 if not specified */
    rb_off_t src_offset; /* (rb_off_t)-1 if not specified */

    rb_io_t *src_fptr;
    rb_io_t *dst_fptr;
    unsigned close_src : 1;
    unsigned close_dst : 1;
    int error_no;
    rb_off_t total;
    const char *syserr;
    const char *notimp;
    VALUE th;
    struct stat src_stat;
    struct stat dst_stat;
#ifdef HAVE_FCOPYFILE
    copyfile_state_t copyfile_state;
#endif
};

static void *
exec_interrupts(void *arg)
{
    VALUE th = (VALUE)arg;
    rb_thread_execute_interrupts(th);
    return NULL;
}

/*
 * returns TRUE if the preceding system call was interrupted
 * so we can continue.  If the thread was interrupted, we
 * reacquire the GVL to execute interrupts before continuing.
 */
static int
maygvl_copy_stream_continue_p(int has_gvl, struct copy_stream_struct *stp)
{
    switch (errno) {
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
        if (rb_thread_interrupted(stp->th)) {
            if (has_gvl)
                rb_thread_execute_interrupts(stp->th);
            else
                rb_thread_call_with_gvl(exec_interrupts, (void *)stp->th);
        }
        return TRUE;
    }
    return FALSE;
}

struct fiber_scheduler_wait_for_arguments {
    VALUE scheduler;

    rb_io_t *fptr;
    short events;

    VALUE result;
};

static void *
fiber_scheduler_wait_for(void * _arguments)
{
    struct fiber_scheduler_wait_for_arguments *arguments = (struct fiber_scheduler_wait_for_arguments *)_arguments;

    arguments->result = rb_fiber_scheduler_io_wait(arguments->scheduler, arguments->fptr->self, INT2NUM(arguments->events), RUBY_IO_TIMEOUT_DEFAULT);

    return NULL;
}

#if USE_POLL
#  define IOWAIT_SYSCALL "poll"
STATIC_ASSERT(pollin_expected, POLLIN == RB_WAITFD_IN);
STATIC_ASSERT(pollout_expected, POLLOUT == RB_WAITFD_OUT);
static int
nogvl_wait_for(VALUE th, rb_io_t *fptr, short events, struct timeval *timeout)
{
    VALUE scheduler = rb_fiber_scheduler_current_for_thread(th);
    if (scheduler != Qnil) {
        struct fiber_scheduler_wait_for_arguments args = {.scheduler = scheduler, .fptr = fptr, .events = events};
        rb_thread_call_with_gvl(fiber_scheduler_wait_for, &args);
        return RTEST(args.result);
    }

    int fd = fptr->fd;
    if (fd == -1) return 0;

    struct pollfd fds;

    fds.fd = fd;
    fds.events = events;

    int timeout_milliseconds = -1;

    if (timeout) {
        timeout_milliseconds = (int)(timeout->tv_sec * 1000) + (int)(timeout->tv_usec / 1000);
    }

    return poll(&fds, 1, timeout_milliseconds);
}
#else /* !USE_POLL */
#  define IOWAIT_SYSCALL "select"
static int
nogvl_wait_for(VALUE th, rb_io_t *fptr, short events, struct timeval *timeout)
{
    VALUE scheduler = rb_fiber_scheduler_current_for_thread(th);
    if (scheduler != Qnil) {
        struct fiber_scheduler_wait_for_arguments args = {.scheduler = scheduler, .fptr = fptr, .events = events};
        rb_thread_call_with_gvl(fiber_scheduler_wait_for, &args);
        return RTEST(args.result);
    }

    int fd = fptr->fd;

    if (fd == -1) {
        errno = EBADF;
        return -1;
    }

    rb_fdset_t fds;
    int ret;

    rb_fd_init(&fds);
    rb_fd_set(fd, &fds);

    switch (events) {
      case RB_WAITFD_IN:
        ret = rb_fd_select(fd + 1, &fds, 0, 0, timeout);
        break;
      case RB_WAITFD_OUT:
        ret = rb_fd_select(fd + 1, 0, &fds, 0, timeout);
        break;
      default:
        VM_UNREACHABLE(nogvl_wait_for);
    }

    rb_fd_term(&fds);

    // On timeout, this returns 0.
    return ret;
}
#endif /* !USE_POLL */

static int
maygvl_copy_stream_wait_read(int has_gvl, struct copy_stream_struct *stp)
{
    int ret;

    do {
        if (has_gvl) {
            ret = RB_NUM2INT(rb_io_wait(stp->src, RB_INT2NUM(RUBY_IO_READABLE), Qnil));
        }
        else {
            ret = nogvl_wait_for(stp->th, stp->src_fptr, RB_WAITFD_IN, NULL);
        }
    } while (ret < 0 && maygvl_copy_stream_continue_p(has_gvl, stp));

    if (ret < 0) {
        stp->syserr = IOWAIT_SYSCALL;
        stp->error_no = errno;
        return ret;
    }
    return 0;
}

static int
nogvl_copy_stream_wait_write(struct copy_stream_struct *stp)
{
    int ret;

    do {
        ret = nogvl_wait_for(stp->th, stp->dst_fptr, RB_WAITFD_OUT, NULL);
    } while (ret < 0 && maygvl_copy_stream_continue_p(0, stp));

    if (ret < 0) {
        stp->syserr = IOWAIT_SYSCALL;
        stp->error_no = errno;
        return ret;
    }
    return 0;
}

#ifdef USE_COPY_FILE_RANGE

static ssize_t
simple_copy_file_range(int in_fd, rb_off_t *in_offset, int out_fd, rb_off_t *out_offset, size_t count, unsigned int flags)
{
#ifdef HAVE_COPY_FILE_RANGE
    return copy_file_range(in_fd, in_offset, out_fd, out_offset, count, flags);
#else
    return syscall(__NR_copy_file_range, in_fd, in_offset, out_fd, out_offset, count, flags);
#endif
}

static int
nogvl_copy_file_range(struct copy_stream_struct *stp)
{
    ssize_t ss;
    rb_off_t src_size;
    rb_off_t copy_length, src_offset, *src_offset_ptr;

    if (!S_ISREG(stp->src_stat.st_mode))
        return 0;

    src_size = stp->src_stat.st_size;
    src_offset = stp->src_offset;
    if (src_offset >= (rb_off_t)0) {
        src_offset_ptr = &src_offset;
    }
    else {
        src_offset_ptr = NULL; /* if src_offset_ptr is NULL, then bytes are read from in_fd starting from the file offset */
    }

    copy_length = stp->copy_length;
    if (copy_length < (rb_off_t)0) {
        if (src_offset < (rb_off_t)0) {
            rb_off_t current_offset;
            errno = 0;
            current_offset = lseek(stp->src_fptr->fd, 0, SEEK_CUR);
            if (current_offset < (rb_off_t)0 && errno) {
                stp->syserr = "lseek";
                stp->error_no = errno;
                return (int)current_offset;
            }
            copy_length = src_size - current_offset;
        }
        else {
            copy_length = src_size - src_offset;
        }
    }

  retry_copy_file_range:
# if SIZEOF_OFF_T > SIZEOF_SIZE_T
    /* we are limited by the 32-bit ssize_t return value on 32-bit */
    ss = (copy_length > (rb_off_t)SSIZE_MAX) ? SSIZE_MAX : (ssize_t)copy_length;
# else
    ss = (ssize_t)copy_length;
# endif
    ss = simple_copy_file_range(stp->src_fptr->fd, src_offset_ptr, stp->dst_fptr->fd, NULL, ss, 0);
    if (0 < ss) {
        stp->total += ss;
        copy_length -= ss;
        if (0 < copy_length) {
            goto retry_copy_file_range;
        }
    }
    if (ss < 0) {
        if (maygvl_copy_stream_continue_p(0, stp)) {
            goto retry_copy_file_range;
        }
        switch (errno) {
          case EINVAL:
          case EPERM: /* copy_file_range(2) doesn't exist (may happen in
                         docker container) */
#ifdef ENOSYS
          case ENOSYS:
#endif
#ifdef EXDEV
          case EXDEV: /* in_fd and out_fd are not on the same filesystem */
#endif
            return 0;
          case EAGAIN:
#if EWOULDBLOCK != EAGAIN
          case EWOULDBLOCK:
#endif
            {
                int ret = nogvl_copy_stream_wait_write(stp);
                if (ret < 0) return ret;
            }
            goto retry_copy_file_range;
          case EBADF:
            {
                int e = errno;
                int flags = fcntl(stp->dst_fptr->fd, F_GETFL);

                if (flags != -1 && flags & O_APPEND) {
                    return 0;
                }
                errno = e;
            }
        }
        stp->syserr = "copy_file_range";
        stp->error_no = errno;
        return (int)ss;
    }
    return 1;
}
#endif

#ifdef HAVE_FCOPYFILE
static int
nogvl_fcopyfile(struct copy_stream_struct *stp)
{
    rb_off_t cur, ss = 0;
    const rb_off_t src_offset = stp->src_offset;
    int ret;

    if (stp->copy_length >= (rb_off_t)0) {
        /* copy_length can't be specified in fcopyfile(3) */
        return 0;
    }

    if (!S_ISREG(stp->src_stat.st_mode))
        return 0;

    if (!S_ISREG(stp->dst_stat.st_mode))
        return 0;
    if (lseek(stp->dst_fptr->fd, 0, SEEK_CUR) > (rb_off_t)0) /* if dst IO was already written */
        return 0;
    if (fcntl(stp->dst_fptr->fd, F_GETFL) & O_APPEND) {
        /* fcopyfile(3) appends src IO to dst IO and then truncates
         * dst IO to src IO's original size. */
        rb_off_t end = lseek(stp->dst_fptr->fd, 0, SEEK_END);
        lseek(stp->dst_fptr->fd, 0, SEEK_SET);
        if (end > (rb_off_t)0) return 0;
    }

    if (src_offset > (rb_off_t)0) {
        rb_off_t r;

        /* get current offset */
        errno = 0;
        cur = lseek(stp->src_fptr->fd, 0, SEEK_CUR);
        if (cur < (rb_off_t)0 && errno) {
            stp->error_no = errno;
            return 1;
        }

        errno = 0;
        r = lseek(stp->src_fptr->fd, src_offset, SEEK_SET);
        if (r < (rb_off_t)0 && errno) {
            stp->error_no = errno;
            return 1;
        }
    }

    stp->copyfile_state = copyfile_state_alloc(); /* this will be freed by copy_stream_finalize() */
    ret = fcopyfile(stp->src_fptr->fd, stp->dst_fptr->fd, stp->copyfile_state, COPYFILE_DATA);
    copyfile_state_get(stp->copyfile_state, COPYFILE_STATE_COPIED, &ss); /* get copied bytes */

    if (ret == 0) { /* success */
        stp->total = ss;
        if (src_offset > (rb_off_t)0) {
            rb_off_t r;
            errno = 0;
            /* reset offset */
            r = lseek(stp->src_fptr->fd, cur, SEEK_SET);
            if (r < (rb_off_t)0 && errno) {
                stp->error_no = errno;
                return 1;
            }
        }
    }
    else {
        switch (errno) {
          case ENOTSUP:
          case EPERM:
          case EINVAL:
            return 0;
        }
        stp->syserr = "fcopyfile";
        stp->error_no = errno;
        return (int)ret;
    }
    return 1;
}
#endif

#ifdef HAVE_SENDFILE

# ifdef __linux__
#  define USE_SENDFILE

#  ifdef HAVE_SYS_SENDFILE_H
#   include <sys/sendfile.h>
#  endif

static ssize_t
simple_sendfile(int out_fd, int in_fd, rb_off_t *offset, rb_off_t count)
{
    return sendfile(out_fd, in_fd, offset, (size_t)count);
}

# elif 0 /* defined(__FreeBSD__) || defined(__DragonFly__) */ || defined(__APPLE__)
/* This runs on FreeBSD8.1 r30210, but sendfiles blocks its execution
 * without cpuset -l 0.
 */
#  define USE_SENDFILE

static ssize_t
simple_sendfile(int out_fd, int in_fd, rb_off_t *offset, rb_off_t count)
{
    int r;
    rb_off_t pos = offset ? *offset : lseek(in_fd, 0, SEEK_CUR);
    rb_off_t sbytes;
#  ifdef __APPLE__
    r = sendfile(in_fd, out_fd, pos, &count, NULL, 0);
    sbytes = count;
#  else
    r = sendfile(in_fd, out_fd, pos, (size_t)count, NULL, &sbytes, 0);
#  endif
    if (r != 0 && sbytes == 0) return r;
    if (offset) {
        *offset += sbytes;
    }
    else {
        lseek(in_fd, sbytes, SEEK_CUR);
    }
    return (ssize_t)sbytes;
}

# endif

#endif

#ifdef USE_SENDFILE
static int
nogvl_copy_stream_sendfile(struct copy_stream_struct *stp)
{
    ssize_t ss;
    rb_off_t src_size;
    rb_off_t copy_length;
    rb_off_t src_offset;
    int use_pread;

    if (!S_ISREG(stp->src_stat.st_mode))
        return 0;

    src_size = stp->src_stat.st_size;
#ifndef __linux__
    if ((stp->dst_stat.st_mode & S_IFMT) != S_IFSOCK)
        return 0;
#endif

    src_offset = stp->src_offset;
    use_pread = src_offset >= (rb_off_t)0;

    copy_length = stp->copy_length;
    if (copy_length < (rb_off_t)0) {
        if (use_pread)
            copy_length = src_size - src_offset;
        else {
            rb_off_t cur;
            errno = 0;
            cur = lseek(stp->src_fptr->fd, 0, SEEK_CUR);
            if (cur < (rb_off_t)0 && errno) {
                stp->syserr = "lseek";
                stp->error_no = errno;
                return (int)cur;
            }
            copy_length = src_size - cur;
        }
    }

  retry_sendfile:
# if SIZEOF_OFF_T > SIZEOF_SIZE_T
    /* we are limited by the 32-bit ssize_t return value on 32-bit */
    ss = (copy_length > (rb_off_t)SSIZE_MAX) ? SSIZE_MAX : (ssize_t)copy_length;
# else
    ss = (ssize_t)copy_length;
# endif
    if (use_pread) {
        ss = simple_sendfile(stp->dst_fptr->fd, stp->src_fptr->fd, &src_offset, ss);
    }
    else {
        ss = simple_sendfile(stp->dst_fptr->fd, stp->src_fptr->fd, NULL, ss);
    }
    if (0 < ss) {
        stp->total += ss;
        copy_length -= ss;
        if (0 < copy_length) {
            goto retry_sendfile;
        }
    }
    if (ss < 0) {
        if (maygvl_copy_stream_continue_p(0, stp))
            goto retry_sendfile;
        switch (errno) {
          case EINVAL:
#ifdef ENOSYS
          case ENOSYS:
#endif
#ifdef EOPNOTSUP
          /* some RedHat kernels may return EOPNOTSUP on an NFS mount.
             see also: [Feature #16965] */
          case EOPNOTSUP:
#endif
            return 0;
          case EAGAIN:
#if EWOULDBLOCK != EAGAIN
          case EWOULDBLOCK:
#endif
            {
                int ret;
#ifndef __linux__
               /*
                * Linux requires stp->src_fptr->fd to be a mmap-able (regular) file,
                * select() reports regular files to always be "ready", so
                * there is no need to select() on it.
                * Other OSes may have the same limitation for sendfile() which
                * allow us to bypass maygvl_copy_stream_wait_read()...
                */
                ret = maygvl_copy_stream_wait_read(0, stp);
                if (ret < 0) return ret;
#endif
                ret = nogvl_copy_stream_wait_write(stp);
                if (ret < 0) return ret;
            }
            goto retry_sendfile;
        }
        stp->syserr = "sendfile";
        stp->error_no = errno;
        return (int)ss;
    }
    return 1;
}
#endif

static ssize_t
maygvl_read(int has_gvl, rb_io_t *fptr, void *buf, size_t count)
{
    if (has_gvl)
        return rb_io_read_memory(fptr, buf, count);
    else
        return read(fptr->fd, buf, count);
}

static ssize_t
maygvl_copy_stream_read(int has_gvl, struct copy_stream_struct *stp, char *buf, size_t len, rb_off_t offset)
{
    ssize_t ss;
  retry_read:
    if (offset < (rb_off_t)0) {
        ss = maygvl_read(has_gvl, stp->src_fptr, buf, len);
    }
    else {
        ss = pread(stp->src_fptr->fd, buf, len, offset);
    }
    if (ss == 0) {
        return 0;
    }
    if (ss < 0) {
        if (maygvl_copy_stream_continue_p(has_gvl, stp))
            goto retry_read;
        switch (errno) {
          case EAGAIN:
#if EWOULDBLOCK != EAGAIN
          case EWOULDBLOCK:
#endif
            {
                int ret = maygvl_copy_stream_wait_read(has_gvl, stp);
                if (ret < 0) return ret;
            }
            goto retry_read;
#ifdef ENOSYS
          case ENOSYS:
            stp->notimp = "pread";
            return ss;
#endif
        }
        stp->syserr = offset < (rb_off_t)0 ?  "read" : "pread";
        stp->error_no = errno;
    }
    return ss;
}

static int
nogvl_copy_stream_write(struct copy_stream_struct *stp, char *buf, size_t len)
{
    ssize_t ss;
    int off = 0;
    while (len) {
        ss = write(stp->dst_fptr->fd, buf+off, len);
        if (ss < 0) {
            if (maygvl_copy_stream_continue_p(0, stp))
                continue;
            if (io_again_p(errno)) {
                int ret = nogvl_copy_stream_wait_write(stp);
                if (ret < 0) return ret;
                continue;
            }
            stp->syserr = "write";
            stp->error_no = errno;
            return (int)ss;
        }
        off += (int)ss;
        len -= (int)ss;
        stp->total += ss;
    }
    return 0;
}

static void
nogvl_copy_stream_read_write(struct copy_stream_struct *stp)
{
    char buf[1024*16];
    size_t len;
    ssize_t ss;
    int ret;
    rb_off_t copy_length;
    rb_off_t src_offset;
    int use_eof;
    int use_pread;

    copy_length = stp->copy_length;
    use_eof = copy_length < (rb_off_t)0;
    src_offset = stp->src_offset;
    use_pread = src_offset >= (rb_off_t)0;

    if (use_pread && stp->close_src) {
        rb_off_t r;
        errno = 0;
        r = lseek(stp->src_fptr->fd, src_offset, SEEK_SET);
        if (r < (rb_off_t)0 && errno) {
            stp->syserr = "lseek";
            stp->error_no = errno;
            return;
        }
        src_offset = (rb_off_t)-1;
        use_pread = 0;
    }

    while (use_eof || 0 < copy_length) {
        if (!use_eof && copy_length < (rb_off_t)sizeof(buf)) {
            len = (size_t)copy_length;
        }
        else {
            len = sizeof(buf);
        }
        if (use_pread) {
            ss = maygvl_copy_stream_read(0, stp, buf, len, src_offset);
            if (0 < ss)
                src_offset += ss;
        }
        else {
            ss = maygvl_copy_stream_read(0, stp, buf, len, (rb_off_t)-1);
        }
        if (ss <= 0) /* EOF or error */
            return;

        ret = nogvl_copy_stream_write(stp, buf, ss);
        if (ret < 0)
            return;

        if (!use_eof)
            copy_length -= ss;
    }
}

static void *
nogvl_copy_stream_func(void *arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;
#if defined(USE_SENDFILE) || defined(USE_COPY_FILE_RANGE) || defined(HAVE_FCOPYFILE)
    int ret;
#endif

#ifdef USE_COPY_FILE_RANGE
    ret = nogvl_copy_file_range(stp);
    if (ret != 0)
        goto finish; /* error or success */
#endif

#ifdef HAVE_FCOPYFILE
    ret = nogvl_fcopyfile(stp);
    if (ret != 0)
        goto finish; /* error or success */
#endif

#ifdef USE_SENDFILE
    ret = nogvl_copy_stream_sendfile(stp);
    if (ret != 0)
        goto finish; /* error or success */
#endif

    nogvl_copy_stream_read_write(stp);

#if defined(USE_SENDFILE) || defined(USE_COPY_FILE_RANGE) || defined(HAVE_FCOPYFILE)
  finish:
#endif
    return 0;
}

static VALUE
copy_stream_fallback_body(VALUE arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;
    const int buflen = 16*1024;
    VALUE n;
    VALUE buf = rb_str_buf_new(buflen);
    rb_off_t rest = stp->copy_length;
    rb_off_t off = stp->src_offset;
    ID read_method = id_readpartial;

    if (!stp->src_fptr) {
        if (!rb_respond_to(stp->src, read_method)) {
            read_method = id_read;
        }
    }

    while (1) {
        long numwrote;
        long l;
        rb_str_make_independent(buf);
        if (stp->copy_length < (rb_off_t)0) {
            l = buflen;
        }
        else {
            if (rest == 0) {
                rb_str_resize(buf, 0);
                break;
            }
            l = buflen < rest ? buflen : (long)rest;
        }
        if (!stp->src_fptr) {
            VALUE rc = rb_funcall(stp->src, read_method, 2, INT2FIX(l), buf);

            if (read_method == id_read && NIL_P(rc))
                break;
        }
        else {
            ssize_t ss;
            rb_str_resize(buf, buflen);
            ss = maygvl_copy_stream_read(1, stp, RSTRING_PTR(buf), l, off);
            rb_str_resize(buf, ss > 0 ? ss : 0);
            if (ss < 0)
                return Qnil;
            if (ss == 0)
                rb_eof_error();
            if (off >= (rb_off_t)0)
                off += ss;
        }
        n = rb_io_write(stp->dst, buf);
        numwrote = NUM2LONG(n);
        stp->total += numwrote;
        rest -= numwrote;
        if (read_method == id_read && RSTRING_LEN(buf) == 0) {
            break;
        }
    }

    return Qnil;
}

static VALUE
copy_stream_fallback(struct copy_stream_struct *stp)
{
    if (!stp->src_fptr && stp->src_offset >= (rb_off_t)0) {
        rb_raise(rb_eArgError, "cannot specify src_offset for non-IO");
    }
    rb_rescue2(copy_stream_fallback_body, (VALUE)stp,
               (VALUE (*) (VALUE, VALUE))0, (VALUE)0,
               rb_eEOFError, (VALUE)0);
    return Qnil;
}

static VALUE
copy_stream_body(VALUE arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;
    VALUE src_io = stp->src, dst_io = stp->dst;
    const int common_oflags = 0
#ifdef O_NOCTTY
        | O_NOCTTY
#endif
        ;

    stp->th = rb_thread_current();

    stp->total = 0;

    if (src_io == argf ||
        !(RB_TYPE_P(src_io, T_FILE) ||
          RB_TYPE_P(src_io, T_STRING) ||
          rb_respond_to(src_io, rb_intern("to_path")))) {
        stp->src_fptr = NULL;
    }
    else {
        int stat_ret;
        VALUE tmp_io = rb_io_check_io(src_io);
        if (!NIL_P(tmp_io)) {
            src_io = tmp_io;
        }
        else if (!RB_TYPE_P(src_io, T_FILE)) {
            VALUE args[2];
            FilePathValue(src_io);
            args[0] = src_io;
            args[1] = INT2NUM(O_RDONLY|common_oflags);
            src_io = rb_class_new_instance(2, args, rb_cFile);
            stp->src = src_io;
            stp->close_src = 1;
        }
        RB_IO_POINTER(src_io, stp->src_fptr);
        rb_io_check_byte_readable(stp->src_fptr);

        stat_ret = fstat(stp->src_fptr->fd, &stp->src_stat);
        if (stat_ret < 0) {
            stp->syserr = "fstat";
            stp->error_no = errno;
            return Qnil;
        }
    }

    if (dst_io == argf ||
        !(RB_TYPE_P(dst_io, T_FILE) ||
          RB_TYPE_P(dst_io, T_STRING) ||
          rb_respond_to(dst_io, rb_intern("to_path")))) {
        stp->dst_fptr = NULL;
    }
    else {
        int stat_ret;
        VALUE tmp_io = rb_io_check_io(dst_io);
        if (!NIL_P(tmp_io)) {
            dst_io = GetWriteIO(tmp_io);
        }
        else if (!RB_TYPE_P(dst_io, T_FILE)) {
            VALUE args[3];
            FilePathValue(dst_io);
            args[0] = dst_io;
            args[1] = INT2NUM(O_WRONLY|O_CREAT|O_TRUNC|common_oflags);
            args[2] = INT2FIX(0666);
            dst_io = rb_class_new_instance(3, args, rb_cFile);
            stp->dst = dst_io;
            stp->close_dst = 1;
        }
        else {
            dst_io = GetWriteIO(dst_io);
            stp->dst = dst_io;
        }
        RB_IO_POINTER(dst_io, stp->dst_fptr);
        rb_io_check_writable(stp->dst_fptr);

        stat_ret = fstat(stp->dst_fptr->fd, &stp->dst_stat);
        if (stat_ret < 0) {
            stp->syserr = "fstat";
            stp->error_no = errno;
            return Qnil;
        }
    }

#ifdef O_BINARY
    if (stp->src_fptr)
        SET_BINARY_MODE_WITH_SEEK_CUR(stp->src_fptr);
#endif
    if (stp->dst_fptr)
        io_ascii8bit_binmode(stp->dst_fptr);

    if (stp->src_offset < (rb_off_t)0 && stp->src_fptr && stp->src_fptr->rbuf.len) {
        size_t len = stp->src_fptr->rbuf.len;
        VALUE str;
        if (stp->copy_length >= (rb_off_t)0 && stp->copy_length < (rb_off_t)len) {
            len = (size_t)stp->copy_length;
        }
        str = rb_str_buf_new(len);
        rb_str_resize(str,len);
        read_buffered_data(RSTRING_PTR(str), len, stp->src_fptr);
        if (stp->dst_fptr) { /* IO or filename */
            if (io_binwrite(RSTRING_PTR(str), RSTRING_LEN(str), stp->dst_fptr, 0) < 0)
                rb_sys_fail_on_write(stp->dst_fptr);
        }
        else /* others such as StringIO */
            rb_io_write(dst_io, str);
        rb_str_resize(str, 0);
        stp->total += len;
        if (stp->copy_length >= (rb_off_t)0)
            stp->copy_length -= len;
    }

    if (stp->dst_fptr && io_fflush(stp->dst_fptr) < 0) {
        rb_raise(rb_eIOError, "flush failed");
    }

    if (stp->copy_length == 0)
        return Qnil;

    if (stp->src_fptr == NULL || stp->dst_fptr == NULL) {
        return copy_stream_fallback(stp);
    }

    IO_WITHOUT_GVL(nogvl_copy_stream_func, stp);
    return Qnil;
}

static VALUE
copy_stream_finalize(VALUE arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;

#ifdef HAVE_FCOPYFILE
    if (stp->copyfile_state) {
        copyfile_state_free(stp->copyfile_state);
    }
#endif

    if (stp->close_src) {
        rb_io_close_m(stp->src);
    }
    if (stp->close_dst) {
        rb_io_close_m(stp->dst);
    }
    if (stp->syserr) {
        rb_syserr_fail(stp->error_no, stp->syserr);
    }
    if (stp->notimp) {
        rb_raise(rb_eNotImpError, "%s() not implemented", stp->notimp);
    }
    return Qnil;
}

/*
 *  call-seq:
 *    IO.copy_stream(src, dst, src_length = nil, src_offset = 0) -> integer
 *
 *  Copies from the given +src+ to the given +dst+,
 *  returning the number of bytes copied.
 *
 *  - The given +src+ must be one of the following:
 *
 *    - The path to a readable file, from which source data is to be read.
 *    - An \IO-like object, opened for reading and capable of responding
 *      to method +:readpartial+ or method +:read+.
 *
 *  - The given +dst+ must be one of the following:
 *
 *    - The path to a writable file, to which data is to be written.
 *    - An \IO-like object, opened for writing and capable of responding
 *      to method +:write+.
 *
 *  The examples here use file <tt>t.txt</tt> as source:
 *
 *    File.read('t.txt')
 *    # => "First line\nSecond line\n\nThird line\nFourth line\n"
 *    File.read('t.txt').size # => 47
 *
 *  If only arguments +src+ and +dst+ are given,
 *  the entire source stream is copied:
 *
 *    # Paths.
 *    IO.copy_stream('t.txt', 't.tmp')  # => 47
 *
 *    # IOs (recall that a File is also an IO).
 *    src_io = File.open('t.txt', 'r') # => #<File:t.txt>
 *    dst_io = File.open('t.tmp', 'w') # => #<File:t.tmp>
 *    IO.copy_stream(src_io, dst_io)   # => 47
 *    src_io.close
 *    dst_io.close
 *
 *  With argument +src_length+ a non-negative integer,
 *  no more than that many bytes are copied:
 *
 *    IO.copy_stream('t.txt', 't.tmp', 10) # => 10
 *    File.read('t.tmp')                   # => "First line"
 *
 *  With argument +src_offset+ also given,
 *  the source stream is read beginning at that offset:
 *
 *    IO.copy_stream('t.txt', 't.tmp', 11, 11) # => 11
 *    IO.read('t.tmp')                         # => "Second line"
 *
 */
static VALUE
rb_io_s_copy_stream(int argc, VALUE *argv, VALUE io)
{
    VALUE src, dst, length, src_offset;
    struct copy_stream_struct st;

    MEMZERO(&st, struct copy_stream_struct, 1);

    rb_scan_args(argc, argv, "22", &src, &dst, &length, &src_offset);

    st.src = src;
    st.dst = dst;

    st.src_fptr = NULL;
    st.dst_fptr = NULL;

    if (NIL_P(length))
        st.copy_length = (rb_off_t)-1;
    else
        st.copy_length = NUM2OFFT(length);

    if (NIL_P(src_offset))
        st.src_offset = (rb_off_t)-1;
    else
        st.src_offset = NUM2OFFT(src_offset);

    rb_ensure(copy_stream_body, (VALUE)&st, copy_stream_finalize, (VALUE)&st);

    return OFFT2NUM(st.total);
}

/*
 *  call-seq:
 *    external_encoding -> encoding or nil
 *
 *  Returns the Encoding object that represents the encoding of the stream,
 *  or +nil+ if the stream is in write mode and no encoding is specified.
 *
 *  See {Encodings}[rdoc-ref:File@Encodings].
 *
 */

static VALUE
rb_io_external_encoding(VALUE io)
{
    rb_io_t *fptr = RFILE(rb_io_taint_check(io))->fptr;

    if (fptr->encs.enc2) {
        return rb_enc_from_encoding(fptr->encs.enc2);
    }
    if (fptr->mode & FMODE_WRITABLE) {
        if (fptr->encs.enc)
            return rb_enc_from_encoding(fptr->encs.enc);
        return Qnil;
    }
    return rb_enc_from_encoding(io_read_encoding(fptr));
}

/*
 *  call-seq:
 *    internal_encoding -> encoding or nil
 *
 *  Returns the Encoding object that represents the encoding of the internal string,
 *  if conversion is specified,
 *  or +nil+ otherwise.
 *
 *  See {Encodings}[rdoc-ref:File@Encodings].
 *
 */

static VALUE
rb_io_internal_encoding(VALUE io)
{
    rb_io_t *fptr = RFILE(rb_io_taint_check(io))->fptr;

    if (!fptr->encs.enc2) return Qnil;
    return rb_enc_from_encoding(io_read_encoding(fptr));
}

/*
 *  call-seq:
 *    set_encoding(ext_enc)                   -> self
 *    set_encoding(ext_enc, int_enc, **enc_opts)  -> self
 *    set_encoding('ext_enc:int_enc', **enc_opts) -> self
 *
 *  See {Encodings}[rdoc-ref:File@Encodings].
 *
 *  Argument +ext_enc+, if given, must be an Encoding object
 *  or a String with the encoding name;
 *  it is assigned as the encoding for the stream.
 *
 *  Argument +int_enc+, if given, must be an Encoding object
 *  or a String with the encoding name;
 *  it is assigned as the encoding for the internal string.
 *
 *  Argument <tt>'ext_enc:int_enc'</tt>, if given, is a string
 *  containing two colon-separated encoding names;
 *  corresponding Encoding objects are assigned as the external
 *  and internal encodings for the stream.
 *
 *  If the external encoding of a string is binary/ASCII-8BIT,
 *  the internal encoding of the string is set to nil, since no
 *  transcoding is needed.
 *
 *  Optional keyword arguments +enc_opts+ specify
 *  {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
 *
 */

static VALUE
rb_io_set_encoding(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    VALUE v1, v2, opt;

    if (!RB_TYPE_P(io, T_FILE)) {
        return forward(io, id_set_encoding, argc, argv);
    }

    argc = rb_scan_args(argc, argv, "11:", &v1, &v2, &opt);
    GetOpenFile(io, fptr);
    io_encoding_set(fptr, v1, v2, opt);
    return io;
}

void
rb_stdio_set_default_encoding(void)
{
    VALUE val = Qnil;

#ifdef _WIN32
    if (isatty(fileno(stdin))) {
        rb_encoding *external = rb_locale_encoding();
        rb_encoding *internal = rb_default_internal_encoding();
        if (!internal) internal = rb_default_external_encoding();
        io_encoding_set(RFILE(rb_stdin)->fptr,
                        rb_enc_from_encoding(external),
                        rb_enc_from_encoding(internal),
                        Qnil);
    }
    else
#endif
    rb_io_set_encoding(1, &val, rb_stdin);
    rb_io_set_encoding(1, &val, rb_stdout);
    rb_io_set_encoding(1, &val, rb_stderr);
}

static inline int
global_argf_p(VALUE arg)
{
    return arg == argf;
}

typedef VALUE (*argf_encoding_func)(VALUE io);

static VALUE
argf_encoding(VALUE argf, argf_encoding_func func)
{
    if (!RTEST(ARGF.current_file)) {
        return rb_enc_default_external();
    }
    return func(rb_io_check_io(ARGF.current_file));
}

/*
 *  call-seq:
 *     ARGF.external_encoding   -> encoding
 *
 *  Returns the external encoding for files read from ARGF as an Encoding
 *  object. The external encoding is the encoding of the text as stored in a
 *  file. Contrast with ARGF.internal_encoding, which is the encoding used to
 *  represent this text within Ruby.
 *
 *  To set the external encoding use ARGF.set_encoding.
 *
 *  For example:
 *
 *     ARGF.external_encoding  #=>  #<Encoding:UTF-8>
 *
 */
static VALUE
argf_external_encoding(VALUE argf)
{
    return argf_encoding(argf, rb_io_external_encoding);
}

/*
 *  call-seq:
 *     ARGF.internal_encoding   -> encoding
 *
 *  Returns the internal encoding for strings read from ARGF as an
 *  Encoding object.
 *
 *  If ARGF.set_encoding has been called with two encoding names, the second
 *  is returned. Otherwise, if +Encoding.default_external+ has been set, that
 *  value is returned. Failing that, if a default external encoding was
 *  specified on the command-line, that value is used. If the encoding is
 *  unknown, +nil+ is returned.
 */
static VALUE
argf_internal_encoding(VALUE argf)
{
    return argf_encoding(argf, rb_io_internal_encoding);
}

/*
 *  call-seq:
 *     ARGF.set_encoding(ext_enc)                -> ARGF
 *     ARGF.set_encoding("ext_enc:int_enc")      -> ARGF
 *     ARGF.set_encoding(ext_enc, int_enc)       -> ARGF
 *     ARGF.set_encoding("ext_enc:int_enc", opt) -> ARGF
 *     ARGF.set_encoding(ext_enc, int_enc, opt)  -> ARGF
 *
 *  If single argument is specified, strings read from ARGF are tagged with
 *  the encoding specified.
 *
 *  If two encoding names separated by a colon are given, e.g. "ascii:utf-8",
 *  the read string is converted from the first encoding (external encoding)
 *  to the second encoding (internal encoding), then tagged with the second
 *  encoding.
 *
 *  If two arguments are specified, they must be encoding objects or encoding
 *  names. Again, the first specifies the external encoding; the second
 *  specifies the internal encoding.
 *
 *  If the external encoding and the internal encoding are specified, the
 *  optional Hash argument can be used to adjust the conversion process. The
 *  structure of this hash is explained in the String#encode documentation.
 *
 *  For example:
 *
 *      ARGF.set_encoding('ascii')         # Tag the input as US-ASCII text
 *      ARGF.set_encoding(Encoding::UTF_8) # Tag the input as UTF-8 text
 *      ARGF.set_encoding('utf-8','ascii') # Transcode the input from US-ASCII
 *                                         # to UTF-8.
 */
static VALUE
argf_set_encoding(int argc, VALUE *argv, VALUE argf)
{
    rb_io_t *fptr;

    if (!next_argv()) {
        rb_raise(rb_eArgError, "no stream to set encoding");
    }
    rb_io_set_encoding(argc, argv, ARGF.current_file);
    GetOpenFile(ARGF.current_file, fptr);
    ARGF.encs = fptr->encs;
    return argf;
}

/*
 *  call-seq:
 *     ARGF.tell  -> Integer
 *     ARGF.pos   -> Integer
 *
 *  Returns the current offset (in bytes) of the current file in ARGF.
 *
 *     ARGF.pos    #=> 0
 *     ARGF.gets   #=> "This is line one\n"
 *     ARGF.pos    #=> 17
 *
 */
static VALUE
argf_tell(VALUE argf)
{
    if (!next_argv()) {
        rb_raise(rb_eArgError, "no stream to tell");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_tell(ARGF.current_file);
}

/*
 *  call-seq:
 *     ARGF.seek(amount, whence=IO::SEEK_SET)  -> 0
 *
 *  Seeks to offset _amount_ (an Integer) in the ARGF stream according to
 *  the value of _whence_. See IO#seek for further details.
 */
static VALUE
argf_seek_m(int argc, VALUE *argv, VALUE argf)
{
    if (!next_argv()) {
        rb_raise(rb_eArgError, "no stream to seek");
    }
    ARGF_FORWARD(argc, argv);
    return rb_io_seek_m(argc, argv, ARGF.current_file);
}

/*
 *  call-seq:
 *     ARGF.pos = position  -> Integer
 *
 *  Seeks to the position given by _position_ (in bytes) in ARGF.
 *
 *  For example:
 *
 *      ARGF.pos = 17
 *      ARGF.gets   #=> "This is line two\n"
 */
static VALUE
argf_set_pos(VALUE argf, VALUE offset)
{
    if (!next_argv()) {
        rb_raise(rb_eArgError, "no stream to set position");
    }
    ARGF_FORWARD(1, &offset);
    return rb_io_set_pos(ARGF.current_file, offset);
}

/*
 *  call-seq:
 *     ARGF.rewind   -> 0
 *
 *  Positions the current file to the beginning of input, resetting
 *  ARGF.lineno to zero.
 *
 *     ARGF.readline   #=> "This is line one\n"
 *     ARGF.rewind     #=> 0
 *     ARGF.lineno     #=> 0
 *     ARGF.readline   #=> "This is line one\n"
 */
static VALUE
argf_rewind(VALUE argf)
{
    VALUE ret;
    int old_lineno;

    if (!next_argv()) {
        rb_raise(rb_eArgError, "no stream to rewind");
    }
    ARGF_FORWARD(0, 0);
    old_lineno = RFILE(ARGF.current_file)->fptr->lineno;
    ret = rb_io_rewind(ARGF.current_file);
    if (!global_argf_p(argf)) {
        ARGF.last_lineno = ARGF.lineno -= old_lineno;
    }
    return ret;
}

/*
 *  call-seq:
 *     ARGF.fileno    -> integer
 *     ARGF.to_i      -> integer
 *
 *  Returns an integer representing the numeric file descriptor for
 *  the current file. Raises an ArgumentError if there isn't a current file.
 *
 *     ARGF.fileno    #=> 3
 */
static VALUE
argf_fileno(VALUE argf)
{
    if (!next_argv()) {
        rb_raise(rb_eArgError, "no stream");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_fileno(ARGF.current_file);
}

/*
 *  call-seq:
 *     ARGF.to_io     -> IO
 *
 *  Returns an IO object representing the current file. This will be a
 *  File object unless the current file is a stream such as STDIN.
 *
 *  For example:
 *
 *     ARGF.to_io    #=> #<File:glark.txt>
 *     ARGF.to_io    #=> #<IO:<STDIN>>
 */
static VALUE
argf_to_io(VALUE argf)
{
    next_argv();
    ARGF_FORWARD(0, 0);
    return ARGF.current_file;
}

/*
 *  call-seq:
 *     ARGF.eof?  -> true or false
 *     ARGF.eof   -> true or false
 *
 *  Returns true if the current file in ARGF is at end of file, i.e. it has
 *  no data to read. The stream must be opened for reading or an IOError
 *  will be raised.
 *
 *     $ echo "eof" | ruby argf.rb
 *
 *     ARGF.eof?                 #=> false
 *     3.times { ARGF.readchar }
 *     ARGF.eof?                 #=> false
 *     ARGF.readchar             #=> "\n"
 *     ARGF.eof?                 #=> true
 */

static VALUE
argf_eof(VALUE argf)
{
    next_argv();
    if (RTEST(ARGF.current_file)) {
        if (ARGF.init_p == 0) return Qtrue;
        next_argv();
        ARGF_FORWARD(0, 0);
        if (rb_io_eof(ARGF.current_file)) {
            return Qtrue;
        }
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     ARGF.read([length [, outbuf]])    -> string, outbuf, or nil
 *
 *  Reads _length_ bytes from ARGF. The files named on the command line
 *  are concatenated and treated as a single file by this method, so when
 *  called without arguments the contents of this pseudo file are returned in
 *  their entirety.
 *
 *  _length_ must be a non-negative integer or +nil+.
 *
 *  If _length_ is a positive integer, +read+ tries to read
 *  _length_ bytes without any conversion (binary mode).
 *  It returns +nil+ if an EOF is encountered before anything can be read.
 *  Fewer than _length_ bytes are returned if an EOF is encountered during
 *  the read.
 *  In the case of an integer _length_, the resulting string is always
 *  in ASCII-8BIT encoding.
 *
 *  If _length_ is omitted or is +nil+, it reads until EOF
 *  and the encoding conversion is applied, if applicable.
 *  A string is returned even if EOF is encountered before any data is read.
 *
 *  If _length_ is zero, it returns an empty string (<code>""</code>).
 *
 *  If the optional _outbuf_ argument is present,
 *  it must reference a String, which will receive the data.
 *  The _outbuf_ will contain only the received data after the method call
 *  even if it is not empty at the beginning.
 *
 *  For example:
 *
 *     $ echo "small" > small.txt
 *     $ echo "large" > large.txt
 *     $ ./glark.rb small.txt large.txt
 *
 *     ARGF.read      #=> "small\nlarge"
 *     ARGF.read(200) #=> "small\nlarge"
 *     ARGF.read(2)   #=> "sm"
 *     ARGF.read(0)   #=> ""
 *
 *  Note that this method behaves like the fread() function in C.
 *  This means it retries to invoke read(2) system calls to read data
 *  with the specified length.
 *  If you need the behavior like a single read(2) system call,
 *  consider ARGF#readpartial or ARGF#read_nonblock.
 */

static VALUE
argf_read(int argc, VALUE *argv, VALUE argf)
{
    VALUE tmp, str, length;
    long len = 0;

    rb_scan_args(argc, argv, "02", &length, &str);
    if (!NIL_P(length)) {
        len = NUM2LONG(argv[0]);
    }
    if (!NIL_P(str)) {
        StringValue(str);
        rb_str_resize(str,0);
        argv[1] = Qnil;
    }

  retry:
    if (!next_argv()) {
        return str;
    }
    if (ARGF_GENERIC_INPUT_P()) {
        tmp = argf_forward(argc, argv, argf);
    }
    else {
        tmp = io_read(argc, argv, ARGF.current_file);
    }
    if (NIL_P(str)) str = tmp;
    else if (!NIL_P(tmp)) rb_str_append(str, tmp);
    if (NIL_P(tmp) || NIL_P(length)) {
        if (ARGF.next_p != -1) {
            argf_close(argf);
            ARGF.next_p = 1;
            goto retry;
        }
    }
    else if (argc >= 1) {
        long slen = RSTRING_LEN(str);
        if (slen < len) {
            argv[0] = LONG2NUM(len - slen);
            goto retry;
        }
    }
    return str;
}

struct argf_call_arg {
    int argc;
    VALUE *argv;
    VALUE argf;
};

static VALUE
argf_forward_call(VALUE arg)
{
    struct argf_call_arg *p = (struct argf_call_arg *)arg;
    argf_forward(p->argc, p->argv, p->argf);
    return Qnil;
}

static VALUE argf_getpartial(int argc, VALUE *argv, VALUE argf, VALUE opts,
                             int nonblock);

/*
 *  call-seq:
 *     ARGF.readpartial(maxlen)              -> string
 *     ARGF.readpartial(maxlen, outbuf)      -> outbuf
 *
 *  Reads at most _maxlen_ bytes from the ARGF stream.
 *
 *  If the optional _outbuf_ argument is present,
 *  it must reference a String, which will receive the data.
 *  The _outbuf_ will contain only the received data after the method call
 *  even if it is not empty at the beginning.
 *
 *  It raises EOFError on end of ARGF stream.
 *  Since ARGF stream is a concatenation of multiple files,
 *  internally EOF is occur for each file.
 *  ARGF.readpartial returns empty strings for EOFs except the last one and
 *  raises EOFError for the last one.
 *
 */

static VALUE
argf_readpartial(int argc, VALUE *argv, VALUE argf)
{
    return argf_getpartial(argc, argv, argf, Qnil, 0);
}

/*
 *  call-seq:
 *     ARGF.read_nonblock(maxlen[, options])              -> string
 *     ARGF.read_nonblock(maxlen, outbuf[, options])      -> outbuf
 *
 *  Reads at most _maxlen_ bytes from the ARGF stream in non-blocking mode.
 */

static VALUE
argf_read_nonblock(int argc, VALUE *argv, VALUE argf)
{
    VALUE opts;

    rb_scan_args(argc, argv, "11:", NULL, NULL, &opts);

    if (!NIL_P(opts))
        argc--;

    return argf_getpartial(argc, argv, argf, opts, 1);
}

static VALUE
argf_getpartial(int argc, VALUE *argv, VALUE argf, VALUE opts, int nonblock)
{
    VALUE tmp, str, length;
    int no_exception;

    rb_scan_args(argc, argv, "11", &length, &str);
    if (!NIL_P(str)) {
        StringValue(str);
        argv[1] = str;
    }
    no_exception = no_exception_p(opts);

    if (!next_argv()) {
        if (!NIL_P(str)) {
            rb_str_resize(str, 0);
        }
        rb_eof_error();
    }
    if (ARGF_GENERIC_INPUT_P()) {
        VALUE (*const rescue_does_nothing)(VALUE, VALUE) = 0;
        struct argf_call_arg arg;
        arg.argc = argc;
        arg.argv = argv;
        arg.argf = argf;
        tmp = rb_rescue2(argf_forward_call, (VALUE)&arg,
                         rescue_does_nothing, Qnil, rb_eEOFError, (VALUE)0);
    }
    else {
        tmp = io_getpartial(argc, argv, ARGF.current_file, no_exception, nonblock);
    }
    if (NIL_P(tmp)) {
        if (ARGF.next_p == -1) {
            return io_nonblock_eof(no_exception);
        }
        argf_close(argf);
        ARGF.next_p = 1;
        if (RARRAY_LEN(ARGF.argv) == 0) {
            return io_nonblock_eof(no_exception);
        }
        if (NIL_P(str))
            str = rb_str_new(NULL, 0);
        return str;
    }
    return tmp;
}

/*
 *  call-seq:
 *     ARGF.getc  -> String or nil
 *
 *  Reads the next character from ARGF and returns it as a String. Returns
 *  +nil+ at the end of the stream.
 *
 *  ARGF treats the files named on the command line as a single file created
 *  by concatenating their contents. After returning the last character of the
 *  first file, it returns the first character of the second file, and so on.
 *
 *  For example:
 *
 *     $ echo "foo" > file
 *     $ ruby argf.rb file
 *
 *     ARGF.getc  #=> "f"
 *     ARGF.getc  #=> "o"
 *     ARGF.getc  #=> "o"
 *     ARGF.getc  #=> "\n"
 *     ARGF.getc  #=> nil
 *     ARGF.getc  #=> nil
 */
static VALUE
argf_getc(VALUE argf)
{
    VALUE ch;

  retry:
    if (!next_argv()) return Qnil;
    if (ARGF_GENERIC_INPUT_P()) {
        ch = forward_current(rb_intern("getc"), 0, 0);
    }
    else {
        ch = rb_io_getc(ARGF.current_file);
    }
    if (NIL_P(ch) && ARGF.next_p != -1) {
        argf_close(argf);
        ARGF.next_p = 1;
        goto retry;
    }

    return ch;
}

/*
 *  call-seq:
 *     ARGF.getbyte  -> Integer or nil
 *
 *  Gets the next 8-bit byte (0..255) from ARGF. Returns +nil+ if called at
 *  the end of the stream.
 *
 *  For example:
 *
 *     $ echo "foo" > file
 *     $ ruby argf.rb file
 *
 *     ARGF.getbyte #=> 102
 *     ARGF.getbyte #=> 111
 *     ARGF.getbyte #=> 111
 *     ARGF.getbyte #=> 10
 *     ARGF.getbyte #=> nil
 */
static VALUE
argf_getbyte(VALUE argf)
{
    VALUE ch;

  retry:
    if (!next_argv()) return Qnil;
    if (!RB_TYPE_P(ARGF.current_file, T_FILE)) {
        ch = forward_current(rb_intern("getbyte"), 0, 0);
    }
    else {
        ch = rb_io_getbyte(ARGF.current_file);
    }
    if (NIL_P(ch) && ARGF.next_p != -1) {
        argf_close(argf);
        ARGF.next_p = 1;
        goto retry;
    }

    return ch;
}

/*
 *  call-seq:
 *     ARGF.readchar  -> String or nil
 *
 *  Reads the next character from ARGF and returns it as a String. Raises
 *  an EOFError after the last character of the last file has been read.
 *
 *  For example:
 *
 *     $ echo "foo" > file
 *     $ ruby argf.rb file
 *
 *     ARGF.readchar  #=> "f"
 *     ARGF.readchar  #=> "o"
 *     ARGF.readchar  #=> "o"
 *     ARGF.readchar  #=> "\n"
 *     ARGF.readchar  #=> end of file reached (EOFError)
 */
static VALUE
argf_readchar(VALUE argf)
{
    VALUE ch;

  retry:
    if (!next_argv()) rb_eof_error();
    if (!RB_TYPE_P(ARGF.current_file, T_FILE)) {
        ch = forward_current(rb_intern("getc"), 0, 0);
    }
    else {
        ch = rb_io_getc(ARGF.current_file);
    }
    if (NIL_P(ch) && ARGF.next_p != -1) {
        argf_close(argf);
        ARGF.next_p = 1;
        goto retry;
    }

    return ch;
}

/*
 *  call-seq:
 *     ARGF.readbyte  -> Integer
 *
 *  Reads the next 8-bit byte from ARGF and returns it as an Integer. Raises
 *  an EOFError after the last byte of the last file has been read.
 *
 *  For example:
 *
 *     $ echo "foo" > file
 *     $ ruby argf.rb file
 *
 *     ARGF.readbyte  #=> 102
 *     ARGF.readbyte  #=> 111
 *     ARGF.readbyte  #=> 111
 *     ARGF.readbyte  #=> 10
 *     ARGF.readbyte  #=> end of file reached (EOFError)
 */
static VALUE
argf_readbyte(VALUE argf)
{
    VALUE c;

    NEXT_ARGF_FORWARD(0, 0);
    c = argf_getbyte(argf);
    if (NIL_P(c)) {
        rb_eof_error();
    }
    return c;
}

#define FOREACH_ARGF() while (next_argv())

static VALUE
argf_block_call_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, argf))
{
    const VALUE current = ARGF.current_file;
    rb_yield_values2(argc, argv);
    if (ARGF.init_p == -1 || current != ARGF.current_file) {
        rb_iter_break_value(Qundef);
    }
    return Qnil;
}

#define ARGF_block_call(mid, argc, argv, func, argf) \
    rb_block_call_kw(ARGF.current_file, mid, argc, argv, \
                     func, argf, rb_keyword_given_p())

static void
argf_block_call(ID mid, int argc, VALUE *argv, VALUE argf)
{
    VALUE ret = ARGF_block_call(mid, argc, argv, argf_block_call_i, argf);
    if (!UNDEF_P(ret)) ARGF.next_p = 1;
}

static VALUE
argf_block_call_line_i(RB_BLOCK_CALL_FUNC_ARGLIST(i, argf))
{
    if (!global_argf_p(argf)) {
        ARGF.last_lineno = ++ARGF.lineno;
    }
    return argf_block_call_i(i, argf, argc, argv, blockarg);
}

static void
argf_block_call_line(ID mid, int argc, VALUE *argv, VALUE argf)
{
    VALUE ret = ARGF_block_call(mid, argc, argv, argf_block_call_line_i, argf);
    if (!UNDEF_P(ret)) ARGF.next_p = 1;
}

/*
 *  call-seq:
 *     ARGF.each(sep=$/)             {|line| block }  -> ARGF
 *     ARGF.each(sep=$/, limit)      {|line| block }  -> ARGF
 *     ARGF.each(...)                                 -> an_enumerator
 *
 *     ARGF.each_line(sep=$/)        {|line| block }  -> ARGF
 *     ARGF.each_line(sep=$/, limit) {|line| block }  -> ARGF
 *     ARGF.each_line(...)                            -> an_enumerator
 *
 *  Returns an enumerator which iterates over each line (separated by _sep_,
 *  which defaults to your platform's newline character) of each file in
 *  +ARGV+. If a block is supplied, each line in turn will be yielded to the
 *  block, otherwise an enumerator is returned.
 *  The optional _limit_ argument is an Integer specifying the maximum
 *  length of each line; longer lines will be split according to this limit.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last line of the first file has been returned, the first line of the
 *  second file is returned. The ARGF.filename and ARGF.lineno methods can be
 *  used to determine the filename of the current line and line number of the
 *  whole input, respectively.
 *
 *  For example, the following code prints out each line of each named file
 *  prefixed with its line number, displaying the filename once per file:
 *
 *     ARGF.each_line do |line|
 *       puts ARGF.filename if ARGF.file.lineno == 1
 *       puts "#{ARGF.file.lineno}: #{line}"
 *     end
 *
 *  While the following code prints only the first file's name at first, and
 *  the contents with line number counted through all named files.
 *
 *     ARGF.each_line do |line|
 *       puts ARGF.filename if ARGF.lineno == 1
 *       puts "#{ARGF.lineno}: #{line}"
 *     end
 */
static VALUE
argf_each_line(int argc, VALUE *argv, VALUE argf)
{
    RETURN_ENUMERATOR(argf, argc, argv);
    FOREACH_ARGF() {
        argf_block_call_line(rb_intern("each_line"), argc, argv, argf);
    }
    return argf;
}

/*
 *  call-seq:
 *     ARGF.each_byte {|byte| block }  -> ARGF
 *     ARGF.each_byte                  -> an_enumerator
 *
 *  Iterates over each byte of each file in +ARGV+.
 *  A byte is returned as an Integer in the range 0..255.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last byte of the first file has been returned, the first byte of the
 *  second file is returned. The ARGF.filename method can be used to
 *  determine the filename of the current byte.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *  For example:
 *
 *     ARGF.bytes.to_a  #=> [35, 32, ... 95, 10]
 *
 */
static VALUE
argf_each_byte(VALUE argf)
{
    RETURN_ENUMERATOR(argf, 0, 0);
    FOREACH_ARGF() {
        argf_block_call(rb_intern("each_byte"), 0, 0, argf);
    }
    return argf;
}

/*
 *  call-seq:
 *     ARGF.each_char {|char| block }  -> ARGF
 *     ARGF.each_char                  -> an_enumerator
 *
 *  Iterates over each character of each file in ARGF.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last character of the first file has been returned, the first
 *  character of the second file is returned. The ARGF.filename method can
 *  be used to determine the name of the file in which the current character
 *  appears.
 *
 *  If no block is given, an enumerator is returned instead.
 */
static VALUE
argf_each_char(VALUE argf)
{
    RETURN_ENUMERATOR(argf, 0, 0);
    FOREACH_ARGF() {
        argf_block_call(rb_intern("each_char"), 0, 0, argf);
    }
    return argf;
}

/*
 *  call-seq:
 *     ARGF.each_codepoint {|codepoint| block }  -> ARGF
 *     ARGF.each_codepoint                       -> an_enumerator
 *
 *  Iterates over each codepoint of each file in ARGF.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last codepoint of the first file has been returned, the first
 *  codepoint of the second file is returned. The ARGF.filename method can
 *  be used to determine the name of the file in which the current codepoint
 *  appears.
 *
 *  If no block is given, an enumerator is returned instead.
 */
static VALUE
argf_each_codepoint(VALUE argf)
{
    RETURN_ENUMERATOR(argf, 0, 0);
    FOREACH_ARGF() {
        argf_block_call(rb_intern("each_codepoint"), 0, 0, argf);
    }
    return argf;
}

/*
 *  call-seq:
 *     ARGF.filename  -> String
 *     ARGF.path      -> String
 *
 *  Returns the current filename. "-" is returned when the current file is
 *  STDIN.
 *
 *  For example:
 *
 *     $ echo "foo" > foo
 *     $ echo "bar" > bar
 *     $ echo "glark" > glark
 *
 *     $ ruby argf.rb foo bar glark
 *
 *     ARGF.filename  #=> "foo"
 *     ARGF.read(5)   #=> "foo\nb"
 *     ARGF.filename  #=> "bar"
 *     ARGF.skip
 *     ARGF.filename  #=> "glark"
 */
static VALUE
argf_filename(VALUE argf)
{
    next_argv();
    return ARGF.filename;
}

static VALUE
argf_filename_getter(ID id, VALUE *var)
{
    return argf_filename(*var);
}

/*
 *  call-seq:
 *     ARGF.file  -> IO or File object
 *
 *  Returns the current file as an IO or File object.
 *  <code>$stdin</code> is returned when the current file is STDIN.
 *
 *  For example:
 *
 *     $ echo "foo" > foo
 *     $ echo "bar" > bar
 *
 *     $ ruby argf.rb foo bar
 *
 *     ARGF.file      #=> #<File:foo>
 *     ARGF.read(5)   #=> "foo\nb"
 *     ARGF.file      #=> #<File:bar>
 */
static VALUE
argf_file(VALUE argf)
{
    next_argv();
    return ARGF.current_file;
}

/*
 *  call-seq:
 *     ARGF.binmode  -> ARGF
 *
 *  Puts ARGF into binary mode. Once a stream is in binary mode, it cannot
 *  be reset to non-binary mode. This option has the following effects:
 *
 *  *  Newline conversion is disabled.
 *  *  Encoding conversion is disabled.
 *  *  Content is treated as ASCII-8BIT.
 */
static VALUE
argf_binmode_m(VALUE argf)
{
    ARGF.binmode = 1;
    next_argv();
    ARGF_FORWARD(0, 0);
    rb_io_ascii8bit_binmode(ARGF.current_file);
    return argf;
}

/*
 *  call-seq:
 *     ARGF.binmode?  -> true or false
 *
 *  Returns true if ARGF is being read in binary mode; false otherwise.
 *  To enable binary mode use ARGF.binmode.
 *
 *  For example:
 *
 *     ARGF.binmode?  #=> false
 *     ARGF.binmode
 *     ARGF.binmode?  #=> true
 */
static VALUE
argf_binmode_p(VALUE argf)
{
    return RBOOL(ARGF.binmode);
}

/*
 *  call-seq:
 *     ARGF.skip  -> ARGF
 *
 *  Sets the current file to the next file in ARGV. If there aren't any more
 *  files it has no effect.
 *
 *  For example:
 *
 *     $ ruby argf.rb foo bar
 *     ARGF.filename  #=> "foo"
 *     ARGF.skip
 *     ARGF.filename  #=> "bar"
 */
static VALUE
argf_skip(VALUE argf)
{
    if (ARGF.init_p && ARGF.next_p == 0) {
        argf_close(argf);
        ARGF.next_p = 1;
    }
    return argf;
}

/*
 *  call-seq:
 *     ARGF.close  -> ARGF
 *
 *  Closes the current file and skips to the next file in ARGV. If there are
 *  no more files to open, just closes the current file. STDIN will not be
 *  closed.
 *
 *  For example:
 *
 *     $ ruby argf.rb foo bar
 *
 *     ARGF.filename  #=> "foo"
 *     ARGF.close
 *     ARGF.filename  #=> "bar"
 *     ARGF.close
 */
static VALUE
argf_close_m(VALUE argf)
{
    next_argv();
    argf_close(argf);
    if (ARGF.next_p != -1) {
        ARGF.next_p = 1;
    }
    ARGF.lineno = 0;
    return argf;
}

/*
 *  call-seq:
 *     ARGF.closed?  -> true or false
 *
 *  Returns _true_ if the current file has been closed; _false_ otherwise. Use
 *  ARGF.close to actually close the current file.
 */
static VALUE
argf_closed(VALUE argf)
{
    next_argv();
    ARGF_FORWARD(0, 0);
    return rb_io_closed_p(ARGF.current_file);
}

/*
 *  call-seq:
 *     ARGF.to_s  -> String
 *
 *  Returns "ARGF".
 */
static VALUE
argf_to_s(VALUE argf)
{
    return rb_str_new2("ARGF");
}

/*
 *  call-seq:
 *     ARGF.inplace_mode  -> String
 *
 *  Returns the file extension appended to the names of backup copies of
 *  modified files under in-place edit mode. This value can be set using
 *  ARGF.inplace_mode= or passing the +-i+ switch to the Ruby binary.
 */
static VALUE
argf_inplace_mode_get(VALUE argf)
{
    if (!ARGF.inplace) return Qnil;
    if (NIL_P(ARGF.inplace)) return rb_str_new(0, 0);
    return rb_str_dup(ARGF.inplace);
}

static VALUE
opt_i_get(ID id, VALUE *var)
{
    return argf_inplace_mode_get(*var);
}

/*
 *  call-seq:
 *     ARGF.inplace_mode = ext  -> ARGF
 *
 *  Sets the filename extension for in-place editing mode to the given String.
 *  The backup copy of each file being edited has this value appended to its
 *  filename.
 *
 *  For example:
 *
 *      $ ruby argf.rb file.txt
 *
 *      ARGF.inplace_mode = '.bak'
 *      ARGF.each_line do |line|
 *        print line.sub("foo","bar")
 *      end
 *
 *  First, _file.txt.bak_ is created as a backup copy of _file.txt_.
 *  Then, each line of _file.txt_ has the first occurrence of "foo" replaced with
 *  "bar".
 */
static VALUE
argf_inplace_mode_set(VALUE argf, VALUE val)
{
    if (!RTEST(val)) {
        ARGF.inplace = Qfalse;
    }
    else if (StringValueCStr(val), !RSTRING_LEN(val)) {
        ARGF.inplace = Qnil;
    }
    else {
        ARGF.inplace = rb_str_new_frozen(val);
    }
    return argf;
}

static void
opt_i_set(VALUE val, ID id, VALUE *var)
{
    argf_inplace_mode_set(*var, val);
}

void
ruby_set_inplace_mode(const char *suffix)
{
    ARGF.inplace = !suffix ? Qfalse : !*suffix ? Qnil : rb_str_new(suffix, strlen(suffix));
}

/*
 *  call-seq:
 *     ARGF.argv  -> ARGV
 *
 *  Returns the +ARGV+ array, which contains the arguments passed to your
 *  script, one per element.
 *
 *  For example:
 *
 *      $ ruby argf.rb -v glark.txt
 *
 *      ARGF.argv   #=> ["-v", "glark.txt"]
 *
 */
static VALUE
argf_argv(VALUE argf)
{
    return ARGF.argv;
}

static VALUE
argf_argv_getter(ID id, VALUE *var)
{
    return argf_argv(*var);
}

VALUE
rb_get_argv(void)
{
    return ARGF.argv;
}

/*
 *  call-seq:
 *     ARGF.to_write_io  -> io
 *
 *  Returns IO instance tied to _ARGF_ for writing if inplace mode is
 *  enabled.
 */
static VALUE
argf_write_io(VALUE argf)
{
    if (!RTEST(ARGF.current_file)) {
        rb_raise(rb_eIOError, "not opened for writing");
    }
    return GetWriteIO(ARGF.current_file);
}

/*
 *  call-seq:
 *     ARGF.write(*objects)  -> integer
 *
 *  Writes each of the given +objects+ if inplace mode.
 */
static VALUE
argf_write(int argc, VALUE *argv, VALUE argf)
{
    return rb_io_writev(argf_write_io(argf), argc, argv);
}

void
rb_readwrite_sys_fail(enum rb_io_wait_readwrite waiting, const char *mesg)
{
    rb_readwrite_syserr_fail(waiting, errno, mesg);
}

void
rb_readwrite_syserr_fail(enum rb_io_wait_readwrite waiting, int n, const char *mesg)
{
    VALUE arg, c = Qnil;
    arg = mesg ? rb_str_new2(mesg) : Qnil;
    switch (waiting) {
      case RB_IO_WAIT_WRITABLE:
        switch (n) {
          case EAGAIN:
            c = rb_eEAGAINWaitWritable;
            break;
#if EAGAIN != EWOULDBLOCK
          case EWOULDBLOCK:
            c = rb_eEWOULDBLOCKWaitWritable;
            break;
#endif
          case EINPROGRESS:
            c = rb_eEINPROGRESSWaitWritable;
            break;
          default:
            rb_mod_syserr_fail_str(rb_mWaitWritable, n, arg);
        }
        break;
      case RB_IO_WAIT_READABLE:
        switch (n) {
          case EAGAIN:
            c = rb_eEAGAINWaitReadable;
            break;
#if EAGAIN != EWOULDBLOCK
          case EWOULDBLOCK:
            c = rb_eEWOULDBLOCKWaitReadable;
            break;
#endif
          case EINPROGRESS:
            c = rb_eEINPROGRESSWaitReadable;
            break;
          default:
            rb_mod_syserr_fail_str(rb_mWaitReadable, n, arg);
        }
        break;
      default:
        rb_bug("invalid read/write type passed to rb_readwrite_sys_fail: %d", waiting);
    }
    rb_exc_raise(rb_class_new_instance(1, &arg, c));
}

static VALUE
get_LAST_READ_LINE(ID _x, VALUE *_y)
{
    return rb_lastline_get();
}

static void
set_LAST_READ_LINE(VALUE val, ID _x, VALUE *_y)
{
    rb_lastline_set(val);
}

/*
 * Document-class: IOError
 *
 * Raised when an IO operation fails.
 *
 *    File.open("/etc/hosts") {|f| f << "example"}
 *      #=> IOError: not opened for writing
 *
 *    File.open("/etc/hosts") {|f| f.close; f.read }
 *      #=> IOError: closed stream
 *
 * Note that some IO failures raise <code>SystemCallError</code>s
 * and these are not subclasses of IOError:
 *
 *    File.open("does/not/exist")
 *      #=> Errno::ENOENT: No such file or directory - does/not/exist
 */

/*
 * Document-class: EOFError
 *
 * Raised by some IO operations when reaching the end of file. Many IO
 * methods exist in two forms,
 *
 * one that returns +nil+ when the end of file is reached, the other
 * raises EOFError.
 *
 * EOFError is a subclass of IOError.
 *
 *    file = File.open("/etc/hosts")
 *    file.read
 *    file.gets     #=> nil
 *    file.readline #=> EOFError: end of file reached
 *    file.close
 */

/*
 * Document-class:  ARGF
 *
 * == \ARGF and +ARGV+
 *
 * The \ARGF object works with the array at global variable +ARGV+
 * to make <tt>$stdin</tt> and file streams available in the Ruby program:
 *
 * - **ARGV** may be thought of as the <b>argument vector</b> array.
 *
 *   Initially, it contains the command-line arguments and options
 *   that are passed to the Ruby program;
 *   the program can modify that array as it likes.
 *
 * - **ARGF** may be thought of as the <b>argument files</b> object.
 *
 *   It can access file streams and/or the <tt>$stdin</tt> stream,
 *   based on what it finds in +ARGV+.
 *   This provides a convenient way for the command line
 *   to specify streams for a Ruby program to read.
 *
 * == Reading
 *
 * \ARGF may read from _source_ streams,
 * which at any particular time are determined by the content of +ARGV+.
 *
 * === Simplest Case
 *
 * When the <i>very first</i> \ARGF read occurs with an empty +ARGV+ (<tt>[]</tt>),
 * the source is <tt>$stdin</tt>:
 *
 * - \File +t.rb+:
 *
 *     p ['ARGV', ARGV]
 *     p ['ARGF.read', ARGF.read]
 *
 * - Commands and outputs
 *   (see below for the content of files +foo.txt+ and +bar.txt+):
 *
 *     $ echo "Open the pod bay doors, Hal." | ruby t.rb
 *     ["ARGV", []]
 *     ["ARGF.read", "Open the pod bay doors, Hal.\n"]
 *
 *     $ cat foo.txt bar.txt | ruby t.rb
 *     ["ARGV", []]
 *     ["ARGF.read", "Foo 0\nFoo 1\nBar 0\nBar 1\nBar 2\nBar 3\n"]
 *
 * === About the Examples
 *
 * Many examples here assume the existence of files +foo.txt+ and +bar.txt+:
 *
 *   $ cat foo.txt
 *   Foo 0
 *   Foo 1
 *   $ cat bar.txt
 *   Bar 0
 *   Bar 1
 *   Bar 2
 *   Bar 3
 *
 * === Sources in +ARGV+
 *
 * For any \ARGF read _except_ the {simplest case}[rdoc-ref:ARGF@Simplest+Case]
 * (that is, _except_ for the <i>very first</i> \ARGF read with an empty +ARGV+),
 * the sources are found in +ARGV+.
 *
 * \ARGF assumes that each element in array +ARGV+ is a potential source,
 * and is one of:
 *
 * - The string path to a file that may be opened as a stream.
 * - The character <tt>'-'</tt>, meaning stream <tt>$stdin</tt>.
 *
 * Each element that is _not_ one of these
 * should be removed from +ARGV+ before \ARGF accesses that source.
 *
 * In the following example:
 *
 * - Filepaths +foo.txt+ and +bar.txt+ may be retained as potential sources.
 * - Options <tt>--xyzzy</tt> and <tt>--mojo</tt> should be removed.
 *
 * Example:
 *
 * - \File +t.rb+:
 *
 *     # Print arguments (and options, if any) found on command line.
 *     p ['ARGV', ARGV]
 *
 * - Command and output:
 *
 *     $ ruby t.rb --xyzzy --mojo foo.txt bar.txt
 *     ["ARGV", ["--xyzzy", "--mojo", "foo.txt", "bar.txt"]]
 *
 * \ARGF's stream access considers the elements of +ARGV+, left to right:
 *
 * - \File +t.rb+:
 *
 *     p "ARGV: #{ARGV}"
 *     p "Read: #{ARGF.read}" # Read everything from all specified streams.
 *
 * - Command and output:
 *
 *     $ ruby t.rb foo.txt bar.txt
 *     "ARGV: [\"foo.txt\", \"bar.txt\"]"
 *     "Read: Foo 0\nFoo 1\nBar 0\nBar 1\nBar 2\nBar 3\n"
 *
 * Because the value at +ARGV+ is an ordinary array,
 * you can manipulate it to control which sources \ARGF considers:
 *
 * - If you remove an element from +ARGV+, \ARGF will not consider the corresponding source.
 * - If you add an element to +ARGV+, \ARGF will consider the corresponding source.
 *
 * Each element in +ARGV+ is removed when its corresponding source is accessed;
 * when all sources have been accessed, the array is empty:
 *
 * - \File +t.rb+:
 *
 *     until ARGV.empty? && ARGF.eof?
 *       p "ARGV: #{ARGV}"
 *       p "Line: #{ARGF.readline}" # Read each line from each specified stream.
 *     end
 *
 * - Command and output:
 *
 *     $ ruby t.rb foo.txt bar.txt
 *     "ARGV: [\"foo.txt\", \"bar.txt\"]"
 *     "Line: Foo 0\n"
 *     "ARGV: [\"bar.txt\"]"
 *     "Line: Foo 1\n"
 *     "ARGV: [\"bar.txt\"]"
 *     "Line: Bar 0\n"
 *     "ARGV: []"
 *     "Line: Bar 1\n"
 *     "ARGV: []"
 *     "Line: Bar 2\n"
 *     "ARGV: []"
 *     "Line: Bar 3\n"
 *
 * ==== Filepaths in +ARGV+
 *
 * The +ARGV+ array may contain filepaths the specify sources for \ARGF reading.
 *
 * This program prints what it reads from files at the paths specified
 * on the command line:
 *
 * - \File +t.rb+:
 *
 *     p ['ARGV', ARGV]
 *     # Read and print all content from the specified sources.
 *     p ['ARGF.read', ARGF.read]
 *
 * - Command and output:
 *
 *     $ ruby t.rb foo.txt bar.txt
 *     ["ARGV", [foo.txt, bar.txt]
 *     ["ARGF.read", "Foo 0\nFoo 1\nBar 0\nBar 1\nBar 2\nBar 3\n"]
 *
 * ==== Specifying <tt>$stdin</tt> in +ARGV+
 *
 * To specify stream <tt>$stdin</tt> in +ARGV+, us the character <tt>'-'</tt>:
 *
 * - \File +t.rb+:
 *
 *     p ['ARGV', ARGV]
 *     p ['ARGF.read', ARGF.read]
 *
 * - Command and output:
 *
 *     $ echo "Open the pod bay doors, Hal." | ruby t.rb -
 *     ["ARGV", ["-"]]
 *     ["ARGF.read", "Open the pod bay doors, Hal.\n"]
 *
 * When no character <tt>'-'</tt> is given, stream <tt>$stdin</tt> is ignored
 * (exception:
 * see {Specifying $stdin in ARGV}[rdoc-ref:ARGF@Specifying+-24stdin+in+ARGV]):
 *
 * - Command and output:
 *
 *     $ echo "Open the pod bay doors, Hal." | ruby t.rb foo.txt bar.txt
 *     "ARGV: [\"foo.txt\", \"bar.txt\"]"
 *     "Read: Foo 0\nFoo 1\nBar 0\nBar 1\nBar 2\nBar 3\n"
 *
 * ==== Mixtures and Repetitions in +ARGV+
 *
 * For an \ARGF reader, +ARGV+ may contain any mixture of filepaths
 * and character <tt>'-'</tt>, including repetitions.
 *
 * ==== Modifications to +ARGV+
 *
 * The running Ruby program may make any modifications to the +ARGV+ array;
 * the current value of +ARGV+ affects \ARGF reading.
 *
 * ==== Empty +ARGV+
 *
 * For an empty +ARGV+, an \ARGF read method either returns +nil+
 * or raises an exception, depending on the specific method.
 *
 * === More Read Methods
 *
 * As seen above, method ARGF#read reads the content of all sources
 * into a single string.
 * Other \ARGF methods provide other ways to access that content;
 * these include:
 *
 * - Byte access: #each_byte, #getbyte, #readbyte.
 * - Character access: #each_char, #getc, #readchar.
 * - Codepoint access: #each_codepoint.
 * - Line access: #each_line, #gets, #readline, #readlines.
 * - Source access: #read, #read_nonblock, #readpartial.
 *
 * === About \Enumerable
 *
 * \ARGF includes module Enumerable.
 * Virtually all methods in \Enumerable call method <tt>#each</tt> in the including class.
 *
 * <b>Note well</b>: In \ARGF, method #each returns data from the _sources_,
 * _not_ from +ARGV+;
 * therefore, for example, <tt>ARGF#entries</tt> returns an array of lines from the sources,
 * not an array of the strings from +ARGV+:
 *
 * - \File +t.rb+:
 *
 *     p ['ARGV', ARGV]
 *     p ['ARGF.entries', ARGF.entries]
 *
 * - Command and output:
 *
 *     $ ruby t.rb foo.txt bar.txt
 *     ["ARGV", ["foo.txt", "bar.txt"]]
 *     ["ARGF.entries", ["Foo 0\n", "Foo 1\n", "Bar 0\n", "Bar 1\n", "Bar 2\n", "Bar 3\n"]]
 *
 * == Writing
 *
 * If <i>inplace mode</i> is in effect,
 * \ARGF may write to target streams,
 * which at any particular time are determined by the content of ARGV.
 *
 * Methods about inplace mode:
 *
 * - #inplace_mode
 * - #inplace_mode=
 * - #to_write_io
 *
 * Methods for writing:
 *
 * - #print
 * - #printf
 * - #putc
 * - #puts
 * - #write
 *
 */

/*
 *  An instance of class \IO (commonly called a _stream_)
 *  represents an input/output stream in the underlying operating system.
 *  Class \IO is the basis for input and output in Ruby.
 *
 *  Class File is the only class in the Ruby core that is a subclass of \IO.
 *  Some classes in the Ruby standard library are also subclasses of \IO;
 *  these include TCPSocket and UDPSocket.
 *
 *  The global constant ARGF (also accessible as <tt>$<</tt>)
 *  provides an IO-like stream that allows access to all file paths
 *  found in ARGV (or found in STDIN if ARGV is empty).
 *  ARGF is not itself a subclass of \IO.
 *
 *  Class StringIO provides an IO-like stream that handles a String.
 *  StringIO is not itself a subclass of \IO.
 *
 *  Important objects based on \IO include:
 *
 *  - $stdin.
 *  - $stdout.
 *  - $stderr.
 *  - Instances of class File.
 *
 *  An instance of \IO may be created using:
 *
 *  - IO.new: returns a new \IO object for the given integer file descriptor.
 *  - IO.open: passes a new \IO object to the given block.
 *  - IO.popen: returns a new \IO object that is connected to the $stdin and $stdout
 *    of a newly-launched subprocess.
 *  - Kernel#open: Returns a new \IO object connected to a given source:
 *    stream, file, or subprocess.
 *
 *  Like a File stream, an \IO stream has:
 *
 *  - A read/write mode, which may be read-only, write-only, or read/write;
 *    see {Read/Write Mode}[rdoc-ref:File@Read-2FWrite+Mode].
 *  - A data mode, which may be text-only or binary;
 *    see {Data Mode}[rdoc-ref:File@Data+Mode].
 *  - Internal and external encodings;
 *    see {Encodings}[rdoc-ref:File@Encodings].
 *
 *  And like other \IO streams, it has:
 *
 *  - A position, which determines where in the stream the next
 *    read or write is to occur;
 *    see {Position}[rdoc-ref:IO@Position].
 *  - A line number, which is a special, line-oriented, "position"
 *    (different from the position mentioned above);
 *    see {Line Number}[rdoc-ref:IO@Line+Number].
 *
 *  == Extension <tt>io/console</tt>
 *
 *  Extension <tt>io/console</tt> provides numerous methods
 *  for interacting with the console;
 *  requiring it adds numerous methods to class \IO.
 *
 *  == Example Files
 *
 *  Many examples here use these variables:
 *
 *    :include: doc/examples/files.rdoc
 *
 *  == Open Options
 *
 *  A number of \IO methods accept optional keyword arguments
 *  that determine how a new stream is to be opened:
 *
 *  - +:mode+: Stream mode.
 *  - +:flags+: Integer file open flags;
 *    If +mode+ is also given, the two are bitwise-ORed.
 *  - +:external_encoding+: External encoding for the stream.
 *  - +:internal_encoding+: Internal encoding for the stream.
 *    <tt>'-'</tt> is a synonym for the default internal encoding.
 *    If the value is +nil+ no conversion occurs.
 *  - +:encoding+: Specifies external and internal encodings as <tt>'extern:intern'</tt>.
 *  - +:textmode+: If a truthy value, specifies the mode as text-only, binary otherwise.
 *  - +:binmode+: If a truthy value, specifies the mode as binary, text-only otherwise.
 *  - +:autoclose+: If a truthy value, specifies that the +fd+ will close
 *    when the stream closes; otherwise it remains open.
 *  - +:path:+ If a string value is provided, it is used in #inspect and is available as
 *    #path method.
 *
 *  Also available are the options offered in String#encode,
 *  which may control conversion between external and internal encoding.
 *
 *  == Basic \IO
 *
 *  You can perform basic stream \IO with these methods,
 *  which typically operate on multi-byte strings:
 *
 *  - IO#read: Reads and returns some or all of the remaining bytes from the stream.
 *  - IO#write: Writes zero or more strings to the stream;
 *    each given object that is not already a string is converted via +to_s+.
 *
 *  === Position
 *
 *  An \IO stream has a nonnegative integer _position_,
 *  which is the byte offset at which the next read or write is to occur.
 *  A new stream has position zero (and line number zero);
 *  method +rewind+ resets the position (and line number) to zero.
 *
 *  These methods discard {buffers}[rdoc-ref:IO@Buffering] and the
 *  Encoding::Converter instances used for that \IO.
 *
 *  The relevant methods:
 *
 *  - IO#tell (aliased as +#pos+): Returns the current position (in bytes) in the stream.
 *  - IO#pos=: Sets the position of the stream to a given integer +new_position+ (in bytes).
 *  - IO#seek: Sets the position of the stream to a given integer +offset+ (in bytes),
 *    relative to a given position +whence+
 *    (indicating the beginning, end, or current position).
 *  - IO#rewind: Positions the stream at the beginning (also resetting the line number).
 *
 *  === Open and Closed Streams
 *
 *  A new \IO stream may be open for reading, open for writing, or both.
 *
 *  A stream is automatically closed when claimed by the garbage collector.
 *
 *  Attempted reading or writing on a closed stream raises an exception.
 *
 *  The relevant methods:
 *
 *  - IO#close: Closes the stream for both reading and writing.
 *  - IO#close_read: Closes the stream for reading.
 *  - IO#close_write: Closes the stream for writing.
 *  - IO#closed?: Returns whether the stream is closed.
 *
 *  === End-of-Stream
 *
 *  You can query whether a stream is positioned at its end:
 *
 *  - IO#eof? (also aliased as +#eof+): Returns whether the stream is at end-of-stream.
 *
 *  You can reposition to end-of-stream by using method IO#seek:
 *
 *    f = File.new('t.txt')
 *    f.eof? # => false
 *    f.seek(0, :END)
 *    f.eof? # => true
 *    f.close
 *
 *  Or by reading all stream content (which is slower than using IO#seek):
 *
 *    f.rewind
 *    f.eof? # => false
 *    f.read # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *    f.eof? # => true
 *
 *  == Line \IO
 *
 *  Class \IO supports line-oriented
 *  {input}[rdoc-ref:IO@Line+Input] and {output}[rdoc-ref:IO@Line+Output]
 *
 *  === Line Input
 *
 *  Class \IO supports line-oriented input for
 *  {files}[rdoc-ref:IO@File+Line+Input] and {IO streams}[rdoc-ref:IO@Stream+Line+Input]
 *
 *  ==== \File Line Input
 *
 *  You can read lines from a file using these methods:
 *
 *  - IO.foreach: Reads each line and passes it to the given block.
 *  - IO.readlines: Reads and returns all lines in an array.
 *
 *  For each of these methods:
 *
 *  - You can specify {open options}[rdoc-ref:IO@Open+Options].
 *  - Line parsing depends on the effective <i>line separator</i>;
 *    see {Line Separator}[rdoc-ref:IO@Line+Separator].
 *  - The length of each returned line depends on the effective <i>line limit</i>;
 *    see {Line Limit}[rdoc-ref:IO@Line+Limit].
 *
 *  ==== Stream Line Input
 *
 *  You can read lines from an \IO stream using these methods:
 *
 *  - IO#each_line: Reads each remaining line, passing it to the given block.
 *  - IO#gets: Returns the next line.
 *  - IO#readline: Like #gets, but raises an exception at end-of-stream.
 *  - IO#readlines: Returns all remaining lines in an array.
 *
 *  For each of these methods:
 *
 *  - Reading may begin mid-line,
 *    depending on the stream's _position_;
 *    see {Position}[rdoc-ref:IO@Position].
 *  - Line parsing depends on the effective <i>line separator</i>;
 *    see {Line Separator}[rdoc-ref:IO@Line+Separator].
 *  - The length of each returned line depends on the effective <i>line limit</i>;
 *    see {Line Limit}[rdoc-ref:IO@Line+Limit].
 *
 *  ===== Line Separator
 *
 *  Each of the {line input methods}[rdoc-ref:IO@Line+Input] uses a <i>line separator</i>:
 *  the string that determines what is considered a line;
 *  it is sometimes called the <i>input record separator</i>.
 *
 *  The default line separator is taken from global variable <tt>$/</tt>,
 *  whose initial value is <tt>"\n"</tt>.
 *
 *  Generally, the line to be read next is all data
 *  from the current {position}[rdoc-ref:IO@Position]
 *  to the next line separator
 *  (but see {Special Line Separator Values}[rdoc-ref:IO@Special+Line+Separator+Values]):
 *
 *    f = File.new('t.txt')
 *    # Method gets with no sep argument returns the next line, according to $/.
 *    f.gets # => "First line\n"
 *    f.gets # => "Second line\n"
 *    f.gets # => "\n"
 *    f.gets # => "Fourth line\n"
 *    f.gets # => "Fifth line\n"
 *    f.close
 *
 *  You can use a different line separator by passing argument +sep+:
 *
 *    f = File.new('t.txt')
 *    f.gets('l')   # => "First l"
 *    f.gets('li')  # => "ine\nSecond li"
 *    f.gets('lin') # => "ne\n\nFourth lin"
 *    f.gets        # => "e\n"
 *    f.close
 *
 *  Or by setting global variable <tt>$/</tt>:
 *
 *    f = File.new('t.txt')
 *    $/ = 'l'
 *    f.gets # => "First l"
 *    f.gets # => "ine\nSecond l"
 *    f.gets # => "ine\n\nFourth l"
 *    f.close
 *
 *  ===== Special Line Separator Values
 *
 *  Each of the {line input methods}[rdoc-ref:IO@Line+Input]
 *  accepts two special values for parameter +sep+:
 *
 *  - +nil+: The entire stream is to be read ("slurped") into a single string:
 *
 *      f = File.new('t.txt')
 *      f.gets(nil) # => "First line\nSecond line\n\nFourth line\nFifth line\n"
 *      f.close
 *
 *  - <tt>''</tt> (the empty string): The next "paragraph" is to be read
 *    (paragraphs being separated by two consecutive line separators):
 *
 *      f = File.new('t.txt')
 *      f.gets('') # => "First line\nSecond line\n\n"
 *      f.gets('') # => "Fourth line\nFifth line\n"
 *      f.close
 *
 *  ===== Line Limit
 *
 *  Each of the {line input methods}[rdoc-ref:IO@Line+Input]
 *  uses an integer <i>line limit</i>,
 *  which restricts the number of bytes that may be returned.
 *  (A multi-byte character will not be split, and so a returned line may be slightly longer
 *  than the limit).
 *
 *  The default limit value is <tt>-1</tt>;
 *  any negative limit value means that there is no limit.
 *
 *  If there is no limit, the line is determined only by +sep+.
 *
 *    # Text with 1-byte characters.
 *    File.open('t.txt') {|f| f.gets(1) }  # => "F"
 *    File.open('t.txt') {|f| f.gets(2) }  # => "Fi"
 *    File.open('t.txt') {|f| f.gets(3) }  # => "Fir"
 *    File.open('t.txt') {|f| f.gets(4) }  # => "Firs"
 *    # No more than one line.
 *    File.open('t.txt') {|f| f.gets(10) } # => "First line"
 *    File.open('t.txt') {|f| f.gets(11) } # => "First line\n"
 *    File.open('t.txt') {|f| f.gets(12) } # => "First line\n"
 *
 *    # Text with 2-byte characters, which will not be split.
 *    File.open('t.rus') {|f| f.gets(1).size } # => 1
 *    File.open('t.rus') {|f| f.gets(2).size } # => 1
 *    File.open('t.rus') {|f| f.gets(3).size } # => 2
 *    File.open('t.rus') {|f| f.gets(4).size } # => 2
 *
 *  ===== Line Separator and Line Limit
 *
 *  With arguments +sep+ and +limit+ given, combines the two behaviors:
 *
 *  - Returns the next line as determined by line separator +sep+.
 *  - But returns no more bytes than are allowed by the limit +limit+.
 *
 *  Example:
 *
 *    File.open('t.txt') {|f| f.gets('li', 20) } # => "First li"
 *    File.open('t.txt') {|f| f.gets('li', 2) }  # => "Fi"
 *
 *  ===== Line Number
 *
 *  A readable \IO stream has a non-negative integer <i>line number</i>:
 *
 *  - IO#lineno: Returns the line number.
 *  - IO#lineno=: Resets and returns the line number.
 *
 *  Unless modified by a call to method IO#lineno=,
 *  the line number is the number of lines read
 *  by certain line-oriented methods,
 *  according to the effective {line separator}[rdoc-ref:IO@Line+Separator]:
 *
 *  - IO.foreach: Increments the line number on each call to the block.
 *  - IO#each_line: Increments the line number on each call to the block.
 *  - IO#gets: Increments the line number.
 *  - IO#readline: Increments the line number.
 *  - IO#readlines: Increments the line number for each line read.
 *
 *  A new stream is initially has line number zero (and position zero);
 *  method +rewind+ resets the line number (and position) to zero:
 *
 *    f = File.new('t.txt')
 *    f.lineno # => 0
 *    f.gets   # => "First line\n"
 *    f.lineno # => 1
 *    f.rewind
 *    f.lineno # => 0
 *    f.close
 *
 *  Reading lines from a stream usually changes its line number:
 *
 *    f = File.new('t.txt', 'r')
 *    f.lineno   # => 0
 *    f.readline # => "This is line one.\n"
 *    f.lineno   # => 1
 *    f.readline # => "This is the second line.\n"
 *    f.lineno   # => 2
 *    f.readline # => "Here's the third line.\n"
 *    f.lineno   # => 3
 *    f.eof?     # => true
 *    f.close
 *
 *  Iterating over lines in a stream usually changes its line number:
 *
 *    File.open('t.txt') do |f|
 *      f.each_line do |line|
 *        p "position=#{f.pos} eof?=#{f.eof?} lineno=#{f.lineno}"
 *      end
 *    end
 *
 *  Output:
 *
 *    "position=11 eof?=false lineno=1"
 *    "position=23 eof?=false lineno=2"
 *    "position=24 eof?=false lineno=3"
 *    "position=36 eof?=false lineno=4"
 *    "position=47 eof?=true lineno=5"
 *
 *  Unlike the stream's {position}[rdoc-ref:IO@Position],
 *  the line number does not affect where the next read or write will occur:
 *
 *    f = File.new('t.txt')
 *    f.lineno = 1000
 *    f.lineno # => 1000
 *    f.gets   # => "First line\n"
 *    f.lineno # => 1001
 *    f.close
 *
 *  Associated with the line number is the global variable <tt>$.</tt>:
 *
 *  - When a stream is opened, <tt>$.</tt> is not set;
 *    its value is left over from previous activity in the process:
 *
 *      $. = 41
 *      f = File.new('t.txt')
 *      $. = 41
 *      # => 41
 *      f.close
 *
 *  - When a stream is read, <tt>$.</tt> is set to the line number for that stream:
 *
 *      f0 = File.new('t.txt')
 *      f1 = File.new('t.dat')
 *      f0.readlines # => ["First line\n", "Second line\n", "\n", "Fourth line\n", "Fifth line\n"]
 *      $.           # => 5
 *      f1.readlines # => ["\xFE\xFF\x99\x90\x99\x91\x99\x92\x99\x93\x99\x94"]
 *      $.           # => 1
 *      f0.close
 *      f1.close
 *
 *  - Methods IO#rewind and IO#seek do not affect <tt>$.</tt>:
 *
 *      f = File.new('t.txt')
 *      f.readlines # => ["First line\n", "Second line\n", "\n", "Fourth line\n", "Fifth line\n"]
 *      $.          # => 5
 *      f.rewind
 *      f.seek(0, :SET)
 *      $.          # => 5
 *      f.close
 *
 *  === Line Output
 *
 *  You can write to an \IO stream line-by-line using this method:
 *
 *  - IO#puts: Writes objects to the stream.
 *
 *  == Character \IO
 *
 *  You can process an \IO stream character-by-character using these methods:
 *
 *  - IO#getc: Reads and returns the next character from the stream.
 *  - IO#readchar: Like #getc, but raises an exception at end-of-stream.
 *  - IO#ungetc: Pushes back ("unshifts") a character or integer onto the stream.
 *  - IO#putc: Writes a character to the stream.
 *  - IO#each_char: Reads each remaining character in the stream,
 *    passing the character to the given block.
 *
 *  == Byte \IO
 *
 *  You can process an \IO stream byte-by-byte using these methods:
 *
 *  - IO#getbyte: Returns the next 8-bit byte as an integer in range 0..255.
 *  - IO#readbyte: Like #getbyte, but raises an exception if at end-of-stream.
 *  - IO#ungetbyte: Pushes back ("unshifts") a byte back onto the stream.
 *  - IO#each_byte: Reads each remaining byte in the stream,
 *    passing the byte to the given block.
 *
 *  == Codepoint \IO
 *
 *  You can process an \IO stream codepoint-by-codepoint:
 *
 *  - IO#each_codepoint: Reads each remaining codepoint, passing it to the given block.
 *
 *  == What's Here
 *
 *  First, what's elsewhere. Class \IO:
 *
 *  - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
 *  - Includes {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here],
 *    which provides dozens of additional methods.
 *
 *  Here, class \IO provides methods that are useful for:
 *
 *  - {Creating}[rdoc-ref:IO@Creating]
 *  - {Reading}[rdoc-ref:IO@Reading]
 *  - {Writing}[rdoc-ref:IO@Writing]
 *  - {Positioning}[rdoc-ref:IO@Positioning]
 *  - {Iterating}[rdoc-ref:IO@Iterating]
 *  - {Settings}[rdoc-ref:IO@Settings]
 *  - {Querying}[rdoc-ref:IO@Querying]
 *  - {Buffering}[rdoc-ref:IO@Buffering]
 *  - {Low-Level Access}[rdoc-ref:IO@Low-Level+Access]
 *  - {Other}[rdoc-ref:IO@Other]
 *
 *  === Creating
 *
 *  - ::new (aliased as ::for_fd): Creates and returns a new \IO object for the given
 *    integer file descriptor.
 *  - ::open: Creates a new \IO object.
 *  - ::pipe: Creates a connected pair of reader and writer \IO objects.
 *  - ::popen: Creates an \IO object to interact with a subprocess.
 *  - ::select: Selects which given \IO instances are ready for reading,
 *    writing, or have pending exceptions.
 *
 *  === Reading
 *
 *  - ::binread: Returns a binary string with all or a subset of bytes
 *    from the given file.
 *  - ::read: Returns a string with all or a subset of bytes from the given file.
 *  - ::readlines: Returns an array of strings, which are the lines from the given file.
 *  - #getbyte: Returns the next 8-bit byte read from +self+ as an integer.
 *  - #getc: Returns the next character read from +self+ as a string.
 *  - #gets: Returns the line read from +self+.
 *  - #pread: Returns all or the next _n_ bytes read from +self+,
 *    not updating the receiver's offset.
 *  - #read: Returns all remaining or the next _n_ bytes read from +self+
 *    for a given _n_.
 *  - #read_nonblock: the next _n_ bytes read from +self+ for a given _n_,
 *    in non-block mode.
 *  - #readbyte: Returns the next byte read from +self+;
 *    same as #getbyte, but raises an exception on end-of-stream.
 *  - #readchar: Returns the next character read from +self+;
 *    same as #getc, but raises an exception on end-of-stream.
 *  - #readline: Returns the next line read from +self+;
 *    same as #getline, but raises an exception of end-of-stream.
 *  - #readlines: Returns an array of all lines read read from +self+.
 *  - #readpartial: Returns up to the given number of bytes from +self+.
 *
 *  === Writing
 *
 *  - ::binwrite: Writes the given string to the file at the given filepath,
 *    in binary mode.
 *  - ::write: Writes the given string to +self+.
 *  - #<<: Appends the given string to +self+.
 *  - #print: Prints last read line or given objects to +self+.
 *  - #printf: Writes to +self+ based on the given format string and objects.
 *  - #putc: Writes a character to +self+.
 *  - #puts: Writes lines to +self+, making sure line ends with a newline.
 *  - #pwrite: Writes the given string at the given offset,
 *    not updating the receiver's offset.
 *  - #write: Writes one or more given strings to +self+.
 *  - #write_nonblock: Writes one or more given strings to +self+ in non-blocking mode.
 *
 *  === Positioning
 *
 *  - #lineno: Returns the current line number in +self+.
 *  - #lineno=: Sets the line number is +self+.
 *  - #pos (aliased as #tell): Returns the current byte offset in +self+.
 *  - #pos=: Sets the byte offset in +self+.
 *  - #reopen: Reassociates +self+ with a new or existing \IO stream.
 *  - #rewind: Positions +self+ to the beginning of input.
 *  - #seek: Sets the offset for +self+ relative to given position.
 *
 *  === Iterating
 *
 *  - ::foreach: Yields each line of given file to the block.
 *  - #each (aliased as #each_line): Calls the given block
 *    with each successive line in +self+.
 *  - #each_byte: Calls the given block with each successive byte in +self+
 *    as an integer.
 *  - #each_char: Calls the given block with each successive character in +self+
 *    as a string.
 *  - #each_codepoint: Calls the given block with each successive codepoint in +self+
 *    as an integer.
 *
 *  === Settings
 *
 *  - #autoclose=: Sets whether +self+ auto-closes.
 *  - #binmode: Sets +self+ to binary mode.
 *  - #close: Closes +self+.
 *  - #close_on_exec=: Sets the close-on-exec flag.
 *  - #close_read: Closes +self+ for reading.
 *  - #close_write: Closes +self+ for writing.
 *  - #set_encoding: Sets the encoding for +self+.
 *  - #set_encoding_by_bom: Sets the encoding for +self+, based on its
 *    Unicode byte-order-mark.
 *  - #sync=: Sets the sync-mode to the given value.
 *
 *  === Querying
 *
 *  - #autoclose?: Returns whether +self+ auto-closes.
 *  - #binmode?: Returns whether +self+ is in binary mode.
 *  - #close_on_exec?: Returns the close-on-exec flag for +self+.
 *  - #closed?: Returns whether +self+ is closed.
 *  - #eof? (aliased as #eof): Returns whether +self+ is at end-of-stream.
 *  - #external_encoding: Returns the external encoding object for +self+.
 *  - #fileno (aliased as #to_i): Returns the integer file descriptor for +self+
 *  - #internal_encoding: Returns the internal encoding object for +self+.
 *  - #pid: Returns the process ID of a child process associated with +self+,
 *    if +self+ was created by ::popen.
 *  - #stat: Returns the File::Stat object containing status information for +self+.
 *  - #sync: Returns whether +self+ is in sync-mode.
 *  - #tty? (aliased as #isatty): Returns whether +self+ is a terminal.
 *
 *  === Buffering
 *
 *  - #fdatasync: Immediately writes all buffered data in +self+ to disk.
 *  - #flush: Flushes any buffered data within +self+ to the underlying
 *    operating system.
 *  - #fsync: Immediately writes all buffered data and attributes in +self+ to disk.
 *  - #ungetbyte: Prepends buffer for +self+ with given integer byte or string.
 *  - #ungetc: Prepends buffer for +self+ with given string.
 *
 *  === Low-Level Access
 *
 *  - ::sysopen: Opens the file given by its path,
 *    returning the integer file descriptor.
 *  - #advise: Announces the intention to access data from +self+ in a specific way.
 *  - #fcntl: Passes a low-level command to the file specified
 *    by the given file descriptor.
 *  - #ioctl: Passes a low-level command to the device specified
 *    by the given file descriptor.
 *  - #sysread: Returns up to the next _n_ bytes read from self using a low-level read.
 *  - #sysseek: Sets the offset for +self+.
 *  - #syswrite: Writes the given string to +self+ using a low-level write.
 *
 *  === Other
 *
 *  - ::copy_stream: Copies data from a source to a destination,
 *    each of which is a filepath or an \IO-like object.
 *  - ::try_convert: Returns a new \IO object resulting from converting
 *    the given object.
 *  - #inspect: Returns the string representation of +self+.
 *
 */

void
Init_IO(void)
{
    VALUE rb_cARGF;
#ifdef __CYGWIN__
#include <sys/cygwin.h>
    static struct __cygwin_perfile pf[] =
    {
        {"", O_RDONLY | O_BINARY},
        {"", O_WRONLY | O_BINARY},
        {"", O_RDWR | O_BINARY},
        {"", O_APPEND | O_BINARY},
        {NULL, 0}
    };
    cygwin_internal(CW_PERFILE, pf);
#endif

    rb_eIOError = rb_define_class("IOError", rb_eStandardError);
    rb_eEOFError = rb_define_class("EOFError", rb_eIOError);

    id_write = rb_intern_const("write");
    id_read = rb_intern_const("read");
    id_getc = rb_intern_const("getc");
    id_flush = rb_intern_const("flush");
    id_readpartial = rb_intern_const("readpartial");
    id_set_encoding = rb_intern_const("set_encoding");
    id_fileno = rb_intern_const("fileno");

    rb_define_global_function("syscall", rb_f_syscall, -1);

    rb_define_global_function("open", rb_f_open, -1);
    rb_define_global_function("printf", rb_f_printf, -1);
    rb_define_global_function("print", rb_f_print, -1);
    rb_define_global_function("putc", rb_f_putc, 1);
    rb_define_global_function("puts", rb_f_puts, -1);
    rb_define_global_function("gets", rb_f_gets, -1);
    rb_define_global_function("readline", rb_f_readline, -1);
    rb_define_global_function("select", rb_f_select, -1);

    rb_define_global_function("readlines", rb_f_readlines, -1);

    rb_define_global_function("`", rb_f_backquote, 1);

    rb_define_global_function("p", rb_f_p, -1);
    rb_define_method(rb_mKernel, "display", rb_obj_display, -1);

    rb_cIO = rb_define_class("IO", rb_cObject);
    rb_include_module(rb_cIO, rb_mEnumerable);

    /* Can be raised by IO operations when IO#timeout= is set. */
    rb_eIOTimeoutError = rb_define_class_under(rb_cIO, "TimeoutError", rb_eIOError);

    /* Readable event mask for IO#wait. */
    rb_define_const(rb_cIO, "READABLE", INT2NUM(RUBY_IO_READABLE));
    /* Writable event mask for IO#wait. */
    rb_define_const(rb_cIO, "WRITABLE", INT2NUM(RUBY_IO_WRITABLE));
    /* Priority event mask for IO#wait. */
    rb_define_const(rb_cIO, "PRIORITY", INT2NUM(RUBY_IO_PRIORITY));

    /* exception to wait for reading. see IO.select. */
    rb_mWaitReadable = rb_define_module_under(rb_cIO, "WaitReadable");
    /* exception to wait for writing. see IO.select. */
    rb_mWaitWritable = rb_define_module_under(rb_cIO, "WaitWritable");
    /* exception to wait for reading by EAGAIN. see IO.select. */
    rb_eEAGAINWaitReadable = rb_define_class_under(rb_cIO, "EAGAINWaitReadable", rb_eEAGAIN);
    rb_include_module(rb_eEAGAINWaitReadable, rb_mWaitReadable);
    /* exception to wait for writing by EAGAIN. see IO.select. */
    rb_eEAGAINWaitWritable = rb_define_class_under(rb_cIO, "EAGAINWaitWritable", rb_eEAGAIN);
    rb_include_module(rb_eEAGAINWaitWritable, rb_mWaitWritable);
#if EAGAIN == EWOULDBLOCK
    rb_eEWOULDBLOCKWaitReadable = rb_eEAGAINWaitReadable;
    /* same as IO::EAGAINWaitReadable */
    rb_define_const(rb_cIO, "EWOULDBLOCKWaitReadable", rb_eEAGAINWaitReadable);
    rb_eEWOULDBLOCKWaitWritable = rb_eEAGAINWaitWritable;
    /* same as IO::EAGAINWaitWritable */
    rb_define_const(rb_cIO, "EWOULDBLOCKWaitWritable", rb_eEAGAINWaitWritable);
#else
    /* exception to wait for reading by EWOULDBLOCK. see IO.select. */
    rb_eEWOULDBLOCKWaitReadable = rb_define_class_under(rb_cIO, "EWOULDBLOCKWaitReadable", rb_eEWOULDBLOCK);
    rb_include_module(rb_eEWOULDBLOCKWaitReadable, rb_mWaitReadable);
    /* exception to wait for writing by EWOULDBLOCK. see IO.select. */
    rb_eEWOULDBLOCKWaitWritable = rb_define_class_under(rb_cIO, "EWOULDBLOCKWaitWritable", rb_eEWOULDBLOCK);
    rb_include_module(rb_eEWOULDBLOCKWaitWritable, rb_mWaitWritable);
#endif
    /* exception to wait for reading by EINPROGRESS. see IO.select. */
    rb_eEINPROGRESSWaitReadable = rb_define_class_under(rb_cIO, "EINPROGRESSWaitReadable", rb_eEINPROGRESS);
    rb_include_module(rb_eEINPROGRESSWaitReadable, rb_mWaitReadable);
    /* exception to wait for writing by EINPROGRESS. see IO.select. */
    rb_eEINPROGRESSWaitWritable = rb_define_class_under(rb_cIO, "EINPROGRESSWaitWritable", rb_eEINPROGRESS);
    rb_include_module(rb_eEINPROGRESSWaitWritable, rb_mWaitWritable);

#if 0
    /* This is necessary only for forcing rdoc handle File::open */
    rb_define_singleton_method(rb_cFile, "open",  rb_io_s_open, -1);
#endif

    rb_define_alloc_func(rb_cIO, io_alloc);
    rb_define_singleton_method(rb_cIO, "new", rb_io_s_new, -1);
    rb_define_singleton_method(rb_cIO, "open",  rb_io_s_open, -1);
    rb_define_singleton_method(rb_cIO, "sysopen",  rb_io_s_sysopen, -1);
    rb_define_singleton_method(rb_cIO, "for_fd", rb_io_s_for_fd, -1);
    rb_define_singleton_method(rb_cIO, "popen", rb_io_s_popen, -1);
    rb_define_singleton_method(rb_cIO, "foreach", rb_io_s_foreach, -1);
    rb_define_singleton_method(rb_cIO, "readlines", rb_io_s_readlines, -1);
    rb_define_singleton_method(rb_cIO, "read", rb_io_s_read, -1);
    rb_define_singleton_method(rb_cIO, "binread", rb_io_s_binread, -1);
    rb_define_singleton_method(rb_cIO, "write", rb_io_s_write, -1);
    rb_define_singleton_method(rb_cIO, "binwrite", rb_io_s_binwrite, -1);
    rb_define_singleton_method(rb_cIO, "select", rb_f_select, -1);
    rb_define_singleton_method(rb_cIO, "pipe", rb_io_s_pipe, -1);
    rb_define_singleton_method(rb_cIO, "try_convert", rb_io_s_try_convert, 1);
    rb_define_singleton_method(rb_cIO, "copy_stream", rb_io_s_copy_stream, -1);

    rb_define_method(rb_cIO, "initialize", rb_io_initialize, -1);

    rb_output_fs = Qnil;
    rb_define_hooked_variable("$,", &rb_output_fs, 0, deprecated_str_setter);

    rb_default_rs = rb_fstring_lit("\n"); /* avoid modifying RS_default */
    rb_vm_register_global_object(rb_default_rs);
    rb_rs = rb_default_rs;
    rb_output_rs = Qnil;
    rb_define_hooked_variable("$/", &rb_rs, 0, deprecated_rs_setter);
    rb_gvar_ractor_local("$/"); // not local but ractor safe
    rb_define_hooked_variable("$-0", &rb_rs, 0, deprecated_rs_setter);
    rb_gvar_ractor_local("$-0"); // not local but ractor safe
    rb_define_hooked_variable("$\\", &rb_output_rs, 0, deprecated_str_setter);

    rb_define_virtual_variable("$_", get_LAST_READ_LINE, set_LAST_READ_LINE);
    rb_gvar_ractor_local("$_");

    rb_define_method(rb_cIO, "initialize_copy", rb_io_init_copy, 1);
    rb_define_method(rb_cIO, "reopen", rb_io_reopen, -1);

    rb_define_method(rb_cIO, "print", rb_io_print, -1);
    rb_define_method(rb_cIO, "putc", rb_io_putc, 1);
    rb_define_method(rb_cIO, "puts", rb_io_puts, -1);
    rb_define_method(rb_cIO, "printf", rb_io_printf, -1);

    rb_define_method(rb_cIO, "each",  rb_io_each_line, -1);
    rb_define_method(rb_cIO, "each_line",  rb_io_each_line, -1);
    rb_define_method(rb_cIO, "each_byte",  rb_io_each_byte, 0);
    rb_define_method(rb_cIO, "each_char",  rb_io_each_char, 0);
    rb_define_method(rb_cIO, "each_codepoint",  rb_io_each_codepoint, 0);

    rb_define_method(rb_cIO, "syswrite", rb_io_syswrite, 1);
    rb_define_method(rb_cIO, "sysread",  rb_io_sysread, -1);

    rb_define_method(rb_cIO, "pread", rb_io_pread, -1);
    rb_define_method(rb_cIO, "pwrite", rb_io_pwrite, 2);

    rb_define_method(rb_cIO, "fileno", rb_io_fileno, 0);
    rb_define_alias(rb_cIO, "to_i", "fileno");
    rb_define_method(rb_cIO, "to_io", rb_io_to_io, 0);

    rb_define_method(rb_cIO, "timeout", rb_io_timeout, 0);
    rb_define_method(rb_cIO, "timeout=", rb_io_set_timeout, 1);

    rb_define_method(rb_cIO, "fsync", rb_io_fsync, 0);
    rb_define_method(rb_cIO, "fdatasync", rb_io_fdatasync, 0);
    rb_define_method(rb_cIO, "sync", rb_io_sync, 0);
    rb_define_method(rb_cIO, "sync=", rb_io_set_sync, 1);

    rb_define_method(rb_cIO, "lineno", rb_io_lineno, 0);
    rb_define_method(rb_cIO, "lineno=", rb_io_set_lineno, 1);

    rb_define_method(rb_cIO, "readlines", rb_io_readlines, -1);

    rb_define_method(rb_cIO, "readpartial", io_readpartial, -1);
    rb_define_method(rb_cIO, "read", io_read, -1);
    rb_define_method(rb_cIO, "write", io_write_m, -1);
    rb_define_method(rb_cIO, "gets", rb_io_gets_m, -1);
    rb_define_method(rb_cIO, "getc", rb_io_getc, 0);
    rb_define_method(rb_cIO, "getbyte", rb_io_getbyte, 0);
    rb_define_method(rb_cIO, "readchar",  rb_io_readchar, 0);
    rb_define_method(rb_cIO, "readbyte",  rb_io_readbyte, 0);
    rb_define_method(rb_cIO, "ungetbyte",rb_io_ungetbyte, 1);
    rb_define_method(rb_cIO, "ungetc",rb_io_ungetc, 1);
    rb_define_method(rb_cIO, "<<",    rb_io_addstr, 1);
    rb_define_method(rb_cIO, "flush", rb_io_flush, 0);
    rb_define_method(rb_cIO, "tell", rb_io_tell, 0);
    rb_define_method(rb_cIO, "seek", rb_io_seek_m, -1);
    /* Set I/O position from the beginning */
    rb_define_const(rb_cIO, "SEEK_SET", INT2FIX(SEEK_SET));
    /* Set I/O position from the current position */
    rb_define_const(rb_cIO, "SEEK_CUR", INT2FIX(SEEK_CUR));
    /* Set I/O position from the end */
    rb_define_const(rb_cIO, "SEEK_END", INT2FIX(SEEK_END));
#ifdef SEEK_DATA
    /* Set I/O position to the next location containing data */
    rb_define_const(rb_cIO, "SEEK_DATA", INT2FIX(SEEK_DATA));
#endif
#ifdef SEEK_HOLE
    /* Set I/O position to the next hole */
    rb_define_const(rb_cIO, "SEEK_HOLE", INT2FIX(SEEK_HOLE));
#endif
    rb_define_method(rb_cIO, "rewind", rb_io_rewind, 0);
    rb_define_method(rb_cIO, "pos", rb_io_tell, 0);
    rb_define_method(rb_cIO, "pos=", rb_io_set_pos, 1);
    rb_define_method(rb_cIO, "eof", rb_io_eof, 0);
    rb_define_method(rb_cIO, "eof?", rb_io_eof, 0);

    rb_define_method(rb_cIO, "close_on_exec?", rb_io_close_on_exec_p, 0);
    rb_define_method(rb_cIO, "close_on_exec=", rb_io_set_close_on_exec, 1);

    rb_define_method(rb_cIO, "close", rb_io_close_m, 0);
    rb_define_method(rb_cIO, "closed?", rb_io_closed_p, 0);
    rb_define_method(rb_cIO, "close_read", rb_io_close_read, 0);
    rb_define_method(rb_cIO, "close_write", rb_io_close_write, 0);

    rb_define_method(rb_cIO, "isatty", rb_io_isatty, 0);
    rb_define_method(rb_cIO, "tty?", rb_io_isatty, 0);
    rb_define_method(rb_cIO, "binmode",  rb_io_binmode_m, 0);
    rb_define_method(rb_cIO, "binmode?", rb_io_binmode_p, 0);
    rb_define_method(rb_cIO, "sysseek", rb_io_sysseek, -1);
    rb_define_method(rb_cIO, "advise", rb_io_advise, -1);

    rb_define_method(rb_cIO, "ioctl", rb_io_ioctl, -1);
    rb_define_method(rb_cIO, "fcntl", rb_io_fcntl, -1);
    rb_define_method(rb_cIO, "pid", rb_io_pid, 0);

    rb_define_method(rb_cIO, "path", rb_io_path, 0);
    rb_define_method(rb_cIO, "to_path", rb_io_path, 0);

    rb_define_method(rb_cIO, "inspect",  rb_io_inspect, 0);

    rb_define_method(rb_cIO, "external_encoding", rb_io_external_encoding, 0);
    rb_define_method(rb_cIO, "internal_encoding", rb_io_internal_encoding, 0);
    rb_define_method(rb_cIO, "set_encoding", rb_io_set_encoding, -1);
    rb_define_method(rb_cIO, "set_encoding_by_bom", rb_io_set_encoding_by_bom, 0);

    rb_define_method(rb_cIO, "autoclose?", rb_io_autoclose_p, 0);
    rb_define_method(rb_cIO, "autoclose=", rb_io_set_autoclose, 1);

    rb_define_method(rb_cIO, "wait", io_wait, -1);

    rb_define_method(rb_cIO, "wait_readable", io_wait_readable, -1);
    rb_define_method(rb_cIO, "wait_writable", io_wait_writable, -1);
    rb_define_method(rb_cIO, "wait_priority", io_wait_priority, -1);

    rb_define_virtual_variable("$stdin",  stdin_getter,  stdin_setter);
    rb_define_virtual_variable("$stdout", stdout_getter, stdout_setter);
    rb_define_virtual_variable("$>",      stdout_getter, stdout_setter);
    rb_define_virtual_variable("$stderr", stderr_getter, stderr_setter);

    rb_gvar_ractor_local("$stdin");
    rb_gvar_ractor_local("$stdout");
    rb_gvar_ractor_local("$>");
    rb_gvar_ractor_local("$stderr");

    rb_global_variable(&rb_stdin);
    rb_stdin  = rb_io_prep_stdin();
    rb_global_variable(&rb_stdout);
    rb_stdout = rb_io_prep_stdout();
    rb_global_variable(&rb_stderr);
    rb_stderr = rb_io_prep_stderr();

    orig_stdout = rb_stdout;
    orig_stderr = rb_stderr;

    /* Holds the original stdin */
    rb_define_global_const("STDIN", rb_stdin);
    /* Holds the original stdout */
    rb_define_global_const("STDOUT", rb_stdout);
    /* Holds the original stderr */
    rb_define_global_const("STDERR", rb_stderr);

#if 0
    /* Hack to get rdoc to regard ARGF as a class: */
    rb_cARGF = rb_define_class("ARGF", rb_cObject);
#endif

    rb_cARGF = rb_class_new(rb_cObject);
    rb_set_class_path(rb_cARGF, rb_cObject, "ARGF.class");
    rb_define_alloc_func(rb_cARGF, argf_alloc);

    rb_include_module(rb_cARGF, rb_mEnumerable);

    rb_define_method(rb_cARGF, "initialize", argf_initialize, -2);
    rb_define_method(rb_cARGF, "initialize_copy", argf_initialize_copy, 1);
    rb_define_method(rb_cARGF, "to_s", argf_to_s, 0);
    rb_define_alias(rb_cARGF, "inspect", "to_s");
    rb_define_method(rb_cARGF, "argv", argf_argv, 0);

    rb_define_method(rb_cARGF, "fileno", argf_fileno, 0);
    rb_define_method(rb_cARGF, "to_i", argf_fileno, 0);
    rb_define_method(rb_cARGF, "to_io", argf_to_io, 0);
    rb_define_method(rb_cARGF, "to_write_io", argf_write_io, 0);
    rb_define_method(rb_cARGF, "each",  argf_each_line, -1);
    rb_define_method(rb_cARGF, "each_line",  argf_each_line, -1);
    rb_define_method(rb_cARGF, "each_byte",  argf_each_byte, 0);
    rb_define_method(rb_cARGF, "each_char",  argf_each_char, 0);
    rb_define_method(rb_cARGF, "each_codepoint",  argf_each_codepoint, 0);

    rb_define_method(rb_cARGF, "read",  argf_read, -1);
    rb_define_method(rb_cARGF, "readpartial",  argf_readpartial, -1);
    rb_define_method(rb_cARGF, "read_nonblock",  argf_read_nonblock, -1);
    rb_define_method(rb_cARGF, "readlines", argf_readlines, -1);
    rb_define_method(rb_cARGF, "to_a", argf_readlines, -1);
    rb_define_method(rb_cARGF, "gets", argf_gets, -1);
    rb_define_method(rb_cARGF, "readline", argf_readline, -1);
    rb_define_method(rb_cARGF, "getc", argf_getc, 0);
    rb_define_method(rb_cARGF, "getbyte", argf_getbyte, 0);
    rb_define_method(rb_cARGF, "readchar", argf_readchar, 0);
    rb_define_method(rb_cARGF, "readbyte", argf_readbyte, 0);
    rb_define_method(rb_cARGF, "tell", argf_tell, 0);
    rb_define_method(rb_cARGF, "seek", argf_seek_m, -1);
    rb_define_method(rb_cARGF, "rewind", argf_rewind, 0);
    rb_define_method(rb_cARGF, "pos", argf_tell, 0);
    rb_define_method(rb_cARGF, "pos=", argf_set_pos, 1);
    rb_define_method(rb_cARGF, "eof", argf_eof, 0);
    rb_define_method(rb_cARGF, "eof?", argf_eof, 0);
    rb_define_method(rb_cARGF, "binmode", argf_binmode_m, 0);
    rb_define_method(rb_cARGF, "binmode?", argf_binmode_p, 0);

    rb_define_method(rb_cARGF, "write", argf_write, -1);
    rb_define_method(rb_cARGF, "print", rb_io_print, -1);
    rb_define_method(rb_cARGF, "putc", rb_io_putc, 1);
    rb_define_method(rb_cARGF, "puts", rb_io_puts, -1);
    rb_define_method(rb_cARGF, "printf", rb_io_printf, -1);

    rb_define_method(rb_cARGF, "filename", argf_filename, 0);
    rb_define_method(rb_cARGF, "path", argf_filename, 0);
    rb_define_method(rb_cARGF, "file", argf_file, 0);
    rb_define_method(rb_cARGF, "skip", argf_skip, 0);
    rb_define_method(rb_cARGF, "close", argf_close_m, 0);
    rb_define_method(rb_cARGF, "closed?", argf_closed, 0);

    rb_define_method(rb_cARGF, "lineno",   argf_lineno, 0);
    rb_define_method(rb_cARGF, "lineno=",  argf_set_lineno, 1);

    rb_define_method(rb_cARGF, "inplace_mode", argf_inplace_mode_get, 0);
    rb_define_method(rb_cARGF, "inplace_mode=", argf_inplace_mode_set, 1);

    rb_define_method(rb_cARGF, "external_encoding", argf_external_encoding, 0);
    rb_define_method(rb_cARGF, "internal_encoding", argf_internal_encoding, 0);
    rb_define_method(rb_cARGF, "set_encoding", argf_set_encoding, -1);

    argf = rb_class_new_instance(0, 0, rb_cARGF);

    rb_define_readonly_variable("$<", &argf);
    /*
     * ARGF is a stream designed for use in scripts that process files given
     * as command-line arguments or passed in via STDIN.
     *
     * See ARGF (the class) for more details.
     */
    rb_define_global_const("ARGF", argf);

    rb_define_hooked_variable("$.", &argf, argf_lineno_getter, argf_lineno_setter);
    rb_define_hooked_variable("$FILENAME", &argf, argf_filename_getter, rb_gvar_readonly_setter);
    ARGF.filename = rb_str_new2("-");

    rb_define_hooked_variable("$-i", &argf, opt_i_get, opt_i_set);
    rb_gvar_ractor_local("$-i");

    rb_define_hooked_variable("$*", &argf, argf_argv_getter, rb_gvar_readonly_setter);

#if defined (_WIN32) || defined(__CYGWIN__)
    atexit(pipe_atexit);
#endif

    Init_File();

    rb_define_method(rb_cFile, "initialize",  rb_file_initialize, -1);

    sym_mode = ID2SYM(rb_intern_const("mode"));
    sym_perm = ID2SYM(rb_intern_const("perm"));
    sym_flags = ID2SYM(rb_intern_const("flags"));
    sym_extenc = ID2SYM(rb_intern_const("external_encoding"));
    sym_intenc = ID2SYM(rb_intern_const("internal_encoding"));
    sym_encoding = ID2SYM(rb_id_encoding());
    sym_open_args = ID2SYM(rb_intern_const("open_args"));
    sym_textmode = ID2SYM(rb_intern_const("textmode"));
    sym_binmode = ID2SYM(rb_intern_const("binmode"));
    sym_autoclose = ID2SYM(rb_intern_const("autoclose"));
    sym_normal = ID2SYM(rb_intern_const("normal"));
    sym_sequential = ID2SYM(rb_intern_const("sequential"));
    sym_random = ID2SYM(rb_intern_const("random"));
    sym_willneed = ID2SYM(rb_intern_const("willneed"));
    sym_dontneed = ID2SYM(rb_intern_const("dontneed"));
    sym_noreuse = ID2SYM(rb_intern_const("noreuse"));
    sym_SET = ID2SYM(rb_intern_const("SET"));
    sym_CUR = ID2SYM(rb_intern_const("CUR"));
    sym_END = ID2SYM(rb_intern_const("END"));
#ifdef SEEK_DATA
    sym_DATA = ID2SYM(rb_intern_const("DATA"));
#endif
#ifdef SEEK_HOLE
    sym_HOLE = ID2SYM(rb_intern_const("HOLE"));
#endif
    sym_wait_readable = ID2SYM(rb_intern_const("wait_readable"));
    sym_wait_writable = ID2SYM(rb_intern_const("wait_writable"));
}

#include "io.rbinc"
