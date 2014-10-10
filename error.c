/**********************************************************************

  error.c -

  $Author$
  created at: Mon Aug  9 16:11:34 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/ruby.h"
#include "ruby/st.h"
#include "ruby/encoding.h"
#include "internal.h"
#include "vm_core.h"

#include <stdio.h>
#include <stdarg.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#include <errno.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif

#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif

#ifndef WIFEXITED
#define WIFEXITED(status) 1
#endif

#ifndef WEXITSTATUS
#define WEXITSTATUS(status) (status)
#endif

VALUE rb_eEAGAIN;
VALUE rb_eEWOULDBLOCK;
VALUE rb_eEINPROGRESS;

extern const char ruby_description[];

static const char REPORTBUG_MSG[] =
	"[NOTE]\n" \
	"You may have encountered a bug in the Ruby interpreter" \
	" or extension libraries.\n" \
	"Bug reports are welcome.\n" \
	""
#if defined __APPLE__
	"Don't forget to include the above Crash Report log file.\n"
#endif
	"For details: http://www.ruby-lang.org/bugreport.html\n\n" \
    ;

static const char *
rb_strerrno(int err)
{
#define defined_error(name, num) if (err == (num)) return (name);
#define undefined_error(name)
#include "known_errors.inc"
#undef defined_error
#undef undefined_error
    return NULL;
}

static int
err_position_0(char *buf, long len, const char *file, int line)
{
    if (!file) {
	return 0;
    }
    else if (line == 0) {
	return snprintf(buf, len, "%s: ", file);
    }
    else {
	return snprintf(buf, len, "%s:%d: ", file, line);
    }
}

static VALUE
compile_snprintf(rb_encoding *enc, const char *pre, const char *file, int line, const char *fmt, va_list args)
{
    VALUE str = rb_enc_str_new(0, 0, enc);

    if (file) {
	rb_str_cat2(str, file);
	if (line) rb_str_catf(str, ":%d", line);
	rb_str_cat2(str, ": ");
    }
    if (pre) rb_str_cat2(str, pre);
    rb_str_vcatf(str, fmt, args);
    return str;
}

static void
compile_err_append(VALUE mesg)
{
    rb_thread_t *th = GET_THREAD();
    VALUE err = th->errinfo;
    rb_block_t *prev_base_block = th->base_block;
    th->base_block = 0;
    /* base_block should be zero while normal Ruby execution */
    /* after this line, any Ruby code *can* run */

    if (th->mild_compile_error) {
	if (RTEST(err)) {
	    VALUE str = rb_obj_as_string(err);

	    rb_str_cat2(str, "\n");
	    rb_str_append(str, mesg);
	    mesg = str;
	}
	err = rb_exc_new3(rb_eSyntaxError, mesg);
	th->errinfo = err;
    }
    else {
	if (!RTEST(err)) {
	    err = rb_exc_new2(rb_eSyntaxError, "compile error");
	    th->errinfo = err;
	}
	rb_str_cat2(mesg, "\n");
	rb_write_error_str(mesg);
    }

    /* returned to the parser world */
    th->base_block = prev_base_block;
}

void
rb_compile_error_with_enc(const char *file, int line, void *enc, const char *fmt, ...)
{
    va_list args;
    VALUE str;

    va_start(args, fmt);
    str = compile_snprintf(enc, NULL, file, line, fmt, args);
    va_end(args);
    compile_err_append(str);
}

void
rb_compile_error(const char *file, int line, const char *fmt, ...)
{
    va_list args;
    VALUE str;

    va_start(args, fmt);
    str = compile_snprintf(NULL, NULL, file, line, fmt, args);
    va_end(args);
    compile_err_append(str);
}

void
rb_compile_error_append(const char *fmt, ...)
{
    va_list args;
    VALUE str;

    va_start(args, fmt);
    str = rb_vsprintf(fmt, args);
    va_end(args);
    compile_err_append(str);
}

static void
compile_warn_print(const char *file, int line, const char *fmt, va_list args)
{
    VALUE str;

    str = compile_snprintf(NULL, "warning: ", file, line, fmt, args);
    rb_str_cat2(str, "\n");
    rb_write_error_str(str);
}

void
rb_compile_warn(const char *file, int line, const char *fmt, ...)
{
    va_list args;

    if (NIL_P(ruby_verbose)) return;

    va_start(args, fmt);
    compile_warn_print(file, line, fmt, args);
    va_end(args);
}

/* rb_compile_warning() reports only in verbose mode */
void
rb_compile_warning(const char *file, int line, const char *fmt, ...)
{
    va_list args;

    if (!RTEST(ruby_verbose)) return;

    va_start(args, fmt);
    compile_warn_print(file, line, fmt, args);
    va_end(args);
}

static void
warn_print(const char *fmt, va_list args)
{
    VALUE str = rb_str_new(0, 0);
    VALUE file = rb_sourcefilename();

    if (!NIL_P(file)) {
	int line = rb_sourceline();
	str = rb_str_append(str, file);
	if (line) rb_str_catf(str, ":%d", line);
	rb_str_cat2(str, ": ");
    }

    rb_str_cat2(str, "warning: ");
    rb_str_vcatf(str, fmt, args);
    rb_str_cat2(str, "\n");
    rb_write_error_str(str);
}

void
rb_warn(const char *fmt, ...)
{
    va_list args;

    if (NIL_P(ruby_verbose)) return;

    va_start(args, fmt);
    warn_print(fmt, args);
    va_end(args);
}

/* rb_warning() reports only in verbose mode */
void
rb_warning(const char *fmt, ...)
{
    va_list args;

    if (!RTEST(ruby_verbose)) return;

    va_start(args, fmt);
    warn_print(fmt, args);
    va_end(args);
}

/*
 * call-seq:
 *    warn(msg, ...)   -> nil
 *
 * Displays each of the given messages followed by a record separator on
 * STDERR unless warnings have been disabled (for example with the
 * <code>-W0</code> flag).
 *
 *    warn("warning 1", "warning 2")
 *
 *  <em>produces:</em>
 *
 *    warning 1
 *    warning 2
 */

static VALUE
rb_warn_m(int argc, VALUE *argv, VALUE exc)
{
    if (!NIL_P(ruby_verbose) && argc > 0) {
	rb_io_puts(argc, argv, rb_stderr);
    }
    return Qnil;
}

#define MAX_BUG_REPORTERS 0x100

static struct bug_reporters {
    void (*func)(FILE *out, void *data);
    void *data;
} bug_reporters[MAX_BUG_REPORTERS];

static int bug_reporters_size;

int
rb_bug_reporter_add(void (*func)(FILE *, void *), void *data)
{
    struct bug_reporters *reporter;
    if (bug_reporters_size >= MAX_BUG_REPORTERS) {
	return 0; /* failed to register */
    }
    reporter = &bug_reporters[bug_reporters_size++];
    reporter->func = func;
    reporter->data = data;

    return 1;
}

/* SIGSEGV handler might have a very small stack. Thus we need to use it carefully. */
#define REPORT_BUG_BUFSIZ 256
static FILE *
bug_report_file(const char *file, int line)
{
    char buf[REPORT_BUG_BUFSIZ];
    FILE *out = stderr;
    int len = err_position_0(buf, sizeof(buf), file, line);

    if ((ssize_t)fwrite(buf, 1, len, out) == (ssize_t)len ||
	(ssize_t)fwrite(buf, 1, len, (out = stdout)) == (ssize_t)len) {
	return out;
    }
    return NULL;
}

