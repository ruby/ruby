/**********************************************************************

  file.c -

  $Author$
  created at: Mon Nov 15 12:24:34 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#ifdef _WIN32
# include "missing/file.h"
# include "ruby.h"
#endif

#include <ctype.h>
#include <time.h>

#ifdef __CYGWIN__
# include <windows.h>
# include <sys/cygwin.h>
# include <wchar.h>
#endif

#ifdef __APPLE__
# if !(defined(__has_feature) && defined(__has_attribute))
/* Maybe a bug in SDK of Xcode 10.2.1 */
/* In this condition, <os/availability.h> does not define
 * API_AVAILABLE and similar, but __API_AVAILABLE and similar which
 * are defined in <Availability.h> */
#   define API_AVAILABLE(...)
#   define API_DEPRECATED(...)
# endif
# include <CoreFoundation/CFString.h>
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#endif

#ifdef HAVE_SYS_FILE_H
# include <sys/file.h>
#else
int flock(int, int);
#endif

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif
#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif

#ifdef HAVE_UTIME_H
# include <utime.h>
#elif defined HAVE_SYS_UTIME_H
# include <sys/utime.h>
#endif

#ifdef HAVE_PWD_H
# include <pwd.h>
#endif

#ifdef HAVE_SYS_SYSMACROS_H
# include <sys/sysmacros.h>
#endif

#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_SYS_MKDEV_H
# include <sys/mkdev.h>
#endif

#if defined(HAVE_FCNTL_H)
# include <fcntl.h>
#endif

#if defined(HAVE_SYS_TIME_H)
# include <sys/time.h>
#endif

#if !defined HAVE_LSTAT && !defined lstat
# define lstat stat
#endif

/* define system APIs */
#ifdef _WIN32
# include "win32/file.h"
# define STAT(p, s)      rb_w32_ustati128((p), (s))
# undef lstat
# define lstat(p, s)     rb_w32_ulstati128((p), (s))
# undef access
# define access(p, m)    rb_w32_uaccess((p), (m))
# undef truncate
# define truncate(p, n)  rb_w32_utruncate((p), (n))
# undef chmod
# define chmod(p, m)     rb_w32_uchmod((p), (m))
# undef chown
# define chown(p, o, g)  rb_w32_uchown((p), (o), (g))
# undef lchown
# define lchown(p, o, g) rb_w32_ulchown((p), (o), (g))
# undef utimensat
# define utimensat(s, p, t, f)   rb_w32_uutimensat((s), (p), (t), (f))
# undef link
# define link(f, t)      rb_w32_ulink((f), (t))
# undef unlink
# define unlink(p)       rb_w32_uunlink(p)
# undef readlink
# define readlink(f, t, l)    rb_w32_ureadlink((f), (t), (l))
# undef rename
# define rename(f, t)    rb_w32_urename((f), (t))
# undef symlink
# define symlink(s, l)   rb_w32_usymlink((s), (l))

# ifdef HAVE_REALPATH
/* Don't use native realpath(3) on Windows, as the check for
   absolute paths does not work for drive letters. */
#  undef HAVE_REALPATH
# endif
#else
# define STAT(p, s)      stat((p), (s))
#endif /* _WIN32 */

#if defined _WIN32 || defined __APPLE__
# define USE_OSPATH 1
# define TO_OSPATH(str) rb_str_encode_ospath(str)
#else
# define USE_OSPATH 0
# define TO_OSPATH(str) (str)
#endif

/* utime may fail if time is out-of-range for the FS [ruby-dev:38277] */
#if defined DOSISH || defined __CYGWIN__
# define UTIME_EINVAL
#endif

/* Solaris 10 realpath(3) doesn't support File.realpath */
#if defined HAVE_REALPATH && defined __sun && defined __SVR4
#undef HAVE_REALPATH
#endif

#ifdef HAVE_REALPATH
# include <limits.h>
# include <stdlib.h>
#endif

#include "dln.h"
#include "encindex.h"
#include "id.h"
#include "internal.h"
#include "internal/compilers.h"
#include "internal/dir.h"
#include "internal/error.h"
#include "internal/file.h"
#include "internal/io.h"
#include "internal/load.h"
#include "internal/object.h"
#include "internal/process.h"
#include "internal/thread.h"
#include "internal/vm.h"
#include "ruby/encoding.h"
#include "ruby/thread.h"
#include "ruby/util.h"

VALUE rb_cFile;
VALUE rb_mFileTest;
VALUE rb_cStat;

static VALUE
file_path_convert(VALUE name)
{
#ifndef _WIN32 /* non Windows == Unix */
    int fname_encidx = ENCODING_GET(name);
    int fs_encidx;
    if (ENCINDEX_US_ASCII != fname_encidx &&
        ENCINDEX_ASCII_8BIT != fname_encidx &&
        (fs_encidx = rb_filesystem_encindex()) != fname_encidx &&
        rb_default_internal_encoding() &&
        !rb_enc_str_asciionly_p(name)) {
        /* Don't call rb_filesystem_encoding() before US-ASCII and ASCII-8BIT */
        /* fs_encoding should be ascii compatible */
        rb_encoding *fname_encoding = rb_enc_from_index(fname_encidx);
        rb_encoding *fs_encoding = rb_enc_from_index(fs_encidx);
        name = rb_str_conv_enc(name, fname_encoding, fs_encoding);
    }
#endif
    return name;
}

static rb_encoding *
check_path_encoding(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);
    if (!rb_enc_asciicompat(enc)) {
        rb_raise(rb_eEncCompatError, "path name must be ASCII-compatible (%s): %"PRIsVALUE,
                 rb_enc_name(enc), rb_str_inspect(str));
    }
    return enc;
}

VALUE
rb_get_path_check_to_string(VALUE obj)
{
    VALUE tmp;
    ID to_path;

    if (RB_TYPE_P(obj, T_STRING)) {
        return obj;
    }
    CONST_ID(to_path, "to_path");
    tmp = rb_check_funcall_default(obj, to_path, 0, 0, obj);
    StringValue(tmp);
    return tmp;
}

VALUE
rb_get_path_check_convert(VALUE obj)
{
    obj = file_path_convert(obj);

    check_path_encoding(obj);
    if (!rb_str_to_cstr(obj)) {
        rb_raise(rb_eArgError, "path name contains null byte");
    }

    return rb_str_new4(obj);
}

VALUE
rb_get_path_no_checksafe(VALUE obj)
{
    return rb_get_path(obj);
}

VALUE
rb_get_path(VALUE obj)
{
    return rb_get_path_check_convert(rb_get_path_check_to_string(obj));
}

VALUE
rb_str_encode_ospath(VALUE path)
{
#if USE_OSPATH
    int encidx = ENCODING_GET(path);
#if 0 && defined _WIN32
    if (encidx == ENCINDEX_ASCII_8BIT) {
        encidx = rb_filesystem_encindex();
    }
#endif
    if (encidx != ENCINDEX_ASCII_8BIT && encidx != ENCINDEX_UTF_8) {
        rb_encoding *enc = rb_enc_from_index(encidx);
        rb_encoding *utf8 = rb_utf8_encoding();
        path = rb_str_conv_enc(path, enc, utf8);
    }
#endif /* USE_OSPATH */
    return path;
}

#ifdef __APPLE__
# define NORMALIZE_UTF8PATH 1

# ifdef HAVE_WORKING_FORK
static void
rb_CFString_class_initialize_before_fork(void)
{
    /*
     * Since macOS 13, CFString family API used in
     * rb_str_append_normalized_ospath may internally use Objective-C classes
     * (NSTaggedPointerString and NSPlaceholderMutableString) for small strings.
     *
     * On the other hand, Objective-C classes should not be used for the first
     * time in a fork()'ed but not exec()'ed process. Violations for this rule
     * can result deadlock during class initialization, so Objective-C runtime
     * conservatively crashes on such cases by default.
     *
     * Therefore, we need to use CFString API to initialize Objective-C classes
     * used internally *before* fork().
     *
     * For future changes, please note that this initialization process cannot
     * be done in ctor because NSTaggedPointerString in CoreFoundation is enabled
     * after CFStringInitializeTaggedStrings(), which is called during loading
     * Objective-C runtime after ctor.
     * For more details, see https://bugs.ruby-lang.org/issues/18912
     */

    /* Enough small but non-empty ASCII string to fit in NSTaggedPointerString. */
    const char small_str[] = "/";
    long len = sizeof(small_str) - 1;

    const CFAllocatorRef alloc = kCFAllocatorDefault;
    CFStringRef s = CFStringCreateWithBytesNoCopy(alloc,
                                                  (const UInt8 *)small_str,
                                                  len, kCFStringEncodingUTF8,
                                                  FALSE, kCFAllocatorNull);
    CFMutableStringRef m = CFStringCreateMutableCopy(alloc, len, s);
    CFRelease(m);
    CFRelease(s);
}
# endif /* HAVE_WORKING_FORK */

static VALUE
rb_str_append_normalized_ospath(VALUE str, const char *ptr, long len)
{
    CFIndex buflen = 0;
    CFRange all;
    CFStringRef s = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault,
                                                  (const UInt8 *)ptr, len,
                                                  kCFStringEncodingUTF8, FALSE,
                                                  kCFAllocatorNull);
    CFMutableStringRef m = CFStringCreateMutableCopy(kCFAllocatorDefault, len, s);
    long oldlen = RSTRING_LEN(str);

    CFStringNormalize(m, kCFStringNormalizationFormC);
    all = CFRangeMake(0, CFStringGetLength(m));
    CFStringGetBytes(m, all, kCFStringEncodingUTF8, '?', FALSE, NULL, 0, &buflen);
    rb_str_modify_expand(str, buflen);
    CFStringGetBytes(m, all, kCFStringEncodingUTF8, '?', FALSE,
                     (UInt8 *)(RSTRING_PTR(str) + oldlen), buflen, &buflen);
    rb_str_set_len(str, oldlen + buflen);
    CFRelease(m);
    CFRelease(s);
    return str;
}

VALUE
rb_str_normalize_ospath(const char *ptr, long len)
{
    const char *p = ptr;
    const char *e = ptr + len;
    const char *p1 = p;
    VALUE str = rb_str_buf_new(len);
    rb_encoding *enc = rb_utf8_encoding();
    rb_enc_associate(str, enc);

    while (p < e) {
        int l, c;
        int r = rb_enc_precise_mbclen(p, e, enc);
        if (!MBCLEN_CHARFOUND_P(r)) {
            /* invalid byte shall not happen but */
            static const char invalid[3] = "\xEF\xBF\xBD";
            rb_str_append_normalized_ospath(str, p1, p-p1);
            rb_str_cat(str, invalid, sizeof(invalid));
            p += 1;
            p1 = p;
            continue;
        }
        l = MBCLEN_CHARFOUND_LEN(r);
        c = rb_enc_mbc_to_codepoint(p, e, enc);
        if ((0x2000 <= c && c <= 0x2FFF) || (0xF900 <= c && c <= 0xFAFF) ||
                (0x2F800 <= c && c <= 0x2FAFF)) {
            if (p - p1 > 0) {
                rb_str_append_normalized_ospath(str, p1, p-p1);
            }
            rb_str_cat(str, p, l);
            p += l;
            p1 = p;
        }
        else {
            p += l;
        }
    }
    if (p - p1 > 0) {
        rb_str_append_normalized_ospath(str, p1, p-p1);
    }

    return str;
}

static int
ignored_char_p(const char *p, const char *e, rb_encoding *enc)
{
    unsigned char c;
    if (p+3 > e) return 0;
    switch ((unsigned char)*p) {
      case 0xe2:
        switch ((unsigned char)p[1]) {
          case 0x80:
            c = (unsigned char)p[2];
            /* c >= 0x200c && c <= 0x200f */
            if (c >= 0x8c && c <= 0x8f) return 3;
            /* c >= 0x202a && c <= 0x202e */
            if (c >= 0xaa && c <= 0xae) return 3;
            return 0;
          case 0x81:
            c = (unsigned char)p[2];
            /* c >= 0x206a && c <= 0x206f */
            if (c >= 0xaa && c <= 0xaf) return 3;
            return 0;
        }
        break;
      case 0xef:
        /* c == 0xfeff */
        if ((unsigned char)p[1] == 0xbb &&
            (unsigned char)p[2] == 0xbf)
            return 3;
        break;
    }
    return 0;
}
#else /* !__APPLE__ */
# define NORMALIZE_UTF8PATH 0
#endif /* __APPLE__ */

#define apply2args(n) (rb_check_arity(argc, n, UNLIMITED_ARGUMENTS), argc-=n)

struct apply_filename {
    const char *ptr;
    VALUE path;
};

struct apply_arg {
    int i;
    int argc;
    int errnum;
    int (*func)(const char *, void *);
    void *arg;
    struct apply_filename fn[FLEX_ARY_LEN];
};

static void *
no_gvl_apply2files(void *ptr)
{
    struct apply_arg *aa = ptr;

    for (aa->i = 0; aa->i < aa->argc; aa->i++) {
        if (aa->func(aa->fn[aa->i].ptr, aa->arg) < 0) {
            aa->errnum = errno;
            break;
        }
    }
    return 0;
}

#ifdef UTIME_EINVAL
NORETURN(static void utime_failed(struct apply_arg *));
static int utime_internal(const char *, void *);
#endif

static VALUE
apply2files(int (*func)(const char *, void *), int argc, VALUE *argv, void *arg)
{
    VALUE v;
    const size_t size = sizeof(struct apply_filename);
    const long len = (long)(offsetof(struct apply_arg, fn) + (size * argc));
    struct apply_arg *aa = ALLOCV(v, len);

    aa->errnum = 0;
    aa->argc = argc;
    aa->arg = arg;
    aa->func = func;

    for (aa->i = 0; aa->i < argc; aa->i++) {
        VALUE path = rb_get_path(argv[aa->i]);

        path = rb_str_encode_ospath(path);
        aa->fn[aa->i].ptr = RSTRING_PTR(path);
        aa->fn[aa->i].path = path;
    }

    IO_WITHOUT_GVL(no_gvl_apply2files, aa);
    if (aa->errnum) {
#ifdef UTIME_EINVAL
        if (func == utime_internal) {
            utime_failed(aa);
        }
#endif
        rb_syserr_fail_path(aa->errnum, aa->fn[aa->i].path);
    }
    if (v) {
        ALLOCV_END(v);
    }
    return LONG2FIX(argc);
}

