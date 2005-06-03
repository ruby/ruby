/**********************************************************************

  io.c -

  $Author$
  $Date$
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"
#include <ctype.h>
#include <errno.h>

#include <sys/types.h>
#if !defined(_WIN32) && !defined(__DJGPP__)
# if defined(__BEOS__)
#  include <net/socket.h>
# else
#  include <sys/socket.h>
# endif
#endif

#if defined(MSDOS) || defined(__BOW__) || defined(__CYGWIN__) || defined(_WIN32) || defined(__human68k__) || defined(__EMX__) || defined(__BEOS__)
# define NO_SAFE_RENAME
#endif

#if defined(MSDOS) || defined(__CYGWIN__) || defined(_WIN32)
# define NO_LONG_FNAME
#endif

#if defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(sun) || defined(_nec_ews)
# define USE_SETVBUF
#endif

#ifdef __QNXNTO__
#include "unix.h"
#endif

#include <sys/types.h>
#if !defined(DJGPP) && !defined(_WIN32) && !defined(__human68k__)
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

extern void Init_File _((void));

#ifdef __BEOS__
# ifndef NOFILE
#  define NOFILE (OPEN_MAX)
# endif
#include <net/socket.h>
#endif

#include "util.h"

#ifndef O_ACCMODE
#define O_ACCMODE (O_RDONLY | O_WRONLY | O_RDWR)
#endif

#if SIZEOF_OFF_T > SIZEOF_LONG && !defined(HAVE_LONG_LONG)
# error off_t is bigger than long, but you have no long long...
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

static ID id_write, id_read, id_getc, id_flush;

extern char *ruby_inplace_mode;

struct timeval rb_time_interval _((VALUE));

static VALUE filename, current_file;
static int gets_lineno;
static int init_p = 0, next_p = 0;
static VALUE lineno = INT2FIX(0);

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
#  define STDIO_READ_DATA_PENDING(fp)       (((unsigned int)(*(fp))->_cnt) > 0)
#else
#  define STDIO_READ_DATA_PENDING(fp) (!feof(fp))
#endif

#if defined(__VMS)
#define fopen(file_spec, mode)  fopen(file_spec, mode, "rfm=stmlf")
#define open(file_spec, flags, mode)  open(file_spec, flags, mode, "rfm=stmlf")
#endif

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

#if defined(_WIN32)
#define is_socket(fd, path)	rb_w32_is_socket(fd)
#elif defined(__DJGPP__)
#define is_socket(fd, path)	0
#define shutdown(a,b)	0
#else
static int
is_socket(fd, path)
    int fd;
    const char *path;
{
    struct stat sbuf;
    if (fstat(fd, &sbuf) < 0)
        rb_sys_fail(path);
    return S_ISSOCK(sbuf.st_mode);
}
#endif

void
rb_eof_error()
{
    rb_raise(rb_eEOFError, "end of file reached");
}

VALUE
rb_io_taint_check(io)
    VALUE io;
{
    if (!OBJ_TAINTED(io) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: operation on untainted IO");
    rb_check_frozen(io);
    return io;
}

void
rb_io_check_initialized(fptr)
    OpenFile *fptr;
{
    if (!fptr) {
	rb_raise(rb_eIOError, "uninitialized stream");
    }
}

void
rb_io_check_closed(fptr)
    OpenFile *fptr;
{
    rb_io_check_initialized(fptr);
    if (fptr->fd < 0) {
	rb_raise(rb_eIOError, "closed stream");
    }
}

static int io_fflush _((OpenFile *));

static VALUE
rb_io_get_io(io)
    VALUE io;
{
    return rb_convert_type(io, T_FILE, "IO", "to_io");
}

static VALUE
rb_io_check_io(io)
    VALUE io;
{
    return rb_check_convert_type(io, T_FILE, "IO", "to_io");
}

static void
io_unread(OpenFile *fptr)
{
    off_t r;
    rb_io_check_closed(fptr);
    if (fptr->rbuf_len == 0 || fptr->mode & FMODE_DUPLEX)
        return;
    /* xxx: target position may be negative if buffer is filled by ungetc */
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

static int
io_ungetc(int c, OpenFile *fptr)
{
    if (fptr->rbuf == NULL) {
        fptr->rbuf_off = 0;
        fptr->rbuf_len = 0;
        fptr->rbuf_capa = 8192;
        fptr->rbuf = ALLOC_N(char, fptr->rbuf_capa);
    }
    if (c < 0 || fptr->rbuf_len == fptr->rbuf_capa) {
        return -1;
    }
    if (fptr->rbuf_off == 0) {
        if (fptr->rbuf_len)
            MEMMOVE(fptr->rbuf+1, fptr->rbuf, char, fptr->rbuf_len);
        fptr->rbuf_off = 1;
    }
    fptr->rbuf_off--;
    fptr->rbuf_len++;
    fptr->rbuf[fptr->rbuf_off] = c;
    return c;
}

static OpenFile *
flush_before_seek(fptr)
    OpenFile *fptr;
{
    io_fflush(fptr);
    io_unread(fptr);
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
rb_io_check_readable(fptr)
    OpenFile *fptr;
{
    rb_io_check_closed(fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	rb_raise(rb_eIOError, "not opened for reading");
    }
    if (fptr->wbuf_len) {
        io_fflush(fptr);
    }
}

void
rb_io_check_writable(fptr)
    OpenFile *fptr;
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
rb_read_pending(fp)
    FILE *fp;
{
    return STDIO_READ_DATA_PENDING(fp);
}

int
rb_io_read_pending(OpenFile *fptr)
{
    return READ_DATA_PENDING(fptr);
}

void
rb_read_check(fp)
    FILE *fp;
{
    if (!STDIO_READ_DATA_PENDING(fp)) {
	rb_thread_wait_fd(fileno(fp));
    }
}

void
rb_io_read_check(OpenFile *fptr)
{
    if (!READ_DATA_PENDING(fptr)) {
	rb_thread_wait_fd(fptr->fd);
    }
    return;
}

static int
ruby_dup(orig)
    int orig;
{
    int fd;

    fd = dup(orig);
    if (fd < 0) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    fd = dup(orig);
	}
	if (fd < 0) {
	    rb_sys_fail(0);
	}
    }
    return fd;
}

static VALUE io_alloc _((VALUE));
static VALUE
io_alloc(klass)
    VALUE klass;
{
    NEWOBJ(io, struct RFile);
    OBJSETUP(io, klass, T_FILE);

    io->fptr = 0;

    return (VALUE)io;
}

