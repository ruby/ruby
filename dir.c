/**********************************************************************

  dir.c -

  $Author$
  $Date$
  created at: Wed Jan  5 09:51:01 JST 1994

  Copyright (C) 1993-2003 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby.h"

#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#if defined HAVE_DIRENT_H && !defined _WIN32
# include <dirent.h>
# define NAMLEN(dirent) strlen((dirent)->d_name)
#elif defined HAVE_DIRECT_H && !defined _WIN32
# include <direct.h>
# define NAMLEN(dirent) strlen((dirent)->d_name)
#else
# define dirent direct
# if !defined __NeXT__
#  define NAMLEN(dirent) (dirent)->d_namlen
# else
#  /* On some versions of NextStep, d_namlen is always zero, so avoid it. */
#  define NAMLEN(dirent) strlen((dirent)->d_name)
# endif
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
char *strchr _((char*,char));
#endif

#include <ctype.h>

#include "util.h"

#ifndef HAVE_LSTAT
#define lstat(path,st) stat(path,st)
#endif

#define FNM_NOESCAPE	0x01
#define FNM_PATHNAME	0x02
#define FNM_DOTMATCH	0x04
#define FNM_CASEFOLD	0x08

#define FNM_NOMATCH	1
#define FNM_ERROR	2

#define downcase(c) (nocase && ISUPPER(c) ? tolower(c) : (c))
#define compare(c1, c2) (((unsigned char)(c1)) - ((unsigned char)(c2)))

/* caution: in case *p == '\0'
   Next(p) == p + 1 in single byte environment
   Next(p) == p     in multi byte environment
*/
#if defined(CharNext)
# define Next(p) CharNext(p)
#elif defined(DJGPP)
# define Next(p) ((p) + mblen(p, RUBY_MBCHAR_MAXSIZE))
#elif defined(__EMX__)
# define Next(p) ((p) + emx_mblen(p))
static inline int
emx_mblen(p)
    const char *p;
{
    int n = mblen(p, RUBY_MBCHAR_MAXSIZE);
    return (n < 0) ? 1 : n;
}
#endif

#ifndef Next /* single byte environment */
# define Next(p) ((p) + 1)
# define Inc(p) (++(p))
# define Compare(p1, p2) (compare(downcase(*(p1)), downcase(*(p2))))
#else /* multi byte environment */
# define Inc(p) ((p) = Next(p))
# define Compare(p1, p2) (CompareImpl(p1, p2, nocase))
static int
CompareImpl(p1, p2, nocase)
    const char *p1;
    const char *p2;
    int nocase;
{
    const int len1 = Next(p1) - p1;
    const int len2 = Next(p2) - p2;
#ifdef _WIN32
    char buf1[10], buf2[10]; /* large enough? */
#endif

    if (len1 < 0 || len2 < 0) {
	rb_fatal("CompareImpl: negative len");
    }

    if (len1 == 0) return  len2;
    if (len2 == 0) return -len1;

#ifdef _WIN32
    if (nocase) {
	if (len1 > 1) {
	    if (len1 >= sizeof(buf1)) {
		rb_fatal("CompareImpl: too large len");
	    }
	    memcpy(buf1, p1, len1);
	    buf1[len1] = '\0';
	    CharLower(buf1);
	    p1 = buf1; /* trick */
	}
	if (len2 > 1) {
	    if (len2 >= sizeof(buf2)) {
		rb_fatal("CompareImpl: too large len");
	    }
	    memcpy(buf2, p2, len2);
	    buf2[len2] = '\0';
	    CharLower(buf2);
	    p2 = buf2; /* trick */
	}
    }
#endif
    if (len1 == 1)
	if (len2 == 1)
	    return compare(downcase(*p1), downcase(*p2));
	else {
	    const int ret = compare(downcase(*p1), *p2);
	    return ret ? ret : -1;
	}
    else
	if (len2 == 1) {
	    const int ret = compare(*p1, downcase(*p2));
	    return ret ? ret : 1;
	}
	else {
	    const int ret = memcmp(p1, p2, len1 < len2 ? len1 : len2);
	    return ret ? ret : len1 - len2;
	}
}
#endif /* environment */

static char *
bracket(p, s, flags)
    const char *p; /* pattern (next to '[') */
    const char *s; /* string */
    int flags;
{
    const int nocase = flags & FNM_CASEFOLD;
    const int escape = !(flags & FNM_NOESCAPE);

    int ok = 0, not = 0;

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
	p = Next(t1);
	if (p[0] == '-' && p[1] != ']') {
	    const char *t2 = p + 1;
	    if (escape && *t2 == '\\')
		t2++;
	    if (!*t2)
		return NULL;
	    p = Next(t2);
	    if (!ok && Compare(t1, s) <= 0 && Compare(s, t2) <= 0)
		ok = 1;
	}
	else
	    if (!ok && Compare(t1, s) == 0)
		ok = 1;
    }

    return ok == not ? NULL : (char *)p + 1;
}

/* If FNM_PATHNAME is set, only path element will be matched. (upto '/' or '\0')
   Otherwise, entire string will be matched.
   End marker itself won't be compared.
   And if function succeeds, *pcur reaches end marker.
*/
#define UNESCAPE(p) (escape && *(p) == '\\' ? (p) + 1 : (p))
#define ISEND(p) (!*(p) || (pathname && *(p) == '/'))
#define RETURN(val) return *pcur = p, *scur = s, (val);

