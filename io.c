/************************************************

  io.c -

  $Author: matz $
  $Date: 1994/06/27 15:48:29 $
  created at: Fri Oct 15 18:08:59 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "io.h"
#include <ctype.h>
#include <errno.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>

VALUE rb_ad_string();

VALUE C_IO;
extern VALUE C_File;

VALUE rb_stdin, rb_stdout, rb_stderr, rb_defout;

VALUE FS, OFS;
VALUE RS, ORS;

ID id_write;

extern char *inplace;

/* writing functions */
static VALUE
Fio_write(obj, str)
    VALUE obj;
    struct RString *str;
{
    OpenFile *fptr;
    FILE *f;
    VALUE out;
    int n;

    if (TYPE(str) != T_STRING)
	str = (struct RString*)obj_as_string(str);

    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	Fail("not opened for writing");
    }

    f = (fptr->f2) ? fptr->f2 : fptr->f;
    if (f == NULL) Fail("closed stream");

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
Fio_puts(obj, str)
    VALUE obj, str;
{
    Fio_write(obj, str);
    return obj;
}

static VALUE
Fio_flush(obj)
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
Fio_eof(obj)
    VALUE obj;
{
    OpenFile *fptr;
    int ch;

    GetOpenFile(obj, fptr);
#ifdef STDSTDIO			/* (the code works without this) */
    if (fptr->f->_cnt > 0)	/* cheat a little, since */
	return FALSE;		/* this is the most usual case */
#endif

    ch = getc(fptr->f);
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
Fio_sync(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    return (fptr->mode & FMODE_SYNC) ? TRUE : FALSE;
}

static VALUE
Fio_set_sync(obj, mode)
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
Fio_fileno(obj)
    VALUE obj;
{
    OpenFile *fptr;
    int f;

    GetOpenFile(obj, fptr);
    f = fileno(fptr->f);
    return INT2FIX(f);
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

    GC_LINK;
    GC_PRO3(str, str_new(0, 0));

    for (;;) {
	n = fread(buf, 1, BUFSIZ, fptr->f);
	if (n == 0) {
	    if (feof(fptr->f)) break;
	    rb_sys_fail(Qnil);
	}
	str_cat(str, buf, n);
    }

    GC_UNLINK;
    return str;
}

static VALUE
Fio_read(obj, args)
    VALUE obj, args;
{
    OpenFile *fptr;
    int n, lgt;
    VALUE len, str;

    if (rb_scan_args(args, "01", &len) == 0) {
	return read_all(obj);
    }

    lgt = NUM2INT(len);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_READABLE)) {
	Fail("not opend for reading");
    }
    if (fptr->f == NULL) Fail("closed stream");

    str = str_new(0, lgt);

    n = fread(RSTRING(str)->ptr, 1, RSTRING(str)->len, fptr->f);
    if (n == 0) {
	if (feof(fptr->f)) return Qnil;
	rb_sys_fail(Qnil);
    }

    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';

    return str;
}

static void
io_gets(str)
    VALUE str;
{
    rb_break();
}

void rb_each();

VALUE rb_lastline;
static VALUE lineno;

static VALUE
Fio_gets(obj)
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

    GC_LINK;
    GC_PRO2(str);

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

    if (rslen == 0 && c == '\n') {
	do {
	    c = getc(f);
	    if (c != '\n') {
		ungetc(c,f);
		break;
	    }
	} while (c != EOF);
    }

    {
	char buf[8192];
	char *bp, *bpe = buf + sizeof buf - 3;
	char *ptr;
	int append = 0;

      again:
	bp = buf;
	while ((c = getc(f)) != EOF && (*bp++ = c) != newline && bp < bpe)
	    ;

	if (c == EOF && !append && bp == buf) {
	    str = Qnil;
	    goto return_gets;
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
    if (rslen == 0 && c == '\n') {
	while (c != EOF) {
	    c = getc(f);
	    if (c != '\n') {
		ungetc(c, f);
		break;
	    }
	}
    }

    GC_UNLINK;

    if (str) {
	fptr->lineno++;
	lineno = INT2FIX(fptr->lineno);
	return rb_lastline = (VALUE)str;
    }
    return Qnil;
}

static VALUE
Fio_each(obj)
    VALUE obj;
{
    VALUE str;

    GC_PRO2(str);
    while (str = Fio_gets(obj)) {
	rb_yield(str);
    }
    return Qnil;
}

static VALUE
Fio_each_byte(obj)
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

    while ((c = getc(f)) != EOF) {
	rb_yield(INT2FIX(c & 0xff));
    }
    if (ferror(f) != 0) rb_sys_fail(Qnil);
    return obj;
}

