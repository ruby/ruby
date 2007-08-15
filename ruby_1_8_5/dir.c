/**********************************************************************

  dir.c -

  $Author: shyouhei $
  $Date: 2006/12/14 14:50:13 $
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

#if !defined HAVE_LSTAT && !defined lstat
#define lstat stat
#endif

#ifndef CASEFOLD_FILESYSTEM
# if defined DOSISH || defined __VMS
#   define CASEFOLD_FILESYSTEM 1
# else
#   define CASEFOLD_FILESYSTEM 0
# endif
#endif

#define FNM_NOESCAPE	0x01
#define FNM_PATHNAME	0x02
#define FNM_DOTMATCH	0x04
#define FNM_CASEFOLD	0x08
#if CASEFOLD_FILESYSTEM
#define FNM_SYSCASE	FNM_CASEFOLD
#else
#define FNM_SYSCASE	0
#endif

#define FNM_NOMATCH	1
#define FNM_ERROR	2

#define downcase(c) (nocase && ISUPPER(c) ? tolower(c) : (c))

#ifndef CharNext		/* defined as CharNext[AW] on Windows. */
# if defined(DJGPP)
#   define CharNext(p) ((p) + mblen(p, MB_CUR_MAX))
# else
#   define CharNext(p) ((p) + 1)
# endif
#endif

#if defined DOSISH
#define isdirsep(c) ((c) == '/' || (c) == '\\')
#else
#define isdirsep(c) ((c) == '/')
#endif

static char *
range(pat, test, flags)
    const char *pat;
    int test;
    int flags;
{
    int not, ok = 0;
    int nocase = flags & FNM_CASEFOLD;
    int escape = !(flags & FNM_NOESCAPE);

    not = *pat == '!' || *pat == '^';
    if (not)
	pat++;

    test = downcase(test);

    while (*pat != ']') {
	int cstart, cend;
        if (escape && *pat == '\\')
	    pat++;
	cstart = cend = *pat++;
	if (!cstart)
	    return NULL;
	if (*pat == '-' && pat[1] != ']') {
	    pat++;
	    if (escape && *pat == '\\')
		pat++;
	    cend = *pat++;
	    if (!cend)
		return NULL;
	}
	if (downcase(cstart) <= test && test <= downcase(cend))
	    ok = 1;
    }
    return ok == not ? NULL : (char *)pat + 1;
}

#define ISDIRSEP(c) (pathname && isdirsep(c))
#define PERIOD(s) (period && *(s) == '.' && \
		  ((s) == string || ISDIRSEP((s)[-1])))
static int
fnmatch(pat, string, flags)
    const char *pat;
    const char *string;
    int flags;
{
    int c;
    int test;
    const char *s = string;
    int escape = !(flags & FNM_NOESCAPE);
    int pathname = flags & FNM_PATHNAME;
    int period = !(flags & FNM_DOTMATCH);
    int nocase = flags & FNM_CASEFOLD;

    while ((c = *pat++) != '\0') {
	switch (c) {
	case '?':
	    if (!*s || ISDIRSEP(*s) || PERIOD(s))
		return FNM_NOMATCH;
	    s++;
	    break;
	case '*':
	    while ((c = *pat++) == '*')
		;

	    if (PERIOD(s))
		return FNM_NOMATCH;

	    if (!c) {
		if (pathname && *rb_path_next(s))
		    return FNM_NOMATCH;
		else
		    return 0;
	    }
	    else if (ISDIRSEP(c)) {
		s = rb_path_next(s);
		if (*s) {
                    s++;
		    break;
                }
		return FNM_NOMATCH;
	    }

	    test = escape && c == '\\' ? *pat : c;
	    test = downcase(test);
	    pat--;
	    while (*s) {
		if ((c == '?' || c == '[' || downcase(*s) == test) &&
		    !fnmatch(pat, s, flags | FNM_DOTMATCH))
		    return 0;
		else if (ISDIRSEP(*s))
		    break;
		s++;
	    }
	    return FNM_NOMATCH;

	case '[':
	    if (!*s || ISDIRSEP(*s) || PERIOD(s))
		return FNM_NOMATCH;
	    pat = range(pat, *s, flags);
	    if (pat == NULL)
		return FNM_NOMATCH;
	    s++;
	    break;

	case '\\':
	    if (escape
#if defined DOSISH
		&& *pat && strchr("*?[]\\", *pat)
#endif
		) {
		c = *pat;
		if (!c)
		    c = '\\';
		else
		    pat++;
	    }
	    /* FALLTHROUGH */

	default:
#if defined DOSISH
	    if (ISDIRSEP(c) && isdirsep(*s))
		;
	    else
#endif
	    if(downcase(c) != downcase(*s))
		return FNM_NOMATCH;
	    s++;
	    break;
	}
    }
    return !*s ? 0 : FNM_NOMATCH;
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

    SafeStringValue(dirname);
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

static void
dir_check(dir)
    VALUE dir;
{
    if (!OBJ_TAINTED(dir) && rb_safe_level() >= 4)
	rb_raise(rb_eSecurityError, "Insecure: operation on untainted Dir");
    rb_check_frozen(dir);
}

#define GetDIR(obj, dirp) do {\
    dir_check(dir);\
    Data_Get_Struct(obj, struct dir_data, dirp);\
    if (dirp->dir == NULL) dir_closed();\
} while (0)

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
    rewinddir(dirp->dir);
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

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(dir)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
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
	SafeStringValue(path);
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

    SafeStringValue(*dir);
    rb_secure(2);
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
    if (mkdir(RSTRING(path)->ptr, mode) == -1)
	rb_sys_fail(RSTRING(path)->ptr);

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

