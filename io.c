/**********************************************************************

  io.c -

  $Author$
  $Date$
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"
#include "env.h"
#include <ctype.h>
#include <errno.h>

#if defined(MSDOS) || defined(__BOW__) || defined(__CYGWIN__) || defined(NT) || defined(__human68k__) || defined(__EMX__) || defined(__BEOS__)
# define NO_SAFE_RENAME
#endif

#if defined(MSDOS) || defined(__CYGWIN__) || defined(NT)
# define NO_LONG_FNAME
#endif

#if defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(sun) || defined(_nec_ews)
# define USE_SETVBUF
#endif

#include <sys/types.h>
#if !defined(DJGPP) && !defined(NT) && !defined(__human68k__)
#include <sys/ioctl.h>
#endif
#if defined(HAVE_FCNTL_H) || defined(NT)
#include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
#include <sys/fcntl.h>
#endif

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
#ifndef NT
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif
#endif
#ifdef HAVE_VFORK_H
#include <vfork.h>
#endif

#include <sys/stat.h>

/* EMX has sys/parm.h, but.. */
#if defined(HAVE_SYS_PARAM_H) && !defined(__EMX__)
# include <sys/param.h>
#else
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

VALUE rb_cIO;
VALUE rb_eEOFError;
VALUE rb_eIOError;

VALUE rb_stdin, rb_stdout, rb_stderr, rb_defout;
static VALUE orig_stdin, orig_stdout, orig_stderr;

VALUE rb_output_fs;
VALUE rb_rs;
VALUE rb_output_rs;
VALUE rb_default_rs;

static VALUE argf;

static ID id_write;

extern char *ruby_inplace_mode;

struct timeval rb_time_interval _((VALUE));

static VALUE filename, current_file;
static int gets_lineno;
static int init_p = 0, next_p = 0, first_p = 1;
static VALUE lineno;

#ifdef _STDIO_USES_IOSTREAM  /* GNU libc */
#  ifdef _IO_fpos_t
#    define READ_DATA_PENDING(fp) ((fp)->_IO_read_ptr != (fp)->_IO_read_end)
#  else
#    define READ_DATA_PENDING(fp) ((fp)->_gptr < (fp)->_egptr)
#  endif
#elif defined(FILE_COUNT)
#  define READ_DATA_PENDING(fp) ((fp)->FILE_COUNT > 0)
#elif defined(__BEOS__)
#  define READ_DATA_PENDING(fp) (fp->_state._eof == 0)
#else
/* requires systems own version of the ReadDataPending() */
extern int ReadDataPending();
#  define READ_DATA_PENDING(fp) ReadDataPending(fp)
#endif

#define READ_CHECK(fp) do {\
    if (!READ_DATA_PENDING(fp)) {\
	rb_thread_wait_fd(fileno(fp));\
        rb_io_check_closed(fptr);\
     }\
} while(0)

void
rb_eof_error()
{
    rb_raise(rb_eEOFError, "End of file reached");
}

VALUE
rb_io_taint_check(io)
    VALUE io;
{
    if (!OBJ_TAINTED(io) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: operation on untainted IO");
    return io;
}

void
rb_io_check_closed(fptr)
    OpenFile *fptr;
{
    if (!fptr) {
	rb_raise(rb_eIOError, "uninitialized stream");
    }
    if (!fptr->f && !fptr->f2) {
	rb_raise(rb_eIOError, "closed stream");
    }
}

void
rb_io_check_readable(fptr)
    OpenFile *fptr;
{
    if (!(fptr->mode & FMODE_READABLE)) {
	rb_raise(rb_eIOError, "not opened for reading");
    }
}

void
rb_io_check_writable(fptr)
    OpenFile *fptr;
{
    if (!(fptr->mode & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "not opened for writing");
    }
}

int
rb_read_pending(fp)
    FILE *fp;
{
    return READ_DATA_PENDING(fp);
}

void
rb_read_check(fp)
    FILE *fp;
{
    if (!READ_DATA_PENDING(fp)) {
	rb_thread_wait_fd(fileno(fp));
    }
}

static int
rb_dup(orig)
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

static void
io_fflush(f, path)
    FILE *f;
    const char *path;
{
    int n;

    rb_thread_fd_writable(fileno(f));
    TRAP_BEG;
    n = fflush(f);
    TRAP_END;
    if (n == EOF) rb_sys_fail(path);
}

/* writing functions */
static VALUE
io_write(io, str)
    VALUE io, str;
{
    OpenFile *fptr;
    FILE *f;
    int n;

    rb_secure(4);
    if (TYPE(str) != T_STRING)
	str = rb_obj_as_string(str);
    if (RSTRING(str)->len == 0) return INT2FIX(0);

    if (TYPE(io) != T_FILE) {
	/* port is not IO, call write method for it. */
	return rb_funcall(io, id_write, 1, str);
    }

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);
    f = GetWriteFile(fptr);

#ifdef __human68k__
    {
	register char *ptr = RSTRING(str)->ptr;
	n = (int)RSTRING(str)->len;
	while (--n >= 0)
	    if (fputc(*ptr++, f) == EOF)
		rb_sys_fail(fptr->path);
	n = ptr - RSTRING(str)->ptr;
    }
    if (ferror(f))
	rb_sys_fail(fptr->path);
#else
    n = fwrite(RSTRING(str)->ptr, 1, RSTRING(str)->len, f);
    if (ferror(f)) {
	rb_sys_fail(fptr->path);
    }
#endif
    if (fptr->mode & FMODE_SYNC) {
	io_fflush(f, fptr->path);
    }

    return INT2FIX(n);
}

VALUE
rb_io_write(io, str)
    VALUE io, str;
{
    return rb_funcall(io, id_write, 1, str);
}

static VALUE
rb_io_addstr(io, str)
    VALUE io, str;
{
    rb_io_write(io, str);
    return io;
}

static VALUE
rb_io_flush(io)
    VALUE io;
{
    OpenFile *fptr;
    FILE *f;

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);
    f = GetWriteFile(fptr);
    
    io_fflush(f, fptr->path);

    return io;
}

static VALUE
rb_io_tell(io)
     VALUE io;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(io, fptr);
    pos = ftell(fptr->f);
    if (ferror(fptr->f)) rb_sys_fail(fptr->path);

    return rb_int2inum(pos);
}

#ifndef SEEK_CUR
# define SEEK_SET 0
# define SEEK_CUR 1
# define SEEK_END 2
#endif

static VALUE
rb_io_seek(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE offset, ptrname;
    int whence;
    OpenFile *fptr;
    long pos;

    rb_scan_args(argc, argv, "11", &offset, &ptrname);
    if (argc == 1) whence = SEEK_SET;
    else whence = NUM2INT(ptrname);

    GetOpenFile(io, fptr);
    pos = fseek(fptr->f, NUM2INT(offset), whence);
    if (pos != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2FIX(0);
}

static VALUE
rb_io_set_pos(io, offset)
     VALUE io, offset;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(io, fptr);
    pos = fseek(fptr->f, NUM2INT(offset), SEEK_SET);
    if (pos != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2NUM(pos);
}

static VALUE
rb_io_rewind(io)
     VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (fseek(fptr->f, 0L, 0) != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);
    if (io == current_file) {
	gets_lineno -= fptr->lineno;
    }
    fptr->lineno = 0;

    return INT2FIX(0);
}

VALUE
rb_io_eof(io)
    VALUE io;
{
    OpenFile *fptr;
    int ch;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (feof(fptr->f)) return Qtrue;
    if (READ_DATA_PENDING(fptr->f)) return Qfalse;
    READ_CHECK(fptr->f);
    TRAP_BEG;
    ch = getc(fptr->f);
    TRAP_END;

    if (ch != EOF) {
	ungetc(ch, fptr->f);
	return Qfalse;
    }
    return Qtrue;
}

static VALUE
rb_io_sync(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    return (fptr->mode & FMODE_SYNC) ? Qtrue : Qfalse;
}

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

static VALUE
rb_io_fileno(io)
    VALUE io;
{
    OpenFile *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = fileno(fptr->f);
    return INT2FIX(fd);
}

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

static VALUE
rb_io_to_io(io)
    VALUE io;
{
    return io;
}

/* reading functions */

static long
io_fread(ptr, len, f)
    char *ptr;
    long len;
    FILE *f;
{
    long n = len;
    int c;

    while (n--) {
	if (!READ_DATA_PENDING(f)) {
	    rb_thread_wait_fd(fileno(f));
	}
	TRAP_BEG;
	c = getc(f);
	TRAP_END;
	if (c == EOF) {
	    if (ferror(f)) {
		if (errno == EINTR) continue;
		if (errno == EAGAIN) return len - n;
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
		if (errno == EWOULDBLOCK) return len - n;
#endif
		return 0;
	    }
	    *ptr = '\0';
	    break;
	}
	*ptr++ = c;
    }

    return len - n - 1;
}