static int
fnmatch_helper(pcur, scur, flags)
    const char **pcur; /* pattern */
    const char **scur; /* string */
    int flags;
{
    const int period = !(flags & FNM_DOTMATCH);
    const int pathname = flags & FNM_PATHNAME;
    const int escape = !(flags & FNM_NOESCAPE);
    const int nocase = flags & FNM_CASEFOLD;

    const char *ptmp = 0;
    const char *stmp = 0;

    const char *p = *pcur;
    const char *s = *scur;

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
	    Inc(s);
	    continue;

	  case '[': {
	    const char *t;
	    if (ISEND(s))
		RETURN(FNM_NOMATCH);
	    if (t = bracket(p + 1, s, flags)) {
		p = t;
		Inc(s);
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
	if (Compare(p, s) != 0)
	    goto failed;
	Inc(p);
	Inc(s);
	continue;

      failed: /* try next '*' position */
	if (ptmp && stmp) {
	    p = ptmp;
	    Inc(stmp); /* !ISEND(*stmp) */
	    s = stmp;
	    continue;
	}
	RETURN(FNM_NOMATCH);
    }
}

static int
fnmatch(p, s, flags)
    const char *p; /* pattern */
    const char *s; /* string */
    int flags;
{
    const int period = !(flags & FNM_DOTMATCH);
    const int pathname = flags & FNM_PATHNAME;

    const char *ptmp = 0;
    const char *stmp = 0;

    if (!p) p = "";
    if (!s) s = "";
    if (pathname) {
	while (1) {
	    if (p[0] == '*' && p[1] == '*' && p[2] == '/') {
		do { p += 3; } while (p[0] == '*' && p[1] == '*' && p[2] == '/');
		ptmp = p;
		stmp = s;
	    }
	    if (fnmatch_helper(&p, &s, flags) == 0) {
		while (*s && *s != '/') Inc(s);
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
		while (*stmp && *stmp != '/') Inc(stmp);
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
	return fnmatch_helper(&p, &s, flags);
}

VALUE rb_cDir;

struct dir_data {
    DIR *dir;
    char *path;
};

static void
free_dir(dir)
    struct dir_data *dir;
{
    if (dir) {
	if (dir->dir) closedir(dir->dir);
	if (dir->path) free(dir->path);
    }
    free(dir);
}

static VALUE dir_close _((VALUE));

static VALUE dir_s_alloc _((VALUE));
static VALUE
dir_s_alloc(klass)
    VALUE klass;
{
    struct dir_data *dirp;
    VALUE obj = Data_Make_Struct(klass, struct dir_data, 0, free_dir, dirp);

    dirp->dir = NULL;
    dirp->path = NULL;

    return obj;
}

/*
 *  call-seq:
 *     Dir.new( string ) -> aDir
 *
 *  Returns a new directory object for the named directory.
 */
static VALUE
dir_initialize(dir, dirname)
    VALUE dir, dirname;
{
    struct dir_data *dp;

    FilePathValue(dirname);
    Data_Get_Struct(dir, struct dir_data, dp);
    if (dp->dir) closedir(dp->dir);
    if (dp->path) free(dp->path);
    dp->dir = NULL;
    dp->path = NULL;
    dp->dir = opendir(RSTRING(dirname)->ptr);
    if (dp->dir == NULL) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    dp->dir = opendir(RSTRING(dirname)->ptr);
	}
	if (dp->dir == NULL) {
	    rb_sys_fail(RSTRING(dirname)->ptr);
	}
    }
    dp->path = strdup(RSTRING(dirname)->ptr);

    return dir;
}

/*
 *  call-seq:
 *     Dir.open( string ) => aDir
 *     Dir.open( string ) {| aDir | block } => anObject
 *
 *  With no block, <code>open</code> is a synonym for
 *  <code>Dir::new</code>. If a block is present, it is passed
 *  <i>aDir</i> as a parameter. The directory is closed at the end of
 *  the block, and <code>Dir::open</code> returns the value of the
 *  block.
 */
static VALUE
dir_s_open(klass, dirname)
    VALUE klass, dirname;
{
    struct dir_data *dp;
    VALUE dir = Data_Make_Struct(klass, struct dir_data, 0, free_dir, dp);

    dir_initialize(dir, dirname);
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, dir, dir_close, dir);
    }

    return dir;
}

static void
dir_closed()
{
    rb_raise(rb_eIOError, "closed directory");
}

#define GetDIR(obj, dirp) do {\
    Data_Get_Struct(obj, struct dir_data, dirp);\
    if (dirp->dir == NULL) dir_closed();\
} while (0)

/*
 *  call-seq:
 *     dir.inspect => string
 *
 *  Return a string describing this Dir object.
 */
static VALUE
dir_inspect(dir)
    VALUE dir;
{
    struct dir_data *dirp;

    GetDIR(dir, dirp);
    if (dirp->path) {
	char *c = rb_obj_classname(dir);
	int len = strlen(c) + strlen(dirp->path) + 4;
	VALUE s = rb_str_new(0, len);
	snprintf(RSTRING(s)->ptr, len+1, "#<%s:%s>", c, dirp->path);
	return s;
    }
    return rb_funcall(dir, rb_intern("to_s"), 0, 0);
}

/*
 *  call-seq:
 *     dir.path => string or nil
 *
 *  Returns the path parameter passed to <em>dir</em>'s constructor.
 *
 *     d = Dir.new("..")
 *     d.path   #=> ".."
 */
static VALUE
dir_path(dir)
    VALUE dir;
{
    struct dir_data *dirp;

    GetDIR(dir, dirp);
    if (!dirp->path) return Qnil;
    return rb_str_new2(dirp->path);
}

/*
 *  call-seq:
 *     dir.read => string or nil
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
dir_read(dir)
    VALUE dir;
{
    struct dir_data *dirp;
    struct dirent *dp;

    GetDIR(dir, dirp);
    errno = 0;
    dp = readdir(dirp->dir);
    if (dp) {
	return rb_tainted_str_new(dp->d_name, NAMLEN(dp));
    }
    else if (errno == 0) {	/* end of stream */
	return Qnil;
    }
    else {
	rb_sys_fail(0);
    }
    return Qnil;		/* not reached */
}

