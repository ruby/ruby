/************************************************

  ruby.c -

  $Author: matz $
  $Date: 1996/12/25 10:42:51 $
  created at: Tue Aug 10 12:47:31 JST 1993

  Copyright (C) 1993-1996 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"
#include "dln.h"
#include <stdio.h>
#include <sys/types.h>
#include <fcntl.h>

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
char *strrchr();
char *strstr();
#endif

static int version, copyright;

int debug = FALSE;
int verbose = FALSE;
static int sflag = FALSE;

char *inplace = FALSE;
char *strdup();

extern int yydebug;
extern int nerrs;

static int xflag = FALSE;
extern VALUE RS, RS_default, ORS, FS;

static void load_stdin();
static void load_file();

static int do_loop = FALSE, do_print = FALSE;
static int do_check = FALSE, do_line = FALSE;
static int do_split = FALSE;

static char *script;

#ifndef RUBY_LIB
#if defined(MSDOS)
#define RUBY_LIB "/usr/local/lib/ruby;."
#else
#define RUBY_LIB "/usr/local/lib/ruby:."
#endif
#endif

#if defined(MSDOS)
#define RUBY_LIB_SEP ';'
#else
#define RUBY_LIB_SEP ':'
#endif

extern VALUE rb_load_path;
VALUE Frequire();

static void
addpath(path)
    char *path;
{
    char *p, *s;
    VALUE ary;

    if (path == 0) return;

    ary = ary_new();
    p = s = path;
    while (*p) {
	while (*p == RUBY_LIB_SEP) p++;
	if (s = strrchr(p, RUBY_LIB_SEP)) {
	    ary_push(ary, str_new(p, (int)(s-p)));
	    p = s + 1;
	}
	else {
	    ary_push(ary, str_new2(p));
	    break;
	}
    }
    rb_load_path = ary_plus(ary, rb_load_path);
}

static void
proc_options(argcp, argvp)
    int *argcp;
    char ***argvp;
{
    int argc = *argcp;
    char **argv = *argvp;
    int script_given, do_search;
    char *s;

    if (argc == 0) return;

    version = FALSE;
    do_search = FALSE;
    script_given = 0;

    for (argc--,argv++; argc > 0; argc--,argv++) {
	if (argv[0][0] != '-' || !argv[0][1]) break;

	s = argv[0]+1;
      reswitch:
	switch (*s) {
	  case 'a':
	    do_split = TRUE;
	    s++;
	    goto reswitch;

	  case 'p':
	    do_print = TRUE;
	    /* through */
	  case 'n':
	    do_loop = TRUE;
	    s++;
	    goto reswitch;

	  case 'd':
	    debug = TRUE;
	    s++;
	    goto reswitch;

	  case 'y':
	    yydebug = 1;
	    s++;
	    goto reswitch;

	  case 'v':
	    show_version();
	    verbose = 2;
	  case 'w':
	    verbose |= 1;
	    s++;
	    goto reswitch;

	  case 'c':
	    do_check = TRUE;
	    s++;
	    goto reswitch;

	  case 's':
	    sflag = TRUE;
	    s++;
	    goto reswitch;

	  case 'l':
	    do_line = TRUE;
	    ORS = RS;
	    s++;
	    goto reswitch;

	  case 'S':
	    do_search = TRUE;
	    s++;
	    goto reswitch;

	  case 'e':
	    script_given++;
	    if (script == 0) script = "-e";
	    if (argv[1]) {
		compile_string("-e", argv[1], strlen(argv[1]));
		argc--,argv++;
	    }
	    else {
		compile_string("-e", "", 0);
	    }
	    break;

	  case 'r':
	    if (*++s) {
		f_require(Qnil, str_new2(s));
	    }
	    else if (argv[1]) {
		f_require(Qnil, str_new2(argv[1]));
		argc--,argv++;
	    }
	    break;

	  case 'i':
	    inplace = strdup(s+1);
	    break;

	  case 'x':
	    xflag = TRUE;
	    s++;
	    if (*s && chdir(s) < 0) {
		Fatal("Can't chdir to %s", s);
	    }
	    break;

	  case 'X':
	    s++;
	    if (!*s) {
		s = argv[1];
		argc--,argv++;
	    }
	    if (*s && chdir(s) < 0) {
		Fatal("Can't chdir to %s", s);
	    }
	    break;

	  case 'F':
	    FS = str_new2(s+1);
	    break;

	  case 'K':
	    s++;
	    rb_set_kcode(s);
	    s++;
	    goto reswitch;

	  case 'I':
	    if (*++s)
		addpath(s);
	    else if (argv[1]) {
		addpath(argv[1]);
		argc--,argv++;
	    }
	    break;

	  case '0':
	    {
		int numlen;
		int v;
		char c;

		v = scan_oct(s, 4, &numlen);
		s += numlen;
		if (v > 0377) RS = Qnil;
		else if (v == 0 && numlen >= 2) {
		    RS = str_new2("\n\n");
		}
		else {
		    c = v & 0xff;
		    RS = str_new(&c, 1);
		}
	    }
	    goto reswitch;

	  case '-':
	    if (!s[1]) {
		argc--,argv++;
		goto switch_end;
	    }
	    s++;
	    if (strcmp("copyright", s) == 0)
		copyright = 1;
	    else if (strcmp("debug", s) == 0)
		debug = 1;
	    else if (strcmp("version", s) == 0)
		version = 1;
	    else if (strcmp("verbose", s) == 0)
		verbose = 2;
	    else if (strcmp("yydebug", s) == 0)
		yydebug = 1;
	    else {
		Fatal("Unrecognized long option: --%s",s);
	    }
	    break;

	  default:
	    Fatal("Unrecognized switch: -%s",s);

	  case 0:
	    break;
	}
    }

  switch_end:
    if (*argvp[0] == 0) return;

    if (version) {
	show_version();
	exit(0);
    }
    if (copyright) {
	show_copyright();
    }

    if (script_given == FALSE) {
	if (argc == 0) {	/* no more args */
	    if (verbose == 3) exit(0);
	    script = "-";
	    load_stdin();
	}
	else {
	    script = argv[0];
	    if (script[0] == '\0') {
		script = "-";
		load_stdin();
	    }
	    else {
		if (do_search) {
		    script = dln_find_file(script, getenv("PATH"));
		    if (!script) script = argv[0];
		}
		load_file(script, 1);
	    }
	    argc--; argv++;
	}
    }
    if (verbose) verbose = TRUE;

    xflag = FALSE;
    *argvp = argv;
    *argcp = argc;

    if (sflag) {
	char *s;

	argc = *argcp; argv = *argvp;
	for (; argc > 0 && argv[0][0] == '-'; argc--,argv++) {
	    if (argv[0][1] == '-') {
		argc--,argv++;
		break;
	    }
	    argv[0][0] = '$';
	    if (s = strchr(argv[0], '=')) {
		*s++ = '\0';
		rb_gvar_set2(argv[0], str_new2(s));
	    }
	    else {
		rb_gvar_set2(argv[0], TRUE);
	    }
	}
	*argcp = argc; *argvp = argv;
    }

}

