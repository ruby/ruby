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

#ifdef HAVE_SYS_WAIT_H
# include <sys/wait.h>
#endif

#if defined __APPLE__
# include <AvailabilityMacros.h>
#endif

#include "internal.h"
#include "internal/class.h"
#include "internal/error.h"
#include "internal/eval.h"
#include "internal/gc.h"
#include "internal/hash.h"
#include "internal/io.h"
#include "internal/load.h"
#include "internal/object.h"
#include "internal/process.h"
#include "internal/string.h"
#include "internal/symbol.h"
#include "internal/thread.h"
#include "internal/variable.h"
#include "ruby/encoding.h"
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby_assert.h"
#include "vm_core.h"
#include "yjit.h"

#if USE_MMTK
#include "internal/mmtk_support.h"
#endif

#include "builtin.h"

/*!
 * \addtogroup exception
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
static ID id_deprecated;
static ID id_experimental;
static ID id_performance;
static VALUE sym_category;
static VALUE sym_highlight;
static struct {
    st_table *id2enum, *enum2id;
} warning_categories;

extern const char *rb_dynamic_description;

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

RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 5, 0)
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

static VALUE syntax_error_with_path(VALUE, VALUE, VALUE*, rb_encoding*);

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
        exc = syntax_error_with_path(exc, file, &mesg, enc);
        err_vcatf(mesg, NULL, fn, line, fmt, args);
    }

    return exc;
}

static unsigned int warning_disabled_categories = (
    (1U << RB_WARN_CATEGORY_DEPRECATED) |
    ~RB_WARN_CATEGORY_DEFAULT_BITS);

static unsigned int
rb_warning_category_mask(VALUE category)
{
    return 1U << rb_warning_category_from_name(category);
}

rb_warning_category_t
rb_warning_category_from_name(VALUE category)
{
    st_data_t cat_value;
    ID cat_id;
    Check_Type(category, T_SYMBOL);
    if (!(cat_id = rb_check_id(&category)) ||
        !st_lookup(warning_categories.id2enum, cat_id, &cat_value)) {
        rb_raise(rb_eArgError, "unknown category: %"PRIsVALUE, category);
    }
    return (rb_warning_category_t)cat_value;
}

static VALUE
rb_warning_category_to_name(rb_warning_category_t category)
{
    st_data_t id;
    if (!st_lookup(warning_categories.enum2id, category, &id)) {
        rb_raise(rb_eArgError, "invalid category: %d", (int)category);
    }
    return id ? ID2SYM(id) : Qnil;
}

void
rb_warning_category_update(unsigned int mask, unsigned int bits)
{
    warning_disabled_categories &= ~mask;
    warning_disabled_categories |= mask & ~bits;
}

bool
rb_warning_category_enabled_p(rb_warning_category_t category)
{
    return !(warning_disabled_categories & (1U << category));
}

/*
 * call-seq:
 *    Warning[category]  -> true or false
 *
 * Returns the flag to show the warning messages for +category+.
 * Supported categories are:
 *
 * +:deprecated+ ::
 *   deprecation warnings
 *   * assignment of non-nil value to <code>$,</code> and <code>$;</code>
 *   * keyword arguments
 *   etc.
 *
 * +:experimental+ ::
 *   experimental features
 *   * Pattern matching
 *
 * +:performance+ ::
 *   performance hints
 *   * Shape variation limit
 */

static VALUE
rb_warning_s_aref(VALUE mod, VALUE category)
{
    rb_warning_category_t cat = rb_warning_category_from_name(category);
    return RBOOL(rb_warning_category_enabled_p(cat));
}

/*
 * call-seq:
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
 * the warning.
 *
 * See the documentation of the Warning module for how to customize this.
 */

static VALUE
rb_warning_s_warn(int argc, VALUE *argv, VALUE mod)
{
    VALUE str;
    VALUE opt;
    VALUE category = Qnil;

    rb_scan_args(argc, argv, "1:", &str, &opt);
    if (!NIL_P(opt)) rb_get_kwargs(opt, &id_category, 0, 1, &category);

    Check_Type(str, T_STRING);
    rb_must_asciicompat(str);
    if (!NIL_P(category)) {
        rb_warning_category_t cat = rb_warning_category_from_name(category);
        if (!rb_warning_category_enabled_p(cat)) return Qnil;
    }
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
 *  warnings somewhere other than <tt>$stderr</tt>.
 *
 *  If you want to change the behavior of Warning.warn you should use
 *  <tt>Warning.extend(MyNewModuleWithWarnMethod)</tt> and you can use +super+
 *  to get the default behavior of printing the warning to <tt>$stderr</tt>.
 *
 *  Example:
 *    module MyWarningFilter
 *      def warn(message, category: nil, **kwargs)
 *        if /some warning I want to ignore/.match?(message)
 *          # ignore
 *        else
 *          super
 *        end
 *      end
 *    end
 *    Warning.extend MyWarningFilter
 *
 *  You should never redefine Warning#warn (the instance method), as that will
 *  then no longer provide a way to use the default behavior.
 *
 *  The warning[https://rubygems.org/gems/warning] gem provides convenient ways to customize Warning.warn.
 */

static VALUE
rb_warning_warn(VALUE mod, VALUE str)
{
    return rb_funcallv(mod, id_warn, 1, &str);
}


static int
rb_warning_warn_arity(void)
{
    const rb_method_entry_t *me = rb_method_entry(rb_singleton_class(rb_mWarning), id_warn);
    return me ? rb_method_entry_arity(me) : 1;
}

static VALUE
rb_warn_category(VALUE str, VALUE category)
{
    if (RUBY_DEBUG && !NIL_P(category)) {
        rb_warning_category_from_name(category);
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

RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 4, 0)
static VALUE
warn_vsprintf(rb_encoding *enc, const char *file, int line, const char *fmt, va_list args)
{
    VALUE str = rb_enc_str_new(0, 0, enc);

    err_vcatf(str, "warning: ", file, line, fmt, args);
    return rb_str_cat2(str, "\n");
}

#define with_warn_vsprintf(file, line, fmt) \
    VALUE str; \
    va_list args; \
    va_start(args, fmt); \
    str = warn_vsprintf(NULL, file, line, fmt, args); \
    va_end(args);

void
rb_compile_warn(const char *file, int line, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
        with_warn_vsprintf(file, line, fmt) {
            rb_write_warning_str(str);
        }
    }
}

/* rb_compile_warning() reports only in verbose mode */
void
rb_compile_warning(const char *file, int line, const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
        with_warn_vsprintf(file, line, fmt) {
            rb_write_warning_str(str);
        }
    }
}

void
rb_category_compile_warn(rb_warning_category_t category, const char *file, int line, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
        with_warn_vsprintf(file, line, fmt) {
            rb_warn_category(str, rb_warning_category_to_name(category));
        }
    }
}

RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 0)
static VALUE
warning_string(rb_encoding *enc, const char *fmt, va_list args)
{
    int line;
    const char *file = rb_source_location_cstr(&line);
    return warn_vsprintf(enc, file, line, fmt, args);
}

#define with_warning_string(mesg, enc, fmt) \
    with_warning_string_from(mesg, enc, fmt, fmt)
#define with_warning_string_from(mesg, enc, fmt, last_arg) \
    VALUE mesg; \
    va_list args; va_start(args, last_arg); \
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
rb_category_warn(rb_warning_category_t category, const char *fmt, ...)
{
    if (!NIL_P(ruby_verbose)) {
        with_warning_string(mesg, 0, fmt) {
            rb_warn_category(mesg, rb_warning_category_to_name(category));
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
rb_category_warning(rb_warning_category_t category, const char *fmt, ...)
{
    if (RTEST(ruby_verbose)) {
        with_warning_string(mesg, 0, fmt) {
            rb_warn_category(mesg, rb_warning_category_to_name(category));
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

static bool
deprecation_warning_enabled(void)
{
    if (NIL_P(ruby_verbose)) return false;
    if (!rb_warning_category_enabled_p(RB_WARN_CATEGORY_DEPRECATED)) return false;
    return true;
}

static void
warn_deprecated(VALUE mesg, const char *removal, const char *suggest)
{
    rb_str_set_len(mesg, RSTRING_LEN(mesg) - 1);
    rb_str_cat_cstr(mesg, " is deprecated");
    if (removal) {
        rb_str_catf(mesg, " and will be removed in Ruby %s", removal);
    }
    if (suggest) rb_str_catf(mesg, "; use %s instead", suggest);
    rb_str_cat_cstr(mesg, "\n");
    rb_warn_category(mesg, ID2SYM(id_deprecated));
}

void
rb_warn_deprecated(const char *fmt, const char *suggest, ...)
{
    if (!deprecation_warning_enabled()) return;

    with_warning_string_from(mesg, 0, fmt, suggest) {
        warn_deprecated(mesg, NULL, suggest);
    }
}

void
rb_warn_deprecated_to_remove(const char *removal, const char *fmt, const char *suggest, ...)
{
    if (!deprecation_warning_enabled()) return;

    with_warning_string_from(mesg, 0, fmt, suggest) {
        warn_deprecated(mesg, removal, suggest);
    }
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

VALUE rb_ec_backtrace_location_ary(const rb_execution_context_t *ec, long lev, long n, bool skip_internal);

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
            location = rb_ec_backtrace_location_ary(ec, lev + 1, 1, TRUE);
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

        if (!NIL_P(category)) {
            category = rb_to_symbol_type(category);
            rb_warning_category_from_name(category);
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

/* returns true if x can not be used as file name */
static bool
path_sep_p(char x)
{
#if defined __CYGWIN__ || defined DOSISH
# define PATH_SEP_ENCODING 1
    // Assume that "/" is only the first byte in any encoding.
    if (x == ':') return true; // drive letter or ADS
    if (x == '\\') return true;
#endif
    return x == '/';
}

struct path_string {
    const char *ptr;
    size_t len;
};

static const char PATHSEP_REPLACE = '!';

static char *
append_pathname(char *p, const char *pe, VALUE str)
{
#ifdef PATH_SEP_ENCODING
    rb_encoding *enc = rb_enc_get(str);
#endif
    const char *s = RSTRING_PTR(str);
    const char *const se = s + RSTRING_LEN(str);
    char c;

    --pe; // for terminator

    while (p < pe && s < se && (c = *s) != '\0') {
        if (c == '.') {
            if (s == se || !*s) break; // chomp "." basename
            if (path_sep_p(s[1])) goto skipsep; // skip "./"
        }
        else if (path_sep_p(c)) {
            // squeeze successive separators
            *p++ = PATHSEP_REPLACE;
          skipsep:
            while (++s < se && path_sep_p(*s));
            continue;
        }
        const char *const ss = s;
        while (p < pe && s < se && *s && !path_sep_p(*s)) {
#ifdef PATH_SEP_ENCODING
            int n = rb_enc_mbclen(s, se, enc);
#else
            const int n = 1;
#endif
            p += n;
            s += n;
        }
        if (s > ss) memcpy(p - (s - ss), ss, s - ss);
    }

    return p;
}

static char *
append_basename(char *p, const char *pe, struct path_string *path, VALUE str)
{
    if (!path->ptr) {
#ifdef PATH_SEP_ENCODING
        rb_encoding *enc = rb_enc_get(str);
#endif
        const char *const b = RSTRING_PTR(str), *const e = RSTRING_END(str), *p = e;

        while (p > b) {
            if (path_sep_p(p[-1])) {
#ifdef PATH_SEP_ENCODING
                const char *t = rb_enc_prev_char(b, p, e, enc);
                if (t == p-1) break;
                p = t;
#else
                break;
#endif
            }
            else {
                --p;
            }
        }

        path->ptr = p;
        path->len = e - p;
    }
    size_t n = path->len;
    if (p + n > pe) n = pe - p;
    memcpy(p, path->ptr, n);
    return p + n;
}

static void
finish_report(FILE *out, rb_pid_t pid)
{
    if (out != stdout && out != stderr) fclose(out);
#ifdef HAVE_WORKING_FORK
    if (pid > 0) waitpid(pid, NULL, 0);
#endif
}

struct report_expansion {
    struct path_string exe, script;
    rb_pid_t pid;
    time_t time;
};

/*
 * Open a bug report file to write.  The `RUBY_CRASH_REPORT`
 * environment variable can be set to define a template that is used
 * to name bug report files.  The template can contain % specifiers
 * which are substituted by the following values when a bug report
 * file is created:
 *
 *   %%    A single % character.
 *   %e    The base name of the executable filename.
 *   %E    Pathname of executable, with slashes ('/') replaced by
 *         exclamation marks ('!').
 *   %f    Similar to %e with the main script filename.
 *   %F    Similar to %E with the main script filename.
 *   %p    PID of dumped process in decimal.
 *   %t    Time of dump, expressed as seconds since the Epoch,
 *         1970-01-01 00:00:00 +0000 (UTC).
 *   %NNN  Octal char code, upto 3 digits.
 */
static char *
expand_report_argument(const char **input_template, struct report_expansion *values,
                       char *buf, size_t size, bool word)
{
    char *p = buf;
    char *end = buf + size;
    const char *template = *input_template;
    bool store = true;

    if (p >= end-1 || !*template) return NULL;
    do {
        char c = *template++;
        if (word && ISSPACE(c)) break;
        if (!store) continue;
        if (c == '%') {
            size_t n;
            switch (c = *template++) {
              case 'e':
                p = append_basename(p, end, &values->exe, rb_argv0);
                continue;
              case 'E':
                p = append_pathname(p, end, rb_argv0);
                continue;
              case 'f':
                p = append_basename(p, end, &values->script, GET_VM()->orig_progname);
                continue;
              case 'F':
                p = append_pathname(p, end, GET_VM()->orig_progname);
                continue;
              case 'p':
                if (!values->pid) values->pid = getpid();
                snprintf(p, end-p, "%" PRI_PIDT_PREFIX "d", values->pid);
                p += strlen(p);
                continue;
              case 't':
                if (!values->time) values->time = time(NULL);
                snprintf(p, end-p, "%" PRI_TIMET_PREFIX "d", values->time);
                p += strlen(p);
                continue;
              default:
                if (c >= '0' && c <= '7') {
                    c = (unsigned char)ruby_scan_oct(template-1, 3, &n);
                    template += n - 1;
                    if (!c) store = false;
                }
                break;
            }
        }
        if (p < end-1) *p++ = c;
    } while (*template);
    *input_template = template;
    *p = '\0';
    return ++p;
}

FILE *ruby_popen_writer(char *const *argv, rb_pid_t *pid);

static FILE *
open_report_path(const char *template, char *buf, size_t size, rb_pid_t *pid)
{
    struct report_expansion values = {{0}};

    if (!template) return NULL;
    if (0) fprintf(stderr, "RUBY_CRASH_REPORT=%s\n", buf);
    if (*template == '|') {
        char *argv[16], *bufend = buf + size, *p;
        int argc;
        template++;
        for (argc = 0; argc < numberof(argv) - 1; ++argc) {
            while (*template && ISSPACE(*template)) template++;
            p = expand_report_argument(&template, &values, buf, bufend-buf, true);
            if (!p) break;
            argv[argc] = buf;
            buf = p;
        }
        argv[argc] = NULL;
        if (!p) return ruby_popen_writer(argv, pid);
    }
    else if (*template) {
        expand_report_argument(&template, &values, buf, size, false);
        return fopen(buf, "w");
    }
    return NULL;
}

static const char *crash_report;

/* SIGSEGV handler might have a very small stack. Thus we need to use it carefully. */
#define REPORT_BUG_BUFSIZ 256
static FILE *
bug_report_file(const char *file, int line, rb_pid_t *pid)
{
    char buf[REPORT_BUG_BUFSIZ];
    const char *report = crash_report;
    if (!report) report = getenv("RUBY_CRASH_REPORT");
    FILE *out = open_report_path(report, buf, sizeof(buf), pid);
    int len = err_position_0(buf, sizeof(buf), file, line);

    if (out) {
        if ((ssize_t)fwrite(buf, 1, len, out) == (ssize_t)len) return out;
        fclose(out);
    }
    if ((ssize_t)fwrite(buf, 1, len, stderr) == (ssize_t)len) {
        return stderr;
    }
    if ((ssize_t)fwrite(buf, 1, len, stdout) == (ssize_t)len) {
        return stdout;
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

#undef CRASH_REPORTER_MAY_BE_CREATED
#if defined(__APPLE__) && \
    (!defined(MAC_OS_X_VERSION_10_6) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6 || defined(__POWERPC__)) /* 10.6 PPC case */
# define CRASH_REPORTER_MAY_BE_CREATED
#endif
static void
preface_dump(FILE *out)
{
#if defined __APPLE__
    static const char msg[] = ""
        "-- Crash Report log information "
        "--------------------------------------------\n"
        "   See Crash Report log file in one of the following locations:\n"
# ifdef CRASH_REPORTER_MAY_BE_CREATED
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
# ifdef CRASH_REPORTER_MAY_BE_CREATED
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

RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 2, 0)
static void
bug_report_begin_valist(FILE *out, const char *fmt, va_list args)
{
    char buf[REPORT_BUG_BUFSIZ];

    fputs("[BUG] ", out);
    vsnprintf(buf, sizeof(buf), fmt, args);
    fputs(buf, out);
    snprintf(buf, sizeof(buf), "\n%s\n\n", rb_dynamic_description);
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
bug_report_end(FILE *out, rb_pid_t pid)
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
    finish_report(out, pid);
}

#define report_bug(file, line, fmt, ctx) do { \
    rb_pid_t pid = -1; \
    FILE *out = bug_report_file(file, line, &pid); \
    if (out) { \
        bug_report_begin(out, fmt); \
        rb_vm_bugreport(ctx, out); \
        bug_report_end(out, pid); \
    } \
} while (0) \

#define report_bug_valist(file, line, fmt, ctx, args) do { \
    rb_pid_t pid = -1; \
    FILE *out = bug_report_file(file, line, &pid); \
    if (out) { \
        bug_report_begin_valist(out, fmt, args); \
        rb_vm_bugreport(ctx, out); \
        bug_report_end(out, pid); \
    } \
} while (0) \

void
ruby_set_crash_report(const char *template)
{
    crash_report = template;
#if RUBY_DEBUG
    rb_pid_t pid = -1;
    char buf[REPORT_BUG_BUFSIZ];
    FILE *out = open_report_path(template, buf, sizeof(buf), &pid);
    if (out) {
        time_t t = time(NULL);
        fprintf(out, "ruby_test_bug_report: %s", ctime(&t));
        finish_report(out, pid);
    }
#endif
}

NORETURN(static void die(void));
static void
die(void)
{
#if defined(_WIN32) && defined(RUBY_MSVCRT_VERSION) && RUBY_MSVCRT_VERSION >= 80
    _set_abort_behavior( 0, _CALL_REPORTFAULT);
#endif

    abort();
}

RBIMPL_ATTR_FORMAT(RBIMPL_PRINTF_FORMAT, 1, 0)
void
rb_bug_without_die(const char *fmt, va_list args)
{
    const char *file = NULL;
    int line = 0;

#if USE_MMTK
    if (rb_mmtk_enabled_p() && rb_mmtk_is_mmtk_worker()) {
        file = NULL;
    } else
#endif
    if (GET_EC()) {
        file = rb_source_location_cstr(&line);
    }

    report_bug_valist(file, line, fmt, NULL, args);
}

void
rb_bug(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    rb_bug_without_die(fmt, args);
    va_end(args);
    die();
}

void
rb_bug_for_fatal_signal(ruby_sighandler_t default_sighandler, int sig, const void *ctx, const char *fmt, ...)
{
    const char *file = NULL;
    int line = 0;

#ifdef USE_MMTK
    // When using MMTk, this function may be called from GC worker threads,
    // in which case there will not be a Ruby execution context.
    if (rb_current_execution_context(!rb_mmtk_enabled_p())) {
#else
    if (GET_EC()) {
#endif
        file = rb_source_location_cstr(&line);
    }

    report_bug(file, line, fmt, ctx);

    if (default_sighandler) default_sighandler(sig);

    ruby_default_signal(sig);
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
    write_or_abort(2, rb_dynamic_description, strlen(rb_dynamic_description));
    abort();
}

void
rb_report_bug_valist(VALUE file, int line, const char *fmt, va_list args)
{
    report_bug_valist(RSTRING_PTR(file), line, fmt, NULL, args);
}

void
rb_assert_failure(const char *file, int line, const char *name, const char *expr)
{
    rb_assert_failure_detail(file, line, name, expr, NULL);
}

void
rb_assert_failure_detail(const char *file, int line, const char *name, const char *expr,
                         const char *fmt, ...)
{
    FILE *out = stderr;
    fprintf(out, "Assertion Failed: %s:%d:", file, line);
    if (name) fprintf(out, "%s:", name);
    fprintf(out, "%s\n%s\n\n", expr, rb_dynamic_description);

    if (fmt && *fmt) {
        va_list args;
        va_start(args, fmt);
        vfprintf(out, fmt, args);
        va_end(args);
    }

    preface_dump(out);
    rb_vm_bugreport(NULL, out);
    bug_report_end(out, -1);
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
    "<Memo>",			/* internal use: general memo */
    "<Node>",			/* internal use: syntax tree node */
    "<iClass>", 		/* internal use: mixed-in module holder */
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

COLDFUNC NORETURN(static void unexpected_type(VALUE, int, int));
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

    if (RB_UNLIKELY(UNDEF_P(x))) {
        rb_bug(UNDEF_LEAKED);
    }

    xt = TYPE(x);
    if (xt != t || (xt == T_DATA && rbimpl_rtypeddata_p(x))) {
        /*
         * Typed data is not simple `T_DATA`, but in a sense an
         * extension of `struct RVALUE`, which are incompatible with
         * each other except when inherited.
         *
         * So it is not enough to just check `T_DATA`, it must be
         * identified by its `type` using `Check_TypedStruct` instead.
         */
        unexpected_type(x, xt, t);
    }
}

void
rb_unexpected_type(VALUE x, int t)
{
    if (RB_UNLIKELY(UNDEF_P(x))) {
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
        return RTYPEDDATA_GET_DATA(obj);
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
VALUE rb_eNoMatchingPatternKeyError;

VALUE rb_eScriptError;
VALUE rb_eSyntaxError;
VALUE rb_eLoadError;

VALUE rb_eSystemCallError;
VALUE rb_mErrno;
static VALUE rb_eNOERROR;

ID ruby_static_id_cause;
#define id_cause ruby_static_id_cause
static ID id_message, id_detailed_message, id_backtrace;
static ID id_key, id_matchee, id_args, id_Errno, id_errno, id_i_path;
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
    rb_yjit_lazy_push_frame(GET_EC()->cfp->pc);
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
void rb_error_write(VALUE errinfo, VALUE emesg, VALUE errat, VALUE str, VALUE opt, VALUE highlight, VALUE reverse);

VALUE
rb_get_message(VALUE exc)
{
    VALUE e = rb_check_funcall(exc, id_message, 0, 0);
    if (UNDEF_P(e)) return Qnil;
    if (!RB_TYPE_P(e, T_STRING)) e = rb_check_string_type(e);
    return e;
}

VALUE
rb_get_detailed_message(VALUE exc, VALUE opt)
{
    VALUE e;
    if (NIL_P(opt)) {
        e = rb_check_funcall(exc, id_detailed_message, 0, 0);
    }
    else {
        e = rb_check_funcall_kw(exc, id_detailed_message, 1, &opt, 1);
    }
    if (UNDEF_P(e)) return Qnil;
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
    return RBOOL(rb_stderr_tty_p());
}

static VALUE
check_highlight_keyword(VALUE opt, int auto_tty_detect)
{
    VALUE highlight = Qnil;

    if (!NIL_P(opt)) {
        highlight = rb_hash_lookup(opt, sym_highlight);

        switch (highlight) {
          default:
            rb_bool_expected(highlight, "highlight", TRUE);
            UNREACHABLE;
          case Qtrue: case Qfalse: case Qnil: break;
        }
    }

    if (NIL_P(highlight)) {
        highlight = RBOOL(auto_tty_detect && rb_stderr_tty_p());
    }

    return highlight;
}

static VALUE
check_order_keyword(VALUE opt)
{
    VALUE order = Qnil;

    if (!NIL_P(opt)) {
        static VALUE kw_order;
        if (!kw_order) kw_order = ID2SYM(rb_intern_const("order"));

        order = rb_hash_lookup(opt, kw_order);

        if (order != Qnil) {
            ID id = rb_check_id(&order);
            if (id == id_bottom) order = Qtrue;
            else if (id == id_top) order = Qfalse;
            else {
                rb_raise(rb_eArgError, "expected :top or :bottom as "
                        "order: %+"PRIsVALUE, order);
            }
        }
    }

    if (NIL_P(order)) order = Qfalse;

    return order;
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
    VALUE highlight, order;

    rb_scan_args(argc, argv, "0:", &opt);

    highlight = check_highlight_keyword(opt, 1);
    order = check_order_keyword(opt);

    {
        if (NIL_P(opt)) opt = rb_hash_new();
        rb_hash_aset(opt, sym_highlight, highlight);
    }

    str = rb_str_new2("");
    errat = rb_get_backtrace(exc);
    emesg = rb_get_detailed_message(exc, opt);

    rb_error_write(exc, emesg, errat, str, opt, highlight, order);
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
 *   exception.detailed_message(highlight: bool, **opt)   ->  string
 *
 * Processes a string returned by #message.
 *
 * It may add the class name of the exception to the end of the first line.
 * Also, when +highlight+ keyword is true, it adds ANSI escape sequences to
 * make the message bold.
 *
 * If you override this method, it must be tolerant for unknown keyword
 * arguments. All keyword arguments passed to #full_message are delegated
 * to this method.
 *
 * This method is overridden by did_you_mean and error_highlight to add
 * their information.
 *
 * A user-defined exception class can also define their own
 * +detailed_message+ method to add supplemental information.
 * When +highlight+ is true, it can return a string containing escape
 * sequences, but use widely-supported ones. It is recommended to limit
 * the following codes:
 *
 * - Reset (+\e[0m+)
 * - Bold (+\e[1m+)
 * - Underline (+\e[4m+)
 * - Foreground color except white and black
 *   - Red (+\e[31m+)
 *   - Green (+\e[32m+)
 *   - Yellow (+\e[33m+)
 *   - Blue (+\e[34m+)
 *   - Magenta (+\e[35m+)
 *   - Cyan (+\e[36m+)
 *
 * Use escape sequences carefully even if +highlight+ is true.
 * Do not use escape sequences to express essential information;
 * the message should be readable even if all escape sequences are
 * ignored.
 */

static VALUE
exc_detailed_message(int argc, VALUE *argv, VALUE exc)
{
    VALUE opt;

    rb_scan_args(argc, argv, "0:", &opt);

    VALUE highlight = check_highlight_keyword(opt, 0);

    extern VALUE rb_decorate_message(const VALUE eclass, VALUE emesg, int highlight);

    return rb_decorate_message(CLASS_OF(exc), rb_get_message(exc), RTEST(highlight));
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

    if (RTEST(rb_str_include(exc, rb_str_new2("\n")))) {
        rb_str_catf(str, ":%+"PRIsVALUE, exc);
    }
    else {
        rb_str_buf_cat(str, ": ", 2);
        rb_str_buf_append(str, exc);
    }

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
        if (state || UNDEF_P(obj)) {
            rb_set_errinfo(Qnil);
            return Qfalse;
        }
        if (rb_obj_class(exc) != rb_obj_class(obj)) return Qfalse;
        mesg = rb_check_funcall(obj, id_message, 0, 0);
        if (UNDEF_P(mesg)) return Qfalse;
        backtrace = rb_check_funcall(obj, id_backtrace, 0, 0);
        if (UNDEF_P(backtrace)) return Qfalse;
    }
    else {
        mesg = rb_attr_get(obj, id_mesg);
        backtrace = exc_backtrace(obj);
    }

    if (!rb_equal(rb_attr_get(exc, id_mesg), mesg))
        return Qfalse;
    return rb_equal(exc_backtrace(exc), backtrace);
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
    return RBOOL(WIFEXITED(status) && WEXITSTATUS(status) == EXIT_SUCCESS);
}

static VALUE
err_init_recv(VALUE exc, VALUE recv)
{
    if (!UNDEF_P(recv)) rb_ivar_set(exc, id_recv, recv);
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
    if (cfp && VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_DUMMY) {
        rb_ivar_set(exc, id_iseq, rb_iseqw_new(cfp->iseq));
    }
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
    rb_ivar_set(exc, id_private_call_p, RBOOL(priv));
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

typedef struct name_error_message_struct {
    VALUE mesg;
    VALUE recv;
    VALUE name;
} name_error_message_t;

static void
name_err_mesg_mark(void *p)
{
    name_error_message_t *ptr = (name_error_message_t *)p;
    rb_gc_mark_movable(ptr->mesg);
    rb_gc_mark_movable(ptr->recv);
    rb_gc_mark_movable(ptr->name);
}

static void
name_err_mesg_update(void *p)
{
    name_error_message_t *ptr = (name_error_message_t *)p;
    ptr->mesg = rb_gc_location(ptr->mesg);
    ptr->recv = rb_gc_location(ptr->recv);
    ptr->name = rb_gc_location(ptr->name);
}

static const rb_data_type_t name_err_mesg_data_type = {
    "name_err_mesg",
    {
        name_err_mesg_mark,
        RUBY_TYPED_DEFAULT_FREE,
        NULL, // No external memory to report,
        name_err_mesg_update,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

/* :nodoc: */
static VALUE
rb_name_err_mesg_init(VALUE klass, VALUE mesg, VALUE recv, VALUE name)
{
    name_error_message_t *message;
    VALUE result = TypedData_Make_Struct(klass, name_error_message_t, &name_err_mesg_data_type, message);
    RB_OBJ_WRITE(result, &message->mesg, mesg);
    RB_OBJ_WRITE(result, &message->recv, recv);
    RB_OBJ_WRITE(result, &message->name, name);
    return result;
}

/* :nodoc: */
static VALUE
rb_name_err_mesg_new(VALUE mesg, VALUE recv, VALUE method)
{
    return rb_name_err_mesg_init(rb_cNameErrorMesg, mesg, recv, method);
}

/* :nodoc: */
static VALUE
name_err_mesg_alloc(VALUE klass)
{
    return rb_name_err_mesg_init(klass, Qnil, Qnil, Qnil);
}

/* :nodoc: */
static VALUE
name_err_mesg_init_copy(VALUE obj1, VALUE obj2)
{
    if (obj1 == obj2) return obj1;
    rb_obj_init_copy(obj1, obj2);

    name_error_message_t *ptr1, *ptr2;
    TypedData_Get_Struct(obj1, name_error_message_t, &name_err_mesg_data_type, ptr1);
    TypedData_Get_Struct(obj2, name_error_message_t, &name_err_mesg_data_type, ptr2);

    RB_OBJ_WRITE(obj1, &ptr1->mesg, ptr2->mesg);
    RB_OBJ_WRITE(obj1, &ptr1->recv, ptr2->recv);
    RB_OBJ_WRITE(obj1, &ptr1->name, ptr2->name);
    return obj1;
}

/* :nodoc: */
static VALUE
name_err_mesg_equal(VALUE obj1, VALUE obj2)
{
    if (obj1 == obj2) return Qtrue;

    if (rb_obj_class(obj2) != rb_cNameErrorMesg)
        return Qfalse;

    name_error_message_t *ptr1, *ptr2;
    TypedData_Get_Struct(obj1, name_error_message_t, &name_err_mesg_data_type, ptr1);
    TypedData_Get_Struct(obj2, name_error_message_t, &name_err_mesg_data_type, ptr2);

    if (!rb_equal(ptr1->mesg, ptr2->mesg)) return Qfalse;
    if (!rb_equal(ptr1->recv, ptr2->recv)) return Qfalse;
    if (!rb_equal(ptr1->name, ptr2->name)) return Qfalse;
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
    name_error_message_t *ptr;
    TypedData_Get_Struct(obj, name_error_message_t, &name_err_mesg_data_type, ptr);

    VALUE mesg = ptr->mesg;
    if (NIL_P(mesg)) return Qnil;
    else {
        struct RString s_str, c_str, d_str;
        VALUE c, s, d = 0, args[4], c2;
        int state = 0;
        rb_encoding *usascii = rb_usascii_encoding();

#define FAKE_CSTR(v, str) rb_setup_fake_str((v), (str), rb_strlen_lit(str), usascii)
        c = s = FAKE_CSTR(&s_str, "");
        obj = ptr->recv;
        switch (obj) {
          case Qnil:
            c = d = FAKE_CSTR(&d_str, "nil");
            break;
          case Qtrue:
            c = d = FAKE_CSTR(&d_str, "true");
            break;
          case Qfalse:
            c = d = FAKE_CSTR(&d_str, "false");
            break;
          default:
            if (strstr(RSTRING_PTR(mesg), "%2$s")) {
                d = rb_protect(name_err_mesg_receiver_name, obj, &state);
                if (state || NIL_OR_UNDEF_P(d))
                    d = rb_protect(rb_inspect, obj, &state);
                if (state) {
                    rb_set_errinfo(Qnil);
                }
                d = rb_check_string_type(d);
                if (NIL_P(d)) {
                    d = rb_any_to_s(obj);
                }
            }

            if (!RB_SPECIAL_CONST_P(obj)) {
                switch (RB_BUILTIN_TYPE(obj)) {
                  case T_MODULE:
                    s = FAKE_CSTR(&s_str, "module ");
                    c = obj;
                    break;
                  case T_CLASS:
                    s = FAKE_CSTR(&s_str, "class ");
                    c = obj;
                    break;
                  default:
                    goto object;
                }
            }
            else {
                VALUE klass;
              object:
                klass = CLASS_OF(obj);
                if (RB_TYPE_P(klass, T_CLASS) && RCLASS_SINGLETON_P(klass)) {
                    s = FAKE_CSTR(&s_str, "");
                    if (obj == rb_vm_top_self()) {
                        c = FAKE_CSTR(&c_str, "main");
                    }
                    else {
                        c = rb_any_to_s(obj);
                    }
                    break;
                }
                else {
                    s = FAKE_CSTR(&s_str, "an instance of ");
                    c = rb_class_real(klass);
                }
            }
            c2 = rb_protect(name_err_mesg_receiver_name, c, &state);
            if (state || NIL_OR_UNDEF_P(c2))
                c2 = rb_protect(rb_inspect, c, &state);
            if (state) {
                rb_set_errinfo(Qnil);
            }
            c2 = rb_check_string_type(c2);
            if (NIL_P(c2)) {
                c2 = rb_any_to_s(c);
            }
            c = c2;
            break;
        }
        args[0] = rb_obj_as_string(ptr->name);
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
    VALUE recv = rb_ivar_lookup(self, id_recv, Qundef);
    if (!UNDEF_P(recv)) return recv;

    VALUE mesg = rb_attr_get(self, id_mesg);
    if (!rb_typeddata_is_kind_of(mesg, &name_err_mesg_data_type)) {
        rb_raise(rb_eArgError, "no receiver is available");
    }

    name_error_message_t *ptr;
    TypedData_Get_Struct(mesg, name_error_message_t, &name_err_mesg_data_type, ptr);
    return ptr->recv;
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
    if (!UNDEF_P(recv)) return recv;
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
    if (!UNDEF_P(key)) return key;
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
            if (!UNDEF_P(values[i])) {
                rb_ivar_set(self, keywords[i], values[i]);
            }
        }
    }

    return self;
}

/*
 * call-seq:
 *   no_matching_pattern_key_error.matchee  -> object
 *
 * Return the matchee associated with this NoMatchingPatternKeyError exception.
 */

static VALUE
no_matching_pattern_key_err_matchee(VALUE self)
{
    VALUE matchee;

    matchee = rb_ivar_lookup(self, id_matchee, Qundef);
    if (!UNDEF_P(matchee)) return matchee;
    rb_raise(rb_eArgError, "no matchee is available");
}

/*
 * call-seq:
 *   no_matching_pattern_key_error.key  -> object
 *
 * Return the key caused this NoMatchingPatternKeyError exception.
 */

static VALUE
no_matching_pattern_key_err_key(VALUE self)
{
    VALUE key;

    key = rb_ivar_lookup(self, id_key, Qundef);
    if (!UNDEF_P(key)) return key;
    rb_raise(rb_eArgError, "no key is available");
}

/*
 * call-seq:
 *   NoMatchingPatternKeyError.new(message=nil, matchee: nil, key: nil) -> no_matching_pattern_key_error
 *
 * Construct a new +NoMatchingPatternKeyError+ exception with the given message,
 * matchee and key.
 */

static VALUE
no_matching_pattern_key_err_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE options;

    rb_call_super(rb_scan_args(argc, argv, "01:", NULL, &options), argv);

    if (!NIL_P(options)) {
        ID keywords[2];
        VALUE values[numberof(keywords)];
        int i;
        keywords[0] = id_matchee;
        keywords[1] = id_key;
        rb_get_kwargs(options, keywords, 0, numberof(values), values);
        for (i = 0; i < numberof(values); ++i) {
            if (!UNDEF_P(values[i])) {
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

static VALUE
syntax_error_with_path(VALUE exc, VALUE path, VALUE *mesg, rb_encoding *enc)
{
    if (NIL_P(exc)) {
        *mesg = rb_enc_str_new(0, 0, enc);
        exc = rb_class_new_instance(1, mesg, rb_eSyntaxError);
        rb_ivar_set(exc, id_i_path, path);
    }
    else {
        if (rb_attr_get(exc, id_i_path) != path) {
            rb_raise(rb_eArgError, "SyntaxError#path changed");
        }
        VALUE s = *mesg = rb_attr_get(exc, idMesg);
        if (RSTRING_LEN(s) > 0 && *(RSTRING_END(s)-1) != '\n')
            rb_str_cat_cstr(s, "\n");
    }
    return exc;
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

void
rb_free_warning(void)
{
    st_free_table(warning_categories.id2enum);
    st_free_table(warning_categories.enum2id);
    st_free_table(syserr_tbl);
}

static VALUE
setup_syserr(int n, const char *name)
{
    VALUE error = rb_define_class_under(rb_mErrno, name, rb_eSystemCallError);

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
    st_add_direct(syserr_tbl, n, (st_data_t)error);
    return error;
}

static VALUE
set_syserr(int n, const char *name)
{
    st_data_t error;

    if (!st_lookup(syserr_tbl, n, &error)) {
        return setup_syserr(n, name);
    }
    else {
        VALUE errclass = (VALUE)error;
        rb_define_const(rb_mErrno, name, errclass);
        return errclass;
    }
}

static VALUE
get_syserr(int n)
{
    st_data_t error;

    if (!st_lookup(syserr_tbl, n, &error)) {
        char name[DECIMAL_SIZE_OF(n) + sizeof("E-")];

        snprintf(name, sizeof(name), "E%03d", n);
        return setup_syserr(n, name);
    }
    return (VALUE)error;
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
    return RBOOL(FIXNUM_P(num) ? num == e : rb_equal(num, e));
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
 *     NoMethodError: undefined method `to_ary' for an instance of String
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
 * +fatal+ is an Exception that is raised when Ruby has encountered a fatal
 * error and must exit.
 */

/*
 * Document-class: NameError::message
 * :nodoc:
 */

/*
 *  Document-class: Exception
 *
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
ivar_copy_i(ID key, VALUE val, st_data_t exc)
{
    rb_ivar_set((VALUE)exc, key, val);
    return ST_CONTINUE;
}

void rb_exc_check_circular_cause(VALUE exc);

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

    rb_exc_check_circular_cause(exc);

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
    rb_define_method(rb_eException, "detailed_message", exc_detailed_message, -1);
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

    /* RDoc will use literal name value while parsing rb_attr,
    *  and will render `idPath` as an attribute name without this trick */
    ID path = idPath;

    /* the path failed to parse */
    rb_attr(rb_eSyntaxError, path, TRUE, FALSE, FALSE);

    rb_eLoadError   = rb_define_class("LoadError", rb_eScriptError);
    /* the path failed to load */
    rb_attr(rb_eLoadError, path, TRUE, FALSE, FALSE);

    rb_eNotImpError = rb_define_class("NotImplementedError", rb_eScriptError);

    rb_eNameError     = rb_define_class("NameError", rb_eStandardError);
    rb_define_method(rb_eNameError, "initialize", name_err_initialize, -1);
    rb_define_method(rb_eNameError, "name", name_err_name, 0);
    rb_define_method(rb_eNameError, "receiver", name_err_receiver, 0);
    rb_define_method(rb_eNameError, "local_variables", name_err_local_variables, 0);
    rb_cNameErrorMesg = rb_define_class_under(rb_eNameError, "message", rb_cObject);
    rb_define_alloc_func(rb_cNameErrorMesg, name_err_mesg_alloc);
    rb_define_method(rb_cNameErrorMesg, "initialize_copy", name_err_mesg_init_copy, 1);
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
    rb_eNoMatchingPatternError = rb_define_class("NoMatchingPatternError", rb_eStandardError);
    rb_eNoMatchingPatternKeyError = rb_define_class("NoMatchingPatternKeyError", rb_eNoMatchingPatternError);
    rb_define_method(rb_eNoMatchingPatternKeyError, "initialize", no_matching_pattern_key_err_initialize, -1);
    rb_define_method(rb_eNoMatchingPatternKeyError, "matchee", no_matching_pattern_key_err_matchee, 0);
    rb_define_method(rb_eNoMatchingPatternKeyError, "key", no_matching_pattern_key_err_key, 0);

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
    id_detailed_message = rb_intern_const("detailed_message");
    id_backtrace = rb_intern_const("backtrace");
    id_key = rb_intern_const("key");
    id_matchee = rb_intern_const("matchee");
    id_args = rb_intern_const("args");
    id_receiver = rb_intern_const("receiver");
    id_private_call_p = rb_intern_const("private_call?");
    id_local_variables = rb_intern_const("local_variables");
    id_Errno = rb_intern_const("Errno");
    id_errno = rb_intern_const("errno");
    id_i_path = rb_intern_const("@path");
    id_warn = rb_intern_const("warn");
    id_category = rb_intern_const("category");
    id_deprecated = rb_intern_const("deprecated");
    id_experimental = rb_intern_const("experimental");
    id_performance = rb_intern_const("performance");
    id_top = rb_intern_const("top");
    id_bottom = rb_intern_const("bottom");
    id_iseq = rb_make_internal_id();
    id_recv = rb_make_internal_id();

    sym_category = ID2SYM(id_category);
    sym_highlight = ID2SYM(rb_intern_const("highlight"));

    warning_categories.id2enum = rb_init_identtable();
    st_add_direct(warning_categories.id2enum, id_deprecated, RB_WARN_CATEGORY_DEPRECATED);
    st_add_direct(warning_categories.id2enum, id_experimental, RB_WARN_CATEGORY_EXPERIMENTAL);
    st_add_direct(warning_categories.id2enum, id_performance, RB_WARN_CATEGORY_PERFORMANCE);

    warning_categories.enum2id = rb_init_identtable();
    st_add_direct(warning_categories.enum2id, RB_WARN_CATEGORY_NONE, 0);
    st_add_direct(warning_categories.enum2id, RB_WARN_CATEGORY_DEPRECATED, id_deprecated);
    st_add_direct(warning_categories.enum2id, RB_WARN_CATEGORY_EXPERIMENTAL, id_experimental);
    st_add_direct(warning_categories.enum2id, RB_WARN_CATEGORY_PERFORMANCE, id_performance);
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
        rb_print_backtrace(stderr);
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

#undef rb_sys_fail
void
rb_sys_fail(const char *mesg)
{
    rb_exc_raise(make_errno_exc(mesg));
}

#undef rb_sys_fail_str
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

NORETURN(static void rb_mod_exc_raise(VALUE exc, VALUE mod));

static void
rb_mod_exc_raise(VALUE exc, VALUE mod)
{
    rb_extend_object(exc, mod);
    rb_exc_raise(exc);
}

void
rb_mod_sys_fail(VALUE mod, const char *mesg)
{
    VALUE exc = make_errno_exc(mesg);
    rb_mod_exc_raise(exc, mod);
}

void
rb_mod_sys_fail_str(VALUE mod, VALUE mesg)
{
    VALUE exc = make_errno_exc_str(mesg);
    rb_mod_exc_raise(exc, mod);
}

void
rb_mod_syserr_fail(VALUE mod, int e, const char *mesg)
{
    VALUE exc = rb_syserr_new(e, mesg);
    rb_mod_exc_raise(exc, mod);
}

void
rb_mod_syserr_fail_str(VALUE mod, int e, VALUE mesg)
{
    VALUE exc = rb_syserr_new_str(e, mesg);
    rb_mod_exc_raise(exc, mod);
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
    rb_yjit_lazy_push_frame(GET_EC()->cfp->pc);
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
rb_check_copyable(VALUE obj, VALUE orig)
{
    if (!FL_ABLE(obj)) return;
    rb_check_frozen_internal(obj);
    if (!FL_ABLE(orig)) return;
}

void
Init_syserr(void)
{
    rb_eNOERROR = setup_syserr(0, "NOERROR");
#if 0
    /* No error */
    rb_define_const(rb_mErrno, "NOERROR", rb_eNOERROR);
#endif
#define defined_error(name, num) set_syserr((num), (name));
#define undefined_error(name) rb_define_const(rb_mErrno, (name), rb_eNOERROR);
#include "known_errors.inc"
#undef defined_error
#undef undefined_error
}

#include "warning.rbinc"

/*!
 * \}
 */
