/**********************************************************************

  dln_find.c -

  $Author$
  created at: Tue Jan 18 17:05:06 JST 1994

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#ifdef RUBY_EXPORT
#include "ruby/ruby.h"
#define dln_warning rb_warning
#define dln_warning_arg
#else
#define dln_warning fprintf
#define dln_warning_arg stderr,
#endif
#include "dln.h"

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#ifdef USE_DLN_A_OUT
char *dln_argv0;
#endif

#if defined(HAVE_ALLOCA_H)
#include <alloca.h>
#endif

#ifdef HAVE_STRING_H
# include <string.h>
#else
# include <strings.h>
#endif

#include <stdio.h>
#if defined(_WIN32)
#include "missing/file.h"
#endif
#include <sys/types.h>
#include <sys/stat.h>

#ifndef S_ISDIR
#   define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#if !defined(_WIN32) && !HAVE_DECL_GETENV
char *getenv();
#endif

static const char default_path[] =
    "/usr/local/bin" PATH_SEP
    "/usr/ucb" PATH_SEP
    "/usr/bin" PATH_SEP
    "/bin" PATH_SEP
    ".";

static char *dln_find_1(const char *fname, const char *path, char *buf, size_t size, int exe_flag,
			dln_alloc_func alloc_func, void *alloc_arg
			DLN_FIND_EXTRA_ARG_DECL);

static char *
fixed_buf(char *ptr, size_t size, void *arg)
{
    return NULL;
}

char *
dln_realloc(char *ptr, size_t size, void *arg)
{
    ptr = realloc(ptr, size);
    if (arg) *(char **)arg = ptr;
    return ptr;
}

char *
dln_find_exe_r(const char *fname, const char *path, char *buf, size_t size
	       DLN_FIND_EXTRA_ARG_DECL)
{
    char *envpath = 0;

    if (!path) {
	path = getenv(PATH_ENV);
	if (path) path = envpath = strdup(path);
    }

    if (!path) {
	path = default_path;
    }
    buf = dln_find_1(fname, path, buf, size, 1, fixed_buf, NULL DLN_FIND_EXTRA_ARG);
    if (envpath) free(envpath);
    return buf;
}

char *
dln_find_file_r(const char *fname, const char *path, char *buf, size_t size
		DLN_FIND_EXTRA_ARG_DECL)
{
    if (!path) path = ".";
    return dln_find_1(fname, path, buf, size, 0, fixed_buf, NULL DLN_FIND_EXTRA_ARG);
}

char *
dln_find_exe_alloc(const char *fname, const char *path,
		   dln_alloc_func alloc_func, void *alloc_arg
		   DLN_FIND_EXTRA_ARG_DECL)
{
    char *envpath = 0;
    char *buf;

    if (!path) {
	path = getenv(PATH_ENV);
	if (path) path = envpath = strdup(path);
    }

    if (!path) {
	path = default_path;
    }
    buf = dln_find_1(fname, path, NULL, 0, 1, alloc_func, alloc_arg DLN_FIND_EXTRA_ARG);
    if (envpath) free(envpath);
    return buf;
}

char *
dln_find_file_alloc(const char *fname, const char *path,
		   dln_alloc_func alloc_func, void *alloc_arg
		    DLN_FIND_EXTRA_ARG_DECL)
{
    if (!path) path = ".";
    return dln_find_1(fname, path, NULL, 0, 0, alloc_func, alloc_arg DLN_FIND_EXTRA_ARG);
}

static void
pathname_too_long(const char *dname, size_t dnlen, const char *fname, size_t fnlen)
{
    const char *fnend = "";
    if (fnlen > 100) {
	fnlen = 100;
	fnend = "...";
    }
    if (dname) {
	const char *dnend = "";
	if (dnlen > 100) {
	    dnlen = 100;
	    dnend = "...";
	}
	dln_warning(dln_warning_arg
		    "openpath: pathname too long (ignored)\n"
		    "\tDirectory \"%.*s\"%s\n"
		    "\tFile \"%.*s\"%s\n",
		    (int)dnlen, dname, dnend,
		    (int)fnlen, fname, fnend);
    }
    else {
	dln_warning(dln_warning_arg
		    "openpath: pathname too long (ignored)\n"
		    "\tFile \"%.*s\"%s\n",
		    (int)fnlen, fname, fnend);
    }
}

static char *
dln_find_1(const char *fname, const char *path, char *fbuf, size_t size,
	   int exe_flag /* non 0 if looking for executable. */,
	   dln_alloc_func alloc_func, void *alloc_arg
	   DLN_FIND_EXTRA_ARG_DECL)
{
    register const char *dp;
    register const char *ep;
    register char *bp;
    struct stat st;
    size_t i, fnlen, fspace;
    const size_t size0 = size;
    size_t newsize;
#ifdef DOSISH
    static const char extension[][5] = {
	EXECUTABLE_EXTS,
    };
    size_t j;
    int is_abs = 0, has_path = 0;
    const char *ext = 0;
    enum {ext_size = sizeof(extension[0])};
#else
    enum {ext = 0, ext_size = 0};
#endif
    const char *p = fname;

#define PATHNAME_TOO_LONG() pathname_too_long(fbuf, bp-fbuf, fname, fnlen)
#define RETURN_IF(expr) if (expr) return (char *)fname;

#define INSERT(str, length, extra) do { 		\
	if (!fbuf || fspace < (length)) {		\
	    ptrdiff_t pos = bp - fbuf;			\
	    if (size0) goto toolong;			\
	    newsize = (length) + pos + extra + 2;	\
	    if (exe_flag && !ext) newsize += ext_size;	\
	    bp = alloc_func(fbuf, newsize, alloc_arg);	\
	    if (!bp) goto toolong;			\
	    fspace = (size = newsize) - pos - 2;	\
	    fbuf = bp;					\
	    bp += pos;					\
	}						\
	fspace -= (length);				\
	memcpy(bp, (str), (length));			\
	bp += (length);					\
    } while (0)

    if (!size) fbuf = 0;
    RETURN_IF(!fname);
    fnlen = strlen(fname);
    if (size && fnlen >= size) {
	pathname_too_long(NULL, 0, fname, fnlen);
	return NULL;
    }
