/************************************************

  io.c -

  $Author$
  $Date$
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"
#include <ctype.h>
#include <errno.h>

#include <sys/types.h>
#if !defined(DJGPP) && !defined(NT) && !defined(__human68k__)
#include <sys/ioctl.h>
#endif
#if defined(HAVE_FCNTL)
#include <fcntl.h>
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

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#else
# define NOFILE 64
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef USE_CWGUSI
 #include <sys/errno.h>
 #include <unix.mac.h>
 #include <compat.h>
 extern void Init_File();
#endif

#ifdef __BEOS__
# ifdef _X86_
#  define NOFILE (OPEN_MAX)
# endif
#include <net/socket.h>
#endif

VALUE cIO;
VALUE eEOFError;
VALUE eIOError;

VALUE rb_stdin, rb_stdout, rb_stderr, rb_defout;

VALUE FS, OFS;
VALUE RS, ORS;
VALUE RS_default;

static VALUE argf;

ID id_write;

extern char *inplace;

struct timeval time_timeval _((VALUE));

static VALUE filename, file;
static int gets_lineno;
static int init_p = 0, next_p = 0;
static VALUE lineno;

#ifdef _STDIO_USES_IOSTREAM  /* GNU libc */
#  ifdef _IO_fpos_t
#    define READ_DATA_PENDING(fp) ((fp)->_IO_read_ptr != (fp)->_IO_read_end)
#  else
#    define READ_DATA_PENDING(fp) ((fp)->_gptr < (fp)->_egptr)
#  endif
#else
#  ifdef FILE_COUNT
#    define READ_DATA_PENDING(fp) ((fp)->FILE_COUNT > 0)
#  else
#    if defined(__BEOS__)
#      define ReadDataPending(fp) (fp->_state._eof == 0)
#    elif defined(USE_CWGUSI)
#      define ReadDataPending(fp) (fp->state.eof == 0)
#    else
/* requires systems own version of the ReadDataPending() */
extern int ReadDataPending();
#    endif
#    define READ_DATA_PENDING(fp) ReadDataPending(fp)
#  endif
#endif

#ifndef THREAD
# define READ_CHECK(fp) 0
#else
# define READ_CHECK(fp) do {\
    if (!READ_DATA_PENDING(fp)) thread_wait_fd(fileno(fp));\
} while(0)
#endif

void
eof_error()
{
    Raise(eEOFError, "End of file reached");
}

void
io_check_closed(fptr)
    OpenFile *fptr;
{
    if (fptr->f == NULL && fptr->f2 == NULL)
	Raise(eIOError, "closed stream");
}

void
io_readable(fptr)
    OpenFile *fptr;
{
    if (!(fptr->mode & FMODE_READABLE)) {
	Raise(eIOError, "not opened for reading");
    }
}

void
io_writable(fptr)
    OpenFile *fptr;
{
    if (!(fptr->mode & FMODE_WRITABLE)) {
	Raise(eIOError, "not opened for writing");
    }
}

/* writing functions */
VALUE
io_write(io, str)
    VALUE io, str;
{
    OpenFile *fptr;
    FILE *f;
    int n;

    if (TYPE(str) != T_STRING)
	str = obj_as_string(str);
    if (RSTRING(str)->len == 0) return INT2FIX(0);

    if (BUILTIN_TYPE(io) != T_FILE) {
	/* port is not IO, call write method for it. */
	return rb_funcall(io, id_write, 1, str);
    }

    rb_secure(4);
    GetOpenFile(io, fptr);
    io_writable(fptr);

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
    if (n == 0 || ferror(f)) {
	rb_sys_fail(fptr->path);
    }
#endif
    if (fptr->mode & FMODE_SYNC) {
	fflush(f);
    }

    return INT2FIX(n);
}

static VALUE
io_addstr(io, str)
    VALUE io, str;
{
    io_write(io, str);
    return io;
}

static VALUE
io_flush(io)
    VALUE io;
{
    OpenFile *fptr;
    FILE *f;

    GetOpenFile(io, fptr);
    io_writable(fptr);
    f = GetWriteFile(fptr);

    if (fflush(f) == EOF) rb_sys_fail(0);

    return io;
}

static VALUE
io_tell(io)
     VALUE io;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(io, fptr);
    pos = ftell(fptr->f);
    if (ferror(fptr->f) != 0) rb_sys_fail(fptr->path);

    return int2inum(pos);
}

static VALUE
io_seek(io, offset, ptrname)
     VALUE io, offset, ptrname;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(io, fptr);
    pos = fseek(fptr->f, NUM2INT(offset), NUM2INT(ptrname));
    if (pos != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2FIX(0);
}

static VALUE
io_set_pos(io, offset)
     VALUE io, offset;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(io, fptr);
    pos = fseek(fptr->f, NUM2INT(offset), 0);
    if (pos != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2NUM(pos);
}

static VALUE
io_rewind(io)
     VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (fseek(fptr->f, 0L, 0) != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2FIX(0);
}

static VALUE
io_eof(io)
    VALUE io;
{
    OpenFile *fptr;
    int ch;

    GetOpenFile(io, fptr);
    io_readable(fptr);

    if (READ_DATA_PENDING(fptr->f)) return FALSE;
#if 0
    if (feof(fptr->f)) return TRUE;
    return FALSE;
#else
    READ_CHECK(fptr->f);
    TRAP_BEG;
    ch = getc(fptr->f);
    TRAP_END;

    if (ch != EOF) {
	(void)ungetc(ch, fptr->f);
	return FALSE;
    }
    return TRUE;
#endif
}

static VALUE
io_sync(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    return (fptr->mode & FMODE_SYNC) ? TRUE : FALSE;
}

static VALUE
io_set_sync(io, mode)
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
io_fileno(io)
    VALUE io;
{
    OpenFile *fptr;
    int fd;

    GetOpenFile(io, fptr);
    fd = fileno(fptr->f);
    return INT2FIX(fd);
}

static VALUE
io_to_io(io)
    VALUE io;
{
    return io;
}