#ifndef S_ISREG
#   define S_ISREG(m) ((m & S_IFMT) == S_IFREG)
#endif

#define SMALLBUF 100

static VALUE
read_all(port)
    VALUE port;
{
    OpenFile *fptr;
    VALUE str = Qnil;
    struct stat st;
    long siz = BUFSIZ;
    long bytes = 0;
    int n;

    GetOpenFile(port, fptr);
    rb_io_check_readable(fptr);

    if (feof(fptr->f)) return Qnil;
    if (fstat(fileno(fptr->f), &st) == 0  && S_ISREG(st.st_mode)
#ifdef __BEOS__
	&& (st.st_dev > 3)
#endif
	)
    {
	if (st.st_size == 0) {
	    getc(fptr->f);	/* force EOF */
	    return rb_str_new(0, 0);
	}
	else {
	    long pos = ftell(fptr->f);
	    if (st.st_size > pos && pos >= 0) {
		siz = st.st_size - pos + 1;
	    }
	}
    }
    str = rb_tainted_str_new(0, siz);
    READ_CHECK(fptr->f);
    for (;;) {
	n = io_fread(RSTRING(str)->ptr+bytes, siz-bytes, fptr->f);
	if (n == 0 && bytes == 0) {
	    if (feof(fptr->f)) return Qnil;
	    rb_sys_fail(fptr->path);
	}
	bytes += n;
	if (bytes < siz) break;
	siz += BUFSIZ;
	rb_str_resize(str, siz);
    }
    if (bytes == 0) return rb_str_new(0,0);
    if (bytes != siz) rb_str_resize(str, bytes);

    return str;
}

static VALUE
io_read(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    OpenFile *fptr;
    int n, len;
    VALUE length, str;

    rb_scan_args(argc, argv, "01", &length);
    if (NIL_P(length)) {
	return read_all(io);
    }

    len = NUM2INT(length);
    if (len < 0) {
	rb_raise(rb_eArgError, "negative length %d given", len);
    }
    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (feof(fptr->f)) return Qnil;
    str = rb_str_new(0, len);
    if (len == 0) return str;

    READ_CHECK(fptr->f);
    n = io_fread(RSTRING(str)->ptr, len, fptr->f);
    if (n == 0) {
	if (feof(fptr->f)) return Qnil;
	rb_sys_fail(fptr->path);
    }
    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';
    OBJ_TAINT(str);

    return str;
}

