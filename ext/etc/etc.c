/************************************************

  etc.c -

  $Author$
  created at: Tue Mar 22 18:39:19 JST 1994

************************************************/

#include "ruby.h"
#include "ruby/encoding.h"
#include "ruby/io.h"

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

#include <errno.h>

#ifdef HAVE_SYS_UTSNAME_H
#include <sys/utsname.h>
#endif

#ifdef HAVE_SCHED_GETAFFINITY
#include <sched.h>
#endif

static VALUE sPasswd;
#ifdef HAVE_GETGRENT
static VALUE sGroup;
#endif

#ifdef _WIN32
#include <shlobj.h>
#ifndef CSIDL_COMMON_APPDATA
#define CSIDL_COMMON_APPDATA 35
#endif
#define HAVE_UNAME 1
#endif

#ifndef _WIN32
char *getenv();
#endif
char *getlogin();

#include "constdefs.h"

/* call-seq:
 *	getlogin	->  String
 *
 * Returns the short user name of the currently logged in user.
 * Unfortunately, it is often rather easy to fool ::getlogin.
 *
 * Avoid ::getlogin for security-related purposes.
 *
 * If ::getlogin fails, try ::getpwuid.
 *
 * See the unix manpage for <code>getpwuid(3)</code> for more detail.
 *
 * e.g.
 *   Etc.getlogin -> 'guest'
 */
static VALUE
etc_getlogin(VALUE obj)
{
    char *login;

#ifdef HAVE_GETLOGIN
    login = getlogin();
    if (!login) login = getenv("USER");
#else
    login = getenv("USER");
#endif

    if (login) {
#ifdef _WIN32
	rb_encoding *extenc = rb_utf8_encoding();
#else
	rb_encoding *extenc = rb_locale_encoding();
#endif
	return rb_external_str_new_with_enc(login, strlen(login), extenc);
    }

    return Qnil;
}

#if defined(HAVE_GETPWENT) || defined(HAVE_GETGRENT)
static VALUE
safe_setup_str(const char *str)
{
    if (str == 0) str = "";
    return rb_tainted_str_new2(str);
}

static VALUE
safe_setup_locale_str(const char *str)
{
    if (str == 0) str = "";
    return rb_locale_str_new_cstr(str);
}

static VALUE
safe_setup_filesystem_str(const char *str)
{
    if (str == 0) str = "";
    return rb_filesystem_str_new_cstr(str);
}
#endif

#ifdef HAVE_GETPWENT
static VALUE
setup_passwd(struct passwd *pwd)
{
    if (pwd == 0) rb_sys_fail("/etc/passwd");
    return rb_struct_new(sPasswd,
			 safe_setup_locale_str(pwd->pw_name),
#ifdef HAVE_STRUCT_PASSWD_PW_PASSWD
			 safe_setup_str(pwd->pw_passwd),
#endif
			 UIDT2NUM(pwd->pw_uid),
			 GIDT2NUM(pwd->pw_gid),
#ifdef HAVE_STRUCT_PASSWD_PW_GECOS
			 safe_setup_locale_str(pwd->pw_gecos),
#endif
			 safe_setup_filesystem_str(pwd->pw_dir),
			 safe_setup_filesystem_str(pwd->pw_shell),
#ifdef HAVE_STRUCT_PASSWD_PW_CHANGE
			 INT2NUM(pwd->pw_change),
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_QUOTA
			 INT2NUM(pwd->pw_quota),
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_AGE
			 PW_AGE2VAL(pwd->pw_age),
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_CLASS
			 safe_setup_locale_str(pwd->pw_class),
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_COMMENT
			 safe_setup_locale_str(pwd->pw_comment),
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_EXPIRE
			 INT2NUM(pwd->pw_expire),
#endif
			 0		/*dummy*/
	);
}
#endif

/* call-seq:
 *	getpwuid(uid)	->  Passwd
 *
 * Returns the /etc/passwd information for the user with the given integer +uid+.
 *
 * The information is returned as a Passwd struct.
 *
 * If +uid+ is omitted, the value from <code>Passwd[:uid]</code> is returned
 * instead.
 *
 * See the unix manpage for <code>getpwuid(3)</code> for more detail.
 *
 * === Example:
 *
 *	Etc.getpwuid(0)
 *	#=> #<struct Etc::Passwd name="root", passwd="x", uid=0, gid=0, gecos="root",dir="/root", shell="/bin/bash">
 */
