/**********************************************************************

  ruby.c -

  $Author$
  created at: Tue Aug 10 12:47:31 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#include "ruby/internal/config.h"

#include <ctype.h>
#include <stdio.h>
#include <sys/types.h>

#ifdef __CYGWIN__
# include <windows.h>
# include <sys/cygwin.h>
#endif

#if defined(LOAD_RELATIVE) && defined(HAVE_DLADDR)
# include <dlfcn.h>
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#if defined(HAVE_FCNTL_H)
# include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
# include <sys/fcntl.h>
#endif

#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif

#include "dln.h"
#include "eval_intern.h"
#include "internal.h"
#include "internal/cmdlineopt.h"
#include "internal/cont.h"
#include "internal/error.h"
#include "internal/file.h"
#include "internal/inits.h"
#include "internal/io.h"
#include "internal/load.h"
#include "internal/loadpath.h"
#include "internal/missing.h"
#include "internal/object.h"
#include "internal/thread.h"
#include "internal/ruby_parser.h"
#include "internal/variable.h"
#include "ruby/encoding.h"
#include "ruby/thread.h"
#include "ruby/util.h"
#include "ruby/version.h"
#include "ruby/internal/error.h"

#define singlebit_only_p(x) !((x) & ((x)-1))
STATIC_ASSERT(Qnil_1bit_from_Qfalse, singlebit_only_p(Qnil^Qfalse));
STATIC_ASSERT(Qundef_1bit_from_Qnil, singlebit_only_p(Qundef^Qnil));

#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif
#ifndef O_ACCMODE
# define O_ACCMODE (O_RDONLY | O_WRONLY | O_RDWR)
#endif

void Init_ruby_description(ruby_cmdline_options_t *opt);

#ifndef HAVE_STDLIB_H
char *getenv();
#endif

#ifndef DISABLE_RUBYGEMS
# define DISABLE_RUBYGEMS 0
#endif
#if DISABLE_RUBYGEMS
#define DEFAULT_RUBYGEMS_ENABLED "disabled"
#else
#define DEFAULT_RUBYGEMS_ENABLED "enabled"
#endif

void rb_warning_category_update(unsigned int mask, unsigned int bits);

#define COMMA ,
#define FEATURE_BIT(bit) (1U << feature_##bit)
#define EACH_FEATURES(X, SEP) \
    X(gems) \
    SEP \
    X(error_highlight) \
    SEP \
    X(did_you_mean) \
    SEP \
    X(syntax_suggest) \
    SEP \
    X(rubyopt) \
    SEP \
    X(frozen_string_literal) \
    SEP \
    X(rjit) \
    SEP \
    X(yjit) \
    /* END OF FEATURES */
#define EACH_DEBUG_FEATURES(X, SEP) \
    X(frozen_string_literal) \
    /* END OF DEBUG FEATURES */
#define AMBIGUOUS_FEATURE_NAMES 0 /* no ambiguous feature names now */
#define DEFINE_FEATURE(bit) feature_##bit
#define DEFINE_DEBUG_FEATURE(bit) feature_debug_##bit
enum feature_flag_bits {
    EACH_FEATURES(DEFINE_FEATURE, COMMA),
    feature_debug_flag_first,
#if defined(RJIT_FORCE_ENABLE) || !USE_YJIT
    DEFINE_FEATURE(jit) = feature_rjit,
#else
    DEFINE_FEATURE(jit) = feature_yjit,
#endif
    feature_jit_mask = FEATURE_BIT(rjit) | FEATURE_BIT(yjit),

    feature_debug_flag_begin = feature_debug_flag_first - 1,
    EACH_DEBUG_FEATURES(DEFINE_DEBUG_FEATURE, COMMA),
    feature_flag_count
};

#define MULTI_BITS_P(bits) ((bits) & ((bits) - 1))

#define DEBUG_BIT(bit) (1U << feature_debug_##bit)

#define DUMP_BIT(bit) (1U << dump_##bit)
#define DEFINE_DUMP(bit) dump_##bit
#define EACH_DUMPS(X, SEP) \
    X(version) \
    SEP \
    X(copyright) \
    SEP \
    X(usage) \
    SEP \
    X(help) \
    SEP \
    X(yydebug) \
    SEP \
    X(syntax) \
    SEP \
    X(parsetree) \
    SEP \
    X(insns) \
    /* END OF DUMPS */
enum dump_flag_bits {
    dump_version_v,
    dump_opt_error_tolerant,
    dump_opt_comment,
    dump_opt_optimize,
    EACH_DUMPS(DEFINE_DUMP, COMMA),
    dump_exit_bits = (DUMP_BIT(yydebug) | DUMP_BIT(syntax) |
                      DUMP_BIT(parsetree) | DUMP_BIT(insns)),
    dump_optional_bits = (DUMP_BIT(opt_error_tolerant) |
                          DUMP_BIT(opt_comment) |
                          DUMP_BIT(opt_optimize))
};

static inline void
rb_feature_set_to(ruby_features_t *feat, unsigned int bit_mask, unsigned int bit_set)
{
    feat->mask |= bit_mask;
    feat->set = (feat->set & ~bit_mask) | bit_set;
}

#define FEATURE_SET_TO(feat, bit_mask, bit_set) \
    rb_feature_set_to(&(feat), bit_mask, bit_set)
#define FEATURE_SET(feat, bits) FEATURE_SET_TO(feat, bits, bits)
#define FEATURE_SET_RESTORE(feat, save) FEATURE_SET_TO(feat, (save).mask, (save).set & (save).mask)
#define FEATURE_SET_P(feat, bits) ((feat).set & FEATURE_BIT(bits))
#define FEATURE_USED_P(feat, bits) ((feat).mask & FEATURE_BIT(bits))
#define FEATURE_SET_BITS(feat) ((feat).set & (feat).mask)

static void init_ids(ruby_cmdline_options_t *);

#define src_encoding_index GET_VM()->src_encoding_index

enum {
    COMPILATION_FEATURES = (
        0
        | FEATURE_BIT(frozen_string_literal)
        | FEATURE_BIT(debug_frozen_string_literal)
        ),
    DEFAULT_FEATURES = (
        (FEATURE_BIT(debug_flag_first)-1)
#if DISABLE_RUBYGEMS
        & ~FEATURE_BIT(gems)
#endif
        & ~FEATURE_BIT(frozen_string_literal)
        & ~feature_jit_mask
        )
};

#define BACKTRACE_LENGTH_LIMIT_VALID_P(n) ((n) >= -1)
#define OPT_BACKTRACE_LENGTH_LIMIT_VALID_P(opt) \
    BACKTRACE_LENGTH_LIMIT_VALID_P((opt)->backtrace_length_limit)

static ruby_cmdline_options_t *
cmdline_options_init(ruby_cmdline_options_t *opt)
{
    MEMZERO(opt, *opt, 1);
    init_ids(opt);
    opt->src.enc.index = src_encoding_index;
    opt->ext.enc.index = -1;
    opt->intern.enc.index = -1;
    opt->features.set = DEFAULT_FEATURES;
#ifdef RJIT_FORCE_ENABLE /* to use with: ./configure cppflags="-DRJIT_FORCE_ENABLE" */
    opt->features.set |= FEATURE_BIT(rjit);
#elif defined(YJIT_FORCE_ENABLE)
    opt->features.set |= FEATURE_BIT(yjit);
#endif
    opt->dump |= DUMP_BIT(opt_optimize);
    opt->backtrace_length_limit = LONG_MIN;

    return opt;
}

static rb_ast_t *load_file(VALUE parser, VALUE fname, VALUE f, int script,
                       ruby_cmdline_options_t *opt);
static VALUE open_load_file(VALUE fname_v, int *xflag);
static void forbid_setid(const char *, const ruby_cmdline_options_t *);
#define forbid_setid(s) forbid_setid((s), opt)

static struct {
    int argc;
    char **argv;
} origarg;

static const char esc_standout[] = "\n\033[1;7m";
static const char esc_bold[] = "\033[1m";
static const char esc_reset[] = "\033[0m";
static const char esc_none[] = "";
#define USAGE_INDENT "  "       /* macro for concatenation */

static void
show_usage_part(const char *str, const unsigned int namelen,
                const char *str2, const unsigned int secondlen,
                const char *desc,
                int help, int highlight, unsigned int w, int columns)
{
    static const int indent_width = (int)rb_strlen_lit(USAGE_INDENT);
    const char *sb = highlight ? esc_bold : esc_none;
    const char *se = highlight ? esc_reset : esc_none;
    unsigned int desclen = (unsigned int)strcspn(desc, "\n");
    if (!help && desclen > 0 && strchr(".;:", desc[desclen-1])) --desclen;
    if (help && (namelen + 1 > w) && /* a padding space */
        (int)(namelen + secondlen + indent_width) >= columns) {
        printf(USAGE_INDENT "%s" "%.*s" "%s\n", sb, namelen, str, se);
        if (secondlen > 0) {
            const int second_end = secondlen;
            int n = 0;
            if (str2[n] == ',') n++;
            if (str2[n] == ' ') n++;
            printf(USAGE_INDENT "%s" "%.*s" "%s\n", sb, second_end-n, str2+n, se);
        }
        printf("%-*s%.*s\n", w + indent_width, USAGE_INDENT, desclen, desc);
    }
    else {
        const int wrap = help && namelen + secondlen >= w;
        printf(USAGE_INDENT "%s%.*s%-*.*s%s%-*s%.*s\n", sb, namelen, str,
               (wrap ? 0 : w - namelen),
               (help ? secondlen : 0), str2, se,
               (wrap ? (int)(w + rb_strlen_lit("\n" USAGE_INDENT)) : 0),
               (wrap ? "\n" USAGE_INDENT : ""),
               desclen, desc);
    }
    if (help) {
        while (desc[desclen]) {
            desc += desclen + rb_strlen_lit("\n");
            desclen = (unsigned int)strcspn(desc, "\n");
            printf("%-*s%.*s\n", w + indent_width, USAGE_INDENT, desclen, desc);
        }
    }
}

static void
show_usage_line(const struct ruby_opt_message *m,
                int help, int highlight, unsigned int w, int columns)
{
    const char *str = m->str;
    const unsigned int namelen = m->namelen, secondlen = m->secondlen;
    const char *desc = str + namelen + secondlen;
    show_usage_part(str, namelen - 1, str + namelen, secondlen - 1, desc,
                    help, highlight, w, columns);
}

void
ruby_show_usage_line(const char *name, const char *secondary, const char *description,
                     int help, int highlight, unsigned int width, int columns)
{
    unsigned int namelen = (unsigned int)strlen(name);
    unsigned int secondlen = (secondary ? (unsigned int)strlen(secondary) : 0);
    show_usage_part(name, namelen, secondary, secondlen,
                    description, help, highlight, width, columns);
}

