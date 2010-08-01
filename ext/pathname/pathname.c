#include "ruby.h"

static VALUE rb_cPathname;
static ID id_at_path, id_to_path;

static VALUE
get_strpath(VALUE obj)
{
    VALUE strpath;
    strpath = rb_ivar_get(obj, id_at_path);
    if (TYPE(strpath) != T_STRING)
        rb_raise(rb_eTypeError, "unexpected @path");
    return strpath;
}

static void
set_strpath(VALUE obj, VALUE val)
{
    rb_ivar_set(obj, id_at_path, val);
}

/*
 * Create a Pathname object from the given String (or String-like object).
 * If +path+ contains a NUL character (<tt>\0</tt>), an ArgumentError is raised.
 */
static VALUE
path_initialize(VALUE self, VALUE arg)
{
    VALUE str;
    if (TYPE(arg) == T_STRING) {
        str = arg;
    }
    else {
        str = rb_check_funcall(arg, id_to_path, 0, NULL);
        if (str == Qundef)
            str = arg;
        StringValue(str);
    }
    if (memchr(RSTRING_PTR(str), '\0', RSTRING_LEN(str)))
        rb_raise(rb_eArgError, "pathname contains null byte");
    str = rb_obj_dup(str);

    set_strpath(self, str);
    OBJ_INFECT(self, str);
    return self;
}

static VALUE
path_freeze(VALUE self)
{
    rb_call_super(0, 0);
    rb_str_freeze(get_strpath(self));
    return self;
}

static VALUE
path_taint(VALUE self)
{
    rb_call_super(0, 0);
    rb_obj_taint(get_strpath(self));
    return self;
}

static VALUE
path_untaint(VALUE self)
{
    rb_call_super(0, 0);
    rb_obj_untaint(get_strpath(self));
    return self;
}

/*
 *  Compare this pathname with +other+.  The comparison is string-based.
 *  Be aware that two different paths (<tt>foo.txt</tt> and <tt>./foo.txt</tt>)
 *  can refer to the same file.
 */
static VALUE
path_eq(VALUE self, VALUE other)
{
    if (!rb_obj_is_kind_of(other, rb_cPathname))
        return Qfalse;
    return rb_str_equal(get_strpath(self), get_strpath(other));
}

/*
 *  Provides for comparing pathnames, case-sensitively.
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

/* :nodoc: */
static VALUE
path_hash(VALUE self)
{
    return INT2FIX(rb_str_hash(get_strpath(self)));
}

/*
 *  call-seq:
 *    pathname.to_s             => string
 *    pathname.to_path          => string
 *
 *  Return the path as a String.
 *
 *  to_path is implemented so Pathname objects are usable with File.open, etc.
 */
static VALUE
path_to_s(VALUE self)
{
    return rb_obj_dup(get_strpath(self));
}

/* :nodoc: */
static VALUE
path_inspect(VALUE self)
{
    const char *c = rb_obj_classname(self);
    VALUE str = get_strpath(self);
    return rb_sprintf("#<%s:%s>", c, RSTRING_PTR(str));
}

/*
 * Return a pathname which is substituted by String#sub.
 */