static VALUE
Fio_getc(obj)
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

    c = getc(f);
    if (c == EOF) {
	if (ferror(f) != 0) rb_sys_fail(Qnil);
	return Qnil;
    }
    return INT2FIX(c & 0xff);
}

static VALUE
Fio_isatty(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (fptr->f == NULL) Fail("closed stream");
    if (isatty(fileno(fptr->f)) == 0)
	return FALSE;

    return TRUE;
}

static VALUE
Fio_close(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);

    if (fptr->f2 != NULL) {
	fclose(fptr->f2);
    }
    if (fptr->f != NULL) {
	fclose(fptr->f);
    }
    fptr->f = fptr->f2 = NULL;
    if (fptr->pid) {
	rb_syswait(fptr->pid);
	fptr->pid = 0;
    }
    return Qnil;
}

static VALUE
Fio_syswrite(obj, str)
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
Fio_sysread(obj, len)
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

    n = read(fileno(fptr->f), RSTRING(str)->ptr, RSTRING(str)->len);

    if (n == -1) rb_sys_fail(Qnil);
    if (n == 0) return Qnil;	/* EOF */

    RSTRING(str)->len = n;
    RSTRING(str)->ptr[n] = '\0';
    return str;
}

void
io_free_OpenFile(fptr)
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
    }
    if (fptr->pid) {
	rb_syswait(fptr->pid);
    }
}

static VALUE
Fio_binmode(obj)
    VALUE obj;
{
#ifdef MSDOS
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (setmode(fileno(fptr), O_BINARY) == -1)
	rb_sys_fail(Qnil);
#endif
    return obj;
}

VALUE obj_alloc();

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
	if (errno = EMFILE) {
	    gc();
	    f = fdopen(fd, mode);
	}
	if (f == NULL) {
	    rb_sys_fail(Qnil);
	}
    }
    return f;
}

static VALUE
pipe_open(pname, mode)
    char *pname, *mode;
{
    VALUE port;
    OpenFile *fptr;

    int pid, pr[2], pw[2];
    int doexec;

    GC_LINK;
    GC_PRO3(port, obj_alloc(C_IO));

    MakeOpenFile(port, fptr);
    fptr->mode = io_mode_flags(mode);

    if ((fptr->mode & FMODE_READABLE) && pipe(pr) == -1 ||
	(fptr->mode & FMODE_WRITABLE) && pipe(pw) == -1)
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
	if (fptr->mode & FMODE_READABLE) {
	    close(pr[0]);
	    dup2(pr[1], 1);
	    close(pr[1]);
	}
	if (fptr->mode & FMODE_WRITABLE) {
	    close(pw[1]);
	    dup2(pw[0], 0);
	    close(pw[0]);
	}

	if (doexec) {
	    rb_proc_exec(pname);
	    _exit(127);
	}
	return Qnil;

      case -1:			/* fork failed */
	if (errno == EAGAIN) {
	    sleep(5);
	    goto retry;
	}
	break;

      default:			/* parent */
	if (fptr->mode & FMODE_READABLE) close(pr[1]);
	if (fptr->mode & FMODE_WRITABLE) close(pw[0]);
    }
    if (pid == -1) {
	close(pr[0]); close(pw[1]);
	rb_sys_fail(Qnil);
    }

    fptr->pid = pid;
    if (fptr->mode & FMODE_READABLE) fptr->f  = rb_fdopen(pr[0], "r");
    if (fptr->mode & FMODE_WRITABLE) fptr->f2 = rb_fdopen(pw[1], "w");

    GC_UNLINK;

    return port;
}

static VALUE
Fopen(self, args)
    VALUE self, args;
{
    char *mode;
    VALUE port;
    int pipe = 0;
    VALUE pname, pmode;

    rb_scan_args(args, "11", &pname, &pmode);
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

    if (RSTRING(pname)->ptr[0] == '|') {
	port = pipe_open(RSTRING(pname)->ptr+1, mode);
    }
    else {
	port = file_open(RSTRING(pname)->ptr, mode);
    }

    return port;
}

