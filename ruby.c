/************************************************

  ruby.c -

  $Author: matz $
  $Date: 1994/06/27 15:48:37 $
  created at: Tue Aug 10 12:47:31 JST 1993

  Copyright (C) 1994 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "re.h"
#include <stdio.h>
#include <sys/file.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <signal.h>

#ifdef HAVE_GETOPT_LONG
#include "getopt.h"
#else
#include "missing/getopt.h"
#endif

static struct option long_options[] =
{
    {"debug", 0, 0, 'd'},
    {"yydebug", 0, 0, 'y'},
    {"verbose", 0, 0, 'v'},
    {"version", 0, 0, 0},
    {0, 0, 0, 0}
};

int debug = 0;
int verbose = 0;
static int sflag = FALSE;

char *inplace = Qnil;
char *strdup();
char *strstr();
char *index();

extern int yydebug;
extern int nerrs;

int xflag = FALSE;

#ifdef USE_DLN
char *rb_dln_argv0;
#endif

static void load_stdin();
void rb_load_file();

static int do_loop = FALSE, do_print = FALSE;
static int do_check = FALSE, do_line = FALSE;
static int do_split = FALSE;

static char*
proc_options(argcp, argvp)
    int *argcp;
    char ***argvp;
{
    int argc = *argcp;
    char **argv = *argvp;
    extern VALUE rb_load_path;
    extern long reg_syntax;
    extern char *optarg;
    extern int optind;
    int c, i, j, script_given, version, opt_index;
    extern VALUE RS, ORS, FS;
    char *script;
    char *src;

    version = FALSE;
    script_given = FALSE;
    script = Qnil;

    optind = 0;
    while ((c = getopt_long(argc, argv, "+acde:F:i:I:lnpR:svxX:yNES",
			    long_options, &opt_index)) != EOF) {
	switch (c) {
	  case 0:		/* long options */
	    if (strcmp(long_options[opt_index].name, "version") == 0) {
		version = TRUE;
		show_version();
	    }
	    break;

	  case 'p':
	    do_print = TRUE;
	    /* through */
	  case 'n':
	    do_loop = TRUE;
	    break;

	  case 'd':
	    debug = TRUE;
	    break;

	  case 'y':
	    yydebug = 1;
	    break;

	  case 'v':
	    version = verbose = TRUE;
	    show_version();
	    break;

	  case 'e':
	    script_given++;
	    if (script == 0) script = "-e";
	    lex_setsrc("-e", optarg, strlen(optarg));
	    yyparse();
	    break;

	  case 'i':
	    inplace = strdup(optarg);
	    break;

	  case 'c':
	    do_check = TRUE;
	    break;

	  case 'x':
	    xflag = TRUE;
	    break;

	  case 'X':
	    if (chdir(optarg) < 0)
		Fatal("Can't chdir to %s", optarg);
	    break;

	  case 's':
	    sflag = TRUE;
	    break;

	  case 'l':
	    do_line = TRUE;
	    ORS = RS;
	    break;

	  case 'R':
	    {
		char *p = optarg;

		while (*p) {
		    if (*p < '0' || '7' < *p) {
			break;
		    }
		    p++;
		}
		if (*p) {
		    RS = str_new2(optarg);
		}
		else {
		    int i = strtoul(optarg, Qnil, 8);

		    if (i == 0) RS = str_new(0, 0);
		    else if (i > 0xff) RS = Qnil;
		    else {
			char c = i;
			RS = str_new(&c, 1);
		    }
		}
	    }
	    break;

	  case 'F':
	    FS = str_new2(optarg);
	    break;

	  case 'a':
	    do_split = TRUE;
	    break;

	  case 'N':
	    reg_syntax &= ~RE_MBCTYPE_MASK;
	    re_set_syntax(reg_syntax);
	    break;
	  case 'E':
	    reg_syntax &= ~RE_MBCTYPE_MASK;
	    reg_syntax |= RE_MBCTYPE_EUC;
	    re_set_syntax(reg_syntax);
	    break;
	  case 'S':
	    reg_syntax &= ~RE_MBCTYPE_MASK;
	    reg_syntax |= RE_MBCTYPE_SJIS;
	    re_set_syntax(reg_syntax);
	    break;

	  case 'I':
	    Fary_unshift(rb_load_path, str_new2(optarg));
	    break;

	  default:
	    break;
	}
    }

    if (argv[0] == Qnil) return Qnil;

    if (script_given == 0) {
	if (argc == optind) {	/* no more args */
	    if (version == TRUE) exit(0);
	    script = "-";
	    load_stdin();
	}
	else {
	    script = argv[optind];
	    rb_load_file(argv[optind]);
	    optind++;
	}
    }

    xflag = FALSE;
    *argvp += optind;
    *argcp -= optind;

    if (sflag) {
	char *s;
	VALUE v;

	argc = *argcp; argv = *argvp;
	for (; argc > 0 && argv[0][0] == '-'; argc--,argv++) {
	    if (argv[0][1] == '-') {
		argc--,argv++;
		break;
	    }
	    argv[0][0] = '$';
	    if (s = index(argv[0], '=')) {
		*s++ = '\0';
		GC_LINK;
		GC_PRO3(v, str_new2(s));
		rb_gvar_set2((*argvp)[0], v);
		GC_UNLINK;
	    }
	    else {
		rb_gvar_set2((*argvp)[0], TRUE);
	    }
	}
	*argcp = argc; *argvp = argv;
    }

    return script;
}

