/************************************************

  file.c -

  $Author$
  $Date$
  created at: Mon Nov 15 12:24:34 JST 1993

  Copyright (C) 1993-2000 Yukihiro Matsumoto

************************************************/

#ifdef NT
#include "missing/file.h"
#endif

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#else
# define MAXPATHLEN 1024
#endif

#include <time.h>
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

VALUE rb_time_new _((time_t, time_t));

#ifdef HAVE_UTIME_H
#include <utime.h>
#endif

#ifdef HAVE_PWD_H
#include <pwd.h>
#endif

#ifndef HAVE_STRING_H
char *strrchr _((const char*,const char));
#endif

#include <sys/types.h>
#include <sys/stat.h>

#ifdef USE_CWGUSI
 #include "macruby_missing.h"
 extern int fileno(FILE *stream);
 extern int utimes();
 char* strdup(char*);
#endif

#ifdef __EMX__
#define lstat stat
#endif
 
VALUE rb_cFile;
VALUE rb_mFileTest;
static VALUE sStat;

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
rb_file_path(obj)
    VALUE obj;
{
    OpenFile *fptr;

    GetOpenFile(obj, fptr);
    if (fptr->path == NULL) return Qnil;
    return rb_str_new2(fptr->path);
}

#ifndef NT
# ifndef USE_CWGUSI
#  include <sys/file.h>
# endif
#else
#include "missing/file.h"
#endif

static VALUE
stat_new(st)
    struct stat *st;
{
    if (!st) rb_bug("stat_new() called with bad value");
    return rb_struct_new(sStat,
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
			 rb_time_new(st->st_atime, 0),
			 rb_time_new(st->st_mtime, 0),
			 rb_time_new(st->st_ctime, 0));
}

static int
rb_stat(file, st)
    VALUE file;
    struct stat *st;
{
    if (TYPE(file) == T_FILE) {
	OpenFile *fptr;

	rb_secure(4);
	GetOpenFile(file, fptr);
	return fstat(fileno(fptr->f), st);
    }
    Check_SafeStr(file);
#if defined DJGPP
    if (RSTRING(file)->len == 0) return -1;
#endif
    return stat(RSTRING(file)->ptr, st);
}

static VALUE
rb_file_s_stat(obj, fname)
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
rb_io_stat(obj)
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
rb_file_s_lstat(obj, fname)
    VALUE obj, fname;
{
#if !defined(MSDOS) && !defined(NT) && !defined(__EMX__)
    struct stat st;

    Check_SafeStr(fname);
    if (lstat(RSTRING(fname)->ptr, &st) == -1) {
	rb_sys_fail(RSTRING(fname)->ptr);
    }
    return stat_new(&st);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static VALUE
rb_file_lstat(obj)
    VALUE obj;
{
#if !defined(MSDOS) && !defined(NT)
    OpenFile *fptr;
    struct stat st;

    rb_secure(4);
    GetOpenFile(obj, fptr);
    if (lstat(fptr->path, &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return stat_new(&st);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static int
group_member(gid)
    GETGROUPS_T gid;
{
#if !defined(NT) && !defined(USE_CWGUSI)
    if (getgid() ==  gid || getegid() == gid)
	return Qtrue;

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
		return Qtrue;
    }
# endif
#endif
    return Qfalse;
}

#ifndef S_IXUGO
#  define S_IXUGO		(S_IXUSR | S_IXGRP | S_IXOTH)
#endif

int
eaccess(path, mode)
     const char *path;
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
#else  /* !NT */
  return access(path, mode);
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

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISDIR(st.st_mode)) return Qtrue;
    return Qfalse;
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

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISFIFO(st.st_mode)) return Qtrue;

#endif
    return Qfalse;
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
    if (lstat(RSTRING(fname)->ptr, &st) < 0) return Qfalse;
    if (S_ISLNK(st.st_mode)) return Qtrue;

#endif
    return Qfalse;
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

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISSOCK(st.st_mode)) return Qtrue;

