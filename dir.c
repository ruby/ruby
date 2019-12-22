/**********************************************************************

  dir.c -

  $Author$
  created at: Wed Jan  5 09:51:01 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/encoding.h"
#include "ruby/thread.h"
#include "internal.h"
#include "id.h"
#include "encindex.h"

#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifndef O_CLOEXEC
#  define O_CLOEXEC 0
#endif

#ifndef USE_OPENDIR_AT
# if defined(HAVE_FDOPENDIR) && defined(HAVE_DIRFD) && \
    defined(HAVE_OPENAT) && defined(HAVE_FSTATAT)
#   define USE_OPENDIR_AT 1
# else
#   define USE_OPENDIR_AT 0
# endif
#endif
#if USE_OPENDIR_AT
# include <fcntl.h>
#endif
#ifndef AT_FDCWD
# define AT_FDCWD -1
#endif

#undef HAVE_DIRENT_NAMLEN
#if defined HAVE_DIRENT_H && !defined _WIN32
# include <dirent.h>
# define NAMLEN(dirent) strlen((dirent)->d_name)
#elif defined HAVE_DIRECT_H && !defined _WIN32
# include <direct.h>
# define NAMLEN(dirent) strlen((dirent)->d_name)
#else
# define dirent direct
# define NAMLEN(dirent) (dirent)->d_namlen
# define HAVE_DIRENT_NAMLEN 1
# if HAVE_SYS_NDIR_H
#  include <sys/ndir.h>
# endif
# if HAVE_SYS_DIR_H
#  include <sys/dir.h>
# endif
# if HAVE_NDIR_H
#  include <ndir.h>
# endif
# ifdef _WIN32
#  include "win32/dir.h"
# endif
#endif

#include <errno.h>

#ifndef HAVE_STDLIB_H
char *getenv();
#endif

#ifndef HAVE_STRING_H
char *strchr(char*,char);
#endif

#include <ctype.h>

#include "ruby/util.h"

#define vm_initialized rb_cThread

/* define system APIs */
#ifdef _WIN32
#undef chdir
#define chdir(p) rb_w32_uchdir(p)
#undef mkdir
#define mkdir(p, m) rb_w32_umkdir((p), (m))
#undef rmdir
#define rmdir(p) rb_w32_urmdir(p)
#undef opendir
#define opendir(p) rb_w32_uopendir(p)
#define ruby_getcwd() rb_w32_ugetcwd(NULL, 0)
#define IS_WIN32 1
#else
#define IS_WIN32 0
#endif

#ifdef HAVE_SYS_ATTR_H
#include <sys/attr.h>
#endif

#define USE_NAME_ON_FS_REAL_BASENAME 1	/* platform dependent APIs to
					 * get real basenames */
#define USE_NAME_ON_FS_BY_FNMATCH 2	/* select the matching
					 * basename by fnmatch */

#ifdef HAVE_GETATTRLIST
# define USE_NAME_ON_FS USE_NAME_ON_FS_REAL_BASENAME
# define RUP32(size) ((size)+3/4)
# define SIZEUP32(type) RUP32(sizeof(type))
#elif defined _WIN32
# define USE_NAME_ON_FS USE_NAME_ON_FS_REAL_BASENAME
#elif defined DOSISH
# define USE_NAME_ON_FS USE_NAME_ON_FS_BY_FNMATCH
#else
# define USE_NAME_ON_FS 0
#endif

#ifdef __APPLE__
# define NORMALIZE_UTF8PATH 1
#else
# define NORMALIZE_UTF8PATH 0
#endif

#if NORMALIZE_UTF8PATH
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/vnode.h>

# if defined HAVE_FGETATTRLIST || !defined HAVE_GETATTRLIST
#   define need_normalization(dirp, path) need_normalization(dirp)
# else
#   define need_normalization(dirp, path) need_normalization(path)
# endif
static inline int
need_normalization(DIR *dirp, const char *path)
{
# if defined HAVE_FGETATTRLIST || defined HAVE_GETATTRLIST
    u_int32_t attrbuf[SIZEUP32(fsobj_tag_t)];
    struct attrlist al = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_OBJTAG,};
#   if defined HAVE_FGETATTRLIST
    int ret = fgetattrlist(dirfd(dirp), &al, attrbuf, sizeof(attrbuf), 0);
#   else
    int ret = getattrlist(path, &al, attrbuf, sizeof(attrbuf), 0);
#   endif
    if (!ret) {
	const fsobj_tag_t *tag = (void *)(attrbuf+1);
	switch (*tag) {
	  case VT_HFS:
	  case VT_CIFS:
	    return TRUE;
	}
    }
# endif
    return FALSE;
}

static inline int
has_nonascii(const char *ptr, size_t len)
{
    while (len > 0) {
	if (!ISASCII(*ptr)) return 1;
	ptr++;
	--len;
    }
    return 0;
}

# define IF_NORMALIZE_UTF8PATH(something) something
#else
# define IF_NORMALIZE_UTF8PATH(something) /* nothing */
#endif

#ifndef IFTODT
# define IFTODT(m)	(((m) & S_IFMT) / ((~S_IFMT & (S_IFMT-1)) + 1))
#endif

typedef enum {
#ifdef DT_UNKNOWN
    path_exist     = DT_UNKNOWN,
    path_directory = DT_DIR,
    path_regular   = DT_REG,
    path_symlink   = DT_LNK,
#else
    path_exist,
    path_directory = IFTODT(S_IFDIR),
    path_regular   = IFTODT(S_IFREG),
    path_symlink   = IFTODT(S_IFLNK),
#endif
    path_noent = -1,
    path_unknown = -2
} rb_pathtype_t;

#define FNM_NOESCAPE	0x01
#define FNM_PATHNAME	0x02
#define FNM_DOTMATCH	0x04
#define FNM_CASEFOLD	0x08
#define FNM_EXTGLOB	0x10
#if CASEFOLD_FILESYSTEM
#define FNM_SYSCASE	FNM_CASEFOLD
#else
#define FNM_SYSCASE	0
#endif
#if _WIN32
#define FNM_SHORTNAME	0x20
#else
#define FNM_SHORTNAME	0
#endif

#define FNM_NOMATCH	1
#define FNM_ERROR	2

# define Next(p, e, enc) ((p)+ rb_enc_mbclen((p), (e), (enc)))
# define Inc(p, e, enc) ((p) = Next((p), (e), (enc)))

static char *
bracket(
    const char *p, /* pattern (next to '[') */
    const char *pend,
    const char *s, /* string */
    const char *send,
    int flags,
    rb_encoding *enc)
{
    const int nocase = flags & FNM_CASEFOLD;
    const int escape = !(flags & FNM_NOESCAPE);
    unsigned int c1, c2;
    int r;
    int ok = 0, not = 0;

    if (p >= pend) return NULL;
    if (*p == '!' || *p == '^') {
	not = 1;
	p++;
    }

    while (*p != ']') {
	const char *t1 = p;
	if (escape && *t1 == '\\')
	    t1++;
	if (!*t1)
	    return NULL;
	p = t1 + (r = rb_enc_mbclen(t1, pend, enc));
	if (p >= pend) return NULL;
	if (p[0] == '-' && p[1] != ']') {
	    const char *t2 = p + 1;
	    int r2;
	    if (escape && *t2 == '\\')
		t2++;
	    if (!*t2)
		return NULL;
	    p = t2 + (r2 = rb_enc_mbclen(t2, pend, enc));
	    if (ok) continue;
	    if ((r <= (send-s) && memcmp(t1, s, r) == 0) ||
		(r2 <= (send-s) && memcmp(t2, s, r2) == 0)) {
		ok = 1;
		continue;
	    }
	    c1 = rb_enc_codepoint(s, send, enc);
	    if (nocase) c1 = rb_enc_toupper(c1, enc);
	    c2 = rb_enc_codepoint(t1, pend, enc);
	    if (nocase) c2 = rb_enc_toupper(c2, enc);
	    if (c1 < c2) continue;
	    c2 = rb_enc_codepoint(t2, pend, enc);
	    if (nocase) c2 = rb_enc_toupper(c2, enc);
	    if (c1 > c2) continue;
	}
	else {
	    if (ok) continue;
	    if (r <= (send-s) && memcmp(t1, s, r) == 0) {
		ok = 1;
		continue;
	    }
	    if (!nocase) continue;
	    c1 = rb_enc_toupper(rb_enc_codepoint(s, send, enc), enc);
	    c2 = rb_enc_toupper(rb_enc_codepoint(p, pend, enc), enc);
	    if (c1 != c2) continue;
	}
	ok = 1;
    }

    return ok == not ? NULL : (char *)p + 1;
}

/* If FNM_PATHNAME is set, only path element will be matched. (up to '/' or '\0')
   Otherwise, entire string will be matched.
   End marker itself won't be compared.
   And if function succeeds, *pcur reaches end marker.
*/
#define UNESCAPE(p) (escape && *(p) == '\\' ? (p) + 1 : (p))
#define ISEND(p) (!*(p) || (pathname && *(p) == '/'))
#define RETURN(val) return *pcur = p, *scur = s, (val);

static int
fnmatch_helper(
    const char **pcur, /* pattern */
    const char **scur, /* string */
    int flags,
    rb_encoding *enc)
{
    const int period = !(flags & FNM_DOTMATCH);
    const int pathname = flags & FNM_PATHNAME;
    const int escape = !(flags & FNM_NOESCAPE);
    const int nocase = flags & FNM_CASEFOLD;

    const char *ptmp = 0;
    const char *stmp = 0;

    const char *p = *pcur;
    const char *pend = p + strlen(p);
    const char *s = *scur;
    const char *send = s + strlen(s);

    int r;

    if (period && *s == '.' && *UNESCAPE(p) != '.') /* leading period */
	RETURN(FNM_NOMATCH);

    while (1) {
	switch (*p) {
	  case '*':
	    do { p++; } while (*p == '*');
	    if (ISEND(UNESCAPE(p))) {
		p = UNESCAPE(p);
		RETURN(0);
	    }
	    if (ISEND(s))
		RETURN(FNM_NOMATCH);
	    ptmp = p;
	    stmp = s;
	    continue;

	  case '?':
	    if (ISEND(s))
		RETURN(FNM_NOMATCH);
	    p++;
	    Inc(s, send, enc);
	    continue;

	  case '[': {
	    const char *t;
	    if (ISEND(s))
		RETURN(FNM_NOMATCH);
	    if ((t = bracket(p + 1, pend, s, send, flags, enc)) != 0) {
		p = t;
		Inc(s, send, enc);
		continue;
	    }
	    goto failed;
	  }
	}

	/* ordinary */
	p = UNESCAPE(p);
	if (ISEND(s))
	    RETURN(ISEND(p) ? 0 : FNM_NOMATCH);
	if (ISEND(p))
	    goto failed;
	r = rb_enc_precise_mbclen(p, pend, enc);
	if (!MBCLEN_CHARFOUND_P(r))
	    goto failed;
	if (r <= (send-s) && memcmp(p, s, r) == 0) {
	    p += r;
	    s += r;
	    continue;
	}
	if (!nocase) goto failed;
	if (rb_enc_toupper(rb_enc_codepoint(p, pend, enc), enc) !=
	    rb_enc_toupper(rb_enc_codepoint(s, send, enc), enc))
	    goto failed;
	p += r;
	Inc(s, send, enc);
	continue;

      failed: /* try next '*' position */
	if (ptmp && stmp) {
	    p = ptmp;
	    Inc(stmp, send, enc); /* !ISEND(*stmp) */
	    s = stmp;
	    continue;
	}
	RETURN(FNM_NOMATCH);
    }
}

static int
fnmatch(
    const char *pattern,
    rb_encoding *enc,
    const char *string,
    int flags)
{
    const char *p = pattern;
    const char *s = string;
    const char *send = s + strlen(string);
    const int period = !(flags & FNM_DOTMATCH);
    const int pathname = flags & FNM_PATHNAME;

    const char *ptmp = 0;
    const char *stmp = 0;

    if (pathname) {
	while (1) {
	    if (p[0] == '*' && p[1] == '*' && p[2] == '/') {
		do { p += 3; } while (p[0] == '*' && p[1] == '*' && p[2] == '/');
		ptmp = p;
		stmp = s;
	    }
	    if (fnmatch_helper(&p, &s, flags, enc) == 0) {
		while (*s && *s != '/') Inc(s, send, enc);
		if (*p && *s) {
		    p++;
		    s++;
		    continue;
		}
		if (!*p && !*s)
		    return 0;
	    }
	    /* failed : try next recursion */
	    if (ptmp && stmp && !(period && *stmp == '.')) {
		while (*stmp && *stmp != '/') Inc(stmp, send, enc);
		if (*stmp) {
		    p = ptmp;
		    stmp++;
		    s = stmp;
		    continue;
		}
	    }
	    return FNM_NOMATCH;
	}
    }
    else
	return fnmatch_helper(&p, &s, flags, enc);
}

VALUE rb_cDir;

struct dir_data {
    DIR *dir;
    const VALUE path;
    rb_encoding *enc;
};

static void
dir_mark(void *ptr)
{
    struct dir_data *dir = ptr;
    rb_gc_mark(dir->path);
}

static void
dir_free(void *ptr)
{
    struct dir_data *dir = ptr;

    if (dir->dir) closedir(dir->dir);
    xfree(dir);
}

static size_t
dir_memsize(const void *ptr)
{
    return sizeof(struct dir_data);
}