static VALUE
rb_io_gets_internal(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    OpenFile *fptr;
    FILE *f;
    VALUE str = Qnil;
    int c, newline;
    char *rsptr;
    int rslen, rspara = 0;
    VALUE rs;

    if (argc == 0) {
	rs = rb_rs;
    }
    else {
	rb_scan_args(argc, argv, "1", &rs);
	if (!NIL_P(rs)) Check_Type(rs, T_STRING);
    }

    if (NIL_P(rs)) {
	rsptr = 0;
	rslen = 0;
    }
    else if (rs == rb_default_rs) {
	return rb_io_gets(io);
    }
    else {
	rslen = RSTRING(rs)->len;
	if (rslen == 0) {
	    rsptr = "\n\n";
	    rslen = 2;
	    rspara = 1;
	}
	else if (rslen == 1 && RSTRING(rs)->ptr[0] == '\n') {
	    return rb_io_gets(io);
	}
	else {
	    rsptr = RSTRING(rs)->ptr;
	}
    }

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    f = fptr->f;

    if (rspara) {
	do {
	    READ_CHECK(f);
	    TRAP_BEG;
	    c = getc(f);
	    TRAP_END;
	    if (c != '\n') {
		ungetc(c,f);
		break;
	    }
	} while (c != EOF);
    }

    newline = rslen ? rsptr[rslen - 1] : 0777;
    {
	char buf[8192];
	char *bp, *bpe = buf + sizeof buf - 3;
	int cnt;
	int append = 0;

      again:
	bp = buf;

	if (rslen) {
	    for (;;) {
		READ_CHECK(f);
		TRAP_BEG;
		c = getc(f);
		TRAP_END;
		if (c == EOF) {
		    if (ferror(f)) {
			if (errno == EINTR) continue;
			rb_sys_fail(fptr->path);
		    }
		    break;
		}
		if ((*bp++ = c) == newline) break;
		if (bp == bpe) break;
	    }
	    cnt = bp - buf;
	}
	else {
	    READ_CHECK(f);
	    cnt = io_fread(buf, sizeof(buf), f);
	    if (cnt == 0) {
		if (ferror(f)) rb_sys_fail(fptr->path);
		c = EOF;
	    }
	    else {
		c = 0;
	    }
	}

	if (c == EOF && !append && cnt == 0) {
	    str = Qnil;
	    goto return_gets;
	}

	if (append)
	    rb_str_cat(str, buf, cnt);
	else
	    str = rb_str_new(buf, cnt);

	if (c != EOF &&
	    (!rslen ||
	     RSTRING(str)->len < rslen ||
	     memcmp(RSTRING(str)->ptr+RSTRING(str)->len-rslen,rsptr,rslen))) {
	    append = 1;
	    goto again;
	}
    }

  return_gets:
    if (rspara) {
	while (c != EOF) {
	    READ_CHECK(f);
	    TRAP_BEG;
	    c = getc(f);
	    TRAP_END;
	    if (c != '\n') {
		ungetc(c, f);
		break;
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
    FILE *f;
    VALUE str = Qnil;
    int c;
    char buf[8192];
    char *bp, *bpe = buf + sizeof buf - 3;
    int cnt;
    int append = 0;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    f = fptr->f;

  again:
    bp = buf;
    for (;;) {
	READ_CHECK(f);
	TRAP_BEG;
	c = getc(f);
	TRAP_END;
	if (c == EOF) {
	    if (ferror(f)) {
		if (errno == EINTR) continue;
		rb_sys_fail(fptr->path);
	    }
	    break;
	}
	if ((*bp++ = c) == '\n') break;
	if (bp == bpe) break;
    }
    cnt = bp - buf;

    if (c == EOF && !append && cnt == 0) {
	str = Qnil;
	goto return_gets;
    }

    if (append)
	rb_str_cat(str, buf, cnt);
    else
	str = rb_str_new(buf, cnt);

    if (c != EOF && RSTRING(str)->ptr[RSTRING(str)->len-1] != '\n') {
	append = 1;
	goto again;
    }

  return_gets:
    if (!NIL_P(str)) {
	fptr->lineno++;
	lineno = INT2FIX(fptr->lineno);
	OBJ_TAINT(str);
    }

    return str;
}

static VALUE
rb_io_gets_m(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE str = rb_io_gets_internal(argc, argv, io);

    if (!NIL_P(str)) {
	rb_lastline_set(str);
    }
    return str;
}

static VALUE
rb_io_lineno(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    return INT2NUM(fptr->lineno);
}

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

static VALUE
rb_io_readlines(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE line, ary;

    ary = rb_ary_new();
    while (!NIL_P(line = rb_io_gets_internal(argc, argv, io))) {
	rb_ary_push(ary, line);
    }
    return ary;
}

static VALUE
rb_io_each_line(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE str;

    while (!NIL_P(str = rb_io_gets_internal(argc, argv, io))) {
	rb_yield(str);
    }
    return io;
}

static VALUE
rb_io_each_byte(io)
    VALUE io;
{
    OpenFile *fptr;
    FILE *f;
    int c;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    f = fptr->f;

    for (;;) {
	READ_CHECK(f);
	TRAP_BEG;
	c = getc(f);
	TRAP_END;
	if (c == EOF) {
	    if (ferror(f)) {
		if (errno == EINTR) continue;
		rb_sys_fail(fptr->path);
	    }
	    break;
	}
	rb_yield(INT2FIX(c & 0xff));
    }
    if (ferror(f)) rb_sys_fail(fptr->path);
    return Qnil;
}

VALUE
rb_io_getc(io)
    VALUE io;
{
    OpenFile *fptr;
    FILE *f;
    int c;

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);
    f = fptr->f;

  retry:
    READ_CHECK(f);
    TRAP_BEG;
    c = getc(f);
    TRAP_END;

    if (c == EOF) {
	if (ferror(f)) {
	    if (errno == EINTR) goto retry;
	    rb_sys_fail(fptr->path);
	}
	return Qnil;
    }
    return INT2FIX(c & 0xff);
}

int
rb_getc(f)
    FILE *f;
{
    int c;

    if (!READ_DATA_PENDING(f)) {
	rb_thread_wait_fd(fileno(f));
    }
    TRAP_BEG;
    c = getc(f);
    TRAP_END;

    return c;
}

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

VALUE
rb_io_ungetc(io, c)
    VALUE io, c;
{
    OpenFile *fptr;
    int cc = NUM2INT(c);

    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (ungetc(cc, fptr->f) == EOF)
	rb_sys_fail(fptr->path);
    return Qnil;
}

static VALUE
rb_io_isatty(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (isatty(fileno(fptr->f)) == 0)
	return Qfalse;
    return Qtrue;
}

static void
fptr_finalize(fptr)
    OpenFile *fptr;
{
    if (fptr->f) {
	fclose(fptr->f);
    }
    if (fptr->f2) {
	fclose(fptr->f2);
    }
}

static void
rb_io_fptr_cleanup(fptr)
    OpenFile *fptr;
{
    if (fptr->finalize) {
	(*fptr->finalize)(fptr);
    }
    else {
	fptr_finalize(fptr);
    }
    fptr->f = fptr->f2 = 0;

    if (fptr->path) {
	free(fptr->path);
	fptr->path = 0;
    }
}

void
rb_io_fptr_finalize(fptr)
    OpenFile *fptr;
{
    if (!fptr) return;
    if (!fptr->f && !fptr->f2) return;
    if (fileno(fptr->f) < 3) return;

    rb_io_fptr_cleanup(fptr);
}

static void
rb_io_fptr_close(fptr)
    OpenFile *fptr;
{
    int fd;

    if (!fptr) return;
    if (!fptr->f && !fptr->f2) return;

    fd = fileno(fptr->f);
    rb_io_fptr_cleanup(fptr);
    rb_thread_fd_close(fd);
}

VALUE
rb_io_close(io)
    VALUE io;
{
    OpenFile *fptr;

    fptr = RFILE(io)->fptr;
    rb_io_fptr_close(fptr);
    if (fptr->pid) {
	rb_syswait(fptr->pid);
	fptr->pid = 0;
    }

    return Qnil;
}

static VALUE
rb_io_close_m(io)
    VALUE io;
{
    if (rb_safe_level() >= 4 && !OBJ_TAINTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    rb_io_close(io);
    return Qnil;
}

static VALUE
rb_io_closed(io)
    VALUE io;
{
    OpenFile *fptr;

    fptr = RFILE(io)->fptr;
    return (fptr->f || fptr->f2)?Qfalse:Qtrue;
}

static VALUE
rb_io_close_read(io)
    VALUE io;
{
    OpenFile *fptr;
    int n;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    GetOpenFile(io, fptr);
    if (fptr->f2 == 0 && (fptr->mode & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "closing non-duplex IO for reading");
    }
    if (fptr->f2 == 0) {
	return rb_io_close(io);
    }
    n = fclose(fptr->f);
    fptr->mode &= ~FMODE_READABLE;
    fptr->f = fptr->f2;
    fptr->f2 = 0;
    if (n != 0) rb_sys_fail(fptr->path);

    return Qnil;
}

static VALUE
rb_io_close_write(io)
    VALUE io;
{
    OpenFile *fptr;
    int n;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(io)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
    GetOpenFile(io, fptr);
    if (fptr->f2 == 0 && (fptr->mode & FMODE_READABLE)) {
	rb_raise(rb_eIOError, "closing non-duplex IO for writing");
    }
    if (fptr->f2 == 0) {
	return rb_io_close(io);
    }
    n = fclose(fptr->f2);
    fptr->f2 = 0;
    fptr->mode &= ~FMODE_WRITABLE;
    if (n != 0) rb_sys_fail(fptr->path);

    return Qnil;
}

static VALUE
rb_io_syswrite(io, str)
    VALUE io, str;
{
    OpenFile *fptr;
    FILE *f;
    int n;

    rb_secure(4);
    if (TYPE(str) != T_STRING)
	str = rb_obj_as_string(str);

    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);
    f = GetWriteFile(fptr);

    if (!rb_thread_fd_writable(fileno(f))) {
        rb_io_check_closed(fptr);
    }
    n = write(fileno(f), RSTRING(str)->ptr, RSTRING(str)->len);

    if (n == -1) rb_sys_fail(fptr->path);

    return INT2FIX(n);
}

static VALUE
rb_io_sysread(io, len)
    VALUE io, len;
{
    OpenFile *fptr;
    int n, ilen;
    VALUE str;

    ilen = NUM2INT(len);
    GetOpenFile(io, fptr);
    rb_io_check_readable(fptr);

    if (READ_DATA_PENDING(fptr->f)) {
	rb_raise(rb_eIOError, "sysread for buffered IO");
    }
    str = rb_str_new(0, ilen);

    rb_thread_wait_fd(fileno(fptr->f));
    TRAP_BEG;
    n = read(fileno(fptr->f), RSTRING(str)->ptr, RSTRING(str)->len);
    TRAP_END;

    if (n == -1) rb_sys_fail(fptr->path);
    if (n == 0 && ilen > 0) {
	rb_eof_error();
    }

    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';
    OBJ_TAINT(str);

    return str;
}

VALUE
rb_io_binmode(io)
    VALUE io;
{
#if defined(NT) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__) || defined(__EMX__)
    OpenFile *fptr;

    GetOpenFile(io, fptr);
#ifdef __human68k__
    if (fptr->f)
	fmode(fptr->f, _IOBIN);
    if (fptr->f2)
	fmode(fptr->f2, _IOBIN);
#else
    if (fptr->f && setmode(fileno(fptr->f), O_BINARY) == -1)
	rb_sys_fail(fptr->path);
    if (fptr->f2 && setmode(fileno(fptr->f2), O_BINARY) == -1)
	rb_sys_fail(fptr->path);
#endif

    fptr->mode |= FMODE_BINMODE;
#endif
    return io;
}

int
rb_io_mode_flags(mode)
    const char *mode;
{
    int flags = 0;

    switch (mode[0]) {
      case 'r':
	flags |= FMODE_READABLE;
	break;
      case 'w':
	flags |= FMODE_WRITABLE;
	break;
      case 'a':
	flags |= FMODE_WRITABLE;
	break;
      default:
      error:
	rb_raise(rb_eArgError, "illegal access mode %s", mode);
    }

    if (mode[1] == 'b') {
	flags |= FMODE_BINMODE;
	mode++;
    }

    if (mode[1] == '+') {
	flags |= FMODE_READWRITE;
	if (mode[2] != 0) goto error;
    }
    else if (mode[1] != 0) goto error;

    return flags;
}

static int
rb_io_mode_flags2(mode)
    int mode;
{
    int flags;

    switch (mode & (O_RDONLY|O_WRONLY|O_RDWR)) {
      case O_RDONLY:	
	flags = FMODE_READABLE;
	break;
      case O_WRONLY:
	flags = FMODE_WRITABLE;
	break;
      case O_RDWR:
	flags = FMODE_WRITABLE|FMODE_READABLE;
	break;
    }

#ifdef O_BINARY
    if (mode & O_BINARY) {
	flags |= FMODE_BINMODE;
    }
#endif

    return flags;
}

static char*
rb_io_flags_mode(flags)
    int flags;
{
    static char mode[4];
    char *p = mode;

    switch (flags & (O_RDONLY|O_WRONLY|O_RDWR)) {
      case O_RDONLY:	
	*p++ = 'r';
	break;
      case O_WRONLY:
	*p++ = 'w';
	break;
      case O_RDWR:
	*p++ = 'w';
	*p++ = '+';
	break;
    }
    *p++ = '\0';
#ifdef O_BINARY
    if (flags & O_BINARY) {
	if (mode[1] == '+') {
	    mode[1] = 'b'; mode[2] = '+'; mode[3] = '\0';
	}
	else {
	    mode[1] = 'b'; mode[2] = '\0';
	}
    }
#endif
    return mode;
}

static int
rb_sysopen(fname, flag, mode)
    char *fname;
    int flag;
    unsigned int mode;
{
    int fd;

    fd = open(fname, flag, mode);
    if (fd < 0) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    fd = open(fname, flag, mode);
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
	rb_warn("setvbuf() can't be honered for %s", fname);
#endif
#ifdef __human68k__
    fmode(file, _IOTEXT);
#endif
    return file;
}

FILE *
rb_fdopen(fd, mode)
    int fd;
    const char *mode;
{
    FILE *file;

    file = fdopen(fd, mode);
    if (!file) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    file = fdopen(fd, mode);
	}
	if (!file) {
	    rb_sys_fail(0);
	}
    }
#ifdef USE_SETVBUF
    if (setvbuf(file, NULL, _IOFBF, 0) != 0)
	rb_warn("setvbuf() can't be honered (fd=%d)", fd);
#endif

    return file;
}

static VALUE
rb_file_open_internal(io, fname, mode)
    VALUE io;
    const char *fname, *mode;
{
    OpenFile *fptr;

    MakeOpenFile(io, fptr);

    fptr->mode = rb_io_mode_flags(mode);
    fptr->f = rb_fopen(fname, mode);
    fptr->path = strdup(fname);

    return io;
}