static void
bug_report_begin(FILE *out, const char *fmt, va_list args)
{
    char buf[REPORT_BUG_BUFSIZ];

    fputs("[BUG] ", out);
    vsnprintf(buf, sizeof(buf), fmt, args);
    fputs(buf, out);
    snprintf(buf, sizeof(buf), "\n%s\n\n", ruby_description);
    fputs(buf, out);
}

#define bug_report_begin(out, fmt) do { \
    va_list args; \
    va_start(args, fmt); \
    bug_report_begin(out, fmt, args); \
    va_end(args); \
} while (0)

static void
bug_report_end(FILE *out)
{
    /* call additional bug reporters */
    {
	int i;
	for (i=0; i<bug_reporters_size; i++) {
	    struct bug_reporters *reporter = &bug_reporters[i];
	    (*reporter->func)(out, reporter->data);
	}
    }
    fprintf(out, REPORTBUG_MSG);
}

#define report_bug(file, line, fmt, ctx) do { \
    FILE *out = bug_report_file(file, line); \
    if (out) { \
	bug_report_begin(out, fmt); \
	rb_vm_bugreport(ctx); \
	bug_report_end(out); \
    } \
} while (0) \

NORETURN(static void die(void));
static void
die(void)
{
#if defined(_WIN32) && defined(RUBY_MSVCRT_VERSION) && RUBY_MSVCRT_VERSION >= 80
    _set_abort_behavior( 0, _CALL_REPORTFAULT);
#endif

    abort();
}

void
rb_bug(const char *fmt, ...)
{
    const char *file = NULL;
    int line = 0;

    if (GET_THREAD()) {
	file = rb_sourcefile();
	line = rb_sourceline();
    }

    report_bug(file, line, fmt, NULL);

    die();
}

void
rb_bug_context(const void *ctx, const char *fmt, ...)
{
    const char *file = NULL;
    int line = 0;

    if (GET_THREAD()) {
	file = rb_sourcefile();
	line = rb_sourceline();
    }

    report_bug(file, line, fmt, ctx);

    die();
}


void
rb_bug_errno(const char *mesg, int errno_arg)
{
    if (errno_arg == 0)
        rb_bug("%s: errno == 0 (NOERROR)", mesg);
    else {
        const char *errno_str = rb_strerrno(errno_arg);
        if (errno_str)
            rb_bug("%s: %s (%s)", mesg, strerror(errno_arg), errno_str);
        else
            rb_bug("%s: %s (%d)", mesg, strerror(errno_arg), errno_arg);
    }
}

/*
 * this is safe to call inside signal handler and timer thread
 * (which isn't a Ruby Thread object)
 */
#define write_or_abort(fd, str, len) (write((fd), (str), (len)) < 0 ? abort() : (void)0)
#define WRITE_CONST(fd,str) write_or_abort((fd),(str),sizeof(str) - 1)

void
rb_async_bug_errno(const char *mesg, int errno_arg)
{
    WRITE_CONST(2, "[ASYNC BUG] ");
    write_or_abort(2, mesg, strlen(mesg));
    WRITE_CONST(2, "\n");

    if (errno_arg == 0) {
	WRITE_CONST(2, "errno == 0 (NOERROR)\n");
    }
    else {
	const char *errno_str = rb_strerrno(errno_arg);

	if (!errno_str)
	    errno_str = "undefined errno";
	write_or_abort(2, errno_str, strlen(errno_str));
    }
    WRITE_CONST(2, "\n\n");
    write_or_abort(2, ruby_description, strlen(ruby_description));
    WRITE_CONST(2, "\n\n");
    WRITE_CONST(2, REPORTBUG_MSG);
    abort();
}

void
rb_compile_bug(const char *file, int line, const char *fmt, ...)
{
    report_bug(file, line, fmt, NULL);

    abort();
}

static const char builtin_types[][10] = {
    "", 			/* 0x00, */
    "Object",
    "Class",
    "Module",
    "Float",
    "String",
    "Regexp",
    "Array",
    "Hash",
    "Struct",
    "Bignum",
    "File",
    "Data",			/* internal use: wrapped C pointers */
    "MatchData",		/* data of $~ */
    "Complex",
    "Rational",
    "",				/* 0x10 */
    "nil",
    "true",
    "false",
    "Symbol",			/* :symbol */
    "Fixnum",
    "",				/* 0x16 */
    "",				/* 0x17 */
    "",				/* 0x18 */
    "",				/* 0x19 */
    "",				/* 0x1a */
    "undef",			/* internal use: #undef; should not happen */
    "Node",			/* internal use: syntax tree node */
    "iClass",			/* internal use: mixed-in module holder */
};

const char *
rb_builtin_type_name(int t)
{
    const char *name;
    if ((unsigned int)t >= numberof(builtin_types)) return 0;
    name = builtin_types[t];
    if (*name) return name;
    return 0;
}

#define builtin_class_name rb_builtin_class_name
const char *
rb_builtin_class_name(VALUE x)
{
    const char *etype;

    if (NIL_P(x)) {
	etype = "nil";
    }
    else if (FIXNUM_P(x)) {
	etype = "Fixnum";
    }
    else if (SYMBOL_P(x)) {
	etype = "Symbol";
    }
    else if (RB_TYPE_P(x, T_TRUE)) {
	etype = "true";
    }
    else if (RB_TYPE_P(x, T_FALSE)) {
	etype = "false";
    }
    else {
	etype = rb_obj_classname(x);
    }
    return etype;
}

void
rb_check_type(VALUE x, int t)
{
    int xt;

    if (x == Qundef) {
	rb_bug("undef leaked to the Ruby space");
    }

    xt = TYPE(x);
    if (xt != t || (xt == T_DATA && RTYPEDDATA_P(x))) {
	const char *tname = rb_builtin_type_name(t);
	if (tname) {
	    rb_raise(rb_eTypeError, "wrong argument type %s (expected %s)",
		     builtin_class_name(x), tname);
	}
	if (xt > T_MASK && xt <= 0x3f) {
	    rb_fatal("unknown type 0x%x (0x%x given, probably comes from extension library for ruby 1.8)", t, xt);
	}
	rb_bug("unknown type 0x%x (0x%x given)", t, xt);
    }
}

int
rb_typeddata_inherited_p(const rb_data_type_t *child, const rb_data_type_t *parent)
{
    while (child) {
	if (child == parent) return 1;
	child = child->parent;
    }
    return 0;
}

int
rb_typeddata_is_kind_of(VALUE obj, const rb_data_type_t *data_type)
{
    if (!RB_TYPE_P(obj, T_DATA) ||
	!RTYPEDDATA_P(obj) || !rb_typeddata_inherited_p(RTYPEDDATA_TYPE(obj), data_type)) {
	return 0;
    }
    return 1;
}

void *
rb_check_typeddata(VALUE obj, const rb_data_type_t *data_type)
{
    const char *etype;
    static const char mesg[] = "wrong argument type %s (expected %s)";

    if (!RB_TYPE_P(obj, T_DATA)) {
	etype = builtin_class_name(obj);
	rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name);
    }
    if (!RTYPEDDATA_P(obj)) {
	etype = rb_obj_classname(obj);
	rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name);
    }
    else if (!rb_typeddata_inherited_p(RTYPEDDATA_TYPE(obj), data_type)) {
	etype = RTYPEDDATA_TYPE(obj)->wrap_struct_name;
	rb_raise(rb_eTypeError, mesg, etype, data_type->wrap_struct_name);
    }
    return DATA_PTR(obj);
}