static const rb_data_type_t dir_data_type = {
    "dir",
    {dir_mark, dir_free, dir_memsize,},
    0, 0, RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE dir_close(VALUE);

static VALUE
dir_s_alloc(VALUE klass)
{
    struct dir_data *dirp;
    VALUE obj = TypedData_Make_Struct(klass, struct dir_data, &dir_data_type, dirp);

    dirp->dir = NULL;
    RB_OBJ_WRITE(obj, &dirp->path, Qnil);
    dirp->enc = NULL;

    return obj;
}

static void *
nogvl_opendir(void *ptr)
{
    const char *path = ptr;

    return (void *)opendir(path);
}

static DIR *
opendir_without_gvl(const char *path)
{
    if (vm_initialized) {
	union { const void *in; void *out; } u;

	u.in = path;

	return rb_thread_call_without_gvl(nogvl_opendir, u.out, RUBY_UBF_IO, 0);
    }
    else
	return opendir(path);
}

/*
 *  call-seq:
 *     Dir.new( string ) -> aDir
 *     Dir.new( string, encoding: enc ) -> aDir
 *
 *  Returns a new directory object for the named directory.
 *
 *  The optional <i>encoding</i> keyword argument specifies the encoding of the directory.
 *  If not specified, the filesystem encoding is used.
 */
static VALUE
dir_initialize(int argc, VALUE *argv, VALUE dir)
{
    struct dir_data *dp;
    rb_encoding  *fsenc;
    VALUE dirname, opt, orig;
    static ID keyword_ids[1];
    const char *path;

    if (!keyword_ids[0]) {
	keyword_ids[0] = rb_id_encoding();
    }

    fsenc = rb_filesystem_encoding();

    rb_scan_args(argc, argv, "1:", &dirname, &opt);

    if (!NIL_P(opt)) {
	VALUE enc;
	rb_get_kwargs(opt, keyword_ids, 0, 1, &enc);
	if (enc != Qundef && !NIL_P(enc)) {
	    fsenc = rb_to_encoding(enc);
	}
    }

    FilePathValue(dirname);
    orig = rb_str_dup_frozen(dirname);
    dirname = rb_str_encode_ospath(dirname);
    dirname = rb_str_dup_frozen(dirname);

    TypedData_Get_Struct(dir, struct dir_data, &dir_data_type, dp);
    if (dp->dir) closedir(dp->dir);
    dp->dir = NULL;
    RB_OBJ_WRITE(dir, &dp->path, Qnil);
    dp->enc = fsenc;
    path = RSTRING_PTR(dirname);
    dp->dir = opendir_without_gvl(path);
    if (dp->dir == NULL) {
	int e = errno;
	if (rb_gc_for_fd(e)) {
	    dp->dir = opendir_without_gvl(path);
	}
#ifdef HAVE_GETATTRLIST
	else if (e == EIO) {
	    u_int32_t attrbuf[1];
	    struct attrlist al = {ATTR_BIT_MAP_COUNT, 0};
	    if (getattrlist(path, &al, attrbuf, sizeof(attrbuf), FSOPT_NOFOLLOW) == 0) {
		dp->dir = opendir_without_gvl(path);
	    }
	}
#endif
	if (dp->dir == NULL) {
	    RB_GC_GUARD(dirname);
	    rb_syserr_fail_path(e, orig);
	}
    }
    RB_OBJ_WRITE(dir, &dp->path, orig);

    return dir;
}

/*
 *  call-seq:
 *     Dir.open( string ) -> aDir
 *     Dir.open( string, encoding: enc ) -> aDir
 *     Dir.open( string ) {| aDir | block } -> anObject
 *     Dir.open( string, encoding: enc ) {| aDir | block } -> anObject
 *
 *  The optional <i>encoding</i> keyword argument specifies the encoding of the directory.
 *  If not specified, the filesystem encoding is used.
 *
 *  With no block, <code>open</code> is a synonym for Dir::new. If a
 *  block is present, it is passed <i>aDir</i> as a parameter. The
 *  directory is closed at the end of the block, and Dir::open returns
 *  the value of the block.
 */
static VALUE
dir_s_open(int argc, VALUE *argv, VALUE klass)
{
    struct dir_data *dp;
    VALUE dir = TypedData_Make_Struct(klass, struct dir_data, &dir_data_type, dp);

    dir_initialize(argc, argv, dir);
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, dir, dir_close, dir);
    }

    return dir;
}

NORETURN(static void dir_closed(void));

static void
dir_closed(void)
{
    rb_raise(rb_eIOError, "closed directory");
}

static struct dir_data *
dir_get(VALUE dir)
{
    rb_check_frozen(dir);
    return rb_check_typeddata(dir, &dir_data_type);
}

static struct dir_data *
dir_check(VALUE dir)
{
    struct dir_data *dirp = dir_get(dir);
    if (!dirp->dir) dir_closed();
    return dirp;
}

#define GetDIR(obj, dirp) ((dirp) = dir_check(obj))


/*
 *  call-seq:
 *     dir.inspect -> string
 *
 *  Return a string describing this Dir object.
 */
static VALUE
dir_inspect(VALUE dir)
{
    struct dir_data *dirp;

    TypedData_Get_Struct(dir, struct dir_data, &dir_data_type, dirp);
    if (!NIL_P(dirp->path)) {
	VALUE str = rb_str_new_cstr("#<");
	rb_str_append(str, rb_class_name(CLASS_OF(dir)));
	rb_str_cat2(str, ":");
	rb_str_append(str, dirp->path);
	rb_str_cat2(str, ">");
	return str;
    }
    return rb_funcallv(dir, idTo_s, 0, 0);
}

/* Workaround for Solaris 10 that does not have dirfd.
   Note: Solaris 11 (POSIX.1-2008 compliant) has dirfd(3C).
 */
#if defined(__sun) && !defined(HAVE_DIRFD)
# if defined(HAVE_DIR_D_FD)
#  define dirfd(x) ((x)->d_fd)
#  define HAVE_DIRFD 1
# elif defined(HAVE_DIR_DD_FD)
#  define dirfd(x) ((x)->dd_fd)
#  define HAVE_DIRFD 1
# endif
#endif

#ifdef HAVE_DIRFD
/*
 *  call-seq:
 *     dir.fileno -> integer
 *
 *  Returns the file descriptor used in <em>dir</em>.
 *
 *     d = Dir.new("..")
 *     d.fileno   #=> 8
 *
 *  This method uses dirfd() function defined by POSIX 2008.
 *  NotImplementedError is raised on other platforms, such as Windows,
 *  which doesn't provide the function.
 *
 */
static VALUE
dir_fileno(VALUE dir)
{
    struct dir_data *dirp;
    int fd;

    GetDIR(dir, dirp);
    fd = dirfd(dirp->dir);
    if (fd == -1)
	rb_sys_fail("dirfd");
    return INT2NUM(fd);
}
#else
#define dir_fileno rb_f_notimplement
#endif

/*
 *  call-seq:
 *     dir.path -> string or nil
 *     dir.to_path -> string or nil
 *
 *  Returns the path parameter passed to <em>dir</em>'s constructor.
 *
 *     d = Dir.new("..")
 *     d.path   #=> ".."
 */
static VALUE
dir_path(VALUE dir)
{
    struct dir_data *dirp;

    TypedData_Get_Struct(dir, struct dir_data, &dir_data_type, dirp);
    if (NIL_P(dirp->path)) return Qnil;
    return rb_str_dup(dirp->path);
}

#if defined _WIN32
static int
fundamental_encoding_p(rb_encoding *enc)
{
    switch (rb_enc_to_index(enc)) {
      case ENCINDEX_ASCII:
      case ENCINDEX_US_ASCII:
      case ENCINDEX_UTF_8:
	return TRUE;
      default:
	return FALSE;
    }
}
# define READDIR(dir, enc) rb_w32_readdir((dir), (enc))
#else
# define READDIR(dir, enc) readdir((dir))
#endif

/* safe to use without GVL */
static int
to_be_skipped(const struct dirent *dp)
{
    const char *name = dp->d_name;
    if (name[0] != '.') return FALSE;
#ifdef HAVE_DIRENT_NAMLEN
    switch (NAMLEN(dp)) {
      case 2:
	if (name[1] != '.') return FALSE;
      case 1:
	return TRUE;
      default:
	break;
    }
#else
    if (!name[1]) return TRUE;
    if (name[1] != '.') return FALSE;
    if (!name[2]) return TRUE;
#endif
    return FALSE;
}

/*
 *  call-seq:
 *     dir.read -> string or nil
 *
 *  Reads the next entry from <em>dir</em> and returns it as a string.
 *  Returns <code>nil</code> at the end of the stream.
 *
 *     d = Dir.new("testdir")
 *     d.read   #=> "."
 *     d.read   #=> ".."
 *     d.read   #=> "config.h"
 */
static VALUE
dir_read(VALUE dir)
{
    struct dir_data *dirp;
    struct dirent *dp;

    GetDIR(dir, dirp);
    errno = 0;
    if ((dp = READDIR(dirp->dir, dirp->enc)) != NULL) {
	return rb_external_str_new_with_enc(dp->d_name, NAMLEN(dp), dirp->enc);
    }
    else {
	int e = errno;
	if (e != 0) rb_syserr_fail(e, 0);
	return Qnil;		/* end of stream */
    }
}

static VALUE dir_each_entry(VALUE, VALUE (*)(VALUE, VALUE), VALUE, int);

static VALUE
dir_yield(VALUE arg, VALUE path)
{
    return rb_yield(path);
}

/*
 *  call-seq:
 *     dir.each { |filename| block }  -> dir
 *     dir.each                       -> an_enumerator
 *
 *  Calls the block once for each entry in this directory, passing the
 *  filename of each entry as a parameter to the block.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     d = Dir.new("testdir")
 *     d.each  {|x| puts "Got #{x}" }
 *
 *  <em>produces:</em>
 *
 *     Got .
 *     Got ..
 *     Got config.h
 *     Got main.rb
 */
static VALUE
dir_each(VALUE dir)
{
    RETURN_ENUMERATOR(dir, 0, 0);
    return dir_each_entry(dir, dir_yield, Qnil, FALSE);
}

static VALUE
dir_each_entry(VALUE dir, VALUE (*each)(VALUE, VALUE), VALUE arg, int children_only)
{
    struct dir_data *dirp;
    struct dirent *dp;
    IF_NORMALIZE_UTF8PATH(int norm_p);

    GetDIR(dir, dirp);
    rewinddir(dirp->dir);
    IF_NORMALIZE_UTF8PATH(norm_p = need_normalization(dirp->dir, RSTRING_PTR(dirp->path)));
    while ((dp = READDIR(dirp->dir, dirp->enc)) != NULL) {
	const char *name = dp->d_name;
	size_t namlen = NAMLEN(dp);
	VALUE path;

	if (children_only && name[0] == '.') {
	    if (namlen == 1) continue; /* current directory */
	    if (namlen == 2 && name[1] == '.') continue; /* parent directory */
	}
#if NORMALIZE_UTF8PATH
	if (norm_p && has_nonascii(name, namlen) &&
	    !NIL_P(path = rb_str_normalize_ospath(name, namlen))) {
	    path = rb_external_str_with_enc(path, dirp->enc);
	}
	else
#endif
	path = rb_external_str_new_with_enc(name, namlen, dirp->enc);
	(*each)(arg, path);
    }
    return dir;
}

#ifdef HAVE_TELLDIR
/*
 *  call-seq:
 *     dir.pos -> integer
 *     dir.tell -> integer
 *
 *  Returns the current position in <em>dir</em>. See also Dir#seek.
 *
 *     d = Dir.new("testdir")
 *     d.tell   #=> 0
 *     d.read   #=> "."
 *     d.tell   #=> 12
 */
static VALUE
dir_tell(VALUE dir)
{
    struct dir_data *dirp;
    long pos;

    GetDIR(dir, dirp);
    pos = telldir(dirp->dir);
    return rb_int2inum(pos);
}
#else
#define dir_tell rb_f_notimplement
#endif

#ifdef HAVE_SEEKDIR
/*
 *  call-seq:
 *     dir.seek( integer ) -> dir
 *
 *  Seeks to a particular location in <em>dir</em>. <i>integer</i>
 *  must be a value returned by Dir#tell.
 *
 *     d = Dir.new("testdir")   #=> #<Dir:0x401b3c40>
 *     d.read                   #=> "."
 *     i = d.tell               #=> 12
 *     d.read                   #=> ".."
 *     d.seek(i)                #=> #<Dir:0x401b3c40>
 *     d.read                   #=> ".."
 */
static VALUE
dir_seek(VALUE dir, VALUE pos)
{
    struct dir_data *dirp;
    long p = NUM2LONG(pos);

    GetDIR(dir, dirp);
    seekdir(dirp->dir, p);
    return dir;
}
#else
#define dir_seek rb_f_notimplement
#endif

#ifdef HAVE_SEEKDIR
/*
 *  call-seq:
 *     dir.pos = integer  -> integer
 *
 *  Synonym for Dir#seek, but returns the position parameter.
 *
 *     d = Dir.new("testdir")   #=> #<Dir:0x401b3c40>
 *     d.read                   #=> "."
 *     i = d.pos                #=> 12
 *     d.read                   #=> ".."
 *     d.pos = i                #=> 12
 *     d.read                   #=> ".."
 */
static VALUE
dir_set_pos(VALUE dir, VALUE pos)
{
    dir_seek(dir, pos);
    return pos;
}
#else
#define dir_set_pos rb_f_notimplement
#endif

/*
 *  call-seq:
 *     dir.rewind -> dir
 *
 *  Repositions <em>dir</em> to the first entry.
 *
 *     d = Dir.new("testdir")
 *     d.read     #=> "."
 *     d.rewind   #=> #<Dir:0x401b3fb0>
 *     d.read     #=> "."
 */
static VALUE
dir_rewind(VALUE dir)
{
    struct dir_data *dirp;

    GetDIR(dir, dirp);
    rewinddir(dirp->dir);
    return dir;
}