static const rb_data_type_t stat_data_type = {
    "stat",
    {
        NULL,
        RUBY_TYPED_DEFAULT_FREE,
        NULL, // No external memory to report
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

struct rb_stat {
    struct stat stat;
    bool initialized;
};

static VALUE
stat_new_0(VALUE klass, const struct stat *st)
{
    struct rb_stat *rb_st;
    VALUE obj = TypedData_Make_Struct(klass, struct rb_stat, &stat_data_type, rb_st);
    if (st) {
        rb_st->stat = *st;
        rb_st->initialized = true;
    }
    return obj;
}

VALUE
rb_stat_new(const struct stat *st)
{
    return stat_new_0(rb_cStat, st);
}

static struct stat*
get_stat(VALUE self)
{
    struct rb_stat* rb_st;
    TypedData_Get_Struct(self, struct rb_stat, &stat_data_type, rb_st);
    if (!rb_st->initialized) rb_raise(rb_eTypeError, "uninitialized File::Stat");
    return &rb_st->stat;
}

static struct timespec stat_mtimespec(const struct stat *st);

/*
 *  call-seq:
 *     stat <=> other_stat    -> -1, 0, 1, nil
 *
 *  Compares File::Stat objects by comparing their respective modification
 *  times.
 *
 *  +nil+ is returned if +other_stat+ is not a File::Stat object
 *
 *     f1 = File.new("f1", "w")
 *     sleep 1
 *     f2 = File.new("f2", "w")
 *     f1.stat <=> f2.stat   #=> -1
 */

static VALUE
rb_stat_cmp(VALUE self, VALUE other)
{
    if (rb_obj_is_kind_of(other, rb_obj_class(self))) {
        struct timespec ts1 = stat_mtimespec(get_stat(self));
        struct timespec ts2 = stat_mtimespec(get_stat(other));
        if (ts1.tv_sec == ts2.tv_sec) {
            if (ts1.tv_nsec == ts2.tv_nsec) return INT2FIX(0);
            if (ts1.tv_nsec < ts2.tv_nsec) return INT2FIX(-1);
            return INT2FIX(1);
        }
        if (ts1.tv_sec < ts2.tv_sec) return INT2FIX(-1);
        return INT2FIX(1);
    }
    return Qnil;
}

#define ST2UINT(val) ((val) & ~(~1UL << (sizeof(val) * CHAR_BIT - 1)))

#ifndef NUM2DEVT
# define NUM2DEVT(v) NUM2UINT(v)
#endif
#ifndef DEVT2NUM
# define DEVT2NUM(v) UINT2NUM(v)
#endif
#ifndef PRI_DEVT_PREFIX
# define PRI_DEVT_PREFIX ""
#endif

/*
 *  call-seq:
 *     stat.dev    -> integer
 *
 *  Returns an integer representing the device on which <i>stat</i>
 *  resides.
 *
 *     File.stat("testfile").dev   #=> 774
 */

static VALUE
rb_stat_dev(VALUE self)
{
#if SIZEOF_STRUCT_STAT_ST_DEV <= SIZEOF_DEV_T
    return DEVT2NUM(get_stat(self)->st_dev);
#elif SIZEOF_STRUCT_STAT_ST_DEV <= SIZEOF_LONG
    return ULONG2NUM(get_stat(self)->st_dev);
#else
    return ULL2NUM(get_stat(self)->st_dev);
#endif
}

/*
 *  call-seq:
 *     stat.dev_major   -> integer
 *
 *  Returns the major part of <code>File_Stat#dev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").dev_major   #=> 2
 *     File.stat("/dev/tty").dev_major   #=> 5
 */

static VALUE
rb_stat_dev_major(VALUE self)
{
#if defined(major)
    return UINT2NUM(major(get_stat(self)->st_dev));
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.dev_minor   -> integer
 *
 *  Returns the minor part of <code>File_Stat#dev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").dev_minor   #=> 1
 *     File.stat("/dev/tty").dev_minor   #=> 0
 */

static VALUE
rb_stat_dev_minor(VALUE self)
{
#if defined(minor)
    return UINT2NUM(minor(get_stat(self)->st_dev));
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.ino   -> integer
 *
 *  Returns the inode number for <i>stat</i>.
 *
 *     File.stat("testfile").ino   #=> 1083669
 *
 */

static VALUE
rb_stat_ino(VALUE self)
{
#ifdef HAVE_STRUCT_STAT_ST_INOHIGH
    /* assume INTEGER_PACK_LSWORD_FIRST and st_inohigh is just next of st_ino */
    return rb_integer_unpack(&get_stat(self)->st_ino, 2,
            SIZEOF_STRUCT_STAT_ST_INO, 0,
            INTEGER_PACK_LSWORD_FIRST|INTEGER_PACK_NATIVE_BYTE_ORDER|
            INTEGER_PACK_2COMP);
#elif SIZEOF_STRUCT_STAT_ST_INO > SIZEOF_LONG
    return ULL2NUM(get_stat(self)->st_ino);
#else
    return ULONG2NUM(get_stat(self)->st_ino);
#endif
}

/*
 *  call-seq:
 *     stat.mode   -> integer
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
rb_stat_mode(VALUE self)
{
    return UINT2NUM(ST2UINT(get_stat(self)->st_mode));
}

/*
 *  call-seq:
 *     stat.nlink   -> integer
 *
 *  Returns the number of hard links to <i>stat</i>.
 *
 *     File.stat("testfile").nlink             #=> 1
 *     File.link("testfile", "testfile.bak")   #=> 0
 *     File.stat("testfile").nlink             #=> 2
 *
 */

static VALUE
rb_stat_nlink(VALUE self)
{
    /* struct stat::st_nlink is nlink_t in POSIX.  Not the case for Windows. */
    const struct stat *ptr = get_stat(self);

    if (sizeof(ptr->st_nlink) <= sizeof(int)) {
        return UINT2NUM((unsigned)ptr->st_nlink);
    }
    else if (sizeof(ptr->st_nlink) == sizeof(long)) {
        return ULONG2NUM((unsigned long)ptr->st_nlink);
    }
    else if (sizeof(ptr->st_nlink) == sizeof(LONG_LONG)) {
        return ULL2NUM((unsigned LONG_LONG)ptr->st_nlink);
    }
    else {
        rb_bug(":FIXME: don't know what to do");
    }
}

/*
 *  call-seq:
 *     stat.uid    -> integer
 *
 *  Returns the numeric user id of the owner of <i>stat</i>.
 *
 *     File.stat("testfile").uid   #=> 501
 *
 */

static VALUE
rb_stat_uid(VALUE self)
{
    return UIDT2NUM(get_stat(self)->st_uid);
}

/*
 *  call-seq:
 *     stat.gid   -> integer
 *
 *  Returns the numeric group id of the owner of <i>stat</i>.
 *
 *     File.stat("testfile").gid   #=> 500
 *
 */

static VALUE
rb_stat_gid(VALUE self)
{
    return GIDT2NUM(get_stat(self)->st_gid);
}

/*
 *  call-seq:
 *     stat.rdev   ->  integer or nil
 *
 *  Returns an integer representing the device type on which
 *  <i>stat</i> resides. Returns <code>nil</code> if the operating
 *  system doesn't support this feature.
 *
 *     File.stat("/dev/fd1").rdev   #=> 513
 *     File.stat("/dev/tty").rdev   #=> 1280
 */

static VALUE
rb_stat_rdev(VALUE self)
{
#ifdef HAVE_STRUCT_STAT_ST_RDEV
# if SIZEOF_STRUCT_STAT_ST_RDEV <= SIZEOF_DEV_T
    return DEVT2NUM(get_stat(self)->st_rdev);
# elif SIZEOF_STRUCT_STAT_ST_RDEV <= SIZEOF_LONG
    return ULONG2NUM(get_stat(self)->st_rdev);
# else
    return ULL2NUM(get_stat(self)->st_rdev);
# endif
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.rdev_major   -> integer
 *
 *  Returns the major part of <code>File_Stat#rdev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").rdev_major   #=> 2
 *     File.stat("/dev/tty").rdev_major   #=> 5
 */

static VALUE
rb_stat_rdev_major(VALUE self)
{
#if defined(HAVE_STRUCT_STAT_ST_RDEV) && defined(major)
    return UINT2NUM(major(get_stat(self)->st_rdev));
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.rdev_minor   -> integer
 *
 *  Returns the minor part of <code>File_Stat#rdev</code> or
 *  <code>nil</code>.
 *
 *     File.stat("/dev/fd1").rdev_minor   #=> 1
 *     File.stat("/dev/tty").rdev_minor   #=> 0
 */

static VALUE
rb_stat_rdev_minor(VALUE self)
{
#if defined(HAVE_STRUCT_STAT_ST_RDEV) && defined(minor)
    return UINT2NUM(minor(get_stat(self)->st_rdev));
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.size    -> integer
 *
 *  Returns the size of <i>stat</i> in bytes.
 *
 *     File.stat("testfile").size   #=> 66
 */

static VALUE
rb_stat_size(VALUE self)
{
    return OFFT2NUM(get_stat(self)->st_size);
}

/*
 *  call-seq:
 *     stat.blksize   -> integer or nil
 *
 *  Returns the native file system's block size. Will return <code>nil</code>
 *  on platforms that don't support this information.
 *
 *     File.stat("testfile").blksize   #=> 4096
 *
 */

static VALUE
rb_stat_blksize(VALUE self)
{
#ifdef HAVE_STRUCT_STAT_ST_BLKSIZE
    return ULONG2NUM(get_stat(self)->st_blksize);
#else
    return Qnil;
#endif
}

/*
 *  call-seq:
 *     stat.blocks    -> integer or nil
 *
 *  Returns the number of native file system blocks allocated for this
 *  file, or <code>nil</code> if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("testfile").blocks   #=> 2
 */

static VALUE
rb_stat_blocks(VALUE self)
{
#ifdef HAVE_STRUCT_STAT_ST_BLOCKS
# if SIZEOF_STRUCT_STAT_ST_BLOCKS > SIZEOF_LONG
    return ULL2NUM(get_stat(self)->st_blocks);
# else
    return ULONG2NUM(get_stat(self)->st_blocks);
# endif
#else
    return Qnil;
#endif
}

static struct timespec
stat_atimespec(const struct stat *st)
{
    struct timespec ts;
    ts.tv_sec = st->st_atime;
#if defined(HAVE_STRUCT_STAT_ST_ATIM)
    ts.tv_nsec = st->st_atim.tv_nsec;
#elif defined(HAVE_STRUCT_STAT_ST_ATIMESPEC)
    ts.tv_nsec = st->st_atimespec.tv_nsec;
#elif defined(HAVE_STRUCT_STAT_ST_ATIMENSEC)
    ts.tv_nsec = (long)st->st_atimensec;
#else
    ts.tv_nsec = 0;
#endif
    return ts;
}

static VALUE
stat_time(const struct timespec ts)
{
    return rb_time_nano_new(ts.tv_sec, ts.tv_nsec);
}

static VALUE
stat_atime(const struct stat *st)
{
    return stat_time(stat_atimespec(st));
}

static struct timespec
stat_mtimespec(const struct stat *st)
{
    struct timespec ts;
    ts.tv_sec = st->st_mtime;
#if defined(HAVE_STRUCT_STAT_ST_MTIM)
    ts.tv_nsec = st->st_mtim.tv_nsec;
#elif defined(HAVE_STRUCT_STAT_ST_MTIMESPEC)
    ts.tv_nsec = st->st_mtimespec.tv_nsec;
#elif defined(HAVE_STRUCT_STAT_ST_MTIMENSEC)
    ts.tv_nsec = (long)st->st_mtimensec;
#else
    ts.tv_nsec = 0;
#endif
    return ts;
}

static VALUE
stat_mtime(const struct stat *st)
{
    return stat_time(stat_mtimespec(st));
}

static struct timespec
stat_ctimespec(const struct stat *st)
{
    struct timespec ts;
    ts.tv_sec = st->st_ctime;
#if defined(HAVE_STRUCT_STAT_ST_CTIM)
    ts.tv_nsec = st->st_ctim.tv_nsec;
#elif defined(HAVE_STRUCT_STAT_ST_CTIMESPEC)
    ts.tv_nsec = st->st_ctimespec.tv_nsec;
#elif defined(HAVE_STRUCT_STAT_ST_CTIMENSEC)
    ts.tv_nsec = (long)st->st_ctimensec;
#else
    ts.tv_nsec = 0;
#endif
    return ts;
}

static VALUE
stat_ctime(const struct stat *st)
{
    return stat_time(stat_ctimespec(st));
}

#define HAVE_STAT_BIRTHTIME
#if defined(HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC)
typedef struct stat statx_data;
static VALUE
stat_birthtime(const struct stat *st)
{
    const struct timespec *ts = &st->st_birthtimespec;
    return rb_time_nano_new(ts->tv_sec, ts->tv_nsec);
}
#elif defined(_WIN32)
typedef struct stat statx_data;
# define stat_birthtime stat_ctime
#else
# undef HAVE_STAT_BIRTHTIME
#endif /* defined(HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC) */

/*
 *  call-seq:
 *     stat.atime   -> time
 *
 *  Returns the last access time for this file as an object of class
 *  Time.
 *
 *     File.stat("testfile").atime   #=> Wed Dec 31 18:00:00 CST 1969
 *
 */

static VALUE
rb_stat_atime(VALUE self)
{
    return stat_atime(get_stat(self));
}

/*
 *  call-seq:
 *     stat.mtime  ->  time
 *
 *  Returns the modification time of <i>stat</i>.
 *
 *     File.stat("testfile").mtime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_stat_mtime(VALUE self)
{
    return stat_mtime(get_stat(self));
}

/*
 *  call-seq:
 *     stat.ctime  ->  time
 *
 *  Returns the change time for <i>stat</i> (that is, the time
 *  directory information about the file was changed, not the file
 *  itself).
 *
 *  Note that on Windows (NTFS), returns creation time (birth time).
 *
 *     File.stat("testfile").ctime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_stat_ctime(VALUE self)
{
    return stat_ctime(get_stat(self));
}

#if defined(HAVE_STAT_BIRTHTIME)
/*
 *  call-seq:
 *     stat.birthtime  ->  time
 *
 *  Returns the birth time for <i>stat</i>.
 *
 *  If the platform doesn't have birthtime, raises NotImplementedError.
 *
 *     File.write("testfile", "foo")
 *     sleep 10
 *     File.write("testfile", "bar")
 *     sleep 10
 *     File.chmod(0644, "testfile")
 *     sleep 10
 *     File.read("testfile")
 *     File.stat("testfile").birthtime   #=> 2014-02-24 11:19:17 +0900
 *     File.stat("testfile").mtime       #=> 2014-02-24 11:19:27 +0900
 *     File.stat("testfile").ctime       #=> 2014-02-24 11:19:37 +0900
 *     File.stat("testfile").atime       #=> 2014-02-24 11:19:47 +0900
 *
 */

static VALUE
rb_stat_birthtime(VALUE self)
{
    return stat_birthtime(get_stat(self));
}
#else
# define rb_stat_birthtime rb_f_notimplement
#endif

/*
 * call-seq:
 *   stat.inspect  ->  string
 *
 * Produce a nicely formatted description of <i>stat</i>.
 *
 *   File.stat("/etc/passwd").inspect
 *      #=> "#<File::Stat dev=0xe000005, ino=1078078, mode=0100644,
 *      #    nlink=1, uid=0, gid=0, rdev=0x0, size=1374, blksize=4096,
 *      #    blocks=8, atime=Wed Dec 10 10:16:12 CST 2003,
 *      #    mtime=Fri Sep 12 15:41:41 CDT 2003,
 *      #    ctime=Mon Oct 27 11:20:27 CST 2003,
 *      #    birthtime=Mon Aug 04 08:13:49 CDT 2003>"
 */

static VALUE
rb_stat_inspect(VALUE self)
{
    VALUE str;
    size_t i;
    static const struct {
        const char *name;
        VALUE (*func)(VALUE);
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
#if defined(HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC)
        {"birthtime",   rb_stat_birthtime},
#endif
    };

    struct rb_stat* rb_st;
    TypedData_Get_Struct(self, struct rb_stat, &stat_data_type, rb_st);
    if (!rb_st->initialized) {
        return rb_sprintf("#<%s: uninitialized>", rb_obj_classname(self));
    }

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
            rb_str_catf(str, "0%lo", (unsigned long)NUM2ULONG(v));
        }
        else if (i == 0 || i == 6) { /* dev/rdev */
            rb_str_catf(str, "0x%"PRI_DEVT_PREFIX"x", NUM2DEVT(v));
        }
        else {
            rb_str_append(str, rb_inspect(v));
        }
    }
    rb_str_buf_cat2(str, ">");

    return str;
}

typedef struct no_gvl_stat_data {
    struct stat *st;
    union {
        const char *path;
        int fd;
    } file;
} no_gvl_stat_data;

static VALUE
no_gvl_fstat(void *data)
{
    no_gvl_stat_data *arg = data;
    return (VALUE)fstat(arg->file.fd, arg->st);
}

static int
fstat_without_gvl(int fd, struct stat *st)
{
    no_gvl_stat_data data;

    data.file.fd = fd;
    data.st = st;

    return (int)(VALUE)rb_thread_io_blocking_region(no_gvl_fstat, &data, fd);
}

static void *
no_gvl_stat(void * data)
{
    no_gvl_stat_data *arg = data;
    return (void *)(VALUE)STAT(arg->file.path, arg->st);
}

static int
stat_without_gvl(const char *path, struct stat *st)
{
    no_gvl_stat_data data;

    data.file.path = path;
    data.st = st;

    return IO_WITHOUT_GVL_INT(no_gvl_stat, &data);
}

#if !defined(HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC) && \
    defined(HAVE_STRUCT_STATX_STX_BTIME)

# ifndef HAVE_STATX
#   ifdef HAVE_SYSCALL_H
#     include <syscall.h>
#   elif defined HAVE_SYS_SYSCALL_H
#     include <sys/syscall.h>
#   endif
#   if defined __linux__
#     include <linux/stat.h>
static inline int
statx(int dirfd, const char *pathname, int flags,
      unsigned int mask, struct statx *statxbuf)
{
    return (int)syscall(__NR_statx, dirfd, pathname, flags, mask, statxbuf);
}
#   endif /* __linux__ */
# endif /* HAVE_STATX */

typedef struct no_gvl_statx_data {
    struct statx *stx;
    int fd;
    const char *path;
    int flags;
    unsigned int mask;
} no_gvl_statx_data;

static VALUE
io_blocking_statx(void *data)
{
    no_gvl_statx_data *arg = data;
    return (VALUE)statx(arg->fd, arg->path, arg->flags, arg->mask, arg->stx);
}

static void *
no_gvl_statx(void *data)
{
    return (void *)io_blocking_statx(data);
}

static int
statx_without_gvl(const char *path, struct statx *stx, unsigned int mask)
{
    no_gvl_statx_data data = {stx, AT_FDCWD, path, 0, mask};

    /* call statx(2) with pathname */
    return IO_WITHOUT_GVL_INT(no_gvl_statx, &data);
}

static int
fstatx_without_gvl(int fd, struct statx *stx, unsigned int mask)
{
    no_gvl_statx_data data = {stx, fd, "", AT_EMPTY_PATH, mask};

    /* call statx(2) with fd */
    return (int)rb_thread_io_blocking_region(io_blocking_statx, &data, fd);
}

static int
rb_statx(VALUE file, struct statx *stx, unsigned int mask)
{
    VALUE tmp;
    int result;

    tmp = rb_check_convert_type_with_id(file, T_FILE, "IO", idTo_io);
    if (!NIL_P(tmp)) {
        rb_io_t *fptr;
        GetOpenFile(tmp, fptr);
        result = fstatx_without_gvl(fptr->fd, stx, mask);
        file = tmp;
    }
    else {
        FilePathValue(file);
        file = rb_str_encode_ospath(file);
        result = statx_without_gvl(RSTRING_PTR(file), stx, mask);
    }
    RB_GC_GUARD(file);
    return result;
}

# define statx_has_birthtime(st) ((st)->stx_mask & STATX_BTIME)

NORETURN(static void statx_notimplement(const char *field_name));

/* rb_notimplement() shows "function is unimplemented on this machine".
   It is not applicable to statx which behavior depends on the filesystem. */
static void
statx_notimplement(const char *field_name)
{
    rb_raise(rb_eNotImpError,
             "%s is unimplemented on this filesystem",
             field_name);
}

static VALUE
statx_birthtime(const struct statx *stx, VALUE fname)
{
    if (!statx_has_birthtime(stx)) {
        /* birthtime is not supported on the filesystem */
        statx_notimplement("birthtime");
    }
    return rb_time_nano_new((time_t)stx->stx_btime.tv_sec, stx->stx_btime.tv_nsec);
}

typedef struct statx statx_data;
# define HAVE_STAT_BIRTHTIME

#elif defined(HAVE_STAT_BIRTHTIME)
# define statx_without_gvl(path, st, mask) stat_without_gvl(path, st)
# define fstatx_without_gvl(fd, st, mask) fstat_without_gvl(fd, st)
# define statx_birthtime(st, fname) stat_birthtime(st)
# define statx_has_birthtime(st) 1
# define rb_statx(file, st, mask) rb_stat(file, st)
#else
# define statx_has_birthtime(st) 0
#endif /* !defined(HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC) && \
        defined(HAVE_STRUCT_STATX_STX_BTIME) */

static int
rb_stat(VALUE file, struct stat *st)
{
    VALUE tmp;
    int result;

    tmp = rb_check_convert_type_with_id(file, T_FILE, "IO", idTo_io);
    if (!NIL_P(tmp)) {
        rb_io_t *fptr;

        GetOpenFile(tmp, fptr);
        result = fstat_without_gvl(fptr->fd, st);
        file = tmp;
    }
    else {
        FilePathValue(file);
        file = rb_str_encode_ospath(file);
        result = stat_without_gvl(RSTRING_PTR(file), st);
    }
    RB_GC_GUARD(file);
    return result;
}

/*
 *  call-seq:
 *    File.stat(filepath) ->  stat
 *
 *  Returns a File::Stat object for the file at +filepath+ (see File::Stat):
 *
 *    File.stat('t.txt').class # => File::Stat
 *
 */

static VALUE
rb_file_s_stat(VALUE klass, VALUE fname)
{
    struct stat st;

    FilePathValue(fname);
    fname = rb_str_encode_ospath(fname);
    if (stat_without_gvl(RSTRING_PTR(fname), &st) < 0) {
        rb_sys_fail_path(fname);
    }
    return rb_stat_new(&st);
}

/*
 *  call-seq:
 *     ios.stat    -> stat
 *
 *  Returns status information for <em>ios</em> as an object of type
 *  File::Stat.
 *
 *     f = File.new("testfile")
 *     s = f.stat
 *     "%o" % s.mode   #=> "100644"
 *     s.blksize       #=> 4096
 *     s.atime         #=> Wed Apr 09 08:53:54 CDT 2003
 *
 */

static VALUE
rb_io_stat(VALUE obj)
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fptr->fd, &st) == -1) {
        rb_sys_fail_path(fptr->pathv);
    }
    return rb_stat_new(&st);
}

#ifdef HAVE_LSTAT
static void *
no_gvl_lstat(void *ptr)
{
    no_gvl_stat_data *arg = ptr;
    return (void *)(VALUE)lstat(arg->file.path, arg->st);
}

static int
lstat_without_gvl(const char *path, struct stat *st)
{
    no_gvl_stat_data data;

    data.file.path = path;
    data.st = st;

    return IO_WITHOUT_GVL_INT(no_gvl_lstat, &data);
}
#endif /* HAVE_LSTAT */

/*
 *  call-seq:
 *    File.lstat(filepath) -> stat
 *
 *  Like File::stat, but does not follow the last symbolic link;
 *  instead, returns a File::Stat object for the link itself.
 *
 *    File.symlink('t.txt', 'symlink')
 *    File.stat('symlink').size  # => 47
 *    File.lstat('symlink').size # => 5
 *
 */

static VALUE
rb_file_s_lstat(VALUE klass, VALUE fname)
{
#ifdef HAVE_LSTAT
    struct stat st;

    FilePathValue(fname);
    fname = rb_str_encode_ospath(fname);
    if (lstat_without_gvl(StringValueCStr(fname), &st) == -1) {
        rb_sys_fail_path(fname);
    }
    return rb_stat_new(&st);
#else
    return rb_file_s_stat(klass, fname);
#endif
}

/*
 *  call-seq:
 *    lstat -> stat
 *
 *  Like File#stat, but does not follow the last symbolic link;
 *  instead, returns a File::Stat object for the link itself:
 *
 *    File.symlink('t.txt', 'symlink')
 *    f = File.new('symlink')
 *    f.stat.size  # => 47
 *    f.lstat.size # => 11
 *
 */

static VALUE
rb_file_lstat(VALUE obj)
{
#ifdef HAVE_LSTAT
    rb_io_t *fptr;
    struct stat st;
    VALUE path;

    GetOpenFile(obj, fptr);
    if (NIL_P(fptr->pathv)) return Qnil;
    path = rb_str_encode_ospath(fptr->pathv);
    if (lstat_without_gvl(RSTRING_PTR(path), &st) == -1) {
        rb_sys_fail_path(fptr->pathv);
    }
    return rb_stat_new(&st);
#else
    return rb_io_stat(obj);
#endif
}

static int
rb_group_member(GETGROUPS_T gid)
{
#if defined(_WIN32) || !defined(HAVE_GETGROUPS)
    return FALSE;
#else
    int rv = FALSE;
    int groups;
    VALUE v = 0;
    GETGROUPS_T *gary;
    int anum = -1;

    if (getgid() == gid || getegid() == gid)
        return TRUE;

    groups = getgroups(0, NULL);
    gary = ALLOCV_N(GETGROUPS_T, v, groups);
    anum = getgroups(groups, gary);
    while (--anum >= 0) {
        if (gary[anum] == gid) {
            rv = TRUE;
            break;
        }
    }
    if (v)
        ALLOCV_END(v);

    return rv;
#endif /* defined(_WIN32) || !defined(HAVE_GETGROUPS) */
}

#ifndef S_IXUGO
#  define S_IXUGO		(S_IXUSR | S_IXGRP | S_IXOTH)
#endif

#if defined(S_IXGRP) && !defined(_WIN32) && !defined(__CYGWIN__)
#define USE_GETEUID 1
#endif

#ifndef HAVE_EACCESS
int
eaccess(const char *path, int mode)
{
#ifdef USE_GETEUID
    struct stat st;
    rb_uid_t euid;

    euid = geteuid();

    /* no setuid nor setgid. run shortcut. */
    if (getuid() == euid && getgid() == getegid())
        return access(path, mode);

    if (STAT(path, &st) < 0)
        return -1;

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

    if ((int)(st.st_mode & mode) == mode) return 0;

    return -1;
#else
    return access(path, mode);
#endif /* USE_GETEUID */
}
#endif /* HAVE_EACCESS */

struct access_arg {
    const char *path;
    int mode;
};

static void *
nogvl_eaccess(void *ptr)
{
    struct access_arg *aa = ptr;

    return (void *)(VALUE)eaccess(aa->path, aa->mode);
}

static int
rb_eaccess(VALUE fname, int mode)
{
    struct access_arg aa;

    FilePathValue(fname);
    fname = rb_str_encode_ospath(fname);
    aa.path = StringValueCStr(fname);
    aa.mode = mode;

    return IO_WITHOUT_GVL_INT(nogvl_eaccess, &aa);
}

static void *
nogvl_access(void *ptr)
{
    struct access_arg *aa = ptr;

    return (void *)(VALUE)access(aa->path, aa->mode);
}

static int
rb_access(VALUE fname, int mode)
{
    struct access_arg aa;

    FilePathValue(fname);
    fname = rb_str_encode_ospath(fname);
    aa.path = StringValueCStr(fname);
    aa.mode = mode;

    return IO_WITHOUT_GVL_INT(nogvl_access, &aa);
}

/*
 * Document-class: FileTest
 *
 *  FileTest implements file test operations similar to those used in
 *  File::Stat. It exists as a standalone module, and its methods are
 *  also insinuated into the File class. (Note that this is not done
 *  by inclusion: the interpreter cheats).
 *
 */

/*
 * call-seq:
 *   File.directory?(path) -> true or false
 *
 * With string +object+ given, returns +true+ if +path+ is a string path
 * leading to a directory, or to a symbolic link to a directory; +false+ otherwise:
 *
 *   File.directory?('.')              # => true
 *   File.directory?('foo')            # => false
 *   File.symlink('.', 'dirlink')      # => 0
 *   File.directory?('dirlink')        # => true
 *   File.symlink('t,txt', 'filelink') # => 0
 *   File.directory?('filelink')       # => false
 *
 * Argument +path+ can be an IO object.
 *
 */

VALUE
rb_file_directory_p(VALUE obj, VALUE fname)
{
#ifndef S_ISDIR
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif

    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISDIR(st.st_mode)) return Qtrue;
    return Qfalse;
}

/*
 * call-seq:
 *   File.pipe?(filepath) -> true or false
 *
 * Returns +true+ if +filepath+ points to a pipe, +false+ otherwise:
 *
 *   File.mkfifo('tmp/fifo')
 *   File.pipe?('tmp/fifo') # => true
 *   File.pipe?('t.txt')    # => false
 *
 */

static VALUE
rb_file_pipe_p(VALUE obj, VALUE fname)
{
#ifdef S_IFIFO
#  ifndef S_ISFIFO
#    define S_ISFIFO(m) (((m) & S_IFMT) == S_IFIFO)
#  endif

    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISFIFO(st.st_mode)) return Qtrue;

#endif
    return Qfalse;
}

/*
 * call-seq:
 *   File.symlink?(filepath) -> true or false
 *
 * Returns +true+ if +filepath+ points to a symbolic link, +false+ otherwise:
 *
 *   symlink = File.symlink('t.txt', 'symlink')
 *   File.symlink?('symlink') # => true
 *   File.symlink?('t.txt')   # => false
 *
 */

static VALUE
rb_file_symlink_p(VALUE obj, VALUE fname)
{
#ifndef S_ISLNK
#  ifdef _S_ISLNK
#    define S_ISLNK(m) _S_ISLNK(m)
#  else
#    ifdef _S_IFLNK
#      define S_ISLNK(m) (((m) & S_IFMT) == _S_IFLNK)
#    else
#      ifdef S_IFLNK
#	 define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)
#      endif
#    endif
#  endif
#endif

#ifdef S_ISLNK
    struct stat st;

    FilePathValue(fname);
    fname = rb_str_encode_ospath(fname);
    if (lstat_without_gvl(StringValueCStr(fname), &st) < 0) return Qfalse;
    if (S_ISLNK(st.st_mode)) return Qtrue;
#endif

    return Qfalse;
}

/*
 * call-seq:
 *   File.socket?(filepath)   ->  true or false
 *
 * Returns +true+ if +filepath+ points to a socket, +false+ otherwise:
 *
 *   require 'socket'
 *   File.socket?(Socket.new(:INET, :STREAM)) # => true
 *   File.socket?(File.new('t.txt'))          # => false
 *
 */

static VALUE
rb_file_socket_p(VALUE obj, VALUE fname)
{
#ifndef S_ISSOCK
#  ifdef _S_ISSOCK
#    define S_ISSOCK(m) _S_ISSOCK(m)
#  else
#    ifdef _S_IFSOCK
#      define S_ISSOCK(m) (((m) & S_IFMT) == _S_IFSOCK)
#    else
#      ifdef S_IFSOCK
#	 define S_ISSOCK(m) (((m) & S_IFMT) == S_IFSOCK)
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
 *   File.blockdev?(filepath) -> true or false
 *
 * Returns +true+ if +filepath+ points to a block device, +false+ otherwise:
 *
 *   File.blockdev?('/dev/sda1')       # => true
 *   File.blockdev?(File.new('t.tmp')) # => false
 *
 */

static VALUE
rb_file_blockdev_p(VALUE obj, VALUE fname)
{
#ifndef S_ISBLK
#   ifdef S_IFBLK
#	define S_ISBLK(m) (((m) & S_IFMT) == S_IFBLK)
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
 *   File.chardev?(filepath) -> true or false
 *
 * Returns +true+ if +filepath+ points to a character device, +false+ otherwise.
 *
 *   File.chardev?($stdin)     # => true
 *   File.chardev?('t.txt')     # => false
 *
 */
static VALUE
rb_file_chardev_p(VALUE obj, VALUE fname)
{
#ifndef S_ISCHR
#   define S_ISCHR(m) (((m) & S_IFMT) == S_IFCHR)
#endif

    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    if (S_ISCHR(st.st_mode)) return Qtrue;

    return Qfalse;
}

/*
 * call-seq:
 *    File.exist?(file_name)    ->  true or false
 *
 * Return <code>true</code> if the named file exists.
 *
 * _file_name_ can be an IO object.
 *
 * "file exists" means that stat() or fstat() system call is successful.
 */

static VALUE
rb_file_exist_p(VALUE obj, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *    File.readable?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file is readable by the effective
 * user and group id of this process. See eaccess(3).
 *
 * Note that some OS-level security features may cause this to return true
 * even though the file is not readable by the effective user/group.
 */

static VALUE
rb_file_readable_p(VALUE obj, VALUE fname)
{
    return RBOOL(rb_eaccess(fname, R_OK) >= 0);
}

/*
 * call-seq:
 *    File.readable_real?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file is readable by the real
 * user and group id of this process. See access(3).
 *
 * Note that some OS-level security features may cause this to return true
 * even though the file is not readable by the real user/group.
 */

static VALUE
rb_file_readable_real_p(VALUE obj, VALUE fname)
{
    return RBOOL(rb_access(fname, R_OK) >= 0);
}

#ifndef S_IRUGO
#  define S_IRUGO		(S_IRUSR | S_IRGRP | S_IROTH)
#endif

#ifndef S_IWUGO
#  define S_IWUGO		(S_IWUSR | S_IWGRP | S_IWOTH)
#endif

/*
 * call-seq:
 *    File.world_readable?(file_name)   -> integer or nil
 *
 * If <i>file_name</i> is readable by others, returns an integer
 * representing the file permission bits of <i>file_name</i>. Returns
 * <code>nil</code> otherwise. The meaning of the bits is platform
 * dependent; on Unix systems, see <code>stat(2)</code>.
 *
 * _file_name_ can be an IO object.
 *
 *    File.world_readable?("/etc/passwd")	    #=> 420
 *    m = File.world_readable?("/etc/passwd")
 *    sprintf("%o", m)				    #=> "644"
 */

static VALUE
rb_file_world_readable_p(VALUE obj, VALUE fname)
{
#ifdef S_IROTH
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qnil;
    if ((st.st_mode & (S_IROTH)) == S_IROTH) {
        return UINT2NUM(st.st_mode & (S_IRUGO|S_IWUGO|S_IXUGO));
    }
#endif
    return Qnil;
}

/*
 * call-seq:
 *    File.writable?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file is writable by the effective
 * user and group id of this process. See eaccess(3).
 *
 * Note that some OS-level security features may cause this to return true
 * even though the file is not writable by the effective user/group.
 */

static VALUE
rb_file_writable_p(VALUE obj, VALUE fname)
{
    return RBOOL(rb_eaccess(fname, W_OK) >= 0);
}

/*
 * call-seq:
 *    File.writable_real?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file is writable by the real
 * user and group id of this process. See access(3).
 *
 * Note that some OS-level security features may cause this to return true
 * even though the file is not writable by the real user/group.
 */

static VALUE
rb_file_writable_real_p(VALUE obj, VALUE fname)
{
    return RBOOL(rb_access(fname, W_OK) >= 0);
}

/*
 * call-seq:
 *    File.world_writable?(file_name)   -> integer or nil
 *
 * If <i>file_name</i> is writable by others, returns an integer
 * representing the file permission bits of <i>file_name</i>. Returns
 * <code>nil</code> otherwise. The meaning of the bits is platform
 * dependent; on Unix systems, see <code>stat(2)</code>.
 *
 * _file_name_ can be an IO object.
 *
 *    File.world_writable?("/tmp")		    #=> 511
 *    m = File.world_writable?("/tmp")
 *    sprintf("%o", m)				    #=> "777"
 */

static VALUE
rb_file_world_writable_p(VALUE obj, VALUE fname)
{
#ifdef S_IWOTH
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qnil;
    if ((st.st_mode & (S_IWOTH)) == S_IWOTH) {
        return UINT2NUM(st.st_mode & (S_IRUGO|S_IWUGO|S_IXUGO));
    }
#endif
    return Qnil;
}

/*
 * call-seq:
 *    File.executable?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file is executable by the effective
 * user and group id of this process. See eaccess(3).
 *
 * Windows does not support execute permissions separately from read
 * permissions. On Windows, a file is only considered executable if it ends in
 * .bat, .cmd, .com, or .exe.
 *
 * Note that some OS-level security features may cause this to return true
 * even though the file is not executable by the effective user/group.
 */

static VALUE
rb_file_executable_p(VALUE obj, VALUE fname)
{
    return RBOOL(rb_eaccess(fname, X_OK) >= 0);
}

/*
 * call-seq:
 *    File.executable_real?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file is executable by the real
 * user and group id of this process. See access(3).
 *
 * Windows does not support execute permissions separately from read
 * permissions. On Windows, a file is only considered executable if it ends in
 * .bat, .cmd, .com, or .exe.
 *
 * Note that some OS-level security features may cause this to return true
 * even though the file is not executable by the real user/group.
 */

static VALUE
rb_file_executable_real_p(VALUE obj, VALUE fname)
{
    return RBOOL(rb_access(fname, X_OK) >= 0);
}

#ifndef S_ISREG
#   define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#endif

/*
 * call-seq:
 *    File.file?(file) -> true or false
 *
 * Returns +true+ if the named +file+ exists and is a regular file.
 *
 * +file+ can be an IO object.
 *
 * If the +file+ argument is a symbolic link, it will resolve the symbolic link
 * and use the file referenced by the link.
 */

static VALUE
rb_file_file_p(VALUE obj, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return RBOOL(S_ISREG(st.st_mode));
}

/*
 * call-seq:
 *    File.zero?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file exists and has
 * a zero size.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_zero_p(VALUE obj, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return RBOOL(st.st_size == 0);
}

/*
 * call-seq:
 *    File.size?(file_name)   -> Integer or nil
 *
 * Returns +nil+ if +file_name+ doesn't exist or has zero size, the size of the
 * file otherwise.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_size_p(VALUE obj, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qnil;
    if (st.st_size == 0) return Qnil;
    return OFFT2NUM(st.st_size);
}

/*
 * call-seq:
 *    File.owned?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file exists and the
 * effective used id of the calling process is the owner of
 * the file.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_owned_p(VALUE obj, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return RBOOL(st.st_uid == geteuid());
}

static VALUE
rb_file_rowned_p(VALUE obj, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return RBOOL(st.st_uid == getuid());
}

/*
 * call-seq:
 *    File.grpowned?(file_name)   -> true or false
 *
 * Returns <code>true</code> if the named file exists and the
 * effective group id of the calling process is the owner of
 * the file. Returns <code>false</code> on Windows.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_grpowned_p(VALUE obj, VALUE fname)
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
check3rdbyte(VALUE fname, int mode)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) return Qfalse;
    return RBOOL(st.st_mode & mode);
}
#endif

/*
 * call-seq:
 *   File.setuid?(file_name)   ->  true or false
 *
 * Returns <code>true</code> if the named file has the setuid bit set.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_suid_p(VALUE obj, VALUE fname)
{
#ifdef S_ISUID
    return check3rdbyte(fname, S_ISUID);
#else
    return Qfalse;
#endif
}

/*
 * call-seq:
 *   File.setgid?(file_name)   ->  true or false
 *
 * Returns <code>true</code> if the named file has the setgid bit set.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_sgid_p(VALUE obj, VALUE fname)
{
#ifdef S_ISGID
    return check3rdbyte(fname, S_ISGID);
#else
    return Qfalse;
#endif
}

/*
 * call-seq:
 *   File.sticky?(file_name)   ->  true or false
 *
 * Returns <code>true</code> if the named file has the sticky bit set.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_sticky_p(VALUE obj, VALUE fname)
{
#ifdef S_ISVTX
    return check3rdbyte(fname, S_ISVTX);
#else
    return Qfalse;
#endif
}

/*
 * call-seq:
 *   File.identical?(file_1, file_2)   ->  true or false
 *
 * Returns <code>true</code> if the named files are identical.
 *
 * _file_1_ and _file_2_ can be an IO object.
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
rb_file_identical_p(VALUE obj, VALUE fname1, VALUE fname2)
{
#ifndef _WIN32
    struct stat st1, st2;

    if (rb_stat(fname1, &st1) < 0) return Qfalse;
    if (rb_stat(fname2, &st2) < 0) return Qfalse;
    if (st1.st_dev != st2.st_dev) return Qfalse;
    if (st1.st_ino != st2.st_ino) return Qfalse;
    return Qtrue;
#else
    extern VALUE rb_w32_file_identical_p(VALUE, VALUE);
    return rb_w32_file_identical_p(fname1, fname2);
#endif
}

/*
 * call-seq:
 *    File.size(file_name)   -> integer
 *
 * Returns the size of <code>file_name</code>.
 *
 * _file_name_ can be an IO object.
 */

static VALUE
rb_file_s_size(VALUE klass, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) {
        int e = errno;
        FilePathValue(fname);
        rb_syserr_fail_path(e, fname);
    }
    return OFFT2NUM(st.st_size);
}

static VALUE
rb_file_ftype(const struct stat *st)
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

    return rb_usascii_str_new2(t);
}

/*
 *  call-seq:
 *     File.ftype(file_name)   -> string
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
rb_file_s_ftype(VALUE klass, VALUE fname)
{
    struct stat st;

    FilePathValue(fname);
    fname = rb_str_encode_ospath(fname);
    if (lstat_without_gvl(StringValueCStr(fname), &st) == -1) {
        rb_sys_fail_path(fname);
    }

    return rb_file_ftype(&st);
}

/*
 *  call-seq:
 *     File.atime(file_name)  ->  time
 *
 *  Returns the last access time for the named file as a Time object.
 *
 *  _file_name_ can be an IO object.
 *
 *     File.atime("testfile")   #=> Wed Apr 09 08:51:48 CDT 2003
 *
 */

static VALUE
rb_file_s_atime(VALUE klass, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) {
        int e = errno;
        FilePathValue(fname);
        rb_syserr_fail_path(e, fname);
    }
    return stat_atime(&st);
}

