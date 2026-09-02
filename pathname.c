#include "ruby.h"
#include "ruby/thread.h"
#include "internal.h"
#include "internal/file.h"
#include "internal/string.h"
#include "internal/vm.h"

#include <sys/stat.h>
#ifdef _WIN32
# include "win32/dir.h"
# define dirent direct
#else
# include <fcntl.h>
# include <dirent.h>
# include <unistd.h>
#endif

#if defined(HAVE_OPENAT) && defined(HAVE_UNLINKAT) && defined(HAVE_FSTATAT) && \
    defined(HAVE_FDOPENDIR) && defined(HAVE_DIRFD) && \
    defined(O_DIRECTORY) && defined(O_NOFOLLOW)
# define USE_OPENAT_RMTREE 1
#endif

#ifndef O_CLOEXEC
# define O_CLOEXEC 0
#endif
#ifndef S_ISDIR
# define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif

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
static ID id_puts;
static ID rmtree_keyword_ids[3];

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
 * :markup: markdown
 *
 * call-seq:
 *   sub_ext(replacement) -> new_pathname
 *
 * Returns a new pathname whose path is the path in `self`,
 * after specified changes:
 *
 * ```ruby
 * Pathname('t.tmp').sub_ext('.txt') # => #<Pathname:t.txt>     # Extension replaced.
 * Pathname('temp').sub_ext('.txt')  # => #<Pathname:temp.txt>  # Extension added.
 * Pathname('t.tmp').sub_ext('')     # => #<Pathname:t>         # Extension removed.
 * ```
 *
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

/*
 * Depth-first removal, preferring the *at family so that the traversal
 * never follows symbolic links and cannot be redirected by concurrent
 * renames of ancestor directories (requested by akr in [Bug #21640]).
 * Platforms without the *at family (e.g. Windows) traverse by full path
 * with the same skeleton.
 */

struct rmtree_ctx {
    char *path;                 /* current path, for error messages */
    size_t len, cap;
    rb_encoding *enc;
    int force;
    int err;                    /* first errno, when !force */
    char *errpath;
    volatile int interrupted;
};

static int
rmtree_fail(struct rmtree_ctx *ctx, int e)
{
    if (ctx->force) return 0;
    if (!ctx->err) {
        char *p = malloc(ctx->len + 1);
        if (p) memcpy(p, ctx->path, ctx->len + 1);
        ctx->err = e;
        ctx->errpath = p;
    }
    return -1;
}

static int
rmtree_push(struct rmtree_ctx *ctx, const char *name)
{
    size_t nlen = strlen(name);
    size_t need = ctx->len + nlen + 2;
    if (need > ctx->cap) {
        size_t cap = ctx->cap;
        char *p;
        while (cap < need) cap *= 2;
        p = realloc(ctx->path, cap);
        if (!p) {
            rmtree_fail(ctx, ENOMEM);
            return -1;
        }
        ctx->path = p;
        ctx->cap = cap;
    }
    ctx->path[ctx->len] = '/';
    memcpy(ctx->path + ctx->len + 1, name, nlen + 1);
    ctx->len += nlen + 1;
    return 0;
}

static void
rmtree_pop(struct rmtree_ctx *ctx, size_t len)
{
    ctx->len = len;
    ctx->path[len] = '\0';
}

#ifdef USE_OPENAT_RMTREE
#define RMTREE_OPEN_FLAGS (O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
#define RMTREE_ROOT_FD AT_FDCWD
#define RMTREE_DIRFD(dirp) dirfd(dirp)

static int
rmtree_do_lstat(struct rmtree_ctx *ctx, int pfd, const char *name, struct stat *st)
{
    (void)ctx;
    return fstatat(pfd, name, st, AT_SYMLINK_NOFOLLOW);
}

static DIR *
rmtree_do_opendir(struct rmtree_ctx *ctx, int pfd, const char *name, const struct stat *st)
{
    struct stat st2;
    DIR *dir;
    int fd = openat(pfd, name, RMTREE_OPEN_FLAGS);
    (void)ctx;
    if (fd < 0) return NULL;
    if (fstat(fd, &st2) != 0 ||
        st2.st_dev != st->st_dev || st2.st_ino != st->st_ino) {
        /* the entry was replaced between lstat and openat */
        close(fd);
        errno = ELOOP;
        return NULL;
    }
    if (!(dir = fdopendir(fd))) {
        int e = errno;
        close(fd);
        errno = e;
    }
    return dir;
}

