/**********************************************************************

  io.c -

  $Author$
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/io.h"
#include "ruby/signal.h"
#include "vm_core.h"
#include <ctype.h>
#include <errno.h>

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

#if defined(MSDOS) || defined(__BOW__) || defined(__CYGWIN__) || defined(_WIN32) || defined(__human68k__) || defined(__EMX__) || defined(__BEOS__)
# define NO_SAFE_RENAME
#endif

#if defined(MSDOS) || defined(__CYGWIN__) || defined(_WIN32)
# define NO_LONG_FNAME
#endif

#if defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__DragonFly__) || defined(sun) || defined(_nec_ews)
# define USE_SETVBUF
#endif

#ifdef __QNXNTO__
#include "unix.h"
#endif

#include <sys/types.h>
#if defined(HAVE_SYS_IOCTL_H) && !defined(DJGPP) && !defined(_WIN32) && !defined(__human68k__)
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

#include <sys/stat.h>

/* EMX has sys/param.h, but.. */
#if defined(HAVE_SYS_PARAM_H) && !(defined(__EMX__) || defined(__HIUX_MPP__))
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

extern void Init_File(void);

#ifdef __BEOS__
# ifndef NOFILE
#  define NOFILE (OPEN_MAX)
# endif
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

VALUE rb_cIO;
VALUE rb_eEOFError;
VALUE rb_eIOError;

VALUE rb_stdin, rb_stdout, rb_stderr;
VALUE rb_deferr;		/* rescue VIM plugin */
static VALUE orig_stdout, orig_stderr;

VALUE rb_output_fs;
VALUE rb_rs;
VALUE rb_output_rs;
VALUE rb_default_rs;

static VALUE argf;

static ID id_write, id_read, id_getc, id_flush, id_encode, id_readpartial;
static VALUE sym_mode, sym_perm, sym_extenc, sym_intenc, sym_encoding, sym_open_args;

struct timeval rb_time_interval(VALUE);

struct argf {
    VALUE filename, current_file;
    int gets_lineno;
    int init_p, next_p;
    VALUE lineno;
    VALUE argv;
    char *inplace;
    int binmode;
    rb_encoding *enc, *enc2;
};

static int max_file_descriptor = NOFILE;
#define UPDATE_MAXFD(fd) \
    do { \
        if (max_file_descriptor < (fd)) max_file_descriptor = (fd); \
    } while (0)

#define argf_of(obj) (*(struct argf *)DATA_PTR(obj))
#define ARGF argf_of(argf)

#ifdef _STDIO_USES_IOSTREAM  /* GNU libc */
#  ifdef _IO_fpos_t
#    define STDIO_READ_DATA_PENDING(fp) ((fp)->_IO_read_ptr != (fp)->_IO_read_end)
#  else
#    define STDIO_READ_DATA_PENDING(fp) ((fp)->_gptr < (fp)->_egptr)
#  endif
#elif defined(FILE_COUNT)
#  define STDIO_READ_DATA_PENDING(fp) ((fp)->FILE_COUNT > 0)
#elif defined(FILE_READEND)
#  define STDIO_READ_DATA_PENDING(fp) ((fp)->FILE_READPTR < (fp)->FILE_READEND)
#elif defined(__BEOS__)
#  define STDIO_READ_DATA_PENDING(fp) (fp->_state._eof == 0)
#elif defined(__VMS)
#  define STDIO_READ_DATA_PENDING(fp) (((unsigned int)(*(fp))->_cnt) > 0)
#else
#  define STDIO_READ_DATA_PENDING(fp) (!feof(fp))
#endif

#if defined(__VMS)
#define fopen(file_spec, mode)  fopen(file_spec, mode, "rfm=stmlf")
#define open(file_spec, flags, mode)  open(file_spec, flags, mode, "rfm=stmlf")
#endif

#define GetWriteIO(io) rb_io_get_write_io(io)

#define READ_DATA_PENDING(fptr) ((fptr)->rbuf_len)
#define READ_DATA_PENDING_COUNT(fptr) ((fptr)->rbuf_len)
#define READ_DATA_PENDING_PTR(fptr) ((fptr)->rbuf+(fptr)->rbuf_off)
#define READ_DATA_BUFFERED(fptr) READ_DATA_PENDING(fptr)

#define READ_CHECK(fptr) do {\
    if (!READ_DATA_PENDING(fptr)) {\
	rb_thread_wait_fd((fptr)->fd);\
	rb_io_check_closed(fptr);\
     }\
} while(0)

#ifndef S_ISSOCK
#  ifdef _S_ISSOCK
#    define S_ISSOCK(m) _S_ISSOCK(m)
#  else
#    ifdef _S_IFSOCK
#      define S_ISSOCK(m) ((m & S_IFMT) == _S_IFSOCK)
#    else
#      ifdef S_IFSOCK
#	 define S_ISSOCK(m) ((m & S_IFMT) == S_IFSOCK)
#      endif
#    endif
#  endif
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
is_socket(int fd, const char *path)
{
    struct stat sbuf;
    if (fstat(fd, &sbuf) < 0)
        rb_sys_fail(path);
    return S_ISSOCK(sbuf.st_mode);
}
#endif

void
rb_eof_error(void)
{
    rb_raise(rb_eEOFError, "end of file reached");
}

VALUE
rb_io_taint_check(VALUE io)
{
    if (!OBJ_UNTRUSTED(io) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: operation on trusted IO");
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
	rb_raise(rb_eIOError, "closed stream");
    }
}

static int io_fflush(rb_io_t *);

VALUE
rb_io_get_io(VALUE io)
{
    return rb_convert_type(io, T_FILE, "IO", "to_io");
}

static VALUE
rb_io_check_io(VALUE io)
{
    return rb_check_convert_type(io, T_FILE, "IO", "to_io");
}

VALUE
rb_io_get_write_io(VALUE io)
{
    VALUE write_io;
    rb_io_check_initialized(RFILE(io)->fptr);
    write_io = RFILE(io)->fptr->tied_io_for_writing;
    if (write_io) {
        return write_io;
    }
    return io;
}

/*
 *  call-seq:
 *     IO.try_convert(obj) -> io or nil
 *
 *  Try to convert <i>obj</i> into an IO, using to_io method.
 *  Returns converted IO or nil if <i>obj</i> cannot be converted
 *  for any reason.
 *
 *     IO.try_convert(STDOUT)     # => STDOUT
 *     IO.try_convert("STDOUT")   # => nil
 */
static VALUE
rb_io_s_try_convert(VALUE dummy, VALUE io)
{
    return rb_io_check_io(io);
}

static void
io_unread(rb_io_t *fptr)
{
    off_t r;
    rb_io_check_closed(fptr);
    if (fptr->rbuf_len == 0 || fptr->mode & FMODE_DUPLEX)
        return;
    /* xxx: target position may be negative if buffer is filled by ungetc */
#if defined(_WIN32) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__) || defined(__EMX__)
    if (!(fptr->mode & FMODE_BINMODE)) {
	int len = fptr->rbuf_len;
	while (fptr->rbuf_len-- > 0) {
	    if (fptr->rbuf[fptr->rbuf_len] == '\n')
		++len;
	}
	r = lseek(fptr->fd, -len, SEEK_CUR);
    }
    else
#endif
    r = lseek(fptr->fd, -fptr->rbuf_len, SEEK_CUR);
    if (r < 0) {
        if (errno == ESPIPE)
            fptr->mode |= FMODE_DUPLEX;
        return;
    }
    fptr->rbuf_off = 0;
    fptr->rbuf_len = 0;
    return;
}

static rb_encoding *io_input_encoding(rb_io_t *fptr);

static void
io_ungetc(VALUE str, rb_io_t *fptr)
{
    int len = RSTRING_LEN(str);

    if (rb_enc_dummy_p(io_input_encoding(fptr))) {
	rb_raise(rb_eNotImpError, "ungetc against dummy encoding is not currently supported");
    }

    if (fptr->rbuf == NULL) {
        fptr->rbuf_off = 0;
        fptr->rbuf_len = 0;
	if (len > 8192)
	    fptr->rbuf_capa = len;
	else
	    fptr->rbuf_capa = 8192;
        fptr->rbuf = ALLOC_N(char, fptr->rbuf_capa);
    }
    if (fptr->rbuf_capa < len + fptr->rbuf_len) {
	rb_raise(rb_eIOError, "ungetc failed");
    }
    if (fptr->rbuf_off < len) {
        MEMMOVE(fptr->rbuf+fptr->rbuf_capa-fptr->rbuf_len,
                fptr->rbuf+fptr->rbuf_off,
                char, fptr->rbuf_len);
        fptr->rbuf_off = fptr->rbuf_capa-fptr->rbuf_len;
    }
    fptr->rbuf_off-=len;
    fptr->rbuf_len+=len;
    MEMMOVE(fptr->rbuf+fptr->rbuf_off, RSTRING_PTR(str), char, len);
}

static rb_io_t *
flush_before_seek(rb_io_t *fptr)
{
    io_fflush(fptr);
    io_unread(fptr);
    errno = 0;
    return fptr;
}

#define io_seek(fptr, ofs, whence) lseek(flush_before_seek(fptr)->fd, ofs, whence)
#define io_tell(fptr) lseek(flush_before_seek(fptr)->fd, 0, SEEK_CUR)

#ifndef SEEK_CUR
# define SEEK_SET 0
# define SEEK_CUR 1
# define SEEK_END 2
#endif

#define FMODE_SYNCWRITE (FMODE_SYNC|FMODE_WRITABLE)

void
rb_io_check_readable(rb_io_t *fptr)
{
    rb_io_check_closed(fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	rb_raise(rb_eIOError, "not opened for reading");
    }
    if (fptr->wbuf_len) {
        io_fflush(fptr);
    }
    if (fptr->tied_io_for_writing) {
	rb_io_t *wfptr;
	GetOpenFile(fptr->tied_io_for_writing, wfptr);
	io_fflush(wfptr);
    }
    if (!fptr->enc && fptr->fd == 0) {
	fptr->enc = rb_default_external_encoding();
    }
}

static rb_encoding*
io_read_encoding(rb_io_t *fptr)
{
    if (fptr->enc) {
	return fptr->enc;
    }
    return rb_default_external_encoding();
}

static rb_encoding*
io_input_encoding(rb_io_t *fptr)
{
    if (fptr->enc2) {
	return fptr->enc2;
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
    if (fptr->rbuf_len) {
        io_unread(fptr);
    }
}

int
rb_read_pending(FILE *fp)
{
    return STDIO_READ_DATA_PENDING(fp);
}

int
rb_io_read_pending(rb_io_t *fptr)
{
    return READ_DATA_PENDING(fptr);
}

void
rb_read_check(FILE *fp)
{
    if (!STDIO_READ_DATA_PENDING(fp)) {
	rb_thread_wait_fd(fileno(fp));
    }
}

void
rb_io_read_check(rb_io_t *fptr)
{
    if (!READ_DATA_PENDING(fptr)) {
	rb_thread_wait_fd(fptr->fd);
    }
    return;
}

static int
ruby_dup(int orig)
{
    int fd;

    fd = dup(orig);
    if (fd < 0) {
	if (errno == EMFILE || errno == ENFILE || errno == ENOMEM) {
	    rb_gc();
	    fd = dup(orig);
	}
	if (fd < 0) {
	    rb_sys_fail(0);
	}
    }
    return fd;
}

static VALUE
io_alloc(VALUE klass)
{
    NEWOBJ(io, struct RFile);
    OBJSETUP(io, klass, T_FILE);

    io->fptr = 0;

    return (VALUE)io;
}

#ifndef S_ISREG
#   define S_ISREG(m) ((m & S_IFMT) == S_IFREG)
#endif

static int
wsplit_p(rb_io_t *fptr)
{
#if defined(HAVE_FCNTL) && defined(F_GETFL) && defined(O_NONBLOCK)
    int r;
#endif

    if (!(fptr->mode & FMODE_WSPLIT_INITIALIZED)) {
        struct stat buf;
        if (fstat(fptr->fd, &buf) == 0 &&
            !S_ISREG(buf.st_mode)
#if defined(HAVE_FCNTL) && defined(F_GETFL) && defined(O_NONBLOCK)
            && (r = fcntl(fptr->fd, F_GETFL)) != -1 &&
            !(r & O_NONBLOCK)
#endif
            ) {
            fptr->mode |= FMODE_WSPLIT;
        }
        fptr->mode |= FMODE_WSPLIT_INITIALIZED;
    }
    return fptr->mode & FMODE_WSPLIT;
}

struct io_internal_struct {
    int fd;
    void *buf;
    size_t capa;
};

static VALUE
internal_read_func(void *ptr)
{
    struct io_internal_struct *iis = (struct io_internal_struct*)ptr;
    return read(iis->fd, iis->buf, iis->capa);
}

static VALUE
internal_write_func(void *ptr)
{
    struct io_internal_struct *iis = (struct io_internal_struct*)ptr;
    return write(iis->fd, iis->buf, iis->capa);
}

static int
rb_read_internal(int fd, void *buf, size_t count)
{
    struct io_internal_struct iis;
    iis.fd = fd;
    iis.buf = buf;
    iis.capa = count;

    return rb_thread_blocking_region(internal_read_func, &iis, RB_UBF_DFL, 0);
}

static int
rb_write_internal(int fd, void *buf, size_t count)
{
    struct io_internal_struct iis;
    iis.fd = fd;
    iis.buf = buf;
    iis.capa = count;

    return rb_thread_blocking_region(internal_write_func, &iis, RB_UBF_DFL, 0);
}

static int
io_fflush(rb_io_t *fptr)
{
    int r, l;
    int wbuf_off, wbuf_len;

    rb_io_check_closed(fptr);
    if (fptr->wbuf_len == 0)
        return 0;
    if (!rb_thread_fd_writable(fptr->fd)) {
        rb_io_check_closed(fptr);
    }
  retry:
    if (fptr->wbuf_len == 0)
        return 0;
    wbuf_off = fptr->wbuf_off;
    wbuf_len = fptr->wbuf_len;
    l = wbuf_len;
    if (PIPE_BUF < l &&
        !rb_thread_critical &&
        !rb_thread_alone() &&
        wsplit_p(fptr)) {
        l = PIPE_BUF;
    }
    r = rb_write_internal(fptr->fd, fptr->wbuf+wbuf_off, l);
    /* xxx: Other threads may modify wbuf.
     * A lock is required, definitely. */
    rb_io_check_closed(fptr);
    if (fptr->wbuf_len <= r) {
        fptr->wbuf_off = 0;
        fptr->wbuf_len = 0;
        return 0;
    }
    if (0 <= r) {
        fptr->wbuf_off += r;
        fptr->wbuf_len -= r;
        errno = EAGAIN;
    }
    if (rb_io_wait_writable(fptr->fd)) {
        rb_io_check_closed(fptr);
        goto retry;
    }
    return -1;
}

#ifdef HAVE_RB_FD_INIT
static VALUE
wait_readable(VALUE p)
{
    rb_fdset_t *rfds = (rb_fdset_t *)p;

    return rb_thread_select(rb_fd_max(rfds), rb_fd_ptr(rfds), NULL, NULL, NULL);
}
#endif

int
rb_io_wait_readable(int f)
{
    rb_fdset_t rfds;

    if (f < 0) {
	rb_raise(rb_eIOError, "closed stream");
    }
    switch (errno) {
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
	rb_thread_wait_fd(f);
	return Qtrue;

      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
	rb_fd_init(&rfds);
	rb_fd_set(f, &rfds);
#ifdef HAVE_RB_FD_INIT
	rb_ensure(wait_readable, (VALUE)&rfds,
		  (VALUE (*)(VALUE))rb_fd_term, (VALUE)&rfds);
#else
	rb_thread_select(f + 1, &rfds, NULL, NULL, NULL);
#endif
	return Qtrue;

      default:
	return Qfalse;
    }
}

#ifdef HAVE_RB_FD_INIT
static VALUE
wait_writable(VALUE p)
{
    rb_fdset_t *wfds = (rb_fdset_t *)p;

    return rb_thread_select(rb_fd_max(wfds), NULL, rb_fd_ptr(wfds), NULL, NULL);
}
#endif

int
rb_io_wait_writable(int f)
{
    rb_fdset_t wfds;

    if (f < 0) {
	rb_raise(rb_eIOError, "closed stream");
    }
    switch (errno) {
      case EINTR:
#if defined(ERESTART)
      case ERESTART:
#endif
	rb_thread_fd_writable(f);
	return Qtrue;

      case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
      case EWOULDBLOCK:
#endif
	rb_fd_init(&wfds);
	rb_fd_set(f, &wfds);
#ifdef HAVE_RB_FD_INIT
	rb_ensure(wait_writable, (VALUE)&wfds,
		  (VALUE (*)(VALUE))rb_fd_term, (VALUE)&wfds);
#else
	rb_thread_select(f + 1, NULL, &wfds, NULL, NULL);
#endif
	return Qtrue;

      default:
	return Qfalse;
    }
}

/* writing functions */
static long
io_fwrite(VALUE str, rb_io_t *fptr)
{
    long len, n, r, l, offset = 0;

    /*
     * If an external encoding was specified and it differs from
     * the strings encoding then we must transcode before writing.
     * We must also transcode if two encodings were specified
     */
    if (fptr->enc) {
	/* transcode str before output */
	/* the methods in transcode.c are static, so call indirectly */
	/* Can't use encode! because puts writes a frozen newline */
	if (fptr->enc2) {
	    str = rb_funcall(str, id_encode, 2,
			     rb_enc_from_encoding(fptr->enc2),
			     rb_enc_from_encoding(fptr->enc));
	}
	else {
	    str = rb_funcall(str, id_encode, 1,
			     rb_enc_from_encoding(fptr->enc));
	}
    }

    len = RSTRING_LEN(str);
    if ((n = len) <= 0) return n;
    if (fptr->wbuf == NULL && !(fptr->mode & FMODE_SYNC)) {
        fptr->wbuf_off = 0;
        fptr->wbuf_len = 0;
        fptr->wbuf_capa = 8192;
        fptr->wbuf = ALLOC_N(char, fptr->wbuf_capa);
    }
    if ((fptr->mode & (FMODE_SYNC|FMODE_TTY)) ||
        (fptr->wbuf && fptr->wbuf_capa <= fptr->wbuf_len + len)) {
        /* xxx: use writev to avoid double write if available */
        if (fptr->wbuf_len && fptr->wbuf_len+len <= fptr->wbuf_capa) {
            if (fptr->wbuf_capa < fptr->wbuf_off+fptr->wbuf_len+len) {
                MEMMOVE(fptr->wbuf, fptr->wbuf+fptr->wbuf_off, char, fptr->wbuf_len);
                fptr->wbuf_off = 0;
            }
            MEMMOVE(fptr->wbuf+fptr->wbuf_off+fptr->wbuf_len, RSTRING_PTR(str)+offset, char, len);
            fptr->wbuf_len += len;
            n = 0;
        }
        if (io_fflush(fptr) < 0)
            return -1L;
        if (n == 0)
            return len;
        /* avoid context switch between "a" and "\n" in STDERR.puts "a".
           [ruby-dev:25080] */
	if (fptr->stdio_file != stderr && !rb_thread_fd_writable(fptr->fd)) {
	    rb_io_check_closed(fptr);
	}
      retry:
        l = n;
        if (PIPE_BUF < l &&
            !rb_thread_critical &&
            !rb_thread_alone() &&
            wsplit_p(fptr)) {
            l = PIPE_BUF;
        }
	r = rb_write_internal(fptr->fd, RSTRING_PTR(str)+offset, l);
	/* xxx: other threads may modify given string. */
        if (r == n) return len;
        if (0 <= r) {
            offset += r;
            n -= r;
            errno = EAGAIN;
        }
        if (rb_io_wait_writable(fptr->fd)) {
            rb_io_check_closed(fptr);
	    if (offset < RSTRING_LEN(str))
		goto retry;
        }
        return -1L;
    }

    if (fptr->wbuf_off) {
        if (fptr->wbuf_len)
            MEMMOVE(fptr->wbuf, fptr->wbuf+fptr->wbuf_off, char, fptr->wbuf_len);
        fptr->wbuf_off = 0;
    }
    MEMMOVE(fptr->wbuf+fptr->wbuf_off+fptr->wbuf_len, RSTRING_PTR(str)+offset, char, len);
    fptr->wbuf_len += len;
    return len;
}

long
rb_io_fwrite(const char *ptr, long len, FILE *f)
{
    rb_io_t of;

    of.fd = fileno(f);
    of.stdio_file = f;
    of.mode = FMODE_WRITABLE;
    of.path = NULL;
    return io_fwrite(rb_str_new(ptr, len), &of);
}

/*
 *  call-seq:
 *     ios.write(string)    => integer
 *
 *  Writes the given string to <em>ios</em>. The stream must be opened
 *  for writing. If the argument is not a string, it will be converted
 *  to a string using <code>to_s</code>. Returns the number of bytes
 *  written.
 *
 *     count = $stdout.write( "This is a test\n" )
 *     puts "That was #{count} bytes of data"
 *
 *  <em>produces:</em>
 *
 *     This is a test
 *     That was 15 bytes of data
 */

static VALUE
io_write(VALUE io, VALUE str)
{
    rb_io_t *fptr;
    long n;
    VALUE tmp;

    rb_secure(4);
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

    n = io_fwrite(str, fptr);
    if (n == -1L) rb_sys_fail(fptr->path);

    return LONG2FIX(n);
}

VALUE
rb_io_write(VALUE io, VALUE str)
{
    return rb_funcall(io, id_write, 1, str);
}

/*
 *  call-seq:
 *     ios << obj     => ios
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

/*
 *  call-seq:
 *     ios.flush    => ios
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
    rb_io_t *fptr;

    if (TYPE(io) != T_FILE) {
        return rb_funcall(io, id_flush, 0);
    }

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    if (fptr->mode & FMODE_WRITABLE) {
        io_fflush(fptr);
    }
    if (fptr->mode & FMODE_READABLE) {
        io_unread(fptr);
    }

    return io;
}

/*
 *  call-seq:
 *     ios.pos     => integer
 *     ios.tell    => integer
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
    if (pos < 0 && errno) rb_sys_fail(fptr->path);
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
    if (pos < 0 && errno) rb_sys_fail(fptr->path);

    return INT2FIX(0);
}

/*
 *  call-seq:
 *     ios.seek(amount, whence=SEEK_SET) -> 0
 *
 *  Seeks to a given offset <i>anInteger</i> in the stream according to
 *  the value of <i>whence</i>:
 *
 *    IO::SEEK_CUR  | Seeks to _amount_ plus current position
 *    --------------+----------------------------------------------------
 *    IO::SEEK_END  | Seeks to _amount_ plus end of stream (you probably
 *                  | want a negative value for _amount_)
 *    --------------+----------------------------------------------------
 *    IO::SEEK_SET  | Seeks to the absolute location given by _amount_
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
	whence = NUM2INT(ptrname);
    }

    return rb_io_seek(io, offset, whence);
}

/*
 *  call-seq:
 *     ios.pos = integer    => integer
 *
 *  Seeks to the given position (in bytes) in <em>ios</em>.
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
    if (pos < 0) rb_sys_fail(fptr->path);

    return OFFT2NUM(pos);
}

/*
 *  call-seq:
 *     ios.rewind    => 0
 *
 *  Positions <em>ios</em> to the beginning of input, resetting
 *  <code>lineno</code> to zero.
 *
 *     f = File.new("testfile")
 *     f.readline   #=> "This is line one\n"
 *     f.rewind     #=> 0
 *     f.lineno     #=> 0
 *     f.readline   #=> "This is line one\n"
 */

static VALUE
rb_io_rewind(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (io_seek(fptr, 0L, 0) < 0) rb_sys_fail(fptr->path);
    if (io == ARGF.current_file) {
	ARGF.gets_lineno -= fptr->lineno;
    }
    fptr->lineno = 0;

    return INT2FIX(0);
}

static int
io_fillbuf(rb_io_t *fptr)
{
    int r;

    if (fptr->rbuf == NULL) {
        fptr->rbuf_off = 0;
        fptr->rbuf_len = 0;
        fptr->rbuf_capa = 8192;
        fptr->rbuf = ALLOC_N(char, fptr->rbuf_capa);
    }
    if (fptr->rbuf_len == 0) {
      retry:
	{
	    r = rb_read_internal(fptr->fd, fptr->rbuf, fptr->rbuf_capa);
	}
        if (r < 0) {
            if (rb_io_wait_readable(fptr->fd))
                goto retry;
            rb_sys_fail(fptr->path);
        }
        fptr->rbuf_off = 0;
        fptr->rbuf_len = r;
        if (r == 0)
            return -1; /* EOF */
    }
    return 0;
}

/*
 *  call-seq:
 *     ios.eof     => true or false
 *     ios.eof?    => true or false
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
 *  Note that <code>IO#eof?</code> reads data to a input buffer.
 *  So <code>IO#sysread</code> doesn't work with <code>IO#eof?</code>.
 */

VALUE
rb_io_eof(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (READ_DATA_PENDING(fptr)) return Qfalse;
    READ_CHECK(fptr);
    if (io_fillbuf(fptr) < 0) {
	return Qtrue;
    }
    return Qfalse;
}

/*
 *  call-seq:
 *     ios.sync    => true or false
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

/*
 *  call-seq:
 *     ios.sync = boolean   => boolean
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
rb_io_set_sync(VALUE io, VALUE mode)
{
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    if (RTEST(mode)) {
	fptr->mode |= FMODE_SYNC;
    }
    else {
	fptr->mode &= ~FMODE_SYNC;
    }
    return mode;
}

/*
 *  call-seq:
 *     ios.fsync   => 0 or nil
 *
 *  Immediately writes all buffered data in <em>ios</em> to disk.
 *  Returns <code>nil</code> if the underlying operating system does not
 *  support <em>fsync(2)</em>. Note that <code>fsync</code> differs from
 *  using <code>IO#sync=</code>. The latter ensures that data is flushed
 *  from Ruby's buffers, but doesn't not guarantee that the underlying
 *  operating system actually writes it to disk.
 */

static VALUE
rb_io_fsync(VALUE io)
{
#ifdef HAVE_FSYNC
    rb_io_t *fptr;

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);

    io_fflush(fptr);
    if (fsync(fptr->fd) < 0)
	rb_sys_fail(fptr->path);
    return INT2FIX(0);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

/*
 *  call-seq:
 *     ios.fileno    => fixnum
 *     ios.to_i      => fixnum
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
    rb_io_t *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = fptr->fd;
    return INT2FIX(fd);
}


/*
 *  call-seq:
 *     ios.pid    => fixnum
 *
 *  Returns the process ID of a child process associated with
 *  <em>ios</em>. This will be set by <code>IO::popen</code>.
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
    return INT2FIX(fptr->pid);
}


/*
 * call-seq:
 *   ios.inspect   => string
 *
 * Return a string describing this IO object.
 */

static VALUE
rb_io_inspect(VALUE obj)
{
    rb_io_t *fptr;
    const char *cname;
    const char *st = "";

    fptr = RFILE(rb_io_taint_check(obj))->fptr;
    if (!fptr || !fptr->path) return rb_any_to_s(obj);
    cname = rb_obj_classname(obj);
    if (fptr->fd < 0) {
	st = " (closed)";
    }
    return rb_sprintf("#<%s:%s%s>", cname, fptr->path, st);
}

/*
 *  call-seq:
 *     ios.to_io -> ios
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
    long n;

    n = READ_DATA_PENDING_COUNT(fptr);
    if (n <= 0) return 0;
    if (n > len) n = len;
    MEMMOVE(ptr, fptr->rbuf+fptr->rbuf_off, char, n);
    fptr->rbuf_off += n;
    fptr->rbuf_len -= n;
    return n;
}

static long
io_fread(VALUE str, long offset, rb_io_t *fptr)
{
    long len = RSTRING_LEN(str) - offset;
    long n = len;
    int c;

    if (READ_DATA_PENDING(fptr) == 0) {
	while (n > 0) {
	    c = rb_read_internal(fptr->fd, RSTRING_PTR(str)+offset, n);
	    if (c == 0) break;
	    if (c < 0) {
		rb_sys_fail(fptr->path);
	    }
	    offset += c;
	    if ((n -= c) <= 0) break;
	    rb_thread_wait_fd(fptr->fd);
	}
	return len - n;
    }

    while (n > 0) {
	c = read_buffered_data(RSTRING_PTR(str)+offset, n, fptr);
	if (c > 0) {
	    offset += c;
	    if ((n -= c) <= 0) break;
	}
	rb_thread_wait_fd(fptr->fd);
	rb_io_check_closed(fptr);
	if (io_fillbuf(fptr) < 0) {
	    break;
	}
    }
    return len - n;
}

long
rb_io_fread(char *ptr, long len, FILE *f)
{
    rb_io_t of;
    VALUE str;
    long n;

    of.fd = fileno(f);
    of.stdio_file = f;
    of.mode = FMODE_READABLE;
    str = rb_str_new(ptr, len);
    n = io_fread(str, 0, &of);
    MEMCPY(ptr, RSTRING_PTR(str), char, n);
    return n;
}

#define SMALLBUF 100

static long
remain_size(rb_io_t *fptr)
{
    struct stat st;
    off_t siz = READ_DATA_PENDING_COUNT(fptr);
    off_t pos;

    if (fstat(fptr->fd, &st) == 0  && S_ISREG(st.st_mode)
#ifdef __BEOS__
	&& (st.st_dev > 3)
#endif
	)
    {
	io_fflush(fptr);
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
    if (fptr->enc2) {
	/* two encodings, so transcode from enc2 to enc */
	/* the methods in transcode.c are static, so call indirectly */
	str = rb_funcall(str, id_encode, 2,
			 rb_enc_from_encoding(fptr->enc),
			 rb_enc_from_encoding(fptr->enc2));
    }
    else {
	/* just one encoding, so associate it with the string */
	rb_enc_associate(str, io_read_encoding(fptr));
    }
    return str;
}

