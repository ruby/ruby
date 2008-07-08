/**********************************************************************

  dir.c -

  $Author$
  created at: Wed Jan  5 09:51:01 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/encoding.h"

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
char *strchr(char*,char);
#endif

#include <ctype.h>

#include "ruby/util.h"

#if !defined HAVE_LSTAT && !defined lstat
#define lstat stat
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

# define Next(p, e, enc) (p + rb_enc_mbclen(p, e, enc))
# define Inc(p, e, enc) ((p) = Next(p, e, enc))

static int
char_casecmp(const char *p1, const char *p2, rb_encoding *enc, const int nocase)
{
    const char *p1end, *p2end;

    if (!*p1) return *p1;
    if (!*p2) return -*p2;
    p1end = p1 + strlen(p1);
    p2end = p2 + strlen(p2);
    int c1 = rb_enc_codepoint(p1, p1end, enc);
    int c2 = rb_enc_codepoint(p2, p2end, enc);

    if (c1 == c2) return 0;
    if (nocase) {
	c1 = rb_enc_toupper(c1, enc);
	c2 = rb_enc_toupper(c2, enc);
    }
    return c1 - c2;
}

static char *
bracket(
    const char *p, /* pattern (next to '[') */
    const char *s, /* string */
    int flags,
    rb_encoding *enc)
{
    const char *pend = p + strlen(p);
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
	p = Next(t1, pend, enc);
	if (p[0] == '-' && p[1] != ']') {
	    const char *t2 = p + 1;
	    if (escape && *t2 == '\\')
		t2++;
	    if (!*t2)
		return NULL;
	    p = Next(t2, pend, enc);
	    if (!ok && char_casecmp(t1, s, enc, nocase) <= 0 && char_casecmp(s, t2, enc, nocase) <= 0)
		ok = 1;
	}
	else
	    if (!ok && char_casecmp(t1, s, enc, nocase) == 0)
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
	    if ((t = bracket(p + 1, s, flags, enc)) != 0) {
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
	if (char_casecmp(p, s, enc, nocase) != 0)
	    goto failed;
	Inc(p, pend, enc);
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
    VALUE pattern,
    VALUE string,
    int flags)
{
    const char *p = RSTRING_PTR(pattern); /* pattern */
    const char *s = RSTRING_PTR(string); /* string */
    const char *send = RSTRING_END(string);
    const int period = !(flags & FNM_DOTMATCH);
    const int pathname = flags & FNM_PATHNAME;
    rb_encoding *enc = rb_enc_get(pattern);

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
    char *path;
    rb_encoding *intenc;
    rb_encoding *extenc;
};

static void
free_dir(struct dir_data *dir)
{
    if (dir) {
	if (dir->dir) closedir(dir->dir);
	if (dir->path) xfree(dir->path);
    }
    xfree(dir);
}

static VALUE dir_close(VALUE);

static VALUE
dir_s_alloc(VALUE klass)
{
    struct dir_data *dirp;
    VALUE obj = Data_Make_Struct(klass, struct dir_data, 0, free_dir, dirp);

    dirp->dir = NULL;
    dirp->path = NULL;
    dirp->intenc = NULL;
    dirp->extenc = NULL;

    return obj;
}

/*
 *  call-seq:
 *     Dir.new( string ) -> aDir
 *
 *  Returns a new directory object for the named directory.
 */
static VALUE
dir_initialize(int argc, VALUE *argv, VALUE dir)
{
    struct dir_data *dp;
    static rb_encoding *fs_encoding;
    rb_encoding  *intencoding, *extencoding;
    VALUE dirname, opt;
    static VALUE sym_intenc, sym_extenc;

    if (!sym_intenc) {
	sym_intenc = ID2SYM(rb_intern("internal_encoding"));
	sym_extenc = ID2SYM(rb_intern("external_encoding"));
	fs_encoding = rb_filesystem_encoding();
    }

    intencoding = NULL;
    extencoding = fs_encoding;
    rb_scan_args(argc, argv, "11", &dirname, &opt);

    if (!NIL_P(opt)) {
        VALUE v, extenc=Qnil, intenc=Qnil;
        opt = rb_check_convert_type(opt, T_HASH, "Hash", "to_hash");

        v = rb_hash_aref(opt, sym_intenc);
        if (!NIL_P(v)) intenc = v;
        v = rb_hash_aref(opt, sym_extenc);
        if (!NIL_P(v)) extenc = v;

	if (!NIL_P(extenc)) {
	    extencoding = rb_to_encoding(extenc);
	    if (!NIL_P(intenc)) {
		intencoding = rb_to_encoding(intenc);
		if (extencoding == intencoding) {
		    rb_warn("Ignoring internal encoding '%s': it is identical to external encoding '%s'",
			    RSTRING_PTR(rb_inspect(intenc)),
			    RSTRING_PTR(rb_inspect(extenc)));
		    intencoding = NULL;
		}
	    }
	}
	else if (!NIL_P(intenc)) {
	    rb_raise(rb_eArgError, "External encoding must be specified when internal encoding is given");
	}
    }

    {
	rb_encoding  *dirname_encoding = rb_enc_get(dirname);
	if (rb_usascii_encoding() != dirname_encoding
	    && rb_ascii8bit_encoding() != dirname_encoding
#if defined __APPLE__
	    && rb_utf8_encoding() != dirname_encoding
#endif
	    && extencoding != dirname_encoding) {
	    if (!intencoding) intencoding = dirname_encoding;
	    dirname = rb_str_transcode(dirname, rb_enc_from_encoding(extencoding));
	}
    }
    FilePathValue(dirname);

    Data_Get_Struct(dir, struct dir_data, dp);
    if (dp->dir) closedir(dp->dir);
    if (dp->path) xfree(dp->path);
    dp->dir = NULL;
    dp->path = NULL;
    dp->intenc = intencoding;
    dp->extenc = extencoding;
    dp->dir = opendir(RSTRING_PTR(dirname));
    if (dp->dir == NULL) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    dp->dir = opendir(RSTRING_PTR(dirname));
	}
	if (dp->dir == NULL) {
	    rb_sys_fail(RSTRING_PTR(dirname));
	}
    }
    dp->path = strdup(RSTRING_PTR(dirname));

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
dir_s_open(int argc, VALUE *argv, VALUE klass)
{
    struct dir_data *dp;
    VALUE dir = Data_Make_Struct(klass, struct dir_data, 0, free_dir, dp);

    dir_initialize(argc, argv, dir);
    if (rb_block_given_p()) {
	return rb_ensure(rb_yield, dir, dir_close, dir);
    }

    return dir;
}

