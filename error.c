/************************************************

  error.c -

  $Author$
  $Date$
  created at: Mon Aug  9 16:11:34 JST 1993

  Copyright (C) 1993-1999 Yukihiro Matsumoto

************************************************/

#include "ruby.h"
#include "env.h"
#include <stdio.h>
#ifdef HAVE_STDARG_PROTOTYPES
#include <stdarg.h>
#define va_init_list(a,b) va_start(a,b)
#else
#include <varargs.h>
#define va_init_list(a,b) va_start(a)
#endif

#ifdef USE_CWGUSI
#include <sys/errno.h>
int sys_nerr = 256;
#endif

int ruby_nerrs;

static void
err_snprintf(buf, len, fmt, args)
    char *buf, *fmt;
    int len;
    va_list args;
{
    if (!ruby_sourcefile) {
	vsnprintf(buf, len, fmt, args);
    }
    else {
	int n = snprintf(buf, len, "%s:%d: ", ruby_sourcefile, ruby_sourceline);
	if (len > n) {
	    vsnprintf((char*)buf+n, len-n, fmt, args);
	}
    }
}

static void err_append _((char*));
static void
err_print(fmt, args)
    char *fmt;
    va_list args;
{
    char buf[BUFSIZ];

    err_snprintf(buf, BUFSIZ, fmt, args);
    err_append(buf);
}

void
#ifdef HAVE_STDARG_PROTOTYPES
rb_compile_error(char *fmt, ...)
#else
rb_compile_error(fmt, va_alist)
    char *fmt;
    va_dcl
#endif
{
    va_list args;

    va_init_list(args, fmt);
    err_print(fmt, args);
    va_end(args);
    ruby_nerrs++;
}

void
#ifdef HAVE_STDARG_PROTOTYPES
rb_compile_error_append(char *fmt, ...)
#else
rb_compile_error_append(fmt, va_alist)
    char *fmt;
    va_dcl
#endif
{
    va_list args;
    char buf[BUFSIZ];

    va_init_list(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);
    err_append(buf);
}

void
#ifdef HAVE_STDARG_PROTOTYPES
rb_warn(char *fmt, ...)
#else
rb_warn(fmt, va_alist)
    char *fmt;
    va_dcl
#endif
{
    char buf[BUFSIZ];
    va_list args;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);

    va_init_list(args, fmt);
    err_print(buf, args);
    va_end(args);
}

/* rb_warning() reports only in verbose mode */
void
#ifdef HAVE_STDARG_PROTOTYPES
rb_warning(char *fmt, ...)
#else
rb_warning(fmt, va_alist)
    char *fmt;
    va_dcl
#endif
{
    char buf[BUFSIZ];
    va_list args;

    if (!RTEST(rb_verbose)) return;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);

    va_init_list(args, fmt);
    err_print(buf, args);
    va_end(args);
}

void
#ifdef HAVE_STDARG_PROTOTYPES
rb_bug(char *fmt, ...)
#else
rb_bug(fmt, va_alist)
    char *fmt;
    va_dcl
#endif
{
    char buf[BUFSIZ];
    va_list args;

    snprintf(buf, BUFSIZ, "[BUG] %s", fmt);
    rb_in_eval = 0;

    va_init_list(args, fmt);
    err_print(buf, args);
    va_end(args);
    abort();
}

static struct types {
    int type;
    char *name;
} builtin_types[] = {
    T_NIL,	"nil",
    T_OBJECT,	"Object",
    T_CLASS,	"Class",
    T_ICLASS,	"iClass",	/* internal use: mixed-in module holder */
    T_MODULE,	"Module",
    T_FLOAT,	"Float",
    T_STRING,	"String",
    T_REGEXP,	"Regexp",
    T_ARRAY,	"Array",
    T_FIXNUM,	"Fixnum",
    T_HASH,	"Hash",
    T_STRUCT,	"Struct",
    T_BIGNUM,	"Bignum",
    T_FILE,	"File",
    T_TRUE,	"TRUE",
    T_FALSE,	"FALSE",
    T_DATA,	"Data",		/* internal use: wrapped C pointers */
    T_MATCH,	"Match",	/* data of $~ */
    T_VARMAP,	"Varmap",	/* internal use: dynamic variables */
    T_SCOPE,	"Scope",	/* internal use: variable scope */
    T_NODE,	"Node",		/* internal use: syntax tree node */
    -1,		0,
};