static VALUE
read_all(rb_io_t *fptr, long siz, VALUE str)
{
    long bytes = 0;
    long n;
    long pos = 0;
    rb_encoding *enc = io_read_encoding(fptr);
    int cr = fptr->enc2 ? ENC_CODERANGE_BROKEN : 0;

    if (siz == 0) siz = BUFSIZ;
    if (NIL_P(str)) {
	str = rb_str_new(0, siz);
    }
    else {
	rb_str_resize(str, siz);
    }
    for (;;) {
	READ_CHECK(fptr);
	n = io_fread(str, bytes, fptr);
	if (n == 0 && bytes == 0) {
	    break;
	}
	bytes += n;
	if (cr != ENC_CODERANGE_BROKEN)
	    pos = rb_str_coderange_scan_restartable(RSTRING_PTR(str) + pos, RSTRING_PTR(str) + bytes, enc, &cr);
	if (bytes < siz) break;
	siz += BUFSIZ;
	rb_str_resize(str, siz);
    }
    if (bytes != siz) rb_str_resize(str, bytes);
    str = io_enc_str(str, fptr);
    if (!fptr->enc2) {
	ENC_CODERANGE_SET(str, cr);
    }
    return str;
}

void
rb_io_set_nonblock(rb_io_t *fptr)
{
    int flags;
#ifdef F_GETFL
    flags = fcntl(fptr->fd, F_GETFL);
    if (flags == -1) {
        rb_sys_fail(fptr->path);
    }
#else
    flags = 0;
#endif
    if ((flags & O_NONBLOCK) == 0) {
        flags |= O_NONBLOCK;
        if (fcntl(fptr->fd, F_SETFL, flags) == -1) {
            rb_sys_fail(fptr->path);
        }
    }
}

static VALUE
io_getpartial(int argc, VALUE *argv, VALUE io, int nonblock)
{
    rb_io_t *fptr;
    VALUE length, str;
    long n, len;

    rb_scan_args(argc, argv, "11", &length, &str);

    if ((len = NUM2LONG(length)) < 0) {
	rb_raise(rb_eArgError, "negative length %ld given", len);
    }

    if (NIL_P(str)) {
	str = rb_str_new(0, len);
    }
    else {
	StringValue(str);
	rb_str_modify(str);
        rb_str_resize(str, len);
    }
    OBJ_TAINT(str);

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (len == 0)
	return str;

    if (!nonblock)
        READ_CHECK(fptr);
    if (RSTRING_LEN(str) != len) {
      modified:
	rb_raise(rb_eRuntimeError, "buffer string modified");
    }
    n = read_buffered_data(RSTRING_PTR(str), len, fptr);
    if (n <= 0) {
      again:
	if (RSTRING_LEN(str) != len) goto modified;
        if (nonblock) {
            rb_io_set_nonblock(fptr);
        }
	n = rb_read_internal(fptr->fd, RSTRING_PTR(str), len);
        if (n < 0) {
            if (!nonblock && rb_io_wait_readable(fptr->fd))
                goto again;
            rb_sys_fail(fptr->path);
        }
    }
    rb_str_resize(str, n);

    if (n == 0)
        return Qnil;
    else
        return str;
}

/*
 *  call-seq:
 *     ios.readpartial(maxlen)              => string
 *     ios.readpartial(maxlen, outbuf)      => outbuf
 *
 *  Reads at most <i>maxlen</i> bytes from the I/O stream.
 *  It blocks only if <em>ios</em> has no data immediately available.
 *  It doesn't block if some data available.
 *  If the optional <i>outbuf</i> argument is present,
 *  it must reference a String, which will receive the data.
 *  It raises <code>EOFError</code> on end of file.
 *
 *  readpartial is designed for streams such as pipe, socket, tty, etc.
 *  It blocks only when no data immediately available.
 *  This means that it blocks only when following all conditions hold.
 *  * the buffer in the IO object is empty.
 *  * the content of the stream is empty.
 *  * the stream is not reached to EOF.
 *
 *  When readpartial blocks, it waits data or EOF on the stream.
 *  If some data is reached, readpartial returns with the data.
 *  If EOF is reached, readpartial raises EOFError.
 *
 *  When readpartial doesn't blocks, it returns or raises immediately.
 *  If the buffer is not empty, it returns the data in the buffer.
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
 *  * If the buffer is not empty, read from the buffer instead of "sysread for buffered IO (IOError)".
 *  * It doesn't cause Errno::EAGAIN and Errno::EINTR.  When readpartial meets EAGAIN and EINTR by read system call, readpartial retry the system call.
 *
 *  The later means that readpartial is nonblocking-flag insensitive.
 *  It blocks on the situation IO#sysread causes Errno::EAGAIN as if the fd is blocking mode.
 *
 */

static VALUE
io_readpartial(int argc, VALUE *argv, VALUE io)
{
    VALUE ret;

    ret = io_getpartial(argc, argv, io, 0);
    if (NIL_P(ret))
        rb_eof_error();
    else
        return ret;
}

/*
 *  call-seq:
 *     ios.read_nonblock(maxlen)              => string
 *     ios.read_nonblock(maxlen, outbuf)      => outbuf
 *
 *  Reads at most <i>maxlen</i> bytes from <em>ios</em> using
 *  read(2) system call after O_NONBLOCK is set for
 *  the underlying file descriptor.
 *
 *  If the optional <i>outbuf</i> argument is present,
 *  it must reference a String, which will receive the data.
 *
 *  read_nonblock just calls read(2).
 *  It causes all errors read(2) causes: EAGAIN, EINTR, etc.
 *  The caller should care such errors.
 *
 *  read_nonblock causes EOFError on EOF.
 *
 *  If the read buffer is not empty,
 *  read_nonblock reads from the buffer like readpartial.
 *  In this case, read(2) is not called.
 *
 */

static VALUE
io_read_nonblock(int argc, VALUE *argv, VALUE io)
{
    VALUE ret;

    ret = io_getpartial(argc, argv, io, 1);
    if (NIL_P(ret))
        rb_eof_error();
    else
        return ret;
}

/*
 *  call-seq:
 *     ios.write_nonblock(string)   => integer
 *
 *  Writes the given string to <em>ios</em> using
 *  write(2) system call after O_NONBLOCK is set for
 *  the underlying file descriptor.
 *
 *  write_nonblock just calls write(2).
 *  It causes all errors write(2) causes: EAGAIN, EINTR, etc.
 *  The result may also be smaller than string.length (partial write).
 *  The caller should care such errors and partial write.
 *
 *  If the write buffer is not empty, it is flushed at first.
 *
 */

static VALUE
rb_io_write_nonblock(VALUE io, VALUE str)
{
    rb_io_t *fptr;
    long n;

    rb_secure(4);
    if (TYPE(str) != T_STRING)
	str = rb_obj_as_string(str);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    io_fflush(fptr);

    rb_io_set_nonblock(fptr);
    n = write(fptr->fd, RSTRING_PTR(str), RSTRING_LEN(str));

    if (n == -1) rb_sys_fail(fptr->path);

    return LONG2FIX(n);
}

/*
 *  call-seq:
 *     ios.read([length [, buffer]])    => string, buffer, or nil
 *
 *  Reads at most <i>length</i> bytes from the I/O stream, or to the
 *  end of file if <i>length</i> is omitted or is <code>nil</code>.
 *  <i>length</i> must be a non-negative integer or nil.
 *  If the optional <i>buffer</i> argument is present, it must reference
 *  a String, which will receive the data.
 *
 *  At end of file, it returns <code>nil</code> or <code>""</code>
 *  depend on <i>length</i>.
 *  <code><i>ios</i>.read()</code> and
 *  <code><i>ios</i>.read(nil)</code> returns <code>""</code>.
 *  <code><i>ios</i>.read(<i>positive-integer</i>)</code> returns nil.
 *
 *  <code><i>ios</i>.read(0)</code> returns <code>""</code>.
 *
 *     f = File.new("testfile")
 *     f.read(16)   #=> "This is line one"
 */

static VALUE
io_read(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    long n, len;
    VALUE length, str;

    rb_scan_args(argc, argv, "02", &length, &str);

    if (NIL_P(length)) {
	if (!NIL_P(str)) StringValue(str);
	GetOpenFile(io, fptr);
	rb_io_check_readable(fptr);
	return read_all(fptr, remain_size(fptr), str);
    }
    len = NUM2LONG(length);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative length %ld given", len);
    }

    if (NIL_P(str)) {
	str = rb_str_new(0, len);
    }
    else {
	StringValue(str);
	rb_str_modify(str);
	rb_str_resize(str,len);
    }

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    if (len == 0) return str;

    READ_CHECK(fptr);
    if (RSTRING_LEN(str) != len) {
	rb_raise(rb_eRuntimeError, "buffer string modified");
    }
    n = io_fread(str, 0, fptr);
    if (n == 0) {
	if (fptr->fd < 0) return Qnil;
        rb_str_resize(str, 0);
        return Qnil;
    }
    rb_str_resize(str, n);

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
    int c = EOF;
    long limit = *lp;

    do {
	long pending = READ_DATA_PENDING_COUNT(fptr);
	if (pending > 0) {
	    const char *p = READ_DATA_PENDING_PTR(fptr);
	    const char *e;
	    long last = 0, len = (c != EOF);
	    rb_encoding *enc = io_read_encoding(fptr);

	    if (limit > 0 && pending > limit) pending = limit;
	    e = memchr(p, delim, pending);
	    if (e) pending = e - p + 1;
	    len += pending;
	    if (!NIL_P(str)) {
		last = RSTRING_LEN(str);
		rb_str_resize(str, last + len);
	    }
	    else {
		*strp = str = rb_str_buf_new(len);
		rb_str_set_len(str, len);
	    }
	    if (c != EOF) {
		RSTRING_PTR(str)[last++] = c;
	    }
	    if (limit > 0 && limit == pending) {
		char *p = fptr->rbuf+fptr->rbuf_off;
		char *pp = p + limit - 1;
		char *pl = rb_enc_left_char_head(p, pp, enc);

		if (pl < pp) {
		    int diff = pp - pl;
		    pending -= diff;
		    limit = pending;
		    rb_str_set_len(str, RSTRING_LEN(str)-diff);
		}
	    }
	    read_buffered_data(RSTRING_PTR(str) + last, pending, fptr); /* must not fail */
	    limit -= pending;
	    *lp = limit;
	    if (limit == 0) return RSTRING_PTR(str)[RSTRING_LEN(str)-1];
	    if (e) return delim;
	}
	else if (c != EOF) {
	    if (!NIL_P(str)) {
		char ch = c;
		rb_str_buf_cat(str, &ch, 1);
	    }
	    else {
		*strp = str = rb_str_buf_new(1);
		rb_str_resize(str, 1);
		RSTRING_PTR(str)[0] = c;
	    }
	}
	rb_thread_wait_fd(fptr->fd);
	rb_io_check_closed(fptr);
	if (io_fillbuf(fptr) < 0) {
	    *lp = limit;
	    return c;
	}
    } while (c != delim);

    {
	char ch = c;
	if (!NIL_P(str)) {
	    rb_str_cat(str, &ch, 1);
	}
	else {
	    *strp = str = rb_str_new(&ch, 1);
	}
    }

    return c;
}

static inline int
swallow(rb_io_t *fptr, int term)
{
    do {
	long cnt;
	while ((cnt = READ_DATA_PENDING_COUNT(fptr)) > 0) {
	    char buf[1024];
	    const char *p = READ_DATA_PENDING_PTR(fptr);
	    int i;
	    if (cnt > sizeof buf) cnt = sizeof buf;
	    if (*p != term) return Qtrue;
	    i = cnt;
	    while (--i && *++p == term);
	    if (!read_buffered_data(buf, cnt - i, fptr)) /* must not fail */
		rb_sys_fail(fptr->path);
	}
	rb_thread_wait_fd(fptr->fd);
	rb_io_check_closed(fptr);
    } while (io_fillbuf(fptr) == 0);
    return Qfalse;
}

static VALUE
rb_io_getline_fast(rb_io_t *fptr, rb_encoding *enc)
{
    VALUE str = Qnil;
    int len = 0;
    long pos = 0;
    int cr = fptr->enc2 ? ENC_CODERANGE_BROKEN : 0;

    for (;;) {
	long pending = READ_DATA_PENDING_COUNT(fptr);

	if (pending > 0) {
	    const char *p = READ_DATA_PENDING_PTR(fptr);
	    const char *e;

	    e = memchr(p, '\n', pending);
	    if (e) {
                pending = e - p + 1;
	    }
	    if (NIL_P(str)) {
		str = rb_str_new(p, pending);
		fptr->rbuf_off += pending;
		fptr->rbuf_len -= pending;
	    }
	    else {
		rb_str_resize(str, len + pending);
		read_buffered_data(RSTRING_PTR(str)+len, pending, fptr);
	    }
	    len += pending;
	    if (cr != ENC_CODERANGE_BROKEN)
		pos = rb_str_coderange_scan_restartable(RSTRING_PTR(str) + pos, RSTRING_PTR(str) + len, enc, &cr);
	    if (e) break;
	}
	rb_thread_wait_fd(fptr->fd);
	rb_io_check_closed(fptr);
	if (io_fillbuf(fptr) < 0) {
	    if (NIL_P(str)) return Qnil;
	    break;
	}
    }

    str = io_enc_str(str, fptr);
    if (!fptr->enc2) ENC_CODERANGE_SET(str, cr);
    fptr->lineno++;
    ARGF.lineno = INT2FIX(fptr->lineno);
    return str;
}