static void
usage(const char *name, int help, int highlight, int columns)
{
#define M(shortopt, longopt, desc) RUBY_OPT_MESSAGE(shortopt, longopt, desc)

#if USE_YJIT
# define PLATFORM_JIT_OPTION "--yjit"
#else
# define PLATFORM_JIT_OPTION "--rjit (experimental)"
#endif

    /* This message really ought to be max 23 lines.
     * Removed -h because the user already knows that option. Others? */
    static const struct ruby_opt_message usage_msg[] = {
        M("-0[octal]",	   "",                     "Set input record separator ($/):\n"
            "-0 for \\0; -00 for paragraph mode; -0777 for slurp mode."),
        M("-a",		   "",                     "Split each input line ($_) into fields ($F)."),
        M("-c",		   "",			   "Check syntax (no execution)."),
        M("-Cdirpath",     "",			   "Execute program in specified directory."),
        M("-d",		   ", --debug",		   "Set debugging flag ($DEBUG) to true."),
        M("-e 'code'",     "",			   "Execute given Ruby code; multiple -e allowed."),
        M("-Eex[:in]",     ", --encoding=ex[:in]", "Set default external and internal encodings."),
        M("-Fpattern",	   "",			   "Set input field separator ($;); used with -a."),
        M("-i[extension]", "",			   "Set ARGF in-place mode;\n"
            "create backup files with given extension."),
        M("-Idirpath",     "",			   "Add specified directory to load paths ($LOAD_PATH);\n"
            "multiple -I allowed."),
        M("-l",		   "",			   "Set output record separator ($\\) to $/;\n"
            "used for line-oriented output."),
        M("-n",		   "",			   "Run program in gets loop."),
        M("-p",		   "",			   "Like -n, with printing added."),
        M("-rlibrary",	   "",			   "Require the given library."),
        M("-s",		   "",			   "Define global variables using switches following program path."),
        M("-S",		   "",			   "Search directories found in the PATH environment variable."),
        M("-v",		   "",			   "Print version; set $VERBOSE to true."),
        M("-w",		   "",			   "Synonym for -W1."),
        M("-W[level=2|:category]", "",             "Set warning flag ($-W):\n"
            "0 for silent; 1 for moderate; 2 for verbose."),
        M("-x[dirpath]",   "",			   "Execute Ruby code starting from a #!ruby line."),
        M("--jit",         "",                     "Enable JIT for the platform; same as " PLATFORM_JIT_OPTION "."),
#if USE_YJIT
        M("--yjit",        "",                     "Enable in-process JIT compiler."),
#endif
#if USE_RJIT
        M("--rjit",        "",                     "Enable pure-Ruby JIT compiler (experimental)."),
#endif
        M("-h",		   "",			   "Print this help message; use --help for longer message."),
    };
    STATIC_ASSERT(usage_msg_size, numberof(usage_msg) < 25);

    static const struct ruby_opt_message help_msg[] = {
        M("--backtrace-limit=num",        "",            "Set backtrace limit."),
        M("--copyright",                  "",            "Print Ruby copyright."),
        M("--crash-report=template",      "",            "Set template for crash report file."),
        M("--disable=features",           "",            "Disable features; see list below."),
        M("--dump=items",                 "",            "Dump items; see list below."),
        M("--enable=features",            "",            "Enable features; see list below."),
        M("--external-encoding=encoding", "",            "Set default external encoding."),
        M("--help",                       "",            "Print long help message; use -h for short message."),
        M("--internal-encoding=encoding", "",            "Set default internal encoding."),
        M("--parser=parser",              "",            "Set Ruby parser: parse.y or prism."),
        M("--verbose",                    "",            "Set $VERBOSE to true; ignore input from $stdin."),
        M("--version",                    "",            "Print Ruby version."),
        M("-y",                           ", --yydebug", "Print parser log; backward compatibility not guaranteed."),
    };
    static const struct ruby_opt_message dumps[] = {
        M("insns",              "", "Instruction sequences."),
        M("yydebug",            "", "yydebug of yacc parser generator."),
        M("parsetree",          "", "Abstract syntax tree (AST)."),
        M("-optimize",          "", "Disable optimization (affects insns)."),
        M("+error-tolerant",    "", "Error-tolerant parsing (affects yydebug, parsetree)."),
        M("+comment",           "", "Add comments to AST (affects parsetree)."),
    };
    static const struct ruby_opt_message features[] = {
        M("gems",                  "", "Rubygems (only for debugging, default: "DEFAULT_RUBYGEMS_ENABLED")."),
        M("error_highlight",       "", "error_highlight (default: "DEFAULT_RUBYGEMS_ENABLED")."),
        M("did_you_mean",          "", "did_you_mean (default: "DEFAULT_RUBYGEMS_ENABLED")."),
        M("syntax_suggest",        "", "syntax_suggest (default: "DEFAULT_RUBYGEMS_ENABLED")."),
        M("rubyopt",               "", "RUBYOPT environment variable (default: enabled)."),
        M("frozen-string-literal", "", "Freeze all string literals (default: disabled)."),
#if USE_YJIT
        M("yjit",                  "", "In-process JIT compiler (default: disabled)."),
#endif
#if USE_RJIT
        M("rjit",                  "", "Pure-Ruby JIT compiler (experimental, default: disabled)."),
#endif
    };
    static const struct ruby_opt_message warn_categories[] = {
        M("deprecated",   "", "Deprecated features."),
        M("experimental", "", "Experimental features."),
        M("performance",  "", "Performance issues."),
    };
#if USE_RJIT
    extern const struct ruby_opt_message rb_rjit_option_messages[];
#endif
    int i;
    const char *sb = highlight ? esc_standout+1 : esc_none;
    const char *se = highlight ? esc_reset : esc_none;
    const int num = numberof(usage_msg) - (help ? 1 : 0);
    unsigned int w = (columns > 80 ? (columns - 79) / 2 : 0) + 16;
#define SHOW(m) show_usage_line(&(m), help, highlight, w, columns)

    printf("%sUsage:%s %s [options] [--] [filepath] [arguments]\n", sb, se, name);
    for (i = 0; i < num; ++i)
        SHOW(usage_msg[i]);

    if (!help) return;

    if (highlight) sb = esc_standout;

    for (i = 0; i < numberof(help_msg); ++i)
        SHOW(help_msg[i]);
    printf("%s""Dump List:%s\n", sb, se);
    for (i = 0; i < numberof(dumps); ++i)
        SHOW(dumps[i]);
    printf("%s""Features:%s\n", sb, se);
    for (i = 0; i < numberof(features); ++i)
        SHOW(features[i]);
    printf("%s""Warning categories:%s\n", sb, se);
    for (i = 0; i < numberof(warn_categories); ++i)
        SHOW(warn_categories[i]);
#if USE_YJIT
    printf("%s""YJIT options:%s\n", sb, se);
    rb_yjit_show_usage(help, highlight, w, columns);
#endif
#if USE_RJIT
    printf("%s""RJIT options (experimental):%s\n", sb, se);
    for (i = 0; rb_rjit_option_messages[i].str; ++i)
        SHOW(rb_rjit_option_messages[i]);
#endif
}

#define rubylib_path_new rb_str_new

static void
ruby_push_include(const char *path, VALUE (*filter)(VALUE))
{
    const char sep = PATH_SEP_CHAR;
    const char *p, *s;
    VALUE load_path = GET_VM()->load_path;
#ifdef __CYGWIN__
    char rubylib[FILENAME_MAX];
    VALUE buf = 0;
# define is_path_sep(c) ((c) == sep || (c) == ';')
#else
# define is_path_sep(c) ((c) == sep)
#endif

    if (path == 0) return;
    p = path;
    while (*p) {
        long len;
        while (is_path_sep(*p))
            p++;
        if (!*p) break;
        for (s = p; *s && !is_path_sep(*s); s = CharNext(s));
        len = s - p;
#undef is_path_sep

#ifdef __CYGWIN__
        if (*s) {
            if (!buf) {
                buf = rb_str_new(p, len);
                p = RSTRING_PTR(buf);
            }
            else {
                rb_str_resize(buf, len);
                p = strncpy(RSTRING_PTR(buf), p, len);
            }
        }
#ifdef HAVE_CYGWIN_CONV_PATH
#define CONV_TO_POSIX_PATH(p, lib) \
        cygwin_conv_path(CCP_WIN_A_TO_POSIX|CCP_RELATIVE, (p), (lib), sizeof(lib))
#else
# error no cygwin_conv_path
#endif
        if (CONV_TO_POSIX_PATH(p, rubylib) == 0) {
            p = rubylib;
            len = strlen(p);
        }
#endif
        rb_ary_push(load_path, (*filter)(rubylib_path_new(p, len)));
        p = s;
    }
}

static VALUE
identical_path(VALUE path)
{
    return path;
}

static VALUE
locale_path(VALUE path)
{
    rb_enc_associate(path, rb_locale_encoding());
    return path;
}

void
ruby_incpush(const char *path)
{
    ruby_push_include(path, locale_path);
}

static VALUE
expand_include_path(VALUE path)
{
    char *p = RSTRING_PTR(path);
    if (!p)
        return path;
    if (*p == '.' && p[1] == '/')
        return path;
    return rb_file_expand_path(path, Qnil);
}

void
ruby_incpush_expand(const char *path)
{
    ruby_push_include(path, expand_include_path);
}

#undef UTF8_PATH
#if defined _WIN32 || defined __CYGWIN__
static HMODULE libruby;

BOOL WINAPI
DllMain(HINSTANCE dll, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
        libruby = dll;
    return TRUE;
}

HANDLE
rb_libruby_handle(void)
{
    return libruby;
}

static inline void
translit_char_bin(char *p, int from, int to)
{
    while (*p) {
        if ((unsigned char)*p == from)
            *p = to;
        p++;
    }
}
#endif

#ifdef _WIN32
# define UTF8_PATH 1
#endif

#ifndef UTF8_PATH
# define UTF8_PATH 0
#endif
#if UTF8_PATH
# define IF_UTF8_PATH(t, f) t
#else
# define IF_UTF8_PATH(t, f) f
#endif

#if UTF8_PATH
static VALUE
str_conv_enc(VALUE str, rb_encoding *from, rb_encoding *to)
{
    return rb_str_conv_enc_opts(str, from, to,
                                ECONV_UNDEF_REPLACE|ECONV_INVALID_REPLACE,
                                Qnil);
}
#else
# define str_conv_enc(str, from, to) (str)
#endif

void ruby_init_loadpath(void);

#if defined(LOAD_RELATIVE)
static VALUE
runtime_libruby_path(void)
{
#if defined _WIN32 || defined __CYGWIN__
    DWORD ret;
    DWORD len = 32;
    VALUE path;
    VALUE wsopath = rb_str_new(0, len*sizeof(WCHAR));
    WCHAR *wlibpath;
    char *libpath;

    while (wlibpath = (WCHAR *)RSTRING_PTR(wsopath),
           ret = GetModuleFileNameW(libruby, wlibpath, len),
           (ret == len))
    {
        rb_str_modify_expand(wsopath, len*sizeof(WCHAR));
        rb_str_set_len(wsopath, (len += len)*sizeof(WCHAR));
    }
    if (!ret || ret > len) rb_fatal("failed to get module file name");
#if defined __CYGWIN__
    {
        const int win_to_posix = CCP_WIN_W_TO_POSIX | CCP_RELATIVE;
        size_t newsize = cygwin_conv_path(win_to_posix, wlibpath, 0, 0);
        if (!newsize) rb_fatal("failed to convert module path to cygwin");
        path = rb_str_new(0, newsize);
        libpath = RSTRING_PTR(path);
        if (cygwin_conv_path(win_to_posix, wlibpath, libpath, newsize)) {
            rb_str_resize(path, 0);
        }
    }
#else
    {
        DWORD i;
        for (len = ret, i = 0; i < len; ++i) {
            if (wlibpath[i] == L'\\') {
                wlibpath[i] = L'/';
                ret = i+1;	/* chop after the last separator */
            }
        }
    }
    len = WideCharToMultiByte(CP_UTF8, 0, wlibpath, ret, NULL, 0, NULL, NULL);
    path = rb_utf8_str_new(0, len);
    libpath = RSTRING_PTR(path);
    WideCharToMultiByte(CP_UTF8, 0, wlibpath, ret, libpath, len, NULL, NULL);
#endif
    rb_str_resize(wsopath, 0);
    return path;
#elif defined(HAVE_DLADDR)
    Dl_info dli;
    VALUE fname, path;
    const void* addr = (void *)(VALUE)expand_include_path;

    if (!dladdr((void *)addr, &dli)) {
        return rb_str_new(0, 0);
    }
#ifdef __linux__
    else if (origarg.argc > 0 && origarg.argv && dli.dli_fname == origarg.argv[0]) {
        fname = rb_str_new_cstr("/proc/self/exe");
        path = rb_readlink(fname, NULL);
    }
#endif
    else {
        fname = rb_str_new_cstr(dli.dli_fname);
        path = rb_realpath_internal(Qnil, fname, 1);
    }
    rb_str_resize(fname, 0);
    return path;
#else
# error relative load path is not supported on this platform.
#endif
}
#endif

#define INITIAL_LOAD_PATH_MARK rb_intern_const("@gem_prelude_index")

VALUE ruby_archlibdir_path, ruby_prefix_path;

