#include "ruby.h"
#include "ruby/encoding.h"

static VALUE rb_cPathname;
static ID id_ENOTDIR;
static ID id_at_path;
static ID id_atime;
static ID id_base;
static ID id_basename;
static ID id_binread;
static ID id_binwrite;
static ID id_birthtime;
static ID id_blockdev_p;
static ID id_chardev_p;
static ID id_chmod;
static ID id_chown;
static ID id_ctime;
static ID id_directory_p;
static ID id_dirname;
static ID id_empty_p;
static ID id_entries;
static ID id_executable_p;
static ID id_executable_real_p;
static ID id_exist_p;
static ID id_expand_path;
static ID id_extname;
static ID id_file_p;
static ID id_fnmatch;
static ID id_foreach;
static ID id_ftype;
static ID id_getwd;
static ID id_glob;
static ID id_grpowned_p;
static ID id_lchmod;
static ID id_lchown;
static ID id_link;
static ID id_lstat;
static ID id_mkdir;
static ID id_mtime;
static ID id_open;
static ID id_owned_p;
static ID id_pipe_p;
static ID id_read;
static ID id_readable_p;
static ID id_readable_real_p;
static ID id_readlines;
static ID id_readlink;
static ID id_realdirpath;
static ID id_realpath;
static ID id_rename;
static ID id_rmdir;
static ID id_setgid_p;
static ID id_setuid_p;
static ID id_size;
static ID id_size_p;
static ID id_socket_p;
static ID id_split;
static ID id_stat;
static ID id_sticky_p;
static ID id_sub;
static ID id_symlink;
static ID id_symlink_p;
static ID id_sysopen;
static ID id_to_path;
static ID id_truncate;
static ID id_unlink;
static ID id_utime;
static ID id_world_readable_p;
static ID id_world_writable_p;
static ID id_writable_p;
static ID id_writable_real_p;
static ID id_write;
static ID id_zero_p;

static VALUE
get_strpath(VALUE obj)
{
    VALUE strpath;
    strpath = rb_ivar_get(obj, id_at_path);
    if (!RB_TYPE_P(strpath, T_STRING))
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
 * If +path+ contains a NULL character (<tt>\0</tt>), an ArgumentError is raised.
 */
static VALUE
path_initialize(VALUE self, VALUE arg)
{
    VALUE str;
    if (RB_TYPE_P(arg, T_STRING)) {
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

/*
 * call-seq:
 *   pathname.freeze -> obj
 *
 * Freezes this Pathname.
 *
 * See Object.freeze.
 */
static VALUE
path_freeze(VALUE self)
{
    rb_call_super(0, 0);
    rb_str_freeze(get_strpath(self));
    return self;
}

/*
 * call-seq:
 *   pathname.taint -> obj
 *
 * Taints this Pathname.
 *
 * See Object.taint.
 */
static VALUE
path_taint(VALUE self)
{
    rb_call_super(0, 0);
    rb_obj_taint(get_strpath(self));
    return self;
}

/*
 * call-seq:
 *   pathname.untaint -> obj
 *
 * Untaints this Pathname.
 *
 * See Object.untaint.
 */
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
 *  Provides a case-sensitive comparison operator for pathnames.
 *
 *	Pathname.new('/usr') <=> Pathname.new('/usr/bin')
 *	    #=> -1
 *	Pathname.new('/usr/bin') <=> Pathname.new('/usr/bin')
 *	    #=> 0
 *	Pathname.new('/usr/bin') <=> Pathname.new('/USR/BIN')
 *	    #=> 1
 *
 *  It will return +-1+, +0+ or +1+ depending on the value of the left argument
 *  relative to the right argument. Or it will return +nil+ if the arguments
 *  are not comparable.
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

#ifndef ST2FIX
#define ST2FIX(h) LONG2FIX((long)(h))
#endif

/* :nodoc: */
static VALUE
path_hash(VALUE self)
{
    return ST2FIX(rb_str_hash(get_strpath(self)));
}

/*
 *  call-seq:
 *    pathname.to_s             -> string
 *    pathname.to_path          -> string
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
    return rb_sprintf("#<%s:%"PRIsVALUE">", c, str);
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
    VALUE str = get_strpath(self);
    VALUE str2;
    long extlen;
    const char *ext;
    const char *p;

    StringValue(repl);
    p = RSTRING_PTR(str);
    extlen = RSTRING_LEN(str);
    ext = ruby_enc_find_extname(p, &extlen, rb_enc_get(str));
    if (ext == NULL) {
        ext = p + RSTRING_LEN(str);
    }
    else if (extlen <= 1) {
        ext += extlen;
    }
    str2 = rb_str_subseq(str, 0, ext-p);
    rb_str_append(str2, repl);
    OBJ_INFECT(str2, str);
    return rb_class_new_instance(1, &str2, rb_obj_class(self));
}

/* Facade for File */

/*
 * Returns the real (absolute) pathname for +self+ in the actual
 * filesystem.
 *
 * Does not contain symlinks or useless dots, +..+ and +.+.
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
    str = rb_funcall(rb_cFile, id_realpath, 2, get_strpath(self), basedir);
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * Returns the real (absolute) pathname of +self+ in the actual filesystem.
 *
 * Does not contain symlinks or useless dots, +..+ and +.+.
 *
 * The last component of the real pathname can be nonexistent.
 */
static VALUE
path_realdirpath(int argc, VALUE *argv, VALUE self)
{
    VALUE basedir, str;
    rb_scan_args(argc, argv, "01", &basedir);
    str = rb_funcall(rb_cFile, id_realdirpath, 2, get_strpath(self), basedir);
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * call-seq:
 *   pathname.each_line {|line| ... }
 *   pathname.each_line(sep=$/ [, open_args]) {|line| block }     -> nil
 *   pathname.each_line(limit [, open_args]) {|line| block }      -> nil
 *   pathname.each_line(sep, limit [, open_args]) {|line| block } -> nil
 *   pathname.each_line(...)                                      -> an_enumerator
 *
 * Iterates over each line in the file and yields a String object for each.
 */
static VALUE
path_each_line(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "03", &args[1], &args[2], &args[3]);
    if (rb_block_given_p()) {
        return rb_block_call(rb_cFile, id_foreach, 1+n, args, 0, 0);
    }
    else {
        return rb_funcallv(rb_cFile, id_foreach, 1+n, args);
    }
}

/*
 * call-seq:
 *   pathname.read([length [, offset]]) -> string
 *   pathname.read([length [, offset]], open_args) -> string
 *
 * Returns all data from the file, or the first +N+ bytes if specified.
 *
 * See File.read.
 *
 */
static VALUE
path_read(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "03", &args[1], &args[2], &args[3]);
    return rb_funcallv(rb_cFile, id_read, 1+n, args);
}

/*
 * call-seq:
 *   pathname.binread([length [, offset]]) -> string
 *
 * Returns all the bytes from the file, or the first +N+ if specified.
 *
 * See File.binread.
 *
 */
static VALUE
path_binread(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "02", &args[1], &args[2]);
    return rb_funcallv(rb_cFile, id_binread, 1+n, args);
}

/*
 * call-seq:
 *   pathname.write(string, [offset] )   => fixnum
 *   pathname.write(string, [offset], open_args )   => fixnum
 *
 * Writes +contents+ to the file.
 *
 * See File.write.
 *
 */
static VALUE
path_write(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "03", &args[1], &args[2], &args[3]);
    return rb_funcallv(rb_cFile, id_write, 1+n, args);
}