/* reading functions */

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
    int siz = BUFSIZ;
    int bytes = 0;
    int n;

    GetOpenFile(port, fptr);
    io_readable(fptr);

    if (fstat(fileno(fptr->f), &st) == 0  && S_ISREG(st.st_mode)
#ifdef __BEOS__
	&& (st.st_dev > 3)
#endif
	)
    {
	if (st.st_size == 0) return str_new(0, 0);
	else {
	    int pos = ftell(fptr->f);
	    if (st.st_size > pos && pos >= 0) {
		siz = st.st_size - pos + 1;
	    }
	}
    }
    str = str_new(0, siz);
    for (;;) {
	READ_CHECK(fptr->f);
	TRAP_BEG;
	n = fread(RSTRING(str)->ptr+bytes, 1, siz-bytes, fptr->f);
	TRAP_END;
	if (n <= 0) {
	    if (ferror(fptr->f)) rb_sys_fail(fptr->path);
	    return str_new(0, 0);
	}
	bytes += n;
	if (bytes <  siz) break;
	siz += BUFSIZ;
	str_resize(str, siz);
    }
    if (bytes == 0) return str_new(0, 0);
    if (bytes != siz) str_resize(str, bytes);
    return str_taint(str);
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

    if (rb_scan_args(argc, argv, "01", &length) == 0 || NIL_P(length)) {
	return read_all(io);
    }

    len = NUM2INT(length);
    GetOpenFile(io, fptr);
    io_readable(fptr);

    str = str_new(0, len);

    READ_CHECK(fptr->f);
    TRAP_BEG;
    n = fread(RSTRING(str)->ptr, 1, len, fptr->f);
    TRAP_END;
    if (n <= 0) {
	if (ferror(fptr->f)) rb_sys_fail(fptr->path);
	return Qnil;
    }
    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';

    return str_taint(str);
}

VALUE
io_gets_method(argc, argv, io)
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
	rs = RS;
    }
    else {
	rb_scan_args(argc, argv, "1", &rs);
	if (!NIL_P(rs)) Check_Type(rs, T_STRING);
    }

    if (NIL_P(rs)) {
	rsptr = 0;
	rslen = 0;
    }
    else {
	rslen = RSTRING(rs)->len;
	if (rslen == 0) {
	    rsptr = "\n\n";
	    rslen = 2;
	    rspara = 1;
	}
	else if (rslen == 1 && RSTRING(rs)->ptr[0] == '\n') {
	    return io_gets(io);
	}
	else {
	    rsptr = RSTRING(rs)->ptr;
	}
    }

    GetOpenFile(io, fptr);
    io_readable(fptr);
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
		    if (errno == EINTR) continue;
		    break;
		}
		if ((*bp++ = c) == newline) break;
		if (bp == bpe) break;
	    }
	    cnt = bp - buf;
	}
	else {
	    READ_CHECK(f);
	    TRAP_BEG;
	    cnt = fread(buf, 1, sizeof(buf), f);
	    TRAP_END;
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
	    str_cat(str, buf, cnt);
	else
	    str = str_new(buf, cnt);

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
	str_taint(str);
    }
    lastline_set(str);

    return str;
}

