/**********************************************************************

  error.c -

  $Author$
  created at: Mon Aug  9 16:11:34 JST 1993

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "ruby/internal/config.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>

#ifdef HAVE_STDLIB_H
# include <stdlib.h>
#endif

#ifdef HAVE_UNISTD_H
# include <unistd.h>
#endif

#if defined __APPLE__
# include <AvailabilityMacros.h>
#endif

#include "internal.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/io.h"
#include "internal/load.h"
#include "internal/object.h"
#include "internal/symbol.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "ruby/encoding.h"
#include "ruby/st.h"
#include "ruby_assert.h"
#include "vm_core.h"

#include "builtin.h"

/*!
 * \defgroup exception Exception handlings
 * \{
 */

#ifndef EXIT_SUCCESS
#define EXIT_SUCCESS 0
#endif

#ifndef WIFEXITED
#define WIFEXITED(status) 1
#endif

#ifndef WEXITSTATUS
#define WEXITSTATUS(status) (status)
#endif

VALUE rb_iseqw_local_variables(VALUE iseqval);
VALUE rb_iseqw_new(const rb_iseq_t *);
int rb_str_end_with_asciichar(VALUE str, int c);

long rb_backtrace_length_limit = -1;
VALUE rb_eEAGAIN;
VALUE rb_eEWOULDBLOCK;
VALUE rb_eEINPROGRESS;
static VALUE rb_mWarning;
static VALUE rb_cWarningBuffer;

static ID id_warn;
static ID id_category;
static VALUE sym_category;
static VALUE warning_categories;

extern const char ruby_description[];

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
err_vcatf(VALUE str, const char *pre, const char *file, int line,
	  const char *fmt, va_list args)
{
    if (file) {
	rb_str_cat2(str, file);
	if (line) rb_str_catf(str, ":%d", line);
	rb_str_cat2(str, ": ");
    }
    if (pre) rb_str_cat2(str, pre);
    rb_str_vcatf(str, fmt, args);
    return str;
}

VALUE
rb_syntax_error_append(VALUE exc, VALUE file, int line, int column,
		       rb_encoding *enc, const char *fmt, va_list args)
{
    const char *fn = NIL_P(file) ? NULL : RSTRING_PTR(file);
    if (!exc) {
	VALUE mesg = rb_enc_str_new(0, 0, enc);
	err_vcatf(mesg, NULL, fn, line, fmt, args);
	rb_str_cat2(mesg, "\n");
	rb_write_error_str(mesg);
    }
    else {
	VALUE mesg;
	if (NIL_P(exc)) {
	    mesg = rb_enc_str_new(0, 0, enc);
	    exc = rb_class_new_instance(1, &mesg, rb_eSyntaxError);
	}
	else {
	    mesg = rb_attr_get(exc, idMesg);
	    if (RSTRING_LEN(mesg) > 0 && *(RSTRING_END(mesg)-1) != '\n')
		rb_str_cat_cstr(mesg, "\n");
	}
	err_vcatf(mesg, NULL, fn, line, fmt, args);
    }

    return exc;
}

static unsigned int warning_disabled_categories = (
    1U << RB_WARN_CATEGORY_DEPRECATED |
    0);

static unsigned int
rb_warning_category_mask(VALUE category)
{
    return 1U << rb_warning_category_from_name(category);
}

rb_warning_category_t
rb_warning_category_from_name(VALUE category)
{
    rb_warning_category_t cat = RB_WARN_CATEGORY_NONE;
    Check_Type(category, T_SYMBOL);
    if (category == ID2SYM(rb_intern("deprecated"))) {
        cat = RB_WARN_CATEGORY_DEPRECATED;
    }
    else if (category == ID2SYM(rb_intern("experimental"))) {
        cat = RB_WARN_CATEGORY_EXPERIMENTAL;
    }
    else {
        rb_raise(rb_eArgError, "unknown category: %"PRIsVALUE, category);
    }
    return cat;
}

void
rb_warning_category_update(unsigned int mask, unsigned int bits)
{
    warning_disabled_categories &= ~mask;
    warning_disabled_categories |= mask & ~bits;
}

MJIT_FUNC_EXPORTED bool
rb_warning_category_enabled_p(rb_warning_category_t category)
{
    return !(warning_disabled_categories & (1U << category));
}

/*
 * call-seq
 *    Warning[category]  -> true or false
 *
 * Returns the flag to show the warning messages for +category+.
 * Supported categories are:
 *
 * +:deprecated+ :: deprecation warnings
 * * assignment of non-nil value to <code>$,</code> and <code>$;</code>
 * * keyword arguments
 * * proc/lambda without block
 * etc.
 *
 * +:experimental+ :: experimental features
 * * Pattern matching
 */

static VALUE
rb_warning_s_aref(VALUE mod, VALUE category)
{
    rb_warning_category_t cat = rb_warning_category_from_name(category);
    if (rb_warning_category_enabled_p(cat))
        return Qtrue;
    return Qfalse;
}

/*
 * call-seq
 *    Warning[category] = flag -> flag
 *
 * Sets the warning flags for +category+.
 * See Warning.[] for the categories.
 */

static VALUE
rb_warning_s_aset(VALUE mod, VALUE category, VALUE flag)
{
    unsigned int mask = rb_warning_category_mask(category);
    unsigned int disabled = warning_disabled_categories;
    if (!RTEST(flag))
        disabled |= mask;
    else
        disabled &= ~mask;
    warning_disabled_categories = disabled;
    return flag;
}

/*
 * call-seq:
 *    warn(msg, category: nil)  -> nil
 *
 * Writes warning message +msg+ to $stderr. This method is called by
 * Ruby for all emitted warnings. A +category+ may be included with
 * the warning, but is ignored by default.
 *
 * See the documentation of the Warning module for how to customize this.
 */

static VALUE
rb_warning_s_warn(int argc, VALUE *argv, VALUE mod)
{
    VALUE str;
    VALUE opt;
    VALUE category;

    rb_scan_args(argc, argv, "1:", &str, &opt);
    if (!NIL_P(opt)) rb_get_kwargs(opt, &id_category, 0, 1, &category);

    Check_Type(str, T_STRING);
    rb_must_asciicompat(str);
    rb_write_error_str(str);
    return Qnil;
}

/*
 *  Document-module: Warning
 *
 *  The Warning module contains a single method named #warn, and the
 *  module extends itself, making Warning.warn available.
 *  Warning.warn is called for all warnings issued by Ruby.
 *  By default, warnings are printed to $stderr.
 *
 *  Changing the behavior of Warning.warn is useful to customize how warnings are
 *  handled by Ruby, for instance by filtering some warnings, and/or outputting
 *  warnings somewhere other than $stderr.
 *
 *  If you want to change the behavior of Warning.warn you should use
 *  +Warning.extend(MyNewModuleWithWarnMethod)+ and you can use `super`
 *  to get the default behavior of printing the warning to $stderr.
 *
 *  Example:
 *    module MyWarningFilter
 *      def warn(message)
 *        if /some warning I want to ignore/.matches?(message)
 *          # ignore
 *        else
 *          super(message)
 *        end
 *      end
 *    end
 *    Warning.extend MyWarningFilter
 *
 *  You should never redefine Warning#warn (the instance method), as that will
 *  then no longer provide a way to use the default behavior.
 *
 *  The +warning+ gem provides convenient ways to customize Warning.warn.
 */

static VALUE
rb_warning_warn(VALUE mod, VALUE str)
{
    return rb_funcallv(mod, id_warn, 1, &str);
}


static int
rb_warning_warn_arity(void) {
    return rb_method_entry_arity(rb_method_entry(rb_singleton_class(rb_mWarning), id_warn));
}