/*
 *  call-seq:
 *     file.atime    -> time
 *
 *  Returns the last access time (a Time object) for <i>file</i>, or
 *  epoch if <i>file</i> has not been accessed.
 *
 *     File.new("testfile").atime   #=> Wed Dec 31 18:00:00 CST 1969
 *
 */

static VALUE
rb_file_atime(VALUE obj)
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fptr->fd, &st) == -1) {
        rb_sys_fail_path(fptr->pathv);
    }
    return stat_atime(&st);
}

/*
 *  call-seq:
 *     File.mtime(file_name)  ->  time
 *
 *  Returns the modification time for the named file as a Time object.
 *
 *  _file_name_ can be an IO object.
 *
 *     File.mtime("testfile")   #=> Tue Apr 08 12:58:04 CDT 2003
 *
 */

static VALUE
rb_file_s_mtime(VALUE klass, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) {
        int e = errno;
        FilePathValue(fname);
        rb_syserr_fail_path(e, fname);
    }
    return stat_mtime(&st);
}

/*
 *  call-seq:
 *     file.mtime  ->  time
 *
 *  Returns the modification time for <i>file</i>.
 *
 *     File.new("testfile").mtime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_file_mtime(VALUE obj)
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fptr->fd, &st) == -1) {
        rb_sys_fail_path(fptr->pathv);
    }
    return stat_mtime(&st);
}

/*
 *  call-seq:
 *     File.ctime(file_name)  -> time
 *
 *  Returns the change time for the named file (the time at which
 *  directory information about the file was changed, not the file
 *  itself).
 *
 *  _file_name_ can be an IO object.
 *
 *  Note that on Windows (NTFS), returns creation time (birth time).
 *
 *     File.ctime("testfile")   #=> Wed Apr 09 08:53:13 CDT 2003
 *
 */

static VALUE
rb_file_s_ctime(VALUE klass, VALUE fname)
{
    struct stat st;

    if (rb_stat(fname, &st) < 0) {
        int e = errno;
        FilePathValue(fname);
        rb_syserr_fail_path(e, fname);
    }
    return stat_ctime(&st);
}

/*
 *  call-seq:
 *     file.ctime  ->  time
 *
 *  Returns the change time for <i>file</i> (that is, the time directory
 *  information about the file was changed, not the file itself).
 *
 *  Note that on Windows (NTFS), returns creation time (birth time).
 *
 *     File.new("testfile").ctime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 */

static VALUE
rb_file_ctime(VALUE obj)
{
    rb_io_t *fptr;
    struct stat st;

    GetOpenFile(obj, fptr);
    if (fstat(fptr->fd, &st) == -1) {
        rb_sys_fail_path(fptr->pathv);
    }
    return stat_ctime(&st);
}

#if defined(HAVE_STAT_BIRTHTIME)
/*
 *  call-seq:
 *     File.birthtime(file_name)  -> time
 *
 *  Returns the birth time for the named file.
 *
 *  _file_name_ can be an IO object.
 *
 *     File.birthtime("testfile")   #=> Wed Apr 09 08:53:13 CDT 2003
 *
 *  If the platform doesn't have birthtime, raises NotImplementedError.
 *
 */

VALUE
rb_file_s_birthtime(VALUE klass, VALUE fname)
{
    statx_data st;

    if (rb_statx(fname, &st, STATX_BTIME) < 0) {
        int e = errno;
        FilePathValue(fname);
        rb_syserr_fail_path(e, fname);
    }
    return statx_birthtime(&st, fname);
}
#else
# define rb_file_s_birthtime rb_f_notimplement
#endif

#if defined(HAVE_STAT_BIRTHTIME)
/*
 *  call-seq:
 *     file.birthtime  ->  time
 *
 *  Returns the birth time for <i>file</i>.
 *
 *     File.new("testfile").birthtime   #=> Wed Apr 09 08:53:14 CDT 2003
 *
 *  If the platform doesn't have birthtime, raises NotImplementedError.
 *
 */

static VALUE
rb_file_birthtime(VALUE obj)
{
    rb_io_t *fptr;
    statx_data st;

    GetOpenFile(obj, fptr);
    if (fstatx_without_gvl(fptr->fd, &st, STATX_BTIME) == -1) {
        rb_sys_fail_path(fptr->pathv);
    }
    return statx_birthtime(&st, fptr->pathv);
}
#else
# define rb_file_birthtime rb_f_notimplement
#endif

rb_off_t
rb_file_size(VALUE file)
{
    if (RB_TYPE_P(file, T_FILE)) {
        rb_io_t *fptr;
        struct stat st;

        RB_IO_POINTER(file, fptr);
        if (fptr->mode & FMODE_WRITABLE) {
            rb_io_flush_raw(file, 0);
        }

        if (fstat(fptr->fd, &st) == -1) {
            rb_sys_fail_path(fptr->pathv);
        }

        return st.st_size;
    }
    else {
        return NUM2OFFT(rb_funcall(file, idSize, 0));
    }
}

/*
 *  call-seq:
 *     file.size    -> integer
 *
 *  Returns the size of <i>file</i> in bytes.
 *
 *     File.new("testfile").size   #=> 66
 *
 */

static VALUE
file_size(VALUE self)
{
    return OFFT2NUM(rb_file_size(self));
}

struct nogvl_chmod_data {
    const char *path;
    mode_t mode;
};

static void *
nogvl_chmod(void *ptr)
{
    struct nogvl_chmod_data *data = ptr;
    int ret = chmod(data->path, data->mode);
    return (void *)(VALUE)ret;
}

static int
rb_chmod(const char *path, mode_t mode)
{
    struct nogvl_chmod_data data = {
        .path = path,
        .mode = mode,
    };
    return IO_WITHOUT_GVL_INT(nogvl_chmod, &data);
}

static int
chmod_internal(const char *path, void *mode)
{
    return chmod(path, *(mode_t *)mode);
}

/*
 *  call-seq:
 *     File.chmod(mode_int, file_name, ... )  ->  integer
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
rb_file_s_chmod(int argc, VALUE *argv, VALUE _)
{
    mode_t mode;

    apply2args(1);
    mode = NUM2MODET(*argv++);

    return apply2files(chmod_internal, argc, argv, &mode);
}

#ifdef HAVE_FCHMOD
struct nogvl_fchmod_data {
    int fd;
    mode_t mode;
};

static VALUE
io_blocking_fchmod(void *ptr)
{
    struct nogvl_fchmod_data *data = ptr;
    int ret = fchmod(data->fd, data->mode);
    return (VALUE)ret;
}

static int
rb_fchmod(int fd, mode_t mode)
{
    (void)rb_chmod; /* suppress unused-function warning when HAVE_FCHMOD */
    struct nogvl_fchmod_data data = {.fd = fd, .mode = mode};
    return (int)rb_thread_io_blocking_region(io_blocking_fchmod, &data, fd);
}
#endif

/*
 *  call-seq:
 *     file.chmod(mode_int)   -> 0
 *
 *  Changes permission bits on <i>file</i> to the bit pattern
 *  represented by <i>mode_int</i>. Actual effects are platform
 *  dependent; on Unix systems, see <code>chmod(2)</code> for details.
 *  Follows symbolic links. Also see File#lchmod.
 *
 *     f = File.new("out", "w");
 *     f.chmod(0644)   #=> 0
 */

static VALUE
rb_file_chmod(VALUE obj, VALUE vmode)
{
    rb_io_t *fptr;
    mode_t mode;
#if !defined HAVE_FCHMOD || !HAVE_FCHMOD
    VALUE path;
#endif

    mode = NUM2MODET(vmode);

    GetOpenFile(obj, fptr);
#ifdef HAVE_FCHMOD
    if (rb_fchmod(fptr->fd, mode) == -1) {
        if (HAVE_FCHMOD || errno != ENOSYS)
            rb_sys_fail_path(fptr->pathv);
    }
    else {
        if (!HAVE_FCHMOD) return INT2FIX(0);
    }
#endif
#if !defined HAVE_FCHMOD || !HAVE_FCHMOD
    if (NIL_P(fptr->pathv)) return Qnil;
    path = rb_str_encode_ospath(fptr->pathv);
    if (rb_chmod(RSTRING_PTR(path), mode) == -1)
        rb_sys_fail_path(fptr->pathv);
#endif

    return INT2FIX(0);
}

#if defined(HAVE_LCHMOD)
static int
lchmod_internal(const char *path, void *mode)
{
    return lchmod(path, *(mode_t *)mode);
}

/*
 *  call-seq:
 *     File.lchmod(mode_int, file_name, ...)  -> integer
 *
 *  Equivalent to File::chmod, but does not follow symbolic links (so
 *  it will change the permissions associated with the link, not the
 *  file referenced by the link). Often not available.
 *
 */

static VALUE
rb_file_s_lchmod(int argc, VALUE *argv, VALUE _)
{
    mode_t mode;

    apply2args(1);
    mode = NUM2MODET(*argv++);

    return apply2files(lchmod_internal, argc, argv, &mode);
}
#else
#define rb_file_s_lchmod rb_f_notimplement
#endif

static inline rb_uid_t
to_uid(VALUE u)
{
    if (NIL_P(u)) {
        return (rb_uid_t)-1;
    }
    return NUM2UIDT(u);
}

static inline rb_gid_t
to_gid(VALUE g)
{
    if (NIL_P(g)) {
        return (rb_gid_t)-1;
    }
    return NUM2GIDT(g);
}

struct chown_args {
    rb_uid_t owner;
    rb_gid_t group;
};

static int
chown_internal(const char *path, void *arg)
{
    struct chown_args *args = arg;
    return chown(path, args->owner, args->group);
}

/*
 *  call-seq:
 *     File.chown(owner_int, group_int, file_name, ...)  ->  integer
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
rb_file_s_chown(int argc, VALUE *argv, VALUE _)
{
    struct chown_args arg;

    apply2args(2);
    arg.owner = to_uid(*argv++);
    arg.group = to_gid(*argv++);

    return apply2files(chown_internal, argc, argv, &arg);
}

struct nogvl_chown_data {
    union {
        const char *path;
        int fd;
    } as;
    struct chown_args new;
};

static void *
nogvl_chown(void *ptr)
{
    struct nogvl_chown_data *data = ptr;
    return (void *)(VALUE)chown(data->as.path, data->new.owner, data->new.group);
}

static int
rb_chown(const char *path, rb_uid_t owner, rb_gid_t group)
{
    struct nogvl_chown_data data = {
        .as = {.path = path},
        .new = {.owner = owner, .group = group},
    };
    return IO_WITHOUT_GVL_INT(nogvl_chown, &data);
}

#ifdef HAVE_FCHOWN
static void *
nogvl_fchown(void *ptr)
{
    struct nogvl_chown_data *data = ptr;
    return (void *)(VALUE)fchown(data->as.fd, data->new.owner, data->new.group);
}

static int
rb_fchown(int fd, rb_uid_t owner, rb_gid_t group)
{
    (void)rb_chown; /* suppress unused-function warning when HAVE_FCHMOD */
    struct nogvl_chown_data data = {
        .as = {.fd = fd},
        .new = {.owner = owner, .group = group},
    };
    return IO_WITHOUT_GVL_INT(nogvl_fchown, &data);
}
#endif

/*
 *  call-seq:
 *     file.chown(owner_int, group_int )   -> 0
 *
 *  Changes the owner and group of <i>file</i> to the given numeric
 *  owner and group id's. Only a process with superuser privileges may
 *  change the owner of a file. The current owner of a file may change
 *  the file's group to any group to which the owner belongs. A
 *  <code>nil</code> or -1 owner or group id is ignored. Follows
 *  symbolic links. See also File#lchown.
 *
 *     File.new("testfile").chown(502, 1000)
 *
 */

static VALUE
rb_file_chown(VALUE obj, VALUE owner, VALUE group)
{
    rb_io_t *fptr;
    rb_uid_t o;
    rb_gid_t g;
#ifndef HAVE_FCHOWN
    VALUE path;
#endif

    o = to_uid(owner);
    g = to_gid(group);
    GetOpenFile(obj, fptr);
#ifndef HAVE_FCHOWN
    if (NIL_P(fptr->pathv)) return Qnil;
    path = rb_str_encode_ospath(fptr->pathv);
    if (rb_chown(RSTRING_PTR(path), o, g) == -1)
        rb_sys_fail_path(fptr->pathv);
#else
    if (rb_fchown(fptr->fd, o, g) == -1)
        rb_sys_fail_path(fptr->pathv);
#endif

    return INT2FIX(0);
}

#if defined(HAVE_LCHOWN)
static int
lchown_internal(const char *path, void *arg)
{
    struct chown_args *args = arg;
    return lchown(path, args->owner, args->group);
}

/*
 *  call-seq:
 *     File.lchown(owner_int, group_int, file_name,..) -> integer
 *
 *  Equivalent to File::chown, but does not follow symbolic
 *  links (so it will change the owner associated with the link, not the
 *  file referenced by the link). Often not available. Returns number
 *  of files in the argument list.
 *
 */

static VALUE
rb_file_s_lchown(int argc, VALUE *argv, VALUE _)
{
    struct chown_args arg;

    apply2args(2);
    arg.owner = to_uid(*argv++);
    arg.group = to_gid(*argv++);

    return apply2files(lchown_internal, argc, argv, &arg);
}
#else
#define rb_file_s_lchown rb_f_notimplement
#endif

struct utime_args {
    const struct timespec* tsp;
    VALUE atime, mtime;
    int follow; /* Whether to act on symlinks (1) or their referent (0) */
};

#ifdef UTIME_EINVAL
NORETURN(static void utime_failed(struct apply_arg *));

static void
utime_failed(struct apply_arg *aa)
{
    int e = aa->errnum;
    VALUE path = aa->fn[aa->i].path;
    struct utime_args *ua = aa->arg;

    if (ua->tsp && e == EINVAL) {
        VALUE e[2], a = Qnil, m = Qnil;
        int d = 0;
        VALUE atime = ua->atime;
        VALUE mtime = ua->mtime;

        if (!NIL_P(atime)) {
            a = rb_inspect(atime);
        }
        if (!NIL_P(mtime) && mtime != atime && !rb_equal(atime, mtime)) {
            m = rb_inspect(mtime);
        }
        if (NIL_P(a)) e[0] = m;
        else if (NIL_P(m) || rb_str_cmp(a, m) == 0) e[0] = a;
        else {
            e[0] = rb_str_plus(a, rb_str_new_cstr(" or "));
            rb_str_append(e[0], m);
            d = 1;
        }
        if (!NIL_P(e[0])) {
            if (path) {
                if (!d) e[0] = rb_str_dup(e[0]);
                rb_str_append(rb_str_cat2(e[0], " for "), path);
            }
            e[1] = INT2FIX(EINVAL);
            rb_exc_raise(rb_class_new_instance(2, e, rb_eSystemCallError));
        }
    }
    rb_syserr_fail_path(e, path);
}
#endif /* UTIME_EINVAL */

#if defined(HAVE_UTIMES)

# if !defined(HAVE_UTIMENSAT)
/* utimensat() is not found, runtime check is not needed */
# elif defined(__APPLE__) && \
    (!defined(MAC_OS_X_VERSION_13_0) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_13_0))

#   if defined(__has_attribute) && __has_attribute(availability)
typedef int utimensat_func(int, const char *, const struct timespec [2], int);

RBIMPL_WARNING_PUSH()
RBIMPL_WARNING_IGNORED(-Wunguarded-availability-new)
static inline utimensat_func *
rb_utimensat(void)
{
    return &utimensat;
}
RBIMPL_WARNING_POP()

#   define utimensat rb_utimensat()
#   else /* __API_AVAILABLE macro does nothing on gcc */
__attribute__((weak)) int utimensat(int, const char *, const struct timespec [2], int);
#   endif /* defined(__has_attribute) && __has_attribute(availability) */
# endif /* __APPLE__ && < MAC_OS_X_VERSION_13_0 */

static int
utime_internal(const char *path, void *arg)
{
    struct utime_args *v = arg;
    const struct timespec *tsp = v->tsp;
    struct timeval tvbuf[2], *tvp = NULL;

#if defined(HAVE_UTIMENSAT)
# if defined(__APPLE__)
    const int try_utimensat = utimensat != NULL;
    const int try_utimensat_follow = utimensat != NULL;
# else /* !__APPLE__ */
#   define TRY_UTIMENSAT 1
    static int try_utimensat = 1;
#   ifdef AT_SYMLINK_NOFOLLOW
    static int try_utimensat_follow = 1;
#   else
    const int try_utimensat_follow = 0;
#   endif
# endif /* __APPLE__ */
    int flags = 0;

    if (v->follow ? try_utimensat_follow : try_utimensat) {
# ifdef AT_SYMLINK_NOFOLLOW
        if (v->follow) {
            flags = AT_SYMLINK_NOFOLLOW;
        }
# endif

        int result = utimensat(AT_FDCWD, path, tsp, flags);
# ifdef TRY_UTIMENSAT
        if (result < 0 && errno == ENOSYS) {
# ifdef AT_SYMLINK_NOFOLLOW
            try_utimensat_follow = 0;
# endif /* AT_SYMLINK_NOFOLLOW */
            if (!v->follow)
                try_utimensat = 0;
        }
        else
# endif /* TRY_UTIMESAT */
            return result;
    }
#endif /* defined(HAVE_UTIMENSAT) */

    if (tsp) {
        tvbuf[0].tv_sec = tsp[0].tv_sec;
        tvbuf[0].tv_usec = (int)(tsp[0].tv_nsec / 1000);
        tvbuf[1].tv_sec = tsp[1].tv_sec;
        tvbuf[1].tv_usec = (int)(tsp[1].tv_nsec / 1000);
        tvp = tvbuf;
    }
#ifdef HAVE_LUTIMES
    if (v->follow) return lutimes(path, tvp);
#endif
    return utimes(path, tvp);
}

#else /* !defined(HAVE_UTIMES) */

#if !defined HAVE_UTIME_H && !defined HAVE_SYS_UTIME_H
struct utimbuf {
    long actime;
    long modtime;
};
#endif

static int
utime_internal(const char *path, void *arg)
{
    struct utime_args *v = arg;
    const struct timespec *tsp = v->tsp;
    struct utimbuf utbuf, *utp = NULL;
    if (tsp) {
        utbuf.actime = tsp[0].tv_sec;
        utbuf.modtime = tsp[1].tv_sec;
        utp = &utbuf;
    }
    return utime(path, utp);
}
#endif /* !defined(HAVE_UTIMES) */

static VALUE
utime_internal_i(int argc, VALUE *argv, int follow)
{
    struct utime_args args;
    struct timespec tss[2], *tsp = NULL;

    apply2args(2);
    args.atime = *argv++;
    args.mtime = *argv++;

    args.follow = follow;

    if (!NIL_P(args.atime) || !NIL_P(args.mtime)) {
        tsp = tss;
        tsp[0] = rb_time_timespec(args.atime);
        if (args.atime == args.mtime)
            tsp[1] = tsp[0];
        else
            tsp[1] = rb_time_timespec(args.mtime);
    }
    args.tsp = tsp;

    return apply2files(utime_internal, argc, argv, &args);
}

/*
 * call-seq:
 *  File.utime(atime, mtime, file_name, ...)   ->  integer
 *
 * Sets the access and modification times of each named file to the
 * first two arguments. If a file is a symlink, this method acts upon
 * its referent rather than the link itself; for the inverse
 * behavior see File.lutime. Returns the number of file
 * names in the argument list.
 */

static VALUE
rb_file_s_utime(int argc, VALUE *argv, VALUE _)
{
    return utime_internal_i(argc, argv, FALSE);
}

#if defined(HAVE_UTIMES) && (defined(HAVE_LUTIMES) || (defined(HAVE_UTIMENSAT) && defined(AT_SYMLINK_NOFOLLOW)))

/*
 * call-seq:
 *  File.lutime(atime, mtime, file_name, ...)   ->  integer
 *
 * Sets the access and modification times of each named file to the
 * first two arguments. If a file is a symlink, this method acts upon
 * the link itself as opposed to its referent; for the inverse
 * behavior, see File.utime. Returns the number of file
 * names in the argument list.
 */

static VALUE
rb_file_s_lutime(int argc, VALUE *argv, VALUE _)
{
    return utime_internal_i(argc, argv, TRUE);
}
#else
#define rb_file_s_lutime rb_f_notimplement
#endif

#ifdef RUBY_FUNCTION_NAME_STRING
# define syserr_fail2(e, s1, s2) syserr_fail2_in(RUBY_FUNCTION_NAME_STRING, e, s1, s2)
#else
# define syserr_fail2_in(func, e, s1, s2) syserr_fail2(e, s1, s2)
#endif
#define sys_fail2(s1, s2) syserr_fail2(errno, s1, s2)
NORETURN(static void syserr_fail2_in(const char *,int,VALUE,VALUE));
static void
syserr_fail2_in(const char *func, int e, VALUE s1, VALUE s2)
{
    VALUE str;
#ifdef MAX_PATH
    const int max_pathlen = MAX_PATH;
#else
    const int max_pathlen = MAXPATHLEN;
#endif

    if (e == EEXIST) {
        rb_syserr_fail_path(e, rb_str_ellipsize(s2, max_pathlen));
    }
    str = rb_str_new_cstr("(");
    rb_str_append(str, rb_str_ellipsize(s1, max_pathlen));
    rb_str_cat2(str, ", ");
    rb_str_append(str, rb_str_ellipsize(s2, max_pathlen));
    rb_str_cat2(str, ")");
#ifdef RUBY_FUNCTION_NAME_STRING
    rb_syserr_fail_path_in(func, e, str);
#else
    rb_syserr_fail_path(e, str);
#endif
}

#ifdef HAVE_LINK
/*
 *  call-seq:
 *     File.link(old_name, new_name)    -> 0
 *
 *  Creates a new name for an existing file using a hard link. Will not
 *  overwrite <i>new_name</i> if it already exists (raising a subclass
 *  of SystemCallError). Not available on all platforms.
 *
 *     File.link("testfile", ".testfile")   #=> 0
 *     IO.readlines(".testfile")[0]         #=> "This is line one\n"
 */

static VALUE
rb_file_s_link(VALUE klass, VALUE from, VALUE to)
{
    FilePathValue(from);
    FilePathValue(to);
    from = rb_str_encode_ospath(from);
    to = rb_str_encode_ospath(to);

    if (link(StringValueCStr(from), StringValueCStr(to)) < 0) {
        sys_fail2(from, to);
    }
    return INT2FIX(0);
}
#else
#define rb_file_s_link rb_f_notimplement
#endif

#ifdef HAVE_SYMLINK
/*
 *  call-seq:
 *     File.symlink(old_name, new_name)   -> 0
 *
 *  Creates a symbolic link called <i>new_name</i> for the existing file
 *  <i>old_name</i>. Raises a NotImplemented exception on
 *  platforms that do not support symbolic links.
 *
 *     File.symlink("testfile", "link2test")   #=> 0
 *
 */

static VALUE
rb_file_s_symlink(VALUE klass, VALUE from, VALUE to)
{
    FilePathValue(from);
    FilePathValue(to);
    from = rb_str_encode_ospath(from);
    to = rb_str_encode_ospath(to);

    if (symlink(StringValueCStr(from), StringValueCStr(to)) < 0) {
        sys_fail2(from, to);
    }
    return INT2FIX(0);
}
#else
#define rb_file_s_symlink rb_f_notimplement
#endif

#ifdef HAVE_READLINK
/*
 *  call-seq:
 *     File.readlink(link_name)  ->  file_name
 *
 *  Returns the name of the file referenced by the given link.
 *  Not available on all platforms.
 *
 *     File.symlink("testfile", "link2test")   #=> 0
 *     File.readlink("link2test")              #=> "testfile"
 */

static VALUE
rb_file_s_readlink(VALUE klass, VALUE path)
{
    return rb_readlink(path, rb_filesystem_encoding());
}

struct readlink_arg {
    const char *path;
    char *buf;
    size_t size;
};

static void *
nogvl_readlink(void *ptr)
{
    struct readlink_arg *ra = ptr;

    return (void *)(VALUE)readlink(ra->path, ra->buf, ra->size);
}

static ssize_t
readlink_without_gvl(VALUE path, VALUE buf, size_t size)
{
    struct readlink_arg ra;

    ra.path = RSTRING_PTR(path);
    ra.buf = RSTRING_PTR(buf);
    ra.size = size;

    return (ssize_t)IO_WITHOUT_GVL(nogvl_readlink, &ra);
}

VALUE
rb_readlink(VALUE path, rb_encoding *enc)
{
    int size = 100;
    ssize_t rv;
    VALUE v;

    FilePathValue(path);
    path = rb_str_encode_ospath(path);
    v = rb_enc_str_new(0, size, enc);
    while ((rv = readlink_without_gvl(path, v, size)) == size
#ifdef _AIX
            || (rv < 0 && errno == ERANGE) /* quirky behavior of GPFS */
#endif
        ) {
        rb_str_modify_expand(v, size);
        size *= 2;
        rb_str_set_len(v, size);
    }
    if (rv < 0) {
        int e = errno;
        rb_str_resize(v, 0);
        rb_syserr_fail_path(e, path);
    }
    rb_str_resize(v, rv);

    return v;
}
#else
#define rb_file_s_readlink rb_f_notimplement
#endif

static int
unlink_internal(const char *path, void *arg)
{
    return unlink(path);
}

/*
 *  call-seq:
 *     File.delete(file_name, ...)  -> integer
 *     File.unlink(file_name, ...)  -> integer
 *
 *  Deletes the named files, returning the number of names
 *  passed as arguments. Raises an exception on any error.
 *  Since the underlying implementation relies on the
 *  <code>unlink(2)</code> system call, the type of
 *  exception raised depends on its error type (see
 *  https://linux.die.net/man/2/unlink) and has the form of
 *  e.g. Errno::ENOENT.
 *
 *  See also Dir::rmdir.
 */

static VALUE
rb_file_s_unlink(int argc, VALUE *argv, VALUE klass)
{
    return apply2files(unlink_internal, argc, argv, 0);
}

struct rename_args {
    const char *src;
    const char *dst;
};

static void *
no_gvl_rename(void *ptr)
{
    struct rename_args *ra = ptr;

    return (void *)(VALUE)rename(ra->src, ra->dst);
}

/*
 *  call-seq:
 *     File.rename(old_name, new_name)   -> 0
 *
 *  Renames the given file to the new name. Raises a SystemCallError
 *  if the file cannot be renamed.
 *
 *     File.rename("afile", "afile.bak")   #=> 0
 */

static VALUE
rb_file_s_rename(VALUE klass, VALUE from, VALUE to)
{
    struct rename_args ra;
    VALUE f, t;

    FilePathValue(from);
    FilePathValue(to);
    f = rb_str_encode_ospath(from);
    t = rb_str_encode_ospath(to);
    ra.src = StringValueCStr(f);
    ra.dst = StringValueCStr(t);
#if defined __CYGWIN__
    errno = 0;
#endif
    if (IO_WITHOUT_GVL_INT(no_gvl_rename, &ra) < 0) {
        int e = errno;
#if defined DOSISH
        switch (e) {
          case EEXIST:
            if (chmod(ra.dst, 0666) == 0 &&
                unlink(ra.dst) == 0 &&
                rename(ra.src, ra.dst) == 0)
                return INT2FIX(0);
        }
#endif
        syserr_fail2(e, from, to);
    }

    return INT2FIX(0);
}