VALUE
io_gets(io)
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
    io_readable(fptr);
    f = fptr->f;

  again:
    bp = buf;
    for (;;) {
	READ_CHECK(f);
	TRAP_BEG;
	c = getc(f);
	TRAP_END;
	if (c == EOF) {
	    if (errno == EINTR) continue;
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
	str_cat(str, buf, cnt);
    else
	str = str_new(buf, cnt);

    if (c != EOF && RSTRING(str)->ptr[RSTRING(str)->len-1] != '\n') {
	append = 1;
	goto again;
    }

  return_gets:
    if (!NIL_P(str)) {
	fptr->lineno++;
	lineno = INT2FIX(fptr->lineno);
	str_taint(str);
    }
    lastline_set(str);

    return str;
}

static VALUE
io_lineno(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    io_readable(fptr);
    return INT2NUM(fptr->lineno);
}

static VALUE
io_set_lineno(io, lineno)
    VALUE io, lineno;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    io_readable(fptr);
    fptr->lineno = NUM2INT(lineno);
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
io_readline(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE line = io_gets_method(argc, argv, io);

    if (NIL_P(line)) {
	eof_error();
    }
    return line;
}

static VALUE
io_readlines(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE line, ary;

    ary = ary_new();
    while (!NIL_P(line = io_gets_method(argc, argv, io))) {
	ary_push(ary, line);
    }
    return ary;
}

static VALUE
io_each_line(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE str;

    while (!NIL_P(str = io_gets_method(argc, argv, io))) {
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
io_each_byte(io)
    VALUE io;
{
    OpenFile *fptr;
    FILE *f;
    int c;

    GetOpenFile(io, fptr);
    io_readable(fptr);
    f = fptr->f;

    for (;;) {
	READ_CHECK(f);
	TRAP_BEG;
	c = getc(f);
	TRAP_END;
	if (c == EOF) break;
	rb_yield(INT2FIX(c & 0xff));
    }
    if (ferror(f) != 0) rb_sys_fail(fptr->path);
    return Qnil;
}

VALUE
io_getc(io)
    VALUE io;
{
    OpenFile *fptr;
    FILE *f;
    int c;

    GetOpenFile(io, fptr);
    io_readable(fptr);
    f = fptr->f;

    READ_CHECK(f);
    TRAP_BEG;
    c = getc(f);
    TRAP_END;

    if (c == EOF) {
	if (ferror(f) != 0) rb_sys_fail(fptr->path);
	return Qnil;
    }
    return INT2FIX(c & 0xff);
}

static VALUE
io_readchar(io)
    VALUE io;
{
    VALUE c = io_getc(io);

    if (NIL_P(c)) {
	eof_error();
    }
    return c;
}

VALUE
io_ungetc(io, c)
    VALUE io, c;
{
    OpenFile *fptr;

    Check_Type(c, T_FIXNUM);
    GetOpenFile(io, fptr);
    io_readable(fptr);

    if (ungetc(FIX2INT(c), fptr->f) == EOF)
	rb_sys_fail(fptr->path);
    return Qnil;
}

static VALUE
io_isatty(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    if (isatty(fileno(fptr->f)) == 0)
	return FALSE;
    return TRUE;
}

static void
fptr_finalize(fptr)
    OpenFile *fptr;
{
    if (fptr->f != NULL) {
	fclose(fptr->f);
    }
    if (fptr->f2 != NULL) {
	fclose(fptr->f2);
    }
    if (fptr->pid) {
	rb_syswait(fptr->pid);
	fptr->pid = 0;
    }
}

static void
io_fptr_close(fptr)
    OpenFile *fptr;
{
    if (fptr->f == NULL && fptr->f2 == NULL) return;

    if (fptr->finalize) {
	(*fptr->finalize)(fptr);
    }
    else {
	fptr_finalize(fptr);
    }
    fptr->f = fptr->f2 = NULL;
}

void
io_fptr_finalize(fptr)
    OpenFile *fptr;
{
    io_fptr_close(fptr);
    if (fptr->path) {
	free(fptr->path);
	fptr->path = NULL;
    }
}

VALUE
io_close(io)
    VALUE io;
{
    OpenFile *fptr;

    GetOpenFile(io, fptr);
    io_fptr_close(fptr);

    return Qnil;
}

VALUE
io_close_method(io)
    VALUE io;
{
    rb_secure(4);
    return io_close(io);
}

static VALUE
io_closed(io)
    VALUE io;
{
    OpenFile *fptr;

    fptr = RFILE(io)->fptr;
    return (fptr->f || fptr->f2)?FALSE:TRUE;
}

static VALUE
io_syswrite(io, str)
    VALUE io, str;
{
    OpenFile *fptr;
    FILE *f;
    int n;

    rb_secure(4);
    if (TYPE(str) != T_STRING)
	str = obj_as_string(str);

    GetOpenFile(io, fptr);
    io_writable(fptr);
    f = GetWriteFile(fptr);

#ifdef THREAD
    thread_fd_writable(fileno(f));
#endif
    n = write(fileno(f), RSTRING(str)->ptr, RSTRING(str)->len);

    if (n == -1) rb_sys_fail(fptr->path);

    return INT2FIX(n);
}

static VALUE
io_sysread(io, len)
    VALUE io, len;
{
    OpenFile *fptr;
    int n, ilen;
    VALUE str;

    ilen = NUM2INT(len);
    GetOpenFile(io, fptr);
    io_readable(fptr);

    str = str_new(0, ilen);

#ifdef THREAD
    thread_wait_fd(fileno(fptr->f));
#endif
    TRAP_BEG;
    n = read(fileno(fptr->f), RSTRING(str)->ptr, RSTRING(str)->len);
    TRAP_END;

    if (n == -1) rb_sys_fail(fptr->path);
    if (n == 0) eof_error();

    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';
    return str_taint(str);
}

VALUE
io_binmode(io)
    VALUE io;
{
#if defined(NT) || defined(DJGPP) || defined(__CYGWIN32__) || defined(__human68k__) || defined(USE_CWGUSI)
    OpenFile *fptr;

    GetOpenFile(io, fptr);
#ifdef __human68k__
    if (fptr->f)
	fmode(fptr->f, _IOBIN);
    if (fptr->f2)
	fmode(fptr->f2, _IOBIN);
#else
# ifndef USE_CWGUSI
    if (fptr->f && setmode(fileno(fptr->f), O_BINARY) == -1)
	rb_sys_fail(fptr->path);
    if (fptr->f2 && setmode(fileno(fptr->f2), O_BINARY) == -1)
	rb_sys_fail(fptr->path);
# else  /* USE_CWGUSI */
	if (fptr->f)
		fptr->f->mode.binary_io = 1;
	if (fptr->f2)
		fptr->f2->mode.binary_io = 1;
# endif /* USE_CWGUSI */
#endif

    fptr->mode |= FMODE_BINMODE;
#endif
    return io;
}

int
io_mode_flags(mode)
    char *mode;
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
	ArgError("illegal access mode");
    }

    if (mode[1] == 'b') {
	flags |= FMODE_BINMODE;
	mode++;
    }

    if (mode[1] == '+') {
	flags |= FMODE_READWRITE;
    }

    return flags;
}

FILE *
rb_fopen(fname, mode)
    char *fname;
    char *mode;
{
    FILE *f;

    f = fopen(fname, mode);
    if (f == NULL) {
	if (errno == EMFILE || errno == ENFILE) {
	    gc_gc();
	    f = fopen(fname, mode);
	}
	if (f == NULL) {
	    rb_sys_fail(fname);
	}
    }
    return f;
}

FILE *
rb_fdopen(fd, mode)
    int fd;
    char *mode;
{
    FILE *f;

    f = fdopen(fd, mode);
    if (f == NULL) {
	if (errno == EMFILE) {
	    f = fdopen(fd, mode);
	}
	if (f == NULL) {
	    rb_sys_fail(0);
	}
    }
    return f;
}

#if defined (NT) || defined(DJGPP) || defined(__CYGWIN32__) || defined(__human68k__)
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
pipe_atexit()
{
    struct pipe_list *list = pipe_list;
    struct pipe_list *tmp;

    while (list) {
	tmp = list->next;
	io_fptr_finalize(list->fptr);
	list = tmp;
    }
}

static void
pipe_finalize(fptr)
    OpenFile *fptr;
{
#if !defined (__CYGWIN32__)
    if (fptr->f != NULL) {
	pclose(fptr->f);
    }
    if (fptr->f2 != NULL) {
	pclose(fptr->f2);
    }
#else
    fptr_finalize(fptr);
#endif
    fptr->f = fptr->f2 = NULL;
    pipe_del_fptr(fptr);
}
#endif

void
io_unbuffered(fptr)
    OpenFile *fptr;
{
    if (fptr->f2 == 0) TypeError("non-writable fptr");
    if (fptr->f != 0) setbuf(fptr->f, NULL);
    setbuf(fptr->f2, NULL);
    fptr->mode |= FMODE_SYNC;
}

static VALUE
pipe_open(pname, mode)
    char *pname, *mode;
{
#ifndef USE_CWGUSI
    int modef = io_mode_flags(mode);
    OpenFile *fptr;

#if defined(NT) || defined(DJGPP) || defined(__human68k__)
    FILE *f = popen(pname, mode);

    if (f == NULL) rb_sys_fail(pname);
    else {
	NEWOBJ(port, struct RFile);
	OBJSETUP(port, cIO, T_FILE);
	MakeOpenFile(port, fptr);
	fptr->finalize = pipe_finalize;
	fptr->mode = modef;

	pipe_add_fptr(fptr);
	if (modef & FMODE_READABLE) fptr->f  = f;
	if (modef & FMODE_WRITABLE) {
	    fptr->f2 = f;
	    io_unbuffered(fptr);
	}
	obj_call_init((VALUE)port);
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
	    extern char *sourcefile;
	    extern int   sourceline;
	    int fd;

	    for (fd = 3; fd < NOFILE; fd++)
		close(fd);
	    rb_proc_exec(pname);
	    fprintf(stderr, "%s:%d: command not found: %s\n",
		    sourcefile, sourceline, pname);
	    _exit(127);
	}
	return Qnil;

      case -1:			/* fork failed */
	if (errno == EAGAIN) {
#ifdef THREAD
	    thread_sleep(1);
#else
	    sleep(1);
#endif
	    goto retry;
	}
	close(pr[0]); close(pw[1]);
	rb_sys_fail(pname);
	break;

      default:			/* parent */
	if (pid < 0) rb_sys_fail(pname);
	else {
	    NEWOBJ(port, struct RFile);
	    OBJSETUP(port, cIO, T_FILE);
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
#if defined (__CYGWIN32__)
	    fptr->finalize = pipe_finalize;
	    pipe_add_fptr(fptr);
#endif
	    obj_call_init((VALUE)port);
	    return (VALUE)port;
	}
    }
#endif
#else /* USE_CWGUSI */
	rb_notimplement();  
#endif
}

static VALUE
io_s_popen(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    char *mode;
    VALUE pname, pmode;

    if (rb_scan_args(argc, argv, "11", &pname, &pmode) == 1) {
	mode = "r";
    }
    else {
	int len;

	mode = STR2CSTR(pmode);
	len = strlen(mode);
	if (len == 0 || len > 3)
	    ArgError("illegal access mode");
    }
    Check_SafeStr(pname);
    return pipe_open(RSTRING(pname)->ptr, mode);
}