/*
 *  call-seq:
 *     dir.close -> nil
 *
 *  Closes the directory stream.
 *  Calling this method on closed Dir object is ignored since Ruby 2.3.
 *
 *     d = Dir.new("testdir")
 *     d.close   #=> nil
 */
static VALUE
dir_close(VALUE dir)
{
    struct dir_data *dirp;

    dirp = dir_get(dir);
    if (!dirp->dir) return Qnil;
    closedir(dirp->dir);
    dirp->dir = NULL;

    return Qnil;
}

static void *
nogvl_chdir(void *ptr)
{
    const char *path = ptr;

    return (void *)(VALUE)chdir(path);
}

static void
dir_chdir(VALUE path)
{
    if (chdir(RSTRING_PTR(path)) < 0)
	rb_sys_fail_path(path);
}

static int chdir_blocking = 0;
static VALUE chdir_thread = Qnil;

struct chdir_data {
    VALUE old_path, new_path;
    int done;
};

static VALUE
chdir_yield(VALUE v)
{
    struct chdir_data *args = (void *)v;
    dir_chdir(args->new_path);
    args->done = TRUE;
    chdir_blocking++;
    if (chdir_thread == Qnil)
	chdir_thread = rb_thread_current();
    return rb_yield(args->new_path);
}

static VALUE
chdir_restore(VALUE v)
{
    struct chdir_data *args = (void *)v;
    if (args->done) {
	chdir_blocking--;
	if (chdir_blocking == 0)
	    chdir_thread = Qnil;
	dir_chdir(args->old_path);
    }
    return Qnil;
}

/*
 *  call-seq:
 *     Dir.chdir( [ string] ) -> 0
 *     Dir.chdir( [ string] ) {| path | block }  -> anObject
 *
 *  Changes the current working directory of the process to the given
 *  string. When called without an argument, changes the directory to
 *  the value of the environment variable <code>HOME</code>, or
 *  <code>LOGDIR</code>. SystemCallError (probably Errno::ENOENT) if
 *  the target directory does not exist.
 *
 *  If a block is given, it is passed the name of the new current
 *  directory, and the block is executed with that as the current
 *  directory. The original working directory is restored when the block
 *  exits. The return value of <code>chdir</code> is the value of the
 *  block. <code>chdir</code> blocks can be nested, but in a
 *  multi-threaded program an error will be raised if a thread attempts
 *  to open a <code>chdir</code> block while another thread has one
 *  open.
 *
 *     Dir.chdir("/var/spool/mail")
 *     puts Dir.pwd
 *     Dir.chdir("/tmp") do
 *       puts Dir.pwd
 *       Dir.chdir("/usr") do
 *         puts Dir.pwd
 *       end
 *       puts Dir.pwd
 *     end
 *     puts Dir.pwd
 *
 *  <em>produces:</em>
 *
 *     /var/spool/mail
 *     /tmp
 *     /usr
 *     /tmp
 *     /var/spool/mail
 */
static VALUE
dir_s_chdir(int argc, VALUE *argv, VALUE obj)
{
    VALUE path = Qnil;

    if (rb_check_arity(argc, 0, 1) == 1) {
        path = rb_str_encode_ospath(rb_get_path(argv[0]));
    }
    else {
	const char *dist = getenv("HOME");
	if (!dist) {
	    dist = getenv("LOGDIR");
	    if (!dist) rb_raise(rb_eArgError, "HOME/LOGDIR not set");
	}
	path = rb_str_new2(dist);
    }

    if (chdir_blocking > 0) {
	if (!rb_block_given_p() || rb_thread_current() != chdir_thread)
	    rb_warn("conflicting chdir during another chdir block");
    }

    if (rb_block_given_p()) {
	struct chdir_data args;

	args.old_path = rb_str_encode_ospath(rb_dir_getwd());
	args.new_path = path;
	args.done = FALSE;
	return rb_ensure(chdir_yield, (VALUE)&args, chdir_restore, (VALUE)&args);
    }
    else {
	char *p = RSTRING_PTR(path);
	int r = (int)(VALUE)rb_thread_call_without_gvl(nogvl_chdir, p,
							RUBY_UBF_IO, 0);
	if (r < 0)
	    rb_sys_fail_path(path);
    }

    return INT2FIX(0);
}

#ifndef _WIN32
VALUE
rb_dir_getwd_ospath(void)
{
    char *path;
    VALUE cwd;
    VALUE path_guard;

#undef RUBY_UNTYPED_DATA_WARNING
#define RUBY_UNTYPED_DATA_WARNING 0
    path_guard = Data_Wrap_Struct((VALUE)0, NULL, RUBY_DEFAULT_FREE, NULL);
    path = ruby_getcwd();
    DATA_PTR(path_guard) = path;
#ifdef __APPLE__
    cwd = rb_str_normalize_ospath(path, strlen(path));
#else
    cwd = rb_str_new2(path);
#endif
    DATA_PTR(path_guard) = 0;

    xfree(path);
    return cwd;
}
#endif

VALUE
rb_dir_getwd(void)
{
    rb_encoding *fs = rb_filesystem_encoding();
    int fsenc = rb_enc_to_index(fs);
    VALUE cwd = rb_dir_getwd_ospath();

    switch (fsenc) {
      case ENCINDEX_US_ASCII:
	fsenc = ENCINDEX_ASCII;
      case ENCINDEX_ASCII:
	break;
#if defined _WIN32 || defined __APPLE__
      default:
	return rb_str_conv_enc(cwd, NULL, fs);
#endif
    }
    return rb_enc_associate_index(cwd, fsenc);
}

/*
 *  call-seq:
 *     Dir.getwd -> string
 *     Dir.pwd -> string
 *
 *  Returns the path to the current working directory of this process as
 *  a string.
 *
 *     Dir.chdir("/tmp")   #=> 0
 *     Dir.getwd           #=> "/tmp"
 *     Dir.pwd             #=> "/tmp"
 */
static VALUE
dir_s_getwd(VALUE dir)
{
    return rb_dir_getwd();
}

static VALUE
check_dirname(VALUE dir)
{
    VALUE d = dir;
    char *path, *pend;
    long len;
    rb_encoding *enc;

    FilePathValue(d);
    enc = rb_enc_get(d);
    RSTRING_GETMEM(d, path, len);
    pend = path + len;
    pend = rb_enc_path_end(rb_enc_path_skip_prefix(path, pend, enc), pend, enc);
    if (pend - path < len) {
	d = rb_str_subseq(d, 0, pend - path);
	StringValueCStr(d);
    }
    return rb_str_encode_ospath(d);
}

#if defined(HAVE_CHROOT)
/*
 *  call-seq:
 *     Dir.chroot( string ) -> 0
 *
 *  Changes this process's idea of the file system root. Only a
 *  privileged process may make this call. Not available on all
 *  platforms. On Unix systems, see <code>chroot(2)</code> for more
 *  information.
 */
static VALUE
dir_s_chroot(VALUE dir, VALUE path)
{
    path = check_dirname(path);
    if (chroot(RSTRING_PTR(path)) == -1)
	rb_sys_fail_path(path);

    return INT2FIX(0);
}
#else
#define dir_s_chroot rb_f_notimplement
#endif

struct mkdir_arg {
    const char *path;
    mode_t mode;
};

static void *
nogvl_mkdir(void *ptr)
{
    struct mkdir_arg *m = ptr;

    return (void *)(VALUE)mkdir(m->path, m->mode);
}

/*
 *  call-seq:
 *     Dir.mkdir( string [, integer] ) -> 0
 *
 *  Makes a new directory named by <i>string</i>, with permissions
 *  specified by the optional parameter <i>anInteger</i>. The
 *  permissions may be modified by the value of File::umask, and are
 *  ignored on NT. Raises a SystemCallError if the directory cannot be
 *  created. See also the discussion of permissions in the class
 *  documentation for File.
 *
 *    Dir.mkdir(File.join(Dir.home, ".foo"), 0700) #=> 0
 *
 */
static VALUE
dir_s_mkdir(int argc, VALUE *argv, VALUE obj)
{
    struct mkdir_arg m;
    VALUE path, vmode;
    int r;

    if (rb_scan_args(argc, argv, "11", &path, &vmode) == 2) {
	m.mode = NUM2MODET(vmode);
    }
    else {
	m.mode = 0777;
    }

    path = check_dirname(path);
    m.path = RSTRING_PTR(path);
    r = (int)(VALUE)rb_thread_call_without_gvl(nogvl_mkdir, &m, RUBY_UBF_IO, 0);
    if (r < 0)
	rb_sys_fail_path(path);

    return INT2FIX(0);
}

static void *
nogvl_rmdir(void *ptr)
{
    const char *path = ptr;

    return (void *)(VALUE)rmdir(path);
}

/*
 *  call-seq:
 *     Dir.delete( string ) -> 0
 *     Dir.rmdir( string ) -> 0
 *     Dir.unlink( string ) -> 0
 *
 *  Deletes the named directory. Raises a subclass of SystemCallError
 *  if the directory isn't empty.
 */
static VALUE
dir_s_rmdir(VALUE obj, VALUE dir)
{
    const char *p;
    int r;

    dir = check_dirname(dir);
    p = RSTRING_PTR(dir);
    r = (int)(VALUE)rb_thread_call_without_gvl(nogvl_rmdir, (void *)p, RUBY_UBF_IO, 0);
    if (r < 0)
	rb_sys_fail_path(dir);

    return INT2FIX(0);
}

struct warning_args {
#ifdef RUBY_FUNCTION_NAME_STRING
    const char *func;
#endif
    const char *mesg;
    rb_encoding *enc;
};

#ifndef RUBY_FUNCTION_NAME_STRING
#define sys_enc_warning_in(func, mesg, enc) sys_enc_warning(mesg, enc)
#endif

static VALUE
sys_warning_1(VALUE mesg)
{
    const struct warning_args *arg = (struct warning_args *)mesg;
#ifdef RUBY_FUNCTION_NAME_STRING
    rb_sys_enc_warning(arg->enc, "%s: %s", arg->func, arg->mesg);
#else
    rb_sys_enc_warning(arg->enc, "%s", arg->mesg);
#endif
    return Qnil;
}

static void
sys_enc_warning_in(const char *func, const char *mesg, rb_encoding *enc)
{
    struct warning_args arg;
#ifdef RUBY_FUNCTION_NAME_STRING
    arg.func = func;
#endif
    arg.mesg = mesg;
    arg.enc = enc;
    rb_protect(sys_warning_1, (VALUE)&arg, 0);
}

#define GLOB_VERBOSE	(1U << (sizeof(int) * CHAR_BIT - 1))
#define sys_warning(val, enc) \
    ((flags & GLOB_VERBOSE) ? sys_enc_warning_in(RUBY_FUNCTION_NAME_STRING, (val), (enc)) :(void)0)

static inline void *
glob_alloc_n(size_t x, size_t y)
{
    size_t z;
    if (rb_mul_size_overflow(x, y, SSIZE_MAX, &z)) {
        rb_memerror();          /* or...? */
    }
    else {
        return malloc(z);
    }
}

#define GLOB_ALLOC(type) ((type *)malloc(sizeof(type)))
#define GLOB_ALLOC_N(type, n) ((type *)glob_alloc_n(sizeof(type), n))
#define GLOB_REALLOC(ptr, size) realloc((ptr), (size))
#define GLOB_FREE(ptr) free(ptr)
#define GLOB_JUMP_TAG(status) (((status) == -1) ? rb_memerror() : rb_jump_tag(status))

/*
 * ENOTDIR can be returned by stat(2) if a non-leaf element of the path
 * is not a directory.
 */
ALWAYS_INLINE(static int to_be_ignored(int e));
static inline int
to_be_ignored(int e)
{
    return e == ENOENT || e == ENOTDIR;
}

#ifdef _WIN32
#define STAT(p, s)	rb_w32_ustati128((p), (s))
#undef lstat
#define lstat(p, s)	rb_w32_ulstati128((p), (s))
#else
#define STAT(p, s)	stat((p), (s))
#endif

typedef int ruby_glob_errfunc(const char*, VALUE, const void*, int);
typedef struct {
    ruby_glob_func *match;
    ruby_glob_errfunc *error;
} ruby_glob_funcs_t;

static const char *
at_subpath(int fd, size_t baselen, const char *path)
{
#if USE_OPENDIR_AT
    if (fd != (int)AT_FDCWD && baselen > 0) {
	path += baselen;
	if (*path == '/') ++path;
    }
#endif
    return *path ? path : ".";
}

/* System call with warning */
static int
do_stat(int fd, size_t baselen, const char *path, struct stat *pst, int flags, rb_encoding *enc)
{
#if USE_OPENDIR_AT
    int ret = fstatat(fd, at_subpath(fd, baselen, path), pst, 0);
#else
    int ret = STAT(path, pst);
#endif
    if (ret < 0 && !to_be_ignored(errno))
	sys_warning(path, enc);

    return ret;
}

#if defined HAVE_LSTAT || defined lstat || USE_OPENDIR_AT
static int
do_lstat(int fd, size_t baselen, const char *path, struct stat *pst, int flags, rb_encoding *enc)
{
#if USE_OPENDIR_AT
    int ret = fstatat(fd, at_subpath(fd, baselen, path), pst, AT_SYMLINK_NOFOLLOW);
#else
    int ret = lstat(path, pst);
#endif
    if (ret < 0 && !to_be_ignored(errno))
	sys_warning(path, enc);

    return ret;
}
#else
#define do_lstat do_stat
#endif

struct opendir_at_arg {
    int basefd;
    const char *path;
};

static void *
with_gvl_gc_for_fd(void *ptr)
{
    int *e = ptr;

    return (void *)(rb_gc_for_fd(*e) ? Qtrue : Qfalse);
}

