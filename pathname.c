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
 *   Pathname('a')  <=> Pathname('b')  # => -1
 *   Pathname('a')  <=> Pathname('ab') # => -1
 *   Pathname('a')  <=> Pathname('a')  # => 0
 *   Pathname('b')  <=> Pathname('a')  # => 1
 *   Pathname('ab') <=> Pathname('a')  # => 1
 *   Pathname('ab') <=> 'a'            # => nil
 *
 * Two pathnames that are different may refer to the same entry in the filesystem:
 *
 *   Pathname('lib') <=> Pathname('./lib') # => 1
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
 * :markup: markdown
 *
 * call-seq:
 *   sub(pattern, replacement) -> new_pathname
 *   sub(pattern) {|match| ... } -> new_pathname
 *
 * Returns a new pathname whose path is the path in `self`,
 * after the specified substitutions.
 *
 * Argument `pattern` may be a string or a Regexp;
 * argument `replacement` may be a string or a hash.
 *
 * Varying types for the argument values makes this method very versatile.
 *
 * Below are some simple examples;
 * for many more related examples (using strings, not pathnames),
 * see [Substitution Methods](rdoc-ref:String@Substitution+Methods).
 *
 * With arguments `pattern` and string `replacement` given,
 * replaces the first matching substring with the given replacement string:
 *
 * ```ruby
 * pn = Pathname('abracadabra.txt') # => #<Pathname:abracadabra.txt>
 * pn.sub('bra', 'xyzzy')           # => #<Pathname:axyzzycadabra.txt>
 * pn.sub(/bra/, 'xyzzy')           # => #<Pathname:axyzzycadabra.txt>
 * pn.sub('nope', 'xyzzy')          # => #<Pathname:abracadabra.txt>
 * ```
 *
 * With arguments `pattern` and hash `replacement` given,
 * replaces the first matching substring with a value from the given replacement hash,
 * or removes it:
 *
 * ```ruby
 * h = {'a' => 'A', 'b' => 'B', 'c' => 'C'}
 * pn.sub('b', h) # => #<Pathname:aBracadabra.txt>
 * pn.sub(/b/, h) # => #<Pathname:aBracadabra.txt>
 * pn.sub(/d/, h) # => #<Pathname:abracaabra.txt>  # 'd' removed.
 * ```
 *
 * With argument `pattern` and a block given,
 * calls the block with the first matching substring;
 * replaces that substring with the block’s return value:
 *
 * ```ruby
 * pn.sub('b') {|match| match.upcase } # => #<Pathname:aBracadabra.txt>
 * pn.sub(/X/) {|match| match.upcase } # => #<Pathname:abracadabra.txt>
 * ```
 *
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

/* :nodoc: */
static VALUE
same_paths(VALUE self, VALUE a, VALUE b)
{
    check_strpath(a);
    check_strpath(b);
    if (CASEFOLD_FILESYSTEM)
        return RBOOL(rb_str_casecmp(a, b) == INT2FIX(0));
    else
        return rb_str_equal(a, b);
}