static VALUE
io_open(fname, mode)
    char *fname, *mode;
{
    if (fname[0] == '|') {
	return pipe_open(fname+1, mode);
    }
    else {
	return file_open(fname, mode);
    }
}

static VALUE
f_open(argc, argv)
    int argc;
    VALUE *argv;
{
    char *mode;
    VALUE pname, pmode;
    VALUE port;

    rb_scan_args(argc, argv, "11", &pname, &pmode);
    Check_SafeStr(pname);
    if (NIL_P(pmode)) {
	mode = "r";
    }
    else {
	int len;

	mode = STR2CSTR(pmode);
	len = strlen(mode);
	if (len == 0 || len > 3)
	    ArgError("illegal access mode");
    }

    port = io_open(RSTRING(pname)->ptr, mode);
    if (NIL_P(port)) return Qnil;
    if (iterator_p()) {
	return rb_ensure(rb_yield, port, io_close, port);
    }

    return port;
}

static VALUE
io_get_io(io)
    VALUE io;
{
    return rb_convert_type(io, T_FILE, "IO", "to_io");
}

static char*
io_mode_string(fptr)
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

VALUE
io_reopen(io, nfile)
    VALUE io, nfile;
{
    OpenFile *fptr, *orig;
    char *mode;
    int fd;

    GetOpenFile(io, fptr);
    nfile = io_get_io(nfile);
    GetOpenFile(nfile, orig);

    if (fptr == orig) return io;
    if (orig->f2) {
	fflush(orig->f2);
    }
    else if (orig->mode & FMODE_WRITABLE) {
	fflush(orig->f);
    }

    /* copy OpenFile structure */
    fptr->mode = orig->mode;
    fptr->pid = orig->pid;
    fptr->lineno = orig->lineno;
    if (fptr->path) free(fptr->path);
    if (orig->path) fptr->path = strdup(orig->path);
    else fptr->path = 0;
    fptr->finalize = orig->finalize;

    mode = io_mode_string(fptr);
    fd = fileno(fptr->f);
    if (fd < 3) {
	/* need to keep stdio */
	if (dup2(fileno(orig->f), fd) < 0)
	    rb_sys_fail(orig->path);
    }
    else {
	fclose(fptr->f);
	if (dup2(fileno(orig->f), fd) < 0)
	    rb_sys_fail(orig->path);
	fptr->f = rb_fdopen(fd, mode);
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
	io_binmode(io);
    }

    RBASIC(io)->klass = RBASIC(nfile)->klass;
    return io;
}