/* exception classes */
VALUE rb_eException;
VALUE rb_eSystemExit;
VALUE rb_eInterrupt;
VALUE rb_eSignal;
VALUE rb_eFatal;
VALUE rb_eStandardError;
VALUE rb_eRuntimeError;
VALUE rb_eTypeError;
VALUE rb_eArgError;
VALUE rb_eIndexError;
VALUE rb_eKeyError;
VALUE rb_eRangeError;
VALUE rb_eNameError;
VALUE rb_eEncodingError;
VALUE rb_eEncCompatError;
VALUE rb_eNoMethodError;
VALUE rb_eSecurityError;
VALUE rb_eNotImpError;
VALUE rb_eNoMemError;
VALUE rb_cNameErrorMesg;

VALUE rb_eScriptError;
VALUE rb_eSyntaxError;
VALUE rb_eLoadError;

VALUE rb_eSystemCallError;
VALUE rb_mErrno;
static VALUE rb_eNOERROR;

#undef rb_exc_new_cstr

VALUE
rb_exc_new(VALUE etype, const char *ptr, long len)
{
    return rb_funcall(etype, rb_intern("new"), 1, rb_str_new(ptr, len));
}

VALUE
rb_exc_new_cstr(VALUE etype, const char *s)
{
    return rb_exc_new(etype, s, strlen(s));
}

VALUE
rb_exc_new_str(VALUE etype, VALUE str)
{
    StringValue(str);
    return rb_funcall(etype, rb_intern("new"), 1, str);
}

/*
 * call-seq:
 *    Exception.new(msg = nil)   ->  exception
 *
 *  Construct a new Exception object, optionally passing in
 *  a message.
 */

static VALUE
exc_initialize(int argc, VALUE *argv, VALUE exc)
{
    VALUE arg;

    rb_scan_args(argc, argv, "01", &arg);
    rb_iv_set(exc, "mesg", arg);
    rb_iv_set(exc, "bt", Qnil);

    return exc;
}

/*
 *  Document-method: exception
 *
 *  call-seq:
 *     exc.exception(string)  ->  an_exception or exc
 *
 *  With no argument, or if the argument is the same as the receiver,
 *  return the receiver. Otherwise, create a new
 *  exception object of the same class as the receiver, but with a
 *  message equal to <code>string.to_str</code>.
 *
 */

static VALUE
exc_exception(int argc, VALUE *argv, VALUE self)
{
    VALUE exc;

    if (argc == 0) return self;
    if (argc == 1 && self == argv[0]) return self;
    exc = rb_obj_clone(self);
    exc_initialize(argc, argv, exc);

    return exc;
}

/*
 * call-seq:
 *   exception.to_s   ->  string
 *
 * Returns exception's message (or the name of the exception if
 * no message is set).
 */

static VALUE
exc_to_s(VALUE exc)
{
    VALUE mesg = rb_attr_get(exc, rb_intern("mesg"));

    if (NIL_P(mesg)) return rb_class_name(CLASS_OF(exc));
    return rb_String(mesg);
}

/*
 * call-seq:
 *   exception.message   ->  string
 *
 * Returns the result of invoking <code>exception.to_s</code>.
 * Normally this returns the exception's message or name. By
 * supplying a to_str method, exceptions are agreeing to
 * be used where Strings are expected.
 */

static VALUE
exc_message(VALUE exc)
{
    return rb_funcall(exc, rb_intern("to_s"), 0, 0);
}

/*
 * call-seq:
 *   exception.inspect   -> string
 *
 * Return this exception's class name and message
 */

static VALUE
exc_inspect(VALUE exc)
{
    VALUE str, klass;

    klass = CLASS_OF(exc);
    exc = rb_obj_as_string(exc);
    if (RSTRING_LEN(exc) == 0) {
	return rb_str_dup(rb_class_name(klass));
    }

    str = rb_str_buf_new2("#<");
    klass = rb_class_name(klass);
    rb_str_buf_append(str, klass);
    rb_str_buf_cat(str, ": ", 2);
    rb_str_buf_append(str, exc);
    rb_str_buf_cat(str, ">", 1);

    return str;
}

/*
 *  call-seq:
 *     exception.backtrace    -> array
 *
 *  Returns any backtrace associated with the exception. The backtrace
 *  is an array of strings, each containing either ``filename:lineNo: in
 *  `method''' or ``filename:lineNo.''
 *
 *     def a
 *       raise "boom"
 *     end
 *
 *     def b
 *       a()
 *     end
 *
 *     begin
 *       b()
 *     rescue => detail
 *       print detail.backtrace.join("\n")
 *     end
 *
 *  <em>produces:</em>
 *
 *     prog.rb:2:in `a'
 *     prog.rb:6:in `b'
 *     prog.rb:10
*/

static VALUE
exc_backtrace(VALUE exc)
{
    ID bt;
    VALUE obj;

    CONST_ID(bt, "bt");
    obj = rb_attr_get(exc, bt);

    if (rb_backtrace_p(obj)) {
	obj = rb_backtrace_to_str_ary(obj);
	/* rb_iv_set(exc, "bt", obj); */
    }

    return obj;
}

/*
 *  call-seq:
 *     exception.backtrace_locations    -> array
 *
 *  Returns any backtrace associated with the exception. This method is
 *  similar to Exception#backtrace, but the backtrace is an array of
 *   Thread::Backtrace::Location.
 *
 *  Now, this method is not affected by Exception#set_backtrace().
 */
static VALUE
exc_backtrace_locations(VALUE exc)
{
    ID bt_locations;
    VALUE obj;

    CONST_ID(bt_locations, "bt_locations");
    obj = rb_attr_get(exc, bt_locations);
    if (!NIL_P(obj)) {
	obj = rb_backtrace_to_location_ary(obj);
    }
    return obj;
}

VALUE
rb_check_backtrace(VALUE bt)
{
    long i;
    static const char err[] = "backtrace must be Array of String";

    if (!NIL_P(bt)) {
	if (RB_TYPE_P(bt, T_STRING)) return rb_ary_new3(1, bt);
	if (rb_backtrace_p(bt)) return bt;
	if (!RB_TYPE_P(bt, T_ARRAY)) {
	    rb_raise(rb_eTypeError, err);
	}
	for (i=0;i<RARRAY_LEN(bt);i++) {
	    VALUE e = RARRAY_AREF(bt, i);
	    if (!RB_TYPE_P(e, T_STRING)) {
		rb_raise(rb_eTypeError, err);
	    }
	}
    }
    return bt;
}

/*
 *  call-seq:
 *     exc.set_backtrace(backtrace)   ->  array
 *
 *  Sets the backtrace information associated with +exc+. The +backtrace+ must
 *  be an array of String objects or a single String in the format described
 *  in Exception#backtrace.
 *
 */

static VALUE
exc_set_backtrace(VALUE exc, VALUE bt)
{
    return rb_iv_set(exc, "bt", rb_check_backtrace(bt));
}

VALUE
rb_exc_set_backtrace(VALUE exc, VALUE bt)
{
    return exc_set_backtrace(exc, bt);
}

/*
 * call-seq:
 *   exception.cause   -> an_exception or nil
 *
 * Returns the previous exception ($!) at the time this exception was raised.
 * This is useful for wrapping exceptions and retaining the original exception
 * information.
 */

VALUE
exc_cause(VALUE exc)
{
    ID id_cause;
    CONST_ID(id_cause, "cause");
    return rb_attr_get(exc, id_cause);
}

static VALUE
try_convert_to_exception(VALUE obj)
{
    ID id_exception;
    CONST_ID(id_exception, "exception");
    return rb_check_funcall(obj, id_exception, 0, 0);
}