/*
 *  call-seq:
 *     File.umask()          -> integer
 *     File.umask(integer)   -> integer
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
rb_file_s_umask(int argc, VALUE *argv, VALUE _)
{
    mode_t omask = 0;

    switch (argc) {
      case 0:
        omask = umask(0);
        umask(omask);
        break;
      case 1:
        omask = umask(NUM2MODET(argv[0]));
        break;
      default:
        rb_error_arity(argc, 0, 1);
    }
    return MODET2NUM(omask);
}

#ifdef __CYGWIN__
#undef DOSISH
#endif
#if defined __CYGWIN__ || defined DOSISH
#define DOSISH_UNC
#define DOSISH_DRIVE_LETTER
#define FILE_ALT_SEPARATOR '\\'
#endif
#ifdef FILE_ALT_SEPARATOR
#define isdirsep(x) ((x) == '/' || (x) == FILE_ALT_SEPARATOR)
# ifdef DOSISH
static const char file_alt_separator[] = {FILE_ALT_SEPARATOR, '\0'};
# endif
#else
#define isdirsep(x) ((x) == '/')
#endif

#ifndef USE_NTFS
#  if defined _WIN32
#    define USE_NTFS 1
#  else
#    define USE_NTFS 0
#  endif
#endif

#ifndef USE_NTFS_ADS
# if USE_NTFS
#   define USE_NTFS_ADS 1
# else
#   define USE_NTFS_ADS 0
# endif
#endif

#if USE_NTFS
#define istrailinggarbage(x) ((x) == '.' || (x) == ' ')
#else
#define istrailinggarbage(x) 0
#endif

#if USE_NTFS_ADS
# define isADS(x) ((x) == ':')
#else
# define isADS(x) 0
#endif

#define Next(p, e, enc) ((p) + rb_enc_mbclen((p), (e), (enc)))
#define Inc(p, e, enc) ((p) = Next((p), (e), (enc)))

#if defined(DOSISH_UNC)
#define has_unc(buf) (isdirsep((buf)[0]) && isdirsep((buf)[1]))
#else
#define has_unc(buf) 0
#endif

#ifdef DOSISH_DRIVE_LETTER
static inline int
has_drive_letter(const char *buf)
{
    if (ISALPHA(buf[0]) && buf[1] == ':') {
        return 1;
    }
    else {
        return 0;
    }
}

#ifndef _WIN32
static char*
getcwdofdrv(int drv)
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
    oldcwd = ruby_getcwd();
    if (chdir(drive) == 0) {
        drvcwd = ruby_getcwd();
        chdir(oldcwd);
        xfree(oldcwd);
    }
    else {
        /* perhaps the drive is not exist. we return only drive letter */
        drvcwd = strdup(drive);
    }
    return drvcwd;
}

static inline int
not_same_drive(VALUE path, int drive)
{
    const char *p = RSTRING_PTR(path);
    if (RSTRING_LEN(path) < 2) return 0;
    if (has_drive_letter(p)) {
        return TOLOWER(p[0]) != TOLOWER(drive);
    }
    else {
        return has_unc(p);
    }
}
#endif /* _WIN32 */
#endif /* DOSISH_DRIVE_LETTER */

static inline char *
skiproot(const char *path, const char *end, rb_encoding *enc)
{
#ifdef DOSISH_DRIVE_LETTER
    if (path + 2 <= end && has_drive_letter(path)) path += 2;
#endif
    while (path < end && isdirsep(*path)) path++;
    return (char *)path;
}

#define nextdirsep rb_enc_path_next
char *
rb_enc_path_next(const char *s, const char *e, rb_encoding *enc)
{
    while (s < e && !isdirsep(*s)) {
        Inc(s, e, enc);
    }
    return (char *)s;
}

#if defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER)
#define skipprefix rb_enc_path_skip_prefix
#else
#define skipprefix(path, end, enc) (path)
#endif
char *
rb_enc_path_skip_prefix(const char *path, const char *end, rb_encoding *enc)
{
#if defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER)
#ifdef DOSISH_UNC
    if (path + 2 <= end && isdirsep(path[0]) && isdirsep(path[1])) {
        path += 2;
        while (path < end && isdirsep(*path)) path++;
        if ((path = rb_enc_path_next(path, end, enc)) < end && path[0] && path[1] && !isdirsep(path[1]))
            path = rb_enc_path_next(path + 1, end, enc);
        return (char *)path;
    }
#endif
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(path))
        return (char *)(path + 2);
#endif
#endif /* defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER) */
    return (char *)path;
}

static inline char *
skipprefixroot(const char *path, const char *end, rb_encoding *enc)
{
#if defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER)
    char *p = skipprefix(path, end, enc);
    while (isdirsep(*p)) p++;
    return p;
#else
    return skiproot(path, end, enc);
#endif
}

#define strrdirsep rb_enc_path_last_separator
char *
rb_enc_path_last_separator(const char *path, const char *end, rb_encoding *enc)
{
    char *last = NULL;
    while (path < end) {
        if (isdirsep(*path)) {
            const char *tmp = path++;
            while (path < end && isdirsep(*path)) path++;
            if (path >= end) break;
            last = (char *)tmp;
        }
        else {
            Inc(path, end, enc);
        }
    }
    return last;
}

static char *
chompdirsep(const char *path, const char *end, rb_encoding *enc)
{
    while (path < end) {
        if (isdirsep(*path)) {
            const char *last = path++;
            while (path < end && isdirsep(*path)) path++;
            if (path >= end) return (char *)last;
        }
        else {
            Inc(path, end, enc);
        }
    }
    return (char *)path;
}

char *
rb_enc_path_end(const char *path, const char *end, rb_encoding *enc)
{
    if (path < end && isdirsep(*path)) path++;
    return chompdirsep(path, end, enc);
}

static rb_encoding *
fs_enc_check(VALUE path1, VALUE path2)
{
    rb_encoding *enc = rb_enc_check(path1, path2);
    int encidx = rb_enc_to_index(enc);
    if (encidx == ENCINDEX_US_ASCII) {
        encidx = rb_enc_get_index(path1);
        if (encidx == ENCINDEX_US_ASCII)
            encidx = rb_enc_get_index(path2);
        enc = rb_enc_from_index(encidx);
    }
    return enc;
}

#if USE_NTFS
static char *
ntfs_tail(const char *path, const char *end, rb_encoding *enc)
{
    while (path < end && *path == '.') path++;
    while (path < end && !isADS(*path)) {
        if (istrailinggarbage(*path)) {
            const char *last = path++;
            while (path < end && istrailinggarbage(*path)) path++;
            if (path >= end || isADS(*path)) return (char *)last;
        }
        else if (isdirsep(*path)) {
            const char *last = path++;
            while (path < end && isdirsep(*path)) path++;
            if (path >= end) return (char *)last;
            if (isADS(*path)) path++;
        }
        else {
            Inc(path, end, enc);
        }
    }
    return (char *)path;
}
#endif /* USE_NTFS */

#define BUFCHECK(cond) do {\
    bdiff = p - buf;\
    if (cond) {\
        do {buflen *= 2;} while (cond);\
        rb_str_resize(result, buflen);\
        buf = RSTRING_PTR(result);\
        p = buf + bdiff;\
        pend = buf + buflen;\
    }\
} while (0)

#define BUFINIT() (\
    p = buf = RSTRING_PTR(result),\
    buflen = RSTRING_LEN(result),\
    pend = p + buflen)

#ifdef __APPLE__
# define SKIPPATHSEP(p) ((*(p)) ? 1 : 0)
#else
# define SKIPPATHSEP(p) 1
#endif

#define BUFCOPY(srcptr, srclen) do { \
    const int skip = SKIPPATHSEP(p); \
    rb_str_set_len(result, p-buf+skip); \
    BUFCHECK(bdiff + ((srclen)+skip) >= buflen); \
    p += skip; \
    memcpy(p, (srcptr), (srclen)); \
    p += (srclen); \
} while (0)

#define WITH_ROOTDIFF(stmt) do { \
    long rootdiff = root - buf; \
    stmt; \
    root = buf + rootdiff; \
} while (0)

static VALUE
copy_home_path(VALUE result, const char *dir)
{
    char *buf;
#if defined DOSISH || defined __CYGWIN__
    char *p, *bend;
    rb_encoding *enc;
#endif
    long dirlen;
    int encidx;

    dirlen = strlen(dir);
    rb_str_resize(result, dirlen);
    memcpy(buf = RSTRING_PTR(result), dir, dirlen);
    encidx = rb_filesystem_encindex();
    rb_enc_associate_index(result, encidx);
#if defined DOSISH || defined __CYGWIN__
    enc = rb_enc_from_index(encidx);
    for (bend = (p = buf) + dirlen; p < bend; Inc(p, bend, enc)) {
        if (*p == '\\') {
            *p = '/';
        }
    }
#endif
    return result;
}

#ifdef HAVE_PWD_H
static void *
nogvl_getpwnam(void *login)
{
    return (void *)getpwnam((const char *)login);
}
#endif

VALUE
rb_home_dir_of(VALUE user, VALUE result)
{
#ifdef HAVE_PWD_H
    struct passwd *pwPtr;
#else
    extern char *getlogin(void);
    const char *pwPtr = 0;
    # define endpwent() ((void)0)
#endif
    const char *dir, *username = RSTRING_PTR(user);
    rb_encoding *enc = rb_enc_get(user);
#if defined _WIN32
    rb_encoding *fsenc = rb_utf8_encoding();
#else
    rb_encoding *fsenc = rb_filesystem_encoding();
#endif
    if (enc != fsenc) {
        dir = username = RSTRING_PTR(rb_str_conv_enc(user, enc, fsenc));
    }

#ifdef HAVE_PWD_H
    pwPtr = (struct passwd *)IO_WITHOUT_GVL(nogvl_getpwnam, (void *)username);
#else
    if (strcasecmp(username, getlogin()) == 0)
        dir = pwPtr = getenv("HOME");
#endif
    if (!pwPtr) {
        endpwent();
        rb_raise(rb_eArgError, "user %"PRIsVALUE" doesn't exist", user);
    }
#ifdef HAVE_PWD_H
    dir = pwPtr->pw_dir;
#endif
    copy_home_path(result, dir);
    endpwent();
    return result;
}

#ifndef _WIN32 /* this encompasses rb_file_expand_path_internal */
VALUE
rb_default_home_dir(VALUE result)
{
    const char *dir = getenv("HOME");

#if defined HAVE_PWD_H
    if (!dir) {
        /* We'll look up the user's default home dir in the password db by
         * login name, if possible, and failing that will fall back to looking
         * the information up by uid (as would be needed for processes that
         * are not a descendant of login(1) or a work-alike).
         *
         * While the lookup by uid is more likely to succeed (since we always
         * have a uid, but may or may not have a login name), we prefer first
         * looking up by name to accommodate the possibility of multiple login
         * names (each with its own record in the password database, so each
         * with a potentially different home directory) being mapped to the
         * same uid (as explicitly allowed for by POSIX; see getlogin(3posix)).
         */
        VALUE login_name = rb_getlogin();

# if !defined(HAVE_GETPWUID_R) && !defined(HAVE_GETPWUID)
        /* This is a corner case, but for backward compatibility reasons we
         * want to emit this error if neither the lookup by login name nor
         * lookup by getuid() has a chance of succeeding.
         */
        if (NIL_P(login_name)) {
            rb_raise(rb_eArgError, "couldn't find login name -- expanding '~'");
        }
# endif /* !defined(HAVE_GETPWUID_R) && !defined(HAVE_GETPWUID) */

        VALUE pw_dir = rb_getpwdirnam_for_login(login_name);
        if (NIL_P(pw_dir)) {
            pw_dir = rb_getpwdiruid();
            if (NIL_P(pw_dir)) {
                rb_raise(rb_eArgError, "couldn't find home for uid '%ld'", (long)getuid());
            }
        }

        /* found it */
        copy_home_path(result, RSTRING_PTR(pw_dir));
        rb_str_resize(pw_dir, 0);
        return result;
    }
#endif /* defined HAVE_PWD_H */
    if (!dir) {
        rb_raise(rb_eArgError, "couldn't find HOME environment -- expanding '~'");
    }
    return copy_home_path(result, dir);
}

static VALUE
ospath_new(const char *ptr, long len, rb_encoding *fsenc)
{
#if NORMALIZE_UTF8PATH
    VALUE path = rb_str_normalize_ospath(ptr, len);
    rb_enc_associate(path, fsenc);
    return path;
#else
    return rb_enc_str_new(ptr, len, fsenc);
#endif
}

static char *
append_fspath(VALUE result, VALUE fname, char *dir, rb_encoding **enc, rb_encoding *fsenc)
{
    char *buf, *cwdp = dir;
    VALUE dirname = Qnil;
    size_t dirlen = strlen(dir), buflen = rb_str_capacity(result);

    if (NORMALIZE_UTF8PATH || *enc != fsenc) {
        dirname = ospath_new(dir, dirlen, fsenc);
        if (!rb_enc_compatible(fname, dirname)) {
            xfree(dir);
            /* rb_enc_check must raise because the two encodings are not
             * compatible. */
            rb_enc_check(fname, dirname);
            rb_bug("unreachable");
        }
        rb_encoding *direnc = fs_enc_check(fname, dirname);
        if (direnc != fsenc) {
            dirname = rb_str_conv_enc(dirname, fsenc, direnc);
            RSTRING_GETMEM(dirname, cwdp, dirlen);
        }
        else if (NORMALIZE_UTF8PATH) {
            RSTRING_GETMEM(dirname, cwdp, dirlen);
        }
        *enc = direnc;
    }
    do {buflen *= 2;} while (dirlen > buflen);
    rb_str_resize(result, buflen);
    buf = RSTRING_PTR(result);
    memcpy(buf, cwdp, dirlen);
    xfree(dir);
    if (!NIL_P(dirname)) rb_str_resize(dirname, 0);
    rb_enc_associate(result, *enc);
    return buf + dirlen;
}

VALUE
rb_file_expand_path_internal(VALUE fname, VALUE dname, int abs_mode, int long_name, VALUE result)
{
    const char *s, *b, *fend;
    char *buf, *p, *pend, *root;
    size_t buflen, bdiff;
    rb_encoding *enc, *fsenc = rb_filesystem_encoding();

    s = StringValuePtr(fname);
    fend = s + RSTRING_LEN(fname);
    enc = rb_enc_get(fname);
    BUFINIT();

    if (s[0] == '~' && abs_mode == 0) {      /* execute only if NOT absolute_path() */
        long userlen = 0;
        if (isdirsep(s[1]) || s[1] == '\0') {
            buf = 0;
            b = 0;
            rb_str_set_len(result, 0);
            if (*++s) ++s;
            rb_default_home_dir(result);
        }
        else {
            s = nextdirsep(b = s, fend, enc);
            b++; /* b[0] is '~' */
            userlen = s - b;
            BUFCHECK(bdiff + userlen >= buflen);
            memcpy(p, b, userlen);
            ENC_CODERANGE_CLEAR(result);
            rb_str_set_len(result, userlen);
            rb_enc_associate(result, enc);
            rb_home_dir_of(result, result);
            buf = p + 1;
            p += userlen;
        }
        if (!rb_is_absolute_path(RSTRING_PTR(result))) {
            if (userlen) {
                rb_enc_raise(enc, rb_eArgError, "non-absolute home of %.*s%.0"PRIsVALUE,
                             (int)userlen, b, fname);
            }
            else {
                rb_raise(rb_eArgError, "non-absolute home");
            }
        }
        BUFINIT();
        p = pend;
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
            rb_enc_copy(result, fname);
        }
        else {
            /* specified drive, but not full path */
            int same = 0;
            if (!NIL_P(dname) && !not_same_drive(dname, s[0])) {
                rb_file_expand_path_internal(dname, Qnil, abs_mode, long_name, result);
                BUFINIT();
                if (has_drive_letter(p) && TOLOWER(p[0]) == TOLOWER(s[0])) {
                    /* ok, same drive */
                    same = 1;
                }
            }
            if (!same) {
                char *e = append_fspath(result, fname, getcwdofdrv(*s), &enc, fsenc);
                BUFINIT();
                p = e;
            }
            else {
                rb_enc_associate(result, enc = fs_enc_check(result, fname));
                p = pend;
            }
            p = chompdirsep(skiproot(buf, p, enc), p, enc);
            s += 2;
        }
    }
#endif /* DOSISH_DRIVE_LETTER */
    else if (!rb_is_absolute_path(s)) {
        if (!NIL_P(dname)) {
            rb_file_expand_path_internal(dname, Qnil, abs_mode, long_name, result);
            rb_enc_associate(result, fs_enc_check(result, fname));
            BUFINIT();
            p = pend;
        }
        else {
            char *e = append_fspath(result, fname, ruby_getcwd(), &enc, fsenc);
            BUFINIT();
            p = e;
        }
#if defined DOSISH || defined __CYGWIN__
        if (isdirsep(*s)) {
            /* specified full path, but not drive letter nor UNC */
            /* we need to get the drive letter or UNC share name */
            p = skipprefix(buf, p, enc);
        }
        else
#endif /* defined DOSISH || defined __CYGWIN__ */
            p = chompdirsep(skiproot(buf, p, enc), p, enc);
    }
    else {
        size_t len;
        b = s;
        do s++; while (isdirsep(*s));
        len = s - b;
        p = buf + len;
        BUFCHECK(bdiff >= buflen);
        memset(buf, '/', len);
        rb_str_set_len(result, len);
        rb_enc_associate(result, fs_enc_check(result, fname));
    }
    if (p > buf && p[-1] == '/')
        --p;
    else {
        rb_str_set_len(result, p-buf);
        BUFCHECK(bdiff + 1 >= buflen);
        *p = '/';
    }

    rb_str_set_len(result, p-buf+1);
    BUFCHECK(bdiff + 1 >= buflen);
    p[1] = 0;
    root = skipprefix(buf, p+1, enc);

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
                        if (!(n = strrdirsep(root, p, enc))) {
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
#endif /* USE_NTFS */
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
                while (s < fend && istrailinggarbage(*s)) s++;
                if (s >= fend) {
                    s = e;
                    goto endpath;
                }
              }
            }
#endif /* USE_NTFS */
            break;
          case '/':
#if defined DOSISH || defined __CYGWIN__
          case '\\':
#endif
            if (s > b) {
                WITH_ROOTDIFF(BUFCOPY(b, s-b));
                *p = '/';
            }
            b = ++s;
            break;
          default:
#ifdef __APPLE__
            {
                int n = ignored_char_p(s, fend, enc);
                if (n) {
                    if (s > b) {
                        WITH_ROOTDIFF(BUFCOPY(b, s-b));
                        *p = '\0';
                    }
                    b = s += n;
                    break;
                }
            }
#endif /* __APPLE__ */
            Inc(s, fend, enc);
            break;
        }
    }

    if (s > b) {
#if USE_NTFS
# if USE_NTFS_ADS
        static const char prime[] = ":$DATA";
        enum {prime_len = sizeof(prime) -1};
# endif
      endpath:
# if USE_NTFS_ADS
        if (s > b + prime_len && strncasecmp(s - prime_len, prime, prime_len) == 0) {
            /* alias of stream */
            /* get rid of a bug of x64 VC++ */
            if (isADS(*(s - (prime_len+1)))) {
                s -= prime_len + 1; /* prime */
            }
            else if (memchr(b, ':', s - prime_len - b)) {
                s -= prime_len;	/* alternative */
            }
        }
# endif /* USE_NTFS_ADS */
#endif /* USE_NTFS */
        BUFCOPY(b, s-b);
        rb_str_set_len(result, p-buf);
    }
    if (p == skiproot(buf, p + !!*p, enc) - 1) p++;

#if USE_NTFS
    *p = '\0';
    if ((s = strrdirsep(b = buf, p, enc)) != 0 && !strpbrk(s, "*?")) {
        VALUE tmp, v;
        size_t len;
        int encidx;
        WCHAR *wstr;
        WIN32_FIND_DATAW wfd;
        HANDLE h;
#ifdef __CYGWIN__
#ifdef HAVE_CYGWIN_CONV_PATH
        char *w32buf = NULL;
        const int flags = CCP_POSIX_TO_WIN_A | CCP_RELATIVE;
#else
        char w32buf[MAXPATHLEN];
#endif /* HAVE_CYGWIN_CONV_PATH */
        const char *path;
        ssize_t bufsize;
        int lnk_added = 0, is_symlink = 0;
        struct stat st;
        p = (char *)s;
        len = strlen(p);
        if (lstat_without_gvl(buf, &st) == 0 && S_ISLNK(st.st_mode)) {
            is_symlink = 1;
            if (len > 4 && STRCASECMP(p + len - 4, ".lnk") != 0) {
                lnk_added = 1;
            }
        }
        path = *buf ? buf : "/";
#ifdef HAVE_CYGWIN_CONV_PATH
        bufsize = cygwin_conv_path(flags, path, NULL, 0);
        if (bufsize > 0) {
            bufsize += len;
            if (lnk_added) bufsize += 4;
            w32buf = ALLOCA_N(char, bufsize);
            if (cygwin_conv_path(flags, path, w32buf, bufsize) == 0) {
                b = w32buf;
            }
        }
#else /* !HAVE_CYGWIN_CONV_PATH */
        bufsize = MAXPATHLEN;
        if (cygwin_conv_to_win32_path(path, w32buf) == 0) {
            b = w32buf;
        }
#endif /* !HAVE_CYGWIN_CONV_PATH */
        if (is_symlink && b == w32buf) {
            *p = '\\';
            strlcat(w32buf, p, bufsize);
            if (lnk_added) {
                strlcat(w32buf, ".lnk", bufsize);
            }
        }
        else {
            lnk_added = 0;
        }
        *p = '/';
#endif /* __CYGWIN__ */
        rb_str_set_len(result, p - buf + strlen(p));
        encidx = ENCODING_GET(result);
        tmp = result;
        if (encidx != ENCINDEX_UTF_8 && !is_ascii_string(result)) {
            tmp = rb_str_encode_ospath(result);
        }
        len = MultiByteToWideChar(CP_UTF8, 0, RSTRING_PTR(tmp), -1, NULL, 0);
        wstr = ALLOCV_N(WCHAR, v, len);
        MultiByteToWideChar(CP_UTF8, 0, RSTRING_PTR(tmp), -1, wstr, len);
        if (tmp != result) rb_str_set_len(tmp, 0);
        h = FindFirstFileW(wstr, &wfd);
        ALLOCV_END(v);
        if (h != INVALID_HANDLE_VALUE) {
            size_t wlen;
            FindClose(h);
            len = lstrlenW(wfd.cFileName);
#ifdef __CYGWIN__
            if (lnk_added && len > 4 &&
                wcscasecmp(wfd.cFileName + len - 4, L".lnk") == 0) {
                wfd.cFileName[len -= 4] = L'\0';
            }
#else
            p = (char *)s;
#endif
            ++p;
            wlen = (int)len;
            len = WideCharToMultiByte(CP_UTF8, 0, wfd.cFileName, wlen, NULL, 0, NULL, NULL);
            if (tmp == result) {
                BUFCHECK(bdiff + len >= buflen);
                WideCharToMultiByte(CP_UTF8, 0, wfd.cFileName, wlen, p, len + 1, NULL, NULL);
            }
            else {
                rb_str_modify_expand(tmp, len);
                WideCharToMultiByte(CP_UTF8, 0, wfd.cFileName, wlen, RSTRING_PTR(tmp), len + 1, NULL, NULL);
                rb_str_cat_conv_enc_opts(result, bdiff, RSTRING_PTR(tmp), len,
                                         rb_utf8_encoding(), 0, Qnil);
                BUFINIT();
                rb_str_resize(tmp, 0);
            }
            p += len;
        }
#ifdef __CYGWIN__
        else {
            p += strlen(p);
        }
#endif
    }
#endif /* USE_NTFS */

    rb_str_set_len(result, p - buf);
    rb_enc_check(fname, result);
    ENC_CODERANGE_CLEAR(result);
    return result;
}
#endif /* !_WIN32 (this ifdef started above rb_default_home_dir) */

#define EXPAND_PATH_BUFFER() rb_usascii_str_new(0, 1)

static VALUE
str_shrink(VALUE str)
{
    rb_str_resize(str, RSTRING_LEN(str));
    return str;
}

#define expand_path(fname, dname, abs_mode, long_name, result) \
    str_shrink(rb_file_expand_path_internal(fname, dname, abs_mode, long_name, result))

#define check_expand_path_args(fname, dname) \
    (((fname) = rb_get_path(fname)), \
     (void)(NIL_P(dname) ? (dname) : ((dname) = rb_get_path(dname))))

static VALUE
file_expand_path_1(VALUE fname)
{
    return rb_file_expand_path_internal(fname, Qnil, 0, 0, EXPAND_PATH_BUFFER());
}

VALUE
rb_file_expand_path(VALUE fname, VALUE dname)
{
    check_expand_path_args(fname, dname);
    return expand_path(fname, dname, 0, 1, EXPAND_PATH_BUFFER());
}

VALUE
rb_file_expand_path_fast(VALUE fname, VALUE dname)
{
    return expand_path(fname, dname, 0, 0, EXPAND_PATH_BUFFER());
}

VALUE
rb_file_s_expand_path(int argc, const VALUE *argv)
{
    rb_check_arity(argc, 1, 2);
    return rb_file_expand_path(argv[0], argc > 1 ? argv[1] : Qnil);
}

/*
 *  call-seq:
 *     File.expand_path(file_name [, dir_string] )  ->  abs_file_name
 *
 *  Converts a pathname to an absolute pathname. Relative paths are
 *  referenced from the current working directory of the process unless
 *  +dir_string+ is given, in which case it will be used as the
 *  starting point. The given pathname may start with a
 *  ``<code>~</code>'', which expands to the process owner's home
 *  directory (the environment variable +HOME+ must be set
 *  correctly). ``<code>~</code><i>user</i>'' expands to the named
 *  user's home directory.
 *
 *     File.expand_path("~oracle/bin")           #=> "/home/oracle/bin"
 *
 *  A simple example of using +dir_string+ is as follows.
 *     File.expand_path("ruby", "/usr/bin")      #=> "/usr/bin/ruby"
 *
 *  A more complex example which also resolves parent directory is as follows.
 *  Suppose we are in bin/mygem and want the absolute path of lib/mygem.rb.
 *
 *     File.expand_path("../../lib/mygem.rb", __FILE__)
 *     #=> ".../path/to/project/lib/mygem.rb"
 *
 *  So first it resolves the parent of __FILE__, that is bin/, then go to the
 *  parent, the root of the project and appends +lib/mygem.rb+.
 */

static VALUE
s_expand_path(int c, const VALUE * v, VALUE _)
{
    return rb_file_s_expand_path(c, v);
}

VALUE
rb_file_absolute_path(VALUE fname, VALUE dname)
{
    check_expand_path_args(fname, dname);
    return expand_path(fname, dname, 1, 1, EXPAND_PATH_BUFFER());
}

VALUE
rb_file_s_absolute_path(int argc, const VALUE *argv)
{
    rb_check_arity(argc, 1, 2);
    return rb_file_absolute_path(argv[0], argc > 1 ? argv[1] : Qnil);
}

/*
 *  call-seq:
 *     File.absolute_path(file_name [, dir_string] )  ->  abs_file_name
 *
 *  Converts a pathname to an absolute pathname. Relative paths are
 *  referenced from the current working directory of the process unless
 *  <i>dir_string</i> is given, in which case it will be used as the
 *  starting point. If the given pathname starts with a ``<code>~</code>''
 *  it is NOT expanded, it is treated as a normal directory name.
 *
 *     File.absolute_path("~oracle/bin")       #=> "<relative_path>/~oracle/bin"
 */

static VALUE
s_absolute_path(int c, const VALUE * v, VALUE _)
{
    return rb_file_s_absolute_path(c, v);
}

/*
 *  call-seq:
 *     File.absolute_path?(file_name)  ->  true or false
 *
 *  Returns <code>true</code> if +file_name+ is an absolute path, and
 *  <code>false</code> otherwise.
 *
 *     File.absolute_path?("c:/foo")     #=> false (on Linux), true (on Windows)
 */

static VALUE
s_absolute_path_p(VALUE klass, VALUE fname)
{
    VALUE path = rb_get_path(fname);

    if (!rb_is_absolute_path(RSTRING_PTR(path))) return Qfalse;
    return Qtrue;
}

enum rb_realpath_mode {
    RB_REALPATH_CHECK,
    RB_REALPATH_DIR,
    RB_REALPATH_STRICT,
    RB_REALPATH_MODE_MAX
};