/*
 *  call-seq:
 *     dir.each { |filename| block }  => dir
 *
 *  Calls the block once for each entry in this directory, passing the
 *  filename of each entry as a parameter to the block.
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
dir_each(dir)
    VALUE dir;
{
    struct dir_data *dirp;
    struct dirent *dp;

    GetDIR(dir, dirp);
    for (dp = readdir(dirp->dir); dp != NULL; dp = readdir(dirp->dir)) {
	rb_yield(rb_tainted_str_new(dp->d_name, NAMLEN(dp)));
	if (dirp->dir == NULL) dir_closed();
    }
    return dir;
}

/*
 *  call-seq:
 *     dir.pos => integer
 *     dir.tell => integer
 *
 *  Returns the current position in <em>dir</em>. See also
 *  <code>Dir#seek</code>.
 *
 *     d = Dir.new("testdir")
 *     d.tell   #=> 0
 *     d.read   #=> "."
 *     d.tell   #=> 12
 */
static VALUE
dir_tell(dir)
    VALUE dir;
{
#ifdef HAVE_TELLDIR
    struct dir_data *dirp;
    long pos;

    GetDIR(dir, dirp);
    pos = telldir(dirp->dir);
    return rb_int2inum(pos);
#else
    rb_notimplement();
#endif
}

/*
 *  call-seq:
 *     dir.seek( integer ) => dir
 *
 *  Seeks to a particular location in <em>dir</em>. <i>integer</i>
 *  must be a value returned by <code>Dir#tell</code>.
 *
 *     d = Dir.new("testdir")   #=> #<Dir:0x401b3c40>
 *     d.read                   #=> "."
 *     i = d.tell               #=> 12
 *     d.read                   #=> ".."
 *     d.seek(i)                #=> #<Dir:0x401b3c40>
 *     d.read                   #=> ".."
 */
static VALUE
dir_seek(dir, pos)
    VALUE dir, pos;
{
    struct dir_data *dirp;
    off_t p = NUM2OFFT(pos);

    GetDIR(dir, dirp);
#ifdef HAVE_SEEKDIR
    seekdir(dirp->dir, p);
    return dir;
#else
    rb_notimplement();
#endif
}

/*
 *  call-seq:
 *     dir.pos( integer ) => integer
 *
 *  Synonym for <code>Dir#seek</code>, but returns the position
 *  parameter.
 *
 *     d = Dir.new("testdir")   #=> #<Dir:0x401b3c40>
 *     d.read                   #=> "."
 *     i = d.pos                #=> 12
 *     d.read                   #=> ".."
 *     d.pos = i                #=> 12
 *     d.read                   #=> ".."
 */
static VALUE
dir_set_pos(dir, pos)
    VALUE dir, pos;
{
    dir_seek(dir, pos);
    return pos;
}

/*
 *  call-seq:
 *     dir.rewind => dir
 *
 *  Repositions <em>dir</em> to the first entry.
 *
 *     d = Dir.new("testdir")
 *     d.read     #=> "."
 *     d.rewind   #=> #<Dir:0x401b3fb0>
 *     d.read     #=> "."
 */
static VALUE
dir_rewind(dir)
    VALUE dir;
{
    struct dir_data *dirp;

    GetDIR(dir, dirp);
    rewinddir(dirp->dir);
    return dir;
}

/*
 *  call-seq:
 *     dir.close => nil
 *
 *  Closes the directory stream. Any further attempts to access
 *  <em>dir</em> will raise an <code>IOError</code>.
 *
 *     d = Dir.new("testdir")
 *     d.close   #=> nil
 */
static VALUE
dir_close(dir)
    VALUE dir;
{
    struct dir_data *dirp;

    GetDIR(dir, dirp);
    closedir(dirp->dir);
    dirp->dir = NULL;

    return Qnil;
}

static void
dir_chdir(path)
    VALUE path;
{
    if (chdir(RSTRING(path)->ptr) < 0)
	rb_sys_fail(RSTRING(path)->ptr);
}

static int chdir_blocking = 0;
static VALUE chdir_thread = Qnil;

struct chdir_data {
    VALUE old_path, new_path;
    int done;
};

static VALUE
chdir_yield(args)
    struct chdir_data *args;
{
    dir_chdir(args->new_path);
    args->done = Qtrue;
    chdir_blocking++;
    if (chdir_thread == Qnil)
	chdir_thread = rb_thread_current();
    return rb_yield(args->new_path);
}

