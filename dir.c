/************************************************

  dir.c -

  $Author$
  $Date$
  created at: Wed Jan  5 09:51:01 JST 1994

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

#include <sys/types.h>
#include <sys/stat.h>

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#else
# define MAXPATHLEN 1024
#endif
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#if HAVE_DIRENT_H
# include <dirent.h>
# define NAMLEN(dirent) strlen((dirent)->d_name)
#elif HAVE_DIRECT_H
# include <direct.h>
# define NAMLEN(dirent) strlen((dirent)->d_name)
#else
# define dirent direct
# define NAMLEN(dirent) (dirent)->d_namlen
# if HAVE_SYS_NDIR_H
#  include <sys/ndir.h>
# endif
# if HAVE_SYS_DIR_H
#  include <sys/dir.h>
# endif
# if HAVE_NDIR_H
#  include <ndir.h>
# endif
# if defined(NT) && defined(_MSC_VER)
#  include "missing/dir.h"
# endif
#endif

#include <errno.h>
#ifdef USE_CWGUSI
# include <sys/errno.h>
#endif

#ifndef HAVE_STDLIB_H
char *getenv();
#endif

#ifndef HAVE_STRING_H
char *strchr _((char*,char));
#endif

#include <ctype.h>

#define FNM_NOESCAPE	0x01
#define FNM_PATHNAME	0x02
#define FNM_PERIOD	0x04
#define FNM_NOCASE	0x08

#define FNM_NOMATCH	1
#define FNM_ERROR	2

#define downcase(c) (nocase && isupper(c) ? tolower(c) : (c))

#if defined DOSISH
#define isdirsep(c) ((c) == '/' || (c) == '\\')
static char *
find_dirsep(s)
    char *s;
{
    while (*s) {
	if (isdirsep(*s))
	    return s;
	s++;
    }
    return 0;
}
#else
#define isdirsep(c) ((c) == '/')
#define find_dirsep(s) strchr(s, '/')
#endif

static char *
range(pat, test, flags)
    char *pat;
    char test;
    int flags;
{
    int not, ok = 0;
    int nocase = flags & FNM_NOCASE;
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

#define PERIOD(s) (period && *(s) == '.' && \
		  ((s) == string || pathname && isdirsep(*(s))))
static int
fnmatch(pat, string, flags)
    char *pat;
    char *string;
    int flags;
{
    int c;
    int test;
    char *s = string;
    int escape = !(flags & FNM_NOESCAPE);
    int pathname = flags & FNM_PATHNAME;
    int period = flags & FNM_PERIOD;
    int nocase = flags & FNM_NOCASE;

    while (c = *pat++) {
	switch (c) {
	case '?':
	    if (!*s || pathname && isdirsep(*s) || PERIOD(s))
		return FNM_NOMATCH;
	    s++;
	    break;
	case '*':
	    while ((c = *pat++) == '*')
		;

	    if (PERIOD(s))
		return FNM_NOMATCH;

	    if (!c) {
		if (pathname && find_dirsep(s))
		    return FNM_NOMATCH;
		else
		    return 0;
	    }
	    else if (pathname && isdirsep(c)) {
		s = find_dirsep(s);
		if (s)
		    break;
		return FNM_NOMATCH;
	    }

	    test = escape && c == '\\' ? *pat : c;
	    test = downcase(test);
	    pat--;
	    while (*s) {
		if ((c == '[' || downcase(*s) == test) &&
		    !fnmatch(pat, s, flags & ~FNM_PERIOD))
		    return 0;
		else if (pathname && isdirsep(*s))
		    break;
		s++;
	    }
	    return FNM_NOMATCH;
      
	case '[':
	    if (!*s || pathname && isdirsep(*s) || PERIOD(s))
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
	    if (pathname && isdirsep(c) && isdirsep(*s))
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

static void
free_dir(dir)
    DIR *dir;
{
    if (dir) closedir(dir);
}

static VALUE dir_close _((VALUE));

static VALUE
dir_s_open(dir_class, dirname)
    VALUE dir_class, dirname;
{
    VALUE obj;
    DIR *dirp;

    Check_SafeStr(dirname);

    dirp = opendir(RSTRING(dirname)->ptr);
    if (dirp == NULL) {
	if (errno == EMFILE || errno == ENFILE) {
	    rb_gc();
	    dirp = opendir(RSTRING(dirname)->ptr);
	}
	if (dirp == NULL) {
	    rb_sys_fail(RSTRING(dirname)->ptr);
	}
    }

    obj = Data_Wrap_Struct(dir_class, 0, free_dir, dirp);

    if (rb_iterator_p()) {
	return rb_ensure(rb_yield, obj, dir_close, obj);
    }

    return obj;
}

static void
dir_closed()
{
    rb_raise(rb_eIOError, "closed directory");
}

#define GetDIR(obj, dirp) {\
    Data_Get_Struct(obj, DIR, dirp);\
    if (dirp == NULL) dir_closed();\
}

static VALUE
dir_read(dir)
    VALUE dir;
{
    DIR *dirp;
    struct dirent *dp;

    GetDIR(dir, dirp);
    errno = 0;
    dp = readdir(dirp);
    if (dp)
	return rb_tainted_str_new(dp->d_name, NAMLEN(dp));
    else if (errno == 0) {	/* end of stream */
	return Qnil;
    }
    else {
	rb_sys_fail(0);
    }
    return Qnil;		/* not reached */
}

