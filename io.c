/************************************************

  io.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:39 $
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "io.h"
#include <ctype.h>
#include <errno.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif
#ifdef HAVE_VFORK_H
#include <vfork.h>
#endif

VALUE rb_ad_string();

VALUE cIO;
extern VALUE cFile;

VALUE rb_stdin, rb_stdout, rb_stderr, rb_defout;

VALUE FS, OFS;
VALUE RS, ORS;

static VALUE argf;

ID id_write, id_fd, id_print_on;

extern char *inplace;

/* writing functions */
VALUE
io_write(obj, str)
    VALUE obj;
    struct RString *str;
{
    OpenFile *fptr;
    FILE *f;
    VALUE out;
    int n;

    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	Fail("not opened for writing");
    }

    f = (fptr->f2) ? fptr->f2 : fptr->f;
    if (f == NULL) Fail("closed stream");

    if (TYPE(str) != T_STRING)
	str = (struct RString*)obj_as_string(str);
    if (str->len == 0) return INT2FIX(0);

    n = fwrite(str->ptr, sizeof(char), str->len, f);
    if (n == 0 || ferror(f)) {
	rb_sys_fail(fptr->path);
    }
    if (fptr->mode & FMODE_SYNC) {
	fflush(f);
    }

    return INT2FIX(n);
}

static VALUE
io_puts(obj, str)
    VALUE obj, str;
{
    io_write(obj, str);
    return obj;
}

static VALUE
io_flush(obj)
    VALUE obj;
{
    OpenFile *fptr;
    FILE *f;

    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	Fail("not opend for writing");
    }
    f = (fptr->f2) ? fptr->f2 : fptr->f;
    if (f == NULL) Fail("closed stream");

    if (fflush(f) == EOF) rb_sys_fail(Qnil);

    return obj;
}

static VALUE
io_eof(obj)
    VALUE obj;
{
    OpenFile *fptr;
    int ch;

    GetOpenFile(obj, fptr);
#ifdef STDSTDIO			/* (the code works without this) */
    if (fptr->f->_cnt > 0)	/* cheat a little, since */
	return FALSE;		/* this is the most usual case */
#endif

    TRAP_BEG;
    ch = getc(fptr->f);
    TRAP_END;

    if (ch != EOF) {
	(void)ungetc(ch, fptr->f);
	return FALSE;
    }
#ifdef STDSTDIO
	if (fptr->f->_cnt < -1)
	    fptr->f->_cnt = -1;
#endif
    return TRUE;
}

static VALUE
io_sync(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    return (fptr->mode & FMODE_SYNC) ? TRUE : FALSE;
}

static VALUE
io_set_sync(obj, mode)
    VALUE obj, mode;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (mode) {
	fptr->mode |= FMODE_SYNC;
    }
    else {
	fptr->mode &= ~FMODE_SYNC;
    }
    return mode;
}

static VALUE
io_fileno(obj)
    VALUE obj;
{
    OpenFile *fptr;
    int fd;

    GetOpenFile(obj, fptr);
    fd = fileno(fptr->f);
    return INT2FIX(fd);
}

/* reading functions */
static VALUE
read_all(port)
    VALUE port;
{
    OpenFile *fptr;
    VALUE str;
    char buf[BUFSIZ];
    int n;

    GetOpenFile(port, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	Fail("not opend for reading");
    }
    if (fptr->f == NULL) Fail("closed stream");

    str = str_new(0, 0);
    for (;;) {
	TRAP_BEG;
	n = fread(buf, 1, BUFSIZ, fptr->f);
	TRAP_END;
	if (n == 0) {
	    if (feof(fptr->f)) break;
	    rb_sys_fail(Qnil);
	}
	str_cat(str, buf, n);
    }
    return str;
}