static void
sys_warning_1(mesg)
    const char* mesg;
{
    rb_sys_warning("%s", mesg);
}

#define GLOB_VERBOSE	(1U << (sizeof(int) * CHAR_BIT - 1))
#define sys_warning(val) \
    (void)((flags & GLOB_VERBOSE) && rb_protect((VALUE (*)_((VALUE)))sys_warning_1, (VALUE)(val), 0))

#define GLOB_ALLOC(type) (type *)malloc(sizeof(type))
#define GLOB_ALLOC_N(type, n) (type *)malloc(sizeof(type) * (n))
#define GLOB_REALLOC_N(var, type, n) (type *)realloc((var), sizeof(type) * (n))
#define GLOB_JUMP_TAG(status) ((status == -1) ? rb_memerror() : rb_jump_tag(status))

/* Return nonzero if S has any special globbing chars in it.  */
static int
has_magic(s, send, flags)
    const char *s, *send;
    int flags;
{
    register const char *p = s;
    register char c;
    int open = 0;
    const int escape = !(flags & FNM_NOESCAPE);
    const int nocase = flags & FNM_CASEFOLD;

    while ((c = *p++) != '\0') {
	switch (c) {
	  case '?':
	  case '*':
	    return Qtrue;

	  case '[':	/* Only accept an open brace if there is a close */
	    open++;	/* brace to match it.  Bracket expressions must be */
	    continue;	/* complete, according to Posix.2 */
	  case ']':
	    if (open)
		return Qtrue;
	    continue;

	  case '\\':
	    if (escape && *p++ == '\0')
		return Qfalse;
	    break;

	  default:
	    if (!FNM_SYSCASE && ISALPHA(c) && nocase)
		return Qtrue;
	}

	if (send && p >= send) break;
    }
    return Qfalse;
}

static char*
extract_path(p, pend)
    const char *p, *pend;
{
    char *alloc;
    int len;

    len = pend - p;
    alloc = GLOB_ALLOC_N(char, len+1);
    if (!alloc) return NULL;
    memcpy(alloc, p, len);
    if (len > 1 && pend[-1] == '/'
#if defined DOSISH_DRIVE_LETTER
    && pend[-2] != ':'
#endif
    ) {
	alloc[len-1] = 0;
    }
    else {
	alloc[len] = 0;
    }

    return alloc;
}

static char*
extract_elem(path)
    const char *path;
{
    const char *pend;

    pend = strchr(path, '/');
    if (!pend) pend = path + strlen(path);

    return extract_path(path, pend);
}

static void
remove_backslashes(p)
    char *p;
{
    char *pend = p + strlen(p);
    char *t = p;

    while (p < pend) {
	if (*p == '\\') {
	    if (++p == pend) break;
	}
	*t++ = *p++;
    }
    *t = '\0';
}

#ifndef S_ISDIR
#   define S_ISDIR(m) ((m & S_IFMT) == S_IFDIR)
#endif

struct glob_args {
    void (*func) _((const char*, VALUE));
    const char *c;
    VALUE v;
};

static VALUE glob_func_caller _((VALUE));

static VALUE
glob_func_caller(val)
    VALUE val;
{
    struct glob_args *args = (struct glob_args *)val;

    (*args->func)(args->c, args->v);
    return Qnil;
}

