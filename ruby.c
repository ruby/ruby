/**********************************************************************

  ruby.c -

  $Author$
  $Date$
  created at: Tue Aug 10 12:47:31 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto
  Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
  Copyright (C) 2000  Information-technology Promotion Agency, Japan

**********************************************************************/

#ifdef __CYGWIN__
#include <windows.h>
#include <sys/cygwin.h>
#endif
#ifdef _WIN32_WCE
#include <winsock.h>
#include "ruby/wince.h"
#endif
#include "ruby/ruby.h"
#include "ruby/node.h"
#include "ruby/encoding.h"
#include "dln.h"
#include <stdio.h>
#include <sys/types.h>
#include <ctype.h>

#ifdef __hpux
#include <sys/pstat.h>
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

#include "ruby/util.h"

/* for gdb */
static const union {
    enum ruby_special_consts	special_consts;
    enum ruby_value_type	value_type;
    enum ruby_value_flags	value_flags;
    enum node_type		node_type;
    enum ruby_node_flags	node_flags;
} dummy_gdb_enums;

#ifndef HAVE_STDLIB_H
char *getenv();
#endif

/* TODO: move to VM */
VALUE ruby_debug = Qfalse;
VALUE ruby_verbose = Qfalse;
extern int ruby_yydebug;

char *ruby_inplace_mode = 0;

struct cmdline_options {
    int sflag, xflag;
    int do_loop, do_print;
    int do_check, do_line;
    int do_split, do_search;
    int usage;
    int version;
    int copyright;
    int verbose;
    int yydebug;
    char *script;
    VALUE e_script;
    int enc_index;
};

static NODE *load_file(VALUE, const char *, int, struct cmdline_options *);
static void forbid_setid(const char *);

static int {
    int argc;
    char **argv;
#if !defined(PSTAT_SETCMD) && !defined(HAVE_SETPROCTITLE)
    int len;
#endif
} origarg;

static void
usage(const char *name)
{
    /* This message really ought to be max 23 lines.
     * Removed -h because the user already knows that option. Others? */

    static const char *const usage_msg[] = {
	"-0[octal]       specify record separator (\\0, if no argument)",
	"-a              autosplit mode with -n or -p (splits $_ into $F)",
	"-c              check syntax only",
	"-Cdirectory     cd to directory, before executing your script",
	"-d              set debugging flags (set $DEBUG to true)",
	"-e 'command'    one line of script. Several -e's allowed. Omit [programfile]",
	"-Fpattern       split() pattern for autosplit (-a)",
	"-i[extension]   edit ARGV files in place (make backup if extension supplied)",
	"-Idirectory     specify $LOAD_PATH directory (may be used more than once)",
	"-Kkcode         specifies KANJI (Japanese) code-set",
	"-l              enable line ending processing",
	"-n              assume 'while gets(); ... end' loop around your script",
	"-p              assume loop like -n but print line also like sed",
	"-rlibrary       require the library, before executing your script",
	"-s              enable some switch parsing for switches after script name",
	"-S              look for the script using PATH environment variable",
	"-T[level]       turn on tainting checks",
	"-v              print version number, then turn on verbose mode",
	"-w              turn warnings on for your script",
	"-W[level]       set warning level; 0=silence, 1=medium, 2=verbose (default)",
	"-x[directory]   strip off text before #!ruby line and perhaps cd to directory",
	"--copyright     print the copyright",
	"--version       print the version",
	NULL
    };
    const char *const *p = usage_msg;

    printf("Usage: %s [switches] [--] [programfile] [arguments]\n", name);
    while (*p)
	printf("  %s\n", *p++);
}

extern VALUE rb_load_path;

#ifndef CharNext		/* defined as CharNext[AW] on Windows. */
#define CharNext(p) ((p) + mblen(p, RUBY_MBCHAR_MAXSIZE))
#endif

#if defined DOSISH || defined __CYGWIN__
static inline void
translate_char(char *p, int from, int to)
{
    while (*p) {
	if ((unsigned char)*p == from)
	    *p = to;
	p = CharNext(p);
    }
}
#endif