static void
prepare_getline_args(int argc, VALUE *argv, VALUE *rsp, long *limit, VALUE io)
{
    VALUE lim, rs;
    rb_io_t *fptr;

    if (argc == 0) {
	rs = rb_rs;
	lim = Qnil;
    }
    else {
	rb_scan_args(argc, argv, "11", &rs, &lim);
	if (!NIL_P(lim)) {
	    StringValue(rs);
	}
	else if (!NIL_P(rs) && TYPE(rs) != T_STRING) {
	    VALUE tmp = rb_check_string_type(rs);

	    if (NIL_P(tmp)) {
		lim = rs;
		rs = rb_rs;
	    }
	    else {
		rs = tmp;
	    }
	}
    }
    if (!NIL_P(rs)) {
	rb_encoding *enc_rs, *enc_io;

	GetOpenFile(io, fptr);
	enc_rs = rb_enc_get(rs);
	enc_io = io_read_encoding(fptr);
	if (enc_io != enc_rs &&
	    (rb_enc_str_coderange(rs) != ENC_CODERANGE_7BIT ||
	     !rb_enc_asciicompat(enc_io))) {
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
	if (fptr->enc2) {
            VALUE rs2;
	    rs2 = rb_funcall(rs, id_encode, 2,
			    rb_enc_from_encoding(fptr->enc2),
			    rb_enc_from_encoding(fptr->enc));
            if (!RTEST(rb_str_equal(rs, rs2))) {
                rs = rs2;
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
    rb_io_check_readable(fptr);
    if (rb_enc_dummy_p(io_input_encoding(fptr)) && rs != rb_default_rs) {
	rb_raise(rb_eNotImpError, "gets with delimiter against dummy encoding is not currently supported");
    }
    if (NIL_P(rs)) {
	str = read_all(fptr, 0, Qnil);
	if (RSTRING_LEN(str) == 0) return Qnil;
    }
    else if (limit == 0) {
	return rb_enc_str_new(0, 0, io_read_encoding(fptr));
    }
    else if (rs == rb_default_rs && limit < 0 &&
             rb_enc_asciicompat(enc = io_read_encoding(fptr))) {
	return rb_io_getline_fast(fptr, enc);
    }
    else {
	int c, newline;
	const char *rsptr;
	long rslen;
	int rspara = 0;

	rslen = RSTRING_LEN(rs);
	if (rslen == 0) {
	    rsptr = "\n\n";
	    rslen = 2;
	    rspara = 1;
	    swallow(fptr, '\n');
	    rs = 0;
	}
	else {
	    rsptr = RSTRING_PTR(rs);
	}
	newline = rsptr[rslen - 1];

	enc = io_input_encoding(fptr);
	while ((c = appendline(fptr, newline, &str, &limit)) != EOF) {
	    if (c == newline) {
		const char *s, *p, *pp;

		if (RSTRING_LEN(str) < rslen) continue;
		s = RSTRING_PTR(str);
		p = s +  RSTRING_LEN(str) - rslen;
		pp = rb_enc_left_char_head(s, p, enc);
		if (pp != p) continue;
		if (!rspara) rscheck(rsptr, rslen, rs);
		if (memcmp(p, rsptr, rslen) == 0) break;
	    }
	    if (limit == 0) {
		nolimit = 1;
		break;
	    }
	}

	if (rspara) {
	    if (c != EOF) {
		swallow(fptr, '\n');
	    }
	}
	if (!NIL_P(str)) str = io_enc_str(str, fptr);
    }

    if (!NIL_P(str)) {
	if (!nolimit) {
	    fptr->lineno++;
	    ARGF.lineno = INT2FIX(fptr->lineno);
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
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    return rb_io_getline_fast(fptr, io_read_encoding(fptr));
}

/*
 *  call-seq:
 *     ios.gets(sep=$/)     => string or nil
 *     ios.gets(limit)      => string or nil
 *     ios.gets(sep, limit) => string or nil
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
 *  given value.
 *
 *     File.new("testfile").gets   #=> "This is line one\n"
 *     $_                          #=> "This is line one\n"
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
 *     ios.lineno    => integer
 *
 *  Returns the current line number in <em>ios</em>. The stream must be
 *  opened for reading. <code>lineno</code> counts the number of times
 *  <code>gets</code> is called, rather than the number of newlines
 *  encountered. The two values will differ if <code>gets</code> is
 *  called with a separator other than newline. See also the
 *  <code>$.</code> variable.
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
    rb_io_check_readable(fptr);
    return INT2NUM(fptr->lineno);
}

/*
 *  call-seq:
 *     ios.lineno = integer    => integer
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
    rb_io_check_readable(fptr);
    fptr->lineno = NUM2INT(lineno);
    return lineno;
}

/*
 *  call-seq:
 *     ios.readline(sep=$/)     => string
 *     ios.readline(limit)      => string
 *     ios.readline(sep, limit) => string
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
 *     ios.readlines(sep=$/)     => array
 *     ios.readlines(limit)      => array
 *     ios.readlines(sep, limit) => array
 *
 *  Reads all of the lines in <em>ios</em>, and returns them in
 *  <i>anArray</i>. Lines are separated by the optional <i>sep</i>. If
 *  <i>sep</i> is <code>nil</code>, the rest of the stream is returned
 *  as a single record.  If the first argument is an integer, or
 *  optional second argument is given, the returning string would not be
 *  longer than the given value. The stream must be opened for reading
 *  or an <code>IOError</code> will be raised.
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
    ary = rb_ary_new();
    while (!NIL_P(line = rb_io_getline_1(rs, limit, io))) {
	rb_ary_push(ary, line);
    }
    return ary;
}

/*
 *  call-seq:
 *     ios.each(sep=$/) {|line| block }         => ios
 *     ios.each(limit) {|line| block }          => ios
 *     ios.each(sep,limit) {|line| block }      => ios
 *     ios.each_line(sep=$/) {|line| block }    => ios
 *     ios.each_line(limit) {|line| block }     => ios
 *     ios.each_line(sep,limit) {|line| block } => ios
 *
 *  Executes the block for every line in <em>ios</em>, where lines are
 *  separated by <i>sep</i>. <em>ios</em> must be opened for
 *  reading or an <code>IOError</code> will be raised.
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
    while (!NIL_P(str = rb_io_getline_1(rs, limit, io))) {
	rb_yield(str);
    }
    return io;
}

/*
 *  call-seq:
 *     ios.each_byte {|byte| block }  => ios
 *
 *  Calls the given block once for each byte (0..255) in <em>ios</em>,
 *  passing the byte as an argument. The stream must be opened for
 *  reading or an <code>IOError</code> will be raised.
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
    char *p, *e;

    RETURN_ENUMERATOR(io, 0, 0);
    GetOpenFile(io, fptr);

    for (;;) {
	p = fptr->rbuf+fptr->rbuf_off;
	e = p + fptr->rbuf_len;
	while (p < e) {
	    fptr->rbuf_off++;
	    fptr->rbuf_len--;
	    rb_yield(INT2FIX(*p & 0xff));
	    p++;
    errno = 0;
	}
	rb_io_check_readable(fptr);
	READ_CHECK(fptr);
	if (io_fillbuf(fptr) < 0) {
	    break;
	}
    }
    return io;
}

static VALUE
io_shift_crbuf(rb_io_t *fptr, int len)
{
    VALUE str;
    str = rb_str_new(fptr->crbuf+fptr->crbuf_off, len);
    fptr->crbuf_off += len;
    fptr->crbuf_len -= len;
    OBJ_TAINT(str);
    rb_enc_associate(str, fptr->enc);
    /* xxx: set coderange */
    if (fptr->crbuf_len == 0)
        fptr->crbuf_off = 0;
    if (fptr->crbuf_off < fptr->crbuf_capa/2) {
        memmove(fptr->crbuf, fptr->crbuf+fptr->crbuf_off, fptr->crbuf_len);
        fptr->crbuf_off = 0;
    }
    return str;
}

static VALUE
io_getc(rb_io_t *fptr, rb_encoding *enc)
{
    int r, n, cr = 0;
    VALUE str;

    if (fptr->enc2) {
        if (!fptr->readconv) {
            fptr->readconv = rb_econv_open(fptr->enc2->name, fptr->enc->name, 0);
            if (!fptr->readconv)
                rb_raise(rb_eIOError, "code converter open failed (%s to %s)", fptr->enc->name, fptr->enc2->name);
            fptr->crbuf_off = 0;
            fptr->crbuf_len = 0;
            fptr->crbuf_capa = 1024;
            fptr->crbuf = ALLOC_N(char, fptr->crbuf_capa);
        }

        while (1) {
            const unsigned char *ss, *sp, *se;
            unsigned char *ds, *dp, *de;
            rb_econv_result_t res;
            int putbackable;
            if (fptr->crbuf_len) {
                r = rb_enc_precise_mbclen(fptr->crbuf+fptr->crbuf_off, fptr->crbuf+fptr->crbuf_off+fptr->crbuf_len, fptr->enc);
                if (!MBCLEN_NEEDMORE_P(r))
                    break;
                if (fptr->crbuf_len == fptr->crbuf_capa) {
                    rb_raise(rb_eIOError, "too long character");
                }
            }
            if (fptr->rbuf_len == 0) {
                if (io_fillbuf(fptr) == -1) {
                    if (fptr->crbuf_len == 0)
                        return Qnil;
                    /* return an incomplete character just before EOF */
                    return io_shift_crbuf(fptr, fptr->crbuf_len);
                }
            }
            ss = sp = (const unsigned char *)fptr->rbuf + fptr->rbuf_off;
            se = sp + fptr->rbuf_len;
            ds = dp = (unsigned char *)fptr->crbuf + fptr->crbuf_off + fptr->crbuf_len;
            de = (unsigned char *)fptr->crbuf + fptr->crbuf_capa;
            res = rb_econv_convert(fptr->readconv, &sp, se, &dp, de, ECONV_PARTIAL_INPUT|ECONV_OUTPUT_FOLLOWED_BY_INPUT);
            fptr->rbuf_off += sp - ss;
            fptr->rbuf_len -= sp - ss;
            fptr->crbuf_len += dp - ds;
            putbackable = rb_econv_putbackable(fptr->readconv);
            if (putbackable) {
                rb_econv_putback(fptr->readconv, (unsigned char *)fptr->rbuf + fptr->rbuf_off - putbackable, putbackable);
                fptr->rbuf_off -= putbackable;
                fptr->rbuf_len += putbackable;
            }
            rb_econv_check_error(fptr->readconv);
        }
        if (MBCLEN_INVALID_P(r)) {
            r = rb_enc_mbclen(fptr->crbuf+fptr->crbuf_off, fptr->crbuf+fptr->crbuf_off+fptr->crbuf_len, fptr->enc);
            return io_shift_crbuf(fptr, r);
        }
        return io_shift_crbuf(fptr, MBCLEN_CHARFOUND_LEN(r));
    }

    if (io_fillbuf(fptr) < 0) {
	return Qnil;
    }
    if (rb_enc_asciicompat(enc) && ISASCII(fptr->rbuf[fptr->rbuf_off])) {
	str = rb_str_new(fptr->rbuf+fptr->rbuf_off, 1);
	fptr->rbuf_off += 1;
	fptr->rbuf_len -= 1;
	cr = ENC_CODERANGE_7BIT;
    }
    else {
	r = rb_enc_precise_mbclen(fptr->rbuf+fptr->rbuf_off, fptr->rbuf+fptr->rbuf_off+fptr->rbuf_len, enc);
	if (MBCLEN_CHARFOUND_P(r) &&
	    (n = MBCLEN_CHARFOUND_LEN(r)) <= fptr->rbuf_len) {
	    str = rb_str_new(fptr->rbuf+fptr->rbuf_off, n);
	    fptr->rbuf_off += n;
	    fptr->rbuf_len -= n;
	    cr = ENC_CODERANGE_VALID;
	}
	else if (MBCLEN_NEEDMORE_P(r)) {
	    str = rb_str_new(fptr->rbuf+fptr->rbuf_off, fptr->rbuf_len);
	    fptr->rbuf_len = 0;
	  getc_needmore:
	    if (io_fillbuf(fptr) != -1) {
		rb_str_cat(str, fptr->rbuf+fptr->rbuf_off, 1);
		fptr->rbuf_off++;
		fptr->rbuf_len--;
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
	    str = rb_str_new(fptr->rbuf+fptr->rbuf_off, 1);
	    fptr->rbuf_off++;
	    fptr->rbuf_len--;
	}
    }
    if (!cr) cr = ENC_CODERANGE_BROKEN;
    str = io_enc_str(str, fptr);
    if (!fptr->enc2) {
	ENC_CODERANGE_SET(str, cr);
    }
    return str;
}

/*
 *  call-seq:
 *     ios.each_char {|c| block }  => ios
 *
 *  Calls the given block once for each character in <em>ios</em>,
 *  passing the character as an argument. The stream must be opened for
 *  reading or an <code>IOError</code> will be raised.
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
    rb_io_check_readable(fptr);

    enc = io_input_encoding(fptr);
    READ_CHECK(fptr);
    while (!NIL_P(c = io_getc(fptr, enc))) {
        rb_yield(c);
    }
    return io;
}



/*
 *  call-seq:
 *     ios.lines(sep=$/)     => anEnumerator
 *     ios.lines(limit)      => anEnumerator
 *     ios.lines(sep, limit) => anEnumerator
 *
 *  Returns an enumerator that gives each line in <em>ios</em>.
 *  The stream must be opened for reading or an <code>IOError</code>
 *  will be raised.
 *
 *     f = File.new("testfile")
 *     f.lines.to_a  #=> ["foo\n", "bar\n"]
 *     f.rewind
 *     f.lines.sort  #=> ["bar\n", "foo\n"]
 */

static VALUE
rb_io_lines(int argc, VALUE *argv, VALUE io)
{
    return rb_enumeratorize(io, ID2SYM(rb_intern("each_line")), argc, argv);
}

/*
 *  call-seq:
 *     ios.bytes   => anEnumerator
 *
 *  Returns an enumerator that gives each byte (0..255) in <em>ios</em>.
 *  The stream must be opened for reading or an <code>IOError</code>
 *  will be raised.
 *     
 *     f = File.new("testfile")
 *     f.bytes.to_a  #=> [104, 101, 108, 108, 111]
 *     f.rewind
 *     f.bytes.sort  #=> [101, 104, 108, 108, 111]
 */

static VALUE
rb_io_bytes(VALUE io)
{
    return rb_enumeratorize(io, ID2SYM(rb_intern("each_byte")), 0, 0);
}

/*
 *  call-seq:
 *     ios.chars   => anEnumerator
 *  
 *  Returns an enumerator that gives each character in <em>ios</em>.
 *  The stream must be opened for reading or an <code>IOError</code>
 *  will be raised.
 *     
 *     f = File.new("testfile")
 *     f.chars.to_a  #=> ["h", "e", "l", "l", "o"]
 *     f.rewind
 *     f.chars.sort  #=> ["e", "h", "l", "l", "o"]
 */

static VALUE
rb_io_chars(VALUE io)
{
    return rb_enumeratorize(io, ID2SYM(rb_intern("each_char")), 0, 0);
}

/*
 *  call-seq:
 *     ios.getc   => fixnum or nil
 *
 *  Reads a one-character string from <em>ios</em>. Returns
 *  <code>nil</code> if called at end of file.
 *
 *     f = File.new("testfile")
 *     f.getc   #=> "8"
 *     f.getc   #=> "1"
 */

static VALUE
rb_io_getc(VALUE io)
{
    rb_io_t *fptr;
    rb_encoding *enc;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    enc = io_input_encoding(fptr);
    READ_CHECK(fptr);
    return io_getc(fptr, enc);
}
int
rb_getc(FILE *f)
{
    int c;

    rb_read_check(f);
    TRAP_BEG;
    c = getc(f);
    TRAP_END;

    return c;
}

/*
 *  call-seq:
 *     ios.readchar   => string
 *
 *  Reads a one-character string from <em>ios</em>. Raises an
 *  <code>EOFError</code> on end of file.
 *
 *     f = File.new("testfile")
 *     f.readchar   #=> "8"
 *     f.readchar   #=> "1"
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
 *     ios.getbyte   => fixnum or nil
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
    rb_io_check_readable(fptr);
    READ_CHECK(fptr);
    if (fptr->fd == 0 && (fptr->mode & FMODE_TTY) && TYPE(rb_stdout) == T_FILE) {
        rb_io_t *ofp;
        GetOpenFile(rb_stdout, ofp);
        if (ofp->mode & FMODE_TTY) {
            rb_io_flush(rb_stdout);
        }
    }
    if (io_fillbuf(fptr) < 0) {
	return Qnil;
    }
    fptr->rbuf_off++;
    fptr->rbuf_len--;
    c = (unsigned char)fptr->rbuf[fptr->rbuf_off-1];
    return INT2FIX(c & 0xff);
}

/*
 *  call-seq:
 *     ios.readbyte   => fixnum
 *
 *  Reads a character as with <code>IO#getc</code>, but raises an
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
 *     ios.ungetc(string)   => nil
 *
 *  Pushes back one character (passed as a parameter) onto <em>ios</em>,
 *  such that a subsequent buffered read will return it. Only one character
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

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    if (NIL_P(c)) return Qnil;
    if (FIXNUM_P(c)) {
	int cc = FIX2INT(c);
	rb_encoding *enc = io_read_encoding(fptr);
	char buf[16];

	c = rb_str_new(buf, rb_enc_mbcput(cc, buf, enc));
    }
    else {
	SafeStringValue(c);
    }
    io_ungetc(c, fptr);
    return Qnil;
}

/*
 *  call-seq:
 *     ios.isatty   => true or false
 *     ios.tty?     => true or false
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

/*
 *  call-seq:
 *     ios.close_on_exec?   => true or false
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
#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(F_SETFD) && defined(FD_CLOEXEC)
    rb_io_t *fptr;
    VALUE write_io;
    int fd, ret;

    write_io = GetWriteIO(io);
    if (io != write_io) {
        GetOpenFile(write_io, fptr);
        if (fptr && 0 <= (fd = fptr->fd)) {
            if ((ret = fcntl(fd, F_GETFD)) == -1) rb_sys_fail(fptr->path);
            if (!(ret & FD_CLOEXEC)) return Qfalse;
        }
    }

    GetOpenFile(io, fptr);
    if (fptr && 0 <= (fd = fptr->fd)) {
        if ((ret = fcntl(fd, F_GETFD)) == -1) rb_sys_fail(fptr->path);
        if (!(ret & FD_CLOEXEC)) return Qfalse;
    }
    return Qtrue;
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

/*
 *  call-seq:
 *     ios.close_on_exec = bool    => true or false
 *
 *  Sets a close-on-exec flag.
 *
 *     f = open("/dev/null")
 *     f.close_on_exec = true
 *     system("cat", "/proc/self/fd/#{f.fileno}") # cat: /proc/self/fd/3: No such file or directory
 *     f.closed?                #=> false
 */

static VALUE
rb_io_set_close_on_exec(VALUE io, VALUE arg)
{
#if defined(HAVE_FCNTL) && defined(F_GETFD) && defined(F_SETFD) && defined(FD_CLOEXEC)
    int flag = RTEST(arg) ? FD_CLOEXEC : 0;
    rb_io_t *fptr;
    VALUE write_io;
    int fd, ret;

    write_io = GetWriteIO(io);
    if (io != write_io) {
        GetOpenFile(write_io, fptr);
        if (fptr && 0 <= (fd = fptr->fd)) {
            if ((ret = fcntl(fptr->fd, F_GETFD)) == -1) rb_sys_fail(fptr->path);
            if ((ret & FD_CLOEXEC) != flag) {
                ret = (ret & ~FD_CLOEXEC) | flag;
                ret = fcntl(fd, F_SETFD, ret);
                if (ret == -1) rb_sys_fail(fptr->path);
            }
        }

    }

    GetOpenFile(io, fptr);
    if (fptr && 0 <= (fd = fptr->fd)) {
        if ((ret = fcntl(fd, F_GETFD)) == -1) rb_sys_fail(fptr->path);
        if ((ret & FD_CLOEXEC) != flag) {
            ret = (ret & ~FD_CLOEXEC) | flag;
            ret = fcntl(fd, F_SETFD, ret);
            if (ret == -1) rb_sys_fail(fptr->path);
        }
    }
#else
    rb_notimplement();
#endif
    return Qnil;
}

#define FMODE_PREP (1<<16)
#define IS_PREP_STDIO(f) ((f)->mode & FMODE_PREP)
#define PREP_STDIO_NAME(f) ((f)->path)

static void
fptr_finalize(rb_io_t *fptr, int noraise)
{
    int ebadf = 0;
    if (fptr->wbuf_len) {
        io_fflush(fptr);
    }
    if (IS_PREP_STDIO(fptr) ||
        fptr->fd <= 2) {
	return;
    }
    if (fptr->stdio_file) {
        if (fclose(fptr->stdio_file) < 0 && !noraise) {
            /* fptr->stdio_file is deallocated anyway */
            fptr->stdio_file = 0;
            fptr->fd = -1;
            rb_sys_fail(fptr->path);
        }
    }
    else if (0 <= fptr->fd) {
        if (close(fptr->fd) < 0 && !noraise) {
            if (errno != EBADF) {
                /* fptr->fd is still not closed */
                rb_sys_fail(fptr->path);
            }
            else {
                /* fptr->fd is already closed. */
                ebadf = 1;
            }
        }
    }
    fptr->fd = -1;
    fptr->stdio_file = 0;
    fptr->mode &= ~(FMODE_READABLE|FMODE_WRITABLE);
    if (ebadf) {
        rb_sys_fail(fptr->path);
    }
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

int
rb_io_fptr_finalize(rb_io_t *fptr)
{
    if (!fptr) return 0;
    if (fptr->refcnt <= 0 || --fptr->refcnt) return 0;
    if (fptr->path) {
	free(fptr->path);
	fptr->path = 0;
    }
    if (0 <= fptr->fd)
	rb_io_fptr_cleanup(fptr, Qtrue);
    if (fptr->rbuf) {
        free(fptr->rbuf);
        fptr->rbuf = 0;
    }
    if (fptr->wbuf) {
        free(fptr->wbuf);
        fptr->wbuf = 0;
    }
    if (fptr->readconv) {
        rb_econv_close(fptr->readconv);
        fptr->readconv = NULL;
    }
    if (fptr->crbuf) {
        free(fptr->crbuf);
        fptr->crbuf = NULL;
    }
    free(fptr);
    return 1;
}

VALUE
rb_io_close(VALUE io)
{
    rb_io_t *fptr;
    int fd;
    VALUE write_io;
    rb_io_t *write_fptr;

    write_io = GetWriteIO(io);
    if (io != write_io) {
        write_fptr = RFILE(write_io)->fptr;
        if (write_fptr && 0 <= write_fptr->fd) {
            rb_io_fptr_cleanup(write_fptr, Qtrue);
        }
    }

    fptr = RFILE(io)->fptr;
    if (!fptr) return Qnil;
    if (fptr->fd < 0) return Qnil;

    fd = fptr->fd;
    rb_io_fptr_cleanup(fptr, Qfalse);
    rb_thread_fd_close(fd);

    if (fptr->pid) {
	rb_syswait(fptr->pid);
	fptr->pid = 0;
    }

    return Qnil;
}

/*
 *  call-seq:
 *     ios.close   => nil
 *
 *  Closes <em>ios</em> and flushes any pending writes to the operating
 *  system. The stream is unavailable for any further data operations;
 *  an <code>IOError</code> is raised if such an attempt is made. I/O
 *  streams are automatically closed when they are claimed by the
 *  garbage collector.
 *
 *  If <em>ios</em> is opened by <code>IO.popen</code>,
 *  <code>close</code> sets <code>$?</code>.
 */

static VALUE
rb_io_close_m(VALUE io)
{
    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    rb_io_check_closed(RFILE(io)->fptr);
    rb_io_close(io);
    return Qnil;
}

static VALUE
io_call_close(VALUE io)
{
    return rb_funcall(io, rb_intern("close"), 0, 0);
}

static VALUE
io_close(VALUE io)
{
    return rb_rescue(io_call_close, io, 0, 0);
}

/*
 *  call-seq:
 *     ios.closed?    => true or false
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

    fptr = RFILE(io)->fptr;
    rb_io_check_initialized(fptr);
    return 0 <= fptr->fd ? Qfalse : Qtrue;
}

/*
 *  call-seq:
 *     ios.close_read    => nil
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

    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    GetOpenFile(io, fptr);
    if (is_socket(fptr->fd, fptr->path)) {
#ifndef SHUT_RD
# define SHUT_RD 0
#endif
        if (shutdown(fptr->fd, SHUT_RD) < 0)
            rb_sys_fail(fptr->path);
        fptr->mode &= ~FMODE_READABLE;
        if (!(fptr->mode & FMODE_WRITABLE))
            return rb_io_close(io);
        return Qnil;
    }

    write_io = GetWriteIO(io);
    if (io != write_io) {
	rb_io_t *wfptr;
        fptr_finalize(fptr, Qfalse);
	GetOpenFile(write_io, wfptr);
	if (fptr->refcnt < LONG_MAX) {
	    wfptr->refcnt++;
	    RFILE(io)->fptr = wfptr;
	    rb_io_fptr_finalize(fptr);
	}
        return Qnil;
    }

    if (fptr->mode & FMODE_WRITABLE) {
	rb_raise(rb_eIOError, "closing non-duplex IO for reading");
    }
    return rb_io_close(io);
}

/*
 *  call-seq:
 *     ios.close_write   => nil
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

    if (rb_safe_level() >= 4 && !OBJ_UNTRUSTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    write_io = GetWriteIO(io);
    GetOpenFile(write_io, fptr);
    if (is_socket(fptr->fd, fptr->path)) {
#ifndef SHUT_WR
# define SHUT_WR 1
#endif
        if (shutdown(fptr->fd, SHUT_WR) < 0)
            rb_sys_fail(fptr->path);
        fptr->mode &= ~FMODE_WRITABLE;
        if (!(fptr->mode & FMODE_READABLE))
	    return rb_io_close(write_io);
        return Qnil;
    }

    if (fptr->mode & FMODE_READABLE) {
	rb_raise(rb_eIOError, "closing non-duplex IO for writing");
    }

    rb_io_close(write_io);
    if (io != write_io) {
	GetOpenFile(io, fptr);
	fptr->tied_io_for_writing = 0;
	fptr->mode &= ~FMODE_DUPLEX;
    }
    return Qnil;
}

/*
 *  call-seq:
 *     ios.sysseek(offset, whence=SEEK_SET)   => integer
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
	whence = NUM2INT(ptrname);
    }
    pos = NUM2OFFT(offset);
    GetOpenFile(io, fptr);
    if ((fptr->mode & FMODE_READABLE) && READ_DATA_BUFFERED(fptr)) {
	rb_raise(rb_eIOError, "sysseek for buffered IO");
    }
    if ((fptr->mode & FMODE_WRITABLE) && fptr->wbuf_len) {
	rb_warn("sysseek for buffered IO");
    }
    pos = lseek(fptr->fd, pos, whence);
    if (pos == -1) rb_sys_fail(fptr->path);

    return OFFT2NUM(pos);
}

/*
 *  call-seq:
 *     ios.syswrite(string)   => integer
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

    rb_secure(4);
    if (TYPE(str) != T_STRING)
	str = rb_obj_as_string(str);

    io = GetWriteIO(io);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    if (fptr->wbuf_len) {
	rb_warn("syswrite for buffered IO");
    }
    if (!rb_thread_fd_writable(fptr->fd)) {
        rb_io_check_closed(fptr);
    }
    TRAP_BEG;
    n = write(fptr->fd, RSTRING_PTR(str), RSTRING_LEN(str));
    TRAP_END;

    if (n == -1) rb_sys_fail(fptr->path);

    return LONG2FIX(n);
}

/*
 *  call-seq:
 *     ios.sysread(integer[, outbuf])    => string
 *
 *  Reads <i>integer</i> bytes from <em>ios</em> using a low-level
 *  read and returns them as a string. Do not mix with other methods
 *  that read from <em>ios</em> or you may get unpredictable results.
 *  If the optional <i>outbuf</i> argument is present, it must reference
 *  a String, which will receive the data.
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

    rb_scan_args(argc, argv, "11", &len, &str);
    ilen = NUM2LONG(len);

    if (NIL_P(str)) {
	str = rb_str_new(0, ilen);
    }
    else {
	StringValue(str);
	rb_str_modify(str);
	rb_str_resize(str, ilen);
    }
    if (ilen == 0) return str;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (READ_DATA_BUFFERED(fptr)) {
	rb_raise(rb_eIOError, "sysread for buffered IO");
    }

    n = fptr->fd;
    rb_thread_wait_fd(fptr->fd);
    rb_io_check_closed(fptr);
    if (RSTRING_LEN(str) != ilen) {
	rb_raise(rb_eRuntimeError, "buffer string modified");
    }

    n = rb_read_internal(fptr->fd, RSTRING_PTR(str), ilen);

    if (n == -1) {
	rb_sys_fail(fptr->path);
    }
    rb_str_set_len(str, n);
    if (n == 0 && ilen > 0) {
	rb_eof_error();
    }
    rb_str_resize(str, n);
    OBJ_TAINT(str);

    return str;
}

VALUE
rb_io_binmode(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
#if defined(_WIN32) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__) || defined(__EMX__)
    if (!(fptr->mode & FMODE_BINMODE) && READ_DATA_BUFFERED(fptr)) {
	rb_raise(rb_eIOError, "buffer already filled with text-mode content");
    }
    if (0 <= fptr->fd && setmode(fptr->fd, O_BINARY) == -1)
	rb_sys_fail(fptr->path);
#endif
    fptr->mode |= FMODE_BINMODE;
    return io;
}

/*
 *  call-seq:
 *     ios.binmode    => ios
 *
 *  Puts <em>ios</em> into binary mode. This is useful only in
 *  MS-DOS/Windows environments. Once a stream is in binary mode, it
 *  cannot be reset to nonbinary mode.
 */

static VALUE
rb_io_binmode_m(VALUE io)
{
#if defined(_WIN32) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__) || defined(__EMX__)
    VALUE write_io;
#endif

    rb_io_binmode(io);

#if defined(_WIN32) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__) || defined(__EMX__)
    write_io = GetWriteIO(io);
    if (write_io != io)
        rb_io_binmode(write_io);
#endif
    return io;
}

/*
 *  call-seq:
 *     ios.binmode?    => true or false
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
rb_io_flags_mode(int flags)
{
#ifdef O_BINARY
# define MODE_BINMODE(a,b) ((flags & FMODE_BINMODE) ? (b) : (a))
#else
# define MODE_BINMODE(a,b) (a)
#endif
    if (flags & FMODE_APPEND) {
	if ((flags & FMODE_READWRITE) == FMODE_READWRITE) {
	    return MODE_BINMODE("a+", "ab+");
	}
	return MODE_BINMODE("a", "ab");
    }
    switch (flags & FMODE_READWRITE) {
      case FMODE_READABLE:
	return MODE_BINMODE("r", "rb");
      case FMODE_WRITABLE:
	return MODE_BINMODE("w", "wb");
      case FMODE_READWRITE:
	if (flags & FMODE_CREATE) {
	    return MODE_BINMODE("w+", "wb+");
	}
	return MODE_BINMODE("r+", "rb+");
    }
    rb_raise(rb_eArgError, "invalid access modenum %o", flags);
    return NULL;		/* not reached */
}

int
rb_io_mode_flags(const char *mode)
{
    int flags = 0;
    const char *m = mode;

    switch (*m++) {
      case 'r':
	flags |= FMODE_READABLE;
	break;
      case 'w':
	flags |= FMODE_WRITABLE | FMODE_CREATE;
	break;
      case 'a':
	flags |= FMODE_WRITABLE | FMODE_APPEND | FMODE_CREATE;
	break;
      default:
      error:
	rb_raise(rb_eArgError, "invalid access mode %s", mode);
    }

    while (*m) {
        switch (*m++) {
	  case 'b':
            flags |= FMODE_BINMODE;
            break;
	  case '+':
            flags |= FMODE_READWRITE;
            break;
	  default:
            goto error;
	  case ':':
	    return flags;
        }
    }

    return flags;
}

int
rb_io_modenum_flags(int mode)
{
    int flags = 0;

    switch (mode & (O_RDONLY|O_WRONLY|O_RDWR)) {
      case O_RDONLY:
	flags = FMODE_READABLE;
	break;
      case O_WRONLY:
	flags = FMODE_WRITABLE;
	break;
      case O_RDWR:
	flags = FMODE_READWRITE;
	break;
    }

    if (mode & O_APPEND) {
	flags |= FMODE_APPEND;
    }
    if (mode & O_CREAT) {
	flags |= FMODE_CREATE;
    }
#ifdef O_BINARY
    if (mode & O_BINARY) {
	flags |= FMODE_BINMODE;
    }
#endif

    return flags;
}

int
rb_io_mode_modenum(const char *mode)
{
    int flags = 0;
    const char *m = mode;

    switch (*m++) {
      case 'r':
	flags |= O_RDONLY;
	break;
      case 'w':
	flags |= O_WRONLY | O_CREAT | O_TRUNC;
	break;
      case 'a':
	flags |= O_WRONLY | O_CREAT | O_APPEND;
	break;
      default:
      error:
	rb_raise(rb_eArgError, "invalid access mode %s", mode);
    }

    while (*m) {
        switch (*m++) {
	  case 'b':
#ifdef O_BINARY
            flags |= O_BINARY;
#endif
            break;
	  case '+':
            flags = (flags & ~O_ACCMODE) | O_RDWR;
            break;
	  default:
            goto error;
	  case ':':
	    return flags;
        }
    }

    return flags;
}

#define MODENUM_MAX 4

static const char*
rb_io_modenum_mode(int flags)
{
#ifdef O_BINARY
# define MODE_BINARY(a,b) ((flags & O_BINARY) ? (b) : (a))
#else
# define MODE_BINARY(a,b) (a)
#endif
    if (flags & O_APPEND) {
	if ((flags & O_RDWR) == O_RDWR) {
	    return MODE_BINARY("a+", "ab+");
	}
	return MODE_BINARY("a", "ab");
    }
    switch (flags & (O_RDONLY|O_WRONLY|O_RDWR)) {
      case O_RDONLY:
	return MODE_BINARY("r", "rb");
      case O_WRONLY:
	return MODE_BINARY("w", "wb");
      case O_RDWR:
	return MODE_BINARY("r+", "rb+");
    }
    rb_raise(rb_eArgError, "invalid access modenum %o", flags);
    return NULL;		/* not reached */
}

static void
mode_enc(rb_io_t *fptr, const char *estr)
{
    const char *p0, *p1;
    char *enc2name;
    int idx, idx2;

    /* parse estr as "enc" or "enc2:enc" */

    p0 = strrchr(estr, ':');
    if (!p0) p1 = estr;
    else     p1 = p0 + 1;
    idx = rb_enc_find_index(p1);
    if (idx >= 0) {
	fptr->enc = rb_enc_from_index(idx);
    }
    else {
	rb_warn("Unsupported encoding %s ignored", p1);
    }

    if (p0) {
	int n = p0 - estr;
	if (n > ENCODING_MAXNAMELEN) {
	    idx2 = -1;
	}
	else {
	    enc2name = ALLOCA_N(char, n+1);
	    memcpy(enc2name, estr, n);
	    enc2name[n] = '\0';
	    estr = enc2name;
	    idx2 = rb_enc_find_index(enc2name);
	}
	if (idx2 < 0) {
	    rb_warn("Unsupported encoding %.*s ignored", n, estr);
	}
	else if (idx2 == idx) {
	    rb_warn("Ignoring internal encoding %.*s: it is identical to external encoding %s",
		    n, estr, p1);
	}
	else {
	    fptr->enc2 = rb_enc_from_index(idx2);
	}
    }
}

void
rb_io_mode_enc(rb_io_t *fptr, const char *mode)
{
    const char *p = strchr(mode, ':');
    if (p) {
	mode_enc(fptr, p+1);
    }
}

struct sysopen_struct {
    char *fname;
    int flag;
    unsigned int mode;
};

static VALUE
sysopen_func(void *ptr)
{
    struct sysopen_struct *data = ptr;
    return (VALUE)open(data->fname, data->flag, data->mode);
}

static int
rb_sysopen_internal(char *fname, int flags, unsigned int mode)
{
    struct sysopen_struct data;
    data.fname = fname;
    data.flag = flags;
    data.mode = mode;
    return (int)rb_thread_blocking_region(sysopen_func, &data, RB_UBF_DFL, 0);
}

static int
rb_sysopen(char *fname, int flags, unsigned int mode)
{
    int fd;

    fd = rb_sysopen_internal(fname, flags, mode);
    if (fd < 0) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    fd = rb_sysopen_internal(fname, flags, mode);
	}
	if (fd < 0) {
	    rb_sys_fail(fname);
	}
    }
    UPDATE_MAXFD(fd);
    return fd;
}

FILE *
rb_fopen(const char *fname, const char *mode)
{
    FILE *file;

    file = fopen(fname, mode);
    if (!file) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    file = fopen(fname, mode);
	}
	if (!file) {
	    rb_sys_fail(fname);
	}
    }
#ifdef USE_SETVBUF
    if (setvbuf(file, NULL, _IOFBF, 0) != 0)
	rb_warn("setvbuf() can't be honoured for %s", fname);
#endif
#ifdef __human68k__
    setmode(fileno(file), O_TEXT);
#endif
    return file;
}

FILE *
rb_fdopen(int fd, const char *mode)
{
    FILE *file;

#if defined(sun)
    errno = 0;
#endif
    file = fdopen(fd, mode);
    if (!file) {
	if (
#if defined(sun)
	    errno == 0 ||
#endif
	    errno == EMFILE || errno == ENFILE) {
	    rb_gc();
#if defined(sun)
	    errno = 0;
#endif
	    file = fdopen(fd, mode);
	}
	if (!file) {
#ifdef _WIN32
	    if (errno == 0) errno = EINVAL;
#elif defined(sun)
	    if (errno == 0) errno = EMFILE;
#endif
	    rb_sys_fail(0);
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

static VALUE
rb_file_open_internal(VALUE io, const char *fname, const char *mode)
{
    rb_io_t *fptr;

    MakeOpenFile(io, fptr);
    fptr->mode = rb_io_mode_flags(mode);
    rb_io_mode_enc(fptr, mode);
    fptr->path = strdup(fname);
    fptr->fd = rb_sysopen(fptr->path, rb_io_mode_modenum(rb_io_flags_mode(fptr->mode)), 0666);
    io_check_tty(fptr);

    return io;
}

VALUE
rb_file_open(const char *fname, const char *mode)
{
    return rb_file_open_internal(io_alloc(rb_cFile), fname, mode);
}

static VALUE
rb_file_sysopen_internal(VALUE io, const char *fname, int flags, int mode)
{
    rb_io_t *fptr;

    MakeOpenFile(io, fptr);

    fptr->path = strdup(fname);
    fptr->mode = rb_io_modenum_flags(flags);
    fptr->fd = rb_sysopen(fptr->path, flags, mode);
    io_check_tty(fptr);

    return io;
}

VALUE
rb_file_sysopen(const char *fname, int flags, int mode)
{
    return rb_file_sysopen_internal(io_alloc(rb_cFile), fname, flags, mode);
}

#if defined(__CYGWIN__) || !defined(HAVE_FORK)
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

static void
pipe_finalize(rb_io_t *fptr, int noraise)
{
#if !defined(HAVE_FORK) && !defined(_WIN32)
    int status;
    if (fptr->stdio_file) {
	status = pclose(fptr->stdio_file);
    }
    fptr->fd = -1;
    fptr->stdio_file = 0;
#if defined DJGPP
    status <<= 8;
#endif
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
    ret = pipe(pipes);
    if (ret == -1) {
        if (errno == EMFILE || errno == ENFILE) {
            rb_gc();
            ret = pipe(pipes);
        }
    }
    if (ret == 0) {
        UPDATE_MAXFD(pipes[0]);
        UPDATE_MAXFD(pipes[1]);
    }
    return ret;
}

#ifdef HAVE_FORK
struct popen_arg {
    struct rb_exec_arg *execp;
    int modef;
    int pair[2];
    int write_pair[2];
};

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

void
rb_close_before_exec(int lowfd, int maxhint, VALUE noclose_fds)
{
    int fd, ret;
    int max = max_file_descriptor;
    if (max < maxhint)
        max = maxhint;
    for (fd = lowfd; fd <= max; fd++) {
        if (!NIL_P(noclose_fds) &&
            RTEST(rb_hash_lookup(noclose_fds, INT2FIX(fd))))
            continue;
#ifdef FD_CLOEXEC
	ret = fcntl(fd, F_GETFD);
	if (ret != -1 && !(ret & FD_CLOEXEC)) {
            fcntl(fd, F_SETFD, ret|FD_CLOEXEC);
        }
#else
	close(fd);
#endif
    }
}

static int
popen_exec(void *pp)
{
    struct popen_arg *p = (struct popen_arg*)pp;

    rb_thread_atfork_before_exec();
    return rb_exec(p->execp);
}
#endif

static VALUE
pipe_open(struct rb_exec_arg *eargp, VALUE prog, const char *mode)
{
    int modef = rb_io_mode_flags(mode);
    int pid = 0;
    rb_io_t *fptr;
    VALUE port;
    rb_io_t *write_fptr;
    VALUE write_port;
#if defined(HAVE_FORK)
    int status;
    struct popen_arg arg;
#elif defined(_WIN32)
    int openmode = rb_io_mode_modenum(mode);
    const char *exename = NULL;
    volatile VALUE cmdbuf;
    struct rb_exec_arg sarg;
#endif
    FILE *fp = 0;
    int fd = -1;
    int write_fd = -1;
    const char *cmd = 0;
    int argc;
    VALUE *argv;

    if (prog)
        cmd = StringValueCStr(prog);

    if (!eargp) {
        /* fork : IO.popen("-") */
        argc = 0;
        argv = 0;
    }
    else if (eargp->argc) {
        /* no shell : IO.popen([prog, arg0], arg1, ...) */
        argc = eargp->argc;
        argv = eargp->argv;
    }
    else {
        /* with shell : IO.popen(prog) */
        argc = 0;
        argv = 0;
    }

#if defined(HAVE_FORK)
    arg.execp = eargp;
    arg.modef = modef;
    arg.pair[0] = arg.pair[1] = -1;
    arg.write_pair[0] = arg.write_pair[1] = -1;
    switch (modef & (FMODE_READABLE|FMODE_WRITABLE)) {
      case FMODE_READABLE|FMODE_WRITABLE:
        if (rb_pipe(arg.write_pair) < 0)
            rb_sys_fail(cmd);
        if (rb_pipe(arg.pair) < 0) {
            int e = errno;
            close(arg.write_pair[0]);
            close(arg.write_pair[1]);
            errno = e;
            rb_sys_fail(cmd);
        }
        if (eargp) {
            rb_exec_arg_addopt(eargp, INT2FIX(0), INT2FIX(arg.write_pair[0]));
            rb_exec_arg_addopt(eargp, INT2FIX(1), INT2FIX(arg.pair[1]));
        }
	break;
      case FMODE_READABLE:
        if (rb_pipe(arg.pair) < 0)
            rb_sys_fail(cmd);
        if (eargp)
            rb_exec_arg_addopt(eargp, INT2FIX(1), INT2FIX(arg.pair[1]));
	break;
      case FMODE_WRITABLE:
        if (rb_pipe(arg.pair) < 0)
            rb_sys_fail(cmd);
        if (eargp)
            rb_exec_arg_addopt(eargp, INT2FIX(0), INT2FIX(arg.pair[0]));
	break;
      default:
        rb_sys_fail(cmd);
    }
    if (eargp) {
        rb_exec_arg_fixup(arg.execp);
	pid = rb_fork(&status, popen_exec, &arg, arg.execp->redirect_fds);
    }
    else {
	fflush(stdin);		/* is it really needed? */
	rb_io_flush(rb_stdout);
	rb_io_flush(rb_stderr);
	pid = rb_fork(&status, 0, 0, Qnil);
	if (pid == 0) {		/* child */
	    popen_redirect(&arg);
	    rb_io_synchronized(RFILE(orig_stdout)->fptr);
	    rb_io_synchronized(RFILE(orig_stderr)->fptr);
	    return Qnil;
	}
    }

    /* parent */
    if (pid == -1) {
	int e = errno;
	close(arg.pair[0]);
	close(arg.pair[1]);
        if ((modef & (FMODE_READABLE|FMODE_WRITABLE)) == (FMODE_READABLE|FMODE_WRITABLE)) {
            close(arg.write_pair[0]);
            close(arg.write_pair[1]);
        }
	errno = e;
	rb_sys_fail(cmd);
    }
    if ((modef & FMODE_READABLE) && (modef & FMODE_WRITABLE)) {
        close(arg.pair[1]);
        fd = arg.pair[0];
        close(arg.write_pair[0]);
        write_fd = arg.write_pair[1];
    }
    else if (modef & FMODE_READABLE) {
        close(arg.pair[1]);
        fd = arg.pair[0];
    }
    else {
        close(arg.pair[0]);
        fd = arg.pair[1];
    }
#elif defined(_WIN32)
    if (argc) {
	volatile VALUE argbuf;
	char **args;
	int i;

	if (argc >= FIXNUM_MAX / sizeof(char *)) {
	    rb_raise(rb_eArgError, "too many arguments");
	}
	argbuf = rb_str_tmp_new((argc+1) * sizeof(char *));
	args = (void *)RSTRING_PTR(argbuf);
	for (i = 0; i < argc; ++i) {
	    args[i] = StringValueCStr(argv[i]);
	}
	args[i] = NULL;
	exename = cmd;
	cmdbuf = rb_str_tmp_new(rb_w32_argv_size(args));
	cmd = rb_w32_join_argv(RSTRING_PTR(cmdbuf), args);
	rb_str_resize(argbuf, 0);
    }
    if (eargp) {
	rb_exec_arg_fixup(eargp);
	rb_run_exec_options(eargp, &sarg);
    }
    while ((pid = rb_w32_pipe_exec(cmd, exename, openmode, &fd, &write_fd)) == -1) {
	/* exec failed */
	switch (errno) {
	  case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
	    rb_thread_sleep(1);
	    break;
	  default:
	    if (eargp)
		rb_run_exec_options(&sarg, NULL);
	    rb_sys_fail(cmd);
	    break;
	}
    }
    if (eargp)
	rb_run_exec_options(&sarg, NULL);
#else
    if (argc) {
	prog = rb_ary_join(rb_ary_new4(argc, argv), rb_str_new2(" "));
	cmd = StringValueCStr(prog);
    }
    if (eargp) {
	rb_exec_arg_fixup(eargp);
	rb_run_exec_options(eargp, &sarg);
    }
    fp = popen(cmd, mode);
    if (eargp)
	rb_run_exec_options(&sarg, NULL);
    if (!fp) rb_sys_fail(RSTRING_PTR(prog));
    fd = fileno(fp);
#endif

    port = io_alloc(rb_cIO);
    MakeOpenFile(port, fptr);
    fptr->fd = fd;
    fptr->stdio_file = fp;
    fptr->mode = modef | FMODE_SYNC|FMODE_DUPLEX;
    rb_io_mode_enc(fptr, mode);
    fptr->pid = pid;

    if (0 <= write_fd) {
        write_port = io_alloc(rb_cIO);
        MakeOpenFile(write_port, write_fptr);
        write_fptr->fd = write_fd;
        write_fptr->mode = (modef & ~FMODE_READABLE)| FMODE_SYNC|FMODE_DUPLEX;
        fptr->mode &= ~FMODE_WRITABLE;
        fptr->tied_io_for_writing = write_port;
        rb_ivar_set(port, rb_intern("@tied_io_for_writing"), write_port);
    }

#if defined (__CYGWIN__) || !defined(HAVE_FORK)
    fptr->finalize = pipe_finalize;
    pipe_add_fptr(fptr);
#endif
    return port;
}

static VALUE
pipe_open_v(int argc, VALUE *argv, const char *mode)
{
    VALUE prog;
    struct rb_exec_arg earg;
    prog = rb_exec_arg_init(argc, argv, Qfalse, &earg);
    return pipe_open(&earg, prog, mode);
}

static VALUE
pipe_open_s(VALUE prog, const char *mode)
{
    const char *cmd = RSTRING_PTR(prog);
    int argc = 1;
    VALUE *argv = &prog;
    struct rb_exec_arg earg;

    if (RSTRING_LEN(prog) == 1 && cmd[0] == '-') {
#if !defined(HAVE_FORK)
	rb_raise(rb_eNotImpError,
		 "fork() function is unimplemented on this machine");
#endif
        return pipe_open(0, 0, mode);
    }

    rb_exec_arg_init(argc, argv, Qtrue, &earg);
    return pipe_open(&earg, prog, mode);
}

/*
 *  call-seq:
 *     IO.popen(cmd, mode="r")               => io
 *     IO.popen(cmd, mode="r") {|io| block } => obj
 *
 *  Runs the specified command as a subprocess; the subprocess's
 *  standard input and output will be connected to the returned
 *  <code>IO</code> object.  If _cmd_ is a +String+
 *  ``<code>-</code>'', then a new instance of Ruby is started as the
 *  subprocess.  If <i>cmd</i> is an +Array+ of +String+, then it will
 *  be used as the subprocess's +argv+ bypassing a shell.
 *  The array can contains a hash at first for environments and
 *  a hash at last for options similar to <code>spawn</code>.  The default
 *  mode for the new file object is ``r'', but <i>mode</i> may be set
 *  to any of the modes listed in the description for class IO.
 *
 *  Raises exceptions which <code>IO::pipe</code> and
 *  <code>Kernel::system</code> raise.
 *
 *  If a block is given, Ruby will run the command as a child connected
 *  to Ruby with a pipe. Ruby's end of the pipe will be passed as a
 *  parameter to the block.
 *  At the end of block, Ruby close the pipe and sets <code>$?</code>.
 *  In this case <code>IO::popen</code> returns
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
 *     puts "Parent is #{Process.pid}"
 *     IO.popen("date") { |f| puts f.gets }
 *     IO.popen("-") {|f| $stderr.puts "#{Process.pid} is here, f is #{f}"}
 *     p $?
 *     IO.popen(%w"sed -e s|^|<foo>| -e s&$&;zot;&", "r+") {|f|
 *       f.puts "bar"; f.close_write; puts f.gets
 *     }
 *
 *  <em>produces:</em>
 *
 *     ["Linux\n"]
 *     Parent is 26166
 *     Wed Apr  9 08:53:52 CDT 2003
 *     26169 is here, f is
 *     26166 is here, f is #<IO:0x401b3d44>
 *     #<Process::Status: pid=26166,exited(0)>
 *     <foo>bar;zot;
 */

static VALUE
rb_io_s_popen(int argc, VALUE *argv, VALUE klass)
{
    const char *mode;
    VALUE pname, pmode, port, tmp;

    if (rb_scan_args(argc, argv, "11", &pname, &pmode) == 1) {
	mode = "r";
    }
    else if (FIXNUM_P(pmode)) {
	mode = rb_io_modenum_mode(FIX2INT(pmode));
    }
    else {
	mode = StringValueCStr(pmode);
    }
    tmp = rb_check_array_type(pname);
    if (!NIL_P(tmp)) {
	tmp = rb_ary_dup(tmp);
	RBASIC(tmp)->klass = 0;
	port = pipe_open_v(RARRAY_LEN(tmp), RARRAY_PTR(tmp), mode);
	rb_ary_clear(tmp);
    }
    else {
	SafeStringValue(pname);
	port = pipe_open_s(pname, mode);
    }
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
    RBASIC(port)->klass = klass;
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, port, io_close, port);
    }
    return port;
}

static void
io_set_encoding(VALUE io, VALUE opt)
{
    rb_io_t *fptr;
    VALUE encoding=Qnil, extenc=Qnil, intenc=Qnil;
    if (!NIL_P(opt)) {
	VALUE v;
	v = rb_hash_aref(opt, sym_encoding);
	if (!NIL_P(v)) encoding = v;
	v = rb_hash_aref(opt, sym_extenc);
	if (!NIL_P(v)) extenc = v;
	v = rb_hash_aref(opt, sym_intenc);
	if (!NIL_P(v)) intenc = v;
    }
    if (!NIL_P(extenc)) {
	rb_encoding *extencoding = rb_to_encoding(extenc);
	GetOpenFile(io, fptr);
	if (!NIL_P(encoding)) {
	    rb_warn("Ignoring encoding parameter '%s': external_encoding is used",
		    RSTRING_PTR(encoding));
	}
	if (!NIL_P(intenc)) {
	    rb_encoding *intencoding = rb_to_encoding(intenc);
	    if (extencoding == intencoding) {
		rb_warn("Ignoring internal encoding '%s': it is identical to external encoding '%s'",
			RSTRING_PTR(rb_inspect(intenc)),
			RSTRING_PTR(rb_inspect(extenc)));
	    }
	    else {
		fptr->enc2 = intencoding;
	    }
	}
	fptr->enc = extencoding;
    }
    else {
	if (!NIL_P(intenc)) {
	    rb_raise(rb_eArgError, "External encoding must be specified when internal encoding is given");
	}
	if (!NIL_P(encoding)) {
	    GetOpenFile(io, fptr);
	    mode_enc(fptr, StringValueCStr(encoding));
	}
    }
}

static VALUE
rb_open_file(int argc, VALUE *argv, VALUE io)
{
    VALUE opt, fname, vmode, perm;
    const char *mode;
    int flags;
    unsigned int fmode;

    opt = rb_check_convert_type(argv[argc-1], T_HASH, "Hash", "to_hash");
    if (!NIL_P(opt)) {
	VALUE v;
	v = rb_hash_aref(opt, sym_mode);
	if (!NIL_P(v)) vmode = v;
	v = rb_hash_aref(opt, sym_perm);
	if (!NIL_P(v)) perm = v;
	argc -= 1;
    }

    rb_scan_args(argc, argv, "12", &fname, &vmode, &perm);
#if defined _WIN32 || defined __APPLE__
    {
	static rb_encoding *fs_encoding;
	rb_encoding *fname_encoding = rb_enc_get(fname);
	if (!fs_encoding)
	    fs_encoding = rb_filesystem_encoding();
	if (rb_usascii_encoding() != fname_encoding
	    && rb_ascii8bit_encoding() != fname_encoding
#if defined __APPLE__
	    && rb_utf8_encoding() != fname_encoding
#endif
	    && fs_encoding != fname_encoding) {
	    static VALUE fs_enc;
	    if (!fs_enc)
		fs_enc = rb_enc_from_encoding(fs_encoding);
	    fname = rb_str_transcode(fname, fs_enc);
	}
    }
#endif
    FilePathValue(fname);

    if (FIXNUM_P(vmode) || !NIL_P(perm)) {
	if (FIXNUM_P(vmode)) {
	    flags = FIX2INT(vmode);
	}
	else {
	    SafeStringValue(vmode);
	    flags = rb_io_mode_modenum(StringValueCStr(vmode));
	}
	fmode = NIL_P(perm) ? 0666 :  NUM2UINT(perm);

	rb_file_sysopen_internal(io, RSTRING_PTR(fname), flags, fmode);
    }
    else {
	mode = NIL_P(vmode) ? "r" : StringValueCStr(vmode);
	rb_file_open_internal(io, RSTRING_PTR(fname), mode);
    }

    io_set_encoding(io, opt);
    return io;
}

/*
 *  call-seq:
 *     IO.open(fd, mode_string="r" )               => io
 *     IO.open(fd, mode_string="r" ) {|io| block } => obj
 *
 *  With no associated block, <code>open</code> is a synonym for
 *  <code>IO::new</code>. If the optional code block is given, it will
 *  be passed <i>io</i> as an argument, and the IO object will
 *  automatically be closed when the block terminates. In this instance,
 *  <code>IO::open</code> returns the value of the block.
 *
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
 *     IO.sysopen(path, [mode, [perm]])  => fixnum
 *
 *  Opens the given path, returning the underlying file descriptor as a
 *  <code>Fixnum</code>.
 *
 *     IO.sysopen("testfile")   #=> 3
 *
 */

static VALUE
rb_io_s_sysopen(int argc, VALUE *argv)
{
    VALUE fname, vmode, perm;
    int flags, fd;
    unsigned int fmode;
    char *path;

    rb_scan_args(argc, argv, "12", &fname, &vmode, &perm);
    FilePathValue(fname);

    if (NIL_P(vmode)) flags = O_RDONLY;
    else if (FIXNUM_P(vmode)) flags = FIX2INT(vmode);
    else {
	SafeStringValue(vmode);
	flags = rb_io_mode_modenum(StringValueCStr(vmode));
    }
    if (NIL_P(perm)) fmode = 0666;
    else             fmode = NUM2UINT(perm);

    RB_GC_GUARD(fname) = rb_str_new4(fname);
    path = RSTRING_PTR(fname);
    fd = rb_sysopen(path, flags, fmode);
    return INT2NUM(fd);
}

/*
 *  call-seq:
 *     open(path [, mode_enc [, perm]] )                => io or nil
 *     open(path [, mode_enc [, perm]] ) {|io| block }  => obj
 *
 *  Creates an <code>IO</code> object connected to the given stream,
 *  file, or subprocess.
 *
 *  If <i>path</i> does not start with a pipe character
 *  (``<code>|</code>''), treat it as the name of a file to open using
 *  the specified mode (defaulting to ``<code>r</code>'').
 *
 *  The mode_enc is
 *  either a string or an integer.  If it is an integer, it must be
 *  bitwise-or of open(2) flags, such as File::RDWR or File::EXCL.
 *  If it is a string, it is either "mode", "mode:ext_enc", or
 *  "mode:ext_enc:int_enc".
 *  The mode is one of the following:
 *
 *   r: read (default)
 *   w: write
 *   a: append
 *
 *  The mode can be followed by "b" (means binary-mode), or "+"
 *  (means both reading and writing allowed) or both.
 *  If ext_enc (external encoding) is specified,
 *  read string will be tagged by the encoding in reading,
 *  and output string will be converted
 *  to the specified encoding in writing.
 *  If two encoding names,
 *  ext_enc and int_enc (external encoding and internal encoding),
 *  are specified, the read string is converted from ext_enc
 *  to int_enc then tagged with the int_enc in read mode,
 *  and in write mode, the output string will be
 *  converted from int_enc to ext_enc before writing.
 *
 *  If a file is being created, its initial permissions may be
 *  set using the integer third parameter.
 *
 *  If a block is specified, it will be invoked with the
 *  <code>File</code> object as a parameter, and the file will be
 *  automatically closed when the block terminates. The call
 *  returns the value of the block.
 *
 *  If <i>path</i> starts with a pipe character, a subprocess is
 *  created, connected to the caller by a pair of pipes. The returned
 *  <code>IO</code> object may be used to write to the standard input
 *  and read from the standard output of this subprocess. If the command
 *  following the ``<code>|</code>'' is a single minus sign, Ruby forks,
 *  and this subprocess is connected to the parent. In the subprocess,
 *  the <code>open</code> call returns <code>nil</code>. If the command
 *  is not ``<code>-</code>'', the subprocess runs the command. If a
 *  block is associated with an <code>open("|-")</code> call, that block
 *  will be run twice---once in the parent and once in the child. The
 *  block parameter will be an <code>IO</code> object in the parent and
 *  <code>nil</code> in the child. The parent's <code>IO</code> object
 *  will be connected to the child's <code>$stdin</code> and
 *  <code>$stdout</code>. The subprocess will be terminated at the end
 *  of the block.
 *
 *     open("testfile") do |f|
 *       print f.gets
 *     end
 *
 *  <em>produces:</em>
 *
 *     This is line one
 *
 *  Open a subprocess and read its output:
 *
 *     cmd = open("|date")
 *     print cmd.gets
 *     cmd.close
 *
 *  <em>produces:</em>
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
 *  <em>produces:</em>
 *
 *     Got: in Child
 *
 *  Open a subprocess using a block to receive the I/O object:
 *
 *     open("|-") do |f|
 *       if f == nil
 *         puts "in Child"
 *       else
 *         puts "Got: #{f.gets}"
 *       end
 *     end
 *
 *  <em>produces:</em>
 *
 *     Got: in Child
 */

static VALUE
rb_f_open(int argc, VALUE *argv)
{
    ID to_open = 0;
    int redirect = Qfalse;

    if (argc >= 1) {
	CONST_ID(to_open, "to_open");
	if (rb_respond_to(argv[0], to_open)) {
	    redirect = Qtrue;
	}
	else {
	    VALUE tmp = argv[0];
	    FilePathValue(tmp);
	    if (NIL_P(tmp)) {
		redirect = Qtrue;
	    }
	    else {
		char *str = StringValuePtr(tmp);
		if (str && str[0] == '|') {
		    argv[0] = rb_str_new(str+1, RSTRING_LEN(tmp)-1);
		    OBJ_INFECT(argv[0], tmp);
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
rb_io_open(const char *fname, const char *mode)
{
    if (fname[0] == '|') {
	VALUE cmd = rb_str_new2(fname+1);
	return pipe_open_s(cmd, mode);
    }
    else {
	return rb_file_open(fname, mode);
    }
}

static VALUE
rb_io_open_with_args(int argc, VALUE *argv)
{
    const char *mode;
    VALUE pname, pmode;

    if (rb_scan_args(argc, argv, "11", &pname, &pmode) == 1) {
	mode = "r";
    }
    else if (FIXNUM_P(pmode)) {
	mode = rb_io_modenum_mode(FIX2INT(pmode));
    }
    else {
	mode = StringValueCStr(pmode);
    }
    return rb_io_open(StringValueCStr(pname), mode);
}

static VALUE
io_reopen(VALUE io, VALUE nfile)
{
    rb_io_t *fptr, *orig;
    int fd, fd2;
    off_t pos = 0;

    nfile = rb_io_get_io(nfile);
    if (rb_safe_level() >= 4 &&
       	(!OBJ_UNTRUSTED(io) || !OBJ_UNTRUSTED(nfile))) {
	rb_raise(rb_eSecurityError, "Insecure: can't reopen");
    }
    GetOpenFile(io, fptr);
    GetOpenFile(nfile, orig);

    if (fptr == orig) return io;
    if (IS_PREP_STDIO(fptr)) {
        if ((fptr->stdio_file == stdin && !(orig->mode & FMODE_READABLE)) ||
            (fptr->stdio_file == stdout && !(orig->mode & FMODE_WRITABLE)) ||
            (fptr->stdio_file == stderr && !(orig->mode & FMODE_WRITABLE))) {
	    rb_raise(rb_eArgError,
		     "%s can't change access mode from \"%s\" to \"%s\"",
		     PREP_STDIO_NAME(fptr), rb_io_flags_mode(fptr->mode),
		     rb_io_flags_mode(orig->mode));
	}
    }
    if (orig->mode & FMODE_READABLE) {
	pos = io_tell(orig);
    }
    if (orig->mode & FMODE_WRITABLE) {
	io_fflush(orig);
    }
    if (fptr->mode & FMODE_WRITABLE) {
	io_fflush(fptr);
    }

    /* copy rb_io_t structure */
    fptr->mode = orig->mode | (fptr->mode & FMODE_PREP);
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (fptr->path) free(fptr->path);
    if (orig->path) fptr->path = strdup(orig->path);
    else fptr->path = 0;
    fptr->finalize = orig->finalize;

    fd = fptr->fd;
    fd2 = orig->fd;
    if (fd != fd2) {
	if (IS_PREP_STDIO(fptr)) {
	    /* need to keep stdio objects */
	    if (dup2(fd2, fd) < 0)
		rb_sys_fail(orig->path);
	}
	else {
            if (fptr->stdio_file)
                fclose(fptr->stdio_file);
            else
                close(fptr->fd);
            fptr->stdio_file = 0;
            fptr->fd = -1;
	    if (dup2(fd2, fd) < 0)
		rb_sys_fail(orig->path);
            fptr->fd = fd;
	}
	rb_thread_fd_close(fd);
	if ((orig->mode & FMODE_READABLE) && pos >= 0) {
	    if (io_seek(fptr, pos, SEEK_SET) < 0) {
		rb_sys_fail(fptr->path);
	    }
	    if (io_seek(orig, pos, SEEK_SET) < 0) {
		rb_sys_fail(orig->path);
	    }
	}
    }

    if (fptr->mode & FMODE_BINMODE) {
	rb_io_binmode(io);
    }

    RBASIC(io)->klass = rb_obj_class(nfile);
    return io;
}

/*
 *  call-seq:
 *     ios.reopen(other_IO)         => ios
 *     ios.reopen(path, mode_str)   => ios
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
    VALUE fname, nmode;
    const char *mode;
    rb_io_t *fptr;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "11", &fname, &nmode) == 1) {
	VALUE tmp = rb_io_check_io(fname);
	if (!NIL_P(tmp)) {
	    return io_reopen(file, tmp);
	}
    }

    FilePathValue(fname);
    rb_io_taint_check(file);
    fptr = RFILE(file)->fptr;
    if (!fptr) {
	fptr = RFILE(file)->fptr = ALLOC(rb_io_t);
	MEMZERO(fptr, rb_io_t, 1);
    }

    if (!NIL_P(nmode)) {
	int flags = rb_io_mode_flags(StringValueCStr(nmode));
	if (IS_PREP_STDIO(fptr) &&
            ((fptr->mode & FMODE_READWRITE) & (flags & FMODE_READWRITE)) !=
            (fptr->mode & FMODE_READWRITE)) {
	    rb_raise(rb_eArgError,
		     "%s can't change access mode from \"%s\" to \"%s\"",
		     PREP_STDIO_NAME(fptr), rb_io_flags_mode(fptr->mode),
		     rb_io_flags_mode(flags));
	}
	fptr->mode = flags;
	rb_io_mode_enc(fptr, StringValueCStr(nmode));
    }

    if (fptr->path) {
	free(fptr->path);
	fptr->path = 0;
    }

    fptr->path = strdup(StringValueCStr(fname));
    mode = rb_io_flags_mode(fptr->mode);
    if (fptr->fd < 0) {
        fptr->fd = rb_sysopen(fptr->path, rb_io_mode_modenum(mode), 0666);
	fptr->stdio_file = 0;
	return file;
    }

    if (fptr->mode & FMODE_WRITABLE) {
        io_fflush(fptr);
    }
    fptr->rbuf_off = fptr->rbuf_len = 0;

    if (fptr->stdio_file) {
        if (freopen(fptr->path, mode, fptr->stdio_file) == 0) {
            rb_sys_fail(fptr->path);
        }
        fptr->fd = fileno(fptr->stdio_file);
#ifdef USE_SETVBUF
        if (setvbuf(fptr->stdio_file, NULL, _IOFBF, 0) != 0)
            rb_warn("setvbuf() can't be honoured for %s", fptr->path);
#endif
    }
    else {
        if (close(fptr->fd) < 0)
            rb_sys_fail(fptr->path);
        fptr->fd = -1;
        fptr->fd = rb_sysopen(fptr->path, rb_io_mode_modenum(mode), 0666);
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

    io = rb_io_get_io(io);
    if (dest == io) return dest;
    GetOpenFile(io, orig);
    MakeOpenFile(dest, fptr);

    rb_io_flush(io);

    /* copy rb_io_t structure */
    fptr->mode = orig->mode & ~FMODE_PREP;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (orig->path) fptr->path = strdup(orig->path);
    fptr->finalize = orig->finalize;

    fd = ruby_dup(orig->fd);
    fptr->fd = fd;
    io_seek(fptr, io_tell(orig), SEEK_SET);
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
 *     ios.printf(format_string [, obj, ...] )   => nil
 *
 *  Formats and writes to <em>ios</em>, converting parameters under
 *  control of the format string. See <code>Kernel#sprintf</code>
 *  for details.
 */

VALUE
rb_io_printf(int argc, VALUE *argv, VALUE out)
{
    rb_io_write(out, rb_f_sprintf(argc, argv));
    return Qnil;
}

/*
 *  call-seq:
 *     printf(io, string [, obj ... ] )    => nil
 *     printf(string [, obj ... ] )        => nil
 *
 *  Equivalent to:
 *     io.write(sprintf(string, obj, ...)
 *  or
 *     $stdout.write(sprintf(string, obj, ...)
 */

static VALUE
rb_f_printf(int argc, VALUE *argv)
{
    VALUE out;

    if (argc == 0) return Qnil;
    if (TYPE(argv[0]) == T_STRING) {
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
 *     ios.print()             => nil
 *     ios.print(obj, ...)     => nil
 *
 *  Writes the given object(s) to <em>ios</em>. The stream must be
 *  opened for writing. If the output record separator (<code>$\\</code>)
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
rb_io_print(int argc, VALUE *argv, VALUE out)
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
	rb_io_write(out, argv[i]);
	if (!NIL_P(rb_output_fs)) {
	    rb_io_write(out, rb_output_fs);
	}
    }
    if (argc > 0 && !NIL_P(rb_output_rs)) {
	rb_io_write(out, rb_output_rs);
    }

    return Qnil;
}

/*
 *  call-seq:
 *     print(obj, ...)    => nil
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
rb_f_print(int argc, VALUE *argv)
{
    rb_io_print(argc, argv, rb_stdout);
    return Qnil;
}

/*
 *  call-seq:
 *     ios.putc(obj)    => obj
 *
 *  If <i>obj</i> is <code>Numeric</code>, write the character whose
 *  code is <i>obj</i>, otherwise write the first character of the
 *  string representation of  <i>obj</i> to <em>ios</em>.
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
    char c = NUM2CHR(ch);

    rb_io_write(io, rb_str_new(&c, 1));
    return ch;
}

/*
 *  call-seq:
 *     putc(int)   => int
 *
 *  Equivalent to:
 *
 *    $stdout.putc(int)
 */

static VALUE
rb_f_putc(VALUE recv, VALUE ch)
{
    if (recv == rb_stdout) {
	return rb_io_putc(recv, ch);
    }
    return rb_funcall2(rb_stdout, rb_intern("putc"), 1, &ch);
}

static VALUE
io_puts_ary(VALUE ary, VALUE out, int recur)
{
    VALUE tmp;
    long i;

    if (recur) {
	tmp = rb_str_new2("[...]");
	rb_io_puts(1, &tmp, out);
	return Qnil;
    }
    for (i=0; i<RARRAY_LEN(ary); i++) {
	tmp = RARRAY_PTR(ary)[i];
	rb_io_puts(1, &tmp, out);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     ios.puts(obj, ...)    => nil
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
rb_io_puts(int argc, VALUE *argv, VALUE out)
{
    int i;
    VALUE line;

    /* if no argument given, print newline. */
    if (argc == 0) {
	rb_io_write(out, rb_default_rs);
	return Qnil;
    }
    for (i=0; i<argc; i++) {
	line = rb_check_array_type(argv[i]);
	if (!NIL_P(line)) {
	    rb_exec_recursive(io_puts_ary, line, out);
	    continue;
	}
	line = rb_obj_as_string(argv[i]);
	rb_io_write(out, line);
	if (RSTRING_LEN(line) == 0 ||
            RSTRING_PTR(line)[RSTRING_LEN(line)-1] != '\n') {
	    rb_io_write(out, rb_default_rs);
	}
    }

    return Qnil;
}

/*
 *  call-seq:
 *     puts(obj, ...)    => nil
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
    rb_str_buf_append(str, rb_default_rs);
    rb_io_write(rb_stdout, str);
}

/*
 *  call-seq:
 *     p(obj)              => obj
 *     p(obj1, obj2, ...)  => [obj, ...]
 *     p()                 => nil
 *
 *  For each object, directly writes
 *  _obj_.+inspect+ followed by the current output
 *  record separator to the program's standard output.
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
    if (TYPE(rb_stdout) == T_FILE) {
	rb_io_flush(rb_stdout);
    }
    return ret;
}

/*
 *  call-seq:
 *     obj.display(port=$>)    => nil
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
	fwrite(mesg, sizeof(char), len, stderr);
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

static void
must_respond_to(ID mid, VALUE val, ID id)
{
    if (!rb_respond_to(val, mid)) {
	rb_raise(rb_eTypeError, "%s must have %s method, %s given",
		 rb_id2name(id), rb_id2name(mid),
		 rb_obj_classname(val));
    }
}

static void
stdout_setter(VALUE val, ID id, VALUE *variable)
{
    must_respond_to(id_write, val, id);
    *variable = val;
}

static VALUE
prep_io(int fd, int mode, VALUE klass, const char *path)
{
    rb_io_t *fp;
    VALUE io = io_alloc(klass);

    MakeOpenFile(io, fp);
    fp->fd = fd;
#ifdef __CYGWIN__
    if (!isatty(fd)) {
	mode |= O_BINARY;
	setmode(fd, O_BINARY);
    }
#endif
    fp->mode = mode;
    io_check_tty(fp);
    if (path) fp->path = strdup(path);

    return io;
}

VALUE
rb_io_fdopen(int fd, int mode, const char *path)
{
    VALUE klass = rb_cIO;

    if (path && strcmp(path, "-")) klass = rb_cFile;
    return prep_io(fd, rb_io_modenum_flags(mode), klass, path);
}

static VALUE
prep_stdio(FILE *f, int mode, VALUE klass, const char *path)
{
    rb_io_t *fptr;
    VALUE io = prep_io(fileno(f), mode|FMODE_PREP, klass, path);

    GetOpenFile(io, fptr);
    fptr->stdio_file = f;

    return io;
}

FILE *
rb_io_stdio_file(rb_io_t *fptr)
{
    if (!fptr->stdio_file) {
        fptr->stdio_file = rb_fdopen(fptr->fd, rb_io_flags_mode(fptr->mode));
    }
    return fptr->stdio_file;
}

/*
 *  call-seq:
 *     IO.new(fd, mode)   => io
 *
 *  Returns a new <code>IO</code> object (a stream) for the given
 *  <code>IO</code> object or integer file descriptor and mode
 *  string. See also <code>IO#fileno</code> and
 *  <code>IO::for_fd</code>.
 *
 *     puts IO.new($stdout).fileno # => 1
 *
 *     a = IO.new(2,"w")      # '2' is standard error
 *     $stderr.puts "Hello"
 *     a.puts "World"
 *
 *  <em>produces:</em>
 *
 *     Hello
 *     World
 */

static VALUE
rb_io_initialize(int argc, VALUE *argv, VALUE io)
{
    VALUE fnum, mode, orig;
    rb_io_t *fp, *ofp = NULL;
    int fd, fmode, flags = O_RDONLY;

    rb_secure(4);
    rb_scan_args(argc, argv, "11", &fnum, &mode);
    if (argc == 2) {
	if (FIXNUM_P(mode)) {
	    flags = FIX2LONG(mode);
	}
	else {
	    SafeStringValue(mode);
	    flags = rb_io_mode_modenum(StringValueCStr(mode));
	}
    }
    orig = rb_io_check_io(fnum);
    if (NIL_P(orig)) {
	fd = NUM2INT(fnum);
        UPDATE_MAXFD(fd);
	if (argc != 2) {
#if defined(HAVE_FCNTL) && defined(F_GETFL)
	    flags = fcntl(fd, F_GETFL);
	    if (flags == -1) rb_sys_fail(0);
#endif
	}
	MakeOpenFile(io, fp);
        fp->fd = fd;
	fp->mode = rb_io_modenum_flags(flags);
        io_check_tty(fp);
    }
    else if (RFILE(io)->fptr) {
	rb_raise(rb_eRuntimeError, "reinitializing IO");
    }
    else {
	GetOpenFile(orig, ofp);
	if (ofp->refcnt == LONG_MAX) {
	    VALUE s = rb_inspect(orig);
	    rb_raise(rb_eIOError, "too many shared IO for %s", StringValueCStr(s));
	}
	if (argc == 2) {
	    fmode = rb_io_modenum_flags(flags);
	    if ((ofp->mode ^ fmode) & (FMODE_READWRITE|FMODE_BINMODE)) {
		if (FIXNUM_P(mode)) {
		    rb_raise(rb_eArgError, "incompatible mode 0%o", flags);
		}
		else {
		    rb_raise(rb_eArgError, "incompatible mode \"%s\"", RSTRING_PTR(mode));
		}
	    }
	}
	ofp->refcnt++;
	RFILE(io)->fptr = ofp;
    }

    return io;
}


/*
 *  call-seq:
 *     File.new(filename, mode="r")            => file
 *     File.new(filename [, mode [, perm]])    => file
 *

 *  Opens the file named by _filename_ according to
 *  _mode_ (default is ``r'') and returns a new
 *  <code>File</code> object. See the description of class +IO+ for
 *  a description of _mode_. The file mode may optionally be
 *  specified as a +Fixnum+ by _or_-ing together the
 *  flags (O_RDONLY etc, again described under +IO+). Optional
 *  permission bits may be given in _perm_. These mode and permission
 *  bits are platform dependent; on Unix systems, see
 *  <code>open(2)</code> for details.
 *
 *     f = File.new("testfile", "r")
 *     f = File.new("newfile",  "w+")
 *     f = File.new("newfile", File::CREAT|File::TRUNC|File::RDWR, 0644)
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

/*
 *  call-seq:
 *     IO.new(fd, mode_string)   => io
 *
 *  Returns a new <code>IO</code> object (a stream) for the given
 *  integer file descriptor and mode string. See also
 *  <code>IO#fileno</code> and <code>IO::for_fd</code>.
 *
 *     a = IO.new(2,"w")      # '2' is standard error
 *     $stderr.puts "Hello"
 *     a.puts "World"
 *
 *  <em>produces:</em>
 *
 *     Hello
 *     World
 */

static VALUE
rb_io_s_new(int argc, VALUE *argv, VALUE klass)
{
    if (rb_block_given_p()) {
	const char *cname = rb_class2name(klass);

	rb_warn("%s::new() does not take block; use %s::open() instead",
		cname, cname);
    }
    return rb_class_new_instance(argc, argv, klass);
}


/*
 *  call-seq:
 *     IO.for_fd(fd, mode)    => io
 *
 *  Synonym for <code>IO::new</code>.
 *
 */

static VALUE
rb_io_s_for_fd(int argc, VALUE *argv, VALUE klass)
{
    VALUE io = rb_obj_alloc(klass);
    rb_io_initialize(argc, argv, io);
    return io;
}

static void
argf_mark(void *ptr)
{
    struct argf *p = ptr;
    rb_gc_mark(p->filename);
    rb_gc_mark(p->current_file);
    rb_gc_mark(p->lineno);
    rb_gc_mark(p->argv);
}

static void
argf_free(void *ptr)
{
    struct argf *p = ptr;
    free(p->inplace);
}

static inline void
argf_init(struct argf *p, VALUE v)
{
    p->filename = Qnil;
    p->current_file = Qnil;
    p->lineno = Qnil;
    p->argv = v;
}

static VALUE
argf_alloc(VALUE klass)
{
    struct argf *p;
    VALUE argf = Data_Make_Struct(klass, struct argf, argf_mark, argf_free, p);

    argf_init(p, Qnil);
    return argf;
}

#undef rb_argv
#define filename          ARGF.filename
#define current_file      ARGF.current_file
#define gets_lineno       ARGF.gets_lineno
#define init_p            ARGF.init_p
#define next_p            ARGF.next_p
#define lineno            ARGF.lineno
#define ruby_inplace_mode ARGF.inplace
#define argf_binmode      ARGF.binmode
#define argf_enc          ARGF.enc
#define argf_enc2         ARGF.enc2
#define rb_argv           ARGF.argv

static VALUE
argf_initialize(VALUE argf, VALUE argv)
{
    memset(&ARGF, 0, sizeof(ARGF));
    argf_init(&ARGF, argv);

    return argf;
}

static VALUE
argf_initialize_copy(VALUE argf, VALUE orig)
{
    ARGF = argf_of(orig);
    rb_argv = rb_obj_dup(rb_argv);
    if (ARGF.inplace) {
	const char *inplace = ARGF.inplace;
	ARGF.inplace = 0;
	ARGF.inplace = ruby_strdup(inplace);
    }
    return argf;
}

static VALUE
argf_set_lineno(VALUE argf, VALUE val)
{
    gets_lineno = NUM2INT(val);
    lineno = INT2FIX(gets_lineno);
    return Qnil;
}

static VALUE
argf_lineno(VALUE argf)
{
    return lineno;
}

static VALUE
argf_forward(int argc, VALUE *argv, VALUE argf)
{
    return rb_funcall3(current_file, rb_frame_this_func(), argc, argv);
}

#define next_argv() argf_next_argv(argf)
#define ARGF_GENERIC_INPUT_P() \
    (current_file == rb_stdin && TYPE(current_file) != T_FILE)
#define ARGF_FORWARD(argc, argv) do {\
    if (ARGF_GENERIC_INPUT_P())\
	return argf_forward(argc, argv, argf);\
} while (0)
#define NEXT_ARGF_FORWARD(argc, argv) do {\
    if (!next_argv()) return Qnil;\
    ARGF_FORWARD(argc, argv);\
} while (0)

static void
argf_close(VALUE file)
{
    rb_funcall3(file, rb_intern("close"), 0, 0);
}

static int
argf_next_argv(VALUE argf)
{
    char *fn;
    rb_io_t *fptr;
    int stdout_binmode = 0;

    if (TYPE(rb_stdout) == T_FILE) {
        GetOpenFile(rb_stdout, fptr);
        if (fptr->mode & FMODE_BINMODE)
            stdout_binmode = 1;
    }

    if (init_p == 0) {
	if (!NIL_P(rb_argv) && RARRAY_LEN(rb_argv) > 0) {
	    next_p = 1;
	}
	else {
	    next_p = -1;
	}
	init_p = 1;
	gets_lineno = 0;
    }

    if (next_p == 1) {
	next_p = 0;
      retry:
	if (RARRAY_LEN(rb_argv) > 0) {
	    filename = rb_ary_shift(rb_argv);
	    fn = StringValueCStr(filename);
	    if (strlen(fn) == 1 && fn[0] == '-') {
		current_file = rb_stdin;
		if (ruby_inplace_mode) {
		    rb_warn("Can't do inplace edit for stdio; skipping");
		    goto retry;
		}
	    }
	    else {
		int fr = rb_sysopen(fn, O_RDONLY, 0);

		if (ruby_inplace_mode) {
		    struct stat st;
#ifndef NO_SAFE_RENAME
		    struct stat st2;
#endif
		    VALUE str;
		    int fw;

		    if (TYPE(rb_stdout) == T_FILE && rb_stdout != orig_stdout) {
			rb_io_close(rb_stdout);
		    }
		    fstat(fr, &st);
		    if (*ruby_inplace_mode) {
			str = rb_str_new2(fn);
#ifdef NO_LONG_FNAME
                        ruby_add_suffix(str, ruby_inplace_mode);
#else
			rb_str_cat2(str, ruby_inplace_mode);
#endif
#ifdef NO_SAFE_RENAME
			(void)close(fr);
			(void)unlink(RSTRING_PTR(str));
			(void)rename(fn, RSTRING_PTR(str));
			fr = rb_sysopen(RSTRING_PTR(str), O_RDONLY, 0);
#else
			if (rename(fn, RSTRING_PTR(str)) < 0) {
			    rb_warn("Can't rename %s to %s: %s, skipping file",
				    fn, RSTRING_PTR(str), strerror(errno));
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
			    rb_warn("Can't remove %s: %s, skipping file",
				    fn, strerror(errno));
			    close(fr);
			    goto retry;
			}
#endif
		    }
		    fw = rb_sysopen(fn, O_WRONLY|O_CREAT|O_TRUNC, 0666);
#ifndef NO_SAFE_RENAME
		    fstat(fw, &st2);
#ifdef HAVE_FCHMOD
		    fchmod(fw, st.st_mode);
#else
		    chmod(fn, st.st_mode);
#endif
		    if (st.st_uid!=st2.st_uid || st.st_gid!=st2.st_gid) {
			fchown(fw, st.st_uid, st.st_gid);
		    }
#endif
		    rb_stdout = prep_io(fw, FMODE_WRITABLE, rb_cFile, fn);
		    if (stdout_binmode) rb_io_binmode(rb_stdout);
		}
		current_file = prep_io(fr, FMODE_READABLE, rb_cFile, fn);
	    }
	    if (argf_binmode) rb_io_binmode(current_file);
	    if (argf_enc) {
		rb_io_t *fptr;

		GetOpenFile(current_file, fptr);
		fptr->enc = argf_enc;
		fptr->enc2 = argf_enc2;
	    }
	}
	else {
	    next_p = 1;
	    return Qfalse;
	}
    }
    else if (next_p == -1) {
	current_file = rb_stdin;
	filename = rb_str_new2("-");
	if (ruby_inplace_mode) {
	    rb_warn("Can't do inplace edit for stdio");
	    rb_stdout = orig_stdout;
	}
    }
    return Qtrue;
}

static VALUE
argf_getline(int argc, VALUE *argv, VALUE argf)
{
    VALUE line;

  retry:
    if (!next_argv()) return Qnil;
    if (ARGF_GENERIC_INPUT_P()) {
	line = rb_funcall3(current_file, rb_intern("gets"), argc, argv);
    }
    else {
	if (argc == 0 && rb_rs == rb_default_rs) {
	    line = rb_io_gets(current_file);
	}
	else {
	    line = rb_io_getline(argc, argv, current_file);
	}
	if (NIL_P(line) && next_p != -1) {
	    argf_close(current_file);
	    next_p = 1;
	    goto retry;
	}
    }
    if (!NIL_P(line)) {
	gets_lineno++;
	lineno = INT2FIX(gets_lineno);
    }
    return line;
}

static VALUE
argf_lineno_getter(ID id, VALUE *var)
{
    VALUE argf = *var;
    return lineno;
}

static void
argf_lineno_setter(VALUE val, ID id, VALUE *var)
{
    VALUE argf = *var;
    int n = NUM2INT(val);
    gets_lineno = n;
    lineno = INT2FIX(n);
}

static VALUE argf_gets(int, VALUE *, VALUE);

/*
 *  call-seq:
 *     gets(sep=$/)    => string or nil
 *     gets(limit)     => string or nil
 *     gets(sep,limit) => string or nil
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
 *  would not be longer than the given value.  If multiple filenames are
 *  present in +ARGV+, +gets(nil)+ will read the contents one file at a
 *  time.
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
    return rb_funcall2(argf, rb_intern("gets"), argc, argv);
}

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
    line = rb_io_gets(current_file);
    if (NIL_P(line) && next_p != -1) {
	rb_io_close(current_file);
	next_p = 1;
	goto retry;
    }
    rb_lastline_set(line);
    if (!NIL_P(line)) {
	gets_lineno++;
	lineno = INT2FIX(gets_lineno);
    }

    return line;
}

static VALUE argf_readline(int, VALUE *, VALUE);

/*
 *  call-seq:
 *     readline(sep=$/)     => string
 *     readline(limit)      => string
 *     readline(sep, limit) => string
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
 *     readlines(sep=$/)    => array
 *     readlines(limit)     => array
 *     readlines(sep,limit) => array
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

static VALUE
argf_readlines(int argc, VALUE *argv, VALUE argf)
{
    VALUE line, ary;

    ary = rb_ary_new();
    while (!NIL_P(line = argf_getline(argc, argv, argf))) {
	rb_ary_push(ary, line);
    }

    return ary;
}

/*
 *  call-seq:
 *     `cmd`    => string
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
    volatile VALUE port;
    VALUE result;
    rb_io_t *fptr;

    SafeStringValue(str);
    port = pipe_open_s(str, "r");
    if (NIL_P(port)) return rb_str_new(0,0);

    GetOpenFile(port, fptr);
    result = read_all(fptr, remain_size(fptr), Qnil);
    rb_io_close(port);

    return result;
}

#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif

static VALUE
select_internal(VALUE read, VALUE write, VALUE except, struct timeval *tp, rb_fdset_t *fds)
{
    VALUE res, list;
    fd_set *rp, *wp, *ep;
    rb_io_t *fptr;
    long i;
    int max = 0, n;
    int interrupt_flag = 0;
    int pending = 0;
    struct timeval timerec;

    if (!NIL_P(read)) {
	Check_Type(read, T_ARRAY);
	for (i=0; i<RARRAY_LEN(read); i++) {
	    GetOpenFile(rb_io_get_io(RARRAY_PTR(read)[i]), fptr);
	    rb_fd_set(fptr->fd, &fds[0]);
	    if (READ_DATA_PENDING(fptr)) { /* check for buffered data */
		pending++;
		rb_fd_set(fptr->fd, &fds[3]);
	    }
	    if (max < fptr->fd) max = fptr->fd;
	}
	if (pending) {		/* no blocking if there's buffered data */
	    timerec.tv_sec = timerec.tv_usec = 0;
	    tp = &timerec;
	}
	rp = rb_fd_ptr(&fds[0]);
    }
    else
	rp = 0;

    if (!NIL_P(write)) {
	Check_Type(write, T_ARRAY);
	for (i=0; i<RARRAY_LEN(write); i++) {
            VALUE write_io = GetWriteIO(rb_io_get_io(RARRAY_PTR(write)[i]));
	    GetOpenFile(write_io, fptr);
	    rb_fd_set(fptr->fd, &fds[1]);
	    if (max < fptr->fd) max = fptr->fd;
	}
	wp = rb_fd_ptr(&fds[1]);
    }
    else
	wp = 0;

    if (!NIL_P(except)) {
	Check_Type(except, T_ARRAY);
	for (i=0; i<RARRAY_LEN(except); i++) {
            VALUE io = rb_io_get_io(RARRAY_PTR(except)[i]);
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
	ep = rb_fd_ptr(&fds[2]);
    }
    else {
	ep = 0;
    }

    max++;

    n = rb_thread_select(max, rp, wp, ep, tp);
    if (n < 0) {
	rb_sys_fail(0);
    }
    if (!pending && n == 0) return Qnil; /* returns nil on timeout */

    res = rb_ary_new2(3);
    rb_ary_push(res, rp?rb_ary_new():rb_ary_new2(0));
    rb_ary_push(res, wp?rb_ary_new():rb_ary_new2(0));
    rb_ary_push(res, ep?rb_ary_new():rb_ary_new2(0));

    if (interrupt_flag == 0) {
	if (rp) {
	    list = RARRAY_PTR(res)[0];
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
	    list = RARRAY_PTR(res)[1];
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
	    list = RARRAY_PTR(res)[2];
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
    }

    return res;			/* returns an empty array on interrupt */
}

struct select_args {
    VALUE read, write, except;
    struct timeval *timeout;
    rb_fdset_t fdsets[4];
};

#ifdef HAVE_RB_FD_INIT
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

    for (i = 0; i < sizeof(p->fdsets) / sizeof(p->fdsets[0]); ++i)
	rb_fd_term(&p->fdsets[i]);
    return Qnil;
}
#endif

/*
 *  call-seq:
 *     IO.select(read_array
 *               [, write_array
 *               [, error_array
 *               [, timeout]]] ) =>  array  or  nil
 *
 *  See <code>Kernel#select</code>.
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

    for (i = 0; i < sizeof(args.fdsets) / sizeof(args.fdsets[0]); ++i)
	rb_fd_init(&args.fdsets[i]);

#ifdef HAVE_RB_FD_INIT
    return rb_ensure(select_call, (VALUE)&args, select_end, (VALUE)&args);
#else
    return select_internal(args.read, args.write, args.except,
			   args.timeout, args.fdsets);
#endif

}

#if !defined(MSDOS) && !defined(__human68k__)
static int
io_cntl(int fd, int cmd, long narg, int io_p)
{
    int retval;

#ifdef HAVE_FCNTL
    TRAP_BEG;
# if defined(__CYGWIN__)
    retval = io_p?ioctl(fd, cmd, (void*)narg):fcntl(fd, cmd, narg);
# else
    retval = io_p?ioctl(fd, cmd, narg):fcntl(fd, cmd, narg);
# endif
    TRAP_END;
#else
    if (!io_p) {
	rb_notimplement();
    }
    TRAP_BEG;
    retval = ioctl(fd, cmd, narg);
    TRAP_END;
#endif
    return retval;
}
#endif

static VALUE
rb_io_ctl(VALUE io, VALUE req, VALUE arg, int io_p)
{
#if !defined(MSDOS) && !defined(__human68k__)
    int cmd = NUM2ULONG(req);
    rb_io_t *fptr;
    long len = 0;
    long narg = 0;
    int retval;

    rb_secure(2);

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
	    arg = tmp;
#ifdef IOCPARM_MASK
#ifndef IOCPARM_LEN
#define IOCPARM_LEN(x)  (((x) >> 16) & IOCPARM_MASK)
#endif
#endif
#ifdef IOCPARM_LEN
	    len = IOCPARM_LEN(cmd);	/* on BSDish systems we're safe */
#else
	    len = 256;		/* otherwise guess at what's safe */
#endif
	    rb_str_modify(arg);

	    if (len <= RSTRING_LEN(arg)) {
		len = RSTRING_LEN(arg);
	    }
	    if (RSTRING_LEN(arg) < len) {
		rb_str_resize(arg, len+1);
	    }
	    RSTRING_PTR(arg)[len] = 17;	/* a little sanity check here */
	    narg = (long)RSTRING_PTR(arg);
	}
    }
    GetOpenFile(io, fptr);
    retval = io_cntl(fptr->fd, cmd, narg, io_p);
    if (retval < 0) rb_sys_fail(fptr->path);
    if (TYPE(arg) == T_STRING && RSTRING_PTR(arg)[len] != 17) {
	rb_raise(rb_eArgError, "return value overflowed string");
    }

    if (!io_p && cmd == F_SETFL) {
      if (narg & O_NONBLOCK) {
        fptr->mode |= FMODE_WSPLIT_INITIALIZED;
        fptr->mode &= ~FMODE_WSPLIT;
      }
      else {
        fptr->mode &= ~(FMODE_WSPLIT_INITIALIZED|FMODE_WSPLIT);
      }
    }

    return INT2NUM(retval);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}


/*
 *  call-seq:
 *     ios.ioctl(integer_cmd, arg)    => integer
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
    return rb_io_ctl(io, req, arg, 1);
}

/*
 *  call-seq:
 *     ios.fcntl(integer_cmd, arg)    => integer
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
#ifdef HAVE_FCNTL
    VALUE req, arg;

    rb_scan_args(argc, argv, "11", &req, &arg);
    return rb_io_ctl(io, req, arg, 0);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

/*
 *  call-seq:
 *     syscall(fixnum [, args...])   => integer
 *
 *  Calls the operating system function identified by _fixnum_,
 *  passing in the arguments, which must be either +String+
 *  objects, or +Integer+ objects that ultimately fit within
 *  a native +long+. Up to nine parameters may be passed (14
 *  on the Atari-ST). The function identified by _fixnum_ is system
 *  dependent. On some Unix systems, the numbers may be obtained from a
 *  header file called <code>syscall.h</code>.
 *
 *     syscall 4, 1, "hello\n", 6   # '4' is write(2) on our box
 *
 *  <em>produces:</em>
 *
 *     hello
 */

static VALUE
rb_f_syscall(int argc, VALUE *argv)
{
#if defined(HAVE_SYSCALL) && !defined(__CHECKER__)
#ifdef atarist
    unsigned long arg[14]; /* yes, we really need that many ! */
#else
    unsigned long arg[8];
#endif
    int retval = -1;
    int i = 1;
    int items = argc - 1;

    /* This probably won't work on machines where sizeof(long) != sizeof(int)
     * or where sizeof(long) != sizeof(char*).  But such machines will
     * not likely have syscall implemented either, so who cares?
     */

    rb_secure(2);
    if (argc == 0)
	rb_raise(rb_eArgError, "too few arguments for syscall");
    if (argc > sizeof(arg) / sizeof(arg[0]))
	rb_raise(rb_eArgError, "too many arguments for syscall");
    arg[0] = NUM2LONG(argv[0]); argv++;
    while (items--) {
	VALUE v = rb_check_string_type(*argv);

	if (!NIL_P(v)) {
	    StringValue(v);
	    rb_str_modify(v);
	    arg[i] = (unsigned long)StringValueCStr(v);
	}
	else {
	    arg[i] = (unsigned long)NUM2LONG(*argv);
	}
	argv++;
	i++;
    }
    TRAP_BEG;
    switch (argc) {
      case 1:
	retval = syscall(arg[0]);
	break;
      case 2:
	retval = syscall(arg[0],arg[1]);
	break;
      case 3:
	retval = syscall(arg[0],arg[1],arg[2]);
	break;
      case 4:
	retval = syscall(arg[0],arg[1],arg[2],arg[3]);
	break;
      case 5:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4]);
	break;
      case 6:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5]);
	break;
      case 7:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6]);
	break;
      case 8:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7]);
	break;