static VALUE
etc_getpwuid(int argc, VALUE *argv, VALUE obj)
{
#if defined(HAVE_GETPWENT)
    VALUE id;
    rb_uid_t uid;
    struct passwd *pwd;

    if (rb_scan_args(argc, argv, "01", &id) == 1) {
	uid = NUM2UIDT(id);
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

/* call-seq:
 *	getpwnam(name)	->  Passwd
 *
 * Returns the /etc/passwd information for the user with specified login
 * +name+.
 *
 * The information is returned as a Passwd struct.
 *
 * See the unix manpage for <code>getpwnam(3)</code> for more detail.
 *
 * === Example:
 *
 *	Etc.getpwnam('root')
 *	#=> #<struct Etc::Passwd name="root", passwd="x", uid=0, gid=0, gecos="root",dir="/root", shell="/bin/bash">
 */
static VALUE
etc_getpwnam(VALUE obj, VALUE nam)
{
#ifdef HAVE_GETPWENT
    struct passwd *pwd;

    SafeStringValue(nam);
    pwd = getpwnam(RSTRING_PTR(nam));
    if (pwd == 0) rb_raise(rb_eArgError, "can't find user for %"PRIsVALUE, nam);
    return setup_passwd(pwd);
#else
    return Qnil;
#endif
}

#ifdef HAVE_GETPWENT
static int passwd_blocking = 0;
static VALUE
passwd_ensure(void)
{
    endpwent();
    passwd_blocking = (int)Qfalse;
    return Qnil;
}

static VALUE
passwd_iterate(void)
{
    struct passwd *pw;

    setpwent();
    while ((pw = getpwent()) != 0) {
	rb_yield(setup_passwd(pw));
    }
    return Qnil;
}

static void
each_passwd(void)
{
    if (passwd_blocking) {
	rb_raise(rb_eRuntimeError, "parallel passwd iteration");
    }
    passwd_blocking = (int)Qtrue;
    rb_ensure(passwd_iterate, 0, passwd_ensure, 0);
}
#endif

/* call-seq:
 *	Etc.passwd { |struct| block }	->  Passwd
 *	Etc.passwd			->  Passwd
 *
 * Provides a convenient Ruby iterator which executes a block for each entry
 * in the /etc/passwd file.
 *
 * The code block is passed an Passwd struct.
 *
 * See ::getpwent above for details.
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
etc_passwd(VALUE obj)
{
#ifdef HAVE_GETPWENT
    struct passwd *pw;

    if (rb_block_given_p()) {
	each_passwd();
    }
    else if ((pw = getpwent()) != 0) {
	return setup_passwd(pw);
    }
#endif
    return Qnil;
}

/* call-seq:
 *	Etc::Passwd.each { |struct| block }	->  Passwd
 *	Etc::Passwd.each			->  Enumerator
 *
 * Iterates for each entry in the /etc/passwd file if a block is given.
 *
 * If no block is given, returns the Enumerator.
 *
 * The code block is passed an Passwd struct.
 *
 * See ::getpwent above for details.
 *
 * Example:
 *
 *     require 'etc'
 *
 *     Etc::Passwd.each {|u|
 *       puts u.name + " = " + u.gecos
 *     }
 *
 *     Etc::Passwd.collect {|u| u.gecos}
 *     Etc::Passwd.collect {|u| u.gecos}
 *
 */
static VALUE
etc_each_passwd(VALUE obj)
{
#ifdef HAVE_GETPWENT
    RETURN_ENUMERATOR(obj, 0, 0);
    each_passwd();
#endif
    return obj;
}

/* Resets the process of reading the /etc/passwd file, so that the next call
 * to ::getpwent will return the first entry again.
 */
static VALUE
etc_setpwent(VALUE obj)
{
#ifdef HAVE_GETPWENT
    setpwent();
#endif
    return Qnil;
}

/* Ends the process of scanning through the /etc/passwd file begun with
 * ::getpwent, and closes the file.
 */
static VALUE
etc_endpwent(VALUE obj)
{
#ifdef HAVE_GETPWENT
    endpwent();
#endif
    return Qnil;
}

/* Returns an entry from the /etc/passwd file.
 *
 * The first time it is called it opens the file and returns the first entry;
 * each successive call returns the next entry, or +nil+ if the end of the file
 * has been reached.
 *
 * To close the file when processing is complete, call ::endpwent.
 *
 * Each entry is returned as a Passwd struct.
 *
 */
static VALUE
etc_getpwent(VALUE obj)
{
#ifdef HAVE_GETPWENT
    struct passwd *pw;

    if ((pw = getpwent()) != 0) {
	return setup_passwd(pw);
    }
#endif
    return Qnil;
}

#ifdef HAVE_GETGRENT
static VALUE
setup_group(struct group *grp)
{
    VALUE mem;
    char **tbl;

    mem = rb_ary_new();
    tbl = grp->gr_mem;
    while (*tbl) {
	rb_ary_push(mem, safe_setup_locale_str(*tbl));
	tbl++;
    }
    return rb_struct_new(sGroup,
			 safe_setup_locale_str(grp->gr_name),
#ifdef HAVE_STRUCT_GROUP_GR_PASSWD
			 safe_setup_str(grp->gr_passwd),
#endif
			 GIDT2NUM(grp->gr_gid),
			 mem);
}
#endif

/* call-seq:
 *	getgrgid(group_id)  ->	Group
 *
 * Returns information about the group with specified integer +group_id+,
 * as found in /etc/group.
 *
 * The information is returned as a Group struct.
 *
 * See the unix manpage for <code>getgrgid(3)</code> for more detail.
 *
 * === Example:
 *
 *	Etc.getgrgid(100)
 *	#=> #<struct Etc::Group name="users", passwd="x", gid=100, mem=["meta", "root"]>
 *
 */
static VALUE
etc_getgrgid(int argc, VALUE *argv, VALUE obj)
{
#ifdef HAVE_GETGRENT
    VALUE id;
    gid_t gid;
    struct group *grp;

    if (rb_scan_args(argc, argv, "01", &id) == 1) {
	gid = NUM2GIDT(id);
    }
    else {
	gid = getgid();
    }
    grp = getgrgid(gid);
    if (grp == 0) rb_raise(rb_eArgError, "can't find group for %d", (int)gid);
    return setup_group(grp);
#else
    return Qnil;
#endif
}

/* call-seq:
 *	getgrnam(name)	->  Group
 *
 * Returns information about the group with specified +name+, as found in
 * /etc/group.
 *
 * The information is returned as a Group struct.
 *
 * See the unix manpage for <code>getgrnam(3)</code> for more detail.
 *
 * === Example:
 *
 *	Etc.getgrnam('users')
 *	#=> #<struct Etc::Group name="users", passwd="x", gid=100, mem=["meta", "root"]>
 *
 */
static VALUE
etc_getgrnam(VALUE obj, VALUE nam)
{
#ifdef HAVE_GETGRENT
    struct group *grp;

    SafeStringValue(nam);
    grp = getgrnam(RSTRING_PTR(nam));
    if (grp == 0) rb_raise(rb_eArgError, "can't find group for %"PRIsVALUE, nam);
    return setup_group(grp);
#else
    return Qnil;
#endif
}

#ifdef HAVE_GETGRENT
static int group_blocking = 0;
static VALUE
group_ensure(void)
{
    endgrent();
    group_blocking = (int)Qfalse;
    return Qnil;
}


static VALUE
group_iterate(void)
{
    struct group *pw;

    setgrent();
    while ((pw = getgrent()) != 0) {
	rb_yield(setup_group(pw));
    }
    return Qnil;
}

static void
each_group(void)
{
    if (group_blocking) {
	rb_raise(rb_eRuntimeError, "parallel group iteration");
    }
    group_blocking = (int)Qtrue;
    rb_ensure(group_iterate, 0, group_ensure, 0);
}
#endif

/* Provides a convenient Ruby iterator which executes a block for each entry
 * in the /etc/group file.
 *
 * The code block is passed an Group struct.
 *
 * See ::getgrent above for details.
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
etc_group(VALUE obj)
{
#ifdef HAVE_GETGRENT
    struct group *grp;

    if (rb_block_given_p()) {
	each_group();
    }
    else if ((grp = getgrent()) != 0) {
	return setup_group(grp);
    }
#endif
    return Qnil;
}

#ifdef HAVE_GETGRENT
/* call-seq:
 *	Etc::Group.each { |group| block }   ->	obj
 *	Etc::Group.each			    ->	Enumerator
 *
 * Iterates for each entry in the /etc/group file if a block is given.
 *
 * If no block is given, returns the Enumerator.
 *
 * The code block is passed a Group struct.
 *
 * Example:
 *
 *     require 'etc'
 *
 *     Etc::Group.each {|g|
 *       puts g.name + ": " + g.mem.join(', ')
 *     }
 *
 *     Etc::Group.collect {|g| g.name}
 *     Etc::Group.select {|g| !g.mem.empty?}
 *
 */
static VALUE
etc_each_group(VALUE obj)
{
    RETURN_ENUMERATOR(obj, 0, 0);
    each_group();
    return obj;
}
#endif

/* Resets the process of reading the /etc/group file, so that the next call
 * to ::getgrent will return the first entry again.
 */
static VALUE
etc_setgrent(VALUE obj)
{
#ifdef HAVE_GETGRENT
    setgrent();
#endif
    return Qnil;
}

/* Ends the process of scanning through the /etc/group file begun by
 * ::getgrent, and closes the file.
 */
static VALUE
etc_endgrent(VALUE obj)
{
#ifdef HAVE_GETGRENT
    endgrent();
#endif
    return Qnil;
}

/* Returns an entry from the /etc/group file.
 *
 * The first time it is called it opens the file and returns the first entry;
 * each successive call returns the next entry, or +nil+ if the end of the file
 * has been reached.
 *
 * To close the file when processing is complete, call ::endgrent.
 *
 * Each entry is returned as a Group struct
 */
static VALUE
etc_getgrent(VALUE obj)
{
#ifdef HAVE_GETGRENT
    struct group *gr;

    if ((gr = getgrent()) != 0) {
	return setup_group(gr);
    }
#endif
    return Qnil;
}

#define numberof(array) (sizeof(array) / sizeof(*(array)))

#ifdef _WIN32
VALUE rb_w32_special_folder(int type);
UINT rb_w32_system_tmpdir(WCHAR *path, UINT len);
VALUE rb_w32_conv_from_wchar(const WCHAR *wstr, rb_encoding *enc);
#endif

/*
 * Returns system configuration directory.
 *
 * This is typically "/etc", but is modified by the prefix used when Ruby was
 * compiled. For example, if Ruby is built and installed in /usr/local, returns
 * "/usr/local/etc".
 */
static VALUE
etc_sysconfdir(VALUE obj)
{
#ifdef _WIN32
    return rb_w32_special_folder(CSIDL_COMMON_APPDATA);
#else
    return rb_filesystem_str_new_cstr(SYSCONFDIR);
#endif
}

/*
 * Returns system temporary directory; typically "/tmp".
 */
static VALUE
etc_systmpdir(void)
{
    VALUE tmpdir;
#ifdef _WIN32
    WCHAR path[_MAX_PATH];
    UINT len = rb_w32_system_tmpdir(path, numberof(path));
    if (!len) return Qnil;
    tmpdir = rb_w32_conv_from_wchar(path, rb_filesystem_encoding());
#else
    const char default_tmp[] = "/tmp";
    const char *tmpstr = default_tmp;
    size_t tmplen = strlen(default_tmp);
# if defined _CS_DARWIN_USER_TEMP_DIR
    #ifndef MAXPATHLEN
    #define MAXPATHLEN 1024
    #endif
    char path[MAXPATHLEN];
    size_t len;
    len = confstr(_CS_DARWIN_USER_TEMP_DIR, path, sizeof(path));
    if (len > 0) {
	tmpstr = path;
	tmplen = len - 1;
    }
# endif
    tmpdir = rb_filesystem_str_new(tmpstr, tmplen);
#endif
    FL_UNSET(tmpdir, FL_TAINT);
    return tmpdir;
}

#ifdef HAVE_UNAME
/*
 * Returns the system information obtained by uname system call.
 *
 * The return value is a hash which has 5 keys at least:
 *   :sysname, :nodename, :release, :version, :machine
 *
 * Example:
 *
 *   require 'etc'
 *   require 'pp'
 *
 *   pp Etc.uname
 *   #=> {:sysname=>"Linux",
 *   #    :nodename=>"boron",
 *   #    :release=>"2.6.18-6-xen-686",
 *   #    :version=>"#1 SMP Thu Nov 5 19:54:42 UTC 2009",
 *   #    :machine=>"i686"}
 *
 */
static VALUE
etc_uname(VALUE obj)
{
#ifdef _WIN32
    OSVERSIONINFOW v;
    SYSTEM_INFO s;
    const char *sysname, *mach;
    VALUE result, release, version;
    VALUE vbuf, nodename = Qnil;
    DWORD len = 0;
    WCHAR *buf;

    v.dwOSVersionInfoSize = sizeof(v);
    if (!GetVersionExW(&v))
        rb_sys_fail("GetVersionEx");

    result = rb_hash_new();
    switch (v.dwPlatformId) {
      case VER_PLATFORM_WIN32s:
	sysname = "Win32s";
	break;
      case VER_PLATFORM_WIN32_NT:
	sysname = "Windows_NT";
	break;
      case VER_PLATFORM_WIN32_WINDOWS:
      default:
	sysname = "Windows";
	break;
    }
    rb_hash_aset(result, ID2SYM(rb_intern("sysname")), rb_str_new_cstr(sysname));
    release = rb_sprintf("%lu.%lu.%lu", v.dwMajorVersion, v.dwMinorVersion, v.dwBuildNumber);
    rb_hash_aset(result, ID2SYM(rb_intern("release")), release);
    version = rb_sprintf("%s Version %"PRIsVALUE": %"PRIsVALUE, sysname, release,
			 rb_w32_conv_from_wchar(v.szCSDVersion, rb_utf8_encoding()));
    rb_hash_aset(result, ID2SYM(rb_intern("version")), version);

# if defined _MSC_VER && _MSC_VER < 1300
#   define GET_COMPUTER_NAME(ptr, plen) GetComputerNameW(ptr, plen)
# else
#   define GET_COMPUTER_NAME(ptr, plen) GetComputerNameExW(ComputerNameDnsFullyQualified, ptr, plen)
# endif
    GET_COMPUTER_NAME(NULL, &len);
    buf = ALLOCV_N(WCHAR, vbuf, len);
    if (GET_COMPUTER_NAME(buf, &len)) {
	nodename = rb_w32_conv_from_wchar(buf, rb_utf8_encoding());
    }
    ALLOCV_END(vbuf);
    if (NIL_P(nodename)) nodename = rb_str_new(0, 0);
    rb_hash_aset(result, ID2SYM(rb_intern("nodename")), nodename);

# ifndef PROCESSOR_ARCHITECTURE_AMD64
#   define PROCESSOR_ARCHITECTURE_AMD64 9
# endif
# ifndef PROCESSOR_ARCHITECTURE_IA64
#   define PROCESSOR_ARCHITECTURE_IA64 6
# endif
# ifndef PROCESSOR_ARCHITECTURE_INTEL
#   define PROCESSOR_ARCHITECTURE_INTEL 0
# endif
    GetSystemInfo(&s);
    switch (s.wProcessorArchitecture) {
      case PROCESSOR_ARCHITECTURE_AMD64:
	mach = "x64";
	break;
      case PROCESSOR_ARCHITECTURE_ARM:
	mach = "ARM";
	break;
      case PROCESSOR_ARCHITECTURE_IA64:
	mach = "IA64";
	break;
      case PROCESSOR_ARCHITECTURE_INTEL:
	mach = "x86";
	break;
      default:
	mach = "unknown";
	break;
    }

    rb_hash_aset(result, ID2SYM(rb_intern("machine")), rb_str_new_cstr(mach));
#else
    struct utsname u;
    int ret;
    VALUE result;

    ret = uname(&u);
    if (ret == -1)
        rb_sys_fail("uname");

    result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("sysname")), rb_str_new_cstr(u.sysname));
    rb_hash_aset(result, ID2SYM(rb_intern("nodename")), rb_str_new_cstr(u.nodename));
    rb_hash_aset(result, ID2SYM(rb_intern("release")), rb_str_new_cstr(u.release));
    rb_hash_aset(result, ID2SYM(rb_intern("version")), rb_str_new_cstr(u.version));
    rb_hash_aset(result, ID2SYM(rb_intern("machine")), rb_str_new_cstr(u.machine));
#endif

    return result;
}
#else
#define etc_uname rb_f_notimplement
#endif

