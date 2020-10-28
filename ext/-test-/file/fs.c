#include "ruby/ruby.h"
#include "ruby/io.h"

#ifdef HAVE_SYS_PARAM_H
#include <sys/param.h>
#endif
#ifdef HAVE_SYS_MOUNT_H
#include <sys/mount.h>
#endif
#ifdef HAVE_SYS_VFS_H
#include <sys/vfs.h>
#endif
#ifdef HAVE_SYS_STATVFS_H
#include <sys/statvfs.h>
#endif

#if defined HAVE_STRUCT_STATFS_F_FSTYPENAME
typedef struct statfs statfs_t;
# define STATFS(f, s) statfs((f), (s))
# define HAVE_STRUCT_STATFS_T_F_FSTYPENAME 1
# if defined HAVE_STRUCT_STATFS_F_TYPE
#   define HAVE_STRUCT_STATFS_T_F_TYPE 1
# endif
#elif defined(HAVE_STRUCT_STATVFS_F_FSTYPENAME) /* NetBSD */
typedef struct statvfs statfs_t;
# define STATFS(f, s) statvfs((f), (s))
# define HAVE_STRUCT_STATFS_T_F_FSTYPENAME 1
# if defined HAVE_STRUCT_STATVFS_F_TYPE
#   define HAVE_STRUCT_STATFS_T_F_TYPE 1
# endif
#elif defined(HAVE_STRUCT_STATVFS_F_BASETYPE) /* AIX, HP-UX, Solaris */
typedef struct statvfs statfs_t;
# define STATFS(f, s) statvfs((f), (s))
# define HAVE_STRUCT_STATFS_T_F_FSTYPENAME 1
# define f_fstypename f_basetype
# if defined HAVE_STRUCT_STATVFS_F_TYPE
#   define HAVE_STRUCT_STATFS_T_F_TYPE 1
# endif
#elif defined(HAVE_STRUCT_STATFS_F_TYPE) /* Linux */
typedef struct statfs statfs_t;
# define STATFS(f, s) statfs((f), (s))
# if defined HAVE_STRUCT_STATFS_F_TYPE
#   define HAVE_STRUCT_STATFS_T_F_TYPE 1
# endif
#endif

VALUE
get_fsname(VALUE self, VALUE str)
{
#ifdef STATFS
    statfs_t st;
# define CSTR(s) rb_str_new_cstr(s)

    FilePathValue(str);
    str = rb_str_encode_ospath(str);
    if (STATFS(StringValueCStr(str), &st) == -1) {
	rb_sys_fail_str(str);
    }
# ifdef HAVE_STRUCT_STATFS_T_F_FSTYPENAME
    if (st.f_fstypename[0])
	return CSTR(st.f_fstypename);
# endif
# ifdef HAVE_STRUCT_STATFS_T_F_TYPE
    switch (st.f_type) {
      case 0x9123683E: /* BTRFS_SUPER_MAGIC */
	return CSTR("btrfs");
      case 0x7461636f: /* OCFS2_SUPER_MAGIC */
	return CSTR("ocfs");
      case 0xEF53: /* EXT2_SUPER_MAGIC EXT3_SUPER_MAGIC EXT4_SUPER_MAGIC */
	return CSTR("ext4");
      case 0x58465342: /* XFS_SUPER_MAGIC */
	return CSTR("xfs");
      case 0x01021994: /* TMPFS_MAGIC */
	return CSTR("tmpfs");
    }
# endif
#endif
    return Qnil;
}

VALUE
get_noatime_p(VALUE self, VALUE str)
{
#ifdef STATFS
    statfs_t st;
    FilePathValue(str);
    str = rb_str_encode_ospath(str);
    if (STATFS(StringValueCStr(str), &st) == -1) {
       rb_sys_fail_str(str);
    }
# ifdef HAVE_STRUCT_STATFS_F_FLAGS
#  ifdef MNT_STRICTATIME
    if (!(st.f_flags & MNT_STRICTATIME)) return Qtrue;
#  endif
#  ifdef MNT_NOATIME
    return st.f_flags & MNT_NOATIME ? Qtrue : Qfalse;
#  elif defined(ST_NOATIME)
    return st.f_flags & ST_NOATIME ? Qtrue : Qfalse;
#  endif
# endif
#endif
    return Qnil;
}

void
Init_fs(VALUE module)
{
    VALUE fs = rb_define_module_under(module, "Fs");
    rb_define_module_function(fs, "fsname", get_fsname, 1);
    rb_define_module_function(fs, "noatime?", get_noatime_p, 1);
}
