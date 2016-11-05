/**********************************************************************

  io.c -

  $Author$
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "internal.h"
#include "ruby/io.h"
#include "ruby/thread.h"
#include "dln.h"
#include "encindex.h"
#include "id.h"
#include <ctype.h>
#include <errno.h>
#include "ruby_atomic.h"

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
#include "unix.h"
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

#if !HAVE_OFF_T && !defined(off_t)
# define off_t  long
#endif
#if SIZEOF_OFF_T > SIZEOF_LONG && defined(HAVE_LONG_LONG)
# define PRI_OFF_T_PREFIX "ll"
#elif SIZEOF_OFF_T == SIZEOF_LONG
# define PRI_OFF_T_PREFIX "l"
#else
# define PRI_OFF_T_PREFIX ""
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

#include "ruby/util.h"

#ifndef O_ACCMODE
#define O_ACCMODE (O_RDONLY | O_WRONLY | O_RDWR)
#endif

#if SIZEOF_OFF_T > SIZEOF_LONG && !defined(HAVE_LONG_LONG)
# error off_t is bigger than long, but you have no long long...
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

#ifdef __native_client__
# undef F_GETFD
# ifdef NACL_NEWLIB
#  undef HAVE_IOCTL
# endif
#endif

#define IO_RBUF_CAPA_MIN  8192
#define IO_CBUF_CAPA_MIN  (128*1024)
#define IO_RBUF_CAPA_FOR(fptr) (NEED_READCONV(fptr) ? IO_CBUF_CAPA_MIN : IO_RBUF_CAPA_MIN)
#define IO_WBUF_CAPA_MIN  8192

/* define system APIs */
#ifdef _WIN32
#undef open
#define open	rb_w32_uopen
#endif

VALUE rb_cIO;
VALUE rb_eEOFError;
VALUE rb_eIOError;
VALUE rb_mWaitReadable;
VALUE rb_mWaitWritable;

static VALUE rb_eEAGAINWaitReadable;
static VALUE rb_eEAGAINWaitWritable;
static VALUE rb_eEWOULDBLOCKWaitReadable;
static VALUE rb_eEWOULDBLOCKWaitWritable;
static VALUE rb_eEINPROGRESSWaitWritable;
static VALUE rb_eEINPROGRESSWaitReadable;

VALUE rb_stdin, rb_stdout, rb_stderr;
VALUE rb_deferr;		/* rescue VIM plugin */
static VALUE orig_stdout, orig_stderr;

VALUE rb_output_fs;
VALUE rb_rs;
VALUE rb_output_rs;
VALUE rb_default_rs;

static VALUE argf;

#define id_exception idException
static ID id_write, id_read, id_getc, id_flush, id_readpartial, id_set_encoding;
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

struct argf {
    VALUE filename, current_file;
    long last_lineno;		/* $. */
    long lineno;
    VALUE argv;
    char *inplace;
    struct rb_io_enc_t encs;
    int8_t init_p, next_p, binmode;
};

static rb_atomic_t max_file_descriptor = NOFILE;
void
rb_update_max_fd(int fd)
{
    struct stat buf;
    rb_atomic_t afd = (rb_atomic_t)fd;

    if (afd <= max_file_descriptor)
        return;

    if (fstat(fd, &buf) != 0 && errno == EBADF) {
        rb_bug("rb_update_max_fd: invalid fd (%d) given.", fd);
    }

    while (max_file_descriptor < afd) {
	ATOMIC_CAS(max_file_descriptor, max_file_descriptor, afd);
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
        if (ret == -1) {
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

int
rb_cloexec_open(const char *pathname, int flags, mode_t mode)
{
    int ret;
    static int o_cloexec_state = -1; /* <0: unknown, 0: ignored, >0: working */

#ifdef O_CLOEXEC
    /* O_CLOEXEC is available since Linux 2.6.23.  Linux 2.6.18 silently ignore it. */
    flags |= O_CLOEXEC;
#elif defined O_NOINHERIT
    flags |= O_NOINHERIT;
#endif
    ret = open(pathname, flags, mode);
    if (ret == -1) return -1;
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
        if (ret == -1) return -1;
    }
    rb_maygvl_fd_fix_cloexec(ret);
    return ret;
}

int
rb_cloexec_pipe(int fildes[2])
{
    int ret;

#if defined(HAVE_PIPE2)
    static int try_pipe2 = 1;
    if (try_pipe2) {
        ret = pipe2(fildes, O_CLOEXEC);
        if (ret != -1)
            return ret;
        /* pipe2 is available since Linux 2.6.27, glibc 2.9. */
        if (errno == ENOSYS) {
            try_pipe2 = 0;
            ret = pipe(fildes);
        }
    }
    else {
        ret = pipe(fildes);
    }
#else
    ret = pipe(fildes);
#endif
    if (ret == -1) return -1;
#ifdef __CYGWIN__
    if (ret == 0 && fildes[1] == -1) {
	close(fildes[0]);
	fildes[0] = -1;
	errno = ENFILE;
	return -1;
    }
#endif
    rb_maygvl_fd_fix_cloexec(fildes[0]);
    rb_maygvl_fd_fix_cloexec(fildes[1]);
    return ret;
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
#elif defined(HAVE_DUP)
    ret = dup(fd);
    if (ret != -1 && ret < minfd) {
        const int prev_fd = ret;
        ret = rb_cloexec_fcntl_dupfd(fd, minfd);
        close(prev_fd);
    }
    return ret;
#else
# error "dup() or fcntl(F_DUPFD) must be supported."
#endif
    if (ret == -1) return -1;
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
    (rb_w32_io_cancelable_p((fptr)->fd) ? 0 : rb_thread_wait_fd((fptr)->fd))
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
static rb_io_t *flush_before_seek(rb_io_t *fptr);

#define NEED_NEWLINE_DECORATOR_ON_READ(fptr) ((fptr)->mode & FMODE_TEXTMODE)
#define NEED_NEWLINE_DECORATOR_ON_WRITE(fptr) ((fptr)->mode & FMODE_TEXTMODE)
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
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
#define NEED_WRITECONV(fptr) (((fptr)->encs.enc != NULL && (fptr)->encs.enc != rb_ascii8bit_encoding()) || ((fptr)->encs.ecflags & ((ECONV_DECORATOR_MASK & ~ECONV_CRLF_NEWLINE_DECORATOR)|ECONV_STATEFUL_DECORATOR_MASK)))
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
io_unread(rb_io_t *fptr)
{
    off_t r, pos;
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
	    return;
	}

	fptr->rbuf.off = 0;
	fptr->rbuf.len = 0;
	return;
    }

    pos = lseek(fptr->fd, 0, SEEK_CUR);
    if (pos < 0 && errno) {
	if (errno == ESPIPE)
	    fptr->mode |= FMODE_DUPLEX;
	return;
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
    fptr->rbuf.off = 0;
    fptr->rbuf.len = 0;
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
    flush_before_seek(fptr);
    return setmode(fptr->fd, O_BINARY);
}
#define SET_BINARY_MODE_WITH_SEEK_CUR(fptr) set_binary_mode_with_seek_cur(fptr)

#else
/* Unix */
# define DEFAULT_TEXTMODE 0
#define NEED_READCONV(fptr) ((fptr)->encs.enc2 != NULL || NEED_NEWLINE_DECORATOR_ON_READ(fptr))
#define NEED_WRITECONV(fptr) (((fptr)->encs.enc != NULL && (fptr)->encs.enc != rb_ascii8bit_encoding()) || NEED_NEWLINE_DECORATOR_ON_WRITE(fptr) || ((fptr)->encs.ecflags & (ECONV_DECORATOR_MASK|ECONV_STATEFUL_DECORATOR_MASK)))
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
    if (fptr->fd < 0) {
	rb_raise(rb_eIOError, closed_stream);
    }
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
    return rb_convert_type(io, T_FILE, "IO", "to_io");
}

VALUE
rb_io_check_io(VALUE io)
{
    return rb_check_convert_type(io, T_FILE, "IO", "to_io");
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
 *     IO.try_convert(obj)  ->  io or nil
 *
 *  Try to convert <i>obj</i> into an IO, using to_io method.
 *  Returns converted IO or nil if <i>obj</i> cannot be converted
 *  for any reason.
 *
 *     IO.try_convert(STDOUT)     #=> STDOUT
 *     IO.try_convert("STDOUT")   #=> nil
 *
 *     require 'zlib'
 *     f = open("/tmp/zz.gz")       #=> #<File:/tmp/zz.gz>
 *     z = Zlib::GzipReader.open(f) #=> #<Zlib::GzipReader:0x81d8744>
 *     IO.try_convert(z)            #=> #<File:/tmp/zz.gz>
 *
 */
static VALUE
rb_io_s_try_convert(VALUE dummy, VALUE io)
{
    return rb_io_check_io(io);
}

#if !(defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32))
static void
io_unread(rb_io_t *fptr)
{
    off_t r;
    rb_io_check_closed(fptr);
    if (fptr->rbuf.len == 0 || fptr->mode & FMODE_DUPLEX)
        return;
    /* xxx: target position may be negative if buffer is filled by ungetc */
    errno = 0;
    r = lseek(fptr->fd, -fptr->rbuf.len, SEEK_CUR);
    if (r < 0 && errno) {
        if (errno == ESPIPE)
            fptr->mode |= FMODE_DUPLEX;
        return;
    }
    fptr->rbuf.off = 0;
    fptr->rbuf.len = 0;
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
flush_before_seek(rb_io_t *fptr)
{
    if (io_fflush(fptr) < 0)
        rb_sys_fail(0);
    io_unread(fptr);
    errno = 0;
    return fptr;
}

#define io_seek(fptr, ofs, whence) (errno = 0, lseek(flush_before_seek(fptr)->fd, (ofs), (whence)))
#define io_tell(fptr) lseek(flush_before_seek(fptr)->fd, 0, SEEK_CUR)

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
            rb_sys_fail(0);
    }
    if (fptr->tied_io_for_writing) {
	rb_io_t *wfptr;
	GetOpenFile(fptr->tied_io_for_writing, wfptr);
        if (io_fflush(wfptr) < 0)
            rb_sys_fail(0);
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
        io_unread(fptr);
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
	rb_thread_wait_fd(fptr->fd);
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

static int
ruby_dup(int orig)
{
    int fd;

    fd = rb_cloexec_dup(orig);
    if (fd < 0) {
	if (rb_gc_for_fd(errno)) {
	    fd = rb_cloexec_dup(orig);
	}
	if (fd < 0) {
	    rb_sys_fail(0);
	}
    }
    rb_update_max_fd(fd);
    return fd;
}

static VALUE
io_alloc(VALUE klass)
{
    NEWOBJ_OF(io, struct RFile, klass, T_FILE);

    io->fptr = 0;

    return (VALUE)io;
}

#ifndef S_ISREG
#   define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#endif

struct io_internal_read_struct {
    int fd;
    void *buf;
    size_t capa;
};

struct io_internal_write_struct {
    int fd;
    const void *buf;
    size_t capa;
};

#ifdef HAVE_WRITEV
struct io_internal_writev_struct {
    int fd;
    int iovcnt;
    const struct iovec *iov;
};
#endif

static VALUE
internal_read_func(void *ptr)
{
    struct io_internal_read_struct *iis = ptr;
    return read(iis->fd, iis->buf, iis->capa);
}

static VALUE
internal_write_func(void *ptr)
{
    struct io_internal_write_struct *iis = ptr;
    return write(iis->fd, iis->buf, iis->capa);
}

static void*
internal_write_func2(void *ptr)
{
    struct io_internal_write_struct *iis = ptr;
    return (void*)(intptr_t)write(iis->fd, iis->buf, iis->capa);
}

#ifdef HAVE_WRITEV
static VALUE
internal_writev_func(void *ptr)
{
    struct io_internal_writev_struct *iis = ptr;
    return writev(iis->fd, iis->iov, iis->iovcnt);
}
#endif

static ssize_t
rb_read_internal(int fd, void *buf, size_t count)
{
    struct io_internal_read_struct iis;
    iis.fd = fd;
    iis.buf = buf;
    iis.capa = count;

    return (ssize_t)rb_thread_io_blocking_region(internal_read_func, &iis, fd);
}

static ssize_t
rb_write_internal(int fd, const void *buf, size_t count)
{
    struct io_internal_write_struct iis;
    iis.fd = fd;
    iis.buf = buf;
    iis.capa = count;

    return (ssize_t)rb_thread_io_blocking_region(internal_write_func, &iis, fd);
}

static ssize_t
rb_write_internal2(int fd, const void *buf, size_t count)
{
    struct io_internal_write_struct iis;
    iis.fd = fd;
    iis.buf = buf;
    iis.capa = count;

    return (ssize_t)rb_thread_call_without_gvl2(internal_write_func2, &iis,
						RUBY_UBF_IO, NULL);
}

#ifdef HAVE_WRITEV
static ssize_t
rb_writev_internal(int fd, const struct iovec *iov, int iovcnt)
{
    struct io_internal_writev_struct iis;
    iis.fd = fd;
    iis.iov = iov;
    iis.iovcnt = iovcnt;

    return (ssize_t)rb_thread_io_blocking_region(internal_writev_func, &iis, fd);
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

static void*
io_flush_buffer_sync2(void *arg)
{
    VALUE result = io_flush_buffer_sync(arg);

    /*
     * rb_thread_call_without_gvl2 uses 0 as interrupted.
     * So, we need to avoid to use 0.
     */
    return !result ? (void*)1 : (void*)result;
}

static VALUE
io_flush_buffer_async(VALUE arg)
{
    rb_io_t *fptr = (rb_io_t *)arg;
    return rb_thread_io_blocking_region(io_flush_buffer_sync, fptr, fptr->fd);
}

static VALUE
io_flush_buffer_async2(VALUE arg)
{
    rb_io_t *fptr = (rb_io_t *)arg;
    VALUE ret;

    ret = (VALUE)rb_thread_call_without_gvl2(io_flush_buffer_sync2, fptr,
					     RUBY_UBF_IO, NULL);

    if (!ret) {
	/* pending async interrupt is there. */
	errno = EAGAIN;
	return -1;
    }
    else if (ret == 1) {
	return 0;
    }
    return ret;
}

static inline int
io_flush_buffer(rb_io_t *fptr)
{
    if (fptr->write_lock) {
	if (rb_mutex_owned_p(fptr->write_lock))
	    return (int)io_flush_buffer_async2((VALUE)fptr);
	else
	    return (int)rb_mutex_synchronize(fptr->write_lock, io_flush_buffer_async2, (VALUE)fptr);
    }
    else {
	return (int)io_flush_buffer_async((VALUE)fptr);
    }
}

static int
io_fflush(rb_io_t *fptr)
{
    rb_io_check_closed(fptr);
    if (fptr->wbuf.len == 0)
        return 0;
    rb_io_check_closed(fptr);
    while (fptr->wbuf.len > 0 && io_flush_buffer(fptr) != 0) {
	if (!rb_io_wait_writable(fptr->fd))
	    return -1;
        rb_io_check_closed(fptr);
    }
    return 0;
}

int
rb_io_wait_readable(int f)
{
    if (f < 0) {
	rb_raise(rb_eIOError, closed_stream);
    }
    switch (errno) {
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
	rb_thread_check_ints();
	return TRUE;

      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
	rb_thread_wait_fd(f);
	return TRUE;

      default:
	return FALSE;
    }
}

int
rb_io_wait_writable(int f)
{
    if (f < 0) {
	rb_raise(rb_eIOError, closed_stream);
    }
    switch (errno) {
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
	/*
	 * In old Linux, several special files under /proc and /sys don't handle
	 * select properly. Thus we need avoid to call if don't use O_NONBLOCK.
	 * Otherwise, we face nasty hang up. Sigh.
	 * e.g. http://git.kernel.org/?p=linux/kernel/git/torvalds/linux-2.6.git;a=commit;h=31b07093c44a7a442394d44423e21d783f5523b8
	 * http://git.kernel.org/?p=linux/kernel/git/torvalds/linux-2.6.git;a=commit;h=31b07093c44a7a442394d44423e21d783f5523b8
	 * In EINTR case, we only need to call RUBY_VM_CHECK_INTS_BLOCKING().
	 * Then rb_thread_check_ints() is enough.
	 */
	rb_thread_check_ints();
	return TRUE;

      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
	rb_thread_fd_writable(f);
	return TRUE;

      default:
	return FALSE;
    }
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

        if (!fptr->encs.enc || (fptr->encs.enc == rb_ascii8bit_encoding() && !fptr->encs.enc2)) {
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
    VALUE str;
    const char *ptr;
    long length;
};

struct write_arg {
    VALUE io;
    VALUE str;
    int nosync;
};

#ifdef HAVE_WRITEV
static VALUE
io_binwrite_string(VALUE arg)
{
    struct binwrite_arg *p = (struct binwrite_arg *)arg;
    rb_io_t *fptr = p->fptr;
    long r;

    if (fptr->wbuf.len) {
	struct iovec iov[2];

	iov[0].iov_base = fptr->wbuf.ptr+fptr->wbuf.off;
	iov[0].iov_len = fptr->wbuf.len;
	iov[1].iov_base = (char *)p->ptr;
	iov[1].iov_len = p->length;

	r = rb_writev_internal(fptr->fd, iov, 2);

        if (r == -1)
            return -1;

	if (fptr->wbuf.len <= r) {
	    r -= fptr->wbuf.len;
	    fptr->wbuf.off = 0;
	    fptr->wbuf.len = 0;
	}
	else {
	    fptr->wbuf.off += (int)r;
	    fptr->wbuf.len -= (int)r;
	    r = 0L;
	}
    }
    else {
	r = rb_write_internal(fptr->fd, p->ptr, p->length);
    }

    return r;
}
#else
static VALUE
io_binwrite_string(VALUE arg)
{
    struct binwrite_arg *p = (struct binwrite_arg *)arg;
    rb_io_t *fptr = p->fptr;
    long l, len;

    l = len = p->length;

    if (fptr->wbuf.len) {
	if (fptr->wbuf.len+len <= fptr->wbuf.capa) {
	    if (fptr->wbuf.capa < fptr->wbuf.off+fptr->wbuf.len+len) {
		MEMMOVE(fptr->wbuf.ptr, fptr->wbuf.ptr+fptr->wbuf.off, char, fptr->wbuf.len);
		fptr->wbuf.off = 0;
	    }
	    MEMMOVE(fptr->wbuf.ptr+fptr->wbuf.off+fptr->wbuf.len, p->ptr, char, len);
	    fptr->wbuf.len += (int)len;
	    l = 0;
	}
	if (io_fflush(fptr) < 0)
	    return -2L; /* fail in fflush */
	if (l == 0)
	    return len;
    }

    if (fptr->stdio_file != stderr && !rb_thread_fd_writable(fptr->fd))
	rb_io_check_closed(fptr);

    return rb_write_internal(p->fptr->fd, p->ptr, p->length);
}
#endif

static long
io_binwrite(VALUE str, const char *ptr, long len, rb_io_t *fptr, int nosync)
{
    long n, r, offset = 0;

    /* don't write anything if current thread has a pending interrupt. */
    rb_thread_check_ints();

    if ((n = len) <= 0) return n;
    if (fptr->wbuf.ptr == NULL && !(!nosync && (fptr->mode & FMODE_SYNC))) {
        fptr->wbuf.off = 0;
        fptr->wbuf.len = 0;
        fptr->wbuf.capa = IO_WBUF_CAPA_MIN;
        fptr->wbuf.ptr = ALLOC_N(char, fptr->wbuf.capa);
	fptr->write_lock = rb_mutex_new();
	rb_mutex_allow_trap(fptr->write_lock, 1);
    }
    if ((!nosync && (fptr->mode & (FMODE_SYNC|FMODE_TTY))) ||
        (fptr->wbuf.ptr && fptr->wbuf.capa <= fptr->wbuf.len + len)) {
	struct binwrite_arg arg;

	arg.fptr = fptr;
	arg.str = str;
      retry:
	arg.ptr = ptr + offset;
	arg.length = n;
	if (fptr->write_lock) {
	    r = rb_mutex_synchronize(fptr->write_lock, io_binwrite_string, (VALUE)&arg);
	}
	else {
	    r = io_binwrite_string((VALUE)&arg);
	}
	/* xxx: other threads may modify given string. */
        if (r == n) return len;
        if (0 <= r) {
            offset += r;
            n -= r;
            errno = EAGAIN;
	}
	if (r == -2L)
	    return -1L;
        if (rb_io_wait_writable(fptr->fd)) {
            rb_io_check_closed(fptr);
	    if (offset < len)
		goto retry;
        }
        return -1L;
    }

    if (fptr->wbuf.off) {
        if (fptr->wbuf.len)
            MEMMOVE(fptr->wbuf.ptr, fptr->wbuf.ptr+fptr->wbuf.off, char, fptr->wbuf.len);
        fptr->wbuf.off = 0;
    }
    MEMMOVE(fptr->wbuf.ptr+fptr->wbuf.off+fptr->wbuf.len, ptr+offset, char, len);
    fptr->wbuf.len += (int)len;
    return len;
}

# define MODE_BTMODE(a,b,c) ((fmode & FMODE_BINMODE) ? (b) : \
                             (fmode & FMODE_TEXTMODE) ? (c) : (a))
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
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
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
#ifdef _WIN32
    if (fptr->mode & FMODE_TTY) {
	long len = rb_w32_write_console(str, fptr->fd);
	if (len > 0) return len;
    }
#endif
    str = do_writeconv(str, fptr, &converted);
    if (converted)
	OBJ_FREEZE(str);
    else
	str = rb_str_new_frozen(str);

    return io_binwrite(str, RSTRING_PTR(str), RSTRING_LEN(str),
		       fptr, nosync);
}

ssize_t
rb_io_bufwrite(VALUE io, const void *buf, size_t size)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);
    return (ssize_t)io_binwrite(0, buf, (long)size, fptr, 0);
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
    if (n == -1L) rb_sys_fail_path(fptr->pathv);

    return LONG2FIX(n);
}

/*
 *  call-seq:
 *     ios.write(string)    -> integer
 *
 *  Writes the given string to <em>ios</em>. The stream must be opened
 *  for writing. If the argument is not a string, it will be converted
 *  to a string using <code>to_s</code>. Returns the number of bytes
 *  written.
 *
 *     count = $stdout.write("This is a test\n")
 *     puts "That was #{count} bytes of data"
 *
 *  <em>produces:</em>
 *
 *     This is a test
 *     That was 15 bytes of data
 */

static VALUE
io_write_m(VALUE io, VALUE str)
{
    return io_write(io, str, 0);
}

VALUE
rb_io_write(VALUE io, VALUE str)
{
    return rb_funcallv(io, id_write, 1, &str);
}

/*
 *  call-seq:
 *     ios << obj     -> ios
 *
 *  String Output---Writes <i>obj</i> to <em>ios</em>.
 *  <i>obj</i> will be converted to a string using
 *  <code>to_s</code>.
 *
 *     $stdout << "Hello " << "world!\n"
 *
 *  <em>produces:</em>
 *
 *     Hello world!
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
            rb_sys_fail(0);
    }
    if (fptr->mode & FMODE_READABLE) {
        io_unread(fptr);
    }

    return io;
}

/*
 *  call-seq:
 *     ios.flush    -> ios
 *
 *  Flushes any buffered data within <em>ios</em> to the underlying
 *  operating system (note that this is Ruby internal buffering only;
 *  the OS may buffer the data as well).
 *
 *     $stdout.print "no newline"
 *     $stdout.flush
 *
 *  <em>produces:</em>
 *
 *     no newline
 */

VALUE
rb_io_flush(VALUE io)
{
    return rb_io_flush_raw(io, 1);
}

/*
 *  call-seq:
 *     ios.pos     -> integer
 *     ios.tell    -> integer
 *
 *  Returns the current offset (in bytes) of <em>ios</em>.
 *
 *     f = File.new("testfile")
 *     f.pos    #=> 0
 *     f.gets   #=> "This is line one\n"
 *     f.pos    #=> 17
 */

static VALUE
rb_io_tell(VALUE io)
{
    rb_io_t *fptr;
    off_t pos;

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
    off_t pos;

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
 *     ios.seek(amount, whence=IO::SEEK_SET)  ->  0
 *
 *  Seeks to a given offset <i>anInteger</i> in the stream according to
 *  the value of <i>whence</i>:
 *
 *    :CUR or IO::SEEK_CUR  | Seeks to _amount_ plus current position
 *    ----------------------+--------------------------------------------------
 *    :END or IO::SEEK_END  | Seeks to _amount_ plus end of stream (you
 *                          | probably want a negative value for _amount_)
 *    ----------------------+--------------------------------------------------
 *    :SET or IO::SEEK_SET  | Seeks to the absolute location given by _amount_
 *
 *  Example:
 *
 *     f = File.new("testfile")
 *     f.seek(-13, IO::SEEK_END)   #=> 0
 *     f.readline                  #=> "And so on...\n"
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
 *     ios.pos = integer    -> integer
 *
 *  Seeks to the given position (in bytes) in <em>ios</em>.
 *  It is not guaranteed that seeking to the right position when <em>ios</em>
 *  is textmode.
 *
 *     f = File.new("testfile")
 *     f.pos = 17
 *     f.gets   #=> "This is line two\n"
 */

static VALUE
rb_io_set_pos(VALUE io, VALUE offset)
{
    rb_io_t *fptr;
    off_t pos;

    pos = NUM2OFFT(offset);
    GetOpenFile(io, fptr);
    pos = io_seek(fptr, pos, SEEK_SET);
    if (pos < 0 && errno) rb_sys_fail_path(fptr->pathv);

    return OFFT2NUM(pos);
}

static void clear_readconv(rb_io_t *fptr);

/*
 *  call-seq:
 *     ios.rewind    -> 0
 *
 *  Positions <em>ios</em> to the beginning of input, resetting
 *  <code>lineno</code> to zero.
 *
 *     f = File.new("testfile")
 *     f.readline   #=> "This is line one\n"
 *     f.rewind     #=> 0
 *     f.lineno     #=> 0
 *     f.readline   #=> "This is line one\n"
 *
 *  Note that it cannot be used with streams such as pipes, ttys, and sockets.
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
	{
	    r = rb_read_internal(fptr->fd, fptr->rbuf.ptr, fptr->rbuf.capa);
	}
        if (r < 0) {
            if (rb_io_wait_readable(fptr->fd))
                goto retry;
	    {
		int e = errno;
		VALUE path = rb_sprintf("fd:%d ", fptr->fd);
		if (!NIL_P(fptr->pathv)) {
		    rb_str_append(path, fptr->pathv);
		}
		rb_syserr_fail_path(e, path);
	    }
        }
        fptr->rbuf.off = 0;
        fptr->rbuf.len = (int)r; /* r should be <= rbuf_capa */
        if (r == 0)
            return -1; /* EOF */
    }
    return 0;
}