#endif
    return Qfalse;
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

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISBLK(st.st_mode)) return Qtrue;

#endif
    return Qfalse;
}

static VALUE
test_c(obj, fname)
    VALUE obj, fname;
{
#ifndef S_ISCHR
#   define S_ISCHR(m) ((m & S_IFMT) == S_IFCHR)
#endif

    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISCHR(st.st_mode)) return Qtrue;

    return Qfalse;
}

static VALUE
test_e(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_r(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (eaccess(RSTRING(fname)->ptr, R_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_R(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (access(RSTRING(fname)->ptr, R_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_w(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (eaccess(RSTRING(fname)->ptr, W_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_W(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (access(RSTRING(fname)->ptr, W_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_x(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (eaccess(RSTRING(fname)->ptr, X_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_X(obj, fname)
    VALUE obj, fname;
{
    Check_SafeStr(fname);
    if (access(RSTRING(fname)->ptr, X_OK) < 0) return Qfalse;
    return Qtrue;
}

#ifndef S_ISREG
#   define S_ISREG(m) ((m & S_IFMT) == S_IFREG)
#endif

static VALUE
test_f(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISREG(st.st_mode)) return Qtrue;
    return Qfalse;
}

static VALUE
test_z(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (st.st_size == 0) return Qtrue;
    return Qfalse;
}

static VALUE
test_s(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qnil;
    if (st.st_size == 0) return Qnil;
    return rb_int2inum(st.st_size);
}

static VALUE
test_owned(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (st.st_uid == geteuid()) return Qtrue;
    return Qfalse;
}

static VALUE
test_rowned(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (st.st_uid == getuid()) return Qtrue;
    return Qfalse;
}

static VALUE
test_grpowned(obj, fname)
    VALUE obj, fname;
{
#ifndef NT
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (st.st_gid == getegid()) return Qtrue;
#endif
    return Qfalse;
}

#if defined(S_ISUID) || defined(S_ISGID) || defined(S_ISVTX)
static VALUE
check3rdbyte(file, mode)
    const char *file;
    int mode;
{
    struct stat st;

    if (stat(file, &st) < 0) return Qfalse;
    if (st.st_mode & mode) return Qtrue;
    return Qfalse;
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
    return Qfalse;
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
    return Qfalse;
#endif
}

static VALUE
test_sticky(obj, fname)
    VALUE obj, fname;
{
#ifdef S_ISVTX
    return check3rdbyte(STR2CSTR(fname), S_ISVTX);
#else
    return Qnil;
#endif
}

static VALUE
rb_file_s_size(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return rb_int2inum(st.st_size);
}

static VALUE
rb_file_s_ftype(obj, fname)
    VALUE obj, fname;
{
    struct stat st;
    char *t;

#if defined(MSDOS) || defined(NT)
    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
#else
    Check_SafeStr(fname);
    if (lstat(RSTRING(fname)->ptr, &st) == -1) {
	rb_sys_fail(RSTRING(fname)->ptr);
    }
#endif

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

    return rb_str_new2(t);
}

static VALUE
rb_file_s_atime(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return rb_time_new(st.st_atime, 0);
}

static VALUE
rb_file_atime(obj)
    VALUE obj;
{
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return rb_time_new(st.st_atime, 0);
}

static VALUE
rb_file_s_mtime(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return rb_time_new(st.st_mtime, 0);
}

static VALUE
rb_file_mtime(obj)
    VALUE obj;
{
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return rb_time_new(st.st_mtime, 0);
}

static VALUE
rb_file_s_ctime(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return rb_time_new(st.st_ctime, 0);
}

static VALUE
rb_file_ctime(obj)
    VALUE obj;
{
    OpenFile *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return rb_time_new(st.st_ctime, 0);
}

static void
chmod_internal(path, mode)
    const char *path;
    int mode;
{
    if (chmod(path, mode) == -1)
	rb_sys_fail(path);
}

static VALUE
rb_file_s_chmod(argc, argv)
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
rb_file_chmod(obj, vmode)
    VALUE obj, vmode;
{
    OpenFile *fptr;
    int mode;

    rb_secure(4);
    mode = NUM2INT(vmode);

    GetOpenFile(obj, fptr);
#if defined(DJGPP) || defined(NT) || defined(USE_CWGUSI) || defined(__BEOS__) || defined(__EMX__)
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
    const char *path;
    struct chown_args *args;
{
    if (chown(path, args->owner, args->group) < 0)
	rb_sys_fail(path);
}

static VALUE
rb_file_s_chown(argc, argv)
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
rb_file_chown(obj, owner, group)
    VALUE obj, owner, group;
{
    OpenFile *fptr;

    rb_secure(4);
    GetOpenFile(obj, fptr);
#if defined(DJGPP) || defined(__CYGWIN32__) || defined(NT) || defined(USE_CWGUSI) || defined(__EMX__)
    if (chown(fptr->path, NUM2INT(owner), NUM2INT(group)) == -1)
	rb_sys_fail(fptr->path);
#else
    if (fchown(fileno(fptr->f), NUM2INT(owner), NUM2INT(group)) == -1)
	rb_sys_fail(fptr->path);
#endif

    return INT2FIX(0);
}

struct timeval rb_time_timeval();

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
rb_file_s_utime(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE atime, mtime, rest;
    struct timeval tvp[2];
    int n;

    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    tvp[0] = rb_time_timeval(atime);
    tvp[1] = rb_time_timeval(mtime);

    n = apply2files(utime_internal, rest, tvp);
    return INT2FIX(n);
}

#else

#ifndef HAVE_UTIME_H
# ifdef NT
#   if defined(__BORLANDC__)
#     include <utime.h>
#   else
#  include <sys/utime.h>
#   endif
#   if defined(_MSC_VER)
#  define utimbuf _utimbuf
#   endif
# else
struct utimbuf {
    long actime;
    long modtime;
};
# endif
#endif

static void
utime_internal(path, utp)
    const char *path;
    struct utimbuf *utp;
{
    if (utime(path, utp) < 0)
	rb_sys_fail(path);
}

static VALUE
rb_file_s_utime(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE atime, mtime, rest;
    int n;
    struct timeval tv;
    struct utimbuf utbuf;

    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    tv = rb_time_timeval(atime);
    utbuf.actime = tv.tv_sec;
    tv = rb_time_timeval(mtime);
    utbuf.modtime = tv.tv_sec;

    n = apply2files(utime_internal, rest, &utbuf);
    return INT2FIX(n);
}

#endif

static VALUE
rb_file_s_link(obj, from, to)
    VALUE obj, from, to;
{
#if defined(USE_CWGUSI)
        rb_notimplement();
#else
    Check_SafeStr(from);
    Check_SafeStr(to);

    if (link(RSTRING(from)->ptr, RSTRING(to)->ptr) < 0)
	rb_sys_fail(RSTRING(from)->ptr);
    return INT2FIX(0);
#endif /* USE_CWGUSI */
}

static VALUE
rb_file_s_symlink(obj, from, to)
    VALUE obj, from, to;
{
#if !defined(MSDOS) && !defined(NT) && !defined(__EMX__)
    Check_SafeStr(from);
    Check_SafeStr(to);

    if (symlink(RSTRING(from)->ptr, RSTRING(to)->ptr) < 0)
	rb_sys_fail(RSTRING(from)->ptr);
    return INT2FIX(0);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static VALUE
rb_file_s_readlink(obj, path)
    VALUE obj, path;
{
#if !defined(MSDOS) && !defined(NT) && !defined(__EMX__)
    char buf[MAXPATHLEN];
    int cc;

    Check_SafeStr(path);

    if ((cc = readlink(RSTRING(path)->ptr, buf, MAXPATHLEN)) < 0)
	rb_sys_fail(RSTRING(path)->ptr);

    return rb_tainted_str_new(buf, cc);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static void
unlink_internal(path)
    const char *path;
{
    if (unlink(path) < 0)
	rb_sys_fail(path);
}

static VALUE
rb_file_s_unlink(obj, args)
    VALUE obj, args;
{
    int n;

    n = apply2files(unlink_internal, args, 0);
    return INT2FIX(n);
}

static VALUE
rb_file_s_rename(obj, from, to)
    VALUE obj, from, to;
{
    Check_SafeStr(from);
    Check_SafeStr(to);

    if (rename(RSTRING(from)->ptr, RSTRING(to)->ptr) < 0)
	rb_sys_fail(RSTRING(from)->ptr);

    return INT2FIX(0);
}

static VALUE
rb_file_s_umask(argc, argv)
    int argc;
    VALUE *argv;
{
#ifdef USE_CWGUSI
    rb_notimplement();
#else
    int omask = 0;

    rb_secure(4);
    if (argc == 0) {
	omask = umask(0);
	umask(omask);
    }
    else if (argc == 1) {
	omask = umask(NUM2INT(argv[0]));
    }
    else {
	rb_raise(rb_eArgError, "wrong # of argument");
    }
    return INT2FIX(omask);
#endif /* USE_CWGUSI */
}

#if defined DOSISH
#define isdirsep(x) ((x) == '/' || (x) == '\\')
#else
#define isdirsep(x) ((x) == '/')
#endif

VALUE
rb_file_s_expand_path(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, dname;
    char *s, *p;
    char buf[MAXPATHLEN+2];
    int tainted = 0;

    rb_scan_args(argc, argv, "11", &fname, &dname);

    s = STR2CSTR(fname);
    p = buf;
    if (s[0] == '~') {
	tainted = 1;
	if (isdirsep(s[1]) || s[1] == '\0') {
	    char *dir = getenv("HOME");

	    if (!dir) {
		rb_raise(rb_eArgError, "couldn't find HOME environment -- expanding `%s'", s);
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
	    while (*s && !isdirsep(*s)) {
		*p++ = *s++;
	    }
	    *p = '\0';
#ifdef HAVE_PWD_H
	    pwPtr = getpwnam(buf);
	    if (!pwPtr) {
		endpwent();
		rb_raise(rb_eArgError, "user %s doesn't exist", buf);
	    }
	    strcpy(buf, pwPtr->pw_dir);
	    p = &buf[strlen(buf)];
	    endpwent();
#endif
	}
    }
#if defined DOSISH
    /* skip drive letter */
    else if (isalpha(s[0]) && s[1] == ':' && isdirsep(s[2])) {
	while (*s && !isdirsep(*s)) {
	    *p++ = *s++;
	}
    }
#endif
    else if (!isdirsep(*s)) {
	if (argc == 2) {
	    dname = rb_file_s_expand_path(1, &dname);
	    if (OBJ_TAINTED(dname)) tainted = 1;
	    strcpy(buf, RSTRING(dname)->ptr);
	}
	else {
	    tainted = 1;
#ifdef HAVE_GETCWD
	    getcwd(buf, MAXPATHLEN);
#else
	    getwd(buf);
#endif
	}
	p = &buf[strlen(buf)];
	while (p > buf && *(p - 1) == '/') p--;
    }
    else {
	while (*s && isdirsep(*s)) {
	    *p++ = '/';
	    s++;
	}
	if (p > buf && *s) p--;
    }
    *p = '/';

    for ( ; *s; s++) {
	switch (*s) {
	  case '.':
	    if (*(s+1)) {
		switch (*++s) {
		  case '.':
		    if (*(s+1) == '\0' || isdirsep(*(s+1))) { 
			/* We must go back to the parent */
			if (isdirsep(*p) && p > buf) p--;
			while (p > buf && !isdirsep(*p)) p--;
		    }
		    else {
			*++p = '.';
			do *++p = '.'; while (*++s == '.');
			--s;
		    }
		    break;
		  case '/':
#if defined DOSISH
		  case '\\':
#endif
		    if (!isdirsep(*p)) *++p = '/'; 
		    break;
		  default:
		    *++p = '.'; *++p = *s; break;
		}
	    }
	    break;
	  case '/':
#if defined DOSISH
	  case '\\':
#endif
	    if (!isdirsep(*p)) *++p = '/'; break;
	  default:
	    *++p = *s;
	}
    }
  
    /* Place a \0 at end. If path ends with a "/", delete it */
    if (p == buf || !isdirsep(*p)) p++;
    *p = '\0';

    fname = rb_str_new2(buf);
    if (tainted) OBJ_TAINT(fname);
    return fname;
}

static int
rmext(p, e)
    const char *p, *e;
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
rb_file_s_basename(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, fext, basename;
    char *name, *p, *ext;
    int f;

    if (rb_scan_args(argc, argv, "11", &fname, &fext) == 2) {
	ext = STR2CSTR(fext);
    }
    name = STR2CSTR(fname);
    p = strrchr(name, '/');
    if (!p) {
	if (!NIL_P(fext)) {
	    f = rmext(name, ext);
	    if (f) return rb_str_new(name, f);
	}
	return fname;
    }
    p++;			/* skip last `/' */
    if (!NIL_P(fext)) {
	f = rmext(p, ext);
	if (f) return rb_str_new(p, f);
    }
    basename = rb_str_new2(p);
    if (OBJ_TAINTED(fname)) OBJ_TAINT(basename);
    return basename;
}

static VALUE
rb_file_s_dirname(obj, fname)
    VALUE obj, fname;
{
    char *name, *p;
    VALUE dirname;

    name = STR2CSTR(fname);
    p = strrchr(name, '/');
    if (!p) {
	return rb_str_new2(".");
    }
    if (p == name)
	p++;
    dirname = rb_str_new(name, p - name);
    if (OBJ_TAINTED(fname)) OBJ_TAINT(dirname);
    return dirname;
}

static VALUE
rb_file_s_split(obj, path)
    VALUE obj, path;
{
    return rb_assoc_new(rb_file_s_dirname(Qnil, path), rb_file_s_basename(1,&path));
}

static VALUE separator;

static VALUE
rb_file_s_join(obj, args)
    VALUE obj, args;
{
    return rb_ary_join(args, separator);
}

static VALUE
rb_file_s_truncate(obj, path, len)
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
rb_file_truncate(obj, len)
    VALUE obj, len;
{
    OpenFile *fptr;

    rb_secure(4);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "not opened for writing");
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

#if defined(EWOULDBLOCK)
static int
rb_thread_flock(fd, op, fptr)
    int fd, op;
    OpenFile *fptr;
{
    if (rb_thread_alone() || (op & LOCK_NB)) {
	return flock(fd, op);
    }
    op |= LOCK_NB;
    while (flock(fd, op) < 0) {
	switch (errno) {
	  case EINTR:		/* can be happen? */
	  case EWOULDBLOCK:
	    rb_thread_schedule();	/* busy wait */
	    rb_io_check_closed(fptr);
	    break;
	  default:
	    return -1;
	}
    }
    return 0;
}
#define flock(fd, op) rb_thread_flock(fd, op, fptr)
#endif

static VALUE
rb_file_flock(obj, operation)
    VALUE obj;
    VALUE operation;
{
#ifdef USE_CWGUSI
    rb_notimplement();
#else
    OpenFile *fptr;

    rb_secure(4);
    GetOpenFile(obj, fptr);

    if (flock(fileno(fptr->f), NUM2INT(operation)) < 0) {
#ifdef EWOULDBLOCK
	if (errno == EWOULDBLOCK) {
	    return Qfalse;
	}
#endif
	rb_sys_fail(fptr->path);
    }
    return INT2FIX(0);
#endif /* USE_CWGUSI */
}
#undef flock

static void
test_check(n, argc, argv)
    int n, argc;
    VALUE *argv;
{
    int i;

    n+=1;
    if (n < argc) rb_raise(rb_eArgError, "wrong # of arguments(%d for %d)", argc, n);
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
rb_f_test(argc, argv)
    int argc;
    VALUE *argv;
{
    int cmd;

    if (argc == 0) rb_raise(rb_eArgError, "wrong # of arguments");
    cmd = NUM2CHR(argv[0]);
    if (cmd == 0) return Qfalse;
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
	    return rb_time_new(st.st_atime, 0);
	  case 'M':
	    return rb_time_new(st.st_mtime, 0);
	  case 'C':
	    return rb_time_new(st.st_ctime, 0);
	}
    }

    if (strchr("-=<>", cmd)) {
	struct stat st1, st2;

	CHECK(2);
	if (rb_stat(argv[1], &st1) < 0) return Qfalse;
	if (rb_stat(argv[2], &st2) < 0) return Qfalse;

	switch (cmd) {
	  case '-':
	    if (st1.st_dev == st2.st_dev && st1.st_ino == st2.st_ino)
		return Qtrue;
            return Qfalse;
                        
	  case '=':
	    if (st1.st_mtime == st2.st_mtime) return Qtrue;
	    return Qfalse;
                        
	  case '>':
	    if (st1.st_mtime > st2.st_mtime) return Qtrue;
	    return Qfalse;
            
	  case '<':
	    if (st1.st_mtime < st2.st_mtime) return Qtrue;
	    return Qfalse;
        }
    }
    /* unknown command */
    rb_raise(rb_eArgError, "unknown command ?%c", cmd);
    return Qnil;		/* not reached */
}

static VALUE rb_mConst;

void
rb_file_const(name, value)
    const char *name;
    VALUE value;
{
    rb_define_const(rb_cFile, name, value);
    rb_define_const(rb_mConst, name, value);
}

void
Init_File()
{
    rb_mFileTest = rb_define_module("FileTest");

    rb_define_module_function(rb_mFileTest, "directory?",  test_d, 1);
    rb_define_module_function(rb_mFileTest, "exist?",  test_e, 1);
    rb_define_module_function(rb_mFileTest, "exists?",  test_e, 1); /* temporary */
    rb_define_module_function(rb_mFileTest, "readable?",  test_r, 1);
    rb_define_module_function(rb_mFileTest, "readable_real?",  test_R, 1);
    rb_define_module_function(rb_mFileTest, "writable?",  test_w, 1);
    rb_define_module_function(rb_mFileTest, "writable_real?",  test_W, 1);
    rb_define_module_function(rb_mFileTest, "executable?",  test_x, 1);
    rb_define_module_function(rb_mFileTest, "executable_real?",  test_X, 1);
    rb_define_module_function(rb_mFileTest, "file?",  test_f, 1);
    rb_define_module_function(rb_mFileTest, "zero?",  test_z, 1);
    rb_define_module_function(rb_mFileTest, "size?",  test_s, 1);
    rb_define_module_function(rb_mFileTest, "size",   test_s, 1);
    rb_define_module_function(rb_mFileTest, "owned?",  test_owned, 1);
    rb_define_module_function(rb_mFileTest, "grpowned?",  test_grpowned, 1);

    rb_define_module_function(rb_mFileTest, "pipe?",  test_p, 1);
    rb_define_module_function(rb_mFileTest, "symlink?",  test_l, 1);
    rb_define_module_function(rb_mFileTest, "socket?",  test_S, 1);

    rb_define_module_function(rb_mFileTest, "blockdev?",  test_b, 1);
    rb_define_module_function(rb_mFileTest, "chardev?",  test_c, 1);

    rb_define_module_function(rb_mFileTest, "setuid?",  test_suid, 1);
    rb_define_module_function(rb_mFileTest, "setgid?",  test_sgid, 1);
    rb_define_module_function(rb_mFileTest, "sticky?",  test_sticky, 1);

    rb_cFile = rb_define_class("File", rb_cIO);
    rb_extend_object(rb_cFile, CLASS_OF(rb_mFileTest));

    rb_define_singleton_method(rb_cFile, "stat",  rb_file_s_stat, 1);
    rb_define_singleton_method(rb_cFile, "lstat", rb_file_s_lstat, 1);
    rb_define_singleton_method(rb_cFile, "ftype", rb_file_s_ftype, 1);

    rb_define_singleton_method(rb_cFile, "atime", rb_file_s_atime, 1);
    rb_define_singleton_method(rb_cFile, "mtime", rb_file_s_mtime, 1);
    rb_define_singleton_method(rb_cFile, "ctime", rb_file_s_ctime, 1);
    rb_define_singleton_method(rb_cFile, "size",  rb_file_s_size, 1);

    rb_define_singleton_method(rb_cFile, "utime", rb_file_s_utime, -1);
    rb_define_singleton_method(rb_cFile, "chmod", rb_file_s_chmod, -1);
    rb_define_singleton_method(rb_cFile, "chown", rb_file_s_chown, -1);

    rb_define_singleton_method(rb_cFile, "link", rb_file_s_link, 2);
    rb_define_singleton_method(rb_cFile, "symlink", rb_file_s_symlink, 2);
    rb_define_singleton_method(rb_cFile, "readlink", rb_file_s_readlink, 1);

    rb_define_singleton_method(rb_cFile, "unlink", rb_file_s_unlink, -2);
    rb_define_singleton_method(rb_cFile, "delete", rb_file_s_unlink, -2);
    rb_define_singleton_method(rb_cFile, "rename", rb_file_s_rename, 2);
    rb_define_singleton_method(rb_cFile, "umask", rb_file_s_umask, -1);
    rb_define_singleton_method(rb_cFile, "truncate", rb_file_s_truncate, 2);
    rb_define_singleton_method(rb_cFile, "expand_path", rb_file_s_expand_path, -1);
    rb_define_singleton_method(rb_cFile, "basename", rb_file_s_basename, -1);
    rb_define_singleton_method(rb_cFile, "dirname", rb_file_s_dirname, 1);

    separator = rb_str_new2("/");
    rb_define_const(rb_cFile, "Separator", separator);
    rb_define_const(rb_cFile, "SEPARATOR", separator);
    rb_define_singleton_method(rb_cFile, "split",  rb_file_s_split, 1);
    rb_define_singleton_method(rb_cFile, "join",   rb_file_s_join, -2);

#ifdef DOSISH
    rb_define_const(rb_cFile, "ALT_SEPARATOR", rb_str_new2("\\"));
#else
    rb_define_const(rb_cFile, "ALT_SEPARATOR", Qnil);
#endif
    rb_define_const(rb_cFile, "PATH_SEPARATOR", rb_str_new2(PATH_SEP));

    rb_define_method(rb_cIO, "stat",  rb_io_stat, 0); /* this is IO's method */
    rb_define_method(rb_cFile, "lstat",  rb_file_lstat, 0);

    rb_define_method(rb_cFile, "atime", rb_file_atime, 0);
    rb_define_method(rb_cFile, "mtime", rb_file_mtime, 0);
    rb_define_method(rb_cFile, "ctime", rb_file_ctime, 0);

    rb_define_method(rb_cFile, "chmod", rb_file_chmod, 1);
    rb_define_method(rb_cFile, "chown", rb_file_chown, 2);
    rb_define_method(rb_cFile, "truncate", rb_file_truncate, 1);

    rb_define_method(rb_cFile, "flock", rb_file_flock, 1);

    rb_mConst = rb_define_module_under(rb_cFile, "Constants");
    rb_file_const("LOCK_SH", INT2FIX(LOCK_SH));
    rb_file_const("LOCK_EX", INT2FIX(LOCK_EX));
    rb_file_const("LOCK_UN", INT2FIX(LOCK_UN));
    rb_file_const("LOCK_NB", INT2FIX(LOCK_NB));

    rb_define_method(rb_cFile, "path",  rb_file_path, 0);

    rb_define_global_function("test", rb_f_test, -1);

    sStat = rb_struct_define("Stat", "dev", "ino", "mode",
			     "nlink", "uid", "gid", "rdev",
			     "size", "blksize", "blocks", 
			     "atime", "mtime", "ctime", 0);
}