#define glob_call_func(func, path, arg) (*func)(path, arg)

static int glob_helper _((const char *path, const char *sub, int flags, int (*func)(const char *,VALUE), VALUE arg));

static int
glob_helper(path, sub, flags, func, arg)
    const char *path;
    const char *sub;
    int flags;
    int (*func) _((const char *, VALUE));
    VALUE arg;
{
    struct stat st;
    const char *p, *m;
    int status = 0;
    char *buf = 0;
    char *newpath = 0;
    char *newbuf;

    p = sub ? sub : path;
    if (!has_magic(p, 0, flags)) {
#if !defined DOSISH
	if (!(flags & FNM_NOESCAPE))
#endif
	{
	    newpath = strdup(path);
	    if (!newpath) return -1;
	    if (sub) {
		p = newpath + (sub - path);
		remove_backslashes(newpath + (sub - path));
		sub = p;
	    }
	    else {
		remove_backslashes(newpath);
		p = path = newpath;
	    }
	}
	if (lstat(path, &st) == 0) {
	    status = glob_call_func(func, path, arg);
	}
	else if (errno != ENOENT) {
	    /* In case stat error is other than ENOENT and
	       we may want to know what is wrong. */
	    sys_warning(path);
	}
	if (newpath) free(newpath);
	return status;
    }

    while (p && !status) {
	if (*p == '/') p++;
	m = strchr(p, '/');
	if (has_magic(p, m, flags)) {
	    char *dir, *base, *magic;
	    DIR *dirp;
	    struct dirent *dp;
	    int recursive = 0;

	    struct d_link {
		char *path;
		struct d_link *next;
	    } *tmp, *link, **tail = &link;

	    base = extract_path(path, p);
	    if (!base) {
		status = -1;
		break;
	    }
	    if (path == p) dir = ".";
	    else dir = base;

	    magic = extract_elem(p);
	    if (!magic) {
		status = -1;
		break;
	    }
	    if (stat(dir, &st) < 0) {
	        if (errno != ENOENT)
		    sys_warning(dir);
	        free(base);
	        free(magic);
	        break;
	    }
	    if (S_ISDIR(st.st_mode)) {
		if (m && strcmp(magic, "**") == 0) {
		    int n = strlen(base);
		    recursive = 1;
		    newbuf = GLOB_REALLOC_N(buf, char, n+strlen(m)+3);
		    if (!newbuf) {
			status = -1;
			goto finalize;
		    }
		    buf = newbuf;
		    sprintf(buf, "%s%s", base, *base ? m : m+1);
		    status = glob_helper(buf, buf+n, flags, func, arg);
		    if (status) goto finalize;
		}
		dirp = opendir(dir);
		if (dirp == NULL) {
		    sys_warning(dir);
		    free(base);
		    free(magic);
		    break;
		}
	    }
	    else {
		free(base);
		free(magic);
		break;
	    }

#if defined DOSISH_DRIVE_LETTER
#define BASE (*base && !((isdirsep(*base) && !base[1]) || (base[1] == ':' && isdirsep(base[2]) && !base[3])))
#else
#define BASE (*base && !(isdirsep(*base) && !base[1]))
#endif

	    for (dp = readdir(dirp); dp != NULL; dp = readdir(dirp)) {
		if (recursive) {
		    if (strcmp(".", dp->d_name) == 0 || strcmp("..", dp->d_name) == 0)
			continue;
		    if (fnmatch("*", dp->d_name, flags) != 0)
			continue;
		    newbuf = GLOB_REALLOC_N(buf, char, strlen(base)+NAMLEN(dp)+strlen(m)+6);
		    if (!newbuf) {
			status = -1;
			break;
		    }
		    buf = newbuf;
		    sprintf(buf, "%s%s%s", base, (BASE) ? "/" : "", dp->d_name);
		    if (lstat(buf, &st) < 0) {
			if (errno != ENOENT)
			    sys_warning(buf);
			continue;
		    }
		    if (S_ISDIR(st.st_mode)) {
			char *t = buf+strlen(buf);
		        strcpy(t, "/**");
			strcpy(t+3, m);
			status = glob_helper(buf, t, flags, func, arg);
			if (status) break;
			continue;
		    }
		    continue;
		}
		if (fnmatch(magic, dp->d_name, flags) == 0) {
		    newbuf = GLOB_REALLOC_N(buf, char, strlen(base)+NAMLEN(dp)+2);
		    if (!newbuf) {
			status = -1;
			break;
		    }
		    buf = newbuf;
		    sprintf(buf, "%s%s%s", base, (BASE) ? "/" : "", dp->d_name);
		    if (!m) {
			status = glob_call_func(func, buf, arg);
			if (status) break;
			continue;
		    }
		    tmp = GLOB_ALLOC(struct d_link);
		    if (!tmp) {
			status = -1;
			break;
		    }
		    tmp->path = buf;
		    buf = 0;
		    *tail = tmp;
		    tail = &tmp->next;
		}
	    }
	    closedir(dirp);
	  finalize:
	    *tail = 0;
	    free(base);
	    free(magic);
	    if (link) {
		while (link) {
		    if (status == 0) {
			if (stat(link->path, &st) == 0) {
			    if (S_ISDIR(st.st_mode)) {
				int len = strlen(link->path);
				int mlen = strlen(m);

				newbuf = GLOB_REALLOC_N(buf, char, len+mlen+1);
				if (!newbuf) {
				    status = -1;
				    goto next_elem;
				}
				buf = newbuf;
				sprintf(buf, "%s%s", link->path, m);
				status = glob_helper(buf, buf+len, flags, func, arg);
			    }
			}
			else {
			    sys_warning(link->path);
			}
		    }
		  next_elem:
		    tmp = link;
		    link = link->next;
		    free(tmp->path);
		    free(tmp);
		}
		break;
	    }
	}
	p = m;
    }
    if (buf) free(buf);
    if (newpath) free(newpath);
    return status;
}

