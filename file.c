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
#ifdef __CYGWIN__
#include <windows.h>
#include <sys/cygwin.h>
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

#if defined(HAVE_FCNTL_H)
#include <fcntl.h>
#endif

#if !defined HAVE_LSTAT && !defined lstat
#define lstat stat
#endif
#if !HAVE_FSEEKO && !defined(fseeko)
# define fseeko  fseek
#endif

#ifdef __BEOS__ /* should not change ID if -1 */
static int
be_chown(const char *path, uid_t owner, gid_t group)
{
    if (owner == -1 || group == -1) {
	struct stat st;
	if (stat(path, &st) < 0) return -1;
	if (owner == -1) owner = st.st_uid;
	if (group == -1) group = st.st_gid;
    }
    return chown(path, owner, group);
}
#define chown be_chown
static int
be_fchown(int fd, uid_t owner, gid_t group)
{
    if (owner == -1 || group == -1) {
	struct stat st;
	if (fstat(fd, &st) < 0) return -1;
	if (owner == -1) owner = st.st_uid;
	if (group == -1) group = st.st_gid;
    }
    return fchown(fd, owner, group);
}
#define fchown be_fchown
#endif /* __BEOS__ */

VALUE rb_cFile;
VALUE rb_mFileTest;
VALUE rb_cStat;

static long apply2files _((void (*)(const char *, void *), VALUE, void *));
static long
apply2files(func, vargs, arg)
    void (*func)_((const char *, void *));
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

/*
 *  call-seq:
 *     file.path -> filename
 *
 *  Returns the pathname used to create <i>file</i> as a string. Does
 *  not normalize the name.
 *
 *     File.new("testfile").path               #=> "testfile"
 *     File.new("/tmp/../tmp/xxx", "w").path   #=> "/tmp/../tmp/xxx"
 *
 */