#ifdef HAVE_SYSCONF
/*
 * Returns system configuration variable using sysconf().
 *
 * _name_ should be a constant under <code>Etc</code> which begins with <code>SC_</code>.
 *
 * The return value is an integer or nil.
 * nil means indefinite limit.  (sysconf() returns -1 but errno is not set.)
 *
 *   Etc.sysconf(Etc::SC_ARG_MAX) #=> 2097152
 *   Etc.sysconf(Etc::SC_LOGIN_NAME_MAX) #=> 256
 *
 */
static VALUE
etc_sysconf(VALUE obj, VALUE arg)
{
    int name;
    long ret;

    name = NUM2INT(arg);

    errno = 0;
    ret = sysconf(name);
    if (ret == -1) {
        if (errno == 0) /* no limit */
            return Qnil;
        rb_sys_fail("sysconf");
    }
    return LONG2NUM(ret);
}
#else
#define etc_sysconf rb_f_notimplement
#endif

#ifdef HAVE_CONFSTR
/*
 * Returns system configuration variable using confstr().
 *
 * _name_ should be a constant under <code>Etc</code> which begins with <code>CS_</code>.
 *
 * The return value is a string or nil.
 * nil means no configuration-defined value.  (confstr() returns 0 but errno is not set.)
 *
 *   Etc.confstr(Etc::CS_PATH) #=> "/bin:/usr/bin"
 *
 *   # GNU/Linux
 *   Etc.confstr(Etc::CS_GNU_LIBC_VERSION) #=> "glibc 2.18"
 *   Etc.confstr(Etc::CS_GNU_LIBPTHREAD_VERSION) #=> "NPTL 2.18"
 *
 */