static void
dir_closed(void)
{
    rb_raise(rb_eIOError, "closed directory");
}

static void
dir_check(VALUE dir)
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

static VALUE
dir_enc_str(VALUE str, struct dir_data *dirp)
{
    rb_enc_associate(str, dirp->extenc);
    if (dirp->intenc) {
        str = rb_str_transcode(str, rb_enc_from_encoding(dirp->intenc));
    }
    return str;
}

/*
 *  call-seq:
 *     dir.inspect => string
 *
 *  Return a string describing this Dir object.
 */
static VALUE
dir_inspect(VALUE dir)
{
    struct dir_data *dirp;

    Data_Get_Struct(dir, struct dir_data, dirp);
    if (dirp->path) {
	const char *c = rb_obj_classname(dir);
	int len = strlen(c) + strlen(dirp->path) + 4;
	VALUE s = rb_str_new(0, len);
	snprintf(RSTRING_PTR(s), len+1, "#<%s:%s>", c, dirp->path);
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
dir_path(VALUE dir)
{
    struct dir_data *dirp;

    Data_Get_Struct(dir, struct dir_data, dirp);
    if (!dirp->path) return Qnil;
    return dir_enc_str(rb_str_new2(dirp->path), dirp);
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
dir_read(VALUE dir)
{
    struct dir_data *dirp;
    struct dirent *dp;

    GetDIR(dir, dirp);
    errno = 0;
    dp = readdir(dirp->dir);
    if (dp) {
	return dir_enc_str(rb_tainted_str_new(dp->d_name, NAMLEN(dp)), dirp);
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
dir_each(VALUE dir)
{
    struct dir_data *dirp;
    struct dirent *dp;

    RETURN_ENUMERATOR(dir, 0, 0);
    GetDIR(dir, dirp);
    rewinddir(dirp->dir);
    for (dp = readdir(dirp->dir); dp != NULL; dp = readdir(dirp->dir)) {
	rb_yield(dir_enc_str(rb_tainted_str_new(dp->d_name, NAMLEN(dp)), dirp));
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
dir_tell(VALUE dir)
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
dir_seek(VALUE dir, VALUE pos)
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
dir_set_pos(VALUE dir, VALUE pos)
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
dir_rewind(VALUE dir)
{
    struct dir_data *dirp;

    if (rb_safe_level() >= 4 && !OBJ_TAINTED(dir)) {
	rb_raise(rb_eSecurityError, "Insecure: can't close");
    }
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
dir_close(VALUE dir)
{
    struct dir_data *dirp;

    GetDIR(dir, dirp);
    closedir(dirp->dir);
    dirp->dir = NULL;

    return Qnil;
}

static void
dir_chdir(VALUE path)
{
    if (chdir(RSTRING_PTR(path)) < 0)
	rb_sys_fail(RSTRING_PTR(path));
}

static int chdir_blocking = 0;
static VALUE chdir_thread = Qnil;

struct chdir_data {
    VALUE old_path, new_path;
    int done;
};

static VALUE
chdir_yield(struct chdir_data *args)
{
    dir_chdir(args->new_path);
    args->done = Qtrue;
    chdir_blocking++;
    if (chdir_thread == Qnil)
	chdir_thread = rb_thread_current();
    return rb_yield(args->new_path);
}

static VALUE
chdir_restore(struct chdir_data *args)
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
dir_s_chdir(int argc, VALUE *argv, VALUE obj)
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

	args.old_path = rb_tainted_str_new2(cwd); xfree(cwd);
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
dir_s_getwd(VALUE dir)
{
    char *path;
    VALUE cwd;

    rb_secure(4);
    path = my_getcwd();
    cwd = rb_tainted_str_new2(path);

    xfree(path);
    return cwd;
}

static void
check_dirname(volatile VALUE *dir)
{
    char *path, *pend;

    rb_secure(2);
    FilePathValue(*dir);
    path = RSTRING_PTR(*dir);
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
dir_s_chroot(VALUE dir, VALUE path)
{
#if defined(HAVE_CHROOT) && !defined(__CHECKER__)
    check_dirname(&path);

    if (chroot(RSTRING_PTR(path)) == -1)
	rb_sys_fail(RSTRING_PTR(path));

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
dir_s_mkdir(int argc, VALUE *argv, VALUE obj)
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
    if (mkdir(RSTRING_PTR(path), mode) == -1)
	rb_sys_fail(RSTRING_PTR(path));

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
dir_s_rmdir(VALUE obj, VALUE dir)
{
    check_dirname(&dir);
    if (rmdir(RSTRING_PTR(dir)) < 0)
	rb_sys_fail(RSTRING_PTR(dir));

    return INT2FIX(0);
}

static void
sys_warning_1(const char* mesg)
{
    rb_sys_warning("%s", mesg);
}

#define GLOB_VERBOSE	(1UL << (sizeof(int) * CHAR_BIT - 1))
#define sys_warning(val) \
    (void)((flags & GLOB_VERBOSE) && rb_protect((VALUE (*)(VALUE))sys_warning_1, (VALUE)(val), 0))

#define GLOB_ALLOC(type) (type *)malloc(sizeof(type))
#define GLOB_ALLOC_N(type, n) (type *)malloc(sizeof(type) * (n))
#define GLOB_FREE(ptr) free(ptr)
#define GLOB_JUMP_TAG(status) ((status == -1) ? rb_memerror() : rb_jump_tag(status))

/*
 * ENOTDIR can be returned by stat(2) if a non-leaf element of the path
 * is not a directory.
 */
#define to_be_ignored(e) ((e) == ENOENT || (e) == ENOTDIR)

/* System call with warning */
static int
do_stat(const char *path, struct stat *pst, int flags)

{
    int ret = stat(path, pst);
    if (ret < 0 && !to_be_ignored(errno))
	sys_warning(path);

    return ret;
}

static int
do_lstat(const char *path, struct stat *pst, int flags)
{
    int ret = lstat(path, pst);
    if (ret < 0 && !to_be_ignored(errno))
	sys_warning(path);

    return ret;
}

static DIR *
do_opendir(const char *path, int flags)
{
    DIR *dirp = opendir(path);
    if (dirp == NULL && !to_be_ignored(errno))
	sys_warning(path);

    return dirp;
}

/* Return nonzero if S has any special globbing chars in it.  */
static int
has_magic(const char *s, int flags, rb_encoding *enc)
{
    const int escape = !(flags & FNM_NOESCAPE);
    const int nocase = flags & FNM_CASEFOLD;

    register const char *p = s;
    register const char *pend = p + strlen(p);
    register char c;

    while ((c = *p++) != 0) {
	switch (c) {
	  case '*':
	  case '?':
	  case '[':
	    return 1;

	  case '\\':
	    if (escape && !(c = *p++))
		return 0;
	    continue;

	  default:
	    if (!FNM_SYSCASE && ISALPHA(c) && nocase)
		return 1;
	}

	p = Next(p-1, pend, enc);
    }

    return 0;
}

/* Find separator in globbing pattern. */
static char *
find_dirsep(const char *s, int flags, rb_encoding *enc)
{
    const int escape = !(flags & FNM_NOESCAPE);

    register const char *p = s;
    register const char *pend = p + strlen(p);
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
static void
remove_backslashes(char *p, rb_encoding *enc)
{
    register const char *pend = p + strlen(p);
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
}

/* Globing pattern */
enum glob_pattern_type { PLAIN, MAGICAL, RECURSIVE, MATCH_ALL, MATCH_DIR };

struct glob_pattern {
    char *str;
    enum glob_pattern_type type;
    struct glob_pattern *next;
};

static void glob_free_pattern(struct glob_pattern *list);

static struct glob_pattern *
glob_make_pattern(const char *p, int flags, rb_encoding *enc)
{
    struct glob_pattern *list, *tmp, **tail = &list;
    int dirsep = 0; /* pattern is terminated with '/' */

    while (*p) {
	tmp = GLOB_ALLOC(struct glob_pattern);
	if (!tmp) goto error;
	if (p[0] == '*' && p[1] == '*' && p[2] == '/') {
	    /* fold continuous RECURSIVEs (needed in glob_helper) */
	    do { p += 3; } while (p[0] == '*' && p[1] == '*' && p[2] == '/');
	    tmp->type = RECURSIVE;
	    tmp->str = 0;
	    dirsep = 1;
	}
	else {
	    const char *m = find_dirsep(p, flags, enc);
	    char *buf = GLOB_ALLOC_N(char, m-p+1);
	    if (!buf) {
		GLOB_FREE(tmp);
		goto error;
	    }
	    memcpy(buf, p, m-p);
	    buf[m-p] = '\0';
	    tmp->type = has_magic(buf, flags, enc) ? MAGICAL : PLAIN;
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
join_path(const char *path, int dirsep, const char *name)
{
    long len = strlen(path);
    char *buf = GLOB_ALLOC_N(char, len+strlen(name)+(dirsep?1:0)+1);

    if (!buf) return 0;
    memcpy(buf, path, len);
    if (dirsep) {
	strcpy(buf+len, "/");
	len++;
    }
    strcpy(buf+len, name);
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
    void (*func)(VALUE, VALUE);
    VALUE path;
    VALUE value;
};

static VALUE
glob_func_caller(VALUE val)
{
    struct glob_args *args = (struct glob_args *)val;

    (*args->func)(args->path, args->value);
    return Qnil;
}

#define glob_call_func(func, path, arg) (*func)(path, arg)

static int
glob_helper(
    VALUE vpath,
    int dirsep, /* '/' should be placed before appending child entry's name to 'path'. */
    enum answer exist, /* Does 'path' indicate an existing entry? */
    enum answer isdir, /* Does 'path' indicate a directory or a symlink to a directory? */
    struct glob_pattern **beg,
    struct glob_pattern **end,
    int flags,
    ruby_glob_func *func,
    VALUE arg)
{
    const char *path = RSTRING_PTR(vpath);
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
	  case RECURSIVE:
	    rb_bug("continuous RECURSIVEs");
	}
    }

    if (*path) {
	if (match_all && exist == UNKNOWN) {
	    if (do_lstat(path, &st, flags) == 0) {
		exist = YES;
		isdir = S_ISDIR(st.st_mode) ? YES : S_ISLNK(st.st_mode) ? UNKNOWN : NO;
	    }
	    else {
		exist = NO;
		isdir = NO;
	    }
	}
	if (match_dir && isdir == UNKNOWN) {
	    if (do_stat(path, &st, flags) == 0) {
		exist = YES;
		isdir = S_ISDIR(st.st_mode) ? YES : NO;
	    }
	    else {
		exist = NO;
		isdir = NO;
	    }
	}
	if (match_all && exist == YES) {
	    status = glob_call_func(func, rb_tainted_str_new2(path), arg);
	    if (status) return status;
	}
	if (match_dir && isdir == YES) {
	    char *tmp = join_path(path, dirsep, "");
	    if (!tmp) return -1;
	    status = glob_call_func(func, rb_tainted_str_new2(tmp), arg);
	    GLOB_FREE(tmp);
	    if (status) return status;
	}
    }

    if (exist == NO || isdir == NO) return 0;

    if (magical || recursive) {
	struct dirent *dp;
	DIR *dirp = do_opendir(*path ? path : ".", flags);
	if (dirp == NULL) return 0;

	for (dp = readdir(dirp); dp != NULL; dp = readdir(dirp)) {
	    char *buf = join_path(path, dirsep, dp->d_name);
	    enum answer new_isdir = UNKNOWN;

	    if (!buf) {
		status = -1;
		break;
	    }
	    if (recursive && strcmp(dp->d_name, ".") != 0 && strcmp(dp->d_name, "..") != 0
		&& fnmatch(rb_usascii_str_new2("*"), rb_str_new2(dp->d_name), flags) == 0) {
#ifndef _WIN32
		if (do_lstat(buf, &st, flags) == 0)
		    new_isdir = S_ISDIR(st.st_mode) ? YES : S_ISLNK(st.st_mode) ? UNKNOWN : NO;
		else
		    new_isdir = NO;
#else
		new_isdir = dp->d_isdir ? (!dp->d_isrep ? YES : UNKNOWN) : NO;
#endif
	    }

	    new_beg = new_end = GLOB_ALLOC_N(struct glob_pattern *, (end - beg) * 2);
	    if (!new_beg) {
		GLOB_FREE(buf);
		status = -1;
		break;
	    }

	    for (cur = beg; cur < end; ++cur) {
		struct glob_pattern *p = *cur;
		if (p->type == RECURSIVE) {
		    if (new_isdir == YES) /* not symlink but real directory */
			*new_end++ = p; /* append recursive pattern */
		    p = p->next; /* 0 times recursion */
		}
		if (p->type == PLAIN || p->type == MAGICAL) {
		    if (fnmatch(rb_str_new2(p->str), rb_str_new2(dp->d_name), flags) == 0)
			*new_end++ = p->next;
		}
	    }

	    status = glob_helper(rb_enc_str_new(buf, strlen(buf), rb_enc_get(vpath)), 1,
	    			 YES, new_isdir, new_beg, new_end, flags, func, arg);
	    GLOB_FREE(buf);
	    GLOB_FREE(new_beg);
	    if (status) break;
	}

	closedir(dirp);
    }
    else if (plain) {
	struct glob_pattern **copy_beg, **copy_end, **cur2;

	copy_beg = copy_end = GLOB_ALLOC_N(struct glob_pattern *, end - beg);
	if (!copy_beg) return -1;
	for (cur = beg; cur < end; ++cur)
	    *copy_end++ = (*cur)->type == PLAIN ? *cur : 0;

	for (cur = copy_beg; cur < copy_end; ++cur) {
	    if (*cur) {
		char *buf;
		char *name;
		name = GLOB_ALLOC_N(char, strlen((*cur)->str) + 1);
		if (!name) {
		    status = -1;
		    break;
		}
		strcpy(name, (*cur)->str);
		if (escape) remove_backslashes(name, rb_enc_get(vpath));

		new_beg = new_end = GLOB_ALLOC_N(struct glob_pattern *, end - beg);
		if (!new_beg) {
		    GLOB_FREE(name);
		    status = -1;
		    break;
		}
		*new_end++ = (*cur)->next;
		for (cur2 = cur + 1; cur2 < copy_end; ++cur2) {
		    if (*cur2 && fnmatch(rb_str_new2((*cur2)->str), rb_str_new2(name), flags) == 0) {
			*new_end++ = (*cur2)->next;
			*cur2 = 0;
		    }
		}

		buf = join_path(path, dirsep, name);
		GLOB_FREE(name);
		if (!buf) {
		    GLOB_FREE(new_beg);
		    status = -1;
		    break;
		}
		status = glob_helper(rb_enc_str_new(buf, strlen(buf), rb_enc_get(vpath)), 1,
				     UNKNOWN, UNKNOWN, new_beg, new_end, flags, func, arg);
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
ruby_glob0(VALUE path, int flags, ruby_glob_func *func, VALUE arg)
{
    struct glob_pattern *list;
    const char *root, *start;
    int status;
    VALUE buf;

    start = root = RSTRING_PTR(path);
    flags |= FNM_SYSCASE;
#if defined DOSISH
    root = rb_path_skip_prefix(root);
#endif

    if (root && *root == '/') root++;

    buf = rb_enc_str_new(start, root - start, rb_enc_get(path));

    list = glob_make_pattern(root, flags, rb_enc_get(path));
    if (!list) {
	return -1;
    }
    status = glob_helper(buf, 0, UNKNOWN, UNKNOWN, &list, &list + 1, flags, func, arg);
    glob_free_pattern(list);

    return status;
}

int
ruby_glob(const char *path, int flags, ruby_glob_func *func, VALUE arg)
{
    return ruby_glob0(rb_str_new2(path), flags & ~GLOB_VERBOSE, func, arg);
}

static int
rb_glob_caller(VALUE path, VALUE a)
{
    int status;
    struct glob_args *args = (struct glob_args *)a;

    args->path = path;
    rb_protect(glob_func_caller, a, &status);
    return status;
}

static int
rb_glob2(VALUE path, int flags, void (*func)(VALUE, VALUE), VALUE arg)
{
    struct glob_args args;

    args.func = func;
    args.value = arg;

    if (flags & FNM_SYSCASE) {
	rb_warning("Dir.glob() ignores File::FNM_CASEFOLD");
    }

    return ruby_glob0(path, flags | GLOB_VERBOSE, rb_glob_caller, (VALUE)&args);
}

void
rb_glob(const char *path, void (*func)(VALUE, VALUE), VALUE arg)
{
    int status = rb_glob2(rb_str_new2(path), 0, func, arg);
    if (status) GLOB_JUMP_TAG(status);
}

static void
push_pattern(VALUE path, VALUE ary)
{
    OBJ_TAINT(path);
    rb_ary_push(ary, path);
}

static int
ruby_brace_expand(const char *str, int flags, ruby_glob_func *func, VALUE arg, rb_encoding *enc)
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
	if (*p == '}' && --nest <= 0) {
	    rbrace = p;
	    break;
	}
	if (*p == '\\' && escape) {
	    if (!*++p) break;
	}
	Inc(p, pend, enc);
    }

    if (lbrace && rbrace) {
	char *buf = GLOB_ALLOC_N(char, strlen(s) + 1);
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
	    strcpy(buf+shift+(p-t), rbrace+1);
	    status = ruby_brace_expand(buf, flags, func, arg, enc);
	    if (status) break;
	}
	GLOB_FREE(buf);
    }
    else if (!lbrace && !rbrace) {
	status = (*func)(rb_enc_str_new(s, strlen(s), enc), arg);
    }

    return status;
}

struct brace_args {
    ruby_glob_func *func;
    VALUE value;
    int flags;
};

static int
glob_brace(VALUE path, VALUE val)
{
    struct brace_args *arg = (struct brace_args *)val;

    return ruby_glob0(path, arg->flags, arg->func, arg->value);
}

static int
ruby_brace_glob0(VALUE str, int flags, ruby_glob_func *func, VALUE arg)
{
    struct brace_args args;

    args.func = func;
    args.value = arg;
    args.flags = flags;
    return ruby_brace_expand(RSTRING_PTR(str), flags, glob_brace, (VALUE)&args, rb_enc_get(str));
}

int
ruby_brace_glob(const char *str, int flags, ruby_glob_func *func, VALUE arg)
{
    return ruby_brace_glob0(rb_str_new2(str), flags & ~GLOB_VERBOSE, func, arg);
}

static int
push_glob(VALUE ary, VALUE str, int flags)
{
    struct glob_args args;

    args.func = push_pattern;
    args.value = ary;
    return ruby_brace_glob0(str, flags | GLOB_VERBOSE, rb_glob_caller, (VALUE)&args);
}

static VALUE
rb_push_glob(VALUE str, int flags) /* '\0' is delimiter */
{
    long offset = 0;
    VALUE ary;

    StringValue(str);
    ary = rb_ary_new();

    while (offset < RSTRING_LEN(str)) {
	char *p, *pend;
	p = RSTRING_PTR(str) + offset;
	int status = push_glob(ary,
		rb_enc_str_new(p, strlen(p), rb_enc_get(str)), flags);
	if (status) GLOB_JUMP_TAG(status);
	if (offset >= RSTRING_LEN(str)) break;
	p += strlen(p) + 1;
	pend = RSTRING_PTR(str) + RSTRING_LEN(str);
	while (p < pend && !*p)
	    p++;
	offset = p - RSTRING_PTR(str);
    }

    return ary;
}

static VALUE
dir_globs(long argc, VALUE *argv, int flags)
{
    VALUE ary = rb_ary_new();
    long i;

    for (i = 0; i < argc; ++i) {
	int status;
	VALUE str = argv[i];
	StringValue(str);
	status = push_glob(ary, str, flags);
	if (status) GLOB_JUMP_TAG(status);
    }

    return ary;
}

/*
 *  call-seq:
 *     Dir[ array ]                 => array
 *     Dir[ string [, string ...] ] => array
 *
 *  Equivalent to calling
 *  <code>Dir.glob(</code><i>array,</i><code>0)</code> and
 *  <code>Dir.glob([</code><i>string,...</i><code>],0)</code>.
 *
 */
static VALUE
dir_s_aref(int argc, VALUE *argv, VALUE obj)
{
    if (argc == 1) {
	return rb_push_glob(argv[0], 0);
    }
    return dir_globs(argc, argv, 0);
}

/*
 *  call-seq:
 *     Dir.glob( pattern, [flags] ) => array
 *     Dir.glob( pattern, [flags] ) {| filename | block }  => nil
 *
 *  Returns the filenames found by expanding <i>pattern</i> which is
 *  an +Array+ of the patterns or the pattern +String+, either as an
 *  <i>array</i> or as parameters to the block. Note that this pattern
 *  is not a regexp (it's closer to a shell glob). See
 *  <code>File::fnmatch</code> for the meaning of the <i>flags</i>
 *  parameter. Note that case sensitivity depends on your system (so
 *  <code>File::FNM_CASEFOLD</code> is ignored)
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
 *                                         #    "lib/song.rb",
 *                                         #    "lib/song/karaoke.rb"]
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
    VALUE str, rflags, ary;
    int flags;

    if (rb_scan_args(argc, argv, "11", &str, &rflags) == 2)
	flags = NUM2INT(rflags);
    else
	flags = 0;

    ary = rb_check_array_type(str);
    if (NIL_P(ary)) {
	ary = rb_push_glob(str, flags);
    }
    else {
	volatile VALUE v = ary;
	ary = dir_globs(RARRAY_LEN(v), RARRAY_PTR(v), flags);
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
    VALUE dir = rb_funcall2(rb_cDir, rb_intern("open"), argc, argv);

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
dir_foreach(int argc, VALUE *argv, VALUE io)
{
    VALUE dir;

    RETURN_ENUMERATOR(io, argc, argv);
    dir = dir_open_dir(argc, argv);
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
dir_entries(int argc, VALUE *argv, VALUE io)
{
    VALUE dir;

    dir = dir_open_dir(argc, argv);
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
 *     File.fnmatch('cat',       'cat')        #=> true  # match entire string
 *     File.fnmatch('cat',       'category')   #=> false # only match partial string
 *     File.fnmatch('c{at,ub}s', 'cats')       #=> false # { } isn't supported
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
 *
 *     File.fnmatch('?',   '/', File::FNM_PATHNAME)  #=> false # wildcard doesn't match '/' on FNM_PATHNAME
 *     File.fnmatch('*',   '/', File::FNM_PATHNAME)  #=> false # ditto
 *     File.fnmatch('[/]', '/', File::FNM_PATHNAME)  #=> false # ditto
 *
 *     File.fnmatch('\?',   '?')                       #=> true  # escaped wildcard becomes ordinary
 *     File.fnmatch('\a',   'a')                       #=> true  # escaped ordinary remains ordinary
 *     File.fnmatch('\a',   '\a', File::FNM_NOESCAPE)  #=> true  # FNM_NOESACPE makes '\' ordinary
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

    StringValue(pattern);
    FilePathStringValue(path);

    if (fnmatch(pattern, path, flags) == 0)
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
Init_Dir(void)
{
    rb_cDir = rb_define_class("Dir", rb_cObject);

    rb_include_module(rb_cDir, rb_mEnumerable);

    rb_define_alloc_func(rb_cDir, dir_s_alloc);
    rb_define_singleton_method(rb_cDir, "open", dir_s_open, -1);
    rb_define_singleton_method(rb_cDir, "foreach", dir_foreach, -1);
    rb_define_singleton_method(rb_cDir, "entries", dir_entries, -1);

    rb_define_method(rb_cDir,"initialize", dir_initialize, -1);
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
    rb_define_singleton_method(rb_cDir,"[]", dir_s_aref, -1);
    rb_define_singleton_method(rb_cDir,"exist?", rb_file_directory_p, 1); /* in file.c */
    rb_define_singleton_method(rb_cDir,"exists?", rb_file_directory_p, 1); /* in file.c */

    rb_define_singleton_method(rb_cFile,"fnmatch", file_s_fnmatch, -1);
    rb_define_singleton_method(rb_cFile,"fnmatch?", file_s_fnmatch, -1);

    rb_file_const("FNM_NOESCAPE", INT2FIX(FNM_NOESCAPE));
    rb_file_const("FNM_PATHNAME", INT2FIX(FNM_PATHNAME));
    rb_file_const("FNM_DOTMATCH", INT2FIX(FNM_DOTMATCH));
    rb_file_const("FNM_CASEFOLD", INT2FIX(FNM_CASEFOLD));
    rb_file_const("FNM_SYSCASE", INT2FIX(FNM_SYSCASE));
}