#ifdef atarist
      case 9:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8]);
	break;
      case 10:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9]);
	break;
      case 11:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9], arg[10]);
	break;
      case 12:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9], arg[10], arg[11]);
	break;
      case 13:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9], arg[10], arg[11], arg[12]);
	break;
      case 14:
	retval = syscall(arg[0],arg[1],arg[2],arg[3],arg[4],arg[5],arg[6],
	  arg[7], arg[8], arg[9], arg[10], arg[11], arg[12], arg[13]);
	break;
#endif /* atarist */
    }
    TRAP_END;
    if (retval < 0) rb_sys_fail(0);
    return INT2NUM(retval);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static VALUE
io_new_instance(VALUE args)
{
    return rb_class_new_instance(2, (VALUE*)args+1, *(VALUE*)args);
}

static void
io_encoding_set(rb_io_t *fptr, int argc, VALUE v1, VALUE v2)
{
    if (NIL_P(v2)) argc = 1;
    if (argc == 2) {
	fptr->enc2 = rb_to_encoding(v1);
	fptr->enc = rb_to_encoding(v2);
    }
    else if (argc == 1) {
	if (NIL_P(v1)) {
	    fptr->enc = 0;
	}
	else {
	    VALUE tmp = rb_check_string_type(v1);
	    if (!NIL_P(tmp)) {
		mode_enc(fptr, StringValueCStr(tmp));
	    }
	    else {
		fptr->enc = rb_to_encoding(v1);
	    }
	}
    }
}