VALUE
rb_file_open(fname, mode)
    const char *fname, *mode;
{
    NEWOBJ(io, struct RFile);
    OBJSETUP(io, rb_cFile, T_FILE);
    return rb_file_open_internal((VALUE)io, fname, mode);
}

static VALUE
rb_file_sysopen_internal(io, fname, flags, mode)
    VALUE io;
    char *fname;
    int flags, mode;
{
    OpenFile *fptr;
    int fd;
    char *m;

    MakeOpenFile(io, fptr);

    fd = rb_sysopen(fname, flags, mode);
    m = rb_io_flags_mode(flags);
    fptr->mode = rb_io_mode_flags2(flags);
    fptr->f = rb_fdopen(fd, m);
    fptr->path = strdup(fname);

    return io;
}

VALUE
rb_file_sysopen(fname, flags, mode)
    const char *fname;
    int flags, mode;
{
    NEWOBJ(io, struct RFile);
    OBJSETUP(io, rb_cFile, T_FILE);
    return rb_file_sysopen_internal((VALUE)io, fname, flags, mode);
}

#if defined (NT) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__)
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

#if defined (NT) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__)
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
#endif

static void
pipe_finalize(fptr)
    OpenFile *fptr;
{
#if !defined (__CYGWIN__)
    extern VALUE rb_last_status;
    int status;
    if (fptr->f) {
	status = pclose(fptr->f);
    }
    if (fptr->f2) {
	status = pclose(fptr->f2);
    }
    fptr->f = fptr->f2 = 0;
#if defined DJGPP
    status <<= 8;
#endif
    rb_last_status = INT2FIX(status);
#else
    fptr_finalize(fptr);
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

static VALUE
pipe_open(pname, mode)
    char *pname, *mode;
{
    int modef = rb_io_mode_flags(mode);
    OpenFile *fptr;

#if defined(NT) || defined(DJGPP) || defined(__human68k__)
    FILE *f = popen(pname, mode);

    if (!f) rb_sys_fail(pname);
    else {
	NEWOBJ(port, struct RFile);
	OBJSETUP(port, rb_cIO, T_FILE);
	MakeOpenFile(port, fptr);
	fptr->finalize = pipe_finalize;
	fptr->mode = modef;

	pipe_add_fptr(fptr);
	if (modef & FMODE_READABLE) fptr->f  = f;
	if (modef & FMODE_WRITABLE) {
	    if (fptr->f) fptr->f2 = f;
	    else fptr->f = f;
	    rb_io_synchronized(fptr);
	}
	return (VALUE)port;
    }
#else
    int pid, pr[2], pw[2];
    volatile int doexec;

    if (((modef & FMODE_READABLE) && pipe(pr) == -1) ||
	((modef & FMODE_WRITABLE) && pipe(pw) == -1))
	rb_sys_fail(pname);

    doexec = (strcmp("-", pname) != 0);
    if (!doexec) {
	fflush(stdin);		/* is it really needed? */
	fflush(stdout);
	fflush(stderr);
    }

  retry:
    switch (pid = (doexec?vfork():fork())) {
      case 0:			/* child */
	if (modef & FMODE_READABLE) {
	    close(pr[0]);
	    if (pr[1] != 1) {
		dup2(pr[1], 1);
		close(pr[1]);
	    }
	}
	if (modef & FMODE_WRITABLE) {
	    close(pw[1]);
	    if (pw[0] != 0) {
		dup2(pw[0], 0);
		close(pw[0]);
	    }
	}

	if (doexec) {
	    int fd;

	    for (fd = 3; fd < NOFILE; fd++)
		close(fd);
	    rb_proc_exec(pname);
	    fprintf(stderr, "%s:%d: command not found: %s\n",
		    ruby_sourcefile, ruby_sourceline, pname);
	    _exit(127);
	}
	rb_io_synchronized(RFILE(orig_stdout)->fptr);
	rb_io_synchronized(RFILE(orig_stderr)->fptr);
	return Qnil;

      case -1:			/* fork failed */
	if (errno == EAGAIN) {
	    rb_thread_sleep(1);
	    goto retry;
	}
	close(pr[0]); close(pw[1]);
	rb_sys_fail(pname);
	break;

      default:			/* parent */
	if (pid < 0) rb_sys_fail(pname);
	else {
	    NEWOBJ(port, struct RFile);
	    OBJSETUP(port, rb_cIO, T_FILE);
	    MakeOpenFile(port, fptr);
	    fptr->mode = modef;
	    fptr->mode |= FMODE_SYNC;
	    fptr->pid = pid;

	    if (modef & FMODE_READABLE) {
		close(pr[1]);
		fptr->f  = rb_fdopen(pr[0], "r");
	    }
	    if (modef & FMODE_WRITABLE) {
		FILE *f = rb_fdopen(pw[1], "w");

		close(pw[0]);
		if (fptr->f) fptr->f2 = f;
		else fptr->f = f;
	    }
#if defined (__CYGWIN__)
	    fptr->finalize = pipe_finalize;
	    pipe_add_fptr(fptr);
#endif
	    return (VALUE)port;
	}
    }
#endif
}

static VALUE
rb_io_popen(str, argc, argv, klass)
    char *str;
    int argc;
    VALUE *argv;
    VALUE klass;
{
    char *mode;
    VALUE pname, pmode, port;

    if (rb_scan_args(argc, argv, "11", &pname, &pmode) == 1) {
	mode = "r";
    }
    else if (FIXNUM_P(pmode)) {
	mode = rb_io_flags_mode(NUM2INT(pmode));
    }
    else {
	mode = STR2CSTR(pmode);
    }
    Check_SafeStr(pname);
    port = pipe_open(str, mode);
    if (NIL_P(port)) {
	/* child */
	if (rb_block_given_p()) {
	    rb_yield(Qnil);
	    fflush(stdout);
	    fflush(stderr);
	    _exit(0);
	}
	return Qnil;
    }
    RBASIC(port)->klass = klass;
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, port, rb_io_close, port);
    }
    return port;
}

static VALUE
rb_io_s_popen(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    char *str = 0;

    if (argc >= 1) {
	str = STR2CSTR(argv[0]);
    }
    return rb_io_popen(str, argc, argv, klass);
}

static VALUE
rb_file_s_open(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE fname, vmode, file, perm;
    char *path, *mode;

    NEWOBJ(io, struct RFile);
    OBJSETUP(io, klass, T_FILE);
    rb_scan_args(argc, argv, "12", &fname, &vmode, &perm);
    Check_SafeStr(fname);
    path = RSTRING(fname)->ptr;

    RFILE(io)->fptr = 0;
    if (FIXNUM_P(vmode)) {
	int flags = NUM2INT(vmode);
	int fmode = NIL_P(perm) ? 0666 : NUM2INT(perm);

	file = rb_file_sysopen_internal((VALUE)io, path, flags, fmode);
    }
    else {
	mode = NIL_P(vmode) ? "r" : STR2CSTR(vmode);
	file = rb_file_open_internal((VALUE)io, RSTRING(fname)->ptr, mode);
    }

    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, file, rb_io_close, file);
    }

    return file;
}

static VALUE
rb_f_open(argc, argv)
    int argc;
    VALUE *argv;
{
    if (argc >= 1) {
	char *str = STR2CSTR(argv[0]);

	if (str[0] == '|') {
	    return rb_io_popen(str+1, argc, argv, rb_cIO);
	}
    }
    return rb_file_s_open(argc, argv, rb_cFile);
}

static VALUE
rb_io_open(fname, mode)
    char *fname, *mode;
{
    if (fname[0] == '|') {
	return pipe_open(fname+1, mode);
    }
    else {
	return rb_file_open(fname, mode);
    }
}

static VALUE
rb_io_get_io(io)
    VALUE io;
{
    return rb_convert_type(io, T_FILE, "IO", "to_io");
}

static char*
rb_io_mode_string(fptr)
    OpenFile *fptr;
{
    switch (fptr->mode & FMODE_READWRITE) {
      case FMODE_READABLE:
      default:
	return "r";
      case FMODE_WRITABLE:
	return "w";
      case FMODE_READWRITE:
	return "r+";
    }
}