static VALUE
io_clone(io)
    VALUE io;
{
    OpenFile *fptr, *orig;
    int fd;
    char *mode;

    NEWOBJ(obj, struct RFile);
    OBJSETUP(obj, CLASS_OF(io), T_FILE);

    GetOpenFile(io, orig);
    MakeOpenFile(obj, fptr);

    if (orig->f2) {
	fflush(orig->f2);
    }
    else if (orig->mode & FMODE_WRITABLE) {
	fflush(orig->f);
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
    fd = dup(fileno(orig->f));
    fptr->f = rb_fdopen(fd, mode);
    if (fptr->f2) {
	fd = dup(fileno(orig->f2));
	fptr->f = rb_fdopen(fd, "w");
    }
    if (fptr->mode & FMODE_BINMODE) {
	io_binmode((VALUE)obj);
    }

    return (VALUE)obj;
}

static VALUE
io_printf(argc, argv, out)
    int argc;
    VALUE argv[];
    VALUE out;
{
    rb_funcall(out, id_write, 1, f_sprintf(argc, argv));

    return Qnil;
}

static VALUE
f_printf(argc, argv)
    int argc;
    VALUE argv[];
{
    VALUE out;

    if (argc == 0) return Qnil;
    if (TYPE(argv[0]) == T_STRING) {
	out = rb_defout;
    }
    else if (rb_respond_to(argv[0], id_write)) {
	out = argv[0];
	argv++;
	argc--;
    }
    else {
	NameError("output must responds to `write'");
    }
    rb_funcall(out, id_write, 1, f_sprintf(argc, argv));

    return Qnil;
}

static VALUE
io_print(argc, argv, out)
    int argc;
    VALUE *argv;
    VALUE out;
{
    int i, j;
    VALUE line;

    /* if no argument given, print `$_' */
    if (argc == 0) {
	argc = 1;
	line = lastline_get();
	argv = &line;
    }
    for (i=0; i<argc; i++) {
	if (!NIL_P(OFS) && i>0) {
	    io_write(out, OFS);
	}
	switch (TYPE(argv[i])) {
	  case T_NIL:
	    io_write(out, str_new2("nil"));
	    break;
	  case T_ARRAY:
	    for (j=0; j<RARRAY(argv[i])->len; j++) {
		if (!NIL_P(OFS) && j>0) {
		    io_write(out, OFS);
		}
		io_write(out, RARRAY(argv[i])->ptr[j]);
	    }
	    break;
	  default:
	    io_write(out, argv[i]);
	    break;
	}
    }
    if (!NIL_P(ORS)) {
	io_write(out, ORS);
    }

    return Qnil;
}

static VALUE
f_print(argc, argv)
    int argc;
    VALUE *argv;
{
    io_print(argc, argv, rb_defout);
    return Qnil;
}

static VALUE
io_putc(io, ch)
    VALUE io, ch;
{
    OpenFile *fptr;
    FILE *f;
    int c = NUM2CHR(ch);

    rb_secure(4);
    GetOpenFile(io, fptr);
    io_writable(fptr);

    f = GetWriteFile(fptr);

    if (fputc(c, f) == EOF || ferror(f))
	rb_sys_fail(fptr->path);
    if (fptr->mode & FMODE_SYNC)
	fflush(f);

    return ch;
}

static VALUE
f_putc(recv, ch)
    VALUE recv, ch;
{
    return io_putc(rb_defout, ch);
}

static VALUE
io_puts(argc, argv, out)
    int argc;
    VALUE *argv;
    VALUE out;
{
    int i, j;
    VALUE line;

    /* if no argument given, print newline. */
    if (argc == 0) {
	io_write(out, RS_default);
	return Qnil;
    }
    for (i=0; i<argc; i++) {
	switch (TYPE(argv[i])) {
	  case T_NIL:
	    line = str_new2("nil");
	    break;
	  case T_ARRAY:
	    for (j=0; j<RARRAY(argv[i])->len; j++) {
		io_puts(1, &RARRAY(argv[i])->ptr[j], out);
	    }
	    continue;
	  default:
	    line = argv[i];
	    break;
	}
	line = obj_as_string(line);
	io_write(out, line);
	if (RSTRING(line)->ptr[RSTRING(line)->len-1] != '\n') {
	    io_write(out, RS_default);
	}
    }

    return Qnil;
}

static VALUE
f_puts(argc, argv)
    int argc;
    VALUE *argv;
{
    io_puts(argc, argv, rb_defout);
    return Qnil;
}

void
rb_p(obj)			/* for debug print within C code */
    VALUE obj;
{
    io_write(rb_defout, rb_inspect(obj));
    io_write(rb_defout, RS_default);
}

static VALUE
f_p(argc, argv)
    int argc;
    VALUE *argv;
{
    int i;

    for (i=0; i<argc; i++) {
	rb_p(argv[i]);
    }
    return Qnil;
}

static VALUE
obj_display(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE out;

    if (rb_scan_args(argc, argv, "01", &out) == 0) {
	out = rb_defout;
    }

    io_write(out, self);

    return Qnil;
}

static void
io_defset(val, id)
    VALUE val;
    ID id;
{
    if (TYPE(val) == T_STRING) {
	val = io_open(RSTRING(val)->ptr, "w");
    }
    if (!rb_respond_to(val, id_write)) {
	TypeError("$> must have write method, %s given",
		  rb_class2name(CLASS_OF(val)));
    }
    rb_defout = val;
}

static void
io_stdio_set(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    OpenFile *fptr;
    int fd;

    if (TYPE(val) != T_FILE) {
	TypeError("%s must be IO object", rb_id2name(id));
    }
    GetOpenFile(*var, fptr);
    fd = fileno(fptr->f);
    GetOpenFile(val, fptr);
    if (fd == 0) {
	io_readable(fptr);
    }
    else {
	io_writable(fptr);
    }
    io_reopen(*var, val);
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
    obj_call_init((VALUE)io);

    return (VALUE)io;
}

static VALUE
io_s_new(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE fnum, mode;
    char *m = "r";

    if (rb_scan_args(argc, argv, "11", &fnum, &mode) == 2) {
	Check_SafeStr(mode);
	m = RSTRING(mode)->ptr;
    }
    return prep_stdio(rb_fdopen(NUM2INT(fnum), m), io_mode_flags(m), klass);
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
	    file = rb_stdin;
	}
	init_p = 1;
	gets_lineno = 0;
    }

  retry:
    if (next_p == 1) {
	next_p = 0;
	if (RARRAY(rb_argv)->len > 0) {
	    filename = ary_shift(rb_argv);
	    fn = STR2CSTR(filename);
	    if (strlen(fn) == 1 && fn[0] == '-') {
		file = rb_stdin;
		if (inplace) {
		    rb_defout = rb_stdout;
		}
	    }
	    else {
		FILE *fr = rb_fopen(fn, "r");

		if (inplace) {
		    struct stat st, st2;
		    VALUE str;
		    FILE *fw;

		    if (TYPE(rb_defout) == T_FILE && rb_defout != rb_stdout) {
			io_close(rb_defout);
		    }
		    fstat(fileno(fr), &st);
		    if (*inplace) {
			str = str_new2(fn);
#if defined(MSDOS) || defined(__CYGWIN32__) || defined(NT)
			add_suffix(str, inplace);
#else
			str_cat(str, inplace, strlen(inplace));
#endif
#if defined(MSDOS) || defined(__BOW__) || defined(__CYGWIN32__) || defined(NT) || defined(__human68k__)
			(void)fclose(fr);
			(void)unlink(RSTRING(str)->ptr);
			(void)rename(fn, RSTRING(str)->ptr);
			fr = rb_fopen(RSTRING(str)->ptr, "r");
#else
			if (rename(fn, RSTRING(str)->ptr) < 0) {
			    Warn("Can't rename %s to %s: %s, skipping file",
				 fn, RSTRING(str)->ptr, strerror(errno));
			    fclose(fr);
			    goto retry;
			}
#endif
		    }
		    else {
#if !defined(MSDOS) && !defined(__BOW__) && !defined(__CYGWIN32__) && !defined(NT) && !defined(__human68k__)
			if (unlink(fn) < 0) {
			    Warn("Can't remove %s: %s, skipping file",
				 fn, strerror(errno));
			    fclose(fr);
			    goto retry;
			}
#else
			Fatal("Can't do inplace edit without backup");
#endif
		    }
		    fw = rb_fopen(fn, "w");
#if !defined(MSDOS) && !defined(__CYGWIN32__) && !(NT) && !defined(__human68k__)\
 && !defined(USE_CWGUSI) && !defined(__BEOS__)
		    fstat(fileno(fw), &st2);
		    fchmod(fileno(fw), st.st_mode);
		    if (st.st_uid!=st2.st_uid || st.st_gid!=st2.st_gid) {
			fchown(fileno(fw), st.st_uid, st.st_gid);
		    }
#endif
		    rb_defout = prep_stdio(fw, FMODE_WRITABLE, cFile);
		}
		file = prep_stdio(fr, FMODE_READABLE, cFile);
	    }
	}
	else {
	    init_p = 0;
	    return FALSE;
	}
    }
    return TRUE;
}

static VALUE
f_gets_method(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line;

  retry:
    if (!next_argv()) return Qnil;
    line = io_gets_method(argc, argv, file);
    if (NIL_P(line) && next_p != -1) {
	io_close(file);
	next_p = 1;
	goto retry;
    }
    gets_lineno++;
    lineno = INT2FIX(gets_lineno);

    return line;
}

VALUE
f_gets()
{
    return f_gets_method(0,0);
}

static VALUE
f_readline(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line = f_gets_method(argc, argv);

    if (NIL_P(line)) {
	eof_error();
    }

    return line;
}

static VALUE
f_tell()
{
  return io_tell(file);
}

static VALUE
f_seek(self, offset, ptrname)
     VALUE self, offset, ptrname;
{
  if (!next_argv()) {
    ArgError("no stream to seek");
  }

  return io_seek(file, offset, ptrname);
}

static VALUE
f_set_pos(self, offset)
     VALUE self, offset;
{
  if (!next_argv()) {
    ArgError("no stream to pos");
  }

  return io_set_pos(file, offset);
}

static VALUE
f_rewind()
{
  return io_rewind(file);
}

static VALUE
f_eof()
{
    if (init_p == 0 && !next_argv())
	return TRUE;
    if (io_eof(file)) {
	next_p = 1;
	return TRUE;
    }
    return FALSE;
}

static VALUE
f_getc()
{
    return io_getc(rb_stdin);
}

static VALUE
f_ungetc(self, c)
    VALUE self, c;
{
    if (!next_argv()) {
	ArgError("no stream to ungetc");
    }

    return io_ungetc(file, c);
}

static VALUE
f_readchar()
{
    VALUE c = f_getc();

    if (NIL_P(c)) {
	eof_error();
    }
    return c;
}