static VALUE
rb_warn_category(VALUE str, VALUE category)
{
    if (category != Qnil) {
        category = rb_to_symbol_type(category);
        if (rb_hash_aref(warning_categories, category) != Qtrue) {
            rb_raise(rb_eArgError, "invalid warning category used: %s", rb_id2name(SYM2ID(category)));
        }
    }

    if (rb_warning_warn_arity() == 1) {
        return rb_warning_warn(rb_mWarning, str);
    }
    else {
        VALUE args[2];
        args[0] = str;
        args[1] = rb_hash_new();
        rb_hash_aset(args[1], sym_category, category);
        return rb_funcallv_kw(rb_mWarning, id_warn, 2, args, RB_PASS_KEYWORDS);
    }
}

static void
rb_write_warning_str(VALUE str)
{
    rb_warning_warn(rb_mWarning, str);
}

static VALUE
warn_vsprintf(rb_encoding *enc, const char *file, int line, const char *fmt, va_list args)
{
    VALUE str = rb_enc_str_new(0, 0, enc);

    err_vcatf(str, "warning: ", file, line, fmt, args);
    return rb_str_cat2(str, "\n");
}

void
rb_compile_warn(const char *file, int line, const char *fmt, ...)
{
    VALUE str;
    va_list args;

    if (NIL_P(ruby_verbose)) return;

    va_start(args, fmt);
    str = warn_vsprintf(NULL, file, line, fmt, args);
    va_end(args);
    rb_write_warning_str(str);
}

/* rb_compile_warning() reports only in verbose mode */
void
rb_compile_warning(const char *file, int line, const char *fmt, ...)
{
    VALUE str;
    va_list args;

    if (!RTEST(ruby_verbose)) return;

    va_start(args, fmt);
    str = warn_vsprintf(NULL, file, line, fmt, args);
    va_end(args);
    rb_write_warning_str(str);
}

static VALUE
warning_string(rb_encoding *enc, const char *fmt, va_list args)
{
    int line;
    const char *file = rb_source_location_cstr(&line);
    return warn_vsprintf(enc, file, line, fmt, args);
}

#define with_warning_string(mesg, enc, fmt) \
    VALUE mesg; \
    va_list args; va_start(args, fmt); \
    mesg = warning_string(enc, fmt, args); \
    va_end(args);

void
rb_warn(const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
	with_warning_string(mesg, 0, fmt) {
	    rb_write_warning_str(mesg);
	}
    }
}

void
rb_category_warn(const char *category, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
        with_warning_string(mesg, 0, fmt) {
            rb_warn_category(mesg, ID2SYM(rb_intern(category)));
        }
    }
}

void
rb_enc_warn(rb_encoding *enc, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
	with_warning_string(mesg, enc, fmt) {
	    rb_write_warning_str(mesg);
	}
    }
}

/* rb_warning() reports only in verbose mode */
void
rb_warning(const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
	with_warning_string(mesg, 0, fmt) {
	    rb_write_warning_str(mesg);
	}
    }
}

/* rb_category_warning() reports only in verbose mode */
void
rb_category_warning(const char *category, const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
        with_warning_string(mesg, 0, fmt) {
            rb_warn_category(mesg, ID2SYM(rb_intern(category)));
        }
    }
}

VALUE
rb_warning_string(const char *fmt, ...)
{
    with_warning_string(mesg, 0, fmt) {
    }
    return mesg;
}

#if 0
void
rb_enc_warning(rb_encoding *enc, const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
	with_warning_string(mesg, enc, fmt) {
	    rb_write_warning_str(mesg);
	}
    }
}
#endif

void
rb_warn_deprecated(const char *fmt, const char *suggest, ...)
{
    if (NIL_P(ruby_verbose)) return;
    if (!rb_warning_category_enabled_p(RB_WARN_CATEGORY_DEPRECATED)) return;
    va_list args;
    va_start(args, suggest);
    VALUE mesg = warning_string(0, fmt, args);
    va_end(args);
    rb_str_set_len(mesg, RSTRING_LEN(mesg) - 1);
    rb_str_cat_cstr(mesg, " is deprecated");
    if (suggest) rb_str_catf(mesg, "; use %s instead", suggest);
    rb_str_cat_cstr(mesg, "\n");
    rb_warn_category(mesg, ID2SYM(rb_intern("deprecated")));
}

void
rb_warn_deprecated_to_remove(const char *fmt, const char *removal, ...)
{
    if (NIL_P(ruby_verbose)) return;
    if (!rb_warning_category_enabled_p(RB_WARN_CATEGORY_DEPRECATED)) return;
    va_list args;
    va_start(args, removal);
    VALUE mesg = warning_string(0, fmt, args);
    va_end(args);
    rb_str_set_len(mesg, RSTRING_LEN(mesg) - 1);
    rb_str_catf(mesg, " is deprecated and will be removed in Ruby %s\n", removal);
    rb_warn_category(mesg, ID2SYM(rb_intern("deprecated")));
}

static inline int
end_with_asciichar(VALUE str, int c)
{
    return RB_TYPE_P(str, T_STRING) &&
	rb_str_end_with_asciichar(str, c);
}

/* :nodoc: */
static VALUE
warning_write(int argc, VALUE *argv, VALUE buf)
{
    while (argc-- > 0) {
	rb_str_append(buf, *argv++);
    }
    return buf;
}

VALUE rb_ec_backtrace_location_ary(rb_execution_context_t *ec, long lev, long n);
static VALUE
rb_warn_m(rb_execution_context_t *ec, VALUE exc, VALUE msgs, VALUE uplevel, VALUE category)
{
    VALUE location = Qnil;
    int argc = RARRAY_LENINT(msgs);
    const VALUE *argv = RARRAY_CONST_PTR(msgs);

    if (!NIL_P(ruby_verbose) && argc > 0) {
        VALUE str = argv[0];
        if (!NIL_P(uplevel)) {
            long lev = NUM2LONG(uplevel);
            if (lev < 0) {
                rb_raise(rb_eArgError, "negative level (%ld)", lev);
            }
            location = rb_ec_backtrace_location_ary(ec, lev + 1, 1);
            if (!NIL_P(location)) {
                location = rb_ary_entry(location, 0);
            }
	}
	if (argc > 1 || !NIL_P(uplevel) || !end_with_asciichar(str, '\n')) {
	    VALUE path;
	    if (NIL_P(uplevel)) {
		str = rb_str_tmp_new(0);
	    }
	    else if (NIL_P(location) ||
		     NIL_P(path = rb_funcall(location, rb_intern("path"), 0))) {
		str = rb_str_new_cstr("warning: ");
	    }
	    else {
		str = rb_sprintf("%s:%ld: warning: ",
		    rb_string_value_ptr(&path),
		    NUM2LONG(rb_funcall(location, rb_intern("lineno"), 0)));
	    }
	    RBASIC_SET_CLASS(str, rb_cWarningBuffer);
	    rb_io_puts(argc, argv, str);
	    RBASIC_SET_CLASS(str, rb_cString);
	}

	if (exc == rb_mWarning) {
	    rb_must_asciicompat(str);
	    rb_write_error_str(str);
	}
	else {
            rb_warn_category(str, category);
	}
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

FUNC_MINIMIZED(static void bug_important_message(FILE *out, const char *const msg, size_t len));

static void
bug_important_message(FILE *out, const char *const msg, size_t len)
{
    const char *const endmsg = msg + len;
    const char *p = msg;

    if (!len) return;
    if (isatty(fileno(out))) {
	static const char red[] = "\033[;31;1;7m";
	static const char green[] = "\033[;32;7m";
	static const char reset[] = "\033[m";
	const char *e = strchr(p, '\n');
	const int w = (int)(e - p);
	do {
	    int i = (int)(e - p);
	    fputs(*p == ' ' ? green : red, out);
	    fwrite(p, 1, e - p, out);
	    for (; i < w; ++i) fputc(' ', out);
	    fputs(reset, out);
	    fputc('\n', out);
	} while ((p = e + 1) < endmsg && (e = strchr(p, '\n')) != 0 && e > p + 1);
    }
    fwrite(p, 1, endmsg - p, out);
}

static void
preface_dump(FILE *out)
{
#if defined __APPLE__
    static const char msg[] = ""
	"-- Crash Report log information "
	"--------------------------------------------\n"
	"   See Crash Report log file under the one of following:\n"
# if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6
	"     * ~/Library/Logs/CrashReporter\n"
	"     * /Library/Logs/CrashReporter\n"
# endif
	"     * ~/Library/Logs/DiagnosticReports\n"
	"     * /Library/Logs/DiagnosticReports\n"
	"   for more details.\n"
	"Don't forget to include the above Crash Report log file in bug reports.\n"
	"\n";
    const size_t msglen = sizeof(msg) - 1;
#else
    const char *msg = NULL;
    const size_t msglen = 0;
#endif
    bug_important_message(out, msg, msglen);
}

static void
postscript_dump(FILE *out)
{
#if defined __APPLE__
    static const char msg[] = ""
	"[IMPORTANT]"
	/*" ------------------------------------------------"*/
	"\n""Don't forget to include the Crash Report log file under\n"
# if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6
	"CrashReporter or "
# endif
	"DiagnosticReports directory in bug reports.\n"
	/*"------------------------------------------------------------\n"*/
	"\n";
    const size_t msglen = sizeof(msg) - 1;
#else
    const char *msg = NULL;
    const size_t msglen = 0;
#endif
    bug_important_message(out, msg, msglen);
}

static void
bug_report_begin_valist(FILE *out, const char *fmt, va_list args)
{
    char buf[REPORT_BUG_BUFSIZ];

    fputs("[BUG] ", out);
    vsnprintf(buf, sizeof(buf), fmt, args);
    fputs(buf, out);
    snprintf(buf, sizeof(buf), "\n%s\n\n", ruby_description);
    fputs(buf, out);
    preface_dump(out);
}

#define bug_report_begin(out, fmt) do { \
    va_list args; \
    va_start(args, fmt); \
    bug_report_begin_valist(out, fmt, args); \
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
    postscript_dump(out);
}

#define report_bug(file, line, fmt, ctx) do { \
    FILE *out = bug_report_file(file, line); \
    if (out) { \
	bug_report_begin(out, fmt); \
	rb_vm_bugreport(ctx); \
	bug_report_end(out); \
    } \
} while (0) \