void
rb_check_type(x, t)
    VALUE x;
    int t;
{
    struct types *type = builtin_types;
    int tt = TYPE(x);

    if (tt != t) {
	while (type->type >= 0) {
	    if (type->type == t) {
		char *etype;

		if (NIL_P(x)) {
		    etype = "nil";
		}
		else if (FIXNUM_P(x)) {
		    etype = "Fixnum";
		}
		else if (rb_special_const_p(x)) {
		    etype = RSTRING(rb_obj_as_string(x))->ptr;
		}
		else {
		    etype = rb_class2name(CLASS_OF(x));
		}
		rb_raise(rb_eTypeError, "wrong argument type %s (expected %s)",
			 etype, type->name);
	    }
	    type++;
	}
	rb_bug("unknown type 0x%x", t);
    }
}

/* exception classes */
#include <errno.h>

VALUE rb_eException;
VALUE rb_eSystemExit, rb_eInterrupt, rb_eFatal;
VALUE rb_eStandardError;
VALUE rb_eRuntimeError;
VALUE rb_eSyntaxError;
VALUE rb_eTypeError;
VALUE rb_eArgError;
VALUE rb_eNameError;
VALUE rb_eIndexError;
VALUE rb_eLoadError;
VALUE rb_eSecurityError;
VALUE rb_eNotImpError;

VALUE rb_eSystemCallError;
VALUE rb_mErrno;

VALUE
rb_exc_new(etype, ptr, len)
    VALUE etype;
    char *ptr;
    int len;
{
    VALUE exc = rb_obj_alloc(etype);

    rb_iv_set(exc, "mesg", rb_str_new(ptr, len));
    return exc;
}

VALUE
rb_exc_new2(etype, s)
    VALUE etype;
    char *s;
{
    return rb_exc_new(etype, s, strlen(s));
}

VALUE
rb_exc_new3(etype, str)
    VALUE etype, str;
{
    char *s;
    int len;

    s = str2cstr(str, &len);
    return rb_exc_new(etype, s, len);
}

static VALUE
exc_initialize(argc, argv, exc)
    int argc;
    VALUE *argv;
    VALUE exc;
{
    VALUE mesg;

    if (rb_scan_args(argc, argv, "01", &mesg) == 1) {
	STR2CSTR(mesg);		/* ensure mesg can be converted to String */
    }
    rb_iv_set(exc, "mesg", mesg);

    return exc;
}

static VALUE
exc_exception(argc, argv, self)
    int argc;
    VALUE *argv;
    VALUE self;
{
    VALUE etype, exc;

    if (argc == 1 && self == argv[0]) return self;
    etype = CLASS_OF(self);
    while (FL_TEST(etype, FL_SINGLETON)) {
	etype = RCLASS(etype)->super;
    }
    exc = rb_obj_alloc(etype);
    rb_obj_call_init(exc);

    return exc;
}

static VALUE
exc_to_s(exc)
    VALUE exc;
{
    VALUE mesg = rb_iv_get(exc, "mesg");

    if (NIL_P(mesg)) return rb_class_path(CLASS_OF(exc));
    return mesg;
}

static VALUE
exc_inspect(exc)
    VALUE exc;
{
    VALUE str, klass;

    klass = CLASS_OF(exc);
    exc = rb_obj_as_string(exc);
    if (RSTRING(exc)->len == 0) {
	return rb_str_dup(rb_class_path(klass));
    }

    str = rb_str_new2("#<");
    klass = rb_class_path(klass);
    rb_str_concat(str, klass);
    rb_str_cat(str, ":", 1);
    rb_str_concat(str, exc);
    rb_str_cat(str, ">", 1);

    return str;
}

static VALUE
exc_backtrace(exc)
    VALUE exc;
{
    return rb_iv_get(exc, "bt");
}