/*
 *  call-seq:
 *     exc == obj   -> true or false
 *
 *  Equality---If <i>obj</i> is not an <code>Exception</code>, returns
 *  <code>false</code>. Otherwise, returns <code>true</code> if <i>exc</i> and
 *  <i>obj</i> share same class, messages, and backtrace.
 */

static VALUE
exc_equal(VALUE exc, VALUE obj)
{
    VALUE mesg, backtrace;
    ID id_mesg;

    if (exc == obj) return Qtrue;
    CONST_ID(id_mesg, "mesg");

    if (rb_obj_class(exc) != rb_obj_class(obj)) {
	int status = 0;
	ID id_message, id_backtrace;
	CONST_ID(id_message, "message");
	CONST_ID(id_backtrace, "backtrace");

	obj = rb_protect(try_convert_to_exception, obj, &status);
	if (status || obj == Qundef) {
	    rb_set_errinfo(Qnil);
	    return Qfalse;
	}
	if (rb_obj_class(exc) != rb_obj_class(obj)) return Qfalse;
	mesg = rb_check_funcall(obj, id_message, 0, 0);
	if (mesg == Qundef) return Qfalse;
	backtrace = rb_check_funcall(obj, id_backtrace, 0, 0);
	if (backtrace == Qundef) return Qfalse;
    }
    else {
	mesg = rb_attr_get(obj, id_mesg);
	backtrace = exc_backtrace(obj);
    }

    if (!rb_equal(rb_attr_get(exc, id_mesg), mesg))
	return Qfalse;
    if (!rb_equal(exc_backtrace(exc), backtrace))
	return Qfalse;
    return Qtrue;
}

/*
 * call-seq:
 *   SystemExit.new              -> system_exit
 *   SystemExit.new(status)      -> system_exit
 *   SystemExit.new(status, msg) -> system_exit
 *   SystemExit.new(msg)         -> system_exit
 *
 * Create a new +SystemExit+ exception with the given status and message.
 * Status is true, false, or an integer.
 * If status is not given, true is used.
 */

static VALUE
exit_initialize(int argc, VALUE *argv, VALUE exc)
{
    VALUE status;
    if (argc > 0) {
	status = *argv;

	switch (status) {
	  case Qtrue:
	    status = INT2FIX(EXIT_SUCCESS);
	    ++argv;
	    --argc;
	    break;
	  case Qfalse:
	    status = INT2FIX(EXIT_FAILURE);
	    ++argv;
	    --argc;
	    break;
	  default:
	    status = rb_check_to_int(status);
	    if (NIL_P(status)) {
		status = INT2FIX(EXIT_SUCCESS);
	    }
	    else {
#if EXIT_SUCCESS != 0
		if (status == INT2FIX(0))
		    status = INT2FIX(EXIT_SUCCESS);
#endif
		++argv;
		--argc;
	    }
	    break;
	}
    }
    else {
	status = INT2FIX(EXIT_SUCCESS);
    }
    rb_call_super(argc, argv);
    rb_iv_set(exc, "status", status);
    return exc;
}


/*
 * call-seq:
 *   system_exit.status   -> fixnum
 *
 * Return the status value associated with this system exit.
 */

static VALUE
exit_status(VALUE exc)
{
    return rb_attr_get(exc, rb_intern("status"));
}


/*
 * call-seq:
 *   system_exit.success?  -> true or false
 *
 * Returns +true+ if exiting successful, +false+ if not.
 */

static VALUE
exit_success_p(VALUE exc)
{
    VALUE status_val = rb_attr_get(exc, rb_intern("status"));
    int status;

    if (NIL_P(status_val))
	return Qtrue;
    status = NUM2INT(status_val);
    if (WIFEXITED(status) && WEXITSTATUS(status) == EXIT_SUCCESS)
	return Qtrue;

    return Qfalse;
}

void
rb_name_error(ID id, const char *fmt, ...)
{
    VALUE exc, argv[2];
    va_list args;

    va_start(args, fmt);
    argv[0] = rb_vsprintf(fmt, args);
    va_end(args);

    argv[1] = ID2SYM(id);
    exc = rb_class_new_instance(2, argv, rb_eNameError);
    rb_exc_raise(exc);
}

void
rb_name_error_str(VALUE str, const char *fmt, ...)
{
    VALUE exc, argv[2];
    va_list args;

    va_start(args, fmt);
    argv[0] = rb_vsprintf(fmt, args);
    va_end(args);

    argv[1] = str;
    exc = rb_class_new_instance(2, argv, rb_eNameError);
    rb_exc_raise(exc);
}

/*
 * call-seq:
 *   NameError.new(msg [, name])  -> name_error
 *
 * Construct a new NameError exception. If given the <i>name</i>
 * parameter may subsequently be examined using the <code>NameError.name</code>
 * method.
 */

static VALUE
name_err_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE name;

    name = (argc > 1) ? argv[--argc] : Qnil;
    rb_call_super(argc, argv);
    rb_iv_set(self, "name", name);
    return self;
}

/*
 *  call-seq:
 *    name_error.name    ->  string or nil
 *
 *  Return the name associated with this NameError exception.
 */

static VALUE
name_err_name(VALUE self)
{
    return rb_attr_get(self, rb_intern("name"));
}

/*
 * call-seq:
 *   NoMethodError.new(msg, name [, args])  -> no_method_error
 *
 * Construct a NoMethodError exception for a method of the given name
 * called with the given arguments. The name may be accessed using
 * the <code>#name</code> method on the resulting object, and the
 * arguments using the <code>#args</code> method.
 */

static VALUE
nometh_err_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE args = (argc > 2) ? argv[--argc] : Qnil;
    name_err_initialize(argc, argv, self);
    rb_iv_set(self, "args", args);
    return self;
}

/* :nodoc: */
#define NAME_ERR_MESG_COUNT 3

static void
name_err_mesg_mark(void *p)
{
    VALUE *ptr = p;
    rb_gc_mark_locations(ptr, ptr+NAME_ERR_MESG_COUNT);
}

#define name_err_mesg_free RUBY_TYPED_DEFAULT_FREE

static size_t
name_err_mesg_memsize(const void *p)
{
    return p ? (NAME_ERR_MESG_COUNT * sizeof(VALUE)) : 0;
}

static const rb_data_type_t name_err_mesg_data_type = {
    "name_err_mesg",
    {
	name_err_mesg_mark,
	name_err_mesg_free,
	name_err_mesg_memsize,
    },
    NULL, NULL, RUBY_TYPED_FREE_IMMEDIATELY
};

/* :nodoc: */
VALUE
rb_name_err_mesg_new(VALUE obj, VALUE mesg, VALUE recv, VALUE method)
{
    VALUE *ptr = ALLOC_N(VALUE, NAME_ERR_MESG_COUNT);
    VALUE result;

    ptr[0] = mesg;
    ptr[1] = recv;
    ptr[2] = method;
    result = TypedData_Wrap_Struct(rb_cNameErrorMesg, &name_err_mesg_data_type, ptr);
    RB_GC_GUARD(mesg);
    RB_GC_GUARD(recv);
    RB_GC_GUARD(method);
    return result;
}

/* :nodoc: */
static VALUE
name_err_mesg_equal(VALUE obj1, VALUE obj2)
{
    VALUE *ptr1, *ptr2;
    int i;

    if (obj1 == obj2) return Qtrue;
    if (rb_obj_class(obj2) != rb_cNameErrorMesg)
	return Qfalse;

    TypedData_Get_Struct(obj1, VALUE, &name_err_mesg_data_type, ptr1);
    TypedData_Get_Struct(obj2, VALUE, &name_err_mesg_data_type, ptr2);
    for (i=0; i<NAME_ERR_MESG_COUNT; i++) {
	if (!rb_equal(ptr1[i], ptr2[i]))
	    return Qfalse;
    }
    return Qtrue;
}