/*
 *  call-seq:
 *     IO.pipe                    -> [read_io, write_io]
 *     IO.pipe(ext_enc)           -> [read_io, write_io]
 *     IO.pipe("ext_enc:int_enc") -> [read_io, write_io]
 *     IO.pipe(ext_enc, int_enc)  -> [read_io, write_io]
 *
 *  Creates a pair of pipe endpoints (connected to each other) and
 *  returns them as a two-element array of <code>IO</code> objects:
 *  <code>[</code> <i>read_io</i>, <i>write_io</i> <code>]</code>. Not
 *  available on all platforms.
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
#ifdef __human68k__
    rb_notimplement();
    return Qnil;		/* not reached */
#else
    int pipes[2], state;
    VALUE r, w, args[3], v1, v2;
    rb_io_t *fptr;

    rb_scan_args(argc, argv, "02", &v1, &v2);
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
    io_encoding_set(fptr, argc, v1, v2);
    args[1] = INT2NUM(pipes[1]);
    args[2] = INT2FIX(O_WRONLY);
    w = rb_protect(io_new_instance, (VALUE)args, &state);
    if (state) {
	close(pipes[1]);
	if (!NIL_P(r)) rb_io_close(r);
	rb_jump_tag(state);
    }
    rb_io_synchronized(RFILE(w)->fptr);

    return rb_assoc_new(r, w);
