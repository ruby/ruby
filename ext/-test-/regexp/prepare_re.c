#include <ruby.h>
#include <ruby/re.h>
#include <ruby/onigmo.h>

/* Frees the result like extensions copied from strscan do. */
static VALUE
legacy_prepare_re(VALUE self, VALUE re, VALUE str)
{
    regex_t *reg = rb_reg_prepare_re(re, str);
    int tmpreg = reg != RREGEXP_PTR(re);
    const UChar *beg = (const UChar *)RSTRING_PTR(str);
    const UChar *end = beg + RSTRING_LEN(str);
    OnigPosition pos = onig_search(reg, beg, end, beg, end, NULL, ONIG_OPTION_NONE);

    if (tmpreg) onig_free(reg);
    return rb_ary_new_from_args(2, LONG2NUM((long)pos), tmpreg ? Qtrue : Qfalse);
}

void
Init_prepare_re(VALUE klass)
{
    rb_define_singleton_method(klass, "legacy_prepare_re", legacy_prepare_re, 2);
}