void
ruby_init_loadpath(void)
{
    VALUE load_path, archlibdir = 0;
    ID id_initial_load_path_mark;
    const char *paths = ruby_initial_load_paths;

#if defined LOAD_RELATIVE
#if !defined ENABLE_MULTIARCH
# define RUBY_ARCH_PATH ""
#elif defined RUBY_ARCH
# define RUBY_ARCH_PATH "/"RUBY_ARCH
#else
# define RUBY_ARCH_PATH "/"RUBY_PLATFORM
#endif
    char *libpath;
    VALUE sopath;
    size_t baselen;
    const char *p;

    sopath = runtime_libruby_path();
    libpath = RSTRING_PTR(sopath);

    p = strrchr(libpath, '/');
    if (p) {
        static const char libdir[] = "/"
#ifdef LIBDIR_BASENAME
            LIBDIR_BASENAME
#else
            "lib"
#endif
            RUBY_ARCH_PATH;
        const ptrdiff_t libdir_len = (ptrdiff_t)sizeof(libdir)
            - rb_strlen_lit(RUBY_ARCH_PATH) - 1;
        static const char bindir[] = "/bin";
        const ptrdiff_t bindir_len = (ptrdiff_t)sizeof(bindir) - 1;

        const char *p2 = NULL;

#ifdef ENABLE_MULTIARCH
      multiarch:
#endif
        if (p - libpath >= bindir_len && !STRNCASECMP(p - bindir_len, bindir, bindir_len)) {
            p -= bindir_len;
            archlibdir = rb_str_subseq(sopath, 0, p - libpath);
            rb_str_cat_cstr(archlibdir, libdir);
            OBJ_FREEZE(archlibdir);
        }
        else if (p - libpath >= libdir_len && !strncmp(p - libdir_len, libdir, libdir_len)) {
            archlibdir = rb_str_subseq(sopath, 0, (p2 ? p2 : p) - libpath);
            OBJ_FREEZE(archlibdir);
            p -= libdir_len;
        }
#ifdef ENABLE_MULTIARCH
        else if (p2) {
            p = p2;
        }
        else {
            p2 = p;
            p = rb_enc_path_last_separator(libpath, p, rb_ascii8bit_encoding());
            if (p) goto multiarch;
            p = p2;
        }
#endif
        baselen = p - libpath;
    }
    else {
        baselen = 0;
    }
    rb_str_resize(sopath, baselen);
    libpath = RSTRING_PTR(sopath);
#define PREFIX_PATH() sopath
#define BASEPATH() rb_str_buf_cat(rb_str_buf_new(baselen+len), libpath, baselen)
#define RUBY_RELATIVE(path, len) rb_str_buf_cat(BASEPATH(), (path), (len))
#else
    const size_t exec_prefix_len = strlen(ruby_exec_prefix);
#define RUBY_RELATIVE(path, len) rubylib_path_new((path), (len))
#define PREFIX_PATH() RUBY_RELATIVE(ruby_exec_prefix, exec_prefix_len)
#endif
    rb_gc_register_address(&ruby_prefix_path);
    ruby_prefix_path = PREFIX_PATH();
    OBJ_FREEZE(ruby_prefix_path);
    if (!archlibdir) archlibdir = ruby_prefix_path;
    rb_gc_register_address(&ruby_archlibdir_path);
    ruby_archlibdir_path = archlibdir;

    load_path = GET_VM()->load_path;

    ruby_push_include(getenv("RUBYLIB"), identical_path);

    id_initial_load_path_mark = INITIAL_LOAD_PATH_MARK;
    while (*paths) {
        size_t len = strlen(paths);
        VALUE path = RUBY_RELATIVE(paths, len);
        rb_ivar_set(path, id_initial_load_path_mark, path);
        rb_ary_push(load_path, path);
        paths += len + 1;
    }

    rb_const_set(rb_cObject, rb_intern_const("TMP_RUBY_PREFIX"), ruby_prefix_path);
}


static void
add_modules(VALUE *req_list, const char *mod)
{
    VALUE list = *req_list;
    VALUE feature;

    if (!list) {
        *req_list = list = rb_ary_hidden_new(0);
    }
    feature = rb_str_cat_cstr(rb_str_tmp_new(0), mod);
    rb_ary_push(list, feature);
}

static void
require_libraries(VALUE *req_list)
{
    VALUE list = *req_list;
    VALUE self = rb_vm_top_self();
    ID require;
    rb_encoding *extenc = rb_default_external_encoding();

    CONST_ID(require, "require");
    while (list && RARRAY_LEN(list) > 0) {
        VALUE feature = rb_ary_shift(list);
        rb_enc_associate(feature, extenc);
        RBASIC_SET_CLASS_RAW(feature, rb_cString);
        OBJ_FREEZE(feature);
        rb_funcallv(self, require, 1, &feature);
    }
    *req_list = 0;
}

static const struct rb_block*
toplevel_context(rb_binding_t *bind)
{
    return &bind->block;
}

static int
process_sflag(int sflag)
{
    if (sflag > 0) {
        long n;
        const VALUE *args;
        VALUE argv = rb_argv;

        n = RARRAY_LEN(argv);
        args = RARRAY_CONST_PTR(argv);
        while (n > 0) {
            VALUE v = *args++;
            char *s = StringValuePtr(v);
            char *p;
            int hyphen = FALSE;

            if (s[0] != '-')
                break;
            n--;
            if (s[1] == '-' && s[2] == '\0')
                break;

            v = Qtrue;
            /* check if valid name before replacing - with _ */
            for (p = s + 1; *p; p++) {
                if (*p == '=') {
                    *p++ = '\0';
                    v = rb_str_new2(p);
                    break;
                }
                if (*p == '-') {
                    hyphen = TRUE;
                }
                else if (*p != '_' && !ISALNUM(*p)) {
                    VALUE name_error[2];
                    name_error[0] =
                        rb_str_new2("invalid name for global variable - ");
                    if (!(p = strchr(p, '='))) {
                        rb_str_cat2(name_error[0], s);
                    }
                    else {
                        rb_str_cat(name_error[0], s, p - s);
                    }
                    name_error[1] = args[-1];
                    rb_exc_raise(rb_class_new_instance(2, name_error, rb_eNameError));
                }
            }
            s[0] = '$';
            if (hyphen) {
                for (p = s + 1; *p; ++p) {
                    if (*p == '-')
                        *p = '_';
                }
            }
            rb_gv_set(s, v);
        }
        n = RARRAY_LEN(argv) - n;
        while (n--) {
            rb_ary_shift(argv);
        }
        return -1;
    }
    return sflag;
}

static long proc_options(long argc, char **argv, ruby_cmdline_options_t *opt, int envopt);

static void
moreswitches(const char *s, ruby_cmdline_options_t *opt, int envopt)
{
    long argc, i, len;
    char **argv, *p;
    const char *ap = 0;
    VALUE argstr, argary;
    void *ptr;

    VALUE src_enc_name = opt->src.enc.name;
    VALUE ext_enc_name = opt->ext.enc.name;
    VALUE int_enc_name = opt->intern.enc.name;
    ruby_features_t feat = opt->features;
    ruby_features_t warn = opt->warn;
    long backtrace_length_limit = opt->backtrace_length_limit;
    const char *crash_report = opt->crash_report;

    while (ISSPACE(*s)) s++;
    if (!*s) return;

    opt->src.enc.name = opt->ext.enc.name = opt->intern.enc.name = 0;

    const int hyphen = *s != '-';
    argstr = rb_str_tmp_new((len = strlen(s)) + hyphen);
    argary = rb_str_tmp_new(0);

    p = RSTRING_PTR(argstr);
    if (hyphen) *p = '-';
    memcpy(p + hyphen, s, len + 1);
    ap = 0;
    rb_str_cat(argary, (char *)&ap, sizeof(ap));
    while (*p) {
        ap = p;
        rb_str_cat(argary, (char *)&ap, sizeof(ap));
        while (*p && !ISSPACE(*p)) ++p;
        if (!*p) break;
        *p++ = '\0';
        while (ISSPACE(*p)) ++p;
    }
    argc = RSTRING_LEN(argary) / sizeof(ap);
    ap = 0;
    rb_str_cat(argary, (char *)&ap, sizeof(ap));
    argv = ptr = ALLOC_N(char *, argc);
    MEMMOVE(argv, RSTRING_PTR(argary), char *, argc);

    while ((i = proc_options(argc, argv, opt, envopt)) > 1 && envopt && (argc -= i) > 0) {
        argv += i;
        if (**argv != '-') {
            *--*argv = '-';
        }
        if ((*argv)[1]) {
            ++argc;
            --argv;
        }
    }

    if (src_enc_name) {
        opt->src.enc.name = src_enc_name;
    }
    if (ext_enc_name) {
        opt->ext.enc.name = ext_enc_name;
    }
    if (int_enc_name) {
        opt->intern.enc.name = int_enc_name;
    }
    FEATURE_SET_RESTORE(opt->features, feat);
    FEATURE_SET_RESTORE(opt->warn, warn);
    if (BACKTRACE_LENGTH_LIMIT_VALID_P(backtrace_length_limit)) {
        opt->backtrace_length_limit = backtrace_length_limit;
    }
    if (crash_report) {
        opt->crash_report = crash_report;
    }

    ruby_xfree(ptr);
    /* get rid of GC */
    rb_str_resize(argary, 0);
    rb_str_resize(argstr, 0);
}

static int
name_match_p(const char *name, const char *str, size_t len)
{
    if (len == 0) return 0;
    while (1) {
        while (TOLOWER(*str) == *name) {
            if (!--len) return 1;
            ++name;
            ++str;
        }
        if (*str != '-' && *str != '_') return 0;
        while (ISALNUM(*name)) name++;
        if (*name != '-' && *name != '_') return 0;
        if (!*++name) return 1;
        ++str;
        if (--len == 0) return 1;
    }
}

#define NAME_MATCH_P(name, str, len) \
    ((len) < (int)sizeof(name) && name_match_p((name), (str), (len)))

#define UNSET_WHEN(name, bit, str, len)	\
    if (NAME_MATCH_P((name), (str), (len))) { \
        *(unsigned int *)arg &= ~(bit); \
        return;				\
    }

#define SET_WHEN(name, bit, str, len)	\
    if (NAME_MATCH_P((name), (str), (len))) { \
        *(unsigned int *)arg |= (bit);	\
        return;				\
    }

#define LITERAL_NAME_ELEMENT(name) #name