#if defined _WIN32 || defined __CYGWIN__ || defined __DJGPP__
static VALUE
rubylib_mangled_path(const char *s, unsigned int l)
{
    static char *newp, *oldp;
    static int newl, oldl, notfound;
    char *ptr;
    VALUE ret;

    if (!newp && !notfound) {
	newp = getenv("RUBYLIB_PREFIX");
	if (newp) {
	    oldp = newp = strdup(newp);
	    while (*newp && !ISSPACE(*newp) && *newp != ';') {
		newp = CharNext(newp);	/* Skip digits. */
	    }
	    oldl = newp - oldp;
	    while (*newp && (ISSPACE(*newp) || *newp == ';')) {
		newp = CharNext(newp);	/* Skip whitespace. */
	    }
	    newl = strlen(newp);
	    if (newl == 0 || oldl == 0) {
		rb_fatal("malformed RUBYLIB_PREFIX");
	    }
	    translate_char(newp, '\\', '/');
	}
	else {
	    notfound = 1;
	}
    }
    if (!newp || l < oldl || strncasecmp(oldp, s, oldl) != 0) {
	return rb_str_new(s, l);
    }
    ret = rb_str_new(0, l + newl - oldl);
    ptr = RSTRING_PTR(ret);
    memcpy(ptr, newp, newl);
    memcpy(ptr + newl, s + oldl, l - oldl);
    ptr[l + newl - oldl] = 0;
    return ret;
}

static VALUE
rubylib_mangled_path2(const char *s)
{
    return rubylib_mangled_path(s, strlen(s));
}
#else
#define rubylib_mangled_path rb_str_new
#define rubylib_mangled_path2 rb_str_new2
#endif