static VALUE
open_to_load(fname)
    char *fname;
{
}

static void
load_file(fname, script)
    char *fname;
    int script;
{
    extern VALUE rb_stdin;
    VALUE f;
    int line_start = 1;

    if (strcmp(fname, "-") == 0) {
	f = rb_stdin;
    }
    else {
	f = file_open(fname, "r");
    }

    if (script) {
	VALUE c;
	VALUE line;
	VALUE rs = RS;

	RS = RS_default;
	if (xflag) {
	    xflag = FALSE;
	    while (!NIL_P(line = io_gets(f))) {
		line_start++;
		if (RSTRING(line)->len > 2
		    || RSTRING(line)->ptr[0] != '#'
		    || RSTRING(line)->ptr[1] != '!') {
		    if (strstr(RSTRING(line)->ptr, "ruby")) {
			goto start_read;
		    }
		}
	    }
	    RS = rs;
	    LoadError("No Ruby script found in input");
	}

	c = io_getc(f);
	if (c == INT2FIX('#')) {
	    line = io_gets(f);
	    line_start++;

	    if (RSTRING(line)->len > 2
		|| RSTRING(line)->ptr[0] != '#'
		|| RSTRING(line)->ptr[1] != '!') {

		char *p;

	      start_read:
		if (p = strstr(RSTRING(line)->ptr, "ruby -")) {
		    int argc; char *argv[2]; char **argvp = argv;
		    char *s;

		    s = RSTRING(line)->ptr;
		    while (isspace(*s++))
			;
		    *s = '\0';
		    RSTRING(line)->ptr[RSTRING(line)->len-1] = '\0';
		    if (RSTRING(line)->ptr[RSTRING(line)->len-2] == '\r')
			RSTRING(line)->ptr[RSTRING(line)->len-2] = '\0';
		    argc = 2; argv[0] = 0; argv[1] = p + 5;
		    proc_options(&argc, &argvp);
		}
	    }
	}
	else if (!NIL_P(c)) {
	    io_ungetc(f, c);
	}
	RS = rs;
    }
    compile_file(fname, f, line_start);
    if (f != rb_stdin) io_close(f);
}