static VALUE
Fprintf(argc, argv)
    int argc;
    VALUE argv[];
{
    VALUE out, str;

    if (argc == 1) return Qnil;
    if (TYPE(argv[1]) == T_STRING) {
	out = rb_defout;
    }
    else if (rb_get_method_body(CLASS_OF(argv[1]), id_write, 0, MTH_FUNC)) {
	out = argv[1];
	argv++;
	argc--;
    }
    else {
	Fail("output must responds to `write'");
    }

    GC_LINK;
    GC_PRO3(str, Fsprintf(argc, argv));

    rb_funcall(out, id_write, 1, str);

    GC_UNLINK;

    return Qnil;
}

static void
obj_print(obj)
    VALUE obj;
{
    int i;

    Fio_write(rb_defout, obj);
}

static VALUE
Fprint(argc, argv)
    int argc;
    VALUE argv[];
{
    int i;

    /* if no argument given, print recv */
    if (argc == 1) {
	obj_print(argv[0]);
    }
    else {
	for (i=1; i<argc; i++) {
	    obj_print(argv[i]);
	    if (OFS && i>1) {
		obj_print(OFS);
	    }
	}
    }
    if (ORS) {
	obj_print(ORS);
    }

    return Qnil;
}

static VALUE
prep_stdio(f, mode)
    FILE *f;
    int mode;
{
    VALUE obj = obj_alloc(C_IO);
    OpenFile *fp;

    GC_LINK;
    GC_PRO(obj);
    MakeOpenFile(obj, fp);
    fp->f = f;
    fp->mode = mode;
    GC_UNLINK;

    return obj;
}

