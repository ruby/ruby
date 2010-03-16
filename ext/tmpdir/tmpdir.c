#include <ruby/ruby.h>
#include <ruby/encoding.h>

#define numberof(array) (sizeof(array) / sizeof(*array))

#ifdef HAVE_RB_W32_SYSTEM_TMPDIR
UINT rb_w32_system_tmpdir(WCHAR *path, UINT len);
VALUE rb_w32_conv_from_wchar(const WCHAR *wstr, rb_encoding *enc);
#endif

static VALUE
system_tmpdir(void)
{
#ifdef HAVE_RB_W32_SYSTEM_TMPDIR
    WCHAR path[_MAX_PATH];
    UINT len = rb_w32_system_tmpdir(path, numberof(path));
    if (!len) return Qnil;
    return rb_w32_conv_from_wchar(path, rb_filesystem_encoding());
#else
    return rb_filesystem_str_new_cstr("/tmp");
#endif
}

/*
 * sets Dir.@@systmpdir.
 */
void
Init_tmpdir(void)
{
    rb_cvar_set(rb_cDir, rb_intern_const("@@systmpdir"),
		rb_obj_freeze(system_tmpdir()));
}