#endif
}

struct foreach_arg {
    int argc;
    VALUE *argv;
    VALUE io;
};

static void
open_key_args(int argc, VALUE *argv, struct foreach_arg *arg)
{
    VALUE opt, v;

    FilePathValue(argv[0]);
    arg->io = 0;
    arg->argc = argc > 1 ? 1 : 0;
    arg->argv = argv + 1;
    if (argc == 1) {
      no_key:
	arg->io = rb_io_open(RSTRING_PTR(argv[0]), "r");
	return;
    }
    opt = rb_check_convert_type(argv[argc-1], T_HASH, "Hash", "to_hash");
    if (NIL_P(opt)) goto no_key;
    if (argc > 2) arg->argc = 1;
    else arg->argc = 0;

    v = rb_hash_aref(opt, sym_open_args);
    if (!NIL_P(v)) {
	VALUE args;

	v = rb_convert_type(v, T_ARRAY, "Array", "to_ary");
	args = rb_ary_new2(RARRAY_LEN(v)+1);
	rb_ary_push(args, argv[0]);
	rb_ary_concat(args, v);
	MEMCPY(RARRAY_PTR(args)+1, RARRAY_PTR(v), VALUE, RARRAY_LEN(v));

	arg->io = rb_io_open_with_args(RARRAY_LEN(args), RARRAY_PTR(args));
	return;
    }
    v = rb_hash_aref(opt, sym_mode);
    if (!NIL_P(v)) {
	arg->io = rb_io_open(RSTRING_PTR(argv[0]), StringValueCStr(v));
    }
    else {
	arg->io = rb_io_open(RSTRING_PTR(argv[0]), "r");
    }

    io_set_encoding(arg->io, opt);
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
 *     IO.foreach(name, sep=$/) {|line| block }     => nil
 *     IO.foreach(name, limit) {|line| block }      => nil
 *     IO.foreach(name, sep, limit) {|line| block } => nil
 *
 *  Executes the block for every line in the named I/O port, where lines
 *  are separated by <em>sep</em>.
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
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "13", NULL, NULL, NULL, NULL);
    RETURN_ENUMERATOR(self, argc, argv);
    open_key_args(argc, argv, &arg);
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
 *     IO.readlines(name, sep=$/)     => array
 *     IO.readlines(name, limit)      => array
 *     IO.readlines(name, sep, limit) => array
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
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "13", NULL, NULL, NULL, NULL);
    open_key_args(argc, argv, &arg);
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(io_s_readlines, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
io_s_read(struct foreach_arg *arg)
{
    return io_read(arg->argc, arg->argv, arg->io);
}

/*
 *  call-seq:
 *     IO.read(name, [length [, offset]] )   => string
 *     IO.read(name, [length [, offset]], opt)   => string
 *
 *  Opens the file, optionally seeks to the given offset, then returns
 *  <i>length</i> bytes (defaulting to the rest of the file).
 *  <code>read</code> ensures the file is closed before returning.
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
 *    specifies mode argument for open().  it should start with "r"
 *    otherwise it would cause error.
 *
 *   open_args: array of strings
 *
 *    specifies arguments for open() as an array.
 *
 *     IO.read("testfile")           #=> "This is line one\nThis is line two\nThis is line three\nAnd so on...\n"
 *     IO.read("testfile", 20)       #=> "This is line one\nThi"
 *     IO.read("testfile", 20, 10)   #=> "ne one\nThis is line "
 */

static VALUE
rb_io_s_read(int argc, VALUE *argv, VALUE io)
{
    VALUE offset;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "13", NULL, NULL, &offset, NULL);
    open_key_args(argc, argv, &arg);
    if (NIL_P(arg.io)) return Qnil;
    if (!NIL_P(offset)) {
	rb_io_binmode(arg.io);
	rb_io_seek(arg.io, offset, SEEK_SET);
	if (arg.argc == 2) arg.argc = 1;
    }
    return rb_ensure(io_s_read, (VALUE)&arg, rb_io_close, arg.io);
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
    rb_thread_t *th;
};