/*
 *  call-seq:
 *     ios.eof     -> true or false
 *     ios.eof?    -> true or false
 *
 *  Returns true if <em>ios</em> is at end of file that means
 *  there are no more data to read.
 *  The stream must be opened for reading or an <code>IOError</code> will be
 *  raised.
 *
 *     f = File.new("testfile")
 *     dummy = f.readlines
 *     f.eof   #=> true
 *
 *  If <em>ios</em> is a stream such as pipe or socket, <code>IO#eof?</code>
 *  blocks until the other end sends some data or closes it.
 *
 *     r, w = IO.pipe
 *     Thread.new { sleep 1; w.close }
 *     r.eof?  #=> true after 1 second blocking
 *
 *     r, w = IO.pipe
 *     Thread.new { sleep 1; w.puts "a" }
 *     r.eof?  #=> false after 1 second blocking
 *
 *     r, w = IO.pipe
 *     r.eof?  # blocks forever
 *
 *  Note that <code>IO#eof?</code> reads data to the input byte buffer.
 *  So <code>IO#sysread</code> may not behave as you intend with
 *  <code>IO#eof?</code>, unless you call <code>IO#rewind</code>
 *  first (which is not available for some streams).
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
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
    if (!NEED_READCONV(fptr) && NEED_NEWLINE_DECORATOR_ON_READ(fptr)) {
	return eof(fptr->fd) ? Qtrue : Qfalse;
    }
#endif
    if (io_fillbuf(fptr) < 0) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     ios.sync    -> true or false
 *
 *  Returns the current ``sync mode'' of <em>ios</em>. When sync mode is
 *  true, all output is immediately flushed to the underlying operating
 *  system and is not buffered by Ruby internally. See also
 *  <code>IO#fsync</code>.
 *
 *     f = File.new("testfile")
 *     f.sync   #=> false
 */

static VALUE
rb_io_sync(VALUE io)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    return (fptr->mode & FMODE_SYNC) ? Qtrue : Qfalse;
}

#ifdef HAVE_FSYNC

/*
 *  call-seq:
 *     ios.sync = boolean   -> boolean
 *
 *  Sets the ``sync mode'' to <code>true</code> or <code>false</code>.
 *  When sync mode is true, all output is immediately flushed to the
 *  underlying operating system and is not buffered internally. Returns
 *  the new state. See also <code>IO#fsync</code>.
 *
 *     f = File.new("testfile")
 *     f.sync = true
 *
 *  <em>(produces no output)</em>
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
 *     ios.fsync   -> 0 or nil
 *
 *  Immediately writes all buffered data in <em>ios</em> to disk.
 *  Note that <code>fsync</code> differs from
 *  using <code>IO#sync=</code>. The latter ensures that data is flushed
 *  from Ruby's buffers, but does not guarantee that the underlying
 *  operating system actually writes it to disk.
 *
 *  <code>NotImplementedError</code> is raised
 *  if the underlying operating system does not support <em>fsync(2)</em>.
 */

static VALUE
rb_io_fsync(VALUE io)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    if (io_fflush(fptr) < 0)
        rb_sys_fail(0);
    if ((int)rb_thread_io_blocking_region(nogvl_fsync, fptr, fptr->fd) < 0)
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
 *     ios.fdatasync   -> 0 or nil
 *
 *  Immediately writes all buffered data in <em>ios</em> to disk.
 *
 *  If the underlying operating system does not support <em>fdatasync(2)</em>,
 *  <code>IO#fsync</code> is called instead (which might raise a
 *  <code>NotImplementedError</code>).
 */

static VALUE
rb_io_fdatasync(VALUE io)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    if (io_fflush(fptr) < 0)
        rb_sys_fail(0);

    if ((int)rb_thread_io_blocking_region(nogvl_fdatasync, fptr, fptr->fd) == 0)
	return INT2FIX(0);

    /* fall back */
    return rb_io_fsync(io);
}
#else
#define rb_io_fdatasync rb_io_fsync
#endif

/*
 *  call-seq:
 *     ios.fileno    -> fixnum
 *     ios.to_i      -> fixnum
 *
 *  Returns an integer representing the numeric file descriptor for
 *  <em>ios</em>.
 *
 *     $stdin.fileno    #=> 0
 *     $stdout.fileno   #=> 1
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


/*
 *  call-seq:
 *     ios.pid    -> fixnum
 *
 *  Returns the process ID of a child process associated with
 *  <em>ios</em>. This will be set by <code>IO.popen</code>.
 *
 *     pipe = IO.popen("-")
 *     if pipe
 *       $stderr.puts "In parent, child pid is #{pipe.pid}"
 *     else
 *       $stderr.puts "In child, pid is #{$$}"
 *     end
 *
 *  <em>produces:</em>
 *
 *     In child, pid is 26209
 *     In parent, child pid is 26209
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
 * call-seq:
 *   ios.inspect   -> string
 *
 * Return a string describing this IO object.
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
 *     ios.to_io  ->  ios
 *
 *  Returns <em>ios</em>.
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
	    c = rb_read_internal(fptr->fd, ptr+offset, n);
	    if (c == 0) break;
	    if (c < 0) {
                if (rb_io_wait_readable(fptr->fd))
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

static void io_setstrbuf(VALUE *str, long len);

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

ssize_t
rb_io_bufread(VALUE io, void *buf, size_t size)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    return (ssize_t)io_bufread(buf, (long)size, fptr);
}

static long
remain_size(rb_io_t *fptr)
{
    struct stat st;
    off_t siz = READ_DATA_PENDING_COUNT(fptr);
    off_t pos;

    if (fstat(fptr->fd, &st) == 0  && S_ISREG(st.st_mode)
#if defined(__HAIKU__)
	&& (st.st_dev > 3)
#endif
	)
    {
        if (io_fflush(fptr) < 0)
            rb_sys_fail(0);
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
    OBJ_TAINT(str);
    rb_enc_associate(str, io_read_encoding(fptr));
    return str;
}

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
            dname = rb_enc_name(fptr->encs.enc);
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
                if (io_fillbuf(fptr) == -1) {
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
	OBJ_TAINT(str);
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

static void
io_setstrbuf(VALUE *str, long len)
{
#ifdef _WIN32
    len = (len + 1) & ~1L;	/* round up for wide char */
#endif
    if (NIL_P(*str)) {
	*str = rb_str_new(0, 0);
    }
    else {
	VALUE s = StringValue(*str);
	long clen = RSTRING_LEN(s);
	if (clen >= len) {
	    rb_str_modify(s);
	    return;
	}
	len -= clen;
    }
    rb_str_modify_expand(*str, len);
}

static void
io_set_read_length(VALUE str, long n)
{
    if (RSTRING_LEN(str) != n) {
	rb_str_modify(str);
	rb_str_set_len(str, n);
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

    if (NEED_READCONV(fptr)) {
	int first = !NIL_P(str);
	SET_BINARY_MODE(fptr);
	io_setstrbuf(&str,0);
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
    io_setstrbuf(&str,siz);
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
	rb_str_modify_expand(str, BUFSIZ);
    }
    str = io_enc_str(str, fptr);
    ENC_CODERANGE_SET(str, cr);
    return str;
}

void
rb_io_set_nonblock(rb_io_t *fptr)
{
#ifdef _WIN32
    if (rb_w32_set_nonblock(fptr->fd) != 0) {
	rb_sys_fail_path(fptr->pathv);
    }
#else
    int oflags;
#ifdef F_GETFL
    oflags = fcntl(fptr->fd, F_GETFL);
    if (oflags == -1) {
        rb_sys_fail_path(fptr->pathv);
    }
#else
    oflags = 0;
#endif
    if ((oflags & O_NONBLOCK) == 0) {
        oflags |= O_NONBLOCK;
        if (fcntl(fptr->fd, F_SETFL, oflags) == -1) {
            rb_sys_fail_path(fptr->pathv);
        }
    }
#endif
}

struct read_internal_arg {
    int fd;
    char *str_ptr;
    long len;
};

static VALUE
read_internal_call(VALUE arg)
{
    struct read_internal_arg *p = (struct read_internal_arg *)arg;
    p->len = rb_read_internal(p->fd, p->str_ptr, p->len);
    return Qundef;
}

static int
no_exception_p(VALUE opts)
{
    VALUE except;
    ID id = id_exception;

    rb_get_kwargs(opts, &id, 0, 1, &except);
    return except == Qfalse;
}

static VALUE
io_getpartial(int argc, VALUE *argv, VALUE io, VALUE opts, int nonblock)
{
    rb_io_t *fptr;
    VALUE length, str;
    long n, len;
    struct read_internal_arg arg;

    rb_scan_args(argc, argv, "11", &length, &str);

    if ((len = NUM2LONG(length)) < 0) {
	rb_raise(rb_eArgError, "negative length %ld given", len);
    }

    io_setstrbuf(&str,len);
    OBJ_TAINT(str);

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);

    if (len == 0)
	return str;

    if (!nonblock)
        READ_CHECK(fptr);
    n = read_buffered_data(RSTRING_PTR(str), len, fptr);
    if (n <= 0) {
      again:
        if (nonblock) {
            rb_io_set_nonblock(fptr);
        }
	io_setstrbuf(&str, len);
	arg.fd = fptr->fd;
	arg.str_ptr = RSTRING_PTR(str);
	arg.len = len;
	rb_str_locktmp_ensure(str, read_internal_call, (VALUE)&arg);
	n = arg.len;
        if (n < 0) {
	    int e = errno;
            if (!nonblock && rb_io_wait_readable(fptr->fd))
                goto again;
	    if (nonblock && (e == EWOULDBLOCK || e == EAGAIN)) {
                if (no_exception_p(opts))
                    return sym_wait_readable;
                else
		    rb_readwrite_syserr_fail(RB_IO_WAIT_READABLE,
					     e, "read would block");
            }
            rb_syserr_fail_path(e, fptr->pathv);
        }
    }
    io_set_read_length(str, n);

    if (n == 0)
        return Qnil;
    else
        return str;
}

/*
 *  call-seq:
 *     ios.readpartial(maxlen)              -> string
 *     ios.readpartial(maxlen, outbuf)      -> outbuf
 *
 *  Reads at most <i>maxlen</i> bytes from the I/O stream.
 *  It blocks only if <em>ios</em> has no data immediately available.
 *  It doesn't block if some data available.
 *  If the optional <i>outbuf</i> argument is present,
 *  it must reference a String, which will receive the data.
 *  The <i>outbuf</i> will contain only the received data after the method call
 *  even if it is not empty at the beginning.
 *  It raises <code>EOFError</code> on end of file.
 *
 *  readpartial is designed for streams such as pipe, socket, tty, etc.
 *  It blocks only when no data immediately available.
 *  This means that it blocks only when following all conditions hold.
 *  * the byte buffer in the IO object is empty.
 *  * the content of the stream is empty.
 *  * the stream is not reached to EOF.
 *
 *  When readpartial blocks, it waits data or EOF on the stream.
 *  If some data is reached, readpartial returns with the data.
 *  If EOF is reached, readpartial raises EOFError.
 *
 *  When readpartial doesn't blocks, it returns or raises immediately.
 *  If the byte buffer is not empty, it returns the data in the buffer.
 *  Otherwise if the stream has some content,
 *  it returns the data in the stream.
 *  Otherwise if the stream is reached to EOF, it raises EOFError.
 *
 *     r, w = IO.pipe           #               buffer          pipe content
 *     w << "abc"               #               ""              "abc".
 *     r.readpartial(4096)      #=> "abc"       ""              ""
 *     r.readpartial(4096)      # blocks because buffer and pipe is empty.
 *
 *     r, w = IO.pipe           #               buffer          pipe content
 *     w << "abc"               #               ""              "abc"
 *     w.close                  #               ""              "abc" EOF
 *     r.readpartial(4096)      #=> "abc"       ""              EOF
 *     r.readpartial(4096)      # raises EOFError
 *
 *     r, w = IO.pipe           #               buffer          pipe content
 *     w << "abc\ndef\n"        #               ""              "abc\ndef\n"
 *     r.gets                   #=> "abc\n"     "def\n"         ""
 *     w << "ghi\n"             #               "def\n"         "ghi\n"
 *     r.readpartial(4096)      #=> "def\n"     ""              "ghi\n"
 *     r.readpartial(4096)      #=> "ghi\n"     ""              ""
 *
 *  Note that readpartial behaves similar to sysread.
 *  The differences are:
 *  * If the byte buffer is not empty, read from the byte buffer instead of "sysread for buffered IO (IOError)".
 *  * It doesn't cause Errno::EWOULDBLOCK and Errno::EINTR.  When readpartial meets EWOULDBLOCK and EINTR by read system call, readpartial retry the system call.
 *
 *  The latter means that readpartial is nonblocking-flag insensitive.
 *  It blocks on the situation IO#sysread causes Errno::EWOULDBLOCK as if the fd is blocking mode.
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
io_nonblock_eof(VALUE opts)
{
    if (!no_exception_p(opts)) {
        rb_eof_error();
    }
    return Qnil;
}

/* :nodoc: */
static VALUE
io_read_nonblock(VALUE io, VALUE length, VALUE str, VALUE ex)
{
    rb_io_t *fptr;
    long n, len;
    struct read_internal_arg arg;

    if ((len = NUM2LONG(length)) < 0) {
	rb_raise(rb_eArgError, "negative length %ld given", len);
    }

    io_setstrbuf(&str,len);
    OBJ_TAINT(str);
    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);

    if (len == 0)
	return str;

    n = read_buffered_data(RSTRING_PTR(str), len, fptr);
    if (n <= 0) {
	rb_io_set_nonblock(fptr);
	io_setstrbuf(&str, len);
	arg.fd = fptr->fd;
	arg.str_ptr = RSTRING_PTR(str);
	arg.len = len;
	rb_str_locktmp_ensure(str, read_internal_call, (VALUE)&arg);
	n = arg.len;
        if (n < 0) {
	    int e = errno;
	    if ((e == EWOULDBLOCK || e == EAGAIN)) {
                if (ex == Qfalse) return sym_wait_readable;
		rb_readwrite_syserr_fail(RB_IO_WAIT_READABLE,
					 e, "read would block");
            }
            rb_syserr_fail_path(e, fptr->pathv);
        }
    }
    io_set_read_length(str, n);

    if (n == 0) {
	if (ex == Qfalse) return Qnil;
	rb_eof_error();
    }

    return str;
}

