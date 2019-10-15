/**********************************************************************

  ruby.c -

  $Author$
  created at: Tue Aug 10 12:47:31 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifdef __CYGWIN__
#include <windows.h>
#include <sys/cygwin.h>
#endif
#include "ruby/encoding.h"
#include "ruby/thread.h"
#include "ruby/version.h"
#include "internal.h"
#include "eval_intern.h"
#include "dln.h"
#include <stdio.h>
#include <sys/types.h>
#include <ctype.h>

#ifdef __hpux
#include <sys/pstat.h>
#endif
#if defined(LOAD_RELATIVE) && defined(HAVE_DLADDR)
#include <dlfcn.h>
#endif

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#if defined(HAVE_FCNTL_H)
#include <fcntl.h>
#elif defined(HAVE_SYS_FCNTL_H)
#include <sys/fcntl.h>
#endif
#ifdef HAVE_SYS_PARAM_H
# include <sys/param.h>
#endif
#ifndef MAXPATHLEN
# define MAXPATHLEN 1024
#endif
#ifndef O_ACCMODE
# define O_ACCMODE (O_RDONLY | O_WRONLY | O_RDWR)
#endif

#include "ruby/util.h"

#include "mjit.h"

void Init_ruby_description(void);

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

#define COMMA ,
#define FEATURE_BIT(bit) (1U << feature_##bit)
#define EACH_FEATURES(X, SEP) \
    X(gems) \
    SEP \
    X(did_you_mean) \
    SEP \
    X(rubyopt) \
    SEP \
    X(frozen_string_literal) \
    SEP \
    X(jit) \
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
    feature_debug_flag_begin = feature_debug_flag_first - 1,
    EACH_DEBUG_FEATURES(DEFINE_DEBUG_FEATURE, COMMA),
    feature_flag_count
};

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
    X(parsetree_with_comment) \
    SEP \
    X(insns) \
    /* END OF DUMPS */
enum dump_flag_bits {
    dump_version_v,
    EACH_DUMPS(DEFINE_DUMP, COMMA),
    dump_exit_bits = (DUMP_BIT(yydebug) | DUMP_BIT(syntax) |
		      DUMP_BIT(parsetree) | DUMP_BIT(parsetree_with_comment) |
		      DUMP_BIT(insns))
};

typedef struct ruby_cmdline_options ruby_cmdline_options_t;

typedef struct {
    unsigned int mask;
    unsigned int set;
} ruby_features_t;

static inline void
rb_feature_set_to(ruby_features_t *feat, unsigned int bit_mask, unsigned int bit_set)
{
    feat->mask |= bit_mask;
    feat->set = (feat->set & ~bit_mask) | bit_set;
}

#define FEATURE_SET_TO(feat, bit_mask, bit_set) \
    rb_feature_set_to(&(feat), bit_mask, bit_set)
#define FEATURE_SET(feat, bits) FEATURE_SET_TO(feat, bits, bits)
#define FEATURE_SET_P(feat, bits) ((feat).set & (bits))

struct ruby_cmdline_options {
    const char *script;
    VALUE script_name;
    VALUE e_script;
    struct {
	struct {
	    VALUE name;
	    int index;
	} enc;
    } src, ext, intern;
    VALUE req_list;
    ruby_features_t features;
    unsigned int dump;
#if USE_MJIT
    struct mjit_options mjit;
#endif
    int safe_level;
    int sflag, xflag;
    unsigned int warning: 1;
    unsigned int verbose: 1;
    unsigned int do_loop: 1;
    unsigned int do_print: 1;
    unsigned int do_line: 1;
    unsigned int do_split: 1;
    unsigned int do_search: 1;
    unsigned int setids: 2;
};

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
        & ~FEATURE_BIT(jit)
	)
};