static VALUE
path_sub(int argc, VALUE *argv, VALUE self)
{
    VALUE str = get_strpath(self);

    if (rb_block_given_p()) {
        str = rb_block_call(str, rb_intern("sub"), argc, argv, 0, 0);
    }
    else {
        str = rb_funcall2(str, rb_intern("sub"), argc, argv);
    }
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * Return a pathname which the extension of the basename is substituted by
 * <i>repl</i>.
 * 
 * If self has no extension part, <i>repl</i> is appended.
 */
static VALUE
path_sub_ext(VALUE self, VALUE repl)
{
    VALUE str = get_strpath(self);
    VALUE str2;
    long extlen;
    const char *ext;
    const char *p;

    StringValue(repl);
    p = RSTRING_PTR(str);
    ext = ruby_find_extname(p, &extlen);
    if (ext == NULL) {
        ext = p + RSTRING_LEN(str);
    }
    else if (extlen <= 1) {
        ext += extlen;
    }
    str2 = rb_str_dup(str);
    rb_str_set_len(str2, ext-p);
    rb_str_append(str2, repl);
    OBJ_INFECT(str2, str);
    return rb_class_new_instance(1, &str2, rb_obj_class(self));
}

/*
 * Returns the real (absolute) pathname of +self+ in the actual
 * filesystem not containing symlinks or useless dots.
 *
 * All components of the pathname must exist when this method is
 * called.
 *
 */
static VALUE
path_realpath(int argc, VALUE *argv, VALUE self)
{
    VALUE basedir, str;
    rb_scan_args(argc, argv, "01", &basedir);
    str = rb_funcall(rb_cFile, rb_intern("realpath"), 2, get_strpath(self), basedir);
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * Returns the real (absolute) pathname of +self+ in the actual filesystem.
 * The real pathname doesn't contain symlinks or useless dots.
 * 
 * The last component of the real pathname can be nonexistent.
 */
static VALUE
path_realdirpath(int argc, VALUE *argv, VALUE self)
{
    VALUE basedir, str;
    rb_scan_args(argc, argv, "01", &basedir);
    str = rb_funcall(rb_cFile, rb_intern("realdirpath"), 2, get_strpath(self), basedir);
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * == Pathname
 *
 * Pathname represents a pathname which locates a file in a filesystem.
 * The pathname depends on OS: Unix, Windows, etc.
 * Pathname library works with pathnames of local OS.
 * However non-Unix pathnames are supported experimentally.
 *
 * It does not represent the file itself.
 * A Pathname can be relative or absolute.  It's not until you try to
 * reference the file that it even matters whether the file exists or not.
 *
 * Pathname is immutable.  It has no method for destructive update.
 *
 * The value of this class is to manipulate file path information in a neater
 * way than standard Ruby provides.  The examples below demonstrate the
 * difference.  *All* functionality from File, FileTest, and some from Dir and
 * FileUtils is included, in an unsurprising way.  It is essentially a facade for
 * all of these, and more.
 *
 * == Examples
 *
 * === Example 1: Using Pathname
 *
 *   require 'pathname'
 *   pn = Pathname.new("/usr/bin/ruby")
 *   size = pn.size              # 27662
 *   isdir = pn.directory?       # false
 *   dir  = pn.dirname           # Pathname:/usr/bin
 *   base = pn.basename          # Pathname:ruby
 *   dir, base = pn.split        # [Pathname:/usr/bin, Pathname:ruby]
 *   data = pn.read
 *   pn.open { |f| _ }
 *   pn.each_line { |line| _ }
 *
 * === Example 2: Using standard Ruby
 *
 *   pn = "/usr/bin/ruby"
 *   size = File.size(pn)        # 27662
 *   isdir = File.directory?(pn) # false
 *   dir  = File.dirname(pn)     # "/usr/bin"
 *   base = File.basename(pn)    # "ruby"
 *   dir, base = File.split(pn)  # ["/usr/bin", "ruby"]
 *   data = File.read(pn)
 *   File.open(pn) { |f| _ }
 *   File.foreach(pn) { |line| _ }
 *
 * === Example 3: Special features
 *
 *   p1 = Pathname.new("/usr/lib")   # Pathname:/usr/lib
 *   p2 = p1 + "ruby/1.8"            # Pathname:/usr/lib/ruby/1.8
 *   p3 = p1.parent                  # Pathname:/usr
 *   p4 = p2.relative_path_from(p3)  # Pathname:lib/ruby/1.8
 *   pwd = Pathname.pwd              # Pathname:/home/gavin
 *   pwd.absolute?                   # true
 *   p5 = Pathname.new "."           # Pathname:.
 *   p5 = p5 + "music/../articles"   # Pathname:music/../articles
 *   p5.cleanpath                    # Pathname:articles
 *   p5.realpath                     # Pathname:/home/gavin/articles
 *   p5.children                     # [Pathname:/home/gavin/articles/linux, ...]
 *
 * == Breakdown of functionality
 *
 * === Core methods
 *
 * These methods are effectively manipulating a String, because that's
 * all a path is.  Except for #mountpoint?, #children, #each_child,
 * #realdirpath and #realpath, they don't access the filesystem.
 *
 * - +
 * - #join
 * - #parent
 * - #root?
 * - #absolute?
 * - #relative?
 * - #relative_path_from
 * - #each_filename
 * - #cleanpath
 * - #realpath
 * - #realdirpath
 * - #children
 * - #each_child
 * - #mountpoint?
 *
 * === File status predicate methods
 *
 * These methods are a facade for FileTest:
 * - #blockdev?
 * - #chardev?
 * - #directory?
 * - #executable?
 * - #executable_real?
 * - #exist?
 * - #file?
 * - #grpowned?
 * - #owned?
 * - #pipe?
 * - #readable?
 * - #world_readable?
 * - #readable_real?
 * - #setgid?
 * - #setuid?
 * - #size
 * - #size?
 * - #socket?
 * - #sticky?
 * - #symlink?
 * - #writable?
 * - #world_writable?
 * - #writable_real?
 * - #zero?
 *
 * === File property and manipulation methods
 *
 * These methods are a facade for File:
 * - #atime
 * - #ctime
 * - #mtime
 * - #chmod(mode)
 * - #lchmod(mode)
 * - #chown(owner, group)
 * - #lchown(owner, group)
 * - #fnmatch(pattern, *args)
 * - #fnmatch?(pattern, *args)
 * - #ftype
 * - #make_link(old)
 * - #open(*args, &block)
 * - #readlink
 * - #rename(to)
 * - #stat
 * - #lstat
 * - #make_symlink(old)
 * - #truncate(length)
 * - #utime(atime, mtime)
 * - #basename(*args)
 * - #dirname
 * - #extname
 * - #expand_path(*args)
 * - #split
 *
 * === Directory methods
 *
 * These methods are a facade for Dir:
 * - Pathname.glob(*args)
 * - Pathname.getwd / Pathname.pwd
 * - #rmdir
 * - #entries
 * - #each_entry(&block)
 * - #mkdir(*args)
 * - #opendir(*args)
 *
 * === IO
 *
 * These methods are a facade for IO:
 * - #each_line(*args, &block)
 * - #read(*args)
 * - #binread(*args)
 * - #readlines(*args)
 * - #sysopen(*args)
 *
 * === Utilities
 *
 * These methods are a mixture of Find, FileUtils, and others:
 * - #find(&block)
 * - #mkpath
 * - #rmtree
 * - #unlink / #delete
 *
 *
 * == Method documentation
 *
 * As the above section shows, most of the methods in Pathname are facades.  The
 * documentation for these methods generally just says, for instance, "See
 * FileTest.writable?", as you should be familiar with the original method
 * anyway, and its documentation (e.g. through +ri+) will contain more
 * information.  In some cases, a brief description will follow.
 */
void
Init_pathname()
{
    id_at_path = rb_intern("@path");
    id_to_path = rb_intern("to_path");

    rb_cPathname = rb_define_class("Pathname", rb_cObject);
    rb_define_method(rb_cPathname, "initialize", path_initialize, 1);
    rb_define_method(rb_cPathname, "freeze", path_freeze, 0);
    rb_define_method(rb_cPathname, "taint", path_taint, 0);
    rb_define_method(rb_cPathname, "untaint", path_untaint, 0);
    rb_define_method(rb_cPathname, "==", path_eq, 1);
    rb_define_method(rb_cPathname, "===", path_eq, 1);
    rb_define_method(rb_cPathname, "eql?", path_eq, 1);
    rb_define_method(rb_cPathname, "<=>", path_cmp, 1);
    rb_define_method(rb_cPathname, "hash", path_hash, 0);
    rb_define_method(rb_cPathname, "to_s", path_to_s, 0);
    rb_define_method(rb_cPathname, "to_path", path_to_s, 0);
    rb_define_method(rb_cPathname, "inspect", path_inspect, 0);
    rb_define_method(rb_cPathname, "sub", path_sub, -1);
    rb_define_method(rb_cPathname, "sub_ext", path_sub_ext, 1);
    rb_define_method(rb_cPathname, "realpath", path_realpath, -1);
    rb_define_method(rb_cPathname, "realdirpath", path_realdirpath, -1);
}
