#ifndef INTERNAL_ERROR_H                                 /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_ERROR_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Internal header for Exception.
 */
#include "ruby/internal/config.h"
#include <stdarg.h>             /* for va_list */
#include "internal/string.h"    /* for rb_fstring_cstr */
#include "ruby/internal/stdbool.h"     /* for bool */
#include "ruby/encoding.h"      /* for rb_encoding */
#include "ruby/intern.h"        /* for rb_exc_raise */
#include "ruby/ruby.h"          /* for enum ruby_value_type */

#ifdef Check_Type
# undef Check_Type               /* in ruby/ruby.h */
#endif

#ifdef rb_raise_static
# undef rb_raise_static
# undef rb_sys_fail_path
# undef rb_syserr_fail_path
#endif

#define rb_raise_static(e, m) \
    rb_raise_cstr_i((e), rb_str_new_static((m), rb_strlen_lit(m)))
#ifdef RUBY_FUNCTION_NAME_STRING
# define rb_sys_fail_path(path) rb_sys_fail_path_in(RUBY_FUNCTION_NAME_STRING, path)
# define rb_syserr_fail_path(err, path) rb_syserr_fail_path_in(RUBY_FUNCTION_NAME_STRING, (err), (path))
# define rb_syserr_new_path(err, path) rb_syserr_new_path_in(RUBY_FUNCTION_NAME_STRING, (err), (path))
#else
# define rb_sys_fail_path(path) rb_sys_fail_str(path)
# define rb_syserr_fail_path(err, path) rb_syserr_fail_str((err), (path))
# define rb_syserr_new_path(err, path) rb_syserr_new_str((err), (path))
#endif

/* error.c */
extern long rb_backtrace_length_limit;
extern VALUE rb_eEAGAIN;
extern VALUE rb_eEWOULDBLOCK;
extern VALUE rb_eEINPROGRESS;
void rb_report_bug_valist(VALUE file, int line, const char *fmt, va_list args);
NORETURN(void rb_async_bug_errno(const char *,int));
const char *rb_builtin_type_name(int t);
const char *rb_builtin_class_name(VALUE x);
PRINTF_ARGS(void rb_warn_deprecated(const char *fmt, const char *suggest, ...), 1, 3);
PRINTF_ARGS(void rb_warn_deprecated_to_remove(const char *fmt, const char *removal, ...), 1, 3);
VALUE rb_syntax_error_append(VALUE, VALUE, int, int, rb_encoding*, const char*, va_list);
PRINTF_ARGS(void rb_enc_warn(rb_encoding *enc, const char *fmt, ...), 2, 3);
PRINTF_ARGS(void rb_sys_enc_warning(rb_encoding *enc, const char *fmt, ...), 2, 3);
PRINTF_ARGS(void rb_syserr_enc_warning(int err, rb_encoding *enc, const char *fmt, ...), 3, 4);
rb_warning_category_t rb_warning_category_from_name(VALUE category);
bool rb_warning_category_enabled_p(rb_warning_category_t category);
VALUE rb_name_err_new(VALUE mesg, VALUE recv, VALUE method);
VALUE rb_nomethod_err_new(VALUE mesg, VALUE recv, VALUE method, VALUE args, int priv);
VALUE rb_key_err_new(VALUE mesg, VALUE recv, VALUE name);
PRINTF_ARGS(VALUE rb_warning_string(const char *fmt, ...), 1, 2);
NORETURN(void rb_vraise(VALUE, const char *, va_list));
NORETURN(static inline void rb_raise_cstr(VALUE etype, const char *mesg));
NORETURN(static inline void rb_raise_cstr_i(VALUE etype, VALUE mesg));
NORETURN(static inline void rb_name_err_raise_str(VALUE mesg, VALUE recv, VALUE name));
NORETURN(static inline void rb_name_err_raise(const char *mesg, VALUE recv, VALUE name));
NORETURN(static inline void rb_key_err_raise(VALUE mesg, VALUE recv, VALUE name));
static inline void Check_Type(VALUE v, enum ruby_value_type t);
static inline bool rb_typeddata_is_instance_of_inline(VALUE obj, const rb_data_type_t *data_type);
#define rb_typeddata_is_instance_of rb_typeddata_is_instance_of_inline

RUBY_SYMBOL_EXPORT_BEGIN
/* error.c (export) */
int rb_bug_reporter_add(void (*func)(FILE *, void *), void *data);
#ifdef RUBY_FUNCTION_NAME_STRING
NORETURN(void rb_sys_fail_path_in(const char *func_name, VALUE path));
NORETURN(void rb_syserr_fail_path_in(const char *func_name, int err, VALUE path));
VALUE rb_syserr_new_path_in(const char *func_name, int n, VALUE path);
#endif
RUBY_SYMBOL_EXPORT_END

static inline void
rb_raise_cstr_i(VALUE etype, VALUE mesg)
{
    VALUE exc = rb_exc_new_str(etype, mesg);
    rb_exc_raise(exc);
}

static inline void
rb_raise_cstr(VALUE etype, const char *mesg)
{
    VALUE str = rb_str_new_cstr(mesg);
    rb_raise_cstr_i(etype, str);
}

static inline void
rb_name_err_raise_str(VALUE mesg, VALUE recv, VALUE name)
{
    VALUE exc = rb_name_err_new(mesg, recv, name);
    rb_exc_raise(exc);
}

static inline void
rb_name_err_raise(const char *mesg, VALUE recv, VALUE name)
{
    VALUE str = rb_fstring_cstr(mesg);
    rb_name_err_raise_str(str, recv, name);
}

static inline void
rb_key_err_raise(VALUE mesg, VALUE recv, VALUE name)
{
    VALUE exc = rb_key_err_new(mesg, recv, name);
    rb_exc_raise(exc);
}

static inline bool
rb_typeddata_is_instance_of_inline(VALUE obj, const rb_data_type_t *data_type)
{
    return RB_TYPE_P(obj, T_DATA) && RTYPEDDATA_P(obj) && (RTYPEDDATA_TYPE(obj) == data_type);
}

#endif /* INTERNAL_ERROR_H */
