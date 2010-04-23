/************************************************

  etc.c -

  $Author$
  $Date$
  created at: Tue Mar 22 18:39:19 JST 1994

************************************************/

#include "ruby.h"

#include <sys/types.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifdef HAVE_GETPWENT
#include <pwd.h>
#endif

#ifdef HAVE_GETGRENT
#include <grp.h>
#endif

#ifndef HAVE_TYPE_UID_T
#define uid_t int
#endif

static VALUE sPasswd;
#ifdef HAVE_GETGRENT
static VALUE sGroup;
#endif

#ifndef _WIN32
char *getenv();
#endif
char *getlogin();

/* Returns the short user name of the currently logged in user.
 * Unfortunately, it is often rather easy to fool getlogin().
 * Avoid getlogin() for security-related purposes.
 *
 * e.g.
 *   Etc.getlogin -> 'guest'
 */
static VALUE
etc_getlogin(obj)
    VALUE obj;
{
    char *login;

    rb_secure(4);
#ifdef HAVE_GETLOGIN
    login = getlogin();
    if (!login) login = getenv("USER");
#else
    login = getenv("USER");
#endif

    if (login)
	return rb_tainted_str_new2(login);
    return Qnil;
}

#if defined(HAVE_GETPWENT) || defined(HAVE_GETGRENT)
static VALUE
safe_setup_str(str)
    const char *str;
{
    if (str == 0) str = "";
    return rb_tainted_str_new2(str);
}
#endif

#ifdef HAVE_GETPWENT
static VALUE
setup_passwd(pwd)
    struct passwd *pwd;
{
    if (pwd == 0) rb_sys_fail("/etc/passwd");
    return rb_struct_new(sPasswd,
			 safe_setup_str(pwd->pw_name),
#ifdef HAVE_ST_PW_PASSWD
			 safe_setup_str(pwd->pw_passwd),
#endif
			 PW_UID2VAL(pwd->pw_uid),
			 PW_GID2VAL(pwd->pw_gid),
#ifdef HAVE_ST_PW_GECOS
			 safe_setup_str(pwd->pw_gecos),
#endif
			 safe_setup_str(pwd->pw_dir),
			 safe_setup_str(pwd->pw_shell),
#ifdef HAVE_ST_PW_CHANGE
			 INT2NUM(pwd->pw_change),
#endif
#ifdef HAVE_ST_PW_QUOTA
			 INT2NUM(pwd->pw_quota),
#endif
#ifdef HAVE_ST_PW_AGE
			 PW_AGE2VAL(pwd->pw_age),
#endif
#ifdef HAVE_ST_PW_CLASS
			 safe_setup_str(pwd->pw_class),
#endif
#ifdef HAVE_ST_PW_COMMENT
			 safe_setup_str(pwd->pw_comment),
#endif
#ifdef HAVE_ST_PW_EXPIRE
			 INT2NUM(pwd->pw_expire),
#endif
			 0		/*dummy*/
	);
}
#endif

/* Returns the /etc/passwd information for the user with specified integer
 * user id (uid).
 *
 * The information is returned as a Struct::Passwd; see getpwent above for
 * details.
 *
 * e.g.  * Etc.getpwuid(0) -> #<struct Struct::Passwd name="root",
 * passwd="x", uid=0, gid=0, gecos="root",dir="/root", shell="/bin/bash">
 */
static VALUE
etc_getpwuid(argc, argv, obj)
    int argc;
    VALUE *argv;
    VALUE obj;
{
#if defined(HAVE_GETPWENT)
    VALUE id;
    uid_t uid;
    struct passwd *pwd;

    rb_secure(4);
    if (rb_scan_args(argc, argv, "01", &id) == 1) {
	uid = PW_VAL2UID(id);
    }
    else {
	uid = getuid();
    }
    pwd = getpwuid(uid);
    if (pwd == 0) rb_raise(rb_eArgError, "can't find user for %d", (int)uid);
    return setup_passwd(pwd);
#else 
    return Qnil;
#endif
}

/* Returns the /etc/passwd information for the user with specified login name.
 *
 * The information is returned as a Struct::Passwd; see getpwent above for
 * details.
 *
 * e.g.  * Etc.getpwnam('root') -> #<struct Struct::Passwd name="root",
 * passwd="x", uid=0, gid=0, gecos="root",dir="/root", shell="/bin/bash">
 */
static VALUE
etc_getpwnam(obj, nam)
    VALUE obj, nam;
{
#ifdef HAVE_GETPWENT
    struct passwd *pwd;

    SafeStringValue(nam);
    pwd = getpwnam(RSTRING(nam)->ptr);
    if (pwd == 0) rb_raise(rb_eArgError, "can't find user for %s", RSTRING(nam)->ptr);
    return setup_passwd(pwd);
#else 
    return Qnil;
#endif
}

#ifdef HAVE_GETPWENT
static int passwd_blocking = 0;
static VALUE
passwd_ensure()
{
    passwd_blocking = Qfalse;
    return Qnil;
}

