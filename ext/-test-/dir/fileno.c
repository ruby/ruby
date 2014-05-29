#include "ruby.h"
#include "ruby/encoding.h"
#include "internal.h"

#if defined HAVE_DIRENT_H && !defined _WIN32
# include <dirent.h>
#elif defined HAVE_DIRECT_H && !defined _WIN32
# include <direct.h>
#else
# define dirent direct
# if HAVE_SYS_NDIR_H
#  include <sys/ndir.h>
# endif
# if HAVE_SYS_DIR_H
#  include <sys/dir.h>
# endif
# if HAVE_NDIR_H
#  include <ndir.h>
# endif
# ifdef _WIN32
#  include "win32/dir.h"
# endif
#endif
#if defined(__native_client__) && defined(NACL_NEWLIB)
# include "nacl/dirent.h"
# include "nacl/stat.h"
#endif

struct dir_data {
    DIR *dir;
    VALUE path;
    rb_encoding *enc;
};

static void *
rb_check_typeddata0(VALUE obj /*, const rb_data_type_t *data_type */)
{
    const char *etype;
    /* static const char mesg[] = "wrong argument type %s (expected %s)"; */

    if (!RB_TYPE_P(obj, T_DATA)) {
        etype = rb_builtin_class_name(obj);
        /* rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name); */
        rb_raise(rb_eTypeError, "wrong argument type %s", etype);
    }
/*
    if (!RTYPEDDATA_P(obj)) {
        etype = rb_obj_classname(obj);
        rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name);
    }
    else if (!rb_typeddata_inherited_p(RTYPEDDATA_TYPE(obj), data_type)) {
        etype = RTYPEDDATA_TYPE(obj)->wrap_struct_name;
        rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name);
    }
*/
    return DATA_PTR(obj);
}

static void
dir_closed(void)
{
    rb_raise(rb_eIOError, "closed directory");
}

static struct dir_data *
dir_check(VALUE dir)
{
    struct dir_data *dirp;
    rb_check_frozen(dir);
    dirp = rb_check_typeddata0(dir /*, &dir_data_type*/);
    if (!dirp->dir) dir_closed();
    return dirp;
}

#define GetDIR(obj, dirp) ((dirp) = dir_check(obj))

#ifdef HAVE_DIRFD
/*
 *  call-seq:
 *     dir.fileno -> integer
 *
 *  Returns the file descriptor used in <em>dir</em>.
 *
 *     d = Dir.new("..")
 *     d.fileno   #=> 8
 */
static VALUE
dir_fileno(VALUE dir)
{
    struct dir_data *dirp;
    int fd;

    GetDIR(dir, dirp);
    fd = dirfd(dirp->dir);
    if (fd == -1)
       rb_sys_fail("dirfd");
    return INT2NUM(fd);
}
#else
#define dir_fileno rb_f_notimplement
#endif

void
Init_fileno(VALUE klass)
{
    rb_define_method(rb_cDir,"fileno", dir_fileno, 0);
}