static ruby_cmdline_options_t *
cmdline_options_init(ruby_cmdline_options_t *opt)
{
    MEMZERO(opt, *opt, 1);
    init_ids(opt);
    opt->src.enc.index = src_encoding_index;
    opt->ext.enc.index = -1;
    opt->intern.enc.index = -1;
    opt->features.set = DEFAULT_FEATURES;
#ifdef MJIT_FORCE_ENABLE /* to use with: ./configure cppflags="-DMJIT_FORCE_ENABLE" */
    opt->features.set |= FEATURE_BIT(jit);
#endif
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

static void
show_usage_line(const char *str, unsigned int namelen, unsigned int secondlen, int help)
{
    const unsigned int w = 16;
    const int wrap = help && namelen + secondlen - 1 > w;
    printf("  %.*s%-*.*s%-*s%s\n", namelen-1, str,
	   (wrap ? 0 : w - namelen + 1),
	   (help ? secondlen-1 : 0), str + namelen,
	   (wrap ? w + 3 : 0), (wrap ? "\n" : ""),
	   str + namelen + secondlen);
}

static void
usage(const char *name, int help)
{
    /* This message really ought to be max 23 lines.
     * Removed -h because the user already knows that option. Others? */

    struct message {
	const char *str;
	unsigned short namelen, secondlen;
    };
#define M(shortopt, longopt, desc) { \
    shortopt " " longopt " " desc, \
    (unsigned short)sizeof(shortopt), \
    (unsigned short)sizeof(longopt), \
}
    static const struct message usage_msg[] = {
	M("-0[octal]",	   "",			   "specify record separator (\\0, if no argument)"),
	M("-a",		   "",			   "autosplit mode with -n or -p (splits $_ into $F)"),
	M("-c",		   "",			   "check syntax only"),
	M("-Cdirectory",   "",			   "cd to directory before executing your script"),
	M("-d",		   ", --debug",		   "set debugging flags (set $DEBUG to true)"),
	M("-e 'command'",  "",			   "one line of script. Several -e's allowed. Omit [programfile]"),
	M("-Eex[:in]",     ", --encoding=ex[:in]", "specify the default external and internal character encodings"),
	M("-Fpattern",	   "",			   "split() pattern for autosplit (-a)"),
	M("-i[extension]", "",			   "edit ARGV files in place (make backup if extension supplied)"),
	M("-Idirectory",   "",			   "specify $LOAD_PATH directory (may be used more than once)"),
	M("-l",		   "",			   "enable line ending processing"),
	M("-n",		   "",			   "assume 'while gets(); ... end' loop around your script"),
	M("-p",		   "",			   "assume loop like -n but print line also like sed"),
	M("-rlibrary",	   "",			   "require the library before executing your script"),
	M("-s",		   "",			   "enable some switch parsing for switches after script name"),
	M("-S",		   "",			   "look for the script using PATH environment variable"),
	M("-T[level=1]",   "",			   "turn on tainting checks"),
	M("-v",		   "",			   "print the version number, then turn on verbose mode"),
	M("-w",		   "",			   "turn warnings on for your script"),
	M("-W[level=2]",   "",			   "set warning level; 0=silence, 1=medium, 2=verbose"),
	M("-x[directory]", "",			   "strip off text before #!ruby line and perhaps cd to directory"),
        M("--jit",         "",                     "enable JIT with default options (experimental)"),
        M("--jit-[option]","",                     "enable JIT with an option (experimental)"),
	M("-h",		   "",			   "show this message, --help for more info"),
    };
    static const struct message help_msg[] = {
	M("--copyright",                            "", "print the copyright"),
	M("--dump={insns|parsetree|...}[,...]",     "",
          "dump debug information. see below for available dump list"),
	M("--enable={gems|rubyopt|...}[,...]", ", --disable={gems|rubyopt|...}[,...]",
	  "enable or disable features. see below for available features"),
	M("--external-encoding=encoding",           ", --internal-encoding=encoding",
	  "specify the default external or internal character encoding"),
	M("--verbose",                              "", "turn on verbose mode and disable script from stdin"),
	M("--version",                              "", "print the version number, then exit"),
	M("--help",			            "", "show this message, -h for short message"),
    };
    static const struct message dumps[] = {
	M("insns",                  "", "instruction sequences"),
	M("yydebug",                "", "yydebug of yacc parser generator"),
	M("parsetree",              "", "AST"),
	M("parsetree_with_comment", "", "AST with comments"),
    };
    static const struct message features[] = {
	M("gems",    "",        "rubygems (default: "DEFAULT_RUBYGEMS_ENABLED")"),
	M("did_you_mean", "",   "did_you_mean (default: "DEFAULT_RUBYGEMS_ENABLED")"),
	M("rubyopt", "",        "RUBYOPT environment variable (default: enabled)"),
	M("frozen-string-literal", "", "freeze all string literals (default: disabled)"),
        M("jit", "",            "JIT compiler (default: disabled)"),
    };
    static const struct message mjit_options[] = {
        M("--jit-warnings",      "", "Enable printing JIT warnings"),
        M("--jit-debug",         "", "Enable JIT debugging (very slow)"),
        M("--jit-wait",          "", "Wait until JIT compilation is finished everytime (for testing)"),
        M("--jit-save-temps",    "", "Save JIT temporary files in $TMP or /tmp (for testing)"),
        M("--jit-verbose=num",   "", "Print JIT logs of level num or less to stderr (default: 0)"),
        M("--jit-max-cache=num", "", "Max number of methods to be JIT-ed in a cache (default: 100)"),
        M("--jit-min-calls=num", "", "Number of calls to trigger JIT (for testing, default: 10000)"),
    };
    int i;
    const int num = numberof(usage_msg) - (help ? 1 : 0);
#define SHOW(m) show_usage_line((m).str, (m).namelen, (m).secondlen, help)

    printf("Usage: %s [switches] [--] [programfile] [arguments]\n", name);
    for (i = 0; i < num; ++i)
	SHOW(usage_msg[i]);

    if (!help) return;

    for (i = 0; i < numberof(help_msg); ++i)
	SHOW(help_msg[i]);
    puts("Dump List:");
    for (i = 0; i < numberof(dumps); ++i)
	SHOW(dumps[i]);
    puts("Features:");
    for (i = 0; i < numberof(features); ++i)
	SHOW(features[i]);
    puts("JIT options (experimental):");
    for (i = 0; i < numberof(mjit_options); ++i)
	SHOW(mjit_options[i]);
}

