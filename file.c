/**********************************************************************

  file.c -

  $Author$
  $Date$
  created at: Mon Nov 15 12:24:34 JST 1993

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifdef _WIN32
#include "missing/file.h"
#endif

#include "ruby.h"
#include "rubyio.h"
#include "rubysig.h"
#include "util.h"
#include "dln.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_SYS_FILE_H
# include <sys/file.h>
#else
int flock _((int, int));
#endif

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif
#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

#include <time.h>

VALUE rb_time_new _((time_t, time_t));

#ifdef HAVE_UTIME_H
#include <utime.h>
#elif defined HAVE_SYS_UTIME_H
#include <sys/utime.h>
#endif

#ifdef HAVE_PWD_H
#include <pwd.h>
#endif

#ifndef HAVE_STRING_H
char *strrchr _((const char*,const char));
#endif

#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_SYS_MKDEV_H
#include <sys/mkdev.h>
#endif

#ifndef HAVE_LSTAT
#define lstat(path,st) stat(path,st)
#endif

VALUE rb_cFile;
VALUE rb_mFileTest;
static VALUE rb_cStat;

static long
apply2files(func, vargs, arg)
    void (*func)();
    VALUE vargs;
    void *arg;
{
    long i;
    VALUE path;
    struct RArray *args = RARRAY(vargs);

    for (i=0; i<args->len; i++) {
	path = args->ptr[i];
	SafeStringValue(path);
	(*func)(StringValueCStr(path), arg);
    }

    return args->len;
}

static VALUE
rb_file_path(obj)
    VALUE obj;
{
    OpenFile *fptr;

    fptr = RFILE(rb_io_taint_check(obj))->fptr;
    if (!fptr->path) return Qnil;
    return rb_tainted_str_new2(fptr->path);
}

static VALUE
stat_new_0(klass, st)
    VALUE klass;
    struct stat *st;
{
    struct stat *nst = 0;

    if (st) {
	nst = ALLOC(struct stat);
	*nst = *st;
    }
    return Data_Wrap_Struct(klass, NULL, free, nst);
}

static VALUE
stat_new(st)
    struct stat *st;
{
    return stat_new_0(rb_cStat, st);
}

static struct stat*
get_stat(self)
    VALUE self;
{
    struct stat* st;
    Data_Get_Struct(self, struct stat, st);
    if (!st) rb_raise(rb_eTypeError, "uninitialized File::Stat");
    return st;
}

static VALUE
rb_stat_cmp(self, other)
    VALUE self, other;
{
    if (rb_obj_is_kind_of(other, rb_obj_class(self))) {
	time_t t1 = get_stat(self)->st_mtime;
	time_t t2 = get_stat(other)->st_mtime;
	if (t1 == t2)
	    return INT2FIX(0);
	else if (t1 < t2)
	    return INT2FIX(-1);
	else
	    return INT2FIX(1);
    }
    return Qnil;
}

static VALUE
rb_stat_dev(self)
    VALUE self;
{
    return INT2NUM(get_stat(self)->st_dev);
}

static VALUE
rb_stat_ino(self)
    VALUE self;
{
#ifdef HUGE_ST_INO
    return ULL2NUM(get_stat(self)->st_ino);
#else
    return ULONG2NUM(get_stat(self)->st_ino);
#endif
}

static VALUE
rb_stat_mode(self)
    VALUE self;
{
#ifdef __BORLANDC__
    return UINT2NUM((unsigned short)(get_stat(self)->st_mode));
#else
    return UINT2NUM(get_stat(self)->st_mode);
#endif
}

static VALUE
rb_stat_nlink(self)
    VALUE self;
{
    return UINT2NUM(get_stat(self)->st_nlink);
}

static VALUE
rb_stat_uid(self)
    VALUE self;
{
    return UINT2NUM(get_stat(self)->st_uid);
}

static VALUE
rb_stat_gid(self)
    VALUE self;
{
    return UINT2NUM(get_stat(self)->st_gid);
}

static VALUE
rb_stat_rdev(self)
    VALUE self;
{
#ifdef HAVE_ST_RDEV
    return ULONG2NUM(get_stat(self)->st_rdev);
#else
    return Qnil;
#endif
}

static VALUE
rb_stat_rdev_major(self)
    VALUE self;
{
#if defined(HAVE_ST_RDEV) && defined(major)
    long rdev = get_stat(self)->st_rdev;
    return ULONG2NUM(major(rdev));
#else
    return Qnil;
#endif
}

static VALUE
rb_stat_rdev_minor(self)
    VALUE self;
{
#if defined(HAVE_ST_RDEV) && defined(minor)
    long rdev = get_stat(self)->st_rdev;
    return ULONG2NUM(minor(rdev));
#else
    return Qnil;
#endif
}

static VALUE
rb_stat_size(self)
    VALUE self;
{
    return OFFT2NUM(get_stat(self)->st_size);
}

static VALUE
rb_stat_blksize(self)
    VALUE self;
{
#ifdef HAVE_ST_BLKSIZE
    return ULONG2NUM(get_stat(self)->st_blksize);
#else
    return Qnil;
#endif
}

static VALUE
rb_stat_blocks(self)
    VALUE self;
{
#ifdef HAVE_ST_BLOCKS
    return ULONG2NUM(get_stat(self)->st_blocks);
#else
    return Qnil;
#endif
}

static VALUE
rb_stat_atime(self)
    VALUE self;
{
    return rb_time_new(get_stat(self)->st_atime, 0);
}

static VALUE
rb_stat_mtime(self)
    VALUE self;
{
    return rb_time_new(get_stat(self)->st_mtime, 0);
}

static VALUE
rb_stat_ctime(self)
    VALUE self;
{
    return rb_time_new(get_stat(self)->st_ctime, 0);
}

static VALUE
rb_stat_inspect(self)
    VALUE self;
{
    VALUE str;
    int i;
    static struct {
        char *name;
        VALUE (*func)();
    } member[] = {
        {"dev",     rb_stat_dev},
        {"ino",     rb_stat_ino},
        {"mode",    rb_stat_mode},
        {"nlink",   rb_stat_nlink},
        {"uid",     rb_stat_uid},
        {"gid",     rb_stat_gid},
        {"rdev",    rb_stat_rdev},
        {"size",    rb_stat_size},
        {"blksize", rb_stat_blksize},
        {"blocks",  rb_stat_blocks},
        {"atime",   rb_stat_atime},
        {"mtime",   rb_stat_mtime},
        {"ctime",   rb_stat_ctime},
    };

    str = rb_str_buf_new2("#<");
    rb_str_buf_cat2(str, rb_obj_classname(self));
    rb_str_buf_cat2(str, " ");

    for (i = 0; i < sizeof(member)/sizeof(member[0]); i++) {
	VALUE v;

	if (i > 0) {
	    rb_str_buf_cat2(str, ", ");
	}
	rb_str_buf_cat2(str, member[i].name);
	rb_str_buf_cat2(str, "=");
	v = (*member[i].func)(self);
	if (i == 2) {		/* mode */
	    char buf[32];

	    sprintf(buf, "0%o", NUM2INT(v));
	    rb_str_buf_cat2(str, buf);
	}
	else if (i == 0 || i == 6) { /* dev/rdev */
	    char buf[32];

	    sprintf(buf, "0x%lx", NUM2ULONG(v));
	    rb_str_buf_cat2(str, buf);
	}
	else {
	    rb_str_append(str, rb_inspect(v));
	}
    }
    rb_str_buf_cat2(str, ">");
    OBJ_INFECT(str, self);

    return str;
}