static VALUE
passwd_iterate()
{
    struct passwd *pw;

    setpwent();
    while (pw = getpwent()) {
	rb_yield(setup_passwd(pw));
    }
    endpwent();
    return Qnil;
}
#endif

/* Provides a convenient Ruby iterator which executes a block for each entry 
 * in the /etc/passwd file.
 *
 * The code block is passed an Struct::Passwd struct; see getpwent above for 
 * details.
 *
 * Example:
 *
 *     require 'etc'
 *
 *     Etc.passwd {|u|
 *       puts u.name + " = " + u.gecos
 *     }
 *
 */
static VALUE
etc_passwd(obj)
    VALUE obj;
{
#ifdef HAVE_GETPWENT
    struct passwd *pw;

    rb_secure(4);
    if (rb_block_given_p()) {
	if (passwd_blocking) {
	    rb_raise(rb_eRuntimeError, "parallel passwd iteration");
	}
	passwd_blocking = Qtrue;
	rb_ensure(passwd_iterate, 0, passwd_ensure, 0);
    }
    if (pw = getpwent()) {
	return setup_passwd(pw);
    }
#endif
    return Qnil;
}

/* Resets the process of reading the /etc/passwd file, so that the next call
 * to getpwent will return the first entry again.
 */
static VALUE
etc_setpwent(obj)
    VALUE obj;
{
#ifdef HAVE_GETPWENT
    setpwent();
#endif
    return Qnil;
}

/* Ends the process of scanning through the /etc/passwd file begun with
 * getpwent, and closes the file.
 */
static VALUE
etc_endpwent(obj)
    VALUE obj;
{
#ifdef HAVE_GETPWENT
    endpwent();
#endif
    return Qnil;
}

/* Returns an entry from the /etc/passwd file. The first time it is called it
 * opens the file and returns the first entry; each successive call returns 
 * the next entry, or nil if the end of the file has been reached.
 *
 * To close the file when processing is complete, call endpwent.
 *
 * Each entry is returned as a Struct::Passwd:
 *
 * - Passwd#name contains the short login name of the user as a String.
 *
 * - Passwd#passwd contains the encrypted password of the user as a String.
 *   an 'x' is returned if shadow passwords are in use. An '*' is returned
 *   if the user cannot log in using a password.
 *
 * - Passwd#uid contains the integer user ID (uid) of the user.
 *
 * - Passwd#gid contains the integer group ID (gid) of the user's primary group.
 *
 * - Passwd#gecos contains a longer String description of the user, such as 
 *   a full name. Some Unix systems provide structured information in the 
 *   gecos field, but this is system-dependent.
 *
 * - Passwd#dir contains the path to the home directory of the user as a String.
 *
 * - Passwd#shell contains the path to the login shell of the user as a String.
 */
static VALUE
etc_getpwent(obj)
    VALUE obj;
{
#ifdef HAVE_GETPWENT
    struct passwd *pw;

    if (pw = getpwent()) {
	return setup_passwd(pw);
    }
#endif
    return Qnil;
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
	rb_ary_push(mem, safe_setup_str(*tbl));
	tbl++;
    }
    return rb_struct_new(sGroup,
			 safe_setup_str(grp->gr_name),
#ifdef HAVE_ST_GR_PASSWD
			 safe_setup_str(grp->gr_passwd),
#endif
			 PW_GID2VAL(grp->gr_gid),
			 mem);
}
#endif

/* Returns information about the group with specified integer group id (gid), 
 * as found in /etc/group.
 *
 * The information is returned as a Struct::Group; see getgrent above for
 * details.
 *
 * e.g.  Etc.getgrgid(100) -> #<struct Struct::Group name="users", passwd="x",
 * gid=100, mem=["meta", "root"]>
 *
 */
static VALUE
etc_getgrgid(obj, id)
    VALUE obj, id;
{
#ifdef HAVE_GETGRENT
    gid_t gid;
    struct group *grp;

    rb_secure(4);
    gid = PW_VAL2GID(id);
    grp = getgrgid(gid);
    if (grp == 0) rb_raise(rb_eArgError, "can't find group for %d", (int)gid);
    return setup_group(grp);
#else
    return Qnil;
#endif
}

/* Returns information about the group with specified String name, as found 
 * in /etc/group.
 *
 * The information is returned as a Struct::Group; see getgrent above for
 * details.
 *
 * e.g.  Etc.getgrnam('users') -> #<struct Struct::Group name="users",
 * passwd="x", gid=100, mem=["meta", "root"]>
 *
 */
static VALUE
etc_getgrnam(obj, nam)
    VALUE obj, nam;
{
#ifdef HAVE_GETGRENT
    struct group *grp;

    rb_secure(4);
    SafeStringValue(nam);
    grp = getgrnam(RSTRING(nam)->ptr);
    if (grp == 0) rb_raise(rb_eArgError, "can't find group for %s", RSTRING(nam)->ptr);
    return setup_group(grp);
#else
    return Qnil;
#endif
}

