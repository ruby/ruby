/************************************************

  dir.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:28 $
  created at: Wed Jan  5 09:51:01 JST 1994

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include <sys/param.h>
#include "ruby.h"

#include <sys/types.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#else
char *getenv();
#endif

#if HAVE_DIRENT_H
# include <dirent.h>
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
#endif

static VALUE C_Dir;
static ID id_dir;

static void
free_dir(dir)
    DIR **dir;
{
    if (dir && *dir) closedir(*dir);
}

static VALUE
Sdir_open(dir_class, dirname)
    VALUE dir_class;
    struct RString *dirname;
{
    VALUE obj;
    DIR *dirp, **d;

    Check_Type(dirname, T_STRING);

    dirp = opendir(dirname->ptr);
    if (dirp == NULL) Fail("Can't open directory %s", dirname->ptr);

    obj = obj_alloc(dir_class);
    if (!id_dir) id_dir = rb_intern("dir");
    Make_Data_Struct(obj, id_dir, DIR*, Qnil, free_dir, d);
    *d = dirp;

    return obj;
}

static void
closeddir()
{
    Fail("closed directory");
}

#define GetDIR(obj, dirp) {\
    DIR **_dp;\
    if (!id_dir) id_dir = rb_intern("dir");\
    Get_Data_Struct(obj, id_dir, DIR*, _dp);\
    dirp = *_dp;\
    if (dirp == NULL) closeddir();\
}

static VALUE
Fdir_each(dir)
    VALUE dir;
{
    extern VALUE rb_lastline;
    DIR *dirp;
    struct dirent *dp;

    GetDIR(dir, dirp);
    for (dp = readdir(dirp); dp != NULL; dp = readdir(dirp)) {
	rb_lastline = str_new(dp->d_name, NAMLEN(dp));
	rb_yield(rb_lastline);
    }
    return dir;
}

static VALUE
Fdir_tell(dir)
    VALUE dir;
{
    DIR *dirp;
    int pos;

    GetDIR(dir, dirp);
    pos = telldir(dirp);
    return int2inum(pos);
}

static VALUE
Fdir_seek(dir, pos)
    VALUE dir, pos;
{
    DIR *dirp;

    GetDIR(dir, dirp);
    seekdir(dirp, NUM2INT(pos));
    return dir;
}

static VALUE
Fdir_rewind(dir)
    VALUE dir;
{
    DIR *dirp;

    GetDIR(dir, dirp);
    rewinddir(dirp);
    return dir;
}

static VALUE
Fdir_close(dir)
    VALUE dir;
{
    DIR **dirpp;

    Get_Data_Struct(dir, id_dir, DIR*, dirpp);
    if (*dirpp == NULL) Fail("already closed directory");
    closedir(*dirpp);
    *dirpp = NULL;

    return Qnil;
}

static VALUE
Sdir_chdir(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
    VALUE path;
    char *dist = "";

    rb_scan_args(argc, argv, "01", &path);
    if (path) {
	Check_Type(path, T_STRING);
	dist = RSTRING(path)->ptr;
    }
    else {
	dist = getenv("HOME");
	if (!dist) {
	    dist = getenv("LOGDIR");
	}
    }

    if (chdir(dist) < 0)
	rb_sys_fail(Qnil);

    return INT2FIX(0);
}

static VALUE
Sdir_getwd(dir)
    VALUE dir;
{
    extern char *getwd();
    char path[MAXPATHLEN];

#ifdef HAVE_GETCWD
    if (getcwd(path, sizeof(path)) == 0) Fail(path);
#else
    if (getwd(path) == 0) Fail(path);
#endif

    return str_new2(path);
}

static VALUE
Sdir_chroot(dir, path)
    VALUE dir, path;
{
    Check_Type(path, T_STRING);

    if (chroot(RSTRING(path)->ptr) == -1)
	rb_sys_fail(Qnil);

    return INT2FIX(0);
}

static VALUE
Sdir_mkdir(argc, argv, obj)
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

    Check_Type(path, T_STRING);
    if (mkdir(RSTRING(path)->ptr, mode) == -1)
	rb_sys_fail(RSTRING(path)->ptr);

    return INT2FIX(0);
}

static VALUE
Sdir_rmdir(obj, dir)
    VALUE obj;
    struct RString *dir;
{
    Check_Type(dir, T_STRING);
    if (rmdir(dir->ptr) < 0)
	rb_sys_fail(dir->ptr);

    return TRUE;
}

#define isdelim(c) ((c)==' '||(c)=='\t'||(c)=='\n'||(c)=='\0')

char **glob_filename();

static void
push_globs(ary, s)
    VALUE ary;
    char *s;
{
    char **fnames, **ff;

    fnames = glob_filename(s);
    if (fnames == (char**)-1) rb_sys_fail(s);
    ff = fnames;
    while (*ff) {
	ary_push(ary, str_new2(*ff));
	free(*ff);
	ff++;
    }
    free(fnames);
}

static int
push_braces(ary, s)
    VALUE ary;
    char *s;
{
    char buf[MAXPATHLEN];
    char *p, *t, *b;
    char *lbrace, *rbrace;

    p = s;
    lbrace = rbrace = Qnil;
    while (*p) {
	if (*p == '{' && !lbrace) lbrace = p;
	if (*p == '}' && lbrace) rbrace = p;
	*p++;
    }

    if (lbrace) {
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
    }
    else {
	push_globs(ary, s);
    }
}

static VALUE
Sdir_glob(dir, str)
    VALUE dir;
    struct RString *str;
{
    char *p, *pend;
    char buf[MAXPATHLEN];
    char *t, *t0;
    int nest;
    VALUE ary;

    Check_Type(str, T_STRING);

    ary = ary_new();

    p = str->ptr;
    pend = p + str->len;

    while (p < pend) {
	t = buf;
	while (p < pend && isdelim(*p)) p++;
	while (p < pend && !isdelim(*p)) {
	    *t++ = *p++;
	}
	*t = '\0';
	t0 = buf;
	nest = 0;
	while (t0 < t) {
	    if (*t0 == '{') nest+=2;
	    if (*t0 == '}') nest+=3;
	    t0++;
	}
	if (nest == 0) {
	    push_globs(ary, buf);
	}
	else if (nest % 5 == 0) {
	    push_braces(ary, buf);
	}
	/* else unmatched braces */
    }
    return ary;
}