/*
 * call-seq:
 *   pathname.binwrite(string, [offset] )   => fixnum
 *   pathname.binwrite(string, [offset], open_args )   => fixnum
 *
 * Writes +contents+ to the file, opening it in binary mode.
 *
 * See File.binwrite.
 *
 */
static VALUE
path_binwrite(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "03", &args[1], &args[2], &args[3]);
    return rb_funcallv(rb_cFile, id_binwrite, 1+n, args);
}

/*
 * call-seq:
 *   pathname.readlines(sep=$/ [, open_args])     -> array
 *   pathname.readlines(limit [, open_args])      -> array
 *   pathname.readlines(sep, limit [, open_args]) -> array
 *
 * Returns all the lines from the file.
 *
 * See File.readlines.
 *
 */
static VALUE
path_readlines(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "03", &args[1], &args[2], &args[3]);
    return rb_funcallv(rb_cFile, id_readlines, 1+n, args);
}

/*
 * call-seq:
 *   pathname.sysopen([mode, [perm]])  -> fixnum
 *
 * See IO.sysopen.
 *
 */
static VALUE
path_sysopen(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "02", &args[1], &args[2]);
    return rb_funcallv(rb_cIO, id_sysopen, 1+n, args);
}

/*
 * call-seq:
 *   pathname.atime	-> time
 *
 * Returns the last access time for the file.
 *
 * See File.atime.
 */
static VALUE
path_atime(VALUE self)
{
    return rb_funcall(rb_cFile, id_atime, 1, get_strpath(self));
}

#if defined(HAVE_RB_FILE_S_BIRTHTIME)
/*
 * call-seq:
 *   pathname.birthtime	-> time
 *
 * Returns the birth time for the file.
 * If the platform doesn't have birthtime, raises NotImplementedError.
 *
 * See File.birthtime.
 */
static VALUE
path_birthtime(VALUE self)
{
    return rb_funcall(rb_cFile, id_birthtime, 1, get_strpath(self));
}
#else
/* check at compilation time for `respond_to?` */
# define path_birthtime rb_f_notimplement
#endif

