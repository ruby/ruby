/************************************************

  dir.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:49 $
  created at: Wed Jan  5 09:51:01 JST 1994

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"

#include <sys/types.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <sys/param.h>

/* unistd.h defines _POSIX_VERSION on POSIX.1 systems.  */
#if defined(DIRENT) || defined(_POSIX_VERSION)
#include <dirent.h>
#define NLENGTH(dirent) (strlen((dirent)->d_name))
#else /* not (DIRENT or _POSIX_VERSION) */
#define dirent direct
#define NLENGTH(dirent) ((dirent)->d_namlen)
#ifdef SYSNDIR
#include <sys/ndir.h>
#endif /* SYSNDIR */
#ifdef SYSDIR
#include <sys/dir.h>
#endif /* SYSDIR */
#ifdef NDIR
#include <ndir.h>
#endif /* NDIR */
#endif /* not (DIRENT or _POSIX_VERSION) */

static VALUE C_Dir;

static void
free_dir(dir)
    DIR **dir;
{
    if (dir) closedir(*dir);
}

static VALUE
Fdir_open(dir_class, dirname)
    VALUE dir_class;
    struct RString *dirname;
{
    VALUE obj;
    DIR *dirp, **d;

    Check_Type(dirname, T_STRING);
    
    dirp = opendir(dirname->ptr);
    if (dirp == NULL) Fail("Can't open directory %s", dirname->ptr);

    GC_LINK;
    GC_PRO3(obj, obj_alloc(dir_class));
    Make_Data_Struct(obj, "dir", DIR*, Qnil, free_dir, d);
    *d = dirp;
    /* use memcpy(d, dirp, sizeof(DIR)) if needed.*/
    GC_UNLINK;

    return obj;
}

static void
closeddir()
{
    Fail("closed directory");
}

#define GetDIR(obj, dirp) {\
    DIR **_dp;\
    Get_Data_Struct(obj, "dir", DIR*, _dp);\
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
	rb_lastline = str_new(dp->d_name, NLENGTH(dp));
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

    Get_Data_Struct(dir, "dir", DIR*, dirpp);
    if (*dirpp == NULL) Fail("already closed directory");
    closedir(*dirpp);
    *dirpp = NULL;

    return Qnil;
}

char *getenv();

static VALUE
Fdir_chdir(obj, args)
    VALUE obj, args;
{
    VALUE path;
    char *dist = "";

    rb_scan_args(args, "01", args, &path);
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

    return Qnil;
}

static VALUE
Fdir_getwd(dir)
    VALUE dir;
{
    extern char *getwd();
    char path[MAXPATHLEN];

    if (getwd(path) == 0) Fail(path);

    return str_new2(path);
}

static VALUE
Fdir_chroot(dir, path)
    VALUE dir, path;
{
    Check_Type(path, T_STRING);

    if (chroot(RSTRING(path)->ptr) == -1)
	rb_sys_fail(Qnil);

    return Qnil;
}

static VALUE
Fdir_mkdir(obj, args)
    VALUE obj, args;
{
    VALUE path, vmode;
    int mode;

    if (rb_scan_args(args, "11", &path, &vmode) == 2) {
	mode = NUM2INT(vmode);
    }
    else {
	mode = 0777;
    }

    Check_Type(path, T_STRING);
    if (mkdir(RSTRING(path)->ptr, mode) == -1)
	rb_sys_fail(RSTRING(path)->ptr);

    return Qnil;
}

static VALUE
Fdir_rmdir(obj, dir)
    VALUE obj;
    struct RString *dir;
{
    Check_Type(dir, T_STRING);
    if (rmdir(dir->ptr) < 0)
	rb_sys_fail(dir->ptr);

    return TRUE;
}

Init_Dir()
{
    extern VALUE M_Enumerable;

    C_Dir = rb_define_class("Directory", C_Object);
    rb_name_class(C_Dir, rb_intern("Dir")); /* alias */

    rb_include_module(C_Dir, M_Enumerable);

    rb_define_single_method(C_Dir, "open", Fdir_open, 1);

    rb_define_method(C_Dir,"each", Fdir_each, 0);
    rb_define_method(C_Dir,"rewind", Fdir_rewind, 0);
    rb_define_method(C_Dir,"tell", Fdir_tell, 0);
    rb_define_method(C_Dir,"seek", Fdir_seek, 1);
    rb_define_method(C_Dir,"close", Fdir_close, 0);

    rb_define_single_method(C_Dir,"chdir", Fdir_chdir, -2);
    rb_define_single_method(C_Dir,"getwd", Fdir_getwd, 0);
    rb_define_alias(C_Dir, "pwd", "getwd");
    rb_define_single_method(C_Dir,"chroot", Fdir_chroot, 1);
    rb_define_single_method(C_Dir,"mkdir", Fdir_mkdir, -2);
    rb_define_single_method(C_Dir,"rmdir", Fdir_rmdir, 1);
    rb_define_alias(C_Dir, "delete", "rmdir");
    rb_define_alias(C_Dir, "unlink", "rmdir");
}
