/************************************************

  file.c -

  $Author$
  $Date$
  created at: Mon Nov 15 12:24:34 JST 1993

  Copyright (C) 1993-1998 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "io.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#else
# define MAXPATHLEN 1024
#endif

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#else
#ifndef NT
struct timeval {
        long    tv_sec;         /* seconds */
        long    tv_usec;        /* and microseconds */
};
#endif /* NT */
#endif

#ifdef HAVE_UTIME_H
#include <utime.h>
#endif

#ifdef HAVE_PWD_H
#include <pwd.h>
#endif

#ifndef HAVE_STRING_H
char *strrchr();
#endif

#include <sys/types.h>
#include <sys/stat.h>

#ifndef NT
char *strdup();
char *getenv();
#endif

extern VALUE cIO;
VALUE cFile;
VALUE mFileTest;
static VALUE sStat;

VALUE time_new();

VALUE
file_open(fname, mode)
    char *fname, *mode;
{
    OpenFile *fptr;
    NEWOBJ(port, struct RFile);
    OBJSETUP(port, cFile, T_FILE);
    MakeOpenFile(port, fptr);

    fptr->mode = io_mode_flags(mode);
    fptr->f = rb_fopen(fname, mode);
    fptr->path = strdup(fname);
    obj_call_init((VALUE)port);

    return (VALUE)port;
}

static VALUE
file_s_open(argc, argv, klass)
    int argc;
    VALUE *argv;
    VALUE klass;
{
    VALUE fname, vmode, file;
    char *mode;

    rb_scan_args(argc, argv, "11", &fname, &vmode);
    Check_SafeStr(fname);
    if (!NIL_P(vmode)) {
	Check_Type(vmode, T_STRING);
	mode = RSTRING(vmode)->ptr;
    }
    else {
	mode = "r";
    }
    file = file_open(RSTRING(fname)->ptr, mode);

    RBASIC(file)->klass = klass;
    if (iterator_p()) {
	rb_ensure(rb_yield, file, io_close, file);
    }
    obj_call_init(file);

    return file;
}

static VALUE
file_reopen(argc, argv, file)
    int argc;
    VALUE *argv;
    VALUE file;
{
    VALUE fname, nmode;
    char *mode;
    OpenFile *fptr;

    if (rb_scan_args(argc, argv, "11", &fname, &nmode) == 1) {
	if (TYPE(fname) == T_FILE) { /* fname must be IO */
	    return io_reopen(file, fname);
	}
    }

    Check_SafeStr(fname);
    if (!NIL_P(nmode)) {
	Check_Type(nmode, T_STRING);
	mode = RSTRING(nmode)->ptr;
    }
    else {
	mode = "r";
    }

    GetOpenFile(file, fptr);
    if (fptr->path) free(fptr->path);
    fptr->path = strdup(RSTRING(fname)->ptr);
    fptr->mode = io_mode_flags(mode);
    if (!fptr->f) {
	fptr->f = rb_fopen(RSTRING(fname)->ptr, mode);
	if (fptr->f2) {
	    fclose(fptr->f2);
	    fptr->f2 = NULL;
	}
	return file;
    }

    if (freopen(RSTRING(fname)->ptr, mode, fptr->f) == NULL) {
	rb_sys_fail(fptr->path);
    }
    if (fptr->f2) {
	if (freopen(RSTRING(fname)->ptr, "w", fptr->f2) == NULL) {
	    rb_sys_fail(fptr->path);
	}
    }

    return file;
}

static int
apply2files(func, vargs, arg)
    int (*func)();
    VALUE vargs;
    void *arg;
{
    int i;
    VALUE path;
    struct RArray *args = RARRAY(vargs);

    for (i=0; i<args->len; i++) {
	Check_SafeStr(args->ptr[i]);
    }

    for (i=0; i<args->len; i++) {
	path = args->ptr[i];
	if ((*func)(RSTRING(path)->ptr, arg) < 0)
	    rb_sys_fail(RSTRING(path)->ptr);
    }

    return args->len;
}

static VALUE
file_tell(obj)
    VALUE obj;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(obj, fptr);
    pos = ftell(fptr->f);
    if (ferror(fptr->f) != 0) rb_sys_fail(fptr->path);

    return int2inum(pos);
}

static VALUE
file_seek(obj, offset, ptrname)
    VALUE obj, offset, ptrname;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(obj, fptr);
    pos = fseek(fptr->f, NUM2INT(offset), NUM2INT(ptrname));
    if (pos != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2FIX(0);
}