/* :nodoc: */
static VALUE
io_write_nonblock(VALUE io, VALUE str, VALUE ex)
{
    rb_io_t *fptr;
    long n;

    if (!RB_TYPE_P(str, T_STRING))
	str = rb_obj_as_string(str);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    if (io_fflush(fptr) < 0)
        rb_sys_fail(0);

    rb_io_set_nonblock(fptr);
    n = write(fptr->fd, RSTRING_PTR(str), RSTRING_LEN(str));

    if (n == -1) {
	int e = errno;
	if (e == EWOULDBLOCK || e == EAGAIN) {
	    if (ex == Qfalse) {
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
 *     ios.read([length [, outbuf]])    -> string, outbuf, or nil
 *
 *  Reads <i>length</i> bytes from the I/O stream.
 *
 *  <i>length</i> must be a non-negative integer or <code>nil</code>.
 *
 *  If <i>length</i> is a positive integer,
 *  it tries to read <i>length</i> bytes without any conversion (binary mode).
 *  It returns <code>nil</code> or a string whose length is 1 to <i>length</i> bytes.
 *  <code>nil</code> means it met EOF at beginning.
 *  The 1 to <i>length</i>-1 bytes string means it met EOF after reading the result.
 *  The <i>length</i> bytes string means it doesn't meet EOF.
 *  The resulted string is always ASCII-8BIT encoding.
 *
 *  If <i>length</i> is omitted or is <code>nil</code>,
 *  it reads until EOF and the encoding conversion is applied.
 *  It returns a string even if EOF is met at beginning.
 *
 *  If <i>length</i> is zero, it returns <code>""</code>.
 *
 *  If the optional <i>outbuf</i> argument is present, it must reference
 *  a String, which will receive the data.
 *  The <i>outbuf</i> will contain only the received data after the method call
 *  even if it is not empty at the beginning.
 *
 *  At end of file, it returns <code>nil</code> or <code>""</code>
 *  depend on <i>length</i>.
 *  <code><i>ios</i>.read()</code> and
 *  <code><i>ios</i>.read(nil)</code> returns <code>""</code>.
 *  <code><i>ios</i>.read(<i>positive-integer</i>)</code> returns <code>nil</code>.
 *
 *     f = File.new("testfile")
 *     f.read(16)   #=> "This is line one"
 *
 *     # reads whole file
 *     open("file") {|f|
 *       data = f.read # This returns a string even if the file is empty.
 *       ...
 *     }
 *
 *     # iterate over fixed length records.
 *     open("fixed-record-file") {|f|
 *       while record = f.read(256)
 *         ...
 *       end
 *     }
 *
 *     # iterate over variable length records.
 *     # record is prefixed by 32-bit length.
 *     open("variable-record-file") {|f|
 *       while len = f.read(4)
 *         len = len.unpack("N")[0] # 32-bit length
 *         record = f.read(len) # This returns a string even if len is 0.
 *       end
 *     }
 *
 *  Note that this method behaves like fread() function in C.
 *  This means it retry to invoke read(2) system call to read data with the specified length (or until EOF).
 *  This behavior is preserved even if <i>ios</i> is non-blocking mode.
 *  (This method is non-blocking flag insensitive as other methods.)
 *  If you need the behavior like single read(2) system call,
 *  consider readpartial, read_nonblock and sysread.
 */

static VALUE
io_read(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    long n, len;
    VALUE length, str;
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
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

    io_setstrbuf(&str,len);

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);
    if (len == 0) {
	io_set_read_length(str, 0);
	return str;
    }

    READ_CHECK(fptr);
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
    previous_mode = set_binary_mode_with_seek_cur(fptr);
#endif
    n = io_fread(str, 0, len, fptr);
    io_set_read_length(str, n);
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
    if (previous_mode == O_TEXT) {
	setmode(fptr->fd, O_TEXT);
    }
#endif
    if (n == 0) return Qnil;
    OBJ_TAINT(str);

    return str;
}

static void
rscheck(const char *rsptr, long rslen, VALUE rs)
{
    if (!rs) return;
    if (RSTRING_PTR(rs) != rsptr && RSTRING_LEN(rs) != rslen)
	rb_raise(rb_eRuntimeError, "rs modified");
}

static int
appendline(rb_io_t *fptr, int delim, VALUE *strp, long *lp)
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
                e = memchr(p, delim, searchlen);
                if (e) {
		    int len = (int)(e-p+1);
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
	    e = memchr(p, delim, pending);
	    if (e) pending = e - p + 1;
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
rb_io_getline_fast(rb_io_t *fptr, rb_encoding *enc, VALUE io)
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

	    e = memchr(p, '\n', pending);
	    if (e) {
                pending = (int)(e - p + 1);
	    }
	    if (NIL_P(str)) {
		str = rb_str_new(p, pending);
		fptr->rbuf.off += pending;
		fptr->rbuf.len -= pending;
	    }
	    else {
		rb_str_resize(str, len + pending);
		read_buffered_data(RSTRING_PTR(str)+len, pending, fptr);
	    }
	    len += pending;
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
    if (io == ARGF.current_file) {
	ARGF.lineno++;
	ARGF.last_lineno = ARGF.lineno;
    }
    else {
	ARGF.last_lineno = fptr->lineno;
    }

    return str;
}

static void
prepare_getline_args(int argc, VALUE *argv, VALUE *rsp, long *limit, VALUE io)
{
    VALUE rs = rb_rs, lim = Qnil;
    rb_io_t *fptr;

    rb_check_arity(argc, 0, 2);
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
    if (!NIL_P(rs)) {
	rb_encoding *enc_rs, *enc_io;

	GetOpenFile(io, fptr);
	enc_rs = rb_enc_get(rs);
	enc_io = io_read_encoding(fptr);
	if (enc_io != enc_rs &&
	    (rb_enc_str_coderange(rs) != ENC_CODERANGE_7BIT ||
	     (RSTRING_LEN(rs) > 0 && !rb_enc_asciicompat(enc_io)))) {
            if (rs == rb_default_rs) {
                rs = rb_enc_str_new(0, 0, enc_io);
                rb_str_buf_cat_ascii(rs, "\n");
            }
            else {
                rb_raise(rb_eArgError, "encoding mismatch: %s IO with %s RS",
                         rb_enc_name(enc_io),
                         rb_enc_name(enc_rs));
            }
	}
    }
    *rsp = rs;
    *limit = NIL_P(lim) ? -1L : NUM2LONG(lim);
}

static VALUE
rb_io_getline_1(VALUE rs, long limit, VALUE io)
{
    VALUE str = Qnil;
    rb_io_t *fptr;
    int nolimit = 0;
    rb_encoding *enc;

    GetOpenFile(io, fptr);
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
	return rb_io_getline_fast(fptr, enc, io);
    }
    else {
	int c, newline = -1;
	const char *rsptr = 0;
	long rslen = 0;
	int rspara = 0;
        int extra_limit = 16;

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
		    rs = rb_str_encode(rs, rb_enc_from_encoding(enc), 0, Qnil);
		    OBJ_FREEZE(rs);
		    rsptr = RSTRING_PTR(rs);
		    rslen = RSTRING_LEN(rs);
		}
	    }
	    else {
		rsptr = RSTRING_PTR(rs);
	    }
	    newline = (unsigned char)rsptr[rslen - 1];
	}

	/* MS - Optimization */
	while ((c = appendline(fptr, newline, &str, &limit)) != EOF) {
            const char *s, *p, *pp, *e;

	    if (c == newline) {
		if (RSTRING_LEN(str) < rslen) continue;
		s = RSTRING_PTR(str);
                e = RSTRING_END(str);
		p = e - rslen;
		pp = rb_enc_left_char_head(s, p, e, enc);
		if (pp != p) continue;
		if (!rspara) rscheck(rsptr, rslen, rs);
		if (memcmp(p, rsptr, rslen) == 0) break;
	    }
	    if (limit == 0) {
		s = RSTRING_PTR(str);
		p = RSTRING_END(str);
		pp = rb_enc_left_char_head(s, p-1, p, enc);
                if (extra_limit &&
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
	if (io == ARGF.current_file) {
	    ARGF.lineno++;
	    ARGF.last_lineno = ARGF.lineno;
	}
	else {
	    ARGF.last_lineno = fptr->lineno;
	}
    }

    return str;
}

static VALUE
rb_io_getline(int argc, VALUE *argv, VALUE io)
{
    VALUE rs;
    long limit;

    prepare_getline_args(argc, argv, &rs, &limit, io);
    return rb_io_getline_1(rs, limit, io);
}

VALUE
rb_io_gets(VALUE io)
{
    return rb_io_getline_1(rb_default_rs, -1, io);
}

/*
 *  call-seq:
 *     ios.gets(sep=$/)     -> string or nil
 *     ios.gets(limit)      -> string or nil
 *     ios.gets(sep, limit) -> string or nil
 *
 *  Reads the next ``line'' from the I/O stream; lines are separated by
 *  <i>sep</i>. A separator of <code>nil</code> reads the entire
 *  contents, and a zero-length separator reads the input a paragraph at
 *  a time (two successive newlines in the input separate paragraphs).
 *  The stream must be opened for reading or an <code>IOError</code>
 *  will be raised. The line read in will be returned and also assigned
 *  to <code>$_</code>. Returns <code>nil</code> if called at end of
 *  file.  If the first argument is an integer, or optional second
 *  argument is given, the returning string would not be longer than the
 *  given value in bytes.
 *
 *     File.new("testfile").gets   #=> "This is line one\n"
 *     $_                          #=> "This is line one\n"
 *
 *     File.new("testfile").gets(4)#=> "This"
 *
 *  If IO contains multibyte characters byte then <code>gets(1)</code>
 *  returns character entirely:
 *
 *     # Russian characters take 2 bytes
 *     File.write("testfile", "\u{442 435 441 442}")
 *     File.open("testfile") {|f|f.gets(1)} #=> "\u0442"
 *     File.open("testfile") {|f|f.gets(2)} #=> "\u0442"
 *     File.open("testfile") {|f|f.gets(3)} #=> "\u0442\u0435"
 *     File.open("testfile") {|f|f.gets(4)} #=> "\u0442\u0435"
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
 *     ios.lineno    -> integer
 *
 *  Returns the current line number in <em>ios</em>.  The stream must be
 *  opened for reading. <code>lineno</code> counts the number of times
 *  #gets is called rather than the number of newlines encountered.  The two
 *  values will differ if #gets is called with a separator other than newline.
 *
 *  Methods that use <code>$/</code> like #each, #lines and #readline will
 *  also increment <code>lineno</code>.
 *
 *  See also the <code>$.</code> variable.
 *
 *     f = File.new("testfile")
 *     f.lineno   #=> 0
 *     f.gets     #=> "This is line one\n"
 *     f.lineno   #=> 1
 *     f.gets     #=> "This is line two\n"
 *     f.lineno   #=> 2
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
 *     ios.lineno = integer    -> integer
 *
 *  Manually sets the current line number to the given value.
 *  <code>$.</code> is updated only on the next read.
 *
 *     f = File.new("testfile")
 *     f.gets                     #=> "This is line one\n"
 *     $.                         #=> 1
 *     f.lineno = 1000
 *     f.lineno                   #=> 1000
 *     $.                         #=> 1         # lineno of last read
 *     f.gets                     #=> "This is line two\n"
 *     $.                         #=> 1001      # lineno of last read
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

/*
 *  call-seq:
 *     ios.readline(sep=$/)     -> string
 *     ios.readline(limit)      -> string
 *     ios.readline(sep, limit) -> string
 *
 *  Reads a line as with <code>IO#gets</code>, but raises an
 *  <code>EOFError</code> on end of file.
 */

static VALUE
rb_io_readline(int argc, VALUE *argv, VALUE io)
{
    VALUE line = rb_io_gets_m(argc, argv, io);

    if (NIL_P(line)) {
	rb_eof_error();
    }
    return line;
}

/*
 *  call-seq:
 *     ios.readlines(sep=$/)     -> array
 *     ios.readlines(limit)      -> array
 *     ios.readlines(sep, limit) -> array
 *
 *  Reads all of the lines in <em>ios</em>, and returns them in
 *  <i>anArray</i>. Lines are separated by the optional <i>sep</i>. If
 *  <i>sep</i> is <code>nil</code>, the rest of the stream is returned
 *  as a single record.  If the first argument is an integer, or
 *  optional second argument is given, the returning string would not be
 *  longer than the given value in bytes. The stream must be opened for
 *  reading or an <code>IOError</code> will be raised.
 *
 *     f = File.new("testfile")
 *     f.readlines[0]   #=> "This is line one\n"
 */

static VALUE
rb_io_readlines(int argc, VALUE *argv, VALUE io)
{
    VALUE line, ary, rs;
    long limit;

    prepare_getline_args(argc, argv, &rs, &limit, io);
    if (limit == 0)
	rb_raise(rb_eArgError, "invalid limit: 0 for readlines");
    ary = rb_ary_new();
    while (!NIL_P(line = rb_io_getline_1(rs, limit, io))) {
	rb_ary_push(ary, line);
    }
    return ary;
}

/*
 *  call-seq:
 *     ios.each(sep=$/) {|line| block }         -> ios
 *     ios.each(limit) {|line| block }          -> ios
 *     ios.each(sep,limit) {|line| block }      -> ios
 *     ios.each(...)                            -> an_enumerator
 *
 *     ios.each_line(sep=$/) {|line| block }    -> ios
 *     ios.each_line(limit) {|line| block }     -> ios
 *     ios.each_line(sep,limit) {|line| block } -> ios
 *     ios.each_line(...)                       -> an_enumerator
 *
 *  Executes the block for every line in <em>ios</em>, where lines are
 *  separated by <i>sep</i>. <em>ios</em> must be opened for
 *  reading or an <code>IOError</code> will be raised.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     f = File.new("testfile")
 *     f.each {|line| puts "#{f.lineno}: #{line}" }
 *
 *  <em>produces:</em>
 *
 *     1: This is line one
 *     2: This is line two
 *     3: This is line three
 *     4: And so on...
 */

static VALUE
rb_io_each_line(int argc, VALUE *argv, VALUE io)
{
    VALUE str, rs;
    long limit;

    RETURN_ENUMERATOR(io, argc, argv);
    prepare_getline_args(argc, argv, &rs, &limit, io);
    if (limit == 0)
	rb_raise(rb_eArgError, "invalid limit: 0 for each_line");
    while (!NIL_P(str = rb_io_getline_1(rs, limit, io))) {
	rb_yield(str);
    }
    return io;
}

/*
 *  This is a deprecated alias for <code>each_line</code>.
 */

static VALUE
rb_io_lines(int argc, VALUE *argv, VALUE io)
{
    rb_warn("IO#lines is deprecated; use #each_line instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(io, ID2SYM(rb_intern("each_line")), argc, argv);
    return rb_io_each_line(argc, argv, io);
}

/*
 *  call-seq:
 *     ios.each_byte {|byte| block }  -> ios
 *     ios.each_byte                  -> an_enumerator
 *
 *  Calls the given block once for each byte (0..255) in <em>ios</em>,
 *  passing the byte as an argument. The stream must be opened for
 *  reading or an <code>IOError</code> will be raised.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     f = File.new("testfile")
 *     checksum = 0
 *     f.each_byte {|x| checksum ^= x }   #=> #<File:testfile>
 *     checksum                           #=> 12
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
	    errno = 0;
	}
	rb_io_check_byte_readable(fptr);
	READ_CHECK(fptr);
    } while (io_fillbuf(fptr) >= 0);
    return io;
}

/*
 *  This is a deprecated alias for <code>each_byte</code>.
 */

static VALUE
rb_io_bytes(VALUE io)
{
    rb_warn("IO#bytes is deprecated; use #each_byte instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(io, ID2SYM(rb_intern("each_byte")), 0, 0);
    return rb_io_each_byte(io);
}

static VALUE
io_getc(rb_io_t *fptr, rb_encoding *enc)
{
    int r, n, cr = 0;
    VALUE str;

    if (NEED_READCONV(fptr)) {
        VALUE str = Qnil;
	rb_encoding *read_enc = io_read_encoding(fptr);

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
 *     ios.each_char {|c| block }  -> ios
 *     ios.each_char               -> an_enumerator
 *
 *  Calls the given block once for each character in <em>ios</em>,
 *  passing the character as an argument. The stream must be opened for
 *  reading or an <code>IOError</code> will be raised.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     f = File.new("testfile")
 *     f.each_char {|c| print c, ' ' }   #=> #<File:testfile>
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
 *  This is a deprecated alias for <code>each_char</code>.
 */

static VALUE
rb_io_chars(VALUE io)
{
    rb_warn("IO#chars is deprecated; use #each_char instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(io, ID2SYM(rb_intern("each_char")), 0, 0);
    return rb_io_each_char(io);
}


/*
 *  call-seq:
 *     ios.each_codepoint {|c| block }  -> ios
 *     ios.codepoints     {|c| block }  -> ios
 *     ios.each_codepoint               -> an_enumerator
 *     ios.codepoints                   -> an_enumerator
 *
 *  Passes the <code>Integer</code> ordinal of each character in <i>ios</i>,
 *  passing the codepoint as an argument. The stream must be opened for
 *  reading or an <code>IOError</code> will be raised.
 *
 *  If no block is given, an enumerator is returned instead.
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
	  invalid:
	    rb_raise(rb_eArgError, "invalid byte sequence in %s", rb_enc_name(enc));
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
    }
    return io;
}

/*
 *  This is a deprecated alias for <code>each_codepoint</code>.
 */

static VALUE
rb_io_codepoints(VALUE io)
{
    rb_warn("IO#codepoints is deprecated; use #each_codepoint instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(io, ID2SYM(rb_intern("each_codepoint")), 0, 0);
    return rb_io_each_codepoint(io);
}


/*
 *  call-seq:
 *     ios.getc   -> string or nil
 *
 *  Reads a one-character string from <em>ios</em>. Returns
 *  <code>nil</code> if called at end of file.
 *
 *     f = File.new("testfile")
 *     f.getc   #=> "h"
 *     f.getc   #=> "e"
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
 *     ios.readchar   -> string
 *
 *  Reads a one-character string from <em>ios</em>. Raises an
 *  <code>EOFError</code> on end of file.
 *
 *     f = File.new("testfile")
 *     f.readchar   #=> "h"
 *     f.readchar   #=> "e"
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
 *     ios.getbyte   -> fixnum or nil
 *
 *  Gets the next 8-bit byte (0..255) from <em>ios</em>. Returns
 *  <code>nil</code> if called at end of file.
 *
 *     f = File.new("testfile")
 *     f.getbyte   #=> 84
 *     f.getbyte   #=> 104
 */

VALUE
rb_io_getbyte(VALUE io)
{
    rb_io_t *fptr;
    int c;

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);
    READ_CHECK(fptr);
    if (fptr->fd == 0 && (fptr->mode & FMODE_TTY) && RB_TYPE_P(rb_stdout, T_FILE)) {
        rb_io_t *ofp;
        GetOpenFile(rb_stdout, ofp);
        if (ofp->mode & FMODE_TTY) {
            rb_io_flush(rb_stdout);
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
 *     ios.readbyte   -> fixnum
 *
 *  Reads a byte as with <code>IO#getbyte</code>, but raises an
 *  <code>EOFError</code> on end of file.
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
 *     ios.ungetbyte(string)   -> nil
 *     ios.ungetbyte(integer)   -> nil
 *
 *  Pushes back bytes (passed as a parameter) onto <em>ios</em>,
 *  such that a subsequent buffered read will return it. Only one byte
 *  may be pushed back before a subsequent read operation (that is,
 *  you will be able to read only the last of several bytes that have been pushed
 *  back). Has no effect with unbuffered reads (such as <code>IO#sysread</code>).
 *
 *     f = File.new("testfile")   #=> #<File:testfile>
 *     b = f.getbyte              #=> 0x38
 *     f.ungetbyte(b)             #=> nil
 *     f.getbyte                  #=> 0x38
 */

VALUE
rb_io_ungetbyte(VALUE io, VALUE b)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);
    if (NIL_P(b)) return Qnil;
    if (FIXNUM_P(b)) {
	char cc = FIX2INT(b);
	b = rb_str_new(&cc, 1);
    }
    else {
	SafeStringValue(b);
    }
    io_ungetbyte(b, fptr);
    return Qnil;
}

/*
 *  call-seq:
 *     ios.ungetc(string)   -> nil
 *
 *  Pushes back one character (passed as a parameter) onto <em>ios</em>,
 *  such that a subsequent buffered character read will return it. Only one character
 *  may be pushed back before a subsequent read operation (that is,
 *  you will be able to read only the last of several characters that have been pushed
 *  back). Has no effect with unbuffered reads (such as <code>IO#sysread</code>).
 *
 *     f = File.new("testfile")   #=> #<File:testfile>
 *     c = f.getc                 #=> "8"
 *     f.ungetc(c)                #=> nil
 *     f.getc                     #=> "8"
 */

VALUE
rb_io_ungetc(VALUE io, VALUE c)
{
    rb_io_t *fptr;
    long len;

    GetOpenFile(io, fptr);
    rb_io_check_char_readable(fptr);
    if (NIL_P(c)) return Qnil;
    if (FIXNUM_P(c)) {
	c = rb_enc_uint_chr(FIX2UINT(c), io_read_encoding(fptr));
    }
    else if (RB_TYPE_P(c, T_BIGNUM)) {
	c = rb_enc_uint_chr(NUM2UINT(c), io_read_encoding(fptr));
    }
    else {
	SafeStringValue(c);
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
 *     ios.isatty   -> true or false
 *     ios.tty?     -> true or false
 *
 *  Returns <code>true</code> if <em>ios</em> is associated with a
 *  terminal device (tty), <code>false</code> otherwise.
 *
 *     File.new("testfile").isatty   #=> false
 *     File.new("/dev/tty").isatty   #=> true
 */

static VALUE
rb_io_isatty(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (isatty(fptr->fd) == 0)
	return Qfalse;
    return Qtrue;
}

#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(F_SETFD) && defined(FD_CLOEXEC)
/*
 *  call-seq:
 *     ios.close_on_exec?   -> true or false
 *
 *  Returns <code>true</code> if <em>ios</em> will be closed on exec.
 *
 *     f = open("/dev/null")
 *     f.close_on_exec?                 #=> false
 *     f.close_on_exec = true
 *     f.close_on_exec?                 #=> true
 *     f.close_on_exec = false
 *     f.close_on_exec?                 #=> false
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
 *     ios.close_on_exec = bool    -> true or false
 *
 *  Sets a close-on-exec flag.
 *
 *     f = open("/dev/null")
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
                if (ret == -1) rb_sys_fail_path(fptr->pathv);
            }
        }

    }

    GetOpenFile(io, fptr);
    if (fptr && 0 <= (fd = fptr->fd)) {
        if ((ret = fcntl(fd, F_GETFD)) == -1) rb_sys_fail_path(fptr->pathv);
        if ((ret & FD_CLOEXEC) != flag) {
            ret = (ret & ~FD_CLOEXEC) | flag;
            ret = fcntl(fd, F_SETFD, ret);
            if (ret == -1) rb_sys_fail_path(fptr->pathv);
        }
    }
    return Qnil;
}
#else
#define rb_io_set_close_on_exec rb_f_notimplement
#endif

#define FMODE_PREP (1<<16)
#define IS_PREP_STDIO(f) ((f)->mode & FMODE_PREP)
#define PREP_STDIO_NAME(f) (RSTRING_PTR((f)->pathv))

static VALUE
finish_writeconv(rb_io_t *fptr, int noalloc)
{
    unsigned char *ds, *dp, *de;
    rb_econv_result_t res;

    if (!fptr->wbuf.ptr) {
        unsigned char buf[1024];
        long r;

        res = econv_destination_buffer_full;
        while (res == econv_destination_buffer_full) {
            ds = dp = buf;
            de = buf + sizeof(buf);
            res = rb_econv_convert(fptr->writeconv, NULL, NULL, &dp, de, 0);
            while (dp-ds) {
              retry:
		if (fptr->write_lock && rb_mutex_owned_p(fptr->write_lock))
		    r = rb_write_internal2(fptr->fd, ds, dp-ds);
		else
		    r = rb_write_internal(fptr->fd, ds, dp-ds);
                if (r == dp-ds)
                    break;
                if (0 <= r) {
                    ds += r;
                }
                if (rb_io_wait_writable(fptr->fd)) {
                    if (fptr->fd < 0)
                        return noalloc ? Qtrue : rb_exc_new3(rb_eIOError, rb_str_new_cstr(closed_stream));
                    goto retry;
                }
                return noalloc ? Qtrue : INT2NUM(errno);
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
            if (io_fflush(fptr) < 0)
                return noalloc ? Qtrue : INT2NUM(errno);
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
    return (int)(intptr_t)rb_thread_call_without_gvl(nogvl_close, &fd, RUBY_UBF_IO, 0);
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

    return (int)(intptr_t)rb_thread_call_without_gvl(nogvl_fclose, file, RUBY_UBF_IO, 0);
}

static void free_io_buffer(rb_io_buffer_t *buf);
static void clear_codeconv(rb_io_t *fptr);

static void
fptr_finalize(rb_io_t *fptr, int noraise)
{
    VALUE err = Qnil;
    int fd = fptr->fd;
    FILE *stdio_file = fptr->stdio_file;
    int mode = fptr->mode;

    if (fptr->writeconv) {
	if (fptr->write_lock && !noraise) {
            struct finish_writeconv_arg arg;
            arg.fptr = fptr;
            arg.noalloc = noraise;
            err = rb_mutex_synchronize(fptr->write_lock, finish_writeconv_sync, (VALUE)&arg);
	}
	else {
	    err = finish_writeconv(fptr, noraise);
	}
    }
    if (fptr->wbuf.len) {
	if (noraise) {
	    if ((int)io_flush_buffer_sync(fptr) < 0 && NIL_P(err))
		err = Qtrue;
	}
	else {
	    if (io_fflush(fptr) < 0 && NIL_P(err))
		err = INT2NUM(errno);
	}
    }

    fptr->fd = -1;
    fptr->stdio_file = 0;
    fptr->mode &= ~(FMODE_READABLE|FMODE_WRITABLE);

    if (IS_PREP_STDIO(fptr) || fd <= 2) {
	/* need to keep FILE objects of stdin, stdout and stderr */
    }
    else if (stdio_file) {
	/* stdio_file is deallocated anyway
         * even if fclose failed.  */
	if ((maygvl_fclose(stdio_file, noraise) < 0) && NIL_P(err))
	    err = noraise ? Qtrue : INT2NUM(errno);
    }
    else if (0 <= fd) {
	/* fptr->fd may be closed even if close fails.
         * POSIX doesn't specify it.
         * We assumes it is closed.  */

	/**/
	int keepgvl = !(mode & FMODE_WRITABLE);
	keepgvl |= noraise;
	if ((maygvl_close(fd, keepgvl) < 0) && NIL_P(err))
	    err = noraise ? Qtrue : INT2NUM(errno);
    }

    if (!NIL_P(err) && !noraise) {
        switch (TYPE(err)) {
          case T_FIXNUM:
          case T_BIGNUM:
	    rb_syserr_fail_path(NUM2INT(err), fptr->pathv);

          default:
            rb_exc_raise(err);
        }
    }
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

int
rb_io_fptr_finalize(rb_io_t *fptr)
{
    if (!fptr) return 0;
    fptr->pathv = Qnil;
    if (0 <= fptr->fd)
	rb_io_fptr_cleanup(fptr, TRUE);
    fptr->write_lock = 0;
    free_io_buffer(&fptr->rbuf);
    free_io_buffer(&fptr->wbuf);
    clear_codeconv(fptr);
    free(fptr);
    return 1;
}

RUBY_FUNC_EXPORTED size_t
rb_io_memsize(const rb_io_t *fptr)
{
    size_t size = sizeof(rb_io_t);
    size += fptr->rbuf.capa;
    size += fptr->wbuf.capa;
    size += fptr->cbuf.capa;
    if (fptr->readconv) size += rb_econv_memsize(fptr->readconv);
    if (fptr->writeconv) size += rb_econv_memsize(fptr->writeconv);
    return size;
}

static rb_io_t *
io_close_fptr(VALUE io)
{
    rb_io_t *fptr;
    int fd;
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

    fd = fptr->fd;
    rb_thread_fd_close(fd);
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
 *     ios.close   -> nil
 *
 *  Closes <em>ios</em> and flushes any pending writes to the operating
 *  system. The stream is unavailable for any further data operations;
 *  an <code>IOError</code> is raised if such an attempt is made. I/O
 *  streams are automatically closed when they are claimed by the
 *  garbage collector.
 *
 *  If <em>ios</em> is opened by <code>IO.popen</code>,
 *  <code>close</code> sets <code>$?</code>.
 *
 *  Calling this method on closed IO object is just ignored since Ruby 2.3.
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
    VALUE mesg = rb_attr_get(exc, rb_intern("mesg"));
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
    if (closed != Qundef && RTEST(closed)) return io;
    rb_rescue2(io_call_close, io, ignore_closed_stream, io,
	       rb_eIOError, (VALUE)0);
    return io;
}

/*
 *  call-seq:
 *     ios.closed?    -> true or false
 *
 *  Returns <code>true</code> if <em>ios</em> is completely closed (for
 *  duplex streams, both reader and writer), <code>false</code>
 *  otherwise.
 *
 *     f = File.new("testfile")
 *     f.close         #=> nil
 *     f.closed?       #=> true
 *     f = IO.popen("/bin/sh","r+")
 *     f.close_write   #=> nil
 *     f.closed?       #=> false
 *     f.close_read    #=> nil
 *     f.closed?       #=> true
 */


static VALUE
rb_io_closed(VALUE io)
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
    return 0 <= fptr->fd ? Qfalse : Qtrue;
}

/*
 *  call-seq:
 *     ios.close_read    -> nil
 *
 *  Closes the read end of a duplex I/O stream (i.e., one that contains
 *  both a read and a write stream, such as a pipe). Will raise an
 *  <code>IOError</code> if the stream is not duplexed.
 *
 *     f = IO.popen("/bin/sh","r+")
 *     f.close_read
 *     f.readlines
 *
 *  <em>produces:</em>
 *
 *     prog.rb:3:in `readlines': not opened for reading (IOError)
 *     	from prog.rb:3
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
 *     ios.close_write   -> nil
 *
 *  Closes the write end of a duplex I/O stream (i.e., one that contains
 *  both a read and a write stream, such as a pipe). Will raise an
 *  <code>IOError</code> if the stream is not duplexed.
 *
 *     f = IO.popen("/bin/sh","r+")
 *     f.close_write
 *     f.print "nowhere"
 *
 *  <em>produces:</em>
 *
 *     prog.rb:3:in `write': not opened for writing (IOError)
 *     	from prog.rb:3:in `print'
 *     	from prog.rb:3
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
 *     ios.sysseek(offset, whence=IO::SEEK_SET)   -> integer
 *
 *  Seeks to a given <i>offset</i> in the stream according to the value
 *  of <i>whence</i> (see <code>IO#seek</code> for values of
 *  <i>whence</i>). Returns the new offset into the file.
 *
 *     f = File.new("testfile")
 *     f.sysseek(-13, IO::SEEK_END)   #=> 53
 *     f.sysread(10)                  #=> "And so on."
 */

static VALUE
rb_io_sysseek(int argc, VALUE *argv, VALUE io)
{
    VALUE offset, ptrname;
    int whence = SEEK_SET;
    rb_io_t *fptr;
    off_t pos;

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
    if (pos == -1 && errno) rb_sys_fail_path(fptr->pathv);

    return OFFT2NUM(pos);
}

/*
 *  call-seq:
 *     ios.syswrite(string)   -> integer
 *
 *  Writes the given string to <em>ios</em> using a low-level write.
 *  Returns the number of bytes written. Do not mix with other methods
 *  that write to <em>ios</em> or you may get unpredictable results.
 *  Raises <code>SystemCallError</code> on error.
 *
 *     f = File.new("out", "w")
 *     f.syswrite("ABCDEF")   #=> 6
 */

static VALUE
rb_io_syswrite(VALUE io, VALUE str)
{
    rb_io_t *fptr;
    long n;

    if (!RB_TYPE_P(str, T_STRING))
	str = rb_obj_as_string(str);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    str = rb_str_new_frozen(str);

    if (fptr->wbuf.len) {
	rb_warn("syswrite for buffered IO");
    }

    n = rb_write_internal(fptr->fd, RSTRING_PTR(str), RSTRING_LEN(str));
    RB_GC_GUARD(str);

    if (n == -1) rb_sys_fail_path(fptr->pathv);

    return LONG2FIX(n);
}

/*
 *  call-seq:
 *     ios.sysread(maxlen[, outbuf])    -> string
 *
 *  Reads <i>maxlen</i> bytes from <em>ios</em> using a low-level
 *  read and returns them as a string.  Do not mix with other methods
 *  that read from <em>ios</em> or you may get unpredictable results.
 *  If the optional <i>outbuf</i> argument is present, it must reference
 *  a String, which will receive the data.
 *  The <i>outbuf</i> will contain only the received data after the method call
 *  even if it is not empty at the beginning.
 *  Raises <code>SystemCallError</code> on error and
 *  <code>EOFError</code> at end of file.
 *
 *     f = File.new("testfile")
 *     f.sysread(16)   #=> "This is line one"
 */

static VALUE
rb_io_sysread(int argc, VALUE *argv, VALUE io)
{
    VALUE len, str;
    rb_io_t *fptr;
    long n, ilen;
    struct read_internal_arg arg;

    rb_scan_args(argc, argv, "11", &len, &str);
    ilen = NUM2LONG(len);

    io_setstrbuf(&str,ilen);
    if (ilen == 0) return str;

    GetOpenFile(io, fptr);
    rb_io_check_byte_readable(fptr);

    if (READ_DATA_BUFFERED(fptr)) {
	rb_raise(rb_eIOError, "sysread for buffered IO");
    }

    /*
     * FIXME: removing rb_thread_wait_fd() here changes sysread semantics
     * on non-blocking IOs.  However, it's still currently possible
     * for sysread to raise Errno::EAGAIN if another thread read()s
     * the IO after we return from rb_thread_wait_fd() but before
     * we call read()
     */
    rb_thread_wait_fd(fptr->fd);

    rb_io_check_closed(fptr);

    io_setstrbuf(&str, ilen);
    rb_str_locktmp(str);
    arg.fd = fptr->fd;
    arg.str_ptr = RSTRING_PTR(str);
    arg.len = ilen;
    rb_ensure(read_internal_call, (VALUE)&arg, rb_str_unlocktmp, str);
    n = arg.len;

    if (n == -1) {
	rb_sys_fail_path(fptr->pathv);
    }
    io_set_read_length(str, n);
    if (n == 0 && ilen > 0) {
	rb_eof_error();
    }
    OBJ_TAINT(str);

    return str;
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
 *     ios.binmode    -> ios
 *
 *  Puts <em>ios</em> into binary mode.
 *  Once a stream is in binary mode, it cannot be reset to nonbinary mode.
 *
 *  - newline conversion disabled
 *  - encoding conversion disabled
 *  - content is treated as ASCII-8BIT
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
 *     ios.binmode?    -> true or false
 *
 *  Returns <code>true</code> if <em>ios</em> is binmode.
 */
static VALUE
rb_io_binmode_p(VALUE io)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    return fptr->mode & FMODE_BINMODE ? Qtrue : Qfalse;
}

static const char*
rb_io_fmode_modestr(int fmode)
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
	return MODE_BTMODE("w", "wb", "wt");
      case FMODE_READWRITE:
	if (fmode & FMODE_CREATE) {
	    return MODE_BTMODE("w+", "wb+", "wt+");
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

int
rb_io_modestr_fmode(const char *modestr)
{
    int fmode = 0;
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
      error:
	rb_raise(rb_eArgError, "invalid access mode %s", modestr);
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
}

int
rb_io_oflags_fmode(int oflags)
{
    int fmode = 0;

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
#ifdef O_BINARY
    if (oflags & O_BINARY) {
	fmode |= FMODE_BINMODE;
    }
#endif

    return fmode;
}

static int
rb_io_fmode_oflags(int fmode)
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
    int accmode = oflags & (O_RDONLY|O_WRONLY|O_RDWR);
    if (oflags & O_APPEND) {
	if (accmode == O_WRONLY) {
	    return MODE_BINARY("a", "ab");
	}
	if (accmode == O_RDWR) {
	    return MODE_BINARY("a+", "ab+");
	}
    }
    switch (oflags & (O_RDONLY|O_WRONLY|O_RDWR)) {
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
rb_io_ext_int_to_encs(rb_encoding *ext, rb_encoding *intern, rb_encoding **enc, rb_encoding **enc2, int fmode)
{
    int default_ext = 0;

    if (ext == NULL) {
	ext = rb_default_external_encoding();
	default_ext = 1;
    }
    if (ext == rb_ascii8bit_encoding()) {
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
	       rb_encoding **enc_p, rb_encoding **enc2_p, int *fmode_p)
{
    const char *p;
    char encname[ENCODING_MAXNAMELEN+1];
    int idx, idx2;
    int fmode = fmode_p ? *fmode_p : 0;
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
rb_io_extract_encoding_option(VALUE opt, rb_encoding **enc_p, rb_encoding **enc2_p, int *fmode_p)
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
	if (v != Qundef) intenc = v;
    }
    if ((extenc != Qundef || intenc != Qundef) && !NIL_P(encoding)) {
	if (!NIL_P(ruby_verbose)) {
	    int idx = rb_to_encoding_index(encoding);
	    if (idx >= 0) encoding = rb_enc_from_encoding(rb_enc_from_index(idx));
	    rb_warn("Ignoring encoding parameter '%"PRIsVALUE"': %s_encoding is used",
		    encoding, extenc == Qundef ? "internal" : "external");
	}
	encoding = Qnil;
    }
    if (extenc != Qundef && !NIL_P(extenc)) {
	extencoding = rb_to_encoding(extenc);
    }
    if (intenc != Qundef) {
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
    else if (extenc != Qundef || intenc != Qundef) {
        extracted = 1;
	rb_io_ext_int_to_encs(extencoding, intencoding, enc_p, enc2_p, 0);
    }
    return extracted;
}

typedef struct rb_io_enc_t convconfig_t;

static void
validate_enc_binmode(int *fmode_p, int ecflags, rb_encoding *enc, rb_encoding *enc2)
{
    int fmode = *fmode_p;

    if ((fmode & FMODE_READABLE) &&
        !enc2 &&
        !(fmode & FMODE_BINMODE) &&
        !rb_enc_asciicompat(enc ? enc : rb_default_external_encoding()))
        rb_raise(rb_eArgError, "ASCII incompatible encoding needs binmode");

    if (!(fmode & FMODE_BINMODE) &&
	(DEFAULT_TEXTMODE || (ecflags & ECONV_NEWLINE_DECORATOR_MASK))) {
	fmode |= DEFAULT_TEXTMODE;
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
extract_binmode(VALUE opthash, int *fmode)
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

static void
rb_io_extract_modeenc(VALUE *vmode_p, VALUE *vperm_p, VALUE opthash,
        int *oflags_p, int *fmode_p, convconfig_t *convconfig_p)
{
    VALUE vmode;
    int oflags, fmode;
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

        SafeStringValue(vmode);
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
    fd = (int)(VALUE)rb_thread_call_without_gvl(sysopen_func, data, RUBY_UBF_IO, 0);
    if (0 <= fd)
        rb_update_max_fd(fd);
    return fd;
}

static int
rb_sysopen(VALUE fname, int oflags, mode_t perm)
{
    int fd;
    struct sysopen_struct data;

    data.fname = rb_str_encode_ospath(fname);
    StringValueCStr(data.fname);
    data.oflags = oflags;
    data.perm = perm;

    fd = rb_sysopen_internal(&data);
    if (fd < 0) {
	if (rb_gc_for_fd(errno)) {
	    fd = rb_sysopen_internal(&data);
	}
	if (fd < 0) {
	    rb_sys_fail_path(fname);
	}
    }
    return fd;
}

FILE *
rb_fdopen(int fd, const char *modestr)
{
    FILE *file;

#if defined(__sun)
    errno = 0;
#endif
    file = fdopen(fd, modestr);
    if (!file) {
#if defined(__sun)
	if (errno == 0) {
	    rb_gc();
	    errno = 0;
	    file = fdopen(fd, modestr);
	}
	else
#endif
	if (rb_gc_for_fd(errno)) {
	    file = fdopen(fd, modestr);
	}
	if (!file) {
	    int e = errno;
#ifdef _WIN32
	    if (e == 0) e = EINVAL;
#elif defined(__sun)
	    if (e == 0) e = EMFILE;
#endif
	    rb_syserr_fail(e, 0);
	}
    }

    /* xxx: should be _IONBF?  A buffer in FILE may have trouble. */
#ifdef USE_SETVBUF
    if (setvbuf(file, NULL, _IOFBF, 0) != 0)
	rb_warn("setvbuf() can't be honoured (fd=%d)", fd);
#endif
    return file;
}

static void
io_check_tty(rb_io_t *fptr)
{
    if (isatty(fptr->fd))
        fptr->mode |= FMODE_TTY|FMODE_DUPLEX;
}

static VALUE rb_io_internal_encoding(VALUE);
static void io_encoding_set(rb_io_t *, VALUE, VALUE, VALUE);

static int
io_strip_bom(VALUE io)
{
    VALUE b1, b2, b3, b4;

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
		rb_io_ungetbyte(io, b3);
	    }
	    else {
		rb_io_ungetbyte(io, b3);
		return ENCINDEX_UTF_16LE;
	    }
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

static void
io_set_encoding_by_bom(VALUE io)
{
    int idx = io_strip_bom(io);
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (idx) {
	io_encoding_set(fptr, rb_enc_from_encoding(rb_enc_from_index(idx)),
		rb_io_internal_encoding(io), Qnil);
    }
    else {
	fptr->encs.enc2 = NULL;
    }
}

static VALUE
rb_file_open_generic(VALUE io, VALUE filename, int oflags, int fmode, convconfig_t *convconfig, mode_t perm)
{
    rb_io_t *fptr;
    convconfig_t cc;
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
    fptr->pathv = rb_str_new_frozen(filename);
    fptr->fd = rb_sysopen(fptr->pathv, oflags, perm);
    io_check_tty(fptr);
    if (fmode & FMODE_SETENC_BY_BOM) io_set_encoding_by_bom(io);

    return io;
}

static VALUE
rb_file_open_internal(VALUE io, VALUE filename, const char *modestr)
{
    int fmode = rb_io_modestr_fmode(modestr);
    const char *p = strchr(modestr, ':');
    convconfig_t convconfig;

    if (p) {
        parse_mode_enc(p+1, rb_usascii_encoding(),
		       &convconfig.enc, &convconfig.enc2, &fmode);
    }
    else {
	rb_encoding *e;
	/* Set to default encodings */

	e = (fmode & FMODE_BINMODE) ? rb_ascii8bit_encoding() : NULL;
	rb_io_ext_int_to_encs(e, NULL, &convconfig.enc, &convconfig.enc2, fmode);
        convconfig.ecflags = 0;
        convconfig.ecopts = Qnil;
    }

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
    struct pipe_list *list = pipe_list;
    struct pipe_list *tmp;

    if (list->fptr == fptr) {
	pipe_list = list->next;
	free(list);
	return;
    }

    while (list->next) {
	if (list->next->fptr == fptr) {
	    tmp = list->next;
	    list->next = list->next->next;
	    free(tmp);
	    return;
	}
	list = list->next;
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
    ret = rb_cloexec_pipe(pipes);
    if (ret == -1) {
        if (rb_gc_for_fd(errno)) {
            ret = rb_cloexec_pipe(pipes);
        }
    }
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
    if (fd == -1) return -1;
    ss = read(fd, buf, sizeof(buf));
    if (ss == -1) goto err;
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
    return -1;
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

static int
popen_exec(void *pp, char *errmsg, size_t errmsg_len)
{
    struct popen_arg *p = (struct popen_arg*)pp;

    return rb_exec_async_signal_safe(p->eargp, errmsg, errmsg_len);
}
#endif

#if defined(HAVE_WORKING_FORK) || defined(HAVE_SPAWNV)
static VALUE
rb_execarg_fixup_v(VALUE execarg_obj)
{
    rb_execarg_parent_start(execarg_obj);
    return Qnil;
}
#else
char *rb_execarg_commandline(const struct rb_execarg *eargp, VALUE *prog);
#endif

static VALUE
pipe_open(VALUE execarg_obj, const char *modestr, int fmode, convconfig_t *convconfig)
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
	while ((pid = DO_SPAWN(cmd, args, envp)) == -1) {
	    /* exec failed */
	    switch (e = errno) {
	      case EAGAIN:
#   if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
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
	pid = rb_fork_ruby(&status);
	if (pid == 0) {		/* child */
	    rb_thread_atfork();
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
    if (pid == -1) {
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
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
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
pipe_open_s(VALUE prog, const char *modestr, int fmode, convconfig_t *convconfig)
{
    int argc = 1;
    VALUE *argv = &prog;
    VALUE execarg_obj = Qnil;

    if (!is_popen_fork(prog))
	execarg_obj = rb_execarg_new(argc, argv, TRUE);
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

/*
 *  call-seq:
 *     IO.popen([env,] cmd, mode="r" [, opt])               -> io
 *     IO.popen([env,] cmd, mode="r" [, opt]) {|io| block } -> obj
 *
 *  Runs the specified command as a subprocess; the subprocess's
 *  standard input and output will be connected to the returned
 *  <code>IO</code> object.
 *
 *  The PID of the started process can be obtained by IO#pid method.
 *
 *  _cmd_ is a string or an array as follows.
 *
 *    cmd:
 *      "-"                                      : fork
 *      commandline                              : command line string which is passed to a shell
 *      [env, cmdname, arg1, ..., opts]          : command name and zero or more arguments (no shell)
 *      [env, [cmdname, argv0], arg1, ..., opts] : command name, argv[0] and zero or more arguments (no shell)
 *    (env and opts are optional.)
 *
 *  If _cmd_ is a +String+ ``<code>-</code>'',
 *  then a new instance of Ruby is started as the subprocess.
 *
 *  If <i>cmd</i> is an +Array+ of +String+,
 *  then it will be used as the subprocess's +argv+ bypassing a shell.
 *  The array can contains a hash at first for environments and
 *  a hash at last for options similar to <code>spawn</code>.
 *
 *  The default mode for the new file object is ``r'',
 *  but <i>mode</i> may be set to any of the modes listed in the description for class IO.
 *  The last argument <i>opt</i> qualifies <i>mode</i>.
 *
 *    # set IO encoding
 *    IO.popen("nkf -e filename", :external_encoding=>"EUC-JP") {|nkf_io|
 *      euc_jp_string = nkf_io.read
 *    }
 *
 *    # merge standard output and standard error using
 *    # spawn option.  See the document of Kernel.spawn.
 *    IO.popen(["ls", "/", :err=>[:child, :out]]) {|ls_io|
 *      ls_result_with_error = ls_io.read
 *    }
 *
 *    # spawn options can be mixed with IO options
 *    IO.popen(["ls", "/"], :err=>[:child, :out]) {|ls_io|
 *      ls_result_with_error = ls_io.read
 *    }
 *
 *  Raises exceptions which <code>IO.pipe</code> and
 *  <code>Kernel.spawn</code> raise.
 *
 *  If a block is given, Ruby will run the command as a child connected
 *  to Ruby with a pipe. Ruby's end of the pipe will be passed as a
 *  parameter to the block.
 *  At the end of block, Ruby closes the pipe and sets <code>$?</code>.
 *  In this case <code>IO.popen</code> returns
 *  the value of the block.
 *
 *  If a block is given with a _cmd_ of ``<code>-</code>'',
 *  the block will be run in two separate processes: once in the parent,
 *  and once in a child. The parent process will be passed the pipe
 *  object as a parameter to the block, the child version of the block
 *  will be passed <code>nil</code>, and the child's standard in and
 *  standard out will be connected to the parent through the pipe. Not
 *  available on all platforms.
 *
 *     f = IO.popen("uname")
 *     p f.readlines
 *     f.close
 *     puts "Parent is #{Process.pid}"
 *     IO.popen("date") { |f| puts f.gets }
 *     IO.popen("-") {|f| $stderr.puts "#{Process.pid} is here, f is #{f.inspect}"}
 *     p $?
 *     IO.popen(%w"sed -e s|^|<foo>| -e s&$&;zot;&", "r+") {|f|
 *       f.puts "bar"; f.close_write; puts f.gets
 *     }
 *
 *  <em>produces:</em>
 *
 *     ["Linux\n"]
 *     Parent is 21346
 *     Thu Jan 15 22:41:19 JST 2009
 *     21346 is here, f is #<IO:fd 3>
 *     21352 is here, f is nil
 *     #<Process::Status: pid 21352 exit 0>
 *     <foo>bar;zot;
 */

static VALUE
rb_io_s_popen(int argc, VALUE *argv, VALUE klass)
{
    const char *modestr;
    VALUE pname, pmode = Qnil, port, tmp, opt = Qnil, env = Qnil, execarg_obj = Qnil;
    int oflags, fmode;
    convconfig_t convconfig;

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

    tmp = rb_check_array_type(pname);
    if (!NIL_P(tmp)) {
	long len = RARRAY_LEN(tmp);
#if SIZEOF_LONG > SIZEOF_INT
	if (len > INT_MAX) {
	    rb_raise(rb_eArgError, "too many arguments");
	}
#endif
	execarg_obj = rb_execarg_new((int)len, RARRAY_CONST_PTR(tmp), FALSE);
	RB_GC_GUARD(tmp);
    }
    else {
	SafeStringValue(pname);
	execarg_obj = Qnil;
	if (!is_popen_fork(pname))
	    execarg_obj = rb_execarg_new(1, &pname, TRUE);
    }
    if (!NIL_P(execarg_obj)) {
	if (!NIL_P(opt))
	    opt = rb_execarg_extract_options(execarg_obj, opt);
	if (!NIL_P(env))
	    rb_execarg_setenv(execarg_obj, env);
    }
    rb_io_extract_modeenc(&pmode, 0, opt, &oflags, &fmode, &convconfig);
    modestr = rb_io_oflags_modestr(oflags);

    port = pipe_open(execarg_obj, modestr, fmode, &convconfig);
    if (NIL_P(port)) {
	/* child */
	if (rb_block_given_p()) {
	    rb_yield(Qnil);
            rb_io_flush(rb_stdout);
            rb_io_flush(rb_stderr);
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

static void
rb_scan_open_args(int argc, const VALUE *argv,
        VALUE *fname_p, int *oflags_p, int *fmode_p,
        convconfig_t *convconfig_p, mode_t *perm_p)
{
    VALUE opt, fname, vmode, vperm;
    int oflags, fmode;
    mode_t perm;

    argc = rb_scan_args(argc, argv, "12:", &fname, &vmode, &vperm, &opt);
    FilePathValue(fname);

    rb_io_extract_modeenc(&vmode, &vperm, opt, &oflags, &fmode, convconfig_p);

    perm = NIL_P(vperm) ? 0666 :  NUM2MODET(vperm);

    *fname_p = fname;
    *oflags_p = oflags;
    *fmode_p = fmode;
    *perm_p = perm;
}

static VALUE
rb_open_file(int argc, const VALUE *argv, VALUE io)
{
    VALUE fname;
    int oflags, fmode;
    convconfig_t convconfig;
    mode_t perm;

    rb_scan_open_args(argc, argv, &fname, &oflags, &fmode, &convconfig, &perm);
    rb_file_open_generic(io, fname, oflags, fmode, &convconfig, perm);

    return io;
}


/*
 *  Document-method: File::open
 *
 *  call-seq:
 *     File.open(filename, mode="r" [, opt])                 -> file
 *     File.open(filename [, mode [, perm]] [, opt])         -> file
 *     File.open(filename, mode="r" [, opt]) {|file| block } -> obj
 *     File.open(filename [, mode [, perm]] [, opt]) {|file| block } -> obj
 *
 *  With no associated block, <code>File.open</code> is a synonym for
 *  File.new. If the optional code block is given, it will
 *  be passed the opened +file+ as an argument and the File object will
 *  automatically be closed when the block terminates.  The value of the block
 *  will be returned from <code>File.open</code>.
 *
 *  If a file is being created, its initial permissions may be set using the
 *  +perm+ parameter.  See File.new for further discussion.
 *
 *  See IO.new for a description of the +mode+ and +opt+ parameters.
 */

/*
 *  Document-method: IO::open
 *
 *  call-seq:
 *     IO.open(fd, mode="r" [, opt])                -> io
 *     IO.open(fd, mode="r" [, opt]) { |io| block } -> obj
 *
 *  With no associated block, <code>IO.open</code> is a synonym for IO.new.  If
 *  the optional code block is given, it will be passed +io+ as an argument,
 *  and the IO object will automatically be closed when the block terminates.
 *  In this instance, IO.open returns the value of the block.
 *
 *  See IO.new for a description of the +fd+, +mode+ and +opt+ parameters.
 */

static VALUE
rb_io_s_open(int argc, VALUE *argv, VALUE klass)
{
    VALUE io = rb_class_new_instance(argc, argv, klass);

    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, io, io_close, io);
    }

    return io;
}

/*
 *  call-seq:
 *     IO.sysopen(path, [mode, [perm]])  -> fixnum
 *
 *  Opens the given path, returning the underlying file descriptor as a
 *  <code>Fixnum</code>.
 *
 *     IO.sysopen("testfile")   #=> 3
 */

static VALUE
rb_io_s_sysopen(int argc, VALUE *argv)
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
	SafeStringValue(vmode);
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
        OBJ_INFECT(cmd, filename_or_command);
        return cmd;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     open(path [, mode [, perm]] [, opt])                -> io or nil
 *     open(path [, mode [, perm]] [, opt]) {|io| block }  -> obj
 *
 *  Creates an IO object connected to the given stream, file, or subprocess.
 *
 *  If +path+ does not start with a pipe character (<code>|</code>), treat it
 *  as the name of a file to open using the specified mode (defaulting to
 *  "r").
 *
 *  The +mode+ is either a string or an integer.  If it is an integer, it
 *  must be bitwise-or of open(2) flags, such as File::RDWR or File::EXCL.  If
 *  it is a string, it is either "fmode", "fmode:ext_enc", or
 *  "fmode:ext_enc:int_enc".
 *
 *  See the documentation of IO.new for full documentation of the +mode+ string
 *  directives.
 *
 *  If a file is being created, its initial permissions may be set using the
 *  +perm+ parameter.  See File.new and the open(2) and chmod(2) man pages for
 *  a description of permissions.
 *
 *  If a block is specified, it will be invoked with the IO object as a
 *  parameter, and the IO will be automatically closed when the block
 *  terminates.  The call returns the value of the block.
 *
 *  If +path+ starts with a pipe character (<code>"|"</code>), a subprocess is
 *  created, connected to the caller by a pair of pipes.  The returned IO
 *  object may be used to write to the standard input and read from the
 *  standard output of this subprocess.
 *
 *  If the command following the pipe is a single minus sign
 *  (<code>"|-"</code>), Ruby forks, and this subprocess is connected to the
 *  parent.  If the command is not <code>"-"</code>, the subprocess runs the
 *  command.
 *
 *  When the subprocess is ruby (opened via <code>"|-"</code>), the +open+
 *  call returns +nil+.  If a block is associated with the open call, that
 *  block will run twice --- once in the parent and once in the child.
 *
 *  The block parameter will be an IO object in the parent and +nil+ in the
 *  child. The parent's +IO+ object will be connected to the child's $stdin
 *  and $stdout.  The subprocess will be terminated at the end of the block.
 *
 *  === Examples
 *
 *  Reading from "testfile":
 *
 *     open("testfile") do |f|
 *       print f.gets
 *     end
 *
 *  Produces:
 *
 *     This is line one
 *
 *  Open a subprocess and read its output:
 *
 *     cmd = open("|date")
 *     print cmd.gets
 *     cmd.close
 *
 *  Produces:
 *
 *     Wed Apr  9 08:56:31 CDT 2003
 *
 *  Open a subprocess running the same Ruby program:
 *
 *     f = open("|-", "w+")
 *     if f == nil
 *       puts "in Child"
 *       exit
 *     else
 *       puts "Got: #{f.gets}"
 *     end
 *
 *  Produces:
 *
 *     Got: in Child
 *
 *  Open a subprocess using a block to receive the IO object:
 *
 *     open "|-" do |f|
 *       if f then
 *         # parent process
 *         puts "Got: #{f.gets}"
 *       else
 *         # child process
 *         puts "in Child"
 *       end
 *     end
 *
 *  Produces:
 *
 *     Got: in Child
 */

static VALUE
rb_f_open(int argc, VALUE *argv)
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
		    argv[0] = cmd;
		    return rb_io_s_popen(argc, argv, rb_cIO);
		}
	    }
	}
    }
    if (redirect) {
	VALUE io = rb_funcall2(argv[0], to_open, argc-1, argv+1);

	if (rb_block_given_p()) {
	    return rb_ensure(rb_yield, io, io_close, io);
	}
	return io;
    }
    return rb_io_s_open(argc, argv, rb_cFile);
}

static VALUE
rb_io_open(VALUE filename, VALUE vmode, VALUE vperm, VALUE opt)
{
    VALUE cmd;
    int oflags, fmode;
    convconfig_t convconfig;
    mode_t perm;

    rb_io_extract_modeenc(&vmode, &vperm, opt, &oflags, &fmode, &convconfig);
    perm = NIL_P(vperm) ? 0666 :  NUM2MODET(vperm);

    if (!NIL_P(cmd = check_pipe_command(filename))) {
	return pipe_open_s(cmd, rb_io_oflags_modestr(oflags), fmode, &convconfig);
    }
    else {
        return rb_file_open_generic(io_alloc(rb_cFile), filename,
                oflags, fmode, &convconfig, perm);
    }
}

static VALUE
rb_io_open_with_args(int argc, const VALUE *argv)
{
    VALUE io;

    io = io_alloc(rb_cFile);
    rb_open_file(argc, argv, io);
    return io;
}

static VALUE
io_reopen(VALUE io, VALUE nfile)
{
    rb_io_t *fptr, *orig;
    int fd, fd2;
    off_t pos = 0;

    nfile = rb_io_get_io(nfile);
    GetOpenFile(io, fptr);
    GetOpenFile(nfile, orig);

    if (fptr == orig) return io;
    if (IS_PREP_STDIO(fptr)) {
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
            rb_sys_fail(0);
    }
    else {
	io_tell(fptr);
    }
    if (orig->mode & FMODE_READABLE) {
	pos = io_tell(orig);
    }
    if (orig->mode & FMODE_WRITABLE) {
        if (io_fflush(orig) < 0)
            rb_sys_fail(0);
    }

    /* copy rb_io_t structure */
    fptr->mode = orig->mode | (fptr->mode & FMODE_PREP);
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (RTEST(orig->pathv)) fptr->pathv = orig->pathv;
    else if (!IS_PREP_STDIO(fptr)) fptr->pathv = Qnil;
    fptr->finalize = orig->finalize;
#if defined (__CYGWIN__) || !defined(HAVE_WORKING_FORK)
    if (fptr->finalize == pipe_finalize)
	pipe_add_fptr(fptr);
#endif

    fd = fptr->fd;
    fd2 = orig->fd;
    if (fd != fd2) {
	if (IS_PREP_STDIO(fptr) || fd <= 2 || !fptr->stdio_file) {
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
	rb_thread_fd_close(fd);
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
 *     ios.reopen(other_IO)         -> ios
 *     ios.reopen(path, mode_str)   -> ios
 *
 *  Reassociates <em>ios</em> with the I/O stream given in
 *  <i>other_IO</i> or to a new stream opened on <i>path</i>. This may
 *  dynamically change the actual class of this stream.
 *
 *     f1 = File.new("testfile")
 *     f2 = File.new("testfile")
 *     f2.readlines[0]   #=> "This is line one\n"
 *     f2.reopen(f1)     #=> #<File:testfile>
 *     f2.readlines[0]   #=> "This is line one\n"
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
	int fmode;
	convconfig_t convconfig;

	rb_io_extract_modeenc(&nmode, 0, opt, &oflags, &fmode, &convconfig);
	if (IS_PREP_STDIO(fptr) &&
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
            rb_sys_fail(0);
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
    off_t pos;

    io = rb_io_get_io(io);
    if (!OBJ_INIT_COPY(dest, io)) return dest;
    GetOpenFile(io, orig);
    MakeOpenFile(dest, fptr);

    rb_io_flush(io);

    /* copy rb_io_t structure */
    fptr->mode = orig->mode & ~FMODE_PREP;
    fptr->encs = orig->encs;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (!NIL_P(orig->pathv)) fptr->pathv = orig->pathv;
    fptr->finalize = orig->finalize;
#if defined (__CYGWIN__) || !defined(HAVE_WORKING_FORK)
    if (fptr->finalize == pipe_finalize)
	pipe_add_fptr(fptr);
#endif

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
 *     ios.printf(format_string [, obj, ...])   -> nil
 *
 *  Formats and writes to <em>ios</em>, converting parameters under
 *  control of the format string. See <code>Kernel#sprintf</code>
 *  for details.
 */

VALUE
rb_io_printf(int argc, const VALUE *argv, VALUE out)
{
    rb_io_write(out, rb_f_sprintf(argc, argv));
    return Qnil;
}

/*
 *  call-seq:
 *     printf(io, string [, obj ... ])    -> nil
 *     printf(string [, obj ... ])        -> nil
 *
 *  Equivalent to:
 *     io.write(sprintf(string, obj, ...))
 *  or
 *     $stdout.write(sprintf(string, obj, ...))
 */

static VALUE
rb_f_printf(int argc, VALUE *argv)
{
    VALUE out;

    if (argc == 0) return Qnil;
    if (RB_TYPE_P(argv[0], T_STRING)) {
	out = rb_stdout;
    }
    else {
	out = argv[0];
	argv++;
	argc--;
    }
    rb_io_write(out, rb_f_sprintf(argc, argv));

    return Qnil;
}

/*
 *  call-seq:
 *     ios.print()             -> nil
 *     ios.print(obj, ...)     -> nil
 *
 *  Writes the given object(s) to <em>ios</em>. The stream must be
 *  opened for writing. If the output field separator (<code>$,</code>)
 *  is not <code>nil</code>, it will be inserted between each object.
 *  If the output record separator (<code>$\\</code>)
 *  is not <code>nil</code>, it will be appended to the output. If no
 *  arguments are given, prints <code>$_</code>. Objects that aren't
 *  strings will be converted by calling their <code>to_s</code> method.
 *  With no argument, prints the contents of the variable <code>$_</code>.
 *  Returns <code>nil</code>.
 *
 *     $stdout.print("This is ", 100, " percent.\n")
 *
 *  <em>produces:</em>
 *
 *     This is 100 percent.
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
 *     print(obj, ...)    -> nil
 *
 *  Prints each object in turn to <code>$stdout</code>. If the output
 *  field separator (<code>$,</code>) is not +nil+, its
 *  contents will appear between each field. If the output record
 *  separator (<code>$\\</code>) is not +nil+, it will be
 *  appended to the output. If no arguments are given, prints
 *  <code>$_</code>. Objects that aren't strings will be converted by
 *  calling their <code>to_s</code> method.
 *
 *     print "cat", [1,2,3], 99, "\n"
 *     $, = ", "
 *     $\ = "\n"
 *     print "cat", [1,2,3], 99
 *
 *  <em>produces:</em>
 *
 *     cat12399
 *     cat, 1, 2, 3, 99
 */

static VALUE
rb_f_print(int argc, const VALUE *argv)
{
    rb_io_print(argc, argv, rb_stdout);
    return Qnil;
}

/*
 *  call-seq:
 *     ios.putc(obj)    -> obj
 *
 *  If <i>obj</i> is <code>Numeric</code>, write the character whose code is
 *  the least-significant byte of <i>obj</i>, otherwise write the first byte
 *  of the string representation of <i>obj</i> to <em>ios</em>. Note: This
 *  method is not safe for use with multi-byte characters as it will truncate
 *  them.
 *
 *     $stdout.putc "A"
 *     $stdout.putc 65
 *
 *  <em>produces:</em>
 *
 *     AA
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

/*
 *  call-seq:
 *     putc(int)   -> int
 *
 *  Equivalent to:
 *
 *    $stdout.putc(int)
 *
 * Refer to the documentation for IO#putc for important information regarding
 * multi-byte characters.
 */

static VALUE
rb_f_putc(VALUE recv, VALUE ch)
{
    if (recv == rb_stdout) {
	return rb_io_putc(recv, ch);
    }
    return rb_funcall2(rb_stdout, rb_intern("putc"), 1, &ch);
}


static int
str_end_with_asciichar(VALUE str, int c)
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
 *     ios.puts(obj, ...)    -> nil
 *
 *  Writes the given objects to <em>ios</em> as with
 *  <code>IO#print</code>. Writes a record separator (typically a
 *  newline) after any that do not already end with a newline sequence.
 *  If called with an array argument, writes each element on a new line.
 *  If called without arguments, outputs a single record separator.
 *
 *     $stdout.puts("this", "is", "a", "test")
 *
 *  <em>produces:</em>
 *
 *     this
 *     is
 *     a
 *     test
 */

VALUE
rb_io_puts(int argc, const VALUE *argv, VALUE out)
{
    int i;
    VALUE line;

    /* if no argument given, print newline. */
    if (argc == 0) {
	rb_io_write(out, rb_default_rs);
	return Qnil;
    }
    for (i=0; i<argc; i++) {
	if (RB_TYPE_P(argv[i], T_STRING)) {
	    line = argv[i];
	    goto string;
	}
	if (rb_exec_recursive(io_puts_ary, argv[i], out)) {
	    continue;
	}
	line = rb_obj_as_string(argv[i]);
      string:
	rb_io_write(out, line);
	if (RSTRING_LEN(line) == 0 ||
            !str_end_with_asciichar(line, '\n')) {
	    rb_io_write(out, rb_default_rs);
	}
    }

    return Qnil;
}

/*
 *  call-seq:
 *     puts(obj, ...)    -> nil
 *
 *  Equivalent to
 *
 *      $stdout.puts(obj, ...)
 */

static VALUE
rb_f_puts(int argc, VALUE *argv, VALUE recv)
{
    if (recv == rb_stdout) {
	return rb_io_puts(argc, argv, recv);
    }
    return rb_funcall2(rb_stdout, rb_intern("puts"), argc, argv);
}

void
rb_p(VALUE obj) /* for debug print within C code */
{
    VALUE str = rb_obj_as_string(rb_inspect(obj));
    if (RB_TYPE_P(rb_stdout, T_FILE) &&
        rb_method_basic_definition_p(CLASS_OF(rb_stdout), id_write)) {
        io_write(rb_stdout, str, 1);
        io_write(rb_stdout, rb_default_rs, 0);
    }
    else {
        rb_io_write(rb_stdout, str);
        rb_io_write(rb_stdout, rb_default_rs);
    }
}

struct rb_f_p_arg {
    int argc;
    VALUE *argv;
};

static VALUE
rb_f_p_internal(VALUE arg)
{
    struct rb_f_p_arg *arg1 = (struct rb_f_p_arg*)arg;
    int argc = arg1->argc;
    VALUE *argv = arg1->argv;
    int i;
    VALUE ret = Qnil;

    for (i=0; i<argc; i++) {
	rb_p(argv[i]);
    }
    if (argc == 1) {
	ret = argv[0];
    }
    else if (argc > 1) {
	ret = rb_ary_new4(argc, argv);
    }
    if (RB_TYPE_P(rb_stdout, T_FILE)) {
	rb_io_flush(rb_stdout);
    }
    return ret;
}

/*
 *  call-seq:
 *     p(obj)              -> obj
 *     p(obj1, obj2, ...)  -> [obj, ...]
 *     p()                 -> nil
 *
 *  For each object, directly writes _obj_.+inspect+ followed by a
 *  newline to the program's standard output.
 *
 *     S = Struct.new(:name, :state)
 *     s = S['dave', 'TX']
 *     p s
 *
 *  <em>produces:</em>
 *
 *     #<S name="dave", state="TX">
 */

static VALUE
rb_f_p(int argc, VALUE *argv, VALUE self)
{
    struct rb_f_p_arg arg;
    arg.argc = argc;
    arg.argv = argv;

    return rb_uninterruptible(rb_f_p_internal, (VALUE)&arg);
}

/*
 *  call-seq:
 *     obj.display(port=$>)    -> nil
 *
 *  Prints <i>obj</i> on the given port (default <code>$></code>).
 *  Equivalent to:
 *
 *     def display(port=$>)
 *       port.write self
 *     end
 *
 *  For example:
 *
 *     1.display
 *     "cat".display
 *     [ 4, 5, 6 ].display
 *     puts
 *
 *  <em>produces:</em>
 *
 *     1cat456
 */

static VALUE
rb_obj_display(int argc, VALUE *argv, VALUE self)
{
    VALUE out;

    if (argc == 0) {
	out = rb_stdout;
    }
    else {
	rb_scan_args(argc, argv, "01", &out);
    }
    rb_io_write(out, self);

    return Qnil;
}

void
rb_write_error2(const char *mesg, long len)
{
    if (rb_stderr == orig_stderr || RFILE(orig_stderr)->fptr->fd < 0) {
	if (fwrite(mesg, sizeof(char), (size_t)len, stderr) < (size_t)len) {
	    /* failed to write to stderr, what can we do? */
	    return;
	}
    }
    else {
	rb_io_write(rb_stderr, rb_str_new(mesg, len));
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
    /* a stopgap measure for the time being */
    if (rb_stderr == orig_stderr || RFILE(orig_stderr)->fptr->fd < 0) {
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
	rb_io_write(rb_stderr, mesg);
    }
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
stdout_setter(VALUE val, ID id, VALUE *variable)
{
    must_respond_to(id_write, val, id);
    *variable = val;
}

static VALUE
prep_io(int fd, int fmode, VALUE klass, const char *path)
{
    rb_io_t *fp;
    VALUE io = io_alloc(klass);

    MakeOpenFile(io, fp);
    fp->fd = fd;
#ifdef __CYGWIN__
    if (!isatty(fd)) {
        fmode |= FMODE_BINMODE;
	setmode(fd, O_BINARY);
    }
#endif
    fp->mode = fmode;
    io_check_tty(fp);
    if (path) fp->pathv = rb_obj_freeze(rb_str_new_cstr(path));
    rb_update_max_fd(fd);

    return io;
}

VALUE
rb_io_fdopen(int fd, int oflags, const char *path)
{
    VALUE klass = rb_cIO;

    if (path && strcmp(path, "-")) klass = rb_cFile;
    return prep_io(fd, rb_io_oflags_fmode(oflags), klass, path);
}

static VALUE
prep_stdio(FILE *f, int fmode, VALUE klass, const char *path)
{
    rb_io_t *fptr;
    VALUE io = prep_io(fileno(f), fmode|FMODE_PREP|DEFAULT_TEXTMODE, klass, path);

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

FILE *
rb_io_stdio_file(rb_io_t *fptr)
{
    if (!fptr->stdio_file) {
        int oflags = rb_io_fmode_oflags(fptr->mode);
        fptr->stdio_file = rb_fdopen(fptr->fd, rb_io_oflags_modestr(oflags));
    }
    return fptr->stdio_file;
}

static inline void
rb_io_buffer_init(rb_io_buffer_t *buf)
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
    fp->write_lock = 0;
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
    RFILE(obj)->fptr = fp;
    return fp;
}

/*
 *  call-seq:
 *     IO.new(fd [, mode] [, opt])   -> io
 *
 *  Returns a new IO object (a stream) for the given integer file descriptor
 *  +fd+ and +mode+ string.  +opt+ may be used to specify parts of +mode+ in a
 *  more readable fashion.  See also IO.sysopen and IO.for_fd.
 *
 *  IO.new is called by various File and IO opening methods such as IO::open,
 *  Kernel#open, and File::open.
 *
 *  === Open Mode
 *
 *  When +mode+ is an integer it must be combination of the modes defined in
 *  File::Constants (+File::RDONLY+, +File::WRONLY | File::CREAT+).  See the
 *  open(2) man page for more information.
 *
 *  When +mode+ is a string it must be in one of the following forms:
 *
 *    fmode
 *    fmode ":" ext_enc
 *    fmode ":" ext_enc ":" int_enc
 *    fmode ":" "BOM|UTF-*"
 *
 *  +fmode+ is an IO open mode string, +ext_enc+ is the external encoding for
 *  the IO and +int_enc+ is the internal encoding.
 *
 *  ==== IO Open Mode
 *
 *  Ruby allows the following open modes:
 *
 *  	"r"  Read-only, starts at beginning of file  (default mode).
 *
 *  	"r+" Read-write, starts at beginning of file.
 *
 *  	"w"  Write-only, truncates existing file
 *  	     to zero length or creates a new file for writing.
 *
 *  	"w+" Read-write, truncates existing file to zero length
 *  	     or creates a new file for reading and writing.
 *
 *  	"a"  Write-only, each write call appends data at end of file.
 *  	     Creates a new file for writing if file does not exist.
 *
 *  	"a+" Read-write, each write call appends data at end of file.
 *	     Creates a new file for reading and writing if file does
 *	     not exist.
 *
 *  The following modes must be used separately, and along with one or more of
 *  the modes seen above.
 *
 *  	"b"  Binary file mode
 *  	     Suppresses EOL <-> CRLF conversion on Windows. And
 *  	     sets external encoding to ASCII-8BIT unless explicitly
 *  	     specified.
 *
 *  	"t"  Text file mode
 *
 *  When the open mode of original IO is read only, the mode cannot be
 *  changed to be writable.  Similarly, the open mode cannot be changed from
 *  write only to readable.
 *
 *  When such a change is attempted the error is raised in different locations
 *  according to the platform.
 *
 *  === IO Encoding
 *
 *  When +ext_enc+ is specified, strings read will be tagged by the encoding
 *  when reading, and strings output will be converted to the specified
 *  encoding when writing.
 *
 *  When +ext_enc+ and +int_enc+ are specified read strings will be converted
 *  from +ext_enc+ to +int_enc+ upon input, and written strings will be
 *  converted from +int_enc+ to +ext_enc+ upon output.  See Encoding for
 *  further details of transcoding on input and output.
 *
 *  If "BOM|UTF-8", "BOM|UTF-16LE" or "BOM|UTF16-BE" are used, ruby checks for
 *  a Unicode BOM in the input document to help determine the encoding.  For
 *  UTF-16 encodings the file open mode must be binary.  When present, the BOM
 *  is stripped and the external encoding from the BOM is used.  When the BOM
 *  is missing the given Unicode encoding is used as +ext_enc+.  (The BOM-set
 *  encoding option is case insensitive, so "bom|utf-8" is also valid.)
 *
 *  === Options
 *
 *  +opt+ can be used instead of +mode+ for improved readability.  The
 *  following keys are supported:
 *
 *  :mode ::
 *    Same as +mode+ parameter
 *
 *  :flags ::
 *    Specifies file open flags as integer.
 *    If +mode+ parameter is given, this parameter will be bitwise-ORed.
 *
 *  :\external_encoding ::
 *    External encoding for the IO.  "-" is a synonym for the default external
 *    encoding.
 *
 *  :\internal_encoding ::
 *    Internal encoding for the IO.  "-" is a synonym for the default internal
 *    encoding.
 *
 *    If the value is nil no conversion occurs.
 *
 *  :encoding ::
 *    Specifies external and internal encodings as "extern:intern".
 *
 *  :textmode ::
 *    If the value is truth value, same as "t" in argument +mode+.
 *
 *  :binmode ::
 *    If the value is truth value, same as "b" in argument +mode+.
 *
 *  :autoclose ::
 *    If the value is +false+, the +fd+ will be kept open after this IO
 *    instance gets finalized.
 *
 *  Also, +opt+ can have same keys in String#encode for controlling conversion
 *  between the external encoding and the internal encoding.
 *
 *  === Example 1
 *
 *    fd = IO.sysopen("/dev/tty", "w")
 *    a = IO.new(fd,"w")
 *    $stderr.puts "Hello"
 *    a.puts "World"
 *
 *  Produces:
 *
 *    Hello
 *    World
 *
 *  === Example 2
 *
 *    require 'fcntl'
 *
 *    fd = STDERR.fcntl(Fcntl::F_DUPFD)
 *    io = IO.new(fd, mode: 'w:UTF-16LE', cr_newline: true)
 *    io.puts "Hello, World!"
 *
 *    fd = STDERR.fcntl(Fcntl::F_DUPFD)
 *    io = IO.new(fd, mode: 'w', cr_newline: true,
 *                external_encoding: Encoding::UTF_16LE)
 *    io.puts "Hello, World!"
 *
 *  Both of above print "Hello, World!" in UTF-16LE to standard error output
 *  with converting EOL generated by <code>puts</code> to CR.
 */

static VALUE
rb_io_initialize(int argc, VALUE *argv, VALUE io)
{
    VALUE fnum, vmode;
    rb_io_t *fp;
    int fd, fmode, oflags = O_RDONLY;
    convconfig_t convconfig;
    VALUE opt;
#if defined(HAVE_FCNTL) && defined(F_GETFL)
    int ofmode;
#else
    struct stat st;
#endif


    argc = rb_scan_args(argc, argv, "11:", &fnum, &vmode, &opt);
    rb_io_extract_modeenc(&vmode, 0, opt, &oflags, &fmode, &convconfig);

    fd = NUM2INT(fnum);
    if (rb_reserved_fd_p(fd)) {
	rb_raise(rb_eArgError, "The given fd is not accessible because RubyVM reserves it");
    }
#if defined(HAVE_FCNTL) && defined(F_GETFL)
    oflags = fcntl(fd, F_GETFL);
    if (oflags == -1) rb_sys_fail(0);
#else
    if (fstat(fd, &st) == -1) rb_sys_fail(0);
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
    if (!NIL_P(opt) && rb_hash_aref(opt, sym_autoclose) == Qfalse) {
	fmode |= FMODE_PREP;
    }
    MakeOpenFile(io, fp);
    fp->fd = fd;
    fp->mode = fmode;
    fp->encs = convconfig;
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
 *     File.new(filename, mode="r" [, opt])            -> file
 *     File.new(filename [, mode [, perm]] [, opt])    -> file
 *
 *  Opens the file named by +filename+ according to the given +mode+ and
 *  returns a new File object.
 *
 *  See IO.new for a description of +mode+ and +opt+.
 *
 *  If a file is being created, permission bits may be given in +perm+.  These
 *  mode and permission bits are platform dependent; on Unix systems, see
 *  open(2) and chmod(2) man pages for details.
 *
 *  === Examples
 *
 *    f = File.new("testfile", "r")
 *    f = File.new("newfile",  "w+")
 *    f = File.new("newfile", File::CREAT|File::TRUNC|File::RDWR, 0644)
 */

static VALUE
rb_file_initialize(int argc, VALUE *argv, VALUE io)
{
    if (RFILE(io)->fptr) {
	rb_raise(rb_eRuntimeError, "reinitializing File");
    }
    if (0 < argc && argc < 3) {
	VALUE fd = rb_check_convert_type(argv[0], T_FIXNUM, "Fixnum", "to_int");

	if (!NIL_P(fd)) {
	    argv[0] = fd;
	    return rb_io_initialize(argc, argv, io);
	}
    }
    rb_open_file(argc, argv, io);

    return io;
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
    return rb_class_new_instance(argc, argv, klass);
}


/*
 *  call-seq:
 *     IO.for_fd(fd, mode [, opt])    -> io
 *
 *  Synonym for <code>IO.new</code>.
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
 *  closed automatically at its finalization, otherwise +false+.
 */

static VALUE
rb_io_autoclose_p(VALUE io)
{
    rb_io_t *fptr = RFILE(io)->fptr;
    rb_io_check_closed(fptr);
    return (fptr->mode & FMODE_PREP) ? Qfalse : Qtrue;
}

/*
 *  call-seq:
 *     io.autoclose = bool    -> true or false
 *
 *  Sets auto-close flag.
 *
 *     f = open("/dev/null")
 *     IO.for_fd(f.fileno)
 *     # ...
 *     f.gets # may cause IOError
 *
 *     f = open("/dev/null")
 *     IO.for_fd(f.fileno).autoclose = true
 *     # ...
 *     f.gets # won't cause IOError
 */

static VALUE
rb_io_set_autoclose(VALUE io, VALUE autoclose)
{
    rb_io_t *fptr;
    GetOpenFile(io, fptr);
    if (!RTEST(autoclose))
	fptr->mode |= FMODE_PREP;
    else
	fptr->mode &= ~FMODE_PREP;
    return io;
}

static void
argf_mark(void *ptr)
{
    struct argf *p = ptr;
    rb_gc_mark(p->filename);
    rb_gc_mark(p->current_file);
    rb_gc_mark(p->argv);
    rb_gc_mark(p->encs.ecopts);
}

static void
argf_free(void *ptr)
{
    struct argf *p = ptr;
    xfree(p->inplace);
    xfree(p);
}

static size_t
argf_memsize(const void *ptr)
{
    const struct argf *p = ptr;
    size_t size = sizeof(*p);
    if (p->inplace) size += strlen(p->inplace) + 1;
    return size;
}

static const rb_data_type_t argf_type = {
    "ARGF",
    {argf_mark, argf_free, argf_memsize},
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
    if (ARGF.inplace) {
	const char *inplace = ARGF.inplace;
	ARGF.inplace = 0;
	ARGF.inplace = ruby_strdup(inplace);
    }
    return argf;
}

/*
 *  call-seq:
 *     ARGF.lineno = integer  -> integer
 *
 *  Sets the line number of +ARGF+ as a whole to the given +Integer+.
 *
 *  +ARGF+ sets the line number automatically as you read data, so normally
 *  you will not need to set it explicitly. To access the current line number
 *  use +ARGF.lineno+.
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
    return Qnil;
}

/*
 *  call-seq:
 *     ARGF.lineno -> integer
 *
 *  Returns the current line number of ARGF as a whole. This value
 *  can be set manually with +ARGF.lineno=+.
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
    return rb_funcall3(ARGF.current_file, rb_frame_this_func(), argc, argv);
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
    rb_funcall3(file, rb_intern("close"), 0, 0);
    ARGF.init_p = -1;
}

static int
argf_next_argv(VALUE argf)
{
    char *fn;
    rb_io_t *fptr;
    int stdout_binmode = 0;
    int fmode;

    if (RB_TYPE_P(rb_stdout, T_FILE)) {
        GetOpenFile(rb_stdout, fptr);
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
      retry:
	if (RARRAY_LEN(ARGF.argv) > 0) {
	    VALUE filename = rb_ary_shift(ARGF.argv);
	    StringValueCStr(filename);
	    ARGF.filename = rb_str_encode_ospath(filename);
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

		    if (RB_TYPE_P(rb_stdout, T_FILE) && rb_stdout != orig_stdout) {
			rb_io_close(rb_stdout);
		    }
		    fstat(fr, &st);
		    str = filename;
		    if (*ARGF.inplace) {
			str = rb_str_dup(str);
			rb_str_cat2(str, ARGF.inplace);
			/* TODO: encoding of ARGF.inplace */
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
		    rb_stdout = write_io;
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
	    rb_stdout = orig_stdout;
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
	line = rb_funcall3(ARGF.current_file, idGets, argc, argv);
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

static VALUE argf_gets(int, VALUE *, VALUE);

/*
 *  call-seq:
 *     gets(sep=$/)    -> string or nil
 *     gets(limit)     -> string or nil
 *     gets(sep,limit) -> string or nil
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
 *  filenames are present in +ARGV+, +gets(nil)+ will read the contents
 *  one file at a time.
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
    return rb_funcall2(argf, idGets, argc, argv);
}

/*
 *  call-seq:
 *     ARGF.gets(sep=$/)     -> string or nil
 *     ARGF.gets(limit)      -> string or nil
 *     ARGF.gets(sep, limit) -> string or nil
 *
 *  Returns the next line from the current file in +ARGF+.
 *
 *  By default lines are assumed to be separated by +$/+; to use a different
 *  character as a separator, supply it as a +String+ for the _sep_ argument.
 *
 *  The optional _limit_ argument specifies how many characters of each line
 *  to return. By default all characters are returned.
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
 *     readline(sep=$/)     -> string
 *     readline(limit)      -> string
 *     readline(sep, limit) -> string
 *
 *  Equivalent to <code>Kernel::gets</code>, except
 *  +readline+ raises +EOFError+ at end of file.
 */

static VALUE
rb_f_readline(int argc, VALUE *argv, VALUE recv)
{
    if (recv == argf) {
	return argf_readline(argc, argv, argf);
    }
    return rb_funcall2(argf, rb_intern("readline"), argc, argv);
}


/*
 *  call-seq:
 *     ARGF.readline(sep=$/)     -> string
 *     ARGF.readline(limit)      -> string
 *     ARGF.readline(sep, limit) -> string
 *
 *  Returns the next line from the current file in +ARGF+.
 *
 *  By default lines are assumed to be separated by +$/+; to use a different
 *  character as a separator, supply it as a +String+ for the _sep_ argument.
 *
 *  The optional  _limit_ argument specifies how many characters of each line
 *  to return. By default all characters are returned.
 *
 *  An +EOFError+ is raised at the end of the file.
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
 *     readlines(sep=$/)    -> array
 *     readlines(limit)     -> array
 *     readlines(sep,limit) -> array
 *
 *  Returns an array containing the lines returned by calling
 *  <code>Kernel.gets(<i>sep</i>)</code> until the end of file.
 */

static VALUE
rb_f_readlines(int argc, VALUE *argv, VALUE recv)
{
    if (recv == argf) {
	return argf_readlines(argc, argv, argf);
    }
    return rb_funcall2(argf, rb_intern("readlines"), argc, argv);
}

/*
 *  call-seq:
 *     ARGF.readlines(sep=$/)     -> array
 *     ARGF.readlines(limit)      -> array
 *     ARGF.readlines(sep, limit) -> array
 *
 *     ARGF.to_a(sep=$/)     -> array
 *     ARGF.to_a(limit)      -> array
 *     ARGF.to_a(sep, limit) -> array
 *
 *  Reads +ARGF+'s current file in its entirety, returning an +Array+ of its
 *  lines, one line per element. Lines are assumed to be separated by _sep_.
 *
 *     lines = ARGF.readlines
 *     lines[0]                #=> "This is line one\n"
 */
static VALUE
argf_readlines(int argc, VALUE *argv, VALUE argf)
{
    long lineno = ARGF.lineno;
    VALUE lines, ary;

    ary = rb_ary_new();
    while (next_argv()) {
	if (ARGF_GENERIC_INPUT_P()) {
	    lines = rb_funcall3(ARGF.current_file, rb_intern("readlines"), argc, argv);
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
 *     `cmd`    -> string
 *
 *  Returns the standard output of running _cmd_ in a subshell.
 *  The built-in syntax <code>%x{...}</code> uses
 *  this method. Sets <code>$?</code> to the process status.
 *
 *     `date`                   #=> "Wed Apr  9 08:56:30 CDT 2003\n"
 *     `ls testdir`.split[1]    #=> "main.rb"
 *     `echo oops && exit 99`   #=> "oops\n"
 *     $?.exitstatus            #=> 99
 */

static VALUE
rb_f_backquote(VALUE obj, VALUE str)
{
    VALUE port;
    VALUE result;
    rb_io_t *fptr;

    SafeStringValue(str);
    rb_last_status_clear();
    port = pipe_open_s(str, "r", FMODE_READABLE|DEFAULT_TEXTMODE, NULL);
    if (NIL_P(port)) return rb_str_new(0,0);

    GetOpenFile(port, fptr);
    result = read_all(fptr, remain_size(fptr), Qnil);
    rb_io_close(port);
    rb_io_fptr_finalize(fptr);
    rb_gc_force_recycle(port); /* also guards from premature GC */

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
    off_t offset;
    off_t len;
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
do_io_advise(rb_io_t *fptr, VALUE advice, off_t offset, off_t len)
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

    rv = (int)rb_thread_io_blocking_region(io_advise_internal, &ias, fptr->fd);
    if (rv && rv != ENOSYS) {
	/* posix_fadvise(2) doesn't set errno. On success it returns 0; otherwise
	   it returns the error code. */
	VALUE message = rb_sprintf("%"PRIsVALUE" "
				   "(%"PRI_OFF_T_PREFIX"d, "
				   "%"PRI_OFF_T_PREFIX"d, "
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
 *     ios.advise(advice, offset=0, len=0) -> nil
 *
 *  Announce an intention to access data from the current file in a
 *  specific pattern. On platforms that do not support the
 *  <em>posix_fadvise(2)</em> system call, this method is a no-op.
 *
 *  _advice_ is one of the following symbols:
 *
 *  :normal::     No advice to give; the default assumption for an open file.
 *  :sequential:: The data will be accessed sequentially
 *                with lower offsets read before higher ones.
 *  :random::     The data will be accessed in random order.
 *  :willneed::   The data will be accessed in the near future.
 *  :dontneed::   The data will not be accessed in the near future.
 *  :noreuse::    The data will only be accessed once.
 *
 *  The semantics of a piece of advice are platform-dependent. See
 *  <em>man 2 posix_fadvise</em> for details.
 *
 *  "data" means the region of the current file that begins at
 *  _offset_ and extends for _len_ bytes. If _len_ is 0, the region
 *  ends at the last byte of the file. By default, both _offset_ and
 *  _len_ are 0, meaning that the advice applies to the entire file.
 *
 *  If an error occurs, one of the following exceptions will be raised:
 *
 *  <code>IOError</code>:: The <code>IO</code> stream is closed.
 *  <code>Errno::EBADF</code>::
 *    The file descriptor of the current file is invalid.
 *  <code>Errno::EINVAL</code>:: An invalid value for _advice_ was given.
 *  <code>Errno::ESPIPE</code>::
 *    The file descriptor of the current file refers to a FIFO or
 *    pipe. (Linux raises <code>Errno::EINVAL</code> in this case).
 *  <code>TypeError</code>::
 *    Either _advice_ was not a Symbol, or one of the
 *    other arguments was not an <code>Integer</code>.
 *  <code>RangeError</code>:: One of the arguments given was too big/small.
 *
 *  This list is not exhaustive; other Errno:: exceptions are also possible.
 */
static VALUE
rb_io_advise(int argc, VALUE *argv, VALUE io)
{
    VALUE advice, offset, len;
    off_t off, l;
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

/*
 *  call-seq:
 *     IO.select(read_array [, write_array [, error_array [, timeout]]]) -> array  or  nil
 *
 *  Calls select(2) system call.
 *  It monitors given arrays of <code>IO</code> objects, waits until one or more
 *  of <code>IO</code> objects are ready for reading, are ready for writing,
 *  and have pending exceptions respectively, and returns an array that
 *  contains arrays of those IO objects.  It will return <code>nil</code>
 *  if optional <i>timeout</i> value is given and no <code>IO</code> object
 *  is ready in <i>timeout</i> seconds.
 *
 *  <code>IO.select</code> peeks the buffer of <code>IO</code> objects for testing readability.
 *  If the <code>IO</code> buffer is not empty,
 *  <code>IO.select</code> immediately notifies readability.
 *  This "peek" only happens for <code>IO</code> objects.
 *  It does not happen for IO-like objects such as OpenSSL::SSL::SSLSocket.
 *
 *  The best way to use <code>IO.select</code> is invoking it
 *  after nonblocking methods such as <code>read_nonblock</code>, <code>write_nonblock</code>, etc.
 *  The methods raise an exception which is extended by
 *  <code>IO::WaitReadable</code> or <code>IO::WaitWritable</code>.
 *  The modules notify how the caller should wait with <code>IO.select</code>.
 *  If <code>IO::WaitReadable</code> is raised, the caller should wait for reading.
 *  If <code>IO::WaitWritable</code> is raised, the caller should wait for writing.
 *
 *  So, blocking read (<code>readpartial</code>) can be emulated using
 *  <code>read_nonblock</code> and <code>IO.select</code> as follows:
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
 *  Especially, the combination of nonblocking methods and
 *  <code>IO.select</code> is preferred for <code>IO</code> like
 *  objects such as <code>OpenSSL::SSL::SSLSocket</code>.
 *  It has <code>to_io</code> method to return underlying <code>IO</code> object.
 *  <code>IO.select</code> calls <code>to_io</code> to obtain the file descriptor to wait.
 *
 *  This means that readability notified by <code>IO.select</code> doesn't mean
 *  readability from <code>OpenSSL::SSL::SSLSocket</code> object.
 *
 *  The most likely situation is that <code>OpenSSL::SSL::SSLSocket</code> buffers some data.
 *  <code>IO.select</code> doesn't see the buffer.
 *  So <code>IO.select</code> can block when <code>OpenSSL::SSL::SSLSocket#readpartial</code> doesn't block.
 *
 *  However, several more complicated situations exist.
 *
 *  SSL is a protocol which is sequence of records.
 *  The record consists of multiple bytes.
 *  So, the remote side of SSL sends a partial record,
 *  <code>IO.select</code> notifies readability but
 *  <code>OpenSSL::SSL::SSLSocket</code> cannot decrypt a byte and
 *  <code>OpenSSL::SSL::SSLSocket#readpartial</code> will blocks.
 *
 *  Also, the remote side can request SSL renegotiation which forces
 *  the local SSL engine to write some data.
 *  This means <code>OpenSSL::SSL::SSLSocket#readpartial</code> may
 *  invoke <code>write</code> system call and it can block.
 *  In such a situation, <code>OpenSSL::SSL::SSLSocket#read_nonblock</code>
 *  raises IO::WaitWritable instead of blocking.
 *  So, the caller should wait for ready for writability as above example.
 *
 *  The combination of nonblocking methods and <code>IO.select</code> is
 *  also useful for streams such as tty, pipe socket socket when
 *  multiple processes read from a stream.
 *
 *  Finally, Linux kernel developers don't guarantee that
 *  readability of select(2) means readability of following read(2) even
 *  for a single process.
 *  See select(2) manual on GNU/Linux system.
 *
 *  Invoking <code>IO.select</code> before <code>IO#readpartial</code> works well as usual.
 *  However it is not the best way to use <code>IO.select</code>.
 *
 *  The writability notified by select(2) doesn't show
 *  how many bytes writable.
 *  <code>IO#write</code> method blocks until given whole string is written.
 *  So, <code>IO#write(two or more bytes)</code> can block after writability is notified by <code>IO.select</code>.
 *  <code>IO#write_nonblock</code> is required to avoid the blocking.
 *
 *  Blocking write (<code>write</code>) can be emulated using
 *  <code>write_nonblock</code> and <code>IO.select</code> as follows:
 *  IO::WaitReadable should also be rescued for SSL renegotiation in <code>OpenSSL::SSL::SSLSocket</code>.
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
 *  === Parameters
 *  read_array:: an array of <code>IO</code> objects that wait until ready for read
 *  write_array:: an array of <code>IO</code> objects that wait until ready for write
 *  error_array:: an array of <code>IO</code> objects that wait for exceptions
 *  timeout:: a numeric value in second
 *
 *  === Example
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
 *  <em>produces:</em>
 *
 *      ping pong
 *      ping pong
 *      ping pong
 *      (snipped)
 *      ping
 */

static VALUE
rb_f_select(int argc, VALUE *argv, VALUE obj)
{
    VALUE timeout;
    struct select_args args;
    struct timeval timerec;
    int i;

    rb_scan_args(argc, argv, "13", &args.read, &args.write, &args.except, &timeout);
    if (NIL_P(timeout)) {
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

#if defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__APPLE__)
 typedef unsigned long ioctl_req_t;
# define NUM2IOCTLREQ(num) NUM2ULONG(num)
#else
 typedef int ioctl_req_t;
# define NUM2IOCTLREQ(num) NUM2INT(num)
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
do_ioctl(int fd, ioctl_req_t cmd, long narg)
{
    int retval;
    struct ioctl_arg arg;

    arg.fd = fd;
    arg.cmd = cmd;
    arg.narg = narg;

    retval = (int)rb_thread_io_blocking_region(nogvl_ioctl, &arg, fd);

    return retval;
}
#endif

#define DEFULT_IOCTL_NARG_LEN (256)

#if defined(__linux__) && defined(_IOC_SIZE)
static long
linux_iocparm_len(ioctl_req_t cmd)
{
    long len;

    if ((cmd & 0xFFFF0000) == 0) {
	/* legacy and unstructured ioctl number. */
	return DEFULT_IOCTL_NARG_LEN;
    }

    len = _IOC_SIZE(cmd);

    /* paranoia check for silly drivers which don't keep ioctl convention */
    if (len < DEFULT_IOCTL_NARG_LEN)
	len = DEFULT_IOCTL_NARG_LEN;

    return len;
}
#endif

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
    len = DEFULT_IOCTL_NARG_LEN;
#endif

    return len;
}

#ifdef HAVE_FCNTL
#ifdef __linux__
typedef long fcntl_arg_t;
#else
/* posix */
typedef int fcntl_arg_t;
#endif

#if defined __native_client__ && !defined __GLIBC__
// struct flock is currently missing the NaCl newlib headers
// TODO(sbc): remove this once it gets added.
#undef F_GETLK
#undef F_SETLK
#undef F_SETLKW
#endif

static long
fcntl_narg_len(int cmd)
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
fcntl_narg_len(int cmd)
{
    return 0;
}
#endif /* HAVE_FCNTL */

static long
setup_narg(ioctl_req_t cmd, VALUE *argp, int io_p)
{
    long narg = 0;
    VALUE arg = *argp;

    if (NIL_P(arg) || arg == Qfalse) {
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
	    if (io_p)
		len = ioctl_narg_len(cmd);
	    else
		len = fcntl_narg_len((int)cmd);
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
	    ptr[slen - 1] = 17;
	    narg = (long)(SIGNED_VALUE)ptr;
	}
    }

    return narg;
}

#ifdef HAVE_IOCTL
static VALUE
rb_ioctl(VALUE io, VALUE req, VALUE arg)
{
    ioctl_req_t cmd = NUM2IOCTLREQ(req);
    rb_io_t *fptr;
    long narg;
    int retval;

    narg = setup_narg(cmd, &arg, 1);
    GetOpenFile(io, fptr);
    retval = do_ioctl(fptr->fd, cmd, narg);
    if (retval < 0) rb_sys_fail_path(fptr->pathv);
    if (RB_TYPE_P(arg, T_STRING)) {
	char *ptr;
	long slen;
	RSTRING_GETMEM(arg, ptr, slen);
	if (ptr[slen-1] != 17)
	    rb_raise(rb_eArgError, "return value overflowed string");
	ptr[slen-1] = '\0';
    }

    return INT2NUM(retval);
}

/*
 *  call-seq:
 *     ios.ioctl(integer_cmd, arg)    -> integer
 *
 *  Provides a mechanism for issuing low-level commands to control or
 *  query I/O devices. Arguments and results are platform dependent. If
 *  <i>arg</i> is a number, its value is passed directly. If it is a
 *  string, it is interpreted as a binary sequence of bytes. On Unix
 *  platforms, see <code>ioctl(2)</code> for details. Not implemented on
 *  all platforms.
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
do_fcntl(int fd, int cmd, long narg)
{
    int retval;
    struct fcntl_arg arg;

    arg.fd = fd;
    arg.cmd = cmd;
    arg.narg = narg;

    retval = (int)rb_thread_io_blocking_region(nogvl_fcntl, &arg, fd);
#if defined(F_DUPFD)
    if (retval != -1 && cmd == F_DUPFD) {
	rb_update_max_fd(retval);
    }
#endif

    return retval;
}

static VALUE
rb_fcntl(VALUE io, VALUE req, VALUE arg)
{
    int cmd = NUM2INT(req);
    rb_io_t *fptr;
    long narg;
    int retval;

    narg = setup_narg(cmd, &arg, 0);
    GetOpenFile(io, fptr);
    retval = do_fcntl(fptr->fd, cmd, narg);
    if (retval < 0) rb_sys_fail_path(fptr->pathv);
    if (RB_TYPE_P(arg, T_STRING)) {
	char *ptr;
	long slen;
	RSTRING_GETMEM(arg, ptr, slen);
	if (ptr[slen-1] != 17)
	    rb_raise(rb_eArgError, "return value overflowed string");
	ptr[slen-1] = '\0';
    }

    return INT2NUM(retval);
}

/*
 *  call-seq:
 *     ios.fcntl(integer_cmd, arg)    -> integer
 *
 *  Provides a mechanism for issuing low-level commands to control or
 *  query file-oriented I/O streams. Arguments and results are platform
 *  dependent. If <i>arg</i> is a number, its value is passed
 *  directly. If it is a string, it is interpreted as a binary sequence
 *  of bytes (<code>Array#pack</code> might be a useful way to build this
 *  string). On Unix platforms, see <code>fcntl(2)</code> for details.
 *  Not implemented on all platforms.
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
 *     syscall(num [, args...])   -> integer
 *
 *  Calls the operating system function identified by _num_ and
 *  returns the result of the function or raises SystemCallError if
 *  it failed.
 *
 *  Arguments for the function can follow _num_. They must be either
 *  +String+ objects or +Integer+ objects. A +String+ object is passed
 *  as a pointer to the byte sequence. An +Integer+ object is passed
 *  as an integer whose bit size is same as a pointer.
 *  Up to nine parameters may be passed (14 on the Atari-ST).
 *
 *  The function identified by _num_ is system
 *  dependent. On some Unix systems, the numbers may be obtained from a
 *  header file called <code>syscall.h</code>.
 *
 *     syscall 4, 1, "hello\n", 6   # '4' is write(2) on our box
 *
 *  <em>produces:</em>
 *
 *     hello
 *
 *
 *  Calling +syscall+ on a platform which does not have any way to
 *  an arbitrary system function just fails with NotImplementedError.
 *
 * Note::
 *   +syscall+ is essentially unsafe and unportable. Feel free to shoot your foot.
 *   DL (Fiddle) library is preferred for safer and a bit more portable programming.
 */

static VALUE
rb_f_syscall(int argc, VALUE *argv)
{
#ifdef atarist
    VALUE arg[13]; /* yes, we really need that many ! */
#else
    VALUE arg[8];
#endif
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
	rb_warning("We plan to remove a syscall function at future release. DL(Fiddle) provides safer alternative.");
    }

    if (argc == 0)
	rb_raise(rb_eArgError, "too few arguments for syscall");
    if (argc > numberof(arg))
	rb_raise(rb_eArgError, "too many arguments for syscall");
    num = NUM2SYSCALLID(argv[0]); ++argv;
    for (i = argc - 1; i--; ) {
	VALUE v = rb_check_string_type(argv[i]);

	if (!NIL_P(v)) {
	    SafeStringValue(v);
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
#ifdef atarist
      case 9:
	retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7]);
	break;
      case 10:
	retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8]);
	break;
      case 11:
	retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9]);
	break;
      case 12:
	retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9], arg[10]);
	break;
      case 13:
	retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9], arg[10], arg[11]);
	break;
      case 14:
	retval = SYSCALL(num, arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9], arg[10], arg[11], arg[12]);
        break;
#endif
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
 *     IO.pipe                             ->  [read_io, write_io]
 *     IO.pipe(ext_enc)                    ->  [read_io, write_io]
 *     IO.pipe("ext_enc:int_enc" [, opt])  ->  [read_io, write_io]
 *     IO.pipe(ext_enc, int_enc [, opt])   ->  [read_io, write_io]
 *
 *     IO.pipe(...) {|read_io, write_io| ... }
 *
 *  Creates a pair of pipe endpoints (connected to each other) and
 *  returns them as a two-element array of <code>IO</code> objects:
 *  <code>[</code> <i>read_io</i>, <i>write_io</i> <code>]</code>.
 *
 *  If a block is given, the block is called and
 *  returns the value of the block.
 *  <i>read_io</i> and <i>write_io</i> are sent to the block as arguments.
 *  If read_io and write_io are not closed when the block exits, they are closed.
 *  i.e. closing read_io and/or write_io doesn't cause an error.
 *
 *  Not available on all platforms.
 *
 *  If an encoding (encoding name or encoding object) is specified as an optional argument,
 *  read string from pipe is tagged with the encoding specified.
 *  If the argument is a colon separated two encoding names "A:B",
 *  the read string is converted from encoding A (external encoding)
 *  to encoding B (internal encoding), then tagged with B.
 *  If two optional arguments are specified, those must be
 *  encoding objects or encoding names,
 *  and the first one is the external encoding,
 *  and the second one is the internal encoding.
 *  If the external encoding and the internal encoding is specified,
 *  optional hash argument specify the conversion option.
 *
 *  In the example below, the two processes close the ends of the pipe
 *  that they are not using. This is not just a cosmetic nicety. The
 *  read end of a pipe will not generate an end of file condition if
 *  there are any writers with the pipe still open. In the case of the
 *  parent process, the <code>rd.read</code> will never return if it
 *  does not first issue a <code>wr.close</code>.
 *
 *     rd, wr = IO.pipe
 *
 *     if fork
 *       wr.close
 *       puts "Parent got: <#{rd.read}>"
 *       rd.close
 *       Process.wait
 *     else
 *       rd.close
 *       puts "Sending message to parent"
 *       wr.write "Hi Dad"
 *       wr.close
 *     end
 *
 *  <em>produces:</em>
 *
 *     Sending message to parent
 *     Parent got: <Hi Dad>
 */

static VALUE
rb_io_s_pipe(int argc, VALUE *argv, VALUE klass)
{
    int pipes[2], state;
    VALUE r, w, args[3], v1, v2;
    VALUE opt;
    rb_io_t *fptr, *fptr2;
    struct io_encoding_set_args ies_args;
    int fmode = 0;
    VALUE ret;

    argc = rb_scan_args(argc, argv, "02:", &v1, &v2, &opt);
    if (rb_pipe(pipes) == -1)
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
#if DEFAULT_TEXTMODE
    if ((fptr->mode & FMODE_TEXTMODE) && (fmode & FMODE_BINMODE)) {
	fptr->mode &= ~FMODE_TEXTMODE;
	setmode(fptr->fd, O_BINARY);
    }
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
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
open_key_args(int argc, VALUE *argv, VALUE opt, struct foreach_arg *arg)
{
    VALUE path, v;

    path = *argv++;
    argc--;
    FilePathValue(path);
    arg->io = 0;
    arg->argc = argc;
    arg->argv = argv;
    if (NIL_P(opt)) {
	arg->io = rb_io_open(path, INT2NUM(O_RDONLY), INT2FIX(0666), Qnil);
	return;
    }
    v = rb_hash_aref(opt, sym_open_args);
    if (!NIL_P(v)) {
	VALUE args;
	long n;

	v = rb_convert_type(v, T_ARRAY, "Array", "to_ary");
	n = RARRAY_LEN(v) + 1;
#if SIZEOF_LONG > SIZEOF_INT
	if (n > INT_MAX) {
	    rb_raise(rb_eArgError, "too many arguments");
	}
#endif
	args = rb_ary_tmp_new(n);
	rb_ary_push(args, path);
	rb_ary_concat(args, v);
	arg->io = rb_io_open_with_args((int)n, RARRAY_CONST_PTR(args));
	rb_ary_clear(args);	/* prevent from GC */
	return;
    }
    arg->io = rb_io_open(path, Qnil, Qnil, opt);
}

static VALUE
io_s_foreach(struct foreach_arg *arg)
{
    VALUE str;

    while (!NIL_P(str = rb_io_gets_m(arg->argc, arg->argv, arg->io))) {
	rb_yield(str);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     IO.foreach(name, sep=$/ [, open_args]) {|line| block }     -> nil
 *     IO.foreach(name, limit [, open_args]) {|line| block }      -> nil
 *     IO.foreach(name, sep, limit [, open_args]) {|line| block } -> nil
 *     IO.foreach(...)                                            -> an_enumerator
 *
 *  Executes the block for every line in the named I/O port, where lines
 *  are separated by <em>sep</em>.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     IO.foreach("testfile") {|x| print "GOT ", x }
 *
 *  <em>produces:</em>
 *
 *     GOT This is line one
 *     GOT This is line two
 *     GOT This is line three
 *     GOT And so on...
 *
 *  If the last argument is a hash, it's the keyword argument to open.
 *  See <code>IO.read</code> for detail.
 *
 */

static VALUE
rb_io_s_foreach(int argc, VALUE *argv, VALUE self)
{
    VALUE opt;
    int orig_argc = argc;
    struct foreach_arg arg;

    argc = rb_scan_args(argc, argv, "13:", NULL, NULL, NULL, NULL, &opt);
    RETURN_ENUMERATOR(self, orig_argc, argv);
    open_key_args(argc, argv, opt, &arg);
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(io_s_foreach, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
io_s_readlines(struct foreach_arg *arg)
{
    return rb_io_readlines(arg->argc, arg->argv, arg->io);
}

/*
 *  call-seq:
 *     IO.readlines(name, sep=$/ [, open_args])     -> array
 *     IO.readlines(name, limit [, open_args])      -> array
 *     IO.readlines(name, sep, limit [, open_args]) -> array
 *
 *  Reads the entire file specified by <i>name</i> as individual
 *  lines, and returns those lines in an array. Lines are separated by
 *  <i>sep</i>.
 *
 *     a = IO.readlines("testfile")
 *     a[0]   #=> "This is line one\n"
 *
 *  If the last argument is a hash, it's the keyword argument to open.
 *  See <code>IO.read</code> for detail.
 *
 */

static VALUE
rb_io_s_readlines(int argc, VALUE *argv, VALUE io)
{
    VALUE opt;
    struct foreach_arg arg;

    argc = rb_scan_args(argc, argv, "13:", NULL, NULL, NULL, NULL, &opt);
    open_key_args(argc, argv, opt, &arg);
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(io_s_readlines, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
io_s_read(struct foreach_arg *arg)
{
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
 *     IO.read(name, [length [, offset]] [, opt] )   -> string
 *
 *  Opens the file, optionally seeks to the given +offset+, then returns
 *  +length+ bytes (defaulting to the rest of the file).  <code>read</code>
 *  ensures the file is closed before returning.
 *
 *  === Options
 *
 *  The options hash accepts the following keys:
 *
 *  encoding::
 *    string or encoding
 *
 *    Specifies the encoding of the read string.  +encoding:+ will be ignored
 *    if +length+ is specified.  See Encoding.aliases for possible encodings.
 *
 *  mode::
 *    string
 *
 *    Specifies the mode argument for open().  It must start with an "r"
 *    otherwise it will cause an error. See IO.new for the list of possible
 *    modes.
 *
 *  open_args::
 *    array of strings
 *
 *    Specifies arguments for open() as an array.  This key can not be used
 *    in combination with either +encoding:+ or +mode:+.
 *
 *  Examples:
 *
 *    IO.read("testfile")              #=> "This is line one\nThis is line two\nThis is line three\nAnd so on...\n"
 *    IO.read("testfile", 20)          #=> "This is line one\nThi"
 *    IO.read("testfile", 20, 10)      #=> "ne one\nThis is line "
 *    IO.read("binfile", mode: "rb")   #=> "\xF7\x00\x00\x0E\x12"
 */

static VALUE
rb_io_s_read(int argc, VALUE *argv, VALUE io)
{
    VALUE opt, offset;
    struct foreach_arg arg;

    argc = rb_scan_args(argc, argv, "13:", NULL, NULL, &offset, NULL, &opt);
    open_key_args(argc, argv, opt, &arg);
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
 *     IO.binread(name, [length [, offset]] )   -> string
 *
 *  Opens the file, optionally seeks to the given <i>offset</i>, then returns
 *  <i>length</i> bytes (defaulting to the rest of the file).
 *  <code>binread</code> ensures the file is closed before returning.
 *  The open mode would be "rb:ASCII-8BIT".
 *
 *     IO.binread("testfile")           #=> "This is line one\nThis is line two\nThis is line three\nAnd so on...\n"
 *     IO.binread("testfile", 20)       #=> "This is line one\nThi"
 *     IO.binread("testfile", 20, 10)   #=> "ne one\nThis is line "
 */

static VALUE
rb_io_s_binread(int argc, VALUE *argv, VALUE io)
{
    VALUE offset;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "12", NULL, NULL, &offset);
    FilePathValue(argv[0]);
    arg.io = rb_io_open(argv[0], rb_str_new_cstr("rb:ASCII-8BIT"), Qnil, Qnil);
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
io_s_write0(struct write_arg *arg)
{
    return io_write(arg->io,arg->str,arg->nosync);
}

static VALUE
io_s_write(int argc, VALUE *argv, int binary)
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
    open_key_args(argc,argv,opt,&arg);

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
 *     IO.write(name, string, [offset] )   => fixnum
 *     IO.write(name, string, [offset], open_args )   => fixnum
 *
 *  Opens the file, optionally seeks to the given <i>offset</i>, writes
 *  <i>string</i>, then returns the length written.
 *  <code>write</code> ensures the file is closed before returning.
 *  If <i>offset</i> is not given, the file is truncated.  Otherwise,
 *  it is not truncated.
 *
 *  If the last argument is a hash, it specifies option for internal
 *  open().  The key would be the following.  open_args: is exclusive
 *  to others.
 *
 *   encoding: string or encoding
 *
 *    specifies encoding of the read string.  encoding will be ignored
 *    if length is specified.
 *
 *   mode: string
 *
 *    specifies mode argument for open().  it should start with "w" or "a" or "r+"
 *    otherwise it would cause error.
 *
 *   perm: fixnum
 *
 *    specifies perm argument for open().
 *
 *   open_args: array
 *
 *    specifies arguments for open() as an array.
 *
 *     IO.write("testfile", "0123456789", 20) # => 10
 *     # File could contain:  "This is line one\nThi0123456789two\nThis is line three\nAnd so on...\n"
 *     IO.write("testfile", "0123456789")      #=> 10
 *     # File would now read: "0123456789"
 */

static VALUE
rb_io_s_write(int argc, VALUE *argv, VALUE io)
{
    return io_s_write(argc, argv, 0);
}

/*
 *  call-seq:
 *     IO.binwrite(name, string, [offset] )   => fixnum
 *     IO.binwrite(name, string, [offset], open_args )   => fixnum
 *
 *  Same as <code>IO.write</code> except opening the file in binary mode
 *  and ASCII-8BIT encoding ("wb:ASCII-8BIT").
 *
 */

static VALUE
rb_io_s_binwrite(int argc, VALUE *argv, VALUE io)
{
    return io_s_write(argc, argv, 1);
}

struct copy_stream_struct {
    VALUE src;
    VALUE dst;
    off_t copy_length; /* (off_t)-1 if not specified */
    off_t src_offset; /* (off_t)-1 if not specified */

    int src_fd;
    int dst_fd;
    int close_src;
    int close_dst;
    off_t total;
    const char *syserr;
    int error_no;
    const char *notimp;
    rb_fdset_t fds;
    VALUE th;
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

/* non-Linux poll may not work on all FDs */
#if defined(HAVE_POLL) && defined(__linux__)
#  define USE_POLL 1
#  define IOWAIT_SYSCALL "poll"
#else
#  define IOWAIT_SYSCALL "select"
#  define USE_POLL 0
#endif

#if USE_POLL
static int
nogvl_wait_for_single_fd(int fd, short events)
{
    struct pollfd fds;

    fds.fd = fd;
    fds.events = events;

    return poll(&fds, 1, 0);
}

static int
maygvl_copy_stream_wait_read(int has_gvl, struct copy_stream_struct *stp)
{
    int ret;

    do {
	if (has_gvl) {
	    ret = rb_wait_for_single_fd(stp->src_fd, RB_WAITFD_IN, NULL);
	}
	else {
	    ret = nogvl_wait_for_single_fd(stp->src_fd, POLLIN);
	}
    } while (ret == -1 && maygvl_copy_stream_continue_p(has_gvl, stp));

    if (ret == -1) {
        stp->syserr = "poll";
        stp->error_no = errno;
        return -1;
    }
    return 0;
}
#else /* !USE_POLL */
static int
maygvl_select(int has_gvl, int n, rb_fdset_t *rfds, rb_fdset_t *wfds, rb_fdset_t *efds, struct timeval *timeout)
{
    if (has_gvl)
        return rb_thread_fd_select(n, rfds, wfds, efds, timeout);
    else
        return rb_fd_select(n, rfds, wfds, efds, timeout);
}

static int
maygvl_copy_stream_wait_read(int has_gvl, struct copy_stream_struct *stp)
{
    int ret;

    do {
	rb_fd_zero(&stp->fds);
	rb_fd_set(stp->src_fd, &stp->fds);
        ret = maygvl_select(has_gvl, rb_fd_max(&stp->fds), &stp->fds, NULL, NULL, NULL);
    } while (ret == -1 && maygvl_copy_stream_continue_p(has_gvl, stp));

    if (ret == -1) {
        stp->syserr = "select";
        stp->error_no = errno;
        return -1;
    }
    return 0;
}
#endif /* !USE_POLL */

static int
nogvl_copy_stream_wait_write(struct copy_stream_struct *stp)
{
    int ret;

    do {
#if USE_POLL
	ret = nogvl_wait_for_single_fd(stp->dst_fd, POLLOUT);
#else
	rb_fd_zero(&stp->fds);
	rb_fd_set(stp->dst_fd, &stp->fds);
        ret = rb_fd_select(rb_fd_max(&stp->fds), NULL, &stp->fds, NULL, NULL);
#endif
    } while (ret == -1 && maygvl_copy_stream_continue_p(0, stp));

    if (ret == -1) {
        stp->syserr = IOWAIT_SYSCALL;
        stp->error_no = errno;
        return -1;
    }
    return 0;
}

#ifdef HAVE_SENDFILE

# ifdef __linux__
#  define USE_SENDFILE

#  ifdef HAVE_SYS_SENDFILE_H
#   include <sys/sendfile.h>
#  endif

static ssize_t
simple_sendfile(int out_fd, int in_fd, off_t *offset, off_t count)
{
    return sendfile(out_fd, in_fd, offset, (size_t)count);
}

# elif 0 /* defined(__FreeBSD__) || defined(__DragonFly__) */ || defined(__APPLE__)
/* This runs on FreeBSD8.1 r30210, but sendfiles blocks its execution
 * without cpuset -l 0.
 */
#  define USE_SENDFILE

static ssize_t
simple_sendfile(int out_fd, int in_fd, off_t *offset, off_t count)
{
    int r;
    off_t pos = offset ? *offset : lseek(in_fd, 0, SEEK_CUR);
    off_t sbytes;
#  ifdef __APPLE__
    r = sendfile(in_fd, out_fd, pos, &count, NULL, 0);
    sbytes = count;
#  else
    r = sendfile(in_fd, out_fd, pos, (size_t)count, NULL, &sbytes, 0);
#  endif
    if (r != 0 && sbytes == 0) return -1;
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
    struct stat src_stat, dst_stat;
    ssize_t ss;
    int ret;

    off_t copy_length;
    off_t src_offset;
    int use_pread;

    ret = fstat(stp->src_fd, &src_stat);
    if (ret == -1) {
        stp->syserr = "fstat";
        stp->error_no = errno;
        return -1;
    }
    if (!S_ISREG(src_stat.st_mode))
        return 0;

    ret = fstat(stp->dst_fd, &dst_stat);
    if (ret == -1) {
        stp->syserr = "fstat";
        stp->error_no = errno;
        return -1;
    }
#ifndef __linux__
    if ((dst_stat.st_mode & S_IFMT) != S_IFSOCK)
	return 0;
#endif

    src_offset = stp->src_offset;
    use_pread = src_offset != (off_t)-1;

    copy_length = stp->copy_length;
    if (copy_length == (off_t)-1) {
        if (use_pread)
            copy_length = src_stat.st_size - src_offset;
        else {
            off_t cur;
            errno = 0;
            cur = lseek(stp->src_fd, 0, SEEK_CUR);
            if (cur == (off_t)-1 && errno) {
                stp->syserr = "lseek";
                stp->error_no = errno;
                return -1;
            }
            copy_length = src_stat.st_size - cur;
        }
    }

  retry_sendfile:
# if SIZEOF_OFF_T > SIZEOF_SIZE_T
    /* we are limited by the 32-bit ssize_t return value on 32-bit */
    ss = (copy_length > (off_t)SSIZE_MAX) ? SSIZE_MAX : (ssize_t)copy_length;
# else
    ss = (ssize_t)copy_length;
# endif
    if (use_pread) {
        ss = simple_sendfile(stp->dst_fd, stp->src_fd, &src_offset, ss);
    }
    else {
        ss = simple_sendfile(stp->dst_fd, stp->src_fd, NULL, ss);
    }
    if (0 < ss) {
        stp->total += ss;
        copy_length -= ss;
        if (0 < copy_length) {
            goto retry_sendfile;
        }
    }
    if (ss == -1) {
	if (maygvl_copy_stream_continue_p(0, stp))
	    goto retry_sendfile;
        switch (errno) {
	  case EINVAL:
#ifdef ENOSYS
	  case ENOSYS:
#endif
            return 0;
	  case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
#ifndef __linux__
           /*
            * Linux requires stp->src_fd to be a mmap-able (regular) file,
            * select() reports regular files to always be "ready", so
            * there is no need to select() on it.
            * Other OSes may have the same limitation for sendfile() which
            * allow us to bypass maygvl_copy_stream_wait_read()...
            */
            if (maygvl_copy_stream_wait_read(0, stp) == -1)
                return -1;
#endif
            if (nogvl_copy_stream_wait_write(stp) == -1)
                return -1;
            goto retry_sendfile;
        }
        stp->syserr = "sendfile";
        stp->error_no = errno;
        return -1;
    }
    return 1;
}
#endif

static ssize_t
maygvl_read(int has_gvl, int fd, void *buf, size_t count)
{
    if (has_gvl)
        return rb_read_internal(fd, buf, count);
    else
        return read(fd, buf, count);
}

static ssize_t
maygvl_copy_stream_read(int has_gvl, struct copy_stream_struct *stp, char *buf, size_t len, off_t offset)
{
    ssize_t ss;
  retry_read:
    if (offset == (off_t)-1) {
        ss = maygvl_read(has_gvl, stp->src_fd, buf, len);
    }
    else {
#ifdef HAVE_PREAD
        ss = pread(stp->src_fd, buf, len, offset);
#else
        stp->notimp = "pread";
        return -1;
#endif
    }
    if (ss == 0) {
        return 0;
    }
    if (ss == -1) {
	if (maygvl_copy_stream_continue_p(has_gvl, stp))
	    goto retry_read;
        switch (errno) {
	  case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
            if (maygvl_copy_stream_wait_read(has_gvl, stp) == -1)
                return -1;
            goto retry_read;
#ifdef ENOSYS
	  case ENOSYS:
            stp->notimp = "pread";
            return -1;
#endif
        }
        stp->syserr = offset == (off_t)-1 ?  "read" : "pread";
        stp->error_no = errno;
        return -1;
    }
    return ss;
}

static int
nogvl_copy_stream_write(struct copy_stream_struct *stp, char *buf, size_t len)
{
    ssize_t ss;
    int off = 0;
    while (len) {
        ss = write(stp->dst_fd, buf+off, len);
        if (ss == -1) {
	    if (maygvl_copy_stream_continue_p(0, stp))
		continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                if (nogvl_copy_stream_wait_write(stp) == -1)
                    return -1;
                continue;
            }
            stp->syserr = "write";
            stp->error_no = errno;
            return -1;
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
    off_t copy_length;
    int use_eof;
    off_t src_offset;
    int use_pread;

    copy_length = stp->copy_length;
    use_eof = copy_length == (off_t)-1;
    src_offset = stp->src_offset;
    use_pread = src_offset != (off_t)-1;

    if (use_pread && stp->close_src) {
        off_t r;
	errno = 0;
        r = lseek(stp->src_fd, src_offset, SEEK_SET);
        if (r == (off_t)-1 && errno) {
            stp->syserr = "lseek";
            stp->error_no = errno;
            return;
        }
        src_offset = (off_t)-1;
        use_pread = 0;
    }

    while (use_eof || 0 < copy_length) {
        if (!use_eof && copy_length < (off_t)sizeof(buf)) {
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
            ss = maygvl_copy_stream_read(0, stp, buf, len, (off_t)-1);
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
#ifdef USE_SENDFILE
    int ret;
#endif

#ifdef USE_SENDFILE
    ret = nogvl_copy_stream_sendfile(stp);
    if (ret != 0)
        goto finish; /* error or success */
#endif

    nogvl_copy_stream_read_write(stp);

#ifdef USE_SENDFILE
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
    off_t rest = stp->copy_length;
    off_t off = stp->src_offset;
    ID read_method = id_readpartial;

    if (stp->src_fd == -1) {
	if (!rb_respond_to(stp->src, read_method)) {
	    read_method = id_read;
	}
    }

    while (1) {
        long numwrote;
        long l;
        if (stp->copy_length == (off_t)-1) {
            l = buflen;
        }
        else {
            if (rest == 0)
                break;
            l = buflen < rest ? buflen : (long)rest;
        }
        if (stp->src_fd == -1) {
            VALUE rc = rb_funcall(stp->src, read_method, 2, INT2FIX(l), buf);

            if (read_method == id_read && NIL_P(rc))
                break;
        }
        else {
            ssize_t ss;
            rb_str_resize(buf, buflen);
            ss = maygvl_copy_stream_read(1, stp, RSTRING_PTR(buf), l, off);
            rb_str_resize(buf, ss > 0 ? ss : 0);
            if (ss == -1)
                return Qnil;
            if (ss == 0)
                rb_eof_error();
            if (off != (off_t)-1)
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
    if (stp->src_fd == -1 && stp->src_offset != (off_t)-1) {
	rb_raise(rb_eArgError, "cannot specify src_offset for non-IO");
    }
    rb_rescue2(copy_stream_fallback_body, (VALUE)stp,
               (VALUE (*) (ANYARGS))0, (VALUE)0,
               rb_eEOFError, (VALUE)0);
    return Qnil;
}

static VALUE
copy_stream_body(VALUE arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;
    VALUE src_io = stp->src, dst_io = stp->dst;
    rb_io_t *src_fptr = 0, *dst_fptr = 0;
    int src_fd, dst_fd;
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
	src_fd = -1;
    }
    else {
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
	GetOpenFile(src_io, src_fptr);
	rb_io_check_byte_readable(src_fptr);
	src_fd = src_fptr->fd;
    }
    stp->src_fd = src_fd;

    if (dst_io == argf ||
	!(RB_TYPE_P(dst_io, T_FILE) ||
	  RB_TYPE_P(dst_io, T_STRING) ||
	  rb_respond_to(dst_io, rb_intern("to_path")))) {
	dst_fd = -1;
    }
    else {
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
	GetOpenFile(dst_io, dst_fptr);
	rb_io_check_writable(dst_fptr);
	dst_fd = dst_fptr->fd;
    }
    stp->dst_fd = dst_fd;

#ifdef O_BINARY
    if (src_fptr)
	SET_BINARY_MODE_WITH_SEEK_CUR(src_fptr);
#endif
    if (dst_fptr)
	io_ascii8bit_binmode(dst_fptr);

    if (stp->src_offset == (off_t)-1 && src_fptr && src_fptr->rbuf.len) {
        size_t len = src_fptr->rbuf.len;
        VALUE str;
        if (stp->copy_length != (off_t)-1 && stp->copy_length < (off_t)len) {
            len = (size_t)stp->copy_length;
        }
        str = rb_str_buf_new(len);
        rb_str_resize(str,len);
        read_buffered_data(RSTRING_PTR(str), len, src_fptr);
        if (dst_fptr) { /* IO or filename */
            if (io_binwrite(str, RSTRING_PTR(str), RSTRING_LEN(str), dst_fptr, 0) < 0)
                rb_sys_fail(0);
        }
        else /* others such as StringIO */
	    rb_io_write(dst_io, str);
        stp->total += len;
        if (stp->copy_length != (off_t)-1)
            stp->copy_length -= len;
    }

    if (dst_fptr && io_fflush(dst_fptr) < 0) {
	rb_raise(rb_eIOError, "flush failed");
    }

    if (stp->copy_length == 0)
        return Qnil;

    if (src_fd == -1 || dst_fd == -1) {
        return copy_stream_fallback(stp);
    }

    rb_fd_set(src_fd, &stp->fds);
    rb_fd_set(dst_fd, &stp->fds);

    rb_thread_call_without_gvl(nogvl_copy_stream_func, (void*)stp, RUBY_UBF_IO, 0);
    return Qnil;
}

static VALUE
copy_stream_finalize(VALUE arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;
    if (stp->close_src) {
        rb_io_close_m(stp->src);
    }
    if (stp->close_dst) {
        rb_io_close_m(stp->dst);
    }
    rb_fd_term(&stp->fds);
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
 *     IO.copy_stream(src, dst)
 *     IO.copy_stream(src, dst, copy_length)
 *     IO.copy_stream(src, dst, copy_length, src_offset)
 *
 *  IO.copy_stream copies <i>src</i> to <i>dst</i>.
 *  <i>src</i> and <i>dst</i> is either a filename or an IO.
 *
 *  This method returns the number of bytes copied.
 *
 *  If optional arguments are not given,
 *  the start position of the copy is
 *  the beginning of the filename or
 *  the current file offset of the IO.
 *  The end position of the copy is the end of file.
 *
 *  If <i>copy_length</i> is given,
 *  No more than <i>copy_length</i> bytes are copied.
 *
 *  If <i>src_offset</i> is given,
 *  it specifies the start position of the copy.
 *
 *  When <i>src_offset</i> is specified and
 *  <i>src</i> is an IO,
 *  IO.copy_stream doesn't move the current file offset.
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

    if (NIL_P(length))
        st.copy_length = (off_t)-1;
    else
        st.copy_length = NUM2OFFT(length);

    if (NIL_P(src_offset))
        st.src_offset = (off_t)-1;
    else
        st.src_offset = NUM2OFFT(src_offset);

    rb_fd_init(&st.fds);
    rb_ensure(copy_stream_body, (VALUE)&st, copy_stream_finalize, (VALUE)&st);

    return OFFT2NUM(st.total);
}

/*
 *  call-seq:
 *     io.external_encoding   -> encoding
 *
 *  Returns the Encoding object that represents the encoding of the file.
 *  If io is write mode and no encoding is specified, returns <code>nil</code>.
 */

static VALUE
rb_io_external_encoding(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
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
 *     io.internal_encoding   -> encoding
 *
 *  Returns the Encoding of the internal string if conversion is
 *  specified.  Otherwise returns nil.
 */

static VALUE
rb_io_internal_encoding(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (!fptr->encs.enc2) return Qnil;
    return rb_enc_from_encoding(io_read_encoding(fptr));
}

/*
 *  call-seq:
 *     io.set_encoding(ext_enc)                -> io
 *     io.set_encoding("ext_enc:int_enc")      -> io
 *     io.set_encoding(ext_enc, int_enc)       -> io
 *     io.set_encoding("ext_enc:int_enc", opt) -> io
 *     io.set_encoding(ext_enc, int_enc, opt)  -> io
 *
 *  If single argument is specified, read string from io is tagged
 *  with the encoding specified.  If encoding is a colon separated two
 *  encoding names "A:B", the read string is converted from encoding A
 *  (external encoding) to encoding B (internal encoding), then tagged
 *  with B.  If two arguments are specified, those must be encoding
 *  objects or encoding names, and the first one is the external encoding, and the
 *  second one is the internal encoding.
 *  If the external encoding and the internal encoding is specified,
 *  optional hash argument specify the conversion option.
 */

static VALUE
rb_io_set_encoding(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    VALUE v1, v2, opt;

    if (!RB_TYPE_P(io, T_FILE)) {
        return rb_funcall2(io, id_set_encoding, argc, argv);
    }

    argc = rb_scan_args(argc, argv, "11:", &v1, &v2, &opt);
    GetOpenFile(io, fptr);
    io_encoding_set(fptr, v1, v2, opt);
    return io;
}

void
rb_stdio_set_default_encoding(void)
{
    extern VALUE rb_stdin, rb_stdout, rb_stderr;
    VALUE val = Qnil;

    rb_io_set_encoding(1, &val, rb_stdin);
    rb_io_set_encoding(1, &val, rb_stdout);
    rb_io_set_encoding(1, &val, rb_stderr);
}

/*
 *  call-seq:
 *     ARGF.external_encoding   -> encoding
 *
 *  Returns the external encoding for files read from +ARGF+ as an +Encoding+
 *  object. The external encoding is the encoding of the text as stored in a
 *  file. Contrast with +ARGF.internal_encoding+, which is the encoding used
 *  to represent this text within Ruby.
 *
 *  To set the external encoding use +ARGF.set_encoding+.
 *
 * For example:
 *
 *     ARGF.external_encoding  #=>  #<Encoding:UTF-8>
 *
 */
static VALUE
argf_external_encoding(VALUE argf)
{
    if (!RTEST(ARGF.current_file)) {
	return rb_enc_from_encoding(rb_default_external_encoding());
    }
    return rb_io_external_encoding(rb_io_check_io(ARGF.current_file));
}

/*
 *  call-seq:
 *     ARGF.internal_encoding   -> encoding
 *
 *  Returns the internal encoding for strings read from +ARGF+ as an
 *  +Encoding+ object.
 *
 *  If +ARGF.set_encoding+ has been called with two encoding names, the second
 *  is returned. Otherwise, if +Encoding.default_external+ has been set, that
 *  value is returned. Failing that, if a default external encoding was
 *  specified on the command-line, that value is used. If the encoding is
 *  unknown, nil is returned.
 */
static VALUE
argf_internal_encoding(VALUE argf)
{
    if (!RTEST(ARGF.current_file)) {
	return rb_enc_from_encoding(rb_default_external_encoding());
    }
    return rb_io_internal_encoding(rb_io_check_io(ARGF.current_file));
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
 *  optional +Hash+ argument can be used to adjust the conversion process. The
 *  structure of this hash is explained in the +String#encode+ documentation.
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
 *  Returns the current offset (in bytes) of the current file in +ARGF+.
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
 *     ARGF.seek(amount, whence=IO::SEEK_SET)  ->  0
 *
 *  Seeks to offset _amount_ (an +Integer+) in the +ARGF+ stream according to
 *  the value of _whence_. See +IO#seek+ for further details.
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
 *  Seeks to the position given by _position_ (in bytes) in +ARGF+.
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
 *  +ARGF.lineno+ to zero.
 *
 *     ARGF.readline   #=> "This is line one\n"
 *     ARGF.rewind     #=> 0
 *     ARGF.lineno     #=> 0
 *     ARGF.readline   #=> "This is line one\n"
 */
static VALUE
argf_rewind(VALUE argf)
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to rewind");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_rewind(ARGF.current_file);
}

/*
 *  call-seq:
 *     ARGF.fileno    -> fixnum
 *     ARGF.to_i      -> fixnum
 *
 *  Returns an integer representing the numeric file descriptor for
 *  the current file. Raises an +ArgumentError+ if there isn't a current file.
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
 *  Returns an +IO+ object representing the current file. This will be a
 *  +File+ object unless the current file is a stream such as STDIN.
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
 *  Returns true if the current file in +ARGF+ is at end of file, i.e. it has
 *  no data to read. The stream must be opened for reading or an +IOError+
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
 *  _length_ must be a non-negative integer or nil. If it is a positive
 *  integer, +read+ tries to read at most _length_ bytes. It returns nil
 *  if an EOF was encountered before anything could be read. Fewer than
 *  _length_ bytes may be returned if an EOF is encountered during the read.
 *
 *  If _length_ is omitted or is _nil_, it reads until EOF. A String is
 *  returned even if EOF is encountered before any data is read.
 *
 *  If _length_ is zero, it returns _""_.
 *
 *  If the optional _outbuf_ argument is present, it must reference a String,
 *  which will receive the data.
 *  The <i>outbuf</i> will contain only the received data after the method call
 *  even if it is not empty at the beginning.
 *
 * For example:
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
 *  Note that this method behaves like fread() function in C.  If you need the
 *  behavior like read(2) system call, consider +ARGF.readpartial+.
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
	    len -= slen;
	    argv[0] = INT2NUM(len);
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
 *  The <i>outbuf</i> will contain only the received data after the method call
 *  even if it is not empty at the beginning.
 *
 *  It raises <code>EOFError</code> on end of ARGF stream.
 *  Since ARGF stream is a concatenation of multiple files,
 *  internally EOF is occur for each file.
 *  ARGF.readpartial returns empty strings for EOFs except the last one and
 *  raises <code>EOFError</code> for the last one.
 *
 */

static VALUE
argf_readpartial(int argc, VALUE *argv, VALUE argf)
{
    return argf_getpartial(argc, argv, argf, Qnil, 0);
}

/*
 *  call-seq:
 *     ARGF.read_nonblock(maxlen)              -> string
 *     ARGF.read_nonblock(maxlen, outbuf)      -> outbuf
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

    rb_scan_args(argc, argv, "11", &length, &str);
    if (!NIL_P(str)) {
        StringValue(str);
        argv[1] = str;
    }

    if (!next_argv()) {
	if (!NIL_P(str)) {
	    rb_str_resize(str, 0);
	}
        rb_eof_error();
    }
    if (ARGF_GENERIC_INPUT_P()) {
	struct argf_call_arg arg;
	arg.argc = argc;
	arg.argv = argv;
	arg.argf = argf;
	tmp = rb_rescue2(argf_forward_call, (VALUE)&arg,
			 RUBY_METHOD_FUNC(0), Qnil, rb_eEOFError, (VALUE)0);
    }
    else {
        tmp = io_getpartial(argc, argv, ARGF.current_file, opts, nonblock);
    }
    if (NIL_P(tmp)) {
        if (ARGF.next_p == -1) {
	    return io_nonblock_eof(opts);
        }
        argf_close(argf);
        ARGF.next_p = 1;
        if (RARRAY_LEN(ARGF.argv) == 0) {
	    return io_nonblock_eof(opts);
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
 *  Reads the next character from +ARGF+ and returns it as a +String+. Returns
 *  +nil+ at the end of the stream.
 *
 *  +ARGF+ treats the files named on the command line as a single file created
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
	ch = rb_funcall3(ARGF.current_file, rb_intern("getc"), 0, 0);
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
 *     ARGF.getbyte  -> Fixnum or nil
 *
 *  Gets the next 8-bit byte (0..255) from +ARGF+. Returns +nil+ if called at
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
	ch = rb_funcall3(ARGF.current_file, rb_intern("getbyte"), 0, 0);
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
 *  Reads the next character from +ARGF+ and returns it as a +String+. Raises
 *  an +EOFError+ after the last character of the last file has been read.
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
	ch = rb_funcall3(ARGF.current_file, rb_intern("getc"), 0, 0);
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
 *     ARGF.readbyte  -> Fixnum
 *
 *  Reads the next 8-bit byte from ARGF and returns it as a +Fixnum+. Raises
 *  an +EOFError+ after the last byte of the last file has been read.
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

static void
argf_block_call(ID mid, int argc, VALUE *argv, VALUE argf)
{
    VALUE ret = rb_block_call(ARGF.current_file, mid, argc, argv, argf_block_call_i, argf);
    if (ret != Qundef) ARGF.next_p = 1;
}

/*
 *  call-seq:
 *     ARGF.each(sep=$/)            {|line| block }  -> ARGF
 *     ARGF.each(sep=$/,limit)      {|line| block }  -> ARGF
 *     ARGF.each(...)                                -> an_enumerator
 *
 *     ARGF.each_line(sep=$/)       {|line| block }  -> ARGF
 *     ARGF.each_line(sep=$/,limit) {|line| block }  -> ARGF
 *     ARGF.each_line(...)                           -> an_enumerator
 *
 *  Returns an enumerator which iterates over each line (separated by _sep_,
 *  which defaults to your platform's newline character) of each file in
 *  +ARGV+. If a block is supplied, each line in turn will be yielded to the
 *  block, otherwise an enumerator is returned.
 *  The optional _limit_ argument is a +Fixnum+ specifying the maximum
 *  length of each line; longer lines will be split according to this limit.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last line of the first file has been returned, the first line of the
 *  second file is returned. The +ARGF.filename+ and +ARGF.lineno+ methods can
 *  be used to determine the filename and line number, respectively, of the
 *  current line.
 *
 *  For example, the following code prints out each line of each named file
 *  prefixed with its line number, displaying the filename once per file:
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
	argf_block_call(rb_intern("each_line"), argc, argv, argf);
    }
    return argf;
}

/*
 *  This is a deprecated alias for <code>each_line</code>.
 */

static VALUE
argf_lines(int argc, VALUE *argv, VALUE argf)
{
    rb_warn("ARGF#lines is deprecated; use #each_line instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(argf, ID2SYM(rb_intern("each_line")), argc, argv);
    return argf_each_line(argc, argv, argf);
}

/*
 *  call-seq:
 *     ARGF.bytes     {|byte| block }  -> ARGF
 *     ARGF.bytes                      -> an_enumerator
 *
 *     ARGF.each_byte {|byte| block }  -> ARGF
 *     ARGF.each_byte                  -> an_enumerator
 *
 *  Iterates over each byte of each file in +ARGV+.
 *  A byte is returned as a +Fixnum+ in the range 0..255.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last byte of the first file has been returned, the first byte of the
 *  second file is returned. The +ARGF.filename+ method can be used to
 *  determine the filename of the current byte.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 * For example:
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
 *  This is a deprecated alias for <code>each_byte</code>.
 */

static VALUE
argf_bytes(VALUE argf)
{
    rb_warn("ARGF#bytes is deprecated; use #each_byte instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(argf, ID2SYM(rb_intern("each_byte")), 0, 0);
    return argf_each_byte(argf);
}

/*
 *  call-seq:
 *     ARGF.each_char  {|char| block }  -> ARGF
 *     ARGF.each_char                   -> an_enumerator
 *
 *  Iterates over each character of each file in +ARGF+.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last character of the first file has been returned, the first
 *  character of the second file is returned. The +ARGF.filename+ method can
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
 *  This is a deprecated alias for <code>each_char</code>.
 */

static VALUE
argf_chars(VALUE argf)
{
    rb_warn("ARGF#chars is deprecated; use #each_char instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(argf, ID2SYM(rb_intern("each_char")), 0, 0);
    return argf_each_char(argf);
}

/*
 *  call-seq:
 *     ARGF.each_codepoint  {|codepoint| block }  -> ARGF
 *     ARGF.each_codepoint                   -> an_enumerator
 *
 *  Iterates over each codepoint of each file in +ARGF+.
 *
 *  This method allows you to treat the files supplied on the command line as
 *  a single file consisting of the concatenation of each named file. After
 *  the last codepoint of the first file has been returned, the first
 *  codepoint of the second file is returned. The +ARGF.filename+ method can
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
 *  This is a deprecated alias for <code>each_codepoint</code>.
 */

static VALUE
argf_codepoints(VALUE argf)
{
    rb_warn("ARGF#codepoints is deprecated; use #each_codepoint instead");
    if (!rb_block_given_p())
	return rb_enumeratorize(argf, ID2SYM(rb_intern("each_codepoint")), 0, 0);
    return argf_each_codepoint(argf);
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
 *  Returns the current file as an +IO+ or +File+ object. #<IO:<STDIN>> is
 *  returned when the current file is STDIN.
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
 *  Puts +ARGF+ into binary mode. Once a stream is in binary mode, it cannot
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
 *  Returns true if +ARGF+ is being read in binary mode; false otherwise. (To
 *  enable binary mode use +ARGF.binmode+.
 *
 * For example:
 *
 *     ARGF.binmode?  #=> false
 *     ARGF.binmode
 *     ARGF.binmode?  #=> true
 */
static VALUE
argf_binmode_p(VALUE argf)
{
    return ARGF.binmode ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     ARGF.skip  -> ARGF
 *
 *  Sets the current file to the next file in ARGV. If there aren't any more
 *  files it has no effect.
 *
 * For example:
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
 *  Closes the current file and skips to the next in the stream. Trying to
 *  close a file that has already been closed causes an +IOError+ to be
 *  raised.
 *
 * For example:
 *
 *     $ ruby argf.rb foo bar
 *
 *     ARGF.filename  #=> "foo"
 *     ARGF.close
 *     ARGF.filename  #=> "bar"
 *     ARGF.close
 *     ARGF.close     #=> closed stream (IOError)
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
 *  +ARGF.close+ to actually close the current file.
 */
static VALUE
argf_closed(VALUE argf)
{
    next_argv();
    ARGF_FORWARD(0, 0);
    return rb_io_closed(ARGF.current_file);
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
 *  Returns the file extension appended to the names of modified files under
 *  inplace-edit mode. This value can be set using +ARGF.inplace_mode=+ or
 *  passing the +-i+ switch to the Ruby binary.
 */
static VALUE
argf_inplace_mode_get(VALUE argf)
{
    if (!ARGF.inplace) return Qnil;
    return rb_str_new2(ARGF.inplace);
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
 *  Sets the filename extension for in place editing mode to the given String.
 *  Each file being edited has this value appended to its filename. The
 *  modified file is saved under this new name.
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
 * Each line of _file.txt_ has the first occurrence of "foo" replaced with
 * "bar", then the new line is written out to _file.txt.bak_.
 */
static VALUE
argf_inplace_mode_set(VALUE argf, VALUE val)
{
    if (rb_safe_level() >= 1 && OBJ_TAINTED(val))
	rb_insecure_operation();

    if (!RTEST(val)) {
	if (ARGF.inplace) free(ARGF.inplace);
	ARGF.inplace = 0;
    }
    else {
	StringValue(val);
	if (ARGF.inplace) free(ARGF.inplace);
	ARGF.inplace = 0;
	ARGF.inplace = strdup(RSTRING_PTR(val));
    }
    return argf;
}

static void
opt_i_set(VALUE val, ID id, VALUE *var)
{
    argf_inplace_mode_set(*var, val);
}

const char *
ruby_get_inplace_mode(void)
{
    return ARGF.inplace;
}

void
ruby_set_inplace_mode(const char *suffix)
{
    if (ARGF.inplace) free(ARGF.inplace);
    ARGF.inplace = 0;
    if (suffix) ARGF.inplace = strdup(suffix);
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
 *     ARGF.write(string)   -> integer
 *
 *  Writes _string_ if inplace mode.
 */
static VALUE
argf_write(VALUE argf, VALUE str)
{
    return rb_io_write(argf_write_io(argf), str);
}

void
rb_readwrite_sys_fail(enum rb_io_wait_readwrite writable, const char *mesg)
{
    rb_readwrite_syserr_fail(writable, errno, mesg);
}

void
rb_readwrite_syserr_fail(enum rb_io_wait_readwrite writable, int n, const char *mesg)
{
    VALUE arg;
    arg = mesg ? rb_str_new2(mesg) : Qnil;
    if (writable == RB_IO_WAIT_WRITABLE) {
	switch (n) {
	  case EAGAIN:
	    rb_exc_raise(rb_class_new_instance(1, &arg, rb_eEAGAINWaitWritable));
	    break;
#if EAGAIN != EWOULDBLOCK
	  case EWOULDBLOCK:
	    rb_exc_raise(rb_class_new_instance(1, &arg, rb_eEWOULDBLOCKWaitWritable));
	    break;
#endif
	  case EINPROGRESS:
	    rb_exc_raise(rb_class_new_instance(1, &arg, rb_eEINPROGRESSWaitWritable));
	    break;
	  default:
	    rb_mod_sys_fail_str(rb_mWaitWritable, arg);
	}
    }
    else if (writable == RB_IO_WAIT_READABLE) {
	switch (n) {
	  case EAGAIN:
	    rb_exc_raise(rb_class_new_instance(1, &arg, rb_eEAGAINWaitReadable));
	    break;
#if EAGAIN != EWOULDBLOCK
	  case EWOULDBLOCK:
	    rb_exc_raise(rb_class_new_instance(1, &arg, rb_eEWOULDBLOCKWaitReadable));
	    break;
#endif
	  case EINPROGRESS:
	    rb_exc_raise(rb_class_new_instance(1, &arg, rb_eEINPROGRESSWaitReadable));
	    break;
	  default:
	    rb_mod_sys_fail_str(rb_mWaitReadable, arg);
	}
    }
    else {
	rb_bug("invalid read/write type passed to rb_readwrite_sys_fail: %d", writable);
    }
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
 * Note that some IO failures raise +SystemCallError+s and these are not
 * subclasses of IOError:
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
 * raises EOFError +EOFError+.
 *
 * +EOFError+ is a subclass of +IOError+.
 *
 *    file = File.open("/etc/hosts")
 *    file.read
 *    file.gets     #=> nil
 *    file.readline #=> EOFError: end of file reached
 */

/*
 * Document-class:  ARGF
 *
 * +ARGF+ is a stream designed for use in scripts that process files given as
 * command-line arguments or passed in via STDIN.
 *
 * The arguments passed to your script are stored in the +ARGV+ Array, one
 * argument per element. +ARGF+ assumes that any arguments that aren't
 * filenames have been removed from +ARGV+. For example:
 *
 *     $ ruby argf.rb --verbose file1 file2
 *
 *     ARGV  #=> ["--verbose", "file1", "file2"]
 *     option = ARGV.shift #=> "--verbose"
 *     ARGV  #=> ["file1", "file2"]
 *
 * You can now use +ARGF+ to work with a concatenation of each of these named
 * files. For instance, +ARGF.read+ will return the contents of _file1_
 * followed by the contents of _file2_.
 *
 * After a file in +ARGV+ has been read +ARGF+ removes it from the Array.
 * Thus, after all files have been read +ARGV+ will be empty.
 *
 * You can manipulate +ARGV+ yourself to control what +ARGF+ operates on. If
 * you remove a file from +ARGV+, it is ignored by +ARGF+; if you add files to
 * +ARGV+, they are treated as if they were named on the command line. For
 * example:
 *
 *     ARGV.replace ["file1"]
 *     ARGF.readlines # Returns the contents of file1 as an Array
 *     ARGV           #=> []
 *     ARGV.replace ["file2", "file3"]
 *     ARGF.read      # Returns the contents of file2 and file3
 *
 * If +ARGV+ is empty, +ARGF+ acts as if it contained STDIN, i.e. the data
 * piped to your script. For example:
 *
 *     $ echo "glark" | ruby -e 'p ARGF.read'
 *     "glark\n"
 */

/*
 *  The IO class is the basis for all input and output in Ruby.
 *  An I/O stream may be <em>duplexed</em> (that is, bidirectional), and
 *  so may use more than one native operating system stream.
 *
 *  Many of the examples in this section use the File class, the only standard
 *  subclass of IO. The two classes are closely associated.  Like the File
 *  class, the Socket library subclasses from IO (such as TCPSocket or
 *  UDPSocket).
 *
 *  The Kernel#open method can create an IO (or File) object for these types
 *  of arguments:
 *
 *  * A plain string represents a filename suitable for the underlying
 *    operating system.
 *
 *  * A string starting with <code>"|"</code> indicates a subprocess.
 *    The remainder of the string following the <code>"|"</code> is
 *    invoked as a process with appropriate input/output channels
 *    connected to it.
 *
 *  * A string equal to <code>"|-"</code> will create another Ruby
 *    instance as a subprocess.
 *
 *  The IO may be opened with different file modes (read-only, write-only) and
 *  encodings for proper conversion.  See IO.new for these options.  See
 *  Kernel#open for details of the various command formats described above.
 *
 *  IO.popen, the Open3 library, or  Process#spawn may also be used to
 *  communicate with subprocesses through an IO.
 *
 *  Ruby will convert pathnames between different operating system
 *  conventions if possible.  For instance, on a Windows system the
 *  filename <code>"/gumby/ruby/test.rb"</code> will be opened as
 *  <code>"\gumby\ruby\test.rb"</code>.  When specifying a Windows-style
 *  filename in a Ruby string, remember to escape the backslashes:
 *
 *    "c:\\gumby\\ruby\\test.rb"
 *
 *  Our examples here will use the Unix-style forward slashes;
 *  File::ALT_SEPARATOR can be used to get the platform-specific separator
 *  character.
 *
 *  The global constant ARGF (also accessible as $<) provides an
 *  IO-like stream which allows access to all files mentioned on the
 *  command line (or STDIN if no files are mentioned). ARGF#path and its alias
 *  ARGF#filename are provided to access the name of the file currently being
 *  read.
 *
 *  == io/console
 *
 *  The io/console extension provides methods for interacting with the
 *  console.  The console can be accessed from IO.console or the standard
 *  input/output/error IO objects.
 *
 *  Requiring io/console adds the following methods:
 *
 *  * IO::console
 *  * IO#raw
 *  * IO#raw!
 *  * IO#cooked
 *  * IO#cooked!
 *  * IO#getch
 *  * IO#echo=
 *  * IO#echo?
 *  * IO#noecho
 *  * IO#winsize
 *  * IO#winsize=
 *  * IO#iflush
 *  * IO#ioflush
 *  * IO#oflush
 *
 *  Example:
 *
 *    require 'io/console'
 *    rows, columns = $stdout.winsize
 *    puts "Your screen is #{columns} wide and #{rows} tall"
 */

void
Init_IO(void)
{
#undef rb_intern
#define rb_intern(str) rb_intern_const(str)

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

    id_write = rb_intern("write");
    id_read = rb_intern("read");
    id_getc = rb_intern("getc");
    id_flush = rb_intern("flush");
    id_readpartial = rb_intern("readpartial");
    id_set_encoding = rb_intern("set_encoding");

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

    rb_mWaitReadable = rb_define_module_under(rb_cIO, "WaitReadable");
    rb_mWaitWritable = rb_define_module_under(rb_cIO, "WaitWritable");
    rb_eEAGAINWaitReadable = rb_define_class_under(rb_cIO, "EAGAINWaitReadable", rb_eEAGAIN);
    rb_include_module(rb_eEAGAINWaitReadable, rb_mWaitReadable);
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
    rb_eEWOULDBLOCKWaitReadable = rb_define_class_under(rb_cIO, "EWOULDBLOCKWaitReadable", rb_eEWOULDBLOCK);
    rb_include_module(rb_eEWOULDBLOCKWaitReadable, rb_mWaitReadable);
    rb_eEWOULDBLOCKWaitWritable = rb_define_class_under(rb_cIO, "EWOULDBLOCKWaitWritable", rb_eEWOULDBLOCK);
    rb_include_module(rb_eEWOULDBLOCKWaitWritable, rb_mWaitWritable);
#endif
    rb_eEINPROGRESSWaitReadable = rb_define_class_under(rb_cIO, "EINPROGRESSWaitReadable", rb_eEINPROGRESS);
    rb_include_module(rb_eEINPROGRESSWaitReadable, rb_mWaitReadable);
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
    rb_define_hooked_variable("$,", &rb_output_fs, 0, rb_str_setter);

    rb_rs = rb_default_rs = rb_usascii_str_new2("\n");
    rb_gc_register_mark_object(rb_default_rs);
    rb_output_rs = Qnil;
    OBJ_FREEZE(rb_default_rs);	/* avoid modifying RS_default */
    rb_define_hooked_variable("$/", &rb_rs, 0, rb_str_setter);
    rb_define_hooked_variable("$-0", &rb_rs, 0, rb_str_setter);
    rb_define_hooked_variable("$\\", &rb_output_rs, 0, rb_str_setter);

    rb_define_virtual_variable("$_", rb_lastline_get, rb_lastline_set);

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
    rb_define_method(rb_cIO, "lines",  rb_io_lines, -1);
    rb_define_method(rb_cIO, "bytes",  rb_io_bytes, 0);
    rb_define_method(rb_cIO, "chars",  rb_io_chars, 0);
    rb_define_method(rb_cIO, "codepoints",  rb_io_codepoints, 0);

    rb_define_method(rb_cIO, "syswrite", rb_io_syswrite, 1);
    rb_define_method(rb_cIO, "sysread",  rb_io_sysread, -1);

    rb_define_method(rb_cIO, "fileno", rb_io_fileno, 0);
    rb_define_alias(rb_cIO, "to_i", "fileno");
    rb_define_method(rb_cIO, "to_io", rb_io_to_io, 0);

    rb_define_method(rb_cIO, "fsync",   rb_io_fsync, 0);
    rb_define_method(rb_cIO, "fdatasync",   rb_io_fdatasync, 0);
    rb_define_method(rb_cIO, "sync",   rb_io_sync, 0);
    rb_define_method(rb_cIO, "sync=",  rb_io_set_sync, 1);

    rb_define_method(rb_cIO, "lineno",   rb_io_lineno, 0);
    rb_define_method(rb_cIO, "lineno=",  rb_io_set_lineno, 1);

    rb_define_method(rb_cIO, "readlines",  rb_io_readlines, -1);

    /* for prelude.rb use only: */
    rb_define_private_method(rb_cIO, "__read_nonblock", io_read_nonblock, 3);
    rb_define_private_method(rb_cIO, "__write_nonblock", io_write_nonblock, 2);

    rb_define_method(rb_cIO, "readpartial",  io_readpartial, -1);
    rb_define_method(rb_cIO, "read",  io_read, -1);
    rb_define_method(rb_cIO, "write", io_write_m, 1);
    rb_define_method(rb_cIO, "gets",  rb_io_gets_m, -1);
    rb_define_method(rb_cIO, "readline",  rb_io_readline, -1);
    rb_define_method(rb_cIO, "getc",  rb_io_getc, 0);
    rb_define_method(rb_cIO, "getbyte",  rb_io_getbyte, 0);
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
    rb_define_method(rb_cIO, "closed?", rb_io_closed, 0);
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
    rb_define_method(rb_cIO, "inspect",  rb_io_inspect, 0);

    rb_define_method(rb_cIO, "external_encoding", rb_io_external_encoding, 0);
    rb_define_method(rb_cIO, "internal_encoding", rb_io_internal_encoding, 0);
    rb_define_method(rb_cIO, "set_encoding", rb_io_set_encoding, -1);

    rb_define_method(rb_cIO, "autoclose?", rb_io_autoclose_p, 0);
    rb_define_method(rb_cIO, "autoclose=", rb_io_set_autoclose, 1);

    rb_define_variable("$stdin", &rb_stdin);
    rb_stdin = prep_stdio(stdin, FMODE_READABLE, rb_cIO, "<STDIN>");
    rb_define_hooked_variable("$stdout", &rb_stdout, 0, stdout_setter);
    rb_stdout = prep_stdio(stdout, FMODE_WRITABLE, rb_cIO, "<STDOUT>");
    rb_define_hooked_variable("$stderr", &rb_stderr, 0, stdout_setter);
    rb_stderr = prep_stdio(stderr, FMODE_WRITABLE|FMODE_SYNC, rb_cIO, "<STDERR>");
    rb_define_hooked_variable("$>", &rb_stdout, 0, stdout_setter);
    orig_stdout = rb_stdout;
    rb_deferr = orig_stderr = rb_stderr;

    /* Holds the original stdin */
    rb_define_global_const("STDIN", rb_stdin);
    /* Holds the original stdout */
    rb_define_global_const("STDOUT", rb_stdout);
    /* Holds the original stderr */
    rb_define_global_const("STDERR", rb_stderr);

#if 0
    /* Hack to get rdoc to regard ARGF as a class: */
    rb_cARGF = rb_define_class("ARGF.class", rb_cObject);
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
    rb_define_method(rb_cARGF, "lines", argf_lines, -1);
    rb_define_method(rb_cARGF, "bytes", argf_bytes, 0);
    rb_define_method(rb_cARGF, "chars", argf_chars, 0);
    rb_define_method(rb_cARGF, "codepoints", argf_codepoints, 0);

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

    rb_define_method(rb_cARGF, "write", argf_write, 1);
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
    rb_define_hooked_variable("$*", &argf, argf_argv_getter, rb_gvar_readonly_setter);

#if defined (_WIN32) || defined(__CYGWIN__)
    atexit(pipe_atexit);
#endif

    Init_File();

    rb_define_method(rb_cFile, "initialize",  rb_file_initialize, -1);

    sym_mode = ID2SYM(rb_intern("mode"));
    sym_perm = ID2SYM(rb_intern("perm"));
    sym_flags = ID2SYM(rb_intern("flags"));
    sym_extenc = ID2SYM(rb_intern("external_encoding"));
    sym_intenc = ID2SYM(rb_intern("internal_encoding"));
    sym_encoding = ID2SYM(rb_id_encoding());
    sym_open_args = ID2SYM(rb_intern("open_args"));
    sym_textmode = ID2SYM(rb_intern("textmode"));
    sym_binmode = ID2SYM(rb_intern("binmode"));
    sym_autoclose = ID2SYM(rb_intern("autoclose"));
    sym_normal = ID2SYM(rb_intern("normal"));
    sym_sequential = ID2SYM(rb_intern("sequential"));
    sym_random = ID2SYM(rb_intern("random"));
    sym_willneed = ID2SYM(rb_intern("willneed"));
    sym_dontneed = ID2SYM(rb_intern("dontneed"));
    sym_noreuse = ID2SYM(rb_intern("noreuse"));
    sym_SET = ID2SYM(rb_intern("SET"));
    sym_CUR = ID2SYM(rb_intern("CUR"));
    sym_END = ID2SYM(rb_intern("END"));
#ifdef SEEK_DATA
    sym_DATA = ID2SYM(rb_intern("DATA"));
#endif
#ifdef SEEK_HOLE
    sym_HOLE = ID2SYM(rb_intern("HOLE"));
#endif
    sym_wait_readable = ID2SYM(rb_intern("wait_readable"));
    sym_wait_writable = ID2SYM(rb_intern("wait_writable"));
}