static VALUE
io_reopen(io, nfile)
    VALUE io, nfile;
{
    OpenFile *fptr, *orig;
    char *mode;
    int fd;
    long pos;

    nfile = rb_io_get_io(nfile);
    if (rb_safe_level() >= 4 && (!OBJ_TAINTED(io) || !OBJ_TAINTED(nfile))) {
	rb_raise(rb_eSecurityError, "Insecure: can't reopen");
    }
    GetOpenFile(io, fptr);
    GetOpenFile(nfile, orig);

    if (fptr == orig) return io;
    if (orig->mode & FMODE_READABLE) {
	pos = ftell(orig->f);
    }
    if (orig->f2) {
	io_fflush(orig->f2, orig->path);
    }
    else if (orig->mode & FMODE_WRITABLE) {
	io_fflush(orig->f, orig->path);
    }
    rb_thread_fd_close(fileno(fptr->f));

    /* copy OpenFile structure */
    fptr->mode = orig->mode;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (fptr->path) free(fptr->path);
    if (orig->path) fptr->path = strdup(orig->path);
    else fptr->path = 0;
    fptr->finalize = orig->finalize;

    mode = rb_io_mode_string(fptr);
    fd = fileno(fptr->f);
    if (fd < 3) {
	clearerr(fptr->f);
	/* need to keep stdio objects */
	if (dup2(fileno(orig->f), fd) < 0)
	    rb_sys_fail(orig->path);
    }
    else {
	fclose(fptr->f);
	if (dup2(fileno(orig->f), fd) < 0)
	    rb_sys_fail(orig->path);
	fptr->f = rb_fdopen(fd, mode);
    }
    if ((orig->mode & FMODE_READABLE) && pos >= 0) {
	fseek(fptr->f, pos, SEEK_SET);
	fseek(orig->f, pos, SEEK_SET);
    }

    if (fptr->f2) {
	fd = fileno(fptr->f2);
	fclose(fptr->f2);
	if (orig->f2) {
	    if (dup2(fileno(orig->f2), fd) < 0)
		rb_sys_fail(orig->path);
	    fptr->f2 = rb_fdopen(fd, "w");
	}
	else {
	    fptr->f2 = 0;
	}
    }

    if (fptr->mode & FMODE_BINMODE) {
	rb_io_binmode(io);
    }

    RBASIC(io)->klass = RBASIC(nfile)->klass;
    return io;
}

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
	if (TYPE(fname) != T_STRING) { /* fname must be IO */
	    return io_reopen(file, fname);
	}
    }

    Check_SafeStr(fname);
    if (!NIL_P(nmode)) {
	mode = STR2CSTR(nmode);
    }
    else {
	mode = "r";
    }

    GetOpenFile(file, fptr);
    if (fptr->path) {
	free(fptr->path);
	fptr->path = 0;
    }

    fptr->path = strdup(RSTRING(fname)->ptr);
    fptr->mode = rb_io_mode_flags(mode);
    if (!fptr->f) {
	fptr->f = rb_fopen(RSTRING(fname)->ptr, mode);
	if (fptr->f2) {
	    fclose(fptr->f2);
	    fptr->f2 = 0;
	}

	return file;
    }

    if (freopen(RSTRING(fname)->ptr, mode, fptr->f) == 0) {
	rb_sys_fail(fptr->path);
    }
#ifdef USE_SETVBUF
    if (setvbuf(fptr->f, NULL, _IOFBF, 0) != 0)
	rb_warn("setvbuf() can't be honered for %s", RSTRING(fname)->ptr);
#endif

    if (fptr->f2) {
	if (freopen(RSTRING(fname)->ptr, "w", fptr->f2) == 0) {
	    rb_sys_fail(fptr->path);
	}
    }

    return file;
}

static VALUE
rb_io_clone(io)
    VALUE io;
{
    VALUE klass;
    OpenFile *fptr, *orig;
    int fd;
    char *mode;

    NEWOBJ(clone, struct RFile);
    CLONESETUP(clone, io);

    GetOpenFile(io, orig);
    MakeOpenFile(clone, fptr);

    if (orig->f2) {
	io_fflush(orig->f2, orig->path);
    }
    else if (orig->mode & FMODE_WRITABLE) {
	io_fflush(orig->f, orig->path);
    }

    /* copy OpenFile structure */
    fptr->mode = orig->mode;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (orig->path) fptr->path = strdup(orig->path);
    fptr->finalize = orig->finalize;

    switch (fptr->mode & FMODE_READWRITE) {
      case FMODE_READABLE:
      default:
	mode = "r"; break;
      case FMODE_WRITABLE:
	mode = "w"; break;
      case FMODE_READWRITE:
	if (orig->f2) mode = "r";
	else          mode = "r+";
	break;
    }
    fd = rb_dup(fileno(orig->f));
    fptr->f = rb_fdopen(fd, mode);
    if (fptr->f2) {
	fd = rb_dup(fileno(orig->f2));
	fptr->f = rb_fdopen(fd, "w");
    }
    if (fptr->mode & FMODE_BINMODE) {
	rb_io_binmode((VALUE)clone);
    }

    return (VALUE)clone;
}

static VALUE
rb_io_printf(argc, argv, out)
    int argc;
    VALUE argv[];
    VALUE out;
{
    rb_io_write(out, rb_f_sprintf(argc, argv));
    return Qnil;
}

static VALUE
rb_f_printf(argc, argv)
    int argc;
    VALUE argv[];
{
    VALUE out;

    if (argc == 0) return Qnil;
    if (TYPE(argv[0]) == T_STRING) {
	out = rb_defout;
    }
    else {
	out = argv[0];
	argv++;
	argc--;
    }
    rb_io_write(out, rb_f_sprintf(argc, argv));

    return Qnil;
}

static VALUE
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

static VALUE
rb_f_print(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_io_print(argc, argv, rb_defout);
    return Qnil;
}

static VALUE
rb_io_putc(io, ch)
    VALUE io, ch;
{
    OpenFile *fptr;
    FILE *f;
    int c = NUM2CHR(ch);

    rb_secure(4);
    GetOpenFile(io, fptr);
    rb_io_check_writable(fptr);
    f = GetWriteFile(fptr);

    if (fputc(c, f) == EOF)
	rb_sys_fail(fptr->path);
    if (fptr->mode & FMODE_SYNC) {
	io_fflush(f, fptr->path);
    }

    return ch;
}

static VALUE
rb_f_putc(recv, ch)
    VALUE recv, ch;
{
    return rb_io_putc(rb_defout, ch);
}

static VALUE rb_io_puts _((int, VALUE*, VALUE));

static VALUE
io_puts_ary(ary, out)
    VALUE ary, out;
{
    VALUE tmp;
    int i;

    for (i=0; i<RARRAY(ary)->len; i++) {
	tmp = RARRAY(ary)->ptr[i];
	if (rb_inspecting_p(tmp)) {
	    tmp = rb_str_new2("[...]");
	}
	rb_io_puts(1, &tmp, out);
    }
    return Qnil;
}

static VALUE
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
	    line = rb_check_convert_type(argv[i], T_ARRAY, "Array", "to_ary");
	    if (!NIL_P(line)) {
		rb_protect_inspect(io_puts_ary, line, out);
		continue;
	    }
	    line = rb_obj_as_string(argv[i]);
	}
	rb_io_write(out, line);
	if (RSTRING(line)->ptr[RSTRING(line)->len-1] != '\n') {
	    rb_io_write(out, rb_default_rs);
	}
    }

    return Qnil;
}

static VALUE
rb_f_puts(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_io_puts(argc, argv, rb_defout);
    return Qnil;
}

void
rb_p(obj)			/* for debug print within C code */
    VALUE obj;
{
    rb_io_write(rb_defout, rb_obj_as_string(rb_inspect(obj)));
    rb_io_write(rb_defout, rb_default_rs);
}

static VALUE
rb_f_p(argc, argv)
    int argc;
    VALUE *argv;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_p(argv[i]);
    }
    if (TYPE(rb_defout) == T_FILE) {
    rb_io_flush(rb_defout);
    }
    return Qnil;
}

static VALUE
rb_obj_display(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE out;

    if (rb_scan_args(argc, argv, "01", &out) == 0) {
	out = rb_defout;
    }

    rb_io_write(out, self);

    return Qnil;
}

static void
rb_io_defset(val, id)
    VALUE val;
    ID id;
{
    if (!rb_respond_to(val, id_write)) {
	rb_raise(rb_eTypeError, "$> must have write method, %s given",
		 rb_class2name(CLASS_OF(val)));
    }
    rb_defout = val;
}

static void
set_stdin(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    OpenFile *fptr;

    if (val == *var) return;
    if (TYPE(val) != T_FILE) {
	*var = val;
	return;
    }
    if (TYPE(*var) != T_FILE) {
	*var = orig_stdin;
    }

    GetOpenFile(val, fptr);
    rb_io_check_readable(fptr);
    dup2(fileno(fptr->f), 0);

    *var = val;
}

static void
set_outfile(val, var, orig, stdf)
    VALUE val;
    VALUE *var;
    VALUE orig;
    FILE *stdf;
{
    OpenFile *fptr;
    FILE *f;

    if (val == *var) return;

    if (TYPE(*var) == T_FILE) {
	rb_io_flush(*var);
    }
    if (TYPE(val) != T_FILE) {
	*var = val;
	return;
    }
    if (TYPE(*var) != T_FILE) {
	*var = orig;
    }

    GetOpenFile(val, fptr);
    rb_io_check_writable(fptr);
    f = GetWriteFile(fptr);
    dup2(fileno(f), fileno(stdf));

    *var = val;
}