static VALUE
check_backtrace(bt)
    VALUE bt;
{
    int i;
    static char *err = "backtrace must be Array of String";

    if (!NIL_P(bt)) {
	int t = TYPE(bt);

	if (t == T_STRING) return rb_ary_new3(1, bt);
	if (t != T_ARRAY) {
	    rb_raise(rb_eTypeError, err);
	}
	for (i=0;i<RARRAY(bt)->len;i++) {
	    if (TYPE(RARRAY(bt)->ptr[i]) != T_STRING) {
		rb_raise(rb_eTypeError, err);
	    }
	}
    }
    return bt;
}

static VALUE
exc_set_backtrace(exc, bt)
    VALUE exc;
{
    return rb_iv_set(exc, "bt", check_backtrace(bt));
}

static VALUE
exception(argc, argv)
    int argc;
    VALUE *argv;
{
    VALUE v = Qnil;
    VALUE etype = rb_eStandardError;
    int i;
    ID id;

    if (argc == 0) {
	rb_raise(rb_eArgError, "wrong # of arguments");
    }
    rb_warn("Exception() is now obsolete");
    if (TYPE(argv[argc-1]) == T_CLASS) {
	etype = argv[argc-1];
	argc--;
	if (!rb_funcall(etype, '<', 1, rb_eException)) {
	    rb_raise(rb_eTypeError, "exception should be subclass of Exception");
	}
    }
    for (i=0; i<argc; i++) {	/* argument check */
	id = rb_to_id(argv[i]);
	if (!rb_id2name(id)) {
	    rb_raise(rb_eArgError, "argument needs to be symbol or string");
	}
	if (!rb_is_const_id(id)) {
	    rb_raise(rb_eArgError, "identifier `%s' needs to be constant",
		     rb_id2name(id));
	}
    }
    for (i=0; i<argc; i++) {
	v = rb_define_class_under(ruby_class,
				  rb_id2name(rb_to_id(argv[i])),
				  rb_eStandardError);
    }
    return v;
}

#ifdef __BEOS__
typedef struct {
   VALUE *list;
   int n;
} syserr_list_entry;

typedef struct {
   int ix;
   int n;
} syserr_index_entry;

static VALUE syserr_list_b_general[16+1];
static VALUE syserr_list_b_os0[2+1];
static VALUE syserr_list_b_os1[5+1];
static VALUE syserr_list_b_os2[2+1];
static VALUE syserr_list_b_os3[3+1];
static VALUE syserr_list_b_os4[1+1];
static VALUE syserr_list_b_app[15+1];
static VALUE syserr_list_b_interface[0+1];
static VALUE syserr_list_b_media[8+1];
static VALUE syserr_list_b_midi[0+1];
static VALUE syserr_list_b_storage[15+1];
static VALUE syserr_list_b_posix[38+1];
static VALUE syserr_list_b_mail[8+1];
static VALUE syserr_list_b_print[1+1];
static VALUE syserr_list_b_device[14+1];

# define SYSERR_LIST_B(n) {(n), sizeof(n)/sizeof(VALUE)}
static const syserr_list_entry syserr_list[] = {
   SYSERR_LIST_B(syserr_list_b_general),
   SYSERR_LIST_B(syserr_list_b_os0),
   SYSERR_LIST_B(syserr_list_b_os1),
   SYSERR_LIST_B(syserr_list_b_os2),
   SYSERR_LIST_B(syserr_list_b_os3),
   SYSERR_LIST_B(syserr_list_b_os4),
   SYSERR_LIST_B(syserr_list_b_app),
   SYSERR_LIST_B(syserr_list_b_interface),
   SYSERR_LIST_B(syserr_list_b_media),
   SYSERR_LIST_B(syserr_list_b_midi),
   SYSERR_LIST_B(syserr_list_b_storage),
   SYSERR_LIST_B(syserr_list_b_posix),
   SYSERR_LIST_B(syserr_list_b_mail),
   SYSERR_LIST_B(syserr_list_b_print),
   SYSERR_LIST_B(syserr_list_b_device),
};
# undef SYSERR_LIST_B

