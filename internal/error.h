#ifndef INTERNAL_ERROR_H /* -*- C -*- */
#define INTERNAL_ERROR_H
/**
 * @file
 * @brief      Internal header for Exception.
 * @author     \@shyouhei
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */

/* error.c */
extern VALUE rb_eEAGAIN;
extern VALUE rb_eEWOULDBLOCK;
extern VALUE rb_eEINPROGRESS;
void rb_report_bug_valist(VALUE file, int line, const char *fmt, va_list args);
NORETURN(void rb_async_bug_errno(const char *,int));
const char *rb_builtin_type_name(int t);
const char *rb_builtin_class_name(VALUE x);
PRINTF_ARGS(void rb_warn_deprecated(const char *fmt, const char *suggest, ...), 1, 3);
#ifdef RUBY_ENCODING_H
VALUE rb_syntax_error_append(VALUE, VALUE, int, int, rb_encoding*, const char*, va_list);
PRINTF_ARGS(void rb_enc_warn(rb_encoding *enc, const char *fmt, ...), 2, 3);
PRINTF_ARGS(void rb_sys_enc_warning(rb_encoding *enc, const char *fmt, ...), 2, 3);
PRINTF_ARGS(void rb_syserr_enc_warning(int err, rb_encoding *enc, const char *fmt, ...), 3, 4);
#endif

typedef enum {
    RB_WARN_CATEGORY_NONE,
    RB_WARN_CATEGORY_DEPRECATED,
    RB_WARN_CATEGORY_EXPERIMENTAL,
} rb_warning_category_t;
rb_warning_category_t rb_warning_category_from_name(VALUE category);
bool rb_warning_category_enabled_p(rb_warning_category_t category);

#define rb_raise_cstr(etype, mesg) \
    rb_exc_raise(rb_exc_new_str(etype, rb_str_new_cstr(mesg)))
#define rb_raise_static(etype, mesg) \
    rb_exc_raise(rb_exc_new_str(etype, rb_str_new_static(mesg, rb_strlen_lit(mesg))))

VALUE rb_name_err_new(VALUE mesg, VALUE recv, VALUE method);
#define rb_name_err_raise_str(mesg, recv, name) \
    rb_exc_raise(rb_name_err_new(mesg, recv, name))
#define rb_name_err_raise(mesg, recv, name) \
    rb_name_err_raise_str(rb_fstring_cstr(mesg), (recv), (name))
VALUE rb_nomethod_err_new(VALUE mesg, VALUE recv, VALUE method, VALUE args, int priv);
VALUE rb_key_err_new(VALUE mesg, VALUE recv, VALUE name);
#define rb_key_err_raise(mesg, recv, name) \
    rb_exc_raise(rb_key_err_new(mesg, recv, name))
PRINTF_ARGS(VALUE rb_warning_string(const char *fmt, ...), 1, 2);
NORETURN(void rb_vraise(VALUE, const char *, va_list));

RUBY_SYMBOL_EXPORT_BEGIN
/* error.c (export) */
int rb_bug_reporter_add(void (*func)(FILE *, void *), void *data);
NORETURN(void rb_unexpected_type(VALUE,int));
#undef Check_Type
#define Check_Type(v, t) \
    (!RB_TYPE_P((VALUE)(v), (t)) || \
     ((t) == RUBY_T_DATA && RTYPEDDATA_P(v)) ? \
     rb_unexpected_type((VALUE)(v), (t)) : (void)0)

static inline int
rb_typeddata_is_instance_of_inline(VALUE obj, const rb_data_type_t *data_type)
{
    return RB_TYPE_P(obj, T_DATA) && RTYPEDDATA_P(obj) && (RTYPEDDATA_TYPE(obj) == data_type);
}
#define rb_typeddata_is_instance_of rb_typeddata_is_instance_of_inline
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_ERROR_H */