static VALUE
rb_file_path(obj)
    VALUE obj;
{
    rb_io_t *fptr;

    fptr = RFILE(rb_io_taint_check(obj))->fptr;
    rb_io_check_initialized(fptr);
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

/*
 *  call-seq:
 *     stat <=> other_stat    => -1, 0, +1 or nil
 *
 *  Compares <code>File::Stat</code> objects by comparing their
 *  respective modification times.
 *
 *     f1 = File.new("f1", "w")
 *     sleep 1
 *     f2 = File.new("f2", "w")
 *     f1.stat <=> f2.stat   #=> -1
 */

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

static VALUE rb_stat_dev _((VALUE));
static VALUE rb_stat_ino _((VALUE));
static VALUE rb_stat_mode _((VALUE));
static VALUE rb_stat_nlink _((VALUE));
static VALUE rb_stat_uid _((VALUE));
static VALUE rb_stat_gid _((VALUE));
static VALUE rb_stat_rdev _((VALUE));
static VALUE rb_stat_size _((VALUE));
static VALUE rb_stat_blksize _((VALUE));
static VALUE rb_stat_blocks _((VALUE));
static VALUE rb_stat_atime _((VALUE));
static VALUE rb_stat_mtime _((VALUE));
static VALUE rb_stat_ctime _((VALUE));

#define ST2UINT(val) ((val) & ~(~1UL << (sizeof(val) * CHAR_BIT - 1)))

/*
 *  call-seq:
 *     stat.dev    => fixnum
 *
 *  Returns an integer representing the device on which <i>stat</i>
 *  resides.
 *
 *     File.stat("testfile").dev   #=> 774
 */

static VALUE
rb_stat_dev(self)
    VALUE self;
{
    return INT2NUM(get_stat(self)->st_dev);
}

/*
 *  call-seq:
 *     stat.dev_major   => fixnum
 *
 *  Returns the major part of <code>File_Stat#dev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").dev_major   #=> 2
 *     File.stat("/dev/tty").dev_major   #=> 5
 */

static VALUE
rb_stat_dev_major(self)
    VALUE self;
{
#if defined(major)
    long dev = get_stat(self)->st_dev;
    return ULONG2NUM(major(dev));
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.dev_minor   => fixnum
 *
 *  Returns the minor part of <code>File_Stat#dev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").dev_minor   #=> 1
 *     File.stat("/dev/tty").dev_minor   #=> 0
 */

static VALUE
rb_stat_dev_minor(self)
    VALUE self;
{
#if defined(minor)
    long dev = get_stat(self)->st_dev;
    return ULONG2NUM(minor(dev));
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.ino   => fixnum
 *
 *  Returns the inode number for <i>stat</i>.
 *
 *     File.stat("testfile").ino   #=> 1083669
 *
 */

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

/*
 *  call-seq:
 *     stat.mode   => fixnum
 *
 *  Returns an integer representing the permission bits of
 *  <i>stat</i>. The meaning of the bits is platform dependent; on
 *  Unix systems, see <code>stat(2)</code>.
 *
 *     File.chmod(0644, "testfile")   #=> 1
 *     s = File.stat("testfile")
 *     sprintf("%o", s.mode)          #=> "100644"
 */

static VALUE
rb_stat_mode(self)
    VALUE self;
{
    return UINT2NUM(ST2UINT(get_stat(self)->st_mode));
}

/*
 *  call-seq:
 *     stat.nlink   => fixnum
 *
 *  Returns the number of hard links to <i>stat</i>.
 *
 *     File.stat("testfile").nlink             #=> 1
 *     File.link("testfile", "testfile.bak")   #=> 0
 *     File.stat("testfile").nlink             #=> 2
 *
 */

static VALUE
rb_stat_nlink(self)
    VALUE self;
{
    return UINT2NUM(get_stat(self)->st_nlink);
}

/*
 *  call-seq:
 *     stat.uid    => fixnum
 *
 *  Returns the numeric user id of the owner of <i>stat</i>.
 *
 *     File.stat("testfile").uid   #=> 501
 *
 */

static VALUE
rb_stat_uid(self)
    VALUE self;
{
    return UINT2NUM(get_stat(self)->st_uid);
}

/*
 *  call-seq:
 *     stat.gid   => fixnum
 *
 *  Returns the numeric group id of the owner of <i>stat</i>.
 *
 *     File.stat("testfile").gid   #=> 500
 *
 */

static VALUE
rb_stat_gid(self)
    VALUE self;
{
    return UINT2NUM(get_stat(self)->st_gid);
}

/*
 *  call-seq:
 *     stat.rdev   =>  fixnum or nil
 *
 *  Returns an integer representing the device type on which
 *  <i>stat</i> resides. Returns <code>nil</code> if the operating
 *  system doesn't support this feature.
 *
 *     File.stat("/dev/fd1").rdev   #=> 513
 *     File.stat("/dev/tty").rdev   #=> 1280
 */

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

/*
 *  call-seq:
 *     stat.rdev_major   => fixnum
 *
 *  Returns the major part of <code>File_Stat#rdev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").rdev_major   #=> 2
 *     File.stat("/dev/tty").rdev_major   #=> 5
 */

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

/*
 *  call-seq:
 *     stat.rdev_minor   => fixnum
 *
 *  Returns the minor part of <code>File_Stat#rdev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").rdev_minor   #=> 1
 *     File.stat("/dev/tty").rdev_minor   #=> 0
 */

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

/*
 *  call-seq:
 *     stat.size    => fixnum
 *
 *  Returns the size of <i>stat</i> in bytes.
 *
 *     File.stat("testfile").size   #=> 66
 */

static VALUE
rb_stat_size(self)
    VALUE self;
{
    return OFFT2NUM(get_stat(self)->st_size);
}

/*
 *  call-seq:
 *     stat.blksize   => integer or nil
 *
 *  Returns the native file system's block size. Will return <code>nil</code>
 *  on platforms that don't support this information.
 *
 *     File.stat("testfile").blksize   #=> 4096
 *
 */

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

/*
 *  call-seq:
 *     stat.blocks    => integer or nil
 *
 *  Returns the number of native file system blocks allocated for this
 *  file, or <code>nil</code> if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("testfile").blocks   #=> 2
 */

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

/*
 *  call-seq:
 *     stat.atime   => time
 *
 *  Returns the last access time for this file as an object of class
 *  <code>Time</code>.
 *
 *     File.stat("testfile").atime   #=> Wed Dec 31 18:00:00 CST 1969
 *
 */

static VALUE
rb_stat_atime(self)
    VALUE self;
{
    return rb_time_new(get_stat(self)->st_atime, 0);
}

/*
 *  call-seq:
 *     stat.mtime -> aTime
 *
 *  Returns the modification time of <i>stat</i>.
 *
 *     File.stat("testfile").mtime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_stat_mtime(self)
    VALUE self;
{
    return rb_time_new(get_stat(self)->st_mtime, 0);
}

/*
 *  call-seq:
 *     stat.ctime -> aTime
 *
 *  Returns the change time for <i>stat</i> (that is, the time
 *  directory information about the file was changed, not the file
 *  itself).
 *
 *     File.stat("testfile").ctime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_stat_ctime(self)
    VALUE self;
{
    return rb_time_new(get_stat(self)->st_ctime, 0);
}

/*
 * call-seq:
 *   stat.inspect  =>  string
 *
 * Produce a nicely formatted description of <i>stat</i>.
 *
 *   File.stat("/etc/passwd").inspect
 *      #=> "#<File::Stat dev=0xe000005, ino=1078078, mode=0100644,
 *           nlink=1, uid=0, gid=0, rdev=0x0, size=1374, blksize=4096,
 *           blocks=8, atime=Wed Dec 10 10:16:12 CST 2003,
 *           mtime=Fri Sep 12 15:41:41 CDT 2003,
 *           ctime=Mon Oct 27 11:20:27 CST 2003>"
 */

static VALUE
rb_stat_inspect(self)
    VALUE self;
{
    VALUE str;
    int i;
    static const struct {
	const char *name;
	VALUE (*func)_((VALUE));
    } member[] = {
	{"dev",	    rb_stat_dev},
	{"ino",	    rb_stat_ino},
	{"mode",    rb_stat_mode},
	{"nlink",   rb_stat_nlink},
	{"uid",	    rb_stat_uid},
	{"gid",	    rb_stat_gid},
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

	    sprintf(buf, "0%lo", NUM2ULONG(v));
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
	rb_io_t *fptr;

	rb_secure(2);
	GetOpenFile(tmp, fptr);
	return fstat(fileno(fptr->f), st);
    }
    SafeStringValue(file);
    return stat(StringValueCStr(file), st);
}

#ifdef _WIN32
static HANDLE
w32_io_info(file, st)
    VALUE *file;
    BY_HANDLE_FILE_INFORMATION *st;
{
    VALUE tmp;
    HANDLE f, ret = 0;

    tmp = rb_check_convert_type(*file, T_FILE, "IO", "to_io");
    if (!NIL_P(tmp)) {
	rb_io_t *fptr;

	GetOpenFile(tmp, fptr);
	f = (HANDLE)rb_w32_get_osfhandle(fileno(fptr->f));
	if (f == (HANDLE)-1) return INVALID_HANDLE_VALUE;
    }
    else {
	SafeStringValue(*file);
	f = CreateFile(StringValueCStr(*file), 0,
	               FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
	               rb_w32_iswin95() ? 0 : FILE_FLAG_BACKUP_SEMANTICS, NULL);
	if (f == INVALID_HANDLE_VALUE) return f;
	ret = f;
    }
    if (GetFileType(f) == FILE_TYPE_DISK) {
	ZeroMemory(st, sizeof(*st));
	if (GetFileInformationByHandle(f, st)) return ret;
    }
    if (ret) CloseHandle(ret);
    return INVALID_HANDLE_VALUE;
}
#endif

/*
 *  call-seq:
 *     File.stat(file_name)   =>  stat
 *
 *  Returns a <code>File::Stat</code> object for the named file (see
 *  <code>File::Stat</code>).
 *
 *     File.stat("testfile").mtime   #=> Tue Apr 08 12:58:04 CDT 2003
 *
 */

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

/*
 *  call-seq:
 *     ios.stat    => stat
 *
 *  Returns status information for <em>ios</em> as an object of type
 *  <code>File::Stat</code>.
 *
 *     f = File.new("testfile")
 *     s = f.stat
 *     "%o" % s.mode   #=> "100644"
 *     s.blksize       #=> 4096
 *     s.atime         #=> Wed Apr 09 08:53:54 CDT 2003
 *
 */

static VALUE
rb_io_stat(obj)
    VALUE obj;
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return stat_new(&st);
}

/*
 *  call-seq:
 *     File.lstat(file_name)   => stat
 *
 *  Same as <code>File::stat</code>, but does not follow the last symbolic
 *  link. Instead, reports on the link itself.
 *
 *     File.symlink("testfile", "link2test")   #=> 0
 *     File.stat("testfile").size              #=> 66
 *     File.lstat("link2test").size            #=> 8
 *     File.stat("link2test").size             #=> 66
 *
 */

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

/*
 *  call-seq:
 *     file.lstat   =>  stat
 *
 *  Same as <code>IO#stat</code>, but does not follow the last symbolic
 *  link. Instead, reports on the link itself.
 *
 *     File.symlink("testfile", "link2test")   #=> 0
 *     File.stat("testfile").size              #=> 66
 *     f = File.new("link2test")
 *     f.lstat.size                            #=> 8
 *     f.stat.size                             #=> 66
 */

static VALUE
rb_file_lstat(obj)
    VALUE obj;
{
#ifdef HAVE_LSTAT
    rb_io_t *fptr;
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
rb_group_member(gid)
    GETGROUPS_T gid;
{
#ifndef _WIN32
    if (getgid() == gid || getegid() == gid)
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

#if defined(S_IXGRP) && !defined(_WIN32) && !defined(__CYGWIN__)
#define USE_GETEUID 1
#endif

#ifndef HAVE_EACCESS
int
eaccess(path, mode)
     const char *path;
     int mode;
{
#ifdef USE_GETEUID
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
    else if (rb_group_member(st.st_gid))
	mode <<= 3;

    if ((st.st_mode & mode) == mode) return 0;

    return -1;
#else
# if defined(_MSC_VER) || defined(__MINGW32__)
    mode &= ~1;
# endif
    return access(path, mode);
#endif
}
#endif


/*
 * Document-class: FileTest
 *
 *  <code>FileTest</code> implements file test operations similar to
 *  those used in <code>File::Stat</code>. It exists as a standalone
 *  module, and its methods are also insinuated into the <code>File</code>
 *  class. (Note that this is not done by inclusion: the interpreter cheats).
 *
 */

/*
 * call-seq:
 *   File.directory?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file is a directory,
 * <code>false</code> otherwise.
 *
 *    File.directory?(".")
 */

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

/*
 * call-seq:
 *   File.pipe?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file is a pipe.
 */

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

/*
 * call-seq:
 *   File.symlink?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file is a symbolic link.
 */

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

    SafeStringValue(fname);
    if (lstat(StringValueCStr(fname), &st) < 0) return Qfalse;
    if (S_ISLNK(st.st_mode)) return Qtrue;
#endif

    return Qfalse;
}

/*
 * call-seq:
 *   File.socket?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file is a socket.
 */

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

/*
 * call-seq:
 *   File.blockdev?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file is a block device.
 */

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

/*
 * call-seq:
 *   File.chardev?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file is a character device.
 */
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

/*
 * call-seq:
 *    File.exist?(file_name)    =>  true or false
 *    File.exists?(file_name)   =>  true or false    (obsolete)
 *
 * Return <code>true</code> if the named file exists.
 */

static VALUE
test_e(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    File.readable?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file is readable by the effective
 * user id of this process.
 */

static VALUE
test_r(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (eaccess(StringValueCStr(fname), R_OK) < 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    File.readable_real?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file is readable by the real
 * user id of this process.
 */

static VALUE
test_R(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (access(StringValueCStr(fname), R_OK) < 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    File.writable?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file is writable by the effective
 * user id of this process.
 */

static VALUE
test_w(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (eaccess(StringValueCStr(fname), W_OK) < 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    File.writable_real?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file is writable by the real
 * user id of this process.
 */

static VALUE
test_W(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (access(StringValueCStr(fname), W_OK) < 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    File.executable?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file is executable by the effective
 * user id of this process.
 */

static VALUE
test_x(obj, fname)
    VALUE obj, fname;
{
    SafeStringValue(fname);
    if (eaccess(StringValueCStr(fname), X_OK) < 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    File.executable_real?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file is executable by the real
 * user id of this process.
 */

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

/*
 * call-seq:
 *    File.file?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file exists and is a
 * regular file.
 */

static VALUE
test_f(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISREG(st.st_mode)) return Qtrue;
    return Qfalse;
}

/*
 * call-seq:
 *    File.zero?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file exists and has
 * a zero size.
 */

static VALUE
test_z(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (st.st_size == 0) return Qtrue;
    return Qfalse;
}

/*
 * call-seq:
 *    File.size?(file_name)   => Integer or nil
 *
 * Returns +nil+ if +file_name+ doesn't exist or has zero size, the size of the
 * file otherwise.
 */

static VALUE
test_s(obj, fname)
    VALUE obj, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qnil;
    if (st.st_size == 0) return Qnil;
    return OFFT2NUM(st.st_size);
}

/*
 * call-seq:
 *    File.owned?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file exists and the
 * effective used id of the calling process is the owner of
 * the file.
 */

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

/*
 * call-seq:
 *    File.grpowned?(file_name)   => true or false
 *
 * Returns <code>true</code> if the named file exists and the
 * effective group id of the calling process is the owner of
 * the file. Returns <code>false</code> on Windows.
 */

static VALUE
test_grpowned(obj, fname)
    VALUE obj, fname;
{
#ifndef _WIN32
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (rb_group_member(st.st_gid)) return Qtrue;
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

/*
 * call-seq:
 *   File.setuid?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file has the setuid bit set.
 */

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

/*
 * call-seq:
 *   File.setgid?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file has the setgid bit set.
 */

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

/*
 * call-seq:
 *   File.sticky?(file_name)   =>  true or false
 *
 * Returns <code>true</code> if the named file has the sticky bit set.
 */

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

/*
 * call-seq:
 *   File.identical?(file_1, file_2)   =>  true or false
 *
 * Returns <code>true</code> if the named files are identical.
 *
 *     open("a", "w") {}
 *     p File.identical?("a", "a")      #=> true
 *     p File.identical?("a", "./a")    #=> true
 *     File.link("a", "b")
 *     p File.identical?("a", "b")      #=> true
 *     File.symlink("a", "c")
 *     p File.identical?("a", "c")      #=> true
 *     open("d", "w") {}
 *     p File.identical?("a", "d")      #=> false
 */

static VALUE
test_identical(obj, fname1, fname2)
    VALUE obj, fname1, fname2;
{
#ifndef DOSISH
    struct stat st1, st2;

    if (rb_stat(fname1, &st1) < 0) return Qfalse;
    if (rb_stat(fname2, &st2) < 0) return Qfalse;
    if (st1.st_dev != st2.st_dev) return Qfalse;
    if (st1.st_ino != st2.st_ino) return Qfalse;
#else
#ifdef _WIN32
    BY_HANDLE_FILE_INFORMATION st1, st2;
    HANDLE f1 = 0, f2 = 0;
#endif

    rb_secure(2);
#ifdef _WIN32
    f1 = w32_io_info(&fname1, &st1);
    if (f1 == INVALID_HANDLE_VALUE) return Qfalse;
    f2 = w32_io_info(&fname2, &st2);
    if (f1) CloseHandle(f1);
    if (f2 == INVALID_HANDLE_VALUE) return Qfalse;
    if (f2) CloseHandle(f2);

    if (st1.dwVolumeSerialNumber == st2.dwVolumeSerialNumber &&
	st1.nFileIndexHigh == st2.nFileIndexHigh &&
	st1.nFileIndexLow == st2.nFileIndexLow)
	return Qtrue;
    if (!f1 || !f2) return Qfalse;
    if (rb_w32_iswin95()) return Qfalse;
#else
    SafeStringValue(fname1);
    fname1 = rb_str_new4(fname1);
    SafeStringValue(fname2);
    if (access(RSTRING(fname1)->ptr, 0)) return Qfalse;
    if (access(RSTRING(fname2)->ptr, 0)) return Qfalse;
#endif
    fname1 = rb_file_expand_path(fname1, Qnil);
    fname2 = rb_file_expand_path(fname2, Qnil);
    if (RSTRING(fname1)->len != RSTRING(fname2)->len) return Qfalse;
    if (rb_memcicmp(RSTRING(fname1)->ptr, RSTRING(fname2)->ptr, RSTRING(fname1)->len))
	return Qfalse;
#endif
    return Qtrue;
}

/*
 * call-seq:
 *    File.size(file_name)   => integer
 *
 * Returns the size of <code>file_name</code>.
 */

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
    const char *t;

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

/*
 *  call-seq:
 *     File.ftype(file_name)   => string
 *
 *  Identifies the type of the named file; the return string is one of
 *  ``<code>file</code>'', ``<code>directory</code>'',
 *  ``<code>characterSpecial</code>'', ``<code>blockSpecial</code>'',
 *  ``<code>fifo</code>'', ``<code>link</code>'',
 *  ``<code>socket</code>'', or ``<code>unknown</code>''.
 *
 *     File.ftype("testfile")            #=> "file"
 *     File.ftype("/dev/tty")            #=> "characterSpecial"
 *     File.ftype("/tmp/.X11-unix/X0")   #=> "socket"
 */

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

/*
 *  call-seq:
 *     File.atime(file_name)  =>  time
 *
 *  Returns the last access time for the named file as a Time object).
 *
 *     File.atime("testfile")   #=> Wed Apr 09 08:51:48 CDT 2003
 *
 */

static VALUE
rb_file_s_atime(klass, fname)
    VALUE klass, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(StringValueCStr(fname));
    return rb_time_new(st.st_atime, 0);
}

/*
 *  call-seq:
 *     file.atime    => time
 *
 *  Returns the last access time (a <code>Time</code> object)
 *   for <i>file</i>, or epoch if <i>file</i> has not been accessed.
 *
 *     File.new("testfile").atime   #=> Wed Dec 31 18:00:00 CST 1969
 *
 */

static VALUE
rb_file_atime(obj)
    VALUE obj;
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return rb_time_new(st.st_atime, 0);
}

/*
 *  call-seq:
 *     File.mtime(file_name)  =>  time
 *
 *  Returns the modification time for the named file as a Time object.
 *
 *     File.mtime("testfile")   #=> Tue Apr 08 12:58:04 CDT 2003
 *
 */

static VALUE
rb_file_s_mtime(klass, fname)
    VALUE klass, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return rb_time_new(st.st_mtime, 0);
}

/*
 *  call-seq:
 *     file.mtime -> time
 *
 *  Returns the modification time for <i>file</i>.
 *
 *     File.new("testfile").mtime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_file_mtime(obj)
    VALUE obj;
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return rb_time_new(st.st_mtime, 0);
}

/*
 *  call-seq:
 *     File.ctime(file_name)  => time
 *
 *  Returns the change time for the named file (the time at which
 *  directory information about the file was changed, not the file
 *  itself).
 *
 *     File.ctime("testfile")   #=> Wed Apr 09 08:53:13 CDT 2003
 *
 */

static VALUE
rb_file_s_ctime(klass, fname)
    VALUE klass, fname;
{
    struct stat st;

    if (rb_stat(fname, &st) < 0)
	rb_sys_fail(RSTRING(fname)->ptr);
    return rb_time_new(st.st_ctime, 0);
}

/*
 *  call-seq:
 *     file.ctime -> time
 *
 *  Returns the change time for <i>file</i> (that is, the time directory
 *  information about the file was changed, not the file itself).
 *
 *     File.new("testfile").ctime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_file_ctime(obj)
    VALUE obj;
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fileno(fptr->f), &st) == -1) {
	rb_sys_fail(fptr->path);
    }
    return rb_time_new(st.st_ctime, 0);
}

static void chmod_internal _((const char *, void *));
static void
chmod_internal(path, mode)
    const char *path;
    void *mode;
{
    if (chmod(path, *(int *)mode) < 0)
	rb_sys_fail(path);
}

/*
 *  call-seq:
 *     File.chmod(mode_int, file_name, ... ) -> integer
 *
 *  Changes permission bits on the named file(s) to the bit pattern
 *  represented by <i>mode_int</i>. Actual effects are operating system
 *  dependent (see the beginning of this section). On Unix systems, see
 *  <code>chmod(2)</code> for details. Returns the number of files
 *  processed.
 *
 *     File.chmod(0644, "testfile", "out")   #=> 2
 */

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

    n = apply2files(chmod_internal, rest, &mode);
    return LONG2FIX(n);
}

/*
 *  call-seq:
 *     file.chmod(mode_int)   => 0
 *
 *  Changes permission bits on <i>file</i> to the bit pattern
 *  represented by <i>mode_int</i>. Actual effects are platform
 *  dependent; on Unix systems, see <code>chmod(2)</code> for details.
 *  Follows symbolic links. Also see <code>File#lchmod</code>.
 *
 *     f = File.new("out", "w");
 *     f.chmod(0644)   #=> 0
 */

static VALUE
rb_file_chmod(obj, vmode)
    VALUE obj, vmode;
{
    rb_io_t *fptr;
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
static void lchmod_internal _((const char *, void *));
static void
lchmod_internal(path, mode)
    const char *path;
    void *mode;
{
    if (lchmod(path, (int)(VALUE)mode) < 0)
	rb_sys_fail(path);
}

/*
 *  call-seq:
 *     File.lchmod(mode_int, file_name, ...)  => integer
 *
 *  Equivalent to <code>File::chmod</code>, but does not follow symbolic
 *  links (so it will change the permissions associated with the link,
 *  not the file referenced by the link). Often not available.
 *
 */

static VALUE
rb_file_s_lchmod(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE vmode;
    VALUE rest;
    long mode, n;

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

static void chown_internal _((const char *, void *));
static void
chown_internal(path, argp)
    const char *path;
    void *argp;
{
    struct chown_args *args = (struct chown_args *)argp;
    if (chown(path, args->owner, args->group) < 0)
	rb_sys_fail(path);
}

/*
 *  call-seq:
 *     File.chown(owner_int, group_int, file_name,... ) -> integer
 *
 *  Changes the owner and group of the named file(s) to the given
 *  numeric owner and group id's. Only a process with superuser
 *  privileges may change the owner of a file. The current owner of a
 *  file may change the file's group to any group to which the owner
 *  belongs. A <code>nil</code> or -1 owner or group id is ignored.
 *  Returns the number of files processed.
 *
 *     File.chown(nil, 100, "testfile")
 *
 */

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

/*
 *  call-seq:
 *     file.chown(owner_int, group_int )   => 0
 *
 *  Changes the owner and group of <i>file</i> to the given numeric
 *  owner and group id's. Only a process with superuser privileges may
 *  change the owner of a file. The current owner of a file may change
 *  the file's group to any group to which the owner belongs. A
 *  <code>nil</code> or -1 owner or group id is ignored. Follows
 *  symbolic links. See also <code>File#lchown</code>.
 *
 *     File.new("testfile").chown(502, 1000)
 *
 */

static VALUE
rb_file_chown(obj, owner, group)
    VALUE obj, owner, group;
{
    rb_io_t *fptr;
    int o, g;

    rb_secure(2);
    o = NIL_P(owner) ? -1 : NUM2INT(owner);
    g = NIL_P(group) ? -1 : NUM2INT(group);
    GetOpenFile(obj, fptr);
#if defined(DJGPP) || defined(__CYGWIN32__) || defined(_WIN32) || defined(__EMX__)
    if (!fptr->path) return Qnil;
    if (chown(fptr->path, o, g) == -1)
	rb_sys_fail(fptr->path);
#else
    if (fchown(fileno(fptr->f), o, g) == -1)
	rb_sys_fail(fptr->path);
#endif

    return INT2FIX(0);
}

#if defined(HAVE_LCHOWN) && !defined(__CHECKER__)
static void lchown_internal _((const char *, void *));
static void
lchown_internal(path, argp)
    const char *path;
    void *argp;
{
    struct chown_args *args = (struct chown_args *)argp;
    if (lchown(path, args->owner, args->group) < 0)
	rb_sys_fail(path);
}

/*
 *  call-seq:
 *     file.lchown(owner_int, group_int, file_name,..) => integer
 *
 *  Equivalent to <code>File::chown</code>, but does not follow symbolic
 *  links (so it will change the owner associated with the link, not the
 *  file referenced by the link). Often not available. Returns number
 *  of files in the argument list.
 *
 */

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

static void utime_internal _((const char *, void *));

#if defined(HAVE_UTIMES) && !defined(__CHECKER__)

static void
utime_internal(path, arg)
    const char *path;
    void *arg;
{
    struct timeval *tvp = arg;
    if (utimes(path, tvp) < 0)
	rb_sys_fail(path);
}

/*
 * call-seq:
 *  File.utime(atime, mtime, file_name,...)   =>  integer
 *
 * Sets the access and modification times of each
 * named file to the first two arguments. Returns
 * the number of file names in the argument list.
 */

static VALUE
rb_file_s_utime(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE atime, mtime, rest;
    struct timeval tvs[2], *tvp = NULL;
    long n;

    rb_secure(2);
    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    if (!NIL_P(atime) || !NIL_P(mtime)) {
	tvp = tvs;
	tvp[0] = rb_time_timeval(atime);
	tvp[1] = rb_time_timeval(mtime);
    }

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
utime_internal(path, arg)
    const char *path;
    void *arg;
{
    struct utimbuf *utp = arg;
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
    struct utimbuf utbuf, *utp = NULL;

    rb_scan_args(argc, argv, "2*", &atime, &mtime, &rest);

    if (!NIL_P(atime) || !NIL_P(mtime)) {
	utp = &utbuf;
	tv = rb_time_timeval(atime);
	utp->actime = tv.tv_sec;
	tv = rb_time_timeval(mtime);
	utp->modtime = tv.tv_sec;
    }

    n = apply2files(utime_internal, rest, utp);
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

/*
 *  call-seq:
 *     File.link(old_name, new_name)    => 0
 *
 *  Creates a new name for an existing file using a hard link. Will not
 *  overwrite <i>new_name</i> if it already exists (raising a subclass
 *  of <code>SystemCallError</code>). Not available on all platforms.
 *
 *     File.link("testfile", ".testfile")   #=> 0
 *     IO.readlines(".testfile")[0]         #=> "This is line one\n"
 */

static VALUE
rb_file_s_link(klass, from, to)
    VALUE klass, from, to;
{
#ifdef HAVE_LINK
    SafeStringValue(from);
    SafeStringValue(to);

    if (link(StringValueCStr(from), StringValueCStr(to)) < 0) {
	sys_fail2(from, to);
    }
    return INT2FIX(0);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

/*
 *  call-seq:
 *     File.symlink(old_name, new_name)   => 0
 *
 *  Creates a symbolic link called <i>new_name</i> for the existing file
 *  <i>old_name</i>. Raises a <code>NotImplemented</code> exception on
 *  platforms that do not support symbolic links.
 *
 *     File.symlink("testfile", "link2test")   #=> 0
 *
 */

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

/*
 *  call-seq:
 *     File.readlink(link_name) -> file_name
 *
 *  Returns the name of the file referenced by the given link.
 *  Not available on all platforms.
 *
 *     File.symlink("testfile", "link2test")   #=> 0
 *     File.readlink("link2test")              #=> "testfile"
 */

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
    while ((rv = readlink(RSTRING(path)->ptr, buf, size)) == size
#ifdef _AIX
	    || (rv < 0 && errno == ERANGE) /* quirky behavior of GPFS */
#endif
	) {
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

static void unlink_internal _((const char *, void *));
static void
unlink_internal(path, arg)
    const char *path;
    void *arg;
{
    if (unlink(path) < 0)
	rb_sys_fail(path);
}

/*
 *  call-seq:
 *     File.delete(file_name, ...)  => integer
 *     File.unlink(file_name, ...)  => integer
 *
 *  Deletes the named files, returning the number of names
 *  passed as arguments. Raises an exception on any error.
 *  See also <code>Dir::rmdir</code>.
 */

static VALUE
rb_file_s_unlink(klass, args)
    VALUE klass, args;
{
    long n;

    rb_secure(2);
    n = apply2files(unlink_internal, args, 0);
    return LONG2FIX(n);
}

/*
 *  call-seq:
 *     File.rename(old_name, new_name)   => 0
 *
 *  Renames the given file to the new name. Raises a
 *  <code>SystemCallError</code> if the file cannot be renamed.
 *
 *     File.rename("afile", "afile.bak")   #=> 0
 */

static VALUE
rb_file_s_rename(klass, from, to)
    VALUE klass, from, to;
{
    const char *src, *dst;
    SafeStringValue(from);
    SafeStringValue(to);

    src = StringValueCStr(from);
    dst = StringValueCStr(to);
#if defined __CYGWIN__
    errno = 0;
#endif
    if (rename(src, dst) < 0) {
#if defined DOSISH && !defined _WIN32
	switch (errno) {
	  case EEXIST:
#if defined (__EMX__)
	  case EACCES:
#endif
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

/*
 *  call-seq:
 *     File.umask()          => integer
 *     File.umask(integer)   => integer
 *
 *  Returns the current umask value for this process. If the optional
 *  argument is given, set the umask to that value and return the
 *  previous value. Umask values are <em>subtracted</em> from the
 *  default permissions, so a umask of <code>0222</code> would make a
 *  file read-only for everyone.
 *
 *     File.umask(0006)   #=> 18
 *     File.umask         #=> 6
 */

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
	rb_raise(rb_eArgError, "wrong number of arguments");
    }
    return INT2FIX(omask);
}

#ifdef __CYGWIN__
#undef DOSISH
#endif
#if defined __CYGWIN__ || defined DOSISH
#define DOSISH_UNC
#define DOSISH_DRIVE_LETTER
#define isdirsep(x) ((x) == '/' || (x) == '\\')
#else
#define isdirsep(x) ((x) == '/')
#endif

#ifndef USE_NTFS
#if defined _WIN32 || defined __CYGWIN__
#define USE_NTFS 1
#else
#define USE_NTFS 0
#endif
#endif

#ifdef DOSISH_DRIVE_LETTER
#include <ctype.h>
#endif

#if USE_NTFS
#define istrailinggarbage(x) ((x) == '.' || (x) == ' ')
#else
#define istrailinggarbage(x) 0
#endif

#ifndef CharNext		/* defined as CharNext[AW] on Windows. */
# if defined(DJGPP)
#   define CharNext(p) ((p) + mblen(p, MB_CUR_MAX))
# else
#   define CharNext(p) ((p) + 1)
# endif
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

static char*
getcwdofdrv(drv)
    int drv;
{
    char drive[4];
    char *drvcwd, *oldcwd;

    drive[0] = drv;
    drive[1] = ':';
    drive[2] = '\0';

    /* the only way that I know to get the current directory
       of a particular drive is to change chdir() to that drive,
       so save the old cwd before chdir()
    */
    oldcwd = my_getcwd();
    if (chdir(drive) == 0) {
	drvcwd = my_getcwd();
	chdir(oldcwd);
	free(oldcwd);
    }
    else {
	/* perhaps the drive is not exist. we return only drive letter */
	drvcwd = strdup(drive);
    }
    return drvcwd;
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

#define nextdirsep rb_path_next
char *
rb_path_next(s)
    const char *s;
{
    while (*s && !isdirsep(*s)) {
	s = CharNext(s);
    }
    return (char *)s;
}

#if defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER)
#define skipprefix rb_path_skip_prefix
#else
#define skipprefix(path) (path)
#endif
char *
rb_path_skip_prefix(path)
    const char *path;
{
#if defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER)
#ifdef DOSISH_UNC
    if (isdirsep(path[0]) && isdirsep(path[1])) {
	path += 2;
	while (isdirsep(*path)) path++;
	if (*(path = nextdirsep(path)) && path[1] && !isdirsep(path[1]))
	    path = nextdirsep(path + 1);
	return (char *)path;
    }
#endif
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(path))
	return (char *)(path + 2);
#endif
#endif
    return (char *)path;
}

#define strrdirsep rb_path_last_separator
char *
rb_path_last_separator(path)
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

char *
rb_path_end(path)
    const char *path;
{
    if (isdirsep(*path)) path++;
    return chompdirsep(path);
}

#if USE_NTFS
static char *
ntfs_tail(const char *path)
{
    while (*path == '.') path++;
    while (*path && *path != ':') {
	if (istrailinggarbage(*path)) {
	    const char *last = path++;
	    while (istrailinggarbage(*path)) path++;
	    if (!*path || *path == ':') return (char *)last;
	}
	else if (isdirsep(*path)) {
	    const char *last = path++;
	    while (isdirsep(*path)) path++;
	    if (!*path) return (char *)last;
	    if (*path == ':') path++;
	}
	else {
	    path = CharNext(path);
	}
    }
    return (char *)path;
}
#endif

#define BUFCHECK(cond) do {\
    long bdiff = p - buf;\
    if (cond) {\
	do {buflen *= 2;} while (cond);\
	rb_str_resize(result, buflen);\
	buf = RSTRING_PTR(result);\
	p = buf + bdiff;\
	pend = buf + buflen;\
    }\
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
    const char *s, *b;
    char *buf, *p, *pend, *root;
    long buflen, dirlen;
    int tainted;

    s = StringValuePtr(fname);
    BUFINIT();
    tainted = OBJ_TAINTED(fname);

    if (s[0] == '~') {
	long userlen = 0;
	if (isdirsep(s[1]) || s[1] == '\0') {
	    const char *dir = getenv("HOME");

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
	    userlen = s - b;
	    BUFCHECK(bdiff + userlen >= buflen);
	    memcpy(p, b, userlen);
	    p += userlen;
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
#else
	    rb_raise(rb_eArgError, "can't find user %s", buf);
#endif
	}
	if (!is_absolute_path(RSTRING_PTR(result))) {
	    if (userlen) {
		rb_raise(rb_eArgError, "non-absolute home of %.*s", userlen, s);
	    }
	    else {
		rb_raise(rb_eArgError, "non-absolute home");
	    }
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
		char *dir = getcwdofdrv(*s);

		tainted = 1;
		dirlen = strlen(dir);
		BUFCHECK(dirlen > buflen);
		strcpy(buf, dir);
		free(dir);
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
			char *n;
			*p = '\0';
			if (!(n = strrdirsep(root))) {
			    *p = '/';
			}
			else {
			    p = n;
			}
			b = ++s;
		    }
#if USE_NTFS
		    else {
			do ++s; while (istrailinggarbage(*s));
		    }
#endif
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
#if USE_NTFS
	    else {
		--s;
	      case ' ': {
		const char *e = s;
		while (istrailinggarbage(*s)) s++;
		if (!*s) {
		    s = e;
		    goto endpath;
		}
	      }
	    }
#endif
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
#if USE_NTFS
	static const char prime[] = ":$DATA";
	enum {prime_len = sizeof(prime) -1};
      endpath:
	if (s > b + prime_len && strncasecmp(s - prime_len, prime, prime_len) == 0) {
	    /* alias of stream */
	    /* get rid of a bug of x64 VC++ */
	    if (*(s - (prime_len+1)) == ':') {
		s -= prime_len + 1; /* prime */
	    }
	    else if (memchr(b, ':', s - prime_len - b)) {
		s -= prime_len;	/* alternative */
	    }
	}
#endif
	BUFCHECK(bdiff + (s-b) >= buflen);
	memcpy(++p, b, s-b);
	p += s-b;
    }
    if (p == skiproot(buf) - 1) p++;

#if USE_NTFS
    *p = '\0';
    if ((s = strrdirsep(b = buf)) != 0 && !strpbrk(s, "*?")) {
	size_t len;
	WIN32_FIND_DATA wfd;
#ifdef __CYGWIN__
	int lnk_added = 0, is_symlink = 0;
	struct stat st;
	char w32buf[MAXPATHLEN];
	p = (char *)s;
	if (lstat(buf, &st) == 0 && S_ISLNK(st.st_mode)) {
	    is_symlink = 1;
	    *p = '\0';
	}
	if (cygwin_conv_to_win32_path((*buf ? buf : "/"), w32buf) == 0) {
	    b = w32buf;
	}
	if (is_symlink && b == w32buf) {
	    *p = '\\';
	    strlcat(w32buf, p, sizeof(w32buf));
	    len = strlen(p);
	    if (len > 4 && strcasecmp(p + len - 4, ".lnk") != 0) {
		lnk_added = 1;
		strlcat(w32buf, ".lnk", sizeof(w32buf));
	    }
	}
	*p = '/';
#endif
	HANDLE h = FindFirstFile(b, &wfd);
	if (h != INVALID_HANDLE_VALUE) {
	    FindClose(h);
	    len = strlen(wfd.cFileName);
#ifdef __CYGWIN__
	    if (lnk_added && len > 4 &&
		strcasecmp(wfd.cFileName + len - 4, ".lnk") == 0) {
		wfd.cFileName[len -= 4] = '\0';
	    }
#else
	    p = (char *)s;
#endif
	    ++p;
	    BUFCHECK(bdiff + len >= buflen);
	    memcpy(p, wfd.cFileName, len + 1);
	    p += len;
	}
#ifdef __CYGWIN__
	else {
	    p += strlen(p);
	}
#endif
    }
#endif

    if (tainted) OBJ_TAINT(result);
    rb_str_set_len(result, p - buf);
    return result;
}

VALUE
rb_file_expand_path(fname, dname)
    VALUE fname, dname;
{
    return file_expand_path(fname, dname, rb_str_new(0, MAXPATHLEN + 2));
}

/*
 *  call-seq:
 *     File.expand_path(file_name [, dir_string] ) -> abs_file_name
 *
 *  Converts a pathname to an absolute pathname. Relative paths are
 *  referenced from the current working directory of the process unless
 *  <i>dir_string</i> is given, in which case it will be used as the
 *  starting point. The given pathname may start with a
 *  ``<code>~</code>'', which expands to the process owner's home
 *  directory (the environment variable <code>HOME</code> must be set
 *  correctly). ``<code>~</code><i>user</i>'' expands to the named
 *  user's home directory.
 *
 *     File.expand_path("~oracle/bin")           #=> "/home/oracle/bin"
 *     File.expand_path("../../bin", "/tmp/x")   #=> "/bin"
 */

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
rmext(p, l1, e)
    const char *p, *e;
    int l1;
{
    int l0, l2;

    if (!e) return 0;

    for (l0 = 0; l0 < l1; ++l0) {
	if (p[l0] != '.') break;
    }
    l2 = strlen(e);
    if (l2 == 2 && e[1] == '*') {
	unsigned char c = *e;
	e = p + l1;
	do {
	    if (e <= p + l0) return 0;
	} while (*--e != c);
	return e - p;
    }
    if (l1 < l2) return l1;

#if CASEFOLD_FILESYSTEM
#define fncomp strncasecmp
#else
#define fncomp strncmp
#endif
    if (fncomp(p+l1-l2, e, l2) == 0) {
	return l1-l2;
    }
    return 0;
}

const char *
ruby_find_basename(const char *name, long *baselen, long *alllen)
{
    const char *p, *q, *e;
#if defined DOSISH_DRIVE_LETTER || defined DOSISH_UNC
    const char *root;
#endif
    long f = 0, n = -1;

    name = skipprefix(name);
#if defined DOSISH_DRIVE_LETTER || defined DOSISH_UNC
    root = name;
#endif
    while (isdirsep(*name))
	name++;
    if (!*name) {
	p = name - 1;
	f = 1;
#if defined DOSISH_DRIVE_LETTER || defined DOSISH_UNC
	if (name != root) {
	    /* has slashes */
	}
#ifdef DOSISH_DRIVE_LETTER
	else if (*p == ':') {
	    p++;
	    f = 0;
	}
#endif
#ifdef DOSISH_UNC
	else {
	    p = "/";
	}
#endif
#endif
    }
    else {
	if (!(p = strrdirsep(name))) {
	    p = name;
	}
	else {
	    while (isdirsep(*p)) p++; /* skip last / */
	}
#if USE_NTFS
	n = ntfs_tail(p) - p;
#else
	n = chompdirsep(p) - p;
#endif
	for (q = p; q - p < n && *q == '.'; q++);
	for (e = 0; q - p < n; q = CharNext(q)) {
	    if (*q == '.') e = q;
	}
	if (e) f = e - p;
	else f = n;
    }

    if (baselen)
	*baselen = f;
    if (alllen)
	*alllen = n;
    return p;
}

/*
 *  call-seq:
 *     File.basename(file_name [, suffix] ) -> base_name
 *
 *  Returns the last component of the filename given in <i>file_name</i>,
 *  which must be formed using forward slashes (``<code>/</code>'')
 *  regardless of the separator used on the local file system. If
 *  <i>suffix</i> is given and present at the end of <i>file_name</i>,
 *  it is removed.
 *
 *     File.basename("/home/gumby/work/ruby.rb")          #=> "ruby.rb"
 *     File.basename("/home/gumby/work/ruby.rb", ".rb")   #=> "ruby"
 */

static VALUE
rb_file_s_basename(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE fname, fext, basename;
    const char *name, *p;
    long f, n;

    if (rb_scan_args(argc, argv, "11", &fname, &fext) == 2) {
	StringValue(fext);
    }
    StringValue(fname);
    if (RSTRING_LEN(fname) == 0 || !*(name = RSTRING_PTR(fname)))
	return fname;

    p = ruby_find_basename(name, &f, &n);
    if (n >= 0) {
	if (NIL_P(fext) || !(f = rmext(p, n, StringValueCStr(fext)))) {
	    f = n;
	}
	if (f == RSTRING_LEN(fname)) return fname;
    }

    basename = rb_str_new(p, f);
    OBJ_INFECT(basename, fname);
    return basename;
}

/*
 *  call-seq:
 *     File.dirname(file_name ) -> dir_name
 *
 *  Returns all components of the filename given in <i>file_name</i>
 *  except the last one. The filename must be formed using forward
 *  slashes (``<code>/</code>'') regardless of the separator used on the
 *  local file system.
 *
 *     File.dirname("/home/gumby/work/ruby.rb")   #=> "/home/gumby/work"
 */

static VALUE
rb_file_s_dirname(klass, fname)
    VALUE klass, fname;
{
    const char *name, *root, *p;
    VALUE dirname;

    name = StringValueCStr(fname);
    root = skiproot(name);
#ifdef DOSISH_UNC
    if (root > name + 1 && isdirsep(*name))
	root = skipprefix(name = root - 2);
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
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(name) && isdirsep(*(name + 2))) {
	const char *top = skiproot(name + 2);
	dirname = rb_str_new(name, 3);
	rb_str_cat(dirname, top, p - top);
    }
    else
#endif
    dirname = rb_str_new(name, p - name);
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(name) && root == name + 2 && p - name == 2)
	rb_str_cat(dirname, ".", 1);
#endif
    OBJ_INFECT(dirname, fname);
    return dirname;
}

/*
 * accept a String, and return the pointer of the extension.
 * if len is passed, set the length of extension to it.
 * returned pointer is in ``name'' or NULL.
 *                 returns   *len
 *   no dot        NULL      0
 *   dotfile       top       0
 *   end with dot  dot       1
 *   .ext          dot       len of .ext
 *   .ext:stream   dot       len of .ext without :stream (NT only)
 *
 */
const char *
ruby_find_extname(const char *name, long *len)
{
    const char *p, *e;

    p = strrdirsep(name);	/* get the last path component */
    if (!p)
	p = name;
    else
	do name = ++p; while (isdirsep(*p));

    e = 0;
    while (*p && *p == '.') p++;
    while (*p) {
	if (*p == '.' || istrailinggarbage(*p)) {
#if USE_NTFS
	    const char *last = p++, *dot = last;
	    while (istrailinggarbage(*p)) {
		if (*p == '.') dot = p;
		p++;
	    }
	    if (!*p || *p == ':') {
		p = last;
		break;
	    }
	    if (*last == '.' || dot > last) e = dot;
	    continue;
#else
	    e = p;	  /* get the last dot of the last component */
#endif
	}
#if USE_NTFS
	else if (*p == ':') {
	    break;
	}
#endif
	else if (isdirsep(*p))
	    break;
	p = CharNext(p);
    }

    if (len) {
	/* no dot, or the only dot is first or end? */
	if (!e || e == name)
	    *len = 0;
	else if (e+1 == p)
	    *len = 1;
	else
	    *len = p - e;
    }
    return e;
}

/*
 *  call-seq:
 *     File.extname(path) -> string
 *
 *  Returns the extension (the portion of file name in <i>path</i>
 *  after the period).
 *
 *     File.extname("test.rb")         #=> ".rb"
 *     File.extname("a/b/d/test.rb")   #=> ".rb"
 *     File.extname("test")            #=> ""
 *     File.extname(".profile")        #=> ""
 *
 */

static VALUE
rb_file_s_extname(klass, fname)
    VALUE klass, fname;
{
    const char *name, *e;
    long len;
    VALUE extname;

    name = StringValueCStr(fname);
    e = ruby_find_extname(name, &len);
    if (len <= 1)
	return rb_str_new(0, 0);
    extname = rb_str_new(e, len);	/* keep the dot, too! */
    OBJ_INFECT(extname, fname);
    return extname;
}

/*
 *  call-seq:
 *     File.split(file_name)   => array
 *
 *  Splits the given string into a directory and a file component and
 *  returns them in a two-element array. See also
 *  <code>File::dirname</code> and <code>File::basename</code>.
 *
 *     File.split("/home/gumby/.profile")   #=> ["/home/gumby", ".profile"]
 */

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
    const char *name, *tail;

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
	    if (tmp == ary || rb_inspecting_p(tmp)) {
		rb_raise(rb_eArgError, "recursive array");
	    }
	    else {
		VALUE args[2];

		args[0] = tmp;
		args[1] = sep;
		tmp = rb_protect_inspect(file_inspect_join, ary, (VALUE)args);
	    }
	    break;
	  default:
	    StringValueCStr(tmp);
	}
	name = StringValueCStr(result);
	if (i > 0 && !NIL_P(sep)) {
	    tail = chompdirsep(name);
	    if (RSTRING(tmp)->ptr && isdirsep(RSTRING(tmp)->ptr[0])) {
		RSTRING(result)->len = tail - name;
	    }
	    else if (!*tail) {
		rb_str_buf_append(result, sep);
	    }
	}
	rb_str_buf_append(result, tmp);
	if (OBJ_TAINTED(tmp)) taint = 1;
    }

    if (taint) OBJ_TAINT(result);
    return result;
}

/*
 *  call-seq:
 *     File.join(string, ...) -> path
 *
 *  Returns a new string formed by joining the strings using
 *  <code>File::SEPARATOR</code>.
 *
 *     File.join("usr", "mail", "gumby")   #=> "usr/mail/gumby"
 *
 */

static VALUE
rb_file_s_join(klass, args)
    VALUE klass, args;
{
    return rb_file_join(args, separator);
}

/*
 *  call-seq:
 *     File.truncate(file_name, integer)  => 0
 *
 *  Truncates the file <i>file_name</i> to be at most <i>integer</i>
 *  bytes long. Not available on all platforms.
 *
 *     f = File.new("out", "w")
 *     f.write("1234567890")     #=> 10
 *     f.close                   #=> nil
 *     File.truncate("out", 5)   #=> 0
 *     File.size("out")          #=> 5
 *
 */

static VALUE
rb_file_s_truncate(klass, path, len)
    VALUE klass, path, len;
{
    off_t pos;

    rb_secure(2);
    pos = NUM2OFFT(len);
    SafeStringValue(path);

#ifdef HAVE_TRUNCATE
    if (truncate(StringValueCStr(path), pos) < 0)
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
	if (chsize(tmpfd, pos) < 0) {
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

/*
 *  call-seq:
 *     file.truncate(integer)    => 0
 *
 *  Truncates <i>file</i> to at most <i>integer</i> bytes. The file
 *  must be opened for writing. Not available on all platforms.
 *
 *     f = File.new("out", "w")
 *     f.syswrite("1234567890")   #=> 10
 *     f.truncate(5)              #=> 0
 *     f.close()                  #=> nil
 *     File.size("out")           #=> 5
 */

static VALUE
rb_file_truncate(obj, len)
    VALUE obj, len;
{
    rb_io_t *fptr;
    FILE *f;
    off_t pos;

    rb_secure(2);
    pos = NUM2OFFT(len);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
	rb_raise(rb_eIOError, "not opened for writing");
    }
    f = GetWriteFile(fptr);
    fflush(f);
    fseeko(f, (off_t)0, SEEK_CUR);
#ifdef HAVE_FTRUNCATE
    if (ftruncate(fileno(f), pos) < 0)
	rb_sys_fail(fptr->path);
#else
# ifdef HAVE_CHSIZE
    if (chsize(fileno(f), pos) < 0)
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

#ifdef __CYGWIN__
#include <winerror.h>
extern unsigned long __attribute__((stdcall)) GetLastError(void);

static int
cygwin_flock(int fd, int op)
{
    int old_errno = errno;
    int ret = flock(fd, op);
    if (GetLastError() == ERROR_NOT_LOCKED) {
	ret = 0;
	errno = old_errno;
    }
    return ret;
}
# define flock(fd, op) cygwin_flock(fd, op)
#endif

static int
rb_thread_flock(fd, op, fptr)
    int fd, op;
    rb_io_t *fptr;
{
    if (rb_thread_alone() || (op & LOCK_NB)) {
	int ret;
	TRAP_BEG;
	ret = flock(fd, op);
	TRAP_END;
	return ret;
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
#ifdef __CYGWIN__
# undef flock
#endif
#define flock(fd, op) rb_thread_flock(fd, op, fptr)

/*
 *  call-seq:
 *     file.flock (locking_constant ) =>  0 or false
 *
 *  Locks or unlocks a file according to <i>locking_constant</i> (a
 *  logical <em>or</em> of the values in the table below).
 *  Returns <code>false</code> if <code>File::LOCK_NB</code> is
 *  specified and the operation would otherwise have blocked. Not
 *  available on all platforms.
 *
 *  Locking constants (in class File):
 *
 *     LOCK_EX   | Exclusive lock. Only one process may hold an
 *               | exclusive lock for a given file at a time.
 *     ----------+------------------------------------------------
 *     LOCK_NB   | Don't block when locking. May be combined
 *               | with other lock options using logical or.
 *     ----------+------------------------------------------------
 *     LOCK_SH   | Shared lock. Multiple processes may each hold a
 *               | shared lock for a given file at the same time.
 *     ----------+------------------------------------------------
 *     LOCK_UN   | Unlock.
 *
 *  Example:
 *
 *     File.new("testfile").flock(File::LOCK_UN)   #=> 0
 *
 */

static VALUE
rb_file_flock(obj, operation)
    VALUE obj;
    VALUE operation;
{
#ifndef __CHECKER__
    rb_io_t *fptr;
    int op;

    rb_secure(2);
    op = NUM2INT(operation);
    GetOpenFile(obj, fptr);

    if (fptr->mode & FMODE_WRITABLE) {
	fflush(GetWriteFile(fptr));
    }
  retry:
    if (flock(fileno(fptr->f), op) < 0) {
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
    if (n != argc) rb_raise(rb_eArgError, "wrong number of arguments (%d for %d)", argc, n);
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

/*
 *  call-seq:
 *     test(int_cmd, file1 [, file2] ) => obj
 *
 *  Uses the integer <i>aCmd</i> to perform various tests on
 *  <i>file1</i> (first table below) or on <i>file1</i> and
 *  <i>file2</i> (second table).
 *
 *  File tests on a single file:
 *
 *    Test   Returns   Meaning
 *     ?A  | Time    | Last access time for file1
 *     ?b  | boolean | True if file1 is a block device
 *     ?c  | boolean | True if file1 is a character device
 *     ?C  | Time    | Last change time for file1
 *     ?d  | boolean | True if file1 exists and is a directory
 *     ?e  | boolean | True if file1 exists
 *     ?f  | boolean | True if file1 exists and is a regular file
 *     ?g  | boolean | True if file1 has the \CF{setgid} bit
 *         |         | set (false under NT)
 *     ?G  | boolean | True if file1 exists and has a group
 *         |         | ownership equal to the caller's group
 *     ?k  | boolean | True if file1 exists and has the sticky bit set
 *     ?l  | boolean | True if file1 exists and is a symbolic link
 *     ?M  | Time    | Last modification time for file1
 *     ?o  | boolean | True if file1 exists and is owned by
 *         |         | the caller's effective uid
 *     ?O  | boolean | True if file1 exists and is owned by
 *         |         | the caller's real uid
 *     ?p  | boolean | True if file1 exists and is a fifo
 *     ?r  | boolean | True if file1 is readable by the effective
 *         |         | uid/gid of the caller
 *     ?R  | boolean | True if file is readable by the real
 *         |         | uid/gid of the caller
 *     ?s  | int/nil | If file1 has nonzero size, return the size,
 *         |         | otherwise return nil
 *     ?S  | boolean | True if file1 exists and is a socket
 *     ?u  | boolean | True if file1 has the setuid bit set
 *     ?w  | boolean | True if file1 exists and is writable by
 *         |         | the effective uid/gid
 *     ?W  | boolean | True if file1 exists and is writable by
 *         |         | the real uid/gid
 *     ?x  | boolean | True if file1 exists and is executable by
 *         |         | the effective uid/gid
 *     ?X  | boolean | True if file1 exists and is executable by
 *         |         | the real uid/gid
 *     ?z  | boolean | True if file1 exists and has a zero length
 *
 * Tests that take two files:
 *
 *     ?-  | boolean | True if file1 and file2 are identical
 *     ?=  | boolean | True if the modification times of file1
 *         |         | and file2 are equal
 *     ?<  | boolean | True if the modification time of file1
 *         |         | is prior to that of file2
 *     ?>  | boolean | True if the modification time of file1
 *         |         | is after that of file2
 */

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

    if (cmd == '-') {
	CHECK(2);
	return test_identical(0, argv[1], argv[2]);
    }

    if (strchr("=<>", cmd)) {
	struct stat st1, st2;

	CHECK(2);
	if (rb_stat(argv[1], &st1) < 0) return Qfalse;
	if (rb_stat(argv[2], &st2) < 0) return Qfalse;

	switch (cmd) {
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


/*
 *  Document-class: File::Stat
 *
 *  Objects of class <code>File::Stat</code> encapsulate common status
 *  information for <code>File</code> objects. The information is
 *  recorded at the moment the <code>File::Stat</code> object is
 *  created; changes made to the file after that point will not be
 *  reflected. <code>File::Stat</code> objects are returned by
 *  <code>IO#stat</code>, <code>File::stat</code>,
 *  <code>File#lstat</code>, and <code>File::lstat</code>. Many of these
 *  methods return platform-specific values, and not all values are
 *  meaningful on all systems. See also <code>Kernel#test</code>.
 */

static VALUE rb_stat_s_alloc _((VALUE));
static VALUE
rb_stat_s_alloc(klass)
    VALUE klass;
{
    return stat_new_0(klass, 0);
}

/*
 * call-seq:
 *
 *   File::Stat.new(file_name)  => stat
 *
 * Create a File::Stat object for the given file name (raising an
 * exception if the file doesn't exist).
 */

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

/* :nodoc: */
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

/*
 *  call-seq:
 *     stat.ftype   => string
 *
 *  Identifies the type of <i>stat</i>. The return string is one of:
 *  ``<code>file</code>'', ``<code>directory</code>'',
 *  ``<code>characterSpecial</code>'', ``<code>blockSpecial</code>'',
 *  ``<code>fifo</code>'', ``<code>link</code>'',
 *  ``<code>socket</code>'', or ``<code>unknown</code>''.
 *
 *     File.stat("/dev/tty").ftype   #=> "characterSpecial"
 *
 */

static VALUE
rb_stat_ftype(obj)
    VALUE obj;
{
    return rb_file_ftype(get_stat(obj));
}

/*
 *  call-seq:
 *     stat.directory?   => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a directory,
 *  <code>false</code> otherwise.
 *
 *     File.stat("testfile").directory?   #=> false
 *     File.stat(".").directory?          #=> true
 */

static VALUE
rb_stat_d(obj)
    VALUE obj;
{
    if (S_ISDIR(get_stat(obj)->st_mode)) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.pipe?    => true or false
 *
 *  Returns <code>true</code> if the operating system supports pipes and
 *  <i>stat</i> is a pipe; <code>false</code> otherwise.
 */

static VALUE
rb_stat_p(obj)
    VALUE obj;
{
#ifdef S_IFIFO
    if (S_ISFIFO(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.symlink?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a symbolic link,
 *  <code>false</code> if it isn't or if the operating system doesn't
 *  support this feature. As <code>File::stat</code> automatically
 *  follows symbolic links, <code>symlink?</code> will always be
 *  <code>false</code> for an object returned by
 *  <code>File::stat</code>.
 *
 *     File.symlink("testfile", "alink")   #=> 0
 *     File.stat("alink").symlink?         #=> false
 *     File.lstat("alink").symlink?        #=> true
 *
 */

static VALUE
rb_stat_l(obj)
    VALUE obj;
{
#ifdef S_ISLNK
    if (S_ISLNK(get_stat(obj)->st_mode)) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.socket?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a socket,
 *  <code>false</code> if it isn't or if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("testfile").socket?   #=> false
 *
 */

static VALUE
rb_stat_S(obj)
    VALUE obj;
{
#ifdef S_ISSOCK
    if (S_ISSOCK(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.blockdev?   => true or false
 *
 *  Returns <code>true</code> if the file is a block device,
 *  <code>false</code> if it isn't or if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("testfile").blockdev?    #=> false
 *     File.stat("/dev/hda1").blockdev?   #=> true
 *
 */

static VALUE
rb_stat_b(obj)
    VALUE obj;
{
#ifdef S_ISBLK
    if (S_ISBLK(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.chardev?    => true or false
 *
 *  Returns <code>true</code> if the file is a character device,
 *  <code>false</code> if it isn't or if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("/dev/tty").chardev?   #=> true
 *
 */

static VALUE
rb_stat_c(obj)
    VALUE obj;
{
    if (S_ISCHR(get_stat(obj)->st_mode)) return Qtrue;

    return Qfalse;
}

/*
 *  call-seq:
 *     stat.owned?    => true or false
 *
 *  Returns <code>true</code> if the effective user id of the process is
 *  the same as the owner of <i>stat</i>.
 *
 *     File.stat("testfile").owned?      #=> true
 *     File.stat("/etc/passwd").owned?   #=> false
 *
 */

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

/*
 *  call-seq:
 *     stat.grpowned?   => true or false
 *
 *  Returns true if the effective group id of the process is the same as
 *  the group id of <i>stat</i>. On Windows NT, returns <code>false</code>.
 *
 *     File.stat("testfile").grpowned?      #=> true
 *     File.stat("/etc/passwd").grpowned?   #=> false
 *
 */

static VALUE
rb_stat_grpowned(obj)
    VALUE obj;
{
#ifndef _WIN32
    if (rb_group_member(get_stat(obj)->st_gid)) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.readable?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is readable by the
 *  effective user id of this process.
 *
 *     File.stat("testfile").readable?   #=> true
 *
 */

static VALUE
rb_stat_r(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (geteuid() == 0) return Qtrue;
#endif
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

/*
 *  call-seq:
 *     stat.readable_real? -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is readable by the real
 *  user id of this process.
 *
 *     File.stat("testfile").readable_real?   #=> true
 *
 */

static VALUE
rb_stat_R(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (getuid() == 0) return Qtrue;
#endif
#ifdef S_IRUSR
    if (rb_stat_rowned(obj))
	return st->st_mode & S_IRUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IRGRP
    if (rb_group_member(get_stat(obj)->st_gid))
	return st->st_mode & S_IRGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IROTH
    if (!(st->st_mode & S_IROTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *     stat.writable? -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is writable by the
 *  effective user id of this process.
 *
 *     File.stat("testfile").writable?   #=> true
 *
 */

static VALUE
rb_stat_w(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (geteuid() == 0) return Qtrue;
#endif
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

/*
 *  call-seq:
 *     stat.writable_real? -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is writable by the real
 *  user id of this process.
 *
 *     File.stat("testfile").writable_real?   #=> true
 *
 */

static VALUE
rb_stat_W(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (getuid() == 0) return Qtrue;
#endif
#ifdef S_IWUSR
    if (rb_stat_rowned(obj))
	return st->st_mode & S_IWUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IWGRP
    if (rb_group_member(get_stat(obj)->st_gid))
	return st->st_mode & S_IWGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IWOTH
    if (!(st->st_mode & S_IWOTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *     stat.executable?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is executable or if the
 *  operating system doesn't distinguish executable files from
 *  nonexecutable files. The tests are made using the effective owner of
 *  the process.
 *
 *     File.stat("testfile").executable?   #=> false
 *
 */

static VALUE
rb_stat_x(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (geteuid() == 0) {
	return st->st_mode & S_IXUGO ? Qtrue : Qfalse;
    }
#endif
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

/*
 *  call-seq:
 *     stat.executable_real?    => true or false
 *
 *  Same as <code>executable?</code>, but tests using the real owner of
 *  the process.
 */

static VALUE
rb_stat_X(obj)
    VALUE obj;
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (getuid() == 0) {
	return st->st_mode & S_IXUGO ? Qtrue : Qfalse;
    }
#endif
#ifdef S_IXUSR
    if (rb_stat_rowned(obj))
	return st->st_mode & S_IXUSR ? Qtrue : Qfalse;
#endif
#ifdef S_IXGRP
    if (rb_group_member(get_stat(obj)->st_gid))
	return st->st_mode & S_IXGRP ? Qtrue : Qfalse;
#endif
#ifdef S_IXOTH
    if (!(st->st_mode & S_IXOTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *     stat.file?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a regular file (not
 *  a device file, pipe, socket, etc.).
 *
 *     File.stat("testfile").file?   #=> true
 *
 */

static VALUE
rb_stat_f(obj)
    VALUE obj;
{
    if (S_ISREG(get_stat(obj)->st_mode)) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.zero?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a zero-length file;
 *  <code>false</code> otherwise.
 *
 *     File.stat("testfile").zero?   #=> false
 *
 */

static VALUE
rb_stat_z(obj)
    VALUE obj;
{
    if (get_stat(obj)->st_size == 0) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     state.size    => integer
 *
 *  Returns the size of <i>stat</i> in bytes.
 *
 *     File.stat("testfile").size   #=> 66
 *
 */

static VALUE
rb_stat_s(obj)
    VALUE obj;
{
    off_t size = get_stat(obj)->st_size;

    if (size == 0) return Qnil;
    return OFFT2NUM(size);
}

/*
 *  call-seq:
 *     stat.setuid?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> has the set-user-id
 *  permission bit set, <code>false</code> if it doesn't or if the
 *  operating system doesn't support this feature.
 *
 *     File.stat("/bin/su").setuid?   #=> true
 */

static VALUE
rb_stat_suid(obj)
    VALUE obj;
{
#ifdef S_ISUID
    if (get_stat(obj)->st_mode & S_ISUID) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.setgid?   => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> has the set-group-id
 *  permission bit set, <code>false</code> if it doesn't or if the
 *  operating system doesn't support this feature.
 *
 *     File.stat("/usr/sbin/lpc").setgid?   #=> true
 *
 */

static VALUE
rb_stat_sgid(obj)
    VALUE obj;
{
#ifdef S_ISGID
    if (get_stat(obj)->st_mode & S_ISGID) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.sticky?    => true or false
 *
 *  Returns <code>true</code> if <i>stat</i> has its sticky bit set,
 *  <code>false</code> if it doesn't or if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("testfile").sticky?   #=> false
 *
 */

static VALUE
rb_stat_sticky(obj)
    VALUE obj;
{
#ifdef S_ISVTX
    if (get_stat(obj)->st_mode & S_ISVTX) return Qtrue;
#endif
    return Qfalse;
}

VALUE rb_mFConst;

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

#ifndef ENABLE_PATH_CHECK
# if defined DOSISH || defined __CYGWIN__
#   define ENABLE_PATH_CHECK 0
# else
#   define ENABLE_PATH_CHECK 1
# endif
#endif

#if ENABLE_PATH_CHECK
static int
path_check_0(fpath, execpath)
     VALUE fpath;
     int execpath;
{
    struct stat st;
    const char *p0 = StringValueCStr(fpath);
    char *p = 0, *s;

    if (!is_absolute_path(p0)) {
	char *buf = my_getcwd();
	VALUE newpath;

	newpath = rb_str_new2(buf);
	free(buf);

	rb_str_cat2(newpath, "/");
	rb_str_cat2(newpath, p0);
	p0 = RSTRING(fpath = newpath)->ptr;
    }
    for (;;) {
#ifndef S_IWOTH
# define S_IWOTH 002
#endif
	if (stat(p0, &st) == 0 && S_ISDIR(st.st_mode) && (st.st_mode & S_IWOTH)
#ifdef S_ISVTX
	    && !(p && execpath && (st.st_mode & S_ISVTX))
#endif
	    ) {
	    rb_warn("Insecure world writable dir %s in %sPATH, mode 0%o",
		    p0, (execpath ? "" : "LOAD_"), st.st_mode);
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

static int
fpath_check(path)
    const char *path;
{
#if ENABLE_PATH_CHECK
    return path_check_0(rb_str_new2(path), Qfalse);
#else
    return 1;
#endif
}

int
rb_path_check(path)
    const char *path;
{
#if ENABLE_PATH_CHECK
    const char *p0, *p, *pend;
    const char sep = PATH_SEP_CHAR;

    if (!path) return 1;

    pend = path + strlen(path);
    p0 = path;
    p = strchr(path, sep);
    if (!p) p = pend;

    for (;;) {
	if (!path_check_0(rb_str_new(p0, p - p0), Qtrue)) {
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
    const char *file;
{
    int ret = 1;
    int fd = open(file, O_RDONLY);
    if (fd == -1) return 0;
#if !defined DOSISH
    {
	struct stat st;
	if (fstat(fd, &st) || !S_ISREG(st.st_mode)) {
	    ret = 0;
	}
    }
#endif
    (void)close(fd);
    return ret;
}

static int
is_explicit_relative(path)
    const char *path;
{
    if (*path++ != '.') return 0;
    if (*path == '.') path++;
    return isdirsep(*path);
}

extern VALUE rb_load_path;

int
rb_find_file_ext(filep, ext)
    VALUE *filep;
    const char * const *ext;
{
    const char *f = RSTRING(*filep)->ptr;
    VALUE fname, tmp;
    long i, j, fnlen;

    if (!ext[0]) return 0;

    if (f[0] == '~') {
	fname = rb_file_expand_path(*filep, Qnil);
	if (rb_safe_level() >= 2 && OBJ_TAINTED(fname)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
	}
	OBJ_FREEZE(fname);
	f = StringValueCStr(fname);
	*filep = fname;
    }

    if (is_absolute_path(f) || is_explicit_relative(f)) {
	fname = rb_str_dup(*filep);
	fnlen = RSTRING_LEN(fname);
	for (i=0; ext[i]; i++) {
	    rb_str_cat2(fname, ext[i]);
	    if (file_load_ok(StringValueCStr(fname))) {
		if (!is_absolute_path(f)) fname = rb_file_expand_path(fname, Qnil);
		OBJ_FREEZE(fname);
		*filep = fname;
		return i+1;
	    }
	    rb_str_set_len(fname, fnlen);
	}
	return 0;
    }

    if (!rb_load_path) return 0;
    Check_Type(rb_load_path, T_ARRAY);

    tmp = rb_str_tmp_new(MAXPATHLEN + 2);
    for (i=0;i<RARRAY(rb_load_path)->len;i++) {
	VALUE str = RARRAY(rb_load_path)->ptr[i];

	SafeStringValue(str);
	if (RSTRING(str)->len == 0) continue;
	file_expand_path(*filep, str, tmp);
	fnlen = RSTRING_LEN(tmp);
	for (j=0; ext[j]; j++) {
	    rb_str_cat2(tmp, ext[j]);
	    if (file_load_ok(RSTRING_PTR(tmp))) {
		rb_str_resize(tmp, 0);
		fname = rb_str_dup(*filep);
		rb_str_cat2(fname, ext[j]);
		OBJ_FREEZE(fname);
		*filep = fname;
		return j+1;
	    }
	    rb_str_set_len(tmp, fnlen);
	}
    }
    return 0;
}

VALUE
rb_find_file(path)
    VALUE path;
{
    VALUE tmp;
    const char *f = StringValueCStr(path);

    if (f[0] == '~') {
	path = rb_file_expand_path(path, Qnil);
	if (rb_safe_level() >= 1 && OBJ_TAINTED(path)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe path %s", f);
	}
	OBJ_FREEZE(path);
	f = StringValueCStr(path);
    }

#if defined(__MACOS__) || defined(riscos)
    if (is_macos_native_path(f)) {
	if (rb_safe_level() >= 1 && !fpath_check(f)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
	}
	if (file_load_ok(f)) return path;
	return 0;
    }
#endif

    if (is_absolute_path(f) || is_explicit_relative(f)) {
	if (rb_safe_level() >= 1 && !fpath_check(f)) {
	    rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
	}
	if (!file_load_ok(f)) return 0;
	if (!is_absolute_path(f)) path = rb_file_expand_path(path, Qnil);
	return path;
	return 0;
    }

    if (rb_safe_level() >= 4) {
	rb_raise(rb_eSecurityError, "loading from non-absolute path %s", f);
    }

    if (rb_load_path) {
	long i;

	Check_Type(rb_load_path, T_ARRAY);
	tmp = rb_str_tmp_new(MAXPATHLEN + 2);
	for (i=0;i<RARRAY(rb_load_path)->len;i++) {
	    VALUE str = RARRAY(rb_load_path)->ptr[i];
	    SafeStringValue(str);
	    if (RSTRING(str)->len > 0) {
		file_expand_path(path, str, tmp);
		f = RSTRING_PTR(tmp);
		if (file_load_ok(f)) goto found;
	    }
	}
	return 0;
      found:
	RBASIC(tmp)->klass = rb_obj_class(path);
	OBJ_FREEZE(tmp);
    }
    else {
	return 0;		/* no path, no load */
    }

    if (rb_safe_level() >= 1 && !fpath_check(f)) {
	rb_raise(rb_eSecurityError, "loading from unsafe file %s", f);
    }

    return tmp;
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


/*
 *  A <code>File</code> is an abstraction of any file object accessible
 *  by the program and is closely associated with class <code>IO</code>
 *  <code>File</code> includes the methods of module
 *  <code>FileTest</code> as class methods, allowing you to write (for
 *  example) <code>File.exist?("foo")</code>.
 *
 *  In the description of File methods,
 *  <em>permission bits</em> are a platform-specific
 *  set of bits that indicate permissions of a file. On Unix-based
 *  systems, permissions are viewed as a set of three octets, for the
 *  owner, the group, and the rest of the world. For each of these
 *  entities, permissions may be set to read, write, or execute the
 *  file:
 *
 *  The permission bits <code>0644</code> (in octal) would thus be
 *  interpreted as read/write for owner, and read-only for group and
 *  other. Higher-order bits may also be used to indicate the type of
 *  file (plain, directory, pipe, socket, and so on) and various other
 *  special features. If the permissions are for a directory, the
 *  meaning of the execute bit changes; when set the directory can be
 *  searched.
 *
 *  On non-Posix operating systems, there may be only the ability to
 *  make a file read-only or read-write. In this case, the remaining
 *  permission bits will be synthesized to resemble typical values. For
 *  instance, on Windows NT the default permission bits are
 *  <code>0644</code>, which means read/write for owner, read-only for
 *  all others. The only change that can be made is to make the file
 *  read-only, which is reported as <code>0444</code>.
 */

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

    define_filetest_function("identical?", test_identical, 2);

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
    rb_define_method(rb_cStat, "dev_major", rb_stat_dev_major, 0);
    rb_define_method(rb_cStat, "dev_minor", rb_stat_dev_minor, 0);
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