static VALUE
f_readlines(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE line, ary;

    ary = ary_new();
    while (!NIL_P(line = f_gets_method(argc, argv))) {
	ary_push(ary, line);
    }

    return ary;
}

void
rb_str_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    if (!NIL_P(val) && TYPE(val) != T_STRING) {
	TypeError("value of %s must be String", rb_id2name(id));
    }
    *var = val;
}

static VALUE
f_backquote(obj, str)
    VALUE obj, str;
{
    VALUE port, result;

    Check_SafeStr(str);
    port = pipe_open(RSTRING(str)->ptr, "r");
    if (NIL_P(port)) return Qnil;

    result = read_all(port);

    io_close(port);

    if (NIL_P(result)) return str_new(0,0);
    return result;
}

#ifdef HAVE_SYS_SELECT_H
#include <sys/select.h>
#endif
#ifdef NT
#define select(v, w, x, y, z) (-1) /* anytime fail */
#endif

static VALUE
f_select(argc, argv, obj)
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
	tp = NULL;
    }
    else {
	timerec = time_timeval(timeout);
	tp = &timerec;
    }

    FD_ZERO(&pset);
    if (!NIL_P(read)) {
	Check_Type(read, T_ARRAY);
	rp = &rset;
	FD_ZERO(rp);
	for (i=0; i<RARRAY(read)->len; i++) {
	    GetOpenFile(io_get_io(RARRAY(read)->ptr[i]), fptr);
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
	rp = NULL;

    if (!NIL_P(write)) {
	Check_Type(write, T_ARRAY);
	wp = &wset;
	FD_ZERO(wp);
	for (i=0; i<RARRAY(write)->len; i++) {
	    GetOpenFile(io_get_io(RARRAY(write)->ptr[i]), fptr);
	    FD_SET(fileno(fptr->f), wp);
	    if (max < fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), wp);
		if (max < fileno(fptr->f2)) max = fileno(fptr->f2);
	    }
	}
    }
    else
	wp = NULL;

    if (!NIL_P(except)) {
	Check_Type(except, T_ARRAY);
	ep = &eset;
	FD_ZERO(ep);
	for (i=0; i<RARRAY(except)->len; i++) {
	    GetOpenFile(io_get_io(RARRAY(except)->ptr[i]), fptr);
	    FD_SET(fileno(fptr->f), ep);
	    if (max < fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), ep);
		if (max < fileno(fptr->f2)) max = fileno(fptr->f2);
	    }
	}
    }
    else
	ep = NULL;

    max++;

#ifdef THREAD
    n = thread_select(max, rp, wp, ep, tp);
    if (n < 0) {
	rb_sys_fail(0);
    }
#else
  retry:
    TRAP_BEG;
    n = select(max, rp, wp, ep, tp);
    TRAP_END;
    if (n < 0) {
	if (errno != EINTR) {
	    rb_sys_fail(0);
	}
	if (tp == NULL) goto retry;
	interrupt_flag = 1;
    }
#endif
    if (!pending && n == 0) return Qnil; /* returns nil on timeout */

    res = ary_new2(3);
    ary_push(res, rp?ary_new():ary_new2(0));
    ary_push(res, wp?ary_new():ary_new2(0));
    ary_push(res, ep?ary_new():ary_new2(0));

    if (interrupt_flag == 0) {
	if (rp) {
	    list = RARRAY(res)->ptr[0];
	    for (i=0; i< RARRAY(read)->len; i++) {
		GetOpenFile(io_get_io(RARRAY(read)->ptr[i]), fptr);
		if (FD_ISSET(fileno(fptr->f), rp)
		    || FD_ISSET(fileno(fptr->f), &pset)) {
		    ary_push(list, RARRAY(read)->ptr[i]);
		}
	    }
	}

	if (wp) {
	    list = RARRAY(res)->ptr[1];
	    for (i=0; i< RARRAY(write)->len; i++) {
		GetOpenFile(io_get_io(RARRAY(write)->ptr[i]), fptr);
		if (FD_ISSET(fileno(fptr->f), wp)) {
		    ary_push(list, RARRAY(write)->ptr[i]);
		}
		else if (fptr->f2 && FD_ISSET(fileno(fptr->f2), wp)) {
		    ary_push(list, RARRAY(write)->ptr[i]);
		}
	    }
	}

	if (ep) {
	    list = RARRAY(res)->ptr[2];
	    for (i=0; i< RARRAY(except)->len; i++) {
		GetOpenFile(io_get_io(RARRAY(except)->ptr[i]), fptr);
		if (FD_ISSET(fileno(fptr->f), ep)) {
		    ary_push(list, RARRAY(except)->ptr[i]);
		}
		else if (fptr->f2 && FD_ISSET(fileno(fptr->f2), ep)) {
		    ary_push(list, RARRAY(except)->ptr[i]);
		}
	    }
	}
    }

    return res;			/* returns an empty array on interrupt */
}

static VALUE
io_ctl(io, req, arg, io_p)
    VALUE io, req, arg;
    int io_p;
{
#if !defined(MSDOS) && !defined(__human68k__)
    int cmd = NUM2INT(req);
    OpenFile *fptr;
    int len = 0;
    int fd;
    long narg = 0;
    int retval;

    rb_secure(2);
    GetOpenFile(io, fptr);

    if (NIL_P(arg) || arg == FALSE) {
	narg = 0;
    }
    else if (FIXNUM_P(arg)) {
	narg = FIX2INT(arg);
    }
    else if (arg == TRUE) {
	narg = 1;
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
	str_modify(arg);

	if (len <= RSTRING(arg)->len) {
	    len = RSTRING(arg)->len;
	}
	if (RSTRING(arg)->len < len) {
	    str_resize(arg, len+1);
	}
	RSTRING(arg)->ptr[len] = 17;	/* a little sanity check here */
	narg = (long)RSTRING(arg)->ptr;
    }
    fd = fileno(fptr->f);
#ifdef HAVE_FCNTL
    TRAP_BEG;
# ifdef USE_CWGUSI
    retval = io_p?ioctl(fd, cmd, (void*) narg):fcntl(fd, cmd, narg);
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
    if (retval < 0) rb_sys_fail(fptr->path);
    if (TYPE(arg) == T_STRING && RSTRING(arg)->ptr[len] != 17) {
	ArgError("return value overflowed string");
    }
    return INT2NUM(retval);
#else
    rb_notimplement();
#endif
}

static VALUE
io_ioctl(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE req, arg;

    rb_scan_args(argc, argv, "11", &req, &arg);
    return io_ctl(io, req, arg, 1);
}

static VALUE
io_fcntl(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
#ifdef HAVE_FCNTL
    VALUE req, arg;

    rb_scan_args(argc, argv, "11", &req, &arg);
    return io_ctl(io, req, arg, 0);
#else
    rb_notimplement();
#endif
}

