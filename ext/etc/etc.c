/************************************************

  etc.c -

  $Author$
  $Date$
  created at: Tue Mar 22 18:39:19 JST 1994

************************************************/

#include "ruby.h"

#ifdef HAVE_GETPWENT
#include <pwd.h>
#endif

#ifdef HAVE_GETGRENT
#include <grp.h>
#endif

static VALUE sPasswd, sGroup;

static VALUE
etc_getlogin(obj)
    VALUE obj;
{
    char *getenv();
    char *login;

#ifdef HAVE_GETLOGIN
    char *getlogin();

    login = getlogin();
    if (!login) login = getenv("USER");
#else
    login = getenv("USER");
#endif

    if (login)
	return rb_str_new2(login);
    return Qnil;
}

#ifdef HAVE_GETPWENT
static VALUE
setup_passwd(pwd)
    struct passwd *pwd;
{
    if (pwd == 0) rb_sys_fail("/etc/passwd");
    return rb_struct_new(sPasswd,
			 rb_str_new2(pwd->pw_name),
			 rb_str_new2(pwd->pw_passwd),
			 INT2FIX(pwd->pw_uid),
			 INT2FIX(pwd->pw_gid),
#ifdef PW_GECOS
			 rb_str_new2(pwd->pw_gecos),
#endif
			 rb_str_new2(pwd->pw_dir),
			 rb_str_new2(pwd->pw_shell),
#ifdef PW_CHANGE
			 INT2FIX(pwd->pw_change),
#endif
#ifdef PW_QUOTA
			 INT2FIX(pwd->pw_quota),
#endif
#ifdef PW_AGE
			 INT2FIX(pwd->pw_age),
#endif
#ifdef PW_CLASS
			 rb_str_new2(pwd->pw_class),
#endif
#ifdef PW_COMMENT
			 rb_str_new2(pwd->pw_comment),
#endif
#ifdef PW_EXPIRE
			 INT2FIX(pwd->pw_expire),
#endif
			 0		/*dummy*/
	);
}
#endif

static VALUE
etc_getpwuid(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
#ifdef HAVE_GETPWENT
    VALUE id;
    int uid;
    struct passwd *pwd;

    if (rb_scan_args(argc, argv, "01", &id) == 1) {
	uid = NUM2INT(id);
    }
    else {
	uid = getuid();
    }
    pwd = getpwuid(uid);
    if (pwd == 0) rb_raise(rb_eArgError, "can't find user for %d", uid);
    return setup_passwd(pwd);
#else 
    return Qnil;
#endif
}

static VALUE
etc_getpwnam(obj, nam)
    VALUE obj, nam;
{
#ifdef HAVE_GETPWENT
    struct passwd *pwd;

    Check_Type(nam, T_STRING);
    pwd = getpwnam(RSTRING(nam)->ptr);
    if (pwd == 0) rb_raise(rb_eArgError, "can't find user for %s", RSTRING(nam)->ptr);
    return setup_passwd(pwd);
#else 
    return Qnil;
#endif
}

static VALUE
etc_passwd(obj)
    VALUE obj;
{
#if defined(HAVE_GETPWENT)
    struct passwd *pw;

    if (rb_iterator_p()) {
	setpwent();
	while (pw = getpwent()) {
	    rb_yield(setup_passwd(pw));
	}
	endpwent();
	return obj;
    }
    pw = getpwent();
    if (pw == 0) rb_raise(rb_eRuntimeError, "can't fetch next -- /etc/passwd");
    return setup_passwd(pw);
#else 
    return Qnil;
#endif
}

#ifdef HAVE_GETGRENT
static VALUE
setup_group(grp)
    struct group *grp;
{
    VALUE mem;
    char **tbl;

    mem = rb_ary_new();
    tbl = grp->gr_mem;
    while (*tbl) {
	rb_ary_push(mem, rb_str_new2(*tbl));
	tbl++;
    }
    return rb_struct_new(sGroup,
			 rb_str_new2(grp->gr_name),
			 rb_str_new2(grp->gr_passwd),
			 INT2FIX(grp->gr_gid),
			 mem);
}
#endif

static VALUE
etc_getgrgid(obj, id)
    VALUE obj, id;
{
#ifdef HAVE_GETGRENT
    int gid;
    struct group *grp;

    gid = NUM2INT(id);
    grp = getgrgid(gid);
    if (grp == 0) rb_raise(rb_eArgError, "can't find group for %d", gid);
    return setup_group(grp);
#else
    return Qnil;
#endif
}

static VALUE
etc_getgrnam(obj, nam)
    VALUE obj, nam;
{
#ifdef HAVE_GETGRENT
    struct group *grp;

    Check_Type(nam, T_STRING);
    grp = getgrnam(RSTRING(nam)->ptr);
    if (grp == 0) rb_raise(rb_eArgError, "can't find group for %s", RSTRING(nam)->ptr);
    return setup_group(grp);
#else
    return Qnil;
#endif
}

static VALUE
etc_group(obj)
    VALUE obj;
{
#ifdef HAVE_GETGRENT
    struct group *grp;

    if (rb_iterator_p()) {
	setgrent();
	while (grp = getgrent()) {
	    rb_yield(setup_group(grp));
	}
	endgrent();
	return obj;
    }
    return setup_group(getgrent());
#else
    return Qnil;
#endif
}

static VALUE mEtc;

void
Init_etc()
{
    mEtc = rb_define_module("Etc");

    rb_define_module_function(mEtc, "getlogin", etc_getlogin, 0);

    rb_define_module_function(mEtc, "getpwuid", etc_getpwuid, -1);
    rb_define_module_function(mEtc, "getpwnam", etc_getpwnam, 1);
    rb_define_module_function(mEtc, "passwd", etc_passwd, 0);

    rb_define_module_function(mEtc, "getgrgid", etc_getgrgid, 1);
    rb_define_module_function(mEtc, "getgrnam", etc_getgrnam, 1);
    rb_define_module_function(mEtc, "group", etc_group, 0);

    sPasswd =  rb_struct_define("Passwd",
				"name", "passwd", "uid", "gid",
				"gecos", "dir", "shell",
#ifdef PW_CHANGE
				"change",
#endif
#ifdef PW_QUOTA
				"quota",
#endif
#ifdef PW_AGE
				"age",
#endif
#ifdef PW_CLASS
				"class",
#endif
#ifdef PW_COMMENT
				"comment",
#endif
#ifdef PW_EXPIRE
				"expire",
#endif
				0);
    rb_global_variable(&sPasswd);

#ifdef HAVE_GETGRENT
    sGroup = rb_struct_define("Group", "name", "passwd", "gid", "mem", 0);
    rb_global_variable(&sGroup);
#endif
}