static VALUE
chdir_restore(args)
    struct chdir_data *args;
{
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
 *     Dir.chdir( [ string] ) => 0
 *     Dir.chdir( [ string] ) {| path | block }  => anObject
 *
 *  Changes the current working directory of the process to the given
 *  string. When called without an argument, changes the directory to
 *  the value of the environment variable <code>HOME</code>, or
 *  <code>LOGDIR</code>. <code>SystemCallError</code> (probably
 *  <code>Errno::ENOENT</code>) if the target directory does not exist.
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
dir_s_chdir(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE path = Qnil;

    rb_secure(2);
    if (rb_scan_args(argc, argv, "01", &path) == 1) {
	FilePathValue(path);
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
	char *cwd = my_getcwd();

	args.old_path = rb_tainted_str_new2(cwd); free(cwd);
	args.new_path = path;
	args.done = Qfalse;
	return rb_ensure(chdir_yield, (VALUE)&args, chdir_restore, (VALUE)&args);
    }
    dir_chdir(path);

    return INT2FIX(0);
}

/*
 *  call-seq:
 *     Dir.getwd => string
 *     Dir.pwd => string
 *
 *  Returns the path to the current working directory of this process as
 *  a string.
 *
 *     Dir.chdir("/tmp")   #=> 0
 *     Dir.getwd           #=> "/tmp"
 */
static VALUE
dir_s_getwd(dir)
    VALUE dir;
{
    char *path;
    VALUE cwd;

    rb_secure(4);
    path = my_getcwd();
    cwd = rb_tainted_str_new2(path);

    free(path);
    return cwd;
}

static void check_dirname _((volatile VALUE *));
static void
check_dirname(dir)
    volatile VALUE *dir;
{
    char *path, *pend;

    rb_secure(2);
    FilePathValue(*dir);
    path = RSTRING(*dir)->ptr;
    if (path && *(pend = rb_path_end(rb_path_skip_prefix(path)))) {
	*dir = rb_str_new(path, pend - path);
    }
}

/*
 *  call-seq:
 *     Dir.chroot( string ) => 0
 *
 *  Changes this process's idea of the file system root. Only a
 *  privileged process may make this call. Not available on all
 *  platforms. On Unix systems, see <code>chroot(2)</code> for more
 *  information.
 */
static VALUE
dir_s_chroot(dir, path)
    VALUE dir, path;
{
#if defined(HAVE_CHROOT) && !defined(__CHECKER__)
    check_dirname(&path);

    if (chroot(RSTRING(path)->ptr) == -1)
	rb_sys_fail(RSTRING(path)->ptr);

    return INT2FIX(0);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

/*
 *  call-seq:
 *     Dir.mkdir( string [, integer] ) => 0
 *
 *  Makes a new directory named by <i>string</i>, with permissions
 *  specified by the optional parameter <i>anInteger</i>. The
 *  permissions may be modified by the value of
 *  <code>File::umask</code>, and are ignored on NT. Raises a
 *  <code>SystemCallError</code> if the directory cannot be created. See
 *  also the discussion of permissions in the class documentation for
 *  <code>File</code>.
 *
 */
static VALUE
dir_s_mkdir(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE path, vmode;
    int mode;

    if (rb_scan_args(argc, argv, "11", &path, &vmode) == 2) {
	mode = NUM2INT(vmode);
    }
    else {
	mode = 0777;
    }

    check_dirname(&path);
#ifndef _WIN32
    if (mkdir(RSTRING(path)->ptr, mode) == -1)
	rb_sys_fail(RSTRING(path)->ptr);
#else
    if (mkdir(RSTRING(path)->ptr) == -1)
	rb_sys_fail(RSTRING(path)->ptr);
#endif

    return INT2FIX(0);
}

/*
 *  call-seq:
 *     Dir.delete( string ) => 0
 *     Dir.rmdir( string ) => 0
 *     Dir.unlink( string ) => 0
 *
 *  Deletes the named directory. Raises a subclass of
 *  <code>SystemCallError</code> if the directory isn't empty.
 */
static VALUE
dir_s_rmdir(obj, dir)
    VALUE obj, dir;
{
    check_dirname(&dir);
    if (rmdir(RSTRING(dir)->ptr) < 0)
	rb_sys_fail(RSTRING(dir)->ptr);

    return INT2FIX(0);
}

/* System call with warning */
static int
do_stat(path, pst)
    const char *path;
    struct stat *pst;
{
    int ret = stat(path, pst);
    if (ret < 0 && errno != ENOENT)
	rb_sys_warning(path);

    return ret;
}

static int
do_lstat(path, pst)
    const char *path;
    struct stat *pst;
{
    int ret = lstat(path, pst);
    if (ret < 0 && errno != ENOENT)
	rb_sys_warning(path);

    return ret;
}

static DIR *
do_opendir(path)
    const char *path;
{
    DIR *dirp = opendir(path);
    if (dirp == NULL && errno != ENOENT && errno != ENOTDIR)
	rb_sys_warning(path);

    return dirp;
}

/* Return nonzero if S has any special globbing chars in it.  */
static int
has_magic(s, flags)
    const char *s;
    int flags;
{
    const int escape = !(flags & FNM_NOESCAPE);

    register const char *p = s;
    register char c;

    while (c = *p++) {
	switch (c) {
	  case '*':
	  case '?':
	  case '[':
	    return 1;

	  case '\\':
	    if (escape && !(c = *p++))
		return 0;
	    continue;
	}

	p = Next(p-1);
    }

    return 0;
}

/* Find separator in globbing pattern. */
static char *
find_dirsep(s, flags)
    const char *s;
    int flags;
{
    const int escape = !(flags & FNM_NOESCAPE);

    register const char *p = s;
    register char c;
    int open = 0;

    while (c = *p++) {
	switch (c) {
	  case '[':
	    open = 1;
	    continue;
	  case ']':
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

	p = Next(p-1);
    }

    return (char *)p-1;
}

/* Remove escaping baskclashes */
static void
remove_backslashes(p)
    char *p;
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
	Inc(p);
    }

    while (*p++);

    if (t != s)
	memmove(t, s, p - s); /* move '\0' too */
}

/* Globing pattern */
enum glob_pattern_type { PLAIN, MAGICAL, RECURSIVE, MATCH_ALL, MATCH_DIR };

struct glob_pattern {
    char *str;
    enum glob_pattern_type type;
    struct glob_pattern *next;
};

static struct glob_pattern *
glob_make_pattern(p, flags)
    const char *p;
    int flags;
{
    struct glob_pattern *list, *tmp, **tail = &list;
    int dirsep = 0; /* pattern is terminated with '/' */

    while (*p) {
	tmp = ALLOC(struct glob_pattern);
	if (p[0] == '*' && p[1] == '*' && p[2] == '/') {
	    /* fold continuous RECURSIVEs (needed in glob_helper) */
	    do { p += 3; } while (p[0] == '*' && p[1] == '*' && p[2] == '/');
	    tmp->type = RECURSIVE;
	    tmp->str = 0;
	    dirsep = 1;
	}
	else {
	    const char *m = find_dirsep(p, flags);
	    char *buf = ALLOC_N(char, m-p+1);
	    memcpy(buf, p, m-p);
	    buf[m-p] = '\0';
	    tmp->type = has_magic(buf, flags) ? MAGICAL : PLAIN;
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

    tmp = ALLOC(struct glob_pattern);
    tmp->type = dirsep ? MATCH_DIR : MATCH_ALL;
    tmp->str = 0;
    *tail = tmp;
    tmp->next = 0;

    return list;
}

static void
glob_free_pattern(list)
    struct glob_pattern *list;
{
    while (list) {
	struct glob_pattern *tmp = list;
	list = list->next;
	if (tmp->str)
	    free(tmp->str);
	free(tmp);
    }
}

static VALUE
join_path(path, dirsep, name)
    VALUE path;
    int dirsep;
    const char *name;
{
    long len = RSTRING(path)->len;
    VALUE buf = rb_str_new(0, RSTRING(path)->len+strlen(name)+(dirsep?1:0));

    memcpy(RSTRING(buf)->ptr, RSTRING(path)->ptr, len);
    if (dirsep) {
	strcpy(RSTRING(buf)->ptr+len, "/");
	len++;
    }
    strcpy(RSTRING(buf)->ptr+len, name);
    return buf;
}

enum answer { YES, NO, UNKNOWN };

#ifndef S_ISDIR
#   define S_ISDIR(m) ((m & S_IFMT) == S_IFDIR)
#endif

#ifndef S_ISLNK
#  ifndef S_IFLNK
#    define S_ISLNK(m) (0)
#  else
#    define S_ISLNK(m) ((m & S_IFMT) == S_IFLNK)
#  endif
#endif

struct glob_args {
    void (*func) _((VALUE, VALUE));
    VALUE c;
    VALUE v;
};

static VALUE glob_func_caller _((VALUE));

static VALUE
glob_func_caller(val)
    VALUE val;
{
    struct glob_args *args = (struct glob_args *)val;
    VALUE path = args->c;

    OBJ_TAINT(path);
    (*args->func)(path, args->v);
    return Qnil;
}

static int
glob_call_func(func, path, arg)
    void (*func) _((VALUE, VALUE));
    VALUE path;
    VALUE arg;
{
    int status;
    struct glob_args args;

    args.func = func;
    args.c = path;
    args.v = arg;

    rb_protect(glob_func_caller, (VALUE)&args, &status);
    return status;
}

static int
glob_helper(path, dirsep, exist, isdir, beg, end, flags, func, arg)
    VALUE path;
    int dirsep; /* '/' should be placed before appending child entry's name to 'path'. */
    enum answer exist; /* Does 'path' indicate an existing entry? */
    enum answer isdir; /* Does 'path' indicate a directory or a symlink to a directory? */
    struct glob_pattern **beg;
    struct glob_pattern **end;
    int flags;
    void (*func) _((VALUE, VALUE));
    VALUE arg;
{
    struct stat st;
    int status = 0;
    struct glob_pattern **cur, **new_beg, **new_end;
    int plain = 0, magical = 0, recursive = 0, match_all = 0, match_dir = 0;
    int escape = !(flags & FNM_NOESCAPE);

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
	case MAGICAL:
	    magical = 1;
	    break;
	case MATCH_ALL:
	    match_all = 1;
	    break;
	case MATCH_DIR:
	    match_dir = 1;
	    break;
	}
    }

    if (RSTRING(path)->len > 0) {
	if (match_all && exist == UNKNOWN) {
	    if (do_lstat(RSTRING(path)->ptr, &st) == 0) {
		exist = YES;
		isdir = S_ISDIR(st.st_mode) ? YES : S_ISLNK(st.st_mode) ? UNKNOWN : NO;
	    }
	    else {
		exist = NO;
		isdir = NO;
	    }
	}

	if (match_dir && isdir == UNKNOWN) {
	    if (do_stat(RSTRING(path)->ptr, &st) == 0) {
		exist = YES;
		isdir = S_ISDIR(st.st_mode) ? YES : NO;
	    }
	    else {
		exist = NO;
		isdir = NO;
	    }
	}

	if (match_all && exist == YES) {
	    status = glob_call_func(func, path, arg);
	    if (status) return status;
	}

	if (match_dir && isdir == YES) {
	    status = glob_call_func(func, join_path(path, dirsep, ""), arg);
	    if (status) return status;
	}
    }

    if (exist == NO || isdir == NO) return 0;

    if (magical || recursive) {
	struct dirent *dp;
	DIR *dirp = do_opendir(RSTRING(path)->len > 0 ? RSTRING(path)->ptr : ".");
	if (dirp == NULL) return 0;

	for (dp = readdir(dirp); dp != NULL; dp = readdir(dirp)) {
	    VALUE buf = join_path(path, dirsep, dp->d_name);

	    enum answer new_isdir = UNKNOWN;
	    if (recursive && strcmp(dp->d_name, ".") != 0 && strcmp(dp->d_name, "..") != 0
		&& fnmatch("*", dp->d_name, flags) == 0) {
#ifndef _WIN32
		if (do_lstat(RSTRING(buf)->ptr, &st) == 0)
		    new_isdir = S_ISDIR(st.st_mode) ? YES : S_ISLNK(st.st_mode) ? UNKNOWN : NO;
		else
		    new_isdir = NO;
#else
		new_isdir = dp->d_isdir ? (!dp->d_isrep ? YES : UNKNOWN) : NO;
#endif
	    }

	    new_beg = new_end = ALLOC_N(struct glob_pattern *, (end - beg) * 2);

	    for (cur = beg; cur < end; ++cur) {
		struct glob_pattern *p = *cur;
		if (p->type == RECURSIVE) {
		    if (new_isdir == YES) /* not symlink but real directory */
			*new_end++ = p; /* append recursive pattern */
		    p = p->next; /* 0 times recursion */
		}
		if (p->type == PLAIN || p->type == MAGICAL) {
		    if (fnmatch(p->str, dp->d_name, flags) == 0)
			*new_end++ = p->next;
		}
	    }

	    status = glob_helper(buf, 1, YES, new_isdir, new_beg, new_end, flags, func, arg);
	    free(new_beg);
	    if (status) break;
	}

	closedir(dirp);
    }
    else if (plain) {
	struct glob_pattern **copy_beg, **copy_end, **cur2;

	copy_beg = copy_end = ALLOC_N(struct glob_pattern *, end - beg);
	for (cur = beg; cur < end; ++cur)
	    *copy_end++ = (*cur)->type == PLAIN ? *cur : 0;

	for (cur = copy_beg; cur < copy_end; ++cur) {
	    if (*cur) {
		VALUE buf;
		char *name;
		name = ALLOC_N(char, strlen((*cur)->str) + 1);
		strcpy(name, (*cur)->str);
		if (escape) remove_backslashes(name);

		new_beg = new_end = ALLOC_N(struct glob_pattern *, end - beg);
		*new_end++ = (*cur)->next;
		for (cur2 = cur + 1; cur2 < copy_end; ++cur2) {
		    if (*cur2 && fnmatch((*cur2)->str, name, flags) == 0) {
			*new_end++ = (*cur2)->next;
			*cur2 = 0;
		    }
		}

		buf = join_path(path, dirsep, name);
		free(name);
		status = glob_helper(buf, 1, UNKNOWN, UNKNOWN, new_beg, new_end, flags, func, arg);
		free(new_beg);
		if (status) break;
	    }
	}

	free(copy_beg);
    }

    return status;
}

static int
rb_glob2(path, flags, func, arg)
    VALUE path;
    int flags;
    void (*func) _((VALUE, VALUE));
    VALUE arg;
{
    struct glob_pattern *list;
    const char *root;
    VALUE buf;
    int n;
    int status;

    if (flags & FNM_CASEFOLD) {
	rb_warn("Dir.glob() ignores File::FNM_CASEFOLD");
    }

#if defined DOSISH
    flags |= FNM_CASEFOLD;
    root = rb_path_skip_prefix(RSTRING(path)->ptr);
#else
    root = StringValuePtr(path);
    flags &= ~FNM_CASEFOLD;
#endif

    if (root && *root == '/') root++;

    n = root - RSTRING(path)->ptr;
    buf = rb_str_new(RSTRING(path)->ptr, n);

    list = glob_make_pattern(root, flags);
    status = glob_helper(buf, 0, UNKNOWN, UNKNOWN, &list, &list + 1, flags, func, arg);
    glob_free_pattern(list);

    return status;
}

struct rb_glob_args {
    void (*func) _((const char*, VALUE));
    VALUE arg;
};

static VALUE
rb_glob_caller(path, a)
    VALUE path, a;
{
    struct rb_glob_args *args = (struct rb_glob_args *)a;
    (*args->func)(RSTRING(path)->ptr, args->arg);
    return Qnil;
}

void
rb_glob(path, func, arg)
    const char *path;
    void (*func) _((const char*, VALUE));
    VALUE arg;
{
    struct rb_glob_args args;
    int status;

    args.func = func;
    args.arg = arg;
    status = rb_glob2(rb_str_new2(path), 0, rb_glob_caller, &args);

    if (status) rb_jump_tag(status);
}

static void
push_pattern(path, ary)
    VALUE path, ary;
{
    rb_ary_push(ary, path);
}

static int
push_glob(VALUE ary, VALUE s, long offset, int flags);

static int
push_glob(ary, str, offset, flags)
    VALUE ary;
    VALUE str;
    long offset;
    int flags;
{
    const int escape = !(flags & FNM_NOESCAPE);

    const char *p = RSTRING(str)->ptr + offset;
    const char *s = RSTRING(str)->ptr + offset;
    const char *lbrace = 0, *rbrace = 0;
    int nest = 0, status = 0;

    while (*p) {
	if (*p == '{' && nest++ == 0) {
	    lbrace = p;
	}
	if (*p == '}' && --nest <= 0) {
	    rbrace = p;
	    break;
	}
	if (*p == '\\' && escape) {
	    if (!*++p) break;
	}
	Inc(p);
    }

    if (lbrace && rbrace) {
	VALUE buffer = rb_str_new(0, strlen(s));
	char *buf;
	long offset;

	buf = RSTRING(buffer)->ptr;
	memcpy(buf, s, lbrace-s);
	offset = (lbrace-s);
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
		Inc(p);
	    }
	    memcpy(buf+offset, t, p-t);
	    strcpy(buf+offset+(p-t), rbrace+1);
	    status = push_glob(ary, buffer, offset, flags);
	    if (status) break;
	}
    }
    else if (!lbrace && !rbrace) {
	status = rb_glob2(str, flags, push_pattern, ary);
    }

    return status;
}