static VALUE
etc_confstr(VALUE obj, VALUE arg)
{
    int name;
    char localbuf[128], *buf = localbuf;
    size_t bufsize = sizeof(localbuf), ret;
    VALUE tmp;

    name = NUM2INT(arg);

    errno = 0;
    ret = confstr(name, buf, bufsize);
    if (bufsize < ret) {
        bufsize = ret;
        buf = ALLOCV_N(char, tmp, bufsize);
        errno = 0;
        ret = confstr(name, buf, bufsize);
    }
    if (bufsize < ret)
        rb_bug("required buffer size for confstr() changed dynamically.");
    if (ret == 0) {
        if (errno == 0) /* no configuration-defined value */
            return Qnil;
        rb_sys_fail("confstr");
    }
    return rb_str_new_cstr(buf);
}
#else
#define etc_confstr rb_f_notimplement
#endif

#ifdef HAVE_FPATHCONF
/*
 * Returns pathname configuration variable using fpathconf().
 *
 * _name_ should be a constant under <code>Etc</code> which begins with <code>PC_</code>.
 *
 * The return value is an integer or nil.
 * nil means indefinite limit.  (fpathconf() returns -1 but errno is not set.)
 *
 *   require 'etc'
 *   IO.pipe {|r, w|
 *     p w.pathconf(Etc::PC_PIPE_BUF) #=> 4096
 *   }
 *
 */