static void
set_stdout(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    set_outfile(val, var, orig_stdout, stdout);
}

static void
set_stderr(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    set_outfile(val, var, orig_stderr, stderr);
}

static VALUE
prep_stdio(f, mode, klass)
    FILE *f;
    int mode;
    VALUE klass;
{
    OpenFile *fp;
    NEWOBJ(io, struct RFile);
    OBJSETUP(io, klass, T_FILE);

    MakeOpenFile(io, fp);
    fp->f = f;
    fp->mode = mode;

    return (VALUE)io;
}

static void
prep_path(io, path)
    VALUE io;
    char *path;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (fptr->path) rb_bug("illegal prep_path() call");
    fptr->path = strdup(path);
}

static VALUE
rb_io_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    NEWOBJ(io, struct RFile);
    OBJSETUP(io, klass, T_FILE);
    
    io->fptr = 0;
    rb_obj_call_init((VALUE)io, argc, argv);

    return (VALUE)io;
}

static VALUE
rb_io_initialize(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fnum, mode;
    OpenFile *fp;
    char *m = "r";

    if (RFILE(io)->fptr) {
	rb_io_close_m(io);
	free(RFILE(io)->fptr);
	RFILE(io)->fptr = 0;
    }
    if (rb_scan_args(argc, argv, "11", &fnum, &mode) == 2) {
	Check_SafeStr(mode);
	m = RSTRING(mode)->ptr;
    }
    MakeOpenFile(io, fp);
    fp->f = rb_fdopen(NUM2INT(fnum), m);
    fp->mode = rb_io_mode_flags(m);

    return io;
}

static VALUE
rb_file_initialize(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname, vmode, file, perm;
    char *path, *mode;

    rb_scan_args(argc, argv, "12", &fname, &vmode, &perm);
    Check_SafeStr(fname);
    path = RSTRING(fname)->ptr;

    if (RFILE(io)->fptr) {
	rb_io_close_m(io);
	free(RFILE(io)->fptr);
	RFILE(io)->fptr = 0;
    }
    if (FIXNUM_P(vmode)) {
	int flags = NUM2INT(vmode);
	int fmode = NIL_P(perm) ? 0666 : NUM2INT(perm);

	file = rb_file_sysopen_internal(io, path, flags, fmode);
    }
    else {
	if (NIL_P(vmode)) {
	    mode = "r";
	}
	else {
	    mode = STR2CSTR(vmode);
	}
	file = rb_file_open_internal(io, RSTRING(fname)->ptr, mode);
    }
    if (rb_block_given_p()) {
	rb_warn("File::new() does not take block; use File::open() instead");
    }

    return file;
}

static int binmode = 0;

static VALUE
argf_forward()
{
    return rb_funcall3(current_file, ruby_frame->last_func,
		       ruby_frame->argc, ruby_frame->argv);
}

static VALUE
argf_binmode()
{
    if (TYPE(current_file) != T_FILE) {
	argf_forward();
    }
    else {
	rb_io_binmode(current_file);
    }
    binmode = 1;
    return argf;
}

static int
next_argv()
{
    extern VALUE rb_argv;
    char *fn;

    if (init_p == 0) {
	if (RARRAY(rb_argv)->len > 0) {
	    next_p = 1;
	}
	else {
	    next_p = -1;
	    current_file = rb_stdin;
	    filename = rb_str_new2("-");
	}
	init_p = 1;
	first_p = 0;
	gets_lineno = 0;
    }

  retry:
    if (next_p == 1) {
	next_p = 0;
	if (RARRAY(rb_argv)->len > 0) {
	    filename = rb_ary_shift(rb_argv);
	    fn = STR2CSTR(filename);
	    if (strlen(fn) == 1 && fn[0] == '-') {
		current_file = rb_stdin;
		if (ruby_inplace_mode) {
		    rb_warn("Can't do inplace edit for stdio");
		    rb_defout = rb_stdout;
		}
	    }
	    else {
		FILE *fr = rb_fopen(fn, "r");

		if (ruby_inplace_mode) {
		    struct stat st, st2;
		    VALUE str;
		    FILE *fw;

		    if (TYPE(rb_defout) == T_FILE && rb_defout != rb_stdout) {
			rb_io_close(rb_defout);
		    }
		    fstat(fileno(fr), &st);
		    if (*ruby_inplace_mode) {
			str = rb_str_new2(fn);
#ifdef NO_LONG_FNAME
                        ruby_add_suffix(str, ruby_inplace_mode);
#else
			rb_str_cat2(str, ruby_inplace_mode);
#endif
#ifdef NO_SAFE_RENAME
			(void)fclose(fr);
			(void)unlink(RSTRING(str)->ptr);
			(void)rename(fn, RSTRING(str)->ptr);
			fr = rb_fopen(RSTRING(str)->ptr, "r");
#else
			if (rename(fn, RSTRING(str)->ptr) < 0) {
			    rb_warn("Can't rename %s to %s: %s, skipping file",
				    fn, RSTRING(str)->ptr, strerror(errno));
			    fclose(fr);
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
			    fclose(fr);
			    goto retry;
			}
#endif
		    }
		    fw = rb_fopen(fn, "w");
#ifndef NO_SAFE_RENAME
		    fstat(fileno(fw), &st2);
#ifdef HAVE_FCHMOD
		    fchmod(fileno(fw), st.st_mode);
#else
		    chmod(fn, st.st_mode);
#endif
		    if (st.st_uid!=st2.st_uid || st.st_gid!=st2.st_gid) {
			fchown(fileno(fw), st.st_uid, st.st_gid);
		    }
#endif
		    rb_defout = prep_stdio(fw, FMODE_WRITABLE, rb_cFile);
		    prep_path(rb_defout, fn);
		}
		current_file = prep_stdio(fr, FMODE_READABLE, rb_cFile);
		prep_path(current_file, fn);
	    }
	    if (binmode) rb_io_binmode(current_file);
	}
	else {
	    init_p = 0;
	    return Qfalse;
	}
    }
    return Qtrue;
}

static void
any_close(file)
    VALUE file;
{
    if (TYPE(file) == T_FILE)
	rb_io_close(file);
    else
	rb_funcall3(file, rb_intern("close"), 0, 0);
}

static VALUE
rb_f_gets_internal(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line;

  retry:
    if (!next_argv()) return Qnil;
    if (TYPE(current_file) != T_FILE) {
	line = rb_funcall3(current_file, rb_intern("gets"), argc, argv);
    }
    else if (argc == 0 && rb_rs == rb_default_rs) {
	line = rb_io_gets(current_file);
    }
    else {
	line = rb_io_gets_internal(argc, argv, current_file);
    }
    if (NIL_P(line) && next_p != -1) {
	any_close(current_file);
	next_p = 1;
	goto retry;
    }
    gets_lineno++;
    lineno = INT2FIX(gets_lineno);

    return line;
}