static VALUE
dir_each(dir)
    VALUE dir;
{
    DIR *dirp;
    struct dirent *dp;
    VALUE file;

    GetDIR(dir, dirp);
    for (dp = readdir(dirp); dp != NULL; dp = readdir(dirp)) {
	file = rb_tainted_str_new(dp->d_name, NAMLEN(dp));
	rb_yield(file);
    }
    return dir;
}

static VALUE
dir_tell(dir)
    VALUE dir;
{
#if !defined(__CYGWIN32__) && !defined(__BEOS__)
    DIR *dirp;
    long pos;

    GetDIR(dir, dirp);
    pos = telldir(dirp);
    return rb_int2inum(pos);
#else
    rb_notimplement();
#endif
}

static VALUE
dir_seek(dir, pos)
    VALUE dir, pos;
{
    DIR *dirp;

#if !defined(__CYGWIN32__) && !defined(__BEOS__)
    GetDIR(dir, dirp);
    seekdir(dirp, NUM2INT(pos));
    return dir;
#else
    rb_notimplement();
#endif
}

static VALUE
dir_rewind(dir)
    VALUE dir;
{
    DIR *dirp;

    GetDIR(dir, dirp);
    rewinddir(dirp);
    return dir;
}

static VALUE
dir_close(dir)
    VALUE dir;
{
    DIR *dirp;

    Data_Get_Struct(dir, DIR, dirp);
    if (dirp == NULL) dir_closed();
    closedir(dirp);
    DATA_PTR(dir) = NULL;

    return Qnil;
}

static VALUE
dir_s_chdir(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE path;
    char *dist = "";

    rb_secure(2);
    if (rb_scan_args(argc, argv, "01", &path) == 1) {
	Check_SafeStr(path);
	dist = RSTRING(path)->ptr;
    }
    else {
	dist = getenv("HOME");
	if (!dist) {
	    dist = getenv("LOGDIR");
	}
    }

    if (chdir(dist) < 0)
	rb_sys_fail(dist);

    return INT2FIX(0);
}

static VALUE
dir_s_getwd(dir)
    VALUE dir;
{
    char path[MAXPATHLEN];

#ifdef HAVE_GETCWD
    if (getcwd(path, sizeof(path)) == 0) rb_sys_fail(path);
#else
    extern char *getwd();
    if (getwd(path) == 0) rb_sys_fail(path);
#endif

    return rb_tainted_str_new2(path);
}

static VALUE
dir_s_chroot(dir, path)
    VALUE dir, path;
{
#if !defined(DJGPP) && !defined(NT) && !defined(__human68k__) && !defined(USE_CWGUSI) && !defined(__BEOS__) && !defined(__EMX__)
    rb_secure(2);
    Check_SafeStr(path);

    if (chroot(RSTRING(path)->ptr) == -1)
	rb_sys_fail(RSTRING(path)->ptr);

    return INT2FIX(0);
#else
    rb_notimplement();
    return Qnil;		/* not reached */
#endif
}