static VALUE
io_pathconf(VALUE io, VALUE arg)
{
    int name;
    long ret;
    rb_io_t *fptr;

    name = NUM2INT(arg);

    GetOpenFile(io, fptr);

    errno = 0;
    ret = fpathconf(fptr->fd, name);
    if (ret == -1) {
        if (errno == 0) /* no limit */
            return Qnil;
        rb_sys_fail("fpathconf");
    }
    return LONG2NUM(ret);
}
#else
#define io_pathconf rb_f_notimplement
#endif

#if (defined(HAVE_SYSCONF) && defined(_SC_NPROCESSORS_ONLN)) || defined(_WIN32)

#if defined(HAVE_SCHED_GETAFFINITY) && defined(CPU_ALLOC)
static int
etc_nprocessors_affin(void)
{
    cpu_set_t *cpuset;
    size_t size;
    int ret;
    int n;

    /*
     * XXX:
     * man page says CPU_ALLOC takes number of cpus. But it is not accurate
     * explanation. sched_getaffinity() returns EINVAL if cpuset bitmap is
     * smaller than kernel internal bitmap.
     * That said, sched_getaffinity() can fail when a kernel have sparse bitmap
     * even if cpuset bitmap is larger than number of cpus.
     * The precious way is to use /sys/devices/system/cpu/online. But there are
     * two problems,
     * - Costly calculation
     *    It is a minor issue, but possibly kill a benefit of a parallel processing.
     * - No guarantee to exist /sys/devices/system/cpu/online
     *    This is an issue especially when using Linux containers.
     * So, we use hardcode number for a workaround. Current linux kernel
     * (Linux 3.17) support 8192 cpus at maximum. Then 16384 must be enough.
     */
    for (n=64; n <= 16384; n *= 2) {
	size = CPU_ALLOC_SIZE(n);
	if (size >= 1024) {
	    cpuset = xcalloc(1, size);
	    if (!cpuset)
		return -1;
	} else {
	    cpuset = alloca(size);
	    CPU_ZERO_S(size, cpuset);
	}

	ret = sched_getaffinity(0, size, cpuset);
	if (ret == 0) {
	    /* On success, count number of cpus. */
	    ret = CPU_COUNT_S(size, cpuset);
	}

	if (size >= 1024) {
	    xfree(cpuset);
	}
	if (ret > 0) {
	    return ret;
	}
    }

    return ret;
}
#endif