static int
io_fflush(fptr)
    OpenFile *fptr;
{
    int r;
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
    TRAP_BEG;
    r = write(fptr->fd, fptr->wbuf+fptr->wbuf_off, fptr->wbuf_len);
    TRAP_END; /* xxx: signal handler may modify wbuf */
    if (r == fptr->wbuf_len) {
        fptr->wbuf_off = 0;
        fptr->wbuf_len = 0;
        return 0;
    }
    if (0 <= r) {
        fptr->wbuf_off = (wbuf_off += r);
        fptr->wbuf_len = (wbuf_len -= r);
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
wait_readable(p)
    VALUE p;
{
    rb_fdset_t *rfds = (rb_fdset_t *)p;

    return rb_thread_select(rb_fd_max(rfds), rb_fd_ptr(rfds), NULL, NULL, NULL);
}
#endif

int
rb_io_wait_readable(f)
    int f;
{
    rb_fdset_t rfds;

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
		  (VALUE (*)_((VALUE)))rb_fd_term, (VALUE)&rfds);
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
wait_writable(p)
    VALUE p;
{
    rb_fdset_t *wfds = (rb_fdset_t *)p;

    return rb_thread_select(rb_fd_max(wfds), NULL, rb_fd_ptr(wfds), NULL, NULL);
}
#endif

int
rb_io_wait_writable(f)
    int f;
{
    rb_fdset_t wfds;

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
		  (VALUE (*)_((VALUE)))rb_fd_term, (VALUE)&wfds);
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
io_fwrite(str, fptr)
    VALUE str;
    OpenFile *fptr;
{
    long len, n, r, offset = 0;

    len = RSTRING(str)->len;
    if ((n = len) <= 0) return n;
    if (fptr->wbuf == NULL && !(fptr->mode & FMODE_SYNC)) {
        fptr->wbuf_off = 0;
        fptr->wbuf_len = 0;
        fptr->wbuf_capa = 8192;
        fptr->wbuf = ALLOC_N(char, fptr->wbuf_capa);
    }
    if ((fptr->mode & FMODE_SYNC) ||
        (fptr->wbuf && fptr->wbuf_capa <= fptr->wbuf_len + len) ||
        ((fptr->mode & FMODE_TTY) && memchr(RSTRING(str)->ptr+offset, '\n', len))) {
        /* xxx: use writev to avoid double write if available */
        if (fptr->wbuf_len && fptr->wbuf_len+len <= fptr->wbuf_capa) {
            if (fptr->wbuf_capa < fptr->wbuf_off+fptr->wbuf_len+len) {
                MEMMOVE(fptr->wbuf, fptr->wbuf+fptr->wbuf_off, char, fptr->wbuf_len);
                fptr->wbuf_off = 0;
            }
            MEMMOVE(fptr->wbuf+fptr->wbuf_off+fptr->wbuf_len, RSTRING(str)->ptr+offset, char, len);
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
        TRAP_BEG;
	r = write(fptr->fd, RSTRING(str)->ptr+offset, n);
        TRAP_END; /* xxx: signal handler may modify given string. */
        if (r == n) return len;
        if (0 <= r) {
            offset += r;
            n -= r;
            errno = EAGAIN;
        }
        if (rb_io_wait_writable(fptr->fd)) {
            rb_io_check_closed(fptr);
	    if (offset < RSTRING(str)->len)
		goto retry;
        }
        return -1L;
    }

    if (fptr->wbuf_off) {
        if (fptr->wbuf_len)
            MEMMOVE(fptr->wbuf, fptr->wbuf+fptr->wbuf_off, char, fptr->wbuf_len);
        fptr->wbuf_off = 0;
    }
    MEMMOVE(fptr->wbuf+fptr->wbuf_off+fptr->wbuf_len, RSTRING(str)->ptr+offset, char, len);
    fptr->wbuf_len += len;
    return len;
}

long
rb_io_fwrite(ptr, len, f)
    const char *ptr;
    long len;
    FILE *f;
{
    OpenFile of;

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
io_write(io, str)
    VALUE io, str;
{
    OpenFile *fptr;
    long n;
    VALUE tmp;

    rb_secure(4);
    str = rb_obj_as_string(str);
    tmp = rb_io_check_io(io);
    if (NIL_P(tmp)) {
	/* port is not IO, call write method for it. */
	return rb_funcall(io, id_write, 1, str);
    }
    io = tmp;
    if (RSTRING(str)->len == 0) return INT2FIX(0);

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    n = io_fwrite(str, fptr);
    if (n == -1L) rb_sys_fail(fptr->path);

    return LONG2FIX(n);
}

VALUE
rb_io_write(io, str)
    VALUE io, str;
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
rb_io_addstr(io, str)
    VALUE io, str;
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
rb_io_flush(io)
    VALUE io;
{
    OpenFile *fptr;

    if (TYPE(io) != T_FILE) {
        return rb_funcall(io, id_flush, 0);
    }

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
rb_io_tell(io)
     VALUE io;
{
    OpenFile *fptr;
    off_t pos;

    GetOpenFile(io, fptr);
    pos = io_tell(fptr);
    if (pos < 0) rb_sys_fail(fptr->path);
    return OFFT2NUM(pos);
}

static VALUE
rb_io_seek(io, offset, whence)
    VALUE io, offset;
    int whence;
{
    OpenFile *fptr;
    off_t pos;

    pos = NUM2OFFT(offset);
    GetOpenFile(io, fptr);
    pos = io_seek(fptr, pos, whence);
    if (pos < 0) rb_sys_fail(fptr->path);

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
rb_io_seek_m(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
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
rb_io_set_pos(io, offset)
     VALUE io, offset;
{
    OpenFile *fptr;
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
rb_io_rewind(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (io_seek(fptr, 0L, 0) < 0) rb_sys_fail(fptr->path);
    if (io == current_file) {
	gets_lineno -= fptr->lineno;
    }
    fptr->lineno = 0;

    return INT2FIX(0);
}

static int
io_getc(OpenFile *fptr)
{
    int r;
    if (fptr->fd == 0 && (fptr->mode & FMODE_TTY) && TYPE(rb_stdout) == T_FILE) {
        OpenFile *ofp;
        GetOpenFile(rb_stdout, ofp);
        if (ofp->mode & FMODE_TTY) {
            rb_io_flush(rb_stdout);
        }
    }
    if (fptr->rbuf == NULL) {
        fptr->rbuf_off = 0;
        fptr->rbuf_len = 0;
        fptr->rbuf_capa = 8192;
        fptr->rbuf = ALLOC_N(char, fptr->rbuf_capa);
    }
    if (fptr->rbuf_len == 0) {
      retry:
        TRAP_BEG;
        r = read(fptr->fd, fptr->rbuf, fptr->rbuf_capa);
        TRAP_END; /* xxx: signal handler may modify rbuf */
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
    fptr->rbuf_off++;
    fptr->rbuf_len--;
    return (unsigned char)fptr->rbuf[fptr->rbuf_off-1];
}

/*
 *  call-seq:
 *     ios.eof     => true or false
 *     ios.eof?    => true or false
 *
 *  Returns true if <em>ios</em> is at end of file. The stream must be
 *  opened for reading or an <code>IOError</code> will be raised.
 *
 *     f = File.new("testfile")
 *     dummy = f.readlines
 *     f.eof   #=> true
 */

VALUE
rb_io_eof(io)
    VALUE io;
{
    OpenFile *fptr;
    int ch;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (READ_DATA_PENDING(fptr)) return Qfalse;
    READ_CHECK(fptr);
    ch = io_getc(fptr);

    if (ch != EOF) {
	io_ungetc(ch, fptr);
	return Qfalse;
    }
    return Qtrue;
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
rb_io_sync(io)
    VALUE io;
{
    OpenFile *fptr;

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
rb_io_set_sync(io, mode)
    VALUE io, mode;
{
    OpenFile *fptr;

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
rb_io_fsync(io)
    VALUE io;
{
#ifdef HAVE_FSYNC
    OpenFile *fptr;

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
rb_io_fileno(io)
    VALUE io;
{
    OpenFile *fptr;
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
rb_io_pid(io)
    VALUE io;
{
    OpenFile *fptr;

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
rb_io_inspect(obj)
    VALUE obj;
{
    OpenFile *fptr;
    char *buf, *cname, *st = "";
    long len;

    fptr = RFILE(rb_io_taint_check(obj))->fptr;
    if (!fptr || !fptr->path) return rb_any_to_s(obj);
    cname = rb_obj_classname(obj);
    len = strlen(cname) + strlen(fptr->path) + 5;
    if (fptr->fd < 0) {
	st = " (closed)";
	len += 9;
    }
    buf = ALLOCA_N(char, len);
    sprintf(buf, "#<%s:%s%s>", cname, fptr->path, st);
    return rb_str_new2(buf);
}

/*
 *  call-seq:
 *     ios.to_io -> ios
 *
 *  Returns <em>ios</em>.
 */

static VALUE
rb_io_to_io(io)
    VALUE io;
{
    return io;
}

/* reading functions */
static long
read_buffered_data(char *ptr, long len, OpenFile *fptr)
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
io_fread(str, offset, fptr)
    VALUE str;
    long offset;
    OpenFile *fptr;
{
    long len = RSTRING(str)->len - offset;
    long n = len;
    int c;

    while (n > 0) {
	c = read_buffered_data(RSTRING(str)->ptr+offset, n, fptr);
	if (c > 0) {
	    offset += c;
	    if ((n -= c) <= 0) break;
	}
	rb_thread_wait_fd(fptr->fd);
	rb_io_check_closed(fptr);
	c = io_getc(fptr);
	if (c < 0) {
	    break;
	}
	RSTRING(str)->ptr[offset++] = c;
	if (offset > RSTRING(str)->len) break;
	n--;
    }
    return len - n;
}

long
rb_io_fread(ptr, len, f)
    char *ptr;
    long len;
    FILE *f;
{
    OpenFile of;
    VALUE str;
    long n;

    of.fd = fileno(f);
    of.stdio_file = f;
    of.mode = FMODE_READABLE;
    str = rb_str_new(ptr, len);
    n = io_fread(str, 0, &of);
    MEMCPY(ptr, RSTRING(str)->ptr, char, n);
    return n;
}

#ifndef S_ISREG
#   define S_ISREG(m) ((m & S_IFMT) == S_IFREG)
#endif

#define SMALLBUF 100

static long
remain_size(fptr)
    OpenFile *fptr;
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
	    siz += st.st_size - pos + 1;
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
read_all(fptr, siz, str)
    OpenFile *fptr;
    long siz;
    VALUE str;
{
    long bytes = 0;
    long n;

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
	if (bytes < siz) break;
	siz += BUFSIZ;
	rb_str_resize(str, siz);
    }
    if (bytes != siz) rb_str_resize(str, bytes);
    OBJ_TAINT(str);

    return str;
}

static VALUE
io_getpartial(int argc, VALUE *argv, VALUE io)
{
    OpenFile *fptr;
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

    READ_CHECK(fptr);
    if (RSTRING(str)->len != len) {
      modified:
	rb_raise(rb_eRuntimeError, "buffer string modified");
    }
    n = read_buffered_data(RSTRING(str)->ptr, len, fptr);
    if (n <= 0) {
      again:
	if (RSTRING(str)->len != len) goto modified;
        TRAP_BEG;
        n = read(fptr->fd, RSTRING(str)->ptr, len);
        TRAP_END;
        if (n < 0) {
            if (rb_io_wait_readable(fptr->fd))
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
 *     ios.readpartial(maxlen[, outbuf])    => string, outbuf
 *
 *  Reads at most <i>maxlen</i> bytes from the I/O stream but
 *  it blocks only if <em>ios</em> has no data immediately available.
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
 *  Note that readpartial is nonblocking-flag insensitive.
 *  It blocks even if the nonblocking-flag is set.
 *
 *  Also note that readpartial behaves similar to sysread in blocking mode.
 *  The behavior is identical when the buffer is empty.
 *
 */

static VALUE
io_readpartial(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE ret;

    ret = io_getpartial(argc, argv, io);
    if (NIL_P(ret))
        rb_eof_error();
    else
        return ret;
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
io_read(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    OpenFile *fptr;
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
	str = rb_tainted_str_new(0, len);
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
    if (RSTRING(str)->len != len) {
	rb_raise(rb_eRuntimeError, "buffer string modified");
    }
    n = io_fread(str, 0, fptr);
    if (n == 0) {
	if (fptr->fd < 0) return Qnil;
        rb_str_resize(str, 0);
        return Qnil;
    }
    rb_str_resize(str, n);
    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';
    OBJ_TAINT(str);

    return str;
}

static int
appendline(fptr, delim, strp)
    OpenFile *fptr;
    int delim;
    VALUE *strp;
{
    VALUE str = *strp;
    int c = EOF;

    do {
	long pending = READ_DATA_PENDING_COUNT(fptr);
	if (pending > 0) {
	    const char *p = READ_DATA_PENDING_PTR(fptr);
	    const char *e = memchr(p, delim, pending);
	    long last = 0, len = (c != EOF);
	    if (e) pending = e - p + 1;
	    len += pending;
	    if (!NIL_P(str)) {
		last = RSTRING(str)->len;
		rb_str_resize(str, last + len);
	    }
	    else {
		*strp = str = rb_str_buf_new(len);
		RSTRING(str)->len = len;
		RSTRING(str)->ptr[len] = '\0';
	    }
	    if (c != EOF) {
		RSTRING(str)->ptr[last++] = c;
	    }
	    read_buffered_data(RSTRING(str)->ptr + last, pending, fptr); /* must not fail */
	    if (e) return delim;
	}
	else if (c != EOF) {
	    if (!NIL_P(str)) {
		char ch = c;
		rb_str_buf_cat(str, &ch, 1);
	    }
	    else {
		*strp = str = rb_str_buf_new(1);
		RSTRING(str)->ptr[RSTRING(str)->len++] = c;
	    }
	}
	rb_thread_wait_fd(fptr->fd);
	rb_io_check_closed(fptr);
	c = io_getc(fptr);
	if (c < 0) {
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
swallow(fptr, term)
    OpenFile *fptr;
    int term;
{
    int c;

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
	c = io_getc(fptr);
	if (c != term) {
	    io_ungetc(c, fptr);
	    return Qtrue;
	}
    } while (c != EOF);
    return Qfalse;
}

static VALUE
rb_io_getline_fast(fptr, delim)
    OpenFile *fptr;
    unsigned char delim;
{
    VALUE str = Qnil;
    int c;

    while ((c = appendline(fptr, delim, &str)) != EOF && c != delim);

    if (!NIL_P(str)) {
	fptr->lineno++;
	lineno = INT2FIX(fptr->lineno);
	OBJ_TAINT(str);
    }

    return str;
}

static int
rscheck(rsptr, rslen, rs)
    char *rsptr;
    long rslen;
    VALUE rs;
{
    if (RSTRING(rs)->ptr != rsptr && RSTRING(rs)->len != rslen)
	rb_raise(rb_eRuntimeError, "rs modified");
    return 0;
}

static VALUE
rb_io_getline(rs, io)
    VALUE rs, io;
{
    VALUE str = Qnil;
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    if (NIL_P(rs)) {
	str = read_all(fptr, 0, Qnil);
	if (RSTRING(str)->len == 0) return Qnil;
    }
    else if (rs == rb_default_rs) {
	return rb_io_getline_fast(fptr, '\n');
    }
    else {
	int c, newline;
	char *rsptr;
	long rslen;
	int rspara = 0;

	rslen = RSTRING(rs)->len;
	if (rslen == 0) {
	    rsptr = "\n\n";
	    rslen = 2;
	    rspara = 1;
	    swallow(fptr, '\n');
	}
	else if (rslen == 1) {
	    return rb_io_getline_fast(fptr, (unsigned char)RSTRING(rs)->ptr[0]);
	}
	else {
	    rsptr = RSTRING(rs)->ptr;
	}
	newline = rsptr[rslen - 1];

	while ((c = appendline(fptr, newline, &str)) != EOF) {
	    if (c == newline) {
		if (RSTRING(str)->len < rslen) continue;
		if (!rspara) rscheck(rsptr, rslen, rs);
		if (memcmp(RSTRING(str)->ptr + RSTRING(str)->len - rslen,
			   rsptr, rslen) == 0) break;
	    }
	}

	if (rspara) {
	    if (c != EOF) {
		swallow(fptr, '\n');
	    }
	}
    }

    if (!NIL_P(str)) {
	fptr->lineno++;
	lineno = INT2FIX(fptr->lineno);
	OBJ_TAINT(str);
    }

    return str;
}

VALUE
rb_io_gets(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    return rb_io_getline_fast(fptr, '\n');
}

/*
 *  call-seq:
 *     ios.gets(sep_string=$/)   => string or nil
 *
 *  Reads the next ``line'' from the I/O stream; lines are separated by
 *  <i>sep_string</i>. A separator of <code>nil</code> reads the entire
 *  contents, and a zero-length separator reads the input a paragraph at
 *  a time (two successive newlines in the input separate paragraphs).
 *  The stream must be opened for reading or an <code>IOError</code>
 *  will be raised. The line read in will be returned and also assigned
 *  to <code>$_</code>. Returns <code>nil</code> if called at end of
 *  file.
 *
 *     File.new("testfile").gets   #=> "This is line one\n"
 *     $_                          #=> "This is line one\n"
 */

static VALUE
rb_io_gets_m(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE rs, str;

    if (argc == 0) {
	rs = rb_rs;
    }
    else {
	rb_scan_args(argc, argv, "1", &rs);
	if (!NIL_P(rs)) StringValue(rs);
    }
    str = rb_io_getline(rs, io);
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
rb_io_lineno(io)
    VALUE io;
{
    OpenFile *fptr;

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
 *     $. # lineno of last read   #=> 1
 *     f.gets                     #=> "This is line two\n"
 *     $. # lineno of last read   #=> 1001
 */

static VALUE
rb_io_set_lineno(io, lineno)
    VALUE io, lineno;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    fptr->lineno = NUM2INT(lineno);
    return lineno;
}

static void
lineno_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    gets_lineno = NUM2INT(val);
    *var = INT2FIX(gets_lineno);
}

static VALUE
argf_set_lineno(argf, val)
    VALUE argf, val;
{
    gets_lineno = NUM2INT(val);
    lineno = INT2FIX(gets_lineno);
    return Qnil;
}

static VALUE
argf_lineno()
{
    return lineno;
}

/*
 *  call-seq:
 *     ios.readline(sep_string=$/)   => string
 *
 *  Reads a line as with <code>IO#gets</code>, but raises an
 *  <code>EOFError</code> on end of file.
 */

static VALUE
rb_io_readline(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE line = rb_io_gets_m(argc, argv, io);

    if (NIL_P(line)) {
	rb_eof_error();
    }
    return line;
}

/*
 *  call-seq:
 *     ios.readlines(sep_string=$/)  =>   array
 *
 *  Reads all of the lines in <em>ios</em>, and returns them in
 *  <i>anArray</i>. Lines are separated by the optional
 *  <i>sep_string</i>. If <i>sep_string</i> is <code>nil</code>, the
 *  rest of the stream is returned as a single record.
 *  The stream must be opened for reading or an
 *  <code>IOError</code> will be raised.
 *
 *     f = File.new("testfile")
 *     f.readlines[0]   #=> "This is line one\n"
 */

static VALUE
rb_io_readlines(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE line, ary;
    VALUE rs;

    if (argc == 0) {
	rs = rb_rs;
    }
    else {
	rb_scan_args(argc, argv, "1", &rs);
	if (!NIL_P(rs)) StringValue(rs);
    }
    ary = rb_ary_new();
    while (!NIL_P(line = rb_io_getline(rs, io))) {
	rb_ary_push(ary, line);
    }
    return ary;
}

/*
 *  call-seq:
 *     ios.each(sep_string=$/)      {|line| block }  => ios
 *     ios.each_line(sep_string=$/) {|line| block }  => ios
 *
 *  Executes the block for every line in <em>ios</em>, where lines are
 *  separated by <i>sep_string</i>. <em>ios</em> must be opened for
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
rb_io_each_line(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE str;
    VALUE rs;

    if (argc == 0) {
	rs = rb_rs;
    }
    else {
	rb_scan_args(argc, argv, "1", &rs);
	if (!NIL_P(rs)) StringValue(rs);
    }
    while (!NIL_P(str = rb_io_getline(rs, io))) {
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
rb_io_each_byte(io)
    VALUE io;
{
    OpenFile *fptr;
    int c;

    GetOpenFile(io, fptr);

    for (;;) {
	rb_io_check_readable(fptr);
	READ_CHECK(fptr);
	c = io_getc(fptr);
	if (c < 0) {
	    break;
	}
	rb_yield(INT2FIX(c & 0xff));
    }
    return io;
}

/*
 *  call-seq:
 *     ios.getc   => fixnum or nil
 *
 *  Gets the next 8-bit byte (0..255) from <em>ios</em>. Returns
 *  <code>nil</code> if called at end of file.
 *
 *     f = File.new("testfile")
 *     f.getc   #=> 84
 *     f.getc   #=> 104
 */

VALUE
rb_io_getc(io)
    VALUE io;
{
    OpenFile *fptr;
    int c;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    READ_CHECK(fptr);
    c = io_getc(fptr);

    if (c < 0) {
	return Qnil;
    }
    return INT2FIX(c & 0xff);
}

int
rb_getc(f)
    FILE *f;
{
    int c;

    if (!STDIO_READ_DATA_PENDING(f)) {
	rb_thread_wait_fd(fileno(f));
    }
    TRAP_BEG;
    c = getc(f);
    TRAP_END;

    return c;
}

/*
 *  call-seq:
 *     ios.readchar   => fixnum
 *
 *  Reads a character as with <code>IO#getc</code>, but raises an
 *  <code>EOFError</code> on end of file.
 */

static VALUE
rb_io_readchar(io)
    VALUE io;
{
    VALUE c = rb_io_getc(io);

    if (NIL_P(c)) {
	rb_eof_error();
    }
    return c;
}

/*
 *  call-seq:
 *     ios.ungetc(integer)   => nil
 *
 *  Pushes back one character (passed as a parameter) onto <em>ios</em>,
 *  such that a subsequent buffered read will return it. Only one character
 *  may be pushed back before a subsequent read operation (that is,
 *  you will be able to read only the last of several characters that have been pushed
 *  back). Has no effect with unbuffered reads (such as <code>IO#sysread</code>).
 *
 *     f = File.new("testfile")   #=> #<File:testfile>
 *     c = f.getc                 #=> 84
 *     f.ungetc(c)                #=> nil
 *     f.getc                     #=> 84
 */

VALUE
rb_io_ungetc(io, c)
    VALUE io, c;
{
    OpenFile *fptr;
    int cc = NUM2INT(c);

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (io_ungetc(cc, fptr) == EOF && cc != EOF) {
	rb_raise(rb_eIOError, "ungetc failed");
    }
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
rb_io_isatty(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (isatty(fptr->fd) == 0)
	return Qfalse;
    return Qtrue;
}

#define FMODE_PREP (1<<16)
#define IS_PREP_STDIO(f) ((f)->mode & FMODE_PREP)
#define PREP_STDIO_NAME(f) ((f)->path)

static void
fptr_finalize(fptr, noraise)
    OpenFile *fptr;
    int noraise;
{
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
            /* fptr->fd is still not closed */
            rb_sys_fail(fptr->path);
        }
    }
    fptr->fd = -1;
    fptr->stdio_file = 0;
    fptr->mode &= ~(FMODE_READABLE|FMODE_WRITABLE);
}

static void
rb_io_fptr_cleanup(fptr, noraise)
    OpenFile *fptr;
    int noraise;
{
    if (fptr->finalize) {
	(*fptr->finalize)(fptr, noraise);
    }
    else {
	fptr_finalize(fptr, noraise);
    }
}

int
rb_io_fptr_finalize(fptr)
    OpenFile *fptr;
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
    free(fptr);
    return 1;
}

VALUE
rb_io_close(io)
    VALUE io;
{
    OpenFile *fptr;
    int fd;

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
 */

static VALUE
rb_io_close_m(io)
    VALUE io;
{
    if (rb_safe_level() >= 4 && !OBJ_TAINTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    rb_io_check_closed(RFILE(io)->fptr);
    rb_io_close(io);
    return Qnil;
}

static VALUE
io_close(io)
    VALUE io;
{
    return rb_funcall(io, rb_intern("close"), 0, 0);
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
rb_io_closed(io)
    VALUE io;
{
    OpenFile *fptr;

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
rb_io_close_read(io)
    VALUE io;
{
    OpenFile *fptr;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(io)) {
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
rb_io_close_write(io)
    VALUE io;
{
    OpenFile *fptr;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    GetOpenFile(io, fptr);
    if (is_socket(fptr->fd, fptr->path)) {
#ifndef SHUT_WR
# define SHUT_WR 1
#endif
        if (shutdown(fptr->fd, SHUT_WR) < 0)
            rb_sys_fail(fptr->path);
        fptr->mode &= ~FMODE_WRITABLE;
        if (!(fptr->mode & FMODE_READABLE))
            return rb_io_close(io);
        return Qnil;
    }

    if (fptr->mode & FMODE_READABLE) {
	rb_raise(rb_eIOError, "closing non-duplex IO for writing");
    }
    return rb_io_close(io);
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
rb_io_sysseek(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE offset, ptrname;
    int whence = SEEK_SET;
    OpenFile *fptr;
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
rb_io_syswrite(io, str)
    VALUE io, str;
{
    OpenFile *fptr;
    long n;

    rb_secure(4);
    if (TYPE(str) != T_STRING)
	str = rb_obj_as_string(str);

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);

    if (fptr->wbuf_len) {
	rb_warn("syswrite for buffered IO");
    }
    if (!rb_thread_fd_writable(fptr->fd)) {
        rb_io_check_closed(fptr);
    }
    n = write(fptr->fd, RSTRING(str)->ptr, RSTRING(str)->len);

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
rb_io_sysread(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE len, str;
    OpenFile *fptr;
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
    if (RSTRING(str)->len != ilen) {
	rb_raise(rb_eRuntimeError, "buffer string modified");
    }
    TRAP_BEG;
    n = read(fptr->fd, RSTRING(str)->ptr, ilen);
    TRAP_END;

    if (n == -1) {
	rb_sys_fail(fptr->path);
    }
    rb_str_resize(str, n);
    if (n == 0 && ilen > 0) {
	rb_eof_error();
    }
    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';
    OBJ_TAINT(str);

    return str;
}

/*
 *  call-seq:
 *     ios.binmode    => ios
 *
 *  Puts <em>ios</em> into binary mode. This is useful only in
 *  MS-DOS/Windows environments. Once a stream is in binary mode, it
 *  cannot be reset to nonbinary mode.
 */

VALUE
rb_io_binmode(io)
    VALUE io;
{
#if defined(_WIN32) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__) || defined(__EMX__)
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (!(fptr->mode & FMODE_BINMODE) && READ_DATA_BUFFERED(fptr)) {
	rb_raise(rb_eIOError, "buffer already filled with text-mode content");
    }
    if (0 <= fptr->fd && setmode(fptr->fd, O_BINARY) == -1)
	rb_sys_fail(fptr->path);

    fptr->mode |= FMODE_BINMODE;
#endif
    return io;
}

static char*
rb_io_flags_mode(flags)
    int flags;
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
    rb_raise(rb_eArgError, "illegal access modenum %o", flags);
    return NULL;		/* not reached */
}

int
rb_io_mode_flags(mode)
    const char *mode;
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
	rb_raise(rb_eArgError, "illegal access mode %s", mode);
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
        }
    }

    return flags;
}

int
rb_io_modenum_flags(mode)
    int mode;
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

static int
rb_io_mode_modenum(mode)
    const char *mode;
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
	rb_raise(rb_eArgError, "illegal access mode %s", mode);
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
        }
    }

    return flags;
}

#define MODENUM_MAX 4

static char*
rb_io_modenum_mode(flags)
    int flags;
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
    rb_raise(rb_eArgError, "illegal access modenum %o", flags);
    return NULL;		/* not reached */
}

static int
rb_sysopen(fname, flags, mode)
    char *fname;
    int flags;
    unsigned int mode;
{
    int fd;

    fd = open(fname, flags, mode);
    if (fd < 0) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    fd = open(fname, flags, mode);
	}
	if (fd < 0) {
	    rb_sys_fail(fname);
	}
    }
    return fd;
}

FILE *
rb_fopen(fname, mode)
    const char *fname;
    const char *mode;
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
rb_fdopen(fd, mode)
    int fd;
    const char *mode;
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
io_check_tty(OpenFile *fptr)
{
    if (isatty(fptr->fd))
        fptr->mode |= FMODE_TTY|FMODE_DUPLEX;
}

static VALUE
rb_file_open_internal(io, fname, mode)
    VALUE io;
    const char *fname, *mode;
{
    OpenFile *fptr;

    MakeOpenFile(io, fptr);
    fptr->mode = rb_io_mode_flags(mode);
    fptr->path = strdup(fname);
    fptr->fd = rb_sysopen(fptr->path, rb_io_mode_modenum(rb_io_flags_mode(fptr->mode)), 0666);
    io_check_tty(fptr);

    return io;
}

VALUE
rb_file_open(fname, mode)
    const char *fname, *mode;
{
    return rb_file_open_internal(io_alloc(rb_cFile), fname, mode);
}

static VALUE
rb_file_sysopen_internal(io, fname, flags, mode)
    VALUE io;
    char *fname;
    int flags, mode;
{
    OpenFile *fptr;

    MakeOpenFile(io, fptr);

    fptr->path = strdup(fname);
    fptr->mode = rb_io_modenum_flags(flags);
    fptr->fd = rb_sysopen(fptr->path, flags, mode);
    io_check_tty(fptr);

    return io;
}

VALUE
rb_file_sysopen(fname, flags, mode)
    const char *fname;
    int flags, mode;
{
    return rb_file_sysopen_internal(io_alloc(rb_cFile), fname, flags, mode);
}

#if defined(__CYGWIN__) || !defined(HAVE_FORK)
static struct pipe_list {
    OpenFile *fptr;
    struct pipe_list *next;
} *pipe_list;

static void
pipe_add_fptr(fptr)
    OpenFile *fptr;
{
    struct pipe_list *list;

    list = ALLOC(struct pipe_list);
    list->fptr = fptr;
    list->next = pipe_list;
    pipe_list = list;
}

static void
pipe_del_fptr(fptr)
    OpenFile *fptr;
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
pipe_atexit _((void))
{
    struct pipe_list *list = pipe_list;
    struct pipe_list *tmp;

    while (list) {
	tmp = list->next;
	rb_io_fptr_finalize(list->fptr);
	list = tmp;
    }
}

static void pipe_finalize _((OpenFile *fptr,int));

static void
pipe_finalize(fptr, noraise)
    OpenFile *fptr;
    int noraise;
{
#if !defined(HAVE_FORK) && !defined(_WIN32)
    extern VALUE rb_last_status;
    int status;
    if (fptr->stdio_file) {
	status = pclose(fptr->stdio_file);
    }
    fptr->fd = -1;
    fptr->stdio_file = 0;
#if defined DJGPP
    status <<= 8;
#endif
    rb_last_status = INT2FIX(status);
#else
    fptr_finalize(fptr, noraise);
#endif
    pipe_del_fptr(fptr);
}
#endif

void
rb_io_synchronized(fptr)
    OpenFile *fptr;
{
    fptr->mode |= FMODE_SYNC;
}

void
rb_io_unbuffered(fptr)
    OpenFile *fptr;
{
    rb_io_synchronized(fptr);
}

struct popen_arg {
    struct rb_exec_arg exec;
    int modef;
    int pair[2];
};

static void
popen_redirect(p)
    struct popen_arg *p;
{
    if ((p->modef & FMODE_READABLE) && (p->modef & FMODE_WRITABLE)) {
        close(p->pair[0]);
        dup2(p->pair[1], 0);
        dup2(p->pair[1], 1);
        if (2 <= p->pair[1])
            close(p->pair[1]);
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

#ifdef HAVE_FORK
static int
popen_exec(p)
    struct popen_arg *p;
{
    int fd;

    popen_redirect(p);
    for (fd = 3; fd < NOFILE; fd++) {
#ifdef FD_CLOEXEC
	fcntl(fd, F_SETFL, FD_CLOEXEC);
#else
	close(fd);
#endif
    }
    return rb_exec(&p->exec);
}
#endif

static VALUE
pipe_open(argc, argv, mode)
    int argc;
    VALUE *argv;
    char *mode;
{
    int modef = rb_io_mode_flags(mode);
    int pid = 0;
    OpenFile *fptr;
    VALUE port, prog;
#if defined(HAVE_FORK)
    int status;
    struct popen_arg arg;
    volatile int doexec;
#elif defined(_WIN32)
    int openmode = rb_io_mode_modenum(mode);
    char *exename = NULL;
#endif
    char *cmd;
    FILE *fp = 0;
    int fd = -1;

    prog = rb_check_argv(argc, argv);
    if (!prog) {
	if (argc == 1) argc = 0;
	prog = argv[0];
    }

#if defined(HAVE_FORK)
    cmd = StringValueCStr(prog);
    doexec = (strcmp("-", cmd) != 0);
    if (!doexec) {
	fflush(stdin);		/* is it really needed? */
        rb_io_flush(rb_stdout);
        rb_io_flush(rb_stderr);
    }
    arg.modef = modef;
    arg.pair[0] = arg.pair[1] = -1;
    if ((modef & FMODE_READABLE) && (modef & FMODE_WRITABLE)) {
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, arg.pair) < 0)
            rb_sys_fail(cmd);
    }
    else if (modef & FMODE_READABLE) {
        if (pipe(arg.pair) < 0)
            rb_sys_fail(cmd);
    }
    else if (modef & FMODE_WRITABLE) {
        if (pipe(arg.pair) < 0)
            rb_sys_fail(cmd);
    }
    else {
        rb_sys_fail(cmd);
    }
    if (doexec) {
	arg.exec.argc = argc;
	arg.exec.argv = argv;
	arg.exec.prog = cmd;
	pid = rb_fork(&status, popen_exec, &arg);
    }
    else {
	pid = rb_fork(&status, 0, 0);
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
	errno = e;
	rb_sys_fail(cmd);
    }
    if ((modef & FMODE_READABLE) && (modef & FMODE_WRITABLE)) {
        close(arg.pair[1]);
        fd = arg.pair[0];
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
	char **args = ALLOCA_N(char *, argc+1);
	int i;

	for (i = 0; i < argc; ++i) {
	    args[i] = RSTRING(argv[i])->ptr;
	}
	args[i] = NULL;
	cmd = ALLOCA_N(char, rb_w32_argv_size(args));
	rb_w32_join_argv(cmd, args);
	exename = RSTRING(prog)->ptr;
    }
    else {
	cmd = StringValueCStr(prog);
    }
    while ((pid = rb_w32_pipe_exec(cmd, exename, openmode, &fd)) == -1) {
	/* exec failed */
	switch (errno) {
	  case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
	    rb_thread_sleep(1);
	    break;
	  default:
	    rb_sys_fail(RSTRING(prog)->ptr);
	    break;
	}
    }
#else
    if (argc)
	prog = rb_ary_join(rb_ary_new4(argc, argv), rb_str_new2(" "));
    fp = popen(StringValueCStr(prog), mode);
    if (!fp) rb_sys_fail(RSTRING(prog)->ptr);
    fd = fileno(fp);
#endif

    port = io_alloc(rb_cIO);
    MakeOpenFile(port, fptr);
    fptr->fd = fd;
    fptr->stdio_file = fp;
    fptr->mode = modef | FMODE_SYNC|FMODE_DUPLEX;
    fptr->pid = pid;

#if defined (__CYGWIN__) || !defined(HAVE_FORK)
    fptr->finalize = pipe_finalize;
    pipe_add_fptr(fptr);
#endif
    return port;
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
 *  be used as the subprocess's +argv+ bypassing a shell.  The default
 *  mode for the new file object is ``r'', but <i>mode</i> may be set
 *  to any of the modes listed in the description for class IO.
 *
 *  Raises exceptions which <code>IO::pipe</code> and
 *  <code>Kernel::system</code> raise.
 *
 *  If a block is given, Ruby will run the command as a child connected
 *  to Ruby with a pipe. Ruby's end of the pipe will be passed as a
 *  parameter to the block. In this case <code>IO::popen</code> returns
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
 *     <foo>bar;zot;
 */

static VALUE
rb_io_s_popen(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    char *mode;
    VALUE pname, pmode, port, tmp;

    if (rb_scan_args(argc, argv, "11", &pname, &pmode) == 1) {
	mode = "r";
    }
    else if (FIXNUM_P(pmode)) {
	mode = rb_io_modenum_mode(FIX2INT(pmode));
    }
    else {
	mode = rb_io_flags_mode(rb_io_mode_flags(StringValuePtr(pmode)));
    }
    tmp = rb_check_array_type(pname);
    if (!NIL_P(tmp)) {
	VALUE *argv = ALLOCA_N(VALUE, RARRAY(tmp)->len);

	MEMCPY(argv, RARRAY(tmp)->ptr, VALUE, RARRAY(tmp)->len);
	port = pipe_open(RARRAY(tmp)->len, argv, mode);
	pname = tmp;
    }
    else {
	SafeStringValue(pname);
	port = pipe_open(1, &pname, mode);
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

static VALUE
rb_open_file(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname, vmode, perm;
    char *mode;
    int flags, fmode;

    rb_scan_args(argc, argv, "12", &fname, &vmode, &perm);
    FilePathValue(fname);

    if (FIXNUM_P(vmode) || !NIL_P(perm)) {
	if (FIXNUM_P(vmode)) {
	    flags = FIX2INT(vmode);
	}
	else {
	    SafeStringValue(vmode);
	    flags = rb_io_mode_modenum(RSTRING(vmode)->ptr);
	}
	fmode = NIL_P(perm) ? 0666 :  NUM2INT(perm);

	rb_file_sysopen_internal(io, RSTRING(fname)->ptr, flags, fmode);
    }
    else {
	mode = NIL_P(vmode) ? "r" : StringValuePtr(vmode);
	rb_file_open_internal(io, RSTRING(fname)->ptr, mode);
    }
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
rb_io_s_open(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
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
rb_io_s_sysopen(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, vmode, perm;
    int flags, fmode, fd;
    char *path;

    rb_scan_args(argc, argv, "12", &fname, &vmode, &perm);
    FilePathValue(fname);

    if (NIL_P(vmode)) flags = O_RDONLY;
    else if (FIXNUM_P(vmode)) flags = FIX2INT(vmode);
    else {
	SafeStringValue(vmode);
	flags = rb_io_mode_modenum(RSTRING(vmode)->ptr);
    }
    if (NIL_P(perm)) fmode = 0666;
    else             fmode = NUM2INT(perm);

    path = ALLOCA_N(char, strlen(RSTRING(fname)->ptr)+1);
    strcpy(path, RSTRING(fname)->ptr);
    fd = rb_sysopen(path, flags, fmode);
    return INT2NUM(fd);
}

/*
 *  call-seq:
 *     open(path [, mode [, perm]] )                => io or nil
 *     open(path [, mode [, perm]] ) {|io| block }  => obj
 *
 *  Creates an <code>IO</code> object connected to the given stream,
 *  file, or subprocess.
 *
 *  If <i>path</i> does not start with a pipe character
 *  (``<code>|</code>''), treat it as the name of a file to open using
 *  the specified mode (defaulting to ``<code>r</code>''). (See the table
 *  of valid modes on page 331.) If a file is being created, its initial
 *  permissions may be set using the integer third parameter.
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
rb_f_open(argc, argv)
    int argc;
    VALUE *argv;
{
    if (argc >= 1) {
	ID to_open = rb_intern("to_open");

	if (rb_respond_to(argv[0], to_open)) {
	    VALUE io = rb_funcall2(argv[0], to_open, argc-1, argv+1);

	    if (rb_block_given_p()) {
		return rb_ensure(rb_yield, io, io_close, io);
	    }
	    return io;
	}
	else {
	    VALUE tmp = rb_check_string_type(argv[0]);
	    if (!NIL_P(tmp)) {
		char *str = StringValuePtr(tmp);
		if (str && str[0] == '|') {
		    argv[0] = rb_str_new(str+1, RSTRING(tmp)->len-1);
		    OBJ_INFECT(argv[0], tmp);
		    return rb_io_s_popen(argc, argv, rb_cIO);
		}
	    }
	}
    }
    return rb_io_s_open(argc, argv, rb_cFile);
}

static VALUE
rb_io_open(fname, mode)
    char *fname, *mode;
{
    if (fname[0] == '|') {
	VALUE cmd = rb_str_new2(fname+1);
	return pipe_open(1, &cmd, mode);
    }
    else {
	return rb_file_open(fname, mode);
    }
}

static VALUE
io_reopen(io, nfile)
    VALUE io, nfile;
{
    OpenFile *fptr, *orig;
    int fd, fd2;
    off_t pos = 0;

    nfile = rb_io_get_io(nfile);
    if (rb_safe_level() >= 4 && (!OBJ_TAINTED(io) || !OBJ_TAINTED(nfile))) {
	rb_raise(rb_eSecurityError, "Insecure: can't reopen");
    }
    GetOpenFile(io, fptr);
    GetOpenFile(nfile, orig);

    if (fptr == orig) return io;
#if !defined __CYGWIN__
    if (IS_PREP_STDIO(fptr)) {
	if ((fptr->mode & FMODE_READWRITE) != (orig->mode & FMODE_READWRITE)) {
	    rb_raise(rb_eArgError,
		     "%s can't change access mode from \"%s\" to \"%s\"",
		     PREP_STDIO_NAME(fptr), rb_io_flags_mode(fptr->mode),
		     rb_io_flags_mode(orig->mode));
	}
    }
#endif
    if (orig->mode & FMODE_READABLE) {
	pos = io_tell(orig);
    }
    if (orig->mode & FMODE_WRITABLE) {
	io_fflush(orig);
    }
    if (fptr->mode & FMODE_WRITABLE) {
	io_fflush(fptr);
    }

    /* copy OpenFile structure */
    fptr->mode = orig->mode;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (fptr->path) free(fptr->path);
    if (orig->path) fptr->path = strdup(orig->path);
    else fptr->path = 0;
    fptr->finalize = orig->finalize;

    fd = fptr->fd;
    fd2 = orig->fd;
    if (fd != fd2) {
#if !defined __CYGWIN__
	if (IS_PREP_STDIO(fptr)) {
	    /* need to keep stdio objects */
	    if (dup2(fd2, fd) < 0)
		rb_sys_fail(orig->path);
	}
	else {
#endif
            if (fptr->stdio_file)
                fclose(fptr->stdio_file);
            else
                close(fptr->fd);
            fptr->stdio_file = 0;
            fptr->fd = -1;
	    if (dup2(fd2, fd) < 0)
		rb_sys_fail(orig->path);
            fptr->fd = fd;
#if !defined __CYGWIN__
	}
#endif
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

    RBASIC(io)->klass = RBASIC(nfile)->klass;
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
rb_io_reopen(argc, argv, file)
    int argc;
    VALUE *argv;
    VALUE file;
{
    VALUE fname, nmode;
    char *mode;
    OpenFile *fptr;

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
	fptr = RFILE(file)->fptr = ALLOC(OpenFile);
	MEMZERO(fptr, OpenFile, 1);
    }

    if (!NIL_P(nmode)) {
	int flags = rb_io_mode_flags(StringValuePtr(nmode));
	if (IS_PREP_STDIO(fptr) &&
	    (fptr->mode & FMODE_READWRITE) != (flags & FMODE_READWRITE)) {
	    rb_raise(rb_eArgError,
		     "%s can't change access mode from \"%s\" to \"%s\"",
		     PREP_STDIO_NAME(fptr), rb_io_flags_mode(fptr->mode),
		     rb_io_flags_mode(flags));
	}
	fptr->mode = flags;
    }

    if (fptr->path) {
	free(fptr->path);
	fptr->path = 0;
    }

    fptr->path = strdup(RSTRING(fname)->ptr);
    mode = rb_io_flags_mode(fptr->mode);
    if (fptr->fd < 0) {
        fptr->fd = rb_sysopen(fptr->path, rb_io_mode_modenum(mode), 0666);
	fptr->stdio_file = 0;
	return file;
    }

    if (fptr->stdio_file) {
        if (freopen(RSTRING(fname)->ptr, mode, fptr->stdio_file) == 0) {
            rb_sys_fail(fptr->path);
        }
        fptr->fd = fileno(fptr->stdio_file);
#ifdef USE_SETVBUF
        if (setvbuf(fptr->stdio_file, NULL, _IOFBF, 0) != 0)
            rb_warn("setvbuf() can't be honoured for %s", RSTRING(fname)->ptr);
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
rb_io_init_copy(dest, io)
    VALUE dest, io;
{
    OpenFile *fptr, *orig;
    int fd;

    io = rb_io_get_io(io);
    if (dest == io) return dest;
    GetOpenFile(io, orig);
    MakeOpenFile(dest, fptr);

    rb_io_flush(io);

    /* copy OpenFile structure */
    fptr->mode = orig->mode;
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
rb_io_printf(argc, argv, out)
    int argc;
    VALUE argv[];
    VALUE out;
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
rb_f_printf(argc, argv)
    int argc;
    VALUE argv[];
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
 *  opened for writing. If the output record separator (<code>$\</code>)
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
rb_io_print(argc, argv, out)
    int argc;
    VALUE *argv;
    VALUE out;
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
	switch (TYPE(argv[i])) {
	  case T_NIL:
	    rb_io_write(out, rb_str_new2("nil"));
	    break;
	  default:
	    rb_io_write(out, argv[i]);
	    break;
	}
    }
    if (!NIL_P(rb_output_rs)) {
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
 *  separator (<code>$\</code>) is not +nil+, it will be
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
rb_f_print(argc, argv)
    int argc;
    VALUE *argv;
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
rb_io_putc(io, ch)
    VALUE io, ch;
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
rb_f_putc(recv, ch)
    VALUE recv, ch;
{
    return rb_io_putc(rb_stdout, ch);
}

static VALUE
io_puts_ary(ary, out, recur)
    VALUE ary, out;
{
    VALUE tmp;
    long i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	tmp = RARRAY(ary)->ptr[i];
	if (recur) {
	    tmp = rb_str_new2("[...]");
	}
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
rb_io_puts(argc, argv, out)
    int argc;
    VALUE *argv;
    VALUE out;
{
    int i;
    VALUE line;

    /* if no argument given, print newline. */
    if (argc == 0) {
	rb_io_write(out, rb_default_rs);
	return Qnil;
    }
    for (i=0; i<argc; i++) {
	if (NIL_P(argv[i])) {
	    line = rb_str_new2("nil");
	}
	else {
	    line = rb_check_array_type(argv[i]);
	    if (!NIL_P(line)) {
		rb_exec_recursive(io_puts_ary, line, out);
		continue;
	    }
	    line = rb_obj_as_string(argv[i]);
	}
	rb_io_write(out, line);
	if (RSTRING(line)->len == 0 ||
            RSTRING(line)->ptr[RSTRING(line)->len-1] != '\n') {
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
rb_f_puts(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_io_puts(argc, argv, rb_stdout);
    return Qnil;
}

void
rb_p(obj)			/* for debug print within C code */
    VALUE obj;
{
    rb_io_write(rb_stdout, rb_obj_as_string(rb_inspect(obj)));
    rb_io_write(rb_stdout, rb_default_rs);
}

/*
 *  call-seq:
 *     p(obj, ...)    => nil
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
rb_f_p(argc, argv)
    int argc;
    VALUE *argv;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_p(argv[i]);
    }
    if (TYPE(rb_stdout) == T_FILE) {
	rb_io_flush(rb_stdout);
    }
    return Qnil;
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
rb_obj_display(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE out;

    if (rb_scan_args(argc, argv, "01", &out) == 0) {
	out = rb_stdout;
    }

    rb_io_write(out, self);

    return Qnil;
}

void
rb_write_error2(mesg, len)
    const char *mesg;
    long len;
{
    rb_io_write(rb_stderr, rb_str_new(mesg, len));
}

void
rb_write_error(mesg)
    const char *mesg;
{
    rb_write_error2(mesg, strlen(mesg));
}

static void
must_respond_to(mid, val, id)
    ID mid;
    VALUE val;
    ID id;
{
    if (!rb_respond_to(val, mid)) {
	rb_raise(rb_eTypeError, "%s must have %s method, %s given",
		 rb_id2name(id), rb_id2name(mid),
		 rb_obj_classname(val));
    }
}

static void
stdout_setter(val, id, variable)
    VALUE val;
    ID id;
    VALUE *variable;
{
    must_respond_to(id_write, val, id);
    *variable = val;
}

static void
defout_setter(val, id, variable)
    VALUE val;
    ID id;
    VALUE *variable;
{
    stdout_setter(val, id, variable);
    rb_warn("$defout is obsolete; use $stdout instead");
}

static void
deferr_setter(val, id, variable)
    VALUE val;
    ID id;
    VALUE *variable;
{
    stdout_setter(val, id, variable);
    rb_warn("$deferr is obsolete; use $stderr instead");
}

static VALUE
prep_io(fd, mode, klass, path)
    int fd;
    int mode;
    VALUE klass;
    const char *path;
{
    OpenFile *fp;
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

static VALUE
prep_stdio(f, mode, klass, path)
    FILE *f;
    int mode;
    VALUE klass;
    const char *path;
{
    OpenFile *fptr;
    VALUE io = prep_io(fileno(f), mode|FMODE_PREP, klass, path);

    GetOpenFile(io, fptr);
    fptr->stdio_file = f;

    return io;
}

FILE *rb_io_stdio_file(OpenFile *fptr)
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
rb_io_initialize(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fnum, mode, orig;
    OpenFile *fp, *ofp = NULL;
    int fd, flags, fmode;

    rb_secure(4);
    rb_scan_args(argc, argv, "11", &fnum, &mode);
    if (argc == 2) {
	if (FIXNUM_P(mode)) {
	    flags = FIX2LONG(mode);
	}
	else {
	    SafeStringValue(mode);
	    flags = rb_io_mode_modenum(RSTRING(mode)->ptr);
	}
    }
    orig = rb_io_check_io(fnum);
    if (NIL_P(orig)) {
	fd = NUM2INT(fnum);
	if (argc != 2) {
#if defined(HAVE_FCNTL) && defined(F_GETFL)
	    flags = fcntl(fd, F_GETFL);
	    if (flags == -1) rb_sys_fail(0);
#else
	    flags = O_RDONLY;
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
	    rb_raise(rb_eIOError, "too many shared IO for %s", StringValuePtr(s));
	}
	if (argc == 2) {
	    fmode = rb_io_modenum_flags(flags);
	    if ((ofp->mode ^ fmode) & (FMODE_READWRITE|FMODE_BINMODE)) {
		if (FIXNUM_P(mode)) {
		    rb_raise(rb_eArgError, "incompatible mode 0%o", flags);
		}
		else {
		    rb_raise(rb_eArgError, "incompatible mode \"%s\"", RSTRING(mode)->ptr);
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
rb_file_initialize(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
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
rb_io_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    if (rb_block_given_p()) {
	char *cname = rb_class2name(klass);

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
rb_io_s_for_fd(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE io = rb_obj_alloc(klass);
    rb_io_initialize(argc, argv, io);
    return io;
}

static int binmode = 0;

static VALUE
argf_forward(argc, argv)
    int argc;
    VALUE *argv;
{
    return rb_funcall3(current_file, rb_frame_this_func(), argc, argv);
}

#define ARGF_FORWARD(argc, argv) do {\
  if (TYPE(current_file) != T_FILE)\
     return argf_forward(argc, argv);\
} while (0)
#define NEXT_ARGF_FORWARD(argc, argv) do {\
     if (!next_argv()) return Qnil;\
     ARGF_FORWARD(argc, argv);\
} while (0)

static void
argf_close(file)
    VALUE file;
{
    if (TYPE(file) == T_FILE)
	rb_io_close(file);
    else
	rb_funcall3(file, rb_intern("close"), 0, 0);
}

static int
next_argv()
{
    extern VALUE rb_argv;
    char *fn;
    OpenFile *fptr;
    int stdout_binmode = 0;

    if (TYPE(rb_stdout) == T_FILE) {
        GetOpenFile(rb_stdout, fptr);
        if (fptr->mode & FMODE_BINMODE)
            stdout_binmode = 1;
    }

    if (init_p == 0) {
	if (RARRAY(rb_argv)->len > 0) {
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
	if (RARRAY(rb_argv)->len > 0) {
	    filename = rb_ary_shift(rb_argv);
	    fn = StringValuePtr(filename);
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
		    struct stat st, st2;
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
			(void)unlink(RSTRING(str)->ptr);
			(void)rename(fn, RSTRING(str)->ptr);
			fr = rb_sysopen(RSTRING(str)->ptr, O_RDONLY, 0);
#else
			if (rename(fn, RSTRING(str)->ptr) < 0) {
			    rb_warn("Can't rename %s to %s: %s, skipping file",
				    fn, RSTRING(str)->ptr, strerror(errno));
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
	    if (binmode) rb_io_binmode(current_file);
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
argf_getline(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line;

  retry:
    if (!next_argv()) return Qnil;
    if (argc == 0 && rb_rs == rb_default_rs) {
	line = rb_io_gets(current_file);
    }
    else {
	VALUE rs;

	if (argc == 0) {
	    rs = rb_rs;
	}
	else {
	    rb_scan_args(argc, argv, "1", &rs);
	    if (!NIL_P(rs)) StringValue(rs);
	}
	line = rb_io_getline(rs, current_file);
    }
    if (NIL_P(line) && next_p != -1) {
	argf_close(current_file);
	next_p = 1;
	goto retry;
    }
    if (!NIL_P(line)) {
	gets_lineno++;
	lineno = INT2FIX(gets_lineno);
    }
    return line;
}

/*
 *  call-seq:
 *     gets(separator=$/)    => string or nil
 *
 *  Returns (and assigns to <code>$_</code>) the next line from the list
 *  of files in +ARGV+ (or <code>$*</code>), or from standard
 *  input if no files are present on the command line. Returns
 *  +nil+ at end of file. The optional argument specifies the
 *  record separator. The separator is included with the contents of
 *  each record. A separator of +nil+ reads the entire
 *  contents, and a zero-length separator reads the input one paragraph
 *  at a time, where paragraphs are divided by two consecutive newlines.
 *  If multiple filenames are present in +ARGV+,
 *  +gets(nil)+ will read the contents one file at a time.
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
rb_f_gets(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line;

    if (!next_argv()) return Qnil;
    if (TYPE(current_file) != T_FILE) {
	line = rb_funcall3(current_file, rb_intern("gets"), argc, argv);
    }
    else {
	line = argf_getline(argc, argv);
    }
    rb_lastline_set(line);
    return line;
}

VALUE
rb_gets()
{
    VALUE line;

    if (rb_rs != rb_default_rs) {
	return rb_f_gets(0, 0);
    }

  retry:
    if (!next_argv()) return Qnil;
    line = rb_io_gets(current_file);
    if (NIL_P(line) && next_p != -1) {
	argf_close(current_file);
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

/*
 *  call-seq:
 *     readline(separator=$/)   => string
 *
 *  Equivalent to <code>Kernel::gets</code>, except
 *  +readline+ raises +EOFError+ at end of file.
 */

static VALUE
rb_f_readline(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line;

    if (!next_argv()) rb_eof_error();
    ARGF_FORWARD(argc, argv);
    line = rb_f_gets(argc, argv);
    if (NIL_P(line)) {
	rb_eof_error();
    }

    return line;
}

/*
 * obsolete
 */
static VALUE
rb_f_getc()
{
    rb_warn("getc is obsolete; use STDIN.getc instead");
    if (TYPE(rb_stdin) != T_FILE) {
	return rb_funcall3(rb_stdin, rb_intern("getc"), 0, 0);
    }
    return rb_io_getc(rb_stdin);
}

/*
 *  call-seq:
 *     readlines(separator=$/)    => array
 *
 *  Returns an array containing the lines returned by calling
 *  <code>Kernel.gets(<i>separator</i>)</code> until the end of file.
 */

static VALUE
rb_f_readlines(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line, ary;

    NEXT_ARGF_FORWARD(argc, argv);
    ary = rb_ary_new();
    while (!NIL_P(line = argf_getline(argc, argv))) {
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
rb_f_backquote(obj, str)
    VALUE obj, str;
{
    VALUE port, result;
    OpenFile *fptr;

    SafeStringValue(str);
    port = pipe_open(1, &str, "r");
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
select_internal(read, write, except, tp, fds)
    VALUE read, write, except;
    struct timeval *tp;
    rb_fdset_t *fds;
{
    VALUE res, list;
    fd_set *rp, *wp, *ep;
    OpenFile *fptr;
    long i;
    int max = 0, n;
    int interrupt_flag = 0;
    int pending = 0;
    struct timeval timerec;

    if (!NIL_P(read)) {
	Check_Type(read, T_ARRAY);
	for (i=0; i<RARRAY(read)->len; i++) {
	    GetOpenFile(rb_io_get_io(RARRAY(read)->ptr[i]), fptr);
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
	for (i=0; i<RARRAY(write)->len; i++) {
	    GetOpenFile(rb_io_get_io(RARRAY(write)->ptr[i]), fptr);
	    rb_fd_set(fptr->fd, &fds[1]);
	    if (max < fptr->fd) max = fptr->fd;
	}
	wp = rb_fd_ptr(&fds[1]);
    }
    else
	wp = 0;

    if (!NIL_P(except)) {
	Check_Type(except, T_ARRAY);
	for (i=0; i<RARRAY(except)->len; i++) {
	    GetOpenFile(rb_io_get_io(RARRAY(except)->ptr[i]), fptr);
	    rb_fd_set(fptr->fd, &fds[2]);
	    if (max < fptr->fd) max = fptr->fd;
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
	    list = RARRAY(res)->ptr[0];
	    for (i=0; i< RARRAY(read)->len; i++) {
		GetOpenFile(rb_io_get_io(RARRAY(read)->ptr[i]), fptr);
		if (rb_fd_isset(fptr->fd, &fds[0]) ||
		    rb_fd_isset(fptr->fd, &fds[3])) {
		    rb_ary_push(list, rb_ary_entry(read, i));
		}
	    }
	}

	if (wp) {
	    list = RARRAY(res)->ptr[1];
	    for (i=0; i< RARRAY(write)->len; i++) {
		GetOpenFile(rb_io_get_io(RARRAY(write)->ptr[i]), fptr);
		if (rb_fd_isset(fptr->fd, &fds[1])) {
		    rb_ary_push(list, rb_ary_entry(write, i));
		}
	    }
	}

	if (ep) {
	    list = RARRAY(res)->ptr[2];
	    for (i=0; i< RARRAY(except)->len; i++) {
		GetOpenFile(rb_io_get_io(RARRAY(except)->ptr[i]), fptr);
		if (rb_fd_isset(fptr->fd, &fds[2])) {
		    rb_ary_push(list, rb_ary_entry(except, i));
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
select_call(arg)
    VALUE arg;
{
    struct select_args *p = (struct select_args *)arg;

    return select_internal(p->read, p->write, p->except, p->timeout, p->fdsets);
}

static VALUE
select_end(arg)
    VALUE arg;
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
rb_f_select(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
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
io_cntl(fd, cmd, narg, io_p)
    int fd, cmd, io_p;
    long narg;
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
rb_io_ctl(io, req, arg, io_p)
    VALUE io, req, arg;
    int io_p;
{
#if !defined(MSDOS) && !defined(__human68k__)
    int cmd = NUM2ULONG(req);
    OpenFile *fptr;
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

	    if (len <= RSTRING(arg)->len) {
		len = RSTRING(arg)->len;
	    }
	    if (RSTRING(arg)->len < len) {
		rb_str_resize(arg, len+1);
	    }
	    RSTRING(arg)->ptr[len] = 17;	/* a little sanity check here */
	    narg = (long)RSTRING(arg)->ptr;
	}
    }
    GetOpenFile(io, fptr);
    retval = io_cntl(fptr->fd, cmd, narg, io_p);
    if (retval < 0) rb_sys_fail(fptr->path);
    if (TYPE(arg) == T_STRING && RSTRING(arg)->ptr[len] != 17) {
	rb_raise(rb_eArgError, "return value overflowed string");
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
rb_io_ioctl(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
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
rb_io_fcntl(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
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
rb_f_syscall(argc, argv)
    int argc;
    VALUE *argv;
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
    arg[0] = NUM2LONG(argv[0]); argv++;
    while (items--) {
	VALUE v = rb_check_string_type(*argv);

	if (!NIL_P(v)) {
	    StringValue(v);
	    rb_str_modify(v);
	    arg[i] = (unsigned long)RSTRING(v)->ptr;
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

static VALUE io_new_instance _((VALUE));
static VALUE
io_new_instance(args)
    VALUE args;
{
    return rb_class_new_instance(2, (VALUE*)args+1, *(VALUE*)args);
}

/*
 *  call-seq:
 *     IO.pipe -> array
 *
 *  Creates a pair of pipe endpoints (connected to each other) and
 *  returns them as a two-element array of <code>IO</code> objects:
 *  <code>[</code> <i>read_file</i>, <i>write_file</i> <code>]</code>. Not
 *  available on all platforms.
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
rb_io_s_pipe(klass)
    VALUE klass;
{
#ifndef __human68k__
    int pipes[2], state;
    VALUE r, w, args[3];

#ifdef _WIN32
    if (_pipe(pipes, 1024, O_BINARY) == -1)
#else
    if (pipe(pipes) == -1)
#endif
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
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

struct foreach_arg {
    int argc;
    VALUE sep;
    VALUE io;
};

static VALUE
io_s_foreach(arg)
    struct foreach_arg *arg;
{
    VALUE str;

    while (!NIL_P(str = rb_io_getline(arg->sep, arg->io))) {
	rb_yield(str);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     IO.foreach(name, sep_string=$/) {|line| block }   => nil
 *
 *  Executes the block for every line in the named I/O port, where lines
 *  are separated by <em>sep_string</em>.
 *
 *     IO.foreach("testfile") {|x| print "GOT ", x }
 *
 *  <em>produces:</em>
 *
 *     GOT This is line one
 *     GOT This is line two
 *     GOT This is line three
 *     GOT And so on...
 */

static VALUE
rb_io_s_foreach(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "11", &fname, &arg.sep);
    FilePathValue(fname);
    if (argc == 1) {
	arg.sep = rb_default_rs;
    }
    else if (!NIL_P(arg.sep)) {
	StringValue(arg.sep);
    }
    arg.io = rb_io_open(RSTRING(fname)->ptr, "r");
    if (NIL_P(arg.io)) return Qnil;

    return rb_ensure(io_s_foreach, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
io_s_readlines(arg)
    struct foreach_arg *arg;
{
    return rb_io_readlines(arg->argc, &arg->sep, arg->io);
}

/*
 *  call-seq:
 *     IO.readlines(name, sep_string=$/)   => array
 *
 *  Reads the entire file specified by <i>name</i> as individual
 *  lines, and returns those lines in an array. Lines are separated by
 *  <i>sep_string</i>.
 *
 *     a = IO.readlines("testfile")
 *     a[0]   #=> "This is line one\n"
 *
 */

static VALUE
rb_io_s_readlines(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "11", &fname, &arg.sep);
    FilePathValue(fname);
    arg.argc = argc - 1;
    arg.io = rb_io_open(RSTRING(fname)->ptr, "r");
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(io_s_readlines, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
io_s_read(arg)
    struct foreach_arg *arg;
{
    return io_read(arg->argc, &arg->sep, arg->io);
}

/*
 *  call-seq:
 *     IO.read(name, [length [, offset]] )   => string
 *
 *  Opens the file, optionally seeks to the given offset, then returns
 *  <i>length</i> bytes (defaulting to the rest of the file).
 *  <code>read</code> ensures the file is closed before returning.
 *
 *     IO.read("testfile")           #=> "This is line one\nThis is line two\nThis is line three\nAnd so on...\n"
 *     IO.read("testfile", 20)       #=> "This is line one\nThi"
 *     IO.read("testfile", 20, 10)   #=> "ne one\nThis is line "
 */

static VALUE
rb_io_s_read(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname, offset;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "12", &fname, &arg.sep, &offset);
    FilePathValue(fname);
    arg.argc = argc ? 1 : 0;
    arg.io = rb_io_open(RSTRING(fname)->ptr, "r");
    if (NIL_P(arg.io)) return Qnil;
    if (!NIL_P(offset)) {
	rb_io_seek(arg.io, offset, SEEK_SET);
    }
    return rb_ensure(io_s_read, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
argf_tell()
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to tell");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_tell(current_file);
}

static VALUE
argf_seek_m(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to seek");
    }
    ARGF_FORWARD(argc, argv);
    return rb_io_seek_m(argc, argv, current_file);
}

static VALUE
argf_set_pos(self, offset)
     VALUE self, offset;
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to set position");
    }
    ARGF_FORWARD(1, &offset);
    return rb_io_set_pos(current_file, offset);
}

static VALUE
argf_rewind()
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to rewind");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_rewind(current_file);
}

static VALUE
argf_fileno()
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream");
    }
    ARGF_FORWARD(0, 0);
    return rb_io_fileno(current_file);
}

static VALUE
argf_to_io()
{
    next_argv();
    ARGF_FORWARD(0, 0);
    return current_file;
}

static VALUE
argf_eof()
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
argf_read(argc, argv)
    int argc;
    VALUE *argv;
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
    if (TYPE(current_file) != T_FILE) {
	tmp = argf_forward(argc, argv);
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
	if (RSTRING(str)->len < len) {
	    len -= RSTRING(str)->len;
	    argv[0] = INT2NUM(len);
	    goto retry;
	}
    }
    return str;
}

static VALUE
argf_readpartial_rescue(VALUE dummy)
{
    return Qnil;
}

static VALUE
argf_readpartial(int argc, VALUE *argv)
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
    if (TYPE(current_file) != T_FILE) {
        tmp = rb_rescue2(argf_forward, (VALUE)argv,
                         argf_readpartial_rescue, (VALUE)Qnil,
                         rb_eEOFError, (VALUE)0);
    }
    else {
        tmp = io_getpartial(argc, argv, current_file);
    }
    if (NIL_P(tmp)) {
        if (next_p == -1) {
            rb_eof_error();
        }
        argf_close(current_file);
        next_p = 1;
        if (RARRAY(rb_argv)->len == 0)
            rb_eof_error();
        if (NIL_P(str))
            str = rb_str_new(NULL, 0);
        return str;
    }
    return tmp;
}

static VALUE
argf_getc()
{
    VALUE byte;

  retry:
    if (!next_argv()) return Qnil;
    if (TYPE(current_file) != T_FILE) {
	byte = rb_funcall3(current_file, rb_intern("getc"), 0, 0);
    }
    else {
	byte = rb_io_getc(current_file);
    }
    if (NIL_P(byte) && next_p != -1) {
	argf_close(current_file);
	next_p = 1;
	goto retry;
    }

    return byte;
}

static VALUE
argf_readchar()
{
    VALUE c;

    NEXT_ARGF_FORWARD(0, 0);
    c = argf_getc();
    if (NIL_P(c)) {
	rb_eof_error();
    }
    return c;
}

static VALUE
argf_each_line(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str;

    if (!next_argv()) return Qnil;
    if (TYPE(current_file) != T_FILE) {
	for (;;) {
	    if (!next_argv()) return argf;
	    rb_iterate(rb_each, current_file, rb_yield, 0);
	    next_p = 1;
	}
    }
    while (!NIL_P(str = argf_getline(argc, argv))) {
	rb_yield(str);
    }
    return argf;
}

static VALUE
argf_each_byte()
{
    VALUE byte;

    while (!NIL_P(byte = argf_getc())) {
	rb_yield(byte);
    }
    return argf;
}

static VALUE
argf_filename()
{
    next_argv();
    return filename;
}

static VALUE
argf_file()
{
    next_argv();
    return current_file;
}

static VALUE
argf_binmode()
{
    binmode = 1;
    next_argv();
    ARGF_FORWARD(0, 0);
    rb_io_binmode(current_file);
    return argf;
}

static VALUE
argf_skip()
{
    if (next_p != -1) {
	argf_close(current_file);
	next_p = 1;
    }
    return argf;
}

static VALUE
argf_close_m()
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
argf_closed()
{
    next_argv();
    ARGF_FORWARD(0, 0);
    return rb_io_closed(current_file);
}

static VALUE
argf_to_s()
{
    return rb_str_new2("ARGF");
}

static VALUE
opt_i_get()
{
    if (!ruby_inplace_mode) return Qnil;
    return rb_str_new2(ruby_inplace_mode);
}

static void
opt_i_set(val)
    VALUE val;
{
    if (!RTEST(val)) {
	if (ruby_inplace_mode) free(ruby_inplace_mode);
	ruby_inplace_mode = 0;
	return;
    }
    StringValue(val);
    if (ruby_inplace_mode) free(ruby_inplace_mode);
    ruby_inplace_mode = 0;
    ruby_inplace_mode = strdup(RSTRING(val)->ptr);
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
Init_IO()
{
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

    rb_define_global_function("syscall", rb_f_syscall, -1);

    rb_define_global_function("open", rb_f_open, -1);
    rb_define_global_function("printf", rb_f_printf, -1);
    rb_define_global_function("print", rb_f_print, -1);
    rb_define_global_function("putc", rb_f_putc, 1);
    rb_define_global_function("puts", rb_f_puts, -1);
    rb_define_global_function("gets", rb_f_gets, -1);
    rb_define_global_function("readline", rb_f_readline, -1);
    rb_define_global_function("getc", rb_f_getc, 0);
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
    rb_define_singleton_method(rb_cIO, "pipe", rb_io_s_pipe, 0);

    rb_define_method(rb_cIO, "initialize", rb_io_initialize, -1);

    rb_output_fs = Qnil;
    rb_define_hooked_variable("$,", &rb_output_fs, 0, rb_str_setter);

    rb_rs = rb_default_rs = rb_str_new2("\n");
    rb_output_rs = Qnil;
    rb_global_variable(&rb_default_rs);
    OBJ_FREEZE(rb_default_rs);	/* avoid modifying RS_default */
    rb_define_hooked_variable("$/", &rb_rs, 0, rb_str_setter);
    rb_define_hooked_variable("$-0", &rb_rs, 0, rb_str_setter);
    rb_define_hooked_variable("$\\", &rb_output_rs, 0, rb_str_setter);

    rb_define_hooked_variable("$.", &lineno, 0, lineno_setter);
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

    rb_define_method(rb_cIO, "readpartial",  io_readpartial, -1);
    rb_define_method(rb_cIO, "read",  io_read, -1);
    rb_define_method(rb_cIO, "write", io_write, 1);
    rb_define_method(rb_cIO, "gets",  rb_io_gets_m, -1);
    rb_define_method(rb_cIO, "readline",  rb_io_readline, -1);
    rb_define_method(rb_cIO, "getc",  rb_io_getc, 0);
    rb_define_method(rb_cIO, "readchar",  rb_io_readchar, 0);
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

    rb_define_method(rb_cIO, "close", rb_io_close_m, 0);
    rb_define_method(rb_cIO, "closed?", rb_io_closed, 0);
    rb_define_method(rb_cIO, "close_read", rb_io_close_read, 0);
    rb_define_method(rb_cIO, "close_write", rb_io_close_write, 0);

    rb_define_method(rb_cIO, "isatty", rb_io_isatty, 0);
    rb_define_method(rb_cIO, "tty?", rb_io_isatty, 0);
    rb_define_method(rb_cIO, "binmode",  rb_io_binmode, 0);
    rb_define_method(rb_cIO, "sysseek", rb_io_sysseek, -1);

    rb_define_method(rb_cIO, "ioctl", rb_io_ioctl, -1);
    rb_define_method(rb_cIO, "fcntl", rb_io_fcntl, -1);
    rb_define_method(rb_cIO, "pid", rb_io_pid, 0);
    rb_define_method(rb_cIO, "inspect",  rb_io_inspect, 0);

    rb_stdin = prep_stdio(stdin, FMODE_READABLE, rb_cIO, "<STDIN>");
    rb_define_variable("$stdin", &rb_stdin);
    rb_stdout = prep_stdio(stdout, FMODE_WRITABLE, rb_cIO, "<STDOUT>");
    rb_define_hooked_variable("$stdout", &rb_stdout, 0, stdout_setter);
    rb_stderr = prep_stdio(stderr, FMODE_WRITABLE|FMODE_SYNC, rb_cIO, "<STDERR>");
    rb_define_hooked_variable("$stderr", &rb_stderr, 0, stdout_setter);
    rb_define_hooked_variable("$>", &rb_stdout, 0, stdout_setter);
    orig_stdout = rb_stdout;
    rb_deferr = orig_stderr = rb_stderr;

    /* variables to be removed in 1.8.1 */
    rb_define_hooked_variable("$defout", &rb_stdout, 0, defout_setter);
    rb_define_hooked_variable("$deferr", &rb_stderr, 0, deferr_setter);

    /* constants to hold original stdin/stdout/stderr */
    rb_define_global_const("STDIN", rb_stdin);
    rb_define_global_const("STDOUT", rb_stdout);
    rb_define_global_const("STDERR", rb_stderr);

    argf = rb_obj_alloc(rb_cObject);
    rb_extend_object(argf, rb_mEnumerable);

    rb_define_readonly_variable("$<", &argf);
    rb_define_global_const("ARGF", argf);

    rb_define_singleton_method(argf, "to_s", argf_to_s, 0);

    rb_define_singleton_method(argf, "fileno", argf_fileno, 0);
    rb_define_singleton_method(argf, "to_i", argf_fileno, 0);
    rb_define_singleton_method(argf, "to_io", argf_to_io, 0);
    rb_define_singleton_method(argf, "each",  argf_each_line, -1);
    rb_define_singleton_method(argf, "each_line",  argf_each_line, -1);
    rb_define_singleton_method(argf, "each_byte",  argf_each_byte, 0);

    rb_define_singleton_method(argf, "read",  argf_read, -1);
    rb_define_singleton_method(argf, "readpartial",  argf_readpartial, -1);
    rb_define_singleton_method(argf, "readlines", rb_f_readlines, -1);
    rb_define_singleton_method(argf, "to_a", rb_f_readlines, -1);
    rb_define_singleton_method(argf, "gets", rb_f_gets, -1);
    rb_define_singleton_method(argf, "readline", rb_f_readline, -1);
    rb_define_singleton_method(argf, "getc", argf_getc, 0);
    rb_define_singleton_method(argf, "readchar", argf_readchar, 0);
    rb_define_singleton_method(argf, "tell", argf_tell, 0);
    rb_define_singleton_method(argf, "seek", argf_seek_m, -1);
    rb_define_singleton_method(argf, "rewind", argf_rewind, 0);
    rb_define_singleton_method(argf, "pos", argf_tell, 0);
    rb_define_singleton_method(argf, "pos=", argf_set_pos, 1);
    rb_define_singleton_method(argf, "eof", argf_eof, 0);
    rb_define_singleton_method(argf, "eof?", argf_eof, 0);
    rb_define_singleton_method(argf, "binmode", argf_binmode, 0);

    rb_define_singleton_method(argf, "filename", argf_filename, 0);
    rb_define_singleton_method(argf, "path", argf_filename, 0);
    rb_define_singleton_method(argf, "file", argf_file, 0);
    rb_define_singleton_method(argf, "skip", argf_skip, 0);
    rb_define_singleton_method(argf, "close", argf_close_m, 0);
    rb_define_singleton_method(argf, "closed?", argf_closed, 0);

    rb_define_singleton_method(argf, "lineno",   argf_lineno, 0);
    rb_define_singleton_method(argf, "lineno=",  argf_set_lineno, 1);

    rb_global_variable(&current_file);
    filename = rb_str_new2("-");
    rb_define_readonly_variable("$FILENAME", &filename);

    rb_define_virtual_variable("$-i", opt_i_get, opt_i_set);

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
#endif
#ifdef O_SYNC
    rb_file_const("SYNC", INT2FIX(O_SYNC));
#endif
}
