#include "ruby/ruby.h"
#include "ruby/io.h"

#ifdef __linux__
# define HAVE_GETMNTENT
#endif

#ifdef HAVE_GETMNTENT
# include <stdio.h>
# include <mntent.h>
#endif

VALUE
get_fsname(VALUE self, VALUE str)
{
#ifdef HAVE_GETMNTENT
    const char *path;
    struct mntent mntbuf;
    static const int buflen = 4096;
    char *buf = alloca(buflen);
    int len = 0;
    FILE *fp;
#define FSNAME_LEN 100
    char name[FSNAME_LEN] = "";

    FilePathValue(str);
    path = RSTRING_PTR(str);
    fp = setmntent("/etc/mtab", "r");
    if (!fp) rb_sys_fail("setmntent(/etb/mtab)");;

    while (getmntent_r(fp, &mntbuf, buf, buflen)) {
	int i;
	char *mnt_dir = mntbuf.mnt_dir;
	for (i=0; mnt_dir[i]; i++) {
	    if (mnt_dir[i] != path[i]) {
		goto next_entry;
	    }
	}
	if (i >= len) {
	    len = i;
	    strlcpy(name, mntbuf.mnt_type, FSNAME_LEN);
	}
next_entry:
	;
    }
    endmntent(fp);

    if (!len) rb_sys_fail("no matching entry");;
    return rb_str_new_cstr(name);
#else
    return Qnil;
#endif
}

void
Init_fs(VALUE module)
{
    VALUE fs = rb_define_module_under(module, "Fs");
    rb_define_module_function(fs, "fsname", get_fsname, 1);
}