/*
 * Returns the number of online processors.
 *
 * The result is intended as the number of processes to
 * use all available processors.
 *
 * This method is implemented using:
 * - sched_getaffinity(): Linux
 * - sysconf(_SC_NPROCESSORS_ONLN): GNU/Linux, NetBSD, FreeBSD, OpenBSD, DragonFly BSD, OpenIndiana, Mac OS X, AIX
 *
 * Example:
 *
 *   require 'etc'
 *   p Etc.nprocessors #=> 4
 *
 * The result might be smaller number than physical cpus especially when ruby
 * process is bound to specific cpus. This is intended for getting better
 * parallel processing.
 *
 * Example: (Linux)
 *
 *   linux$ taskset 0x3 ./ruby -retc -e "p Etc.nprocessors"  #=> 2
 *
 */
static VALUE
etc_nprocessors(VALUE obj)
{
    long ret;

#if !defined(_WIN32)

#if defined(HAVE_SCHED_GETAFFINITY) && defined(CPU_ALLOC)
    int ncpus;

    ncpus = etc_nprocessors_affin();
    if (ncpus != -1) {
       return INT2NUM(ncpus);
    }
    /* fallback to _SC_NPROCESSORS_ONLN */
#endif

    errno = 0;
    ret = sysconf(_SC_NPROCESSORS_ONLN);
    if (ret == -1) {
        rb_sys_fail("sysconf(_SC_NPROCESSORS_ONLN)");
    }
#else
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    ret = (long)si.dwNumberOfProcessors;
#endif
    return LONG2NUM(ret);
}
#else
#define etc_nprocessors rb_f_notimplement
#endif