static int
rmtree_do_unlink(struct rmtree_ctx *ctx, int pfd, const char *name)
{
    (void)ctx;
    return unlinkat(pfd, name, 0);
}

static int
rmtree_do_rmdir(struct rmtree_ctx *ctx, int pfd, const char *name)
{
    (void)ctx;
    return unlinkat(pfd, name, AT_REMOVEDIR);
}
#else
#define RMTREE_ROOT_FD -1
#define RMTREE_DIRFD(dirp) -1

static int
rmtree_do_lstat(struct rmtree_ctx *ctx, int pfd, const char *name, struct stat *st)
{
    (void)pfd;
    (void)name;
    return lstat(ctx->path, st);
}

static DIR *
rmtree_do_opendir(struct rmtree_ctx *ctx, int pfd, const char *name, const struct stat *st)
{
    (void)pfd;
    (void)name;
    (void)st;
    return opendir(ctx->path);
}

static int
rmtree_do_unlink(struct rmtree_ctx *ctx, int pfd, const char *name)
{
    (void)pfd;
    (void)name;
    return unlink(ctx->path);
}

static int
rmtree_do_rmdir(struct rmtree_ctx *ctx, int pfd, const char *name)
{
    (void)pfd;
    (void)name;
    return rmdir(ctx->path);
}
#endif

static int rmtree_entry(struct rmtree_ctx *ctx, int pfd, const char *name, int root);

/* remove all children of dir; closes dir */
static int
rmtree_children(DIR *dir, struct rmtree_ctx *ctx)
{
    char **names = NULL;
    size_t n = 0, cap = 0, i;
    int ret = 0;
    struct dirent *de;

    while ((de = readdir(dir)) != NULL) {
        const char *nm = de->d_name;
        size_t nlen;
        char *copy;
        if (nm[0] == '.' && (!nm[1] || (nm[1] == '.' && !nm[2]))) continue;
        if (n >= cap) {
            char **p;
            cap = cap ? cap * 2 : 16;
            p = realloc(names, cap * sizeof(*names));
            if (!p) {
                rmtree_fail(ctx, ENOMEM);
                ret = -1;
                goto done;
            }
            names = p;
        }
        nlen = strlen(nm) + 1;
        copy = malloc(nlen);
        if (!copy) {
            rmtree_fail(ctx, ENOMEM);
            ret = -1;
            goto done;
        }
        memcpy(copy, nm, nlen);
        names[n++] = copy;
    }
    for (i = 0; i < n; i++) {
        if (ctx->interrupted) {
            ret = -1;
            break;
        }
        if (rmtree_entry(ctx, RMTREE_DIRFD(dir), names[i], 0)) {
            ret = -1;
            break;
        }
    }
  done:
    for (i = 0; i < n; i++) free(names[i]);
    free(names);
    closedir(dir);
    return ret;
}

static int
rmtree_entry(struct rmtree_ctx *ctx, int pfd, const char *name, int root)
{
    struct stat st;
    size_t len = ctx->len;
    int ret = 0;

    if (!root && rmtree_push(ctx, name)) return -1;
    if (rmtree_do_lstat(ctx, pfd, name, &st) != 0) {
        if (root || errno != ENOENT) ret = rmtree_fail(ctx, errno);
    }
    else if (S_ISDIR(st.st_mode)) {
        DIR *dir = rmtree_do_opendir(ctx, pfd, name, &st);
        if (!dir) {
            ret = rmtree_fail(ctx, errno);
        }
        else if (rmtree_children(dir, ctx)) {
            ret = -1;
        }
        else if (!ctx->interrupted &&
                 rmtree_do_rmdir(ctx, pfd, name) != 0 && errno != ENOENT) {
            ret = rmtree_fail(ctx, errno);
        }
    }
    else if (rmtree_do_unlink(ctx, pfd, name) != 0 && errno != ENOENT) {
        ret = rmtree_fail(ctx, errno);
    }
    if (!root) rmtree_pop(ctx, len);
    return ret;
}

static void *
rmtree_body(void *ptr)
{
    struct rmtree_ctx *ctx = ptr;
    rmtree_entry(ctx, RMTREE_ROOT_FD, ctx->path, 1);
    return NULL;
}

static void
rmtree_ubf(void *ptr)
{
    ((struct rmtree_ctx *)ptr)->interrupted = 1;
}