static VALUE
rb_push_glob(str, flags) /* '\0' is delimiter */
    VALUE str;
    int flags;
{
    long offset = 0;
    VALUE ary;

    FilePathValue(str);

    ary = rb_ary_new();

    while (offset < RSTRING(str)->len) {
	int status = push_glob(ary, str, offset, flags);
	char *p, *pend;
	if (status) rb_jump_tag(status);
	p = RSTRING(str)->ptr + offset;
	p += strlen(p) + 1;
	pend = RSTRING(str)->ptr + RSTRING(str)->len;
	while (p < pend && !*p)
	    p++;
	offset = p - RSTRING(str)->ptr;
    }

    if (rb_block_given_p()) {
	rb_ary_each(ary);
	return Qnil;
    }
    return ary;
}

/*
 *  call-seq:
 *     Dir[ string ] => array
 *
 *  Equivalent to calling
 *  <em>dir</em>.<code>glob(</code><i>string,</i><code>0)</code>.
 *
 */
static VALUE
dir_s_aref(obj, str)
    VALUE obj, str;
{
    return rb_push_glob(str, 0);
}

/*
 *  call-seq:
 *     Dir.glob( string, [flags] ) => array
 *     Dir.glob( string, [flags] ) {| filename | block }  => nil
 *
 *  Returns the filenames found by expanding the pattern given in
 *  <i>string</i>, either as an <i>array</i> or as parameters to the
 *  block. Note that this pattern is not a regexp (it's closer to a
 *  shell glob). See <code>File::fnmatch</code> for the meaning of
 *  the <i>flags</i> parameter. Note that case sensitivity 
 *  depends on your system (so <code>File::FNM_CASEFOLD</code> is ignored)
 *
 *  <code>*</code>::        Matches any file. Can be restricted by
 *                          other values in the glob. <code>*</code>
 *                          will match all files; <code>c*</code> will
 *                          match all files beginning with
 *                          <code>c</code>; <code>*c</code> will match
 *                          all files ending with <code>c</code>; and
 *                          <code>*c*</code> will match all files that
 *                          have <code>c</code> in them (including at
 *                          the beginning or end). Equivalent to
 *                          <code>/ .* /x</code> in regexp.
 *  <code>**</code>::       Matches directories recursively.
 *  <code>?</code>::        Matches any one character. Equivalent to
 *                          <code>/.{1}/</code> in regexp.
 *  <code>[set]</code>::    Matches any one character in +set+.
 *                          Behaves exactly like character sets in
 *                          Regexp, including set negation
 *                          (<code>[^a-z]</code>).
 *  <code>{p,q}</code>::    Matches either literal <code>p</code> or
 *                          literal <code>q</code>. Matching literals
 *                          may be more than one character in length.
 *                          More than two literals may be specified.
 *                          Equivalent to pattern alternation in
 *                          regexp.
 *  <code>\</code>::        Escapes the next metacharacter.
 *
 *     Dir["config.?"]                     #=> ["config.h"]
 *     Dir.glob("config.?")                #=> ["config.h"]
 *     Dir.glob("*.[a-z][a-z]")            #=> ["main.rb"]
 *     Dir.glob("*.[^r]*")                 #=> ["config.h"]
 *     Dir.glob("*.{rb,h}")                #=> ["main.rb", "config.h"]
 *     Dir.glob("*")                       #=> ["config.h", "main.rb"]
 *     Dir.glob("*", File::FNM_DOTMATCH)   #=> [".", "..", "config.h", "main.rb"]
 *
 *     Dir.glob("*", File::FNM_DOTMATCH)   #=> [".", "..", "config.h",
 *                                              "main.rb"]
 *     Dir.glob("**.rb")                   #=> []
 *
 *     rbfiles = File.join("**", "*.rb")
 *     Dir.glob(rbfiles)                   #=> ["main.rb",
 *                                              "lib/song.rb",
 *                                              "lib/song/karaoke.rb"]
 *     libdirs = File.join("**", "lib")
 *     Dir.glob(libdirs)                   #=> ["lib"]
 *
 *     librbfiles = File.join("**", "lib", "**", "*.rb")
 *     Dir.glob(librbfiles)                #=> ["lib/song.rb",
 *                                              "lib/song/karaoke.rb"]
 *
 *     librbfiles = File.join("**", "lib", "*.rb")
 *     Dir.glob(librbfiles)                #=> ["lib/song.rb"]
 */