static const syserr_index_entry syserr_index[]= {
     {0, 1},  {1, 5},  {6, 1},  {7, 1}, {8, 1}, {9, 1}, {10, 1}, {11, 1},
     {12, 1}, {13, 1}, {14, 1}, {0, 0},
};
#else
static VALUE *syserr_list;
#endif

#ifndef NT
extern int sys_nerr;
#endif

static VALUE
set_syserr(i, name)
    int i;
    char *name;
{
#ifdef __BEOS__
   VALUE *list;
   int ix, offset;
#endif
    VALUE error = rb_define_class_under(rb_mErrno, name, rb_eSystemCallError);
    rb_define_const(error, "Errno", INT2FIX(i));
#ifdef __BEOS__
   i -= B_GENERAL_ERROR_BASE;
   ix = (i >> 12) & 0xf;
   offset = (i >> 8) & 0xf;
   if (offset < syserr_index[ix].n) {
      ix = syserr_index[ix].ix;
      if ((i & 0xff) < syserr_list[ix + offset].n) {
	 list = syserr_list[ix + offset].list;
	 list[i & 0xff] = error;
	 rb_global_variable(&list[i & 0xff]);
      }
   }
#else
    if (i <= sys_nerr) {
	syserr_list[i] = error;
    }
#endif
    return error;
}

static VALUE
syserr_errno(self)
    VALUE self;
{
    return rb_iv_get(self, "errno");
}

#ifdef __BEOS__
static VALUE
get_syserr(int i)
{
   VALUE *list;
   int ix, offset;
   
   i -= B_GENERAL_ERROR_BASE;
   ix = (i >> 12) & 0xf;
   offset = (i >> 8) & 0xf;
   if (offset < syserr_index[ix].n) {
      ix = syserr_index[ix].ix;
      if ((i & 0xff) < syserr_list[ix + offset].n) {
	 list = syserr_list[ix + offset].list;
	 return list[i & 0xff];
      }
   }
   return 0;
}
#endif /* __BEOS__ */

static void init_syserr _((void));

void
Init_Exception()
{
    rb_eException   = rb_define_class("Exception", rb_cObject);
    rb_define_singleton_method(rb_eException, "exception", rb_class_new_instance, -1);
    rb_define_method(rb_eException, "exception", exc_exception, -1);
    rb_define_method(rb_eException, "initialize", exc_initialize, -1);
    rb_define_method(rb_eException, "to_s", exc_to_s, 0);
    rb_define_method(rb_eException, "to_str", exc_to_s, 0);
    rb_define_method(rb_eException, "message", exc_to_s, 0);
    rb_define_method(rb_eException, "inspect", exc_inspect, 0);
    rb_define_method(rb_eException, "backtrace", exc_backtrace, 0);
    rb_define_method(rb_eException, "set_backtrace", exc_set_backtrace, 1);

    rb_eSystemExit  = rb_define_class("SystemExit", rb_eException);
    rb_eFatal  	 = rb_define_class("fatal", rb_eException);
    rb_eInterrupt   = rb_define_class("Interrupt", rb_eException);

    rb_eStandardError = rb_define_class("StandardError", rb_eException);
    rb_eSyntaxError = rb_define_class("SyntaxError", rb_eStandardError);
    rb_eTypeError   = rb_define_class("TypeError", rb_eStandardError);
    rb_eArgError    = rb_define_class("ArgumentError", rb_eStandardError);
    rb_eNameError   = rb_define_class("NameError", rb_eStandardError);
    rb_eIndexError  = rb_define_class("IndexError", rb_eStandardError);
    rb_eLoadError   = rb_define_class("LoadError", rb_eStandardError);

    rb_eRuntimeError = rb_define_class("RuntimeError", rb_eStandardError);
    rb_eSecurityError = rb_define_class("SecurityError", rb_eStandardError);
    rb_eNotImpError = rb_define_class("NotImplementError", rb_eException);

    init_syserr();

    rb_define_global_function("Exception", exception, -1);
}

void
#ifdef HAVE_STDARG_PROTOTYPES
rb_raise(VALUE exc, char *fmt, ...)
#else
rb_raise(exc, fmt, va_alist)
    VALUE exc;
    char *fmt;
    va_dcl