static VALUE
rmtree_call(VALUE ptr)
{
    struct rmtree_ctx *ctx = (struct rmtree_ctx *)ptr;
    size_t rootlen = ctx->len;

    for (;;) {
        ctx->interrupted = 0;
        rb_thread_call_without_gvl(rmtree_body, ctx, rmtree_ubf, ctx);
        if (!ctx->interrupted || ctx->err) break;
        rb_thread_check_ints();
        /* spurious wakeup: restart the traversal (removal is idempotent) */
        rmtree_pop(ctx, rootlen);
    }
    if (ctx->err) {
        if (ctx->errpath) {
            rb_syserr_fail_str(ctx->err, rb_enc_str_new_cstr(ctx->errpath, ctx->enc));
        }
        rb_syserr_fail(ctx->err, "rmtree");
    }
    return Qnil;
}

static VALUE
rmtree_ensure(VALUE ptr)
{
    struct rmtree_ctx *ctx = (struct rmtree_ctx *)ptr;
    free(ctx->path);
    free(ctx->errpath);
    return Qnil;
}

static void
rmtree_remove(VALUE path, int force)
{
    struct rmtree_ctx ctx = {0};
    long len;

    check_strpath(path);
    ctx.force = force;
    ctx.enc = rb_enc_get(path);
    len = RSTRING_LEN(path);
    ctx.cap = len + 32;
    ctx.path = malloc(ctx.cap);
    if (!ctx.path) rb_memerror();
    memcpy(ctx.path, RSTRING_PTR(path), len);
    ctx.path[len] = '\0';
    ctx.len = len;
    rb_ensure(rmtree_call, (VALUE)&ctx, rmtree_ensure, (VALUE)&ctx);
}

/* :nodoc: */
static VALUE
path_remove_entry(int argc, VALUE *argv, VALUE self)
{
    VALUE path, force;

    rb_scan_args(argc, argv, "11", &path, &force);
    rmtree_remove(path, argc < 2 ? 1 : RTEST(force));
    return Qnil;
}

/*
 * :markup: markdown
 *
 * call-seq:
 *   rmtree(noop: nil, verbose: nil, secure: nil) -> self
 *
 * Deletes the entire filetree at the path in `self`; returns `self`:
 *
 * ```ruby
 * dir_pn = Pathname('foo/bar/baz') # => #<Pathname:foo/bar/baz>
 * dir_pn.mkpath                    # Create 'baz' and intermediate directories.
 * file_pn = dir_pn.join('t.tmp')   # => #<Pathname:foo/bar/baz/t.tmp>
 * file_pn.write('foo')             # Create file at nested directory 'baz'.
 * Pathname('foo').rmtree           # Delete the entire tree at directory 'foo'.
 * Pathname('foo').exist?           # => false
 * ```
 *
 * Use method #rmdir to delete a single (empty) directory.
 *
 * Keyword arguments `noop` and `verbose` work as in FileUtils.rm_rf;
 * `secure` is accepted for compatibility and ignored
 * (the traversal never follows symbolic links).
 *
 */
static VALUE
path_rmtree(int argc, VALUE *argv, VALUE self)
{
    /* The name "rmtree" is borrowed from File::Path of Perl.
     * File::Path provides "mkpath" and "rmtree". */
    VALUE opts, kwvals[3];
    VALUE path = get_strpath(self);

    rb_scan_args(argc, argv, "0:", &opts);
    kwvals[0] = kwvals[1] = kwvals[2] = Qnil;
    if (!NIL_P(opts)) {
        rb_get_kwargs(opts, rmtree_keyword_ids, 0, 3, kwvals);
        if (UNDEF_P(kwvals[0])) kwvals[0] = Qnil;
        if (UNDEF_P(kwvals[1])) kwvals[1] = Qnil;
    }
    if (RTEST(kwvals[1])) {
        VALUE mesg = rb_sprintf("rm -rf %"PRIsVALUE, path);
        rb_funcall(rb_gv_get("$stdout"), id_puts, 1, mesg);
    }
    if (RTEST(kwvals[0])) return self;
    rmtree_remove(path, 1);
    return self;
}

#include "pathname.rbinc"

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
    rb_define_method(rb_cPathname, "rmtree", path_rmtree, -1);
    rb_define_private_method(rb_cPathname, "remove_entry", path_remove_entry, -1);

    rb_provide("pathname.so");
    rb_provide("pathname.rb");
}

void
init_ids(void)
{
#undef rb_intern
    id_at_path = rb_intern("@path");
    id_sub = rb_intern("sub");
    id_puts = rb_intern("puts");
    rmtree_keyword_ids[0] = rb_intern("noop");
    rmtree_keyword_ids[1] = rb_intern("verbose");
    rmtree_keyword_ids[2] = rb_intern("secure");
}