static VALUE
dir_s_glob(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE str, rflags;
    int flags;

    if (rb_scan_args(argc, argv, "11", &str, &rflags) == 2)
	flags = NUM2INT(rflags);
    else
	flags = 0;

    return rb_push_glob(str, flags);
}

/*
 *  call-seq:
 *     Dir.foreach( dirname ) {| filename | block }  => nil
 *
 *  Calls the block once for each entry in the named directory, passing
 *  the filename of each entry as a parameter to the block.
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
dir_foreach(io, dirname)
    VALUE io, dirname;
{
    VALUE dir;

    dir = rb_funcall(rb_cDir, rb_intern("open"), 1, dirname);
    rb_ensure(dir_each, dir, dir_close, dir);
    return Qnil;
}

/*
 *  call-seq:
 *     Dir.entries( dirname ) => array
 *
 *  Returns an array containing all of the filenames in the given
 *  directory. Will raise a <code>SystemCallError</code> if the named
 *  directory doesn't exist.
 *
 *     Dir.entries("testdir")   #=> [".", "..", "config.h", "main.rb"]
 *
 */
static VALUE
dir_entries(io, dirname)
    VALUE io, dirname;
{
    VALUE dir;

    dir = rb_funcall(rb_cDir, rb_intern("open"), 1, dirname);
    return rb_ensure(rb_Array, dir, dir_close, dir);
}