static VALUE
io_read(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    OpenFile *fptr;
    int n, lgt;
    VALUE len, str;

    if (rb_scan_args(argc, argv, "01", &len) == 0) {
	return read_all(obj);
    }

    lgt = NUM2INT(len);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	Fail("not opend for reading");
    }
    if (fptr->f == NULL) Fail("closed stream");

    str = str_new(0, lgt);

    TRAP_BEG;
    n = fread(RSTRING(str)->ptr, 1, RSTRING(str)->len, fptr->f);
    TRAP_END;
    if (n == 0) {
	if (feof(fptr->f)) return Qnil;
	rb_sys_fail(Qnil);
    }

    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';

    return str;
}

VALUE rb_lastline;
static VALUE lineno;

static VALUE
io_gets(obj)
    VALUE obj;
{
    OpenFile *fptr;
    FILE *f;
    struct RString *str;
    int c, newline;
    int rslen;

    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	Fail("not opend for reading");
    }
    f = fptr->f;
    if (f == NULL) Fail("closed stream");

    if (RS) {
	rslen = RSTRING(RS)->len;
	if (rslen == 0) {
	    newline = '\n';
	}
	else {
	    newline = RSTRING(RS)->ptr[rslen-1];
	}
    }
    else {
	newline = 0777;	/* non matching char */
	rslen = 1;
    }

    if (rslen == 0) {
	do {
	    TRAP_BEG;
	    c = getc(f);
	    TRAP_END;
	    if (c != '\n') {
		ungetc(c,f);
		break;
	    }
	} while (c != EOF);
    }

    {
	char buf[8192];
	char *bp, *bpe = buf + sizeof buf - 3;
	int append = 0;

      again:
	bp = buf;

      retry:
	TRAP_BEG;
	while ((c = getc(f)) != EOF && (*bp++ = c) != newline && bp < bpe)
	    ;
	TRAP_END;

	if (c == EOF) {
	    if (!feof(f)) goto retry;
	    if (!append && bp == buf) {
		str = Qnil;
		goto return_gets;
	    }
	}

	if (append)
	    str_cat(str, buf, bp - buf);
	else
	    str = (struct RString*)str_new(buf, bp - buf);

	if (c != EOF
	    &&
	    (c != newline
	     ||
	     (rslen > 1
	      &&
	      (str->len < rslen
	       ||
	       memcmp(str->ptr+str->len-rslen, RSTRING(RS)->ptr, rslen)
	       )
	      )
	     )
	    ) {
	    append = 1;
	    goto again;
	}
    }

  return_gets:
    if (rslen == 0) {
	while (c != EOF) {
	    TRAP_BEG;
	    c = getc(f);
	    TRAP_END;
	    if (c != '\n') {
		ungetc(c, f);
		break;
	    }
	}
    }

    if (str) {
	fptr->lineno++;
	lineno = INT2FIX(fptr->lineno);
    }
    return rb_lastline = (VALUE)str;
}

static VALUE
io_each_line(obj)
    VALUE obj;
{
    VALUE str;

    while (str = io_gets(obj)) {
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
io_each_byte(obj)
    VALUE obj;
{
    OpenFile *fptr;
    FILE *f;
    int c;

    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	Fail("not opend for reading");
    }
    f = fptr->f;
    if (f == NULL) Fail("closed stream");

    for (;;) {
	TRAP_BEG;
	c = getc(f);
	TRAP_END;
	if (c == EOF) break;
	rb_yield(INT2FIX(c & 0xff));
    }
    if (ferror(f) != 0) rb_sys_fail(Qnil);
    return obj;
}

static VALUE
io_getc(obj)
    VALUE obj;
{
    OpenFile *fptr;
    FILE *f;
    int c;

    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	Fail("not opend for reading");
    }
    f = fptr->f;
    if (f == NULL) Fail("closed stream");

    TRAP_BEG;
    c = getc(f);
    TRAP_END;

    if (c == EOF) {
	if (ferror(f) != 0) rb_sys_fail(Qnil);
	return Qnil;
    }
    return INT2FIX(c & 0xff);
}