int
ruby_glob(path, flags, func, arg)
    const char *path;
    int flags;
    int (*func) _((const char *, VALUE));
    VALUE arg;
{
    flags |= FNM_SYSCASE;
    return glob_helper(path, 0, flags & ~GLOB_VERBOSE, func, arg);
}

int
ruby_globi(path, flags, func, arg)
    const char *path;
    int flags;
    int (*func) _((const char *, VALUE));
    VALUE arg;
{
    return glob_helper(path, 0, flags | FNM_CASEFOLD, func, arg);
}

static int rb_glob_caller _((const char *, VALUE));

static int
rb_glob_caller(path, a)
    const char *path;
    VALUE a;
{
    int status;
    struct glob_args *args = (struct glob_args *)a;

    args->c = path;
    rb_protect(glob_func_caller, a, &status);
    return status;
}

static int
rb_glob2(path, flags, func, arg)
    const char *path;
    int flags;
    void (*func) _((const char *, VALUE));
    VALUE arg;
{
    struct glob_args args;

    args.func = func;
    args.v = arg;

    flags |= FNM_SYSCASE;
    return glob_helper(path, 0, flags | GLOB_VERBOSE, rb_glob_caller, (VALUE)&args);
}

void
rb_glob(path, func, arg)
    const char *path;
    void (*func) _((const char*, VALUE));
    VALUE arg;
{
    int status = rb_glob2(path, 0, func, arg);
    if (status) rb_jump_tag(status);
}

void
rb_globi(path, func, arg)
    const char *path;
    void (*func) _((const char*, VALUE));
    VALUE arg;
{
    int status = rb_glob2(path, FNM_CASEFOLD, func, arg);
    if (status) rb_jump_tag(status);
}

static void
push_pattern(path, ary)
    const char *path;
    VALUE ary;
{
    rb_ary_push(ary, rb_tainted_str_new2(path));
}

static int
push_globs(ary, s, flags)
    VALUE ary;
    const char *s;
    int flags;
{
    return rb_glob2(s, flags, push_pattern, ary);
}

static int
push_braces(ary, str, flags)
    VALUE ary;
    const char *str;
    int flags;
{
    char *buf = 0;
    char *b, *newbuf;
    const char *s, *p, *t;
    const char *lbrace, *rbrace;
    int nest = 0;
    int status = 0;

    s = p = str;
    lbrace = rbrace = 0;
    while (*p) {
	if (*p == '{') {
	    lbrace = p;
	    break;
	}
	p++;
    }
    while (*p) {
	if (*p == '{') nest++;
	if (*p == '}' && --nest == 0) {
	    rbrace = p;
	    break;
	}
	p++;
    }

    if (lbrace && rbrace) {
	int len = strlen(s);
	p = lbrace;
	while (*p != '}') {
	    t = p + 1;
	    for (p = t; *p!='}' && *p!=','; p++) {
		/* skip inner braces */
		if (*p == '{') {
		    nest = 1;
		    while (*++p != '}' || --nest) {
			if (*p == '{') nest++;
		    }
		}
	    }
	    newbuf = GLOB_REALLOC_N(buf, char, len+1);
	    if (!newbuf) {
		status = -1;
		break;
	    }
	    buf = newbuf;
	    memcpy(buf, s, lbrace-s);
	    b = buf + (lbrace-s);
	    memcpy(b, t, p-t);
	    strcpy(b+(p-t), rbrace+1);
	    status = push_braces(ary, buf, flags);
	    if (status) break;
	}
    }
    else {
	status = push_globs(ary, str, flags);
    }
    if (buf) free(buf);

    return status;
}