/*
 *  call-seq:
 *     File.fnmatch( pattern, path, [flags] ) => (true or false)
 *     File.fnmatch?( pattern, path, [flags] ) => (true or false)
 *
 *  Returns true if <i>path</i> matches against <i>pattern</i> The
 *  pattern is not a regular expression; instead it follows rules
 *  similar to shell filename globbing. It may contain the following
 *  metacharacters:
 *
 *  <code>*</code>::        Matches any file. Can be restricted by
 *                          other values in the glob. <code>*</code>
 *                          will match all files; <code>c*</code> will
 *                          match all files beginning with
 *                          <code>c</code>; <code>*c</code> will match
 *                          all files ending with <code>c</code>; and
 *                          <code>*c*</code> will match all files that
 *                          have <code>c</code> in them (including at
 *                          the beginning or end). Equivalent to
 *                          <code>/ .* /x</code> in regexp.
 *  <code>**</code>::       Matches directories recursively or files
 *                          expansively.
 *  <code>?</code>::        Matches any one character. Equivalent to
 *                          <code>/.{1}/</code> in regexp.
 *  <code>[set]</code>::    Matches any one character in +set+.
 *                          Behaves exactly like character sets in
 *                          Regexp, including set negation
 *                          (<code>[^a-z]</code>).
 *  <code>\</code>::        Escapes the next metacharacter.
 *
 *  <i>flags</i> is a bitwise OR of the <code>FNM_xxx</code>
 *  parameters. The same glob pattern and flags are used by
 *  <code>Dir::glob</code>.
 *
 *     File.fnmatch('cat',       'cat')        #=> true  : match entire string
 *     File.fnmatch('cat',       'category')   #=> false : only match partial string
 *     File.fnmatch('c{at,ub}s', 'cats')       #=> false : { } isn't supported
 *
 *     File.fnmatch('c?t',     'cat')          #=> true  : '?' match only 1 character
 *     File.fnmatch('c??t',    'cat')          #=> false : ditto
 *     File.fnmatch('c*',      'cats')         #=> true  : '*' match 0 or more characters
 *     File.fnmatch('c*t',     'c/a/b/t')      #=> true  : ditto
 *     File.fnmatch('ca[a-z]', 'cat')          #=> true  : inclusive bracket expression
 *     File.fnmatch('ca[^t]',  'cat')          #=> false : exclusive bracket expression ('^' or '!')
 *
 *     File.fnmatch('cat', 'CAT')                     #=> false : case sensitive
 *     File.fnmatch('cat', 'CAT', File::FNM_CASEFOLD) #=> true  : case insensitive
 *
 *     File.fnmatch('?',   '/', File::FNM_PATHNAME)  #=> false : wildcard doesn't match '/' on FNM_PATHNAME
 *     File.fnmatch('*',   '/', File::FNM_PATHNAME)  #=> false : ditto
 *     File.fnmatch('[/]', '/', File::FNM_PATHNAME)  #=> false : ditto
 *
 *     File.fnmatch('\?',   '?')                       #=> true  : escaped wildcard becomes ordinary
 *     File.fnmatch('\a',   'a')                       #=> true  : escaped ordinary remains ordinary
 *     File.fnmatch('\a',   '\a', File::FNM_NOESCAPE)  #=> true  : FNM_NOESACPE makes '\' ordinary
 *     File.fnmatch('[\?]', '?')                       #=> true  : can escape inside bracket expression
 *
 *     File.fnmatch('*',   '.profile')                      #=> false : wildcard doesn't match leading
 *     File.fnmatch('*',   '.profile', File::FNM_DOTMATCH)  #=> true    period by default.
 *     File.fnmatch('.*',  '.profile')                      #=> true
 *
 *     rbfiles = File.join("**", "*.rb")
 *     File.fnmatch(rbfiles, 'main.rb')                    #=> false
 *     File.fnmatch(rbfiles, './main.rb')                  #=> false
 *     File.fnmatch(rbfiles, 'lib/song.rb')                #=> true
 *     File.fnmatch('**.rb', 'main.rb')                    #=> true
 *     File.fnmatch('**.rb', './main.rb')                  #=> false
 *     File.fnmatch('**.rb', 'lib/song.rb')                #=> true
 *     File.fnmatch('*',           'dave/.profile')                      #=> true
 *
 *     File.fnmatch('* IGNORE /*', 'dave/.profile', File::FNM_PATHNAME)  #=> false
 *     File.fnmatch('* IGNORE /*', 'dave/.profile', File::FNM_PATHNAME | File::FNM_DOTMATCH) #=> true
 *
 *     File.fnmatch('** IGNORE /foo', 'a/b/c/foo', File::FNM_PATHNAME)     #=> true
 *     File.fnmatch('** IGNORE /foo', '/a/b/c/foo', File::FNM_PATHNAME)    #=> true
 *     File.fnmatch('** IGNORE /foo', 'c:/a/b/c/foo', File::FNM_PATHNAME)  #=> true
 *     File.fnmatch('** IGNORE /foo', 'a/.b/c/foo', File::FNM_PATHNAME)    #=> false
 *     File.fnmatch('** IGNORE /foo', 'a/.b/c/foo', File::FNM_PATHNAME | File::FNM_DOTMATCH) #=> true
 */