/* :nodoc: */
static VALUE
name_err_mesg_to_str(VALUE obj)
{
    VALUE *ptr, mesg;
    TypedData_Get_Struct(obj, VALUE, &name_err_mesg_data_type, ptr);

    mesg = ptr[0];
    if (NIL_P(mesg)) return Qnil;
    else {
	const char *desc = 0;
	VALUE d = 0, args[NAME_ERR_MESG_COUNT];
	int state = 0;

	obj = ptr[1];
	switch (obj) {
	  case Qnil:
	    desc = "nil";
	    break;
	  case Qtrue:
	    desc = "true";
	    break;
	  case Qfalse:
	    desc = "false";
	    break;
	  default:
	    d = rb_protect(rb_inspect, obj, &state);
	    if (state)
		rb_set_errinfo(Qnil);
	    if (NIL_P(d) || RSTRING_LEN(d) > 65) {
		d = rb_any_to_s(obj);
	    }
	    desc = RSTRING_PTR(d);
	    break;
	}
	if (desc && desc[0] != '#') {
	    d = d ? rb_str_dup(d) : rb_str_new2(desc);
	    rb_str_cat2(d, ":");
	    rb_str_append(d, rb_class_name(CLASS_OF(obj)));
	}
	args[0] = mesg;
	args[1] = ptr[2];
	args[2] = d;
	mesg = rb_f_sprintf(NAME_ERR_MESG_COUNT, args);
    }
    return mesg;
}

/* :nodoc: */
static VALUE
name_err_mesg_dump(VALUE obj, VALUE limit)
{
    return name_err_mesg_to_str(obj);
}

/* :nodoc: */
static VALUE
name_err_mesg_load(VALUE klass, VALUE str)
{
    return str;
}

/*
 * call-seq:
 *   no_method_error.args  -> obj
 *
 * Return the arguments passed in as the third parameter to
 * the constructor.
 */

static VALUE
nometh_err_args(VALUE self)
{
    return rb_attr_get(self, rb_intern("args"));
}

void
rb_invalid_str(const char *str, const char *type)
{
    VALUE s = rb_str_new2(str);

    rb_raise(rb_eArgError, "invalid value for %s: %+"PRIsVALUE, type, s);
}

/*
 *  Document-module: Errno
 *
 *  Ruby exception objects are subclasses of <code>Exception</code>.
 *  However, operating systems typically report errors using plain
 *  integers. Module <code>Errno</code> is created dynamically to map
 *  these operating system errors to Ruby classes, with each error
 *  number generating its own subclass of <code>SystemCallError</code>.
 *  As the subclass is created in module <code>Errno</code>, its name
 *  will start <code>Errno::</code>.
 *
 *  The names of the <code>Errno::</code> classes depend on
 *  the environment in which Ruby runs. On a typical Unix or Windows
 *  platform, there are <code>Errno</code> classes such as
 *  <code>Errno::EACCES</code>, <code>Errno::EAGAIN</code>,
 *  <code>Errno::EINTR</code>, and so on.
 *
 *  The integer operating system error number corresponding to a
 *  particular error is available as the class constant
 *  <code>Errno::</code><em>error</em><code>::Errno</code>.
 *
 *     Errno::EACCES::Errno   #=> 13
 *     Errno::EAGAIN::Errno   #=> 11
 *     Errno::EINTR::Errno    #=> 4
 *
 *  The full list of operating system errors on your particular platform
 *  are available as the constants of <code>Errno</code>.
 *
 *     Errno.constants   #=> :E2BIG, :EACCES, :EADDRINUSE, :EADDRNOTAVAIL, ...
 */

static st_table *syserr_tbl;

static VALUE
set_syserr(int n, const char *name)
{
    st_data_t error;

    if (!st_lookup(syserr_tbl, n, &error)) {
	error = rb_define_class_under(rb_mErrno, name, rb_eSystemCallError);

	/* capture nonblock errnos for WaitReadable/WaitWritable subclasses */
	switch (n) {
	    case EAGAIN:
	        rb_eEAGAIN = error;

#if EAGAIN != EWOULDBLOCK
                break;
	    case EWOULDBLOCK:
#endif

		rb_eEWOULDBLOCK = error;
		break;
	    case EINPROGRESS:
		rb_eEINPROGRESS = error;
		break;
	}

	rb_define_const(error, "Errno", INT2NUM(n));
	st_add_direct(syserr_tbl, n, error);
    }
    else {
	rb_define_const(rb_mErrno, name, error);
    }
    return error;
}

static VALUE
get_syserr(int n)
{
    st_data_t error;

    if (!st_lookup(syserr_tbl, n, &error)) {
	char name[8];	/* some Windows' errno have 5 digits. */

	snprintf(name, sizeof(name), "E%03d", n);
	error = set_syserr(n, name);
    }
    return error;
}

/*
 * call-seq:
 *   SystemCallError.new(msg, errno)  -> system_call_error_subclass
 *
 * If _errno_ corresponds to a known system error code, constructs
 * the appropriate <code>Errno</code> class for that error, otherwise
 * constructs a generic <code>SystemCallError</code> object. The
 * error number is subsequently available via the <code>errno</code>
 * method.
 */

static VALUE
syserr_initialize(int argc, VALUE *argv, VALUE self)
{
#if !defined(_WIN32)
    char *strerror();
#endif
    const char *err;
    VALUE mesg, error, func;
    VALUE klass = rb_obj_class(self);

    if (klass == rb_eSystemCallError) {
	st_data_t data = (st_data_t)klass;
	rb_scan_args(argc, argv, "12", &mesg, &error, &func);
	if (argc == 1 && FIXNUM_P(mesg)) {
	    error = mesg; mesg = Qnil;
	}
	if (!NIL_P(error) && st_lookup(syserr_tbl, NUM2LONG(error), &data)) {
	    klass = (VALUE)data;
	    /* change class */
	    if (!RB_TYPE_P(self, T_OBJECT)) { /* insurance to avoid type crash */
		rb_raise(rb_eTypeError, "invalid instance type");
	    }
	    RBASIC_SET_CLASS(self, klass);
	}
    }
    else {
	rb_scan_args(argc, argv, "02", &mesg, &func);
	error = rb_const_get(klass, rb_intern("Errno"));
    }
    if (!NIL_P(error)) err = strerror(NUM2INT(error));
    else err = "unknown error";
    if (!NIL_P(mesg)) {
	rb_encoding *le = rb_locale_encoding();
	VALUE str = StringValue(mesg);
	rb_encoding *me = rb_enc_get(mesg);

	if (NIL_P(func))
	    mesg = rb_sprintf("%s - %"PRIsVALUE, err, mesg);
	else
	    mesg = rb_sprintf("%s @ %"PRIsVALUE" - %"PRIsVALUE, err, func, mesg);
	if (le != me && rb_enc_asciicompat(me)) {
	    le = me;
	}/* else assume err is non ASCII string. */
	OBJ_INFECT(mesg, str);
	rb_enc_associate(mesg, le);
    }
    else {
	mesg = rb_str_new2(err);
	rb_enc_associate(mesg, rb_locale_encoding());
    }
    rb_call_super(1, &mesg);
    rb_iv_set(self, "errno", error);
    return self;
}