static VALUE
io_isatty(obj)
    VALUE obj;
{
    OpenFile *fptr;

#ifndef NT
    GetOpenFile(obj, fptr);
    if (fptr->f == NULL) Fail("closed stream");
    if (isatty(fileno(fptr->f)) == 0)
	return FALSE;
#endif
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
    if (fptr->path) {
	free(fptr->path);
	fptr->path = NULL;
    }
    if (fptr->pid) {
	rb_syswait(fptr->pid);
	fptr->pid = 0;
    }
}

void
io_fptr_finalize(fptr)
    OpenFile *fptr;
{
    if (fptr->finalize) {
	(*fptr->finalize)(fptr);
	fptr->finalize = 0;
    }
    else {
	fptr_finalize(fptr);
    }
    fptr->f = fptr->f2 = NULL;
}

VALUE
io_close(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    io_fptr_finalize(fptr);

    return Qnil;
}

static VALUE
io_closed(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    return fptr->f?FALSE:TRUE;
}

static VALUE
io_syswrite(obj, str)
    VALUE obj, str;
{
    OpenFile *fptr;
    FILE *f;
    int n;

    if (TYPE(str) != T_STRING)
	str = obj_as_string(str);

    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	Fail("not opend for writing");
    }
    f = (fptr->f2) ? fptr->f2 : fptr->f;
    if (f == NULL) Fail("closed stream");

    n = write(fileno(f), RSTRING(str)->ptr, RSTRING(str)->len);

    if (n == -1) rb_sys_fail(Qnil);

    return INT2FIX(n);
}

static VALUE
io_sysread(obj, len)
    VALUE obj, len;
{
    OpenFile *fptr;
    int n, ilen;
    VALUE str;

    ilen = NUM2INT(len);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	Fail("not opend for reading");
    }
    if (fptr->f == NULL) Fail("closed stream");

    str = str_new(0, ilen);

    TRAP_BEG;
    n = read(fileno(fptr->f), RSTRING(str)->ptr, RSTRING(str)->len);
    TRAP_END;

    if (n == -1) rb_sys_fail(Qnil);
    if (n == 0) return Qnil;	/* EOF */

    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';
    return str;
}

static VALUE
io_binmode(obj)
    VALUE obj;
{
#ifdef NT
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (setmode(fileno(fptr), O_BINARY) == -1)
	rb_sys_fail(Qnil);
#endif
    return obj;
}

VALUE obj_alloc();

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
	Fail("illegal access mode");
    }
    if (mode[1] == '+') {
	flags |= FMODE_READABLE | FMODE_WRITABLE;
    }

    return flags;
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
	    rb_sys_fail(Qnil);
	}
    }
    return f;
}

#ifdef NT
static void
pipe_finalize(fptr)
    OpenFile *fptr;
{
    if (fptr->f != NULL) {
	pclose(fptr->f);
    }
    fptr->f = fptr->f2 = NULL;
}
#endif