#define isdelim(c) ((c)=='\0')

static VALUE
rb_push_glob(str, flags)
    VALUE str;
    int flags;
{
    const char *p, *pend, *buf;
    int nest, maxnest;
    int status = 0;
    int noescape = flags & FNM_NOESCAPE;
    VALUE ary;

    ary = rb_ary_new();
    SafeStringValue(str);
    p = RSTRING(str)->ptr;
    pend = p + RSTRING(str)->len;

    while (p < pend) {
	nest = maxnest = 0;
	while (p < pend && isdelim(*p)) p++;
	buf = p;
	while (p < pend && !isdelim(*p)) {
	    if (*p == '{') nest++, maxnest++;
	    if (*p == '}') nest--;
	    if (!noescape && *p == '\\') {
		if (++p == pend) break;
	    }
	    p++;
	}
	if (maxnest == 0) {
	    status = push_globs(ary, buf, flags);
	    if (status) break;
	}
	else if (nest == 0) {
	    status = push_braces(ary, buf, flags);
	    if (status) break;
	}
	/* else unmatched braces */
    }
    if (status) GLOB_JUMP_TAG(status);
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
 *  the <i>flags</i> parameter.
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

static VALUE
dir_open_dir(path)
    VALUE path;
{
    VALUE dir = rb_funcall(rb_cDir, rb_intern("open"), 1, path);

    if (TYPE(dir) != T_DATA ||
	RDATA(dir)->dfree != (RUBY_DATA_FUNC)free_dir) {
	rb_raise(rb_eTypeError, "wrong argument type %s (expected Dir)",
		 rb_obj_classname(dir));
    }
    return dir;
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

    dir = dir_open_dir(dirname);
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

    dir = dir_open_dir(dirname);
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
 *     File.fnmatch('cat',       'cat')        #=> true
 *     File.fnmatch('cat',       'category')   #=> false
 *     File.fnmatch('c{at,ub}s', 'cats')       #=> false
 *     File.fnmatch('c{at,ub}s', 'cubs')       #=> false
 *     File.fnmatch('c{at,ub}s', 'cat')        #=> false
 *
 *     File.fnmatch('c?t',    'cat')                       #=> true
 *     File.fnmatch('c\?t',   'cat')                       #=> false
 *     File.fnmatch('c??t',   'cat')                       #=> false
 *     File.fnmatch('c*',     'cats')                      #=> true
 *     File.fnmatch('c/ * FIXME * /t', 'c/a/b/c/t')                 #=> true
 *     File.fnmatch('c*t',    'cat')                       #=> true
 *     File.fnmatch('c\at',   'cat')                       #=> true
 *     File.fnmatch('c\at',   'cat', File::FNM_NOESCAPE)   #=> false
 *     File.fnmatch('a?b',    'a/b')                       #=> true
 *     File.fnmatch('a?b',    'a/b', File::FNM_PATHNAME)   #=> false
 *
 *     File.fnmatch('*',   '.profile')                            #=> false
 *     File.fnmatch('*',   '.profile', File::FNM_DOTMATCH)        #=> true
 *     File.fnmatch('*',   'dave/.profile')                       #=> true
 *     File.fnmatch('*',   'dave/.profile', File::FNM_DOTMATCH)   #=> true
 *     File.fnmatch('*',   'dave/.profile', File::FNM_PATHNAME)   #=> false
 *     File.fnmatch('* / FIXME *', 'dave/.profile', File::FNM_PATHNAME)   #=> false
 *     STRICT = File::FNM_PATHNAME | File::FNM_DOTMATCH
 *     File.fnmatch('* / FIXME *', 'dave/.profile', STRICT)               #=> true
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
    rb_file_const("FNM_SYSCASE", INT2FIX(FNM_SYSCASE));
}
