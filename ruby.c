/************************************************

  ruby.c -

  $Author: matz $
  $Date: 1995/01/10 10:42:51 $
  created at: Tue Aug 10 12:47:31 JST 1993

  Copyright (C) 1993-1995 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"
#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "dln.h"

#ifdef HAVE_STRING_H
# include <string.h>
#else
char *strchr();
char *strstr();
#endif

static int version, copyright;

int debug = 0;
int verbose = 0;
static int sflag = FALSE;

char *inplace = Qnil;
char *strdup();

extern int yydebug;
extern int nerrs;

int xflag = FALSE;

#ifdef USE_DL
char *rb_dln_argv0;
#endif

static void load_stdin();
static void load_file();

static int do_loop = FALSE, do_print = FALSE;
static int do_check = FALSE, do_line = FALSE;
static int do_split = FALSE;

static char *script;

static void
proc_options(argcp, argvp)
    int *argcp;
    char ***argvp;
{
    int argc = *argcp;
    char **argv = *argvp;
    int script_given, do_search;
    char *s;

    extern VALUE rb_load_path;
    extern VALUE RS, ORS, FS;

    if (argc == 0) return;

    version = FALSE;
    script_given = FALSE;
    do_search = FALSE;

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
	    verbose = TRUE;
	    show_version();
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
		lex_setsrc("-e", argv[1], strlen(argv[1]));
		argc--,argv++;
	    }
	    else {
		lex_setsrc("-e", "", 0);
	    }
	    yyparse();
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

	  case 'F':
	    FS = str_new2(s+1);
	    break;

	  case 'K':
	    s++;
	    rb_set_kanjicode(s);
	    s++;
	    goto reswitch;

	  case 'I':
	    ary_unshift(rb_load_path, str_new2(s+1));
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

	  case 'u':
	  case 'U':

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
		verbose = 1;
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
    if (*argvp[0] == Qnil) return;

    if (version) {
	show_version();
	exit(0);
    }
    if (copyright) {
	show_copyright();
    }

    rb_setup_kcode();

    if (script_given == 0) {
	if (argc == 0) {	/* no more args */
	    if (verbose) exit(0);
	    script = "-";
	    load_stdin();
	}
	else {
	    script = argv[0];
	    if (do_search) {
		script = dln_find_file(script, getenv("PATH"));
		if (!script) script = argv[0];
	    }
	    load_file(script, 1);
	    argc--,argv++;
	}
    }

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
		rb_gvar_set2((*argvp)[0], str_new2(s));
	    }
	    else {
		rb_gvar_set2((*argvp)[0], TRUE);
	    }
	}
	*argcp = argc; *argvp = argv;
    }

}

static void
readin(fd, fname, script)
    int fd;
    char *fname;
    int script;
{
    struct stat st;
    char *ptr, *p, *pend, *s;

    if (fstat(fd, &st) < 0) rb_sys_fail(fname);
    if (!S_ISREG(st.st_mode))
	Fail("script is not a regular file - %s", fname);

    p = ptr = ALLOC_N(char, st.st_size+1);
    if (read(fd, ptr, st.st_size) != st.st_size) {
	free(ptr);
	rb_sys_fail(fname);
    }
    pend = p + st.st_size;
    *pend = '\0';

    if (script) {
	if (xflag) {
	    xflag = FALSE;
	    while (p < pend) {
		if (p[0] == '#' && p[1] == '!') {
		    char *s = p;
		    while (s < pend && *s != '\n') s++;
		    if (*s == '\n') {
			*s = '\0';
			if (strstr(p, "ruby")) {
			    *s = '\n';
			    goto start_read;
			}
		    }
		    p = s + 1;
		}
		else {
		    while (p < pend && *p++ != '\n')
			;
		    if (p >= pend) break;
		}
	    }
	    free(ptr);
	    Fail("No Ruby script found in input");
	}

      start_read:
	if (p[0] == '#' && p[1] == '!') {
	    char *s = p, *q;

	    while (s < pend && *s != '\n') s++;
	    if (*s == '\n') {
		*s = '\0';
		if (q = strstr(p, "ruby -")) {
		    int argc; char *argv[2]; char **argvp = argv;
		    argc = 2; argv[0] = Qnil; argv[1] = q + 5;
		    proc_options(&argc, &argvp);
		    p = s + 1;
		}
		else {
		    *s = '\n';
		}
	    }
	}
    }
    lex_setsrc(fname, p, pend - p);
    yyparse();
    free(ptr);
}

static void
load_file(fname, script)
    char *fname;
    int script;
{
    int fd;
    char *ptr;

    if (fname[0] == '\0') {
	load_stdin();
	return;
    }

    fd = open(fname, O_RDONLY, 0);
    if (fd < 0) rb_sys_fail(fname);
    readin(fd, fname, script);
    close(fd);
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
    char buf[32];
    FILE *f;
    char c;
    int fd;

    sprintf(buf, "/tmp/ruby-f%d", getpid());
    f = fopen(buf, "w");
    fd = open(buf, O_RDONLY, 0);
    if (fd < 0) rb_sys_fail(buf);
    unlink(buf);
    while ((c = getchar()) != EOF) {
	putc(c, f);
    }
    fclose(f);
    readin(fd, "-");
}

static VALUE Progname;
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

    rb_define_variable("$@", &errat, Qnil, Qnil, 0);
    errat = str_new2(argv[0]);
    rb_define_variable("$VERBOSE", &verbose, Qnil, Qnil, 0);
    rb_define_variable("$DEBUG", &debug, Qnil, Qnil, 0);

#ifdef USE_DL
    rb_dln_argv0 = argv[0];
#endif

    proc_options(&argc, &argv);
    if (do_check && nerrs == 0) {
	printf("Syntax OK\n");
	exit(0);
    }
    if (do_print) {
	yyappend_print();
    }
    if (do_loop) {
	yywhole_loop(do_line, do_split);
    }

    rb_define_variable("$0", &Progname, Qnil, set_arg0, 0);
    ruby_script(script);

    rb_define_variable("$ARGV", &Argv, Qnil, Qnil, 0);
    rb_define_variable("$*", &Argv, Qnil, Qnil, 0);
    Argv = ary_new2(argc);
    for (i=0; i < argc; i++) {
	ary_push(Argv, str_new2(argv[i]));
    }
}