static VALUE
pipe_open(pname, mode)
    char *pname, *mode;
{
    int modef = io_mode_flags(mode);
    VALUE port;
    OpenFile *fptr;

#ifdef NT
    FILE *f = popen(pname, mode);

    if (f == NULL) rb_sys_fail(pname);

    port = obj_alloc(cIO);
    MakeOpenFile(port, fptr);
    fptr->finalize = pipe_finalize;

    if (modef & FMODE_READABLE) fptr->f  = f;
    if (modef & FMODE_WRITABLE) fptr->f2 = f;
    fptr->mode = modef | FMODE_SYNC;
    return port;
#else
    int pid, pr[2], pw[2];
    volatile int doexec;

    if (((modef & FMODE_READABLE) && pipe(pr) == -1) ||
	((modef & FMODE_WRITABLE) && pipe(pw) == -1))
	rb_sys_fail(Qnil);

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
	    dup2(pr[1], 1);
	    close(pr[1]);
	}
	if (modef & FMODE_WRITABLE) {
	    close(pw[1]);
	    dup2(pw[0], 0);
	    close(pw[0]);
	}

	if (doexec) {
	    VALUE fd = io_fileno(rb_stderr);
	    int f = FIX2INT(fd);

	    if (f != 2) {
		close(2);
		dup2(f, 2);
		close(f);
	    }
	    rb_proc_exec(pname);
	    _exit(127);
	}
	return Qnil;

      case -1:			/* fork failed */
	if (errno == EAGAIN) {
	    sleep(1);
	    goto retry;
	}
	close(pr[0]); close(pw[1]);
	rb_sys_fail(pname);
	break;

      default:			/* parent */
	port = obj_alloc(cIO);
	MakeOpenFile(port, fptr);
	if (modef & FMODE_READABLE) close(pr[1]);
	if (modef & FMODE_WRITABLE) close(pw[0]);
	fptr->mode = modef;
	fptr->mode |= FMODE_SYNC;
    }

    fptr->pid = pid;
    if (modef & FMODE_READABLE) fptr->f  = rb_fdopen(pr[0], "r");
    if (modef & FMODE_WRITABLE) fptr->f2 = rb_fdopen(pw[1], "w");

    return port;
#endif
}

static VALUE
io_open(fname, mode)
    char *fname, *mode;
{
    int pipe = 0;

    if (fname[0] == '|') {
	return pipe_open(fname+1, mode);
    }
    else {
	return file_open(fname, mode);
    }
}