/*
 * call-seq:
 *   pathname.ctime	-> time
 *
 * Returns the last change time, using directory information, not the file itself.
 *
 * See File.ctime.
 */
static VALUE
path_ctime(VALUE self)
{
    return rb_funcall(rb_cFile, id_ctime, 1, get_strpath(self));
}

/*
 * call-seq:
 *   pathname.mtime	-> time
 *
 * Returns the last modified time of the file.
 *
 * See File.mtime.
 */
static VALUE
path_mtime(VALUE self)
{
    return rb_funcall(rb_cFile, id_mtime, 1, get_strpath(self));
}

/*
 * call-seq:
 *   pathname.chmod	-> integer
 *
 * Changes file permissions.
 *
 * See File.chmod.
 */
static VALUE
path_chmod(VALUE self, VALUE mode)
{
    return rb_funcall(rb_cFile, id_chmod, 2, mode, get_strpath(self));
}

/*
 * call-seq:
 *   pathname.lchmod	-> integer
 *
 * Same as Pathname.chmod, but does not follow symbolic links.
 *
 * See File.lchmod.
 */
static VALUE
path_lchmod(VALUE self, VALUE mode)
{
    return rb_funcall(rb_cFile, id_lchmod, 2, mode, get_strpath(self));
}

/*
 * call-seq:
 *   pathname.chown	-> integer
 *
 * Change owner and group of the file.
 *
 * See File.chown.
 */
static VALUE
path_chown(VALUE self, VALUE owner, VALUE group)
{
    return rb_funcall(rb_cFile, id_chown, 3, owner, group, get_strpath(self));
}

/*
 * call-seq:
 *   pathname.lchown	-> integer
 *
 * Same as Pathname.chown, but does not follow symbolic links.
 *
 * See File.lchown.
 */
static VALUE
path_lchown(VALUE self, VALUE owner, VALUE group)
{
    return rb_funcall(rb_cFile, id_lchown, 3, owner, group, get_strpath(self));
}

/*
 * call-seq:
 *    pathname.fnmatch(pattern, [flags])        -> string
 *    pathname.fnmatch?(pattern, [flags])       -> string
 *
 * Return +true+ if the receiver matches the given pattern.
 *
 * See File.fnmatch.
 */
static VALUE
path_fnmatch(int argc, VALUE *argv, VALUE self)
{
    VALUE str = get_strpath(self);
    VALUE pattern, flags;
    if (rb_scan_args(argc, argv, "11", &pattern, &flags) == 1)
        return rb_funcall(rb_cFile, id_fnmatch, 2, pattern, str);
    else
        return rb_funcall(rb_cFile, id_fnmatch, 3, pattern, str, flags);
}

/*
 * call-seq:
 *   pathname.ftype	-> string
 *
 * Returns "type" of file ("file", "directory", etc).
 *
 * See File.ftype.
 */
static VALUE
path_ftype(VALUE self)
{
    return rb_funcall(rb_cFile, id_ftype, 1, get_strpath(self));
}

/*
 * call-seq:
 *   pathname.make_link(old)
 *
 * Creates a hard link at _pathname_.
 *
 * See File.link.
 */
static VALUE
path_make_link(VALUE self, VALUE old)
{
    return rb_funcall(rb_cFile, id_link, 2, old, get_strpath(self));
}

/*
 * Opens the file for reading or writing.
 *
 * See File.open.
 */
static VALUE
path_open(int argc, VALUE *argv, VALUE self)
{
    VALUE args[4];
    int n;

    args[0] = get_strpath(self);
    n = rb_scan_args(argc, argv, "03", &args[1], &args[2], &args[3]);
    if (rb_block_given_p()) {
        return rb_block_call(rb_cFile, id_open, 1+n, args, 0, 0);
    }
    else {
        return rb_funcallv(rb_cFile, id_open, 1+n, args);
    }
}

/*
 * Read symbolic link.
 *
 * See File.readlink.
 */