#ifdef DOSISH
# ifndef CharNext
# define CharNext(p) ((p)+1)
# endif
# ifdef DOSISH_DRIVE_LETTER
    if (((p[0] | 0x20) - 'a') < 26  && p[1] == ':') {
	p += 2;
	is_abs = 1;
    }
# endif
    switch (*p) {
      case '/': case '\\':
	is_abs = 1;
	p++;
    }
    has_path = is_abs;
    while (*p) {
	switch (*p) {
	  case '/': case '\\':
	    has_path = 1;
	    ext = 0;
	    p++;
	    break;
	  case '.':
	    ext = p;
	    p++;
	    break;
	  default:
	    p = CharNext(p);
	}
    }
    if (ext) {
	for (j = 0; STRCASECMP(ext, extension[j]); ) {
	    if (++j == sizeof(extension) / sizeof(extension[0])) {
		ext = 0;
		break;
	    }
	}
    }
    ep = bp = 0;
    if (!exe_flag) {
	RETURN_IF(is_abs);
    }
    else if (has_path) {
	RETURN_IF(ext);
	fspace = size;
	i = p - fname;
	ep = p;
	INSERT(fname, i + 1, 0);
	goto needs_extension;
    }
    p = fname;
#endif

    if (*p == '.' && *++p == '.') ++p;
    RETURN_IF(*p == '/');
    RETURN_IF(exe_flag && strchr(fname, '/'));

#undef RETURN_IF

    dp = path;
    do {
	register size_t l;

	/* extract a component */
	ep = strchr(dp, PATH_SEP[0]);
	if (ep == NULL)
	    ep = dp+strlen(dp);

	/* find the length of that component */
	l = ep - dp;
	bp = fbuf;
	fspace = size ? size - 2 : 0;
	if (l > 0) {
	    /*
	    **	If the length of the component is zero length,
	    **	start from the current directory.  If the
	    **	component begins with "~", start from the
	    **	user's $HOME environment variable.  Otherwise
	    **	take the path literally.
	    */

	    if (*dp == '~' && (l == 1 ||
#if defined(DOSISH)
			       dp[1] == '\\' ||
#endif
			       dp[1] == '/')) {
		char *home;

		home = getenv("HOME");
		if (home != NULL) {
		    i = strlen(home);
		    INSERT(home, i, fnlen);
		}
		dp++;
		l--;
	    }
	    if (l > 0) {
		INSERT(dp, l, fnlen);
	    }

	    /* add a "/" between directory and filename */
	    if (ep[-1] != '/')
		*bp++ = '/';
	}

	/* now append the file name */
	INSERT(fname, fnlen, 0);

#if defined(DOSISH)
	if (exe_flag && !ext) {
	  needs_extension:
	    for (j = 0; j < sizeof(extension) / sizeof(extension[0]); j++) {
		if (fspace < strlen(extension[j])) {
		    PATHNAME_TOO_LONG();
		    continue;
		}
		strlcpy(bp + i, extension[j], fspace);
		if (stat(fbuf, &st) == 0)
		    return fbuf;
	    }
	    continue;
	}
#endif
	*bp = '\0';

#ifndef S_ISREG
# define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#endif
	if (stat(fbuf, &st) == 0 && S_ISREG(st.st_mode)) {
	    if (exe_flag == 0) return fbuf;
	    /* looking for executable */
	    if (eaccess(fbuf, X_OK) == 0) return fbuf;
	}
	if (0) {
	  toolong:
	    PATHNAME_TOO_LONG();
	}
    } while (dp = ep + 1, *ep);

    return NULL;
}