#define report_bug_valist(file, line, fmt, ctx, args) do { \
    FILE *out = bug_report_file(file, line); \
    if (out) { \
	bug_report_begin_valist(out, fmt, args); \
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

    if (GET_EC()) {
	file = rb_source_location_cstr(&line);
    }

    report_bug(file, line, fmt, NULL);

    die();
}

void
rb_bug_for_fatal_signal(ruby_sighandler_t default_sighandler, int sig, const void *ctx, const char *fmt, ...)
{
    const char *file = NULL;
    int line = 0;

    if (GET_EC()) {
	file = rb_source_location_cstr(&line);
    }

    report_bug(file, line, fmt, ctx);

    if (default_sighandler) default_sighandler(sig);

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
    abort();
}

void
rb_report_bug_valist(VALUE file, int line, const char *fmt, va_list args)
{
    report_bug_valist(RSTRING_PTR(file), line, fmt, NULL, args);
}

MJIT_FUNC_EXPORTED void
rb_assert_failure(const char *file, int line, const char *name, const char *expr)
{
    FILE *out = stderr;
    fprintf(out, "Assertion Failed: %s:%d:", file, line);
    if (name) fprintf(out, "%s:", name);
    fprintf(out, "%s\n%s\n\n", expr, ruby_description);
    preface_dump(out);
    rb_vm_bugreport(NULL);
    bug_report_end(out);
    die();
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
    "Integer",
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
    "Integer",
    "undef",			/* internal use: #undef; should not happen */
    "",				/* 0x17 */
    "",				/* 0x18 */
    "",				/* 0x19 */
    "Memo",			/* internal use: general memo */
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

static VALUE
displaying_class_of(VALUE x)
{
    switch (x) {
      case Qfalse: return rb_fstring_cstr("false");
      case Qnil:   return rb_fstring_cstr("nil");
      case Qtrue:  return rb_fstring_cstr("true");
      default:     return rb_obj_class(x);
    }
}

static const char *
builtin_class_name(VALUE x)
{
    const char *etype;

    if (NIL_P(x)) {
	etype = "nil";
    }
    else if (FIXNUM_P(x)) {
	etype = "Integer";
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
	etype = NULL;
    }
    return etype;
}

const char *
rb_builtin_class_name(VALUE x)
{
    const char *etype = builtin_class_name(x);

    if (!etype) {
	etype = rb_obj_classname(x);
    }
    return etype;
}

NORETURN(static void unexpected_type(VALUE, int, int));
#define UNDEF_LEAKED "undef leaked to the Ruby space"

static void
unexpected_type(VALUE x, int xt, int t)
{
    const char *tname = rb_builtin_type_name(t);
    VALUE mesg, exc = rb_eFatal;

    if (tname) {
        mesg = rb_sprintf("wrong argument type %"PRIsVALUE" (expected %s)",
                          displaying_class_of(x), tname);
	exc = rb_eTypeError;
    }
    else if (xt > T_MASK && xt <= 0x3f) {
	mesg = rb_sprintf("unknown type 0x%x (0x%x given, probably comes"
			  " from extension library for ruby 1.8)", t, xt);
    }
    else {
	mesg = rb_sprintf("unknown type 0x%x (0x%x given)", t, xt);
    }
    rb_exc_raise(rb_exc_new_str(exc, mesg));
}

void
rb_check_type(VALUE x, int t)
{
    int xt;

    if (x == Qundef) {
	rb_bug(UNDEF_LEAKED);
    }

    xt = TYPE(x);
    if (xt != t || (xt == T_DATA && RTYPEDDATA_P(x))) {
	unexpected_type(x, xt, t);
    }
}

void
rb_unexpected_type(VALUE x, int t)
{
    if (x == Qundef) {
	rb_bug(UNDEF_LEAKED);
    }

    unexpected_type(x, TYPE(x), t);
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

#undef rb_typeddata_is_instance_of
int
rb_typeddata_is_instance_of(VALUE obj, const rb_data_type_t *data_type)
{
    return rb_typeddata_is_instance_of_inline(obj, data_type);
}

void *
rb_check_typeddata(VALUE obj, const rb_data_type_t *data_type)
{
    VALUE actual;

    if (!RB_TYPE_P(obj, T_DATA)) {
        actual = displaying_class_of(obj);
    }
    else if (!RTYPEDDATA_P(obj)) {
        actual = displaying_class_of(obj);
    }
    else if (!rb_typeddata_inherited_p(RTYPEDDATA_TYPE(obj), data_type)) {
        const char *name = RTYPEDDATA_TYPE(obj)->wrap_struct_name;
        actual = rb_str_new_cstr(name); /* or rb_fstring_cstr? not sure... */
    }
    else {
        return DATA_PTR(obj);
    }

    const char *expected = data_type->wrap_struct_name;
    rb_raise(rb_eTypeError, "wrong argument type %"PRIsVALUE" (expected %s)",
             actual, expected);
    UNREACHABLE_RETURN(NULL);
}

/* exception classes */
VALUE rb_eException;
VALUE rb_eSystemExit;
VALUE rb_eInterrupt;
VALUE rb_eSignal;
VALUE rb_eFatal;
VALUE rb_eStandardError;
VALUE rb_eRuntimeError;
VALUE rb_eFrozenError;
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
VALUE rb_eNoMatchingPatternError;

VALUE rb_eScriptError;
VALUE rb_eSyntaxError;
VALUE rb_eLoadError;

VALUE rb_eSystemCallError;
VALUE rb_mErrno;
static VALUE rb_eNOERROR;

ID ruby_static_id_cause;
#define id_cause ruby_static_id_cause
static ID id_message, id_backtrace;
static ID id_key, id_args, id_Errno, id_errno, id_i_path;
static ID id_receiver, id_recv, id_iseq, id_local_variables;
static ID id_private_call_p, id_top, id_bottom;
#define id_bt idBt
#define id_bt_locations idBt_locations
#define id_mesg idMesg
#define id_name idName

#undef rb_exc_new_cstr

VALUE
rb_exc_new(VALUE etype, const char *ptr, long len)
{
    VALUE mesg = rb_str_new(ptr, len);
    return rb_class_new_instance(1, &mesg, etype);
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
    return rb_class_new_instance(1, &str, etype);
}

static VALUE
exc_init(VALUE exc, VALUE mesg)
{
    rb_ivar_set(exc, id_mesg, mesg);
    rb_ivar_set(exc, id_bt, Qnil);

    return exc;
}

/*
 * call-seq:
 *    Exception.new(msg = nil)        ->  exception
 *    Exception.exception(msg = nil)  ->  exception
 *
 *  Construct a new Exception object, optionally passing in
 *  a message.
 */

static VALUE
exc_initialize(int argc, VALUE *argv, VALUE exc)
{
    VALUE arg;

    arg = (!rb_check_arity(argc, 0, 1) ? Qnil : argv[0]);
    return exc_init(exc, arg);
}

/*
 *  Document-method: exception
 *
 *  call-seq:
 *     exc.exception([string])  ->  an_exception or exc
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

    argc = rb_check_arity(argc, 0, 1);
    if (argc == 0) return self;
    if (argc == 1 && self == argv[0]) return self;
    exc = rb_obj_clone(self);
    rb_ivar_set(exc, id_mesg, argv[0]);
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
    VALUE mesg = rb_attr_get(exc, idMesg);

    if (NIL_P(mesg)) return rb_class_name(CLASS_OF(exc));
    return rb_String(mesg);
}

/* FIXME: Include eval_error.c */
void rb_error_write(VALUE errinfo, VALUE emesg, VALUE errat, VALUE str, VALUE highlight, VALUE reverse);

VALUE
rb_get_message(VALUE exc)
{
    VALUE e = rb_check_funcall(exc, id_message, 0, 0);
    if (e == Qundef) return Qnil;
    if (!RB_TYPE_P(e, T_STRING)) e = rb_check_string_type(e);
    return e;
}

/*
 * call-seq:
 *    Exception.to_tty?   ->  true or false
 *
 * Returns +true+ if exception messages will be sent to a tty.
 */
static VALUE
exc_s_to_tty_p(VALUE self)
{
    return rb_stderr_tty_p() ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   exception.full_message(highlight: bool, order: [:top or :bottom]) ->  string
 *
 * Returns formatted string of _exception_.
 * The returned string is formatted using the same format that Ruby uses
 * when printing an uncaught exceptions to stderr.
 *
 * If _highlight_ is +true+ the default error handler will send the
 * messages to a tty.
 *
 * _order_ must be either of +:top+ or +:bottom+, and places the error
 * message and the innermost backtrace come at the top or the bottom.
 *
 * The default values of these options depend on <code>$stderr</code>
 * and its +tty?+ at the timing of a call.
 */

static VALUE
exc_full_message(int argc, VALUE *argv, VALUE exc)
{
    VALUE opt, str, emesg, errat;
    enum {kw_highlight, kw_order, kw_max_};
    static ID kw[kw_max_];
    VALUE args[kw_max_] = {Qnil, Qnil};

    rb_scan_args(argc, argv, "0:", &opt);
    if (!NIL_P(opt)) {
	if (!kw[0]) {
#define INIT_KW(n) kw[kw_##n] = rb_intern_const(#n)
	    INIT_KW(highlight);
	    INIT_KW(order);
#undef INIT_KW
	}
	rb_get_kwargs(opt, kw, 0, kw_max_, args);
	switch (args[kw_highlight]) {
	  default:
	    rb_raise(rb_eArgError, "expected true or false as "
		     "highlight: %+"PRIsVALUE, args[kw_highlight]);
	  case Qundef: args[kw_highlight] = Qnil; break;
	  case Qtrue: case Qfalse: case Qnil: break;
	}
	if (args[kw_order] == Qundef) {
	    args[kw_order] = Qnil;
	}
	else {
	    ID id = rb_check_id(&args[kw_order]);
	    if (id == id_bottom) args[kw_order] = Qtrue;
	    else if (id == id_top) args[kw_order] = Qfalse;
	    else {
		rb_raise(rb_eArgError, "expected :top or :bottom as "
			 "order: %+"PRIsVALUE, args[kw_order]);
	    }
	}
    }
    str = rb_str_new2("");
    errat = rb_get_backtrace(exc);
    emesg = rb_get_message(exc);

    rb_error_write(exc, emesg, errat, str, args[kw_highlight], args[kw_order]);
    return str;
}

/*
 * call-seq:
 *   exception.message   ->  string
 *
 * Returns the result of invoking <code>exception.to_s</code>.
 * Normally this returns the exception's message or name.
 */

static VALUE
exc_message(VALUE exc)
{
    return rb_funcallv(exc, idTo_s, 0, 0);
}

/*
 * call-seq:
 *   exception.inspect   -> string
 *
 * Return this exception's class name and message.
 */

static VALUE
exc_inspect(VALUE exc)
{
    VALUE str, klass;

    klass = CLASS_OF(exc);
    exc = rb_obj_as_string(exc);
    if (RSTRING_LEN(exc) == 0) {
        return rb_class_name(klass);
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
 *     exception.backtrace    -> array or nil
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
 *
 *  In the case no backtrace has been set, +nil+ is returned
 *
 *    ex = StandardError.new
 *    ex.backtrace
 *    #=> nil
*/

static VALUE
exc_backtrace(VALUE exc)
{
    VALUE obj;

    obj = rb_attr_get(exc, id_bt);

    if (rb_backtrace_p(obj)) {
	obj = rb_backtrace_to_str_ary(obj);
	/* rb_ivar_set(exc, id_bt, obj); */
    }

    return obj;
}

static VALUE rb_check_backtrace(VALUE);

VALUE
rb_get_backtrace(VALUE exc)
{
    ID mid = id_backtrace;
    VALUE info;
    if (rb_method_basic_definition_p(CLASS_OF(exc), id_backtrace)) {
	VALUE klass = rb_eException;
	rb_execution_context_t *ec = GET_EC();
	if (NIL_P(exc))
	    return Qnil;
	EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_CALL, exc, mid, mid, klass, Qundef);
	info = exc_backtrace(exc);
	EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, exc, mid, mid, klass, info);
    }
    else {
	info = rb_funcallv(exc, mid, 0, 0);
    }
    if (NIL_P(info)) return Qnil;
    return rb_check_backtrace(info);
}

/*
 *  call-seq:
 *     exception.backtrace_locations    -> array or nil
 *
 *  Returns any backtrace associated with the exception. This method is
 *  similar to Exception#backtrace, but the backtrace is an array of
 *  Thread::Backtrace::Location.
 *
 *  This method is not affected by Exception#set_backtrace().
 */
static VALUE
exc_backtrace_locations(VALUE exc)
{
    VALUE obj;

    obj = rb_attr_get(exc, id_bt_locations);
    if (!NIL_P(obj)) {
	obj = rb_backtrace_to_location_ary(obj);
    }
    return obj;
}

static VALUE
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
    return rb_ivar_set(exc, id_bt, rb_check_backtrace(bt));
}

MJIT_FUNC_EXPORTED VALUE
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

static VALUE
exc_cause(VALUE exc)
{
    return rb_attr_get(exc, id_cause);
}

static VALUE
try_convert_to_exception(VALUE obj)
{
    return rb_check_funcall(obj, idException, 0, 0);
}

/*
 *  call-seq:
 *     exc == obj   -> true or false
 *
 *  Equality---If <i>obj</i> is not an Exception, returns
 *  <code>false</code>. Otherwise, returns <code>true</code> if <i>exc</i> and
 *  <i>obj</i> share same class, messages, and backtrace.
 */

static VALUE
exc_equal(VALUE exc, VALUE obj)
{
    VALUE mesg, backtrace;

    if (exc == obj) return Qtrue;

    if (rb_obj_class(exc) != rb_obj_class(obj)) {
	int state;

	obj = rb_protect(try_convert_to_exception, obj, &state);
	if (state || obj == Qundef) {
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
    rb_ivar_set(exc, id_status, status);
    return exc;
}


/*
 * call-seq:
 *   system_exit.status   -> integer
 *
 * Return the status value associated with this system exit.
 */

static VALUE
exit_status(VALUE exc)
{
    return rb_attr_get(exc, id_status);
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
    VALUE status_val = rb_attr_get(exc, id_status);
    int status;

    if (NIL_P(status_val))
	return Qtrue;
    status = NUM2INT(status_val);
    if (WIFEXITED(status) && WEXITSTATUS(status) == EXIT_SUCCESS)
	return Qtrue;

    return Qfalse;
}

static VALUE
err_init_recv(VALUE exc, VALUE recv)
{
    if (recv != Qundef) rb_ivar_set(exc, id_recv, recv);
    return exc;
}

/*
 * call-seq:
 *   FrozenError.new(msg=nil, receiver: nil)  -> frozen_error
 *
 * Construct a new FrozenError exception. If given the <i>receiver</i>
 * parameter may subsequently be examined using the FrozenError#receiver
 * method.
 *
 *    a = [].freeze
 *    raise FrozenError.new("can't modify frozen array", receiver: a)
 */

static VALUE
frozen_err_initialize(int argc, VALUE *argv, VALUE self)
{
    ID keywords[1];
    VALUE values[numberof(keywords)], options;

    argc = rb_scan_args(argc, argv, "*:", NULL, &options);
    keywords[0] = id_receiver;
    rb_get_kwargs(options, keywords, 0, numberof(values), values);
    rb_call_super(argc, argv);
    err_init_recv(self, values[0]);
    return self;
}

/*
 * Document-method: FrozenError#receiver
 * call-seq:
 *   frozen_error.receiver  -> object
 *
 * Return the receiver associated with this FrozenError exception.
 */

#define frozen_err_receiver name_err_receiver

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

static VALUE
name_err_init_attr(VALUE exc, VALUE recv, VALUE method)
{
    const rb_execution_context_t *ec = GET_EC();
    rb_control_frame_t *cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(ec->cfp);
    cfp = rb_vm_get_ruby_level_next_cfp(ec, cfp);
    rb_ivar_set(exc, id_name, method);
    err_init_recv(exc, recv);
    if (cfp) rb_ivar_set(exc, id_iseq, rb_iseqw_new(cfp->iseq));
    return exc;
}

/*
 * call-seq:
 *   NameError.new(msg=nil, name=nil, receiver: nil)  -> name_error
 *
 * Construct a new NameError exception. If given the <i>name</i>
 * parameter may subsequently be examined using the NameError#name
 * method. <i>receiver</i> parameter allows to pass object in
 * context of which the error happened. Example:
 *
 *    [1, 2, 3].method(:rject) # NameError with name "rject" and receiver: Array
 *    [1, 2, 3].singleton_method(:rject) # NameError with name "rject" and receiver: [1, 2, 3]
 */

static VALUE
name_err_initialize(int argc, VALUE *argv, VALUE self)
{
    ID keywords[1];
    VALUE values[numberof(keywords)], name, options;

    argc = rb_scan_args(argc, argv, "*:", NULL, &options);
    keywords[0] = id_receiver;
    rb_get_kwargs(options, keywords, 0, numberof(values), values);
    name = (argc > 1) ? argv[--argc] : Qnil;
    rb_call_super(argc, argv);
    name_err_init_attr(self, values[0], name);
    return self;
}

static VALUE rb_name_err_mesg_new(VALUE mesg, VALUE recv, VALUE method);

static VALUE
name_err_init(VALUE exc, VALUE mesg, VALUE recv, VALUE method)
{
    exc_init(exc, rb_name_err_mesg_new(mesg, recv, method));
    return name_err_init_attr(exc, recv, method);
}

VALUE
rb_name_err_new(VALUE mesg, VALUE recv, VALUE method)
{
    VALUE exc = rb_obj_alloc(rb_eNameError);
    return name_err_init(exc, mesg, recv, method);
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
    return rb_attr_get(self, id_name);
}

/*
 *  call-seq:
 *    name_error.local_variables  ->  array
 *
 *  Return a list of the local variable names defined where this
 *  NameError exception was raised.
 *
 *  Internal use only.
 */

static VALUE
name_err_local_variables(VALUE self)
{
    VALUE vars = rb_attr_get(self, id_local_variables);

    if (NIL_P(vars)) {
	VALUE iseqw = rb_attr_get(self, id_iseq);
	if (!NIL_P(iseqw)) vars = rb_iseqw_local_variables(iseqw);
	if (NIL_P(vars)) vars = rb_ary_new();
	rb_ivar_set(self, id_local_variables, vars);
    }
    return vars;
}

static VALUE
nometh_err_init_attr(VALUE exc, VALUE args, int priv)
{
    rb_ivar_set(exc, id_args, args);
    rb_ivar_set(exc, id_private_call_p, priv ? Qtrue : Qfalse);
    return exc;
}

/*
 * call-seq:
 *   NoMethodError.new(msg=nil, name=nil, args=nil, private=false, receiver: nil)  -> no_method_error
 *
 * Construct a NoMethodError exception for a method of the given name
 * called with the given arguments. The name may be accessed using
 * the <code>#name</code> method on the resulting object, and the
 * arguments using the <code>#args</code> method.
 *
 * If <i>private</i> argument were passed, it designates method was
 * attempted to call in private context, and can be accessed with
 * <code>#private_call?</code> method.
 *
 * <i>receiver</i> argument stores an object whose method was called.
 */

static VALUE
nometh_err_initialize(int argc, VALUE *argv, VALUE self)
{
    int priv;
    VALUE args, options;
    argc = rb_scan_args(argc, argv, "*:", NULL, &options);
    priv = (argc > 3) && (--argc, RTEST(argv[argc]));
    args = (argc > 2) ? argv[--argc] : Qnil;
    if (!NIL_P(options)) argv[argc++] = options;
    rb_call_super_kw(argc, argv, RB_PASS_CALLED_KEYWORDS);
    return nometh_err_init_attr(self, args, priv);
}

VALUE
rb_nomethod_err_new(VALUE mesg, VALUE recv, VALUE method, VALUE args, int priv)
{
    VALUE exc = rb_obj_alloc(rb_eNoMethodError);
    name_err_init(exc, mesg, recv, method);
    return nometh_err_init_attr(exc, args, priv);
}

/* :nodoc: */
enum {
    NAME_ERR_MESG__MESG,
    NAME_ERR_MESG__RECV,
    NAME_ERR_MESG__NAME,
    NAME_ERR_MESG_COUNT
};

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
    return NAME_ERR_MESG_COUNT * sizeof(VALUE);
}

static const rb_data_type_t name_err_mesg_data_type = {
    "name_err_mesg",
    {
	name_err_mesg_mark,
	name_err_mesg_free,
	name_err_mesg_memsize,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

/* :nodoc: */
static VALUE
rb_name_err_mesg_new(VALUE mesg, VALUE recv, VALUE method)
{
    VALUE result = TypedData_Wrap_Struct(rb_cNameErrorMesg, &name_err_mesg_data_type, 0);
    VALUE *ptr = ALLOC_N(VALUE, NAME_ERR_MESG_COUNT);

    ptr[NAME_ERR_MESG__MESG] = mesg;
    ptr[NAME_ERR_MESG__RECV] = recv;
    ptr[NAME_ERR_MESG__NAME] = method;
    RTYPEDDATA_DATA(result) = ptr;
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
name_err_mesg_receiver_name(VALUE obj)
{
    if (RB_SPECIAL_CONST_P(obj)) return Qundef;
    if (RB_BUILTIN_TYPE(obj) == T_MODULE || RB_BUILTIN_TYPE(obj) == T_CLASS) {
        return rb_check_funcall(obj, rb_intern("name"), 0, 0);
    }
    return Qundef;
}

/* :nodoc: */
static VALUE
name_err_mesg_to_str(VALUE obj)
{
    VALUE *ptr, mesg;
    TypedData_Get_Struct(obj, VALUE, &name_err_mesg_data_type, ptr);

    mesg = ptr[NAME_ERR_MESG__MESG];
    if (NIL_P(mesg)) return Qnil;
    else {
	struct RString s_str, d_str;
	VALUE c, s, d = 0, args[4];
	int state = 0, singleton = 0;
	rb_encoding *usascii = rb_usascii_encoding();

#define FAKE_CSTR(v, str) rb_setup_fake_str((v), (str), rb_strlen_lit(str), usascii)
	obj = ptr[NAME_ERR_MESG__RECV];
	switch (obj) {
	  case Qnil:
	    d = FAKE_CSTR(&d_str, "nil");
	    break;
	  case Qtrue:
	    d = FAKE_CSTR(&d_str, "true");
	    break;
	  case Qfalse:
	    d = FAKE_CSTR(&d_str, "false");
	    break;
	  default:
	    d = rb_protect(name_err_mesg_receiver_name, obj, &state);
	    if (state || d == Qundef || d == Qnil)
		d = rb_protect(rb_inspect, obj, &state);
	    if (state)
		rb_set_errinfo(Qnil);
	    if (NIL_P(d)) {
		d = rb_any_to_s(obj);
	    }
	    singleton = (RSTRING_LEN(d) > 0 && RSTRING_PTR(d)[0] == '#');
	    break;
	}
	if (!singleton) {
	    s = FAKE_CSTR(&s_str, ":");
	    c = rb_class_name(CLASS_OF(obj));
	}
	else {
	    c = s = FAKE_CSTR(&s_str, "");
	}
        args[0] = rb_obj_as_string(ptr[NAME_ERR_MESG__NAME]);
	args[1] = d;
	args[2] = s;
	args[3] = c;
	mesg = rb_str_format(4, args, mesg);
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
 *   name_error.receiver  -> object
 *
 * Return the receiver associated with this NameError exception.
 */

static VALUE
name_err_receiver(VALUE self)
{
    VALUE *ptr, recv, mesg;

    recv = rb_ivar_lookup(self, id_recv, Qundef);
    if (recv != Qundef) return recv;

    mesg = rb_attr_get(self, id_mesg);
    if (!rb_typeddata_is_kind_of(mesg, &name_err_mesg_data_type)) {
	rb_raise(rb_eArgError, "no receiver is available");
    }
    ptr = DATA_PTR(mesg);
    return ptr[NAME_ERR_MESG__RECV];
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
    return rb_attr_get(self, id_args);
}

/*
 * call-seq:
 *   no_method_error.private_call?  -> true or false
 *
 * Return true if the caused method was called as private.
 */

static VALUE
nometh_err_private_call_p(VALUE self)
{
    return rb_attr_get(self, id_private_call_p);
}

void
rb_invalid_str(const char *str, const char *type)
{
    VALUE s = rb_str_new2(str);

    rb_raise(rb_eArgError, "invalid value for %s: %+"PRIsVALUE, type, s);
}

/*
 * call-seq:
 *   key_error.receiver  -> object
 *
 * Return the receiver associated with this KeyError exception.
 */

static VALUE
key_err_receiver(VALUE self)
{
    VALUE recv;

    recv = rb_ivar_lookup(self, id_receiver, Qundef);
    if (recv != Qundef) return recv;
    rb_raise(rb_eArgError, "no receiver is available");
}

/*
 * call-seq:
 *   key_error.key  -> object
 *
 * Return the key caused this KeyError exception.
 */

static VALUE
key_err_key(VALUE self)
{
    VALUE key;

    key = rb_ivar_lookup(self, id_key, Qundef);
    if (key != Qundef) return key;
    rb_raise(rb_eArgError, "no key is available");
}

VALUE
rb_key_err_new(VALUE mesg, VALUE recv, VALUE key)
{
    VALUE exc = rb_obj_alloc(rb_eKeyError);
    rb_ivar_set(exc, id_mesg, mesg);
    rb_ivar_set(exc, id_bt, Qnil);
    rb_ivar_set(exc, id_key, key);
    rb_ivar_set(exc, id_receiver, recv);
    return exc;
}

/*
 * call-seq:
 *   KeyError.new(message=nil, receiver: nil, key: nil) -> key_error
 *
 * Construct a new +KeyError+ exception with the given message,
 * receiver and key.
 */

static VALUE
key_err_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE options;

    rb_call_super(rb_scan_args(argc, argv, "01:", NULL, &options), argv);

    if (!NIL_P(options)) {
	ID keywords[2];
	VALUE values[numberof(keywords)];
	int i;
	keywords[0] = id_receiver;
	keywords[1] = id_key;
	rb_get_kwargs(options, keywords, 0, numberof(values), values);
	for (i = 0; i < numberof(values); ++i) {
	    if (values[i] != Qundef) {
		rb_ivar_set(self, keywords[i], values[i]);
	    }
	}
    }

    return self;
}

/*
 * call-seq:
 *   SyntaxError.new([msg])  -> syntax_error
 *
 * Construct a SyntaxError exception.
 */

static VALUE
syntax_error_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE mesg;
    if (argc == 0) {
	mesg = rb_fstring_lit("compile error");
	argc = 1;
	argv = &mesg;
    }
    return rb_call_super(argc, argv);
}

/*
 *  Document-module: Errno
 *
 *  Ruby exception objects are subclasses of Exception.  However,
 *  operating systems typically report errors using plain
 *  integers. Module Errno is created dynamically to map these
 *  operating system errors to Ruby classes, with each error number
 *  generating its own subclass of SystemCallError.  As the subclass
 *  is created in module Errno, its name will start
 *  <code>Errno::</code>.
 *
 *  The names of the <code>Errno::</code> classes depend on the
 *  environment in which Ruby runs. On a typical Unix or Windows
 *  platform, there are Errno classes such as Errno::EACCES,
 *  Errno::EAGAIN, Errno::EINTR, and so on.
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
 *  are available as the constants of Errno.
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

#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
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
 * If _errno_ corresponds to a known system error code, constructs the
 * appropriate Errno class for that error, otherwise constructs a
 * generic SystemCallError object. The error number is subsequently
 * available via the #errno method.
 */

static VALUE
syserr_initialize(int argc, VALUE *argv, VALUE self)
{
#if !defined(_WIN32)
    char *strerror();
#endif
    const char *err;
    VALUE mesg, error, func, errmsg;
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
	error = rb_const_get(klass, id_Errno);
    }
    if (!NIL_P(error)) err = strerror(NUM2INT(error));
    else err = "unknown error";

    errmsg = rb_enc_str_new_cstr(err, rb_locale_encoding());
    if (!NIL_P(mesg)) {
	VALUE str = StringValue(mesg);

	if (!NIL_P(func)) rb_str_catf(errmsg, " @ %"PRIsVALUE, func);
	rb_str_catf(errmsg, " - %"PRIsVALUE, str);
    }
    mesg = errmsg;

    rb_call_super(1, &mesg);
    rb_ivar_set(self, id_errno, error);
    return self;
}

/*
 * call-seq:
 *   system_call_error.errno   -> integer
 *
 * Return this SystemCallError's error number.
 */

static VALUE
syserr_errno(VALUE self)
{
    return rb_attr_get(self, id_errno);
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

    if (!rb_obj_is_kind_of(exc, rb_eSystemCallError)) {
	if (!rb_respond_to(exc, id_errno)) return Qfalse;
    }
    else if (self == rb_eSystemCallError) return Qtrue;

    num = rb_attr_get(exc, id_errno);
    if (NIL_P(num)) {
	num = rb_funcallv(exc, id_errno, 0, 0);
    }
    e = rb_const_get(self, id_Errno);
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
 *  Raised when the interrupt signal is received, typically because the
 *  user has pressed Control-C (on most posix platforms). As such, it is a
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
 *     ArgumentError: wrong number of arguments (given 2, expected 1)
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
 *     Integer.const_set :answer, 42
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
 *  Document-class: FrozenError
 *
 *  Raised when there is an attempt to modify a frozen object.
 *
 *     [1, 2, 3].freeze << 4
 *
 *  <em>raises the exception:</em>
 *
 *     FrozenError: can't modify frozen Array
 */

/*
 *  Document-class: RuntimeError
 *
 *  A generic error class raised when an invalid operation is attempted.
 *  Kernel#raise will raise a RuntimeError if no Exception class is
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
 *  No longer used by internal code.
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
 * fatal is an Exception that is raised when Ruby has encountered a fatal
 * error and must exit.
 */

/*
 * Document-class: NameError::message
 * :nodoc:
 */

/*
 *  \Class Exception and its subclasses are used to communicate between
 *  Kernel#raise and +rescue+ statements in <code>begin ... end</code> blocks.
 *
 *  An Exception object carries information about an exception:
 *  - Its type (the exception's class).
 *  - An optional descriptive message.
 *  - Optional backtrace information.
 *
 *  Some built-in subclasses of Exception have additional methods: e.g., NameError#name.
 *
 *  == Defaults
 *
 *  Two Ruby statements have default exception classes:
 *  - +raise+: defaults to RuntimeError.
 *  - +rescue+: defaults to StandardError.
 *
 *  == Global Variables
 *
 *  When an exception has been raised but not yet handled (in +rescue+,
 *  +ensure+, +at_exit+ and +END+ blocks), two global variables are set:
 *  - <code>$!</code> contains the current exception.
 *  - <code>$@</code> contains its backtrace.
 *
 *  == Custom Exceptions
 *
 *  To provide additional or alternate information,
 *  a program may create custom exception classes
 *  that derive from the built-in exception classes.
 *
 *  A good practice is for a library to create a single "generic" exception class
 *  (typically a subclass of StandardError or RuntimeError)
 *  and have its other exception classes derive from that class.
 *  This allows the user to rescue the generic exception, thus catching all exceptions
 *  the library may raise even if future versions of the library add new
 *  exception subclasses.
 *
 *  For example:
 *
 *    class MyLibrary
 *      class Error < ::StandardError
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
 *  To handle both MyLibrary::WidgetError and MyLibrary::FrobError the library
 *  user can rescue MyLibrary::Error.
 *
 *  == Built-In Exception Classes
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
 *  * StandardError
 *    * ArgumentError
 *      * UncaughtThrowError
 *    * EncodingError
 *    * FiberError
 *    * IOError
 *      * EOFError
 *    * IndexError
 *      * KeyError
 *      * StopIteration
 *        * ClosedQueueError
 *    * LocalJumpError
 *    * NameError
 *      * NoMethodError
 *    * RangeError
 *      * FloatDomainError
 *    * RegexpError
 *    * RuntimeError
 *      * FrozenError
 *    * SystemCallError
 *      * Errno::*
 *    * ThreadError
 *    * TypeError
 *    * ZeroDivisionError
 *  * SystemExit
 *  * SystemStackError
 *  * fatal
 */

static VALUE
exception_alloc(VALUE klass)
{
    return rb_class_allocate_instance(klass);
}

static VALUE
exception_dumper(VALUE exc)
{
    // TODO: Currently, the instance variables "bt" and "bt_locations"
    // refers to the same object (Array of String). But "bt_locations"
    // should have an Array of Thread::Backtrace::Locations.

    return exc;
}

static int
ivar_copy_i(st_data_t key, st_data_t val, st_data_t exc)
{
    rb_ivar_set((VALUE) exc, (ID) key, (VALUE) val);
    return ST_CONTINUE;
}

static VALUE
exception_loader(VALUE exc, VALUE obj)
{
    // The loader function of rb_marshal_define_compat seems to be called for two events:
    // one is for fixup (r_fixup_compat), the other is for TYPE_USERDEF.
    // In the former case, the first argument is an instance of Exception (because
    // we pass rb_eException to rb_marshal_define_compat). In the latter case, the first
    // argument is a class object (see TYPE_USERDEF case in r_object0).
    // We want to copy all instance variables (but "bt_locations") from obj to exc.
    // But we do not want to do so in the second case, so the following branch is for that.
    if (RB_TYPE_P(exc, T_CLASS)) return obj; // maybe called from Marshal's TYPE_USERDEF

    rb_ivar_foreach(obj, ivar_copy_i, exc);

    if (rb_attr_get(exc, id_bt) == rb_attr_get(exc, id_bt_locations)) {
        rb_ivar_set(exc, id_bt_locations, Qnil);
    }

    return exc;
}

void
Init_Exception(void)
{
    rb_eException   = rb_define_class("Exception", rb_cObject);
    rb_define_alloc_func(rb_eException, exception_alloc);
    rb_marshal_define_compat(rb_eException, rb_eException, exception_dumper, exception_loader);
    rb_define_singleton_method(rb_eException, "exception", rb_class_new_instance, -1);
    rb_define_singleton_method(rb_eException, "to_tty?", exc_s_to_tty_p, 0);
    rb_define_method(rb_eException, "exception", exc_exception, -1);
    rb_define_method(rb_eException, "initialize", exc_initialize, -1);
    rb_define_method(rb_eException, "==", exc_equal, 1);
    rb_define_method(rb_eException, "to_s", exc_to_s, 0);
    rb_define_method(rb_eException, "message", exc_message, 0);
    rb_define_method(rb_eException, "full_message", exc_full_message, -1);
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
    rb_define_method(rb_eKeyError, "initialize", key_err_initialize, -1);
    rb_define_method(rb_eKeyError, "receiver", key_err_receiver, 0);
    rb_define_method(rb_eKeyError, "key", key_err_key, 0);
    rb_eRangeError    = rb_define_class("RangeError", rb_eStandardError);

    rb_eScriptError = rb_define_class("ScriptError", rb_eException);
    rb_eSyntaxError = rb_define_class("SyntaxError", rb_eScriptError);
    rb_define_method(rb_eSyntaxError, "initialize", syntax_error_initialize, -1);

    rb_eLoadError   = rb_define_class("LoadError", rb_eScriptError);
    /* the path failed to load */
    rb_attr(rb_eLoadError, rb_intern_const("path"), 1, 0, Qfalse);

    rb_eNotImpError = rb_define_class("NotImplementedError", rb_eScriptError);

    rb_eNameError     = rb_define_class("NameError", rb_eStandardError);
    rb_define_method(rb_eNameError, "initialize", name_err_initialize, -1);
    rb_define_method(rb_eNameError, "name", name_err_name, 0);
    rb_define_method(rb_eNameError, "receiver", name_err_receiver, 0);
    rb_define_method(rb_eNameError, "local_variables", name_err_local_variables, 0);
    rb_cNameErrorMesg = rb_define_class_under(rb_eNameError, "message", rb_cData);
    rb_define_method(rb_cNameErrorMesg, "==", name_err_mesg_equal, 1);
    rb_define_method(rb_cNameErrorMesg, "to_str", name_err_mesg_to_str, 0);
    rb_define_method(rb_cNameErrorMesg, "_dump", name_err_mesg_dump, 1);
    rb_define_singleton_method(rb_cNameErrorMesg, "_load", name_err_mesg_load, 1);
    rb_eNoMethodError = rb_define_class("NoMethodError", rb_eNameError);
    rb_define_method(rb_eNoMethodError, "initialize", nometh_err_initialize, -1);
    rb_define_method(rb_eNoMethodError, "args", nometh_err_args, 0);
    rb_define_method(rb_eNoMethodError, "private_call?", nometh_err_private_call_p, 0);

    rb_eRuntimeError = rb_define_class("RuntimeError", rb_eStandardError);
    rb_eFrozenError = rb_define_class("FrozenError", rb_eRuntimeError);
    rb_define_method(rb_eFrozenError, "initialize", frozen_err_initialize, -1);
    rb_define_method(rb_eFrozenError, "receiver", frozen_err_receiver, 0);
    rb_eSecurityError = rb_define_class("SecurityError", rb_eException);
    rb_eNoMemError = rb_define_class("NoMemoryError", rb_eException);
    rb_eEncodingError = rb_define_class("EncodingError", rb_eStandardError);
    rb_eEncCompatError = rb_define_class_under(rb_cEncoding, "CompatibilityError", rb_eEncodingError);
    rb_eNoMatchingPatternError = rb_define_class("NoMatchingPatternError", rb_eRuntimeError);

    syserr_tbl = st_init_numtable();
    rb_eSystemCallError = rb_define_class("SystemCallError", rb_eStandardError);
    rb_define_method(rb_eSystemCallError, "initialize", syserr_initialize, -1);
    rb_define_method(rb_eSystemCallError, "errno", syserr_errno, 0);
    rb_define_singleton_method(rb_eSystemCallError, "===", syserr_eqq, 1);

    rb_mErrno = rb_define_module("Errno");

    rb_mWarning = rb_define_module("Warning");
    rb_define_singleton_method(rb_mWarning, "[]", rb_warning_s_aref, 1);
    rb_define_singleton_method(rb_mWarning, "[]=", rb_warning_s_aset, 2);
    rb_define_method(rb_mWarning, "warn", rb_warning_s_warn, -1);
    rb_extend_object(rb_mWarning, rb_mWarning);

    /* :nodoc: */
    rb_cWarningBuffer = rb_define_class_under(rb_mWarning, "buffer", rb_cString);
    rb_define_method(rb_cWarningBuffer, "write", warning_write, -1);

    id_cause = rb_intern_const("cause");
    id_message = rb_intern_const("message");
    id_backtrace = rb_intern_const("backtrace");
    id_key = rb_intern_const("key");
    id_args = rb_intern_const("args");
    id_receiver = rb_intern_const("receiver");
    id_private_call_p = rb_intern_const("private_call?");
    id_local_variables = rb_intern_const("local_variables");
    id_Errno = rb_intern_const("Errno");
    id_errno = rb_intern_const("errno");
    id_i_path = rb_intern_const("@path");
    id_warn = rb_intern_const("warn");
    id_category = rb_intern_const("category");
    id_top = rb_intern_const("top");
    id_bottom = rb_intern_const("bottom");
    id_iseq = rb_make_internal_id();
    id_recv = rb_make_internal_id();

    sym_category = ID2SYM(id_category);

    warning_categories = rb_hash_new();
    rb_gc_register_mark_object(warning_categories);
    rb_hash_aset(warning_categories, ID2SYM(rb_intern("deprecated")), Qtrue);
    rb_obj_freeze(warning_categories);
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
rb_vraise(VALUE exc, const char *fmt, va_list ap)
{
    rb_exc_raise(rb_exc_new3(exc, rb_vsprintf(fmt, ap)));
}

void
rb_raise(VALUE exc, const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    rb_vraise(exc, fmt, args);
    va_end(args);
}

NORETURN(static void raise_loaderror(VALUE path, VALUE mesg));

static void
raise_loaderror(VALUE path, VALUE mesg)
{
    VALUE err = rb_exc_new3(rb_eLoadError, mesg);
    rb_ivar_set(err, id_i_path, path);
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
	     "%"PRIsVALUE"() function is unimplemented on this machine",
	     rb_id2str(rb_frame_this_func()));
}

void
rb_fatal(const char *fmt, ...)
{
    va_list args;
    VALUE mesg;

    if (! ruby_thread_has_gvl_p()) {
        /* The thread has no GVL.  Object allocation impossible (cant run GC),
         * thus no message can be printed out. */
        fprintf(stderr, "[FATAL] rb_fatal() outside of GVL\n");
        rb_print_backtrace();
        die();
    }

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
    rb_exc_raise(rb_syserr_new_path_in(func_name, n, path));
}

VALUE
rb_syserr_new_path_in(const char *func_name, int n, VALUE path)
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
    return rb_class_new_instance(2, args, get_syserr(n));
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

static void
syserr_warning(VALUE mesg, int err)
{
    rb_str_set_len(mesg, RSTRING_LEN(mesg)-1);
    rb_str_catf(mesg, ": %s\n", strerror(err));
    rb_write_warning_str(mesg);
}

#if 0
void
rb_sys_warn(const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
	int errno_save = errno;
	with_warning_string(mesg, 0, fmt) {
	    syserr_warning(mesg, errno_save);
	}
	errno = errno_save;
    }
}

void
rb_syserr_warn(int err, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
	with_warning_string(mesg, 0, fmt) {
	    syserr_warning(mesg, err);
	}
    }
}

void
rb_sys_enc_warn(rb_encoding *enc, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
	int errno_save = errno;
	with_warning_string(mesg, enc, fmt) {
	    syserr_warning(mesg, errno_save);
	}
	errno = errno_save;
    }
}

void
rb_syserr_enc_warn(int err, rb_encoding *enc, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
	with_warning_string(mesg, enc, fmt) {
	    syserr_warning(mesg, err);
	}
    }
}
#endif

void
rb_sys_warning(const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
	int errno_save = errno;
	with_warning_string(mesg, 0, fmt) {
	    syserr_warning(mesg, errno_save);
	}
	errno = errno_save;
    }
}

#if 0
void
rb_syserr_warning(int err, const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
	with_warning_string(mesg, 0, fmt) {
	    syserr_warning(mesg, err);
	}
    }
}
#endif