static VALUE
path_readlink(VALUE self)
{
    VALUE str;
    str = rb_funcall(rb_cFile, id_readlink, 1, get_strpath(self));
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * Rename the file.
 *
 * See File.rename.
 */
static VALUE
path_rename(VALUE self, VALUE to)
{
    return rb_funcall(rb_cFile, id_rename, 2, get_strpath(self), to);
}

/*
 * Returns a File::Stat object.
 *
 * See File.stat.
 */
static VALUE
path_stat(VALUE self)
{
    return rb_funcall(rb_cFile, id_stat, 1, get_strpath(self));
}

/*
 * See File.lstat.
 */
static VALUE
path_lstat(VALUE self)
{
    return rb_funcall(rb_cFile, id_lstat, 1, get_strpath(self));
}

/*
 * call-seq:
 *   pathname.make_symlink(old)
 *
 * Creates a symbolic link.
 *
 * See File.symlink.
 */
static VALUE
path_make_symlink(VALUE self, VALUE old)
{
    return rb_funcall(rb_cFile, id_symlink, 2, old, get_strpath(self));
}

/*
 * Truncates the file to +length+ bytes.
 *
 * See File.truncate.
 */
static VALUE
path_truncate(VALUE self, VALUE length)
{
    return rb_funcall(rb_cFile, id_truncate, 2, get_strpath(self), length);
}

/*
 * Update the access and modification times of the file.
 *
 * See File.utime.
 */
static VALUE
path_utime(VALUE self, VALUE atime, VALUE mtime)
{
    return rb_funcall(rb_cFile, id_utime, 3, atime, mtime, get_strpath(self));
}

/*
 * Returns the last component of the path.
 *
 * See File.basename.
 */
static VALUE
path_basename(int argc, VALUE *argv, VALUE self)
{
    VALUE str = get_strpath(self);
    VALUE fext;
    if (rb_scan_args(argc, argv, "01", &fext) == 0)
        str = rb_funcall(rb_cFile, id_basename, 1, str);
    else
        str = rb_funcall(rb_cFile, id_basename, 2, str, fext);
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * Returns all but the last component of the path.
 *
 * See File.dirname.
 */
static VALUE
path_dirname(VALUE self)
{
    VALUE str = get_strpath(self);
    str = rb_funcall(rb_cFile, id_dirname, 1, str);
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * Returns the file's extension.
 *
 * See File.extname.
 */
static VALUE
path_extname(VALUE self)
{
    VALUE str = get_strpath(self);
    return rb_funcall(rb_cFile, id_extname, 1, str);
}

/*
 * Returns the absolute path for the file.
 *
 * See File.expand_path.
 */
static VALUE
path_expand_path(int argc, VALUE *argv, VALUE self)
{
    VALUE str = get_strpath(self);
    VALUE dname;
    if (rb_scan_args(argc, argv, "01", &dname) == 0)
        str = rb_funcall(rb_cFile, id_expand_path, 1, str);
    else
        str = rb_funcall(rb_cFile, id_expand_path, 2, str, dname);
    return rb_class_new_instance(1, &str, rb_obj_class(self));
}

/*
 * Returns the #dirname and the #basename in an Array.
 *
 * See File.split.
 */
static VALUE
path_split(VALUE self)
{
    VALUE str = get_strpath(self);
    VALUE ary, dirname, basename;
    ary = rb_funcall(rb_cFile, id_split, 1, str);
    ary = rb_check_array_type(ary);
    dirname = rb_ary_entry(ary, 0);
    basename = rb_ary_entry(ary, 1);
    dirname = rb_class_new_instance(1, &dirname, rb_obj_class(self));
    basename = rb_class_new_instance(1, &basename, rb_obj_class(self));
    return rb_ary_new3(2, dirname, basename);
}

/*
 * See FileTest.blockdev?.
 */
static VALUE
path_blockdev_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_blockdev_p, 1, get_strpath(self));
}

/*
 * See FileTest.chardev?.
 */
static VALUE
path_chardev_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_chardev_p, 1, get_strpath(self));
}

/*
 * See FileTest.executable?.
 */
static VALUE
path_executable_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_executable_p, 1, get_strpath(self));
}

/*
 * See FileTest.executable_real?.
 */
static VALUE
path_executable_real_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_executable_real_p, 1, get_strpath(self));
}

/*
 * See FileTest.exist?.
 */
static VALUE
path_exist_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_exist_p, 1, get_strpath(self));
}

/*
 * See FileTest.grpowned?.
 */
static VALUE
path_grpowned_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_grpowned_p, 1, get_strpath(self));
}

/*
 * See FileTest.directory?.
 */
static VALUE
path_directory_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_directory_p, 1, get_strpath(self));
}

/*
 * See FileTest.file?.
 */
static VALUE
path_file_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_file_p, 1, get_strpath(self));
}

/*
 * See FileTest.pipe?.
 */
static VALUE
path_pipe_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_pipe_p, 1, get_strpath(self));
}

/*
 * See FileTest.socket?.
 */
static VALUE
path_socket_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_socket_p, 1, get_strpath(self));
}

/*
 * See FileTest.owned?.
 */
static VALUE
path_owned_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_owned_p, 1, get_strpath(self));
}

/*
 * See FileTest.readable?.
 */
static VALUE
path_readable_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_readable_p, 1, get_strpath(self));
}

/*
 * See FileTest.world_readable?.
 */
static VALUE
path_world_readable_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_world_readable_p, 1, get_strpath(self));
}

/*
 * See FileTest.readable_real?.
 */
static VALUE
path_readable_real_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_readable_real_p, 1, get_strpath(self));
}

/*
 * See FileTest.setuid?.
 */