static void
readin(fd, fname)
    int fd;
    char *fname;
{
    struct stat st;
    char *ptr, *p, *pend;

    if (fstat(fd, &st) < 0) rb_sys_fail(fname);
    if (!S_ISREG(st.st_mode))
	Fail("script is not a regular file - %s", fname);

    p = ptr = ALLOC_N(char, st.st_size+1);
    if (read(fd, ptr, st.st_size) != st.st_size) {
	rb_sys_fail(fname);
    }
    p = ptr;
    pend = p + st.st_size;
    if (xflag) {
	char *s = p;

	*pend = '\0'; 
	xflag = FALSE;
	while (p < pend) {
	    while (s < pend && *s != '\n') s++;
	    if (*s != '\n') break;
	    *s = '\0';
	    if (p[0] == '#' && p[1] == '!' && strstr(p, "ruby")) {
		if (p = strstr(p, "ruby -")) {
		    int argc; char *argv[2]; char **argvp = argv;
		    argc = 2; argv[0] = Qnil; argv[1] = p + 5;
		    proc_options(&argc, &argvp);
		}
		xflag = TRUE;
		p = s + 1;
		goto start_read;
	    }
	    p = s + 1;
	}
	Fail("No Ruby script found in input");
    }
  start_read:
    lex_setsrc(fname, p, pend - p);
    yyparse();
    free(ptr);
}

void
rb_load_file(fname)
    char *fname;
{
    int fd;
    char *ptr;

    if (fname[0] == '\0') {
	load_stdin();
	return;
    }

    fd = open(fname, O_RDONLY, 0);
    if (fd < 0) rb_sys_fail(fname);
    readin(fd, fname);
    close(fd);
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

    if (fd < 0) rb_sys_fail(buf);

    readin(fd, "-");
}

void
rb_main(argc, argv)		/* real main() is in eval.c */
    int argc;
    char **argv;
{
    char *script;
    extern VALUE errat;

    rb_call_inits();

    rb_define_variable("$@", &errat, Qnil, Qnil);
    errat = str_new2(argv[0]);
    rb_define_variable("$VERBOSE", &verbose, Qnil, Qnil);
    rb_define_variable("$DEBUG", &debug, Qnil, Qnil);

#ifdef USE_DLN
    rb_dln_argv0 = argv[0];
#endif

    script = proc_options(&argc, &argv);
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

    if (nerrs == 0) {
	TopLevel(script, argc, argv);
    }

    exit(nerrs);
}
