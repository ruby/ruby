/************************************************

  etc.c -

  $Author: matz $
  $Date: 1994/06/17 14:23:49 $
  created at: Tue Mar 22 18:39:19 JST 1994

************************************************/

#include "ruby.h"
#include <pwd.h>
#include <grp.h>

char *getlogin();

static VALUE
Fetc_getlogin(obj)
    VALUE obj;
{
    char *login = getlogin();

    if (login)
	return str_new2(getlogin());
    return Qnil;
}

static VALUE
setup_passwd(pwd)
    struct passwd *pwd;
{
    VALUE pw, name, passwd, gecos, dir, shell;
#ifdef PW_CLASS
    VALUE class;
#endif
#ifdef PW_COMMENT
    VALUE comment;
#endif

    if (pwd == Qnil) rb_sys_fail("/etc/passwd");
    GC_LINK;
    GC_PRO3(pw, str_new2(pwd->pw_name));
    GC_PRO3(passwd, str_new2(pwd->pw_passwd));
    GC_PRO3(gecos, str_new2(pwd->pw_gecos));
    GC_PRO3(dir, str_new2(pwd->pw_dir));
    GC_PRO3(shell, str_new2(pwd->pw_shell));
#ifdef PW_CLASS
    GC_PRO3(class, str_new2(pwd->pw_class));
#endif
#ifdef PW_COMMENT
    GC_PRO3(comment, str_new2(pwd->pw_comment));
#endif

    pw = struct_new("passwd",
		    "name", name,
		    "passwd", passwd,
		    "uid", INT2FIX(pwd->pw_uid),
		    "gid", INT2FIX(pwd->pw_gid),
		    "gecos", gecos,
		    "dir", dir,
		    "shell", shell,
#ifdef PW_CHANGE
		    "change", INT2FIX(pwd->pw_change),
#endif
#ifdef PW_QUOTA
		    "quota", INT2FIX(pwd->pw_quota),
#endif
#ifdef PW_AGE
		    "age", INT2FIX(pwd->pw_age),
#endif
#ifdef PW_CLASS
		    "class", class,
#endif
#ifdef PW_COMMENT
		    "comment", comment,
#endif
#ifdef PW_EXPIRE
		    "expire", INT2FIX(pwd->pw_expire),
#endif
		    Qnil);
    GC_UNLINK;

    return pw;
}

static VALUE
Fetc_getpwuid(obj, args)
    VALUE obj, args;
{
    VALUE id;
    int uid;
    struct passwd *pwd;

    if (rb_scan_args(args, "01", &id) == 1) {
	uid = NUM2INT(id);
    }
    else {
	uid = getuid();
    }
    pwd = getpwuid(uid);
    if (pwd == Qnil) Fail("can't find user for %d", uid);
    return setup_passwd(pwd);
}

static VALUE
Fetc_getpwnam(obj, nam)
    VALUE obj, nam;
{
    struct passwd *pwd;

    Check_Type(nam, T_STRING);
    pwd = getpwnam(RSTRING(nam)->ptr);
    if (pwd == Qnil) Fail("can't find user for %s", RSTRING(nam)->ptr);
    return setup_passwd(pwd);
}

static VALUE
Fetc_passwd(obj)
    VALUE obj;
{
    struct passwd *pw;

    if (iterator_p()) {
	setpwent();
	while (pw = getpwent()) {
	    rb_yield(setup_passwd(pw));
	}
	endpwent();
	return obj;
    }
    pw = getpwent();
    if (pw == Qnil) Fail("can't fetch next -- /etc/passwd");
    return setup_passwd(pw);
}

static VALUE
setup_group(grp)
    struct group *grp;
{
    VALUE mem, obj, name, passwd;
    char **tbl;

    GC_LINK;
    GC_PRO3(mem, ary_new());
    tbl = grp->gr_mem;
    while (*tbl) {
	Fary_push(mem, str_new2(*tbl));
	tbl++;
    }
    GC_PRO3(name, str_new2(grp->gr_name));
    GC_PRO3(passwd, str_new2(grp->gr_passwd));
    obj = struct_new("group",
		     "name", name, 
		     "passwd", passwd,
		     "gid", INT2FIX(grp->gr_gid),
		     "mem", mem,
		     Qnil);
    GC_UNLINK;

    return obj;
}

static VALUE
Fetc_getgrgid(obj, id)
    VALUE obj, id;
{
    int gid;
    struct group *grp;

    gid = NUM2INT(id);
    grp = getgrgid(gid);
    if (grp == Qnil) Fail("can't find group for %d", gid);
    return setup_group(grp);
}

static VALUE
Fetc_getgrnam(obj, nam)
    VALUE obj, nam;
{
    struct group *grp;

    Check_Type(nam, T_STRING);
    grp = getgrnam(RSTRING(nam)->ptr);
    if (grp == Qnil) Fail("can't find group for %s", RSTRING(nam)->ptr);
    return setup_group(grp);
}

static VALUE
Fetc_group(obj)
    VALUE obj;
{
    struct group *grp;

    if (iterator_p()) {
	setgrent();
	while (grp = getgrent()) {
	    rb_yield(setup_group(grp));
	}
	endgrent();
	return obj;
    }
    return setup_group(getgrent());
}

VALUE M_Etc;

Init_Etc()
{
    M_Etc = rb_define_module("Etc");

    rb_define_mfunc(M_Etc, "getlogin", Fetc_getlogin, 0);

    rb_define_mfunc(M_Etc, "getpwuid", Fetc_getpwuid, -2);
    rb_define_mfunc(M_Etc, "getpwnam", Fetc_getpwnam, 1);
    rb_define_mfunc(M_Etc, "passwd", Fetc_passwd, 0);

    rb_define_mfunc(M_Etc, "getgrgid", Fetc_getgrgid, 1);
    rb_define_mfunc(M_Etc, "getgrnam", Fetc_getgrnam, 1);
    rb_define_mfunc(M_Etc, "group", Fetc_group, 0);
}