static VALUE
path_setuid_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_setuid_p, 1, get_strpath(self));
}

/*
 * See FileTest.setgid?.
 */
static VALUE
path_setgid_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_setgid_p, 1, get_strpath(self));
}

/*
 * See FileTest.size.
 */
static VALUE
path_size(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_size, 1, get_strpath(self));
}

/*
 * See FileTest.size?.
 */
static VALUE
path_size_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_size_p, 1, get_strpath(self));
}

/*
 * See FileTest.sticky?.
 */
static VALUE
path_sticky_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_sticky_p, 1, get_strpath(self));
}

/*
 * See FileTest.symlink?.
 */
static VALUE
path_symlink_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_symlink_p, 1, get_strpath(self));
}

/*
 * See FileTest.writable?.
 */
static VALUE
path_writable_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_writable_p, 1, get_strpath(self));
}

/*
 * See FileTest.world_writable?.
 */
static VALUE
path_world_writable_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_world_writable_p, 1, get_strpath(self));
}

/*
 * See FileTest.writable_real?.
 */
static VALUE
path_writable_real_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_writable_real_p, 1, get_strpath(self));
}

/*
 * See FileTest.zero?.
 */
static VALUE
path_zero_p(VALUE self)
{
    return rb_funcall(rb_mFileTest, id_zero_p, 1, get_strpath(self));
}

/*
 * Tests the file is empty.
 *
 * See Dir#empty? and FileTest.empty?.
 */
static VALUE
path_empty_p(VALUE self)
{

    VALUE path = get_strpath(self);
    if (RTEST(rb_funcall(rb_mFileTest, id_directory_p, 1, path)))
        return rb_funcall(rb_cDir, id_empty_p, 1, path);
    else
        return rb_funcall(rb_mFileTest, id_empty_p, 1, path);
}

static VALUE
s_glob_i(RB_BLOCK_CALL_FUNC_ARGLIST(elt, klass))
{
    return rb_yield(rb_class_new_instance(1, &elt, klass));
}

/*
 * Returns or yields Pathname objects.
 *
 *  Pathname.glob("lib/i*.rb")
 *	#=> [#<Pathname:lib/ipaddr.rb>, #<Pathname:lib/irb.rb>]
 *
 * See Dir.glob.
 */
static VALUE
path_s_glob(int argc, VALUE *argv, VALUE klass)
{
    VALUE args[3];
    int n;

    n = rb_scan_args(argc, argv, "12", &args[0], &args[1], &args[2]);
    if (rb_block_given_p()) {
        return rb_block_call(rb_cDir, id_glob, n, args, s_glob_i, klass);
    }
    else {
        VALUE ary;
        long i;
        ary = rb_funcallv(rb_cDir, id_glob, n, args);
        ary = rb_convert_type(ary, T_ARRAY, "Array", "to_ary");
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            VALUE elt = RARRAY_AREF(ary, i);
            elt = rb_class_new_instance(1, &elt, klass);
            rb_ary_store(ary, i, elt);
        }
        return ary;
    }
}

static VALUE
glob_i(RB_BLOCK_CALL_FUNC_ARGLIST(elt, self))
{
    elt = rb_funcall(self, '+', 1, elt);
    return rb_yield(elt);
}

/*
 * Returns or yields Pathname objects.
 *
 *  Pathname("ruby-2.4.2").glob("R*.md")
 *  #=> [#<Pathname:ruby-2.4.2/README.md>, #<Pathname:ruby-2.4.2/README.ja.md>]
 *
 * See Dir.glob.
 * This method uses the +base+ keyword argument of Dir.glob.
 */
static VALUE
path_glob(int argc, VALUE *argv, VALUE self)
{
    VALUE args[3];
    int n;

    n = rb_scan_args(argc, argv, "11", &args[0], &args[1]);
    if (n == 1)
      args[1] = INT2FIX(0);

    args[2] = rb_hash_new();
    rb_hash_aset(args[2], ID2SYM(id_base), get_strpath(self));

    n = 3;

    if (rb_block_given_p()) {
        return rb_block_call(rb_cDir, id_glob, n, args, glob_i, self);
    }
    else {
        VALUE ary;
        long i;
        ary = rb_funcallv(rb_cDir, id_glob, n, args);
        ary = rb_convert_type(ary, T_ARRAY, "Array", "to_ary");
        for (i = 0; i < RARRAY_LEN(ary); i++) {
            VALUE elt = RARRAY_AREF(ary, i);
            elt = rb_funcall(self, '+', 1, elt);
            rb_ary_store(ary, i, elt);
        }
        return ary;
    }
}

/*
 * Returns the current working directory as a Pathname.
 *
 *	Pathname.getwd
 *	    #=> #<Pathname:/home/zzak/projects/ruby>
 *
 * See Dir.getwd.
 */