static void
push_include(const char *path, VALUE (*filter)(VALUE))
{
    const char sep = PATH_SEP_CHAR;
    const char *p, *s;

    p = path;
    while (*p) {
	while (*p == sep)
	    p++;
	if (!*p) break;
	for (s = p; *s && *s != sep; s = CharNext(s));
	rb_ary_push(rb_load_path, (*filter)(rubylib_mangled_path(p, s - p)));
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
	if (cygwin_conv_to_posix_path(p, rubylib) == 0)
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

void
ruby_incpush(const char *path)
{
    ruby_push_include(path, identical_path);
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

#if defined DOSISH || defined __CYGWIN__
#define LOAD_RELATIVE 1
#endif

#if defined _WIN32 || defined __CYGWIN__
static HMODULE libruby;

BOOL WINAPI
DllMain(HINSTANCE dll, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH)
	libruby = dll;
    return TRUE;
}
#endif

void
ruby_init_loadpath(void)
{
#if defined LOAD_RELATIVE
    char libpath[MAXPATHLEN + 1];
    char *p;
    int rest;

#if defined _WIN32 || defined __CYGWIN__
    GetModuleFileName(libruby, libpath, sizeof libpath);
#elif defined(DJGPP)
    extern char *__dos_argv0;
    strncpy(libpath, __dos_argv0, sizeof(libpath) - 1);
#elif defined(__human68k__)
    extern char **_argv;
    strncpy(libpath, _argv[0], sizeof(libpath) - 1);
#elif defined(__EMX__)
    _execname(libpath, sizeof(libpath) - 1);
#endif

    libpath[sizeof(libpath) - 1] = '\0';
#if defined DOSISH
    translate_char(libpath, '\\', '/');
#elif defined __CYGWIN__
    {
	char rubylib[FILENAME_MAX];
	cygwin_conv_to_posix_path(libpath, rubylib);
	strncpy(libpath, rubylib, sizeof(libpath));
    }
#endif
    p = strrchr(libpath, '/');
    if (p) {
	*p = 0;
	if (p - libpath > 3 && !strcasecmp(p - 4, "/bin")) {
	    p -= 4;
	    *p = 0;
	}
    }
    else {
	strcpy(libpath, ".");
	p = libpath + 1;
    }

    rest = sizeof(libpath) - 1 - (p - libpath);

#define RUBY_RELATIVE(path) (strncpy(p, (path), rest), libpath)
#else
#define RUBY_RELATIVE(path) (path)
#endif
#define incpush(path) rb_ary_push(rb_load_path, rubylib_mangled_path2(path))

    if (rb_safe_level() == 0) {
	ruby_incpush(getenv("RUBYLIB"));
    }

#ifdef RUBY_SEARCH_PATH
    incpush(RUBY_RELATIVE(RUBY_SEARCH_PATH));
#endif

    incpush(RUBY_RELATIVE(RUBY_SITE_LIB2));
#ifdef RUBY_SITE_THIN_ARCHLIB
    incpush(RUBY_RELATIVE(RUBY_SITE_THIN_ARCHLIB));
#endif
    incpush(RUBY_RELATIVE(RUBY_SITE_ARCHLIB));
    incpush(RUBY_RELATIVE(RUBY_SITE_LIB));

    incpush(RUBY_RELATIVE(RUBY_LIB));
#ifdef RUBY_THIN_ARCHLIB
    incpush(RUBY_RELATIVE(RUBY_THIN_ARCHLIB));
#endif
    incpush(RUBY_RELATIVE(RUBY_ARCHLIB));

    if (rb_safe_level() == 0) {
	incpush(".");
    }
}

struct req_list {
    char *name;
    struct req_list *next;
};
static struct {
    struct req_list *last, head;
} req_list = {&req_list.head,};

static void
add_modules(const char *mod)
{
    struct req_list *list;

    list = ALLOC(struct req_list);
    list->name = ALLOC_N(char, strlen(mod) + 1);
    strcpy(list->name, mod);
    list->next = 0;
    req_list.last->next = list;
    req_list.last = list;
}

extern void Init_ext(void);

static void
require_libraries(void)
{
    struct req_list *list = req_list.head.next;
    struct req_list *tmp;

    Init_ext();		/* should be called here for some reason :-( */
    req_list.last = 0;
    while (list) {
	int state;

	rb_protect((VALUE (*)(VALUE))rb_require, (VALUE)list->name, &state);
	if (state)
	    rb_jump_tag(state);
	tmp = list->next;
	free(list->name);
	free(list);
	list = tmp;
    }
    req_list.head.next = 0;
}

static void
process_sflag(struct cmdline_options *opt)
{
    if (opt->sflag) {
	long n;
	VALUE *args;

	n = RARRAY_LEN(rb_argv);
	args = RARRAY_PTR(rb_argv);
	while (n > 0) {
	    VALUE v = *args++;
	    char *s = StringValuePtr(v);
	    char *p;
	    int hyphen = Qfalse;

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
		    hyphen = Qtrue;
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
	n = RARRAY_LEN(rb_argv) - n;
	while (n--) {
	    rb_ary_shift(rb_argv);
	}
    }
    opt->sflag = 0;
}

NODE *rb_parser_append_print(VALUE, NODE *);
NODE *rb_parser_while_loop(VALUE, NODE *, int, int);
static int proc_options(int argc, char **argv, struct cmdline_options *opt);

static char *
moreswitches(const char *s, struct cmdline_options *opt)
{
    int argc;
    char *argv[3];
    const char *p = s;

    argc = 2;
    argv[0] = argv[2] = 0;
    while (*s && !ISSPACE(*s))
	s++;
    argv[1] = ALLOCA_N(char, s - p + 2);
    argv[1][0] = '-';
    strncpy(argv[1] + 1, p, s - p);
    argv[1][s - p + 1] = '\0';
    proc_options(argc, argv, opt);
    while (*s && ISSPACE(*s))
	s++;
    return (char *)s;
}

static int
proc_options(int argc, char **argv, struct cmdline_options *opt)
{
    int argc0 = argc;
    const char *s;

    if (argc == 0)
	return 0;

    for (argc--, argv++; argc > 0; argc--, argv++) {
	if (argv[0][0] != '-' || !argv[0][1])
	    break;

	s = argv[0] + 1;
      reswitch:
	switch (*s) {
	  case 'a':
	    opt->do_split = Qtrue;
	    s++;
	    goto reswitch;

	  case 'p':
	    opt->do_print = Qtrue;
	    /* through */
	  case 'n':
	    opt->do_loop = Qtrue;
	    s++;
	    goto reswitch;

	  case 'd':
	    ruby_debug = Qtrue;
	    ruby_verbose = Qtrue;
	    s++;
	    goto reswitch;

	  case 'y':
	    ruby_yydebug = 1;
	    s++;
	    goto reswitch;

	  case 'v':
	    if (opt->verbose) {
		s++;
		goto reswitch;
	    }
	    ruby_show_version();
	    opt->verbose = 1;
	  case 'w':
	    ruby_verbose = Qtrue;
	    s++;
	    goto reswitch;

	  case 'W':
	    {
		int numlen;
		int v = 2;	/* -W as -W2 */

		if (*++s) {
		    v = scan_oct(s, 1, &numlen);
		    if (numlen == 0)
			v = 1;
		    s += numlen;
		}
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
	    goto reswitch;

	  case 'c':
	    opt->do_check = Qtrue;
	    s++;
	    goto reswitch;

	  case 's':
	    forbid_setid("-s");
	    opt->sflag = 1;
	    s++;
	    goto reswitch;

	  case 'h':
	    usage(origarg.argv[0]);
	    exit(0);

	  case 'l':
	    opt->do_line = Qtrue;
	    rb_output_rs = rb_rs;
	    s++;
	    goto reswitch;

	  case 'S':
	    forbid_setid("-S");
	    opt->do_search = Qtrue;
	    s++;
	    goto reswitch;

	  case 'e':
	    forbid_setid("-e");
	    if (!*++s) {
		s = argv[1];
		argc--, argv++;
	    }
	    if (!s) {
		rb_raise(rb_eRuntimeError, "no code specified for -e");
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
		add_modules(s);
	    }
	    else if (argv[1]) {
		add_modules(argv[1]);
		argc--, argv++;
	    }
	    break;

	  case 'i':
	    forbid_setid("-i");
	    if (ruby_inplace_mode)
		free(ruby_inplace_mode);
	    ruby_inplace_mode = strdup(s + 1);
	    break;

	  case 'x':
	    opt->xflag = Qtrue;
	    s++;
	    if (*s && chdir(s) < 0) {
		rb_fatal("Can't chdir to %s", s);
	    }
	    break;

	  case 'C':
	  case 'X':
	    s++;
	    if (!*s) {
		s = argv[1];
		argc--, argv++;
	    }
	    if (!s || !*s) {
		rb_fatal("Can't chdir");
	    }
	    if (chdir(s) < 0) {
		rb_fatal("Can't chdir to %s", s);
	    }
	    break;

	  case 'F':
	    if (*++s) {
		rb_fs = rb_reg_new(rb_str_new2(s), 0);
	    }
	    break;

	  case 'K':
	    if (*++s) {
		rb_encoding *enc = 0;
#if 0
		if ((opt->enc_index = rb_enc_find_index(s)) >= 0) break;
#endif
		switch (*s) {
		  case 'E': case 'e':
		    enc = ONIG_ENCODING_EUC_JP;
		    break;
		  case 'S': case 's':
		    enc = ONIG_ENCODING_SJIS;
		    break;
		  case 'U': case 'u':
		    enc = ONIG_ENCODING_UTF8;
		    break;
		  case 'N': case 'n': case 'A': case 'a':
		    enc = ONIG_ENCODING_ASCII;
		    break;
		  default:
		    rb_raise(rb_eRuntimeError, "unknown encoding name - %s", s);
		}
		opt->enc_index = rb_enc_to_index(enc);
		s++;
	    }
	    goto reswitch;

	  case 'T':
	    {
		int numlen;
		int v = 1;

		if (*++s) {
		    v = scan_oct(s, 2, &numlen);
		    if (numlen == 0)
			v = 1;
		    s += numlen;
		}
		rb_set_safe_level(v);
	    }
	    goto reswitch;

	  case 'I':
	    forbid_setid("-I");
	    if (*++s)
		ruby_incpush_expand(s);
	    else if (argv[1]) {
		ruby_incpush_expand(argv[1]);
		argc--, argv++;
	    }
	    break;

	  case '0':
	    {
		int numlen;
		int v;
		char c;

		v = scan_oct(s, 4, &numlen);
		s += numlen;
		if (v > 0377)
		    rb_rs = Qnil;
		else if (v == 0 && numlen >= 2) {
		    rb_rs = rb_str_new2("\n\n");
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
	    if (strcmp("copyright", s) == 0)
		opt->copyright = 1;
	    else if (strcmp("debug", s) == 0) {
		ruby_debug = Qtrue;
                ruby_verbose = Qtrue;
            }
	    else if (strcmp("version", s) == 0)
		opt->version = 1;
	    else if (strcmp("verbose", s) == 0) {
		opt->verbose = 1;
		ruby_verbose = Qtrue;
	    }
	    else if (strcmp("yydebug", s) == 0)
		ruby_yydebug = 1;
	    else if (strcmp("help", s) == 0) {
		usage(origarg.argv[0]);
		exit(0);
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
		const char *format;
		if (ISPRINT(*s)) {
		    format =
			"invalid option -%c  (-h will show valid options)";
		}
		else {
		    format =
			"invalid option -\\%03o  (-h will show valid options)";
		}
		rb_raise(rb_eRuntimeError, format, (int)(unsigned char)*s);
	    }
	    goto switch_end;

	  case 0:
	    break;
	}
    }

  switch_end:
    return argc0 - argc;
}

static NODE *
process_options(int argc, char **argv, struct cmdline_options *opt)
{
    NODE *tree = 0;
    VALUE parser;
    const char *s;
    int i = proc_options(argc, argv, opt);

    argc -= i;
    argv += i;

    if (rb_safe_level() == 0 && (s = getenv("RUBYOPT"))) {
	while (ISSPACE(*s))
	    s++;
	if (*s == 'T' || (*s == '-' && *(s + 1) == 'T')) {
	    int numlen;
	    int v = 1;

	    if (*s != 'T')
		++s;
	    if (*++s) {
		v = scan_oct(s, 2, &numlen);
		if (numlen == 0)
		    v = 1;
	    }
	    rb_set_safe_level(v);
	}
	else {
	    while (s && *s) {
		if (*s == '-') {
		    s++;
		    if (ISSPACE(*s)) {
			do {
			    s++;
			} while (ISSPACE(*s));
			continue;
		    }
		}
		if (!*s)
		    break;
		if (!strchr("IdvwWrK", *s))
		    rb_raise(rb_eRuntimeError,
			     "illegal switch in RUBYOPT: -%c", *s);
		s = moreswitches(s, opt);
	    }
	}
    }

    if (opt->version) {
	ruby_show_version();
	exit(0);
    }
    if (opt->copyright) {
	ruby_show_copyright();
    }

    if (rb_safe_level() >= 4) {
	OBJ_TAINT(rb_argv);
	OBJ_TAINT(rb_load_path);
    }

    if (!opt->e_script) {
	if (argc == 0) {	/* no more args */
	    if (opt->verbose)
		return 0;
	    opt->script = "-";
	}
	else {
	    opt->script = argv[0];
	    if (opt->script[0] == '\0') {
		opt->script = "-";
	    }
	    else if (opt->do_search) {
		char *path = getenv("RUBYPATH");

		opt->script = 0;
		if (path) {
		    opt->script = dln_find_file(argv[0], path);
		}
		if (!opt->script) {
		    opt->script = dln_find_file(argv[0], getenv(PATH_ENV));
		}
		if (!opt->script)
		    opt->script = argv[0];
	    }
#if defined DOSISH || defined __CYGWIN__
	    /* assume that we can change argv[n] if never change its length. */
	    translate_char(opt->script, '\\', '/');
#endif
	    argc--;
	    argv++;
	}
    }

    ruby_script(opt->script);
    ruby_set_argv(argc, argv);
    process_sflag(opt);

    ruby_init_loadpath();
    parser = rb_parser_new();
    if (opt->e_script) {
	rb_enc_associate_index(opt->e_script, opt->enc_index);
	require_libraries();
	tree = rb_parser_compile_string(parser, opt->script, opt->e_script, 1);
    }
    else {
	if (opt->script[0] == '-' && !opt->script[1]) {
	    forbid_setid("program input from stdin");
	}
	tree = load_file(parser, opt->script, 1, opt);
    }

    if (!tree) return 0;

    process_sflag(opt);
    opt->xflag = 0;

    if (rb_safe_level() >= 4) {
	FL_UNSET(rb_argv, FL_TAINT);
	FL_UNSET(rb_load_path, FL_TAINT);
    }

    if (tree) {
	if (opt->do_print) {
	    tree = rb_parser_append_print(parser, tree);
	}
	if (opt->do_loop) {
	    tree = rb_parser_while_loop(parser, tree, opt->do_line, opt->do_split);
	}
    }

    return tree;
}

static NODE *
load_file(VALUE parser, const char *fname, int script, struct cmdline_options *opt)
{
    extern VALUE rb_stdin;
    VALUE f;
    int line_start = 1;
    NODE *tree = 0;

    if (!fname)
	rb_load_fail(fname);
    if (strcmp(fname, "-") == 0) {
	f = rb_stdin;
    }
    else {
	int fd, mode = O_RDONLY;
#if defined DOSISH || defined __CYGWIN__
	{
	    const char *ext = strrchr(fname, '.');
	    if (ext && strcasecmp(ext, ".exe") == 0)
		mode |= O_BINARY;
	}
#endif
	if ((fd = open(fname, mode)) < 0) {
	    rb_load_fail(fname);
	}

	f = rb_io_fdopen(fd, mode, fname);
    }

    if (script) {
	VALUE c = 1;		/* something not nil */
	VALUE line;
	char *p;

	if (opt->xflag) {
	    forbid_setid("-x");
	    opt->xflag = Qfalse;
	    while (!NIL_P(line = rb_io_gets(f))) {
		line_start++;
		if (RSTRING_LEN(line) > 2
		    && RSTRING_PTR(line)[0] == '#'
		    && RSTRING_PTR(line)[1] == '!') {
		    if ((p = strstr(RSTRING_PTR(line), "ruby")) != 0) {
			goto start_read;
		    }
		}
	    }
	    rb_raise(rb_eLoadError, "no Ruby script found in input");
	}

	c = rb_io_getbyte(f);
	if (c == INT2FIX('#')) {
	    c = rb_io_getbyte(f);
	    if (c == INT2FIX('!')) {
		line = rb_io_gets(f);
		if (NIL_P(line))
		    return 0;

		if ((p = strstr(RSTRING_PTR(line), "ruby")) == 0) {
		    /* not ruby script, kick the program */
		    char **argv;
		    char *path;
		    char *pend = RSTRING_PTR(line) + RSTRING_LEN(line);

		    p = RSTRING_PTR(line);	/* skip `#!' */
		    if (pend[-1] == '\n')
			pend--;	/* chomp line */
		    if (pend[-1] == '\r')
			pend--;
		    *pend = '\0';
		    while (p < pend && ISSPACE(*p))
			p++;
		    path = p;	/* interpreter path */
		    while (p < pend && !ISSPACE(*p))
			p++;
		    *p++ = '\0';
		    if (p < pend) {
			argv = ALLOCA_N(char *, origarg.argc + 3);
			argv[1] = p;
			MEMCPY(argv + 2, origarg.argv + 1, char *, origarg.argc);
		    }
		    else {
			argv = origarg.argv;
		    }
		    argv[0] = path;
		    execv(path, argv);

		    rb_fatal("Can't exec %s", path);
		}

	      start_read:
		p += 4;
		RSTRING_PTR(line)[RSTRING_LEN(line) - 1] = '\0';
		if (RSTRING_PTR(line)[RSTRING_LEN(line) - 2] == '\r')
		    RSTRING_PTR(line)[RSTRING_LEN(line) - 2] = '\0';
		if ((p = strstr(p, " -")) != 0) {
		    p++;	/* skip space before `-' */
		    while (*p == '-') {
			p = moreswitches(p + 1, opt);
		    }
		}

		/* push back shebang for pragma may exist in next line */
		rb_io_ungetc(f, rb_str_new2("!\n"));
	    }
	    else if (!NIL_P(c)) {
		rb_io_ungetc(f, c);
	    }
	    rb_io_ungetc(f, INT2FIX('#'));
	}
	else if (!NIL_P(c)) {
	    rb_io_ungetc(f, c);
	}
	require_libraries();	/* Why here? unnatural */
    }
    rb_enc_associate_index(f, opt->enc_index);
    parser = rb_parser_new();
    tree = (NODE *)rb_parser_compile_file(parser, fname, f, line_start);
    if (script && rb_parser_end_seen_p(parser)) {
	rb_define_global_const("DATA", f);
    }
    else if (f != rb_stdin) {
	rb_io_close(f);
    }
    return tree;
}

void *
rb_load_file(const char *fname)
{
    struct cmdline_options opt;

    MEMZERO(&opt, opt, 1);
    return load_file(rb_parser_new(), fname, 0, &opt);
}

VALUE rb_progname;
VALUE rb_argv;
VALUE rb_argv0;

#if !defined(PSTAT_SETCMD) && !defined(HAVE_SETPROCTITLE)
#if !defined(_WIN32) && !(defined(HAVE_SETENV) && defined(HAVE_UNSETENV))
#define USE_ENVSPACE_FOR_ARG0
#endif

#ifdef USE_ENVSPACE_FOR_ARG0
extern char **environ;
#endif

static int
get_arglen(int argc, char **argv)
{
    char *s = argv[0];
    int i;

    s += strlen(s);
    /* See if all the arguments are contiguous in memory */
    for (i = 1; i < argc; i++) {
	if (argv[i] == s + 1) {
	    s++;
	    s += strlen(s);	/* this one is ok too */
	}
	else {
	    break;
	}
    }
#if defined(USE_ENVSPACE_FOR_ARG0)
    if (environ && (s == environ[0])) {
	s += strlen(s);
	for (i = 1; environ[i]; i++) {
	    if (environ[i] == s + 1) {
		s++;
		s += strlen(s);	/* this one is ok too */
	    }
	}
	ruby_setenv("", NULL); /* duplicate environ vars */
    }
#endif
    return s - argv[0];
}
#endif

static void
set_arg0(VALUE val, ID id)
{
    char *s;
    long i;

    if (origarg.argv == 0)
	rb_raise(rb_eRuntimeError, "$0 not initialized");
    StringValue(val);
    s = RSTRING_PTR(val);
    i = RSTRING_LEN(val);
#if defined(PSTAT_SETCMD)
    if (i > PST_CLEN) {
	union pstun un;
	char buf[PST_CLEN + 1];	/* PST_CLEN is 64 (HP-UX 11.23) */
	strncpy(buf, s, PST_CLEN);
	buf[PST_CLEN] = '\0';
	un.pst_command = buf;
	pstat(PSTAT_SETCMD, un, PST_CLEN, 0, 0);
    }
    else {
	union pstun un;
	un.pst_command = s;
	pstat(PSTAT_SETCMD, un, i, 0, 0);
    }
#elif defined(HAVE_SETPROCTITLE)
    setproctitle("%.*s", (int)i, s);
#else

    if (i >= origarg.len) {
	i = origarg.len;
    }

    memcpy(origarg.argv[0], s, i);
    s = origarg.argv[0] + i;
    *s = '\0';
    if (i + 1 < origarg.len) memset(s + 1, ' ', origarg.len - i - 1);
    {
	int j;
	for (j = 1; j < origarg.argc; j++)
	    origarg.argv[i] = s;
    }
#endif
    rb_progname = rb_tainted_str_new(s, i);
}

void
ruby_script(const char *name)
{
    if (name) {
	rb_progname = rb_tainted_str_new2(name);
    }
}

static int uid, euid, gid, egid;

static void
init_ids(void)
{
    uid = (int)getuid();
    euid = (int)geteuid();
    gid = (int)getgid();
    egid = (int)getegid();
#ifdef VMS
    uid |= gid << 16;
    euid |= egid << 16;
#endif
    if (uid && (euid != uid || egid != gid)) {
	rb_set_safe_level(1);
    }
}

static void
forbid_setid(const char *s)
{
    if (euid != uid)
        rb_raise(rb_eSecurityError, "no %s allowed while running setuid", s);
    if (egid != gid)
        rb_raise(rb_eSecurityError, "no %s allowed while running setgid", s);
    if (rb_safe_level() > 0)
        rb_raise(rb_eSecurityError, "no %s allowed in tainted mode", s);
}

static void
verbose_setter(VALUE val, ID id, VALUE *variable)
{
    ruby_verbose = RTEST(val) ? Qtrue : val;
}

static VALUE
opt_W_getter(VALUE val, ID id)
{
    if (ruby_verbose == Qnil)
	return INT2FIX(0);
    if (ruby_verbose == Qfalse)
	return INT2FIX(1);
    if (ruby_verbose == Qtrue)
	return INT2FIX(2);
    return Qnil;		/* not reached */
}

void
ruby_prog_init(void)
{
    init_ids();

    rb_define_hooked_variable("$VERBOSE", &ruby_verbose, 0, verbose_setter);
    rb_define_hooked_variable("$-v", &ruby_verbose, 0, verbose_setter);
    rb_define_hooked_variable("$-w", &ruby_verbose, 0, verbose_setter);
    rb_define_virtual_variable("$-W", opt_W_getter, 0);
    rb_define_variable("$DEBUG", &ruby_debug);
    rb_define_variable("$-d", &ruby_debug);

    rb_define_hooked_variable("$0", &rb_progname, 0, set_arg0);
    rb_define_hooked_variable("$PROGRAM_NAME", &rb_progname, 0, set_arg0);

    rb_define_readonly_variable("$*", &rb_argv);
    rb_argv = rb_ary_new();
    rb_define_global_const("ARGV", rb_argv);
    rb_global_variable(&rb_argv0);

#ifdef MSDOS
    /*
     * There is no way we can refer to them from ruby, so close them to save
     * space.
     */
    (void)fclose(stdaux);
    (void)fclose(stdprn);
#endif
}

void
ruby_set_argv(int argc, char **argv)
{
    int i;

#if defined(USE_DLN_A_OUT)
    if (origarg.argv)
	dln_argv0 = origarg.argv[0];
    else
	dln_argv0 = argv[0];
#endif
    rb_ary_clear(rb_argv);
    for (i = 0; i < argc; i++) {
	VALUE arg = rb_tainted_str_new2(argv[i]);

	OBJ_FREEZE(arg);
	rb_ary_push(rb_argv, arg);
    }
}

static VALUE
false_value(void)
{
    return Qfalse;
}

static VALUE
true_value(void)
{
    return Qtrue;
}

#define rb_define_readonly_boolean(name, val) \
    rb_define_virtual_variable((name), (val) ? true_value : false_value, 0)

void *
ruby_process_options(int argc, char **argv)
{
    struct cmdline_options opt;
    NODE *tree;

    origarg.argc = argc;
    origarg.argv = argv;

    MEMZERO(&opt, opt, 1);
    ruby_script(argv[0]);	/* for the time being */
    rb_argv0 = rb_progname;
#if defined(USE_DLN_A_OUT)
    dln_argv0 = argv[0];
#endif
#if !defined(PSTAT_SETCMD) && !defined(HAVE_SETPROCTITLE)
    origarg.len = get_arglen(origarg.argc, origarg.argv);
#endif
    tree = process_options(argc, argv, &opt);

    rb_define_readonly_boolean("$-p", opt.do_print);
    rb_define_readonly_boolean("$-l", opt.do_line);
    rb_define_readonly_boolean("$-a", opt.do_split);

    return tree;
}