static int
rb_stat(file, st)
    VALUE file;
    struct stat *st;
{
    VALUE tmp;

    tmp = rb_check_convert_type(file, T_FILE, "IO", "to_io");
    if (!NIL_P(tmp)) {
	OpenFile *fptr;

	rb_secure(2);
	GetOpenFile(tmp, fptr);
	return fstat(fileno(fptr->f), st);
    }
    SafeStringValue(file);
    return stat(StringValueCStr(file), st);
}

static VALUE
rb_file_s_stat(klass, fname)
    VALUE klass, fname;
{
    struct stat st;

    SafeStringValue(fname);
    if (rb_stat(fname, &st) < 0) {
	rb_sys_fail(StringValueCStr(fname));
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
rb_file_s_lstat(klass, fname)
    VALUE klass, fname;
{
#ifdef HAVE_LSTAT
    struct stat st;

    SafeStringValue(fname);
    if (lstat(StringValueCStr(fname), &st) == -1) {
	rb_sys_fail(RSTRING(fname)->ptr);
    }
    return stat_new(&st);
#else
    return rb_file_s_stat(klass, fname);
#endif
}

static VALUE
rb_file_lstat(obj)
    VALUE obj;
{
#ifdef HAVE_LSTAT
    OpenFile *fptr;
    struct stat st;

    rb_secure(2);
    GetOpenFile(obj, fptr);
    if (!fptr->path) return Qnil;
    if (lstat(fptr->path, &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return stat_new(&st);
#else
    return rb_io_stat(obj);
#endif
}

static int
group_member(gid)
    GETGROUPS_T gid;
{
#ifndef _WIN32
    if (getgid() ==  gid)
	return Qtrue;

# ifdef HAVE_GETGROUPS
#  ifndef NGROUPS
#   ifdef NGROUPS_MAX
#    define NGROUPS NGROUPS_MAX
#   else
#    define NGROUPS 32
#   endif
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
#if defined(S_IXGRP) && !defined(_WIN32) && !defined(__CYGWIN__)
    struct stat st;
    int euid;

    if (stat(path, &st) < 0) return -1;

    euid = geteuid();

    if (euid == 0) {
	/* Root can read or write any file. */
	if (!(mode & X_OK))
	    return 0;

	/* Root can execute any file that has any one of the execute
	   bits set. */
	if (st.st_mode & S_IXUGO)
	    return 0;

	return -1;
    }

    if (st.st_uid == euid)        /* owner */
	mode <<= 6;
    else if (getegid() == st.st_gid || group_member(st.st_gid))
	mode <<= 3;

    if ((st.st_mode & mode) == mode) return 0;

    return -1;
#else
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
#  elif defined __BORLANDC__
#    ifdef _S_IFLNK
#      define S_ISLNK(m) (((unsigned short)(m) & S_IFMT) == _S_IFLNK)
#    else
#      ifdef S_IFLNK
#        define S_ISLNK(m) (((unsigned short)(m) & S_IFMT) == S_IFLNK)
#      endif
#    endif
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

    SafeStringValue(fname);
    if (lstat(StringValueCStr(fname), &st) < 0) return Qfalse;
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
#  elif defined __BORLANDC__
#    ifdef _S_IFSOCK
#      define S_ISSOCK(m) (((unsigned short)(m) & S_IFMT) == _S_IFSOCK)
#    else
#      ifdef S_IFSOCK
#        define S_ISSOCK(m) (((unsigned short)(m) & S_IFMT) == S_IFSOCK)
#      endif
#    endif
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
    SafeStringValue(fname);
    if (eaccess(StringValueCStr(fname), R_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_R(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (access(StringValueCStr(fname), R_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_w(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (eaccess(StringValueCStr(fname), W_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_W(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (access(StringValueCStr(fname), W_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_x(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (eaccess(StringValueCStr(fname), X_OK) < 0) return Qfalse;
    return Qtrue;
}

static VALUE
test_X(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (access(StringValueCStr(fname), X_OK) < 0) return Qfalse;
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
    return OFFT2NUM(st.st_size);
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
#ifndef _WIN32
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (st.st_gid == getegid()) return Qtrue;
#endif
    return Qfalse;
}

#if defined(S_ISUID) || defined(S_ISGID) || defined(S_ISVTX)
static VALUE
check3rdbyte(fname, mode)
    VALUE fname;
    int mode;
{
    struct stat st;

    SafeStringValue(fname);
    if (stat(StringValueCStr(fname), &st) < 0) return Qfalse;
    if (st.st_mode & mode) return Qtrue;
    return Qfalse;
}
#endif

static VALUE
test_suid(obj, fname)
    VALUE obj, fname;
{
#ifdef S_ISUID
    return check3rdbyte(fname, S_ISUID);
#else
    return Qfalse;
#endif
}

static VALUE
test_sgid(obj, fname)
    VALUE obj, fname;
{
#ifdef S_ISGID
    return check3rdbyte(fname, S_ISGID);
#else
    return Qfalse;
#endif
}

static VALUE
test_sticky(obj, fname)
    VALUE obj, fname;
{
#ifdef S_ISVTX
    return check3rdbyte(fname, S_ISVTX);
#else
    return Qnil;
#endif
}

static VALUE
rb_file_s_size(klass, fname)
    VALUE klass, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(StringValueCStr(fname));
    return OFFT2NUM(st.st_size);
}

static VALUE
rb_file_ftype(st)
    struct stat *st;
{
    char *t;

    if (S_ISREG(st->st_mode)) {
	t = "file";
    }
    else if (S_ISDIR(st->st_mode)) {
	t = "directory";
    }
    else if (S_ISCHR(st->st_mode)) {
	t = "characterSpecial";
    }
#ifdef S_ISBLK
    else if (S_ISBLK(st->st_mode)) {
	t = "blockSpecial";
    }
#endif
#ifdef S_ISFIFO
    else if (S_ISFIFO(st->st_mode)) {
	t = "fifo";
    }
#endif
#ifdef S_ISLNK
    else if (S_ISLNK(st->st_mode)) {
	t = "link";
    }
#endif
#ifdef S_ISSOCK
    else if (S_ISSOCK(st->st_mode)) {
	t = "socket";
    }
#endif
    else {
	t = "unknown";
    }

    return rb_str_new2(t);
}

static VALUE
rb_file_s_ftype(klass, fname)
    VALUE klass, fname;
{
    struct stat st;

    SafeStringValue(fname);
    if (lstat(StringValueCStr(fname), &st) == -1) {
	rb_sys_fail(RSTRING(fname)->ptr);
    }

    return rb_file_ftype(&st);
}

static VALUE
rb_file_s_atime(klass, fname)
    VALUE klass, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(StringValueCStr(fname));
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
rb_file_s_mtime(klass, fname)
    VALUE klass, fname;
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
rb_file_s_ctime(klass, fname)
    VALUE klass, fname;
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
    if (chmod(path, mode) < 0)
	rb_sys_fail(path);
}

static VALUE
rb_file_s_chmod(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vmode;
    VALUE rest;
    int mode;
    long n;

    rb_secure(2);
    rb_scan_args(argc, argv, "1*", &vmode, &rest);
    mode = NUM2INT(vmode);

    n = apply2files(chmod_internal, rest, (void *)(long)mode);
    return LONG2FIX(n);
}

static VALUE
rb_file_chmod(obj, vmode)
    VALUE obj, vmode;
{
    OpenFile *fptr;
    int mode;

    rb_secure(2);
    mode = NUM2INT(vmode);

    GetOpenFile(obj, fptr);
#ifdef HAVE_FCHMOD
    if (fchmod(fileno(fptr->f), mode) == -1)
	rb_sys_fail(fptr->path);
#else
    if (!fptr->path) return Qnil;
    if (chmod(fptr->path, mode) == -1)
	rb_sys_fail(fptr->path);
#endif

    return INT2FIX(0);
}

#if defined(HAVE_LCHMOD)
static void
lchmod_internal(path, mode)
    const char *path;
    int mode;
{
    if (lchmod(path, mode) < 0)
	rb_sys_fail(path);
}

static VALUE
rb_file_s_lchmod(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vmode;
    VALUE rest;
    int mode;
    long n;

    rb_secure(2);
    rb_scan_args(argc, argv, "1*", &vmode, &rest);
    mode = NUM2INT(vmode);

    n = apply2files(lchmod_internal, rest, (void *)(long)mode);
    return LONG2FIX(n);
}
#else
static VALUE
rb_file_s_lchmod(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_notimplement();
    return Qnil;		/* not reached */
}
#endif

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
    long n;

    rb_secure(2);
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
    return LONG2FIX(n);
}

static VALUE
rb_file_chown(obj, owner, group)
    VALUE obj, owner, group;
{
    OpenFile *fptr;

    rb_secure(2);
    GetOpenFile(obj, fptr);
#if defined(DJGPP) || defined(__CYGWIN32__) || defined(_WIN32) || defined(__EMX__)
    if (!fptr->path) return Qnil;
    if (chown(fptr->path, NUM2INT(owner), NUM2INT(group)) == -1)
	rb_sys_fail(fptr->path);
#else
    if (fchown(fileno(fptr->f), NUM2INT(owner), NUM2INT(group)) == -1)
	rb_sys_fail(fptr->path);
#endif

    return INT2FIX(0);
}

#if defined(HAVE_LCHOWN) && !defined(__CHECKER__)
static void
lchown_internal(path, args)
    const char *path;
    struct chown_args *args;
{
    if (lchown(path, args->owner, args->group) < 0)
	rb_sys_fail(path);
}

static VALUE
rb_file_s_lchown(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE o, g, rest;
    struct chown_args arg;
    long n;

    rb_secure(2);
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

    n = apply2files(lchown_internal, rest, &arg);
    return LONG2FIX(n);
}
#else
static VALUE
rb_file_s_lchown(argc, argv)
    int argc;
    VALUE *argv;
{
    rb_notimplement();
}
#endif

struct timeval rb_time_timeval();

#if defined(HAVE_UTIMES) && !defined(__CHECKER__)

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
    long n;

    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    tvp[0] = rb_time_timeval(atime);
    tvp[1] = rb_time_timeval(mtime);

    n = apply2files(utime_internal, rest, tvp);
    return LONG2FIX(n);
}

#else

#if !defined HAVE_UTIME_H && !defined HAVE_SYS_UTIME_H
struct utimbuf {
    long actime;
    long modtime;
};
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
    long n;
    struct timeval tv;
    struct utimbuf utbuf;

    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    tv = rb_time_timeval(atime);
    utbuf.actime = tv.tv_sec;
    tv = rb_time_timeval(mtime);
    utbuf.modtime = tv.tv_sec;

    n = apply2files(utime_internal, rest, &utbuf);
    return LONG2FIX(n);
}

#endif

NORETURN(static void sys_fail2 _((VALUE,VALUE)));
static void
sys_fail2(s1, s2)
    VALUE s1, s2;
{
    char *buf;
    int len;

    len = RSTRING(s1)->len + RSTRING(s2)->len + 5;
    buf = ALLOCA_N(char, len);
    snprintf(buf, len, "%s or %s", RSTRING(s1)->ptr, RSTRING(s2)->ptr);
    rb_sys_fail(buf);
}

static VALUE
rb_file_s_link(klass, from, to)
    VALUE klass, from, to;
{
    SafeStringValue(from);
    SafeStringValue(to);

    if (link(StringValueCStr(from), StringValueCStr(to)) < 0) {
	sys_fail2(from, to);
    }
    return INT2FIX(0);
}

static VALUE
rb_file_s_symlink(klass, from, to)
    VALUE klass, from, to;
{
#ifdef HAVE_SYMLINK
    SafeStringValue(from);
    SafeStringValue(to);

    if (symlink(StringValueCStr(from), StringValueCStr(to)) < 0) {
	sys_fail2(from, to);
    }
    return INT2FIX(0);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static VALUE
rb_file_s_readlink(klass, path)
    VALUE klass, path;
{
#ifdef HAVE_READLINK
    char *buf;
    int size = 100;
    int rv;
    VALUE v;

    SafeStringValue(path);
    buf = xmalloc(size);
    while ((rv = readlink(StringValueCStr(path), buf, size)) == size) {
	size *= 2;
	buf = xrealloc(buf, size);
    }
    if (rv < 0) {
	free(buf);
	rb_sys_fail(RSTRING(path)->ptr);
    }
    v = rb_tainted_str_new(buf, rv);
    free(buf);

    return v;
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
rb_file_s_unlink(klass, args)
    VALUE klass, args;
{
    long n;

    rb_secure(2);
    n = apply2files(unlink_internal, args, 0);
    return LONG2FIX(n);
}

static VALUE
rb_file_s_rename(klass, from, to)
    VALUE klass, from, to;
{
    const char *src, *dst;
    SafeStringValue(from);
    SafeStringValue(to);

    src = StringValueCStr(from);
    dst = StringValueCStr(to);
    if (rename(src, dst) < 0) {
#if defined __CYGWIN__
	extern unsigned long __attribute__((stdcall)) GetLastError();
	errno = GetLastError(); /* This is a Cygwin bug */
#elif defined DOSISH && !defined _WIN32
	if (errno == EEXIST
#if defined (__EMX__)
	    || errno == EACCES
#endif
	    ) {
	    if (chmod(dst, 0666) == 0 &&
		unlink(dst) == 0 &&
		rename(src, dst) == 0)
		return INT2FIX(0);
	}
#endif
	sys_fail2(from, to);
    }

    return INT2FIX(0);
}

static VALUE
rb_file_s_umask(argc, argv)
    int argc;
    VALUE *argv;
{
    int omask = 0;

    rb_secure(2);
    if (argc == 0) {
	omask = umask(0);
	umask(omask);
    }
    else if (argc == 1) {
	omask = umask(NUM2INT(argv[0]));
    }
    else {
	rb_raise(rb_eArgError, "wrong number of argument");
    }
    return INT2FIX(omask);
}

#if defined DOSISH
#define DOSISH_UNC
#define isdirsep(x) ((x) == '/' || (x) == '\\')
#else
#define isdirsep(x) ((x) == '/')
#endif
#ifndef CharNext		/* defined as CharNext[AW] on Windows. */
# if defined(DJGPP)
#   define CharNext(p) ((p) + mblen(p, MB_CUR_MAX))
# else
#   define CharNext(p) ((p) + 1)
# endif
#endif

#ifdef __CYGWIN__
#undef DOSISH
#define DOSISH_UNC
#define DOSISH_DRIVE_LETTER
#endif

#ifdef DOSISH_DRIVE_LETTER
static inline int
has_drive_letter(buf)
    const char *buf;
{
    if (ISALPHA(buf[0]) && buf[1] == ':') {
	return 1;
    }
    else {
	return 0;
    }
}

static void
getcwdofdrv(drv, buf, len)
    int drv;
    char *buf;
    int len;
{
    char drive[4];
    char oldcwd[MAXPATHLEN+1];

    drive[0] = drv;
    drive[1] = ':';
    drive[2] = '\0';

    /* the only way that I know to get the current directory
       of a particular drive is to change chdir() to that drive,
       so save the old cwd before chdir()
    */
    getcwd(oldcwd, MAXPATHLEN);
    if (chdir(drive) == 0) {
	getcwd(buf, len);
	chdir(oldcwd);
    }
    else {
	/* perhaps the drive is not exist. we return only drive letter */
	strncpy(buf, drive, len);
    }
}
#endif

static inline char *
skiproot(path)
    const char *path;
{
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(path)) path += 2;
#endif
    while (isdirsep(*path)) path++;
    return (char *)path;
}

static inline char *
nextdirsep(s)
    const char *s;
{
    while (*s && !isdirsep(*s)) {
	s = CharNext(s);
    }
    return (char *)s;
}

#if defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER) 
static inline char *
skipprefix(path)
    const char *path;
{
#ifdef DOSISH_UNC
    if (isdirsep(path[0]) && isdirsep(path[1])) {
	if (*(path = nextdirsep(path + 2)))
	    path = nextdirsep(path + 1);
	return (char *)path;
    }
#endif
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(path))
	return (char *)(path + 2);
#endif
    return (char *)path;
}
#else
#define skipprefix(path) (path)
#endif

static char *
strrdirsep(path)
    const char *path;
{
    char *last = NULL;
    while (*path) {
	if (isdirsep(*path)) {
	    const char *tmp = path++;
	    while (isdirsep(*path)) path++;
	    if (!*path) break;
	    last = (char *)tmp;
	}
	else {
	    path = CharNext(path);
	}
    }
    return last;
}

static char *
chompdirsep(path)
    const char *path;
{
    while (*path) {
	if (isdirsep(*path)) {
	    const char *last = path++;
	    while (isdirsep(*path)) path++;
	    if (!*path) return (char *)last;
	}
	else {
	    path = CharNext(path);
	}
    }
    return (char *)path;
}

#define BUFCHECK(cond) do {\
    long bdiff = p - buf;\
    while (cond) {\
	buflen *= 2;\
    }\
    rb_str_resize(result, buflen);\
    buf = RSTRING(result)->ptr;\
    p = buf + bdiff;\
    pend = buf + buflen;\
} while (0)

#define BUFINIT() (\
    p = buf = RSTRING(result)->ptr,\
    buflen = RSTRING(result)->len,\
    pend = p + buflen)

#if !defined(TOLOWER)
#define TOLOWER(c) (ISUPPER(c) ? tolower(c) : (c))
#endif

static int is_absolute_path _((const char*));

static VALUE
file_expand_path(fname, dname, result)
    VALUE fname, dname, result;
{
    char *s, *buf, *b, *p, *pend, *root;
    long buflen, dirlen;
    int tainted;

    s = StringValuePtr(fname);
    BUFINIT();
    tainted = OBJ_TAINTED(fname);

    if (s[0] == '~') {
	if (isdirsep(s[1]) || s[1] == '\0') {
	    char *dir = getenv("HOME");

	    if (!dir) {
		rb_raise(rb_eArgError, "couldn't find HOME environment -- expanding `%s'", s);
	    }
	    dirlen = strlen(dir);
	    BUFCHECK(dirlen > buflen);
	    strcpy(buf, dir);
#if defined DOSISH || defined __CYGWIN__
	    for (p = buf; *p; p = CharNext(p)) {
		if (*p == '\\') {
		    *p = '/';
		}
	    }
#else
	    p = buf + strlen(dir);
#endif
	    s++;
	    tainted = 1;
	}
	else {
#ifdef HAVE_PWD_H
	    struct passwd *pwPtr;
	    s++;
#endif
	    s = nextdirsep(b = s);
	    BUFCHECK(bdiff + (s-b) >= buflen);
	    memcpy(p, b, s-b);
	    p += s-b;
	    *p = '\0';
#ifdef HAVE_PWD_H
	    pwPtr = getpwnam(buf);
	    if (!pwPtr) {
		endpwent();
		rb_raise(rb_eArgError, "user %s doesn't exist", buf);
	    }
	    dirlen = strlen(pwPtr->pw_dir);
	    BUFCHECK(dirlen > buflen);
	    strcpy(buf, pwPtr->pw_dir);
	    p = buf + strlen(pwPtr->pw_dir);
	    endpwent();
#endif
	}
    }
#ifdef DOSISH_DRIVE_LETTER
    /* skip drive letter */
    else if (has_drive_letter(s)) {
	if (isdirsep(s[2])) {
	    /* specified drive letter, and full path */
	    /* skip drive letter */
	    BUFCHECK(bdiff + 2 >= buflen);
	    memcpy(p, s, 2);
	    p += 2;
	    s += 2;
	}
	else {
	    /* specified drive, but not full path */
	    int same = 0;
	    if (!NIL_P(dname)) {
		file_expand_path(dname, Qnil, result);
		BUFINIT();
		if (has_drive_letter(p) && TOLOWER(p[0]) == TOLOWER(s[0])) {
		    /* ok, same drive */
		    same = 1;
		}
	    }
	    if (!same) {
		BUFCHECK(buflen < MAXPATHLEN);
		getcwdofdrv(*s, buf, MAXPATHLEN);
		tainted = 1;
	    }
	    p = chompdirsep(skiproot(buf));
	    s += 2;
	}
    }
#endif
    else if (!is_absolute_path(s)) {
	if (!NIL_P(dname)) {
	    file_expand_path(dname, Qnil, result);
	    BUFINIT();
	}
	else {
	    char *dir = my_getcwd();

	    tainted = 1;
	    dirlen = strlen(dir);
	    BUFCHECK(dirlen > buflen);
	    strcpy(buf, dir);
	    free(dir);
	}
#if defined DOSISH || defined __CYGWIN__
	if (isdirsep(*s)) {
	    /* specified full path, but not drive letter nor UNC */
	    /* we need to get the drive letter or UNC share name */
	    p = skipprefix(buf);
	}
	else
#endif
	    p = chompdirsep(skiproot(buf));
    }
    else {
	b = s;
	do s++; while (isdirsep(*s));
	p = buf + (s - b);
	BUFCHECK(bdiff >= buflen);
	memset(buf, '/', p - buf);
    }
    if (p > buf && p[-1] == '/')
	--p;
    else
	*p = '/';

    p[1] = 0;
    root = skipprefix(buf);

    b = s;
    while (*s) {
	switch (*s) {
	  case '.':
	    if (b == s++) {	/* beginning of path element */
		switch (*s) {
		  case '\0':
		    b = s;
		    break;
		  case '.':
		    if (*(s+1) == '\0' || isdirsep(*(s+1))) {
			/* We must go back to the parent */
			*p = '\0';
			if (!(b = strrdirsep(root))) {
			    *p = '/';
			}
			else {
			    p = b;
			}
			b = ++s;
		    }
		    break;
		  case '/':
#if defined DOSISH || defined __CYGWIN__
		  case '\\':
#endif
		    b = ++s;
		    break;
		  default:
		    /* ordinary path element, beginning don't move */
		    break;
		}
	    }
	    break;
	  case '/':
#if defined DOSISH || defined __CYGWIN__
	  case '\\':
#endif
	    if (s > b) {
		long rootdiff = root - buf;
		BUFCHECK(bdiff + (s-b+1) >= buflen);
		root = buf + rootdiff;
		memcpy(++p, b, s-b);
		p += s-b;
		*p = '/';
	    }
	    b = ++s;
	    break;
	  default:
	    s = CharNext(s);
	    break;
	}
    }

    if (s > b) {
	BUFCHECK(bdiff + (s-b) >= buflen);
	memcpy(++p, b, s-b);
	p += s-b;
    }
    if (p == skiproot(buf) - 1) p++;

    if (tainted) OBJ_TAINT(result);
    RSTRING(result)->len = p - buf;
    *p = '\0';
    return result;
}

VALUE
rb_file_expand_path(fname, dname)
    VALUE fname, dname;
{
    return file_expand_path(fname, dname, rb_str_new(0, MAXPATHLEN + 2));
}

VALUE
rb_file_s_expand_path(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, dname;

    if (argc == 1) {
	return rb_file_expand_path(argv[0], Qnil);
    }
    rb_scan_args(argc, argv, "11", &fname, &dname);

    return rb_file_expand_path(fname, dname);
}

static int
rmext(p, e)
    const char *p, *e;
{
    int l1, l2;

    if (!e) return 0;

    l1 = chompdirsep(p) - p;
    l2 = strlen(e);
    if (l2 == 2 && e[1] == '*') {
	e = strrchr(p, *e);
	if (!e) return 0;
	return e - p;
    }
    if (l1 < l2) return l1;

    if (strncmp(p+l1-l2, e, l2) == 0) {
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
    char *name, *p, *ext = NULL;
    int f;

    if (rb_scan_args(argc, argv, "11", &fname, &fext) == 2) {
	ext = StringValueCStr(fext);
    }
    StringValue(fname);
    if (RSTRING(fname)->len == 0 || !*(name = RSTRING(fname)->ptr))
	return fname;
    if (!*(name = skiproot(name))) {
	p = name - 1;
	f = 1;
#ifdef DOSISH_DRIVE_LETTER
	if (*p == ':') {
	    p++;
	    f = 0;
	}
#endif
    }
    else if (!(p = strrdirsep(name))) {
	if (NIL_P(fext) || !(f = rmext(name, ext))) {
	    f = chompdirsep(name) - name;
	    if (f == RSTRING(fname)->len) return fname;
	}
	p = name;
    }
    else {
	while (isdirsep(*p)) p++; /* skip last / */
	if (NIL_P(fext) || !(f = rmext(p, ext))) {
	    f = chompdirsep(p) - p;
	}
    }
    basename = rb_str_new(p, f);
    OBJ_INFECT(basename, fname);
    return basename;
}

static VALUE
rb_file_s_dirname(klass, fname)
    VALUE klass, fname;
{
    char *name, *root, *p;
    VALUE dirname;

    name = StringValueCStr(fname);
    root = skiproot(name);
#ifdef DOSISH_UNC
    if (root > name + 2 && isdirsep(*name))
	name = root - 2;
#else
    if (root > name + 1)
	name = root - 1;
#endif
    p = strrdirsep(root);
    if (!p) {
	p = root;
    }
    if (p == name)
	return rb_str_new2(".");
    dirname = rb_str_new(name, p - name);
#ifdef DOSISH_DRIVE_LETTER
    if (root == name + 2 && name[1] == ':')
	rb_str_cat(dirname, ".", 1);
#endif
    OBJ_INFECT(dirname, fname);
    return dirname;
}

static VALUE
rb_file_s_extname(klass, fname)
    VALUE klass, fname;
{
    char *name, *p, *e;
    VALUE extname;

    name = StringValueCStr(fname);
    p = strrdirsep(name);	/* get the last path component */
    if (!p)
 	p = name;
    else
 	p++;
 
     e = strrchr(p, '.');	/* get the last dot of the last component */
     if (!e || e == p)		/* no dot, or the only dot is first? */
	 return rb_str_new2("");
     extname = rb_str_new(e, chompdirsep(e) - e);	/* keep the dot, too! */
     OBJ_INFECT(extname, fname);
     return extname;
}

static VALUE
rb_file_s_split(klass, path)
    VALUE klass, path;
{
    StringValue(path);		/* get rid of converting twice */
    return rb_assoc_new(rb_file_s_dirname(Qnil, path), rb_file_s_basename(1,&path));
}

static VALUE separator;

static VALUE rb_file_join _((VALUE ary, VALUE sep));

static VALUE
file_inspect_join(ary, arg)
    VALUE ary;
    VALUE *arg;
{
    return rb_file_join(arg[0], arg[1]);
}

static VALUE
rb_file_join(ary, sep)
    VALUE ary, sep;
{
    long len, i;
    int taint = 0;
    VALUE result, tmp;
    char *name;

    if (RARRAY(ary)->len == 0) return rb_str_new(0, 0);
    if (OBJ_TAINTED(ary)) taint = 1;
    if (OBJ_TAINTED(sep)) taint = 1;

    len = 1;
    for (i=0; i<RARRAY(ary)->len; i++) {
	if (TYPE(RARRAY(ary)->ptr[i]) == T_STRING) {
	    len += RSTRING(RARRAY(ary)->ptr[i])->len;
	}
	else {
	    len += 10;
	}
    }
    if (!NIL_P(sep) && TYPE(sep) == T_STRING) {
	len += RSTRING(sep)->len * RARRAY(ary)->len - 1;
    }
    result = rb_str_buf_new(len);
    for (i=0; i<RARRAY(ary)->len; i++) {
	tmp = RARRAY(ary)->ptr[i];
	switch (TYPE(tmp)) {
	  case T_STRING:
	    break;
	  case T_ARRAY:
	    if (rb_inspecting_p(tmp)) {
		tmp = rb_str_new2("[...]");
	    }
	    else {
		VALUE args[2];

		args[0] = tmp;
		args[1] = sep;
		tmp = rb_protect_inspect(file_inspect_join, ary, (VALUE)args);
	    }
	    break;
	  default:
	    tmp = rb_obj_as_string(tmp);
	}
	name = StringValueCStr(result);
	if (i > 0 && !NIL_P(sep) && !*chompdirsep(name))
	    rb_str_buf_append(result, sep);
	rb_str_buf_append(result, tmp);
	if (OBJ_TAINTED(tmp)) taint = 1;
    }

    if (taint) OBJ_TAINT(result);
    return result;
}

static VALUE
rb_file_s_join(klass, args)
    VALUE klass, args;
{
    return rb_file_join(args, separator);
}

static VALUE
rb_file_s_truncate(klass, path, len)
    VALUE klass, path, len;
{
    rb_secure(2);
    SafeStringValue(path);

#ifdef HAVE_TRUNCATE
    if (truncate(StringValueCStr(path), NUM2OFFT(len)) < 0)
	rb_sys_fail(RSTRING(path)->ptr);
#else
# ifdef HAVE_CHSIZE
    {
	int tmpfd;

#  ifdef _WIN32
	if ((tmpfd = open(StringValueCStr(path), O_RDWR)) < 0) {
	    rb_sys_fail(RSTRING(path)->ptr);
	}
#  else
	if ((tmpfd = open(StringValueCStr(path), 0)) < 0) {
	    rb_sys_fail(RSTRING(path)->ptr);
	}
#  endif
	if (chsize(tmpfd, NUM2OFFT(len)) < 0) {
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

    rb_secure(2);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "not opened for writing");
    }
#ifdef HAVE_TRUNCATE
    if (ftruncate(fileno(fptr->f), NUM2OFFT(len)) < 0)
	rb_sys_fail(fptr->path);
#else
# ifdef HAVE_CHSIZE
    if (chsize(fileno(fptr->f), NUM2OFFT(len)) < 0)
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

#if 0
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
          case EAGAIN:
          case EACCES:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
	  case EWOULDBLOCK:
#endif
	    rb_thread_polling();	/* busy wait */
	    rb_io_check_closed(fptr);
            continue;
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
#ifndef __CHECKER__
    OpenFile *fptr;
    int ret;

    rb_secure(2);
    GetOpenFile(obj, fptr);

    if (fptr->mode & FMODE_WRITABLE) {
	fflush(GetWriteFile(fptr));
    }
  retry:
    TRAP_BEG;
    ret = flock(fileno(fptr->f), NUM2INT(operation));
    TRAP_END;
    if (ret < 0) {
        switch (errno) {
          case EAGAIN:
          case EACCES:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
          case EWOULDBLOCK:
#endif
              return Qfalse;
	  case EINTR:
#if defined(ERESTART)
	  case ERESTART:
#endif
	    goto retry;
        }
	rb_sys_fail(fptr->path);
    }
#endif
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
    if (n != argc) rb_raise(rb_eArgError, "wrong number of arguments(%d for %d)", argc, n);
    for (i=1; i<n; i++) {
	switch (TYPE(argv[i])) {
	  case T_STRING:
	  default:
	    SafeStringValue(argv[i]);
	    break;
	  case T_FILE:
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

    if (argc == 0) rb_raise(rb_eArgError, "wrong number of arguments");
#if 0 /* 1.7 behavior? */
    if (argc == 1) {
	return RTEST(argv[0]) ? Qtrue : Qfalse;
    }
#endif
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

static VALUE rb_stat_s_alloc _((VALUE));
static VALUE
rb_stat_s_alloc(klass)
    VALUE klass;
{
    return stat_new_0(klass, 0);
}

static VALUE
rb_stat_init(obj, fname)
    VALUE obj, fname;
{
    struct stat st, *nst;

    SafeStringValue(fname);

    if (stat(StringValueCStr(fname), &st) == -1) {
	rb_sys_fail(RSTRING(fname)->ptr);
    }
    if (DATA_PTR(obj)) {
	free(DATA_PTR(obj));
	DATA_PTR(obj) = NULL;
    }
    nst = ALLOC(struct stat);
    *nst = st;
    DATA_PTR(obj) = nst;

    return Qnil;
}

static VALUE
rb_stat_init_copy(copy, orig)
    VALUE copy, orig;
{
    struct stat *nst;

    if (copy == orig) return orig;
    rb_check_frozen(copy);
    /* need better argument type check */
    if (!rb_obj_is_instance_of(orig, rb_obj_class(copy))) {
	rb_raise(rb_eTypeError, "wrong argument class");
    }
    if (DATA_PTR(copy)) {
	free(DATA_PTR(copy));
	DATA_PTR(copy) = 0;
    }
    if (DATA_PTR(orig)) {
	nst = ALLOC(struct stat);
	*nst = *(struct stat*)DATA_PTR(orig);
	DATA_PTR(copy) = nst;
    }

    return copy;
}

static VALUE
rb_stat_ftype(obj)
    VALUE obj;
{
    return rb_file_ftype(get_stat(obj));
}

static VALUE
rb_stat_d(obj)
    VALUE obj;
{
    if (S_ISDIR(get_stat(obj)->st_mode)) return Qtrue;
    return Qfalse;
}

static VALUE
rb_stat_p(obj)
    VALUE obj;
{
#ifdef S_IFIFO
    if (S_ISFIFO(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

static VALUE
rb_stat_l(obj)
    VALUE obj;
{
#ifdef S_ISLNK
    if (S_ISLNK(get_stat(obj)->st_mode)) return Qtrue;
#endif
    return Qfalse;
}

static VALUE
rb_stat_S(obj)
    VALUE obj;
{
#ifdef S_ISSOCK
    if (S_ISSOCK(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

static VALUE
rb_stat_b(obj)
    VALUE obj;
{
#ifdef S_ISBLK
    if (S_ISBLK(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

static VALUE
rb_stat_c(obj)
    VALUE obj;
{
    if (S_ISCHR(get_stat(obj)->st_mode)) return Qtrue;

    return Qfalse;
}

static VALUE
rb_stat_owned(obj)
    VALUE obj;
{
    if (get_stat(obj)->st_uid == geteuid()) return Qtrue;
    return Qfalse;
}

static VALUE
rb_stat_rowned(obj)
    VALUE obj;
{
    if (get_stat(obj)->st_uid == getuid()) return Qtrue;
    return Qfalse;
}

static VALUE
rb_stat_grpowned(obj)
    VALUE obj;
{
#ifndef _WIN32
    if (get_stat(obj)->st_gid == getegid()) return Qtrue;
#endif
    return Qfalse;
}

static VALUE
rb_stat_r(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef S_IRUSR
    if (rb_stat_owned(obj))
	return st->st_mode & S_IRUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IRGRP
    if (rb_stat_grpowned(obj))
	return st->st_mode & S_IRGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IROTH
    if (!(st->st_mode & S_IROTH)) return Qfalse;
#endif
    return Qtrue;
}

static VALUE
rb_stat_R(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef S_IRUSR
    if (rb_stat_rowned(obj))
	return st->st_mode & S_IRUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IRGRP
    if (group_member(get_stat(obj)->st_gid))
	return st->st_mode & S_IRGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IROTH
    if (!(st->st_mode & S_IROTH)) return Qfalse;
#endif
    return Qtrue;
}

static VALUE
rb_stat_w(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef S_IWUSR
    if (rb_stat_owned(obj))
	return st->st_mode & S_IWUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IWGRP
    if (rb_stat_grpowned(obj))
	return st->st_mode & S_IWGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IWOTH
    if (!(st->st_mode & S_IWOTH)) return Qfalse;
#endif
    return Qtrue;
}

static VALUE
rb_stat_W(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef S_IWUSR
    if (rb_stat_rowned(obj))
	return st->st_mode & S_IWUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IWGRP
    if (group_member(get_stat(obj)->st_gid))
	return st->st_mode & S_IWGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IWOTH
    if (!(st->st_mode & S_IWOTH)) return Qfalse;
#endif
    return Qtrue;
}

static VALUE
rb_stat_x(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef S_IXUSR
    if (rb_stat_owned(obj))
	return st->st_mode & S_IXUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IXGRP
    if (rb_stat_grpowned(obj))
	return st->st_mode & S_IXGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IXOTH
    if (!(st->st_mode & S_IXOTH)) return Qfalse;
#endif
    return Qtrue;
}

static VALUE
rb_stat_X(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef S_IXUSR
    if (rb_stat_rowned(obj))
	return st->st_mode & S_IXUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IXGRP
    if (group_member(get_stat(obj)->st_gid))
	return st->st_mode & S_IXGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IXOTH
    if (!(st->st_mode & S_IXOTH)) return Qfalse;
#endif
    return Qtrue;
}

static VALUE
rb_stat_f(obj)
    VALUE obj;
{
    if (S_ISREG(get_stat(obj)->st_mode)) return Qtrue;
    return Qfalse;
}

static VALUE
rb_stat_z(obj)
    VALUE obj;
{
    if (get_stat(obj)->st_size == 0) return Qtrue;
    return Qfalse;
}

static VALUE
rb_stat_s(obj)
    VALUE obj;
{
    off_t size = get_stat(obj)->st_size;

    if (size == 0) return Qnil;
    return OFFT2NUM(size);
}

static VALUE
rb_stat_suid(obj)
    VALUE obj;
{
#ifdef S_ISUID
    if (get_stat(obj)->st_mode & S_ISUID) return Qtrue;
#endif
    return Qfalse;
}

static VALUE
rb_stat_sgid(obj)
    VALUE obj;
{
#ifdef S_ISGID
    if (get_stat(obj)->st_mode & S_ISGID) return Qtrue;
#endif
    return Qfalse;
}

static VALUE
rb_stat_sticky(obj)
    VALUE obj;
{
#ifdef S_ISVTX
    if (get_stat(obj)->st_mode & S_ISVTX) return Qtrue;
#endif
    return Qfalse;
}

static VALUE rb_mFConst;

void
rb_file_const(name, value)
    const char *name;
    VALUE value;
{
    rb_define_const(rb_mFConst, name, value);
}

static int
is_absolute_path(path)
    const char *path;
{
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(path) && isdirsep(path[2])) return 1;
#endif
#ifdef DOSISH_UNC
    if (isdirsep(path[0]) && isdirsep(path[1])) return 1;
#endif
#ifndef DOSISH
    if (path[0] == '/') return 1;
#endif
    return 0;
}

#ifndef DOSISH
static int
path_check_1(path)
     VALUE path;
{
    struct stat st;
    char *p0 = StringValueCStr(path);
    char *p = 0, *s;

    if (!is_absolute_path(p0)) {
	char *buf = my_getcwd();
	VALUE newpath;

	newpath = rb_str_new2(buf);
	free(buf);

	rb_str_cat2(newpath, "/");
	rb_str_cat2(newpath, p0);
	return path_check_1(newpath);
    }
    for (;;) {
#ifndef S_IWOTH
# define S_IWOTH 002
#endif
	if (stat(p0, &st) == 0 && S_ISDIR(st.st_mode) && (st.st_mode & S_IWOTH)
#ifdef S_ISVTX
	    && (!p || !(st.st_mode & S_ISVTX))
#endif
	    ) {
	    rb_warn("Insecure world writable dir %s, mode 0%o", p0, st.st_mode);
	    if (p) *p = '/';
	    return 0;
	}
	s = strrdirsep(p0);
	if (p) *p = '/';
	if (!s || s == p0) return 1;
	p = s;
	*p = '\0';
    }
}
#endif

int
rb_path_check(path)
    char *path;
{
#ifndef DOSISH
    char *p0, *p, *pend;
    const char sep = PATH_SEP_CHAR;

    if (!path) return 1;

    pend = path + strlen(path);
    p0 = path;
    p = strchr(path, sep);
    if (!p) p = pend;

    for (;;) {
	if (!path_check_1(rb_str_new(p0, p - p0))) {
	    return 0;		/* not safe */
	}
	p0 = p + 1;
	if (p0 > pend) break;
	p = strchr(p0, sep);
	if (!p) p = pend;
    }
#endif
    return 1;
}

#if defined(__MACOS__) || defined(riscos)
static int
is_macos_native_path(path)
    const char *path;
{
    if (strchr(path, ':')) return 1;
    return 0;
}
#endif

static int
file_load_ok(file)
    char *file;
{
    FILE *f;

    if (!file) return 0;
    f = fopen(file, "r");
    if (f == NULL) return 0;
    fclose(f);
    return 1;
}

extern VALUE rb_load_path;

int
rb_find_file_ext(filep, ext)
    VALUE *filep;
    const char * const *ext;
{
    char *path, *found;
    char *f = RSTRING(*filep)->ptr;
    VALUE fname;
    long i, j;

    if (f[0] == '~') {
	fname = rb_file_expand_path(*filep, Qnil);
	if (rb_safe_level() >= 2 && OBJ_TAINTED(fname)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
	}
	f = StringValueCStr(fname);
	*filep = fname;
    }

    if (is_absolute_path(f)) {
	for (i=0; ext[i]; i++) {
	    fname = rb_str_dup(*filep);
	    rb_str_cat2(fname, ext[i]);
	    if (file_load_ok(StringValueCStr(fname))) {
		*filep = fname;
		return i+1;
	    }
	}
	return 0;
    }

    if (!rb_load_path) return 0;

    Check_Type(rb_load_path, T_ARRAY);
    for (i=0;i<RARRAY(rb_load_path)->len;i++) {
	VALUE str = RARRAY(rb_load_path)->ptr[i];

	SafeStringValue(str);
	if (RSTRING(str)->len == 0) continue;
	path = RSTRING(str)->ptr;
	for (j=0; ext[j]; j++) {
	    fname = rb_str_dup(*filep);
	    rb_str_cat2(fname, ext[j]);
	    found = dln_find_file(StringValueCStr(fname), path);
	    if (found && file_load_ok(found)) {
		*filep = fname;
		return j+1;
	    }
	}
    }
    return 0;
}

VALUE
rb_find_file(path)
    VALUE path;
{
    VALUE tmp;
    char *f = StringValueCStr(path);
    char *lpath;

    if (f[0] == '~') {
	path = rb_file_expand_path(path, Qnil);
	if (rb_safe_level() >= 1 && OBJ_TAINTED(path)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe path %s", f);
	}
	f = StringValueCStr(path);
    }

#if defined(__MACOS__) || defined(riscos)
    if (is_macos_native_path(f)) {
	if (rb_safe_level() >= 1 && !rb_path_check(f)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
	}
	if (file_load_ok(f)) return path;
    }
#endif

    if (is_absolute_path(f)) {
	if (rb_safe_level() >= 1 && !rb_path_check(f)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
	}
	if (file_load_ok(f)) return path;
    }

    if (rb_safe_level() >= 4) {
	rb_raise(rb_eSecurityError, "loading from non-absolute path %s", f);
    }

    if (rb_load_path) {
	long i;

	Check_Type(rb_load_path, T_ARRAY);
	tmp = rb_ary_new();
	for (i=0;i<RARRAY(rb_load_path)->len;i++) {
	    VALUE str = RARRAY(rb_load_path)->ptr[i];
	    SafeStringValue(str);
	    if (RSTRING(str)->len > 0) {
		rb_ary_push(tmp, str);
	    }
	}
	tmp = rb_ary_join(tmp, rb_str_new2(PATH_SEP));
	if (RSTRING(tmp)->len == 0) {
	    lpath = 0;
	}
	else {
	    lpath = RSTRING(tmp)->ptr;
	    if (rb_safe_level() >= 1 && !rb_path_check(lpath)) {
		rb_raise(rb_eSecurityError, "loading from unsafe path %s", lpath);
	    }
	}
    }
    else {
	lpath = 0;
    }

    if (!lpath) {
	return 0;		/* no path, no load */
    }
    f = dln_find_file(f, lpath);
    if (rb_safe_level() >= 1 && !rb_path_check(f)) {
	rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
    }
    if (file_load_ok(f)) {
	return rb_str_new2(f);
    }
    return 0;
}

static void
define_filetest_function(name, func, argc)
    const char *name;
    VALUE (*func)();
    int argc;
{
    rb_define_module_function(rb_mFileTest, name, func, argc);
    rb_define_singleton_method(rb_cFile, name, func, argc);
}

void
Init_File()
{
    rb_mFileTest = rb_define_module("FileTest");
    rb_cFile = rb_define_class("File", rb_cIO);

    define_filetest_function("directory?", test_d, 1);
    define_filetest_function("exist?", test_e, 1);
    define_filetest_function("exists?", test_e, 1); /* temporary */
    define_filetest_function("readable?", test_r, 1);
    define_filetest_function("readable_real?", test_R, 1);
    define_filetest_function("writable?", test_w, 1);
    define_filetest_function("writable_real?", test_W, 1);
    define_filetest_function("executable?", test_x, 1);
    define_filetest_function("executable_real?", test_X, 1);
    define_filetest_function("file?", test_f, 1);
    define_filetest_function("zero?", test_z, 1);
    define_filetest_function("size?", test_s, 1);
    define_filetest_function("size", rb_file_s_size, 1);
    define_filetest_function("owned?", test_owned, 1);
    define_filetest_function("grpowned?", test_grpowned, 1);

    define_filetest_function("pipe?", test_p, 1);
    define_filetest_function("symlink?", test_l, 1);
    define_filetest_function("socket?", test_S, 1);

    define_filetest_function("blockdev?", test_b, 1);
    define_filetest_function("chardev?", test_c, 1);

    define_filetest_function("setuid?", test_suid, 1);
    define_filetest_function("setgid?", test_sgid, 1);
    define_filetest_function("sticky?", test_sticky, 1);

    rb_define_singleton_method(rb_cFile, "stat",  rb_file_s_stat, 1);
    rb_define_singleton_method(rb_cFile, "lstat", rb_file_s_lstat, 1);
    rb_define_singleton_method(rb_cFile, "ftype", rb_file_s_ftype, 1);

    rb_define_singleton_method(rb_cFile, "atime", rb_file_s_atime, 1);
    rb_define_singleton_method(rb_cFile, "mtime", rb_file_s_mtime, 1);
    rb_define_singleton_method(rb_cFile, "ctime", rb_file_s_ctime, 1);

    rb_define_singleton_method(rb_cFile, "utime", rb_file_s_utime, -1);
    rb_define_singleton_method(rb_cFile, "chmod", rb_file_s_chmod, -1);
    rb_define_singleton_method(rb_cFile, "chown", rb_file_s_chown, -1);
    rb_define_singleton_method(rb_cFile, "lchmod", rb_file_s_lchmod, -1);
    rb_define_singleton_method(rb_cFile, "lchown", rb_file_s_lchown, -1);

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
    rb_define_singleton_method(rb_cFile, "extname", rb_file_s_extname, 1);

    separator = rb_obj_freeze(rb_str_new2("/"));
    rb_define_const(rb_cFile, "Separator", separator);
    rb_define_const(rb_cFile, "SEPARATOR", separator);
    rb_define_singleton_method(rb_cFile, "split",  rb_file_s_split, 1);
    rb_define_singleton_method(rb_cFile, "join",   rb_file_s_join, -2);

#ifdef DOSISH
    rb_define_const(rb_cFile, "ALT_SEPARATOR", rb_obj_freeze(rb_str_new2("\\")));
#else
    rb_define_const(rb_cFile, "ALT_SEPARATOR", Qnil);
#endif
    rb_define_const(rb_cFile, "PATH_SEPARATOR", rb_obj_freeze(rb_str_new2(PATH_SEP)));

    rb_define_method(rb_cIO, "stat",  rb_io_stat, 0); /* this is IO's method */
    rb_define_method(rb_cFile, "lstat",  rb_file_lstat, 0);

    rb_define_method(rb_cFile, "atime", rb_file_atime, 0);
    rb_define_method(rb_cFile, "mtime", rb_file_mtime, 0);
    rb_define_method(rb_cFile, "ctime", rb_file_ctime, 0);

    rb_define_method(rb_cFile, "chmod", rb_file_chmod, 1);
    rb_define_method(rb_cFile, "chown", rb_file_chown, 2);
    rb_define_method(rb_cFile, "truncate", rb_file_truncate, 1);

    rb_define_method(rb_cFile, "flock", rb_file_flock, 1);

    rb_mFConst = rb_define_module_under(rb_cFile, "Constants");
    rb_include_module(rb_cIO, rb_mFConst);
    rb_file_const("LOCK_SH", INT2FIX(LOCK_SH));
    rb_file_const("LOCK_EX", INT2FIX(LOCK_EX));
    rb_file_const("LOCK_UN", INT2FIX(LOCK_UN));
    rb_file_const("LOCK_NB", INT2FIX(LOCK_NB));

    rb_define_method(rb_cFile, "path",  rb_file_path, 0);
    rb_define_global_function("test", rb_f_test, -1);

    rb_cStat = rb_define_class_under(rb_cFile, "Stat", rb_cObject);
    rb_define_alloc_func(rb_cStat,  rb_stat_s_alloc);
    rb_define_method(rb_cStat, "initialize", rb_stat_init, 1);
    rb_define_method(rb_cStat, "initialize_copy", rb_stat_init_copy, 1);

    rb_include_module(rb_cStat, rb_mComparable);

    rb_define_method(rb_cStat, "<=>", rb_stat_cmp, 1);

    rb_define_method(rb_cStat, "dev", rb_stat_dev, 0);
    rb_define_method(rb_cStat, "ino", rb_stat_ino, 0);
    rb_define_method(rb_cStat, "mode", rb_stat_mode, 0);
    rb_define_method(rb_cStat, "nlink", rb_stat_nlink, 0);
    rb_define_method(rb_cStat, "uid", rb_stat_uid, 0);
    rb_define_method(rb_cStat, "gid", rb_stat_gid, 0);
    rb_define_method(rb_cStat, "rdev", rb_stat_rdev, 0);
    rb_define_method(rb_cStat, "rdev_major", rb_stat_rdev_major, 0);
    rb_define_method(rb_cStat, "rdev_minor", rb_stat_rdev_minor, 0);
    rb_define_method(rb_cStat, "size", rb_stat_size, 0);
    rb_define_method(rb_cStat, "blksize", rb_stat_blksize, 0);
    rb_define_method(rb_cStat, "blocks", rb_stat_blocks, 0);
    rb_define_method(rb_cStat, "atime", rb_stat_atime, 0);
    rb_define_method(rb_cStat, "mtime", rb_stat_mtime, 0);
    rb_define_method(rb_cStat, "ctime", rb_stat_ctime, 0);

    rb_define_method(rb_cStat, "inspect", rb_stat_inspect, 0);

    rb_define_method(rb_cStat, "ftype", rb_stat_ftype, 0);

    rb_define_method(rb_cStat, "directory?",  rb_stat_d, 0);
    rb_define_method(rb_cStat, "readable?",  rb_stat_r, 0);
    rb_define_method(rb_cStat, "readable_real?",  rb_stat_R, 0);
    rb_define_method(rb_cStat, "writable?",  rb_stat_w, 0);
    rb_define_method(rb_cStat, "writable_real?",  rb_stat_W, 0);
    rb_define_method(rb_cStat, "executable?",  rb_stat_x, 0);
    rb_define_method(rb_cStat, "executable_real?",  rb_stat_X, 0);
    rb_define_method(rb_cStat, "file?",  rb_stat_f, 0);
    rb_define_method(rb_cStat, "zero?",  rb_stat_z, 0);
    rb_define_method(rb_cStat, "size?",  rb_stat_s, 0);
    rb_define_method(rb_cStat, "owned?",  rb_stat_owned, 0);
    rb_define_method(rb_cStat, "grpowned?",  rb_stat_grpowned, 0);

    rb_define_method(rb_cStat, "pipe?",  rb_stat_p, 0);
    rb_define_method(rb_cStat, "symlink?",  rb_stat_l, 0);
    rb_define_method(rb_cStat, "socket?",  rb_stat_S, 0);

    rb_define_method(rb_cStat, "blockdev?",  rb_stat_b, 0);
    rb_define_method(rb_cStat, "chardev?",  rb_stat_c, 0);

    rb_define_method(rb_cStat, "setuid?",  rb_stat_suid, 0);
    rb_define_method(rb_cStat, "setgid?",  rb_stat_sgid, 0);
    rb_define_method(rb_cStat, "sticky?",  rb_stat_sticky, 0);
}
