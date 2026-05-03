#include "ruby.h"
#include "internal.h"
#include "internal/file.h"
#include "internal/string.h"
#include "internal/vm.h"

#if defined __CYGWIN__ || defined DOSISH
# define drive_letter 1
# define alt_separator 1
# define isdirsep(x) ((x) == '/' || (x) == '\\')
#else
# define drive_letter 0
# define alt_separator 0
# define isdirsep(x) ((x) == '/')
#endif

static VALUE rb_cPathname;
static ID id_at_path;
static ID id_sub;

static VALUE
check_strpath(VALUE path)
{
    Check_Type(path, T_STRING);
    rb_get_path_check_no_convert(path);
    return path;
}

static VALUE
get_strpath(VALUE obj)
{
    VALUE strpath;
    strpath = rb_ivar_get(obj, id_at_path);
    if (!RB_TYPE_P(strpath, T_STRING))
        rb_raise(rb_eTypeError, "unexpected @path");
    rb_get_path_check_no_convert(strpath);
    return strpath;
}

/*
 * call-seq:
 *   self <=> other -> -1, 0, 1, or nil
 *
 * Compares the contents of +self+ and +other+ as strings;
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

/*
 * Predicate method for root directories.  Returns +true+ if the
 * pathname consists of consecutive slashes.
 *
 * It doesn't access the filesystem.  So it may return +false+ for some
 * pathnames which points to roots such as <tt>/usr/..</tt>.
 */
static VALUE
path_root_p(VALUE self)
{
    VALUE path = get_strpath(self);
    if (RSTRING_LEN(path) == 0) return Qfalse;
    const char *ptr = RSTRING_PTR(path), *end = RSTRING_END(path);
    rb_encoding *enc = rb_enc_get(path);
    const char *base = rb_enc_path_skip_prefix_root(ptr, end, enc);
    return RBOOL(base == end);
}

/*
 * call-seq:
 *   absolute? -> true or false
 *
 * Returns whether +self+ contains an absolute path:
 *
 *   Pathname.new('/home').absolute? # => true
 *   Pathname.new('lib').absolute?   # => false
 *
 * OS-dependent for some paths:
 *
 *   Pathname.new('C:/').absolute?   # => true   # On Windows.
 *   Pathname.new('C:/').absolute?   # => false  # Elsewhere.
 */
static VALUE
path_absolute_p(VALUE self)
{
    VALUE path = get_strpath(self);
    const char *ptr = RSTRING_PTR(path);
    long len = RSTRING_LEN(path);
    if (len < 1) return Qfalse;
    if (drive_letter) {
        if (len >= 2 && ISALPHA(ptr[0]) && (ptr[1] == ':')) return Qtrue;
    }
    return RBOOL(isdirsep(ptr[0]));
}

/* :nodoc: */
static VALUE
has_separator_p(VALUE self, VALUE path)
{
    const char *ptr = RSTRING_PTR(check_strpath(path));
    const char *end = RSTRING_END(path);
    if (alt_separator) {
        rb_encoding *enc = rb_enc_get(path);
        bool mb = !rb_str_enc_fastpath(path);
        while (ptr < end) {
            if (isdirsep(*ptr)) return Qtrue;
            ptr += (mb ? rb_enc_mbclen(ptr, end, enc) : 1);
        }
    }
    else {
        /* assume '/' will never be trailing bytes */
        if (memchr(ptr, '/', end - ptr)) return Qtrue;
    }
    return Qfalse;
}

/*
 * Return a pathname with +repl+ added as a suffix to the basename.
 *
 * If self has no extension part, +repl+ is appended.
 *
 *	Pathname.new('/usr/bin/shutdown').sub_ext('.rb')
 *	    #=> #<Pathname:/usr/bin/shutdown.rb>
 */
static VALUE
path_sub_ext(VALUE self, VALUE repl)
{
    VALUE path = get_strpath(self);
    long len = RSTRING_LEN(path);
    const char *ptr = RSTRING_PTR(path);
    const char *ext = ruby_enc_find_extname(ptr, &len, rb_enc_get(path));
    if (len > 0) {
        RUBY_ASSERT(ext, "should point the last dot");
        path = rb_str_subseq(path, 0, ext - ptr);
    }
    else {
        /* no dot or dotted file */
        path = rb_str_dup(path);
    }
    path = rb_str_append(path, repl);
    return rb_class_new_instance(1, &path, rb_obj_class(self));
}

/* :nodoc: */
/* chop_basename(path) -> [pre-basename, basename] or nil */
static VALUE
chop_basename(VALUE self, VALUE path)
{
    long baselen, alllen = RSTRING_LEN(check_strpath(path));
    if (alllen <= 0) return Qnil;
    rb_encoding *enc = rb_enc_get(path);
    const char *name = RSTRING_PTR(path);
    const char *base = ruby_enc_find_basename(name, &baselen, &alllen, enc);
    if (baselen < 1) return Qnil;
    if (baselen == 1 && isdirsep(*base)) return Qnil;
    RUBY_ASSERT(base >= name);
    RUBY_ASSERT(base <= RSTRING_END(path));
    VALUE dir = rb_str_subseq(path, 0, base - name);
    VALUE basename = rb_enc_str_new(base, alllen, enc);
    RB_GC_GUARD(path);
    return rb_assoc_new(dir, basename);
}

/* :nodoc: */
/* has_trailing_separator?(path) -> bool */
static VALUE
has_trailing_separator(VALUE self, VALUE path)
{
    long baselen, alllen = RSTRING_LEN(check_strpath(path));
    if (alllen <= 0) return Qfalse;
    rb_encoding *enc = rb_enc_get(path);
    const char *name = RSTRING_PTR(path);
    const char *base = ruby_enc_find_basename(name, &baselen, &alllen, enc);
    if (baselen < 1) return Qfalse;
    if (baselen == 1 && isdirsep(*base)) return Qfalse;
    return RBOOL(base + alllen < RSTRING_END(path));
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
    rb_define_method(rb_cPathname, "sub_ext", path_sub_ext, 1);
    rb_define_method(rb_cPathname, "root?", path_root_p, 0);
    rb_define_method(rb_cPathname, "absolute?", path_absolute_p, 0);

    rb_define_private_method(rb_cPathname, "has_separator?", has_separator_p, 1);
    rb_define_private_method(rb_cPathname, "chop_basename", chop_basename, 1);
    rb_define_private_method(rb_cPathname, "has_trailing_separator?", has_trailing_separator, 1);

    rb_provide("pathname.so");
}

void
init_ids(void)
{
#undef rb_intern
    id_at_path = rb_intern("@path");
    id_sub = rb_intern("sub");
}