static int
realpath_rec(long *prefixlenp, VALUE *resolvedp, const char *unresolved, VALUE fallback,
             VALUE loopcheck, enum rb_realpath_mode mode, int last)
{
    const char *pend = unresolved + strlen(unresolved);
    rb_encoding *enc = rb_enc_get(*resolvedp);
    ID resolving;
    CONST_ID(resolving, "resolving");
    while (unresolved < pend) {
        const char *testname = unresolved;
        const char *unresolved_firstsep = rb_enc_path_next(unresolved, pend, enc);
        long testnamelen = unresolved_firstsep - unresolved;
        const char *unresolved_nextname = unresolved_firstsep;
        while (unresolved_nextname < pend && isdirsep(*unresolved_nextname))
            unresolved_nextname++;
        unresolved = unresolved_nextname;
        if (testnamelen == 1 && testname[0] == '.') {
        }
        else if (testnamelen == 2 && testname[0] == '.' && testname[1] == '.') {
            if (*prefixlenp < RSTRING_LEN(*resolvedp)) {
                const char *resolved_str = RSTRING_PTR(*resolvedp);
                const char *resolved_names = resolved_str + *prefixlenp;
                const char *lastsep = strrdirsep(resolved_names, resolved_str + RSTRING_LEN(*resolvedp), enc);
                long len = lastsep ? lastsep - resolved_names : 0;
                rb_str_resize(*resolvedp, *prefixlenp + len);
            }
        }
        else {
            VALUE checkval;
            VALUE testpath = rb_str_dup(*resolvedp);
            if (*prefixlenp < RSTRING_LEN(testpath))
                rb_str_cat2(testpath, "/");
#if defined(DOSISH_UNC) || defined(DOSISH_DRIVE_LETTER)
            if (*prefixlenp > 1 && *prefixlenp == RSTRING_LEN(testpath)) {
                const char *prefix = RSTRING_PTR(testpath);
                const char *last = rb_enc_left_char_head(prefix, prefix + *prefixlenp - 1, prefix + *prefixlenp, enc);
                if (!isdirsep(*last)) rb_str_cat2(testpath, "/");
            }
#endif
            rb_str_cat(testpath, testname, testnamelen);
            checkval = rb_hash_aref(loopcheck, testpath);
            if (!NIL_P(checkval)) {
                if (checkval == ID2SYM(resolving)) {
                    if (mode == RB_REALPATH_CHECK) {
                        errno = ELOOP;
                        return -1;
                    }
                    rb_syserr_fail_path(ELOOP, testpath);
                }
                else {
                    *resolvedp = rb_str_dup(checkval);
                }
            }
            else {
                struct stat sbuf;
                int ret;
                ret = lstat_without_gvl(RSTRING_PTR(testpath), &sbuf);
                if (ret == -1) {
                    int e = errno;
                    if (e == ENOENT && !NIL_P(fallback)) {
                        if (stat_without_gvl(RSTRING_PTR(fallback), &sbuf) == 0) {
                            rb_str_replace(*resolvedp, fallback);
                            return 0;
                        }
                    }
                    if (mode == RB_REALPATH_CHECK) return -1;
                    if (e == ENOENT) {
                        if (mode == RB_REALPATH_STRICT || !last || *unresolved_firstsep)
                            rb_syserr_fail_path(e, testpath);
                        *resolvedp = testpath;
                        break;
                    }
                    else {
                        rb_syserr_fail_path(e, testpath);
                    }
                }
#ifdef HAVE_READLINK
                if (S_ISLNK(sbuf.st_mode)) {
                    VALUE link;
                    VALUE link_orig = Qnil;
                    const char *link_prefix, *link_names;
                    long link_prefixlen;
                    rb_hash_aset(loopcheck, testpath, ID2SYM(resolving));
                    link = rb_readlink(testpath, enc);
                    link_prefix = RSTRING_PTR(link);
                    link_names = skipprefixroot(link_prefix, link_prefix + RSTRING_LEN(link), rb_enc_get(link));
                    link_prefixlen = link_names - link_prefix;
                    if (link_prefixlen > 0) {
                        rb_encoding *tmpenc, *linkenc = rb_enc_get(link);
                        link_orig = link;
                        link = rb_str_subseq(link, 0, link_prefixlen);
                        tmpenc = fs_enc_check(*resolvedp, link);
                        if (tmpenc != linkenc) link = rb_str_conv_enc(link, linkenc, tmpenc);
                        *resolvedp = link;
                        *prefixlenp = link_prefixlen;
                    }
                    if (realpath_rec(prefixlenp, resolvedp, link_names, testpath,
                                     loopcheck, mode, !*unresolved_firstsep))
                        return -1;
                    RB_GC_GUARD(link_orig);
                    rb_hash_aset(loopcheck, testpath, rb_str_dup_frozen(*resolvedp));
                }
                else
#endif /* HAVE_READLINK */
                {
                    VALUE s = rb_str_dup_frozen(testpath);
                    rb_hash_aset(loopcheck, s, s);
                    *resolvedp = testpath;
                }
            }
        }
    }
    return 0;
}

static VALUE
rb_check_realpath_emulate(VALUE basedir, VALUE path, rb_encoding *origenc, enum rb_realpath_mode mode)
{
    long prefixlen;
    VALUE resolved;
    VALUE unresolved_path;
    VALUE loopcheck;
    VALUE curdir = Qnil;

    rb_encoding *enc;
    char *path_names = NULL, *basedir_names = NULL, *curdir_names = NULL;
    char *ptr, *prefixptr = NULL, *pend;
    long len;

    unresolved_path = rb_str_dup_frozen(path);

    if (!NIL_P(basedir)) {
        FilePathValue(basedir);
        basedir = TO_OSPATH(rb_str_dup_frozen(basedir));
    }

    enc = rb_enc_get(unresolved_path);
    unresolved_path = TO_OSPATH(unresolved_path);
    RSTRING_GETMEM(unresolved_path, ptr, len);
    path_names = skipprefixroot(ptr, ptr + len, rb_enc_get(unresolved_path));
    if (ptr != path_names) {
        resolved = rb_str_subseq(unresolved_path, 0, path_names - ptr);
        goto root_found;
    }

    if (!NIL_P(basedir)) {
        RSTRING_GETMEM(basedir, ptr, len);
        basedir_names = skipprefixroot(ptr, ptr + len, rb_enc_get(basedir));
        if (ptr != basedir_names) {
            resolved = rb_str_subseq(basedir, 0, basedir_names - ptr);
            goto root_found;
        }
    }

    curdir = rb_dir_getwd_ospath();
    RSTRING_GETMEM(curdir, ptr, len);
    curdir_names = skipprefixroot(ptr, ptr + len, rb_enc_get(curdir));
    resolved = rb_str_subseq(curdir, 0, curdir_names - ptr);

  root_found:
    RSTRING_GETMEM(resolved, prefixptr, prefixlen);
    pend = prefixptr + prefixlen;
    ptr = chompdirsep(prefixptr, pend, enc);
    if (ptr < pend) {
        prefixlen = ++ptr - prefixptr;
        rb_str_set_len(resolved, prefixlen);
    }
#ifdef FILE_ALT_SEPARATOR
    while (prefixptr < ptr) {
        if (*prefixptr == FILE_ALT_SEPARATOR) {
            *prefixptr = '/';
        }
        Inc(prefixptr, pend, enc);
    }
#endif

    switch (rb_enc_to_index(enc)) {
      case ENCINDEX_ASCII_8BIT:
      case ENCINDEX_US_ASCII:
        rb_enc_associate_index(resolved, rb_filesystem_encindex());
    }

    loopcheck = rb_hash_new();
    if (curdir_names) {
        if (realpath_rec(&prefixlen, &resolved, curdir_names, Qnil, loopcheck, mode, 0))
            return Qnil;
    }
    if (basedir_names) {
        if (realpath_rec(&prefixlen, &resolved, basedir_names, Qnil, loopcheck, mode, 0))
            return Qnil;
    }
    if (realpath_rec(&prefixlen, &resolved, path_names, Qnil, loopcheck, mode, 1))
        return Qnil;

    if (origenc && origenc != rb_enc_get(resolved)) {
        if (rb_enc_str_asciionly_p(resolved)) {
            rb_enc_associate(resolved, origenc);
        }
        else {
            resolved = rb_str_conv_enc(resolved, NULL, origenc);
        }
    }

    RB_GC_GUARD(unresolved_path);
    RB_GC_GUARD(curdir);
    return resolved;
}

static VALUE rb_file_join(VALUE ary);

#ifndef HAVE_REALPATH
static VALUE
rb_check_realpath_emulate_try(VALUE arg)
{
    VALUE *args = (VALUE *)arg;
    return rb_check_realpath_emulate(args[0], args[1], (rb_encoding *)args[2], RB_REALPATH_CHECK);
}

static VALUE
rb_check_realpath_emulate_rescue(VALUE arg, VALUE exc)
{
    return Qnil;
}
#endif /* HAVE_REALPATH */

static VALUE
rb_check_realpath_internal(VALUE basedir, VALUE path, rb_encoding *origenc, enum rb_realpath_mode mode)
{
#ifdef HAVE_REALPATH
    VALUE unresolved_path;
    char *resolved_ptr = NULL;
    VALUE resolved;

    if (mode == RB_REALPATH_DIR) {
        return rb_check_realpath_emulate(basedir, path, origenc, mode);
    }

    unresolved_path = rb_str_dup_frozen(path);
    if (*RSTRING_PTR(unresolved_path) != '/' && !NIL_P(basedir)) {
        unresolved_path = rb_file_join(rb_assoc_new(basedir, unresolved_path));
    }
    if (origenc) unresolved_path = TO_OSPATH(unresolved_path);

    if ((resolved_ptr = realpath(RSTRING_PTR(unresolved_path), NULL)) == NULL) {
        /* glibc realpath(3) does not allow /path/to/file.rb/../other_file.rb,
           returning ENOTDIR in that case.
           glibc realpath(3) can also return ENOENT for paths that exist,
           such as /dev/fd/5.
           Fallback to the emulated approach in either of those cases. */
        if (errno == ENOTDIR ||
            (errno == ENOENT && rb_file_exist_p(0, unresolved_path))) {
            return rb_check_realpath_emulate(basedir, path, origenc, mode);

        }
        if (mode == RB_REALPATH_CHECK) {
            return Qnil;
        }
        rb_sys_fail_path(unresolved_path);
    }
    resolved = ospath_new(resolved_ptr, strlen(resolved_ptr), rb_filesystem_encoding());
    free(resolved_ptr);

# if !defined(__LINUX__) && !defined(__APPLE__)
    /* As `resolved` is a String in the filesystem encoding, no
     * conversion is needed */
    struct stat st;
    if (stat_without_gvl(RSTRING_PTR(resolved), &st) < 0) {
        if (mode == RB_REALPATH_CHECK) {
            return Qnil;
        }
        rb_sys_fail_path(unresolved_path);
    }
# endif /* !defined(__LINUX__) && !defined(__APPLE__) */

    if (origenc && origenc != rb_enc_get(resolved)) {
        if (!rb_enc_str_asciionly_p(resolved)) {
            resolved = rb_str_conv_enc(resolved, NULL, origenc);
        }
        rb_enc_associate(resolved, origenc);
    }

    if (is_broken_string(resolved)) {
        rb_enc_associate(resolved, rb_filesystem_encoding());
        if (is_broken_string(resolved)) {
            rb_enc_associate(resolved, rb_ascii8bit_encoding());
        }
    }

    RB_GC_GUARD(unresolved_path);
    return resolved;
#else /* !HAVE_REALPATH */
    if (mode == RB_REALPATH_CHECK) {
        VALUE arg[3];
        arg[0] = basedir;
        arg[1] = path;
        arg[2] = (VALUE)origenc;

        return rb_rescue(rb_check_realpath_emulate_try, (VALUE)arg,
                         rb_check_realpath_emulate_rescue, Qnil);
    }
    else {
        return rb_check_realpath_emulate(basedir, path, origenc, mode);
    }
#endif /* HAVE_REALPATH */
}

VALUE
rb_realpath_internal(VALUE basedir, VALUE path, int strict)
{
    const enum rb_realpath_mode mode =
        strict ? RB_REALPATH_STRICT : RB_REALPATH_DIR;
    return rb_check_realpath_internal(basedir, path, rb_enc_get(path), mode);
}

VALUE
rb_check_realpath(VALUE basedir, VALUE path, rb_encoding *enc)
{
    return rb_check_realpath_internal(basedir, path, enc, RB_REALPATH_CHECK);
}

/*
 * call-seq:
 *     File.realpath(pathname [, dir_string])  ->  real_pathname
 *
 *  Returns the real (absolute) pathname of _pathname_ in the actual
 *  filesystem not containing symlinks or useless dots.
 *
 *  If _dir_string_ is given, it is used as a base directory
 *  for interpreting relative pathname instead of the current directory.
 *
 *  All components of the pathname must exist when this method is
 *  called.
 */
static VALUE
rb_file_s_realpath(int argc, VALUE *argv, VALUE klass)
{
    VALUE basedir = (rb_check_arity(argc, 1, 2) > 1) ? argv[1] : Qnil;
    VALUE path = argv[0];
    FilePathValue(path);
    return rb_realpath_internal(basedir, path, 1);
}

/*
 * call-seq:
 *     File.realdirpath(pathname [, dir_string])  ->  real_pathname
 *
 *  Returns the real (absolute) pathname of _pathname_ in the actual filesystem.
 *  The real pathname doesn't contain symlinks or useless dots.
 *
 *  If _dir_string_ is given, it is used as a base directory
 *  for interpreting relative pathname instead of the current directory.
 *
 *  The last component of the real pathname can be nonexistent.
 */
static VALUE
rb_file_s_realdirpath(int argc, VALUE *argv, VALUE klass)
{
    VALUE basedir = (rb_check_arity(argc, 1, 2) > 1) ? argv[1] : Qnil;
    VALUE path = argv[0];
    FilePathValue(path);
    return rb_realpath_internal(basedir, path, 0);
}

static size_t
rmext(const char *p, long l0, long l1, const char *e, long l2, rb_encoding *enc)
{
    int len1, len2;
    unsigned int c;
    const char *s, *last;

    if (!e || !l2) return 0;

    c = rb_enc_codepoint_len(e, e + l2, &len1, enc);
    if (rb_enc_ascget(e + len1, e + l2, &len2, enc) == '*' && len1 + len2 == l2) {
        if (c == '.') return l0;
        s = p;
        e = p + l1;
        last = e;
        while (s < e) {
            if (rb_enc_codepoint_len(s, e, &len1, enc) == c) last = s;
            s += len1;
        }
        return last - p;
    }
    if (l1 < l2) return l1;

    s = p+l1-l2;
    if (!at_char_boundary(p, s, p+l1, enc)) return 0;
#if CASEFOLD_FILESYSTEM
#define fncomp strncasecmp
#else
#define fncomp strncmp
#endif
    if (fncomp(s, e, l2) == 0) {
        return l1-l2;
    }
    return 0;
}