Init_Dir()
{
    extern VALUE M_Enumerable;

    C_Dir = rb_define_class("Dir", C_Object);

    rb_include_module(C_Dir, M_Enumerable);

    rb_define_single_method(C_Dir, "open", Sdir_open, 1);

    rb_define_method(C_Dir,"each", Fdir_each, 0);
    rb_define_method(C_Dir,"rewind", Fdir_rewind, 0);
    rb_define_method(C_Dir,"tell", Fdir_tell, 0);
    rb_define_method(C_Dir,"seek", Fdir_seek, 1);
    rb_define_method(C_Dir,"close", Fdir_close, 0);

    rb_define_single_method(C_Dir,"chdir", Sdir_chdir, -1);
    rb_define_single_method(C_Dir,"getwd", Sdir_getwd, 0);
    rb_define_single_method(C_Dir,"pwd", Sdir_getwd, 0);
    rb_define_single_method(C_Dir,"chroot", Sdir_chroot, 1);
    rb_define_single_method(C_Dir,"mkdir", Sdir_mkdir, -1);
    rb_define_single_method(C_Dir,"rmdir", Sdir_rmdir, 1);
    rb_define_single_method(C_Dir,"delete", Sdir_rmdir, 1);
    rb_define_single_method(C_Dir,"unlink", Sdir_rmdir, 1);

    rb_define_single_method(C_Dir,"glob", Sdir_glob, 1);
    rb_define_single_method(C_Dir,"[]", Sdir_glob, 1);
}