static void
feature_option(const char *str, int len, void *arg, const unsigned int enable)
{
    static const char list[] = EACH_FEATURES(LITERAL_NAME_ELEMENT, ", ");
    ruby_features_t *argp = arg;
    unsigned int mask = ~0U;
    unsigned int set = 0U;
#if AMBIGUOUS_FEATURE_NAMES
    int matched = 0;
# define FEATURE_FOUND ++matched
#else
# define FEATURE_FOUND goto found
#endif
#define SET_FEATURE(bit) \
    if (NAME_MATCH_P(#bit, str, len)) {set |= mask = FEATURE_BIT(bit); FEATURE_FOUND;}
    EACH_FEATURES(SET_FEATURE, ;);
    if (NAME_MATCH_P("jit", str, len)) { // This allows you to cancel --jit
        set |= mask = FEATURE_BIT(jit);
        goto found;
    }
    if (NAME_MATCH_P("all", str, len)) {
        // YJIT and RJIT cannot be enabled at the same time. We enable only one for --enable=all.
        mask &= ~feature_jit_mask | FEATURE_BIT(jit);
        goto found;
    }
#if AMBIGUOUS_FEATURE_NAMES
    if (matched == 1) goto found;
    if (matched > 1) {
        VALUE mesg = rb_sprintf("ambiguous feature: '%.*s' (", len, str);
#define ADD_FEATURE_NAME(bit) \
        if (FEATURE_BIT(bit) & set) { \
            rb_str_cat_cstr(mesg, #bit); \
            if (--matched) rb_str_cat_cstr(mesg, ", "); \
        }
        EACH_FEATURES(ADD_FEATURE_NAME, ;);
        rb_str_cat_cstr(mesg, ")");
        rb_exc_raise(rb_exc_new_str(rb_eRuntimeError, mesg));
#undef ADD_FEATURE_NAME
    }
#else
    (void)set;
#endif
    rb_warn("unknown argument for --%s: '%.*s'",
            enable ? "enable" : "disable", len, str);
    rb_warn("features are [%.*s].", (int)strlen(list), list);
    return;

  found:
    FEATURE_SET_TO(*argp, mask, (mask & enable));
    return;
}

static void
enable_option(const char *str, int len, void *arg)
{
    feature_option(str, len, arg, ~0U);
}

static void
disable_option(const char *str, int len, void *arg)
{
    feature_option(str, len, arg, 0U);
}

RUBY_EXTERN const int  ruby_patchlevel;
int ruby_env_debug_option(const char *str, int len, void *arg);

static void
debug_option(const char *str, int len, void *arg)
{
    static const char list[] = EACH_DEBUG_FEATURES(LITERAL_NAME_ELEMENT, ", ");
    ruby_features_t *argp = arg;
#define SET_WHEN_DEBUG(bit) \
    if (NAME_MATCH_P(#bit, str, len)) { \
        FEATURE_SET(*argp, DEBUG_BIT(bit)); \
        return; \
    }
    EACH_DEBUG_FEATURES(SET_WHEN_DEBUG, ;);
#ifdef RUBY_DEVEL
    if (ruby_patchlevel < 0 && ruby_env_debug_option(str, len, 0)) return;
#endif
    rb_warn("unknown argument for --debug: '%.*s'", len, str);
    rb_warn("debug features are [%.*s].", (int)strlen(list), list);
}

static int
memtermspn(const char *str, char term, int len)
{
    RUBY_ASSERT(len >= 0);
    if (len <= 0) return 0;
    const char *next = memchr(str, term, len);
    return next ? (int)(next - str) : len;
}

static const char additional_opt_sep = '+';

static unsigned int
dump_additional_option_flag(const char *str, int len, unsigned int bits, bool set)
{
#define SET_DUMP_OPT(bit) if (NAME_MATCH_P(#bit, str, len)) { \
        return set ? (bits | DUMP_BIT(opt_ ## bit)) : (bits & ~DUMP_BIT(opt_ ## bit)); \
    }
    SET_DUMP_OPT(error_tolerant);
    SET_DUMP_OPT(comment);
    SET_DUMP_OPT(optimize);
#undef SET_DUMP_OPT
    rb_warn("don't know how to dump with%s '%.*s'", set ? "" : "out", len, str);
    return bits;
}

static unsigned int
dump_additional_option(const char *str, int len, unsigned int bits)
{
    int w;
    for (; len-- > 0 && *str++ == additional_opt_sep; len -= w, str += w) {
        w = memtermspn(str, additional_opt_sep, len);
        bool set = true;
        if (*str == '-' || *str == '+') {
            set = *str++ == '+';
            --w;
        }
        else {
            int n = memtermspn(str, '-', w);
            if (str[n] == '-') {
                if (NAME_MATCH_P("with", str, n)) {
                    str += n;
                    w -= n;
                }
                else if (NAME_MATCH_P("without", str, n)) {
                    set = false;
                    str += n;
                    w -= n;
                }
            }
        }
        bits = dump_additional_option_flag(str, w, bits, set);
    }
    return bits;
}

static void
dump_option(const char *str, int len, void *arg)
{
    static const char list[] = EACH_DUMPS(LITERAL_NAME_ELEMENT, ", ");
    unsigned int *bits_ptr = (unsigned int *)arg;
    if (*str == '+' || *str == '-') {
        bool set = *str++ == '+';
        *bits_ptr = dump_additional_option_flag(str, --len, *bits_ptr, set);
        return;
    }
    int w = memtermspn(str, additional_opt_sep, len);

#define SET_WHEN_DUMP(bit) \
    if (NAME_MATCH_P(#bit "-", (str), (w))) { \
        *bits_ptr = dump_additional_option(str + w, len - w, *bits_ptr | DUMP_BIT(bit)); \
        return; \
    }
    EACH_DUMPS(SET_WHEN_DUMP, ;);
    rb_warn("don't know how to dump '%.*s',", len, str);
    rb_warn("but only [%.*s].", (int)strlen(list), list);
}

static void
set_option_encoding_once(const char *type, VALUE *name, const char *e, long elen)
{
    VALUE ename;

    if (!elen) elen = strlen(e);
    ename = rb_str_new(e, elen);

    if (*name &&
        rb_funcall(ename, rb_intern("casecmp"), 1, *name) != INT2FIX(0)) {
        rb_raise(rb_eRuntimeError,
                 "%s already set to %"PRIsVALUE, type, *name);
    }
    *name = ename;
}

#define set_internal_encoding_once(opt, e, elen) \
    set_option_encoding_once("default_internal", &(opt)->intern.enc.name, (e), (elen))
#define set_external_encoding_once(opt, e, elen) \
    set_option_encoding_once("default_external", &(opt)->ext.enc.name, (e), (elen))
#define set_source_encoding_once(opt, e, elen) \
    set_option_encoding_once("source", &(opt)->src.enc.name, (e), (elen))

#define yjit_opt_match_noarg(s, l, name) \
    opt_match(s, l, name) && (*(s) ? (rb_warn("argument to --yjit-" name " is ignored"), 1) : 1)
#define yjit_opt_match_arg(s, l, name) \
    opt_match(s, l, name) && (*(s) && *(s+1) ? 1 : (rb_raise(rb_eRuntimeError, "--yjit-" name " needs an argument"), 0))

#if USE_YJIT
static bool
setup_yjit_options(const char *s)
{
    // The option parsing is done in yjit/src/options.rs
    bool rb_yjit_parse_option(const char* s);
    bool success = rb_yjit_parse_option(s);

    if (success) {
        return true;
    }

    rb_raise(
        rb_eRuntimeError,
        "invalid YJIT option '%s' (--help will show valid yjit options)",
        s
    );
}
#endif

/*
 * Following proc_*_option functions are tree kinds:
 *
 * - with a required argument, takes also `argc` and `argv`, and
 *   returns the number of consumed argv including the option itself.
 *
 * - with a mandatory argument just after the option.
 *
 * - no required argument, this returns the address of
 *   the next character after the last consumed character.
 */

/* optional */
static const char *
proc_W_option(ruby_cmdline_options_t *opt, const char *s, int *warning)
{
    if (s[1] == ':') {
        unsigned int bits = 0;
        static const char no_prefix[] = "no-";
        int enable = strncmp(s += 2, no_prefix, sizeof(no_prefix)-1) != 0;
        if (!enable) s += sizeof(no_prefix)-1;
        size_t len = strlen(s);
        if (NAME_MATCH_P("deprecated", s, len)) {
            bits = 1U << RB_WARN_CATEGORY_DEPRECATED;
        }
        else if (NAME_MATCH_P("experimental", s, len)) {
            bits = 1U << RB_WARN_CATEGORY_EXPERIMENTAL;
        }
        else if (NAME_MATCH_P("performance", s, len)) {
            bits = 1U << RB_WARN_CATEGORY_PERFORMANCE;
        }
        else {
            rb_warn("unknown warning category: '%s'", s);
        }
        if (bits) FEATURE_SET_TO(opt->warn, bits, enable ? bits : 0);
        return 0;
    }
    else {
        size_t numlen;
        int v = 2;	/* -W as -W2 */

        if (*++s) {
            v = scan_oct(s, 1, &numlen);
            if (numlen == 0)
                v = 2;
            s += numlen;
        }
        if (!opt->warning) {
            switch (v) {
              case 0:
                ruby_verbose = Qnil;
                break;
              case 1:
                ruby_verbose = Qfalse;
                break;
              default:
                ruby_verbose = Qtrue;
                break;
            }
        }
        *warning = 1;
        switch (v) {
          case 0:
            FEATURE_SET_TO(opt->warn, RB_WARN_CATEGORY_DEFAULT_BITS, 0);
            break;
          case 1:
            FEATURE_SET_TO(opt->warn, 1U << RB_WARN_CATEGORY_DEPRECATED, 0);
            break;
          default:
            FEATURE_SET(opt->warn, RB_WARN_CATEGORY_DEFAULT_BITS);
            break;
        }
        return s;
    }
}

/* required */
static long
proc_e_option(ruby_cmdline_options_t *opt, const char *s, long argc, char **argv)
{
    long n = 1;
    forbid_setid("-e");
    if (!*++s) {
        if (!--argc)
            rb_raise(rb_eRuntimeError, "no code specified for -e");
        s = *++argv;
        n++;
    }
    if (!opt->e_script) {
        opt->e_script = rb_str_new(0, 0);
        if (opt->script == 0)
            opt->script = "-e";
    }
    rb_str_cat2(opt->e_script, s);
    rb_str_cat2(opt->e_script, "\n");
    return n;
}

/* optional */
static const char *
proc_K_option(ruby_cmdline_options_t *opt, const char *s)
{
    if (*++s) {
        const char *enc_name = 0;
        switch (*s) {
          case 'E': case 'e':
            enc_name = "EUC-JP";
            break;
          case 'S': case 's':
            enc_name = "Windows-31J";
            break;
          case 'U': case 'u':
            enc_name = "UTF-8";
            break;
          case 'N': case 'n': case 'A': case 'a':
            enc_name = "ASCII-8BIT";
            break;
        }
        if (enc_name) {
            opt->src.enc.name = rb_str_new2(enc_name);
            if (!opt->ext.enc.name)
                opt->ext.enc.name = opt->src.enc.name;
        }
        s++;
    }
    return s;
}

/* optional */
static const char *
proc_0_option(ruby_cmdline_options_t *opt, const char *s)
{
    size_t numlen;
    int v;
    char c;

    v = scan_oct(s, 4, &numlen);
    s += numlen;
    if (v > 0377)
        rb_rs = Qnil;
    else if (v == 0 && numlen >= 2) {
        rb_rs = rb_str_new2("");
    }
    else {
        c = v & 0xff;
        rb_rs = rb_str_new(&c, 1);
    }
    return s;
}

/* mandatory */
static void
proc_encoding_option(ruby_cmdline_options_t *opt, const char *s, const char *opt_name)
{
    char *p;
# define set_encoding_part(type) \
    if (!(p = strchr(s, ':'))) {                        \
        set_##type##_encoding_once(opt, s, 0);          \
        return;                                         \
    }                                                   \
    else if (p > s) {                                   \
        set_##type##_encoding_once(opt, s, p-s);        \
    }
    set_encoding_part(external);
    if (!*(s = ++p)) return;
    set_encoding_part(internal);
    if (!*(s = ++p)) return;
#if defined ALLOW_DEFAULT_SOURCE_ENCODING && ALLOW_DEFAULT_SOURCE_ENCODING
    set_encoding_part(source);
    if (!*(s = ++p)) return;
#endif
    rb_raise(rb_eRuntimeError, "extra argument for %s: %s", opt_name, s);
# undef set_encoding_part
    UNREACHABLE;
}

static long
proc_long_options(ruby_cmdline_options_t *opt, const char *s, long argc, char **argv, int envopt)
{
    size_t n;
    long argc0 = argc;
# define is_option_end(c, allow_hyphen)                         \
    (!(c) || ((allow_hyphen) && (c) == '-') || (c) == '=')
# define check_envopt(name, allow_envopt)                               \
    (((allow_envopt) || !envopt) ? (void)0 :                            \
     rb_raise(rb_eRuntimeError, "invalid switch in RUBYOPT: --" name))
# define need_argument(name, s, needs_arg, next_arg)                    \
    ((*(s) ? !*++(s) : (next_arg) && (argc <= 1 || !((s) = argv[1]) || (--argc, ++argv, 0))) && (needs_arg) ? \
     rb_raise(rb_eRuntimeError, "missing argument for --" name)         \
     : (void)0)
# define is_option_with_arg(name, allow_hyphen, allow_envopt)           \
    is_option_with_optarg(name, allow_hyphen, allow_envopt, Qtrue, Qtrue)
# define is_option_with_optarg(name, allow_hyphen, allow_envopt, needs_arg, next_arg) \
    (strncmp((name), s, n = sizeof(name) - 1) == 0 && is_option_end(s[n], (allow_hyphen)) && \
     (s[n] != '-' || (s[n] && s[n+1])) ?                                \
     (check_envopt(name, (allow_envopt)), s += n,                       \
      need_argument(name, s, needs_arg, next_arg), 1) : 0)

    if (strcmp("copyright", s) == 0) {
        if (envopt) goto noenvopt_long;
        opt->dump |= DUMP_BIT(copyright);
    }
    else if (is_option_with_optarg("debug", Qtrue, Qtrue, Qfalse, Qfalse)) {
        if (s && *s) {
            ruby_each_words(s, debug_option, &opt->features);
        }
        else {
            ruby_debug = Qtrue;
            ruby_verbose = Qtrue;
        }
    }
    else if (is_option_with_arg("enable", Qtrue, Qtrue)) {
        ruby_each_words(s, enable_option, &opt->features);
    }
    else if (is_option_with_arg("disable", Qtrue, Qtrue)) {
        ruby_each_words(s, disable_option, &opt->features);
    }
    else if (is_option_with_arg("encoding", Qfalse, Qtrue)) {
        proc_encoding_option(opt, s, "--encoding");
    }
    else if (is_option_with_arg("internal-encoding", Qfalse, Qtrue)) {
        set_internal_encoding_once(opt, s, 0);
    }
    else if (is_option_with_arg("external-encoding", Qfalse, Qtrue)) {
        set_external_encoding_once(opt, s, 0);
    }
    else if (is_option_with_arg("parser", Qfalse, Qtrue)) {
        if (strcmp("prism", s) == 0) {
            (*rb_ruby_prism_ptr()) = true;
        }
        else if (strcmp("parse.y", s) == 0) {
            // default behavior
        }
        else {
            rb_raise(rb_eRuntimeError, "unknown parser %s", s);
        }
    }
#if defined ALLOW_DEFAULT_SOURCE_ENCODING && ALLOW_DEFAULT_SOURCE_ENCODING
    else if (is_option_with_arg("source-encoding", Qfalse, Qtrue)) {
        set_source_encoding_once(opt, s, 0);
    }
#endif
    else if (strcmp("version", s) == 0) {
        if (envopt) goto noenvopt_long;
        opt->dump |= DUMP_BIT(version);
    }
    else if (strcmp("verbose", s) == 0) {
        opt->verbose = 1;
        ruby_verbose = Qtrue;
    }
    else if (strcmp("jit", s) == 0) {
#if USE_YJIT || USE_RJIT
        FEATURE_SET(opt->features, FEATURE_BIT(jit));
#else
        rb_warn("Ruby was built without JIT support");
#endif
    }
    else if (is_option_with_optarg("rjit", '-', true, false, false)) {
#if USE_RJIT
        extern void rb_rjit_setup_options(const char *s, struct rb_rjit_options *rjit_opt);
        FEATURE_SET(opt->features, FEATURE_BIT(rjit));
        rb_rjit_setup_options(s, &opt->rjit);
#else
        rb_warn("RJIT support is disabled.");
#endif
    }
    else if (is_option_with_optarg("yjit", '-', true, false, false)) {
#if USE_YJIT
        FEATURE_SET(opt->features, FEATURE_BIT(yjit));
        setup_yjit_options(s);
#else
        rb_warn("Ruby was built without YJIT support."
                " You may need to install rustc to build Ruby with YJIT.");
#endif
    }
    else if (strcmp("yydebug", s) == 0) {
        if (envopt) goto noenvopt_long;
        opt->dump |= DUMP_BIT(yydebug);
    }
    else if (is_option_with_arg("dump", Qfalse, Qfalse)) {
        ruby_each_words(s, dump_option, &opt->dump);
    }
    else if (strcmp("help", s) == 0) {
        if (envopt) goto noenvopt_long;
        opt->dump |= DUMP_BIT(help);
        return 0;
    }
    else if (is_option_with_arg("backtrace-limit", Qfalse, Qtrue)) {
        char *e;
        long n = strtol(s, &e, 10);
        if (errno == ERANGE || !BACKTRACE_LENGTH_LIMIT_VALID_P(n) || *e) {
            rb_raise(rb_eRuntimeError, "wrong limit for backtrace length");
        }
        else {
            opt->backtrace_length_limit = n;
        }
    }
    else if (is_option_with_arg("crash-report", true, true)) {
        opt->crash_report = s;
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid option --%s  (-h will show valid options)", s);
    }
    return argc0 - argc + 1;

  noenvopt_long:
    rb_raise(rb_eRuntimeError, "invalid switch in RUBYOPT: --%s", s);
# undef is_option_end
# undef check_envopt
# undef need_argument
# undef is_option_with_arg
# undef is_option_with_optarg
    UNREACHABLE_RETURN(0);
}

static long
proc_options(long argc, char **argv, ruby_cmdline_options_t *opt, int envopt)
{
    long n, argc0 = argc;
    const char *s;
    int warning = opt->warning;

    if (argc <= 0 || !argv)
        return 0;

    for (argc--, argv++; argc > 0; argc--, argv++) {
        const char *const arg = argv[0];
        if (!arg || arg[0] != '-' || !arg[1])
            break;

        s = arg + 1;
      reswitch:
        switch (*s) {
          case 'a':
            if (envopt) goto noenvopt;
            opt->do_split = TRUE;
            s++;
            goto reswitch;

          case 'p':
            if (envopt) goto noenvopt;
            opt->do_print = TRUE;
            /* through */
          case 'n':
            if (envopt) goto noenvopt;
            opt->do_loop = TRUE;
            s++;
            goto reswitch;

          case 'd':
            ruby_debug = Qtrue;
            ruby_verbose = Qtrue;
            s++;
            goto reswitch;

          case 'y':
            if (envopt) goto noenvopt;
            opt->dump |= DUMP_BIT(yydebug);
            s++;
            goto reswitch;

          case 'v':
            if (opt->verbose) {
                s++;
                goto reswitch;
            }
            opt->dump |= DUMP_BIT(version_v);
            opt->verbose = 1;
          case 'w':
            if (!opt->warning) {
                warning = 1;
                ruby_verbose = Qtrue;
            }
            FEATURE_SET(opt->warn, RB_WARN_CATEGORY_DEFAULT_BITS);
            s++;
            goto reswitch;

          case 'W':
            if (!(s = proc_W_option(opt, s, &warning))) break;
            goto reswitch;

          case 'c':
            if (envopt) goto noenvopt;
            opt->dump |= DUMP_BIT(syntax);
            s++;
            goto reswitch;

          case 's':
            if (envopt) goto noenvopt;
            forbid_setid("-s");
            if (!opt->sflag) opt->sflag = 1;
            s++;
            goto reswitch;

          case 'h':
            if (envopt) goto noenvopt;
            opt->dump |= DUMP_BIT(usage);
            goto switch_end;

          case 'l':
            if (envopt) goto noenvopt;
            opt->do_line = TRUE;
            rb_output_rs = rb_rs;
            s++;
            goto reswitch;

          case 'S':
            if (envopt) goto noenvopt;
            forbid_setid("-S");
            opt->do_search = TRUE;
            s++;
            goto reswitch;

          case 'e':
            if (envopt) goto noenvopt;
            if (!(n = proc_e_option(opt, s, argc, argv))) break;
            --n;
            argc -= n;
            argv += n;
            break;

          case 'r':
            forbid_setid("-r");
            if (*++s) {
                add_modules(&opt->req_list, s);
            }
            else if (argc > 1) {
                add_modules(&opt->req_list, argv[1]);
                argc--, argv++;
            }
            break;

          case 'i':
            if (envopt) goto noenvopt;
            forbid_setid("-i");
            ruby_set_inplace_mode(s + 1);
            break;

          case 'x':
            if (envopt) goto noenvopt;
            forbid_setid("-x");
            opt->xflag = TRUE;
            s++;
            if (*s && chdir(s) < 0) {
                rb_fatal("Can't chdir to %s", s);
            }
            break;

          case 'C':
          case 'X':
            if (envopt) goto noenvopt;
            if (!*++s && (!--argc || !(s = *++argv) || !*s)) {
                rb_fatal("Can't chdir");
            }
            if (chdir(s) < 0) {
                rb_fatal("Can't chdir to %s", s);
            }
            break;

          case 'F':
            if (envopt) goto noenvopt;
            if (*++s) {
                rb_fs = rb_reg_new(s, strlen(s), 0);
            }
            break;

          case 'E':
            if (!*++s && (!--argc || !(s = *++argv))) {
                rb_raise(rb_eRuntimeError, "missing argument for -E");
            }
            proc_encoding_option(opt, s, "-E");
            break;

          case 'U':
            set_internal_encoding_once(opt, "UTF-8", 0);
            ++s;
            goto reswitch;

          case 'K':
            if (!(s = proc_K_option(opt, s))) break;
            goto reswitch;

          case 'I':
            forbid_setid("-I");
            if (*++s)
                ruby_incpush_expand(s);
            else if (argc > 1) {
                ruby_incpush_expand(argv[1]);
                argc--, argv++;
            }
            break;

          case '0':
            if (envopt) goto noenvopt;
            if (!(s = proc_0_option(opt, s))) break;
            goto reswitch;

          case '-':
            if (!s[1] || (s[1] == '\r' && !s[2])) {
                argc--, argv++;
                goto switch_end;
            }
            s++;

            if (!(n = proc_long_options(opt, s, argc, argv, envopt))) goto switch_end;
            --n;
            argc -= n;
            argv += n;
            break;

          case '\r':
            if (!s[1])
                break;

          default:
            rb_raise(rb_eRuntimeError,
                     "invalid option -%c  (-h will show valid options)",
                     (int)(unsigned char)*s);
            goto switch_end;

          noenvopt:
            /* "EIdvwWrKU" only */
            rb_raise(rb_eRuntimeError, "invalid switch in RUBYOPT: -%c", *s);
            break;

          case 0:
            break;
        }
    }

  switch_end:
    if (warning) opt->warning = warning;
    return argc0 - argc;
}

void Init_builtin_features(void);

static void
ruby_init_prelude(void)
{
    Init_builtin_features();
    rb_const_remove(rb_cObject, rb_intern_const("TMP_RUBY_PREFIX"));
}

void rb_call_builtin_inits(void);

// Initialize extra optional exts linked statically.
// This empty definition will be replaced with the actual strong symbol by linker.
#if RBIMPL_HAS_ATTRIBUTE(weak)
__attribute__((weak))
#endif
void
Init_extra_exts(void)
{
}

static void
ruby_opt_init(ruby_cmdline_options_t *opt)
{
    rb_warning_category_update(opt->warn.mask, opt->warn.set);

    if (opt->dump & dump_exit_bits) return;

    if (FEATURE_SET_P(opt->features, gems)) {
        rb_define_module("Gem");
        if (opt->features.set & FEATURE_BIT(error_highlight)) {
            rb_define_module("ErrorHighlight");
        }
        if (opt->features.set & FEATURE_BIT(did_you_mean)) {
            rb_define_module("DidYouMean");
        }
        if (opt->features.set & FEATURE_BIT(syntax_suggest)) {
            rb_define_module("SyntaxSuggest");
        }
    }

    /* [Feature #19785] Warning for removed GC environment variable.
     * Remove this in Ruby 3.4. */
    if (getenv("RUBY_GC_HEAP_INIT_SLOTS")) {
        rb_warn_deprecated("The environment variable RUBY_GC_HEAP_INIT_SLOTS",
                           "environment variables RUBY_GC_HEAP_%d_INIT_SLOTS");
    }

    if (getenv("RUBY_FREE_AT_EXIT")) {
        rb_warn("Free at exit is experimental and may be unstable");
        rb_free_at_exit = true;
    }

#if USE_RJIT
    // rb_call_builtin_inits depends on RubyVM::RJIT.enabled?
    if (opt->rjit.on)
        rb_rjit_enabled = true;
    if (opt->rjit.stats)
        rb_rjit_stats_enabled = true;
    if (opt->rjit.trace_exits)
        rb_rjit_trace_exits_enabled = true;
#endif

    Init_ext(); /* load statically linked extensions before rubygems */
    Init_extra_exts();

    GET_VM()->running = 0;
    rb_call_builtin_inits();
    GET_VM()->running = 1;
    memset(ruby_vm_redefined_flag, 0, sizeof(ruby_vm_redefined_flag));

    ruby_init_prelude();

    // Initialize JITs after prelude because JITing prelude is typically not optimal.
#if USE_RJIT
    // Also, rb_rjit_init is safe only after rb_call_builtin_inits() defines RubyVM::RJIT::Compiler.
    if (opt->rjit.on)
        rb_rjit_init(&opt->rjit);
#endif
#if USE_YJIT
    rb_yjit_init(opt->yjit);
#endif

    ruby_set_script_name(opt->script_name);
    require_libraries(&opt->req_list);
}

static int
opt_enc_index(VALUE enc_name)
{
    const char *s = RSTRING_PTR(enc_name);
    int i = rb_enc_find_index(s);

    if (i < 0) {
        rb_raise(rb_eRuntimeError, "unknown encoding name - %s", s);
    }
    else if (rb_enc_dummy_p(rb_enc_from_index(i))) {
        rb_raise(rb_eRuntimeError, "dummy encoding is not acceptable - %s ", s);
    }
    return i;
}

#define rb_progname      (GET_VM()->progname)
#define rb_orig_progname (GET_VM()->orig_progname)
VALUE rb_argv0;
VALUE rb_e_script;

static VALUE
false_value(ID _x, VALUE *_y)
{
    return Qfalse;
}

static VALUE
true_value(ID _x, VALUE *_y)
{
    return Qtrue;
}

#define rb_define_readonly_boolean(name, val) \
    rb_define_virtual_variable((name), (val) ? true_value : false_value, 0)

static VALUE
uscore_get(void)
{
    VALUE line;

    line = rb_lastline_get();
    if (!RB_TYPE_P(line, T_STRING)) {
        rb_raise(rb_eTypeError, "$_ value need to be String (%s given)",
                 NIL_P(line) ? "nil" : rb_obj_classname(line));
    }
    return line;
}

/*
 *  call-seq:
 *     sub(pattern, replacement)   -> $_
 *     sub(pattern) {|...| block } -> $_
 *
 *  Equivalent to <code>$_.sub(<i>args</i>)</code>, except that
 *  <code>$_</code> will be updated if substitution occurs.
 *  Available only when -p/-n command line option specified.
 */

static VALUE
rb_f_sub(int argc, VALUE *argv, VALUE _)
{
    VALUE str = rb_funcall_passing_block(uscore_get(), rb_intern("sub"), argc, argv);
    rb_lastline_set(str);
    return str;
}

/*
 *  call-seq:
 *     gsub(pattern, replacement)    -> $_
 *     gsub(pattern) {|...| block }  -> $_
 *
 *  Equivalent to <code>$_.gsub...</code>, except that <code>$_</code>
 *  will be updated if substitution occurs.
 *  Available only when -p/-n command line option specified.
 *
 */

static VALUE
rb_f_gsub(int argc, VALUE *argv, VALUE _)
{
    VALUE str = rb_funcall_passing_block(uscore_get(), rb_intern("gsub"), argc, argv);
    rb_lastline_set(str);
    return str;
}

/*
 *  call-seq:
 *     chop   -> $_
 *
 *  Equivalent to <code>($_.dup).chop!</code>, except <code>nil</code>
 *  is never returned. See String#chop!.
 *  Available only when -p/-n command line option specified.
 *
 */

static VALUE
rb_f_chop(VALUE _)
{
    VALUE str = rb_funcall_passing_block(uscore_get(), rb_intern("chop"), 0, 0);
    rb_lastline_set(str);
    return str;
}


/*
 *  call-seq:
 *     chomp            -> $_
 *     chomp(string)    -> $_
 *
 *  Equivalent to <code>$_ = $_.chomp(<em>string</em>)</code>. See
 *  String#chomp.
 *  Available only when -p/-n command line option specified.
 *
 */

static VALUE
rb_f_chomp(int argc, VALUE *argv, VALUE _)
{
    VALUE str = rb_funcall_passing_block(uscore_get(), rb_intern("chomp"), argc, argv);
    rb_lastline_set(str);
    return str;
}

static void
setup_pager_env(void)
{
    if (!getenv("LESS")) {
        // Output "raw" control characters, and move per sections.
        ruby_setenv("LESS", "-R +/^[A-Z].*");
    }
}

#ifdef _WIN32
static int
tty_enabled(void)
{
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD m;
    if (!GetConsoleMode(h, &m)) return 0;
# ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#   define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x4
# endif
    if (!(m & ENABLE_VIRTUAL_TERMINAL_PROCESSING)) return 0;
    return 1;
}
#elif !defined(HAVE_WORKING_FORK)
# define tty_enabled() 0
#endif

static VALUE
copy_str(VALUE str, rb_encoding *enc, bool intern)
{
    if (!intern) {
        if (rb_enc_str_coderange_scan(str, enc) == ENC_CODERANGE_BROKEN)
            return 0;
        return rb_enc_associate(rb_str_dup(str), enc);
    }
    return rb_enc_interned_str(RSTRING_PTR(str), RSTRING_LEN(str), enc);
}

#if USE_YJIT
// Check that an environment variable is set to a truthy value
static bool
env_var_truthy(const char *name)
{
    const char *value = getenv(name);

    if (!value)
        return false;
    if (strcmp(value, "1") == 0)
        return true;
    if (strcmp(value, "true") == 0)
        return true;
    if (strcmp(value, "yes") == 0)
        return true;

    return false;
}
#endif

rb_pid_t rb_fork_ruby(int *status);

static void
show_help(const char *progname, int help)
{
    int tty = isatty(1);
    int columns = 0;
    if (help && tty) {
        const char *pager_env = getenv("RUBY_PAGER");
        if (!pager_env) pager_env = getenv("PAGER");
        if (pager_env && *pager_env && isatty(0)) {
            const char *columns_env = getenv("COLUMNS");
            if (columns_env) columns = atoi(columns_env);
            VALUE pager = rb_str_new_cstr(pager_env);
#ifdef HAVE_WORKING_FORK
            int fds[2];
            if (rb_pipe(fds) == 0) {
                rb_pid_t pid = rb_fork_ruby(NULL);
                if (pid > 0) {
                    /* exec PAGER with reading from child */
                    dup2(fds[0], 0);
                }
                else if (pid == 0) {
                    /* send the help message to the parent PAGER */
                    dup2(fds[1], 1);
                    dup2(fds[1], 2);
                }
                close(fds[0]);
                close(fds[1]);
                if (pid > 0) {
                    setup_pager_env();
                    rb_f_exec(1, &pager);
                    kill(SIGTERM, pid);
                    rb_waitpid(pid, 0, 0);
                }
            }
#else
            setup_pager_env();
            VALUE port = rb_io_popen(pager, rb_str_new_lit("w"), Qnil, Qnil);
            if (!NIL_P(port)) {
                int oldout = dup(1);
                int olderr = dup(2);
                int fd = RFILE(port)->fptr->fd;
                tty = tty_enabled();
                dup2(fd, 1);
                dup2(fd, 2);
                usage(progname, 1, tty, columns);
                fflush(stdout);
                dup2(oldout, 1);
                dup2(olderr, 2);
                rb_io_close(port);
                return;
            }
#endif
        }
    }
    usage(progname, help, tty, columns);
}

static rb_ast_t *
process_script(ruby_cmdline_options_t *opt)
{
    rb_ast_t *ast;
    VALUE parser = rb_parser_new();
    const unsigned int dump = opt->dump;

    if (dump & DUMP_BIT(yydebug)) {
        rb_parser_set_yydebug(parser, Qtrue);
    }

    if ((dump & dump_exit_bits) && (dump & DUMP_BIT(opt_error_tolerant))) {
        rb_parser_error_tolerant(parser);
    }

    if (opt->e_script) {
        VALUE progname = rb_progname;
        rb_parser_set_context(parser, 0, TRUE);

        ruby_opt_init(opt);
        ruby_set_script_name(progname);
        rb_parser_set_options(parser, opt->do_print, opt->do_loop,
                              opt->do_line, opt->do_split);
        ast = rb_parser_compile_string(parser, opt->script, opt->e_script, 1);
    }
    else {
        VALUE f;
        int xflag = opt->xflag;
        f = open_load_file(opt->script_name, &xflag);
        opt->xflag = xflag != 0;
        rb_parser_set_context(parser, 0, f == rb_stdin);
        ast = load_file(parser, opt->script_name, f, 1, opt);
    }
    if (!ast->body.root) {
        rb_ast_dispose(ast);
        return NULL;
    }
    return ast;
}

/**
 * Call ruby_opt_init to set up the global state based on the command line
 * options, and then warn if prism is enabled and the experimental warning
 * category is enabled.
 */
static void
prism_opt_init(ruby_cmdline_options_t *opt)
{
    ruby_opt_init(opt);

    if (rb_warning_category_enabled_p(RB_WARN_CATEGORY_EXPERIMENTAL)) {
        rb_category_warn(
            RB_WARN_CATEGORY_EXPERIMENTAL,
            "The compiler based on the Prism parser is currently experimental "
            "and compatibility with the compiler based on parse.y is not yet "
            "complete. Please report any issues you find on the `ruby/prism` "
            "issue tracker."
        );
    }
}

/**
 * Process the command line options and parse the script into the given result.
 * Raise an error if the script cannot be parsed.
 */
static void
prism_script(ruby_cmdline_options_t *opt, pm_parse_result_t *result)
{
    memset(result, 0, sizeof(pm_parse_result_t));

    pm_options_t *options = &result->options;
    pm_options_line_set(options, 1);

    if (opt->ext.enc.name != 0) {
        pm_options_encoding_set(options, StringValueCStr(opt->ext.enc.name));
    }

    uint8_t command_line = 0;
    if (opt->do_split) command_line |= PM_OPTIONS_COMMAND_LINE_A;
    if (opt->do_line) command_line |= PM_OPTIONS_COMMAND_LINE_L;
    if (opt->do_loop) command_line |= PM_OPTIONS_COMMAND_LINE_N;
    if (opt->do_print) command_line |= PM_OPTIONS_COMMAND_LINE_P;
    if (opt->xflag) command_line |= PM_OPTIONS_COMMAND_LINE_X;

    VALUE error;
    if (strcmp(opt->script, "-") == 0) {
        pm_options_command_line_set(options, command_line);
        pm_options_filepath_set(options, "-");

        prism_opt_init(opt);
        error = pm_parse_stdin(result);
    }
    else if (opt->e_script) {
        command_line |= PM_OPTIONS_COMMAND_LINE_E;
        pm_options_command_line_set(options, command_line);

        prism_opt_init(opt);
        error = pm_parse_string(result, opt->e_script, rb_str_new2("-e"));
    }
    else {
        pm_options_command_line_set(options, command_line);
        error = pm_load_file(result, opt->script_name, true);

        // If reading the file did not error, at that point we load the command
        // line options. We do it in this order so that if the main script fails
        // to load, it doesn't require files required by -r.
        if (NIL_P(error)) {
            prism_opt_init(opt);
            error = pm_parse_file(result, opt->script_name);
        }

        // If we found an __END__ marker, then we're going to define a global
        // DATA constant that is a file object that can be read to read the
        // contents after the marker.
        if (NIL_P(error) && result->parser.data_loc.start != NULL) {
            int xflag = opt->xflag;
            VALUE file = open_load_file(opt->script_name, &xflag);

            const pm_parser_t *parser = &result->parser;
            size_t offset = parser->data_loc.start - parser->start + 7;

            if ((parser->start + offset < parser->end) && parser->start[offset] == '\r') offset++;
            if ((parser->start + offset < parser->end) && parser->start[offset] == '\n') offset++;

            rb_funcall(file, rb_intern_const("seek"), 2, SIZET2NUM(offset), INT2FIX(SEEK_SET));
            rb_define_global_const("DATA", file);
        }
    }

    if (!NIL_P(error)) {
        pm_parse_result_free(result);
        rb_exc_raise(error);
    }
}

static VALUE
prism_dump_tree(pm_parse_result_t *result)
{
    pm_buffer_t output_buffer = { 0 };

    pm_prettyprint(&output_buffer, &result->parser, result->node.ast_node);
    VALUE tree = rb_str_new(output_buffer.value, output_buffer.length);
    pm_buffer_free(&output_buffer);
    return tree;
}

static void
process_options_global_setup(const ruby_cmdline_options_t *opt, const rb_iseq_t *iseq)
{
    if (OPT_BACKTRACE_LENGTH_LIMIT_VALID_P(opt)) {
        rb_backtrace_length_limit = opt->backtrace_length_limit;
    }

    if (opt->do_loop) {
        rb_define_global_function("sub", rb_f_sub, -1);
        rb_define_global_function("gsub", rb_f_gsub, -1);
        rb_define_global_function("chop", rb_f_chop, 0);
        rb_define_global_function("chomp", rb_f_chomp, -1);
    }

    rb_define_readonly_boolean("$-p", opt->do_print);
    rb_define_readonly_boolean("$-l", opt->do_line);
    rb_define_readonly_boolean("$-a", opt->do_split);

    rb_gvar_ractor_local("$-p");
    rb_gvar_ractor_local("$-l");
    rb_gvar_ractor_local("$-a");

    if ((rb_e_script = opt->e_script) != 0) {
        rb_str_freeze(rb_e_script);
        rb_vm_register_global_object(opt->e_script);
    }

    rb_execution_context_t *ec = GET_EC();
    VALUE script = (opt->e_script ? opt->e_script : Qnil);
    rb_exec_event_hook_script_compiled(ec, iseq, script);
}

static VALUE
process_options(int argc, char **argv, ruby_cmdline_options_t *opt)
{
    struct {
        rb_ast_t *ast;
        pm_parse_result_t prism;
    } result = {0};
#define dispose_result() \
    (result.ast ? rb_ast_dispose(result.ast) : pm_parse_result_free(&result.prism))

    const rb_iseq_t *iseq;
    rb_encoding *enc, *lenc;
#if UTF8_PATH
    rb_encoding *ienc = 0;
    rb_encoding *const uenc = rb_utf8_encoding();
#endif
    const char *s;
    char fbuf[MAXPATHLEN];
    int i = (int)proc_options(argc, argv, opt, 0);
    unsigned int dump = opt->dump & dump_exit_bits;
    rb_vm_t *vm = GET_VM();
    const long loaded_before_enc = RARRAY_LEN(vm->loaded_features);

    if (opt->dump & (DUMP_BIT(usage)|DUMP_BIT(help))) {
        const char *const progname =
            (argc > 0 && argv && argv[0] ? argv[0] :
             origarg.argc > 0 && origarg.argv && origarg.argv[0] ? origarg.argv[0] :
             ruby_engine);
        show_help(progname, (opt->dump & DUMP_BIT(help)));
        return Qtrue;
    }

    argc -= i;
    argv += i;

    if (FEATURE_SET_P(opt->features, rubyopt) && (s = getenv("RUBYOPT"))) {
        moreswitches(s, opt, 1);
    }

    if (opt->src.enc.name)
        /* cannot set deprecated category, as enabling deprecation warnings based on flags
         * has not happened yet.
         */
        rb_warning("-K is specified; it is for 1.8 compatibility and may cause odd behavior");

    if (!(FEATURE_SET_BITS(opt->features) & feature_jit_mask)) {
#if USE_YJIT
        if (!FEATURE_USED_P(opt->features, yjit) && env_var_truthy("RUBY_YJIT_ENABLE")) {
            FEATURE_SET(opt->features, FEATURE_BIT(yjit));
        }
#endif
    }
    if (MULTI_BITS_P(FEATURE_SET_BITS(opt->features) & feature_jit_mask)) {
        rb_warn("RJIT and YJIT cannot both be enabled at the same time. Exiting");
        return Qfalse;
    }

#if USE_RJIT
    if (FEATURE_SET_P(opt->features, rjit)) {
        opt->rjit.on = true; // set opt->rjit.on for Init_ruby_description() and calling rb_rjit_init()
    }
#endif
#if USE_YJIT
    if (FEATURE_SET_P(opt->features, yjit)) {
        opt->yjit = true; // set opt->yjit for Init_ruby_description() and calling rb_yjit_init()
    }
#endif

    ruby_mn_threads_params();
    Init_ruby_description(opt);

    if (opt->dump & (DUMP_BIT(version) | DUMP_BIT(version_v))) {
        ruby_show_version();
        if (opt->dump & DUMP_BIT(version)) return Qtrue;
    }
    if (opt->dump & DUMP_BIT(copyright)) {
        ruby_show_copyright();
        return Qtrue;
    }

    if (!opt->e_script) {
        if (argc <= 0) {	/* no more args */
            if (opt->verbose)
                return Qtrue;
            opt->script = "-";
        }
        else {
            opt->script = argv[0];
            if (!opt->script || opt->script[0] == '\0') {
                opt->script = "-";
            }
            else if (opt->do_search) {
                const char *path = getenv("RUBYPATH");

                opt->script = 0;
                if (path) {
                    opt->script = dln_find_file_r(argv[0], path, fbuf, sizeof(fbuf));
                }
                if (!opt->script) {
                    opt->script = dln_find_file_r(argv[0], getenv(PATH_ENV), fbuf, sizeof(fbuf));
                }
                if (!opt->script)
                    opt->script = argv[0];
            }
            argc--;
            argv++;
        }
        if (opt->script[0] == '-' && !opt->script[1]) {
            forbid_setid("program input from stdin");
        }
    }

    opt->script_name = rb_str_new_cstr(opt->script);
    opt->script = RSTRING_PTR(opt->script_name);

#ifdef _WIN32
    translit_char_bin(RSTRING_PTR(opt->script_name), '\\', '/');
#endif

    ruby_gc_set_params();
    ruby_init_loadpath();

    Init_enc();
    lenc = rb_locale_encoding();
    rb_enc_associate(rb_progname, lenc);
    rb_obj_freeze(rb_progname);
    if (opt->ext.enc.name != 0) {
        opt->ext.enc.index = opt_enc_index(opt->ext.enc.name);
    }
    if (opt->intern.enc.name != 0) {
        opt->intern.enc.index = opt_enc_index(opt->intern.enc.name);
    }
    if (opt->src.enc.name != 0) {
        opt->src.enc.index = opt_enc_index(opt->src.enc.name);
        src_encoding_index = opt->src.enc.index;
    }
    if (opt->ext.enc.index >= 0) {
        enc = rb_enc_from_index(opt->ext.enc.index);
    }
    else {
        enc = IF_UTF8_PATH(uenc, lenc);
    }
    rb_enc_set_default_external(rb_enc_from_encoding(enc));
    if (opt->intern.enc.index >= 0) {
        enc = rb_enc_from_index(opt->intern.enc.index);
        rb_enc_set_default_internal(rb_enc_from_encoding(enc));
        opt->intern.enc.index = -1;
#if UTF8_PATH
        ienc = enc;
#endif
    }
    rb_enc_associate(opt->script_name, IF_UTF8_PATH(uenc, lenc));
#if UTF8_PATH
    if (uenc != lenc) {
        opt->script_name = str_conv_enc(opt->script_name, uenc, lenc);
        opt->script = RSTRING_PTR(opt->script_name);
    }
#endif
    rb_obj_freeze(opt->script_name);
    if (IF_UTF8_PATH(uenc != lenc, 1)) {
        long i;
        VALUE load_path = vm->load_path;
        const ID id_initial_load_path_mark = INITIAL_LOAD_PATH_MARK;
        int modifiable = FALSE;

        rb_get_expanded_load_path();
        for (i = 0; i < RARRAY_LEN(load_path); ++i) {
            VALUE path = RARRAY_AREF(load_path, i);
            int mark = rb_attr_get(path, id_initial_load_path_mark) == path;
#if UTF8_PATH
            VALUE newpath = rb_str_conv_enc(path, uenc, lenc);
            if (newpath == path) continue;
            path = newpath;
#else
            if (!(path = copy_str(path, lenc, !mark))) continue;
#endif
            if (mark) rb_ivar_set(path, id_initial_load_path_mark, path);
            if (!modifiable) {
                rb_ary_modify(load_path);
                modifiable = TRUE;
            }
            RARRAY_ASET(load_path, i, path);
        }
        if (modifiable) {
            rb_ary_replace(vm->load_path_snapshot, load_path);
        }
    }
    {
        VALUE loaded_features = vm->loaded_features;
        bool modified = false;
        for (long i = loaded_before_enc; i < RARRAY_LEN(loaded_features); ++i) {
            VALUE path = RARRAY_AREF(loaded_features, i);
            if (!(path = copy_str(path, IF_UTF8_PATH(uenc, lenc), true))) continue;
            if (!modified) {
                rb_ary_modify(loaded_features);
                modified = true;
            }
            RARRAY_ASET(loaded_features, i, path);
        }
        if (modified) {
            rb_ary_replace(vm->loaded_features_snapshot, loaded_features);
        }
    }

    if (opt->features.mask & COMPILATION_FEATURES) {
        VALUE option = rb_hash_new();
#define SET_COMPILE_OPTION(h, o, name) \
        rb_hash_aset((h), ID2SYM(rb_intern_const(#name)), \
                     RBOOL(FEATURE_SET_P(o->features, name)))
        SET_COMPILE_OPTION(option, opt, frozen_string_literal);
        SET_COMPILE_OPTION(option, opt, debug_frozen_string_literal);
        rb_funcallv(rb_cISeq, rb_intern_const("compile_option="), 1, &option);
#undef SET_COMPILE_OPTION
    }
    ruby_set_argv(argc, argv);
    opt->sflag = process_sflag(opt->sflag);

    if (opt->e_script) {
        rb_encoding *eenc;
        if (opt->src.enc.index >= 0) {
            eenc = rb_enc_from_index(opt->src.enc.index);
        }
        else {
            eenc = lenc;
#if UTF8_PATH
            if (ienc) eenc = ienc;
#endif
        }
#if UTF8_PATH
        if (eenc != uenc) {
            opt->e_script = str_conv_enc(opt->e_script, uenc, eenc);
        }
#endif
        rb_enc_associate(opt->e_script, eenc);
    }

    if (!(*rb_ruby_prism_ptr())) {
        if (!(result.ast = process_script(opt))) return Qfalse;
    }
    else {
        prism_script(opt, &result.prism);
    }
    ruby_set_script_name(opt->script_name);
    if ((dump & DUMP_BIT(yydebug)) && !(dump &= ~DUMP_BIT(yydebug))) {
        dispose_result();
        return Qtrue;
    }

    if (opt->ext.enc.index >= 0) {
        enc = rb_enc_from_index(opt->ext.enc.index);
    }
    else {
        enc = IF_UTF8_PATH(uenc, lenc);
    }
    rb_enc_set_default_external(rb_enc_from_encoding(enc));
    if (opt->intern.enc.index >= 0) {
        /* Set in the shebang line */
        enc = rb_enc_from_index(opt->intern.enc.index);
        rb_enc_set_default_internal(rb_enc_from_encoding(enc));
    }
    else if (!rb_default_internal_encoding())
        /* Freeze default_internal */
        rb_enc_set_default_internal(Qnil);
    rb_stdio_set_default_encoding();

    opt->sflag = process_sflag(opt->sflag);
    opt->xflag = 0;

    if (dump & DUMP_BIT(syntax)) {
        printf("Syntax OK\n");
        dump &= ~DUMP_BIT(syntax);
        if (!dump) return Qtrue;
    }

    if (dump & DUMP_BIT(parsetree)) {
        VALUE tree;
        if (result.ast) {
            int comment = opt->dump & DUMP_BIT(opt_comment);
            tree = rb_parser_dump_tree(result.ast->body.root, comment);
        }
        else {
            tree = prism_dump_tree(&result.prism);
        }
        rb_io_write(rb_stdout, tree);
        rb_io_flush(rb_stdout);
        dump &= ~DUMP_BIT(parsetree);
        if (!dump) {
            dispose_result();
            return Qtrue;
        }
    }

    {
        VALUE path = Qnil;
        if (!opt->e_script && strcmp(opt->script, "-")) {
            path = rb_realpath_internal(Qnil, opt->script_name, 1);
#if UTF8_PATH
            if (uenc != lenc) {
                path = str_conv_enc(path, uenc, lenc);
            }
#endif
            if (!ENCODING_GET(path)) { /* ASCII-8BIT */
                rb_enc_copy(path, opt->script_name);
            }
        }

        rb_binding_t *toplevel_binding;
        GetBindingPtr(rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING")), toplevel_binding);
        const struct rb_block *base_block = toplevel_context(toplevel_binding);
        const rb_iseq_t *parent = vm_block_iseq(base_block);
        bool optimize = (opt->dump & DUMP_BIT(opt_optimize)) != 0;

        if (!result.ast) {
            pm_parse_result_t *pm = &result.prism;
            iseq = pm_iseq_new_main(&pm->node, opt->script_name, path, parent, optimize);
            pm_parse_result_free(pm);
        }
        else {
            rb_ast_t *ast = result.ast;
            iseq = rb_iseq_new_main(&ast->body, opt->script_name, path, parent, optimize);
            rb_ast_dispose(ast);
        }
    }

    if (dump & DUMP_BIT(insns)) {
        rb_io_write(rb_stdout, rb_iseq_disasm((const rb_iseq_t *)iseq));
        rb_io_flush(rb_stdout);
        dump &= ~DUMP_BIT(insns);
        if (!dump) return Qtrue;
    }
    if (opt->dump & dump_exit_bits) return Qtrue;

    process_options_global_setup(opt, iseq);
    return (VALUE)iseq;
}

#ifndef DOSISH
static void
warn_cr_in_shebang(const char *str, long len)
{
    if (len > 1 && str[len-1] == '\n' && str[len-2] == '\r') {
        rb_warn("shebang line ending with \\r may cause problems");
    }
}
#else
#define warn_cr_in_shebang(str, len) (void)0
#endif

void rb_reset_argf_lineno(long n);

struct load_file_arg {
    VALUE parser;
    VALUE fname;
    int script;
    ruby_cmdline_options_t *opt;
    VALUE f;
};

void rb_set_script_lines_for(VALUE vparser, VALUE path);

static VALUE
load_file_internal(VALUE argp_v)
{
    struct load_file_arg *argp = (struct load_file_arg *)argp_v;
    VALUE parser = argp->parser;
    VALUE orig_fname = argp->fname;
    int script = argp->script;
    ruby_cmdline_options_t *opt = argp->opt;
    VALUE f = argp->f;
    int line_start = 1;
    rb_ast_t *ast = 0;
    rb_encoding *enc;
    ID set_encoding;

    CONST_ID(set_encoding, "set_encoding");
    if (script) {
        VALUE c = 1;		/* something not nil */
        VALUE line;
        char *p, *str;
        long len;
        int no_src_enc = !opt->src.enc.name;
        int no_ext_enc = !opt->ext.enc.name;
        int no_int_enc = !opt->intern.enc.name;

        enc = rb_ascii8bit_encoding();
        rb_funcall(f, set_encoding, 1, rb_enc_from_encoding(enc));

        if (opt->xflag) {
            line_start--;
          search_shebang:
            while (!NIL_P(line = rb_io_gets(f))) {
                line_start++;
                RSTRING_GETMEM(line, str, len);
                if (len > 2 && str[0] == '#' && str[1] == '!') {
                    if (line_start == 1) warn_cr_in_shebang(str, len);
                    if ((p = strstr(str+2, ruby_engine)) != 0) {
                        goto start_read;
                    }
                }
            }
            rb_loaderror("no Ruby script found in input");
        }

        c = rb_io_getbyte(f);
        if (c == INT2FIX('#')) {
            c = rb_io_getbyte(f);
            if (c == INT2FIX('!') && !NIL_P(line = rb_io_gets(f))) {
                RSTRING_GETMEM(line, str, len);
                warn_cr_in_shebang(str, len);
                if ((p = strstr(str, ruby_engine)) == 0) {
                    /* not ruby script, assume -x flag */
                    goto search_shebang;
                }

              start_read:
                str += len - 1;
                if (*str == '\n') *str-- = '\0';
                if (*str == '\r') *str-- = '\0';
                /* ruby_engine should not contain a space */
                if ((p = strstr(p, " -")) != 0) {
                    opt->warning = 0;
                    moreswitches(p + 1, opt, 0);
                }

                /* push back shebang for pragma may exist in next line */
                rb_io_ungetbyte(f, rb_str_new2("!\n"));
            }
            else if (!NIL_P(c)) {
                rb_io_ungetbyte(f, c);
            }
            rb_io_ungetbyte(f, INT2FIX('#'));
            if (no_src_enc && opt->src.enc.name) {
                opt->src.enc.index = opt_enc_index(opt->src.enc.name);
                src_encoding_index = opt->src.enc.index;
            }
            if (no_ext_enc && opt->ext.enc.name) {
                opt->ext.enc.index = opt_enc_index(opt->ext.enc.name);
            }
            if (no_int_enc && opt->intern.enc.name) {
                opt->intern.enc.index = opt_enc_index(opt->intern.enc.name);
            }
        }
        else if (!NIL_P(c)) {
            rb_io_ungetbyte(f, c);
        }
        if (NIL_P(c)) {
            argp->f = f = Qnil;
        }
        rb_reset_argf_lineno(0);
        ruby_opt_init(opt);
    }
    if (opt->src.enc.index >= 0) {
        enc = rb_enc_from_index(opt->src.enc.index);
    }
    else if (f == rb_stdin) {
        enc = rb_locale_encoding();
    }
    else {
        enc = rb_utf8_encoding();
    }
    rb_parser_set_options(parser, opt->do_print, opt->do_loop,
                          opt->do_line, opt->do_split);

    rb_set_script_lines_for(parser, orig_fname);

    if (NIL_P(f)) {
        f = rb_str_new(0, 0);
        rb_enc_associate(f, enc);
        return (VALUE)rb_parser_compile_string_path(parser, orig_fname, f, line_start);
    }
    rb_funcall(f, set_encoding, 2, rb_enc_from_encoding(enc), rb_str_new_cstr("-"));
    ast = rb_parser_compile_file_path(parser, orig_fname, f, line_start);
    rb_funcall(f, set_encoding, 1, rb_parser_encoding(parser));
    if (script && rb_parser_end_seen_p(parser)) {
        /*
         * DATA is a File that contains the data section of the executed file.
         * To create a data section use <tt>__END__</tt>:
         *
         *   $ cat t.rb
         *   puts DATA.gets
         *   __END__
         *   hello world!
         *
         *   $ ruby t.rb
         *   hello world!
         */
        rb_define_global_const("DATA", f);
        argp->f = Qnil;
    }
    return (VALUE)ast;
}

/* disabling O_NONBLOCK, and returns 0 on success, otherwise errno */
static inline int
disable_nonblock(int fd)
{
#if defined(HAVE_FCNTL) && defined(F_SETFL)
    if (fcntl(fd, F_SETFL, 0) < 0) {
        const int e = errno;
        ASSUME(e != 0);
# if defined ENOTSUP
        if (e == ENOTSUP) return 0;
# endif
# if defined B_UNSUPPORTED
        if (e == B_UNSUPPORTED) return 0;
# endif
        return e;
    }
#endif
    return 0;
}

static VALUE
open_load_file(VALUE fname_v, int *xflag)
{
    const char *fname = (fname_v = rb_str_encode_ospath(fname_v),
                         StringValueCStr(fname_v));
    long flen = RSTRING_LEN(fname_v);
    VALUE f;
    int e;

    if (flen == 1 && fname[0] == '-') {
        f = rb_stdin;
    }
    else {
        int fd;
        /* open(2) may block if fname is point to FIFO and it's empty. Let's
           use O_NONBLOCK. */
        const int MODE_TO_LOAD = O_RDONLY | (
#if defined O_NONBLOCK && HAVE_FCNTL
        /* TODO: fix conflicting O_NONBLOCK in ruby/win32.h */
            !(O_NONBLOCK & O_ACCMODE) ? O_NONBLOCK :
#endif
#if defined O_NDELAY && HAVE_FCNTL
            !(O_NDELAY & O_ACCMODE) ? O_NDELAY :
#endif
            0);
        int mode = MODE_TO_LOAD;
#if defined DOSISH || defined __CYGWIN__
# define isdirsep(x) ((x) == '/' || (x) == '\\')
        {
            static const char exeext[] = ".exe";
            enum {extlen = sizeof(exeext)-1};
            if (flen > extlen && !isdirsep(fname[flen-extlen-1]) &&
                STRNCASECMP(fname+flen-extlen, exeext, extlen) == 0) {
                mode |= O_BINARY;
                *xflag = 1;
            }
        }
#endif

        if ((fd = rb_cloexec_open(fname, mode, 0)) < 0) {
            e = errno;
            if (!rb_gc_for_fd(e)) {
                rb_load_fail(fname_v, strerror(e));
            }
            if ((fd = rb_cloexec_open(fname, mode, 0)) < 0) {
                rb_load_fail(fname_v, strerror(errno));
            }
        }
        rb_update_max_fd(fd);

        if (MODE_TO_LOAD != O_RDONLY && (e = disable_nonblock(fd)) != 0) {
            (void)close(fd);
            rb_load_fail(fname_v, strerror(e));
        }

        e = ruby_is_fd_loadable(fd);
        if (!e) {
            e = errno;
            (void)close(fd);
            rb_load_fail(fname_v, strerror(e));
        }

        f = rb_io_fdopen(fd, mode, fname);
        if (e < 0) {
            /*
              We need to wait if FIFO is empty. It's FIFO's semantics.
              rb_thread_wait_fd() release GVL. So, it's safe.
            */
            rb_io_wait(f, RB_INT2NUM(RUBY_IO_READABLE), Qnil);
        }
    }
    return f;
}

static VALUE
restore_load_file(VALUE arg)
{
    struct load_file_arg *argp = (struct load_file_arg *)arg;
    VALUE f = argp->f;

    if (!NIL_P(f) && f != rb_stdin) {
        rb_io_close(f);
    }
    return Qnil;
}

static rb_ast_t *
load_file(VALUE parser, VALUE fname, VALUE f, int script, ruby_cmdline_options_t *opt)
{
    struct load_file_arg arg;
    arg.parser = parser;
    arg.fname = fname;
    arg.script = script;
    arg.opt = opt;
    arg.f = f;
    return (rb_ast_t *)rb_ensure(load_file_internal, (VALUE)&arg,
                              restore_load_file, (VALUE)&arg);
}

void *
rb_load_file(const char *fname)
{
    VALUE fname_v = rb_str_new_cstr(fname);
    return rb_load_file_str(fname_v);
}

void *
rb_load_file_str(VALUE fname_v)
{
    return rb_parser_load_file(rb_parser_new(), fname_v);
}

void *
rb_parser_load_file(VALUE parser, VALUE fname_v)
{
    ruby_cmdline_options_t opt;
    int xflag = 0;
    VALUE f = open_load_file(fname_v, &xflag);
    cmdline_options_init(&opt)->xflag = xflag != 0;
    return load_file(parser, fname_v, f, 0, &opt);
}

/*
 *  call-seq:
 *     Process.argv0  -> frozen_string
 *
 *  Returns the name of the script being executed.  The value is not
 *  affected by assigning a new value to $0.
 *
 *  This method first appeared in Ruby 2.1 to serve as a global
 *  variable free means to get the script name.
 */

static VALUE
proc_argv0(VALUE process)
{
    return rb_orig_progname;
}

static VALUE ruby_setproctitle(VALUE title);

/*
 *  call-seq:
 *     Process.setproctitle(string)  -> string
 *
 *  Sets the process title that appears on the ps(1) command.  Not
 *  necessarily effective on all platforms.  No exception will be
 *  raised regardless of the result, nor will NotImplementedError be
 *  raised even if the platform does not support the feature.
 *
 *  Calling this method does not affect the value of $0.
 *
 *     Process.setproctitle('myapp: worker #%d' % worker_id)
 *
 *  This method first appeared in Ruby 2.1 to serve as a global
 *  variable free means to change the process title.
 */

static VALUE
proc_setproctitle(VALUE process, VALUE title)
{
    return ruby_setproctitle(title);
}

static VALUE
ruby_setproctitle(VALUE title)
{
    const char *ptr = StringValueCStr(title);
    setproctitle("%.*s", RSTRING_LENINT(title), ptr);
    return title;
}

static void
set_arg0(VALUE val, ID id, VALUE *_)
{
    if (origarg.argv == 0)
        rb_raise(rb_eRuntimeError, "$0 not initialized");

    rb_progname = rb_str_new_frozen(ruby_setproctitle(val));
}

static inline VALUE
external_str_new_cstr(const char *p)
{
#if UTF8_PATH
    VALUE str = rb_utf8_str_new_cstr(p);
    str = str_conv_enc(str, NULL, rb_default_external_encoding());
    return str;
#else
    return rb_external_str_new_cstr(p);
#endif
}

static void
set_progname(VALUE name)
{
    rb_orig_progname = rb_progname = name;
    rb_vm_set_progname(rb_progname);
}

void
ruby_script(const char *name)
{
    if (name) {
        set_progname(rb_str_freeze(external_str_new_cstr(name)));
    }
}

/*! Sets the current script name to this value.
 *
 * Same as ruby_script() but accepts a VALUE.
 */
void
ruby_set_script_name(VALUE name)
{
    set_progname(rb_str_new_frozen(name));
}

static void
init_ids(ruby_cmdline_options_t *opt)
{
    rb_uid_t uid = getuid();
    rb_uid_t euid = geteuid();
    rb_gid_t gid = getgid();
    rb_gid_t egid = getegid();

    if (uid != euid) opt->setids |= 1;
    if (egid != gid) opt->setids |= 2;
}

#undef forbid_setid
static void
forbid_setid(const char *s, const ruby_cmdline_options_t *opt)
{
    if (opt->setids & 1)
        rb_raise(rb_eSecurityError, "no %s allowed while running setuid", s);
    if (opt->setids & 2)
        rb_raise(rb_eSecurityError, "no %s allowed while running setgid", s);
}

static VALUE
verbose_getter(ID id, VALUE *ptr)
{
    return *rb_ruby_verbose_ptr();
}

static void
verbose_setter(VALUE val, ID id, VALUE *variable)
{
    *rb_ruby_verbose_ptr() = RTEST(val) ? Qtrue : val;
}

static VALUE
opt_W_getter(ID id, VALUE *dmy)
{
    VALUE v = *rb_ruby_verbose_ptr();

    switch (v) {
      case Qnil:
        return INT2FIX(0);
      case Qfalse:
        return INT2FIX(1);
      case Qtrue:
        return INT2FIX(2);
      default:
        return Qnil;
    }
}

static VALUE
debug_getter(ID id, VALUE *dmy)
{
    return *rb_ruby_debug_ptr();
}

static void
debug_setter(VALUE val, ID id, VALUE *dmy)
{
    *rb_ruby_debug_ptr() = val;
}

void
ruby_prog_init(void)
{
    rb_define_virtual_variable("$VERBOSE", verbose_getter, verbose_setter);
    rb_define_virtual_variable("$-v",      verbose_getter, verbose_setter);
    rb_define_virtual_variable("$-w",      verbose_getter, verbose_setter);
    rb_define_virtual_variable("$-W",      opt_W_getter,   rb_gvar_readonly_setter);
    rb_define_virtual_variable("$DEBUG",   debug_getter,   debug_setter);
    rb_define_virtual_variable("$-d",      debug_getter,   debug_setter);

    rb_gvar_ractor_local("$VERBOSE");
    rb_gvar_ractor_local("$-v");
    rb_gvar_ractor_local("$-w");
    rb_gvar_ractor_local("$-W");
    rb_gvar_ractor_local("$DEBUG");
    rb_gvar_ractor_local("$-d");

    rb_define_hooked_variable("$0", &rb_progname, 0, set_arg0);
    rb_define_hooked_variable("$PROGRAM_NAME", &rb_progname, 0, set_arg0);

    rb_define_module_function(rb_mProcess, "argv0", proc_argv0, 0);
    rb_define_module_function(rb_mProcess, "setproctitle", proc_setproctitle, 1);

    /*
     * ARGV contains the command line arguments used to run ruby.
     *
     * A library like OptionParser can be used to process command-line
     * arguments.
     */
    rb_define_global_const("ARGV", rb_argv);
}

void
ruby_set_argv(int argc, char **argv)
{
    int i;
    VALUE av = rb_argv;

    rb_ary_clear(av);
    for (i = 0; i < argc; i++) {
        VALUE arg = external_str_new_cstr(argv[i]);

        OBJ_FREEZE(arg);
        rb_ary_push(av, arg);
    }
}

void *
ruby_process_options(int argc, char **argv)
{
    ruby_cmdline_options_t opt;
    VALUE iseq;
    const char *script_name = (argc > 0 && argv[0]) ? argv[0] : ruby_engine;

    (*rb_ruby_prism_ptr()) = false;

    if (!origarg.argv || origarg.argc <= 0) {
        origarg.argc = argc;
        origarg.argv = argv;
    }
    set_progname(external_str_new_cstr(script_name));  /* for the time being */
    rb_argv0 = rb_str_new4(rb_progname);
    rb_vm_register_global_object(rb_argv0);

#ifndef HAVE_SETPROCTITLE
    ruby_init_setproctitle(argc, argv);
#endif

    iseq = process_options(argc, argv, cmdline_options_init(&opt));

    if (opt.crash_report && *opt.crash_report) {
        void ruby_set_crash_report(const char *template);
        ruby_set_crash_report(opt.crash_report);
    }
    return (void*)(struct RData*)iseq;
}

static void
fill_standard_fds(void)
{
    int f0, f1, f2, fds[2];
    struct stat buf;
    f0 = fstat(0, &buf) == -1 && errno == EBADF;
    f1 = fstat(1, &buf) == -1 && errno == EBADF;
    f2 = fstat(2, &buf) == -1 && errno == EBADF;
    if (f0) {
        if (pipe(fds) == 0) {
            close(fds[1]);
            if (fds[0] != 0) {
                dup2(fds[0], 0);
                close(fds[0]);
            }
        }
    }
    if (f1 || f2) {
        if (pipe(fds) == 0) {
            close(fds[0]);
            if (f1 && fds[1] != 1)
                dup2(fds[1], 1);
            if (f2 && fds[1] != 2)
                dup2(fds[1], 2);
            if (fds[1] != 1 && fds[1] != 2)
                close(fds[1]);
        }
    }
}

void
ruby_sysinit(int *argc, char ***argv)
{
#if defined(_WIN32)
    rb_w32_sysinit(argc, argv);
#endif
    if (*argc >= 0 && *argv) {
        origarg.argc = *argc;
        origarg.argv = *argv;
    }
    fill_standard_fds();
}