/*
 * The Etc module provides access to information typically stored in
 * files in the /etc directory on Unix systems.
 *
 * The information accessible consists of the information found in the
 * /etc/passwd and /etc/group files, plus information about the system's
 * temporary directory (/tmp) and configuration directory (/etc).
 *
 * The Etc module provides a more reliable way to access information about
 * the logged in user than environment variables such as +$USER+.
 *
 * == Example:
 *
 *     require 'etc'
 *
 *     login = Etc.getlogin
 *     info = Etc.getpwnam(login)
 *     username = info.gecos.split(/,/).first
 *     puts "Hello #{username}, I see your login name is #{login}"
 *
 * Note that the methods provided by this module are not always secure.
 * It should be used for informational purposes, and not for security.
 *
 * All operations defined in this module are class methods, so that you can
 * include the Etc module into your class.
 */
void
Init_etc(void)
{
    VALUE mEtc;

    mEtc = rb_define_module("Etc");
    init_constants(mEtc);

    rb_define_module_function(mEtc, "getlogin", etc_getlogin, 0);

    rb_define_module_function(mEtc, "getpwuid", etc_getpwuid, -1);
    rb_define_module_function(mEtc, "getpwnam", etc_getpwnam, 1);
    rb_define_module_function(mEtc, "setpwent", etc_setpwent, 0);
    rb_define_module_function(mEtc, "endpwent", etc_endpwent, 0);
    rb_define_module_function(mEtc, "getpwent", etc_getpwent, 0);
    rb_define_module_function(mEtc, "passwd", etc_passwd, 0);

    rb_define_module_function(mEtc, "getgrgid", etc_getgrgid, -1);
    rb_define_module_function(mEtc, "getgrnam", etc_getgrnam, 1);
    rb_define_module_function(mEtc, "group", etc_group, 0);
    rb_define_module_function(mEtc, "setgrent", etc_setgrent, 0);
    rb_define_module_function(mEtc, "endgrent", etc_endgrent, 0);
    rb_define_module_function(mEtc, "getgrent", etc_getgrent, 0);
    rb_define_module_function(mEtc, "sysconfdir", etc_sysconfdir, 0);
    rb_define_module_function(mEtc, "systmpdir", etc_systmpdir, 0);
    rb_define_module_function(mEtc, "uname", etc_uname, 0);
    rb_define_module_function(mEtc, "sysconf", etc_sysconf, 1);
    rb_define_module_function(mEtc, "confstr", etc_confstr, 1);
    rb_define_method(rb_cIO, "pathconf", io_pathconf, 1);
    rb_define_module_function(mEtc, "nprocessors", etc_nprocessors, 0);

    sPasswd =  rb_struct_define_under(mEtc, "Passwd",
				      "name",
#ifdef HAVE_STRUCT_PASSWD_PW_PASSWD
				      "passwd",
#endif
				      "uid",
				      "gid",
#ifdef HAVE_STRUCT_PASSWD_PW_GECOS
				      "gecos",
#endif
				      "dir",
				      "shell",
#ifdef HAVE_STRUCT_PASSWD_PW_CHANGE
				      "change",
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_QUOTA
				      "quota",
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_AGE
				      "age",
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_CLASS
				      "uclass",
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_COMMENT
				      "comment",
#endif
#ifdef HAVE_STRUCT_PASSWD_PW_EXPIRE
				      "expire",
#endif
				      NULL);
#if 0
    /* Define-const: Passwd
     *
     * Passwd is a Struct that contains the following members:
     *
     * name::
     *	    contains the short login name of the user as a String.
     * passwd::
     *	    contains the encrypted password of the user as a String.
     *	    an 'x' is returned if shadow passwords are in use. An '*' is returned
     *      if the user cannot log in using a password.
     * uid::
     *	    contains the integer user ID (uid) of the user.
     * gid::
     *	    contains the integer group ID (gid) of the user's primary group.
     * dir::
     *	    contains the path to the home directory of the user as a String.
     * shell::
     *	    contains the path to the login shell of the user as a String.
     *
     * === The following members below are optional, and must be compiled with special flags:
     *
     * gecos::
     *     contains a longer String description of the user, such as
     *	   a full name. Some Unix systems provide structured information in the
     *     gecos field, but this is system-dependent.
     *     must be compiled with +HAVE_STRUCT_PASSWD_PW_GECOS+
     * change::
     *     password change time(integer) must be compiled with +HAVE_STRUCT_PASSWD_PW_CHANGE+
     * quota::
     *     quota value(integer) must be compiled with +HAVE_STRUCT_PASSWD_PW_QUOTA+
     * age::
     *     password age(integer) must be compiled with +HAVE_STRUCT_PASSWD_PW_AGE+
     * class::
     *     user access class(string) must be compiled with +HAVE_STRUCT_PASSWD_PW_CLASS+
     * comment::
     *     comment(string) must be compiled with +HAVE_STRUCT_PASSWD_PW_COMMENT+
     * expire::
     *	    account expiration time(integer) must be compiled with +HAVE_STRUCT_PASSWD_PW_EXPIRE+
     */
    rb_define_const(mEtc, "Passwd", sPasswd);
#endif
    rb_define_const(rb_cStruct, "Passwd", sPasswd); /* deprecated name */
    rb_extend_object(sPasswd, rb_mEnumerable);
    rb_define_singleton_method(sPasswd, "each", etc_each_passwd, 0);

#ifdef HAVE_GETGRENT
    sGroup = rb_struct_define_under(mEtc, "Group", "name",
#ifdef HAVE_STRUCT_GROUP_GR_PASSWD
				    "passwd",
#endif
				    "gid", "mem", NULL);

#if 0
    /* Define-const: Group
     *
     * Group is a Struct that is only available when compiled with +HAVE_GETGRENT+.
     *
     * The struct contains the following members:
     *
     * name::
     *	    contains the name of the group as a String.
     * passwd::
     *	    contains the encrypted password as a String. An 'x' is
     *	    returned if password access to the group is not available; an empty
     *	    string is returned if no password is needed to obtain membership of
     *	    the group.
     *
     *	    Must be compiled with +HAVE_STRUCT_GROUP_GR_PASSWD+.
     * gid::
     *	    contains the group's numeric ID as an integer.
     * mem::
     *	    is an Array of Strings containing the short login names of the
     *	    members of the group.
     */
    rb_define_const(mEtc, "Group", sGroup);
#endif
    rb_define_const(rb_cStruct, "Group", sGroup); /* deprecated name */
    rb_extend_object(sGroup, rb_mEnumerable);
    rb_define_singleton_method(sGroup, "each", etc_each_group, 0);
#endif
}