static int
gc_for_fd_with_gvl(int e)
{
    if (vm_initialized)
	return (int)(VALUE)rb_thread_call_with_gvl(with_gvl_gc_for_fd, &e);
    else
	return rb_gc_for_fd(e) ? Qtrue : Qfalse;
}

static void *
nogvl_opendir_at(void *ptr)
{
    const struct opendir_at_arg *oaa = ptr;
    DIR *dirp;

#if USE_OPENDIR_AT
    const int opendir_flags = (O_RDONLY|O_CLOEXEC|
#  ifdef O_DIRECTORY
			       O_DIRECTORY|
#  endif /* O_DIRECTORY */
			       0);
    int fd = openat(oaa->basefd, oaa->path, opendir_flags);

    dirp = fd >= 0 ? fdopendir(fd) : 0;
    if (!dirp) {
	int e = errno;

	switch (gc_for_fd_with_gvl(e)) {
	  default:
	    if (fd < 0) fd = openat(oaa->basefd, oaa->path, opendir_flags);
	    if (fd >= 0) dirp = fdopendir(fd);
	    if (dirp) return dirp;

	    e = errno;
	    /* fallthrough*/
	  case 0:
	    if (fd >= 0) close(fd);
	    errno = e;
	}
    }
#else  /* !USE_OPENDIR_AT */
    dirp = opendir(oaa->path);
    if (!dirp && gc_for_fd_with_gvl(errno))
	dirp = opendir(oaa->path);
#endif /* !USE_OPENDIR_AT */

    return dirp;
}

static DIR *
opendir_at(int basefd, const char *path)
{
    struct opendir_at_arg oaa;

    oaa.basefd = basefd;
    oaa.path = path;

    if (vm_initialized)
	return rb_thread_call_without_gvl(nogvl_opendir_at, &oaa, RUBY_UBF_IO, 0);
    else
	return nogvl_opendir_at(&oaa);
}

static DIR *
do_opendir(const int basefd, size_t baselen, const char *path, int flags, rb_encoding *enc,
	   ruby_glob_errfunc *errfunc, VALUE arg, int *status)
{
    DIR *dirp;
#ifdef _WIN32
    VALUE tmp = 0;
    if (!fundamental_encoding_p(enc)) {
	tmp = rb_enc_str_new(path, strlen(path), enc);
	tmp = rb_str_encode_ospath(tmp);
	path = RSTRING_PTR(tmp);
    }
#endif
    dirp = opendir_at(basefd, at_subpath(basefd, baselen, path));
    if (!dirp) {
	int e = errno;

	*status = 0;
	if (!to_be_ignored(e)) {
	    if (errfunc) {
		*status = (*errfunc)(path, arg, enc, e);
	    }
	    else {
		sys_warning(path, enc);
	    }
	}
    }
#ifdef _WIN32
    if (tmp) rb_str_resize(tmp, 0); /* GC guard */
#endif

    return dirp;
}

/* Globing pattern */
enum glob_pattern_type { PLAIN, ALPHA, BRACE, MAGICAL, RECURSIVE, MATCH_ALL, MATCH_DIR };

/* Return nonzero if S has any special globbing chars in it.  */
static enum glob_pattern_type
has_magic(const char *p, const char *pend, int flags, rb_encoding *enc)
{
    const int escape = !(flags & FNM_NOESCAPE);
    int hasalpha = 0;
    int hasmagical = 0;

    register char c;

    while (p < pend && (c = *p++) != 0) {
	switch (c) {
	  case '{':
	    return BRACE;

	  case '*':
	  case '?':
	  case '[':
	    hasmagical = 1;
	    break;

	  case '\\':
	    if (escape && p++ >= pend)
		continue;
	    break;

#ifdef _WIN32
	  case '.':
	    break;

	  case '~':
	    hasalpha = 1;
	    break;
#endif
	  default:
	    if (IS_WIN32 || ISALPHA(c)) {
		hasalpha = 1;
	    }
	    break;
	}

	p = Next(p-1, pend, enc);
    }

    return hasmagical ? MAGICAL : hasalpha ? ALPHA : PLAIN;
}

/* Find separator in globbing pattern. */
static char *
find_dirsep(const char *p, const char *pend, int flags, rb_encoding *enc)
{
    const int escape = !(flags & FNM_NOESCAPE);

    register char c;
    int open = 0;

    while ((c = *p++) != 0) {
	switch (c) {
	  case '[':
	    open = 1;
	    continue;
	  case ']':
	    open = 0;
	    continue;

	  case '{':
	    open = 1;
	    continue;
	  case '}':
	    open = 0;
	    continue;

	  case '/':
	    if (!open)
		return (char *)p-1;
	    continue;

	  case '\\':
	    if (escape && !(c = *p++))
		return (char *)p-1;
	    continue;
	}

	p = Next(p-1, pend, enc);
    }

    return (char *)p-1;
}

/* Remove escaping backslashes */
static char *
remove_backslashes(char *p, register const char *pend, rb_encoding *enc)
{
    char *t = p;
    char *s = p;

    while (*p) {
	if (*p == '\\') {
	    if (t != s)
		memmove(t, s, p - s);
	    t += p - s;
	    s = ++p;
	    if (!*p) break;
	}
	Inc(p, pend, enc);
    }

    while (*p++);

    if (t != s)
	memmove(t, s, p - s); /* move '\0' too */

    return p;
}

struct glob_pattern {
    char *str;
    enum glob_pattern_type type;
    struct glob_pattern *next;
};

static void glob_free_pattern(struct glob_pattern *list);

static struct glob_pattern *
glob_make_pattern(const char *p, const char *e, int flags, rb_encoding *enc)
{
    struct glob_pattern *list, *tmp, **tail = &list;
    int dirsep = 0; /* pattern is terminated with '/' */
    int recursive = 0;

    while (p < e && *p) {
	tmp = GLOB_ALLOC(struct glob_pattern);
	if (!tmp) goto error;
	if (p + 2 < e && p[0] == '*' && p[1] == '*' && p[2] == '/') {
	    /* fold continuous RECURSIVEs (needed in glob_helper) */
	    do { p += 3; while (*p == '/') p++; } while (p[0] == '*' && p[1] == '*' && p[2] == '/');
	    tmp->type = RECURSIVE;
	    tmp->str = 0;
	    dirsep = 1;
	    recursive = 1;
	}
	else {
	    const char *m = find_dirsep(p, e, flags, enc);
	    const enum glob_pattern_type magic = has_magic(p, m, flags, enc);
	    const enum glob_pattern_type non_magic = (USE_NAME_ON_FS || FNM_SYSCASE) ? PLAIN : ALPHA;
	    char *buf;

	    if (!(FNM_SYSCASE || magic > non_magic) && !recursive && *m) {
		const char *m2;
		while (has_magic(m+1, m2 = find_dirsep(m+1, e, flags, enc), flags, enc) <= non_magic &&
		       *m2) {
		    m = m2;
		}
	    }
	    buf = GLOB_ALLOC_N(char, m-p+1);
	    if (!buf) {
		GLOB_FREE(tmp);
		goto error;
	    }
	    memcpy(buf, p, m-p);
	    buf[m-p] = '\0';
	    tmp->type = magic > MAGICAL ? MAGICAL : magic > non_magic ? magic : PLAIN;
	    tmp->str = buf;
	    if (*m) {
		dirsep = 1;
		p = m + 1;
	    }
	    else {
		dirsep = 0;
		p = m;
	    }
	}
	*tail = tmp;
	tail = &tmp->next;
    }

    tmp = GLOB_ALLOC(struct glob_pattern);
    if (!tmp) {
      error:
	*tail = 0;
	glob_free_pattern(list);
	return 0;
    }
    tmp->type = dirsep ? MATCH_DIR : MATCH_ALL;
    tmp->str = 0;
    *tail = tmp;
    tmp->next = 0;

    return list;
}

static void
glob_free_pattern(struct glob_pattern *list)
{
    while (list) {
	struct glob_pattern *tmp = list;
	list = list->next;
	if (tmp->str)
	    GLOB_FREE(tmp->str);
	GLOB_FREE(tmp);
    }
}

static char *
join_path(const char *path, size_t len, int dirsep, const char *name, size_t namlen)
{
    char *buf = GLOB_ALLOC_N(char, len+namlen+(dirsep?1:0)+1);

    if (!buf) return 0;
    memcpy(buf, path, len);
    if (dirsep) {
	buf[len++] = '/';
    }
    memcpy(buf+len, name, namlen);
    buf[len+namlen] = '\0';
    return buf;
}

#ifdef HAVE_GETATTRLIST
# if defined HAVE_FGETATTRLIST
#   define is_case_sensitive(dirp, path) is_case_sensitive(dirp)
# else
#   define is_case_sensitive(dirp, path) is_case_sensitive(path)
# endif
static int
is_case_sensitive(DIR *dirp, const char *path)
{
    struct {
	u_int32_t length;
	vol_capabilities_attr_t cap[1];
    } __attribute__((aligned(4), packed)) attrbuf[1];
    struct attrlist al = {ATTR_BIT_MAP_COUNT, 0, 0, ATTR_VOL_INFO|ATTR_VOL_CAPABILITIES};
    const vol_capabilities_attr_t *const cap = attrbuf[0].cap;
    const int idx = VOL_CAPABILITIES_FORMAT;
    const uint32_t mask = VOL_CAP_FMT_CASE_SENSITIVE;

#   if defined HAVE_FGETATTRLIST
    if (fgetattrlist(dirfd(dirp), &al, attrbuf, sizeof(attrbuf), FSOPT_NOFOLLOW))
	return -1;
#   else
    if (getattrlist(path, &al, attrbuf, sizeof(attrbuf), FSOPT_NOFOLLOW))
	return -1;
#   endif
    if (!(cap->valid[idx] & mask))
	return -1;
    return (cap->capabilities[idx] & mask) != 0;
}

static char *
replace_real_basename(char *path, long base, rb_encoding *enc, int norm_p, int flags, rb_pathtype_t *type)
{
    struct {
	u_int32_t length;
	attrreference_t ref[1];
	fsobj_type_t objtype;
	char path[MAXPATHLEN * 3];
    } __attribute__((aligned(4), packed)) attrbuf[1];
    struct attrlist al = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_NAME|ATTR_CMN_OBJTYPE};
    const attrreference_t *const ar = attrbuf[0].ref;
    const char *name;
    long len;
    char *tmp;
    IF_NORMALIZE_UTF8PATH(VALUE utf8str = Qnil);

    *type = path_noent;
    if (getattrlist(path, &al, attrbuf, sizeof(attrbuf), FSOPT_NOFOLLOW)) {
	if (!to_be_ignored(errno))
	    sys_warning(path, enc);
	return path;
    }

    switch (attrbuf[0].objtype) {
      case VREG: *type = path_regular; break;
      case VDIR: *type = path_directory; break;
      case VLNK: *type = path_symlink; break;
      default: *type = path_exist; break;
    }
    name = (char *)ar + ar->attr_dataoffset;
    len = (long)ar->attr_length - 1;
    if (name + len > (char *)attrbuf + sizeof(attrbuf))
	return path;

# if NORMALIZE_UTF8PATH
    if (norm_p && has_nonascii(name, len)) {
	if (!NIL_P(utf8str = rb_str_normalize_ospath(name, len))) {
	    RSTRING_GETMEM(utf8str, name, len);
	}
    }
# endif

    tmp = GLOB_REALLOC(path, base + len + 1);
    if (tmp) {
	path = tmp;
	memcpy(path + base, name, len);
	path[base + len] = '\0';
    }
    IF_NORMALIZE_UTF8PATH(if (!NIL_P(utf8str)) rb_str_resize(utf8str, 0));
    return path;
}
#elif defined _WIN32
VALUE rb_w32_conv_from_wchar(const WCHAR *wstr, rb_encoding *enc);
int rb_w32_reparse_symlink_p(const WCHAR *path);