static VALUE
f_syscall(argc, argv)
    int argc;
    VALUE *argv;
{
#ifdef HAVE_SYSCALL
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
	ArgError("too few arguments for syscall");
    arg[0] = NUM2INT(argv[0]); argv++;
    while (items--) {
	if (FIXNUM_P(*argv)) {
	    arg[i] = (unsigned long)NUM2INT(*argv); argv++;
	}
	else {
	    Check_Type(*argv, T_STRING);
	    str_modify(*argv);
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
    if (retval == -1) rb_sys_fail(0);
    return INT2FIX(0);
#else
    rb_notimplement();
#endif
}

static VALUE
io_s_pipe()
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

    r = prep_stdio(fdopen(pipes[0], "r"), FMODE_READABLE, cIO);
    w = prep_stdio(fdopen(pipes[1], "w"), FMODE_WRITABLE, cIO);

    ary = ary_new2(2);
    ary_push(ary, r);
    ary_push(ary, w);

    return ary;
#else
    rb_notimplement();
#endif
}

struct foreach_arg {
    int argc;
    VALUE sep;
    VALUE io;
};

static VALUE
io_foreach_line(arg)
    struct foreach_arg *arg;
{
    VALUE str;

    while (!NIL_P(str = io_gets_method(arg->argc, &arg->sep, arg->io))) {
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
io_s_foreach(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "11", &fname, &arg.sep);
    Check_SafeStr(fname);

    arg.argc = argc - 1;
    arg.io = io_open(RSTRING(fname)->ptr, "r");
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(io_foreach_line, (VALUE)&arg, io_close, arg.io);
}

static VALUE
io_readline_line(arg)
    struct foreach_arg *arg;
{
    VALUE line, ary;

    ary = ary_new();
    while (!NIL_P(line = io_gets_method(arg->argc, &arg->sep, arg->io))) {
	ary_push(ary, line);
    }

    return ary;
}

static VALUE
io_s_readlines(argc, argv, io)
    int argc;
    VALUE *argv;
    VALUE io;
{
    VALUE fname;
    struct foreach_arg arg;

    rb_scan_args(argc, argv, "11", &fname, &arg.sep);
    Check_SafeStr(fname);

    arg.argc = argc - 1;
    arg.io = io_open(RSTRING(fname)->ptr, "r");
    if (NIL_P(arg.io)) return Qnil;
    return rb_ensure(io_readline_line, (VALUE)&arg, io_close, arg.io);
}

static VALUE
arg_fileno()
{
    return io_fileno(file);
}

static VALUE
arg_to_io()
{
    return file;
}

static VALUE
arg_read(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE tmp, str;
    int len;

    if (argc == 1) len = NUM2INT(argv[0]);
    str = Qnil;

  retry:
    if (!next_argv()) return str;
    tmp = io_read(argc, argv, file);
    if ((NIL_P(tmp)  || RSTRING(tmp)->len == 0) && next_p != -1) {
	io_close(file);
	next_p = 1;
	goto retry;
    }
    if (NIL_P(tmp) || RSTRING(tmp)->len == 0) return str;
    else if (NIL_P(str)) str = tmp;
    else str_cat(str, RSTRING(tmp)->ptr, RSTRING(tmp)->len);
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
arg_getc()
{
    VALUE byte;

  retry:
    if (!next_argv()) return Qnil;
    byte = io_getc(file);
    if (NIL_P(byte) && next_p != -1) {
	io_close(file);
	next_p = 1;
	goto retry;
    }

    return byte;
}

static VALUE
arg_readchar()
{
    VALUE c = io_getc(file);

    if (NIL_P(c)) {
	eof_error();
    }
    return c;
}

static VALUE
arg_each_line(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE str;

    while (RTEST(str = f_gets_method(argc, argv))) {
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
arg_each_byte()
{
    VALUE byte;

    while (!NIL_P(byte = arg_getc())) {
	rb_yield(byte);
    }
    return Qnil;
}

static VALUE
arg_filename()
{
    return filename;
}

static VALUE
arg_file()
{
    return file;
}

static VALUE
arg_skip()
{
    if (next_p != -1) {
	io_close(file);
	next_p = 1;
    }
    return argf;
}

static VALUE
arg_close()
{
    io_close(file);
    if (next_p != -1) {
	next_p = 1;
    }
    gets_lineno = 0;
    return argf;
}

static VALUE
arg_closed()
{
    return io_closed(file);
}

static VALUE
opt_i_get()
{
    if (!inplace) return Qnil;
    return str_new2(inplace);
}

static void
opt_i_set(val)
    VALUE val;
{
    if (!RTEST(val)) {
	inplace = 0;
	return;
    }
    inplace = STR2CSTR(val);
}

void
Init_IO()
{
    eIOError = rb_define_class("IOError", eStandardError);
    eEOFError = rb_define_class("EOFError", eIOError);

    id_write = rb_intern("write");

    rb_define_global_function("syscall", f_syscall, -1);

    rb_define_global_function("open", f_open, -1);
    rb_define_global_function("printf", f_printf, -1);
    rb_define_global_function("print", f_print, -1);
    rb_define_global_function("putc", f_putc, 1);
    rb_define_global_function("puts", f_puts, -1);
    rb_define_global_function("gets", f_gets_method, -1);
    rb_define_global_function("readline", f_readline, -1);
    rb_define_global_function("tell", f_tell, 0);
    rb_define_global_function("seek", f_seek, 2);
    rb_define_global_function("rewind", f_rewind, 0);
    rb_define_global_function("eof", f_eof, 0);
    rb_define_global_function("eof?", f_eof, 0);
    rb_define_global_function("getc", f_getc, 0);
    rb_define_global_function("readchar", f_readchar, 0);
    rb_define_global_function("select", f_select, -1);
    rb_define_global_function("ungetc", f_ungetc, 1);

    rb_define_global_function("readlines", f_readlines, -1);

    rb_define_global_function("`", f_backquote, 1);
    rb_define_global_function("pipe", io_s_pipe, 0);

    rb_define_global_function("p", f_p, -1);
    rb_define_method(mKernel, "display", obj_display, -1);

    cIO = rb_define_class("IO", cObject);
    rb_include_module(cIO, mEnumerable);

    rb_define_singleton_method(cIO, "new", io_s_new, -1);
    rb_define_singleton_method(cIO, "popen", io_s_popen, -1);
    rb_define_singleton_method(cIO, "foreach", io_s_foreach, -1);
    rb_define_singleton_method(cIO, "readlines", io_s_readlines, -1);
    rb_define_singleton_method(cIO, "select", f_select, -1);

    FS = OFS = Qnil;
    rb_define_hooked_variable("$;", &FS, 0, rb_str_setter);
    rb_define_hooked_variable("$-F", &FS, 0, rb_str_setter);
    rb_define_hooked_variable("$,", &OFS, 0, rb_str_setter);

    RS = RS_default = str_new2("\n"); ORS = Qnil;
    rb_global_variable(&RS_default);
    str_freeze(RS_default);	/* avoid modifying RS_default */
    rb_define_hooked_variable("$/", &RS, 0, rb_str_setter);
    rb_define_hooked_variable("$-0", &RS, 0, rb_str_setter);
    rb_define_hooked_variable("$\\", &ORS, 0, rb_str_setter);

    rb_define_hooked_variable("$.", &lineno, 0, lineno_setter);
    rb_define_virtual_variable("$_", lastline_get, lastline_set);

    rb_define_method(cIO, "clone", io_clone, 0);
    rb_define_method(cIO, "reopen", io_reopen, 1);

    rb_define_method(cIO, "print", io_print, -1);
    rb_define_method(cIO, "putc", io_putc, 1);
    rb_define_method(cIO, "puts", io_puts, -1);
    rb_define_method(cIO, "printf", io_printf, -1);

    rb_define_method(cIO, "each",  io_each_line, -1);
    rb_define_method(cIO, "each_line",  io_each_line, -1);
    rb_define_method(cIO, "each_byte",  io_each_byte, 0);

    rb_define_method(cIO, "syswrite", io_syswrite, 1);
    rb_define_method(cIO, "sysread",  io_sysread, 1);

    rb_define_method(cIO, "fileno", io_fileno, 0);
    rb_define_alias(cIO, "to_i", "fileno");
    rb_define_method(cIO, "to_io", io_to_io, 0);

    rb_define_method(cIO, "sync",   io_sync, 0);
    rb_define_method(cIO, "sync=",  io_set_sync, 1);

    rb_define_method(cIO, "lineno",   io_lineno, 0);
    rb_define_method(cIO, "lineno=",  io_set_lineno, 1);

    rb_define_method(cIO, "readlines",  io_readlines, -1);

    rb_define_method(cIO, "read",  io_read, -1);
    rb_define_method(cIO, "write", io_write, 1);
    rb_define_method(cIO, "gets",  io_gets_method, -1);
    rb_define_method(cIO, "readline",  io_readline, -1);
    rb_define_method(cIO, "getc",  io_getc, 0);
    rb_define_method(cIO, "readchar",  io_readchar, 0);
    rb_define_method(cIO, "ungetc",io_ungetc, 1);
    rb_define_method(cIO, "<<",    io_addstr, 1);
    rb_define_method(cIO, "flush", io_flush, 0);
    rb_define_method(cIO, "tell", io_tell, 0);
    rb_define_method(cIO, "seek", io_seek, 2);
    rb_define_method(cIO, "rewind", io_rewind, 0);
    rb_define_method(cIO, "pos", io_tell, 0);
    rb_define_method(cIO, "pos=", io_set_pos, 1);
    rb_define_method(cIO, "eof", io_eof, 0);
    rb_define_method(cIO, "eof?", io_eof, 0);

    rb_define_method(cIO, "close", io_close_method, 0);
    rb_define_method(cIO, "closed?", io_closed, 0);

    rb_define_method(cIO, "isatty", io_isatty, 0);
    rb_define_method(cIO, "tty?", io_isatty, 0);
    rb_define_method(cIO, "binmode",  io_binmode, 0);

    rb_define_method(cIO, "ioctl", io_ioctl, -1);
    rb_define_method(cIO, "fcntl", io_fcntl, -1);

    rb_stdin = prep_stdio(stdin, FMODE_READABLE, cIO);
    rb_define_hooked_variable("$stdin", &rb_stdin, 0, io_stdio_set);
    rb_stdout = prep_stdio(stdout, FMODE_WRITABLE, cIO);
    rb_define_hooked_variable("$stdout", &rb_stdout, 0, io_stdio_set);
    rb_stderr = prep_stdio(stderr, FMODE_WRITABLE, cIO);
    rb_define_hooked_variable("$stderr", &rb_stderr, 0, io_stdio_set);
    rb_defout = rb_stdout;
    rb_define_hooked_variable("$>", &rb_defout, 0, io_defset);

    rb_define_global_const("STDIN", rb_stdin);
    rb_define_global_const("STDOUT", rb_stdout);
    rb_define_global_const("STDERR", rb_stderr);

    argf = obj_alloc(cObject);
    rb_extend_object(argf, mEnumerable);

    rb_define_readonly_variable("$<", &argf);
    rb_define_global_const("ARGF", argf);

    rb_define_singleton_method(argf, "fileno", arg_fileno, 0);
    rb_define_singleton_method(argf, "to_i", arg_fileno, 0);
    rb_define_singleton_method(argf, "to_io", arg_to_io, 0);
    rb_define_singleton_method(argf, "each",  arg_each_line, -1);
    rb_define_singleton_method(argf, "each_line",  arg_each_line, -1);
    rb_define_singleton_method(argf, "each_byte",  arg_each_byte, 0);

    rb_define_singleton_method(argf, "read",  arg_read, -1);
    rb_define_singleton_method(argf, "readlines", f_readlines, -1);
    rb_define_singleton_method(argf, "to_a", f_readlines, -1);
    rb_define_singleton_method(argf, "gets", f_gets_method, -1);
    rb_define_singleton_method(argf, "readline", f_readline, -1);
    rb_define_singleton_method(argf, "getc", arg_getc, 0);
    rb_define_singleton_method(argf, "readchar", arg_readchar, 0);
    rb_define_singleton_method(argf, "tell", f_tell, 0);
    rb_define_singleton_method(argf, "seek", f_seek, 2);
    rb_define_singleton_method(argf, "rewind", f_rewind, 0);
    rb_define_singleton_method(argf, "pos", f_tell, 0);
    rb_define_singleton_method(argf, "pos=", f_set_pos, 1);
    rb_define_singleton_method(argf, "eof", f_eof, 0);
    rb_define_singleton_method(argf, "eof?", f_eof, 0);
    rb_define_singleton_method(argf, "ungetc", f_ungetc, 1);

    rb_define_singleton_method(argf, "to_s", arg_filename, 0);
    rb_define_singleton_method(argf, "filename", arg_filename, 0);
    rb_define_singleton_method(argf, "file", arg_file, 0);
    rb_define_singleton_method(argf, "skip", arg_skip, 0);
    rb_define_singleton_method(argf, "close", arg_close, 0);
    rb_define_singleton_method(argf, "closed?", arg_closed, 0);

    filename = str_new2("-");
    rb_define_readonly_variable("$FILENAME", &filename);
    file = rb_stdin;
    rb_global_variable(&file);

    rb_define_virtual_variable("$-i", opt_i_get, opt_i_set);

#if defined (NT) || defined(DJGPP) || defined(__CYGWIN32__) || defined(__human68k__)
    atexit(pipe_atexit);
#endif

    Init_File();
}