static VALUE
file_s_fnmatch(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE pattern, path;
    VALUE rflags;
    int flags;

    if (rb_scan_args(argc, argv, "21", &pattern, &path, &rflags) == 3)
	flags = NUM2INT(rflags);
    else
	flags = 0;

    StringValue(pattern);
    StringValue(path);

    if (fnmatch(RSTRING(pattern)->ptr, RSTRING(path)->ptr, flags) == 0)
	return Qtrue;

    return Qfalse;
}

/*
 *  Objects of class <code>Dir</code> are directory streams representing
 *  directories in the underlying file system. They provide a variety of
 *  ways to list directories and their contents. See also
 *  <code>File</code>.
 *
 *  The directory used in these examples contains the two regular files
 *  (<code>config.h</code> and <code>main.rb</code>), the parent
 *  directory (<code>..</code>), and the directory itself
 *  (<code>.</code>).
 */
void
Init_Dir()
{
    rb_cDir = rb_define_class("Dir", rb_cObject);

    rb_include_module(rb_cDir, rb_mEnumerable);

    rb_define_alloc_func(rb_cDir, dir_s_alloc);
    rb_define_singleton_method(rb_cDir, "open", dir_s_open, 1);
    rb_define_singleton_method(rb_cDir, "foreach", dir_foreach, 1);
    rb_define_singleton_method(rb_cDir, "entries", dir_entries, 1);

    rb_define_method(rb_cDir,"initialize", dir_initialize, 1);
    rb_define_method(rb_cDir,"path", dir_path, 0);
    rb_define_method(rb_cDir,"inspect", dir_inspect, 0);
    rb_define_method(rb_cDir,"read", dir_read, 0);
    rb_define_method(rb_cDir,"each", dir_each, 0);
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

    rb_define_singleton_method(rb_cDir,"glob", dir_s_glob, -1);
    rb_define_singleton_method(rb_cDir,"[]", dir_s_aref, 1);

    rb_define_singleton_method(rb_cFile,"fnmatch", file_s_fnmatch, -1);
    rb_define_singleton_method(rb_cFile,"fnmatch?", file_s_fnmatch, -1);

    rb_file_const("FNM_NOESCAPE", INT2FIX(FNM_NOESCAPE));
    rb_file_const("FNM_PATHNAME", INT2FIX(FNM_PATHNAME));
    rb_file_const("FNM_DOTMATCH", INT2FIX(FNM_DOTMATCH));
    rb_file_const("FNM_CASEFOLD", INT2FIX(FNM_CASEFOLD));
}