static VALUE
f_open(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    char *mode;
    VALUE port;
    int pipe = 0;
    VALUE pname, pmode;

    rb_scan_args(argc, argv, "11", &pname, &pmode);
    Check_Type(pname, T_STRING);
    if (pmode == Qnil) {
	mode = "r";
    }
    else {
	Check_Type(pmode, T_STRING);
	if (RSTRING(pmode)->len == 0 || RSTRING(pmode)->len > 2)
	    Fail("illegal access mode");
	mode = RSTRING(pmode)->ptr;
    }
    return io_open(RSTRING(pname)->ptr, mode);
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
    else if (rb_responds_to(argv[0], id_write)) {
	out = argv[0];
	argv++;
	argc--;
    }
    else {
	Fail("output must responds to `write'");
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
    int i;
    VALUE line;

    /* if no argument given, print `$_' */
    if (argc == 0) {
	argc = 1;
	if (rb_lastline)
	    argv = &rb_lastline;
	else {
	    line = str_new(0,0);
	    argv = &line;
	}
    }
    for (i=0; i<argc; i++) {
	if (OFS && i>0) {
	    io_write(out, OFS);
	}
	switch (TYPE(argv[i])) {
	  case T_STRING:
	    io_write(out, argv[i]);
	    break;
	  case T_ARRAY:
	    ary_print_on(argv[i], out);
	    break;
	  default:
	    rb_funcall(argv[i], id_print_on, 1, out);
	    break;
	}
    }
    if (ORS) {
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
io_defset(val, id)
    VALUE val;
    ID id;
{
    if (TYPE(val) == T_STRING) {
	val = io_open(RSTRING(val)->ptr, "w");
    }
    if (!obj_is_kind_of(val, cIO)) {
	Fail("$< must be a file, %s given", rb_class2name(CLASS_OF(val)));
    }
    return rb_defout = val;
}

static VALUE
f_print_on(obj, port)
    VALUE obj, port;
{
    return io_write(port, obj);
}

static VALUE
prep_stdio(f, mode)
    FILE *f;
    int mode;
{
    VALUE obj = obj_alloc(cIO);
    OpenFile *fp;

    MakeOpenFile(obj, fp);
    fp->f = f;
    fp->mode = mode;

    return obj;
}

static VALUE filename, file;
static int gets_lineno;
static int init_p = 0, next_p = 0;

static int
next_argv()
{
    extern VALUE Argv;
    char *fn;

    if (init_p == 0) {
	if (RARRAY(Argv)->len > 0) {
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
	if (RARRAY(Argv)->len > 0) {
	    filename = ary_shift(Argv);
	    fn = RSTRING(filename)->ptr;
	    if (RSTRING(filename)->len == 1 && fn[0] == '-') {
		file = rb_stdin;
		if (inplace) {
		    rb_defout = rb_stdout;
		}
	    }
	    else {
		FILE *fr = fopen(fn, "r");

		if (!fr) rb_sys_fail(fn);
		if (inplace) {
		    struct stat st, st2;
		    VALUE str;
		    FILE *fw;

		    if (rb_defout != rb_stdout) {
			io_close(rb_defout);
		    }
		    fstat(fileno(fr), &st);
		    if (*inplace) {
			str = str_new2(fn);
#ifdef NT
			add_suffix(str, inplace);
#else
			str_cat(str, inplace, strlen(inplace));
#endif
			if (rename(fn, RSTRING(str)->ptr) < 0) {
			    Warning("Can't rename %s to %s: %s, skipping file",
				    fn, RSTRING(str)->ptr, strerror(errno));
			    fclose(fr);
			    goto retry;
			}
		    }
		    else if (unlink(fn) < 0) {
			Warning("Can't remove %s: %s, skipping file",
				fn, strerror(errno));
			fclose(fr);
			goto retry;
		    }
		    fw = fopen(fn, "w");
		    fstat(fileno(fw), &st2);
		    fchmod(fileno(fw), st.st_mode);
		    if (st.st_uid!=st2.st_uid || st.st_gid!=st2.st_gid) {
			fchown(fileno(fw), st.st_uid, st.st_gid);
		    }
		    rb_defout = prep_stdio(fw, FMODE_WRITABLE);
		}
		file = prep_stdio(fr, FMODE_READABLE);
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
f_gets()
{
    VALUE line;

  retry:
    if (!next_argv()) return Qnil;
    line = io_gets(file);
    if (line == Qnil && next_p != -1) {
	io_close(file);
	next_p = 1;
	goto retry;
    }

    gets_lineno++;
    lineno = INT2FIX(gets_lineno);

    return line;
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
f_readlines(obj)
    VALUE obj;
{
    VALUE line, ary;

    ary = ary_new();
    while (line = f_gets(obj)) {
	ary_push(ary, line);
    }

    return ary;
}

VALUE
rb_str_setter(val, id, var)
    VALUE val;
    ID id;
    VALUE *var;
{
    if (val && TYPE(val) != T_STRING) {
	Fail("value of %s must be String", rb_id2name(id));
    }
    return *var = val;
}

VALUE
rb_xstring(str)
    struct RString *str;
{
    VALUE port, result;
    OpenFile *fptr;

    Check_Type(str, T_STRING);
    port = pipe_open(str->ptr, "r");
    result = read_all(port);

    io_close(port);

    return result;
}

struct timeval *time_timeval();

#ifdef _STDIO_USES_IOSTREAM  /* GNU libc */
#  ifdef _IO_fpos_t
#    define READ_DATA_PENDING(fp) ((fp)->_IO_read_ptr < (fp)->_IO_read_end)
#  else
#    define READ_DATA_PENDING(fp) ((fp)->_gptr < (fp)->_egptr)
#  endif
#else
#  ifdef FILE_COUNT
#    define READ_DATA_PENDING(fp) ((fp)->FILE_COUNT > 0)
#  else
extern int ReadDataPending();
#    define READ_DATA_PENDING(fp) ReadDataPending(fp)
#  endif
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
    int interrupt = 0;

    rb_scan_args(argc, argv, "13", &read, &write, &except, &timeout);
    if (timeout) {
	tp = time_timeval(timeout);
    }
    else {
	tp = NULL;
    }

    FD_ZERO(&pset);
    if (read) {
	int pending = 0;

	Check_Type(read, T_ARRAY);
	rp = &rset;
	FD_ZERO(rp);
	for (i=0; i<RARRAY(read)->len; i++) {
	    GetOpenFile(RARRAY(read)->ptr[i], fptr);
	    FD_SET(fileno(fptr->f), rp);
	    if (READ_DATA_PENDING(fptr->f)) { /* check for buffered data */
		pending++;
		FD_SET(fileno(fptr->f), &pset);
	    }
	    if (max < (int)fileno(fptr->f)) max = fileno(fptr->f);
	}
	if (pending) {		/* no blocking if there's buffered data */
	    timerec.tv_sec = timerec.tv_usec = 0;
	    tp = &timerec;
	}
    }
    else
	rp = NULL;

    if (write) {
	Check_Type(write, T_ARRAY);
	wp = &wset;
	FD_ZERO(wp);
	for (i=0; i<RARRAY(write)->len; i++) {
	    GetOpenFile(RARRAY(write)->ptr[i], fptr);
	    FD_SET(fileno(fptr->f), wp);
	    if (max > (int)fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), wp);
		if (max < (int)fileno(fptr->f2)) max = fileno(fptr->f2);
	    }
	}
    }
    else
	wp = NULL;

    if (except) {
	Check_Type(except, T_ARRAY);
	ep = &eset;
	FD_ZERO(ep);
	for (i=0; i<RARRAY(except)->len; i++) {
	    GetOpenFile(RARRAY(except)->ptr[i], fptr);
	    FD_SET(fileno(fptr->f), ep);
	    if (max < (int)fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), ep);
		if (max > (int)fileno(fptr->f2)) max = fileno(fptr->f2);
	    }
	}
    }
    else
	ep = NULL;

    max++;

  retry:
    TRAP_BEG;
    n = select(max, rp, wp, ep, tp);
    TRAP_END;
    if (n < 0) {
	if (errno != EINTR) {
	    rb_sys_fail(Qnil);
	}
	if (tp == NULL) goto retry;
	interrupt = 1;
    }

    res = ary_new2(3);
    ary_push(res, rp?ary_new():ary_new2(0));
    ary_push(res, wp?ary_new():ary_new2(0));
    ary_push(res, ep?ary_new():ary_new2(0));

    if (interrupt == 0) {

	if (rp) {
	    list = RARRAY(res)->ptr[0];
	    for (i=0; i< RARRAY(read)->len; i++) {
		GetOpenFile(RARRAY(read)->ptr[i], fptr);
		if (FD_ISSET(fileno(fptr->f), rp)
		    || FD_ISSET(fileno(fptr->f), &pset)) {
		    ary_push(list, RARRAY(read)->ptr[i]);
		}
	    }
	}

	if (wp) {
	    list = RARRAY(res)->ptr[1];
	    for (i=0; i< RARRAY(write)->len; i++) {
		GetOpenFile(RARRAY(write)->ptr[i], fptr);
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
		GetOpenFile(RARRAY(except)->ptr[i], fptr);
		if (FD_ISSET(fileno(fptr->f), ep)) {
		    ary_push(list, RARRAY(except)->ptr[i]);
		}
		else if (fptr->f2 && FD_ISSET(fileno(fptr->f2), ep)) {
		    ary_push(list, RARRAY(except)->ptr[i]);
		}
	    }
	}
    }

    return res;
}

void
io_ctl(obj, req, arg, io_p)
    VALUE obj, req;
    struct RString *arg;
    int io_p;
{
    int cmd = NUM2INT(req);
    OpenFile *fptr;
    int len, fd;

    GetOpenFile(obj, fptr);

#ifdef IOCPARM_MASK
#ifndef IOCPARM_LEN
#define IOCPARM_LEN(x)  (((x) >> 16) & IOCPARM_MASK)
#endif
#endif
#ifdef IOCPARM_LEN
    len = IOCPARM_LEN(cmd);	/* on BSDish systems we're safe */
#else
    len = 256;			/* otherwise guess at what's safe */
#endif

    Check_Type(arg, T_STRING);
    str_modify(arg);

    if (arg->len < len) {
	str_grow(arg, len+1);
    }
    arg->ptr[len] = 17;
    fd = fileno(fptr->f);
#ifdef HAVE_FCNTL
    if ((io_p?ioctl(fd, cmd, arg->ptr):fcntl(fd, cmd, arg->ptr))<0) {
	rb_sys_fail(fptr->path);
    }
#else
    if (!io_p) {
	Bug("fcntl() not implemented");
    }
    if (ioctl(fd, cmd, arg->ptr)<0) rb_sys_fail(fptr->path);
#endif
    if (arg->ptr[len] != 17) {
	Fail("Return value overflowed string");
    }
}

static VALUE
io_ioctl(obj, req, arg)
    VALUE obj, req;
    struct RString *arg;
{
    io_ctl(obj, req, arg, 1);
    return obj;
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
    int i = 0;
    int items = argc - 1;

    /* This probably won't work on machines where sizeof(long) != sizeof(int)
     * or where sizeof(long) != sizeof(char*).  But such machines will
     * not likely have syscall implemented either, so who cares?
     */

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
    switch (argc) {
      case 0:
	Fail("Too few args to syscall");
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
    if (retval == -1) rb_sys_fail(0);
    return INT2FIX(0);
#else
    Fail("syscall() unimplemented");
#endif
}

static VALUE
arg_read(obj)
    VALUE obj;
{
    VALUE str, str2;

    str = str_new(0, 0);
    for (;;) {
      retry:
	if (!next_argv()) return Qnil;
	str2 = io_read(0, Qnil, file);
	if (str2 == Qnil && next_p != -1) {
	    io_close(file);
	    next_p = 1;
	    goto retry;
	}
	if (str2 == Qnil) break;
	str_cat(str, RSTRING(str2)->ptr, RSTRING(str2)->len);
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
    if (byte == Qnil && next_p != -1) {
	io_close(file);
	next_p = 1;
	goto retry;
    }

    return byte;
}

static VALUE
arg_each_line()
{
    VALUE str;

    while (str = f_gets()) {
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
arg_each_byte()
{
    VALUE byte;

    while (byte = arg_getc()) {
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

extern VALUE mEnumerable;

void
Init_IO()
{
    extern VALUE cKernel;

    id_write = rb_intern("write");
    id_fd = rb_intern("fd");
    id_print_on = rb_intern("print_on");

    rb_define_private_method(cKernel, "syscall", f_syscall, -1);

    rb_define_private_method(cKernel, "open", f_open, -1);
    rb_define_private_method(cKernel, "printf", f_printf, -1);
    rb_define_private_method(cKernel, "print", f_print, -1);
    rb_define_private_method(cKernel, "gets", f_gets, 0);
    rb_define_alias(cKernel,"readline", "gets");
    rb_define_private_method(cKernel, "eof", f_eof, 0);
    rb_define_private_method(cKernel, "getc", f_getc, 0);
    rb_define_private_method(cKernel, "select", f_select, -1);

    rb_define_private_method(cKernel, "readlines", f_readlines, 0);

    rb_define_method(cKernel, "print_on", f_print_on, 1);

    cIO = rb_define_class("IO", cObject);
    rb_include_module(cIO, mEnumerable);

    rb_define_hooked_variable("$;", &FS, 0, rb_str_setter);
    rb_define_hooked_variable("$,", &OFS, 0, rb_str_setter);

    RS = str_new2("\n");
    rb_define_hooked_variable("$/", &RS, 0, rb_str_setter);
    rb_define_hooked_variable("$\\", &ORS, 0, rb_str_setter);

    rb_define_variable("$.", &lineno);
    rb_define_variable("$_", &rb_lastline);

    rb_define_method(cIO, "print", io_print, -1);

    rb_define_method(cIO, "each",  io_each_line, 0);
    rb_define_method(cIO, "each_line",  io_each_line, 0);
    rb_define_method(cIO, "each_byte",  io_each_byte, 0);

    rb_define_method(cIO, "syswrite", io_syswrite, 1);
    rb_define_method(cIO, "sysread",  io_sysread, 1);

    rb_define_method(cIO, "fileno", io_fileno, 0);
    rb_define_alias(cIO, "to_i", "fileno");

    rb_define_method(cIO, "sync",   io_sync, 0);
    rb_define_method(cIO, "sync=",  io_set_sync, 1);

    rb_define_alias(cIO, "readlines", "to_a");

    rb_define_method(cIO, "read",  io_read, -2);
    rb_define_method(cIO, "write", io_write, 1);
    rb_define_method(cIO, "gets",  io_gets, 0);
    rb_define_alias(cIO,  "readline", "gets");
    rb_define_method(cIO, "getc",  io_getc, 0);
    rb_define_method(cIO, "puts",  io_puts, 1);
    rb_define_method(cIO, "<<",    io_puts, 1);
    rb_define_method(cIO, "flush", io_flush, 0);
    rb_define_method(cIO, "eof", io_eof, 0);

    rb_define_method(cIO, "close", io_close, 0);
    rb_define_method(cIO, "closed?", io_closed, 0);

    rb_define_method(cIO, "isatty", io_isatty, 0);
    rb_define_method(cIO, "tty?", io_isatty, 0);
    rb_define_method(cIO, "binmode",  io_binmode, 0);

    rb_define_method(cIO, "ioctl", io_ioctl, 2);

    rb_stdin = prep_stdio(stdin, FMODE_READABLE);
    rb_define_readonly_variable("$stdin", &rb_stdin);
    rb_stdout = prep_stdio(stdout, FMODE_WRITABLE);
    rb_define_readonly_variable("$stdout", &rb_stdout);
    rb_stderr = prep_stdio(stderr, FMODE_WRITABLE);
    rb_define_readonly_variable("$stderr", &rb_stderr);
    rb_defout = rb_stdout;
    rb_define_hooked_variable("$>", &rb_defout, 0, io_defset);

    rb_define_const(cObject, "STDIN", rb_stdin);
    rb_define_const(cObject, "STDOUT", rb_stdout);
    rb_define_const(cObject, "STDERR", rb_stderr);

    argf = obj_alloc(cObject);
    rb_extend_object(argf, mEnumerable);

    rb_define_readonly_variable("$<", &argf);
    rb_define_readonly_variable("$ARGF", &argf);

    rb_define_singleton_method(argf, "each",  arg_each_line, 0);
    rb_define_singleton_method(argf, "each_line",  arg_each_line, 0);
    rb_define_singleton_method(argf, "each_byte",  arg_each_byte, 0);

    rb_define_singleton_method(argf, "read",  arg_read, 0);
    rb_define_singleton_method(argf, "readlines", f_readlines, 0);
    rb_define_singleton_method(argf, "gets", f_gets, 0);
    rb_define_singleton_method(argf, "readline", f_gets, 0);
    rb_define_singleton_method(argf, "getc", arg_getc, 0);
    rb_define_singleton_method(argf, "eof", f_eof, 0);
    rb_define_singleton_method(argf, "eof?", f_eof, 0);

    rb_define_singleton_method(argf, "to_s", arg_filename, 0);
    rb_define_singleton_method(argf, "filename", arg_filename, 0);
    rb_define_singleton_method(argf, "file", arg_file, 0);

    filename = str_new2("-");
    rb_define_readonly_variable("$FILENAME", &filename);
    file = rb_stdin;
    rb_global_variable(&file);

    Init_File();
}
