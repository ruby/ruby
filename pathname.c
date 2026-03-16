#include "ruby.h"

static VALUE rb_cPathname;
static ID id_at_path;
static ID id_sub;

static VALUE
get_strpath(VALUE obj)
{
    VALUE strpath;
    strpath = rb_ivar_get(obj, id_at_path);
    if (!RB_TYPE_P(strpath, T_STRING))
        rb_raise(rb_eTypeError, "unexpected @path");
    return strpath;
}

/*
 * call-seq:
 *   self <=> other -> -1, 0, 1, or nil
 *
 * Compares the contents of +self+ and +other+ as strings
 * (first performing necessary conversions);
 * see String#<=>.
 *
 * Returns:
 *
 * - <tt>-1</tt> if +self+'s string is smaller than +other+'s string.
 * - <tt>0</tt> if the two are equal.
 * - <tt>1</tt> if +self+'s string is larger than +other+'s string.
 * - <tt>nil</tt> if +other+ is not a \Pathname.
 *
 * Examples:
 *
 *   Pathname.new('a')  <=> Pathname.new('b')      # => -1
 *   Pathname.new('a')  <=> Pathname.new('ab')     # => -1
 *   Pathname.new('a')  <=> Pathname.new('a')      # => 0
 *   Pathname.new('b')  <=> Pathname.new('a')      # => 1
 *   Pathname.new('ab') <=> Pathname.new('a')      # => 1
 *   Pathname.new('ab') <=> 'a'                    # => nil
 *
 * Two pathnames that are different may refer to the same entry in the filesystem:
 *
 *   Pathname.new('lib') <=> Pathname.new('./lib') # => 1
 *
 */
static VALUE
path_cmp(VALUE self, VALUE other)
{
    VALUE s1, s2;
    char *p1, *p2;
    char *e1, *e2;
    if (!rb_obj_is_kind_of(other, rb_cPathname))
        return Qnil;
    s1 = get_strpath(self);
    s2 = get_strpath(other);
    p1 = RSTRING_PTR(s1);
    p2 = RSTRING_PTR(s2);
    e1 = p1 + RSTRING_LEN(s1);
    e2 = p2 + RSTRING_LEN(s2);
    while (p1 < e1 && p2 < e2) {
        int c1, c2;
        c1 = (unsigned char)*p1++;
        c2 = (unsigned char)*p2++;
        if (c1 == '/') c1 = '\0';
        if (c2 == '/') c2 = '\0';
        if (c1 != c2) {
            if (c1 < c2)
                return INT2FIX(-1);
            else
                return INT2FIX(1);
        }
    }
    if (p1 < e1)
        return INT2FIX(1);
    if (p2 < e2)
        return INT2FIX(-1);
    return INT2FIX(0);
}

/*
 * Return a pathname which is substituted by String#sub.
 *
 *	path1 = Pathname.new('/usr/bin/perl')
 *	path1.sub('perl', 'ruby')
 *	    #=> #<Pathname:/usr/bin/ruby>
 */
static VALUE
path_sub(int argc, VALUE *argv, VALUE self)
{
    VALUE str = get_strpath(self);

    if (rb_block_given_p()) {
        str = rb_block_call(str, id_sub, argc, argv, 0, 0);
    }
    else {
        str = rb_funcallv(str, id_sub, argc, argv);
    }
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

#include "pathname_builtin.rbinc"

static void init_ids(void);

void
Init_pathname(void)
{
#ifdef HAVE_RB_EXT_RACTOR_SAFE
    rb_ext_ractor_safe(true);
#endif

    init_ids();
    InitVM(pathname);
}

void
InitVM_pathname(void)
{
    rb_cPathname = rb_define_class("Pathname", rb_cObject);
    rb_define_method(rb_cPathname, "<=>", path_cmp, 1);
    rb_define_method(rb_cPathname, "sub", path_sub, -1);

    rb_provide("pathname.so");
}

void
init_ids(void)
{
#undef rb_intern
    id_at_path = rb_intern("@path");
    id_sub = rb_intern("sub");
}