static VALUE
rb_f_gets(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line = rb_f_gets_internal(argc, argv);

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
	any_close(current_file);
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

static VALUE
rb_f_readline(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line = rb_f_gets(argc, argv);

    if (NIL_P(line)) {
	rb_eof_error();
    }

    return line;
}

static VALUE
rb_f_getc()
{
    rb_warn("getc is obsolete; use STDIN.getc instead");
    return rb_io_getc(rb_stdin);
}

static VALUE
rb_f_readlines(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line, ary;

    ary = rb_ary_new();
    while (!NIL_P(line = rb_f_gets_internal(argc, argv))) {
	rb_ary_push(ary, line);
    }

    return ary;
}

static VALUE
rb_f_backquote(obj, str)
    VALUE obj, str;
{
    VALUE port, result;

    Check_SafeStr(str);
    port = pipe_open(RSTRING(str)->ptr, "r");
    if (NIL_P(port)) return rb_str_new(0,0);
    result = read_all(port);

    rb_io_close(port);

    if (NIL_P(result)) return rb_str_new(0,0);
    return result;
}

#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif

static VALUE
rb_f_select(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE read, write, except, timeout, res, list;
    fd_set rset, wset, eset, pset;
    fd_set *rp, *wp, *ep;
    struct timeval *tp, timerec;
    OpenFile *fptr;
    int i, max = 0, n;
    int interrupt_flag = 0;
    int pending = 0;

    rb_scan_args(argc, argv, "13", &read, &write, &except, &timeout);
    if (NIL_P(timeout)) {
	tp = 0;
    }
    else {
	timerec = rb_time_interval(timeout);
	tp = &timerec;
    }

    FD_ZERO(&pset);
    if (!NIL_P(read)) {
	Check_Type(read, T_ARRAY);
	rp = &rset;
	FD_ZERO(rp);
	for (i=0; i<RARRAY(read)->len; i++) {
	    GetOpenFile(rb_io_get_io(RARRAY(read)->ptr[i]), fptr);
	    FD_SET(fileno(fptr->f), rp);
	    if (READ_DATA_PENDING(fptr->f)) { /* check for buffered data */
		pending++;
		FD_SET(fileno(fptr->f), &pset);
	    }
	    if (max < fileno(fptr->f)) max = fileno(fptr->f);
	}
	if (pending) {		/* no blocking if there's buffered data */
	    timerec.tv_sec = timerec.tv_usec = 0;
	    tp = &timerec;
	}
    }
    else
	rp = 0;

    if (!NIL_P(write)) {
	Check_Type(write, T_ARRAY);
	wp = &wset;
	FD_ZERO(wp);
	for (i=0; i<RARRAY(write)->len; i++) {
	    GetOpenFile(rb_io_get_io(RARRAY(write)->ptr[i]), fptr);
	    FD_SET(fileno(fptr->f), wp);
	    if (max < fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), wp);
		if (max < fileno(fptr->f2)) max = fileno(fptr->f2);
	    }
	}
    }
    else
	wp = 0;

    if (!NIL_P(except)) {
	Check_Type(except, T_ARRAY);
	ep = &eset;
	FD_ZERO(ep);
	for (i=0; i<RARRAY(except)->len; i++) {
	    GetOpenFile(rb_io_get_io(RARRAY(except)->ptr[i]), fptr);
	    FD_SET(fileno(fptr->f), ep);
	    if (max < fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), ep);
		if (max < fileno(fptr->f2)) max = fileno(fptr->f2);
	    }
	}
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
		if (FD_ISSET(fileno(fptr->f), rp)
		    || FD_ISSET(fileno(fptr->f), &pset)) {
		    rb_ary_push(list, RARRAY(read)->ptr[i]);
		}
	    }
	}

	if (wp) {
	    list = RARRAY(res)->ptr[1];
	    for (i=0; i< RARRAY(write)->len; i++) {
		GetOpenFile(rb_io_get_io(RARRAY(write)->ptr[i]), fptr);
		if (FD_ISSET(fileno(fptr->f), wp)) {
		    rb_ary_push(list, RARRAY(write)->ptr[i]);
		}
		else if (fptr->f2 && FD_ISSET(fileno(fptr->f2), wp)) {
		    rb_ary_push(list, RARRAY(write)->ptr[i]);
		}
	    }
	}

	if (ep) {
	    list = RARRAY(res)->ptr[2];
	    for (i=0; i< RARRAY(except)->len; i++) {
		GetOpenFile(rb_io_get_io(RARRAY(except)->ptr[i]), fptr);
		if (FD_ISSET(fileno(fptr->f), ep)) {
		    rb_ary_push(list, RARRAY(except)->ptr[i]);
		}
		else if (fptr->f2 && FD_ISSET(fileno(fptr->f2), ep)) {
		    rb_ary_push(list, RARRAY(except)->ptr[i]);
		}
	    }
	}
    }

    return res;			/* returns an empty array on interrupt */
}

#if !defined(MSDOS) && !defined(__human68k__)
static int
io_cntl(fd,cmd,narg,io_p)
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
    int len = 0;
    long narg = 0;
    int retval;

    rb_secure(2);
    GetOpenFile(io, fptr);

    if (NIL_P(arg) || arg == Qfalse) {
	narg = 0;
    }
    else if (FIXNUM_P(arg)) {
	narg = FIX2INT(arg);
    }
    else if (arg == Qtrue) {
	narg = 1;
    }
    else if (rb_obj_is_kind_of(arg, rb_cInteger)) {
	narg = NUM2LONG(arg);
    }
    else {
	Check_Type(arg, T_STRING);

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
    retval = io_cntl(fileno(fptr->f), cmd, narg, io_p);
    if (retval < 0) rb_sys_fail(fptr->path);
    if (TYPE(arg) == T_STRING && RSTRING(arg)->ptr[len] != 17) {
	rb_raise(rb_eArgError, "return value overflowed string");
    }

    if (fptr->f2) {		/* call on f2 too; ignore result */
	io_cntl(fileno(fptr->f2), cmd, narg, io_p);
    }

    return INT2NUM(retval);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

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
    arg[0] = NUM2INT(argv[0]); argv++;
    while (items--) {
	if (FIXNUM_P(*argv)) {
	    arg[i] = (unsigned long)NUM2INT(*argv); argv++;
	}
	else {
	    Check_Type(*argv, T_STRING);
	    rb_str_modify(*argv);
	    arg[i] = (unsigned long)RSTRING(*argv)->ptr; argv++;
	}
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
rb_io_s_pipe()
{
#ifndef __human68k__
    int pipes[2];
    VALUE r, w, ary;

#ifdef NT
    if (_pipe(pipes, 1024, O_BINARY) == -1)
#else
    if (pipe(pipes) == -1)
#endif
	rb_sys_fail(0);

    r = prep_stdio(rb_fdopen(pipes[0], "r"), FMODE_READABLE, rb_cIO);
    w = prep_stdio(rb_fdopen(pipes[1], "w"), FMODE_WRITABLE|FMODE_SYNC, rb_cIO);

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
rb_io_foreach_line(arg)
    struct foreach_arg *arg;
{
    VALUE str;

    while (!NIL_P(str = rb_io_gets_internal(arg->argc, &arg->sep, arg->io))) {
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
rb_io_s_foreach(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "11", &fname, &arg.sep);
    Check_SafeStr(fname);

    arg.argc = argc - 1;
    arg.io = rb_io_open(RSTRING(fname)->ptr, "r");
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(rb_io_foreach_line, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
rb_io_readline_line(arg)
    struct foreach_arg *arg;
{
    VALUE line, ary;

    ary = rb_ary_new();
    while (!NIL_P(line = rb_io_gets_internal(arg->argc, &arg->sep, arg->io))) {
	rb_ary_push(ary, line);
    }

    return ary;
}

static VALUE
rb_io_s_readlines(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "11", &fname, &arg.sep);
    Check_SafeStr(fname);

    arg.argc = argc - 1;
    arg.io = rb_io_open(RSTRING(fname)->ptr, "r");
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(rb_io_readline_line, (VALUE)&arg, rb_io_close, arg.io);
}

static VALUE
argf_tell()
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to tell");
    }

    if (TYPE(current_file) != T_FILE) {
	return argf_forward();
    }
    return rb_io_tell(current_file);
}

static VALUE
argf_seek(argc, argv)
    int argc;
    VALUE *argv;
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to seek");
    }

    if (TYPE(current_file) != T_FILE) {
	return argf_forward();
    }
    return rb_io_seek(argc, argv, current_file);
}

static VALUE
argf_set_pos(self, offset)
     VALUE self, offset;
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to pos");
    }

    if (TYPE(current_file) != T_FILE) {
	return argf_forward();
    }
    return rb_io_set_pos(current_file, offset);
}

static VALUE
argf_rewind()
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream to rewind");
    }
    if (TYPE(current_file) != T_FILE) {
	return argf_forward();
    }
    return rb_io_rewind(current_file);
}

static VALUE
argf_fileno()
{
    if (!next_argv()) {
	rb_raise(rb_eArgError, "no stream");
    }
    if (TYPE(current_file) != T_FILE) {
	return argf_forward();
    }
    return rb_io_fileno(current_file);
}

static VALUE
argf_to_io()
{
    return current_file;
}

static VALUE
argf_read(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE tmp, str;
    int len;

    if (argc == 1) len = NUM2INT(argv[0]);
    str = Qnil;

  retry:
    if (!next_argv()) return str;
    if (TYPE(current_file) != T_FILE) {
	tmp = argf_forward();
	STR2CSTR(tmp);
    }
    else {
	tmp = io_read(argc, argv, current_file);
    }
    if (NIL_P(tmp) && next_p != -1) {
	any_close(current_file);
	next_p = 1;
	goto retry;
    }
    if (NIL_P(tmp) || RSTRING(tmp)->len == 0) return str;
    else if (NIL_P(str)) str = tmp;
    else rb_str_append(str, tmp);
    if (argc == 0) {
	goto retry;
    }
    if (RSTRING(tmp)->len < len) {
	len -= RSTRING(tmp)->len;
	argv[0] = INT2FIX(len);
	goto retry;
    }

    return str;
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
	any_close(current_file);
	next_p = 1;
	goto retry;
    }

    return byte;
}

static VALUE
argf_readchar()
{
    VALUE c = argf_getc();

    if (NIL_P(c)) {
	rb_eof_error();
    }
    return c;
}