#endif
{
    va_list args;
    char buf[BUFSIZ];

    va_init_list(args,fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);
    rb_exc_raise(rb_exc_new2(exc, buf));
}

void
#ifdef HAVE_STDARG_PROTOTYPES
rb_loaderror(char *fmt, ...)
#else
rb_loaderror(fmt, va_alist)
    char *fmt;
    va_dcl
#endif
{
    va_list args;
    char buf[BUFSIZ];

    va_init_list(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);
    rb_exc_raise(rb_exc_new2(rb_eLoadError, buf));
}

void
rb_notimplement()
{
    rb_raise(rb_eNotImpError,
	     "The %s() function is unimplemented on this machine",
	     rb_id2name(ruby_frame->last_func));
}

void
#ifdef HAVE_STDARG_PROTOTYPES
rb_fatal(char *fmt, ...)
#else
rb_fatal(fmt, va_alist)
    char *fmt;
    va_dcl
#endif
{
    va_list args;
    char buf[BUFSIZ];

    va_init_list(args, fmt);
    vsnprintf(buf, BUFSIZ, fmt, args);
    va_end(args);

    rb_in_eval = 0;
    rb_exc_fatal(rb_exc_new2(rb_eFatal, buf));
}

void
rb_sys_fail(mesg)
    char *mesg;
{
#ifndef NT
    char *strerror();
#endif
    char *err;
    char *buf;
    extern int errno;
    int n = errno;
    VALUE ee;

    err = strerror(errno);
    if (mesg) {
	buf = ALLOCA_N(char, strlen(err)+strlen(mesg)+4);
	sprintf(buf, "%s - %s", err, mesg);
    }
    else {
	buf = ALLOCA_N(char, strlen(err)+1);
	strcpy(buf, err);
    }

    errno = 0;
#ifdef __BEOS__
    ee = get_syserr(n);
    if (!ee) {
	char name[6];
      
	sprintf(name, "E%03d", n);
	ee = set_syserr(n, name);
   }
#else
# ifdef USE_CWGUSI
    if (n < 0) {
	int macoserr_index = sys_nerr - 1;
	if (!syserr_list[macoserr_index]) {
	    char name[6];
	    sprintf(name, "E%03d", macoserr_index);
	    ee = set_syserr(macoserr_index, name);
	}
    }
    else
#endif /* USE_CWGUSI */
    if (n > sys_nerr || !syserr_list[n]) {
	char name[6];

	sprintf(name, "E%03d", n);
	ee = set_syserr(n, name);
    }
    else {
	ee = syserr_list[n];
    }
    ee = rb_exc_new2(ee, buf);
#endif
    rb_iv_set(ee, "errno", INT2FIX(n));
    rb_exc_raise(ee);
}

