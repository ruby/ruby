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
    char *pat;
    char test;
    int flags;
{
    int not, ok = 0;
    int nocase = flags & FNM_CASEFOLD;
    int escape = !(flags & FNM_NOESCAPE);

    not = *pat == '!' || *pat == '^';
    if (not)
	pat++;

    test = downcase(test);

    while (*pat) {
	int cstart, cend;
	cstart = cend = *pat++;
	if (cstart == ']')
	    return ok == not ? 0 : pat;
        else if (escape && cstart == '\\')
	    cstart = cend = *pat++;
	if (*pat == '-' && pat[1] != ']') {
	    if (escape && pat[1] == '\\')
		pat++;
	    cend = pat[1];
	    if (!cend)
		return 0;
	    pat += 2;
	}
	if (downcase(cstart) <= test && test <= downcase(cend))
	    ok = 1;
    }
    return 0;
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

    while (c = *pat++) {
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
		if ((c == '[' || downcase(*s) == test) &&
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
	    if (!pat)
		return FNM_NOMATCH;
	    s++;
	    break;

	case '\\':
	    if (escape
#if defined DOSISH
		&& *pat && strchr("*?[\\", *pat)
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
    if (dir && dir->dir) closedir(dir->dir);
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

#define GetDIR(obj, dirp) do {\
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

#ifdef HAVE_SEEKDIR
    GetDIR(dir, dirp);
    seekdir(dirp->dir, NUM2INT(pos));
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
    const char *path;
{
    if (chdir(path) < 0)
	rb_sys_fail(path);
}

static int chdir_blocking = 0;
static VALUE chdir_thread = Qnil;

static VALUE
chdir_restore(path)
    char *path;
{
    chdir_blocking--;
    if (chdir_blocking == 0)
	chdir_thread = Qnil;
    dir_chdir(path);
    free(path);
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
    char *dist = "";

    rb_secure(2);
    if (rb_scan_args(argc, argv, "01", &path) == 1) {
	SafeStringValue(path);
	dist = RSTRING(path)->ptr;
    }
    else {
	dist = getenv("HOME");
	if (!dist) {
	    dist = getenv("LOGDIR");
	    if (!dist) rb_raise(rb_eArgError, "HOME/LOGDIR not set");
	}
    }

    if (chdir_blocking > 0) {
	if (!rb_block_given_p() || rb_thread_current() != chdir_thread)
	    rb_warn("conflicting chdir during another chdir block");
    }

    if (rb_block_given_p()) {
	char *cwd = my_getcwd();
	chdir_blocking++;
	if (chdir_thread == Qnil)
	    chdir_thread = rb_thread_current();
	dir_chdir(dist);
	return rb_ensure(rb_yield, path, chdir_restore, (VALUE)cwd);
    }
    dir_chdir(dist);

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

/* Return nonzero if S has any special globbing chars in it.  */
static int
has_magic(s, send, flags)
     char *s, *send;
     int flags;
{
    register char *p = s;
    register char c;
    int open = 0;
    int escape = !(flags & FNM_NOESCAPE);

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
	}

	if (send && p >= send) break;
    }
    return Qfalse;
}

static char*
extract_path(p, pend)
    char *p, *pend;
{
    char *alloc;
    int len;

    len = pend - p;
    alloc = ALLOC_N(char, len+1);
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
    char *path;
{
    char *pend;

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

static int
glob_call_func(func, path, arg)
    void (*func) _((const char*, VALUE));
    const char *path;
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
glob_helper(path, sub, flags, func, arg)
    char *path;
    char *sub;
    int flags;
    void (*func) _((const char*, VALUE));
    VALUE arg;
{
    struct stat st;
    char *p, *m;
    int status = 0;

    p = sub ? sub : path;
    if (!has_magic(p, 0, flags)) {
#if defined DOSISH
	remove_backslashes(path);
#else
	if (!(flags & FNM_NOESCAPE)) remove_backslashes(p);
#endif
	if (lstat(path, &st) == 0) {
	    status = glob_call_func(func, path, arg);
	    if (status) return status;
	}
	else if (errno != ENOENT) {
	    /* In case stat error is other than ENOENT and
	       we may want to know what is wrong. */
	    rb_sys_warning(path);
	}
	return 0;
    }

    while (p && !status) {
	if (*p == '/') p++;
	m = strchr(p, '/');
	if (has_magic(p, m, flags)) {
	    char *dir, *base, *magic, *buf;
	    DIR *dirp;
	    struct dirent *dp;
	    int recursive = 0;

	    struct d_link {
		char *path;
		struct d_link *next;
	    } *tmp, *link, **tail = &link;

	    base = extract_path(path, p);
	    if (path == p) dir = ".";
	    else dir = base;

	    magic = extract_elem(p);
	    if (stat(dir, &st) < 0) {
	        if (errno != ENOENT) rb_sys_warning(dir);
	        free(base);
	        free(magic);
	        break;
	    }
	    if (S_ISDIR(st.st_mode)) {
		if (m && strcmp(magic, "**") == 0) {
		    int n = strlen(base);
		    recursive = 1;
		    buf = ALLOC_N(char, n+strlen(m)+3);
		    sprintf(buf, "%s%s", base, *base ? m : m+1);
		    status = glob_helper(buf, buf+n, flags, func, arg);
		    free(buf);
		    if (status) goto finalize;
		}
		dirp = opendir(dir);
		if (dirp == NULL) {
		    rb_sys_warning(dir);
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
		    buf = ALLOC_N(char, strlen(base)+NAMLEN(dp)+strlen(m)+6);
		    sprintf(buf, "%s%s%s", base, (BASE) ? "/" : "", dp->d_name);
		    if (lstat(buf, &st) < 0) {
			if (errno != ENOENT) rb_sys_warning(buf);
			free(buf);
			continue;
		    }
		    if (S_ISDIR(st.st_mode)) {
			char *t = buf+strlen(buf);
		        strcpy(t, "/**");
			strcpy(t+3, m);
			status = glob_helper(buf, t, flags, func, arg);
			free(buf);
			if (status) break;
			continue;
		    }
		    free(buf);
		    continue;
		}
		if (fnmatch(magic, dp->d_name, flags) == 0) {
		    buf = ALLOC_N(char, strlen(base)+NAMLEN(dp)+2);
		    sprintf(buf, "%s%s%s", base, (BASE) ? "/" : "", dp->d_name);
		    if (!m) {
			status = glob_call_func(func, buf, arg);
			free(buf);
			if (status) break;
			continue;
		    }
		    tmp = ALLOC(struct d_link);
		    tmp->path = buf;
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
				char *t = ALLOC_N(char, len+mlen+1);

				sprintf(t, "%s%s", link->path, m);
				status = glob_helper(t, t+len, flags, func, arg);
				free(t);
			    }
			}
			else {
			    rb_sys_warning(link->path);
			}
		    }
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
    return status;
}

static void
rb_glob2(path, flags, func, arg)
    char *path;
    int flags;
    void (*func) _((const char*, VALUE));
    VALUE arg;
{
    int status = glob_helper(path, 0, flags, func, arg);
    if (status) rb_jump_tag(status);
}

void
rb_glob(path, func, arg)
    char *path;
    void (*func) _((const char*, VALUE));
    VALUE arg;
{
    rb_glob2(path, 0, func, arg);
}

void
rb_globi(path, func, arg)
    char *path;
    void (*func) _((const char*, VALUE));
    VALUE arg;
{
    rb_glob2(path, FNM_CASEFOLD, func, arg);
}

static void
push_pattern(path, ary)
    const char *path;
    VALUE ary;
{
    VALUE str = rb_tainted_str_new2(path);

    if (ary) {
	rb_ary_push(ary, str);
    }
    else {
	rb_yield(str);
    }
}

static void
push_globs(ary, s, flags)
    VALUE ary;
    char *s;
    int flags;
{
    rb_glob2(s, flags, push_pattern, ary);
}

static void
push_braces(ary, s, flags)
    VALUE ary;
    char *s;
    int flags;
{
    char *buf;
    char *p, *t, *b;
    char *lbrace, *rbrace;
    int nest = 0;

    p = s;
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
	buf = xmalloc(len + 1);
	memcpy(buf, s, lbrace-s);
	b = buf + (lbrace-s);
	p = lbrace;
	while (*p != '}') {
	    t = p + 1;
	    for (p = t; *p!='}' && *p!=','; p++) {
		/* skip inner braces */
		if (*p == '{') while (*p!='}') p++;
	    }
	    memcpy(b, t, p-t);
	    strcpy(b+(p-t), rbrace+1);
	    push_braces(ary, buf, flags);
	}
	free(buf);
    }
    else {
	push_globs(ary, s, flags);
    }
}

#define isdelim(c) ((c)=='\0')

static VALUE
rb_push_glob(str, flags)
    VALUE str;
    int flags;
{
    char *p, *pend;
    char *buf;
    char *t;
    int nest, maxnest;
    int noescape = flags & FNM_NOESCAPE;
    VALUE ary;

    if (rb_block_given_p())
	ary = 0;
    else
	ary = rb_ary_new();

    SafeStringValue(str);
    buf = xmalloc(RSTRING(str)->len + 1);

    p = RSTRING(str)->ptr;
    pend = p + RSTRING(str)->len;

    while (p < pend) {
	t = buf;
	nest = maxnest = 0;
	while (p < pend && isdelim(*p)) p++;
	while (p < pend && !isdelim(*p)) {
	    if (*p == '{') nest++, maxnest++;
	    if (*p == '}') nest--;
	    if (!noescape && *p == '\\') {
		*t++ = *p++;
		if (p == pend) break;
	    }
	    *t++ = *p++;
	}
	*t = '\0';
	if (maxnest == 0) {
	    push_globs(ary, buf, flags);
	}
	else if (nest == 0) {
	    push_braces(ary, buf, flags);
	}
	/* else unmatched braces */
    }
    free(buf);

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
 *     Dir.glob( string, [flags] ) {| filename | block }  => false
 *
 *  Returns the filenames found by expanding the pattern given in
 *  <i>string</i>, either as an <i>array</i> or as parameters to the
 *  block. Note that this pattern is not a regexp (it's closer to a
 *  shell glob). See <code>File::fnmatch</code> for
 *  details of file name matching and the meaning of the <i>flags</i>
 *  parameter.
 *
 *     Dir["config.?"]                     #=> ["config.h"]
 *     Dir.glob("config.?")                #=> ["config.h"]
 *     Dir.glob("*.[a-z][a-z]")            #=> ["main.rb"]
 *     Dir.glob("*.[^r]*")                 #=> ["config.h"]
 *     Dir.glob("*.{rb,h}")                #=> ["main.rb", "config.h"]
 *     Dir.glob("*")                       #=> ["config.h", "main.rb"]
 *     Dir.glob("*", File::FNM_DOTMATCH)   #=> [".", "..", "config.h", "main.rb"]
 *
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
 *  <i>flags</i> is a bitwise OR of the <code>FNM_xxx</code> parameters.
 *  The same glob pattern and flags are used by <code>Dir::glob</code>.
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
}