#ifdef HAVE_GETGRENT
static int group_blocking = 0;
static VALUE
group_ensure()
{
    group_blocking = Qfalse;
    return Qnil;
}

static VALUE
group_iterate()
{
    struct group *pw;

    setgrent();
    while (pw = getgrent()) {
	rb_yield(setup_group(pw));
    }
    endgrent();
    return Qnil;
}
#endif

/* Provides a convenient Ruby iterator which executes a block for each entry 
 * in the /etc/group file.
 *
 * The code block is passed an Struct::Group struct; see getgrent above for 
 * details.
 *
 * Example:
 *
 *     require 'etc'
 *
 *     Etc.group {|g|
 *       puts g.name + ": " + g.mem.join(', ')
 *     }
 *
 */
static VALUE
etc_group(obj)
    VALUE obj;
{
#ifdef HAVE_GETGRENT
    struct group *grp;

    rb_secure(4);
    if (rb_block_given_p()) {
	if (group_blocking) {
	    rb_raise(rb_eRuntimeError, "parallel group iteration");
	}
	group_blocking = Qtrue;
	rb_ensure(group_iterate, 0, group_ensure, 0);
    }
    if (grp = getgrent()) {
	return setup_group(grp);
    }
#endif
    return Qnil;
}

/* Resets the process of reading the /etc/group file, so that the next call
 * to getgrent will return the first entry again.
 */
static VALUE
etc_setgrent(obj)
    VALUE obj;
{
#ifdef HAVE_GETGRENT
    setgrent();
#endif
    return Qnil;
}

/* Ends the process of scanning through the /etc/group file begun by 
 * getgrent, and closes the file.
 */
static VALUE
etc_endgrent(obj)
    VALUE obj;
{
#ifdef HAVE_GETGRENT
    endgrent();
#endif
    return Qnil;
}

/* Returns an entry from the /etc/group file. The first time it is called it
 * opens the file and returns the first entry; each successive call returns 
 * the next entry, or nil if the end of the file has been reached.
 *
 * To close the file when processing is complete, call endgrent.
 *
 * Each entry is returned as a Struct::Group:
 *
 * - Group#name contains the name of the group as a String.
 *
 * - Group#passwd contains the encrypted password as a String. An 'x' is
 *   returned if password access to the group is not available; an empty 
 *   string is returned if no password is needed to obtain membership of 
 *   the group.
 *
 * - Group#gid contains the group's numeric ID as an integer.
 *
 * - Group#mem is an Array of Strings containing the short login names of the 
 *   members of the group.
 */
static VALUE
etc_getgrent(obj)
    VALUE obj;
{
#ifdef HAVE_GETGRENT
    struct group *gr;

    if (gr = getgrent()) {
	return setup_group(gr);
    }
#endif
    return Qnil;
}

static VALUE mEtc;

/*
 * The etc module provides access to information from the running OS.
 *
 * Documented by mathew <meta@pobox.com>.
 */
void
Init_etc()
{
    mEtc = rb_define_module("Etc");

    rb_define_module_function(mEtc, "getlogin", etc_getlogin, 0);

    rb_define_module_function(mEtc, "getpwuid", etc_getpwuid, -1);
    rb_define_module_function(mEtc, "getpwnam", etc_getpwnam, 1);
    rb_define_module_function(mEtc, "setpwent", etc_setpwent, 0);
    rb_define_module_function(mEtc, "endpwent", etc_endpwent, 0);
    rb_define_module_function(mEtc, "getpwent", etc_getpwent, 0);
    rb_define_module_function(mEtc, "passwd", etc_passwd, 0);

    rb_define_module_function(mEtc, "getgrgid", etc_getgrgid, 1);
    rb_define_module_function(mEtc, "getgrnam", etc_getgrnam, 1);
    rb_define_module_function(mEtc, "group", etc_group, 0);
    rb_define_module_function(mEtc, "setgrent", etc_setgrent, 0);
    rb_define_module_function(mEtc, "endgrent", etc_endgrent, 0);
    rb_define_module_function(mEtc, "getgrent", etc_getgrent, 0);

    rb_global_variable(&sPasswd);
    sPasswd =  rb_struct_define("Passwd",
				"name", "passwd", "uid", "gid",
#ifdef HAVE_ST_PW_GECOS
				"gecos",
#endif
				"dir", "shell",
#ifdef HAVE_ST_PW_CHANGE
				"change",
#endif
#ifdef HAVE_ST_PW_QUOTA
				"quota",
#endif
#ifdef HAVE_ST_PW_AGE
				"age",
#endif
#ifdef HAVE_ST_PW_CLASS
				"uclass",
#endif
#ifdef HAVE_ST_PW_COMMENT
				"comment",
#endif
#ifdef HAVE_ST_PW_EXPIRE
				"expire",
#endif
				NULL);

#ifdef HAVE_GETGRENT
    rb_global_variable(&sGroup);
    sGroup = rb_struct_define("Group", "name",
#ifdef HAVE_ST_GR_PASSWD
			      "passwd",
#endif
			      "gid", "mem", NULL);
#endif
}