static char *
replace_real_basename(char *path, long base, rb_encoding *enc, int norm_p, int flags, rb_pathtype_t *type)
{
    char *plainname = path;
    volatile VALUE tmp = 0;
    WIN32_FIND_DATAW fd;
    WIN32_FILE_ATTRIBUTE_DATA fa;
    WCHAR *wplain;
    HANDLE h = INVALID_HANDLE_VALUE;
    long wlen;
    int e = 0;
    if (!fundamental_encoding_p(enc)) {
	tmp = rb_enc_str_new_cstr(plainname, enc);
	tmp = rb_str_encode_ospath(tmp);
	plainname = RSTRING_PTR(tmp);
    }
    wplain = rb_w32_mbstr_to_wstr(CP_UTF8, plainname, -1, &wlen);
    if (tmp) rb_str_resize(tmp, 0);
    if (!wplain) return path;
    if (GetFileAttributesExW(wplain, GetFileExInfoStandard, &fa)) {
	h = FindFirstFileW(wplain, &fd);
	e = rb_w32_map_errno(GetLastError());
    }
    if (fa.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
	if (!rb_w32_reparse_symlink_p(wplain))
	    fa.dwFileAttributes &= ~FILE_ATTRIBUTE_REPARSE_POINT;
    }
    free(wplain);
    if (h == INVALID_HANDLE_VALUE) {
	*type = path_noent;
	if (e && !to_be_ignored(e)) {
	    errno = e;
	    sys_warning(path, enc);
	}
	return path;
    }
    FindClose(h);
    *type =
	(fa.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ? path_symlink :
	(fa.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? path_directory :
	path_regular;
    if (tmp) {
	char *buf;
	tmp = rb_w32_conv_from_wchar(fd.cFileName, enc);
	wlen = RSTRING_LEN(tmp);
	buf = GLOB_REALLOC(path, base + wlen + 1);
	if (buf) {
	    path = buf;
	    memcpy(path + base, RSTRING_PTR(tmp), wlen);
	    path[base + wlen] = 0;
	}
	rb_str_resize(tmp, 0);
    }
    else {
	char *utf8filename;
	wlen = WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, NULL, 0, NULL, NULL);
	utf8filename = GLOB_REALLOC(0, wlen);
	if (utf8filename) {
	    char *buf;
	    WideCharToMultiByte(CP_UTF8, 0, fd.cFileName, -1, utf8filename, wlen, NULL, NULL);
	    buf = GLOB_REALLOC(path, base + wlen + 1);
	    if (buf) {
		path = buf;
		memcpy(path + base, utf8filename, wlen);
		path[base + wlen] = 0;
	    }
	    GLOB_FREE(utf8filename);
	}
    }
    return path;
}
#elif USE_NAME_ON_FS == USE_NAME_ON_FS_REAL_BASENAME
# error not implemented
#endif

#ifndef S_ISDIR
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif

#ifndef S_ISLNK
#  ifndef S_IFLNK
#    define S_ISLNK(m) (0)
#  else
#    define S_ISLNK(m) (((m) & S_IFMT) == S_IFLNK)
#  endif
#endif

struct glob_args {
    void (*func)(const char *, VALUE, void *);
    const char *path;
    const char *base;
    size_t baselen;
    VALUE value;
    rb_encoding *enc;
};

#define glob_call_func(func, path, arg, enc) (*(func))((path), (arg), (void *)(enc))

static VALUE
glob_func_caller(VALUE val)
{
    struct glob_args *args = (struct glob_args *)val;

    glob_call_func(args->func, args->path, args->value, args->enc);
    return Qnil;
}

struct glob_error_args {
    const char *path;
    rb_encoding *enc;
    int error;
};

static VALUE
glob_func_warning(VALUE val)
{
    struct glob_error_args *arg = (struct glob_error_args *)val;
    rb_syserr_enc_warning(arg->error, arg->enc, "%s", arg->path);
    return Qnil;
}

#if 0
static int
rb_glob_warning(const char *path, VALUE a, const void *enc, int error)
{
    int status;
    struct glob_error_args args;

    args.path = path;
    args.enc = enc;
    args.error = error;
    rb_protect(glob_func_warning, (VALUE)&args, &status);
    return status;
}
#endif

static VALUE
glob_func_error(VALUE val)
{
    struct glob_error_args *arg = (struct glob_error_args *)val;
    VALUE path = rb_enc_str_new_cstr(arg->path, arg->enc);
    rb_syserr_fail_str(arg->error, path);
    return Qnil;
}

static int
rb_glob_error(const char *path, VALUE a, const void *enc, int error)
{
    int status;
    struct glob_error_args args;
    VALUE (*errfunc)(VALUE) = glob_func_error;

    if (error == EACCES) {
	errfunc = glob_func_warning;
    }
    args.path = path;
    args.enc = enc;
    args.error = error;
    rb_protect(errfunc, (VALUE)&args, &status);
    return status;
}

static inline int
dirent_match(const char *pat, rb_encoding *enc, const char *name, const struct dirent *dp, int flags)
{
    if (fnmatch(pat, enc, name, flags) == 0) return 1;
#ifdef _WIN32
    if (dp->d_altname && (flags & FNM_SHORTNAME)) {
	if (fnmatch(pat, enc, dp->d_altname, flags) == 0) return 1;
    }
#endif
    return 0;
}

struct push_glob_args {
    int fd;
    const char *path;
    size_t baselen;
    size_t namelen;
    int dirsep; /* '/' should be placed before appending child entry's name to 'path'. */
    rb_pathtype_t pathtype; /* type of 'path' */
    int flags;
    const ruby_glob_funcs_t *funcs;
    VALUE arg;
};

struct dirent_brace_args {
    const char *name;
    const struct dirent *dp;
    int flags;
};

static int
dirent_match_brace(const char *pattern, VALUE val, void *enc)
{
    struct dirent_brace_args *arg = (struct dirent_brace_args *)val;

    return dirent_match(pattern, enc, arg->name, arg->dp, arg->flags);
}

/* join paths from pattern list of glob_make_pattern() */
static char*
join_path_from_pattern(struct glob_pattern **beg)
{
    struct glob_pattern *p;
    char *path = NULL;
    size_t path_len = 0;

    for (p = *beg; p; p = p->next) {
	const char *str;
	switch (p->type) {
	  case RECURSIVE:
	    str = "**";
	    break;
	  case MATCH_DIR:
	    /* append last slash */
	    str = "";
	    break;
	  default:
	    str = p->str;
	    if (!str) continue;
	}
	if (!path) {
	    path_len = strlen(str);
	    path = GLOB_ALLOC_N(char, path_len + 1);
            if (path) {
                memcpy(path, str, path_len);
                path[path_len] = '\0';
            }
        }
        else {
	    size_t len = strlen(str);
	    char *tmp;
	    tmp = GLOB_REALLOC(path, path_len + len + 2);
	    if (tmp) {
		path = tmp;
		path[path_len++] = '/';
		memcpy(path + path_len, str, len);
		path_len += len;
		path[path_len] = '\0';
	    }
	}
    }
    return path;
}

static int push_caller(const char *path, VALUE val, void *enc);

static int ruby_brace_expand(const char *str, int flags, ruby_glob_func *func, VALUE arg,
			     rb_encoding *enc, VALUE var);

static int
glob_helper(
    int fd,
    const char *path,
    size_t baselen,
    size_t namelen,
    int dirsep, /* '/' should be placed before appending child entry's name to 'path'. */
    rb_pathtype_t pathtype, /* type of 'path' */
    struct glob_pattern **beg,
    struct glob_pattern **end,
    int flags,
    const ruby_glob_funcs_t *funcs,
    VALUE arg,
    rb_encoding *enc)
{
    struct stat st;
    int status = 0;
    struct glob_pattern **cur, **new_beg, **new_end;
    int plain = 0, brace = 0, magical = 0, recursive = 0, match_all = 0, match_dir = 0;
    int escape = !(flags & FNM_NOESCAPE);
    size_t pathlen = baselen + namelen;

    for (cur = beg; cur < end; ++cur) {
	struct glob_pattern *p = *cur;
	if (p->type == RECURSIVE) {
	    recursive = 1;
	    p = p->next;
	}
	switch (p->type) {
	  case PLAIN:
	    plain = 1;
	    break;
	  case ALPHA:
#if USE_NAME_ON_FS == USE_NAME_ON_FS_REAL_BASENAME
	    plain = 1;
#else
	    magical = 1;
#endif
	    break;
	  case BRACE:
	    if (!recursive) {
		brace = 1;
	    }
	    break;
	  case MAGICAL:
	    magical = 2;
	    break;
	  case MATCH_ALL:
	    match_all = 1;
	    break;
	  case MATCH_DIR:
	    match_dir = 1;
	    break;
	  case RECURSIVE:
	    rb_bug("continuous RECURSIVEs");
	}
    }

    if (brace) {
	struct push_glob_args args;
	char* brace_path = join_path_from_pattern(beg);
	if (!brace_path) return -1;
	args.fd = fd;
	args.path = path;
	args.baselen = baselen;
	args.namelen = namelen;
	args.dirsep = dirsep;
	args.pathtype = pathtype;
	args.flags = flags;
	args.funcs = funcs;
	args.arg = arg;
	status = ruby_brace_expand(brace_path, flags, push_caller, (VALUE)&args, enc, Qfalse);
	GLOB_FREE(brace_path);
	return status;
    }

    if (*path) {
	if (match_all && pathtype == path_unknown) {
	    if (do_lstat(fd, baselen, path, &st, flags, enc) == 0) {
		pathtype = IFTODT(st.st_mode);
	    }
	    else {
		pathtype = path_noent;
	    }
	}
	if (match_dir && (pathtype == path_unknown || pathtype == path_symlink)) {
	    if (do_stat(fd, baselen, path, &st, flags, enc) == 0) {
		pathtype = IFTODT(st.st_mode);
	    }
	    else {
		pathtype = path_noent;
	    }
	}
	if (match_all && pathtype > path_noent) {
	    const char *subpath = path + baselen + (baselen && path[baselen] == '/');
	    status = glob_call_func(funcs->match, subpath, arg, enc);
	    if (status) return status;
	}
	if (match_dir && pathtype == path_directory) {
	    int seplen = (baselen && path[baselen] == '/');
	    const char *subpath = path + baselen + seplen;
	    char *tmp = join_path(subpath, namelen - seplen, dirsep, "", 0);
	    if (!tmp) return -1;
	    status = glob_call_func(funcs->match, tmp, arg, enc);
	    GLOB_FREE(tmp);
	    if (status) return status;
	}
    }

    if (pathtype == path_noent) return 0;

    if (magical || recursive) {
	struct dirent *dp;
	DIR *dirp;
# if USE_NAME_ON_FS == USE_NAME_ON_FS_BY_FNMATCH
	char *plainname = 0;
# endif
	IF_NORMALIZE_UTF8PATH(int norm_p);
# if USE_NAME_ON_FS == USE_NAME_ON_FS_BY_FNMATCH
	if (cur + 1 == end && (*cur)->type <= ALPHA) {
	    plainname = join_path(path, pathlen, dirsep, (*cur)->str, strlen((*cur)->str));
	    if (!plainname) return -1;
	    dirp = do_opendir(fd, basename, plainname, flags, enc, funcs->error, arg, &status);
	    GLOB_FREE(plainname);
	}
	else
# else
	    ;
# endif
	dirp = do_opendir(fd, baselen, path, flags, enc, funcs->error, arg, &status);
	if (dirp == NULL) {
# if FNM_SYSCASE || NORMALIZE_UTF8PATH
	    if ((magical < 2) && !recursive && (errno == EACCES)) {
		/* no read permission, fallback */
		goto literally;
	    }
# endif
	    return status;
	}
	IF_NORMALIZE_UTF8PATH(norm_p = need_normalization(dirp, *path ? path : "."));

# if NORMALIZE_UTF8PATH
	if (!(norm_p || magical || recursive)) {
	    closedir(dirp);
	    goto literally;
	}
# endif
# ifdef HAVE_GETATTRLIST
	if (is_case_sensitive(dirp, path) == 0)
	    flags |= FNM_CASEFOLD;
# endif
	while ((dp = READDIR(dirp, enc)) != NULL) {
	    char *buf;
	    rb_pathtype_t new_pathtype = path_unknown;
	    const char *name;
	    size_t namlen;
	    int dotfile = 0;
	    IF_NORMALIZE_UTF8PATH(VALUE utf8str = Qnil);

	    name = dp->d_name;
	    namlen = NAMLEN(dp);
	    if (recursive && name[0] == '.') {
		++dotfile;
		if (namlen == 1) {
		    /* unless DOTMATCH, skip current directories not to recurse infinitely */
		    if (!(flags & FNM_DOTMATCH)) continue;
		    ++dotfile;
		    new_pathtype = path_directory; /* force to skip stat/lstat */
		}
		else if (namlen == 2 && name[1] == '.') {
		    /* always skip parent directories not to recurse infinitely */
		    continue;
		}
	    }

# if NORMALIZE_UTF8PATH
	    if (norm_p && has_nonascii(name, namlen)) {
		if (!NIL_P(utf8str = rb_str_normalize_ospath(name, namlen))) {
		    RSTRING_GETMEM(utf8str, name, namlen);
		}
	    }
# endif
	    buf = join_path(path, pathlen, dirsep, name, namlen);
	    IF_NORMALIZE_UTF8PATH(if (!NIL_P(utf8str)) rb_str_resize(utf8str, 0));
	    if (!buf) {
		status = -1;
		break;
	    }
	    name = buf + pathlen + (dirsep != 0);
#ifdef DT_UNKNOWN
	    if (dp->d_type != DT_UNKNOWN) {
		/* Got it. We need no more lstat. */
		new_pathtype = dp->d_type;
	    }
#endif
	    if (recursive && dotfile < ((flags & FNM_DOTMATCH) ? 2 : 1) &&
		new_pathtype == path_unknown) {
		/* RECURSIVE never match dot files unless FNM_DOTMATCH is set */
		if (do_lstat(fd, baselen, buf, &st, flags, enc) == 0)
		    new_pathtype = IFTODT(st.st_mode);
		else
		    new_pathtype = path_noent;
	    }

	    new_beg = new_end = GLOB_ALLOC_N(struct glob_pattern *, (end - beg) * 2);
	    if (!new_beg) {
		GLOB_FREE(buf);
		status = -1;
		break;
	    }

	    for (cur = beg; cur < end; ++cur) {
		struct glob_pattern *p = *cur;
		struct dirent_brace_args args;
		if (p->type == RECURSIVE) {
		    if (new_pathtype == path_directory || /* not symlink but real directory */
			new_pathtype == path_exist) {
			if (dotfile < ((flags & FNM_DOTMATCH) ? 2 : 1))
			    *new_end++ = p; /* append recursive pattern */
		    }
		    p = p->next; /* 0 times recursion */
		}
		switch (p->type) {
		  case BRACE:
		    args.name = name;
		    args.dp = dp;
		    args.flags = flags;
		    if (ruby_brace_expand(p->str, flags, dirent_match_brace,
					  (VALUE)&args, enc, Qfalse) > 0)
			*new_end++ = p->next;
		    break;
		  case ALPHA:
# if USE_NAME_ON_FS == USE_NAME_ON_FS_BY_FNMATCH
		    if (plainname) {
			*new_end++ = p->next;
			break;
		    }
# endif
		  case PLAIN:
		  case MAGICAL:
		    if (dirent_match(p->str, enc, name, dp, flags))
			*new_end++ = p->next;
		  default:
		    break;
		}
	    }

	    status = glob_helper(fd, buf, baselen, name - buf - baselen + namlen, 1,
				 new_pathtype, new_beg, new_end,
				 flags, funcs, arg, enc);
	    GLOB_FREE(buf);
	    GLOB_FREE(new_beg);
	    if (status) break;
	}

	closedir(dirp);
    }
    else if (plain) {
	struct glob_pattern **copy_beg, **copy_end, **cur2;

# if FNM_SYSCASE || NORMALIZE_UTF8PATH
      literally:
# endif
	copy_beg = copy_end = GLOB_ALLOC_N(struct glob_pattern *, end - beg);
	if (!copy_beg) return -1;
	for (cur = beg; cur < end; ++cur)
	    *copy_end++ = (*cur)->type <= ALPHA ? *cur : 0;

	for (cur = copy_beg; cur < copy_end; ++cur) {
	    if (*cur) {
		rb_pathtype_t new_pathtype = path_unknown;
		char *buf;
		char *name;
		size_t len = strlen((*cur)->str) + 1;
		name = GLOB_ALLOC_N(char, len);
		if (!name) {
		    status = -1;
		    break;
		}
		memcpy(name, (*cur)->str, len);
		if (escape)
		    len = remove_backslashes(name, name+len-1, enc) - name;

		new_beg = new_end = GLOB_ALLOC_N(struct glob_pattern *, end - beg);
		if (!new_beg) {
		    GLOB_FREE(name);
		    status = -1;
		    break;
		}
		*new_end++ = (*cur)->next;
		for (cur2 = cur + 1; cur2 < copy_end; ++cur2) {
		    if (*cur2 && fnmatch((*cur2)->str, enc, name, flags) == 0) {
			*new_end++ = (*cur2)->next;
			*cur2 = 0;
		    }
		}

		buf = join_path(path, pathlen, dirsep, name, len);
		GLOB_FREE(name);
		if (!buf) {
		    GLOB_FREE(new_beg);
		    status = -1;
		    break;
		}
#if USE_NAME_ON_FS == USE_NAME_ON_FS_REAL_BASENAME
		if ((*cur)->type == ALPHA) {
		    buf = replace_real_basename(buf, pathlen + (dirsep != 0), enc,
						IF_NORMALIZE_UTF8PATH(1)+0,
						flags, &new_pathtype);
		    if (!buf) break;
		}
#endif
		status = glob_helper(fd, buf, baselen,
				     namelen + strlen(buf + pathlen), 1,
				     new_pathtype, new_beg, new_end,
				     flags, funcs, arg, enc);
		GLOB_FREE(buf);
		GLOB_FREE(new_beg);
		if (status) break;
	    }
	}

	GLOB_FREE(copy_beg);
    }

    return status;
}

static int
push_caller(const char *path, VALUE val, void *enc)
{
    struct push_glob_args *arg = (struct push_glob_args *)val;
    struct glob_pattern *list;
    int status;

    list = glob_make_pattern(path, path + strlen(path), arg->flags, enc);
    if (!list) {
	return -1;
    }
    status = glob_helper(arg->fd, arg->path, arg->baselen, arg->namelen, arg->dirsep,
			 arg->pathtype, &list, &list + 1, arg->flags, arg->funcs,
			 arg->arg, enc);
    glob_free_pattern(list);
    return status;
}

static int ruby_glob0(const char *path, int fd, const char *base, int flags,
                      const ruby_glob_funcs_t *funcs, VALUE arg, rb_encoding *enc);

struct push_glob0_args {
    int fd;
    const char *base;
    int flags;
    const ruby_glob_funcs_t *funcs;
    VALUE arg;
};

static int
push_glob0_caller(const char *path, VALUE val, void *enc)
{
    struct push_glob0_args *arg = (struct push_glob0_args *)val;
    return ruby_glob0(path, arg->fd, arg->base, arg->flags, arg->funcs, arg->arg, enc);
}

static int
ruby_glob0(const char *path, int fd, const char *base, int flags,
	   const ruby_glob_funcs_t *funcs, VALUE arg,
	   rb_encoding *enc)
{
    struct glob_pattern *list;
    const char *root, *start;
    char *buf;
    size_t n, baselen = 0;
    int status, dirsep = FALSE;

    start = root = path;

    if (*root == '{') {
        struct push_glob0_args args;
        args.fd = fd;
        args.base = base;
        args.flags = flags;
        args.funcs = funcs;
        args.arg = arg;
        return ruby_brace_expand(path, flags, push_glob0_caller, (VALUE)&args, enc, Qfalse);
    }

    flags |= FNM_SYSCASE;
#if defined DOSISH
    root = rb_enc_path_skip_prefix(root, root + strlen(root), enc);
#endif

    if (*root == '/') root++;

    n = root - start;
    if (!n && base) {
	n = strlen(base);
	baselen = n;
	start = base;
	dirsep = TRUE;
    }
    buf = GLOB_ALLOC_N(char, n + 1);
    if (!buf) return -1;
    MEMCPY(buf, start, char, n);
    buf[n] = '\0';

    list = glob_make_pattern(root, root + strlen(root), flags, enc);
    if (!list) {
	GLOB_FREE(buf);
	return -1;
    }
    status = glob_helper(fd, buf, baselen, n-baselen, dirsep,
			 path_unknown, &list, &list + 1,
			 flags, funcs, arg, enc);
    glob_free_pattern(list);
    GLOB_FREE(buf);

    return status;
}

int
ruby_glob(const char *path, int flags, ruby_glob_func *func, VALUE arg)
{
    ruby_glob_funcs_t funcs;
    funcs.match = func;
    funcs.error = NULL;
    return ruby_glob0(path, AT_FDCWD, 0, flags & ~GLOB_VERBOSE,
		      &funcs, arg, rb_ascii8bit_encoding());
}

static int
rb_glob_caller(const char *path, VALUE a, void *enc)
{
    int status;
    struct glob_args *args = (struct glob_args *)a;

    args->path = path;
    rb_protect(glob_func_caller, a, &status);
    return status;
}

static const ruby_glob_funcs_t rb_glob_funcs = {
    rb_glob_caller, rb_glob_error,
};

void
rb_glob(const char *path, void (*func)(const char *, VALUE, void *), VALUE arg)
{
    struct glob_args args;
    int status;

    args.func = func;
    args.value = arg;
    args.enc = rb_ascii8bit_encoding();

    status = ruby_glob0(path, AT_FDCWD, 0, GLOB_VERBOSE, &rb_glob_funcs,
			(VALUE)&args, args.enc);
    if (status) GLOB_JUMP_TAG(status);
}

static void
push_pattern(const char *path, VALUE ary, void *enc)
{
#if defined _WIN32 || defined __APPLE__
    VALUE name = rb_utf8_str_new_cstr(path);
    rb_encoding *eenc = rb_default_internal_encoding();
    name = rb_str_conv_enc(name, NULL, eenc ? eenc : enc);
#else
    VALUE name = rb_external_str_new_with_enc(path, strlen(path), enc);
#endif
    rb_ary_push(ary, name);
}

static int
ruby_brace_expand(const char *str, int flags, ruby_glob_func *func, VALUE arg,
		  rb_encoding *enc, VALUE var)
{
    const int escape = !(flags & FNM_NOESCAPE);
    const char *p = str;
    const char *pend = p + strlen(p);
    const char *s = p;
    const char *lbrace = 0, *rbrace = 0;
    int nest = 0, status = 0;

    while (*p) {
	if (*p == '{' && nest++ == 0) {
	    lbrace = p;
	}
	if (*p == '}' && lbrace && --nest == 0) {
	    rbrace = p;
	    break;
	}
	if (*p == '\\' && escape) {
	    if (!*++p) break;
	}
	Inc(p, pend, enc);
    }

    if (lbrace && rbrace) {
	size_t len = strlen(s) + 1;
	char *buf = GLOB_ALLOC_N(char, len);
	long shift;

	if (!buf) return -1;
	memcpy(buf, s, lbrace-s);
	shift = (lbrace-s);
	p = lbrace;
	while (p < rbrace) {
	    const char *t = ++p;
	    nest = 0;
	    while (p < rbrace && !(*p == ',' && nest == 0)) {
		if (*p == '{') nest++;
		if (*p == '}') nest--;
		if (*p == '\\' && escape) {
		    if (++p == rbrace) break;
		}
		Inc(p, pend, enc);
	    }
	    memcpy(buf+shift, t, p-t);
	    strlcpy(buf+shift+(p-t), rbrace+1, len-(shift+(p-t)));
	    status = ruby_brace_expand(buf, flags, func, arg, enc, var);
	    if (status) break;
	}
	GLOB_FREE(buf);
    }
    else if (!lbrace && !rbrace) {
	status = glob_call_func(func, s, arg, enc);
    }

    RB_GC_GUARD(var);
    return status;
}

struct brace_args {
    ruby_glob_funcs_t funcs;
    VALUE value;
    int flags;
};

static int
glob_brace(const char *path, VALUE val, void *enc)
{
    struct brace_args *arg = (struct brace_args *)val;

    return ruby_glob0(path, AT_FDCWD, 0, arg->flags, &arg->funcs, arg->value, enc);
}

int
ruby_brace_glob_with_enc(const char *str, int flags, ruby_glob_func *func, VALUE arg, rb_encoding *enc)
{
    struct brace_args args;

    flags &= ~GLOB_VERBOSE;
    args.funcs.match = func;
    args.funcs.error = NULL;
    args.value = arg;
    args.flags = flags;
    return ruby_brace_expand(str, flags, glob_brace, (VALUE)&args, enc, Qfalse);
}

int
ruby_brace_glob(const char *str, int flags, ruby_glob_func *func, VALUE arg)
{
    return ruby_brace_glob_with_enc(str, flags, func, arg, rb_ascii8bit_encoding());
}

static int
push_glob(VALUE ary, VALUE str, VALUE base, int flags)
{
    struct glob_args args;
    int fd;
    rb_encoding *enc = rb_enc_get(str);

#if defined _WIN32 || defined __APPLE__
    str = rb_str_encode_ospath(str);
#endif
    if (rb_enc_to_index(enc) == ENCINDEX_US_ASCII)
	enc = rb_filesystem_encoding();
    if (rb_enc_to_index(enc) == ENCINDEX_US_ASCII)
	enc = rb_ascii8bit_encoding();
    flags |= GLOB_VERBOSE;
    args.func = push_pattern;
    args.value = ary;
    args.enc = enc;
    args.base = 0;
    fd = AT_FDCWD;
    if (!NIL_P(base)) {
	if (!RB_TYPE_P(base, T_STRING) || !rb_enc_check(str, base)) {
	    struct dir_data *dirp = DATA_PTR(base);
	    if (!dirp->dir) dir_closed();
#ifdef HAVE_DIRFD
	    if ((fd = dirfd(dirp->dir)) == -1)
		rb_sys_fail_path(dir_inspect(base));
#endif
	    base = dirp->path;
	}
	args.base = RSTRING_PTR(base);
    }
#if defined _WIN32 || defined __APPLE__
    enc = rb_utf8_encoding();
#endif

    return ruby_glob0(RSTRING_PTR(str), fd, args.base, flags, &rb_glob_funcs,
		      (VALUE)&args, enc);
}

static VALUE
rb_push_glob(VALUE str, VALUE base, int flags) /* '\0' is delimiter */
{
    VALUE ary;
    int status;

    /* can contain null bytes as separators */
    if (!RB_TYPE_P(str, T_STRING)) {
	FilePathValue(str);
    }
    else if (!rb_str_to_cstr(str)) {
        rb_raise(rb_eArgError, "nul-separated glob pattern is deprecated");
    }
    else {
	rb_enc_check(str, rb_enc_from_encoding(rb_usascii_encoding()));
    }
    ary = rb_ary_new();

    status = push_glob(ary, str, base, flags);
    if (status) GLOB_JUMP_TAG(status);

    return ary;
}

static VALUE
dir_globs(long argc, const VALUE *argv, VALUE base, int flags)
{
    VALUE ary = rb_ary_new();
    long i;

    for (i = 0; i < argc; ++i) {
	int status;
	VALUE str = argv[i];
	FilePathValue(str);
	status = push_glob(ary, str, base, flags);
	if (status) GLOB_JUMP_TAG(status);
    }

    return ary;
}

static void
dir_glob_options(VALUE opt, VALUE *base, int *flags)
{
    ID kw[2];
    VALUE args[2];
    kw[0] = rb_intern("base");
    if (flags) kw[1] = rb_intern("flags");
    rb_get_kwargs(opt, kw, 0, flags ? 2 : 1, args);
    if (args[0] == Qundef || NIL_P(args[0])) {
	*base = Qnil;
    }
#if USE_OPENDIR_AT
    else if (rb_typeddata_is_kind_of(args[0], &dir_data_type)) {
	*base = args[0];
    }
#endif
    else {
	FilePathValue(args[0]);
	if (!RSTRING_LEN(args[0])) args[0] = Qnil;
	*base = args[0];
    }
    if (flags && args[1] != Qundef) {
	*flags = NUM2INT(args[1]);
    }
}

/*
 *  call-seq:
 *     Dir[ string [, string ...] [, base: path] ] -> array
 *
 *  Equivalent to calling
 *  <code>Dir.glob([</code><i>string,...</i><code>], 0)</code>.
 *
 */
static VALUE
dir_s_aref(int argc, VALUE *argv, VALUE obj)
{
    VALUE opts, base;
    argc = rb_scan_args(argc, argv, "*:", NULL, &opts);
    dir_glob_options(opts, &base, NULL);
    if (argc == 1) {
	return rb_push_glob(argv[0], base, 0);
    }
    return dir_globs(argc, argv, base, 0);
}

/*
 *  call-seq:
 *     Dir.glob( pattern, [flags], [base: path] )                       -> array
 *     Dir.glob( pattern, [flags], [base: path] ) { |filename| block }  -> nil
 *
 *  Expands +pattern+, which is a pattern string or an Array of pattern
 *  strings, and returns an array containing the matching filenames.
 *  If a block is given, calls the block once for each matching filename,
 *  passing the filename as a parameter to the block.
 *
 *  The optional +base+ keyword argument specifies the base directory for
 *  interpreting relative pathnames instead of the current working directory.
 *  As the results are not prefixed with the base directory name in this
 *  case, you will need to prepend the base directory name if you want real
 *  paths.
 *
 *  Note that the pattern is not a regexp, it's closer to a shell glob.
 *  See File::fnmatch for the meaning of the +flags+ parameter.
 *  Case sensitivity depends on your system (File::FNM_CASEFOLD is ignored),
 *  as does the order in which the results are returned.
 *
 *  <code>*</code>::
 *    Matches any file. Can be restricted by other values in the glob.
 *    Equivalent to <code>/ .* /mx</code> in regexp.
 *
 *    <code>*</code>::     Matches all files
 *    <code>c*</code>::    Matches all files beginning with <code>c</code>
 *    <code>*c</code>::    Matches all files ending with <code>c</code>
 *    <code>\*c\*</code>:: Match all files that have <code>c</code> in them
 *                         (including at the beginning or end).
 *
 *    Note, this will not match Unix-like hidden files (dotfiles).  In order
 *    to include those in the match results, you must use the
 *    File::FNM_DOTMATCH flag or something like <code>"{*,.*}"</code>.
 *
 *  <code>**</code>::
 *    Matches directories recursively.
 *
 *  <code>?</code>::
 *    Matches any one character. Equivalent to <code>/.{1}/</code> in regexp.
 *
 *  <code>[set]</code>::
 *    Matches any one character in +set+.  Behaves exactly like character sets
 *    in Regexp, including set negation (<code>[^a-z]</code>).
 *
 *  <code>{p,q}</code>::
 *    Matches either literal <code>p</code> or literal <code>q</code>.
 *    Equivalent to pattern alternation in regexp.
 *
 *    Matching literals may be more than one character in length.  More than
 *    two literals may be specified.
 *
 *  <code> \\ </code>::
 *    Escapes the next metacharacter.
 *
 *    Note that this means you cannot use backslash on windows as part of a
 *    glob, i.e.  <code>Dir["c:\\foo*"]</code> will not work, use
 *    <code>Dir["c:/foo*"]</code> instead.
 *
 *  Examples:
 *
 *     Dir["config.?"]                     #=> ["config.h"]
 *     Dir.glob("config.?")                #=> ["config.h"]
 *     Dir.glob("*.[a-z][a-z]")            #=> ["main.rb"]
 *     Dir.glob("*.[^r]*")                 #=> ["config.h"]
 *     Dir.glob("*.{rb,h}")                #=> ["main.rb", "config.h"]
 *     Dir.glob("*")                       #=> ["config.h", "main.rb"]
 *     Dir.glob("*", File::FNM_DOTMATCH)   #=> [".", "..", "config.h", "main.rb"]
 *     Dir.glob(["*.rb", "*.h"])           #=> ["main.rb", "config.h"]
 *
 *     rbfiles = File.join("**", "*.rb")
 *     Dir.glob(rbfiles)                   #=> ["main.rb",
 *                                         #    "lib/song.rb",
 *                                         #    "lib/song/karaoke.rb"]
 *
 *     Dir.glob(rbfiles, base: "lib")      #=> ["song.rb",
 *                                         #    "song/karaoke.rb"]
 *
 *     libdirs = File.join("**", "lib")
 *     Dir.glob(libdirs)                   #=> ["lib"]
 *
 *     librbfiles = File.join("**", "lib", "**", "*.rb")
 *     Dir.glob(librbfiles)                #=> ["lib/song.rb",
 *                                         #    "lib/song/karaoke.rb"]
 *
 *     librbfiles = File.join("**", "lib", "*.rb")
 *     Dir.glob(librbfiles)                #=> ["lib/song.rb"]
 */
static VALUE
dir_s_glob(int argc, VALUE *argv, VALUE obj)
{
    VALUE str, rflags, ary, opts, base;
    int flags;

    argc = rb_scan_args(argc, argv, "11:", &str, &rflags, &opts);
    if (argc == 2)
	flags = NUM2INT(rflags);
    else
	flags = 0;
    dir_glob_options(opts, &base, &flags);

    ary = rb_check_array_type(str);
    if (NIL_P(ary)) {
	ary = rb_push_glob(str, base, flags);
    }
    else {
	VALUE v = ary;
	ary = dir_globs(RARRAY_LEN(v), RARRAY_CONST_PTR(v), base, flags);
	RB_GC_GUARD(v);
    }

    if (rb_block_given_p()) {
	rb_ary_each(ary);
	return Qnil;
    }
    return ary;
}

static VALUE
dir_open_dir(int argc, VALUE *argv)
{
    VALUE dir = rb_funcallv_kw(rb_cDir, rb_intern("open"), argc, argv, RB_PASS_CALLED_KEYWORDS);

    rb_check_typeddata(dir, &dir_data_type);
    return dir;
}


/*
 *  call-seq:
 *     Dir.foreach( dirname ) {| filename | block }                 -> nil
 *     Dir.foreach( dirname, encoding: enc ) {| filename | block }  -> nil
 *     Dir.foreach( dirname )                                       -> an_enumerator
 *     Dir.foreach( dirname, encoding: enc )                        -> an_enumerator
 *
 *  Calls the block once for each entry in the named directory, passing
 *  the filename of each entry as a parameter to the block.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     Dir.foreach("testdir") {|x| puts "Got #{x}" }
 *
 *  <em>produces:</em>
 *
 *     Got .
 *     Got ..
 *     Got config.h
 *     Got main.rb
 *
 */
static VALUE
dir_foreach(int argc, VALUE *argv, VALUE io)
{
    VALUE dir;

    RETURN_ENUMERATOR(io, argc, argv);
    dir = dir_open_dir(argc, argv);
    rb_ensure(dir_each, dir, dir_close, dir);
    return Qnil;
}

static VALUE
dir_collect(VALUE dir)
{
    VALUE ary = rb_ary_new();
    dir_each_entry(dir, rb_ary_push, ary, FALSE);
    return ary;
}

/*
 *  call-seq:
 *     Dir.entries( dirname )                -> array
 *     Dir.entries( dirname, encoding: enc ) -> array
 *
 *  Returns an array containing all of the filenames in the given
 *  directory. Will raise a SystemCallError if the named directory
 *  doesn't exist.
 *
 *  The optional <i>encoding</i> keyword argument specifies the encoding of the
 *  directory. If not specified, the filesystem encoding is used.
 *
 *     Dir.entries("testdir")   #=> [".", "..", "config.h", "main.rb"]
 *
 */
static VALUE
dir_entries(int argc, VALUE *argv, VALUE io)
{
    VALUE dir;

    dir = dir_open_dir(argc, argv);
    return rb_ensure(dir_collect, dir, dir_close, dir);
}

static VALUE
dir_each_child(VALUE dir)
{
    return dir_each_entry(dir, dir_yield, Qnil, TRUE);
}

/*
 *  call-seq:
 *     Dir.each_child( dirname ) {| filename | block }                 -> nil
 *     Dir.each_child( dirname, encoding: enc ) {| filename | block }  -> nil
 *     Dir.each_child( dirname )                                       -> an_enumerator
 *     Dir.each_child( dirname, encoding: enc )                        -> an_enumerator
 *
 *  Calls the block once for each entry except for "." and ".." in the
 *  named directory, passing the filename of each entry as a parameter
 *  to the block.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     Dir.each_child("testdir") {|x| puts "Got #{x}" }
 *
 *  <em>produces:</em>
 *
 *     Got config.h
 *     Got main.rb
 *
 */
static VALUE
dir_s_each_child(int argc, VALUE *argv, VALUE io)
{
    VALUE dir;

    RETURN_ENUMERATOR(io, argc, argv);
    dir = dir_open_dir(argc, argv);
    rb_ensure(dir_each_child, dir, dir_close, dir);
    return Qnil;
}

/*
 *  call-seq:
 *     dir.each_child {| filename | block }  -> nil
 *     dir.each_child                        -> an_enumerator
 *
 *  Calls the block once for each entry except for "." and ".." in
 *  this directory, passing the filename of each entry as a parameter
 *  to the block.
 *
 *  If no block is given, an enumerator is returned instead.
 *
 *     d = Dir.new("testdir")
 *     d.each_child  {|x| puts "Got #{x}" }
 *
 *  <em>produces:</em>
 *
 *     Got config.h
 *     Got main.rb
 *
 */
static VALUE
dir_each_child_m(VALUE dir)
{
    RETURN_ENUMERATOR(dir, 0, 0);
    return dir_each_entry(dir, dir_yield, Qnil, TRUE);
}

/*
 *  call-seq:
 *     dir.children  -> array
 *
 *  Returns an array containing all of the filenames except for "."
 *  and ".." in this directory.
 *
 *     d = Dir.new("testdir")
 *     d.children   #=> ["config.h", "main.rb"]
 *
 */
static VALUE
dir_collect_children(VALUE dir)
{
    VALUE ary = rb_ary_new();
    dir_each_entry(dir, rb_ary_push, ary, TRUE);
    return ary;
}

/*
 *  call-seq:
 *     Dir.children( dirname )                -> array
 *     Dir.children( dirname, encoding: enc ) -> array
 *
 *  Returns an array containing all of the filenames except for "."
 *  and ".." in the given directory. Will raise a SystemCallError if
 *  the named directory doesn't exist.
 *
 *  The optional <i>encoding</i> keyword argument specifies the encoding of the
 *  directory. If not specified, the filesystem encoding is used.
 *
 *     Dir.children("testdir")   #=> ["config.h", "main.rb"]
 *
 */
static VALUE
dir_s_children(int argc, VALUE *argv, VALUE io)
{
    VALUE dir;

    dir = dir_open_dir(argc, argv);
    return rb_ensure(dir_collect_children, dir, dir_close, dir);
}

static int
fnmatch_brace(const char *pattern, VALUE val, void *enc)
{
    struct brace_args *arg = (struct brace_args *)val;
    VALUE path = arg->value;
    rb_encoding *enc_pattern = enc;
    rb_encoding *enc_path = rb_enc_get(path);

    if (enc_pattern != enc_path) {
	if (!rb_enc_asciicompat(enc_pattern))
	    return FNM_NOMATCH;
	if (!rb_enc_asciicompat(enc_path))
	    return FNM_NOMATCH;
	if (!rb_enc_str_asciionly_p(path)) {
	    int cr = ENC_CODERANGE_7BIT;
	    long len = strlen(pattern);
	    if (rb_str_coderange_scan_restartable(pattern, pattern + len,
						  enc_pattern, &cr) != len)
		return FNM_NOMATCH;
	    if (cr != ENC_CODERANGE_7BIT)
		return FNM_NOMATCH;
	}
    }
    return (fnmatch(pattern, enc, RSTRING_PTR(path), arg->flags) == 0);
}

/*
 *  call-seq:
 *     File.fnmatch( pattern, path, [flags] ) -> (true or false)
 *     File.fnmatch?( pattern, path, [flags] ) -> (true or false)
 *
 *  Returns true if +path+ matches against +pattern+.  The pattern is not a
 *  regular expression; instead it follows rules similar to shell filename
 *  globbing.  It may contain the following metacharacters:
 *
 *  <code>*</code>::
 *    Matches any file. Can be restricted by other values in the glob.
 *    Equivalent to <code>/ .* /x</code> in regexp.
 *
 *    <code>*</code>::    Matches all files regular files
 *    <code>c*</code>::   Matches all files beginning with <code>c</code>
 *    <code>*c</code>::   Matches all files ending with <code>c</code>
 *    <code>\*c*</code>:: Matches all files that have <code>c</code> in them
 *                        (including at the beginning or end).
 *
 *    To match hidden files (that start with a <code>.</code> set the
 *    File::FNM_DOTMATCH flag.
 *
 *  <code>**</code>::
 *    Matches directories recursively or files expansively.
 *
 *  <code>?</code>::
 *    Matches any one character. Equivalent to <code>/.{1}/</code> in regexp.
 *
 *  <code>[set]</code>::
 *    Matches any one character in +set+.  Behaves exactly like character sets
 *    in Regexp, including set negation (<code>[^a-z]</code>).
 *
 *  <code> \ </code>::
 *    Escapes the next metacharacter.
 *
 *  <code>{a,b}</code>::
 *    Matches pattern a and pattern b if File::FNM_EXTGLOB flag is enabled.
 *    Behaves like a Regexp union (<code>(?:a|b)</code>).
 *
 *  +flags+ is a bitwise OR of the <code>FNM_XXX</code> constants. The same
 *  glob pattern and flags are used by Dir::glob.
 *
 *  Examples:
 *
 *     File.fnmatch('cat',       'cat')        #=> true  # match entire string
 *     File.fnmatch('cat',       'category')   #=> false # only match partial string
 *
 *     File.fnmatch('c{at,ub}s', 'cats')                    #=> false # { } isn't supported by default
 *     File.fnmatch('c{at,ub}s', 'cats', File::FNM_EXTGLOB) #=> true  # { } is supported on FNM_EXTGLOB
 *
 *     File.fnmatch('c?t',     'cat')          #=> true  # '?' match only 1 character
 *     File.fnmatch('c??t',    'cat')          #=> false # ditto
 *     File.fnmatch('c*',      'cats')         #=> true  # '*' match 0 or more characters
 *     File.fnmatch('c*t',     'c/a/b/t')      #=> true  # ditto
 *     File.fnmatch('ca[a-z]', 'cat')          #=> true  # inclusive bracket expression
 *     File.fnmatch('ca[^t]',  'cat')          #=> false # exclusive bracket expression ('^' or '!')
 *
 *     File.fnmatch('cat', 'CAT')                     #=> false # case sensitive
 *     File.fnmatch('cat', 'CAT', File::FNM_CASEFOLD) #=> true  # case insensitive
 *     File.fnmatch('cat', 'CAT', File::FNM_SYSCASE)  #=> true or false # depends on the system default
 *
 *     File.fnmatch('?',   '/', File::FNM_PATHNAME)  #=> false # wildcard doesn't match '/' on FNM_PATHNAME
 *     File.fnmatch('*',   '/', File::FNM_PATHNAME)  #=> false # ditto
 *     File.fnmatch('[/]', '/', File::FNM_PATHNAME)  #=> false # ditto
 *
 *     File.fnmatch('\?',   '?')                       #=> true  # escaped wildcard becomes ordinary
 *     File.fnmatch('\a',   'a')                       #=> true  # escaped ordinary remains ordinary
 *     File.fnmatch('\a',   '\a', File::FNM_NOESCAPE)  #=> true  # FNM_NOESCAPE makes '\' ordinary
 *     File.fnmatch('[\?]', '?')                       #=> true  # can escape inside bracket expression
 *
 *     File.fnmatch('*',   '.profile')                      #=> false # wildcard doesn't match leading
 *     File.fnmatch('*',   '.profile', File::FNM_DOTMATCH)  #=> true  # period by default.
 *     File.fnmatch('.*',  '.profile')                      #=> true
 *
 *     rbfiles = '**' '/' '*.rb' # you don't have to do like this. just write in single string.
 *     File.fnmatch(rbfiles, 'main.rb')                    #=> false
 *     File.fnmatch(rbfiles, './main.rb')                  #=> false
 *     File.fnmatch(rbfiles, 'lib/song.rb')                #=> true
 *     File.fnmatch('**.rb', 'main.rb')                    #=> true
 *     File.fnmatch('**.rb', './main.rb')                  #=> false
 *     File.fnmatch('**.rb', 'lib/song.rb')                #=> true
 *     File.fnmatch('*',           'dave/.profile')                      #=> true
 *
 *     pattern = '*' '/' '*'
 *     File.fnmatch(pattern, 'dave/.profile', File::FNM_PATHNAME)  #=> false
 *     File.fnmatch(pattern, 'dave/.profile', File::FNM_PATHNAME | File::FNM_DOTMATCH) #=> true
 *
 *     pattern = '**' '/' 'foo'
 *     File.fnmatch(pattern, 'a/b/c/foo', File::FNM_PATHNAME)     #=> true
 *     File.fnmatch(pattern, '/a/b/c/foo', File::FNM_PATHNAME)    #=> true
 *     File.fnmatch(pattern, 'c:/a/b/c/foo', File::FNM_PATHNAME)  #=> true
 *     File.fnmatch(pattern, 'a/.b/c/foo', File::FNM_PATHNAME)    #=> false
 *     File.fnmatch(pattern, 'a/.b/c/foo', File::FNM_PATHNAME | File::FNM_DOTMATCH) #=> true
 */
static VALUE
file_s_fnmatch(int argc, VALUE *argv, VALUE obj)
{
    VALUE pattern, path;
    VALUE rflags;
    int flags;

    if (rb_scan_args(argc, argv, "21", &pattern, &path, &rflags) == 3)
	flags = NUM2INT(rflags);
    else
	flags = 0;

    StringValueCStr(pattern);
    FilePathStringValue(path);

    if (flags & FNM_EXTGLOB) {
	struct brace_args args;

	args.value = path;
	args.flags = flags;
	if (ruby_brace_expand(RSTRING_PTR(pattern), flags, fnmatch_brace,
			      (VALUE)&args, rb_enc_get(pattern), pattern) > 0)
	    return Qtrue;
    }
    else {
	rb_encoding *enc = rb_enc_compatible(pattern, path);
	if (!enc) return Qfalse;
	if (fnmatch(RSTRING_PTR(pattern), enc, RSTRING_PTR(path), flags) == 0)
	    return Qtrue;
    }
    RB_GC_GUARD(pattern);

    return Qfalse;
}

/*
 *  call-seq:
 *    Dir.home()       -> "/home/me"
 *    Dir.home("root") -> "/root"
 *
 *  Returns the home directory of the current user or the named user
 *  if given.
 */
static VALUE
dir_s_home(int argc, VALUE *argv, VALUE obj)
{
    VALUE user;
    const char *u = 0;

    rb_check_arity(argc, 0, 1);
    user = (argc > 0) ? argv[0] : Qnil;
    if (!NIL_P(user)) {
	SafeStringValue(user);
	rb_must_asciicompat(user);
	u = StringValueCStr(user);
	if (*u) {
	    return rb_home_dir_of(user, rb_str_new(0, 0));
	}
    }
    return rb_default_home_dir(rb_str_new(0, 0));

}

#if 0
/*
 * call-seq:
 *   Dir.exist?(file_name)   ->  true or false
 *
 * Returns <code>true</code> if the named file is a directory,
 * <code>false</code> otherwise.
 *
 */
VALUE
rb_file_directory_p(void)
{
}
#endif

/*
 * call-seq:
 *   Dir.exists?(file_name)  ->  true or false
 *
 * Deprecated method. Don't use.
 */
static VALUE
rb_dir_exists_p(VALUE obj, VALUE fname)
{
    rb_warning("Dir.exists? is a deprecated name, use Dir.exist? instead");
    return rb_file_directory_p(obj, fname);
}

static void *
nogvl_dir_empty_p(void *ptr)
{
    const char *path = ptr;
    DIR *dir = opendir(path);
    struct dirent *dp;
    VALUE result = Qtrue;

    if (!dir) {
	int e = errno;
	switch (gc_for_fd_with_gvl(e)) {
	  default:
	    dir = opendir(path);
	    if (dir) break;
	    e = errno;
	    /* fall through */
	  case 0:
	    if (e == ENOTDIR) return (void *)Qfalse;
	    errno = e; /* for rb_sys_fail_path */
	    return (void *)Qundef;
	}
    }
    while ((dp = READDIR(dir, NULL)) != NULL) {
	if (!to_be_skipped(dp)) {
	    result = Qfalse;
	    break;
	}
    }
    closedir(dir);
    return (void *)result;
}

/*
 * call-seq:
 *   Dir.empty?(path_name)  ->  true or false
 *
 * Returns <code>true</code> if the named file is an empty directory,
 * <code>false</code> if it is not a directory or non-empty.
 */
static VALUE
rb_dir_s_empty_p(VALUE obj, VALUE dirname)
{
    VALUE result, orig;
    const char *path;
    enum {false_on_notdir = 1};

    FilePathValue(dirname);
    orig = rb_str_dup_frozen(dirname);
    dirname = rb_str_encode_ospath(dirname);
    dirname = rb_str_dup_frozen(dirname);
    path = RSTRING_PTR(dirname);

#if defined HAVE_GETATTRLIST && defined ATTR_DIR_ENTRYCOUNT
    {
	u_int32_t attrbuf[SIZEUP32(fsobj_tag_t)];
	struct attrlist al = {ATTR_BIT_MAP_COUNT, 0, ATTR_CMN_OBJTAG,};
	if (getattrlist(path, &al, attrbuf, sizeof(attrbuf), 0) != 0)
	    rb_sys_fail_path(orig);
	if (*(const fsobj_tag_t *)(attrbuf+1) == VT_HFS) {
	    al.commonattr = 0;
	    al.dirattr = ATTR_DIR_ENTRYCOUNT;
	    if (getattrlist(path, &al, attrbuf, sizeof(attrbuf), 0) == 0) {
		if (attrbuf[0] >= 2 * sizeof(u_int32_t))
		    return attrbuf[1] ? Qfalse : Qtrue;
		if (false_on_notdir) return Qfalse;
	    }
	    rb_sys_fail_path(orig);
	}
    }
#endif

    result = (VALUE)rb_thread_call_without_gvl(nogvl_dir_empty_p, (void *)path,
					    RUBY_UBF_IO, 0);
    if (result == Qundef) {
	rb_sys_fail_path(orig);
    }
    return result;
}

/*
 *  Objects of class Dir are directory streams representing
 *  directories in the underlying file system. They provide a variety
 *  of ways to list directories and their contents. See also File.
 *
 *  The directory used in these examples contains the two regular files
 *  (<code>config.h</code> and <code>main.rb</code>), the parent
 *  directory (<code>..</code>), and the directory itself
 *  (<code>.</code>).
 */
void
Init_Dir(void)
{
    rb_cDir = rb_define_class("Dir", rb_cObject);

    rb_include_module(rb_cDir, rb_mEnumerable);

    rb_define_alloc_func(rb_cDir, dir_s_alloc);
    rb_define_singleton_method(rb_cDir, "open", dir_s_open, -1);
    rb_define_singleton_method(rb_cDir, "foreach", dir_foreach, -1);
    rb_define_singleton_method(rb_cDir, "entries", dir_entries, -1);
    rb_define_singleton_method(rb_cDir, "each_child", dir_s_each_child, -1);
    rb_define_singleton_method(rb_cDir, "children", dir_s_children, -1);

    rb_define_method(rb_cDir,"initialize", dir_initialize, -1);
    rb_define_method(rb_cDir,"fileno", dir_fileno, 0);
    rb_define_method(rb_cDir,"path", dir_path, 0);
    rb_define_method(rb_cDir,"to_path", dir_path, 0);
    rb_define_method(rb_cDir,"inspect", dir_inspect, 0);
    rb_define_method(rb_cDir,"read", dir_read, 0);
    rb_define_method(rb_cDir,"each", dir_each, 0);
    rb_define_method(rb_cDir,"each_child", dir_each_child_m, 0);
    rb_define_method(rb_cDir,"children", dir_collect_children, 0);
    rb_define_method(rb_cDir,"rewind", dir_rewind, 0);
    rb_define_method(rb_cDir,"tell", dir_tell, 0);
    rb_define_method(rb_cDir,"seek", dir_seek, 1);
    rb_define_method(rb_cDir,"pos", dir_tell, 0);
    rb_define_method(rb_cDir,"pos=", dir_set_pos, 1);
    rb_define_method(rb_cDir,"close", dir_close, 0);

    rb_define_singleton_method(rb_cDir,"chdir", dir_s_chdir, -1);
    rb_define_singleton_method(rb_cDir,"getwd", dir_s_getwd, 0);
    rb_define_singleton_method(rb_cDir,"pwd", dir_s_getwd, 0);
    rb_define_singleton_method(rb_cDir,"chroot", dir_s_chroot, 1);
    rb_define_singleton_method(rb_cDir,"mkdir", dir_s_mkdir, -1);
    rb_define_singleton_method(rb_cDir,"rmdir", dir_s_rmdir, 1);
    rb_define_singleton_method(rb_cDir,"delete", dir_s_rmdir, 1);
    rb_define_singleton_method(rb_cDir,"unlink", dir_s_rmdir, 1);
    rb_define_singleton_method(rb_cDir,"home", dir_s_home, -1);

    rb_define_singleton_method(rb_cDir,"glob", dir_s_glob, -1);
    rb_define_singleton_method(rb_cDir,"[]", dir_s_aref, -1);
    rb_define_singleton_method(rb_cDir,"exist?", rb_file_directory_p, 1);
    rb_define_singleton_method(rb_cDir,"exists?", rb_dir_exists_p, 1);
    rb_define_singleton_method(rb_cDir,"empty?", rb_dir_s_empty_p, 1);

    rb_define_singleton_method(rb_cFile,"fnmatch", file_s_fnmatch, -1);
    rb_define_singleton_method(rb_cFile,"fnmatch?", file_s_fnmatch, -1);

    /*  Document-const: File::Constants::FNM_NOESCAPE
     *
     *  Disables escapes in File.fnmatch and Dir.glob patterns
     */
    rb_file_const("FNM_NOESCAPE", INT2FIX(FNM_NOESCAPE));

    /*  Document-const: File::Constants::FNM_PATHNAME
     *
     *  Wildcards in File.fnmatch and Dir.glob patterns do not match directory
     *  separators
     */
    rb_file_const("FNM_PATHNAME", INT2FIX(FNM_PATHNAME));

    /*  Document-const: File::Constants::FNM_DOTMATCH
     *
     *  The '*' wildcard matches filenames starting with "." in File.fnmatch
     *  and Dir.glob patterns
     */
    rb_file_const("FNM_DOTMATCH", INT2FIX(FNM_DOTMATCH));

    /*  Document-const: File::Constants::FNM_CASEFOLD
     *
     *  Makes File.fnmatch patterns case insensitive (but not Dir.glob
     *  patterns).
     */
    rb_file_const("FNM_CASEFOLD", INT2FIX(FNM_CASEFOLD));

    /*  Document-const: File::Constants::FNM_EXTGLOB
     *
     *  Allows file globbing through "{a,b}" in File.fnmatch patterns.
     */
    rb_file_const("FNM_EXTGLOB", INT2FIX(FNM_EXTGLOB));

    /*  Document-const: File::Constants::FNM_SYSCASE
     *
     *  System default case insensitiveness, equals to FNM_CASEFOLD or
     *  0.
     */
    rb_file_const("FNM_SYSCASE", INT2FIX(FNM_SYSCASE));

    /*  Document-const: File::Constants::FNM_SHORTNAME
     *
     *  Makes patterns to match short names if existing.  Valid only
     *  on Microsoft Windows.
     */
    rb_file_const("FNM_SHORTNAME", INT2FIX(FNM_SHORTNAME));
}