static void
init_syserr()
{
#ifdef __BEOS__
   int i, ix, offset;
#endif
    rb_eSystemCallError = rb_define_class("SystemCallError", rb_eStandardError);
    rb_define_method(rb_eSystemCallError, "errno", syserr_errno, 0);

    rb_mErrno = rb_define_module("Errno");
#ifdef __BEOS__
   for (i = 0; syserr_index[i].n != 0; i++) {
      ix = syserr_index[i].ix;
      for (offset = 0; offset < syserr_index[i].n; offset++) {
	 MEMZERO(syserr_list[ix + offset].list, VALUE, syserr_list[ix + offset].n);
      }
   }
#else
    syserr_list = ALLOC_N(VALUE, sys_nerr+1);
    MEMZERO(syserr_list, VALUE, sys_nerr+1);
#endif

#ifdef EPERM
    set_syserr(EPERM, "EPERM");
#endif
#ifdef ENOENT
    set_syserr(ENOENT, "ENOENT");
#endif
#ifdef ESRCH
    set_syserr(ESRCH, "ESRCH");
#endif
#ifdef EINTR
    set_syserr(EINTR, "EINTR");
#endif
#ifdef EIO
    set_syserr(EIO, "EIO");
#endif
#ifdef ENXIO
    set_syserr(ENXIO, "ENXIO");
#endif
#ifdef E2BIG
    set_syserr(E2BIG, "E2BIG");
#endif
#ifdef ENOEXEC
    set_syserr(ENOEXEC, "ENOEXEC");
#endif
#ifdef EBADF
    set_syserr(EBADF, "EBADF");
#endif
#ifdef ECHILD
    set_syserr(ECHILD, "ECHILD");
#endif
#ifdef EAGAIN
    set_syserr(EAGAIN, "EAGAIN");
#endif
#ifdef ENOMEM
    set_syserr(ENOMEM, "ENOMEM");
#endif
#ifdef EACCES
    set_syserr(EACCES, "EACCES");
#endif
#ifdef EFAULT
    set_syserr(EFAULT, "EFAULT");
#endif
#ifdef ENOTBLK
    set_syserr(ENOTBLK, "ENOTBLK");
#endif
#ifdef EBUSY
    set_syserr(EBUSY, "EBUSY");
#endif
#ifdef EEXIST
    set_syserr(EEXIST, "EEXIST");
#endif
#ifdef EXDEV
    set_syserr(EXDEV, "EXDEV");
#endif
#ifdef ENODEV
    set_syserr(ENODEV, "ENODEV");
#endif
#ifdef ENOTDIR
    set_syserr(ENOTDIR, "ENOTDIR");
#endif
#ifdef EISDIR
    set_syserr(EISDIR, "EISDIR");
#endif
#ifdef EINVAL
    set_syserr(EINVAL, "EINVAL");
#endif
#ifdef ENFILE
    set_syserr(ENFILE, "ENFILE");
#endif
#ifdef EMFILE
    set_syserr(EMFILE, "EMFILE");
#endif
#ifdef ENOTTY
    set_syserr(ENOTTY, "ENOTTY");
#endif
#ifdef ETXTBSY
    set_syserr(ETXTBSY, "ETXTBSY");
#endif
#ifdef EFBIG
    set_syserr(EFBIG, "EFBIG");
#endif
#ifdef ENOSPC
    set_syserr(ENOSPC, "ENOSPC");
#endif
#ifdef ESPIPE
    set_syserr(ESPIPE, "ESPIPE");
#endif
#ifdef EROFS
    set_syserr(EROFS, "EROFS");
#endif
#ifdef EMLINK
    set_syserr(EMLINK, "EMLINK");
#endif
#ifdef EPIPE
    set_syserr(EPIPE, "EPIPE");
#endif
#ifdef EDOM
    set_syserr(EDOM, "EDOM");
#endif
#ifdef ERANGE
    set_syserr(ERANGE, "ERANGE");
#endif
#ifdef EDEADLK
    set_syserr(EDEADLK, "EDEADLK");
#endif
#ifdef ENAMETOOLONG
    set_syserr(ENAMETOOLONG, "ENAMETOOLONG");
#endif
#ifdef ENOLCK
    set_syserr(ENOLCK, "ENOLCK");
#endif
#ifdef ENOSYS
    set_syserr(ENOSYS, "ENOSYS");
#endif
#ifdef ENOTEMPTY
    set_syserr(ENOTEMPTY, "ENOTEMPTY");
#endif
#ifdef ELOOP
    set_syserr(ELOOP, "ELOOP");
#endif
#ifdef EWOULDBLOCK
    set_syserr(EWOULDBLOCK, "EWOULDBLOCK");
#endif
#ifdef ENOMSG
    set_syserr(ENOMSG, "ENOMSG");
#endif
#ifdef EIDRM
    set_syserr(EIDRM, "EIDRM");
#endif
#ifdef ECHRNG
    set_syserr(ECHRNG, "ECHRNG");
#endif
#ifdef EL2NSYNC
    set_syserr(EL2NSYNC, "EL2NSYNC");
#endif
#ifdef EL3HLT
    set_syserr(EL3HLT, "EL3HLT");
#endif
#ifdef EL3RST
    set_syserr(EL3RST, "EL3RST");
#endif
#ifdef ELNRNG
    set_syserr(ELNRNG, "ELNRNG");
#endif
#ifdef EUNATCH
    set_syserr(EUNATCH, "EUNATCH");
#endif
#ifdef ENOCSI
    set_syserr(ENOCSI, "ENOCSI");
#endif
#ifdef EL2HLT
    set_syserr(EL2HLT, "EL2HLT");
#endif
#ifdef EBADE
    set_syserr(EBADE, "EBADE");
#endif
#ifdef EBADR
    set_syserr(EBADR, "EBADR");
#endif
#ifdef EXFULL
    set_syserr(EXFULL, "EXFULL");
#endif
#ifdef ENOANO
    set_syserr(ENOANO, "ENOANO");
#endif
#ifdef EBADRQC
    set_syserr(EBADRQC, "EBADRQC");
#endif
#ifdef EBADSLT
    set_syserr(EBADSLT, "EBADSLT");
#endif
#ifdef EDEADLOCK
    set_syserr(EDEADLOCK, "EDEADLOCK");
#endif
#ifdef EBFONT
    set_syserr(EBFONT, "EBFONT");
#endif
#ifdef ENOSTR
    set_syserr(ENOSTR, "ENOSTR");
#endif
#ifdef ENODATA
    set_syserr(ENODATA, "ENODATA");
#endif
#ifdef ETIME
    set_syserr(ETIME, "ETIME");
#endif
#ifdef ENOSR
    set_syserr(ENOSR, "ENOSR");
#endif
#ifdef ENONET
    set_syserr(ENONET, "ENONET");
#endif
#ifdef ENOPKG
    set_syserr(ENOPKG, "ENOPKG");
#endif
#ifdef EREMOTE
    set_syserr(EREMOTE, "EREMOTE");
#endif
#ifdef ENOLINK
    set_syserr(ENOLINK, "ENOLINK");
#endif
#ifdef EADV
    set_syserr(EADV, "EADV");
#endif
#ifdef ESRMNT
    set_syserr(ESRMNT, "ESRMNT");
#endif
#ifdef ECOMM
    set_syserr(ECOMM, "ECOMM");
#endif
#ifdef EPROTO
    set_syserr(EPROTO, "EPROTO");
#endif
#ifdef EMULTIHOP
    set_syserr(EMULTIHOP, "EMULTIHOP");
#endif
#ifdef EDOTDOT
    set_syserr(EDOTDOT, "EDOTDOT");
#endif
#ifdef EBADMSG
    set_syserr(EBADMSG, "EBADMSG");
#endif
#ifdef EOVERFLOW
    set_syserr(EOVERFLOW, "EOVERFLOW");
#endif
#ifdef ENOTUNIQ
    set_syserr(ENOTUNIQ, "ENOTUNIQ");
#endif
#ifdef EBADFD
    set_syserr(EBADFD, "EBADFD");
#endif
#ifdef EREMCHG
    set_syserr(EREMCHG, "EREMCHG");
#endif
#ifdef ELIBACC
    set_syserr(ELIBACC, "ELIBACC");
#endif
#ifdef ELIBBAD
    set_syserr(ELIBBAD, "ELIBBAD");
#endif
#ifdef ELIBSCN
    set_syserr(ELIBSCN, "ELIBSCN");
#endif
#ifdef ELIBMAX
    set_syserr(ELIBMAX, "ELIBMAX");
#endif
#ifdef ELIBEXEC
    set_syserr(ELIBEXEC, "ELIBEXEC");
#endif
#ifdef EILSEQ
    set_syserr(EILSEQ, "EILSEQ");
#endif
#ifdef ERESTART
    set_syserr(ERESTART, "ERESTART");
#endif
#ifdef ESTRPIPE
    set_syserr(ESTRPIPE, "ESTRPIPE");
#endif
#ifdef EUSERS
    set_syserr(EUSERS, "EUSERS");
#endif
#ifdef ENOTSOCK
    set_syserr(ENOTSOCK, "ENOTSOCK");
#endif
#ifdef EDESTADDRREQ
    set_syserr(EDESTADDRREQ, "EDESTADDRREQ");
#endif
#ifdef EMSGSIZE
    set_syserr(EMSGSIZE, "EMSGSIZE");
#endif
#ifdef EPROTOTYPE
    set_syserr(EPROTOTYPE, "EPROTOTYPE");
#endif
#ifdef ENOPROTOOPT
    set_syserr(ENOPROTOOPT, "ENOPROTOOPT");
#endif
#ifdef EPROTONOSUPPORT
    set_syserr(EPROTONOSUPPORT, "EPROTONOSUPPORT");
#endif
#ifdef ESOCKTNOSUPPORT
    set_syserr(ESOCKTNOSUPPORT, "ESOCKTNOSUPPORT");
#endif
#ifdef EOPNOTSUPP
    set_syserr(EOPNOTSUPP, "EOPNOTSUPP");
#endif
#ifdef EPFNOSUPPORT
    set_syserr(EPFNOSUPPORT, "EPFNOSUPPORT");
#endif
#ifdef EAFNOSUPPORT
    set_syserr(EAFNOSUPPORT, "EAFNOSUPPORT");
#endif
#ifdef EADDRINUSE
    set_syserr(EADDRINUSE, "EADDRINUSE");
#endif
#ifdef EADDRNOTAVAIL
    set_syserr(EADDRNOTAVAIL, "EADDRNOTAVAIL");
#endif
#ifdef ENETDOWN
    set_syserr(ENETDOWN, "ENETDOWN");
#endif
#ifdef ENETUNREACH
    set_syserr(ENETUNREACH, "ENETUNREACH");
#endif
#ifdef ENETRESET
    set_syserr(ENETRESET, "ENETRESET");
#endif
#ifdef ECONNABORTED
    set_syserr(ECONNABORTED, "ECONNABORTED");
#endif
#ifdef ECONNRESET
    set_syserr(ECONNRESET, "ECONNRESET");
#endif
#ifdef ENOBUFS
    set_syserr(ENOBUFS, "ENOBUFS");
#endif
#ifdef EISCONN
    set_syserr(EISCONN, "EISCONN");
#endif
#ifdef ENOTCONN
    set_syserr(ENOTCONN, "ENOTCONN");
#endif
#ifdef ESHUTDOWN
    set_syserr(ESHUTDOWN, "ESHUTDOWN");
#endif
#ifdef ETOOMANYREFS
    set_syserr(ETOOMANYREFS, "ETOOMANYREFS");
#endif
#ifdef ETIMEDOUT
    set_syserr(ETIMEDOUT, "ETIMEDOUT");
#endif
#ifdef ECONNREFUSED
    set_syserr(ECONNREFUSED, "ECONNREFUSED");
#endif
#ifdef EHOSTDOWN
    set_syserr(EHOSTDOWN, "EHOSTDOWN");
#endif
#ifdef EHOSTUNREACH
    set_syserr(EHOSTUNREACH, "EHOSTUNREACH");
#endif
#ifdef EALREADY
    set_syserr(EALREADY, "EALREADY");
#endif
#ifdef EINPROGRESS
    set_syserr(EINPROGRESS, "EINPROGRESS");
#endif
#ifdef ESTALE
    set_syserr(ESTALE, "ESTALE");
#endif
#ifdef EUCLEAN
    set_syserr(EUCLEAN, "EUCLEAN");
#endif
#ifdef ENOTNAM
    set_syserr(ENOTNAM, "ENOTNAM");
#endif
#ifdef ENAVAIL
    set_syserr(ENAVAIL, "ENAVAIL");
#endif
#ifdef EISNAM
    set_syserr(EISNAM, "EISNAM");
#endif
#ifdef EREMOTEIO
    set_syserr(EREMOTEIO, "EREMOTEIO");
#endif
#ifdef EDQUOT
    set_syserr(EDQUOT, "EDQUOT");
#endif
}

static void
err_append(s)
    char *s;
{
    extern VALUE rb_errinfo;

    if (rb_in_eval) {
	if (NIL_P(rb_errinfo)) {
	    rb_errinfo = rb_exc_new2(rb_eSyntaxError, s);
	}
	else {
	    VALUE str = rb_str_to_str(rb_errinfo);

	    rb_str_cat(str, "\n", 1);
	    rb_str_cat(str, s, strlen(s));
	    rb_errinfo = rb_exc_new3(rb_eSyntaxError, str);
	}
    }
    else {
	fputs(s, stderr);
	fputs("\n", stderr);
	fflush(stderr);
    }
}