/*
 * call-seq:
 *   system_call_error.errno   -> fixnum
 *
 * Return this SystemCallError's error number.
 */

static VALUE
syserr_errno(VALUE self)
{
    return rb_attr_get(self, rb_intern("errno"));
}

/*
 * call-seq:
 *   system_call_error === other  -> true or false
 *
 * Return +true+ if the receiver is a generic +SystemCallError+, or
 * if the error numbers +self+ and _other_ are the same.
 */

static VALUE
syserr_eqq(VALUE self, VALUE exc)
{
    VALUE num, e;
    ID en;

    CONST_ID(en, "errno");

    if (!rb_obj_is_kind_of(exc, rb_eSystemCallError)) {
	if (!rb_respond_to(exc, en)) return Qfalse;
    }
    else if (self == rb_eSystemCallError) return Qtrue;

    num = rb_attr_get(exc, rb_intern("errno"));
    if (NIL_P(num)) {
	num = rb_funcall(exc, en, 0, 0);
    }
    e = rb_const_get(self, rb_intern("Errno"));
    if (FIXNUM_P(num) ? num == e : rb_equal(num, e))
	return Qtrue;
    return Qfalse;
}


/*
 *  Document-class: StandardError
 *
 *  The most standard error types are subclasses of StandardError. A
 *  rescue clause without an explicit Exception class will rescue all
 *  StandardErrors (and only those).
 *
 *     def foo
 *       raise "Oups"
 *     end
 *     foo rescue "Hello"   #=> "Hello"
 *
 *  On the other hand:
 *
 *     require 'does/not/exist' rescue "Hi"
 *
 *  <em>raises the exception:</em>
 *
 *     LoadError: no such file to load -- does/not/exist
 *
 */

/*
 *  Document-class: SystemExit
 *
 *  Raised by +exit+ to initiate the termination of the script.
 */

/*
 *  Document-class: SignalException
 *
 *  Raised when a signal is received.
 *
 *     begin
 *       Process.kill('HUP',Process.pid)
 *       sleep # wait for receiver to handle signal sent by Process.kill
 *     rescue SignalException => e
 *       puts "received Exception #{e}"
 *     end
 *
 *  <em>produces:</em>
 *
 *     received Exception SIGHUP
 */

/*
 *  Document-class: Interrupt
 *
 *  Raised with the interrupt signal is received, typically because the
 *  user pressed on Control-C (on most posix platforms). As such, it is a
 *  subclass of +SignalException+.
 *
 *     begin
 *       puts "Press ctrl-C when you get bored"
 *       loop {}
 *     rescue Interrupt => e
 *       puts "Note: You will typically use Signal.trap instead."
 *     end
 *
 *  <em>produces:</em>
 *
 *     Press ctrl-C when you get bored
 *
 *  <em>then waits until it is interrupted with Control-C and then prints:</em>
 *
 *     Note: You will typically use Signal.trap instead.
 */

/*
 *  Document-class: TypeError
 *
 *  Raised when encountering an object that is not of the expected type.
 *
 *     [1, 2, 3].first("two")
 *
 *  <em>raises the exception:</em>
 *
 *     TypeError: no implicit conversion of String into Integer
 *
 */

/*
 *  Document-class: ArgumentError
 *
 *  Raised when the arguments are wrong and there isn't a more specific
 *  Exception class.
 *
 *  Ex: passing the wrong number of arguments
 *
 *     [1, 2, 3].first(4, 5)
 *
 *  <em>raises the exception:</em>
 *
 *     ArgumentError: wrong number of arguments (2 for 1)
 *
 *  Ex: passing an argument that is not acceptable:
 *
 *     [1, 2, 3].first(-4)
 *
 *  <em>raises the exception:</em>
 *
 *     ArgumentError: negative array size
 */

/*
 *  Document-class: IndexError
 *
 *  Raised when the given index is invalid.
 *
 *     a = [:foo, :bar]
 *     a.fetch(0)   #=> :foo
 *     a[4]         #=> nil
 *     a.fetch(4)   #=> IndexError: index 4 outside of array bounds: -2...2
 *
 */

/*
 *  Document-class: KeyError
 *
 *  Raised when the specified key is not found. It is a subclass of
 *  IndexError.
 *
 *     h = {"foo" => :bar}
 *     h.fetch("foo") #=> :bar
 *     h.fetch("baz") #=> KeyError: key not found: "baz"
 *
 */

/*
 *  Document-class: RangeError
 *
 *  Raised when a given numerical value is out of range.
 *
 *     [1, 2, 3].drop(1 << 100)
 *
 *  <em>raises the exception:</em>
 *
 *     RangeError: bignum too big to convert into `long'
 */

/*
 *  Document-class: ScriptError
 *
 *  ScriptError is the superclass for errors raised when a script
 *  can not be executed because of a +LoadError+,
 *  +NotImplementedError+ or a +SyntaxError+. Note these type of
 *  +ScriptErrors+ are not +StandardError+ and will not be
 *  rescued unless it is specified explicitly (or its ancestor
 *  +Exception+).
 */

/*
 *  Document-class: SyntaxError
 *
 *  Raised when encountering Ruby code with an invalid syntax.
 *
 *     eval("1+1=2")
 *
 *  <em>raises the exception:</em>
 *
 *     SyntaxError: (eval):1: syntax error, unexpected '=', expecting $end
 */

/*
 *  Document-class: LoadError
 *
 *  Raised when a file required (a Ruby script, extension library, ...)
 *  fails to load.
 *
 *     require 'this/file/does/not/exist'
 *
 *  <em>raises the exception:</em>
 *
 *     LoadError: no such file to load -- this/file/does/not/exist
 */

/*
 *  Document-class: NotImplementedError
 *
 *  Raised when a feature is not implemented on the current platform. For
 *  example, methods depending on the +fsync+ or +fork+ system calls may
 *  raise this exception if the underlying operating system or Ruby
 *  runtime does not support them.
 *
 *  Note that if +fork+ raises a +NotImplementedError+, then
 *  <code>respond_to?(:fork)</code> returns +false+.
 */

/*
 *  Document-class: NameError
 *
 *  Raised when a given name is invalid or undefined.
 *
 *     puts foo
 *
 *  <em>raises the exception:</em>
 *
 *     NameError: undefined local variable or method `foo' for main:Object
 *
 *  Since constant names must start with a capital:
 *
 *     Fixnum.const_set :answer, 42
 *
 *  <em>raises the exception:</em>
 *
 *     NameError: wrong constant name answer
 */

/*
 *  Document-class: NoMethodError
 *
 *  Raised when a method is called on a receiver which doesn't have it
 *  defined and also fails to respond with +method_missing+.
 *
 *     "hello".to_ary
 *
 *  <em>raises the exception:</em>
 *
 *     NoMethodError: undefined method `to_ary' for "hello":String
 */

/*
 *  Document-class: RuntimeError
 *
 *  A generic error class raised when an invalid operation is attempted.
 *
 *     [1, 2, 3].freeze << 4
 *
 *  <em>raises the exception:</em>
 *
 *     RuntimeError: can't modify frozen array
 *
 *  Kernel.raise will raise a RuntimeError if no Exception class is
 *  specified.
 *
 *     raise "ouch"
 *
 *  <em>raises the exception:</em>
 *
 *     RuntimeError: ouch
 */

/*
 *  Document-class: SecurityError
 *
 *  Raised when attempting a potential unsafe operation, typically when
 *  the $SAFE level is raised above 0.
 *
 *     foo = "bar"
 *     proc = Proc.new do
 *       $SAFE = 3
 *       foo.untaint
 *     end
 *     proc.call
 *
 *  <em>raises the exception:</em>
 *
 *     SecurityError: Insecure: Insecure operation `untaint' at level 3
 */