void
rb_load_file(fname)
    char *fname;
{
    load_file(fname, 0);
}

static void
load_stdin()
{
    load_file("-", 1);
}

VALUE Progname;
VALUE Argv;

static int origargc;
static char **origargv, **origenvp;

static VALUE
set_arg0(val, id)
    VALUE val;
    ID id;
{
    char *s;
    int i;
    static int len;

    Check_Type(val, T_STRING);
    if (len == 0) {
	s = origargv[0];
	s += strlen(s);
	/* See if all the arguments are contiguous in memory */
	for (i = 1; i < origargc; i++) {
	    if (origargv[i] == s + 1)
		s += strlen(++s);	/* this one is ok too */
	}
	len = s - origargv[0];
    }
    s = RSTRING(val)->ptr;
    i = RSTRING(val)->len;
    if (i > len) {
	memcpy(origargv[0], s, len);
	origargv[0][len] = '\0';
    }
    else {
	memcpy(origargv[0], s, i);
	s = origargv[0]+i;
	*s++ = '\0';
	while (++i < len)
	    *s++ = ' ';
    }
    Progname = str_new2(origargv[0]);

    return val;
}

void
ruby_script(name)
    char *name;
{
    if (name) {
	Progname = str_new2(name);
    }
}

void
ruby_options(argc, argv, envp)
    int argc;
    char **argv, **envp;
{
    extern VALUE errat;
    int i;

    origargc = argc; origargv = argv; origenvp = envp;

    errat = str_new2(argv[0]);
    rb_define_variable("$VERBOSE", &verbose);
    rb_define_variable("$DEBUG", &debug);

    addpath(getenv("RUBYLIB"));
    addpath(RUBY_LIB);
#ifdef RUBY_ARCHLIB
    addpath(RUBY_ARCHLIB);
#endif
#if defined(USE_DLN_A_OUT)
    dln_argv0 = argv[0];
#endif

    rb_define_hooked_variable("$0", &Progname, 0, set_arg0);

    Argv = ary_new2(argc);
    rb_define_readonly_variable("$*", &Argv);
    rb_define_global_const("ARGV", Argv);

    proc_options(&argc, &argv);
    ruby_script(script);

    if (do_check && nerrs == 0) {
	printf("Syntax OK\n");
	exit(0);
    }
    if (do_print) {
	yyappend_print();
    }
    if (do_loop) {
	yywhile_loop(do_line, do_split);
    }

    for (i=0; i < argc; i++) {
	ary_push(Argv, str_new2(argv[i]));
    }
}