static VALUE
file_set_pos(obj, offset)
    VALUE obj, offset;
{
    OpenFile *fptr;
    long pos;

    GetOpenFile(obj, fptr);
    pos = fseek(fptr->f, NUM2INT(offset), 0);
    if (pos != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2NUM(pos);
}

static VALUE
file_rewind(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (fseek(fptr->f, 0L, 0) != 0) rb_sys_fail(fptr->path);
    clearerr(fptr->f);

    return INT2FIX(0);
}

static VALUE
file_eof(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (feof(fptr->f) == 0) return FALSE;
    return TRUE;
}

static VALUE
file_path(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (fptr->path == NULL) return Qnil;
    return str_new2(fptr->path);
}

#ifndef NT
#include <sys/file.h>
#else
#include "missing/file.h"
#endif

static VALUE
stat_new(st)
    struct stat *st;
{
    if (!st) Bug("stat_new() called with bad value");
    return struct_new(sStat,
		      INT2FIX((int)st->st_dev),
		      INT2FIX((int)st->st_ino),
		      INT2FIX((int)st->st_mode),
		      INT2FIX((int)st->st_nlink),
		      INT2FIX((int)st->st_uid),
		      INT2FIX((int)st->st_gid),
#ifdef HAVE_ST_RDEV
		      INT2FIX((int)st->st_rdev),
#else
		      INT2FIX(0),
#endif
		      INT2FIX((int)st->st_size),
#ifdef HAVE_ST_BLKSIZE
		      INT2FIX((int)st->st_blksize),
#else
		      INT2FIX(0),
#endif
#ifdef HAVE_ST_BLOCKS
		      INT2FIX((int)st->st_blocks),
#else
		      INT2FIX(0),
#endif
		      time_new(st->st_atime, 0),
		      time_new(st->st_mtime, 0),
		      time_new(st->st_ctime, 0));
}

static int
rb_stat(file, st)
    VALUE file;
    struct stat *st;
{
    OpenFile *fptr;

    switch (TYPE(file)) {
      case T_STRING:
	Check_SafeStr(file);
	return stat(RSTRING(file)->ptr, st);
	break;
      case T_FILE:
	GetOpenFile(file, fptr);
	return fstat(fileno(fptr->f), st);
	break;
      default:
	Check_Type(file, T_STRING); 
    }
    return -1;			/* not reached */
}

static VALUE
file_s_stat(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    Check_SafeStr(fname);
    if (stat(RSTRING(fname)->ptr, &st) == -1) {
	rb_sys_fail(RSTRING(fname)->ptr);
    }
    return stat_new(&st);
}

static VALUE
file_stat(obj)
    VALUE obj;
{
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return stat_new(&st);
}

static VALUE
file_s_lstat(obj, fname)
    VALUE obj, fname;
{
#if !defined(MSDOS) && !defined(NT)
    struct stat st;

    Check_SafeStr(fname);
    if (lstat(RSTRING(fname)->ptr, &st) == -1) {
	rb_sys_fail(RSTRING(fname)->ptr);
    }
    return stat_new(&st);
#else
    rb_notimplement();
#endif
}

static VALUE
file_lstat(obj)
    VALUE obj;
{
#if !defined(MSDOS) && !defined(NT) 
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (lstat(fptr->path, &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return stat_new(&st);
#else
    rb_notimplement();
#endif
}

static int
group_member(gid)
    GETGROUPS_T gid;
{
#ifndef NT
    if (getgid() ==  gid || getegid() == gid)
	return TRUE;

# ifdef HAVE_GETGROUPS
#  ifndef NGROUPS
#    define NGROUPS 32
#  endif
    {
	GETGROUPS_T gary[NGROUPS];
	int anum;

	anum = getgroups(NGROUPS, gary);
	while (--anum >= 0)
	    if (gary[anum] == gid)
		return TRUE;
    }
# endif
#endif
    return FALSE;
}

#ifndef S_IXUGO
#  define S_IXUGO		(S_IXUSR | S_IXGRP | S_IXOTH)
#endif

int
eaccess(path, mode)
     char *path;
     int mode;
{
#ifndef NT
  struct stat st;
  static int euid = -1;

  if (stat(path, &st) < 0) return (-1);

  if (euid == -1)
    euid = geteuid ();

  if (euid == 0)
    {
      /* Root can read or write any file. */
      if (mode != X_OK)
	return 0;

      /* Root can execute any file that has any one of the execute
	 bits set. */
      if (st.st_mode & S_IXUGO)
	return 0;
    }

  if (st.st_uid == euid)        /* owner */
    mode <<= 6;
  else if (group_member (st.st_gid))
    mode <<= 3;

  if (st.st_mode & mode) return 0;

  return -1;
#else  /* !NT*/
	return 0;
#endif
}

static VALUE
test_d(obj, fname)
    VALUE obj, fname;
{
#ifndef S_ISDIR
#   define S_ISDIR(m) ((m & S_IFMT) == S_IFDIR)
#endif

    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (S_ISDIR(st.st_mode)) return TRUE;
    return FALSE;
}

static VALUE
test_p(obj, fname)
    VALUE obj, fname;
{
#ifdef S_IFIFO
#  ifndef S_ISFIFO
#    define S_ISFIFO(m) ((m & S_IFMT) == S_IFIFO)
#  endif

    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (S_ISFIFO(st.st_mode)) return TRUE;

#endif
    return FALSE;
}

static VALUE
test_l(obj, fname)
    VALUE obj, fname;
{
#ifndef S_ISLNK
#  ifdef _S_ISLNK
#    define S_ISLNK(m) _S_ISLNK(m)
#  else
#    ifdef _S_IFLNK
#      define S_ISLNK(m) ((m & S_IFMT) == _S_IFLNK)
#    else
#      ifdef S_IFLNK
#	 define S_ISLNK(m) ((m & S_IFMT) == S_IFLNK)
#      endif
#    endif
#  endif
#endif

#ifdef S_ISLNK
    struct stat st;

    Check_SafeStr(fname);
    if (lstat(RSTRING(fname)->ptr, &st) < 0) return FALSE;
    if (S_ISLNK(st.st_mode)) return TRUE;

#endif
    return FALSE;
}

static VALUE
test_S(obj, fname)
    VALUE obj, fname;
{
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

#ifdef S_ISSOCK
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (S_ISSOCK(st.st_mode)) return TRUE;

#endif
    return FALSE;
}

static VALUE
test_b(obj, fname)
    VALUE obj, fname;
{
#ifndef S_ISBLK
#   ifdef S_IFBLK
#	define S_ISBLK(m) ((m & S_IFMT) == S_IFBLK)
#   else
#	define S_ISBLK(m) (0)  /* anytime false */
#   endif
#endif

#ifdef S_ISBLK
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (S_ISBLK(st.st_mode)) return TRUE;

#endif
    return FALSE;
}

static VALUE
test_c(obj, fname)
    VALUE obj, fname;
{
#ifndef S_ISCHR
#   define S_ISCHR(m) ((m & S_IFMT) == S_IFCHR)
#endif

    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (S_ISBLK(st.st_mode)) return TRUE;

    return FALSE;
}

static VALUE
test_e(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    return TRUE;
}

static VALUE
test_r(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (eaccess(RSTRING(fname)->ptr, R_OK) < 0) return FALSE;
    return TRUE;
}

static VALUE
test_R(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (access(RSTRING(fname)->ptr, R_OK) < 0) return FALSE;
    return TRUE;
}

static VALUE
test_w(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (eaccess(RSTRING(fname)->ptr, W_OK) < 0) return FALSE;
    return TRUE;
}

static VALUE
test_W(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (access(RSTRING(fname)->ptr, W_OK) < 0) return FALSE;
    return TRUE;
}

static VALUE
test_x(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (eaccess(RSTRING(fname)->ptr, X_OK) < 0) return FALSE;
    return TRUE;
}

static VALUE
test_X(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (access(RSTRING(fname)->ptr, X_OK) < 0) return FALSE;
    return TRUE;
}

#ifndef S_ISREG
#   define S_ISREG(m) ((m & S_IFMT) == S_IFREG)
#endif

static VALUE
test_f(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (S_ISREG(st.st_mode)) return TRUE;
    return FALSE;
}

static VALUE
test_z(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (st.st_size == 0) return TRUE;
    return FALSE;
}

static VALUE
test_s(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (st.st_size == 0) return FALSE;
    return int2inum(st.st_size);
}

static VALUE
test_owned(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (st.st_uid == geteuid()) return TRUE;
    return FALSE;
}

static VALUE
test_rowned(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (st.st_uid == getuid()) return TRUE;
    return FALSE;
}

static VALUE
test_grpowned(obj, fname)
    VALUE obj, fname;
{
#ifndef NT
    struct stat st;

    if (rb_stat(fname, &st) < 0) return FALSE;
    if (st.st_gid == getegid()) return TRUE;
#endif
    return FALSE;
}

#if defined(S_ISUID) || defined(S_ISGID) || defined(S_ISVTX)
static VALUE
check3rdbyte(file, mode)
    char *file;
    int mode;
{
    struct stat st;

    if (stat(file, &st) < 0) return FALSE;
    if (st.st_mode & mode) return TRUE;
    return FALSE;
}
#endif

static VALUE
test_suid(obj, fname)
    VALUE obj, fname;
{
#ifdef S_ISUID
    Check_SafeStr(fname);
    return check3rdbyte(RSTRING(fname)->ptr, S_ISUID);
#else
    return FALSE;
#endif
}

static VALUE
test_sgid(obj, fname)
    VALUE obj, fname;
{
#ifndef NT
    Check_SafeStr(fname);
    return check3rdbyte(RSTRING(fname)->ptr, S_ISGID);
#else
    return FALSE;
#endif
}

static VALUE
test_sticky(obj, fname)
    VALUE obj, fname;
{
    Check_Type(fname, T_STRING);
#ifdef S_ISVTX
    return check3rdbyte(RSTRING(fname)->ptr, S_ISVTX);
#else
    return FALSE;
#endif
}

static VALUE
file_s_size(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return int2inum(st.st_size);
}

static VALUE
file_s_ftype(obj, fname)
    VALUE obj, fname;
{
    struct stat st;
    char *t;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);

    if (S_ISREG(st.st_mode)) {
	t = "file";
    } else if (S_ISDIR(st.st_mode)) {
	t = "directory";
    } else if (S_ISCHR(st.st_mode)) {
	t = "characterSpecial";
    }
#ifdef S_ISBLK
    else if (S_ISBLK(st.st_mode)) {
	t = "blockSpecial";
    }
#endif
#ifdef S_ISFIFO
    else if (S_ISFIFO(st.st_mode)) {
	t = "fifo";
    }
#endif
#ifdef S_ISLNK
    else if (S_ISLNK(st.st_mode)) {
	t = "link";
    }
#endif
#ifdef S_ISSOCK
    else if (S_ISSOCK(st.st_mode)) {
	t = "socket";
    }
#endif
    else {
	t = "unknown";
    }

    return str_new2(t);
}

static VALUE
file_s_atime(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return time_new(st.st_atime, 0);
}

static VALUE
file_atime(obj)
    VALUE obj;
{
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return time_new(st.st_atime, 0);
}

static VALUE
file_s_mtime(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return time_new(st.st_mtime, 0);
}

static VALUE
file_mtime(obj)
    VALUE obj;
{
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return time_new(st.st_mtime, 0);
}

static VALUE
file_s_ctime(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return time_new(st.st_ctime, 0);
}

static VALUE
file_ctime(obj)
    VALUE obj;
{
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return time_new(st.st_ctime, 0);
}

static void
chmod_internal(path, mode)
    char *path;
    int mode;
{
    if (chmod(path, mode) == -1)
	rb_sys_fail(path);
}

static VALUE
file_s_chmod(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vmode;
    VALUE rest;
    int mode, n;

    rb_scan_args(argc, argv, "1*", &vmode, &rest);
    mode = NUM2INT(vmode);

    n = apply2files(chmod_internal, rest, mode);
    return INT2FIX(n);
}

static VALUE
file_chmod(obj, vmode)
    VALUE obj, vmode;
{
    OpenFile *fptr;
    int mode;

    rb_secure(2);
    mode = NUM2INT(vmode);

    GetOpenFile(obj, fptr);
#if defined(DJGPP) || defined(NT)
    if (chmod(fptr->path, mode) == -1)
	rb_sys_fail(fptr->path);
#else
    if (fchmod(fileno(fptr->f), mode) == -1)
	rb_sys_fail(fptr->path);
#endif

    return INT2FIX(0);
}

struct chown_args {
    int owner, group;
};

static void
chown_internal(path, args)
    char *path;
    struct chown_args *args;
{
    if (chown(path, args->owner, args->group) < 0)
	rb_sys_fail(path);
}

static VALUE
file_s_chown(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE o, g, rest;
    struct chown_args arg;
    int n;

    rb_scan_args(argc, argv, "2*", &o, &g, &rest);
    if (NIL_P(o)) {
	arg.owner = -1;
    }
    else {
	arg.owner = NUM2INT(o);
    }
    if (NIL_P(g)) {
	arg.group = -1;
    }
    else {
	arg.group = NUM2INT(g);
    }

    n = apply2files(chown_internal, rest, &arg);
    return INT2FIX(n);
}

static VALUE
file_chown(obj, owner, group)
    VALUE obj, owner, group;
{
    OpenFile *fptr;

    rb_secure(2);
    GetOpenFile(obj, fptr);
#if defined(DJGPP) || defined(__CYGWIN32__) || defined(NT)
    if (chown(fptr->path, NUM2INT(owner), NUM2INT(group)) == -1)
	rb_sys_fail(fptr->path);
#else
    if (fchown(fileno(fptr->f), NUM2INT(owner), NUM2INT(group)) == -1)
	rb_sys_fail(fptr->path);
#endif

    return INT2FIX(0);
}

struct timeval time_timeval();

#ifdef HAVE_UTIMES

static void
utime_internal(path, tvp)
    char *path;
    struct timeval tvp[];
{
    if (utimes(path, tvp) < 0)
	rb_sys_fail(path);
}

static VALUE
file_s_utime(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE atime, mtime, rest;
    struct timeval tvp[2];
    int n;

    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    tvp[0] = time_timeval(atime);
    tvp[1] = time_timeval(mtime);

    n = apply2files(utime_internal, rest, tvp);
    return INT2FIX(n);
}

#else

#ifndef HAVE_UTIME_H
# ifdef NT
#  include <sys/utime.h>
#  define utimbuf _utimbuf
# else
struct utimbuf {
    long actime;
    long modtime;
};
# endif
#endif

static void
utime_internal(path, utp)
    char *path;
    struct utimbuf *utp;
{
    if (utime(path, utp) < 0)
	rb_sys_fail(path);
}

static VALUE
file_s_utime(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE atime, mtime, rest;
    int n;
    struct timeval tv;
    struct utimbuf utbuf;

    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    tv = time_timeval(atime);
    utbuf.actime = tv.tv_sec;
    tv = time_timeval(mtime);
    utbuf.modtime = tv.tv_sec;

    n = apply2files(utime_internal, rest, &utbuf);
    return INT2FIX(n);
}

#endif

static VALUE
file_s_link(obj, from, to)
    VALUE obj, from, to;
{
    Check_SafeStr(from);
    Check_SafeStr(to);

    if (link(RSTRING(from)->ptr, RSTRING(to)->ptr) < 0)
	rb_sys_fail(RSTRING(from)->ptr);
    return INT2FIX(0);
}

static VALUE
file_s_symlink(obj, from, to)
    VALUE obj, from, to;
{
#if !defined(MSDOS) && !defined(NT)
    Check_SafeStr(from);
    Check_SafeStr(to);

    if (symlink(RSTRING(from)->ptr, RSTRING(to)->ptr) < 0)
	rb_sys_fail(RSTRING(from)->ptr);
    return INT2FIX(0);
#else
    rb_notimplement();
#endif
}

static VALUE
file_s_readlink(obj, path)
    VALUE obj, path;
{
#if !defined(MSDOS) && !defined(NT)
    char buf[MAXPATHLEN];
    int cc;

    Check_SafeStr(path);

    if ((cc = readlink(RSTRING(path)->ptr, buf, MAXPATHLEN)) < 0)
	rb_sys_fail(RSTRING(path)->ptr);

    return str_new(buf, cc);
#else
    rb_notimplement();
#endif
}

static void
unlink_internal(path)
    char *path;
{
    if (unlink(path) < 0)
	rb_sys_fail(path);
}

static VALUE
file_s_unlink(obj, args)
    VALUE obj, args;
{
    int n;

    n = apply2files(unlink_internal, args, 0);
    return INT2FIX(n);
}

static VALUE
file_s_rename(obj, from, to)
    VALUE obj, from, to;
{
    Check_SafeStr(from);
    Check_SafeStr(to);

    if (rename(RSTRING(from)->ptr, RSTRING(to)->ptr) < 0)
	rb_sys_fail(RSTRING(from)->ptr);

    return INT2FIX(0);
}

static VALUE
file_s_umask(argc, argv)
    int argc;
    VALUE *argv;
{
    int omask = 0;

    if (argc == 0) {
	omask = umask(0);
	umask(omask);
    }
    else if (argc == 1) {
	omask = umask(NUM2INT(argv[0]));
    }
    else {
	ArgError("wrong # of argument");
    }
    return INT2FIX(omask);
}

VALUE
file_s_expand_path(obj, fname)
    VALUE obj, fname;
{
    char *s, *p;
    char buf[MAXPATHLEN+2];

    Check_Type(fname, T_STRING);
    s = RSTRING(fname)->ptr;

    p = buf;
    if (s[0] == '~') {
	if (s[1] == '/' || s[1] == '\0') {
	    char *dir = getenv("HOME");

	    if (!dir) {
		Fail("couldn't find HOME environment -- expanding `%s'", s);
	    }
	    strcpy(buf, dir);
	    p = &buf[strlen(buf)];
	    s++;
	}
	else {
#ifdef HAVE_PWD_H
	    struct passwd *pwPtr;
	    s++;
#endif

	    while (*s && *s != '/') {
		*p++ = *s++;
	    }
	    *p = '\0';
#ifdef HAVE_PWD_H
	    pwPtr = getpwnam(buf);
	    if (!pwPtr) {
		endpwent();
		Fail("user %s doesn't exist", buf);
	    }
	    strcpy(buf, pwPtr->pw_dir);
	    p = &buf[strlen(buf)];
	    endpwent();
#endif
	}
    }
    else if (s[0] != '/') {
#ifdef HAVE_GETCWD
	getcwd(buf, MAXPATHLEN);
#else
	getwd(buf);
#endif
	p = &buf[strlen(buf)];
    }
    *p = '/';

    for ( ; *s; s++) {
	switch (*s) {
	  case '.':
	    if (*(s+1)) {
		switch (*++s) {
		  case '.':
		    if (*(s+1) == '\0' || *(s+1) == '/') { 
			/* We must go back to the parent */
			if (*p == '/' && p > buf) p--;
			while (p > buf && *p != '/') p--;
		    }
		    else {
			*++p = '.';
			*++p = '.';
		    }
		    break;
		  case '/':
		    if (*p != '/') *++p = '/'; 
		    break;
		  default:
		    *++p = '.'; *++p = *s; break;
		}
	    }
	    break;
	  case '/':
	    if (*p != '/') *++p = '/'; break;
	  default:
	    *++p = *s;
	}
    }
  
    /* Place a \0 at end. If path ends with a "/", delete it */
    if (p == buf || *p != '/') p++;
    *p = '\0';

    return str_taint(str_new2(buf));
}

static int
rmext(p, e)
    char *p, *e;
{
    int l1, l2;

    l1 = strlen(p);
    if (!e) return 0;

    l2 = strlen(e);
    if (l2 == 2 && e[1] == '*') {
	e = strrchr(p, *e);
	if (!e) return 0;
	return e - p;
    }
    if (l1 < l2) return l1;

    if (strcmp(p+l1-l2, e) == 0) {
	return l1-l2;
    }
    return 0;
}

static VALUE
file_s_basename(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, ext;
    char *p;
    int f;

    rb_scan_args(argc, argv, "11", &fname, &ext);
    Check_Type(fname, T_STRING);
    if (!NIL_P(ext)) Check_Type(ext, T_STRING);
    p = strrchr(RSTRING(fname)->ptr, '/');
    if (!p) {
	if (!NIL_P(ext)) {
	    f = rmext(RSTRING(fname)->ptr, RSTRING(ext)->ptr);
	    if (f) return str_new(RSTRING(fname)->ptr, f);
	}
	return fname;
    }
    p++;			/* skip last `/' */
    if (!NIL_P(ext)) {
	f = rmext(p, RSTRING(ext)->ptr);
	if (f) return str_new(p, f);
    }
    return str_taint(str_new2(p));
}

static VALUE
file_s_dirname(obj, fname)
    VALUE obj, fname;
{
    UCHAR *p;

    Check_Type(fname, T_STRING);
    p = strrchr(RSTRING(fname)->ptr, '/');
    if (!p) {
	return str_new2(".");
    }
    if (p == RSTRING(fname)->ptr)
	p++;
    return str_taint(str_new(RSTRING(fname)->ptr, p - RSTRING(fname)->ptr));
}

static VALUE
file_s_split(obj, path)
    VALUE obj, path;
{
    return assoc_new(file_s_dirname(Qnil, path), file_s_basename(1,&path));
}

static VALUE separator;

static VALUE
file_s_join(obj, args)
    VALUE obj, args;
{
    return ary_join(args, separator);
}

static VALUE
file_s_truncate(obj, path, len)
    VALUE obj, path, len;
{
    Check_SafeStr(path);

#ifdef HAVE_TRUNCATE
    if (truncate(RSTRING(path)->ptr, NUM2INT(len)) < 0)
	rb_sys_fail(RSTRING(path)->ptr);
#else
# ifdef HAVE_CHSIZE
    {
	int tmpfd;

#  if defined(NT)
	if ((tmpfd = open(RSTRING(path)->ptr, O_RDWR)) < 0) {
	    rb_sys_fail(RSTRING(path)->ptr);
	}
#  else
	if ((tmpfd = open(RSTRING(path)->ptr, 0)) < 0) {
	    rb_sys_fail(RSTRING(path)->ptr);
	}
#  endif
	if (chsize(tmpfd, NUM2INT(len)) < 0) {
	    close(tmpfd);
	    rb_sys_fail(RSTRING(path)->ptr);
	}
	close(tmpfd);
    }
# else
    rb_notimplement();
# endif
#endif
    return INT2FIX(0);
}

static VALUE
file_truncate(obj, len)
    VALUE obj, len;
{
    OpenFile *fptr;

    rb_secure(2);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	Fail("not opened for writing");
    }
#ifdef HAVE_TRUNCATE
    if (ftruncate(fileno(fptr->f), NUM2INT(len)) < 0)
	rb_sys_fail(fptr->path);
#else
# ifdef HAVE_CHSIZE
    if (chsize(fileno(fptr->f), NUM2INT(len)) < 0)
	rb_sys_fail(fptr->path);
# else
    rb_notimplement();
# endif
#endif
    return INT2FIX(0);
}

#if defined(THREAD) && defined(EWOULDBLOCK)
static int
thread_flock(fd, op)
    int fd, op;
{
    if (thread_alone() || (op & LOCK_NB)) {
	return flock(fd, op);
    }
    op |= LOCK_NB;
    while (flock(fd, op) < 0) {
	switch (errno) {
	  case EINTR:		/* can be happen? */
	  case EWOULDBLOCK:
	    thread_schedule();	/* busy wait */
	    break;
	  default:
	    return -1;
	}
    }
    return 0;
}
#define flock thread_flock
#endif

static VALUE
file_flock(obj, operation)
    VALUE obj;
    VALUE operation;
{
    OpenFile *fptr;

    rb_secure(2);
    GetOpenFile(obj, fptr);

    if (flock(fileno(fptr->f), NUM2INT(operation)) < 0) {
#ifdef EWOULDBLOCK
	if (errno == EWOULDBLOCK) {
	    return FALSE;
	}
#endif
	rb_sys_fail(fptr->path);
    }
    return INT2FIX(0);
}
#undef flock

static void
test_check(n, argc, argv)
    int n, argc;
    VALUE *argv;
{
    int i;

    n+=1;
    if (n < argc) ArgError("Wrong # of arguments(%d for %d)", argc, n);
    for (i=1; i<n; i++) {
	switch (TYPE(argv[i])) {
	  case T_STRING:
	    Check_SafeStr(argv[i]);
	    break;
	  case T_FILE:
	    break;
	  default:
	    Check_Type(argv[i], T_STRING);
	    break;
	}
    }
}

#define CHECK(n) test_check((n), argc, argv)

static VALUE
f_test(argc, argv)
    int argc;
    VALUE *argv;
{
    int cmd;

    if (argc == 0) ArgError("Wrong # of arguments");
    cmd = NUM2CHR(argv[0]);
    if (cmd == 0) return FALSE;
    if (strchr("bcdefgGkloOprRsSuwWxXz", cmd)) {
	CHECK(1);
	switch (cmd) {
	  case 'b':
	    return test_b(0, argv[1]);

	  case 'c':
	    return test_c(0, argv[1]);

	  case 'd':
	    return test_d(0, argv[1]);

	  case 'a':
	  case 'e':
	    return test_e(0, argv[1]);

	  case 'f':
	    return test_f(0, argv[1]);

	  case 'g':
	    return test_sgid(0, argv[1]);

	  case 'G':
	    return test_grpowned(0, argv[1]);

	  case 'k':
	    return test_sticky(0, argv[1]);

	  case 'l':
	    return test_l(0, argv[1]);

	  case 'o':
	    return test_owned(0, argv[1]);

	  case 'O':
	    return test_rowned(0, argv[1]);

	  case 'p':
	    return test_p(0, argv[1]);

	  case 'r':
	    return test_r(0, argv[1]);

	  case 'R':
	    return test_R(0, argv[1]);

	  case 's':
	    return test_s(0, argv[1]);

	  case 'S':
	    return test_S(0, argv[1]);

	  case 'u':
	    return test_suid(0, argv[1]);

	  case 'w':
	    return test_w(0, argv[1]);

	  case 'W':
	    return test_W(0, argv[1]);

	  case 'x':
	    return test_x(0, argv[1]);

	  case 'X':
	    return test_X(0, argv[1]);

	  case 'z':
	    return test_z(0, argv[1]);
	}
    }

    if (strchr("MAC", cmd)) {
	struct stat st;

	CHECK(1);
	if (rb_stat(argv[1], &st) == -1) {
	    rb_sys_fail(RSTRING(argv[1])->ptr);
	}

	switch (cmd) {
	  case 'A':
	    return time_new(st.st_atime, 0);
	  case 'M':
	    return time_new(st.st_mtime, 0);
	  case 'C':
	    return time_new(st.st_ctime, 0);
	}
    }

    if (strchr("-=<>", cmd)) {
	struct stat st1, st2;

	CHECK(2);
	if (rb_stat(argv[1], &st1) < 0) return FALSE;
	if (rb_stat(argv[2], &st2) < 0) return FALSE;

	switch (cmd) {
	  case '-':
	    if (st1.st_dev == st2.st_dev && st1.st_ino == st2.st_ino)
		return TRUE;
	    break;

	  case '=':
	    if (st1.st_mtime == st2.st_mtime) return TRUE;
	    break;

	  case '>':
	    if (st1.st_mtime > st2.st_mtime) return TRUE;
	    break;

	  case '<':
	    if (st1.st_mtime < st2.st_mtime) return TRUE;
	    break;
	}
    }
    /* unknown command */
    ArgError("unknow command ?%c", cmd);
    return Qnil;		/* not reached */
}

extern VALUE mKernel;

void
Init_File()
{
    VALUE mConst;

    mFileTest = rb_define_module("FileTest");

    rb_define_module_function(mFileTest, "directory?",  test_d, 1);
    rb_define_module_function(mFileTest, "exist?",  test_e, 1);
    rb_define_module_function(mFileTest, "exists?",  test_e, 1); /* temporary */
    rb_define_module_function(mFileTest, "readable?",  test_r, 1);
    rb_define_module_function(mFileTest, "readable_real?",  test_R, 1);
    rb_define_module_function(mFileTest, "writable?",  test_w, 1);
    rb_define_module_function(mFileTest, "writable_real?",  test_W, 1);
    rb_define_module_function(mFileTest, "executable?",  test_x, 1);
    rb_define_module_function(mFileTest, "executable_real?",  test_X, 1);
    rb_define_module_function(mFileTest, "file?",  test_f, 1);
    rb_define_module_function(mFileTest, "zero?",  test_z, 1);
    rb_define_module_function(mFileTest, "size?",  test_s, 1);
    rb_define_module_function(mFileTest, "size",   test_s, 1);
    rb_define_module_function(mFileTest, "owned?",  test_owned, 1);
    rb_define_module_function(mFileTest, "grpowned?",  test_grpowned, 1);

    rb_define_module_function(mFileTest, "pipe?",  test_p, 1);
    rb_define_module_function(mFileTest, "symlink?",  test_l, 1);
    rb_define_module_function(mFileTest, "socket?",  test_S, 1);

    rb_define_module_function(mFileTest, "blockdev?",  test_b, 1);
    rb_define_module_function(mFileTest, "chardev?",  test_c, 1);

    rb_define_module_function(mFileTest, "setuid?",  test_suid, 1);
    rb_define_module_function(mFileTest, "setgid?",  test_sgid, 1);
    rb_define_module_function(mFileTest, "sticky?",  test_sticky, 1);

    cFile = rb_define_class("File", cIO);
    rb_extend_object(cFile, CLASS_OF(mFileTest));

    rb_define_singleton_method(cFile, "new",  file_s_open, -1);
    rb_define_singleton_method(cFile, "open",  file_s_open, -1);

    rb_define_singleton_method(cFile, "stat",  file_s_stat, 1);
    rb_define_singleton_method(cFile, "lstat", file_s_lstat, 1);
    rb_define_singleton_method(cFile, "ftype", file_s_ftype, 1);

    rb_define_singleton_method(cFile, "atime", file_s_atime, 1);
    rb_define_singleton_method(cFile, "mtime", file_s_mtime, 1);
    rb_define_singleton_method(cFile, "ctime", file_s_ctime, 1);
    rb_define_singleton_method(cFile, "size",  file_s_size, 1);

    rb_define_singleton_method(cFile, "utime", file_s_utime, -1);
    rb_define_singleton_method(cFile, "chmod", file_s_chmod, -1);
    rb_define_singleton_method(cFile, "chown", file_s_chown, -1);

    rb_define_singleton_method(cFile, "link", file_s_link, 2);
    rb_define_singleton_method(cFile, "symlink", file_s_symlink, 2);
    rb_define_singleton_method(cFile, "readlink", file_s_readlink, 1);

    rb_define_singleton_method(cFile, "unlink", file_s_unlink, -2);
    rb_define_singleton_method(cFile, "delete", file_s_unlink, -2);
    rb_define_singleton_method(cFile, "rename", file_s_rename, 2);
    rb_define_singleton_method(cFile, "umask", file_s_umask, -1);
    rb_define_singleton_method(cFile, "truncate", file_s_truncate, 2);
    rb_define_singleton_method(cFile, "expand_path", file_s_expand_path, 1);
    rb_define_singleton_method(cFile, "basename", file_s_basename, -1);
    rb_define_singleton_method(cFile, "dirname", file_s_dirname, 1);

    separator = str_new2("/");
    rb_define_const(cFile, "Separator", separator);
    rb_define_singleton_method(cFile, "split",  file_s_split, 1);
    rb_define_singleton_method(cFile, "join",   file_s_join, -2);

    rb_define_method(cFile, "reopen",  file_reopen, -1);

    rb_define_method(cFile, "stat",  file_stat, 0);
    rb_define_method(cFile, "lstat",  file_lstat, 0);

    rb_define_method(cFile, "atime", file_atime, 0);
    rb_define_method(cFile, "mtime", file_mtime, 0);
    rb_define_method(cFile, "ctime", file_ctime, 0);

    rb_define_method(cFile, "chmod", file_chmod, 1);
    rb_define_method(cFile, "chown", file_chown, 2);
    rb_define_method(cFile, "truncate", file_truncate, 1);

    rb_define_method(cFile, "tell",  file_tell, 0);
    rb_define_method(cFile, "seek",  file_seek, 2);

    rb_define_method(cFile, "rewind", file_rewind, 0);

    rb_define_method(cFile, "pos",  file_tell, 0);
    rb_define_method(cFile, "pos=", file_set_pos, 1);

    rb_define_method(cFile, "eof", file_eof, 0);
    rb_define_method(cFile, "eof?", file_eof, 0);

    rb_define_method(cFile, "flock", file_flock, 1);

# ifndef LOCK_SH
#  define LOCK_SH 1
# endif
# ifndef LOCK_EX
#  define LOCK_EX 2
# endif
# ifndef LOCK_NB
#  define LOCK_NB 4
# endif
# ifndef LOCK_UN
#  define LOCK_UN 8
# endif

    mConst = rb_define_module_under(cFile, "Constants");
    rb_define_const(cFile, "LOCK_SH", INT2FIX(LOCK_SH));
    rb_define_const(cFile, "LOCK_EX", INT2FIX(LOCK_EX));
    rb_define_const(cFile, "LOCK_UN", INT2FIX(LOCK_UN));
    rb_define_const(cFile, "LOCK_NB", INT2FIX(LOCK_NB));

    rb_define_const(mConst, "LOCK_SH", INT2FIX(LOCK_SH));
    rb_define_const(mConst, "LOCK_EX", INT2FIX(LOCK_EX));
    rb_define_const(mConst, "LOCK_UN", INT2FIX(LOCK_UN));
    rb_define_const(mConst, "LOCK_NB", INT2FIX(LOCK_NB));

    rb_define_method(cFile, "path",  file_path, 0);

    rb_define_global_function("test", f_test, -1);

    sStat = struct_define("Stat", "dev", "ino", "mode",
			  "nlink", "uid", "gid", "rdev",
			  "size", "blksize", "blocks", 
			  "atime", "mtime", "ctime", 0);
}