/*
 *  Document-class: NoMemoryError
 *
 *  Raised when memory allocation fails.
 */

/*
 *  Document-class: SystemCallError
 *
 *  SystemCallError is the base class for all low-level
 *  platform-dependent errors.
 *
 *  The errors available on the current platform are subclasses of
 *  SystemCallError and are defined in the Errno module.
 *
 *     File.open("does/not/exist")
 *
 *  <em>raises the exception:</em>
 *
 *     Errno::ENOENT: No such file or directory - does/not/exist
 */

/*
 * Document-class: EncodingError
 *
 * EncodingError is the base class for encoding errors.
 */

/*
 *  Document-class: Encoding::CompatibilityError
 *
 *  Raised by Encoding and String methods when the source encoding is
 *  incompatible with the target encoding.
 */

/*
 * Document-class: fatal
 *
 * fatal is an Exception that is raised when ruby has encountered a fatal
 * error and must exit.  You are not able to rescue fatal.
 */

/*
 * Document-class: NameError::message
 * :nodoc:
 */

/*
 *  Descendants of class Exception are used to communicate between
 *  Kernel#raise and +rescue+ statements in <code>begin ... end</code> blocks.
 *  Exception objects carry information about the exception -- its type (the
 *  exception's class name), an optional descriptive string, and optional
 *  traceback information.  Exception subclasses may add additional
 *  information like NameError#name.
 *
 *  Programs may make subclasses of Exception, typically of StandardError or
 *  RuntimeError, to provide custom classes and add additional information.
 *  See the subclass list below for defaults for +raise+ and +rescue+.
 *
 *  When an exception has been raised but not yet handled (in +rescue+,
 *  +ensure+, +at_exit+ and +END+ blocks) the global variable <code>$!</code>
 *  will contain the current exception and <code>$@</code> contains the
 *  current exception's backtrace.
 *
 *  It is recommended that a library should have one subclass of StandardError
 *  or RuntimeError and have specific exception types inherit from it.  This
 *  allows the user to rescue a generic exception type to catch all exceptions
 *  the library may raise even if future versions of the library add new
 *  exception subclasses.
 *
 *  For example:
 *
 *    class MyLibrary
 *      class Error < RuntimeError
 *      end
 *
 *      class WidgetError < Error
 *      end
 *
 *      class FrobError < Error
 *      end
 *
 *    end
 *
 *  To handle both WidgetError and FrobError the library user can rescue
 *  MyLibrary::Error.
 *
 *  The built-in subclasses of Exception are:
 *
 *  * NoMemoryError
 *  * ScriptError
 *    * LoadError
 *    * NotImplementedError
 *    * SyntaxError
 *  * SecurityError
 *  * SignalException
 *    * Interrupt
 *  * StandardError -- default for +rescue+
 *    * ArgumentError
 *    * EncodingError
 *    * FiberError
 *    * IOError
 *      * EOFError
 *    * IndexError
 *      * KeyError
 *      * StopIteration
 *    * LocalJumpError
 *    * NameError
 *      * NoMethodError
 *    * RangeError
 *      * FloatDomainError
 *    * RegexpError
 *    * RuntimeError -- default for +raise+
 *    * SystemCallError
 *      * Errno::*
 *    * ThreadError
 *    * TypeError
 *    * ZeroDivisionError
 *  * SystemExit
 *  * SystemStackError
 *  * fatal -- impossible to rescue
 */

void
Init_Exception(void)
{
    rb_eException   = rb_define_class("Exception", rb_cObject);
    rb_define_singleton_method(rb_eException, "exception", rb_class_new_instance, -1);
    rb_define_method(rb_eException, "exception", exc_exception, -1);
    rb_define_method(rb_eException, "initialize", exc_initialize, -1);
    rb_define_method(rb_eException, "==", exc_equal, 1);
    rb_define_method(rb_eException, "to_s", exc_to_s, 0);
    rb_define_method(rb_eException, "message", exc_message, 0);
    rb_define_method(rb_eException, "inspect", exc_inspect, 0);
    rb_define_method(rb_eException, "backtrace", exc_backtrace, 0);
    rb_define_method(rb_eException, "backtrace_locations", exc_backtrace_locations, 0);
    rb_define_method(rb_eException, "set_backtrace", exc_set_backtrace, 1);
    rb_define_method(rb_eException, "cause", exc_cause, 0);

    rb_eSystemExit  = rb_define_class("SystemExit", rb_eException);
    rb_define_method(rb_eSystemExit, "initialize", exit_initialize, -1);
    rb_define_method(rb_eSystemExit, "status", exit_status, 0);
    rb_define_method(rb_eSystemExit, "success?", exit_success_p, 0);

    rb_eFatal  	    = rb_define_class("fatal", rb_eException);
    rb_eSignal      = rb_define_class("SignalException", rb_eException);
    rb_eInterrupt   = rb_define_class("Interrupt", rb_eSignal);

    rb_eStandardError = rb_define_class("StandardError", rb_eException);
    rb_eTypeError     = rb_define_class("TypeError", rb_eStandardError);
    rb_eArgError      = rb_define_class("ArgumentError", rb_eStandardError);
    rb_eIndexError    = rb_define_class("IndexError", rb_eStandardError);
    rb_eKeyError      = rb_define_class("KeyError", rb_eIndexError);
    rb_eRangeError    = rb_define_class("RangeError", rb_eStandardError);

    rb_eScriptError = rb_define_class("ScriptError", rb_eException);
    rb_eSyntaxError = rb_define_class("SyntaxError", rb_eScriptError);

    rb_eLoadError   = rb_define_class("LoadError", rb_eScriptError);
    /* the path failed to load */
    rb_attr(rb_eLoadError, rb_intern_const("path"), 1, 0, Qfalse);

    rb_eNotImpError = rb_define_class("NotImplementedError", rb_eScriptError);

    rb_eNameError     = rb_define_class("NameError", rb_eStandardError);
    rb_define_method(rb_eNameError, "initialize", name_err_initialize, -1);
    rb_define_method(rb_eNameError, "name", name_err_name, 0);
    rb_cNameErrorMesg = rb_define_class_under(rb_eNameError, "message", rb_cData);
    rb_define_singleton_method(rb_cNameErrorMesg, "!", rb_name_err_mesg_new, NAME_ERR_MESG_COUNT);
    rb_define_method(rb_cNameErrorMesg, "==", name_err_mesg_equal, 1);
    rb_define_method(rb_cNameErrorMesg, "to_str", name_err_mesg_to_str, 0);
    rb_define_method(rb_cNameErrorMesg, "_dump", name_err_mesg_dump, 1);
    rb_define_singleton_method(rb_cNameErrorMesg, "_load", name_err_mesg_load, 1);
    rb_eNoMethodError = rb_define_class("NoMethodError", rb_eNameError);
    rb_define_method(rb_eNoMethodError, "initialize", nometh_err_initialize, -1);
    rb_define_method(rb_eNoMethodError, "args", nometh_err_args, 0);

    rb_eRuntimeError = rb_define_class("RuntimeError", rb_eStandardError);
    rb_eSecurityError = rb_define_class("SecurityError", rb_eException);
    rb_eNoMemError = rb_define_class("NoMemoryError", rb_eException);
    rb_eEncodingError = rb_define_class("EncodingError", rb_eStandardError);
    rb_eEncCompatError = rb_define_class_under(rb_cEncoding, "CompatibilityError", rb_eEncodingError);

    syserr_tbl = st_init_numtable();
    rb_eSystemCallError = rb_define_class("SystemCallError", rb_eStandardError);
    rb_define_method(rb_eSystemCallError, "initialize", syserr_initialize, -1);
    rb_define_method(rb_eSystemCallError, "errno", syserr_errno, 0);
    rb_define_singleton_method(rb_eSystemCallError, "===", syserr_eqq, 1);

    rb_mErrno = rb_define_module("Errno");

    rb_define_global_function("warn", rb_warn_m, -1);
}