static VALUE
path_s_getwd(VALUE klass)
{
    VALUE str;
    str = rb_funcall(rb_cDir, id_getwd, 0);
    return rb_class_new_instance(1, &str, klass);
}

/*
 * Return the entries (files and subdirectories) in the directory, each as a
 * Pathname object.
 *
 * The results contains just the names in the directory, without any trailing
 * slashes or recursive look-up.
 *
 *   pp Pathname.new('/usr/local').entries
 *   #=> [#<Pathname:share>,
 *   #    #<Pathname:lib>,
 *   #    #<Pathname:..>,
 *   #    #<Pathname:include>,
 *   #    #<Pathname:etc>,
 *   #    #<Pathname:bin>,
 *   #    #<Pathname:man>,
 *   #    #<Pathname:games>,
 *   #    #<Pathname:.>,
 *   #    #<Pathname:sbin>,
 *   #    #<Pathname:src>]
 *
 * The result may contain the current directory <code>#<Pathname:.></code> and
 * the parent directory <code>#<Pathname:..></code>.
 *
 * If you don't want +.+ and +..+ and
 * want directories, consider Pathname#children.
 */
static VALUE
path_entries(VALUE self)
{
    VALUE klass, str, ary;
    long i;
    klass = rb_obj_class(self);
    str = get_strpath(self);
    ary = rb_funcall(rb_cDir, id_entries, 1, str);
    ary = rb_convert_type(ary, T_ARRAY, "Array", "to_ary");
    for (i = 0; i < RARRAY_LEN(ary); i++) {
	VALUE elt = RARRAY_AREF(ary, i);
        elt = rb_class_new_instance(1, &elt, klass);
        rb_ary_store(ary, i, elt);
    }
    return ary;
}

/*
 * Create the referenced directory.
 *
 * See Dir.mkdir.
 */
static VALUE
path_mkdir(int argc, VALUE *argv, VALUE self)
{
    VALUE str = get_strpath(self);
    VALUE vmode;
    if (rb_scan_args(argc, argv, "01", &vmode) == 0)
        return rb_funcall(rb_cDir, id_mkdir, 1, str);
    else
        return rb_funcall(rb_cDir, id_mkdir, 2, str, vmode);
}

/*
 * Remove the referenced directory.
 *
 * See Dir.rmdir.
 */
static VALUE
path_rmdir(VALUE self)
{
    return rb_funcall(rb_cDir, id_rmdir, 1, get_strpath(self));
}

/*
 * Opens the referenced directory.
 *
 * See Dir.open.
 */
static VALUE
path_opendir(VALUE self)
{
    VALUE args[1];

    args[0] = get_strpath(self);
    return rb_block_call(rb_cDir, id_open, 1, args, 0, 0);
}

static VALUE
each_entry_i(RB_BLOCK_CALL_FUNC_ARGLIST(elt, klass))
{
    return rb_yield(rb_class_new_instance(1, &elt, klass));
}

/*
 * Iterates over the entries (files and subdirectories) in the directory,
 * yielding a Pathname object for each entry.
 */
static VALUE
path_each_entry(VALUE self)
{
    VALUE args[1];

    args[0] = get_strpath(self);
    return rb_block_call(rb_cDir, id_foreach, 1, args, each_entry_i, rb_obj_class(self));
}

static VALUE
unlink_body(VALUE str)
{
    return rb_funcall(rb_cDir, id_unlink, 1, str);
}

static VALUE
unlink_rescue(VALUE str, VALUE errinfo)
{
    return rb_funcall(rb_cFile, id_unlink, 1, str);
}

/*
 * Removes a file or directory, using File.unlink if +self+ is a file, or
 * Dir.unlink as necessary.
 */
static VALUE
path_unlink(VALUE self)
{
    VALUE eENOTDIR = rb_const_get_at(rb_mErrno, id_ENOTDIR);
    VALUE str = get_strpath(self);
    return rb_rescue2(unlink_body, str, unlink_rescue, str, eENOTDIR, (VALUE)0);
}

/*
 * :call-seq:
 *  Pathname(path)  -> pathname
 *
 * Creates a new Pathname object from the given string, +path+, and returns
 * pathname object.
 *
 * In order to use this constructor, you must first require the Pathname
 * standard library extension.
 *
 *	require 'pathname'
 *	Pathname("/home/zzak")
 *	#=> #<Pathname:/home/zzak>
 *
 * See also Pathname::new for more information.
 */
static VALUE
path_f_pathname(VALUE self, VALUE str)
{
    return rb_class_new_instance(1, &str, rb_cPathname);
}

