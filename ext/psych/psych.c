#include <psych.h>

/* call-seq: Psych.libyaml_version
 *
 * Returns the version of libyaml being used
 */
static VALUE libyaml_version(VALUE module)
{
    int major, minor, patch;
    VALUE list[3];

#ifdef PSYCH_USE_LIBFYAML
    /* Experimental libfyaml backend: there is no libyaml linked in.  Report
     * the libfyaml version so callers still receive a 3-element version. */
    const struct fy_version *v = fy_version_default();
    major = v ? v->major : 0;
    minor = v ? v->minor : 0;
    patch = 0;
#else
    yaml_get_version(&major, &minor, &patch);
#endif

    list[0] = INT2NUM(major);
    list[1] = INT2NUM(minor);
    list[2] = INT2NUM(patch);

    return rb_ary_new4((long)3, list);
}

#ifdef PSYCH_USE_LIBFYAML
/* call-seq: Psych.libfyaml_version
 *
 * Returns the libfyaml version string, or nil when not built with libfyaml.
 */
static VALUE libfyaml_version(VALUE module)
{
    const char *v = fy_library_version();
    return v ? rb_usascii_str_new2(v) : Qnil;
}
#endif

VALUE mPsych;

void Init_psych(void)
{
    #ifdef HAVE_RB_EXT_RACTOR_SAFE
        RB_EXT_RACTOR_SAFE(true);
    #endif
    mPsych = rb_define_module("Psych");

    rb_define_singleton_method(mPsych, "libyaml_version", libyaml_version, 0);

#ifdef PSYCH_USE_LIBFYAML
    rb_define_singleton_method(mPsych, "libfyaml_version", libfyaml_version, 0);
    rb_define_const(mPsych, "BACKEND", rb_usascii_str_new2("libfyaml"));
#else
    rb_define_const(mPsych, "BACKEND", rb_usascii_str_new2("libyaml"));
#endif

    Init_psych_parser();
    Init_psych_emitter();
    Init_psych_to_ruby();
    Init_psych_yaml_tree();
}