const char *
ruby_enc_find_basename(const char *name, long *baselen, long *alllen, rb_encoding *enc)
{
    const char *p, *q, *e, *end;
#if defined DOSISH_DRIVE_LETTER || defined DOSISH_UNC
    const char *root;
#endif
    long f = 0, n = -1;

    end = name + (alllen ? (size_t)*alllen : strlen(name));
    name = skipprefix(name, end, enc);
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
#endif /* DOSISH_DRIVE_LETTER */
#ifdef DOSISH_UNC
        else {
            p = "/";
        }
#endif /* DOSISH_UNC */
#endif /* defined DOSISH_DRIVE_LETTER || defined DOSISH_UNC */
    }
    else {
        if (!(p = strrdirsep(name, end, enc))) {
            p = name;
        }
        else {
            while (isdirsep(*p)) p++; /* skip last / */
        }
#if USE_NTFS
        n = ntfs_tail(p, end, enc) - p;
#else
        n = chompdirsep(p, end, enc) - p;
#endif
        for (q = p; q - p < n && *q == '.'; q++);
        for (e = 0; q - p < n; Inc(q, end, enc)) {
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
 *     File.basename(file_name [, suffix] )  ->  base_name
 *
 *  Returns the last component of the filename given in
 *  <i>file_name</i> (after first stripping trailing separators),
 *  which can be formed using both File::SEPARATOR and
 *  File::ALT_SEPARATOR as the separator when File::ALT_SEPARATOR is
 *  not <code>nil</code>. If <i>suffix</i> is given and present at the
 *  end of <i>file_name</i>, it is removed. If <i>suffix</i> is ".*",
 *  any extension will be removed.
 *
 *     File.basename("/home/gumby/work/ruby.rb")          #=> "ruby.rb"
 *     File.basename("/home/gumby/work/ruby.rb", ".rb")   #=> "ruby"
 *     File.basename("/home/gumby/work/ruby.rb", ".*")    #=> "ruby"
 */

static VALUE
rb_file_s_basename(int argc, VALUE *argv, VALUE _)
{
    VALUE fname, fext, basename;
    const char *name, *p;
    long f, n;
    rb_encoding *enc;

    fext = Qnil;
    if (rb_check_arity(argc, 1, 2) == 2) {
        fext = argv[1];
        StringValue(fext);
        enc = check_path_encoding(fext);
    }
    fname = argv[0];
    FilePathStringValue(fname);
    if (NIL_P(fext) || !(enc = rb_enc_compatible(fname, fext))) {
        enc = rb_enc_get(fname);
        fext = Qnil;
    }
    if ((n = RSTRING_LEN(fname)) == 0 || !*(name = RSTRING_PTR(fname)))
        return rb_str_new_shared(fname);

    p = ruby_enc_find_basename(name, &f, &n, enc);
    if (n >= 0) {
        if (NIL_P(fext)) {
            f = n;
        }
        else {
            const char *fp;
            fp = StringValueCStr(fext);
            if (!(f = rmext(p, f, n, fp, RSTRING_LEN(fext), enc))) {
                f = n;
            }
            RB_GC_GUARD(fext);
        }
        if (f == RSTRING_LEN(fname)) return rb_str_new_shared(fname);
    }

    basename = rb_str_new(p, f);
    rb_enc_copy(basename, fname);
    return basename;
}

static VALUE rb_file_dirname_n(VALUE fname, int n);

/*
 *  call-seq:
 *     File.dirname(file_name, level = 1)  ->  dir_name
 *
 *  Returns all components of the filename given in <i>file_name</i>
 *  except the last one (after first stripping trailing separators).
 *  The filename can be formed using both File::SEPARATOR and
 *  File::ALT_SEPARATOR as the separator when File::ALT_SEPARATOR is
 *  not <code>nil</code>.
 *
 *     File.dirname("/home/gumby/work/ruby.rb")   #=> "/home/gumby/work"
 *
 *  If +level+ is given, removes the last +level+ components, not only
 *  one.
 *
 *     File.dirname("/home/gumby/work/ruby.rb", 2) #=> "/home/gumby"
 *     File.dirname("/home/gumby/work/ruby.rb", 4) #=> "/"
 */

static VALUE
rb_file_s_dirname(int argc, VALUE *argv, VALUE klass)
{
    int n = 1;
    if ((argc = rb_check_arity(argc, 1, 2)) > 1) {
        n = NUM2INT(argv[1]);
    }
    return rb_file_dirname_n(argv[0], n);
}

VALUE
rb_file_dirname(VALUE fname)
{
    return rb_file_dirname_n(fname, 1);
}

static VALUE
rb_file_dirname_n(VALUE fname, int n)
{
    const char *name, *root, *p, *end;
    VALUE dirname;
    rb_encoding *enc;
    VALUE sepsv = 0;
    const char **seps;

    if (n < 0) rb_raise(rb_eArgError, "negative level: %d", n);
    FilePathStringValue(fname);
    name = StringValueCStr(fname);
    end = name + RSTRING_LEN(fname);
    enc = rb_enc_get(fname);
    root = skiproot(name, end, enc);
#ifdef DOSISH_UNC
    if (root > name + 1 && isdirsep(*name))
        root = skipprefix(name = root - 2, end, enc);
#else
    if (root > name + 1)
        name = root - 1;
#endif
    if (n > (end - root + 1) / 2) {
        p = root;
    }
    else {
        int i;
        switch (n) {
          case 0:
            p = end;
            break;
          case 1:
            if (!(p = strrdirsep(root, end, enc))) p = root;
            break;
          default:
            seps = ALLOCV_N(const char *, sepsv, n);
            for (i = 0; i < n; ++i) seps[i] = root;
            i = 0;
            for (p = root; p < end; ) {
                if (isdirsep(*p)) {
                    const char *tmp = p++;
                    while (p < end && isdirsep(*p)) p++;
                    if (p >= end) break;
                    seps[i++] = tmp;
                    if (i == n) i = 0;
                }
                else {
                    Inc(p, end, enc);
                }
            }
            p = seps[i];
            ALLOCV_END(sepsv);
            break;
        }
    }
    if (p == name)
        return rb_usascii_str_new2(".");
#ifdef DOSISH_DRIVE_LETTER
    if (has_drive_letter(name) && isdirsep(*(name + 2))) {
        const char *top = skiproot(name + 2, end, enc);
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
    rb_enc_copy(dirname, fname);
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
 *   .ext:stream   dot       len of .ext without :stream (NTFS only)
 *
 */
const char *
ruby_enc_find_extname(const char *name, long *len, rb_encoding *enc)
{
    const char *p, *e, *end = name + (len ? *len : (long)strlen(name));

    p = strrdirsep(name, end, enc);	/* get the last path component */
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
            if (!*p || isADS(*p)) {
                p = last;
                break;
            }
            if (*last == '.' || dot > last) e = dot;
            continue;
#else
            e = p;	  /* get the last dot of the last component */
#endif /* USE_NTFS */
        }
#if USE_NTFS
        else if (isADS(*p)) {
            break;
        }
#endif
        else if (isdirsep(*p))
            break;
        Inc(p, end, enc);
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
 *     File.extname(path)  ->  string
 *
 *  Returns the extension (the portion of file name in +path+
 *  starting from the last period).
 *
 *  If +path+ is a dotfile, or starts with a period, then the starting
 *  dot is not dealt with the start of the extension.
 *
 *  An empty string will also be returned when the period is the last character
 *  in +path+.
 *
 *  On Windows, trailing dots are truncated.
 *
 *     File.extname("test.rb")         #=> ".rb"
 *     File.extname("a/b/d/test.rb")   #=> ".rb"
 *     File.extname(".a/b/d/test.rb")  #=> ".rb"
 *     File.extname("foo.")            #=> "" on Windows
 *     File.extname("foo.")            #=> "." on non-Windows
 *     File.extname("test")            #=> ""
 *     File.extname(".profile")        #=> ""
 *     File.extname(".profile.sh")     #=> ".sh"
 *
 */

static VALUE
rb_file_s_extname(VALUE klass, VALUE fname)
{
    const char *name, *e;
    long len;
    VALUE extname;

    FilePathStringValue(fname);
    name = StringValueCStr(fname);
    len = RSTRING_LEN(fname);
    e = ruby_enc_find_extname(name, &len, rb_enc_get(fname));
    if (len < 1)
        return rb_str_new(0, 0);
    extname = rb_str_subseq(fname, e - name, len); /* keep the dot, too! */
    return extname;
}

/*
 *  call-seq:
 *     File.path(path)  ->  string
 *
 *  Returns the string representation of the path
 *
 *     File.path(File::NULL)           #=> "/dev/null"
 *     File.path(Pathname.new("/tmp")) #=> "/tmp"
 *
 */

static VALUE
rb_file_s_path(VALUE klass, VALUE fname)
{
    return rb_get_path(fname);
}

/*
 *  call-seq:
 *     File.split(file_name)   -> array
 *
 *  Splits the given string into a directory and a file component and
 *  returns them in a two-element array. See also File::dirname and
 *  File::basename.
 *
 *     File.split("/home/gumby/.profile")   #=> ["/home/gumby", ".profile"]
 */

static VALUE
rb_file_s_split(VALUE klass, VALUE path)
{
    FilePathStringValue(path);		/* get rid of converting twice */
    return rb_assoc_new(rb_file_dirname(path), rb_file_s_basename(1,&path,Qundef));
}

static VALUE
file_inspect_join(VALUE ary, VALUE arg, int recur)
{
    if (recur || ary == arg) rb_raise(rb_eArgError, "recursive array");
    return rb_file_join(arg);
}

static VALUE
rb_file_join(VALUE ary)
{
    long len, i;
    VALUE result, tmp;
    const char *name, *tail;
    int checked = TRUE;
    rb_encoding *enc;

    if (RARRAY_LEN(ary) == 0) return rb_str_new(0, 0);

    len = 1;
    for (i=0; i<RARRAY_LEN(ary); i++) {
        tmp = RARRAY_AREF(ary, i);
        if (RB_TYPE_P(tmp, T_STRING)) {
            check_path_encoding(tmp);
            len += RSTRING_LEN(tmp);
        }
        else {
            len += 10;
        }
    }
    len += RARRAY_LEN(ary) - 1;
    result = rb_str_buf_new(len);
    RBASIC_CLEAR_CLASS(result);
    for (i=0; i<RARRAY_LEN(ary); i++) {
        tmp = RARRAY_AREF(ary, i);
        switch (OBJ_BUILTIN_TYPE(tmp)) {
          case T_STRING:
            if (!checked) check_path_encoding(tmp);
            StringValueCStr(tmp);
            break;
          case T_ARRAY:
            if (ary == tmp) {
                rb_raise(rb_eArgError, "recursive array");
            }
            else {
                tmp = rb_exec_recursive(file_inspect_join, ary, tmp);
            }
            break;
          default:
            FilePathStringValue(tmp);
            checked = FALSE;
        }
        RSTRING_GETMEM(result, name, len);
        if (i == 0) {
            rb_enc_copy(result, tmp);
        }
        else {
            tail = chompdirsep(name, name + len, rb_enc_get(result));
            if (RSTRING_PTR(tmp) && isdirsep(RSTRING_PTR(tmp)[0])) {
                rb_str_set_len(result, tail - name);
            }
            else if (!*tail) {
                rb_str_cat(result, "/", 1);
            }
        }
        enc = fs_enc_check(result, tmp);
        rb_str_buf_append(result, tmp);
        rb_enc_associate(result, enc);
    }
    RBASIC_SET_CLASS_RAW(result, rb_cString);

    return result;
}

/*
 *  call-seq:
 *     File.join(string, ...)  ->  string
 *
 *  Returns a new string formed by joining the strings using
 *  <code>"/"</code>.
 *
 *     File.join("usr", "mail", "gumby")   #=> "usr/mail/gumby"
 *
 */

static VALUE
rb_file_s_join(VALUE klass, VALUE args)
{
    return rb_file_join(args);
}

#if defined(HAVE_TRUNCATE)
struct truncate_arg {
    const char *path;
    rb_off_t pos;
};

static void *
nogvl_truncate(void *ptr)
{
    struct truncate_arg *ta = ptr;
    return (void *)(VALUE)truncate(ta->path, ta->pos);
}

/*
 *  call-seq:
 *     File.truncate(file_name, integer)  -> 0
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
rb_file_s_truncate(VALUE klass, VALUE path, VALUE len)
{
    struct truncate_arg ta;
    int r;

    ta.pos = NUM2OFFT(len);
    FilePathValue(path);
    path = rb_str_encode_ospath(path);
    ta.path = StringValueCStr(path);

    r = IO_WITHOUT_GVL_INT(nogvl_truncate, &ta);
    if (r < 0)
        rb_sys_fail_path(path);
    return INT2FIX(0);
}
#else
#define rb_file_s_truncate rb_f_notimplement
#endif

#if defined(HAVE_FTRUNCATE)
struct ftruncate_arg {
    int fd;
    rb_off_t pos;
};

static VALUE
nogvl_ftruncate(void *ptr)
{
    struct ftruncate_arg *fa = ptr;

    return (VALUE)ftruncate(fa->fd, fa->pos);
}

/*
 *  call-seq:
 *     file.truncate(integer)    -> 0
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
rb_file_truncate(VALUE obj, VALUE len)
{
    rb_io_t *fptr;
    struct ftruncate_arg fa;

    fa.pos = NUM2OFFT(len);
    GetOpenFile(obj, fptr);
    if (!(fptr->mode & FMODE_WRITABLE)) {
        rb_raise(rb_eIOError, "not opened for writing");
    }
    rb_io_flush_raw(obj, 0);
    fa.fd = fptr->fd;
    if ((int)rb_thread_io_blocking_region(nogvl_ftruncate, &fa, fa.fd) < 0) {
        rb_sys_fail_path(fptr->pathv);
    }
    return INT2FIX(0);
}
#else
#define rb_file_truncate rb_f_notimplement
#endif

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
#endif

static VALUE
rb_thread_flock(void *data)
{
#ifdef __CYGWIN__
    int old_errno = errno;
#endif
    int *op = data, ret = flock(op[0], op[1]);

#ifdef __CYGWIN__
    if (GetLastError() == ERROR_NOT_LOCKED) {
        ret = 0;
        errno = old_errno;
    }
#endif
    return (VALUE)ret;
}

/*  :markup: markdown
 *
 *  call-seq:
 *    flock(locking_constant) -> 0 or false
 *
 *  Locks or unlocks file +self+ according to the given `locking_constant`,
 *  a bitwise OR of the values in the table below.
 *
 *  Not available on all platforms.
 *
 *  Returns `false` if `File::LOCK_NB` is specified and the operation would have blocked;
 *  otherwise returns `0`.
 *
 *  | Constant        | Lock         | Effect
 *  |-----------------|--------------|-----------------------------------------------------------------------------------------------------------------|
 *  | +File::LOCK_EX+ | Exclusive    | Only one process may hold an exclusive lock for +self+ at a time.                                               |
 *  | +File::LOCK_NB+ | Non-blocking | No blocking; may be combined with +File::LOCK_SH+ or +File::LOCK_EX+ using the bitwise OR operator <tt>\|</tt>. |
 *  | +File::LOCK_SH+ | Shared       | Multiple processes may each hold a shared lock for +self+ at the same time.                                     |
 *  | +File::LOCK_UN+ | Unlock       | Remove an existing lock held by this process.                                                                   |
 *
 *  Example:
 *
 *  ```ruby
 *  # Update a counter using an exclusive lock.
 *  # Don't use File::WRONLY because it truncates the file.
 *  File.open('counter', File::RDWR | File::CREAT, 0644) do |f|
 *    f.flock(File::LOCK_EX)
 *    value = f.read.to_i + 1
 *    f.rewind
 *    f.write("#{value}\n")
 *    f.flush
 *    f.truncate(f.pos)
 *  end
 *
 *  # Read the counter using a shared lock.
 *  File.open('counter', 'r') do |f|
 *    f.flock(File::LOCK_SH)
 *    f.read
 *  end
 *  ```
 *
 */

static VALUE
rb_file_flock(VALUE obj, VALUE operation)
{
    rb_io_t *fptr;
    int op[2], op1;
    struct timeval time;

    op[1] = op1 = NUM2INT(operation);
    GetOpenFile(obj, fptr);
    op[0] = fptr->fd;

    if (fptr->mode & FMODE_WRITABLE) {
        rb_io_flush_raw(obj, 0);
    }
    while ((int)rb_thread_io_blocking_region(rb_thread_flock, op, fptr->fd) < 0) {
        int e = errno;
        switch (e) {
          case EAGAIN:
          case EACCES:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
          case EWOULDBLOCK:
#endif
            if (op1 & LOCK_NB) return Qfalse;

            time.tv_sec = 0;
            time.tv_usec = 100 * 1000;	/* 0.1 sec */
            rb_thread_wait_for(time);
            rb_io_check_closed(fptr);
            continue;

          case EINTR:
#if defined(ERESTART)
          case ERESTART:
#endif
            break;

          default:
            rb_syserr_fail_path(e, fptr->pathv);
        }
    }
    return INT2FIX(0);
}

static void
test_check(int n, int argc, VALUE *argv)
{
    int i;

    n+=1;
    rb_check_arity(argc, n, n);
    for (i=1; i<n; i++) {
        if (!RB_TYPE_P(argv[i], T_FILE)) {
            FilePathValue(argv[i]);
        }
    }
}

#define CHECK(n) test_check((n), argc, argv)

/*
 *  :markup: markdown
 *
 *  call-seq:
 *    test(char, path0, path1 = nil) -> object
 *
 *  Performs a test on one or both of the <i>filesystem entities</i> at the given paths
 *  `path0` and `path1`:
 *
 *  - Each path `path0` or `path1` points to a file, directory, device, pipe, etc.
 *  - Character `char` selects a specific test.
 *
 *  The tests:
 *
 *  - Each of these tests operates only on the entity at `path0`,
 *    and returns `true` or `false`;
 *    for a non-existent entity, returns `false` (does not raise exception):
 *
 *      | Character    | Test                                                                      |
 *      |:------------:|:--------------------------------------------------------------------------|
 *      | <tt>'b'</tt> | Whether the entity is a block device.                                     |
 *      | <tt>'c'</tt> | Whether the entity is a character device.                                 |
 *      | <tt>'d'</tt> | Whether the entity is a directory.                                        |
 *      | <tt>'e'</tt> | Whether the entity is an existing entity.                                 |
 *      | <tt>'f'</tt> | Whether the entity is an existing regular file.                           |
 *      | <tt>'g'</tt> | Whether the entity's setgid bit is set.                                   |
 *      | <tt>'G'</tt> | Whether the entity's group ownership is equal to the caller's.            |
 *      | <tt>'k'</tt> | Whether the entity's sticky bit is set.                                   |
 *      | <tt>'l'</tt> | Whether the entity is a symbolic link.                                    |
 *      | <tt>'o'</tt> | Whether the entity is owned by the caller's effective uid.                |
 *      | <tt>'O'</tt> | Like <tt>'o'</tt>, but uses the real uid (not the effective uid).         |
 *      | <tt>'p'</tt> | Whether the entity is a FIFO device (named pipe).                         |
 *      | <tt>'r'</tt> | Whether the entity is readable by the caller's effecive uid/gid.          |
 *      | <tt>'R'</tt> | Like <tt>'r'</tt>, but uses the real uid/gid (not the effective uid/gid). |
 *      | <tt>'S'</tt> | Whether the entity is a socket.                                           |
 *      | <tt>'u'</tt> | Whether the entity's setuid bit is set.                                   |
 *      | <tt>'w'</tt> | Whether the entity is writable by the caller's effective uid/gid.         |
 *      | <tt>'W'</tt> | Like <tt>'w'</tt>, but uses the real uid/gid (not the effective uid/gid). |
 *      | <tt>'x'</tt> | Whether the entity is executable by the caller's effective uid/gid.       |
 *      | <tt>'X'</tt> | Like <tt>'x'</tt>, but uses the real uid/gid (not the effecive uid/git).  |
 *      | <tt>'z'</tt> | Whether the entity exists and is of length zero.                          |
 *
 *  - This test operates only on the entity at `path0`,
 *    and returns an integer size or +nil+:
 *
 *      | Character    | Test                                                                                         |
 *      |:------------:|:---------------------------------------------------------------------------------------------|
 *      | <tt>'s'</tt> | Returns positive integer size if the entity exists and has non-zero length, +nil+ otherwise. |
 *
 *  - Each of these tests operates only on the entity at `path0`,
 *    and returns a Time object;
 *    raises an exception if the entity does not exist:
 *
 *      | Character    | Test                                   |
 *      |:------------:|:---------------------------------------|
 *      | <tt>'A'</tt> | Last access time for the entity.       |
 *      | <tt>'C'</tt> | Last change time for the entity.       |
 *      | <tt>'M'</tt> | Last modification time for the entity. |
 *
 *  - Each of these tests operates on the modification time (`mtime`)
 *    of each of the entities at `path0` and `path1`,
 *    and returns a `true` or `false`;
 *    returns `false` if either entity does not exist:
 *
 *      | Character    | Test                                                            |
 *      |:------------:|:----------------------------------------------------------------|
 *      | <tt>'<'</tt> | Whether the `mtime` at `path0` is less than that at `path1`.    |
 *      | <tt>'='</tt> | Whether the `mtime` at `path0` is equal to that at `path1`.     |
 *      | <tt>'>'</tt> | Whether the `mtime` at `path0` is greater than that at `path1`. |
 *
 *  - This test operates on the content of each of the entities at `path0` and `path1`,
 *    and returns a `true` or `false`;
 *    returns `false` if either entity does not exist:
 *
 *      | Character    | Test                                          |
 *      |:------------:|:----------------------------------------------|
 *      | <tt>'-'</tt> | Whether the entities exist and are identical. |
 *
 */

static VALUE
rb_f_test(int argc, VALUE *argv, VALUE _)
{
    int cmd;

    if (argc == 0) rb_check_arity(argc, 2, 3);
    cmd = NUM2CHR(argv[0]);
    if (cmd == 0) {
        goto unknown;
    }
    if (strchr("bcdefgGkloOprRsSuwWxXz", cmd)) {
        CHECK(1);
        switch (cmd) {
          case 'b':
            return rb_file_blockdev_p(0, argv[1]);

          case 'c':
            return rb_file_chardev_p(0, argv[1]);

          case 'd':
            return rb_file_directory_p(0, argv[1]);

          case 'e':
            return rb_file_exist_p(0, argv[1]);

          case 'f':
            return rb_file_file_p(0, argv[1]);

          case 'g':
            return rb_file_sgid_p(0, argv[1]);

          case 'G':
            return rb_file_grpowned_p(0, argv[1]);

          case 'k':
            return rb_file_sticky_p(0, argv[1]);

          case 'l':
            return rb_file_symlink_p(0, argv[1]);

          case 'o':
            return rb_file_owned_p(0, argv[1]);

          case 'O':
            return rb_file_rowned_p(0, argv[1]);

          case 'p':
            return rb_file_pipe_p(0, argv[1]);

          case 'r':
            return rb_file_readable_p(0, argv[1]);

          case 'R':
            return rb_file_readable_real_p(0, argv[1]);

          case 's':
            return rb_file_size_p(0, argv[1]);

          case 'S':
            return rb_file_socket_p(0, argv[1]);

          case 'u':
            return rb_file_suid_p(0, argv[1]);

          case 'w':
            return rb_file_writable_p(0, argv[1]);

          case 'W':
            return rb_file_writable_real_p(0, argv[1]);

          case 'x':
            return rb_file_executable_p(0, argv[1]);

          case 'X':
            return rb_file_executable_real_p(0, argv[1]);

          case 'z':
            return rb_file_zero_p(0, argv[1]);
        }
    }

    if (strchr("MAC", cmd)) {
        struct stat st;
        VALUE fname = argv[1];

        CHECK(1);
        if (rb_stat(fname, &st) == -1) {
            int e = errno;
            FilePathValue(fname);
            rb_syserr_fail_path(e, fname);
        }

        switch (cmd) {
          case 'A':
            return stat_atime(&st);
          case 'M':
            return stat_mtime(&st);
          case 'C':
            return stat_ctime(&st);
        }
    }

    if (cmd == '-') {
        CHECK(2);
        return rb_file_identical_p(0, argv[1], argv[2]);
    }

    if (strchr("=<>", cmd)) {
        struct stat st1, st2;
        struct timespec t1, t2;

        CHECK(2);
        if (rb_stat(argv[1], &st1) < 0) return Qfalse;
        if (rb_stat(argv[2], &st2) < 0) return Qfalse;

        t1 = stat_mtimespec(&st1);
        t2 = stat_mtimespec(&st2);

        switch (cmd) {
          case '=':
            if (t1.tv_sec == t2.tv_sec && t1.tv_nsec == t2.tv_nsec) return Qtrue;
            return Qfalse;

          case '>':
            if (t1.tv_sec > t2.tv_sec) return Qtrue;
            if (t1.tv_sec == t2.tv_sec && t1.tv_nsec > t2.tv_nsec) return Qtrue;
            return Qfalse;

          case '<':
            if (t1.tv_sec < t2.tv_sec) return Qtrue;
            if (t1.tv_sec == t2.tv_sec && t1.tv_nsec < t2.tv_nsec) return Qtrue;
            return Qfalse;
        }
    }
  unknown:
    /* unknown command */
    if (ISPRINT(cmd)) {
        rb_raise(rb_eArgError, "unknown command '%s%c'", cmd == '\'' || cmd == '\\' ? "\\" : "", cmd);
    }
    else {
        rb_raise(rb_eArgError, "unknown command \"\\x%02X\"", cmd);
    }
    UNREACHABLE_RETURN(Qundef);
}


/*
 *  Document-class: File::Stat
 *
 *  Objects of class File::Stat encapsulate common status information
 *  for File objects. The information is recorded at the moment the
 *  File::Stat object is created; changes made to the file after that
 *  point will not be reflected. File::Stat objects are returned by
 *  IO#stat, File::stat, File#lstat, and File::lstat. Many of these
 *  methods return platform-specific values, and not all values are
 *  meaningful on all systems. See also Kernel#test.
 */

static VALUE
rb_stat_s_alloc(VALUE klass)
{
    return stat_new_0(klass, 0);
}

/*
 * call-seq:
 *
 *   File::Stat.new(file_name)  -> stat
 *
 * Create a File::Stat object for the given file name (raising an
 * exception if the file doesn't exist).
 */

static VALUE
rb_stat_init(VALUE obj, VALUE fname)
{
    struct stat st;

    FilePathValue(fname);
    fname = rb_str_encode_ospath(fname);
    if (STAT(StringValueCStr(fname), &st) == -1) {
        rb_sys_fail_path(fname);
    }

    struct rb_stat *rb_st;
    TypedData_Get_Struct(obj, struct rb_stat, &stat_data_type, rb_st);

    rb_st->stat = st;
    rb_st->initialized = true;

    return Qnil;
}

/* :nodoc: */
static VALUE
rb_stat_init_copy(VALUE copy, VALUE orig)
{
    if (!OBJ_INIT_COPY(copy, orig)) return copy;

    struct rb_stat *orig_rb_st;
    TypedData_Get_Struct(orig, struct rb_stat, &stat_data_type, orig_rb_st);

    struct rb_stat *copy_rb_st;
    TypedData_Get_Struct(copy, struct rb_stat, &stat_data_type, copy_rb_st);

    *copy_rb_st = *orig_rb_st;
    return copy;
}

/*
 *  call-seq:
 *     stat.ftype   -> string
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
rb_stat_ftype(VALUE obj)
{
    return rb_file_ftype(get_stat(obj));
}

/*
 *  call-seq:
 *     stat.directory?   -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a directory,
 *  <code>false</code> otherwise.
 *
 *     File.stat("testfile").directory?   #=> false
 *     File.stat(".").directory?          #=> true
 */

static VALUE
rb_stat_d(VALUE obj)
{
    if (S_ISDIR(get_stat(obj)->st_mode)) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.pipe?    -> true or false
 *
 *  Returns <code>true</code> if the operating system supports pipes and
 *  <i>stat</i> is a pipe; <code>false</code> otherwise.
 */

static VALUE
rb_stat_p(VALUE obj)
{
#ifdef S_IFIFO
    if (S_ISFIFO(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.symlink?    -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a symbolic link,
 *  <code>false</code> if it isn't or if the operating system doesn't
 *  support this feature. As File::stat automatically follows symbolic
 *  links, #symlink? will always be <code>false</code> for an object
 *  returned by File::stat.
 *
 *     File.symlink("testfile", "alink")   #=> 0
 *     File.stat("alink").symlink?         #=> false
 *     File.lstat("alink").symlink?        #=> true
 *
 */

static VALUE
rb_stat_l(VALUE obj)
{
#ifdef S_ISLNK
    if (S_ISLNK(get_stat(obj)->st_mode)) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.socket?    -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a socket,
 *  <code>false</code> if it isn't or if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("testfile").socket?   #=> false
 *
 */

static VALUE
rb_stat_S(VALUE obj)
{
#ifdef S_ISSOCK
    if (S_ISSOCK(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.blockdev?   -> true or false
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
rb_stat_b(VALUE obj)
{
#ifdef S_ISBLK
    if (S_ISBLK(get_stat(obj)->st_mode)) return Qtrue;

#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.chardev?    -> true or false
 *
 *  Returns <code>true</code> if the file is a character device,
 *  <code>false</code> if it isn't or if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("/dev/tty").chardev?   #=> true
 *
 */

static VALUE
rb_stat_c(VALUE obj)
{
    if (S_ISCHR(get_stat(obj)->st_mode)) return Qtrue;

    return Qfalse;
}

/*
 *  call-seq:
 *     stat.owned?    -> true or false
 *
 *  Returns <code>true</code> if the effective user id of the process is
 *  the same as the owner of <i>stat</i>.
 *
 *     File.stat("testfile").owned?      #=> true
 *     File.stat("/etc/passwd").owned?   #=> false
 *
 */

static VALUE
rb_stat_owned(VALUE obj)
{
    if (get_stat(obj)->st_uid == geteuid()) return Qtrue;
    return Qfalse;
}

static VALUE
rb_stat_rowned(VALUE obj)
{
    if (get_stat(obj)->st_uid == getuid()) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.grpowned?   -> true or false
 *
 *  Returns true if the effective group id of the process is the same as
 *  the group id of <i>stat</i>. On Windows, returns <code>false</code>.
 *
 *     File.stat("testfile").grpowned?      #=> true
 *     File.stat("/etc/passwd").grpowned?   #=> false
 *
 */

static VALUE
rb_stat_grpowned(VALUE obj)
{
#ifndef _WIN32
    if (rb_group_member(get_stat(obj)->st_gid)) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.readable?    -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is readable by the
 *  effective user id of this process.
 *
 *     File.stat("testfile").readable?   #=> true
 *
 */

static VALUE
rb_stat_r(VALUE obj)
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (geteuid() == 0) return Qtrue;
#endif
#ifdef S_IRUSR
    if (rb_stat_owned(obj))
        return RBOOL(st->st_mode & S_IRUSR);
#endif
#ifdef S_IRGRP
    if (rb_stat_grpowned(obj))
        return RBOOL(st->st_mode & S_IRGRP);
#endif
#ifdef S_IROTH
    if (!(st->st_mode & S_IROTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *     stat.readable_real?  ->  true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is readable by the real
 *  user id of this process.
 *
 *     File.stat("testfile").readable_real?   #=> true
 *
 */

static VALUE
rb_stat_R(VALUE obj)
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (getuid() == 0) return Qtrue;
#endif
#ifdef S_IRUSR
    if (rb_stat_rowned(obj))
        return RBOOL(st->st_mode & S_IRUSR);
#endif
#ifdef S_IRGRP
    if (rb_group_member(get_stat(obj)->st_gid))
        return RBOOL(st->st_mode & S_IRGRP);
#endif
#ifdef S_IROTH
    if (!(st->st_mode & S_IROTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 * call-seq:
 *    stat.world_readable? -> integer or nil
 *
 * If <i>stat</i> is readable by others, returns an integer
 * representing the file permission bits of <i>stat</i>. Returns
 * <code>nil</code> otherwise. The meaning of the bits is platform
 * dependent; on Unix systems, see <code>stat(2)</code>.
 *
 *    m = File.stat("/etc/passwd").world_readable?  #=> 420
 *    sprintf("%o", m)				    #=> "644"
 */

static VALUE
rb_stat_wr(VALUE obj)
{
#ifdef S_IROTH
    struct stat *st = get_stat(obj);
    if ((st->st_mode & (S_IROTH)) == S_IROTH) {
        return UINT2NUM(st->st_mode & (S_IRUGO|S_IWUGO|S_IXUGO));
    }
#endif
    return Qnil;
}

/*
 *  call-seq:
 *     stat.writable?  ->  true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is writable by the
 *  effective user id of this process.
 *
 *     File.stat("testfile").writable?   #=> true
 *
 */

static VALUE
rb_stat_w(VALUE obj)
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (geteuid() == 0) return Qtrue;
#endif
#ifdef S_IWUSR
    if (rb_stat_owned(obj))
        return RBOOL(st->st_mode & S_IWUSR);
#endif
#ifdef S_IWGRP
    if (rb_stat_grpowned(obj))
        return RBOOL(st->st_mode & S_IWGRP);
#endif
#ifdef S_IWOTH
    if (!(st->st_mode & S_IWOTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *     stat.writable_real?  ->  true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is writable by the real
 *  user id of this process.
 *
 *     File.stat("testfile").writable_real?   #=> true
 *
 */

static VALUE
rb_stat_W(VALUE obj)
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (getuid() == 0) return Qtrue;
#endif
#ifdef S_IWUSR
    if (rb_stat_rowned(obj))
        return RBOOL(st->st_mode & S_IWUSR);
#endif
#ifdef S_IWGRP
    if (rb_group_member(get_stat(obj)->st_gid))
        return RBOOL(st->st_mode & S_IWGRP);
#endif
#ifdef S_IWOTH
    if (!(st->st_mode & S_IWOTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 * call-seq:
 *    stat.world_writable?  ->  integer or nil
 *
 * If <i>stat</i> is writable by others, returns an integer
 * representing the file permission bits of <i>stat</i>. Returns
 * <code>nil</code> otherwise. The meaning of the bits is platform
 * dependent; on Unix systems, see <code>stat(2)</code>.
 *
 *    m = File.stat("/tmp").world_writable?	    #=> 511
 *    sprintf("%o", m)				    #=> "777"
 */

static VALUE
rb_stat_ww(VALUE obj)
{
#ifdef S_IWOTH
    struct stat *st = get_stat(obj);
    if ((st->st_mode & (S_IWOTH)) == S_IWOTH) {
        return UINT2NUM(st->st_mode & (S_IRUGO|S_IWUGO|S_IXUGO));
    }
#endif
    return Qnil;
}

/*
 *  call-seq:
 *     stat.executable?    -> true or false
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
rb_stat_x(VALUE obj)
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (geteuid() == 0) {
        return RBOOL(st->st_mode & S_IXUGO);
    }
#endif
#ifdef S_IXUSR
    if (rb_stat_owned(obj))
        return RBOOL(st->st_mode & S_IXUSR);
#endif
#ifdef S_IXGRP
    if (rb_stat_grpowned(obj))
        return RBOOL(st->st_mode & S_IXGRP);
#endif
#ifdef S_IXOTH
    if (!(st->st_mode & S_IXOTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *     stat.executable_real?    -> true or false
 *
 *  Same as <code>executable?</code>, but tests using the real owner of
 *  the process.
 */

static VALUE
rb_stat_X(VALUE obj)
{
    struct stat *st = get_stat(obj);

#ifdef USE_GETEUID
    if (getuid() == 0) {
        return RBOOL(st->st_mode & S_IXUGO);
    }
#endif
#ifdef S_IXUSR
    if (rb_stat_rowned(obj))
        return RBOOL(st->st_mode & S_IXUSR);
#endif
#ifdef S_IXGRP
    if (rb_group_member(get_stat(obj)->st_gid))
        return RBOOL(st->st_mode & S_IXGRP);
#endif
#ifdef S_IXOTH
    if (!(st->st_mode & S_IXOTH)) return Qfalse;
#endif
    return Qtrue;
}

/*
 *  call-seq:
 *     stat.file?    -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a regular file (not
 *  a device file, pipe, socket, etc.).
 *
 *     File.stat("testfile").file?   #=> true
 *
 */

static VALUE
rb_stat_f(VALUE obj)
{
    if (S_ISREG(get_stat(obj)->st_mode)) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.zero?    -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> is a zero-length file;
 *  <code>false</code> otherwise.
 *
 *     File.stat("testfile").zero?   #=> false
 *
 */

static VALUE
rb_stat_z(VALUE obj)
{
    if (get_stat(obj)->st_size == 0) return Qtrue;
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.size?    -> Integer or nil
 *
 *  Returns +nil+ if <i>stat</i> is a zero-length file, the size of
 *  the file otherwise.
 *
 *     File.stat("testfile").size?   #=> 66
 *     File.stat(File::NULL).size?   #=> nil
 *
 */

static VALUE
rb_stat_s(VALUE obj)
{
    rb_off_t size = get_stat(obj)->st_size;

    if (size == 0) return Qnil;
    return OFFT2NUM(size);
}

/*
 *  call-seq:
 *     stat.setuid?    -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> has the set-user-id
 *  permission bit set, <code>false</code> if it doesn't or if the
 *  operating system doesn't support this feature.
 *
 *     File.stat("/bin/su").setuid?   #=> true
 */

static VALUE
rb_stat_suid(VALUE obj)
{
#ifdef S_ISUID
    if (get_stat(obj)->st_mode & S_ISUID) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.setgid?   -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> has the set-group-id
 *  permission bit set, <code>false</code> if it doesn't or if the
 *  operating system doesn't support this feature.
 *
 *     File.stat("/usr/sbin/lpc").setgid?   #=> true
 *
 */

static VALUE
rb_stat_sgid(VALUE obj)
{
#ifdef S_ISGID
    if (get_stat(obj)->st_mode & S_ISGID) return Qtrue;
#endif
    return Qfalse;
}

/*
 *  call-seq:
 *     stat.sticky?    -> true or false
 *
 *  Returns <code>true</code> if <i>stat</i> has its sticky bit set,
 *  <code>false</code> if it doesn't or if the operating system doesn't
 *  support this feature.
 *
 *     File.stat("testfile").sticky?   #=> false
 *
 */

static VALUE
rb_stat_sticky(VALUE obj)
{
#ifdef S_ISVTX
    if (get_stat(obj)->st_mode & S_ISVTX) return Qtrue;
#endif
    return Qfalse;
}

#if !defined HAVE_MKFIFO && defined HAVE_MKNOD && defined S_IFIFO
#define mkfifo(path, mode) mknod(path, (mode)&~S_IFMT|S_IFIFO, 0)
#define HAVE_MKFIFO
#endif

#ifdef HAVE_MKFIFO
struct mkfifo_arg {
    const char *path;
    mode_t mode;
};

static void *
nogvl_mkfifo(void *ptr)
{
    struct mkfifo_arg *ma = ptr;

    return (void *)(VALUE)mkfifo(ma->path, ma->mode);
}

/*
 *  call-seq:
 *     File.mkfifo(file_name, mode=0666)  => 0
 *
 *  Creates a FIFO special file with name _file_name_.  _mode_
 *  specifies the FIFO's permissions. It is modified by the process's
 *  umask in the usual way: the permissions of the created file are
 *  (mode & ~umask).
 */

static VALUE
rb_file_s_mkfifo(int argc, VALUE *argv, VALUE _)
{
    VALUE path;
    struct mkfifo_arg ma;

    ma.mode = 0666;
    rb_check_arity(argc, 1, 2);
    if (argc > 1) {
        ma.mode = NUM2MODET(argv[1]);
    }
    path = argv[0];
    FilePathValue(path);
    path = rb_str_encode_ospath(path);
    ma.path = RSTRING_PTR(path);
    if (IO_WITHOUT_GVL(nogvl_mkfifo, &ma)) {
        rb_sys_fail_path(path);
    }
    return INT2FIX(0);
}
#else
#define rb_file_s_mkfifo rb_f_notimplement
#endif

static VALUE rb_mFConst;

void
rb_file_const(const char *name, VALUE value)
{
    rb_define_const(rb_mFConst, name, value);
}

int
rb_is_absolute_path(const char *path)
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
path_check_0(VALUE path)
{
    struct stat st;
    const char *p0 = StringValueCStr(path);
    const char *e0;
    rb_encoding *enc;
    char *p = 0, *s;

    if (!rb_is_absolute_path(p0)) {
        char *buf = ruby_getcwd();
        VALUE newpath;

        newpath = rb_str_new2(buf);
        xfree(buf);

        rb_str_cat2(newpath, "/");
        rb_str_cat2(newpath, p0);
        path = newpath;
        p0 = RSTRING_PTR(path);
    }
    e0 = p0 + RSTRING_LEN(path);
    enc = rb_enc_get(path);
    for (;;) {
#ifndef S_IWOTH
# define S_IWOTH 002
#endif
        if (STAT(p0, &st) == 0 && S_ISDIR(st.st_mode) && (st.st_mode & S_IWOTH)
#ifdef S_ISVTX
            && !(p && (st.st_mode & S_ISVTX))
#endif
            && !access(p0, W_OK)) {
            rb_enc_warn(enc, "Insecure world writable dir %s in PATH, mode 0%"
#if SIZEOF_DEV_T > SIZEOF_INT
                        PRI_MODET_PREFIX"o",
#else
                        "o",
#endif
                        p0, st.st_mode);
            if (p) *p = '/';
            RB_GC_GUARD(path);
            return 0;
        }
        s = strrdirsep(p0, e0, enc);
        if (p) *p = '/';
        if (!s || s == p0) return 1;
        p = s;
        e0 = p;
        *p = '\0';
    }
}
#endif

int
rb_path_check(const char *path)
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
        if (!path_check_0(rb_str_new(p0, p - p0))) {
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

int
ruby_is_fd_loadable(int fd)
{
#ifdef _WIN32
    return 1;
#else
    struct stat st;

    if (fstat(fd, &st) < 0)
        return 0;

    if (S_ISREG(st.st_mode))
        return 1;

    if (S_ISFIFO(st.st_mode) || S_ISCHR(st.st_mode))
        return -1;

    if (S_ISDIR(st.st_mode))
        errno = EISDIR;
    else
        errno = ENXIO;

    return 0;
#endif
}

#ifndef _WIN32
int
rb_file_load_ok(const char *path)
{
    int ret = 1;
    /*
      open(2) may block if path is FIFO and it's empty. Let's use O_NONBLOCK.
      FIXME: Why O_NDELAY is checked?
    */
    int mode = (O_RDONLY |
#if defined O_NONBLOCK
                O_NONBLOCK |
#elif defined O_NDELAY
                O_NDELAY |
#endif
                0);
    int fd = rb_cloexec_open(path, mode, 0);
    if (fd < 0) {
        if (!rb_gc_for_fd(errno)) return 0;
        fd = rb_cloexec_open(path, mode, 0);
        if (fd < 0) return 0;
    }
    rb_update_max_fd(fd);
    ret = ruby_is_fd_loadable(fd);
    (void)close(fd);
    return ret;
}
#endif

static int
is_explicit_relative(const char *path)
{
    if (*path++ != '.') return 0;
    if (*path == '.') path++;
    return isdirsep(*path);
}

static VALUE
copy_path_class(VALUE path, VALUE orig)
{
    int encidx = rb_enc_get_index(orig);
    if (encidx == ENCINDEX_ASCII_8BIT || encidx == ENCINDEX_US_ASCII)
        encidx = rb_filesystem_encindex();
    rb_enc_associate_index(path, encidx);
    str_shrink(path);
    RBASIC_SET_CLASS(path, rb_obj_class(orig));
    OBJ_FREEZE(path);
    return path;
}

int
rb_find_file_ext(VALUE *filep, const char *const *ext)
{
    const char *f = StringValueCStr(*filep);
    VALUE fname = *filep, load_path, tmp;
    long i, j, fnlen;
    int expanded = 0;

    if (!ext[0]) return 0;

    if (f[0] == '~') {
        fname = file_expand_path_1(fname);
        f = RSTRING_PTR(fname);
        *filep = fname;
        expanded = 1;
    }

    if (expanded || rb_is_absolute_path(f) || is_explicit_relative(f)) {
        if (!expanded) fname = file_expand_path_1(fname);
        fnlen = RSTRING_LEN(fname);
        for (i=0; ext[i]; i++) {
            rb_str_cat2(fname, ext[i]);
            if (rb_file_load_ok(RSTRING_PTR(fname))) {
                *filep = copy_path_class(fname, *filep);
                return (int)(i+1);
            }
            rb_str_set_len(fname, fnlen);
        }
        return 0;
    }

    RB_GC_GUARD(load_path) = rb_get_expanded_load_path();
    if (!load_path) return 0;

    fname = rb_str_dup(*filep);
    RBASIC_CLEAR_CLASS(fname);
    fnlen = RSTRING_LEN(fname);
    tmp = rb_str_tmp_new(MAXPATHLEN + 2);
    rb_enc_associate_index(tmp, rb_usascii_encindex());
    for (j=0; ext[j]; j++) {
        rb_str_cat2(fname, ext[j]);
        for (i = 0; i < RARRAY_LEN(load_path); i++) {
            VALUE str = RARRAY_AREF(load_path, i);

            RB_GC_GUARD(str) = rb_get_path(str);
            if (RSTRING_LEN(str) == 0) continue;
            rb_file_expand_path_internal(fname, str, 0, 0, tmp);
            if (rb_file_load_ok(RSTRING_PTR(tmp))) {
                *filep = copy_path_class(tmp, *filep);
                return (int)(j+1);
            }
        }
        rb_str_set_len(fname, fnlen);
    }
    rb_str_resize(tmp, 0);
    RB_GC_GUARD(load_path);
    return 0;
}

VALUE
rb_find_file(VALUE path)
{
    VALUE tmp, load_path;
    const char *f = StringValueCStr(path);
    int expanded = 0;

    if (f[0] == '~') {
        tmp = file_expand_path_1(path);
        path = copy_path_class(tmp, path);
        f = RSTRING_PTR(path);
        expanded = 1;
    }

    if (expanded || rb_is_absolute_path(f) || is_explicit_relative(f)) {
        if (!rb_file_load_ok(f)) return 0;
        if (!expanded)
            path = copy_path_class(file_expand_path_1(path), path);
        return path;
    }

    RB_GC_GUARD(load_path) = rb_get_expanded_load_path();
    if (load_path) {
        long i;

        tmp = rb_str_tmp_new(MAXPATHLEN + 2);
        rb_enc_associate_index(tmp, rb_usascii_encindex());
        for (i = 0; i < RARRAY_LEN(load_path); i++) {
            VALUE str = RARRAY_AREF(load_path, i);
            RB_GC_GUARD(str) = rb_get_path(str);
            if (RSTRING_LEN(str) > 0) {
                rb_file_expand_path_internal(path, str, 0, 0, tmp);
                f = RSTRING_PTR(tmp);
                if (rb_file_load_ok(f)) goto found;
            }
        }
        rb_str_resize(tmp, 0);
        return 0;
    }
    else {
        return 0;		/* no path, no load */
    }

  found:
    return copy_path_class(tmp, path);
}

#define define_filetest_function(name, func, argc) do {        \
    rb_define_module_function(rb_mFileTest, name, func, argc); \
    rb_define_singleton_method(rb_cFile, name, func, argc);    \
} while(false)

const char ruby_null_device[] =
#if defined DOSISH
    "NUL"
#elif defined AMIGA || defined __amigaos__
    "NIL"
#elif defined __VMS
    "NL:"
#else
    "/dev/null"
#endif
    ;

/*
 *  A \File object is a representation of a file in the underlying platform.
 *
 *  \Class \File extends module FileTest, supporting such singleton methods
 *  as <tt>File.exist?</tt>.
 *
 *  == About the Examples
 *
 *  Many examples here use these variables:
 *
 *    :include: doc/examples/files.rdoc
 *
 *  == Access Modes
 *
 *  Methods File.new and File.open each create a \File object for a given file path.
 *
 *  === \String Access Modes
 *
 *  Methods File.new and File.open each may take string argument +mode+, which:
 *
 *  - Begins with a 1- or 2-character
 *    {read/write mode}[rdoc-ref:File@Read-2FWrite+Mode].
 *  - May also contain a 1-character {data mode}[rdoc-ref:File@Data+Mode].
 *  - May also contain a 1-character
 *    {file-create mode}[rdoc-ref:File@File-Create+Mode].
 *
 *  ==== Read/Write Mode
 *
 *  The read/write +mode+ determines:
 *
 *  - Whether the file is to be initially truncated.
 *
 *  - Whether reading is allowed, and if so:
 *
 *    - The initial read position in the file.
 *    - Where in the file reading can occur.
 *
 *  - Whether writing is allowed, and if so:
 *
 *    - The initial write position in the file.
 *    - Where in the file writing can occur.
 *
 *  These tables summarize:
 *
 *    Read/Write Modes for Existing File
 *
 *    |------|-----------|----------|----------|----------|-----------|
 *    | R/W  | Initial   |          | Initial  |          | Initial   |
 *    | Mode | Truncate? |  Read    | Read Pos |  Write   | Write Pos |
 *    |------|-----------|----------|----------|----------|-----------|
 *    | 'r'  |    No     | Anywhere |    0     |   Error  |     -     |
 *    | 'w'  |    Yes    |   Error  |    -     | Anywhere |     0     |
 *    | 'a'  |    No     |   Error  |    -     | End only |    End    |
 *    | 'r+' |    No     | Anywhere |    0     | Anywhere |     0     |
 *    | 'w+' |    Yes    | Anywhere |    0     | Anywhere |     0     |
 *    | 'a+' |    No     | Anywhere |   End    | End only |    End    |
 *    |------|-----------|----------|----------|----------|-----------|
 *
 *    Read/Write Modes for \File To Be Created
 *
 *    |------|----------|----------|----------|-----------|
 *    | R/W  |          | Initial  |          | Initial   |
 *    | Mode |  Read    | Read Pos |  Write   | Write Pos |
 *    |------|----------|----------|----------|-----------|
 *    | 'w'  |   Error  |    -     | Anywhere |     0     |
 *    | 'a'  |   Error  |    -     | End only |     0     |
 *    | 'w+' | Anywhere |    0     | Anywhere |     0     |
 *    | 'a+' | Anywhere |    0     | End only |    End    |
 *    |------|----------|----------|----------|-----------|
 *
 *  Note that modes <tt>'r'</tt> and <tt>'r+'</tt> are not allowed
 *  for a non-existent file (exception raised).
 *
 *  In the tables:
 *
 *  - +Anywhere+ means that methods IO#rewind, IO#pos=, and IO#seek
 *    may be used to change the file's position,
 *    so that allowed reading or writing may occur anywhere in the file.
 *  - <tt>End only</tt> means that writing can occur only at end-of-file,
 *    and that methods IO#rewind, IO#pos=, and IO#seek do not affect writing.
 *  - +Error+ means that an exception is raised if disallowed reading or writing
 *    is attempted.
 *
 *  ===== Read/Write Modes for Existing \File
 *
 *  - <tt>'r'</tt>:
 *
 *    - \File is not initially truncated:
 *
 *        f = File.new('t.txt') # => #<File:t.txt>
 *        f.size == 0           # => false
 *
 *    - File's initial read position is 0:
 *
 *        f.pos # => 0
 *
 *    - \File may be read anywhere; see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.readline # => "First line\n"
 *        f.readline # => "Second line\n"
 *
 *        f.rewind
 *        f.readline # => "First line\n"
 *
 *        f.pos = 1
 *        f.readline # => "irst line\n"
 *
 *        f.seek(1, :CUR)
 *        f.readline # => "econd line\n"
 *
 *    - Writing is not allowed:
 *
 *        f.write('foo') # Raises IOError.
 *
 *  - <tt>'w'</tt>:
 *
 *    - \File is initially truncated:
 *
 *        path = 't.tmp'
 *        File.write(path, text)
 *        f = File.new(path, 'w')
 *        f.size == 0 # => true
 *
 *    - File's initial write position is 0:
 *
 *        f.pos # => 0
 *
 *    - \File may be written anywhere (even past end-of-file);
 *      see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.write('foo')
 *        f.flush
 *        File.read(path) # => "foo"
 *        f.pos # => 3
 *
 *        f.write('bar')
 *        f.flush
 *        File.read(path) # => "foobar"
 *        f.pos # => 6
 *
 *        f.rewind
 *        f.write('baz')
 *        f.flush
 *        File.read(path) # => "bazbar"
 *        f.pos # => 3
 *
 *        f.pos = 3
 *        f.write('foo')
 *        f.flush
 *        File.read(path) # => "bazfoo"
 *        f.pos # => 6
 *
 *        f.seek(-3, :END)
 *        f.write('bam')
 *        f.flush
 *        File.read(path) # => "bazbam"
 *        f.pos # => 6
 *
 *        f.pos = 8
 *        f.write('bah')  # Zero padding as needed.
 *        f.flush
 *        File.read(path) # => "bazbam\u0000\u0000bah"
 *        f.pos # => 11
 *
 *    - Reading is not allowed:
 *
 *        f.read # Raises IOError.
 *
 *  - <tt>'a'</tt>:
 *
 *    - \File is not initially truncated:
 *
 *        path = 't.tmp'
 *        File.write(path, 'foo')
 *        f = File.new(path, 'a')
 *        f.size == 0 # => false
 *
 *    - File's initial position is 0 (but is ignored):
 *
 *        f.pos # => 0
 *
 *    - \File may be written only at end-of-file;
 *      IO#rewind, IO#pos=, IO#seek do not affect writing:
 *
 *        f.write('bar')
 *        f.flush
 *        File.read(path) # => "foobar"
 *        f.write('baz')
 *        f.flush
 *        File.read(path) # => "foobarbaz"
 *
 *        f.rewind
 *        f.write('bat')
 *        f.flush
 *        File.read(path) # => "foobarbazbat"
 *
 *    - Reading is not allowed:
 *
 *        f.read # Raises IOError.
 *
 *  - <tt>'r+'</tt>:
 *
 *    - \File is not initially truncated:
 *
 *        path = 't.tmp'
 *        File.write(path, text)
 *        f = File.new(path, 'r+')
 *        f.size == 0 # => false
 *
 *    - File's initial read position is 0:
 *
 *        f.pos # => 0
 *
 *    - \File may be read or written anywhere (even past end-of-file);
 *      see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.readline # => "First line\n"
 *        f.readline # => "Second line\n"
 *
 *        f.rewind
 *        f.readline # => "First line\n"
 *
 *        f.pos = 1
 *        f.readline # => "irst line\n"
 *
 *        f.seek(1, :CUR)
 *        f.readline # => "econd line\n"
 *
 *        f.rewind
 *        f.write('WWW')
 *        f.flush
 *        File.read(path)
 *        # => "WWWst line\nSecond line\nFourth line\nFifth line\n"
 *
 *        f.pos = 10
 *        f.write('XXX')
 *        f.flush
 *        File.read(path)
 *        # => "WWWst lineXXXecond line\nFourth line\nFifth line\n"
 *
 *        f.seek(-6, :END)
 *        # => 0
 *        f.write('YYY')
 *        # => 3
 *        f.flush
 *        # => #<File:t.tmp>
 *        File.read(path)
 *        # => "WWWst lineXXXecond line\nFourth line\nFifth YYYe\n"
 *
 *        f.seek(2, :END)
 *        f.write('ZZZ') # Zero padding as needed.
 *        f.flush
 *        File.read(path)
 *        # => "WWWst lineXXXecond line\nFourth line\nFifth YYYe\n\u0000\u0000ZZZ"
 *
 *
 *  - <tt>'a+'</tt>:
 *
 *    - \File is not initially truncated:
 *
 *        path = 't.tmp'
 *        File.write(path, 'foo')
 *        f = File.new(path, 'a+')
 *        f.size == 0 # => false
 *
 *    - File's initial read position is 0:
 *
 *        f.pos # => 0
 *
 *    - \File may be written only at end-of-file;
 *      IO#rewind, IO#pos=, IO#seek do not affect writing:
 *
 *        f.write('bar')
 *        f.flush
 *        File.read(path)      # => "foobar"
 *        f.write('baz')
 *        f.flush
 *        File.read(path)      # => "foobarbaz"
 *
 *        f.rewind
 *        f.write('bat')
 *        f.flush
 *        File.read(path) # => "foobarbazbat"
 *
 *    - \File may be read anywhere; see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.rewind
 *        f.read # => "foobarbazbat"
 *
 *        f.pos = 3
 *        f.read # => "barbazbat"
 *
 *        f.seek(-3, :END)
 *        f.read # => "bat"
 *
 *  ===== Read/Write Modes for \File To Be Created
 *
 *  Note that modes <tt>'r'</tt> and <tt>'r+'</tt> are not allowed
 *  for a non-existent file (exception raised).
 *
 *  - <tt>'w'</tt>:
 *
 *    - File's initial write position is 0:
 *
 *        path = 't.tmp'
 *        FileUtils.rm_f(path)
 *        f = File.new(path, 'w')
 *        f.pos # => 0
 *
 *    - \File may be written anywhere (even past end-of-file);
 *      see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.write('foo')
 *        f.flush
 *        File.read(path) # => "foo"
 *        f.pos # => 3
 *
 *        f.write('bar')
 *        f.flush
 *        File.read(path) # => "foobar"
 *        f.pos # => 6
 *
 *        f.rewind
 *        f.write('baz')
 *        f.flush
 *        File.read(path) # => "bazbar"
 *        f.pos # => 3
 *
 *        f.pos = 3
 *        f.write('foo')
 *        f.flush
 *        File.read(path) # => "bazfoo"
 *        f.pos # => 6
 *
 *        f.seek(-3, :END)
 *        f.write('bam')
 *        f.flush
 *        File.read(path) # => "bazbam"
 *        f.pos # => 6
 *
 *        f.pos = 8
 *        f.write('bah')  # Zero padding as needed.
 *        f.flush
 *        File.read(path) # => "bazbam\u0000\u0000bah"
 *        f.pos # => 11
 *
 *    - Reading is not allowed:
 *
 *        f.read # Raises IOError.
 *
 *  - <tt>'a'</tt>:
 *
 *    - File's initial write position is 0:
 *
 *        path = 't.tmp'
 *        FileUtils.rm_f(path)
 *        f = File.new(path, 'a')
 *        f.pos # => 0
 *
 *    - Writing occurs only at end-of-file:
 *
 *        f.write('foo')
 *        f.pos # => 3
 *        f.write('bar')
 *        f.pos # => 6
 *        f.flush
 *        File.read(path) # => "foobar"
 *
 *        f.rewind
 *        f.write('baz')
 *        f.flush
 *        File.read(path) # => "foobarbaz"
 *
 *    - Reading is not allowed:
 *
 *        f.read # Raises IOError.
 *
 *  - <tt>'w+'</tt>:
 *
 *    - File's initial position is 0:
 *
 *        path = 't.tmp'
 *        FileUtils.rm_f(path)
 *        f = File.new(path, 'w+')
 *        f.pos # => 0
 *
 *    - \File may be written anywhere (even past end-of-file);
 *      see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.write('foo')
 *        f.flush
 *        File.read(path) # => "foo"
 *        f.pos # => 3
 *
 *        f.write('bar')
 *        f.flush
 *        File.read(path) # => "foobar"
 *        f.pos # => 6
 *
 *        f.rewind
 *        f.write('baz')
 *        f.flush
 *        File.read(path) # => "bazbar"
 *        f.pos # => 3
 *
 *        f.pos = 3
 *        f.write('foo')
 *        f.flush
 *        File.read(path) # => "bazfoo"
 *        f.pos # => 6
 *
 *        f.seek(-3, :END)
 *        f.write('bam')
 *        f.flush
 *        File.read(path) # => "bazbam"
 *        f.pos # => 6
 *
 *        f.pos = 8
 *        f.write('bah')  # Zero padding as needed.
 *        f.flush
 *        File.read(path) # => "bazbam\u0000\u0000bah"
 *        f.pos # => 11
 *
 *    - \File may be read anywhere (even past end-of-file);
 *      see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.rewind
 *        # => 0
 *        f.read
 *        # => "bazbam\u0000\u0000bah"
 *
 *        f.pos = 3
 *        # => 3
 *        f.read
 *        # => "bam\u0000\u0000bah"
 *
 *        f.seek(-3, :END)
 *        # => 0
 *        f.read
 *        # => "bah"
 *
 *  - <tt>'a+'</tt>:
 *
 *    - File's initial write position is 0:
 *
 *        path = 't.tmp'
 *        FileUtils.rm_f(path)
 *        f = File.new(path, 'a+')
 *        f.pos # => 0
 *
 *    - Writing occurs only at end-of-file:
 *
 *        f.write('foo')
 *        f.pos # => 3
 *        f.write('bar')
 *        f.pos # => 6
 *        f.flush
 *        File.read(path) # => "foobar"
 *
 *        f.rewind
 *        f.write('baz')
 *        f.flush
 *        File.read(path) # => "foobarbaz"
 *
 *    - \File may be read anywhere (even past end-of-file);
 *      see IO#rewind, IO#pos=, IO#seek:
 *
 *        f.rewind
 *        f.read # => "foobarbaz"
 *
 *        f.pos = 3
 *        f.read # => "barbaz"
 *
 *        f.seek(-3, :END)
 *        f.read # => "baz"
 *
 *        f.pos = 800
 *        f.read # => ""
 *
 *  ==== \Data Mode
 *
 *  To specify whether data is to be treated as text or as binary data,
 *  either of the following may be suffixed to any of the string read/write modes
 *  above:
 *
 *  - <tt>'t'</tt>: Text data; sets the default external encoding
 *    to <tt>Encoding::UTF_8</tt>;
 *    on Windows, enables conversion between EOL and CRLF
 *    and enables interpreting <tt>0x1A</tt> as an end-of-file marker.
 *  - <tt>'b'</tt>: Binary data; sets the default external encoding
 *    to <tt>Encoding::ASCII_8BIT</tt>;
 *    on Windows, suppresses conversion between EOL and CRLF
 *    and disables interpreting <tt>0x1A</tt> as an end-of-file marker.
 *
 *  If neither is given, the stream defaults to text data.
 *
 *  Examples:
 *
 *    File.new('t.txt', 'rt')
 *    File.new('t.dat', 'rb')
 *
 *  When the data mode is specified, the read/write mode may not be omitted,
 *  and the data mode must precede the file-create mode, if given:
 *
 *    File.new('t.dat', 'b')   # Raises an exception.
 *    File.new('t.dat', 'rxb') # Raises an exception.
 *
 *  ==== \File-Create Mode
 *
 *  The following may be suffixed to any writable string mode above:
 *
 *  - <tt>'x'</tt>: Creates the file if it does not exist;
 *    raises an exception if the file exists.
 *
 *  Example:
 *
 *    File.new('t.tmp', 'wx')
 *
 *  When the file-create mode is specified, the read/write mode may not be omitted,
 *  and the file-create mode must follow the data mode:
 *
 *    File.new('t.dat', 'x')   # Raises an exception.
 *    File.new('t.dat', 'rxb') # Raises an exception.
 *
 *  === \Integer Access Modes
 *
 *  When mode is an integer it must be one or more of the following constants,
 *  which may be combined by the bitwise OR operator <tt>|</tt>:
 *
 *  - +File::RDONLY+: Open for reading only.
 *  - +File::WRONLY+: Open for writing only.
 *  - +File::RDWR+: Open for reading and writing.
 *  - +File::APPEND+: Open for appending only.
 *
 *  Examples:
 *
 *    File.new('t.txt', File::RDONLY)
 *    File.new('t.tmp', File::RDWR | File::CREAT | File::EXCL)
 *
 *  Note: Method IO#set_encoding does not allow the mode to be specified as an integer.
 *
 *  === File-Create Mode Specified as an \Integer
 *
 *  These constants may also be ORed into the integer mode:
 *
 *  - +File::CREAT+: Create file if it does not exist.
 *  - +File::EXCL+: Raise an exception if +File::CREAT+ is given and the file exists.
 *
 *  === \Data Mode Specified as an \Integer
 *
 *  \Data mode cannot be specified as an integer.
 *  When the stream access mode is given as an integer,
 *  the data mode is always text, never binary.
 *
 *  Note that although there is a constant +File::BINARY+,
 *  setting its value in an integer stream mode has no effect;
 *  this is because, as documented in File::Constants,
 *  the +File::BINARY+ value disables line code conversion,
 *  but does not change the external encoding.
 *
 *  === Encodings
 *
 *  Any of the string modes above may specify encodings -
 *  either external encoding only or both external and internal encodings -
 *  by appending one or both encoding names, separated by colons:
 *
 *    f = File.new('t.dat', 'rb')
 *    f.external_encoding # => #<Encoding:ASCII-8BIT>
 *    f.internal_encoding # => nil
 *    f = File.new('t.dat', 'rb:UTF-16')
 *    f.external_encoding # => #<Encoding:UTF-16 (dummy)>
 *    f.internal_encoding # => nil
 *    f = File.new('t.dat', 'rb:UTF-16:UTF-16')
 *    f.external_encoding # => #<Encoding:UTF-16 (dummy)>
 *    f.internal_encoding # => #<Encoding:UTF-16>
 *    f.close
 *
 *  The numerous encoding names are available in array Encoding.name_list:
 *
 *    Encoding.name_list.take(3) # => ["ASCII-8BIT", "UTF-8", "US-ASCII"]
 *
 *  When the external encoding is set, strings read are tagged by that encoding
 *  when reading, and strings written are converted to that encoding when
 *  writing.
 *
 *  When both external and internal encodings are set,
 *  strings read are converted from external to internal encoding,
 *  and strings written are converted from internal to external encoding.
 *  For further details about transcoding input and output,
 *  see {Encodings}[rdoc-ref:encodings.rdoc@Encodings].
 *
 *  If the external encoding is <tt>'BOM|UTF-8'</tt>, <tt>'BOM|UTF-16LE'</tt>
 *  or <tt>'BOM|UTF16-BE'</tt>,
 *  Ruby checks for a Unicode BOM in the input document
 *  to help determine the encoding.
 *  For UTF-16 encodings the file open mode must be binary.
 *  If the BOM is found,
 *  it is stripped and the external encoding from the BOM is used.
 *
 *  Note that the BOM-style encoding option is case insensitive,
 *  so <tt>'bom|utf-8'</tt> is also valid.
 *
 *  == \File Permissions
 *
 *  A \File object has _permissions_, an octal integer representing
 *  the permissions of an actual file in the underlying platform.
 *
 *  Note that file permissions are quite different from the _mode_
 *  of a file stream (\File object).
 *
 *  In a \File object, the permissions are available thus,
 *  where method +mode+, despite its name, returns permissions:
 *
 *    f = File.new('t.txt')
 *    f.lstat.mode.to_s(8) # => "100644"
 *
 *  On a Unix-based operating system,
 *  the three low-order octal digits represent the permissions
 *  for owner (6), group (4), and world (4).
 *  The triplet of bits in each octal digit represent, respectively,
 *  read, write, and execute permissions.
 *
 *  Permissions <tt>0644</tt> thus represent read-write access for owner
 *  and read-only access for group and world.
 *  See man pages {open(2)}[https://www.unix.com/man-page/bsd/2/open]
 *  and {chmod(2)}[https://www.unix.com/man-page/bsd/2/chmod].
 *
 *  For a directory, the meaning of the execute bit changes:
 *  when set, the directory can be searched.
 *
 *  Higher-order bits in permissions may indicate the type of file
 *  (plain, directory, pipe, socket, etc.) and various other special features.
 *
 *  On non-Posix operating systems, permissions may include only read-only or read-write,
 *  in which case, the remaining permission will resemble typical values.
 *  On Windows, for instance, the default permissions are <code>0644</code>;
 *  The only change that can be made is to make the file
 *  read-only, which is reported as <code>0444</code>.
 *
 *  For a method that actually creates a file in the underlying platform
 *  (as opposed to merely creating a \File object),
 *  permissions may be specified:
 *
 *    File.new('t.tmp', File::CREAT, 0644)
 *    File.new('t.tmp', File::CREAT, 0444)
 *
 *  Permissions may also be changed:
 *
 *    f = File.new('t.tmp', File::CREAT, 0444)
 *    f.chmod(0644)
 *    f.chmod(0444)
 *
 *  == \File \Constants
 *
 *  Various constants for use in \File and IO methods
 *  may be found in module File::Constants;
 *  an array of their names is returned by <tt>File::Constants.constants</tt>.
 *
 *  == What's Here
 *
 *  First, what's elsewhere. \Class \File:
 *
 *  - Inherits from {class IO}[rdoc-ref:IO@What-27s+Here],
 *    in particular, methods for creating, reading, and writing files
 *  - Includes module FileTest,
 *    which provides dozens of additional methods.
 *
 *  Here, class \File provides methods that are useful for:
 *
 *  - {Creating}[rdoc-ref:File@Creating]
 *  - {Querying}[rdoc-ref:File@Querying]
 *  - {Settings}[rdoc-ref:File@Settings]
 *  - {Other}[rdoc-ref:File@Other]
 *
 *  === Creating
 *
 *  - ::new: Opens the file at the given path; returns the file.
 *  - ::open: Same as ::new, but when given a block will yield the file to the block,
 *    and close the file upon exiting the block.
 *  - ::link: Creates a new name for an existing file using a hard link.
 *  - ::mkfifo: Returns the FIFO file created at the given path.
 *  - ::symlink: Creates a symbolic link for the given file path.
 *
 *  === Querying
 *
 *  _Paths_
 *
 *  - ::absolute_path: Returns the absolute file path for the given path.
 *  - ::absolute_path?: Returns whether the given path is the absolute file path.
 *  - ::basename: Returns the last component of the given file path.
 *  - ::dirname: Returns all but the last component of the given file path.
 *  - ::expand_path: Returns the absolute file path for the given path,
 *    expanding <tt>~</tt> for a home directory.
 *  - ::extname: Returns the file extension for the given file path.
 *  - ::fnmatch? (aliased as ::fnmatch): Returns whether the given file path
 *    matches the given pattern.
 *  - ::join: Joins path components into a single path string.
 *  - ::path: Returns the string representation of the given path.
 *  - ::readlink: Returns the path to the file at the given symbolic link.
 *  - ::realdirpath: Returns the real path for the given file path,
 *    where the last component need not exist.
 *  - ::realpath: Returns the real path for the given file path,
 *    where all components must exist.
 *  - ::split: Returns an array of two strings: the directory name and basename
 *    of the file at the given path.
 *  - #path (aliased as #to_path):  Returns the string representation of the given path.
 *
 *  _Times_
 *
 *  - ::atime: Returns a Time for the most recent access to the given file.
 *  - ::birthtime: Returns a Time  for the creation of the given file.
 *  - ::ctime: Returns a Time  for the metadata change of the given file.
 *  - ::mtime: Returns a Time for the most recent data modification to
 *    the content of the given file.
 *  - #atime: Returns a Time for the most recent access to +self+.
 *  - #birthtime: Returns a Time  the creation for +self+.
 *  - #ctime: Returns a Time for the metadata change of +self+.
 *  - #mtime: Returns a Time for the most recent data modification
 *    to the content of +self+.
 *
 *  _Types_
 *
 *  - ::blockdev?: Returns whether the file at the given path is a block device.
 *  - ::chardev?: Returns whether the file at the given path is a character device.
 *  - ::directory?: Returns whether the file at the given path is a directory.
 *  - ::executable?: Returns whether the file at the given path is executable
 *    by the effective user and group of the current process.
 *  - ::executable_real?: Returns whether the file at the given path is executable
 *    by the real user and group of the current process.
 *  - ::exist?: Returns whether the file at the given path exists.
 *  - ::file?: Returns whether the file at the given path is a regular file.
 *  - ::ftype: Returns a string giving the type of the file at the given path.
 *  - ::grpowned?: Returns whether the effective group of the current process
 *    owns the file at the given path.
 *  - ::identical?: Returns whether the files at two given paths are identical.
 *  - ::lstat: Returns the File::Stat object for the last symbolic link
 *    in the given path.
 *  - ::owned?: Returns whether the effective user of the current process
 *    owns the file at the given path.
 *  - ::pipe?: Returns whether the file at the given path is a pipe.
 *  - ::readable?: Returns whether the file at the given path is readable
 *    by the effective user and group of the current process.
 *  - ::readable_real?: Returns whether the file at the given path is readable
 *    by the real user and group of the current process.
 *  - ::setgid?: Returns whether the setgid bit is set for the file at the given path.
 *  - ::setuid?: Returns whether the setuid bit is set for the file at the given path.
 *  - ::socket?: Returns whether the file at the given path is a socket.
 *  - ::stat: Returns the File::Stat object for the file at the given path.
 *  - ::sticky?: Returns whether the file at the given path has its sticky bit set.
 *  - ::symlink?: Returns whether the file at the given path is a symbolic link.
 *  - ::umask: Returns the umask value for the current process.
 *  - ::world_readable?: Returns whether the file at the given path is readable
 *    by others.
 *  - ::world_writable?: Returns whether the file at the given path is writable
 *    by others.
 *  - ::writable?: Returns whether the file at the given path is writable
 *    by the effective user and group of the current process.
 *  - ::writable_real?: Returns whether the file at the given path is writable
 *    by the real user and group of the current process.
 *  - #lstat: Returns the File::Stat object for the last symbolic link
 *    in the path for +self+.
 *
 *  _Contents_
 *
 *  - ::empty? (aliased as ::zero?): Returns whether the file at the given path
 *    exists and is empty.
 *  - ::size: Returns the size (bytes) of the file at the given path.
 *  - ::size?: Returns +nil+ if there is no file at the given path,
 *    or if that file is empty; otherwise returns the file size (bytes).
 *  - #size: Returns the size (bytes) of +self+.
 *
 *  === Settings
 *
 *  - ::chmod: Changes permissions of the file at the given path.
 *  - ::chown: Change ownership of the file at the given path.
 *  - ::lchmod: Changes permissions of the last symbolic link in the given path.
 *  - ::lchown: Change ownership of the last symbolic in the given path.
 *  - ::lutime: For each given file path, sets the access time and modification time
 *    of the last symbolic link in the path.
 *  - ::rename: Moves the file at one given path to another given path.
 *  - ::utime: Sets the access time and modification time of each file
 *    at the given paths.
 *  - #flock: Locks or unlocks +self+.
 *
 *  === Other
 *
 *  - ::truncate: Truncates the file at the given file path to the given size.
 *  - ::unlink (aliased as ::delete): Deletes the file for each given file path.
 *  - #truncate: Truncates +self+ to the given size.
 *
 */

void
Init_File(void)
{
#if defined(__APPLE__) && defined(HAVE_WORKING_FORK)
    rb_CFString_class_initialize_before_fork();
#endif

    VALUE separator;

    rb_mFileTest = rb_define_module("FileTest");
    rb_cFile = rb_define_class("File", rb_cIO);

    define_filetest_function("directory?", rb_file_directory_p, 1);
    define_filetest_function("exist?", rb_file_exist_p, 1);
    define_filetest_function("readable?", rb_file_readable_p, 1);
    define_filetest_function("readable_real?", rb_file_readable_real_p, 1);
    define_filetest_function("world_readable?", rb_file_world_readable_p, 1);
    define_filetest_function("writable?", rb_file_writable_p, 1);
    define_filetest_function("writable_real?", rb_file_writable_real_p, 1);
    define_filetest_function("world_writable?", rb_file_world_writable_p, 1);
    define_filetest_function("executable?", rb_file_executable_p, 1);
    define_filetest_function("executable_real?", rb_file_executable_real_p, 1);
    define_filetest_function("file?", rb_file_file_p, 1);
    define_filetest_function("zero?", rb_file_zero_p, 1);
    define_filetest_function("empty?", rb_file_zero_p, 1);
    define_filetest_function("size?", rb_file_size_p, 1);
    define_filetest_function("size", rb_file_s_size, 1);
    define_filetest_function("owned?", rb_file_owned_p, 1);
    define_filetest_function("grpowned?", rb_file_grpowned_p, 1);

    define_filetest_function("pipe?", rb_file_pipe_p, 1);
    define_filetest_function("symlink?", rb_file_symlink_p, 1);
    define_filetest_function("socket?", rb_file_socket_p, 1);

    define_filetest_function("blockdev?", rb_file_blockdev_p, 1);
    define_filetest_function("chardev?", rb_file_chardev_p, 1);

    define_filetest_function("setuid?", rb_file_suid_p, 1);
    define_filetest_function("setgid?", rb_file_sgid_p, 1);
    define_filetest_function("sticky?", rb_file_sticky_p, 1);

    define_filetest_function("identical?", rb_file_identical_p, 2);

    rb_define_singleton_method(rb_cFile, "stat",  rb_file_s_stat, 1);
    rb_define_singleton_method(rb_cFile, "lstat", rb_file_s_lstat, 1);
    rb_define_singleton_method(rb_cFile, "ftype", rb_file_s_ftype, 1);

    rb_define_singleton_method(rb_cFile, "atime", rb_file_s_atime, 1);
    rb_define_singleton_method(rb_cFile, "mtime", rb_file_s_mtime, 1);
    rb_define_singleton_method(rb_cFile, "ctime", rb_file_s_ctime, 1);
    rb_define_singleton_method(rb_cFile, "birthtime", rb_file_s_birthtime, 1);

    rb_define_singleton_method(rb_cFile, "utime", rb_file_s_utime, -1);
    rb_define_singleton_method(rb_cFile, "chmod", rb_file_s_chmod, -1);
    rb_define_singleton_method(rb_cFile, "chown", rb_file_s_chown, -1);
    rb_define_singleton_method(rb_cFile, "lchmod", rb_file_s_lchmod, -1);
    rb_define_singleton_method(rb_cFile, "lchown", rb_file_s_lchown, -1);
    rb_define_singleton_method(rb_cFile, "lutime", rb_file_s_lutime, -1);

    rb_define_singleton_method(rb_cFile, "link", rb_file_s_link, 2);
    rb_define_singleton_method(rb_cFile, "symlink", rb_file_s_symlink, 2);
    rb_define_singleton_method(rb_cFile, "readlink", rb_file_s_readlink, 1);

    rb_define_singleton_method(rb_cFile, "unlink", rb_file_s_unlink, -1);
    rb_define_singleton_method(rb_cFile, "delete", rb_file_s_unlink, -1);
    rb_define_singleton_method(rb_cFile, "rename", rb_file_s_rename, 2);
    rb_define_singleton_method(rb_cFile, "umask", rb_file_s_umask, -1);
    rb_define_singleton_method(rb_cFile, "truncate", rb_file_s_truncate, 2);
    rb_define_singleton_method(rb_cFile, "mkfifo", rb_file_s_mkfifo, -1);
    rb_define_singleton_method(rb_cFile, "expand_path", s_expand_path, -1);
    rb_define_singleton_method(rb_cFile, "absolute_path", s_absolute_path, -1);
    rb_define_singleton_method(rb_cFile, "absolute_path?", s_absolute_path_p, 1);
    rb_define_singleton_method(rb_cFile, "realpath", rb_file_s_realpath, -1);
    rb_define_singleton_method(rb_cFile, "realdirpath", rb_file_s_realdirpath, -1);
    rb_define_singleton_method(rb_cFile, "basename", rb_file_s_basename, -1);
    rb_define_singleton_method(rb_cFile, "dirname", rb_file_s_dirname, -1);
    rb_define_singleton_method(rb_cFile, "extname", rb_file_s_extname, 1);
    rb_define_singleton_method(rb_cFile, "path", rb_file_s_path, 1);

    separator = rb_fstring_lit("/");
    /* separates directory parts in path */
    rb_define_const(rb_cFile, "Separator", separator);
    /* separates directory parts in path */
    rb_define_const(rb_cFile, "SEPARATOR", separator);
    rb_define_singleton_method(rb_cFile, "split",  rb_file_s_split, 1);
    rb_define_singleton_method(rb_cFile, "join",   rb_file_s_join, -2);

#ifdef DOSISH
    /* platform specific alternative separator */
    rb_define_const(rb_cFile, "ALT_SEPARATOR", rb_obj_freeze(rb_usascii_str_new2(file_alt_separator)));
#else
    rb_define_const(rb_cFile, "ALT_SEPARATOR", Qnil);
#endif
    /* path list separator */
    rb_define_const(rb_cFile, "PATH_SEPARATOR", rb_fstring_cstr(PATH_SEP));

    rb_define_method(rb_cIO, "stat",  rb_io_stat, 0); /* this is IO's method */
    rb_define_method(rb_cFile, "lstat",  rb_file_lstat, 0);

    rb_define_method(rb_cFile, "atime", rb_file_atime, 0);
    rb_define_method(rb_cFile, "mtime", rb_file_mtime, 0);
    rb_define_method(rb_cFile, "ctime", rb_file_ctime, 0);
    rb_define_method(rb_cFile, "birthtime", rb_file_birthtime, 0);
    rb_define_method(rb_cFile, "size", file_size, 0);

    rb_define_method(rb_cFile, "chmod", rb_file_chmod, 1);
    rb_define_method(rb_cFile, "chown", rb_file_chown, 2);
    rb_define_method(rb_cFile, "truncate", rb_file_truncate, 1);

    rb_define_method(rb_cFile, "flock", rb_file_flock, 1);

    /*
     * Document-module: File::Constants
     *
     * \Module +File::Constants+ defines file-related constants.
     *
     * There are two families of constants here:
     *
     * - Those having to do with {file access}[rdoc-ref:File::Constants@File+Access].
     * - Those having to do with {filename globbing}[rdoc-ref:File::Constants@Filename+Globbing+Constants+-28File-3A-3AFNM_-2A-29].
     *
     * \File constants defined for the local process may be retrieved
     * with method File::Constants.constants:
     *
     *   File::Constants.constants.take(5)
     *   # => [:RDONLY, :WRONLY, :RDWR, :APPEND, :CREAT]
     *
     * == \File Access
     *
     * \File-access constants may be used with optional argument +mode+ in calls
     * to the following methods:
     *
     * - File.new.
     * - File.open.
     * - IO.for_fd.
     * - IO.new.
     * - IO.open.
     * - IO.popen.
     * - IO.reopen.
     * - IO.sysopen.
     * - StringIO.new.
     * - StringIO.open.
     * - StringIO#reopen.
     *
     * === Read/Write Access
     *
     * Read-write access for a stream
     * may be specified by a file-access constant.
     *
     * The constant may be specified as part of a bitwise OR of other such constants.
     *
     * Any combination of the constants in this section may be specified.
     *
     * ==== File::RDONLY
     *
     * Flag File::RDONLY specifies the stream should be opened for reading only:
     *
     *   filepath = '/tmp/t.tmp'
     *   f = File.new(filepath, File::RDONLY)
     *   f.write('Foo') # Raises IOError (not opened for writing).
     *
     * ==== File::WRONLY
     *
     * Flag File::WRONLY specifies that the stream should be opened for writing only:
     *
     *   f = File.new(filepath, File::WRONLY)
     *   f.read # Raises IOError (not opened for reading).
     *
     * ==== File::RDWR
     *
     * Flag File::RDWR specifies that the stream should be opened
     * for both reading and writing:
     *
     *   f = File.new(filepath, File::RDWR)
     *   f.write('Foo') # => 3
     *   f.rewind       # => 0
     *   f.read         # => "Foo"
     *
     * === \File Positioning
     *
     * ==== File::APPEND
     *
     * Flag File::APPEND specifies that the stream should be opened
     * in append mode.
     *
     * Before each write operation, the position is set to end-of-stream.
     * The modification of the position and the following write operation
     * are performed as a single atomic step.
     *
     * ==== File::TRUNC
     *
     * Flag File::TRUNC specifies that the stream should be truncated
     * at its beginning.
     * If the file exists and is successfully opened for writing,
     * it is to be truncated to position zero;
     * its ctime and mtime are updated.
     *
     * There is no effect on a FIFO special file or a terminal device.
     * The effect on other file types is implementation-defined.
     * The result of using File::TRUNC with File::RDONLY is undefined.
     *
     * === Creating and Preserving
     *
     * ==== File::CREAT
     *
     * Flag File::CREAT specifies that the stream should be created
     * if it does not already exist.
     *
     * If the file exists:
     *
     *   - Raise an exception if File::EXCL is also specified.
     *   - Otherwise, do nothing.
     *
     * If the file does not exist, then it is created.
     * Upon successful completion, the atime, ctime, and mtime of the file are updated,
     * and the ctime and mtime of the parent directory are updated.
     *
     * ==== File::EXCL
     *
     * Flag File::EXCL specifies that the stream should not already exist;
     * If flags File::CREAT and File::EXCL are both specified
     * and the stream already exists, an exception is raised.
     *
     * The check for the existence and creation of the file is performed as an
     * atomic operation.
     *
     * If both File::EXCL and File::CREAT are specified and the path names a symbolic link,
     * an exception is raised regardless of the contents of the symbolic link.
     *
     * If File::EXCL is specified and File::CREAT is not specified,
     * the result is undefined.
     *
     * === POSIX \File \Constants
     *
     * Some file-access constants are defined only on POSIX-compliant systems;
     * those are:
     *
     * - File::SYNC.
     * - File::DSYNC.
     * - File::RSYNC.
     * - File::DIRECT.
     * - File::NOATIME.
     * - File::NOCTTY.
     * - File::NOFOLLOW.
     * - File::TMPFILE.
     *
     * ==== File::SYNC, File::RSYNC, and File::DSYNC
     *
     * Flag File::SYNC, File::RSYNC, or File::DSYNC
     * specifies synchronization of I/O operations with the underlying file system.
     *
     * These flags are valid only for POSIX-compliant systems.
     *
     * - File::SYNC specifies that all write operations (both data and metadata)
     *   are immediately to be flushed to the underlying storage device.
     *   This means that the data is written to the storage device,
     *   and the file's metadata (e.g., file size, timestamps, permissions)
     *   are also synchronized.
     *   This guarantees that data is safely stored on the storage medium
     *   before returning control to the calling program.
     *   This flag can have a significant impact on performance
     *   since it requires synchronous writes, which can be slower
     *   compared to asynchronous writes.
     *
     * - File::RSYNC specifies that any read operations on the file will not return
     *   until all outstanding write operations
     *   (those that have been issued but not completed) are also synchronized.
     *   This is useful when you want to read the most up-to-date data,
     *   which may still be in the process of being written.
     *
     * - File::DSYNC specifies that all _data_ write operations
     *   are immediately to be flushed to the underlying storage device;
     *   this differs from File::SYNC, which requires that _metadata_
     *   also be synchronized.
     *
     * Note that the behavior of these flags may vary slightly
     * depending on the operating system and filesystem being used.
     * Additionally, using these flags can have an impact on performance
     * due to the synchronous nature of the I/O operations,
     * so they should be used judiciously,
     * especially in performance-critical applications.
     *
     * ==== File::NOCTTY
     *
     * Flag File::NOCTTY specifies that if the stream is a terminal device,
     * that device does not become the controlling terminal for the process.
     *
     * Defined only for POSIX-compliant systems.
     *
     * ==== File::DIRECT
     *
     * Flag File::DIRECT requests that cache effects of the I/O to and from the stream
     * be minimized.
     *
     * Defined only for POSIX-compliant systems.
     *
     * ==== File::NOATIME
     *
     * Flag File::NOATIME specifies that act of opening the stream
     * should not modify its access time (atime).
     *
     * Defined only for POSIX-compliant systems.
     *
     * ==== File::NOFOLLOW
     *
     * Flag File::NOFOLLOW specifies that if path is a symbolic link,
     * it should not be followed.
     *
     * Defined only for POSIX-compliant systems.
     *
     * ==== File::TMPFILE
     *
     * Flag File::TMPFILE specifies that the opened stream
     * should be a new temporary file.
     *
     * Defined only for POSIX-compliant systems.
     *
     * === Other File-Access \Constants
     *
     * ==== File::NONBLOCK
     *
     * When possible, the file is opened in nonblocking mode.
     * Neither the open operation nor any subsequent I/O operations on
     * the file will cause the calling process to wait.
     *
     * ==== File::BINARY
     *
     * Flag File::BINARY specifies that the stream is to be accessed in binary mode.
     *
     * ==== File::SHARE_DELETE
     *
     * Flag File::SHARE_DELETE enables other processes to open the stream
     * with delete access.
     *
     * Windows only.
     *
     * If the stream is opened for (local) delete access without File::SHARE_DELETE,
     * and another process attempts to open it with delete access,
     * the attempt fails and the stream is not opened for that process.
     *
     * == Locking
     *
     * Four file constants relate to stream locking;
     * see File#flock:
     *
     * ==== File::LOCK_EX
     *
     * Flag File::LOCK_EX specifies an exclusive lock;
     * only one process a a time may lock the stream.
     *
     * ==== File::LOCK_NB
     *
     * Flag File::LOCK_NB specifies non-blocking locking for the stream;
     * may be combined with File::LOCK_EX or File::LOCK_SH.
     *
     * ==== File::LOCK_SH
     *
     * Flag File::LOCK_SH specifies that multiple processes may lock
     * the stream at the same time.
     *
     * ==== File::LOCK_UN
     *
     * Flag File::LOCK_UN specifies that the stream is not to be locked.
     *
     * == Filename Globbing \Constants (File::FNM_*)
     *
     * Filename-globbing constants may be used with optional argument +flags+
     * in calls to the following methods:
     *
     * - Dir.glob.
     * - File.fnmatch.
     * - Pathname#fnmatch.
     * - Pathname.glob.
     * - Pathname#glob.
     *
     * The constants are:
     *
     * ==== File::FNM_CASEFOLD
     *
     * Flag File::FNM_CASEFOLD makes patterns case insensitive
     * for File.fnmatch (but not Dir.glob).
     *
     * ==== File::FNM_DOTMATCH
     *
     * Flag File::FNM_DOTMATCH makes the <tt>'*'</tt> pattern
     * match a filename starting with <tt>'.'</tt>.
     *
     * ==== File::FNM_EXTGLOB
     *
     * Flag File::FNM_EXTGLOB enables pattern <tt>'{_a_,_b_}'</tt>,
     * which matches pattern '_a_' and pattern '_b_';
     * behaves like
     * a {regexp union}[rdoc-ref:Regexp.union]
     * (e.g., <tt>'(?:_a_|_b_)'</tt>):
     *
     *   pattern = '{LEGAL,BSDL}'
     *   Dir.glob(pattern)      # => ["LEGAL", "BSDL"]
     *   Pathname.glob(pattern) # => [#<Pathname:LEGAL>, #<Pathname:BSDL>]
     *   pathname.glob(pattern) # => [#<Pathname:LEGAL>, #<Pathname:BSDL>]
     *
     * ==== File::FNM_NOESCAPE
     *
     * Flag File::FNM_NOESCAPE disables <tt>'\'</tt> escaping.
     *
     * ==== File::FNM_PATHNAME
     *
     * Flag File::FNM_PATHNAME specifies that patterns <tt>'*'</tt> and <tt>'?'</tt>
     * do not match the directory separator
     * (the value of constant File::SEPARATOR).
     *
     * ==== File::FNM_SHORTNAME
     *
     * Flag File::FNM_SHORTNAME allows patterns to match short names if they exist.
     *
     * Windows only.
     *
     * ==== File::FNM_SYSCASE
     *
     * Flag File::FNM_SYSCASE specifies that case sensitivity
     * is the same as in the underlying operating system;
     * effective for File.fnmatch, but not Dir.glob.
     *
     * == Other \Constants
     *
     * ==== File::NULL
     *
     * Flag File::NULL contains the string value of the null device:
     *
     * - On a Unix-like OS, <tt>'/dev/null'</tt>.
     * - On Windows, <tt>'NUL'</tt>.
     *
     */
    rb_mFConst = rb_define_module_under(rb_cFile, "Constants");
    rb_include_module(rb_cIO, rb_mFConst);
    /* {File::RDONLY}[rdoc-ref:File::Constants@File-3A-3ARDONLY] */
    rb_define_const(rb_mFConst, "RDONLY", INT2FIX(O_RDONLY));
    /* {File::WRONLY}[rdoc-ref:File::Constants@File-3A-3AWRONLY] */
    rb_define_const(rb_mFConst, "WRONLY", INT2FIX(O_WRONLY));
    /* {File::RDWR}[rdoc-ref:File::Constants@File-3A-3ARDWR] */
    rb_define_const(rb_mFConst, "RDWR", INT2FIX(O_RDWR));
    /* {File::APPEND}[rdoc-ref:File::Constants@File-3A-3AAPPEND] */
    rb_define_const(rb_mFConst, "APPEND", INT2FIX(O_APPEND));
    /* {File::CREAT}[rdoc-ref:File::Constants@File-3A-3ACREAT] */
    rb_define_const(rb_mFConst, "CREAT", INT2FIX(O_CREAT));
    /* {File::EXCL}[rdoc-ref:File::Constants@File-3A-3AEXCL] */
    rb_define_const(rb_mFConst, "EXCL", INT2FIX(O_EXCL));
#if defined(O_NDELAY) || defined(O_NONBLOCK)
# ifndef O_NONBLOCK
#   define O_NONBLOCK O_NDELAY
# endif
    /* {File::NONBLOCK}[rdoc-ref:File::Constants@File-3A-3ANONBLOCK] */
    rb_define_const(rb_mFConst, "NONBLOCK", INT2FIX(O_NONBLOCK));
#endif
    /* {File::TRUNC}[rdoc-ref:File::Constants@File-3A-3ATRUNC] */
    rb_define_const(rb_mFConst, "TRUNC", INT2FIX(O_TRUNC));
#ifdef O_NOCTTY
    /* {File::NOCTTY}[rdoc-ref:File::Constants@File-3A-3ANOCTTY] */
    rb_define_const(rb_mFConst, "NOCTTY", INT2FIX(O_NOCTTY));
#endif
#ifndef O_BINARY
# define  O_BINARY 0
#endif
    /* {File::BINARY}[rdoc-ref:File::Constants@File-3A-3ABINARY] */
    rb_define_const(rb_mFConst, "BINARY", INT2FIX(O_BINARY));
#ifndef O_SHARE_DELETE
# define O_SHARE_DELETE 0
#endif
    /* {File::SHARE_DELETE}[rdoc-ref:File::Constants@File-3A-3ASHARE_DELETE] */
    rb_define_const(rb_mFConst, "SHARE_DELETE", INT2FIX(O_SHARE_DELETE));
#ifdef O_SYNC
    /* {File::SYNC}[rdoc-ref:File::Constants@File-3A-3ASYNC-2C+File-3A-3ARSYNC-2C+and+File-3A-3ADSYNC] */
    rb_define_const(rb_mFConst, "SYNC", INT2FIX(O_SYNC));
#endif
#ifdef O_DSYNC
    /* {File::DSYNC}[rdoc-ref:File::Constants@File-3A-3ASYNC-2C+File-3A-3ARSYNC-2C+and+File-3A-3ADSYNC] */
    rb_define_const(rb_mFConst, "DSYNC", INT2FIX(O_DSYNC));
#endif
#ifdef O_RSYNC
    /* {File::RSYNC}[rdoc-ref:File::Constants@File-3A-3ASYNC-2C+File-3A-3ARSYNC-2C+and+File-3A-3ADSYNC] */
    rb_define_const(rb_mFConst, "RSYNC", INT2FIX(O_RSYNC));
#endif
#ifdef O_NOFOLLOW
    /* {File::NOFOLLOW}[rdoc-ref:File::Constants@File-3A-3ANOFOLLOW] */
    rb_define_const(rb_mFConst, "NOFOLLOW", INT2FIX(O_NOFOLLOW)); /* FreeBSD, Linux */
#endif
#ifdef O_NOATIME
    /* {File::NOATIME}[rdoc-ref:File::Constants@File-3A-3ANOATIME] */
    rb_define_const(rb_mFConst, "NOATIME", INT2FIX(O_NOATIME)); /* Linux */
#endif
#ifdef O_DIRECT
    /* {File::DIRECT}[rdoc-ref:File::Constants@File-3A-3ADIRECT] */
    rb_define_const(rb_mFConst, "DIRECT", INT2FIX(O_DIRECT));
#endif
#ifdef O_TMPFILE
    /* {File::TMPFILE}[rdoc-ref:File::Constants@File-3A-3ATMPFILE] */
    rb_define_const(rb_mFConst, "TMPFILE", INT2FIX(O_TMPFILE));
#endif

    /* {File::LOCK_SH}[rdoc-ref:File::Constants@File-3A-3ALOCK_SH] */
    rb_define_const(rb_mFConst, "LOCK_SH", INT2FIX(LOCK_SH));
    /* {File::LOCK_EX}[rdoc-ref:File::Constants@File-3A-3ALOCK_EX] */
    rb_define_const(rb_mFConst, "LOCK_EX", INT2FIX(LOCK_EX));
    /* {File::LOCK_UN}[rdoc-ref:File::Constants@File-3A-3ALOCK_UN] */
    rb_define_const(rb_mFConst, "LOCK_UN", INT2FIX(LOCK_UN));
    /* {File::LOCK_NB}[rdoc-ref:File::Constants@File-3A-3ALOCK_NB] */
    rb_define_const(rb_mFConst, "LOCK_NB", INT2FIX(LOCK_NB));

    /* {File::NULL}[rdoc-ref:File::Constants@File-3A-3ANULL] */
    rb_define_const(rb_mFConst, "NULL", rb_fstring_cstr(ruby_null_device));

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
    rb_define_method(rb_cStat, "birthtime", rb_stat_birthtime, 0);

    rb_define_method(rb_cStat, "inspect", rb_stat_inspect, 0);

    rb_define_method(rb_cStat, "ftype", rb_stat_ftype, 0);

    rb_define_method(rb_cStat, "directory?",  rb_stat_d, 0);
    rb_define_method(rb_cStat, "readable?",  rb_stat_r, 0);
    rb_define_method(rb_cStat, "readable_real?",  rb_stat_R, 0);
    rb_define_method(rb_cStat, "world_readable?", rb_stat_wr, 0);
    rb_define_method(rb_cStat, "writable?",  rb_stat_w, 0);
    rb_define_method(rb_cStat, "writable_real?",  rb_stat_W, 0);
    rb_define_method(rb_cStat, "world_writable?", rb_stat_ww, 0);
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