void
rb_enc_raise(rb_encoding *enc, VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_enc_vsprintf(enc, fmt, args);
    va_end(args);

    rb_exc_raise(rb_exc_new3(exc, mesg));
}

void
rb_raise(VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_vsprintf(fmt, args);
    va_end(args);
    rb_exc_raise(rb_exc_new3(exc, mesg));
}

NORETURN(static void raise_loaderror(VALUE path, VALUE mesg));

static void
raise_loaderror(VALUE path, VALUE mesg)
{
    VALUE err = rb_exc_new3(rb_eLoadError, mesg);
    rb_ivar_set(err, rb_intern("@path"), path);
    rb_exc_raise(err);
}

void
rb_loaderror(const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_enc_vsprintf(rb_locale_encoding(), fmt, args);
    va_end(args);
    raise_loaderror(Qnil, mesg);
}

void
rb_loaderror_with_path(VALUE path, const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_enc_vsprintf(rb_locale_encoding(), fmt, args);
    va_end(args);
    raise_loaderror(path, mesg);
}

void
rb_notimplement(void)
{
    rb_raise(rb_eNotImpError,
	     "%s() function is unimplemented on this machine",
	     rb_id2name(rb_frame_this_func()));
}

void
rb_fatal(const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    va_start(args, fmt);
    mesg = rb_vsprintf(fmt, args);
    va_end(args);

    rb_exc_fatal(rb_exc_new3(rb_eFatal, mesg));
}

static VALUE
make_errno_exc(const char *mesg)
{
    int n = errno;

    errno = 0;
    if (n == 0) {
	rb_bug("rb_sys_fail(%s) - errno == 0", mesg ? mesg : "");
    }
    return rb_syserr_new(n, mesg);
}

static VALUE
make_errno_exc_str(VALUE mesg)
{
    int n = errno;

    errno = 0;
    if (!mesg) mesg = Qnil;
    if (n == 0) {
	const char *s = !NIL_P(mesg) ? RSTRING_PTR(mesg) : "";
	rb_bug("rb_sys_fail_str(%s) - errno == 0", s);
    }
    return rb_syserr_new_str(n, mesg);
}

VALUE
rb_syserr_new(int n, const char *mesg)
{
    VALUE arg;
    arg = mesg ? rb_str_new2(mesg) : Qnil;
    return rb_syserr_new_str(n, arg);
}

VALUE
rb_syserr_new_str(int n, VALUE arg)
{
    return rb_class_new_instance(1, &arg, get_syserr(n));
}

void
rb_syserr_fail(int e, const char *mesg)
{
    rb_exc_raise(rb_syserr_new(e, mesg));
}

void
rb_syserr_fail_str(int e, VALUE mesg)
{
    rb_exc_raise(rb_syserr_new_str(e, mesg));
}

void
rb_sys_fail(const char *mesg)
{
    rb_exc_raise(make_errno_exc(mesg));
}

void
rb_sys_fail_str(VALUE mesg)
{
    rb_exc_raise(make_errno_exc_str(mesg));
}

#ifdef RUBY_FUNCTION_NAME_STRING
void
rb_sys_fail_path_in(const char *func_name, VALUE path)
{
    int n = errno;

    errno = 0;
    rb_syserr_fail_path_in(func_name, n, path);
}

void
rb_syserr_fail_path_in(const char *func_name, int n, VALUE path)
{
    VALUE args[2];

    if (!path) path = Qnil;
    if (n == 0) {
	const char *s = !NIL_P(path) ? RSTRING_PTR(path) : "";
	if (!func_name) func_name = "(null)";
	rb_bug("rb_sys_fail_path_in(%s, %s) - errno == 0",
	       func_name, s);
    }
    args[0] = path;
    args[1] = rb_str_new_cstr(func_name);
    rb_exc_raise(rb_class_new_instance(2, args, get_syserr(n)));
}
#endif

void
rb_mod_sys_fail(VALUE mod, const char *mesg)
{
    VALUE exc = make_errno_exc(mesg);
    rb_extend_object(exc, mod);
    rb_exc_raise(exc);
}

void
rb_mod_sys_fail_str(VALUE mod, VALUE mesg)
{
    VALUE exc = make_errno_exc_str(mesg);
    rb_extend_object(exc, mod);
    rb_exc_raise(exc);
}

void
rb_mod_syserr_fail(VALUE mod, int e, const char *mesg)
{
    VALUE exc = rb_syserr_new(e, mesg);
    rb_extend_object(exc, mod);
    rb_exc_raise(exc);
}

void
rb_mod_syserr_fail_str(VALUE mod, int e, VALUE mesg)
{
    VALUE exc = rb_syserr_new_str(e, mesg);
    rb_extend_object(exc, mod);
    rb_exc_raise(exc);
}

void
rb_sys_warning(const char *fmt, ...)
{
    char buf[BUFSIZ];
    va_list args;
    int errno_save;

    errno_save = errno;

    if (!RTEST(ruby_verbose)) return;

    snprintf(buf, BUFSIZ, "warning: %s", fmt);
    snprintf(buf+strlen(buf), BUFSIZ-strlen(buf), ": %s", strerror(errno_save));

    va_start(args, fmt);
    warn_print(buf, args);
    va_end(args);
    errno = errno_save;
}

void
rb_load_fail(VALUE path, const char *err)
{
    VALUE mesg = rb_str_buf_new_cstr(err);
    rb_str_cat2(mesg, " -- ");
    rb_str_append(mesg, path);	/* should be ASCII compatible */
    raise_loaderror(path, mesg);
}

void
rb_error_frozen(const char *what)
{
    rb_raise(rb_eRuntimeError, "can't modify frozen %s", what);
}

void
rb_error_frozen_object(VALUE frozen_obj)
{
    rb_raise(rb_eRuntimeError, "can't modify frozen %"PRIsVALUE,
	     CLASS_OF(frozen_obj));
}

#undef rb_check_frozen
void
rb_check_frozen(VALUE obj)
{
    rb_check_frozen_internal(obj);
}

void
rb_error_untrusted(VALUE obj)
{
}

#undef rb_check_trusted
void
rb_check_trusted(VALUE obj)
{
}

void
rb_check_copyable(VALUE obj, VALUE orig)
{
    if (!FL_ABLE(obj)) return;
    rb_check_frozen_internal(obj);
    if (!FL_ABLE(orig)) return;
    if ((~RBASIC(obj)->flags & RBASIC(orig)->flags) & FL_TAINT) {
	if (rb_safe_level() > 0) {
	    rb_raise(rb_eSecurityError, "Insecure: can't modify %"PRIsVALUE,
		     RBASIC(obj)->klass);
	}
    }
}

void
Init_syserr(void)
{
    rb_eNOERROR = set_syserr(0, "NOERROR");
#define defined_error(name, num) set_syserr((num), (name));
#define undefined_error(name) set_syserr(0, (name));
#include "known_errors.inc"
#undef defined_error
#undef undefined_error
}