static VALUE
argf_eof()
{
    int first = first_p;

    if (!next_argv()) return Qtrue;
    if (!first && next_p == -1) {
	return Qtrue;
    }
    if (TYPE(current_file) != T_FILE) {
	return argf_forward();
    }
    if (rb_io_eof(current_file)) {
	next_p = 1;
	return Qtrue;
    }
    return Qfalse;
}

static VALUE
argf_each_line(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str;

    while (RTEST(str = rb_f_gets_internal(argc, argv))) {
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
    return Qnil;
}

static VALUE
argf_filename()
{
    return filename;
}

static VALUE
argf_file()
{
    return current_file;
}

static VALUE
argf_skip()
{
    if (next_p != -1) {
	any_close(current_file);
	next_p = 1;
    }
    return argf;
}

static VALUE
argf_close()
{
    any_close(current_file);
    if (next_p != -1) {
	next_p = 1;
    }
    gets_lineno = 0;
    return argf;
}

static VALUE
argf_closed()
{
    if (TYPE(current_file) != T_FILE) {
	return argf_forward();
    }
    return rb_io_closed(current_file);
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
    long len;

    if (!RTEST(val)) {
	if (ruby_inplace_mode) free(ruby_inplace_mode);
	ruby_inplace_mode = 0;
	return;
    }
    STR2CSTR(val);
    len = RSTRING(val)->len;
    REALLOC_N(ruby_inplace_mode, char, len + 1);
    ((char *)MEMCPY(ruby_inplace_mode, RSTRING(val)->ptr, char, len))[len] = '\0';
}

void
Init_IO()
{
    rb_eIOError = rb_define_class("IOError", rb_eStandardError);
    rb_eEOFError = rb_define_class("EOFError", rb_eIOError);

    id_write = rb_intern("write");

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

    rb_define_singleton_method(rb_cIO, "new", rb_io_s_new, -1);
    rb_define_method(rb_cIO, "initialize", rb_io_initialize, -1);
    rb_define_singleton_method(rb_cIO, "popen", rb_io_s_popen, -1);
    rb_define_singleton_method(rb_cIO, "foreach", rb_io_s_foreach, -1);
    rb_define_singleton_method(rb_cIO, "readlines", rb_io_s_readlines, -1);
    rb_define_singleton_method(rb_cIO, "select", rb_f_select, -1);
    rb_define_singleton_method(rb_cIO, "pipe", rb_io_s_pipe, 0);

    rb_output_fs = Qnil;
    rb_define_hooked_variable("$,", &rb_output_fs, 0, rb_str_setter);

    rb_rs = rb_default_rs = rb_str_new2("\n"); rb_output_rs = Qnil;
    rb_global_variable(&rb_default_rs);
    OBJ_FREEZE(rb_default_rs);	/* avoid modifying RS_default */
    rb_define_hooked_variable("$/", &rb_rs, 0, rb_str_setter);
    rb_define_hooked_variable("$-0", &rb_rs, 0, rb_str_setter);
    rb_define_hooked_variable("$\\", &rb_output_rs, 0, rb_str_setter);

    rb_define_hooked_variable("$.", &lineno, 0, lineno_setter);
    rb_define_virtual_variable("$_", rb_lastline_get, rb_lastline_set);

    rb_define_method(rb_cIO, "clone", rb_io_clone, 0);
    rb_define_method(rb_cIO, "reopen", rb_io_reopen, -1);

    rb_define_method(rb_cIO, "print", rb_io_print, -1);
    rb_define_method(rb_cIO, "putc", rb_io_putc, 1);
    rb_define_method(rb_cIO, "puts", rb_io_puts, -1);
    rb_define_method(rb_cIO, "printf", rb_io_printf, -1);

    rb_define_method(rb_cIO, "each",  rb_io_each_line, -1);
    rb_define_method(rb_cIO, "each_line",  rb_io_each_line, -1);
    rb_define_method(rb_cIO, "each_byte",  rb_io_each_byte, 0);

    rb_define_method(rb_cIO, "syswrite", rb_io_syswrite, 1);
    rb_define_method(rb_cIO, "sysread",  rb_io_sysread, 1);

    rb_define_method(rb_cIO, "fileno", rb_io_fileno, 0);
    rb_define_alias(rb_cIO, "to_i", "fileno");
    rb_define_method(rb_cIO, "to_io", rb_io_to_io, 0);

    rb_define_method(rb_cIO, "sync",   rb_io_sync, 0);
    rb_define_method(rb_cIO, "sync=",  rb_io_set_sync, 1);

    rb_define_method(rb_cIO, "lineno",   rb_io_lineno, 0);
    rb_define_method(rb_cIO, "lineno=",  rb_io_set_lineno, 1);

    rb_define_method(rb_cIO, "readlines",  rb_io_readlines, -1);

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
    rb_define_method(rb_cIO, "seek", rb_io_seek, -1);
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

    rb_define_method(rb_cIO, "ioctl", rb_io_ioctl, -1);
    rb_define_method(rb_cIO, "fcntl", rb_io_fcntl, -1);
    rb_define_method(rb_cIO, "pid", rb_io_pid, 0);

    rb_stdin = orig_stdin = prep_stdio(stdin, FMODE_READABLE, rb_cIO);
    rb_define_hooked_variable("$stdin", &rb_stdin, 0, set_stdin);
    rb_stdout = orig_stdout = prep_stdio(stdout, FMODE_WRITABLE, rb_cIO);
    rb_define_hooked_variable("$stdout", &rb_stdout, 0, set_stdout);
    rb_stderr = orig_stderr = prep_stdio(stderr, FMODE_WRITABLE, rb_cIO);
    rb_define_hooked_variable("$stderr", &rb_stderr, 0, set_stderr);
    rb_defout = rb_stdout;
    rb_define_hooked_variable("$>", &rb_defout, 0, rb_io_defset);
    rb_define_hooked_variable("$defout", &rb_defout, 0, rb_io_defset);

    rb_define_global_const("STDIN", rb_stdin);
    rb_define_global_const("STDOUT", rb_stdout);
    rb_define_global_const("STDERR", rb_stderr);

    argf = rb_obj_alloc(rb_cObject);
    rb_extend_object(argf, rb_mEnumerable);

    rb_define_readonly_variable("$<", &argf);
    rb_define_global_const("ARGF", argf);

    rb_define_singleton_method(argf, "fileno", argf_fileno, 0);
    rb_define_singleton_method(argf, "to_i", argf_fileno, 0);
    rb_define_singleton_method(argf, "to_io", argf_to_io, 0);
    rb_define_singleton_method(argf, "each",  argf_each_line, -1);
    rb_define_singleton_method(argf, "each_line",  argf_each_line, -1);
    rb_define_singleton_method(argf, "each_byte",  argf_each_byte, 0);

    rb_define_singleton_method(argf, "read",  argf_read, -1);
    rb_define_singleton_method(argf, "readlines", rb_f_readlines, -1);
    rb_define_singleton_method(argf, "to_a", rb_f_readlines, -1);
    rb_define_singleton_method(argf, "gets", rb_f_gets, -1);
    rb_define_singleton_method(argf, "readline", rb_f_readline, -1);
    rb_define_singleton_method(argf, "getc", argf_getc, 0);
    rb_define_singleton_method(argf, "readchar", argf_readchar, 0);
    rb_define_singleton_method(argf, "tell", argf_tell, 0);
    rb_define_singleton_method(argf, "seek", argf_seek, -1);
    rb_define_singleton_method(argf, "rewind", argf_rewind, 0);
    rb_define_singleton_method(argf, "pos", argf_tell, 0);
    rb_define_singleton_method(argf, "pos=", argf_set_pos, 1);
    rb_define_singleton_method(argf, "eof", argf_eof, 0);
    rb_define_singleton_method(argf, "eof?", argf_eof, 0);
    rb_define_singleton_method(argf, "binmode", argf_binmode, 0);

    rb_define_singleton_method(argf, "to_s", argf_filename, 0);
    rb_define_singleton_method(argf, "filename", argf_filename, 0);
    rb_define_singleton_method(argf, "file", argf_file, 0);
    rb_define_singleton_method(argf, "skip", argf_skip, 0);
    rb_define_singleton_method(argf, "close", argf_close, 0);
    rb_define_singleton_method(argf, "closed?", argf_closed, 0);

    rb_define_singleton_method(argf, "lineno",   argf_lineno, 0);
    rb_define_singleton_method(argf, "lineno=",  argf_set_lineno, 1);

    current_file = rb_stdin;
    rb_global_variable(&current_file);
    filename = rb_str_new2("-");
    rb_define_readonly_variable("$FILENAME", &filename);

    rb_define_virtual_variable("$-i", opt_i_get, opt_i_set);

#if defined (NT) || defined(DJGPP) || defined(__CYGWIN__) || defined(__human68k__)
    atexit(pipe_atexit);
#endif

    Init_File();

    rb_define_singleton_method(rb_cFile, "open",  rb_file_s_open, -1);
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