static int
copy_stream_wait_read(struct copy_stream_struct *stp)
{
    int ret;
    rb_fd_zero(&stp->fds);
    rb_fd_set(stp->src_fd, &stp->fds);
    ret = rb_fd_select(rb_fd_max(&stp->fds), &stp->fds, NULL, NULL, NULL);
    if (ret == -1) {
        stp->syserr = "select";
        stp->error_no = errno;
        return -1;
    }
    return 0;
}

static int
copy_stream_wait_write(struct copy_stream_struct *stp)
{
    int ret;
    rb_fd_zero(&stp->fds);
    rb_fd_set(stp->dst_fd, &stp->fds);
    ret = rb_fd_select(rb_fd_max(&stp->fds), NULL, &stp->fds, NULL, NULL);
    if (ret == -1) {
        stp->syserr = "select";
        stp->error_no = errno;
        return -1;
    }
    return 0;
}

#ifdef HAVE_SENDFILE

#ifdef __linux__
#define USE_SENDFILE

#ifdef HAVE_SYS_SENDFILE_H
#include <sys/sendfile.h>
#endif

static ssize_t
simple_sendfile(int out_fd, int in_fd, off_t *offset, size_t count)
{
    return sendfile(out_fd, in_fd, offset, count);
}

#endif

#endif

#ifdef USE_SENDFILE
static int
copy_stream_sendfile(struct copy_stream_struct *stp)
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
    if ((dst_stat.st_mode & S_IFMT) != S_IFSOCK)
        return 0;

    src_offset = stp->src_offset;
    use_pread = src_offset != (off_t)-1;

    copy_length = stp->copy_length;
    if (copy_length == (off_t)-1) {
        if (use_pread)
            copy_length = src_stat.st_size - src_offset;
        else {
            off_t cur = lseek(stp->src_fd, 0, SEEK_CUR);
            if (cur == (off_t)-1) {
                stp->syserr = "lseek";
                stp->error_no = errno;
                return -1;
            }
            copy_length = src_stat.st_size - cur;
        }
    }

retry_sendfile:
    if (use_pread) {
        ss = simple_sendfile(stp->dst_fd, stp->src_fd, &src_offset, copy_length);
    }
    else {
        ss = simple_sendfile(stp->dst_fd, stp->src_fd, NULL, copy_length);
    }
    if (0 < ss) {
        stp->total += ss;
        copy_length -= ss;
        if (0 < copy_length) {
            ss = -1;
            errno = EAGAIN;
        }
    }
    if (ss == -1) {
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
            if (copy_stream_wait_write(stp) == -1)
                return -1;
            if (RUBY_VM_INTERRUPTED(stp->th))
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
copy_stream_read(struct copy_stream_struct *stp, char *buf, int len, off_t offset)
{
    ssize_t ss;
retry_read:
    if (offset == (off_t)-1)
        ss = read(stp->src_fd, buf, len);
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
        switch (errno) {
	  case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
            if (copy_stream_wait_read(stp) == -1)
                return -1;
            goto retry_read;
#ifdef ENOSYS
	  case ENOSYS:
#endif
            stp->notimp = "pread";
            return -1;
        }
        stp->syserr = offset == (off_t)-1 ?  "read" : "pread";
        stp->error_no = errno;
        return -1;
    }
    return ss;
}

static int
copy_stream_write(struct copy_stream_struct *stp, char *buf, int len)
{
    ssize_t ss;
    int off = 0;
    while (len) {
        ss = write(stp->dst_fd, buf+off, len);
        if (ss == -1) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                if (copy_stream_wait_write(stp) == -1)
                    return -1;
                continue;
            }
            stp->syserr = "write";
            stp->error_no = errno;
            return -1;
        }
        off += ss;
        len -= ss;
        stp->total += ss;
    }
    return 0;
}

static void
copy_stream_read_write(struct copy_stream_struct *stp)
{
    char buf[1024*16];
    int len;
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
        r = lseek(stp->src_fd, src_offset, SEEK_SET);
        if (r == (off_t)-1) {
            stp->syserr = "lseek";
            stp->error_no = errno;
            return;
        }
        src_offset = (off_t)-1;
        use_pread = 0;
    }

    while (use_eof || 0 < copy_length) {
        if (!use_eof && copy_length < sizeof(buf)) {
            len = copy_length;
        }
        else {
            len = sizeof(buf);
        }
        if (use_pread) {
            ss = copy_stream_read(stp, buf, len, src_offset);
            if (0 < ss)
                src_offset += ss;
        }
        else {
            ss = copy_stream_read(stp, buf, len, (off_t)-1);
        }
        if (ss <= 0) /* EOF or error */
            return;

        ret = copy_stream_write(stp, buf, ss);
        if (ret < 0)
            return;

        if (!use_eof)
            copy_length -= ss;

        if (RUBY_VM_INTERRUPTED(stp->th))
            return;
    }
}

static VALUE
copy_stream_func(void *arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;
#ifdef USE_SENDFILE
    int ret;
#endif

#ifdef USE_SENDFILE
    ret = copy_stream_sendfile(stp);
    if (ret != 0)
        goto finish; /* error or success */
#endif

    copy_stream_read_write(stp);

#ifdef USE_SENDFILE
finish:
#endif
    return Qnil;
}

static VALUE
copy_stream_fallback_body(VALUE arg)
{
    struct copy_stream_struct *stp = (struct copy_stream_struct *)arg;
    const int buflen = 16*1024;
    VALUE n;
    VALUE buf = rb_str_buf_new(buflen);
    long rest = stp->copy_length;
    off_t off = stp->src_offset;

    while (1) {
        long numwrote;
        long l;
        if (stp->copy_length == (off_t)-1) {
            l = buflen;
        }
        else {
            if (rest == 0)
                break;
            l = buflen < rest ? buflen : rest;
        }
        if (stp->src_fd == -1) {
            rb_funcall(stp->src, id_readpartial, 2, INT2FIX(l), buf);
        }
        else {
            ssize_t ss;
            rb_thread_wait_fd(stp->src_fd);
            rb_str_resize(buf, buflen);
            ss = copy_stream_read(stp, RSTRING_PTR(buf), l, off);
            if (ss == -1)
                return Qnil;
            if (ss == 0)
                rb_eof_error();
            rb_str_resize(buf, ss);
            if (off != (off_t)-1)
                off += ss;
        }
        n = rb_io_write(stp->dst, buf);
        numwrote = NUM2LONG(n);
        stp->total += numwrote;
        rest -= numwrote;
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
    VALUE src_io, dst_io;
    rb_io_t *src_fptr = 0, *dst_fptr = 0;
    int src_fd, dst_fd;

    stp->th = GET_THREAD();

    stp->total = 0;

    if (stp->src == argf ||
        !(TYPE(stp->src) == T_FILE ||
          rb_respond_to(stp->src, rb_intern("to_io")) ||
          TYPE(stp->src) == T_STRING ||
          rb_respond_to(stp->src, rb_intern("to_path")))) {
        src_fd = -1;
    }
    else {
        src_io = rb_check_convert_type(stp->src, T_FILE, "IO", "to_io");
        if (NIL_P(src_io)) {
            VALUE args[2];
            int flags = O_RDONLY;
#ifdef O_NOCTTY
            flags |= O_NOCTTY;
#endif
            FilePathValue(stp->src);
            args[0] = stp->src;
            args[1] = INT2NUM(flags);
            src_io = rb_class_new_instance(2, args, rb_cFile);
            stp->src = src_io;
            stp->close_src = 1;
        }
        GetOpenFile(src_io, src_fptr);
        rb_io_check_readable(src_fptr);
        src_fd = src_fptr->fd;
    }
    stp->src_fd = src_fd;

    if (stp->dst == argf ||
        !(TYPE(stp->dst) == T_FILE ||
          rb_respond_to(stp->dst, rb_intern("to_io")) ||
          TYPE(stp->dst) == T_STRING ||
          rb_respond_to(stp->dst, rb_intern("to_path")))) {
        dst_fd = -1;
    }
    else {
        dst_io = rb_check_convert_type(stp->dst, T_FILE, "IO", "to_io");
        if (NIL_P(dst_io)) {
            VALUE args[3];
            int flags = O_WRONLY|O_CREAT|O_TRUNC;
#ifdef O_NOCTTY
            flags |= O_NOCTTY;
#endif
            FilePathValue(stp->dst);
            args[0] = stp->dst;
            args[1] = INT2NUM(flags);
            args[2] = INT2FIX(0600);
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

    if (stp->src_offset == (off_t)-1 && src_fptr && src_fptr->rbuf_len) {
        long len = src_fptr->rbuf_len;
        VALUE str;
        if (stp->copy_length != (off_t)-1 && stp->copy_length < len) {
            len = stp->copy_length;
        }
        str = rb_str_buf_new(len);
        rb_str_resize(str,len);
        read_buffered_data(RSTRING_PTR(str), len, src_fptr);
        if (dst_fptr) /* IO or filename */
            io_fwrite(str, dst_fptr);
        else /* others such as StringIO */
            rb_io_write(stp->dst, str);
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

    rb_fd_init(&stp->fds);
    rb_fd_set(src_fd, &stp->fds);
    rb_fd_set(dst_fd, &stp->fds);

    return rb_thread_blocking_region(copy_stream_func, (void*)stp, RB_UBF_DFL, 0);
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
        errno = stp->error_no;
        rb_sys_fail(stp->syserr);
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

    rb_ensure(copy_stream_body, (VALUE)&st, copy_stream_finalize, (VALUE)&st);

    return OFFT2NUM(st.total);
}

/*
 *  call-seq:
 *     io.external_encoding   => encoding
 *
 *  Returns the Encoding object that represents the encoding of the file.
 *  If io is write mode and no encoding is specified, returns <code>nil</code>.
 */

static VALUE
rb_io_external_encoding(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (fptr->enc2) {
	return rb_enc_from_encoding(fptr->enc2);
    }
    if (!fptr->enc && fptr->fd == 0) {
	fptr->enc = rb_default_external_encoding();
    }
    if (fptr->mode & FMODE_WRITABLE) {
	if (fptr->enc)
	    return rb_enc_from_encoding(fptr->enc);
	return Qnil;
    }
    return rb_enc_from_encoding(io_read_encoding(fptr));
}

/*
 *  call-seq:
 *     io.internal_encoding   => encoding
 *
 *  Returns the Encoding of the internal string if conversion is
 *  specified.  Otherwise returns nil.
 */

static VALUE
rb_io_internal_encoding(VALUE io)
{
    rb_io_t *fptr;

    GetOpenFile(io, fptr);
    if (!fptr->enc2) return Qnil;
    return rb_enc_from_encoding(io_read_encoding(fptr));
}

/*
 *  call-seq:
 *     io.set_encoding(ext_enc)           => io
 *     io.set_encoding("ext_enc:int_enc") => io
 *     io.set_encoding(ext_enc, int_enc)  => io
 *
 *  If single argument is specified, read string from io is tagged
 *  with the encoding specified.  If encoding is a colon separated two
 *  encoding names "A:B", the read string is converted from encoding A
 *  (external encoding) to encoding B (internal encoding), then tagged
 *  with B.  If two arguments are specified, those must be encoding
 *  objects or encoding names, and the first one is the external encoding, and the
 *  second one is the internal encoding.
 */

static VALUE
rb_io_set_encoding(int argc, VALUE *argv, VALUE io)
{
    rb_io_t *fptr;
    VALUE v1, v2;

    rb_scan_args(argc, argv, "11", &v1, &v2);
    GetOpenFile(io, fptr);
    io_encoding_set(fptr, argc, v1, v2);
    return io;
}

static VALUE
argf_external_encoding(VALUE argf)
{
    if (!RTEST(current_file)) {
	return rb_enc_from_encoding(rb_default_external_encoding());
    }
    return rb_io_external_encoding(rb_io_check_io(current_file));
}

static VALUE
argf_internal_encoding(VALUE argf)
{
    if (!RTEST(current_file)) {
	return rb_enc_from_encoding(rb_default_external_encoding());
    }
    return rb_io_internal_encoding(rb_io_check_io(current_file));
}

static VALUE
argf_set_encoding(int argc, VALUE *argv, VALUE argf)
{
    rb_io_t *fptr;

    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to set encoding");
    }
    rb_io_set_encoding(argc, argv, current_file);
    GetOpenFile(current_file, fptr);
    argf_enc = fptr->enc;
    argf_enc2 = fptr->enc2;
    return argf;
}

static VALUE
argf_tell(VALUE argf)
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to tell");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_tell(current_file);
}

static VALUE
argf_seek_m(int argc, VALUE *argv, VALUE argf)
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to seek");
    }
    ARGF_FORWARD(argc, argv);
    return rb_io_seek_m(argc, argv, current_file);
}