/*
 *
 * Pathname represents the name of a file or directory on the filesystem,
 * but not the file itself.
 *
 * The pathname depends on the Operating System: Unix, Windows, etc.
 * This library works with pathnames of local OS, however non-Unix pathnames
 * are supported experimentally.
 *
 * A Pathname can be relative or absolute.  It's not until you try to
 * reference the file that it even matters whether the file exists or not.
 *
 * Pathname is immutable.  It has no method for destructive update.
 *
 * The goal of this class is to manipulate file path information in a neater
 * way than standard Ruby provides.  The examples below demonstrate the
 * difference.
 *
 * *All* functionality from File, FileTest, and some from Dir and FileUtils is
 * included, in an unsurprising way.  It is essentially a facade for all of
 * these, and more.
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
 * all a path is.  None of these access the file system except for
 * #mountpoint?, #children, #each_child, #realdirpath and #realpath.
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
 * - #birthtime
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
Init_pathname(void)
{
    InitVM(pathname);

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
    rb_define_method(rb_cPathname, "each_line", path_each_line, -1);
    rb_define_method(rb_cPathname, "read", path_read, -1);
    rb_define_method(rb_cPathname, "binread", path_binread, -1);
    rb_define_method(rb_cPathname, "readlines", path_readlines, -1);
    rb_define_method(rb_cPathname, "write", path_write, -1);
    rb_define_method(rb_cPathname, "binwrite", path_binwrite, -1);
    rb_define_method(rb_cPathname, "sysopen", path_sysopen, -1);
    rb_define_method(rb_cPathname, "atime", path_atime, 0);
    rb_define_method(rb_cPathname, "birthtime", path_birthtime, 0);
    rb_define_method(rb_cPathname, "ctime", path_ctime, 0);
    rb_define_method(rb_cPathname, "mtime", path_mtime, 0);
    rb_define_method(rb_cPathname, "chmod", path_chmod, 1);
    rb_define_method(rb_cPathname, "lchmod", path_lchmod, 1);
    rb_define_method(rb_cPathname, "chown", path_chown, 2);
    rb_define_method(rb_cPathname, "lchown", path_lchown, 2);
    rb_define_method(rb_cPathname, "fnmatch", path_fnmatch, -1);
    rb_define_method(rb_cPathname, "fnmatch?", path_fnmatch, -1);
    rb_define_method(rb_cPathname, "ftype", path_ftype, 0);
    rb_define_method(rb_cPathname, "make_link", path_make_link, 1);
    rb_define_method(rb_cPathname, "open", path_open, -1);
    rb_define_method(rb_cPathname, "readlink", path_readlink, 0);
    rb_define_method(rb_cPathname, "rename", path_rename, 1);
    rb_define_method(rb_cPathname, "stat", path_stat, 0);
    rb_define_method(rb_cPathname, "lstat", path_lstat, 0);
    rb_define_method(rb_cPathname, "make_symlink", path_make_symlink, 1);
    rb_define_method(rb_cPathname, "truncate", path_truncate, 1);
    rb_define_method(rb_cPathname, "utime", path_utime, 2);
    rb_define_method(rb_cPathname, "basename", path_basename, -1);
    rb_define_method(rb_cPathname, "dirname", path_dirname, 0);
    rb_define_method(rb_cPathname, "extname", path_extname, 0);
    rb_define_method(rb_cPathname, "expand_path", path_expand_path, -1);
    rb_define_method(rb_cPathname, "split", path_split, 0);
    rb_define_method(rb_cPathname, "blockdev?", path_blockdev_p, 0);
    rb_define_method(rb_cPathname, "chardev?", path_chardev_p, 0);
    rb_define_method(rb_cPathname, "executable?", path_executable_p, 0);
    rb_define_method(rb_cPathname, "executable_real?", path_executable_real_p, 0);
    rb_define_method(rb_cPathname, "exist?", path_exist_p, 0);
    rb_define_method(rb_cPathname, "grpowned?", path_grpowned_p, 0);
    rb_define_method(rb_cPathname, "directory?", path_directory_p, 0);
    rb_define_method(rb_cPathname, "file?", path_file_p, 0);
    rb_define_method(rb_cPathname, "pipe?", path_pipe_p, 0);
    rb_define_method(rb_cPathname, "socket?", path_socket_p, 0);
    rb_define_method(rb_cPathname, "owned?", path_owned_p, 0);
    rb_define_method(rb_cPathname, "readable?", path_readable_p, 0);
    rb_define_method(rb_cPathname, "world_readable?", path_world_readable_p, 0);
    rb_define_method(rb_cPathname, "readable_real?", path_readable_real_p, 0);
    rb_define_method(rb_cPathname, "setuid?", path_setuid_p, 0);
    rb_define_method(rb_cPathname, "setgid?", path_setgid_p, 0);
    rb_define_method(rb_cPathname, "size", path_size, 0);
    rb_define_method(rb_cPathname, "size?", path_size_p, 0);
    rb_define_method(rb_cPathname, "sticky?", path_sticky_p, 0);
    rb_define_method(rb_cPathname, "symlink?", path_symlink_p, 0);
    rb_define_method(rb_cPathname, "writable?", path_writable_p, 0);
    rb_define_method(rb_cPathname, "world_writable?", path_world_writable_p, 0);
    rb_define_method(rb_cPathname, "writable_real?", path_writable_real_p, 0);
    rb_define_method(rb_cPathname, "zero?", path_zero_p, 0);
    rb_define_method(rb_cPathname, "empty?", path_empty_p, 0);
    rb_define_singleton_method(rb_cPathname, "glob", path_s_glob, -1);
    rb_define_singleton_method(rb_cPathname, "getwd", path_s_getwd, 0);
    rb_define_singleton_method(rb_cPathname, "pwd", path_s_getwd, 0);
    rb_define_method(rb_cPathname, "glob", path_glob, -1);
    rb_define_method(rb_cPathname, "entries", path_entries, 0);
    rb_define_method(rb_cPathname, "mkdir", path_mkdir, -1);
    rb_define_method(rb_cPathname, "rmdir", path_rmdir, 0);
    rb_define_method(rb_cPathname, "opendir", path_opendir, 0);
    rb_define_method(rb_cPathname, "each_entry", path_each_entry, 0);
    rb_define_method(rb_cPathname, "unlink", path_unlink, 0);
    rb_define_method(rb_cPathname, "delete", path_unlink, 0);
    rb_undef_method(rb_cPathname, "=~");
    rb_define_global_function("Pathname", path_f_pathname, 1);
}

void
InitVM_pathname(void)
{
#undef rb_intern
    id_at_path = rb_intern("@path");
    id_to_path = rb_intern("to_path");
    id_ENOTDIR = rb_intern("ENOTDIR");
    id_atime = rb_intern("atime");
    id_basename = rb_intern("basename");
    id_base = rb_intern("base");
    id_binread = rb_intern("binread");
    id_binwrite = rb_intern("binwrite");
    id_birthtime = rb_intern("birthtime");
    id_blockdev_p = rb_intern("blockdev?");
    id_chardev_p = rb_intern("chardev?");
    id_chmod = rb_intern("chmod");
    id_chown = rb_intern("chown");
    id_ctime = rb_intern("ctime");
    id_directory_p = rb_intern("directory?");
    id_dirname = rb_intern("dirname");
    id_empty_p = rb_intern("empty?");
    id_entries = rb_intern("entries");
    id_executable_p = rb_intern("executable?");
    id_executable_real_p = rb_intern("executable_real?");
    id_exist_p = rb_intern("exist?");
    id_expand_path = rb_intern("expand_path");
    id_extname = rb_intern("extname");
    id_file_p = rb_intern("file?");
    id_fnmatch = rb_intern("fnmatch");
    id_foreach = rb_intern("foreach");
    id_ftype = rb_intern("ftype");
    id_getwd = rb_intern("getwd");
    id_glob = rb_intern("glob");
    id_grpowned_p = rb_intern("grpowned?");
    id_lchmod = rb_intern("lchmod");
    id_lchown = rb_intern("lchown");
    id_link = rb_intern("link");
    id_lstat = rb_intern("lstat");
    id_mkdir = rb_intern("mkdir");
    id_mtime = rb_intern("mtime");
    id_open = rb_intern("open");
    id_owned_p = rb_intern("owned?");
    id_pipe_p = rb_intern("pipe?");
    id_read = rb_intern("read");
    id_readable_p = rb_intern("readable?");
    id_readable_real_p = rb_intern("readable_real?");
    id_readlines = rb_intern("readlines");
    id_readlink = rb_intern("readlink");
    id_realdirpath = rb_intern("realdirpath");
    id_realpath = rb_intern("realpath");
    id_rename = rb_intern("rename");
    id_rmdir = rb_intern("rmdir");
    id_setgid_p = rb_intern("setgid?");
    id_setuid_p = rb_intern("setuid?");
    id_size = rb_intern("size");
    id_size_p = rb_intern("size?");
    id_socket_p = rb_intern("socket?");
    id_split = rb_intern("split");
    id_stat = rb_intern("stat");
    id_sticky_p = rb_intern("sticky?");
    id_sub = rb_intern("sub");
    id_symlink = rb_intern("symlink");
    id_symlink_p = rb_intern("symlink?");
    id_sysopen = rb_intern("sysopen");
    id_truncate = rb_intern("truncate");
    id_unlink = rb_intern("unlink");
    id_utime = rb_intern("utime");
    id_world_readable_p = rb_intern("world_readable?");
    id_world_writable_p = rb_intern("world_writable?");
    id_writable_p = rb_intern("writable?");
    id_writable_real_p = rb_intern("writable_real?");
    id_write = rb_intern("write");
    id_zero_p = rb_intern("zero?");
}