static VALUE filename = Qnil, file = Qnil;
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
	    filename = Fary_shift(Argv);
	    fn = RSTRING(filename)->ptr; 
	    if (RSTRING(filename)->len == 1 && fn[0] == '-') {
		file = rb_stdin;
		if (inplace) {
		    rb_defout = rb_stdout;
		}
	    }
	    else {
		FILE *fr = fopen(fn, "r");

		if (inplace) {
		    struct stat st, st2;
		    VALUE str;
		    FILE *fw;

		    if (!*inplace) {
			Fatal("Can't do inplace edit without backup");
		    }
		    if (rb_defout != rb_stdout) {
			Fio_close(rb_defout);
		    }
		    fstat(fileno(fr), &st);
		    str = str_new2(fn);
		    str_cat(str, inplace, strlen(inplace));
		    if (rename(fn, RSTRING(str)->ptr) < 0) {
			Warning("Can't rename %s to %s: %s, skipping file",
				fn, RSTRING(str)->ptr, strerror(errno));
			fclose(fr);
			goto retry;
		    }
		    obj_free(str);
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
Fgets(obj)
    VALUE obj;
{
    VALUE line;

  retry:
    if (!next_argv()) return Qnil;
    line = Fio_gets(file);
    if (line == Qnil && next_p != -1) {
	Fio_close(file);
	next_p = 1;
	goto retry;
    }

    gets_lineno++;
    lineno = INT2FIX(gets_lineno);

    return line;
}

static VALUE
Feof(obj)
    VALUE obj;
{
    if (init_p == 0 && !next_argv())
	return TRUE;
    if (Fio_eof(file)) {
	next_p = 1;
	return TRUE;
    }
    return FALSE;
}

static VALUE
Fgetc(obj)
    VALUE obj;
{
    return Fio_getc(rb_stdin);
}

static VALUE
Freadlines(obj)
    VALUE obj;
{
    VALUE line, ary;

    GC_LINK;
    GC_PRO2(line);
    GC_PRO3(ary, ary_new());

    while (line = Fgets(obj)) {
	Fary_push(ary, line);
    }

    GC_UNLINK;
    return ary;
}

VALUE
rb_check_str(val, id)
    VALUE val;
    ID id;
{
    if (val == Qnil) return TRUE;
    if (TYPE(val) != T_STRING) {
	Fail("value of %s must be String", rb_id2name(id));
    }
    return TRUE;
}

static VALUE
Fsystem2(obj, str)
    VALUE obj;
    struct RString *str;
{
    VALUE port, result;
    OpenFile *fptr;
    int mask;

    Check_Type(str, T_STRING);
    GC_LINK;
    GC_PRO3(port, pipe_open(str->ptr, "r"));
    GC_PRO2(result);

    result = read_all(port);

    GetOpenFile(port, fptr);
    rb_syswait(fptr->pid);
    fptr->pid = 0;

    obj_free(port);
    GC_UNLINK;

    return result;
}

struct timeval *time_timeval();

#ifdef __linux__
#   define READ_PENDING(fp) ((fp)->_gptr < (fp)->_egptr > 0)
#else
# ifdef __SLBF
#   define READ_PENDING(fp) ((fp)->_r > 0)
# else
#   define READ_PENDING(fp) ((fp)->_cnt != 0)
# endif
#endif

static VALUE
Fselect(obj, args)
    VALUE obj, args;
{
    VALUE read, write, except, timeout, res, list;
    fd_set rset, wset, eset, pset;
    fd_set *rp, *wp, *ep;
    struct timeval time, *tp, timerec;
    OpenFile *fptr;
    int i, max = 0, n;
    int interrupt = 0;

    rb_scan_args(args, "13", &read, &write, &except, &timeout);
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
	    if (READ_PENDING(fptr->f)) { /* check for buffered data */
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

    if (write) {
	Check_Type(write, T_ARRAY);
	wp = &wset;
	FD_ZERO(wp);
	for (i=0; i<RARRAY(write)->len; i++) {
	    GetOpenFile(RARRAY(write)->ptr[i], fptr);
	    FD_SET(fileno(fptr->f), wp);
	    if (max > fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), wp);	
		if (max < fileno(fptr->f2)) max = fileno(fptr->f2);
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
	    if (max < fileno(fptr->f)) max = fileno(fptr->f);
	    if (fptr->f2) {
		FD_SET(fileno(fptr->f2), ep);	
		if (max > fileno(fptr->f2)) max = fileno(fptr->f2);
	    }
	}
    }
    else
	ep = NULL;

    max++;

  retry:
    if ((n = select(max, rp, wp, ep, tp)) < 0) {
	if (errno == EINTR) {
	    if (tp == NULL) goto retry;
	    interrupt = 1;
	}
	rb_sys_fail(Qnil);
    }
    if (n == 0) return Qnil;

    GC_LINK;
    GC_PRO3(res, ary_new2(3));
    RARRAY(res)->ptr[0] = rp?ary_new():Qnil;
    RARRAY(res)->len++;
    RARRAY(res)->ptr[1] = wp?ary_new():Qnil;
    RARRAY(res)->len++;
    RARRAY(res)->ptr[2] = ep?ary_new():Qnil;
    RARRAY(res)->len++;

    if (interrupt == 0) {

	if (rp) {
	    list = RARRAY(res)->ptr[0];
	    for (i=0; i< RARRAY(read)->len; i++) {
		GetOpenFile(RARRAY(read)->ptr[i], fptr);
		if (FD_ISSET(fileno(fptr->f), rp)
		    || FD_ISSET(fileno(fptr->f), &pset)) {
		    Fary_push(list, RARRAY(read)->ptr[i]);
		}
	    }
	}

	if (wp) {
	    list = RARRAY(res)->ptr[1];
	    for (i=0; i< RARRAY(write)->len; i++) {
		GetOpenFile(RARRAY(write)->ptr[i], fptr);
		if (FD_ISSET(fileno(fptr->f), rp)) {
		    Fary_push(list, RARRAY(write)->ptr[i]);
		}
		else if (fptr->f2 && FD_ISSET(fileno(fptr->f2), rp)) {
		    Fary_push(list, RARRAY(write)->ptr[i]);
		}
	    }
	}

	if (ep) {
	    list = RARRAY(res)->ptr[2];
	    for (i=0; i< RARRAY(except)->len; i++) {
		GetOpenFile(RARRAY(except)->ptr[i], fptr);
		if (FD_ISSET(fileno(fptr->f), rp)) {
		    Fary_push(list, RARRAY(except)->ptr[i]);
		}
		else if (fptr->f2 && FD_ISSET(fileno(fptr->f2), rp)) {
		    Fary_push(list, RARRAY(except)->ptr[i]);
		}
	    }
	}
    }

    GC_UNLINK;
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
    len = IOCPARM_LEN(cmd);	/* on BSDish systes we're safe */
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
    if (io_p?ioctl(fd, cmd, arg->ptr):fcntl(fd, cmd, arg->ptr)<0) {
	rb_sys_fail(fptr->path);
    }
    if (arg->ptr[len] != 17) {
	Fail("Return value overflowed string");
    }
}

static VALUE
Fio_ioctl(obj, req, arg)
    VALUE obj, req;
    struct RString *arg;
{
    io_ctl(obj, req, arg, 1);
    return obj;
}

static VALUE
Fio_defget(obj)
    VALUE obj;
{
    return rb_defout;
}

static VALUE
Fio_defset(obj, val)
    VALUE obj, val;
{
    return rb_defout = val;
}

extern VALUE M_Enumerable;
VALUE rb_readonly_hook();

Init_IO()
{
    extern VALUE C_Kernel;

    rb_define_func(C_Kernel, "open", Fopen, -2);
    rb_define_func(C_Kernel, "printf", Fprintf, -1);
    rb_define_method(C_Kernel, "print", Fprint, -1);
    rb_define_func(C_Kernel, "gets", Fgets, 0);
    rb_define_func(C_Kernel, "eof", Feof, 0);
    rb_define_alias(C_Kernel,"readline", "gets");
    rb_define_func(C_Kernel, "getc", Fgetc, 0);
    rb_define_func(C_Kernel, "system2", Fsystem2, 1);
    rb_define_func(C_Kernel, "select", Fselect, -2);

    rb_define_func(C_Kernel, "readlines", Freadlines, 0);

    C_IO = rb_define_class("IO", C_Object);
    rb_include_module(C_IO, M_Enumerable);

    rb_define_variable("$;", &FS,  Qnil, rb_check_str);
    rb_define_variable("$,", &OFS, Qnil, rb_check_str);

    RS = str_new2("\n");
    rb_define_variable("$/",  &RS, Qnil, rb_check_str);
    rb_define_variable("$\\", &ORS, Qnil, rb_check_str);

    rb_define_variable("$FILENAME", &filename, Qnil, rb_readonly_hook);
    rb_global_variable(&file);

    rb_define_variable("$.", &lineno, Qnil, Qnil);
    rb_define_variable("$_", &rb_lastline, Qnil, Qnil);

    rb_define_method(C_IO, "each",  Fio_each, 0);
    rb_define_method(C_IO, "each_byte",  Fio_each_byte, 0);

    rb_define_method(C_IO, "syswrite", Fio_syswrite, 1);
    rb_define_method(C_IO, "sysread",  Fio_sysread, 1);

    rb_define_method(C_IO, "fileno", Fio_fileno, 0);
    rb_define_method(C_IO, "sync",  Fio_sync, 0);
    rb_define_method(C_IO, "sync=",  Fio_set_sync, 1);

    rb_define_alias(C_IO, "readlines", "to_a");

    rb_define_method(C_IO, "read",  Fio_read, -2);
    rb_define_method(C_IO, "write", Fio_write, 1);
    rb_define_method(C_IO, "gets",  Fio_gets, 0);
    rb_define_alias(C_IO,  "readlines", "gets");
    rb_define_method(C_IO, "getc",  Fio_getc, 0);
    rb_define_method(C_IO, "puts",  Fio_puts, 1);
    rb_define_method(C_IO, "<<",    Fio_puts, 1);
    rb_define_method(C_IO, "flush", Fio_flush, 0);
    rb_define_method(C_IO, "eof", Fio_eof, 0);

    rb_define_method(C_IO, "close", Fio_close, 0);

    rb_define_method(C_IO, "isatty", Fio_isatty, 0);
    rb_define_method(C_IO, "binmode",  Fio_binmode, 0);

    rb_define_method(C_IO, "ioctl", Fio_ioctl, 2);

    rb_stdin = prep_stdio(stdin, FMODE_READABLE);
    rb_define_variable("$stdin",  &rb_stdin, Qnil, rb_readonly_hook);
    rb_stdout = prep_stdio(stdout, FMODE_WRITABLE);
    rb_define_variable("$stdout", &rb_stdout, Qnil, rb_readonly_hook);
    rb_stderr = prep_stdio(stderr, FMODE_WRITABLE);
    rb_define_variable("$stderr", &rb_stderr, Qnil, rb_readonly_hook);
    rb_defout = rb_stdout;
    rb_global_variable(&rb_defout);
    rb_define_single_method(C_IO, "default", Fio_defget, 0);
    rb_define_single_method(C_IO, "default=", Fio_defset, 1);

    id_write = rb_intern("write");
    Init_File();
}