static VALUE
argf_set_pos(VALUE argf, VALUE offset)
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to set position");
    }
    ARGF_FORWARD(1, &offset);
    return rb_io_set_pos(current_file, offset);
}

static VALUE
argf_rewind(VALUE argf)
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to rewind");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_rewind(current_file);
}

static VALUE
argf_fileno(VALUE argf)
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_fileno(current_file);
}

static VALUE
argf_to_io(VALUE argf)
{
    next_argv();
    ARGF_FORWARD(0, 0);
    return current_file;
}

static VALUE
argf_eof(VALUE argf)
{
    if (current_file) {
	if (init_p == 0) return Qtrue;
	ARGF_FORWARD(0, 0);
	if (rb_io_eof(current_file)) {
	    return Qtrue;
	}
    }
    return Qfalse;
}

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
	tmp = io_read(argc, argv, current_file);
    }
    if (NIL_P(str)) str = tmp;
    else if (!NIL_P(tmp)) rb_str_append(str, tmp);
    if (NIL_P(tmp) || NIL_P(length)) {
	if (next_p != -1) {
	    argf_close(current_file);
	    next_p = 1;
	    goto retry;
	}
    }
    else if (argc >= 1) {
	if (RSTRING_LEN(str) < len) {
	    len -= RSTRING_LEN(str);
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

static VALUE
argf_readpartial(int argc, VALUE *argv, VALUE argf)
{
    VALUE tmp, str, length;

    rb_scan_args(argc, argv, "11", &length, &str);
    if (!NIL_P(str)) {
        StringValue(str);
        argv[1] = str;
    }

    if (!next_argv()) {
        rb_str_resize(str, 0);
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
        tmp = io_getpartial(argc, argv, current_file, 0);
    }
    if (NIL_P(tmp)) {
        if (next_p == -1) {
            rb_eof_error();
        }
        argf_close(current_file);
        next_p = 1;
        if (RARRAY_LEN(rb_argv) == 0)
            rb_eof_error();
        if (NIL_P(str))
            str = rb_str_new(NULL, 0);
        return str;
    }
    return tmp;
}

static VALUE
argf_getc(VALUE argf)
{
    VALUE ch;

  retry:
    if (!next_argv()) return Qnil;
    if (ARGF_GENERIC_INPUT_P()) {
	ch = rb_funcall3(current_file, rb_intern("getc"), 0, 0);
    }
    else {
	ch = rb_io_getc(current_file);
    }
    if (NIL_P(ch) && next_p != -1) {
	argf_close(current_file);
	next_p = 1;
	goto retry;
    }

    return ch;
}

static VALUE
argf_getbyte(VALUE argf)
{
    VALUE ch;

  retry:
    if (!next_argv()) return Qnil;
    if (TYPE(current_file) != T_FILE) {
	ch = rb_funcall3(current_file, rb_intern("getbyte"), 0, 0);
    }
    else {
	ch = rb_io_getbyte(current_file);
    }
    if (NIL_P(ch) && next_p != -1) {
	argf_close(current_file);
	next_p = 1;
	goto retry;
    }

    return ch;
}

static VALUE
argf_readchar(VALUE argf)
{
    VALUE ch;

  retry:
    if (!next_argv()) rb_eof_error();
    if (TYPE(current_file) != T_FILE) {
	ch = rb_funcall3(current_file, rb_intern("getc"), 0, 0);
    }
    else {
	ch = rb_io_getc(current_file);
    }
    if (NIL_P(ch) && next_p != -1) {
	argf_close(current_file);
	next_p = 1;
	goto retry;
    }

    return ch;
}

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

static VALUE
argf_each_line(int argc, VALUE *argv, VALUE argf)
{
    RETURN_ENUMERATOR(argf, argc, argv);
    for (;;) {
	if (!next_argv()) return Qnil;
	rb_block_call(current_file, rb_intern("each_line"), argc, argv, rb_yield, 0);
	next_p = 1;
    }
    return argf;
}

static VALUE
argf_each_byte(VALUE argf)
{
    RETURN_ENUMERATOR(argf, 0, 0);
    for (;;) {
	if (!next_argv()) return Qnil;
	rb_block_call(current_file, rb_intern("each_byte"), 0, 0, rb_yield, 0);
	next_p = 1;
    }
}

static VALUE
argf_each_char(VALUE argf)
{
    RETURN_ENUMERATOR(argf, 0, 0);
    for (;;) {
	if (!next_argv()) return Qnil;
	rb_block_call(current_file, rb_intern("each_char"), 0, 0, rb_yield, 0);
	next_p = 1;
    }
}

static VALUE
argf_filename(VALUE argf)
{
    next_argv();
    return filename;
}

static VALUE
argf_filename_getter(ID id, VALUE *var)
{
    return argf_filename(*var);
}

static VALUE
argf_file(VALUE argf)
{
    next_argv();
    return current_file;
}

static VALUE
argf_binmode_m(VALUE argf)
{
    argf_binmode = 1;
    next_argv();
    ARGF_FORWARD(0, 0);
    rb_io_binmode(current_file);
    return argf;
}

static VALUE
argf_binmode_p(VALUE argf)
{
    return argf_binmode ? Qtrue : Qfalse;
}

static VALUE
argf_skip(VALUE argf)
{
    if (next_p != -1) {
	argf_close(current_file);
	next_p = 1;
    }
    return argf;
}

static VALUE
argf_close_m(VALUE argf)
{
    next_argv();
    argf_close(current_file);
    if (next_p != -1) {
	next_p = 1;
    }
    gets_lineno = 0;
    return argf;
}

static VALUE
argf_closed(VALUE argf)
{
    next_argv();
    ARGF_FORWARD(0, 0);
    return rb_io_closed(current_file);
}

static VALUE
argf_to_s(VALUE argf)
{
    return rb_str_new2("ARGF");
}

static VALUE
argf_inplace_mode_get(VALUE argf)
{
    if (!ruby_inplace_mode) return Qnil;
    return rb_str_new2(ruby_inplace_mode);
}

static VALUE
opt_i_get(ID id, VALUE *var)
{
    return argf_inplace_mode_get(*var);
}

static VALUE
argf_inplace_mode_set(VALUE argf, VALUE val)
{
    if (!RTEST(val)) {
	if (ruby_inplace_mode) free(ruby_inplace_mode);
	ruby_inplace_mode = 0;
    }
    else {
	StringValue(val);
	if (ruby_inplace_mode) free(ruby_inplace_mode);
	ruby_inplace_mode = 0;
	ruby_inplace_mode = strdup(RSTRING_PTR(val));
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
    return ruby_inplace_mode;
}

void
ruby_set_inplace_mode(const char *suffix)
{
    if (ruby_inplace_mode) free(ruby_inplace_mode);
    ruby_inplace_mode = 0;
    if (suffix) ruby_inplace_mode = strdup(suffix);
}

static VALUE
argf_argv(VALUE argf)
{
    return rb_argv;
}

static VALUE
argf_argv_getter(ID id, VALUE *var)
{
    return argf_argv(*var);
}

VALUE
rb_get_argv(void)
{
    return rb_argv;
}

/*
 *  Class <code>IO</code> is the basis for all input and output in Ruby.
 *  An I/O stream may be <em>duplexed</em> (that is, bidirectional), and
 *  so may use more than one native operating system stream.
 *
 *  Many of the examples in this section use class <code>File</code>,
 *  the only standard subclass of <code>IO</code>. The two classes are
 *  closely associated.
 *
 *  As used in this section, <em>portname</em> may take any of the
 *  following forms.
 *
 *  * A plain string represents a filename suitable for the underlying
 *    operating system.
 *
 *  * A string starting with ``<code>|</code>'' indicates a subprocess.
 *    The remainder of the string following the ``<code>|</code>'' is
 *    invoked as a process with appropriate input/output channels
 *    connected to it.
 *
 *  * A string equal to ``<code>|-</code>'' will create another Ruby
 *    instance as a subprocess.
 *
 *  Ruby will convert pathnames between different operating system
 *  conventions if possible. For instance, on a Windows system the
 *  filename ``<code>/gumby/ruby/test.rb</code>'' will be opened as
 *  ``<code>\gumby\ruby\test.rb</code>''. When specifying a
 *  Windows-style filename in a Ruby string, remember to escape the
 *  backslashes:
 *
 *     "c:\\gumby\\ruby\\test.rb"
 *
 *  Our examples here will use the Unix-style forward slashes;
 *  <code>File::SEPARATOR</code> can be used to get the
 *  platform-specific separator character.
 *
 *  I/O ports may be opened in any one of several different modes, which
 *  are shown in this section as <em>mode</em>. The mode may
 *  either be a Fixnum or a String. If numeric, it should be
 *  one of the operating system specific constants (O_RDONLY,
 *  O_WRONLY, O_RDWR, O_APPEND and so on). See man open(2) for
 *  more information.
 *
 *  If the mode is given as a String, it must be one of the
 *  values listed in the following table.
 *
 *    Mode |  Meaning
 *    -----+--------------------------------------------------------
 *    "r"  |  Read-only, starts at beginning of file  (default mode).
 *    -----+--------------------------------------------------------
 *    "r+" |  Read-write, starts at beginning of file.
 *    -----+--------------------------------------------------------
 *    "w"  |  Write-only, truncates existing file
 *         |  to zero length or creates a new file for writing.
 *    -----+--------------------------------------------------------
 *    "w+" |  Read-write, truncates existing file to zero length
 *         |  or creates a new file for reading and writing.
 *    -----+--------------------------------------------------------
 *    "a"  |  Write-only, starts at end of file if file exists,
 *         |  otherwise creates a new file for writing.
 *    -----+--------------------------------------------------------
 *    "a+" |  Read-write, starts at end of file if file exists,
 *         |  otherwise creates a new file for reading and
 *         |  writing.
 *    -----+--------------------------------------------------------
 *     "b" |  (DOS/Windows only) Binary file mode (may appear with
 *         |  any of the key letters listed above).
 *
 *
 *  The global constant ARGF (also accessible as $<) provides an
 *  IO-like stream which allows access to all files mentioned on the
 *  command line (or STDIN if no files are mentioned). ARGF provides
 *  the methods <code>#path</code> and <code>#filename</code> to access
 *  the name of the file currently being read.
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
    id_encode = rb_intern("encode");
    id_readpartial = rb_intern("readpartial");

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

    rb_define_alloc_func(rb_cIO, io_alloc);
    rb_define_singleton_method(rb_cIO, "new", rb_io_s_new, -1);
    rb_define_singleton_method(rb_cIO, "open",  rb_io_s_open, -1);
    rb_define_singleton_method(rb_cIO, "sysopen",  rb_io_s_sysopen, -1);
    rb_define_singleton_method(rb_cIO, "for_fd", rb_io_s_for_fd, -1);
    rb_define_singleton_method(rb_cIO, "popen", rb_io_s_popen, -1);
    rb_define_singleton_method(rb_cIO, "foreach", rb_io_s_foreach, -1);
    rb_define_singleton_method(rb_cIO, "readlines", rb_io_s_readlines, -1);
    rb_define_singleton_method(rb_cIO, "read", rb_io_s_read, -1);
    rb_define_singleton_method(rb_cIO, "select", rb_f_select, -1);
    rb_define_singleton_method(rb_cIO, "pipe", rb_io_s_pipe, -1);
    rb_define_singleton_method(rb_cIO, "try_convert", rb_io_s_try_convert, 1);
    rb_define_singleton_method(rb_cIO, "copy_stream", rb_io_s_copy_stream, -1);

    rb_define_method(rb_cIO, "initialize", rb_io_initialize, -1);

    rb_output_fs = Qnil;
    rb_define_hooked_variable("$,", &rb_output_fs, 0, rb_str_setter);

    rb_global_variable(&rb_default_rs);
    rb_rs = rb_default_rs = rb_str_new2("\n");
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
    rb_define_method(rb_cIO, "lines",  rb_io_lines, -1);
    rb_define_method(rb_cIO, "bytes",  rb_io_bytes, 0);
    rb_define_method(rb_cIO, "chars",  rb_io_chars, 0);

    rb_define_method(rb_cIO, "syswrite", rb_io_syswrite, 1);
    rb_define_method(rb_cIO, "sysread",  rb_io_sysread, -1);

    rb_define_method(rb_cIO, "fileno", rb_io_fileno, 0);
    rb_define_alias(rb_cIO, "to_i", "fileno");
    rb_define_method(rb_cIO, "to_io", rb_io_to_io, 0);

    rb_define_method(rb_cIO, "fsync",   rb_io_fsync, 0);
    rb_define_method(rb_cIO, "sync",   rb_io_sync, 0);
    rb_define_method(rb_cIO, "sync=",  rb_io_set_sync, 1);

    rb_define_method(rb_cIO, "lineno",   rb_io_lineno, 0);
    rb_define_method(rb_cIO, "lineno=",  rb_io_set_lineno, 1);

    rb_define_method(rb_cIO, "readlines",  rb_io_readlines, -1);

    rb_define_method(rb_cIO, "read_nonblock",  io_read_nonblock, -1);
    rb_define_method(rb_cIO, "write_nonblock", rb_io_write_nonblock, 1);
    rb_define_method(rb_cIO, "readpartial",  io_readpartial, -1);
    rb_define_method(rb_cIO, "read",  io_read, -1);
    rb_define_method(rb_cIO, "write", io_write, 1);
    rb_define_method(rb_cIO, "gets",  rb_io_gets_m, -1);
    rb_define_method(rb_cIO, "readline",  rb_io_readline, -1);
    rb_define_method(rb_cIO, "getc",  rb_io_getc, 0);
    rb_define_method(rb_cIO, "getbyte",  rb_io_getbyte, 0);
    rb_define_method(rb_cIO, "readchar",  rb_io_readchar, 0);
    rb_define_method(rb_cIO, "readbyte",  rb_io_readbyte, 0);
    rb_define_method(rb_cIO, "ungetc",rb_io_ungetc, 1);
    rb_define_method(rb_cIO, "<<",    rb_io_addstr, 1);
    rb_define_method(rb_cIO, "flush", rb_io_flush, 0);
    rb_define_method(rb_cIO, "tell", rb_io_tell, 0);
    rb_define_method(rb_cIO, "seek", rb_io_seek_m, -1);
    rb_define_const(rb_cIO, "SEEK_SET", INT2FIX(SEEK_SET));
    rb_define_const(rb_cIO, "SEEK_CUR", INT2FIX(SEEK_CUR));
    rb_define_const(rb_cIO, "SEEK_END", INT2FIX(SEEK_END));
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

    rb_define_method(rb_cIO, "ioctl", rb_io_ioctl, -1);
    rb_define_method(rb_cIO, "fcntl", rb_io_fcntl, -1);
    rb_define_method(rb_cIO, "pid", rb_io_pid, 0);
    rb_define_method(rb_cIO, "inspect",  rb_io_inspect, 0);

    rb_define_method(rb_cIO, "external_encoding", rb_io_external_encoding, 0);
    rb_define_method(rb_cIO, "internal_encoding", rb_io_internal_encoding, 0);
    rb_define_method(rb_cIO, "set_encoding", rb_io_set_encoding, -1);

    rb_define_variable("$stdin", &rb_stdin);
    rb_stdin = prep_stdio(stdin, FMODE_READABLE, rb_cIO, "<STDIN>");
    rb_define_hooked_variable("$stdout", &rb_stdout, 0, stdout_setter);
    rb_stdout = prep_stdio(stdout, FMODE_WRITABLE, rb_cIO, "<STDOUT>");
    rb_define_hooked_variable("$stderr", &rb_stderr, 0, stdout_setter);
    rb_stderr = prep_stdio(stderr, FMODE_WRITABLE|FMODE_SYNC, rb_cIO, "<STDERR>");
    rb_define_hooked_variable("$>", &rb_stdout, 0, stdout_setter);
    orig_stdout = rb_stdout;
    rb_deferr = orig_stderr = rb_stderr;

    /* constants to hold original stdin/stdout/stderr */
    rb_define_global_const("STDIN", rb_stdin);
    rb_define_global_const("STDOUT", rb_stdout);
    rb_define_global_const("STDERR", rb_stderr);

    rb_cARGF = rb_class_new(rb_cObject);
    rb_set_class_path(rb_cARGF, rb_cObject, "ARGF.class");
    rb_define_alloc_func(rb_cARGF, argf_alloc);

    rb_include_module(rb_cARGF, rb_mEnumerable);

    rb_define_method(rb_cARGF, "initialize", argf_initialize, -2);
    rb_define_method(rb_cARGF, "initialize_copy", argf_initialize_copy, 1);
    rb_define_method(rb_cARGF, "to_s", argf_to_s, 0);
    rb_define_method(rb_cARGF, "argv", argf_argv, 0);

    rb_define_method(rb_cARGF, "fileno", argf_fileno, 0);
    rb_define_method(rb_cARGF, "to_i", argf_fileno, 0);
    rb_define_method(rb_cARGF, "to_io", argf_to_io, 0);
    rb_define_method(rb_cARGF, "each",  argf_each_line, -1);
    rb_define_method(rb_cARGF, "each_line",  argf_each_line, -1);
    rb_define_method(rb_cARGF, "each_byte",  argf_each_byte, 0);
    rb_define_method(rb_cARGF, "each_char",  argf_each_char, 0);
    rb_define_method(rb_cARGF, "lines", argf_each_line, -1);
    rb_define_method(rb_cARGF, "bytes", argf_each_byte, 0);
    rb_define_method(rb_cARGF, "chars", argf_each_char, 0);

    rb_define_method(rb_cARGF, "read",  argf_read, -1);
    rb_define_method(rb_cARGF, "readpartial",  argf_readpartial, -1);
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
    rb_define_global_const("ARGF", argf);

    rb_define_hooked_variable("$.", &argf, argf_lineno_getter, argf_lineno_setter);
    rb_define_hooked_variable("$FILENAME", &argf, argf_filename_getter, 0);
    filename = rb_str_new2("-");

    rb_define_hooked_variable("$-i", &argf, opt_i_get, opt_i_set);
    rb_define_hooked_variable("$*", &argf, argf_argv_getter, 0);

#if defined (_WIN32) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__)
    atexit(pipe_atexit);
#endif

    Init_File();

    rb_define_method(rb_cFile, "initialize",  rb_file_initialize, -1);

    rb_file_const("RDONLY", INT2FIX(O_RDONLY));
    rb_file_const("WRONLY", INT2FIX(O_WRONLY));
    rb_file_const("RDWR", INT2FIX(O_RDWR));
    rb_file_const("APPEND", INT2FIX(O_APPEND));
    rb_file_const("CREAT", INT2FIX(O_CREAT));
    rb_file_const("EXCL", INT2FIX(O_EXCL));
#if defined(O_NDELAY) || defined(O_NONBLOCK)
#   ifdef O_NONBLOCK
    rb_file_const("NONBLOCK", INT2FIX(O_NONBLOCK));
#   else
    rb_file_const("NONBLOCK", INT2FIX(O_NDELAY));
#   endif
#endif
    rb_file_const("TRUNC", INT2FIX(O_TRUNC));
#ifdef O_NOCTTY
    rb_file_const("NOCTTY", INT2FIX(O_NOCTTY));
#endif
#ifdef O_BINARY
    rb_file_const("BINARY", INT2FIX(O_BINARY));
#else
    rb_file_const("BINARY", INT2FIX(0));
#endif
#ifdef O_SYNC
    rb_file_const("SYNC", INT2FIX(O_SYNC));
#endif

    sym_mode = ID2SYM(rb_intern("mode"));
    sym_perm = ID2SYM(rb_intern("perm"));
    sym_extenc = ID2SYM(rb_intern("external_encoding"));
    sym_intenc = ID2SYM(rb_intern("internal_encoding"));
    sym_encoding = ID2SYM(rb_intern("encoding"));
    sym_open_args = ID2SYM(rb_intern("open_args"));
}