static VALUE
dir_s_mkdir(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE path, vmode;
    int mode;

    rb_secure(2);
    if (rb_scan_args(argc, argv, "11", &path, &vmode) == 2) {
	mode = NUM2INT(vmode);
    }
    else {
	mode = 0777;
    }

    Check_SafeStr(path);
#if !defined(NT) && !defined(USE_CWGUSI)
    if (mkdir(RSTRING(path)->ptr, mode) == -1)
	rb_sys_fail(RSTRING(path)->ptr);
#else
    if (mkdir(RSTRING(path)->ptr) == -1)
	rb_sys_fail(RSTRING(path)->ptr);
#endif

    return INT2FIX(0);
}

static VALUE
dir_s_rmdir(obj, dir)
    VALUE obj, dir;
{
    rb_secure(2);
    Check_SafeStr(dir);
    if (rmdir(RSTRING(dir)->ptr) < 0)
	rb_sys_fail(RSTRING(dir)->ptr);

    return Qtrue;
}

/* Return nonzero if S has any special globbing chars in it.  */
static int
has_magic(s, send)
     char *s, *send;
{
    register char *p = s;
    register char c;
    int open = 0;

    while ((c = *p++) != '\0') {
	switch (c) {
	  case '?':
	  case '*':
	    return Qtrue;

	  case '[':		/* Only accept an open brace if there is a close */
	    open++;		/* brace to match it.  Bracket expressions must be */
	    continue;	/* complete, according to Posix.2 */
	  case ']':
	    if (open)
		return Qtrue;
	    continue;

	  case '\\':
	    if (*p++ == '\0')
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
    if (len > 0 && pend[-1] == '/') {
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

#ifndef S_ISDIR
#   define S_ISDIR(m) ((m & S_IFMT) == S_IFDIR)
#endif

static void
glob(path, func, arg)
    char *path;
    void (*func)();
    VALUE arg;
{
    struct stat st;
    char *p, *m;

    if (!has_magic(path, 0)) {
	if (stat(path, &st) == 0) {
	    (*func)(path, arg);
	}
	return;
    }

    p = path;
    while (p) {
	if (*p == '/') p++;
	m = strchr(p, '/');
	if (has_magic(p, m)) {
	    char *dir, *base, *magic;
	    DIR *dirp;
	    struct dirent *dp;

	    struct d_link {
		char *path;
		struct d_link *next;
	    } *tmp, *link = 0;

	    base = extract_path(path, p);
	    if (path == p) dir = ".";
	    else dir = base;

	    dirp = opendir(dir);
	    if (dirp == NULL) {
		free(base);
		break;
	    }
	    magic = extract_elem(p);
	    for (dp = readdir(dirp); dp != NULL; dp = readdir(dirp)) {
		if (fnmatch(magic, dp->d_name, FNM_PERIOD|FNM_PATHNAME) == 0) {
		    char *fix = ALLOC_N(char, strlen(base)+NAMLEN(dp)+2);

		    sprintf(fix, "%s%s%s", base, (*base)?"/":"", dp->d_name);
		    if (!m) {
			(*func)(fix, arg);
			free(fix);
			continue;
		    }
		    tmp = ALLOC(struct d_link);
		    tmp->path = fix;
		    tmp->next = link;
		    link = tmp;
		}
	    }
	    closedir(dirp);
	    free(base);
	    free(magic);
	    while (link) {
		stat(link->path, &st); /* should success */
		if (S_ISDIR(st.st_mode)) {
		    int len = strlen(link->path);
		    int mlen = strlen(m);
		    char *t = ALLOC_N(char, len+mlen+1);

		    sprintf(t, "%s%s", link->path, m);
		    glob(t, func, arg);
		    free(t);
		}
		tmp = link;
		link = link->next;
		free(tmp->path);
		free(tmp);
	    }
	}
	p = m;
    }
}

static void
push_pattern(path, ary)
    char *path;
    VALUE ary;
{
    rb_ary_push(ary, rb_tainted_str_new2(path));
}

static void
push_globs(ary, s)
    VALUE ary;
    char *s;
{
    glob(s, push_pattern, ary);
}

static void
push_braces(ary, s)
    VALUE ary;
    char *s;
{
    char buffer[MAXPATHLEN], *buf = buffer;
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

    if (lbrace) {
	int len = strlen(s);
	if (len >= MAXPATHLEN)
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
	    push_braces(ary, buf);
	}
	if (buf != buffer)
	    free(buf);
    }
    else {
	push_globs(ary, s);
    }
}

#define isdelim(c) ((c)==' '||(c)=='\t'||(c)=='\n'||(c)=='\0')

static VALUE
dir_s_glob(dir, str)
    VALUE dir, str;
{
    char *p, *pend;
    char buffer[MAXPATHLEN], *buf = buffer;
    char *t;
    int nest;
    VALUE ary;

    Check_SafeStr(str);
    ary = rb_ary_new();
    if (RSTRING(str)->len >= MAXPATHLEN)
	buf = xmalloc(RSTRING(str)->len + 1);

    p = RSTRING(str)->ptr;
    pend = p + RSTRING(str)->len;

    while (p < pend) {
	t = buf;
	nest = 0;
	while (p < pend && isdelim(*p)) p++;
	while (p < pend && !isdelim(*p)) {
	    if (*p == '{') nest+=2;
	    if (*p == '}') nest+=3;
	    *t++ = *p++;
	}
	*t = '\0';
	if (nest == 0) {
	    push_globs(ary, buf);
	}
	else if (nest % 5 == 0) {
	    push_braces(ary, buf);
	}
	/* else unmatched braces */
    }
    if (buf != buffer)
	free(buf);
    return ary;
}

static VALUE
dir_foreach(io, dirname)
    VALUE io, dirname;
{
    VALUE dir;

    dir = rb_funcall(rb_cDir, rb_intern("open"), 1, dirname);
    return rb_ensure(dir_each, dir, dir_close, dir);
}

static VALUE
dir_entries(io, dirname)
    VALUE io, dirname;
{
    VALUE dir;

    dir = rb_funcall(rb_cDir, rb_intern("open"), 1, dirname);
    return rb_ensure(rb_Array, dir, dir_close, dir);
}

void
Init_Dir()
{
    rb_cDir = rb_define_class("Dir", rb_cObject);

    rb_include_module(rb_cDir, rb_mEnumerable);

    rb_define_singleton_method(rb_cDir, "new", dir_s_open, 1);
    rb_define_singleton_method(rb_cDir, "open", dir_s_open, 1);
    rb_define_singleton_method(rb_cDir, "foreach", dir_foreach, 1);
    rb_define_singleton_method(rb_cDir, "entries", dir_entries, 1);

    rb_define_method(rb_cDir,"read", dir_read, 0);
    rb_define_method(rb_cDir,"each", dir_each, 0);
    rb_define_method(rb_cDir,"rewind", dir_rewind, 0);
    rb_define_method(rb_cDir,"tell", dir_tell, 0);
    rb_define_method(rb_cDir,"seek", dir_seek, 1);
    rb_define_method(rb_cDir,"close", dir_close, 0);

    rb_define_singleton_method(rb_cDir,"chdir", dir_s_chdir, -1);
    rb_define_singleton_method(rb_cDir,"getwd", dir_s_getwd, 0);
    rb_define_singleton_method(rb_cDir,"pwd", dir_s_getwd, 0);
    rb_define_singleton_method(rb_cDir,"chroot", dir_s_chroot, 1);
    rb_define_singleton_method(rb_cDir,"mkdir", dir_s_mkdir, -1);
    rb_define_singleton_method(rb_cDir,"rmdir", dir_s_rmdir, 1);
    rb_define_singleton_method(rb_cDir,"delete", dir_s_rmdir, 1);
    rb_define_singleton_method(rb_cDir,"unlink", dir_s_rmdir, 1);

    rb_define_singleton_method(rb_cDir,"glob", dir_s_glob, 1);
    rb_define_singleton_method(rb_cDir,"[]", dir_s_glob, 1);
}