/*
 * :markup: markdown
 *
 * call-seq:
 *   root? -> true or false
 *
 * Returns whether the path in `self` points to a root directory.
 *
 * On a non-Windows system, a root directory path is one whose name begins
 * with one or more slash characters (`'/'):
 *
 * ```ruby
 * Pathname('/').root?       # => true
 * Pathname('////').root?    # => true
 * Pathname('/usr').root?    # => false
 * Pathname('foo').root?     # => false
 * ```
 *
 * Does not resolve dot directories:
 *
 * ```ruby
 * Pathname('/usr/.').root?  # => false
 * Pathname('/usr/..').root? # => false
 * ```
 *
 * On a Windows system, a root directory path is one whose name begins as above,
 * or with a device letter followed by a colon character (`':'`)
 * and one or more slash characters (`'/'):
 *
 * ```ruby
 * Pathname('/').root?      # => true
 * Pathname('////').root?   # => true
 * Pathname('C:/').root?    # => true
 * Pathname('C:////').root? # => true
 * Pathname('c:/').root?    # => true
 * Pathname('H:/').root?    # => true
 * Pathname('C:/m').root?   # => false
 * Pathname('C:').root?     # => false
 * ```
 *
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
 *   Pathname('/home').absolute? # => true
 *   Pathname('lib').absolute?   # => false
 *
 * The result is OS-dependent for some paths:
 *
 *   Pathname('C:/').absolute?   # => true   # On Windows.
 *   Pathname('C:/').absolute?   # => false  # Elsewhere.
 *
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
/* split_names(path) -> prefix, [name, ...] */
static VALUE
split_names(VALUE self, VALUE path)
{
    rb_encoding *enc = rb_enc_get(check_strpath(path));
    const char *beg = RSTRING_PTR(path), *ptr = beg;
    const char *end = RSTRING_END(path);
    const char *root = rb_enc_path_skip_prefix_root(ptr, end, enc);
    VALUE pre = rb_str_subseq(path, 0, root - ptr);
    VALUE names = rb_ary_new();
    while (ptr < end) {
        const char *next = rb_enc_path_next(ptr, end, enc);
        if (next > ptr) rb_ary_push(names, rb_str_subseq(path, ptr - beg, next - ptr));
        ptr = next;
        while (ptr < end && isdirsep(*ptr)) ++ptr;
    }
    return rb_assoc_new(pre, names);
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

/* :nodoc: */
/* add_trailing_separator(path) -> path */
static VALUE
add_trailing_separator(VALUE self, VALUE path)
{
    if (RSTRING_LEN(check_strpath(path)) <= 0) return path;
    rb_encoding *enc = rb_enc_get(path);
    const char *name = RSTRING_PTR(path);
    const char *end = RSTRING_END(path);
    const char *top = rb_enc_path_skip_prefix(name, end, enc);
    if (top < end && isdirsep(end[-1])) {
        if (end[-1] == '/' || rb_enc_prev_char(top, end, end, enc) == end - 1)
            return path;
    }
    return rb_str_cat_cstr(rb_str_dup(path), "/");
}

/* :nodoc: */
static VALUE
del_trailing_separator(VALUE self, VALUE path)
{
    long len = RSTRING_LEN(check_strpath(path));
    if (len <= 0) return path;
    rb_encoding *enc = rb_enc_get(path);
    const char *name = RSTRING_PTR(path);
    const char *end = name + len, *tail = end;
    const char *top = rb_enc_path_skip_prefix(name, end, enc);
    if (tail > top && isdirsep(tail[-1])) {
        while (--tail > top && isdirsep(tail[-1]));
        if (tail > top &&
            tail[0] != '/' &&
            !rb_str_enc_fastpath(path) &&
            rb_enc_left_char_head(top, tail, end, enc) != tail) {
            /* trailing byte, not a directory separator */
            ++tail;
        }
        if (tail < end) {
            if (tail == name || (drive_letter && tail == top && top[-1] == ':')) {
                ++tail;
            }
        }
    }
    if (tail == end) return path;
    return rb_str_subseq(path, 0, tail - name);
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

    rb_define_private_method(rb_cPathname, "same_paths?", same_paths, 2);
    rb_define_private_method(rb_cPathname, "has_separator?", has_separator_p, 1);
    rb_define_private_method(rb_cPathname, "chop_basename", chop_basename, 1);
    rb_define_private_method(rb_cPathname, "split_names", split_names, 1);
    rb_define_private_method(rb_cPathname, "has_trailing_separator?", has_trailing_separator, 1);
    rb_define_private_method(rb_cPathname, "add_trailing_separator", add_trailing_separator, 1);
    rb_define_private_method(rb_cPathname, "del_trailing_separator", del_trailing_separator, 1);

    rb_provide("pathname.so");
}

void
init_ids(void)
{
#undef rb_intern
    id_at_path = rb_intern("@path");
    id_sub = rb_intern("sub");
}