void
rb_sys_enc_warning(rb_encoding *enc, const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
	int errno_save = errno;
	with_warning_string(mesg, enc, fmt) {
	    syserr_warning(mesg, errno_save);
	}
	errno = errno_save;
    }
}

void
rb_syserr_enc_warning(int err, rb_encoding *enc, const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
	with_warning_string(mesg, enc, fmt) {
	    syserr_warning(mesg, err);
	}
    }
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
    rb_raise(rb_eFrozenError, "can't modify frozen %s", what);
}

void
rb_frozen_error_raise(VALUE frozen_obj, const char *fmt, ...)
{
    va_list args;
    VALUE exc, mesg;

    va_start(args, fmt);
    mesg = rb_vsprintf(fmt, args);
    va_end(args);
    exc = rb_exc_new3(rb_eFrozenError, mesg);
    rb_ivar_set(exc, id_recv, frozen_obj);
    rb_exc_raise(exc);
}

static VALUE
inspect_frozen_obj(VALUE obj, VALUE mesg, int recur)
{
    if (recur) {
        rb_str_cat_cstr(mesg, " ...");
    }
    else {
        rb_str_append(mesg, rb_inspect(obj));
    }
    return mesg;
}

void
rb_error_frozen_object(VALUE frozen_obj)
{
    VALUE debug_info;
    const ID created_info = id_debug_created_info;
    VALUE mesg = rb_sprintf("can't modify frozen %"PRIsVALUE": ",
                            CLASS_OF(frozen_obj));
    VALUE exc = rb_exc_new_str(rb_eFrozenError, mesg);

    rb_ivar_set(exc, id_recv, frozen_obj);
    rb_exec_recursive(inspect_frozen_obj, frozen_obj, mesg);

    if (!NIL_P(debug_info = rb_attr_get(frozen_obj, created_info))) {
	VALUE path = rb_ary_entry(debug_info, 0);
	VALUE line = rb_ary_entry(debug_info, 1);

        rb_str_catf(mesg, ", created at %"PRIsVALUE":%"PRIsVALUE, path, line);
    }
    rb_exc_raise(exc);
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
    rb_warn_deprecated_to_remove("rb_error_untrusted", "3.2");
}

#undef rb_check_trusted
void
rb_check_trusted(VALUE obj)
{
    rb_warn_deprecated_to_remove("rb_check_trusted", "3.2");
}

void
rb_check_copyable(VALUE obj, VALUE orig)
{
    if (!FL_ABLE(obj)) return;
    rb_check_frozen_internal(obj);
    if (!FL_ABLE(orig)) return;
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

#include "warning.rbinc"

/*!
 * \}
 */