#define rubylib_path_new rb_str_new

static void
push_include(const char *path, VALUE (*filter)(VALUE))
{
    const char sep = PATH_SEP_CHAR;
    const char *p, *s;
    VALUE load_path = GET_VM()->load_path;

    p = path;
    while (*p) {
	while (*p == sep)
	    p++;
	if (!*p) break;
	for (s = p; *s && *s != sep; s = CharNext(s));
	rb_ary_push(load_path, (*filter)(rubylib_path_new(p, s - p)));
	p = s;
    }
}

#ifdef __CYGWIN__
static void
push_include_cygwin(const char *path, VALUE (*filter)(VALUE))
{
    const char *p, *s;
    char rubylib[FILENAME_MAX];
    VALUE buf = 0;

    p = path;
    while (*p) {
	unsigned int len;
	while (*p == ';')
	    p++;
	if (!*p) break;
	for (s = p; *s && *s != ';'; s = CharNext(s));
	len = s - p;
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
	if (CONV_TO_POSIX_PATH(p, rubylib) == 0)
	    p = rubylib;
	push_include(p, filter);
	if (!*s) break;
	p = s + 1;
    }
}

#define push_include push_include_cygwin
#endif

void
ruby_push_include(const char *path, VALUE (*filter)(VALUE))
{
    if (path == 0)
	return;
    push_include(path, filter);
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

void ruby_init_loadpath_safe(int safe_level);

void
ruby_init_loadpath(void)
{
    ruby_init_loadpath_safe(0);
}

#if defined(LOAD_RELATIVE)
static VALUE
runtime_libruby_path(void)
{
#if defined _WIN32 || defined __CYGWIN__
    DWORD len = RSTRING_EMBED_LEN_MAX, ret;
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
ruby_init_loadpath_safe(int safe_level)
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
	    OBJ_FREEZE_RAW(archlibdir);
	}
	else if (p - libpath >= libdir_len && !strncmp(p - libdir_len, libdir, libdir_len)) {
	    archlibdir = rb_str_subseq(sopath, 0, (p2 ? p2 : p) - libpath);
	    OBJ_FREEZE_RAW(archlibdir);
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
    }
    baselen = p - libpath;
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
    OBJ_FREEZE_RAW(ruby_prefix_path);
    if (!archlibdir) archlibdir = ruby_prefix_path;
    rb_gc_register_address(&ruby_archlibdir_path);
    ruby_archlibdir_path = archlibdir;

    load_path = GET_VM()->load_path;

    if (safe_level == 0) {
	ruby_push_include(getenv("RUBYLIB"), identical_path);
    }

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
	*req_list = list = rb_ary_tmp_new(0);
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

static void
process_sflag(int *sflag)
{
    if (*sflag > 0) {
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
	*sflag = -1;
    }
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

    while (ISSPACE(*s)) s++;
    if (!*s) return;
    argstr = rb_str_tmp_new((len = strlen(s)) + (envopt!=0));
    argary = rb_str_tmp_new(0);

    p = RSTRING_PTR(argstr);
    if (envopt) *p++ = ' ';
    memcpy(p, s, len + 1);
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
	    if (!--len || !*++str) return 1;
	    ++name;
	}
	if (*str != '-' && *str != '_') return 0;
	while (ISALNUM(*name)) name++;
	if (*name != '-' && *name != '_') return 0;
	++name;
	++str;
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
    if (NAME_MATCH_P("all", str, len)) {
      found:
        FEATURE_SET_TO(*argp, mask, (mask & enable));
	return;
    }
#if AMBIGUOUS_FEATURE_NAMES
    if (matched == 1) goto found;
    if (matched > 1) {
	VALUE mesg = rb_sprintf("ambiguous feature: `%.*s' (", len, str);
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
#endif
    rb_warn("unknown argument for --%s: `%.*s'",
	    enable ? "enable" : "disable", len, str);
    rb_warn("features are [%.*s].", (int)strlen(list), list);
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
    rb_warn("unknown argument for --debug: `%.*s'", len, str);
    rb_warn("debug features are [%.*s].", (int)strlen(list), list);
}

static void
dump_option(const char *str, int len, void *arg)
{
    static const char list[] = EACH_DUMPS(LITERAL_NAME_ELEMENT, ", ");
#define SET_WHEN_DUMP(bit) SET_WHEN(#bit, DUMP_BIT(bit), str, len)
    EACH_DUMPS(SET_WHEN_DUMP, ;);
    rb_warn("don't know how to dump `%.*s',", len, str);
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

#if USE_MJIT
static void
setup_mjit_options(const char *s, struct mjit_options *mjit_opt)
{
    if (*s == 0) return;
    else if (strcmp(s, "-warnings") == 0) {
        mjit_opt->warnings = 1;
    }
    else if (strcmp(s, "-debug") == 0) {
        mjit_opt->debug = 1;
    }
    else if (strcmp(s, "-wait") == 0) {
        mjit_opt->wait = 1;
    }
    else if (strcmp(s, "-save-temps") == 0) {
        mjit_opt->save_temps = 1;
    }
    else if (strncmp(s, "-verbose=", 9) == 0) {
        mjit_opt->verbose = atoi(s + 9);
    }
    else if (strncmp(s, "-max-cache=", 11) == 0) {
        mjit_opt->max_cache_size = atoi(s + 11);
    }
    else if (strncmp(s, "-min-calls=", 11) == 0) {
        mjit_opt->min_calls = atoi(s + 11);
    }
    else {
        rb_raise(rb_eRuntimeError,
                 "invalid MJIT option `%s' (--help will show valid MJIT options)", s + 1);
    }
}
#endif

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
	    s++;
	    goto reswitch;

	  case 'W':
	    {
		size_t numlen;
		int v = 2;	/* -W as -W2 */

		if (*++s) {
		    v = scan_oct(s, 1, &numlen);
		    if (numlen == 0)
			v = 1;
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
		warning = 1;
	    }
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
	    forbid_setid("-e");
	    if (!*++s) {
		if (!--argc)
		    rb_raise(rb_eRuntimeError, "no code specified for -e");
		s = *++argv;
	    }
	    if (!opt->e_script) {
		opt->e_script = rb_str_new(0, 0);
		if (opt->script == 0)
		    opt->script = "-e";
	    }
	    rb_str_cat2(opt->e_script, s);
	    rb_str_cat2(opt->e_script, "\n");
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
	    goto encoding;

	  case 'U':
	    set_internal_encoding_once(opt, "UTF-8", 0);
	    ++s;
	    goto reswitch;

	  case 'K':
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
	    goto reswitch;

	  case 'T':
	    {
		size_t numlen;
		int v = 1;

		if (*++s) {
		    v = scan_oct(s, 2, &numlen);
		    if (numlen == 0)
			v = 1;
		    s += numlen;
		}
		if (v > opt->safe_level) opt->safe_level = v;
	    }
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
	    }
	    goto reswitch;

	  case '-':
	    if (!s[1] || (s[1] == '\r' && !s[2])) {
		argc--, argv++;
		goto switch_end;
	    }
	    s++;

#	define is_option_end(c, allow_hyphen) \
	    (!(c) || ((allow_hyphen) && (c) == '-') || (c) == '=')
#	define check_envopt(name, allow_envopt) \
	    (((allow_envopt) || !envopt) ? (void)0 : \
	     rb_raise(rb_eRuntimeError, "invalid switch in RUBYOPT: --" name))
#	define need_argument(name, s, needs_arg, next_arg)			\
	    ((*(s) ? !*++(s) : (next_arg) && (!argc || !((s) = argv[1]) || (--argc, ++argv, 0))) && (needs_arg) ? \
	     rb_raise(rb_eRuntimeError, "missing argument for --" name) \
	     : (void)0)
#	define is_option_with_arg(name, allow_hyphen, allow_envopt)	\
	    is_option_with_optarg(name, allow_hyphen, allow_envopt, Qtrue, Qtrue)
#	define is_option_with_optarg(name, allow_hyphen, allow_envopt, needs_arg, next_arg) \
	    (strncmp((name), s, n = sizeof(name) - 1) == 0 && is_option_end(s[n], (allow_hyphen)) ? \
	     (check_envopt(name, (allow_envopt)), s += n, \
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
		char *p;
	      encoding:
		do {
#	define set_encoding_part(type) \
		    if (!(p = strchr(s, ':'))) { \
			set_##type##_encoding_once(opt, s, 0); \
			break; \
		    } \
		    else if (p > s) { \
			set_##type##_encoding_once(opt, s, p-s); \
		    }
		    set_encoding_part(external);
		    if (!*(s = ++p)) break;
		    set_encoding_part(internal);
		    if (!*(s = ++p)) break;
#if defined ALLOW_DEFAULT_SOURCE_ENCODING && ALLOW_DEFAULT_SOURCE_ENCODING
		    set_encoding_part(source);
		    if (!*(s = ++p)) break;
#endif
		    rb_raise(rb_eRuntimeError, "extra argument for %s: %s",
			     (arg[1] == '-' ? "--encoding" : "-E"), s);
#	undef set_encoding_part
		} while (0);
	    }
	    else if (is_option_with_arg("internal-encoding", Qfalse, Qtrue)) {
		set_internal_encoding_once(opt, s, 0);
	    }
	    else if (is_option_with_arg("external-encoding", Qfalse, Qtrue)) {
		set_external_encoding_once(opt, s, 0);
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
            else if (strncmp("jit", s, 3) == 0) {
#if USE_MJIT
                FEATURE_SET(opt->features, FEATURE_BIT(jit));
                setup_mjit_options(s + 3, &opt->mjit);
#else
                rb_warn("MJIT support is disabled.");
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
		goto switch_end;
	    }
	    else {
		rb_raise(rb_eRuntimeError,
			 "invalid option --%s  (-h will show valid options)", s);
	    }
	    break;

	  case '\r':
	    if (!s[1])
		break;

	  default:
	    {
                rb_raise(rb_eRuntimeError,
			"invalid option -%c  (-h will show valid options)",
                        (int)(unsigned char)*s);
	    }
	    goto switch_end;

	  noenvopt:
	    /* "EIdvwWrKU" only */
	    rb_raise(rb_eRuntimeError, "invalid switch in RUBYOPT: -%c", *s);
	    break;

	  noenvopt_long:
	    rb_raise(rb_eRuntimeError, "invalid switch in RUBYOPT: --%s", s);
	    break;

	  case 0:
	    break;
#	undef is_option_end
#	undef check_envopt
#	undef need_argument
#	undef is_option_with_arg
#	undef is_option_with_optarg
	}
    }

  switch_end:
    if (warning) opt->warning = warning;
    return argc0 - argc;
}

static void
ruby_init_prelude(void)
{
    Init_prelude();
    rb_const_remove(rb_cObject, rb_intern_const("TMP_RUBY_PREFIX"));
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

static VALUE
process_options(int argc, char **argv, ruby_cmdline_options_t *opt)
{
    rb_ast_t *ast = 0;
    VALUE parser;
    VALUE script_name;
    const rb_iseq_t *iseq;
    rb_encoding *enc, *lenc;
#if UTF8_PATH
    rb_encoding *uenc, *ienc = 0;
#endif
    const char *s;
    char fbuf[MAXPATHLEN];
    int i = (int)proc_options(argc, argv, opt, 0);
    unsigned int dump = opt->dump & dump_exit_bits;

    if (opt->dump & (DUMP_BIT(usage)|DUMP_BIT(help))) {
	const char *const progname =
	    (argc > 0 && argv && argv[0] ? argv[0] :
	     origarg.argc > 0 && origarg.argv && origarg.argv[0] ? origarg.argv[0] :
	     ruby_engine);
	usage(progname, (opt->dump & DUMP_BIT(help)));
	return Qtrue;
    }

    argc -= i;
    argv += i;

    if ((opt->features.set & FEATURE_BIT(rubyopt)) &&
	opt->safe_level == 0 && (s = getenv("RUBYOPT"))) {
	VALUE src_enc_name = opt->src.enc.name;
	VALUE ext_enc_name = opt->ext.enc.name;
	VALUE int_enc_name = opt->intern.enc.name;
        ruby_features_t feat = opt->features;

	opt->src.enc.name = opt->ext.enc.name = opt->intern.enc.name = 0;
	moreswitches(s, opt, 1);
	if (src_enc_name)
	    opt->src.enc.name = src_enc_name;
	if (ext_enc_name)
	    opt->ext.enc.name = ext_enc_name;
	if (int_enc_name)
	    opt->intern.enc.name = int_enc_name;
        FEATURE_SET_TO(opt->features, feat.mask, feat.set & feat.mask);
    }

    if (opt->src.enc.name)
	rb_warning("-K is specified; it is for 1.8 compatibility and may cause odd behavior");

#if USE_MJIT
    if (opt->features.set & FEATURE_BIT(jit)) {
        opt->mjit.on = TRUE; /* set mjit.on for ruby_show_version() API and check to call mjit_init() */
    }
#endif
    if (opt->dump & (DUMP_BIT(version) | DUMP_BIT(version_v))) {
#if USE_MJIT
        mjit_opts.on = opt->mjit.on; /* used by ruby_show_version(). mjit_init() still can't be called here. */
#endif
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
		char *path = getenv("RUBYPATH");

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

#if _WIN32
    translit_char_bin(RSTRING_PTR(opt->script_name), '\\', '/');
#elif defined DOSISH
    translit_char(RSTRING_PTR(opt->script_name), '\\', '/');
#endif

    ruby_gc_set_params(opt->safe_level);
    ruby_init_loadpath_safe(opt->safe_level);

#if USE_MJIT
    if (opt->mjit.on)
        /* Using TMP_RUBY_PREFIX created by ruby_init_loadpath_safe(). */
        mjit_init(&opt->mjit);
#endif

    Init_ruby_description();
    Init_enc();
    lenc = rb_locale_encoding();
    rb_enc_associate(rb_progname, lenc);
    rb_obj_freeze(rb_progname);
    parser = rb_parser_new();
    if (opt->dump & DUMP_BIT(yydebug)) {
	rb_parser_set_yydebug(parser, Qtrue);
    }
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
	enc = lenc;
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
    script_name = opt->script_name;
    rb_enc_associate(opt->script_name,
		     IF_UTF8_PATH(uenc = rb_utf8_encoding(), lenc));
#if UTF8_PATH
    if (uenc != lenc) {
	opt->script_name = str_conv_enc(opt->script_name, uenc, lenc);
	opt->script = RSTRING_PTR(opt->script_name);
    }
#endif
    rb_obj_freeze(opt->script_name);
    if (IF_UTF8_PATH(uenc != lenc, 1)) {
	long i;
        rb_vm_t *vm = GET_VM();
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
	    path = rb_enc_associate(rb_str_dup(path), lenc);
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
    Init_ext();		/* load statically linked extensions before rubygems */
    if (opt->features.set & FEATURE_BIT(gems)) {
	rb_define_module("Gem");
        if (opt->features.set & FEATURE_BIT(did_you_mean)) {
	    rb_define_module("DidYouMean");
	}
    }
    ruby_init_prelude();
    if (opt->features.mask & COMPILATION_FEATURES) {
	VALUE option = rb_hash_new();
#define SET_COMPILE_OPTION(h, o, name) \
	rb_hash_aset((h), ID2SYM(rb_intern_const(#name)),		\
                     (FEATURE_SET_P(o->features, FEATURE_BIT(name)) ? Qtrue : Qfalse));
	SET_COMPILE_OPTION(option, opt, frozen_string_literal);
	SET_COMPILE_OPTION(option, opt, debug_frozen_string_literal);
	rb_funcallv(rb_cISeq, rb_intern_const("compile_option="), 1, &option);
#undef SET_COMPILE_OPTION
    }
    ruby_set_argv(argc, argv);
    process_sflag(&opt->sflag);

    rb_parser_set_context(parser, 0, TRUE);

    if (opt->e_script) {
	VALUE progname = rb_progname;
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
	if (!(opt->dump & ~DUMP_BIT(version_v))) {
	    ruby_set_script_name(opt->script_name);
	    require_libraries(&opt->req_list);
	}
        ruby_set_script_name(progname);
	rb_parser_set_options(parser, opt->do_print, opt->do_loop,
			      opt->do_line, opt->do_split);
	ast = rb_parser_compile_string(parser, opt->script, opt->e_script, 1);
    }
    else {
	VALUE f;
	f = open_load_file(script_name, &opt->xflag);
	ast = load_file(parser, opt->script_name, f, 1, opt);
    }
    ruby_set_script_name(opt->script_name);
    if (dump & DUMP_BIT(yydebug)) {
	dump &= ~DUMP_BIT(yydebug);
	if (!dump) return Qtrue;
    }

    if (opt->ext.enc.index >= 0) {
	enc = rb_enc_from_index(opt->ext.enc.index);
    }
    else {
	enc = lenc;
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

    if (!ast->body.root) {
	rb_ast_dispose(ast);
	return Qfalse;
    }

    process_sflag(&opt->sflag);
    opt->xflag = 0;

    if (dump & DUMP_BIT(syntax)) {
	printf("Syntax OK\n");
	dump &= ~DUMP_BIT(syntax);
	if (!dump) return Qtrue;
    }

    if (opt->do_loop) {
	rb_define_global_function("sub", rb_f_sub, -1);
	rb_define_global_function("gsub", rb_f_gsub, -1);
	rb_define_global_function("chop", rb_f_chop, 0);
	rb_define_global_function("chomp", rb_f_chomp, -1);
    }

    if (dump & (DUMP_BIT(parsetree)|DUMP_BIT(parsetree_with_comment))) {
	rb_io_write(rb_stdout, rb_parser_dump_tree(ast->body.root, dump & DUMP_BIT(parsetree_with_comment)));
	rb_io_flush(rb_stdout);
	dump &= ~DUMP_BIT(parsetree)&~DUMP_BIT(parsetree_with_comment);
	if (!dump) {
	    rb_ast_dispose(ast);
	    return Qtrue;
	}
    }

    {
	VALUE path = Qnil;
	if (!opt->e_script && strcmp(opt->script, "-")) {
	    path = rb_realpath_internal(Qnil, script_name, 1);
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
        GetBindingPtr(rb_const_get(rb_cObject, rb_intern("TOPLEVEL_BINDING")),
                      toplevel_binding);
        const struct rb_block *base_block = toplevel_context(toplevel_binding);
	iseq = rb_iseq_new_main(&ast->body, opt->script_name, path, vm_block_iseq(base_block));
	rb_ast_dispose(ast);
    }

    if (dump & DUMP_BIT(insns)) {
	rb_io_write(rb_stdout, rb_iseq_disasm((const rb_iseq_t *)iseq));
	rb_io_flush(rb_stdout);
	dump &= ~DUMP_BIT(insns);
	if (!dump) return Qtrue;
    }
    if (opt->dump & dump_exit_bits) return Qtrue;

    rb_define_readonly_boolean("$-p", opt->do_print);
    rb_define_readonly_boolean("$-l", opt->do_line);
    rb_define_readonly_boolean("$-a", opt->do_split);

    if ((rb_e_script = opt->e_script) != 0) {
        rb_gc_register_mark_object(opt->e_script);
    }

    rb_set_safe_level(opt->safe_level);

    {
        rb_execution_context_t *ec = GET_EC();

        if (opt->e_script) {
            /* -e */
            rb_exec_event_hook_script_compiled(ec, iseq, opt->e_script);
        }
        else {
            /* file */
            rb_exec_event_hook_script_compiled(ec, iseq, Qnil);
        }
    }
    return (VALUE)iseq;
}

#ifndef DOSISH
static void
warn_cr_in_shebang(const char *str, long len)
{
    if (str[len-1] == '\n' && str[len-2] == '\r') {
	rb_warn("shebang line ending with \\r may cause problems");
    }
}
#else
#define warn_cr_in_shebang(str, len) (void)0
#endif

struct load_file_arg {
    VALUE parser;
    VALUE fname;
    int script;
    ruby_cmdline_options_t *opt;
    VALUE f;
};

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
	if (!(opt->dump & ~DUMP_BIT(version_v))) {
	    ruby_set_script_name(opt->script_name);
	    require_libraries(&opt->req_list);	/* Why here? unnatural */
	}
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
#if defined O_NONBLOCK && HAVE_FCNTL && !(O_NONBLOCK & O_ACCMODE)
	/* TODO: fix conflicting O_NONBLOCK in ruby/win32.h */
# define MODE_TO_LOAD (O_RDONLY | O_NONBLOCK)
#elif defined O_NDELAY && HAVE_FCNTL && !(O_NDELAY & O_ACCMODE)
# define MODE_TO_LOAD (O_RDONLY | O_NDELAY)
#else
# define MODE_TO_LOAD (O_RDONLY)
#endif
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

#if defined HAVE_FCNTL && MODE_TO_LOAD != O_RDONLY
	/* disabling O_NONBLOCK */
	if (fcntl(fd, F_SETFL, 0) < 0) {
	    e = errno;
	    (void)close(fd);
	    rb_load_fail(fname_v, strerror(e));
	}
#endif

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
	    rb_thread_wait_fd(fd);
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
    VALUE f = open_load_file(fname_v, &cmdline_options_init(&opt)->xflag);
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
    OBJ_TAINT_RAW(str);
    return str;
#else
    return rb_external_str_new_cstr(p);
#endif
}

/*! Sets the current script name to this value.
 *
 * This is similar to <code>$0 = name</code> in Ruby level but also affects
 * <code>Method#location</code> and others.
 */
void
ruby_script(const char *name)
{
    if (name) {
	rb_orig_progname = rb_progname = external_str_new_cstr(name);
	rb_vm_set_progname(rb_progname);
    }
}

/*! Sets the current script name to this value.
 *
 * Same as ruby_script() but accepts a VALUE.
 */
void
ruby_set_script_name(VALUE name)
{
    rb_orig_progname = rb_progname = rb_str_dup(name);
    rb_vm_set_progname(rb_progname);
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
    if (uid && opt->setids) {
	if (opt->safe_level < 1) opt->safe_level = 1;
    }
}

#undef forbid_setid
static void
forbid_setid(const char *s, const ruby_cmdline_options_t *opt)
{
    if (opt->setids & 1)
        rb_raise(rb_eSecurityError, "no %s allowed while running setuid", s);
    if (opt->setids & 2)
        rb_raise(rb_eSecurityError, "no %s allowed while running setgid", s);
    if (opt->safe_level > 0)
        rb_raise(rb_eSecurityError, "no %s allowed in tainted mode", s);
}

static void
verbose_setter(VALUE val, ID id, VALUE *variable)
{
    *variable = RTEST(val) ? Qtrue : val;
}

static VALUE
opt_W_getter(ID id, VALUE *variable)
{
    switch (*variable) {
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

/*! Defines built-in variables */
void
ruby_prog_init(void)
{
    rb_define_hooked_variable("$VERBOSE", &ruby_verbose, 0, verbose_setter);
    rb_define_hooked_variable("$-v", &ruby_verbose, 0, verbose_setter);
    rb_define_hooked_variable("$-w", &ruby_verbose, 0, verbose_setter);
    rb_define_hooked_variable("$-W", &ruby_verbose, opt_W_getter, rb_gvar_readonly_setter);
    rb_define_variable("$DEBUG", &ruby_debug);
    rb_define_variable("$-d", &ruby_debug);

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

#if defined(USE_DLN_A_OUT)
    if (origarg.argc > 0 && origarg.argv)
	dln_argv0 = origarg.argv[0];
    else if (argc > 0 && argv)
	dln_argv0 = argv[0];
#endif
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

    if (!origarg.argv || origarg.argc <= 0) {
	origarg.argc = argc;
	origarg.argv = argv;
    }
    ruby_script(script_name);  /* for the time being */
    rb_argv0 = rb_str_new4(rb_progname);
    rb_gc_register_mark_object(rb_argv0);
    iseq = process_options(argc, argv, cmdline_options_init(&opt));

#ifndef HAVE_SETPROCTITLE
    ruby_init_setproctitle(argc, argv);
#endif

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

/*! Initializes the process for libruby.
 *
 * This function assumes this process is ruby(1) and it has just started.
 * Usually programs that embed CRuby interpreter may not call this function,
 * and may do their own initialization.
 * argc and argv cannot be NULL.
 */
void
ruby_sysinit(int *argc, char ***argv)
{
#if defined(_WIN32)
    rb_w32_sysinit(argc, argv);
#endif
    if (*argc >= 0 && *argv) {
	origarg.argc = *argc;
	origarg.argv = *argv;
#if defined(USE_DLN_A_OUT)
	dln_argv0 = origarg.argv[0];
#endif
    }
    fill_standard_fds();
}
